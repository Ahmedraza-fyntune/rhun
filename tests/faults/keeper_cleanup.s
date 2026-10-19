.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/taskproc.inc"
.section .rodata
kcf_bad_cwd: .asciz "relative"
kcf_null: .asciz "/dev/null"
kcf_delays: .quad 16,32,64,128,256,512,1000,1000
kcf_offsets: .quad KX_control,KX_status,KX_output,KX_launchfd,KX_lease,KX_job,KX_helper
.data
kcf_spec: .quad 0,0,kcf_bad_cwd,-1,-1,-1,KP_TASK,0,0
.bss
kcf_frame: .quad 0
kcf_fail_unmap: .quad 0
kcf_unmaps: .quad 0
kcf_close_calls: .quad 0
kcf_close_active: .quad 0
kcf_target: .quad 0
kcf_raw: .quad 0
kcf_source: .quad 0
kcf_now: .quad 0
kcf_time_calls: .quad 0
kcf_info: .zero 64
kcf_fd_snapshot: .zero 64
kcf_attr_calls: .quad 0
kcf_slot: .quad 0
kcf_poison: .quad 0
kcf_pathlen: .quad 0
kcf_pathbytes: .zero 4096
kcf_record_mem: .quad 0
.text
kcf_fail:
    mov edi, 73
    call sys_exit
FN time_ms
    inc qword ptr [rip + kcf_time_calls]
    mov rax, [rip + kcf_now]
    ret
FN mem_alloc_try
    PROLOGUE
    mov rbx, rdi
.if KCF_CASE == 5
    cmp rbx, KP_FRAME_MAX
    jne 9f
    xor eax, eax
    EPILOGUE
9:
.endif
    call kcf_real_alloc
.if KCF_CASE == 0 || KCF_CASE == 1 || KCF_CASE == 2 || KCF_CASE == 3
    cmp rbx, KP_FRAME_MAX
    jne 1f
    mov [rip + kcf_frame], rax
1:
.endif
    EPILOGUE
FN kcf_munmap
    lea rcx, [rdi + 16]
    cmp rcx, [rip + kcf_frame]
    jne 1f
    inc qword ptr [rip + kcf_unmaps]
    cmp qword ptr [rip + kcf_fail_unmap], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN ext_root_close
    cmp qword ptr [rip + kcf_raw], 0
    je kcf_real_root_close
    jmp kcf_close_hook
FN ext_fd_close_checked
    cmp qword ptr [rip + kcf_raw], 0
    jne kcf_real_fd_close
    jmp kcf_close_hook
kcf_close_hook:
    cmp qword ptr [rip + kcf_close_active], 0
    je kcf_real_close
    cmp rdi, [rip + kcf_target]
    jne kcf_real_close
    PROLOGUE 96
    inc qword ptr [rip + kcf_close_calls]
.if KCF_DISP != 0
.ifdef WINDOWS
.if KCF_DISP == 2
    cmp qword ptr [rip + kcf_raw], 0
    jne 2f
    call win_fd
    test rax, rax
    jz kcf_fail
    mov rcx, [rax + FD_handle]
    API CloseHandle
    test eax, eax
    jz kcf_fail
    jmp 3f
2:
.endif
.endif
    call kcf_real_close
    test rax, rax
    jnz kcf_fail
    cmp rdx, 1
    jne kcf_fail
3:
.endif
    mov rax, -13
    mov edx, KCF_DISP
    EPILOGUE
kcf_real_close:
    cmp qword ptr [rip + kcf_raw], 0
    jne kcf_real_root_close
    jmp kcf_real_fd_close
kcf_make_fd:
    lea rdi, [rip + kcf_null]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js kcf_fail
    ret
kcf_make_raw:
.ifdef WINDOWS
    PROLOGUE 96
    xor ecx, ecx
    mov edx, 1
    xor r8d, r8d
    xor r9d, r9d
    API CreateEventW
    test rax, rax
    jz kcf_fail
    EPILOGUE
.else
    jmp kcf_make_fd
.endif
FN kcf_prepare_hook
    PROLOGUE
    mov rbx, rdi
