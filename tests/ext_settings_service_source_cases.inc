# Appended to the real constructor/retirement fixture. Trusted fixed ESB ownership only.
.bss
.p2align 3
svst_epoch: .quad 0
svst_source: .quad 0
.data
svst_tag: .quad 41,37,11,29
.text
# A refusal must not retain source or expose an old output epoch.
svst_refused:
    PROLOGUE
    mov qword ptr [rip + svst_epoch], 99
    mov rdi, rbx
    lea rsi, [rip + svst_epoch]
    call ext_settings_service_source
    test rax, rax
    jnz svt_fail
    test rdx, rdx
    jns svt_fail
    cmp qword ptr [rip + svst_epoch], 0
    jne svt_fail
    mov rax, [rip + svst_source]
    cmp qword ptr [rax + ESB_refs], 1
    jne svt_fail
    EPILOGUE
# Called with the real current constructor owner in RBX.
svst_check:
    PROLOGUE
    mov qword ptr [rip + svt_stage], 191
    # A proposed foreign SVC pointer is rejected before its inaccessible fields.
    mov edi, 1
    call settings_service_domain
    cmp rax, -116
    jne svt_fail
    mov rdi, rbx
    lea rsi, [rip + svst_epoch]
    call ext_settings_service_source
    test rax, rax
    jnz svt_fail
    cmp rdx, -11
    jne svt_fail
    cmp qword ptr [rip + svst_epoch], 0
    jne svt_fail
    lea rdi, [rip + svst_tag]
    mov esi, EW_SNAPSHOT
    mov edx, 48
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz svt_fail
    mov r12, rax
    mov rdi, rax
    call ext_settings_frame_seal
    test rax, rax
    jnz svt_fail
    mov rdi, r12
    mov esi, 37
    call ext_settings_snapshot_begin
    test rax, rax
    jz svt_fail
    mov [rip + svst_source], rax
    mov [rbx + SV_source], rax
    mov qword ptr [rbx + SV_source_epoch], 1
    mov qword ptr [rip + svt_stage], 192
    mov rdi, rbx
    lea rsi, [rip + svst_epoch]
    call ext_settings_service_source
    cmp [rip + svst_source], rax
    jne svt_fail
    test rdx, rdx
    jnz svt_fail
    cmp qword ptr [rip + svst_epoch], 1
    jne svt_fail
    cmp qword ptr [rax + ESB_refs], 2
    jne svt_fail
    mov rdi, rbx
    mov rsi, rax
    mov edx, 1
    call ext_settings_service_source_check
    test rax, rax
    jnz svt_fail
    mov rdi, [rip + svst_source]
    call ext_settings_snapshot_release
    test rax, rax
    jnz svt_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call ext_settings_service_source_check
    cmp rax, -116
    jne svt_fail
    mov rdi, rbx
    mov rsi, [rip + svst_source]
    mov edx, 2
    call ext_settings_service_source_check
    cmp rax, -116
    jne svt_fail
    # Each independent outstanding owner/phase blocks fresh authority.
    lea r12, [rip + svst_fields]
    mov r13d, 10
1:  mov r14, [r12]
    mov qword ptr [rbx + r14], 1
    call svst_refused
    mov qword ptr [rbx + r14], 0
    add r12, 8
    dec r13
    jnz 1b
    mov qword ptr [rbx + SV_source_epoch], 0
    call svst_refused
    mov qword ptr [rbx + SV_source_epoch], 1
    mov qword ptr [rip + svt_stage], 193
    mov qword ptr [rbx + SV_primary], -5
    call svst_refused
    mov qword ptr [rbx + SV_primary], 0
    mov qword ptr [rbx + SV_apply_error], -22
    call svst_refused
    mov qword ptr [rbx + SV_apply_error], 0
    mov qword ptr [rbx + SV_uncertain], 1
    call svst_refused
    mov qword ptr [rbx + SV_uncertain], 0
    mov qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    call svst_refused
    mov qword ptr [rbx + SV_state], SV_LIVE
    inc qword ptr [rip + esv_cfg_context]
    call svst_refused
    dec qword ptr [rip + esv_cfg_context]
    mov qword ptr [rip + svt_stage], 194
    mov rax, [rip + svst_source]
    mov rcx, 0x7fffffffffffffff
    mov [rax + ESB_refs], rcx
    mov rdi, rbx
    lea rsi, [rip + svst_epoch]
    call ext_settings_service_source
    test rax, rax
    jnz svt_fail
    cmp rdx, -75
    jne svt_fail
    cmp qword ptr [rip + svst_epoch], 0
    jne svt_fail
    mov rax, [rip + svst_source]
    mov qword ptr [rax + ESB_refs], 1
    mov rdi, rax
    call ext_settings_snapshot_release
    test rax, rax
    jnz svt_fail
    mov qword ptr [rbx + SV_source], 0
    mov qword ptr [rbx + SV_source_epoch], 0
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne svt_fail
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne svt_fail
    mov qword ptr [rip + svst_source], 0
    EPILOGUE
.section .rodata
svst_fields:
    .quad SV_phase,SV_job,SV_frame,SV_release_frame,SV_delivery
    .quad SV_batch,SV_pending,SV_sap,SV_srt,SV_provisional
