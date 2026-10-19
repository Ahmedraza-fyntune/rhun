# Whole-set work shares one byte, transition and allocation ledger.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN ext_settings_catalog_step
    test rdi, rdi
    jz .Lcps_invalid
    test rsi, rsi
    jz .Lcps_invalid
    cmp rsi, 65536
    ja .Lcps_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call cp_check_epochs
    test rax, rax
    js .Lcps_no_work
    cmp qword ptr [rbx + CP_phase], CPP_READY
    je .Lcps_already_ready
    cmp qword ptr [rbx + CP_phase], CPP_FAILED
    jne 1f
    mov rax, [rbx + CP_error]
    jmp .Lcps_no_work
1:  mov [rbx + CP_bytesleft], r12
    mov qword ptr [rbx + CP_phasesleft], 1024
    mov qword ptr [rbx + CP_allocsleft], 64
.Lcps_loop:
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lcps_pending
    cmp qword ptr [rbx + CP_phasesleft], 0
    je .Lcps_pending
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lcps_pending
    mov rax, [rbx + CP_phase]
    cmp rax, CPP_READY
    je .Lcps_ready
    dec qword ptr [rbx + CP_phasesleft]
    mov rdi, rbx
    cmp rax, CPP_ID_COMPARE
    jbe .Lcps_capture
    cmp rax, CPP_PROVIDERS
    je .Lcps_providers
    cmp rax, CPP_FINAL
    je .Lcps_final
    mov rax, -22
    jmp .Lcps_failed
.Lcps_capture:
    call cp_capture_step
    jmp .Lcps_after
.Lcps_providers:
    call cp_provider_step
    jmp .Lcps_after
.Lcps_final:
    call cp_finish_step
.Lcps_after:
    test rax, rax
    js .Lcps_failed
    jmp .Lcps_loop
.Lcps_failed:
    mov [rbx + CP_error], rax
    mov qword ptr [rbx + CP_phase], CPP_FAILED
    jmp .Lcps_return
.Lcps_pending:
    xor eax, eax
    jmp .Lcps_return
.Lcps_ready:
    mov eax, 1
.Lcps_return:
    mov rdx, r12
    sub rdx, [rbx + CP_bytesleft]
    mov ecx, 1024
    sub rcx, [rbx + CP_phasesleft]
    mov r8d, 64
    sub r8, [rbx + CP_allocsleft]
    EPILOGUE
.Lcps_already_ready:
    mov eax, 1
.Lcps_no_work:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
.Lcps_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    ret

FN cp_finish_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + CP_scanpos]
    test rax, rax
    jz .Lcpf_cursor
    cmp rax, 1
    je .Lcpf_baseline
    cmp rax, 2
    je .Lcpf_oldref
    call cp_check_epochs
    test rax, rax
    jnz .Lcpf_return
    mov r12, [rbx + CP_model]
    mov rax, [rbx + CP_context]
    mov [r12 + ELM_context], rax
    mov rax, [rbx + CP_newregistry]
    mov [r12 + ELM_registry], rax
    mov rax, [rbx + CP_dirty]
    mov [r12 + ELM_dirty], rax
    mov rax, [rbx + CP_newepoch]
    mov [r12 + ELM_epoch], rax
    mov rax, [rbx + CP_newprovider]
    mov [r12 + ELM_provider_epoch], rax
    mov rax, [rbx + CP_sequence]
    mov [r12 + ELM_sequence], rax
    mov qword ptr [r12 + ELM_ready], 1
    mov qword ptr [rbx + CP_phase], CPP_READY
    jmp .Lcpf_zero
.Lcpf_cursor:
    lea r12, [rbx + CP_cursor]
    mov rdi, [r12]
    test rdi, rdi
    jz .Lcpf_advance
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lcpf_zero
    dec qword ptr [rbx + CP_allocsleft]
    call ext_settings_ini_free
    cmp rcx, 1
    jne .Lcpf_return
    jmp .Lcpf_consumed
.Lcpf_baseline:
    cmp qword ptr [rbx + CP_allocsleft], 0
    je .Lcpf_zero
    lea r12, [rbx + CP_baseline]
    mov rdi, [r12]
    dec qword ptr [rbx + CP_allocsleft]
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lcpf_return
.Lcpf_consumed:
    mov qword ptr [r12], 0
    test rdx, rdx
    jns .Lcpf_advance
    cmp qword ptr [rbx + CP_cleanup], 0
    jne .Lcpf_advance
    mov [rbx + CP_cleanup], rdx
    jmp .Lcpf_advance
.Lcpf_oldref:
    mov rdi, [rbx + CP_oldref]
    call ext_settings_model_release
    test rax, rax
    jnz .Lcpf_return
    mov qword ptr [rbx + CP_oldref], 0
.Lcpf_advance:
    inc qword ptr [rbx + CP_scanpos]
.Lcpf_zero:
    xor eax, eax
.Lcpf_return:
    EPILOGUE
