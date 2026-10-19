.include "app/extruntime.inc"
.include "app/extruntimeadmit.inc"
.include "app/extruntimeremove.inc"
.data
rr_owner: .asciz "owner"
rr_name: .asciz "name"
rr_key: .asciz "a"
rr_title: .asciz "Runtime"
rr_ok: .ascii "ok 7\n"
rr_missing: .ascii "error 7 refused not a runtime command of this extension\n"
.bss
.p2align 3
rr_config: .zero ROC_SIZE
rr_request: .zero RTQ_SIZE
rr_stage: .quad 0
rr_row: .quad 0
rr_hold: .quad 0
rr_live: .quad 0
rr_charge: .quad 0
rr_mutation: .quad 0
rr_flags: .quad 0
rr_neighbor: .quad 0
rr_neighbor_save: .zero RT_ROW_SIZE
rr_drop_mode: .quad 0
rr_drop_calls: .quad 0
rr_drop_snapshot: .quad 0
rr_response_snapshot: .zero 56
rr_reply_snapshot: .zero 128
rr_work_watch: .quad 0
rr_free_saved: .quad 0
rr_cursor_saved: .quad 0
rr_next_saved: .quad 0
rr_large_map: .quad 0
rr_large_header: .zero 16
rr_large_live: .quad 0
rr_large_charge: .quad 0
rr_long_title: .zero 65537
.text
rr_cases:
    PROLOGUE
    mov rbx, [rip + rts_table]
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    mov rax, [rip + g_mem_live]
    mov [rip + rr_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + rr_charge], rax
    mov qword ptr [rip + rr_stage], 151
    # Real RO constructor and separate retained observer, no fabricated owner header.
    lea rax, [rip + rts_exts + 17 * EXT_SIZE]
    mov [rip + rr_config + ROC_target], rax
    mov rax, [rip + rts_session]
    mov [rip + rr_config + ROC_session], rax
    lea rax, [rip + rr_owner]
    mov [rip + rr_config + ROC_owner], rax
    lea rax, [rip + rr_name]
    mov [rip + rr_config + ROC_name], rax
    lea rax, [rip + rr_key]
    mov [rip + rr_config + ROC_key], rax
.if RR_TEST_LARGE == 1
    lea rdi, [rip + rr_long_title]
    mov esi, 116
    mov edx, 65536
    call memset
    lea rax, [rip + rr_long_title]
.else
    lea rax, [rip + rr_title]
.endif
    mov [rip + rr_config + ROC_title], rax
    lea rdi, [rip + rr_config]
    call ext_runtime_new
    test rax, rax
    jz rr_fail
    mov [rip + rr_hold], rax
    mov rdi, rax
    call ext_runtime_retain
    test rax, rax
    jnz rr_fail
    # Test publication-shaped seed transfers one real RO ref into the free physical row.
    mov rsi, [rbx + RT_freeHead]
    mov [rip + rr_row], rsi
    lea rax, [rsi - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r13, [rbx + rax + RT_rows]
    mov rax, [r13 + RTR_next]
    mov [rbx + RT_freeHead], rax
    mov rax, [rip + rr_hold]
    mov [r13 + RTR_ro], rax
    mov qword ptr [r13 + RTR_ordinal], 17
    mov rax, [rip + rts_session]
    mov [r13 + RTR_session], rax
    mov qword ptr [r13 + RTR_next], 0
    mov qword ptr [r13 + RTR_prev], 0
    mov qword ptr [r13 + RTR_acceptSequence], 1
    mov qword ptr [r13 + RTR_state], RTR_LIVE
    mov qword ptr [r13 + RTR_slotNext], 0
    mov [rbx + RT_liveHead], rsi
    mov [rbx + RT_liveTail], rsi
    mov qword ptr [rbx + RT_nlive], 1
    mov [r12 + RTS_liveHead], rsi
    mov qword ptr [r12 + RTS_nlive], 1
    mov rax, [rbx + RT_mutation]
    mov [rip + rr_mutation], rax
    mov rdi, rbx
    mov rdx, 17
    mov rcx, [rip + rts_session]
    mov r8d, 1
    call rt_row_owner_check
    test rax, rax
    jnz rr_fail
    # Same descriptor shape as captured protocol, detached from the mutable TABLE.
    mov qword ptr [rip + rr_request + RTQ_ordinal], 17
    mov rax, [rip + rts_session]
    mov [rip + rr_request + RTQ_session], rax
    mov qword ptr [rip + rr_request + RTQ_id], 7
    lea rax, [rip + rr_key]
    mov [rip + rr_request + RTQ_key], rax
    mov qword ptr [rip + rr_request + RTQ_keyLen], 1
    mov qword ptr [rip + rr_request + RTQ_kind], RTQ_UNREGISTER
    mov eax, [rip + rts_exts + 17 * EXT_SIZE + EXT_features]
    mov [rip + rr_flags], rax
    and dword ptr [rip + rts_exts + 17 * EXT_SIZE + EXT_features], ~FEAT_COMMANDS
    mov qword ptr [rip + rr_stage], 152
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rr_checked_remove
    cmp rax, -95
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r13 + RTR_state], RTR_LIVE
    jne rr_fail
    mov rax, [rip + rr_hold]
    cmp qword ptr [rax + RO_live], 1
    jne rr_fail
    call rr_clear_credit
    or dword ptr [rip + rts_exts + 17 * EXT_SIZE + EXT_features], FEAT_COMMANDS
    call rr_invalid_cases
