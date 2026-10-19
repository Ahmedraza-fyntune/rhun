# Typed row identity and checked no-fail LIVE to DEBT ownership transfer.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntime.inc"
.include "app/extruntimeremove.inc"
.include "app/extruntimedebtscan.inc"
.text
# Held TABLE,encoded row,ordinal,session,requireLive1/0 ->0/-EINVAL,DX borrowed RO.
FN rt_row_owner_check
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    call rt_table_is_owned
    test eax, eax
    jz .Lrow_bad
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lrow_bad
    cmp r13, RT_SLOT_COUNT
    jae .Lrow_bad
    test r14, r14
    jle .Lrow_bad
    cmp r15, 1
    ja .Lrow_bad
    lea rax, [r12 - 1]
    cmp rax, RT_ROW_COUNT
    jae .Lrow_bad
    imul rax, rax, RT_ROW_SIZE
    lea r11, [rbx + rax + RT_rows]
    cmp [r11 + RTR_ordinal], r13
    jne .Lrow_bad
    cmp [r11 + RTR_session], r14
    jne .Lrow_bad
    mov eax, RTR_DEBT
    sub rax, r15
    cmp [r11 + RTR_state], rax
    jne .Lrow_bad
    mov r10, [r11 + RTR_ro]
    test r10, r10
    jz .Lrow_bad
    lea r9, [r10 - RD_SIZE]
    cmp [r9 + RD_object], r10
    jne .Lrow_bad
    cmp qword ptr [r9 + RD_kind], 5
    jne .Lrow_bad
    cmp qword ptr [r9 + RD_state], RD_ACTIVE
    jne .Lrow_bad
    cmp qword ptr [r10 + RO_refs], 0
    je .Lrow_bad
    cmp [r10 + RO_session], r14
    jne .Lrow_bad
    cmp [r10 + RO_live], r15
    jne .Lrow_bad
    cmp qword ptr [r10 + RO_incarnation], 0
    jle .Lrow_bad
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    jne .Lrow_bad
    mov rax, [rbx + RT_stableExtBase]
    test rax, rax
    jz .Lrow_bad
    imul rcx, r13, EXT_SIZE
    add rax, rcx
    jc .Lrow_bad
    cmp [r10 + RO_target], rax
    jne .Lrow_bad
    # Check exact factory extent using only fixed header fields.
    mov rax, [r10 + RO_ownerlen]
    test rax, rax
    jz .Lrow_bad
    cmp rax, RO_LIMIT
    ja .Lrow_bad
    mov rcx, [r10 + RO_namelen]
    test rcx, rcx
    jz .Lrow_bad
    cmp rcx, RO_LIMIT
    ja .Lrow_bad
    mov rdx, [r10 + RO_keylen]
    dec rdx
    cmp rdx, 39
    ja .Lrow_bad
    inc rdx
    add rcx, rdx
    add rcx, rcx
    add rax, rcx
    mov rcx, [r10 + RO_titlelen]
    cmp rcx, RO_LIMIT
    ja .Lrow_bad
    add rax, rcx
    mov rcx, [r10 + RO_keyslen]
    cmp rcx, RO_LIMIT
    ja .Lrow_bad
    add rax, rcx
    add rax, RO_SIZE + 7
    cmp [r10 + RO_allocsize], rax
    jne .Lrow_bad
    add rax, RD_SIZE
    cmp [r9 - 8], rax
    jne .Lrow_bad
    mov [rsp], r10
    mov [rsp + 8], rax
    mov rdi, r9
    call mem_capacity
    cmp rax, [rsp + 8]
    jb .Lrow_bad
    mov rdx, [rsp]
    xor eax, eax
    EPILOGUE
.Lrow_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# Held TABLE,encoded row,ordinal,session,local previous ->0/-EINVAL.
FN rt_row_unlink_check
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov r8d, 1
    call rt_row_owner_check
    test rax, rax
    jnz .Lruc_done
    imul rax, r13, RT_SLOT_SIZE
    lea r9, [rbx + rax + RT_slots]
    cmp [r9 + RTS_session], r14
    jne .Lruc_bad
    mov rax, [r9 + RTS_state]
    cmp rax, RTS_ACTIVE
    je 1f
    cmp rax, RTS_DRAINING
    jne .Lruc_bad
