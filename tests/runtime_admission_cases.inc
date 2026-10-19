.equ RA_INVALID_LEN, 48
.equ RA_CANCELLED_LEN, 18
.include "app/extruntimeadmit.inc"
.bss
.p2align 3
ra_credit_watch: .quad 0
.globl ra_validation_count
ra_validation_count: .quad 0
ra_aliases: .zero 8 * 16
ra_stage: .quad 0
ra_authority: .quad 0
ra_accept: .quad 0
ra_saved_reply: .zero 128
.text
ra_cases:
    PROLOGUE
    mov rbx, [rip + rts_table]
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    mov qword ptr [rip + ra_stage], 240
    mov byte ptr [rip + tt_key], 'a'
    mov qword ptr [rip + tt_request + RTQ_id], 7
    mov qword ptr [rip + tt_request + RTQ_title], 0
    mov qword ptr [rip + tt_request + RTQ_titleLen], 0
    mov qword ptr [rip + tt_request + RTQ_keys], 0
    mov qword ptr [rip + tt_request + RTQ_keysLen], 0
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
    # Overlap refusal owns nothing, allocates nothing and preserves native grant.
    mov rdi, rbx
    mov rsi, rbx
    call rt_admit
    cmp rax, -22
    jne ra_fail
    test rdx, rdx
    jnz ra_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne ra_fail
    # Terminal credit is independent of heap and supports the full native ID range.
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 0x7fffffff
    mov r8d, RTRSP_INVALID
    call rt_reject
    cmp rax, -22
    jne ra_fail
    cmp rdx, 1
    jne ra_fail
    lea rsi, [rip + ra_invalid]
    mov edx, RA_INVALID_LEN
    call ra_reply_equal
    mov qword ptr [rip + ra_stage], 246
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_OOM
    mov r8d, 123
    call rt_reply_freeze
    cmp rax, -114
    jne ra_fail
    lea rsi, [rip + ra_invalid]
    mov edx, RA_INVALID_LEN
    call ra_reply_equal
    call ra_clear_credit
    # Capture cannot change current runtime or authority epochs.
    mov rax, [rip + rt_authority_epoch]
    mov [rip + ra_authority], rax
    mov rax, [rip + rt_last_accept]
    mov [rip + ra_accept], rax
    mov qword ptr [rip + ra_stage], 241
    mov qword ptr [rip + ra_validation_count], 0
    mov qword ptr [rip + ra_credit_watch], 1
    call ra_admit
    mov qword ptr [rip + ra_credit_watch], 0
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [rip + ra_stage], 250
    cmp qword ptr [rip + ra_validation_count], 1
    jne ra_fail
    mov qword ptr [rip + ra_stage], 242
    cmp qword ptr [r12 + RTS_nreserved], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_nreserved], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_npending], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_pending], 18
    jne ra_fail
    cmp qword ptr [rbx + RT_mutation], 1
    jne ra_fail
    mov rax, [rip + ra_authority]
    cmp [rip + rt_authority_epoch], rax
    jne ra_fail
    mov rax, [rip + ra_accept]
    inc rax
    cmp [rip + rt_last_accept], rax
    jne ra_fail
    mov r13, [r12 + RTS_ticket]
    test r13, r13
    jz ra_fail
    cmp qword ptr [r13 + RTT_reservedRow], 1
    jne ra_fail
    cmp qword ptr [r13 + RTT_phase], RTT_PENDING
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RTR_state], RTR_RESERVED
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RTR_ordinal], 17
    jne ra_fail
    mov rax, [rip + rts_session]
    cmp [rbx + RT_rows + RTR_session], rax
    jne ra_fail
    mov byte ptr [rip + tt_key], 'z'
    cmp byte ptr [r13 + RTT_HEADER_SIZE], 'a'
    jne ra_fail
    mov byte ptr [rip + tt_key], 'a'
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 8
    call rt_credit_begin
    cmp rax, -11
    jne ra_fail
    test rdx, rdx
    jnz ra_fail
    mov qword ptr [rip + ra_stage], 243
    # Complete negative-time preflight must precede reservation/FIFO mutation.
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_CANCELLED
    mov r8, -1
    call rt_admit_cancel
    cmp rax, -22
    jne ra_fail
    cmp qword ptr [rbx + RT_npending], 1
    jne ra_fail
    cmp qword ptr [r13 + RTT_reservedRow], 1
    jne ra_fail
    cmp qword ptr [r12 + RTS_delivery], 0
    jne ra_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_CANCELLED
    mov r8d, 42
    call rt_admit_cancel
    test rax, rax
    jnz ra_fail
    cmp qword ptr [r13 + RTT_phase], RTT_TERMINAL_ERROR
    jne ra_fail
    cmp qword ptr [r13 + RTT_reservedRow], 0
    jne ra_fail
    mov rax, [rbx + RT_npending]
    or rax, [rbx + RT_nreserved]
    or rax, [r12 + RTS_nreserved]
    or rax, [rbx + RT_pending]
    jnz ra_fail
    cmp qword ptr [rbx + RT_freeHead], 1
    jne ra_fail
    cmp qword ptr [rbx + RT_rows + RTR_state], RTR_FREE
    jne ra_fail
    lea rsi, [rip + ra_cancelled]
    mov edx, RA_CANCELLED_LEN
    call ra_reply_equal
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
    # A semantic reference overflow still owns an answer, and allocates nothing.
    mov rax, [rip + af_ea]
    mov qword ptr [rax + PO_refs], -1
    mov qword ptr [rip + tt_alloc_calls], 0
    mov qword ptr [rip + tt_armed], 1
    call ra_admit
    mov qword ptr [rip + tt_armed], 0
    mov r13, rax
    mov r14, rdx
    mov rax, [rip + af_ea]
    mov rcx, [rip + tt_refs]
    mov [rax + PO_refs], rcx
    cmp r13, -11
    jne ra_fail
    cmp r14, 1
    jne ra_fail
    cmp qword ptr [rip + tt_alloc_calls], 0
    jne ra_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne ra_fail
    call ra_clear_credit
    call tt_census


    mov qword ptr [rip + ra_stage], 247
    # Owned syntax error does not allocate or reserve a physical row.
    mov byte ptr [rip + tt_key], '!'
    call ra_admit
    mov byte ptr [rip + tt_key], 'a'
    cmp rax, -22
    jne ra_fail
    cmp rdx, 1
    jne ra_fail
    cmp qword ptr [r12 + RTS_outcome], RTRSP_INVALID + 1
    jne ra_fail
    call ra_clear_credit
    # Sources that alias inline response storage are refused before byte reads/stores.
    mov r13, [rip + tt_request + RTQ_key]
    lea rax, [r12 + RTS_reply]
    mov [rip + tt_request + RTQ_key], rax
    call ra_admit
    mov [rip + tt_request + RTQ_key], r13
    cmp rax, -22
    jne ra_fail
    test rdx, rdx
    jnz ra_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne ra_fail
    call ra_alias_cases
    # Fixed reason frames and saturated absolute deadlines have an independent byte oracle.
    xor r13d, r13d
