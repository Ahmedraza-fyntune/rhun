# Deferred results use the original prefix and current indentation settings.
.include "rhun.inc"
.text
# fill(SC*, SB*, byte, count) -> bool. Reserve all bytes before allocating/writing.
FN snippet_transform_fill
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, [rbx + SC_rx]
    cmp qword ptr [rdi + RX_error], 0
    jne 8f
    mov rax, [r12 + SB_len]
    cmp rax, 4194304
    ja 7f
    mov edx, 4194304
    sub rdx, rax
    cmp r14, rdx
    ja 7f
    mov rsi, r14
    call snippet_regex_spend
    test eax, eax
    jz 8f
    test r14, r14
    jz 9f
    mov rax, [r12 + SB_len]
    lea rdx, [rax + r14 + 1]
    cmp rdx, [r12 + SB_cap]
    jbe 1f
    mov rax, [r12 + SB_cap]
    add rax, rax
    cmp rdx, rax
    cmovb rdx, rax
    cmp rdx, 4194305
    jbe 2f
    mov edx, 4194305
2:  mov rdi, rbx
    mov rsi, r12
    call snippet_case_reserve
    test eax, eax
    jz 8f
1:  mov rdi, [r12 + SB_ptr]
    add rdi, [r12 + SB_len]
    mov rsi, r13
    mov rdx, r14
    call memset
    add [r12 + SB_len], r14
    mov rdi, [r12 + SB_ptr]
    add rdi, [r12 + SB_len]
    mov byte ptr [rdi], 0
9:  mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_CASE_OUTPUT_ERROR
    call snippet_case_fail
8:  xor eax, eax
    EPILOGUE
# columns(RX*, ptr, len, initialcolumn, width, stop-at-text) -> column, consumed, ecx ok
# Input bytes were prepaid; periodic clocks bound long whitespace scans.
FN snippet_transform_columns
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp + 8], r9
    mov qword ptr [rsp], 0
1:  mov rax, [rsp]
    cmp rax, r13
    jae 9f
    and eax, 1023
    jnz 2f
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz 8f
2:  mov rax, [rsp]
    movzx ecx, byte ptr [r12 + rax]
    cmp ecx, 9
    je 3f
    cmp ecx, 32
    je 4f
    cmp qword ptr [rsp + 8], 0
    jne 9f
4:  inc r14
    jmp 5f
3:  mov rax, r14
    xor edx, edx
    div r15
    mov rax, r15
    sub rax, rdx
    add r14, rax
5:  inc qword ptr [rsp]
    jmp 1b
9:  mov rax, r14
    mov rdx, [rsp]
    mov ecx, 1
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
# indent(RX*, readonly TI*) -> owned bytes, len, ecx success
FN snippet_transform_indent
    PROLOGUE 144
    mov r15, rdi
    mov r12, rsi
    cmp qword ptr [r15 + RX_error], 0
    jne .Lti_sticky
    mov rbx, rsp
    mov rdi, rsp
    mov ecx, 144/8
    xor eax, eax
    rep stosq
    mov [rbx + SC_rx], r15
    mov qword ptr [r15 + RX_pc], -1
    mov qword ptr [r15 + RX_errbyte], -1
    mov r13, [r12 + TI_input]
    mov r14, [r12 + TI_ilen]
    mov rax, [r12 + TI_prefix]
    mov [rsp + 96], rax
    mov rax, [r12 + TI_plen]
    mov [rsp + 104], rax
    mov rax, [r12 + TI_width]
    cmp rax, 1
    jb .Lti_argument
    cmp rax, 16
    ja .Lti_argument
    mov [rsp + 112], rax
    mov rax, [r12 + TI_spaces]
    cmp rax, 1
    ja .Lti_argument
    mov [rsp + 120], rax
    cmp r14, 4194304
    ja .Lti_input
    cmp qword ptr [rsp + 104], 4194304
    ja .Lti_input
    mov rdi, r15
    call snippet_regex_clock
    test eax, eax
    jz .Lti_finish
    mov rdi, r15
    lea rsi, [r14 + r14*2 + 1]
    add rsi, [rsp + 104]
    call snippet_regex_spend
    test eax, eax
    jz .Lti_finish
    xor r15d, r15d
.Lti_utf8:
    cmp r15, r14
    jae .Lti_prefix_init
    lea rdi, [r13 + r15]
    mov rsi, r14
    sub rsi, r15
    call utf8_decode
    cmp eax, 0x10ffff
    ja .Lti_invalid
    cmp eax, 0xd800
    jb 1f
    cmp eax, 0xdfff
    jbe .Lti_invalid
