# Retained reply transport authority is independent of runtime action authority.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/taskauth.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.text
# owned TABLE,ordinal,session ->AX0/-errno,DX exact EXT only on success.
# Never interprets DRAINING, a closed TABLE or a legacy error timestamp as death.
FN rt_session_channel_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrch_stale
    test r13, r13
    jle .Lrch_stale
    call rt_table_is_owned
    test eax, eax
    jz .Lrch_stale
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrch_stale
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrch_stale
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrch_stale
    mov r15, [rbx + RT_stableExtBase]
    test r15, r15
    jz .Lrch_stale
    cmp [rip + g_exts + VEC_ptr], r15
    jne .Lrch_stale
    cmp qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    jne .Lrch_stale
    cmp qword ptr [rip + g_exts + VEC_len], RT_SLOT_COUNT
    ja .Lrch_stale
    mov rax, r15
    add rax, RT_SLOT_COUNT * EXT_SIZE
    jc .Lrch_stale
    imul rax, r12, EXT_SIZE
    add r15, rax
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp [r14 + RTS_session], r13
    jne .Lrch_stale
    mov rax, [r14 + RTS_state]
    cmp rax, RTS_ACTIVE
    je 1f
    cmp rax, RTS_DRAINING
    jne .Lrch_stale
1:  test qword ptr [r14 + RTS_flags], RTSF_CHANNEL_BOUND
    jz .Lrch_stale
    cmp qword ptr [r14 + RTS_expectedKeeper], 0
    jle .Lrch_stale
    mov rdi, [r14 + RTS_ea]
    call ea_is_ready
    test eax, eax
    jz .Lrch_stale
    mov rdi, [r14 + RTS_ea]
    cmp qword ptr [rdi + PO_refs], 2
    jb .Lrch_stale
    cmp [r15 + EXT_activation_owner], rdi
    jne .Lrch_stale
    lea rax, [rdi + EA_plan]
    cmp [r15 + EXT_activation_plan], rax
    jne .Lrch_stale
    mov rdi, [r14 + RTS_hi]
    call hi_is_ready
    test eax, eax
    jz .Lrch_stale
    mov rdi, [r14 + RTS_hi]
    cmp qword ptr [rdi + PO_refs], 2
    jb .Lrch_stale
    cmp [r15 + EXT_identity_owner], rdi
    jne .Lrch_stale
    cmp dword ptr [r15 + EXT_activation_required], 1
    jne .Lrch_stale
    mov rax, [r14 + RTS_expectedKeeper]
    cmp [r15 + EXT_keeper], rax
    jne .Lrch_stale
    cmp dword ptr [r15 + EXT_startaccepted], 1
    jne .Lrch_stale
    # Unknown and known-retained closes quarantine the exact native owner.
    cmp dword ptr [r15 + EXT_host_cleanup_mask], 0
    jne .Lrch_pending
    cmp dword ptr [r15 + EXT_in], 0
    jl .Lrch_closed
    cmp qword ptr [r15 + EXT_in_closed_at], 0
    jne .Lrch_pending
    mov eax, [r15 + EXT_status]
    cmp eax, ES_RUNNING
    je 2f
    cmp eax, ES_STOPPING
    jne .Lrch_pending
2:  cmp dword ptr [r15 + EXT_retiring], 0
    jne .Lrch_pending
    cmp dword ptr [r15 + EXT_out], 0
    jl .Lrch_pending
    cmp dword ptr [r15 + EXT_host_child_in], 0
    jge .Lrch_pending
    cmp dword ptr [r15 + EXT_host_child_out], 0
    jge .Lrch_pending
    xor eax, eax
    mov rdx, r15
    EPILOGUE
.Lrch_stale:
    mov rax, -116
    jmp .Lrch_refuse
.Lrch_pending:
    mov rax, -11
    jmp .Lrch_refuse
.Lrch_closed:
    mov rax, -32
.Lrch_refuse:
    xor edx, edx
    EPILOGUE
