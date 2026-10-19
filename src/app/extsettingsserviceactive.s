# One native or local receipt category per turn. Never inspect opaque capsule fields.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# Internal first-diagnostic channels. COMMITTED truth never becomes a cleanup errno.
FN settings_service_cleanup_error
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + SV_cleanup], 0
    jne 1f
    mov [rdi + SV_cleanup], rsi
1:  ret
FN settings_service_observation_error
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + SV_observation], 0
    jne 1f
    mov [rdi + SV_observation], rsi
1:  ret
# Internal cleanup backoff. Live native progress is separately scheduled every other turn.
FN settings_service_cleanup_delay
    mov rax, [rdi + SV_retry_delay]
    test rax, rax
    jnz 1f
    mov eax, 8
1:  add rax, rax
    cmp rax, 1000
    jbe 2f
    mov eax, 1000
2:  mov [rdi + SV_retry_delay], rax
    add rax, [rdi + SV_now]
    jns 3f
    mov rax, 0x7fffffffffffffff
3:  mov [rdi + SV_retry_due], rax
    ret
# drop_frame(SVC,fieldOffset)->0 accepted/-errno, preserves slot unless consumed1.
FN settings_service_drop_frame
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lsvd_wait
    mov rdi, [rbx + r12]
    call ext_settings_frame_free
    cmp rcx, 1
    jne .Lsvd_retained
    mov qword ptr [rbx + r12], 0
    mov qword ptr [rbx + SV_retry_due], 0
    mov qword ptr [rbx + SV_retry_delay], 0
    mov rdi, rbx
    mov rsi, rdx
    call settings_service_cleanup_error
    xor eax, eax
    EPILOGUE
.Lsvd_retained:
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call settings_service_cleanup_error
    mov rdi, rbx
    call settings_service_cleanup_delay
    mov rax, r13
    EPILOGUE
.Lsvd_wait:
    mov rax, -11
    EPILOGUE
FN settings_service_active_step
    PROLOGUE 64
    mov rbx, rdi
    mov r12, [rbx + SV_job]
    test r12, r12
    jz .Lsva_finish
    mov rdi, r12
    mov rsi, rsp
    call ext_settings_job_status
    mov rax, [rsp]
    mov [rbx + SV_final_state], rax
    mov rax, [rsp + 8]
    mov [rbx + SV_final_primary], rax
    mov rax, [rsp + 40]
    mov [rbx + SV_final_flags], rax
    mov rax, [rsp + 24]
    mov [rbx + SV_final_observation], rax
    mov rdi, rbx
    mov rsi, [rsp + 16]
    call settings_service_cleanup_error
    mov rdi, rbx
    mov rsi, [rsp + 24]
    call settings_service_observation_error
    test qword ptr [rsp + 40], 1
    jnz .Lsva_take
    cmp qword ptr [rbx + SV_native_turn], 0
    jne .Lsva_native
.Lsva_take:
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lsva_delivery
    mov rdi, r12
    call ext_settings_job_take_frame
    test rax, rax
    jz .Lsva_no_delivery
    mov [rbx + SV_delivery], rax
    cmp qword ptr [rax + EJF_kind], EW_COMMITTED
    jne .Lsva_return
    # Correlated SHA-verified COMMITTED is commit truth before any allocation.
    mov qword ptr [rbx + SV_commit], 1
    mov qword ptr [rbx + SV_batch_phase], SVB_ACK_WAITING
    jmp .Lsva_return
.Lsva_delivery:
    mov r13, [rbx + SV_delivery]
    cmp qword ptr [r13 + EJF_kind], EW_COMMITTED
    je .Lsva_committed
    cmp qword ptr [r13 + EJF_kind], EW_SNAPSHOT
    je .Lsva_snapshot
    cmp qword ptr [r13 + EJF_kind], EW_PREPARED
    je .Lsva_prepared
    mov rdi, r12
    call ext_settings_job_cancel
    mov qword ptr [rbx + SV_abort], 2
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsva_drop_delivery
    mov qword ptr [rbx + SV_primary], -71
    jmp .Lsva_drop_delivery
.Lsva_snapshot:
    cmp qword ptr [rbx + SV_mode], 1
    jne .Lsva_drop_delivery
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsva_drop_delivery
    cmp qword ptr [rbx + SV_conversion_tried], 0
    jne .Lsva_terminal_or_native
    mov qword ptr [rbx + SV_conversion_tried], 1
    mov rdi, r13
    mov rsi, [rbx + SV_context]
    call ext_settings_snapshot_begin
    test rax, rax
    jz .Lsva_read_convert_fail
    mov [rbx + SV_provisional], rax
    mov qword ptr [rbx + SV_delivery], 0
    jmp .Lsva_local_done
.Lsva_read_convert_fail:
    cmp qword ptr [rbx + SV_primary], 0
    jne 1f
    mov [rbx + SV_primary], rdx
1:  mov qword ptr [rbx + SV_abort], 1
    jmp .Lsva_local_done
