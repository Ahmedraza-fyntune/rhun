# POSIX keeper ownership. No editor confinement or parent-death signal is applied to helper.
.include "rhun.inc"
.include "app/taskproc.inc"
.ifndef WINDOWS
.bss
.p2align 4
kp_close_work: .zero 1048576
.section .rodata
kp_helper_flag: .asciz "--process-keeper"
kp_helper_version: .asciz "v1"
kp_null: .asciz "/dev/null"
kp_root: .asciz "/"
kp_safe_path: .asciz "PATH=/usr/bin:/bin"
kp_safe_locale: .asciz "LC_ALL=C"
kp_fdpath: .asciz "/proc/self/fd"
.p2align 3
kp_safe_env: .quad kp_safe_path, kp_safe_locale, 0
.text

# Make just this pipe end nonblocking. Source target stdio remains caller-owned.
kp_nonblock:
    PROLOGUE
    mov rbx, rdi
    mov esi, 3
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 9f
    mov rdi, rbx
    mov esi, 4
    mov rdx, rax
    or edx, O_NONBLOCK
    SYS SYS_fcntl
9:  EPILOGUE

# pipe(pair,flags,KB,firstSlot). Install both owned endpoints before flag checks.
FN kp_pipe_owned
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    SYS SYS_pipe2
    test rax, rax
    js 9f
    movsxd rax, dword ptr [rbx]
    mov [r13 + r14*8 + KB_fds], rax
    movsxd rax, dword ptr [rbx + 4]
    mov [r13 + r14*8 + KB_fds + 8], rax
    xor r15d, r15d
1:  movsxd rdi, dword ptr [rbx + r15*4]
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 9f
    mov rdx, rax
    test r12d, O_CLOEXEC
    jz 2f
    or edx, 1
2:  movsxd rdi, dword ptr [rbx + r15*4]
    mov esi, 2
    SYS SYS_fcntl
    test rax, rax
    js 9f
    test r12d, O_NONBLOCK
    jz 3f
    movsxd rdi, dword ptr [rbx + r15*4]
    call kp_nonblock
    test rax, rax
    js 9f
3:  inc r15
    cmp r15, 2
    jb 1b
    xor eax, eax
9:  EPILOGUE

# Child-only, remap sources[0..count) safely. Last source is the CLOEXEC error pipe.
# Returns0/-errno, rdx an owned usable error pipe even on a partial remap failure.
kp_remap:
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + r12*8 - 8]
    mov [rsp + 64], rax
    xor r13d, r13d
1:  mov rdi, [rbx + r13*8]
    xor esi, esi
    # Temporary descriptors must exceed every remap destination, including at low RLIMIT_NOFILE.
    mov rdx, r12
    SYS SYS_fcntl
    test rax, rax
    js 8f
    mov [rsp + r13*8], rax
    inc r13
    cmp r13, r12
    jb 1b
    mov rax, [rsp + r12*8 - 8]
    mov [rsp + 64], rax
    xor r13d, r13d
2:  mov rdi, [rsp + r13*8]
    mov rsi, r13
    SYS SYS_dup2
    cmp rax, -4
    je 2b
    test rax, rax
    js 8f
    inc r13
    cmp r13, r12
    jb 2b
    lea rax, [r12 - 1]
    mov [rsp + 64], rax
    mov rdi, rax
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
    test rax, rax
    js 8f
    mov rdi, r12
    lea rsi, [rip + kp_close_work]
    call kp_closefrom
8:  mov rdx, [rsp + 64]
    EPILOGUE

# Parent-side backend. Before fork failure cleans every temporary FD. After fork returns a handle.
FN kp_backend_prepare
    PROLOGUE 4448
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp + 96]
    mov esi, 255
    mov edx, 36
    call memset
    lea rdi, [rsp + 160]
    mov esi, 4096
    call proc_self_path
    test rax, rax
    jle .Lkp_backend_fail
    lea rdi, [rsp + 96]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KX_native]
    mov ecx, 0
    call kp_pipe_owned
    test rax, rax
    js .Lkp_backend_fail
    lea rdi, [rsp + 104]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KX_native]
    mov ecx, 2
    call kp_pipe_owned
    test rax, rax
    js .Lkp_backend_fail
    lea rdi, [rip + kp_null]
    mov esi, O_RDWR | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lkp_backend_fail
    mov [rsp + 112], eax
    mov [rbx + KX_native + KB_fds + 32], rax
    cmp qword ptr [r12 + KP_stdout], -1
    jne 1f
    lea rdi, [rsp + 116]
    mov esi, O_CLOEXEC
    lea rdx, [rbx + KX_native]
    mov ecx, 5
    call kp_pipe_owned
    test rax, rax
    js .Lkp_backend_fail
    mov edi, [rsp + 116]
    call kp_nonblock
    test rax, rax
    js .Lkp_backend_fail
