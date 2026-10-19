# Checked ownership for ordinary virtual file and pipe descriptors.
.include "win.inc"
.text
FN win_ext_fd_close_checked
    PROLOGUE 96
    call win_fd
    test rax, rax
    jz .Lhfc_missing
    mov rbx, rax
    cmp dword ptr [rbx + FD_kind], FD_FILE
    je 1f
    cmp dword ptr [rbx + FD_kind], FD_PIPE
    jne .Lhfc_kind
1:  mov r12, [rbx + FD_path]
    test r12, r12
    jz 2f
    # Only a small allocator block can be released without another native call.
    cmp qword ptr [r12 - 16], 12
    jae .Lhfc_large
2:  mov rcx, [rbx + FD_handle]
    API CloseHandle
    test eax, eax
    jz .Lhfc_unknown
    mov rdi, rbx
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    mov rdi, r12
    call mem_free
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lhfc_unknown:
    call win_error
    test rax, rax
    js 3f
    mov rax, -5
3:  mov edx, 2
    EPILOGUE
.Lhfc_missing:
    mov rax, -9
    jmp .Lhfc_retained
.Lhfc_kind:
    mov rax, -22
    jmp .Lhfc_retained
.Lhfc_large:
    mov rax, -7
.Lhfc_retained:
    xor edx, edx
    EPILOGUE
