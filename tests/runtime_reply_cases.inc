.include "app/extruntimereply.inc"
.include "app/extruntime.inc"
.bss
.p2align 3
rpl_stage: .quad 0
rpl_ext_saved: .zero EXT_SIZE
rpl_slot_saved: .zero RT_SLOT_SIZE
rpl_due: .quad 0
rpl_drop_mode: .quad 0
rpl_drop_calls: .quad 0
rpl_eo_mode: .quad 0
rpl_eo_calls: .quad 0
rpl_events: .quad 0
rpl_expected_diag: .quad 0
rpl_copy_bytes: .quad 0
rpl_compactions: .quad 0
rpl_queue_allocations: .quad 0
rpl_queue_refuse: .quad 0
rpl_ro_config: .zero ROC_SIZE
rpl_committed_ro: .quad 0
rpl_unmap_budget: .quad 0
rpl_unmap_live: .quad 0
rpl_unmap_charge: .quad 0
rpl_quiet_other_ea: .quad 0
rpl_quiet_other_hi: .quad 0
.text
FN rpl_copy
    add [rip + rpl_copy_bytes], rdx
    jmp memcpy
FN rpl_move
    inc qword ptr [rip + rpl_compactions]
    add [rip + rpl_copy_bytes], rdx
    jmp memmove
FN rpl_queue_alloc
    inc qword ptr [rip + rpl_queue_allocations]
    cmp qword ptr [rip + rpl_queue_refuse], 0
    jne 1f
    jmp mem_alloc_try
1:  xor eax, eax
    ret
FN rpl_clock
    mov rax, [rip + rpl_due]
    ret
FN rpl_watch
    inc qword ptr [rip + rpl_events]
    xor eax, eax
    ret
FN rpl_ticket_drop
    inc qword ptr [rip + rpl_drop_calls]
    cmp qword ptr [rip + rpl_drop_mode], 2
    je rpl_ticket_negative
    cmp qword ptr [rip + rpl_drop_mode], 0
    je rt_ticket_release
    mov rax, -5
    xor edx, edx
    ret
rpl_ticket_negative:
    PROLOGUE
    call rt_ticket_release
    mov rax, -5
    EPILOGUE
FN rpl_eo_drop
    inc qword ptr [rip + rpl_eo_calls]
    cmp qword ptr [rip + rpl_eo_mode], 0
    je ext_prepare_owner_release_deferred
    mov rax, -5
    xor edx, edx
    ret
rpl_fail:
    mov rdi, [rip + rpl_stage]
    jmp sys_exit
rpl_reply_step:
    mov rdi, rbx
    mov rsi, [rip + rpl_due]
    mov edx, 1
    mov qword ptr [rbx + RT_replyCursor], 17
    jmp rt_reply_step
rpl_cleanup_step:
    mov rdi, rbx
    mov rsi, [rip + rpl_due]
    mov edx, 1
    mov qword ptr [rbx + RT_cleanupCursor], 17
    jmp rt_operation_cleanup_step
rpl_freeze:
    PROLOGUE
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 1
    call rt_credit_begin
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_OK
    mov r8, [rip + rpl_due]
    call rt_reply_freeze
    test rax, rax
    jnz rpl_fail
    EPILOGUE
