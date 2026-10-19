# Worker-side bounded sizing of an immutable actual prepared grammar.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.include "app/extdiscoverygpxfer.inc"
.text
FN pg_export_begin
    test rdi, rdi
    jz .Lpe_api
    test rsi, rsi
    jz .Lpe_api
    mov rax, [rdi + PGE_state]
    cmp rax, PGE_FAILED
    ja .Lpe_api
    test rax, rax
    jz 1f
    cmp rax, PGE_DONE
    jb .Lpe_busy
1:  cmp qword ptr [rsi + 32], 0
    jne .Lpe_api
    mov r8, [rsi]
    test r8, r8
    jz .Lpe_api
    mov rax, r8
    add rax, GP_SIZE
    jc .Lpe_api
    mov r9, [rsi + 8]
    lea rax, [r9 - 1]
    cmp rax, 1
    ja .Lpe_api
    mov r10, [rsi + 16]
    cmp r10, 257
    ja .Lpe_api
    mov r11, [rsi + 24]
    cmp r11, GPC_SOURCE_MAX
    ja .Lpe_resource
    cmp qword ptr [r8 + PO_ready], 1
    jne .Lpe_api
    cmp qword ptr [r8 + PO_error], 0
    jne .Lpe_api
    cmp qword ptr [r8 + PO_refs], 0
    jle .Lpe_api
    cmp [r8 + GP_legacy], rax
    jne .Lpe_api
    cmp [r8 + GP_gr + GR_owner], r8
    jne .Lpe_api
    mov rcx, [r8 + GP_gr + GR_flags]
    cmp rcx, 255
    ja .Lpe_api
    mov rcx, [r8 + GP_warnings]
    test rcx, rcx
    js .Lpe_api
    cmp r9, 2
    je 2f
    test rcx, rcx
    jnz .Lpe_api
2:  mov rcx, [r8 + GP_gr + GR_regions + VEC_len]
    add rcx, [r8 + GP_gr + GR_lines + VEC_len]
    jc .Lpe_resource
    cmp rcx, 4096
    ja .Lpe_resource
    mov rcx, [r8 + GP_gr + GR_wcap]
    test rcx, rcx
    jnz 3f
    cmp qword ptr [r8 + GP_gr + GR_wn], 0
    jne .Lpe_api
    jmp 5f
3:  cmp rcx, 64
    jb .Lpe_api
    cmp rcx, 131072
    ja .Lpe_resource
    lea rdx, [rcx - 1]
    test rcx, rdx
    jnz .Lpe_api
    shr rcx, 1
    mov rdx, [r8 + GP_gr + GR_wn]
    test rdx, rdx
    jz .Lpe_api
    cmp rdx, rcx
    ja .Lpe_api
    mov rdx, [r8 + GP_gr + GR_words]
    test rdx, rdx
    jz .Lpe_api
    mov rcx, [r8 + GP_gr + GR_wcap]
    shl rcx, 4
    add rdx, rcx
    jc .Lpe_api
5:  mov rax, [r8 + GP_gr + GR_regions + VEC_len]
    cmp rax, [r8 + GP_gr + GR_regions + VEC_cap]
    ja .Lpe_api
    test rax, rax
    jz 6f
    mov rdx, [r8 + GP_gr + GR_regions + VEC_ptr]
    test rdx, rdx
    jz .Lpe_api
    imul rax, 40
    add rdx, rax
    jc .Lpe_api
6:  mov rax, [r8 + GP_gr + GR_lines + VEC_len]
    cmp rax, [r8 + GP_gr + GR_lines + VEC_cap]
    ja .Lpe_api
    test rax, rax
    jz 7f
    mov rdx, [r8 + GP_gr + GR_lines + VEC_ptr]
    test rdx, rdx
    jz .Lpe_api
    imul rax, 24
    add rdx, rax
    jc .Lpe_api
