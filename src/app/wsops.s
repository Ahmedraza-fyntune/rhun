# workspace edits' file operations (v1.1.md file-operations): create, rename and delete as parts of
# a transaction. Each is checked before anything changes, planned in the journal, made in phase
# order (creates, then text groups, then renames, then deletes), and undone and redone with the
# rest; an overwritten or deleted item moves into the journal folder, so it comes back. Open tabs
# follow renames (a new DOC id: extensions see the file closed and opened again); a deleted file's
# clean tab closes and comes back with undo.
.include "rhun.inc"

.equ WO_TREE_MAX, 10000         # entries a recursive delete may take (copied when it must be)

STRUCT
F FW_doc, 8                     # a tab's document that follows a rename
F FW_tail, 8                    # owned: its resolved path's part inside the renamed item ("" for it)
ENDSTRUCT FW_SIZE

.bss
.p2align 3
wo_count: .quad 0               # entries counted in a folder
wo_leaf: .quad 0                # ws_real_new keeps the last part as written (a rename's target)
wo_follow: .zero VEC_SIZE       # FW records of the rename being made
wo_steps: .zero SB_SIZE         # recovery: the plan's step lines (offsets)
wo_sb: .zero SB_SIZE
wo_a: .zero 4100                # resolved paths
wo_b: .zero 4100
wo_c: .zero 4100
wo_tmp: .zero 4100

.text

# ---------------- paths ----------------

# wo_sep(byte) -> eax 1 for a path separator
wo_sep:
    xor eax, eax
    cmp dil, '/'
    je 1f
.ifdef WINDOWS
    cmp dil, 92
    je 1f
.endif
    ret
1:  mov eax, 1
    ret

# FN ws_real_new(path, out[4096]) -> eax 1 with the path as it is or will be on disk: its nearest
# existing folder resolved (links followed), the rest as written (no "." or ".." in it); 0 when
# no part of it exists or it is too long
FN ws_real_new
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rip + wo_leaf]
    mov [rsp + 8], rax
    mov qword ptr [rip + wo_leaf], 0
    call strlen
    cmp rax, 4000
    jae 8f
    mov r13, rax                # its length
    lea rdi, [rip + wo_tmp]
    mov rsi, rbx
    call cstr_copy
    lea rbx, [rip + wo_tmp]
1:  cmp r13, 1                  # a separator at its end goes ("dir/" makes a folder: the caller knows)
    jbe 2f
    movzx edi, byte ptr [rbx + r13 - 1]
    call wo_sep
    test eax, eax
    jz 2f
    dec r13
    mov byte ptr [rbx + r13], 0
    jmp 1b
2:  mov r14, r13                # the prefix tried
    cmp qword ptr [rsp + 8], 0
    je 3f
    jmp 4f                      # its folder first: the last part stays as written
3:  movzx eax, byte ptr [rbx + r14]
    mov [rsp], al
    mov byte ptr [rbx + r14], 0
    mov rdi, rbx
    mov rsi, r12
    call ext_realpath
    mov ecx, eax
    mov al, [rsp]
    mov [rbx + r14], al
    test ecx, ecx
    jnz 5f
    # one part shorter
4:  test r14, r14
    jz 8f
    dec r14
    movzx edi, byte ptr [rbx + r14]
    call wo_sep
    test eax, eax
    jz 4b
    test r14, r14
    jnz 3b
    mov r14d, 1                 # "/" itself
    jmp 3b
5:  # the rest, after its separator
    cmp r14, r13
    jae 7f
    lea r15, [rbx + r14]        # "/a/b"
    # no "." or ".." part
    mov rcx, r15
51: movzx edi, byte ptr [rcx]
    test edi, edi
    jz 6f
    call wo_sep
    inc rcx
    test eax, eax
    jz 51b
    cmp byte ptr [rcx], '.'
    jne 51b
    movzx edi, byte ptr [rcx + 1]
    test edi, edi
    jz 8f
    call wo_sep
    test eax, eax
    jnz 8f
    cmp byte ptr [rcx + 1], '.'
    jne 51b
    movzx edi, byte ptr [rcx + 2]
    test edi, edi
    jz 8f
    call wo_sep
    test eax, eax
    jnz 8f
    jmp 51b
6:  mov rdi, r12
    call strlen
    mov rcx, rax
    test rcx, rcx
    jz 61f
    movzx edi, byte ptr [r12 + rcx - 1]
    push rcx
    push rcx
    call wo_sep
    pop rcx
    pop rcx
    test eax, eax
    jz 61f
    dec rcx                     # the root's separator and the rest's are one
61: mov rdi, r15
    push rcx
    push rcx
    call strlen
    pop rcx
    pop rcx
    lea rdx, [rcx + rax]
    cmp rdx, 4090
    jae 8f
    lea rdi, [r12 + rcx]
    mov rsi, r15
    call cstr_copy
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wo_git(real) -> eax 1 when the path is inside (or is) a .git folder
wo_git:
    push rbx
    mov rbx, rdi
1:  movzx edi, byte ptr [rbx]
    test edi, edi
    jz 8f
    call wo_sep
    inc rbx
    test eax, eax
    jz 1b
    cmp byte ptr [rbx], '.'
    jne 1b
    cmp byte ptr [rbx + 1], 'g'
    jne 1b
    cmp byte ptr [rbx + 2], 'i'
    jne 1b
    cmp byte ptr [rbx + 3], 't'
    jne 1b
    movzx edi, byte ptr [rbx + 4]
    test edi, edi
    jz 9f
    call wo_sep
    test eax, eax
    jz 1b
9:  mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# wo_project_or_above(real) -> eax 1 when the path is the project folder or a folder above it
wo_project_or_above:
    push rbx
    mov rbx, rdi
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 8f
    lea rsi, [rip + wo_c]
    call ext_realpath
    test eax, eax
    jz 8f
    lea rdi, [rip + wo_c]
    mov rsi, rbx
    call app_path_inside
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# wo_dirty_inside(path) -> eax 1 when an open document whose file is that path, or inside it when
# it is a folder, has unsaved changes
wo_dirty_inside:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    mov rdi, rbx
    inc rbx
    call tab_at
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz 1b
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rdi, [r13 + DOC_path]
    test rdi, rdi
    jz 1b
    lea rsi, [rip + wo_b]
    call ext_realpath
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_b]
    mov rsi, r12
    call app_path_inside
    test eax, eax
    jz 1b
    mov rdi, r13
    call doc_dirty
    test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wo_count_cb(ctx, name): one entry more
wo_count_cb:
    inc qword ptr [rip + wo_count]
    ret

# wo_tree_count(path) -> rax entries in the tree under a folder (stops counting past the cap)
wo_tree_count:
    PROLOGUE
    mov qword ptr [rip + wo_count], 0
    call wo_tree_count1
    mov rax, [rip + wo_count]
    EPILOGUE
wo_tree_count1:
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rip + wo_count], WO_TREE_MAX
    ja 9f
    mov rdi, rbx
    call file_is_dir
    test eax, eax
    jz 9f
    mov rdi, rbx
    lea rsi, [rip + wo_count_tree_cb]
    mov rdx, rbx
    call dir_each
