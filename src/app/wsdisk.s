# workspace edits on disk (v1.1.md workspace-edits, file-operations): files that are not open are
# read into hidden documents, edited there and written back atomically; the open documents an
# edit changes that had no unsaved changes are written with them. Every write is first recorded
# in a journal ($XDG_STATE_HOME/rhun/edits/tx-PID-ID: a plan and each file's bytes before and
# after), so a failure puts everything back, undo and redo work on closed files, and a crash in
# the middle is rolled back at the next start.
.include "rhun.inc"

.equ WS_FILE_MAX, 16777216      # a closed file read for a text group
.equ WS_READ_MAX, 67108864      # everything one edit reads and keeps

.bss
.p2align 3
wd_budget: .quad 0              # bytes read by the edit being made
wd_crash: .quad 0               # RHUN_TEST_EDIT_CRASH: exit after this many disk steps (tests)
wd_steps: .quad 0
.globl wd_slot
wd_slot: .quad 0                # the next journal slot
wd_restored: .quad 0            # recovery: files put back, files left as they were
wd_left: .quad 0
.globl wd_plan
wd_plan: .zero SB_SIZE          # the journal's plan being written
wd_path: .zero SB_SIZE          # a journal file's path
wd_sb: .zero SB_SIZE            # bytes to write, messages
wd_names: .zero SB_SIZE         # recovery: the journal folders found, NUL-separated
wd_real: .zero 4100             # a resolved path
wd_root: .zero 4100             # a resolved permission root

.text

# ---------------- helpers ----------------

# FN ws_fnv(ptr, len) -> rax the 64-bit FNV-1a hash of the bytes (the fnv1a64: precondition)
FN ws_fnv
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx edx, byte ptr [rdi + rcx]
    xor rax, rdx
    imul rax, r8
    inc rcx
    jmp 1b
2:  ret

# FN ws_doc_bytes(doc, sb): the document's text as it is written to its file, LF as CRLF when
# the file had CRLF line endings (as Save writes it)
FN ws_doc_bytes
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call sb_clear
    mov rdi, rbx
    call doc_len
    mov r13, rax
    mov rsi, rax
    cmp dword ptr [rbx + DOC_crlf], 0
    je 1f
    add rsi, rax
1:  mov rdi, r12
    call sb_reserve
    mov r14, rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    mov rcx, r14
    call doc_copy
    mov [r12 + SB_len], r13
    cmp dword ptr [rbx + DOC_crlf], 0
    je 9f
    # expand LF to CRLF from the back
    xor ecx, ecx
    xor edx, edx
2:  cmp rcx, r13
    jae 3f
    cmp byte ptr [r14 + rcx], 10
    jne 21f
    inc rdx
21: inc rcx
    jmp 2b
3:  lea r8, [r13 + rdx]
    mov [r12 + SB_len], r8
    mov rcx, r13
4:  test rcx, rcx
    jz 9f
    dec rcx
    dec r8
    movzx eax, byte ptr [r14 + rcx]
    mov [r14 + r8], al
    cmp al, 10
    jne 4b
    dec r8
    mov byte ptr [r14 + r8], 13
    jmp 4b
9:  EPILOGUE

# FN ws_file_hash(path) -> rax the FNV-1a hash of the file's bytes, edx 1; edx 0 when it cannot
# be read
FN ws_file_hash
    push rbx
    mov esi, WS_READ_MAX
    call vfs_read_limited
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    call ws_fnv
    push rax
    mov rdi, rbx
    call mem_free
    pop rax
    mov edx, 1
    pop rbx
    ret
8:  xor eax, eax
    xor edx, edx
    pop rbx
    ret

# FN ws_doc_written(doc): the document's file now holds its text: unmodified, the stamp the
# reload watcher compares, the saved event for extensions
FN ws_doc_written
    push rbx
    mov rbx, rdi
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rbx + DOC_savepoint], rax
    mov rdi, [rbx + DOC_path]
    call vfs_stamp
    mov [rbx + DOC_mtime], rax
    mov rdi, rbx
    call doc_note_eol
    and dword ptr [rbx + DOC_flags], ~DF_DISK_CHANGED
    mov qword ptr [rbx + DOC_disk_seen], 0
    inc qword ptr [rbx + DOC_saves]
    mov rdi, rbx
    call git_doc_saved
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# FN ws_inside(real cstr) -> eax 1 when the resolved path lies in the project or in the edit's
# extension's own state folder (where its disk changes may go)
FN ws_inside
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 1f
    lea rsi, [rip + wd_root]
    call ext_realpath
    test eax, eax
    jz 1f
    mov rdi, rbx
    lea rsi, [rip + wd_root]
    call app_path_inside
    test eax, eax
    jnz 9f
1:  mov rax, [rip + ws_ext]
    test rax, rax
    jz 8f
    mov rdi, [rax + EXT_state]
    test rdi, rdi
    jz 8f
    lea rsi, [rip + wd_root]
    call ext_realpath
    test eax, eax
    jz 8f
    mov rdi, rbx
    lea rsi, [rip + wd_root]
    call app_path_inside
    test eax, eax
    jnz 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# ---------------- before anything changes ----------------

# FN ws_disk_resolve() -> eax 1 with every text group's file that is not open read into a hidden
# document (a regular text file of at most 16 MiB in the project or the extension's state folder,
# hashing as its precondition says); 0 when one cannot be (ws_code says why)
FN ws_disk_resolve
    PROLOGUE
    mov qword ptr [rip + wd_budget], 0
    call ws_ops_resolve         # file operations first: text groups may name created files (wsops.s)
    test eax, eax
    jz .Lwr_fail
    xor ebx, ebx
