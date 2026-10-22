# Bounded native paste distribution, with owned input and normalized payloads.
.include "rhun.inc"
.text
# (destination, UTF8 source, byte length) -> written length. Output never grows.
FN editor_paste_normalize_into
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 4f
    mov r8b, [rsi + rcx]
    inc rcx
    cmp r8b, 13
    jne 3f
    mov r8b, 10
    cmp rcx, rdx
    jae 3f
    cmp byte ptr [rsi + rcx], 10
    jne 3f
    inc rcx
3:  mov [rdi + rax], r8b
    inc rax
    jmp 1b
4:  mov byte ptr [rdi + rax], 0
    ret

# editor_paste_plan_new(doc, text, len, PPO*) -> owned EPP, or0/edx error.
FN editor_paste_plan_new
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    xor r12d, r12d
    test rdi, rdi
    jz .Lpp_input
    test rcx, rcx
    jz .Lpp_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lpp_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Lpp_busy
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Lpp_limit
    test rsi, rsi
    jnz 1f
    test rdx, rdx
    jnz .Lpp_input
1:  mov rax, [rcx + PPO_mode]
    cmp rax, 1
    ja .Lpp_input
    mov [rsp + 40], rax
    mov rax, [rcx + PPO_line]
    cmp rax, 1
    ja .Lpp_input
    mov [rsp + 48], rax
    mov rax, [rcx + PPO_limit]
    cmp rax, DOC_MULTI_BYTES_MAX
    ja .Lpp_limit
    mov [rsp + 56], rax
    mov rax, [rcx + PPO_metadata]
    mov [rsp + 24], rax
    mov rdi, rsi
    mov rsi, rdx
    call snippet_utf8_valid
    test eax, eax
    jz .Lpp_input
    mov edi, EPP_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + EPP_doc], rbx
    mov rcx, [rsp + 40]
    mov [rax + EPP_mode], rcx
    mov rcx, [rsp + 48]
    mov [rax + EPP_line], rcx
    mov rcx, [rsp + 56]
    mov [rax + EPP_limit], rcx
    mov rcx, [rsp + 8]
    mov [rax + EPP_inputlen], rcx
    mov qword ptr [rax + EPP_lastline], -1
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [r12 + EPP_input], rax
    mov rsi, [rsp + 24]
    test rsi, rsi
    jz .Lpp_metadata_done
    mov rdx, [rsi + ECM_count]
    test rdx, rdx
    jz .Lpp_input
    cmp rdx, DOC_SELECTIONS_MAX
    ja .Lpp_input
    mov rax, [rsi + ECM_total]
    cmp rax, [r12 + EPP_inputlen]
    jne .Lpp_input
    shl rdx, 4
    add rdx, ECM_segments
    lea rdi, [r12 + EPP_metadata]
    call memcpy
    xor r13d, r13d
    xor r14d, r14d
.Lpp_metadata:
    cmp r13, [r12 + EPP_metadata + ECM_count]
    jae .Lpp_metadata_done
    mov rax, r13
    shl rax, 4
    lea rax, [r12 + rax + EPP_metadata + ECM_segments]
    mov rsi, [rax + ECS_offset]
    cmp rsi, r14
    jb .Lpp_input
    mov r14, rsi
    add r14, [rax + ECS_len]
    jc .Lpp_input
    cmp r14, [r12 + EPP_inputlen]
    ja .Lpp_input
    mov rdi, r12
    call editor_paste_input_boundary
    test eax, eax
    jz .Lpp_input
    mov rdi, r12
    mov rsi, r14
    call editor_paste_input_boundary
    test eax, eax
    jz .Lpp_input
    inc r13
    jmp .Lpp_metadata
.Lpp_metadata_done:
    cmp qword ptr [r12 + EPP_inputlen], 0
    jne 1f
    mov qword ptr [r12 + EPP_noop], 1
    jmp .Lpp_done
