# Workspace folders (docs/guide.md; docs/extensions/v1.1.md, feature workspace-folders). A window has
# zero or more folders, 16 at most; the first, the primary, is g_project, and every other part of
# rhun that means "the project" keeps meaning it. Folders do not nest. Each folder has an id that
# stays the same for the rhun session (removing and adding a path again gives a new one) and a
# display name unique in the window (a second "src" is "src 2"). Folders added to a project are
# remembered with its primary folder (<state>/<project>.folders, one path a line) and come back
# when it is opened again, before the explorer, git and extensions see the project.
#
#   workspace_reset()            set_project: the primary, then the remembered (or carried) folders
#   workspace_add(path) -> rax the new folder's id, or -17 already a folder, -22 inside one or
#     around one, -28 16 folders, -20 not a folder
#   workspace_remove(id) -> eax 1 when it went (the primary's going opens the next folder)
#   wfold_count() -> eax; wfold_path(i), wfold_name(i) -> rax cstr; wfold_id(i) -> rax;
#   wfold_flags(i) -> eax WFR_*; wfold_index(id) -> rax index or -1; wfold_of(path) -> rax the index
#   of the folder the path is in, or -1; wfold_join(label) -> rax an owned absolute path for a label
#   a list shows ("name/rel" with two folders or more, "rel" with one)
#   g_ws_gen                      changes whenever the folders do
.include "rhun.inc"

.equ WS_MAX, 16
.equ WS_PRIMARY, 1              # wfold_flags: the primary folder
.equ WS_TRUSTED, 2              # opened by hand, or trusted
STRUCT
F WFR_path, 8           # owned, absolute, no trailing separator
F WFR_name, 8           # owned display name
F WFR_id, 8
ENDSTRUCT WFR_SIZE

.bss
.p2align 3
ws_folders: .zero VEC_SIZE
ws_next_id: .quad 0
ws_carry: .zero VEC_SIZE        # owned paths workspace_reset adds instead of the remembered ones
ws_buf: .zero SB_SIZE
ws_name: .zero 280
.globl g_ws_gen
g_ws_gen: .long 0

.text

# FN wfold_count() -> eax
FN wfold_count
    mov rax, [rip + ws_folders + VEC_len]
    ret

# ws_at(i) -> rax the WSF of folder i, or 0
ws_at:
    xor eax, eax
    cmp rdi, [rip + ws_folders + VEC_len]
    jae 1f
    imul rax, rdi, WFR_SIZE
    add rax, [rip + ws_folders + VEC_ptr]
1:  ret

# FN wfold_path(i) -> rax
FN wfold_path
    call ws_at
    test rax, rax
    jz 1f
    mov rax, [rax + WFR_path]
1:  ret

# FN wfold_name(i) -> rax
FN wfold_name
    call ws_at
    test rax, rax
    jz 1f
    mov rax, [rax + WFR_name]
1:  ret

# FN wfold_id(i) -> rax
FN wfold_id
    call ws_at
    test rax, rax
    jz 1f
    mov rax, [rax + WFR_id]
1:  ret

# FN wfold_flags(i) -> eax WS_PRIMARY for the first, WS_TRUSTED unless a rhun:// link opened the
# project and the user has not trusted it
FN wfold_flags
    push rdi
    call ws_at
    pop rdi
    test rax, rax
    jz 9f
    xor eax, eax
    test rdi, rdi
    jnz 1f
    mov eax, WS_PRIMARY
1:  cmp dword ptr [rip + g_project_link], 0
    je 2f
    cmp qword ptr [rip + g_git_root], 0
    je 9f
    cmp dword ptr [rip + g_git_paused], 0
    jne 9f
2:  or eax, WS_TRUSTED
9:  ret

# FN wfold_index(id) -> rax
FN wfold_index
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 8f
    mov rdi, rbx
    call ws_at
    cmp [rax + WFR_id], r12
    je 9f
    inc rbx
    jmp 1b
