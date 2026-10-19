.include "rhun.inc"
.include "app/themecapture.inc"
.bss
.p2align 3
tcc_target: .quad 0
tcc_fault: .quad 0
tcc_calls: .quad 0
.section .rodata
tcc_path: .asciz "/theme"
.text
tcc_fail:
    mov edi, 73
    call sys_exit
FN tcc_munmap
    cmp rdi, [rip + tcc_target]
    jne 1f
    inc qword ptr [rip + tcc_calls]
    cmp qword ptr [rip + tcc_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN tcc_dispose
.if TCC_MODE == 0
    jmp tc_free
.else
    jmp theme_capture_request_free
.endif
FN main
    PROLOGUE 112
    mov r15, [rip + g_mem_live]
.if TCC_MODE == 0
    mov edi, TC_INPUT_CAP
    call tc_alloc_try
    test rax, rax
    jz tcc_fail
    mov rbx, rax
    mov r12, rax
.else
    mov rdi, rsp
    xor esi, esi
    mov edx, TCFG_SIZE
    call memset
    mov qword ptr [rsp + TCFG_job], 1
    mov qword ptr [rsp + TCFG_context], 2
    mov qword ptr [rsp + TCFG_nonce], 3
    mov rdi, rsp
    xor esi, esi
    call theme_capture_request_begin
    test rax, rax
    jz tcc_fail
    mov rbx, rax
    mov r12, [rax + TCQ_wire]
    # An in-flight request cannot transfer ownership to its public destructor.
    mov qword ptr [rax + TCQ_state], TCQ_OWNED
    mov rdi, rax
    call theme_capture_request_free
    cmp rax, -16
    jne tcc_fail
    test rdx, rdx
    jnz tcc_fail
    mov qword ptr [rbx + TCQ_state], TCQ_BUILDING
.endif
    lea rax, [r12 - 16]
    mov [rip + tcc_target], rax
    mov rax, [rax]
    mov [rsp + 80], rax
    mov r14, [rip + g_theme_capture_charge]
    mov rax, [rip + g_mem_live]
    mov [rsp + 88], rax
    mov qword ptr [rip + tcc_fault], 1
    mov r13d, 1
2:  mov rdi, rbx
    call tcc_dispose
    cmp rax, -5
    jne tcc_fail
    test rdx, rdx
    jnz tcc_fail
    cmp [rip + g_theme_capture_charge], r14
    jne tcc_fail
    mov rax, [rsp + 88]
    cmp [rip + g_mem_live], rax
    jne tcc_fail
    cmp [rip + tcc_calls], r13
    jne tcc_fail
    mov rax, [r12 - 16]
    cmp rax, [rsp + 80]
    jne tcc_fail
.if TCC_MODE == 1
    cmp qword ptr [rbx + TCQ_state], TCQ_RETIRING
    jne tcc_fail
    cmp [rbx + TCQ_wire], r12
    jne tcc_fail
    mov rax, 0x0031514552544852
    cmp [r12], rax
    jne tcc_fail
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + tcc_path]
    call theme_capture_request_add
    cmp rax, -22
    jne tcc_fail
    mov rdi, rbx
    call theme_capture_request_seal
    cmp rax, -22
    jne tcc_fail
.endif
    inc r13
    cmp r13, 2
    jbe 2b
    mov qword ptr [rip + tcc_fault], 0
    mov rdi, rbx
    call tcc_dispose
.if TCC_MODE == 0
    test rax, rax
.else
    cmp rax, -5
.endif
    jne tcc_fail
    cmp rdx, 1
    jne tcc_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcc_fail
    cmp [rip + g_mem_live], r15
    jne tcc_fail
    xor eax, eax
    EPILOGUE