9:  EPILOGUE
# wo_count_tree_cb(folder, name, is_dir): counted, and folders counted inside
wo_count_tree_cb:
    PROLOGUE
    inc qword ptr [rip + wo_count]
    test edx, edx
    jz 9f
    cmp qword ptr [rip + wo_count], WO_TREE_MAX
    ja 9f
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rdx
    call path_join_cstr
    mov rbx, rax
    mov rdi, rax
    call wo_tree_count1
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# path_join_cstr(name, folder) -> rax "folder/name" (mem_free it)
path_join_cstr:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rbx
    call path_join
    pop rbx
    ret

# wo_entries(folder) -> rax how many entries it has (0: empty)
wo_entries:
    push rbx
    mov qword ptr [rip + wo_count], 0
    lea rsi, [rip + wo_count_cb]
    xor edx, edx
    call dir_each_names
    mov rax, [rip + wo_count]
    pop rbx
    ret

# wo_same_but_case(a, b) -> eax 1 when the paths differ only in letter case (ASCII)
wo_same_but_case:
    xor ecx, ecx
    xor r8d, r8d                # a difference seen
1:  movzx eax, byte ptr [rdi + rcx]
    movzx edx, byte ptr [rsi + rcx]
    cmp eax, edx
    je 3f
    or eax, 0x20
    or edx, 0x20
    cmp eax, edx
    jne 8f
    lea r9d, [rax - 'a']
    cmp r9d, 25
    ja 8f
    mov r8d, 1
3:  test eax, eax
    jz 9f
    inc rcx
    jmp 1b
9:  mov eax, r8d
    ret
8:  xor eax, eax
    ret

# ---------------- checks before anything changes ----------------

# wo_err(reply, toast) -> eax 0
wo_err:
    call ws_err
    xor eax, eax
    ret

# FN ws_ops_resolve() -> eax 1 when every file operation can be made: paths absolute, in the
# project or the extension's state folder, not in .git, not the project or above it; creates and
# renames onto free paths unless overwrite (never a folder, never an unsaved document) or
# ignore-existing; sources present unless ignore-missing; no path named twice; nothing inside a
# folder another entry renames or deletes; 0 otherwise (ws_code says why)
FN ws_ops_resolve
    PROLOGUE 16
    xor ebx, ebx
.Lor_next:
    cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lor_names
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    mov r13, [r12 + WG_kind]
    cmp r13, WK_TEXT
    je .Lor_next
    mov rdi, r12
    xor esi, esi
    call ws_path
    test eax, eax
    jz .Lor_nofile
    lea rdi, [rip + ws_pathbuf]
    call lf_is_abs
    test eax, eax
    jz .Lor_nofile
    # a create of "dir/" makes a folder
    cmp r13, WK_CREATE
    jne 1f
    mov rcx, [r12 + WG_plen]
    lea rax, [rip + ws_pathbuf]
    movzx edi, byte ptr [rax + rcx - 1]
    call wo_sep
    mov [r12 + WG_folder], rax
1:  lea rdi, [rip + ws_pathbuf]
    lea rsi, [rip + wo_a]
    call ws_real_new
    test eax, eax
    jz .Lor_refused
    lea rdi, [rip + wo_a]
    call ws_inside
    test eax, eax
    jz .Lor_needs
    lea rdi, [rip + wo_a]
    call wo_git
    test eax, eax
    jnz .Lor_refused
    lea rdi, [rip + wo_a]
    call dup_cstr
    mov [r12 + WG_real], rax
    cmp r13, WK_CREATE
    je .Lor_create
    cmp r13, WK_RENAME
    je .Lor_rename
    # delete: present, or skipped with ignore-missing
    lea rdi, [rip + wo_a]
    call file_missing
    test eax, eax
    jz 2f
    test qword ptr [r12 + WG_flags], WF_IGNORE_MISSING
    jz .Lor_nofile
    mov qword ptr [r12 + WG_skip], 1
    jmp .Lor_next
2:  lea rdi, [rip + wo_a]
    call wo_project_or_above
    test eax, eax
    jnz .Lor_refused
    lea rdi, [rip + wo_a]
    call wo_dirty_inside
    test eax, eax
    jnz .Lor_refused
    lea rdi, [rip + wo_a]
    call file_is_dir
    mov [r12 + WG_folder], rax
    test eax, eax
    jz .Lor_next
    lea rdi, [rip + wo_a]
    call wo_tree_count
    cmp rax, WO_TREE_MAX
    ja .Lor_big
    test rax, rax
    jz .Lor_next
    test qword ptr [r12 + WG_flags], WF_RECURSIVE
    jz .Lor_refused             # a folder with things in it needs recursive
    jmp .Lor_next
.Lor_create:
    lea rdi, [rip + wo_a]
    call file_missing
    test eax, eax
    jnz .Lor_next               # free
    lea rdi, [rip + wo_a]
    call file_is_dir
    test eax, eax
    jz 3f
    cmp qword ptr [r12 + WG_folder], 0
    je .Lor_refused             # a file where a folder is
    mov qword ptr [r12 + WG_skip], 1    # the folder is there already
    jmp .Lor_next
3:  cmp qword ptr [r12 + WG_folder], 0
    jne .Lor_exists
    test qword ptr [r12 + WG_flags], WF_OVERWRITE
    jnz 4f
    test qword ptr [r12 + WG_flags], WF_IGNORE_EXISTING
    jz .Lor_exists
    mov qword ptr [r12 + WG_skip], 1
    jmp .Lor_next
4:  lea rdi, [rip + wo_a]
    call wo_dirty_inside
    test eax, eax
    jnz .Lor_refused
    mov qword ptr [r12 + WG_exists], 1
    jmp .Lor_next
.Lor_rename:
    lea rdi, [rip + wo_a]
    call file_missing
    test eax, eax
    jnz .Lor_nofile
    lea rdi, [rip + wo_a]
    call wo_project_or_above
    test eax, eax
    jnz .Lor_refused
    lea rdi, [rip + wo_a]
    call file_is_dir
    mov [r12 + WG_folder], rax
    mov rdi, r12
    mov esi, 1
    call ws_path
    test eax, eax
    jz .Lor_nofile
    lea rdi, [rip + ws_pathbuf]
    call lf_is_abs
    test eax, eax
    jz .Lor_nofile
    mov qword ptr [rip + wo_leaf], 1    # "Util.go" for "util.go" on a case-insensitive volume
    lea rdi, [rip + ws_pathbuf]
    lea rsi, [rip + wo_b]
    call ws_real_new
    test eax, eax
    jz .Lor_refused
    lea rdi, [rip + wo_b]
    call ws_inside
    test eax, eax
    jz .Lor_needs
    lea rdi, [rip + wo_b]
    call wo_git
    test eax, eax
    jnz .Lor_refused
    lea rdi, [rip + wo_b]
    call dup_cstr
    mov [r12 + WG_real2], rax
    # into itself?
    mov rdi, [r12 + WG_real2]
    mov rsi, [r12 + WG_real]
    call app_path_inside
    test eax, eax
    jnz .Lor_refused
    # the same volume: the source's device and the target's nearest existing folder's
    mov rdi, [r12 + WG_real]
    call file_id
    mov [rsp], rdx
    mov rdi, [r12 + WG_real2]
    call wo_parent_dev
    cmp rax, [rsp]
    jne .Lor_refused
    mov rdi, [r12 + WG_real2]
    call file_missing
    test eax, eax
    jnz .Lor_next               # free
    # the target exists: the same file in another letter case, or another file
    mov rdi, [r12 + WG_real]
    call file_id
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, [r12 + WG_real2]
    call file_id
    cmp rax, [rsp]
    jne 5f
    cmp rdx, [rsp + 8]
    jne 5f
    mov rdi, [r12 + WG_real]
    mov rsi, [r12 + WG_real2]
    call wo_same_but_case
    test eax, eax
    jz .Lor_refused             # a hard link, or the same name
    mov qword ptr [r12 + WG_case], 1
    jmp .Lor_next
