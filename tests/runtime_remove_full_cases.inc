# Full physical capacity with independently retained EA/HI/EP session graphs.
# Keeper/fd values remain structural tokens, not spawned-process evidence.
.bss
.p2align 3
rr_full_sessions: .zero 128 * 8
rr_full_native_out: .quad 0
rr_full_ord: .quad 0
rr_full_key: .quad 0
rr_full_old_count: .quad 0
rr_full_retire: .zero 32
.text
rr_full_cases:
    PROLOGUE 32
    mov qword ptr [rip + rr_stage], 173
    mov rbx, [rip + rts_table]
    or dword ptr [rip + rts_exts + 17 * EXT_SIZE + EXT_features], FEAT_COMMANDS
    mov rax, [rip + rts_session]
    mov [rip + rr_full_sessions + 17 * 8], rax
    xor r12d, r12d
.Lrrf_clone:
    cmp r12, 17
    je .Lrrf_next_clone
    imul rax, r12, EXT_SIZE
    lea r13, [rip + rts_exts]
    add r13, rax
    mov rdi, r13
    lea rsi, [rip + rts_exts + 17 * EXT_SIZE]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, [r13 + EXT_activation_owner]
    call ext_activation_owner_retain
    test rax, rax
    jnz rr_fail
    mov rdi, [r13 + EXT_identity_owner]
    call ext_host_identity_retain
    test rax, rax
    jnz rr_fail
    mov rdi, [r13 + EXT_metadata_owner]
    call ext_prepare_retain
    test rax, rax
    jnz rr_fail
    lea rcx, [r12 + 200]
    mov [r13 + EXT_keeper], rcx
    mov dword ptr [r13 + EXT_status], ES_STARTING
    mov dword ptr [r13 + EXT_startaccepted], 0
    mov dword ptr [r13 + EXT_start_armed], 0
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + EXT_activation_owner]
    lea r8, [rip + rr_full_sessions]
    lea r8, [r8 + r12*8]
    call rt_session_begin
    test rax, rax
    jnz rr_fail
    mov dword ptr [r13 + EXT_status], ES_RUNNING
    mov dword ptr [r13 + EXT_startaccepted], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + rr_full_sessions]
    mov rdx, [rdx + r12*8]
    call rt_session_bind
    test rax, rax
    jnz rr_fail
.Lrrf_next_clone:
    inc r12
    cmp r12, 128
    jb .Lrrf_clone
    mov qword ptr [rip + rr_full_ord], 0
.Lrrf_peer_seed:
    mov rax, [rip + rr_full_ord]
    imul rcx, rax, EXT_SIZE
    lea rdx, [rip + rts_exts]
    add rdx, rcx
    mov [rip + rr_config + ROC_target], rdx
    lea rdx, [rip + rr_full_sessions]
    mov rdx, [rdx + rax*8]
    mov [rip + rr_config + ROC_session], rdx
    imul rax, rax, RT_SLOT_SIZE
    lea r12, [rbx + rax + RT_slots]
    lea rax, [rip + rr_many_key]
    mov [rip + rr_config + ROC_key], rax
    mov qword ptr [rip + rr_full_key], 0
