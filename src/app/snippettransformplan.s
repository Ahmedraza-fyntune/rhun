.include "rhun.inc"
.text
# (STL*, marker top, doc or 0, preflight RX or 0) -> bool.
# Both passes choose from the same stable field indices and current marker positions.
FN snippet_transform_apply_plan
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor ecx, ecx
1:  cmp rcx, [rbx + STL_count]
    jae .Lstap_choose
    imul rax, rcx, STLR_SIZE
    add rax, [rbx + STL_plan]
    mov qword ptr [rax + STLR_done], 0
    inc rcx
    jmp 1b
.Lstap_choose:
    mov rdi, r14
    call snippet_deadline_optional
    test eax, eax
    jz .Lstap_bad
    xor r15d, r15d
    mov qword ptr [rsp], 0      # best current position
    mov qword ptr [rsp + 8], 0  # best field index
    xor ecx, ecx
2:  cmp rcx, [rbx + STL_count]
    jae .Lstap_chosen
    imul rax, rcx, STLR_SIZE
    add rax, [rbx + STL_plan]
    inc rcx
    cmp qword ptr [rax + STLR_done], 0
    jne 2b
    mov rdx, [rax + STLR_field]
    imul rsi, rdx, SF_SIZE
    lea rsi, [r12 + rsi + SN_fields]
    mov rsi, [rsi + SF_start]
    test r15, r15
    jz 4f
    cmp rsi, [rsp]
    jb 2b
    ja 4f
    cmp rdx, [rsp + 8]
    jbe 2b
4:  mov r15, rax
    mov [rsp], rsi
    mov [rsp + 8], rdx
    jmp 2b
.Lstap_chosen:
    test r15, r15
    jz .Lstap_done
    mov qword ptr [r15 + STLR_done], 1
    mov rax, [r15 + STLR_field]
    imul rax, rax, SF_SIZE
    lea rax, [r12 + rax + SN_fields]
    mov rdx, [rax + SF_end]
    sub rdx, [rsp]
    mov [rsp + 16], rdx         # deleted bytes
    mov rdi, r12
    mov rsi, [r15 + STLR_field]
    mov rcx, rdx
    mov rdx, [rsp]
    mov r8, [r15 + STLR_len]
    mov r9, r14
    call snippet_retire_touch_limited
    test eax, eax
    jz .Lstap_bad
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, rsi
    add rdx, [rsp + 16]
    call snippet_chain_replace_mark
    cmp qword ptr [rsp + 16], 0
    je .Lstap_insert
    test r13, r13
    jz 5f
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 16]
    mov ecx, EK_OTHER
    call doc_delete
5:  mov rdi, r12
    mov rsi, [r15 + STLR_field]
    mov rdx, [rsp]
    mov rcx, [rsp + 16]
    xor r8d, r8d
    call snippet_map_chain
.Lstap_insert:
    mov rdi, r14
    call snippet_deadline_optional
    test eax, eax
    jz .Lstap_bad
    cmp qword ptr [r15 + STLR_len], 0
    je .Lstap_clear
    test r13, r13
    jz 6f
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [r15 + STLR_output]
    mov rcx, [r15 + STLR_len]
    mov r8d, EK_OTHER
    call doc_insert
6:  mov rdi, r12
    mov rsi, [r15 + STLR_field]
    mov rdx, [rsp]
    xor ecx, ecx
    mov r8, [r15 + STLR_len]
    call snippet_map_chain
.Lstap_clear:
    mov rdi, r14
    call snippet_deadline_optional
    test eax, eax
    jz .Lstap_bad
    mov rdi, r12
    call snippet_chain_replace_clear
    jmp .Lstap_choose
.Lstap_done:
    mov rax, [rbx + STL_group]
    imul rax, rax, SG_SIZE
    mov qword ptr [r12 + rax + SN_groups + SG_dirty], 0
    mov eax, 1
    EPILOGUE
.Lstap_bad:
    xor eax, eax
    EPILOGUE