rpl_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 180
    mov rbx, [rip + rts_table]
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    mov r13, [rbx + RT_stableExtBase]
    add r13, 17 * EXT_SIZE
    lea rdi, [rip + rpl_ext_saved]
    mov rsi, r13
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + rpl_slot_saved]
    mov rsi, r12
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov qword ptr [r13 + EXT_wq + SB_ptr], 0
    mov qword ptr [r13 + EXT_wq + SB_cap], 0
    mov qword ptr [r13 + EXT_wq + SB_len], 0
    mov qword ptr [r13 + EXT_wq_off], 0
    mov qword ptr [rip + rpl_due], 100
    call rpl_freeze
    mov qword ptr [rip + rpl_stage], 181
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    mov rdi, rbx
    mov esi, 100
    call rt_reply_timeout
    cmp rax, 100
    jne rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_ID_IN_USE
    jnz rpl_fail
    mov rax, [r12 + RTS_flags]
    and eax, RTSF_OP_CREDIT | RTSF_PARSER_PAUSED
    cmp eax, RTSF_OP_CREDIT | RTSF_PARSER_PAUSED
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 5
    jne rpl_fail
    mov rdi, [r13 + EXT_wq + SB_ptr]
    lea rsi, [rip + ra_reason_0]
    mov edx, 5
    call memeq
    test eax, eax
    jz rpl_fail
    mov qword ptr [rip + rpl_stage], 182
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 5
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    mov rax, [r12 + RTS_flags]
    and eax, RTSF_OP_CREDIT | RTSF_PARSER_PAUSED | RTSF_ID_IN_USE
    jnz rpl_fail
    mov rax, [r12 + RTS_replyID]
    or rax, [r12 + RTS_outcome]
    or rax, [r12 + RTS_delivery]
    or rax, [r12 + RTS_replyLen]
    or rax, [r12 + RTS_retryDue]
    or rax, [r12 + RTS_backoff]
    or rax, [r12 + RTS_stallDeadline]
    or rax, [r12 + RTS_opKind]
    or rax, [r12 + RTS_opStart]
    jnz rpl_fail
    lea rdi, [r13 + EXT_wq]
    call sb_free
    mov rdi, r13
    lea rsi, [rip + rpl_ext_saved]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, r12
    lea rsi, [rip + rpl_slot_saved]
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov qword ptr [rbx + RT_replyCursor], 0
    mov qword ptr [rbx + RT_cleanupCursor], 0
.if RPL_SCENARIO == 0
    call rpl_time_cases
    call rpl_quiet_cases
.else
.if RPL_SCENARIO == 1
    call rpl_ticket_cases
.else
.if RPL_SCENARIO == 2
    call rpl_memory_cases
.else
.if RPL_SCENARIO == 3
    call rpl_unmap_cases
.else
.if RPL_SCENARIO == 4
    call rpl_fair_cases
.else
    call rpl_committed_cases
.endif
.endif
.endif
.endif
.endif
    EPILOGUE

# Structural native model only, same borrowed EA/HI and fake native endpoints as baseline.
rpl_restore:
    PROLOGUE
    mov rax, [r13 + EXT_wq + SB_ptr]
    cmp rax, [rip + rpl_ext_saved + EXT_wq + SB_ptr]
    je 1f
    lea rdi, [r13 + EXT_wq]
    call sb_free
1:  mov rdi, r13
    lea rsi, [rip + rpl_ext_saved]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, r12
    lea rsi, [rip + rpl_slot_saved]
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov qword ptr [rbx + RT_replyCursor], 0
    mov qword ptr [rbx + RT_cleanupCursor], 0
    EPILOGUE
