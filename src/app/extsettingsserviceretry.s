# Explicit local/user retry grants. No timer or newer edit clears sticky failure.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
FN ext_settings_service_refresh
    mov esi, 1
    jmp settings_service_explicit_retry
FN ext_settings_service_retry_save
    mov esi, 2
settings_service_explicit_retry:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call settings_service_domain
    test rax, rax
    js .Lsvr_done
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_provisional], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvr_busy
    cmp qword ptr [rip + settings_adoption_scheduler], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvr_unknown
    cmp qword ptr [rbx + SV_commit], 0
    jne .Lsvr_local_commit
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvr_abandon_pending
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lsvr_busy
    cmp r12, 2
    jne .Lsvr_serial
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lsvr_again
    mov rax, [rbx + SV_queue]
    cmp qword ptr [rax + EQ_count], 0
    je .Lsvr_again
.Lsvr_serial:
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_job_serial], rax
    jae .Lsvr_overflow
.Lsvr_new_intent:
    # All rejection and overflow checks precede any changed intent/state.
    mov [rbx + SV_mode], r12
    mov qword ptr [rbx + SV_primary], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_apply_rebuild], 0
    mov qword ptr [rbx + SV_apply_grant], 0
    mov qword ptr [rbx + SV_abort], 0
    mov qword ptr [rbx + SV_retry_count], 0
    mov qword ptr [rbx + SV_retry_pending], 0
    mov rdi, rbx
    call settings_service_operation_tag
    mov eax, SVP_REQUEST
    cmp r12, 1
    je 1f
    mov eax, SVP_BATCH
1:  mov [rbx + SV_phase], rax
    xor eax, eax
    jmp .Lsvr_done
.Lsvr_local_commit:
    cmp r12, 1
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACK_WAITING
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_batch], 0
    je .Lsvr_busy
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvr_local_adoption
    mov rax, [rbx + SV_delivery]
    test rax, rax
    jz .Lsvr_busy
    cmp qword ptr [rax + EJF_kind], EW_COMMITTED
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_apply_error], 0
    jge .Lsvr_busy
    cmp qword ptr [rbx + SV_conversion_tried], 1
    jne .Lsvr_busy
    # A local allocation retry never constructs a new native job/tag or clears truth.
    mov qword ptr [rbx + SV_conversion_tried], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_phase], SVP_FINISH
    xor eax, eax
    jmp .Lsvr_done
.Lsvr_local_adoption:
    cmp qword ptr [rbx + SV_apply_error], 0
    jge .Lsvr_busy
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsvr_busy
    mov qword ptr [rbx + SV_apply_rebuild], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_apply_grant], 1
    xor eax, eax
    jmp .Lsvr_done
.Lsvr_abandon_pending:
    cmp r12, 1
    jne .Lsvr_busy
    cmp qword ptr [rbx + SV_apply_error], 0
    jge .Lsvr_busy
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lsvr_busy
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_job_serial], rax
    jae .Lsvr_overflow
    mov rax, [rbx + SV_pending]
    mov [rbx + SV_replaced_source], rax
    mov qword ptr [rbx + SV_pending], 0
    jmp .Lsvr_new_intent
.Lsvr_busy:
    mov rax, -16
    jmp .Lsvr_done
.Lsvr_unknown:
    mov rax, -117
    jmp .Lsvr_done
.Lsvr_again:
    mov rax, -11
    jmp .Lsvr_done
.Lsvr_overflow:
    mov rax, -75
.Lsvr_done:
    EPILOGUE
# status(SVC,out112)->0/-EINVAL. Diagnostic copy, no saved/model-adoption assertion.
FN ext_settings_service_status
    test rdi, rdi
    jz .Lsvstatus_bad
    test rsi, rsi
    jz .Lsvstatus_bad
    mov rax, SVC_MAGIC
    cmp [rdi + SV_magic], rax
    jne .Lsvstatus_bad
    cmp qword ptr [rdi + SV_refs], 0
    jle .Lsvstatus_bad
    mov rax, [rdi + SV_installed]
    mov [rsi], rax
    xor eax, eax
    mov rcx, [rdi + SV_queue]
    test rcx, rcx
    jz 1f
    mov rax, [rcx + EQ_count]
1:  mov [rsi + 8], rax
    xor eax, eax
    cmp qword ptr [rdi + SV_batch], 0
    setne al
    mov [rsi + 16], rax
    mov rax, [rdi + SV_commit]
    mov [rsi + 24], rax
    mov rax, [rdi + SV_uncertain]
    mov [rsi + 32], rax
    mov rax, [rdi + SV_primary]
    mov [rsi + 40], rax
    mov rax, [rdi + SV_observation]
    mov [rsi + 48], rax
    mov rax, [rdi + SV_cleanup]
    mov [rsi + 56], rax
    mov rax, [rdi + SV_source_epoch]
    mov [rsi + 64], rax
    mov rax, [rdi + SV_pending_epoch]
    mov [rsi + 72], rax
    mov rax, [rdi + SV_phase]
    mov [rsi + 80], rax
    mov rax, [rdi + SV_mode]
    mov [rsi + 88], rax
    mov rax, [rdi + SV_apply_error]
    mov [rsi + 96], rax
    mov rax, [rdi + SV_batch_phase]
    mov [rsi + 104], rax
    xor eax, eax
    ret
.Lsvstatus_bad:
    mov rax, -22
    ret