5:  test qword ptr [r12 + WG_flags], WF_OVERWRITE
    jnz 6f
    test qword ptr [r12 + WG_flags], WF_IGNORE_EXISTING
    jz .Lor_exists
    mov qword ptr [r12 + WG_skip], 1
    jmp .Lor_next
6:  mov rdi, [r12 + WG_real2]
    call file_is_dir
    test eax, eax
    jnz .Lor_refused            # a folder is never replaced
    mov rdi, [r12 + WG_real2]
    call wo_dirty_inside
    test eax, eax
    jnz .Lor_refused
    mov qword ptr [r12 + WG_exists], 1
    jmp .Lor_next
.Lor_names:
    # no path named twice; nothing inside a folder another entry renames or deletes
    xor ebx, ebx
7:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lor_ok
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    je 7b
    xor r13d, r13d              # (skipped entries count too: one path, one entry)
71: cmp r13, [rip + wg_vec + VEC_len]
    jae 7b
    imul r14, r13, WG_SIZE
    add r14, [rip + wg_vec + VEC_ptr]
    inc r13
    cmp r14, r12
    je 71b
    cmp qword ptr [r14 + WG_kind], WK_TEXT
    je 71b
    # r12's paths against r14's: equal ones, or r12's inside r14's renamed or deleted one
    mov rdi, [r12 + WG_real]
    mov rsi, r14
    call wo_clash
    test eax, eax
    jnz .Lor_refused
    mov rdi, [r12 + WG_real2]
    test rdi, rdi
    jz 71b
    mov rsi, r14
    call wo_clash
    test eax, eax
    jnz .Lor_refused
    jmp 71b
.Lor_ok:
    mov qword ptr [rip + ws_entry], 0
    mov eax, 1
    EPILOGUE
.Lor_nofile:
    lea rdi, [rip + .Lwc_nofile]
    lea rsi, [rip + .Lws_e_op]
    call wo_err
    EPILOGUE
.Lor_needs:
    lea rdi, [rip + .Lwc_needs]
    lea rsi, [rip + .Lws_e_needs]
    call wo_err
    EPILOGUE
.Lor_exists:
    lea rdi, [rip + .Lwc_exists]
    lea rsi, [rip + .Lws_e_op]
    call wo_err
    EPILOGUE
.Lor_big:
    lea rdi, [rip + .Lwc_big]
    lea rsi, [rip + .Lws_e_op]
    call wo_err
    EPILOGUE
.Lor_refused:
    lea rdi, [rip + .Lwc_refused]
    lea rsi, [rip + .Lws_e_op]
    call wo_err
    EPILOGUE

# wo_clash(path, WG* other op) -> eax 1 when the path is one of the other's paths, or lies inside
# what it renames (its source) or deletes
wo_clash:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, [r12 + WG_real]
    call strcmp_eq
    test eax, eax
    jnz 9f
    mov rsi, [r12 + WG_real2]
    test rsi, rsi
    jz 1f
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jnz 9f
1:  cmp qword ptr [r12 + WG_kind], WK_CREATE
    je 8f
    mov rdi, rbx
    mov rsi, [r12 + WG_real]
    call app_path_inside
    test eax, eax
    jnz 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# wo_parent_dev(path) -> rax the device of its nearest existing folder
wo_parent_dev:
    PROLOGUE
    lea rbx, [rip + wo_c]
    mov rsi, rdi
    mov rdi, rbx
    call cstr_copy
    mov rdi, rbx
    call strlen
    mov r12, rax
1:  test r12, r12
    jz 8f
    dec r12
    movzx edi, byte ptr [rbx + r12]
    call wo_sep
    test eax, eax
    jz 1b
    mov byte ptr [rbx + r12], 0
    test r12, r12
    jnz 2f
    mov word ptr [rbx], '/'
2:  mov rdi, rbx
    call file_id
    test rax, rax
    jz 1b
    mov rax, rdx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_ops_textcheck() -> eax 1 when no text group names a path an entry deletes (or a file inside
# a deleted folder) or a rename's target: text groups run before renames and deletes, so they may
# name a rename's source
FN ws_ops_textcheck
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 1b
    cmp qword ptr [r12 + WG_created], 0
    jne 1b
    mov r13, [r12 + WG_real]
    test r13, r13
    jnz 2f
    # an open document outside where the extension may write is not on disk's side of the edit
    jmp 1b
2:  xor r14d, r14d
3:  cmp r14, [rip + wg_vec + VEC_len]
    jae 1b
    imul r15, r14, WG_SIZE
    add r15, [rip + wg_vec + VEC_ptr]
    inc r14
    cmp qword ptr [r15 + WG_skip], 0
    jne 3b
    cmp qword ptr [r15 + WG_kind], WK_DELETE
    jne 4f
    mov rdi, r13
    mov rsi, [r15 + WG_real]
    call app_path_inside
    test eax, eax
    jnz 9f
    jmp 3b
4:  cmp qword ptr [r15 + WG_kind], WK_RENAME
    jne 3b
    mov rdi, r13
    mov rsi, [r15 + WG_real2]
    call strcmp_eq
    test eax, eax
    jnz 9f
    jmp 3b
8:  mov qword ptr [rip + ws_entry], 0
    mov eax, 1
    EPILOGUE
9:  lea rdi, [rip + .Lwc_refused]
    lea rsi, [rip + .Lws_e_op]
    call wo_err
    EPILOGUE

# FN ws_ops_created(WG*) -> eax 1 when the text group's file is one an earlier create makes: its
# document is a hidden empty one (written after the create)
FN ws_ops_created
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    xor esi, esi
    call ws_path
    test eax, eax
    jz 8f
    lea rdi, [rip + ws_pathbuf]
    lea rsi, [rip + wo_a]
    call ws_real_new
    test eax, eax
    jz 8f
    xor r12d, r12d
1:  cmp r12, [rip + wg_vec + VEC_len]
    jae 8f
    imul r13, r12, WG_SIZE
    add r13, [rip + wg_vec + VEC_ptr]
    inc r12
    cmp r13, rbx
    jae 8f                      # an earlier one
    cmp qword ptr [r13 + WG_kind], WK_CREATE
    jne 1b
    cmp qword ptr [r13 + WG_skip], 0
    jne 1b
    cmp qword ptr [r13 + WG_folder], 0
    jne 1b
    mov rdi, [r13 + WG_real]
    lea rsi, [rip + wo_a]
    call strcmp_eq
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_a]
    call dup_cstr
    mov [rbx + WG_real], rax
    mov qword ptr [rbx + WG_created], 1
    mov qword ptr [rbx + WG_olen], 0
    lea rdi, [rip + .Lempty]
    xor esi, esi
    call mem_dup
    mov [rbx + WG_orig], rax
    mov rax, 0xcbf29ce484222325 # FNV-1a of nothing
    mov [rbx + WG_before], rax
    call doc_new
    mov [rbx + WG_doc], rax
    mov qword ptr [rbx + WG_hidden], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_ops_recheck() -> eax 1 when the file operations' paths are still as the edit found them
