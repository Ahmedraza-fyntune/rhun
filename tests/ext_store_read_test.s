.include "rhun.inc"
.include "app/extstore.inc"
.bss
.p2align 3
esrt_cancel_at: .quad 0
esrt_calls: .quad 0
.text
esrt_fail:
    mov edi, 73
    call sys_exit
esrt_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne esrt_fail
    EPILOGUE
esrt_cancel:
    inc qword ptr [rip + esrt_calls]
    mov rax, [rip + esrt_calls]
    cmp rax, [rip + esrt_cancel_at]
    jne 1f
    mov rax, -125
    ret
1:  xor eax, eax
    ret
FN main
    PROLOGUE 112
    mov r15, [rip + g_mem_live]
    cmp qword ptr [rip + g_argc], 4
    jne esrt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov rdi, [rax + 16]
    call esrt_number
    mov [rip + esrt_cancel_at], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call esrt_number
    test rax, rax
    jz esrt_fail
    cmp rax, 64
    ja esrt_fail
    mov r13, rax
1:  mov qword ptr [rip + esrt_calls], 0
    mov rdi, r12
    lea rsi, [rip + esrt_cancel]
    xor edx, edx
    call ext_store_snapshot_try
    mov rbx, rax
    mov [rsp + 64], rdx
    mov [rsp + 72], rcx
    mov qword ptr [rsp + 80], 0
    xor r14d, r14d
    test rax, rax
    jz 2f
    mov rdi, rsp
    xor esi, esi
    mov edx, EST_SIZE
    call memset
    mov qword ptr [rsp + EST_epoch], 7
    mov qword ptr [rsp + EST_job], 9
    lea rdi, [rsp + EST_root_id]
    lea rsi, [rbx + ESS_tag + EST_root_id]
    mov edx, 32
    call memcpy
    mov rdi, rbx
    mov rsi, rsp
    call ext_store_snapshot_pack_try
    test rax, rax
    jz esrt_fail
    mov r14, rax
    mov [rsp + 80], rdx
2:  cmp r13, 1
    jne 3f
    mov edi, 1
    lea rsi, [rsp + 64]
    mov edx, 24
    call write_all
    test rax, rax
    jnz esrt_fail
    mov edi, 1
    mov rsi, r14
    mov rdx, [rsp + 80]
    call write_all
    test rax, rax
    jnz esrt_fail
3:  mov rdi, r14
    call mem_free
    mov rdi, rbx
    call ext_store_snapshot_free
    cmp r15, [rip + g_mem_live]
    jne esrt_fail
    dec r13
    jnz 1b
    xor eax, eax
    EPILOGUE