rpl_time_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 183
    mov qword ptr [rip + rpl_due], 100
    call rpl_freeze
    mov qword ptr [r13 + EXT_in_closed_at], 1
    mov qword ptr [rip + rpl_events], 0
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    cmp qword ptr [r12 + RTS_retryDue], 116
    jne rpl_fail
    cmp qword ptr [r12 + RTS_backoff], 16
    jne rpl_fail
    cmp rcx, 116
    jne rpl_fail
    # An unrelated event before due cannot retry or reset the deadline.
    mov qword ptr [rip + rpl_stage], 184
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [r12 + RTS_retryDue], 116
    jne rpl_fail
    cmp qword ptr [rip + rpl_events], 0
    jne rpl_fail
    mov qword ptr [rip + rpl_due], 116
    call rpl_reply_step
    cmp qword ptr [r12 + RTS_retryDue], 148
    jne rpl_fail
    cmp qword ptr [r12 + RTS_stallDeadline], 10100
    jne rpl_fail
    # Deadline must revoke before a later retryDue permits another attempt.
    mov qword ptr [rip + rpl_stage], 185
    mov qword ptr [r12 + RTS_retryDue], 11000
    mov qword ptr [rip + rpl_due], 10100
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_STOP_REQUIRED
    jz rpl_fail
    cmp qword ptr [r12 + RTS_outcome], RTRSP_OK + 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    cmp rcx, 11000
    jne rpl_fail
    mov qword ptr [rip + rpl_stage], 186
    mov dword ptr [r13 + EXT_in], -1
    mov qword ptr [r13 + EXT_in_closed_at], 0
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_reply_wake
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [r12 + RTS_stallDeadline], 10100
    jne rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_ABANDONED
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne rpl_fail
    cmp qword ptr [r12 + RTS_expectedKeeper], 123
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_PARSER_PAUSED
    jz rpl_fail
    call rpl_restore
    # Terminal clock cannot create an immediately-due retry loop.
    mov qword ptr [rip + rpl_stage], 187
    mov rax, 0x7fffffffffffffff
    mov [rip + rpl_due], rax
    call rpl_freeze
    mov qword ptr [r13 + EXT_in_closed_at], 1
    call rpl_reply_step
    cmp rax, -75
    jne rpl_fail
    cmp qword ptr [rip + prep_retire_first_diagnostic], -75
    jne rpl_fail
    mov qword ptr [rip + rpl_expected_diag], -75
    cmp qword ptr [r12 + RTS_retryDue], RTR_PARKED
    jne rpl_fail
    test rcx, rcx
    jnz rpl_fail
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    jne rpl_fail
    mov qword ptr [rip + rpl_stage], 188
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    test rcx, rcx
    jnz rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    # Only an explicit genuine-event wake rearms the parked class.
    mov dword ptr [r13 + EXT_in], -1
    mov qword ptr [r13 + EXT_in_closed_at], 0
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_reply_wake
    test rax, rax
    jnz rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_ABANDONED
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    EPILOGUE
rpl_request:
    mov qword ptr [rip + tt_request + RTQ_ordinal], 17
    mov rax, [rip + rts_session]
    mov [rip + tt_request + RTQ_session], rax
    mov qword ptr [rip + tt_request + RTQ_id], 1
    mov qword ptr [rip + tt_request + RTQ_kind], RTQ_REGISTER
    lea rax, [rip + tt_key]
    mov [rip + tt_request + RTQ_key], rax
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
    mov qword ptr [rip + tt_request + RTQ_title], 0
    mov qword ptr [rip + tt_request + RTQ_titleLen], 0
    mov qword ptr [rip + tt_request + RTQ_keys], 0
    mov qword ptr [rip + tt_request + RTQ_keysLen], 0
.if RPL_SCENARIO == 3
    lea rax, [rip + tt_keys]
    mov [rip + tt_request + RTQ_keys], rax
    mov qword ptr [rip + tt_request + RTQ_keysLen], 65536
.endif
    mov qword ptr [rip + rpl_due], 100
    mov rdi, rbx
    lea rsi, [rip + tt_request]
    jmp rt_admit
