# Deferred transforms publish one fully preflighted editing transaction.
.include "rhun.inc"
.text
# leave(doc) -> bool. A failure has not changed the real document or session.
FN snippet_transform_leave
    PROLOGUE STL_SIZE
    mov r12, rdi
    mov rbx, rsp
    mov rdi, rbx
    xor esi, esi
    mov edx, STL_SIZE
    call memset
    mov [rbx + STL_doc], r12
    mov r12, [r12 + DOC_snippet]
    test r12, r12
    jz .Lstl_ok
    mov [rbx + STL_state], r12
    mov rax, [r12 + SN_active]
    cmp rax, [r12 + SN_nfields]
    jae .Lstl_ok
    imul rax, rax, SF_SIZE
    mov rax, [r12 + rax + SN_fields + SF_gindex]
    mov [rbx + STL_group], rax
    cmp qword ptr [r12 + SN_transform], 0
    je .Lstl_ok
    xor ecx, ecx
1:  cmp rcx, [r12 + SN_nfields]
    jae .Lstl_ok
    imul rdx, rcx, SF_SIZE
    lea rdx, [r12 + rdx + SN_fields]
    test qword ptr [rdx + SF_flags], 1
    jz 2f
    cmp [rdx + SF_gindex], rax
    jne 2f
    cmp qword ptr [rdx + SF_group], 0
    je 2f
    cmp qword ptr [rdx + SF_transform], 0
    jne .Lstl_start
2:  inc rcx
    jmp 1b
.Lstl_start:
    call time_us
    add rax, 50000
    jc .Lstl_bad
    mov rsi, rax
    mov edi, RX_WORK_MAX
    call snippet_regex_new
    test rax, rax
    jz .Lstl_bad
    mov [rbx + SC_rx], rax
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz .Lstl_bad
    mov [rbx + STL_plan], rax
    mov rdi, rax
    xor esi, esi
    mov edx, STLR_SIZE*SN_FIELDS_MAX
    call memset
    mov rdi, [rbx + STL_doc]
    mov esi, OPT_TAB
    call ext_doc_option
    test eax, eax
    jnz 3f
    mov eax, [rip + cfg_tab_width]
3:  mov [rbx + STL_width], rax
    mov rdi, [rbx + STL_doc]
    mov esi, OPT_SPACES
    call ext_doc_option
    cmp eax, 2
    je 5f
    cmp eax, 1
    je 4f
    cmp dword ptr [rip + cfg_insert_spaces], 0
    jne 5f
4:  xor eax, eax
    jmp 6f
5:  mov eax, 1
6:  mov [rbx + STL_spaces], rax
.Lstl_field:
    mov rax, [rbx + STL_index]
    cmp rax, [r12 + SN_nfields]
    jae .Lstl_preflight
    imul rdx, rax, SF_SIZE
    lea rdx, [r12 + rdx + SN_fields]
    test qword ptr [rdx + SF_flags], 1
    jz .Lstl_next
    mov rcx, [rbx + STL_group]
    cmp [rdx + SF_gindex], rcx
    jne .Lstl_next
    cmp qword ptr [rdx + SF_group], 0
    je .Lstl_next
    cmp qword ptr [rdx + SF_transform], 0
    je .Lstl_next
    mov rdi, rbx
    mov rsi, rax
    call snippet_transform_prepare_field
    test eax, eax
    jz .Lstl_bad
.Lstl_next:
    inc qword ptr [rbx + STL_index]
    jmp .Lstl_field
.Lstl_preflight:
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lstl_bad
    cmp qword ptr [rbx + STL_count], 0
    je .Lstl_ok
    mov rdi, r12
    call snippet_clone_chain_try
    test rax, rax
    jz .Lstl_bad
    mov [rbx + STL_clone], rax
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    mov rcx, [rbx + SC_rx]
    call snippet_transform_apply_plan
    test eax, eax
    jz .Lstl_bad
    mov rax, [rbx + STL_bytes]
    mov [rbx + STL_total], rax
    mov rdi, [rbx + STL_clone]
    xor esi, esi
    lea rdx, [rbx + STL_total]
    mov rcx, [rbx + SC_rx]
    call snippet_propagate_chain_budget
    test eax, eax
    jz .Lstl_bad
    mov rdi, [rbx + STL_clone]
    mov qword ptr [rbx + STL_clone], 0
    call snippet_free_chain
    mov rdi, [rbx + SC_rx]
    call snippet_regex_clock
    test eax, eax
    jz .Lstl_bad
    # Every recoverable failure is now behind us. Replay the same marker plan.
    mov r13, [rbx + STL_doc]
    mov eax, [r13 + DOC_flags]
    and eax, DF_GROUP
    mov [rbx + STL_flags], rax
    mov rdi, r13
    call doc_begin_group
    mov qword ptr [r12 + SN_mutating], 1
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call snippet_transform_apply_plan
    mov rax, [rbx + STL_bytes]
    mov [rbx + STL_total], rax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rbx + STL_total]
    xor ecx, ecx
    call snippet_propagate_chain_budget
    mov qword ptr [r12 + SN_mutating], 0
    mov rdi, r13
    call doc_end_group
    mov eax, [rbx + STL_flags]
    or [r13 + DOC_flags], eax
.Lstl_ok:
    mov r14d, 1
    jmp .Lstl_finish
.Lstl_bad:
    xor r14d, r14d
.Lstl_finish:
    mov rdi, [rbx + STL_clone]
    call snippet_free_chain
    mov rdi, [rbx + STL_raw]
    call mem_free
    mov rdi, [rbx + STL_temp]
    call mem_free
    mov r12, [rbx + STL_plan]
    xor r13d, r13d