.Lra_reason_loop:
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 1
    call rt_credit_begin
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov rcx, r13
    mov r8, 0x7ffffffffffffffa
    call rt_reply_freeze
    test rax, rax
    jnz ra_fail
    mov rax, 0x7fffffffffffffff
    cmp [r12 + RTS_stallDeadline], rax
    jne ra_fail
    lea rax, [rip + ra_reason_rows]
    mov rcx, r13
    shl rcx, 4
    mov rsi, [rax + rcx]
    mov rdx, [rax + rcx + 8]
    call ra_reply_equal
    call ra_clear_credit
    inc r13
    cmp r13, 10
    jb .Lra_reason_loop

    call ra_max_cases
    call ra_fifo_cases

.if RA_TEST_FAULT != 0
    mov qword ptr [rip + ra_stage], 244
    mov qword ptr [rip + tt_alloc_calls], 0
    mov qword ptr [rip + tt_armed], 1
.if RA_TEST_FAULT == 1 || RA_TEST_FAULT == 2
    mov qword ptr [rip + tt_fail_at], RA_TEST_FAULT
.endif
.if RA_TEST_FAULT == 3 || RA_TEST_FAULT == 7
    mov qword ptr [rip + tt_mark_fault], 1
.endif
.if RA_TEST_FAULT == 4 || RA_TEST_FAULT == 7
    mov qword ptr [rip + tt_drop_mode], 1
.endif
.if RA_TEST_FAULT == 5
    mov qword ptr [rip + tt_drop_mode], 2
.endif
.if RA_TEST_FAULT == 6
    mov qword ptr [rip + tt_register_fault], 1
.endif
    mov qword ptr [rip + ra_credit_watch], 1
    call ra_admit
    mov qword ptr [rip + ra_credit_watch], 0
    mov qword ptr [rip + tt_armed], 0
.if RA_TEST_FAULT == 1 || RA_TEST_FAULT == 2
    cmp rax, -12
.else
    cmp rax, -11
.endif
    jne ra_fail
    cmp rdx, 1
    jne ra_fail
    cmp qword ptr [r12 + RTS_replyID], 7
    jne ra_fail
