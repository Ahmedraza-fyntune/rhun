# Faults apply only in the parent fixture. Child helper starts with zero BSS mode.
.globl svw_mode, svw_svc, svwf_alloc_fail, svwf_conversion_attempts
.globl svwf_native_starts, svwf_native_capture, svwf_native_fail
.bss
.p2align 3
svwf_alloc_fail: .quad 0
svwf_conversion_attempts: .quad 0
svwf_native_starts: .quad 0
svwf_native_capture: .quad 0
svwf_native_fail: .quad 0
svwf_invalidated: .quad 0
svwf_local_retry: .quad 0
svwf_backoff_seen: .quad 0
svwf_frame_fail: .quad 0
svwf_command_fail: .quad 0
svwf_finish_seen: .quad 0
svwf_child_die: .quad 0
svwf_guard: .quad 0
svwf_close_retry: .quad 0
.text
# Actual native owner is captured as opaque pointer only, never read by fixture.
FN ext_settings_native_start
    PROLOGUE
    call svwf_native_start_real
    mov [rip + svwf_native_capture], rax
    test rax, rax
    jz 1f
    inc qword ptr [rip + svwf_native_starts]
1:  EPILOGUE
# Refuse the exact fallible allocation without touching charge/allocator state.
FN svwf_memory_try
    mov rax, [rip + svw_svc]
    test rax, rax
    jz .Lsvwf_alloc_real
    cmp rdi, 128
    jne .Lsvwf_alloc_real
    cmp qword ptr [rip + svw_mode], 3
    je .Lsvwf_release_fault
    cmp qword ptr [rip + svw_mode], 4
    je .Lsvwf_commit_fault
    cmp qword ptr [rip + svw_mode], 5
    jne .Lsvwf_alloc_real
    cmp qword ptr [rax + SV_commit], 1
    jne .Lsvwf_alloc_real
    mov rcx, [rax + SV_delivery]
    test rcx, rcx
    jz .Lsvwf_alloc_real
    cmp qword ptr [rcx + EJF_kind], EW_COMMITTED
    jne .Lsvwf_alloc_real
    inc qword ptr [rip + svwf_conversion_attempts]
    jmp .Lsvwf_alloc_once
.Lsvwf_release_fault:
    cmp qword ptr [rax + SV_phase], SVP_RELEASE
    jne .Lsvwf_alloc_real
    jmp .Lsvwf_alloc_once
.Lsvwf_commit_fault:
    cmp qword ptr [rax + SV_phase], SVP_ACTIVE
    jne .Lsvwf_alloc_real
    mov rcx, [rax + SV_delivery]
    test rcx, rcx
    jz .Lsvwf_alloc_real
    cmp qword ptr [rcx + EJF_kind], EW_PREPARED
    jne .Lsvwf_alloc_real
.Lsvwf_alloc_once:
    cmp qword ptr [rip + svwf_alloc_fail], 0
    jne .Lsvwf_alloc_real
    mov qword ptr [rip + svwf_alloc_fail], 1
    xor eax, eax
    mov rdx, -12
    ret
.Lsvwf_alloc_real:
    jmp svwf_memory_try_real
# Only the captured large native capsule's actual OS unmap is failed once.
FN svwf_native_unmap
    cmp qword ptr [rip + svwf_native_fail], 0
    jne .Lsvwf_unmap_real
    mov r11, [rip + svwf_native_capture]
    test r11, r11
    jz .Lsvwf_unmap_real
    sub r11, 16
.ifdef WINDOWS
    cmp rcx, r11
.else
    cmp rdi, r11
.endif
    jne .Lsvwf_unmap_real
    cmp qword ptr [rip + svw_mode], 6
    je .Lsvwf_unmap_fail
    cmp qword ptr [rip + svw_mode], 7
    jne .Lsvwf_unmap_real
    mov r11, [rip + svw_svc]
    cmp qword ptr [r11 + SV_commit], 1
    jne .Lsvwf_unmap_real
.Lsvwf_unmap_fail:
    mov qword ptr [rip + svwf_native_fail], 1
.ifdef WINDOWS
    mov ecx, 1
.else
    mov edi, 1
.endif
.Lsvwf_unmap_real:
.ifdef WINDOWS
    jmp [rip + __imp_VirtualFree]
.else
    SYS SYS_munmap
    ret
.endif
# Return1 once actual stale READ cleanup is settled, otherwise0.
svwf_read_observe:
    cmp qword ptr [rip + svw_mode], 6
    jne .Lsvwf_read_not_done
    mov rax, [rip + svw_svc]
    cmp qword ptr [rax + SV_source], 0
    jne .Lsvwf_stale_published
    cmp qword ptr [rip + svwf_native_fail], 1
    jne .Lsvwf_read_not_done
    cmp qword ptr [rip + svwf_invalidated], 0
    jne 1f
    inc qword ptr [rip + esv_cfg_context]
    mov qword ptr [rip + svwf_invalidated], 1
    jmp .Lsvwf_read_not_done
