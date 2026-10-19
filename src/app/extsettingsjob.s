# One settings worker owner. All native process fields remain capsule-private.
.include "rhun.inc"
.include "app/extsettingsjob.inc"
.bss
.p2align 3
ecj_active: .quad 0
.text
# Internal fixed ownership check, without walking caller-owned payloads.
ecj_frame_check:
    test rdi, rdi
    jz 2f
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EJF_sealed], 1
    jne 1f
    lea rdi, [rbx + EJF_header]
    mov rsi, rbx
    call ext_settings_wire_check
    test rax, rax
    js 1f
    cmp [rbx + EJF_kind], rdx
    jne 1f
    cmp [rbx + EJF_length], r8
    jne 1f
    cmp [rbx + EJF_round], r9
    jne 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -71
    EPILOGUE
2:  mov rax, -71
    ret

# begin(owned sealed REQUEST)->ECJ/NULL,RDX error. Only nonNULL consumes request.
FN ext_settings_job_begin
    PROLOGUE
    mov r12, rdi
    cmp qword ptr [rip + ecj_active], 0
    jne .Lecjb_busy
    call ecj_frame_check
    test rax, rax
    js .Lecjb_bad
    cmp qword ptr [r12 + EJF_kind], EW_REQUEST
    jne .Lecjb_bad
    mov ebx, [r12 + EJF_body]
    cmp ebx, 1
    jb .Lecjb_bad
    cmp ebx, 3
    ja .Lecjb_bad
    mov eax, [r12 + EJF_body + 4]
    cmp ebx, 2
    je 1f
    test eax, eax
    jnz .Lecjb_bad
    jmp 2f
1:  test eax, eax
    jz .Lecjb_bad
    cmp eax, 128
    ja .Lecjb_bad
2:  cmp dword ptr [r12 + EJF_body + 12], 1
    ja .Lecjb_bad
    cmp qword ptr [r12 + EJF_body + 16], 1
    ja .Lecjb_bad
    cmp dword ptr [r12 + EJF_body + 12], 0
    jne 5f
    mov rax, [r12 + EJF_body + 16]
    or rax, [r12 + EJF_body + 24]
    or rax, [r12 + EJF_body + 32]
    or rax, [r12 + EJF_body + 40]
    or rax, [r12 + EJF_body + 48]
    jnz .Lecjb_bad
5:  mov eax, [r12 + EJF_body + 8]
    test eax, eax
    jz .Lecjb_bad
    cmp eax, 4095
    ja .Lecjb_bad
    add rax, 56
    cmp rax, [r12 + EJF_length]
    ja .Lecjb_bad
    cmp ebx, 2
    je 6f
    cmp rax, [r12 + EJF_length]
    jne .Lecjb_bad
6:  mov edi, ECJ_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lecjb_done
    mov r13, rax
    mov [r13 + ECJ_mode], rbx
    mov [r13 + ECJ_tx], r12
    mov qword ptr [r13 + ECJ_exit], -1
    mov rdi, r13
    mov rsi, r12
    mov edx, 32
    call memcpy
    mov eax, ECJP_READ_SNAPSHOT
    cmp ebx, 1
    je 3f
    mov eax, ECJP_TX_SNAPSHOT
    cmp ebx, 3
    je 3f
    mov eax, ECJP_SAVE_SNAPSHOT
    mov qword ptr [r13 + ECJ_round], 1
3:  mov [r13 + ECJ_phase], rax
    call time_ms
    add rax, 10000
    mov [r13 + ECJ_deadline], rax
    mov [rip + ecj_active], r13
    mov edi, ESM_NATIVE_RESERVE
    call ext_settings_memory_reserve
    test rax, rax
    js .Lecjb_local_failure
    mov qword ptr [r13 + ECJ_reservation], ESM_NATIVE_RESERVE
    mov rdi, r13
    call ext_settings_native_start
    mov [r13 + ECJ_native], rax
    mov [r13 + ECJ_start_error], rdx
    mov [r13 + ECJ_secondary], rcx
    test rcx, rcx
    jns 7f
    mov [r13 + ECJ_cleanup], rcx
7:  test rax, rax
    jz .Lecjb_start_null
    test rdx, rdx
    js .Lecjb_owned_failure
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lecjb_start_null:
    mov rbx, rdx
    mov edi, ESM_NATIVE_RESERVE
    call ext_settings_memory_release
    mov qword ptr [r13 + ECJ_reservation], 0
    mov rax, rbx
    test rax, rax
    js .Lecjb_local_failure
    mov rax, -5
