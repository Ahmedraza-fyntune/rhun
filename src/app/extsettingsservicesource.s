# Pure current-domain and settled-source authority. Retains never publish a model.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# Internal, caller holds SVC reference. No child/global ownership changes.
FN settings_service_domain
    test rdi, rdi
    jz .Lsvs_bad
    cmp [rip + settings_service_current], rdi
    jne .Lsvs_stale
    mov rax, SVC_MAGIC
    cmp [rdi + SV_magic], rax
    jne .Lsvs_bad
    cmp qword ptr [rdi + SV_refs], 0
    jle .Lsvs_bad
    cmp qword ptr [rdi + SV_state], SV_LIVE
    jb .Lsvs_stale
    cmp qword ptr [rdi + SV_state], SV_SHUTTING
    ja .Lsvs_stale
    mov rax, [rdi + SV_context]
    test rax, rax
    jle .Lsvs_stale
    cmp [rip + esv_cfg_context], rax
    jne .Lsvs_stale
    mov rax, [rdi + SV_queue]
    test rax, rax
    jz .Lsvs_stale
    cmp [rip + esv_service_queue], rax
    jne .Lsvs_stale
    xor eax, eax
    ret
# Internal exact source preflight. IDLE has phase0; no background job authorizes CP.
FN settings_service_source_ready
    PROLOGUE
    mov rbx, rdi
    call settings_service_domain
    test rax, rax
    js .Lsvs_ready_done
    cmp qword ptr [rbx + SV_state], SV_LIVE
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_phase], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_provisional], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvs_ready_busy
    cmp qword ptr [rbx + SV_uncertain], 0
    jne .Lsvs_ready_uncertain
    mov rax, [rbx + SV_primary]
    test rax, rax
    js .Lsvs_ready_done
    mov rax, [rbx + SV_apply_error]
    test rax, rax
    js .Lsvs_ready_done
    cmp qword ptr [rbx + SV_source], 0
    je .Lsvs_ready_again
    cmp qword ptr [rbx + SV_source_epoch], 0
    jle .Lsvs_ready_stale
    xor eax, eax
.Lsvs_ready_done:
    EPILOGUE
.Lsvs_ready_busy:
    mov rax, -16
    EPILOGUE
.Lsvs_ready_again:
    mov rax, -11
    EPILOGUE
.Lsvs_ready_stale:
    mov rax, -116
    EPILOGUE
.Lsvs_ready_uncertain:
    mov rax, -117
    EPILOGUE
# source(SVC,outEpoch)->owned retained ESB/NULL,RDX error. No semantic validity grant.
FN ext_settings_service_source
    test rsi, rsi
    jz .Lsvs_source_bad
    mov qword ptr [rsi], 0
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call settings_service_source_ready
    test rax, rax
    js .Lsvs_source_error
    mov r13, [rbx + SV_source]
    mov rdi, r13
    call ext_settings_snapshot_retain
    test rax, rax
    js .Lsvs_source_error
    mov rax, [rbx + SV_source_epoch]
    mov [r12], rax
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lsvs_source_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.Lsvs_source_bad:
    xor eax, eax
    mov rdx, -22
    ret
# source_check(SVC,exactHeldESB,epoch)->0/-errno. Retention alone is not authority.
FN ext_settings_service_source_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call settings_service_source_ready
    test rax, rax
    js .Lsvs_check_done
    cmp [rbx + SV_source], r12
    jne .Lsvs_check_stale
    cmp [rbx + SV_source_epoch], r13
    jne .Lsvs_check_stale
    xor eax, eax
.Lsvs_check_done:
    EPILOGUE
.Lsvs_check_stale:
    mov rax, -116
    EPILOGUE
.Lsvs_bad:
    mov rax, -22
    ret
.Lsvs_stale:
    mov rax, -116
    ret
