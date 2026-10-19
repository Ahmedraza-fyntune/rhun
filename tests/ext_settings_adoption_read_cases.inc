# Actual changed READ, allocation refusal, and fresh explicit READ with bounded retirement.
.bss
.p2align 3
.globl svar_fail_alloc
svar_fail_alloc: .quad 0
svar_pending: .quad 0
svar_oldmodel: .quad 0
.text
.globl svar_memory_try
svar_memory_try:
    cmp qword ptr [rip + svar_fail_alloc], 0
    je 1f
    cmp rdi, AP_SIZE
    jne 1f
    mov qword ptr [rip + svar_fail_alloc], 0
    xor eax, eax
    mov rdx, -12
    ret
1:  jmp svwf_memory_try
svar_step:
    PROLOGUE
    call time_ms
    mov rsi, rax
    mov rdi, [rip + svw_svc]
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    EPILOGUE
svar_retry:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 248
    mov rbx, [rip + svw_svc]
    mov rax, [rbx + SV_pending]
    mov [rip + svar_pending], rax
    mov rax, [rip + esv_live_model]
    mov [rip + svar_oldmodel], rax
    mov qword ptr [rip + svar_fail_alloc], 1
    call svar_step
    cmp qword ptr [rip + svar_fail_alloc], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_error], -12
    jne svw_fail
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_grant], 0
    jne svw_fail
    mov qword ptr [rip + svw_stage], 249
    mov rax, 0x7fffffffffffffff
    mov [rbx + SV_job_serial], rax
    mov rdi, rbx
    call ext_settings_service_refresh
    cmp rax, -75
    jne svw_fail
    mov rax, [rip + svar_pending]
    cmp [rbx + SV_pending], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne svw_fail
    mov qword ptr [rbx + SV_job_serial], 2
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    mov rax, [rip + svar_pending]
    cmp [rbx + SV_replaced_source], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 1
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 1
    jne svw_fail
    mov rax, [rip + svw_held]
    cmp [rbx + SV_source], rax
    jne svw_fail
    mov rax, [rip + svar_oldmodel]
    cmp [rip + esv_live_model], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_job_serial], 3
    jne svw_fail
    mov qword ptr [rip + svw_stage], 250
    call svar_step
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_REQUEST
    jne svw_fail
1:  call svar_step
    mov rax, [rbx + SV_sap]
    test rax, rax
    jz 2f
    cmp qword ptr [rax + AP_state], APS_READY
    je 3f
2:  call svw_wait
    jmp 1b
3:  mov qword ptr [rip + svw_stage], 251
    cmp qword ptr [rip + svwf_native_starts], 3
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 2
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_adoption
    test rax, rax
    jz svw_fail
    mov r12, rax
    mov rdi, r12
    call ext_settings_adoption_model
    test rax, rax
    jz svw_fail
    mov r13, rax
    mov qword ptr [rip + sva_pure], 1
    mov rdi, r12
    call ext_settings_adoption_check
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_publish
    mov qword ptr [rip + sva_pure], 0
    cmp [rip + esv_live_model], r13
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 0
    jne svw_fail
    mov rdi, r13
    call ext_settings_model_release
    mov rdi, r12
    call ext_settings_adoption_release
    mov r14d, 1024
4:  mov edi, 1
    call ext_settings_adoption_gc
    mov edi, 64
    call ext_settings_catalog_gc
    mov edi, 64
    call ext_settings_view_gc
    mov edi, 64
    call ext_settings_model_gc
    mov edi, 64
    call ext_settings_snapshot_gc
    dec r14
    jnz 4b
    mov rdi, rbx
    call ext_settings_service_can_start
    test rax, rax
    jnz svw_fail
    EPILOGUE
