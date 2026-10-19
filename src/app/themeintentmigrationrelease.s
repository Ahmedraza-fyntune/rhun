# Bounded caller-owned TCM retirement. Exact ownership survives every failed checked free.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintentmigration.inc"
.text
tcm_cleanup:
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + TCM_cleanup], 0
    jne 1f
    mov [rdi + TCM_cleanup], rsi
1:  ret
# release(plan,now)->stickycleanup/consumed/reason. One actual release at most per call.
FN theme_intent_migration_release
    test rdi, rdi
    jz .Ltcmr_empty
    test rsi, rsi
    js .Ltcmr_bad_leaf
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + TCM_state], TCM_RETIRING
    je .Ltcmr_reservations
    cmp qword ptr [rbx + TCM_state], TCM_READY
    je 1f
    cmp qword ptr [rbx + TCM_state], TCM_COMMITTED
    jne .Ltcmr_bad
1:  mov qword ptr [rbx + TCM_state], TCM_RETIRING
.Ltcmr_reservations:
    # Precommit reservations carry no ownership of the old global allocations.
    xor r13d, r13d
2:  cmp r13, 3
    jae .Ltcmr_scan_begin
    bt qword ptr [rbx + TCM_reservations], r13
    jnc 3f
    mov rdi, [rbx + TCM_old_charge + r13*8]
    call tc_charge_release
    test rax, rax
    js .Ltcmr_reserve_error
    btr qword ptr [rbx + TCM_reservations], r13
    mov qword ptr [rbx + TCM_old_charge + r13*8], 0
3:  inc r13
    jmp 2b
.Ltcmr_reserve_error:
    mov rdi, rbx
    mov rsi, rax
    call tcm_cleanup
    jmp .Ltcmr_progress
.Ltcmr_scan_begin:
    cmp qword ptr [rbx + TCM_owned], 0
    je .Ltcmr_self
    xor r14d, r14d
.Ltcmr_scan:
    cmp r14, 8
    jae .Ltcmr_backoff
    mov r13, [rbx + TCM_cursor]
    inc qword ptr [rbx + TCM_cursor]
    and qword ptr [rbx + TCM_cursor], 7
    inc r14
    bt qword ptr [rbx + TCM_owned], r13
    jnc .Ltcmr_scan
    cmp r12, [rbx + TCM_due + r13*8]
    jl .Ltcmr_scan
    cmp r13, 6
    jae .Ltcmr_ti
    cmp r13, 3
    jae 4f
    mov rdi, [rbx + TCM_new + r13*8]
    jmp 5f
4:  lea rcx, [r13 - 3]
    mov rdi, [rbx + TCM_old + rcx*8]
5:  call tc_free
    jmp .Ltcmr_attempted
.Ltcmr_ti:
    mov rdi, [rbx + TCM_new_ti]
    cmp r13, 6
    je 6f
    mov rdi, [rbx + TCM_old_ti]
6:  call theme_intent_release
.Ltcmr_attempted:
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    call tcm_cleanup
    test r15, r15
    jz .Ltcmr_retained
    btr qword ptr [rbx + TCM_owned], r13
    mov qword ptr [rbx + TCM_due + r13*8], 0
    mov qword ptr [rbx + TCM_delay + r13*8], 0
    cmp r13, 6
    jae .Ltcmr_clear_ti
    cmp r13, 3
    jae 7f
    mov qword ptr [rbx + TCM_new + r13*8], 0
    jmp .Ltcmr_progress
7:  lea rcx, [r13 - 3]
    mov qword ptr [rbx + TCM_old + rcx*8], 0
    jmp .Ltcmr_progress
.Ltcmr_clear_ti:
    cmp r13, 6
    jne 8f
    mov qword ptr [rbx + TCM_new_ti], 0
    jmp .Ltcmr_progress
8:  mov qword ptr [rbx + TCM_old_ti], 0
    jmp .Ltcmr_progress
.Ltcmr_retained:
    mov rdi, rbx
    mov rsi, -5
    call tcm_cleanup
    mov rax, [rbx + TCM_delay + r13*8]
    call tcm_delay
    mov [rbx + TCM_delay + r13*8], rax
    add rax, r12
    jno 9f
    mov rax, 9223372036854775807
9:  mov [rbx + TCM_due + r13*8], rax
    jmp .Ltcmr_progress
.Ltcmr_self:
    cmp r12, [rbx + TCM_self_due]
    jl .Ltcmr_backoff
    mov r13, [rbx + TCM_cleanup]
    mov rdi, rbx
    call tc_free
    test rdx, rdx
    jz .Ltcmr_self_retained
    # No dereference of the dead plan follows consumed1.
    mov qword ptr [rip + g_theme_intent_migration], 0
    test r13, r13
    jz 10f
    mov rax, r13
10: mov edx, 1
    xor ecx, ecx
    EPILOGUE
.Ltcmr_self_retained:
    mov rdi, rbx
    mov rsi, rax
    call tcm_cleanup
    mov rdi, rbx
    mov rsi, -5
    call tcm_cleanup
    mov rax, [rbx + TCM_self_delay]
    call tcm_delay
    mov [rbx + TCM_self_delay], rax
    add rax, r12
    jno 11f
    mov rax, 9223372036854775807
11: mov [rbx + TCM_self_due], rax
    jmp .Ltcmr_backoff
.Ltcmr_progress:
    mov rax, [rbx + TCM_cleanup]
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltcmr_backoff:
    mov rax, [rbx + TCM_cleanup]
    xor edx, edx
    mov ecx, 1
    EPILOGUE
.Ltcmr_bad:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltcmr_empty:
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    ret
.Ltcmr_bad_leaf:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
# rax olddelay -> newdelay16..1000; no state access.
tcm_delay:
    test rax, rax
    jnz 1f
    mov eax, 8
1:  add rax, rax
    cmp rax, 1000
    jbe 2f
    mov eax, 1000
2:  ret
# status(plan,out56) never follows children, allocator metadata or borrowed guard pointers.
FN theme_intent_migration_status
    test rdi, rdi
    jz .Ltcmr_bad_leaf
    test rsi, rsi
    jz .Ltcmr_bad_leaf
    mov rax, [rdi + TCM_state]
    mov [rsi], rax
    mov rax, [rdi + TCM_cleanup]
    mov [rsi + 8], rax
    mov r8, [rdi + TCM_owned]
    mov rax, [rdi + TCM_reservations]
    shl rax, 3
    or r8, rax
    or r8, 256
    mov [rsi + 32], r8
    mov rax, [rdi + TCM_committed]
    mov [rsi + 40], rax
    mov rax, [rdi + TCM_primary]
    mov [rsi + 48], rax
    mov r9, [rdi + TCM_self_due]
    mov r10, [rdi + TCM_self_delay]
    # Self is only eligible after all children/reservations; it must not force due0 early.
    test r8, 255
    jz 2f
    mov r9, 9223372036854775807
    xor r10d, r10d
    xor ecx, ecx
1:  bt r8, rcx
    jnc 3f
    mov rax, [rdi + TCM_due + rcx*8]
    cmp r9, rax
    cmovg r9, rax
    mov rax, [rdi + TCM_delay + rcx*8]
    cmp r10, rax
    cmovb r10, rax
3:  inc ecx
    cmp ecx, 8
    jb 1b
2:  mov [rsi + 16], r9
    mov [rsi + 24], r10
    xor eax, eax
    ret
