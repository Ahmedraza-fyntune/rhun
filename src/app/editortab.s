# Pure bounded helpers for per-selection Tab and shared line indentation.
.include "rhun.inc"
.text

# Count each source-byte examination before reading. -> eax byte, r8 success.
# rdx points to the remaining shared scan allowance; document and gap stay unchanged.
editor_tab_byte:
    xor r8d, r8d
    cmp qword ptr [rdx], 0
    je 1f
    dec qword ptr [rdx]
    mov r8d, 1
    jmp doc_byte
1:  xor eax, eax
    ret

# (doc, byte position, tab width1..16, scan allowance*) -> column, edx error.
# Uses the same UTF8 decoder and width rules as doc_col_of, without DOC scratch.
FN editor_tab_column
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    xor r15d, r15d
    test rcx, rcx
    jz .Letc_input
    test rdx, rdx
    jz .Letc_input
    cmp rdx, 16
    ja .Letc_input
    test rbx, rbx
    jz .Letc_input
    call doc_len
    cmp r12, rax
    ja .Letc_input
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r13, rax
.Letc_next:
    cmp r13, r12
    jae .Letc_good
    mov r14, r12
    sub r14, r13
    cmp r14, 4
    jbe 1f
    mov r14d, 4
1:  xor ecx, ecx
2:  cmp rcx, r14
    jae 3f
    mov rdi, rbx
    lea rsi, [r13 + rcx]
    mov rdx, [rsp + 16]
    call editor_tab_byte
    test r8d, r8d
    jz .Letc_limit
    mov [rsp + rcx], al
    inc rcx
    jmp 2b
3:  cmp byte ptr [rsp], 9
    je .Letc_tab
    mov rdi, rsp
    mov rsi, r14
    call utf8_decode
    add r13, rdx
    mov edi, eax
    call cp_width
    add r15, rax
    jmp .Letc_next
.Letc_tab:
    mov rax, r15
    xor edx, edx
    div qword ptr [rsp + 8]
    mov rax, [rsp + 8]
    sub rax, rdx
    add r15, rax
    inc r13
    jmp .Letc_next
.Letc_good:
    mov rax, r15
    xor edx, edx
    EPILOGUE
.Letc_input:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Letc_limit:
    xor eax, eax
    mov edx, 2
    EPILOGUE

# (doc, line start, width, scan*) -> leading prefix bytes to remove, edx error.
# At most width spaces, or the prefix through the first TAB before that boundary.
FN editor_tab_outdent
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor r15d, r15d
    test rbx, rbx
    jz .Leto_input
    test r14, r14
    jz .Leto_input
    test r13, r13
    jz .Leto_input
    cmp r13, 16
    ja .Leto_input
    call doc_len
    cmp r12, rax
    ja .Leto_input
    mov [rsp], rax
1:  cmp r15, r13
    jae .Leto_good
    lea rsi, [r12 + r15]
    cmp rsi, [rsp]
    jae .Leto_good
    mov rdi, rbx
    mov rdx, r14
    call editor_tab_byte
    test r8d, r8d
    jz .Leto_limit
    cmp eax, 9
    je 2f
    cmp eax, ' '
    jne .Leto_good
    inc r15
    jmp 1b
2:  inc r15
.Leto_good:
    mov rax, r15
    xor edx, edx
    EPILOGUE
.Leto_input:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Leto_limit:
    xor eax, eax
    mov edx, 2
    EPILOGUE

# (plan, source line, allow-empty) -> success,error. Shared lines occur only once.
FN editor_tab_add_line
    xor ecx, ecx
1:  cmp rcx, [rdi + ETB_nlines]
    jae 2f
    mov rax, rcx
    shl rax, 4
    lea rax, [rdi + rax + ETB_lines]
    cmp rsi, [rax + ETL_line]
    je 3f
    inc rcx
    jmp 1b
