.include "rhun.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.include "app/extsettingsnative.inc"
.ifndef WINDOWS
.section .rodata
esjp_null: .asciz "/dev/null"
esjp_root: .asciz "/"
esjp_path: .asciz "PATH=/usr/bin:/bin"
esjp_locale: .asciz "LC_ALL=C"
.p2align 3
esjp_env: .quad esjp_path, esjp_locale, 0
.text
esjp_nonblock:
    PROLOGUE
    mov rbx, rdi
    mov esi, 3
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 1f
    mov rdi, rbx
    mov esi, 4
    mov rdx, rax
    or edx, O_NONBLOCK
    SYS SYS_fcntl
1:  EPILOGUE

# Child only. Report descriptor is valid even when an early duplicate fails.
esjp_remap:
    PROLOGUE 64
    mov rbx, rdi
    mov r13d, 5
    mov rax, [rbx + ESJ_native + 96]
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 10f
    mov r13d, 4
    mov rax, [rbx + ESJ_native + 88]
10: mov [rsp + 40], rax
    xor r12d, r12d
1:  mov rdi, [rbx + ESJ_native + 64 + r12*8]
    xor esi, esi
    mov edx, 10
    SYS SYS_fcntl
    test rax, rax
    js 8f
    mov [rsp + r12*8], rax
    inc r12
    cmp r12, r13
    jb 1b
    mov rax, [rsp + r13*8 - 8]
    mov [rsp + 40], rax
    xor r12d, r12d
2:  mov rdi, [rsp + r12*8]
    mov rsi, r12
    SYS SYS_dup2
    test rax, rax
    js 8f
    inc r12
    cmp r12, r13
    jb 2b
    lea rdi, [r13 - 1]
    mov [rsp + 40], rdi
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
    test rax, rax
    js 8f
    mov rdi, r13
    mov rsi, [rbx + ESJ_work]
    call kp_closefrom
8:  mov rdx, [rsp + 40]
    EPILOGUE

FN ext_store_job_native_spawn
    PROLOGUE 16
    mov rbx, rdi
    mov edi, 1048576
    call mem_alloc_try
    test rax, rax
    jz .Lesjp_oom
    mov [rbx + ESJ_work], rax
    xor r12d, r12d
.Lesjp_pipes:
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Lesjp_spawn_error
    movsxd rax, dword ptr [rsp]
    mov [rbx + ESJ_native + r12], rax
    movsxd rax, dword ptr [rsp + 4]
    mov [rbx + ESJ_native + r12 + 8], rax
    mov rdi, [rbx + ESJ_native + r12]
    cmp r12, 48
    jne 11f
    mov rdi, [rbx + ESJ_native + 56]
11: call esjp_nonblock
    test rax, rax
    js .Lesjp_spawn_error
    add r12, 16
    mov eax, 48
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 12f
    mov eax, 64
12: cmp r12, rax
    jb .Lesjp_pipes
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 13f
    mov rax, [rbx + ESJ_native + 48]
    mov [rbx + ESJ_native + 64], rax
    mov rax, [rbx + ESJ_native + 40]
    mov [rbx + ESJ_native + 88], rax
    jmp .Lesjp_stdio
13: lea rdi, [rip + esjp_null]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lesjp_spawn_error
    mov [rbx + ESJ_native + 48], rax
    mov [rbx + ESJ_native + 64], rax
.Lesjp_stdio:
    mov rax, [rbx + ESJ_native + 8]
    mov [rbx + ESJ_native + 72], rax
    mov rax, [rbx + ESJ_native + 24]
    mov [rbx + ESJ_native + 80], rax
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    je 14f
    mov rax, [rbx + ESJ_anchor]
    mov [rbx + ESJ_native + 88], rax
14:
    mov rax, [rbx + ESJ_native + 40]
    mov [rbx + ESJ_native + 96], rax
    mov word ptr [rbx + ESJ_rawtext], 0x0033
    SYS SYS_fork
    test rax, rax
    js .Lesjp_spawn_error
    jz .Lesjp_child
    mov [rbx + ESJ_process], rax
    mov qword ptr [rbx + ESJ_authority], ESJ_OWNED
    mov rax, [rbx + ESJ_native]
    mov [rbx + ESJ_stdout], rax
    mov qword ptr [rbx + ESJ_native], -1
    mov rax, [rbx + ESJ_native + 16]
    mov [rbx + ESJ_stderr], rax
    mov qword ptr [rbx + ESJ_native + 16], -1
    mov rax, [rbx + ESJ_native + 32]
    mov [rbx + ESJ_launch], rax
    mov qword ptr [rbx + ESJ_native + 32], -1
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 15f
    mov rax, [rbx + ESJ_native + 56]
    mov [rbx + ECN_input], rax
    mov qword ptr [rbx + ESJ_native + 56], -1
15:
    mov rdi, rbx
    call ext_store_job_native_free
    EPILOGUE
