.include "win.inc"
.include "app/extvalidate.inc"
.text
# External runtimes may follow installation links. Stack-only bounded UTF16 conversion.
FN win_ext_runtime_open
    PROLOGUE 8480
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lwero_bad
    mov r12, rax
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9, rax
    lea rax, [rsp + 128]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    API MultiByteToWideChar
    test eax, eax
    jz .Lwero_bad
    mov r12, rax
    mov word ptr [rsp + 128 + r12*2], 0
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp word ptr [rsp + 128 + rcx*2], '/'
    jne 11f
    mov word ptr [rsp + 128 + rcx*2], 92
11: inc rcx
    jmp 1b
2:  cmp r12, 3
    jb .Lwero_bad
    cmp word ptr [rsp + 130], ':'
    jne .Lwero_unc
    cmp word ptr [rsp + 132], 92
    jne .Lwero_bad
    movzx eax, word ptr [rsp + 128]
    or eax, 32
    sub eax, 'a'
    cmp eax, 25
    ja .Lwero_bad
    mov rax, 0x005c003f005c005c
    mov [rsp + 120], rax
    lea r14, [rsp + 120]
    jmp .Lwero_open
.Lwero_unc:
    cmp r12, 5
    jb .Lwero_bad
    cmp dword ptr [rsp + 128], 0x005c005c
    jne .Lwero_bad
    cmp word ptr [rsp + 132], '?'
    je .Lwero_bad
    cmp word ptr [rsp + 132], '.'
    je .Lwero_bad
    mov rax, 0x005c003f005c005c
    mov [rsp + 116], rax
    mov rax, 0x005c0043004e0055
    mov [rsp + 124], rax
    lea r14, [rsp + 116]
.Lwero_open:
    mov rcx, r14
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02000000
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lwero_native_error
    mov r12, rax
    mov rdi, rax
    lea rsi, [rsp + 8384]
    call win_ext_root_stat
    test rax, rax
    js .Lwero_close
    cmp qword ptr [rsp + 8384 + ER_kind], ER_FILE
    jne .Lwero_type
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Lwero_type:
    mov rax, -EV_BAD_RUNTIME
.Lwero_close:
    mov r13, rax
    mov rdi, r12
    call win_ext_root_close
    mov rdx, rax
    mov rax, r13
    EPILOGUE
.Lwero_native_error:
    call win_error
    xor edx, edx
    EPILOGUE
.Lwero_bad:
    mov rax, -EV_BAD_RUNTIME
    xor edx, edx
    EPILOGUE