1:  mov rax, [r9 + RTS_nlive]
    dec rax
    cmp rax, 64
    jae .Lruc_bad
    mov rax, [rbx + RT_nlive]
    dec rax
    cmp rax, RT_ROW_COUNT
    jae .Lruc_bad
    cmp qword ptr [r9 + RTS_ndebt], RT_ROW_COUNT
    jae .Lruc_bad
    lea rax, [r12 - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r10, [rbx + rax + RT_rows]
    mov rcx, [r10 + RTR_next]
    mov rdx, [r10 + RTR_prev]
    cmp rcx, RT_ROW_COUNT
    ja .Lruc_bad
    cmp rdx, RT_ROW_COUNT
    ja .Lruc_bad
    cmp rcx, r12
    je .Lruc_bad
    cmp rdx, r12
    je .Lruc_bad
    test rcx, rcx
    jz 2f
    cmp rcx, rdx
    je .Lruc_bad
    lea rax, [rcx - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_LIVE
    jne .Lruc_bad
    cmp [r8 + RTR_prev], r12
    jne .Lruc_bad
    jmp 3f
2:  cmp [rbx + RT_liveTail], r12
    jne .Lruc_bad
3:  test rdx, rdx
    jz 4f
    lea rax, [rdx - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_LIVE
    jne .Lruc_bad
    cmp [r8 + RTR_next], r12
    jne .Lruc_bad
    jmp 5f
4:  cmp [rbx + RT_liveHead], r12
    jne .Lruc_bad
5:  mov rcx, [r10 + RTR_slotNext]
    cmp rcx, RT_ROW_COUNT
    ja .Lruc_bad
    cmp rcx, r12
    je .Lruc_bad
    mov [rsp], rcx
    test rcx, rcx
    jz 6f
    mov rdi, rbx
    mov rsi, rcx
    mov rdx, r13
    mov rcx, r14
    mov r8d, 1
    call rt_row_owner_check
    test rax, rax
    jnz .Lruc_done
6:  test r15, r15
    jz 7f
    cmp r15, r12
    je .Lruc_bad
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r13
    mov rcx, r14
    mov r8d, 1
    call rt_row_owner_check
    test rax, rax
    jnz .Lruc_done
    lea rax, [r15 - 1]
    imul rax, rax, RT_ROW_SIZE
    cmp [rbx + rax + RT_rows + RTR_slotNext], r12
    jne .Lruc_bad
    cmp [rsp], r15
    je .Lruc_bad
    jmp 8f
7:  imul rax, r13, RT_SLOT_SIZE
    cmp [rbx + rax + RT_slots + RTS_liveHead], r12
    jne .Lruc_bad
8:  mov rsi, [rbx + RT_debtHead]
    mov rax, [rbx + RT_debtCursor]
    test rsi, rsi
    jnz 9f
    test rax, rax
    jnz .Lruc_bad
    xor eax, eax
    jmp .Lruc_done
9:  cmp rsi, RT_ROW_COUNT
    ja .Lruc_bad
    test rax, rax
    jz .Lruc_bad
    cmp rax, RT_ROW_COUNT
    ja .Lruc_bad
    dec rax
    imul rax, rax, RT_ROW_SIZE
    cmp qword ptr [rbx + rax + RT_rows + RTR_state], RTR_DEBT
    jne .Lruc_bad
    lea rax, [rsi - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r8, [rbx + rax + RT_rows]
    cmp qword ptr [r8 + RTR_state], RTR_DEBT
    jne .Lruc_bad
    cmp qword ptr [r8 + RTR_prev], 0
    jne .Lruc_bad
    mov rdi, rbx
    mov rsi, [rbx + RT_debtHead]
    call rt_debt_row_check
    jmp .Lruc_done
.Lruc_bad:
    mov rax, -22
.Lruc_done:
    EPILOGUE

# VOID immediately after full check, held TABLE,row,ordinal,local previous.
FN rt_row_unlink_publish
    lea rax, [rsi - 1]
    imul rax, rax, RT_ROW_SIZE
    lea r10, [rdi + rax + RT_rows]
    imul rax, rdx, RT_SLOT_SIZE
    lea r9, [rdi + rax + RT_slots]
    mov rax, [r10 + RTR_ro]
    mov qword ptr [rax + RO_live], 0
    mov r8, [r10 + RTR_next]
    mov r11, [r10 + RTR_prev]
    test r8, r8
    jz 1f
    lea rax, [r8 - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rdi + rax + RT_rows + RTR_prev], r11
    jmp 2f
1:  mov [rdi + RT_liveTail], r11
2:  test r11, r11
    jz 3f
    lea rax, [r11 - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rdi + rax + RT_rows + RTR_next], r8
    jmp 4f
3:  mov [rdi + RT_liveHead], r8
4:  mov r8, [r10 + RTR_slotNext]
    test rcx, rcx
    jz 5f
    lea rax, [rcx - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rdi + rax + RT_rows + RTR_slotNext], r8
    jmp 6f
5:  mov [r9 + RTS_liveHead], r8
6:  dec qword ptr [rdi + RT_nlive]
    dec qword ptr [r9 + RTS_nlive]
    inc qword ptr [r9 + RTS_ndebt]
    mov r8, [rdi + RT_debtHead]
    mov [r10 + RTR_next], r8
    mov qword ptr [r10 + RTR_prev], 0
    mov qword ptr [r10 + RTR_debtBackoff], 0
    mov qword ptr [r10 + RTR_debtDue], 0
    mov qword ptr [r10 + RTR_state], RTR_DEBT
    mov qword ptr [rdi + RT_debtScanValid], 0
    mov qword ptr [rdi + RT_debtScanDirty], 1
    test r8, r8
    jz 7f
    lea rax, [r8 - 1]
    imul rax, rax, RT_ROW_SIZE
    mov [rdi + rax + RT_rows + RTR_prev], rsi
    jmp 8f
7:  mov [rdi + RT_debtCursor], rsi
8:  mov [rdi + RT_debtHead], rsi
    ret
