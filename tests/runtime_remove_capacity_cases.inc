# Sixty-four real owned suppliers. No spawned-process/collection claim is made here.
.data
rr_many_key: .asciz "aa"
rr_many_missing: .asciz "zz"
rr_many_busy: .ascii "error 7 busy runtime request cancelled\n"
.bss
.p2align 3
rr_many_rows: .zero 64 * 8
rr_many_free: .quad 0
rr_many_reply: .zero 128
.text
rr_many_cases:
    PROLOGUE 32
    mov rbx, [rip + rts_table]
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    or dword ptr [rip + rts_exts + 17 * EXT_SIZE + EXT_features], FEAT_COMMANDS
    lea rax, [rip + rr_many_key]
    mov [rip + rr_config + ROC_key], rax
    mov [rip + rr_request + RTQ_key], rax
    mov qword ptr [rip + rr_request + RTQ_keyLen], 2
    mov qword ptr [rip + rr_stage], 161
    xor r15d, r15d
.Lrrm_seed:
    mov rdi, r15
    call rr_many_make_key
    lea rdi, [rip + rr_config]
    call ext_runtime_new
    test rax, rax
    jz rr_fail
    mov [rsp], rax
    mov r13, [rbx + RT_freeHead]
    lea rax, [r13 - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r14, [rbx + rax + RT_rows]
    mov rax, [r14 + RTR_next]
    mov [rbx + RT_freeHead], rax
    lea rax, [rip + rr_many_rows]
    mov [rax + r15*8], r13
    mov rax, [rsp]
    mov [r14 + RTR_ro], rax
    mov qword ptr [r14 + RTR_ordinal], 17
    mov rax, [rip + rts_session]
    mov [r14 + RTR_session], rax
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
    lea rax, [r15 + 100]
    mov [r14 + RTR_acceptSequence], rax
    mov qword ptr [r14 + RTR_state], RTR_LIVE
    mov rax, [r12 + RTS_liveHead]
    mov [r14 + RTR_slotNext], rax
    mov [r12 + RTS_liveHead], r13
    inc qword ptr [r12 + RTS_nlive]
    inc qword ptr [rbx + RT_nlive]
    inc r15
    cmp r15, 64
    jb .Lrrm_seed
    cmp qword ptr [r12 + RTS_nlive], 64
    jne rr_fail
    mov rax, [rbx + RT_freeHead]
    mov [rip + rr_many_free], rax
    call rr_many_duplicate_case
    # Missing key inspects the complete own chain and cannot remove unrelated names.
    lea rax, [rip + rr_many_missing]
    mov [rip + rr_request + RTQ_key], rax
    call rr_call
    cmp rax, -2
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_nlive], 64
    jne rr_fail
    call rr_clear_credit
    lea rax, [rip + rr_many_key]
    mov [rip + rr_request + RTQ_key], rax
.if RR_TEST_SATURATION == 1
    mov qword ptr [rip + rr_stage], 164
    mov rax, 0x7fffffffffffffff
    mov [rbx + RT_mutation], rax
    xor edi, edi
    call rr_many_make_key
    call rr_call
    cmp rax, -11
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    test qword ptr [rbx + RT_flags], RTF_CLOSED
    jz rr_fail
    cmp qword ptr [r12 + RTS_grantSession], 0
    jne rr_fail
    cmp qword ptr [r12 + RTS_state], RTS_DRAINING
    jne rr_fail
    cmp qword ptr [r12 + RTS_nlive], 64
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 0
    jne rr_fail
    cmp [rip + g_activeRT], rbx
    jne rr_fail
    cmp qword ptr [rip + g_closingRT], 0
    jne rr_fail
    mov rax, 0x7fffffffffffffff
    cmp [rbx + RT_mutation], rax
    jne rr_fail
    cmp qword ptr [r12 + RTS_replyLen], 39
    jne rr_fail
    lea rdi, [r12 + RTS_reply]
    lea rsi, [rip + rr_many_busy]
    mov edx, 39
    call memeq
    test eax, eax
    jz rr_fail
    lea rdi, [rip + rr_many_reply]
    lea rsi, [r12 + RTS_reply]
    mov edx, 128
    call memcpy
    jmp .Lrrm_lifecycle