1:  mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jz .Lpp_input
    mov [r12 + EPP_dns], rax
    mov rcx, [rax + DNS_count]
    cmp rcx, 1
    jbe .Lpp_line_check
    cmp rcx, [r12 + EPP_metadata + ECM_count]
    jne .Lpp_line_check
    mov [r12 + EPP_nspans], rcx
    lea rdi, [r12 + EPP_spans]
    lea rsi, [r12 + EPP_metadata + ECM_segments]
    mov rdx, rcx
    shl rdx, 4
    call memcpy
    mov qword ptr [r12 + EPP_distributed], 1
    mov qword ptr [r12 + EPP_line], 0
    jmp .Lpp_cook_begin
.Lpp_line_check:
    cmp qword ptr [r12 + EPP_line], 0
    je .Lpp_try_spread
    mov rax, [r12 + EPP_dns]
    xor ecx, ecx
1:  cmp rcx, [rax + DNS_count]
    jae .Lpp_full
    mov rdx, rcx
    shl rdx, 5
    lea rdx, [rax + rdx + DNS_ranges]
    mov rsi, [rdx + DMR_start]
    cmp rsi, [rdx + DMR_end]
    jne 2f
    inc rcx
    jmp 1b
2:  mov qword ptr [r12 + EPP_line], 0
.Lpp_try_spread:
    cmp qword ptr [r12 + EPP_mode], 0
    jne .Lpp_full
    mov rax, [r12 + EPP_dns]
    cmp qword ptr [rax + DNS_count], 1
    jbe .Lpp_full
    mov r15, [rax + DNS_count]
    mov r14, [r12 + EPP_inputlen]
    mov rbx, [r12 + EPP_input]
    cmp byte ptr [rbx + r14 - 1], 10
    jne 1f
    dec r14
1:  test r14, r14
    jz 2f
    cmp byte ptr [rbx + r14 - 1], 13
    jne 2f
    dec r14
2:  xor r13d, r13d             # line count
    xor ecx, ecx               # current source byte
    xor edx, edx               # current line start
.Lpp_split:
    cmp rcx, r14
    jae .Lpp_split_final
    mov al, [rbx + rcx]
    cmp al, 13
    je .Lpp_split_delim
    cmp al, 10
    je .Lpp_split_delim
    inc rcx
    jmp .Lpp_split
.Lpp_split_delim:
    cmp r13, r15
    jae .Lpp_full
    mov rdi, r13
    shl rdi, 4
    lea rdi, [r12 + rdi + EPP_spans]
    mov [rdi + ECS_offset], rdx
    mov rsi, rcx
    sub rsi, rdx
    mov [rdi + ECS_len], rsi
    inc r13
    inc rcx
    cmp al, 13
    jne 3f
    cmp rcx, r14
    jae 3f
    cmp byte ptr [rbx + rcx], 10
    jne 3f
    inc rcx
3:  mov rdx, rcx
    jmp .Lpp_split
.Lpp_split_final:
    cmp r13, r15
    jae .Lpp_full
    mov rdi, r13
    shl rdi, 4
    lea rdi, [r12 + rdi + EPP_spans]
    mov [rdi + ECS_offset], rdx
    sub rcx, rdx
    mov [rdi + ECS_len], rcx
    inc r13
    cmp r13, r15
    jne .Lpp_full
    mov [r12 + EPP_nspans], r13
    mov qword ptr [r12 + EPP_distributed], 1
    jmp .Lpp_cook_begin
.Lpp_full:
    mov qword ptr [r12 + EPP_nspans], 1
    mov qword ptr [r12 + EPP_spans + ECS_offset], 0
    mov rax, [r12 + EPP_inputlen]
    mov [r12 + EPP_spans + ECS_len], rax
.Lpp_cook_begin:
    mov rdi, [r12 + EPP_inputlen]
    inc rdi
    call mem_alloc
    mov [r12 + EPP_cooked], rax
    xor r13d, r13d
