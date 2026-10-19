.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstorejob.inc"
.include "app/extsettingsnative.inc"
.section .rodata
ecnt_marker: .asciz "--theme-source-worker"
ecnt_v1: .asciz "v1"
ecnt_nonce: .asciz "0102030405060708090a0b0c0d0e0f10"
.data
ecnt_sigact: .quad 1,0,0,0
.text
ecnt_fail:
    mov edi, 73
    call sys_exit
ecnt_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne ecnt_fail
    EPILOGUE
FN main
    PROLOGUE 512
    mov edi, 13
    lea rsi, [rip + ecnt_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + ecnt_marker]
    call strcmp_eq
    test eax, eax
    jnz ecnt_child
    cmp qword ptr [rip + g_argc], 2
    jne ecnt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call ecnt_number
    mov [rsp + 160], rax
    cmp qword ptr [rsp + 160], 3
    je 90f
    call ext_store_job_legacy_cache_executable
    test rax, rax
    jnz ecnt_fail
90: mov r15, [rip + g_mem_live]
    call ecnt_census
    mov [rsp + 168], rax
    call ecnt_foreign_open
    mov [rsp + 176], rax
    xor ecx, ecx
92: lea eax, [rcx + 1]
    mov [rsp + 16 + rcx], al
    inc ecx
    cmp ecx, 16
    jb 92b
    cmp qword ptr [rsp + 160], 4
    jne 91f
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], 0
91: mov rax, [rsp + 160]
    inc rax
    mov [rsp], rax
    mov rax, [rsp + 176]
    mov [rsp + 8], rax
    mov rdi, rsp
    call theme_capture_native_start
    cmp qword ptr [rsp + 160], 3
    jae ecnt_refused
    test rax, rax
    jz ecnt_fail
    test rdx, rdx
    jnz ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
    mov r12, rax
    mov rdi, r12
    mov esi, 3
    lea rdx, [rsp + 32]
    mov ecx, 1
    call ext_settings_native_read
    cmp rax, -22
    jne ecnt_fail
    mov rdi, r12
    xor esi, esi
    call ext_settings_native_write_poll
    cmp rax, -22
    jne ecnt_fail
    test rdx, rdx
    jnz ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
    mov rdi, r12
    call ext_settings_native_free
    cmp rax, -16
    jne ecnt_fail
    test rdx, rdx
    jnz ecnt_fail
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz ecnt_fail
    mov r13, rax
    mov qword ptr [rsp + 184], 0    # queued chunk count
    mov qword ptr [rsp + 192], 0    # one input chunk pending
    mov qword ptr [rsp + 200], 0    # native progress
    mov qword ptr [rsp + 208], 0    # stdout bytes
    mov qword ptr [rsp + 216], 0    # EOF bits
    mov qword ptr [rsp + 224], 0    # input close requested
    mov qword ptr [rsp + 232], 0    # observed EOF while process alive
    mov qword ptr [rsp + 240], 0    # iterations
    call time_ms
    add rax, 10000
    mov [rsp + 248], rax
.Lecnt_loop:
    inc qword ptr [rsp + 240]
    call time_ms
    cmp rax, [rsp + 248]
    jae ecnt_fail
    cmp qword ptr [rsp + 160], 2
    je .Lecnt_cancel
    cmp qword ptr [rsp + 192], 0
    jne .Lecnt_write
    cmp qword ptr [rsp + 184], 16
    jae .Lecnt_close
    mov rdi, r13
    mov esi, 90
    mov edx, 65536
    call memset
    mov rdi, r12
    mov rsi, r13
    mov edx, 65536
    call ext_settings_native_write_begin
    cmp rax, 1
    jne ecnt_fail
    mov rdi, r12
    mov rsi, r13
    mov edx, 1
    call ext_settings_native_write_begin
    test rax, rax
    jnz ecnt_fail
    mov qword ptr [rsp + 192], 1
    inc qword ptr [rsp + 184]
    mov rdi, r13
    mov esi, 51
    mov edx, 65536
    call memset