.Lwr_next:
    cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lwr_ok
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne .Lwr_next
    cmp qword ptr [r12 + WG_doc], 0
    jne .Lwr_open
    mov rdi, r12
    call ws_ops_created         # a file an earlier create makes: an empty text (wsops.s)
    test eax, eax
    jnz .Lwr_next
    mov rdi, r12
    xor esi, esi
    call ws_path
    test eax, eax
    jz .Lwr_nofile
    lea rdi, [rip + ws_pathbuf]
    lea rsi, [rip + wd_real]
    call ext_realpath
    test eax, eax
    jz .Lwr_nofile              # missing
    lea rdi, [rip + wd_real]
    call ws_inside
    test eax, eax
    jz .Lwr_needs
    lea rdi, [rip + wd_real]
    call vfs_type
    cmp eax, 0x8000
    jne .Lwr_nofile
    # named twice under two spellings?
    xor r13d, r13d
1:  cmp r13, rbx
    jae 2f
    imul rax, r13, WG_SIZE
    add rax, [rip + wg_vec + VEC_ptr]
    inc r13
    cmp qword ptr [rax + WG_kind], WK_TEXT
    jne 1b
    mov rdi, [rax + WG_real]
    test rdi, rdi
    jz 1b
    lea rsi, [rip + wd_real]
    call strcmp_eq
    test eax, eax
    jnz .Lwr_twice
    jmp 1b
2:  lea rdi, [rip + wd_real]
    call dup_cstr
    mov [r12 + WG_real], rax
    lea rdi, [rip + wd_real]
    mov esi, WS_FILE_MAX
    call vfs_read_limited
    test rax, rax
    jz .Lwr_unreadable
    mov [r12 + WG_orig], rax
    mov [r12 + WG_olen], rdx
    add [rip + wd_budget], rdx
    cmp qword ptr [rip + wd_budget], WS_READ_MAX
    ja .Lwr_big
    mov rdi, rax
    mov rsi, rdx
    call doc_is_binary
    test eax, eax
    jnz .Lwr_nofile
    mov rdi, [r12 + WG_orig]
    mov rsi, [r12 + WG_olen]
    call ws_fnv
    mov [r12 + WG_before], rax
    cmp qword ptr [r12 + WG_pre], WP_HASH
    jne 3f
    cmp rax, [r12 + WG_hash]
    jne .Lwr_stale
3:  mov rdi, [r12 + WG_real]
    call vfs_stamp
    mov [r12 + WG_stamp], rax
    # the hidden document: the text as rhun keeps it (CR before LF dropped)
    call doc_new
    mov r13, rax
    mov [r12 + WG_doc], rax
    mov qword ptr [r12 + WG_hidden], 1
    mov rdi, [r12 + WG_orig]
    mov rsi, [r12 + WG_olen]
    call mem_dup
    mov r14, rax
    mov rdi, r13
    mov rsi, r14
    mov rdx, [r12 + WG_olen]
    call doc_normalize_eol
    mov rdi, r13
    mov rsi, r14
    mov rdx, rax
    call doc_replace_all
    mov rdi, r14
    call mem_free
    jmp .Lwr_next
.Lwr_open:
    # an open document: written too when the edit changes disk and it has no unsaved changes,
    # if its file is where the extension may write
    cmp qword ptr [r12 + WG_hidden], 0
    jne .Lwr_next
    mov rax, [r12 + WG_doc]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz .Lwr_next                # untitled
    lea rsi, [rip + wd_real]
    call ext_realpath
    test eax, eax
    jz .Lwr_next
    lea rdi, [rip + wd_real]
    call ws_inside
    test eax, eax
    jz .Lwr_next
    lea rdi, [rip + wd_real]
    call dup_cstr
    mov [r12 + WG_real], rax
    jmp .Lwr_next
.Lwr_ok:
    call ws_ops_textcheck       # text groups against the file operations' paths (wsops.s)
    EPILOGUE
.Lwr_fail:
    xor eax, eax
    EPILOGUE
.Lwr_nofile:
    lea rdi, [rip + .Lwc_nofile]
    lea rsi, [rip + .Lws_e_nofile]
    jmp .Lwr_err
.Lwr_unreadable:
    cmp rdx, -27                # EFBIG: over 16 MiB
    je .Lwr_big
    jmp .Lwr_nofile
.Lwr_needs:
    lea rdi, [rip + .Lwc_needs]
    lea rsi, [rip + .Lws_e_needs]
    jmp .Lwr_err
.Lwr_twice:
    lea rdi, [rip + .Lwc_twice]
    lea rsi, [rip + .Lws_e_bad]
    jmp .Lwr_err
.Lwr_stale:
    lea rdi, [rip + .Lwc_stale]
    lea rsi, [rip + .Lws_e_stale]
    jmp .Lwr_err
.Lwr_big:
    lea rdi, [rip + .Lwc_big]
    lea rsi, [rip + .Lws_e_big]
.Lwr_err:
    call ws_err
    xor eax, eax
    EPILOGUE

# FN ws_disk_hash_open(WG*) -> eax 1 when the open document's file hashes as its group's
# fnv1a64: precondition says (0 with ws_code: stale)
FN ws_disk_hash_open
    push rbx
    mov rbx, rdi
    mov rax, [rbx + WG_doc]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz 8f
    call ws_file_hash
    test edx, edx
    jz 8f
    cmp rax, [rbx + WG_hash]
    jne 8f
    mov eax, 1
    pop rbx
    ret
8:  lea rdi, [rip + .Lwc_stale]
    lea rsi, [rip + .Lws_e_stale]
    call ws_err
    xor eax, eax
    pop rbx
    ret

# FN ws_disk_needed() -> eax 1 when the edit changes files on disk: a closed file's group with
# edits, or a file operation
FN ws_disk_needed
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + wg_vec + VEC_len]
    jae 9f
    imul rdx, rcx, WG_SIZE
    add rdx, [rip + wg_vec + VEC_ptr]
    inc rcx
    cmp qword ptr [rdx + WG_kind], WK_TEXT
    jne 8f
    cmp qword ptr [rdx + WG_hidden], 0
    je 1b
    cmp qword ptr [rdx + WG_count], 0
    je 1b
