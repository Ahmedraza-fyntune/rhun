# Initial model authority composes with the root's complete catalog preflight.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# initial_check(svc,heldSource,sourceEpoch,futureELM)->0/-errno, pure.
# The caller retains futureELM and composes full CPcheck before any visible store.
FN ext_settings_service_initial_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call ext_settings_service_source_check
    test rax, rax
    js .Lsvic_done
    cmp qword ptr [rbx + SV_installed], 0
    jne .Lsvic_already
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvic_stale
    cmp qword ptr [rip + esv_live_model], 0
    jne .Lsvic_stale
    test r14, r14
    jz .Lsvic_bad
    cmp qword ptr [r14 + ELM_refs], 0
    jle .Lsvic_bad
    cmp qword ptr [r14 + ELM_ready], 1
    jne .Lsvic_again
    cmp [r14 + ELM_source], r12
    jne .Lsvic_stale
    mov rax, [rbx + SV_context]
    cmp [r14 + ELM_context], rax
    jne .Lsvic_stale
    mov r15, 0x7fffffffffffffff
    mov rax, [rip + esv_registry_epoch]
    test rax, rax
    jle .Lsvic_stale
    cmp rax, r15
    jae .Lsvic_overflow
    inc rax
    cmp [r14 + ELM_registry], rax
    jne .Lsvic_stale
    mov rax, [rip + esv_model_epoch]
    test rax, rax
    jle .Lsvic_stale
    cmp rax, r15
    jae .Lsvic_overflow
    inc rax
    cmp [r14 + ELM_epoch], rax
    jne .Lsvic_stale
    cmp qword ptr [r14 + ELM_provider_epoch], 0
    jle .Lsvic_stale
    mov rax, [rbx + SV_queue]
    mov rcx, [rax + EQ_epoch]
    test rcx, rcx
    jle .Lsvic_stale
    cmp [r14 + ELM_dirty], rcx
    jne .Lsvic_stale
    mov rcx, [rax + EQ_seq]
    test rcx, rcx
    js .Lsvic_stale
    cmp [r14 + ELM_sequence], rcx
    jne .Lsvic_stale
    xor eax, eax
.Lsvic_done:
    EPILOGUE
.Lsvic_already:
    mov rax, -114
    EPILOGUE
.Lsvic_stale:
    mov rax, -116
    EPILOGUE
.Lsvic_bad:
    mov rax, -22
    EPILOGUE
.Lsvic_again:
    mov rax, -11
    EPILOGUE
.Lsvic_overflow:
    mov rax, -75
    EPILOGUE
# VOID, only inside the root's checked callback immediately after CP model publish.
FN ext_settings_service_initial_publish
    mov qword ptr [rdi + SV_installed], 1
    mov qword ptr [rdi + SV_apply_error], 0
    mov qword ptr [rdi + SV_apply_rebuild], 0
    mov qword ptr [rdi + SV_apply_grant], 0
    mov qword ptr [rdi + SV_abort], 0
    ret
# One reference transfer outside authority publication. No native disposal here.
FN settings_service_source_retire
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lsvsr_wait
    mov rdi, [rbx + SV_replaced_source]
    test rdi, rdi
    jz .Lsvsr_ok
    call ext_settings_snapshot_release
    test rax, rax
    js .Lsvsr_retained
    mov qword ptr [rbx + SV_replaced_source], 0
    mov qword ptr [rbx + SV_retry_due], 0
    mov qword ptr [rbx + SV_retry_delay], 0
.Lsvsr_ok:
    xor eax, eax
    EPILOGUE
.Lsvsr_retained:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call settings_service_cleanup_error
    mov rdi, rbx
    call settings_service_cleanup_delay
    mov rax, r12
    EPILOGUE
.Lsvsr_wait:
    mov rax, -11
    EPILOGUE
