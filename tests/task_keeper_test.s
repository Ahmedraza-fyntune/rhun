.include "rhun.inc"
.include "app/taskproc.inc"
.section .rodata
.ifdef WINDOWS
tkp_shell: .asciz ""
tkp_nologo: .asciz "-NoLogo"
tkp_noprofile: .asciz "-NoProfile"
tkp_noninteractive: .asciz "-NonInteractive"
tkp_commandarg: .asciz "-Command"
tkp_encodedarg: .asciz "-EncodedCommand"
tkp_drive_env: .asciz "=R:=R:\\keeper-probe"
tkp_wincommand: .asciz "[Console]::Out.Write('keeper'); $x='雪🦊'"
tkp_encoded_expected: .asciz "WwBDAG8AbgBzAG8AbABlAF0AOgA6AE8AdQB0AC4AVwByAGkAdABlACgAJwBrAGUAZQBwAGUAcgAnACkAOwAgACQAeAA9ACcA6pY+2IrdJwA="
.else
.ifdef MACOS
tkp_shell: .asciz "/bin/zsh"
tkp_login: .asciz "-l"
.else
tkp_shell: .asciz "/bin/sh"
.endif
.endif
tkp_c: .asciz "-c"
tkp_command: .asciz "printf keeper"
tkp_cwd: .asciz "/"
tkp_path: .asciz "PATH=/usr/bin:/bin"
tkp_home: .asciz "HOME=/nonexistent"
tkp_expected: .ascii "keeper"
tkp_ok: .asciz "ok independent task keeper\n"
.data
.p2align 3
tkp_env: .quad tkp_path, tkp_home, 0
tkp_argv:
    .quad tkp_shell
.ifdef WINDOWS
    .quad tkp_nologo, tkp_noprofile, tkp_noninteractive, tkp_commandarg, tkp_wincommand, 0
.else
.ifdef MACOS
    .quad tkp_login
.endif
    .quad tkp_c, tkp_command, 0
