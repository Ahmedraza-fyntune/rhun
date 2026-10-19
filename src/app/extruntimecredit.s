# One inline operation credit. It never grants native action authority.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeadmit.inc"
.text
# table,ordinal,session,positiveINT31id -> status, DX0 unconsumed/1 owned/2 fatal.
FN rt_credit_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test r14, r14
    jle .Lrc_invalid
    cmp r14, 0x7fffffff
    ja .Lrc_invalid
    call rt_session_check
    test rax, rax
    jnz .Lrc_unconsumed
    imul rax, r12, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    test qword ptr [r15 + RTS_flags], RTSF_ID_IN_USE | RTSF_OP_CREDIT
    jz 1f
    cmp [r15 + RTS_replyID], r14
    je .Lrc_duplicate
1:  cmp [r15 + RTS_promptID], r14
    je .Lrc_duplicate
    mov rax, [r15 + RTS_flags]
    # Bit32 is retained CHANNEL_BOUND, not an operation or stop obligation.
    and rax, -33
    or rax, [r15 + RTS_ticket]
    or rax, [r15 + RTS_failedPO]
    or rax, [r15 + RTS_orphanEO]
    or rax, [r15 + RTS_replyID]
    or rax, [r15 + RTS_outcome]
    or rax, [r15 + RTS_delivery]
    or rax, [r15 + RTS_replyLen]
    or rax, [r15 + RTS_retryDue]
    or rax, [r15 + RTS_backoff]
    or rax, [r15 + RTS_stallDeadline]
    or rax, [r15 + RTS_opKind]
    or rax, [r15 + RTS_opStart]
    or rax, [r15 + RTS_nreserved]
    jnz .Lrc_busy
    imul rax, r12, RT_DISCARD_SIZE
    lea rax, [rbx + rax + RT_discards]
    mov rcx, [rax + RTD_state]
    or rcx, [rax + RTD_rejectedRequestID]
    jnz .Lrc_busy
    mov [r15 + RTS_replyID], r14
    or qword ptr [r15 + RTS_flags], RTSF_OP_CREDIT | RTSF_ID_IN_USE | RTSF_PARSER_PAUSED
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lrc_duplicate:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov ecx, RT_STOP_DUPLICATE_ID
    call rt_session_end
    mov rax, -71
    mov edx, 2
    EPILOGUE
.Lrc_busy:
    mov rax, -11
    jmp .Lrc_unconsumed
.Lrc_invalid:
    mov rax, -22
.Lrc_unconsumed:
    xor edx, edx
    EPILOGUE

# table,ordinal,session,id,nonOK reason -> errno, explicit disposition.
FN rt_reject
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, r8
    lea rax, [r14 - 1]
    cmp rax, RTRSP_CANCELLED - 1
    ja .Lrj_invalid
    call rt_credit_begin
    cmp rdx, 1
    jne .Lrj_done
    call time_ms
    mov r8, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call rt_reply_freeze_publish
    lea rax, [rip + rt_reply_errors]
    mov rax, [rax + r14*8]
    mov edx, 1
.Lrj_done:
    EPILOGUE
.Lrj_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
