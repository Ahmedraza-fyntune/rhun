.include "app/extruntimeticket.inc"
.data
tt_key: .zero 40
tt_title: .zero 80
tt_keys: .zero 65536
.bss
.p2align 3
tt_request: .zero RTQ_SIZE
tt_out: .zero RTC_SIZE
tt_live: .quad 0
tt_charge: .quad 0
tt_refs: .quad 0
tt_stage: .quad 0
tt_armed: .quad 0
tt_alloc_calls: .quad 0
tt_fail_at: .quad 0
tt_mark_fault: .quad 0
tt_register_fault: .quad 0
tt_drop_mode: .quad 0
tt_report: .zero 32
tt_unmap_fault: .quad 0
tt_unmap_calls: .quad 0
tt_unmap_seen: .quad 0
tt_failed_map: .quad 0
tt_failed_header: .zero 16
.text
tt_cases:
    PROLOGUE
    mov qword ptr [rip + tt_stage], 221
    lea rdi, [rip + tt_key]
    mov esi, 0x61
    mov edx, 40
    call memset
    lea rdi, [rip + tt_title]
    mov esi, 0x74
    mov edx, 80
    call memset
    lea rdi, [rip + tt_keys]
    mov esi, 0x6b
    mov edx, 65536
    call memset
    mov rax, [rip + g_mem_live]
    mov [rip + tt_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + tt_charge], rax
    mov rax, [rip + af_ea]
    mov rax, [rax + PO_refs]
    mov [rip + tt_refs], rax
    mov qword ptr [rip + tt_request + RTQ_ordinal], 17
    mov rax, [rip + rts_session]
    mov [rip + tt_request + RTQ_session], rax
    mov qword ptr [rip + tt_request + RTQ_id], 1
    mov qword ptr [rip + tt_request + RTQ_kind], RTQ_REGISTER
    lea rax, [rip + tt_key]
    mov [rip + tt_request + RTQ_key], rax
.if TT_TEST_MAX == 1
    mov qword ptr [rip + tt_request + RTQ_keyLen], 40
    lea rax, [rip + tt_title]
    mov [rip + tt_request + RTQ_title], rax
    mov qword ptr [rip + tt_request + RTQ_titleLen], 80
    lea rax, [rip + tt_keys]
    mov [rip + tt_request + RTQ_keys], rax
    mov qword ptr [rip + tt_request + RTQ_keysLen], 65536
.else
    mov qword ptr [rip + tt_request + RTQ_keyLen], 1
.endif
    mov qword ptr [rip + tt_stage], 222
    mov rdi, [rip + rts_table]
    lea rsi, [rip + tt_request]
    mov rdx, rdi
    call rt_ticket_create
    cmp rax, -22
    jne tt_fail
    call tt_census
    mov qword ptr [rip + tt_stage], 223
    mov qword ptr [rip + tt_request + RTQ_id], 0
    call tt_create
    test rax, rax
    jnz tt_fail
    cmp qword ptr [rip + tt_out + RTC_primary], -22
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_primary], 0
    call tt_empty
    call tt_census
    mov qword ptr [rip + tt_request + RTQ_id], 1
    mov qword ptr [rip + tt_stage], 224
    mov byte ptr [rip + tt_key], 0x41
    call tt_create
    mov byte ptr [rip + tt_key], 0x61
    test rax, rax
    jnz tt_fail
    cmp qword ptr [rip + tt_out + RTC_primary], -22
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_primary], 0
    call tt_empty
    call tt_census
    mov qword ptr [rip + tt_stage], 225
    mov rax, [rip + af_ea]
    mov qword ptr [rax + PO_refs], -1
    call tt_create
    mov r12, rax
    mov rax, [rip + af_ea]
    mov rcx, [rip + tt_refs]
    mov [rax + PO_refs], rcx
    test r12, r12
    jnz tt_fail
    cmp qword ptr [rip + tt_out + RTC_primary], -75
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_primary], 0
    call tt_empty
    call tt_census
    mov qword ptr [rip + tt_stage], 226
    mov qword ptr [rip + tt_armed], 1
.if TT_TEST_FAULT == 1 || TT_TEST_FAULT == 2
    mov qword ptr [rip + tt_fail_at], TT_TEST_FAULT
