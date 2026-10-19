.include "rhun.inc"
.include "app/taskproc.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.section .rodata
tek_target: .asciz "--extension-target"
lc_protocol_target: .asciz "--extension-protocol-target"
lc_barrier: .byte 1
tek_home_key: .asciz "HOME"
lc_state_key: .asciz "TEST_KEEPER_STATE"
lc_state_prefix: .asciz "TEST_KEEPER_STATE="
lc_approved_key: .asciz "TEST_KEEPER_APPROVED"
lc_approved_prefix: .asciz "TEST_KEEPER_APPROVED="
tek_home_prefix: .asciz "HOME="
tek_owner: .asciz "owner"
tek_name: .asciz "name"
tek_approved: .asciz "approved"
tek_expected: .ascii "keeper"
lc_hello: .ascii "hello 1\n"
tek_ok: .asciz "ok supervised extension lifecycle\n"
lc_marker_name: .asciz "ran"
lc_stop_text: .asciz "fixture requested stop"
.bss
.p2align 4
tek_plan: .zero KE_SIZE
tek_spec: .zero KP_SIZE
tek_args: .zero 40
tek_home: .zero 4101
tek_program: .zero 4096
tek_env: .zero 8224
tek_info: .zero 24
tek_owned_plan: .quad 0
tek_auth: .quad 0
tek_handle: .quad 0
tek_lease: .quad 0
tek_deadline: .quad 0
tek_started: .quad 0
tek_flags: .quad 0
tek_used: .quad 0
tek_eof: .quad 0
tek_stage: .quad 0
tek_bytes: .zero 65536
tek_signal: .zero 32
.p2align 3
lc_extension: .zero EXT_SIZE
lc_arguments: .zero 12300
lc_state_env: .zero 4120
lc_approved_env: .zero 4120
lc_marker: .quad 0
lc_helper: .quad 0
lc_case: .quad 0
lc_stop_reason: .quad 0
lc_protocol_mode: .quad 0
.text
FN main
    PROLOGUE 16
    mov qword ptr [rip + tek_stage], 1
    mov qword ptr [rip + tek_signal], 1
    mov edi, 13
    lea rsi, [rip + tek_signal]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    call keeper_helper_entry
    test rax, rax
    jns .Ltek_return
    call tek_target_main
    test rax, rax
    jns .Ltek_return
    cmp qword ptr [rip + g_argc], 5
    jne .Ltek_fail
    mov r12, [rip + g_argv]
    lea rbx, [rip + tek_plan]
    mov rax, [r12 + 8]
    mov [rbx + KE_root], rax
    lea rax, [rip + tek_owner]
    mov [rbx + KE_owner], rax
    lea rax, [rip + tek_name]
    mov [rbx + KE_name], rax
    mov rax, [r12 + 16]
    mov [rbx + KE_payload], rax
    mov rax, [r12 + 24]
    mov [rbx + KE_state], rax
    mov rax, [r12 + 32]
    mov [rbx + KE_home], rax
    lea rdi, [rip + tek_program]
    mov esi, 4096
    call proc_self_path
    test rax, rax
    jle .Ltek_fail
    lea rax, [rip + tek_program]
    mov [rbx + KE_program], rax
    mov [rip + tek_args], rax
    lea rax, [rip + tek_target]
    mov [rip + tek_args + 8], rax
    mov rax, [rbx + KE_state]
    mov [rip + tek_args + 16], rax
    mov rdi, [rbx + KE_home]
    lea rsi, [rip + tek_approved]
    call path_join
    mov [rip + tek_args + 24], rax
    mov dword ptr [rbx + KE_needs], NEEDS_HOME_READ
    mov dword ptr [rbx + KE_fallback], 1
    mov qword ptr [rbx + KE_kind], KA_LEGACY
    call ext_activation_epoch_get
    mov [rbx + KE_context], rax
    mov qword ptr [rip + tek_stage], 10
    mov rdi, [rbx + KE_root]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz .Ltek_fail
    mov r13, rax
    mov qword ptr [rip + tek_stage], 11
    mov rdi, rax
    lea rsi, [rip + tek_owner]
    lea rdx, [rip + tek_name]
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call ext_store_lease_try
    test rax, rax
    js .Ltek_fail
    mov [rbx + KE_lease], rax
    mov [rip + tek_lease], rax
    mov rdi, r13
    call ext_store_guard_free
    test rax, rax
    js .Ltek_fail
    mov qword ptr [rip + tek_stage], 12
    call lc_arguments_prepare
    call lc_ep_create
    call lc_plan_capture
    mov rax, [rip + tek_plan + KE_root]
    mov [rip + g_ext_dir], rax
    call lc_environment
    call lc_arguments_prepare
    mov rdi, [rip + tek_plan + KE_state]
    lea rsi, [rip + lc_marker_name]
    call path_join
    mov [rip + lc_marker], rax
    # Stop during preparation must close the gate before it can become READY.
    mov qword ptr [rip + tek_stage], 20
    call lc_reset
    call lc_start
    lea rdi, [rip + lc_extension]
    lea rsi, [rip + lc_stop_text]
    call ext_stop
    call lc_wait
    call lc_no_marker
    cmp dword ptr [rip + lc_extension + EXT_status], ES_STOPPED
    jne .Ltek_fail
    # Disable between prepare and START is authoritative too.
    mov qword ptr [rip + tek_stage], 21
    call lc_reset
    call lc_start
    mov dword ptr [rip + lc_extension + EXT_disabled], 1
    call lc_wait
    call lc_no_marker
    cmp dword ptr [rip + lc_extension + EXT_status], ES_DISABLED
    jne .Ltek_fail
    # Removal remains final while cleanup is asynchronous.
    mov qword ptr [rip + tek_stage], 22
    call lc_reset
    call lc_start
    lea rdi, [rip + lc_extension]
    call ext_retire
    call lc_wait
    call lc_no_marker
    cmp dword ptr [rip + lc_extension + EXT_status], ES_REMOVED
    jne .Ltek_fail
    # Context change cannot open a previously prepared gate.
    mov qword ptr [rip + tek_stage], 23
    call lc_reset
    call lc_start
    call ext_activation_invalidate
    call lc_wait
    call lc_no_marker
    cmp dword ptr [rip + lc_extension + EXT_activation_stale], 1
    jne .Ltek_fail
    call ext_activation_epoch_get
    mov [rip + tek_plan + KE_context], rax
    call lc_plan_capture
    call lc_accepted_invalidators
    # A full protocol input queue and throttled output cannot stall raw retirement draining.
    mov qword ptr [rip + tek_stage], 24
    call lc_protocol_start
    lea rdi, [rip + lc_extension + EXT_wq]
    mov esi, EXT_WQ_MAX + 1
    call sb_reserve
    mov qword ptr [rip + lc_extension + EXT_wq + SB_len], EXT_WQ_MAX + 1
    mov dword ptr [rip + lc_extension + EXT_throttled], 1