8:  mov rbx, -1
9:  mov rax, rbx
    EPILOGUE

# FN wfold_of(path) -> rax the index of the folder the path is in, or -1
FN wfold_of
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 8f
    mov rdi, rbx
    call ws_at
    mov rdi, r12
    mov rsi, [rax + WFR_path]
    call app_path_inside
    test eax, eax
    jnz 9f
    inc rbx
    jmp 1b
8:  mov rbx, -1
9:  mov rax, rbx
    EPILOGUE

# FN wfold_join(label) -> rax an owned path: with one folder the label is relative to it, with more
# its first part names the folder
FN wfold_join
    PROLOGUE
    mov r12, rdi
    cmp qword ptr [rip + ws_folders + VEC_len], 1
    ja 2f
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 8f
1:  mov rsi, r12
    call path_join
    EPILOGUE
2:  xor ebx, ebx
3:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 8f
    mov rdi, rbx
    call ws_at
    mov r13, rax
    mov rdi, [r13 + WFR_name]
    call strlen
    mov r14, rax
    mov rdi, r12
    mov rsi, [r13 + WFR_name]
    mov rdx, r14
    call strncmp_eq
    test eax, eax
    jz 4f
    cmp byte ptr [r12 + r14], '/'
    jne 4f
    mov rdi, [r13 + WFR_path]
    lea r12, [r12 + r14 + 1]
    jmp 1b
4:  inc rbx
    jmp 3b
8:  mov rdi, r12                # not a folder's: as it is
    call dup_cstr
    EPILOGUE

# strncmp_eq(a, b, n) -> eax 1 when the first n bytes are the same
strncmp_eq:
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    cmp al, [rsi + rcx]
    jne 3f
    inc rcx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret

# ---------------- changing the folders ----------------

# ws_clear(): every folder goes
ws_clear:
    PROLOGUE
1:  mov rax, [rip + ws_folders + VEC_len]
    test rax, rax
    jz 9f
    dec rax
    mov [rip + ws_folders + VEC_len], rax
    mov rdi, rax
    call ws_at_any
    mov rbx, rax
    mov rdi, [rbx + WFR_path]
    call mem_free
    mov rdi, [rbx + WFR_name]
    call mem_free
    jmp 1b
9:  EPILOGUE

# ws_at_any(i) -> rax the WSF slot i (also past the length)
ws_at_any:
    imul rax, rdi, WFR_SIZE
    add rax, [rip + ws_folders + VEC_ptr]
    ret

# ws_push(path cstr) -> rax the new folder's id: appended with a new id and a unique name
ws_push:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov r12, rax
    # its name: the last part, made unique
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call path_basename
    mov r13, rax
    cmp byte ptr [r13], 0
    jne 1f
    mov r13, r12                # a root: its path
1:  mov rdi, r13
    call strlen
    cmp rax, 250
    jbe 2f
    mov eax, 250
2:  lea rdi, [rip + ws_name]
    mov rsi, r13
    mov rcx, rax
    rep movsb
    mov byte ptr [rdi], 0
    mov r14, rdi                # where " N" goes
    mov r15d, 1
3:  call ws_name_taken
    test eax, eax
    jz 4f
    inc r15d
    mov byte ptr [r14], ' '
    lea rdi, [r14 + 1]
    mov esi, r15d
    call fmt_u64
    mov byte ptr [rdi], 0
    jmp 3b
