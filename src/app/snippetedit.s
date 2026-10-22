# Field marker mapping is shared by mirror preflight and actual document edits.
.include "rhun.inc"

.text

# snippet_replace_mark(state, start, end): retain original nonempty replacement boundaries
FN snippet_replace_mark
    mov qword ptr [rdi + SN_finalowner], -1
    mov [rdi + SN_repla], rsi
    mov [rdi + SN_replb], rdx
    xor eax, eax
    cmp rsi, rdx
    setb al
    mov [rdi + SN_replacing], rax
    xor ecx, ecx
1:  cmp rcx, [rdi + SN_nfields]
    jae 9f
    imul r8, rcx, SF_SIZE
    lea r8, [rdi + r8 + SN_fields]
    and qword ptr [r8 + SF_flags], 3
    test rax, rax
    jz 8f
    test qword ptr [r8 + SF_flags], 1
    jz 8f
    cmp [r8 + SF_start], rsi
    jne 2f
    or qword ptr [r8 + SF_flags], 4
2:  cmp [r8 + SF_start], rdx
    jne 3f
    or qword ptr [r8 + SF_flags], 8
3:  cmp [r8 + SF_end], rsi
    jne 4f
    or qword ptr [r8 + SF_flags], 16
4:  cmp [r8 + SF_end], rdx
    jne 8f
    or qword ptr [r8 + SF_flags], 32
8:  inc rcx
    jmp 1b
9:  ret

# snippet_replace_clear(state)
FN snippet_replace_clear
    mov qword ptr [rdi + SN_finalowner], -1
    mov qword ptr [rdi + SN_replacing], 0
    xor ecx, ecx
1:  cmp rcx, [rdi + SN_nfields]
    jae 9f
    imul rax, rcx, SF_SIZE
    and qword ptr [rdi + rax + SN_fields + SF_flags], 3
    inc rcx
    jmp 1b
9:  ret

# Map one endpoint through deletion [start,start+len), retaining its left boundary.
sn_delete_point:
    mov rax, rdi
    cmp rax, rsi
    jbe 9f
    lea rcx, [rsi + rdx]
    cmp rax, rcx
    jb 1f
    sub rax, rdx
    ret
1:  mov rax, rsi
9:  ret

# snippet_dirty(state, occurrence): the group and its primary ancestors need propagation
FN snippet_dirty
1:  imul rax, rsi, SF_SIZE
    lea rax, [rdi + rax + SN_fields]
    cmp qword ptr [rax + SF_group], 0
    je 2f
    mov rcx, [rax + SF_gindex]
    imul rcx, rcx, SG_SIZE
    mov qword ptr [rdi + rcx + SN_groups + SG_dirty], 1
2:  mov rsi, [rax + SF_parent]
    test rsi, rsi
    jz 9f
    dec rsi
    jmp 1b
9:  ret

# Retiring a primary retires its entire group, including mirrors outside its subtree.
sn_retire_group:
    imul rax, rsi, SG_SIZE
    mov qword ptr [rdi + rax + SN_groups + SG_alive], 0
    mov qword ptr [rdi + rax + SN_groups + SG_dirty], 0
    xor ecx, ecx
1:  cmp rcx, [rdi + SN_nfields]
    jae 9f
    imul rax, rcx, SF_SIZE
    lea rax, [rdi + rax + SN_fields]
    cmp qword ptr [rax + SF_group], 0
    je 8f
    cmp [rax + SF_gindex], rsi
    jne 8f
    and qword ptr [rax + SF_flags], -2
8:  inc rcx
    jmp 1b
9:  ret

# snippet_prune(state): remove orphan primaries/mirrors, preserve/reparent the final caret
FN snippet_prune
    xor esi, esi
    jmp snippet_prune_limited
FN snippet_prune_limited
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rsi
    xor r14d, r14d
.Lsp_again:
    inc r14
    cmp r14, SN_FIELDS_MAX
    ja .Lsp_bad
    xor r12d, r12d
    xor r13d, r13d
