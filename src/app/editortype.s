# Typed input prepares all cursor results before applying any document change.
.include "rhun.inc"
.bss
.p2align 3
etp_plan: .zero LTP_SIZE        # lc_type's plan for one cursor

.text

# editor_multi_type(active doc, Unicode scalar) -> success, edx input/limit/readonly/busy.
# UI entry points show errors; this helper only touches the editor after success.
FN editor_multi_type
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rsi
    xor r12d, r12d
    test rbx, rbx
    jz .Let_input
    cmp rbx, [rip + g_doc]
    jne .Let_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Let_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Let_busy
    cmp rsi, 0x10ffff
    ja .Let_input
    cmp rsi, 0xd800
    jb 1f
    cmp rsi, 0xdfff
    jbe .Let_input
1:  mov edi, ETP_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + ETP_doc], rbx
    mov rdi, [rsp]
    mov [rax + ETP_scalar], rdi
    lea rsi, [rax + ETP_encoded]
    call utf8_encode
    mov [r12 + ETP_elen], rax
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Let_input
    mov [r12 + ETP_ranges], rax
    xor r13d, r13d
.Let_plan:
    mov rax, [r12 + ETP_ranges]
    cmp r13, [rax + DNS_count]
    jae .Let_order
    mov r14, r13
    shl r14, 5
    lea r14, [rax + r14 + DNS_ranges]
    mov rdi, rbx
    mov rsi, [r14 + DMR_index]
    call doc_selections_get
    cmp rax, rdx
    setae al
    movzx eax, al
    mov [r12 + ETP_direction], rax
    mov rdi, r12
    mov rsi, r14
    call editor_type_payload
    test eax, eax
    jz .Let_limit
    mov rax, [r12 + ETP_temp]
    mov [r12 + r13*8 + ETP_payloads], rax
    lea rax, [r13 + 1]
    mov [r12 + ETP_built], rax
    mov r15, [r14 + DMR_start]
    add r15, [r12 + ETP_delta]
    cmp qword ptr [r12 + ETP_write], 0
    je .Let_positions
    mov rax, [r12 + ETP_nedits]
    shl rax, 5
    lea rax, [r12 + rax + ETP_edits]
    mov rcx, [r14 + DMR_start]
    mov [rax + DBE_start], rcx
    mov rcx, [r14 + DMR_end]
    mov [rax + DBE_end], rcx
    sub rcx, [r14 + DMR_start]
    sub [r12 + ETP_delta], rcx
    mov rcx, [r12 + ETP_temp]
    mov [rax + DBE_text], rcx
    mov rcx, [r12 + ETP_tlen]
    mov [rax + DBE_len], rcx
    add [r12 + ETP_delta], rcx
    inc qword ptr [r12 + ETP_nedits]
.Let_positions:
    mov rax, [r12 + ETP_cur]
    add rax, r15
    mov [r14 + DMR_start], rax
    mov rax, [r12 + ETP_anchor]
    add rax, r15
    mov [r14 + DMR_end], rax
    inc r13
    jmp .Let_plan
