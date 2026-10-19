# Suggested timer cadence only, never a hidden wait or native process poll.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
FN ext_settings_service_timeout
    test rdi, rdi
    jz .Lsvt_none_leaf
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, -1
    cmp qword ptr [rbx + SV_replaced_source], 0
    je 9f
    cmp qword ptr [rbx + SV_job], 0
    jne 9f
    cmp qword ptr [rbx + SV_retry_due], 0
    jne .Lsvt_due
    jmp .Lsvt_one
9:  cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne 8f
    cmp qword ptr [rbx + SV_job], 0
    jne 8f
    mov rdi, rbx
    mov rsi, r12
    call settings_service_adoption_timeout
    cmp rax, -1
    je 8f
    mov r13, rax
    jmp .Lsvt_return
8:  mov rdi, [rbx + SV_job]
    test rdi, rdi
    jz .Lsvt_local
    call ext_settings_job_timeout
    mov r13, rax
.Lsvt_local:
    mov rax, [rbx + SV_phase]
    cmp rax, SVP_IDLE
    je .Lsvt_idle
    cmp rax, SVP_RETRY
    je .Lsvt_due
    cmp rax, SVP_FAILED
    je .Lsvt_cleanup
    cmp rax, SVP_FINISH
    je .Lsvt_cleanup
    cmp rax, SVP_ACTIVE
    jne .Lsvt_one
    # A terminal ECJ has no IO cadence. Local retained cleanup uses actual due.
    cmp r13, -1
    jne .Lsvt_return
.Lsvt_cleanup:
    cmp qword ptr [rbx + SV_retry_due], 0
    jne .Lsvt_due
    jmp .Lsvt_one
.Lsvt_idle:
    cmp qword ptr [rbx + SV_state], SV_SHUTTING
    jae .Lsvt_none
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lsvt_none
    cmp qword ptr [rbx + SV_source], 0
    je .Lsvt_initial
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lsvt_none
    mov rax, [rbx + SV_queue]
    cmp qword ptr [rax + EQ_count], 0
    jne .Lsvt_one
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvt_none
    mov rax, [rbx + SV_poll_due]
    jmp .Lsvt_difference
.Lsvt_initial:
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvt_none
    jmp .Lsvt_one
.Lsvt_due:
    mov rax, [rbx + SV_retry_due]
.Lsvt_difference:
    cmp rax, r12
    jbe .Lsvt_one
    sub rax, r12
    mov r13, rax
    jmp .Lsvt_return
.Lsvt_one:
    mov r13d, 1
    jmp .Lsvt_return
.Lsvt_none:
    mov r13, -1
.Lsvt_return:
    mov rax, r13
    EPILOGUE
.Lsvt_none_leaf:
    mov rax, -1
    ret
# Existing coherent model can start during an undiscovered background read.
FN ext_settings_service_can_start
    PROLOGUE
    mov rbx, rdi
    call settings_service_domain
    test rax, rax
    js .Lsvc_start_done
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvc_start_busy
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lsvc_start_again
    cmp qword ptr [rbx + SV_source], 0
    je .Lsvc_start_again
    cmp qword ptr [rbx + SV_source_epoch], 0
    jle .Lsvc_start_again
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvc_start_busy
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACK_WAITING
    je .Lsvc_start_busy
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvc_start_busy
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvc_start_busy
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvc_start_unknown
    mov rax, [rbx + SV_primary]
    test rax, rax
    js .Lsvc_start_done
    mov rax, [rbx + SV_apply_error]
    test rax, rax
    js .Lsvc_start_done
    xor eax, eax
.Lsvc_start_done:
    EPILOGUE
.Lsvc_start_busy:
    mov rax, -16
    EPILOGUE
.Lsvc_start_again:
    mov rax, -11
    EPILOGUE
.Lsvc_start_unknown:
    mov rax, -117
    EPILOGUE
