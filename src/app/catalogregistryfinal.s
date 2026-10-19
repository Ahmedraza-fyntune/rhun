# Final immutable views and independent supplier ownership before input pruning.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.text
FN registry_final_view_one
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + RW_stage]
    test rax, rax
    jz .Lrgfv_grammar
    cmp rax, 1
    je .Lrgfv_builtin
    cmp rax, 2
    je .Lrgfv_candidates
    cmp rax, 3
    je .Lrgfv_header
    cmp rax, 4
    je .Lrgfv_scratch
    jmp .Lrgfv_bad
.Lrgfv_grammar:
    mov rcx, [rbx + RG_index]
    cmp rcx, [rbx + RG_ngrammar]
    jae .Lrgfv_advance
    imul rax, rcx, GRR_SIZE
    add rax, [rbx + RG_grammars]
    mov rax, [rax + GRR_gr]
    mov rdx, [rbx + RG_grammar_view]
    mov [rdx + rcx*8], rax
    inc qword ptr [rbx + RG_index]
    jmp .Lrgfv_pending
.Lrgfv_builtin:
    mov rcx, [rbx + RG_index]
    mov r12, [rbx + RG_base]
    cmp rcx, [r12 + RB_nbuiltin]
    jae .Lrgfv_advance
    mov rax, [r12 + RB_builtins]
    mov r13, [rax + rcx*8]
    mov rcx, [rbx + RG_ngrammar]
    cmp rcx, [rbx + RW_grcap]
    jae .Lrgfv_bad
    imul rax, rcx, GRR_SIZE
    add rax, [rbx + RG_grammars]
    mov [rax + GRR_gr], r13
    mov qword ptr [rax + GRR_supplier], -1
    mov rdx, [rbx + RG_grammar_view]
    mov [rdx + rcx*8], r13
    inc qword ptr [rbx + RG_ngrammar]
    inc qword ptr [rbx + RG_index]
    jmp .Lrgfv_pending
.Lrgfv_candidates:
    mov rcx, [rbx + RG_index]
    cmp rcx, [rbx + RG_ntheme]
    jae .Lrgfv_advance
    imul rax, rcx, TH_SIZE
    add rax, [rbx + RG_themes]
    mov rdx, [rax + TH_id]
    imul rax, rcx, TM_SIZE
    add rax, [rbx + RG_meta]
    mov rsi, [rax + TM_idlen]
    shl rcx, 4
    add rcx, [rbx + RG_candidates]
    mov [rcx], rdx
    mov [rcx + 8], rsi
    inc qword ptr [rbx + RG_index]
    jmp .Lrgfv_pending
.Lrgfv_header:
    lea r12, [rbx + RG_view]
    mov rax, [rbx + RG_grammar_view]
    mov [r12], rax
    mov rax, [rbx + RG_ngrammar]
    mov [r12 + 8], rax
    mov [r12 + 16], rax
    mov rax, [rbx + RG_themes]
    mov [r12 + 24], rax
    mov rax, [rbx + RG_ntheme]
    mov [r12 + 32], rax
    mov [r12 + 40], rax
    mov [r12 + 56], rax
    mov rax, [rbx + RG_candidates]
    mov [r12 + 48], rax
    mov rax, [rbx + RG_follow]
    mov [r12 + 64], rax
    mov rax, [rbx + RG_epoch]
    mov [r12 + 72], rax
    mov [r12 + 88], rax
    mov rax, [rbx + RG_meta]
    mov [r12 + 80], rax
    mov rax, [rbx + RG_base_version]
    mov [r12 + 96], rax
    inc qword ptr [rbx + RW_stage]
    jmp .Lrgfv_pending
.Lrgfv_scratch:
    lea rdi, [rbx - RD_PO_BACK]
    lea rsi, [rbx + RG_scratch_po]
    mov edx, 4
    call catalog_retire_drop
    test rax, rax
    js .Lrgfv_return
    mov qword ptr [rbx + RG_grammar_map], 0
    mov qword ptr [rbx + RG_theme_map], 0
    mov qword ptr [rbx + RG_phase], RG_FINAL_REFS
    mov qword ptr [rbx + RG_index], 0
    mov eax, 2
    EPILOGUE
.Lrgfv_advance:
    inc qword ptr [rbx + RW_stage]
    mov qword ptr [rbx + RG_index], 0
.Lrgfv_pending:
    mov eax, 1
.Lrgfv_return:
    EPILOGUE
.Lrgfv_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

FN registry_final_ref_one
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RG_index]
    cmp r12, [rbx + RG_ninput]
    jae .Lrgfr_drop
    imul r13, r12, RGS_SIZE
    add r13, [rbx + RG_inputs]
    mov rax, [r13 + RGS_grammars]
    or rax, [r13 + RGS_themes]
    jz .Lrgfr_skip
    mov rdi, [r13 + RGS_ep]
    call ext_prepare_retain
    test rax, rax
    js .Lrgfr_return
    imul r14, r12, RGS_SIZE
    add r14, [rbx + RG_suppliers]
    mov rax, [r13 + RGS_ep]
    mov [r14 + RGS_ep], rax
    mov [r14 + RGS_ordinal], r12
    mov rax, [r13 + RGS_grammars]
    mov [r14 + RGS_grammars], rax
    mov rax, [r13 + RGS_themes]
    mov [r14 + RGS_themes], rax
    inc qword ptr [rbx + RG_index]
    mov eax, 2
    EPILOGUE
.Lrgfr_skip:
    inc qword ptr [rbx + RG_index]
    mov eax, 1
    EPILOGUE
.Lrgfr_drop:
    mov qword ptr [rbx + RG_phase], RG_DROP_INPUT
    mov qword ptr [rbx + RG_index], 0
    mov eax, 1
.Lrgfr_return:
    EPILOGUE

FN registry_drop_input_one
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RG_index]
    cmp r12, [rbx + RG_ninput]
    jae .Lrgdi_ready
    imul rsi, r12, RGS_SIZE
    add rsi, [rbx + RG_inputs]
    lea rdi, [rbx - RD_PO_BACK]
    mov edx, 2
    call catalog_retire_drop
    test rax, rax
    js .Lrgdi_return
    inc qword ptr [rbx + RG_index]
    mov eax, 2
    EPILOGUE
.Lrgdi_ready:
    mov qword ptr [rbx + RG_phase], RG_READY
    mov qword ptr [rbx + PO_ready], 1
    xor eax, eax
.Lrgdi_return:
    EPILOGUE
