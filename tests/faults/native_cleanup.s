.ifndef NCF_MODE
.equ NCF_MODE, 0
.endif
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstorejob.inc"
.include "app/extsettingsnative.inc"
.include "app/extstore.inc"
.include "app/extstorejoblegacy.inc"
.bss
.p2align 3
ncf_target: .quad 0
ncf_fault: .quad 0
ncf_calls: .quad 0
ncf_close_calls: .quad 0
ncf_temp_close_calls: .quad 0
.text
ncf_fail:
    mov edi, 73
    call sys_exit
FN ncf_munmap
    cmp rdi, [rip + ncf_target]
    jne 1f
    inc qword ptr [rip + ncf_calls]
    cmp qword ptr [rip + ncf_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN ext_store_job_native_close
    PROLOGUE
    inc qword ptr [rip + ncf_close_calls]
    call ncf_real_close
.if NCF_MODE == 14
    test rax, rax
    jnz 1f
    mov rax, -13
1:
.endif
    EPILOGUE
FN ncf_temp_close
    PROLOGUE 96
    inc qword ptr [rip + ncf_temp_close_calls]
.ifdef WINDOWS
    mov rdi, rcx
.endif
    call ncf_real_close
    test rax, rax
    jnz ncf_fail
.ifdef WINDOWS
    mov ecx, 5
    API SetLastError
    xor eax, eax
.else
    mov rax, -13
.endif
    EPILOGUE
FN ncf_stream
    PROLOGUE 128
.ifdef WINDOWS
    lea rcx, [rsp + 96]
    lea rdx, [rsp + 104]
    xor r8d, r8d
    xor r9d, r9d
    API CreatePipe
    test eax, eax
    jz ncf_fail
    mov rbx, [rsp + 96]
    mov rdi, [rsp + 104]
.else
    mov rdi, rsp
    xor esi, esi
    SYS SYS_pipe2
    test rax, rax
    js ncf_fail
    movsxd rbx, dword ptr [rsp]
    movsxd rdi, dword ptr [rsp + 4]
.endif
    call ncf_real_close
    test rax, rax
    jnz ncf_fail
    mov rax, rbx
    EPILOGUE
FN ncf_allocate
    call mem_alloc_try
    test rax, rax
    jz ncf_fail
    ret
FN ncf_owner_free
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    jmp ext_settings_native_free
.else
.if NCF_MODE == 8 || NCF_MODE == 9
    jmp ext_store_snapshot_free_try
.else
    jmp ext_store_job_free
.endif
.endif
FN main
    PROLOGUE 32
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    xor edi, edi
    call ext_settings_native_free
    test rax, rax
    jnz ncf_fail
    cmp rdx, 1
    jne ncf_fail
    test rcx, rcx
    jnz ncf_fail
.endif
    mov r15, [rip + g_mem_live]
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    mov edi, ECN_SIZE
.else
.if NCF_MODE == 8 || NCF_MODE == 9
    mov edi, ESS_SIZE
.else
    mov edi, ESJ_SIZE
.endif
.endif
    call ncf_allocate
    mov rbx, rax
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    mov qword ptr [rbx + ECN_input], -1
    mov qword ptr [rbx + ECN_event], -1
.endif
.if NCF_MODE != 8 && NCF_MODE != 9
    mov qword ptr [rbx + ESJ_stdout], -1
    mov qword ptr [rbx + ESJ_stderr], -1
    mov qword ptr [rbx + ESJ_launch], -1
    mov qword ptr [rbx + ESJ_anchor], -1
    lea rdi, [rbx + ESJ_native]
    mov esi, 255
    mov edx, 64
    call memset
.endif
.if NCF_MODE == 0
    mov r12, rbx
.else
    mov edi, 131072
    call ncf_allocate
    mov r12, rax
.if NCF_MODE == 1 || NCF_MODE == 14 || NCF_MODE == 16
    mov [rbx + ESJ_work], rax
.else
.if NCF_MODE >= 2 && NCF_MODE <= 4
    mov [rbx + ESJ_native + 96 + (NCF_MODE - 2)*8], rax
.else
.if NCF_MODE == 5 || NCF_MODE == 11
    mov [rbx + ESJ_wire], rax
.else
.if NCF_MODE == 6
    mov [rbx + ESJ_legacy], rax
.else
.if NCF_MODE == 7 || NCF_MODE == 15
    mov qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    mov [rbx + ESJ_result], rax
.else
.if NCF_MODE == 8
    mov [rbx + ESS_entries + VEC_ptr], rax
.else
.if NCF_MODE == 9
    mov [rbx + ESS_owners + VEC_ptr], rax
.else
.if NCF_MODE == 10
    mov edi, ESS_SIZE
    call ncf_allocate
    mov [rbx + ESJ_result], rax
    mov [rax + ESS_entries + VEC_ptr], r12
    mov qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
.endif
.endif
.endif
.endif
.endif
.endif
.endif
.endif
.endif
.if NCF_MODE == 11 || NCF_MODE == 15
    mov edi, ELC_SIZE
    call ncf_allocate
    mov [rbx + ESJ_legacy], rax
    mov qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    lea rcx, [rax + ELC_cwdbuf]
    mov [rax + ELC_cwd], rcx
    mov dword ptr [rcx], 0x00636261
    mov rdi, rbx
    mov rsi, rsp
    call ext_store_job_legacy_context
    test rax, rax
    jnz ncf_fail
.endif
.if NCF_MODE == 14
    call ncf_stream
    mov [rbx + ESJ_stdout], rax
.endif
.if NCF_MODE == 6
    mov qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    lea rcx, [r12 + ELC_cwdbuf]
    mov [r12 + ELC_cwd], rcx
    mov dword ptr [rcx], 0x00636261
    mov rdi, rbx
    mov rsi, rsp
    call ext_store_job_legacy_context
    test rax, rax
    jnz ncf_fail
.endif
.if NCF_MODE == 16
    call ncf_stream
    mov [rbx + ESJ_native], rax
.endif
    lea rcx, [r12 - 16]
    mov [rip + ncf_target], rcx
    mov rax, [rcx]
    mov [rsp + 16], rax
    mov rax, [rcx + 8]
    mov [rsp + 24], rax
    mov r14, [rip + g_mem_live]
    mov qword ptr [rip + ncf_fault], 1
    mov r13d, 1
2:  mov rdi, rbx
    call ncf_owner_free
.if NCF_MODE == 14 || NCF_MODE == 16
    cmp rax, -13
.else
    cmp rax, -5
.endif
    jne ncf_fail
    test rdx, rdx
    jnz ncf_fail
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    cmp rcx, 1
    jne ncf_fail
.endif
    cmp [rip + g_mem_live], r14
    jne ncf_fail
    cmp [rip + ncf_calls], r13
    jne ncf_fail
.if NCF_MODE == 14
    cmp qword ptr [rip + ncf_close_calls], 1
    jne ncf_fail
.endif
.if NCF_MODE == 16
    cmp qword ptr [rip + ncf_temp_close_calls], 1
    jne ncf_fail
.endif
    mov rcx, [rip + ncf_target]
    mov rax, [rsp + 16]
    cmp [rcx], rax
    jne ncf_fail
    mov rax, [rsp + 24]
    cmp [rcx + 8], rax
    jne ncf_fail
.if NCF_MODE == 6 || NCF_MODE == 11 || NCF_MODE == 15
    mov rax, [rsp]
    cmp dword ptr [rax], 0x00636261
    jne ncf_fail
.endif
    inc r13
    cmp r13, 2
    jbe 2b
    mov qword ptr [rip + ncf_fault], 0
    mov rdi, rbx
    call ncf_owner_free
.if NCF_MODE == 8 || NCF_MODE == 9
    test rax, rax
.else
.if NCF_MODE == 14 || NCF_MODE == 16
    cmp rax, -13
.else
    cmp rax, -5
.endif
.endif
    jne ncf_fail
    cmp rdx, 1
    jne ncf_fail
.if NCF_MODE <= 4 || NCF_MODE == 14 || NCF_MODE == 16
    test rcx, rcx
    jnz ncf_fail
.endif
    cmp [rip + g_mem_live], r15
    jne ncf_fail
    xor eax, eax
    EPILOGUE