1:  cmp qword ptr [rip + svwf_invalidated], 1
    jne 2f
    cmp qword ptr [rax + SV_abort], 0
    je .Lsvwf_read_not_done
    dec qword ptr [rip + esv_cfg_context]
    mov qword ptr [rip + svwf_invalidated], 2
2:  cmp qword ptr [rax + SV_job], 0
    jne .Lsvwf_read_not_done
    cmp qword ptr [rax + SV_phase], SVP_IDLE
    jne .Lsvwf_read_not_done
    cmp qword ptr [rax + SV_provisional], 0
    jne .Lsvwf_stale_published
    cmp qword ptr [rax + SV_pending], 0
    jne .Lsvwf_stale_published
    cmp qword ptr [rax + SV_source_epoch], 0
    jne .Lsvwf_stale_published
    cmp qword ptr [rax + SV_pending_epoch], 0
    jne .Lsvwf_stale_published
    cmp qword ptr [rax + SV_primary], -116
    jne svw_fail
    cmp qword ptr [rip + svwf_invalidated], 2
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 1
    jne svw_fail
    mov eax, 1
    ret
.Lsvwf_stale_published:
    mov qword ptr [rip + svw_stage], 222
    jmp svw_fail
.Lsvwf_read_not_done:
    xor eax, eax
    ret
# Real sticky-error behavior and explicit local retry, not a native resend.
svwf_save_observe:
    PROLOGUE
    mov rbx, [rip + svw_svc]
    cmp qword ptr [rip + svw_mode], 14
    je .Lsvwf_save_close_retry
    cmp qword ptr [rip + svw_mode], 9
    je .Lsvwf_uncertain
    cmp qword ptr [rip + svw_mode], 8
    je .Lsvwf_finish_backoff
    cmp qword ptr [rip + svw_mode], 7
    je .Lsvwf_backoff
    cmp qword ptr [rip + svw_mode], 5
    je .Lsvwf_apply
    cmp qword ptr [rip + svw_mode], 3
    je .Lsvwf_definite
    cmp qword ptr [rip + svw_mode], 4
    jne .Lsvwf_save_no
.Lsvwf_definite:
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_primary], -12
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_batch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_frame], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_release_frame], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_delivery], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_alloc_fail], 1
    jne svw_fail
    mov eax, 1
    cmp qword ptr [rip + svw_mode], 3
    je 1f
    mov eax, 2
1:  cmp [rip + svwf_native_starts], rax
    jne svw_fail
    call svwf_idle_no_jobs
    mov eax, 1
    EPILOGUE
.Lsvwf_apply:
    cmp qword ptr [rip + svwf_local_retry], 0
    jne 1f
    cmp qword ptr [rip + svwf_conversion_attempts], 1
    jbe 1f
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvwf_save_no
    mov qword ptr [rip + svw_stage], 223
    jmp svw_fail
1:  cmp qword ptr [rbx + SV_job], 0
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_apply_error], -12
    jne .Lsvwf_save_no
    cmp qword ptr [rip + svwf_local_retry], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 1
    jne svw_fail
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACK_WAITING
    jne svw_fail
    cmp qword ptr [rbx + SV_delivery], 0
    je svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_conversion_attempts], 1
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    call svwf_idle_no_jobs
    cmp qword ptr [rip + svwf_conversion_attempts], 1
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
    mov qword ptr [rip + svwf_local_retry], 1
    jmp .Lsvwf_save_no
.Lsvwf_save_close_retry:
    cmp qword ptr [rbx + SV_phase], SVP_RETRY
    jne .Lsvwf_save_no
    cmp qword ptr [rip + svwf_close_retry], 0
    jne svw_fail
    mov qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    call svwf_busy_end
    mov rdi, rbx
    mov rsi, [rbx + SV_retry_due]
    call ext_settings_service_step
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_RELEASE
    jne svw_fail
    cmp qword ptr [rbx + SV_job_serial], 3
    jne svw_fail
    mov qword ptr [rip + svwf_close_retry], 1
    jmp .Lsvwf_save_no
.Lsvwf_uncertain:
    cmp qword ptr [rbx + SV_uncertain], 1
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_batch], 0
    je svw_fail
    cmp qword ptr [rbx + SV_batch_phase], SVB_SAVING
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_commit], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_refresh
    cmp rax, -117
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_retry_save
    cmp rax, -117
    jne svw_fail
    call svwf_idle_no_jobs
    mov eax, 1
    EPILOGUE
