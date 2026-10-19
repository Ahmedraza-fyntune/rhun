.include "rhun.inc"
.include "app/extsettingsjob.inc"
.section .rodata
ecrf_tag: .quad 17,29,0,0
ecrf_ok: .ascii "ok terminal cleanup retry ownership and cadence\n"
.bss
.p2align 3
ecrf_case: .quad 0
ecrf_alive: .quad 0
ecrf_claimed: .quad 0
ecrf_frees: .quad 0
ecrf_now: .quad 0
ecrf_job: .quad 0
ecrf_charge: .quad 0
ecrf_cap: .quad 0
ecrf_status: .zero 64
.text
ecrf_fail:
    mov edi, 79
    call sys_exit
FN ecrf_time
    mov rax, [rip + ecrf_now]
    ret
ecrf_guard:
    cmp qword ptr [rip + ecrf_alive], 1
    jne ecrf_fail
    cmp qword ptr [rip + ecrf_claimed], 0
    jne ecrf_fail
    ret
FN ecrf_start
    mov qword ptr [rip + ecrf_alive], 1
    mov qword ptr [rip + ecrf_claimed], 0
    mov qword ptr [rip + ecrf_frees], 0
    lea rax, [rip + ecrf_cap]
    mov rdx, -5
    mov rcx, -12
    ret
FN ecrf_poll
    call ecrf_guard
    xor eax, eax
    mov rdx, -1
    xor ecx, ecx
    ret
FN ecrf_read
    call ecrf_guard
    mov rax, -11
    ret
FN ecrf_write_begin
    jmp ecrf_fail
FN ecrf_write_poll
    call ecrf_guard
    mov eax, 1
    xor edx, edx
    xor ecx, ecx
    ret
FN ecrf_close_input
    call ecrf_guard
    xor eax, eax
    ret
FN ecrf_kill
    jmp ecrf_fail
FN ecrf_free
    cmp qword ptr [rip + ecrf_alive], 1
    jne ecrf_fail
    mov qword ptr [rip + ecrf_claimed], 1
    inc qword ptr [rip + ecrf_frees]
    cmp qword ptr [rip + ecrf_frees], 11
    je 2f
    mov rax, -22
    xor edx, edx
    mov ecx, 1
    # Defensive proof: a terminal-only classification may not resume stale IO.
    cmp qword ptr [rip + ecrf_case], 2
    jne 1f
    cmp qword ptr [rip + ecrf_frees], 4
    jne 1f
    xor ecx, ecx
1:  ret
2:  mov qword ptr [rip + ecrf_alive], 0
    mov rax, -9
    mov edx, 1
    xor ecx, ecx
    ret
ecrf_request:
    PROLOGUE
    lea rdi, [rip + ecrf_tag]
    mov esi, EW_REQUEST
    mov edx, 57
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz ecrf_fail
    mov rbx, rax
    mov dword ptr [rax + EJF_body], 3
    mov dword ptr [rax + EJF_body + 8], 1
    mov byte ptr [rax + EJF_body + 56], '/'
    mov rdi, rax
    call ext_settings_frame_seal
    test rax, rax
    jnz ecrf_fail
    mov rax, rbx
    EPILOGUE
ecrf_step:
    mov rdi, [rip + ecrf_job]
    mov rsi, [rip + ecrf_now]
    mov edx, 97
    mov ecx, 8
    jmp ext_settings_job_step
# Repeated unrelated wakes must make exactly zero capsule calls before due.
ecrf_early:
    PROLOGUE
    mov rbx, [rip + ecrf_frees]
    mov r12d, 3
1:  call ecrf_step
    test rax, rax
    jnz ecrf_fail
    or rdx, rcx
    jnz ecrf_fail
    cmp [rip + ecrf_frees], rbx
    jne ecrf_fail
    cmp qword ptr [rip + ecrf_alive], 1
    jne ecrf_fail
    call ext_settings_memory_total
    cmp [rip + ecrf_charge], rax
    jne ecrf_fail
    dec r12
    jnz 1b
    EPILOGUE