.Let_order:
    mov rax, [r12 + ETP_ranges]
    lea rdi, [rax + DNS_ranges]
    mov rsi, [rax + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    xor ecx, ecx
    mov r14, [r12 + ETP_ranges]
1:  cmp rcx, [r14 + DNS_count]
    jae .Let_apply
    mov rax, rcx
    shl rax, 5
    lea rax, [r14 + rax + DNS_ranges]
    mov rdx, rcx
    shl rdx, 4
    lea rdx, [r12 + rdx + ETP_pairs]
    mov rsi, [rax + DMR_start]
    mov [rdx + DMP_cur], rsi
    mov rsi, [rax + DMR_end]
    mov [rdx + DMP_anchor], rsi
    inc rcx
    jmp 1b
.Let_apply:
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [r12 + ETP_undo], rax
    mov rdi, rbx
    mov rsi, [r12 + ETP_scalar]
    call editor_type_can_join
    test eax, eax
    jz 1f
    or dword ptr [rbx + DOC_flags], DF_GROUP
    mov qword ptr [r12 + ETP_joined], 1
1:  mov rdi, rbx
    lea rsi, [r12 + ETP_edits]
    mov rdx, [r12 + ETP_nedits]
    lea rcx, [r12 + ETP_pairs]
    mov r8, [r14 + DNS_count]
    call doc_selections_apply
    mov [r12 + ETP_error], rdx
    cmp qword ptr [r12 + ETP_joined], 0
    je 2f
    and dword ptr [rbx + DOC_flags], ~DF_GROUP
2:  test eax, eax
    jz .Let_free
    mov rax, [rbx + DOC_undo + VEC_len]
    cmp rax, [r12 + ETP_undo]
    jbe 3f
    mov qword ptr [rbx + DOC_lastkind], EK_TYPE
    mov rax, [r12 + ETP_scalar]
    mov [rbx + DOC_multilastcp], rax
3:  mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp .Let_free
.Let_input:
    mov edx, 1
    jmp .Let_error
.Let_limit:
    mov edx, 2
    jmp .Let_error
.Let_readonly:
    mov edx, 3
    jmp .Let_error
.Let_busy:
    mov edx, 4
.Let_error:
    test r12, r12
    jz .Let_return_error
    mov [r12 + ETP_error], rdx
.Let_free:
    xor r13d, r13d
1:  cmp r13, [r12 + ETP_built]
    jae 2f
    mov rdi, [r12 + r13*8 + ETP_payloads]
    call mem_free
    inc r13
    jmp 1b
2:  mov rdi, [r12 + ETP_ranges]
    call mem_free
    mov r13, [r12 + ETP_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Let_return_error:
    xor eax, eax
    EPILOGUE

# Populate one owned payload and relative output endpoints, or a pure overtype move.
editor_type_payload:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + DMR_start]
    mov r14, [r12 + DMR_end]
    mov qword ptr [rbx + ETP_temp], 0
    mov qword ptr [rbx + ETP_write], 1
    mov rax, [rbx + ETP_elen]
    mov [rbx + ETP_cur], rax
    mov [rbx + ETP_anchor], rax
    # what typing it does here: the language configuration's pairs and outdenting (langconf.s)
    mov rdi, [rbx + ETP_doc]
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rbx + ETP_scalar]
    lea r8, [rip + etp_plan]
    call lc_type
    cmp eax, LTK_OVER
    je .Letp_over
    cmp eax, LTK_PAIR
    je .Letp_pair
    cmp eax, LTK_OUTDENT
    je .Letp_outdent
    cmp eax, LTK_WRAP
    jne .Letp_plain
    movzx r15d, byte ptr [rip + etp_plan + LTP_close]
    jmp .Letp_wrap
.Letp_over:
    mov qword ptr [rbx + ETP_write], 0
    mov qword ptr [rbx + ETP_tlen], 0
    mov qword ptr [rbx + ETP_cur], 1
    mov qword ptr [rbx + ETP_anchor], 1
    jmp .Letp_ok
.Letp_pair:
    mov esi, [rip + etp_plan + LTP_clen]
    add rsi, [rbx + ETP_elen]
    mov rdi, rbx
    call editor_type_allocate
    test rax, rax
    jz .Letp_limit
    mov r15, rax
    mov rdi, rax
    lea rsi, [rbx + ETP_encoded]
    mov rdx, [rbx + ETP_elen]
    call memcpy
    mov rdi, r15
    add rdi, [rbx + ETP_elen]
    lea rsi, [rip + etp_plan + LTP_close]
    mov edx, [rip + etp_plan + LTP_clen]
    call memcpy
    mov rax, [rbx + ETP_elen]
    mov [rbx + ETP_cur], rax
    mov [rbx + ETP_anchor], rax
    jmp .Letp_ok
.Letp_outdent:
    # the edit starts at the line's start: the line one unit less, then the character
    mov rax, [rip + etp_plan + LTP_from]
    mov [r12 + DMR_start], rax
    mov rsi, [rip + etp_plan + LTP_tlen]
    mov rdi, rbx
    call editor_type_allocate
    test rax, rax
    jz .Letp_limit
    mov rdi, rax
    mov rsi, [rip + etp_plan + LTP_text]
    mov rdx, [rip + etp_plan + LTP_tlen]
    call memcpy
    mov rax, [rip + etp_plan + LTP_tlen]
    mov [rbx + ETP_cur], rax
    mov [rbx + ETP_anchor], rax
    jmp .Letp_ok
.Letp_wrap:
    mov rsi, r14
    sub rsi, r13
    add rsi, 2
    jc .Letp_limit
    mov rdi, rbx
    call editor_type_allocate
    test rax, rax
    jz .Letp_limit
    mov rcx, [rbx + ETP_scalar]
    mov [rax], cl
    mov rdx, [rbx + ETP_tlen]
    mov [rax + rdx - 1], r15b
    mov rdi, [rbx + ETP_doc]
    mov rsi, r13
    mov rdx, r14
    sub rdx, r13
    lea rcx, [rax + 1]
    call doc_copy
    mov rax, r14
    sub rax, r13
    inc rax
    mov ecx, 1
    cmp qword ptr [rbx + ETP_direction], 0
    jne 1f
    xchg rax, rcx