.Lecjb_local_failure:
    mov [r13 + ECJ_error], rax
    mov qword ptr [r13 + ECJ_closing], 1
    mov qword ptr [r13 + ECJ_phase], ECJP_FAILED
    mov rax, r13
    mov rdx, [r13 + ECJ_error]
    EPILOGUE
.Lecjb_owned_failure:
    mov [r13 + ECJ_error], rdx
    mov qword ptr [r13 + ECJ_closing], 1
    mov qword ptr [r13 + ECJ_phase], ECJP_FAILED
    mov rax, r13
    EPILOGUE
.Lecjb_bad:
    xor eax, eax
    mov rdx, -71
.Lecjb_done:
    EPILOGUE
.Lecjb_busy:
    xor eax, eax
    mov rdx, -16
    EPILOGUE

# command(job,owned sealed frame)->0/-errno; refusal leaves input ownership unchanged.
FN ext_settings_job_command
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .Lecjc_bad
    cmp qword ptr [r12 + ECJ_hold], 0
    jne .Lecjc_held
    cmp qword ptr [r12 + ECJ_closing], 0
    jne .Lecjc_pipe
    cmp qword ptr [r12 + ECJ_error], 0
    jne .Lecjc_pipe
    cmp qword ptr [r12 + ECJ_observation], 0
    jne .Lecjc_pipe
    cmp qword ptr [r12 + ECJ_native], 0
    je .Lecjc_pipe
    cmp qword ptr [r12 + ECJ_tx], 0
    jne .Lecjc_busy
    cmp qword ptr [r12 + ECJ_delivery], 0
    jne .Lecjc_busy
    cmp qword ptr [r12 + ECJ_rx], 0
    jne .Lecjc_busy
    cmp qword ptr [r12 + ECJ_rx_offset], 0
    jne .Lecjc_busy
    mov rdi, r13
    call ecj_frame_check
    test rax, rax
    js .Lecjc_bad
    mov rdi, r12
    mov rsi, r13
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lecjc_bad
    mov rbx, [r13 + EJF_kind]
    mov r14, [r13 + EJF_round]
    cmp rbx, EW_DELTA
    je .Lecjc_delta
    cmp r14, [r12 + ECJ_round]
    jne .Lecjc_bad
    cmp rbx, EW_RELEASE
    je .Lecjc_release
    cmp qword ptr [r12 + ECJ_phase], ECJP_PREPARED
    jne .Lecjc_bad
    cmp rbx, EW_ABORT
    je .Lecjc_abort
    cmp rbx, EW_COMMIT
    jne .Lecjc_bad
    mov eax, ECJP_COMMIT
    jmp .Lecjc_accept
.Lecjc_abort:
    mov eax, ECJP_ABORT
    jmp .Lecjc_accept
.Lecjc_release:
    cmp qword ptr [r12 + ECJ_phase], ECJP_IDLE
    je 1f
    cmp qword ptr [r12 + ECJ_phase], ECJP_PREPARED
    jne .Lecjc_bad
1:  mov eax, ECJP_RELEASE
    jmp .Lecjc_accept
.Lecjc_delta:
    cmp qword ptr [r12 + ECJ_mode], 1
    je .Lecjc_bad
    cmp qword ptr [r12 + ECJ_phase], ECJP_IDLE
    jne .Lecjc_bad
    mov rax, [r12 + ECJ_round]
    inc rax
    cmp rax, 3
    ja .Lecjc_bad
    cmp r14, rax
    jne .Lecjc_bad
    cmp dword ptr [r13 + EJF_body + 4], 0
    jne .Lecjc_bad
    mov eax, [r13 + EJF_body]
    test eax, eax
    jz .Lecjc_bad
    cmp eax, 128
    ja .Lecjc_bad
    mov [r12 + ECJ_round], r14
    mov qword ptr [r12 + ECJ_state], ECJS_PENDING
    mov eax, ECJP_PREPARATION
.Lecjc_accept:
    mov [r12 + ECJ_phase], rax
    mov [r12 + ECJ_tx], r13
    mov qword ptr [r12 + ECJ_tx_offset], 0
    mov qword ptr [r12 + ECJ_tx_pending], 0
    call time_ms
    add rax, 10000
    mov [r12 + ECJ_deadline], rax
    xor eax, eax
    EPILOGUE
.Lecjc_bad:
    mov rax, -71
    EPILOGUE
.Lecjc_busy:
    mov rax, -11
    EPILOGUE
.Lecjc_held:
    mov rax, -16
    EPILOGUE
.Lecjc_pipe:
    mov rax, -32
    EPILOGUE

