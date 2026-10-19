# Retained whole-set request construction. Caller pointers never survive return.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN ext_settings_catalog_prepare
    xor esi, esi
    jmp cp_prepare_common
FN ext_settings_refresh_prepare
    mov esi, 1
cp_prepare_common:
    test rdi, rdi
    jz .Lcp_prepare_bad
    cmp qword ptr [rdi + ECSCP_count], 128
    ja .Lcp_prepare_bad
    cmp qword ptr [rdi + ECSCP_count], 0
    je 1f
    cmp qword ptr [rdi + ECSCP_rows], 0
    je .Lcp_prepare_bad
1:  cmp esi, 1
    ja .Lcp_prepare_bad
    test esi, esi
    jz 11f
    cmp qword ptr [rip + esv_live_model], 0
    je .Lcp_prepare_again
11: cmp qword ptr [rip + esv_service_queue], 0
    je .Lcp_prepare_again
    cmp qword ptr [rip + esv_cfg_context], 0
    jle .Lcp_prepare_stale
    mov rax, [rip + esv_registry_epoch]
    test rax, rax
    jle .Lcp_prepare_stale
    cmp [rdi + ECSCP_registry], rax
    jne .Lcp_prepare_stale
    mov rdx, 0x7fffffffffffffff
    test esi, esi
    jnz 12f
    cmp rax, rdx
    jae .Lcp_prepare_overflow
12: mov rax, [rip + esv_model_epoch]
    test rax, rax
    jle .Lcp_prepare_stale
    cmp [rdi + ECSCP_model], rax
    jne .Lcp_prepare_stale
    cmp rax, rdx
    jae .Lcp_prepare_overflow
    mov rax, [rip + esv_service_queue]
    cmp qword ptr [rax + EQ_seq], 0
    jl .Lcp_prepare_stale
    mov rax, [rax + EQ_epoch]
    test rax, rax
    jle .Lcp_prepare_stale
    cmp [rdi + ECSCP_dirty], rax
    jne .Lcp_prepare_stale
    cmp qword ptr [rip + esv_provider_epoch], 0
    jle .Lcp_prepare_stale
    mov rax, [rdi + ECSCP_source]
    test rax, rax
    jnz 2f
    mov rax, [rip + esv_live_model]
    test rax, rax
    jz .Lcp_prepare_again
    mov rax, [rax + ELM_source]
2:  test rax, rax
    jz .Lcp_prepare_again
    cmp qword ptr [rax + ESB_ready], 1
    jne .Lcp_prepare_bad
    cmp qword ptr [rax + ESB_refs], 0
    jle .Lcp_prepare_bad
    mov rdx, [rip + esv_cfg_context]
    cmp [rax + ESB_context], rdx
    jne .Lcp_prepare_stale
    PROLOGUE
    mov r12, rdi
    mov r13, rax
    mov r15, rsi
    mov edi, CP_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lcp_prepare_empty
    mov rbx, rax
    mov qword ptr [rax + CP_refs], 1
    mov qword ptr [rax + CP_phase], CPP_MODEL_ALLOC
    mov [rax + CP_kind], r15
    mov rcx, [rip + esv_service_queue]
    mov rcx, [rcx + EQ_seq]
    mov [rax + CP_sequence], rcx
    mov rax, [r12 + ECSCP_count]
    mov [rbx + CP_count], rax
    mov rax, [rip + esv_cfg_context]
    mov [rbx + CP_context], rax
    mov rax, [r12 + ECSCP_registry]
    mov [rbx + CP_registry], rax
    cmp qword ptr [rbx + CP_kind], 0
    jne 13f
    inc rax
