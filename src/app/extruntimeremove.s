# Bounded unregister keeps its terminal response owned before live mutation.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.include "app/extruntimeadmit.inc"
.include "app/extruntime.inc"
.include "app/extruntimeremove.inc"
.text
# TABLE,request80 ->status,DX0 not consumed/1 owned terminal/2 duplicate fatal.
FN rt_remove
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    call rt_admit_source_check
    test rax, rax
    jnz .Lrm_unconsumed
    mov r13, [r12 + RTQ_ordinal]
    mov rsi, r13
    mov rdi, rbx
    mov rdx, [r12 + RTQ_session]
    mov rcx, [r12 + RTQ_id]
    call rt_credit_begin
    cmp rdx, 1
    jne .Lrm_done
    imul rax, r13, RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    mov qword ptr [r14 + RTS_opKind], RTQ_UNREGISTER
    call time_ms
    mov [r14 + RTS_opStart], rax
    cmp qword ptr [r12 + RTQ_kind], RTQ_UNREGISTER
    jne .Lrm_invalid
    mov rax, [r12 + RTQ_title]
    or rax, [r12 + RTQ_titleLen]
    or rax, [r12 + RTQ_keys]
    or rax, [r12 + RTQ_keysLen]
    jnz .Lrm_invalid
    mov rax, [r12 + RTQ_keyLen]
    test rax, rax
    jz .Lrm_invalid
    cmp rax, 40
    ja .Lrm_toobig
    mov rdi, [r12 + RTQ_key]
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    cmp al, '_'
    je 2f
    sub al, '0'
    cmp al, 9
    jbe 2f
    sub al, 'a' - '0'
    cmp al, 25
    ja .Lrm_invalid
2:  inc rcx
    cmp rcx, [r12 + RTQ_keyLen]
    jb 1b
    imul rax, r13, EXT_SIZE
    add rax, [rbx + RT_stableExtBase]
    test dword ptr [rax + EXT_features], FEAT_COMMANDS
    jz .Lrm_unsupported
    cmp qword ptr [rbx + RT_barrierState], RTB_QUIESCING
    ja .Lrm_busy
    mov rcx, [rbx + RT_batchCount]
    cmp rcx, 16
    ja .Lrm_busy
    xor edx, edx
3:  cmp rdx, rcx
    jae 4f
    mov rax, [rbx + rdx*8 + RT_selected0]
    cmp rax, RT_SLOT_COUNT
    jae .Lrm_busy
    cmp rax, r13
    je .Lrm_busy
    inc rdx
    jmp 3b
4:  cmp qword ptr [r14 + RTS_nlive], 64
    ja .Lrm_busy
    mov rax, [r14 + RTS_liveHead]
    mov [rsp], rax
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], 0
    mov qword ptr [rsp + 32], 0
.Lrm_scan:
    mov rsi, [rsp]
    test rsi, rsi
    jz .Lrm_scanned
    mov rax, [rsp + 32]
    cmp rax, [r14 + RTS_nlive]
    jae .Lrm_busy
    mov rdi, rbx
    mov rdx, r13
    mov rcx, [r12 + RTQ_session]
    mov r8d, 1
    call rt_row_owner_check
    test rax, rax
    jnz .Lrm_busy
    mov rcx, [r12 + RTQ_keyLen]
    cmp [rdx + RO_keylen], rcx
    jne .Lrm_next
    lea rdi, [rdx + RO_SIZE + 2]
    add rdi, [rdx + RO_ownerlen]
    add rdi, [rdx + RO_namelen]
    mov rsi, [r12 + RTQ_key]
    xor eax, eax
5:  mov dl, [rdi + rax]
    cmp dl, [rsi + rax]
    jne .Lrm_next
    inc rax
    cmp rax, rcx
    jb 5b
    cmp qword ptr [rsp + 16], 0
    jne .Lrm_busy
    mov rax, [rsp]
    mov [rsp + 16], rax
    mov rax, [rsp + 8]
    mov [rsp + 24], rax
.Lrm_next:
    mov rax, [rsp]
    mov [rsp + 8], rax
    dec rax
    imul rax, rax, RT_ROW_SIZE
    mov rax, [rbx + rax + RT_rows + RTR_slotNext]
    mov [rsp], rax
    inc qword ptr [rsp + 32]
    jmp .Lrm_scan
.Lrm_scanned:
    mov rax, [rsp + 32]
    cmp rax, [r14 + RTS_nlive]
    jne .Lrm_busy
    cmp qword ptr [rsp + 16], 0
    je .Lrm_not_runtime
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, r13
    mov rcx, [r12 + RTQ_session]
    mov r8, [rsp + 24]
    call rt_row_unlink_check
    test rax, rax
    jnz .Lrm_busy
    mov rax, [rbx + RT_mutation]
    test rax, rax
    jle .Lrm_busy
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    je .Lrm_saturated
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + RTQ_session]
    xor ecx, ecx
    mov r8, [r14 + RTS_opStart]
    call rt_reply_freeze_check
    test rax, rax
    jnz .Lrm_busy
    # Full row and response checks precede this stores-only ownership change.
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, r13
    mov rcx, [rsp + 24]
    call rt_row_unlink_publish
    inc qword ptr [rbx + RT_mutation]
    call rt_authority_invalidate_pure
    xor r15d, r15d
    jmp .Lrm_freeze
.Lrm_saturated:
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + RTQ_session]
    mov ecx, RTRSP_BUSY
    mov r8, [r14 + RTS_opStart]
    call rt_reply_freeze_check
    test rax, rax
    jnz .Lrm_busy
    mov rdi, rbx
    call rt_table_revoke_all_pure
.Lrm_busy:
    mov r15d, RTRSP_BUSY
    jmp .Lrm_freeze
.Lrm_invalid:
    mov r15d, RTRSP_INVALID
    jmp .Lrm_freeze
.Lrm_toobig:
    mov r15d, RTRSP_TOOBIG
    jmp .Lrm_freeze
.Lrm_unsupported:
    mov r15d, RTRSP_UNSUPPORTED
    jmp .Lrm_freeze
.Lrm_not_runtime:
    mov r15d, RTRSP_NOT_RUNTIME
.Lrm_freeze:
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + RTQ_session]
    mov rcx, r15
    mov r8, [r14 + RTS_opStart]
    call rt_reply_freeze_publish
    lea rax, [rip + rt_reply_errors]
    mov rax, [rax + r15*8]
    mov edx, 1
.Lrm_done:
    EPILOGUE
.Lrm_unconsumed:
    xor edx, edx
    EPILOGUE