2:  cmp rcx, DOC_BATCH_EDITS_MAX
    jae 4f
    mov rax, rcx
    shl rax, 4
    lea rax, [rdi + rax + ETB_lines]
    mov [rax + ETL_line], rsi
    inc qword ptr [rdi + ETB_nlines]
3:  or [rax + ETL_empty], rdx
    mov eax, 1
    xor edx, edx
    ret
4:  xor eax, eax
    mov edx, 2
    ret

# (plan,start,end,length,kind) -> inline candidate,error; caller fills counted payload.
FN editor_tab_add_candidate
    cmp rsi, rdx
    ja 4f
    cmp rcx, 32
    ja 4f
    cmp r8, 1
    ja 4f
    test rcx, rcx
    jnz 1f
    cmp rsi, rdx
    je 4f
1:  mov rax, [rdi + ETB_ncandidates]
    cmp rax, ETB_CANDIDATES_MAX
    jae 5f
    imul r9, rax, ETC_SIZE
    lea r9, [rdi + r9 + ETB_candidates]
    mov [rdi + rax*8 + ETB_order], r9
    inc qword ptr [rdi + ETB_ncandidates]
    mov [r9 + ETC_start], rsi
    mov [r9 + ETC_end], rdx
    mov [r9 + ETC_len], rcx
    mov [r9 + ETC_kind], r8
    mov qword ptr [r9 + ETC_output], -1
    mov rax, r9
    xor edx, edx
    ret
4:  xor eax, eax
    mov edx, 1
    ret
5:  xor eax, eax
    mov edx, 2
    ret

# Stable pointer sort: source start, end, then line prefix before replacement.
editor_tab_sort:
    mov rsi, [rdi + ETB_ncandidates]
    cmp rsi, 2
    jb 9f
    dec rsi
1:  xor ecx, ecx
2:  mov r8, [rdi + rcx*8 + ETB_order]
    mov r9, [rdi + rcx*8 + ETB_order + 8]
    mov rax, [r8 + ETC_start]
    cmp rax, [r9 + ETC_start]
    ja 3f
    jb 4f
    mov rax, [r8 + ETC_end]
    cmp rax, [r9 + ETC_end]
    ja 3f
    jb 4f
    mov rax, [r8 + ETC_kind]
    cmp rax, [r9 + ETC_kind]
    jbe 4f
3:  mov [rdi + rcx*8 + ETB_order], r9
    mov [rdi + rcx*8 + ETB_order + 8], r8
4:  inc rcx
    cmp rcx, rsi
    jb 2b
    dec rsi
    jnz 1b
9:  ret

# Compose same-position prefix/replacement effects; produce disjoint owned DBEs.
FN editor_tab_compact
    PROLOGUE 16
    mov rbx, rdi
    call editor_tab_sort
    mov qword ptr [rbx + ETB_nedits], 0
    mov qword ptr [rbx + ETB_bytes], 0
    xor r12d, r12d
    xor r15d, r15d
.Letp_next:
    cmp r12, [rbx + ETB_ncandidates]
    jae .Letp_budget
    mov r13, [rbx + r12*8 + ETB_order]
    mov rax, [rbx + ETB_nedits]
    test rax, rax
    jz .Letp_append
    dec rax
    mov [rsp], rax
    shl rax, 5
    lea r14, [rbx + rax + ETB_edits]
    mov rcx, [r13 + ETC_start]
    cmp rcx, [r14 + DBE_start]
    je .Letp_same
    cmp rcx, [r14 + DBE_end]
    jb .Letp_input
.Letp_append:
    mov rax, [rbx + ETB_nedits]
    cmp rax, [rbx + ETB_editlimit]
    jae .Letp_limit
    cmp rax, DOC_BATCH_EDITS_MAX
    jae .Letp_limit
    mov [r13 + ETC_output], rax
    shl rax, 5
    lea r14, [rbx + rax + ETB_edits]
    lea rcx, [rbx + rax + ETB_payloads]
    mov [r14 + DBE_text], rcx
    mov rdi, rcx
    lea rsi, [r13 + ETC_data]
    mov rdx, [r13 + ETC_len]
    call memcpy
    mov rax, [r13 + ETC_start]
    mov [r14 + DBE_start], rax
    mov rax, [r13 + ETC_end]
    mov [r14 + DBE_end], rax
    mov rax, [r13 + ETC_len]
    mov [r14 + DBE_len], rax
    inc qword ptr [rbx + ETB_nedits]
    jmp .Letp_advance
