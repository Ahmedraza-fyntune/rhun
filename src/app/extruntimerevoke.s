# DRAINING rows lose visibility in bounded slices before later checked retirement.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeremove.inc"
.text
# TABLE,now,budget1..16 ->0 no progress/1 progress/-errno,DXvisited,CX0.
FN rt_rows_revoke_step
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    xor r15d, r15d
    test r12, r12
    js .Lrrv_invalid
    lea rax, [r13 - 1]
    cmp rax, 16
    jae .Lrrv_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrrv_invalid
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrrv_invalid
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrrv_invalid
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrrv_invalid
    cmp qword ptr [rbx + RT_revokeCursor], RT_SLOT_COUNT
    jae .Lrrv_invalid
.Lrrv_loop:
    cmp r14, r13
    jae .Lrrv_finish
    mov rsi, [rbx + RT_revokeCursor]
    mov [rsp], rsi
    lea rax, [rsi + 1]
    cmp rax, RT_SLOT_COUNT
    jb 1f
    xor eax, eax
1:  mov [rbx + RT_revokeCursor], rax
    inc r14
    imul rax, rsi, RT_SLOT_SIZE
    lea r8, [rbx + rax + RT_slots]
    cmp qword ptr [r8 + RTS_state], RTS_DRAINING
    jne .Lrrv_loop
    mov rax, [r8 + RTS_liveHead]
    test rax, rax
    jnz 2f
    cmp qword ptr [r8 + RTS_nlive], 0
    jne .Lrrv_corrupt
    jmp .Lrrv_loop
2:  mov [rsp + 8], rax
    mov rcx, [r8 + RTS_session]
    mov rdi, rbx
    mov rdx, rsi
    mov rsi, rax
    xor r8d, r8d
    call rt_row_unlink_check
    test rax, rax
    jnz .Lrrv_corrupt
    mov rax, [rbx + RT_mutation]
    test rax, rax
    jle .Lrrv_corrupt
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jne 3f
    test qword ptr [rbx + RT_flags], RTF_CLOSED
    jnz 3f
    mov rdi, rbx
    call rt_table_revoke_all_pure
3:  mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [rsp]
    xor ecx, ecx
    call rt_row_unlink_publish
    mov rax, 0x7fffffffffffffff
    cmp [rbx + RT_mutation], rax
    je 4f
    inc qword ptr [rbx + RT_mutation]
    call rt_authority_invalidate_pure
4:  mov r15d, 1
    jmp .Lrrv_loop
.Lrrv_finish:
    mov rax, r15
    jmp .Lrrv_return
.Lrrv_corrupt:
    mov rax, -71
    jmp .Lrrv_return
.Lrrv_invalid:
    mov rax, -22
.Lrrv_return:
    mov rdx, r14
    xor ecx, ecx
    EPILOGUE
