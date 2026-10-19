.include "app/extsettingsnative.inc"
.include "app/extchoicesdisk.inc"
.data
ecnf_allocs: .quad 0
ecnf_pipe_calls: .quad 0
ecnf_fired: .quad 0
ecnf_observed: .quad 0
ecnf_collected_busy: .quad 0
ecnf_local_frees: .quad 0
ecnf_write_fired: .quad 0
ecnf_write_size: .quad 0
.text
FN mem_alloc_try
.if ECNF_MODE == 1 || ECNF_MODE == 2 || (ECNF_MODE >= 16 && ECNF_MODE <= 18)
    inc qword ptr [rip + ecnf_allocs]
 .if ECNF_MODE >= 16 && ECNF_MODE <= 18
    cmp qword ptr [rip + ecnf_allocs], ECNF_MODE - 13
.else
    cmp qword ptr [rip + ecnf_allocs], ECNF_MODE
.endif
    jne 1f
    xor eax, eax
    ret
.endif
1:  jmp ecnf_real_alloc
FN ext_settings_native_free
    PROLOGUE 16
    mov rbx, rdi
    mov qword ptr [rsp], 0
    test rbx, rbx
    jz 1f
    cmp qword ptr [rbx + ESJ_authority], ESJ_REAPED
    jne 1f
    cmp qword ptr [rbx + ECN_operation], 0
    je 1f
    inc qword ptr [rip + ecnf_collected_busy]
    mov qword ptr [rsp], 1
1:  call ecnf_real_free
    test rdx, rdx
    jz 2f
    cmp qword ptr [rsp], 1
    je ecnt_fail
2:  EPILOGUE
FN ext_store_job_native_close
    PROLOGUE
    call ecnf_real_close
.if ECNF_MODE == 9
    test rax, rax
    js 1f
    cmp qword ptr [rip + ecnf_fired], 0
    jne 1f
    inc qword ptr [rip + ecnf_fired]
    mov rax, -16
.endif
1:  EPILOGUE

.ifndef WINDOWS
FN ecnf_pipe
.if ECNF_MODE == 3
    mov rax, -24
    ret
.endif
    SYS SYS_pipe2
    ret
FN ecnf_fcntl
.if ECNF_MODE == 4 || ECNF_MODE == 15
    cmp esi, 3
    je 1f
    cmp esi, 4
    jne 2f
1:  mov rax, -5
    ret
2:
.endif
    SYS SYS_fcntl
    ret
FN ecnf_fork
.if ECNF_MODE == 5
    mov rax, -11
    ret
.endif
    SYS SYS_fork
    ret
FN ecnf_parent_close
    SYS SYS_close
.if ECNF_MODE == 6 || ECNF_MODE == 15
    test rax, rax
    js 1f
    cmp qword ptr [rip + ecnf_fired], 0
    jne 1f
    inc qword ptr [rip + ecnf_fired]
 .if ECNF_MODE == 15
    mov rax, -16
.else
    mov rax, -5
.endif
1:
.endif
    ret
FN ecnf_wait
.if ECNF_MODE == 7
    cmp qword ptr [rip + ecnf_observed], 0
    jne 1f
    inc qword ptr [rip + ecnf_observed]
    mov rax, -5
    ret
1:
.endif
    SYS SYS_wait4
.if ECNF_MODE == 14
    test rax, rax
    jle 2f
    mov rax, -10
2:
.endif
    ret
.else
FN ecnf_CreatePipe
.if ECNF_MODE == 15
    inc qword ptr [rip + ecnf_allocs]
    cmp qword ptr [rip + ecnf_allocs], 2
    jne 9f
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
9:
.endif
.if ECNF_MODE == 3 || ECNF_MODE == 4
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_CreatePipe]
FN ecnf_CreateProcessW
.if ECNF_MODE == 11
    jmp ecnt_fail
.endif
.if ECNF_MODE == 5
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_CreateProcessW]
FN ecnf_parent_close
    PROLOGUE 96
    API CloseHandle
.if ECNF_MODE == 6 || ECNF_MODE == 15
    test eax, eax
    jz 1f
    cmp qword ptr [rip + ecnf_fired], 0
    jne 1f
    inc qword ptr [rip + ecnf_fired]
 .if ECNF_MODE == 15
    mov ecx, 6
.else
    mov ecx, 31
.endif
    API SetLastError
    xor eax, eax
1:
.endif
    EPILOGUE
FN ecnf_WaitForSingleObject
.if ECNF_MODE == 7
    cmp qword ptr [rip + ecnf_observed], 0
    jne 1f
    inc qword ptr [rip + ecnf_observed]
    sub rsp, 40
    mov ecx, 6
    API SetLastError
    add rsp, 40
    mov eax, -1
    ret
1:
.endif
    jmp [rip + __imp_WaitForSingleObject]
