# One service-owned local category. Exported owner stepping stays with root.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.text
# Internal, ordinary IDLE/jobNULL and no SRT. 0 action,1 quiescent.
FN settings_service_adoption_step
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + SV_commit], 1
    jne .Laps_module
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACKED
    je .Laps_batch
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    je .Laps_batch
.Laps_module:
    mov r12, [rip + settings_adoption_scheduler]
    test r12, r12
    jz .Laps_admit
    cmp [r12 + AP_svc], rbx
    jne .Laps_quiet
    cmp qword ptr [r12 + AP_state], APS_CANCELED
    je .Laps_canceled
    mov rdi, r12
    call settings_adoption_current
    test rax, rax
    js .Laps_fail
    cmp qword ptr [r12 + AP_state], APS_READY
    je .Laps_ready
    mov rdi, r12
    call settings_adoption_build_step
    test rax, rax
    js .Laps_fail
    # The next category performs complete READY preflight, never assumes ACK capacity.
    jmp .Laps_action
.Laps_ready:
    mov rdi, r12
    call ext_settings_adoption_check
    test rax, rax
    js .Laps_fail
    jmp .Laps_quiet
.Laps_admit:
    cmp qword ptr [rbx + SV_sap], 0
    jne .Laps_quiet
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Laps_quiet
    cmp qword ptr [rbx + SV_apply_grant], 1
    jne .Laps_quiet
    mov rdi, rbx
    call settings_adoption_domain
    test rax, rax
    js .Laps_quiet
    mov rdi, rbx
    call settings_adoption_begin
    test rax, rax
    jns .Laps_action
    mov qword ptr [rbx + SV_apply_grant], 0
    mov [rbx + SV_apply_error], rax
    jmp .Laps_action
.Laps_fail:
    mov r13, rax
    mov r14, [r12 + AP_pending]
    mov r15, [r12 + AP_pendingepoch]
    mov rdi, r12
    call ext_settings_adoption_cancel
    test rax, rax
    js .Laps_owner_error
    mov qword ptr [rip + settings_adoption_scheduler], 0
    mov rdi, r12
    call ext_settings_adoption_release
    test rax, rax
    js .Laps_owner_error
    mov qword ptr [rbx + SV_apply_grant], 0
    cmp r13, -116
    jne .Laps_sticky
    cmp [rbx + SV_pending], r14
    jne .Laps_sticky
    cmp [rbx + SV_pending_epoch], r15
    jne .Laps_sticky
    cmp qword ptr [rbx + SV_apply_rebuild], 3
    jae .Laps_sticky
    inc qword ptr [rbx + SV_apply_rebuild]
    cmp qword ptr [rbx + SV_apply_rebuild], 3
    jae .Laps_sticky
    mov rdi, rbx
    call settings_adoption_domain
    test rax, rax
    js .Laps_sticky
    mov qword ptr [rbx + SV_apply_grant], 1
    jmp .Laps_action
.Laps_sticky:
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Laps_action
    mov [rbx + SV_apply_error], r13
    jmp .Laps_action
.Laps_canceled:
    mov qword ptr [rip + settings_adoption_scheduler], 0
    mov rdi, r12
    call ext_settings_adoption_release
    test rax, rax
    js .Laps_owner_error
    mov qword ptr [rbx + SV_apply_grant], 0
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Laps_action
    mov qword ptr [rbx + SV_apply_error], -125
    jmp .Laps_action
.Laps_owner_error:
    # Refusal cannot erase the module's owned pointer.
    mov [rip + settings_adoption_scheduler], r12
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Laps_quiet
    mov [rbx + SV_apply_error], rax
    jmp .Laps_quiet
.Laps_batch:
    mov rdi, rbx
    call settings_service_ack_retire
.Laps_action:
    xor eax, eax
    EPILOGUE
.Laps_quiet:
    mov eax, 1
    EPILOGUE
# One checked batch disposal. SELF_DEBT means refs/Q accounting already detached once.
FN settings_service_ack_retire
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lapsbr_done
    mov rdi, [rbx + SV_batch]
    test rdi, rdi
    jz .Lapsbr_protocol
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    je .Lapsbr_self
    mov qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    call ext_settings_batch_free
    jmp .Lapsbr_result
.Lapsbr_self:
    call ext_settings_memory_free
.Lapsbr_result:
    cmp rcx, 1
    jne .Lapsbr_retained
    mov qword ptr [rbx + SV_batch], 0
    mov qword ptr [rbx + SV_batch_phase], SVB_NONE
    mov qword ptr [rbx + SV_commit], 0
    mov qword ptr [rbx + SV_retry_due], 0
    mov qword ptr [rbx + SV_retry_delay], 0
    mov rdi, rbx
    mov rsi, rdx
    call settings_service_cleanup_error
    jmp .Lapsbr_done
.Lapsbr_retained:
    mov rdi, rbx
    mov rsi, rax
    call settings_service_cleanup_error
    mov rdi, rbx
    call settings_service_cleanup_delay
    jmp .Lapsbr_done
.Lapsbr_protocol:
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lapsbr_done
    mov qword ptr [rbx + SV_apply_error], -71
.Lapsbr_done:
    xor eax, eax
    EPILOGUE
# Pure cadence matches executable admission. Settled exported/ready work waits on root.
FN settings_service_adoption_timeout
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lapst_none
    cmp qword ptr [rbx + SV_commit], 1
    jne .Lapst_module
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACKED
    je .Lapst_batch
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    je .Lapst_batch
.Lapst_module:
    mov r13, [rip + settings_adoption_scheduler]
    test r13, r13
    jz .Lapst_admit
    cmp [r13 + AP_svc], rbx
    jne .Lapst_none
    cmp qword ptr [r13 + AP_state], APS_READY
    jne .Lapst_one
    mov rdi, r13
    call ext_settings_adoption_check
    test rax, rax
    jnz .Lapst_one
    jmp .Lapst_none
.Lapst_admit:
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lapst_none
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lapst_none
    cmp qword ptr [rbx + SV_apply_grant], 1
    jne .Lapst_none
    mov rdi, rbx
    call settings_adoption_domain
    test rax, rax
    js .Lapst_none
    jmp .Lapst_one
.Lapst_batch:
    mov rax, [rbx + SV_retry_due]
    cmp rax, r12
    jbe .Lapst_one
    sub rax, r12
    EPILOGUE
.Lapst_one:
    mov eax, 1
    EPILOGUE
.Lapst_none:
    mov rax, -1
    EPILOGUE