.Lsva_prepared:
    cmp qword ptr [rbx + SV_control_sent], 0
    jne .Lsva_drop_delivery
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsva_drop_delivery
    cmp qword ptr [rbx + SV_mode], 2
    jne .Lsva_protocol
    cmp qword ptr [rbx + SV_batch_phase], SVB_SAVING
    jne .Lsva_protocol
    cmp qword ptr [rbx + SV_batch], 0
    je .Lsva_protocol
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lsva_protocol
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsva_protocol
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsva_protocol
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsva_protocol
    cmp qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    ja .Lsva_protocol
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsva_commit_command
    lea rdi, [rbx + SV_tag]
    mov esi, EW_COMMIT
    xor edx, edx
    mov ecx, 1
    call ext_settings_frame_new
    test rax, rax
    jz .Lsva_protocol_rdx
    mov [rbx + SV_frame], rax
    mov rdi, rax
    call ext_settings_frame_seal
    test rax, rax
    js .Lsva_protocol_rax
    jmp .Lsva_local_done
.Lsva_commit_command:
    mov rdi, r12
    mov rsi, [rbx + SV_frame]
    call ext_settings_job_command
    test rax, rax
    jz 1f
    cmp rax, -11
    je .Lsva_local_done
    jmp .Lsva_protocol_rax
1:  mov qword ptr [rbx + SV_frame], 0
    mov qword ptr [rbx + SV_control_sent], 1
    jmp .Lsva_local_done
.Lsva_committed:
    cmp qword ptr [rbx + SV_release_frame], 0
    je .Lsva_committed_convert
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsva_committed_convert
    test qword ptr [rsp + 40], 1
    jnz .Lsva_committed_convert
    mov rdi, r12
    mov rsi, [rbx + SV_release_frame]
    call ext_settings_job_command
    test rax, rax
    jz 1f
    cmp rax, -11
    je .Lsva_local_done
    mov rdi, rbx
    mov rsi, rax
    call settings_service_observation_error
    mov rdi, r12
    call ext_settings_job_cancel
    mov qword ptr [rbx + SV_abort], 2
    jmp .Lsva_local_done
1:  mov qword ptr [rbx + SV_release_frame], 0
    jmp .Lsva_local_done
.Lsva_committed_convert:
    cmp qword ptr [rbx + SV_conversion_tried], 0
    jne .Lsva_terminal_or_native
    mov qword ptr [rbx + SV_conversion_tried], 1
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_pending_epoch], rax
    jae .Lsva_apply_overflow
    mov rdi, r13
    mov rsi, [rbx + SV_context]
    call ext_settings_snapshot_begin
    test rax, rax
    jz .Lsva_apply_failure
    mov [rbx + SV_pending], rax
    inc qword ptr [rbx + SV_pending_epoch]
    mov qword ptr [rbx + SV_delivery], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_apply_rebuild], 0
    mov qword ptr [rbx + SV_apply_grant], 1
    jmp .Lsva_local_done
.Lsva_apply_overflow:
    mov rdx, -75
.Lsva_apply_failure:
    mov [rbx + SV_apply_error], rdx
    jmp .Lsva_local_done
.Lsva_protocol:
    mov rax, -71
    jmp .Lsva_protocol_rax
.Lsva_protocol_rdx:
    mov rax, rdx
.Lsva_protocol_rax:
    cmp qword ptr [rbx + SV_primary], 0
    jne 1f
    mov [rbx + SV_primary], rax
1:  mov qword ptr [rbx + SV_abort], 1
    jmp .Lsva_local_done
.Lsva_drop_delivery:
    mov rdi, rbx
    mov esi, SV_delivery
    call settings_service_drop_frame
.Lsva_local_done:
    mov qword ptr [rbx + SV_native_turn], 1
    jmp .Lsva_return
.Lsva_no_delivery:
    # The mailbox was drained before freeing the ECJ, even at terminal proof.
.Lsva_terminal_or_native:
    test qword ptr [rsp + 40], 1
    jz .Lsva_native
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lsva_return
    mov rdi, r12
    call ext_settings_job_free
    cmp rcx, 1
    jne .Lsva_job_retained
    mov qword ptr [rbx + SV_job], 0
    mov qword ptr [rbx + SV_retry_due], 0
    mov qword ptr [rbx + SV_retry_delay], 0
    mov rdi, rbx
    mov rsi, rdx
    call settings_service_cleanup_error
.Lsva_finish:
    mov qword ptr [rbx + SV_phase], SVP_FINISH
    jmp .Lsva_return
.Lsva_job_retained:
    mov rdi, rbx
    mov rsi, rax
    call settings_service_cleanup_error
    mov rdi, rbx
    call settings_service_cleanup_delay
    jmp .Lsva_return
.Lsva_native:
    mov rdi, r12
    mov rsi, [rbx + SV_now]
    mov edx, 65536
    mov ecx, 16
    call ext_settings_job_step
    mov qword ptr [rbx + SV_native_turn], 0
.Lsva_return:
    xor eax, eax
    EPILOGUE