8:  mov eax, 1
9:  ret

# FN ws_disk_prepare(): the closed files' edits made in their hidden documents, and the bytes to
# write with their hashes (the confirmation list's preview shows them)
FN ws_disk_prepare
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 9f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    cmp qword ptr [r12 + WG_hidden], 0
    je 1b
    cmp qword ptr [r12 + WG_count], 0
    je 1b
    cmp qword ptr [r12 + WG_new], 0
    jne 1b
    mov rdi, r12
    call ws_apply_group
    mov rdi, [r12 + WG_doc]
    lea rsi, [rip + wd_sb]
    call ws_doc_bytes
    mov rdi, [rip + wd_sb + SB_ptr]
    mov rsi, [rip + wd_sb + SB_len]
    mov [r12 + WG_nlen], rsi
    call mem_dup
    mov [r12 + WG_new], rax
    mov rdi, rax
    mov rsi, [r12 + WG_nlen]
    call ws_fnv
    mov [r12 + WG_after], rax
    jmp 1b
9:  EPILOGUE

# ---------------- the journal ----------------

# FN wd_jpath(T, slot, suffix cstr or 0) -> rax cstr: the journal folder, or a file in it ("plan"
# for slot -1, else SLOT.suffix), in wd_path
FN wd_jpath
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rip + wd_path]
    call sb_clear
    lea rdi, [rip + wd_path]
    mov rsi, [rbx + TX_journal]
    call sb_push_cstr
    test r13, r13
    jz 8f
    lea rdi, [rip + wd_path]
    mov esi, '/'
    call sb_push_byte
    test r12, r12
    jns 1f
    lea rdi, [rip + wd_path]
    mov rsi, r13
    call sb_push_cstr
    jmp 8f
1:  lea rdi, [rip + wd_path]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + wd_path]
    mov rsi, r13
    call sb_push_cstr
8:  lea rdi, [rip + wd_path]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + wd_path + SB_ptr]
    EPILOGUE

# wd_edits_dir(sb) -> eax 1 with "$XDG_STATE_HOME/rhun/edits" in sb (created), 0 without a home
wd_edits_dir:
    push rbx
    mov rbx, rdi
    call session_state_dir
    test eax, eax
    jz 9f
    mov rdi, rbx
    lea rsi, [rip + .Ledits]
    call sb_push_cstr
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    mov rdi, [rbx + SB_ptr]
    call vfs_mkdir_p
    mov eax, 1
9:  pop rbx
    ret

# wd_journal_new(T) -> eax 1 with T's journal folder made (TX_journal) and the plan begun
wd_journal_new:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + wd_path]
    call wd_edits_dir
    test eax, eax
    jz 8f
    lea rdi, [rip + wd_path]
    lea rsi, [rip + .Ltx_prefix]
    call sb_push_cstr
    SYS SYS_getpid
    mov r12, rax
    lea rdi, [rip + wd_path]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + wd_path]
    mov esi, '-'
    call sb_push_byte
    lea rdi, [rip + wd_path]
    mov rsi, [rbx + TX_id]
    call sb_push_u64
    lea rdi, [rip + wd_path]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_path + SB_ptr]
    call file_remove_tree       # a leftover of an earlier process with this pid
    mov rdi, [rip + wd_path + SB_ptr]
    call vfs_mkdir_p
    mov rdi, [rip + wd_path + SB_ptr]
    call vfs_is_dir
    test eax, eax
    jz 8f
    mov rdi, [rip + wd_path + SB_ptr]
    call dup_cstr
    mov [rbx + TX_journal], rax
    lea rdi, [rip + wd_plan]
    call sb_clear
    lea rdi, [rip + wd_plan]
    lea rsi, [rip + .Lplan_head]
    call sb_push_cstr
    lea rdi, [rip + wd_plan]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    mov qword ptr [rip + wd_slot], 0
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN wd_plan_write(T) -> rax 0 or -errno: the plan as it is now, durably in the journal
FN wd_plan_write
    push rbx
    mov rsi, -1
    lea rdx, [rip + .Lplan]
    call wd_jpath
    mov rdi, rax
    mov rsi, [rip + wd_plan + SB_ptr]
    mov rdx, [rip + wd_plan + SB_len]
    call vfs_write_all
    pop rbx
    ret

# FN wd_plan_step(word cstr, slot, before, after, path cstr): a line "WORD SLOT BEFORE AFTER LEN"
# and the path on the next line
FN wd_plan_step
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    lea rdi, [rip + wd_plan]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + wd_plan]
    mov rsi, r12
    call sb_push_u64
    mov rdi, r13
    call wd_plan_hex
    mov rdi, r14
    call wd_plan_hex
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r15
    call strlen
    lea rdi, [rip + wd_plan]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + wd_plan]
    mov rsi, r15
    call sb_push_cstr
    lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# wd_plan_hex(value): " " and 16 hex digits
wd_plan_hex:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    mov r12d, 16
1:  mov rax, rbx
    shr rax, 60
    lea rdx, [rip + .Lhex]
    movzx esi, byte ptr [rdx + rax]
    shl rbx, 4
    lea rdi, [rip + wd_plan]
    call sb_push_byte
    dec r12d
    jnz 1b
    EPILOGUE

# FN wd_keep(T, slot, ptr, len, suffix) -> rax 0 or -errno: bytes kept in the journal as
# SLOT.suffix
FN wd_keep
    PROLOGUE
    mov r12, rdx
    mov r13, rcx
    mov rdx, r8
    call wd_jpath
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call vfs_write_all
    EPILOGUE

# FN wd_step(): one disk step of a commit; with RHUN_TEST_EDIT_CRASH=N the process exits (status
# 70) after the Nth, as a crash would leave the journal (tests only)
FN wd_step
    inc qword ptr [rip + wd_steps]
    mov rax, [rip + wd_crash]
    test rax, rax
    jz 9f
    cmp [rip + wd_steps], rax
    jb 9f
    mov edi, 70
    SYS SYS_exit_group