.if KCF_CASE == 1 || KCF_CASE == 2 || KCF_CASE == 3 || KCF_CASE == 6
    mov rdi, [rip + kcf_source]
    call kp_lease_duplicate
    test rax, rax
    js kcf_fail
    mov [rbx + KX_lease], rax
    mov [rip + kcf_target], rax
.endif
    EPILOGUE
FN main
    PROLOGUE 32
    mov qword ptr [rip + kcf_now], 1000
    mov r15, [rip + g_mem_live]
    call keeper_cleanup_contract_version
    cmp rax, 1
    jne kcf_fail
.if KCF_CASE == 5
    xor edi, edi
    mov rdx, -5
    mov rcx, -13
    call keeper_prepare
    cmp rax, -22
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    test rcx, rcx
    jnz kcf_fail
    mov qword ptr [rip + kcf_spec + KP_mode], 99
    lea rdi, [rip + kcf_spec]
    mov rdx, -5
    mov rcx, -13
    call keeper_prepare
    cmp rax, -95
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    test rcx, rcx
    jnz kcf_fail
    mov qword ptr [rip + kcf_spec + KP_mode], KP_TASK
    lea rdi, [rip + kcf_spec]
    mov rdx, -5
    mov rcx, -13
    call keeper_prepare
    cmp rax, -12
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    test rcx, rcx
    jnz kcf_fail
    cmp [rip + g_mem_live], r15
    jne kcf_fail
    jmp kcf_success
.endif
.if KCF_CASE == 7
    lea r13, [rip + kp_slots]
    mov rdi, r13
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    mov qword ptr [r13 + KX_id], 7001
    mov qword ptr [r13 + KX_control], -1
    mov qword ptr [r13 + KX_status], -1
    mov qword ptr [r13 + KX_output], -1
    mov qword ptr [r13 + KX_launchfd], -1
    mov qword ptr [r13 + KX_lease], -1
    mov qword ptr [r13 + KX_status_eof], 1
    mov qword ptr [r13 + KX_native_state], KN_OWNED
    lea rdi, [r13 + KX_native]
    call kp_native_init
    SYS SYS_getpid
    mov [r13 + KX_helper], rax
    mov rdi, r13
    call kp_backend_poll
    cmp qword ptr [r13 + KX_native_state], KN_LOST
    jne kcf_fail
    cmp dword ptr [r13 + KX_reaped], 0
    jne kcf_fail
    mov rdi, r13
    call kp_backend_abort        # The poison PID is this fixture: LOST must never signal it.
    mov edi, 7001
    call keeper_close_checked
    cmp rax, -16
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    cmp qword ptr [r13 + KX_lifetime_ready], 0
    jne kcf_fail
    jmp kcf_success
.endif
.if KCF_CASE == 6
    call kcf_make_raw
    mov [rip + kcf_source], rax
    mov qword ptr [rip + kcf_raw], 1
    mov qword ptr [rip + kcf_close_active], 1
    xor r14d, r14d
61: lea rdi, [rip + kcf_spec]
    call keeper_prepare
    test rax, rax
    jle kcf_fail
    cmp rdx, -22
    jne kcf_fail
    cmp rcx, -13
    jne kcf_fail
    inc r14
    cmp r14, KP_TASK_MAX
    jb 61b
    lea rdi, [rip + kcf_spec]
    call keeper_prepare
    cmp rax, -11
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    test rcx, rcx
    jnz kcf_fail
    cmp qword ptr [rip + kcf_close_calls], KP_TASK_MAX
    jne kcf_fail
    jmp kcf_finish_source
.endif
.if KCF_CASE <= 3
.if KCF_CASE == 0
    mov qword ptr [rip + kcf_fail_unmap], 1
.else
    call kcf_make_raw
    mov [rip + kcf_source], rax
    mov qword ptr [rip + kcf_raw], 1
    mov qword ptr [rip + kcf_close_active], 1
.endif
    lea rdi, [rip + kcf_spec]
    call keeper_prepare
.if KCF_CASE == 3
    cmp rax, -22
    jne kcf_fail
    cmp rcx, -13
    jne kcf_fail
    jmp kcf_finish_source
.else
    test rax, rax
    jle kcf_fail
    mov r12, rax
    cmp rdx, -22
    jne kcf_fail
