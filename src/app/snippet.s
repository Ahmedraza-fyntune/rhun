# Prepared native snippet fields. Validation is independent of document mutation.
.include "rhun.inc"

.bss
.p2align 3
sn_identity: .quad 0
.globl sn_activation
sn_activation: .quad 0
.text

# snippet_new(text, len) -> owned empty candidate
FN snippet_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov edi, SN_SIZE
    call mem_alloc
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, SN_SIZE
    call memset
    inc qword ptr [rip + sn_identity]
    mov rax, [rip + sn_identity]
    mov [rbx + SN_identity], rax
    mov [rbx + SN_text], r12
    mov [rbx + SN_tlen], r13
    mov [rbx + SN_final], r13
    mov [rbx + SN_finalend], r13
    mov qword ptr [rbx + SN_finalfield], -1
    mov qword ptr [rbx + SN_finalowner], -1
    mov qword ptr [rbx + SN_finalcollapseowner], -1
    mov qword ptr [rbx + SN_active], -1
    mov qword ptr [rbx + SN_lastrecord], -1
    mov qword ptr [rbx + SN_valid], 1
    mov rax, rbx
    EPILOGUE

# snippet_add(state, group, start, end, parent) -> 1, or sticky invalid candidate
FN snippet_add
    cmp qword ptr [rdi + SN_valid], 0
    je 8f
    mov rax, [rdi + SN_nfields]
    cmp rax, SN_FIELDS_MAX
    jae 7f
    imul r9, rax, SF_SIZE
    lea r9, [rdi + r9 + SN_fields]
    mov [r9 + SF_group], rsi
    mov [r9 + SF_start], rdx
    mov [r9 + SF_end], rcx
    mov [r9 + SF_parent], r8
    mov qword ptr [r9 + SF_flags], 1
    inc qword ptr [rdi + SN_nfields]
    mov eax, 1
    ret
7:  mov qword ptr [rdi + SN_valid], 0
8:  xor eax, eax
    ret

# snippet_utf8_valid(ptr, len) -> 1. Unlike display decoding, reject surrogate values.
FN snippet_utf8_valid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, r12
    jae 9f
    lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp eax, 0x10ffff
    ja 8f
    cmp eax, 0xd800
    jb 2f
    cmp eax, 0xdfff
    jbe 8f
2:  cmp eax, 0xfffd
    jne 3f
    cmp edx, 1
    je 8f
3:  add r13, rdx
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# snippet_ancestor(state, parent index, child index) -> 1
FN snippet_ancestor
    imul rdx, rdx, SF_SIZE
    lea rdx, [rdi + rdx + SN_fields]
1:  mov rax, [rdx + SF_parent]
    test rax, rax
    jz 8f
    dec rax
    cmp rax, rsi
    je 9f
    imul rdx, rax, SF_SIZE
    lea rdx, [rdi + rdx + SN_fields]
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# snippet_validate(state) -> 1, after constructing primary indices and propagation order
FN snippet_validate
    PROLOGUE 64
    mov rbx, rdi
    cmp qword ptr [rbx + SN_valid], 0
    je .Lsv_bad
    cmp qword ptr [rbx + SN_nfields], SN_FIELDS_MAX
    ja .Lsv_bad
    cmp qword ptr [rbx + SN_tlen], SN_BYTES_MAX
    ja .Lsv_bad
    mov rdi, [rbx + SN_text]
    mov rsi, [rbx + SN_tlen]
    call snippet_utf8_valid
    test eax, eax
    jz .Lsv_bad
    mov qword ptr [rbx + SN_ngroups], 0
    mov rax, [rbx + SN_tlen]
    mov [rbx + SN_final], rax
    mov [rbx + SN_finalend], rax
    mov qword ptr [rbx + SN_finalfield], -1
    mov qword ptr [rbx + SN_finalspan], 0
    mov qword ptr [rbx + SN_finalowner], -1
    mov qword ptr [rbx + SN_finalcollapseowner], -1
    mov qword ptr [rsp], 0       # final caret seen
    xor r12d, r12d
.Lsv_field:
    cmp r12, [rbx + SN_nfields]
    jae .Lsv_pairs_begin
    imul r13, r12, SF_SIZE
    lea r13, [rbx + r13 + SN_fields]
    and qword ptr [r13 + SF_flags], 64
    or qword ptr [r13 + SF_flags], 1
    mov rax, [r13 + SF_group]
    cmp rax, 2147483647
    ja .Lsv_bad
    mov rax, [r13 + SF_start]
    cmp rax, [r13 + SF_end]
    ja .Lsv_bad
    mov rcx, [r13 + SF_end]
    cmp rcx, [rbx + SN_tlen]
    ja .Lsv_bad
    mov rdx, [rbx + SN_text]
    cmp rax, [rbx + SN_tlen]
    je 1f
    movzx eax, byte ptr [rdx + rax]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lsv_bad
1:  cmp rcx, [rbx + SN_tlen]
    je 2f
    movzx eax, byte ptr [rdx + rcx]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lsv_bad
2:  mov r14, [r13 + SF_parent]
    cmp r14, r12
    ja .Lsv_bad
    xor r15d, r15d
3:  test r14, r14
    jz .Lsv_group
    inc r15
    cmp r15, SN_DEPTH_MAX
    jae .Lsv_bad
    dec r14
    imul rax, r14, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 2
    jz .Lsv_bad
    mov rcx, [rax + SF_group]
    cmp rcx, [r13 + SF_group]
    je .Lsv_bad
    mov rcx, [r13 + SF_start]
    cmp rcx, [rax + SF_start]
    jb .Lsv_bad
    mov rcx, [r13 + SF_end]
    cmp rcx, [rax + SF_end]
    ja .Lsv_bad
    mov r14, [rax + SF_parent]
    jmp 3b
.Lsv_group:
    mov r14, [r13 + SF_group]
    test r14, r14
    jnz .Lsv_find_group
    test qword ptr [r13 + SF_flags], 64
    jnz .Lsv_bad
    cmp qword ptr [rsp], 0
    jne .Lsv_bad
    mov rax, [r13 + SF_start]
    mov [rbx + SN_final], rax
    mov rcx, [r13 + SF_end]
    mov [rbx + SN_finalend], rcx
    mov [rbx + SN_finalfield], r12
    cmp rax, rcx
    setb al
    movzx eax, al
    mov [rbx + SN_finalspan], rax
    mov qword ptr [rsp], 1
    jmp .Lsv_field_next
.Lsv_find_group:
    xor r15d, r15d
4:  cmp r15, [rbx + SN_ngroups]
    jae .Lsv_new_group
    imul rax, r15, SG_SIZE
    lea rax, [rbx + rax + SN_groups]
    cmp r14, [rax + SG_id]
    je .Lsv_mirror
    inc r15
    jmp 4b
.Lsv_new_group:
    test qword ptr [r13 + SF_flags], 64
    jnz .Lsv_bad
    cmp r15, SN_GROUPS_MAX
    jae .Lsv_bad
    imul rax, r15, SG_SIZE
    lea rax, [rbx + rax + SN_groups]
    mov [rax + SG_id], r14
    mov [rax + SG_primary], r12
    mov qword ptr [rax + SG_alive], 1
    mov qword ptr [rax + SG_dirty], 0
    mov qword ptr [rax + SG_choice], 0
    or qword ptr [r13 + SF_flags], 2
    inc qword ptr [rbx + SN_ngroups]
    jmp .Lsv_group_index
.Lsv_mirror:
    mov rax, [rax + SG_primary]
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov rcx, [rax + SF_end]
    sub rcx, [rax + SF_start]
    mov rdx, [r13 + SF_end]
    sub rdx, [r13 + SF_start]
    cmp rcx, rdx
    jne .Lsv_unequal
    test rcx, rcx
    jz .Lsv_equal
    mov rdi, [rbx + SN_text]
    mov rsi, rdi
    add rdi, [rax + SF_start]
    add rsi, [r13 + SF_start]
    repe cmpsb
    jne .Lsv_unequal
