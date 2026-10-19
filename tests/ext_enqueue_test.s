.include "rhun.inc"
.section .rodata
ee_prefix: .ascii "ABCDEFGHIJKL"
ee_payload: .ascii "xyz1234"
ee_expected: .ascii "ABCDEFGHIJKLxyz"
ee_ok: .asciz "ok bounded extension enqueue\n"
.bss
.p2align 3
ee_ext: .zero EXT_SIZE
ee_live: .quad 0
ee_pointer: .quad 0
ee_stage: .quad 0
.globl ee_fail_alloc
ee_fail_alloc: .quad 0
.text
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + ee_live], rax
    lea rbx, [rip + ee_ext]
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_in], 9999
    mov edi, 16
    call mem_alloc_try
    test rax, rax
    jz .Lee_fail
    mov [rbx + EXT_wq + SB_ptr], rax
    mov [rip + ee_pointer], rax
    mov qword ptr [rbx + EXT_wq + SB_cap], 16
    mov qword ptr [rbx + EXT_wq + SB_len], 12
    mov rdi, rax
    lea rsi, [rip + ee_prefix]
    mov edx, 12
    call memcpy
    mov qword ptr [rip + ee_stage], 1
    call ee_send3
    test rax, rax
    jnz .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 15
    jne .Lee_fail
    mov rdi, [rbx + EXT_wq + SB_ptr]
    lea rsi, [rip + ee_expected]
    mov edx, 15
    call memeq
    test eax, eax
    jz .Lee_fail
    mov qword ptr [rip + ee_stage], 2
    mov qword ptr [rbx + EXT_wq_off], 4
    mov r12, [rip + g_mem_live]
    call ee_send3
    cmp rax, -11
    jne .Lee_fail
    cmp r12, [rip + g_mem_live]
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 15
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq_off], 4
    jne .Lee_fail
    mov qword ptr [rip + ee_stage], 3
    mov qword ptr [rbx + EXT_wq_off], 15
    call ee_send3
    test rax, rax
    jnz .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 3
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne .Lee_fail
    mov rdi, [rbx + EXT_wq + SB_ptr]
    lea rsi, [rip + ee_payload]
    mov edx, 3
    call memeq
    test eax, eax
    jz .Lee_fail
    mov qword ptr [rip + ee_stage], 4
    mov rdi, rbx
    mov rsi, [rbx + EXT_wq + SB_ptr]
    mov edx, 1
    mov ecx, 1
    call ext_send_enqueue_bounded
    cmp rax, -22
    jne .Lee_fail
    mov qword ptr [rbx + EXT_wq_off], 4
    call ee_send3
    cmp rax, -22
    jne .Lee_fail
    mov qword ptr [rbx + EXT_wq_off], 0
    mov dword ptr [rbx + EXT_retiring], 1
    call ee_send3
    cmp rax, -32
    jne .Lee_fail
    mov dword ptr [rbx + EXT_retiring], 0
    mov rdi, [rbx + EXT_wq + SB_ptr]
    call mem_free
    mov qword ptr [rbx + EXT_wq + SB_ptr], 0
    mov qword ptr [rbx + EXT_wq + SB_cap], 0
    mov qword ptr [rbx + EXT_wq + SB_len], 0
    mov qword ptr [rip + ee_stage], 5
.ifdef TEST_ENQUEUE_FAULT
    mov qword ptr [rip + ee_fail_alloc], 1
    call ee_send3
    cmp rax, -12
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_ptr], 0
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_cap], 0
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 0
    jne .Lee_fail
.endif
    call ee_send3
    test rax, rax
    jnz .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_cap], 65536
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 3
    jne .Lee_fail
    mov rdi, [rbx + EXT_wq + SB_ptr]
    call mem_free
    mov qword ptr [rip + ee_stage], 6
    mov edi, EXT_WQ_HARD + 64
    call mem_alloc_try
    test rax, rax
    jz .Lee_fail
    mov [rbx + EXT_wq + SB_ptr], rax
    mov qword ptr [rbx + EXT_wq + SB_cap], EXT_WQ_HARD + 64
    mov qword ptr [rbx + EXT_wq + SB_len], EXT_WQ_HARD - 1
    mov rdi, rbx
    lea rsi, [rip + ee_payload]
    mov edx, 1
    mov ecx, 1
    call ext_send_enqueue_bounded
    cmp rax, -11
    jne .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], EXT_WQ_HARD - 1
    jne .Lee_fail
    mov qword ptr [rbx + EXT_wq + SB_len], EXT_WQ_HARD - 8
    mov rdi, rbx
    lea rsi, [rip + ee_payload]
    mov edx, 7
    mov ecx, 7
    call ext_send_enqueue_bounded
    test rax, rax
    jnz .Lee_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], EXT_WQ_HARD - 1
    jne .Lee_fail
    mov rdi, [rbx + EXT_wq + SB_ptr]
    call mem_free
    mov rax, [rip + ee_live]
    cmp rax, [rip + g_mem_live]
    jne .Lee_fail
    lea rdi, [rip + ee_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lee_fail:
    mov rdi, [rip + ee_stage]
    call sys_exit

ee_send3:
    mov rdi, rbx
    lea rsi, [rip + ee_payload]
    mov edx, 3
    mov ecx, 3
    jmp ext_send_enqueue_bounded

.ifdef TEST_ENQUEUE_FAULT
FN ee_alloc
    cmp qword ptr [rip + ee_fail_alloc], 0
    je 1f
    mov qword ptr [rip + ee_fail_alloc], 0
    xor eax, eax
    ret
1:  jmp mem_alloc_try
FN ee_poison
    mov edi, 80
    jmp sys_exit
.endif
