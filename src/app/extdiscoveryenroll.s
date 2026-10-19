# Atomic raw-to-common-ledger enrollment. No fallible step after the first store.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extdiscoveryalloc.inc"
.text
# ctx,index,kind -> slot/0, RDX diagnostic. Does not dereference payload fields.
FN pd_enroll_slot_check
    test rdi, rdi
    jz .Lpde_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpde_invalid
    cmp qword ptr [rdi + DIA_primary], 0
    jne .Lpde_invalid
    cmp qword ptr [rdi + DIA_cleanup], 0
    jne .Lpde_invalid
    PROLOGUE
    mov rbx, rdx
    call pd_alloc_slot
    test rax, rax
    js 8f
    cmp [rax + DTS_kind], rbx
    jne 8f
    cmp qword ptr [rax + DTS_state], DTS_INITIALIZED
    jne 8f
    mov r12, rax
    mov rdi, [rax + DTS_raw]
    call prep_pointer_charge
    cmp rax, [r12 + DTS_charge]
    jne 8f
    mov rax, [r12 + DTS_request]
    cmp [r12 + DTS_initialized], rax
    jne 8f
    mov rax, r12
    xor edx, edx
    EPILOGUE
8:  xor eax, eax
    mov rdx, -22
    EPILOGUE

# ctx,EO,charge -> 0/-error. Only native constructed EO reaches this boundary.
FN pd_enroll_owner_check
    test rsi, rsi
    jz .Lpde_scalar_invalid
    cmp qword ptr [rsi + EO_refs], 0
    jle .Lpde_scalar_invalid
    cmp qword ptr [rsi + EO_deferred], 1
    jne .Lpde_scalar_invalid
    cmp qword ptr [rsi + EO_error], 0
    jne .Lpde_scalar_invalid
    cmp qword ptr [rsi - RD_SIZE + RD_kind], RD_EO
    jne .Lpde_scalar_invalid
    cmp qword ptr [rsi - RD_SIZE + RD_state], 0
    jne .Lpde_scalar_invalid
    mov rax, [rsi + EO_used]
    add rax, rdx
    jc 8f
    cmp rax, [rsi + EO_cap]
    ja 8f
    cmp rax, PREP_CAP
    ja 8f
    mov rax, [rip + prep_total_charge]
    add rax, rdx
    jc 8f
    cmp rax, PREP_TOTAL_CAP
    ja 8f
    cmp [rip + discovery_extra_charge], rdx
    jb .Lpde_scalar_invalid
    xor eax, eax
    ret
8:  mov rax, -EV_RESOURCE
    ret

# ctx,slot,EO. Same charge leaves EXTRA and enters prep, sum unchanged.
FN pd_enroll_commit
    mov rcx, [rsi + DTS_charge]
    add [rdx + EO_used], rcx
    add [rip + prep_total_charge], rcx
    sub [rip + discovery_extra_charge], rcx
    jmp pd_alloc_clear_slot

FN pd_alloc_enroll_eo
    PROLOGUE
    mov rbx, rdi
    mov edx, PD_EO
    call pd_enroll_slot_check
    test rax, rax
    jz .Lpde_exit
    mov r12, rax
    mov rax, [rbx + DIA_eo]
    or rax, [rbx + DIA_ep]
    or rax, [rbx + DIA_gp]
    or rax, [rbx + DIA_blocked]
    or rax, [rbx + DIA_settings]
    or rax, [rbx + DIA_settings_cap]
    or rax, [rbx + DIA_settings_len]
    or rax, [rbx + DIA_grammars]
    or rax, [rbx + DIA_grammars_cap]
    jnz .Lpde_bad
    cmp qword ptr [r12 + DTS_logical], EO_SIZE
    jne .Lpde_bad
    cmp qword ptr [r12 + DTS_request], EO_SIZE + RD_SIZE
    jne .Lpde_bad
    mov r13, [r12 + DTS_charge]
    mov rax, [rip + prep_total_charge]
    add rax, r13
    jc .Lpde_resource
    cmp rax, PREP_TOTAL_CAP
    ja .Lpde_resource
    cmp [rip + discovery_extra_charge], r13
    jb .Lpde_bad
    mov r14, [r12 + DTS_raw]
    lea r15, [r14 + RD_SIZE]
    mov [r14 + RD_object], r15
    mov qword ptr [r14 + RD_kind], RD_EO
    mov qword ptr [r15 + EO_refs], 1
    mov [r15 + EO_used], r13
    mov qword ptr [r15 + EO_cap], PREP_CAP
    mov qword ptr [r15 + EO_error], 0
    mov qword ptr [r15 + EO_lease], -1
    mov qword ptr [r15 + EO_deferred], 1
    add [rip + prep_total_charge], r13
    sub [rip + discovery_extra_charge], r13
    mov [rbx + DIA_eo], r15
    mov rdi, rbx
    mov rsi, r12
    call pd_alloc_clear_slot
    mov rax, r15
    xor edx, edx
    EPILOGUE