1:  mov [rbx + ETP_cur], rax
    mov [rbx + ETP_anchor], rcx
    jmp .Letp_ok
.Letp_plain:
    mov rdi, rbx
    mov rsi, [rbx + ETP_elen]
    call editor_type_allocate
    test rax, rax
    jz .Letp_limit
    mov rdi, rax
    lea rsi, [rbx + ETP_encoded]
    mov rdx, [rbx + ETP_elen]
    call memcpy
.Letp_ok:
    mov eax, 1
    EPILOGUE
.Letp_limit:
    xor eax, eax
    EPILOGUE

# Bound aggregate ownership before allocating or copying selected source bytes.
editor_type_allocate:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp rsi, DOC_MULTI_BYTES_MAX
    ja 8f
    mov rax, [rbx + ETP_bytes]
    add rax, rsi
    jc 8f
    cmp rax, DOC_MULTI_BYTES_MAX
    ja 8f
    mov [rbx + ETP_bytes], rax
    mov [rbx + ETP_tlen], r12
    mov rdi, r12
    call mem_alloc
    mov [rbx + ETP_temp], rax
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Reuse a typing run only when its complete final selection still matches.
editor_type_can_join:
    cmp rsi, 10
    je .Letj_type_no
    cmp qword ptr [rdi + DOC_multilastcp], ' '
    jne 1f
    cmp rsi, ' '
    jne .Letj_type_no
1:  mov esi, EK_TYPE
    jmp editor_multi_can_join
.Letj_type_no:
    xor eax, eax
    ret

# All grouped input requires an exact match with the previous final selection state.
FN editor_multi_can_join
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jnz .Letj_no
    cmp [rbx + DOC_lastkind], r12
    jne .Letj_no
    call time_ms
    sub rax, [rbx + DOC_lastedit]
    cmp rax, 1500
    ja .Letj_no
    mov rax, [rbx + DOC_undo + VEC_len]
    test rax, rax
    jz .Letj_no
    dec rax
    imul rax, rax, UR_SIZE
    add rax, [rbx + DOC_undo + VEC_ptr]
    mov r13, rax
    mov rcx, [rax + UR_group]
    cmp rcx, [rbx + DOC_group]
    jne .Letj_no
    mov rcx, [rax + UR_aftercur]
    cmp rcx, [rbx + DOC_cur]
    jne .Letj_no
    mov rcx, [rax + UR_afteranchor]
    cmp rcx, [rbx + DOC_anchor]
    jne .Letj_no
    mov r14, [rax + UR_afterselections]
    cmp r14, -1
    je .Letj_no
    mov r15, [rbx + DOC_selections]
    test r14, r14
    jz 2f
    test r15, r15
    jz .Letj_no
    mov rdx, [r14 + DMS_count]
    cmp rdx, [r15 + DMS_count]
    jne .Letj_no
    shl rdx, 4
    add rdx, DMS_DATA
    mov rdi, r14
    mov rsi, r15
    call memeq
    test eax, eax
    jz .Letj_no
    jmp 3f
2:  test r15, r15
    jnz .Letj_no
3:  mov rdi, rbx
    call doc_selections_count
    mov r14, rax
    xor r15d, r15d
4:  mov rdi, rbx
    mov rsi, r15
    call doc_selections_get
    cmp rax, rdx
    jne .Letj_no
    inc r15
    cmp r15, r14
    jb 4b
    mov eax, 1
    EPILOGUE
.Letj_no:
    xor eax, eax
    EPILOGUE

# ed_insert's secondary-selection path. Inactive document edits never touch another view.
FN editor_multi_insert
    PROLOGUE 16
    mov rbx, rdi
    call doc_selections_replace
    mov [rsp], rax
    mov [rsp + 8], rdx
    test eax, eax
    jz 8f
    mov dword ptr [rip + g_dirty], 1
8:
    cmp rbx, [rip + g_doc]
    jne 9f
    test eax, eax
    jz 1f
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp 9f
1:  mov edi, edx
    call editor_multi_error
9:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE

# The input entry points own UI feedback; the private planner returns typed errors.
FN editor_multi_error
    cmp edi, 2
    jne 1f
    lea rdi, [rip + .Let_limit_message]
    jmp app_toast
1:  lea rdi, [rip + .Let_input_message]
    jmp app_toast
.section .rodata
.Let_limit_message: .asciz "This edit exceeds the multiple selection size limit."
.Let_input_message: .asciz "This edit could not be applied."
