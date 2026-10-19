# Owned reconstruction of an already validated immutable counted GP image.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.include "app/extdiscoveryalloc.inc"
.include "app/extdiscoverygpxfer.inc"
.if GP_SIZE + RD_SIZE + AO_SIZE + 16 > 4096
.error "GP constructor exceeds transfer bound"
.endif
.text
# Local trusted owner snapshot. No serialized bytes or GP payload are read.
# ctx -> 0 or -ESTALE. Also used before BEGIN stores via a temporary register set.
FN pg_import_binding_check
    mov r8, [rdi + PGI_token]
    cmp qword ptr [r8 + 8], 1
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_generation]
    cmp [r8], rax
    jne .Lpi_stale_leaf
    mov r8, [rdi + PGI_gpc]
    cmp qword ptr [r8 + GPC_state], GPC_VALID
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_wire]
    cmp [r8 + GPC_wire], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_length]
    cmp [r8 + GPC_length], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_mode]
    cmp [r8 + GPC_mode], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_ordinal]
    cmp [r8 + GPC_source], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_sourcebytes]
    cmp [r8 + GPC_sourcebytes], rax
    jne .Lpi_stale_leaf
    mov r8, [rdi + PGI_dia]
    cmp qword ptr [r8 + DIA_state], DIA_ACTIVE
    jne .Lpi_stale_leaf
    mov rax, [r8 + DIA_primary]
    or rax, [r8 + DIA_cleanup]
    or rax, [r8 + DIA_blocked]
    jnz .Lpi_stale_leaf
    mov r9, [rdi + PGI_eo]
    cmp [r8 + DIA_eo], r9
    jne .Lpi_stale_leaf
    mov r10, [rdi + PGI_ep]
    cmp [r8 + DIA_ep], r10
    jne .Lpi_stale_leaf
    cmp qword ptr [r9 + EO_deferred], 1
    jne .Lpi_stale_leaf
    cmp qword ptr [r9 + EO_error], 0
    jne .Lpi_stale_leaf
    cmp qword ptr [r9 + EO_refs], 0
    jle .Lpi_stale_leaf
    cmp qword ptr [r10 + PO_ready], 0
    jne .Lpi_stale_leaf
    cmp qword ptr [r10 + PO_error], 0
    jne .Lpi_stale_leaf
    cmp qword ptr [r10 + PO_refs], 0
    jle .Lpi_stale_leaf
    cmp [r10 + PO_eo], r9
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_grammarptr]
    cmp [r8 + DIA_grammars], rax
    jne .Lpi_stale_leaf
    cmp [r10 + EP_grammars + VEC_ptr], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_grammarlen]
    cmp [r10 + EP_grammars + VEC_len], rax
    jne .Lpi_stale_leaf
    mov rax, [rdi + PGI_grammarcap]
    cmp [r8 + DIA_grammars_cap], rax
    jne .Lpi_stale_leaf
    cmp [r10 + EP_grammars + VEC_cap], rax
    jne .Lpi_stale_leaf
    xor eax, eax
    cmp qword ptr [rdi + PGI_phase], PGI_INIT
    je 1f
    mov rax, [rdi + PGI_gp]
1:  cmp [r8 + DIA_gp], rax
    jne .Lpi_stale_leaf
    xor eax, eax
    ret
.Lpi_stale_leaf:
    mov rax, -116
    ret