FN ecnf_GetExitCodeProcess
.if ECNF_MODE == 25
    PROLOGUE 96
    mov rbx, rdx
    API GetExitCodeProcess
    test eax, eax
    jz 1f
    mov dword ptr [rbx], 0xc0000005
1:  EPILOGUE
.endif
.if ECNF_MODE == 8
    cmp qword ptr [rip + ecnf_observed], 0
    jne 1f
    inc qword ptr [rip + ecnf_observed]
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
1:
.endif
    jmp [rip + __imp_GetExitCodeProcess]
FN ecnf_LocalFree
.if ECNF_MODE == 10 || ECNF_MODE == 22 || ECNF_MODE == 23
    inc qword ptr [rip + ecnf_local_frees]
.if ECNF_MODE == 10
    cmp qword ptr [rip + ecnf_local_frees], 4
    ja 1f
.else
.if ECNF_MODE == 22
    cmp qword ptr [rip + ecnf_local_frees], 2
    je 2f
    cmp qword ptr [rip + ecnf_local_frees], 3
    jne 1f
.else
    cmp qword ptr [rip + ecnf_local_frees], 1
    je 2f
    cmp qword ptr [rip + ecnf_local_frees], 3
    jne 1f
.endif
.endif
2:
    PROLOGUE 96
    mov rbx, rcx
    mov ecx, 5
    API SetLastError
    mov rax, rbx
    EPILOGUE
1:
.endif
    jmp [rip + __imp_LocalFree]
FN ecnf_CreateFileW
    cmp edx, 0x80000000
    jne ecnt_fail
    test r8d, r8d
    jnz ecnt_fail
.if ECNF_MODE == 11
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    mov rax, -1
    ret
.endif
    jmp [rip + __imp_CreateFileW]
FN ecnf_WriteFile
    inc qword ptr [rip + ecnf_pipe_calls]
.if ECNF_MODE == 12 || ECNF_MODE == 13 || ECNF_MODE == 24
    mov rax, [rsp + 40]
    mov qword ptr [rax], 259
    mov qword ptr [rax + 8], 0
    mov [rip + ecnf_write_size], r8
    inc qword ptr [rip + ecnf_write_fired]
    sub rsp, 40
    mov ecx, 997
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_WriteFile]
FN ecnf_CancelIoEx
.if ECNF_MODE == 11
    PROLOGUE 96
    API CancelIoEx
    mov ecx, 1168
    API SetLastError
    xor eax, eax
    EPILOGUE
.endif
.if ECNF_MODE == 12 || ECNF_MODE == 24
    sub rsp, 40
    mov ecx, 1168
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_CancelIoEx]
FN ecnf_GetOverlappedResult
    inc qword ptr [rip + ecnf_pipe_calls]
.if ECNF_MODE == 12 || ECNF_MODE == 13 || ECNF_MODE == 24
    cmp qword ptr [rip + ecnf_write_fired], 0
    je 9f
.if ECNF_MODE == 24
    cmp qword ptr [rip + ecnf_observed], 0
    jne 3f
    inc qword ptr [rip + ecnf_observed]
    mov qword ptr [rdx], 0
    mov rax, [rip + ecnf_write_size]
    mov [rdx + 8], rax
    sub rsp, 40
    mov ecx, 6
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
3:
.endif
.if ECNF_MODE == 13 || ECNF_MODE == 24
    mov qword ptr [rdx], 0
    mov rax, [rip + ecnf_write_size]
    mov [rdx + 8], rax
    mov [r8], eax
    mov eax, 1
    ret
.else
    lea rax, [rdx - ECN_overlapped]
    cmp qword ptr [rax + ESJ_authority], ESJ_REAPED
    je 2f
    inc qword ptr [rip + ecnf_observed]
    sub rsp, 40
    mov ecx, 6
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
2:  mov qword ptr [rdx], -1073741536
    mov dword ptr [r8], 0
    sub rsp, 40
    mov ecx, 995
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
9:
.endif
    jmp [rip + __imp_GetOverlappedResult]
FN ecnf_CreateEventW
.if ECNF_MODE == 19
    sub rsp, 40
    mov ecx, 8
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_CreateEventW]
FN ecnf_OpenProcessToken
.if ECNF_MODE == 21
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
    jmp [rip + __imp_OpenProcessToken]
FN ecnf_UpdateProcThreadAttribute
    cmp qword ptr [rsp + 40], 24
    jne ecnt_fail
    jmp [rip + __imp_UpdateProcThreadAttribute]
