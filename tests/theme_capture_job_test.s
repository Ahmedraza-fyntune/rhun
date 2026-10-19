# Real private helper job, bounded parent model and owned result. No editor initialization.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturejob.inc"
.section .rodata
tcjt_marker: .asciz "--theme-source-worker"
.bss
.p2align 3
tcjt_request: .zero TC_INPUT_CAP + 1
.text
tcjt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 96
    cmp qword ptr [rip + g_argc], 2
    jb .Ltcjt_parent
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + tcjt_marker]
    call strcmp_eq
    test eax, eax
    jz .Ltcjt_parent
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call theme_capture_worker_main
    EPILOGUE
.Ltcjt_parent:
    mov qword ptr [rsp], 65536
    cmp qword ptr [rip + g_argc], 1
    je 1f
    cmp qword ptr [rip + g_argc], 2
    jne tcjt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call parse_u64
    cmp rdx, rsi
    jne tcjt_fail
    test rax, rax
    jz tcjt_fail
    cmp rax, 65536
    ja tcjt_fail
    mov [rsp], rax
1:  call ext_store_job_legacy_cache_executable
    test rax, rax
    jnz tcjt_fail
    mov r15, [rip + g_mem_live]
    xor r13d, r13d
2:  xor edi, edi
    lea rsi, [rip + tcjt_request]
    add rsi, r13
    mov edx, TC_INPUT_CAP + 1
    sub rdx, r13
    SYS SYS_read
    cmp rax, -EINTR
    je 2b
    test rax, rax
    js tcjt_fail
    jz 3f
    add r13, rax
    cmp r13, TC_INPUT_CAP
    jbe 2b
    jmp tcjt_fail
3:  lea rdi, [rip + tcjt_request]
    mov rsi, r13
    call tc_request_validate
    test rax, rax
    jnz tcjt_fail
    mov edi, TCQ_SIZE
    call tc_alloc_try
    test rax, rax
    jz tcjt_fail
    mov r14, rax
    mov qword ptr [r14 + TCQ_state], TCQ_SEALED
    mov [r14 + TCQ_length], r13
    lea rdi, [r13 + 1]
    call tc_alloc_try
    test rax, rax
    jz tcjt_fail
    mov [r14 + TCQ_wire], rax
    mov rdi, rax
    lea rsi, [rip + tcjt_request]
    mov rdx, r13
    call memcpy
    call time_ms
    lea rcx, [rax + 20000]
    mov [rsp + 8], rcx
    mov rsi, rax
    mov rdi, r14
    mov edx, 2
    call theme_capture_job_start
    test rax, rax
    jz tcjt_fail
    mov r12, rax
    # No forward result may be taken before actual completion.
    mov rdi, r12
    mov esi, 2
    call theme_capture_job_take
    test rax, rax
    jnz tcjt_fail
.Ltcjt_loop:
    call time_ms
    cmp rax, [rsp + 8]
    jae tcjt_fail
    mov rsi, rax
    mov rdi, r12
    mov rdx, [rsp]
    mov ecx, 2
    call theme_capture_job_step
    test rax, rax
    js tcjt_fail
    jz .Ltcjt_terminal
    call tc_helper_wait
    jmp .Ltcjt_loop
.Ltcjt_terminal:
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    or rdx, rcx
    jnz .Ltcjt_error_free
    mov rdi, r12
    mov esi, 2
    call theme_capture_job_take
    test rax, rax
    jz tcjt_fail
    or rdx, rcx
    jnz tcjt_fail
    mov r13, rax
    mov edi, 1
    mov rsi, [r13 + TCS_wire]
    mov rdx, [r13 + TCS_length]
    call write_all
    test rax, rax
    jnz tcjt_fail
.Ltcjt_job_free:
    mov rdi, r12
    call theme_capture_job_free
    test rax, rax
    jnz tcjt_fail
    test rdx, rdx
    jz .Ltcjt_job_free
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne tcjt_fail
    cmp qword ptr [rip + g_theme_capture_results], 1
    jne tcjt_fail
.Ltcjt_result_free:
    mov rdi, r13
    call theme_capture_result_release
    test rax, rax
    jnz tcjt_fail
    test rdx, rdx
    jz .Ltcjt_result_free
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcjt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcjt_fail
    cmp r15, [rip + g_mem_live]
    jne tcjt_fail
    xor eax, eax
    EPILOGUE
.Ltcjt_error_free:
    mov rdi, r12
    call theme_capture_job_free
    test rdx, rdx
    jz .Ltcjt_error_free
    jmp tcjt_fail