4:  lea rdi, [rip + ws_folders]
    mov esi, WFR_SIZE
    call vec_push
    mov rbx, rax
    mov [rbx + WFR_path], r12
    lea rdi, [rip + ws_name]
    call dup_cstr
    mov [rbx + WFR_name], rax
    inc qword ptr [rip + ws_next_id]
    mov rax, [rip + ws_next_id]
    mov [rbx + WFR_id], rax
    inc dword ptr [rip + g_ws_gen]
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ws_name_taken() -> eax 1 when a folder already has the name in ws_name
ws_name_taken:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 8f
    mov rdi, rbx
    call ws_at
    mov rdi, [rax + WFR_name]
    lea rsi, [rip + ws_name]
    call strcmp_eq
    test eax, eax
    jnz 9f
    inc rbx
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# ws_check(path) -> rax 0 when the path may become a folder, else -errno (workspace_add's)
ws_check:
    PROLOGUE
    mov r12, rdi
    mov rax, -28
    cmp qword ptr [rip + ws_folders + VEC_len], WS_MAX
    jae 9f
    mov rdi, r12
    call vfs_is_dir
    test eax, eax
    mov rax, -20
    jz 9f
    xor ebx, ebx
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 8f
    mov rdi, rbx
    call ws_at
    mov r13, [rax + WFR_path]
    mov rdi, r12
    mov rsi, r13
    call app_path_inside
    test eax, eax
    jz 2f
    # the folder itself, or inside it
    mov r14, rdx
    mov rdi, r12
    call strlen
    cmp rax, r14
    mov rax, -17
    je 9f
    mov rax, -22
    jmp 9f
2:  mov rdi, r13                # around it
    mov rsi, r12
    call app_path_inside
    test eax, eax
    mov rax, -22
    jnz 9f
    inc rbx
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# ws_path_clean(path) -> rax an owned absolute normalized copy without a trailing separator
ws_path_clean:
    PROLOGUE
    mov rbx, rdi
    PATH_ABSOLUTE rbx, 1f
    sub rsp, 4096
    mov rdi, rsp
    mov esi, 4000
    SYS SYS_getcwd
    mov rdi, rsp
    mov rsi, rbx
    call path_join
    add rsp, 4096
    jmp 2f
1:  mov rdi, rbx
    call dup_cstr
2:  mov rbx, rax
    mov rdi, rax
    call path_normalize
    mov rdi, rbx
    call strlen
.ifdef WINDOWS
    mov r12, rax
    mov rdi, rbx
    call path_rootlen
    mov rcx, rax
    mov rax, r12
    cmp rax, rcx
.else
    cmp rax, 1
.endif
    jbe 3f
    movzx ecx, byte ptr [rbx + rax - 1]
    cmp ecx, '/'
    je 31f
    cmp ecx, 92
    jne 3f
31: mov byte ptr [rbx + rax - 1], 0
3:  mov rax, rbx
    EPILOGUE

# FN workspace_add(path) -> rax the id or -errno; a folder added is remembered with the project
FN workspace_add
    PROLOGUE
    cmp qword ptr [rip + g_project], 0
    jne 1f
    # a window without a project opens it as the primary
    call app_set_project
    mov rax, [rip + ws_folders + VEC_len]
    test rax, rax
    jz 7f
    xor edi, edi
    call wfold_id
    EPILOGUE
1:  call ws_path_clean
    mov rbx, rax
    mov rdi, rax
    call ws_check
    test rax, rax
    jnz 8f
    mov rdi, rbx
    call ws_push
    mov r12, rax
    call ws_save
    call ws_changed
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
7:  mov rax, -20
    EPILOGUE
8:  mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE

# FN workspace_remove(id) -> eax 1 when the folder went. The primary's going makes the next folder
# the primary: the window takes it up (its unsaved files asked about first) and keeps the others.
FN workspace_remove
    PROLOGUE
    call wfold_index
    test rax, rax
    js 8f
    mov rbx, rax
    test rbx, rbx
    jnz 3f
    # the primary: the next one takes its place
    cmp qword ptr [rip + ws_folders + VEC_len], 2
    jb 8f
    call ws_carry_clear
    mov r12d, 2
1:  cmp r12, [rip + ws_folders + VEC_len]
    jae 2f
    mov rdi, r12
    call wfold_path
    mov rdi, rax
    call dup_cstr
    mov r13, rax
    lea rdi, [rip + ws_carry]
    mov esi, 8
    call vec_push
    mov [rax], r13
    inc r12
    jmp 1b