1:  lea rdi, [rsp + 124]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KX_native]
    mov ecx, 7
    call kp_pipe_owned
    test rax, rax
    js .Lkp_backend_fail
    lea rdi, [rsp + 4256]
    mov rsi, [rbx + KX_id]
    call fmt_u64
    mov byte ptr [rsp + rax + 4256], 0
    lea rax, [rsp + 160]
    mov [rsp + 4288], rax
    lea rax, [rip + kp_helper_flag]
    mov [rsp + 4296], rax
    lea rax, [rip + kp_helper_version]
    mov [rsp + 4304], rax
    lea rax, [rsp + 4256]
    mov [rsp + 4312], rax
    mov qword ptr [rsp + 4320], 0
    movsxd rax, dword ptr [rsp + 96]
    mov [rsp + 4352], rax
    movsxd rax, dword ptr [rsp + 108]
    mov [rsp + 4360], rax
    movsxd rax, dword ptr [rsp + 112]
    mov [rsp + 4368], rax
    mov rcx, [r12 + KP_stdin]
    cmp rcx, -1
    jne 2f
    mov rcx, rax
2:  mov [rsp + 4376], rcx
    mov rcx, [r12 + KP_stdout]
    cmp rcx, -1
    jne 3f
    movsxd rcx, dword ptr [rsp + 120]
3:  mov [rsp + 4384], rcx
    mov rcx, [r12 + KP_stderr]
    cmp rcx, -1
    jne 4f
    movsxd rcx, dword ptr [rsp + 120]
4:  mov [rsp + 4392], rcx
    movsxd rax, dword ptr [rsp + 128]
    mov [rsp + 4400], rax
    SYS SYS_fork
    test rax, rax
    js .Lkp_backend_fail
    jz .Lkp_backend_child
    mov [rbx + KX_helper], rax
    mov qword ptr [rbx + KX_native_state], KN_OWNED
    movsxd rax, dword ptr [rsp + 100]
    mov [rbx + KX_control], rax
    mov dword ptr [rsp + 100], -1
    mov qword ptr [rbx + KX_native + KB_fds + 8], -1
    movsxd rax, dword ptr [rsp + 104]
    mov [rbx + KX_status], rax
    mov dword ptr [rsp + 104], -1
    mov qword ptr [rbx + KX_native + KB_fds + 16], -1
    movsxd rax, dword ptr [rsp + 116]
    mov [rbx + KX_output], rax
    mov dword ptr [rsp + 116], -1
    mov qword ptr [rbx + KX_native + KB_fds + 40], -1
    movsxd rax, dword ptr [rsp + 124]
    mov [rbx + KX_launchfd], rax
    mov dword ptr [rsp + 124], -1
    mov qword ptr [rbx + KX_native + KB_fds + 56], -1
    xor r15d, r15d
    jmp .Lkp_backend_cleanup
.Lkp_backend_child:
    lea rdi, [rsp + 4352]
    mov esi, 7
    call kp_remap
    test rax, rax
    js .Lkp_backend_child_error
    SYS SYS_setsid
    test rax, rax
    js .Lkp_backend_child_error6
    lea rdi, [rip + kp_root]
    SYS SYS_chdir
    test rax, rax
    js .Lkp_backend_child_error6
    lea rdi, [rsp + 160]
    lea rsi, [rsp + 4288]
    lea rdx, [rip + kp_safe_env]
    SYS SYS_execve
.Lkp_backend_child_error6:
    mov edx, 6
.Lkp_backend_child_error:
    mov [rsp + 80], eax
    mov rdi, rdx
    lea rsi, [rsp + 80]
    mov edx, 4
    SYS SYS_write
    mov edi, 111
    SYS SYS_exit
.Lkp_backend_fail:
    mov r15, rax
    test r15, r15
    js .Lkp_backend_cleanup
    mov r15, -5
.Lkp_backend_cleanup:
    lea rdi, [rbx + KX_native]
    xor esi, esi
    call kp_native_cleanup
    mov rdx, rax
    mov rax, r15
    EPILOGUE

