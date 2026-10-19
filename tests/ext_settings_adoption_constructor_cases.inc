# Retain-overflow and late constructor failure keep every partial child reachable.
.bss
.p2align 3
svac_charge: .quad 0
svac_live: .quad 0
svac_oldrefs: .quad 0
.text
svac_collect:
    PROLOGUE
    mov r12d, 256
1:  mov edi, 1
    call ext_settings_adoption_gc
    cmp rax, 1
    ja svw_fail
    test rdx, rdx
    jnz svw_fail
    dec r12
    jnz 1b
    call ext_settings_adoption_pending
    test rax, rax
    jnz svw_fail
    mov rax, [rip + svw_svc]
    cmp qword ptr [rax + SV_refs], 1
    jne svw_fail
    mov rdx, [rax + SV_pending]
    cmp qword ptr [rdx + ESB_refs], 1
    jne svw_fail
    mov rax, [rip + esv_live_model]
    cmp qword ptr [rax + ELM_refs], 1
    jne svw_fail
    call ext_settings_memory_total
    cmp [rip + svac_charge], rax
    jne svw_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + svac_live], rax
    jne svw_fail
    EPILOGUE
svac_constructor_faults:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 248
    mov rbx, [rip + svw_svc]
    mov r14, [rip + esv_live_model]
    mov r15, [rbx + SV_pending]
    call ext_settings_memory_total
    mov [rip + svac_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + svac_live], rax
    mov rax, [rbx + SV_refs]
    mov [rip + svac_oldrefs], rax
    mov rax, 0x7fffffffffffffff
    mov [rbx + SV_refs], rax
    mov rdi, rbx
    call settings_adoption_begin
    cmp rax, -75
    jne svw_fail
    mov rax, [rip + svac_oldrefs]
    mov [rbx + SV_refs], rax
    call svac_collect
    mov qword ptr [rip + svw_stage], 249
    mov rax, [r14 + ELM_refs]
    mov [rip + svac_oldrefs], rax
    mov rax, 0x7fffffffffffffff
    mov [r14 + ELM_refs], rax
    mov rdi, rbx
    call settings_adoption_begin
    cmp rax, -75
    jne svw_fail
    mov rax, [rip + svac_oldrefs]
    mov [r14 + ELM_refs], rax
    call svac_collect
    mov qword ptr [rip + svw_stage], 250
    mov rax, [r15 + ESB_refs]
    mov [rip + svac_oldrefs], rax
    mov rax, 0x7fffffffffffffff
    mov [r15 + ESB_refs], rax
    mov rdi, rbx
    call settings_adoption_begin
    cmp rax, -75
    jne svw_fail
    mov rax, [rip + svac_oldrefs]
    mov [r15 + ESB_refs], rax
    call svac_collect
    mov qword ptr [rip + svw_stage], 251
    mov rax, 0x7fffffffffffffff
    mov [rbx + SV_source_epoch], rax
    mov rdi, rbx
    call settings_adoption_begin
    cmp rax, -75
    jne svw_fail
    mov qword ptr [rbx + SV_source_epoch], 1
    call svac_collect
    cmp qword ptr [rbx + SV_refs], 1
    jne svw_fail
    cmp [rip + esv_live_model], r14
    jne svw_fail
    cmp [rbx + SV_pending], r15
    jne svw_fail
    cmp qword ptr [rbx + SV_pending_epoch], 1
    jne svw_fail
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_sap_serial], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_apply_grant], 1
    jne svw_fail
    cmp qword ptr [rip + settings_adoption_scheduler], 0
    jne svw_fail
    EPILOGUE