# (it waited for the user): sources there, free targets free
FN ws_ops_recheck
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    je 1b
    cmp qword ptr [r12 + WG_skip], 0
    jne 1b
    mov rdi, [r12 + WG_real]
    call file_missing
    cmp qword ptr [r12 + WG_kind], WK_CREATE
    jne 2f
    xor eax, 1                  # a create's path: free unless it overwrites
    xor eax, [r12 + WG_exists]
    jmp 3f
2:  test eax, eax               # a rename's or delete's source: there
    jnz 9f
    cmp qword ptr [r12 + WG_kind], WK_RENAME
    jne 1b
    cmp qword ptr [r12 + WG_case], 0
    jne 1b
    mov rdi, [r12 + WG_real2]
    call file_missing
    xor eax, 1
    xor eax, [r12 + WG_exists]
3:  test eax, eax
    jnz 9f
    jmp 1b
8:  mov qword ptr [rip + ws_entry], 0
    mov eax, 1
    EPILOGUE
9:  lea rdi, [rip + .Lwc_stale]
    lea rsi, [rip + .Lws_e_stale]
    call wo_err
    EPILOGUE

# ---------------- the journal ----------------

# wo_plan(word, slot, flags, path, path2 or 0): "WORD SLOT+1 FLAGS LEN1 LEN2" and the two paths
# on lines of their own (recovery reads them)
wo_plan:
    PROLOGUE
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
    lea rsi, [r12 + 1]
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + wd_plan]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r14
    call strlen
    lea rdi, [rip + wd_plan]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, ' '
    call sb_push_byte
    xor eax, eax
    test r15, r15
    jz 1f
    mov rdi, r15
    call strlen
1:  lea rdi, [rip + wd_plan]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + wd_plan]
    mov rsi, r14
    call sb_push_cstr
    lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    test r15, r15
    jz 2f
    lea rdi, [rip + wd_plan]
    mov rsi, r15
    call sb_push_cstr
2:  lea rdi, [rip + wd_plan]
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# FN ws_ops_plan(T) -> rax 0: the file operations' participants, and their steps in the plan
FN ws_ops_plan
    PROLOGUE
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov rax, [r12 + WG_kind]
    cmp rax, WK_TEXT
    je 1b
    cmp qword ptr [r12 + WG_skip], 0
    jne 1b
    mov esi, TPK_CREATE
    lea r14, [rip + .Lk_create]
    cmp rax, WK_CREATE
    je 2f
    mov esi, TPK_RENAME
    lea r14, [rip + .Lk_rename]
    cmp rax, WK_RENAME
    je 2f
    mov esi, TPK_DELETE
    lea r14, [rip + .Lk_delete]
2:  mov rdi, r15
    call tx_add
    mov r13, rax
    mov rdi, [r12 + WG_real]
    call dup_cstr
    mov [r13 + TP_path], rax
    mov rdi, [r12 + WG_real2]
    test rdi, rdi
    jz 3f
    call dup_cstr
    mov [r13 + TP_path2], rax
3:  xor eax, eax
    cmp qword ptr [r12 + WG_folder], 0
    je 31f
    or eax, TPF_FOLDER
31: cmp qword ptr [r12 + WG_case], 0
    je 32f
    or eax, TPF_CASE
32: cmp qword ptr [r12 + WG_exists], 0
    je 33f
    or eax, TPF_OVER
33: mov [r13 + TP_flags], rax
    mov rax, 0xcbf29ce484222325 # a created file is empty
    mov [r13 + TP_after], rax
    # a slot for what moves into the journal: an overwritten target, a deleted item
    test qword ptr [r13 + TP_flags], TPF_OVER
    jnz 4f
    cmp qword ptr [r13 + TP_kind], TPK_DELETE
    jne 5f
4:  mov rax, [rip + wd_slot]
    inc qword ptr [rip + wd_slot]
    mov [r13 + TP_slot], rax
5:  mov rdi, r14
    mov rsi, [r13 + TP_slot]
    mov rdx, [r13 + TP_flags]
    mov rcx, [r13 + TP_path]
    mov r8, [r13 + TP_path2]
    call wo_plan
    jmp 1b
8:  xor eax, eax
    EPILOGUE

# wo_out(T, slot, path, suffix) -> rax 0 or -errno: the item moves into the journal (a rename, or a
# copy and removal when the journal is on another volume)
wo_out:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdx, rcx
    call wd_jpath
    mov rdi, rax
    call dup_cstr
    mov r14, rax                # where it goes
    mov rdi, r13
    mov rsi, r14
    SYS SYS_rename
    test rax, rax
    jns 8f
    mov rdi, r13
    mov rsi, r14
    call wo_copy
    test rax, rax
    js 8f
    mov rdi, r13
    call file_remove_tree
8:  mov r15, rax
    mov rdi, r14
    call mem_free
    mov rax, r15
    EPILOGUE

# wo_in(T, slot, path, suffix) -> rax 0 or -errno: the item comes back from the journal
wo_in:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdx, rcx
    call wd_jpath
    mov rdi, rax
    call dup_cstr
    mov r14, rax
    mov rdi, r13
    call mkdir_parent
    mov rdi, r13
    call file_missing
    test eax, eax
    jz 7f                       # something is in its way
    mov rdi, r14
    mov rsi, r13
    SYS SYS_rename
    test rax, rax
    jns 8f
    mov rdi, r14
    mov rsi, r13
    call wo_copy
    test rax, rax
    js 8f
    mov rdi, r14
    call file_remove_tree
    xor eax, eax
    jmp 8f
7:  mov rax, -17                # EEXIST
8:  mov r15, rax
    mov rdi, r14
    call mem_free
    mov rax, r15
    EPILOGUE

# wo_copy(src, dst) -> rax 0 or -errno: a file's bytes, or a folder and everything in it
wo_copy:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call file_is_dir
    test eax, eax
    jnz 2f
    mov rdi, rbx
    mov esi, 67108864
    call file_read_limited
    test rax, rax
    jz 7f
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    call file_write_all
    mov r14, rax
    mov rdi, r13
    call mem_free
    mov rax, r14
    EPILOGUE
2:  mov rdi, r12
    mov esi, 0755
    SYS SYS_mkdir
    mov [rsp], rbx
    mov [rsp + 8], r12
    mov rdi, rbx
    lea rsi, [rip + wo_copy_cb]
    mov rdx, rsp
    call dir_each_names
    test rax, rax
    js 9f
    xor eax, eax
    EPILOGUE
7:  mov rax, rdx
    test rax, rax
    js 9f
    mov rax, -5
9:  EPILOGUE
# wo_copy_cb(ctx [src, dst], name): one entry copied
wo_copy_cb:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx]
    mov rsi, r12
    call path_join
    mov r13, rax
    mov rdi, [rbx + 8]
    mov rsi, r12
    call path_join
    mov r14, rax
    mov rdi, r13
    mov rsi, r14
    call wo_copy
    mov rdi, r13
    call mem_free
    mov rdi, r14
    call mem_free
    EPILOGUE

# ---------------- making them ----------------

