# Prepared setup owns child originals independently of the native keeper.
.include "rhun.inc"
.text
# Refusal changes no field, including the previous cleanup diagnostic.
FN ext_host_prepared_start_admit
    PROLOGUE
    mov rbx, rdi
    test rdi, rdi
    jz .Lhsa_bad
    cmp dword ptr [rdi + EXT_host_child_in], 0
    jns .Lhsa_busy
    cmp dword ptr [rdi + EXT_host_child_out], 0
    jns .Lhsa_busy
    call ext_host_start_admit
    test rax, rax
    jnz 1f
    mov dword ptr [rbx + EXT_host_setup_error], 0
    mov dword ptr [rbx + EXT_host_native_result], 0
1:  EPILOGUE
.Lhsa_bad:
    mov rax, -22
    EPILOGUE
.Lhsa_busy:
    mov rax, -16
    EPILOGUE

# Fixed two checked operations. Negative consumed diagnostics still block START.
FN ext_host_prepared_children_close
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lhsc_bad
    xor r12d, r12d
    mov esi, 3
    call ext_host_close_field
    test rax, rax
    jns 1f
    mov r12, rax
1:  mov rdi, rbx
    mov esi, 4
    call ext_host_close_field
    test r12, r12
    jnz 2f
    test rax, rax
    jns 2f
    mov r12, rax
2:  mov rax, r12
    EPILOGUE
.Lhsc_bad:
    mov rax, -22
    EPILOGUE

# Fixed five checked operations. DX1 means every endpoint owner was consumed.
FN ext_host_prepared_cleanup
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lhsp_bad
    xor r12d, r12d
    xor r13d, r13d
1:  mov rdi, rbx
    mov rsi, r13
    call ext_host_close_field
    test r12, r12
    jnz 2f
    test rax, rax
    jns 2f
    mov r12, rax
2:  inc r13
    cmp r13, 5
    jb 1b
    xor edx, edx
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne 4f
    xor r13d, r13d
3:  lea rax, [rip + host_setup_fields]
    mov rax, [rax + r13*8]
    cmp dword ptr [rbx + rax], 0
    jns 4f
    inc r13
    cmp r13, 5
    jb 3b
    mov edx, 1
4:  mov rax, r12
    EPILOGUE
.Lhsp_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# The common collector cannot finalize while a child close mask is retained.
FN ext_host_prepared_collect
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 1f
    call ext_host_prepared_children_close
    mov rdi, rbx
    call ext_host_keeper_collect
    EPILOGUE
1:  xor eax, eax
    xor edx, edx
    EPILOGUE

# Completed native proof with only endpoint debt cannot create a permanent20ms poll.
# Existing backend-memory retry deadlines and a bounded raw continuation still apply.
FN ext_host_prepared_timeout
    PROLOGUE 64
    mov rbx, rdi
    call ext_host_keeper_timeout
    mov r12, rax
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    je 9f
    mov rdi, [rbx + EXT_keeper]
    test rdi, rdi
    jz 9f
    mov rsi, rsp
    call keeper_cleanup_info
    test rax, rax
    js 9f
    cmp qword ptr [rsp + 56], 1
    jne 9f
    cmp qword ptr [rsp + 48], 0
    jne 9f
    mov rdi, rbx
    call ext_host_retire_due
    mov r12, -1
    test eax, eax
    jz 9f
    mov r12d, 16
9:  mov rax, r12
    EPILOGUE

# Record a real closed-gate setup failure before any deliberate native stop.
FN ext_host_prepared_setup_note
    mov rax, -22
    test rdi, rdi
    jz 9f
    cmp dword ptr [rdi + EXT_activation_required], 1
    jne 9f
    cmp dword ptr [rdi + EXT_startaccepted], 0
    jne 9f
    test rsi, rsi
    jns 9f
    cmp rsi, -4095
    jl 9f
    cmp dword ptr [rdi + EXT_host_setup_error], 0
    jne 1f
    mov [rdi + EXT_host_setup_error], esi
1:  xor eax, eax
9:  ret

# Reporting policy only. The native observation and cleanup remain independent.
FN ext_host_prepared_finish_result
    mov eax, [rdi + EXT_host_native_result]
    test eax, eax
    jns 1f
    cmp eax, -125
    jne 9f
1:  cmp dword ptr [rdi + EXT_startaccepted], 0
    jne 2f
    mov ecx, [rdi + EXT_host_setup_error]
    test ecx, ecx
    jns 2f
    mov eax, ecx
    jmp 9f
2:  test eax, eax
    jnz 9f
    mov ecx, [rdi + EXT_host_cleanup_error]
    test ecx, ecx
    jns 9f
    mov eax, ecx
9:  ret

# Caller has the reviewed resource-free no-KX/no-target setup-failure provenance.
# A positive failed keeper id must never enter this shortcut.
FN ext_host_prepared_abort
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lhpa_bad
    cmp qword ptr [rbx + EXT_keeper], 0
    jne .Lhpa_busy
    cmp dword ptr [rbx + EXT_pid], 0
    jne .Lhpa_busy
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Lhpa_busy
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Lhpa_busy
    call ext_host_prepared_setup_note
    test rax, rax
    jnz .Lhpa_return
    mov dword ptr [rbx + EXT_activation_stale], 1
    mov dword ptr [rbx + EXT_status], ES_FAILED
    mov dword ptr [rbx + EXT_host_native_result], 0
    mov rdi, rbx
    call ext_host_prepared_cleanup
    mov dword ptr [rbx + EXT_retiring], 0
    cmp rdx, 1
    jne 1f
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jns 2f
1:  mov dword ptr [rbx + EXT_retiring], 3
2:  mov rdi, rbx
    call ext_host_prepared_finish_result
    mov [rbx + EXT_finish_code], eax
.Lhpa_return:
    EPILOGUE
.Lhpa_bad:
    mov rax, -22
    EPILOGUE
.Lhpa_busy:
    mov rax, -16
    EPILOGUE
.section .rodata
.p2align 3
host_setup_fields: .quad EXT_in, EXT_out, EXT_log, EXT_host_child_in, EXT_host_child_out
