# Bounded INI text validation shared by private managed parsers.
.include "rhun.inc"
.text
FN prep_ini_text_valid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    xor r13d, r13d
1:  cmp r13, r12
    jae 9f
    lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp eax, 9
    je 2f
    cmp eax, 10
    je 2f
    cmp eax, 13
    je 2f
    cmp eax, 32
    jb 8f
    cmp eax, 127
    jb 2f
    cmp eax, 160
    jb 8f
2:  add r13, rdx
    jmp 1b
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
