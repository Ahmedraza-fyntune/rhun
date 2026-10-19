# Registration capture owns a response before any fallible allocation.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.include "app/extruntimeadmit.inc"
.text
# table,request80 -> status, DX0 unconsumed/1 owned/2 fatal.
FN rt_admit
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    call rt_admit_source_check
    test rax, rax
    jnz .Lra_unconsumed
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], 0
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rsp
    call rt_ticket_request_check
    cmp rdx, 1
    jne .Lra_unconsumed
    mov [rsp + 32], rax
    mov r13, [r12 + RTQ_ordinal]
    imul rax, r13, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + RTQ_session]
    mov rcx, [r12 + RTQ_id]
    call rt_credit_begin
    cmp rdx, 1
    jne .Lra_done
    mov qword ptr [r14 + RTS_opKind], RTQ_REGISTER
    call time_ms
    mov [r14 + RTS_opStart], rax
    mov rax, [rsp + 32]
    test rax, rax
    jz .Lra_capacity
    cmp rax, -75
    je .Lra_busy
    mov rcx, [r12 + RTQ_keyLen]
    cmp rcx, 40
    ja .Lra_toobig
    cmp qword ptr [r12 + RTQ_titleLen], 80
    ja .Lra_toobig
    cmp qword ptr [r12 + RTQ_keysLen], 65536
    ja .Lra_toobig
    mov r15d, RTRSP_INVALID
    jmp .Lra_error
.Lra_capacity:
    cmp qword ptr [rbx + RT_barrierState], 0
    jne .Lra_busy
    mov rax, 0x7fffffffffffffff
    cmp [rip + rt_last_accept], rax
    jae .Lra_toobig
    cmp qword ptr [r14 + RTS_nlive], 64
    jae .Lra_toobig
    cmp qword ptr [r14 + RTS_nreserved], 0
    jne .Lra_busy
    mov rax, [rbx + RT_nlive]
    add rax, [rbx + RT_nreserved]
    jc .Lra_toobig
    cmp rax, RT_ROW_COUNT
    jae .Lra_toobig
    cmp qword ptr [rbx + RT_npending], RT_SLOT_COUNT
    jae .Lra_toobig
    mov rax, [rbx + RT_freeHead]
    test rax, rax
    jz .Lra_toobig
    cmp rax, RT_ROW_COUNT
    ja .Lra_busy
    mov [rsp + 48], rax
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r15, [rbx + rax + RT_rows]
    mov rax, [r15 + RTR_state]
    or rax, [r15 + RTR_ro]
    jnz .Lra_busy
    cmp qword ptr [r15 + RTR_next], RT_ROW_COUNT
    ja .Lra_busy
    mov [rsp + 56], r15
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rsp
    call rt_ticket_create_checked
    # Capture every separate result obligation before any later call.
    mov rax, [rsp + RTC_orphanEO]
    mov [r14 + RTS_orphanEO], rax
    mov r15, [rsp + RTC_owner]
    mov [r14 + RTS_failedPO], r15
    mov rax, [rsp + RTC_primary]
    or rax, [rsp + RTC_cleanup]
    or rax, [rsp + RTC_orphanEO]
    jnz .Lra_constructor_error
    test r15, r15
    jz .Lra_constructor_error
    # Checked constructor succeeds only with ready CAPTURED owner. No yield intervened.
    mov rdx, [rsp + 56]
    mov rax, [rdx + RTR_next]
    mov [rbx + RT_freeHead], rax
    inc qword ptr [rip + rt_last_accept]
    mov rax, [rip + rt_last_accept]
    mov [r15 + RTT_acceptSequence], rax
    mov [rdx + RTR_acceptSequence], rax
    mov rax, [rsp + 48]
    mov [r15 + RTT_reservedRow], rax
    mov [rdx + RTR_ordinal], r13
    mov rax, [r12 + RTQ_session]
    mov [rdx + RTR_session], rax
    mov qword ptr [rdx + RTR_state], RTR_RESERVED
    mov qword ptr [rdx + RTR_next], 0
    mov qword ptr [rdx + RTR_prev], 0
    mov qword ptr [rdx + RTR_slotNext], 0
    inc qword ptr [r14 + RTS_nreserved]
    inc qword ptr [rbx + RT_nreserved]
    mov rax, [rbx + RT_npending]
    lea rcx, [r13 + 1]
    lea rdx, [rbx + RT_pending]
    mov [rdx + rax*8], rcx
    inc qword ptr [rbx + RT_npending]
    mov qword ptr [r15 + RTT_phase], RTT_PENDING
    mov [r14 + RTS_ticket], r15
    mov qword ptr [r14 + RTS_failedPO], 0
    xor eax, eax
    mov edx, 1
    jmp .Lra_done