.if KCF_CASE == 0
    cmp rcx, -5
.else
    cmp rcx, -13
.endif
    jne kcf_fail
    mov rdi, r12
    call kp_find
    test rax, rax
    jz kcf_fail
    mov r13, rax
.if KCF_CASE == 0
    mov rax, [rip + kcf_frame]
    cmp [r13 + KX_frame], rax
    jne kcf_fail
    lea rax, [r15 + 1]
    cmp [rip + g_mem_live], rax
    jne kcf_fail
    jmp kcf_memory_retry
.else
    mov rax, [rip + kcf_target]
    cmp [r13 + KX_lease], rax
    jne kcf_fail
    jmp kcf_close_assert
.endif
.endif
.else
    lea r13, [rip + kp_slots]
    mov rdi, r13
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    mov qword ptr [r13 + KX_id], 7001
    mov r12d, 7001
    mov qword ptr [r13 + KX_control], -1
    mov qword ptr [r13 + KX_status], -1
    mov qword ptr [r13 + KX_output], -1
    mov qword ptr [r13 + KX_launchfd], -1
    mov qword ptr [r13 + KX_lease], -1
    mov qword ptr [r13 + KX_lifetime_ready], 1
    mov qword ptr [r13 + KX_native_state], KN_REAPED
    mov dword ptr [r13 + KX_reaped], 1
    mov dword ptr [r13 + KX_flags], KP_DONE
    lea rdi, [r13 + KX_native]
    call kp_native_init
.if KCF_INDEX >= 26
    mov edi, 262144
    call mem_alloc_try
    test rax, rax
    jz kcf_fail
    mov [rip + kcf_frame], rax
.if KCF_INDEX == 34
    mov [r13 + KX_frame], rax
.else
    mov [r13 + KX_native + KB_mem + (KCF_INDEX - 26)*8], rax
.endif
    mov qword ptr [rip + kcf_fail_unmap], 1
.if KCF_CASE == 8
    mov qword ptr [r13 + KX_native + KB_attr], 1
.endif
.else
.if KCF_INDEX == 4 || KCF_INDEX == 5 || KCF_INDEX == 6 || KCF_INDEX >= 16
    mov qword ptr [rip + kcf_raw], 1
    call kcf_make_raw
.else
    call kcf_make_fd
.endif
    mov [rip + kcf_target], rax
    call kcf_record_take
.if KCF_INDEX < 7
    lea rcx, [rip + kcf_offsets]
    mov rcx, [rcx + KCF_INDEX*8]
    lea rdx, [r13 + rcx]
    mov [rip + kcf_slot], rdx
    mov [r13 + rcx], rax
.else
    lea rdx, [r13 + KX_native + (KCF_INDEX - 7)*8]
    mov [rip + kcf_slot], rdx
    mov [r13 + KX_native + (KCF_INDEX - 7)*8], rax
.endif
    mov qword ptr [rip + kcf_close_active], 1
.endif
.if KCF_CASE == 4
    mov edi, 262144
    call mem_alloc_try
    test rax, rax
    jz kcf_fail
    mov [rip + kcf_frame], rax
    mov [r13 + KX_frame], rax
    mov qword ptr [rip + kcf_fail_unmap], 1
.endif
    mov rdi, r12
    call keeper_close_checked
.if KCF_INDEX >= 26
    cmp rax, -5
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    jmp kcf_memory_retry
.else
.ifndef WINDOWS
.if KCF_INDEX == 5 || KCF_INDEX == 6
    test rax, rax
    jnz kcf_fail
    cmp rdx, 1
    jne kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 0
    jne kcf_fail
    mov rdi, [rip + kcf_target]
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js kcf_fail
    mov rdi, [rip + kcf_target]
    call kcf_real_root_close
    jmp kcf_success
.endif
.endif
    cmp rax, -13
    jne kcf_fail
    cmp rdx, KCF_DISP
    jne kcf_fail
.if KCF_CASE == 4
    jmp kcf_mixed
.endif
.if KCF_DISP == 1
    mov rdi, r12
    call kp_find
    test rax, rax
    jnz kcf_fail
    jmp kcf_success
