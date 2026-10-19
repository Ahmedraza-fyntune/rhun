# Pure cleanup scheduling wake. Action grants and native ownership remain independent.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimesessionclock.inc"
.text
# Retained TABLE,ordinal,exact session -> AX0/-errno, no other result registers promised.
# Genuine relevant native/ownership event or explicit retry only. Never a timer visit.
FN rt_session_cleanup_wake
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrcw_invalid
    test r13, r13
    jle .Lrcw_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrcw_stale
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrcw_stale
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrcw_busy
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrcw_stale
    mov rax, [rbx + RT_stableExtBase]
    test rax, rax
    jz .Lrcw_stale
    cmp [rip + g_exts + VEC_ptr], rax
    jne .Lrcw_stale
    cmp qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    jne .Lrcw_stale
    cmp qword ptr [rip + g_exts + VEC_len], RT_SLOT_COUNT
    ja .Lrcw_stale
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp [r14 + RTS_session], r13
    jne .Lrcw_stale
    cmp qword ptr [r14 + RTS_state], RTS_DRAINING
    jne .Lrcw_busy
    test qword ptr [r14 + RTS_flags], RTSF_OP_CREDIT | RTSF_ID_IN_USE
    jnz .Lrcw_busy
    mov rax, [r14 + RTS_replyID]
    or rax, [r14 + RTS_outcome]
    or rax, [r14 + RTS_delivery]
    or rax, [r14 + RTS_replyLen]
    or rax, [r14 + RTS_stallDeadline]
    or rax, [r14 + RTS_opKind]
    or rax, [r14 + RTS_opStart]
    or rax, [r14 + RTS_ticket]
    or rax, [r14 + RTS_failedPO]
    or rax, [r14 + RTS_orphanEO]
    or rax, [r14 + RTS_liveHead]
    or rax, [r14 + RTS_nlive]
    or rax, [r14 + RTS_ndebt]
    or rax, [r14 + RTS_nreserved]
    or rax, [r14 + RTS_promptID]
    or rax, [r14 + RTS_grantSession]
    jnz .Lrcw_busy
    imul rax, r12, RT_DISCARD_SIZE
    lea r15, [rbx + rax + RT_discards]
    mov rax, [r15 + RTD_state]
    or rax, [r15 + RTD_rejectedRequestID]
    jnz .Lrcw_busy
    cmp qword ptr [r14 + RTS_retryDue], RTSC_PARKED
    jl .Lrcw_invalid
    cmp qword ptr [r14 + RTS_backoff], 1000
    ja .Lrcw_invalid
    mov qword ptr [r14 + RTS_retryDue], 0
    mov qword ptr [r14 + RTS_backoff], 0
    xor eax, eax
    EPILOGUE
.Lrcw_invalid:
    mov rax, -22
    EPILOGUE
.Lrcw_stale:
    mov rax, -116
    EPILOGUE
.Lrcw_busy:
    mov rax, -16
    EPILOGUE
