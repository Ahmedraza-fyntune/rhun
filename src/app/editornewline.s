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
# -> owned rax, rdx length, rcx caret offset, r8 error. No document mutation.
FN editor_newline_payload
    PROLOGUE 96
    mov rbx, rdi
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov [rsp + 16], rsi
    mov [rsp + 24], rdx
    mov qword ptr [rsp + 40], 0  # leading indent bytes
    mov qword ptr [rsp + 48], 0  # added indentation unit bytes
    mov qword ptr [rsp + 56], 0  # matching closer, or0
    test rcx, rcx
    jz .Lenp_limit
    cmp rcx, DOC_MULTI_BYTES_MAX
    ja .Lenp_limit
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov [rsp + 32], rax
    mov r12, rax
.Lenp_indent:
    cmp r12, [rsp + 16]
    jae .Lenp_context
    call .Lenp_scan
    test eax, eax
    jz .Lenp_limit
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    cmp eax, ' '
    je 1f
    cmp eax, 9
    jne .Lenp_context
1:  inc qword ptr [rsp + 40]
    mov rax, [rsp + 40]
    cmp rax, [rsp]
    jae .Lenp_limit           # LF must also fit
    inc r12
    jmp .Lenp_indent
.Lenp_context:
    mov r12, [rsp + 16]
1:  cmp r12, [rsp + 32]
    jbe .Lenp_size
    dec r12
    call .Lenp_scan
    test eax, eax
    jz .Lenp_limit
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    cmp eax, ' '
    je 1b
    cmp eax, 9
    je 1b
    mov r13d, '}'
    cmp eax, '{'
    je .Lenp_unit
    mov r13d, ')'
    cmp eax, '('
    je .Lenp_unit
    mov r13d, ']'
    cmp eax, '['
    je .Lenp_unit
    cmp eax, ':'
    jne .Lenp_size
    mov rdi, rbx
    call doc_language
    test rax, rax
    jz .Lenp_size
    test qword ptr [rax + GR_flags], GF_COLON
    jz .Lenp_size
    xor r13d, r13d
.Lenp_unit:
    mov eax, 1
    cmp dword ptr [rip + g_insert_spaces], 0
    je 1f
    mov eax, [rip + g_tab_width]
1:  mov [rsp + 48], rax
    test r13d, r13d
    jz .Lenp_size
    mov rdi, rbx
    mov rsi, [rsp + 24]
    call doc_byte
    cmp eax, r13d
    jne .Lenp_size
    mov [rsp + 56], r13
.Lenp_size:
    mov r12, [rsp + 40]
    inc r12
    add r12, [rsp + 48]
    mov [rsp + 72], r12       # caret offset
    cmp qword ptr [rsp + 56], 0
    je 1f
    inc r12
    add r12, [rsp + 40]
1:  cmp r12, [rsp]
    ja .Lenp_limit
    mov rdi, r12
    call mem_alloc
    mov r14, rax
    mov byte ptr [r14], 10
    mov rdi, rbx
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 40]
    lea rcx, [r14 + 1]
    call doc_copy
    lea rdi, [r14 + 1]
    add rdi, [rsp + 40]
    mov esi, ' '
    cmp dword ptr [rip + g_insert_spaces], 0
    jne 2f
    mov esi, 9
2:  mov rdx, [rsp + 48]
    call memset
    cmp qword ptr [rsp + 56], 0
    je 3f
    mov rax, [rsp + 72]
    mov byte ptr [r14 + rax], 10
    lea rcx, [r14 + rax + 1]
    mov rdi, rbx
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 40]
    call doc_copy
3:  mov rax, r14
    mov rdx, r12
    mov rcx, [rsp + 72]
    xor r8d, r8d
    EPILOGUE
.Lenp_limit:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    mov r8d, 2
    EPILOGUE

# The call adds8 to the caller's frame offsets. Only rax/rcx are clobbered.
.Lenp_scan:
    mov rcx, [rsp + 16]
    xor eax, eax
    cmp qword ptr [rcx], 0
    je 1f
    dec qword ptr [rcx]
    mov eax, 1
1:  ret
