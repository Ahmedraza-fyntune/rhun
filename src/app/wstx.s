# workspace-edit transactions (docs/extensions/v1.1.md, workspace-edits): the documents and files
# one workspace edit changed undo and redo together. Each document keeps its own undo records; a
# transaction's records carry its id (UR_tx), and doc_undo/doc_redo hand such a step to tx_step,
# which undoes every participant or, when one changed since, asks what to do.
.include "rhun.inc"

.equ WLK_UNDO, 1                # wslist kinds (wsconfirm.s): the partial-undo list

.bss
.p2align 3
tx_table: .zero TX_SIZE * TX_MAX    # oldest first
tx_count: .quad 0
tx_next: .quad 0                # the last id given
tx_sb: .zero SB_SIZE            # a message being built
tx_name: .zero 4100             # a participant's name for a message
# the partial-undo list on show: its transaction, document and direction (0 undo, 1 redo)
tx_ask_id: .quad 0
tx_ask_doc: .quad 0
tx_ask_dir: .quad 0
.globl tx_local
tx_local: .long 0               # doc_undo and doc_redo undo their own document only (tx_run's calls)
tx_ask_ok: .long 0              # in that list: the participants that did not change

.text

# FN tx_find(id) -> rax the live transaction with that id, or 0
FN tx_find
    xor eax, eax
    test rdi, rdi
    jz 9f
    lea rax, [rip + tx_table]
    mov rcx, [rip + tx_count]
1:  test rcx, rcx
    jz 8f
    cmp [rax + TX_id], rdi
    je 9f
    add rax, TX_SIZE
    dec rcx
    jmp 1b
8:  xor eax, eax
9:  ret

# tx_free(T): what it owns goes (its journal folder too)
tx_free:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    call ws_journal_drop
    mov rdi, [rbx + TX_label]
    call mem_free
    xor r12d, r12d
1:  cmp r12, [rbx + TX_nparts]
    jae 2f
    imul r13, r12, TP_SIZE
    add r13, [rbx + TX_parts]
    mov rdi, [r13 + TP_path]
    call mem_free
    mov rdi, [r13 + TP_path2]
    call mem_free
    inc r12
    jmp 1b
2:  mov rdi, [rbx + TX_parts]
    call mem_free
    EPILOGUE

# FN tx_new(label ptr, len) -> rax a new transaction with no participants; when 64 are kept the
# oldest goes (its records become ordinary per-document steps: their id no longer resolves)
FN tx_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp qword ptr [rip + tx_count], TX_MAX
    jb 1f
    lea rdi, [rip + tx_table]
    call tx_free
    lea rdi, [rip + tx_table]
    lea rsi, [rdi + TX_SIZE]
    mov edx, TX_SIZE * (TX_MAX - 1)
    call memmove
    dec qword ptr [rip + tx_count]
1:  mov rbx, [rip + tx_count]
    imul rbx, rbx, TX_SIZE
    lea rax, [rip + tx_table]
    add rbx, rax
    inc qword ptr [rip + tx_count]
    inc qword ptr [rip + tx_next]
    mov rax, [rip + tx_next]
    mov [rbx + TX_id], rax
    mov qword ptr [rbx + TX_journal], 0
    mov qword ptr [rbx + TX_nparts], 0
    mov qword ptr [rbx + TX_parts], 0
    mov qword ptr [rbx + TX_flags], 0
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx + TX_label], rax
    mov rax, rbx
    EPILOGUE

# FN tx_drop_last(): the newest transaction goes again (a commit that failed before it was used)
FN tx_drop_last
    PROLOGUE
    mov rax, [rip + tx_count]
    test rax, rax
    jz 9f
    dec rax
    mov [rip + tx_count], rax
    imul rdi, rax, TX_SIZE
    lea rax, [rip + tx_table]
    add rdi, rax
    call tx_free
9:  EPILOGUE

# FN tx_add(T, kind) -> rax its new participant (TP_SIZE bytes, cleared, no journal slot)
FN tx_add
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + TX_nparts]
    inc rax
    imul rsi, rax, TP_SIZE
    mov rdi, [rbx + TX_parts]
    test rdi, rdi
    jnz 1f
    mov rdi, rsi
    call mem_alloc
    jmp 2f
