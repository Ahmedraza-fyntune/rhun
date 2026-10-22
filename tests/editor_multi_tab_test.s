# Multiple selection Tab: pure helpers, prepared plans, and real input entry points.
.include "rhun.inc"
.section .rodata
mt_unicode: .byte 'a',9,0xc3,0xa9,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80,0
mt_composed: .ascii "    RRR"
mt_indent: .ascii "  \tx"
mt_ok: .ascii "ok multiple selection Tab and indentation\n"
.equ MT_OK_SIZE, 42
.bss
.p2align 3
mt_stage: .quad 0
mt_phase: .quad 0
mt_live: .quad 0
mt_doc: .quad 0
mt_sn: .quad 0
mt_sn_before: .quad 0
mt_dms_before: .zero DMS_DATA + DMP_SIZE
mt_plan: .quad 0
mt_candidate: .quad 0
mt_allowance: .quad 0
mt_before: .zero DOC_SIZE
mt_copy: .zero 65536
mt_max_source: .zero 2050
mt_max_result: .zero 3075
.p2align 3
mt_max_pairs: .zero 8 + DMP_SIZE*DOC_SELECTIONS_MAX
mt_max_final: .zero 8 + DMP_SIZE*DOC_SELECTIONS_MAX
.text
mt_fail:
    mov edi, [rip + mt_stage]
    imul edi, edi, 10
    add edi, [rip + mt_phase]
    call sys_exit
