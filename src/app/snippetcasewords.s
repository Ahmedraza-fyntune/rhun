# Scalar initials and word formats.
.include "rhun.inc"
.text
# initial(SC*, SB*, ptr, len, upper) -> bool
FN snippet_case_initial
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rsi, r13
    mov rdx, r14
    call snippet_case_decode
    mov [rsp], rdx
    mov rdi, rbx
    mov rsi, r13
    mov rcx, rax
    mov r8, r15
    mov r9, r12
    call snippet_case_mapped
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    mov rax, [rsp]
    lea rdx, [r13 + rax]
    mov rcx, r14
    sub rcx, rax
    mov r8d, 4194304
    call snippet_case_append
8:  EPILOGUE
# words(SC*, ptr, len, camel, SB*) -> bool
FN snippet_case_words
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov qword ptr [rsp + 8], -1
    mov qword ptr [rsp + 16], 0
    mov r15, r8
    xor r14d, r14d
.Lcw_loop:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lcw_bad
    cmp r14, r13
    jae .Lcw_end
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
    jz 1f
    cmp qword ptr [rsp + 8], -1
    jne .Lcw_next
    mov [rsp + 8], r14
    jmp .Lcw_next
1:  cmp qword ptr [rsp + 8], -1
    je .Lcw_next
    mov rdi, rbx
    mov rsi, r15
    mov rax, [rsp + 8]
    lea rdx, [r12 + rax]
    mov rcx, r14
    sub rcx, rax
    mov r8d, 1
    cmp qword ptr [rsp], 0
    je 2f
    cmp qword ptr [rsp + 16], 0
    jne 2f
    xor r8d, r8d
2:  call snippet_case_initial
    inc qword ptr [rsp + 16]
    mov qword ptr [rsp + 8], -1
.Lcw_next:
    add r14, [rsp + 24]
    jmp .Lcw_loop
.Lcw_end:
    cmp qword ptr [rsp + 8], -1
    je .Lcw_fallback
    mov rdi, rbx
    mov rsi, r15
    mov rax, [rsp + 8]
    lea rdx, [r12 + rax]
    mov rcx, r13
    sub rcx, rax
    mov r8d, 1
    cmp qword ptr [rsp], 0
    je 2f
    cmp qword ptr [rsp + 16], 0
    jne 2f
    xor r8d, r8d
2:  call snippet_case_initial
    inc qword ptr [rsp + 16]
.Lcw_fallback:
    cmp qword ptr [rsp + 16], 0
    jne .Lcw_ok
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    mov r8d, 4194304
    call snippet_case_append
.Lcw_ok:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lcw_bad
    mov eax, 1
    EPILOGUE
.Lcw_bad:
    xor eax, eax
    EPILOGUE
