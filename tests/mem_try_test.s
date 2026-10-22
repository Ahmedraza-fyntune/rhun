# Fallible allocation boundaries and the actual platform mapping-error path.
.include "rhun.inc"
.bss
.p2align 3
mt_live: .quad 0
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 1
    je .Lmt_basic
    cmp qword ptr [rip + g_argc], 2
    jne .Lmt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov rdi, r12
    lea rsi, [rip + mt_fatal_map]
    call strcmp_eq
    test eax, eax
    jz 1f
    xor edi, edi
    call os_map
    jmp .Lmt_fail
1:  mov rdi, r12
    lea rsi, [rip + mt_fatal_alloc]
    call strcmp_eq
    test eax, eax
    jz 2f
    mov rdi, -1
    call mem_alloc
    jmp .Lmt_fail
2:  mov rdi, r12
    lea rsi, [rip + mt_fatal_realloc]
    call strcmp_eq
    test eax, eax
    jz .Lmt_fail
    mov edi, 70000
    call mem_alloc
    mov rdi, rax
    mov rsi, -1
    call mem_realloc
    jmp .Lmt_fail
.Lmt_basic:
    mov rax, [rip + g_mem_live]
    mov [rip + mt_live], rax
    xor edi, edi
    call os_map_try
    test rax, rax
    jnz .Lmt_fail
    xor r12d, r12d
.Lmt_size:
    lea rax, [rip + mt_sizes]
    mov r13, [rax + r12*8]
    cmp r13, -1
    je .Lmt_huge
    mov r14d, 2
1:  mov rdi, r13
    call mem_alloc_try
    test rax, rax
    jz .Lmt_fail
    mov rbx, rax
    mov rdi, rax
    call mem_capacity
    cmp rax, r13
    jb .Lmt_free_fail
    mov r15, rax
    xor ecx, ecx
2:  cmp rcx, r15
    jae 3f
    cmp byte ptr [rbx + rcx], 0
    jne .Lmt_free_fail
    inc rcx
    jmp 2b
3:  mov rdi, rbx
    mov esi, 0xa5
    mov rdx, r15
    call memset
    mov rdi, rbx
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + mt_live]
    jne .Lmt_fail
    dec r14d
    jnz 1b
    inc r12
    jmp .Lmt_size
.Lmt_huge:
    xor r12d, r12d
1:  lea rax, [rip + mt_huge]
    mov rdi, [rax + r12*8]
    test rdi, rdi
    jz 2f
    call mem_alloc_try
    test rax, rax
    jz 3f
    mov rdi, rax
    call mem_free
    jmp .Lmt_fail
3:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + mt_live]
    jne .Lmt_fail
    inc r12
    jmp 1b
2:  lea rdi, [rip + mt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lmt_free_fail:
    mov rdi, rbx
    call mem_free
.Lmt_fail:
    mov eax, 90
    EPILOGUE
.section .rodata
.p2align 3
mt_sizes:
    .quad 0, 1, 15, 16, 17, 47, 48, 49, 111, 112, 113
    .quad 239, 240, 241, 495, 496, 497, 1007, 1008, 1009
    .quad 2031, 2032, 2033, 4079, 4080, 4081, 8175, 8176, 8177
    .quad 16367, 16368, 16369, 32751, 32752, 32753
    .quad 65519, 65520, 65521, 65535, 65536, 65537, 1048576, -1
mt_huge: .quad -1, -16, -4096, 1 << 40, (1 << 40) + 1, 0x7fffffffffffffff, 0
mt_fatal_map: .asciz "fatal-map"
mt_fatal_alloc: .asciz "fatal-alloc"
mt_fatal_realloc: .asciz "fatal-realloc"
mt_ok: .asciz "ok recoverable allocation\n"