13: mov [rbx + CP_newregistry], rax
    mov rax, [r12 + ECSCP_dirty]
    mov [rbx + CP_dirty], rax
    mov rax, [r12 + ECSCP_model]
    mov [rbx + CP_epoch], rax
    inc rax
    mov [rbx + CP_newepoch], rax
    mov rax, [rip + esv_provider_epoch]
    mov [rbx + CP_providerepoch], rax
    mov [rbx + CP_newprovider], rax
    mov rdi, r13
    call ext_settings_snapshot_retain
    test rax, rax
    js .Lcp_prepare_retire
    mov [rbx + CP_source], r13
    mov rdi, [rip + esv_live_model]
    test rdi, rdi
    jz .Lcp_prepare_rows
    mov r13, rdi
    mov rax, [rbx + CP_context]
    cmp [rdi + ELM_context], rax
    jne .Lcp_prepare_owned_stale
    call ext_settings_model_retain
    test rax, rax
    js .Lcp_prepare_retire
    mov [rbx + CP_oldmodel], r13
    mov [rbx + CP_oldref], r13
.Lcp_prepare_rows:
    xor r14d, r14d
.Lcp_prepare_row:
    cmp r14, [rbx + CP_count]
    jae .Lcp_prepare_names_begin
    imul rax, r14, ECSR_SIZE
    add rax, [r12 + ECSCP_rows]
    mov r15, [rax + ECSR_view]
    test r15, r15
    jz .Lcp_prepare_owned_bad
    mov r13, [rax + ECSR_slot]
    cmp r13, 128
    jae .Lcp_prepare_owned_bad
    mov rcx, r13
    and ecx, 63
    mov eax, 1
    shl rax, cl
    mov rcx, r13
    shr rcx, 6
    test [rbx + CP_slotbits + rcx * 8], rax
    jnz .Lcp_prepare_owned_bad
    or [rbx + CP_slotbits + rcx * 8], rax
    mov rdi, r15
    call ext_settings_view_check
    test rax, rax
    jnz .Lcp_prepare_retire
    mov rax, [rbx + CP_source]
    cmp [r15 + EV_source], rax
    jne .Lcp_prepare_owned_stale
    mov rax, [r15 + EV_ownerlen]
    add rax, [r15 + EV_namelen]
    jc .Lcp_prepare_large
    add rax, 2
    jc .Lcp_prepare_large
    add rax, [rbx + CP_namelen]
    jc .Lcp_prepare_large
    cmp rax, 65536
    ja .Lcp_prepare_large
    mov [rbx + CP_namelen], rax
    mov rdi, r15
    call ext_settings_view_retain
    test rax, rax
    jnz .Lcp_prepare_retire
    imul rax, r14, CPR_SIZE
    mov [rbx + CP_rows + rax + CPR_view], r15
    mov [rbx + CP_rows + rax + CPR_slot], r13
    inc r14
    jmp .Lcp_prepare_row
.Lcp_prepare_names_begin:
    xor r14d, r14d
.Lcp_prepare_names:
    cmp r14, [rbx + CP_count]
    jae .Lcp_prepare_done
    imul rax, r14, CPR_SIZE
    mov r15, [rbx + CP_rows + rax + CPR_view]
    imul rax, r14, ECSR_SIZE
    add rax, [r12 + ECSCP_rows]
    mov r13, rax
    mov rdi, [r15 + EV_section]
    mov rsi, [r15 + EV_ownerlen]
    mov rdx, [r13 + ECSR_owner]
    call cp_name_matches
    test rax, rax
    jnz .Lcp_prepare_retire
    mov rdi, [r15 + EV_section]
    add rdi, [r15 + EV_ownerlen]
    inc rdi
    mov rsi, [r15 + EV_namelen]
    mov rdx, [r13 + ECSR_name]
    call cp_name_matches
    test rax, rax
    jnz .Lcp_prepare_retire
    inc r14
    jmp .Lcp_prepare_names
.Lcp_prepare_done:
    mov rdi, rbx
    call cp_refresh_map_check
    test rax, rax
    jnz .Lcp_prepare_retire
    mov rdi, rbx
    call cp_check_epochs
    test rax, rax
    jnz .Lcp_prepare_retire
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lcp_prepare_owned_stale:
    mov rax, -116
    jmp .Lcp_prepare_retire
.Lcp_prepare_owned_bad:
    mov rax, -22
    jmp .Lcp_prepare_retire
.Lcp_prepare_large:
    mov rax, -7