FN pg_import_begin
    test rdi, rdi
    jz .Lpi_api
    test rsi, rsi
    jz .Lpi_api
    cmp qword ptr [rdi + PGI_state], PGI_FAILED
    ja .Lpi_api
    cmp qword ptr [rdi + PGI_state], PGI_NEW
    jne .Lpi_busy
    mov r8, [rsi]
    mov r9, [rsi + 8]
    mov r10, [rsi + 16]
    mov r11, [rsi + 24]
    test r8, r8
    jz .Lpi_api
    test r9, r9
    jz .Lpi_api
    test r10, r10
    jz .Lpi_api
    test r11, r11
    jz .Lpi_api
    mov rax, [rsi + 32]
    or rax, [rsi + 40]
    jnz .Lpi_api
    cmp qword ptr [r10 + 8], 1
    jne .Lpi_api
    cmp [r10], r11
    jne .Lpi_api
    cmp qword ptr [r9 + GPC_state], GPC_VALID
    jne .Lpi_api
    cmp qword ptr [r8 + DIA_state], DIA_ACTIVE
    jne .Lpi_api
    mov rax, [r8 + DIA_primary]
    or rax, [r8 + DIA_cleanup]
    or rax, [r8 + DIA_gp]
    or rax, [r8 + DIA_blocked]
    jnz .Lpi_api
    mov rcx, [r8 + DIA_eo]
    test rcx, rcx
    jz .Lpi_api
    cmp qword ptr [rcx + EO_deferred], 1
    jne .Lpi_api
    cmp qword ptr [rcx + EO_error], 0
    jne .Lpi_api
    cmp qword ptr [rcx + EO_refs], 0
    jle .Lpi_api
    mov rdx, [r8 + DIA_ep]
    test rdx, rdx
    jz .Lpi_api
    cmp qword ptr [rdx + PO_ready], 0
    jne .Lpi_api
    cmp qword ptr [rdx + PO_error], 0
    jne .Lpi_api
    cmp qword ptr [rdx + PO_refs], 0
    jle .Lpi_api
    cmp [rdx + PO_eo], rcx
    jne .Lpi_api
    mov rax, [r8 + DIA_grammars]
    test rax, rax
    jz .Lpi_api
    cmp [rdx + EP_grammars + VEC_ptr], rax
    jne .Lpi_api
    mov rax, [rdx + EP_grammars + VEC_len]
    cmp rax, [r8 + DIA_grammars_cap]
    jae .Lpi_api
    mov rax, [r8 + DIA_grammars_cap]
    cmp [rdx + EP_grammars + VEC_cap], rax
    jne .Lpi_api
    # Exactly sixteen successful native stores. No input/header/context clear.
    mov [rdi + PGI_dia], r8
    mov [rdi + PGI_gpc], r9
    mov [rdi + PGI_token], r10
    mov [rdi + PGI_generation], r11
    mov [rdi + PGI_eo], rcx
    mov [rdi + PGI_ep], rdx
    mov rax, [r9 + GPC_wire]
    mov [rdi + PGI_wire], rax
    mov rax, [r9 + GPC_length]
    mov [rdi + PGI_length], rax
    mov rax, [r9 + GPC_mode]
    mov [rdi + PGI_mode], rax
    mov rax, [r9 + GPC_source]
    mov [rdi + PGI_ordinal], rax
    mov rax, [r9 + GPC_sourcebytes]
    mov [rdi + PGI_sourcebytes], rax
    mov rax, [r8 + DIA_grammars]
    mov [rdi + PGI_grammarptr], rax
    mov rax, [rdx + EP_grammars + VEC_len]
    mov [rdi + PGI_grammarlen], rax
    mov rax, [r8 + DIA_grammars_cap]
    mov [rdi + PGI_grammarcap], rax
    mov qword ptr [rdi + PGI_phase], PGI_INIT
    mov qword ptr [rdi + PGI_state], PGI_WORK
    xor eax, eax
    ret

# ctx,primary -> sticky first failure and one bounded DIA abort.
FN pg_import_fail
    cmp qword ptr [rdi + PGI_state], PGI_WORK
    jne 2f
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + PGI_phase], PGI_INIT
    jne 1f
    mov qword ptr [rbx + PGI_work], 0
    mov qword ptr [rbx + PGI_units], 0
    mov qword ptr [rbx + PGI_cursor], 0
    mov qword ptr [rbx + PGI_wordindex], 0
1:  mov [rbx + PGI_error], r12
    mov qword ptr [rbx + PGI_state], PGI_FAILED
    mov rdi, [rbx + PGI_dia]
    mov rsi, r12
    call pd_alloc_abort
    mov rax, r12
    EPILOGUE
