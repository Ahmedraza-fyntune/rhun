# Pure typed scalar checks and retry scheduling, with no native authority inference.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeadmit.inc"
.include "app/extruntimereply.inc"
.text
# Held TABLE only. No native base or action authority read.
FN rt_reply_table_check
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Lrrt_bad
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrrt_bad
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrrt_bad
    xor eax, eax
    EPILOGUE
.Lrrt_bad:
    mov rax, -22
    EPILOGUE

# Owned fixed slot, mode0 WAIT/1 QUEUED or ABANDONED. No mutation.
FN rt_reply_credit_check
    mov rax, [rdi + RTS_state]
    cmp rax, RTS_ACTIVE
    je 1f
    cmp rax, RTS_DRAINING
    jne .Lrrc_bad
1:  cmp qword ptr [rdi + RTS_session], 0
    jle .Lrrc_bad
    test qword ptr [rdi + RTS_flags], RTSF_OP_CREDIT
    jz .Lrrc_bad
    mov rax, [rdi + RTS_outcome]
    dec rax
    cmp rax, RTRSP_CANCELLED
    ja .Lrrc_bad
    mov rax, [rdi + RTS_replyLen]
    dec rax
    cmp rax, 127
    ja .Lrrc_bad
    cmp qword ptr [rdi + RTS_retryDue], RTR_PARKED
    jl .Lrrc_bad
    cmp qword ptr [rdi + RTS_stallDeadline], 0
    jle .Lrrc_bad
    cmp qword ptr [rdi + RTS_opStart], 0
    jl .Lrrc_bad
    mov rax, [rdi + RTS_backoff]
    cmp rax, 1000
    ja .Lrrc_bad
    test esi, esi
    jnz .Lrrc_settled
    cmp qword ptr [rdi + RTS_delivery], RTDEL_WAIT
    jne .Lrrc_bad
    cmp rax, 250
    ja .Lrrc_bad
    test qword ptr [rdi + RTS_flags], RTSF_ID_IN_USE
    jz .Lrrc_bad
    mov rax, [rdi + RTS_replyID]
    test rax, rax
    jle .Lrrc_bad
    cmp rax, 0x7fffffff
    ja .Lrrc_bad
    xor eax, eax
    ret
.Lrrc_settled:
    mov rax, [rdi + RTS_delivery]
    cmp rax, RTDEL_QUEUED
    je 2f
    cmp rax, RTDEL_ABANDONED
    jne .Lrrc_bad
2:  test qword ptr [rdi + RTS_flags], RTSF_ID_IN_USE
    jnz .Lrrc_bad
    cmp qword ptr [rdi + RTS_replyID], 0
    jne .Lrrc_bad
    xor eax, eax
    ret
.Lrrc_bad:
    mov rax, -22
    ret

# Slot,nonnegativeNow,maximumDelay ->0/-EOVERFLOW; exact owner remains retained.
FN rt_reply_retry_schedule
    mov rax, [rdi + RTS_backoff]
    test rax, rax
    jnz 1f
    mov eax, 8
1:  cmp rax, rdx
    jae 11f
    shl rax, 1
    cmp rax, rdx
    jbe 2f
11: mov rax, rdx
2:  mov [rdi + RTS_backoff], rax
    mov rcx, 0x7fffffffffffffff
    sub rcx, rax
    cmp rsi, rcx
    ja .Lrrs_park
    add rax, rsi
    mov [rdi + RTS_retryDue], rax
    xor eax, eax
    ret
.Lrrs_park:
    mov qword ptr [rdi + RTS_retryDue], RTR_PARKED
    mov rax, -75
    ret

# Genuine relevant ownership/native event or explicit retry only, never a timer pump.
FN rt_reply_wake
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrrw_stale
    test r13, r13
    jle .Lrrw_stale
    call rt_reply_table_check
    test rax, rax
    jnz .Lrrw_done
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp [r14 + RTS_session], r13
    jne .Lrrw_stale
    xor esi, esi
    cmp qword ptr [r14 + RTS_delivery], RTDEL_WAIT
    je 1f
    inc esi