FN kp_backend_poll
    PROLOGUE 16
    mov rbx, rdi
    test qword ptr [rbx + KX_close_unknown], 8
    jnz 4f
    test qword ptr [rbx + KX_close_known], 8
    jnz 4f
    mov rdi, [rbx + KX_launchfd]
    test rdi, rdi
    js 4f
    mov rax, [rbx + KX_launchlen]
    lea rsi, [rbx + KX_launchbuf + rax]
    mov edx, 4
    sub rdx, rax
    SYS SYS_read
    test rax, rax
    jg 1f
    cmp rax, -11
    je 4f
    cmp rax, -4
    je 4f
    jmp 3f
1:  add [rbx + KX_launchlen], rax
    cmp qword ptr [rbx + KX_launchlen], 4
    jne 4f
    mov eax, [rbx + KX_launchbuf]
    cmp eax, -1
    jg 3f
    cmp eax, -4095
    jl 3f
    mov qword ptr [rbx + KX_no_target], 1
    mov qword ptr [rbx + KX_preexec_failed], 1
    cmp dword ptr [rbx + KX_error], 0
    jne 2f
    mov [rbx + KX_error], eax
2:  or dword ptr [rbx + KX_flags], KP_FAILED
3:  mov rdi, rbx
    mov esi, 3
    call kp_close_field
    test rax, rax
    jns 4f
    mov qword ptr [rbx + KX_transport_bad], 1
    or dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
4:  cmp qword ptr [rbx + KX_native_state], KN_OWNED
    jne 9f
    mov rdi, [rbx + KX_helper]
    lea rsi, [rsp]
    mov edx, 1
    xor r10d, r10d
    SYS SYS_wait4
    test rax, rax
    jz 9f
    cmp rax, -4
    je 9f
    cmp rax, [rbx + KX_helper]
    je 5f
    cmp rax, -10
    jne 41f
    mov qword ptr [rbx + KX_native_state], KN_LOST
41: test rax, rax
    js 42f
    mov rax, -5
42: cmp dword ptr [rbx + KX_error], 0
    jne 43f
    mov [rbx + KX_error], eax
43: or dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
    jmp 9f
5:  mov qword ptr [rbx + KX_native_state], KN_REAPED
    mov dword ptr [rbx + KX_reaped], 1
    mov eax, [rsp]
    mov edx, eax
    and edx, 127
    jnz 6f
    shr eax, 8
    and eax, 255
    jmp 7f
6:  lea eax, [rdx + 128]
7:  mov [rbx + KX_helper_exit], eax
9:  xor eax, eax
    EPILOGUE

# Killing before INIT is safe: no target recipe has crossed the gate.
FN kp_backend_abort
    cmp qword ptr [rdi + KX_native_state], KN_OWNED
    jne 1f
    cmp qword ptr [rdi + KX_sent], 0
    jne 1f
    cmp qword ptr [rdi + KX_kill_once], 0
    jne 1f
    mov qword ptr [rdi + KX_kill_once], 1
    mov rdi, [rdi + KX_helper]
    mov esi, 9
    SYS SYS_kill
    ret
1:  xor eax, eax
    ret

FN kp_backend_recover
    cmp qword ptr [rdi + KX_no_target], 1
    je 1f
    mov rdi, [rdi + KX_target]
    test rdi, rdi
    jle 2f
    neg rdi
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    sete al
    movzx eax, al
    ret
1:  mov eax, 1
    ret
2:  xor eax, eax
    ret

FN kp_backend_close
    xor eax, eax
    ret

# Common helper IO is already mapped to raw POSIX0/1 and explicit target3/4/5.
FN kp_helper_adopt
    jmp kp_native_helper_init

# Close all descriptors at or above first. Linux fallback enumerates its private post-fork table.
FN kp_closefrom
.ifdef MACOS
    jmp kp_native_closefrom
.else
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov esi, -1
    xor edx, edx
    SYS SYS_close_range
    test rax, rax
    jz 9f
    cmp rax, -38
    jne 9f
    lea rdi, [rip + kp_fdpath]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 9f
    mov r13, rax
    mov qword ptr [rsp], 0
1:  mov rdi, r13
    mov rsi, r12
    mov edx, 65536
    SYS SYS_getdents64
    test rax, rax
    jle 6f
    mov r14, rax
    xor r15d, r15d
