# Pure host ownership transfers. All references are preheld by the caller.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extactivation.inc"
.text
# Check launch borrows against the independently retained metadata supplier.
FN ea_host_metadata
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call ea_is_ready
    test eax, eax
    jz .Lehm_stale
    mov r13, [r12 + EA_ep]
    cmp [rbx + EXT_metadata_owner], r13
    jne .Lehm_stale
    cmp qword ptr [r13 + PO_refs], 2
    jb .Lehm_stale
    xor r14d, r14d
1:  lea rax, [rip + ea_host_launch_fields]
    mov rax, [rax + r14*8]
    mov rcx, [r13 + EP_ext + rax]
    cmp [rbx + rax], rcx
    jne .Lehm_stale
    inc r14
    cmp r14, 5
    jb 1b
    mov eax, [r13 + EP_ext + EXT_needs]
    cmp [rbx + EXT_needs], eax
    jne .Lehm_stale
    mov rdi, rbx
    call ext_host_identity_matches
    test eax, eax
    jz .Lehm_stale
    xor r14d, r14d
2:  lea rax, [rip + ea_host_identity_fields]
    mov rax, [rax + r14*8]
    mov rdi, [rbx + rax]
    lea rax, [rip + ea_host_context_fields]
    mov rax, [rax + r14*8]
    mov rsi, [r12 + EA_plan + rax]
    call strcmp_eq
    test eax, eax
    jz .Lehm_stale
    inc r14
    cmp r14, 3
    jb 2b
    xor eax, eax
    EPILOGUE
.Lehm_stale:
    mov rax, -116
    EPILOGUE

FN ext_activation_host_check
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lehc_stale
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lehc_stale
    cmp dword ptr [rbx + EXT_activation_stale], 0
    jne .Lehc_stale
    mov r12, [rbx + EXT_activation_owner]
    mov rdi, r12
    call ext_activation_owner_plan
    test rax, rax
    jz .Lehc_stale
    cmp [rbx + EXT_activation_plan], rax
    jne .Lehc_stale
    mov rsi, [rax + KE_context]
    mov rdi, r12
    call ext_activation_owner_check
    test rax, rax
    js .Lehc_stale
    mov rdi, rbx
    mov rsi, r12
    call ea_host_metadata
    EPILOGUE
.Lehc_stale:
    mov rax, -116
    EPILOGUE

# Running session ownership is independent from a pending START epoch.
# EXT, separately retained expected EA, exact expected native keeper handle.
FN ext_activation_host_running_check
    test rdi, rdi
    jz .Lehr_running_stale
    cmp dword ptr [rdi + EXT_status], ES_RUNNING
    jne .Lehr_running_stale
    jmp ext_activation_host_accepted_check
.Lehr_running_stale:
    mov rax, -116
    ret

# Accepted handshake and graceful stop retain native ownership without new START authority.
FN ext_activation_host_accepted_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .Lehr_stale
    test r12, r12
    jz .Lehr_stale
    test r13, r13
    jle .Lehr_stale
    cmp [rbx + EXT_activation_owner], r12
    jne .Lehr_stale
    cmp [rbx + EXT_keeper], r13
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_activation_stale], 0
    jne .Lehr_stale
    mov eax, [rbx + EXT_status]
    cmp eax, ES_STARTING
    je 1f
    cmp eax, ES_RUNNING
    je 1f
    cmp eax, ES_STOPPING
    jne .Lehr_stale
1:
    cmp dword ptr [rbx + EXT_disabled], 0
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_startaccepted], 1
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lehr_stale
    cmp dword ptr [rbx + EXT_in], 0
    js .Lehr_stale
    cmp dword ptr [rbx + EXT_out], 0
    js .Lehr_stale
    cmp dword ptr [rbx + EXT_host_child_in], 0
    jns .Lehr_stale
    cmp dword ptr [rbx + EXT_host_child_out], 0
    jns .Lehr_stale
    mov rdi, rbx
    call ext_can_act
    test eax, eax
    jz .Lehr_stale
    mov rdi, rbx
    call ext_has_metadata
    test eax, eax
    jz .Lehr_stale
    mov rdi, r12
    call ext_activation_owner_plan
    test rax, rax
    jz .Lehr_stale
    cmp [rbx + EXT_activation_plan], rax
    jne .Lehr_stale
    mov rdi, rbx
    mov rsi, r12
    call ea_host_metadata
    EPILOGUE
.Lehr_stale:
    mov rax, -116
    EPILOGUE

# RAX0/RDX1 transfers incoming ref and writes old owned ref. Error/RDX0 leaves all unchanged.
FN ext_activation_host_swap
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .Lehs_bad
    test r13, r13
    jz .Lehs_bad
    mov rdi, rbx
    call ext_host_native_quiet
    test rax, rax
    jnz .Lehs_busy
    mov r14, [rbx + EXT_activation_owner]
    test r14, r14
    jnz 5f
    cmp qword ptr [rbx + EXT_activation_plan], 0
    jne .Lehs_bad
    jmp 6f
5:  cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lehs_bad
    mov rdi, r14
    call ext_activation_owner_plan
    test rax, rax
    jz .Lehs_bad
    cmp [rbx + EXT_activation_plan], rax
    jne .Lehs_bad
    mov rdi, rbx
    mov rsi, r14
    call ea_host_metadata
    test rax, rax
    js .Lehs_bad
6:  xor r15d, r15d
    test r12, r12
    jz .Lehs_commit
    mov rdi, r12
    call ext_activation_owner_plan
    test rax, rax
    jz .Lehs_stale
    mov r15, rax
    mov rsi, [rax + KE_context]
    mov rdi, r12
    call ext_activation_owner_check
    test rax, rax
    js .Lehs_stale
    cmp r12, r14
    jne 7f
    cmp qword ptr [r12 + PO_refs], 2
    jb .Lehs_bad
7:  mov rdi, rbx
    mov rsi, r12
    call ea_host_metadata
    test rax, rax
    js .Lehs_stale
.Lehs_commit:
    mov rdi, r13
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r14
    call ext_owned_output_check
    test rax, rax
    jnz .Lehs_bad
    mov [r13], r14
    mov [rbx + EXT_activation_owner], r12
    mov [rbx + EXT_activation_plan], r15
    mov eax, 1
    test r12, r12
    jz 8f
    mov dword ptr [rbx + EXT_activation_required], 1
    xor eax, eax
8:  mov [rbx + EXT_activation_stale], eax
    mov dword ptr [rbx + EXT_start_armed], 0
    mov dword ptr [rbx + EXT_startaccepted], 0
    lea rdi, [rbx + EXT_start_record]
    xor esi, esi
    mov edx, EXI_SIZE
    call memset
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lehs_stale:
    mov rax, -116
    jmp .Lehs_reject
.Lehs_bad:
    mov rax, -22
    jmp .Lehs_reject
.Lehs_busy:
    mov rax, -16
.Lehs_reject:
    xor edx, edx
    EPILOGUE
.section .rodata
.p2align 3
ea_host_launch_fields: .quad EXT_dir, EXT_prog, EXT_script, EXT_runs, EXT_args
ea_host_identity_fields: .quad EXT_owner, EXT_name, EXT_state
ea_host_context_fields: .quad KE_owner, KE_name, KE_state