9:  ret

# ---------------- making it ----------------

# FN ws_disk_commit() -> eax 1 when the edit was made with what it writes; 0 when the system
# refused a write and everything was put back (ws_code: io)
FN ws_disk_commit
    PROLOGUE 16
    mov qword ptr [rip + wd_steps], 0
    mov qword ptr [rip + wd_crash], 0
    lea rdi, [rip + .Lenv_crash]
    call getenv
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, rax
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call parse_u64
    mov [rip + wd_crash], rax
1:  call ws_tx_label
    mov rdi, rax
    mov rsi, rdx
    call tx_new
    mov r15, rax                # T
    or qword ptr [r15 + TX_flags], TXF_DISK
    mov rdi, r15
    call wd_journal_new
    test eax, eax
    jz .Lwc_nojournal
    # the plan lists the steps in the order they are made (recovery undoes them newest first):
    # the creates, the closed files' bytes, the clean open documents', the renames and deletes
    mov rdi, r15
    xor esi, esi
    call ws_ops_plan            # the creates (wsops.s)
    # the closed files: kept in the journal, planned, then written
    xor ebx, ebx
2:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 3f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_hidden], 0
    je 2b
    cmp qword ptr [r12 + WG_count], 0
    je 2b
    mov rdi, r15
    mov rsi, r12
    call wd_plan_file
    test rax, rax
    js .Lwc_io
    jmp 2b
3:  mov rdi, r15
    call wd_plan_write
    test rax, rax
    js .Lwc_io
    # creates first (wsops.s), then the closed files
    mov rdi, r15
    call ws_ops_creates
    test rax, rax
    js .Lwc_rollback
    xor ebx, ebx
4:  cmp rbx, [r15 + TX_nparts]
    jae 5f
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    inc rbx
    cmp qword ptr [r12 + TP_kind], TPK_FILE
    jne 4b
    mov rdi, r15
    mov rsi, [r12 + TP_slot]
    mov rdx, r12
    call wd_write_slot          # the bytes after
    test rax, rax
    js .Lwc_rollback
    or qword ptr [r12 + TP_flags], TPF_DONE
    call wd_step
    jmp 4b
5:  # the open documents, each one undo step of T
    xor ebx, ebx
6:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 7f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, r15
    call ws_buf_group
    jmp 6b
7:  # those that had no unsaved changes are written too
    mov rdi, r15
    call wd_write_clean
    test rax, rax
    js .Lwc_rollback
    # renames and deletes (wsops.s), planned first
    mov rdi, r15
    mov esi, 1
    call ws_ops_plan
    mov rdi, r15
    call wd_plan_write
    test rax, rax
    js .Lwc_rollback
    mov rdi, r15
    call ws_ops_moves
    test rax, rax
    js .Lwc_rollback
    lea rdi, [rip + wd_plan]
    lea rsi, [rip + .Lcommitted]
    call sb_push_cstr
    mov rdi, r15
    call wd_plan_write
    mov dword ptr [rip + ws_wrote], 1
    call ws_ops_done            # tabs follow, the explorer catches up
    cmp dword ptr [rip + ws_user], 0
    jne 72f
    # "Applied 'Rename to total' to 4 files"
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lapplied]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    mov rsi, [r15 + TX_label]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lto]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    mov rsi, [r15 + TX_nparts]
    call sb_push_u64
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lfiles]
    cmp qword ptr [r15 + TX_nparts], 1
    jne 71f
    lea rsi, [rip + .Lfile]
71: call sb_push_cstr
    lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    call app_toast
    mov eax, 1
    EPILOGUE
72: # the explorer's own: "Delete util.go: Undo Last Multi-File Edit (Ctrl+Z here) brings it back"
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    mov rsi, [r15 + TX_label]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Luser_undo]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    call app_toast
    mov eax, 1
    EPILOGUE
.Lwc_rollback:
    mov rdi, r15
    call wd_rollback
.Lwc_io:
    call tx_drop_last           # its journal goes with it
    lea rdi, [rip + .Lwc_io_text]
    lea rsi, [rip + .Lws_e_io]
    call ws_err
    xor eax, eax
    EPILOGUE
.Lwc_nojournal:
    call tx_drop_last
    mov qword ptr [rip + ws_entry], 0
    lea rdi, [rip + .Lwc_io_text]
    lea rsi, [rip + .Lws_e_io]
    call ws_err
    xor eax, eax
    EPILOGUE

# wd_plan_file(T, WG*) -> rax 0 or -errno: a closed file's participant, its bytes before and after
# kept in the journal and its write planned
wd_plan_file:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov esi, TPK_FILE
    call tx_add
    mov r13, rax
    mov rax, [rip + wd_slot]
    inc qword ptr [rip + wd_slot]
    mov [r13 + TP_slot], rax
    mov rdi, [r12 + WG_real]
    call dup_cstr
    mov [r13 + TP_path], rax
    mov rax, [r12 + WG_before]
    mov [r13 + TP_before], rax
    mov rax, [r12 + WG_after]
    mov [r13 + TP_after], rax
    mov rdi, rbx
    mov rsi, [r13 + TP_slot]
    mov rdx, [r12 + WG_orig]
    mov rcx, [r12 + WG_olen]
    lea r8, [rip + .Lorig]
    call wd_keep
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, [r13 + TP_slot]
    mov rdx, [r12 + WG_new]
    mov rcx, [r12 + WG_nlen]
    lea r8, [rip + .Lnew]
    call wd_keep
    test rax, rax
    js 9f
    lea rdi, [rip + .Lw_write]
    mov rsi, [r13 + TP_slot]
    mov rdx, [r13 + TP_before]
    mov rcx, [r13 + TP_after]
    mov r8, [r13 + TP_path]
    call wd_plan_step
    xor eax, eax
9:  EPILOGUE

