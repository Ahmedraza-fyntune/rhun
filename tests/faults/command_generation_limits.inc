# Owned real input caps and duplicate/runtime liveness build refusals.
.bss
.p2align 3
cgbt_limit_name: .zero 8
.text
cgbt_limit_name_make:
    lea r8, [rip + cgbt_limit_hex]
    lea r9, [rip + cgbt_limit_name]
    mov byte ptr [r9], 'n'
    mov rcx, rdi
    shr rcx, 4
    and ecx, 15
    movzx eax, byte ptr [r8 + rcx]
    mov [r9 + 1], al
    and edi, 15
    movzx eax, byte ptr [r8 + rdi]
    mov [r9 + 2], al
    mov byte ptr [r9 + 3], 0
    mov rax, r9
    ret
cgbt_limits:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 12
    # Per-slot64 is reached through64 real checked retains, then65 leaves it unchanged.
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov r12, rcx
    mov r13d, 63
1:  mov rdi, rbx
    mov rsi, r12
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    dec r13
    jnz 1b
    cmp qword ptr [r12 + RO_refs], 64
    jne cgbt_fail
    cmp qword ptr [rbx + CG_slots + CS_runtime], 64
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nruntimes], 64
    jne cgbt_fail
    mov rdi, rbx
    mov rsi, r12
    call command_generation_add_runtime
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [r12 + RO_refs], 64
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nruntimes], 64
    jne cgbt_fail
    cmp qword ptr [rbx + CG_ncommands], 65
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    # Exactly8192 retained runtime rows across all128 actual ready, uniquely named suppliers.
    mov qword ptr [rip + cgbt_stage], 13
    call cgbt_new
    mov rbx, rax
    xor r14d, r14d
.Lcgbl_global_slot:
    mov rdi, r14
    call cgbt_limit_name_make
    mov rsi, rax
    lea rdi, [rip + cgbt_one]
    xor edx, edx
    call cgbt_ep
    mov r12, rax
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    imul rdx, r14, EXT_SIZE
    lea rax, [rip + cgbt_exts]
    add rdx, rax
    mov rcx, r14
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    imul rax, r14, EXT_SIZE
    lea rdx, [rip + cgbt_exts]
    add rax, rdx
    mov [rip + cgbt_roc + ROC_target], rax
    mov rax, [r12 + EP_ext + EXT_name]
    mov [rip + cgbt_roc + ROC_name], rax
    lea rax, [rip + cgbt_one]
    mov [rip + cgbt_roc + ROC_owner], rax
    lea rax, [rip + cgbt_dynamic]
    mov [rip + cgbt_roc + ROC_key], rax
    lea rax, [rip + cgbt_rawtitle]
    mov [rip + cgbt_roc + ROC_title], rax
    lea rax, [rip + cgbt_runtimekeys]
    mov [rip + cgbt_roc + ROC_keys], rax
    mov qword ptr [rip + cgbt_roc + ROC_keyslen], 10
    mov qword ptr [rip + cgbt_roc + ROC_session], 7
    lea rdi, [rip + cgbt_roc]
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r13, rax
    test r14, r14
    jnz 1f
    mov r15, rax
1:  mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov r12d, 64
.Lcgbl_global_runtime:
    mov rdi, rbx
    mov rsi, r13
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    dec r12
    jnz .Lcgbl_global_runtime
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [r13 + RO_refs], 64
    jne cgbt_fail
    inc r14
    cmp r14, 128
    jb .Lcgbl_global_slot
    cmp qword ptr [rbx + CG_nruntimes], 8192
    jne cgbt_fail
    cmp qword ptr [rbx + CG_ncommands], 8192
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nslots], 128
    jne cgbt_fail
    mov rdi, rbx
    mov rsi, r15
    call command_generation_add_runtime
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [r15 + RO_refs], 64
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nruntimes], 8192
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    # Genuine ledger-owned32768PC array with valid duplicate legacy entries, not a forged count.
    mov qword ptr [rip + cgbt_stage], 14
    call cgbt_new
    mov rbx, rax
    lea rdi, [rip + cgbt_one]
    lea rsi, [rip + cgbt_tool]
    xor edx, edx
    call cgbt_ep
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov r13, [r12 + EP_commands]
    mov rdi, r12
    mov esi, 32768 * PC_SIZE
    call prep_owned_alloc
    test rax, rax
    jz cgbt_fail
    mov r14, rax
    xor r15d, r15d
1:  imul rdi, r15, PC_SIZE
    add rdi, r14
    mov rsi, r13
    mov edx, PC_SIZE
    call memcpy
    inc r15
    cmp r15, 32768
    jb 1b
    mov [r12 + EP_commands], r14
    mov qword ptr [r12 + EP_commands + VEC_len], 32768
    mov qword ptr [r12 + EP_commands + VEC_cap], 32768
    mov dword ptr [r12 + EP_ext + EXT_ncmd], 32768
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    lea rdi, [rip + cgbt_two]
    lea rsi, [rip + cgbt_other]
    xor edx, edx
    call cgbt_ep
    mov r13, rax
    mov rdi, r13
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov qword ptr [r13 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r13
    mov edx, 2
    mov ecx, 94
    call command_generation_add_extension
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [r13 + PO_refs], 1
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nmanifest], 32768
    jne cgbt_fail
    cmp qword ptr [rbx + CG_ncommands], 32768
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nslots], 1
    jne cgbt_fail
    mov rdi, r13
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    # The same retained runtime object cannot be published twice, nor can equal own wires.
    mov qword ptr [rip + cgbt_stage], 15
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov r12, rcx
    mov rdi, rbx
    mov rsi, r12
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [r12 + RO_refs], 2
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_build
    cmp rax, -17
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    lea rdi, [rip + cgbt_roc]
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_build
    cmp rax, -17
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    # Revocation after accepted retention is rechecked by bounded row construction.
    mov qword ptr [rip + cgbt_stage], 16
    lea rdi, [rip + cgbt_dynamic]
    call cgbt_small
    mov rbx, rax
    mov rdi, rcx
    call ext_runtime_revoke
    mov rdi, rbx
    call cgbt_build
    cmp rax, -116
    jne cgbt_fail
    cmp qword ptr [rbx + PO_ready], 0
    jne cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE
.section .rodata
cgbt_limit_hex: .ascii "0123456789abcdef"