.Letp_same:
    # Only one line prefix plus one independent selection replacement may coincide.
    cmp qword ptr [r15 + ETC_kind], 0
    jne .Letp_input
    cmp qword ptr [r13 + ETC_kind], 1
    jne .Letp_input
    mov rax, [r14 + DBE_start]
    cmp rax, [r14 + DBE_end]
    jne .Letp_input
    cmp rax, [r13 + ETC_end]
    jne .Letp_compose
    mov rax, [r13 + ETC_len]
    cmp rax, [r14 + DBE_len]
    jne .Letp_input
    mov rdi, [r14 + DBE_text]
    lea rsi, [r13 + ETC_data]
    mov rdx, rax
    call memeq
    test eax, eax
    jz .Letp_input
    jmp .Letp_link
.Letp_compose:
    mov rdx, [r13 + ETC_len]
    mov rax, [r14 + DBE_len]
    add rax, rdx
    cmp rax, 32
    ja .Letp_input
    mov rdi, [r14 + DBE_text]
    add rdi, [r14 + DBE_len]
    lea rsi, [r13 + ETC_data]
    call memcpy
    mov rax, [r13 + ETC_end]
    mov [r14 + DBE_end], rax
    mov rax, [r13 + ETC_len]
    add [r14 + DBE_len], rax
.Letp_link:
    mov rax, [rsp]
    mov [r13 + ETC_output], rax
.Letp_advance:
    mov r15, r13
    inc r12
    jmp .Letp_next
.Letp_budget:
    xor ecx, ecx
    xor eax, eax
1:  cmp rcx, [rbx + ETB_nedits]
    jae 2f
    mov rdx, rcx
    shl rdx, 5
    add rax, [rbx + rdx + ETB_edits + DBE_len]
    cmp rax, [rbx + ETB_limit]
    ja .Letp_limit
    inc rcx
    jmp 1b
2:  mov [rbx + ETB_bytes], rax
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Letp_input:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Letp_limit:
    xor eax, eax
    mov edx, 2
    EPILOGUE

# Map an original endpoint, rdx=1 for left insertion affinity. Prepared DBEs are disjoint.
FN editor_tab_map
    xor ecx, ecx
    xor r8d, r8d
1:  cmp rcx, [rdi + ETB_nedits]
    jae 8f
    mov rax, rcx
    shl rax, 5
    lea r9, [rdi + rax + ETB_edits]
    cmp rsi, [r9 + DBE_start]
    jb 8f
    mov rax, [r9 + DBE_end]
    cmp rax, [r9 + DBE_start]
    jne 3f
    cmp rsi, rax
    jne 4f
    test edx, edx
    jnz 8f
4:  add r8, [r9 + DBE_len]
    jmp 7f
3:  cmp rsi, rax
    jae 5f
    mov rsi, [r9 + DBE_start]
    jmp 8f
5:  sub rax, [r9 + DBE_start]
    sub r8, rax
    add r8, [r9 + DBE_len]
7:  inc rcx
    jmp 1b
8:  lea rax, [rsi + r8]
    ret

# Normalize each range's Tab behavior and collect independent line intervals.
editor_tab_prepare_ranges:
    PROLOGUE 32
    mov r12, rdi
    mov rbx, [r12 + ETB_doc]
    xor r13d, r13d
