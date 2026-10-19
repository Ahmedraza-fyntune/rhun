# Typed native callbacks hand back one supplier or one allocation per unit.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
custom_po_step:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + PO_SIZE]
    test rdi, rdi
    jz 1f
    call grammar_prepare_release_deferred
    test rax, rax
    js 2f
    cmp rdx, 1
    jne 2f
    mov qword ptr [rbx + PO_SIZE], 0
    mov eax, 1
    EPILOGUE
1:  mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js 2f
    mov eax, 1
    EPILOGUE
2:  mov rax, -5
    mov edx, 2
    EPILOGUE
custom_simple_step:
    cmp qword ptr [rdi + 8], 0x12345678
    jne 1f
    jmp ext_prepare_retire_free_custom
1:  mov rax, -5
    mov edx, 2
    ret
FN main
    PROLOGUE 48
    mov rax, [rip + g_mem_live]
    mov [rsp + 32], rax
    mov edi, 6
    lea rsi, [rip + custom_po_step]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    jnz .Lct_bad
    mov edi, 6
    lea rsi, [rip + custom_po_step]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    jnz .Lct_bad
    mov edi, 6
    lea rsi, [rip + custom_simple_step]
    xor edx, edx
    call ext_prepare_retire_register_kind
    cmp rax, -17
    jne .Lct_bad
    mov edi, 3
    lea rsi, [rip + custom_simple_step]
    xor edx, edx
    call ext_prepare_retire_register_kind
    cmp rax, -22
    jne .Lct_bad
    mov edi, 7
    lea rsi, [rip + custom_simple_step]
    xor edx, edx
    call ext_prepare_retire_register_kind
    test rax, rax
    jnz .Lct_bad
    mov edi, 100000
    mov esi, 6
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jnz .Lct_bad
    cmp rdx, -22
    jne .Lct_bad
    mov edi, PREP_CAP + 1
    mov esi, 7
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jnz .Lct_bad
    cmp rdx, -EV_RESOURCE
    jne .Lct_bad
    mov edi, 100000
    mov esi, 7
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jz .Lct_bad
    mov r15, rax
    mov qword ptr [rax + 8], 0x12345678
    mov rdi, rax
    call ext_prepare_retire_free_custom
    cmp rax, -22
    jne .Lct_bad
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lct_bad
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lct_bad
    mov r12, rax
    mov rdi, rax
    mov esi, 120000
    call prep_owned_alloc
    test rax, rax
    jz .Lct_bad
    mov rdi, rbx
    mov esi, PO_SIZE + 8
    call prep_object_create
    test rax, rax
    jz .Lct_bad
    mov r13, rax
    mov [r13 + PO_SIZE], r12
    mov rdi, r13
    mov esi, 7
    call ext_prepare_retire_mark_custom_po
    cmp rax, -22
    jne .Lct_bad
    mov rdi, r13
    mov esi, 6
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    jnz .Lct_bad
    mov rdi, rbx
    call ext_prepare_owner_release
    mov r14, [rip + g_mem_live]
    mov rdi, r13
    call ext_prepare_retire_release_custom_po
    test rax, rax
    jnz .Lct_bad
    cmp rdx, 1
    jne .Lct_bad
    lea rdi, [r15 - RD_SIZE]
    call ext_prepare_retire_enqueue_custom
    test rax, rax
    jnz .Lct_bad
    cmp [rip + g_mem_live], r14
    jne .Lct_bad
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lct_bad
    cmp qword ptr [r12 + PO_refs], 0
    jne .Lct_bad
    cmp [rip + g_mem_live], r14
    jne .Lct_bad
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lct_bad
    dec r14
    cmp [rip + g_mem_live], r14
    jne .Lct_bad
1:  mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    test rax, rax
    js .Lct_bad
    cmp qword ptr [rsp + 16], 0
    jne .Lct_bad
    cmp qword ptr [rsp + 24], 0
    jne .Lct_bad
    test rax, rax
    jnz 1b
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lct_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 32]
    jne .Lct_bad
    xor eax, eax
    EPILOGUE
.Lct_bad:
    mov eax, 1
    EPILOGUE
