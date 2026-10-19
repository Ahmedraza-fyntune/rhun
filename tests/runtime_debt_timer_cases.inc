# Producer invalidation uses real RO owners. Raw census cases below deliberately
# populate only physical scalar states and poison unused pointers, then restore
# the complete original row image before any owning cleanup.
.bss
.p2align 3
dts_saved_rows: .zero 8192 * 64
dts_header: .zero 575488
dts_expected_rows: .zero 8192 * 64
dts_now: .quad 0
dts_aba_row: .zero 64
dts_total: .quad 0
dts_budget: .quad 0
dts_cursors: .zero 40
.text
dts_fail:
    mov edi, 190
    SYS SYS_exit_group
    ud2
# Force and complete a stable scan under the same allocation/native-stop tripwires.
dts_prime:
    PROLOGUE
    mov rdi, [rip + rts_table]
    call rt_debt_scan_invalidate
    call dts_complete
    EPILOGUE
# Complete an existing or invalidated pass. Every cursor and result is checked.
dts_complete:
    PROLOGUE 16
    mov r14d, 512
1:  mov rax, [rbx + RT_debtScanCursor]
    cmp qword ptr [rbx + RT_debtScanActive], 0
    je 2f
    cmp qword ptr [rbx + RT_debtScanDirty], 0
    je 3f
2:  xor eax, eax
3:  add rax, 16
    mov [rsp], rax
    mov rdi, rbx
    mov esi, 16
    call dts_step
    cmp rdx, 16
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    mov rdx, [rsp]
    cmp [rbx + RT_debtScanCursor], rdx
    jne dts_fail
    cmp rdx, 8192
    je 4f
    test rax, rax
    jnz dts_fail
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    or rax, rdx
    or rax, rcx
    jnz dts_fail
    dec r14
    jnz 1b
    jmp dts_fail
4:  cmp rax, 1
    jne dts_fail
    EPILOGUE
dts_prepare_producer:
.if DTS_INTERLEAVE == 0
    jmp dts_prime
.else
    jmp dts_partial
.endif
dts_partial:
    PROLOGUE
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov r14d, 1
.if DTS_INTERLEAVE == 2
    mov r14d, 257
.endif
    xor r15d, r15d
1:  mov rdi, rbx
    mov esi, 16
    call dts_step
    test rax, rax
    jnz dts_fail
    cmp rdx, 16
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    add r15, 16
    cmp [rbx + RT_debtScanCursor], r15
    jne dts_fail
    dec r14
    jnz 1b
    EPILOGUE
# Preserve producer return values, settle its real partial scan, inspect exact due.
dts_finish_real:
    PROLOGUE 32
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
.if DTS_INTERLEAVE != 0
    call dts_complete
.else
    cmp qword ptr [rbx + RT_debtScanValid], 1
    je 1f
    call dts_complete
1:
.endif
    mov rax, [rip + rr_row]
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r15, [rbx + rax + RT_rows]
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    cmp rdx, 1
    jne dts_fail
    cmp qword ptr [r15 + RTR_state], RTR_DEBT
    jne 2f
    mov r8, [r15 + RTR_debtDue]
    cmp r8, -1
    je 2f
    cmp r8, 100
    jbe 3f
    cmp rax, r8
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    jmp 4f
2:  or rax, rcx
    jnz dts_fail
    jmp 4f
3:  test rax, rax
    jnz dts_fail
    cmp rcx, 1
    jne dts_fail
4:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE
dts_step:
    PROLOGUE
    mov qword ptr [rip + rr_work_watch], 1
    call rt_debt_scan_step
    mov qword ptr [rip + rr_work_watch], 0
    EPILOGUE
dts_timeout:
    PROLOGUE
    mov qword ptr [rip + rr_work_watch], 1
    call rt_debt_timeout
    mov qword ptr [rip + rr_work_watch], 0
    EPILOGUE
dts_wake:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    call dts_prepare_producer
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    call rt_debt_wake
    mov [rsp + 24], rax
    test rax, rax
    setz al
    movzx eax, al
    cmp [rbx + RT_debtScanDirty], rax
    jne dts_fail