2:  lea rcx, [r15 + 20]
    cmp rcx, r14
    ja 7f
    movzx edx, word ptr [r12 + r15 + 16]
    cmp edx, 20
    jb 7f
    lea rax, [r15 + rdx]
    cmp rax, r14
    ja 7f
    mov [rsp + 8], rax
    inc qword ptr [rsp]
    cmp qword ptr [rsp], 65538
    ja 7f
    lea rsi, [r12 + r15 + 19]
    lea rcx, [r12 + rax]
    xor edi, edi
    xor edx, edx
3:  cmp rsi, rcx
    jae 7f
    movzx eax, byte ptr [rsi]
    inc rsi
    test eax, eax
    jz 4f
    sub eax, '0'
    cmp eax, 9
    ja 5f
    imul rdi, rdi, 10
    add rdi, rax
    cmp rdi, 0x7fffffff
    ja 7f
    inc edx
    jmp 3b
4:  test edx, edx
    jz 5f
    cmp rdi, rbx
    jb 5f
    cmp rdi, r13
    je 5f
    SYS SYS_close
    test rax, rax
    js 7f
5:  mov r15, [rsp + 8]
    cmp r15, r14
    jb 2b
    jmp 1b
6:  mov [rsp + 16], rax
    mov rdi, r13
    SYS SYS_close
    mov rax, [rsp + 16]
9:  EPILOGUE
7:  mov rdi, r13
    SYS SYS_close
    mov rax, -75
    EPILOGUE
.endif

.ifndef MACOS
# Native Linux signal/child adapters. Darwin counterparts are in mac/taskproc.s.
FN kp_native_helper_init
    PROLOGUE 48
    xor esi, esi
    mov rdi, rsp
    mov edx, 48
    call memset
    mov edi, 17                # SIGCHLD
    mov rsi, rsp
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    test rax, rax
    js 9f
    mov edi, 2                 # SIG_SETMASK
    lea rsi, [rsp + 32]
    xor edx, edx
    mov r10d, 8
    SYS 14
    test rax, rax
    js 9f
    mov edi, 36                # PR_SET_CHILD_SUBREAPER
    mov esi, 1
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    SYS SYS_prctl
9:  EPILOGUE

FN kp_native_reset_signals
    PROLOGUE 48
    mov rdi, rsp
    xor esi, esi
    mov edx, 48
    call memset
    mov ebx, 1
1:  cmp ebx, 9
    je 2f
    cmp ebx, 19
    je 2f
    mov edi, ebx
    mov rsi, rsp
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    test rax, rax
    js 9f
2:  inc ebx
    cmp ebx, 65
    jb 1b
    mov edi, 2
    lea rsi, [rsp + 32]
    xor edx, edx
    mov r10d, 8
    SYS 14
9:  EPILOGUE

FN kp_native_wait
    PROLOGUE 128
    mov r12, rdi
    mov rdi, rsp
    xor esi, esi
    mov edx, 128
    call memset
    mov edi, 1                 # P_PID
    mov rsi, r12
    mov rdx, rsp
    mov r10d, 0x1000005         # WEXITED|WNOHANG|WNOWAIT
    xor r8d, r8d
    SYS 247
    test rax, rax
    js 9f
    cmp dword ptr [rsp + 16], 0
    je 8f
    mov r8d, [rsp + 24]
    cmp dword ptr [rsp + 8], 1
    je 1f
    lea edx, [r8 + 128]
    cmp edx, 255
    jbe 2f
    mov edx, 255
    jmp 2f
1:  mov edx, r8d
    and edx, 255
2:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    mov edx, -1
    xor r8d, r8d
9:  EPILOGUE
.endif
.endif

# Helper controls have a finite20ms wait, including after control EOF.
.ifndef WINDOWS
FN kp_helper_pause
    PROLOGUE 16
    cmp qword ptr [rdi + KH_stopping], 0
    jne 1f
    cmp dword ptr [rdi + KH_eof], 0
    jne 1f
    mov dword ptr [rsp], 0
    mov word ptr [rsp + 4], POLLIN
    mov word ptr [rsp + 6], 0
    mov rdi, rsp
    mov esi, 1
    jmp 2f
1:  xor edi, edi
    xor esi, esi
2:  mov edx, 20
    SYS SYS_poll
    EPILOGUE