1:  cmp r13, [rbx + STL_count]
    jae 2f
    imul rax, r13, STLR_SIZE
    mov rdi, [r12 + rax + STLR_output]
    call mem_free
    inc r13
    jmp 1b
2:  mov rdi, r12
    call mem_free
    lea rdi, [rbx + SC_prep]
    call sb_free
    mov rdi, [rbx + SC_rx]
    call snippet_regex_free
    mov eax, r14d
    EPILOGUE

# Prepare a single occurrence from its own current value, without changing markers.
FN snippet_transform_prepare_field
    PROLOGUE 16
    mov rbx, rdi
    mov r13, rsi
    mov r12, [rbx + STL_state]
    mov r15, [rbx + SC_rx]
    imul r14, r13, SF_SIZE
    lea r14, [r12 + r14 + SN_fields]
    mov rdx, [r14 + SF_end]
    sub rdx, [r14 + SF_start]
    cmp rdx, SN_BYTES_MAX
    ja .Lstpf_input_bad
    mov [rbx + STL_td + TD_ilen], rdx
    mov rdi, r15
    mov rsi, rdx
    call snippet_regex_spend
    test eax, eax
    jz .Lstpf_bad
    mov rdx, [rbx + STL_td + TD_ilen]
    cmp rdx, [rbx + SC_prep + SB_cap]
    jbe 1f
    mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    call snippet_case_reserve
    test eax, eax
    jz .Lstpf_bad
1:  mov rax, [rbx + SC_prep + SB_ptr]
    mov [rbx + STL_td + TD_input], rax
    mov rcx, rax
    mov rdi, [rbx + STL_doc]
    mov rsi, [r14 + SF_start]
    mov rdx, [rbx + STL_td + TD_ilen]
    call doc_copy
    mov rax, [r12 + SN_transform]
    add rax, SC_DATA
    mov rdx, [r14 + SF_transform]
    lea rdx, [rax + rdx - 1]
    mov ecx, [rdx + 4]
    add rcx, rax
    mov [rbx + STL_td + TD_regex], rcx
    mov ecx, [rdx + 8]
    mov [rbx + STL_td + TD_rlen], rcx
    mov ecx, [rdx + 12]
    add rcx, rax
    mov [rbx + STL_td + TD_format], rcx
    mov ecx, [rdx + 16]
    mov [rbx + STL_td + TD_flen], rcx
    mov rdi, r15
    lea rsi, [rbx + STL_td]
    call snippet_transform_execute
    test ecx, ecx
    jz .Lstpf_bad
    mov [rbx + STL_raw], rax
    mov [rbx + STL_ti + TI_input], rax
    mov [rbx + STL_ti + TI_ilen], rdx
    mov rax, [r12 + SN_indent]
    test rax, rax
    jz 2f
    add rax, SC_DATA
2:  mov [rbx + STL_ti + TI_prefix], rax
    mov rax, [r12 + SN_indentbytes]
    mov [rbx + STL_ti + TI_plen], rax
    mov rax, [rbx + STL_width]
    mov [rbx + STL_ti + TI_width], rax
    mov rax, [rbx + STL_spaces]
    mov [rbx + STL_ti + TI_spaces], rax
    mov rdi, r15
    lea rsi, [rbx + STL_ti]
    call snippet_transform_indent
    mov [rbx + STL_temp], rax
    mov [rbx + STL_tlen], rdx
    mov [rsp], rcx
    mov rdi, [rbx + STL_raw]
    mov qword ptr [rbx + STL_raw], 0
    call mem_free
    cmp qword ptr [rsp], 0
    je .Lstpf_bad
    mov rdx, [rbx + STL_tlen]
    cmp rdx, [rbx + STL_td + TD_ilen]
    jne .Lstpf_retain
    mov rdi, r15
    mov rsi, rdx
    call snippet_regex_spend
    test eax, eax
    jz .Lstpf_bad
    mov rdi, [rbx + STL_temp]
    mov rsi, [rbx + STL_td + TD_input]
    mov rdx, [rbx + STL_tlen]
    call memeq
    test eax, eax
    jz .Lstpf_retain
    mov rdi, [rbx + STL_temp]
    mov qword ptr [rbx + STL_temp], 0
    call mem_free
    mov eax, 1
    EPILOGUE
.Lstpf_retain:
    mov rax, [rbx + STL_bytes]
    add rax, [rbx + STL_tlen]
    cmp rax, SN_BYTES_MAX
    ja .Lstpf_output_bad
    mov [rbx + STL_bytes], rax
    mov rax, [rbx + STL_count]
    imul rax, rax, STLR_SIZE
    add rax, [rbx + STL_plan]
    mov [rax + STLR_field], r13
    mov rcx, [rbx + STL_temp]
    mov [rax + STLR_output], rcx
    mov rcx, [rbx + STL_tlen]
    mov [rax + STLR_len], rcx
    mov qword ptr [rbx + STL_temp], 0
    inc qword ptr [rbx + STL_count]
    mov eax, 1
    EPILOGUE
.Lstpf_input_bad:
    mov rdi, r15
    mov esi, RX_INPUT_ERROR
    call snippet_regex_fail
    EPILOGUE
.Lstpf_output_bad:
    mov rdi, r15
    mov esi, RX_CASE_OUTPUT_ERROR
    call snippet_regex_fail
.Lstpf_bad:
    xor eax, eax
    EPILOGUE
