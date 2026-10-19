# Counted streaming output, never a serialized native owner/header/pointer.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygpxfer.inc"
.text
# ctx,DLbyte ->1written/0exhausted/negative invariant failure.
FN pg_export_output_byte
    xor eax, eax
    cmp qword ptr [rdi + PGE_budget], 0
    je 1f
    cmp qword ptr [rdi + PGE_outremaining], 0
    je 1f
    mov rax, [rdi + PGE_outcursor]
    cmp rax, [rdi + PGE_total]
    jae .Lpx_leaf_bad
    mov rax, [rdi + PGE_out]
    add rax, [rdi + PGE_produced]
    mov [rax], dl
    dec qword ptr [rdi + PGE_budget]
    inc qword ptr [rdi + PGE_work]
    dec qword ptr [rdi + PGE_outremaining]
    inc qword ptr [rdi + PGE_produced]
    inc qword ptr [rdi + PGE_outcursor]
    mov eax, 1
1:  ret
.Lpx_leaf_bad:
    mov rsi, -EV_BAD_GRAMMAR
    jmp pg_export_fail

# ctx,source,rule0any/1nonNUL/2NUL ->0written/1pending/negative.
# Two actual payload touches are reserved before the source read.
FN pg_export_source_byte
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    cmp qword ptr [rbx + PGE_budget], 2
    jb .Lpx_pending
    cmp qword ptr [rbx + PGE_outremaining], 0
    je .Lpx_pending
    call pg_export_read_byte
    test rdx, rdx
    jz .Lpx_invariant
    test r12, r12
    jz 2f
    cmp r12, 1
    jne 1f
    test eax, eax
    jz .Lpx_bad
    jmp 2f
1:  test eax, eax
    jnz .Lpx_bad
2:  mov rdx, rax
    mov rdi, rbx
    call pg_export_output_byte
    test rax, rax
    js .Lpx_return
    cmp rax, 1
    jne .Lpx_invariant
    xor eax, eax
.Lpx_return:
    EPILOGUE
.Lpx_invariant:
    mov rdi, rbx
    mov rsi, -EV_BAD_PREPARE
    call pg_export_fail
    EPILOGUE
.Lpx_pending:
    mov eax, 1
    EPILOGUE
.Lpx_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_export_fail
    EPILOGUE

# Native cached W fields only, no payload read. 0empty/1real/negative.
FN pg_export_cached_word_check
    mov rax, [rdi + PGE_currentptr]
    mov rdx, [rdi + PGE_currentlen]
    test rax, rax
    jnz 1f
    or rdx, [rdi + PGE_currentclass]
    jnz .Lpx_leaf_bad
    xor eax, eax
    ret
1:  test rdx, rdx
    jz .Lpx_leaf_bad
    cmp rdx, [rdi + PGE_sourcebytes]
    ja .Lpx_leaf_bad
    cmp qword ptr [rdi + PGE_currentclass], C_COUNT
    jae .Lpx_leaf_bad
    add rax, rdx
    jc .Lpx_leaf_bad
    inc rax
    jz .Lpx_leaf_bad
    mov eax, 1
    ret

# Header, REG, LR and fixed arrays share a metered byte-copy cursor.
FN pg_export_emit_block
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + PGE_emitsection]
    test rax, rax
    jz .Lpx_block_header
    cmp rax, 2
    je .Lpx_block_regions
    cmp rax, 3
    je .Lpx_block_lines
    cmp rax, 4
    jne .Lpx_bad
    mov r12, [rbx + PGE_gp]
    add r12, GP_gr + GR_identx
    mov r13d, 576
    jmp .Lpx_block_again
.Lpx_block_header:
    lea r12, [rbx + PGE_header]
    mov r13d, 256
    jmp .Lpx_block_again
.Lpx_block_regions:
    mov r12, [rbx + PGE_regionptr]
    mov r13, [rbx + PGE_regionbytes]
    jmp .Lpx_block_again
