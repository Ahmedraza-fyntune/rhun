# Actual second READ before initial publication. Old future model stays retained.
.bss
.p2align 3
svi_oldplan: .quad 0
svi_newplan: .quad 0
svi_oldfuture: .quad 0
svi_newfuture: .quad 0
svi_source: .quad 0
svi_epoch: .quad 0
.globl svi_pure
svi_pure: .quad 0
.text
# Source is borrowed for construction. Returns owned plan and owned future model.
svi_make_plan:
    PROLOGUE ECSCP_SIZE
    mov [rsp + ECSCP_source], rdi
    mov qword ptr [rsp + ECSCP_rows], 0
    mov qword ptr [rsp + ECSCP_count], 0
    mov rax, [rip + esv_registry_epoch]
    mov [rsp + ECSCP_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [rsp + ECSCP_model], rax
    mov rax, [rip + esv_service_queue]
    mov rax, [rax + EQ_epoch]
    mov [rsp + ECSCP_dirty], rax
    mov rdi, rsp
    call ext_settings_catalog_prepare
    test rax, rax
    jz svw_fail
    mov r12, rax
1:  mov rdi, r12
    mov esi, 65536
    call ext_settings_catalog_step
    test rax, rax
    js svw_fail
    cmp rax, 1
    jne 1b
    mov rdi, r12
    call ext_settings_catalog_check
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_catalog_model
    test rax, rax
    jz svw_fail
    mov rdx, rax
    mov rax, r12
    EPILOGUE
svi_initial_replace:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 230
    mov rbx, [rip + svw_svc]
    mov rdi, [rip + svw_held]
    call svi_make_plan
    mov [rip + svi_oldplan], rax
    mov [rip + svi_oldfuture], rdx
    mov rcx, rdx
    mov rdi, rbx
    mov rsi, [rip + svw_held]
    mov edx, 1
    call ext_settings_service_initial_check
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rip + svw_mode], 17
    je .Lsvi_refresh
    cmp qword ptr [rip + svw_mode], 18
    jne 8f
    mov rax, 0x7fffffffffffffff
    mov [rbx + SV_source_epoch], rax
8:  # External actor changes only the fixture's actual file.
    mov r12, [rbx + SV_length]
    cmp r12, 4080
    ja svw_fail
    lea rdi, [rip + svwf_filepath]
    mov rsi, [rbx + SV_path]
    mov rdx, r12
    call memcpy
    lea rdi, [rip + svwf_filepath]
    add rdi, r12
    lea rsi, [rip + svwf_suffix]
    mov edx, 16
    call memcpy
    lea rdi, [rip + svwf_filepath]
    lea rsi, [rip + svwf_foreign]
    mov edx, SVWF_FOREIGNLEN
    call file_write_all
    test rax, rax
    jnz svw_fail
.Lsvi_refresh:
    mov rdi, rbx
    call ext_settings_service_refresh
    test rax, rax
    jnz svw_fail
1:  call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    cmp qword ptr [rip + svw_mode], 17
    je .Lsvi_unchanged_wait
    cmp qword ptr [rip + svw_mode], 18
    je .Lsvi_overflow_wait
    cmp qword ptr [rbx + SV_primary], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    je 2f
.Lsvi_wait:
    call svw_wait
    jmp 1b
.Lsvi_unchanged_wait:
    cmp qword ptr [rbx + SV_primary], 0
    jne svw_fail
    cmp qword ptr [rip + svwf_native_starts], 2
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_source_epoch], 1
    jne svw_fail
    mov rax, [rip + svw_held]
    cmp [rbx + SV_source], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    mov rdi, rbx
    mov rsi, rax
    mov edx, 1
    mov rcx, [rip + svi_oldfuture]
    call ext_settings_service_initial_check
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_oldplan]
    call ext_settings_catalog_check
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_oldplan]
    call ext_settings_catalog_publish
    mov rdi, rbx
    call ext_settings_service_initial_publish
    jmp .Lsvi_drop_old
