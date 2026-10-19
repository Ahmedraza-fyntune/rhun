# Bounded partial-owner retirement. Accepted common refs outlive this context.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extdiscoveryalloc.inc"
.text
# ctx,now -> relative delay, -1 no timed/progress work. Pure fixed slot scan.
FN pd_alloc_timeout
    test rdi, rdi
    jz .Lpdr_invalid
    test rsi, rsi
    js .Lpdr_invalid
    cmp qword ptr [rdi + DIA_state], DIA_EMPTY
    ja .Lpdr_invalid
    mov r8, -1
    xor ecx, ecx
1:  mov rax, rcx
    shl rax, 6
    lea rax, [rdi + rax + DIA_slots]
    cmp qword ptr [rax + DTS_raw], 0
    je 3f
    cmp qword ptr [rax + DTS_state], DTS_RETAINED
    jne .Lpdr_due
    mov rdx, [rax + DTS_due]
    sub rdx, rsi
    jle .Lpdr_due
    cmp r8, -1
    je 2f
    cmp rdx, r8
    jae 3f
2:  mov r8, rdx
3:  inc rcx
    cmp rcx, 16
    jb 1b
    mov rcx, [rdi + DIA_blocked]
    test cl, 1
    jnz 4f
    cmp qword ptr [rdi + DIA_gp], 0
    jne .Lpdr_due
4:  test cl, 2
    jnz 5f
    cmp qword ptr [rdi + DIA_ep], 0
    jne .Lpdr_due
5:  test cl, 4
    jnz 6f
    cmp qword ptr [rdi + DIA_eo], 0
    jne .Lpdr_due
6:  mov rax, r8
    ret
.Lpdr_due:
    xor eax, eax
    ret

# ctx,out64,now. Status reports ownership, not common queue quiescence.
FN pd_alloc_status
    test rsi, rsi
    jz .Lpdr_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rdx
    call pd_alloc_timeout
    cmp rax, -1
    jl .Lpdr_status_exit
    mov r13, rax
    mov rax, [rbx + DIA_state]
    mov [r12], rax
    mov rax, [rbx + DIA_primary]
    mov [r12 + 8], rax
    mov rax, [rbx + DIA_cleanup]
    mov [r12 + 16], rax
    mov rax, [rbx + DIA_active]
    mov [r12 + 24], rax
    xor eax, eax
    cmp qword ptr [rbx + DIA_gp], 0
    je 1f
    or eax, 1
1:  cmp qword ptr [rbx + DIA_ep], 0
    je 2f
    or eax, 2
2:  cmp qword ptr [rbx + DIA_eo], 0
    je 3f
    or eax, 4
3:  mov [r12 + 32], rax
    xor r14d, r14d
    xor r15d, r15d
    xor ecx, ecx
4:  mov rax, rcx
    shl rax, 6
    lea rax, [rbx + rax + DIA_slots]
    cmp qword ptr [rax + DTS_state], DTS_RETAINED
    jne 7f
    mov rdx, [rax + DTS_due]
    test r14, r14
    jz 5f
    cmp rdx, r14
    jae 6f
5:  mov r14, rdx
6:  mov rdx, [rax + DTS_logical]
    test r15, r15
    jz 8f
    cmp rdx, r15
    jae 7f
8:  mov r15, rdx
7:  inc rcx
    cmp rcx, 16
    jb 4b
    mov [r12 + 40], r14
    mov [r12 + 48], r15
    xor ecx, ecx
    test r13, r13
    jz 9f
    jg 10f
    cmp qword ptr [rbx + DIA_blocked], 0
    je 9f
    mov ecx, 2
    jmp 9f
10: mov ecx, 1
9:  mov [r12 + 56], rcx
    xor eax, eax
.Lpdr_status_exit:
    EPILOGUE

# ctx,negative diagnostic. No native pointer follows.
FN pd_alloc_note_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + DIA_cleanup], 0
    jne 1f
    mov [rdi + DIA_cleanup], rsi
1:  ret

# ctx. Drop its EO construction ref only after an EP exists.
FN pd_alloc_drop_eo_root
    test rdi, rdi
    jz .Lpdr_invalid_result
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpdr_invalid_result
    cmp qword ptr [rdi + DIA_ep], 0
    je .Lpdr_invalid_result
    test qword ptr [rdi + DIA_blocked], 4
    jnz .Lpdr_invalid_result
    mov rax, [rdi + DIA_eo]
    test rax, rax
    jz .Lpdr_invalid_result
    mov rcx, [rdi + DIA_ep]
    cmp [rcx + PO_eo], rax
    jne .Lpdr_invalid_result
    mov rcx, [rdi + DIA_gp]
    test rcx, rcx
    jz 1f
    cmp [rcx + PO_eo], rax
    jne .Lpdr_invalid_result
