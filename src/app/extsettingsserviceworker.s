# Ordinary operation launch. Native authority stays entirely within reviewed ECJ.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.include "app/extsettingsrequest.inc"
.text
# Internal fixed error transition. No owned pointer is disposed by an errno.
FN settings_service_operation_fail
    test rsi, rsi
    js 1f
    mov rsi, -5
1:  mov [rdi + SV_final_primary], rsi
    mov qword ptr [rdi + SV_final_state], ECJS_PRECOMMIT_FAILED
    mov qword ptr [rdi + SV_final_flags], 0
    mov qword ptr [rdi + SV_phase], SVP_FINISH
    xor eax, eax
    ret
# Internal new exact tag. Retry retains the immutable accepted batch.
FN settings_service_operation_tag
    mov rax, 0x7fffffffffffffff
    cmp [rdi + SV_job_serial], rax
    jae 1f
    inc qword ptr [rdi + SV_job_serial]
    mov rax, [rdi + SV_job_serial]
    mov [rdi + SV_tag], rax
    mov rax, [rdi + SV_context]
    mov [rdi + SV_tag + 8], rax
    mov rax, [rdi + SV_nonce]
    mov [rdi + SV_tag + 16], rax
    mov rax, [rdi + SV_nonce + 8]
    mov [rdi + SV_tag + 24], rax
    mov qword ptr [rdi + SV_commit], 0
    mov qword ptr [rdi + SV_final_state], 0
    mov qword ptr [rdi + SV_final_primary], 0
    mov qword ptr [rdi + SV_final_flags], 0
    mov qword ptr [rdi + SV_final_observation], 0
    mov qword ptr [rdi + SV_conversion_tried], 0
    mov qword ptr [rdi + SV_control_sent], 0
    mov qword ptr [rdi + SV_native_turn], 1
    mov qword ptr [rdi + SV_retry_due], 0
    mov qword ptr [rdi + SV_retry_delay], 0
    xor eax, eax
    ret
1:  mov rax, -75
    ret
# step(SVC,now)->0 pending/1 quiescent/-EINVAL,RDX sticky diagnostic.
FN ext_settings_service_step
    test rdi, rdi
    jz .Lsvw_bad_leaf
    test rsi, rsi
    js .Lsvw_bad_leaf
    PROLOGUE 48
    mov rbx, rdi
    mov rax, SVC_MAGIC
    cmp [rbx + SV_magic], rax
    jne .Lsvw_bad
    cmp qword ptr [rbx + SV_refs], 0
    jle .Lsvw_bad
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jb .Lsvw_bad
    cmp qword ptr [rbx + SV_state], SV_SHUTTING
    ja .Lsvw_bad
    mov [rbx + SV_now], rsi
    call settings_service_domain
    test rax, rax
    js .Lsvw_abort
    cmp qword ptr [rbx + SV_state], SV_SHUTTING
    jne .Lsvw_dispatch
    mov rax, -125
.Lsvw_abort:
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvw_dispatch
    mov qword ptr [rbx + SV_abort], 1
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsvw_dispatch
    mov [rbx + SV_primary], rax
.Lsvw_dispatch:
    # Memory-only old-source retirement also progresses in canceled/shutdown domains.
    cmp qword ptr [rbx + SV_replaced_source], 0
    je 9f
    cmp qword ptr [rbx + SV_job], 0
    jne 9f
    mov rdi, rbx
    call settings_service_source_retire
    jmp .Lsvw_return
9:
    # A transaction token has exclusive stepping authority over its separate job.
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne 7f
    cmp qword ptr [rbx + SV_job], 0
    jne 7f
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvw_adoption
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvw_adoption
    mov rax, [rip + settings_adoption_scheduler]
    test rax, rax
    jz 8f
    cmp [rax + AP_svc], rbx
    je .Lsvw_adoption
8:  cmp qword ptr [rbx + SV_commit], 1
    jne 7f
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACKED
    je .Lsvw_adoption
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    je .Lsvw_adoption
7:
    cmp qword ptr [rbx + SV_abort], 0
    je .Lsvw_phase
    cmp qword ptr [rbx + SV_job], 0
    je .Lsvw_abort_unlaunched
    cmp qword ptr [rbx + SV_abort], 1
    jne .Lsvw_phase
    mov rdi, [rbx + SV_job]
    call ext_settings_job_cancel
    mov qword ptr [rbx + SV_abort], 2
    jmp .Lsvw_return
.Lsvw_abort_unlaunched:
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    je .Lsvw_idle_return
    cmp qword ptr [rbx + SV_phase], SVP_FINISH
    jae .Lsvw_phase
    mov qword ptr [rbx + SV_final_state], ECJS_CANCELED
    mov rax, [rbx + SV_primary]
    mov [rbx + SV_final_primary], rax
    mov qword ptr [rbx + SV_phase], SVP_FINISH
.Lsvw_phase:
    mov rax, [rbx + SV_phase]
    cmp rax, SVP_IDLE
    je .Lsvw_idle
    cmp rax, SVP_BATCH
    je .Lsvw_batch
    cmp rax, SVP_RELEASE
    je .Lsvw_release
    cmp rax, SVP_REQUEST
    je .Lsvw_request
    cmp rax, SVP_ENCODE
    je .Lsvw_encode
    cmp rax, SVP_LAUNCH
    je .Lsvw_launch
    cmp rax, SVP_ACTIVE
    je .Lsvw_active
    cmp rax, SVP_FINISH
    je .Lsvw_finish
    cmp rax, SVP_FAILED
    je .Lsvw_cleanup
    cmp rax, SVP_RETRY
    je .Lsvw_retry
    jmp .Lsvw_bad
