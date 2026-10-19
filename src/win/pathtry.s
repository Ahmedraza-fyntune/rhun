# Separate fallible path/open entry points for package validation. Ordinary
# editor filesystem operations keep their existing conversion and open paths.
.include "win.inc"
.text
# Bounded UTF-8 -> owned UTF-16, or 0, negative errno.
.Lwpt_wide:
    PROLOGUE 96
    mov rbx, rdi
    test rdi, rdi
    jz .Lwpt_wide_invalid
    xor ecx, ecx
1:  cmp byte ptr [rbx + rcx], 0
    je 2f
    inc ecx
    cmp ecx, 4096
    jb 1b
    mov rdx, -36
    jmp .Lwpt_wide_fail
2:  mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz .Lwpt_wide_invalid
    mov r12d, eax
    lea edi, [rax*2]
    call mem_alloc_try
    test rax, rax
    jz .Lwpt_wide_oom
    mov r13, rax
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov [rsp + 32], r13
    mov [rsp + 40], r12
    API MultiByteToWideChar
    cmp eax, r12d
    jne .Lwpt_wide_release
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lwpt_wide_release:
    mov rdi, r13
    call mem_free
.Lwpt_wide_invalid:
    mov rdx, -22
    jmp .Lwpt_wide_fail
.Lwpt_wide_oom:
    mov rdx, -12
.Lwpt_wide_fail:
    xor eax, eax
    EPILOGUE

# win_file_path_try(UTF-8 path) -> owned UTF-16 filesystem path, 0;
# on error -> 0, negative errno. At most two recoverable allocations.
FN win_file_path_try
    PROLOGUE 8320
    call .Lwpt_wide
    mov rbx, rax
    test rax, rax
    jz .Lwpt_fail
    xor r12d, r12d
.Lwpt_len:
    cmp word ptr [rbx + r12*2], 0
    je .Lwpt_kind
    inc r12d
    jmp .Lwpt_len
.Lwpt_kind:
    cmp r12d, 4
    jb .Lwpt_resolve
    movzx eax, word ptr [rbx]
    cmp eax, '/'
    je 1f
    cmp eax, 92
    jne .Lwpt_drive
1:  movzx eax, word ptr [rbx + 2]
    cmp eax, '/'
    je 2f
    cmp eax, 92
    jne .Lwpt_resolve
2:  movzx eax, word ptr [rbx + 4]
    cmp eax, '?'
    je 3f
    cmp eax, '.'
    jne .Lwpt_absolute
3:  movzx eax, word ptr [rbx + 6]
    cmp eax, '/'
    je .Lwpt_namespace
    cmp eax, 92
    je .Lwpt_namespace
    jmp .Lwpt_absolute
.Lwpt_drive:
    cmp word ptr [rbx + 2], ':'
    jne .Lwpt_resolve
    movzx eax, word ptr [rbx + 4]
    cmp eax, '/'
    je .Lwpt_absolute
    cmp eax, 92
    jne .Lwpt_resolve
.Lwpt_absolute:
    cmp r12d, 248
    jb .Lwpt_original
.Lwpt_resolve:
    mov rcx, rbx
    mov edx, 4096
    lea r8, [rsp + 96]
    xor r9d, r9d
    API GetFullPathNameW
    test eax, eax
    jz .Lwpt_native_fail
    cmp eax, 4096
    jae .Lwpt_long
    cmp eax, 248
    jb .Lwpt_original
    mov r12d, eax
    mov r14d, 4
    lea r15, [rsp + 96]
    cmp word ptr [r15], 92
    jne .Lwpt_allocate
    cmp word ptr [r15 + 2], 92
    jne .Lwpt_invalid
    cmp word ptr [r15 + 6], 92
    jne 7f
    cmp word ptr [r15 + 4], '?'
    je .Lwpt_resolved_namespace
    cmp word ptr [r15 + 4], '.'
    je .Lwpt_resolved_namespace
7:  mov r14d, 6
    add r15, 4
.Lwpt_allocate:
    lea edi, [r12 + r14 + 1]
    add edi, edi
    call mem_alloc_try
    test rax, rax
    jz .Lwpt_oom
    mov r13, rax
    mov rax, 0x005c003f005c005c
    mov [r13], rax
    lea rdi, [r13 + 8]
    cmp r14d, 6
    jne 4f
    mov rax, 0x005c0043004e0055
    mov [rdi], rax
    add rdi, 8
    sub r12d, 2
4:  mov rsi, r15
    lea edx, [r12*2 + 2]
    call memcpy
    mov rdi, rbx
    call mem_free
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lwpt_resolved_namespace:
    lea edi, [r12*2 + 2]
    call mem_alloc_try
    test rax, rax
    jz .Lwpt_oom
    mov r13, rax
    mov rdi, rax
    mov rsi, r15
    lea edx, [r12*2 + 2]
    call memcpy
    mov rdi, rbx
    call mem_free
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lwpt_namespace:
    xor ecx, ecx
5:  movzx eax, word ptr [rbx + rcx*2]
    test eax, eax
    jz .Lwpt_original
    cmp eax, '/'
    jne 6f
    mov word ptr [rbx + rcx*2], 92
6:  inc rcx
    jmp 5b
.Lwpt_original:
    mov rax, rbx
    xor edx, edx
    EPILOGUE
.Lwpt_native_fail:
    call win_error
    mov r12, rax
    jmp .Lwpt_release
.Lwpt_long:
    mov r12, -36
    jmp .Lwpt_release
.Lwpt_invalid:
    mov r12, -22
    jmp .Lwpt_release
.Lwpt_oom:
    mov r12, -12
.Lwpt_release:
    mov rdi, rbx
    call mem_free
    mov rdx, r12
.Lwpt_fail:
    xor eax, eax
    EPILOGUE

# win_open_read_try(path) -> regular-file virtual descriptor, or negative errno.
# Classify the opened object and reject final reparse points before registration.
FN win_open_read_try
    PROLOGUE 160
    call win_file_path_try
    test rax, rax
    jz .Lwot_path_fail
    mov rbx, rax
    mov rcx, rax
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02200000
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lwot_open_fail
    mov r13, rax
    mov rcx, rax
    API GetFileType
    test eax, eax
    jz .Lwot_info_fail
    cmp eax, 1
    jne .Lwot_invalid
    mov rcx, r13
    lea rdx, [rsp + 96]
    API GetFileInformationByHandle
    test eax, eax
    jz .Lwot_info_fail
    test dword ptr [rsp + 96], 0x400
    jnz .Lwot_link
    test dword ptr [rsp + 96], 16
    jnz .Lwot_directory
    mov rdi, r13
    mov esi, FD_FILE
    mov edx, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    call win_fd_alloc
    test rax, rax
    js .Lwot_close_error
    mov r15, rax
    mov edi, eax
    call win_fd
    mov [rax + FD_path], rbx
    mov rax, r15
    EPILOGUE
.Lwot_info_fail:
    call win_error
    jmp .Lwot_close_error
.Lwot_invalid:
    mov rax, -22
    jmp .Lwot_close_error
.Lwot_link:
    mov rax, -40
    jmp .Lwot_close_error
.Lwot_directory:
    mov rax, -21
.Lwot_close_error:
    mov r15, rax
    mov rcx, r13
    API CloseHandle
    jmp .Lwot_free_error
.Lwot_open_fail:
    call win_error
    mov r15, rax
.Lwot_free_error:
    mov rdi, rbx
    call mem_free
    mov rax, r15
    EPILOGUE
.Lwot_path_fail:
    mov rax, rdx
    EPILOGUE
