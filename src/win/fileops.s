.include "win.inc"
.text
FN win_file_lock_try
    PROLOGUE 128
    mov r12d, esi
    call win_fd
    test rax, rax
    jz .Lwfl_bad
    cmp dword ptr [rax + FD_kind], FD_FILE
    jne .Lwfl_bad
    mov rcx, [rax + FD_handle]
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 104], 0
    mov qword ptr [rsp + 112], 0
    mov qword ptr [rsp + 120], 0
    lea edx, [r12*2 + 1]       # FAIL_IMMEDIATELY, optional EXCLUSIVE_LOCK
    xor r8d, r8d
    mov r9d, 1
    mov qword ptr [rsp + 32], 0
    lea rax, [rsp + 96]
    mov [rsp + 40], rax
    API LockFileEx
    test eax, eax
    jnz .Lwfl_ok
    API GetLastError
    cmp eax, 33                # ERROR_LOCK_VIOLATION
    je .Lwfl_busy
    call win_error
    EPILOGUE
.Lwfl_busy:
    mov rax, -11
    EPILOGUE
.Lwfl_bad:
    mov rax, -9
    EPILOGUE
.Lwfl_ok:
    xor eax, eax
    EPILOGUE

FN win_file_lock_release
    PROLOGUE 128
    call win_fd
    test rax, rax
    jz .Lwfu_bad
    cmp dword ptr [rax + FD_kind], FD_FILE
    jne .Lwfu_bad
    mov rcx, [rax + FD_handle]
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 104], 0
    mov qword ptr [rsp + 112], 0
    mov qword ptr [rsp + 120], 0
    xor edx, edx
    mov r8d, 1
    xor r9d, r9d
    lea rax, [rsp + 96]
    mov [rsp + 32], rax
    API UnlockFileEx
    test eax, eax
    jnz .Lwfu_ok
    call win_error
    EPILOGUE
.Lwfu_bad:
    mov rax, -9
    EPILOGUE
.Lwfu_ok:
    xor eax, eax
    EPILOGUE

FN win_file_publish_new
    PROLOGUE 96
    mov r12, rsi
    call win_file_path_try
    test rax, rax
    jz .Lwfp_path_error
    mov rbx, rax
    mov rdi, r12
    call win_file_path_try
    test rax, rax
    jz .Lwfp_second_error
    mov r13, rax
    mov rcx, rbx
    mov rdx, rax
    xor r8d, r8d              # No replace, copy, delayed move or compensation.
    API MoveFileExW
    xor r14d, r14d
    test eax, eax
    jnz .Lwfp_release
    call win_error             # Capture before cleanup changes last-error.
    mov r14, rax
.Lwfp_release:
    mov rdi, r13
    call mem_free
    mov rdi, rbx
    call mem_free
    mov rax, r14
    EPILOGUE
.Lwfp_second_error:
    mov r14, rdx
    mov rdi, rbx
    call mem_free
    mov rax, r14
    EPILOGUE
.Lwfp_path_error:
    mov rax, rdx
    EPILOGUE
