.include "rhun.inc"
.data
sw_entry_sigact: .quad 1,0,0,0
.ifdef TEST_SETTINGS_WORKER_ALLOC_FAULT
.bss
sw_fail_remaining: .quad 0
sw_fail_observed: .quad 0
.text
FN mem_alloc_try
    cmp qword ptr [rip + sw_fail_remaining], 0
    je 1f
    dec qword ptr [rip + sw_fail_remaining]
    jne 1f
    mov qword ptr [rip + sw_fail_observed], 1
    xor eax, eax
    ret
1:  jmp sw_real_mem_alloc_try
.endif
.text
FN main
    PROLOGUE
    mov edi, 13
    lea rsi, [rip + sw_entry_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
.ifdef TEST_SETTINGS_WORKER_ALLOC_FAULT
    mov rax, [rip + g_argv]
    mov rax, [rax + 24]
    xor ecx, ecx
1:  movzx edx, byte ptr [rax]
    test edx, edx
    jz 2f
    imul rcx, rcx, 10
    sub edx, '0'
    add rcx, rdx
    inc rax
    jmp 1b
2:  mov [rip + sw_fail_remaining], rcx
.endif
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
.ifdef TEST_SETTINGS_WORKER_ALLOC_FAULT
    mov r15, [rip + g_mem_live]
.endif
    call ext_settings_worker_main
.ifdef TEST_SETTINGS_WORKER_ALLOC_FAULT
    mov rbx, rax
    cmp [rip + g_mem_live], r15
    jne 3f
    cmp qword ptr [rip + sw_fail_observed], 0
    je 4f
    mov rax, rbx
    EPILOGUE
3:  mov eax, 90
    EPILOGUE
4:  mov eax, 91
.endif
    EPILOGUE
