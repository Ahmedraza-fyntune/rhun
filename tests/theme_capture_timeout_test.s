.include "rhun.inc"
.include "app/themecapturejob.inc"
.bss
.p2align 3
tctt_job: .zero TCJ_SIZE
.text
tctt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE
    xor edi, edi
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, -1
    jne tctt_fail
    lea rbx, [rip + tctt_job]
    mov rdi, rbx
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, 1
    jne tctt_fail
    mov qword ptr [rbx + TCJ_state], TCJS_CLOSING
    mov qword ptr [rbx + TCJ_cleanup_only], 1
    mov qword ptr [rbx + TCJ_retry_due], 1032
    mov rdi, rbx
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, 32
    jne tctt_fail
    mov rdi, rbx
    mov esi, 1032
    call theme_capture_job_timeout
    test rax, rax
    jnz tctt_fail
    mov rdi, rbx
    mov esi, 2000
    call theme_capture_job_timeout
    test rax, rax
    jnz tctt_fail
    mov qword ptr [rbx + TCJ_state], TCJS_READY
    mov rdi, rbx
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, -1
    jne tctt_fail
    mov qword ptr [rbx + TCJ_state], TCJS_TAKEN
    mov rdi, rbx
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, -1
    jne tctt_fail
    mov rdi, rbx
    mov rsi, -1
    call theme_capture_job_timeout
    cmp rax, -22
    jne tctt_fail
    mov qword ptr [rbx + TCJ_state], 6
    mov rdi, rbx
    mov esi, 1000
    call theme_capture_job_timeout
    cmp rax, -22
    jne tctt_fail
    xor eax, eax
    EPILOGUE
