# Native fields are constructed locally. Only opaque GP-owned member data relocates.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.include "app/extdiscoveryalloc.inc"
.include "app/extdiscoverygpxfer.inc"
.text
# ctx,validated offset -> local pointer or0; offset0 represents absent span.
FN pg_import_local_pointer
    test rsi, rsi
    jz 1f
    cmp rsi, [rdi + PGI_length]
    jae .Lpr_bad_leaf
    mov rax, [rdi + PGI_member]
    add rax, rsi
    jc .Lpr_bad_leaf
    ret
1:  xor eax, eax
    ret
.Lpr_bad_leaf:
    mov rsi, -EV_BAD_GRAMMAR
    jmp pg_import_fail

# Construct at most16 fixed local fields. Never copy native headers from wire.
FN pg_import_fields_step
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + PGI_gp]
.Lpr_fields_again:
    cmp qword ptr [rbx + PGI_units], 16
    jae .Lpr_pending
    mov rax, [rbx + PGI_nativefield]
    cmp rax, 21
    jae .Lpr_fields_done
    cmp rax, 15
    jae .Lpr_string_field
    cmp rax, 4
    jae .Lpr_gr_field
    mov edx, GP_warnings
    mov rcx, [rbx + PGI_info + 72]
    test rax, rax
    jz .Lpr_field_store
    mov edx, GP_rules
    mov rcx, [rbx + PGI_info + 48]
    add rcx, [rbx + PGI_info + 56]
    cmp rax, 1
    je .Lpr_field_store
    mov edx, GP_name_len
    mov rcx, [rbx + PGI_spans + 8]
    cmp rax, 2
    je .Lpr_field_store
    mov edx, GP_legacy
    mov rcx, [rbx + PGI_mode]
    dec rcx
    jmp .Lpr_field_store
.Lpr_gr_field:
    mov edx, GP_gr + GR_owner
    mov rcx, r12
    cmp rax, 4
    je .Lpr_field_store
    mov edx, GP_gr + GR_flags
    mov rcx, [rbx + PGI_info + 64]
    cmp rax, 5
    je .Lpr_field_store
    mov edx, GP_gr + GR_wcap
    mov rcx, [rbx + PGI_info + 24]
    cmp rax, 6
    je .Lpr_field_store
    mov edx, GP_gr + GR_wn
    mov rcx, [rbx + PGI_info + 32]
    cmp rax, 7
    je .Lpr_field_store
    cmp rax, 8
    je .Lpr_words_pointer
    cmp rax, 12
    jb .Lpr_region_field
    mov r13d, GP_gr + GR_lines
    mov r14, [rbx + PGI_info + 56]
    mov rsi, [rbx + PGI_lines]
    sub rax, 12
    jmp .Lpr_vector_field
.Lpr_region_field:
    mov r13d, GP_gr + GR_regions
    mov r14, [rbx + PGI_info + 48]
    mov rsi, [rbx + PGI_regions]
    sub rax, 9
.Lpr_vector_field:
    test rax, rax
    jnz .Lpr_vector_count
    xor ecx, ecx
    test r14, r14
    jz 1f
    mov rdi, rbx
    call pg_import_local_pointer
    test rax, rax
    js .Lpr_return
    mov rcx, rax
1:  lea rdx, [r13 + VEC_ptr]
    jmp .Lpr_field_store
.Lpr_vector_count:
    mov rcx, r14
    lea rdx, [r13 + VEC_len]
    cmp rax, 1
    je .Lpr_field_store
    lea rdx, [r13 + VEC_cap]
    jmp .Lpr_field_store
.Lpr_words_pointer:
    xor ecx, ecx
    cmp qword ptr [rbx + PGI_info + 24], 0
    je 1f
    mov rdi, rbx
    mov rsi, [rbx + PGI_words]
    call pg_import_local_pointer
    test rax, rax
    js .Lpr_return
    mov rcx, rax
1:  mov edx, GP_gr + GR_words
    jmp .Lpr_field_store
.Lpr_string_field:
    cmp rax, 20
    je .Lpr_comment_length
    sub rax, 15
    mov r13, rax
    shl rax, 4
    mov rsi, [rbx + rax + PGI_spans]
    mov rdi, rbx
    call pg_import_local_pointer
    test rax, rax
    js .Lpr_return
    mov rcx, rax
    lea rdx, [rip + pg_import_string_targets]
    mov rdx, [rdx + r13*8]
    jmp .Lpr_field_store
.Lpr_comment_length:
    mov edx, GP_gr + GR_commentlen
    mov rcx, [rbx + PGI_spans + 72]