mt_document:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_new
    mov [rip + mt_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, rbx
    mov rcx, r12
    xor r8d, r8d
    call doc_insert
    lea rdi, [rip + mt_before]
    mov rsi, [rip + mt_doc]
    mov edx, DOC_SIZE
    call memcpy
    EPILOGUE
mt_unchanged:
    PROLOGUE
    lea rdi, [rip + mt_before]
    mov rsi, [rip + mt_doc]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz mt_fail
    EPILOGUE
mt_cleanup:
    PROLOGUE
    call mt_unchanged
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    EPILOGUE
mt_plan_reset:
    PROLOGUE
    mov rdi, [rip + mt_plan]
    xor esi, esi
    mov edx, ETB_SIZE
    call memset
    mov rax, [rip + mt_plan]
    mov qword ptr [rax + ETB_limit], DOC_MULTI_BYTES_MAX
    mov qword ptr [rax + ETB_editlimit], DOC_BATCH_EDITS_MAX
    EPILOGUE
# Inline test candidate: final argument is the repeated payload byte.
mt_candidate_fill:
    PROLOGUE
    mov r12, r9
    call editor_tab_add_candidate
    test rax, rax
    jz mt_fail
    mov r13, rax
    lea rdi, [rax + ETC_data]
    mov rsi, r12
    mov rdx, [rax + ETC_len]
    call memset
    mov rax, r13
    EPILOGUE
mt_composition:
    PROLOGUE
    inc qword ptr [rip + mt_stage]
    mov edi, ETB_SIZE
    call mem_alloc
    mov [rip + mt_plan], rax
    call mt_plan_reset
    mov rdi, [rip + mt_plan]
    xor esi, esi
    mov edx, 2
    mov ecx, 3
    mov r8d, 1
    mov r9d, 'R'
    call mt_candidate_fill
    mov [rip + mt_candidate], rax
    mov rdi, [rip + mt_plan]
    xor esi, esi
    xor edx, edx
    mov ecx, 4
    xor r8d, r8d
    mov r9d, ' '
    call mt_candidate_fill
    mov rdi, [rip + mt_plan]
    mov esi, 4
    mov edx, 4
    mov ecx, 1
    mov r8d, 1
    mov r9d, 9
    call mt_candidate_fill
    mov rdi, [rip + mt_plan]
    call editor_tab_compact
    cmp eax, 1
    jne mt_fail
    mov rbx, [rip + mt_plan]
    cmp qword ptr [rbx + ETB_nedits], 2
    jne mt_fail
    cmp qword ptr [rbx + ETB_bytes], 8
    jne mt_fail
    cmp qword ptr [rbx + ETB_edits + DBE_start], 0
    jne mt_fail
    cmp qword ptr [rbx + ETB_edits + DBE_end], 2
    jne mt_fail
    cmp qword ptr [rbx + ETB_edits + DBE_len], 7
    jne mt_fail
    mov rdi, [rbx + ETB_edits + DBE_text]
    lea rsi, [rip + mt_composed]
    mov edx, 7
    call memeq
    test eax, eax
    jz mt_fail
    mov rax, [rip + mt_candidate]
    cmp qword ptr [rax + ETC_output], 0
    jne mt_fail
    mov rdi, rbx
    mov esi, 3
    xor edx, edx
    call editor_tab_map
    cmp rax, 8
    jne mt_fail
    mov rdi, rbx
    mov esi, 4
    mov edx, 1
    call editor_tab_map
    cmp rax, 9
    jne mt_fail
    mov rdi, rbx
    mov esi, 4
    xor edx, edx
    call editor_tab_map
    cmp rax, 10
    jne mt_fail
    call mt_plan_reset
    inc qword ptr [rip + mt_stage]
    mov rdi, [rip + mt_plan]
    mov esi, 2
    mov edx, 2
    mov ecx, 4
    mov r8d, 1
    mov r9d, ' '
    call mt_candidate_fill
    mov [rip + mt_candidate], rax
    mov rdi, [rip + mt_plan]
    mov esi, 2
    mov edx, 2
    mov ecx, 4
    xor r8d, r8d
    mov r9d, ' '
    call mt_candidate_fill
    mov rdi, [rip + mt_plan]
    call editor_tab_compact
    cmp eax, 1
    jne mt_fail
    mov rbx, [rip + mt_plan]
    cmp qword ptr [rbx + ETB_nedits], 1
    jne mt_fail
    cmp qword ptr [rbx + ETB_bytes], 4
    jne mt_fail
    mov rax, [rip + mt_candidate]
    cmp qword ptr [rax + ETC_output], 0
    jne mt_fail
    mov qword ptr [rbx + ETB_limit], 3
    mov rdi, rbx
    call editor_tab_compact
    test eax, eax
    jnz mt_fail
    cmp edx, 2
    jne mt_fail
    # Shared line union preserves allow-empty and admits duplicates even at capacity.
    call mt_plan_reset
    xor r12d, r12d
1:  mov rdi, [rip + mt_plan]
    mov rsi, r12
    xor edx, edx
    call editor_tab_add_line
    cmp eax, 1
    jne mt_fail
    inc r12
    cmp r12, DOC_BATCH_EDITS_MAX
    jb 1b
    mov rdi, [rip + mt_plan]
    xor esi, esi
    mov edx, 1
    call editor_tab_add_line
    cmp eax, 1
    jne mt_fail
    mov rbx, [rip + mt_plan]
    cmp qword ptr [rbx + ETB_lines + ETL_empty], 1
    jne mt_fail
    cmp qword ptr [rbx + ETB_nlines], DOC_BATCH_EDITS_MAX
    jne mt_fail
    mov rdi, rbx
    mov esi, DOC_BATCH_EDITS_MAX
    xor edx, edx
    call editor_tab_add_line
    test eax, eax
    jnz mt_fail
    cmp edx, 2
    jne mt_fail
    mov rdi, [rip + mt_plan]
    call mem_free
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    EPILOGUE
mt_check:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rip + mt_doc]
    call doc_len
    cmp rax, r12
    jne mt_fail
    mov rdi, [rip + mt_doc]
    xor esi, esi
    mov rdx, r12
    lea rcx, [rip + mt_copy]
    call doc_copy
    lea rdi, [rip + mt_copy]
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz mt_fail
    mov rdi, [rip + mt_doc]
    call doc_selections_count
    cmp rax, [r13]
    jne mt_fail
    xor r14d, r14d
1:  cmp r14, [r13]
    jae 2f
    mov rdi, [rip + mt_doc]
    mov rsi, r14
    call doc_selections_get
    mov rcx, r14
    shl rcx, 4
    cmp rax, [r13 + rcx + 8]
    jne mt_fail
    cmp rdx, [r13 + rcx + 16]
    jne mt_fail
    inc r14
    jmp 1b