.endif
.if TT_TEST_FAULT == 3 || TT_TEST_FAULT == 7
    mov qword ptr [rip + tt_mark_fault], 1
.endif
.if TT_TEST_FAULT == 4 || TT_TEST_FAULT == 7
    mov qword ptr [rip + tt_drop_mode], 1
.endif
.if TT_TEST_FAULT == 5
    mov qword ptr [rip + tt_drop_mode], 2
.endif
.if TT_TEST_FAULT == 6
    mov qword ptr [rip + tt_register_fault], 1
.endif
    call tt_create
    mov qword ptr [rip + tt_armed], 0
    test rax, rax
    jnz tt_fail
.if TT_TEST_FAULT == 1 || TT_TEST_FAULT == 2 || TT_TEST_FAULT == 6
    mov qword ptr [rip + tt_stage], 231
    cmp qword ptr [rip + tt_out + RTC_owner], 0
    jne tt_fail
    mov qword ptr [rip + tt_stage], 232
    cmp qword ptr [rip + tt_out + RTC_orphanEO], 0
    jne tt_fail
.if TT_TEST_FAULT == 6
    cmp qword ptr [rip + tt_alloc_calls], 0
    jne tt_fail
    cmp qword ptr [rip + tt_out + RTC_primary], -17
.else
    mov qword ptr [rip + tt_stage], 233
    cmp qword ptr [rip + tt_alloc_calls], TT_TEST_FAULT
    jne tt_fail
    mov qword ptr [rip + tt_stage], 234
    cmp qword ptr [rip + tt_out + RTC_primary], -12
.endif
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_primary], 0
    mov qword ptr [rip + tt_stage], 235
    call tt_empty
    mov qword ptr [rip + tt_stage], 236
    call tt_drain
    mov qword ptr [rip + tt_stage], 237
    call tt_census
    jmp tt_cases_done
.endif
    mov rbx, [rip + tt_out + RTC_owner]
    test rbx, rbx
    jz tt_fail
.if TT_TEST_FAULT == 4 || TT_TEST_FAULT == 7
    mov rdi, [rip + tt_out + RTC_orphanEO]
    test rdi, rdi
    jz tt_fail
    cmp [rbx + PO_eo], rdi
    jne tt_fail
    cmp qword ptr [rdi + EO_refs], 2
    jne tt_fail
    call ext_prepare_owner_release_deferred
    test rax, rax
    jnz tt_fail
    cmp rdx, 1
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_orphanEO], 0
.else
    cmp qword ptr [rip + tt_out + RTC_orphanEO], 0
    jne tt_fail
.endif
.if TT_TEST_FAULT == 3 || TT_TEST_FAULT == 7
    cmp qword ptr [rip + tt_out + RTC_primary], -22
    jne tt_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    jne tt_fail
    cmp qword ptr [rbx + PO_ready], 0
    jne tt_fail
    cmp qword ptr [rbx + RTT_phase], RTT_BUILDING
    jne tt_fail
    cmp qword ptr [rbx + RTT_ea], 0
    jne tt_fail
    mov rdi, rbx
    call rt_ticket_release
    test rax, rax
    jnz tt_fail
    cmp rdx, 1
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_owner], 0
    call tt_drain
    call tt_census
    mov rax, [rip + af_ea]
    mov rcx, [rip + tt_refs]
    cmp [rax + PO_refs], rcx
    jne tt_fail
    jmp tt_cases_done
.endif
    cmp qword ptr [rip + tt_out + RTC_primary], 0
    jne tt_fail
.if TT_TEST_FAULT == 4 || TT_TEST_FAULT == 5
    cmp qword ptr [rip + tt_out + RTC_cleanup], -5
    jne tt_fail
    cmp qword ptr [rbx + RTT_cleanup], -5
    jne tt_fail
.else
    cmp qword ptr [rip + tt_out + RTC_cleanup], 0
    jne tt_fail
