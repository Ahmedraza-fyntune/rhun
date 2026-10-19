# Replace all selections as one operation, retaining primary identity through merges.
.include "rhun.inc"
.text

# doc_selections_replace(doc, UTF8 payload, length) -> eax success, edx error.
# Errors: 1 invalid input/selection, 2 size limit, 3 readonly, 4 nested batch.
# An enclosing group owner records its final selection after any subsequent edits.
FN doc_selections_replace
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    xor r12d, r12d
    test rbx, rbx
    jz .Ldme_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Ldme_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Ldme_busy
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Ldme_limit
    test rdx, rdx
    jz 1f
    test rsi, rsi
    jz .Ldme_input
1:  mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Ldme_input
    mov r14, rax
    mov edi, DME_SIZE
    call mem_alloc
    mov r12, rax
    mov rcx, [r14 + DNS_count]
    mov [rax + DME_count], rcx
    mov rcx, [r14 + DNS_doclen]
    mov [rax + DME_doclen], rcx
    mov rcx, [rsp]
    mov [rax + DME_input], rcx
    mov rcx, [rsp + 8]
    mov [rax + DME_len], rcx
    lea rdi, [r12 + DME_ranges]
    lea rsi, [r14 + DNS_ranges]
    mov rdx, [r12 + DME_count]
    shl rdx, 5
    call memcpy
    mov rdi, r14
    call mem_free
    mov r13, [r12 + DME_count]
    mov rax, r13
    imul rax, [r12 + DME_len]
    cmp rax, DOC_MULTI_BYTES_MAX
    ja .Ldme_limit
    mov [rsp + 16], rax       # aggregate insertion, bounded before scanning payload
    xor r13d, r13d
    xor r14d, r14d            # signed length delta before this record
.Ldme_positions:
    cmp r13, [r12 + DME_count]
    jae .Ldme_size
    mov rax, r13
    shl rax, 5
    lea rdi, [r12 + rax + DME_ranges]
    mov rax, [rdi + DMR_start]
    add rax, r14
    add rax, [r12 + DME_len]
    mov [rdi + DMR_caret], rax
    mov rdx, [rdi + DMR_end]
    sub rdx, [rdi + DMR_start]
    add [r12 + DME_deleted], rdx
    sub r14, rdx
    add r14, [r12 + DME_len]
    inc r13
    jmp .Ldme_positions
.Ldme_size:
    mov rax, [r12 + DME_doclen]
    sub rax, [r12 + DME_deleted]
    jc .Ldme_input
    add rax, [rsp + 16]
    jc .Ldme_limit
    mov rcx, (1 << 40) - 4096
    cmp rax, rcx
    ja .Ldme_limit
    # Build disjoint original-coordinate edits before sorting the result selections.
    xor r13d, r13d
.Ldme_plan:
    cmp r13, [r12 + DME_count]
    jae .Ldme_output
    mov r14, r13
    shl r14, 5
    lea r14, [r12 + r14 + DME_ranges]
    mov rax, [r14 + DMR_start]
    cmp rax, [r14 + DMR_end]
    jne 1f
    cmp qword ptr [r12 + DME_len], 0
    je 2f
1:  mov rcx, [r12 + DME_nedits]
    shl rcx, 5
    lea rcx, [r12 + rcx + DME_edits]
    mov [rcx + DBE_start], rax
    mov rax, [r14 + DMR_end]
    mov [rcx + DBE_end], rax
    mov rax, [r12 + DME_input]
    mov [rcx + DBE_text], rax
    mov rax, [r12 + DME_len]
    mov [rcx + DBE_len], rax
    inc qword ptr [r12 + DME_nedits]
2:  inc r13
    jmp .Ldme_plan
.Ldme_output:
    lea rdi, [r12 + DME_ranges]
    mov rsi, [r12 + DME_count]
    mov edx, DMR_index
    call doc_ranges_sort
    xor ecx, ecx
1:  cmp rcx, [r12 + DME_count]
    jae 2f
    mov rax, rcx
    shl rax, 5
    mov rdx, [r12 + rax + DME_ranges + DMR_caret]
    mov rax, rcx
    shl rax, 4
    lea rax, [r12 + rax + DME_pairs]
    mov [rax + DMP_cur], rdx
    mov [rax + DMP_anchor], rdx
    inc rcx
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [r12 + DME_edits]
    mov rdx, [r12 + DME_nedits]
    lea rcx, [r12 + DME_pairs]
    mov r8, [r12 + DME_count]
    call doc_selections_apply
    mov [r12 + DME_error], rdx
    jmp .Ldme_free
.Ldme_input:
    mov edx, 1
    jmp .Ldme_error
.Ldme_limit:
    mov edx, 2
    jmp .Ldme_error
.Ldme_readonly:
    mov edx, 3
    jmp .Ldme_error
.Ldme_busy:
    mov edx, 4
.Ldme_error:
    test r12, r12
    jz .Ldme_return_error
    mov [r12 + DME_error], rdx
.Ldme_free:
    mov r13, [r12 + DME_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Ldme_return_error:
    xor eax, eax
    EPILOGUE

