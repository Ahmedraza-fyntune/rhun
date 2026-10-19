# Standalone adversarial private API probes, with a unit entry point.
.include "rhun.inc"
.text
FN main
    PROLOGUE
    call snippet_case_api_test
    test eax, eax
    jz 1f
    lea rdi, [rip + .Lca_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
1:  lea rdi, [rip + .Lca_failed]
    call log_cstr
    mov eax, 1
    EPILOGUE
FN snippet_case_api_test
    PROLOGUE SC_SIZE+16
    mov r15, [rip + g_mem_live]
    mov rbx, rsp
    mov rdi, rbx
    mov ecx, SC_SIZE/8
    xor eax, eax
    rep stosq
    # Shared-budget conversions, successful matcher-state preservation and empty input.
    mov edi, 49
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lca_bad
    mov r12, rax
    mov qword ptr [r12 + RX_ready], 1
    mov qword ptr [r12 + RX_hasmatch], 1
    mov qword ptr [r12 + RX_captures], 7
    mov qword ptr [r12 + RX_captures + 8], 11
    mov r13d, 2
.Lca_twice:
    mov rdi, r12
    lea rsi, [rip + .Lca_a]
    mov edx, 1
    mov ecx, 2
    call snippet_case_convert
    cmp ecx, 1
    jne .Lca_bad
    cmp rdx, 1
    jne .Lca_bad
    cmp byte ptr [rax], 65
    jne .Lca_bad
    mov rdi, rax
    call mem_free
    cmp qword ptr [r12 + RX_ready], 1
    jne .Lca_bad
    cmp qword ptr [r12 + RX_hasmatch], 1
    jne .Lca_bad
    cmp qword ptr [r12 + RX_captures], 7
    jne .Lca_bad
    cmp qword ptr [r12 + RX_captures + 8], 11
    jne .Lca_bad
    dec r13
    jnz .Lca_twice
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, 2
    call snippet_case_convert
    test rax, rax
    jnz .Lca_bad
    test rdx, rdx
    jnz .Lca_bad
    cmp ecx, 1
    jne .Lca_bad
    cmp qword ptr [r12 + RX_work], 0
    jne .Lca_bad
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, 2
    call snippet_case_convert
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_error], RX_WORK_ERROR
    jne .Lca_bad
    mov qword ptr [r12 + RX_errbyte], 42
    mov rdi, r12
    xor esi, esi
    mov rdx, -1
    mov rcx, -1
    call snippet_case_convert
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_errbyte], 42
    jne .Lca_bad
    mov rdi, r12
    call snippet_regex_free
    # Expired entry deadline must avoid reading a nonempty invalid pointer.
    mov edi, 10000
    mov esi, 1
    call snippet_regex_new
    test rax, rax
    jz .Lca_bad
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    mov edx, 1
    mov ecx, 2
    call snippet_case_convert
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_error], RX_TIME_ERROR
    jne .Lca_bad
    mov rdi, r12
    call snippet_regex_free
    # Private builders exercise cap failure and real recoverable allocation failure.
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lca_bad
    mov r12, rax
    mov [rbx + SC_rx], rax
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    lea rdx, [rip + .Lca_a]
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
    cmp eax, 1
    jne .Lca_bad
    mov r14, [rbx + SC_out + SB_ptr]
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    mov rdx, 1 << 40
    call snippet_case_reserve
    test eax, eax
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_error], RX_CASE_ALLOC_ERROR
    jne .Lca_bad
    cmp [rbx + SC_out + SB_ptr], r14
    jne .Lca_bad
    cmp qword ptr [rbx + SC_out + SB_len], 1
    jne .Lca_bad
    cmp byte ptr [r14], 97
    jne .Lca_bad
    mov rdi, rbx
    call snippet_case_finish
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    cmp qword ptr [rbx + SC_out + SB_ptr], 0
    jne .Lca_bad
    mov rdi, r12
    call snippet_regex_free
    # Late deadline checks free both populated buffers before publishing anything.
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    mov r12, rax
    test rax, rax
    jz .Lca_bad
    mov [rbx + SC_rx], rax
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    lea rdx, [rip + .Lca_a]
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
    test eax, eax
    jz .Lca_bad
    mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    lea rdx, [rip + .Lca_a]
    mov ecx, 1
    mov r8d, 8388608
    call snippet_case_append
    test eax, eax
    jz .Lca_bad
    mov qword ptr [r12 + RX_deadline], 1
    mov rdi, rbx
    call snippet_case_finish
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_error], RX_TIME_ERROR
    jne .Lca_bad
    cmp qword ptr [rbx + SC_out + SB_ptr], 0
    jne .Lca_bad
    cmp qword ptr [rbx + SC_prep + SB_ptr], 0
    jne .Lca_bad
    mov rdi, r12
    call snippet_regex_free
    # Full output cap refuses another byte before spending or reading it.
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    mov r12, rax
    test rax, rax
    jz .Lca_bad
    mov [rbx + SC_rx], rax
    mov qword ptr [rbx + SC_out + SB_len], 4194304
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    xor edx, edx
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
    test eax, eax
    jnz .Lca_bad
    cmp qword ptr [r12 + RX_work], 10000
    jne .Lca_bad
    cmp qword ptr [r12 + RX_error], RX_CASE_OUTPUT_ERROR
    jne .Lca_bad
    mov rdi, rbx
    call snippet_case_finish
    or rax, rdx
    or rax, rcx
    jnz .Lca_bad
    mov rdi, r12
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lca_bad
    mov eax, 1
    EPILOGUE
.Lca_bad:
    xor eax, eax
    EPILOGUE
.section .rodata
.Lca_a: .byte 97

.Lca_ok: .asciz "ok snippet case API\n"
.Lca_failed: .asciz "failed snippet case API\n"
