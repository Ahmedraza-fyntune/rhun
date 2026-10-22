# Document hooks distinguish native user operations from external changes and mirror replay.
.include "rhun.inc"
.text

# Completed ordinary selection moves cannot leave and later revive an old field session.
FN snippet_selection_changed
    test rdi, rdi
    jz 9f
    mov rax, [rdi + DOC_snippet]
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_user], 0
    jne 9f
    cmp qword ptr [rax + SN_mutating], 0
    jne 9f
    jmp snippet_check
9:  ret

FN snippet_user_begin
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    mov rax, [rdi + DOC_snippet]
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_mutating], 0
    jne 9f
    cmp qword ptr [rax + SN_user], 0
    jne 1f
    call snippet_check
    test rax, rax
    jz 9f
    mov rcx, [rbx + DOC_undo + VEC_len]
    mov [rax + SN_beginundo], rcx
1:  inc qword ptr [rax + SN_user]
9:  EPILOGUE

FN snippet_user_end
    PROLOGUE 16
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    mov rax, [rbx + DOC_snippet]
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_mutating], 0
    jne 9f
    cmp qword ptr [rax + SN_user], 0
    je 9f
    dec qword ptr [rax + SN_user]
    jnz 9f
    mov rcx, [rax + SN_beginundo]
    mov [rsp], rcx             # flush may cancel and free the session
    mov rdi, rax
    call snippet_chain_replace_clear
    mov rdi, rbx
    call snippet_flush
    mov rdi, rbx
    mov rsi, [rsp]
    call snippet_record_after
9:  EPILOGUE

# Keep a group's final selection only when this operation appended at least one record.
FN snippet_record_after
    jmp doc_selections_record_after

# snippet_before_change(doc, pos, deleted, inserted)
FN snippet_before_change
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, [rbx + DOC_snippet]
    test r15, r15
    jz 9f
    cmp qword ptr [r15 + SN_mutating], 0
    jne 9f
    cmp qword ptr [r15 + SN_user], 0
    je 8f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 8f
    mov rax, [r15 + SN_docid]
    cmp rax, [rbx + DOC_id]
    jne 8f
1:  mov rdx, r12
    add rdx, r13
    jc 8f
    mov rdi, r15
    mov rsi, r12
    call snippet_range_inside
    test eax, eax
    jz 8f
    mov r15, [r15 + SN_parent]
    test r15, r15
    jnz 1b
    mov r15, [rbx + DOC_snippet]
2:
    mov rdi, r15
    mov rsi, [r15 + SN_active]
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    call snippet_retire_touch
    test eax, eax
    jz 8f
    mov r15, [r15 + SN_parent]
    test r15, r15
    jnz 2b
    jmp 9f
8:  mov rdi, rbx
    call snippet_forget
9:  EPILOGUE

# snippet_after_change(doc, pos, deleted, inserted)
FN snippet_after_change
    mov rax, [rdi + DOC_snippet]
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_mutating], 0
    jne 9f
    mov r8, rcx
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, [rax + SN_active]
    mov rdi, rax
    jmp snippet_map_chain
9:  ret

FN snippet_replace_begin
    PROLOGUE
    mov rbx, [rdi + DOC_snippet]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + SN_user], 0
    je 9f
    call ed_sel
    mov rdi, rbx
    mov rsi, rax
    call snippet_chain_replace_mark
9:  EPILOGUE

# Return the tracked primary record, resolving its stable index after vector reallocations.
# rax = ephemeral UR pointer, rdx = logical position after preceding mirror updates.
FN snippet_previous_record
    mov rcx, [rdi + DOC_snippet]
    test rcx, rcx
    jz 8f
    cmp qword ptr [rcx + SN_mutating], 0
    jne 8f
    cmp qword ptr [rcx + SN_user], 0
    je 8f
    mov rax, [rcx + SN_lastgroup]
    cmp rax, [rdi + DOC_group]
    jne 8f
    mov rax, [rcx + SN_lastrecord]
    cmp rax, [rdi + DOC_undo + VEC_len]
    jae 8f
    imul rax, rax, UR_SIZE
    add rax, [rdi + DOC_undo + VEC_ptr]
    mov rdx, [rcx + SN_lastpos]
    ret
8:  xor eax, eax
    ret

# snippet_note_record(doc, newly appended UR): only the user operation owns coalescing state
FN snippet_note_record
    mov rcx, [rdi + DOC_snippet]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx + SN_mutating], 0
    jne 9f
    cmp qword ptr [rcx + SN_user], 0
    je 9f
    mov rax, [rdi + DOC_undo + VEC_len]
    dec rax
    mov [rcx + SN_lastrecord], rax
    mov rax, [rsi + UR_pos]
    mov [rcx + SN_lastpos], rax
    mov rax, [rsi + UR_len]
    mov [rcx + SN_lastlen], rax
    mov rax, [rsi + UR_group]
    mov [rcx + SN_lastgroup], rax
9:  ret
