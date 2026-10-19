# Actual CG scheduler retains unconsumed suppliers and consumes a negative result exactly once.
.bss
.p2align 3
cgbt_retire_mode: .quad 0
cgbt_drop_ep_calls: .quad 0
cgbt_drop_ro_calls: .quad 0
cgbt_ep_consumed: .quad 0
cgbt_ro_consumed: .quad 0
cgbt_ledger_calls: .quad 0
.text
FN cgbt_drop_ep
    cmp qword ptr [rip + cgbt_retire_mode], 0
    je ext_prepare_release_deferred
    inc qword ptr [rip + cgbt_drop_ep_calls]
    cmp qword ptr [rip + cgbt_retire_mode], 1
    jne 1f
    cmp qword ptr [rip + cgbt_drop_ep_calls], 1
    jne 1f
    mov rax, -5
    xor edx, edx
    ret
1:  PROLOGUE
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne 2f
    inc qword ptr [rip + cgbt_ep_consumed]
    cmp qword ptr [rip + cgbt_retire_mode], 3
    jne 2f
    mov rax, -7
2:  EPILOGUE
FN cgbt_drop_ro
    cmp qword ptr [rip + cgbt_retire_mode], 0
    je ext_runtime_release_deferred
    inc qword ptr [rip + cgbt_drop_ro_calls]
    cmp qword ptr [rip + cgbt_retire_mode], 2
    jne 1f
    cmp qword ptr [rip + cgbt_drop_ro_calls], 1
    jne 1f
    mov rax, -6
    xor edx, edx
    ret
1:  PROLOGUE
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne 2f
    inc qword ptr [rip + cgbt_ro_consumed]
2:  EPILOGUE
FN cgbt_ledger
    cmp qword ptr [rip + cgbt_retire_mode], 0
    je ext_prepare_retire_handoff_ledger
    inc qword ptr [rip + cgbt_ledger_calls]
    cmp qword ptr [rip + cgbt_retire_mode], 4
    jne ext_prepare_retire_handoff_ledger
    cmp qword ptr [rip + cgbt_ledger_calls], 1
    jne ext_prepare_retire_handoff_ledger
    mov rax, -8
    ret
cgbt_retire_faults:
    PROLOGUE
    mov r14d, 1
.Lcgbtr_case:
    mov qword ptr [rip + cgbt_stage], 22
    call ext_prepare_retire_ack
    test rax, rax
    jnz cgbt_fail
    mov qword ptr [rip + cgbt_retire_mode], 0
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov r12, rdx
    mov r13, rcx
    mov rdi, rbx
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov qword ptr [rip + cgbt_drop_ep_calls], 0
    mov qword ptr [rip + cgbt_drop_ro_calls], 0
    mov qword ptr [rip + cgbt_ep_consumed], 0
    mov qword ptr [rip + cgbt_ro_consumed], 0
    mov qword ptr [rip + cgbt_ledger_calls], 0
    mov [rip + cgbt_retire_mode], r14
    mov qword ptr [rip + cgbt_stage], 23
    mov rdi, rbx
    call command_generation_retain
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne cgbt_fail
    mov rdi, rbx
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [rip + prep_retire_ready_count], 0
    jne cgbt_fail
    mov rdi, rbx
    call command_generation_release_deferred
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_drop_ep_calls], 0
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_drop_ro_calls], 0
    jne cgbt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgbt_fail
    cmp r14, 3
    je .Lcgbtr_drain
    mov r15d, 1000
.Lcgbtr_until_blocked:
    mov qword ptr [rip + cgbt_stage], 24
    mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cgbt_retire], 1
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_retire + 16], 1
    je .Lcgbtr_blocked
    dec r15
    jnz .Lcgbtr_until_blocked
    jmp cgbt_fail
.Lcgbtr_blocked:
    mov qword ptr [rip + cgbt_stage], 25
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], 4
    jne cgbt_fail
    cmp r14, 1
    jne 1f
    cmp [rbx + CG_slots + CS_ep], r12
    jne cgbt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [rbx + CG_retirephase], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_retirecursor], 0
    jne cgbt_fail
    jmp 3f
1:  cmp qword ptr [rbx + CG_slots + CS_ep], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_retirephase], 1
    jne cgbt_fail
    cmp r14, 2
    jne 2f
    cmp [rbx + CG_runtimes], r13
    jne cgbt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgbt_fail
    cmp qword ptr [rbx + CG_retirecursor], 0
    jne cgbt_fail
    jmp 3f
2:  cmp qword ptr [rbx + CG_runtimes], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_retirecursor], 1
    jne cgbt_fail
3:  mov qword ptr [rip + cgbt_stage], 26
    mov r12, [rip + cgbt_drop_ep_calls]
    mov r13, [rip + cgbt_drop_ro_calls]
    mov r15d, 1000
4:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cgbt_retire + 16], 1
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_retire], 1
    ja cgbt_fail
    cmp qword ptr [rip + cgbt_retire + 8], 0
    je 5f
    dec r15
    jnz 4b
    jmp cgbt_fail
5:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cgbt_retire], 0
    jne cgbt_fail
    cmp [rip + cgbt_drop_ep_calls], r12
    jne cgbt_fail
    cmp [rip + cgbt_drop_ro_calls], r13
    jne cgbt_fail
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
.Lcgbtr_drain:
    mov qword ptr [rip + cgbt_stage], 27
    call cgbt_drain
    cmp qword ptr [rip + cgbt_ep_consumed], 1
    jne cgbt_fail
    cmp qword ptr [rip + cgbt_ro_consumed], 1
    jne cgbt_fail
    mov rax, -5
    cmp r14, 1
    je 1f
    sub rax, r14
    inc rax
1:  cmp [rip + prep_retire_first_diagnostic], rax
    jne cgbt_fail
    mov qword ptr [rip + cgbt_retire_mode], 0
    call ext_prepare_retire_ack
    test rax, rax
    jnz cgbt_fail
    inc r14
    cmp r14, 4
    jbe .Lcgbtr_case
    EPILOGUE
