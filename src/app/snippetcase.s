# Shared bounded Unicode snippet case conversion helpers.
.include "rhun.inc"
.text
# Private failure/cleanup. The shared batch keeps the first diagnostic.
FN snippet_case_fail
    mov rdi, [rdi + SC_rx]
    jmp snippet_regex_fail
FN snippet_case_cleanup
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rbx + SC_out]
    call sb_free
    lea rdi, [rbx + SC_prep]
    call sb_free
    EPILOGUE
# reserve(SC*, SB*, capacity) -> bool. Private callers bound normal capacities.
FN snippet_case_reserve
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, 65536
    jae 1f
    mov r13d, 65536
1:  mov rdi, r13
    call mem_alloc_try
    test rax, rax
    jz 8f
    mov r14, rax
    mov rdi, rax
    mov rsi, [r12 + SB_ptr]
    mov rcx, [r12 + SB_len]
    rep movsb
    mov rdi, [r12 + SB_ptr]
    call mem_free
    mov [r12 + SB_ptr], r14
    mov [r12 + SB_cap], r13
    mov eax, 1
    EPILOGUE
8:  mov rdi, rbx
    mov esi, RX_CASE_ALLOC_ERROR
    call snippet_case_fail
    EPILOGUE
# append(SC*, SB*, bytes, length, bytecap) -> bool
FN snippet_case_append
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, [rbx + SC_rx]
    cmp qword ptr [rdi + RX_error], 0
    jne 8f
    mov rax, [r12 + SB_len]
    cmp rax, r15
    ja 7f
    sub r15, rax
    cmp r14, r15
    ja 7f
    add r15, rax
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
    inc r15
    cmp rdx, r15
    cmova rdx, r15
    mov rdi, rbx
    mov rsi, r12
    call snippet_case_reserve
    test eax, eax
    jz 8f
1:  mov rdi, [r12 + SB_ptr]
    add rdi, [r12 + SB_len]
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov byte ptr [rdi], 0
    add [r12 + SB_len], r14
9:  mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_CASE_OUTPUT_ERROR
    call snippet_case_fail
8:  xor eax, eax
    EPILOGUE
# decode(SC*, scalarptr, available) -> cp, length, ecx success
FN snippet_case_decode
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    mov rdi, [rdi + SC_rx]
    mov esi, 4
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call utf8_decode
    mov ecx, 1
    EPILOGUE
8:  xor eax, eax
    mov edx, 1
    xor ecx, ecx
    EPILOGUE
# property(SC*, cp, id) -> bool. IDs L/Lu/Ll/Cased/CI/ECMAspace.
FN snippet_case_property
    PROLOGUE
    mov r12d, esi
    mov r13d, edx
    mov rdi, [rdi + SC_rx]
    mov esi, 16
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov edi, r12d
    cmp r13d, 0
    jne 1f
    call snippet_unicode_letter
    EPILOGUE
1:  cmp r13d, 1
    jne 2f
    call snippet_unicode_upper_letter
    EPILOGUE
2:  cmp r13d, 2
    jne 3f
    call snippet_unicode_lower_letter
    EPILOGUE
3:  cmp r13d, 3
    jne 4f
    call snippet_unicode_cased
    EPILOGUE
4:  cmp r13d, 4
    jne 5f
    call snippet_unicode_case_ignorable
    EPILOGUE
5:  cmp edi, 9
    jb 8f
    cmp edi, 13
    jbe 9f
    cmp edi, 32
    je 9f
    cmp edi, 0xa0
    je 9f
    cmp edi, 0x1680
    je 9f
    cmp edi, 0x2000
    jb 8f
    cmp edi, 0x200a
    jbe 9f
    cmp edi, 0x2028
    je 9f
    cmp edi, 0x2029
    je 9f
    cmp edi, 0x202f
    je 9f
    cmp edi, 0x205f
    je 9f
    cmp edi, 0x3000
    je 9f
    cmp edi, 0xfeff
    je 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
# word(SC*, cp) -> L or ASCII digit. Property always charged first.
FN snippet_case_word
    PROLOGUE
    mov r12d, esi
    xor edx, edx
    call snippet_case_property
    test eax, eax
    jnz 1f
    sub r12d, 48
    cmp r12d, 9
    seta al
    xor eax, 1
    movzx eax, al
1:  EPILOGUE
# separator(SC*, cp) -> ECMAspace or underscore/hyphen.
FN snippet_case_separator
    PROLOGUE
    mov r12d, esi
    mov edx, 5
    call snippet_case_property
    test eax, eax
    jnz 1f
    cmp r12d, 95
    je 2f
    cmp r12d, 45
    sete al
    movzx eax, al
1:  EPILOGUE
2:  mov eax, 1
    EPILOGUE
# mapped(SC*, original, bytelen, cp, upper, SB*) -> bool
FN snippet_case_mapped
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15, r9
    mov [rsp], r8
    mov rdi, [rbx + SC_rx]
    mov esi, 16
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov edi, r14d
    cmp qword ptr [rsp], 0
    je 1f
    call snippet_unicode_upper
    jmp 2f
1:  call snippet_unicode_lower
2:  test rdx, rdx
    jz 3f
    mov r12, rax
    mov r13, rdx
3:  mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    mov r8d, 4194304
    call snippet_case_append
8:  EPILOGUE