.Lpx_block_lines:
    mov r12, [rbx + PGE_lineptr]
    mov r13, [rbx + PGE_linebytes]
.Lpx_block_again:
    cmp qword ptr [rbx + PGE_units], 16
    jae .Lpx_pending
    mov rax, [rbx + PGE_stringcursor]
    cmp rax, r13
    jae .Lpx_block_done
    lea rsi, [r12 + rax]
    mov rdi, rbx
    xor edx, edx
    call pg_export_source_byte
    test rax, rax
    jnz .Lpx_return
    inc qword ptr [rbx + PGE_stringcursor]
    jmp .Lpx_block_again
.Lpx_block_done:
    inc qword ptr [rbx + PGE_emitsection]
    mov qword ptr [rbx + PGE_stringcursor], 0
    mov qword ptr [rbx + PGE_field], 0
    mov qword ptr [rbx + PGE_fieldread], 0
    mov qword ptr [rbx + PGE_wordindex], 0
    mov qword ptr [rbx + PGE_recordstage], 0
    inc qword ptr [rbx + PGE_units]
    jmp .Lpx_pending

FN pg_export_emit_words
    PROLOGUE
    mov rbx, rdi
.Lpx_words_again:
    cmp qword ptr [rbx + PGE_units], 16
    jae .Lpx_pending
    mov rax, [rbx + PGE_wordindex]
    cmp rax, [rbx + PGE_wcap]
    jae .Lpx_words_done
    cmp qword ptr [rbx + PGE_recordstage], 3
    je .Lpx_word_bytes
    mov rdi, rbx
    call pg_export_word_read
    test rax, rax
    jnz .Lpx_return
    inc qword ptr [rbx + PGE_units]
    mov rdi, rbx
    call pg_export_cached_word_check
    test rax, rax
    js .Lpx_return
    jz 1f
    mov rax, [rbx + PGE_poolcursor]
    mov [rbx + PGE_wordpool], rax
    add rax, [rbx + PGE_currentlen]
    jc .Lpx_bad
    inc rax
    jz .Lpx_bad
    cmp rax, [rbx + PGE_total]
    ja .Lpx_bad
    mov [rbx + PGE_poolcursor], rax
    jmp 2f
1:  mov qword ptr [rbx + PGE_wordpool], 0
2:  mov qword ptr [rbx + PGE_fieldbyte], 0
    mov qword ptr [rbx + PGE_recordstage], 3
    jmp .Lpx_words_again
.Lpx_word_bytes:
    mov rcx, [rbx + PGE_fieldbyte]
    cmp rcx, 16
    jae .Lpx_word_done
    mov rax, [rbx + PGE_wordpool]
    cmp rcx, 8
    jb 3f
    mov rax, [rbx + PGE_currentlen]
    cmp rcx, 12
    jb 1f
    mov rax, [rbx + PGE_currentclass]
1:  and ecx, 3
3:  shl ecx, 3
    shr rax, cl
    mov rdx, rax
    mov rdi, rbx
    call pg_export_output_byte
    test rax, rax
    js .Lpx_return
    jz .Lpx_pending
    inc qword ptr [rbx + PGE_fieldbyte]
    jmp .Lpx_words_again
.Lpx_word_done:
    inc qword ptr [rbx + PGE_wordindex]
    mov qword ptr [rbx + PGE_recordstage], 0
    inc qword ptr [rbx + PGE_units]
    jmp .Lpx_words_again
.Lpx_words_done:
    mov rax, [rbx + PGE_poolcursor]
    cmp rax, [rbx + PGE_total]
    jne .Lpx_bad
    mov qword ptr [rbx + PGE_emitsection], 2
    mov qword ptr [rbx + PGE_stringcursor], 0
    inc qword ptr [rbx + PGE_units]
    jmp .Lpx_pending

FN pg_export_emit_fields
    PROLOGUE
    mov rbx, rdi
