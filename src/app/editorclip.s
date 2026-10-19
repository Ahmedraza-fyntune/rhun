# Owned multi-selection clipboard planning. No document or platform writes during preparation.
.include "rhun.inc"
.text
FN editor_clip_plan_new
    mov edx, DOC_MULTI_BYTES_MAX
    jmp editor_clip_plan_new_limited
FN editor_clip_plan_new_limited
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    xor r12d, r12d
    test rbx, rbx
    jz .Lcp_input
    cmp rsi, 1
    ja .Lcp_input
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Lcp_limit
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Lcp_busy
    test rsi, rsi
    jz 1f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lcp_readonly
1:  mov edi, ECP_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + ECP_doc], rbx
    mov rcx, [rsp]
    mov [rax + ECP_cut], rcx
    mov rcx, [rsp + 8]
    mov [rax + ECP_limit], rcx
    mov qword ptr [rax + ECP_lastline], -1
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Lcp_input
    mov [r12 + ECP_dns], rax
    mov edi, ECM_SIZE
    call mem_alloc
    mov [r12 + ECP_metadata], rax
    xor r13d, r13d
.Lcp_measure:
    mov rax, [r12 + ECP_dns]
    cmp r13, [rax + DNS_count]
    jae .Lcp_copy_begin
    mov r14, r13
    shl r14, 5
    add r14, rax
    add r14, DNS_ranges
    mov r15, r13
    shl r15, 5
    add r15, r12
    add r15, ECP_cuts
    mov rdi, r15
    mov rsi, r14
    mov edx, DMR_SIZE
    call memcpy
    mov qword ptr [rsp + 16], 0
    mov rax, [r14 + DMR_start]
    mov rdx, [r14 + DMR_end]
    cmp rax, rdx
    jne .Lcp_piece
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    mov [rsp + 24], rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov [r15 + DMR_start], rax
    mov rdi, rbx
    mov rsi, [rsp + 24]
    call doc_line_end
    mov [r15 + DMR_end], rax
    mov rcx, [rsp + 24]
    inc rcx
    cmp rcx, [rbx + DOC_nlines]
    jae 1f
    inc qword ptr [r15 + DMR_end]
    jmp 2f
1:  cmp qword ptr [r15 + DMR_start], 0
    je 2f
    dec qword ptr [r15 + DMR_start]
2:  mov rcx, [rsp + 24]
    cmp rcx, [r12 + ECP_lastline]
    je .Lcp_next
    mov [r12 + ECP_lastline], rcx
    # Copy starts at the line, while last-line deletion may include its preceding LF.
    mov rdi, rbx
    mov rsi, rcx
    call doc_line_start
    mov rdx, [r15 + DMR_end]
    mov rcx, [rsp + 24]
    inc rcx
    cmp rcx, [rbx + DOC_nlines]
    jae 3f
    dec rdx
3:  mov qword ptr [rsp + 16], 1
.Lcp_piece:
    mov rcx, [r12 + ECP_npieces]
    shl rcx, 5
    lea r14, [r12 + rcx + ECP_pieces]
    mov [r14 + ECR_start], rax
    mov [r14 + ECR_end], rdx
    mov rcx, [rsp + 16]
    mov [r14 + ECR_append], rcx
    sub rdx, rax
    add rdx, rcx
    jc .Lcp_limit
    mov r15, [r12 + ECP_metadata]
    mov rax, [r15 + ECM_total]
    cmp qword ptr [r12 + ECP_npieces], 0
    je 4f
    inc rax
4:  mov rcx, rax
    add rcx, rdx
    jc .Lcp_limit
    cmp rcx, [r12 + ECP_limit]
    ja .Lcp_limit
    mov [r15 + ECM_total], rcx
    mov rcx, [r12 + ECP_npieces]
    shl rcx, 4
    lea rcx, [r15 + rcx + ECM_segments]
    mov [rcx + ECS_offset], rax
    mov [rcx + ECS_len], rdx
    inc qword ptr [r12 + ECP_npieces]
.Lcp_next:
    inc r13
    jmp .Lcp_measure
.Lcp_copy_begin:
    mov rax, [r12 + ECP_npieces]
    mov r15, [r12 + ECP_metadata]
    mov [r15 + ECM_count], rax
    cmp rax, 1
    jne 1f
    mov rax, [r12 + ECP_pieces + ECR_append]
    mov [r12 + ECP_line], rax
