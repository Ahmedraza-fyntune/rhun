# Composite preflight rejects everything before the caller's first visible mutation.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN ext_settings_catalog_check
    PROLOGUE
    mov rbx, rdi
    call cp_check_epochs
    test rax, rax
    jnz .Lcpc_return
    cmp qword ptr [rbx + CP_phase], CPP_READY
    jne .Lcpc_again
    mov r13, [rbx + CP_model]
    test r13, r13
    jz .Lcpc_invalid
    cmp qword ptr [r13 + ELM_ready], 1
    jne .Lcpc_invalid
    cmp qword ptr [r13 + ELM_refs], 0
    jle .Lcpc_invalid
    mov rax, [rbx + CP_context]
    cmp [r13 + ELM_context], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_newregistry]
    cmp [r13 + ELM_registry], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_newepoch]
    cmp [r13 + ELM_epoch], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_dirty]
    cmp [r13 + ELM_dirty], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_newprovider]
    test rax, rax
    jle .Lcpc_overflow
    cmp [r13 + ELM_provider_epoch], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_sequence]
    cmp [r13 + ELM_sequence], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_source]
    cmp [r13 + ELM_source], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_registry]
    mov rcx, 0x7fffffffffffffff
    cmp qword ptr [rbx + CP_kind], 0
    jne 2f
    cmp rax, rcx
    jae .Lcpc_overflow
    inc rax
2:  cmp [rbx + CP_newregistry], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_epoch]
    cmp rax, rcx
    jae .Lcpc_overflow
    inc rax
    cmp [rbx + CP_newepoch], rax
    jne .Lcpc_invalid
    mov rax, [rbx + CP_providerepoch]
    cmp qword ptr [rbx + CP_ppdiff], 0
    je 1f
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jae .Lcpc_overflow
    inc rax
1:  cmp [rbx + CP_newprovider], rax
    jne .Lcpc_invalid
    xor r12d, r12d
.Lcpc_row:
    cmp r12, [rbx + CP_count]
    jae .Lcpc_ok
    imul rax, r12, CPR_SIZE
    lea r14, [rbx + CP_rows + rax]
    mov r15, [r14 + CPR_view]
    mov rdi, r15
    call ext_settings_view_check
    test rax, rax
    jnz .Lcpc_return
    mov rcx, [r14 + CPR_slot]
    cmp rcx, 128
    jae .Lcpc_invalid
    cmp [r13 + ELM_slots + rcx * 8], r15
    jne .Lcpc_invalid
    inc r12
    jmp .Lcpc_row
.Lcpc_ok:
    mov rdi, rbx
    call cp_refresh_map_check
.Lcpc_return:
    EPILOGUE
.Lcpc_again:
    mov rax, -11
    EPILOGUE
.Lcpc_invalid:
    mov rax, -22
    EPILOGUE
.Lcpc_overflow:
    mov rax, -75
    EPILOGUE

# Valid-once, immediately after successful composite preflight with no yield.
# Intentionally VOID: no post-metadata rejection, allocation, IO, or schema walk.
FN ext_settings_catalog_publish
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CP_model]
    mov r13, [rip + esv_live_model]
    mov [rip + esv_live_model], r12
    mov rax, [rbx + CP_newregistry]
    mov [rip + esv_registry_epoch], rax
    mov rax, [rbx + CP_newepoch]
    mov [rip + esv_model_epoch], rax
    mov rax, [rbx + CP_newprovider]
    mov [rip + esv_provider_epoch], rax
    mov qword ptr [rbx + CP_model], 0
    mov qword ptr [rbx + CP_provider], 0
    mov qword ptr [rbx + CP_published], 1
    mov rdi, r13
    call ext_settings_model_release
    EPILOGUE

# An owned independent model reference must be captured before publication.
FN ext_settings_catalog_model
    test rdi, rdi
    jz .Lcpm_invalid
    cmp qword ptr [rdi + CP_refs], 0
    jle .Lcpm_invalid
    cmp qword ptr [rdi + CP_published], 0
    jne .Lcpm_published
    cmp qword ptr [rdi + CP_phase], CPP_READY
    jne .Lcpm_again
    PROLOGUE
    mov rbx, [rdi + CP_model]
    mov rdi, rbx
    call ext_settings_model_retain
    test rax, rax
    jnz 1f
    mov rax, rbx
    xor edx, edx
    EPILOGUE
1:  mov rdx, rax
    xor eax, eax
    EPILOGUE
.Lcpm_invalid:
    mov rdx, -22
    jmp .Lcpm_null
.Lcpm_published:
    mov rdx, -114
    jmp .Lcpm_null
.Lcpm_again:
    mov rdx, -11
.Lcpm_null:
    xor eax, eax
    ret

# Historical immutable capture tuple, source borrowed under the retained plan.
FN ext_settings_catalog_context
    test rdi, rdi
    jz .Lcpx_bad
    test rsi, rsi
    jz .Lcpx_bad
    cmp qword ptr [rdi + CP_refs], 0
    jle .Lcpx_bad
    cmp qword ptr [rdi + CP_phase], CPP_READY
    jne .Lcpx_again
    mov rax, [rdi + CP_source]
    mov [rsi], rax
    mov rax, [rdi + CP_context]
    mov [rsi + 8], rax
    mov rax, [rdi + CP_registry]
    mov [rsi + 16], rax
    mov rax, [rdi + CP_dirty]
    mov [rsi + 24], rax
    mov rax, [rdi + CP_epoch]
    mov [rsi + 32], rax
    mov rax, [rdi + CP_newregistry]
    mov [rsi + 40], rax
    mov rax, [rdi + CP_newepoch]
    mov [rsi + 48], rax
    mov rax, [rdi + CP_newprovider]
    mov [rsi + 56], rax
    xor eax, eax
    ret
.Lcpx_bad:
    mov rax, -22
    ret
.Lcpx_again:
    mov rax, -11
    ret