2:  EPILOGUE
mt_vectors:
    PROLOGUE 32
    lea r15, [rip + mt_vectors_data]
.Lmtv_next:
    cmp qword ptr [r15], 0
    je .Lmtv_done
    inc qword ptr [rip + mt_stage]
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call mt_document
    mov rdi, [rip + mt_doc]
    mov rsi, [r15 + 16]
    mov rdx, [rsi]
    add rsi, 8
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    mov eax, [r15 + 24]
    mov [rip + g_tab_width], eax
    mov eax, [r15 + 32]
    mov [rip + g_insert_spaces], eax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov rax, [rip + mt_doc]
    mov rcx, [rax + DOC_undo + VEC_len]
    mov [rsp], rcx
    mov rcx, [rax + DOC_group]
    mov [rsp + 8], rcx
    mov rdi, rax
    mov rsi, [r15 + 40]
    mov qword ptr [rip + mt_phase], 1
    call editor_multi_tab
    cmp eax, 1
    jne mt_fail
    test edx, edx
    jnz mt_fail
    mov qword ptr [rip + mt_phase], 2
    mov rdi, [r15 + 48]
    mov rsi, [r15 + 56]
    mov rdx, [r15 + 64]
    call mt_check
    mov qword ptr [rip + mt_phase], 3
    mov rdi, [rip + mt_doc]
    mov rax, [rdi + DOC_undo + VEC_len]
    cmp rax, [rsp]
    jbe mt_fail
    mov rax, [rdi + DOC_group]
    sub rax, [rsp + 8]
    cmp rax, 1
    jne mt_fail
    call doc_undo
    mov rax, [rip + mt_doc]
    mov rax, [rax + DOC_undo + VEC_len]
    cmp rax, [rsp]
    jne mt_fail
    mov qword ptr [rip + mt_phase], 4
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_redo
    mov qword ptr [rip + mt_phase], 5
    mov rdi, [r15 + 48]
    mov rsi, [r15 + 56]
    mov rdx, [r15 + 64]
    call mt_check
    mov qword ptr [rip + mt_phase], 6
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    add r15, 72
    jmp .Lmtv_next
.Lmtv_done:
    EPILOGUE
mt_failures:
    PROLOGUE 48
    xor r15d, r15d
.Lmt_fail_case:
    mov dword ptr [rip + g_tab_width], 4
    mov dword ptr [rip + g_insert_spaces], 1
    inc qword ptr [rip + mt_stage]
    mov qword ptr [rip + mt_phase], 0
    lea rdi, [rip + mt_two]
    mov esi, 5
    call mt_document
    mov rdi, [rip + mt_doc]
    mov esi, 5
    lea rdx, [rip + mt_unicode]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + mt_doc]
    call doc_undo
    lea rdi, [rip + mt_two]
    mov esi, 5
    call snippet_new
    mov [rip + mt_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + mt_sn]
    call snippet_validate
    cmp eax, 1
    jne mt_fail
    mov rdi, [rip + mt_doc]
    mov rsi, [rip + mt_sn]
    xor edx, edx
    call snippet_attach
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_two_pairs + 8]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    mov dword ptr [rip + g_tab_width], 4
    mov dword ptr [rip + g_insert_spaces], 1
    mov rbx, [rip + mt_doc]
    cmp r15, 0
    jne 1f
    or dword ptr [rbx + DOC_flags], DF_READONLY
1:  cmp r15, 1
    jne 2f
    mov qword ptr [rbx + DOC_selectionbatch], 1
2:  cmp r15, 5
    jne 3f
    mov dword ptr [rip + g_tab_width], 0
3:  cmp r15, 6
    jne 4f
    mov dword ptr [rip + g_insert_spaces], 2
4:  lea rdi, [rip + mt_before]
    mov rsi, rbx
    mov edx, DOC_SIZE
    call memcpy
    lea rdi, [rip + mt_dms_before]
    mov rsi, [rbx + DOC_selections]
    mov edx, DMS_DATA + DMP_SIZE
    call memcpy
    mov rdi, [rip + mt_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + mt_sn_before], rax
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov dword ptr [rip + g_dirty], 0
    mov rdi, rbx
    xor esi, esi
    mov edx, DOC_MULTI_BYTES_MAX
    mov ecx, DOC_MULTI_BYTES_MAX
    mov r8d, DOC_BATCH_EDITS_MAX
    mov qword ptr [rsp + 8], 1
    cmp r15, 0
    jne 5f
    mov qword ptr [rsp + 8], 3
