.bss
.p2align 3
cgt_context_bad: .zero 24
cgt_input_saved: .zero CG_SIZE
cgt_bad_runtime: .zero ROC_SIZE
.text
# Sticky failure must precede all input argument access, preserving the entire admitted state.
cgt_sticky:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + cgt_input_saved]
    mov rsi, rbx
    mov edx, CG_SIZE
    call memcpy
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    mov rcx, -1
    call command_generation_add_extension
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    mov esi, 1
    mov rdx, -1
    mov ecx, 1
    mov r8d, 1
    call command_generation_add_identity
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    mov esi, 1
    call command_generation_add_runtime
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    mov rsi, -1
    mov rdx, -1
    call command_generation_key_begin
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call command_generation_key_append
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    call command_generation_key_finish
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    call command_generation_seal
    cmp rax, r12
    jne cgt_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call command_generation_step
    cmp rax, r12
    jne cgt_fail
    test rdx, rdx
    jnz cgt_fail
    mov rdi, rbx
    lea rsi, [rip + cgt_input_saved]
    mov edx, CG_SIZE
    call memeq
    test eax, eax
    jz cgt_fail
    EPILOGUE
cgt_input_faults:
    PROLOGUE
    mov qword ptr [rip + cgt_stage], 9
    xor edi, edi
    call command_generation_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, -22
    jne cgt_fail
    test rcx, rcx
    jnz cgt_fail
    xor r14d, r14d
.Lcgtif_context:
    lea rdi, [rip + cgt_context_bad]
    lea rsi, [rip + cgt_context]
    mov edx, 24
    call memcpy
    lea rdi, [rip + cgt_context_bad]
    mov qword ptr [rdi + r14 * 8], 0
    call command_generation_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, -22
    jne cgt_fail
    test rcx, rcx
    jnz cgt_fail
    lea rdi, [rip + cgt_context_bad]
    mov qword ptr [rdi + r14 * 8], -1
    call command_generation_begin
    test rax, rax
    jnz cgt_fail
    cmp rdx, -22
    jne cgt_fail
    test rcx, rcx
    jnz cgt_fail
    inc r14
    cmp r14, 3
    jb .Lcgtif_context
    # Identity copy and key buffer allocation failures cannot admit a partial input.
    xor r14d, r14d
.Lcgtif_alloc:
    mov qword ptr [rip + cgt_stage], 10
    call cgt_new
    mov rbx, rax
    mov qword ptr [rip + cgt_fail_alloc], 1
    mov qword ptr [rip + cgt_alloc_count], 0
    test r14, r14
    jnz 1f
    mov rdi, rbx
    mov esi, 1
    mov edx, 17
    lea rcx, [rip + cgt_owner]
    lea r8, [rip + cgt_name]
    call command_generation_add_identity
    jmp 2f
1:  mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call command_generation_key_begin
2:  cmp rax, -12
    jne cgt_fail
    cmp qword ptr [rip + cgt_alloc_count], 1
    jne cgt_fail
    mov qword ptr [rip + cgt_fail_alloc], 0
    cmp qword ptr [rbx + CG_nslots], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_openkey], 0
    jne cgt_fail
    mov rdi, rbx
    mov rsi, -12
    call cgt_sticky
    mov rdi, rbx
    call cgt_abort
    inc r14
    cmp r14, 2
    jb .Lcgtif_alloc
    # Each distinct uniqueness dimension refuses before copying a second identity.
    xor r14d, r14d
.Lcgtif_duplicate:
    mov qword ptr [rip + cgt_stage], 11
    call cgt_new
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    mov edx, 17
    lea rcx, [rip + cgt_owner]
    lea r8, [rip + cgt_name]
    call command_generation_add_identity
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    mov esi, 2
    mov edx, 18
    lea rcx, [rip + cgt_other]
    lea r8, [rip + cgt_name]
    test r14, r14
    jnz 1f
    mov esi, 1
    jmp 3f
1:  cmp r14, 1
    jne 2f
    mov edx, 17
    jmp 3f
2:  lea rcx, [rip + cgt_owner]
3:  call command_generation_add_identity
    cmp rax, -17
    jne cgt_fail
    cmp qword ptr [rbx + CG_nslots], 1
    jne cgt_fail
    mov rdi, rbx
    mov rsi, -17
    call cgt_sticky
    mov rdi, rbx
    call cgt_abort
    inc r14
    cmp r14, 3
    jb .Lcgtif_duplicate
    # Zero/excess append, incomplete finish, input interleaving and post-seal calls.
    xor r14d, r14d
.Lcgtif_state:
    mov qword ptr [rip + cgt_stage], 12
    call cgt_new
    mov rbx, rax
    cmp r14, 5
    je .Lcgtif_sealed
    mov rdi, rax
    mov esi, 5
    xor edx, edx
    call command_generation_key_begin
    test rax, rax
    jnz cgt_fail
    cmp r14, 3
    je .Lcgtif_incomplete
    cmp r14, 4
    je .Lcgtif_interleave
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    test r14, r14
    jz .Lcgtif_append
    mov edx, 4097
    cmp r14, 1
    je .Lcgtif_append
    mov edx, 6
.Lcgtif_append:
    call command_generation_key_append
    jmp .Lcgtif_refused
.Lcgtif_incomplete:
    mov rdi, rbx
    call command_generation_key_finish
    jmp .Lcgtif_refused
.Lcgtif_sealed:
    mov rdi, rbx
    call command_generation_seal
    test rax, rax
    jnz cgt_fail
.Lcgtif_interleave:
    mov rdi, rbx
    mov esi, 1
    mov edx, 17
    lea rcx, [rip + cgt_owner]
    lea r8, [rip + cgt_name]
    call command_generation_add_identity