.Lsp_field:
    mov rdi, [rsp]
    call snippet_deadline_optional
    test eax, eax
    jz .Lsp_bad
    cmp r12, [rbx + SN_nfields]
    jae .Lsp_pass_end
    imul r15, r12, SF_SIZE
    lea r15, [rbx + r15 + SN_fields]
    test qword ptr [r15 + SF_flags], 1
    jz .Lsp_next
    mov rax, [r15 + SF_parent]
    test rax, rax
    jz .Lsp_next
    dec rax
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jnz .Lsp_next
    mov r13d, 1
    cmp qword ptr [r15 + SF_group], 0
    je .Lsp_final
    test qword ptr [r15 + SF_flags], 2
    jz .Lsp_mirror
    mov rdi, rbx
    mov rsi, [r15 + SF_gindex]
    call sn_retire_group
    jmp .Lsp_next
.Lsp_mirror:
    and qword ptr [r15 + SF_flags], -2
    jmp .Lsp_next
.Lsp_final:
    mov rcx, [rax + SF_parent]
    mov [r15 + SF_parent], rcx
    # Another pass reaches the nearest surviving ancestor if several were removed.
.Lsp_next:
    inc r12
    jmp .Lsp_field
.Lsp_pass_end:
    test r13, r13
    jnz .Lsp_again
    mov rdi, rbx
    mov rsi, [rsp]
    call snippet_order_limited
    EPILOGUE
.Lsp_bad:
    mov qword ptr [rbx + SN_valid], 0
    xor eax, eax
    EPILOGUE

# snippet_retire_touch(state, owner, position, deletion, insertion): before user mutation
# Editing through a descendant ends that descendant's links, retaining all of its text.
FN snippet_retire_touch
    xor r9d, r9d
    jmp snippet_retire_touch_limited
FN snippet_retire_touch_limited
    PROLOGUE 32
    mov [rsp + 16], r9
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    or rcx, r8
    jz .Lsrt_ok
    mov qword ptr [rsp], 0
.Lsrt_loop:
    mov rdi, [rsp + 16]
    call snippet_deadline_optional
    test eax, eax
    jz .Lsrt_timeout
    mov rsi, [rsp]
    cmp rsi, [rbx + SN_nfields]
    jae .Lsrt_prune
    imul r15, rsi, SF_SIZE
    lea r15, [rbx + r15 + SN_fields]
    test qword ptr [r15 + SF_flags], 1
    jz .Lsrt_next
    cmp qword ptr [r15 + SF_group], 0
    je .Lsrt_next
    cmp rsi, r12
    je .Lsrt_next
    mov rdi, rbx
    mov rdx, rsi
    mov rsi, r12
    call snippet_ancestor
    test eax, eax
    jz .Lsrt_next
    test r14, r14
    jz .Lsrt_insertion
    mov rax, [r15 + SF_start]
    cmp rax, [r15 + SF_end]
    je .Lsrt_point
    lea rcx, [r13 + r14]
    cmp rax, rcx
    jae .Lsrt_next
    cmp [r15 + SF_end], r13
    jbe .Lsrt_next
    jmp .Lsrt_retire
.Lsrt_point:
    cmp rax, r13
    jb .Lsrt_next
    lea rcx, [r13 + r14]
    cmp rax, rcx
    ja .Lsrt_next
    jmp .Lsrt_retire
.Lsrt_insertion:
    cmp r13, [r15 + SF_start]
    jb .Lsrt_next
    cmp r13, [r15 + SF_end]
    ja .Lsrt_next
.Lsrt_retire:
    test qword ptr [r15 + SF_flags], 2
    jz .Lsrt_mirror
    mov rdi, rbx
    mov rsi, [r15 + SF_gindex]
    call sn_retire_group
    jmp .Lsrt_next
.Lsrt_mirror:
    and qword ptr [r15 + SF_flags], -2
.Lsrt_next:
    inc qword ptr [rsp]
    jmp .Lsrt_loop
