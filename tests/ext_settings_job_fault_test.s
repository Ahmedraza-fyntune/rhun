.include "rhun.inc"
.include "app/extsettingsjob.inc"
.bss
ecnf_case: .quad 0
ecnf_alive: .quad 0
ecnf_polls: .quad 0
ecnf_progress: .quad 0
ecnf_frees: .quad 0
ecnf_cap: .zero 8
.section .rodata
ecnf_tag: .quad 17,29,0,0
ecnf_ok: .ascii "ok settings owned start failures and pending cleanup\n"
.text
ecnf_fail:
    mov edi, 75
    call sys_exit
FN ecnf_start
    cmp qword ptr [rip + ecnf_case], 3
    je 1f
    cmp qword ptr [rip + ecnf_case], 4
    je ecnf_fail
    mov qword ptr [rip + ecnf_alive], 1
    mov qword ptr [rip + ecnf_polls], 0
    mov qword ptr [rip + ecnf_progress], 0
    mov qword ptr [rip + ecnf_frees], 0
    lea rax, [rip + ecnf_cap]
    mov rdx, -5
    mov rcx, -12
    ret
1:  mov qword ptr [rip + ecnf_alive], 0
    xor eax, eax
    mov rdx, -5
    mov rcx, -12
    ret
FN ecnf_poll
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    inc qword ptr [rip + ecnf_polls]
    xor eax, eax
    mov rdx, -1
    xor ecx, ecx
    cmp qword ptr [rip + ecnf_case], 1
    je 2f
    mov eax, 1
    cmp qword ptr [rip + ecnf_polls], 3
    jb 2f
    mov eax, 2
    mov edx, 111
2:  ret
FN ecnf_read
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    cmp qword ptr [rip + ecnf_case], 2
    jne 1f
    cmp qword ptr [rip + ecnf_polls], 3
    jb 1f
    xor eax, eax
    ret
1:  mov rax, -11
    ret
FN ecnf_write_begin
    jmp ecnf_fail
FN ecnf_write_poll
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    inc qword ptr [rip + ecnf_progress]
    xor edx, edx
    xor ecx, ecx
    cmp qword ptr [rip + ecnf_progress], 1
    je 1f
    xor eax, eax
    cmp qword ptr [rip + ecnf_progress], 3
    jb 2f
    mov eax, 1
2:  ret
1:  mov rax, -5                 # Observation error, actual native operation still pending.
    ret
FN ecnf_close_input
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    cmp qword ptr [rip + ecnf_progress], 2
    jae 1f
    mov rax, -115
    ret
1:  xor eax, eax
    ret
FN ecnf_kill
    cmp qword ptr [rip + ecnf_case], 2
    jne ecnf_fail
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    xor eax, eax
    ret
FN ecnf_free
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    inc qword ptr [rip + ecnf_frees]
    cmp qword ptr [rip + ecnf_case], 2
    jne 1f
    cmp qword ptr [rip + ecnf_polls], 3
    jb ecnf_fail                 # No collection, so parent must not attempt disposal.
1:  cmp qword ptr [rip + ecnf_progress], 3
    jb 2f
    mov qword ptr [rip + ecnf_alive], 0
    mov rax, -9                  # Cleanup errno and consumed1 are independent facts.
    mov edx, 1
    xor ecx, ecx                 # Consumed, no further native progress.
    ret
2:  mov rax, -16
    xor edx, edx
    xor ecx, ecx                 # Actual pending operation/debt still needs progress.
    ret
FN main
    PROLOGUE 64
    mov r15, [rip + g_mem_live]
    mov r14d, 1
.Lecnf_case:
    mov [rip + ecnf_case], r14
    lea rdi, [rip + ecnf_tag]
    mov esi, EW_REQUEST
    mov edx, 57
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz ecnf_fail
    mov rbx, rax
    mov dword ptr [rbx + EJF_body], 3
    mov dword ptr [rbx + EJF_body + 8], 1
    mov byte ptr [rbx + EJF_body + 56], '/'
    mov rdi, rbx
    call ext_settings_frame_seal
    test rax, rax
    jnz ecnf_fail
    cmp r14, 4
    jne 7f
    mov edi, ESM_CAP - 1048576
    call ext_settings_memory_reserve
    test rax, rax
    jnz ecnf_fail
7:  mov rdi, rbx
    call ext_settings_job_begin
    test rax, rax
    jz ecnf_fail
    cmp r14, 4
    je 7f
    cmp rdx, -5
    jne ecnf_fail
    jmp 8f
7:  cmp rdx, -12
    jne ecnf_fail
8:  mov r12, rax
    call ext_settings_jobs_timeout
    cmp rax, 1
    jne ecnf_fail
    xor r13d, r13d
.Lecnf_step:
    inc r13
    cmp r13, 32
    ja ecnf_fail
    mov rdi, r12
    mov rsi, r13
    mov edx, 97
    mov ecx, 8
    call ext_settings_job_step
    cmp rdx, 97
    ja ecnf_fail
    cmp rcx, 8
    ja ecnf_fail
    cmp rax, 1
    je .Lecnf_terminal
    test rax, rax
    jnz ecnf_fail
    cmp qword ptr [rip + ecnf_alive], 1
    jne ecnf_fail
    call ext_settings_memory_total
    cmp rax, ESM_NATIVE_RESERVE
    jb ecnf_fail
    jmp .Lecnf_step
.Lecnf_terminal:
    call ext_settings_jobs_timeout
    cmp rax, -1
    jne ecnf_fail
    cmp r14, 3
    jae 7f
    cmp qword ptr [rip + ecnf_alive], 0
    jne ecnf_fail
    cmp qword ptr [rip + ecnf_progress], 3
    jb ecnf_fail
7:  mov rdi, r12
    mov rsi, rsp
    call ext_settings_job_status
    cmp qword ptr [rsp], ECJS_PRECOMMIT_FAILED
    jne ecnf_fail
    cmp r14, 4
    je 7f
    cmp qword ptr [rsp + 8], -5
    jne ecnf_fail
    cmp qword ptr [rsp + 16], -12
    jne ecnf_fail
    jmp 8f
7:  cmp qword ptr [rsp + 8], -12
    jne ecnf_fail
    cmp qword ptr [rsp + 16], 0
    jne ecnf_fail
    mov edi, ESM_CAP - 1048576
    call ext_settings_memory_release
    test rax, rax
    jnz ecnf_fail
8:
    mov rdi, r12
    call ext_settings_job_free
    test rax, rax
    jnz ecnf_fail
    call ext_settings_memory_total
    test rax, rax
    jnz ecnf_fail
    cmp [rip + g_mem_live], r15
    jne ecnf_fail
    inc r14
    cmp r14, 4
    jbe .Lecnf_case
    mov edi, 1
    lea rsi, [rip + ecnf_ok]
    mov edx, 53
    call write_all
    xor eax, eax
    EPILOGUE
