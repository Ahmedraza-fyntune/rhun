# Bounded memory-only activation capture, with explicit failed-owner returns.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.text
# Nonzero digest test, exactly32 bytes. RAX1 if any byte is nonzero.
ea_digest_nonzero:
    xor eax, eax
    xor ecx, ecx
1:  or al, [rdi + rcx]
    inc rcx
    cmp rcx, 32
    jb 1b
    test al, al
    setnz al
    movzx eax, al
    ret

# Nullable metadata equality. The copied KE input is already bounded by its wire parser.
ea_equal:
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + ea_create_empty]
1:  test rsi, rsi
    jnz 2f
    lea rsi, [rip + ea_create_empty]
2:  jmp strcmp_eq

# Bind a copied plan to immutable metadata; state/project/home are captured dynamic context.
FN ea_ep_matches
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rax, [rip + ea_ep_offsets]
    mov rax, [rax + r13*8]
    mov rdi, [rbx + EP_ext + rax]
    lea rax, [rip + ea_ke_offsets]
    mov rax, [rax + r13*8]
    mov rsi, [r12 + rax]
    call ea_equal
    test eax, eax
    jz 8f
    inc r13
    cmp r13, 6
    jb 1b
    mov eax, [rbx + EP_ext + EXT_needs]
    cmp eax, [r12 + KE_needs]
    jne 8f
    xor eax, eax
    EPILOGUE
8:  mov rax, -22
    EPILOGUE

FN ext_activation_owner_create
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    test rbx, rbx
    jz .Leac_bad
    test r12, r12
    jz .Leac_bad
    test r14, r14
    jz .Leac_bad
    test r15, r15
    jz .Leac_bad
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_EP
    jne .Leac_bad
    mov rax, [rbx - RD_PO_BACK + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Leac_bad
    test eax, RDF_PO
    jz .Leac_bad
    cmp qword ptr [rbx + PO_ready], 1
    jne .Leac_bad
    cmp qword ptr [rbx + PO_refs], 0
    je .Leac_bad
    cmp r13, EA_MANAGED
    je 1f
    cmp r13, EA_LEGACY
    jne .Leac_bad
    cmp qword ptr [rbx + EP_kind], 2
    jne .Leac_bad
    cmp qword ptr [r12 + KE_kind], KA_LEGACY
    jne .Leac_bad
    mov rdi, r15
    call ea_digest_nonzero
    test eax, eax
    jnz .Leac_bad
    jmp 2f
1:  cmp qword ptr [rbx + EP_kind], 1
    jne .Leac_bad
    mov rax, [r12 + KE_kind]
    cmp rax, KA_SELECTED
    je 11f
    cmp rax, KA_CANDIDATE
    jne .Leac_bad
11: mov rdi, r15
    call ea_digest_nonzero
    test eax, eax
    jz .Leac_bad
2:  mov rdi, r14
    call ea_digest_nonzero
    test eax, eax
    jz .Leac_bad
    mov rax, [rbx + PO_eo]
    mov rax, [rax + EO_lease]
.ifdef WINDOWS
    test rax, rax
    jz .Leac_bad
    cmp rax, -1
    je .Leac_bad
.else
    test rax, rax
    js .Leac_bad
.endif
    cmp rax, [r12 + KE_lease]
    jne .Leac_bad
    call ext_activation_epoch_get
    test rax, rax
    jle .Leac_stale
    cmp rax, [r12 + KE_context]
    jne .Leac_stale
    mov edi, EA_KIND
    lea rsi, [rip + ea_retire_one]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Leac_empty_rax
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Leac_empty
    mov [rsp], rax
    # Fresh exclusively owned EO: establish its one-way deferred flag before PO admission.
    mov qword ptr [rax + EO_deferred], 1
    mov rdi, rax
    mov esi, EA_SIZE
    call prep_object_create
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov rdi, [rsp]
    call ext_prepare_owner_release_deferred
    mov rax, [rsp + 8]
    test rax, rax
    jz .Leac_po_empty
    mov rdi, rax
    mov esi, EA_KIND
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    js .Leac_owned_error
    mov rdi, [rsp + 8]
    mov [rdi + EA_proof_kind], r13
    lea rdi, [rdi + EA_source]
    mov rsi, r14
    mov edx, 32
    call memcpy
    mov rdi, [rsp + 8]
    add rdi, EA_tree
    mov rsi, r15
    mov edx, 32
    call memcpy
    mov rdi, [rsp + 8]
    mov rsi, r12
    call ea_wire_build
    test rax, rax
    js .Leac_owned_error
    mov rdi, rbx
    mov rsi, [rsp + 8]
    add rsi, EA_plan
    call ea_ep_matches
    test rax, rax
    js .Leac_owned_error
    mov rdi, rbx
    call ext_prepare_retain
    test rax, rax
    js .Leac_owned_error
    mov rax, [rsp + 8]
    mov [rax + EA_ep], rbx
    mov qword ptr [rax + PO_ready], 1
    xor edx, edx
    EPILOGUE
.Leac_owned_error:
    mov rdx, rax
    mov rax, [rsp + 8]
    mov [rax + PO_error], rdx
    EPILOGUE
.Leac_po_empty:
    mov rdx, [rsp + 16]
.Leac_empty:
    xor eax, eax
    EPILOGUE
.Leac_bad:
    mov rax, -22
    jmp .Leac_empty_rax
.Leac_stale:
    mov rax, -116
.Leac_empty_rax:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.section .rodata
.p2align 3
ea_ep_offsets: .quad EXT_owner, EXT_name, EXT_dir, EXT_prog, EXT_script, EXT_runs
ea_ke_offsets: .quad KE_owner, KE_name, KE_payload, KE_program, KE_script, KE_runs
ea_create_empty: .asciz ""
