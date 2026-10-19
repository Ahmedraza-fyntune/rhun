# Retained immutable suppliers and copied, chunked configuration inputs.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntime.inc"
.include "app/keycombo.inc"
.include "app/commandgeneration.inc"
.text
# CG,readyEP,targetEXT,ordinal ->0/-errno; no source reference consumed on failure.
FN command_generation_add_extension
    PROLOGUE CS_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call cg_input
    test rax, rax
    jnz .Lcgax_ret
    cmp qword ptr [rbx + CG_openkey], 0
    jne .Lcgax_invalid
    test r12, r12
    jz .Lcgax_invalid
    cmp qword ptr [r12 + PO_refs], 0
    je .Lcgax_invalid
    cmp qword ptr [r12 + PO_ready], 1
    jne .Lcgax_invalid
    cmp qword ptr [r12 - RD_PO_BACK + RD_kind], RD_EP
    jne .Lcgax_invalid
    test qword ptr [r12 - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz .Lcgax_invalid
    mov [rsp + CS_target], r13
    mov [rsp + CS_ordinal], r14
    mov [rsp + CS_ep], r12
    mov rdi, [r12 + EP_ext + EXT_owner]
    test rdi, rdi
    jz .Lcgax_invalid
    mov [rsp + CS_owner], rdi
    call ext_validate_identity
    test rax, rax
    jz .Lcgax_invalid
    mov [rsp + CS_ownerlen], rax
    mov rdi, [r12 + EP_ext + EXT_name]
    test rdi, rdi
    jz .Lcgax_invalid
    mov [rsp + CS_name], rdi
    call ext_validate_identity
    test rax, rax
    jz .Lcgax_invalid
    mov [rsp + CS_namelen], rax
    mov rax, [rbx + CG_nmanifest]
    mov [rsp + CS_first], rax
    mov r15, [r12 + EP_commands + VEC_len]
    mov [rsp + CS_count], r15
    mov qword ptr [rsp + CS_runtime], 0
    mov rax, [rbx + CG_ncommands]
    add rax, r15
    jc .Lcgax_resource
    cmp rax, CG_COMMAND_CAP
    ja .Lcgax_resource
    mov rdi, rbx
    mov rsi, rsp
    call cg_slot_check
    test rax, rax
    jnz .Lcgax_error
    mov rdi, r12
    call ext_prepare_retain
    test rax, rax
    jnz .Lcgax_error
    imul rdi, [rbx + CG_nslots], CS_SIZE
    lea rdi, [rbx + rdi + CG_slots]
    mov rsi, rsp
    mov edx, CS_SIZE
    call memcpy
    inc qword ptr [rbx + CG_nslots]
    add [rbx + CG_nmanifest], r15
    add [rbx + CG_ncommands], r15
    xor eax, eax
.Lcgax_ret:
    EPILOGUE
.Lcgax_resource:
    mov rax, -EV_RESOURCE
    jmp .Lcgax_error
.Lcgax_invalid:
    mov rax, -22
.Lcgax_error:
    mov rdi, rbx
    call cg_fail
    EPILOGUE

# CG,targetEXT,ordinal,owner,name -> identity-only visible slot with owned strings.
FN command_generation_add_identity
    PROLOGUE CS_SIZE
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    mov [rsp + CS_target], rsi
    mov [rsp + CS_ordinal], rdx
    call cg_input
    test rax, rax
    jnz .Lcgai_ret
    cmp qword ptr [rbx + CG_openkey], 0
    jne .Lcgai_invalid
    test r12, r12
    jz .Lcgai_invalid
    test r13, r13
    jz .Lcgai_invalid
    mov rdi, r12
    call ext_validate_identity
    test rax, rax
    jz .Lcgai_invalid
    mov [rsp + CS_ownerlen], rax
    mov rdi, r13
    call ext_validate_identity
    test rax, rax
    jz .Lcgai_invalid
    mov [rsp + CS_namelen], rax
    mov [rsp + CS_owner], r12
    mov [rsp + CS_name], r13
    mov qword ptr [rsp + CS_ep], 0
    mov rax, [rbx + CG_nmanifest]
    mov [rsp + CS_first], rax
    mov qword ptr [rsp + CS_count], 0
    mov qword ptr [rsp + CS_runtime], 0
    mov rdi, rbx
    mov rsi, rsp
    call cg_slot_check
    test rax, rax
    jnz .Lcgai_error
    mov rsi, [rsp + CS_ownerlen]
    add rsi, [rsp + CS_namelen]
    add rsi, 2
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lcgai_allocated_error
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, [rsp + CS_ownerlen]
    inc rdx
    call memcpy
    mov [rsp + CS_owner], r14
    add r14, [rsp + CS_ownerlen]
    inc r14
    mov rdi, r14
    mov rsi, r13
    mov rdx, [rsp + CS_namelen]
    inc rdx
    call memcpy
    mov [rsp + CS_name], r14
    imul rdi, [rbx + CG_nslots], CS_SIZE
    lea rdi, [rbx + rdi + CG_slots]
    mov rsi, rsp
    mov edx, CS_SIZE
    call memcpy
    inc qword ptr [rbx + CG_nslots]
    xor eax, eax
.Lcgai_ret:
    EPILOGUE
.Lcgai_allocated_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lcgai_invalid:
    mov rax, -22
.Lcgai_error:
    mov rdi, rbx
    call cg_fail
    EPILOGUE

# CG,ownedRO(borrowed caller ref) ->0/-errno. Duplicate wire validation is a bounded build phase.
FN command_generation_add_runtime
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call cg_input
    test rax, rax
    jnz .Lcgar_ret
    cmp qword ptr [rbx + CG_openkey], 0
    jne .Lcgar_invalid
    test r12, r12
    jz .Lcgar_invalid
    cmp qword ptr [r12 + RO_refs], 0
    je .Lcgar_invalid
    cmp qword ptr [r12 - RD_SIZE + RD_kind], 5
    jne .Lcgar_invalid
    test qword ptr [r12 - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lcgar_invalid
    cmp qword ptr [r12 + RO_live], 1
    jne .Lcgar_invalid
    cmp qword ptr [r12 + RO_session], 0
    jle .Lcgar_invalid
    cmp qword ptr [r12 + RO_incarnation], 0
    jle .Lcgar_invalid
    mov rax, [r12 + RO_ownerlen]
    dec rax
    cmp rax, 99
    ja .Lcgar_invalid
    mov rax, [r12 + RO_namelen]
    dec rax
    cmp rax, 99
    ja .Lcgar_invalid
    cmp qword ptr [rbx + CG_nruntimes], CG_RUNTIME_CAP
    jae .Lcgar_resource
    cmp qword ptr [rbx + CG_ncommands], CG_COMMAND_CAP
    jae .Lcgar_resource
    xor r13d, r13d
1:  cmp r13, [rbx + CG_nslots]
    jae .Lcgar_invalid
    imul r14, r13, CS_SIZE
    lea r14, [rbx + r14 + CG_slots]
    cmp qword ptr [r14 + CS_ep], 0
    je 2f
    mov rax, [r12 + RO_target]
    cmp [r14 + CS_target], rax
    jne 2f
    mov rax, [r12 + RO_ownerlen]
    cmp [r14 + CS_ownerlen], rax
    jne 2f
    mov rax, [r12 + RO_namelen]
    cmp [r14 + CS_namelen], rax
    jne 2f
    mov rdi, r12
    xor esi, esi
    call ext_runtime_get
    mov rdi, rax
    mov rsi, [r14 + CS_owner]
    mov rdx, [r12 + RO_ownerlen]
    call memeq
    test eax, eax
    jz 2f
    mov rdi, r12
    mov esi, 1
    call ext_runtime_get
    mov rdi, rax
    mov rsi, [r14 + CS_name]
    mov rdx, [r12 + RO_namelen]
    call memeq
    test eax, eax
    jnz 3f
2:  inc r13
    jmp 1b
3:  cmp qword ptr [r14 + CS_runtime], 64
    jae .Lcgar_resource
    mov r15, [r12 + RO_keyslen]
    cmp r15, RO_LIMIT
    ja .Lcgar_invalid
    inc r15
    add r15, [rbx + CG_defaultcapacity]
    jc .Lcgar_resource
    mov eax, CG_DEFAULT_NODE_CAP
    cmp r15, rax
    cmova r15, rax
    mov rdi, r12
    call ext_runtime_retain
    test rax, rax
    jnz .Lcgar_error
    mov rax, [rbx + CG_nruntimes]
    shl rax, 4
    lea rax, [rbx + rax + CG_runtimes]
    mov [rax], r12
    mov [rax + 8], r13
    mov [rbx + CG_defaultcapacity], r15
    inc qword ptr [rbx + CG_nruntimes]
    inc qword ptr [rbx + CG_ncommands]
    inc qword ptr [r14 + CS_runtime]
    xor eax, eax
.Lcgar_ret:
    EPILOGUE
.Lcgar_resource:
    mov rax, -EV_RESOURCE
    jmp .Lcgar_error
.Lcgar_invalid:
    mov rax, -22
.Lcgar_error:
    mov rdi, rbx
    call cg_fail
    EPILOGUE

# CG,comboLen,commandLen ->0/-errno. One ledger-owned block, no caller bytes retained.
FN command_generation_key_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call cg_input
    test rax, rax
    jnz .Lcgkb_ret
    cmp qword ptr [rbx + CG_openkey], 0
    jne .Lcgkb_invalid
    cmp qword ptr [rbx + CG_nkeys], CG_KEY_CAP
    jae .Lcgkb_resource
    cmp r12, KC_CAP
    ja .Lcgkb_resource
    cmp r13, KC_CAP
    ja .Lcgkb_resource
    lea r14, [r12 + r13]
    mov rax, [rbx + CG_keybytes]
    add rax, r14
    jc .Lcgkb_resource
    cmp rax, CG_KEY_BYTES_CAP
    ja .Lcgkb_resource
    lea rsi, [r14 + 2]
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lcgkb_allocated_error
    mov [rbx + CG_openkey], rax
    mov [rbx + CG_combolen], r12
    mov [rbx + CG_commandlen], r13
    mov qword ptr [rbx + CG_keycursor], 0
    xor eax, eax
.Lcgkb_ret:
    EPILOGUE
.Lcgkb_allocated_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lcgkb_invalid:
    mov rax, -22
    jmp .Lcgkb_error
.Lcgkb_resource:
    mov rax, -EV_RESOURCE
.Lcgkb_error:
    mov rdi, rbx
    call cg_fail
    EPILOGUE

# Ordered combo bytes then command bytes, without the two owned NUL slots.
FN command_generation_key_append
    PROLOGUE 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call cg_input
    test rax, rax
    jnz .Lcgka_ret
    cmp qword ptr [rbx + CG_openkey], 0
    je .Lcgka_invalid
    test r12, r12
    jz .Lcgka_invalid
    lea rax, [r13 - 1]
    cmp rax, 4095
    ja .Lcgka_invalid
    mov r14, [rbx + CG_keycursor]
    mov rax, [rbx + CG_combolen]
    add rax, [rbx + CG_commandlen]
    sub rax, r14
    cmp r13, rax
    ja .Lcgka_invalid
    xor ecx, ecx
1:  cmp byte ptr [r12 + rcx], 0
    je .Lcgka_invalid
    inc rcx
    cmp rcx, r13
    jb 1b
    mov r15, [rbx + CG_combolen]
    cmp r14, r15
    jae 3f
    sub r15, r14
    cmp r15, r13
    cmova r15, r13
    mov rdi, [rbx + CG_openkey]
    add rdi, r14
    mov rsi, r12
    mov rdx, r15
    call memcpy
    add r12, r15
    add r14, r15
    sub r13, r15
    test r13, r13
    jz 4f
3:  mov rdi, [rbx + CG_openkey]
    lea rdi, [rdi + r14 + 1]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add r14, r13
4:  mov [rbx + CG_keycursor], r14
    xor eax, eax
.Lcgka_ret:
    EPILOGUE
.Lcgka_invalid:
    mov rax, -22
    mov rdi, rbx
    call cg_fail
    EPILOGUE

FN command_generation_key_finish
    PROLOGUE
    mov rbx, rdi
    call cg_input
    test rax, rax
    jnz .Lcgkf_ret
    mov r12, [rbx + CG_openkey]
    test r12, r12
    jz .Lcgkf_invalid
    mov r13, [rbx + CG_combolen]
    mov r14, [rbx + CG_commandlen]
    lea rax, [r13 + r14]
    cmp [rbx + CG_keycursor], rax
    jne .Lcgkf_invalid
    mov byte ptr [r12 + r13], 0
    lea rcx, [r13 + r14 + 1]
    mov byte ptr [r12 + rcx], 0
    mov rdx, [rbx + CG_nkeys]
    shl rdx, 5
    lea rdx, [rbx + rdx + CG_keylines]
    mov [rdx], r12
    mov [rdx + 8], r13
    lea rcx, [r12 + r13 + 1]
    mov [rdx + 16], rcx
    mov [rdx + 24], r14
    inc qword ptr [rbx + CG_nkeys]
    add [rbx + CG_keybytes], rax
    mov qword ptr [rbx + CG_openkey], 0
    xor eax, eax
.Lcgkf_ret:
    EPILOGUE
.Lcgkf_invalid:
    mov rax, -22
    mov rdi, rbx
    call cg_fail
    EPILOGUE

FN command_generation_seal
    PROLOGUE
    mov rbx, rdi
    call cg_input
    test rax, rax
    jnz .Lcgseal_ret
    cmp qword ptr [rbx + CG_openkey], 0
    jne .Lcgseal_invalid
    mov qword ptr [rbx + CG_phase], CG_ALLOC
    xor eax, eax
.Lcgseal_ret:
    EPILOGUE
.Lcgseal_invalid:
    mov rax, -22
    mov rdi, rbx
    call cg_fail
    EPILOGUE