FN kp_target_prepare
    PROLOGUE 96
    mov rbx, rdi
    mov qword ptr [rsp], -1
    mov qword ptr [rsp + 8], -1
    mov rdi, rsp
    mov esi, O_CLOEXEC
    lea rdx, [rbx + KH_native]
    mov ecx, 0
    call kp_pipe_owned
    test rax, rax
    js .Lkp_target_prepare_fail
    lea rdi, [rsp + 8]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KH_native]
    mov ecx, 2
    call kp_pipe_owned
    test rax, rax
    js .Lkp_target_prepare_fail
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 4
    mov qword ptr [rsp + 48], 5
    movsxd rax, dword ptr [rsp]
    mov [rsp + 56], rax
    movsxd rax, dword ptr [rsp + 12]
    mov [rsp + 64], rax
    SYS SYS_fork
    test rax, rax
    js .Lkp_target_prepare_fail
    jz .Lkp_target_child
    mov [rbx + KH_target], rax
    movsxd rax, dword ptr [rsp + 4]
    mov [rbx + KH_gate], rax
    mov qword ptr [rbx + KH_native + KB_fds + 8], -1
    movsxd rax, dword ptr [rsp + 8]
    mov [rbx + KH_setup], rax
    mov qword ptr [rbx + KH_native + KB_fds + 16], -1
    xor r12d, r12d
    jmp .Lkp_target_owned_cleanup
.Lkp_target_child:
    mov r12, rbx
    cmp qword ptr [r12 + KH_mode], KP_EXTENSION
    jne 901f
    call confine_child
901:
    lea rdi, [rsp + 32]
    mov esi, 5
    call kp_remap
    test rax, rax
    js .Lkp_target_child_error
    mov edi, 3
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
    test rax, rax
    js .Lkp_target_child_error4
    SYS SYS_setsid
    test rax, rax
    js .Lkp_target_child_error4
    call kp_native_reset_signals
    test rax, rax
    js .Lkp_target_child_error4
    mov rdi, [r12 + KH_cwd]
    SYS SYS_chdir
    test rax, rax
    js .Lkp_target_child_error4
    mov dword ptr [rsp + 80], 0
1:  mov edi, 4
    lea rsi, [rsp + 80]
    mov edx, 4
    SYS SYS_write
    cmp rax, -4
    je 1b
    cmp rax, 4
    jne .Lkp_target_child_exit
2:  mov edi, 3
    lea rsi, [rsp + 80]
    mov edx, 1
    SYS SYS_read
    cmp rax, -4
    je 2b
    cmp rax, 1
    jne .Lkp_target_child_exit
    cmp byte ptr [rsp + 80], 1
    jne .Lkp_target_child_exit
    mov edi, 3
    SYS SYS_close
    mov rsi, [r12 + KH_argv]
    mov rdi, [rsi]
    mov rdx, [r12 + KH_envp]
    SYS SYS_execve
.Lkp_target_child_error4:
    mov edx, 4
.Lkp_target_child_error:
    mov [rsp + 80], eax
    mov rdi, rdx
    lea rsi, [rsp + 80]
    mov edx, 4
    SYS SYS_write
.Lkp_target_child_exit:
    mov edi, 127
    SYS SYS_exit
.Lkp_target_prepare_fail:
    mov r12, rax
    cmp dword ptr [rbx + KH_error], 0
    jne .Lkp_target_owned_cleanup
    mov [rbx + KH_error], eax
.Lkp_target_owned_cleanup:
    lea rdi, [rbx + KH_native]
    xor esi, esi
    call kp_native_cleanup
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    mov r13d, 9
1:  mov rdi, rbx
    mov rsi, r13
    call kh_close_field
    inc r13
    cmp r13, 12
    jb 1b
    mov rax, r12
    test rax, rax
    js 2f
    mov rax, [rbx + KH_cleanup]
2:  EPILOGUE

FN kp_target_start
    PROLOGUE 16
    mov rbx, rdi
    call kp_helper_alive
    test rax, rax
    js 9f
    mov byte ptr [rsp], 1
    mov rdi, [rbx + KH_gate]
    test rdi, rdi
    js 8f
    mov rsi, rsp
    mov edx, 1
    SYS SYS_write
    cmp rax, 1
    jne 8f
    mov rdi, rbx
    xor esi, esi
    call kh_close_field
    EPILOGUE
8:  mov rax, -5
9:  EPILOGUE

FN kp_target_stop
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + KH_stopping], 0
    jne 9f
    mov qword ptr [rbx + KH_stopping], 1
    call time_ms
    mov [rbx + KH_stop_at], rax
    add rax, 500
    mov [rbx + KH_next_kill], rax
    mov rdi, rbx
    xor esi, esi
    call kh_close_field
