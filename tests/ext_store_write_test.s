.include "rhun.inc"
.include "app/extstore.inc"
.text
esww_fail:
    mov edi, 76
    call sys_exit
# Complete snapshot fixture. Sorting/transport happens before parent-only bind.
esww_snapshot:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rdi + ESG_root]
    xor esi, esi
    xor edx, edx
    call ext_store_snapshot_root_try
    test rax, rax
    jz esww_fail
    mov r12, rax
    mov rcx, [rbx + ESG_epoch]
    mov [rax + ESS_tag + EST_epoch], rcx
    mov rdi, rax
    lea rsi, [rax + ESS_tag]
    call ext_store_snapshot_pack_try
    test rax, rax
    jz esww_fail
    mov rdi, rax
    call mem_free
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rbx + ESG_epoch]
    call ext_store_snapshot_bind
    test rax, rax
    jnz esww_fail
    mov rax, r12
    EPILOGUE
esww_precommit:
    inc qword ptr [rdi]
    mov rax, [rdi + 8]
    ret
esww_pause:
    PROLOGUE 16
    mov edi, 1
    lea rsi, [rip + esww_ready]
    mov edx, 6
    call write_all
    test rax, rax
    jnz esww_fail
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne esww_fail
    EPILOGUE
FN main
    PROLOGUE 128
    cmp qword ptr [rip + g_argc], 6
    jne esww_fail
    mov r15, [rip + g_mem_live]
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 40]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 40]
    call parse_u64
    cmp rdx, rsi
    jne esww_fail
    mov [rsp + 96], rax
    mov rdi, rsp
    xor esi, esi
    mov edx, 96
    call memset
    mov rdi, [rbx + 32]
    mov esi, 160
    call file_read_limited_try
    test rax, rax
    jz esww_fail
    cmp rdx, 160
    jne esww_fail
    mov [rsp + 104], rax
    mov rdi, [rbx + 8]
    mov esi, 1
    mov edx, 1
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz esww_fail
    mov r12, rax
    mov rdi, rax
    call esww_snapshot
    mov r13, rax
    mov rdi, rax
    mov rsi, [rbx + 16]
    mov rdx, [rbx + 24]
    call ext_store_snapshot_find
    xor ecx, ecx
    test rax, rax
    jz 1f
    cmp qword ptr [rax + ESR_generation], 0
    je 1f
    lea rcx, [rax + ESR_index]
1:  mov rdi, r12
    mov rsi, [rbx + 16]
    mov rdx, [rbx + 24]
    mov r8, [rsp + 104]
    mov r9, r13
    call ext_store_prepare_begin_try
    mov [rsp], rdx
    mov [rsp + 48], rcx
    mov r14, rax
    test rax, rax
    jz 8f
    mov rdi, r12
    call ext_store_guard_free
    cmp rax, -16
    jne esww_fail
2:  inc qword ptr [rsp + 56]
    mov rdi, r14
    mov esi, 3
    call ext_store_prepare_step
    mov [rsp + 112], rax
    cmp qword ptr [rsp + 96], 10
    jne 21f
    call esww_pause
21: mov rax, [rsp + 112]
    test rax, rax
    jz 2b
    js 7f
    cmp qword ptr [rsp + 96], 6
    jne 22f
    call esww_pause
22: cmp qword ptr [rsp + 96], 5
    je 3f
    mov rdi, r13
    call ext_store_snapshot_free
    mov rdi, r12
    call esww_snapshot
    mov r13, rax
3:  mov rdi, r14
    mov rsi, r13
    call ext_store_ready_try
    mov [rsp + 8], rax
    test rax, rax
    js 6f
    cmp qword ptr [rsp + 96], 4
    jne 34f
    call esww_pause
34: mov qword ptr [rsp + 72], 0
    cmp qword ptr [rsp + 96], 1
    jne 31f
    mov qword ptr [rsp + 72], -125
31: cmp qword ptr [rsp + 96], 2
    jne 32f
    inc qword ptr [r12 + ESG_epoch]
32: cmp qword ptr [rsp + 96], 3
    jne 33f
    mov qword ptr [rsp + 72], 1
33: mov rdi, r14
    lea rsi, [rip + esww_precommit]
    lea rdx, [rsp + 64]
    call ext_store_commit_try
    mov [rsp + 16], rax
    test rax, rax
    js 6f
    cmp qword ptr [rsp + 96], 7
    jne 35f
    call esww_pause
35: cmp qword ptr [rsp + 64], 1
    jne esww_fail
    mov rdi, r14
    mov esi, 3
    call ext_store_cleanup_step
    cmp rax, -22
    jne esww_fail
    mov rdi, r14
    call ext_store_visible
    test rax, rax
    jnz esww_fail
4:  mov rdi, r14
    mov esi, 3
    call ext_store_cleanup_step
    test rax, rax
    js esww_fail
    jnz 4b
6:  mov rax, [r14 + ESW_state]
    mov [rsp + 24], rax
    mov rax, [r14 + ESW_publish_error]
    mov [rsp + 32], rax
    mov rax, [r14 + ESW_reconcile_error]
    mov [rsp + 40], rax
    mov rdi, r14
    call ext_store_prepare_free
    mov [rsp + 48], rax
    jmp 8f
7:  mov [rsp], rax
    jmp 6b
8:  mov rdi, r13
    call ext_store_snapshot_free
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esww_fail
    mov rdi, [rsp + 104]
    call mem_free
    cmp r15, [rip + g_mem_live]
    jne esww_fail
    cmp qword ptr [rsp + 96], 10
    jne 81f
    mov edi, 1
    lea rsi, [rip + esww_done]
    mov edx, 5
    call write_all
81: mov edi, 1
    mov rsi, rsp
    mov edx, 64
    call write_all
    test rax, rax
    jnz esww_fail
    xor eax, eax
    EPILOGUE

.section .rodata
esww_ready: .ascii "READY\n"
esww_done: .ascii "DONE\n"