.if DTS_INTERLEAVE == 0
    xor eax, 1
.else
    xor eax, eax
.endif
    cmp [rbx + RT_debtScanValid], rax
    jne dts_fail
    call dts_finish_real
    mov rax, [rsp + 24]
    EPILOGUE
dts_cases:
    PROLOGUE 32
    mov rbx, [rip + rts_table]
.if DTS_TEST_CLOSED == 0
    call dts_actual_aba
.endif
.if DTS_TEST_CLOSED == 1
    mov rdi, rbx
    call rt_table_close
    test rax, rax
    jnz dts_fail
.endif
    lea rdi, [rip + dts_saved_rows]
    lea rsi, [rbx + RT_rows]
    mov edx, 524288
    call memcpy
    # All scheduler cursors remain independent of this physical scan.
    mov qword ptr [rbx + RT_replyCursor], 3
    mov qword ptr [rbx + RT_cleanupCursor], 5
    mov qword ptr [rbx + RT_debtCursor], 7
    mov qword ptr [rbx + RT_nativeCursor], 11
    mov qword ptr [rbx + RT_revokeCursor], 13
    # Every unused pointer is unreadable. Only resident scalar state/due is input.
    xor r14d, r14d
1:  imul rax, r14, RT_ROW_SIZE
    lea rdx, [rbx + rax + RT_rows]
    mov qword ptr [rdx + RTR_state], RTR_DEBT
    mov qword ptr [rdx + RTR_debtDue], -1
    mov qword ptr [rdx + RTR_ro], -4096
    mov qword ptr [rdx + RTR_next], -4096
    mov qword ptr [rdx + RTR_prev], -4096
    inc r14
    cmp r14, 8192
    jb 1b
    lea rdi, [rip + dts_expected_rows]
    lea rsi, [rbx + RT_rows]
    mov edx, 524288
    call memcpy
    call dts_prime
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rdx, 1
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    # The last physical row is mandatory, including at maximum representable due.
    mov rax, 0x7fffffffffffffff
    mov [rbx + RT_rows + 8191 * RT_ROW_SIZE + RTR_debtDue], rax
    mov [rip + dts_expected_rows + 8191 * RT_ROW_SIZE + RTR_debtDue], rax
    call dts_prime
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    mov r8, 0x7fffffffffffffff
    cmp rax, r8
    jne dts_fail
    cmp rdx, 1
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    mov rdi, rbx
    mov rsi, r8
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rcx, 1
    jne dts_fail
    # Positive minimum and time advancing beyond it use the same absolute cache.
    mov qword ptr [rbx + RT_rows + 4096 * RT_ROW_SIZE + RTR_debtDue], 50
    mov qword ptr [rip + dts_expected_rows + 4096 * RT_ROW_SIZE + RTR_debtDue], 50
    call dts_prime
    mov rdi, rbx
    mov esi, 49
    call dts_timeout
    cmp rax, 50
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    mov rdi, rbx
    mov esi, 51
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rcx, 1
    jne dts_fail
    mov qword ptr [rbx + RT_rows + RTR_debtDue], 0
    mov qword ptr [rip + dts_expected_rows + RTR_debtDue], 0
    call dts_prime
    mov rdi, rbx
    xor esi, esi
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rcx, 1
    jne dts_fail
    # Dirty is sticky through two mutations that return bytes to their old values.
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov rdi, rbx
    mov esi, 16
    call dts_step
    test rax, rax
    jnz dts_fail
    cmp rdx, 16
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    cmp qword ptr [rbx + RT_debtScanCursor], 16
    jne dts_fail
    mov qword ptr [rbx + RT_rows + RTR_debtDue], 12
    mov qword ptr [rip + dts_expected_rows + RTR_debtDue], 12
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov qword ptr [rbx + RT_rows + RTR_debtDue], 0
    mov qword ptr [rip + dts_expected_rows + RTR_debtDue], 0
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov rdi, rbx
    mov esi, 16
    call dts_step
    test rax, rax
    jnz dts_fail
    cmp rdx, 16
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    cmp qword ptr [rbx + RT_debtScanCursor], 16
    jne dts_fail
    mov rdi, rbx
    mov esi, 10
    call dts_timeout
    or rax, rdx
    or rax, rcx
    jnz dts_fail
    call dts_complete
    mov rdi, rbx
    mov esi, 10
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rdx, 1
    jne dts_fail
    cmp rcx, 1
    jne dts_fail
    mov qword ptr [rbx + RT_rows + RTR_debtDue], -1
    mov qword ptr [rip + dts_expected_rows + RTR_debtDue], -1
    # Budget1 still completes exactly8192 visits; no borrowed pointer survives.
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov r15d, 8192
    xor r14d, r14d
    mov qword ptr [rip + dts_now], 49