.if RR_TEST_QUIESCING == 1
    mov qword ptr [rbx + RT_barrierState], RTB_QUIESCING
.endif
    mov qword ptr [rip + rr_stage], 155
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rr_checked_remove
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov rax, [rip + rr_hold]
    cmp qword ptr [rax + RO_live], 0
    jne rr_fail
    cmp qword ptr [rax + RO_refs], 2
    jne rr_fail
    cmp qword ptr [r13 + RTR_state], RTR_DEBT
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 1
    jne rr_fail
    cmp qword ptr [rbx + RT_nlive], 0
    jne rr_fail
    mov rax, [rip + rr_mutation]
    inc rax
    cmp [rbx + RT_mutation], rax
    jne rr_fail
    cmp qword ptr [r12 + RTS_replyLen], 5
    jne rr_fail
    lea rdi, [r12 + RTS_reply]
    lea rsi, [rip + rr_ok]
    mov edx, 5
    call memeq
    test eax, eax
    jz rr_fail
    mov qword ptr [rbx + RT_barrierState], 0
    lea rdi, [rip + rr_response_snapshot]
    lea rsi, [r12 + RTS_replyID]
    mov edx, 56
    call memcpy
    lea rdi, [rip + rr_reply_snapshot]
    lea rsi, [r12 + RTS_reply]
    mov edx, 128
    call memcpy
    call rr_debt_corrupt_cases
    call rr_debt_retry_cases
    call rr_compare_reply
    lea rdi, [r12 + RTS_replyID]
    lea rsi, [rip + rr_response_snapshot]
    mov edx, 56
    call memeq
    test eax, eax
    jz rr_fail
.if RR_TEST_DIAG == 1
    mov qword ptr [rip + rr_drop_mode], 2
.endif
    mov qword ptr [rip + rr_stage], 153
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 1
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r13 + RTR_state], RTR_FREE
    jne rr_fail
    cmp qword ptr [r13 + RTR_ro], 0
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 0
    jne rr_fail
    cmp qword ptr [rbx + RT_debtHead], 0
    jne rr_fail
    cmp qword ptr [rbx + RT_debtCursor], 0
    jne rr_fail
.if RR_TEST_DIAG == 1
    cmp qword ptr [rbx - RD_PO_BACK + RD_diagnostic], -5
    jne rr_fail
    mov rax, [rbx + PO_eo]
    cmp qword ptr [rax - RD_SIZE + RD_diagnostic], -5
    jne rr_fail
    cmp qword ptr [rip + prep_retire_first_diagnostic], -5
    jne rr_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz rr_fail
.endif
.if RR_TEST_LARGE == 1
    mov rax, [rip + rr_hold]
    sub rax, RD_SIZE + 16
    mov [rip + rr_large_map], rax
    mov rcx, [rax]
    mov [rip + rr_large_header], rcx
    mov rcx, [rax + 8]
    mov [rip + rr_large_header + 8], rcx
    mov rax, [rip + g_mem_live]
    mov [rip + rr_large_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + rr_large_charge], rax
.endif
    mov rdi, [rip + rr_hold]
    cmp qword ptr [rdi + RO_refs], 1
    jne rr_fail
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_hold], 0
.if RR_TEST_LARGE == 1
    call rr_large_retire_case
.else
    call tt_drain
.endif
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + rr_live]
    jne rr_fail
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + rr_charge]
    jne rr_fail