5:  cmp r15, 1
    jne 6f
    mov qword ptr [rsp + 8], 4
6:  cmp r15, 2
    jne 7f
    xor ecx, ecx
    mov qword ptr [rsp + 8], 2
7:  cmp r15, 3
    jne 8f
    xor edx, edx
    mov qword ptr [rsp + 8], 2
8:  cmp r15, 4
    jne 9f
    mov r8d, 1
    mov qword ptr [rsp + 8], 2
9:  cmp r15, 7
    jne 10f
    mov esi, 2
10: cmp r15, 8
    jne 11f
    mov qword ptr [rip + g_doc], 0
11: cmp r15, 9
    jne 12f
    xor edi, edi
12: cmp r15, 10
    jne 13f
    mov rsi, -1
    mov qword ptr [rsp + 8], 0
13: call editor_multi_tab_limited
    cmp rdx, [rsp + 8]
    jne mt_fail
    mov rcx, [rsp + 8]
    test rcx, rcx
    sete cl
    movzx ecx, cl
    cmp eax, ecx
    jne mt_fail
    mov [rip + g_doc], rbx
    cmp dword ptr [rip + g_dirty], 0
    jne mt_fail
    mov rax, [rsp]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    call mt_unchanged
    lea rdi, [rip + mt_dms_before]
    mov rsi, [rbx + DOC_selections]
    mov edx, DMS_DATA + DMP_SIZE
    call memeq
    test eax, eax
    jz mt_fail
    mov rdi, [rip + mt_sn]
    mov rsi, [rip + mt_sn_before]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz mt_fail
    mov rdi, [rip + mt_sn_before]
    call mem_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    inc r15
    cmp r15, 11
    jb .Lmt_fail_case
    EPILOGUE
mt_input_routes:
    PROLOGUE
    xor r15d, r15d
1:  inc qword ptr [rip + mt_stage]
    mov qword ptr [rip + mt_phase], 0
    mov dword ptr [rip + g_tab_width], 4
    mov dword ptr [rip + g_insert_spaces], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    mov qword ptr [rip + g_tab_cur], -1
    lea rdi, [rip + mt_two]
    mov esi, 5
    cmp r15, 3
    jb 2f
    lea rdi, [rip + mt_two_indent]
    mov esi, 13
2:  call mt_document
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_two_pairs + 8]
    cmp r15, 3
    jb 3f
    lea rsi, [rip + mt_two_indent_pairs + 8]
3:  mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    cmp r15, 0
    je .Lmti_tab
    cmp r15, 1
    je .Lmti_key_tab
    cmp r15, 2
    je .Lmti_indent
    cmp r15, 3
    je .Lmti_key_outdent
    call cmd_outdent
    jmp .Lmti_verify_outdent
.Lmti_key_outdent:
    mov edi, KEY_TAB
    xor esi, esi
    mov edx, MOD_SHIFT
    call app_on_key
.Lmti_verify_outdent:
    lea rdi, [rip + mt_two]
    mov esi, 5
    lea rdx, [rip + mt_two_pairs]
    jmp .Lmti_check
.Lmti_indent:
    call cmd_indent
    lea rdi, [rip + mt_two_indent]
    mov esi, 13
    lea rdx, [rip + mt_two_indent_pairs]
    jmp .Lmti_check
.Lmti_tab:
    call ed_tab
    jmp .Lmti_verify_tab
.Lmti_key_tab:
    mov edi, KEY_TAB
    xor esi, esi
    xor edx, edx
    call app_on_key
.Lmti_verify_tab:
    lea rdi, [rip + mt_two_tab]
    mov esi, 9
    lea rdx, [rip + mt_two_tab_pairs]
.Lmti_check:
    call mt_check
    cmp r15, 2
    jae 4f
    mov edi, 'X'
    call ed_type
    lea rdi, [rip + mt_after_type]
    mov esi, 11
    lea rdx, [rip + mt_after_type_pairs]
    call mt_check
