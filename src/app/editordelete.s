# Expand and merge deletion ranges without changing the live selections during planning.
.include "rhun.inc"
.text

FN editor_multi_delete_ui
    call editor_multi_delete
    test eax, eax
    jnz 1f
    mov edi, edx
    jmp editor_multi_error
1:  ret

# editor_multi_delete(active doc, direction0back/1forward, word0/1) -> bool,error.
FN editor_multi_delete
    mov ecx, DOC_MULTI_BYTES_MAX
    jmp editor_multi_delete_limited

# The private limited entry permits deterministic scan exhaustion tests.
FN editor_multi_delete_limited
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    xor r12d, r12d
    test rbx, rbx
    jz .Led_input
    cmp rbx, [rip + g_doc]
    jne .Led_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Led_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Led_busy
    cmp rsi, 1
    ja .Led_input
    cmp rdx, 1
    ja .Led_input
    cmp rcx, DOC_MULTI_BYTES_MAX
    ja .Led_limit
    mov edi, EDP_SIZE
    call mem_alloc
    mov r12, rax
    mov rcx, [rsp]
    mov [rax + EDP_direction], rcx
    add rcx, EK_BACK
    mov [rax + EDP_kind], rcx
    mov rcx, [rsp + 8]
    mov [rax + EDP_word], rcx
    mov rcx, [rsp + 16]
    mov [rax + EDP_scan], rcx
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Led_input
    mov [r12 + EDP_ranges], rax
    lea rdi, [rax + DNS_ranges]
    mov rsi, [rax + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    xor r13d, r13d
.Led_expand:
    mov rax, [r12 + EDP_ranges]
    cmp r13, [rax + DNS_count]
    jae .Led_normalize
    mov rcx, r13
    shl rcx, 5
    lea rcx, [rax + rcx + DNS_ranges]
    mov rdi, rbx
    mov rsi, [rcx + DMR_start]
    mov rdx, [rcx + DMR_end]
    mov rcx, [r12 + EDP_direction]
    mov r8, [r12 + EDP_word]
    lea r9, [r12 + EDP_scan]
    call editor_delete_span
    test r8d, r8d
    jnz .Led_span_error
    mov rcx, r13
    shl rcx, 4
    mov [r12 + rcx + EDP_candidates + DMP_cur], rax
    mov [r12 + rcx + EDP_candidates + DMP_anchor], rdx
    inc r13
    jmp .Led_expand
.Led_normalize:
    mov rdi, rbx
    lea rsi, [r12 + EDP_candidates]
    mov rdx, [rax + DNS_count]
    call doc_ranges_new
    test rax, rax
    jz .Led_input
    mov [r12 + EDP_expanded], rax
    mov r14, rax
    xor r13d, r13d
.Led_plan:
    cmp r13, [r14 + DNS_count]
    jae .Led_order
    mov r15, r13
    shl r15, 5
    lea r15, [r14 + r15 + DNS_ranges]
    mov rax, [r15 + DMR_start]
    mov rcx, rax
    sub rcx, [r12 + EDP_delta]
    mov [r15 + DMR_caret], rcx
    mov rdx, [r15 + DMR_end]
    cmp rax, rdx
    je 1f
    mov rcx, [r12 + EDP_nedits]
    shl rcx, 5
    lea rcx, [r12 + rcx + EDP_edits]
    mov [rcx + DBE_start], rax
    mov [rcx + DBE_end], rdx
    sub rdx, rax
    add [r12 + EDP_delta], rdx
    inc qword ptr [r12 + EDP_nedits]
1:  inc r13
    jmp .Led_plan
.Led_order:
    lea rdi, [r14 + DNS_ranges]
    mov rsi, [r14 + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    xor ecx, ecx
1:  cmp rcx, [r14 + DNS_count]
    jae .Led_apply
    mov rax, rcx
    shl rax, 5
    mov rdx, [r14 + rax + DNS_ranges + DMR_caret]
    mov rax, rcx
    shl rax, 4
    mov [r12 + rax + EDP_pairs + DMP_cur], rdx
    mov [r12 + rax + EDP_pairs + DMP_anchor], rdx
    inc rcx
    jmp 1b
.Led_apply:
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [r12 + EDP_undo], rax
    mov rdi, rbx
    mov rsi, [r12 + EDP_kind]
    call editor_multi_can_join
    test eax, eax
    jz 1f
    or dword ptr [rbx + DOC_flags], DF_GROUP
    mov qword ptr [r12 + EDP_joined], 1
1:  mov rdi, rbx
    lea rsi, [r12 + EDP_edits]
    mov rdx, [r12 + EDP_nedits]
    lea rcx, [r12 + EDP_pairs]
    mov r8, [r14 + DNS_count]
    call doc_selections_apply
    mov [r12 + EDP_error], rdx
    cmp qword ptr [r12 + EDP_joined], 0
    je 2f
    and dword ptr [rbx + DOC_flags], ~DF_GROUP
2:  test eax, eax
    jz .Led_free
    mov rax, [rbx + DOC_undo + VEC_len]
    cmp rax, [r12 + EDP_undo]
    jbe 3f
    mov rax, [r12 + EDP_kind]
    mov [rbx + DOC_lastkind], rax
3:  mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp .Led_free
.Led_span_error:
    mov edx, r8d
    jmp .Led_error
.Led_input:
    mov edx, 1
    jmp .Led_error
.Led_limit:
    mov edx, 2
    jmp .Led_error
.Led_readonly:
    mov edx, 3
    jmp .Led_error
.Led_busy:
    mov edx, 4
.Led_error:
    test r12, r12
    jz .Led_return_error
    mov [r12 + EDP_error], rdx
.Led_free:
    mov rdi, [r12 + EDP_ranges]
    call mem_free
    mov rdi, [r12 + EDP_expanded]
    call mem_free
    mov r13, [r12 + EDP_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Led_return_error:
    xor eax, eax
    EPILOGUE

# editor_delete_span(doc, validated cur,anchor,direction,word,scan counter*)
# -> start,end,r8 error. Selected spans do not expand.
FN editor_delete_span
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], r9
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    cmp r12, r13
    jne .Leds_done
    test r8d, r8d
    jnz .Leds_word
    test ecx, ecx
    jnz .Leds_forward
    test r12, r12
    jz .Leds_done
    call doc_prev_char
    mov r13, rax
    cmp dword ptr [rip + g_insert_spaces], 0
    je .Leds_pair
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    cmp eax, ' '
    jne .Leds_pair
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, rax
    mov r15, rax
.Leds_indent:
    cmp r15, r12
    jae .Leds_tabstop
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rsp]
    call editor_delete_read
    test r8d, r8d
    jnz .Leds_error
    cmp eax, ' '
    jne .Leds_pair
    inc r15
    jmp .Leds_indent
.Leds_tabstop:
    mov rax, r12
    sub rax, r14
    dec rax
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    imul eax, [rip + g_tab_width]
    add rax, r14
    mov r13, rax
    jmp .Leds_done
.Leds_pair:
    cmp dword ptr [rip + cfg_auto_pairs], 0
    je .Leds_done
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    mov r14d, eax
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    mov r15d, eax
    lea rax, [rip + pair_open]
    lea rdx, [rip + pair_close]
    xor ecx, ecx
1:  movzx esi, byte ptr [rax + rcx]
    test esi, esi
    jz .Leds_done
    cmp esi, r14d
    jne 2f
    movzx esi, byte ptr [rdx + rcx]
    cmp esi, r15d
    jne 2f
    inc r12
    jmp .Leds_done
2:  inc ecx
    jmp 1b
.Leds_forward:
    call doc_next_char
    mov r13, rax
    jmp .Leds_done
.Leds_word:
    mov edx, [rsp + 8]
    mov rcx, [rsp]
    call editor_delete_word
    test edx, edx
    jnz .Leds_word_error
    mov r13, rax
.Leds_done:
    mov rax, r12
    mov rdx, r13
    cmp rax, rdx
    jbe 1f
    xchg rax, rdx
1:  xor r8d, r8d
    EPILOGUE
.Leds_word_error:
    mov r8d, edx
.Leds_error:
    xor eax, eax
    xor edx, edx
    EPILOGUE

# A counted byte read. doc_byte's leaf implementation preserves r8.
editor_delete_read:
    cmp qword ptr [rdx], 0
    je 1f
    dec qword ptr [rdx]
    xor r8d, r8d
    jmp doc_byte
1:  xor eax, eax
    mov r8d, 2
    ret

# Native word boundaries with one shared operation-wide byte-scan allowance.
# editor_delete_word(doc,pos,direction,scan*) -> pos,edx error.
FN editor_delete_word
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r15, rcx
    test edx, edx
    jz .Ledw_left
    call doc_len
    mov r13, rax
    cmp r12, r13
    jae .Ledw_done
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
    cmp eax, 10
    jne .Ledw_right_class
    inc r12
    jmp .Ledw_done
.Ledw_right_read:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
.Ledw_right_class:
    mov edi, eax
    call char_class
    test eax, eax
    jnz .Ledw_right_group
    inc r12
    cmp r12, r13
    jb .Ledw_right_read
    jmp .Ledw_done
.Ledw_right_group:
    cmp eax, 1
    je .Ledw_done
    mov r14d, eax
.Ledw_right_more:
    inc r12
    cmp r12, r13
    jae .Ledw_done
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
    mov edi, eax
    call char_class
    cmp eax, r14d
    je .Ledw_right_more
    jmp .Ledw_done
.Ledw_left:
    test r12, r12
    jz .Ledw_done
    mov rdi, rbx
    lea rsi, [r12 - 1]
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
    cmp eax, 10
    jne .Ledw_left_class
    dec r12
    jmp .Ledw_done
.Ledw_left_read:
    mov rdi, rbx
    lea rsi, [r12 - 1]
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
.Ledw_left_class:
    mov edi, eax
    call char_class
    test eax, eax
    jnz .Ledw_left_group
    dec r12
    jnz .Ledw_left_read
    jmp .Ledw_done
.Ledw_left_group:
    cmp eax, 1
    je .Ledw_done
    mov r14d, eax
.Ledw_left_more:
    dec r12
    jz .Ledw_done
    mov rdi, rbx
    lea rsi, [r12 - 1]
    mov rdx, r15
    call editor_delete_read
    test r8d, r8d
    jnz .Ledw_limit
    mov edi, eax
    call char_class
    cmp eax, r14d
    je .Ledw_left_more
.Ledw_done:
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Ledw_limit:
    xor eax, eax
    mov edx, 2
    EPILOGUE