1:  cmp eax, 0xfffd
    jne 2f
    cmp edx, 1
    je .Lti_invalid
2:  add r15, rdx
    mov rax, r15
    and eax, 1023
    cmp rax, rdx
    jae .Lti_utf8
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lti_finish
    jmp .Lti_utf8
.Lti_prefix_init:
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lti_finish
    xor r15d, r15d
.Lti_prefix:
    cmp r15, [rsp + 104]
    jae .Lti_lines_init
    mov rax, r15
    and eax, 1023
    jnz 1f
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lti_finish
1:  mov rax, [rsp + 96]
    movzx eax, byte ptr [rax + r15]
    cmp eax, 32
    je 2f
    cmp eax, 9
    jne .Lti_argument
2:  inc r15
    jmp .Lti_prefix
.Lti_lines_init:
    xor r15d, r15d
    mov qword ptr [rsp + 88], 1
.Lti_line_start:
    mov [rsp + 64], r15
.Lti_scan:
    mov rax, [rsp + 64]
    cmp rax, r14
    jae .Lti_line
    and eax, 1023
    jnz 1f
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lti_finish
1:  mov rax, [rsp + 64]
    movzx eax, byte ptr [r13 + rax]
    cmp eax, 13
    je .Lti_line
    cmp eax, 10
    je .Lti_line
    inc qword ptr [rsp + 64]
    jmp .Lti_scan
.Lti_line:
    mov [rsp + 72], r15
    cmp qword ptr [rsp + 88], 0
    jne .Lti_content
    mov rdi, [rbx + SC_rx]
    mov rsi, [rsp + 104]
    call snippet_regex_spend
    test eax, eax
    jz .Lti_finish
    mov rdi, [rbx + SC_rx]
    mov rsi, [rsp + 96]
    mov rdx, [rsp + 104]
    xor ecx, ecx
    mov r8, [rsp + 112]
    xor r9d, r9d
    call snippet_transform_columns
    test ecx, ecx
    jz .Lti_finish
    mov rcx, rax
    mov rdi, [rbx + SC_rx]
    lea rsi, [r13 + r15]
    mov rdx, [rsp + 64]
    sub rdx, r15
    mov r8, [rsp + 112]
    mov r9d, 1
    call snippet_transform_columns
    test ecx, ecx
    jz .Lti_finish
    add rdx, r15
    mov [rsp + 72], rdx
    mov [rsp + 80], rax
    cmp qword ptr [rsp + 120], 0
    jne .Lti_spaces
    xor edx, edx
    div qword ptr [rsp + 112]
    mov [rsp + 80], rdx
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    mov edx, 9
    mov rcx, rax
    call snippet_transform_fill
    test eax, eax
    jz .Lti_finish
.Lti_spaces:
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    mov edx, 32
    mov rcx, [rsp + 80]
    call snippet_transform_fill
    test eax, eax
    jz .Lti_finish
.Lti_content:
    mov rax, [rsp + 72]
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    lea rdx, [r13 + rax]
    mov rcx, [rsp + 64]
    sub rcx, rax
    mov r8d, 4194304
    call snippet_case_append
    test eax, eax
    jz .Lti_finish
    mov rax, [rsp + 64]
    cmp rax, r14
    je .Lti_finish
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    lea rdx, [rip + .Lti_lf]
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
    test eax, eax
    jz .Lti_finish
    mov rax, [rsp + 64]
    lea r15, [rax + 1]
    cmp byte ptr [r13 + rax], 13
    jne 1f
    cmp r15, r14
    jae 1f
    cmp byte ptr [r13 + r15], 10
    jne 1f
    inc r15
1:  mov qword ptr [rsp + 88], 0
    jmp .Lti_line_start
.Lti_invalid:
    mov rax, [rbx + SC_rx]
    mov [rax + RX_errbyte], r15
.Lti_input:
    mov esi, RX_INPUT_ERROR
    jmp .Lti_fail
.Lti_argument:
    mov esi, RX_CASE_OP_ERROR
.Lti_fail:
    mov rdi, rbx
    call snippet_case_fail
.Lti_finish:
    mov rdi, rbx
    call snippet_case_finish
    EPILOGUE
.Lti_sticky:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.section .rodata
.Lti_lf: .byte 10
