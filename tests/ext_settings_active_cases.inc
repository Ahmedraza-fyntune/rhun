# Additional refresh fixtures appended to the actual catalog driver program.
.text
act_prepare:
    PROLOGUE ECSCP_SIZE
    mov [rsp + ECSCP_source], rdi
    mov [rsp + ECSCP_rows], rsi
    mov [rsp + ECSCP_count], rdx
    mov rax, [rip + esv_registry_epoch]
    mov [rsp + ECSCP_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [rsp + ECSCP_model], rax
    mov rax, [rip + esv_service_queue]
    mov rax, [rax + EQ_epoch]
    mov [rsp + ECSCP_dirty], rax
    mov rdi, rsp
    call ext_settings_refresh_prepare
    EPILOGUE
act_refresh_cases:
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 151
    mov rax, [rip + esv_registry_epoch]
    mov [rsp], rax
    mov rax, [rip + esv_model_epoch]
    mov [rsp + 8], rax
    mov rax, [rip + esv_provider_epoch]
    mov [rsp + 16], rax
    mov rax, [rip + vt_queue]
    mov rax, [rax + EQ_seq]
    mov [rsp + 24], rax
    xor r14d, r14d
1:  mov rax, [rip + esv_live_model]
    mov rax, [rax + ELM_slots + r14 * 8]
    test rax, rax
    jz vt_fail
    mov r12, [rax + EV_ep]
    mov rdi, r12
    mov rsi, [rip + ct_source_c_ref]
    mov edx, 65536
    call vt_build
    imul rcx, r14, ECSR_SIZE
    lea r13, [rip + ct_rows]
    add r13, rcx
    mov [r13 + ECSR_view], rax
    mov [r13 + ECSR_slot], r14
    mov rax, [r12 + EP_ext + EXT_owner]
    mov [r13 + ECSR_owner], rax
    mov rax, [r12 + EP_ext + EXT_name]
    mov [r13 + ECSR_name], rax
    inc r14
    cmp r14, 128
    jb 1b
    # Missing one current schema cannot be accepted as a settings-only refresh.
    mov rdi, [rip + ct_source_c_ref]
    lea rsi, [rip + ct_rows]
    mov edx, 127
    call act_prepare
    test rax, rax
    jnz vt_fail
    cmp rdx, -116
    jne vt_fail
    # Swapping unique slots preserves identity set but violates exact schema map.
    lea rax, [rip + ct_rows]
    mov qword ptr [rax + ECSR_slot], 1
    mov qword ptr [rax + ECSR_SIZE + ECSR_slot], 0
    mov rdi, [rip + ct_source_c_ref]
    mov rsi, rax
    mov edx, 128
    call act_prepare
    test rax, rax
    jnz vt_fail
    cmp rdx, -116
    jne vt_fail
    lea rax, [rip + ct_rows]
    mov qword ptr [rax + ECSR_slot], 0
    mov qword ptr [rax + ECSR_SIZE + ECSR_slot], 1
    # Failed plans must not keep the successful plan's input borrows alive.
    call ct_gc
    mov rdi, [rip + ct_source_c_ref]
    lea rsi, [rip + ct_rows]
    mov edx, 128
    call act_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    cmp qword ptr [rax + CP_kind], 1
    jne vt_fail
    mov rax, [rsp + 24]
    cmp [rbx + CP_sequence], rax
    jne vt_fail
    # A sequence mismatch must reject before any work, even if epoch is unchanged.
    mov r12, [rip + vt_queue]
    inc qword ptr [r12 + EQ_seq]
    mov rdi, rbx
    mov esi, 1
    call ext_settings_catalog_step
    cmp rax, -116
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    dec qword ptr [r12 + EQ_seq]
    xor r14d, r14d
2:  imul rax, r14, ECSR_SIZE
    lea rcx, [rip + ct_rows]
    mov rdi, [rcx + rax + ECSR_view]
    call ext_settings_view_release
    inc r14
    cmp r14, 128
    jb 2b
    lea rdi, [rip + ct_rows]
    xor esi, esi
    mov edx, 128 * ECSR_SIZE
    call memset
    mov rdi, rbx
    mov esi, 1
    call ct_build_plan
    mov rax, [rsp + 24]
    cmp [rbx + CP_sequence], rax
    jne vt_fail
    mov rdi, rbx
    call ext_settings_catalog_model
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov rdi, rax
    call ext_settings_model_sequence
    test rdx, rdx
    jnz vt_fail
    cmp rax, [rsp + 24]
    jne vt_fail
    mov rdi, r12
    call ext_settings_model_release
    mov qword ptr [rbx + CP_kind], 2
    mov rdi, rbx
    call ext_settings_catalog_check
    cmp rax, -22
    jne vt_fail
    mov qword ptr [rbx + CP_kind], 1
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rax, [rsp]
    cmp [rip + esv_registry_epoch], rax
    jne vt_fail
    mov rax, [rsp + 8]
    inc rax
    cmp [rip + esv_model_epoch], rax
    jne vt_fail
    mov rax, [rsp + 16]
    cmp [rip + esv_provider_epoch], rax
    jne vt_fail
    mov rax, [rip + esv_live_model]
    mov rax, [rax + ELM_sequence]
    cmp rax, [rsp + 24]
    jne vt_fail
    call ct_gc
    EPILOGUE

act_max_cases:
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 152
    mov r12, [rip + vt_queue]
    mov r13, [r12 + EQ_seq]
    mov qword ptr [r12 + EQ_seq], -1
    mov rdi, [rip + ct_source_c_ref]
    xor esi, esi
    xor edx, edx
    call act_prepare
    test rax, rax
    jnz vt_fail
    cmp rdx, -116
    jne vt_fail
    mov rax, 0x7fffffffffffffff
    mov [r12 + EQ_seq], rax
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    mov rax, 0x7fffffffffffffff
    cmp [rbx + CP_sequence], rax
    jne vt_fail
    mov rdi, rbx
    call ext_settings_catalog_model
    test rax, rax
    jz vt_fail
    mov r14, rax
    mov rdi, rax
    call ext_settings_model_sequence
    test rdx, rdx
    jnz vt_fail
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jne vt_fail
    mov rdi, r14
    call ext_settings_model_release
    mov rdi, rbx
    call ext_settings_catalog_release
    # Queue refuses exhausted serial without changing epoch or allocating.
    mov r14, [r12 + EQ_epoch]
    lea rax, [rip + ct_provider_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 9
    lea rax, [rip + ct_provider_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 9
    lea rax, [rip + ct_owner_new]
    mov [rsp + EC_value], rax
    mov qword ptr [rsp + EC_vallen], 8
    mov qword ptr [rsp + EC_remove], 0
    mov rdi, r12
    mov rsi, rsp
    call ext_settings_queue_put
    cmp rax, -75
    jne vt_fail
    cmp [r12 + EQ_epoch], r14
    jne vt_fail
    mov [r12 + EQ_seq], r13
    call ct_gc
    # Simulate registry exhaustion through actual catalog preparation/publication,
    # never by mutating an immutable installed model's header.
    mov rax, 0x7ffffffffffffffe
    mov [rip + esv_registry_epoch], rax
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rax, 0x7fffffffffffffff
    cmp [rip + esv_registry_epoch], rax
    jne vt_fail
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jnz vt_fail
    cmp rdx, -75
    jne vt_fail
    mov rdi, [rip + ct_source_c_ref]
    xor esi, esi
    xor edx, edx
    call act_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call ct_build_plan
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rax, 0x7fffffffffffffff
    cmp [rip + esv_registry_epoch], rax
    jne vt_fail
    call ct_gc
    EPILOGUE