.endif
    # Hold a separate observer for the oldest command across logical removal/debt.
    mov rax, [rip + rr_many_rows]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    mov rdi, [rbx + rax + RT_rows + RTR_ro]
    mov [rip + rr_hold], rdi
    call ext_runtime_retain
    test rax, rax
    jnz rr_fail
    xor edi, edi
    call rr_many_remove
    mov edi, 31
    call rr_many_remove
    mov edi, 63
    call rr_many_remove
    cmp qword ptr [r12 + RTS_nlive], 61
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 3
    jne rr_fail
    mov rax, [rip + rr_many_free]
    cmp [rbx + RT_freeHead], rax
    jne rr_fail
    # First, middle and last global removals preserve both reciprocal directions.
    mov rax, [rip + rr_many_rows + 8]
    cmp [rbx + RT_liveHead], rax
    jne rr_fail
    mov rax, [rip + rr_many_rows + 62 * 8]
    cmp [rbx + RT_liveTail], rax
    jne rr_fail
    mov rax, [rip + rr_many_rows + 30 * 8]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    mov rcx, [rip + rr_many_rows + 32 * 8]
    cmp [rbx + rax + RT_rows + RTR_next], rcx
    jne rr_fail
    dec rcx
    imul rcx, rcx, RT_ROW_SIZE
    mov rax, [rip + rr_many_rows + 30 * 8]
    cmp [rbx + rcx + RT_rows + RTR_prev], rax
    jne rr_fail
    cmp [rbx + rcx + RT_rows + RTR_slotNext], rax
    jne rr_fail
    # A missing reciprocal DEBT link rejects before a checked reference call.
    mov qword ptr [rip + rr_stage], 166
    mov rax, [rip + rr_many_rows + 31 * 8]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r14, [rbx + rax + RT_rows]
    mov rax, [r14 + RTR_prev]
    mov [rsp + 16], rax
    mov rax, [rbx + RT_debtCursor]
    mov [rsp + 24], rax
    mov qword ptr [r14 + RTR_prev], 0
    mov rax, [rbx + RT_debtHead]
    mov [rbx + RT_debtCursor], rax
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
    mov rax, [rsp + 16]
    mov [r14 + RTR_prev], rax
    mov rax, [rsp + 24]
    mov [rbx + RT_debtCursor], rax
    # Actual refused reference drop parks one debt without suppressing its peers.
    mov qword ptr [rip + rr_stage], 162
    mov qword ptr [rip + rr_drop_mode], 1
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 1
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    mov rax, [rip + rr_drop_calls]
    mov [rip + rr_drop_snapshot], rax
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 16
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    cmp rdx, 3
    jb rr_fail
    cmp rdx, 16
    ja rr_fail
    mov rax, [rip + rr_drop_calls]
    sub rax, [rip + rr_drop_snapshot]
    cmp rax, 2
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 1
    jne rr_fail
    mov rdi, [rip + rr_hold]
    cmp qword ptr [rdi + RO_live], 0
    jne rr_fail
    cmp qword ptr [rdi + RO_refs], 2
    jne rr_fail
    mov rdi, rbx
    mov rsi, [rip + rr_many_rows]
    mov rdx, [rip + rts_session]
    call rt_debt_wake
    test rax, rax
    jnz rr_fail
    mov rdi, rbx
    mov rsi, 0x7fffffffffffffff
    mov edx, 1
    call rr_checked_debt
    cmp rax, 1
    jne rr_fail
    mov rdi, [rip + rr_hold]
    cmp qword ptr [rdi + RO_refs], 1
    jne rr_fail
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_hold], 0
.Lrrm_lifecycle:
    # Lifecycle revocation requires no request credit. Each budget1 call visits one slot.
    mov qword ptr [rip + rr_stage], 163
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 29
    call rt_session_end
    test rax, rax
    jnz rr_fail
    mov qword ptr [rbx + RT_replyCursor], 31
    mov qword ptr [rbx + RT_cleanupCursor], 47
    mov qword ptr [rbx + RT_nativeCursor], 63
    mov qword ptr [rbx + RT_revokeCursor], 79
    mov r15d, 8192
