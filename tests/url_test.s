# rhun_url on the links in a file, one per line: prints "path LINE COL", or "none" (no rhun: link) or
# "bad" (a rhun: link that is not rhun://file/PATH)
.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
line: .zero 512
path: .zero 512
.text
FN main
    PROLOGUE
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    lea r13, [rax + rdx]
1:  cmp r12, r13
    jae 9f
    mov r14, r12                # the line
2:  cmp byte ptr [r12], 10
    je 3f
    inc r12
    jmp 2b
3:  mov rbx, r12
    sub rbx, r14                # its length
    inc r12
    lea rdi, [rip + line]
    mov rsi, r14
    mov rdx, rbx
    call memcpy
    lea rax, [rip + line]
    mov byte ptr [rax + rbx], 0
    lea rdi, [rip + line]
    lea rsi, [rip + path]
    mov edx, 64                 # small, so that a long path is refused
    call rhun_url
    mov r14d, edx
    mov r15d, ecx
    cmp rax, -1
    jne 4f
    lea rsi, [rip + .Lnone]
    jmp 6f
4:  cmp rax, -2
    jne 5f
    lea rsi, [rip + .Lbad]
    jmp 6f
5:  lea rdi, [rip + out]
    lea rsi, [rip + path]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, r14d
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, r15d
    call sb_push_u64
    jmp 7f
6:  lea rdi, [rip + out]
    call sb_push_cstr
7:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE

.section .rodata
.Lnone: .asciz "none"
.Lbad: .asciz "bad"
