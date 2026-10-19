# Trusted final shutdown boundary. Root also proves external preparers quiescent.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# check(SVC)->0/-errno, pure. Immediately precedes VOID publish, no yield/mutation.
FN ext_settings_service_detach_check
    test rdi, rdi
    jz .Lsvd_bad
    cmp [rip + settings_service_current], rdi
    jne .Lsvd_stale
    mov rax, SVC_MAGIC
    cmp [rdi + SV_magic], rax
    jne .Lsvd_bad
    cmp qword ptr [rdi + SV_state], SV_SHUTTING
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_refs], 1
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_job], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_frame], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_release_frame], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_delivery], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_sap], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_srt], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_batch], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_pending], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_provisional], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_replaced_source], 0
    jne .Lsvd_busy
    cmp qword ptr [rdi + SV_detached_model], 0
    jne .Lsvd_busy
    mov rax, [rdi + SV_queue]
    test rax, rax
    jz .Lsvd_bad
    cmp [rip + esv_service_queue], rax
    jne .Lsvd_stale
    mov rcx, [rdi + SV_context]
    cmp [rip + esv_cfg_context], rcx
    jne .Lsvd_stale
    cmp qword ptr [rax + EQ_count], 0
    jne .Lsvd_busy
    cmp qword ptr [rax + EQ_batch], 0
    jne .Lsvd_busy
    cmp qword ptr [rax + EQ_retired], 0
    jne .Lsvd_busy
    xor eax, eax
    ret
.Lsvd_bad:
    mov rax, -22
    ret
.Lsvd_stale:
    mov rax, -116
    ret
.Lsvd_busy:
    mov rax, -16
    ret
# VOID: checked once immediately after complete final root+service preflight.
# The installed model is OWNED. Transfer it before revoking global authority.
FN ext_settings_service_detach_publish
    mov rax, [rip + esv_live_model]
    mov [rdi + SV_detached_model], rax
    mov qword ptr [rip + esv_live_model], 0
    mov qword ptr [rip + esv_service_queue], 0
    mov qword ptr [rip + esv_cfg_context], 0
    mov qword ptr [rip + esv_registry_epoch], 0
    mov qword ptr [rip + esv_model_epoch], 0
    mov qword ptr [rip + esv_provider_epoch], 0
    mov qword ptr [rip + settings_service_current], 0
    mov qword ptr [rdi + SV_installed], 0
    mov qword ptr [rdi + SV_state], SV_DETACHED
    ret
