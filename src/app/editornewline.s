# Prepare every newline and final caret before committing a multiple selection edit.
.include "rhun.inc"
.text

# editor_multi_newline(active doc) -> eax success, edx input/limit/readonly/busy.
FN editor_multi_newline
    mov esi, DOC_MULTI_BYTES_MAX
    mov edx, DOC_MULTI_BYTES_MAX
    jmp editor_multi_newline_limited

# Private bounded entry allows deterministic quota tests without allocating huge text.
FN editor_multi_newline_limited
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    xor r12d, r12d
    test rbx, rbx
    jz .Len_input
    cmp rbx, [rip + g_doc]
    jne .Len_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Len_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Len_busy
    cmp rsi, DOC_MULTI_BYTES_MAX
    ja .Len_limit
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Len_limit
    mov edi, ENP_SIZE
    call mem_alloc
    mov r12, rax
    mov rcx, [rsp]
    mov [rax + ENP_limit], rcx
    mov rcx, [rsp + 8]
    mov [rax + ENP_scan], rcx
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Len_input
    mov [r12 + ENP_ranges], rax
    xor r13d, r13d
.Len_plan:
    mov rax, [r12 + ENP_ranges]
    cmp r13, [rax + DNS_count]
    jae .Len_order
    mov r14, r13
    shl r14, 5
    lea r14, [rax + r14 + DNS_ranges]
    mov rdi, rbx
    mov rsi, [r14 + DMR_start]
    mov rdx, [r14 + DMR_end]
    mov rcx, [r12 + ENP_limit]
    sub rcx, [r12 + ENP_bytes]
    lea r8, [r12 + ENP_scan]
    call editor_newline_payload
    test rax, rax
    jz .Len_payload_error
    sub [r14 + DMR_start], r9   # an ended list's marker or an outdented word goes too
    mov [r12 + r13*8 + ENP_payloads], rax
    inc qword ptr [r12 + ENP_built]
    add [r12 + ENP_bytes], rdx
    mov r15, r13
    shl r15, 5
    lea r15, [r12 + r15 + ENP_edits]
    mov [r15 + DBE_text], rax
    mov [r15 + DBE_len], rdx
    mov rax, [r14 + DMR_start]
    mov [r15 + DBE_start], rax
    add rax, [r12 + ENP_delta]
    add rax, rcx
    mov [r14 + DMR_caret], rax
    mov rax, [r14 + DMR_end]
    mov [r15 + DBE_end], rax
    sub rax, [r14 + DMR_start]
    sub [r12 + ENP_delta], rax
    add [r12 + ENP_delta], rdx
    inc r13
    jmp .Len_plan
.Len_order:
    mov rax, [r12 + ENP_ranges]
    lea rdi, [rax + DNS_ranges]
    mov rsi, [rax + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    mov r14, [r12 + ENP_ranges]
    xor ecx, ecx
1:  cmp rcx, [r14 + DNS_count]
    jae .Len_apply
    mov rax, rcx
    shl rax, 5
    mov rdx, [r14 + rax + DNS_ranges + DMR_caret]
    mov rax, rcx
    shl rax, 4
    mov [r12 + rax + ENP_pairs + DMP_cur], rdx
    mov [r12 + rax + ENP_pairs + DMP_anchor], rdx
    inc rcx
    jmp 1b
.Len_apply:
    mov rdi, rbx
    lea rsi, [r12 + ENP_edits]
    mov rdx, [r14 + DNS_count]
    lea rcx, [r12 + ENP_pairs]
    mov r8, rdx
    call doc_selections_apply
    mov [r12 + ENP_error], rdx
    test eax, eax
    jz .Len_free
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp .Len_free
.Len_payload_error:
    mov edx, r8d
    jmp .Len_error
.Len_input:
    mov edx, 1
    jmp .Len_error
.Len_readonly:
    mov edx, 3
    jmp .Len_error
.Len_limit:
    mov edx, 2
    jmp .Len_error
.Len_busy:
    mov edx, 4
.Len_error:
    test r12, r12
    jz .Len_return_error
    mov [r12 + ENP_error], rdx
.Len_free:
    xor r13d, r13d
1:  cmp r13, [r12 + ENP_built]
    jae 2f
    mov rdi, [r12 + r13*8 + ENP_payloads]
    call mem_free
    inc r13
    jmp 1b
2:  mov rdi, [r12 + ENP_ranges]
    call mem_free
    mov r13, [r12 + ENP_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Len_return_error:
    xor eax, eax
    EPILOGUE

# editor_newline_payload(doc, validated start,end, byte budget, shared scan counter*)
# -> owned rax, rdx length, rcx caret offset, r8 error, r9 bytes before start the text replaces too.
# No document mutation. The text is the language configuration's (lc_newline, langconf.s), as on
# the single-cursor path.
FN editor_newline_payload
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rcx
    mov [rsp + 8], r8
    test rcx, rcx
    jz .Lenp_limit
    cmp rcx, DOC_MULTI_BYTES_MAX
    ja .Lenp_limit
    call lc_newline             # rdi doc, rsi start, rdx end
    mov r12, rax
    mov r13, rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    # the bytes read count against the shared scan budget
    mov rcx, [rsp + 8]
    mov rax, [rip + lc_scanned]
    cmp [rcx], rax
    jb .Lenp_limit
    sub [rcx], rax
    cmp r13, [rsp]
    ja .Lenp_limit              # the text must fit the budget
    lea rdi, [r13 + 1]
    call mem_alloc
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, r14
    mov rdx, r13
    mov rcx, [rsp + 16]
    xor r8d, r8d
    mov r9, [rsp + 24]
    EPILOGUE
.Lenp_limit:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    mov r8d, 2
    xor r9d, r9d
    EPILOGUE
