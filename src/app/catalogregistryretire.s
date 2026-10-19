# One ownership/cursor unit per callback, including cancellation of partial builds.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.text
# record, owned pointer cell, type1GP/2EP/3RB/4scratchPO/5initialEO.
FN catalog_retire_drop
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [r12]
    test rdi, rdi
    jz .Lcrd_pending
    cmp r13, 1
    je .Lcrd_po
    cmp r13, 2
    je .Lcrd_ep
    cmp r13, 3
    je .Lcrd_base
    cmp r13, 4
    je .Lcrd_po
    cmp r13, 5
    jne .Lcrd_bad
    mov rax, [rbx + RD_object]
    cmp [rax + PO_eo], rdi
    jne .Lcrd_bad
    call ext_prepare_owner_release_deferred
    jmp .Lcrd_result
.Lcrd_po:
    call prep_object_release_deferred
    jmp .Lcrd_result
.Lcrd_ep:
    call ext_prepare_release_deferred
    jmp .Lcrd_result
.Lcrd_base:
    call registry_base_release_deferred
.Lcrd_result:
    mov r14, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    call ext_prepare_retire_note_error
    cmp r15, 1
    jne .Lcrd_retained
    mov qword ptr [r12], 0
.Lcrd_pending:
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lcrd_retained:
    mov rax, r14
    test rax, rax
    js 1f
    mov rax, -EV_BAD_PREPARE
1:  mov rdx, r15
    test rdx, rdx
    jz 2f
    mov edx, 2
2:  EPILOGUE
.Lcrd_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    EPILOGUE

FN registry_retire_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + RD_phase]
    test rax, rax
    jz .Lrgr_old
    cmp rax, 1
    je .Lrgr_new
    cmp rax, 2
    je .Lrgr_grammars
    cmp rax, 3
    je .Lrgr_inputs
    cmp rax, 4
    je .Lrgr_suppliers
    cmp rax, 5
    je .Lrgr_scratch
    cmp rax, 6
    je .Lrgr_base
    cmp rax, 7
    je .Lrgr_eo
    cmp rax, 8
    je .Lrgr_handoff
    jmp .Lrgr_bad
.Lrgr_old:
    lea r13, [rbx + RG_old_gp]
    mov r14d, 1
    jmp .Lrgr_single
.Lrgr_new:
    lea r13, [rbx + RG_new_gp]
    mov r14d, 1
    jmp .Lrgr_single
.Lrgr_scratch:
    lea r13, [rbx + RG_scratch_po]
    mov r14d, 4
    jmp .Lrgr_single
.Lrgr_base:
    lea r13, [rbx + RG_base]
    mov r14d, 3
    jmp .Lrgr_single
.Lrgr_eo:
    lea r13, [rbx + RG_constructor_eo]
    mov r14d, 5
.Lrgr_single:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call catalog_retire_drop
    test rax, rax
    js .Lrgr_return
    jmp .Lrgr_advance
.Lrgr_grammars:
    mov rax, [rbx + RG_ngrammar]
    cmp rax, REG_ROW_CAP
    ja .Lrgr_bad
    mov r13, [r12 + RD_index]
    cmp r13, rax
    jae .Lrgr_advance
    mov rax, [rbx + RG_grammars]
    test rax, rax
    jz .Lrgr_bad
    imul rsi, r13, GRR_SIZE
    add rsi, rax
    add rsi, GRR_gp
    mov edx, 1
    jmp .Lrgr_row
.Lrgr_inputs:
    mov rax, [rbx + RG_inputs]
    jmp .Lrgr_ep_row
.Lrgr_suppliers:
    mov rax, [rbx + RG_suppliers]
    test rax, rax
    jz .Lrgr_advance
.Lrgr_ep_row:
    cmp qword ptr [rbx + RG_ninput], REG_EP_CAP
    ja .Lrgr_bad
    mov r13, [r12 + RD_index]
    cmp r13, [rbx + RG_ninput]
    jae .Lrgr_advance
    test rax, rax
    jz .Lrgr_bad
    imul rsi, r13, RGS_SIZE
    add rsi, rax
    mov edx, 2
.Lrgr_row:
    mov rdi, r12
    call catalog_retire_drop
    test rax, rax
    js .Lrgr_return
    inc qword ptr [r12 + RD_index]
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrgr_advance:
    inc qword ptr [r12 + RD_phase]
    mov qword ptr [r12 + RD_index], 0
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrgr_handoff:
    mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js .Lrgr_bad
    mov eax, 1
    xor edx, edx
.Lrgr_return:
    EPILOGUE
.Lrgr_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    EPILOGUE

FN registry_base_retire_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + RD_phase]
    test rax, rax
    jz .Lrbr_scratch
    cmp rax, 1
    je .Lrbr_po
    cmp rax, 2
    je .Lrbr_eo
    cmp rax, 3
    je .Lrbr_handoff
    jmp .Lrbr_bad
.Lrbr_scratch:
    mov rdi, rbx
    call catalog_base_scratch_consume
    test rax, rax
    js .Lrbr_bad
    test r8, r8
    jz .Lrbr_advance
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrbr_po:
    lea rsi, [rbx + RB_scratch_po]
    mov edx, 4
    jmp .Lrbr_drop
.Lrbr_eo:
    lea rsi, [rbx + RB_constructor_eo]
    mov edx, 5
.Lrbr_drop:
    mov rdi, r12
    call catalog_retire_drop
    test rax, rax
    js .Lrbr_return
.Lrbr_advance:
    inc qword ptr [r12 + RD_phase]
    mov qword ptr [r12 + RD_index], 0
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrbr_handoff:
    mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js .Lrbr_bad
    mov eax, 1
    xor edx, edx
.Lrbr_return:
    EPILOGUE
.Lrbr_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    EPILOGUE