.endif
    mov rdi, rbx
    call rt_ticket_is_owned
    cmp eax, 1
    jne tt_fail
    cmp qword ptr [rbx + PO_ready], 1
    jne tt_fail
    cmp qword ptr [rbx + RTT_phase], RTT_CAPTURED
    jne tt_fail
    mov rax, [rip + af_ea]
    cmp [rbx + RTT_ea], rax
    jne tt_fail
    mov rcx, [rip + tt_refs]
    inc rcx
    cmp [rax + PO_refs], rcx
    jne tt_fail
    cmp qword ptr [rbx + RTT_ordinal], 17
    jne tt_fail
    mov rax, [rip + rts_session]
    cmp [rbx + RTT_session], rax
    jne tt_fail
    cmp qword ptr [rbx + RTT_requestID], 1
    jne tt_fail
.if TT_TEST_MAX == 1
    cmp qword ptr [rbx + RTT_fixedBytes], RTT_MAX_SIZE
    jne tt_fail
.else
    cmp qword ptr [rbx + RTT_fixedBytes], 260
    jne tt_fail
.endif
    mov qword ptr [rip + tt_stage], 230
    mov r14, [rbx + RTT_fixedBytes]
    inc qword ptr [rbx + RTT_fixedBytes]
    mov rdi, rbx
    call rt_ticket_release
    mov [rbx + RTT_fixedBytes], r14
    cmp rax, -22
    jne tt_fail
    test rdx, rdx
    jnz tt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne tt_fail
    mov qword ptr [rbx + RTT_role], RT_TABLE_ROLE
    mov rdi, rbx
    call rt_ticket_release
    mov qword ptr [rbx + RTT_role], RT_TICKET_ROLE
    cmp rax, -22
    jne tt_fail
    test rdx, rdx
    jnz tt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne tt_fail
    mov qword ptr [rip + tt_stage], 227
    mov rdi, rbx
    call rt_ticket_retain
    test rax, rax
    jnz tt_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne tt_fail
    mov rdi, rbx
    call rt_ticket_release
    test rax, rax
    jnz tt_fail
    cmp rdx, 1
    jne tt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne tt_fail
    mov qword ptr [rip + tt_stage], 228
    lea rdi, [rip + tt_key]
    mov esi, 0x7a
    mov edx, 40
    call memset
    lea rdi, [rip + tt_title]
    mov esi, 0x7a
    mov edx, 80
    call memset
    lea rdi, [rip + tt_keys]
    mov esi, 0x7a
    mov edx, 65536
    call memset
    mov rdi, [rbx + RTT_keyOffset]
    add rdi, rbx
    mov rsi, [rbx + RTT_keyLen]
    mov edx, 0x61
    call tt_bytes
    mov rdi, [rbx + RTT_titleOffset]
    add rdi, rbx
    mov rsi, [rbx + RTT_titleLen]
    mov edx, 0x74
    call tt_bytes
    mov rdi, [rbx + RTT_keysOffset]
    add rdi, rbx
    mov rsi, [rbx + RTT_keysLen]
    mov edx, 0x6b
    call tt_bytes
    mov qword ptr [rip + tt_stage], 229
.if TT_TEST_FAULT == 8
    mov qword ptr [rip + tt_unmap_fault], 1
.endif
    mov rdi, rbx
    call rt_ticket_release
    test rax, rax
    jnz tt_fail
    cmp rdx, 1
    jne tt_fail
    mov qword ptr [rip + tt_out + RTC_owner], 0
    call tt_drain
    call tt_census
    mov rax, [rip + af_ea]
    mov rcx, [rip + tt_refs]
    cmp [rax + PO_refs], rcx
    jne tt_fail
tt_cases_done:
    EPILOGUE
tt_create:
    mov rdi, [rip + rts_table]
    lea rsi, [rip + tt_request]
    lea rdx, [rip + tt_out]
    jmp rt_ticket_create
tt_empty:
    mov rax, [rip + tt_out + RTC_owner]
    or rax, [rip + tt_out + RTC_orphanEO]
    or rax, [rip + tt_out + RTC_primary]
    or rax, [rip + tt_out + RTC_cleanup]
    jnz tt_fail
    ret
tt_census:
    mov rax, [rip + g_mem_live]
    cmp [rip + tt_live], rax
    jne tt_fail
    mov rax, [rip + prep_total_charge]
    cmp [rip + tt_charge], rax
    jne tt_fail
    ret