1:  lea rdi, [r12 + ECP_text]
    mov rsi, [r15 + ECM_total]
    call sb_reserve
    xor r13d, r13d
.Lcp_copy:
    cmp r13, [r12 + ECP_npieces]
    jae .Lcp_copy_done
    mov r14, r13
    shl r14, 5
    lea r14, [r12 + r14 + ECP_pieces]
    mov rcx, [r12 + ECP_text + SB_ptr]
    add rcx, [r12 + ECP_text + SB_len]
    test r13, r13
    jz 1f
    mov byte ptr [rcx], 10
    inc rcx
    inc qword ptr [r12 + ECP_text + SB_len]
1:  mov rdi, rbx
    mov rsi, [r14 + ECR_start]
    mov rdx, [r14 + ECR_end]
    sub rdx, rsi
    call doc_copy
    mov rax, [r14 + ECR_end]
    sub rax, [r14 + ECR_start]
    add [r12 + ECP_text + SB_len], rax
    cmp qword ptr [r14 + ECR_append], 0
    je 2f
    mov rax, [r12 + ECP_text + SB_ptr]
    add rax, [r12 + ECP_text + SB_len]
    mov byte ptr [rax], 10
    inc qword ptr [r12 + ECP_text + SB_len]
2:  inc r13
    jmp .Lcp_copy
.Lcp_copy_done:
    cmp qword ptr [r12 + ECP_cut], 0
    je .Lcp_done
    mov rax, [r12 + ECP_dns]
    mov rsi, [rax + DNS_count]
    lea rdi, [r12 + ECP_cuts]
    xor edx, edx
    call doc_ranges_sort
    xor r13d, r13d
    mov r14d, 1
.Lcp_union:
    mov rax, [r12 + ECP_dns]
    cmp r14, [rax + DNS_count]
    jae .Lcp_unioned
    mov rdi, r13
    shl rdi, 5
    lea rdi, [r12 + rdi + ECP_cuts]
    mov rsi, r14
    shl rsi, 5
    lea rsi, [r12 + rsi + ECP_cuts]
    mov rax, [rsi + DMR_start]
    cmp rax, [rdi + DMR_end]
    ja .Lcp_separate
    mov rax, [rsi + DMR_end]
    cmp rax, [rdi + DMR_end]
    jbe 1f
    mov [rdi + DMR_end], rax
1:  mov rax, [rsi + DMR_index]
    cmp rax, [rdi + DMR_index]
    jae 2f
    mov [rdi + DMR_index], rax
2:  inc r14
    jmp .Lcp_union
.Lcp_separate:
    inc r13
    mov rdi, r13
    shl rdi, 5
    lea rdi, [r12 + rdi + ECP_cuts]
    mov edx, DMR_SIZE
    call memmove
    inc r14
    jmp .Lcp_union
.Lcp_unioned:
    inc r13
    mov [r12 + ECP_ncuts], r13
    xor r13d, r13d
    xor r14d, r14d
.Lcp_delete:
    cmp r13, [r12 + ECP_ncuts]
    jae .Lcp_outputs
    mov r15, r13
    shl r15, 5
    lea r15, [r12 + r15 + ECP_cuts]
    mov rax, [r15 + DMR_start]
    mov rcx, rax
    sub rcx, r14
    mov [r15 + DMR_caret], rcx
    mov rdx, [r15 + DMR_end]
    cmp rax, rdx
    je 1f
    mov rcx, [r12 + ECP_nedits]
    shl rcx, 5
    lea rcx, [r12 + rcx + ECP_edits]
    mov [rcx + DBE_start], rax
    mov [rcx + DBE_end], rdx
    inc qword ptr [r12 + ECP_nedits]
    sub rdx, rax
    add r14, rdx
1:  inc r13
    jmp .Lcp_delete
.Lcp_outputs:
    lea rdi, [r12 + ECP_cuts]
    mov rsi, [r12 + ECP_ncuts]
    mov edx, DMR_index
    call doc_ranges_sort
    xor ecx, ecx
1:  cmp rcx, [r12 + ECP_ncuts]
    jae .Lcp_done
    mov rax, rcx
    shl rax, 5
    mov rax, [r12 + rax + ECP_cuts + DMR_caret]
    mov rdx, rcx
    shl rdx, 4
    mov [r12 + rdx + ECP_pairs + DMP_cur], rax
    mov [r12 + rdx + ECP_pairs + DMP_anchor], rax
    inc rcx
    jmp 1b
