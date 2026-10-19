# Actual collected native ownership is distinct from action/channel eligibility.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/taskauth.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.text
# Retained TABLE,ordinal,session -> AX0/-errno, DX exact EXT only on proof.
FN rt_session_channel_quiet_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, RT_SLOT_COUNT
    jae .Lrcq_stale
    test r13, r13
    jle .Lrcq_stale
    call rt_reply_table_check
    test rax, rax
    jnz .Lrcq_stale
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrcq_stale
    mov r15, [rbx + RT_stableExtBase]
    test r15, r15
    jz .Lrcq_stale
    cmp [rip + g_exts + VEC_ptr], r15
    jne .Lrcq_stale
    cmp qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    jne .Lrcq_stale
    cmp qword ptr [rip + g_exts + VEC_len], RT_SLOT_COUNT
    ja .Lrcq_stale
    mov rax, r15
    add rax, RT_SLOT_COUNT * EXT_SIZE
    jc .Lrcq_stale
    imul rax, r12, EXT_SIZE
    add r15, rax
    imul rax, r12, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    cmp [r14 + RTS_session], r13
    jne .Lrcq_stale
    cmp qword ptr [r14 + RTS_state], RTS_DRAINING
    jne .Lrcq_stale
    mov rax, [r14 + RTS_flags]
    and eax, RTSF_STOP_REQUIRED | RTSF_CHANNEL_BOUND
    cmp eax, RTSF_STOP_REQUIRED | RTSF_CHANNEL_BOUND
    jne .Lrcq_stale
    cmp qword ptr [r14 + RTS_expectedKeeper], 0
    jle .Lrcq_stale
    mov rdi, [r14 + RTS_ea]
    call ea_is_ready
    test eax, eax
    jz .Lrcq_stale
    mov rdi, [r14 + RTS_ea]
    mov rax, [r15 + EXT_activation_owner]
    test rax, rax
    jz .Lrcq_ea_taken
    cmp rax, rdi
    jne .Lrcq_stale
    cmp qword ptr [rdi + PO_refs], 2
    jb .Lrcq_stale
    lea rax, [rdi + EA_plan]
    cmp [r15 + EXT_activation_plan], rax
    jne .Lrcq_stale
    jmp .Lrcq_hi
.Lrcq_ea_taken:
    cmp qword ptr [r15 + EXT_activation_plan], 0
    jne .Lrcq_stale
.Lrcq_hi:
    mov rdi, [r14 + RTS_hi]
    call hi_is_ready
    test eax, eax
    jz .Lrcq_stale
    mov rdi, [r14 + RTS_hi]
    mov rax, [r15 + EXT_identity_owner]
    test rax, rax
    jz .Lrcq_native
    cmp rax, rdi
    jne .Lrcq_stale
    cmp qword ptr [rdi + PO_refs], 2
    jb .Lrcq_stale
.Lrcq_native:
    mov rdi, r15
    call ext_host_native_quiet
    test rax, rax
    jnz .Lrcq_wait
    mov eax, [r15 + EXT_start_armed]
    or eax, [r15 + EXT_wait_slot]
    or eax, [r15 + EXT_restart]
    jnz .Lrcq_wait
    # Accepted HELLO is history. A checked host take may already have consumed it.
    xor eax, eax
    mov rdx, r15
    EPILOGUE
.Lrcq_stale:
    mov rax, -116
    jmp .Lrcq_refuse
.Lrcq_wait:
    mov rax, -11
.Lrcq_refuse:
    xor edx, edx
    EPILOGUE
