# Private effective values retain their exact schema and source across yields.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.text
# begin(owned-ready EP borrowed, explicit ESB orNULL current raw source).
# Pointer refusal leaves caller references untouched; partial ownership retires internally.
FN ext_settings_view_begin
    test rdi, rdi
    jz .Lesv_begin_bad
    cmp qword ptr [rdi + PO_ready], 1
    jne .Lesv_begin_bad
    cmp qword ptr [rdi + PO_refs], 0
    jle .Lesv_begin_bad
    cmp qword ptr [rip + esv_service_queue], 0
    je .Lesv_begin_again
    cmp qword ptr [rip + esv_registry_epoch], 0
    jle .Lesv_begin_stale
    cmp qword ptr [rip + esv_model_epoch], 0
    jle .Lesv_begin_stale
    mov rax, [rdi + EP_ext + EXT_sdefs + VEC_len]
    cmp rax, ESV_MAX
    ja .Lesv_begin_bad
    test rsi, rsi
    jnz 1f
    mov rsi, [rip + esv_live_model]
    test rsi, rsi
    jz .Lesv_begin_again
    mov rsi, [rsi + ELM_source]
1:  test rsi, rsi
    jz .Lesv_begin_again
    cmp qword ptr [rsi + ESB_ready], 1
    jne .Lesv_begin_bad
    cmp qword ptr [rsi + ESB_refs], 0
    jle .Lesv_begin_bad
    mov rax, [rip + esv_cfg_context]
    cmp [rsi + ESB_context], rax
    jne .Lesv_begin_stale
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, EV_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lesv_begin_empty
    mov r13, rax
    mov qword ptr [rax + EV_refs], 1
    mov qword ptr [rax + EV_phase], EVP_ID_OWNER
    mov rdi, rbx
    call ext_prepare_retain
    test rax, rax
    js .Lesv_begin_retire
    mov [r13 + EV_ep], rbx
    mov rdi, r12
    call ext_settings_snapshot_retain
    test rax, rax
    js .Lesv_begin_retire
    mov [r13 + EV_source], r12
    mov rdi, [rip + esv_live_model]
    test rdi, rdi
    jz 2f
    mov r14, rdi
    call ext_settings_model_retain
    test rax, rax
    js .Lesv_begin_retire
    mov [r13 + EV_oldmodel], r14
2:  mov rdi, r12
    call ext_settings_ini_begin
    test rax, rax
    jz .Lesv_begin_cursor
    mov [r13 + EV_cursor], rax
    mov rax, [rbx + EP_ext + EXT_sdefs + VEC_len]
    mov [r13 + EV_count], rax
    mov rax, [rip + esv_cfg_context]
    mov [r13 + EV_context], rax
    mov rax, [rip + esv_registry_epoch]
    mov [r13 + EV_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [r13 + EV_model], rax
    mov rax, [rip + esv_service_queue]
    mov rax, [rax + EQ_epoch]
    test rax, rax
    jle .Lesv_begin_queue_stale
    mov [r13 + EV_dirty], rax
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesv_begin_queue_stale:
    mov rax, -116
    jmp .Lesv_begin_retire
.Lesv_begin_cursor:
    mov rax, rdx
.Lesv_begin_retire:
    mov r14, rax
    mov [r13 + EV_error], rax
    mov qword ptr [r13 + EV_phase], EVP_FAILED
    mov rdi, r13
    call ext_settings_view_release
    xor eax, eax
    mov rdx, r14
    xor ecx, ecx
.Lesv_begin_empty:
    xor ecx, ecx
    EPILOGUE
.Lesv_begin_bad:
    mov rdx, -22
    jmp .Lesv_begin_null
.Lesv_begin_again:
    mov rdx, -11
    jmp .Lesv_begin_null
.Lesv_begin_stale:
    mov rdx, -116
.Lesv_begin_null:
    xor eax, eax
    xor ecx, ecx
    ret

# Internal before every yielding slice, before deriving any queue/schema address.
FN esv_check_epochs
    test rdi, rdi
    jz .Lesv_epochs_bad
    cmp qword ptr [rdi + EV_refs], 0
    jle .Lesv_epochs_bad
    mov rax, [rip + esv_cfg_context]
    test rax, rax
    jle .Lesv_epochs_stale
    cmp [rdi + EV_context], rax
    jne .Lesv_epochs_stale
    mov rax, [rip + esv_registry_epoch]
    test rax, rax
    jle .Lesv_epochs_stale
    cmp [rdi + EV_registry], rax
    jne .Lesv_epochs_stale
    mov rax, [rip + esv_model_epoch]
    test rax, rax
    jle .Lesv_epochs_stale
    cmp [rdi + EV_model], rax
    jne .Lesv_epochs_stale
    mov rax, [rip + esv_service_queue]
    test rax, rax
    jz .Lesv_epochs_stale
    mov rax, [rax + EQ_epoch]
    test rax, rax
    jle .Lesv_epochs_stale
    cmp [rdi + EV_dirty], rax
    jne .Lesv_epochs_stale
    mov rax, [rdi + EV_source]
    test rax, rax
    jz .Lesv_epochs_bad
    cmp qword ptr [rax + ESB_ready], 1
    jne .Lesv_epochs_stale
    cmp qword ptr [rax + ESB_refs], 0
    jle .Lesv_epochs_stale
    xor eax, eax
    ret
.Lesv_epochs_bad:
    mov rax, -22
    ret
.Lesv_epochs_stale:
    mov rax, -116
    ret
FN ext_settings_view_check
    PROLOGUE
    mov rbx, rdi
    call esv_check_epochs
    test rax, rax
    jnz 1f
    cmp qword ptr [rbx + EV_phase], EVP_READY
    je 1f
    mov rax, -11
1:  EPILOGUE
# A retained ready view owns these immutable bytes even after publication advances epochs.
# Freshness is checked separately before authorizing catalog/process consequences.
FN ext_settings_view_value
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + EV_refs], 0
    jle 2f
    cmp qword ptr [rdi + EV_phase], EVP_READY
    jne 1f
    cmp rsi, [rdi + EV_count]
    jae 2f
    imul rax, rsi, EVR_SIZE
    mov rax, [rdi + rax + EV_rows + EVR_value]
    xor edx, edx
    ret
1:  mov rdx, -11
    jmp 3f
2:  mov rdx, -22
3:  xor eax, eax
    ret
FN ext_settings_view_flags
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + EV_refs], 0
    jle 1f
    cmp qword ptr [rdi + EV_phase], EVP_READY
    jne 1f
    mov rax, [rdi + EV_pinned]
    mov rdx, [rdi + EV_disabled]
    mov rcx, [rdi + EV_invalid]
    ret
1:  mov rax, -11
    xor edx, edx
    xor ecx, ecx
    ret