rpl_wake:
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    jmp rt_reply_wake
rpl_ticket_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 189
    call rpl_request
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_CANCELLED
    mov r8d, 100
    call rt_admit_cancel
    test rax, rax
    jnz rpl_fail
    mov r14, [r12 + RTS_ticket]
    test r14, r14
    jz rpl_fail
    cmp qword ptr [r14 + RTT_phase], RTT_TERMINAL_ERROR
    jne rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    mov qword ptr [rip + rpl_stage], 190
    mov qword ptr [rip + rpl_drop_mode], 1
    mov qword ptr [rip + rpl_drop_calls], 0
    call rpl_cleanup_step
    cmp rax, -5
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    cmp [r12 + RTS_ticket], r14
    jne rpl_fail
    cmp qword ptr [r12 + RTS_retryDue], 116
    jne rpl_fail
    cmp qword ptr [rip + prep_retire_first_diagnostic], -5
    jne rpl_fail
    mov qword ptr [rip + rpl_expected_diag], -5
    mov qword ptr [rip + rpl_stage], 191
    call rpl_cleanup_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_PARSER_PAUSED
    jz rpl_fail
    # A selected raw ordinal is a borrower even if phase is terminal.
    mov qword ptr [rip + rpl_stage], 192
    call rpl_wake
    mov qword ptr [rbx + RT_batchCount], 1
    mov qword ptr [rbx + RT_selected0], 17
    call rpl_cleanup_step
    cmp rax, -16
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    call rpl_wake
    mov qword ptr [rbx + RT_selected0], RT_SLOT_COUNT
    call rpl_cleanup_step
    cmp rax, -22
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    mov qword ptr [rbx + RT_batchCount], 0
    mov qword ptr [rbx + RT_selected0], 0
    # Deliberate role/phase corruption must refuse before the drop call.
    mov qword ptr [rip + rpl_stage], 193
    call rpl_wake
    mov qword ptr [r14 + RTT_role], RT_PROMPT_ROLE
    call rpl_cleanup_step
    cmp rax, -22
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    mov qword ptr [r14 + RTT_role], RT_TICKET_ROLE
    call rpl_wake
    mov qword ptr [r14 + RTT_phase], RTT_PENDING
    call rpl_cleanup_step
    cmp rax, -22
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 1
    jne rpl_fail
    mov qword ptr [r14 + RTT_phase], RTT_TERMINAL_ERROR
    call rpl_wake
    mov qword ptr [rip + rpl_stage], 194
    mov qword ptr [rip + rpl_drop_mode], 2
    call rpl_cleanup_step
    cmp rax, -5
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 2
    jne rpl_fail
    cmp qword ptr [r12 + RTS_ticket], 0
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_PARSER_PAUSED
    jz rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_drop_calls], 2
    jne rpl_fail
    mov qword ptr [rip + rpl_drop_mode], 0
    call rpl_restore
    call tt_drain
    call tt_census
    # Real failed custom marking returns an owned generic2 premark ticket.
    mov qword ptr [rip + rpl_stage], 195
    mov qword ptr [rip + tt_mark_fault], 1
    call rpl_request
    cmp rdx, 1
    jne rpl_fail
    mov r14, [r12 + RTS_failedPO]
    test r14, r14
    jz rpl_fail
    cmp qword ptr [r14 - RD_PO_BACK + RD_kind], RD_LEDGER
    jne rpl_fail
    cmp qword ptr [r14 + RTT_phase], RTT_BUILDING
    jne rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_failedPO], 0
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    call tt_drain
    call tt_census
    # Real refused initial EO drop returns BOTH ready failedPO and orphanEO.
    mov qword ptr [rip + rpl_stage], 196
    mov qword ptr [rip + tt_drop_mode], 1
    call rpl_request
    cmp rdx, 1
    jne rpl_fail
    mov r14, [r12 + RTS_failedPO]
    test r14, r14
    jz rpl_fail
    cmp qword ptr [r14 + PO_ready], 1
    jne rpl_fail
    cmp qword ptr [r14 + RTT_phase], RTT_CAPTURED
    jne rpl_fail
    cmp qword ptr [r12 + RTS_orphanEO], 0
    je rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_failedPO], 0
    jne rpl_fail
    cmp qword ptr [r12 + RTS_orphanEO], 0
    je rpl_fail
    mov qword ptr [rip + rpl_stage], 197
    mov qword ptr [rip + rpl_eo_mode], 1
    mov qword ptr [rip + rpl_eo_calls], 0
    call rpl_cleanup_step
    cmp rax, -5
    jne rpl_fail
    cmp qword ptr [rip + rpl_eo_calls], 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_orphanEO], 0
    je rpl_fail
    call rpl_cleanup_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [rip + rpl_eo_calls], 1
    jne rpl_fail
    mov qword ptr [rip + rpl_eo_mode], 0
    call rpl_wake
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_orphanEO], 0
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    call tt_drain
    call tt_census
    EPILOGUE