7:  cmp qword ptr [r8 + GP_gr + GR_name], 0
    je .Lpe_api
    cmp qword ptr [r8 + GP_gr + GR_files], 0
    je .Lpe_api
    cmp qword ptr [r8 + GP_gr + GR_first], 0
    je .Lpe_api
    cmp qword ptr [r8 + GP_gr + GR_icon], 0
    je .Lpe_api
    mov qword ptr [rdi + PGE_state], PGE_MEASURE
    mov qword ptr [rdi + PGE_phase], PGE_META
    mov qword ptr [rdi + PGE_error], 0
    mov [rdi + PGE_gp], r8
    mov [rdi + PGE_mode], r9
    mov [rdi + PGE_ordinal], r10
    mov [rdi + PGE_sourcebytes], r11
    mov qword ptr [rdi + PGE_work], 0
    mov qword ptr [rdi + PGE_units], 0
    mov qword ptr [rdi + PGE_field], 0
    mov qword ptr [rdi + PGE_fieldread], 0
    mov qword ptr [rdi + PGE_wordindex], 0
    mov qword ptr [rdi + PGE_outcursor], 0
    mov qword ptr [rdi + PGE_total], 0
    mov qword ptr [rdi + PGE_copyhave], 0
    mov qword ptr [rdi + PGE_recordstage], 0
    xor eax, eax
    ret

FN pg_export_cancel
    test rdi, rdi
    jz .Lpe_api
    mov rax, [rdi + PGE_state]
    test rax, rax
    jz .Lpe_api
    cmp rax, PGE_FAILED
    ja .Lpe_api
    je 1f
    mov qword ptr [rdi + PGE_error], -125
    mov qword ptr [rdi + PGE_state], PGE_FAILED
1:  xor eax, eax
    ret

FN pg_export_status
    test rdi, rdi
    jz .Lpe_api
    test rsi, rsi
    jz .Lpe_api
    mov rax, [rdi + PGE_state]
    test rax, rax
    jz .Lpe_api
    cmp rax, PGE_FAILED
    ja .Lpe_api
    mov [rsi], rax
    mov rax, [rdi + PGE_error]
    mov [rsi + 8], rax
    mov rax, [rdi + PGE_phase]
    mov [rsi + 16], rax
    mov rax, [rdi + PGE_work]
    mov [rsi + 24], rax
    mov rax, [rdi + PGE_units]
    mov [rsi + 32], rax
    mov rax, [rdi + PGE_total]
    mov [rsi + 40], rax
    mov rax, [rdi + PGE_outcursor]
    mov [rsi + 48], rax
    mov rax, [rdi + PGE_wordindex]
    mov [rsi + 56], rax
    xor eax, eax
    ret

FN pg_export_info
    test rdi, rdi
    jz .Lpe_api
    test rsi, rsi
    jz .Lpe_api
    mov rax, [rdi + PGE_state]
    sub rax, PGE_SIZED
    cmp rax, PGE_DONE - PGE_SIZED
    ja .Lpe_api
    mov rax, [rdi + PGE_mode]
    mov [rsi], rax
    mov rax, [rdi + PGE_ordinal]
    mov [rsi + 8], rax
    mov rax, [rdi + PGE_total]
    mov [rsi + 16], rax
    mov rax, [rdi + PGE_wcap]
    mov [rsi + 24], rax
    mov rax, [rdi + PGE_parsercount]
    mov [rsi + 32], rax
    mov rax, [rdi + PGE_occupied]
    mov [rsi + 40], rax
    mov rax, [rdi + PGE_regions]
    mov [rsi + 48], rax
    mov rax, [rdi + PGE_lines]
    mov [rsi + 56], rax
    mov rax, [rdi + PGE_flags]
    mov [rsi + 64], rax
    mov rax, [rdi + PGE_warnings]
    mov [rsi + 72], rax
    xor eax, eax
    ret

FN pg_export_read_byte
    xor edx, edx
    cmp qword ptr [rdi + PGE_budget], 0
    je 1f
    movzx eax, byte ptr [rsi]
    dec qword ptr [rdi + PGE_budget]
    inc qword ptr [rdi + PGE_work]
    mov edx, 1
1:  ret
FN pg_export_write_byte
    xor eax, eax
    cmp qword ptr [rdi + PGE_budget], 0
    je 1f
    mov [rsi], dl
    dec qword ptr [rdi + PGE_budget]
    inc qword ptr [rdi + PGE_work]
    mov eax, 1