.Lra_constructor_error:
    cmp qword ptr [rsp + RTC_primary], -12
    je .Lra_oom
.Lra_busy:
    mov r15d, RTRSP_BUSY
    jmp .Lra_error
.Lra_toobig:
    mov r15d, RTRSP_TOOBIG
    jmp .Lra_error
.Lra_oom:
    mov r15d, RTRSP_OOM
.Lra_error:
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + RTQ_session]
    mov rcx, r15
    mov r8, [r14 + RTS_opStart]
    call rt_reply_freeze_publish
    lea rax, [rip + rt_reply_errors]
    mov rax, [rax + r15*8]
    mov edx, 1
.Lra_done:
    EPILOGUE
.Lra_unconsumed:
    xor edx, edx
    EPILOGUE

# Pure source alias checks before response stores. No counted source bytes read here.
FN rt_admit_source_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .Lras_bad
    mov rax, r12
    add rax, RTQ_SIZE
    jc .Lras_bad
    call rt_table_action_check
    test rax, rax
    jnz .Lras_done
    mov rdi, r12
    mov esi, RTQ_SIZE
    mov rdx, rbx
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lras_done
    mov rdi, r12
    mov esi, RTQ_SIZE
    mov rdx, [rbx + RT_stableExtBase]
    mov ecx, RT_SLOT_COUNT * EXT_SIZE
    call rt_spans_disjoint
    test rax, rax
    jnz .Lras_done
    mov r13, [r12 + RTQ_ordinal]
    cmp r13, RT_SLOT_COUNT
    jae .Lras_bad
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    mov ecx, RTQ_SIZE
    call rt_admit_span_check
    test rax, rax
    jnz .Lras_done
    mov r14d, RTQ_key
1:  mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + r14]
    mov rcx, [r12 + r14 + 8]
    call rt_admit_span_check
    test rax, rax
    jnz .Lras_done
    add r14, 16
    cmp r14, RTQ_keys
    jbe 1b
    xor eax, eax
.Lras_done:
    EPILOGUE
.Lras_bad:
    mov rax, -22
    EPILOGUE

# table,validOrdinal,source,width ->0/-EINVAL. zero width needs no pointer.
FN rt_admit_span_check
    test rcx, rcx
    jnz 1f
    xor eax, eax
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    imul rax, rsi, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lrasp_done
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + RT_stableExtBase]
    mov ecx, RT_SLOT_COUNT * EXT_SIZE
    call rt_spans_disjoint
    test rax, rax
    jnz .Lrasp_done
    mov r15, [r14 + RTS_ea]
    test r15, r15
    jz .Lrasp_bad
    mov rdi, r15
    call ea_is_ready
    test eax, eax
    jz .Lrasp_bad
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lrasp_done
    mov r15, [r14 + RTS_hi]
    mov rdi, r15
    call hi_is_ready
    test eax, eax
    jz .Lrasp_bad
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    call rt_output_disjoint_po
.Lrasp_done:
    EPILOGUE
.Lrasp_bad:
    mov rax, -22
    EPILOGUE

