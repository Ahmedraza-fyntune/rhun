# Prepared disjoint edits and explicit final selections share one undo boundary.
.include "rhun.inc"
.text

# doc_selections_apply(doc, edits, count, final {cur,anchor} pairs, pair count)
# -> eax success, edx error: 1 input, 2 limit, 3 readonly, 4 nested batch.
# The owner of an enclosing group finalizes its selections after any later edits.
FN doc_selections_apply
    xor r9d, r9d
    jmp doc_selections_apply_guarded

# Optional GDC in r9 runs after all owned preparation and before the first mutation.
# Additional errors: 5 guard rejected, 6 guard changed document state.
FN doc_selections_apply_guarded
    PROLOGUE 64
    mov [rsp + 40], r9
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    xor r12d, r12d
    test rbx, rbx
    jz .Ldba_input
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Ldba_readonly
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne .Ldba_busy
    cmp rdx, DOC_BATCH_EDITS_MAX
    ja .Ldba_limit
    cmp r8, DOC_SELECTIONS_MAX
    ja .Ldba_limit
    test r8, r8
    jz .Ldba_input
    test rcx, rcx
    jz .Ldba_input
    test rdx, rdx
    jz 1f
    test rsi, rsi
    jz .Ldba_input
1:  call doc_selections_count
    test rax, rax
    jz .Ldba_input
    cmp rax, DOC_SELECTIONS_MAX
    ja .Ldba_input
    mov [rsp + 32], rax
    mov edi, DBA_SIZE
    call mem_alloc
    mov r12, rax
    mov [rax + DBA_doc], rbx
    mov rcx, [rsp + 40]
    test rcx, rcx
    jz 10f
    mov rdx, [rcx + GDC_callback]
    test rdx, rdx
    jz .Ldba_input
    mov [r12 + DBA_callback], rdx
    mov rdx, [rcx + GDC_context]
    mov [r12 + DBA_context], rdx
10: mov rcx, [rsp + 8]
    mov [rax + DBA_count], rcx
    mov rcx, [rsp + 24]
    mov [rax + DBA_npairs], rcx
    mov rcx, [rbx + DOC_cur]
    mov [rax + DBA_cur], rcx
    mov rcx, [rbx + DOC_anchor]
    mov [rax + DBA_anchor], rcx
    mov rdi, rbx
    call doc_len
    mov [r12 + DBA_doclen], rax
    lea rdi, [r12 + DBA_edits]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    shl rdx, 5
    test rdx, rdx
    jz 2f
    call memcpy
2:  lea rdi, [r12 + DBA_pairs]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    shl rdx, 4
    call memcpy
    xor r13d, r13d
.Ldba_current:
    cmp r13, [rsp + 32]
    jae .Ldba_edits_begin
    mov rdi, rbx
    mov rsi, r13
    call doc_selections_get
    test r8d, r8d
    jz .Ldba_input
    mov r14, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r12 + DBA_doclen]
    call doc_batch_source_boundary
    test eax, eax
    jz .Ldba_input
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [r12 + DBA_doclen]
    call doc_batch_source_boundary
    test eax, eax
    jz .Ldba_input
    inc r13
    jmp .Ldba_current
.Ldba_edits_begin:
    xor r13d, r13d
.Ldba_edit:
    cmp r13, [r12 + DBA_count]
    jae .Ldba_size
    mov r14, r13
    shl r14, 5
    lea r14, [r12 + r14 + DBA_edits]
    mov rsi, [r14 + DBE_start]
    cmp rsi, [r14 + DBE_end]
    ja .Ldba_input
    jb 1f
    cmp qword ptr [r14 + DBE_len], 0
    je .Ldba_input
1:  test r13, r13
    jz 2f
    cmp rsi, [r14 - DBE_SIZE + DBE_start]
    jbe .Ldba_input
    cmp rsi, [r14 - DBE_SIZE + DBE_end]
    jb .Ldba_input
2:  mov rdi, rbx
    mov rdx, [r12 + DBA_doclen]
    call doc_batch_source_boundary
    test eax, eax
    jz .Ldba_input
    mov rdi, rbx
    mov rsi, [r14 + DBE_end]
    mov rdx, [r12 + DBA_doclen]
    call doc_batch_source_boundary
    test eax, eax
    jz .Ldba_input
    mov rax, [r14 + DBE_end]
    sub rax, [r14 + DBE_start]
    add [r12 + DBA_deleted], rax
    jc .Ldba_limit
    mov rax, [r14 + DBE_len]
    cmp rax, DOC_MULTI_BYTES_MAX
    ja .Ldba_limit
    add [r12 + DBA_inserted], rax
    jc .Ldba_limit
    cmp qword ptr [r12 + DBA_inserted], DOC_MULTI_BYTES_MAX
    ja .Ldba_limit
    test rax, rax
    jz 3f
    cmp qword ptr [r14 + DBE_text], 0
    je .Ldba_input