# FN wd_write_slot(T, slot, TP) -> rax 0 or -errno: the participant's file gets its bytes after
# (slot.new) from the journal
FN wd_write_slot
    lea rcx, [rip + .Lnew]
    jmp wd_put
# FN wd_restore_slot(T, slot, TP) -> rax 0 or -errno: and its bytes before (slot.orig)
FN wd_restore_slot
    lea rcx, [rip + .Lorig]
wd_put:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov rdx, rcx
    call wd_jpath
    mov rdi, rax
    mov esi, WS_READ_MAX
    call vfs_read_limited
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, [r12 + TP_path]
    mov rsi, rax
    call vfs_write_all
    mov r14, rax
    mov rdi, r13
    call mem_free
    mov rax, r14
    EPILOGUE
8:  mov rax, rdx
    test rax, rax
    js 9f
    mov rax, -5                 # EIO
9:  EPILOGUE

# wd_write_clean(T) -> rax 0 or -errno: the open documents of T that had no unsaved changes,
# written as they now are (their bytes before and after kept, the write planned first)
wd_write_clean:
    PROLOGUE 16
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 1b
    cmp qword ptr [r12 + WG_hidden], 0
    jne 1b
    cmp qword ptr [r12 + WG_count], 0
    je 1b
    cmp qword ptr [r12 + WG_clean], 0
    je 1b
    cmp qword ptr [r12 + WG_real], 0
    je 1b                       # untitled, or outside where the extension may write
    mov r13, [r12 + WG_doc]
    # its participant
    xor ecx, ecx
2:  cmp rcx, [r15 + TX_nparts]
    jae 1b
    imul r14, rcx, TP_SIZE
    add r14, [r15 + TX_parts]
    inc rcx
    cmp qword ptr [r14 + TP_kind], TPK_BUF
    jne 2b
    cmp [r14 + TP_doc], r13
    jne 2b
    # the file as it is (its bytes before), the buffer as it will be written
    mov rdi, [r13 + DOC_path]
    mov esi, WS_READ_MAX
    call vfs_read_limited
    test rax, rax
    jz 1b                       # gone meanwhile: the buffer stays unsaved
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rax
    mov rsi, rdx
    call ws_fnv
    mov [r14 + TP_before], rax
    mov rax, [rip + wd_slot]
    inc qword ptr [rip + wd_slot]
    mov [r14 + TP_slot], rax
    mov rdi, r15
    mov rsi, rax
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    lea r8, [rip + .Lorig]
    call wd_keep
    mov [rsp + 8], rax
    mov rdi, [rsp]
    call mem_free
    mov rax, [rsp + 8]
    test rax, rax
    js 9f
    mov rdi, r13
    lea rsi, [rip + wd_sb]
    call ws_doc_bytes
    mov rdi, [rip + wd_sb + SB_ptr]
    mov rsi, [rip + wd_sb + SB_len]
    call ws_fnv
    mov [r14 + TP_after], rax
    mov rdi, r15
    mov rsi, [r14 + TP_slot]
    mov rdx, [rip + wd_sb + SB_ptr]
    mov rcx, [rip + wd_sb + SB_len]
    lea r8, [rip + .Lnew]
    call wd_keep
    test rax, rax
    js 9f
    mov rdi, [r13 + DOC_path]
    call dup_cstr
    mov [r14 + TP_path], rax
    lea rdi, [rip + .Lw_write]
    mov rsi, [r14 + TP_slot]
    mov rdx, [r14 + TP_before]
    mov rcx, [r14 + TP_after]
    mov r8, [r14 + TP_path]
    call wd_plan_step
    mov rdi, r15
    call wd_plan_write
    test rax, rax
    js 9f
    mov rdi, r13
    lea rsi, [rip + wd_sb]
    call ws_doc_bytes           # (the journal paths used wd_path only)
    mov rdi, [r14 + TP_path]
    mov rsi, [rip + wd_sb + SB_ptr]
    mov rdx, [rip + wd_sb + SB_len]
    call vfs_write_all
    test rax, rax
    js 9f
    mov qword ptr [r14 + TP_wrote], 1
    or qword ptr [r14 + TP_flags], TPF_DONE
    mov rdi, r13
    call ws_doc_written
    call wd_step
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# wd_rollback(T): a commit that failed: every step done is put back, newest first (renames and
# deletes, written files, buffers, creates); the journal stays when something could not be
FN wd_rollback
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    call ws_ops_undo_moves      # renames and deletes back (wsops.s) -> rax steps left
    mov r14, rax                # steps that could not be put back
    mov r12, [rbx + TX_nparts]
1:  test r12, r12
    jz 5f
    dec r12
    imul r13, r12, TP_SIZE
    add r13, [rbx + TX_parts]
    cmp qword ptr [r13 + TP_kind], TPK_BUF
    jne 3f
    # its buffer step undone; a written one's file back
    test qword ptr [r13 + TP_flags], TPF_DONE
    jz 2f
    mov rdi, rbx
    mov rsi, [r13 + TP_slot]
    mov rdx, r13
    call wd_restore_slot
    test rax, rax
    jns 2f
    inc r14
2:  mov dword ptr [rip + tx_local], 1
    mov rdi, [r13 + TP_doc]
    call doc_undo
    mov dword ptr [rip + tx_local], 0
    test qword ptr [r13 + TP_flags], TPF_DONE
    jz 1b
    mov rdi, [r13 + TP_doc]
    call ws_doc_written         # the file holds its old text again
    jmp 1b
3:  cmp qword ptr [r13 + TP_kind], TPK_FILE
    jne 1b
    test qword ptr [r13 + TP_flags], TPF_DONE
    jz 1b
    mov rdi, rbx
    mov rsi, [r13 + TP_slot]
    mov rdx, r13
    call wd_restore_slot
    test rax, rax
    jns 1b
    inc r14
    jmp 1b