rpl_memory_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 198
    mov qword ptr [rip + rpl_due], 100
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz rpl_fail
    mov [r13 + EXT_wq + SB_ptr], rax
    mov qword ptr [r13 + EXT_wq + SB_cap], 65536
    mov qword ptr [r13 + EXT_wq + SB_len], 65536
    mov qword ptr [r13 + EXT_wq_off], 4
    mov rdi, rax
    mov esi, 0x4b
    mov edx, 65536
    call memset
    call rpl_freeze
    mov qword ptr [rip + rpl_copy_bytes], 0
    mov qword ptr [rip + rpl_compactions], 0
    mov qword ptr [rip + rpl_queue_allocations], 0
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 0
    jne rpl_fail
    cmp qword ptr [rip + rpl_compactions], 0
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq_off], 4
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 65536
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    mov qword ptr [rip + rpl_stage], 199
    # One modeled positive flush byte creates exactly enough shared copy budget.
    mov qword ptr [r13 + EXT_wq_off], 5
    call rpl_wake
    mov qword ptr [rbx + RT_replyCursor], 17
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 18
    jne rpl_fail
    cmp qword ptr [rip + rpl_compactions], 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 65536
    jne rpl_fail
    cmp qword ptr [rip + rpl_queue_allocations], 0
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq_off], 0
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 65536
    jne rpl_fail
    mov rdi, [r13 + EXT_wq + SB_ptr]
    add rdi, 65531
    lea rsi, [rip + ra_reason_0]
    mov edx, 5
    call memeq
    test eax, eax
    jz rpl_fail
    mov rdi, [r13 + EXT_wq + SB_ptr]
    cmp byte ptr [rdi], 0x4b
    jne rpl_fail
    cmp byte ptr [rdi + 65530], 0x4b
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    # Even an allocation-capable visit with budget16 ends after this one peer.
    mov qword ptr [rip + rpl_stage], 200
    call rpl_freeze
    mov qword ptr [rip + rpl_queue_allocations], 0
    mov qword ptr [rip + rpl_copy_bytes], 0
    mov qword ptr [rbx + RT_replyCursor], 17
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 18
    jne rpl_fail
    cmp qword ptr [rip + rpl_queue_allocations], 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 5
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    # Refused allocation retains the frozen reply and ID and ends the whole slice.
    mov qword ptr [rip + rpl_stage], 207
    call rpl_freeze
    mov qword ptr [rip + rpl_queue_refuse], 1
    mov qword ptr [rip + rpl_queue_allocations], 0
    mov qword ptr [rip + rpl_copy_bytes], 0
    mov qword ptr [rbx + RT_replyCursor], 17
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_queue_allocations], 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 0
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 18
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    cmp qword ptr [r12 + RTS_replyID], 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_outcome], RTRSP_OK + 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_retryDue], 116
    jne rpl_fail
    cmp qword ptr [r12 + RTS_backoff], 16
    jne rpl_fail
    cmp qword ptr [r13 + EXT_wq + SB_ptr], 0
    jne rpl_fail
    mov qword ptr [rip + rpl_queue_refuse], 0
    call rpl_reply_step
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [rip + rpl_queue_allocations], 1
    jne rpl_fail
    call rpl_wake
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_queue_allocations], 2
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_restore
    # The timeout census covers a late scalar credit outside this slice's16 visits.
    # This is an explicit timer model, not a fabricated positive native channel.
    mov qword ptr [rip + rpl_stage], 201
    lea r14, [rbx + RT_slots + 127 * RT_SLOT_SIZE]
    mov qword ptr [r14 + RTS_state], RTS_ACTIVE
    mov qword ptr [r14 + RTS_session], 222
    mov qword ptr [r14 + RTS_flags], RTSF_OP_CREDIT | RTSF_ID_IN_USE | RTSF_PARSER_PAUSED
    mov qword ptr [r14 + RTS_replyID], 2
    mov qword ptr [r14 + RTS_outcome], 1
    mov qword ptr [r14 + RTS_delivery], RTDEL_WAIT
    mov qword ptr [r14 + RTS_replyLen], 5
    mov qword ptr [r14 + RTS_retryDue], 500
    mov qword ptr [r14 + RTS_stallDeadline], 1000
    mov qword ptr [rbx + RT_replyCursor], 17
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    test rax, rax
    jnz rpl_fail
    cmp rdx, 16
    jne rpl_fail
    cmp rcx, 500
    jne rpl_fail
    mov rdi, r14
    xor esi, esi
    mov edx, RT_SLOT_SIZE
    call memset
    call rpl_restore
    EPILOGUE
