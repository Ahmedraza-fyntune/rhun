# Typed native owners and read-only views. No live registry/global publication.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.text
# Native object, expected role -> Boolean. Preserves RDI/RSI, accepts owned failure.
FN catalog_is_owned
    xor eax, eax
    test rdi, rdi
    jz .Lcio_no
    lea rcx, [rsi - C7_REGISTRY]
    cmp rcx, 1
    ja .Lcio_no
    cmp [rdi + C7_role], rsi
    jne .Lcio_no
    mov rcx, C7_MAGIC
    cmp [rdi + C7_magic], rcx
    jne .Lcio_no
    cmp qword ptr [rdi + C7_bytes], RG_SIZE
    jne .Lcio_no
    cmp qword ptr [rdi - RD_PO_BACK - 8], RG_SIZE + RD_PO_BACK
    jb .Lcio_no
    mov rcx, [rdi - RD_PO_BACK + RD_state]
    test ecx, RDF_STATE_MASK
    jnz .Lcio_no
    test ecx, RDF_PO
    jz .Lcio_no
    cmp qword ptr [rdi + PO_refs], 0
    je .Lcio_no
    mov rcx, [rdi - RD_PO_BACK + RD_kind]
    cmp rcx, C7_KIND
    je 1f
    cmp rcx, RD_LEDGER
    jne .Lcio_no
    cmp qword ptr [rdi + PO_refs], 1
    jne .Lcio_no
    cmp qword ptr [rdi + PO_ready], 0
    jne .Lcio_no
    cmp qword ptr [rdi + PO_error], 0
    jge .Lcio_no
1:  mov rcx, [rdi + PO_eo]
    test rcx, rcx
    jz .Lcio_no
    cmp qword ptr [rcx + EO_cap], PREP_CAP
    jne .Lcio_no
    cmp qword ptr [rcx + EO_deferred], 1
    jne .Lcio_no
    cmp qword ptr [rcx + EO_lease], -1
    jne .Lcio_no
    cmp qword ptr [rcx + EO_refs], 0
    je .Lcio_no
    cmp qword ptr [rcx - RD_SIZE + RD_kind], RD_EO
    jne .Lcio_no
    test qword ptr [rcx - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lcio_no
    mov eax, 1
.Lcio_no:
    ret

FN catalog_is_ready
    PROLOGUE
    call catalog_is_owned
    test eax, eax
    jz 9f
    xor eax, eax
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], C7_KIND
    jne 9f
    cmp qword ptr [rdi + PO_ready], 1
    jne 9f
    cmp qword ptr [rdi + PO_error], 0
    jne 9f
    mov ecx, RG_READY
    cmp rsi, C7_BASE
    jne 1f
    mov ecx, RB_READY
1:  cmp [rdi + RG_phase], rcx
    jne 9f
    mov eax, 1
9:  EPILOGUE

# An exact native role constructor owns the EO until its explicit initial drop.
FN catalog_object_create
    PROLOGUE 32
    mov rbx, rdi
    lea rax, [rbx - C7_REGISTRY]
    cmp rax, 1
    ja .Lco_invalid
    call catalog_kind7_check
    test rax, rax
    js .Lco_error_null
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lco_null
    mov r12, rax
    mov qword ptr [rax + EO_deferred], 1
    mov rdi, rax
    mov esi, RG_SIZE
    call prep_object_create
    test rax, rax
    jz .Lco_po_failure
    mov r13, rax
    mov [rax + C7_role], rbx
    mov rax, C7_MAGIC
    mov [r13 + C7_magic], rax
    mov qword ptr [r13 + C7_bytes], RG_SIZE
    mov r14d, RG_constructor_eo
    cmp rbx, C7_BASE
    jne 1f
    mov r14d, RB_constructor_eo
1:  mov [r13 + r14], r12
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne .Lco_drop_failure
    mov qword ptr [r13 + r14], 0
    test rax, rax
    js .Lco_drop_failure
    mov rdi, r13
    mov esi, C7_KIND
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    js .Lco_partial
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lco_drop_failure:
    test rax, rax
    js 2f
    mov rax, -EV_BAD_PREPARE
