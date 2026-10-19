# Exact process-session capture. Capture itself never opens the native START gate.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimesessionclock.inc"
.data
.p2align 3
.globl rt_authority_epoch
rt_authority_epoch: .quad 1
.text
# Saturation permanently disables caches. Direct authority still checks native grants.
FN rt_authority_invalidate_pure
    mov rax, [rip + rt_authority_epoch]
    test rax, rax
    jz 2f
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jae 1f
    inc rax
    mov [rip + rt_authority_epoch], rax
2:  ret
1:  mov qword ptr [rip + rt_authority_epoch], 0
    ret

# Current, open, ready TABLE only. Does not read EXT or establish session authority.
FN rt_table_action_check
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Lrta_stale
    cmp [rip + g_activeRT], rbx
    jne .Lrta_stale
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrta_stale
    cmp qword ptr [rbx + RT_flags], 0
    jne .Lrta_stale
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrta_stale
    mov rax, [rbx + RT_stableExtBase]
    test rax, rax
    jz .Lrta_stale
    cmp [rip + g_exts + VEC_ptr], rax
    jne .Lrta_stale
    cmp qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    jne .Lrta_stale
    cmp qword ptr [rip + g_exts + VEC_len], RT_SLOT_COUNT
    ja .Lrta_stale
    xor eax, eax
    EPILOGUE
.Lrta_stale:
    mov rax, -116
    EPILOGUE

# table,ordinal,EA,exactPositiveKeeper,outSession8 ->0/-errno, no changes on refusal.
FN rt_session_begin_check
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    cmp r12, RT_SLOT_COUNT
    jae .Lrsb_invalid
    test r14, r14
    jle .Lrsb_invalid
    call rt_table_action_check
    test rax, rax
    jnz .Lrsb_done
    cmp qword ptr [rbx + RT_barrierState], 0
    jne .Lrsb_busy
    imul rax, r12, RT_SLOT_SIZE
    lea r9, [rbx + rax + RT_slots]
    mov rax, [r9 + RTS_state]
    or rax, [r9 + RTS_ea]
    or rax, [r9 + RTS_hi]
    or rax, [r9 + RTS_ticket]
    or rax, [r9 + RTS_orphanEO]
    or rax, [r9 + RTS_failedPO]
    or rax, [r9 + RTS_nlive]
    or rax, [r9 + RTS_nreserved]
    or rax, [r9 + RTS_ndebt]
    or rax, [r9 + RTS_liveHead]
    or rax, [r9 + RTS_flags]
    or rax, [r9 + RTS_replyID]
    or rax, [r9 + RTS_promptID]
    or rax, [r9 + RTS_expectedKeeper]
    or rax, [r9 + RTS_grantSession]
    jnz .Lrsb_busy
    mov rdi, r15
    mov esi, 8
    mov rdx, rbx
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lrsb_done
    mov rdi, r15
    mov esi, 8
    mov rdx, [rbx + RT_stableExtBase]
    mov ecx, RT_SLOT_COUNT * EXT_SIZE
    call rt_spans_disjoint
    test rax, rax
    jnz .Lrsb_done
    imul rax, r12, EXT_SIZE
    add rax, [rbx + RT_stableExtBase]
    mov [rsp], rax
    cmp [rax + EXT_activation_owner], r13
    jne .Lrsb_stale
    cmp [rax + EXT_keeper], r14
    jne .Lrsb_stale
    cmp dword ptr [rax + EXT_start_armed], 0
    jne .Lrsb_stale
    cmp dword ptr [rax + EXT_startaccepted], 0
    jne .Lrsb_stale
    cmp dword ptr [rax + EXT_retiring], 0
    jne .Lrsb_stale
    cmp dword ptr [rax + EXT_status], ES_RUNNING
    je .Lrsb_stale
    cmp dword ptr [rax + EXT_status], ES_STOPPING
    je .Lrsb_stale
    mov rdi, r13
    call ea_is_ready
    test eax, eax
    jz .Lrsb_stale
    cmp qword ptr [r13 + PO_refs], -1
    je .Lrsb_overflow
    mov rax, [rsp]
    mov rax, [rax + EXT_identity_owner]
    mov [rsp + 8], rax
    mov rdi, rax
    call hi_is_ready
    test eax, eax
    jz .Lrsb_stale
    mov rax, [rsp + 8]
    cmp qword ptr [rax + PO_refs], -1
    je .Lrsb_overflow
    mov rdi, r15
    mov esi, 8
    mov rdx, r13
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lrsb_done
    mov rdi, r15
    mov esi, 8
    mov rdx, [rsp + 8]
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lrsb_done
    mov rdi, [rsp]
    call ext_activation_host_check
    test rax, rax
    jnz .Lrsb_done
    mov rax, 0x7fffffffffffffff
    cmp [rip + rt_last_session], rax
    jae .Lrsb_overflow
    xor eax, eax