.ifndef WINDOWS
    call lc_suspend
.endif
    call time_ms
    sub rax, 10000
    mov [rip + lc_extension + EXT_started], rax
    lea rdi, [rip + lc_extension]
    lea rsi, [rip + lc_stop_text]
    call ext_kill
.ifndef WINDOWS
    call time_ms
    mov r12, rax
    call ext_timeout
    test rax, rax
    js .Ltek_fail
    cmp rax, 20
    ja .Ltek_fail
    test rax, rax
    jnz 1f
    call time_ms
    sub rax, r12
    cmp rax, 20
    jb .Ltek_fail
1:  call lc_resume
.endif
    call lc_wait
    cmp qword ptr [rip + lc_extension + EXT_wq + SB_len], 0
    jne .Ltek_fail
    cmp qword ptr [rip + lc_extension + EXT_rbuf + SB_len], 0
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_stdout_eof], 1
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_status], ES_STOPPED
    jne .Ltek_fail
    call lc_after_collection
    lea rdi, [rip + tek_ok]
    call log_cstr
    xor eax, eax
.Ltek_return:
    EPILOGUE
.Ltek_fail:
    mov rdi, [rip + tek_stage]
    call sys_exit

lc_environment:
    PROLOGUE
    lea rdi, [rip + tek_home]
    lea rsi, [rip + tek_home_prefix]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + tek_plan + KE_home]
    call cstr_copy
    lea rax, [rip + tek_home]
    mov [rip + tek_env], rax
    mov r12, [rip + g_envp]
    xor r13d, r13d
    lea rdi, [rip + lc_state_env]
    lea rsi, [rip + lc_state_prefix]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + tek_plan + KE_state]
    call cstr_copy
    lea rax, [rip + lc_state_env]
    mov [rip + tek_env + 8], rax
    lea rdi, [rip + lc_approved_env]
    lea rsi, [rip + lc_approved_prefix]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + tek_args + 24]
    call cstr_copy
    lea rax, [rip + lc_approved_env]
    mov [rip + tek_env + 16], rax
    lea rdi, [rip + lc_config_env]
    lea rsi, [rip + lc_config_prefix]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + tek_plan + KE_state]
    call cstr_copy
    lea rax, [rip + lc_config_env]
    mov [rip + tek_env + 24], rax
    mov r14d, 4
