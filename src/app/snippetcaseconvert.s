.include "rhun.inc"
.text
# convert(RX*, input, len, op) -> owned bytes, len, ecx success
FN snippet_case_convert
    PROLOGUE SC_SIZE
    mov r15, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rbx, rsp
    mov rdi, rsp
    mov ecx, SC_SIZE/8
    xor eax, eax
    rep stosq
    mov [rbx + SC_rx], r15
    cmp qword ptr [r15 + RX_error], 0
    jne .Lcc_bad
    mov qword ptr [r15 + RX_errbyte], -1
    mov qword ptr [r15 + RX_pc], -1
    cmp r14, 2
    jb .Lcc_op
    cmp r14, 8
    ja .Lcc_op
    cmp r13, 4194304
    ja .Lcc_input
    mov rdi, r15
    call snippet_regex_clock
    test eax, eax
    jz .Lcc_bad
    mov rdi, r15
    lea rsi, [r13*2 + 1]
    call snippet_regex_spend
    test eax, eax
    jz .Lcc_bad
    # Preserve opcode while scanning strict UTF-8 without processing charges.
    mov r15, r14
    xor r14d, r14d
.Lcc_scan:
    cmp r14, r13
    jae .Lcc_dispatch
    lea rdi, [r12 + r14]
    mov rsi, r13
    sub rsi, r14
    call utf8_decode
    cmp eax, 0x10ffff
    ja .Lcc_invalid
    cmp eax, 0xd800
    jb 1f
    cmp eax, 0xdfff
    jbe .Lcc_invalid
1:  cmp eax, 0xfffd
    jne 2f
    cmp edx, 1
    je .Lcc_invalid
2:  add r14, rdx
    # Byte-modulo crossings ensure at most 1024 validation scalars
    # between clock checks, including multibyte scalar boundaries.
    mov rax, r14
    and eax, 1023
    cmp rax, rdx
    jae .Lcc_scan
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lcc_bad
    jmp .Lcc_scan
.Lcc_dispatch:
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lcc_bad
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rbx + SC_out]
    cmp r15, 2
    je .Lcc_upper
    cmp r15, 3
    je .Lcc_lower
    cmp r15, 4
    je .Lcc_capital
    cmp r15, 6
    jbe .Lcc_words
    cmp r15, 7
    je .Lcc_snake
    call snippet_case_kebab
    jmp .Lcc_complete
.Lcc_upper:
    call snippet_case_upper
    jmp .Lcc_complete
.Lcc_lower:
    call snippet_case_lower
    jmp .Lcc_complete
.Lcc_capital:
    test r13, r13
    jz .Lcc_complete
    lea rsi, [rbx + SC_out]
    mov rdx, r12
    mov rcx, r13
    mov r8d, 1
    call snippet_case_initial
    jmp .Lcc_complete
.Lcc_words:
    lea r8, [rbx + SC_out]
    xor ecx, ecx
    cmp r15, 5
    sete cl
    call snippet_case_words
    jmp .Lcc_complete
.Lcc_snake:
    call snippet_case_snake
.Lcc_complete:
    mov rdi, rbx
    call snippet_case_finish
    EPILOGUE
.Lcc_invalid:
    mov rax, [rbx + SC_rx]
    mov [rax + RX_errbyte], r14
.Lcc_input:
    mov esi, RX_INPUT_ERROR
    jmp .Lcc_fail
.Lcc_op:
    mov esi, RX_CASE_OP_ERROR
.Lcc_fail:
    mov rdi, rbx
    call snippet_case_fail
.Lcc_bad:
    mov rdi, rbx
    call snippet_case_cleanup
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
# upper(SC*, input, len, SB*) -> bool
FN snippet_case_upper
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, rcx
    xor r14d, r14d
1:  mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne 8f
    cmp r14, r13
    jae 9f
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov rcx, rax
    mov rdi, rbx
    lea rsi, [r12 + r14]
    add r14, rdx
    mov r8d, 1
    mov r9, r15
    call snippet_case_mapped
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# finish(SC*) -> owned bytes, len, ecx success. Also used by deadline tests.
FN snippet_case_finish
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz 8f
    lea rdi, [rbx + SC_prep]
    call sb_free
    mov rax, [rbx + SC_out + SB_ptr]
    mov rdx, [rbx + SC_out + SB_len]
    mov qword ptr [rbx + SC_out + SB_ptr], 0
    mov qword ptr [rbx + SC_out + SB_len], 0
    mov qword ptr [rbx + SC_out + SB_cap], 0
    mov ecx, 1
    EPILOGUE
8:  mov rdi, rbx
    call snippet_case_cleanup
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