1:  mov rdi, [rbx + KH_target]
    test rdi, rdi
    jz 5f
    cmp qword ptr [rbx + KH_reaped], 0
    jne 9f
    cmp qword ptr [rbx + KH_group_ready], 0
    je 2f
    neg rdi
2:  mov esi, 15
    SYS SYS_kill
    jmp 9f
5:  mov dword ptr [rbx + KH_exit], 255
    or dword ptr [rbx + KH_flags], KP_DONE
    mov qword ptr [rbx + KH_dirty], 1
9:  xor eax, eax
    EPILOGUE

# Nonblocking setup/exec acknowledgement. Child emits zero after setsid and errno only on failure.
kp_setup_poll:
    PROLOGUE
    mov rbx, rdi
    test qword ptr [rbx + KH_unknown], 2
    jnz 9f
    test qword ptr [rbx + KH_known], 2
    jnz 9f
    mov rdi, [rbx + KH_setup]
    test rdi, rdi
    js 9f
    mov rax, [rbx + KH_setup_used]
    cmp rax, 8
    jae 8f
    lea rsi, [rbx + KH_setup_bytes + rax]
    mov edx, 8
    sub rdx, rax
    SYS SYS_read
    cmp rax, -11
    je 9f
    cmp rax, -4
    je 9f
    test rax, rax
    jle 6f
    add [rbx + KH_setup_used], rax
    cmp qword ptr [rbx + KH_setup_used], 4
    jb 9f
    mov eax, [rbx + KH_setup_bytes]
    test eax, eax
    jnz 7f
    cmp qword ptr [rbx + KH_group_ready], 0
    jne 1f
    mov qword ptr [rbx + KH_group_ready], 1
    or dword ptr [rbx + KH_flags], KP_READY
    mov qword ptr [rbx + KH_dirty], 1
1:  cmp qword ptr [rbx + KH_setup_used], 8
    jb 9f
    mov eax, [rbx + KH_setup_bytes + 4]
    jmp 7f
6:  test rax, rax
    jns 61f
    mov r12, rax
    jmp 11f
61: cmp qword ptr [rbx + KH_setup_used], 4
    jne 8f
    mov rdi, rbx
    mov esi, 1
    call kh_close_field
    test rax, rax
    js 10f
    mov qword ptr [rbx + KH_exec_ok], 1
9:  xor eax, eax
10: EPILOGUE
7:  cmp eax, -1
    jg 8f
    cmp eax, -4095
    jl 8f
    movsxd r12, eax
    jmp 11f
8:  mov r12, -5
11: mov rdi, rbx
    mov esi, r12d
    call kp_extension_setup_error
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call kh_note_primary
    mov rdi, rbx
    mov esi, 1
    call kh_close_field
    mov rax, r12
    EPILOGUE

FN kp_target_poll
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + KH_target], 0
    je .Lkp_target_poll_ok
    call kp_setup_poll
    test rax, rax
    js .Lkp_target_poll_return
    test dword ptr [rbx + KH_flags], KP_EXIT_KNOWN
    jnz .Lkp_target_poll_cleanup
    cmp qword ptr [rbx + KH_reaped], 0
    jne .Lkp_target_poll_proof
    mov rdi, [rbx + KH_target]
    call kp_native_wait
    test rax, rax
    js .Lkp_target_wait_lost
    jz .Lkp_target_poll_cleanup
    mov [rbx + KH_exit], edx
    mov [rbx + KH_raw], r8d
    or dword ptr [rbx + KH_flags], KP_EXIT_KNOWN
    mov qword ptr [rbx + KH_dirty], 1
    mov rdi, rbx
    call kp_target_stop
.Lkp_target_poll_cleanup:
    cmp qword ptr [rbx + KH_stopping], 0
    je .Lkp_target_poll_ok
    cmp qword ptr [rbx + KH_reaped], 0
    jne .Lkp_target_poll_proof
    call time_ms
    cmp rax, [rbx + KH_next_kill]
    jb 1f
    mov [rbx + KH_kill_at], rax
    add rax, 100
    mov [rbx + KH_next_kill], rax
    mov rdi, [rbx + KH_target]
    cmp qword ptr [rbx + KH_group_ready], 0
    je 11f
    neg rdi
11: mov esi, 9
    SYS SYS_kill