2:  mov rax, [rdi + PGI_error]
    ret

FN pg_import_cancel
    test rdi, rdi
    jz .Lpi_api
    mov rax, [rdi + PGI_state]
    test rax, rax
    jz .Lpi_api
    cmp rax, PGI_FAILED
    ja .Lpi_api
    cmp rax, PGI_DONE
    je .Lpi_busy
    cmp rax, PGI_FAILED
    je 1f
    PROLOGUE
    mov rsi, -125
    call pg_import_fail
    xor eax, eax
    EPILOGUE
1:  xor eax, eax
    ret

FN pg_import_clear
    test rdi, rdi
    jz .Lpi_api
    mov rax, [rdi + PGI_state]
    test rax, rax
    jz .Lpi_zero
    cmp rax, PGI_FAILED
    ja .Lpi_api
    cmp rax, PGI_WORK
    je .Lpi_busy
    cmp rax, PGI_DONE
    je 1f
    mov rax, [rdi + PGI_dia]
    cmp qword ptr [rax + DIA_state], DIA_EMPTY
    jne .Lpi_busy
1:  mov qword ptr [rdi + PGI_dia], 0
    mov qword ptr [rdi + PGI_gpc], 0
    mov qword ptr [rdi + PGI_wire], 0
    mov qword ptr [rdi + PGI_token], 0
    mov qword ptr [rdi + PGI_gp], 0
    mov qword ptr [rdi + PGI_member], 0
    mov qword ptr [rdi + PGI_eo], 0
    mov qword ptr [rdi + PGI_ep], 0
    mov qword ptr [rdi + PGI_grammarptr], 0
    mov qword ptr [rdi + PGI_state], PGI_NEW
.Lpi_zero:
    xor eax, eax
    ret
.Lpi_api:
    mov rax, -22
    ret
.Lpi_busy:
    mov rax, -16
    ret

FN pg_import_status
    test rdi, rdi
    jz .Lpi_api
    test rsi, rsi
    jz .Lpi_api
    mov rax, [rdi + PGI_state]
    test rax, rax
    jz .Lpi_api
    cmp rax, PGI_FAILED
    ja .Lpi_api
    mov [rsi], rax
    mov rdx, [rdi + PGI_phase]
    mov [rsi + 16], rdx
    mov rcx, [rdi + PGI_ordinal]
    mov [rsi + 40], rcx
    cmp rax, PGI_WORK
    jne 1f
    test rdx, rdx
    jnz 1f
    mov qword ptr [rsi + 8], 0
    mov qword ptr [rsi + 24], 0
    mov qword ptr [rsi + 32], 0
    mov qword ptr [rsi + 48], 0
    mov qword ptr [rsi + 56], 0
    xor eax, eax
    ret
1:  mov rax, [rdi + PGI_error]
    mov [rsi + 8], rax
    mov rax, [rdi + PGI_work]
    mov [rsi + 24], rax
    mov rax, [rdi + PGI_units]
    mov [rsi + 32], rax
    mov rax, [rdi + PGI_cursor]
    mov [rsi + 48], rax
    mov rax, [rdi + PGI_wordindex]
    mov [rsi + 56], rax
    xor eax, eax
    ret

# INIT does not follow payload or allocate. Every progress field becomes defined.
FN pg_import_init_step
    mov qword ptr [rdi + PGI_error], 0
    mov qword ptr [rdi + PGI_gp], 0
    mov qword ptr [rdi + PGI_member], 0
    mov qword ptr [rdi + PGI_gpslot], -1
    mov qword ptr [rdi + PGI_memberslot], -1
    mov qword ptr [rdi + PGI_cursor], 0
    mov qword ptr [rdi + PGI_wordindex], 0
    mov qword ptr [rdi + PGI_byteindex], 0
    mov qword ptr [rdi + PGI_scalar], 0
    mov qword ptr [rdi + PGI_recordstage], 0
    mov qword ptr [rdi + PGI_nativefield], 0
    mov qword ptr [rdi + PGI_phase], PGI_CACHE
    mov qword ptr [rdi + PGI_units], 12
    mov eax, 1
    ret