2:  mov rdi, rbx
    mov esi, 1
    call dts_step
    cmp rdx, 1
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    inc r14
    cmp [rbx + RT_debtScanCursor], r14
    jne dts_fail
    cmp r14, 4096
    jne 3f
    mov qword ptr [rip + dts_now], 51
3:  dec r15
    jz 4f
    test rax, rax
    jnz dts_fail
    mov rdi, rbx
    mov rsi, [rip + dts_now]
    call dts_timeout
    or rax, rdx
    or rax, rcx
    jnz dts_fail
    jmp 2b
4:  cmp rax, 1
    jne dts_fail
    mov rdi, rbx
    mov esi, 49
    call dts_timeout
    cmp rax, 50
    jne dts_fail
    cmp rdx, 1
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    mov rdi, rbx
    mov rsi, [rip + dts_now]
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rdx, 1
    jne dts_fail
    cmp rcx, 1
    jne dts_fail
    cmp qword ptr [rbx + RT_replyCursor], 3
    jne dts_fail
    cmp qword ptr [rbx + RT_cleanupCursor], 5
    jne dts_fail
    cmp qword ptr [rbx + RT_debtCursor], 7
    jne dts_fail
    cmp qword ptr [rbx + RT_nativeCursor], 11
    jne dts_fail
    cmp qword ptr [rbx + RT_revokeCursor], 13
    jne dts_fail
    # Malformed scalar state fails before any owner traversal; cache stays invalid.
    mov qword ptr [rbx + RT_rows + RTR_state], 4
    mov rdi, rbx
    call rt_debt_scan_invalidate
    mov rdi, rbx
    mov esi, 16
    call dts_step
    cmp rax, -71
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanValid], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanActive], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanDirty], 1
    jne dts_fail
    cmp rdx, 1
    jne dts_fail
    mov qword ptr [rbx + RT_rows + RTR_state], RTR_DEBT
    mov qword ptr [rbx + RT_rows + RTR_debtDue], -2
    mov rdi, rbx
    mov esi, 16
    call dts_step
    cmp rax, -71
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanValid], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanActive], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanDirty], 1
    jne dts_fail
    mov qword ptr [rbx + RT_rows + RTR_debtDue], -1
    mov qword ptr [rip + dts_expected_rows + RTR_debtDue], -1
    # Compare every word, including ordinal/session/backoff/due, before restoring.
    lea rdi, [rbx + RT_rows]
    lea rsi, [rip + dts_expected_rows]
    mov edx, 524288
    call memeq
    test eax, eax
    jz dts_fail
    # Restore physical ownership/list state before ordinary table/native teardown.
    lea rdi, [rbx + RT_rows]
    lea rsi, [rip + dts_saved_rows]
    mov edx, 524288
    call memcpy
    mov qword ptr [rbx + RT_debtCursor], 0
    call dts_prime
    mov rdi, rbx
    mov esi, 50
    call dts_timeout
    test rax, rax
    jnz dts_fail
    cmp rdx, 1
    jne dts_fail
    test rcx, rcx
    jnz dts_fail
    call dts_invalid_cases
    EPILOGUE