5:  mov rdi, rbx
    call ws_ops_undo_creates
    add r14, rax
    test r14, r14
    jz 9f
    # something could not be put back: the journal stays for the next start
    mov rdi, [rbx + TX_journal]
    call mem_free
    mov qword ptr [rbx + TX_journal], 0
    lea rdi, [rip + .Lnot_back]
    call app_toast
9:  EPILOGUE

# ---------------- undo and redo of disk participants ----------------

# FN ws_disk_ready(T, TP, dir) -> eax 1 when the participant's file still holds what the step
# before left (dir 0: T's result, to be undone; dir 1: the original, to be redone)
FN ws_disk_ready
    PROLOGUE
    mov r13, rdi
    mov rbx, rsi
    mov r12d, edx
    cmp qword ptr [rbx + TP_kind], TPK_BUF
    je 1f
    cmp qword ptr [rbx + TP_kind], TPK_FILE
    jne .Lwy_ops
1:  mov rdi, [rbx + TP_path]
    test rdi, rdi
    jz 8f
    cmp qword ptr [rbx + TP_slot], 0
    jl 8f
    # where its file is now: an open document's own path; else moved by T's renames while T is
    # applied
    mov rax, [rbx + TP_doc]
    test rax, rax
    jz 11f
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz 8f
    jmp 12f
11: test r12d, r12d
    jnz 12f
    mov rsi, rdi
    mov rdi, r13                # T
    call ws_ops_map
    mov rdi, rax
12: mov r14, rdi
    call ws_file_hash
    test edx, edx
    jnz 13f
    # missing: fine on redo when T creates it first
    test r12d, r12d
    jz 8f
    mov rdi, r13
    mov rsi, r14
    call ws_ops_creates_path
    test eax, eax
    jz 8f
    EPILOGUE
13:
    mov rcx, [rbx + TP_after]
    test r12d, r12d
    jz 2f
    mov rcx, [rbx + TP_before]
2:  cmp rax, rcx
    jne 8f
    mov eax, 1
    EPILOGUE
.Lwy_ops:
    mov rsi, rbx
    mov edx, r12d
    call ws_ops_ready           # creates, renames, deletes (wsops.s)
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_disk_step(T, dir) -> eax 1 when the picked file participants were undone (dir 0: their
# bytes before back) or redone (dir 1: after), or there were none; 0 when the system refused a
# write or a file operation (everything done is put back, a toast says which, and nothing is picked
# any more)
FN ws_disk_step
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rbx
    mov esi, r12d
    call ws_ops_step_first      # renames and deletes back first on undo (wsops.s; a failure there
    test eax, eax               # puts back what it did itself)
    jz .Lws_none
    xor r13d, r13d
1:  cmp r13, [rbx + TX_nparts]
    jae .Lws_ok
    imul r14, r13, TP_SIZE
    add r14, [rbx + TX_parts]
    inc r13
    test qword ptr [r14 + TP_flags], TPF_PICK
    jz 1b
    cmp qword ptr [r14 + TP_kind], TPK_FILE
    jne 1b
    mov rdi, rbx
    mov rsi, [r14 + TP_slot]
    mov rdx, r14
    test r12d, r12d
    jnz 2f
    call wd_restore_slot
    jmp 3f
2:  call wd_write_slot
3:  test rax, rax
    jns 1b
    # this file failed: the ones before it go back as they were, then the first steps
    mov [rsp], r14
    mov r15, r13
    dec r15
    call wd_step_files_back
    mov rdi, rbx
    mov esi, r12d
    call ws_ops_unstep_first
    mov rdi, [rsp]
    call wd_cannot
    jmp .Lws_none
.Lws_ok:
    mov rdi, rbx
    mov esi, r12d
    call ws_ops_step_last       # creates (and redone renames and deletes); a failure there puts
    test eax, eax               # back what it did itself and says so
    jnz 8f
    mov r15, [rbx + TX_nparts]  # every file goes back, then the first steps
    call wd_step_files_back
    mov rdi, rbx
    mov esi, r12d
    call ws_ops_unstep_first
.Lws_none:
    # nothing moved: the picks are cleared so tx_run changes no buffer either
    xor ecx, ecx
6:  cmp rcx, [rbx + TX_nparts]
    jae 7f
    imul rax, rcx, TP_SIZE
    add rax, [rbx + TX_parts]
    and qword ptr [rax + TP_flags], ~TPF_PICK
    inc rcx
    jmp 6b
7:  xor eax, eax
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# wd_step_files_back (rbx T, r12d dir, r15 parts before this index): ws_disk_step's picked files
# below r15 get the bytes they had before the step (clobbers r14, r15)
wd_step_files_back:
    sub rsp, 8
1:  test r15, r15
    jz 9f
    dec r15
    imul r14, r15, TP_SIZE
    add r14, [rbx + TX_parts]
    test qword ptr [r14 + TP_flags], TPF_PICK
    jz 1b
    cmp qword ptr [r14 + TP_kind], TPK_FILE
    jne 1b
    mov rdi, rbx
    mov rsi, [r14 + TP_slot]
    mov rdx, r14
    test r12d, r12d
    jz 2f
    call wd_restore_slot
    jmp 1b
2:  call wd_write_slot
    jmp 1b
9:  add rsp, 8
    ret

# FN wd_cannot(TP): "Could not write NAME: nothing changed"
FN wd_cannot
    push rbx
    mov rbx, rdi
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lcannot]
    call sb_push_cstr
    mov rdi, [rbx + TP_path]
    test rdi, rdi
    jz 1f
    call strlen
    mov rsi, rax
    mov rdi, [rbx + TP_path]
    call path_basename
    lea rdi, [rip + wd_sb]
    mov rsi, rax
    call sb_push
1:  lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lcannot2]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    call app_toast
    pop rbx
    ret

