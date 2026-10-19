# PATH-only runtime lookup with bounded stack conversions, no allocating Win32 adapters.
.include "win.inc"
.text
# name is a checked UTF8 basename<=255 bytes; EPOr0 determines output ownership.
FN win_prep_runtime_candidate
    PROLOGUE 148000
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov r13, rax
    mov ecx, 65001
    mov edx, 8
    mov r8, r12
    mov r9, r13
    lea rax, [rsp + 96]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 256
    API MultiByteToWideChar
    test eax, eax
    jz .Lwpr_bad
    mov word ptr [rsp + 96 + rax*2], 0
    lea rcx, [rip + wpr_path]
    xor edx, edx
    xor r8d, r8d
    API GetEnvironmentVariableW
    test eax, eax
    jz .Lwpr_none
    cmp eax, 65537
    ja .Lwpr_bad
    mov r14d, eax
    lea rcx, [rip + wpr_path]
    lea rdx, [rsp + 640]
    mov r8, r14
    API GetEnvironmentVariableW
    test eax, eax
    jz .Lwpr_none
    cmp eax, r14d
    jae .Lwpr_bad
    lea rcx, [rsp + 640]
    lea rdx, [rsp + 96]
    lea r8, [rip + wpr_exe]
    mov r9d, 4096
    lea rax, [rsp + 131744]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    API SearchPathW
    test eax, eax
    jz .Lwpr_none
    cmp eax, 4096
    jae .Lwpr_bad
    mov r14d, eax
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 131744]
    mov r9, r14
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lwpr_bad
    cmp eax, 4095
    ja .Lwpr_bad
    mov r15d, eax
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 131744]
    mov r9, r14
    lea rax, [rsp + 140000]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    cmp eax, r15d
    jne .Lwpr_bad
    mov byte ptr [rsp + 140000 + r15], 0
    lea rdi, [rsp + 140000]
    call win_slashes
    mov rdi, rbx
    lea rsi, [rsp + 140000]
    mov rdx, r15
    call prep_runtime_dup
    EPILOGUE
.Lwpr_none:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lwpr_bad:
    xor eax, eax
    mov rdx, -1006
    EPILOGUE
.section .rodata
wpr_path: .short 'P','A','T','H',0
wpr_exe: .short '.','e','x','e',0