1:  call mem_realloc
2:  mov [rbx + TX_parts], rax
    mov rcx, [rbx + TX_nparts]
    inc qword ptr [rbx + TX_nparts]
    imul rcx, rcx, TP_SIZE
    add rax, rcx
    mov r13, rax
    mov rdi, rax
    xor esi, esi
    mov edx, TP_SIZE
    call memset
    mov [r13 + TP_kind], r12
    mov qword ptr [r13 + TP_slot], -1
    mov rax, r13
    EPILOGUE

# FN tx_tag(T, doc): the records of the document's last undo step belong to T
FN tx_tag
    mov rax, [rdi + TX_id]
    mov rcx, [rsi + DOC_undo + VEC_len]
    test rcx, rcx
    jz 9f
    mov rdx, [rsi + DOC_undo + VEC_ptr]
    dec rcx
    imul rcx, rcx, UR_SIZE
    mov r8, [rdx + rcx + UR_group]
1:  cmp [rdx + rcx + UR_group], r8
    jne 9f
    mov [rdx + rcx + UR_tx], rax
    sub rcx, UR_SIZE
    jns 1b
9:  mov qword ptr [rsi + DOC_lastkind], EK_OTHER   # the next edit starts a step of its own
    ret

# tx_top(doc, dir) -> rax UR_tx of the last undo (dir 0) or redo (1) record, 0 when there is none
tx_top:
    lea rax, [rdi + DOC_undo]
    test esi, esi
    jz 1f
    lea rax, [rdi + DOC_redo]
1:  mov rcx, [rax + VEC_len]
    test rcx, rcx
    jz 8f
    dec rcx
    imul rcx, rcx, UR_SIZE
    add rcx, [rax + VEC_ptr]
    mov rax, [rcx + UR_tx]
    ret
8:  xor eax, eax
    ret

# FN tx_undo_hook(doc) -> eax -1 when the document's last step is not part of a live transaction
# (doc_undo goes on as usual), else 1 when it was handled (undone everywhere, or a question asked)
FN tx_undo_hook
    xor esi, esi
    jmp tx_hook
# FN tx_redo_hook(doc): the same for redo
FN tx_redo_hook
    mov esi, 1
tx_hook:
    cmp dword ptr [rip + tx_local], 0
    jne 8f
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    call tx_top
    mov rdi, rax
    call tx_find
    test rax, rax
    jz 7f
    mov rdi, rax
    mov rsi, rbx
    mov edx, r12d
    call tx_step
    pop r13
    pop r12
    pop rbx
    ret
7:  pop r13
    pop r12
    pop rbx
8:  mov eax, -1
    ret

# tx_ready(T, TP, dir) -> eax 1 when the participant can be undone (dir 0) or redone (1) as part of
# the whole: its document's step on top is T's, the file on disk still what T left
tx_ready:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp qword ptr [r12 + TP_kind], TPK_BUF
    jne 5f
    mov rdi, [r12 + TP_doc]
    mov esi, r13d
    call tx_top
    cmp rax, [rbx + TX_id]
    jne 8f
    cmp qword ptr [r12 + TP_wrote], 0
    je 9f
5:  # what is on disk
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ws_disk_ready
    test eax, eax
    jz 8f
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# tx_part_name(TP): its file's name (or the document's) into tx_name
tx_part_name:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + TP_path]
    test rax, rax
    jnz 1f
    mov rax, [rbx + TP_doc]
    mov rax, [rax + DOC_name]
    jmp 2f
1:  mov rdi, rax
    call strlen
    mov rsi, rax
    mov rdi, [rbx + TP_path]
    call path_basename
2:  lea rdi, [rip + tx_name]
    mov rsi, rax
    mov edx, 4000
    call tx_copy_cut
    pop rbx
    ret

# tx_copy_cut(dst, src cstr, max): src copied, at most max bytes, NUL-terminated
tx_copy_cut:
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 2f
    mov al, [rsi + rcx]
    test al, al
    jz 2f
    mov [rdi + rcx], al
    inc rcx
    jmp 1b
2:  mov byte ptr [rdi + rcx], 0
    ret

# FN tx_step(T, doc, dir) -> eax 1: undo (dir 0) or redo (1) T where it can go whole; when a
# participant changed since, the partial list asks (doc is where the user asked)
FN tx_step
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d              # participants that can go
    xor r15d, r15d              # participants that cannot
    mov qword ptr [rsp], 0      # the first of those
    mov eax, TPS_APPLIED
    test r13d, r13d
    jz 1f
    mov eax, TPS_UNDONE
1:  mov [rsp + 8], rax          # the state of the ones that go
    xor ecx, ecx