.Lcgtif_refused:
    cmp rax, -22
    jne cgt_fail
    cmp qword ptr [rbx + CG_nslots], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_keycursor], 0
    jne cgt_fail
    mov rdi, rbx
    mov rsi, -22
    call cgt_sticky
    mov rdi, rbx
    call cgt_abort
    inc r14
    cmp r14, 6
    jb .Lcgtif_state
    call cgt_supplier_refusals
    EPILOGUE
# A genuine empty EP is still sufficient to test typed supplier admission and ownership.
cgt_empty_ep:
    PROLOGUE
    mov rdi, -1
    lea rsi, [rip + cgt_path]
    lea rdx, [rip + cgt_owner]
    lea rcx, [rip + cgt_name]
    call ext_prepare_alloc
    test rax, rax
    jz cgt_fail
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_enable_deferred
    test rax, rax
    jnz cgt_fail
    mov qword ptr [rbx + PO_ready], 1
    mov rax, rbx
    EPILOGUE
cgt_supplier_refusals:
    PROLOGUE
    xor r14d, r14d
.Lcgtis_ep:
    mov qword ptr [rip + cgt_stage], 13
    call cgt_new
    mov rbx, rax
    call cgt_empty_ep
    mov r12, rax
    mov r15, [rax - RD_PO_BACK + RD_state]
    test r14, r14
    jnz 1f
    mov qword ptr [rax + PO_ready], 0
    jmp 4f
1:  cmp r14, 1
    jne 2f
    mov qword ptr [rax + PO_refs], 0
    jmp 4f
2:  cmp r14, 2
    jne 3f
    mov qword ptr [rax - RD_PO_BACK + RD_kind], RD_LEDGER
    jmp 4f
3:  or qword ptr [rax - RD_PO_BACK + RD_state], RD_READY
4:  mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov ecx, 17
    call command_generation_add_extension
    cmp rax, -22
    jne cgt_fail
    cmp qword ptr [rbx + CG_nslots], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_ncommands], 0
    jne cgt_fail
    mov eax, 1
    cmp r14, 1
    jne 5f
    xor eax, eax
5:  cmp [r12 + PO_refs], rax
    jne cgt_fail
    # Restore only deliberately invalid test state before releasing the original caller owner.
    mov qword ptr [r12 + PO_ready], 1
    mov qword ptr [r12 + PO_refs], 1
    mov qword ptr [r12 - RD_PO_BACK + RD_kind], RD_EP
    mov [r12 - RD_PO_BACK + RD_state], r15
    mov rdi, rbx
    mov rsi, -22
    call cgt_sticky
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    inc r14
    cmp r14, 4
    jb .Lcgtis_ep
    xor r14d, r14d
.Lcgtis_ro:
    mov qword ptr [rip + cgt_stage], 14
    call cgt_new
    mov rbx, rax
    cmp r14, 7
    je .Lcgtis_identity_only
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
    jmp .Lcgtis_ro_make
.Lcgtis_identity_only:
    mov rdi, rbx
    mov esi, 1
    mov edx, 17
    lea rcx, [rip + cgt_owner]
    lea r8, [rip + cgt_name]
    call command_generation_add_identity
    test rax, rax
    jnz cgt_fail
.Lcgtis_ro_make:
    lea rdi, [rip + cgt_bad_runtime]
    lea rsi, [rip + cgt_runtime]
    mov edx, ROC_SIZE
    call memcpy
    test r14, r14
    jnz 1f
    mov qword ptr [rip + cgt_bad_runtime + ROC_target], 2
    jmp 3f
1:  cmp r14, 1
    jne 2f
    lea rax, [rip + cgt_other]
    mov [rip + cgt_bad_runtime + ROC_owner], rax
    jmp 3f
2:  cmp r14, 2
    jne 3f
    lea rax, [rip + cgt_other]
    mov [rip + cgt_bad_runtime + ROC_name], rax
3:  lea rdi, [rip + cgt_bad_runtime]
    call ext_runtime_new
    test rax, rax
    jz cgt_fail
    mov r13, rax
    mov r15, [rax - RD_SIZE + RD_state]
    cmp r14, 3
    jne 4f
    mov rdi, rax
    call ext_runtime_revoke
    jmp 7f
4:  cmp r14, 4
    jne 5f
    mov qword ptr [rax + RO_refs], 0
    jmp 7f
5:  cmp r14, 5
    jne 6f
    mov qword ptr [rax - RD_SIZE + RD_kind], 4
    jmp 7f
6:  cmp r14, 6
    jne 7f
    or qword ptr [rax - RD_SIZE + RD_state], RD_READY
7:  mov rdi, rbx
    mov rsi, r13
    call command_generation_add_runtime
    cmp rax, -22
    jne cgt_fail
    cmp qword ptr [rbx + CG_nruntimes], 0
    jne cgt_fail
    cmp qword ptr [rbx + CG_ncommands], 0
    jne cgt_fail
    # No rejected supplier retain. Valid-ref cases remain exactly1 before test-state restoration.
    mov eax, 1
    cmp r14, 4
    jne 8f
    xor eax, eax
8:  cmp [r13 + RO_refs], rax
    jne cgt_fail
    mov qword ptr [r13 + RO_refs], 1
    mov qword ptr [r13 + RO_live], 1
    mov qword ptr [r13 - RD_SIZE + RD_kind], 5
    mov [r13 - RD_SIZE + RD_state], r15
    mov rdi, rbx
    mov rsi, -22
    call cgt_sticky
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    inc r14
    cmp r14, 8
    jb .Lcgtis_ro
    EPILOGUE