2:  mov r15, rax
    lea rdi, [r13 - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
    mov rax, r15
.Lco_partial:
    mov rdi, r13
    call catalog_fail
    mov rdx, rax
    mov rcx, [r13 - RD_PO_BACK + RD_diagnostic]
    mov rax, r13
    EPILOGUE
.Lco_po_failure:
    mov r13, rdx
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov r14, rax
    cmp rdx, 1
    je 3f
    # Internal invariant failure: keep the sole EO charged in explicit quarantine.
    lea rdi, [r12 - RD_SIZE]
    mov rsi, -EV_BAD_PREPARE
    mov edx, 2
    call prep_retire_enqueue_blocked
    mov r14, -EV_BAD_PREPARE
3:  mov rdx, r13
    mov rcx, r14
    xor eax, eax
    EPILOGUE
.Lco_invalid:
    mov rax, -22
.Lco_error_null:
    mov rdx, rax
.Lco_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# Valid owned RB/RG, negative primary. No child or allocator operation.
FN catalog_fail
    test rax, rax
    js 1f
    mov rax, -EV_BAD_PREPARE
1:  cmp qword ptr [rdi + PO_error], 0
    jne 2f
    mov [rdi + PO_error], rax
    mov [rdi + RG_primary], rax
2:  mov qword ptr [rdi + PO_ready], 0
    mov ecx, RG_FAILED
    cmp qword ptr [rdi + C7_role], C7_BASE
    jne 3f
    mov ecx, RB_FAILED
3:  mov [rdi + RG_phase], rcx
    mov rax, [rdi + PO_error]
    ret

FN registry_base_retain
    mov esi, C7_BASE
    jmp catalog_retain
FN registry_retain
    mov esi, C7_REGISTRY
catalog_retain:
    PROLOGUE
    call catalog_is_ready
    test eax, eax
    jz .Lcre_bad
    call prep_object_retain
    EPILOGUE
.Lcre_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE

FN registry_base_release_deferred
    mov esi, C7_BASE
    jmp catalog_release
FN registry_release_deferred
    mov esi, C7_REGISTRY
catalog_release:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call catalog_is_owned
    test eax, eax
    jz .Lcrel_bad
    mov r13d, RG_constructor_eo
    cmp r12, C7_BASE
    jne 1f
    mov r13d, RB_constructor_eo
1:  mov rdi, [rbx + r13]
    test rdi, rdi
    jz 3f
    cmp [rbx + PO_eo], rdi
    jne .Lcrel_bad
    call ext_prepare_owner_release_deferred
    mov r14, rax
    mov r15, rdx
    lea rdi, [rbx - RD_PO_BACK]
    mov rsi, rax
    call ext_prepare_retire_note_error
    cmp r15, 1
    jne .Lcrel_retained
    mov qword ptr [rbx + r13], 0
3:  mov r12, [rbx - RD_PO_BACK + RD_diagnostic]
    mov rdi, rbx
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    je 4f
    call ext_prepare_retire_release_custom_po
    jmp 5f
4:  call prep_owned_dispose
5:  test rax, rax
    js 6f
    test r12, r12
    jns 6f
    mov rax, r12
6:  EPILOGUE
.Lcrel_retained:
    mov rax, r14
    test rax, rax
    js 7f
    mov rax, -EV_BAD_PREPARE
7:  xor edx, edx
    EPILOGUE
.Lcrel_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    EPILOGUE

FN registry_base_status
    mov esi, C7_BASE
    jmp catalog_status
FN registry_status
    mov esi, C7_REGISTRY
catalog_status:
    PROLOGUE
    mov rbx, rdi
    call catalog_is_owned
    test eax, eax
    jz .Lcstatus_bad
    mov rax, [rbx + RG_phase]
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    mov r8, [rbx + PO_ready]
    EPILOGUE
.Lcstatus_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

FN registry_base_view
    mov esi, C7_BASE
    mov edx, RB_view
    jmp catalog_view
FN registry_view
    mov esi, C7_REGISTRY
    mov edx, RG_view
    jmp catalog_view
catalog_view:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    call catalog_is_ready
    test eax, eax
    jz .Lcv_bad
    lea rax, [rbx + r12]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
.Lcv_bad:
    xor eax, eax
    mov rdx, -EV_BAD_PREPARE
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

FN registry_base_owner
    PROLOGUE
    mov rbx, rdi
    mov esi, C7_REGISTRY
    call catalog_is_ready
    test eax, eax
    jz .Lcv_bad
    mov rax, [rbx + RG_base]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE

FN registry_segments
    PROLOGUE
    mov rbx, rdi
    mov esi, C7_REGISTRY
    call catalog_is_ready
    test eax, eax
    jz .Lcseg_bad
    mov rax, [rbx + RG_base]
    mov rdx, [rax + RB_nbuiltin]
    mov rcx, rdx
    mov r8, [rbx + RG_ngrammar]
    mov rax, [rax + RB_nuser]
    mov rdx, r8
    sub rdx, rax
    sub rdx, rcx
    xor r9d, r9d
    EPILOGUE
.Lcseg_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE

FN registry_theme_source
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, C7_REGISTRY
    call catalog_is_ready
    test eax, eax
    jz .Lcv_bad
    cmp r12, [rbx + RG_ntheme]
    jae .Lcv_bad
    imul rax, r12, TM_SIZE
    add rax, [rbx + RG_meta]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
