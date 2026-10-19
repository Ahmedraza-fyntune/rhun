# A captured request owns immutable bytes and one EA reference, never a TABLE reference.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.text
# table,canonicalRequest80,emptyResult32 ->0 result/-EINVAL unchanged.
FN rt_ticket_create
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call rt_ticket_request_check
    test rax, rax
    jz .Ltt_new
    cmp rdx, 1
    jne .Ltt_api
    mov [r13 + RTC_primary], rax
    xor eax, eax
    EPILOGUE
    # Public failure returns above; checked callers enter with the same frame.
FN rt_ticket_create_checked
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
.Ltt_new:
    mov edi, RT_KIND
    lea rsi, [rip + rt_retire_one]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Ltt_primary
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Ltt_eo_failed
    mov [rsp], rax
    mov [r13 + RTC_orphanEO], rax
    mov qword ptr [rax + EO_deferred], 1
    mov rsi, RTT_HEADER_SIZE + 3
    add rsi, [r12 + RTQ_keyLen]
    add rsi, [r12 + RTQ_titleLen]
    add rsi, [r12 + RTQ_keysLen]
    mov [rsp + 8], rsi
    mov rdi, rax
    call prep_object_create
    test rax, rax
    jz .Ltt_po_failed
    mov r14, rax
    mov [r13 + RTC_owner], rax
    mov qword ptr [rax + RTT_role], RT_TICKET_ROLE
    mov qword ptr [rax + RTT_phase], RTT_BUILDING
    mov rcx, [rsp + 8]
    mov [rax + RTT_fixedBytes], rcx
    mov rcx, [r12 + RTQ_ordinal]
    mov [rax + RTT_ordinal], rcx
    mov rcx, [r12 + RTQ_session]
    mov [rax + RTT_session], rcx
    mov rcx, [r12 + RTQ_id]
    mov [rax + RTT_requestID], rcx
    mov rcx, [r12 + RTQ_keyLen]
    mov [rax + RTT_keyLen], rcx
    mov qword ptr [rax + RTT_keyOffset], RTT_HEADER_SIZE
    add rcx, RTT_HEADER_SIZE + 1
    mov [rax + RTT_titleOffset], rcx
    mov rdx, [r12 + RTQ_titleLen]
    mov [rax + RTT_titleLen], rdx
    lea rcx, [rcx + rdx + 1]
    mov [rax + RTT_keysOffset], rcx
    mov rcx, [r12 + RTQ_keysLen]
    mov [rax + RTT_keysLen], rcx
    mov rdi, r14
    mov esi, RT_KIND
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    js .Ltt_mark_failed
    lea rdi, [r14 + RTT_HEADER_SIZE]
    mov rsi, [r12 + RTQ_key]
    mov rdx, [r12 + RTQ_keyLen]
    call memcpy
    mov rdi, [r14 + RTT_titleOffset]
    add rdi, r14
    mov rsi, [r12 + RTQ_title]
    mov rdx, [r12 + RTQ_titleLen]
    # memcpy does not touch a NULL source when its size is zero.
    test rdx, rdx
    jz 1f
    call memcpy
1:  mov rdi, [r14 + RTT_keysOffset]
    add rdi, r14
    mov rsi, [r12 + RTQ_keys]
    mov rdx, [r12 + RTQ_keysLen]
    test rdx, rdx
    jz 2f
    call memcpy
2:  mov rax, [r14 + RTT_ordinal]
    imul rax, rax, RT_SLOT_SIZE
    lea rax, [rbx + rax + RT_slots]
    mov r15, [rax + RTS_ea]
    # Preflight checked this increment, and no event/callback/yield intervened.
    inc qword ptr [r15 + PO_refs]
    mov [r14 + RTT_ea], r15
    mov qword ptr [r14 + RTT_phase], RTT_CAPTURED
    mov qword ptr [r14 + PO_ready], 1
    jmp .Ltt_initial_drop
.Ltt_mark_failed:
    mov [r14 + PO_error], rax
    mov [r14 + RTT_primary], rax
    mov [r13 + RTC_primary], rax
    jmp .Ltt_initial_drop
.Ltt_po_failed:
    mov [r13 + RTC_primary], rdx
.Ltt_initial_drop:
    mov rdi, [rsp]
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne 3f
    mov qword ptr [r13 + RTC_orphanEO], 0
3:  test rax, rax
    jns .Ltt_done
    mov [r13 + RTC_cleanup], rax
    mov r14, [r13 + RTC_owner]
    test r14, r14
    jz .Ltt_done
    mov [r14 + RTT_cleanup], rax
.Ltt_done:
    xor eax, eax
    EPILOGUE
.Ltt_eo_failed:
    mov rax, rdx
.Ltt_primary:
    mov [r13 + RTC_primary], rax
    jmp .Ltt_done
.Ltt_api:
    mov rax, -22
    EPILOGUE

# Common ACTIVE ownership guard. Readiness/action eligibility is separate.
FN rt_ticket_is_owned
    mov esi, RT_KIND