.Letr_next:
    mov rax, [r12 + ETB_ranges]
    cmp r13, [rax + DNS_count]
    jae .Letr_good
    mov r14, r13
    shl r14, 5
    lea r14, [rax + r14 + DNS_ranges]
    mov [r12 + r13*8 + ETB_rangeorder], r14
    mov rdi, rbx
    mov rsi, [r14 + DMR_index]
    call doc_selections_get
    cmp rax, rdx
    setae al
    movzx eax, al
    mov [r12 + r13*8 + ETB_direction], rax
    mov rdi, rbx
    mov rsi, [r14 + DMR_start]
    call doc_line_of
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, [r14 + DMR_end]
    call doc_line_of
    mov [rsp + 8], rax
    cmp qword ptr [r12 + ETB_mode], 0
    jne .Letr_block
    mov rax, [r14 + DMR_start]
    cmp rax, [r14 + DMR_end]
    je .Letr_replace
    mov rax, [rsp]
    cmp rax, [rsp + 8]
    jne .Letr_block
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, [r14 + DMR_start]
    jne .Letr_replace
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_line_end
    cmp rax, [r14 + DMR_end]
    jne .Letr_replace
.Letr_block:
    mov qword ptr [r12 + r13*8 + ETB_class], 1
    mov rax, [rsp + 8]
    cmp rax, [rsp]
    je 1f
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, [r14 + DMR_end]
    jne 1f
    dec qword ptr [rsp + 8]
1:  mov r15, [rsp]
    cmp r15, [rsp + 8]
    sete al
    movzx eax, al
    mov [rsp + 16], rax
2:  mov rdi, r12
    mov rsi, r15
    mov rdx, [rsp + 16]
    call editor_tab_add_line
    test eax, eax
    jz .Letr_return
    inc r15
    cmp r15, [rsp + 8]
    jbe 2b
    jmp .Letr_advance
.Letr_replace:
    mov r15d, 1
    cmp qword ptr [r12 + ETB_spaces], 0
    je 3f
    mov rdi, rbx
    mov rsi, [r14 + DMR_start]
    mov rdx, [r12 + ETB_width]
    lea rcx, [r12 + ETB_scan]
    call editor_tab_column
    test edx, edx
    jnz .Letr_error
    xor edx, edx
    div qword ptr [r12 + ETB_width]
    mov r15, [r12 + ETB_width]
    sub r15, rdx
3:  mov rdi, r12
    mov rsi, [r14 + DMR_start]
    mov rdx, [r14 + DMR_end]
    mov rcx, r15
    mov r8d, 1
    call editor_tab_add_candidate
    test rax, rax
    jz .Letr_error
    mov [r12 + r13*8 + ETB_replacements], rax
    lea rdi, [rax + ETC_data]
    mov esi, ' '
    cmp qword ptr [r12 + ETB_spaces], 0
    jne 4f
    mov esi, 9
4:  mov rdx, r15
    call memset
.Letr_advance:
    inc r13
    jmp .Letr_next
.Letr_good:
    mov eax, 1
    xor edx, edx
.Letr_return:
    EPILOGUE
.Letr_error:
    xor eax, eax
    EPILOGUE

# Emit each shared line prefix once, with its unioned empty-line policy.
editor_tab_prepare_lines:
    PROLOGUE 16
    mov r12, rdi
    mov rbx, [r12 + ETB_doc]
    xor r13d, r13d
.Letl_next:
    cmp r13, [r12 + ETB_nlines]
    jae .Letl_good
    mov rax, r13
    shl rax, 4
    mov rsi, [r12 + rax + ETB_lines + ETL_line]
    mov rax, [r12 + rax + ETB_lines + ETL_empty]
    mov [rsp], rax
    mov [rsp + 8], rsi
    mov rdi, rbx
    call doc_line_start
    mov r14, rax
    cmp qword ptr [r12 + ETB_mode], -1
    je .Letl_outdent
    cmp qword ptr [rsp], 0
    jne 1f
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call doc_line_end
    cmp rax, r14
    je .Letl_advance
1:  mov r15d, 1
    cmp qword ptr [r12 + ETB_spaces], 0
    je 2f
    mov r15, [r12 + ETB_width]