# table,ordinal,session,nonOK reason,now ->0/-errno, unchanged on refusal.
# Only unselected PENDING preparation may be cancelled by this entry.
FN rt_admit_cancel
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    test rcx, rcx
    jz .Lrac_bad
    call rt_reply_freeze_check
    test rax, rax
    jnz .Lrac_done
    cmp qword ptr [rbx + RT_batchCount], 0
    jne .Lrac_busy
    cmp qword ptr [rbx + RT_serviceCG], 0
    jne .Lrac_busy
    imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    cmp qword ptr [r13 + RTS_nreserved], 1
    jne .Lrac_bad
    mov r14, [r13 + RTS_ticket]
    mov rdi, r14
    call rt_ticket_is_owned
    test eax, eax
    jz .Lrac_bad
    cmp qword ptr [r14 + PO_ready], 1
    jne .Lrac_bad
    cmp qword ptr [r14 + RTT_phase], RTT_PENDING
    jne .Lrac_bad
    cmp qword ptr [r14 + RTT_ro], 0
    jne .Lrac_bad
    cmp [r14 + RTT_ordinal], r12
    jne .Lrac_bad
    mov rax, [rsp]
    cmp [r14 + RTT_session], rax
    jne .Lrac_bad
    mov rax, [r13 + RTS_replyID]
    cmp [r14 + RTT_requestID], rax
    jne .Lrac_bad
    mov rax, [r14 + RTT_reservedRow]
    test rax, rax
    jz .Lrac_bad
    cmp rax, RT_ROW_COUNT
    ja .Lrac_bad
    mov [rsp + 24], rax
    dec rax
    imul rax, rax, RT_ROW_SIZE
    lea r15, [rbx + rax + RT_rows]
    cmp qword ptr [r15 + RTR_state], RTR_RESERVED
    jne .Lrac_bad
    cmp qword ptr [r15 + RTR_ro], 0
    jne .Lrac_bad
    cmp [r15 + RTR_ordinal], r12
    jne .Lrac_bad
    mov rax, [rsp]
    cmp [r15 + RTR_session], rax
    jne .Lrac_bad
    mov rax, [r14 + RTT_acceptSequence]
    test rax, rax
    jle .Lrac_bad
    cmp [r15 + RTR_acceptSequence], rax
    jne .Lrac_bad
    cmp qword ptr [rbx + RT_nreserved], 0
    je .Lrac_bad
    cmp qword ptr [rbx + RT_nreserved], RT_ROW_COUNT
    ja .Lrac_bad
    cmp qword ptr [rbx + RT_freeHead], RT_ROW_COUNT
    ja .Lrac_bad
    mov rcx, [rbx + RT_npending]
    test rcx, rcx
    jz .Lrac_bad
    cmp rcx, RT_SLOT_COUNT
    ja .Lrac_bad
    mov [rsp + 40], rcx
    xor r8d, r8d
    xor r9d, r9d
    lea r10, [r12 + 1]
    lea r11, [rbx + RT_pending]
1:  cmp [r11 + r8*8], r10
    jne 2f
    inc r9
    mov [rsp + 32], r8
2:  inc r8
    cmp r8, rcx
    jb 1b
    cmp r9, 1
    jne .Lrac_bad
    # Every fallible predicate, including freeze reason/time/credit, precedes this store.
    mov rcx, [rsp + 40]
    dec rcx
    mov r8, [rsp + 32]
3:  cmp r8, rcx
    jae 4f
    mov rax, [r11 + r8*8 + 8]
    mov [r11 + r8*8], rax
    inc r8
    jmp 3b
4:  mov qword ptr [r11 + rcx*8], 0
    mov [rbx + RT_npending], rcx
    dec qword ptr [rbx + RT_nreserved]
    dec qword ptr [r13 + RTS_nreserved]
    mov rax, [rbx + RT_freeHead]
    mov qword ptr [r15 + RTR_ro], 0
    mov qword ptr [r15 + RTR_ordinal], 0
    mov qword ptr [r15 + RTR_session], 0
    mov [r15 + RTR_next], rax
    mov qword ptr [r15 + RTR_prev], 0
    mov qword ptr [r15 + RTR_acceptSequence], 0
    mov qword ptr [r15 + RTR_state], RTR_FREE
    mov qword ptr [r15 + RTR_slotNext], 0
    mov rax, [rsp + 24]
    mov [rbx + RT_freeHead], rax
    mov qword ptr [r14 + RTT_reservedRow], 0
    mov qword ptr [r14 + RTT_phase], RTT_TERMINAL_ERROR
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    call rt_reply_freeze_publish
    xor eax, eax
.Lrac_done:
    EPILOGUE
.Lrac_bad:
    mov rax, -22
    EPILOGUE
.Lrac_busy:
    mov rax, -16
    EPILOGUE