1:  PROLOGUE
    mov rbx, rdi
    mov rdi, rax
    call ext_prepare_owner_release_deferred
    mov r12, rax
    mov r13, rdx
    cmp rdx, 1
    je 2f
    or qword ptr [rbx + DIA_blocked], 4
    mov qword ptr [rbx + DIA_state], DIA_ABORT
    test r12, r12
    js 3f
    mov r12, -EV_BAD_PREPARE
    jmp 3f
2:  mov qword ptr [rbx + DIA_eo], 0
3:  mov rdi, rbx
    mov rsi, r12
    call pd_alloc_note_cleanup
    mov rax, r12
    mov rdx, r13
    EPILOGUE

# ctx,now. One actual raw free OR one deferred root drop, never both.
FN pd_alloc_retire_step
    test rdi, rdi
    jz .Lpdr_invalid_result
    test rsi, rsi
    js .Lpdr_invalid_result
    cmp qword ptr [rdi + DIA_state], DIA_EMPTY
    ja .Lpdr_invalid_result
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + DIA_state], DIA_EMPTY
    je .Lpdr_finish
    mov qword ptr [rbx + DIA_state], DIA_ABORT
    mov r13, [rbx + DIA_cursor]
    xor r14d, r14d
1:  mov rax, r13
    shl rax, 6
    lea r15, [rbx + rax + DIA_slots]
    cmp qword ptr [r15 + DTS_raw], 0
    je 3f
    cmp qword ptr [r15 + DTS_state], DTS_RETAINED
    jne 2f
    cmp [r15 + DTS_due], r12
    jg 3f
2:  inc r13
    and r13d, 15
    mov [rbx + DIA_cursor], r13
    mov rdi, [r15 + DTS_raw]
    call prep_cleanup_free
    mov rdi, rbx
    mov rsi, rax
    call pd_alloc_note_cleanup
    cmp rdx, 1
    je .Lpdr_raw_consumed
    mov eax, 16
    cmp qword ptr [r15 + DTS_state], DTS_RETAINED
    jne 4f
    mov rax, [r15 + DTS_logical]
    add rax, rax
    cmp rax, 1000
    jbe 4f
    mov eax, 1000
4:  mov [r15 + DTS_logical], rax
    mov qword ptr [r15 + DTS_state], DTS_RETAINED
    add rax, r12
    jno 5f
    mov rax, 0x7fffffffffffffff
5:  mov [r15 + DTS_due], rax
    jmp .Lpdr_finish
3:  inc r13
    and r13d, 15
    inc r14
    cmp r14, 16
    jb 1b
    mov r13d, DIA_gp
    mov r14d, 1
    mov rdi, [rbx + DIA_gp]
    test rdi, rdi
    jz 6f
    test qword ptr [rbx + DIA_blocked], 1
    jnz 6f
    call grammar_prepare_release_deferred
    jmp .Lpdr_root_result
6:  mov r13d, DIA_ep
    mov r14d, 2
    mov rdi, [rbx + DIA_ep]
    test rdi, rdi
    jz 7f
    test qword ptr [rbx + DIA_blocked], 2
    jnz 7f
    call ext_prepare_release_deferred
    jmp .Lpdr_root_result
7:  mov r13d, DIA_eo
    mov r14d, 4
    mov rdi, [rbx + DIA_eo]
    test rdi, rdi
    jz .Lpdr_finish
    test qword ptr [rbx + DIA_blocked], 4
    jnz .Lpdr_finish
    call ext_prepare_owner_release_deferred
.Lpdr_root_result:
    cmp rdx, 1
    jne 8f
    mov qword ptr [rbx + r13], 0
    cmp r13, DIA_ep
    jne 9f
    mov [rsp], rax
    mov rdi, rbx
    call pd_alloc_clear_bindings
    mov rax, [rsp]
    jmp 9f
8:  or [rbx + DIA_blocked], r14
    test rax, rax
    js 9f
    mov rax, -EV_BAD_PREPARE
9:  mov rdi, rbx
    mov rsi, rax
    call pd_alloc_note_cleanup
    jmp .Lpdr_finish
.Lpdr_raw_consumed:
    mov rax, [r15 + DTS_charge]
    sub [rip + discovery_extra_charge], rax
    mov rdi, rbx
    mov rsi, r15
    call pd_alloc_clear_slot
.Lpdr_finish:
    mov rax, [rbx + DIA_active]
    or rax, [rbx + DIA_gp]
    or rax, [rbx + DIA_ep]
    or rax, [rbx + DIA_eo]
    jnz 1f
    mov qword ptr [rbx + DIA_state], DIA_EMPTY
1:  mov rdi, rbx
    lea rsi, [rsp]
    mov rdx, r12
    call pd_alloc_status
    mov rcx, [rsp + 56]
    mov rdx, [rbx + DIA_cleanup]
    xor eax, eax
    cmp qword ptr [rbx + DIA_state], DIA_EMPTY
    setne al
    EPILOGUE

.Lpdr_invalid_result:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
.Lpdr_invalid:
    mov rax, -22
    ret
