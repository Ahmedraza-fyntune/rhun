# Three structural native-session graphs use actual retained EA/HI/EP suppliers.
# Keeper/fd values are fixture tokens, not spawned-process or collection evidence.
.bss
.p2align 3
ra_peer_sessions: .zero 2 * 8
ra_native_out: .quad 0
.text
ra_fifo_cases:
    PROLOGUE
    mov qword ptr [rip + ra_stage], 249
    mov rbx, [rip + rts_table]
    mov r12d, 18
1:  imul rax, r12, EXT_SIZE
    lea r13, [rip + rts_exts]
    add r13, rax
    mov rdi, r13
    lea rsi, [rip + rts_exts + 17 * EXT_SIZE]
    mov edx, EXT_SIZE
    call memcpy
    # Each copied EXT explicitly acquires its independent supplier references.
    mov rdi, [r13 + EXT_activation_owner]
    call ext_activation_owner_retain
    test rax, rax
    jnz ra_fail
    mov rdi, [r13 + EXT_identity_owner]
    call ext_host_identity_retain
    test rax, rax
    jnz ra_fail
    mov rdi, [r13 + EXT_metadata_owner]
    call ext_prepare_retain
    test rax, rax
    jnz ra_fail
    lea rcx, [r12 + 200]
    mov [r13 + EXT_keeper], rcx
    mov dword ptr [r13 + EXT_status], ES_STARTING
    mov dword ptr [r13 + EXT_startaccepted], 0
    mov dword ptr [r13 + EXT_start_armed], 0
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + EXT_activation_owner]
    lea r8, [rip + ra_peer_sessions]
    mov rax, r12
    sub rax, 18
    lea r8, [r8 + rax*8]
    call rt_session_begin
    test rax, rax
    jnz ra_fail
    mov dword ptr [r13 + EXT_status], ES_RUNNING
    mov dword ptr [r13 + EXT_startaccepted], 1
    mov rdi, rbx
    mov rsi, r12
    mov rax, r12
    sub rax, 18
    lea rdx, [rip + ra_peer_sessions]
    mov rdx, [rdx + rax*8]
    call rt_session_bind
    test rax, rax
    jnz ra_fail
    inc r12
    cmp r12, 20
    jb 1b
    mov r12d, 17
2:  call ra_peer_request
    call ra_admit
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    inc r12
    cmp r12, 20
    jb 2b
    cmp qword ptr [rbx + RT_npending], 3
    jne ra_fail
    cmp qword ptr [rbx + RT_nreserved], 3
    jne ra_fail
    cmp qword ptr [rbx + RT_pending], 18
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 8], 19
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 16], 20
    jne ra_fail
    # Each physical reservation has independent peer/session/age association.
    mov r12d, 17