.if RR_TEST_ENDED == 1
    mov qword ptr [rip + rr_stage], 165
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 29
    call rt_session_end
    test rax, rax
    jnz rr_fail
    call rr_compare_reply
    lea rdi, [r12 + RTS_replyID]
    lea rsi, [rip + rr_response_snapshot]
    mov edx, 56
    call memeq
    test eax, eax
    jz rr_fail
    call rr_clear_credit
.else
    # This standalone row fixture only checks frozen frames, not delivery acceptance.
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    call rr_clear_credit
    mov qword ptr [rip + rr_stage], 154
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rr_checked_remove
    cmp rax, -2
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_replyLen], 56
    jne rr_fail
    lea rdi, [r12 + RTS_reply]
    lea rsi, [rip + rr_missing]
    mov edx, 56
    call memeq
    test eax, eax
    jz rr_fail
    call rr_clear_credit
.endif
    mov eax, [rip + rr_flags]
    mov [rip + rts_exts + 17 * EXT_SIZE + EXT_features], eax
    EPILOGUE
rr_clear_credit:
    mov rax, [r12 + RTS_flags]
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    je 1f
    and rax, RTSF_CHANNEL_BOUND
    jmp 2f
1:  and rax, ~(RTSF_OP_CREDIT | RTSF_ID_IN_USE | RTSF_REPLY_ATTEMPTED)
2:  mov [r12 + RTS_flags], rax
    mov qword ptr [r12 + RTS_replyID], 0
    mov qword ptr [r12 + RTS_outcome], 0
    mov qword ptr [r12 + RTS_delivery], 0
    mov qword ptr [r12 + RTS_replyLen], 0
    mov qword ptr [r12 + RTS_retryDue], 0
    mov qword ptr [r12 + RTS_backoff], 0
    mov qword ptr [r12 + RTS_stallDeadline], 0
    mov qword ptr [r12 + RTS_opKind], 0
    mov qword ptr [r12 + RTS_opStart], 0
    ret
rr_fail:
    mov rdi, [rip + rr_stage]
    SYS SYS_exit_group
    ud2

.text
rr_invalid_cases:
    PROLOGUE
    mov qword ptr [rip + rr_stage], 156
    mov rdi, rbx
    mov rsi, rbx
    call rr_checked_remove
    cmp rax, -22
    jne rr_fail
    test rdx, rdx
    jnz rr_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne rr_fail
    mov rdi, [rbx + RT_publicationRecord]
    lea rsi, [rip + rr_request]
    mov edx, RTQ_SIZE
    call memcpy
    mov rdi, rbx
    mov rsi, [rbx + RT_publicationRecord]
    call rr_checked_remove
    cmp rax, -22
    jne rr_fail
    test rdx, rdx
    jnz rr_fail
    cmp qword ptr [r12 + RTS_replyID], 0
    jne rr_fail
    mov rdi, [rbx + RT_publicationRecord]
    xor esi, esi
    mov edx, RTQ_SIZE
    call memset
    mov qword ptr [rip + rr_request + RTQ_kind], RTQ_REGISTER
    call rr_call
    mov rdi, -22
    call rr_error_unchanged
    mov qword ptr [rip + rr_request + RTQ_kind], RTQ_UNREGISTER
    mov qword ptr [rip + rr_request + RTQ_keyLen], 41
    call rr_call
    mov rdi, -7
    call rr_error_unchanged
    mov qword ptr [rip + rr_request + RTQ_keyLen], 1
    mov qword ptr [rbx + RT_barrierState], RTB_PUBLISHING
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [rbx + RT_barrierState], 99
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [rbx + RT_barrierState], 0
    mov qword ptr [rbx + RT_batchCount], 1
    mov qword ptr [rbx + RT_selected0], 17
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [rbx + RT_selected0], RT_SLOT_COUNT
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [rbx + RT_selected0], 0
    mov qword ptr [rbx + RT_batchCount], 0
    mov rax, [rip + rr_row]
    mov [r13 + RTR_slotNext], rax
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [r13 + RTR_slotNext], 0
    inc qword ptr [r13 + RTR_session]
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    dec qword ptr [r13 + RTR_session]
    # Corrupt reciprocal global neighbors may still alias the same other row.
    mov qword ptr [rip + rr_stage], 157
    mov rax, [rbx + RT_freeHead]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea rax, [rbx + rax + RT_rows]
    mov [rip + rr_neighbor], rax
    lea rdi, [rip + rr_neighbor_save]
    mov rsi, rax
    mov edx, RT_ROW_SIZE
    call memcpy
    mov r8, [rip + rr_neighbor]
    mov qword ptr [r8 + RTR_state], RTR_LIVE
    mov rax, [rip + rr_row]
    mov [r8 + RTR_next], rax
    mov [r8 + RTR_prev], rax
    mov rax, [rbx + RT_freeHead]
    mov [r13 + RTR_next], rax
    mov [r13 + RTR_prev], rax
    call rr_call
    mov rdi, -11
    call rr_error_unchanged
    mov qword ptr [r13 + RTR_next], 0
    mov qword ptr [r13 + RTR_prev], 0
    mov rdi, [rip + rr_neighbor]
    lea rsi, [rip + rr_neighbor_save]
    mov edx, RT_ROW_SIZE
    call memcpy
    cmp qword ptr [rbx + RT_nlive], 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_nlive], 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 0
    jne rr_fail
    EPILOGUE