.Lpr_field_store:
    mov [r12 + rdx], rcx
    inc qword ptr [rbx + PGI_nativefield]
    inc qword ptr [rbx + PGI_units]
    jmp .Lpr_fields_again
.Lpr_fields_done:
    mov qword ptr [rbx + PGI_wordindex], 0
    mov qword ptr [rbx + PGI_recordstage], 0
    mov qword ptr [rbx + PGI_phase], PGI_WORD_RELOC
    inc qword ptr [rbx + PGI_units]
    jmp .Lpr_pending

# ctx,source -> byte/EDX1 or EDX0 budget exhausted.
FN pg_import_read_byte
    xor eax, eax
    xor edx, edx
    cmp qword ptr [rdi + PGI_budget], 0
    je 1f
    movzx eax, byte ptr [rsi]
    dec qword ptr [rdi + PGI_budget]
    inc qword ptr [rdi + PGI_work]
    mov edx, 1
1:  ret

FN pg_import_words_step
    PROLOGUE
    mov rbx, rdi
.Lpr_words_again:
    cmp qword ptr [rbx + PGI_units], 16
    jae .Lpr_pending
    mov rax, [rbx + PGI_wordindex]
    cmp rax, [rbx + PGI_info + 24]
    jae .Lpr_words_done
    mov r13, rax
    shl r13, 4
    add r13, [rbx + PGI_words]
    add r13, [rbx + PGI_member]
    mov rax, [rbx + PGI_recordstage]
    cmp rax, 2
    je .Lpr_word_write
    test rax, rax
    jnz .Lpr_word_read
    mov qword ptr [rbx + PGI_byteindex], 0
    mov qword ptr [rbx + PGI_currentoffset], 0
    mov qword ptr [rbx + PGI_currentlen], 0
    mov qword ptr [rbx + PGI_currentclass], 0
    mov qword ptr [rbx + PGI_accumulator], 0
    mov qword ptr [rbx + PGI_recordstage], 1
.Lpr_word_read:
    mov r12, [rbx + PGI_byteindex]
    cmp r12, 16
    jae .Lpr_word_decoded
    mov rdi, rbx
    lea rsi, [r13 + r12]
    call pg_import_read_byte
    test rdx, rdx
    jz .Lpr_pending
    mov rcx, r12
    cmp rcx, 8
    jb 1f
    and ecx, 3
1:  shl ecx, 3
    shl rax, cl
    or [rbx + PGI_accumulator], rax
    mov edx, PGI_currentoffset
    cmp r12, 7
    je 2f
    mov edx, PGI_currentlen
    cmp r12, 11
    je 2f
    mov edx, PGI_currentclass
    cmp r12, 15
    jne 3f
2:  mov rax, [rbx + PGI_accumulator]
    mov [rbx + rdx], rax
    mov qword ptr [rbx + PGI_accumulator], 0
3:  inc qword ptr [rbx + PGI_byteindex]
    jmp .Lpr_word_read
.Lpr_word_decoded:
    mov rax, [rbx + PGI_currentoffset]
    test rax, rax
    jnz .Lpr_real_word
    mov rax, [rbx + PGI_currentlen]
    or rax, [rbx + PGI_currentclass]
    jnz .Lpr_bad
    jmp .Lpr_word_done
.Lpr_real_word:
    cmp rax, [rbx + PGI_pool]
    jb .Lpr_bad
    mov rdx, [rbx + PGI_currentlen]
    test rdx, rdx
    jz .Lpr_bad
    cmp rdx, [rbx + PGI_sourcebytes]
    ja .Lpr_bad
    cmp qword ptr [rbx + PGI_currentclass], C_COUNT
    jae .Lpr_bad
    add rdx, rax
    jc .Lpr_bad
    cmp rdx, [rbx + PGI_length]
    jae .Lpr_bad
    mov rdi, rbx
    mov rsi, rax
    call pg_import_local_pointer
    test rax, rax
    js .Lpr_return
    mov [rbx + PGI_nativepointer], rax
    mov qword ptr [rbx + PGI_byteindex], 0
    mov qword ptr [rbx + PGI_recordstage], 2
.Lpr_word_write:
    mov rcx, [rbx + PGI_byteindex]
    cmp rcx, 8
    jae .Lpr_word_done
    cmp qword ptr [rbx + PGI_budget], 0
    je .Lpr_pending
    mov rax, [rbx + PGI_nativepointer]
    shl ecx, 3
    shr rax, cl
    mov rcx, [rbx + PGI_byteindex]
    mov [r13 + rcx], al
    dec qword ptr [rbx + PGI_budget]
    inc qword ptr [rbx + PGI_work]
    inc qword ptr [rbx + PGI_byteindex]
    jmp .Lpr_word_write
