# Exact helper-local confinement context. No editor GUI or global contributions are initialized.
.include "rhun.inc"
.include "app/taskproc.inc"
.include "app/taskauth.inc"
.bss
.p2align 4
kc_extension: .zero EXT_SIZE
kc_prepared: .quad 0
.text
FN kp_extension_confinement
.ifdef WINDOWS
    mov dword ptr [rdi + KH_confined], CONFINED_NO
    mov dword ptr [rdi + KH_confine_reason], 1
    xor eax, eax
    ret
.else
    PROLOGUE 160
    mov rbx, rdi
    mov r14, [rbx + KH_authctx]
    # Required paths are validated even when this system cannot provide a native sandbox.
    mov rdi, [r14 + AX_strings + 40]
    mov esi, O_RDONLY | O_NONBLOCK | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lkc_direct_error
    mov r13, rax
    mov [rbx + KH_native + KB_fds + 64], rax
    mov rdi, rax
    mov rsi, rsp
    SYS SYS_fstat
    mov r12, rax
    test r12, r12
    js 901f
    mov eax, [rsp + 24]
    and eax, 0xf000
    cmp eax, 0x8000
    je 901f
    mov r12, -22
901: mov rdi, rbx
    call kh_close_probe
    test r12, r12
    js .Lkc_result
    test rax, rax
    js .Lkc_direct_error
    mov rdi, [r14 + AX_strings + 32]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lkc_direct_error
    mov [rbx + KH_native + KB_fds + 64], rax
    mov rdi, rbx
    call kh_close_probe
    test rax, rax
    js .Lkc_direct_error
    # Bound token expansion independently of profile/rule caps.
    mov r12, [r14 + AX_strings + 56]
    xor r13d, r13d
1:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 4f
    cmp eax, ' '
    je 2f
    cmp eax, 9
    je 2f
    inc r13
    cmp r13, 64
    ja .Lkc_big
3:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 4f
    inc r12
    cmp eax, ' '
    je 1b
    cmp eax, 9
    jne 3b
    jmp 1b
2:  inc r12
    jmp 1b
4:  lea r12, [rip + kc_extension]
    mov rdi, r12
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    mov rax, [r14 + AX_strings + 24]
    mov [r12 + EXT_dir], rax
    mov rax, [r14 + AX_strings + 32]
    mov [r12 + EXT_state], rax
    mov rax, [r14 + AX_strings + 40]
    mov [r12 + EXT_prog], rax
    mov rax, [r14 + AX_strings + 48]
    cmp byte ptr [rax], 0
    jne 5f
    xor eax, eax
5:  mov [r12 + EXT_script], rax
    mov rax, [r14 + AX_strings + 56]
    cmp byte ptr [rax], 0
    jne 6f
    xor eax, eax
6:  mov [r12 + EXT_runs], rax
    mov eax, [r14 + AX_needs]
    mov [r12 + EXT_needs], eax
    mov dword ptr [r12 + EXT_log], -1
    mov [rip + g_exts + VEC_ptr], r12
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov qword ptr [rip + g_exts + VEC_cap], 1
    mov rax, [r14 + AX_strings + 64]
    cmp byte ptr [rax], 0
    jne 7f
    xor eax, eax
7:  mov [rip + g_project], rax
    mov rax, [rip + g_envp]
    mov [rsp], rax
    mov rax, [rbx + KH_envp]
    mov [rip + g_envp], rax
    mov rdi, r12
    mov rsi, [r14 + AX_strings + 72]
    lea rdx, [rip + kc_cancel]
    mov rcx, rbx
    mov r8, [r14 + AX_fallback]
    call confine_helper_prepare
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, rcx
    call kh_note_cleanup
    mov rax, [rsp]
    mov [rip + g_envp], rax
    test r12, r12
    js .Lkc_result
    cmp qword ptr [rbx + KH_cleanup], 0
    je 91f
    mov r12, [rbx + KH_cleanup]
    jmp .Lkc_result
91: mov [rbx + KH_confined], r12d
    mov [rbx + KH_confine_reason], r13d
    mov qword ptr [rip + kc_prepared], 1
    xor eax, eax
    EPILOGUE
.Lkc_direct_error:
    mov r12, rax
    jmp .Lkc_result
.Lkc_big:
    mov r12, -7
.Lkc_result:
    mov rax, r12
    EPILOGUE
.endif

kc_cancel:
    jmp kp_helper_alive

# Called in helper after target fork, or on definite no-target failure, never in target.
FN kp_extension_confinement_release
.ifdef WINDOWS
    xor eax, eax
    ret
.else
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rip + kc_prepared], 0
    call confine_helper_release_checked
    mov rdi, rbx
    mov rsi, rcx
    call kh_note_cleanup
    mov rax, [rbx + KH_cleanup]
    EPILOGUE
.endif

# The shared fork page distinguishes actual sandbox failure from a program choosing exit75.
FN kp_extension_setup_error
.ifdef WINDOWS
    movsxd rax, esi
    ret
.else
    PROLOGUE
    mov rbx, rdi
    movsxd r12, esi
    cmp qword ptr [rbx + KH_mode], KP_EXTENSION
    jne 1f
    lea rdi, [rip + kc_extension]
    call confine_failed
    test eax, eax
    jz 1f
    mov [rbx + KH_confine_reason], eax
    mov dword ptr [rbx + KH_confined], CONFINED_NO
    mov qword ptr [rbx + KH_dirty], 1
    mov r12, -13
1:  mov rax, r12
    EPILOGUE
.endif

# One checked close of the classification probe, before any later probe can replace it.
kh_close_probe:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rbx + KH_native + KB_fds + 64]
    lea rsi, [rbx + KH_native + KB_unknown]
    mov edx, 8
    xor ecx, ecx
    call kp_close_owned
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    mov rax, r12
    EPILOGUE