.Lecnt_write:
    mov rdi, r12
    mov esi, 32768
    call ext_settings_native_write_poll
    cmp rdx, 32768
    ja ecnt_fail
    cmp rcx, 1
    ja ecnt_fail
    add [rsp + 200], rdx
    test rax, rax
    js ecnt_fail
    jz .Lecnt_read
    mov qword ptr [rsp + 192], 0
    jmp .Lecnt_read
.Lecnt_cancel:
    cmp qword ptr [rsp + 224], 0
    jne .Lecnt_cancel_poll
    cmp qword ptr [rsp + 184], 16
    jae ecnt_fail
    mov rdi, r13
    mov esi, 90
    mov edx, 65536
    call memset
    mov rdi, r12
    mov rsi, r13
    mov edx, 65536
    call ext_settings_native_write_begin
    cmp rax, 1
    jne ecnt_fail
    inc qword ptr [rsp + 184]
    mov rdi, r12
    mov esi, 65536
    call ext_settings_native_write_poll
    test rax, rax
    js ecnt_fail
    jnz .Lecnt_cancel
    mov qword ptr [rsp + 224], 1
    mov rdi, r12
    call ext_settings_native_close_input
    mov rdi, r12
    call ext_settings_native_kill
    test rax, rax
    jnz ecnt_fail
.Lecnt_cancel_poll:
    mov rdi, r12
    mov esi, 17
    call ext_settings_native_write_poll
    cmp rdx, 17
    ja ecnt_fail
    mov rdi, r12
    call ext_settings_native_close_input
    jmp .Lecnt_read
.Lecnt_close:
    cmp qword ptr [rsp + 224], 0
    jne .Lecnt_read
    mov rdi, r12
    call ext_settings_native_close_input
    test rax, rax
    jnz ecnt_fail
    mov qword ptr [rsp + 224], 1
    mov rdi, r12
    mov rsi, r13
    mov edx, 1
    call ext_settings_native_write_begin
    cmp rax, -32
    jne ecnt_fail
.Lecnt_read:
    xor ebx, ebx
1:  bt qword ptr [rsp + 216], rbx
    jc 4f
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rsp + 32]
    mov ecx, 64
    call ext_settings_native_read
    cmp rax, -11
    je 4f
    cmp rax, -4
    je 4f
    test rax, rax
    js ecnt_fail
    jz 3f
    test rbx, rbx
    jnz ecnt_fail
    mov r14, rax
    add rax, [rsp + 208]
    cmp rax, 16
    ja ecnt_fail
    lea rdi, [rsp + 128]
    add rdi, [rsp + 208]
    lea rsi, [rsp + 32]
    mov rdx, r14
    call memcpy
    add [rsp + 208], r14
    jmp 4f
3:  bts qword ptr [rsp + 216], rbx
4:  inc rbx
    cmp rbx, 3
    jb 1b
    mov rdi, r12
    call ext_settings_native_poll
    test rcx, rcx
    jnz ecnt_fail
    cmp rax, ESJ_OWNED
    jne .Lecnt_collected
    cmp qword ptr [rsp + 216], 7
    jne 5f
    mov qword ptr [rsp + 232], 1
5:  call ext_store_job_retire_wait
    jmp .Lecnt_loop
.Lecnt_collected:
    cmp rax, ESJ_REAPED
    jne ecnt_fail
    cmp qword ptr [rsp + 160], 2
    je .Lecnt_finish
    test rdx, rdx
    jnz ecnt_fail
    cmp qword ptr [rsp + 216], 7
    jne .Lecnt_loop
    cmp qword ptr [rsp + 208], 16
    jne ecnt_fail
    cmp qword ptr [rsp + 128], 1048576
    jne ecnt_fail
    cmp qword ptr [rsp + 136], 94371840
    jne ecnt_fail
    cmp qword ptr [rsp + 200], 1048576
    jne ecnt_fail
    cmp qword ptr [rsp + 160], 1
    jne .Lecnt_finish
    cmp qword ptr [rsp + 232], 1
    jne ecnt_fail
.Lecnt_finish:
    mov rdi, r12
    call ext_settings_native_free
    test rdx, rdx
    jz .Lecnt_loop
    test rax, rax
    jnz ecnt_fail
    mov rdi, r13
    call mem_free
    mov rdi, [rsp + 176]
    call ecnt_foreign_close
    cmp [rip + g_mem_live], r15
    jne ecnt_fail
    call ecnt_census
    cmp rax, [rsp + 168]
    jne ecnt_fail
    xor eax, eax
    EPILOGUE

