# Terminal response transfer is queue acceptance, never inferred peer receipt.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeadmit.inc"
.include "app/extruntimereply.inc"
.text
# TABLE,nonnegativeNow,budget1..16 -> status,DXvisited,CX class-only absolute due.
FN rt_reply_step
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], RTR_COPY_CAP
    mov qword ptr [rsp + 64], 0
    test r12, r12
    js .Lrr_api
    lea rax, [r13 - 1]
    cmp rax, RTR_STEP_CAP - 1
    ja .Lrr_api
    call rt_reply_table_check
    test rax, rax
    jnz .Lrr_api
    cmp qword ptr [rbx + RT_replyCursor], RT_SLOT_COUNT
    jae .Lrr_api
.Lrr_loop:
    cmp [rsp], r13
    jae .Lrr_done
    cmp qword ptr [rsp + 64], 0
    jne .Lrr_done
    mov r14, [rbx + RT_replyCursor]
    lea rax, [r14 + 1]
    and eax, RT_SLOT_COUNT - 1
    mov [rbx + RT_replyCursor], rax
    inc qword ptr [rsp]
    imul rax, r14, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    test qword ptr [r15 + RTS_flags], RTSF_OP_CREDIT
    jz .Lrr_loop
    cmp qword ptr [r15 + RTS_delivery], RTDEL_WAIT
    jne .Lrr_loop
    mov rdi, r15
    xor esi, esi
    call rt_reply_credit_check
    test rax, rax
    jnz .Lrr_bad_slot
    # Deadline revocation precedes retry eligibility, including a parked attempt.
    cmp qword ptr [r15 + RTS_state], RTS_ACTIVE
    jne 1f
    cmp r12, [r15 + RTS_stallDeadline]
    jb 1f
    call .Lrr_end_session
    test rax, rax
    jnz .Lrr_bad_slot
    mov qword ptr [rsp + 8], 1
1:  mov rax, [r15 + RTS_retryDue]
    test rax, rax
    js .Lrr_loop
    cmp rax, r12
    ja .Lrr_loop
    mov rax, [r15 + RTS_replyLen]
    cmp [rsp + 24], rax
    jb .Lrr_done
    mov qword ptr [rsp + 40], 0
    call .Lrr_channel
    test rax, rax
    jnz .Lrr_failed
    mov [rsp + 32], rdx
    mov rdi, rdx
    mov rsi, [r15 + RTS_replyLen]
    call rt_reply_queue_check
    test rax, rax
    jnz .Lrr_failed
    mov [rsp + 40], rcx
    # If this enqueue could allocate, its single attempt ends the service slice.
    test rcx, rcx
    jz 2f
    mov qword ptr [rsp + 64], 1
2:  call .Lrr_enqueue
    test rax, rax
    jz .Lrr_accepted
    cmp rax, -11
    jne .Lrr_failed
    cmp qword ptr [rsp + 64], 0
    jne .Lrr_failed
    # Re-prove exact ownership before inspecting a fragmentation opportunity.
    call .Lrr_channel
    test rax, rax
    jnz .Lrr_failed
    mov [rsp + 32], rdx
    mov rdi, rdx
    mov rsi, [r15 + RTS_replyLen]
    call rt_reply_queue_check
    test rax, rax
    jnz .Lrr_failed
    test r8, r8
    jz .Lrr_again
    mov rax, [rsp + 24]
    sub rax, [r15 + RTS_replyLen]
    jz .Lrr_again
    cmp rdx, rax
    ja .Lrr_again
    mov [rsp + 48], rdx
    mov qword ptr [rsp + 64], 1
    mov rdi, [rsp + 32]
    mov rsi, rax
    call ext_send_queue_compact_bounded
    test rax, rax
    jnz .Lrr_failed
    mov rax, [rsp + 48]
    sub [rsp + 24], rax
    mov qword ptr [rsp + 8], 1
    # Only one retry, after successful bounded compaction. It cannot allocate.
    call .Lrr_enqueue
    test rax, rax
    jnz .Lrr_failed
.Lrr_accepted:
    mov rax, [r15 + RTS_replyLen]
    sub [rsp + 24], rax
    mov qword ptr [r15 + RTS_delivery], RTDEL_QUEUED
    mov qword ptr [r15 + RTS_replyID], 0
    and qword ptr [r15 + RTS_flags], ~RTSF_ID_IN_USE
    mov qword ptr [r15 + RTS_retryDue], 0
    mov qword ptr [r15 + RTS_backoff], 0
    mov qword ptr [rsp + 8], 1
    jmp .Lrr_loop
.Lrr_failed:
    cmp rax, -32
    je .Lrr_closed
    mov [rsp + 56], rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    call rt_session_channel_quiet_check
    test rax, rax
    jz .Lrr_abandoned
    mov rax, [rsp + 56]
    jmp .Lrr_retry
.Lrr_closed:
    call .Lrr_end_session
    test rax, rax
    jnz .Lrr_bad_slot
.Lrr_abandoned:
    # Known-closed EPIPE or complete native quiet, never mere action revocation.
    mov qword ptr [r15 + RTS_delivery], RTDEL_ABANDONED
    mov qword ptr [r15 + RTS_replyID], 0
    and qword ptr [r15 + RTS_flags], ~RTSF_ID_IN_USE
    mov qword ptr [r15 + RTS_retryDue], 0
    mov qword ptr [r15 + RTS_backoff], 0
    mov qword ptr [rsp + 8], 1
    jmp .Lrr_loop
.Lrr_again:
    mov rax, -11
.Lrr_retry:
    mov [rsp + 56], rax
    mov rdi, r15
    mov rsi, r12
    mov edx, 250
    call rt_reply_retry_schedule
    test rax, rax
    js .Lrr_bad_slot
    mov rax, [rsp + 56]
    # Expected backpressure, OOM and stale tuple remain owned pending responses.
    cmp rax, -11
    je .Lrr_loop
    cmp rax, -12
    je .Lrr_loop
    cmp rax, -116
    je .Lrr_loop
.Lrr_bad_slot:
    cmp qword ptr [rsp + 16], 0
    jne 3f
    mov [rsp + 16], rax
3:  lea rdi, [rbx - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
    jmp .Lrr_loop
.Lrr_done:
    mov rdi, rbx
    mov rsi, r12
    call rt_reply_timeout
    mov rcx, rax
    mov rdx, [rsp]
    mov rax, [rsp + 16]
    test rax, rax
    jnz 4f
    mov rax, [rsp + 8]
4:  EPILOGUE
.Lrr_api:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

# Private helpers use the caller's retained TABLE/ordinal/slot callee-saved tuple.
.Lrr_channel:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    jmp rt_session_channel_check
.Lrr_enqueue:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    lea rcx, [r15 + RTS_reply]
    mov r8, [r15 + RTS_replyLen]
    mov r9d, 128
    jmp ext_send_enqueue_channel_bounded
.Lrr_end_session:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    mov ecx, RT_STOP_RESPONSE_STALLED
    jmp rt_session_end