FN ecnf_CreateNamedPipeW
    cmp edx, 0x40080002
    jne ecnt_fail
    cmp r8d, 8
    jne ecnt_fail
    cmp r9d, 1
    jne ecnt_fail
    mov rax, [rsp + 64]
    test rax, rax
    jz ecnt_fail
    cmp dword ptr [rax], 24
    jne ecnt_fail
    cmp dword ptr [rax + 16], 0
    jne ecnt_fail
    PROLOGUE 512
    mov [rsp + 96], rcx
    mov [rsp + 104], rdx
    mov [rsp + 112], r8
    mov [rsp + 120], r9
    mov [rsp + 128], rdi
    mov [rsp + 136], rsi
    mov rbx, [rax + 8]
    mov rax, [rbp + 48]
    mov [rsp + 400], rax
    mov rax, [rbp + 56]
    mov [rsp + 408], rax
    mov rax, [rbp + 64]
    mov [rsp + 416], rax
    mov rax, [rbp + 72]
    mov [rsp + 424], rax
    mov rcx, rbx
    lea rdx, [rsp + 160]
    lea r8, [rsp + 168]
    API GetSecurityDescriptorControl
    test eax, eax
    jz ecnt_fail
    test word ptr [rsp + 160], 0x1000
    jz ecnt_fail
    mov rcx, rbx
    lea rdx, [rsp + 176]
    lea r8, [rsp + 184]
    lea r9, [rsp + 192]
    API GetSecurityDescriptorDacl
    test eax, eax
    jz ecnt_fail
    cmp dword ptr [rsp + 176], 1
    jne ecnt_fail
    mov r14, [rsp + 184]
    test r14, r14
    jz ecnt_fail
    cmp word ptr [r14 + 4], 3
    jne ecnt_fail
    movzx r15d, word ptr [r14 + 2]
    add r15, r14
    add r14, 8
    mov rax, [rbp - 8]
    mov rcx, [rax + ECN_security + ECP_token]
    mov edx, 1
    lea r8, [rsp + 208]
    mov r9d, 128
    lea rax, [rsp + 344]
    mov [rsp + 32], rax
    API GetTokenInformation
    test eax, eax
    jz ecnt_fail
    xor r13d, r13d
1:  lea r12, [rip + ecnf_system_sid]
    test r13, r13
    jz 2f
    lea r12, [rip + ecnf_admin_sid]
    cmp r13, 1
    je 2f
    mov r12, [rsp + 208]
2:  lea rax, [r14 + 8]
    cmp rax, r15
    ja ecnt_fail
    cmp byte ptr [r14], 0
    jne ecnt_fail
    cmp byte ptr [r14 + 1], 0
    jne ecnt_fail
    cmp dword ptr [r14 + 4], 0x1f01ff
    jne ecnt_fail
    movzx eax, word ptr [r14 + 2]
    add rax, r14
    cmp rax, r15
    ja ecnt_fail
    movzx edx, byte ptr [r12 + 1]
    lea edx, [rdx*4 + 8]
    lea rax, [rdx + 8]
    movzx ecx, word ptr [r14 + 2]
    cmp rcx, rax
    jne ecnt_fail
    lea rdi, [r14 + 8]
    mov rsi, r12
    call memeq
    test eax, eax
    jz ecnt_fail
    movzx eax, word ptr [r14 + 2]
    add r14, rax
    inc r13
    cmp r13, 3
    jb 1b
    cmp r14, r15
    jne ecnt_fail
    mov rax, [rsp + 400]
    mov [rsp + 32], rax
    mov rax, [rsp + 408]
    mov [rsp + 40], rax
    mov rax, [rsp + 416]
    mov [rsp + 48], rax
    mov rax, [rsp + 424]
    mov [rsp + 56], rax
    mov rdi, [rsp + 128]
    mov rsi, [rsp + 136]
.if ECNF_MODE == 20
    mov ecx, 5
    API SetLastError
    mov rax, -1
.else
    mov rcx, [rsp + 96]
    mov rdx, [rsp + 104]
    mov r8, [rsp + 112]
    mov r9, [rsp + 120]
    API CreateNamedPipeW
.endif
    EPILOGUE
.section .rdata,"dr"
ecnf_system_sid: .byte 1,1,0,0,0,0,0,5
    .long 18
ecnf_admin_sid: .byte 1,2,0,0,0,0,0,5
    .long 32,544
.endif

.text
FN ext_settings_native_write_poll
    PROLOGUE 16
    mov [rsp], rsi
    mov qword ptr [rip + ecnf_pipe_calls], 0
    call ecnf_real_write_poll
    cmp rdx, [rsp]
    ja ecnt_fail
    cmp rcx, 1
    ja ecnt_fail
    cmp qword ptr [rip + ecnf_pipe_calls], 1
    ja ecnt_fail
    cmp rax, 1
    jg ecnt_fail
    cmp rax, -4095
    jl ecnt_fail
    EPILOGUE
.ifndef WINDOWS
FN ecnf_write
    inc qword ptr [rip + ecnf_pipe_calls]
    SYS SYS_write
    ret
.endif
