# Allocation-free action revocation. Native/UI cleanup remains separately owned.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.text
# table,ordinal,session. No prompt owner is manufactured by this hook.
FN rt_prompt_action_revoke_pure
    xor r9d, r9d
    jmp rt_prompt_revoke_owned
FN rt_prompt_revoke_all_pure
    mov r9d, 1
rt_prompt_revoke_owned:
    mov r8, [rdi + RT_promptActive]
    test r8, r8
    jz 9f
    cmp qword ptr [r8 - RD_PO_BACK + RD_kind], RT_KIND
    jne 9f
    mov rax, [r8 - RD_PO_BACK + RD_state]
    test eax, RDF_STATE_MASK
    jnz 9f
    test eax, RDF_PO
    jz 9f
    cmp qword ptr [r8 + PO_refs], 0
    je 9f
    cmp qword ptr [r8 - AO_SIZE + AO_charge], RTP_HEADER_SIZE + RTP_FRAME_CAP + RD_PO_BACK + 16
    jb 9f
    cmp qword ptr [r8 + RTP_role], RT_PROMPT_ROLE
    jne 9f
    test r9d, r9d
    jnz 1f
    cmp [r8 + RTP_ordinal], rsi
    jne 9f
    cmp [r8 + RTP_session], rdx
    jne 9f
1:  or qword ptr [r8 + RTP_flags], RTPF_ACTION_REVOKED
9:  ret
