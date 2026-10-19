# Deferred drops perform no destruction; every pump honors its work budget.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
FN main
    PROLOGUE 80
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lrt_bad
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lrt_bad
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    jnz .Lrt_bad
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrt_bad
    mov r12, rax
    xor r13d, r13d
1:  mov rdi, r12
    mov esi, 17
    call prep_owned_alloc
    test rax, rax
    jz .Lrt_bad
    inc r13
    cmp r13, 1024
    jb 1b
    # Refcounts are unsigned; maximum cannot wrap back to zero.
    mov qword ptr [r12 + PO_ready], 1
    mov qword ptr [r12 + PO_refs], -2
    mov rdi, r12
    call prep_object_retain
    test rax, rax
    jnz .Lrt_bad
    mov rdi, r12
    call prep_object_retain
    cmp rax, -75
    jne .Lrt_bad
    mov qword ptr [r12 + PO_refs], 1
    mov rdi, rbx
    call ext_prepare_owner_release
    test rax, rax
    jnz .Lrt_bad
    call ext_prepare_retire_charge
    mov r14, rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 16], rax
    mov rdi, r12
    call grammar_prepare_release_deferred
    test rax, rax
    jnz .Lrt_bad
    cmp rdx, 1
    jne .Lrt_bad
    call ext_prepare_retire_charge
    cmp rax, r14
    jne .Lrt_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 16]
    jne .Lrt_bad
    mov rdi, r12
    call grammar_prepare_release_deferred
    cmp rax, -EV_BAD_PREPARE
    jne .Lrt_bad
    test rdx, rdx
    jnz .Lrt_bad
    mov rdi, r12
    call prep_object_retain
    cmp rax, -EV_BAD_PREPARE
    jne .Lrt_bad
    lea rdi, [rsp + 32]
    mov esi, 0x55
    mov edx, 32
    call memset
    xor edi, edi
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    cmp rax, -22
    jne .Lrt_bad
    mov edi, 65
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    cmp rax, -22
    jne .Lrt_bad
    mov r15, 0x5555555555555555
    xor ecx, ecx
2:  cmp [rsp + 32 + rcx*8], r15
    jne .Lrt_bad
    inc rcx
    cmp rcx, 4
    jb 2b
    mov qword ptr [rsp + 8], 0
3:  mov r15, [rip + g_mem_live]
    mov edi, 1
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    test rax, rax
    js .Lrt_bad
    mov r14, rax
    cmp qword ptr [rsp + 32], 1
    jne .Lrt_bad
    cmp qword ptr [rsp + 48], 0
    jne .Lrt_bad
    cmp qword ptr [rsp + 56], 0
    jne .Lrt_bad
    mov rax, [rip + g_mem_live]
    cmp rax, r15
    ja .Lrt_bad
    sub r15, rax
    cmp r15, 1
    ja .Lrt_bad
    inc qword ptr [rsp + 8]
    cmp qword ptr [rsp + 8], 1032
    ja .Lrt_bad
    test r14, r14
    jnz 3b
    cmp qword ptr [rsp + 8], 1026
    jb .Lrt_bad
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lrt_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lrt_bad
    # Two independent ledgers sharing one EO rotate fairly, without recursive drains.
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lrt_bad
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrt_bad
    mov r12, rax
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrt_bad
    mov r13, rax
    mov r14d, 4
4:  mov rdi, r12
    mov esi, 5
    call prep_owned_alloc
    test rax, rax
    jz .Lrt_bad
    mov rdi, r13
    mov esi, 5
    call prep_owned_alloc
    test rax, rax
    jz .Lrt_bad
    dec r14
    jnz 4b
    mov rdi, rbx
    call ext_prepare_owner_release
    mov rdi, r12
    call prep_owned_dispose
    test rax, rax
    jnz .Lrt_bad
    mov rdi, r13
    call prep_owned_dispose
    test rax, rax
    jnz .Lrt_bad
    mov r14, [r12 + PO_allocs]
    mov r15, [r13 + PO_allocs]
    mov edi, 1
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrt_bad
    cmp [r12 + PO_allocs], r14
    je .Lrt_bad
    cmp [r13 + PO_allocs], r15
    jne .Lrt_bad
    mov r14, [r12 + PO_allocs]
    mov edi, 1
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrt_bad
    cmp [r12 + PO_allocs], r14
    jne .Lrt_bad
    cmp [r13 + PO_allocs], r15
    je .Lrt_bad
5:  mov edi, 64
    lea rsi, [rsp + 32]
    call ext_prepare_retire_step
    test rax, rax
    js .Lrt_bad
    cmp qword ptr [rsp + 32], 64
    ja .Lrt_bad
    test rax, rax
    jnz 5b
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lrt_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lrt_bad
    call ext_prepare_retire_ack
    test rax, rax
    jnz .Lrt_bad
    xor eax, eax
    EPILOGUE
.Lrt_bad:
    mov eax, 1
    EPILOGUE
