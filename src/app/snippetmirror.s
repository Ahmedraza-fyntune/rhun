# The simulation and mutation passes use the same propagation and marker operations.
.include "rhun.inc"
.text

# snippet_propagate(state, doc or 0, aggregate budget pointer, optional RX): 0 simulates
# -> 1 if the whole propagation fits, 0 before mutation when called for preflight
FN snippet_propagate
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + 80], rcx
    mov [rsp], rdx             # shared aggregate mirror insertion bytes
    mov qword ptr [rsp + 8], 0  # copied primary bytes for this group
    lea rdi, [rbx + SN_done]
    xor esi, esi
    mov edx, SN_FIELDS_MAX
    call memset
    xor r13d, r13d
.Lsmp_group:
    mov rdi, [rsp + 80]
    call snippet_deadline_optional
    test eax, eax
    jz .Lsmp_bad
    cmp r13, [rbx + SN_ntopo]
    jae .Lsmp_ok
    mov r14, [rbx + r13*8 + SN_topo]
    imul rax, r14, SG_SIZE
    lea rax, [rbx + rax + SN_groups]
    mov [rsp + 16], rax
    cmp qword ptr [rax + SG_alive], 0
    je .Lsmp_next_group
    cmp qword ptr [rax + SG_dirty], 0
    je .Lsmp_next_group
    mov rcx, [rax + SG_primary]
    mov [rsp + 24], rcx
    imul rax, rcx, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov r15, [rax + SF_end]
    sub r15, [rax + SF_start]
.Lsmp_choose:
    mov rdi, [rsp + 80]
    call snippet_deadline_optional
    test eax, eax
    jz .Lsmp_bad
    mov qword ptr [rsp + 32], -1
    mov qword ptr [rsp + 64], 0
    xor ecx, ecx
1:  cmp rcx, [rbx + SN_nfields]
    jae .Lsmp_chosen
    cmp byte ptr [rbx + rcx + SN_done], 0
    jne 4f
    imul rax, rcx, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    test qword ptr [rax + SF_flags], 1
    jz 4f
    test qword ptr [rax + SF_flags], 2
    jnz 4f
    cmp qword ptr [rax + SF_group], 0
    je 4f
    cmp [rax + SF_gindex], r14
    jne 4f
    mov rdx, [rax + SF_start]
    cmp qword ptr [rsp + 32], -1
    je 3f
    cmp rdx, [rsp + 64]
    jb 4f
3:  mov [rsp + 64], rdx
    mov [rsp + 32], rcx         # descending position, then descending record index
4:  inc rcx
    jmp 1b
.Lsmp_chosen:
    mov rax, [rsp + 32]
    cmp rax, -1
    je .Lsmp_group_done
    mov byte ptr [rbx + rax + SN_done], 1
    mov rdx, [rsp]
    mov rcx, [rdx]
    add rcx, r15
    jc .Lsmp_bad
    cmp rcx, SN_BYTES_MAX
    ja .Lsmp_bad
    mov [rdx], rcx
    test r12, r12
    jz .Lsmp_replace
    test r15, r15
    jz .Lsmp_replace
    cmp qword ptr [rsp + 8], 0
    jne .Lsmp_replace
    mov rax, [rsp + 24]
    imul rax, rax, SF_SIZE
    mov rsi, [rbx + rax + SN_fields + SF_start]
    mov rdi, r12
    mov rdx, r15
    call doc_range
    mov rdi, rax
    mov rsi, r15
    call mem_dup
    mov [rsp + 8], rax
.Lsmp_replace:
    mov rax, [rsp + 32]
    imul rax, rax, SF_SIZE
    lea rax, [rbx + rax + SN_fields]
    mov [rsp + 40], rax
    mov rsi, [rax + SF_start]
    mov [rsp + 48], rsi
    mov rdx, [rax + SF_end]
    mov rcx, rdx
    sub rcx, rsi
    mov [rsp + 56], rcx
    mov rdi, rbx
    call snippet_chain_replace_mark
    cmp qword ptr [rsp + 56], 0
    je .Lsmp_insert
    test r12, r12
    jz 5f
    mov rdi, r12
    mov rsi, [rsp + 48]
    mov rdx, [rsp + 56]
    mov ecx, EK_OTHER
    call doc_delete