# Fixed native GPC caches, not a second wire decoder. At most16 fields percall.
FN pg_import_cache_step
    mov r8, [rdi + PGI_gpc]
    lea r9, [rip + pg_import_cache_fields]
1:  cmp qword ptr [rdi + PGI_units], 16
    jae 3f
    mov rax, [rdi + PGI_nativefield]
    cmp rax, 25
    jae 2f
    shl rax, 4
    mov rcx, [r9 + rax]
    mov rdx, [r9 + rax + 8]
    mov rcx, [r8 + rcx]
    mov [rdi + rdx], rcx
    inc qword ptr [rdi + PGI_nativefield]
    inc qword ptr [rdi + PGI_units]
    jmp 1b
2:  mov qword ptr [rdi + PGI_phase], PGI_ACQUIRE_GP
    inc qword ptr [rdi + PGI_units]
3:  mov eax, 1
    ret

FN pg_import_acquire_step
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + PGI_dia]
    mov esi, PD_GP
    mov edx, GP_SIZE
    cmp qword ptr [rbx + PGI_phase], PGI_ACQUIRE_GP
    je 1f
    mov esi, PD_MEMBER
    mov rdx, [rbx + PGI_length]
1:  call pd_alloc_begin
    test rax, rax
    js .Lpi_helper_error
    mov rdi, [rbx + PGI_dia]
    mov rsi, rax
    cmp qword ptr [rbx + PGI_phase], PGI_ACQUIRE_GP
    jne 2f
    mov [rbx + PGI_gpslot], rax
    call pd_alloc_slot
    test rax, rax
    js .Lpi_helper_error
    cmp qword ptr [rax + DTS_charge], 4096
    ja .Lpi_helper_resource
    mov qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    jmp .Lpi_helper_pending
2:  mov [rbx + PGI_memberslot], rax
    mov qword ptr [rbx + PGI_phase], PGI_ZERO_AO
    jmp .Lpi_helper_pending

FN pg_import_zero_step
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + PGI_dia]
    mov rsi, [rbx + PGI_gpslot]
    cmp qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    je 1f
    mov rsi, [rbx + PGI_memberslot]
1:  call pd_alloc_slot
    test rax, rax
    js .Lpi_helper_error
    mov r12, [rax + DTS_request]
    cmp qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    je 2f
    mov r12d, AO_SIZE
2:  sub r12, [rax + DTS_initialized]
    jbe .Lpi_helper_invalid
    cmp r12, [rbx + PGI_budget]
    cmova r12, [rbx + PGI_budget]
    mov rdi, [rbx + PGI_dia]
    mov rsi, [rbx + PGI_gpslot]
    cmp qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    je 3f
    mov rsi, [rbx + PGI_memberslot]
3:  mov rdx, r12
    call pd_alloc_zero
    test rax, rax
    js .Lpi_helper_error
    cmp rax, r12
    jne .Lpi_helper_invalid
    add [rbx + PGI_work], rax
    sub [rbx + PGI_budget], rax
    mov rdi, [rbx + PGI_dia]
    mov rsi, [rbx + PGI_gpslot]
    cmp qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    je 4f
    mov rsi, [rbx + PGI_memberslot]
4:  call pd_alloc_slot
    test rax, rax
    js .Lpi_helper_error
    mov rcx, [rax + DTS_request]
    cmp qword ptr [rbx + PGI_phase], PGI_ZERO_GP
    je 5f
    mov ecx, AO_SIZE
5:  cmp [rax + DTS_initialized], rcx
    jb .Lpi_helper_pending
    inc qword ptr [rbx + PGI_phase]
    jmp .Lpi_helper_pending

