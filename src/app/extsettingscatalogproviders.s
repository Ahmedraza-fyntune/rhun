# Provider stages share the catalog's remaining work budget and owned blocks.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN cp_provider_step
    mov rax, [rdi + CP_ppphase]
    cmp rax, PPS_DIRTY_NEXT
    jbe cp_provider_setup
    cmp rax, PPS_OWNER
    jbe cp_provider_parse
    cmp rax, PPS_INSTALL
    jbe cp_provider_install
    cmp rax, PPS_RAW_NEXT
    jbe cp_provider_setup
    cmp rax, PPS_COMPARE_OWNER
    jbe cp_provider_compare
    mov rax, -22
    ret
# Both target blocks remain owned throughout a synchronous slice.
FN cp_provider_target
    cmp qword ptr [rdi + CP_pptarget], 0
    jne 1f
    mov rax, [rdi + CP_baseline]
    ret
1:  mov rax, [rdi + CP_provider]
    ret
# Queue fields are never stored across yields. Captured slot+seq are re-derived.
FN cp_provider_fields
    test qword ptr [rdi + CP_workflags], PPF_DIRTY
    jnz 1f
    lea rax, [rdi + CP_ppraw]
    xor edx, edx
    ret
1:  mov rax, [rip + esv_service_queue]
    test rax, rax
    jz 3f
    mov rcx, [rdi + CP_ppdirtyslot]
    cmp rcx, EQ_MAX
    jae 3f
    imul rcx, EQ_SLOT
    mov rax, [rax + EQ_slots + rcx + EQS_cell]
    test rax, rax
    jz 3f
    mov rdx, [rdi + CP_ppdirtyseq]
    cmp [rax + EQC_seq], rdx
    jne 3f
    mov rdx, [rax + EC_remove]
    ret
3:  xor eax, eax
    mov rdx, -116
    ret
FN cp_provider_advance
    test qword ptr [rdi + CP_workflags], PPF_DIRTY
    jnz 1f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + CP_cursor]
    call ext_settings_ini_advance
    test rax, rax
    jnz 2f
    mov qword ptr [rbx + CP_ppphase], PPS_RAW_NEXT
2:  EPILOGUE
1:  inc qword ptr [rdi + CP_ppdirtyslot]
    mov qword ptr [rdi + CP_ppphase], PPS_DIRTY_NEXT
    xor eax, eax
    ret

FN cp_provider_setup
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + CP_ppphase]
    cmp rax, PPS_BASE_ALLOC
    je .Lpp_base_alloc
    cmp rax, PPS_BASE_COPY
    je .Lpp_base_copy
    cmp rax, PPS_BASE_REBASE
    je .Lpp_base_rebase
    cmp rax, PPS_DIRTY_NEXT
    je .Lpp_dirty
    cmp rax, PPS_CAND_ALLOC
    je .Lpp_cand_alloc
    cmp rax, PPS_CURSOR_ALLOC
    je .Lpp_cursor
    cmp rax, PPS_RAW_NEXT
    je .Lpp_raw
    mov rax, -22
    jmp .Lpp_return
.Lpp_base_alloc:
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lpp_zero
    dec qword ptr [rbx + CP_allocsleft]
    mov edi, PB_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lpp_alloc_error
    mov [rbx + CP_baseline], rax
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_BASE_COPY
    jmp .Lpp_zero
.Lpp_base_copy:
    mov rax, [rbx + CP_oldref]
    test rax, rax
    jz .Lpp_rebase_begin
    mov rsi, [rax + ELM_providers]
    test rsi, rsi
    jz .Lpp_rebase_begin
    mov rdx, PB_SIZE
    sub rdx, [rbx + CP_scanpos]
    jz .Lpp_rebase_begin
    mov rax, [rbx + CP_bytesleft]
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .Lpp_zero
    mov r12, rdx
    add rsi, [rbx + CP_scanpos]
    mov rdi, [rbx + CP_baseline]
    add rdi, [rbx + CP_scanpos]
    call memcpy
    add [rbx + CP_scanpos], r12
    sub [rbx + CP_bytesleft], r12
    cmp qword ptr [rbx + CP_scanpos], PB_SIZE
    jne .Lpp_zero
.Lpp_rebase_begin:
    mov qword ptr [rbx + CP_ppsourceindex], 0
    mov qword ptr [rbx + CP_ppphase], PPS_BASE_REBASE
    jmp .Lpp_zero