FN ext_settings_job_take_frame
    test rdi, rdi
    jz 1f
    mov rax, [rdi + ECJ_delivery]
    mov qword ptr [rdi + ECJ_delivery], 0
    ret
1:  xor eax, eax
    ret

FN ext_settings_job_cancel
    test rdi, rdi
    jz 1f
    mov qword ptr [rdi + ECJ_closing], 1
    cmp qword ptr [rdi + ECJ_error], 0
    jne 1f
    mov qword ptr [rdi + ECJ_error], -125
1:  xor eax, eax
    ret

# The bounded step owns all disposal. Free never hides process or frame cleanup.
# Checked free -> AX status, DX cleanup, CX consumed on EVERY return.
# Busy retains the exact job and all native/frame/reservation ownership.
FN ext_settings_job_free
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + ECJ_hold], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_phase], ECJP_TERMINAL
    jne 1f
    cmp qword ptr [rdi + ECJ_native], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_tx], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_rx], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_delivery], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_reservation], 0
    jne 1f
    jmp ext_settings_memory_free
1:  mov rax, -16
    xor edx, edx
    xor ecx, ecx
    ret
2:  xor eax, eax
    xor edx, edx
    mov ecx, 1
    ret

# Coordinator pins config-guard control ownership before issuing native index publication.
FN ext_settings_job_hold
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + ECJ_mode], 3
    jne 2f
    cmp qword ptr [rdi + ECJ_hold], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_phase], ECJP_IDLE
    jne 2f
    cmp qword ptr [rdi + ECJ_closing], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_error], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_observation], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_cleanup], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_result_seen], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_native], 0
    je 2f
    cmp qword ptr [rdi + ECJ_authority], 1
    jne 2f
    cmp qword ptr [rdi + ECJ_tx], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_tx_pending], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_delivery], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_rx], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_rx_offset], 0
    jne 2f
    mov rax, [rdi + ECJ_round]
    imul rax, rax, ECJ_ROW
    test qword ptr [rdi + rax + ECJ_ledger + ECJR_flags], ECJR_SNAPSHOT | ECJR_COMMITTED | ECJR_DISCARDED
    jz 2f
    mov qword ptr [rdi + ECJ_hold], 1
    xor eax, eax
    ret
2:  mov rax, -16
    ret

# Caller proves index native terminality and reconciliation before releasing this pin.
FN ext_settings_job_release_hold
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + ECJ_hold], 1
    jne 2f
    mov qword ptr [rdi + ECJ_hold], 0
    cmp qword ptr [rdi + ECJ_native], 0
    jne 1f
    cmp [rip + ecj_active], rdi
    jne 1f
    mov qword ptr [rip + ecj_active], 0
1:  xor eax, eax
    ret
2:  mov rax, -22
    ret

# Native free has proved consumed1. No frame or process ownership is inferred from errno.
FN ecj_native_consumed
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + ECJ_native], 0
    mov rdi, [rbx + ECJ_reservation]
    test rdi, rdi
    jz 1f
    mov qword ptr [rbx + ECJ_reservation], 0
    call ext_settings_memory_release
1:  cmp qword ptr [rbx + ECJ_hold], 0
    jne 2f
    cmp [rip + ecj_active], rbx
    jne 2f
    mov qword ptr [rip + ecj_active], 0
2:  xor eax, eax
    EPILOGUE

# Suggested UI timer cadence, never a blocking wait. Transfer states need a prompt
# wake independently of the kernel's optional pipe-buffer size hint.
FN ext_settings_job_timeout
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + ECJ_phase], ECJP_TERMINAL
    je 3f
    cmp qword ptr [rdi + ECJ_cleanup_only], 0
    jne .Lecjt_cleanup_due
    cmp qword ptr [rdi + ECJ_hold], 0
    jne 2f
    cmp qword ptr [rdi + ECJ_phase], ECJP_IDLE
    jne 1f
    cmp qword ptr [rdi + ECJ_closing], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_tx], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_rx], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_delivery], 0
    jne 1f
    cmp qword ptr [rdi + ECJ_rx_offset], 0
    jne 1f
2:  mov eax, 16
    ret
1:  mov eax, 1
    ret
3:  mov rax, -1
    ret
.Lecjt_cleanup_due:
    PROLOGUE
    mov rbx, rdi
    call time_ms
    mov rdx, [rbx + ECJ_retry_due]
    sub rdx, rax
    jbe 1f
    mov eax, 1000
    cmp rdx, rax
    cmovb rax, rdx
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
FN ext_settings_jobs_timeout
    mov rdi, [rip + ecj_active]
    jmp ext_settings_job_timeout