.Lsvw_adoption:
    mov rdi, rbx
    call settings_service_adoption_step
    cmp rax, 1
    je .Lsvw_idle_return
    jmp .Lsvw_return
.Lsvw_idle:
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lsvw_idle_return
    cmp qword ptr [rbx + SV_source], 0
    je .Lsvw_choose_read
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lsvw_idle_return
    mov rax, [rbx + SV_queue]
    cmp qword ptr [rax + EQ_count], 0
    jne .Lsvw_choose_save
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_poll_due]
    jb .Lsvw_idle_return
.Lsvw_choose_read:
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvw_idle_return
    mov qword ptr [rbx + SV_mode], 1
    mov qword ptr [rbx + SV_phase], SVP_REQUEST
    jmp .Lsvw_new_operation
.Lsvw_choose_save:
    mov qword ptr [rbx + SV_mode], 2
    mov qword ptr [rbx + SV_phase], SVP_BATCH
.Lsvw_new_operation:
    mov qword ptr [rbx + SV_retry_count], 0
    mov qword ptr [rbx + SV_retry_pending], 0
    mov rdi, rbx
    call settings_service_operation_tag
    test rax, rax
    js .Lsvw_fail_rax
    jmp .Lsvw_return
.Lsvw_batch:
    mov rdi, [rbx + SV_queue]
    call ext_settings_queue_batch
    test rax, rax
    jz .Lsvw_fail_rdx
    mov [rbx + SV_batch], rax
    mov qword ptr [rbx + SV_batch_phase], SVB_SAVING
    mov qword ptr [rbx + SV_phase], SVP_RELEASE
    jmp .Lsvw_return
.Lsvw_release:
    lea rdi, [rbx + SV_tag]
    mov esi, EW_RELEASE
    xor edx, edx
    mov ecx, 1
    call ext_settings_frame_new
    test rax, rax
    jz .Lsvw_fail_rdx
    mov [rbx + SV_release_frame], rax
    mov rdi, rax
    call ext_settings_frame_seal
    test rax, rax
    js .Lsvw_fail_rax
    mov qword ptr [rbx + SV_phase], SVP_REQUEST
    jmp .Lsvw_return
.Lsvw_request:
    lea rax, [rbx + SV_tag]
    mov [rsp + SRQ_tag], rax
    mov rax, [rbx + SV_path]
    mov [rsp + SRQ_path], rax
    mov rax, [rbx + SV_length]
    mov [rsp + SRQ_length], rax
    mov rax, [rbx + SV_batch]
    mov [rsp + SRQ_batch], rax
    mov rax, [rbx + SV_mode]
    mov [rsp + SRQ_mode], rax
    mov rdi, rsp
    lea rsi, [rbx + SV_cursor]
    call ext_settings_request_begin
    test rax, rax
    jz .Lsvw_fail_rdx
    mov [rbx + SV_frame], rax
    mov qword ptr [rbx + SV_phase], SVP_ENCODE
    jmp .Lsvw_return
.Lsvw_encode:
    mov rdi, [rbx + SV_frame]
    mov rsi, [rbx + SV_batch]
    lea rdx, [rbx + SV_cursor]
    mov ecx, 65536
    call ext_settings_request_step
    test rax, rax
    js .Lsvw_fail_rax
    cmp rax, 1
    jne .Lsvw_return
    mov qword ptr [rbx + SV_phase], SVP_LAUNCH
    jmp .Lsvw_return
.Lsvw_launch:
    mov rdi, [rbx + SV_frame]
    call ext_settings_job_begin
    test rax, rax
    jz .Lsvw_fail_rdx
    mov [rbx + SV_job], rax
    mov qword ptr [rbx + SV_frame], 0
    mov qword ptr [rbx + SV_cursor + ESQ_magic], 0
    mov qword ptr [rbx + SV_cursor + ESQ_frame], 0
    mov qword ptr [rbx + SV_cursor + ESQ_batch], 0
    mov qword ptr [rbx + SV_phase], SVP_ACTIVE
    jmp .Lsvw_return
.Lsvw_active:
    mov rdi, rbx
    call settings_service_active_step
    jmp .Lsvw_return
.Lsvw_finish:
    mov rdi, rbx
    call settings_service_finish_step
    jmp .Lsvw_return
.Lsvw_cleanup:
    mov rdi, rbx
    call settings_service_failure_cleanup
    jmp .Lsvw_return
.Lsvw_retry:
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lsvw_idle_return
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvw_retry_abort
    cmp qword ptr [rbx + SV_mode], 1
    jne 8f
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvw_retry_abort
8:  mov rdi, rbx
    call settings_service_operation_tag
    test rax, rax
    js .Lsvw_fail_rax
    mov qword ptr [rbx + SV_retry_pending], 0
    mov eax, SVP_REQUEST
    cmp qword ptr [rbx + SV_mode], 1
    je 1f
    mov eax, SVP_RELEASE
1:  mov [rbx + SV_phase], rax
    jmp .Lsvw_return
.Lsvw_retry_abort:
    mov qword ptr [rbx + SV_retry_pending], 0
    mov qword ptr [rbx + SV_phase], SVP_FAILED
    jmp .Lsvw_return
.Lsvw_fail_rdx:
    mov rax, rdx
.Lsvw_fail_rax:
    mov rdi, rbx
    mov rsi, rax
    call settings_service_operation_fail
.Lsvw_return:
    xor eax, eax
    mov rdx, [rbx + SV_primary]
    EPILOGUE
.Lsvw_idle_return:
    mov eax, 1
    mov rdx, [rbx + SV_primary]
    EPILOGUE
.Lsvw_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lsvw_bad_leaf:
    mov rax, -22
    xor edx, edx
    ret
