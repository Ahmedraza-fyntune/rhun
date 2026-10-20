# Workspace folders (docs/extensions/v1.1.md, feature workspace-folders). A window has zero or more
# folders; the first, the primary, is g_project. Each folder has an id that stays the same for the
# rhun session.
#
#   wfold_count() -> eax the folders (0 in a no-project window)
#   wfold_path(i) -> rax folder i's path (a cstr, valid until the folders change)
#   wfold_id(i) -> rax folder i's id
#   wfold_index(id) -> rax the index of the folder with that id, or -1
.include "rhun.inc"

.text

# FN wfold_count() -> eax
FN wfold_count
    xor eax, eax
    mov rcx, [rip + g_project]
    test rcx, rcx
    jz 1f
    cmp byte ptr [rcx], 0
    je 1f
    mov eax, 1
1:  ret

# FN wfold_path(i) -> rax
FN wfold_path
    mov rax, [rip + g_project]
    ret

# FN wfold_id(i) -> rax
FN wfold_id
    lea rax, [rdi + 1]
    ret

# FN wfold_index(id) -> rax
FN wfold_index
    push rdi
    call wfold_count
    pop rdi
    mov ecx, eax
    test rdi, rdi
    jz 8f
    cmp rdi, rcx
    ja 8f
    lea rax, [rdi - 1]
    ret
8:  mov rax, -1
    ret