3:  imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    mov r14, [r13 + RTS_ticket]
    mov rax, [r14 + RTT_reservedRow]
    mov rcx, r12
    sub rcx, 16
    cmp rax, rcx
    jne ra_fail
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r15, [rbx + rax + RT_rows]
    cmp [r15 + RTR_ordinal], r12
    jne ra_fail
    mov rax, [r13 + RTS_session]
    cmp [r15 + RTR_session], rax
    jne ra_fail
    mov rax, [r14 + RTT_acceptSequence]
    cmp [r15 + RTR_acceptSequence], rax
    jne ra_fail
    inc r12
    cmp r12, 20
    jb 3b
    # Invalid reason and selected-builder work both preserve the exact FIFO and owners.
    mov r12d, 18
    call ra_peer_cancel_args
    xor ecx, ecx
    call rt_admit_cancel
    cmp rax, -22
    jne ra_fail
    call ra_fifo_unchanged
    mov qword ptr [rbx + RT_batchCount], 1
    call ra_peer_cancel_args
    call rt_admit_cancel
    mov qword ptr [rbx + RT_batchCount], 0
    cmp rax, -16
    jne ra_fail
    call ra_fifo_unchanged
    # Duplicate queue ordinal refuses without consuming either ticket/reservation.
    mov qword ptr [rbx + RT_pending + 8], 18
    mov r12d, 17
    call ra_peer_cancel_args
    call rt_admit_cancel
    mov qword ptr [rbx + RT_pending + 8], 19
    cmp rax, -22
    jne ra_fail
    call ra_fifo_unchanged
    # Wrong row session fails before any FIFO store, then restore the injected corruption.
    mov r12d, 18
    mov r14, [rbx + RT_rows + RT_ROW_SIZE + RTR_session]
    mov qword ptr [rbx + RT_rows + RT_ROW_SIZE + RTR_session], 0
    call ra_peer_cancel_args
    call rt_admit_cancel
    mov [rbx + RT_rows + RT_ROW_SIZE + RTR_session], r14
    cmp rax, -22
    jne ra_fail
    call ra_fifo_unchanged
    # Middle, first, last cancellation must preserve surviving FIFO order.
    call ra_peer_cancel_args
    call rt_admit_cancel
    test rax, rax
    jnz ra_fail
    cmp qword ptr [rbx + RT_npending], 2
    jne ra_fail
    cmp qword ptr [rbx + RT_nreserved], 2
    jne ra_fail
    cmp qword ptr [rbx + RT_pending], 18
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 8], 20
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 16], 0
    jne ra_fail
    call ra_peer_finish
    mov r12d, 17
    call ra_peer_cancel_args
    call rt_admit_cancel
    test rax, rax
    jnz ra_fail
    cmp qword ptr [rbx + RT_npending], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_pending], 20
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 8], 0
    jne ra_fail
    call ra_peer_finish
    mov r12d, 19
    call ra_peer_cancel_args
    call rt_admit_cancel
    test rax, rax
    jnz ra_fail
    call ra_peer_finish
    mov rax, [rbx + RT_npending]
    or rax, [rbx + RT_nreserved]
    or rax, [rbx + RT_pending]
    jnz ra_fail
    cmp qword ptr [rbx + RT_freeHead], 3
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + 2 * RT_ROW_SIZE + RTR_next], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RTR_next], 2
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RT_ROW_SIZE + RTR_next], 4
    jne ra_fail
    mov r12d, 18
4:  call ra_peer_retire
    inc r12
    cmp r12, 20
    jb 4b
    call tt_drain
    call tt_census
    # Restore canonical request17 for remaining fault cases and original fixture teardown.
    mov r12d, 17
    call ra_peer_request
    mov qword ptr [rip + tt_request + RTQ_id], 7
    EPILOGUE
ra_fifo_unchanged:
    cmp qword ptr [rbx + RT_npending], 3
    jne ra_fail
    cmp qword ptr [rbx + RT_nreserved], 3
    jne ra_fail
    cmp qword ptr [rbx + RT_pending], 18
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 8], 19
    jne ra_fail
    cmp qword ptr [rbx + RT_pending + 16], 20
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RTR_state], RTR_RESERVED
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RT_ROW_SIZE + RTR_state], RTR_RESERVED
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + 2 * RT_ROW_SIZE + RTR_state], RTR_RESERVED
    jne ra_fail
    ret
ra_peer_request:
    mov [rip + tt_request + RTQ_ordinal], r12
    mov rax, [rip + rts_session]
    cmp r12, 17
    je 1f
    mov rax, r12
    sub rax, 18
    lea rcx, [rip + ra_peer_sessions]
    mov rax, [rcx + rax*8]
1:  mov [rip + tt_request + RTQ_session], rax
    lea rax, [r12 + 53]
    mov [rip + tt_request + RTQ_id], rax
    ret
ra_peer_cancel_args:
    mov rdi, rbx
    mov rsi, r12
    imul rax, r12, RT_SLOT_SIZE
    mov rdx, [rbx + rax + RT_slots + RTS_session]
    mov ecx, RTRSP_CANCELLED
    mov r8d, 42
    ret
ra_peer_finish:
    PROLOGUE
    imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    cmp qword ptr [r13 + RTS_nreserved], 0
    jne ra_fail
    mov rdi, [r13 + RTS_ticket]
    cmp qword ptr [rdi + RTT_phase], RTT_TERMINAL_ERROR
    jne ra_fail
    cmp qword ptr [rdi + RTT_reservedRow], 0
    jne ra_fail
    call rt_ticket_release
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [r13 + RTS_ticket], 0
    and qword ptr [r13 + RTS_flags], 32
    lea rdi, [r13 + RTS_replyID]
    xor esi, esi
    mov edx, 56
    call memset
    mov qword ptr [r13 + RTS_opKind], 0
    mov qword ptr [r13 + RTS_opStart], 0
    EPILOGUE
