# Construction and retained inputs for a complete immutable command generation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntime.inc"
.include "app/keycombo.inc"
.include "app/commandgeneration.inc"
.text
# Preserve first input/build failure. Caller owns a valid CG.
FN cg_fail
    cmp qword ptr [rdi + PO_error], 0
    jne 1f
    mov [rdi + PO_error], rax
1:  mov rax, [rdi + PO_error]
    ret

# No borrowed source is followed until the caller's owned generation is valid.
FN cg_input
    test rdi, rdi
    jz .Lcgi_invalid
    cmp qword ptr [rdi + PO_refs], 0
    je .Lcgi_invalid
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], 4
    jne .Lcgi_invalid
    test qword ptr [rdi - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz .Lcgi_invalid
    mov rax, [rdi + PO_error]
    test rax, rax
    jnz 9f
    cmp qword ptr [rdi + CG_phase], CG_INPUT
    jne .Lcgi_sticky
9:  ret
.Lcgi_sticky:
    mov rax, -22
    jmp cg_fail
.Lcgi_invalid:
    mov rax, -22
    ret

# context24 -> owned CG or NULL, RDXprimary, RCXcleanup. Failed nonNULL owners must be released.
FN command_generation_begin
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lcgb_invalid
    xor ecx, ecx
1:  cmp qword ptr [rbx + rcx*8], 0
    jle .Lcgb_invalid
    inc rcx
    cmp rcx, 3
    jb 1b
    mov edi, 4
    lea rsi, [rip + command_generation_retire_one]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Lcgb_registration
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lcgb_null
    mov r12, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    js .Lcgb_owner_error
    mov rdi, r12
    mov esi, CG_SIZE
    call prep_object_create
    test rax, rax
    jz .Lcgb_create_error
    mov r13, rax
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov rax, [rbx]
    mov [r13 + CG_intent], rax
    mov rax, [rbx + 8]
    mov [r13 + CG_keyepoch], rax
    mov rax, [rbx + 16]
    mov [r13 + CG_visibility], rax
    mov rdi, r13
    mov esi, 4
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    js .Lcgb_partial
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lcgb_partial:
    mov [r13 + PO_error], rax
    mov rdx, rax
    mov rax, r13
    xor ecx, ecx
    EPILOGUE
.Lcgb_create_error:
    mov r13, rdx
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov rdx, r13
    jmp .Lcgb_null
.Lcgb_owner_error:
    mov r13, rax
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov rdx, r13
    jmp .Lcgb_null
.Lcgb_registration:
    mov rdx, rax
    jmp .Lcgb_null
.Lcgb_invalid:
    mov rdx, -22
.Lcgb_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

FN command_generation_retain
    test rdi, rdi
    jz .Lcgr_bad
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], 4
    jne .Lcgr_bad
    cmp qword ptr [rdi + PO_error], 0
    jne .Lcgr_bad
    jmp prep_object_retain
.Lcgr_bad:
    mov rax, -22
    ret

# Constructor-failure owners may still have generic kind2 and no supplier refs.
FN command_generation_release_deferred
    test rdi, rdi
    jz .Lcgr_null
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], RD_LEDGER
    je prep_owned_dispose
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], 4
    je ext_prepare_retire_release_custom_po
    xor edx, edx
    mov rax, -22
    ret
.Lcgr_null:
    xor eax, eax
    mov edx, 1
    ret

# Fixed-size identity checks, at most128 rows with<=100 bytes per identity field.
# CG,candidate80 ->0/-errno. Does not retain or mutate either input.
FN cg_slot_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + CG_nslots], CG_SLOT_CAP
    jae .Lcgsc_resource
    cmp qword ptr [r12 + CS_target], 0
    je .Lcgsc_invalid
    cmp qword ptr [r12 + CS_ordinal], 128
    jae .Lcgsc_invalid
    xor r13d, r13d
1:  cmp r13, [rbx + CG_nslots]
    jae .Lcgsc_ok
    imul r14, r13, CS_SIZE
    lea r14, [rbx + r14 + CG_slots]
    mov rax, [r12 + CS_target]
    cmp [r14 + CS_target], rax
    je .Lcgsc_duplicate
    mov rax, [r12 + CS_ordinal]
    cmp [r14 + CS_ordinal], rax
    je .Lcgsc_duplicate
    mov rax, [r12 + CS_ownerlen]
    cmp [r14 + CS_ownerlen], rax
    jne 2f
    mov rax, [r12 + CS_namelen]
    cmp [r14 + CS_namelen], rax
    jne 2f
    mov rdi, [r12 + CS_owner]
    mov rsi, [r14 + CS_owner]
    mov rdx, [r12 + CS_ownerlen]
    call memeq
    test eax, eax
    jz 2f
    mov rdi, [r12 + CS_name]
    mov rsi, [r14 + CS_name]
    mov rdx, [r12 + CS_namelen]
    call memeq
    test eax, eax
    jnz .Lcgsc_duplicate
2:  inc r13
    jmp 1b
.Lcgsc_ok:
    xor eax, eax
    EPILOGUE
.Lcgsc_duplicate:
    mov rax, -17
    EPILOGUE
.Lcgsc_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lcgsc_invalid:
    mov rax, -22
    EPILOGUE

# One deferred supplier reference per scheduler unit, followed by common ledger ownership.
FN command_generation_retire_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + CG_retirecursor]
    cmp qword ptr [rbx + CG_retirephase], 0
    jne .Lcgd_runtime
    cmp r13, [rbx + CG_nslots]
    jae .Lcgd_phase
    imul r14, r13, CS_SIZE
    lea r14, [rbx + r14 + CG_slots + CS_ep]
    jmp .Lcgd_drop_ep
.Lcgd_runtime:
    cmp r13, [rbx + CG_nruntimes]
    jae .Lcgd_handoff
    shl r13, 4
    lea r14, [rbx + r13 + CG_runtimes]
    mov rdi, [r14]
    test rdi, rdi
    jz .Lcgd_advance
    call ext_runtime_release_deferred
    jmp .Lcgd_result
.Lcgd_drop_ep:
    mov rdi, [r14]
    test rdi, rdi
    jz .Lcgd_advance
    call ext_prepare_release_deferred
.Lcgd_result:
    cmp rdx, 1
    jne .Lcgd_blocked
    mov qword ptr [r14], 0
    test rax, rax
    jns .Lcgd_advance
    mov rdi, r12
    mov rsi, rax
    call ext_prepare_retire_note_error
.Lcgd_advance:
    inc qword ptr [rbx + CG_retirecursor]
    mov eax, 1
    EPILOGUE
.Lcgd_phase:
    mov qword ptr [rbx + CG_retirephase], 1
    mov qword ptr [rbx + CG_retirecursor], 0
    mov eax, 1
    EPILOGUE
.Lcgd_handoff:
    mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js .Lcgd_blocked
    mov eax, 1
    EPILOGUE
.Lcgd_blocked:
    test rax, rax
    js 1f
    mov rax, -5
1:  xor edx, edx
    EPILOGUE