1:  ret
FN pg_export_fail
    test rsi, rsi
    js 1f
    mov rsi, -EV_BAD_GRAMMAR
1:  cmp qword ptr [rdi + PGE_state], PGE_FAILED
    je 2f
    mov [rdi + PGE_error], rsi
    mov qword ptr [rdi + PGE_state], PGE_FAILED
2:  mov rax, [rdi + PGE_error]
    ret
.Lpe_api:
    mov rax, -22
    ret
.Lpe_busy:
    mov rax, -16
    ret
.Lpe_resource:
    mov rax, -EV_RESOURCE
    ret

# Bounded fixed native metadata snapshots. No product table/string byte reads.
FN pg_export_meta_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + PGE_units], 16
    jae .Lpe_pending
    mov rax, [rbx + PGE_field]
    cmp rax, 16
    jae 3f
    shl rax, 4
    lea r12, [rip + pge_metadata]
    add r12, rax
    mov rcx, [r12]
    xor eax, eax
    cmp rcx, -1
    je 2f
    mov rdx, [rbx + PGE_gp]
    mov rax, [rdx + rcx]
2:  mov rcx, [r12 + 8]
    mov [rbx + rcx], rax
    inc qword ptr [rbx + PGE_field]
    inc qword ptr [rbx + PGE_units]
    jmp 1b
3:  mov qword ptr [rbx + PGE_field], 0
    mov qword ptr [rbx + PGE_fieldread], 0
    mov qword ptr [rbx + PGE_phase], PGE_STRINGS
    inc qword ptr [rbx + PGE_units]
.Lpe_pending:
    mov eax, 1
    EPILOGUE

FN pg_export_strings_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + PGE_units], 16
    jae .Lpe_pending
    mov r12, [rbx + PGE_field]
    cmp r12, 5
    jae .Lpe_strings_done
    mov rsi, [rbx + r12*8 + PGE_fields]
    test rsi, rsi
    jnz 2f
    cmp r12, 4
    jne .Lpe_bad
    mov rax, r12
    shl rax, 4
    mov qword ptr [rbx + rax + PGE_spans], 0
    mov qword ptr [rbx + rax + PGE_spans + 8], 0
    jmp .Lpe_string_next
2:  mov rax, [rbx + PGE_fieldread]
    cmp rax, [rbx + PGE_sourcebytes]
    ja .Lpe_bad
    add rsi, rax
    jc .Lpe_bad
    mov rdi, rbx
    call pg_export_read_byte
    test rdx, rdx
    jz .Lpe_pending
    test eax, eax
    jz .Lpe_string_end
    inc qword ptr [rbx + PGE_fieldread]
    jmp 1b
.Lpe_string_end:
    mov rax, [rbx + PGE_fieldread]
    cmp r12, 4
    jne 3f
    test rax, rax
    jz .Lpe_bad
3:  test r12, r12
    jnz 4f
    cmp qword ptr [rbx + PGE_mode], 1
    jne 4f
    test rax, rax
    jz .Lpe_bad
    cmp rax, 128
    ja .Lpe_bad
4:  mov rcx, [rbx + PGE_chars]
    add rcx, rax
    jc .Lpe_bad
    cmp rcx, [rbx + PGE_sourcebytes]
    ja .Lpe_bad
    mov [rbx + PGE_chars], rcx
    mov rcx, r12
    shl rcx, 4
    mov [rbx + rcx + PGE_spans + 8], rax
.Lpe_string_next:
    inc qword ptr [rbx + PGE_field]
    mov qword ptr [rbx + PGE_fieldread], 0
    inc qword ptr [rbx + PGE_units]
    jmp 1b
.Lpe_strings_done:
    mov qword ptr [rbx + PGE_wordindex], 0
    mov qword ptr [rbx + PGE_recordstage], 0
    mov qword ptr [rbx + PGE_phase], PGE_WORDS
    inc qword ptr [rbx + PGE_units]
    jmp .Lpe_pending