.Lsvwf_finish_backoff:
    cmp qword ptr [rip + svwf_frame_fail], 1
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_release_frame], 0
    je .Lsvwf_save_no
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_FINISH
    jne svw_fail
    mov rdi, rbx
    mov rsi, [rbx + SV_now]
    call ext_settings_service_timeout
    cmp rax, 16
    je 1f
    mov qword ptr [rip + svw_stage], 221
    jmp svw_fail
1:  inc qword ptr [rip + svwf_finish_seen]
    jmp .Lsvwf_save_no
.Lsvwf_backoff:
    cmp qword ptr [rip + svwf_native_fail], 1
    jne .Lsvwf_save_no
    cmp qword ptr [rbx + SV_job], 0
    je .Lsvwf_save_no
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, 1
    jbe .Lsvwf_save_no
    cmp rax, 1000
    ja svw_fail
    inc qword ptr [rip + svwf_backoff_seen]
.Lsvwf_save_no:
    xor eax, eax
    EPILOGUE
svwf_idle_no_jobs:
    PROLOGUE
    mov r12d, 128
    mov r13, [rip + svwf_native_starts]
1:  call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_timeout
    cmp rax, -1
    jne svw_fail
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_step
    cmp rax, 1
    jne svw_fail
    cmp [rip + svwf_native_starts], r13
    jne svw_fail
    dec r12
    jnz 1b
    EPILOGUE

# Deliberate RELEASE refusal after a proven COMMITTED, then real phase-aware EOF.
FN ext_settings_job_command
    cmp qword ptr [rip + svw_mode], 8
    jne 1f
    cmp qword ptr [rip + svwf_command_fail], 0
    jne 1f
    cmp qword ptr [rsi + EJF_kind], EW_RELEASE
    jne 1f
    mov qword ptr [rip + svwf_command_fail], 1
    mov rax, -32
    ret
1:  jmp svwf_job_command_real
# A retained small control owner exercises consumed0 without pretending an OS unmap.
FN svwf_memory_free
    cmp qword ptr [rip + svw_mode], 8
    jne 1f
    cmp qword ptr [rip + svwf_frame_fail], 0
    jne 1f
    mov rax, [rip + svw_svc]
    test rax, rax
    jz 1f
    cmp qword ptr [rax + SV_phase], SVP_FINISH
    jne 1f
    cmp qword ptr [rax + SV_job], 0
    jne 1f
    cmp qword ptr [rax + SV_commit], 1
    jne 1f
    cmp [rax + SV_release_frame], rdi
    jne 1f
    mov qword ptr [rip + svwf_frame_fail], 1
    mov rax, -16
    xor edx, edx
    xor ecx, ecx
    ret
1:  jmp svwf_memory_free_real

# Actual worker terminates after proven native commit, before its COMMITTED frame.
FN svwf_after_commit
    cmp qword ptr [rip + svwf_child_die], 0
    je 1f
    mov edi, 91
    call sys_exit
1:  ret

.section .rodata
svwf_suffix: .asciz "/extensions.ini"
svwf_foreign: .ascii "; changed outside\n[external/tool]\nsetting.opaque=changed\n"
.equ SVWF_FOREIGNLEN, 57
.bss
svwf_filepath: .zero 4096
.text
# Deliberate external fixture write, followed by actual READ. No service file IO.
svwf_reload:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 224
    mov rbx, [rip + svw_svc]
    call svw_install_empty
    cmp qword ptr [rip + svw_mode], 11
    jne .Lsvwf_reload_begin
    mov r12, [rbx + SV_length]
    cmp r12, 4080
    ja svw_fail
    lea rdi, [rip + svwf_filepath]
    mov rsi, [rbx + SV_path]
    mov rdx, r12
    call memcpy
    lea rdi, [rip + svwf_filepath]
    add rdi, r12
    lea rsi, [rip + svwf_suffix]
    mov edx, 16
    call memcpy
    lea rdi, [rip + svwf_filepath]
    lea rsi, [rip + svwf_foreign]
    mov edx, SVWF_FOREIGNLEN
    call file_write_all
    test rax, rax
    jnz svw_fail
.Lsvwf_reload_begin:
    mov rdi, rbx
    call ext_settings_service_can_start
    test rax, rax
    jnz svw_fail
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
.Lsvwf_reload_loop:
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    cmp qword ptr [rbx + SV_primary], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvwf_reload_pending
    # A private provisional READ alone cannot revoke coherent installed authority.
    mov rdi, rbx
    call ext_settings_service_can_start
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvwf_reload_wait
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_reload_wait
    cmp qword ptr [rip + svw_mode], 10
    jne svw_fail
    mov rdi, rbx
    mov rsi, [rip + svw_held]
    mov edx, 1
    call ext_settings_service_source_check
    test rax, rax
    jnz svw_fail
    jmp .Lsvwf_reload_done
