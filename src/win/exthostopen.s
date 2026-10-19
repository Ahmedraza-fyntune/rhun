# Scoped prepared FILE open. Admission precedes acquiring a native handle.
.include "win.inc"
.text
# Checked common wrapper supplies bounded absolute path or mode1 null.
FN win_ext_host_log_open
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz 1f
    lea r12, [rip + wh_null]
1:  mov rdi, r12
    call win_file_path_try
    test rax, rax
    jz .Lwh_open_conversion
    mov r12, rax
    xor edi, edi
    mov esi, FD_FILE
    mov edx, O_WRONLY | O_CLOEXEC
    test r13, r13
    jnz 2f
    or edx, O_CREAT | O_APPEND
2:  call win_fd_alloc
    test rax, rax
    js .Lwh_open_admission
    mov r14, rax
    mov r15, r8
    mov rcx, r12
    mov edx, 0x40000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 4
    test r13, r13
    jz 3f
    mov qword ptr [rsp + 32], 3
3:  mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lwh_open_native
    # All native ownership is now reachable, even if later positioning fails.
    mov [r15 + FD_handle], rax
    mov [r15 + FD_write], rax
    mov [r15 + FD_path], r12
    mov [rbx + EXT_log], r14d
    mov rcx, rax
    API GetFileType
    test r13, r13
    jnz 4f
    cmp eax, 1
    jne .Lwh_open_kind
    mov edi, r14d
    xor esi, esi
    mov edx, 2
    call ws_lseek
    test rax, rax
    js .Lwh_open_done
    xor eax, eax
    EPILOGUE
4:  cmp eax, 2
    jne .Lwh_open_kind
    xor eax, eax
    EPILOGUE
.Lwh_open_kind:
    mov rax, -22
    EPILOGUE
.Lwh_open_native:
    call win_error
    mov r13, rax
    mov rdi, r15
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    mov rdi, r12
    call mem_free
    mov rax, r13
    EPILOGUE
.Lwh_open_admission:
    mov r13, rax
    mov rdi, r12
    call mem_free
    mov rax, r13
    EPILOGUE
.Lwh_open_conversion:
    mov rax, rdx
.Lwh_open_done:
    EPILOGUE
.section .rodata
wh_null: .asciz "NUL"
