# Native immutable input admission. No globals, payload IO or contribution parsing.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.text
FN registry_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jle .Lrgbi_invalid
    mov esi, C7_BASE
    call catalog_is_ready
    test eax, eax
    jz .Lrgbi_invalid
    mov edi, C7_REGISTRY
    call catalog_object_create
    test rax, rax
    jz .Lrgbi_return
    test rdx, rdx
    js .Lrgbi_return
    mov r13, rax
    mov rdi, rbx
    call registry_base_retain
    test rax, rax
    js .Lrgbi_failed
    mov [r13 + RG_base], rbx
    mov rax, [rbx + RB_version]
    mov [r13 + RG_base_version], rax
    mov [r13 + RG_epoch], r12
    mov rax, [rbx + RB_nuser]
    add rax, [rbx + RB_nbuiltin]
    mov [r13 + RW_grcap], rax
    mov rax, [rbx + RB_ntheme]
    mov [r13 + RW_thcap], rax
    mov rax, [rbx + RB_follow]
    mov [r13 + RG_follow], rax
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
.Lrgbi_return:
    EPILOGUE
.Lrgbi_failed:
    mov rdi, r13
    call catalog_fail
    mov rdx, rax
    mov rax, r13
    xor ecx, ecx
    EPILOGUE
.Lrgbi_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    EPILOGUE

# rg,ready native EP. Success owns one independent input ref; refusal owns none.
# At first admission only, one fixed128-row ledger allocation precedes the retain.
FN registry_add_ep
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, C7_REGISTRY
    call catalog_is_owned
    test eax, eax
    jz .Lrga_invalid
    cmp qword ptr [rbx + PO_error], 0
    jne .Lrga_existing
    cmp qword ptr [rbx + RG_sealed], 0
    jne .Lrga_busy
    cmp qword ptr [rbx + RG_phase], RG_INPUT
    jne .Lrga_busy
    cmp qword ptr [rbx + RG_ninput], REG_EP_CAP
    jae .Lrga_cap
    # Count is already bounded. Reject replay before allocation or supplier retain.
    xor ecx, ecx
    mov r8, [rbx + RG_inputs]
1:  cmp rcx, [rbx + RG_ninput]
    jae 2f
    test r8, r8
    jz .Lrga_invalid
    imul rax, rcx, RGS_SIZE
    cmp [r8 + rax + RGS_ep], r12
    je .Lrga_duplicate
    inc rcx
    jmp 1b
2:  mov rdi, r12
    call registry_ep_ready
    test eax, eax
    jz .Lrga_invalid
    mov r13, [r12 + EP_grammars + VEC_len]
    cmp r13, 256
    ja .Lrga_invalid
    cmp r13, [r12 + EP_grammars + VEC_cap]
    ja .Lrga_invalid
    mov r14, [r12 + EP_themeviews + VEC_len]
    cmp r14, 256
    ja .Lrga_invalid
    cmp r14, [r12 + EP_themeviews + VEC_cap]
    ja .Lrga_invalid
    test r13, r13
    jz 1f
    cmp qword ptr [r12 + EP_grammars + VEC_ptr], 0
    je .Lrga_invalid
1:  test r14, r14
    jz 2f
    cmp qword ptr [r12 + EP_themeviews + VEC_ptr], 0
    je .Lrga_invalid
2:  cmp qword ptr [rbx + RG_inputs], 0
    jne 3f
    mov rdi, rbx
    mov esi, REG_EP_CAP * RGS_SIZE
    call prep_owned_alloc
    test rax, rax
    jz .Lrga_alloc_failed
    mov [rbx + RG_inputs], rax
3:  mov rdi, r12
    call ext_prepare_retain
    test rax, rax
    js .Lrga_return
    mov rcx, [rbx + RG_ninput]
    imul rax, rcx, RGS_SIZE
    add rax, [rbx + RG_inputs]
    mov [rax + RGS_ep], r12
    mov [rax + RGS_ordinal], rcx
    inc qword ptr [rbx + RG_ninput]
    add r13, [rbx + RW_grcap]
    cmp r13, REG_ROW_CAP
    mov eax, REG_ROW_CAP
    cmova r13, rax
    mov [rbx + RW_grcap], r13
    add r14, [rbx + RW_thcap]
    cmp r14, REG_ROW_CAP
    cmova r14, rax
    mov [rbx + RW_thcap], r14
    xor eax, eax
.Lrga_return:
    EPILOGUE
.Lrga_alloc_failed:
    mov rax, rdx
    mov rdi, rbx
    call catalog_fail
    EPILOGUE
.Lrga_existing:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lrga_duplicate:
    mov rax, -17
    EPILOGUE
.Lrga_cap:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lrga_busy:
    mov rax, -16
    EPILOGUE
.Lrga_invalid:
    mov rax, -22
    EPILOGUE

FN registry_seal_inputs
    PROLOGUE
    mov rbx, rdi
    mov esi, C7_REGISTRY
    call catalog_is_owned
    test eax, eax
    jz .Lrgsi_bad
    cmp qword ptr [rbx + PO_error], 0
    jne .Lrgsi_existing
    cmp qword ptr [rbx + RG_sealed], 1
    je .Lrgsi_ok
    cmp qword ptr [rbx + RG_phase], RG_INPUT
    jne .Lrgsi_bad
    mov qword ptr [rbx + RG_sealed], 1
    mov qword ptr [rbx + RG_phase], RG_ALLOCATE
.Lrgsi_ok:
    xor eax, eax
    EPILOGUE
.Lrgsi_existing:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lrgsi_bad:
    mov rax, -22
    EPILOGUE

# Native owned pointer only. Reject other owner kinds before reading EP fields.
FN registry_ep_ready
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], RD_EP
    jne 9f
    mov rcx, [rdi - RD_PO_BACK + RD_state]
    test ecx, RDF_STATE_MASK
    jnz 9f
    test ecx, RDF_PO
    jz 9f
    cmp qword ptr [rdi - RD_PO_BACK - 8], EP_SIZE + RD_PO_BACK
    jb 9f
    cmp qword ptr [rdi + PO_refs], 0
    je 9f
    cmp qword ptr [rdi + PO_ready], 1
    jne 9f
    cmp qword ptr [rdi + PO_error], 0
    jne 9f
    mov rcx, [rdi + EP_kind]
    dec rcx
    cmp rcx, 1
    ja 9f
    mov eax, 1
9:  ret
