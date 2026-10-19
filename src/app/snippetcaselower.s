# Full default lowercase, including substring-local Unicode Final_Sigma.
.include "rhun.inc"
.text
# lower(SC*, input, len, SB*) -> bool
FN snippet_case_lower
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, rcx
    xor r14d, r14d
    mov qword ptr [rsp], 0
.Lcl_loop:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lcl_bad
    cmp r14, r13
    jae .Lcl_ok
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 4
    call snippet_case_property
    mov [rsp + 8], rax
    cmp qword ptr [rsp + 16], 0x3a3
    jne .Lcl_map
    cmp qword ptr [rsp], 0
    je .Lcl_map
    mov rax, [rsp + 24]
    add rax, r14
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
.Lcl_look:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lcl_bad
    mov rax, [rsp + 32]
    cmp rax, r13
    jae .Lcl_sigma
    mov rdi, rbx
    lea rsi, [r12 + rax]
    mov rdx, r13
    sub rdx, rax
    call snippet_case_decode
    add [rsp + 32], rdx
    mov [rsp + 40], rax
    mov rdi, rbx
    mov esi, eax
    mov edx, 4
    call snippet_case_property
    test eax, eax
    jz 2f
    mov qword ptr [rsp + 40], 0
    jmp .Lcl_look
2:
    mov rdi, rbx
    mov rsi, [rsp + 40]
    mov edx, 3
    call snippet_case_property
    mov [rsp + 40], rax
    jmp .Lcl_sigma
.Lcl_sigma:
    cmp qword ptr [rsp + 40], 0
    jne .Lcl_map
    mov rdi, [rbx + SC_rx]
    mov esi, 16
    call snippet_regex_spend
    test eax, eax
    jz .Lcl_bad
    mov rdi, rbx
    mov rsi, r15
    lea rdx, [rip + .Lcl_final]
    mov ecx, 2
    mov r8d, 4194304
    call snippet_case_append
    jmp .Lcl_prior
.Lcl_map:
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, [rsp + 24]
    mov rcx, [rsp + 16]
    xor r8d, r8d
    mov r9, r15
    call snippet_case_mapped
.Lcl_prior:
    cmp qword ptr [rsp + 8], 0
    jne 1f
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, 3
    call snippet_case_property
    mov [rsp], rax
1:  add r14, [rsp + 24]
    jmp .Lcl_loop
.Lcl_bad:
    xor eax, eax
    EPILOGUE
.Lcl_ok:
    mov eax, 1
    EPILOGUE
.section .rodata
.Lcl_final: .byte 0xcf,0x82