rt_ticket_owned_kind:
    xor eax, eax
    test rdi, rdi
    jz 9f
    lea r8, [rdi - RD_PO_BACK]
    cmp [r8 + RD_object], rdi
    jne 9f
    cmp [r8 + RD_kind], rsi
    jne 9f
    mov rcx, [r8 + RD_state]
    test ecx, RDF_STATE_MASK
    jnz 9f
    test ecx, RDF_PO
    jz 9f
    cmp qword ptr [rdi + PO_refs], 0
    je 9f
    cmp qword ptr [rdi - AO_SIZE + AO_charge], RTT_HEADER_SIZE + RD_PO_BACK + 16
    jb 9f
    cmp qword ptr [rdi + RTT_role], RT_TICKET_ROLE
    jne 9f
    mov rcx, [rdi + PO_eo]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx - RD_SIZE + RD_kind], RD_EO
    jne 9f
    test qword ptr [rcx - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz 9f
    cmp qword ptr [rcx + EO_refs], 0
    je 9f
    cmp qword ptr [rcx + EO_deferred], 1
    jne 9f
    cmp qword ptr [rcx + EO_lease], -1
    jne 9f
    jmp rt_ticket_extent_check
9:  ret

# Caller proved at least the fixed256byte header and correct role/record association.
# Shared by ACTIVE ownership and the distinct zero-ref RUNNING retirement path.
FN rt_ticket_extent_check
    xor eax, eax
    cmp qword ptr [rdi + RTT_keyLen], 1
    jb 9f
    cmp qword ptr [rdi + RTT_keyLen], 40
    ja 9f
    cmp qword ptr [rdi + RTT_titleLen], 80
    ja 9f
    cmp qword ptr [rdi + RTT_keysLen], 65536
    ja 9f
    cmp qword ptr [rdi + RTT_keyOffset], RTT_HEADER_SIZE
    jne 9f
    mov rcx, [rdi + RTT_keyLen]
    add rcx, RTT_HEADER_SIZE + 1
    cmp [rdi + RTT_titleOffset], rcx
    jne 9f
    add rcx, [rdi + RTT_titleLen]
    inc rcx
    cmp [rdi + RTT_keysOffset], rcx
    jne 9f
    add rcx, [rdi + RTT_keysLen]
    inc rcx
    cmp [rdi + RTT_fixedBytes], rcx
    jne 9f
    add rcx, RD_PO_BACK
    cmp [rdi - RD_PO_BACK - 8], rcx
    jne 9f
    add rcx, 16
    cmp [rdi - AO_SIZE + AO_charge], rcx
    jb 9f
    cmp qword ptr [rdi - AO_SIZE + AO_charge], PREP_CAP
    ja 9f
    lea rcx, [rdi - AO_SIZE]
    cmp [rdi + PO_allocs], rcx
    jne 9f
    cmp qword ptr [rcx + AO_next], 0
    jne 9f
    mov eax, 1
9:  ret

FN rt_ticket_retain
    PROLOGUE
    call rt_ticket_is_owned
    test eax, eax
    jz .Ltt_retain_bad
    cmp qword ptr [rdi + PO_ready], 1
    jne .Ltt_retain_bad
    call prep_object_retain
    EPILOGUE
.Ltt_retain_bad:
    mov rax, -22
    EPILOGUE

FN rt_ticket_release
    test rdi, rdi
    jz .Ltt_release_empty
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    je .Ltt_release_generic
    call rt_ticket_is_owned
    test eax, eax
    jz .Ltt_release_bad
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    EPILOGUE
.Ltt_release_generic:
    mov esi, RD_LEDGER
    call rt_ticket_owned_kind
    test eax, eax
    jz .Ltt_release_bad
    cmp qword ptr [rbx + PO_ready], 0
    jne .Ltt_release_bad
    cmp qword ptr [rbx + RTT_phase], RTT_BUILDING
    jne .Ltt_release_bad
    mov rax, [rbx + RTT_ro]
    or rax, [rbx + RTT_ea]
    or rax, [rbx + RTT_orphanEO]
    jnz .Ltt_release_bad
    mov rdi, rbx
    call prep_object_release_deferred
    EPILOGUE
.Ltt_release_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Ltt_release_empty:
    xor eax, eax
    mov edx, 1
    ret

# Common dispatcher has already checked exact kind8 RD_RUNNING/refs0/ready0 and role2.
FN rt_ticket_retire_fields
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call rt_ticket_extent_check
    test eax, eax
    jz .Ltt_retire_bad
    mov r13, [r12 + RD_index]
    cmp r13, 3
    ja .Ltt_retire_bad
    je .Ltt_retire_handoff
    lea rax, [rip + rt_ticket_retire_offsets]
    mov r14, [rax + r13*8]
    add r14, rbx
    mov rdi, [r14]
    test rdi, rdi
    jz .Ltt_retire_advance
    test r13, r13
    jz .Ltt_retire_ro
    cmp r13, 1
    jne .Ltt_retire_eo
    call ext_activation_owner_release
    jmp .Ltt_retire_result
.Ltt_retire_ro:
    call ext_runtime_release_deferred
    jmp .Ltt_retire_result
.Ltt_retire_eo:
    call ext_prepare_owner_release_deferred
.Ltt_retire_result:
    cmp rdx, 1
    jne .Ltt_retire_blocked
    mov qword ptr [r14], 0
    test rax, rax
    jns .Ltt_retire_advance
    mov rdi, r12
    mov rsi, rax
    call ext_prepare_retire_note_error
.Ltt_retire_advance:
    inc qword ptr [r12 + RD_index]
    mov eax, 1
    EPILOGUE
.Ltt_retire_handoff:
    mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js .Ltt_retire_blocked
    mov eax, 1
    EPILOGUE
.Ltt_retire_bad:
    mov rax, -22
.Ltt_retire_blocked:
    test rax, rax
    js 1f
    mov rax, -5
1:  xor edx, edx
    EPILOGUE
.section .rodata
.p2align 3
rt_ticket_retire_offsets: .quad RTT_ro,RTT_ea,RTT_orphanEO