.if RA_TEST_FAULT == 1 || RA_TEST_FAULT == 2
    cmp qword ptr [r12 + RTS_outcome], RTRSP_OOM + 1
    jne ra_fail
    lea rsi, [rip + ra_oom7]
    mov edx, 31
.else
    cmp qword ptr [r12 + RTS_outcome], RTRSP_BUSY + 1
    jne ra_fail
    lea rsi, [rip + ra_busy7]
    mov edx, 39
.endif
    call ra_reply_equal
    cmp qword ptr [r12 + RTS_ticket], 0
    jne ra_fail
    cmp qword ptr [rbx + RT_npending], 0
    jne ra_fail
    cmp qword ptr [rbx + RT_nreserved], 0
    jne ra_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne ra_fail
.if RA_TEST_FAULT == 4 || RA_TEST_FAULT == 7
    cmp qword ptr [r12 + RTS_orphanEO], 0
    je ra_fail
.else
    cmp qword ptr [r12 + RTS_orphanEO], 0
    jne ra_fail
.endif
.if RA_TEST_FAULT == 3 || RA_TEST_FAULT == 4 || RA_TEST_FAULT == 5 || RA_TEST_FAULT == 7
    cmp qword ptr [r12 + RTS_failedPO], 0
    je ra_fail
.else
    cmp qword ptr [r12 + RTS_failedPO], 0
    jne ra_fail
.endif
    mov rdi, [r12 + RTS_failedPO]
    call rt_ticket_release
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [r12 + RTS_failedPO], 0
    mov rdi, [r12 + RTS_orphanEO]
    test rdi, rdi
    jz 991f
    call ext_prepare_owner_release_deferred
    test rax, rax
    jnz ra_fail
    cmp rdx, 1
    jne ra_fail
    mov qword ptr [r12 + RTS_orphanEO], 0
991:
    call ra_clear_credit
    call tt_drain
    # A consumed-negative initial EO records the cleanup diagnostic on common RD.
.if RA_TEST_FAULT == 5
    call ext_prepare_retire_ack
.endif
    call tt_census
.endif
    # Duplicate of an independent outstanding prompt is consumed-fatal, no reply.
    mov qword ptr [rip + ra_stage], 245
    mov qword ptr [r12 + RTS_promptID], 19
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 19
    call rt_credit_begin
    cmp rax, -71
    jne ra_fail
    cmp rdx, 2
    jne ra_fail
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    jne ra_fail
    cmp qword ptr [r12 + RTS_grantSession], 0
    jne ra_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne ra_fail
    cmp qword ptr [r12 + RTS_promptID], 19
    jne ra_fail
    mov rax, [r12 + RTS_flags]
    shr rax, 32
    cmp eax, RT_STOP_DUPLICATE_ID
    jne ra_fail
    # Private graph teardown restores this artificial host for original session regressions.
    # No native collection/restart or reply-delivery proof is inferred from this reset.
    mov qword ptr [r12 + RTS_promptID], 0
    mov qword ptr [r12 + RTS_state], RTS_ACTIVE
    mov qword ptr [r12 + RTS_flags], 0
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_session_bind
    test rax, rax
    jnz ra_fail
    mov qword ptr [rip + ra_stage], 245
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 20
    call rt_credit_begin
    test rax, rax
    jnz ra_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    xor ecx, ecx
    mov r8d, 1
    call rt_reply_freeze
    test rax, rax
    jnz ra_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 20
    call rt_credit_begin
    cmp rax, -71
    jne ra_fail
    cmp rdx, 2
    jne ra_fail
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    jne ra_fail
    cmp qword ptr [r12 + RTS_replyID], 20
    jne ra_fail
    cmp qword ptr [r12 + RTS_outcome], RTRSP_OK + 1
    jne ra_fail
    lea rsi, [rip + ra_committed]
    mov edx, 6
    call ra_reply_equal
    call ra_clear_credit
    mov qword ptr [r12 + RTS_state], RTS_ACTIVE
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_session_bind
    test rax, rax
    jnz ra_fail
    EPILOGUE
ra_admit:
    mov rdi, [rip + rts_table]
    lea rsi, [rip + tt_request]
    jmp rt_admit
ra_reply_equal:
    PROLOGUE
    mov rdi, [rip + rts_table]
    lea rdi, [rdi + RT_slots + 17 * RT_SLOT_SIZE]
    cmp [rdi + RTS_replyLen], rdx
    jne ra_fail
    cmp qword ptr [rdi + RTS_delivery], RTDEL_WAIT
    jne ra_fail
    add rdi, RTS_reply
    call memeq
    test eax, eax
    jz ra_fail
    EPILOGUE