# wo_create(T, TP) -> rax 0 or -errno: a create made (an overwritten file into the journal first)
wo_create:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test qword ptr [r12 + TP_flags], TPF_OVER
    jz 1f
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, [r12 + TP_path]
    lea rcx, [rip + .Lover]
    call wo_out
    test rax, rax
    js 9f
1:  mov rdi, [r12 + TP_path]
    call mkdir_parent
    test qword ptr [r12 + TP_flags], TPF_FOLDER
    jz 2f
    mov rdi, [r12 + TP_path]
    mov esi, 0755
    SYS SYS_mkdir
    jmp 3f
2:  mov rdi, [r12 + TP_path]
    mov esi, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
    mov edx, 0644
    SYS SYS_open
    test rax, rax
    js 9f
    mov edi, eax
    SYS SYS_close
3:  test rax, rax
    js 9f
    xor eax, eax
9:  EPILOGUE

# wo_uncreate(T, TP) -> rax 0 or -errno: a create undone (an overwritten file back)
wo_uncreate:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test qword ptr [r12 + TP_flags], TPF_FOLDER
    jz 1f
    mov rdi, [r12 + TP_path]
    mov eax, 84                 # rmdir: only an empty folder
    XSYS
    jmp 2f
1:  mov rdi, [r12 + TP_path]
    SYS SYS_unlink
2:  test rax, rax
    js 9f
    test qword ptr [r12 + TP_flags], TPF_OVER
    jz 8f
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, [r12 + TP_path]
    lea rcx, [rip + .Lover]
    call wo_in
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# wo_move(T, TP, dir) -> rax 0 or -errno: a rename made (dir 1: FROM to TO, an overwritten target
# into the journal first) or undone (dir 0: TO back to FROM, the overwritten target back); the tabs
# follow
wo_move:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, [r12 + TP_path]    # from
    mov r15, [r12 + TP_path2]   # to
    test r13d, r13d
    jnz 1f
    xchg r14, r15
    jmp 2f
1:  test qword ptr [r12 + TP_flags], TPF_OVER
    jz 2f
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, r15
    lea rcx, [rip + .Lover]
    call wo_out
    test rax, rax
    js 9f
2:  mov rdi, r14
    call wo_follow_collect
    mov rdi, r15
    call mkdir_parent
    test qword ptr [r12 + TP_flags], TPF_CASE
    jz 3f
    # letter case only: through a name of its own (a case-insensitive volume sees one name)
    lea rdi, [rip + wo_tmp]
    mov rsi, r14
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Lcase_tmp]
    call cstr_copy
    mov rdi, r14
    lea rsi, [rip + wo_tmp]
    SYS SYS_rename
    test rax, rax
    js 9f
    lea rdi, [rip + wo_tmp]
    mov rsi, r15
    SYS SYS_rename
    test rax, rax
    jns 4f
    mov [rsp], rax
    lea rdi, [rip + wo_tmp]
    mov rsi, r14
    SYS SYS_rename
    mov rax, [rsp]
    jmp 9f
3:  mov rdi, r15
    call file_missing
    test eax, eax
    jz 8f                       # never over something that appeared meanwhile
    mov rdi, r14
    mov rsi, r15
    SYS SYS_rename
    test rax, rax
    js 9f
4:  mov rdi, r15
    call wo_follow_apply
    test r13d, r13d
    jnz 7f
    # undone: an overwritten target comes back
    test qword ptr [r12 + TP_flags], TPF_OVER
    jz 7f
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, r14                # (TO, now that it is free again)
    lea rcx, [rip + .Lover]
    call wo_in
    jmp 9f
7:  xor eax, eax
    jmp 9f
8:  mov rax, -17
9:  EPILOGUE

# wo_delete(T, TP) -> rax 0 or -errno: a delete made: clean tabs of it close, it moves into the
# journal
wo_delete:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call wo_close_tabs
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, [r12 + TP_path]
    lea rcx, [rip + .Lgone]
    call wo_out
    EPILOGUE

# wo_undelete(T, TP) -> rax 0 or -errno: a delete undone: the item back from the journal, a tab
# that closed with it open again
wo_undelete:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, [r12 + TP_slot]
    mov rdx, [r12 + TP_path]
    lea rcx, [rip + .Lgone]
    call wo_in
    test rax, rax
    js 9f
    test qword ptr [r12 + TP_flags], TPF_HADTAB
    jz 8f
    and qword ptr [r12 + TP_flags], ~TPF_HADTAB
    mov rax, [rip + g_tab_cur]
    mov r13, rax
    mov rdi, [r12 + TP_path]
    call app_open_file
    test r13, r13
    js 8f
    mov rdi, r13
    call app_activate_tab       # the user stays where they were
8:  xor eax, eax
9:  EPILOGUE

# wo_close_tabs(TP): the clean tabs of a deleted item close (they were checked to be clean); a
# file's own tab is remembered (TPF_HADTAB)
wo_close_tabs:
    PROLOGUE
    mov r14, rdi
    mov rbx, [rip + g_tabs + VEC_len]
1:  test rbx, rbx
    jz 9f
    dec rbx
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 1b
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz 1b
    lea rsi, [rip + wo_b]
    call ext_realpath
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_b]
    mov rsi, [r14 + TP_path]
    call app_path_inside
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_b]
    mov rsi, [r14 + TP_path]
    call strcmp_eq
    test eax, eax
    jz 2f
    or qword ptr [r14 + TP_flags], TPF_HADTAB
2:  mov rdi, rbx
    call app_close_tab_now
    jmp 1b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# wo_follow_collect(from): the open documents whose files are, or are inside, what a rename moves
wo_follow_collect:
    PROLOGUE
    mov r14, rdi
    mov qword ptr [rip + wo_follow + VEC_len], 0
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    inc rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 1b
    mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz 1b
    lea rsi, [rip + wo_b]
    call ext_realpath
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_b]
    mov rsi, r14
    call app_path_inside
    test eax, eax
    jz 1b
    lea rdi, [rip + wo_b]
    add rdi, rdx                # its part inside from
    call dup_cstr
    mov r13, rax
    lea rdi, [rip + wo_follow]
    mov esi, FW_SIZE
    call vec_push
    mov [rax + FW_doc], r12
    mov [rax + FW_tail], r13
    jmp 1b
9:  EPILOGUE

