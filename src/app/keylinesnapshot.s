.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/keylinesnapshot.inc"
.text
# Typed retained object validation. Readiness and source freshness are separate.
FN ksi_active
    test rdi, rdi
    jz 8f
    cmp qword ptr [rdi + PO_refs], 0
    je 8f
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], RD_LEDGER
    jne 8f
    test qword ptr [rdi - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz 8f
    cmp qword ptr [rdi + KSI_magic], KSI_MAGIC
    jne 8f
    cmp qword ptr [rdi + KSI_nrows], KSI_MAX_ROWS
    ja 8f
    xor eax, eax
    ret
8:  mov rax, -22
    ret
FN ksi_ready
    PROLOGUE
    mov rbx, rdi
    call ksi_active
    test rax, rax
    jnz 9f
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz 9f
    cmp qword ptr [rbx + PO_ready], 1
    jne 8f
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
# Current source shape, no row string reads. Valid only within this event-loop call.
FN ksi_source_shape
    mov rax, [rip + g_keylines + VEC_len]
    cmp rax, KSI_MAX_ROWS
    ja 8f
    cmp rax, [rip + g_keylines + VEC_cap]
    ja 8f
    test rax, rax
    jz 9f
    cmp qword ptr [rip + g_keylines + VEC_ptr], 0
    je 8f
9:  xor edx, edx
    ret
8:  mov rdx, -EV_RESOURCE
    ret
# ->owned KSI/NULL, primary, cleanup. Native allocations are constructor-only here.
FN keyline_snapshot_begin
    PROLOGUE 16
    call config_key_source_epoch
    test rax, rax
    jle .Lksb_stale
    test rdx, rdx
    jnz .Lksb_stale
    mov r14, rax
    call ksi_source_shape
    test rdx, rdx
    jnz .Lksb_null
    mov r15, rax
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lksb_null
    mov r12, rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    js .Lksb_owner_fail
    mov rsi, r15
    shl rsi, 5
    add rsi, KSI_rows
    mov [rsp], rsi
    mov rdi, r12
    call prep_object_create
    test rax, rax
    jz .Lksb_create_fail
    mov r13, rax
    mov qword ptr [r13 + KSI_magic], KSI_MAGIC
    mov [r13 + KSI_epoch], r14
    mov [r13 + KSI_nrows], r15
    mov rax, [rsp]
    mov [r13 + KSI_creation], rax
    mov qword ptr [r13 + KSI_phase], KSI_ROW
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lksb_owner_fail:
    mov rdx, rax
.Lksb_create_fail:
    mov [rsp + 8], rdx
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    mov rdx, [rsp + 8]
    jmp .Lksb_null
.Lksb_stale:
    mov rdx, -116
.Lksb_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
FN keyline_snapshot_retain
    PROLOGUE
    mov rbx, rdi
    call ksi_ready
    test rax, rax
    jnz 9f
    mov rdi, rbx
    call prep_object_retain
9:  EPILOGUE
FN keyline_snapshot_release
    PROLOGUE
    mov rbx, rdi
    call ksi_active
    test rax, rax
    jnz 8f
    mov rdi, rbx
    call grammar_prepare_release_deferred
    EPILOGUE
8:  xor edx, edx
    EPILOGUE