2:  cmp rcx, [rbx + TX_nparts]
    jae 4f
    imul rsi, rcx, TP_SIZE
    add rsi, [rbx + TX_parts]
    inc rcx
    and qword ptr [rsi + TP_flags], ~TPF_PICK
    mov rax, [rsi + TP_state]
    cmp rax, [rsp + 8]
    jne 2b
    push rcx
    push rsi
    mov rdi, rbx
    mov edx, r13d
    call tx_ready
    pop rsi
    pop rcx
    test eax, eax
    jz 3f
    or qword ptr [rsi + TP_flags], TPF_PICK
    inc r14
    jmp 2b
3:  inc r15
    cmp qword ptr [rsp], 0
    jne 2b
    mov [rsp], rsi
    jmp 2b
4:  test r15, r15
    jnz 5f
    # every one of them: as one
    mov rdi, rbx
    mov esi, r13d
    call tx_run
    mov eax, 1
    EPILOGUE
5:  # ask: "'Rename to total': calc.go changed after it"
    lea rdi, [rip + tx_sb]
    call sb_clear
    lea rdi, [rip + tx_sb]
    mov esi, 39
    call sb_push_byte
    lea rdi, [rip + tx_sb]
    mov rsi, [rbx + TX_label]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lchanged1]
    call sb_push_cstr
    mov rdi, [rsp]
    call tx_part_name
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + tx_name]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lchanged2]
    cmp r15, 1
    je 51f
    lea rsi, [rip + .Lchanged3]
51: call sb_push_cstr
    lea rdi, [rip + tx_sb]
    xor esi, esi
    call sb_push_byte
    mov edi, WLK_UNDO
    mov rsi, [rip + tx_sb + SB_ptr]
    call wslist_open            # a list that was open is cancelled first
    mov [rip + tx_ask_ok], r14d
    mov rax, [rbx + TX_id]
    mov [rip + tx_ask_id], rax
    mov [rip + tx_ask_doc], r12
    mov [rip + tx_ask_dir], r13
    # this file only (the document asked from can go: its step on top is T's)
    test r12, r12
    jz 62f                      # asked from the command, not from a document
    lea rdi, [rip + .Lthis_undo]
    test r13d, r13d
    jz 6f
    lea rdi, [rip + .Lthis_redo]
6:  mov esi, 1
    call wslist_add
62:
    test r12, r12
    jz 63f
    cmp r14, 1
    jbe 7f
63: test r14, r14
    jz 7f
    # the ones that did not change
    lea rdi, [rip + tx_sb]
    call sb_clear
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lrest_undo]
    test r13d, r13d
    jz 61f
    lea rsi, [rip + .Lrest_redo]
61: call sb_push_cstr
    lea rdi, [rip + tx_sb]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lrest_tail]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tx_sb + SB_ptr]
    mov esi, 2
    call wslist_add
7:  lea rdi, [rip + .Lcancel]
    mov esi, 3
    call wslist_add
    call wslist_ready
    mov eax, 1
    EPILOGUE

# FN tx_list_chosen(n): the partial list's answer: 1 this file only, 2 the participants that did
# not change, 3 cancel
FN tx_list_chosen
    PROLOGUE
    mov r12, rdi
    mov rdi, [rip + tx_ask_id]
    call tx_find
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp r12, 1
    je 1f
    cmp r12, 2
    jne 9f
    # the ones that can go, checked again (the list was open a while)
    mov r13d, [rip + tx_ask_dir]
    mov r14d, TPS_APPLIED
    test r13d, r13d
    jz 21f
    mov r14d, TPS_UNDONE
21: xor r15d, r15d
2:  cmp r15, [rbx + TX_nparts]
    jae 3f
    imul r12, r15, TP_SIZE
    add r12, [rbx + TX_parts]
    inc r15
    and qword ptr [r12 + TP_flags], ~TPF_PICK
    cmp [r12 + TP_state], r14
    jne 2b
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call tx_ready
    test eax, eax
    jz 2b
    or qword ptr [r12 + TP_flags], TPF_PICK
    jmp 2b
3:  mov rdi, rbx
    mov esi, r13d
    call tx_run
    jmp 9f
1:  # this document only: its own step, the classic undo
    mov r13d, [rip + tx_ask_dir]
    xor r15d, r15d
