# Pure composite preflight followed by an infallible ownership publication callback.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.text
FN ext_settings_adoption_check
    PROLOGUE
    mov rbx, rdi
    call settings_adoption_current
    test rax, rax
    js .Lapp_check_done
    cmp qword ptr [rbx + AP_state], APS_READY
    je 1f
    cmp qword ptr [rbx + AP_state], APS_EXPORTED
    jne .Lapp_again
1:  cmp qword ptr [rbx + AP_retiredsource], 0
    jne .Lapp_stale
    cmp qword ptr [rbx + AP_error], 0
    jne .Lapp_stale
    mov rax, [rbx + AP_sourceepoch]
    cmp qword ptr [rbx + AP_changed], 0
    je 2f
    mov rdx, 0x7fffffffffffffff
    cmp rax, rdx
    jae .Lapp_overflow
    inc rax
2:  cmp [rbx + AP_futureepoch], rax
    jne .Lapp_stale
    mov rdi, [rbx + AP_plan]
    test rdi, rdi
    jz .Lapp_again
    call ext_settings_catalog_check
    test rax, rax
    js .Lapp_check_done
    mov rdi, [rbx + AP_batch]
    test rdi, rdi
    jz .Lapp_ok
    call ext_settings_batch_ack_check
    jmp .Lapp_check_done
.Lapp_ok:
    xor eax, eax
.Lapp_check_done:
    EPILOGUE
.Lapp_again:
    mov rax, -11
    EPILOGUE
.Lapp_stale:
    mov rax, -116
    EPILOGUE
.Lapp_overflow:
    mov rax, -75
    EPILOGUE
# VOID. Caller composes complete root preflight, holds all consequences, then no yield.
FN ext_settings_adoption_publish
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + AP_svc]
    mov rdi, [rbx + AP_batch]
    test rdi, rdi
    jz 1f
    call ext_settings_batch_ack_publish
1:  mov rdi, [rbx + AP_plan]
    call ext_settings_catalog_publish
    mov rax, [r12 + SV_source]
    mov [rbx + AP_retiredsource], rax
    mov rax, [r12 + SV_pending]
    mov [r12 + SV_source], rax
    mov qword ptr [r12 + SV_pending], 0
    mov rax, [rbx + AP_futureepoch]
    mov [r12 + SV_source_epoch], rax
    cmp qword ptr [rbx + AP_batch], 0
    je 2f
    mov qword ptr [r12 + SV_batch_phase], SVB_ACKED
2:  mov qword ptr [r12 + SV_sap], 0
    mov qword ptr [r12 + SV_sap_ticket], 0
    mov qword ptr [r12 + SV_apply_error], 0
    mov qword ptr [r12 + SV_apply_rebuild], 0
    mov qword ptr [r12 + SV_apply_grant], 0
    mov qword ptr [r12 + SV_abort], 0
    mov qword ptr [rbx + AP_state], APS_PUBLISHED
    EPILOGUE
# Immutable future history getter, available while the unpublished plan retains it.
FN ext_settings_adoption_model
    test rdi, rdi
    jz .Lapp_model_bad
    mov rax, SAP_MAGIC
    cmp [rdi + AP_magic], rax
    jne .Lapp_model_bad
    cmp qword ptr [rdi + AP_refs], 0
    jle .Lapp_model_bad
    cmp qword ptr [rdi + AP_state], APS_READY
    jb .Lapp_model_again
    cmp qword ptr [rdi + AP_state], APS_EXPORTED
    ja .Lapp_model_stale
    mov rdi, [rdi + AP_plan]
    jmp ext_settings_catalog_model
.Lapp_model_bad:
    xor eax, eax
    mov rdx, -22
    ret
.Lapp_model_again:
    xor eax, eax
    mov rdx, -11
    ret
.Lapp_model_stale:
    xor eax, eax
    mov rdx, -116
    ret
# The module's owned ready reference moves once to the caller. Registration stays borrowed.
FN ext_settings_service_adoption
    PROLOGUE
    mov rbx, rdi
    call settings_adoption_domain
    test rax, rax
    js .Lapp_export_error
    mov r12, [rip + settings_adoption_scheduler]
    test r12, r12
    jz .Lapp_export_again
    cmp [r12 + AP_svc], rbx
    jne .Lapp_export_stale
    cmp qword ptr [r12 + AP_state], APS_READY
    jne .Lapp_export_again
    mov rdi, r12
    call ext_settings_adoption_check
    test rax, rax
    js .Lapp_export_error
    mov qword ptr [r12 + AP_state], APS_EXPORTED
    mov qword ptr [rip + settings_adoption_scheduler], 0
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Lapp_export_stale:
    mov rax, -116
    jmp .Lapp_export_error
.Lapp_export_again:
    mov rax, -11
.Lapp_export_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
