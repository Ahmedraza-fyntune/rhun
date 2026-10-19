# Startup path spelling only. All native cwd/fullpath work precedes sealed interactive capture.
.include "win.inc"
.text
FN win_tc_startup_cwd
    PROLOGUE 8320
    mov rbx, rdi
    mov ecx, 4096
    lea rdx, [rsp + 96]
    API GetCurrentDirectoryW
    test eax, eax
    jz .Lwts_api
    cmp eax, 4096
    jae .Lwts_long
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 96]
    mov r9d, -1
    mov [rsp + 32], rbx
    mov qword ptr [rsp + 40], 4096
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lwts_api
    xor eax, eax
    EPILOGUE
.Lwts_api:
    call win_error
    EPILOGUE
.Lwts_long:
    mov rax, -36
    EPILOGUE
# bounded validated-length UTF8 raw path -> small owned ordinary absolute UTF8.
FN win_tc_startup_path
    PROLOGUE 20832
    mov rbx, rdi
    mov r12, rsi
    # Namespace prefixes are refused before native qualification can reinterpret them.
    cmp r12, 4
    jb 3f
    mov al, [rbx]
    cmp al, '/'
    je 1f
    cmp al, 92
    jne 3f
1:  mov al, [rbx + 1]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne 3f
2:  mov al, [rbx + 2]
    cmp al, '?'
    je .Lwtsp_bad
    cmp al, '.'
    je .Lwtsp_bad
3:  mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9, r12
    lea rax, [rsp + 96]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4095
    API MultiByteToWideChar
    test eax, eax
    jz .Lwtsp_bad
    lea rcx, [rsp + 96]
    mov word ptr [rcx + rax*2], 0
    # Treat slash as the ordinary Windows separator before Wine/native qualification.
    xor edx, edx
4:  cmp rdx, rax
    jae 5f
    cmp word ptr [rcx + rdx*2], '/'
    jne 6f
    mov word ptr [rcx + rdx*2], 92
6:  inc rdx
    jmp 4b
5:  mov edx, 4096
    lea r8, [rsp + 8288]
    xor r9d, r9d
    API GetFullPathNameW
    test eax, eax
    jz .Lwtsp_api
    cmp eax, 4096
    jae .Lwtsp_long
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 8288]
    mov r9d, -1
    lea rax, [rsp + 16480]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lwtsp_api
    lea rdi, [rsp + 16480]
    call tc_path_len
    test rax, rax
    js .Lwtsp_error
    mov r12, rax
    lea rdi, [rax + 1]
    call mem_alloc_try
    test rax, rax
    jz .Lwtsp_oom
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rsp + 16480]
    lea rdx, [r12 + 1]
    call memcpy
    mov rax, rbx
    xor edx, edx
    EPILOGUE
.Lwtsp_api:
    call win_error
    jmp .Lwtsp_error
.Lwtsp_bad:
    mov rax, -22
    jmp .Lwtsp_error
.Lwtsp_long:
    mov rax, -36
    jmp .Lwtsp_error
.Lwtsp_oom:
    mov rax, -12
.Lwtsp_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