.Lpx_fields_again:
    cmp qword ptr [rbx + PGE_units], 16
    jae .Lpx_pending
    mov r12, [rbx + PGE_field]
    cmp r12, 5
    jae .Lpx_fields_done
    mov rsi, [rbx + r12*8 + PGE_fields]
    test rsi, rsi
    jz .Lpx_field_done
    mov rax, r12
    shl rax, 4
    mov r13, [rbx + rax + PGE_spans + 8]
    mov rax, [rbx + PGE_fieldread]
    cmp rax, r13
    ja .Lpx_bad
    add rsi, rax
    mov edx, 1
    cmp rax, r13
    jne 1f
    mov edx, 2
1:  mov rdi, rbx
    call pg_export_source_byte
    test rax, rax
    jnz .Lpx_return
    mov rax, [rbx + PGE_fieldread]
    inc qword ptr [rbx + PGE_fieldread]
    cmp rax, r13
    jne .Lpx_fields_again
.Lpx_field_done:
    inc qword ptr [rbx + PGE_field]
    mov qword ptr [rbx + PGE_fieldread], 0
    inc qword ptr [rbx + PGE_units]
    jmp .Lpx_fields_again
.Lpx_fields_done:
    mov rax, [rbx + PGE_outcursor]
    cmp rax, [rbx + PGE_fieldpoolend]
    jne .Lpx_bad
    mov qword ptr [rbx + PGE_emitsection], 6
    mov qword ptr [rbx + PGE_wordindex], 0
    mov qword ptr [rbx + PGE_recordstage], 0
    mov qword ptr [rbx + PGE_fieldread], 0
    inc qword ptr [rbx + PGE_units]
    jmp .Lpx_pending

FN pg_export_emit_pool
    PROLOGUE
    mov rbx, rdi
.Lpx_pool_again:
    cmp qword ptr [rbx + PGE_units], 16
    jae .Lpx_pending
    mov rax, [rbx + PGE_wordindex]
    cmp rax, [rbx + PGE_wcap]
    jae .Lpx_pool_done
    cmp qword ptr [rbx + PGE_recordstage], 3
    je .Lpx_pool_byte
    mov rdi, rbx
    call pg_export_word_read
    test rax, rax
    jnz .Lpx_return
    inc qword ptr [rbx + PGE_units]
    mov rdi, rbx
    call pg_export_cached_word_check
    test rax, rax
    js .Lpx_return
    jz .Lpx_pool_word_done
    mov qword ptr [rbx + PGE_recordstage], 3
    mov qword ptr [rbx + PGE_fieldread], 0
    jmp .Lpx_pool_again
.Lpx_pool_byte:
    mov rax, [rbx + PGE_fieldread]
    mov r13, [rbx + PGE_currentlen]
    cmp rax, r13
    ja .Lpx_bad
    mov rsi, [rbx + PGE_currentptr]
    add rsi, rax
    mov edx, 1
    cmp rax, r13
    jne 1f
    mov edx, 2
1:  mov rdi, rbx
    call pg_export_source_byte
    test rax, rax
    jnz .Lpx_return
    mov rax, [rbx + PGE_fieldread]
    inc qword ptr [rbx + PGE_fieldread]
    cmp rax, r13
    jne .Lpx_pool_again
    inc qword ptr [rbx + PGE_units]
.Lpx_pool_word_done:
    inc qword ptr [rbx + PGE_wordindex]
    mov qword ptr [rbx + PGE_recordstage], 0
    jmp .Lpx_pool_again
.Lpx_pool_done:
    mov rax, [rbx + PGE_outcursor]
    cmp rax, [rbx + PGE_total]
    jne .Lpx_bad
    mov qword ptr [rbx + PGE_emitsection], 7
    mov qword ptr [rbx + PGE_state], PGE_DONE
    inc qword ptr [rbx + PGE_units]
    xor eax, eax
    EPILOGUE