.endif
    jmp kcf_close_assert
.endif
.endif
kcf_mixed:
    cmp qword ptr [rip + kcf_unmaps], 1
    jne kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 1
    jne kcf_fail
    mov rdi, r12
    call keeper_close_checked
    cmp rdx, 2
    jne kcf_fail
    cmp qword ptr [rip + kcf_unmaps], 1
    jne kcf_fail
    mov qword ptr [rip + kcf_fail_unmap], 0
    mov qword ptr [rip + kcf_now], 1016
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -13
    jne kcf_fail
    cmp rdx, 2
    jne kcf_fail
    cmp qword ptr [rip + kcf_unmaps], 2
    jne kcf_fail
    mov r14, [rip + kcf_time_calls]
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -13
    jne kcf_fail
    cmp rdx, 2
    jne kcf_fail
    cmp [rip + kcf_time_calls], r14
    jne kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 1
    jne kcf_fail
    cmp [rip + g_mem_live], r15
    jne kcf_fail
    jmp kcf_success
kcf_memory_retry:
.if KCF_CASE == 9
    xor r14d, r14d
    lea rbx, [rip + kcf_delays]
1:  mov rax, [rbx + r14*8]
    cmp [r13 + KX_retry_delay], rax
    jne kcf_fail
    add rax, [rip + kcf_now]
    cmp [r13 + KX_retry_due], rax
    jne kcf_fail
    mov [rsp + 16], rax
    dec rax
    mov [rip + kcf_now], rax
    mov rdi, r12
    call keeper_close_checked
    test rdx, rdx
    jnz kcf_fail
    lea rax, [r14 + 1]
    cmp [rip + kcf_unmaps], rax
    jne kcf_fail
    mov rax, [rsp + 16]
    cmp [r13 + KX_retry_due], rax
    jne kcf_fail
    mov [rip + kcf_now], rax
    mov rdi, r12
    call keeper_close_checked
    test rdx, rdx
    jnz kcf_fail
    lea rax, [r14 + 2]
    cmp [rip + kcf_unmaps], rax
    jne kcf_fail
    inc r14
    cmp r14, 8
    jb 1b
    mov qword ptr [rip + kcf_fail_unmap], 0
    mov rax, [r13 + KX_retry_due]
    mov [rip + kcf_now], rax
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -5
    jne kcf_fail
    cmp rdx, 1
    jne kcf_fail
    cmp qword ptr [rip + kcf_unmaps], 10
    jne kcf_fail
    cmp [rip + g_mem_live], r15
    jne kcf_fail
    jmp kcf_success
.endif
    cmp qword ptr [rip + kcf_unmaps], 1
    jne kcf_fail
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -5
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    cmp qword ptr [rip + kcf_unmaps], 1
    jne kcf_fail
    mov qword ptr [rip + kcf_fail_unmap], 0
    mov qword ptr [rip + kcf_now], 1016
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -5
    jne kcf_fail
    cmp rdx, 1
    jne kcf_fail
    cmp qword ptr [rip + kcf_unmaps], 2
    jne kcf_fail
.if KCF_CASE == 8
    cmp qword ptr [rip + kcf_attr_calls], 1
    jne kcf_fail
.endif
    cmp [rip + g_mem_live], r15
    jne kcf_fail
    jmp kcf_success
kcf_close_assert:
.if KCF_CASE <= 3
    lea rax, [r13 + KX_lease]
    mov [rip + kcf_slot], rax
.endif
    call kcf_record_check
    mov rax, [rip + kcf_slot]
    mov rdx, [rip + kcf_target]
    cmp [rax], rdx
    jne kcf_fail
.ifndef WINDOWS
.if KCF_DISP == 2
    # Replace the actually closed number. Automatic cleanup must never close this new object.
    call kcf_make_fd
    mov rbx, rax
    cmp rax, [rip + kcf_target]
    je 81f
    mov rdi, rax
    mov rsi, [rip + kcf_target]
    SYS SYS_dup2
    test rax, rax
    js kcf_fail
    mov rdi, rbx
    call kcf_real_fd_close
81: mov rax, [rip + kcf_target]
    mov [rip + kcf_poison], rax
