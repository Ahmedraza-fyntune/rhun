# Refresh preserves the entire active sparse schema map and registry owner.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN cp_refresh_map_check
    cmp qword ptr [rdi + CP_kind], 0
    je .Lcrm_ok
    cmp qword ptr [rdi + CP_kind], 1
    jne .Lcrm_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CP_oldmodel]
    test r12, r12
    jz .Lcrm_stale
    cmp qword ptr [r12 + ELM_refs], 0
    jle .Lcrm_stale
    cmp qword ptr [r12 + ELM_ready], 1
    jne .Lcrm_stale
    mov rax, [rbx + CP_context]
    cmp [r12 + ELM_context], rax
    jne .Lcrm_stale
    mov rax, [rbx + CP_registry]
    cmp [r12 + ELM_registry], rax
    jne .Lcrm_stale
    mov rax, [rbx + CP_epoch]
    cmp [r12 + ELM_epoch], rax
    jne .Lcrm_stale
    xor r13d, r13d
.Lcrm_rows:
    cmp r13, [rbx + CP_count]
    jae .Lcrm_slots_begin
    imul rax, r13, CPR_SIZE
    lea r14, [rbx + CP_rows + rax]
    mov rcx, [r14 + CPR_slot]
    cmp rcx, 128
    jae .Lcrm_stale
    mov r15, [r12 + ELM_slots + rcx * 8]
    test r15, r15
    jz .Lcrm_stale
    mov rax, [r14 + CPR_view]
    test rax, rax
    jz .Lcrm_stale
    mov rax, [rax + EV_ep]
    cmp [r15 + EV_ep], rax
    jne .Lcrm_stale
    inc r13
    jmp .Lcrm_rows
.Lcrm_slots_begin:
    xor r13d, r13d
.Lcrm_slots:
    mov rax, [r12 + ELM_slots + r13 * 8]
    mov rcx, r13
    and ecx, 63
    mov edx, 1
    shl rdx, cl
    mov rcx, r13
    shr rcx, 6
    test [rbx + CP_slotbits + rcx * 8], rdx
    jnz .Lcrm_present
    test rax, rax
    jnz .Lcrm_stale
    jmp .Lcrm_next
.Lcrm_present:
    test rax, rax
    jz .Lcrm_stale
.Lcrm_next:
    inc r13
    cmp r13, 128
    jb .Lcrm_slots
    xor eax, eax
    EPILOGUE
.Lcrm_stale:
    mov rax, -116
    EPILOGUE
.Lcrm_ok:
    xor eax, eax
    ret
.Lcrm_invalid:
    mov rax, -22
    ret