1:  mov rdi, [r12 + r13*8]
    test rdi, rdi
    jz 3f
    inc r13
    cmp r13, 1024
    jae .Ltek_fail
    cmp dword ptr [rdi], 0x454d4f48
    jne 11f
    cmp byte ptr [rdi + 4], '='
    je 1b
11: cmp dword ptr [rdi], 0x5f474458
    jne 2f
    call lc_is_config
    test eax, eax
    jnz 1b
2:  lea rax, [rip + tek_env]
    mov [rax + r14*8], rdi
    inc r14
    jmp 1b
3:  lea rax, [rip + tek_env]
    mov qword ptr [rax + r14*8], 0
    mov [rip + g_envp], rax
    EPILOGUE

lc_arguments_prepare:
    lea rdi, [rip + lc_arguments]
    lea rsi, [rip + lc_protocol_target]
    jmp cstr_copy

lc_reset:
    PROLOGUE
    cmp qword ptr [rip + lc_ea], 0
    jne 1f
    call lc_plan_capture
1:  call lc_owner_take
    call lc_metadata_drop
    call lc_retire_pump
    mov rdi, [rip + lc_marker]
    test rdi, rdi
    jz 11f
    SYS SYS_unlink
11: lea rbx, [rip + lc_extension]
    mov r14d, [rbx + EXT_activation_required]
    mov rdi, rbx
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    mov [rbx + EXT_activation_required], r14d
    mov r12, [rip + tek_owned_plan]
    lea rdi, [rip + tek_owner]
    lea rsi, [rip + tek_name]
    mov rdx, [rip + tek_plan + KE_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz .Ltek_fail
    test rdx, rdx
    jnz .Ltek_fail
    mov [rbx + EXT_identity_owner], rax
    mov rcx, [rax + HI_owner]
    mov [rbx + EXT_owner], rcx
    mov rcx, [rax + HI_name]
    mov [rbx + EXT_name], rcx
    mov rcx, [rax + HI_state]
    mov [rbx + EXT_state], rcx
    mov r13, [rip + lc_ep]
    mov rax, [r13 + EP_ext + EXT_title]
    mov [rbx + EXT_title], rax
    mov rax, [r13 + EP_ext + EXT_version]
    mov [rbx + EXT_version], rax
    mov rax, [r13 + EP_ext + EXT_dir]
    mov [rbx + EXT_dir], rax
    mov rax, [r13 + EP_ext + EXT_prog]
    mov [rbx + EXT_prog], rax
    mov eax, [r12 + KE_needs]
    mov [rbx + EXT_needs], eax
    mov rax, [r13 + EP_ext + EXT_args]
    mov [rbx + EXT_args], rax
    mov rax, [r13 + EP_ext + EXT_script]
    mov [rbx + EXT_script], rax
    mov rax, [r13 + EP_ext + EXT_runs]
    mov [rbx + EXT_runs], rax
    mov rdi, r13
    call ext_prepare_retain
    test rax, rax
    jnz .Ltek_fail
    mov [rbx + EXT_metadata_owner], r13
    mov dword ptr [rbx + EXT_manifest_ok], 1
    mov dword ptr [rbx + EXT_catalog_state], 1
    mov qword ptr [rip + g_ext_prepared_catalog_active], 1
    mov dword ptr [rbx + EXT_status], ES_IDLE
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_host_child_in], -1
    mov dword ptr [rbx + EXT_host_child_out], -1
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov qword ptr [rip + g_exts + VEC_cap], 1
    EPILOGUE