.Lsv_equal:
    test qword ptr [r13 + SF_flags], 64
    jnz .Lsv_bad
    jmp .Lsv_group_index
.Lsv_unequal:
    test qword ptr [r13 + SF_flags], 64
    jz .Lsv_bad
.Lsv_group_index:
    mov [r13 + SF_gindex], r15
.Lsv_field_next:
    inc r12
    jmp .Lsv_field
.Lsv_pairs_begin:
    xor r12d, r12d
.Lsv_pair_outer:
    cmp r12, [rbx + SN_nfields]
    jae .Lsv_graph
    imul r13, r12, SF_SIZE
    lea r13, [rbx + r13 + SN_fields]
    xor r14d, r14d
.Lsv_pair_inner:
    cmp r14, r12
    jae .Lsv_pair_next
    imul r15, r14, SF_SIZE
    lea r15, [rbx + r15 + SN_fields]
    cmp qword ptr [r13 + SF_group], 0
    je .Lsv_pair_skip
    cmp qword ptr [r15 + SF_group], 0
    je .Lsv_pair_skip
    mov rax, [r13 + SF_start]
    cmp rax, [r15 + SF_end]
    jae .Lsv_pair_skip
    mov rax, [r15 + SF_start]
    cmp rax, [r13 + SF_end]
    jae .Lsv_pair_skip
    mov rax, [r13 + SF_group]
    cmp rax, [r15 + SF_group]
    je .Lsv_bad
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call snippet_ancestor
    test eax, eax
    jnz .Lsv_pair_skip
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call snippet_ancestor
    test eax, eax
    jz .Lsv_bad
.Lsv_pair_skip:
    inc r14
    jmp .Lsv_pair_inner
.Lsv_pair_next:
    inc r12
    jmp .Lsv_pair_outer
.Lsv_graph:
    mov rdi, rbx
    call snippet_order
    test eax, eax
    jz .Lsv_bad
    xor ecx, ecx
1:  cmp rcx, [rbx + SN_nfields]
    jae 2f
    imul rax, rcx, SF_SIZE
    and qword ptr [rbx + rax + SN_fields + SF_flags], -65
    inc rcx
    jmp 1b
2:  mov eax, 1
    EPILOGUE
.Lsv_bad:
    mov qword ptr [rbx + SN_valid], 0
    xor eax, eax
    EPILOGUE

# snippet_forget(doc): accepted text survives; only field state is released
FN snippet_forget
    test rdi, rdi
    jz 9f
    mov rax, [rdi + DOC_snippet]
    mov qword ptr [rdi + DOC_snippet], 0
    test rax, rax
    jz 9f
    mov rdi, rax
    jmp snippet_free_chain
9:  ret

FN snippet_free_chain
    PROLOGUE
    mov rbx, rdi
1:  test rbx, rbx
    jz 9f
    mov r12, [rbx + SN_parent]
    mov rdi, rbx
    call snippet_free_node
    mov rbx, r12
    jmp 1b
9:  EPILOGUE

# An independently owned copy is used for whole-chain propagation preflight.
FN snippet_clone_chain
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d             # previous (inner) clone
    xor r13d, r13d             # top clone
1:  test rbx, rbx
    jz 9f
    mov rdi, rbx
    mov esi, SN_SIZE
    call mem_dup
    mov rcx, [rax + SN_choice]
    test rcx, rcx
    jz 4f
    inc qword ptr [rcx + SC_refs]
4:  mov rcx, [rax + SN_transform]
    test rcx, rcx
    jz 5f
    inc qword ptr [rcx + SC_refs]
5:  mov rcx, [rax + SN_indent]
    test rcx, rcx
    jz 6f
    inc qword ptr [rcx + SC_refs]
6:  mov qword ptr [rax + SN_parent], 0
    mov [rax + SN_child], r12
    test r12, r12
    jz 2f
    mov [r12 + SN_parent], rax
    jmp 3f
2:  mov r13, rax
3:  mov r12, rax
    mov rbx, [rbx + SN_parent]
    jmp 1b
