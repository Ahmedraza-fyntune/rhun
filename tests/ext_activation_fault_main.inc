# Fault fixture main replaces only the normal main. Common setup/cleanup stays real.
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + af_live], rax
    cmp qword ptr [rip + g_argc], 3
    jne .Laf_fault_bad
    mov rax, [rip + g_argv]
    mov rax, [rax + 16]
    movzx r12d, byte ptr [rax]
    sub r12d, '0'
    cmp r12d, 6
    ja .Laf_fault_bad
    test r12d, r12d
    jz .Laf_fault_bad
    call af_setup
    cmp r12d, 1
    jne 1f
    mov qword ptr [rip + af_fail_at], 1
1:  cmp r12d, 2
    jne 2f
    mov qword ptr [rip + af_fail_at], 2
2:  cmp r12d, 3
    jne 3f
    mov qword ptr [rip + af_mark_fault], 1
3:  mov qword ptr [rip + af_armed], 1
    call af_new
    mov qword ptr [rip + af_armed], 0
    cmp qword ptr [rip + af_io_calls], 0
    jne .Laf_fault_bad
    cmp r12d, 3
    ja 5f
    test rdx, rdx
    jns .Laf_fault_bad
    cmp r12d, 2
    ja 4f
    test rax, rax
    jnz .Laf_fault_bad
    cmp rdx, -12
    jne .Laf_fault_bad
    jmp 9f
4:  test rax, rax
    jz .Laf_fault_bad
    cmp rdx, -22
    jne .Laf_fault_bad
    cmp qword ptr [rax - RD_PO_BACK + RD_kind], RD_LEDGER
    jne .Laf_fault_bad
    mov rdi, [rax + PO_eo]
    cmp qword ptr [rdi + EO_refs], 1
    jne .Laf_fault_bad
    mov rdi, rax
    call ext_activation_owner_release
    call af_consumed
    jmp 9f
5:  test rax, rax
    jz .Laf_fault_bad
    test rdx, rdx
    jnz .Laf_fault_bad
    mov rbx, rax
    cmp r12d, 5
    jne 6f
    mov qword ptr [rip + af_drop_mode], 1
6:  cmp r12d, 6
    jne 7f
    mov qword ptr [rip + af_drop_mode], 2
7:  mov rdi, rbx
    call ext_activation_owner_release
    call af_consumed
    cmp r12d, 4
    je 9f
    mov edi, 1
    lea rsi, [rip + af_status]
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Laf_fault_bad
    cmp qword ptr [rip + af_status + 24], -5
    jne .Laf_fault_bad
    cmp r12d, 6
    je 8f
    mov rax, [rip + af_ep]
    cmp [rbx + EA_ep], rax
    jne .Laf_fault_bad
    cmp qword ptr [rax + PO_refs], 2
    jne .Laf_fault_bad
    cmp qword ptr [rip + af_status + 16], 1
    jne .Laf_fault_bad
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne .Laf_fault_bad
    cmp rdx, 1
    jne .Laf_fault_bad
    jmp 9f
8:  cmp qword ptr [rbx + EA_ep], 0
    jne .Laf_fault_bad
    mov rax, [rip + af_ep]
    cmp qword ptr [rax + PO_refs], 1
    jne .Laf_fault_bad
9:  call af_fault_drain
    call ext_prepare_retire_ack
    test rax, rax
    jnz .Laf_fault_bad
    mov rdi, [rip + af_ep]
    cmp qword ptr [rdi + PO_refs], 1
    jne .Laf_fault_bad
    call ext_prepare_release_deferred
    call af_consumed
    call af_drain
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Laf_fault_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + af_live]
    jne .Laf_fault_bad
    xor eax, eax
    EPILOGUE
.Laf_fault_bad:
    mov eax, 90
    EPILOGUE

af_fault_drain:
    PROLOGUE
    mov rbx, 4096
1:  mov edi, 1
    lea rsi, [rip + af_status]
    call ext_prepare_retire_step
    test rax, rax
    js .Laf_abort
    cmp qword ptr [rip + af_status], 1
    ja .Laf_abort
    cmp qword ptr [rip + af_status + 16], 0
    jne .Laf_abort
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp .Laf_abort
2:  EPILOGUE