# Decodes one native W16 from an immutable actual GP into native scalar caches.
# Every source record byte is metered; cached scalar accumulation is fixed control.
FN pg_export_word_read
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + PGE_recordstage], 2
    je .Lpe_record_done
    cmp qword ptr [rbx + PGE_recordstage], 1
    je 1f
    mov qword ptr [rbx + PGE_recordcursor], 0
    mov qword ptr [rbx + PGE_accumulator], 0
    mov qword ptr [rbx + PGE_currentptr], 0
    mov qword ptr [rbx + PGE_currentlen], 0
    mov qword ptr [rbx + PGE_currentclass], 0
    mov qword ptr [rbx + PGE_recordstage], 1
1:  mov r12, [rbx + PGE_recordcursor]
    cmp r12, 16
    jae 5f
    mov rsi, [rbx + PGE_wordindex]
    shl rsi, 4
    add rsi, [rbx + PGE_words]
    add rsi, r12
    mov rdi, rbx
    call pg_export_read_byte
    test rdx, rdx
    jz .Lpe_pending
    mov rcx, r12
    cmp rcx, 8
    jb 2f
    and ecx, 3
2:  shl ecx, 3
    shl rax, cl
    or [rbx + PGE_accumulator], rax
    mov edx, PGE_currentptr
    cmp r12, 7
    je 3f
    mov edx, PGE_currentlen
    cmp r12, 11
    je 3f
    mov edx, PGE_currentclass
    cmp r12, 15
    jne 4f
3:  mov rax, [rbx + PGE_accumulator]
    mov [rbx + rdx], rax
    mov qword ptr [rbx + PGE_accumulator], 0
4:  inc qword ptr [rbx + PGE_recordcursor]
    jmp 1b
5:  mov qword ptr [rbx + PGE_recordstage], 2
.Lpe_record_done:
    xor eax, eax
    EPILOGUE

FN pg_export_words_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + PGE_units], 16
    jae .Lpe_pending
    mov rax, [rbx + PGE_wordindex]
    cmp rax, [rbx + PGE_wcap]
    jae .Lpe_words_done
    mov rdi, rbx
    call pg_export_word_read
    test rax, rax
    jnz .Lpe_pending
    inc qword ptr [rbx + PGE_units]
    mov rax, [rbx + PGE_currentptr]
    mov rdx, [rbx + PGE_currentlen]
    test rax, rax
    jnz 2f
    or rdx, [rbx + PGE_currentclass]
    jnz .Lpe_bad
    jmp 3f
2:  test rdx, rdx
    jz .Lpe_bad
    cmp rdx, [rbx + PGE_sourcebytes]
    ja .Lpe_bad
    cmp qword ptr [rbx + PGE_currentclass], C_COUNT
    jae .Lpe_bad
    add rax, rdx
    jc .Lpe_bad
    inc rax
    jz .Lpe_bad
    mov rax, [rbx + PGE_chars]
    add rax, rdx
    jc .Lpe_bad
    cmp rax, [rbx + PGE_sourcebytes]
    ja .Lpe_bad
    mov [rbx + PGE_chars], rax
    inc qword ptr [rbx + PGE_occupied]
3:  inc qword ptr [rbx + PGE_wordindex]
    mov qword ptr [rbx + PGE_recordstage], 0
    jmp 1b
.Lpe_words_done:
    mov rax, [rbx + PGE_occupied]
    cmp rax, [rbx + PGE_parsercount]
    ja .Lpe_bad
    cmp qword ptr [rbx + PGE_wcap], 0
    je 4f
    test rax, rax
    jz .Lpe_bad
4:  mov qword ptr [rbx + PGE_phase], PGE_LAYOUT
    inc qword ptr [rbx + PGE_units]
    jmp .Lpe_pending

FN pg_export_layout_step
    PROLOGUE
    mov rbx, rdi
    mov r12d, 256
    mov rax, [rbx + PGE_wcap]
    shl rax, 4
    mov [rbx + PGE_wordbytes], rax
    xor ecx, ecx
    test rax, rax
    jz 1f
    mov rcx, r12
    add r12, rax
1:  mov [rbx + PGE_wordoffset], rcx
    mov rax, [rbx + PGE_regions]
    imul rax, 40
    mov [rbx + PGE_regionbytes], rax
    xor ecx, ecx
    test rax, rax
    jz 2f
    mov rcx, r12
    add r12, rax