1:  test dword ptr [rbx + KH_flags], KP_EXIT_KNOWN
    jz .Lkp_target_poll_ok
    cmp qword ptr [rbx + KH_group_ready], 0
    je .Lkp_target_reap
.ifdef MACOS
    mov rdi, [rbx + KH_target]
    mov rsi, [rbx + KH_work]
    call kp_native_group_alone
    test eax, eax
    jz .Lkp_target_poll_ok
.else
    cmp qword ptr [rbx + KH_kill_at], 0
    je .Lkp_target_poll_ok
.endif
.Lkp_target_reap:
    mov rdi, [rbx + KH_target]
    xor esi, esi
    mov edx, 1
    xor r10d, r10d
    SYS SYS_wait4
    cmp rax, -4
    je .Lkp_target_poll_ok
    test rax, rax
    jz .Lkp_target_poll_ok
    cmp rax, [rbx + KH_target]
    jne .Lkp_target_wait_lost
    mov qword ptr [rbx + KH_reaped], 1
.Lkp_target_poll_proof:
.ifndef MACOS
    cmp qword ptr [rbx + KH_group_ready], 0
    je 2f
    mov rdi, rbx
    call kp_linux_children
    cmp eax, 1
    je 2f
    test rax, rax
    jns .Lkp_target_poll_ok
    or dword ptr [rbx + KH_flags], KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
    jmp .Lkp_target_poll_return
2:
.endif
    cmp qword ptr [rbx + KH_group_ready], 0
    je .Lkp_target_done
    mov rdi, [rbx + KH_target]
    neg rdi
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    je .Lkp_target_done
    or dword ptr [rbx + KH_flags], KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
.Lkp_target_poll_ok:
    xor eax, eax
.Lkp_target_poll_return:
    EPILOGUE
.Lkp_target_done:
    mov rdi, rbx
    call kp_setup_poll
    test rax, rax
    js .Lkp_target_poll_return
    cmp qword ptr [rbx + KH_setup], -1
    je 21f
    mov rax, [rbx + KH_unknown]
    or rax, [rbx + KH_known]
    test eax, 2
    jz .Lkp_target_poll_ok
21:
    cmp dword ptr [rbx + KH_exit], -1
    jne 3f
    mov dword ptr [rbx + KH_exit], 255
3:  or dword ptr [rbx + KH_flags], KP_DONE
    mov qword ptr [rbx + KH_dirty], 1
    xor eax, eax
    EPILOGUE
.Lkp_target_wait_lost:
    cmp rax, -4
    je .Lkp_target_poll_ok
    or dword ptr [rbx + KH_flags], KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
    test rax, rax
    js .Lkp_target_poll_return
    mov rax, -10
    EPILOGUE

.ifndef MACOS
.section .rodata
kp_children_prefix: .ascii "/proc/self/task/"
kp_children_suffix: .asciz "/children"
.text
# ECHILD is the only proof. Incomplete candidate enumeration merely delays cleanup.
kp_linux_children:
    PROLOGUE 224
    mov rbx, rdi
    xor r13d, r13d
1:  lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, 128
    call memset
    xor edi, edi
    xor esi, esi
    lea rdx, [rsp + 96]
    mov r10d, 0x1000005
    xor r8d, r8d
    SYS 247
    cmp rax, -10
    je .Lkp_children_none
    test rax, rax
    js .Lkp_children_return
    mov edi, [rsp + 112]
    test edi, edi
    jz .Lkp_children_scan
    xor esi, esi
    mov edx, 1
    xor r10d, r10d
    SYS SYS_wait4
    test rax, rax
    jle .Lkp_children_wait_error
    inc r13d
    cmp r13d, 32
    jb 1b
    jmp .Lkp_children_more
.Lkp_children_scan:
    cmp qword ptr [rbx + KH_scan_ready], 0
    jne .Lkp_children_candidates
    test qword ptr [rbx + KH_unknown], 32
    jnz .Lkp_children_scan_blocked
    test qword ptr [rbx + KH_known], 32
    jnz .Lkp_children_scan_blocked
    cmp qword ptr [rbx + KH_scan], -1
    jne 2f
    mov rdi, rsp
    lea rsi, [rip + kp_children_prefix]
    mov edx, 16
    call memcpy
    SYS SYS_getpid
    lea rdi, [rsp + 16]
    mov rsi, rax
    call fmt_u64
    lea rdi, [rsp + rax + 16]
    lea rsi, [rip + kp_children_suffix]
    mov edx, 10
    call memcpy
    mov rdi, rsp
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lkp_children_return
    mov [rbx + KH_scan], rax
    mov qword ptr [rbx + 336], 0
    mov qword ptr [rbx + 344], 0
