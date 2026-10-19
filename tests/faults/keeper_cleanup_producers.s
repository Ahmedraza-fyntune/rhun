.include "rhun.inc"
.include "app/taskproc.inc"
.section .rodata
kcu_null: .asciz "/dev/null"
.bss
kcu_rule: .zero CR_SIZE
kcu_buf: .zero 4096
kcu_target: .quad 0
kcu_calls: .quad 0
kcu_flags: .quad 0
kcu_pair: .zero 8
kcu_native: .zero KB_SIZE
kcu_ext: .zero EXT_SIZE
.text
FN ext_fd_close_checked
    cmp rdi, [rip + kcu_target]
    jne kcu_real_close
    PROLOGUE
    inc qword ptr [rip + kcu_calls]
.if KCU_DISP != 0
    call kcu_real_close
    test rax, rax
    jnz 9f
.endif
    mov rax, -13
    mov edx, KCU_DISP
    EPILOGUE
9:  mov edi, 73
    call sys_exit
.if KCU_MODE == 4
FN kcu_prep_probe
    mov qword ptr [rip + conf_helper_error], -22
    ret
.endif
FN kcu_stat
    mov rax, -5
    ret
FN kcu_fcntl
    mov rax, [rip + kcu_flags]
    inc qword ptr [rip + kcu_flags]
    cmp rax, KCU_STAGE
    jne 1f
    mov rax, -5
    ret
1:  SYS SYS_fcntl
    ret
FN main
    PROLOGUE
.if KCU_MODE == 3
    lea rdi, [rip + kcu_native]
    call kp_native_init
    lea rdi, [rip + kcu_pair]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rip + kcu_native]
    xor ecx, ecx
    call kp_pipe_owned
    cmp rax, -5
    jne .Lkcu_fail
    movsxd rax, dword ptr [rip + kcu_pair]
    cmp [rip + kcu_native + KB_fds], rax
    jne .Lkcu_fail
    mov [rip + kcu_target], rax
    movsxd rax, dword ptr [rip + kcu_pair + 4]
    cmp [rip + kcu_native + KB_fds + 8], rax
    jne .Lkcu_fail
    lea rdi, [rip + kcu_native]
    xor esi, esi
    call kp_native_cleanup
    cmp rax, -13
    jne .Lkcu_fail
    test rdx, rdx
    jnz .Lkcu_fail
    cmp qword ptr [rip + kcu_native + KB_unknown], 1
    jne .Lkcu_fail
    cmp qword ptr [rip + kcu_native + KB_fds + 8], -1
    jne .Lkcu_fail
    lea rdi, [rip + kcu_native]
    xor esi, esi
    call kp_native_cleanup
.else
.if KCU_MODE != 4
    mov qword ptr [rip + conf_helper_mode], 1
    mov qword ptr [rip + conf_helper_cleanup_init], 1
    mov qword ptr [rip + conf_helper_scratch], -1
    mov qword ptr [rip + conf_helper_scratch + 8], -1
.endif
.if KCU_MODE == 0 || KCU_MODE == 4
    lea rdi, [rip + kcu_null]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lkcu_fail
    mov [rip + kcu_target], rax
    mov [rip + kcu_rule + CR_fd], eax
    lea rax, [rip + kcu_rule]
    mov [rip + conf_rules + VEC_ptr], rax
    mov qword ptr [rip + conf_rules + VEC_len], 1
.if KCU_MODE == 4
    lea rdi, [rip + kcu_ext]
    mov [rip + g_exts + VEC_ptr], rdi
    lea rsi, [rip + kcu_null]
    mov [rdi + EXT_dir], rsi
    mov [rdi + EXT_state], rsi
    mov [rdi + EXT_prog], rsi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call confine_helper_prepare
    cmp rax, -22
    jne .Lkcu_fail
    cmp rcx, -13
    jne .Lkcu_fail
    cmp qword ptr [rip + kcu_calls], 1
    jne .Lkcu_fail
.endif
.else
    lea rdi, [rip + kcu_null]
.if KCU_MODE == 1
    lea rsi, [rip + kcu_buf]
    call kcu_interp
.else
    xor esi, esi
    call kcu_add_rule
.endif
    test rax, rax
    jnz .Lkcu_fail
.endif
    call confine_helper_release_checked
    cmp rax, -13
    jne .Lkcu_fail
    cmp rcx, -13
    jne .Lkcu_fail
.if KCU_MODE == 0
    cmp qword ptr [rip + conf_helper_error], -13
.else
.if KCU_MODE == 1 || KCU_MODE == 4
    cmp qword ptr [rip + conf_helper_error], -22
.else
    cmp qword ptr [rip + conf_helper_error], -5
.endif
.endif
    jne .Lkcu_fail
.if KCU_MODE == 0 || KCU_MODE == 4
.if KCU_DISP == 1
    cmp dword ptr [rip + kcu_rule + CR_fd], -1
.else
    mov rax, [rip + kcu_target]
    cmp dword ptr [rip + kcu_rule + CR_fd], eax
.endif
.else
.if KCU_MODE == 1
    lea rbx, [rip + conf_helper_scratch]
.else
    lea rbx, [rip + conf_helper_scratch + 8]
.endif
.if KCU_DISP == 1
    cmp qword ptr [rbx], -1
.else
    mov rax, [rip + kcu_target]
    cmp [rbx], rax
.endif
.endif
    jne .Lkcu_fail
    call confine_helper_release_checked
.endif
    cmp qword ptr [rip + kcu_calls], 1
    jne .Lkcu_fail
    xor eax, eax
    EPILOGUE
.Lkcu_fail:
    mov edi, 73
    call sys_exit