9:  mov rax, r13
    EPILOGUE

# Pop only the innermost session after its final stop; the parent remains paused at its group.
FN snippet_pop
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DOC_snippet]
    test r12, r12
    jz 9f
    mov rax, [r12 + SN_parent]
    mov [rbx + DOC_snippet], rax
    test rax, rax
    jz 1f
    mov qword ptr [rax + SN_child], 0
    mov qword ptr [rax + SN_lastrecord], -1
1:  mov rdi, [rbx + DOC_snippet]
    call snippet_activate
    mov qword ptr [rbx + DOC_lastkind], EK_OTHER
    mov rdi, r12
    call snippet_free_node
9:  EPILOGUE

# snippet_can_nest(doc, candidate or 0) -> live top within aggregate bounds, else zero.
# Callers check every edit range before opening a scope or discarding an old chain.
FN snippet_can_nest
    PROLOGUE
    mov r12, rsi
    call snippet_check
    mov rbx, rax
    test rax, rax
    jz 9f
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    test r12, r12
    jz 1f
    cmp qword ptr [r12 + SN_ngroups], 0
    je 1f
    inc r8
    mov rdx, [r12 + SN_nfields]
    mov rcx, [r12 + SN_ngroups]
    mov r9, [r12 + SN_choicebytes]
    add r9, [r12 + SN_transformbytes]
    jc 8f
    add r9, [r12 + SN_indentbytes]
    jc 8f
    cmp r9, SN_BYTES_MAX
    ja 8f
1:  test rax, rax
    jz 3f
    inc r8
    add rdx, [rax + SN_nfields]
    add rcx, [rax + SN_ngroups]
    add r9, [rax + SN_choicebytes]
    jc 8f
    add r9, [rax + SN_transformbytes]
    jc 8f
    add r9, [rax + SN_indentbytes]
    jc 8f
    cmp r9, SN_BYTES_MAX
    ja 8f
    cmp r8, SN_SESSIONS_MAX
    ja 8f
    cmp rdx, SN_FIELDS_MAX
    ja 8f
    cmp rcx, SN_GROUPS_MAX
    ja 8f
    mov rax, [rax + SN_parent]
    jmp 1b
3:  mov rax, rbx
    EPILOGUE
8:  xor ebx, ebx
9:  mov rax, rbx
    EPILOGUE

# snippet_range_inside(state, start, end) -> 1 when a whole edit fits its active primary.
FN snippet_range_inside
    mov rax, [rdi + SN_active]
    cmp rax, [rdi + SN_nfields]
    jae 8f
    imul rax, rax, SF_SIZE
    lea rax, [rdi + rax + SN_fields]
    cmp rsi, [rax + SF_start]
    jb 8f
    cmp rdx, [rax + SF_end]
    ja 8f
    cmp rsi, rdx
    ja 8f
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# snippet_check(doc) -> state when its active field still owns the selection
FN snippet_check
    test rdi, rdi
    jz 8f
    mov rax, [rdi + DOC_snippet]
    test rax, rax
    jz 8f
    mov rcx, [rdi + DOC_id]
    cmp rcx, [rax + SN_docid]
    jne 7f
    test dword ptr [rdi + DOC_flags], DF_READONLY
    jnz 7f
    mov rcx, [rax + SN_active]
    cmp rcx, [rax + SN_nfields]
    jae 7f
    imul rcx, rcx, SF_SIZE
    lea rcx, [rax + rcx + SN_fields]
    test qword ptr [rcx + SF_flags], 1
    jz 7f
    mov rdx, [rdi + DOC_cur]
    cmp rdx, [rcx + SF_start]
    jb 7f
    cmp rdx, [rcx + SF_end]
    ja 7f
    mov rdx, [rdi + DOC_anchor]
    cmp rdx, [rcx + SF_start]
    jb 7f
    cmp rdx, [rcx + SF_end]
    ja 7f
    ret
7:  push rdi
    call snippet_forget
    pop rdi
8:  xor eax, eax
    ret

