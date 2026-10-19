.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
many: .zero DOC_SELECTIONS_MAX * DMP_SIZE
.text

.macro SET pairs, count
    mov rdi, rbx
    lea rsi, [rip + \pairs]
    mov edx, \count
    call doc_selections_set
    cmp eax, 1
    jne failed
.endm
.macro CHECK pairs, count
    mov rdi, rbx
    lea rsi, [rip + \pairs]
    mov edx, \count
    call check
    test eax, eax
    jz failed
.endm

# Compare every oriented pair, count, and one out-of-range read.
check:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_selections_count
    cmp rax, r13
    jne .Lcheck_bad
    xor r14d, r14d
1:  mov rdi, rbx
    mov rsi, r14
    call doc_selections_get
    cmp r14, r13
    je 2f
    test r8d, r8d
    jz .Lcheck_bad
    cmp rax, [r12 + DMP_cur]
    jne .Lcheck_bad
    cmp rdx, [r12 + DMP_anchor]
    jne .Lcheck_bad
    add r12, DMP_SIZE
    inc r14
    jmp 1b
2:  test r8d, r8d
    jnz .Lcheck_bad
    mov eax, 1
    EPILOGUE
.Lcheck_bad:
    xor eax, eax
    EPILOGUE

FN main
    PROLOGUE 48
    mov r15, [rip + g_mem_live]
    mov r13d, 1
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + text]
    mov ecx, 8
    xor r8d, r8d
    call doc_insert
    # Leave the gap before a multibyte scalar without changing the text.
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rip + inserted]
    mov ecx, 1
    call raw_insert
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call raw_delete
    SET original, 4
    CHECK original, 4
    mov rdi, rbx
    mov rsi, -1
    call doc_selections_get
    test r8d, r8d
    jnz failed
    # No-op record-after cannot modify an existing record's after state.
    mov rdi, rbx
    mov rsi, [rbx + DOC_undo + VEC_len]
    call doc_selections_record_after
    mov rax, [rbx + DOC_undo + VEC_ptr]
    cmp qword ptr [rax + UR_afterselections], -1
    jne failed
    # Primary direct writes are authoritative, independent of secondary storage.
    mov qword ptr [rbx + DOC_cur], 8
    mov qword ptr [rbx + DOC_anchor], 0
    CHECK primary_changed, 4
    SET original, 4
    mov rdi, rbx
    call doc_selections_snapshot
    mov r12, rax
    mov r13d, 2
    # Invalid endpoints include a split scalar, negative, and beyond EOF.
    lea r14, [rip + invalid]
