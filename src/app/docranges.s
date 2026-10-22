# Pure, bounded selection normalization shared by edit planners.
.include "rhun.inc"
.text

# doc_ranges_new(doc, optional {cur,anchor} pairs, count) -> owned DNS, or0/edx1.
# Null pairs/count0 reads the document. Explicit pairs keep their input-order identity.
FN doc_ranges_new
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rsi
    xor r12d, r12d
    test rbx, rbx
    jz .Ldns_input
    test rsi, rsi
    jnz .Ldns_count
    test rdx, rdx
    jnz .Ldns_input
    call doc_selections_count
    mov rdx, rax
.Ldns_count:
    test rdx, rdx
    jz .Ldns_input
    cmp rdx, DOC_SELECTIONS_MAX
    ja .Ldns_input
    mov r13, rdx
    mov edi, DNS_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + DNS_count], r13
    mov rdi, rbx
    call doc_len
    mov [r12 + DNS_doclen], rax
    xor r13d, r13d
.Ldns_enumerate:
    cmp r13, [r12 + DNS_count]
    jae .Ldns_normalize
    cmp qword ptr [rsp], 0
    jne .Ldns_explicit
    mov rdi, rbx
    mov rsi, r13
    call doc_selections_get
    test r8d, r8d
    jz .Ldns_input
    jmp .Ldns_endpoints
.Ldns_explicit:
    mov rax, r13
    shl rax, 4
    add rax, [rsp]
    mov rdx, [rax + DMP_anchor]
    mov rax, [rax + DMP_cur]
.Ldns_endpoints:
    mov r14, rax
    mov r15, rdx
    cmp r14, r15
    jbe 1f
    xchg r14, r15
1:  mov rdi, rbx
    mov rsi, r14
    mov rdx, [r12 + DNS_doclen]
    call doc_ranges_boundary
    test eax, eax
    jz .Ldns_input
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [r12 + DNS_doclen]
    call doc_ranges_boundary
    test eax, eax
    jz .Ldns_input
    mov rax, r13
    shl rax, 5
    lea rax, [r12 + rax + DNS_ranges]
    mov [rax + DMR_start], r14
    mov [rax + DMR_end], r15
    mov [rax + DMR_index], r13
    inc r13
    jmp .Ldns_enumerate
.Ldns_normalize:
    lea rdi, [r12 + DNS_ranges]
    mov rsi, [r12 + DNS_count]
    xor edx, edx
    call doc_ranges_sort
    xor r13d, r13d            # last normalized record
    mov r14d, 1              # next input record
.Ldns_merge:
    cmp r14, [r12 + DNS_count]
    jae .Ldns_merged
    mov rax, r13
    shl rax, 5
    lea rdi, [r12 + rax + DNS_ranges]
    mov rax, r14
    shl rax, 5
    lea rsi, [r12 + rax + DNS_ranges]
    mov rax, [rsi + DMR_start]
    cmp rax, [rdi + DMR_end]
    jb .Ldns_join
    ja .Ldns_separate
    cmp rax, [rsi + DMR_end]
    je .Ldns_join
    cmp rax, [rdi + DMR_start]
    jne .Ldns_separate
.Ldns_join:
    mov rax, [rsi + DMR_end]
    cmp rax, [rdi + DMR_end]
    jbe 1f
    mov [rdi + DMR_end], rax
1:  mov rax, [rsi + DMR_index]
    cmp rax, [rdi + DMR_index]
    jae 2f
    mov [rdi + DMR_index], rax
2:  inc r14
    jmp .Ldns_merge
.Ldns_separate:
    inc r13
    mov rax, r13
    shl rax, 5
    lea rdi, [r12 + rax + DNS_ranges]
    mov edx, DMR_SIZE
    call memmove
    inc r14
    jmp .Ldns_merge
.Ldns_merged:
    inc r13
    mov [r12 + DNS_count], r13
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Ldns_input:
    mov rdi, r12
    call mem_free
    xor eax, eax
    mov edx, 1
    EPILOGUE

# A byte boundary check that does not move the document's gap or allocate scratch.
doc_ranges_boundary:
    cmp rsi, rdx
    ja 8f
    je 9f
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
9:  mov eax, 1
    ret
8:  xor eax, eax
    ret

# Stable in-place sort of bounded records by start/end, or by original index.
FN doc_ranges_sort
    cmp rsi, 2
    jb 9f
    dec rsi
1:  xor ecx, ecx
2:  mov rax, rcx
    shl rax, 5
    add rax, rdi
    mov r8, [rax + rdx]
    cmp r8, [rax + rdx + DMR_SIZE]
    ja 3f
    jb 5f
    test edx, edx
    jnz 5f
    mov r8, [rax + DMR_end]
    cmp r8, [rax + DMR_SIZE + DMR_end]
    jbe 5f
3:  mov r8, [rax]
    mov r9, [rax + DMR_SIZE]
    mov [rax], r9
    mov [rax + DMR_SIZE], r8
    mov r8, [rax + 8]
    mov r9, [rax + DMR_SIZE + 8]
    mov [rax + 8], r9
    mov [rax + DMR_SIZE + 8], r8
    mov r8, [rax + 16]
    mov r9, [rax + DMR_SIZE + 16]
    mov [rax + 16], r9
    mov [rax + DMR_SIZE + 16], r8
    mov r8, [rax + 24]
    mov r9, [rax + DMR_SIZE + 24]
    mov [rax + 24], r9
    mov [rax + DMR_SIZE + 24], r8
5:  inc rcx
    cmp rcx, rsi
    jb 2b
    dec rsi
    jnz 1b
9:  ret