# FN ws_disk_rewrite(T, TP, dir): a written buffer's file again as the buffer now is (after its
# undo or redo), and the hash that step leaves noted for the next one
FN ws_disk_rewrite
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, [r12 + TP_doc]
    test r14, r14
    jz 9f
    mov rdi, r14
    lea rsi, [rip + wd_sb]
    call ws_doc_bytes
    mov rdi, [r14 + DOC_path]   # where it is now (a rename of the edit moves it)
    mov rsi, [rip + wd_sb + SB_ptr]
    mov rdx, [rip + wd_sb + SB_len]
    call vfs_write_all
    test rax, rax
    js 8f
    mov rdi, r14
    call ws_doc_written
    mov rdi, [rip + wd_sb + SB_ptr]
    mov rsi, [rip + wd_sb + SB_len]
    call ws_fnv
    test r13d, r13d
    jnz 1f
    mov [r12 + TP_before], rax
    jmp 9f
1:  mov [r12 + TP_after], rax
    jmp 9f
8:  mov rdi, r12                # the buffer moved; its file did not: it stays unsaved
    call wd_cannot
9:  EPILOGUE

# FN ws_disk_done(): after an undo or redo of disk participants (wsops.s: tabs and the explorer)
FN ws_disk_done
    jmp ws_ops_done

# FN ws_journal_drop(T): its journal folder goes
FN ws_journal_drop
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + TX_journal]
    test rdi, rdi
    jz 9f
    call vfs_remove_tree
    mov rdi, [rbx + TX_journal]
    call mem_free
    mov qword ptr [rbx + TX_journal], 0
9:  pop rbx
    ret

# ---------------- recovery ----------------

# wd_name_cb(ctx, name cstr): a journal folder's name ("tx-...") collected (NUL-separated)
wd_name_cb:
    push rbx
    mov rbx, rsi
    mov rdi, rsi
    call strlen
    cmp rax, 3
    jb 9f
    cmp byte ptr [rbx], 't'
    jne 9f
    cmp byte ptr [rbx + 1], 'x'
    jne 9f
    cmp byte ptr [rbx + 2], '-'
    jne 9f
    lea rdi, [rip + wd_names]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wd_names]
    xor esi, esi
    call sb_push_byte
9:  pop rbx
    ret

# wd_alive(pid) -> eax 1 when a process with that id runs (not this one)
wd_alive:
    push rbx
    mov rbx, rdi
    SYS SYS_getpid
    cmp rax, rbx
    je 8f                       # this process: the journal is an earlier one's
.ifdef WINDOWS
    mov rdi, rbx
    call win_pid_alive
    pop rbx
    ret
.else
    mov rdi, rbx
    xor esi, esi
    SYS SYS_kill
    test rax, rax
    jz 9f
    cmp rax, -1                 # EPERM: it runs, as another user
    je 9f
.endif
8:  xor eax, eax
    pop rbx
    ret
9:  mov eax, 1
    pop rbx
    ret

# FN ws_recover(): at startup, before any tab opens: every journal of a process that no longer
# runs is resolved. Without "committed" the edit was cut short: each write whose file still
# holds what it wrote gets its bytes before back (anything else is left as it is); with it, the
# session that could undo it is gone. Either way the journal goes.
FN ws_recover
    PROLOGUE 16
    mov qword ptr [rip + wd_restored], 0
    mov qword ptr [rip + wd_left], 0
    lea rdi, [rip + wd_names]
    call sb_clear
    lea rdi, [rip + wd_path]
    call wd_edits_dir
    test eax, eax
    jz 9f
    mov rdi, [rip + wd_path + SB_ptr]
    call dup_cstr
    mov r15, rax                # the edits folder
    mov rdi, rax
    lea rsi, [rip + wd_name_cb]
    xor edx, edx
    call vfs_dir_each_names
    xor ebx, ebx                # offset of the next name
1:  cmp rbx, [rip + wd_names + SB_len]
    jae 8f
    mov r12, [rip + wd_names + SB_ptr]
    add r12, rbx
    mov rdi, r12
    call strlen
    lea rbx, [rbx + rax + 1]
    # "tx-PID-ID"
    lea rdi, [r12 + 3]
    lea rsi, [rax - 3]
    call parse_u64
    test rdx, rdx
    jz 1b
    mov rdi, rax
    call wd_alive
    test eax, eax
    jnz 1b
    # the folder's path
    lea rdi, [rip + wd_path]
    call sb_clear
    lea rdi, [rip + wd_path]
    mov rsi, r15
    call sb_push_cstr
    lea rdi, [rip + wd_path]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + wd_path]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + wd_path]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_path + SB_ptr]
    call dup_cstr
    mov r13, rax
    mov rdi, r13
    call wd_recover_one
    mov rdi, r13
    call vfs_remove_tree
    mov rdi, r13
    call mem_free
    jmp 1b
8:  mov rdi, r15
    call mem_free
    cmp qword ptr [rip + wd_restored], 0
    jne 81f
    cmp qword ptr [rip + wd_left], 0
    je 9f
81: # "Restored 3 files from a workspace edit that was cut short"
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lrestored]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    mov rsi, [rip + wd_restored]
    call sb_push_u64
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lrestored2]
    call sb_push_cstr
    cmp qword ptr [rip + wd_left], 0
    je 82f
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lrestored3]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    mov rsi, [rip + wd_left]
    call sb_push_u64
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lrestored4]
    call sb_push_cstr
82: lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    call app_toast
9:  EPILOGUE

# wd_recover_one(folder cstr): one journal (see ws_recover)
wd_recover_one:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lslash_plan]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    mov esi, 16777216
    call vfs_read_limited
    test rax, rax
    jz 9f
    mov r12, rax                # the plan
    mov r13, rdx
    # "committed" at its end: nothing to do
    cmp r13, 10
    jb 1f
    lea rdi, [r12 + r13 - 10]
    mov esi, 10
    lea rdx, [rip + .Lcommitted]
    call str_eq_cstr
    test eax, eax
    jnz 8f
1:  mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call ws_recover_steps       # every step, newest first (wsops.s) -> rax restored, rdx left
    add [rip + wd_restored], rax
    add [rip + wd_left], rdx