# Fixture-only consumption of already asserted inline reply, with no owned supplier left.
# Queue acceptance and native parser resumption are not claimed by this helper.
ra_clear_credit:
    mov rax, [rip + rts_table]
    lea rax, [rax + RT_slots + 17 * RT_SLOT_SIZE]
    mov qword ptr [rax + RTS_flags], 0
    mov qword ptr [rax + RTS_replyID], 0
    mov qword ptr [rax + RTS_outcome], 0
    mov qword ptr [rax + RTS_delivery], 0
    mov qword ptr [rax + RTS_replyLen], 0
    mov qword ptr [rax + RTS_retryDue], 0
    mov qword ptr [rax + RTS_backoff], 0
    mov qword ptr [rax + RTS_stallDeadline], 0
    mov qword ptr [rax + RTS_opKind], 0
    mov qword ptr [rax + RTS_opStart], 0
    ret
ra_alloc_fail:
    mov edi, 241
    jmp sys_exit
ra_fail:
    mov rdi, [rip + ra_stage]
    jmp sys_exit

# Readable native allocation aliases must never become an owned semantic rejection.
ra_alias_cases:
    PROLOGUE
    mov qword ptr [rip + ra_stage], 248
    mov rbx, [rip + rts_table]
    lea r12, [rip + ra_aliases]
    mov rax, [rbx + RT_stableExtBase]
    add rax, 17 * EXT_SIZE
    mov [r12], rax
    mov qword ptr [r12 + 8], 1
    mov rax, [rip + af_ea]
    mov [r12 + 16], rax
    mov qword ptr [r12 + 24], 1
    mov rcx, [rax + PO_eo]
    mov [r12 + 48], rcx
    mov qword ptr [r12 + 56], 1
    dec rax
    mov [r12 + 96], rax
    mov qword ptr [r12 + 104], 2
    mov rax, [rip + ss_hi]
    mov [r12 + 32], rax
    mov qword ptr [r12 + 40], 1
    mov rcx, [rax + PO_eo]
    mov [r12 + 64], rcx
    mov qword ptr [r12 + 72], 1
    dec rax
    mov [r12 + 112], rax
    mov qword ptr [r12 + 120], 2
    mov rcx, [rbx + PO_eo]
    mov [r12 + 80], rcx
    mov qword ptr [r12 + 88], 1
    xor r13d, r13d
1:  mov rax, [r12 + r13]
    mov [rip + tt_request + RTQ_key], rax
    mov rax, [r12 + r13 + 8]
    mov [rip + tt_request + RTQ_keyLen], rax
    mov qword ptr [rip + tt_alloc_calls], 0
    mov qword ptr [rip + tt_armed], 1
    call ra_admit
    mov qword ptr [rip + tt_armed], 0
    cmp rax, -22
    jne ra_fail
    test rdx, rdx
    jnz ra_fail
    cmp qword ptr [rip + tt_alloc_calls], 0
    jne ra_fail
    cmp qword ptr [rbx + RT_slots + 17 * RT_SLOT_SIZE + RTS_replyID], 0
    jne ra_fail
    add r13, 16
    cmp r13, 8 * 16
    jb 1b
    lea rax, [rip + tt_key]
    mov [rip + tt_request + RTQ_key], rax
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
    EPILOGUE
.section .rodata
ra_invalid: .ascii "error 2147483647 syntax invalid runtime request\n"
ra_cancelled: .ascii "error 7 cancelled\n"

.p2align 3
ra_reason_rows:
    .quad ra_reason_0,5
    .quad ra_reason_1,39
    .quad ra_reason_2,39
    .quad ra_reason_3,31
    .quad ra_reason_4,27
    .quad ra_reason_5,35
    .quad ra_reason_6,56
    .quad ra_reason_7,36
    .quad ra_reason_8,42
    .quad ra_reason_9,18
ra_reason_0: .ascii "ok 1\n"
ra_reason_1: .ascii "error 1 syntax invalid runtime request\n"
ra_reason_2: .ascii "error 1 busy runtime request cancelled\n"
ra_reason_3: .ascii "error 1 busy allocation failed\n"
ra_reason_4: .ascii "error 1 toobig 64 commands\n"
ra_reason_5: .ascii "error 1 refused the name is in use\n"
ra_reason_6: .ascii "error 1 refused not a runtime command of this extension\n"
ra_reason_7: .ascii "error 1 unknown unsupported request\n"
ra_reason_8: .ascii "error 1 refused command catalogue invalid\n"
ra_reason_9: .ascii "error 1 cancelled\n"
ra_committed: .ascii "ok 20\n"
ra_oom7: .ascii "error 7 busy allocation failed\n"
ra_busy7: .ascii "error 7 busy runtime request cancelled\n"