.Lrsb_done:
    EPILOGUE
.Lrsb_overflow:
    mov rax, -75
    EPILOGUE
.Lrsb_busy:
    mov rax, -16
    EPILOGUE
.Lrsb_stale:
    mov rax, -116
    EPILOGUE
.Lrsb_invalid:
    mov rax, -22
    EPILOGUE

# Same exact arguments immediately after successful check, with no intervening mutation.
# The two checked increments and all installation stores are infallible.
FN rt_session_begin_publish
    PROLOGUE
    imul rax, rsi, EXT_SIZE
    add rax, [rdi + RT_stableExtBase]
    mov r9, [rax + EXT_identity_owner]
    imul rax, rsi, RT_SLOT_SIZE
    lea r10, [rdi + rax + RT_slots]
    inc qword ptr [rdx + PO_refs]
    inc qword ptr [r9 + PO_refs]
    inc qword ptr [rip + rt_last_session]
    mov rax, [rip + rt_last_session]
    mov [r10 + RTS_ea], rdx
    mov [r10 + RTS_hi], r9
    mov [r10 + RTS_session], rax
    mov [r10 + RTS_expectedKeeper], rcx
    mov qword ptr [r10 + RTS_state], RTS_ACTIVE
    mov qword ptr [r10 + RTS_grantSession], 0
    mov qword ptr [r10 + RTS_outcome], 0
    mov qword ptr [r10 + RTS_delivery], 0
    mov qword ptr [r10 + RTS_replyLen], 0
    mov qword ptr [r10 + RTS_retryDue], 0
    mov qword ptr [r10 + RTS_backoff], 0
    mov qword ptr [r10 + RTS_stallDeadline], 0
    mov qword ptr [r10 + RTS_opKind], 0
    mov qword ptr [r10 + RTS_opStart], 0
    mov [r8], rax
    call rt_authority_invalidate_pure
    xor eax, eax
    EPILOGUE

FN rt_session_begin
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    call rt_session_begin_check
    test rax, rax
    jnz 1f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8, [rsp + 32]
    call rt_session_begin_publish
1:  EPILOGUE

# Called only after actual accepted HELLO made the exact native host RUNNING.
# A failed bind leaves no grant. Full validation is admission work, never hot lookup work.
FN rt_session_bind
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrs_bind_stale
    test r13, r13
    jle .Lrs_bind_stale
    call rt_table_action_check
    test rax, rax
    jnz .Lrs_bind_done
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp qword ptr [r14 + RTS_state], RTS_ACTIVE
    jne .Lrs_bind_stale
    cmp [r14 + RTS_session], r13
    jne .Lrs_bind_stale
    cmp qword ptr [r14 + RTS_grantSession], 0
    je .Lrs_bind_cleared
    mov qword ptr [r14 + RTS_grantSession], 0
    call rt_authority_invalidate_pure
.Lrs_bind_cleared:
    imul rax, r12, EXT_SIZE
    mov rdi, [rbx + RT_stableExtBase]
    add rdi, rax
    mov rsi, [r14 + RTS_ea]
    mov rdx, [r14 + RTS_expectedKeeper]
    mov rcx, [r14 + RTS_hi]
    call ext_activation_host_running_bind_check
    test rax, rax
    jnz .Lrs_bind_done
    or qword ptr [r14 + RTS_flags], RTSF_CHANNEL_BOUND
    mov [r14 + RTS_grantSession], r13
    call rt_authority_invalidate_pure
    xor eax, eax
.Lrs_bind_done:
    EPILOGUE
.Lrs_bind_stale:
    mov rax, -116
    EPILOGUE

