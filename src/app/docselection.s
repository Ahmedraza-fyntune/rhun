# Document selections. The primary remains in DOC_cur/DOC_anchor.
.include "rhun.inc"
.text

# doc_selections_set(doc, {cur,anchor} pairs, total count) -> 1, or 0 without changes.
# Validate every byte boundary before copying. Copy before freeing permits aliased input.
FN doc_selections_set
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .Ldss_bad
    test r13, r13
    jz .Ldss_bad
    cmp r13, DOC_SELECTIONS_MAX
    ja .Ldss_bad
    call doc_len
    mov r14, rax
    mov r15, r13
    shl r15, 1
    mov qword ptr [rsp], 0
.Ldss_validate:
    mov rcx, [rsp]
    cmp rcx, r15
    jae .Ldss_copy
    mov rsi, [r12 + rcx*8]
    cmp rsi, r14
    ja .Ldss_bad
    je .Ldss_next
    mov rdi, rbx
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je .Ldss_bad
.Ldss_next:
    inc qword ptr [rsp]
    jmp .Ldss_validate
.Ldss_copy:
    xor r15d, r15d
    dec r13
    jz .Ldss_install
    mov rdi, r13
    shl rdi, 4
    add rdi, DMS_DATA
    call mem_alloc
    mov r15, rax
    mov [rax + DMS_count], r13
    lea rdi, [rax + DMS_DATA]
    lea rsi, [r12 + DMP_SIZE]
    mov rdx, r13
    shl rdx, 4
    call memcpy
.Ldss_install:
    mov rax, [r12 + DMP_cur]
    mov [rbx + DOC_cur], rax
    mov rax, [r12 + DMP_anchor]
    mov [rbx + DOC_anchor], rax
    mov rdi, [rbx + DOC_selections]
    mov [rbx + DOC_selections], r15
    call mem_free
    mov eax, 1
    EPILOGUE
.Ldss_bad:
    xor eax, eax
    EPILOGUE

# doc_selections_get(doc, zero-based index) -> cur, anchor, r8d valid.
FN doc_selections_get
    test rsi, rsi
    jz .Ldsg_primary
    mov rcx, [rdi + DOC_selections]
    test rcx, rcx
    jz .Ldsg_bad
    dec rsi
    cmp rsi, [rcx + DMS_count]
    jae .Ldsg_bad
    shl rsi, 4
    lea rcx, [rcx + rsi + DMS_DATA]
    mov rax, [rcx + DMP_cur]
    mov rdx, [rcx + DMP_anchor]
    mov r8d, 1
    ret
.Ldsg_primary:
    mov rax, [rdi + DOC_cur]
    mov rdx, [rdi + DOC_anchor]
    mov r8d, 1
    ret
.Ldsg_bad:
    xor eax, eax
    xor edx, edx
    xor r8d, r8d
    ret

FN doc_selections_count
    mov eax, 1
    mov rcx, [rdi + DOC_selections]
    test rcx, rcx
    jz 1f
    add rax, [rcx + DMS_count]
1:  ret

# Drop only secondary selections, preserving the primary and history.
FN doc_selections_clear
    mov rax, [rdi + DOC_selections]
    mov qword ptr [rdi + DOC_selections], 0
    mov rdi, rax
    jmp mem_free

# doc_selections_snapshot(doc) -> independent owned block, or 0 for a single selection.
FN doc_selections_snapshot
    mov rdi, [rdi + DOC_selections]
    jmp doc_selections_clone

# Internal trusted block clone. Does not consume its input.
doc_selections_clone:
    test rdi, rdi
    jz 1f
    mov rsi, [rdi + DMS_count]
    shl rsi, 4
    add rsi, DMS_DATA
    jmp mem_dup
1:  xor eax, eax
    ret

# doc_selections_restore(doc, borrowed snapshot): copy before releasing the old live block.
FN doc_selections_restore
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    call doc_selections_clone
    mov rdi, [rbx + DOC_selections]
    mov [rbx + DOC_selections], rax
    call mem_free
    EPILOGUE

# Secondary endpoints use exactly the primary marker's left insertion affinity.
# doc_selections_insert(doc, position, length)
FN doc_selections_insert
    mov rdi, [rdi + DOC_selections]
    test rdi, rdi
    jz 9f
    mov rcx, [rdi + DMS_count]
    shl rcx, 1
    add rdi, DMS_DATA
1:  cmp [rdi], rsi
    jbe 2f
    add [rdi], rdx
2:  add rdi, 8
    dec rcx
    jnz 1b
9:  ret

# doc_selections_delete(doc, position, length)
FN doc_selections_delete
    mov rdi, [rdi + DOC_selections]
    test rdi, rdi
    jz 9f
    lea r8, [rsi + rdx]
    mov rcx, [rdi + DMS_count]
    shl rcx, 1
    add rdi, DMS_DATA
1:  mov rax, [rdi]
    cmp rax, r8
    jb 2f
    sub rax, rdx
    mov [rdi], rax
    jmp 3f
2:  cmp rax, rsi
    jbe 3f
    mov [rdi], rsi
3:  add rdi, 8
    dec rcx
    jnz 1b
9:  ret

# Record an operation's final selections only if it appended a record.
FN doc_selections_record_after
    PROLOGUE
    mov rbx, rdi
    mov rax, [rdi + DOC_undo + VEC_len]
    cmp rax, rsi
    jbe 9f
    dec rax
    imul rax, rax, UR_SIZE
    add rax, [rdi + DOC_undo + VEC_ptr]
    mov r12, rax
    call doc_selections_snapshot
    mov r13, rax
    mov rdi, [r12 + UR_afterselections]
    cmp rdi, -1
    je 1f
    call mem_free
1:  mov [r12 + UR_afterselections], r13
    mov rcx, [rbx + DOC_cur]
    mov [r12 + UR_aftercur], rcx
    mov rcx, [rbx + DOC_anchor]
    mov [r12 + UR_afteranchor], rcx
9:  EPILOGUE