3:  inc r13
    jmp .Ldba_edit
.Ldba_size:
    mov rax, [r12 + DBA_doclen]
    sub rax, [r12 + DBA_deleted]
    jc .Ldba_input
    add rax, [r12 + DBA_inserted]
    jc .Ldba_limit
    mov rcx, (1 << 40) - 4096
    cmp rax, rcx
    ja .Ldba_limit
    mov [r12 + DBA_final], rax
    cmp qword ptr [r12 + DBA_inserted], 0
    je .Ldba_pairs_begin
    mov rdi, [r12 + DBA_inserted]
    call mem_alloc
    mov [r12 + DBA_text], rax
    mov r15, rax
    xor r13d, r13d
.Ldba_payload:
    cmp r13, [r12 + DBA_count]
    jae .Ldba_pairs_begin
    mov r14, r13
    shl r14, 5
    lea r14, [r12 + r14 + DBA_edits]
    mov rdi, [r14 + DBE_text]
    mov rsi, [r14 + DBE_len]
    call snippet_utf8_valid
    test eax, eax
    jz .Ldba_input
    mov rdi, r15
    mov rsi, [r14 + DBE_text]
    mov rdx, [r14 + DBE_len]
    test rdx, rdx
    jz 1f
    call memcpy
1:  mov [r14 + DBE_text], r15
    add r15, [r14 + DBE_len]
    inc r13
    jmp .Ldba_payload
.Ldba_pairs_begin:
    xor r13d, r13d
    mov r14, [r12 + DBA_npairs]
    shl r14, 1
.Ldba_pair:
    cmp r13, r14
    jae .Ldba_prepared
    mov rdi, r12
    mov rsi, [r12 + r13*8 + DBA_pairs]
    call doc_batch_result_boundary
    test eax, eax
    jz .Ldba_input
    inc r13
    jmp .Ldba_pair