rr_call:
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    jmp rr_checked_remove
rr_error_unchanged:
    PROLOGUE
    cmp rax, rdi
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    mov rax, [rip + rr_hold]
    cmp qword ptr [rax + RO_live], 1
    jne rr_fail
    cmp qword ptr [rax + RO_refs], 2
    jne rr_fail
    cmp qword ptr [r13 + RTR_state], RTR_LIVE
    jne rr_fail
    mov rax, [rip + rr_mutation]
    cmp [rbx + RT_mutation], rax
    jne rr_fail
    call rr_clear_credit
    EPILOGUE
rr_debt_retry_cases:
    PROLOGUE
    mov qword ptr [rip + rr_stage], 158
    mov qword ptr [rip + rr_drop_mode], 1
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r13 + RTR_debtDue], 116
    jne rr_fail
    cmp qword ptr [r13 + RTR_debtBackoff], 16
    jne rr_fail
    mov rax, [rip + rr_hold]
    cmp qword ptr [rax + RO_refs], 2
    jne rr_fail
    mov rax, [rip + rr_drop_calls]
    mov [rip + rr_drop_snapshot], rax
    mov rdi, rbx
    mov esi, 115
    mov edx, 16
    call rr_checked_debt
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp rcx, 116
    jne rr_fail
    mov rax, [rip + rr_drop_calls]
    cmp [rip + rr_drop_snapshot], rax
    jne rr_fail
    mov qword ptr [rip + rr_stage], 159
    mov qword ptr [rip + rr_drop_mode], 1
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 1
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    cmp qword ptr [r13 + RTR_debtDue], -1
    jne rr_fail
    cmp qword ptr [r13 + RTR_debtBackoff], 32
    jne rr_fail
    mov rax, [rip + rr_drop_calls]
    mov [rip + rr_drop_snapshot], rax
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 16
    call rr_checked_debt
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov rax, [rip + rr_drop_calls]
    cmp [rip + rr_drop_snapshot], rax
    jne rr_fail
    mov rdi, rbx
    mov rsi, [rip + rr_row]
    mov rdx, [rip + rts_session]
    inc rdx
    call rt_debt_wake
    cmp rax, -22
    jne rr_fail
    cmp qword ptr [r13 + RTR_debtDue], -1
    jne rr_fail
    mov rdi, rbx
    mov rsi, [rip + rr_row]
    mov rdx, [rip + rts_session]
    call rt_debt_wake
    test rax, rax
    jnz rr_fail
    cmp qword ptr [r13 + RTR_debtDue], 0
    jne rr_fail
    EPILOGUE
FN ext_runtime_release_deferred
    inc qword ptr [rip + rr_drop_calls]
    cmp qword ptr [rip + rr_drop_mode], 2
    je 1f
    cmp qword ptr [rip + rr_drop_mode], 1
    jne rr_real_ro_release
    mov qword ptr [rip + rr_drop_mode], 0
    mov rax, -5
    xor edx, edx
    ret
1:  PROLOGUE
    mov qword ptr [rip + rr_drop_mode], 0
    call rr_real_ro_release
    cmp rdx, 1
    jne rr_fail
    mov rax, -5
    EPILOGUE

