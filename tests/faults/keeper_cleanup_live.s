.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/taskproc.inc"
.section .rodata
kcl_marker: .asciz "--process-keeper"
kcl_pidname: .asciz "native-target-pid"
.bss
kcl_fired: .quad 0
kcl_force_raw: .quad 0
kcl_force_fd: .quad 0
kcl_helper_frame: .quad 0
kcl_read_fault: .quad 0
kcl_owner: .quad 0
kcl_selections: .quad 0
kcl_guards: .quad 0
kcl_statbuf: .zero 64
kcl_forkpid: .quad 0
.text
kcl_is_helper:
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jb 1f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + kcl_marker]
    call strcmp_eq
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
FN ext_fd_close_checked
    PROLOGUE 96
    mov rbx, rdi
    call kcl_is_helper
    test eax, eax
    jz 9f
    cmp qword ptr [rip + kcl_fired], 0
    jne 9f
.if KCL_MODE <= 2 || KCL_MODE == 10
    cmp rbx, 3
    jne 9f
.else
.if KCL_MODE == 7 || KCL_MODE == 11 || KCL_MODE == 12
    cmp qword ptr [rip + kcl_force_fd], 0
    je 9f
.else
    jmp 9f
.endif
.endif
    mov qword ptr [rip + kcl_fired], 1
.if KCL_MODE != 2
.ifdef WINDOWS
    mov rdi, rbx
    call win_fd
    test rax, rax
    jz 8f
    mov rcx, [rax + FD_handle]
    API CloseHandle
    test eax, eax
    jz 8f
.if KCL_MODE == 1
    # Consumed outcome also retires its virtual reservation and path.
    mov rdi, rbx
    call win_fd
    mov r12, rax
    mov rdi, [rax + FD_path]
    call mem_free
    mov rdi, r12
    xor esi, esi
    mov edx, FD_SIZE
    call memset
.endif
.else
    mov rdi, rbx
    call kcl_real_fd_close
    test rax, rax
    jnz 8f
.endif
.endif
    mov rax, -13
.if KCL_MODE == 2
    xor edx, edx
.else
.if KCL_MODE == 1
    mov edx, 1
.else
    mov edx, 2
.endif
.endif
    EPILOGUE
9:  mov rdi, rbx
    call kcl_real_fd_close
    EPILOGUE
8:  mov edi, 73
    call sys_exit
FN ext_root_close
    PROLOGUE
    mov rbx, rdi
    mov rax, [rip + kcl_owner]
    test rax, rax
    jz 90f
    cmp rbx, [rax + KH_lease]
    jne 90f
    cmp qword ptr [rax + KH_target], 0
    je 90f
    cmp qword ptr [rax + KH_reaped], 0
    je 8f
90:

    call kcl_is_helper
    test eax, eax
    jz 9f
    cmp qword ptr [rip + kcl_force_raw], 0
    je 9f
    cmp qword ptr [rip + kcl_fired], 0
    jne 9f
    mov qword ptr [rip + kcl_fired], 1
    mov rdi, rbx
    call kcl_real_root_close
    test rax, rax
    jnz 8f
    mov rax, -13
    mov edx, 2
    EPILOGUE
9:  mov rdi, rbx
    call kcl_real_root_close
    EPILOGUE
8:  mov edi, 73
    call sys_exit
FN ext_store_selection_matches
    PROLOGUE
    call kcl_real_selection
    mov r12, rax
    mov r13, rdx
.if KCL_MODE == 3
    call kcl_is_helper
    test eax, eax
    jz 1f
    test r12, r12
    js 1f
    mov r13, -13
1:
.endif
.if KCL_MODE == 13
    call kcl_is_helper
    test eax, eax
    jz 2f
    inc qword ptr [rip + kcl_selections]
    cmp qword ptr [rip + kcl_selections], 2
    jne 2f
    mov r12, -22
    mov r13, -13
2:
.endif
    mov rax, r12
    mov rdx, r13
    EPILOGUE
FN ext_store_lease_try
    PROLOGUE
    call kcl_real_lease
    mov r12, rax
    mov r13, rdx
.if KCL_MODE == 4
    call kcl_is_helper
    test eax, eax
    jz 1f
    test r12, r12
    js 1f
    mov r13, -13
1:
.endif
.if KCL_MODE == 15
    call kcl_is_helper
    test eax, eax
    jz 2f
    test r12, r12
    js 8f
    mov rdi, r12
    call kcl_real_root_close
    test rax, rax
    jnz 8f
    mov r12, -22
    mov r13, -13
2:
.endif
    mov rax, r12
    mov rdx, r13
    EPILOGUE
8:  mov edi, 73
    call sys_exit
FN ext_store_guard_try
    PROLOGUE
    call kcl_real_guard
    mov r12, rax
    mov r13, rdx
    mov r14, rcx
.if KCL_MODE == 5
    call kcl_is_helper
    test eax, eax
    jz 1f
    mov r14, -13
1:
.endif
.if KCL_MODE == 14 || KCL_MODE == 16
    call kcl_is_helper
    test eax, eax
    jz 2f
    inc qword ptr [rip + kcl_guards]
.if KCL_MODE == 14
    cmp qword ptr [rip + kcl_guards], 2
.else
    cmp qword ptr [rip + kcl_guards], 1
.endif
    jne 2f
    test r12, r12
    jz 8f
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz 8f
    xor r12d, r12d
    mov r13, -22
    mov r14, -13
