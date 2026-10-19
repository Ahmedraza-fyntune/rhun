# One shared catalog kind; PLAN stays closed until its actual owner exists.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.text
FN catalog_kind7_init
    mov edi, C7_KIND
    lea rsi, [rip + catalog_retire_one]
    mov edx, 1
    jmp ext_prepare_retire_register_kind

# Pure actual table check, no cached Boolean or competing registration.
FN catalog_kind7_check
    mov rax, [rip + prep_retire_handlers + C7_KIND * 8]
    test rax, rax
    jz .Lck_missing
    lea rcx, [rip + catalog_retire_one]
    cmp rax, rcx
    jne .Lck_different
    cmp qword ptr [rip + prep_retire_modes + C7_KIND * 8], 1
    jne .Lck_different
    xor eax, eax
    ret
.Lck_missing:
    mov rax, -2
    ret
.Lck_different:
    mov rax, -17
    ret

# object, exact record. Callback admission deliberately permits zero PO refs.
FN catalog_retire_one
    test rdi, rdi
    jz .Lcr_bad
    test rsi, rsi
    jz .Lcr_bad
    lea rax, [rdi - RD_PO_BACK]
    cmp rax, rsi
    jne .Lcr_bad
    cmp [rsi + RD_object], rdi
    jne .Lcr_bad
    cmp qword ptr [rsi + RD_kind], C7_KIND
    jne .Lcr_bad
    mov rax, [rsi + RD_state]
    test eax, RDF_PO
    jz .Lcr_bad
    and eax, RDF_STATE_MASK
    cmp eax, RD_RUNNING
    jne .Lcr_bad
    cmp qword ptr [rdi + PO_refs], 0
    jne .Lcr_bad
    cmp qword ptr [rdi + PO_ready], 0
    jne .Lcr_bad
    mov rax, C7_MAGIC
    cmp [rdi + C7_magic], rax
    jne .Lcr_bad
    cmp qword ptr [rdi + C7_bytes], RG_SIZE
    jne .Lcr_bad
    cmp qword ptr [rdi + C7_role], C7_REGISTRY
    je registry_retire_one
    cmp qword ptr [rdi + C7_role], C7_BASE
    je registry_base_retire_one
.Lcr_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    ret
