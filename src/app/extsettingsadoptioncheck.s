# Current authority checks never grant authority merely from retained history.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.text
# Internal borrowed SVC, pure: native/ordinary source work must be fully settled.
FN settings_adoption_domain
    PROLOGUE
    mov rbx, rdi
    call settings_service_domain
    test rax, rax
    js .Lapd_done
    cmp qword ptr [rbx + SV_state], SV_PREPARE_CLOSE
    ja .Lapd_stale
    cmp qword ptr [rbx + SV_installed], 1
    jne .Lapd_again
    cmp qword ptr [rbx + SV_phase], SVP_IDLE
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_job], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_provisional], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_replaced_source], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_primary], 0
    jne .Lapd_stale
    cmp qword ptr [rbx + SV_apply_error], 0
    jne .Lapd_stale
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lapd_unknown
    cmp qword ptr [rbx + SV_source_epoch], 0
    jle .Lapd_stale
    cmp qword ptr [rbx + SV_pending_epoch], 0
    jle .Lapd_stale
    mov rax, [rbx + SV_pending]
    test rax, rax
    jz .Lapd_again
    cmp qword ptr [rax + ESB_refs], 0
    jle .Lapd_stale
    cmp qword ptr [rax + ESB_ready], 1
    jne .Lapd_again
    mov rdx, [rbx + SV_context]
    cmp [rax + ESB_context], rdx
    jne .Lapd_stale
    mov rax, [rip + esv_live_model]
    test rax, rax
    jz .Lapd_again
    cmp qword ptr [rax + ELM_refs], 0
    jle .Lapd_stale
    cmp qword ptr [rax + ELM_ready], 1
    jne .Lapd_again
    cmp [rax + ELM_context], rdx
    jne .Lapd_stale
    mov rdx, [rbx + SV_source]
    test rdx, rdx
    jz .Lapd_stale
    cmp [rax + ELM_source], rdx
    jne .Lapd_stale
    mov rdx, [rip + esv_registry_epoch]
    test rdx, rdx
    jle .Lapd_stale
    cmp [rax + ELM_registry], rdx
    jne .Lapd_stale
    mov rdx, [rip + esv_model_epoch]
    test rdx, rdx
    jle .Lapd_stale
    cmp [rax + ELM_epoch], rdx
    jne .Lapd_stale
    mov rdx, [rip + esv_provider_epoch]
    test rdx, rdx
    jle .Lapd_stale
    cmp [rax + ELM_provider_epoch], rdx
    jne .Lapd_stale
    mov rax, [rbx + SV_queue]
    cmp qword ptr [rax + EQ_epoch], 0
    jle .Lapd_stale
    cmp qword ptr [rax + EQ_seq], 0
    js .Lapd_stale
    cmp qword ptr [rbx + SV_commit], 0
    je .Lapd_read
    cmp qword ptr [rbx + SV_commit], 1
    jne .Lapd_stale
    cmp qword ptr [rbx + SV_batch_phase], SVB_ACK_WAITING
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_batch], 0
    je .Lapd_stale
    jmp .Lapd_ok
.Lapd_read:
    cmp qword ptr [rbx + SV_abort], 0
    jne .Lapd_stale
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lapd_busy
    cmp qword ptr [rbx + SV_batch_phase], SVB_NONE
    jne .Lapd_busy
.Lapd_ok:
    xor eax, eax
.Lapd_done:
    EPILOGUE
.Lapd_stale:
    mov rax, -116
    EPILOGUE
.Lapd_again:
    mov rax, -11
    EPILOGUE
.Lapd_busy:
    mov rax, -16
    EPILOGUE
.Lapd_unknown:
    mov rax, -117
    EPILOGUE
# Internal AP borrowed; exact registration and every captured input remain current.
FN settings_adoption_current
    test rdi, rdi
    jz .Lapc_bad_leaf
    PROLOGUE
    mov rbx, rdi
    mov rax, SAP_MAGIC
    cmp [rbx + AP_magic], rax
    jne .Lapc_bad
    cmp qword ptr [rbx + AP_refs], 0
    jle .Lapc_bad
    cmp qword ptr [rbx + AP_state], APS_BUILDING
    jb .Lapc_stale
    cmp qword ptr [rbx + AP_state], APS_EXPORTED
    ja .Lapc_stale
    mov r12, [rbx + AP_svc]
    mov rdi, r12
    call settings_adoption_domain
    test rax, rax
    js .Lapc_done
    cmp [r12 + SV_sap], rbx
    jne .Lapc_stale
    mov rax, [rbx + AP_ticket]
    test rax, rax
    jle .Lapc_stale
    cmp [r12 + SV_sap_ticket], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_pending]
    cmp [r12 + SV_pending], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_pendingepoch]
    cmp [r12 + SV_pending_epoch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_oldsource]
    cmp [r12 + SV_source], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_sourceepoch]
    cmp [r12 + SV_source_epoch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_oldmodel]
    cmp [rip + esv_live_model], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_context]
    cmp [rip + esv_cfg_context], rax
    jne .Lapc_stale
    cmp [r12 + SV_context], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_registry]
    cmp [rip + esv_registry_epoch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_model]
    cmp [rip + esv_model_epoch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_provider]
    cmp [rip + esv_provider_epoch], rax
    jne .Lapc_stale
    mov rdx, [r12 + SV_queue]
    mov rax, [rbx + AP_dirty]
    cmp [rdx + EQ_epoch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_sequence]
    cmp [rdx + EQ_seq], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_batch]
    cmp [r12 + SV_batch], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_batchphase]
    cmp [r12 + SV_batch_phase], rax
    jne .Lapc_stale
    mov rax, [rbx + AP_commit]
    cmp [r12 + SV_commit], rax
    jne .Lapc_stale
    xor eax, eax
.Lapc_done:
    EPILOGUE
.Lapc_stale:
    mov rax, -116
    EPILOGUE
.Lapc_bad:
    mov rax, -22
    EPILOGUE
.Lapc_bad_leaf:
    mov rax, -22
    ret
