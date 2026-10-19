# One checked operation reference per visited peer; response truth is immutable.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.include "app/extruntimeadmit.inc"
.include "app/extruntimereply.inc"
.text
# TABLE,now,budget -> status,DXvisited,CX reply-class due. No native stop here.
FN rt_operation_cleanup_step
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    test r12, r12
    js .Lroc_api
    lea rax, [r13 - 1]
    cmp rax, RTR_STEP_CAP - 1
    ja .Lroc_api
    call rt_reply_table_check
    test rax, rax
    jnz .Lroc_api
    cmp qword ptr [rbx + RT_cleanupCursor], RT_SLOT_COUNT
    jae .Lroc_api
.Lroc_loop:
    cmp [rsp], r13
    jae .Lroc_done
    mov r14, [rbx + RT_cleanupCursor]
    lea rax, [r14 + 1]
    and eax, RT_SLOT_COUNT - 1
    mov [rbx + RT_cleanupCursor], rax
    inc qword ptr [rsp]
    imul rax, r14, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    test qword ptr [r15 + RTS_flags], RTSF_OP_CREDIT
    jz .Lroc_loop
    mov rax, [r15 + RTS_delivery]
    cmp rax, RTDEL_QUEUED
    je 1f
    cmp rax, RTDEL_ABANDONED
    jne .Lroc_loop
1:  mov rdi, r15
    mov esi, 1
    call rt_reply_credit_check
    test rax, rax
    jnz .Lroc_error
    mov rax, [r15 + RTS_retryDue]
    test rax, rax
    js .Lroc_loop
    cmp rax, r12
    ja .Lroc_loop
    cmp qword ptr [r15 + RTS_nreserved], 0
    jne .Lroc_busy
    mov rcx, [rbx + RT_batchCount]
    cmp rcx, 16
    ja .Lroc_bad
    xor edx, edx
2:  cmp rdx, rcx
    jae 3f
    mov rax, [rbx + RT_selected0 + rdx*8]
    cmp rax, RT_SLOT_COUNT
    jae .Lroc_bad
    cmp rax, r14
    je .Lroc_busy
    inc rdx
    jmp 2b
3:  mov rax, [r15 + RTS_ticket]
    test rax, rax
    jz 4f
    cmp rax, [r15 + RTS_failedPO]
    je .Lroc_bad
4:  lea rax, [r15 + RTS_ticket]
    xor r8d, r8d
    cmp qword ptr [rax], 0
    jne .Lroc_ticket
    lea rax, [r15 + RTS_failedPO]
    inc r8d
    cmp qword ptr [rax], 0
    jne .Lroc_ticket
    lea rax, [r15 + RTS_orphanEO]
    cmp qword ptr [rax], 0
    je .Lroc_finalize
    mov [rsp + 24], rax
    mov rdi, [rax]
    call ext_prepare_owner_release_deferred
    jmp .Lroc_drop_result
.Lroc_ticket:
    mov [rsp + 24], rax
    mov rdi, r15
    mov rsi, [rax]
    mov rdx, r14
    # R8=0 main terminal ticket,1 original failed constructor result.
    call rt_operation_ticket_check
    test rax, rax
    jnz .Lroc_error
    mov rax, [rsp + 24]
    mov rdi, [rax]
    call rt_ticket_release
.Lroc_drop_result:
    mov [rsp + 32], rax
    cmp rdx, 1
    jne .Lroc_refused
    mov rdx, [rsp + 24]
    mov qword ptr [rdx], 0
    mov qword ptr [r15 + RTS_retryDue], 0
    mov qword ptr [r15 + RTS_backoff], 0
    mov qword ptr [rsp + 8], 1
    mov rax, [rsp + 32]
    test rax, rax
    js .Lroc_note_continue
    jmp .Lroc_loop
.Lroc_refused:
    mov rax, [rsp + 32]
    test rax, rax
    js .Lroc_error
    mov rax, -5
    jmp .Lroc_error
.Lroc_finalize:
    imul rax, r14, RT_DISCARD_SIZE
    lea rax, [rbx + rax + RT_discards]
    mov rcx, [rax + RTD_state]
    or rcx, [rax + RTD_rejectedRequestID]
    jnz .Lroc_busy
    # Pure action check precedes completion. It cannot follow a replacement EXT base.
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    call rt_session_check
    mov [rsp + 40], rax
    test rax, rax
    jz 5f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r15 + RTS_session]
    mov ecx, RT_STOP_RESPONSE_STALLED
    call rt_session_end
    test rax, rax
    jnz .Lroc_error
5:  and qword ptr [r15 + RTS_flags], ~(RTSF_OP_CREDIT | RTSF_REPLY_ATTEMPTED)
    cmp qword ptr [rsp + 40], 0
    jne 6f
    and qword ptr [r15 + RTS_flags], ~RTSF_PARSER_PAUSED
6:  mov qword ptr [r15 + RTS_outcome], 0
    mov qword ptr [r15 + RTS_delivery], 0
    mov qword ptr [r15 + RTS_replyLen], 0
    mov qword ptr [r15 + RTS_retryDue], 0
    mov qword ptr [r15 + RTS_backoff], 0
    mov qword ptr [r15 + RTS_stallDeadline], 0
    mov qword ptr [r15 + RTS_opKind], 0
    mov qword ptr [r15 + RTS_opStart], 0
    mov qword ptr [rsp + 8], 1
    jmp .Lroc_loop
