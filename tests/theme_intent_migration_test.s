.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintentmigration.inc"
.section .rodata
tcmt_value: .asciz "requested"
tcmt_empty: .asciz ""
.bss
.p2align 3
.globl tcmt_fault_target
tcmt_fault_target: .zero 8
.text
tcmt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 400
    mov r15, [rip + g_mem_live]
    cmp qword ptr [rip + g_argc], 2
    jne tcmt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call parse_u64
    mov [rsp + 360], rax
    mov rdi, rsp
    xor esi, esi
    mov edx, 352
    call memset
    lea rax, [rip + tcmt_value]
    mov [rsp], rax
    mov [rsp + 8], rax
    lea rax, [rip + tcmt_empty]
    mov [rsp + 16], rax
    mov qword ptr [rsp + TIR_context], 1
    mov qword ptr [rsp + TIR_config], 2
    mov qword ptr [rsp + TIR_catalog], 3
    mov dword ptr [rsp + TIR_keys], 7
    mov dword ptr [rsp + TIR_system], -1
    cmp qword ptr [rsp + 360], 5
    jne 31f
    lea rax, [rip + tcmt_value]
    mov [rsp + TIR_pending], rax
    lea rax, [rip + tcmt_empty]
    mov [rsp + TIR_pending_dark], rax
31:
    mov rdi, rsp
    call theme_intent_capture
    test rax, rax
    jz tcmt_fail
    or rdx, rcx
    jnz tcmt_fail
    mov [rsp + 64], rax
    mov [rsp + 336], rax
    xor r13d, r13d
1:  mov edi, 17
    test r13, r13
    jnz 2f
    mov edi, 70000
2:  call mem_alloc_try
    test rax, rax
    jz tcmt_fail
    mov [rsp + 40 + r13*8], rax
    mov [rsp + 304 + r13*8], rax
    mov byte ptr [rax], 0
    inc r13
    cmp r13, 3
    jb 1b
    mov rax, [rsp + 40]
    mov [rip + tcmt_fault_target], rax
    mov rdi, rsp
    call theme_intent_capture
    test rax, rax
    jz tcmt_fail
    or rdx, rcx
    jnz tcmt_fail
    mov r12, rax
    cmp qword ptr [rsp + 360], 5
    jne 32f
    mov rdi, r12
    call theme_intent_retain
    cmp rax, r12
    jne tcmt_fail
    mov rdi, [rsp + 336]
    call theme_intent_retain
    cmp rax, [rsp + 336]
    jne tcmt_fail
32: cmp qword ptr [rsp + 360], 2
    jne 3f
    mov qword ptr [rsp + 40], 1
3:  cmp qword ptr [rsp + 360], 3
    jne 4f
    mov rax, [rsp + 40]
    mov [rsp + 48], rax
    # Keep exact trusted guards equal while proving duplicate-owner rejection.
    mov [r12 + TI_guard + 48], rax
4:  cmp qword ptr [rsp + 360], 4
    jne 5f
    mov qword ptr [r12 + TI_values], 0
5:  mov rdi, r12
    mov rsi, rsp
    call theme_intent_migration_prepare
    mov r14, rax
    cmp qword ptr [rsp + 360], 5
    je .Ltcmt_prepared
    cmp qword ptr [rsp + 360], 2
    jb .Ltcmt_prepared
    test r14, r14
    jnz tcmt_fail
    cmp qword ptr [rsp + 360], 2
    jne 6f
    cmp rdx, -116
    jne tcmt_fail
    jmp 7f
6:  cmp rdx, -22
    jne tcmt_fail
7:  test rcx, rcx
    jnz tcmt_fail
    cmp qword ptr [rip + g_theme_intent_migration], 0
    jne tcmt_fail
    mov rdi, r12
    call theme_intent_release
    test rax, rax
    jnz tcmt_fail
    cmp rdx, 1
    jne tcmt_fail
    jmp .Ltcmt_old_cleanup
.Ltcmt_prepared:
    test r14, r14
    jz tcmt_fail
    or rdx, rcx
    jnz tcmt_fail
    mov rdi, r14
    mov rsi, rsp
    call theme_intent_migration_check
    test rax, rax
    jnz tcmt_fail
    inc qword ptr [rsp + TIR_config]
    mov rdi, r14
    mov rsi, rsp
    call theme_intent_migration_check
    cmp rax, -116
    jne tcmt_fail
    dec qword ptr [rsp + TIR_config]
    mov rdi, r14
    call theme_intent_migration_view
    test rax, rax
    jz tcmt_fail
    mov r13, rax
    xor ebx, ebx