# table,ordinal,session ->0/-ESTALE. No bytes/epoch/native IO/ref mutation.
FN rt_session_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrsc_stale
    test r13, r13
    jle .Lrsc_stale
    call rt_table_action_check
    test rax, rax
    jnz .Lrsc_done
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp qword ptr [r14 + RTS_state], RTS_ACTIVE
    jne .Lrsc_stale
    cmp [r14 + RTS_session], r13
    jne .Lrsc_stale
    cmp [r14 + RTS_grantSession], r13
    jne .Lrsc_stale
    imul rax, r12, EXT_SIZE
    add rax, [rbx + RT_stableExtBase]
    mov rdi, rax
    mov rsi, [r14 + RTS_ea]
    mov rdx, [r14 + RTS_expectedKeeper]
    mov rcx, [r14 + RTS_hi]
    call ext_activation_host_running_session_check
.Lrsc_done:
    EPILOGUE
.Lrsc_stale:
    mov rax, -116
    EPILOGUE

# Logical revocation only. Native stop, physical removal and owned replies progress later.
# Flags high32 store the first native stop reason without stealing any response field.
FN rt_session_end
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp r12, RT_SLOT_COUNT
    jae .Lrse_stale
    test r13, r13
    jle .Lrse_stale
    call rt_table_is_owned
    test eax, eax
    jz .Lrse_stale
    imul rax, r12, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    cmp [r15 + RTS_session], r13
    jne .Lrse_stale
    cmp qword ptr [r15 + RTS_state], RTS_DRAINING
    je .Lrse_ok
    cmp qword ptr [r15 + RTS_state], RTS_ACTIVE
    jne .Lrse_stale
    mov qword ptr [r15 + RTS_grantSession], 0
    mov qword ptr [r15 + RTS_state], RTS_DRAINING
    mov eax, r14d
    shl rax, 32
    mov ecx, [r15 + RTS_flags]
    or rax, rcx
    or rax, RTSF_STOP_REQUIRED | RTSF_PARSER_PAUSED
    mov [r15 + RTS_flags], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call rt_prompt_action_revoke_pure
    call rt_authority_invalidate_pure
.Lrse_ok:
    xor eax, eax
    EPILOGUE
.Lrse_stale:
    mov rax, -116
    EPILOGUE

# Root reference transfer check. A retained shared ref never clears either root owner.
FN rt_root_close_check
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Lrrc_stale
    cmp [rip + g_activeRT], rbx
    jne 1f
    cmp qword ptr [rip + g_closingRT], 0
    jne .Lrrc_busy
    xor eax, eax
    EPILOGUE
1:  cmp [rip + g_closingRT], rbx
    jne .Lrrc_stale
    cmp qword ptr [rip + g_activeRT], 0
    jne .Lrrc_busy
    xor eax, eax
    EPILOGUE
.Lrrc_busy:
    mov rax, -16
    EPILOGUE
.Lrrc_stale:
    mov rax, -116
    EPILOGUE

# VOID, immediately after successful check. Transfer the existing root ref, no retain/drop.
FN rt_root_close_publish
    PROLOGUE
    mov rbx, rdi
    cmp [rip + g_activeRT], rbx
    jne 1f
    mov [rip + g_closingRT], rbx
    mov qword ptr [rip + g_activeRT], 0
1:  mov rdi, rbx
    call rt_table_revoke_all_pure
    EPILOGUE

FN rt_root_close
    PROLOGUE
    mov rbx, rdi
    call rt_root_close_check
    test rax, rax
    jnz 1f
    mov rdi, rbx
    call rt_root_close_publish
    xor eax, eax
1:  EPILOGUE