.Lpp_cook:
    cmp r13, [r12 + EPP_nspans]
    jae .Lpp_edits_begin
    mov r14, r13
    shl r14, 4
    lea r14, [r12 + r14 + EPP_spans]
    mov rdi, [r12 + EPP_cooked]
    add rdi, [r12 + EPP_cookedlen]
    mov rsi, [r12 + EPP_input]
    add rsi, [r14 + ECS_offset]
    mov rdx, [r14 + ECS_len]
    call editor_paste_normalize_into
    mov rdx, r13
    shl rdx, 4
    lea rdx, [r12 + rdx + EPP_payloads]
    mov rcx, [r12 + EPP_cookedlen]
    mov [rdx + ECS_offset], rcx
    mov [rdx + ECS_len], rax
    add [r12 + EPP_cookedlen], rax
    inc r13
    jmp .Lpp_cook
.Lpp_edits_begin:
    mov rbx, [r12 + EPP_doc]
    xor r13d, r13d
.Lpp_edit:
    mov rax, [r12 + EPP_dns]
    cmp r13, [rax + DNS_count]
    jae .Lpp_outputs
    mov r14, r13
    shl r14, 5
    lea r14, [rax + r14 + DNS_ranges]
    xor eax, eax
    cmp qword ptr [r12 + EPP_distributed], 0
    je 1f
    mov rax, r13
    shl rax, 4
1:  lea rax, [r12 + rax + EPP_payloads]
    mov r15, [rax + ECS_len]
    mov rcx, [r12 + EPP_cooked]
    add rcx, [rax + ECS_offset]
    mov [rsp + 32], rcx
    cmp qword ptr [r12 + EPP_line], 0
    jne .Lpp_line_edit
    mov rax, [r14 + DMR_start]
    add rax, [r12 + EPP_delta]
    add rax, r15
    mov [r14 + DMR_caret], rax
    mov rax, [r14 + DMR_end]
    sub rax, [r14 + DMR_start]
    sub [r12 + EPP_delta], rax
    add [r12 + EPP_delta], r15
    test rax, rax
    jnz 2f
    test r15, r15
    jz .Lpp_edit_next
2:  mov rax, [r14 + DMR_start]
    mov rdx, [r14 + DMR_end]
    jmp .Lpp_emit
.Lpp_line_edit:
    mov rdi, rbx
    mov rsi, [r14 + DMR_start]
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, [r12 + EPP_lastline]
    je .Lpp_line_caret
    mov [r12 + EPP_lastline], rax
    add [r12 + EPP_delta], r15
    mov rdx, rax
    jmp .Lpp_emit
.Lpp_line_caret:
    mov rax, [r14 + DMR_start]
    add rax, [r12 + EPP_delta]
    mov [r14 + DMR_caret], rax
    jmp .Lpp_edit_next
.Lpp_emit:
    add [r12 + EPP_inserted], r15
    jc .Lpp_limit
    mov rcx, [r12 + EPP_inserted]
    cmp rcx, [r12 + EPP_limit]
    ja .Lpp_limit
    mov rcx, [r12 + EPP_nedits]
    shl rcx, 5
    lea rcx, [r12 + rcx + EPP_edits]
    mov [rcx + DBE_start], rax
    mov [rcx + DBE_end], rdx
    mov rax, [rsp + 32]
    mov [rcx + DBE_text], rax
    mov [rcx + DBE_len], r15
    inc qword ptr [r12 + EPP_nedits]
    cmp qword ptr [r12 + EPP_line], 0
    jne .Lpp_line_caret
.Lpp_edit_next:
    inc r13
    jmp .Lpp_edit
