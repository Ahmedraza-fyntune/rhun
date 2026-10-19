# Physical row reuse follows checked ownership consumption, independently of replies.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntime.inc"
.include "app/extruntimeremove.inc"
.include "app/extruntimedebtscan.inc"
.text
# Internal preflight: held TABLE,encoded DEBT ->0/-EINVAL. No mutation.
FN rt_debt_row_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rax, [r12 - 1]
    cmp rax, RT_ROW_COUNT
    jae .Lrdc_bad
    imul rax, rax, RT_ROW_SIZE
    lea r13, [rbx + rax + RT_rows]
    mov rdx, [r13 + RTR_ordinal]
    mov rcx, [r13 + RTR_session]
    xor r8d, r8d
    call rt_row_owner_check
    test rax, rax
    jnz .Lrdc_done
    mov rax, [rbx + RT_debtHead]
    dec rax
    cmp rax, RT_ROW_COUNT
    jae .Lrdc_bad
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_DEBT
    jne .Lrdc_bad
    cmp qword ptr [r8 + RTR_prev], 0
    jne .Lrdc_bad
    imul rax, [r13 + RTR_ordinal], RT_SLOT_SIZE
    lea r14, [rbx + rax + RT_slots]
    mov rax, [r13 + RTR_session]
    cmp [r14 + RTS_session], rax
    jne .Lrdc_bad
    mov rax, [r14 + RTS_state]
    cmp rax, RTS_ACTIVE
    je 1f
    cmp rax, RTS_DRAINING
    jne .Lrdc_bad
1:  mov rax, [r14 + RTS_ndebt]
    dec rax
    cmp rax, RT_ROW_COUNT
    jae .Lrdc_bad
    cmp qword ptr [r13 + RTR_debtBackoff], 1000
    ja .Lrdc_bad
    mov rax, [r13 + RTR_debtDue]
    test rax, rax
    jns 2f
    cmp rax, -1
    jne .Lrdc_bad