# A real >64KiB ticket mapping fails the actual native unmap boundary AFTER
# its caller reference is consumed. The common owner must retain charge/header.
rpl_unmap_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 202
    call rpl_request
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    mov r14, [r12 + RTS_ticket]
    cmp qword ptr [r14 + RTT_keysLen], 65536
    jne rpl_fail
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, RTRSP_CANCELLED
    mov r8d, 100
    call rt_admit_cancel
    test rax, rax
    jnz rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_ticket], 0
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_OP_CREDIT | RTSF_PARSER_PAUSED
    jnz rpl_fail
    call rpl_restore
    mov qword ptr [rip + tt_unmap_fault], 1
    mov qword ptr [rip + tt_unmap_calls], 0
    mov qword ptr [rip + tt_unmap_seen], 0
    mov qword ptr [rip + rpl_unmap_budget], 4096
.Lrpl_gc:
    mov rax, [rip + g_mem_live]
    mov [rip + rpl_unmap_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + rpl_unmap_charge], rax
    mov edi, 1
    lea rsi, [rip + tt_report]
    call ext_prepare_retire_step
    test rax, rax
    js rpl_fail
    cmp qword ptr [rip + tt_report], 1
    ja rpl_fail
    cmp qword ptr [rip + tt_unmap_seen], 0
    jne .Lrpl_gc_after
    cmp qword ptr [rip + tt_unmap_calls], 0
    je .Lrpl_gc_next
    cmp qword ptr [rip + tt_unmap_calls], 1
    jne rpl_fail
    cmp qword ptr [rip + tt_report + 16], 1
    jne rpl_fail
    cmp qword ptr [rip + tt_report + 24], -5
    jne rpl_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + rpl_unmap_live], rax
    jne rpl_fail
    mov rax, [rip + prep_total_charge]
    cmp [rip + rpl_unmap_charge], rax
    jne rpl_fail
    mov rcx, [rip + tt_failed_map]
    mov rdx, [rip + tt_failed_header]
    cmp [rcx], rdx
    jne rpl_fail
    mov rdx, [rip + tt_failed_header + 8]
    cmp [rcx + 8], rdx
    jne rpl_fail
    # No further read of the failed mapping after retry may consume it.
    mov qword ptr [rip + tt_unmap_seen], 1
    mov qword ptr [rip + tt_unmap_fault], 0
    mov qword ptr [rip + tt_failed_map], 0
    mov qword ptr [rip + rpl_expected_diag], -5
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rpl_fail
    jmp .Lrpl_gc_continue
.Lrpl_gc_after:
    cmp qword ptr [rip + tt_unmap_calls], 1
    jne rpl_fail
    cmp qword ptr [rip + tt_report + 16], 0
    jne rpl_fail
.Lrpl_gc_next:
    test rax, rax
    jz .Lrpl_gc_done
.Lrpl_gc_continue:
    dec qword ptr [rip + rpl_unmap_budget]
    jnz .Lrpl_gc
    jmp rpl_fail
.Lrpl_gc_done:
    cmp qword ptr [rip + tt_unmap_seen], 1
    jne rpl_fail
    call tt_census
    EPILOGUE
rpl_quiet_check:
    PROLOGUE 16
    mov [rsp], rdi
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_session_channel_quiet_check
    cmp rax, [rsp]
    jne rpl_fail
    test rax, rax
    jnz 1f
    cmp rdx, r13
    jne rpl_fail
    jmp 2f
1:  test rdx, rdx
    jnz rpl_fail
