# Public service scheduler failure/retry transitions, actual helper receipt retained.
.bss
.p2align 3
.globl svat_debt_fault, svat_free_calls
svat_debt_fault: .quad 0
svat_free_calls: .quad 0
svat_charge: .quad 0
svat_pending: .quad 0
svat_qepoch: .quad 0
svat_model: .quad 0
.text
# Fixture native cadence, single public service step per iteration.
svat_step:
    PROLOGUE
    call time_ms
    mov rsi, rax
    mov rdi, [rip + svw_svc]
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    EPILOGUE
svat_ready:
    PROLOGUE
    mov rbx, [rip + svw_svc]
1:  call svat_step
    mov rax, [rbx + SV_sap]
    test rax, rax
    jz 2f
    cmp qword ptr [rax + AP_state], APS_READY
    je 3f
2:  call svw_wait
    jmp 1b
3:  EPILOGUE
svat_failures:
    PROLOGUE
    mov rbx, [rip + svw_svc]
    mov rax, [rbx + SV_pending]
    mov [rip + svat_pending], rax
    mov r15, [rbx + SV_queue]
    mov rax, [r15 + EQ_epoch]
    mov [rip + svat_qepoch], rax
    mov qword ptr [rip + svw_stage], 248
    # Known COMMITTED remains locally admissible after historical RELEASE cancellation.
    mov qword ptr [rbx + SV_abort], 2
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, 1
    jne svw_fail
    # A late committed grant in an unusable domain cannot cause a constructor spin.
    inc qword ptr [rip + esv_cfg_context]
    mov qword ptr [rbx + SV_primary], -116
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, -1
    jne svw_fail
    dec qword ptr [rip + esv_cfg_context]
    mov qword ptr [rbx + SV_primary], 0
    # ACK epoch overflow is detected after a real READY plan, not stranded at export.
    mov qword ptr [rip + svw_stage], 250
    mov rax, 0x7fffffffffffffff
    mov [r15 + EQ_epoch], rax
    call svat_ready
    mov rdi, rbx
    call ext_settings_service_adoption
    test rax, rax
    jnz svw_fail
    cmp rdx, -75
    jne svw_fail
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, 1
    jne svw_fail
    call svat_step
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp qword ptr [rip + settings_adoption_scheduler], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_error], -75
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_grant], 0
    jne svw_fail
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, -1
    jne svw_fail
    call svat_step
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    mov rax, [rip + svat_qepoch]
    mov [r15 + EQ_epoch], rax
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
    # Export/cancel cannot auto-rebuild or silently authorize another native save.
    mov qword ptr [rip + svw_stage], 249
    call svat_ready
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
    mov rdi, r12
    call ext_settings_adoption_cancel
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_cancel
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rbx + SV_apply_error], -125
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_grant], 0
    jne svw_fail
    call svat_step
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, -1
    jne svw_fail
    mov rdi, r12
    call ext_settings_adoption_check
    cmp rax, -116
    jne svw_fail
    # Retained canceled model is readable history until this owned reference drops.
    mov rax, [rip + svat_pending]
    cmp [r13 + ELM_source], rax
    jne svw_fail
    mov rdi, r13
    call ext_settings_model_release
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_release
    test rax, rax
    jnz svw_fail
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
    # Three actual accepted newer edits stale three builders, never reset the count.
    mov qword ptr [rip + svw_stage], 252
    xor r14d, r14d
1:  call svat_step
    cmp qword ptr [rbx + SV_sap], 0
    je svw_fail
    lea rdi, [rip + svw_no]
    mov esi, 2
    call svw_put
    call svat_step
    inc r14
    cmp [rbx + SV_apply_rebuild], r14
    jne svw_fail
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp r14, 3
    jb 1b
    cmp qword ptr [rbx + SV_apply_error], -116
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_grant], 0
    jne svw_fail
    lea rdi, [rip + svw_no]
    mov esi, 2
    call svw_put
    call svat_step
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_rebuild], 3
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_error], -116
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    mov rax, [rip + svat_pending]
    cmp [rbx + SV_pending], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 1
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rbx + SV_apply_rebuild], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_job_serial], 2
    jne svw_fail
    EPILOGUE
# The fixture wrapper refuses only batch self disposition, after real ref/account detach.
.globl svat_memory_free
svat_memory_free:
    cmp qword ptr [rip + svat_debt_fault], 0
    je .Lsvat_free_real
    mov rax, [rip + svw_svc]
    cmp [rax + SV_batch], rdi
    jne .Lsvat_free_real
    inc qword ptr [rip + svat_free_calls]
    cmp qword ptr [rip + svat_debt_fault], 1
    jne .Lsvat_free_real
    mov qword ptr [rip + svat_debt_fault], 2
    mov rax, -5
    mov rdx, -5
    xor ecx, ecx
    ret
.Lsvat_free_real:
    jmp svwf_memory_free
svat_after_publish:
    PROLOGUE
    mov rbx, [rip + svw_svc]
    mov r15, [rbx + SV_queue]
    mov qword ptr [rip + svw_stage], 251
    mov qword ptr [rip + svat_debt_fault], 1
    call svat_step
    cmp qword ptr [rbx + SV_batch_phase], SVB_SELF_DEBT
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 1
    jne svw_fail
    cmp qword ptr [r15 + EQ_batch], 0
    jne svw_fail
    cmp qword ptr [rip + svat_free_calls], 1
    jne svw_fail
    mov rax, [r15 + EQ_charge]
    mov [rip + svat_charge], rax
    mov rdi, rbx
    mov rsi, [rbx + SV_now]
    call ext_settings_service_step
    cmp qword ptr [rip + svat_free_calls], 1
    jne svw_fail
    mov rdi, rbx
    mov rsi, [rbx + SV_now]
    call ext_settings_service_timeout
    cmp rax, 16
    jne svw_fail
    mov rdx, rax
    xor edi, edi
    xor esi, esi
    SYS SYS_poll
    call svat_step
    mov qword ptr [rip + svw_stage], 253
    cmp qword ptr [rip + svat_free_calls], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_batch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 0
    jne svw_fail
    mov rax, [rip + svat_charge]
    cmp [r15 + EQ_charge], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_cleanup], -5
    jne svw_fail
    cmp qword ptr [r15 + EQ_count], 1
    jne svw_fail
    mov qword ptr [rip + svat_debt_fault], 0
    # The newer retained edit is the next real SAVE, followed by another pure adoption.
    mov qword ptr [rip + svw_stage], 254
    mov rax, [rip + esv_model_epoch]
    mov [rip + svat_model], rax
1:  call svat_step
    mov rax, [rbx + SV_sap]
    test rax, rax
    jz 2f
    cmp qword ptr [rax + AP_state], APS_READY
    je 3f
2:  call svw_wait
    jmp 1b
3:  cmp qword ptr [rip + svwf_native_starts], 3
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_adoption
    test rax, rax
    jz svw_fail
    mov r12, rax
    mov rdi, rax
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
    cmp qword ptr [rbx + SV_source_epoch], 3
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 2
    jne svw_fail
    cmp qword ptr [r15 + EQ_count], 0
    jne svw_fail
    mov rax, [rip + svat_model]
    inc rax
    cmp [rip + esv_model_epoch], rax
    jne svw_fail
    cmp [rip + esv_live_model], r13
    jne svw_fail
    mov rdi, r13
    call ext_settings_model_release
    mov rdi, r12
    call ext_settings_adoption_release
    mov r14d, 2048
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
    call svat_step
    cmp qword ptr [rbx + SV_batch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_cleanup], -5
    jne svw_fail
    EPILOGUE