2:  mov rcx, [r13 + RTR_next]
    mov rdx, [r13 + RTR_prev]
    cmp rcx, RT_ROW_COUNT
    ja .Lrdc_bad
    cmp rdx, RT_ROW_COUNT
    ja .Lrdc_bad
    cmp rcx, r12
    je .Lrdc_bad
    cmp rdx, r12
    je .Lrdc_bad
    test rcx, rcx
    jz 3f
    cmp rcx, rdx
    je .Lrdc_bad
    lea rax, [rcx - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_DEBT
    jne .Lrdc_bad
    cmp [r8 + RTR_prev], r12
    jne .Lrdc_bad
3:  test rdx, rdx
    jz 4f
    lea rax, [rdx - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_DEBT
    jne .Lrdc_bad
    cmp [r8 + RTR_next], r12
    jne .Lrdc_bad
    jmp 5f
4:  cmp [rbx + RT_debtHead], r12
    jne .Lrdc_bad
5:  mov rax, [rbx + RT_freeHead]
    test rax, rax
    jz .Lrdc_ok
    dec rax
    cmp rax, RT_ROW_COUNT
    jae .Lrdc_bad
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    mov rax, [r8 + RTR_ro]
    or rax, [r8 + RTR_state]
    or rax, [r8 + RTR_ordinal]
    or rax, [r8 + RTR_session]
    or rax, [r8 + RTR_prev]
    or rax, [r8 + RTR_acceptSequence]
    or rax, [r8 + RTR_slotNext]
    jnz .Lrdc_bad
    cmp qword ptr [r8 + RTR_next], RT_ROW_COUNT
    ja .Lrdc_bad
    mov rax, [rbx + RT_freeHead]
    cmp [r8 + RTR_next], rax
    je .Lrdc_bad
    mov rax, [r8 + RTR_next]
    test rax, rax
    jz .Lrdc_ok
    dec rax
    imul rax, rax, RT_ROW_SIZE
    mov rcx, [rbx + rax + RT_rows + RTR_state]
    or rcx, [rbx + rax + RT_rows + RTR_ro]
    jnz .Lrdc_bad
.Lrdc_ok:
    xor eax, eax
    jmp .Lrdc_done
.Lrdc_bad:
    mov rax, -22
.Lrdc_done:
    EPILOGUE

# TABLE,encoded row,expected session ->0/-EINVAL. Only genuine event/explicit retry.
FN rt_debt_wake
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call rt_table_is_owned
    test eax, eax
    jz .Lrdw_bad
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrdw_bad
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrdw_bad
    mov rdi, rbx
    mov rsi, r12
    call rt_debt_row_check
    test rax, rax
    jnz .Lrdw_bad
    dec r12
    imul r12, r12, RT_ROW_SIZE
    lea r8, [rbx + r12 + RT_rows]
    cmp [r8 + RTR_session], r13
    jne .Lrdw_bad
    mov qword ptr [r8 + RTR_debtDue], 0
    mov qword ptr [rbx + RT_debtScanValid], 0
    mov qword ptr [rbx + RT_debtScanDirty], 1
    xor eax, eax
    EPILOGUE
.Lrdw_bad:
    mov rax, -22
    EPILOGUE

# TABLE,now,budget1..16 ->0 no progress/1 progress/-errno,DXvisited,CXslice due.
FN rt_debt_step
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    xor r15d, r15d
    mov qword ptr [rsp], 0
    test r12, r12
    js .Lrds_invalid
    lea rax, [r13 - 1]
    cmp rax, 16
    jae .Lrds_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrds_invalid
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrds_invalid
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Lrds_invalid
    mov rax, [rbx + RT_debtCursor]
    mov [rsp + 8], rax
    cmp qword ptr [rbx + RT_debtHead], 0
    jne .Lrds_loop
    test rax, rax
    jnz .Lrds_corrupt
    jmp .Lrds_finish
.Lrds_loop:
    cmp r14, r13
    jae .Lrds_finish
    mov rsi, [rbx + RT_debtCursor]
    test rsi, rsi
    jz .Lrds_corrupt
    mov [rsp + 16], rsi
    mov rdi, rbx
    call rt_debt_row_check
    test rax, rax
    jnz .Lrds_corrupt
    mov rsi, [rsp + 16]
    lea rax, [rsi - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    mov [rsp + 24], r8
    mov rax, [r8 + RTR_next]
    mov [rsp + 32], rax
    mov rcx, [r8 + RTR_prev]
    mov [rsp + 40], rcx
    test rax, rax
    jnz 1f
    mov rax, [rbx + RT_debtHead]
1:  mov [rbx + RT_debtCursor], rax
    inc r14
    mov rax, [r8 + RTR_debtDue]
    cmp rax, -1
    je .Lrds_next
    cmp rax, r12
    ja .Lrds_due
    mov rdi, [r8 + RTR_ro]
    call ext_runtime_release_deferred
    mov [rsp + 48], rax
    cmp rdx, 1
    je .Lrds_consumed
    # A refused reference remains in exactly this row with its own retry clock.
    mov r8, [rsp + 24]
    mov rax, [r8 + RTR_debtBackoff]
    test rax, rax
    jnz 2f
    mov eax, 8
2:  add rax, rax
    cmp rax, 1000
    jbe 3f
    mov eax, 1000
3:  mov [r8 + RTR_debtBackoff], rax
    mov qword ptr [rbx + RT_debtScanValid], 0
    mov qword ptr [rbx + RT_debtScanDirty], 1
    add rax, r12
    jo 4f
    cmp rax, r12
    jbe 4f
    mov [r8 + RTR_debtDue], rax
    mov r15d, 1
    jmp .Lrds_due
4:  mov qword ptr [r8 + RTR_debtDue], -1
    mov r15d, 1
    jmp .Lrds_next
.Lrds_consumed:
    # Only TABLE and saved numeric neighbors are read after consumption.
    test rax, rax
    jns 5f
    lea rdi, [rbx - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
5:  mov r8, [rsp + 24]
    mov qword ptr [r8 + RTR_ro], 0
    mov r9, [rsp + 32]
    mov r10, [rsp + 40]
    test r9, r9
    jz 6f
    lea rax, [r9 - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rbx + rax + RT_rows + RTR_prev], r10
6:  test r10, r10
    jz 7f
    lea rax, [r10 - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rbx + rax + RT_rows + RTR_next], r9
    jmp 8f
7:  mov [rbx + RT_debtHead], r9
8:  mov rax, [rsp + 16]
    cmp [rbx + RT_debtCursor], rax
    jne 9f
    mov rax, r9
    test rax, rax
    jnz 10f
    mov rax, [rbx + RT_debtHead]
10: mov [rbx + RT_debtCursor], rax
9:  mov rax, [r8 + RTR_ordinal]
    imul rax, rax, RT_SLOT_SIZE
    dec qword ptr [rbx + rax + RT_slots + RTS_ndebt]
    mov rax, [rbx + RT_freeHead]
    mov [r8 + RTR_next], rax
    mov qword ptr [r8 + RTR_ordinal], 0
    mov qword ptr [r8 + RTR_session], 0
    mov qword ptr [r8 + RTR_prev], 0
    mov qword ptr [r8 + RTR_acceptSequence], 0
    mov qword ptr [r8 + RTR_state], RTR_FREE
    mov qword ptr [rbx + RT_debtScanValid], 0
    mov qword ptr [rbx + RT_debtScanDirty], 1
    mov qword ptr [r8 + RTR_slotNext], 0
    mov rax, [rsp + 16]
    mov [rbx + RT_freeHead], rax
    mov r15d, 1
    cmp qword ptr [rbx + RT_debtHead], 0
    je .Lrds_finish
    jmp .Lrds_next
.Lrds_due:
    mov rcx, [rsp]
    test rcx, rcx
    jz 11f
    cmp rcx, rax
    jbe .Lrds_next
11: mov [rsp], rax
.Lrds_next:
    mov rax, [rbx + RT_debtCursor]
    cmp rax, [rsp + 8]
    jne .Lrds_loop
.Lrds_finish:
    mov rax, r15
    jmp .Lrds_return
.Lrds_corrupt:
    mov rax, -71
    jmp .Lrds_return
.Lrds_invalid:
    mov rax, -22
.Lrds_return:
    mov rdx, r14
    mov rcx, [rsp]
    EPILOGUE