FN pd_alloc_enroll_ep
    mov edx, PD_EP
    mov ecx, EP_SIZE
    mov r8d, DIA_ep
    jmp pd_enroll_po
FN pd_alloc_enroll_gp
    mov edx, PD_GP
    mov ecx, GP_SIZE
    mov r8d, DIA_gp
pd_enroll_po:
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], rcx
    mov [rsp + 8], r8
    call pd_enroll_slot_check
    test rax, rax
    jz .Lpde_exit
    mov r12, rax
    mov rax, [rsp + 8]
    cmp qword ptr [rbx + rax], 0
    jne .Lpde_bad
    mov rcx, [rsp]
    cmp [r12 + DTS_logical], rcx
    jne .Lpde_bad
    add rcx, RD_SIZE + AO_SIZE
    cmp [r12 + DTS_request], rcx
    jne .Lpde_bad
    mov r13, [rbx + DIA_eo]
    mov rsi, r13
    mov rdx, [r12 + DTS_charge]
    mov rdi, rbx
    call pd_enroll_owner_check
    test rax, rax
    js .Lpde_scalar_error
    mov rax, 0x7fffffffffffffff
    cmp [r13 + EO_refs], rax
    jae .Lpde_resource
    mov r14, [r12 + DTS_raw]
    lea r15, [r14 + RD_SIZE + AO_SIZE]
    mov [r14 + RD_object], r15
    mov qword ptr [r14 + RD_kind], RD_LEDGER
    mov qword ptr [r14 + RD_state], RDF_PO
    mov qword ptr [r14 + RD_SIZE + AO_next], 0
    mov rax, [r12 + DTS_charge]
    mov [r14 + RD_SIZE + AO_charge], rax
    mov qword ptr [r15 + PO_refs], 1
    mov [r15 + PO_eo], r13
    lea rax, [r14 + RD_SIZE]
    mov [r15 + PO_allocs], rax
    mov qword ptr [r15 + PO_error], 0
    mov qword ptr [r15 + PO_ready], 0
    cmp qword ptr [rsp + 8], DIA_ep
    jne 1f
    mov qword ptr [r15 + EP_root], -1
    mov qword ptr [r15 + EP_syntax], -1
    mov qword ptr [r15 + EP_themes], -1
    mov qword ptr [r15 + EP_capture_handle], -1
    mov dword ptr [r15 + EP_ext + EXT_in], -1
    mov dword ptr [r15 + EP_ext + EXT_out], -1
    mov dword ptr [r15 + EP_ext + EXT_log], -1
    mov qword ptr [r15 + EP_ext + EXT_active], -1
    mov qword ptr [r14 + RD_kind], RD_EP
1:  inc qword ptr [r13 + EO_refs]
    mov rcx, [rsp + 8]
    mov [rbx + rcx], r15
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pd_enroll_commit
    mov rax, r15
    xor edx, edx
    EPILOGUE

