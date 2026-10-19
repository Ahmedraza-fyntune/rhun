.include "gpc-cases.inc"
.bss
.p2align 3
gpc_ctx: .skip GPC_SIZE
gpc_req: .skip 48
gpc_info: .skip 80
gpc_diag: .skip 64
.globl gpc_byte_actual, gpc_unit_actual, gpc_fold_actual, gpc_active, gpc_forbidden_actual
gpc_active: .quad 0
gpc_forbidden_actual: .quad 0
gpc_byte_actual: .quad 0
gpc_unit_actual: .quad 0
gpc_fold_actual: .quad 0
gpc_fold_total: .quad 0
gpc_saved_result: .quad 0
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne .Lgr_fail
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    movzx r13d, byte ptr [rax]
    sub r13d, '0'
    cmp r13d, 3
    ja .Lgr_fail
    cmp r13d, 3
    jne 9f
    call gpc_api
    EPILOGUE
9:
    mov eax, 1
    test r13d, r13d
    jz 1f
    mov eax, 4096
    cmp r13d, 1
    je 1f
    mov eax, 65536
1:  mov r13, rax
    xor r12d, r12d
.Lgr_case:
    cmp r12, GPC_CASE_COUNT
    jae .Lgr_done
    imul r14, r12, 104
    lea rax, [rip + gpc_cases]
    add r14, rax
    cmp r13, 1
    jne 1f
    cmp qword ptr [r14 + 8], 65536
    ja .Lgr_skip
1:  mov rax, [r14]
    mov [rip + gpc_req], rax
    mov rax, [r14 + 8]
    mov [rip + gpc_req + 8], rax
    mov rax, [r14 + 16]
    mov [rip + gpc_req + 16], rax
    mov rax, [r14 + 24]
    mov [rip + gpc_req + 24], rax
    mov rax, [r14 + 32]
    mov [rip + gpc_req + 32], rax
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    # A live borrow cannot be replaced and refusal leaves the working state live.
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    cmp rax, -16
    jne .Lgr_fail
    mov qword ptr [rip + gpc_info], 0x12345678
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_info]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_info], 0x12345678
    jne .Lgr_fail
    mov r15d, 100000000
.Lgr_step:
    lea rdi, [rip + gpc_ctx]
    mov rsi, r13
    mov qword ptr [rip + gpc_byte_actual], 0
    mov qword ptr [rip + gpc_unit_actual], 0
    mov qword ptr [rip + gpc_fold_actual], 0
    mov qword ptr [rip + gpc_active], 1
    lea r10, [rip + pg_validate_step]
    call gpc_checked
    mov qword ptr [rip + gpc_active], 0
    cmp qword ptr [rip + gpc_forbidden_actual], 0
    jne .Lgr_fail
    cmp rdx, [rip + gpc_byte_actual]
    jne .Lgr_fail
    cmp rcx, [rip + gpc_unit_actual]
    jne .Lgr_fail
    cmp rcx, [rip + gpc_fold_actual]
    jb .Lgr_fail
    cmp qword ptr [rip + gpc_fold_actual], 9
    ja .Lgr_fail
    mov r8, [rip + gpc_fold_actual]
    add [rip + gpc_fold_total], r8
    cmp rdx, r13
    ja .Lgr_fail
    cmp rcx, 16
    ja .Lgr_fail
    test rax, rax
    js .Lgr_rejected
    jz .Lgr_ready
    dec r15
    jnz .Lgr_step
    jmp .Lgr_fail
.Lgr_rejected:
    cmp rax, [r14 + 96]
    jne .Lgr_fail
    jmp .Lgr_terminal
.Lgr_ready:
    cmp qword ptr [r14 + 96], 0
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_info]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    lea rbx, [rip + gpc_info]
    mov rax, [r14 + 16]
    cmp [rbx], rax
    jne .Lgr_fail
    mov rax, [r14 + 24]
    cmp [rbx + 8], rax
    jne .Lgr_fail
    mov rax, [r14 + 8]
    cmp [rbx + 16], rax
    jne .Lgr_fail
    xor ecx, ecx
1:  mov rax, [r14 + rcx*8 + 40]
    cmp [rbx + rcx*8 + 24], rax
    jne .Lgr_fail
    inc rcx
    cmp rcx, 7
    jb 1b
.Lgr_terminal:
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_diag]
    lea r10, [rip + pg_validate_status]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    mov rax, [r14 + 96]
    test rax, rax
    jz 2f
    cmp [rip + gpc_diag + 8], rax
    jne .Lgr_fail
2:  lea rdi, [rip + gpc_ctx]
    lea r10, [rip + pg_validate_cancel]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_info]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
.Lgr_skip:
    inc r12
    jmp .Lgr_case