# table,ordinal,session,nonnegativeNow -> AX0 waiting/1 FREE/-errno,
# DX0/1 work units, CX nextDue (0 no timer, -1 genuine event/explicit retry).
# A parked supplier retry is resumed only by rt_session_cleanup_wake, never a timer.
# Native stop/collection is performed by the rotating service before this utility.
# A stopped process alone never authorizes dropping channel owners or slot reuse.
FN rt_session_cleanup_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp r12, RT_SLOT_COUNT
    jae .Lrcl_stale
    test r13, r13
    jle .Lrcl_stale
    test r14, r14
    js .Lrcl_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrcl_stale
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrcl_stale
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrcl_stale
    mov rax, [rbx + RT_stableExtBase]
    test rax, rax
    jz .Lrcl_stale
    cmp [rip + g_exts + VEC_ptr], rax
    jne .Lrcl_stale
    cmp qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    jne .Lrcl_stale
    imul rax, r12, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    cmp [r15 + RTS_session], r13
    jne .Lrcl_stale
    cmp qword ptr [r15 + RTS_state], RTS_DRAINING
    jne .Lrcl_stale
    mov rcx, [r15 + RTS_retryDue]
    cmp rcx, RTSC_PARKED
    jl .Lrcl_invalid
    cmp qword ptr [r15 + RTS_backoff], 1000
    ja .Lrcl_invalid
    cmp rcx, RTSC_PARKED
    je .Lrcl_wait_due
    cmp r14, rcx
    jb .Lrcl_wait_due
    mov rax, [r15 + RTS_ticket]
    or rax, [r15 + RTS_orphanEO]
    or rax, [r15 + RTS_failedPO]
    or rax, [r15 + RTS_liveHead]
    or rax, [r15 + RTS_nlive]
    or rax, [r15 + RTS_ndebt]
    or rax, [r15 + RTS_nreserved]
    or rax, [r15 + RTS_replyID]
    or rax, [r15 + RTS_promptID]
    or rax, [r15 + RTS_grantSession]
    jnz .Lrcl_wait
    test qword ptr [r15 + RTS_flags], RTSF_OP_CREDIT | RTSF_ID_IN_USE
    jnz .Lrcl_wait
    imul rax, r12, RT_DISCARD_SIZE
    cmp qword ptr [rbx + rax + RT_discards + RTD_state], 0
    jne .Lrcl_wait
    imul rax, r12, EXT_SIZE
    add rax, [rbx + RT_stableExtBase]
    mov r13, rax
    mov rdi, rax
    call ext_host_native_quiet
    test rax, rax
    jnz .Lrcl_native_wait
    mov eax, [r13 + EXT_start_armed]
    or eax, [r13 + EXT_wait_slot]
    or eax, [r13 + EXT_restart]
    jnz .Lrcl_native_wait
    # The actual native exit path clears these after detaching parser/UI borrowers.
    # Do not clear them here, free their buffers, or assume that an empty pipe reset them.
    mov rax, [r13 + EXT_body]
    or rax, [r13 + EXT_rbuf + SB_len]
    or rax, [r13 + EXT_wq + SB_len]
    or rax, [r13 + EXT_wq_off]
    jnz .Lrcl_native_wait
    lea r12, [r15 + RTS_ea]
    mov rdi, [r12]
    test rdi, rdi
    jz 1f
    call ext_activation_owner_release
    jmp .Lrcl_drop
1:  lea r12, [r15 + RTS_hi]
    mov rdi, [r12]
    test rdi, rdi
    jz .Lrcl_free
    call ext_host_identity_release
.Lrcl_drop:
    mov r13, rax
    cmp rdx, 1
    jne .Lrcl_refused
    mov qword ptr [r12], 0
    mov qword ptr [r15 + RTS_retryDue], 0
    mov qword ptr [r15 + RTS_backoff], 0
    lea rdi, [rbx - RD_PO_BACK]
    mov rsi, r13
    call ext_prepare_retire_note_error
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    EPILOGUE
.Lrcl_refused:
    lea rdi, [rbx - RD_PO_BACK]
    mov rsi, r13
    call ext_prepare_retire_note_error
    mov rax, [r15 + RTS_backoff]
    test rax, rax
    jnz 2f
    mov eax, 8
2:  shl rax, 1
    cmp rax, 1000
    jbe 3f
    mov eax, 1000
3:  mov [r15 + RTS_backoff], rax
    add rax, r14
    jc 4f
    test rax, rax
    jns 5f
4:  mov rax, RTSC_PARKED
5:  mov [r15 + RTS_retryDue], rax
    mov rcx, rax
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lrcl_free:
    # All owning fields are now empty. A fixed scalar reset cannot fail or yield.
    mov rdi, r15
    xor esi, esi
    mov edx, RT_SLOT_SIZE
    call memset
    mov eax, 1
    mov edx, 1
    xor ecx, ecx
    EPILOGUE
.Lrcl_native_wait:
    mov rcx, -1
    jmp .Lrcl_wait_due
.Lrcl_wait:
    xor ecx, ecx
.Lrcl_wait_due:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lrcl_stale:
    mov rax, -116
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lrcl_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