.section .rodata
dts_bad_fields:
    .quad RT_debtScanDirty,2
    .quad RT_debtScanActive,2
    .quad RT_debtScanValid,2
    .quad RT_debtScanHasDue,2
    .quad RT_debtScanCursor,8193
    .quad RT_debtScanDirty,1
    .quad RT_debtScanActive,1
    .quad RT_debtScanCursor,0
    .quad PO_ready,0
    .quad RT_flags,RTF_MEMORY_ONLY
    .quad RT_flags,RTF_BUILDING
dts_bad_fields_end:
.text
# All malformed input calls preserve the exact fault-injected48byte cache.
dts_invalid_cases:
    PROLOGUE 32
    lea r14, [rip + dts_bad_fields]
1:  mov r15, [r14]
    mov rax, [rbx + r15]
    mov [rsp], rax
    mov rax, [r14 + 8]
    mov [rbx + r15], rax
    call dts_save_header
    mov rdi, rbx
    mov esi, 16
    call dts_step
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov rax, [rsp]
    mov [rbx + r15], rax
    add r14, 16
    lea rax, [rip + dts_bad_fields_end]
    cmp r14, rax
    jb 1b
    call dts_save_header
    mov rdi, rbx
    xor esi, esi
    call dts_step
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov rdi, rbx
    mov esi, 17
    call dts_step
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov rdi, rbx
    mov rsi, -1
    call dts_timeout
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    # Negative cached minimum is rejected only when a due is present.
    mov qword ptr [rbx + RT_debtScanHasDue], 1
    mov qword ptr [rbx + RT_debtScanMin], -1
    call dts_save_header
    mov rdi, rbx
    mov esi, 16
    call dts_step
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov rdi, rbx
    mov esi, 100
    call dts_timeout
    cmp rax, -22
    jne dts_fail
    or rdx, rcx
    jnz dts_fail
    call dts_same_header
    mov qword ptr [rbx + RT_debtScanHasDue], 0
    mov qword ptr [rbx + RT_debtScanMin], 0
    EPILOGUE
dts_save_header:
    lea rdi, [rip + dts_header]
    mov rsi, rbx
    mov edx, 575488
    jmp memcpy
dts_same_header:
    PROLOGUE
    lea rdi, [rip + dts_header]
    mov rsi, rbx
    mov edx, 575488
    call memeq
    test eax, eax
    jz dts_fail
    EPILOGUE

# Move a genuine FREE row into the allocation head, preserving the full free list.
# Row4096 can be both unvisited and already visited in a still-partial pass.
dts_choose_row:
    PROLOGUE
    mov rbx, [rip + rts_table]
    cmp qword ptr [rbx + RT_freeHead], 4097
    je 3f
    mov r12, [rbx + RT_freeHead]
    mov r13d, 8192
1:  lea rax, [r12 - 1]
    cmp rax, 8192
    jae dts_fail
    imul rax, rax, RT_ROW_SIZE
    lea r14, [rbx + rax + RT_rows]
    cmp qword ptr [r14 + RTR_state], RTR_FREE
    jne dts_fail
    cmp qword ptr [r14 + RTR_ro], 0
    jne dts_fail
    cmp qword ptr [r14 + RTR_next], 4097
    je 2f
    mov r12, [r14 + RTR_next]
    dec r13
    jnz 1b
    jmp dts_fail
2:  lea r15, [rbx + RT_rows + 4096 * RT_ROW_SIZE]
    cmp qword ptr [r15 + RTR_state], RTR_FREE
    jne dts_fail
    mov rax, [r15 + RTR_next]
    mov [r14 + RTR_next], rax
    mov rax, [rbx + RT_freeHead]
    mov [r15 + RTR_next], rax
    mov qword ptr [rbx + RT_freeHead], 4097
3:  EPILOGUE