ra_peer_retire:
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
    jnz ra_fail
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
    lea rdx, [rip + ra_native_out]
    call ext_activation_host_swap
    test rax, rax
    jnz ra_fail
    mov rdi, [rip + ra_native_out]
    call ext_activation_owner_release
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [rip + ra_native_out], 0
    mov rdi, r14
    call ext_slot_hide_pure
    mov rdi, r14
    lea rsi, [rip + ra_native_out]
    call ext_slot_metadata_take
    test rax, rax
    jnz ra_fail
    mov rdi, [rip + ra_native_out]
    call ext_prepare_release_deferred
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [rip + ra_native_out], 0
    mov rdi, r14
    lea rsi, [rip + ra_native_out]
    call ext_host_identity_take
    test rax, rax
    jnz ra_fail
    mov rdi, [rip + ra_native_out]
    call ext_host_identity_release
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [rip + ra_native_out], 0
    mov r15d, 4
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + RTS_session]
    mov ecx, 100
    call rt_session_cleanup_step
    test rax, rax
    js ra_fail
    cmp rax, 1
    je 2f
    dec r15
    jnz 1b
    jmp ra_fail
2:  cmp qword ptr [r13 + RTS_state], RTS_FREE
    jne ra_fail
    EPILOGUE

# Maximum canonical source spans are copied once and remain owned after source overwrite.
ra_max_cases:
    PROLOGUE
    mov qword ptr [rip + ra_stage], 251
    mov rbx, [rip + rts_table]
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    lea rdi, [rip + tt_key]
    mov esi, 'a'
    mov edx, 40
    call memset
    lea rdi, [rip + tt_title]
    mov esi, 't'
    mov edx, 80
    call memset
    lea rdi, [rip + tt_keys]
    mov esi, 'k'
    mov edx, 65536
    call memset
    mov qword ptr [rip + tt_request + RTQ_id], 7
    mov qword ptr [rip + tt_request + RTQ_keyLen], 40
    lea rax, [rip + tt_title]
    mov [rip + tt_request + RTQ_title], rax
    mov qword ptr [rip + tt_request + RTQ_titleLen], 80
    lea rax, [rip + tt_keys]
    mov [rip + tt_request + RTQ_keys], rax
    mov qword ptr [rip + tt_request + RTQ_keysLen], 65536
    mov qword ptr [rip + ra_validation_count], 0
    call ra_admit
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    cmp qword ptr [rip + ra_validation_count], 1
    jne ra_fail
    mov r13, [r12 + RTS_ticket]
    cmp qword ptr [r13 + RTT_fixedBytes], RTT_MAX_SIZE
    jne ra_fail
    lea rdi, [rip + tt_key]
    mov esi, 'z'
    mov edx, 40
    call memset
    lea rdi, [rip + tt_title]
    mov esi, 'z'
    mov edx, 80
    call memset
    lea rdi, [rip + tt_keys]
    mov esi, 'z'
    mov edx, 65536
    call memset
    lea rdi, [r13 + RTT_HEADER_SIZE]
    mov esi, 40
    mov edx, 'a'
    call tt_bytes
    mov rdi, [r13 + RTT_titleOffset]
    add rdi, r13
    mov esi, 80
    mov edx, 't'
    call tt_bytes
    mov rdi, [r13 + RTT_keysOffset]
    add rdi, r13
    mov esi, 65536
    mov edx, 'k'
    call tt_bytes
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_CANCELLED
    mov r8d, 42
    call rt_admit_cancel
    test rax, rax
    jnz ra_fail
    mov rdi, r13
    call rt_ticket_release
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [r12 + RTS_ticket], 0
    call ra_clear_credit
    call tt_drain
    call tt_census
    mov byte ptr [rip + tt_key], 'a'
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
    mov qword ptr [rip + tt_request + RTQ_title], 0
    mov qword ptr [rip + tt_request + RTQ_titleLen], 0
    mov qword ptr [rip + tt_request + RTQ_keys], 0
    mov qword ptr [rip + tt_request + RTQ_keysLen], 0
    EPILOGUE