2:  mov rdi, r12
    mov rsi, r14
    mov rdx, r14
    mov rcx, r15
    xor r8d, r8d
    call editor_tab_add_candidate
    test rax, rax
    jz .Letl_error
    lea rdi, [rax + ETC_data]
    mov esi, ' '
    cmp qword ptr [r12 + ETB_spaces], 0
    jne 3f
    mov esi, 9
3:  mov rdx, r15
    call memset
    jmp .Letl_advance
.Letl_outdent:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r12 + ETB_width]
    lea rcx, [r12 + ETB_scan]
    call editor_tab_outdent
    test edx, edx
    jnz .Letl_error
    test rax, rax
    jz .Letl_advance
    mov rdi, r12
    mov rsi, r14
    lea rdx, [r14 + rax]
    xor ecx, ecx
    xor r8d, r8d
    call editor_tab_add_candidate
    test rax, rax
    jz .Letl_error
.Letl_advance:
    inc r13
    jmp .Letl_next
.Letl_good:
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Letl_error:
    xor eax, eax
    EPILOGUE

# Prepare source-order pairs, then restore normalized original selection identity.
editor_tab_finish_pairs:
    PROLOGUE 32
    mov r12, rdi
    mov rbx, [r12 + ETB_doc]
    xor r13d, r13d
.Letf_next:
    mov rax, [r12 + ETB_ranges]
    cmp r13, [rax + DNS_count]
    jae .Letf_order
    mov r14, r13
    shl r14, 5
    lea r14, [rax + r14 + DNS_ranges]
    cmp qword ptr [r12 + r13*8 + ETB_class], 0
    jne .Letf_block
    mov rax, [r12 + r13*8 + ETB_replacements]
    mov rax, [rax + ETC_output]
    shl rax, 5
    lea r14, [r12 + rax + ETB_edits]
    mov rdi, r12
    mov rsi, [r14 + DBE_start]
    mov edx, 1
    call editor_tab_map
    add rax, [r14 + DBE_len]
    mov rdx, rax
    jmp .Letf_store
.Letf_block:
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov rax, [r14 + DMR_start]
    cmp rax, [r14 + DMR_end]
    je 1f
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, [r14 + DMR_start]
    sete al
    movzx eax, al
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, [r14 + DMR_end]
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, [r14 + DMR_end]
    sete al
    movzx eax, al
    mov [rsp + 8], rax
1:  mov rdi, r12
    mov rsi, [r14 + DMR_start]
    mov rdx, [rsp]
    call editor_tab_map
    mov r15, rax
    mov rdi, r12
    mov rsi, [r14 + DMR_end]
    mov rdx, [rsp + 8]
    call editor_tab_map
    mov rdx, r15
    cmp qword ptr [r12 + r13*8 + ETB_direction], 0
    jne .Letf_store
    xchg rax, rdx
.Letf_store:
    mov rcx, r13
    shl rcx, 4
    mov [r12 + rcx + ETB_sourcepairs + DMP_cur], rax
    mov [r12 + rcx + ETB_sourcepairs + DMP_anchor], rdx
    inc r13
    jmp .Letf_next
.Letf_order:
    mov rax, [r12 + ETB_ranges]
    mov rsi, [rax + DNS_count]
    cmp rsi, 2
    jb .Letf_copy
    dec rsi
2:  xor ecx, ecx
3:  mov r8, [r12 + rcx*8 + ETB_rangeorder]
    mov r9, [r12 + rcx*8 + ETB_rangeorder + 8]
    mov rax, [r8 + DMR_index]
    cmp rax, [r9 + DMR_index]
    jbe 4f
    mov [r12 + rcx*8 + ETB_rangeorder], r9
    mov [r12 + rcx*8 + ETB_rangeorder + 8], r8
4:  inc rcx
    cmp rcx, rsi
    jb 3b
    dec rsi
    jnz 2b
.Letf_copy:
    xor ecx, ecx
    mov r8, [r12 + ETB_ranges]
    mov r9, [r8 + DNS_count]
    add r8, DNS_ranges
