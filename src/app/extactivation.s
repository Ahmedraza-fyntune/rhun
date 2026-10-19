# Retained native plan views and one-unit supplier retirement.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.text
# Internal typed ready check; preserves RDI. Caller owns an actual native EA pointer.
FN ea_is_ready
    xor eax, eax
    test rdi, rdi
    jz 9f
    lea rcx, [rdi - RD_PO_BACK]
    cmp qword ptr [rcx + RD_kind], EA_KIND
    jne 9f
    mov rdx, [rcx + RD_state]
    test edx, RDF_STATE_MASK
    jnz 9f
    test edx, RDF_PO
    jz 9f
    cmp qword ptr [rdi + PO_refs], 0
    je 9f
    cmp qword ptr [rdi + PO_ready], 1
    jne 9f
    cmp qword ptr [rdi + EA_ep], 0
    je 9f
    mov eax, 1
9:  ret

FN ext_activation_owner_retain
    PROLOGUE
    call ea_is_ready
    test eax, eax
    jz 8f
    call prep_object_retain
    EPILOGUE
8:  mov rax, -EV_BAD_PREPARE
    EPILOGUE

# Also accepts the sole failed generic PO returned if fresh custom marking failed.
FN ext_activation_owner_release
    test rdi, rdi
    jz 8f
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], EA_KIND
    je ext_prepare_retire_release_custom_po
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], RD_LEDGER
    jne 8f
    cmp qword ptr [rdi + PO_ready], 0
    jne 8f
    jmp prep_owned_dispose
8:  mov rax, -EV_BAD_PREPARE
    xor edx, edx
    ret

FN ext_activation_owner_plan
    PROLOGUE
    call ea_is_ready
    test eax, eax
    jz 9f
    lea rax, [rdi + EA_plan]
9:  EPILOGUE

FN ext_activation_owner_ep
    PROLOGUE
    call ea_is_ready
    test eax, eax
    jz 9f
    mov rax, [rdi + EA_ep]
9:  EPILOGUE

# Copies immutable evidence only, never fresh authorization. Out unchanged on failure.
FN ext_activation_owner_proof
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 8f
    call ea_is_ready
    test eax, eax
    jz 8f
    mov rax, [rbx + EA_proof_kind]
    mov [r12 + EAP_kind], rax
    lea rdi, [r12 + EAP_source]
    lea rsi, [rbx + EA_source]
    mov edx, 64
    call memcpy
    mov rax, [rbx + EA_plan + KE_context]
    mov [r12 + EAP_context], rax
    xor eax, eax
    EPILOGUE
8:  mov rax, -22
    EPILOGUE

FN ext_activation_owner_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ea_is_ready
    test eax, eax
    jz 8f
    test r12, r12
    jle 7f
    cmp r12, [rbx + EA_plan + KE_context]
    jne 7f
    call ext_activation_epoch_get
    cmp rax, r12
    jne 7f
    xor eax, eax
    EPILOGUE
7:  mov rax, -116
    EPILOGUE
8:  mov rax, -22
    EPILOGUE

# Scheduler callback: one supplier drop, then a separate ledger handoff unit.
FN ea_retire_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + EA_ep]
    test rdi, rdi
    jz 2f
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne 8f
    mov qword ptr [rbx + EA_ep], 0
    test rax, rax
    jns 1f
    mov rdi, r12
    mov rsi, rax
    call ext_prepare_retire_note_error
1:  mov eax, 1
    xor edx, edx
    EPILOGUE
2:  mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js 8f
    mov eax, 1
    xor edx, edx
    EPILOGUE
8:  xor edx, edx
    EPILOGUE