# wo_follow_apply(to): the documents collected take their paths under to, each with a new id (a
# reopened file for extensions) and its language detected again
wo_follow_apply:
    PROLOGUE
    mov r14, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + wo_follow + VEC_len]
    jae 9f
    imul r12, rbx, FW_SIZE
    add r12, [rip + wo_follow + VEC_ptr]
    inc rbx
    mov r13, [r12 + FW_doc]
    lea rdi, [rip + wo_sb]
    call sb_clear
    lea rdi, [rip + wo_sb]
    mov rsi, r14
    call sb_push_cstr
    lea rdi, [rip + wo_sb]
    mov rsi, [r12 + FW_tail]
    call sb_push_cstr
    lea rdi, [rip + wo_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [r12 + FW_tail]
    call mem_free
    mov rdi, r13
    mov rsi, [rip + wo_sb + SB_ptr]
    call doc_set_path
    mov rdi, r13
    call doc_renew_id
    mov rdi, r13
    call app_detect_lang
    jmp 1b
9:  mov qword ptr [rip + wo_follow + VEC_len], 0
    call app_update_title
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- the phases of a commit ----------------

# FN ws_ops_creates(T) -> rax 0 or -errno: the creates made
FN ws_ops_creates
    PROLOGUE
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [r15 + TX_nparts]
    jae 8f
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    inc rbx
    cmp qword ptr [r12 + TP_kind], TPK_CREATE
    jne 1b
    mov rdi, r15
    mov rsi, r12
    call wo_create
    test rax, rax
    js 9f
    or qword ptr [r12 + TP_flags], TPF_DONE
    call wd_step
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# FN ws_ops_moves(T) -> rax 0 or -errno: the renames, then the deletes, made
FN ws_ops_moves
    PROLOGUE
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [r15 + TX_nparts]
    jae 2f
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    inc rbx
    cmp qword ptr [r12 + TP_kind], TPK_RENAME
    jne 1b
    mov rdi, r15
    mov rsi, r12
    mov edx, 1
    call wo_move
    test rax, rax
    js 9f
    or qword ptr [r12 + TP_flags], TPF_DONE
    call wd_step
    jmp 1b
2:  xor ebx, ebx
3:  cmp rbx, [r15 + TX_nparts]
    jae 8f
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    inc rbx
    cmp qword ptr [r12 + TP_kind], TPK_DELETE
    jne 3b
    mov rdi, r15
    mov rsi, r12
    call wo_delete
    test rax, rax
    js 9f
    or qword ptr [r12 + TP_flags], TPF_DONE
    call wd_step
    jmp 3b
8:  xor eax, eax
9:  EPILOGUE

# FN ws_ops_undo_moves(T) -> rax the steps that could not be put back: the deletes and renames a
# failed commit made, newest first
FN ws_ops_undo_moves
    PROLOGUE
    mov r15, rdi
    xor r14d, r14d
    mov rbx, [r15 + TX_nparts]
1:  test rbx, rbx
    jz 8f
    dec rbx
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    test qword ptr [r12 + TP_flags], TPF_DONE
    jz 1b
    mov rdi, r15
    mov rsi, r12
    cmp qword ptr [r12 + TP_kind], TPK_DELETE
    jne 2f
    call wo_undelete
    jmp 3f
2:  cmp qword ptr [r12 + TP_kind], TPK_RENAME
    jne 1b
    xor edx, edx
    call wo_move
3:  and qword ptr [r12 + TP_flags], ~TPF_DONE
    test rax, rax
    jns 1b
    inc r14
    jmp 1b
8:  mov rax, r14
    EPILOGUE

# FN ws_ops_undo_creates(T) -> rax the steps that could not be put back: a failed commit's creates
FN ws_ops_undo_creates
    PROLOGUE
    mov r15, rdi
    xor r14d, r14d
    mov rbx, [r15 + TX_nparts]
1:  test rbx, rbx
    jz 8f
    dec rbx
    imul r12, rbx, TP_SIZE
    add r12, [r15 + TX_parts]
    cmp qword ptr [r12 + TP_kind], TPK_CREATE
    jne 1b
    test qword ptr [r12 + TP_flags], TPF_DONE
    jz 1b
    and qword ptr [r12 + TP_flags], ~TPF_DONE
    mov rdi, r15
    mov rsi, r12
    call wo_uncreate
    test rax, rax
    jns 1b
    inc r14
    jmp 1b
8:  mov rax, r14
    EPILOGUE

# FN ws_ops_done(): after file operations: the explorer catches up
FN ws_ops_done
    push rbx
    call explorer_refresh
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# ---------------- undo and redo ----------------

# FN ws_ops_map(T, path) -> rax where the path is while T is applied: moved by T's renames (in a
# buffer of its own until the next call), or the path itself
FN ws_ops_map
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, [rbx + TX_nparts]
    jae 9f
    imul r14, r13, TP_SIZE
    add r14, [rbx + TX_parts]
    inc r13
    cmp qword ptr [r14 + TP_kind], TPK_RENAME
    jne 1b
    mov rdi, r12
    mov rsi, [r14 + TP_path]
    call app_path_inside
    test eax, eax
    jz 1b
    lea r15, [r12 + rdx]        # its part inside the renamed item
    lea rdi, [rip + wo_c]
    mov rsi, [r14 + TP_path2]
    call cstr_copy
    mov rdi, rax
    mov rsi, r15
    call cstr_copy
    lea r12, [rip + wo_c]
    lea rdi, [rip + wo_tmp]     # (wo_c is reused for the next rename)
    mov rsi, r12
    call cstr_copy
    lea r12, [rip + wo_tmp]
    jmp 1b
9:  mov rax, r12
    EPILOGUE

# FN ws_ops_ready(T, TP, dir) -> eax 1 when a file operation can be undone (dir 0) or redone (1):
# a create's path holds what it made (an empty file, or a folder); a rename's target is there and
# its source free (or the other way round); a deleted path is free (or there again)
FN ws_ops_ready
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rax, [r12 + TP_kind]
    cmp rax, TPK_CREATE
    je .Loy_create
    cmp rax, TPK_RENAME
    je .Loy_rename
    # delete
    mov rdi, [r12 + TP_path]
    call file_missing
    test r13d, r13d
    jz 9f                       # undo: free
    xor eax, 1                  # redo: there
    jmp 9f
.Loy_create:
    mov rdi, [r12 + TP_path]
    call file_missing
    test r13d, r13d
    jnz 9f                      # redo: free
    test eax, eax
    jnz 8f
    test qword ptr [r12 + TP_flags], TPF_FOLDER
    jnz 7f
    # a file: as made, unless a text group of T wrote it (that one's own check covers it)
    mov rdi, rbx
    mov rsi, [r12 + TP_path]
    call wo_written_by
    test eax, eax
    jnz 7f
    mov rdi, [r12 + TP_path]
    call ws_file_hash
    test edx, edx
    jz 8f
    cmp rax, [r12 + TP_after]
    jne 8f
7:  mov eax, 1
    jmp 9f
.Loy_rename:
    mov r14, [r12 + TP_path]
    mov r15, [r12 + TP_path2]
    test r13d, r13d
    jnz 1f
    xchg r14, r15
1:  mov rdi, r14                # what moves: there
    call file_missing
    test eax, eax
    jnz 8f
    test qword ptr [r12 + TP_flags], TPF_CASE
    jnz 7b
    mov rdi, r15                # where it goes: free
    call file_missing
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# FN ws_ops_creates_path(T, path) -> eax 1 when T creates that file
FN ws_ops_creates_path
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, [rbx + TX_nparts]
    jae 8f
    imul r14, r13, TP_SIZE
    add r14, [rbx + TX_parts]
    inc r13
    cmp qword ptr [r14 + TP_kind], TPK_CREATE
    jne 1b
    mov rdi, [r14 + TP_path]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wo_written_by(T, path) -> eax 1 when a file participant of T writes that path
wo_written_by:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, [rbx + TX_nparts]
    jae 8f
    imul r14, r13, TP_SIZE
    add r14, [rbx + TX_parts]
    inc r13
    cmp qword ptr [r14 + TP_kind], TPK_FILE
    jne 1b
    mov rdi, [r14 + TP_path]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wo_step_kinds(T, dir, kinds mask): the picked file operations of those kinds undone (dir 0,
# newest first) or redone (dir 1, oldest first) -> eax 1, 0 when one failed (a toast says so)
wo_step_kinds:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], rdx
    mov r13, [rbx + TX_nparts]
    xor r14d, r14d
1:  test r12d, r12d
    jnz 2f
    test r13, r13               # undo: newest first
    jz 8f
    dec r13
    mov r15, r13
    jmp 3f
2:  cmp r14, [rbx + TX_nparts]  # redo: oldest first
    jae 8f
    mov r15, r14
    inc r14
3:  imul r15, r15, TP_SIZE
    add r15, [rbx + TX_parts]
    test qword ptr [r15 + TP_flags], TPF_PICK
    jz 1b
    mov rcx, [r15 + TP_kind]
    mov eax, 1
    shl eax, cl
    test eax, [rsp]
    jz 1b
    mov rdi, rbx
    mov rsi, r15
    mov rax, [r15 + TP_kind]
    cmp rax, TPK_CREATE
    jne 4f
    test r12d, r12d
    jnz 31f
    call wo_uncreate
    jmp 6f
31: call wo_create
    jmp 6f
4:  cmp rax, TPK_RENAME
    jne 5f
    mov edx, r12d
    call wo_move
    jmp 6f
5:  test r12d, r12d
    jnz 51f
    call wo_undelete
    jmp 6f
51: call wo_delete
6:  test rax, rax
    jns 1b
    mov rdi, r15
    call wd_cannot
    xor eax, eax
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# FN ws_ops_step_first(T, dir) -> eax 1: before the files' bytes: on undo the deletes and renames
# go back; on redo the creates are made again
FN ws_ops_step_first
    mov edx, (1 << TPK_DELETE) | (1 << TPK_RENAME)
    test esi, esi
    jz wo_step_kinds
    mov edx, 1 << TPK_CREATE
    jmp wo_step_kinds

# FN ws_ops_step_last(T, dir) -> eax 1: after the files' bytes: on undo the creates go; on redo the
# renames and deletes are made again
FN ws_ops_step_last
    PROLOGUE
    mov edx, 1 << TPK_CREATE
    test esi, esi
    jz 1f
    mov edx, (1 << TPK_DELETE) | (1 << TPK_RENAME)
1:  call wo_step_kinds
    push rax
    push rax
    call ws_ops_done
    pop rax
    pop rax
    EPILOGUE

# ---------------- the confirmation list and the preview ----------------

# FN ws_ops_summary(sb): ", creates N, renames N, deletes N" for the kinds there are
FN ws_ops_summary
    PROLOGUE
    mov r15, rdi
    lea r14, [rip + wo_words]
    mov r13d, WK_CREATE
1:  cmp r13d, WK_DELETE
    ja 9f
    xor ebx, ebx                # how many
    xor ecx, ecx
2:  cmp rcx, [rip + wg_vec + VEC_len]
    jae 3f
    imul rax, rcx, WG_SIZE
    add rax, [rip + wg_vec + VEC_ptr]
    inc rcx
    cmp [rax + WG_kind], r13
    jne 2b
    cmp qword ptr [rax + WG_skip], 0
    jne 2b
    inc rbx
    jmp 2b
3:  test rbx, rbx
    jz 4f
    mov rdi, r15
    mov rsi, [r14 + r13*8 - 8]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, rbx
    call sb_push_u64
4:  inc r13d
    jmp 1b
9:  EPILOGUE

# FN ws_ops_row(WG*, sb): a file operation's row: "C  path", "R  from → to", "D  path" (a skipped
# one: nothing)
FN ws_ops_row
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + WG_skip], 0
    jne 9f
    mov rax, [rbx + WG_kind]
    lea rsi, [rip + .Lrow_c]
    cmp rax, WK_CREATE
    je 1f
    lea rsi, [rip + .Lrow_r]
    cmp rax, WK_RENAME
    je 1f
    lea rsi, [rip + .Lrow_d]