5:  cmp rcx, r9
    jae 6f
    mov rax, [r12 + rcx*8 + ETB_rangeorder]
    sub rax, r8
    shr rax, 1                # source DMR stride32 -> DMP stride16
    mov rsi, [r12 + rax + ETB_sourcepairs]
    mov rdx, [r12 + rax + ETB_sourcepairs + 8]
    mov rax, rcx
    shl rax, 4
    mov [r12 + rax + ETB_pairs], rsi
    mov [r12 + rax + ETB_pairs + 8], rdx
    inc rcx
    jmp 5b
6:  EPILOGUE

FN editor_multi_tab_ui
    sub rsp, 8
    call editor_multi_tab
    add rsp, 8
    test eax, eax
    jnz 1f
    mov edi, edx
    jmp editor_multi_error
1:  ret

# (active doc, mode0Tab/1Indent/-1Outdent) -> bool,error.
FN editor_multi_tab
    mov edx, DOC_MULTI_BYTES_MAX
    mov ecx, DOC_MULTI_BYTES_MAX
    mov r8d, DOC_BATCH_EDITS_MAX
    jmp editor_multi_tab_limited

# Private deterministic bounds: (doc,mode,insert-byte budget,scan budget,edit limit).
FN editor_multi_tab_limited
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    xor r12d, r12d
    test rbx, rbx
    jz .Letb_input
    cmp rbx, [rip + g_doc]
    jne .Letb_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Letb_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Letb_busy
    cmp rsi, -1
    je 1f
    cmp rsi, 1
    ja .Letb_input
1:  mov eax, [rip + g_tab_width]
    dec eax
    cmp eax, 15
    ja .Letb_input
    cmp dword ptr [rip + g_insert_spaces], 1
    ja .Letb_input
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Letb_limit
    cmp rcx, DOC_MULTI_BYTES_MAX
    ja .Letb_limit
    cmp r8, DOC_BATCH_EDITS_MAX
    ja .Letb_limit
    mov edi, ETB_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + ETB_doc], rbx
    mov rcx, [rsp]
    mov [rax + ETB_mode], rcx
    mov ecx, [rip + g_tab_width]
    mov [rax + ETB_width], rcx
    mov ecx, [rip + g_insert_spaces]
    mov [rax + ETB_spaces], rcx
    mov rcx, [rsp + 8]
    mov [rax + ETB_limit], rcx
    mov rcx, [rsp + 16]
    mov [rax + ETB_scan], rcx
    mov rcx, [rsp + 24]
    mov [rax + ETB_editlimit], rcx
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Letb_input
    mov [r12 + ETB_ranges], rax
    mov rdi, r12
    call editor_tab_prepare_ranges
    test eax, eax
    jz .Letb_error
    mov rdi, r12
    call editor_tab_prepare_lines
    test eax, eax
    jz .Letb_error
    mov rdi, r12
    call editor_tab_compact
    test eax, eax
    jz .Letb_error
    cmp qword ptr [r12 + ETB_nedits], 0
    je .Letb_free
    mov rdi, r12
    call editor_tab_finish_pairs
    mov rdi, rbx
    lea rsi, [r12 + ETB_edits]
    mov rdx, [r12 + ETB_nedits]
    lea rcx, [r12 + ETB_pairs]
    mov rax, [r12 + ETB_ranges]
    mov r8, [rax + DNS_count]
    call doc_selections_apply
    test eax, eax
    jz .Letb_error
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp .Letb_free
.Letb_input:
    mov edx, 1
    jmp .Letb_error
.Letb_limit:
    mov edx, 2
    jmp .Letb_error
.Letb_readonly:
    mov edx, 3
    jmp .Letb_error
.Letb_busy:
    mov edx, 4
.Letb_error:
    test r12, r12
    jz .Letb_return_error
    mov [r12 + ETB_error], rdx
.Letb_free:
    mov rdi, [r12 + ETB_ranges]
    call mem_free
    mov r13, [r12 + ETB_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Letb_return_error:
    xor eax, eax
    EPILOGUE