.Lsrt_prune:
    mov rdi, rbx
    mov rsi, [rsp + 16]
    call snippet_prune_limited
    EPILOGUE
.Lsrt_timeout:
    xor eax, eax
    EPILOGUE
.Lsrt_ok:
    mov eax, 1
    EPILOGUE

# snippet_map(state, owner occurrence, position, deleted bytes, inserted bytes)
# Replacement tags survive its deletion and paired insertion. Owner/ancestor ranges grow;
# unrelated touching ranges and coincident empty stops keep their specified side affinity.
FN snippet_map
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rax, [rbx + SN_final]
    cmp rax, [rbx + SN_finalend]
    setb al
    movzx eax, al
    mov [rsp + 40], rax        # was a span before this raw edit
    mov rdi, rbx
    mov rsi, r12
    call sn_final_owns
    cmp qword ptr [rbx + SN_replacing], 0
    je 0f
    cmp qword ptr [rbx + SN_finalowner], -1
    jne 1f
    mov [rbx + SN_finalowner], rax
1:  mov rax, [rbx + SN_finalowner]
0:  mov [rsp + 32], rax
    mov qword ptr [rsp], 0
.Lsm_loop:
    mov rax, [rsp]
    cmp rax, [rbx + SN_nfields]
    jae .Lsm_final
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov [rsp + 8], rax
    test qword ptr [rax + SF_flags], 1
    jz .Lsm_next
    cmp qword ptr [rax + SF_group], 0
    jne .Lsm_regular_owner
    mov rcx, [rsp + 32]
    mov [rsp + 16], rcx
    jmp .Lsm_delete
.Lsm_regular_owner:
    mov qword ptr [rsp + 16], 1
    cmp [rsp], r12
    je .Lsm_delete
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, r12
    call snippet_ancestor
    mov [rsp + 16], rax
.Lsm_delete:
    test r14, r14
    jz .Lsm_insert
    mov rax, [rsp + 8]
    mov rdi, [rax + SF_start]
    mov rsi, r13
    mov rdx, r14
    call sn_delete_point
    mov rcx, [rsp + 8]
    mov [rcx + SF_start], rax
    mov rdi, [rcx + SF_end]
    mov rsi, r13
    mov rdx, r14
    call sn_delete_point
    mov rcx, [rsp + 8]
    mov [rcx + SF_end], rax
.Lsm_insert:
    test r15, r15
    jz .Lsm_next
    mov rdx, [rsp + 8]
    mov r8, [rdx + SF_start]
    mov r9, [rdx + SF_end]
    xor eax, eax
    cmp r8, r9
    sete al
    mov [rsp + 24], rax         # empty after deletion; boundary tags take precedence
    cmp r8, r13
    jb .Lsm_end
    ja .Lsm_start_right
    # Final spans honor original replacement boundaries before synthetic ownership.
    cmp qword ptr [rdx + SF_group], 0
    jne .Lsm_start_owner
    cmp qword ptr [rbx + SN_finalspan], 0
    je .Lsm_start_right
    cmp qword ptr [rbx + SN_replacing], 0
    je .Lsm_start_owner
    cmp r13, [rbx + SN_repla]
    jne .Lsm_start_owner
    test qword ptr [rdx + SF_flags], 8
    jnz .Lsm_start_right
    test qword ptr [rdx + SF_flags], 4
    jnz .Lsm_end
.Lsm_start_owner:
    cmp qword ptr [rsp + 16], 0
    jne .Lsm_end               # owner starts remain on the left
    cmp qword ptr [rbx + SN_replacing], 0
    je 1f
    cmp r13, [rbx + SN_repla]
    jne 1f
    test qword ptr [rdx + SF_flags], 4
    jnz .Lsm_end
    test qword ptr [rdx + SF_flags], 8
    jnz .Lsm_start_right
1:  cmp qword ptr [rsp + 24], 0
    je .Lsm_start_right
    cmp [rsp], r12
    jb .Lsm_end
