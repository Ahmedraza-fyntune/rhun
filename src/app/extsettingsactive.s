# Installed authority is separate from immutable preparation capture epochs.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingscatalog.inc"
.text
# Internal synchronous borrowed model. No caller-visible lifetime transfer.
FN settings_active_model
    mov rax, [rip + esv_live_model]
    test rax, rax
    jz .Lsam_again
    cmp qword ptr [rax + ELM_refs], 0
    jle .Lsam_stale
    cmp qword ptr [rax + ELM_ready], 1
    jne .Lsam_stale
    mov rcx, [rip + esv_cfg_context]
    test rcx, rcx
    jle .Lsam_stale
    cmp [rax + ELM_context], rcx
    jne .Lsam_stale
    mov rcx, [rip + esv_registry_epoch]
    test rcx, rcx
    jle .Lsam_stale
    cmp [rax + ELM_registry], rcx
    jne .Lsam_stale
    mov rcx, [rip + esv_model_epoch]
    test rcx, rcx
    jle .Lsam_stale
    cmp [rax + ELM_epoch], rcx
    jne .Lsam_stale
    mov rcx, [rax + ELM_source]
    test rcx, rcx
    jz .Lsam_stale
    cmp qword ptr [rcx + ESB_ready], 1
    jne .Lsam_stale
    cmp qword ptr [rcx + ESB_refs], 0
    jle .Lsam_stale
    mov rdx, [rax + ELM_context]
    cmp [rcx + ESB_context], rdx
    jne .Lsam_stale
    mov rcx, [rip + esv_service_queue]
    test rcx, rcx
    jz .Lsam_again
    cmp qword ptr [rcx + EQ_epoch], 0
    jle .Lsam_stale
    mov rdx, [rcx + EQ_seq]
    test rdx, rdx
    js .Lsam_stale
    mov rcx, [rax + ELM_sequence]
    test rcx, rcx
    js .Lsam_stale
    cmp rcx, rdx
    ja .Lsam_stale
    xor edx, edx
    ret
.Lsam_again:
    mov rdx, -11
    jmp .Lsam_null
.Lsam_stale:
    mov rdx, -116
.Lsam_null:
    xor eax, eax
    ret

# Internal slot/exact EP lookup. R8 model and RAX view borrow for this call only.
FN settings_active_view
    cmp rdi, 128
    jae .Lsav_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call settings_active_model
    test rax, rax
    jz .Lsav_return
    mov r8, rax
    mov rax, [rax + ELM_slots + rbx * 8]
    test rax, rax
    jz .Lsav_stale
    cmp qword ptr [rax + EV_refs], 0
    jle .Lsav_stale
    cmp qword ptr [rax + EV_phase], EVP_READY
    jne .Lsav_stale
    test r12, r12
    jz .Lsav_stale
    cmp [rax + EV_ep], r12
    jne .Lsav_stale
    cmp qword ptr [r12 + PO_refs], 0
    jle .Lsav_stale
    cmp qword ptr [r12 + PO_ready], 1
    jne .Lsav_stale
    mov rcx, [r8 + ELM_source]
    cmp [rax + EV_source], rcx
    jne .Lsav_stale
    mov rcx, [r8 + ELM_context]
    cmp [rax + EV_context], rcx
    jne .Lsav_stale
    mov rcx, [rax + EV_count]
    cmp rcx, ESV_MAX
    ja .Lsav_stale
    cmp [r12 + EP_ext + EXT_sdefs + VEC_len], rcx
    jne .Lsav_stale
    xor edx, edx
.Lsav_return:
    EPILOGUE
.Lsav_stale:
    xor eax, eax
    mov rdx, -116
    EPILOGUE
.Lsav_bad:
    xor eax, eax
    mov rdx, -22
    ret