2:  mov [rbx + PGE_regionoffset], rcx
    mov rax, [rbx + PGE_lines]
    imul rax, 24
    mov [rbx + PGE_linebytes], rax
    xor ecx, ecx
    test rax, rax
    jz 3f
    mov rcx, r12
    add r12, rax
3:  mov [rbx + PGE_lineoffset], rcx
    mov [rbx + PGE_arrayoffset], r12
    add r12, 576
    mov [rbx + PGE_pool], r12
    mov qword ptr [rbx + PGE_units], 5
    xor r13d, r13d
4:  mov rax, r13
    shl rax, 4
    cmp qword ptr [rbx + r13*8 + PGE_fields], 0
    je 5f
    mov [rbx + rax + PGE_spans], r12
    add r12, [rbx + rax + PGE_spans + 8]
    inc r12
5:  inc r13
    inc qword ptr [rbx + PGE_units]
    cmp r13, 5
    jb 4b
    mov [rbx + PGE_fieldpoolend], r12
    mov [rbx + PGE_poolcursor], r12
    mov rax, [rbx + PGE_pool]
    add rax, [rbx + PGE_chars]
    add rax, [rbx + PGE_occupied]
    add rax, 4
    cmp qword ptr [rbx + PGE_fields + 32], 0
    je 6f
    inc rax
6:  cmp rax, 4424517
    ja .Lpe_bad
    mov [rbx + PGE_total], rax
    mov qword ptr [rbx + PGE_headercursor], 0
    mov qword ptr [rbx + PGE_field], 0
    mov qword ptr [rbx + PGE_fieldbyte], 0
    mov qword ptr [rbx + PGE_phase], PGE_HEADER_BUILD
    inc qword ptr [rbx + PGE_units]
    jmp .Lpe_pending

FN pg_export_header_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + PGE_units], 16
    jae .Lpe_pending
    mov rax, [rbx + PGE_field]
    cmp rax, 32
    jae .Lpe_sized
    imul rax, 24
    lea r12, [rip + pge_header_fields]
    add r12, rax
    mov rcx, [r12 + 16]
    mov rax, [r12 + 8]
    cmp rcx, 0
    jne 2f
    mov rax, [rbx + rax]
2:  cmp rcx, 2
    jne 3f
    lea rdx, [rip + pge_magic]
    add rdx, [rbx + PGE_fieldbyte]
    movzx eax, byte ptr [rdx]
    jmp 4f
3:  cmp rcx, 3
    je 4f
    mov rcx, [rbx + PGE_fieldbyte]
    shl ecx, 3
    shr rax, cl
4:  mov rdx, rax
    lea rsi, [rbx + PGE_header]
    add rsi, [rbx + PGE_headercursor]
    mov rdi, rbx
    call pg_export_write_byte
    test rax, rax
    jz .Lpe_pending
    inc qword ptr [rbx + PGE_headercursor]
    inc qword ptr [rbx + PGE_fieldbyte]
    mov rax, [rbx + PGE_fieldbyte]
    cmp rax, [r12]
    jb 1b
    mov qword ptr [rbx + PGE_fieldbyte], 0
    inc qword ptr [rbx + PGE_field]
    inc qword ptr [rbx + PGE_units]
    jmp 1b
.Lpe_sized:
    mov qword ptr [rbx + PGE_state], PGE_SIZED
    inc qword ptr [rbx + PGE_units]
    xor eax, eax
    EPILOGUE
.Lpe_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_export_fail
    EPILOGUE

FN pg_export_measure_step
    test rdi, rdi
    jz .Lpe_step_api
    lea rax, [rsi - 1]
    cmp rax, 65535
    ja .Lpe_step_api
    mov rax, [rdi + PGE_state]
    test rax, rax
    jz .Lpe_step_api
    cmp rax, PGE_FAILED
    ja .Lpe_step_api
    cmp rax, PGE_FAILED
    je .Lpe_step_sticky
    cmp rax, PGE_MEASURE
    jne .Lpe_step_complete
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov [rbx + PGE_budget], rsi
    mov qword ptr [rbx + PGE_work], 0
    mov qword ptr [rbx + PGE_units], 0
    mov rax, [rbx + PGE_phase]
    test rax, rax
    jz .Lpe_step_meta
    cmp rax, PGE_STRINGS
    je .Lpe_step_strings
    cmp rax, PGE_WORDS
    je .Lpe_step_words
    cmp rax, PGE_LAYOUT
    je .Lpe_step_layout
    cmp rax, PGE_HEADER_BUILD
    je .Lpe_step_header
    mov rsi, -EV_BAD_PREPARE
    call pg_export_fail
    jmp .Lpe_step_result