.Lgr_done:
    cmp qword ptr [rip + gpc_fold_total], 0
    je .Lgr_fail
    xor eax, eax
    EPILOGUE
.Lgr_fail:
    mov [rip + gpc_diag], r12
    mov [rip + gpc_diag + 8], r13
    mov rax, [rip + gpc_ctx + GPC_error]
    mov [rip + gpc_diag + 16], rax
    mov rax, [rip + gpc_ctx + GPC_phase]
    mov [rip + gpc_diag + 24], rax
    mov rax, [rip + gpc_ctx + GPC_bytes]
    mov [rip + gpc_diag + 32], rax
    mov rax, [rip + gpc_ctx + GPC_units]
    mov [rip + gpc_diag + 40], rax
    mov edi, 2
    lea rsi, [rip + gpc_diag]
    mov edx, 48
    call write_all
    mov eax, 73
    EPILOGUE

FN gpc_checked
    PROLOGUE 32
    mov ebx, 0x31415926
    mov r12d, 0x27182818
    mov r13d, 0x16180339
    mov r14d, 0x14142135
    mov r15d, 0x17320508
    call r10
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    cmp rbx, 0x31415926
    jne .Lgr_fail
    cmp r12, 0x27182818
    jne .Lgr_fail
    cmp r13, 0x16180339
    jne .Lgr_fail
    cmp r14, 0x14142135
    jne .Lgr_fail
    cmp r15, 0x17320508
    jne .Lgr_fail
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE

# Fresh/terminal refusal and cancellation never inspect the wire or touch output.
FN gpc_api
    PROLOGUE
    mov qword ptr [rip + gpc_info], 0x12345678
    mov qword ptr [rip + gpc_info + 72], 0x76543210
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_info]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_status]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_info], 0x12345678
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_info + 72], 0x76543210
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea r10, [rip + pg_validate_cancel]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    lea r14, [rip + gpc_cases]
    mov rax, [r14]
    mov [rip + gpc_req], rax
    mov rax, [r14 + 8]
    mov [rip + gpc_req + 8], rax
    mov rax, [r14 + 16]
    mov [rip + gpc_req + 16], rax
    mov rax, [r14 + 24]
    mov [rip + gpc_req + 24], rax
    mov rax, [r14 + 32]
    mov [rip + gpc_req + 32], rax
    # A wrapped address+length is an API refusal before reading a single byte.
    mov qword ptr [rip + gpc_req], -128
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_ctx + GPC_state], GPC_NEW
    jne .Lgr_fail
    mov rax, [r14]
    mov [rip + gpc_req], rax
    mov qword ptr [rip + gpc_req + 40], 1
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    mov qword ptr [rip + gpc_req + 40], 0
    mov qword ptr [rip + gpc_req + 8], GPC_MAX + 1
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    cmp rax, -EV_RESOURCE
    jne .Lgr_fail
    mov rax, [r14 + 8]
    mov [rip + gpc_req + 8], rax
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    xor r12d, r12d
.Lgc_bad_budget:
    lea rdi, [rip + gpc_ctx]
    mov rsi, r12
    lea r10, [rip + pg_validate_step]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    or rdx, rcx
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_ctx + GPC_state], GPC_WORK
    jne .Lgr_fail
    cmp r12, 65537
    je 1f
    mov r12d, 65537
    jmp .Lgc_bad_budget
1:  lea rdi, [rip + gpc_ctx]
    lea r10, [rip + pg_validate_cancel]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    mov esi, 1
    lea r10, [rip + pg_validate_step]
    call gpc_checked
    cmp rax, -125
    jne .Lgr_fail
    or rdx, rcx
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_info]
    lea r10, [rip + pg_validate_info]
    call gpc_checked
    cmp rax, -22
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_info], 0x12345678
    jne .Lgr_fail
    cmp qword ptr [rip + gpc_info + 72], 0x76543210
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea rsi, [rip + gpc_req]
    lea r10, [rip + pg_validate_begin]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    mov esi, 1
    lea r10, [rip + pg_validate_step]
    call gpc_checked
    cmp rax, 1
    jne .Lgr_fail
    cmp rdx, 1
    jne .Lgr_fail
    lea rdi, [rip + gpc_ctx]
    lea r10, [rip + pg_validate_cancel]
    call gpc_checked
    test rax, rax
    jne .Lgr_fail
    # Exhaust the accepted Unicode scalar domain against the actual fixed table.
    xor r12d, r12d
.Lgc_fold_bound:
    mov qword ptr [rip + gpc_fold_actual], 0
    mov rdi, r12
    call case_fold
    cmp qword ptr [rip + gpc_fold_actual], 9
    ja .Lgr_fail
    inc r12
    cmp r12, 0x110000
    jb .Lgc_fold_bound
    xor eax, eax
    EPILOGUE