lc_start:
    PROLOGUE
    # The old raw entry cannot install a naked plan, even while its source is live.
    lea rdi, [rip + lc_extension]
    mov rsi, [rip + tek_owned_plan]
    call ext_start_plan
    cmp rax, -22
    jne .Ltek_fail
    mov rdi, [rip + lc_ea]
    call ext_activation_owner_retain
    test rax, rax
    jnz .Ltek_fail
    lea rdi, [rip + lc_extension]
    mov rsi, [rip + lc_ea]
    lea rdx, [rip + lc_old_ea]
    call ext_activation_host_swap
    call lc_consumed
    cmp qword ptr [rip + lc_old_ea], 0
    jne .Ltek_fail
    mov rdi, [rip + lc_ea]
    mov qword ptr [rip + lc_ea], 0
    call ext_activation_owner_release
    call lc_consumed
    # Drop the CP analog before preparation and reject same-identity unaccepted arguments.
    mov r12, [rip + lc_extension + EXT_args]
    lea rax, [rip + lc_unaccepted_args]
    mov [rip + lc_extension + EXT_args], rax
    lea rdi, [rip + lc_extension]
    mov rsi, [rip + tek_owned_plan]
    call ext_start_plan
    cmp rax, -22
    jne .Ltek_fail
    cmp qword ptr [rip + lc_extension + EXT_keeper], 0
    jne .Ltek_fail
    mov [rip + lc_extension + EXT_args], r12
    lea rdi, [rip + lc_extension]
    mov rsi, [rip + tek_owned_plan]
    call ext_start_plan
    test rax, rax
    jle .Ltek_fail
    EPILOGUE

lc_wait:
    PROLOGUE
    call time_ms
    lea r12, [rax + 10000]
1:  call ext_tick
    cmp qword ptr [rip + lc_extension + EXT_keeper], 0
    jne 3f
    cmp dword ptr [rip + lc_extension + EXT_retiring], 1
    je 3f
    cmp dword ptr [rip + lc_extension + EXT_retiring], 3
    jne 2f
3:  call time_ms
    cmp rax, r12
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp 1b
2:  EPILOGUE

lc_wait_running:
    PROLOGUE
    call time_ms
    lea r12, [rax + 10000]
1:  call ext_tick
    cmp dword ptr [rip + lc_extension + EXT_startaccepted], 1
    jne 11f
    xor edi, edi
    call loop_poll
11: mov rdi, [rip + lc_marker]
    call file_type
    cmp eax, 0x8000
    jne 12f
    cmp dword ptr [rip + lc_extension + EXT_status], ES_RUNNING
    je 2f
12:
    cmp qword ptr [rip + lc_extension + EXT_keeper], 0
    je .Ltek_fail
    call time_ms
    cmp rax, r12
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp 1b
2:  EPILOGUE

lc_no_marker:
    PROLOGUE
    mov rdi, [rip + lc_marker]
    call file_type
    test eax, eax
    jnz .Ltek_fail
    EPILOGUE

