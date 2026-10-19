# Ordered Unicode word matching for kebab snippet formats.
.include "rhun.inc"
.text
# consume(SC*, input, len, byteindex, propertyid or -1 digits) -> endindex
FN snippet_case_consume
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
1:  mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne 9f
    cmp r14, r13
    jae 9f
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    # Length must survive the predicate call.
    push rdx
    sub rsp, 8
    cmp r15, -1
    je 2f
    mov rdi, rbx
    mov esi, eax
    mov rdx, r15
    call snippet_case_property
    jmp 3f
2:  sub eax, 48
    cmp eax, 9
    setbe al
    movzx eax, al
3:  add rsp, 8
    pop rdx
    test eax, eax
    jz 9f
    add r14, rdx
    jmp 1b
9:  mov rax, r14
    EPILOGUE
# emit(SC*, SB*, ptr, len, priorwordcount) -> bool
FN snippet_case_kebab_emit
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test r8, r8
    jz 1f
    lea rdx, [rip + .Lck_hyphen]
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
1:  mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r12
    call snippet_case_lower
    EPILOGUE
# kebab(SC*, input, len, SB*) -> bool
FN snippet_case_kebab
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov qword ptr [rsp + 8], 0
    xor r14d, r14d
.Lck_initial:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    cmp r14, r13
    jae .Lck_original
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    call snippet_case_word
    test eax, eax
    jnz .Lck_trim
    add r14, [rsp + 24]
    jmp .Lck_initial
.Lck_original:
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, r12
    mov rcx, r13
    mov r8d, 4194304
    call snippet_case_append
    jmp .Lck_done
.Lck_trim:
    xor r14d, r14d
    mov r15, r13
.Lck_left:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    cmp r14, r15
    jae .Lck_underscores
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 5
    call snippet_case_property
    test eax, eax
    jz .Lck_right
    add r14, [rsp + 24]
    jmp .Lck_left
.Lck_right:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    cmp r14, r15
    jae .Lck_underscores
    mov rdi, [rbx + SC_rx]
    mov esi, 4
    call snippet_regex_spend
    test eax, eax
    jz .Lck_bad
    lea rdi, [r12 + r15 - 1]
1:  movzx eax, byte ptr [rdi]
    and eax, 0xc0
    cmp eax, 0x80
    jne 2f
    dec rdi
    jmp 1b
2:  lea rsi, [r12 + r15]
    sub rsi, rdi
    call utf8_decode
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 5
    call snippet_case_property
    test eax, eax
    jz .Lck_underscores
    sub r15, [rsp + 24]
    jmp .Lck_right
.Lck_underscores:
    cmp r14, r15
    jae .Lck_view
    cmp byte ptr [r12 + r14], 95
    jne .Lck_trailing
    mov rdi, [rbx + SC_rx]
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lck_bad
    inc r14
    jmp .Lck_underscores
.Lck_trailing:
    cmp r14, r15
    jae .Lck_view
    cmp byte ptr [r12 + r15 - 1], 95
    jne .Lck_view
    mov rdi, [rbx + SC_rx]
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lck_bad
    dec r15
    jmp .Lck_trailing
.Lck_view:
    add r12, r14
    mov r13, r15
    sub r13, r14
    xor r14d, r14d
.Lck_loop:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    cmp r14, r13
    jae .Lck_fallback
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 1
    call snippet_case_property
    test eax, eax
    jz .Lck_notupper
    mov rax, [rsp + 24]
    add rax, r14
    mov [rsp + 32], rax
    mov [rsp + 40], r14
    mov qword ptr [rsp + 48], 1
.Lck_upperrun:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    mov rax, [rsp + 32]
    cmp rax, r13
    jae .Lck_afterrun
    mov rdi, rbx
    lea rsi, [r12 + rax]
    mov rdx, r13
    sub rdx, rax
    call snippet_case_decode
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 1
    call snippet_case_property
    test eax, eax
    jz .Lck_afterrun
    mov rax, [rsp + 32]
    mov [rsp + 40], rax
    add rax, [rsp + 24]
    mov [rsp + 32], rax
    inc qword ptr [rsp + 48]
    jmp .Lck_upperrun