.Lroc_busy:
    mov rax, -16
    jmp .Lroc_error
.Lroc_bad:
    mov rax, -22
.Lroc_error:
    mov [rsp + 32], rax
    # Preserve the first actual cleanup refusal even if scheduling itself parks.
    lea rdi, [rbx - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
    mov rdi, r15
    mov rsi, r12
    mov edx, 1000
    call rt_reply_retry_schedule
    test rax, rax
    jns 7f
    mov [rsp + 32], rax
7:  mov rax, [rsp + 32]
.Lroc_note_continue:
    cmp qword ptr [rsp + 16], 0
    jne 8f
    mov [rsp + 16], rax
8:  lea rdi, [rbx - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
    jmp .Lroc_loop
.Lroc_done:
    mov rdi, rbx
    mov rsi, r12
    call rt_reply_timeout
    mov rcx, rax
    mov rdx, [rsp]
    mov rax, [rsp + 16]
    test rax, rax
    jnz 9f
    mov rax, [rsp + 8]
9:  EPILOGUE
.Lroc_api:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

# Owned slot,owned result,ordinal,R8failed ->0/-EINVAL. Role3 never reaches a drop.
FN rt_operation_ticket_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, r8
    mov rdi, r12
    call rt_ticket_is_owned
    test eax, eax
    jnz .Lrot_typed
    test r14, r14
    jz .Lrot_bad
    # Premark generic ticket: prove the complete creation header before field reads.
    test r12, r12
    jz .Lrot_bad
    lea rax, [r12 - RD_PO_BACK]
    cmp [rax + RD_object], r12
    jne .Lrot_bad
    cmp qword ptr [rax + RD_kind], RD_LEDGER
    jne .Lrot_bad
    mov rcx, [rax + RD_state]
    test ecx, RDF_STATE_MASK
    jnz .Lrot_bad
    test ecx, RDF_PO
    jz .Lrot_bad
    cmp qword ptr [r12 + PO_refs], 0
    je .Lrot_bad
    cmp qword ptr [r12 - AO_SIZE + AO_charge], RTT_HEADER_SIZE + RD_PO_BACK + 16
    jb .Lrot_bad
    cmp qword ptr [r12 + RTT_role], RT_TICKET_ROLE
    jne .Lrot_bad
    mov rdi, [r12 + PO_eo]
    test rdi, rdi
    jz .Lrot_bad
    cmp qword ptr [rdi - RD_SIZE + RD_kind], RD_EO
    jne .Lrot_bad
    test qword ptr [rdi - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lrot_bad
    cmp qword ptr [rdi + EO_refs], 0
    je .Lrot_bad
    cmp qword ptr [rdi + EO_deferred], 1
    jne .Lrot_bad
    cmp qword ptr [rdi + EO_lease], -1
    jne .Lrot_bad
    mov rdi, r12
    call rt_ticket_extent_check
    test eax, eax
    jz .Lrot_bad
.Lrot_typed:
    cmp [r12 + RTT_ordinal], r13
    jne .Lrot_bad
    mov rax, [rbx + RTS_session]
    cmp [r12 + RTT_session], rax
    jne .Lrot_bad
    mov rax, [r12 + RTT_requestID]
    test rax, rax
    jle .Lrot_bad
    cmp rax, 0x7fffffff
    ja .Lrot_bad
    cmp qword ptr [r12 + RTT_reservedRow], 0
    jne .Lrot_bad
    test r14, r14
    jnz .Lrot_failed
    cmp qword ptr [r12 + PO_ready], 1
    jne .Lrot_bad
    cmp qword ptr [r12 + RTT_acceptSequence], 0
    jle .Lrot_bad
    cmp qword ptr [rbx + RTS_outcome], RTRSP_OK + 1
    jne 1f
    cmp qword ptr [r12 + RTT_phase], RTT_COMMITTED
    jne .Lrot_bad
    jmp .Lrot_ea
1:  cmp qword ptr [r12 + RTT_phase], RTT_TERMINAL_ERROR
    jne .Lrot_bad
.Lrot_ea:
    mov rax, [rbx + RTS_ea]
    cmp [r12 + RTT_ea], rax
    jne .Lrot_bad
    xor eax, eax
    EPILOGUE
.Lrot_failed:
    cmp qword ptr [r12 + RTT_acceptSequence], 0
    jne .Lrot_bad
    cmp qword ptr [r12 + RTT_ro], 0
    jne .Lrot_bad
    cmp qword ptr [r12 + RTT_phase], RTT_BUILDING
    je 2f
    cmp qword ptr [r12 + RTT_phase], RTT_CAPTURED
    jne .Lrot_bad
    cmp qword ptr [r12 + PO_ready], 1
    jne .Lrot_bad
    jmp .Lrot_ea
2:  cmp qword ptr [r12 + PO_ready], 0
    jne .Lrot_bad
    cmp qword ptr [r12 + RTT_ea], 0
    jne .Lrot_bad
    cmp qword ptr [r12 + RTT_orphanEO], 0
    jne .Lrot_bad
    xor eax, eax
    EPILOGUE
.Lrot_bad:
    mov rax, -22
    EPILOGUE