2:  mov edi, 1
    call wfold_path
    mov rdi, rax
    call dup_cstr
    mov r12, rax
    mov dword ptr [rip + ws_carrying], 1
    mov rdi, r12
    call app_switch_project
    mov rdi, r12
    call mem_free
    mov eax, 1
    EPILOGUE
3:  mov rdi, rbx
    call ws_at
    mov r12, rax
    mov rdi, [r12 + WFR_path]
    call mem_free
    mov rdi, [r12 + WFR_name]
    call mem_free
    # the later ones move up
    mov rdi, r12
    lea rsi, [r12 + WFR_SIZE]
    mov rax, [rip + ws_folders + VEC_len]
    sub rax, rbx
    dec rax
    imul rdx, rax, WFR_SIZE
    call memmove
    dec qword ptr [rip + ws_folders + VEC_len]
    inc dword ptr [rip + g_ws_gen]
    call ws_save
    call ws_changed
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ws_carry_clear(): the carried paths go
ws_carry_clear:
    PROLOGUE
1:  mov rax, [rip + ws_carry + VEC_len]
    test rax, rax
    jz 9f
    dec rax
    mov [rip + ws_carry + VEC_len], rax
    mov rcx, [rip + ws_carry + VEC_ptr]
    mov rdi, [rcx + rax*8]
    call mem_free
    jmp 1b
9:  mov dword ptr [rip + ws_carrying], 0
    EPILOGUE

# ws_changed(): the parts that show or use the folders follow
ws_changed:
    PROLOGUE
    call explorer_set_root
    call app_update_title
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN workspace_reset(): the primary (g_project), then the folders remembered with it, or those the
# primary's removal carried over
FN workspace_reset
    PROLOGUE
    call ws_clear
    inc dword ptr [rip + g_ws_gen]
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 8f
    call ws_push
    cmp dword ptr [rip + ws_carrying], 0
    je 3f
    xor ebx, ebx
1:  cmp rbx, [rip + ws_carry + VEC_len]
    jae 2f
    mov rax, [rip + ws_carry + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call ws_add_quiet
    inc rbx
    jmp 1b
2:  call ws_carry_clear
    call ws_save
    jmp 8f
3:  # the remembered folders
    lea rdi, [rip + .Lext_folders]
    call session_project_file
    test rax, rax
    jz 8f
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 8f
    mov r12, rax
    lea r13, [rax + rdx]
    mov rbx, rax
4:  cmp rbx, r13
    jae 7f
    mov r14, rbx
5:  cmp r14, r13
    jae 6f
    cmp byte ptr [r14], 10
    je 6f
    inc r14
    jmp 5b
6:  mov byte ptr [r14], 0
    cmp r14, rbx
    je 61f
    mov rdi, rbx
    call ws_add_quiet
61: lea rbx, [r14 + 1]
    jmp 4b
7:  mov rdi, r12
    call mem_free
8:  EPILOGUE

# ws_add_quiet(path): added when it may be (a folder that went is skipped)
ws_add_quiet:
    PROLOGUE
    mov r12, rdi
    PATH_ABSOLUTE r12, 1f
    jmp 9f                      # remembered paths are absolute
1:  mov rdi, r12
    call ws_check
    test rax, rax
    jnz 9f
    mov rdi, r12
    call ws_push
9:  EPILOGUE

# ws_save(): <state>/<project>.folders: the folders after the primary, one a line (none: removed)
ws_save:
    PROLOGUE
    lea rdi, [rip + ws_buf]
    call sb_clear
    mov ebx, 1
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 2f
    mov rdi, rbx
    call wfold_path
    lea rdi, [rip + ws_buf]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + ws_buf]
    mov esi, 10
    call sb_push_byte
    inc rbx
    jmp 1b
