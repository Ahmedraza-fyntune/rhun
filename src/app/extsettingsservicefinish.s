# Terminal proof, source authority and exact-once failed-batch retirement.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# Retained correlated COMMITTED delivery can be converted after native collection.
# Explicit retry grants one attempt; this function never resets conversion_tried itself.
FN settings_service_finish_step
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvf_done
    cmp qword ptr [rbx + SV_commit], 0
    jne .Lsvf_committed
    cmp qword ptr [rbx + SV_final_state], ECJS_UNCERTAIN
    je .Lsvf_uncertain
    cmp qword ptr [rbx + SV_mode], 1
    jne .Lsvf_failed
    cmp qword ptr [rbx + SV_final_state], ECJS_READ_OK
    jne .Lsvf_failed
    test qword ptr [rbx + SV_final_flags], 1
    jz .Lsvf_failed
    test qword ptr [rbx + SV_final_flags], 2
    jz .Lsvf_failed
    cmp qword ptr [rbx + SV_final_primary], 0
    jne .Lsvf_failed
    cmp qword ptr [rbx + SV_final_observation], 0
    jne .Lsvf_failed
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvf_failed
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvf_stale
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsvf_stale
    mov r12, [rbx + SV_provisional]
    test r12, r12
    jz .Lsvf_protocol
    mov r13, [rbx + SV_source]
    test r13, r13
    jz .Lsvf_first_source
    mov rax, [r12 + ESB_exists]
    cmp [r13 + ESB_exists], rax
    jne .Lsvf_changed
    mov rax, [r12 + ESB_length]
    cmp [r13 + ESB_length], rax
    jne .Lsvf_changed
    lea rdi, [r12 + ESB_digest]
    lea rsi, [r13 + ESB_digest]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lsvf_changed
    # Unchanged bytes have no new source/model authority or epoch.
    mov rdi, r12
    call ext_settings_snapshot_release
    test rax, rax
    js .Lsvf_done
    mov qword ptr [rbx + SV_provisional], 0
    jmp .Lsvf_idle
.Lsvf_changed:
    cmp qword ptr [rbx + SV_installed], 0
    je .Lsvf_initial_replacement
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_pending_epoch], rax
    jae .Lsvf_overflow
    # Final pure domain check after equality/preflight, immediately before stores.
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsvf_stale
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvf_stale
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvf_stale
    mov [rbx + SV_pending], r12
    mov qword ptr [rbx + SV_provisional], 0
    inc qword ptr [rbx + SV_pending_epoch]
    mov qword ptr [rbx + SV_apply_rebuild], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_apply_grant], 1
    jmp .Lsvf_idle
.Lsvf_initial_replacement:
    cmp qword ptr [rip + esv_live_model], 0
    jne .Lsvf_protocol
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne .Lsvf_protocol
    cmp qword ptr [rbx + SV_source_epoch], 0
    jle .Lsvf_protocol
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_source_epoch], rax
    jae .Lsvf_overflow
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsvf_stale
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvf_stale
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvf_stale
    mov [rbx + SV_replaced_source], r13
    mov [rbx + SV_source], r12
    mov qword ptr [rbx + SV_provisional], 0
    inc qword ptr [rbx + SV_source_epoch]
    jmp .Lsvf_idle
.Lsvf_first_source:
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsvf_stale
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvf_stale
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvf_stale
    mov [rbx + SV_source], r12
    mov qword ptr [rbx + SV_provisional], 0
    mov qword ptr [rbx + SV_source_epoch], 1
    jmp .Lsvf_idle
.Lsvf_committed:
    # These auxiliary controls are now independent of actual child lifetime.
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsvf_drop_frame
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lsvf_drop_release
    cmp qword ptr [rbx + SV_delivery], 0
    je .Lsvf_commit_has_source
    cmp qword ptr [rbx + SV_conversion_tried], 0
    jne .Lsvf_idle
    mov qword ptr [rbx + SV_conversion_tried], 1
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_pending_epoch], rax
    jae .Lsvf_commit_overflow
    mov rdi, [rbx + SV_delivery]
    mov rsi, [rbx + SV_context]
    call ext_settings_snapshot_begin
    test rax, rax
    jz .Lsvf_commit_error
    mov [rbx + SV_pending], rax
    mov qword ptr [rbx + SV_delivery], 0
    inc qword ptr [rbx + SV_pending_epoch]
    mov qword ptr [rbx + SV_apply_rebuild], 0
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_apply_grant], 1
    mov qword ptr [rbx + SV_apply_error], 0
    jmp .Lsvf_idle
.Lsvf_commit_overflow:
    mov rdx, -75
.Lsvf_commit_error:
    mov [rbx + SV_apply_error], rdx
    jmp .Lsvf_idle
.Lsvf_commit_has_source:
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvf_idle
    mov qword ptr [rbx + SV_apply_error], -71
    jmp .Lsvf_idle
.Lsvf_uncertain:
    mov qword ptr [rbx + SV_uncertain], 1
    mov qword ptr [rbx + SV_phase], SVP_FAILED
    jmp .Lsvf_done
.Lsvf_stale:
    mov rax, -116
    jmp .Lsvf_set_primary
.Lsvf_overflow:
    mov rax, -75
    jmp .Lsvf_set_primary
.Lsvf_protocol:
    mov rax, -71
    jmp .Lsvf_set_primary
