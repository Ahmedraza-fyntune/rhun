# These immutable-owner getters do not authorize current editor/runtime actions.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
model_readable:
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + ELM_refs], 0
    jle 1f
    cmp qword ptr [rdi + ELM_ready], 1
    jne 1f
    xor eax, eax
    ret
1:  mov rax, -22
    ret
FN ext_settings_model_source
    PROLOGUE
    mov rbx, rdi
    call model_readable
    test rax, rax
    jnz .Lmr_error
    mov rax, [rbx + ELM_source]
    xor edx, edx
    EPILOGUE
FN ext_settings_model_view
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call model_readable
    test rax, rax
    jnz .Lmr_error
    cmp r12, 128
    jae .Lmr_invalid
    mov rax, [rbx + ELM_slots + r12 * 8]
    xor edx, edx
    EPILOGUE
FN ext_settings_model_providers
    PROLOGUE
    mov rbx, rdi
    call model_readable
    test rax, rax
    jnz .Lmr_error
    mov rax, [rbx + ELM_providers]
    test rax, rax
    jz 1f
    mov rdx, [rax + PB_count]
    add rax, PB_rows
    EPILOGUE
1:  xor edx, edx
    EPILOGUE
FN ext_settings_model_epochs
    test rsi, rsi
    jz 2f
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call model_readable
    test rax, rax
    jnz 1f
    mov rax, [rbx + ELM_context]
    mov [r12], rax
    mov rax, [rbx + ELM_registry]
    mov [r12 + 8], rax
    mov rax, [rbx + ELM_dirty]
    mov [r12 + 16], rax
    mov rax, [rbx + ELM_epoch]
    mov [r12 + 24], rax
    mov rax, [rbx + ELM_provider_epoch]
    mov [r12 + 32], rax
    xor eax, eax
1:  EPILOGUE
2:  mov rax, -22
    ret
.Lmr_invalid:
    mov rax, -22
.Lmr_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE

# Historical capture only, not current live-overlay authority.
FN ext_settings_model_sequence
    PROLOGUE
    mov rbx, rdi
    call model_readable
    test rax, rax
    jnz .Lmr_error
    mov rax, [rbx + ELM_sequence]
    test rax, rax
    js .Lmr_invalid
    xor edx, edx
    EPILOGUE