.Lrrf_seed:
    mov rdi, [rip + rr_full_key]
    call rr_many_make_key
    lea rdi, [rip + rr_config]
    call ext_runtime_new
    test rax, rax
    jz rr_fail
    mov [rsp], rax
    mov r13, [rbx + RT_freeHead]
    test r13, r13
    jz rr_fail
    lea rax, [r13 - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r14, [rbx + rax + RT_rows]
    mov rax, [r14 + RTR_next]
    mov [rbx + RT_freeHead], rax
    mov rax, [rsp]
    mov [r14 + RTR_ro], rax
    mov rax, [rip + rr_full_ord]
    mov [r14 + RTR_ordinal], rax
    lea rdx, [rip + rr_full_sessions]
    mov rdx, [rdx + rax*8]
    mov [r14 + RTR_session], rdx
    imul rax, rax, 64
    add rax, [rip + rr_full_key]
    inc rax
    mov [r14 + RTR_acceptSequence], rax
    mov rax, [rbx + RT_liveTail]
    mov [r14 + RTR_prev], rax
    mov qword ptr [r14 + RTR_next], 0
    test rax, rax
    jz 1f
    dec rax
    imul rax, rax, RT_ROW_SIZE
    mov [rbx + rax + RT_rows + RTR_next], r13
    jmp 2f
1:  mov [rbx + RT_liveHead], r13
2:  mov [rbx + RT_liveTail], r13
    mov qword ptr [r14 + RTR_state], RTR_LIVE
    mov rax, [r12 + RTS_liveHead]
    mov [r14 + RTR_slotNext], rax
    mov [r12 + RTS_liveHead], r13
    inc qword ptr [r12 + RTS_nlive]
    inc qword ptr [rbx + RT_nlive]
    inc qword ptr [rip + rr_full_key]
    cmp qword ptr [rip + rr_full_key], 64
    jb .Lrrf_seed
    inc qword ptr [rip + rr_full_ord]
    cmp qword ptr [rip + rr_full_ord], 128
    jb .Lrrf_peer_seed
    mov qword ptr [rip + rr_stage], 174
    cmp qword ptr [rbx + RT_nlive], 8192
    jne rr_fail
    cmp qword ptr [rbx + RT_freeHead], 0
    jne rr_fail
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    lea rax, [rip + rr_many_key]
    mov [rip + rr_request + RTQ_key], rax
    mov qword ptr [rip + rr_request + RTQ_keyLen], 2
    xor edi, edi
    call rr_many_make_key
    call rr_call
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_nlive], 8191
    jne rr_fail
    cmp qword ptr [rbx + RT_freeHead], 0
    jne rr_fail
    cmp qword ptr [r12 + RTS_nlive], 63
    jne rr_fail
    call rr_clear_credit
    # 127 other suppliers still have the same key. They cannot satisfy this lookup.
    call rr_call
    cmp rax, -2
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_slots + 18 * RT_SLOT_SIZE + RTS_nlive], 64
    jne rr_fail
    call rr_clear_credit
    # A logical vacancy cannot reuse a physical DEBT row before its ref is consumed.
    mov qword ptr [rip + rr_stage], 175
    lea rax, [rip + rr_many_missing]
    mov [rip + rr_request + RTQ_key], rax
    mov qword ptr [rip + rr_request + RTQ_kind], RTQ_REGISTER
    lea rax, [rip + rr_title]
    mov [rip + rr_request + RTQ_title], rax
    mov qword ptr [rip + rr_request + RTQ_titleLen], 7
    mov qword ptr [rip + tt_alloc_calls], 0
    mov qword ptr [rip + tt_fail_at], 0x7fffffff
    mov qword ptr [rip + tt_armed], 1
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rt_admit
    mov qword ptr [rip + tt_armed], 0
    cmp qword ptr [rip + tt_alloc_calls], 0
    jne rr_fail
    cmp rax, -7
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    mov rax, [rbx + RT_nreserved]
    or rax, [rbx + RT_npending]
    or rax, [r12 + RTS_ticket]
    jnz rr_fail
    call rr_clear_credit
    mov rdi, rbx
    mov esi, 42
    mov edx, 1
    call rr_checked_debt
    test rax, rax
    js rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_freeHead], 0
    je rr_fail
    # Now the same native admission really reserves the consumed physical slot.
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rt_admit
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_nreserved], 1
    jne rr_fail
    cmp qword ptr [rbx + RT_npending], 1
    jne rr_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 9
    mov r8d, 42
    call rt_admit_cancel
    test rax, rax
    jnz rr_fail
    mov rdi, [r12 + RTS_ticket]
    call rt_ticket_release
    cmp rdx, 1
    jne rr_fail
    test rax, rax
    jnz rr_fail
    mov qword ptr [r12 + RTS_ticket], 0
    call rr_clear_credit
    mov rdi, rbx
    call rt_table_close
    test rax, rax
    jnz rr_fail
    mov qword ptr [rip + rr_stage], 176
    mov r15d, 1024
.Lrrf_revoke:
    mov rax, [rbx + RT_nlive]
    mov [rip + rr_full_old_count], rax
    mov rdi, rbx
    mov esi, 50
    mov edx, 16
    call rr_checked_revoke
    test rax, rax
    js rr_fail
    cmp rdx, 16
    ja rr_fail
    mov rax, [rip + rr_full_old_count]
    sub rax, [rbx + RT_nlive]
    cmp rax, 16
    ja rr_fail
    cmp qword ptr [rbx + RT_nlive], 0
    je .Lrrf_drain_start
    dec r15
    jnz .Lrrf_revoke
    jmp rr_fail
.Lrrf_drain_start:
    mov qword ptr [rip + rr_stage], 177
    mov r15d, 1024
