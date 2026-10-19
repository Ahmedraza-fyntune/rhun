# Additive construction in an already owned deferred preparation domain.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/commandgeneration.inc"
.text
# Borrowed readable EO. Shape only, preserves RDI; no refs or authority acquired.
cgo_owner_shape:
    test rdi, rdi
    jz .Lcgo_invalid
    cmp [rdi - RD_SIZE + RD_object], rdi
    jne .Lcgo_invalid
    cmp qword ptr [rdi - RD_SIZE + RD_kind], RD_EO
    jne .Lcgo_invalid
    mov rax, [rdi - RD_SIZE + RD_state]
    test eax, RDF_STATE_MASK | RDF_PO
    jnz .Lcgo_invalid
    cmp qword ptr [rdi + EO_deferred], 1
    jne .Lcgo_invalid
    cmp qword ptr [rdi + EO_refs], 0
    jle .Lcgo_invalid
    cmp qword ptr [rdi + EO_used], 128
    jb .Lcgo_invalid
    mov rax, [rdi + EO_cap]
    cmp rax, PREP_CAP
    ja .Lcgo_invalid
    cmp [rdi + EO_used], rax
    ja .Lcgo_invalid
    xor eax, eax
    ret
.Lcgo_invalid:
    mov rax, -22
    ret

# EO,context24 ->owned PO/0, DXprimary,CXcleanup,R8 actual kind0/2/4.
# The initial caller EO reference is never consumed here.
FN command_generation_begin_in_owner
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call cgo_owner_shape
    test rax, rax
    js .Lcgob_error
    mov rax, 0x7fffffffffffffff
    cmp [rbx + EO_refs], rax
    je .Lcgob_overflow
    mov rax, [rbx + EO_error]
    test rax, rax
    js .Lcgob_error
    jnz .Lcgob_invalid
    test r12, r12
    jz .Lcgob_invalid
    xor ecx, ecx
1:  cmp qword ptr [r12 + rcx*8], 0
    jle .Lcgob_invalid
    inc rcx
    cmp rcx, 3
    jb 1b
    mov edi, 4
    lea rsi, [rip + command_generation_retire_one]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Lcgob_error
    mov rdi, rbx
    mov esi, CG_SIZE
    call prep_object_create
    test rax, rax
    jz .Lcgob_null
    mov r13, rax
    mov rdi, rax
    mov esi, 4
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    js .Lcgob_partial
    mov rax, [r12]
    mov [r13 + CG_intent], rax
    mov rax, [r12 + 8]
    mov [r13 + CG_keyepoch], rax
    mov rax, [r12 + 16]
    mov [r13 + CG_visibility], rax
    xor edx, edx
    jmp .Lcgob_owned
.Lcgob_partial:
    mov [r13 + PO_error], rax
    mov rdx, rax
.Lcgob_owned:
    mov r8, [r13 - RD_PO_BACK + RD_kind]
    mov rax, r13
    xor ecx, ecx
    EPILOGUE
.Lcgob_overflow:
    mov rax, -75
    jmp .Lcgob_error
.Lcgob_invalid:
    mov rax, -22
.Lcgob_error:
    mov rdx, rax
.Lcgob_null:
    xor eax, eax
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

# Exact constructor-result tag plus readable owned PO. No release fallback on refusal.
FN command_generation_constructor_release
    test rdi, rdi
    jnz 1f
    test rsi, rsi
    jnz .Lcgor_bad
    xor eax, eax
    mov edx, 1
    ret
1:  cmp rsi, RD_LEDGER
    je 2f
    cmp rsi, 4
    jne .Lcgor_bad
2:  lea r8, [rdi - RD_PO_BACK]
    cmp [r8 + RD_object], rdi
    jne .Lcgor_bad
    cmp [r8 + RD_kind], rsi
    jne .Lcgor_bad
    mov rax, [r8 + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lcgor_bad
    test eax, RDF_PO
    jz .Lcgor_bad
    cmp qword ptr [rdi + PO_refs], 0
    jle .Lcgor_bad
    # Native requested extent is before the RD prefix, outside mutable CG fields.
    cmp qword ptr [r8 - 8], CG_SIZE + RD_PO_BACK
    jne .Lcgor_bad
    cmp qword ptr [rdi - AO_SIZE + AO_charge], CG_SIZE + RD_PO_BACK + 16
    jb .Lcgor_bad
    cmp qword ptr [rdi - AO_SIZE + AO_charge], PREP_CAP
    ja .Lcgor_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + PO_eo]
    call cgo_owner_shape
    test rax, rax
    js .Lcgor_refuse
    cmp r12, 4
    je .Lcgor_custom
    cmp qword ptr [rbx + PO_refs], 1
    jne .Lcgor_refuse
    cmp qword ptr [rbx + PO_ready], 0
    jne .Lcgor_refuse
    cmp qword ptr [rbx + PO_error], 0
    jge .Lcgor_refuse
    lea rax, [rbx - AO_SIZE]
    cmp [rbx + PO_allocs], rax
    jne .Lcgor_refuse
    cmp qword ptr [rax + AO_next], 0
    jne .Lcgor_refuse
    # Before a successful mark, no fixed header input/supplier state exists.
    mov ecx, PO_SIZE
3:  cmp qword ptr [rbx + rcx], 0
    jne .Lcgor_refuse
    add rcx, 8
    cmp rcx, CG_slots
    jb 3b
    cmp qword ptr [rbx + CG_defaultmeta], 0
    jne .Lcgor_refuse
    cmp qword ptr [rbx + CG_defaultnodes], 0
    jne .Lcgor_refuse
    cmp qword ptr [rbx + CG_defaultcapacity], 0
    jne .Lcgor_refuse
    cmp qword ptr [rbx + CG_defaultcount], 0
    jne .Lcgor_refuse
    mov rdi, rbx
    call prep_object_release_deferred
    EPILOGUE
.Lcgor_custom:
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    EPILOGUE
.Lcgor_refuse:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lcgor_bad:
    mov rax, -22
    xor edx, edx
    ret