tt_bytes:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp [rdi + rcx], dl
    jne tt_fail
    inc rcx
    jmp 1b
2:  cmp byte ptr [rdi + rsi], 0
    jne tt_fail
    ret
tt_fail:
    mov rdi, [rip + tt_stage]
    jmp sys_exit

tt_drain:
    PROLOGUE
    mov r15d, 4096
1:  mov r13, [rip + g_mem_live]
    mov r14, [rip + prep_total_charge]
    mov edi, 1
    lea rsi, [rip + tt_report]
    call ext_prepare_retire_step
    test rax, rax
    js tt_fail
    cmp qword ptr [rip + tt_report], 1
    ja tt_fail
.if TT_TEST_FAULT == 8
    cmp qword ptr [rip + tt_unmap_calls], 0
    je 3f
    cmp qword ptr [rip + tt_unmap_seen], 0
    jne 4f
    cmp qword ptr [rip + tt_unmap_calls], 1
    jne tt_fail
    cmp [rip + g_mem_live], r13
    jne tt_fail
    cmp [rip + prep_total_charge], r14
    jne tt_fail
    cmp qword ptr [rip + tt_report + 16], 1
    jne tt_fail
    mov rcx, [rip + tt_failed_map]
    mov rdx, [rip + tt_failed_header]
    cmp [rcx], rdx
    jne tt_fail
    mov rdx, [rip + tt_failed_header + 8]
    cmp [rcx + 8], rdx
    jne tt_fail
    mov qword ptr [rip + tt_unmap_fault], 0
    mov qword ptr [rip + tt_unmap_seen], 1
    mov qword ptr [rip + tt_failed_map], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne tt_fail
    jmp 5f
4:  cmp qword ptr [rip + tt_report + 24], -5
    jne tt_fail
    jmp 6f
3:  cmp qword ptr [rip + tt_report + 24], 0
    jne tt_fail
    jmp 6f
.else
    cmp qword ptr [rip + tt_report + 24], 0
    jne tt_fail
.endif
6:  cmp qword ptr [rip + tt_report + 16], 0
    jne tt_fail
    test rax, rax
    jz 2f
5:  dec r15
    jnz 1b
    jmp tt_fail
2:
.if TT_TEST_FAULT == 8
    cmp qword ptr [rip + tt_unmap_seen], 1
    jne tt_fail
    cmp qword ptr [rip + tt_unmap_calls], 1
    jne tt_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz tt_fail
.endif
    EPILOGUE
FN mem_alloc_try
    cmp qword ptr [rip + tt_armed], 0
    je tt_real_alloc
    inc qword ptr [rip + tt_alloc_calls]
    mov rax, [rip + tt_alloc_calls]
    cmp rax, [rip + tt_fail_at]
    jne tt_real_alloc
    xor eax, eax
    ret
FN ext_prepare_retire_mark_custom_po
    cmp qword ptr [rip + tt_mark_fault], 0
    je tt_real_mark
    mov qword ptr [rip + tt_mark_fault], 0
    mov rax, -22
    ret
FN ext_prepare_retire_register_kind
    cmp qword ptr [rip + tt_register_fault], 0
    je tt_real_register
    mov qword ptr [rip + tt_register_fault], 0
    mov rax, -17
    ret
FN ext_prepare_owner_release_deferred
    cmp qword ptr [rip + tt_drop_mode], 0
    je tt_real_eo_drop
    cmp qword ptr [rip + tt_drop_mode], 2
    je 1f
    mov qword ptr [rip + tt_drop_mode], 0
    mov rax, -5
    xor edx, edx
    ret
1:  PROLOGUE
    mov qword ptr [rip + tt_drop_mode], 0
    call tt_real_eo_drop
    cmp rdx, 1
    jne tt_fail
    mov rax, -5
    EPILOGUE

FN tt_unmap
    cmp qword ptr [rip + tt_unmap_fault], 0
    je 1f
    inc qword ptr [rip + tt_unmap_calls]
    mov [rip + tt_failed_map], rdi
    mov rax, [rdi]
    mov [rip + tt_failed_header], rax
    mov rax, [rdi + 8]
    mov [rip + tt_failed_header + 8], rax
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
