.include "rhun.inc"
.include "app/taskproc.inc"
.include "app/taskauth.inc"
.section .rodata
tek_target: .asciz "--extension-target"
tek_home_key: .asciz "HOME"
tek_home_prefix: .asciz "HOME="
tek_owner: .asciz "owner"
tek_name: .asciz "name"
tek_approved: .asciz "approved"
tek_expected: .ascii "keeper"
tek_ok: .asciz "ok independent extension keeper\n"
.bss
.p2align 4
tek_plan: .zero KE_SIZE
tek_spec: .zero KP_SIZE
tek_args: .zero 40
tek_home: .zero 4101
tek_program: .zero 4096
tek_env: .zero 8216
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
    mov rdi, rbx
    call keeper_extension_plan_try
    test rax, rax
    jz .Ltek_fail
    mov rbx, rax
    mov [rip + tek_owned_plan], rax
    mov rdi, rax
    call keeper_extension_auth
    test rax, rax
    jz .Ltek_fail
    mov [rip + tek_auth], rax
    lea r12, [rip + tek_spec]
    mov [r12 + KP_auth], rax
    mov [r12 + KP_auth_len], rdx
    lea rax, [rip + tek_args]
    mov [r12 + KP_argv], rax
    # Preserve inherited platform environment while replacing HOME with extension state.
    lea rdi, [rip + tek_home]
    lea rsi, [rip + tek_home_prefix]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + KE_state]
    call cstr_copy
    lea rax, [rip + tek_home]
    mov [rip + tek_env], rax
    mov r13, [rip + g_envp]
    xor r14d, r14d
    mov r15d, 1
1:  mov rdi, [r13 + r14*8]
    test rdi, rdi
    jz 3f
    inc r14
    cmp r14, 1024
    jae .Ltek_fail
    cmp dword ptr [rdi], 0x454d4f48
    jne 2f
    cmp byte ptr [rdi + 4], '='
    je 1b
2:  lea rax, [rip + tek_env]
    mov [rax + r15*8], rdi
    inc r15
    jmp 1b
3:  lea rax, [rip + tek_env]
    mov qword ptr [rax + r15*8], 0
    mov [r12 + KP_envp], rax
    mov rax, [rbx + KE_payload]
    mov [r12 + KP_cwd], rax
    mov qword ptr [r12 + KP_stdin], -1
    mov qword ptr [r12 + KP_stdout], -1
    mov qword ptr [r12 + KP_stderr], -1
    mov qword ptr [r12 + KP_mode], KP_EXTENSION
    mov rax, [rip + tek_lease]
    mov [r12 + KP_parentlease], rax
    mov qword ptr [rip + tek_stage], 13
    mov rdi, r12
    call keeper_prepare
    test rax, rax
    jle .Ltek_fail
    mov [rip + tek_handle], rax
    # The service duplicate must survive original metadata-owner lease closure.
    mov rdi, [rip + tek_lease]
    call ext_root_close
    test rax, rax
    js .Ltek_fail
    mov rdi, [rip + tek_auth]
    call mem_free
    mov rdi, [rip + tek_owned_plan]
    call keeper_extension_plan_free
    mov qword ptr [rip + tek_stage], 2
    call time_ms
    add rax, 10000
    mov [rip + tek_deadline], rax
.Ltek_loop:
    mov rdi, [rip + tek_handle]
    call keeper_poll
    test rax, rax
    js .Ltek_fail
    mov [rip + tek_flags], rax
    test eax, KP_FAILED
    jnz .Ltek_fail
    cmp qword ptr [rip + tek_started], 0
    jne 4f
    test eax, KP_READY
    jz 4f
    mov rdi, [rip + tek_handle]
    xor esi, esi
    call ext_activation_epoch_get
    mov rdx, rax
    mov rdi, [rip + tek_handle]
    call keeper_start_selected
    test rax, rax
    js .Ltek_fail
    cmp eax, 1
    jne 4f
    mov qword ptr [rip + tek_started], 1
4:  mov rdi, [rip + tek_handle]
    lea rsi, [rip + tek_bytes]
    mov rdx, [rip + tek_used]
    add rsi, rdx
    mov eax, 65536
    sub rax, rdx
    mov rdx, rax
    call keeper_read
    cmp rax, -11
    je 5f
    cmp rax, -4
    je 5f
    test rax, rax
    js .Ltek_fail
    jz 41f
    add [rip + tek_used], rax
    jmp 5f
41: mov qword ptr [rip + tek_eof], 1
5:  test dword ptr [rip + tek_flags], KP_DONE
    jz 6f
    cmp qword ptr [rip + tek_eof], 0
    jne .Ltek_complete
6:  call time_ms
    cmp rax, [rip + tek_deadline]
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp .Ltek_loop
.Ltek_complete:
    mov qword ptr [rip + tek_stage], 3
    mov rdi, [rip + tek_handle]
    call keeper_poll
    test edx, edx
    jnz .Ltek_fail
    test r8d, r8d
    jnz .Ltek_fail
    mov rdi, [rip + tek_handle]
    lea rsi, [rip + tek_info]
    call keeper_info
    test rax, rax
    jnz .Ltek_fail
    cmp qword ptr [rip + tek_info + 16], 1
    jne .Ltek_fail
    mov rdi, [rip + tek_handle]
    call keeper_close
    test rax, rax
    jnz .Ltek_fail
    cmp qword ptr [rip + tek_used], 6
    jne .Ltek_fail
    lea rdi, [rip + tek_bytes]
    lea rsi, [rip + tek_expected]
    mov edx, 6
    call memeq
    test eax, eax
    jz .Ltek_fail
    lea rdi, [rip + tek_ok]
    call log_cstr
    xor eax, eax
.Ltek_return:
    EPILOGUE
.Ltek_fail:
    mov rdi, [rip + tek_stage]
    call sys_exit

tek_target_main:
    PROLOGUE 16
    cmp qword ptr [rip + g_argc], 4
    jne 8f
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    lea rsi, [rip + tek_target]
    call strcmp_eq
    test eax, eax
    jz 8f
    lea rdi, [rip + tek_home_key]
    call getenv
    test rax, rax
    jz 7f
    mov rdi, rax
    mov rsi, [rbx + 16]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [rbx + 24]
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
    mov edi, 1
    lea rsi, [rip + tek_expected]
    mov edx, 6
    SYS SYS_write
    cmp rax, 6
    jne 7f
    xor eax, eax
    EPILOGUE
7:  mov eax, 90
    EPILOGUE
8:  mov rax, -1
    EPILOGUE