FN pg_import_enroll_step
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + PGI_dia]
    mov rsi, [rbx + PGI_gpslot]
    cmp qword ptr [rbx + PGI_phase], PGI_ENROLL_GP
    jne 1f
    call pd_alloc_enroll_gp
    test rax, rax
    jz .Lpi_helper_diagnostic
    mov [rbx + PGI_gp], rax
    mov qword ptr [rbx + PGI_gpslot], -1
    mov qword ptr [rbx + PGI_phase], PGI_ACQUIRE_BLOB
    jmp .Lpi_helper_pending
1:  mov rsi, [rbx + PGI_memberslot]
    mov edx, 2
    call pd_alloc_enroll_member
    test rax, rax
    jz .Lpi_helper_diagnostic
    mov [rbx + PGI_member], rax
    mov qword ptr [rbx + PGI_memberslot], -1
    mov qword ptr [rbx + PGI_cursor], 0
    mov qword ptr [rbx + PGI_nativefield], 0
    mov qword ptr [rbx + PGI_phase], PGI_FIELDS
    jmp .Lpi_helper_pending

FN pg_import_copy_step
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + PGI_length]
    sub r12, [rbx + PGI_cursor]
    jbe .Lpi_helper_invalid
    mov rax, [rbx + PGI_budget]
    shr rax, 1
    cmp r12, rax
    cmova r12, rax
    mov rdi, [rbx + PGI_dia]
    mov rsi, [rbx + PGI_memberslot]
    mov rdx, [rbx + PGI_wire]
    add rdx, [rbx + PGI_cursor]
    mov rcx, r12
    call pd_alloc_copy
    test rax, rax
    js .Lpi_helper_error
    cmp rax, r12
    jne .Lpi_helper_invalid
    add [rbx + PGI_cursor], rax
    shl rax, 1
    add [rbx + PGI_work], rax
    sub [rbx + PGI_budget], rax
    mov rax, [rbx + PGI_cursor]
    cmp rax, [rbx + PGI_length]
    jb .Lpi_helper_pending
    mov qword ptr [rbx + PGI_phase], PGI_ENROLL_BLOB
.Lpi_helper_pending:
    inc qword ptr [rbx + PGI_units]
    mov eax, 1
    EPILOGUE
.Lpi_helper_resource:
    mov rax, -EV_RESOURCE
    jmp .Lpi_helper_error
.Lpi_helper_invalid:
    mov rax, -EV_BAD_PREPARE
    jmp .Lpi_helper_error
.Lpi_helper_diagnostic:
    mov rax, rdx
.Lpi_helper_error:
    mov rdi, rbx
    mov rsi, rax
    call pg_import_fail
    EPILOGUE

FN pg_import_step
    test rdi, rdi
    jz .Lpi_step_api
    lea rax, [rsi - 2]
    cmp rax, 65534
    ja .Lpi_step_api
    mov rax, [rdi + PGI_state]
    test rax, rax
    jz .Lpi_step_api
    cmp rax, PGI_FAILED
    ja .Lpi_step_api
    cmp rax, PGI_DONE
    je .Lpi_step_done
    cmp rax, PGI_FAILED
    je .Lpi_step_failed
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov [rbx + PGI_budget], rsi
    mov qword ptr [rbx + PGI_work], 0
    mov qword ptr [rbx + PGI_units], 0
    call pg_import_binding_check
    test rax, rax
    js .Lpi_step_error
    mov rdi, rbx
    mov rax, [rbx + PGI_phase]
    cmp rax, PGI_INIT
    je .Lpi_step_init
    cmp rax, PGI_CACHE
    je .Lpi_step_cache
    cmp rax, PGI_ACQUIRE_GP
    je .Lpi_step_acquire
    cmp rax, PGI_ACQUIRE_BLOB
    je .Lpi_step_acquire
    cmp rax, PGI_ZERO_GP
    je .Lpi_step_zero
    cmp rax, PGI_ZERO_AO
    je .Lpi_step_zero
    cmp rax, PGI_ENROLL_GP
    je .Lpi_step_enroll
    cmp rax, PGI_ENROLL_BLOB
    je .Lpi_step_enroll
    cmp rax, PGI_COPY_BLOB
    je .Lpi_step_copy
    cmp rax, PGI_FIELDS
    je .Lpi_step_fields
    cmp rax, PGI_WORD_RELOC
    je .Lpi_step_words
    cmp rax, PGI_ARRAYS
    je .Lpi_step_arrays
    cmp rax, PGI_FINAL
    je .Lpi_step_final
    mov rax, -EV_BAD_PREPARE
    jmp .Lpi_step_error