4:  mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    inc r15
    cmp r15, 5
    jb 1b
    EPILOGUE
mt_maximum:
    PROLOGUE
    inc qword ptr [rip + mt_stage]
    mov qword ptr [rip + mt_phase], 0
    mov dword ptr [rip + g_tab_width], 4
    mov dword ptr [rip + g_insert_spaces], 0
    lea rdi, [rip + mt_max_source]
    mov esi, 'a'
    mov edx, DOC_SELECTIONS_MAX
    call memset
    mov qword ptr [rip + mt_max_pairs], DOC_SELECTIONS_MAX
    mov qword ptr [rip + mt_max_final], DOC_SELECTIONS_MAX
    xor ecx, ecx
1:  lea rdi, [rip + mt_max_result]
    mov byte ptr [rdi + rcx*2], 9
    mov byte ptr [rdi + rcx*2 + 1], 'a'
    mov rax, rcx
    shl rax, 4
    lea rdi, [rip + mt_max_pairs + 8]
    mov [rdi + rax], rcx
    mov [rdi + rax + 8], rcx
    lea rdx, [rcx*2 + 1]
    lea rdi, [rip + mt_max_final + 8]
    mov [rdi + rax], rdx
    mov [rdi + rax + 8], rdx
    inc rcx
    cmp rcx, DOC_SELECTIONS_MAX
    jb 1b
    lea rdi, [rip + mt_max_source]
    mov esi, DOC_SELECTIONS_MAX
    call mt_document
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_max_pairs + 8]
    mov edx, DOC_SELECTIONS_MAX
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    mov rdi, [rip + mt_doc]
    xor esi, esi
    call editor_multi_tab
    cmp eax, 1
    jne mt_fail
    lea rdi, [rip + mt_max_result]
    mov esi, DOC_SELECTIONS_MAX*2
    lea rdx, [rip + mt_max_final]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_undo
    lea rdi, [rip + mt_max_source]
    mov esi, DOC_SELECTIONS_MAX
    lea rdx, [rip + mt_max_pairs]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    # Exactly1024 distinct line prefixes fit; a1025th rejects before mutation.
    xor r15d, r15d
.Lmtm_lines:
    inc qword ptr [rip + mt_stage]
    mov r14d, DOC_BATCH_EDITS_MAX
    add r14, r15
    xor ecx, ecx
2:  lea rdi, [rip + mt_max_source]
    mov byte ptr [rdi + rcx*2], 'x'
    mov byte ptr [rdi + rcx*2 + 1], 10
    lea rdi, [rip + mt_max_result]
    lea rax, [rcx + rcx*2]
    mov byte ptr [rdi + rax], 9
    mov byte ptr [rdi + rax + 1], 'x'
    mov byte ptr [rdi + rax + 2], 10
    inc rcx
    cmp rcx, r14
    jb 2b
    lea rdi, [rip + mt_max_source]
    lea rsi, [r14*2]
    call mt_document
    mov qword ptr [rip + mt_max_pairs], 2
    mov qword ptr [rip + mt_max_pairs + 8], 0
    lea rax, [r14*2]
    mov [rip + mt_max_pairs + 16], rax
    mov [rip + mt_max_pairs + 24], rax
    mov [rip + mt_max_pairs + 32], rax
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_max_pairs + 8]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    lea rdi, [rip + mt_before]
    mov rsi, [rip + mt_doc]
    mov edx, DOC_SIZE
    call memcpy
    mov rdi, [rip + mt_doc]
    mov esi, 1
    call editor_multi_tab
    test r15, r15
    jnz .Lmtm_rejected
    cmp eax, 1
    jne mt_fail
    mov qword ptr [rip + mt_max_final], 1
    mov qword ptr [rip + mt_max_final + 8], 0
    lea rax, [r14 + r14*2]
    mov [rip + mt_max_final + 16], rax
    lea rdi, [rip + mt_max_result]
    mov rsi, rax
    lea rdx, [rip + mt_max_final]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_undo
    lea rdi, [rip + mt_max_source]
    lea rsi, [r14*2]
    lea rdx, [rip + mt_max_pairs]
    call mt_check
    jmp .Lmtm_cleanup
