# Constructor stages every owned input before publishing a borrowed registration.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.bss
.p2align 3
.globl settings_adoption_scheduler
settings_adoption_scheduler: .quad 0
.text
# Internal, caller owns SVC. Success transfers new initial SAP reference to module.
FN settings_adoption_begin
    PROLOGUE
    mov rbx, rdi
    call settings_adoption_domain
    test rax, rax
    js .Lapb_done
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lapb_busy
    cmp qword ptr [rip + settings_adoption_scheduler], 0
    jne .Lapb_busy
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lapb_stale
    cmp qword ptr [rbx + SV_apply_grant], 1
    jne .Lapb_busy
    mov rax, 0x7fffffffffffffff
    cmp [rbx + SV_sap_serial], rax
    jae .Lapb_overflow
    mov edi, AP_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lapb_alloc
    mov r12, rax
    mov rax, SAP_MAGIC
    mov [r12 + AP_magic], rax
    mov qword ptr [r12 + AP_refs], 1
    mov qword ptr [r12 + AP_state], APS_CANCELED
    mov qword ptr [r12 + AP_phase], APP_NEXT
    mov rdi, rbx
    call ext_settings_service_retain
    test rax, rax
    js .Lapb_retire
    mov [r12 + AP_svc], rbx
    mov r13, [rip + esv_live_model]
    mov rdi, r13
    call ext_settings_model_retain
    test rax, rax
    js .Lapb_retire
    mov [r12 + AP_oldmodel], r13
    mov r13, [rbx + SV_pending]
    mov rdi, r13
    call ext_settings_snapshot_retain
    test rax, rax
    js .Lapb_retire
    mov [r12 + AP_pending], r13
    mov rax, [rbx + SV_source]
    mov [r12 + AP_oldsource], rax
    mov rax, [rbx + SV_pending_epoch]
    mov [r12 + AP_pendingepoch], rax
    mov rax, [rbx + SV_source_epoch]
    mov [r12 + AP_sourceepoch], rax
    mov [r12 + AP_futureepoch], rax
    mov rax, [rbx + SV_context]
    mov [r12 + AP_context], rax
    mov rax, [rip + esv_registry_epoch]
    mov [r12 + AP_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [r12 + AP_model], rax
    mov rax, [rip + esv_provider_epoch]
    mov [r12 + AP_provider], rax
    mov rax, [rbx + SV_queue]
    mov rdx, [rax + EQ_epoch]
    mov [r12 + AP_dirty], rdx
    mov rdx, [rax + EQ_seq]
    mov [r12 + AP_sequence], rdx
    mov rax, [rbx + SV_batch]
    mov [r12 + AP_batch], rax
    mov rax, [rbx + SV_batch_phase]
    mov [r12 + AP_batchphase], rax
    mov rax, [rbx + SV_commit]
    mov [r12 + AP_commit], rax
    mov rax, [rbx + SV_apply_rebuild]
    mov [r12 + AP_rebuild], rax
    # Fixed content comparison precomputes the sole source epoch increment.
    mov r14, [r12 + AP_oldsource]
    mov rax, [r13 + ESB_exists]
    cmp [r14 + ESB_exists], rax
    jne .Lapb_changed
    mov rax, [r13 + ESB_length]
    cmp [r14 + ESB_length], rax
    jne .Lapb_changed
    lea rdi, [r13 + ESB_digest]
    lea rsi, [r14 + ESB_digest]
    mov edx, 32
    call memeq
    test eax, eax
    jnz .Lapb_register
.Lapb_changed:
    mov rax, 0x7fffffffffffffff
    cmp [r12 + AP_futureepoch], rax
    jae .Lapb_owned_overflow
    inc qword ptr [r12 + AP_futureepoch]
    mov qword ptr [r12 + AP_changed], 1
.Lapb_register:
    inc qword ptr [rbx + SV_sap_serial]
    mov rax, [rbx + SV_sap_serial]
    mov [r12 + AP_ticket], rax
    mov [rbx + SV_sap_ticket], rax
    mov qword ptr [r12 + AP_state], APS_BUILDING
    mov [rbx + SV_sap], r12
    mov [rip + settings_adoption_scheduler], r12
    mov qword ptr [rbx + SV_apply_grant], 0
    xor eax, eax
.Lapb_done:
    EPILOGUE
.Lapb_owned_overflow:
    mov rax, -75
.Lapb_retire:
    mov r13, rax
    mov [r12 + AP_error], rax
    mov rdi, r12
    call ext_settings_adoption_release
    mov rax, r13
    EPILOGUE
.Lapb_alloc:
    mov rax, rdx
    EPILOGUE
.Lapb_overflow:
    mov rax, -75
    EPILOGUE
.Lapb_busy:
    mov rax, -16
    EPILOGUE
.Lapb_stale:
    mov rax, -116
    EPILOGUE