.Ldba_prepared:
    cmp qword ptr [r12 + DBA_callback], 0
    je .Ldba_commit
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [r12 + DBA_snapshot], rax
    mov rdi, rbx
    call doc_selections_snapshot
    mov [r12 + DBA_extras], rax
    mov rdi, [r12 + DBA_context]
    call [r12 + DBA_callback]
    test eax, eax
    jz .Ldba_rejected
    # Compare scalar state and pointers before following any potentially changed pointer.
    mov rdi, rbx
    mov rsi, [r12 + DBA_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz .Ldba_stale
    mov rsi, [r12 + DBA_extras]
    test rsi, rsi
    jz .Ldba_commit
    mov rdi, [rbx + DOC_selections]
    mov rdx, [rsi + DMS_count]
    cmp rdx, [rdi + DMS_count]
    jne .Ldba_stale
    shl rdx, 4
    add rdx, DMS_DATA
    call memeq
    test eax, eax
    jz .Ldba_stale
.Ldba_commit:
    cmp qword ptr [r12 + DBA_count], 0
    je .Ldba_install
    mov rdi, rbx
    call doc_selections_snapshot
    mov [r12 + DBA_before], rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [r12 + DBA_undo], rax
    mov eax, [rbx + DOC_flags]
    and eax, DF_GROUP
    mov [r12 + DBA_grouped], rax
    mov rdi, rbx
    call snippet_forget
    mov qword ptr [rbx + DOC_selectionbatch], 1
    cmp qword ptr [r12 + DBA_grouped], 0
    jne 1f
    mov rdi, rbx
    call doc_begin_group
1:  mov r13, [r12 + DBA_count]
.Ldba_apply:
    dec r13
    mov r14, r13
    shl r14, 5
    lea r14, [r12 + r14 + DBA_edits]
    mov rdi, rbx
    mov rsi, [r14 + DBE_start]
    mov rdx, [r14 + DBE_end]
    sub rdx, rsi
    xor ecx, ecx
    call doc_delete
    mov rdi, rbx
    mov rsi, [r14 + DBE_start]
    mov rdx, [r14 + DBE_text]
    mov rcx, [r14 + DBE_len]
    xor r8d, r8d
    call doc_insert
    test r13, r13
    jnz .Ldba_apply
    cmp qword ptr [r12 + DBA_grouped], 0
    jne .Ldba_history
    mov rdi, rbx
    call doc_end_group
.Ldba_history:
    mov rax, [r12 + DBA_undo]
    imul rax, rax, UR_SIZE
    add rax, [rbx + DOC_undo + VEC_ptr]
    mov rcx, [r12 + DBA_before]
    mov [rax + UR_beforeselections], rcx
    mov qword ptr [r12 + DBA_before], 0
    mov rcx, [r12 + DBA_cur]
    mov [rax + UR_cur], rcx
    mov rcx, [r12 + DBA_anchor]
    mov [rax + UR_anchor], rcx
.Ldba_install:
    mov rdi, rbx
    lea rsi, [r12 + DBA_pairs]
    mov rdx, [r12 + DBA_npairs]
    call doc_selections_set
    test eax, eax
    jz .Ldba_invariant
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    je .Ldba_success
    mov rdi, rbx
    mov rsi, [r12 + DBA_undo]
    call doc_selections_record_after
    mov qword ptr [rbx + DOC_selectionbatch], 0
.Ldba_success:
    mov qword ptr [r12 + DBA_error], 0
    jmp .Ldba_free
.Ldba_input:
    mov edx, 1
    jmp .Ldba_error
.Ldba_limit:
    mov edx, 2
    jmp .Ldba_error
.Ldba_readonly:
    mov edx, 3
    jmp .Ldba_error
.Ldba_busy:
    mov edx, 4
    jmp .Ldba_error
.Ldba_rejected:
    mov edx, 5
    jmp .Ldba_error
.Ldba_stale:
    mov edx, 6
.Ldba_error:
    test r12, r12
    jz .Ldba_return_error
    mov [r12 + DBA_error], rdx
.Ldba_free:
    mov rdi, [r12 + DBA_snapshot]
    call mem_free
    mov rdi, [r12 + DBA_extras]
    call mem_free
    mov rdi, [r12 + DBA_text]
    call mem_free
    mov rdi, [r12 + DBA_before]
    call mem_free
    mov r13, [r12 + DBA_error]
    mov rdi, r12
    call mem_free
    mov rdx, r13
    xor eax, eax
    test rdx, rdx
    sete al
    EPILOGUE
.Ldba_return_error:
    xor eax, eax
    EPILOGUE
.Ldba_invariant:
    ud2

# doc, source offset, length -> byte boundary; never allocates or moves the gap.
doc_batch_source_boundary:
    cmp rsi, rdx
    ja 8f
    je 9f
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
9:  mov eax, 1
    ret
8:  xor eax, eax
    ret

# Locate a final byte in a virtual concatenation of untouched and inserted segments.
# Exact seams belong to the next nonempty segment. Final EOF is always a boundary.
doc_batch_result_boundary:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp rsi, [rbx + DBA_final]
    ja .Ldbv_bad
    je .Ldbv_ok
    xor r13d, r13d             # original source cursor
    xor r14d, r14d             # final cursor
    xor r15d, r15d             # edit index
.Ldbv_edit:
    cmp r15, [rbx + DBA_count]
    jae .Ldbv_original
    mov rax, r15
    shl rax, 5
    lea rax, [rbx + rax + DBA_edits]
    mov rcx, [rax + DBE_start]
    sub rcx, r13
    add rcx, r14
    cmp r12, rcx
    jb .Ldbv_original
    mov r14, rcx
    add rcx, [rax + DBE_len]
    cmp r12, rcx
    jb .Ldbv_inserted
    mov r14, rcx
    mov r13, [rax + DBE_end]
    inc r15
    jmp .Ldbv_edit
.Ldbv_inserted:
    mov rax, [rax + DBE_text]
    mov rdx, r12
    sub rdx, r14
    movzx eax, byte ptr [rax + rdx]
    jmp .Ldbv_byte
.Ldbv_original:
    mov rsi, r12
    sub rsi, r14
    add rsi, r13
    mov rdi, [rbx + DBA_doc]
    call doc_byte
.Ldbv_byte:
    and eax, 0xc0
    cmp eax, 0x80
    je .Ldbv_bad
.Ldbv_ok:
    mov eax, 1
    EPILOGUE
.Ldbv_bad:
    xor eax, eax
    EPILOGUE
