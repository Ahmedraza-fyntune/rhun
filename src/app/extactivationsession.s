# Trusted native RT tuples retain EA and HI continuously after successful binding.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.text
# EXT, retainedEA, positiveKeeper, retainedExactHI ->0/-ESTALE, no ref change.
# Only this full check may establish the caller's immutable session grant.
FN ext_activation_host_running_bind_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test rbx, rbx
    jz .Lasb_stale
    test r14, r14
    jz .Lasb_stale
    cmp [rbx + EXT_identity_owner], r14
    jne .Lasb_stale
    mov rdi, r12
    call ea_is_ready
    test eax, eax
    jz .Lasb_stale
    cmp qword ptr [r12 + PO_refs], 2
    jb .Lasb_stale
    mov rdi, r14
    call hi_is_ready
    test eax, eax
    jz .Lasb_stale
    cmp qword ptr [r14 + PO_refs], 2
    jb .Lasb_stale
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_activation_host_running_check
    EPILOGUE
.Lasb_stale:
    mov rax, -116
    EPILOGUE

# Fixed-work check for an already bound native RT record, never a new START grant.
# Caller validates RT grant/session and continuously owns both supplied references.
FN ext_activation_host_running_session_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test rbx, rbx
    jz .Lass_stale
    test r12, r12
    jz .Lass_stale
    test r14, r14
    jz .Lass_stale
    test r13, r13
    jle .Lass_stale
    cmp [rbx + EXT_activation_owner], r12
    jne .Lass_stale
    cmp [rbx + EXT_identity_owner], r14
    jne .Lass_stale
    cmp [rbx + EXT_keeper], r13
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_catalog_state], 1
    jne .Lass_stale
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 1
    ja .Lass_stale
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_activation_stale], 0
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_disabled], 0
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_startaccepted], 1
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lass_stale
    cmp dword ptr [rbx + EXT_in], 0
    js .Lass_stale
    cmp dword ptr [rbx + EXT_out], 0
    js .Lass_stale
    cmp dword ptr [rbx + EXT_host_child_in], 0
    jns .Lass_stale
    cmp dword ptr [rbx + EXT_host_child_out], 0
    jns .Lass_stale
    mov rdi, r12
    call ea_is_ready
    test eax, eax
    jz .Lass_stale
    cmp qword ptr [r12 + PO_refs], 2
    jb .Lass_stale
    mov rdi, r14
    call hi_is_ready
    test eax, eax
    jz .Lass_stale
    cmp qword ptr [r14 + PO_refs], 2
    jb .Lass_stale
    mov r15, [r12 + EA_ep]
    cmp [rbx + EXT_metadata_owner], r15
    jne .Lass_stale
    cmp qword ptr [r15 - RD_PO_BACK + RD_kind], RD_EP
    jne .Lass_stale
    test qword ptr [r15 - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz .Lass_stale
    cmp qword ptr [r15 + PO_ready], 1
    jne .Lass_stale
    cmp qword ptr [r15 + PO_refs], 2
    jb .Lass_stale
    mov rax, [r15 + EP_kind]
    dec rax
    cmp rax, 1
    ja .Lass_stale
    lea rax, [r12 + EA_plan]
    cmp [rbx + EXT_activation_plan], rax
    jne .Lass_stale
    mov rax, [r14 + HI_owner]
    cmp [rbx + EXT_owner], rax
    jne .Lass_stale
    mov rax, [r14 + HI_name]
    cmp [rbx + EXT_name], rax
    jne .Lass_stale
    mov rax, [r14 + HI_state]
    cmp [rbx + EXT_state], rax
    jne .Lass_stale
    cmp byte ptr [rax], 0
    je .Lass_stale
    xor ecx, ecx
1:  lea rax, [rip + session_launch_fields]
    mov rax, [rax + rcx*8]
    mov rdx, [r15 + EP_ext + rax]
    cmp [rbx + rax], rdx
    jne .Lass_stale
    inc ecx
    cmp ecx, 5
    jb 1b
    mov eax, [r15 + EP_ext + EXT_needs]
    cmp [rbx + EXT_needs], eax
    jne .Lass_stale
    xor eax, eax
    EPILOGUE
.Lass_stale:
    mov rax, -116
    EPILOGUE
.section .rodata
.p2align 3
session_launch_fields: .quad EXT_dir, EXT_prog, EXT_script, EXT_runs, EXT_args