# snippet_step(doc, direction): choose next/previous numeric group, next at end finishes
FN snippet_step
    PROLOGUE 16
    mov rbx, rdi
    mov rax, [rdi + DOC_undo + VEC_len]
    mov [rsp], rax
    movsxd r12, esi
    mov r13, [rbx + DOC_snippet]
    test r13, r13
    jz .Lss_none
    mov rax, [r13 + SN_active]
    cmp rax, [r13 + SN_nfields]
    jae .Lss_transform_done
    mov rdi, rbx
    call snippet_transform_leave
    test eax, eax
    jnz .Lss_transform_done
    mov rdi, rbx
    call snippet_forget
    jmp .Lss_touch
.Lss_transform_done:
    mov rax, [r13 + SN_active]
    mov r14, -1
    cmp rax, [r13 + SN_nfields]
    jae 1f
    imul rax, rax, SF_SIZE
    mov r14, [r13 + rax + SN_fields + SF_group]
1:  mov r15, -1
    xor ecx, ecx
    mov r8, 2147483648
    test r12, r12
    jns .Lss_group
    xor r8d, r8d
.Lss_group:
    cmp rcx, [r13 + SN_ngroups]
    jae .Lss_found
    imul rax, rcx, SG_SIZE
    lea rax, [r13 + rax + SN_groups]
    cmp qword ptr [rax + SG_alive], 0
    je .Lss_skip
    mov rdx, [rax + SG_id]
    test r12, r12
    js 2f
    cmp r14, -1
    je 3f
    cmp rdx, r14
    jbe .Lss_skip
3:  cmp rdx, r8
    jae .Lss_skip
    jmp 4f
2:  cmp rdx, r14
    jae .Lss_skip
    cmp rdx, r8
    jbe .Lss_skip
4:  mov r8, rdx
    mov r15, [rax + SG_primary]
.Lss_skip:
    inc rcx
    jmp .Lss_group
.Lss_found:
    cmp r15, -1
    jne .Lss_select
    test r12, r12
    jns .Lss_finish
    mov r15, [r13 + SN_active]
    cmp r15, [r13 + SN_nfields]
    jb .Lss_select           # backward at the first field restores its full selection
    jmp .Lss_handled
.Lss_finish:
    mov rax, [r13 + SN_final]
    mov [rbx + DOC_anchor], rax
    mov rax, [r13 + SN_finalend]
    mov [rbx + DOC_cur], rax
    mov rdi, rbx
    call snippet_pop
    jmp .Lss_touch
.Lss_select:
    mov [r13 + SN_active], r15
    mov qword ptr [r13 + SN_lastrecord], -1
    mov qword ptr [rbx + DOC_lastkind], EK_OTHER
    imul rax, r15, SF_SIZE
    lea rax, [r13 + rax + SN_fields]
    mov rcx, [rax + SF_start]
    mov [rbx + DOC_anchor], rcx
    mov rcx, [rax + SF_end]
    mov [rbx + DOC_cur], rcx
    mov rdi, r13
    call snippet_activate
.Lss_touch:
    mov rdi, rbx
    mov rsi, [rsp]
    call snippet_record_after
    mov qword ptr [rbx + DOC_prefx], -1
    mov dword ptr [rip + g_dirty], 1
    cmp rbx, [rip + g_doc]
    jne .Lss_handled
    call ed_touch
.Lss_handled:
    mov eax, 1
    EPILOGUE
.Lss_none:
    xor eax, eax
    EPILOGUE

# snippet_attach(doc, candidate, inserted start): takes ownership after successful insertion
FN snippet_attach
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call snippet_forget
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call snippet_push
    EPILOGUE

# Validated insertion has already mapped/propagated the old top; retain it under new fields.
FN snippet_push
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [r12 + SN_valid], 0
    je .Lsa_discard
    mov rax, [rbx + DOC_id]
    mov [r12 + SN_docid], rax
    mov qword ptr [r12 + SN_text], 0
    add [r12 + SN_final], r13
    add [r12 + SN_finalend], r13
    xor ecx, ecx