.ifndef WINDOWS
lc_suspend:
    PROLOGUE 16
    mov rdi, [rip + lc_extension + EXT_keeper]
    call kp_find
    test rax, rax
    jz .Ltek_fail
    mov rax, [rax + KX_helper]
    mov [rip + lc_helper], rax
    mov rdi, rax
.ifdef MACOS
    mov esi, 17
.else
    mov esi, 19
.endif
    SYS SYS_kill
    test rax, rax
    js .Ltek_fail
1:  mov rdi, [rip + lc_helper]
    mov rsi, rsp
    mov edx, 2
    xor r10d, r10d
    SYS SYS_wait4
    cmp rax, -EINTR
    je 1b
    cmp rax, [rip + lc_helper]
    jne .Ltek_fail
    EPILOGUE
lc_resume:
    PROLOGUE
    mov rdi, [rip + lc_helper]
.ifdef MACOS
    mov esi, 19
.else
    mov esi, 18
.endif
    SYS SYS_kill
    test rax, rax
    js .Ltek_fail
    EPILOGUE
.endif

tek_target_main:
    PROLOGUE 16
    cmp qword ptr [rip + g_argc], 2
    jne 8f
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    lea rsi, [rip + tek_target]
    call strcmp_eq
    test eax, eax
    jnz 1f
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    lea rsi, [rip + lc_protocol_target]
    call strcmp_eq
    test eax, eax
    jz 8f
    mov qword ptr [rip + lc_protocol_mode], 1
1:  lea rdi, [rip + lc_state_key]
    call getenv
    test rax, rax
    jz 7f
    mov rbx, rax
    lea rdi, [rip + tek_home_key]
    call getenv
    test rax, rax
    jz 7f
    mov rdi, rax
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jz 7f
    lea rdi, [rip + lc_approved_key]
    call getenv
    test rax, rax
    jz 7f
    mov rdi, rax
    mov esi, O_RDONLY | O_NONBLOCK | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 7f
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    mov edx, 16
    SYS SYS_read
    mov r13, rax
    mov rdi, r12
    SYS SYS_close
    cmp r13, 6
    jne 7f
    mov rdi, rsp
    lea rsi, [rip + tek_expected]
    mov edx, 6
    call memeq
    test eax, eax
    jz 7f
    mov rdi, rbx
    lea rsi, [rip + lc_marker_name]
    call path_join
    mov r14, rax
    mov rdi, rax
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js 7f
    mov rdi, rax
    SYS SYS_close
    mov rdi, r14
    call mem_free
    cmp qword ptr [rip + lc_protocol_mode], 0
    je 51f
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne 7f
51: mov edi, 1
    lea rsi, [rip + lc_hello]
    mov edx, 8
    SYS SYS_write
    cmp rax, 8
    jne 7f
6:  mov edi, 1
    lea rsi, [rip + tek_bytes]
    mov edx, 16384
    SYS SYS_write
    test rax, rax
    jg 6b
    mov eax, 91
    EPILOGUE
7:  mov eax, 90
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

.include "../tests/ext_activation_lifecycle_helpers.inc"

.text
# Observe parser-established native RUNNING, then an unrelated pending epoch advance.
lc_running_observe:
    PROLOGUE
    lea rbx, [rip + lc_extension]
    mov r12, [rbx + EXT_activation_owner]
    mov rdi, r12
    call ext_activation_owner_retain
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    mov rsi, [rbx + EXT_activation_owner]
    mov rdx, [rbx + EXT_keeper]
    call ext_activation_host_running_check
    test rax, rax
    jnz .Ltek_fail
    call ext_activation_invalidate
    test rax, rax
    jz .Ltek_fail
    mov rdi, rbx
    mov rsi, [rbx + EXT_activation_owner]
    mov rdx, [rbx + EXT_keeper]
    call ext_activation_host_running_check
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    call ext_activation_host_check
    cmp rax, -116
    jne .Ltek_fail
    mov r13d, 8