.endif
.endif
    cmp qword ptr [rip + kcf_close_calls], 1
    jne kcf_fail
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -13
    jne kcf_fail
    cmp rdx, KCF_DISP
    jne kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 1
    jne kcf_fail
    mov rdi, r12
.if KCF_CASE <= 3
    mov esi, 4
.else
    mov esi, KCF_INDEX
.endif
    call keeper_retry_known
.if KCF_DISP == 2
    cmp rax, -22
    jne kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 1
    jne kcf_fail
    mov rdi, r12
    call kp_find
    test rax, rax
    jz kcf_fail
    mov rax, [rip + kcf_slot]
    mov rdx, [rip + kcf_target]
    cmp [rax], rdx
    jne kcf_fail
.ifndef WINDOWS
    mov rdi, [rip + kcf_poison]
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js kcf_fail
    mov rdi, [rip + kcf_poison]
    call kcf_real_fd_close
.endif
    jmp kcf_success
.else
    # The explicit retry is the sole authority to attempt a known retained numeric close.
    cmp rax, -13
    jne kcf_fail
    test rdx, rdx
    jnz kcf_fail
    cmp qword ptr [rip + kcf_close_calls], 2
    jne kcf_fail
    mov qword ptr [rip + kcf_close_active], 0
    mov rdi, r12
.if KCF_CASE <= 3
    mov esi, 4
.else
    mov esi, KCF_INDEX
.endif
    call keeper_retry_known
    test rax, rax
    jnz kcf_fail
    cmp rdx, 1
    jne kcf_fail
    mov rdi, r12
    call keeper_close_checked
    cmp rax, -13
    jne kcf_fail
    cmp rdx, 1
    jne kcf_fail
.endif
kcf_finish_source:
    mov rdi, [rip + kcf_source]
    test rdi, rdi
    jz kcf_success
    call kcf_real_root_close
kcf_success:
    xor eax, eax
    EPILOGUE

.ifdef WINDOWS
FN kcf_DeleteAttr
    inc qword ptr [rip + kcf_attr_calls]
    # A native callee owns all32 bytes of caller shadow space.
    mov qword ptr [rsp + 8], 0x11111111
    mov qword ptr [rsp + 16], 0x22222222
    mov qword ptr [rsp + 24], 0x33333333
    mov qword ptr [rsp + 32], 0x44444444
    ret
.endif

# The complete Windows FD record and its path allocation remain owned on either refusal.
kcf_record_take:
.ifdef WINDOWS
    PROLOGUE
    mov r12, rax
    cmp qword ptr [rip + kcf_raw], 0
    jne 2f
    mov rdi, r12
    call win_fd
    test rax, rax
    jz kcf_fail
    mov rbx, rax
    lea rdi, [rip + kcf_fd_snapshot]
    mov rsi, rax
    mov edx, FD_SIZE
    call memcpy
    mov rdi, [rbx + FD_path]
    test rdi, rdi
    jz 1f
    mov esi, 4095
    call ext_root_length
    test rax, rax
    js kcf_fail
    inc rax
    mov [rip + kcf_pathlen], rax
    lea rdi, [rip + kcf_pathbytes]
    mov rsi, [rbx + FD_path]
    mov rdx, rax
    call memcpy
1:  mov rax, [rip + g_mem_live]
    mov [rip + kcf_record_mem], rax
2:  mov rax, r12
    EPILOGUE
.else
    ret
.endif
kcf_record_check:
.ifdef WINDOWS
    PROLOGUE
    cmp qword ptr [rip + kcf_raw], 0
    jne 2f
    mov rdi, [rip + kcf_target]
    call win_fd
    test rax, rax
    jz kcf_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + kcf_fd_snapshot]
    mov edx, FD_SIZE
    call memeq
    test eax, eax
    jz kcf_fail
    mov rdx, [rip + kcf_pathlen]
    test rdx, rdx
    jz 1f
    mov rdi, [rbx + FD_path]
    lea rsi, [rip + kcf_pathbytes]
    call memeq
    test eax, eax
    jz kcf_fail
1:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + kcf_record_mem]
    jne kcf_fail
2:  EPILOGUE
.else
    ret
.endif