.Lck_afterrun:
    mov qword ptr [rsp + 56], 0
    mov rax, [rsp + 32]
    cmp rax, r13
    jae .Lck_emitrun
    mov rdi, rbx
    lea rsi, [r12 + rax]
    mov rdx, r13
    sub rdx, rax
    call snippet_case_decode
    mov [rsp + 56], rax
    mov rdi, rbx
    mov esi, eax
    mov edx, 2
    call snippet_case_property
    test eax, eax
    jz .Lck_runseparator
    cmp qword ptr [rsp + 48], 2
    jb .Lck_runlower
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + r14]
    mov rcx, [rsp + 40]
    sub rcx, r14
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
    inc qword ptr [rsp + 8]
.Lck_runlower:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rsp + 32]
    mov r8d, 2
    call snippet_case_consume
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    mov r8, -1
    call snippet_case_consume
    mov r15, rax
    mov rax, [rsp + 40]
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + rax]
    mov rcx, r15
    sub rcx, rax
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
    inc qword ptr [rsp + 8]
    mov r14, r15
    jmp .Lck_loop
.Lck_runseparator:
    mov rdi, rbx
    mov rsi, [rsp + 56]
    call snippet_case_separator
    test eax, eax
    jnz .Lck_emitrun
    mov r14, [rsp + 32]
    jmp .Lck_loop
.Lck_emitrun:
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + r14]
    mov rcx, [rsp + 32]
    sub rcx, r14
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
    inc qword ptr [rsp + 8]
    mov r14, [rsp + 32]
    jmp .Lck_loop
.Lck_notupper:
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, 2
    call snippet_case_property
    test eax, eax
    jz .Lck_digit
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    add rcx, [rsp + 24]
    mov r8d, 2
    call snippet_case_consume
    mov rcx, rax
    jmp .Lck_digitscan
.Lck_digit:
    mov rax, [rsp + 16]
    sub eax, 48
    cmp eax, 9
    ja .Lck_skip
    mov rcx, r14
    add rcx, [rsp + 24]
.Lck_digitscan:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov r8, -1
    call snippet_case_consume
    mov r15, rax
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + r14]
    mov rcx, r15
    sub rcx, r14
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
    inc qword ptr [rsp + 8]
    mov r14, r15
    jmp .Lck_loop
.Lck_skip:
    add r14, [rsp + 24]
    jmp .Lck_loop
.Lck_fallback:
    cmp qword ptr [rsp + 8], 0
    jne .Lck_done
    mov qword ptr [rsp + 88], -1
    xor r14d, r14d
.Lck_split:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    cmp r14, r13
    jae .Lck_tail
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    call snippet_case_separator
    test eax, eax
    jz 1f
    cmp qword ptr [rsp + 88], -1
    je .Lck_splitnext
    mov rax, [rsp + 88]
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + rax]
    mov rcx, r14
    sub rcx, rax
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
    inc qword ptr [rsp + 8]
    mov qword ptr [rsp + 88], -1
    jmp .Lck_splitnext
1:  cmp qword ptr [rsp + 88], -1
    jne .Lck_splitnext
    mov [rsp + 88], r14
.Lck_splitnext:
    add r14, [rsp + 24]
    jmp .Lck_split
.Lck_tail:
    cmp qword ptr [rsp + 88], -1
    je .Lck_done
    mov rax, [rsp + 88]
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + rax]
    mov rcx, r13
    sub rcx, rax
    mov r8, [rsp + 8]
    call snippet_case_kebab_emit
.Lck_done:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lck_bad
    mov eax, 1
    EPILOGUE
.Lck_bad:
    xor eax, eax
    EPILOGUE
.section .rodata
.Lck_hyphen: .byte 45
