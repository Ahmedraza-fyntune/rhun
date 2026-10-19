# Typed runtime table construction and owned partial-result handling.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.bss
.p2align 3
.globl g_activeRT, g_closingRT
g_activeRT: .quad 0
g_closingRT: .quad 0
.globl rt_last_session, rt_last_accept, rt_last_prompt_generation
rt_last_session: .quad 0
rt_last_accept: .quad 0
rt_last_prompt_generation: .quad 0
.text
# Owned native pointer only. Validate the creation allocation before role fields.
# AX boolean, preserves RDI. No readiness or action authority implied.
FN rt_table_is_owned
    mov esi, RT_KIND
rt_table_owned_kind:
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
    cmp qword ptr [rdi - AO_SIZE + AO_charge], RT_TABLE_SIZE + RD_PO_BACK + 16
    jb 9f
    cmp qword ptr [rdi - AO_SIZE + AO_charge], PREP_CAP
    ja 9f
    cmp qword ptr [rdi + RT_role], RT_TABLE_ROLE
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
    mov eax, 1
9:  ret

# rt_table_create(out32)->0, or EINVAL leaving output unchanged.
# NonNULL failed PO and unconsumed standalone EO are separately owned result fields.
FN rt_table_create
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lrtc_invalid
    mov rax, rbx
    add rax, RTC_SIZE
    jc .Lrtc_invalid
    mov rax, [rbx]
    or rax, [rbx + 8]
    or rax, [rbx + 16]
    or rax, [rbx + 24]
    jnz .Lrtc_invalid
    mov edi, RT_KIND
    lea rsi, [rip + rt_retire_one]
    mov edx, 1
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Lrtc_primary
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lrtc_owner_failed
    mov r12, rax
    mov [rbx + RTC_orphanEO], rax
    mov qword ptr [r12 + EO_deferred], 1
    mov rdi, r12
    mov esi, RT_TABLE_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrtc_po_failed
    mov r13, rax
    mov [rbx + RTC_owner], rax
    mov qword ptr [r13 + RT_role], RT_TABLE_ROLE
    mov qword ptr [r13 + RT_flags], RTF_BUILDING | RTF_CLOSED
    mov qword ptr [r13 + RT_mutation], 1
    mov rdi, r13
    mov esi, RT_KIND
    call ext_prepare_retire_mark_custom_po
    test rax, rax
    jns .Lrtc_drop_initial
    mov [rbx + RTC_primary], rax
    jmp .Lrtc_drop_initial
.Lrtc_po_failed:
    mov [rbx + RTC_primary], rdx
.Lrtc_drop_initial:
    mov rdi, r12
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne 1f
    mov qword ptr [rbx + RTC_orphanEO], 0
1:  test rax, rax
    jns .Lrtc_done
    mov [rbx + RTC_cleanup], rax
.Lrtc_done:
    xor eax, eax
    EPILOGUE
.Lrtc_owner_failed:
    mov rax, rdx
.Lrtc_primary:
    mov [rbx + RTC_primary], rax
    xor eax, eax
    EPILOGUE
.Lrtc_invalid:
    mov rax, -22
    EPILOGUE

FN rt_table_retain
    PROLOGUE
    call rt_table_is_owned
    test eax, eax
    jz 1f
    call prep_object_retain
    EPILOGUE
1:  mov rax, -22
    EPILOGUE

# Bounded initialization of the free-row chain; one allocation ends a call.
# table,budget1..16 ->0 pending/1 ready/-errno, DX units consumed.
# Each row unit initializes at most16 records, with no source/native borrow.
FN rt_table_init_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    dec rsi
    cmp rsi, 15
    ja .Lrti_invalid
    call rt_table_is_owned
    test eax, eax
    jz .Lrti_invalid
    cmp qword ptr [rbx + PO_ready], 1
    je .Lrti_ready
    cmp qword ptr [rbx + PO_refs], 1
    jne .Lrti_invalid
    cmp qword ptr [rbx + PO_error], 0
    jne .Lrti_sticky
    cmp qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_CLOSED
    jne .Lrti_invalid
    cmp qword ptr [rbx + RT_sourceCopyCursor], 0
    je .Lrti_cursor
    cmp qword ptr [rbx + RT_publicationRecord], 0
    je .Lrti_record
    cmp qword ptr [rbx + RT_scratch], 0
    je .Lrti_scratch
    cmp qword ptr [rbx + RT_discardBuffer], 0
    je .Lrti_discard
    mov r13, [rbx + RT_initCursor]
    cmp r13, RT_ROW_COUNT
    ja .Lrti_invalid
    xor r14d, r14d