.endif
tkp_spec: .quad tkp_argv, tkp_env, tkp_cwd, -1, -1, -1, KP_TASK, 0, 0
.bss
.p2align 3
tkp_handle: .quad 0
tkp_deadline: .quad 0
tkp_started: .quad 0
tkp_eof: .quad 0
tkp_used: .quad 0
tkp_stage: .quad 0
tkp_sigact: .zero 32
tkp_flags: .quad 0
tkp_bytes: .zero 65536
tkp_self: .zero 4096
tkp_current_cwd: .zero 4096
.ifdef WINDOWS
tkp_native_env: .zero 8200
.endif
.text
FN main
    PROLOGUE
    mov qword ptr [rip + tkp_sigact], 1
    mov edi, 13
    lea rsi, [rip + tkp_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    call keeper_helper_entry
    test rax, rax
    jns .Ltkp_return
.ifdef WINDOWS
    call tkp_encoded_target
    test rax, rax
    jns .Ltkp_return
    lea rdi, [rip + tkp_self]
    mov esi, 4096
    call proc_self_path
    test rax, rax
    jle .Ltkp_fail
    lea rax, [rip + tkp_self]
    mov [rip + tkp_argv], rax
    lea rdi, [rip + tkp_current_cwd]
    mov esi, 4096
    SYS SYS_getcwd
    test rax, rax
    js .Ltkp_fail
    lea rax, [rip + tkp_current_cwd]
    mov [rip + tkp_spec + KP_cwd], rax
    mov qword ptr [rip + tkp_spec + KP_envp], 0
    lea rdi, [rip + tkp_native_env]
    lea rax, [rip + tkp_drive_env]
    mov [rdi], rax
    mov rsi, [rip + g_envp]
    xor ecx, ecx
1:  cmp ecx, 1023
    jae .Ltkp_fail
    mov rax, [rsi + rcx*8]
    mov [rdi + rcx*8 + 8], rax
    inc rcx
    test rax, rax
    jnz 1b
    mov [rip + g_envp], rdi
.endif
    mov qword ptr [rip + tkp_stage], 1
    lea rdi, [rip + tkp_spec]
    call keeper_prepare
    test rax, rax
    jle .Ltkp_fail
    mov [rip + tkp_handle], rax
    call time_ms
    add rax, 10000
    mov [rip + tkp_deadline], rax
.Ltkp_loop:
    mov rdi, [rip + tkp_handle]
    call keeper_poll
    test rax, rax
    js .Ltkp_fail
    mov [rip + tkp_flags], rax
    test eax, KP_FAILED
    jnz .Ltkp_fail
    cmp qword ptr [rip + tkp_started], 0
    jne 1f
    test eax, KP_READY
    jz 1f
    mov qword ptr [rip + tkp_stage], 2
    mov rdi, [rip + tkp_handle]
    call keeper_start
    test rax, rax
    js .Ltkp_fail
    cmp eax, 1
    jne 1f
    mov qword ptr [rip + tkp_started], 1
1:  mov qword ptr [rip + tkp_stage], 3
    mov rdi, [rip + tkp_handle]
    lea rsi, [rip + tkp_bytes]
    mov rdx, [rip + tkp_used]
    add rsi, rdx
    mov ecx, 65536
    sub rcx, rdx
    mov rdx, rcx
    call keeper_read
    cmp rax, -11
    je 2f
    cmp rax, -4
    je 2f
    test rax, rax
    js .Ltkp_fail
    jz 11f
    add [rip + tkp_used], rax
    jmp 2f
11: mov qword ptr [rip + tkp_eof], 1
2:  test dword ptr [rip + tkp_flags], KP_DONE
    jz 3f
    cmp qword ptr [rip + tkp_eof], 0
    jne .Ltkp_complete
3:  call time_ms
    cmp rax, [rip + tkp_deadline]
    jae .Ltkp_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp .Ltkp_loop
.Ltkp_complete:
    mov qword ptr [rip + tkp_stage], 4
    mov rdi, [rip + tkp_handle]
    call keeper_poll
    test r8d, r8d
    jnz .Ltkp_fail
    test edx, edx
    jnz .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close
    test rax, rax
    jnz .Ltkp_fail
    cmp qword ptr [rip + tkp_used], 6
    jne .Ltkp_fail
    lea rdi, [rip + tkp_bytes]
    lea rsi, [rip + tkp_expected]
    mov edx, 6
    call memeq
    test eax, eax
    jz .Ltkp_fail
.ifdef TEST_KEEPER_FAULT
    call tkp_fault_checks
.endif
    lea rdi, [rip + tkp_ok]
    call log_cstr
    xor eax, eax
.Ltkp_return:
    EPILOGUE
.Ltkp_fail:
    mov rdi, [rip + tkp_stage]
    call sys_exit

.ifdef WINDOWS
# Native target fixture verifies exact EncodedCommand argv, then writes expected bytes.
# Actual PowerShell execution remains a native Windows release gate.
tkp_encoded_target:
    PROLOGUE
    cmp qword ptr [rip + g_argc], 6
    jne 8f
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    lea rsi, [rip + tkp_nologo]
    call strcmp_eq
    test eax, eax
    jz 8f
    mov rdi, [rbx + 16]
    lea rsi, [rip + tkp_noprofile]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [rbx + 24]
    lea rsi, [rip + tkp_noninteractive]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [rbx + 32]
    lea rsi, [rip + tkp_encodedarg]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [rbx + 40]
    lea rsi, [rip + tkp_encoded_expected]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov r12, [rip + g_envp]
6:  mov rdi, [r12]
    test rdi, rdi
    jz 7f
    add r12, 8
    lea rsi, [rip + tkp_drive_env]
    call strcmp_eq
    test eax, eax
    jz 6b
    mov edi, 1
    lea rsi, [rip + tkp_expected]
    mov edx, 6
    SYS SYS_write
    cmp rax, 6
    jne 7f
    xor eax, eax
    EPILOGUE
7:  mov eax, 10
    EPILOGUE
8:  mov rax, -1
    EPILOGUE
.endif

.ifdef TEST_KEEPER_FAULT
.bss
.p2align 3
tkp_reap_interrupted: .quad 0
.text
# Private link fixture: one interrupted native reap must retry and finish the golden lifetime.
FN tkp_fault_wait4
    cmp qword ptr [rip + tkp_reap_interrupted], 0
    jne 1f
    mov qword ptr [rip + tkp_reap_interrupted], 1
    mov rax, -4
    ret
1:  SYS SYS_wait4
    ret

# Private synthetic recovery record isolates cumulative result preservation from OS timing.
tkp_fault_checks:
    PROLOGUE
    lea rbx, [rip + kp_slots]
    mov rdi, rbx
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    lea rdi, [rbx + KX_native]
    call kp_native_init
    mov qword ptr [rbx + KX_native_state], KN_REAPED
    mov qword ptr [rbx + KX_id], 123
    mov qword ptr [rbx + KX_control], -1
    mov qword ptr [rbx + KX_status], -1
    mov qword ptr [rbx + KX_output], -1
    mov qword ptr [rbx + KX_launchfd], -1
    mov qword ptr [rbx + KX_lease], -1
    mov qword ptr [rbx + KX_status_eof], 1
    mov qword ptr [rbx + KX_no_target], 1
    # This synthetic record models a validated child pre-exec failure, not stale READY state.
    mov qword ptr [rbx + KX_preexec_failed], 1
    mov dword ptr [rbx + KX_reaped], 1
    mov dword ptr [rbx + KX_flags], KP_EXIT_KNOWN
    mov dword ptr [rbx + KX_exit], 23
    mov dword ptr [rbx + KX_raw], 0x1700
    mov edi, 123
    call keeper_poll
    test eax, KP_DONE
    jz 9f
    test eax, KP_EXIT_KNOWN
    jz 9f
    cmp edx, 23
    jne 9f
    cmp r9d, 0x1700
    jne 9f
    mov edi, 123
    call keeper_close
    test rax, rax
    jnz 9f
    EPILOGUE
9:  mov edi, 70
    call sys_exit
.endif