1:  cmp qword ptr [r14], -2
    je 2f
    mov rdi, rbx
    mov rsi, r14
    mov edx, 2
    call doc_selections_set
    test eax, eax
    jnz failed
    CHECK original, 4
    add r14, 2 * DMP_SIZE
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [rip + original]
    xor edx, edx
    call doc_selections_set
    test eax, eax
    jnz failed
    mov rdi, rbx
    lea rsi, [rip + many]
    mov edx, DOC_SELECTIONS_MAX + 1
    call doc_selections_set
    test eax, eax
    jnz failed
    mov rdi, rbx
    xor esi, esi
    mov edx, 1
    call doc_selections_set
    test eax, eax
    jnz failed
    CHECK original, 4
    mov r13d, 3
    SET many, DOC_SELECTIONS_MAX
    CHECK many, DOC_SELECTIONS_MAX
    # Aliased setter input begins at the old secondary array.
    mov rsi, [rbx + DOC_selections]
    add rsi, DMS_DATA
    mov rdi, rbx
    mov edx, DOC_SELECTIONS_MAX - 1
    call doc_selections_set
    cmp eax, 1
    jne failed
    CHECK many, (DOC_SELECTIONS_MAX-1)
    mov rdi, rbx
    mov rsi, r12
    call doc_selections_restore
    mov qword ptr [rbx + DOC_cur], 3
    mov qword ptr [rbx + DOC_anchor], 1
    CHECK original, 4
    # Restore also permits borrowing the current live block.
    mov rdi, rbx
    mov rsi, [rbx + DOC_selections]
    call doc_selections_restore
    CHECK original, 4
    mov r13d, 4
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + inserted]
    mov ecx, 2
    xor r8d, r8d
    call doc_insert
    CHECK after_insert, 4
    mov rdi, rbx
    mov esi, 1
    mov edx, 6
    xor ecx, ecx
    call doc_delete
    CHECK after_delete, 4
    mov rdi, rbx
    call doc_end_group
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    # Replacing an after snapshot releases the old snapshot, and keeps explicit orientation.
    SET final_pairs, 3
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    mov r14d, 5
3:  mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    CHECK original, 4
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    CHECK final_pairs, 3
    dec r14
    jnz 3b
    # The saved independent block has not been mapped by document edits.
    cmp qword ptr [r12 + DMS_count], 3
    jne failed
    cmp qword ptr [r12 + DMS_DATA + DMP_SIZE + DMP_cur], 8
    jne failed
    mov rdi, r12
    call mem_free
    mov r13d, 5
    # Explicit single-selection after state is distinct from an unspecified one.
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    mov esi, 4
    lea rdx, [rip + inserted]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    SET single_after, 1
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    mov rdi, rbx
    call doc_undo
    CHECK final_pairs, 3
    mov rdi, rbx
    call doc_redo
    CHECK single_after, 1
    mov rdi, rbx
    call doc_undo
    CHECK final_pairs, 3
    # Undo then branch frees redo-owned snapshots.
    mov rdi, rbx
    call doc_undo
    CHECK original, 4
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + inserted]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    cmp qword ptr [rbx + DOC_redo + VEC_len], 0
    jne failed
    mov rdi, rbx
    call doc_undo
    CHECK original, 4
    # Unspecified redo after state retains ordinary scalar behavior and clears extras.
    mov rdi, rbx
    call doc_redo
    mov rdi, rbx
    call doc_selections_count
    cmp rax, 1
    jne failed
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 6
    call doc_new
    mov rbx, rax
    SET empty_pairs, 3
    mov rdi, rbx
    call doc_undo
    test eax, eax
    jnz failed
    mov rdi, rbx
    call doc_redo
    test eax, eax
    jnz failed
    CHECK empty_pairs, 3
    # Failed load preserves extras. Successful load drops them.
    mov rdi, rbx
    lea rsi, [rip + missing]
    call doc_load
    test rax, rax
    jz failed
    CHECK empty_pairs, 3
    mov rdi, rbx
    lea rsi, [rip + path]
    call doc_load
    test rax, rax
    jnz failed
    mov rdi, rbx
    call doc_selections_count
    cmp rax, 1
    jne failed
    SET empty_pairs, 3
    mov rdi, rbx
    lea rsi, [rip + text]
    mov edx, 8
    call doc_replace_all
    cmp qword ptr [rbx + DOC_undo + VEC_len], 0
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 0
    jne failed
    mov rdi, rbx
    call doc_selections_count
    cmp rax, 1
    jne failed
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
failed:
    lea rdi, [rip + fail]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE
.section .rodata
text: .ascii "aéz\nβ!"
inserted: .ascii "XY"
original: .quad 3,1, 0,0, 8,7, 4,5
primary_changed: .quad 8,0, 0,0, 8,7, 4,5
after_insert: .quad 3,1, 0,0, 10,9, 6,7
after_delete: .quad 1,1, 0,0, 4,3, 1,1
final_pairs: .quad 4,3, 1,0, 0,0
single_after: .quad 5,5
empty_pairs: .quad 0,0, 0,0, 0,0
invalid:
    .quad 3,1, 2,0
    .quad 3,1, 0,6
    .quad 3,1, -1,0
    .quad 9,0, 0,0
    .quad -2,0, 0,0
path: .asciz "tests/data/case.txt"
missing: .asciz "build/missing-doc-selections-file"
ok: .asciz "ok document selections\n"
fail: .asciz "failed document selections case "