.Lrti_unit:
    cmp r13, RT_ROW_COUNT
    jae .Lrti_finish
    mov r15d, 16
1:  cmp r13, RT_ROW_COUNT
    jae .Lrti_finish
    imul rax, r13, RT_ROW_SIZE
    lea rdx, [rbx + rax + RT_rows]
    lea rax, [r13 + 2]
    cmp r13, RT_ROW_COUNT - 1
    jne 2f
    xor eax, eax
2:  mov [rdx + RTR_next], rax
    inc r13
    mov [rbx + RT_initCursor], r13
    dec r15
    jnz 1b
    inc r14
    cmp r14, r12
    jb .Lrti_unit
    xor eax, eax
    mov rdx, r14
    EPILOGUE
.Lrti_finish:
    mov qword ptr [rbx + RT_freeHead], 1
    mov qword ptr [rbx + RT_flags], RTF_CLOSED
    mov qword ptr [rbx + PO_ready], 1
    mov eax, 1
    mov rdx, r14
    EPILOGUE
.Lrti_cursor:
    mov r13d, RT_sourceCopyCursor
    mov esi, 64
    jmp .Lrti_allocate
.Lrti_record:
    mov r13d, RT_publicationRecord
    mov esi, 4096
    jmp .Lrti_allocate
.Lrti_scratch:
    mov r13d, RT_scratch
    mov esi, 64
    jmp .Lrti_allocate
.Lrti_discard:
    mov r13d, RT_discardBuffer
    mov esi, 65536
.Lrti_allocate:
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lrti_sticky
    mov [rbx + r13], rax
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lrti_ready:
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrti_sticky:
    mov rax, [rbx + PO_error]
    test rax, rax
    js 3f
    mov rax, -5
3:  xor edx, edx
    EPILOGUE
.Lrti_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# A completed or failed table can be closed without transferring any references.
# Every slot loses its action grant before later native maintenance can run.
FN rt_table_close
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Lrt_close_bad
    mov rdi, rbx
    call rt_table_revoke_all_pure
    xor eax, eax
    EPILOGUE
.Lrt_close_bad:
    mov rax, -22
    EPILOGUE

# Prechecked held TABLE. No rejecting checks, ref drops, allocations or callbacks.
FN rt_table_revoke_all_pure
    PROLOGUE
    mov rbx, rdi
    mov r14, [rbx + RT_flags]
    and r14d, RTF_CLOSED
    or qword ptr [rbx + RT_flags], RTF_CLOSED
    call rt_prompt_revoke_all_pure
    xor r12d, r12d
1:  imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    mov qword ptr [r13 + RTS_grantSession], 0
    cmp qword ptr [r13 + RTS_state], RTS_ACTIVE
    jne 2f
    mov qword ptr [r13 + RTS_state], RTS_DRAINING
    or qword ptr [r13 + RTS_flags], RTSF_STOP_REQUIRED | RTSF_PARSER_PAUSED
2:  inc r12
    cmp r12, RT_SLOT_COUNT
    jb 1b
    test r14, r14
    jnz 3f
    call rt_authority_invalidate_pure
3:  EPILOGUE

# Pure final native-ownership proof, independent of the TABLE reference count.
# Memory CG/KSI/ledger references may remain. No action or START grant is returned.
FN rt_table_native_quiet_check
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Lrtq_bad
    test qword ptr [rbx + RT_flags], RTF_CLOSED
    jz .Lrtq_busy
    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    ja .Lrtq_bad
    # Reject a replaced historical base before any EXT read, even for shared readers.
    cmp qword ptr [rbx + RT_stableExtCount], 0
    je .Lrtq_base_checked
    test qword ptr [rbx + RT_flags], RTF_MEMORY_ONLY
    jnz .Lrtq_bad
    mov rax, [rbx + RT_stableExtBase]
    test rax, rax
    jz .Lrtq_bad
    cmp [rip + g_exts + VEC_ptr], rax
    jne .Lrtq_busy
    mov rcx, [rip + g_exts + VEC_cap]
    cmp rcx, [rbx + RT_stableExtCount]
    jb .Lrtq_busy
.Lrtq_base_checked:
    mov rax, [rbx + RT_nlive]
    or rax, [rbx + RT_nreserved]
    or rax, [rbx + RT_npending]
    or rax, [rbx + RT_liveHead]
    or rax, [rbx + RT_liveTail]
    or rax, [rbx + RT_debtHead]
    or rax, [rbx + RT_promptActive]
    or rax, [rbx + RT_promptWire]
    or rax, [rbx + RT_promptRetired]
    jnz .Lrtq_busy
    mov rax, [rbx + RT_sourceCopyCursor]
    test rax, rax
    jz 1f
    # A reset copy cursor has no KSI/CG source or destination borrow.
    mov rcx, [rax]
    or rcx, [rax + 8]
    jnz .Lrtq_busy
