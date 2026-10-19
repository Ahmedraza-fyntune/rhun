# Real parsed ready EP/defaults, private fixture readiness is not execution authority.
.section .rodata
svs_owner: .asciz "owner"
svs_fixture: .asciz "fixture"
svs_tool: .asciz "tool"
svs_example: .asciz "example"
svs_third: .asciz "third"
svs_default: .asciz "5"
.bss
.p2align 3
svs_eps: .zero 24
svs_views: .zero 24
svs_rows: .zero 96
svs_plan: .quad 0
svs_future: .quad 0
.text
# Borrowed owner/name/manifest/count, returns one ready private fixture EP.
svs_schema:
    PROLOGUE
    mov r12, rdx
    mov r13, rcx
    mov rdx, rdi
    mov rcx, rsi
    mov rdi, -1
    lea rsi, [rip + vt_dir]
    call ext_prepare_alloc
    test rax, rax
    jz svw_fail
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call ext_manifest_parse_owned
    test rax, rax
    jnz svw_fail
    mov rdi, rbx
    call ext_prepare_defaults
    test rax, rax
    jnz svw_fail
    mov qword ptr [rbx + PO_ready], 1
    mov rax, rbx
    EPILOGUE
# Replaces only fixture composition, uses actual whole final set and initial boundary.
svw_install_empty:
    PROLOGUE ECSCP_SIZE
    mov qword ptr [rip + svw_stage], 248
    lea rdi, [rip + svs_owner]
    lea rsi, [rip + svs_tool]
    lea rdx, [rip + vt_schema1]
    mov ecx, VT_SCHEMA1_LEN
    call svs_schema
    mov [rip + svs_eps], rax
    lea rdi, [rip + svs_fixture]
    lea rsi, [rip + svs_example]
    lea rdx, [rip + vt_schema2]
    mov ecx, VT_SCHEMA2_LEN
    call svs_schema
    mov [rip + svs_eps + 8], rax
    lea rdi, [rip + svs_owner]
    lea rsi, [rip + svs_third]
    lea rdx, [rip + vt_schema1]
    mov ecx, VT_SCHEMA1_LEN
    call svs_schema
    mov [rip + svs_eps + 16], rax
    xor r14d, r14d
1:  lea rax, [rip + svs_eps]
    mov rdi, [rax + r14 * 8]
    mov rsi, [rip + svw_held]
    mov edx, 65536
    call vt_build
    lea rdx, [rip + svs_views]
    mov [rdx + r14 * 8], rax
    mov rdx, r14
    shl rdx, 5
    lea r15, [rip + svs_rows]
    add r15, rdx
    mov [r15 + ECSR_view], rax
    mov rcx, r14
    shl rcx, 6
    cmp rcx, 128
    jne 2f
    dec rcx
2:  mov [r15 + ECSR_slot], rcx
    mov rax, [rax + EV_ep]
    mov rdx, [rax + EP_ext + EXT_owner]
    mov [r15 + ECSR_owner], rdx
    mov rdx, [rax + EP_ext + EXT_name]
    mov [r15 + ECSR_name], rdx
    inc r14
    cmp r14, 3
    jne 1b
    mov rax, [rip + svw_held]
    mov [rsp + ECSCP_source], rax
    lea rax, [rip + svs_rows]
    mov [rsp + ECSCP_rows], rax
    mov qword ptr [rsp + ECSCP_count], 3
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
    mov [rip + svs_plan], rax
1:  mov rdi, [rip + svs_plan]
    mov esi, 65536
    call ext_settings_catalog_step
    test rax, rax
    js svw_fail
    cmp rax, 1
    jne 1b
    mov rdi, [rip + svs_plan]
    call ext_settings_catalog_model
    test rax, rax
    jz svw_fail
    mov [rip + svs_future], rax
    mov rcx, rax
    mov rdi, [rip + svw_svc]
    mov rsi, [rip + svw_held]
    mov edx, 1
    call ext_settings_service_initial_check
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svs_plan]
    call ext_settings_catalog_check
    test rax, rax
    jnz svw_fail
    mov rdi, [rip + svs_plan]
    call ext_settings_catalog_publish
    mov rdi, [rip + svw_svc]
    call ext_settings_service_initial_publish
    mov rdi, [rip + svs_future]
    call ext_settings_model_release
    mov rdi, [rip + svs_plan]
    call ext_settings_catalog_release
    xor r14d, r14d
1:  lea rax, [rip + svs_views]
    mov rdi, [rax + r14 * 8]
    call ext_settings_view_release
    lea rax, [rip + svs_eps]
    mov rdi, [rax + r14 * 8]
    call ext_prepare_release_deferred
    inc r14
    cmp r14, 3
    jne 1b
    EPILOGUE
# Future model uses the exact sparse supplier map and independently normalized rows.
svs_verify_future:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 249
    mov r12, [rip + sva_future]
    xor r13d, r13d
1:  mov rax, r13
    shl rax, 6
    cmp rax, 128
    jne 2f
    dec rax
2:  mov r14, [r12 + rax * 8 + ELM_slots]
    test r14, r14
    jz svw_fail
    lea rax, [rip + svs_eps]
    mov rdx, [rax + r13 * 8]
    cmp [r14 + EV_ep], rdx
    jne svw_fail
    mov rdi, r14
    xor esi, esi
    call ext_settings_view_value
    test rax, rax
    jz svw_fail
    mov rdi, rax
    lea rsi, [rip + vt_base]
    cmp r13, 1
    jne 3f
    lea rsi, [rip + vt_20]
3:  call strcmp_eq
    test eax, eax
    jz svw_fail
    inc r13
    cmp r13, 3
    jne 1b
    mov r14, [r12 + ELM_slots]
    cmp qword ptr [r14 + EV_pinned], 0
    jne svw_fail
    cmp qword ptr [r12 + ELM_slots + 8], 0
    jne svw_fail
    EPILOGUE