.Lpr_word_done:
    inc qword ptr [rbx + PGI_wordindex]
    mov qword ptr [rbx + PGI_recordstage], 0
    inc qword ptr [rbx + PGI_units]
    jmp .Lpr_words_again
.Lpr_words_done:
    mov qword ptr [rbx + PGI_cursor], 0
    mov qword ptr [rbx + PGI_phase], PGI_ARRAYS
    inc qword ptr [rbx + PGI_units]
    jmp .Lpr_pending

FN pg_import_arrays_step
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + PGI_gp]
    add r12, GP_gr + GR_identx
    mov r13, [rbx + PGI_member]
    add r13, [rbx + PGI_arrays]
.Lpr_arrays_again:
    mov r14, [rbx + PGI_cursor]
    cmp r14, 576
    jae .Lpr_arrays_done
    cmp qword ptr [rbx + PGI_budget], 2
    jb .Lpr_pending
    mov rdi, rbx
    lea rsi, [r13 + r14]
    call pg_import_read_byte
    mov [r12 + r14], al
    dec qword ptr [rbx + PGI_budget]
    inc qword ptr [rbx + PGI_work]
    inc qword ptr [rbx + PGI_cursor]
    jmp .Lpr_arrays_again
.Lpr_arrays_done:
    mov qword ptr [rbx + PGI_phase], PGI_FINAL
    inc qword ptr [rbx + PGI_units]
    jmp .Lpr_pending

# All rejecting checks precede the first five-store, nonyielding attach.
FN pg_import_final_step
    PROLOGUE
    mov rbx, rdi
    call pg_import_binding_check
    test rax, rax
    js .Lpr_failure
    mov r12, [rbx + PGI_gp]
    test r12, r12
    jz .Lpr_bad
    cmp qword ptr [r12 + PO_ready], 0
    jne .Lpr_bad
    cmp qword ptr [r12 + PO_error], 0
    jne .Lpr_bad
    cmp qword ptr [r12 + PO_refs], 1
    jne .Lpr_bad
    mov r13, [rbx + PGI_eo]
    cmp [r12 + PO_eo], r13
    jne .Lpr_bad
    cmp qword ptr [r12 - RD_PO_BACK + RD_kind], RD_LEDGER
    jne .Lpr_bad
    cmp qword ptr [r12 - RD_PO_BACK + RD_state], RDF_PO
    jne .Lpr_bad
    cmp [r12 + GP_gr + GR_owner], r12
    jne .Lpr_bad
    cmp qword ptr [rbx + PGI_cursor], 576
    jne .Lpr_bad
    mov rax, [rbx + PGI_wordindex]
    cmp rax, [rbx + PGI_info + 24]
    jne .Lpr_bad
    cmp qword ptr [rbx + PGI_member], 0
    je .Lpr_bad
    cmp qword ptr [rbx + PGI_gpslot], -1
    jne .Lpr_bad
    cmp qword ptr [rbx + PGI_memberslot], -1
    jne .Lpr_bad
    mov r13, [rbx + PGI_ep]
    mov rcx, [rbx + PGI_grammarptr]
    mov rdx, [rbx + PGI_grammarlen]
    cmp rdx, [rbx + PGI_grammarcap]
    jae .Lpr_bad
    lea rcx, [rcx + rdx*8]
    cmp qword ptr [rcx], 0
    jne .Lpr_bad
    inc rdx
    mov r8, [rbx + PGI_dia]
    mov qword ptr [rbx + PGI_units], 1
    # VOID: no call, test or fallible work follows the first store.
    mov qword ptr [r12 + PO_ready], 1
    mov [rcx], r12
    mov [r13 + EP_grammars + VEC_len], rdx
    mov qword ptr [r8 + DIA_gp], 0
    mov qword ptr [rbx + PGI_state], PGI_DONE
    xor eax, eax
.Lpr_return:
    EPILOGUE
.Lpr_bad:
    mov rax, -EV_BAD_GRAMMAR
.Lpr_failure:
    mov rdi, rbx
    mov rsi, rax
    call pg_import_fail
    EPILOGUE
.Lpr_pending:
    mov eax, 1
    EPILOGUE

.section .rodata
.p2align 3
pg_import_string_targets:
    .quad GP_gr + GR_name, GP_gr + GR_files, GP_gr + GR_first
    .quad GP_gr + GR_icon, GP_gr + GR_comment