1:  xor r12d, r12d
.Lrtq_slot:
    imul rax, r12, RT_SLOT_SIZE
    lea r13, [rbx + rax + RT_slots]
    mov rax, [r13 + RTS_ea]
    or rax, [r13 + RTS_state]
    or rax, [r13 + RTS_nlive]
    or rax, [r13 + RTS_ticket]
    or rax, [r13 + RTS_flags]
    or rax, [r13 + RTS_replyID]
    or rax, [r13 + RTS_orphanEO]
    or rax, [r13 + RTS_failedPO]
    or rax, [r13 + RTS_liveHead]
    or rax, [r13 + RTS_ndebt]
    or rax, [r13 + RTS_nreserved]
    or rax, [r13 + RTS_promptID]
    or rax, [r13 + RTS_hi]
    or rax, [r13 + RTS_grantSession]
    jnz .Lrtq_busy
    imul rax, r12, RT_DISCARD_SIZE
    cmp qword ptr [rbx + rax + RT_discards + RTD_state], 0
    jne .Lrtq_busy
    cmp r12, [rbx + RT_stableExtCount]
    jae .Lrtq_next
    mov r13, [rbx + RT_stableExtBase]
    test r13, r13
    jz .Lrtq_bad
    imul rax, r12, EXT_SIZE
    add r13, rax
    mov rdi, r13
    call ext_host_native_quiet
    test rax, rax
    jnz .Lrtq_done
    mov eax, [r13 + EXT_start_armed]
    or eax, [r13 + EXT_wait_slot]
    or eax, [r13 + EXT_restart]
    jnz .Lrtq_busy
    mov rax, [r13 + EXT_body]
    or rax, [r13 + EXT_rbuf + SB_len]
    or rax, [r13 + EXT_wq + SB_len]
    or rax, [r13 + EXT_wq_off]
    jnz .Lrtq_busy
.Lrtq_next:
    inc r12
    cmp r12, RT_SLOT_COUNT
    jb .Lrtq_slot
    xor eax, eax
.Lrtq_done:
    EPILOGUE
.Lrtq_bad:
    mov rax, -22
    EPILOGUE
.Lrtq_busy:
    mov rax, -16
    EPILOGUE

# Root closing reference is retained until actual native quiet, even with shared refs.
FN rt_closing_finish
    PROLOGUE
    mov rbx, [rip + g_closingRT]
    test rbx, rbx
    jz .Lrtf_ok
    cmp qword ptr [rip + g_activeRT], 0
    jne .Lrtf_busy
    mov rdi, rbx
    call rt_table_native_quiet_check
    test rax, rax
    jnz .Lrtf_refused
    or qword ptr [rbx + RT_flags], RTF_MEMORY_ONLY
    mov qword ptr [rbx + RT_stableExtBase], 0
    mov qword ptr [rbx + RT_stableExtCount], 0
    mov qword ptr [rbx + RT_capturedActiveCG], 0
    mov rdi, rbx
    call rt_table_release
    cmp rdx, 1
    jne .Lrtf_done
    mov qword ptr [rip + g_closingRT], 0
.Lrtf_done:
    EPILOGUE
.Lrtf_busy:
    mov rax, -16
.Lrtf_refused:
    xor edx, edx
    EPILOGUE
.Lrtf_ok:
    xor eax, eax
    mov edx, 1
    EPILOGUE

# Shared drops never authorize clearing a root closing owner. Last drop needs memory-only
# or a partial BUILDING owner which has never captured any native session.
FN rt_table_release
    test rdi, rdi
    jz .Lrtr_empty
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    je .Lrtr_generic
    call rt_table_is_owned
    test eax, eax
    jz .Lrtr_bad
    cmp qword ptr [rbx + PO_refs], 1
    ja .Lrtr_drop
    test qword ptr [rbx + RT_flags], RTF_MEMORY_ONLY
    jnz .Lrtr_drop
    cmp qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_CLOSED
    jne .Lrtr_busy
    mov rdi, rbx
    call rt_table_native_quiet_check
    test rax, rax
    jnz .Lrtr_refused