2:  mov rdi, [rbx + KH_scan]
    mov rax, [rbx + 336]
    mov rsi, [rbx + KH_work]
    add rsi, rax
    mov edx, 262145
    sub rdx, rax
    cmp rdx, 65536
    jbe 3f
    mov edx, 65536
3:  SYS SYS_read
    cmp rax, -4
    je .Lkp_children_more
    cmp rax, -11
    je .Lkp_children_more
    test rax, rax
    js .Lkp_children_scan_error
    jz 4f
    add [rbx + 336], rax
    cmp qword ptr [rbx + 336], 262144
    jbe .Lkp_children_more
    mov rax, -75
    jmp .Lkp_children_scan_error
4:  mov rdi, rbx
    mov esi, 5
    call kh_close_field
    test rax, rax
    js .Lkp_children_return
    mov qword ptr [rbx + KH_scan_ready], 1
.Lkp_children_candidates:
    call time_ms
    add rax, 2
    mov [rsp + 80], rax
    xor r13d, r13d
5:  mov r14, [rbx + 344]
    cmp r14, [rbx + 336]
    jae .Lkp_children_scan_done
    mov r15, [rbx + KH_work]
    movzx eax, byte ptr [r15 + r14]
    inc r14
    cmp eax, ' '
    je 51f
    cmp eax, 9
    je 51f
    cmp eax, 10
    je 51f
    dec r14
    xor r12d, r12d
6:  cmp r14, [rbx + 336]
    jae 7f
    movzx eax, byte ptr [r15 + r14]
    cmp eax, ' '
    je 7f
    cmp eax, 9
    je 7f
    cmp eax, 10
    je 7f
    sub eax, '0'
    cmp eax, 9
    ja .Lkp_children_invalid
    imul r12, r12, 10
    add r12, rax
    cmp r12, 0x7fffffff
    ja .Lkp_children_invalid
    inc r14
    jmp 6b
7:  test r12, r12
    jz .Lkp_children_invalid
    mov [rbx + 344], r14
    mov rdi, r12
    call kp_native_wait
    cmp rax, -10
    je 8f
    test rax, rax
    js .Lkp_children_return
    jnz 71f
    mov rdi, r12
    mov esi, 9
    SYS SYS_kill
    test rax, rax
    js .Lkp_children_return
    jmp 8f
71: mov rdi, r12
    xor esi, esi
    mov edx, 1
    xor r10d, r10d
    SYS SYS_wait4
    test rax, rax
    jle .Lkp_children_wait_error
8:  inc r13d
    cmp r13d, 32
    jae .Lkp_children_more
    call time_ms
    cmp rax, [rsp + 80]
    jae .Lkp_children_more
    jmp 5b
51: mov [rbx + 344], r14
    jmp 5b
.Lkp_children_scan_done:
    mov qword ptr [rbx + KH_scan_ready], 0
.Lkp_children_more:
    xor eax, eax
.Lkp_children_return:
    EPILOGUE
.Lkp_children_none:
    mov rdi, [rbx + KH_scan]
    cmp rdi, -1
    je 9f
    mov rdi, rbx
    mov esi, 5
    call kh_close_field
9:  mov eax, 1
    EPILOGUE
.Lkp_children_wait_error:
    test rax, rax
    js .Lkp_children_return
    mov rax, -5
    EPILOGUE
.Lkp_children_invalid:
    mov qword ptr [rbx + KH_scan_ready], 0
    mov rax, -71
    EPILOGUE
.Lkp_children_scan_blocked:
    mov rax, -5
    jmp .Lkp_children_return
.Lkp_children_scan_error:
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call kh_note_primary
    mov rdi, rbx
    mov esi, 5
    call kh_close_field
    mov rax, r12
    EPILOGUE
.endif
.endif

.ifndef WINDOWS
# Duplicate an existing raw lifetime lease, preserving the same native lock description.
FN kp_lease_duplicate
    PROLOGUE
.ifdef MACOS
    mov esi, 67               # Darwin F_DUPFD_CLOEXEC
.else
    mov esi, 1030
.endif
    xor edx, edx
1:  SYS SYS_fcntl
    cmp rax, -4
    je 1b
    EPILOGUE
.endif