11: cmp r15, [rbx + TX_nparts]
    jae 3b
    imul r12, r15, TP_SIZE
    add r12, [rbx + TX_parts]
    inc r15
    and qword ptr [r12 + TP_flags], ~TPF_PICK
    cmp qword ptr [r12 + TP_kind], TPK_BUF
    jne 11b
    mov rax, [rip + tx_ask_doc]
    cmp [r12 + TP_doc], rax
    jne 11b
    or qword ptr [r12 + TP_flags], TPF_PICK
    jmp 11b
9:  mov qword ptr [rip + tx_ask_id], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# tx_run(T, dir): every participant marked TPF_PICK undone (dir 0) or redone (1): the files on
# disk first (one commit of their own, rolled back whole if the system refuses a write), then
# the buffers; a toast says what was done
tx_run:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    # disk participants of either kind (a written buffer's file goes after its buffer)
    mov rdi, rbx
    mov esi, r12d
    call ws_disk_step
    test eax, eax
    jz 9f                       # refused: nothing changed, the toast said why
    xor r13d, r13d              # participants done
    xor r14d, r14d
1:  cmp r14, [rbx + TX_nparts]
    jae 5f
    imul r15, r14, TP_SIZE
    add r15, [rbx + TX_parts]
    inc r14
    test qword ptr [r15 + TP_flags], TPF_PICK
    jz 1b
    and qword ptr [r15 + TP_flags], ~TPF_PICK
    inc r13
    mov rax, TPS_UNDONE
    test r12d, r12d
    jz 2f
    mov rax, TPS_APPLIED
2:  mov [r15 + TP_state], rax
    cmp qword ptr [r15 + TP_kind], TPK_BUF
    jne 1b
    mov dword ptr [rip + tx_local], 1
    mov rdi, [r15 + TP_doc]
    test r12d, r12d
    jnz 3f
    call doc_undo
    jmp 4f
3:  call doc_redo
4:  mov dword ptr [rip + tx_local], 0
    cmp qword ptr [r15 + TP_wrote], 0
    je 1b
    # its file again as the buffer now is (it had no unsaved changes when T wrote it)
    mov rdi, rbx
    mov rsi, r15
    mov edx, r12d
    call ws_disk_rewrite
    jmp 1b
5:  call ws_disk_done
    # "Undid 'Rename to total' in 5 files"
    lea rdi, [rip + tx_sb]
    call sb_clear
    lea rsi, [rip + .Lundid]
    test r12d, r12d
    jz 6f
    lea rsi, [rip + .Lredid]
6:  lea rdi, [rip + tx_sb]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    mov rsi, [rbx + TX_label]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lin]
    call sb_push_cstr
    lea rdi, [rip + tx_sb]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + tx_sb]
    lea rsi, [rip + .Lfiles]
    cmp r13, 1
    jne 7f
    lea rsi, [rip + .Lfile]
7:  call sb_push_cstr
    lea rdi, [rip + tx_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tx_sb + SB_ptr]
    call app_toast
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# FN tx_list_cancel(): the partial list closed unanswered: nothing changes
FN tx_list_cancel
    mov qword ptr [rip + tx_ask_id], 0
    ret

# FN tx_doc_closed(doc): a document that took part in transactions closes. A participant whose
# text was also written to disk, and whose file still holds what the transaction wrote, becomes a
# file participant (the journal has both texts); otherwise it can no longer be undone: lost
FN tx_doc_closed
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + tx_count]
    jae 9f
    imul r13, rbx, TX_SIZE
    lea rax, [rip + tx_table]
    add r13, rax
    inc rbx
    xor r14d, r14d
2:  cmp r14, [r13 + TX_nparts]
    jae 1b
    imul r15, r14, TP_SIZE
    add r15, [r13 + TX_parts]
    inc r14
    cmp qword ptr [r15 + TP_kind], TPK_BUF
    jne 2b
    cmp [r15 + TP_doc], r12
    jne 2b
    mov qword ptr [r15 + TP_doc], 0
    cmp qword ptr [r15 + TP_wrote], 0
    je 3f
    cmp qword ptr [r15 + TP_slot], 0
    jl 3f
    mov qword ptr [r15 + TP_kind], TPK_FILE
    jmp 2b
3:  mov qword ptr [r15 + TP_state], TPS_LOST
    mov qword ptr [r15 + TP_kind], TPK_FILE    # nothing points at the freed document
    jmp 2b
9:  EPILOGUE