.Lpe_step_meta:
    call pg_export_meta_step
    jmp .Lpe_step_result
.Lpe_step_strings:
    call pg_export_strings_step
    jmp .Lpe_step_result
.Lpe_step_words:
    call pg_export_words_step
    jmp .Lpe_step_result
.Lpe_step_layout:
    call pg_export_layout_step
    jmp .Lpe_step_result
.Lpe_step_header:
    call pg_export_header_step
.Lpe_step_result:
    cmp [rbx + PGE_work], r12
    ja .Lpe_step_overrun
    cmp qword ptr [rbx + PGE_units], 16
    ja .Lpe_step_overrun
.Lpe_step_return:
    mov rdx, [rbx + PGE_work]
    mov rcx, [rbx + PGE_units]
    EPILOGUE
.Lpe_step_overrun:
    mov rdi, rbx
    mov rsi, -EV_BAD_PREPARE
    call pg_export_fail
    jmp .Lpe_step_return
.Lpe_step_sticky:
    mov rax, [rdi + PGE_error]
    xor edx, edx
    xor ecx, ecx
    ret
.Lpe_step_complete:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    ret
.Lpe_step_api:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret

.section .rodata
.p2align 3
pge_metadata:
    .quad GP_gr + GR_wcap, PGE_wcap
    .quad GP_gr + GR_wn, PGE_parsercount
    .quad GP_gr + GR_regions + VEC_len, PGE_regions
    .quad GP_gr + GR_lines + VEC_len, PGE_lines
    .quad GP_gr + GR_flags, PGE_flags
    .quad GP_warnings, PGE_warnings
    .quad GP_gr + GR_words, PGE_words
    .quad GP_gr + GR_regions + VEC_ptr, PGE_regionptr
    .quad GP_gr + GR_lines + VEC_ptr, PGE_lineptr
    .quad GP_gr + GR_name, PGE_fields
    .quad GP_gr + GR_files, PGE_fields + 8
    .quad GP_gr + GR_first, PGE_fields + 16
    .quad GP_gr + GR_icon, PGE_fields + 24
    .quad GP_gr + GR_comment, PGE_fields + 32
    .quad -1, PGE_chars
    .quad -1, PGE_occupied
pge_magic: .ascii "RHGPR1\0\0"
pge_header_fields:
    .quad 8, 0, 2
    .quad 4, 1, 1
    .quad 4, 256, 1
    .quad 8, PGE_total, 0
    .quad 4, PGE_ordinal, 0
    .quad 4, PGE_mode, 0
    .quad 8, PGE_flags, 0
    .quad 8, PGE_warnings, 0
    .quad 4, PGE_wcap, 0
    .quad 4, PGE_parsercount, 0
    .quad 4, PGE_regions, 0
    .quad 4, PGE_lines, 0
    .quad 8, PGE_spans, 0
    .quad 8, PGE_spans + 8, 0
    .quad 8, PGE_spans + 16, 0
    .quad 8, PGE_spans + 24, 0
    .quad 8, PGE_spans + 32, 0
    .quad 8, PGE_spans + 40, 0
    .quad 8, PGE_spans + 48, 0
    .quad 8, PGE_spans + 56, 0
    .quad 8, PGE_spans + 64, 0
    .quad 8, PGE_spans + 72, 0
    .quad 8, PGE_wordoffset, 0
    .quad 8, PGE_wordbytes, 0
    .quad 8, PGE_regionoffset, 0
    .quad 8, PGE_regionbytes, 0
    .quad 8, PGE_lineoffset, 0
    .quad 8, PGE_linebytes, 0
    .quad 8, PGE_arrayoffset, 0
    .quad 8, 576, 1
    .quad 4, PGE_occupied, 0
    .quad 44, 0, 3