.Lpp_outputs:
    mov rax, [r12 + EPP_dns]
    lea rdi, [rax + DNS_ranges]
    mov rsi, [rax + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    xor r13d, r13d
.Lpp_output:
    mov rax, [r12 + EPP_dns]
    cmp r13, [rax + DNS_count]
    jae .Lpp_done
    mov rdx, r13
    shl rdx, 5
    mov rdx, [rax + rdx + DNS_ranges + DMR_caret]
    xor ecx, ecx
1:  cmp rcx, [r12 + EPP_npairs]
    jae 2f
    mov rax, rcx
    shl rax, 4
    cmp rdx, [r12 + rax + EPP_pairs + DMP_cur]
    je 3f
    inc rcx
    jmp 1b
2:  shl rcx, 4
    mov [r12 + rcx + EPP_pairs + DMP_cur], rdx
    mov [r12 + rcx + EPP_pairs + DMP_anchor], rdx
    inc qword ptr [r12 + EPP_npairs]
3:  inc r13
    jmp .Lpp_output
.Lpp_done:
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Lpp_input:
    mov edx, 1
    jmp .Lpp_error
.Lpp_limit:
    mov edx, 2
    jmp .Lpp_error
.Lpp_readonly:
    mov edx, 3
    jmp .Lpp_error
.Lpp_busy:
    mov edx, 4
.Lpp_error:
    mov r13, rdx
    mov rdi, r12
    call editor_paste_plan_free
    xor eax, eax
    mov rdx, r13
    EPILOGUE

editor_paste_input_boundary:
    cmp rsi, [rdi + EPP_inputlen]
    je 1f
    mov rax, [rdi + EPP_input]
    movzx eax, byte ptr [rax + rsi]
    and eax, 0xc0
    cmp eax, 0x80
    je 2f
1:  mov eax, 1
    ret
2:  xor eax, eax
    ret

FN editor_paste_plan_free
    PROLOGUE
    mov rbx, rdi
    test rdi, rdi
    jz 9f
    mov rdi, [rbx + EPP_dns]
    call mem_free
    mov rdi, [rbx + EPP_input]
    call mem_free
    mov rdi, [rbx + EPP_cooked]
    call mem_free
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

FN editor_multi_paste_ui
    call editor_multi_paste
    test eax, eax
    jnz 1f
    mov edi, edx
    jmp editor_multi_error
1:  ret

# editor_multi_paste(active doc, counted text, length, spread0/full1) -> bool/error.
FN editor_multi_paste
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, rcx
    test rdi, rdi
    jz .Lpa_input
    cmp rdi, [rip + g_doc]
    jne .Lpa_input
    cmp rcx, 1
    ja .Lpa_input
    cmp rdx, DOC_MULTI_BYTES_MAX
    ja .Lpa_limit
    test rsi, rsi
    jnz 1f
    test rdx, rdx
    jnz .Lpa_input
1:  mov rdi, r12
    mov rsi, r13
    call editor_clip_segments_get
    mov [rsp + PPO_metadata], rax
    mov rdi, r12
    mov rsi, r13
    call ed_clip_linewise
    mov [rsp + PPO_line], rax
    mov [rsp + PPO_mode], r15
    mov qword ptr [rsp + PPO_limit], DOC_MULTI_BYTES_MAX
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rsp]
    call editor_paste_plan_new
    test rax, rax
    jz .Lpa_return
    mov r14, rax
    cmp qword ptr [rax + EPP_noop], 0
    jne .Lpa_success
    mov rdi, rbx
    lea rsi, [r14 + EPP_edits]
    mov rdx, [r14 + EPP_nedits]
    lea rcx, [r14 + EPP_pairs]
    mov r8, [r14 + EPP_npairs]
    call doc_selections_apply
    test eax, eax
    jz .Lpa_free
    call ed_touch
.Lpa_success:
    mov eax, 1
    xor edx, edx
.Lpa_free:
    mov [rsp + 32], rax
    mov [rsp + 40], rdx
    mov rdi, r14
    call editor_paste_plan_free
    mov rax, [rsp + 32]
    mov rdx, [rsp + 40]
.Lpa_return:
    EPILOGUE
.Lpa_input:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lpa_limit:
    xor eax, eax
    mov edx, 2
    EPILOGUE