rr_large_retire_case:
    PROLOGUE
    mov qword ptr [rip + rr_stage], 160
    mov qword ptr [rip + tt_unmap_fault], 1
    mov edi, 1
    lea rsi, [rip + tt_report]
    call ext_prepare_retire_step
    cmp qword ptr [rip + tt_report], 1
    jne rr_fail
    cmp qword ptr [rip + tt_report + 16], 1
    jne rr_fail
    cmp qword ptr [rip + tt_report + 24], -5
    jne rr_fail
    mov rax, [rip + rr_large_map]
    cmp [rip + tt_failed_map], rax
    jne rr_fail
    mov rcx, [rip + rr_large_header]
    cmp [rax], rcx
    jne rr_fail
    mov rcx, [rip + rr_large_header + 8]
    cmp [rax + 8], rcx
    jne rr_fail
    mov rax, [rip + rr_large_live]
    cmp [rip + g_mem_live], rax
    jne rr_fail
    mov rax, [rip + rr_large_charge]
    cmp [rip + prep_total_charge], rax
    jne rr_fail
    mov qword ptr [rip + tt_unmap_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rr_fail
    mov r12d, 64
1:  mov edi, 1
    lea rsi, [rip + tt_report]
    call ext_prepare_retire_step
    test rax, rax
    jz 2f
    dec r12
    jnz 1b
    jmp rr_fail
2:  call ext_prepare_retire_ack
    test rax, rax
    jnz rr_fail
    EPILOGUE

rr_compare_reply:
    PROLOGUE
    lea rdi, [r12 + RTS_reply]
    lea rsi, [rip + rr_reply_snapshot]
    mov edx, 128
    call memeq
    test eax, eax
    jz rr_fail
    EPILOGUE
rr_checked_remove:
    PROLOGUE
    mov qword ptr [rip + rr_work_watch], 1
    call rt_remove
    mov qword ptr [rip + rr_work_watch], 0
    EPILOGUE
rr_checked_revoke:
    PROLOGUE
    mov qword ptr [rip + rr_work_watch], 1
    call rt_rows_revoke_step
    mov qword ptr [rip + rr_work_watch], 0
    EPILOGUE
rr_checked_debt:
    PROLOGUE
    mov qword ptr [rip + rr_work_watch], 1
    call rt_debt_step
    mov qword ptr [rip + rr_work_watch], 0
    EPILOGUE
FN ext_stop
    cmp qword ptr [rip + rr_work_watch], 0
    je rr_real_ext_stop
    mov qword ptr [rip + rr_stage], 171
    jmp rr_fail
rr_debt_corrupt_cases:
    PROLOGUE
    mov qword ptr [rip + rr_stage], 167
    mov rax, [rbx + RT_freeHead]
    mov [rip + rr_free_saved], rax
    mov rax, [rbx + RT_debtCursor]
    mov [rip + rr_cursor_saved], rax
    mov rax, [rip + rr_row]
    mov [r13 + RTR_next], rax
    call rr_debt_bad
    mov qword ptr [r13 + RTR_next], 0
    mov [r13 + RTR_prev], rax
    call rr_debt_bad
    mov qword ptr [r13 + RTR_prev], 0
    mov qword ptr [rbx + RT_debtCursor], 0
    call rr_debt_bad
    mov qword ptr [rbx + RT_debtCursor], RT_ROW_COUNT + 1
    call rr_debt_bad
    mov rax, [rip + rr_free_saved]
    mov [rbx + RT_debtCursor], rax
    call rr_debt_bad
    mov rax, [rip + rr_cursor_saved]
    mov [rbx + RT_debtCursor], rax
    mov rax, [rip + rr_row]
    mov [rbx + RT_freeHead], rax
    call rr_debt_bad
    mov rax, [rip + rr_free_saved]
    mov [rbx + RT_freeHead], rax
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r15, [rbx + rax + RT_rows]
    mov rax, [r15 + RTR_next]
    mov [rip + rr_next_saved], rax
    mov rax, [rip + rr_row]
    mov [r15 + RTR_next], rax
    call rr_debt_bad
    mov rax, [rip + rr_next_saved]
    mov [r15 + RTR_next], rax
    EPILOGUE
rr_debt_bad:
    PROLOGUE
    mov rax, [rip + rr_drop_calls]
    mov [rip + rr_drop_snapshot], rax
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rr_checked_debt
    cmp rax, -71
    jne rr_fail
    test rdx, rdx
    jnz rr_fail
    mov rax, [rip + rr_drop_calls]
    cmp [rip + rr_drop_snapshot], rax
    jne rr_fail
    mov rax, [rip + rr_hold]
    cmp qword ptr [rax + RO_refs], 2
    jne rr_fail
    cmp qword ptr [r13 + RTR_state], RTR_DEBT
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 1
    jne rr_fail
    mov rax, [rip + rr_row]
    EPILOGUE