5:  mov rdi, rbx
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 48]
    mov rcx, [rsp + 56]
    xor r8d, r8d
    call snippet_map_chain
.Lsmp_insert:
    test r15, r15
    jz .Lsmp_replaced
    test r12, r12
    jz 6f
    mov rdi, r12
    mov rsi, [rsp + 48]
    mov rdx, [rsp + 8]
    mov rcx, r15
    mov r8d, EK_OTHER
    call doc_insert
6:  mov rdi, rbx
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 48]
    xor ecx, ecx
    mov r8, r15
    call snippet_map_chain
.Lsmp_replaced:
    mov rdi, rbx
    call snippet_chain_replace_clear
    jmp .Lsmp_choose
.Lsmp_group_done:
    mov rax, [rsp + 16]
    mov qword ptr [rax + SG_dirty], 0
    mov rdi, [rsp + 8]
    call mem_free
    mov qword ptr [rsp + 8], 0
.Lsmp_next_group:
    inc r13
    jmp .Lsmp_group
.Lsmp_bad:
    mov rdi, [rsp + 8]
    call mem_free
    xor eax, eax
    EPILOGUE
.Lsmp_ok:
    mov eax, 1
    EPILOGUE

# snippet_flush(doc): mirror one completed user operation, retaining its cursor and undo group
FN snippet_flush
    PROLOGUE 80
    mov rbx, rdi
    call snippet_check
    test rax, rax
    jz .Lsf_done
    mov r12, rax
    mov rdi, rax
    call snippet_clone_chain
    mov r13, rax
    mov rdi, rax
    xor esi, esi
    call snippet_propagate_chain
    mov r14d, eax
    mov rdi, r13
    call snippet_free_chain
    test r14d, r14d
    jz .Lsf_cancel
    mov rax, [r12 + SN_active]
    imul rax, rax, SF_SIZE
    lea r13, [r12 + rax + SN_fields]
    mov rax, [rbx + DOC_cur]
    sub rax, [r13 + SF_start]
    mov [rsp], rax
    mov rax, [rbx + DOC_anchor]
    sub rax, [r13 + SF_start]
    mov [rsp + 8], rax
    mov rax, [r12 + SN_lastpos]
    sub rax, [r13 + SF_start]
    mov [rsp + 16], rax
    mov eax, [rbx + DOC_flags]
    and eax, 1
    mov [rsp + 24], rax
    mov rax, [rbx + DOC_lastkind]
    mov [rsp + 32], rax
    mov rax, [rbx + DOC_lastedit]
    mov [rsp + 40], rax
    or dword ptr [rbx + DOC_flags], 1
    mov qword ptr [r12 + SN_mutating], 1
    mov rdi, r12
    mov rsi, rbx
    call snippet_propagate_chain
    mov [rsp + 48], rax
    mov qword ptr [r12 + SN_mutating], 0
    and dword ptr [rbx + DOC_flags], -2
    mov eax, [rsp + 24]
    or [rbx + DOC_flags], eax
    mov rax, [rsp + 32]
    mov [rbx + DOC_lastkind], rax
    mov rax, [rsp + 40]
    mov [rbx + DOC_lastedit], rax
    mov rcx, [r13 + SF_start]
    mov rax, [rsp]
    add rax, rcx
    mov [rbx + DOC_cur], rax
    mov rax, [rsp + 8]
    add rax, rcx
    mov [rbx + DOC_anchor], rax
    cmp qword ptr [r12 + SN_lastrecord], -1
    je 1f
    add rcx, [rsp + 16]
    mov [r12 + SN_lastpos], rcx
1:  cmp qword ptr [rsp + 48], 0
    je .Lsf_cancel
    mov dword ptr [rip + g_dirty], 1
    cmp rbx, [rip + g_doc]
    jne .Lsf_done
    call ed_touch
    jmp .Lsf_done
.Lsf_cancel:
    mov rdi, rbx
    call snippet_forget
.Lsf_done:
    EPILOGUE