.Lcp_done:
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Lcp_input:
    mov edx, 1
    jmp .Lcp_error
.Lcp_limit:
    mov edx, 2
    jmp .Lcp_error
.Lcp_readonly:
    mov edx, 3
    jmp .Lcp_error
.Lcp_busy:
    mov edx, 4
.Lcp_error:
    mov r13, rdx
    mov rdi, r12
    call editor_clip_plan_free
    xor eax, eax
    mov rdx, r13
    EPILOGUE

FN editor_clip_plan_free
    PROLOGUE
    mov rbx, rdi
    test rdi, rdi
    jz 9f
    mov rdi, [rbx + ECP_dns]
    call mem_free
    mov rdi, [rbx + ECP_metadata]
    call mem_free
    lea rdi, [rbx + ECP_text]
    call sb_free
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

.bss
.p2align 3
clip_metadata: .quad 0
.text
FN editor_clip_segments_clear
    mov rdi, [rip + clip_metadata]
    mov qword ptr [rip + clip_metadata], 0
    jmp mem_free
FN editor_clip_segments_adopt
    PROLOGUE
    mov rbx, rdi
    call editor_clip_segments_clear
    mov [rip + clip_metadata], rbx
    EPILOGUE

# Observation invalidates permanently on a mismatch, without freeing delivered text.
FN ed_clip_observe
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call clip_delivery_get
    test rax, rax
    jnz 1f
    mov rdi, rbx
    mov rsi, r12
    call ed_clip_matches
    test eax, eax
    jnz 9f
1:  call editor_clip_segments_clear
    mov dword ptr [rip + g_clip_line], 0
    xor eax, eax
9:  EPILOGUE
FN editor_clip_segments_get
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call clip_delivery_get
    test rax, rax
    jz 1f
    mov rax, [rax + CWB_metadata]
    jmp 9f
1:  mov rdi, rbx
    mov rsi, r12
    call ed_clip_observe
    test eax, eax
    jz 9f
    mov rax, [rip + clip_metadata]
9:  EPILOGUE

# Trusted guard callback. The platform write cannot enter document callbacks.
editor_clip_plan_accept:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ECP_text + SB_ptr]
    mov rsi, [rbx + ECP_text + SB_len]
    mov rdx, [rbx + ECP_line]
    mov rcx, [rbx + ECP_metadata]
    call ed_clip_set_metadata
    test eax, eax
    jz 9f
    mov rdi, [rbx + ECP_metadata]
    mov qword ptr [rbx + ECP_metadata], 0
    call editor_clip_segments_adopt
    mov eax, 1
9:  EPILOGUE

FN editor_multi_copy_ui
    call editor_multi_copy
    test eax, eax
    jnz 1f
    jmp editor_clip_failure
1:  ret
FN editor_multi_copy
    PROLOGUE 32
    mov rbx, rdi
    test rdi, rdi
    jz .Lcc_input
    cmp rdi, [rip + g_doc]
    jne .Lcc_input
    call editor_clip_plan_new
    test rax, rax
    jz .Lcc_return
    mov r12, rax
    cmp qword ptr [rax + ECP_cut], 0
    jne .Lcc_cut
    mov rdi, r12
    call editor_clip_plan_accept
    xor edx, edx
    test eax, eax
    jnz .Lcc_free
    mov edx, 5
    jmp .Lcc_free
.Lcc_cut:
    lea rax, [rip + editor_clip_plan_accept]
    mov [rsp + GDC_callback], rax
    mov [rsp + GDC_context], r12
    mov rdi, rbx
    lea rsi, [r12 + ECP_edits]
    mov rdx, [r12 + ECP_nedits]
    lea rcx, [r12 + ECP_pairs]
    mov r8, [r12 + ECP_ncuts]
    lea r9, [rsp]
    call doc_selections_apply_guarded
    test eax, eax
    jz .Lcc_free
    call ed_touch
    mov eax, 1
    xor edx, edx
.Lcc_free:
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, r12
    call editor_clip_plan_free
    mov rax, [rsp + 16]
    mov rdx, [rsp + 24]
.Lcc_return:
    EPILOGUE
.Lcc_input:
    xor eax, eax
    mov edx, 1
    EPILOGUE
