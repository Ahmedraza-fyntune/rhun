# Durable identity and state bytes remain independent from package metadata.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/exthostidentity.inc"
.text
# owner,name,state,flags -> owned HI or0, RDX0/-errno. Copies only bounded memory.
FN ext_host_identity_create
    PROLOGUE 96
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    test rcx, -2
    jnz .Lhic_invalid
    call ext_store_identity_len
    test rax, rax
    jz .Lhic_invalid
    mov [rsp + 32], rax
    mov rdi, [rsp + 8]
    call ext_store_identity_len
    test rax, rax
    jz .Lhic_invalid
    mov [rsp + 40], rax
    mov rdi, [rsp + 16]
    mov esi, 4095
    call ext_root_length
    test rax, rax
    js .Lhic_invalid
    mov [rsp + 48], rax
    jnz 1f
    test qword ptr [rsp + 24], HI_DIAGNOSTIC
    jz .Lhic_invalid
    jmp 2f
1:  mov rsi, rax
    mov rdi, [rsp + 16]
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lhic_invalid
2:  mov rax, HI_SIZE + 3
    add rax, [rsp + 32]
    add rax, [rsp + 40]
    add rax, [rsp + 48]
    mov [rsp + 72], rax
    mov edi, HI_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lhic_empty
    mov [rsp + 56], rax
    mov qword ptr [rax + EO_deferred], 1
    mov rdi, rax
    mov rsi, [rsp + 72]
    call prep_object_create
    mov [rsp + 64], rax
    mov [rsp + 80], rdx
    mov rdi, [rsp + 56]
    call ext_prepare_owner_release_deferred
    mov rbx, [rsp + 64]
    test rbx, rbx
    jz .Lhic_po_empty
    mov rax, HI_MAGIC
    mov [rbx + HI_magic], rax
    mov rax, [rsp + 72]
    mov [rbx + HI_bytes], rax
    lea r12, [rbx + HI_SIZE]
    mov [rbx + HI_owner], r12
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 32]
    inc rdx
    call memcpy
    add r12, [rsp + 32]
    inc r12
    mov [rbx + HI_name], r12
    mov rdi, r12
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 40]
    inc rdx
    call memcpy
    add r12, [rsp + 40]
    inc r12
    mov [rbx + HI_state], r12
    mov rdi, r12
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 48]
    inc rdx
    call memcpy
    mov qword ptr [rbx + PO_ready], 1
    mov rax, rbx
    xor edx, edx
    EPILOGUE
.Lhic_po_empty:
    mov rdx, [rsp + 80]
.Lhic_empty:
    xor eax, eax
    EPILOGUE
.Lhic_invalid:
    mov rdx, -22
    jmp .Lhic_empty

# Typed ownership check accepts an owned failed HI; no pointer may come from user data.
FN hi_is_owned
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], RD_LEDGER
    jne 9f
    mov rcx, [rdi - RD_PO_BACK + RD_state]
    test ecx, RDF_STATE_MASK
    jnz 9f
    test ecx, RDF_PO
    jz 9f
    cmp qword ptr [rdi + PO_refs], 0
    je 9f
    mov rcx, HI_MAGIC
    cmp [rdi + HI_magic], rcx
    jne 9f
    cmp qword ptr [rdi + HI_bytes], HI_SIZE + 5
    jb 9f
    cmp qword ptr [rdi + HI_bytes], HI_MAX
    ja 9f
    lea rcx, [rdi - AO_SIZE]
    cmp [rdi + PO_allocs], rcx
    jne 9f
    cmp qword ptr [rcx + AO_next], 0
    jne 9f
    mov rcx, [rdi + PO_eo]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx + EO_lease], -1
    jne 9f
    cmp qword ptr [rcx + EO_deferred], 1
    jne 9f
    cmp qword ptr [rcx + EO_refs], 0
    je 9f
    cmp qword ptr [rcx - RD_SIZE + RD_kind], RD_EO
    jne 9f
    test qword ptr [rcx - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz 9f
    cmp qword ptr [rcx + EO_cap], HI_CAP
    jne 9f
    mov rdx, [rdi - AO_SIZE + AO_charge]
    cmp rdx, HI_CAP
    ja 9f
    mov rcx, [rdi + HI_bytes]
    add rcx, RD_PO_BACK + 16
    cmp rdx, rcx
    jb 9f
    mov eax, 1
9:  ret

# Fixed shape checks; constructor-validated inline bytes are immutable.
FN hi_is_ready
    PROLOGUE
    mov rbx, rdi
    call hi_is_owned
    test eax, eax
    jz .Lhir_no
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lhir_no
    mov r12, rbx
    add r12, [rbx + HI_bytes]
    jc .Lhir_no
    lea rax, [rbx + HI_SIZE]
    cmp [rbx + HI_owner], rax
    jne .Lhir_no
    mov rdx, [rbx + HI_name]
    sub rdx, rax
    cmp rdx, 2
    jb .Lhir_no
    cmp rdx, 101
    ja .Lhir_no
    mov rcx, [rbx + HI_name]
    cmp rcx, r12
    jae .Lhir_no
    cmp byte ptr [rcx - 1], 0
    jne .Lhir_no
    mov rax, [rbx + HI_state]
    sub rax, rcx
    cmp rax, 2
    jb .Lhir_no
    cmp rax, 101
    ja .Lhir_no
    mov rcx, [rbx + HI_state]
    cmp rcx, r12
    jae .Lhir_no
    cmp byte ptr [rcx - 1], 0
    jne .Lhir_no
    mov rax, r12
    cmp byte ptr [rax - 1], 0
    jne .Lhir_no
    sub rax, rcx
    cmp rax, 1
    jb .Lhir_no
    cmp rax, 4096
    ja .Lhir_no
    mov eax, 1
    EPILOGUE
.Lhir_no:
    xor eax, eax
    EPILOGUE

FN ext_host_identity_retain
    PROLOGUE
    call hi_is_ready
    test eax, eax
    jz .Lhi_ref_bad
    call prep_object_retain
    EPILOGUE
.Lhi_ref_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

FN ext_host_identity_release
    PROLOGUE
    call hi_is_owned
    test eax, eax
    jz .Lhi_drop_bad
    call prep_object_release_deferred
    EPILOGUE
.Lhi_drop_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    EPILOGUE

.macro HI_VIEW name, field
FN \name
    PROLOGUE
    mov rbx, rdi
    call hi_is_ready
    test eax, eax
    jz 1f
    mov rax, [rbx + \field]
1:  EPILOGUE
.endm
HI_VIEW ext_host_identity_owner, HI_owner
HI_VIEW ext_host_identity_name, HI_name
HI_VIEW ext_host_identity_state, HI_state