2:  lea rdi, [rip + .Lext_folders]
    call session_project_file
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp qword ptr [rip + ws_buf + SB_len], 0
    jne 3f
    mov rdi, rbx
    call vfs_unlink
    jmp 9f
3:  mov rdi, rbx
    mov rsi, [rip + ws_buf + SB_ptr]
    mov rdx, [rip + ws_buf + SB_len]
    call file_write_all
9:  EPILOGUE

# ---------------- commands ----------------

# FN cmd_add_workspace_folder(): the path browser picks a folder to add
FN cmd_add_workspace_folder
    mov edi, 2
    jmp browse_open_kind

# FN workspace_add_ui(path): Add Folder's pick: added, or a toast says why not
FN workspace_add_ui
    PROLOGUE
    mov rbx, rdi
    call workspace_add
    test rax, rax
    jns 9f
    lea rdi, [rip + .Lt_nested]
    cmp rax, -22
    je 1f
    lea rdi, [rip + .Lt_already]
    cmp rax, -17
    je 1f
    lea rdi, [rip + .Lt_full]
    cmp rax, -28
    je 1f
    lea rdi, [rip + .Lt_not_folder]
1:  call app_toast
9:  EPILOGUE

# FN cmd_remove_workspace_folder(): the active document's folder (or the explorer's selection's)
# leaves the workspace; the primary only when another folder can take its place
FN cmd_remove_workspace_folder
    PROLOGUE
    cmp qword ptr [rip + ws_folders + VEC_len], 2
    jb 8f
    lea rdi, [rip + g_explorer_target]
    cmp byte ptr [rdi], 0
    jne 1f
    mov rax, [rip + g_doc]
    test rax, rax
    jz 8f
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz 8f
1:  call wfold_of
    test rax, rax
    js 8f
    mov rdi, rax
    call wfold_id
    mov rdi, rax
    call workspace_remove
    EPILOGUE
8:  lea rdi, [rip + .Lt_no_remove]
    call app_toast
    EPILOGUE

# FN c_print_folders(out, args, len): print-folders: "folder=ID name=N path=P flags=F" a line
FN c_print_folders
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + ws_folders + VEC_len]
    jae 9f
    mov rdi, r12
    lea rsi, [rip + .Lp_folder]
    call sb_push_cstr
    mov rdi, rbx
    call wfold_id
    mov rdi, r12
    mov rsi, rax
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Lp_name]
    call sb_push_cstr
    mov rdi, rbx
    call wfold_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_path]
    call sb_push_cstr
    mov rdi, rbx
    call wfold_path
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_flags]
    call sb_push_cstr
    mov rdi, rbx
    call wfold_flags
    mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc rbx
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# FN c_folder_add(out, args, len): folder-add PATH: "id=N", or "error=-E"
FN c_folder_add
    PROLOGUE 16
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call mem_dup
    mov rbx, rax
    mov rdi, rax
    call workspace_add
    mov r13, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    lea rsi, [rip + .Lp_id]
    test r13, r13
    jns 1f
    lea rsi, [rip + .Lp_error]
    neg r13
1:  call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# FN c_folder_remove(out, args, len): folder-remove ID
FN c_folder_remove
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call parse_u64
    mov rdi, rax
    call workspace_remove
    mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

.data
ws_carrying: .long 0            # workspace_reset adds ws_carry's paths

.section .rodata
.Lext_folders: .asciz ".folders"
.Lt_nested: .asciz "A workspace folder cannot be inside another one, or around it"
.Lt_already: .asciz "That folder is in the workspace already"
.Lt_full: .asciz "A workspace has 16 folders at most"
.Lt_not_folder: .asciz "Not a folder"
.Lt_no_remove: .asciz "Only a workspace of two folders or more has one to remove"
.Lp_folder: .asciz "folder="
.Lp_name: .asciz " name="
.Lp_path: .asciz " path="
.Lp_flags: .asciz " flags="
.Lp_id: .asciz "id="
.Lp_error: .asciz "error="
