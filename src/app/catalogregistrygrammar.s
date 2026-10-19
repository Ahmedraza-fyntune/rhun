# Extension-only exact name replacement. User/builtin precedence is preserved.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.text
FN registry_grammar_one
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + RW_stage]
    test rax, rax
    jz .Lrgg_next
    cmp rax, 1
    je .Lrgg_map
    cmp rax, 2
    je .Lrgg_retain
    cmp rax, 3
    je .Lrgg_install
    cmp rax, 4
    je .Lrgg_drop
    jmp .Lrgg_bad
.Lrgg_next:
    mov r12, [rbx + RW_ep]
    cmp r12, [rbx + RG_ninput]
    jae .Lrgg_themes
    imul rax, r12, RGS_SIZE
    add rax, [rbx + RG_inputs]
    mov r13, [rax + RGS_ep]
    mov rcx, [rbx + RW_item]
    cmp rcx, [r13 + EP_grammars + VEC_len]
    jae .Lrgg_next_ep
    mov rax, [r13 + EP_grammars + VEC_ptr]
    mov r14, [rax + rcx*8]
    test r14, r14
    jz .Lrgg_bad
    cmp qword ptr [r14 + PO_ready], 1
    jne .Lrgg_bad
    cmp qword ptr [r14 + PO_error], 0
    jne .Lrgg_bad
    cmp [r14 + GP_gr + GR_owner], r14
    jne .Lrgg_bad
    mov rdx, [r14 + GP_name_len]
    cmp rdx, 2*1024*1024
    ja .Lrgg_bad
    mov [rbx + RW_current], r14
    mov rax, [rbx + RG_ngrammar]
    mov [rbx + RW_target], rax
    mov rsi, [r14 + GP_gr + GR_name]
    test rsi, rsi
    jz .Lrgg_no_name
    lea rcx, [rax + 1]
    cmp rcx, REG_ROW_CAP
    mov eax, REG_ROW_CAP
    cmova rcx, rax
    mov rdi, [rbx + RG_grammar_map]
    call registry_map_start
    test rax, rax
    js .Lrgg_return
    mov qword ptr [rbx + RW_stage], 1
    jmp .Lrgg_pending
.Lrgg_no_name:
    test rdx, rdx
    jnz .Lrgg_bad
    mov qword ptr [rbx + RW_stage], 2
    jmp .Lrgg_pending
.Lrgg_map:
    mov rdi, rbx
    mov rsi, [rbx + RG_grammar_map]
    call registry_map_one
    test rax, rax
    js .Lrgg_return
    jnz .Lrgg_pending
    dec rdx
    test rcx, rcx
    jnz 1f
    mov rdx, [rbx + RG_ngrammar]
1:  mov [rbx + RW_target], rdx
    mov qword ptr [rbx + RW_stage], 2
    jmp .Lrgg_pending
.Lrgg_retain:
    mov rax, [rbx + RW_target]
    cmp rax, [rbx + RG_ngrammar]
    ja .Lrgg_bad
    jb 2f
    mov rcx, [rbx + RG_base]
    add rax, [rcx + RB_nbuiltin]
    cmp rax, [rbx + RW_grcap]
    jae .Lrgg_resource
2:  mov rdi, [rbx + RW_current]
    call grammar_prepare_retain
    test rax, rax
    js .Lrgg_return
    mov rax, [rbx + RW_current]
    mov [rbx + RG_new_gp], rax
    mov qword ptr [rbx + RW_stage], 3
    mov eax, 2
    EPILOGUE
.Lrgg_install:
    mov r12, [rbx + RW_target]
    imul r13, r12, GRR_SIZE
    add r13, [rbx + RG_grammars]
    mov r14, [rbx + RG_new_gp]
    test r14, r14
    jz .Lrgg_bad
    mov r15, [r13 + GRR_gp]
    test r15, r15
    jz 3f
    mov rax, [r13 + GRR_supplier]
    cmp rax, [rbx + RG_ninput]
    jae .Lrgg_bad
    imul rax, rax, RGS_SIZE
    add rax, [rbx + RG_inputs]
    cmp qword ptr [rax + RGS_grammars], 0
    je .Lrgg_bad
    dec qword ptr [rax + RGS_grammars]
3:  mov [rbx + RG_old_gp], r15
    mov rax, [rbx + RW_ep]
    mov [r13 + GRR_supplier], rax
    imul rax, rax, RGS_SIZE
    add rax, [rbx + RG_inputs]
    inc qword ptr [rax + RGS_grammars]
    mov [r13 + GRR_gp], r14
    lea rax, [r14 + GP_gr]
    mov [r13 + GRR_gr], rax
    mov rax, [r14 + GP_name_len]
    mov [r13 + GRR_namelen], rax
    mov qword ptr [rbx + RG_new_gp], 0
    cmp r12, [rbx + RG_ngrammar]
    jne 4f
    inc qword ptr [rbx + RG_ngrammar]
4:  mov qword ptr [rbx + RW_stage], 4
    jmp .Lrgg_pending
.Lrgg_drop:
    cmp qword ptr [rbx + RG_old_gp], 0
    je .Lrgg_advance
    lea rdi, [rbx - RD_PO_BACK]
    lea rsi, [rbx + RG_old_gp]
    mov edx, 1
    call catalog_retire_drop
    test rax, rax
    js .Lrgg_return
    inc qword ptr [rbx + RW_item]
    mov qword ptr [rbx + RW_stage], 0
    mov eax, 2
    EPILOGUE
.Lrgg_advance:
    inc qword ptr [rbx + RW_item]
    mov qword ptr [rbx + RW_stage], 0
    jmp .Lrgg_pending
.Lrgg_next_ep:
    inc qword ptr [rbx + RW_ep]
    mov qword ptr [rbx + RW_item], 0
    jmp .Lrgg_pending
.Lrgg_themes:
    mov qword ptr [rbx + RG_phase], RG_THEME
    mov qword ptr [rbx + RW_ep], 0
    mov qword ptr [rbx + RW_item], 0
.Lrgg_pending:
    mov eax, 1
.Lrgg_return:
    EPILOGUE
.Lrgg_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lrgg_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE
