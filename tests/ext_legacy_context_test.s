# Pure volume grammar fixture, independent of native working directory.
.include "rhun.inc"
.bss
.p2align 3
elc_result: .zero 16
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne 1f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call prep_legacy_cwd_volume
    mov [rip + elc_result], rax
    mov [rip + elc_result + 8], rdx
    mov edi, 1
    lea rsi, [rip + elc_result]
    mov edx, 16
    call write_all
    xor eax, eax
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
