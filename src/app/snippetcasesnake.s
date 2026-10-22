.include "rhun.inc"
.text
# snake(SC*, ptr, len, SB*) -> bool
FN snippet_case_snake
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, rcx
    xor r14d, r14d
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
.Lcs_loop:
    mov rax, [rbx + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne .Lcs_bad
    cmp r14, r13
    jae .Lcs_lower
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call snippet_case_decode
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov esi, eax
    mov edx, 5
    call snippet_case_property
    test eax, eax
    jnz .Lcs_sep
    cmp qword ptr [rsp + 16], 45
    je .Lcs_sep
    mov qword ptr [rsp + 32], 0
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, 1
    call snippet_case_property
    test eax, eax
    jz 1f
    cmp qword ptr [rsp], 0
    je 1f
    mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    lea rdx, [rip + .Lcs_underscore]
    mov ecx, 1
    mov r8d, 8388608
    call snippet_case_append
1:  mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    lea rdx, [r12 + r14]
    mov rcx, [rsp + 24]
    mov r8d, 8388608
    call snippet_case_append
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, 2
    call snippet_case_property
    mov [rsp], rax
    jmp .Lcs_next
.Lcs_sep:
    cmp qword ptr [rsp + 8], 0
    jne 1f
    mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    lea rdx, [rip + .Lcs_underscore]
    mov ecx, 1
    mov r8d, 8388608
    call snippet_case_append
1:  mov qword ptr [rsp], 0
    mov qword ptr [rsp + 32], 1
.Lcs_next:
    mov rax, [rsp + 32]
    mov [rsp + 8], rax
    add r14, [rsp + 24]
    jmp .Lcs_loop
.Lcs_lower:
    mov rdi, rbx
    mov rsi, [rbx + SC_prep + SB_ptr]
    mov rdx, [rbx + SC_prep + SB_len]
    mov rcx, r15
    call snippet_case_lower
    EPILOGUE
.Lcs_bad:
    xor eax, eax
    EPILOGUE
.section .rodata
.Lcs_underscore: .byte 95