.Lpi_step_init:
    call pg_import_init_step
    jmp .Lpi_step_checked
.Lpi_step_cache:
    call pg_import_cache_step
    jmp .Lpi_step_checked
.Lpi_step_acquire:
    call pg_import_acquire_step
    jmp .Lpi_step_checked
.Lpi_step_zero:
    call pg_import_zero_step
    jmp .Lpi_step_checked
.Lpi_step_enroll:
    call pg_import_enroll_step
    jmp .Lpi_step_checked
.Lpi_step_copy:
    call pg_import_copy_step
    jmp .Lpi_step_checked
.Lpi_step_fields:
    call pg_import_fields_step
    jmp .Lpi_step_checked
.Lpi_step_words:
    call pg_import_words_step
    jmp .Lpi_step_checked
.Lpi_step_arrays:
    call pg_import_arrays_step
    jmp .Lpi_step_checked
.Lpi_step_final:
    call pg_import_final_step
    jmp .Lpi_step_result
.Lpi_step_checked:
    cmp [rbx + PGI_work], r12
    ja .Lpi_step_overrun
    cmp qword ptr [rbx + PGI_units], 16
    ja .Lpi_step_overrun
.Lpi_step_result:
    mov rdx, [rbx + PGI_work]
    mov rcx, [rbx + PGI_units]
    EPILOGUE
.Lpi_step_overrun:
    mov rax, -EV_BAD_PREPARE
.Lpi_step_error:
    mov rdi, rbx
    mov rsi, rax
    call pg_import_fail
    jmp .Lpi_step_result
.Lpi_step_failed:
    mov rax, [rdi + PGI_error]
    jmp .Lpi_step_nowork
.Lpi_step_api:
    mov rax, -22
    jmp .Lpi_step_nowork
.Lpi_step_done:
    xor eax, eax
.Lpi_step_nowork:
    xor edx, edx
    xor ecx, ecx
    ret

.section .rodata
.p2align 3
pg_import_cache_fields:
    .quad GPC_mode, PGI_info
    .quad GPC_source, PGI_info + 8
    .quad GPC_length, PGI_info + 16
    .quad GPC_wcap, PGI_info + 24
    .quad GPC_parsercount, PGI_info + 32
    .quad GPC_occupied, PGI_info + 40
    .quad GPC_regions, PGI_info + 48
    .quad GPC_lines, PGI_info + 56
    .quad GPC_flags, PGI_info + 64
    .quad GPC_warnings, PGI_info + 72
    .quad GPC_spans, PGI_spans
    .quad GPC_spans + 8, PGI_spans + 8
    .quad GPC_spans + 16, PGI_spans + 16
    .quad GPC_spans + 24, PGI_spans + 24
    .quad GPC_spans + 32, PGI_spans + 32
    .quad GPC_spans + 40, PGI_spans + 40
    .quad GPC_spans + 48, PGI_spans + 48
    .quad GPC_spans + 56, PGI_spans + 56
    .quad GPC_spans + 64, PGI_spans + 64
    .quad GPC_spans + 72, PGI_spans + 72
    .quad GPC_arrays, PGI_arrays
    .quad GPC_words, PGI_words
    .quad GPC_regionoffset, PGI_regions
    .quad GPC_lineoffset, PGI_lines
    .quad GPC_pool, PGI_pool