.Lpp_base_rebase:
    mov r12, [rbx + CP_baseline]
    mov rcx, [rbx + CP_ppsourceindex]
    cmp rcx, [r12 + PB_count]
    jae .Lpp_baseline_dirty
    imul rax, rcx, PBR_SIZE
    lea r13, [r12 + PB_rows + rax]
    imul rax, rcx, 129
    lea rax, [r12 + PB_language + rax]
    mov [r13 + PBR_language], rax
    cmp qword ptr [r13 + PBR_owner], 0
    je 1f
    imul rax, rcx, 202
    lea rax, [r12 + PB_owner + rax]
    mov [r13 + PBR_owner], rax
1:  inc qword ptr [rbx + CP_ppsourceindex]
    jmp .Lpp_zero
.Lpp_baseline_dirty:
    mov qword ptr [rbx + CP_pptarget], 0
    mov qword ptr [rbx + CP_ppdirtyslot], 0
    mov qword ptr [rbx + CP_ppphase], PPS_DIRTY_NEXT
    jmp .Lpp_zero
.Lpp_dirty:
    mov rcx, [rbx + CP_ppdirtyslot]
    cmp rcx, EQ_MAX
    jae .Lpp_dirty_done
    mov rax, [rip + esv_service_queue]
    imul rcx, EQ_SLOT
    mov rax, [rax + EQ_slots + rcx + EQS_cell]
    test rax, rax
    jnz 1f
    inc qword ptr [rbx + CP_ppdirtyslot]
    jmp .Lpp_zero
1:  mov rcx, [rax + EQC_seq]
    mov [rbx + CP_ppdirtyseq], rcx
    mov qword ptr [rbx + CP_workflags], PPF_DIRTY
    mov qword ptr [rbx + CP_ppraw], 0
    mov qword ptr [rbx + CP_ppraw + EC_key], 0
    mov qword ptr [rbx + CP_ppraw + EC_value], 0
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_SECTION
    jmp .Lpp_zero
.Lpp_dirty_done:
    cmp qword ptr [rbx + CP_pptarget], 0
    jne 1f
    mov qword ptr [rbx + CP_ppphase], PPS_CAND_ALLOC
    jmp .Lpp_zero
1:  mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_BEGIN
    jmp .Lpp_zero
.Lpp_cand_alloc:
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lpp_zero
    dec qword ptr [rbx + CP_allocsleft]
    mov edi, PB_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lpp_alloc_error
    mov [rbx + CP_provider], rax
    mov rcx, [rbx + CP_model]
    mov [rcx + ELM_providers], rax
    mov qword ptr [rbx + CP_pptarget], 1
    mov qword ptr [rbx + CP_ppphase], PPS_CURSOR_ALLOC
    jmp .Lpp_zero
.Lpp_cursor:
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lpp_zero
    dec qword ptr [rbx + CP_allocsleft]
    mov rdi, [rbx + CP_source]
    call ext_settings_ini_begin
    test rax, rax
    jz .Lpp_alloc_error
    mov [rbx + CP_cursor], rax
    mov qword ptr [rbx + CP_ppphase], PPS_RAW_NEXT
    jmp .Lpp_zero
.Lpp_raw:
    cmp qword ptr [rbx + CP_phasesleft], 0
    je .Lpp_zero
    mov rdi, [rbx + CP_cursor]
    mov rsi, [rbx + CP_bytesleft]
    mov rdx, [rbx + CP_phasesleft]
    call ext_settings_ini_step_budget
    cmp rdx, [rbx + CP_bytesleft]
    ja .Lpp_bad
    cmp rcx, [rbx + CP_phasesleft]
    ja .Lpp_bad
    sub [rbx + CP_bytesleft], rdx
    sub [rbx + CP_phasesleft], rcx
    test rax, rax
    js .Lpp_return
    jz .Lpp_zero
    cmp rax, 2
    je .Lpp_raw_done
    cmp rax, 1
    jne .Lpp_bad
    mov rdi, [rbx + CP_cursor]
    lea rsi, [rbx + CP_ppraw]
    call ext_settings_ini_row
    test rax, rax
    jnz .Lpp_return
    mov qword ptr [rbx + CP_workflags], 0
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_SECTION
    jmp .Lpp_zero
.Lpp_raw_done:
    mov qword ptr [rbx + CP_ppdirtyslot], 0
    mov qword ptr [rbx + CP_ppphase], PPS_DIRTY_NEXT
.Lpp_zero:
    xor eax, eax
.Lpp_return:
    EPILOGUE
.Lpp_bad:
    mov rax, -22
    EPILOGUE
.Lpp_alloc_error:
    mov rax, rdx
    EPILOGUE
