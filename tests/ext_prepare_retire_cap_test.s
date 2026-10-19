# Rounded global admission includes queued allocations and never drains them implicitly.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
FN main
    PROLOGUE 112
    mov rax, [rip + g_mem_live]
    mov [rsp + 96], rax
    xor r12d, r12d
1:  mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lcap_bad
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lcap_bad
    mov [rsp + r12*8], rax
    mov rdi, rbx
    call ext_prepare_owner_release
    mov rdi, [rsp + r12*8]
    mov esi, 32 * 1024 * 1024
    call prep_owned_alloc
    cmp r12, 7
    je 2f
    test rax, rax
    jz .Lcap_bad
    inc r12
    jmp 1b
2:  test rax, rax
    jnz .Lcap_bad
    cmp rdx, -EV_RESOURCE
    jne .Lcap_bad
    call ext_prepare_retire_charge
    mov r13, rax
    mov r14, [rip + g_mem_live]
    xor r12d, r12d
3:  mov rdi, [rsp + r12*8]
    call prep_owned_dispose
    test rax, rax
    jnz .Lcap_bad
    cmp rdx, 1
    jne .Lcap_bad
    inc r12
    cmp r12, 8
    jb 3b
    call ext_prepare_retire_charge
    cmp rax, r13
    jne .Lcap_bad
    cmp [rip + g_mem_live], r14
    jne .Lcap_bad
    # Refusal does not run a hidden reclamation pass.
    mov edi, PREP_TOTAL_CAP
    call prep_global_admit
    cmp rax, -EV_RESOURCE
    jne .Lcap_bad
    cmp [rip + g_mem_live], r14
    jne .Lcap_bad
4:  mov edi, 3
    lea rsi, [rsp + 64]
    call ext_prepare_retire_step
    test rax, rax
    js .Lcap_bad
    cmp qword ptr [rsp + 80], 0
    jne .Lcap_bad
    cmp qword ptr [rsp + 88], 0
    jne .Lcap_bad
    test rax, rax
    jnz 4b
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lcap_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 96]
    jne .Lcap_bad
    mov edi, PREP_TOTAL_CAP
    call prep_global_admit
    test rax, rax
    jnz .Lcap_bad
    xor eax, eax
    EPILOGUE
.Lcap_bad:
    mov eax, 1
    EPILOGUE