.Lmtm_rejected:
    test eax, eax
    jnz mt_fail
    cmp edx, 2
    jne mt_fail
    call mt_unchanged
.Lmtm_cleanup:
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    inc r15
    cmp r15, 2
    jb .Lmtm_lines
    EPILOGUE
mt_priority_and_group:
    PROLOGUE 16
    inc qword ptr [rip + mt_stage]
    mov qword ptr [rip + mt_phase], 0
    mov dword ptr [rip + g_tab_width], 4
    mov dword ptr [rip + g_insert_spaces], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    lea rdi, [rip + mt_two]
    mov esi, 5
    call mt_document
    lea rdi, [rip + mt_two]
    mov esi, 5
    call snippet_new
    mov r14, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call snippet_add
    mov rdi, r14
    mov esi, 2
    mov edx, 2
    mov ecx, 2
    xor r8d, r8d
    call snippet_add
    mov rdi, r14
    call snippet_validate
    cmp eax, 1
    jne mt_fail
    mov rdi, [rip + mt_doc]
    mov rsi, r14
    xor edx, edx
    call snippet_attach
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_priority_pairs + 8]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    mov rax, [rip + mt_doc]
    mov rcx, [rax + DOC_undo + VEC_len]
    mov [rsp], rcx
    mov edi, KEY_TAB
    xor esi, esi
    xor edx, edx
    call app_on_key
    lea rdi, [rip + mt_two]
    mov esi, 5
    lea rdx, [rip + mt_priority_final]
    call mt_check
    mov rax, [rip + mt_doc]
    cmp r14, [rax + DOC_snippet]
    jne mt_fail
    mov rcx, [rsp]
    cmp rcx, [rax + DOC_undo + VEC_len]
    jne mt_fail
    mov edi, KEY_TAB
    xor esi, esi
    mov edx, MOD_SHIFT
    call app_on_key
    lea rdi, [rip + mt_two]
    mov esi, 5
    lea rdx, [rip + mt_priority_pairs]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    # An enclosing group owns the same single undo boundary.
    inc qword ptr [rip + mt_stage]
    lea rdi, [rip + mt_two]
    mov esi, 5
    call mt_document
    mov rdi, [rip + mt_doc]
    lea rsi, [rip + mt_two_pairs + 8]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne mt_fail
    mov rdi, [rip + mt_doc]
    call doc_begin_group
    mov rdi, [rip + mt_doc]
    xor esi, esi
    call editor_multi_tab
    cmp eax, 1
    jne mt_fail
    mov rdi, [rip + mt_doc]
    call doc_end_group
    lea rdi, [rip + mt_two_tab]
    mov esi, 9
    lea rdx, [rip + mt_two_tab_pairs]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_undo
    lea rdi, [rip + mt_two]
    mov esi, 5
    lea rdx, [rip + mt_two_pairs]
    call mt_check
    mov rdi, [rip + mt_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + mt_live]
    cmp rax, [rip + g_mem_live]
    jne mt_fail
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + mt_stage], 1
    mov rax, [rip + g_mem_live]
    mov [rip + mt_live], rax
    lea rdi, [rip + mt_unicode]
    mov esi, 12
    call mt_document
    mov r15d, 1
