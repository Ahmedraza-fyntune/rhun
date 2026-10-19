# Checked descriptor consumption and ordinary pipe byte transport.
.include "rhun.inc"
.section .rodata
hn_bytes: .ascii "rhunpipe"
hn_null: .asciz "/dev/null"
.bss
.p2align 3
hn_pair: .zero 8
hn_buf: .zero 8
hn_stage: .quad 0
hn_live: .quad 0
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + hn_live], rax
    mov qword ptr [rip + hn_stage], 1
    lea rdi, [rip + hn_pair]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    jnz .Lhn_bad
    mov edi, [rip + hn_pair + 4]
    lea rsi, [rip + hn_bytes]
    mov edx, 8
    SYS SYS_write
    cmp rax, 8
    jne .Lhn_bad
    mov edi, [rip + hn_pair]
    lea rsi, [rip + hn_buf]
    mov edx, 8
    SYS SYS_read
    cmp rax, 8
    jne .Lhn_bad
    lea rdi, [rip + hn_bytes]
    lea rsi, [rip + hn_buf]
    mov edx, 8
    call memeq
    test rax, rax
    jz .Lhn_bad
    mov qword ptr [rip + hn_stage], 2
    mov edi, [rip + hn_pair]
    call ext_fd_close_checked
    test rax, rax
    jnz .Lhn_bad
    cmp rdx, 1
    jne .Lhn_bad
    mov edi, [rip + hn_pair + 4]
    call ext_fd_close_checked
    test rax, rax
    jnz .Lhn_bad
    cmp rdx, 1
    jne .Lhn_bad
    lea rdi, [rip + hn_null]
    mov esi, O_RDONLY
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lhn_bad
    mov rdi, rax
    call ext_fd_close_checked
    test rax, rax
    jnz .Lhn_bad
    cmp rdx, 1
    jne .Lhn_bad
    mov edi, -1
    call ext_fd_close_checked
    cmp rax, -9
    jne .Lhn_bad
.ifdef WINDOWS
    test rdx, rdx
.else
    cmp rdx, 1
.endif
    jne .Lhn_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + hn_live]
    jne .Lhn_bad
    xor eax, eax
    EPILOGUE
.Lhn_bad:
    mov rax, [rip + hn_stage]
    EPILOGUE