# ctx,slot,target1EP/2GP -> borrowed member.
FN pd_alloc_enroll_member
    PROLOGUE
    mov rbx, rdi
    mov r15, rdx
    mov edx, PD_MEMBER
    call pd_enroll_slot_check
    test rax, rax
    jz .Lpde_exit
    mov r12, rax
    mov rcx, [r12 + DTS_logical]
    add rcx, AO_SIZE
    jc .Lpde_bad
    cmp [r12 + DTS_request], rcx
    jne .Lpde_bad
    mov r14, [rbx + DIA_ep]
    cmp r15, 1
    je 1f
    cmp r15, 2
    jne .Lpde_bad
    mov r14, [rbx + DIA_gp]
1:  test r14, r14
    jz .Lpde_bad
    cmp qword ptr [r14 + PO_ready], 0
    jne .Lpde_bad
    cmp qword ptr [r14 + PO_error], 0
    jne .Lpde_bad
    cmp qword ptr [r14 + PO_refs], 0
    jle .Lpde_bad
    cmp qword ptr [r14 - RD_PO_BACK + RD_state], RDF_PO
    jne .Lpde_bad
    mov r13, [rbx + DIA_eo]
    cmp [r14 + PO_eo], r13
    jne .Lpde_bad
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + DTS_charge]
    call pd_enroll_owner_check
    test rax, rax
    js .Lpde_scalar_error
    mov r15, [r12 + DTS_raw]
    mov rax, [r14 + PO_allocs]
    mov [r15 + AO_next], rax
    mov rax, [r12 + DTS_charge]
    mov [r15 + AO_charge], rax
    mov [r14 + PO_allocs], r15
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pd_enroll_commit
    lea rax, [r15 + AO_SIZE]
    xor edx, edx
    EPILOGUE

# ctx,slot,count. Bind consumes the raw MEMBER. No ledger search or pointer trust.
FN pd_alloc_bind_settings
    mov ecx, 1
    jmp pd_enroll_bind
FN pd_alloc_bind_grammars
    xor ecx, ecx
pd_enroll_bind:
    test rdi, rdi
    jz .Lpde_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpde_invalid
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpde_invalid
    cmp rdx, 256
    ja .Lpde_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov r14, [rbx + DIA_ep]
    test r14, r14
    jz .Lpde_bad
    cmp qword ptr [r14 + PO_ready], 0
    jne .Lpde_bad
    lea r15, [r14 + EP_grammars]
    mov eax, DIA_grammars
    mov edx, DIA_grammars_cap
    mov esi, 8
    cmp qword ptr [rsp], 0
    je 1f
    lea r15, [r14 + EP_ext + EXT_sdefs]
    mov eax, DIA_settings
    mov edx, DIA_settings_cap
    mov esi, SD_SIZE
1:  mov [rsp + 8], rax
    mov [rsp + 16], rdx
    imul rsi, r13
    mov [rsp + 24], rsi
    mov rcx, [r15 + VEC_ptr]
    or rcx, [r15 + VEC_len]
    or rcx, [r15 + VEC_cap]
    or rcx, [rbx + rax]
    or rcx, [rbx + rdx]
    jnz .Lpde_bad
    test r13, r13
    jnz 2f
    cmp r12, -1
    jne .Lpde_bad
    xor eax, eax
    xor edx, edx
    EPILOGUE
2:  mov rdi, rbx
    mov rsi, r12
    call pd_alloc_slot
    test rax, rax
    js .Lpde_bad
    mov rcx, [rsp + 24]
    cmp [rax + DTS_logical], rcx
    jne .Lpde_bad
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    call pd_alloc_enroll_member
    test rax, rax
    jz .Lpde_exit
    mov [r15 + VEC_ptr], rax
    mov [r15 + VEC_cap], r13
    mov rcx, [rsp + 8]
    mov [rbx + rcx], rax
    mov rcx, [rsp + 16]
    mov [rbx + rcx], r13
    xor edx, edx
    EPILOGUE