.Lsm_start_right:
    add r8, r15
.Lsm_end:
    cmp r9, r13
    jb .Lsm_store
    ja .Lsm_end_right
    cmp qword ptr [rdx + SF_group], 0
    jne .Lsm_end_owner
    cmp qword ptr [rbx + SN_finalspan], 0
    je .Lsm_end_right
    cmp qword ptr [rbx + SN_replacing], 0
    je .Lsm_end_owner
    cmp r13, [rbx + SN_repla]
    jne .Lsm_end_owner
    test qword ptr [rdx + SF_flags], 16
    jnz .Lsm_store
    test qword ptr [rdx + SF_flags], 32
    jnz .Lsm_end_right
.Lsm_end_owner:
    cmp qword ptr [rsp + 16], 0
    jne .Lsm_end_right
    cmp qword ptr [rbx + SN_replacing], 0
    je 2f
    cmp r13, [rbx + SN_repla]
    jne 2f
    test qword ptr [rdx + SF_flags], 16
    jnz .Lsm_store
    test qword ptr [rdx + SF_flags], 32
    jnz .Lsm_end_right
2:  cmp qword ptr [rsp + 24], 0
    je .Lsm_store
    cmp [rsp], r12
    jb .Lsm_store
.Lsm_end_right:
    add r9, r15
.Lsm_store:
    mov [rdx + SF_start], r8
    mov [rdx + SF_end], r9
.Lsm_next:
    inc qword ptr [rsp]
    jmp .Lsm_loop
.Lsm_final:
    mov rax, [rbx + SN_finalfield]
    cmp rax, -1
    je .Lsm_implicit
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov rcx, [rax + SF_start]
    mov [rbx + SN_final], rcx
    mov rax, [rax + SF_end]
    mov [rbx + SN_finalend], rax
    cmp rcx, rax
    jne .Lsm_regrown
    cmp qword ptr [rsp + 40], 0
    je .Lsm_dirty
    test r14, r14
    jz .Lsm_dirty
    mov rax, -1
    cmp qword ptr [rsp + 32], 0
    je 4f
    mov rax, r12
4:  mov [rbx + SN_finalcollapseowner], rax
    jmp .Lsm_dirty
.Lsm_regrown:
    mov qword ptr [rbx + SN_finalcollapseowner], -1
    jmp .Lsm_dirty
.Lsm_implicit:
    mov rdi, [rbx + SN_final]
    mov rsi, r13
    mov rdx, r14
    call sn_delete_point
    cmp rax, r13
    jb 3f
    add rax, r15               # the implicit final caret always follows inserted text
3:  mov [rbx + SN_final], rax
    mov [rbx + SN_finalend], rax
.Lsm_dirty:
    mov rdi, rbx
    mov rsi, r12
    call snippet_dirty
    EPILOGUE

# Ownership is determined before any occurrence mapping. Collapsed spans keep their
# last deleting occurrence, rather than absorbing a different adjacent field.
sn_final_owns:
    cmp qword ptr [rdi + SN_finalspan], 0
    je 8f
    cmp rsi, [rdi + SN_nfields]
    jae 8f
    imul rcx, rsi, SF_SIZE
    lea rcx, [rdi + rcx + SN_fields]
    mov r8, [rdi + SN_final]
    mov r9, [rdi + SN_finalend]
    mov r10, [rcx + SF_start]
    mov r11, [rcx + SF_end]
    cmp r8, r9
    jne 1f
    cmp rsi, [rdi + SN_finalcollapseowner]
    jne 8f
    cmp r8, r10
    jb 8f
    cmp r8, r11
    ja 8f
    jmp 9f
1:  cmp r10, r11
    je 2f
    cmp r10, r9
    jae 8f
    cmp r8, r11
    jae 8f
    jmp 9f
2:  cmp r10, r8
    jb 8f
    cmp r10, r9
    ja 8f
9:  mov eax, 1
    ret
8:  xor eax, eax
    ret