1:  mov [rip + g_tab_width], r15d
    mov rdi, [rip + mt_doc]
    mov esi, 12
    call doc_col_of
    mov r14, rax
    mov qword ptr [rip + mt_allowance], 64
    mov rdi, [rip + mt_doc]
    mov esi, 12
    mov rdx, r15
    lea rcx, [rip + mt_allowance]
    call editor_tab_column
    test edx, edx
    jnz mt_fail
    cmp rax, r14
    jne mt_fail
    call mt_unchanged
    inc r15
    cmp r15, 16
    jbe 1b
    inc qword ptr [rip + mt_stage]
    mov qword ptr [rip + mt_allowance], 0
    mov rdi, [rip + mt_doc]
    mov esi, 12
    mov edx, 4
    lea rcx, [rip + mt_allowance]
    call editor_tab_column
    cmp edx, 2
    jne mt_fail
    mov rdi, [rip + mt_doc]
    xor esi, esi
    mov edx, 4
    lea rcx, [rip + mt_allowance]
    call editor_tab_column
    test rax, rax
    jnz mt_fail
    test edx, edx
    jnz mt_fail
    mov rdi, [rip + mt_doc]
    mov esi, 12
    xor edx, edx
    lea rcx, [rip + mt_allowance]
    call editor_tab_column
    cmp edx, 1
    jne mt_fail
    call mt_cleanup
    inc qword ptr [rip + mt_stage]
    lea rdi, [rip + mt_indent]
    mov esi, 4
    call mt_document
    mov qword ptr [rip + mt_allowance], 4
    mov rdi, [rip + mt_doc]
    xor esi, esi
    mov edx, 4
    lea rcx, [rip + mt_allowance]
    call editor_tab_outdent
    test edx, edx
    jnz mt_fail
    cmp rax, 3
    jne mt_fail
    cmp qword ptr [rip + mt_allowance], 1
    jne mt_fail
    mov qword ptr [rip + mt_allowance], 4
    mov rdi, [rip + mt_doc]
    xor esi, esi
    mov edx, 2
    lea rcx, [rip + mt_allowance]
    call editor_tab_outdent
    test edx, edx
    jnz mt_fail
    cmp rax, 2
    jne mt_fail
    mov qword ptr [rip + mt_allowance], 2
    mov rdi, [rip + mt_doc]
    xor esi, esi
    mov edx, 4
    lea rcx, [rip + mt_allowance]
    call editor_tab_outdent
    cmp edx, 2
    jne mt_fail
    call mt_cleanup
    call mt_composition
    call mt_vectors
    call mt_failures
    call mt_input_routes
    call mt_maximum
    call mt_priority_and_group
    mov edi, 1
    lea rsi, [rip + mt_ok]
    mov edx, MT_OK_SIZE
    call write_all
    xor edi, edi
    call sys_exit

.section .rodata
.p2align 3
mt_two: .ascii "a\nabc"
mt_two_tab: .ascii "a   \nabc "
mt_after_type: .ascii "a   X\nabc X"
mt_after_type_pairs: .quad 2,11,11,5,5
mt_two_literal: .ascii "a\t\nabc\t"
mt_two_indent: .ascii "    a\n    abc"
mt_two_pairs: .quad 2,5,5,1,1
mt_two_tab_pairs: .quad 2,9,9,4,4
mt_two_literal_pairs: .quad 2,7,7,2,2
mt_two_indent_pairs: .quad 2,13,13,5,5
mt_out: .ascii "  \ta\n    bc"
mt_out_result: .ascii "a\nbc"
mt_out_pairs: .quad 2,10,10,4,4
mt_out_final: .quad 2,3,3,1,1
mt_mix: .ascii "abcdef\ngh"
mt_mix_result: .ascii "        cdef\n    gh"
mt_mix_pairs: .quad 2,0,2,4,9
mt_mix_final: .quad 2,8,8,10,19
mt_block: .ascii "a\nb\nc"
mt_block_result: .ascii "    a\n    b\nc"
mt_block_pairs: .quad 2,0,2,2,4
mt_block_final: .quad 2,0,6,6,12
mt_priority_pairs: .quad 2,0,0,1,1
mt_priority_final: .quad 2,2,2,1,1
mt_vectors_data:
    .quad mt_two,5,mt_two_pairs,4,1,0,mt_two_tab,9,mt_two_tab_pairs
    .quad mt_two,5,mt_two_pairs,4,0,0,mt_two_literal,7,mt_two_literal_pairs
    .quad mt_two,5,mt_two_pairs,4,1,1,mt_two_indent,13,mt_two_indent_pairs
    .quad mt_out,11,mt_out_pairs,4,1,-1,mt_out_result,4,mt_out_final
    .quad mt_mix,9,mt_mix_pairs,4,1,0,mt_mix_result,19,mt_mix_final
    .quad mt_block,5,mt_block_pairs,4,1,0,mt_block_result,13,mt_block_final
    .quad 0