FN pd_alloc_publish_setting
    test rdi, rdi
    jz .Lpde_scalar_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpde_scalar_invalid
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpde_scalar_invalid
    mov rcx, [rdi + DIA_ep]
    test rcx, rcx
    jz .Lpde_scalar_invalid
    cmp qword ptr [rcx + PO_ready], 0
    jne .Lpde_scalar_invalid
    cmp rsi, [rdi + DIA_settings_len]
    jne .Lpde_scalar_invalid
    cmp rsi, [rdi + DIA_settings_cap]
    jae .Lpde_scalar_invalid
    cmp rsi, [rcx + EP_ext + EXT_sdefs + VEC_len]
    jne .Lpde_scalar_invalid
    mov rax, [rdi + DIA_settings]
    cmp [rcx + EP_ext + EXT_sdefs + VEC_ptr], rax
    jne .Lpde_scalar_invalid
    imul rdx, rsi, SD_SIZE
    add rdx, rax
    cmp qword ptr [rdx + SD_value], 0
    jne .Lpde_scalar_invalid
    mov dword ptr [rdx + SD_pad], 1
    inc qword ptr [rcx + EP_ext + EXT_sdefs + VEC_len]
    inc qword ptr [rdi + DIA_settings_len]
    xor eax, eax
    ret

FN pd_alloc_enroll_value
    PROLOGUE
    mov rbx, rdi
    mov r15, rdx
    mov edx, PD_VALUE
    call pd_enroll_slot_check
    test rax, rax
    jz .Lpde_exit
    mov r12, rax
    mov r14, [rbx + DIA_ep]
    test r14, r14
    jz .Lpde_bad
    cmp qword ptr [r14 + PO_ready], 0
    jne .Lpde_bad
    cmp qword ptr [r14 + PO_error], 0
    jne .Lpde_bad
    cmp qword ptr [r14 + PO_refs], 0
    jle .Lpde_bad
    cmp qword ptr [r14 - RD_PO_BACK + RD_state], RDF_PO
    jne .Lpde_bad
    cmp r15, [rbx + DIA_settings_len]
    jae .Lpde_bad
    mov rcx, [rbx + DIA_settings]
    cmp [r14 + EP_ext + EXT_sdefs + VEC_ptr], rcx
    jne .Lpde_bad
    imul r15, r15, SD_SIZE
    add r15, rcx
    cmp dword ptr [r15 + SD_pad], 1
    jne .Lpde_bad
    cmp qword ptr [r15 + SD_value], 0
    jne .Lpde_bad
    mov rcx, [r12 + DTS_raw]
    mov rax, [r12 + DTS_request]
    cmp byte ptr [rcx + rax - 1], 0
    jne .Lpde_bad
    mov r13, [rbx + DIA_eo]
    cmp [r14 + PO_eo], r13
    jne .Lpde_bad
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + DTS_charge]
    call pd_enroll_owner_check
    test rax, rax
    js .Lpde_scalar_error
    mov rax, [r14 + EP_valuecharge]
    add rax, [r12 + DTS_charge]
    jc .Lpde_resource
    mov rcx, [r12 + DTS_raw]
    mov [r15 + SD_value], rcx
    mov [r14 + EP_valuecharge], rax
    mov r15, rcx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pd_enroll_commit
    mov rax, r15
    xor edx, edx
    EPILOGUE

FN pd_alloc_attach_gp
    test rdi, rdi
    jz .Lpde_scalar_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpde_scalar_invalid
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpde_scalar_invalid
    mov rax, [rdi + DIA_ep]
    mov rdx, [rdi + DIA_gp]
    test rax, rax
    jz .Lpde_scalar_invalid
    test rdx, rdx
    jz .Lpde_scalar_invalid
    cmp qword ptr [rax + PO_ready], 0
    jne .Lpde_scalar_invalid
    cmp qword ptr [rdx + PO_ready], 1
    jne .Lpde_scalar_invalid
    mov rcx, [rax + PO_eo]
    cmp [rdx + PO_eo], rcx
    jne .Lpde_scalar_invalid
    mov rcx, [rdi + DIA_grammars]
    test rcx, rcx
    jz .Lpde_scalar_invalid
    cmp [rax + EP_grammars + VEC_ptr], rcx
    jne .Lpde_scalar_invalid
    mov rsi, [rax + EP_grammars + VEC_len]
    cmp rsi, [rdi + DIA_grammars_cap]
    jae .Lpde_scalar_invalid
    cmp qword ptr [rcx + rsi*8], 0
    jne .Lpde_scalar_invalid
    mov [rcx + rsi*8], rdx
    inc qword ptr [rax + EP_grammars + VEC_len]
    mov qword ptr [rdi + DIA_gp], 0
    xor eax, eax
    ret