1:  call ext_tick
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne .Ltek_fail
    cmp [rbx + EXT_activation_owner], r12
    jne .Ltek_fail
    cmp qword ptr [rbx + EXT_keeper], 0
    je .Ltek_fail
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Ltek_fail
    dec r13d
    jnz 1b
    mov rdi, r12
    call ext_activation_owner_release
    call lc_consumed
    EPILOGUE

.text
# The target creates its marker then waits on its actual inherited stdin before hello.
lc_wait_accepted:
    PROLOGUE
    call time_ms
    lea r12, [rax + 10000]
1:  call ext_tick
    cmp dword ptr [rip + lc_extension + EXT_startaccepted], 1
    jne 3f
    mov rdi, [rip + lc_marker]
    call file_type
    cmp eax, 0x8000
    jne 3f
    cmp dword ptr [rip + lc_extension + EXT_status], ES_STARTING
    jne .Ltek_fail
    EPILOGUE
3:  cmp qword ptr [rip + lc_extension + EXT_keeper], 0
    je .Ltek_fail
    call time_ms
    cmp rax, r12
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp 1b

lc_prehello_observe:
    PROLOGUE
    lea rbx, [rip + lc_extension]
    mov r12, [rbx + EXT_activation_owner]
    mov r13, [rbx + EXT_keeper]
    mov rdi, r12
    call ext_activation_owner_retain
    test rax, rax
    jnz .Ltek_fail
    call ext_activation_invalidate
    mov r14d, 8
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_activation_host_accepted_check
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_activation_host_running_check
    cmp rax, -116
    jne .Ltek_fail
    call ext_tick
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    jne .Ltek_fail
    cmp [rbx + EXT_keeper], r13
    jne .Ltek_fail
    cmp [rbx + EXT_activation_owner], r12
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Ltek_fail
    dec r14d
    jnz 1b
    mov edi, [rbx + EXT_in]
    lea rsi, [rip + lc_barrier]
    mov edx, 1
    SYS SYS_write
    cmp rax, 1
    jne .Ltek_fail
    mov rdi, r12
    call ext_activation_owner_release
    call lc_consumed
    EPILOGUE

lc_protocol_start:
    PROLOGUE
    mov r14, [rip + tek_stage]
    mov qword ptr [rip + tek_stage], 60
    call ext_activation_epoch_get
    mov [rip + tek_plan + KE_context], rax
    call lc_reset
    mov qword ptr [rip + tek_stage], 61
    call lc_start
    mov qword ptr [rip + tek_stage], 62
    call lc_wait_accepted
    mov qword ptr [rip + tek_stage], 63
    call lc_prehello_observe
    mov qword ptr [rip + tek_stage], 64
    call lc_wait_running
    mov qword ptr [rip + tek_stage], 65
    call lc_running_observe
    mov [rip + tek_stage], r14
    EPILOGUE

# Every explicit accepted-session revocation still services its historical lifetime.
lc_accepted_invalidators:
    PROLOGUE
    xor r15d, r15d
1:  lea rax, [r15 + 30]
    mov [rip + tek_stage], rax
    call lc_protocol_start
    lea rbx, [rip + lc_extension]
    test r15, r15
    jnz 2f
    mov dword ptr [rbx + EXT_disabled], 1
    jmp 5f
2:  cmp r15, 1
    jne 3f
    mov rdi, rbx
    call ext_slot_hide_pure
    jmp 5f
3:  cmp r15, 2
    jne 4f
    mov dword ptr [rbx + EXT_activation_stale], 1
    jmp 5f
4:  mov rax, [rip + tek_plan + KE_state]
    mov [rip + g_project], rax
5:  call lc_wait
    cmp qword ptr [rbx + EXT_keeper], 0
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_retiring], 2
    jne .Ltek_fail
    test r15, r15
    jnz 6f
    cmp dword ptr [rbx + EXT_status], ES_DISABLED
    jne .Ltek_fail
6:  mov qword ptr [rip + g_project], 0
    call ext_tick
    inc r15
    cmp r15, 4
    jb 1b
    EPILOGUE