.Lrrm_revoke:
    mov rax, [r12 + RTS_nlive]
    mov [rsp + 8], rax
    mov rax, [rbx + RT_revokeCursor]
    inc rax
    and eax, 127
    mov [rsp + 16], rax
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rr_checked_revoke
    test rax, rax
    js rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_replyCursor], 31
    jne rr_fail
    cmp qword ptr [rbx + RT_cleanupCursor], 47
    jne rr_fail
    cmp qword ptr [rbx + RT_nativeCursor], 63
    jne rr_fail
    mov rax, [rsp + 16]
    cmp [rbx + RT_revokeCursor], rax
    jne rr_fail
    mov rax, [rsp + 8]
    sub rax, [r12 + RTS_nlive]
    cmp rax, 1
    ja rr_fail
    cmp qword ptr [r12 + RTS_nlive], 0
    je 3f
    dec r15
    jnz .Lrrm_revoke
    jmp rr_fail
3:  mov rax, [rbx + RT_nlive]
    or rax, [rbx + RT_liveHead]
    or rax, [rbx + RT_liveTail]
    or rax, [r12 + RTS_liveHead]
    jnz rr_fail
.if RR_TEST_SATURATION == 1
    cmp qword ptr [r12 + RTS_ndebt], 64
.else
    cmp qword ptr [r12 + RTS_ndebt], 61
.endif
    jne rr_fail
    mov r15d, 8
.Lrrm_drain:
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rr_checked_debt
    test rax, rax
    js rr_fail
    cmp rdx, 16
    ja rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 0
    je 4f
    dec r15
    jnz .Lrrm_drain
    jmp rr_fail
4:  call tt_drain
    mov rax, [rip + rr_live]
    cmp [rip + g_mem_live], rax
    jne rr_fail
    mov rax, [rip + rr_charge]
    cmp [rip + prep_total_charge], rax
    jne rr_fail
.if RR_TEST_SATURATION == 1
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne rr_fail
    cmp qword ptr [r12 + RTS_outcome], RTRSP_BUSY + 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_replyID], 7
    jne rr_fail
    lea rdi, [r12 + RTS_reply]
    lea rsi, [rip + rr_many_reply]
    mov edx, 128
    call memeq
    test eax, eax
    jz rr_fail
    call rr_clear_credit
.endif
    mov eax, [rip + rr_flags]
    mov [rip + rts_exts + 17 * EXT_SIZE + EXT_features], eax
    EPILOGUE
rr_many_make_key:
    mov rax, rdi
    xor edx, edx
    mov ecx, 26
    div rcx
    add al, 'a'
    add dl, 'a'
    mov [rip + rr_many_key], al
    mov [rip + rr_many_key + 1], dl
    ret
rr_many_remove:
    PROLOGUE
    call rr_many_make_key
    call rr_call
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [r12 + RTS_replyLen], 5
    jne rr_fail
    call rr_clear_credit
    EPILOGUE