.Lsvwf_reload_pending:
    cmp qword ptr [rip + svw_mode], 11
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_can_start
    cmp rax, -16
    jne svw_fail
    mov rdi, rbx
    mov rsi, [rip + svw_held]
    mov edx, 1
    call ext_settings_service_source_check
    cmp rax, -16
    jne svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvwf_reload_wait
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_reload_wait
    cmp qword ptr [rbx + SV_pending_epoch], 1
    jne svw_fail
    mov rax, [rbx + SV_pending]
    cmp qword ptr [rax + ESB_length], SVWF_FOREIGNLEN
    jne svw_fail
    mov rdi, [rax + ESB_bytes]
    lea rsi, [rip + svwf_foreign]
    mov edx, SVWF_FOREIGNLEN
    call memeq
    test eax, eax
    jz svw_fail
.Lsvwf_reload_done:
    cmp qword ptr [rbx + SV_source_epoch], 1
    jne svw_fail
    mov rax, [rip + svw_held]
    cmp [rbx + SV_source], rax
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    EPILOGUE
.Lsvwf_reload_wait:
    call svw_wait
    jmp .Lsvwf_reload_loop

# Native complete snapshot validation rejects malformed generic INI before a receipt.
svwf_malformed:
    PROLOGUE
    mov rbx, [rip + svw_svc]
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_malformed_pending
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_primary], -22
    jne svw_fail
    cmp qword ptr [rbx + SV_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 0
    jne svw_fail
    mov rdi, rbx
    lea rsi, [rip + svw_epoch]
    call ext_settings_service_source
    test rax, rax
    jnz svw_fail
    cmp rdx, -22
    jne svw_fail
    cmp qword ptr [rip + svw_epoch], 0
    jne svw_fail
    call svwf_idle_no_jobs
    mov eax, 1
    EPILOGUE
.Lsvwf_malformed_pending:
    xor eax, eax
    EPILOGUE

# Fixture-only real config EX lock. Never part of product SVC UI calls.
svwf_busy_begin:
    PROLOGUE
    mov rax, [rip + svw_svc]
    mov rdi, [rax + SV_path]
    mov esi, 1
    mov edx, 1
    call ext_choices_guard_try
    test rax, rax
    jz svw_fail
    test rdx, rdx
    jnz svw_fail
    test r8, r8
    jnz svw_fail
    mov [rip + svwf_guard], rax
    EPILOGUE
svwf_busy_end:
    PROLOGUE
    mov rdi, [rip + svwf_guard]
    test rdi, rdi
    jz svw_fail
    call ext_choices_guard_free
    test rax, rax
    jnz svw_fail
    mov qword ptr [rip + svwf_guard], 0
    EPILOGUE
# READ retry eligibility and delayed expiry are both canceled by PREPARE_CLOSE.
svwf_read_close_retry:
    PROLOGUE
    mov rbx, [rip + svw_svc]
    cmp qword ptr [rip + svwf_close_retry], 0
    jne .Lsvwf_read_close_finish
    cmp qword ptr [rip + svw_mode], 15
    jne .Lsvwf_read_close_expiry
    cmp qword ptr [rbx + SV_phase], SVP_FINISH
    jne .Lsvwf_read_close_wait
    jmp .Lsvwf_read_close_set
.Lsvwf_read_close_expiry:
    cmp qword ptr [rbx + SV_phase], SVP_RETRY
    jne .Lsvwf_read_close_wait
.Lsvwf_read_close_set:
    mov qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    call svwf_busy_end
    mov qword ptr [rip + svwf_close_retry], 1
    mov rdi, rbx
    mov rsi, [rbx + SV_retry_due]
    cmp qword ptr [rip + svw_mode], 13
    je 1f
    mov rsi, [rbx + SV_now]
1:  call ext_settings_service_step
.Lsvwf_read_close_finish:
    cmp qword ptr [rip + svw_mode], 15
    jne 9f
    cmp qword ptr [rbx + SV_phase], SVP_RETRY
    jne 9f
    mov qword ptr [rip + svw_stage], 226
    jmp svw_fail
9:  cmp qword ptr [rip + svwf_native_starts], 1
    jne .Lsvwf_read_close_failed
    cmp qword ptr [rbx + SV_job_serial], 1
    jne .Lsvwf_read_close_failed
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvwf_read_close_wait
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 0
    jne svw_fail
    mov eax, 1
    EPILOGUE
.Lsvwf_read_close_failed:
    mov qword ptr [rip + svw_stage], 225
    jmp svw_fail
.Lsvwf_read_close_wait:
    xor eax, eax
    EPILOGUE
