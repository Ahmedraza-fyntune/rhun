.include "rhun.inc"
.text
# Ordinary editing passes no context. Only transform preflight can time out.
FN snippet_deadline_optional
    test rdi, rdi
    jnz snippet_regex_clock
    mov eax, 1
    ret

# Recoverable, independently owned marker copies for transform preflight.
FN snippet_clone_chain_try
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
1:  test rbx, rbx
    jz 8f
    mov edi, SN_SIZE
    call mem_alloc_try
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, rax
    mov rsi, rbx
    mov edx, SN_SIZE
    call memcpy
    mov rcx, [r14 + SN_choice]
    test rcx, rcx
    jz 2f
    inc qword ptr [rcx + SC_refs]
2:  mov rcx, [r14 + SN_transform]
    test rcx, rcx
    jz 3f
    inc qword ptr [rcx + SC_refs]
3:  mov rcx, [r14 + SN_indent]
    test rcx, rcx
    jz 4f
    inc qword ptr [rcx + SC_refs]
4:  mov qword ptr [r14 + SN_parent], 0
    mov [r14 + SN_child], r12
    test r12, r12
    jz 5f
    mov [r12 + SN_parent], r14
    jmp 6f
5:  mov r13, r14
6:  mov r12, r14
    mov rbx, [rbx + SN_parent]
    jmp 1b
8:  mov rax, r13
    EPILOGUE
9:  mov rdi, r13
    call snippet_free_chain
    xor eax, eax
    EPILOGUE

# (top, doc or 0, shared insertion-byte counter, optional preflight RX) -> bool.
FN snippet_propagate_chain_budget
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
1:  mov rdi, r14
    call snippet_deadline_optional
    test eax, eax
    jz 9f
    test rbx, rbx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call snippet_propagate
    test eax, eax
    jz 9f
    mov rbx, [rbx + SN_parent]
    jmp 1b
8:  mov eax, 1
9:  EPILOGUE