8:  mov rax, [r13 + rbx*8]
    test rax, rax
    jz tcmt_fail
    cmp rax, [r12 + TI_values + rbx*8]
    je tcmt_fail
    cmp rax, [rsp + 304 + rbx*8]
    je tcmt_fail
    cmp [r13 + 24 + rbx*8], rax
    jne tcmt_fail
    mov [rsp + 272 + rbx*8], rax
    cmp qword ptr [rax - 16], 8
    ja tcmt_fail
    mov rdi, rax
    mov rsi, [r12 + TI_values + rbx*8]
    mov rdx, [r12 + TI_lengths + rbx*8]
    inc rdx
    call memeq
    test eax, eax
    jz tcmt_fail
    inc ebx
    cmp ebx, 3
    jb 8b
    mov rax, [r13 + 48]
    mov [rsp + 240], rax
    mov rax, [r13 + 56]
    mov [rsp + 248], rax
    cmp qword ptr [rsp + 360], 0
    je .Ltcmt_release
    # Emulate root's already-preflighted pointer exchange, then mark ownership only.
    mov rax, [rip + g_theme_capture_charge]
    sub rax, [r14 + TCM_new_total]
    mov [rsp + 256], rax
    mov rdi, r14
    call theme_intent_migration_mark_committed
    mov rax, [rip + g_theme_capture_charge]
    cmp rax, [rsp + 256]
    jne tcmt_fail
    mov rdi, r14
    call theme_intent_migration_view
    test rax, rax
    jnz tcmt_fail
    cmp qword ptr [r14 + TCM_owned], 184
    jne tcmt_fail
    cmp qword ptr [r14 + TCM_reservations], 0
    jne tcmt_fail
.Ltcmt_release:
    mov qword ptr [rsp + 352], 1000
.Ltcmt_release_loop:
    mov rdi, r14
    mov rsi, [rsp + 352]
    call theme_intent_migration_release
    test rax, rax
    jnz tcmt_fail
    add qword ptr [rsp + 352], 1
    cmp qword ptr [rsp + 352], 1100
    ja tcmt_fail
    test rdx, rdx
    jz .Ltcmt_release_loop
    cmp qword ptr [rip + g_theme_intent_migration], 0
    jne tcmt_fail
    cmp qword ptr [rsp + 360], 0
    je .Ltcmt_old_cleanup
    mov eax, 32768
    cmp qword ptr [rsp + 360], 5
    jne 33f
    add eax, 32768
    cmp qword ptr [r12 + TI_refs], 2
    jne tcmt_fail
    mov rcx, [rsp + 336]
    cmp qword ptr [rcx + TI_refs], 1
    jne tcmt_fail
    mov rcx, [rsp + 240]
    cmp rcx, [r12 + TI_values + 24]
    jne tcmt_fail
    cmp byte ptr [rcx], 'r'
    jne tcmt_fail
    mov rcx, [rsp + 248]
    cmp rcx, [r12 + TI_values + 32]
    jne tcmt_fail
    cmp byte ptr [rcx], 0
    jne tcmt_fail
33: cmp [rip + g_theme_capture_charge], rax
    jne tcmt_fail
    # Published cfg strings are ordinary legacy allocator owners outside TC charge.
    xor ebx, ebx
9:  mov rdi, [rsp + 272 + rbx*8]
    call mem_free
    inc ebx
    cmp ebx, 3
    jb 9b
    mov rdi, r12
    call theme_intent_release
    test rax, rax
    jnz tcmt_fail
    cmp rdx, 1
    jne tcmt_fail
    cmp qword ptr [rsp + 360], 5
    jne .Ltcmt_done
    cmp qword ptr [r12 + TI_refs], 1
    jne tcmt_fail
    mov rdi, r12
    call theme_intent_release
    cmp rdx, 1
    jne tcmt_fail
    mov rdi, [rsp + 336]
    call theme_intent_release
    cmp rdx, 1
    jne tcmt_fail
    jmp .Ltcmt_done
.Ltcmt_old_cleanup:
    xor ebx, ebx
10: mov rdi, [rsp + 304 + rbx*8]
    call prep_cleanup_free
    test rax, rax
    jnz tcmt_fail
    cmp rdx, 1
    jne tcmt_fail
    inc ebx
    cmp ebx, 3
    jb 10b
    mov rdi, [rsp + 336]
    call theme_intent_release
    test rax, rax
    jnz tcmt_fail
    cmp rdx, 1
    jne tcmt_fail
.Ltcmt_done:
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcmt_fail
    cmp r15, [rip + g_mem_live]
    jne tcmt_fail
    xor eax, eax
    EPILOGUE
