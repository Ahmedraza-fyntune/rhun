.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.text
FN registry_copy_base_one
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RG_base]
    mov rax, [rbx + RW_stage]
    test rax, rax
    jz .Lrgcb_user
    cmp rax, 1
    je .Lrgcb_theme
    cmp rax, 2
    je .Lrgcb_map
    jmp .Lrgcb_bad
.Lrgcb_user:
    mov rcx, [rbx + RG_index]
    cmp rcx, [r12 + RB_nuser]
    jae .Lrgcb_next
    mov rax, [r12 + RB_users]
    mov r13, [rax + rcx*8]
    imul rax, rcx, GRR_SIZE
    add rax, [rbx + RG_grammars]
    mov [rax + GRR_gr], r13
    mov qword ptr [rax + GRR_supplier], -1
    inc qword ptr [rbx + RG_ngrammar]
    inc qword ptr [rbx + RG_index]
    jmp .Lrgcb_pending
.Lrgcb_theme:
    mov r13, [rbx + RG_index]
    cmp r13, [r12 + RB_ntheme]
    jae .Lrgcb_grammar
    imul r14, r13, TH_SIZE
    mov rsi, [r12 + RB_themes]
    add rsi, r14
    mov rdi, [rbx + RG_themes]
    add rdi, r14
    mov edx, TH_SIZE
    call memcpy
    imul r14, r13, BTM_SIZE
    add r14, [r12 + RB_meta]
    imul r15, r13, TM_SIZE
    add r15, [rbx + RG_meta]
    mov rax, [r14 + BTM_kind]
    mov [r15 + TM_kind], rax
    mov qword ptr [r15 + TM_supplier], -1
    mov rax, [r14 + BTM_key]
    mov [r15 + TM_key], rax
    mov rax, [r14 + BTM_keylen]
    mov [r15 + TM_keylen], rax
    mov rax, [r14 + BTM_path]
    mov [r15 + TM_path], rax
    mov rax, [r14 + BTM_pathlen]
    mov [r15 + TM_pathlen], rax
    mov rax, [r14 + BTM_idlen]
    mov [r15 + TM_idlen], rax
    mov rax, [r14 + BTM_namelen]
    mov [r15 + TM_namelen], rax
    mov [r15 + TM_baseordinal], r13
    inc qword ptr [rbx + RG_ntheme]
    cmp qword ptr [r15 + TM_key], 0
    je .Lrgcb_theme_advance
    mov rdi, [rbx + RG_theme_map]
    mov rsi, [r15 + TM_key]
    mov rdx, [r15 + TM_keylen]
    lea rcx, [r13 + 1]
    call registry_map_start
    test rax, rax
    js .Lrgcb_return
    mov qword ptr [rbx + RW_stage], 2
    jmp .Lrgcb_pending
.Lrgcb_map:
    mov rdi, rbx
    mov rsi, [rbx + RG_theme_map]
    call registry_map_one
    test rax, rax
    js .Lrgcb_return
    jnz .Lrgcb_pending
.Lrgcb_theme_advance:
    mov qword ptr [rbx + RW_stage], 1
    inc qword ptr [rbx + RG_index]
    jmp .Lrgcb_pending
.Lrgcb_next:
    mov qword ptr [rbx + RW_stage], 1
    mov qword ptr [rbx + RG_index], 0
    jmp .Lrgcb_pending
.Lrgcb_grammar:
    mov qword ptr [rbx + RG_phase], RG_GRAMMAR
    mov qword ptr [rbx + RW_stage], 0
    mov qword ptr [rbx + RG_index], 0
.Lrgcb_pending:
    mov eax, 1
.Lrgcb_return:
    EPILOGUE
.Lrgcb_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE
