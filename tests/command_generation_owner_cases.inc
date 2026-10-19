.bss
.p2align 3
cgo_owner: .quad 0
cgo_po: .quad 0
cgo_tag: .quad 0
cgo_saved: .zero 112
cgo_context: .zero 24
cgo_drop_refuse: .quad 0
cgo_drop_count: .quad 0
.globl cgo_unmap_target, cgo_unmap_armed, cgo_unmap_hits
cgo_unmap_target: .quad 0
cgo_unmap_armed: .quad 0
cgo_unmap_hits: .quad 0
cgo_native_charge: .quad 0
cgo_native_live: .quad 0
cgo_custom_refuse: .quad 0
.text
cgo_new_owner:
    PROLOGUE
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz cgt_fail
    mov [rip + cgo_owner], rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    jnz cgt_fail
    lea rdi, [rip + cgo_saved]
    mov rsi, [rip + cgo_owner]
    sub rsi, RD_SIZE
    mov edx, EO_SIZE + RD_SIZE
    call memcpy
    EPILOGUE
cgo_begin:
    mov rdi, [rip + cgo_owner]
    lea rsi, [rip + cgt_context]
    jmp command_generation_begin_in_owner
cgo_drop_owner:
    inc qword ptr [rip + cgo_drop_count]
    cmp qword ptr [rip + cgo_drop_refuse], 0
    je 1f
    mov qword ptr [rip + cgo_drop_refuse], 0
    mov rax, -5
    xor edx, edx
    ret
1:  jmp ext_prepare_owner_release_deferred
cgo_finish_owner:
    PROLOGUE
    mov rdi, [rip + cgo_owner]
    call cgo_drop_owner
    cmp rdx, 1
    jne cgt_fail
    test rax, rax
    jnz cgt_fail
    mov qword ptr [rip + cgo_owner], 0
    call cgt_drain
    EPILOGUE
cgo_release:
    mov rdi, [rip + cgo_po]
    mov rsi, [rip + cgo_tag]
    jmp command_generation_constructor_release
cgo_expect_refused:
    PROLOGUE
    call cgo_release
    cmp rax, -22
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    mov rax, [rip + cgo_po]
    cmp qword ptr [rax + PO_refs], 1
    jne cgt_fail
    EPILOGUE
cgo_accept_po:
    PROLOGUE
    call cgo_release
    test rax, rax
    jnz cgt_fail
    cmp rdx, 1
    jne cgt_fail
    mov qword ptr [rip + cgo_po], 0
    mov qword ptr [rip + cgo_tag], 0
    EPILOGUE
cgo_test_cases:
    PROLOGUE
    mov qword ptr [rip + cgt_stage], 40
    xor edi, edi
    lea rsi, [rip + cgt_context]
    call command_generation_begin_in_owner
    test rax, rax
    jnz cgt_fail
    cmp rdx, -22
    jne cgt_fail
    or rcx, r8
    jnz cgt_fail
    xor edi, edi
    xor esi, esi
    call command_generation_constructor_release
    test rax, rax
    jnz cgt_fail
    cmp rdx, 1
    jne cgt_fail
    xor edi, edi
    mov esi, 2
    call command_generation_constructor_release
    cmp rax, -22
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    # Actual owned EO with one invalid field at a time. Restore only test mutations.
    xor r14d, r14d
.Lcgo_shape_loop:
    call cgo_new_owner
    lea r15, [rip + cgo_bad_owner]
    imul rax, r14, 24
    add r15, rax
    mov rbx, [rip + cgo_owner]
    mov rcx, [r15]
    mov rax, [r15 + 8]
    mov [rbx + rcx], rax
    call cgo_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, [r15 + 16]
    jne cgt_fail
    or rcx, r8
    jnz cgt_fail
    mov rdi, rbx
    sub rdi, RD_SIZE
    lea rsi, [rip + cgo_saved]
    mov edx, EO_SIZE + RD_SIZE
    call memcpy
    call cgo_finish_owner
    inc r14
    cmp r14, 10
    jb .Lcgo_shape_loop
    # All tuple components must be positive before any creation/ref increment.
    xor r14d, r14d
.Lcgo_context_loop:
    call cgo_new_owner
    lea rdi, [rip + cgo_context]
    lea rsi, [rip + cgt_context]
    mov edx, 24
    call memcpy
    lea rsi, [rip + cgo_context]
    mov qword ptr [rsi + r14*8], 0
    mov rdi, [rip + cgo_owner]
    call command_generation_begin_in_owner
    test rax, rax
    jnz cgt_fail
    cmp rdx, -22
    jne cgt_fail
    or rcx, r8
    jnz cgt_fail
    mov rbx, [rip + cgo_owner]
    cmp qword ptr [rbx + EO_refs], 1
    jne cgt_fail
    call cgo_finish_owner
    inc r14
    cmp r14, 3
    jb .Lcgo_context_loop
    # Largest admitted signed reference can increment once, then retire independently.
    call cgo_new_owner
    mov rbx, [rip + cgo_owner]
    mov rax, 0x7ffffffffffffffe
    mov [rbx + EO_refs], rax
    call cgo_begin
    test rax, rax
    jz cgt_fail
    or rdx, rcx
    jnz cgt_fail
    cmp r8, 4
    jne cgt_fail
    mov [rip + cgo_po], rax
    mov [rip + cgo_tag], r8
    mov rax, 0x7fffffffffffffff
    cmp [rbx + EO_refs], rax
    jne cgt_fail
    call cgo_accept_po
    mov r15d, 1000