8:  mov rdi, r12
    call mem_free
9:  EPILOGUE

# FN ws_recover_write(folder, slot, before, after, path) -> eax 1 restored, 2 already as before,
# 0 left: a cut-short write whose file still holds what it wrote gets its bytes before (SLOT.orig)
# back
FN ws_recover_write
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, r15
    call ws_file_hash
    test edx, edx
    jz 8f
    cmp rax, r14
    jne 7f                      # not what it wrote
    lea rdi, [rip + wd_path]
    call sb_clear
    lea rdi, [rip + wd_path]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wd_path]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + wd_path]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + wd_path]
    lea rsi, [rip + .Lorig]
    call sb_push_cstr
    lea rdi, [rip + wd_path]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_path + SB_ptr]
    mov esi, WS_READ_MAX
    call vfs_read_limited
    test rax, rax
    jz 8f
    mov [rsp], rax
    mov rdi, r15
    mov rsi, rax
    call vfs_write_all
    mov r14, rax
    mov rdi, [rsp]
    call mem_free
    test r14, r14
    js 8f
    mov eax, 1
    EPILOGUE
7:  cmp rax, r13                # already its bytes before: nothing to do, nothing left
    jne 8f
    mov eax, 2
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_journal_cleanup(): when rhun quits: this session's journals go (nothing can undo them)
FN ws_journal_cleanup
    jmp tx_drop_journals

# FN ws_journal_print(sb): print-journal, the journal folders on disk: "journal=NAME
# committed=0|1", or "journal=none"
FN ws_journal_print
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + wd_names]
    call sb_clear
    lea rdi, [rip + wd_path]
    call wd_edits_dir
    test eax, eax
    jz 7f
    mov rdi, [rip + wd_path + SB_ptr]
    call dup_cstr
    mov r15, rax
    mov rdi, rax
    lea rsi, [rip + wd_name_cb]
    xor edx, edx
    call vfs_dir_each_names
    xor r12d, r12d
1:  cmp r12, [rip + wd_names + SB_len]
    jae 6f
    mov r13, [rip + wd_names + SB_ptr]
    add r13, r12
    mov rdi, r13
    call strlen
    lea r12, [r12 + rax + 1]
    mov rdi, rbx
    lea rsi, [rip + .Lp_journal]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r13
    call sb_push_cstr
    # committed?
    lea rdi, [rip + wd_sb]
    call sb_clear
    lea rdi, [rip + wd_sb]
    mov rsi, r15
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + wd_sb]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    lea rsi, [rip + .Lslash_plan]
    call sb_push_cstr
    lea rdi, [rip + wd_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wd_sb + SB_ptr]
    mov esi, 16777216
    call vfs_read_limited
    xor r14d, r14d
    test rax, rax
    jz 4f
    mov r13, rax
    cmp rdx, 10
    jb 31f
    lea rdi, [rax + rdx - 10]
    mov esi, 10
    lea rdx, [rip + .Lcommitted]
    call str_eq_cstr
    mov r14d, eax
31: mov rdi, r13
    call mem_free
4:  mov rdi, rbx
    lea rsi, [rip + .Lp_committed]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r14
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    jmp 1b
6:  mov rdi, r15
    call mem_free
    cmp qword ptr [rip + wd_names + SB_len], 0
    jne 9f
7:  mov rdi, rbx
    lea rsi, [rip + .Lp_none]
    call sb_push_cstr
9:  EPILOGUE

.section .rodata
.Ledits: .asciz "/edits"
.Ltx_prefix: .asciz "/tx-"
.Lplan: .asciz "plan"
.Lslash_plan: .asciz "/plan"
.Lplan_head: .asciz "rhun-edit 1 "
.Lw_write: .asciz "write"
.Lcommitted: .asciz "committed\n"
.globl ws_s_orig, ws_s_new
ws_s_orig:
.Lorig: .asciz ".orig"
ws_s_new:
.Lnew: .asciz ".new"
.Lhex: .ascii "0123456789abcdef"
.Lenv_crash: .asciz "RHUN_TEST_EDIT_CRASH"
.Lapplied: .asciz "Applied '"
.Luser_undo: .asciz ": Ctrl+Z in the explorer, or Undo Last Multi-File Edit, takes it back"
.Lto: .asciz "' to "
.Lfiles: .asciz " files"
.Lfile: .asciz " file"
.Lcannot: .asciz "Could not write "
.Lcannot2: .asciz ": nothing changed"
.Lnot_back: .asciz "A workspace edit failed and some files could not be put back: rhun retries at its next start"
.Lrestored: .asciz "Restored "
.Lrestored2: .asciz " files from a workspace edit that was cut short"
.Lrestored3: .asciz " ("
.Lrestored4: .asciz " changed since and left as they are)"
.Lp_journal: .asciz "journal="
.Lp_committed: .asciz " committed="
.Lp_none: .asciz "journal=none\n"
.Lwc_nofile: .asciz "nofile a file is missing, not a regular text file, or over 16 MiB"
.Lws_e_nofile: .asciz "A file the edit changes cannot be read: nothing changed"
.Lwc_needs: .asciz "needs project=write a file is outside the project and the extension's state folder"
.Lws_e_needs: .asciz "The extension's edit changes a file outside the project: nothing changed"
.Lwc_twice: .asciz "syntax a file appears in two groups"
.Lws_e_bad: .asciz "The extension's edit could not be read: nothing changed"
.Lwc_stale: .asciz "stale a file changed since the edit was made"
.Lws_e_stale: .asciz "A file changed since the edit was made: nothing changed"
.Lwc_big: .asciz "toobig over 16 MiB in a file or 64 MiB in all"
.Lws_e_big: .asciz "The extension's edit is too big: nothing changed"
.Lwc_io_text: .asciz "io the system refused a write; everything was put back"
.Lws_e_io: .asciz "A file could not be written: the edit was put back"
