# A recognizable native image that marks execution only when the test supplies a path.
.include "rhun.inc"
.text
FN main
    PROLOGUE
    lea rdi, [rip + evp_marker]
    call getenv
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
    mov edx, 0x180
    SYS SYS_open
    test rax, rax
    js 8f
    mov rdi, rax
    SYS SYS_close
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE
.section .rodata
evp_marker: .asciz "RHUN_VALIDATION_MARKER"
