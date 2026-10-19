.include "rhun.inc"
.include "app/extstore.inc"
.section .rodata
esgt_ready: .ascii "READY\n"
esgt_released: .ascii "RELEASED\n"
.text
esgt_fail:
    mov edi, 74
    call sys_exit
esgt_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne esgt_fail
    EPILOGUE
FN main
    PROLOGUE 96
    cmp qword ptr [rip + g_argc], 5
    je 9f
    cmp qword ptr [rip + g_argc], 10
    jne esgt_fail
9:  mov r15, [rip + g_mem_live]
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    call esgt_number
    mov [rsp], rax
    mov rdi, [rbx + 24]
    call esgt_number
    mov [rsp + 8], rax
    mov rdi, [rbx + 32]
    call esgt_number
    mov [rsp + 16], rax
    mov rdi, [rbx + 8]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    mov r12, rax
    mov [rsp + 48], rdx
    mov [rsp + 56], rcx
    mov r14, -1
    test rax, rax
    jz 4f
    cmp qword ptr [rip + g_argc], 10
    jne 2f
    mov rdi, [rbx + 64]
    call esgt_number
    mov [rsp + 24], rax
    mov rdi, [rbx + 72]
    call esgt_number
    mov [rsp + 32], rax
    mov rdi, r12
    mov rsi, [rbx + 40]
    mov rdx, [rbx + 48]
    mov rcx, [rbx + 56]
    cmp byte ptr [rcx], '-'
    jne 1f
    xor ecx, ecx
1:  mov r8, [rsp + 24]
    mov r9, [rsp + 32]
    call ext_store_lease_try
    test rax, rax
    jns 11f
    mov [rsp + 48], rax
    mov [rsp + 56], rdx
    jmp 12f
11: mov r14, rax
12: mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esgt_fail
    xor r12d, r12d
2:  cmp qword ptr [rsp + 48], 0
    jne 4f
    cmp qword ptr [rsp + 16], 0
    je 4f
    mov edi, 1
    lea rsi, [rip + esgt_ready]
    mov edx, 6
    call write_all
    test rax, rax
    jnz esgt_fail
    xor edi, edi
    lea rsi, [rsp + 80]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne esgt_fail
3:  cmp r14, -1
    je 31f
    mov rdi, r14
    call ext_root_close
    test rax, rax
    jnz esgt_fail
    mov r14, -1
31: test r12, r12
    jz 32f
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esgt_fail
    xor r12d, r12d
32: mov edi, 1
    lea rsi, [rip + esgt_released]
    mov edx, 9
    call write_all
    test rax, rax
    jnz esgt_fail
    jmp 6f
4:  cmp r14, -1
    je 5f
    mov rdi, r14
    call ext_root_close
    test rax, rax
    jnz esgt_fail
5:  mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esgt_fail
    mov edi, 1
    lea rsi, [rsp + 48]
    mov edx, 16
    call write_all
    test rax, rax
    jnz esgt_fail
6:  cmp r15, [rip + g_mem_live]
    jne esgt_fail
    xor eax, eax
    EPILOGUE