.Lcp_prepare_retire:
    mov r14, rax
    mov [rbx + CP_error], rax
    mov qword ptr [rbx + CP_phase], CPP_FAILED
    mov rdi, rbx
    call ext_settings_catalog_release
    xor eax, eax
    mov rdx, r14
.Lcp_prepare_empty:
    xor ecx, ecx
    EPILOGUE
.Lcp_prepare_bad:
    mov rdx, -22
    jmp .Lcp_prepare_null
.Lcp_prepare_again:
    mov rdx, -11
    jmp .Lcp_prepare_null
.Lcp_prepare_stale:
    mov rdx, -116
    jmp .Lcp_prepare_null
.Lcp_prepare_overflow:
    mov rdx, -75
.Lcp_prepare_null:
    xor eax, eax
    xor ecx, ecx
    ret

# Counted own identity segment versus a caller cstr, no read past its first NUL.
cp_name_matches:
    test rdx, rdx
    jz 3f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdx + rcx]
    test eax, eax
    jz 3f
    cmp al, [rdi + rcx]
    jne 3f
    inc rcx
    jmp 1b
2:  cmp byte ptr [rdx + rcx], 0
    jne 3f
    xor eax, eax
    ret
3:  mov rax, -22
    ret

# Fixed context check before every slice and before deriving any global queue row.
FN cp_check_epochs
    test rdi, rdi
    jz .Lcp_epoch_bad
    cmp qword ptr [rdi + CP_refs], 0
    jle .Lcp_epoch_bad
    cmp qword ptr [rdi + CP_kind], 1
    ja .Lcp_epoch_bad
    cmp qword ptr [rdi + CP_published], 0
    jne .Lcp_epoch_published
    mov rax, [rip + esv_cfg_context]
    test rax, rax
    jle .Lcp_epoch_stale
    cmp [rdi + CP_context], rax
    jne .Lcp_epoch_stale
    mov rax, [rip + esv_registry_epoch]
    test rax, rax
    jle .Lcp_epoch_stale
    cmp [rdi + CP_registry], rax
    jne .Lcp_epoch_stale
    mov rax, [rip + esv_model_epoch]
    test rax, rax
    jle .Lcp_epoch_stale
    cmp [rdi + CP_epoch], rax
    jne .Lcp_epoch_stale
    mov rax, [rip + esv_provider_epoch]
    test rax, rax
    jle .Lcp_epoch_stale
    cmp [rdi + CP_providerepoch], rax
    jne .Lcp_epoch_stale
    mov rax, [rip + esv_service_queue]
    test rax, rax
    jz .Lcp_epoch_stale
    mov rdx, [rax + EQ_seq]
    test rdx, rdx
    js .Lcp_epoch_stale
    cmp [rdi + CP_sequence], rdx
    jne .Lcp_epoch_stale
    mov rax, [rax + EQ_epoch]
    test rax, rax
    jle .Lcp_epoch_stale
    cmp [rdi + CP_dirty], rax
    jne .Lcp_epoch_stale
    mov rax, [rip + esv_live_model]
    cmp [rdi + CP_oldmodel], rax
    jne .Lcp_epoch_stale
    test rax, rax
    jz 1f
    cmp qword ptr [rax + ELM_refs], 0
    jle .Lcp_epoch_stale
    cmp qword ptr [rax + ELM_ready], 1
    jne .Lcp_epoch_stale
    mov rdx, [rdi + CP_context]
    cmp [rax + ELM_context], rdx
    jne .Lcp_epoch_stale
1:  mov rax, [rdi + CP_source]
    test rax, rax
    jz .Lcp_epoch_bad
    cmp qword ptr [rax + ESB_ready], 1
    jne .Lcp_epoch_stale
    cmp qword ptr [rax + ESB_refs], 0
    jle .Lcp_epoch_stale
    xor eax, eax
    ret
.Lcp_epoch_bad:
    mov rax, -22
    ret
.Lcp_epoch_stale:
    mov rax, -116
    ret
.Lcp_epoch_published:
    mov rax, -114
    ret