1:  mov rdi, r12
    call sb_push_cstr
    mov rdi, [rbx + WG_real]
    call ws_rel
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, [rbx + WG_real2]
    test rdi, rdi
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Larrow]
    call sb_push_cstr
    mov rdi, [rbx + WG_real2]
    call ws_rel
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
9:  EPILOGUE

# FN ws_ops_preview(WG*, sb): a file operation in the preview: a hunk header line saying what
# happens to it ("@@ -0,0 +0,0 @@ util.go renamed to helpers.go")
FN ws_ops_preview
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + WG_skip], 0
    jne 9f
    mov rdi, r12
    lea rsi, [rip + .Lpv_git]
    call sb_push_cstr
    mov rdi, [rbx + WG_real]
    call ws_rel
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Lpv_hunk]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    call sb_push_cstr
    mov rax, [rbx + WG_kind]
    lea rsi, [rip + .Lpv_created]
    cmp rax, WK_CREATE
    je 1f
    lea rsi, [rip + .Lpv_deleted]
    cmp rax, WK_DELETE
    je 1f
    mov rdi, r12
    lea rsi, [rip + .Lpv_renamed]
    call sb_push_cstr
    mov rdi, [rbx + WG_real2]
    call ws_rel
    mov rsi, rax
1:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

# ---------------- recovery ----------------

# FN ws_recover_steps(plan, len, folder) -> rax files restored, rdx left as they were: the plan's
# steps undone newest first where the disk still shows rhun's result
FN ws_recover_steps
    PROLOGUE 64
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov [rsp], rdx              # the folder
    mov qword ptr [rsp + 8], 0  # restored
    mov qword ptr [rsp + 16], 0 # left
    # the step lines' offsets, oldest first
    lea rdi, [rip + wo_steps]
    call sb_clear
    mov rbx, r12
1:  cmp rbx, r13
    jae 4f
    mov rcx, rbx
2:  cmp rcx, r13
    jae 4f
    cmp byte ptr [rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov r14, rcx
    mov rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    call wo_step_word
    test eax, eax
    jz 31f
    mov [rsp + 24], rbx
    lea rdi, [rip + wo_steps]
    lea rsi, [rsp + 24]
    mov edx, 8
    call sb_push
31: lea rbx, [r14 + 1]
    jmp 1b
4:  mov r15, [rip + wo_steps + SB_len]
5:  test r15, r15
    jz 9f
    sub r15, 8
    mov rax, [rip + wo_steps + SB_ptr]
    mov rbx, [rax + r15]
    mov [rip + ps_ptr], rbx
    mov [rip + ps_end], r13
    call ps_line
    test eax, eax
    jz 5b
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call wo_step_word
    mov [rsp + 56], rax         # 1 write, 2 create, 3 rename, 4 delete
    cmp eax, 1
    jne 6f
    # "write SLOT BEFORE AFTER LEN" LF PATH LF
    call ps_num
    test edx, edx
    jz 5b
    mov [rsp + 24], rax         # slot
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call parse_hex
    mov [rsp + 32], rax         # before
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call parse_hex
    mov [rsp + 40], rax         # after
    call ps_num
    test edx, edx
    jz 5b
    mov r14, rax
    call ps_eol
    test eax, eax
    jz 5b
    mov rdi, r14
    call lf_take
    test rax, rax
    jz 5b
    mov rdi, rax
    mov rsi, r14
    call mem_dup
    mov r14, rax
    mov rdi, [rsp]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 40]
    mov r8, r14
    call ws_recover_write
    jmp 7f
