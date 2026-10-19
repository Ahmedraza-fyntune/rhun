# Private candidate ownership and ready-only product views.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# Internal allocation only. Input root is borrowed, returned EP owns an independent stream.
FN ext_prepare_alloc
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rdx
    call ext_validate_identity
    test rax, rax
    jz .Lepa_id
    mov rdi, r14
    call ext_validate_identity
    test rax, rax
    jz .Lepa_id
    mov rdi, r12
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lepa_path
    mov [rsp], rax
    mov [rsp + 24], rbx
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lepa_empty
    mov rbx, rax
    mov rdi, rax
    mov esi, EP_SIZE
    call prep_object_create
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov rdi, rbx
    call ext_prepare_owner_release
    mov rbx, [rsp + 8]
    test rbx, rbx
    jz .Lepa_object_error
    mov qword ptr [rbx - RD_PO_BACK + RD_kind], RD_EP
    mov qword ptr [rbx + EP_kind], 1
    mov qword ptr [rbx + EP_root], -1
    mov qword ptr [rbx + EP_capture_handle], -1
    mov qword ptr [rbx + EP_syntax], -1
    mov qword ptr [rbx + EP_themes], -1
    mov dword ptr [rbx + EP_ext + EXT_in], -1
    mov dword ptr [rbx + EP_ext + EXT_out], -1
    mov dword ptr [rbx + EP_ext + EXT_log], -1
    mov qword ptr [rbx + EP_ext + EXT_active], -1
    cmp qword ptr [rsp + 24], -1
    je .Lepa_native_ready
    mov rdi, [rsp + 24]
    lea rsi, [rbx + EP_root]
    call ext_root_reopen_dir_into
    test rax, rax
    js .Lepa_native_failed
.Lepa_native_ready:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp]
    call prep_owned_dup
    mov [rbx + EP_ext + EXT_dir], rax
    test rax, rax
    jz .Lepa_discard
    mov rdi, r13
    call strlen
    mov rdi, rbx
    mov rsi, r13
    mov rdx, rax
    call prep_owned_dup
    mov [rbx + EP_ext + EXT_owner], rax
    test rax, rax
    jz .Lepa_discard
    mov rdi, r14
    call strlen
    mov rdi, rbx
    mov rsi, r14
    mov rdx, rax
    call prep_owned_dup
    mov [rbx + EP_ext + EXT_name], rax
    test rax, rax
    jz .Lepa_discard
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lepa_discard:
    mov r12, [rbx + PO_error]
    mov rdi, rbx
    call ext_prepare_release
    mov rcx, rax
    mov rdx, r12
    xor eax, eax
    EPILOGUE
.Lepa_object_error:
    mov rdx, [rsp + 16]
    xor ecx, ecx
    xor eax, eax
    EPILOGUE
.Lepa_native_failed:
    mov r12, rax
    mov rdi, rbx
    call ext_prepare_release
    mov rcx, rax
    mov rdx, r12
    xor eax, eax
    EPILOGUE
.Lepa_id:
    mov rdx, -EV_BAD_ID
    jmp .Lepa_empty
.Lepa_path:
    mov rdx, -EV_BAD_PATH
.Lepa_empty:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

FN ext_prepare_retain
    jmp prep_object_retain

FN ext_prepare_release
    mov esi, RD_EP
    jmp prep_retire_po_release_sync

FN ext_prepare_kind
    xor eax, eax
    cmp qword ptr [rdi + PO_ready], 1
    jne 1f
    mov rax, [rdi + EP_kind]
1:  ret

FN ext_prepare_ext
    xor eax, eax
    cmp qword ptr [rdi + PO_ready], 1
    jne 1f
    lea rax, [rdi + EP_ext]
1:  ret
.macro EP_VIEW name, field
FN \name
    xor eax, eax
    xor edx, edx
    cmp qword ptr [rdi + PO_ready], 1
    jne 1f
    mov rax, [rdi + \field + VEC_ptr]
    mov rdx, [rdi + \field + VEC_len]
1:  ret
.endm
EP_VIEW ext_prepare_commands, EP_commands
EP_VIEW ext_prepare_grammars, EP_grammars
EP_VIEW ext_prepare_themes, EP_themeviews
EP_VIEW ext_prepare_sources, EP_sources

# Private SD_value copy: field owns charged heap storage and stays immutable after preparation.
FN prep_value_dup
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rbx + PO_error], 0
    jne .Lepv_empty
    mov r14, [rbx + PO_eo]
    cmp qword ptr [r14 + EO_error], 0
    jne .Lepv_existing
    lea rdi, [rdx + 1]
    test rdi, rdi
    jz .Lepv_resource
    call prep_alloc_charge
    test rax, rax
    jz .Lepv_resource
    mov r15, rax
    mov rdi, rax
    call prep_global_admit
    test rax, rax
    js .Lepv_resource
    mov rax, r15
    add rax, [r14 + EO_used]
    jc .Lepv_resource
    cmp rax, [r14 + EO_cap]
    ja .Lepv_resource
    mov rdi, r12
    mov rsi, r13
    call mem_dup_try
    test rax, rax
    jz .Lepv_oom
    add [r14 + EO_used], r15
    add [rbx + EP_valuecharge], r15
    add [rip + prep_total_charge], r15
    EPILOGUE
.Lepv_oom:
    mov rax, -12
    jmp .Lepv_error
.Lepv_resource:
    mov rax, -EV_RESOURCE
.Lepv_error:
    mov [r14 + EO_error], rax
.Lepv_existing:
    mov rax, [r14 + EO_error]
    mov [rbx + PO_error], rax
.Lepv_empty:
    xor eax, eax
    EPILOGUE