.Lrrf_debt:
    mov rdi, rbx
    mov esi, 60
    mov edx, 16
    call rr_checked_debt
    test rax, rax
    js rr_fail
    cmp rdx, 16
    ja rr_fail
    cmp qword ptr [rbx + RT_debtHead], 0
    je .Lrrf_verify_free
    dec r15
    jnz .Lrrf_debt
    jmp rr_fail
.Lrrf_verify_free:
    mov qword ptr [rip + rr_stage], 178
    xor ecx, ecx
    mov rax, [rbx + RT_freeHead]
1:  test rax, rax
    jz 2f
    cmp rax, 8192
    ja rr_fail
    inc rcx
    cmp rcx, 8192
    ja rr_fail
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea rdx, [rbx + rax + RT_rows]
    cmp qword ptr [rdx + RTR_state], RTR_FREE
    jne rr_fail
    cmp qword ptr [rdx + RTR_ro], 0
    jne rr_fail
    mov rax, [rdx + RTR_next]
    jmp 1b
2:  cmp rcx, 8192
    jne rr_fail
    mov qword ptr [rip + rr_stage], 179
    call rr_full_drain
    mov qword ptr [rip + rr_stage], 180
    xor r12d, r12d
.Lrrf_retire_peers:
    cmp r12, 17
    je 3f
    call rr_full_peer_retire
3:  inc r12
    cmp r12, 128
    jb .Lrrf_retire_peers
    mov qword ptr [rip + rr_stage], 181
    call rr_full_drain
    mov rax, [rip + rr_live]
    cmp [rip + g_mem_live], rax
    jne rr_fail
    mov rax, [rip + rr_charge]
    cmp [rip + prep_total_charge], rax
    jne rr_fail
    mov eax, [rip + rr_flags]
    mov [rip + rts_exts + 17 * EXT_SIZE + EXT_features], eax
    EPILOGUE
rr_full_drain:
    PROLOGUE
    mov r14d, 4096
1:  mov edi, 16
    lea rsi, [rip + rr_full_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + rr_full_retire], 16
    ja rr_fail
    cmp qword ptr [rip + rr_full_retire + 16], 0
    jne rr_fail
    cmp qword ptr [rip + rr_full_retire + 24], 0
    jne rr_fail
    cmp qword ptr [rip + rr_full_retire + 8], 0
    je 2f
    dec r14
    jnz 1b
    jmp rr_fail
2:  EPILOGUE
rr_full_peer_retire:
    PROLOGUE
    imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    imul rax, r12, EXT_SIZE
    lea r14, [rip + rts_exts]
    add r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + RTS_session]
    mov ecx, 88
    call rt_session_end
    test rax, rax
    jnz rr_fail
    # Same explicit private native-collection model as the original structural fixture.
    mov qword ptr [r14 + EXT_keeper], 0
    mov dword ptr [r14 + EXT_pid], 0
    mov dword ptr [r14 + EXT_in], -1
    mov dword ptr [r14 + EXT_out], -1
    mov dword ptr [r14 + EXT_log], -1
    mov dword ptr [r14 + EXT_host_child_in], -1
    mov dword ptr [r14 + EXT_host_child_out], -1
    mov dword ptr [r14 + EXT_status], ES_IDLE
    mov dword ptr [r14 + EXT_retiring], 2
    mov dword ptr [r14 + EXT_stdout_eof], 1
    mov rdi, r14
    xor esi, esi
    lea rdx, [rip + rr_full_native_out]
    call ext_activation_host_swap
    test rax, rax
    jnz rr_fail
    mov rdi, [rip + rr_full_native_out]
    call ext_activation_owner_release
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_full_native_out], 0
    mov rdi, r14
    call ext_slot_hide_pure
    mov rdi, r14
    lea rsi, [rip + rr_full_native_out]
    call ext_slot_metadata_take
    test rax, rax
    jnz rr_fail
    mov rdi, [rip + rr_full_native_out]
    call ext_prepare_release_deferred
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_full_native_out], 0
    mov rdi, r14
    lea rsi, [rip + rr_full_native_out]
    call ext_host_identity_take
    test rax, rax
    jnz rr_fail
    mov rdi, [rip + rr_full_native_out]
    call ext_host_identity_release
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_full_native_out], 0
    mov r15d, 4
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + RTS_session]
    mov ecx, 100
    call rt_session_cleanup_step
    test rax, rax
    js rr_fail
    cmp rax, 1
    je 2f
    dec r15
    jnz 1b
    jmp rr_fail
2:  cmp qword ptr [r13 + RTS_state], RTS_FREE
    jne rr_fail
    EPILOGUE