6:  # "KIND SLOT+1 FLAGS LEN1 LEN2" LF PATH1 LF PATH2 LF
    call ps_num
    test edx, edx
    jz 5b
    dec rax
    mov [rsp + 24], rax         # slot, -1 for none
    call ps_num
    test edx, edx
    jz 5b
    mov [rsp + 32], rax         # flags
    call ps_num
    test edx, edx
    jz 5b
    mov r14, rax
    call ps_num
    test edx, edx
    jz 5b
    mov [rsp + 40], rax
    call ps_eol
    test eax, eax
    jz 5b
    mov rdi, r14
    call lf_take
    test rax, rax
    jz 5b
    mov rdi, rax
    mov rsi, r14
    call mem_dup
    mov r14, rax                # path 1
    call lf_take_lf
    mov rdi, [rsp + 40]
    call lf_take
    test rax, rax
    jz 61f
    mov rdi, rax
    mov rsi, [rsp + 40]
    call mem_dup
    mov [rsp + 48], rax         # path 2
    jmp 62f
61: mov qword ptr [rsp + 48], 0
62: mov rdi, [rsp]
    mov rsi, [rsp + 56]
    mov rdx, [rsp + 24]
    mov rcx, [rsp + 32]
    mov r8, r14
    mov r9, [rsp + 48]
    call wo_recover_op
    push rax
    push rax
    mov rdi, [rsp + 64]
    call mem_free
    pop rax
    pop rax
7:  mov ebx, eax
    mov rdi, r14
    call mem_free
    cmp ebx, 1
    jne 71f
    inc qword ptr [rsp + 8]
    jmp 5b
71: test ebx, ebx
    jnz 5b
    inc qword ptr [rsp + 16]
    jmp 5b
9:  mov rax, [rsp + 8]
    mov rdx, [rsp + 16]
    EPILOGUE

# lf_take_lf(): the LF after a plan's path
lf_take_lf:
    mov edi, 1
    jmp lf_take

# wo_step_word(ptr, len) -> eax 1 "write", 2 "create", 3 "rename", 4 "delete" at the line's start
# (followed by a space), else 0
wo_step_word:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r14, [rip + wo_step_words]
    xor r13d, r13d
1:  cmp r13d, 4
    jae 8f
    mov rdi, [r14 + r13*8]
    call strlen
    mov r15, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r14 + r13*8]
    mov rcx, r15
    call str_starts
    inc r13d
    test eax, eax
    jz 1b
    cmp r12, r15
    je 2f
    cmp byte ptr [rbx + r15], ' '
    jne 1b
2:  mov eax, r13d
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# wo_recover_op(folder, kind 2..4, slot, flags, path, path2) -> eax 1 restored, 2 nothing to do,
# 0 left: a cut-short file operation undone where the disk still shows it
wo_recover_op:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, r8
    mov r15, r9
    mov [rsp], rcx
    cmp r12d, 3
    je .Lro_rename
    cmp r12d, 4
    je .Lro_delete
    # create: made, and empty: it goes (an overwritten file back)
    mov rdi, r14
    call file_missing
    test eax, eax
    jnz .Lro_none
    test qword ptr [rsp], TPF_FOLDER
    jz 1f
    mov rdi, r14
    mov eax, 84
    XSYS
    test rax, rax
    js .Lro_left
    jmp 2f
1:  mov rdi, r14
    call ws_file_hash
    test edx, edx
    jz .Lro_left
    mov rcx, 0xcbf29ce484222325
    cmp rax, rcx
    jne .Lro_left
    mov rdi, r14
    SYS SYS_unlink
2:  test qword ptr [rsp], TPF_OVER
    jz .Lro_done
    lea rdx, [rip + .Lover]
    mov rdi, r14
    call wo_recover_in
    jmp .Lro_done
.Lro_rename:
    # TO there and FROM free: back
    mov rdi, r15
    call file_missing
    test eax, eax
    jnz .Lro_none
    test qword ptr [rsp], TPF_CASE
    jnz 3f
    mov rdi, r14
    call file_missing
    test eax, eax
    jz .Lro_left
3:  mov rdi, r15
    mov rsi, r14
    SYS SYS_rename
    test rax, rax
    js .Lro_left
    test qword ptr [rsp], TPF_OVER
    jz .Lro_done
    lea rdx, [rip + .Lover]
    mov rdi, r15
    call wo_recover_in
    jmp .Lro_done
.Lro_delete:
    # the path free: it comes back
    mov rdi, r14
    call file_missing
    test eax, eax
    jz .Lro_none
    lea rdx, [rip + .Lgone]
    mov rdi, r14
    call wo_recover_in
    test rax, rax
    js .Lro_left
.Lro_done:
    mov eax, 1
    EPILOGUE
.Lro_none:
    mov eax, 2
    EPILOGUE
.Lro_left:
    xor eax, eax
    EPILOGUE
# wo_recover_in(path, suffix) -> rax 0 or -errno: folder/SLOT.suffix (rbx, r13 of wo_recover_op)
# back at path
wo_recover_in:
    push r12
    push r14
    sub rsp, 8
    mov r14, rdi
    mov r12, rdx
    lea rdi, [rip + wo_sb]
    call sb_clear
    lea rdi, [rip + wo_sb]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wo_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + wo_sb]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + wo_sb]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + wo_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, r14
    call mkdir_parent
    mov rdi, [rip + wo_sb + SB_ptr]
    mov rsi, r14
    SYS SYS_rename
    test rax, rax
    jns 9f
    mov rdi, [rip + wo_sb + SB_ptr]
    mov rsi, r14
    call wo_copy
9:  add rsp, 8
    pop r14
    pop r12
    ret

.section .rodata
.p2align 3
wo_words: .quad .Ls_creates, .Ls_renames, .Ls_deletes
wo_step_words: .quad .Lk_write, .Lk_create, .Lk_rename, .Lk_delete
.Ls_creates: .asciz ", creates "
.Ls_renames: .asciz ", renames "
.Ls_deletes: .asciz ", deletes "
.Lk_write: .asciz "write"
.Lk_create: .asciz "create"
.Lk_rename: .asciz "rename"
.Lk_delete: .asciz "delete"
.Lgone: .asciz ".gone"
.Lover: .asciz ".over"
.Lcase_tmp: .asciz ".rhun-case"
.Lempty: .asciz ""
.Lrow_c: .asciz "C  "
.Lrow_r: .asciz "R  "
.Lrow_d: .asciz "D  "
.Larrow: .asciz " \xe2\x86\x92 "
.Lpv_git: .asciz "diff --git a/"
.Lpv_hunk: .asciz "@@ -0,0 +0,0 @@ "
.Lpv_created: .asciz " created"
.Lpv_deleted: .asciz " deleted"
.Lpv_renamed: .asciz " renamed to "
.Lwc_nofile: .asciz "nofile a file the edit names is missing"
.Lwc_needs: .asciz "needs project=write a path is outside the project and the extension's state folder"
.Lwc_exists: .asciz "refused a path the edit creates or renames to exists"
.Lwc_big: .asciz "toobig a folder to delete has over 10000 entries"
.Lwc_refused: .asciz "refused the edit's file operations cannot be made together or here"
.Lwc_stale: .asciz "stale a file changed while the edit waited"
.Lws_e_op: .asciz "The extension's file operations cannot be made: nothing changed"
.Lws_e_needs: .asciz "The extension's edit changes a file outside the project: nothing changed"
.Lws_e_stale: .asciz "A file changed while the edit waited: nothing changed"