.Lcgo_max_ref_drain:
    mov edi, 1
    lea rsi, [rip + cgt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgt_fail
    jz 2f
    dec r15
    jnz .Lcgo_max_ref_drain
    jmp cgt_fail
2:  mov rax, 0x7ffffffffffffffe
    cmp [rbx + EO_refs], rax
    jne cgt_fail
    mov qword ptr [rbx + EO_refs], 1
    call cgo_finish_owner
    # Insufficient caller-domain capacity fails before another allocation is attempted.
    call cgo_new_owner
    mov rbx, [rip + cgo_owner]
    mov rax, [rbx + EO_used]
    mov [rbx + EO_cap], rax
    mov qword ptr [rip + cgt_fail_alloc], 1
    mov qword ptr [rip + cgt_alloc_count], 0
    call cgo_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, -EV_RESOURCE
    jne cgt_fail
    or rcx, r8
    jnz cgt_fail
    cmp qword ptr [rip + cgt_alloc_count], 0
    jne cgt_fail
    cmp qword ptr [rbx + EO_refs], 1
    jne cgt_fail
    mov qword ptr [rip + cgt_fail_alloc], 0
    call cgo_finish_owner
    # A single actual allocation failure leaves the preheld EO independently owned.
    mov qword ptr [rip + cgt_stage], 41
    call cgo_new_owner
    mov qword ptr [rip + cgt_fail_alloc], 1
    mov qword ptr [rip + cgt_alloc_count], 0
    call cgo_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, -12
    jne cgt_fail
    or rcx, r8
    jnz cgt_fail
    cmp qword ptr [rip + cgt_alloc_count], 1
    jne cgt_fail
    mov qword ptr [rip + cgt_fail_alloc], 0
    mov rbx, [rip + cgo_owner]
    cmp qword ptr [rbx + EO_refs], 1
    jne cgt_fail
    cmp qword ptr [rbx + EO_error], -12
    jne cgt_fail
    call cgo_finish_owner
    # A real smaller generic PO cannot be mistaken for a CG creation block.
    call cgo_new_owner
    mov rdi, [rip + cgo_owner]
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz cgt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 2
    call command_generation_constructor_release
    cmp rax, -22
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgt_fail
    mov rdi, rbx
    call prep_object_release_deferred
    cmp rdx, 1
    jne cgt_fail
    call cgo_finish_owner
    # Generic fallback exists before any external supplier/input acquisition.
    mov qword ptr [rip + cgt_stage], 42
    call cgo_new_owner
    mov qword ptr [rip + cgt_fail_mark], 1
    call cgo_begin
    mov qword ptr [rip + cgt_fail_mark], 0
    test rax, rax
    jz cgt_fail
    cmp rdx, -5
    jne cgt_fail
    test rcx, rcx
    jnz cgt_fail
    cmp r8, 2
    jne cgt_fail
    mov [rip + cgo_po], rax
    mov [rip + cgo_tag], r8
    mov rbx, rax
    cmp qword ptr [rbx + PO_eo], 0
    je cgt_fail
    mov rax, [rip + cgo_owner]
    cmp [rbx + PO_eo], rax
    jne cgt_fail
    cmp qword ptr [rax + EO_refs], 2
    jne cgt_fail
    mov qword ptr [rip + cgo_tag], 4
    call cgo_expect_refused
    mov qword ptr [rip + cgo_tag], 2
    mov qword ptr [rbx + PO_refs], 2
    call cgo_release
    cmp rax, -22
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne cgt_fail
    mov qword ptr [rbx + PO_refs], 1
    xor r14d, r14d
.Lcgo_generic_loop:
    lea r15, [rip + cgo_bad_generic]
    imul rax, r14, 16
    add r15, rax
    mov rcx, [r15]
    mov r12, [rbx + rcx]
    mov rax, [r15 + 8]
    mov [rbx + rcx], rax
    call cgo_expect_refused
    mov rcx, [r15]
    mov [rbx + rcx], r12
    inc r14
    cmp r14, 9
    jb .Lcgo_generic_loop
    # Refused independent caller drop cannot be erased by a later PO release.
    mov qword ptr [rip + cgo_drop_refuse], 1
    mov rdi, [rip + cgo_owner]
    call cgo_drop_owner
    cmp rax, -5
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    mov rax, [rip + cgo_owner]
    cmp qword ptr [rax + EO_refs], 2
    jne cgt_fail
    call cgo_accept_po
    # GC drops only the PO's EO ref. The initial caller EO survives.
    mov r15d, 1000
.Lcgo_partial_drain:
    mov edi, 1
    lea rsi, [rip + cgt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgt_fail
    jz 1f
    dec r15
    jnz .Lcgo_partial_drain
    jmp cgt_fail
1:  mov rax, [rip + cgo_owner]
    cmp qword ptr [rax + EO_refs], 1
    jne cgt_fail
    call cgo_finish_owner
    # Even an injected post-mark diagnostic must return the actual custom kind.
    call cgo_new_owner
    mov qword ptr [rip + cgt_fail_mark], 2
    call cgo_begin
    mov qword ptr [rip + cgt_fail_mark], 0
    test rax, rax
    jz cgt_fail
    cmp rdx, -5
    jne cgt_fail
    test rcx, rcx
    jnz cgt_fail
    cmp r8, 4
    jne cgt_fail
    mov [rip + cgo_po], rax
    mov [rip + cgo_tag], r8
    cmp qword ptr [rax + CG_intent], 0
    jne cgt_fail
    call cgo_accept_po
    call cgo_finish_owner
    # Success with actual independently owned EP/RO suppliers and native ledger failure.
    mov qword ptr [rip + cgt_stage], 43
    call cgo_new_owner
    call cgo_begin
    test rax, rax
    jz cgt_fail
    or rdx, rcx
    jnz cgt_fail
    cmp r8, 4
    jne cgt_fail
    mov [rip + cgo_po], rax
    mov [rip + cgo_tag], r8
    mov rbx, rax
    cmp qword ptr [rbx + CG_intent], 11
    jne cgt_fail
    cmp qword ptr [rbx + CG_keyepoch], 12
    jne cgt_fail
    cmp qword ptr [rbx + CG_visibility], 13
    jne cgt_fail
    call cgt_empty_ep
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    mov edx, 1
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgt_fail
    lea rdi, [rip + cgt_runtime]
    call ext_runtime_new
    test rax, rax
    jz cgt_fail
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call command_generation_add_runtime
    test rax, rax
    jnz cgt_fail
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgt_fail
    mov qword ptr [rip + cgo_tag], 2
    call cgo_expect_refused
    mov qword ptr [rip + cgo_tag], 4
    mov qword ptr [rip + cgo_drop_refuse], 1
    mov rdi, [rip + cgo_owner]
    call cgo_drop_owner
    cmp rax, -5
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    # A kind4 backend refusal must retain the exact reference, without generic fallback.
    mov qword ptr [rip + cgo_custom_refuse], 1
    call cgo_release
    cmp rax, -5
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgt_fail
    lea rax, [rbx - RD_PO_BACK - 16]
    mov [rip + cgo_unmap_target], rax
    mov qword ptr [rip + cgo_unmap_armed], 1
    call cgo_accept_po
    mov qword ptr [rip + cgt_stage], 44
    mov r15d, 1000
.Lcgo_until_native:
    call ext_prepare_retire_charge
    mov [rip + cgo_native_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + cgo_native_live], rax
    mov edi, 1
    lea rsi, [rip + cgt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + cgt_retire], 1
    jne cgt_fail
    cmp qword ptr [rip + cgo_unmap_hits], 1
    je .Lcgo_native_blocked
    test rax, rax
    js cgt_fail
    dec r15
    jnz .Lcgo_until_native
    jmp cgt_fail
.Lcgo_native_blocked:
    cmp rax, 1
    jne cgt_fail
    cmp qword ptr [rip + cgt_retire + 24], -5
    jne cgt_fail
    call ext_prepare_retire_charge
    cmp rax, [rip + cgo_native_charge]
    jne cgt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cgo_native_live]
    jne cgt_fail
    cmp qword ptr [rip + prep_retire_blocked_count], 1
    jne cgt_fail
    mov rax, [rip + cgo_owner]
    cmp qword ptr [rax + EO_refs], 2
    jne cgt_fail
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne cgt_fail
    mov r15d, 1000
.Lcgo_native_finish:
    mov edi, 1
    lea rsi, [rip + cgt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgt_fail
    jz 2f
    dec r15
    jnz .Lcgo_native_finish
    jmp cgt_fail
2:  mov rax, [rip + cgo_owner]
    cmp qword ptr [rax + EO_refs], 1
    jne cgt_fail
    call cgo_finish_owner
    call ext_prepare_retire_ack
    test rax, rax
    jnz cgt_fail
    EPILOGUE
.section .rodata
.p2align 3
cgo_bad_owner:
    .quad -RD_SIZE + RD_kind, 2, -22
    .quad -RD_SIZE + RD_object, 0, -22
    .quad -RD_SIZE + RD_state, RD_READY, -22
    .quad EO_deferred, 0, -22
    .quad EO_refs, 0, -22
    .quad EO_refs, 0x7fffffffffffffff, -75
    .quad EO_error, -7, -7
    .quad EO_cap, PREP_CAP + 1, -22
    .quad EO_used, PREP_CAP + 1, -22
    .quad EO_used, 0, -22
cgo_bad_generic:
    .quad -RD_PO_BACK - 8, 40
    .quad PO_ready, 1
    .quad PO_error, 0
    .quad PO_allocs, 0
    .quad -AO_SIZE + AO_next, 1
    .quad CG_nslots, 1
    .quad CG_nruntimes, 1
    .quad CG_openkey, 1
    .quad CG_defaultnodes, 1