.Lsvi_overflow_wait:
    mov qword ptr [rip + svw_stage], 235
    cmp qword ptr [rip + svwf_native_starts], 2
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_primary], -75
    jne svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lsvi_wait
    cmp qword ptr [rbx + SV_provisional], 0
    jne .Lsvi_wait
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_source_epoch], rax
    jne svw_fail
    mov rax, [rip + svw_held]
    cmp [rbx + SV_source], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rip + esv_live_model], 0
    jne svw_fail
    cmp qword ptr [rip + esv_registry_epoch], 1
    jne svw_fail
    cmp qword ptr [rip + esv_model_epoch], 1
    jne svw_fail
    jmp .Lsvi_drop_old
2:  mov qword ptr [rip + svw_stage], 231
    cmp qword ptr [rbx + SV_source_epoch], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_installed], 0
    jne svw_fail
    cmp qword ptr [rip + esv_live_model], 0
    jne svw_fail
    cmp qword ptr [rip + esv_registry_epoch], 1
    jne svw_fail
    cmp qword ptr [rip + esv_model_epoch], 1
    jne svw_fail
    mov rax, [rip + svw_held]
    cmp [rbx + SV_replaced_source], rax
    jne svw_fail
    mov qword ptr [rip + svw_stage], 232
    mov rdi, rbx
    mov rsi, rax
    mov edx, 1
    mov rcx, [rip + svi_oldfuture]
    call ext_settings_service_initial_check
    cmp rax, -116
    jne svw_fail
    # The new source is usable before deferred old-reference disposal.
    mov rdi, rbx
    lea rsi, [rip + svi_epoch]
    call ext_settings_service_source
    test rax, rax
    jz svw_fail
    mov [rip + svi_source], rax
    cmp qword ptr [rip + svi_epoch], 2
    jne svw_fail
    mov qword ptr [rip + svw_stage], 233
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    mov rcx, [rip + svi_oldfuture]
    call ext_settings_service_initial_check
    cmp rax, -116
    jne svw_fail
    mov rdi, [rip + svi_source]
    call svi_make_plan
    mov [rip + svi_newplan], rax
    mov [rip + svi_newfuture], rdx
    mov qword ptr [rip + svi_pure], 1
    mov rcx, rdx
    mov rdi, rbx
    mov rsi, [rip + svi_source]
    mov edx, 2
    call ext_settings_service_initial_check
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_newplan]
    call ext_settings_catalog_check
    test rax, rax
    jnz svw_fail
    # Pure caller callback: all refusal happened above, no recheck after mutation.
    mov rdi, [rip + svi_newplan]
    call ext_settings_catalog_publish
    mov rdi, rbx
    call ext_settings_service_initial_publish
    mov qword ptr [rip + svi_pure], 0
    cmp qword ptr [rbx + SV_installed], 1
    jne svw_fail
    mov rax, [rip + svi_newfuture]
    cmp [rip + esv_live_model], rax
    jne svw_fail
    mov rax, [rip + svi_source]
    cmp [rbx + SV_source], rax
    jne svw_fail
    # One category retires the old SVC-owned reference without dropping held history.
    call time_ms
    mov rsi, rax
    mov rdi, rbx
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_job], 0
    jne svw_fail
    mov rax, [rip + svi_oldfuture]
    mov rdx, [rip + svw_held]
    cmp [rax + ELM_source], rdx
    jne svw_fail
    cmp qword ptr [rdx + ESB_refs], 0
    jle svw_fail
    mov rdi, [rip + svi_source]
    call ext_settings_snapshot_release
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_newfuture]
    call ext_settings_model_release
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_newplan]
    call ext_settings_catalog_release
    test rax, rax
    jnz svw_fail
.Lsvi_drop_old:
    mov rdi, [rip + svi_oldfuture]
    call ext_settings_model_release
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svi_oldplan]
    call ext_settings_catalog_release
    test rax, rax
    jnz svw_fail
    EPILOGUE

.globl svi_pure_fail
svi_pure_fail:
    mov edi, 236
    call sys_exit