# FN tx_last_applied(dir) -> rax the newest transaction with a participant that undo (dir 0) or
# redo (1) would move, or 0
tx_last:
    mov r8d, TPS_APPLIED
    test edi, edi
    jz 1f
    mov r8d, TPS_UNDONE
1:  mov rcx, [rip + tx_count]
2:  test rcx, rcx
    jz 8f
    dec rcx
    imul rax, rcx, TX_SIZE
    lea rdx, [rip + tx_table]
    add rax, rdx
    xor edx, edx
3:  cmp rdx, [rax + TX_nparts]
    jae 2b
    imul rsi, rdx, TP_SIZE
    add rsi, [rax + TX_parts]
    inc rdx
    cmp [rsi + TP_state], r8
    jne 3b
    ret
8:  xor eax, eax
    ret

# FN cmd_undo_workspace_edit / cmd_redo_workspace_edit: the newest multi-file edit, also when all
# of its files are closed
FN cmd_undo_workspace_edit
    xor edi, edi
    jmp tx_cmd
FN cmd_redo_workspace_edit
    mov edi, 1
tx_cmd:
    push rbx
    mov ebx, edi
    call tx_last
    test rax, rax
    jz 8f
    mov rdi, rax
    xor esi, esi                # no document asked: "this file only" is not offered
    mov edx, ebx
    call tx_step
    pop rbx
    jmp ed_touch
8:  lea rdi, [rip + .Lnone_undo]
    test ebx, ebx
    jz 9f
    lea rdi, [rip + .Lnone_redo]
9:  call app_toast
    pop rbx
    ret

# FN tx_print(sb): print-tx, the newest first: "tx=ID state=applied|undone|partial parts=N
# files=N label=TEXT", one line per transaction ("tx=none" without any)
FN tx_print
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + tx_count]
    test r12, r12
    jnz 1f
    lea rsi, [rip + .Lp_none]
    call sb_push_cstr
    EPILOGUE
1:  test r12, r12
    jz 9f
    dec r12
    imul r13, r12, TX_SIZE
    lea rax, [rip + tx_table]
    add r13, rax
    mov rdi, rbx
    lea rsi, [rip + .Lp_tx]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + TX_id]
    call sb_push_u64
    # the state: every live participant applied, undone, or a mix
    xor r14d, r14d              # bit 0 applied seen, bit 1 undone seen
    xor r15d, r15d              # files
    xor ecx, ecx
2:  cmp rcx, [r13 + TX_nparts]
    jae 3f
    imul rax, rcx, TP_SIZE
    add rax, [r13 + TX_parts]
    inc rcx
    cmp qword ptr [rax + TP_kind], TPK_BUF
    je 21f
    cmp qword ptr [rax + TP_kind], TPK_FILE
    jne 22f
21: inc r15
22: mov rdx, [rax + TP_state]
    cmp rdx, TPS_APPLIED
    jne 23f
    or r14d, 1
23: cmp rdx, TPS_UNDONE
    jne 2b
    or r14d, 2
    jmp 2b
3:  lea rsi, [rip + .Lp_applied]
    cmp r14d, 2
    jne 31f
    lea rsi, [rip + .Lp_undone]
31: cmp r14d, 3
    jne 32f
    lea rsi, [rip + .Lp_partial]
32: mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lp_parts]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + TX_nparts]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lp_files]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r15
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lp_label]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + TX_label]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lchanged1: .asciz "': "
.Lchanged2: .asciz " changed after it"
.Lchanged3: .asciz " and others changed after it"
.Lthis_undo: .asciz "Undo in this file only"
.Lthis_redo: .asciz "Redo in this file only"
.Lrest_undo: .asciz "Undo in the "
.Lrest_redo: .asciz "Redo in the "
.Lrest_tail: .asciz " files that did not change"
.Lcancel: .asciz "Cancel"
.Lundid: .asciz "Undid '"
.Lredid: .asciz "Redid '"
.Lin: .asciz "' in "
.Lfiles: .asciz " files"
.Lfile: .asciz " file"
.Lnone_undo: .asciz "No multi-file edit to undo"
.Lnone_redo: .asciz "No multi-file edit to redo"
.Lp_none: .asciz "tx=none\n"
.Lp_tx: .asciz "tx="
.Lp_applied: .asciz " state=applied"
.Lp_undone: .asciz " state=undone"
.Lp_partial: .asciz " state=partial"
.Lp_parts: .asciz " parts="
.Lp_files: .asciz " files="
.Lp_label: .asciz " label="