.bss
.p2align 3
rr_dup_old: .quad 0
rr_dup_new: .quad 0
rr_dup_row: .quad 0
rr_dup_mutation: .quad 0
rr_dup_authority: .quad 0
rr_dup_live: .quad 0
rr_dup_charge: .quad 0
rr_dup_rows: .zero 64 * RT_ROW_SIZE
.text
rr_many_duplicate_case:
    PROLOGUE
    mov qword ptr [rip + rr_stage], 182
    mov rax, [rip + g_mem_live]
    mov [rip + rr_dup_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + rr_dup_charge], rax
    xor edi, edi
    call rr_many_make_key
    lea rdi, [rip + rr_config]
    call ext_runtime_new
    test rax, rax
    jz rr_fail
    mov [rip + rr_dup_new], rax
    # An independent factory-produced immutable RO duplicates key aa at chain position31.
    mov rax, [rip + rr_many_rows + 31 * 8]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea rax, [rbx + rax + RT_rows]
    mov [rip + rr_dup_row], rax
    mov rcx, [rax + RTR_ro]
    mov [rip + rr_dup_old], rcx
    mov rcx, [rip + rr_dup_new]
    mov [rax + RTR_ro], rcx
    xor r15d, r15d
1:  lea rax, [rip + rr_many_rows]
    mov rax, [rax + r15*8]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea rsi, [rbx + rax + RT_rows]
    imul rax, r15, RT_ROW_SIZE
    lea rdi, [rip + rr_dup_rows]
    add rdi, rax
    mov edx, RT_ROW_SIZE
    call memcpy
    inc r15
    cmp r15, 64
    jb 1b
    mov rax, [rbx + RT_mutation]
    mov [rip + rr_dup_mutation], rax
    mov rax, [rip + rt_authority_epoch]
    mov [rip + rr_dup_authority], rax
    call rr_call
    cmp rax, -11
    jne rr_fail
    cmp rdx, 1
    jne rr_fail
    cmp qword ptr [rbx + RT_nlive], 64
    jne rr_fail
    cmp qword ptr [r12 + RTS_nlive], 64
    jne rr_fail
    cmp qword ptr [r12 + RTS_ndebt], 0
    jne rr_fail
    cmp qword ptr [rbx + RT_debtHead], 0
    jne rr_fail
    mov rax, [rip + rr_many_free]
    cmp [rbx + RT_freeHead], rax
    jne rr_fail
    mov rax, [rip + rr_dup_mutation]
    cmp [rbx + RT_mutation], rax
    jne rr_fail
    mov rax, [rip + rr_dup_authority]
    cmp [rip + rt_authority_epoch], rax
    jne rr_fail
    xor r15d, r15d
2:  lea rax, [rip + rr_many_rows]
    mov rax, [rax + r15*8]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea rdi, [rbx + rax + RT_rows]
    mov rax, [rdi + RTR_ro]
    cmp qword ptr [rax + RO_live], 1
    jne rr_fail
    cmp qword ptr [rax + RO_refs], 1
    jne rr_fail
    imul rax, r15, RT_ROW_SIZE
    lea rsi, [rip + rr_dup_rows]
    add rsi, rax
    mov edx, RT_ROW_SIZE
    call memeq
    test eax, eax
    jz rr_fail
    inc r15
    cmp r15, 64
    jb 2b
    mov rax, [rip + rr_dup_old]
    cmp qword ptr [rax + RO_live], 1
    jne rr_fail
    cmp qword ptr [rax + RO_refs], 1
    jne rr_fail
    call rr_clear_credit
    mov rax, [rip + rr_dup_row]
    mov rcx, [rip + rr_dup_old]
    mov [rax + RTR_ro], rcx
    mov qword ptr [rip + rr_dup_old], 0
    mov rdi, [rip + rr_dup_new]
    call ext_runtime_release_deferred
    test rax, rax
    jnz rr_fail
    cmp rdx, 1
    jne rr_fail
    mov qword ptr [rip + rr_dup_new], 0
    call tt_drain
    mov rax, [rip + rr_dup_live]
    cmp [rip + g_mem_live], rax
    jne rr_fail
    mov rax, [rip + rr_dup_charge]
    cmp [rip + prep_total_charge], rax
    jne rr_fail
    EPILOGUE