1:  cmp rcx, [r12 + SN_nfields]
    jae 2f
    imul rax, rcx, SF_SIZE
    lea rax, [r12 + rax + SN_fields]
    add [rax + SF_start], r13
    add [rax + SF_end], r13
    inc rcx
    jmp 1b
2:  cmp qword ptr [r12 + SN_nfields], 0
    je .Lsa_discard
    mov rax, [rbx + DOC_snippet]
    mov [r12 + SN_parent], rax
    test rax, rax
    jz 3f
    mov [rax + SN_child], r12
3:
    mov [rbx + DOC_snippet], r12
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    EPILOGUE
.Lsa_discard:
    mov rdi, r12
    call snippet_free_node
    EPILOGUE

# snippet_order(state): recompute propagation after retiring fields, without reviving them
FN snippet_order
    xor esi, esi
    jmp snippet_order_limited
FN snippet_order_limited
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp + 8], rsi
    mov qword ptr [rsp], 0
    lea rdi, [rbx + SN_edges]
    xor esi, esi
    mov edx, SN_GROUPS_MAX * SN_GROUPS_MAX + 16 * SN_GROUPS_MAX
    call memset
    xor r12d, r12d
.Lso_edge_field:
    mov rdi, [rsp + 8]
    call snippet_deadline_optional
    test eax, eax
    jz .Lso_bad
    cmp r12, [rbx + SN_nfields]
    jae .Lso_queue
    imul rax, r12, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jz .Lso_edge_next
    cmp qword ptr [rax + SF_group], 0
    je .Lso_edge_next
    mov r13, [rax + SF_gindex]
    mov r14, [rax + SF_parent]
.Lso_edge_parent:
    test r14, r14
    jz .Lso_edge_next
    dec r14
    imul rax, r14, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jz .Lso_bad
    mov r15, [rax + SF_gindex]
    imul rcx, r13, SN_GROUPS_MAX
    add rcx, r15
    cmp byte ptr [rbx + rcx + SN_edges], 0
    jne 5f
    mov byte ptr [rbx + rcx + SN_edges], 1
    inc qword ptr [rbx + r15*8 + SN_degree]
5:  mov r14, [rax + SF_parent]
    jmp .Lso_edge_parent
.Lso_edge_next:
    inc r12
    jmp .Lso_edge_field
.Lso_queue:
    xor r12d, r12d
    xor r13d, r13d
6:  cmp r12, [rbx + SN_ngroups]
    jae .Lso_topo_begin
    imul rax, r12, SG_SIZE
    cmp qword ptr [rbx + rax + SN_groups + SG_alive], 0
    je 7f
    inc qword ptr [rsp]
    cmp qword ptr [rbx + r12*8 + SN_degree], 0
    jne 7f
    mov [rbx + r13*8 + SN_topo], r12
    inc r13
7:  inc r12
    jmp 6b
.Lso_topo_begin:
    xor r12d, r12d
.Lso_topo_outer:
    mov rdi, [rsp + 8]
    call snippet_deadline_optional
    test eax, eax
    jz .Lso_bad
    cmp r12, r13
    jae .Lso_topo_end
    mov rax, [rbx + r12*8 + SN_topo]
    imul r14, rax, SN_GROUPS_MAX
    lea r14, [rbx + r14 + SN_edges]
    xor r15d, r15d
8:  cmp r15, [rbx + SN_ngroups]
    jae .Lso_topo_next
    cmp byte ptr [r14 + r15], 0
    je 9f
    dec qword ptr [rbx + r15*8 + SN_degree]
    jnz 9f
    mov [rbx + r13*8 + SN_topo], r15
    inc r13
9:  inc r15
    jmp 8b
.Lso_topo_next:
    inc r12
    jmp .Lso_topo_outer
.Lso_topo_end:
    cmp r13, [rsp]
    jne .Lso_bad
    mov [rbx + SN_ntopo], r13
    mov eax, 1
    EPILOGUE
.Lso_bad:
    mov qword ptr [rbx + SN_valid], 0
    xor eax, eax
    EPILOGUE