# Forward transfer only. Caller combines check+VOID with the row native attach.
FN pd_alloc_take_ep_check
    test rdi, rdi
    jz .Lpde_scalar_invalid
    test rsi, rsi
    jz .Lpde_scalar_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpde_scalar_invalid
    mov rax, [rdi + DIA_primary]
    or rax, [rdi + DIA_cleanup]
    or rax, [rdi + DIA_eo]
    or rax, [rdi + DIA_gp]
    or rax, [rdi + DIA_blocked]
    jnz .Lpde_scalar_invalid
    cmp qword ptr [rsi], 0
    jne .Lpde_scalar_invalid
    mov rax, [rdi + DIA_ep]
    test rax, rax
    jz .Lpde_scalar_invalid
    cmp qword ptr [rax + PO_ready], 1
    jne .Lpde_scalar_invalid
    cmp qword ptr [rax + PO_error], 0
    jne .Lpde_scalar_invalid
    mov rcx, [rax + PO_eo]
    cmp qword ptr [rcx + EO_error], 0
    jne .Lpde_scalar_invalid
    xor eax, eax
    ret
FN pd_alloc_take_ep_VOID
    mov rax, [rdi + DIA_ep]
    mov [rsi], rax
    mov qword ptr [rdi + DIA_ep], 0
    jmp pd_alloc_clear_bindings
FN pd_alloc_clear_bindings
    mov qword ptr [rdi + DIA_settings], 0
    mov qword ptr [rdi + DIA_settings_cap], 0
    mov qword ptr [rdi + DIA_settings_len], 0
    mov qword ptr [rdi + DIA_grammars], 0
    mov qword ptr [rdi + DIA_grammars_cap], 0
    ret

FN pd_alloc_extra_take_check
    test rdx, rdx
    jz .Lpde_scalar_invalid
    PROLOGUE
    mov rbx, rdx
    mov edx, PD_EXTRA
    call pd_enroll_slot_check
    test rax, rax
    jz 1f
    mov rcx, [rbx]
    or rcx, [rbx + 8]
    or rcx, [rbx + 16]
    or rcx, [rbx + 24]
    jnz 2f
    xor eax, eax
    EPILOGUE
2:  mov rdx, -22
1:  mov rax, rdx
    EPILOGUE
FN pd_alloc_extra_take_VOID
    mov rax, rsi
    shl rax, 6
    lea rsi, [rdi + rax + DIA_slots]
    mov rax, [rsi + DTS_raw]
    mov [rdx], rax
    mov rax, [rsi + DTS_request]
    mov [rdx + 8], rax
    mov rax, [rsi + DTS_charge]
    mov [rdx + 16], rax
    mov qword ptr [rdx + 24], PD_EXTRA
    jmp pd_alloc_clear_slot

.Lpde_bad:
    mov rdx, -22
    xor eax, eax
.Lpde_exit:
    EPILOGUE
.Lpde_resource:
    mov rax, -EV_RESOURCE
.Lpde_scalar_error:
    mov rdx, rax
    cmp rax, -22
    je 1f
    mov rdi, rbx
    mov rsi, rax
    call pd_alloc_abort
1:  xor eax, eax
    EPILOGUE
.Lpde_invalid:
    xor eax, eax
    mov rdx, -22
    ret
.Lpde_scalar_invalid:
    mov rax, -22
    ret