1:  mov rdi, r14
    call rt_reply_credit_check
    test rax, rax
    jnz .Lrrw_done
    mov qword ptr [r14 + RTS_retryDue], 0
    mov qword ptr [r14 + RTS_backoff], 0
    xor eax, eax
.Lrrw_done:
    EPILOGUE
.Lrrw_stale:
    mov rax, -116
    EPILOGUE

# Reply/operation class only. Parent MUST aggregate builder/native/session timers.
# Fixed128 scalar census, independent from budgeted service visits.
FN rt_reply_timeout
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    js .Lrrto_bad
    call rt_reply_table_check
    test rax, rax
    jnz .Lrrto_done
    xor r13d, r13d
    xor r14d, r14d
.Lrrto_loop:
    imul rax, r13, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    xor esi, esi
    cmp qword ptr [r15 + RTS_delivery], RTDEL_WAIT
    je 1f
    inc esi
1:  mov rdi, r15
    call rt_reply_credit_check
    test rax, rax
    jnz .Lrrto_next
    mov rax, [r15 + RTS_retryDue]
    test rax, rax
    js 3f
    cmp rax, r12
    ja 2f
    mov rax, r12
    test rax, rax
    jnz 2f
    inc rax
2:  test r14, r14
    jz 21f
    cmp rax, r14
    jae 3f
21: mov r14, rax
3:  cmp qword ptr [r15 + RTS_delivery], RTDEL_WAIT
    jne .Lrrto_next
    # A DRAINING stop has already handled the absolute deadline.
    cmp qword ptr [r15 + RTS_state], RTS_ACTIVE
    jne .Lrrto_next
    mov rax, [r15 + RTS_stallDeadline]
    cmp rax, r12
    ja 4f
    mov rax, r12
    test rax, rax
    jnz 4f
    inc rax
4:  test r14, r14
    jz 41f
    cmp rax, r14
    jae .Lrrto_next
41: mov r14, rax
.Lrrto_next:
    inc r13
    cmp r13, RT_SLOT_COUNT
    jb .Lrrto_loop
    mov rax, r14
.Lrrto_done:
    EPILOGUE
.Lrrto_bad:
    mov rax, -22
    EPILOGUE

# Full checked output queue shape, EXT/positiveReplyLen<=128. No source copy.
# AX0/-errno, DXpending, CXmayAllocate0/1, R8tailFragmented0/1.
FN rt_reply_queue_check
    mov r9, [rdi + EXT_wq_off]
    mov rax, [rdi + EXT_wq + SB_len]
    cmp r9, rax
    ja .Lrrq_bad
    mov rdx, [rdi + EXT_wq + SB_cap]
    cmp rax, rdx
    ja .Lrrq_bad
    mov r10, [rdi + EXT_wq + SB_ptr]
    test rdx, rdx
    jnz 1f
    test r10, r10
    jnz .Lrrq_bad
    jmp 2f
1:  test r10, r10
    jz .Lrrq_bad
    add r10, rdx
    jc .Lrrq_bad
2:  mov r10, rax
    sub r10, r9
    mov r11, r10
    add r11, rsi
    jc .Lrrq_full
    cmp r11, EXT_WQ_HARD
    jae .Lrrq_full
    xor ecx, ecx
    xor r8d, r8d
    test r10, r10
    jnz 3f
    # Allocation when reply length exceeds existing capacity.
    xor ecx, ecx
    cmp rsi, rdx
    seta cl
    jmp 4f
3:  test r9, r9
    jz 4f
    add rax, rsi
    jc .Lrrq_bad
    cmp rax, rdx
    seta r8b
4:  mov rdx, r10
    xor eax, eax
    ret
.Lrrq_full:
    mov rax, -11
    ret
.Lrrq_bad:
    mov rax, -22
    ret