FN main
    PROLOGUE 32
    mov r15, [rip + g_mem_live]
    mov r14d, 1
.Lecrf_case:
    mov [rip + ecrf_case], r14
    mov qword ptr [rip + ecrf_now], 1000
    call ecrf_request
    mov rdi, rax
    call ext_settings_job_begin
    test rax, rax
    jz ecrf_fail
    cmp rdx, -5
    jne ecrf_fail
    mov r12, rax
    mov [rip + ecrf_job], rax
    mov ebx, 8
1:  call ecrf_step
    test rax, rax
    jnz ecrf_fail
    cmp qword ptr [r12 + ECJ_cleanup_only], 1
    je 2f
    dec rbx
    jz ecrf_fail
    jmp 1b
2:  cmp qword ptr [rip + ecrf_frees], 1
    jne ecrf_fail
    cmp qword ptr [r12 + ECJ_reservation], ESM_NATIVE_RESERVE
    jne ecrf_fail
    call ext_settings_memory_total
    mov [rip + ecrf_charge], rax
    cmp rax, ESM_NATIVE_RESERVE
    jb ecrf_fail
    # A still-owned cleanup-only capsule keeps the singleton occupied.
    call ecrf_request
    mov rbx, rax
    mov rdi, rax
    call ext_settings_job_begin
    test rax, rax
    jnz ecrf_fail
    cmp rdx, -16
    jne ecrf_fail
    mov rdi, rbx
    call ext_settings_frame_free
    test rax, rax
    jnz ecrf_fail
    mov r13d, 16
.Lecrf_retry:
    call ext_settings_jobs_timeout
    cmp rax, r13
    jne ecrf_fail
    call ecrf_early
    lea rax, [r13 - 1]
    add [rip + ecrf_now], rax
    call ext_settings_jobs_timeout
    cmp rax, 1
    jne ecrf_fail
    call ecrf_early
    mov rax, [rip + ecrf_frees]
    mov [rsp], rax
    inc qword ptr [rip + ecrf_now]
    call ecrf_step
    test rdx, rdx
    jnz ecrf_fail
    cmp rcx, 1
    jne ecrf_fail
    mov rdx, [rsp]
    inc rdx
    cmp [rip + ecrf_frees], rdx
    jne ecrf_fail
    cmp rax, 1
    je .Lecrf_terminal
    test rax, rax
    jnz ecrf_fail
    cmp qword ptr [r12 + ECJ_cleanup_only], 1
    jne ecrf_fail
    cmp qword ptr [r12 + ECJ_reservation], ESM_NATIVE_RESERVE
    jne ecrf_fail
    add r13, r13
    cmp r13, 1000
    jbe .Lecrf_retry
    mov r13d, 1000
    jmp .Lecrf_retry
.Lecrf_terminal:
    cmp qword ptr [rip + ecrf_frees], 11
    jne ecrf_fail
    cmp qword ptr [rip + ecrf_alive], 0
    jne ecrf_fail
    cmp qword ptr [r12 + ECJ_native], 0
    jne ecrf_fail
    cmp qword ptr [r12 + ECJ_reservation], 0
    jne ecrf_fail
    call ext_settings_jobs_timeout
    cmp rax, -1
    jne ecrf_fail
    mov rdi, r12
    lea rsi, [rip + ecrf_status]
    call ext_settings_job_status
    cmp qword ptr [rip + ecrf_status], ECJS_PRECOMMIT_FAILED
    jne ecrf_fail
    cmp qword ptr [rip + ecrf_status + 8], -5
    jne ecrf_fail
    cmp qword ptr [rip + ecrf_status + 16], -12
    jne ecrf_fail
    mov rdi, r12
    call ext_settings_job_free
    test rax, rax
    jnz ecrf_fail
    call ext_settings_memory_total
    test rax, rax
    jnz ecrf_fail
    cmp [rip + g_mem_live], r15
    jne ecrf_fail
    inc r14
    cmp r14, 2
    jbe .Lecrf_case
    mov edi, 1
    lea rsi, [rip + ecrf_ok]
    mov edx, 48
    call write_all
    xor eax, eax
    EPILOGUE