# Exact reexec argv, controlled stdio and no unrelated inherited process/FD identity.
ecnt_child:
    cmp qword ptr [rip + g_argc], 6
    jne ecnt_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    lea rsi, [rip + ecnt_v1]
    call strcmp_eq
    test eax, eax
    jz ecnt_fail
    mov rdi, [rbx + 40]
    lea rsi, [rip + ecnt_nonce]
    call strcmp_eq
    test eax, eax
    jz ecnt_fail
    mov rdi, [rbx + 24]
    call ecnt_number
    mov r12, rax
    mov rdi, [rbx + 32]
    call ecnt_number
    mov rdi, rax
    call ecnt_foreign_check
    cmp r12, 3
    je .Lecnt_child_idle
    xor r13d, r13d
    xor r14d, r14d
1:  xor edi, edi
    lea rsi, [rsp + 32]
    mov edx, 64
    SYS SYS_read
    cmp rax, -4
    je 1b
    test rax, rax
    js ecnt_fail
    jz 3f
    add r13, rax
    xor ecx, ecx
2:  movzx edx, byte ptr [rsp + 32 + rcx]
    add r14, rdx
    inc rcx
    cmp rcx, rax
    jb 2b
    jmp 1b
3:  mov [rsp + 128], r13
    mov [rsp + 136], r14
    mov edi, 1
    lea rsi, [rsp + 128]
    mov edx, 16
    call write_all
    test rax, rax
    jnz ecnt_fail
    cmp r12, 2
    jne 5f
    mov edi, 1
    SYS SYS_close
    mov edi, 2
    SYS SYS_close
    mov r13d, 10
4:  call ext_store_job_retire_wait
    dec r13
    jnz 4b
5:  xor eax, eax
    EPILOGUE
.Lecnt_child_idle:
    call ext_store_job_retire_wait
    jmp .Lecnt_child_idle

ecnt_census:
    PROLOGUE 112
.ifdef WINDOWS
    mov rcx, -1
    lea rdx, [rsp + 96]
    API GetProcessHandleCount
    test eax, eax
    jz ecnt_fail
    mov eax, [rsp + 96]
.else
    xor ebx, ebx
    xor r12d, r12d
1:  mov rdi, rbx
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 2f
    inc r12
2:  inc rbx
    cmp rbx, 256
    jb 1b
    mov rax, r12
.endif
    EPILOGUE

ecnt_foreign_open:
.ifdef WINDOWS
    PROLOGUE 112
    mov rcx, -1
    mov rdx, -1
    mov r8, -1
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 1
    mov qword ptr [rsp + 48], 2
    API DuplicateHandle
    test eax, eax
    jz ecnt_fail
    API GetCurrentProcessId
    shl rax, 32
    or rax, [rsp + 96]
    EPILOGUE
.else
    mov eax, 150
    ret
.endif

ecnt_foreign_close:
.ifdef WINDOWS
    PROLOGUE 96
    mov ecx, edi
    API CloseHandle
    test eax, eax
    jz ecnt_fail
    EPILOGUE
.else
    ret
.endif

ecnt_foreign_check:
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, rdi
    shr rbx, 32
    mov ecx, edi
    API GetProcessId
    cmp eax, ebx
    je ecnt_fail
    EPILOGUE
.else
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    cmp rax, -9
    jne ecnt_fail
    ret
.endif

# Refusal must not leave a process/native capsule or disturb inherited ownership.
ecnt_refused:
    test rax, rax
    jnz ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
    mov rax, -2
    cmp qword ptr [rsp + 160], 3
    je 1f
    mov rax, -22
1:  cmp rdx, rax
    jne ecnt_fail
    mov rdi, [rsp + 176]
    call ecnt_foreign_close
    call ecnt_census
    cmp rax, [rsp + 168]
    jne ecnt_fail
    cmp r15, [rip + g_mem_live]
    jne ecnt_fail
    xor eax, eax
    EPILOGUE