.Lrtr_drop:
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    EPILOGUE
.Lrtr_generic:
    # Only failed-before-mark constructor output can use the generic path.
    mov esi, RD_LEDGER
    call rt_table_owned_kind
    test eax, eax
    jz .Lrtr_bad
    cmp qword ptr [rbx - AO_SIZE + AO_charge], RT_TABLE_SIZE + RD_PO_BACK + 16
    jb .Lrtr_bad
    cmp qword ptr [rbx + PO_ready], 0
    jne .Lrtr_bad
    cmp qword ptr [rbx + RT_role], RT_TABLE_ROLE
    jne .Lrtr_bad
    cmp qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_CLOSED
    jne .Lrtr_bad
    cmp qword ptr [rbx + RT_initCursor], 0
    jne .Lrtr_bad
    mov rax, [rbx + RT_sourceCopyCursor]
    or rax, [rbx + RT_publicationRecord]
    or rax, [rbx + RT_scratch]
    or rax, [rbx + RT_discardBuffer]
    or rax, [rbx + RT_stableExtBase]
    or rax, [rbx + RT_stableExtCount]
    jnz .Lrtr_bad
    mov rdi, rbx
    call prep_object_release_deferred
    EPILOGUE
.Lrtr_bad:
    mov rax, -22
    jmp .Lrtr_refused
.Lrtr_busy:
    mov rax, -16
.Lrtr_refused:
    xor edx, edx
    EPILOGUE
.Lrtr_empty:
    xor eax, eax
    mov edx, 1
    ret

# The common scheduler calls with PO_refs=0/ready=0 and RD_RUNNING.
# Do not reuse the active guard here. One supplier or phase is processed per call.
FN rt_retire_one
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rax, [rdi - RD_PO_BACK]
    cmp rax, rsi
    jne .Lrtd_bad
    cmp [r12 + RD_object], rbx
    jne .Lrtd_bad
    cmp qword ptr [r12 + RD_kind], RT_KIND
    jne .Lrtd_bad
    mov rax, [r12 + RD_state]
    test eax, RDF_PO
    jz .Lrtd_bad
    and eax, RDF_STATE_MASK
    cmp eax, RD_RUNNING
    jne .Lrtd_bad
    cmp qword ptr [rbx + PO_refs], 0
    jne .Lrtd_bad
    cmp qword ptr [rbx + PO_ready], 0
    jne .Lrtd_bad
    cmp qword ptr [rbx - AO_SIZE + AO_charge], RTT_HEADER_SIZE + RD_PO_BACK + 16
    jb .Lrtd_bad
    cmp qword ptr [rbx + RT_role], RT_TICKET_ROLE
    je .Lrtd_ticket
    cmp qword ptr [rbx - AO_SIZE + AO_charge], RT_TABLE_SIZE + RD_PO_BACK + 16
    jb .Lrtd_bad
    cmp qword ptr [rbx + RT_role], RT_TABLE_ROLE
    jne .Lrtd_bad
    mov qword ptr [rbx + RT_capturedActiveCG], 0
    mov r13, [r12 + RD_index]
    cmp r13, 8
    ja .Lrtd_bad
    je .Lrtd_handoff
    lea rax, [rip + rt_table_retire_fields]
    mov r14, [rax + r13*8]
    add r14, rbx
    mov rdi, [r14]
    test rdi, rdi
    jz .Lrtd_advance
    cmp r13, 5
    jae .Lrtd_non_cg
    call command_generation_release_deferred
    jmp .Lrtd_result
.Lrtd_non_cg:
    cmp r13, 7
    je .Lrtd_eo
    call prep_object_release_deferred
    jmp .Lrtd_result
.Lrtd_eo:
    call ext_prepare_owner_release_deferred
.Lrtd_result:
    cmp rdx, 1
    jne .Lrtd_blocked
    mov qword ptr [r14], 0
    test rax, rax
    jns .Lrtd_advance
    mov rdi, r12
    mov rsi, rax
    call ext_prepare_retire_note_error
.Lrtd_advance:
    inc qword ptr [r12 + RD_index]
    mov eax, 1
    EPILOGUE
.Lrtd_handoff:
    mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    js .Lrtd_blocked
    mov eax, 1
    EPILOGUE
 .Lrtd_ticket:
    mov rdi, rbx
    mov rsi, r12
    call rt_ticket_retire_fields
    EPILOGUE
.Lrtd_bad:
    mov rax, -22
.Lrtd_blocked:
    test rax, rax
    js 1f
    mov rax, -5
1:  xor edx, edx
    EPILOGUE
.section .rodata
.p2align 3
rt_table_retire_fields:
    .quad RT_serviceCG, RT_baseCG, RT_retiredActiveCG, RT_retiredBaseCG, RT_abortedCG
    .quad RT_heldKSI, RT_retiredKSI, RT_builderEO