2:
.endif
    mov rax, r12
    mov rdx, r13
    mov rcx, r14
    EPILOGUE
8:  mov edi, 73
    call sys_exit
FN kh_guard_release
    PROLOGUE
.if KCL_MODE == 6
    mov qword ptr [rip + kcl_force_raw], 1
.endif
    call kcl_real_guard_release
    mov qword ptr [rip + kcl_force_raw], 0
    EPILOGUE
.ifndef WINDOWS
FN kh_close_probe
    PROLOGUE
.if KCL_MODE == 7 || KCL_MODE == 11
    mov qword ptr [rip + kcl_force_fd], 1
.endif
    call kcl_real_probe
    mov qword ptr [rip + kcl_force_fd], 0
    EPILOGUE
.endif
FN mem_alloc_try
    PROLOGUE
    mov r12, rdi
    call kcl_real_alloc
    mov r13, rax
.if KCL_MODE == 9
    cmp r12, KP_FRAME_MAX + 8720 + 1048576
    jne 1f
    call kcl_is_helper
    test eax, eax
    jz 1f
    mov [rip + kcl_helper_frame], r13
1:
.endif
    mov rax, r13
    EPILOGUE
FN kcl_munmap
.if KCL_MODE == 9
    lea rcx, [rdi + 16]
    cmp rcx, [rip + kcl_helper_frame]
    jne 1f
    mov rax, -5
    ret
1:
.endif
    SYS SYS_munmap
    ret

FN kcl_target_fork
.if KCL_MODE == 12
    PROLOGUE
    SYS SYS_fork
    test rax, rax
    jle 9f
    mov r12, rax
    mov [rip + kcl_forkpid], rax
    mov rax, [rip + kcl_owner]
    mov rax, [rax + KH_authctx]
    mov rdi, [rax + AX_strings + 32]
    lea rsi, [rip + kcl_pidname]
    call path_join
    mov r13, rax
    mov rdi, rax
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js 8f
    mov r14, rax
    mov rdi, rax
    lea rsi, [rip + kcl_forkpid]
    mov edx, 8
    SYS SYS_write
    cmp rax, 8
    jne 8f
    mov rdi, r14
    call kcl_real_fd_close
    test rax, rax
    jnz 8f
    mov rdi, r13
    call prep_cleanup_free
    cmp rdx, 1
    jne 8f
    mov rax, r12
9:  EPILOGUE
8:  mov edi, 73
    call sys_exit
.else
    mov rax, -11
    ret
.endif

.ifndef WINDOWS
FN kcl_probe_stat
    mov rax, -22
    ret
FN kp_setup_poll
    PROLOGUE
.if KCL_MODE == 12
    mov qword ptr [rip + kcl_force_fd], 1
.endif
    call kcl_real_setup_poll
    mov qword ptr [rip + kcl_force_fd], 0
    EPILOGUE
FN kcl_setup_read
    cmp qword ptr [rip + kcl_read_fault], 0
    jne 1f
    mov qword ptr [rip + kcl_read_fault], 1
    mov rax, -5
    ret
1:  SYS SYS_read
    ret
.endif

# Inspect both diagnostics at their actual helper boundary, before later cleanup runs.
FN kp_extension_authorize
    PROLOGUE
    mov rbx, rdi
    mov [rip + kcl_owner], rdi
    call kcl_real_authorize
.if KCL_MODE == 15 || KCL_MODE == 16
    cmp rax, -22
    jne 8f
    cmp qword ptr [rbx + KH_cleanup], -13
    jne 8f
.endif
    EPILOGUE
8:  mov edi, 73
    call sys_exit
FN kp_extension_start
    PROLOGUE
    mov rbx, rdi
    call kcl_real_start
.if KCL_MODE == 13 || KCL_MODE == 14
    cmp rax, -22
    jne 8f
    cmp qword ptr [rbx + KH_cleanup], -13
    jne 8f
.endif
    EPILOGUE
8:  mov edi, 73
    call sys_exit

# An independent exclusive open must remain blocked by the parent's retained metadata lease.
kcl_parent_lease_check:
    PROLOGUE
    mov rdi, [rip + tek_plan + KE_root]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz 8f
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + tek_owner]
    lea rdx, [rip + tek_name]
    xor ecx, ecx
    mov r8d, 1
    xor r9d, r9d
    call ext_store_lease_try
    cmp rax, -11
    jne 8f
    test rdx, rdx
    jnz 8f
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz 8f
    EPILOGUE
8:  mov edi, 73
    call sys_exit

.ifndef WINDOWS
# Mode12's setup read fails before wire identity. Observe the actual fork result out of band.
kcl_parent_target_check:
    PROLOGUE
    mov rdi, [rip + tek_plan + KE_state]
    lea rsi, [rip + kcl_pidname]
    call path_join
    mov r12, rax
    mov rdi, rax
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 8f
    mov r13, rax
    mov rdi, rax
    lea rsi, [rip + kcl_forkpid]
    mov edx, 8
    SYS SYS_read
    cmp rax, 8
    jne 8f
    mov rdi, r13
    call kcl_real_fd_close
    test rax, rax
    jnz 8f
    mov rdi, r12
    call prep_cleanup_free
    cmp rdx, 1
    jne 8f
    mov rdi, [rip + kcl_forkpid]
    test rdi, rdi
    jle 8f
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne 8f
    mov rdi, [rip + kcl_forkpid]
    neg rdi
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne 8f
    EPILOGUE
8:  mov edi, 73
    call sys_exit
.endif