.Lesjp_child:
    mov rdi, rbx
    call esjp_remap
    test rax, rax
    js .Lesjp_child_error
    SYS SYS_setsid
    test rax, rax
    js .Lesjp_child_error4
    call kp_native_reset_signals
    test rax, rax
    js .Lesjp_child_error4
    mov rax, [rbx + ESJ_purpose]
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    jbe 16f
    lea rdi, [rip + esjp_root]
    SYS SYS_chdir
    test rax, rax
    js .Lesjp_child_error4
    lea rdi, [rbx + ESJ_exe]
    lea rsi, [rbx + ESJ_argv]
    lea rdx, [rip + esjp_env]
    jmp 17f
16: lea rdi, [rbx + ESJ_exe]
    lea rsi, [rbx + ESJ_argv]
    mov rdx, [rbx + ESJ_legacy]
    mov rdx, [rdx + ELC_env]
17: SYS SYS_execve
.Lesjp_child_error4:
    mov edx, 4
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne .Lesjp_child_error
    mov edx, 3
.Lesjp_child_error:
    mov [rsp], eax
    mov r12, rdx
    xor r13d, r13d
1:  mov rdi, r12
    lea rsi, [rsp + r13]
    mov edx, 4
    sub rdx, r13
    SYS SYS_write
    cmp rax, -4
    je 1b
    test rax, rax
    jle 2f
    add r13, rax
    cmp r13, 4
    jb 1b
2:  mov edi, 111
    SYS SYS_exit
.Lesjp_oom:
    mov rax, -12
.Lesjp_spawn_error:
    mov r12, rax
    mov rdi, rbx
    call ext_store_job_native_free
    test rax, rax
    jns 1f
    cmp qword ptr [rbx + ESJ_secondary], 0
    jne 1f
    mov [rbx + ESJ_secondary], rax
1:  mov rax, r12
    EPILOGUE

FN ext_store_job_native_free
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
1:  mov rdi, [rbx + ESJ_native + r12]
    mov qword ptr [rbx + ESJ_native + r12], -1
    test rdi, rdi
    js 3f
    SYS SYS_close
    test rax, rax
    jns 3f
    test r13, r13
    jnz 3f
    mov r13, rax
3:  add r12, 8
    cmp r12, 64
    jb 1b
    mov rdi, [rbx + ESJ_work]
    call prep_cleanup_free
    test rdx, rdx
    jz 4f
    mov qword ptr [rbx + ESJ_work], 0
4:  test rax, rax
    jns 5f
    test r13, r13
    jnz 5f
    mov r13, rax
5:  mov rax, r13
    EPILOGUE

FN ext_store_job_native_close
    SYS SYS_close
    ret
FN ext_store_job_native_read
    SYS SYS_read
    ret
FN ext_store_job_native_kill
    mov rdi, [rdi + ESJ_process]
    mov esi, 9
    SYS SYS_kill
    # ESRCH does not imply collection; retain waitable child authority.
    cmp rax, -3
    jne 1f
    xor eax, eax
1:  ret
FN ext_store_job_native_poll
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne 5f
    mov rdi, [rbx + ESJ_process]
    mov rsi, rsp
    mov edx, 1
    xor r10d, r10d
    SYS SYS_wait4
    cmp rax, -4
    je 5f
    cmp rax, -10
    je 4f
    test rax, rax
    jle 6f
    cmp rax, [rbx + ESJ_process]
    jne 7f
    mov qword ptr [rbx + ESJ_authority], ESJ_REAPED
    mov qword ptr [rbx + ESJ_process], 0
    mov eax, [rsp]
    test eax, 127
    jnz 2f
    shr eax, 8
    and eax, 255
    jmp 3f
2:  and eax, 127
    add eax, 128
3:  mov [rbx + ESJ_exit], rax
5:  xor eax, eax
6:  EPILOGUE
4:  mov qword ptr [rbx + ESJ_authority], ESJ_LOST
    mov qword ptr [rbx + ESJ_process], 0
    mov rax, -10
    EPILOGUE
7:  mov rax, -5
    EPILOGUE

FN ext_store_job_nonce
    PROLOGUE 16
    mov rbx, rdi
    lea rdi, [rip + .Lesjp_random]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 5f
    mov r12, rax
    xor r13d, r13d
1:  mov rdi, r12
    lea rsi, [rsp + r13]
    mov edx, 16
    sub rdx, r13
    SYS SYS_read
    cmp rax, -4
    je 1b
    test rax, rax
    jle 2f
    add r13, rax
    cmp r13, 16
    jb 1b
    xor eax, eax
    jmp 3f
2:  test rax, rax
    js 3f
    mov rax, -5
3:  mov r13, rax
    mov rdi, r12
    SYS SYS_close
    test r13, r13
    jnz 4f
    test rax, rax
    js 5f
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 16
    call memcpy
4:  mov rax, r13
5:  EPILOGUE

FN ext_store_job_retire_wait
.ifdef MACOS
    jmp mac_ext_store_job_retire_wait
.else
    xor edi, edi
    xor esi, esi
    mov edx, 16
    SYS SYS_poll
    ret
.endif
.section .rodata
.Lesjp_random: .asciz "/dev/urandom"
.endif
