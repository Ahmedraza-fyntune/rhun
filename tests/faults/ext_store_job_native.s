.include "app/extstorejob.inc"
.data
esjf_fired: .quad 0
esjf_readfd: .quad -1
esjf_readbytes: .quad 0
esjf_step_reads: .quad 0
esjf_step_bytes: .quad 0
.text
FN esjf_step_reset
    mov qword ptr [rip + esjf_step_reads], 0
    mov qword ptr [rip + esjf_step_bytes], 0
    ret
FN esjf_cancel
    xor eax, eax
    cmp qword ptr [rip + esjf_fired], 0
    je 1f
    mov rax, -125
1:  ret
FN ext_store_job_native_read
.if ESJF_MODE == 0 || ESJF_MODE == 14
    inc qword ptr [rip + esjf_step_reads]
    cmp qword ptr [rip + esjf_step_reads], 8
    ja 91f
    cmp rdx, 17
    ja 91f
.if ESJF_MODE == 14
    mov rax, -11
    ret
.endif
    PROLOGUE
    call esjf_real_read
    test rax, rax
    jle 92f
    add [rip + esjf_step_bytes], rax
    cmp qword ptr [rip + esjf_step_bytes], 17
    jbe 92f
    mov rax, -33
92: EPILOGUE
91: mov rax, -33
    ret
.endif
.if ESJF_MODE == 12
    cmp qword ptr [rip + esjf_fired], 0
    jne 91f
    PROLOGUE
    call esjf_real_read
    mov qword ptr [rip + esjf_fired], 1
    EPILOGUE
91: mov rax, -33
    ret
.endif
.if ESJF_MODE == 1
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -4
    ret
.endif
.if ESJF_MODE == 2
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -11
    ret
.endif
.if ESJF_MODE == 3
    cmp qword ptr [rip + esjf_readfd], -1
    jne 2f
    mov [rip + esjf_readfd], rdi
2:  cmp [rip + esjf_readfd], rdi
    jne 1f
    cmp qword ptr [rip + esjf_readbytes], 17
    jb 3f
    mov rax, -5
    ret
3:  PROLOGUE
    call esjf_real_read
    test rax, rax
    jle 4f
    add [rip + esjf_readbytes], rax
4:  EPILOGUE
.endif
1:  jmp esjf_real_read

.ifndef WINDOWS
FN esjf_wait
.if ESJF_MODE == 4
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -5
    ret
.endif
.if ESJF_MODE == 5
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -4
    ret
.endif
1:  SYS SYS_wait4
.if ESJF_MODE == 6
    test rax, rax
    jle 2f
    mov rax, -10
2:
.endif
    ret
FN esjf_fcntl
.if ESJF_MODE == 8
    mov rax, -24
    ret
.else
    SYS SYS_fcntl
    ret
.endif
FN esjf_exec
.if ESJF_MODE == 10
    PROLOGUE 16
    mov dword ptr [rsp], -2
    mov edi, 4
    mov rsi, rsp
    mov edx, 2
    SYS SYS_write
    mov edi, 111
    SYS SYS_exit
.else
    SYS SYS_execve
    ret
.endif
.else
FN esjf_wait_win
.if ESJF_MODE == 4
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    sub rsp, 40
    mov ecx, 12345
    call [rip + __imp_SetLastError]
    add rsp, 40
    mov rax, -1
    ret
.endif
.if ESJF_MODE == 5
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov eax, 258
    ret
.endif
1:  jmp [rip + __imp_WaitForSingleObject]
.endif

FN esjf_close
    PROLOGUE
    call ext_root_close
    test rax, rax
    js 1f
.if ESJF_MODE == 7
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -16
.endif
1:  EPILOGUE

FN esjf_alloc
    xor eax, eax
    ret

# A consumed destructor error must clear capacity so another owned job can launch.
esjf_restart:
    PROLOGUE
    call ext_store_job_start
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    call ext_store_job_cancel
1:  call time_ms
    mov rsi, rax
    mov rdi, rbx
    mov edx, 65536
    call ext_store_job_step
    test rax, rax
    jnz 2f
    call ext_store_job_retire_wait
    jmp 1b
2:  mov rdi, rbx
    call ext_store_job_free
    cmp rdx, 1
    jne 9f
    test rax, rax
    jnz 9f
    xor eax, eax
    EPILOGUE
9:  mov rax, -5
    EPILOGUE

.if ESJF_MODE == 13
FN ext_store_job_native_spawn
    mov qword ptr [rdi + ESJ_secondary], -5
    mov rax, -24
    ret
.endif

FN esjf_parent_close
.ifdef WINDOWS
    PROLOGUE 96
    mov rdi, rcx
    call ext_store_job_native_close
    test rax, rax
    js 2f
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    mov ecx, 12345
    call [rip + __imp_SetLastError]
    xor eax, eax
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
2:  xor eax, eax
    EPILOGUE
.else
    PROLOGUE
    call ext_store_job_native_close
    test rax, rax
    js 2f
    cmp qword ptr [rip + esjf_fired], 0
    jne 2f
    mov qword ptr [rip + esjf_fired], 1
    mov rax, -5
2:  EPILOGUE
.endif
.ifdef WINDOWS
FN esjf_exitcode_win
    cmp qword ptr [rip + esjf_fired], 0
    jne 1f
    mov qword ptr [rip + esjf_fired], 1
    sub rsp, 40
    mov ecx, 12345
    call [rip + __imp_SetLastError]
    add rsp, 40
    xor eax, eax
    ret
1:  jmp [rip + __imp_GetExitCodeProcess]
.endif