FN pg_export_emit_step
    test rdi, rdi
    jz .Lpx_api
    test rsi, rsi
    jz .Lpx_api
    lea rax, [rdx - 1]
    cmp rax, 65535
    ja .Lpx_api
    mov rax, rsi
    add rax, rdx
    jc .Lpx_api
    mov r8, rdi
    add r8, PGE_SIZE
    jc .Lpx_api
    cmp rsi, r8
    jae 1f
    cmp rax, rdi
    ja .Lpx_api
1:  lea rax, [rcx - 2]
    cmp rax, 65534
    ja .Lpx_api
    mov rax, [rdi + PGE_state]
    cmp rax, PGE_SIZED
    jb .Lpx_api
    cmp rax, PGE_FAILED
    ja .Lpx_api
    cmp rax, PGE_FAILED
    je .Lpx_sticky
    cmp rax, PGE_DONE
    je .Lpx_complete
    PROLOGUE
    mov rbx, rdi
    mov r12, rcx
    mov [rbx + PGE_budget], rcx
    mov [rbx + PGE_out], rsi
    mov [rbx + PGE_outcap], rdx
    mov [rbx + PGE_outremaining], rdx
    mov qword ptr [rbx + PGE_produced], 0
    mov qword ptr [rbx + PGE_work], 0
    mov qword ptr [rbx + PGE_units], 0
    cmp rax, PGE_SIZED
    jne .Lpx_dispatch
    mov qword ptr [rbx + PGE_state], PGE_EMIT
    mov qword ptr [rbx + PGE_emitsection], 0
    mov qword ptr [rbx + PGE_outcursor], 0
    mov qword ptr [rbx + PGE_stringcursor], 0
    mov qword ptr [rbx + PGE_wordindex], 0
    mov qword ptr [rbx + PGE_recordstage], 0
    mov qword ptr [rbx + PGE_field], 0
    mov qword ptr [rbx + PGE_fieldread], 0
    mov rax, [rbx + PGE_fieldpoolend]
    mov [rbx + PGE_poolcursor], rax
.Lpx_dispatch:
    mov rax, [rbx + PGE_emitsection]
    test rax, rax
    jz .Lpx_block
    cmp rax, 1
    je .Lpx_words
    cmp rax, 4
    jbe .Lpx_block
    cmp rax, 5
    je .Lpx_fields
    cmp rax, 6
    je .Lpx_pool
    mov rsi, -EV_BAD_PREPARE
    call pg_export_fail
    jmp .Lpx_checked
.Lpx_block:
    call pg_export_emit_block
    jmp .Lpx_checked
.Lpx_words:
    call pg_export_emit_words
    jmp .Lpx_checked
.Lpx_fields:
    call pg_export_emit_fields
    jmp .Lpx_checked
.Lpx_pool:
    call pg_export_emit_pool
.Lpx_checked:
    cmp [rbx + PGE_work], r12
    ja .Lpx_overrun
    cmp qword ptr [rbx + PGE_units], 16
    ja .Lpx_overrun
    mov rcx, [rbx + PGE_produced]
    cmp rcx, [rbx + PGE_outcap]
    ja .Lpx_overrun
.Lpx_result:
    mov rdx, [rbx + PGE_produced]
    mov rcx, [rbx + PGE_work]
    mov r8, [rbx + PGE_units]
    mov qword ptr [rbx + PGE_out], 0
    mov qword ptr [rbx + PGE_outcap], 0
    mov qword ptr [rbx + PGE_outremaining], 0
    EPILOGUE
.Lpx_overrun:
    mov rdi, rbx
    mov rsi, -EV_BAD_PREPARE
    call pg_export_fail
    jmp .Lpx_result
.Lpx_api:
    mov rax, -22
    jmp .Lpx_zero
.Lpx_sticky:
    mov rax, [rdi + PGE_error]
    jmp .Lpx_zero
.Lpx_complete:
    xor eax, eax
.Lpx_zero:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    ret
