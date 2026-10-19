# Actual helper SAVE -> retained future model -> exact ACK and source publication.
.include "app/extsettingsadoption.inc"
.section .rodata
sva_extra_key: .ascii "setting.unknown"
sva_extra_value: .ascii "saved"
.bss
.p2align 3
.globl sva_pure
sva_pure: .quad 0
sva_ap: .quad 0
sva_future: .quad 0
sva_oldsource: .quad 0
sva_beforemodel: .quad 0
sva_beforeregistry: .quad 0
sva_beforeprovider: .quad 0
sva_beforequeue: .quad 0
.text
.globl sva_pure_fail
sva_pure_fail:
    mov edi, 247
    call sys_exit
sva_apply_empty:
    PROLOGUE
    mov qword ptr [rip + svw_stage], 240
    mov rbx, [rip + svw_svc]
    mov rax, [rbx + SV_source]
    mov [rip + sva_oldsource], rax
    mov rax, [rip + esv_model_epoch]
    mov [rip + sva_beforemodel], rax
    mov rax, [rip + esv_registry_epoch]
    mov [rip + sva_beforeregistry], rax
    mov rax, [rip + esv_provider_epoch]
    mov [rip + sva_beforeprovider], rax
    mov rax, [rbx + SV_queue]
    mov rax, [rax + EQ_epoch]
    mov [rip + sva_beforequeue], rax
    mov rdi, rbx
    call settings_adoption_begin
    test rax, rax
    jnz svw_fail
    mov r12, [rbx + SV_sap]
    test r12, r12
    jz svw_fail
1:  mov rdi, r12
    call settings_adoption_build_step
    test rax, rax
    js svw_fail
    cmp rax, 1
    je 2f
    call svw_wait
    jmp 1b
2:  mov qword ptr [rip + svw_stage], 241
    cmp qword ptr [rip + svwf_native_starts], 2
    jne svw_fail
    mov rdi, rbx
    call ext_settings_service_adoption
    cmp rax, r12
    jne svw_fail
    mov [rip + sva_ap], rax
    cmp qword ptr [rip + settings_adoption_scheduler], 0
    jne svw_fail
    mov rdi, r12
    call ext_settings_adoption_release
    cmp rax, -16
    jne svw_fail
    test ecx, ecx
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_model
    test rax, rax
    jz svw_fail
    mov [rip + sva_future], rax
    mov rdx, [rbx + SV_pending]
    cmp [rax + ELM_source], rdx
    jne svw_fail
    mov rdx, [rip + sva_beforeregistry]
    cmp [rax + ELM_registry], rdx
    jne svw_fail
    mov rdx, [rip + sva_beforemodel]
    inc rdx
    cmp [rax + ELM_epoch], rdx
    jne svw_fail
    # Publication rejects a newer accepted intent before any mutation.
    mov qword ptr [rip + svw_stage], 244
    mov r15, [rbx + SV_queue]
    inc qword ptr [r15 + EQ_seq]
    mov rdi, r12
    call ext_settings_adoption_check
    cmp rax, -116
    jne svw_fail
    dec qword ptr [r15 + EQ_seq]
    inc qword ptr [rbx + SV_sap_ticket]
    mov rdi, r12
    call ext_settings_adoption_check
    cmp rax, -116
    jne svw_fail
    dec qword ptr [rbx + SV_sap_ticket]
    inc qword ptr [rip + esv_provider_epoch]
    mov rdi, r12
    call ext_settings_adoption_check
    cmp rax, -116
    jne svw_fail
    dec qword ptr [rip + esv_provider_epoch]
    mov qword ptr [rip + sva_pure], 1
    mov rdi, r12
    call ext_settings_adoption_check
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_publish
    mov qword ptr [rip + sva_pure], 0
    mov qword ptr [rip + svw_stage], 242
    mov rax, [rip + sva_beforequeue]
    inc rax
    cmp [r15 + EQ_epoch], rax
    jne svw_fail
    mov rax, [rip + sva_future]
    cmp [rip + esv_live_model], rax
    jne svw_fail
    mov rax, [rip + sva_beforemodel]
    inc rax
    cmp [rip + esv_model_epoch], rax
    jne svw_fail
    mov rax, [rip + sva_beforeregistry]
    cmp [rip + esv_registry_epoch], rax
    jne svw_fail
    mov rax, [rip + sva_future]
    mov rax, [rax + ELM_source]
    cmp [rbx + SV_source], rax
    jne svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_pending], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_sap], 0
    jne svw_fail
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACKED
    jne svw_fail
    mov rax, [rip + sva_oldsource]
    cmp [r12 + AP_retiredsource], rax
    jne svw_fail
    cmp qword ptr [rax + ESB_refs], 0
    jle svw_fail
    mov qword ptr [rip + svw_stage], 243
    cmp qword ptr [r15 + EQ_count], 1
    jne svw_fail
    mov rdi, r15
    lea rsi, [rip + svw_section]
    mov edx, 10
    lea rcx, [rip + svw_key]
    mov r8d, 6
    call ext_settings_queue_find
    test rax, rax
    jz svw_fail
    cmp qword ptr [rax + EC_vallen], 2
    jne svw_fail
    mov rdi, [rax + EC_value]
    lea rsi, [rip + svw_no]
    mov edx, 2
    call memeq
    test eax, eax
    jz svw_fail
    mov rdi, r12
    call ext_settings_adoption_check
    cmp rax, -116
    jne svw_fail
    mov rdi, r12
    call ext_settings_adoption_cancel
    cmp rax, -116
    jne svw_fail
    mov rdi, [rip + sva_future]
    call ext_settings_model_release
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_adoption_release
    test rax, rax
    jnz svw_fail
    mov qword ptr [rip + svw_stage], 245
    mov r14d, 512
3:  mov edi, 1
    call ext_settings_adoption_gc
    cmp rax, 1
    ja svw_fail
    test rdx, rdx
    js svw_fail
    mov edi, 64
    call ext_settings_catalog_gc
    mov edi, 64
    call ext_settings_view_gc
    mov edi, 64
    call ext_settings_model_gc
    mov edi, 64
    call ext_settings_snapshot_gc
    dec r14
    jnz 3b
    mov qword ptr [rip + svw_stage], 245
    call ext_settings_adoption_pending
    test rax, rax
    jnz svw_fail
    cmp qword ptr [rbx + SV_refs], 1
    jne svw_fail
    EPILOGUE

# A second unchanged captured cell proves ACK removes only the accepted old intent.
sva_put_extra:
    PROLOGUE EC_SIZE
    lea rax, [rip + svw_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 10
    lea rax, [rip + sva_extra_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 15
    lea rax, [rip + sva_extra_value]
    mov [rsp + EC_value], rax
    mov qword ptr [rsp + EC_vallen], 5
    mov qword ptr [rsp + EC_remove], 0
    mov rax, [rip + svw_svc]
    mov rdi, [rax + SV_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz svw_fail
    EPILOGUE