# A real insert and actual consumed owner drop occur with no census slice between.
# The physical row returns to exactly its former FREE image; sticky dirty remains.
dts_actual_aba:
    PROLOGUE 48
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov rax, [rip + prep_total_charge]
    mov [rsp + 8], rax
    mov eax, [rip + rts_exts + 17 * EXT_SIZE + EXT_features]
    mov [rsp + 16], rax
    or dword ptr [rip + rts_exts + 17 * EXT_SIZE + EXT_features], FEAT_COMMANDS
    call dts_choose_row
    lea r12, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    lea rax, [rip + rr_key]
    mov [rip + rr_config + ROC_key], rax
    lea rdi, [rip + rr_config]
    call ext_runtime_new
    test rax, rax
    jz dts_fail
    mov [rsp + 24], rax
    mov qword ptr [rip + rr_hold], 0
    mov qword ptr [rip + rr_row], 4097
    lea r13, [rbx + RT_rows + 4096 * RT_ROW_SIZE]
    lea rdi, [rip + dts_aba_row]
    mov rsi, r13
    mov edx, 64
    call memcpy
    mov rax, [r13 + RTR_next]
    mov [rbx + RT_freeHead], rax
    mov rax, [rsp + 24]
    mov [r13 + RTR_ro], rax
    mov qword ptr [r13 + RTR_ordinal], 17
    mov rax, [rip + rts_session]
    mov [r13 + RTR_session], rax
    mov qword ptr [r13 + RTR_next], 0
    mov qword ptr [r13 + RTR_prev], 0
    mov qword ptr [r13 + RTR_acceptSequence], 1
    mov qword ptr [r13 + RTR_state], RTR_LIVE
    mov qword ptr [r13 + RTR_slotNext], 0
    mov qword ptr [rbx + RT_nlive], 1
    mov qword ptr [rbx + RT_liveHead], 4097
    mov qword ptr [rbx + RT_liveTail], 4097
    mov qword ptr [r12 + RTS_nlive], 1
    mov qword ptr [r12 + RTS_liveHead], 4097
    lea rdi, [rip + rr_request]
    xor esi, esi
    mov edx, RTQ_SIZE
    call memset
    mov qword ptr [rip + rr_request + RTQ_ordinal], 17
    mov rax, [rip + rts_session]
    mov [rip + rr_request + RTQ_session], rax
    mov qword ptr [rip + rr_request + RTQ_id], 7
    mov qword ptr [rip + rr_request + RTQ_kind], RTQ_UNREGISTER
    lea rax, [rip + rr_key]
    mov [rip + rr_request + RTQ_key], rax
    mov qword ptr [rip + rr_request + RTQ_keyLen], 1
    call dts_partial
    mov rax, [rbx + RT_debtScanCursor]
    mov [rsp + 32], rax
    mov rdi, rbx
    lea rsi, [rip + rr_request]
    call rr_checked_remove
    test rax, rax
    jnz dts_fail
    cmp rdx, 1
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanValid], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanDirty], 1
    jne dts_fail
    cmp qword ptr [r13 + RTR_state], RTR_DEBT
    jne dts_fail
    call rr_clear_credit
    mov qword ptr [rip + rr_drop_mode], 0
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    mov qword ptr [rip + rr_work_watch], 1
    call rt_debt_step
    mov qword ptr [rip + rr_work_watch], 0
    cmp rax, 1
    jne dts_fail
    cmp rdx, 1
    jne dts_fail
    mov rax, [rsp + 32]
    cmp [rbx + RT_debtScanCursor], rax
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanActive], 1
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanValid], 0
    jne dts_fail
    cmp qword ptr [rbx + RT_debtScanDirty], 1
    jne dts_fail
    mov rdi, r13
    lea rsi, [rip + dts_aba_row]
    mov edx, 64
    call memeq
    test eax, eax
    jz dts_fail
    call dts_finish_real
    call tt_drain
    mov rax, [rsp]
    cmp [rip + g_mem_live], rax
    jne dts_fail
    mov rax, [rsp + 8]
    cmp [rip + prep_total_charge], rax
    jne dts_fail
    mov eax, [rsp + 16]
    mov [rip + rts_exts + 17 * EXT_SIZE + EXT_features], eax
    EPILOGUE
