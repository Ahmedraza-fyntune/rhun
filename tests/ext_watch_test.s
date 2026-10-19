# Shared native watch references, aliases, editor overlap and backend slot reuse.
.include "rhun.inc"
.section .rodata
ewt_ok: .asciz "ok shared native watchers\n"
.bss
.p2align 3
ewt_stage: .quad 0
ewt_a: .zero EXT_SIZE
ewt_b: .zero EXT_SIZE
.text
ewt_fail:
    mov edi, [rip + ewt_stage]
    add edi, 100
    call sys_exit
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 3
    jb ewt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov r13, [rax + 16]
    call watch_init
    mov qword ptr [rip + ewt_stage], 1
    mov rdi, r12
    call watch_broker_acquire
    test rax, rax
    js ewt_fail
    mov r14, rax
    mov rdi, r12
    call watch_broker_acquire
    cmp rax, r14
    jne ewt_fail
    mov rdi, r14
    call watch_broker_count
    cmp eax, 2
    jne ewt_fail
    mov qword ptr [rip + ewt_stage], 2
    mov rdi, r13
    call watch_broker_acquire
    test rax, rax
    js ewt_fail
    mov r15, rax
.ifndef WINDOWS
    cmp r15, r14
    jne ewt_fail
    mov rdi, r14
    call watch_broker_count
    cmp eax, 3
    jne ewt_fail
.endif
    mov rdi, r15
    call watch_broker_release
    mov rdi, r14
    call watch_broker_release
    mov rdi, r14
    call watch_broker_count
    cmp eax, 1
    jne ewt_fail
    mov rdi, r14
    call watch_broker_release
    mov rdi, r14
    call watch_broker_count
    test eax, eax
    jnz ewt_fail
    mov qword ptr [rip + ewt_stage], 3
    # More than macOS's total slot capacity, while only one watch is live.
.ifdef MACOS
    mov ebx, 1050
.else
    mov ebx, 4100
.endif
1:  mov rdi, r12
    call watch_broker_acquire
    test rax, rax
    js ewt_fail
    mov rdi, rax
    call watch_broker_release
    dec ebx
    jnz 1b
    mov qword ptr [rip + ewt_stage], 4
    mov rdi, r12
    call watch_dir
    test rax, rax
    js ewt_fail
    mov r14, rax
    mov rdi, r12
    call watch_broker_acquire
    cmp rax, r14
    jne ewt_fail
    mov rdi, r14
    call watch_broker_release
    mov rdi, r12
    call watch_broker_acquire
    cmp rax, r14
    jne ewt_fail
    mov rdi, r14
    call watch_broker_release
    mov qword ptr [rip + ewt_stage], 5
    cmp qword ptr [rip + g_argc], 4
    jb ewt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 24]
    mov [rip + g_project], r12
    mov r15, [rip + g_mem_live]
    mov rdi, r12
    call watch_broker_acquire
    test rax, rax
    js ewt_fail
    mov r14, rax
    lea rbx, [rip + ewt_a]
    mov dword ptr [rbx + EXT_features], FEAT_WORKSPACE_WATCH
    mov dword ptr [rbx + EXT_needs], NEEDS_PROJECT_READ
    mov rdi, rbx
    call extwatch_add
    cmp rax, 1
    jne ewt_fail
    mov rdi, rbx
    call extwatch_add
    cmp rax, 1
    jne ewt_fail
    lea rbx, [rip + ewt_b]
    mov dword ptr [rbx + EXT_features], FEAT_WORKSPACE_WATCH
    mov dword ptr [rbx + EXT_needs], NEEDS_PROJECT_READ
    mov rdi, rbx
    call extwatch_add
    cmp rax, 2
    jne ewt_fail
    mov rdi, rbx
    mov esi, 1
    call extwatch_remove
    test eax, eax
    jnz ewt_fail
    # Overfull enumeration must release every staging ref, preserving the
    # independent inspector reference and the other subscriber.
    call extwatch_tick
    mov rdi, r14
    call watch_broker_count
    cmp eax, 1
    jne ewt_fail
    lea rdi, [rip + ewt_a]
    call extwatch_owner_gone
    lea rdi, [rip + ewt_b]
    call extwatch_owner_gone
    mov rdi, r14
    call watch_broker_count
    cmp eax, 1
    jne ewt_fail
    mov rdi, r14
    call watch_broker_release
    cmp r15, [rip + g_mem_live]
    jne ewt_fail
    mov qword ptr [rip + ewt_stage], 6
    cmp qword ptr [rip + g_argc], 5
    jb ewt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov [rip + g_project], r12
    mov r15, [rip + g_mem_live]
    lea rdi, [rip + ewt_a]
    call extwatch_add
    cmp rax, 3
    jne ewt_fail
    call extwatch_tick
    call extwatch_tick
    mov rdi, r12
    call watch_broker_acquire
    test rax, rax
    js ewt_fail
    mov r14, rax
    mov rdi, r14
    call watch_broker_count
    cmp eax, 2
    jne ewt_fail
    # Replace the enrolled path with an overfull directory. A failed rebuild
    # retains the active reference until the runtime explicitly retires.
    mov rax, [rip + g_argv]
    mov rdi, r12
    mov rsi, [rax + 32]
    SYS SYS_rename
    test rax, rax
    js ewt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    mov rsi, r12
    SYS SYS_rename
    test rax, rax
    js ewt_fail
    mov edi, -1
    mov esi, 0x4000
    call extwatch_native_event
    call extwatch_tick
    mov rdi, r14
    call watch_broker_count
    cmp eax, 2
    jne ewt_fail
    lea rdi, [rip + ewt_a]
    call extwatch_owner_gone
    mov rdi, r14
    call watch_broker_count
    cmp eax, 1
    jne ewt_fail
    mov rdi, r14
    call watch_broker_release
    cmp r15, [rip + g_mem_live]
    jne ewt_fail
    lea rdi, [rip + ewt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