.Lsvf_failed:
    # Only definite busy before possible COMMIT can schedule automatic retry.
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lsvf_error_value
    cmp qword ptr [rbx + SV_final_state], ECJS_PRECOMMIT_FAILED
    jne .Lsvf_error_value
    test qword ptr [rbx + SV_final_flags], 32
    jnz .Lsvf_error_value
    mov rax, [rbx + SV_final_primary]
    cmp rax, -11
    je 1f
    cmp rax, -16
    jne .Lsvf_error_value
1:  cmp qword ptr [rbx + SV_retry_count], 3
    jae .Lsvf_error_value
    mov rdi, rbx
    call settings_service_domain
    test rax, rax
    js .Lsvf_stale
    cmp qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    ja .Lsvf_error_value
    cmp qword ptr [rbx + SV_mode], 1
    jne 8f
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvf_error_value
8:  inc qword ptr [rbx + SV_retry_count]
    mov qword ptr [rbx + SV_retry_pending], 1
    mov qword ptr [rbx + SV_phase], SVP_FAILED
    jmp .Lsvf_done
.Lsvf_error_value:
    mov rax, [rbx + SV_final_primary]
    test rax, rax
    js .Lsvf_set_primary
    mov rax, [rbx + SV_final_observation]
    test rax, rax
    js .Lsvf_set_primary
    mov rax, -71
.Lsvf_set_primary:
    cmp qword ptr [rbx + SV_primary], 0
    jne 1f
    mov [rbx + SV_primary], rax
1:  mov qword ptr [rbx + SV_retry_pending], 0
    mov qword ptr [rbx + SV_phase], SVP_FAILED
    jmp .Lsvf_done
.Lsvf_drop_frame:
    mov esi, SV_frame
    jmp .Lsvf_drop
.Lsvf_drop_release:
    mov esi, SV_release_frame
.Lsvf_drop:
    mov rdi, rbx
    call settings_service_drop_frame
    jmp .Lsvf_done
.Lsvf_idle:
    mov rax, [rbx + SV_now]
    add rax, 1000
    jns 1f
    mov rax, 0x7fffffffffffffff
1:  mov [rbx + SV_poll_due], rax
    mov qword ptr [rbx + SV_phase], SVP_IDLE
.Lsvf_done:
    xor eax, eax
    EPILOGUE
# One checked cleanup action, never drop a batch's refs twice on consumed0.
FN settings_service_failure_cleanup
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsvfc_frame
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lsvfc_release
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lsvfc_delivery
    mov rdi, [rbx + SV_provisional]
    test rdi, rdi
    jz .Lsvfc_batch
    call ext_settings_snapshot_release
    test rax, rax
    js .Lsvfc_done
    mov qword ptr [rbx + SV_provisional], 0
    jmp .Lsvfc_done
.Lsvfc_batch:
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvfc_idle
    cmp qword ptr [rbx + SV_retry_pending], 0
    jne .Lsvfc_retry
    mov rdi, [rbx + SV_batch]
    test rdi, rdi
    jz .Lsvfc_idle
    mov rax, [rbx + SV_now]
    cmp rax, [rbx + SV_retry_due]
    jb .Lsvfc_done
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    je .Lsvfc_batch_self
    mov qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    call ext_settings_batch_free
    jmp .Lsvfc_batch_result
.Lsvfc_batch_self:
    call ext_settings_memory_free
.Lsvfc_batch_result:
    cmp rcx, 1
    jne .Lsvfc_batch_retained
    mov qword ptr [rbx + SV_batch], 0
    mov qword ptr [rbx + SV_batch_phase], SVB_NONE
    mov qword ptr [rbx + SV_retry_due], 0
    mov qword ptr [rbx + SV_retry_delay], 0
    mov rdi, rbx
    mov rsi, rdx
    call settings_service_cleanup_error
    jmp .Lsvfc_done
.Lsvfc_batch_retained:
    mov rdi, rbx
    mov rsi, rax
    call settings_service_cleanup_error
    mov rdi, rbx
    call settings_service_cleanup_delay
    jmp .Lsvfc_done
.Lsvfc_frame:
    mov esi, SV_frame
    # Invalidate all cursor borrowed authority before disposal may consume frame.
    mov qword ptr [rbx + SV_cursor + 56], 0
    mov qword ptr [rbx + SV_cursor], 0
    mov qword ptr [rbx + SV_cursor + 8], 0
    jmp .Lsvfc_drop
.Lsvfc_release:
    mov esi, SV_release_frame
    jmp .Lsvfc_drop
.Lsvfc_delivery:
    mov esi, SV_delivery
.Lsvfc_drop:
    mov rdi, rbx
    call settings_service_drop_frame
    jmp .Lsvfc_done
.Lsvfc_retry:
    mov eax, 100
    cmp qword ptr [rbx + SV_retry_count], 1
    je 1f
    mov eax, 250
    cmp qword ptr [rbx + SV_retry_count], 2
    je 1f
    mov eax, 1000
1:  add rax, [rbx + SV_now]
    jns 2f
    mov rax, 0x7fffffffffffffff
2:  mov [rbx + SV_retry_due], rax
    mov qword ptr [rbx + SV_phase], SVP_RETRY
    jmp .Lsvfc_done
.Lsvfc_idle:
    mov qword ptr [rbx + SV_phase], SVP_IDLE
.Lsvfc_done:
    xor eax, eax
    EPILOGUE