2:  EPILOGUE
rpl_quiet_cases:
    PROLOGUE 32
    mov qword ptr [rip + rpl_stage], 204
    call af_new
    test rax, rax
    jz rpl_fail
    test rdx, rdx
    jnz rpl_fail
    mov [rip + rpl_quiet_other_ea], rax
    lea rdi, [rip + af_other]
    lea rsi, [rip + af_name]
    lea rdx, [rip + af_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz rpl_fail
    test rdx, rdx
    jnz rpl_fail
    mov [rip + rpl_quiet_other_hi], rax
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 77
    call rt_session_end
    test rax, rax
    jnz rpl_fail
    # Explicit collected-native structural model. Actual native case uses real take.
    mov qword ptr [r13 + EXT_keeper], 0
    mov dword ptr [r13 + EXT_pid], 0
    mov dword ptr [r13 + EXT_status], ES_STOPPED
    mov dword ptr [r13 + EXT_in], -1
    mov dword ptr [r13 + EXT_out], -1
    mov dword ptr [r13 + EXT_log], -1
    mov dword ptr [r13 + EXT_host_child_in], -1
    mov dword ptr [r13 + EXT_host_child_out], -1
    mov dword ptr [r13 + EXT_start_armed], 0
    mov dword ptr [r13 + EXT_wait_slot], 0
    mov dword ptr [r13 + EXT_restart], 0
    mov dword ptr [r13 + EXT_retiring], 0
    # Historical accepted1 must remain compatible with genuine quiet proof.
    mov dword ptr [r13 + EXT_startaccepted], 1
    xor edi, edi
    call rpl_quiet_check
    xor r14d, r14d
.Lrpl_quiet_fields:
    lea r15, [rip + rpl_quiet_fields]
    mov rax, r14
    shl rax, 5
    add r15, rax
    mov rcx, [r15]
    mov rax, [r13 + rcx]
    mov [rsp], rax
    mov rax, [r15 + 8]
    cmp qword ptr [r15 + 24], 4
    jne 1f
    mov [r13 + rcx], eax
    jmp 2f
1:  mov [r13 + rcx], rax
2:  mov rdi, [r15 + 16]
    call rpl_quiet_check
    mov rax, [rsp]
    mov rcx, [r15]
    cmp qword ptr [r15 + 24], 4
    jne 3f
    mov [r13 + rcx], eax
    jmp 4f
3:  mov [r13 + rcx], rax
4:  inc r14
    cmp r14, 9
    jb .Lrpl_quiet_fields
    mov r14, [r13 + EXT_activation_owner]
    mov rax, [rip + rpl_quiet_other_ea]
    mov [r13 + EXT_activation_owner], rax
    mov rdi, -116
    call rpl_quiet_check
    mov [r13 + EXT_activation_owner], r14
    mov r14, [r13 + EXT_identity_owner]
    mov rax, [rip + rpl_quiet_other_hi]
    mov [r13 + EXT_identity_owner], rax
    mov rdi, -116
    call rpl_quiet_check
    mov [r13 + EXT_identity_owner], r14
    mov r14, [rbx + RT_stableExtBase]
    add qword ptr [rbx + RT_stableExtBase], EXT_SIZE
    mov rdi, -116
    call rpl_quiet_check
    mov [rbx + RT_stableExtBase], r14
    mov qword ptr [rbx + RT_stableExtCount], 127
    mov rdi, -116
    call rpl_quiet_check
    mov qword ptr [rbx + RT_stableExtCount], 128
    # A detached host owner needs plan0 and the RT's independently retained refs.
    mov r14, [r13 + EXT_activation_owner]
    mov r15, [r13 + EXT_activation_plan]
    mov qword ptr [r13 + EXT_activation_owner], 0
    mov rdi, -116
    call rpl_quiet_check
    mov qword ptr [r13 + EXT_activation_plan], 0
    xor edi, edi
    call rpl_quiet_check
    mov rax, [r13 + EXT_identity_owner]
    mov [rsp + 8], rax
    mov qword ptr [r13 + EXT_identity_owner], 0
    xor edi, edi
    call rpl_quiet_check
    mov rax, [rsp + 8]
    mov [r13 + EXT_identity_owner], rax
    mov [r13 + EXT_activation_owner], r14
    mov [r13 + EXT_activation_plan], r15
    call rpl_restore
    mov rdi, [rip + rpl_quiet_other_ea]
    call ext_activation_owner_release
    call rpl_peer_consumed
    mov qword ptr [rip + rpl_quiet_other_ea], 0
    mov rdi, [rip + rpl_quiet_other_hi]
    call ext_host_identity_release
    call rpl_peer_consumed
    mov qword ptr [rip + rpl_quiet_other_hi], 0
    call tt_drain
    call tt_census
    EPILOGUE
.section .rodata
.p2align 3
rpl_quiet_fields:
    .quad EXT_host_cleanup_mask,1,-11,4
    .quad EXT_host_cleanup_mask,0x80000000,-11,4
    .quad EXT_keeper,444,-11,8
    .quad EXT_status,ES_RUNNING,-11,4
    .quad EXT_in,124,-11,4
    .quad EXT_host_child_in,0,-11,4
    .quad EXT_start_armed,1,-11,4
    .quad EXT_wait_slot,1,-11,4
    .quad EXT_restart,1,-11,4

.text
# Future builder COMMITTED transition is modeled explicitly; ticket/RO ownership is real.
# This does not claim to implement or exercise the future publication coordinator.
rpl_committed_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 205
    mov qword ptr [rip + tt_request + RTQ_ordinal], 17
    mov rax, [rip + rts_session]
    mov [rip + tt_request + RTQ_session], rax
    mov qword ptr [rip + tt_request + RTQ_id], 1
    mov qword ptr [rip + tt_request + RTQ_kind], RTQ_REGISTER
    lea rax, [rip + tt_key]
    mov [rip + tt_request + RTQ_key], rax
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
    mov qword ptr [rip + tt_request + RTQ_title], 0
    mov qword ptr [rip + tt_request + RTQ_titleLen], 0
    mov qword ptr [rip + tt_request + RTQ_keys], 0
    mov qword ptr [rip + tt_request + RTQ_keysLen], 0
    mov rdi, rbx
    lea rsi, [rip + tt_request]
    lea rdx, [rip + tt_out]
    call rt_ticket_create
    test rax, rax
    jnz rpl_fail
    cmp qword ptr [rip + tt_out + RTC_primary], 0
    jne rpl_fail
    mov r14, [rip + tt_out + RTC_owner]
    test r14, r14
    jz rpl_fail
    mov qword ptr [rip + tt_out + RTC_owner], 0
    mov rax, [r13 + EXT_owner]
    mov [rip + rpl_ro_config + ROC_owner], rax
    mov rax, [r13 + EXT_name]
    mov [rip + rpl_ro_config + ROC_name], rax
    mov [rip + rpl_ro_config + ROC_target], r13
    mov rax, [rip + rts_session]
    mov [rip + rpl_ro_config + ROC_session], rax
    lea rax, [rip + rpl_ro_key]
    mov [rip + rpl_ro_config + ROC_key], rax
    lea rax, [rip + rpl_ro_empty]
    mov [rip + rpl_ro_config + ROC_title], rax
    lea rdi, [rip + rpl_ro_config]
    call ext_runtime_new
    test rax, rax
    jz rpl_fail
    test rdx, rdx
    jnz rpl_fail
    mov [rip + rpl_committed_ro], rax
    # An observer retain proves ticket retirement releases its independent RO ref.
    mov rdi, rax
    call ext_runtime_retain
    test rax, rax
    jnz rpl_fail
    mov rax, [rip + rpl_committed_ro]
    mov [r14 + RTT_ro], rax
    mov qword ptr [r14 + RTT_acceptSequence], 1
    mov qword ptr [r14 + RTT_phase], RTT_COMMITTED
    call rpl_freeze
    mov [r12 + RTS_ticket], r14
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [r12 + RTS_ticket], 0
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_OP_CREDIT
    jz rpl_fail
    call tt_drain
    mov rax, [rip + rpl_committed_ro]
    cmp qword ptr [rax + RO_refs], 1
    jne rpl_fail
    mov rdi, rax
    call ext_runtime_release_deferred
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    mov qword ptr [rip + rpl_committed_ro], 0
    call tt_drain
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    test qword ptr [r12 + RTS_flags], RTSF_OP_CREDIT | RTSF_PARSER_PAUSED
    jnz rpl_fail
    call rpl_restore
    call tt_census
    EPILOGUE
.section .rodata
rpl_ro_key: .asciz "a"
rpl_ro_empty: .asciz ""
