# Pure typed-GP validation. All source-byte work crosses the metered helpers.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.text
# ctx, trusted request48. Enclosing constructor initializes stateNEW once.
FN pg_validate_begin
    test rdi, rdi
    jz .Lpg_api
    test rsi, rsi
    jz .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_WORK
    je .Lpg_busy
    cmp qword ptr [rdi + GPC_state], GPC_FAILED
    ja .Lpg_api
    cmp qword ptr [rsi], 0
    je .Lpg_api
    mov rax, [rsi + 8]
    cmp rax, 256
    jb .Lpg_api
    cmp rax, GPC_MAX
    ja .Lpg_resource
    mov rcx, [rsi]
    add rcx, rax
    jc .Lpg_api
    mov rcx, [rsi + 16]
    dec rcx
    cmp rcx, 1
    ja .Lpg_api
    cmp qword ptr [rsi + 24], 257
    ja .Lpg_api
    cmp qword ptr [rsi + 32], GPC_SOURCE_MAX
    ja .Lpg_resource
    cmp qword ptr [rsi + 40], 0
    jne .Lpg_api
    mov rax, [rsi]
    mov [rdi + GPC_wire], rax
    mov rax, [rsi + 8]
    mov [rdi + GPC_length], rax
    mov rax, [rsi + 16]
    mov [rdi + GPC_mode], rax
    mov rax, [rsi + 24]
    mov [rdi + GPC_source], rax
    mov rax, [rsi + 32]
    mov [rdi + GPC_sourcebytes], rax
    mov qword ptr [rdi + GPC_error], 0
    mov qword ptr [rdi + GPC_cursor], 0
    mov qword ptr [rdi + GPC_bytes], 0
    mov qword ptr [rdi + GPC_units], 0
    mov qword ptr [rdi + GPC_comparehave], 0
    mov qword ptr [rdi + GPC_wordindex], 0
    mov qword ptr [rdi + GPC_probes], 0
    mov qword ptr [rdi + GPC_phase], GPC_HEADER_COPY
    mov qword ptr [rdi + GPC_state], GPC_WORK
    xor eax, eax
    ret

FN pg_validate_cancel
    test rdi, rdi
    jz .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_NEW
    je .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_FAILED
    ja .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_FAILED
    je 1f
    mov qword ptr [rdi + GPC_error], -125
    mov qword ptr [rdi + GPC_state], GPC_FAILED
1:  xor eax, eax
    ret

# ctx,out64. Pure native control metadata, never serialized header reads.
FN pg_validate_status
    test rdi, rdi
    jz .Lpg_api
    test rsi, rsi
    jz .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_FAILED
    ja .Lpg_api
    mov rax, [rdi + GPC_state]
    test rax, rax
    jz .Lpg_api
    mov [rsi], rax
    mov rax, [rdi + GPC_error]
    mov [rsi + 8], rax
    mov rax, [rdi + GPC_phase]
    mov [rsi + 16], rax
    mov rax, [rdi + GPC_bytes]
    mov [rsi + 24], rax
    mov rax, [rdi + GPC_units]
    mov [rsi + 32], rax
    mov rax, [rdi + GPC_wordindex]
    mov [rsi + 40], rax
    mov rax, [rdi + GPC_probes]
    mov [rsi + 48], rax
    mov rax, [rdi + GPC_source]
    mov [rsi + 56], rax
    xor eax, eax
    ret

FN pg_validate_info
    test rdi, rdi
    jz .Lpg_api
    test rsi, rsi
    jz .Lpg_api
    cmp qword ptr [rdi + GPC_state], GPC_VALID
    jne .Lpg_api
    mov rax, [rdi + GPC_mode]
    mov [rsi], rax
    mov rax, [rdi + GPC_source]
    mov [rsi + 8], rax
    mov rax, [rdi + GPC_length]
    mov [rsi + 16], rax
    mov rax, [rdi + GPC_wcap]
    mov [rsi + 24], rax
    mov rax, [rdi + GPC_parsercount]
    mov [rsi + 32], rax
    mov rax, [rdi + GPC_occupied]
    mov [rsi + 40], rax
    mov rax, [rdi + GPC_regions]
    mov [rsi + 48], rax
    mov rax, [rdi + GPC_lines]
    mov [rsi + 56], rax
    mov rax, [rdi + GPC_flags]
    mov [rsi + 64], rax
    mov rax, [rdi + GPC_warnings]
    mov [rsi + 72], rax
    xor eax, eax
    ret

# ctx, prevalidated in-range byte address -> byte, RDX1; exhausted RDX0.
# Static program tables and native decoded control scalars are fixed work.
FN pg_read_byte
    xor edx, edx
    cmp qword ptr [rdi + GPC_budget], 0
    je 1f
    movzx eax, byte ptr [rsi]
    dec qword ptr [rdi + GPC_budget]
    inc qword ptr [rdi + GPC_bytes]
    mov edx, 1
1:  ret

# ctx, owned scratch byte address, DLbyte -> RAX1 written or0 exhausted.
FN pg_write_byte
    xor eax, eax
    cmp qword ptr [rdi + GPC_budget], 0
    je 1f
    mov [rsi], dl
    dec qword ptr [rdi + GPC_budget]
    inc qword ptr [rdi + GPC_bytes]
    mov eax, 1
1:  ret

# ctx, decoded scalar -> folded scalar, RDX1; RDX0 when fewer than9 units left.
# Existing fixed175-range case_fold has<=8 binary probes+one terminal check.
FN pg_fold_scalar
    xor edx, edx
    cmp qword ptr [rdi + GPC_units], 7
    ja 1f
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    call case_fold
    add qword ptr [rbx + GPC_units], 9
    mov edx, 1
    EPILOGUE
1:  ret

# ctx, negative protocol/resource error. Never drops the caller's wire owner.
FN pg_fail
    test rsi, rsi
    js 2f
    mov rsi, -EV_BAD_GRAMMAR
2:  cmp qword ptr [rdi + GPC_state], GPC_FAILED
    je 1f
    mov [rdi + GPC_error], rsi
    mov qword ptr [rdi + GPC_state], GPC_FAILED
1:  mov rax, [rdi + GPC_error]
    ret

.Lpg_api:
    mov rax, -22
    ret
.Lpg_busy:
    mov rax, -16
    ret

.Lpg_resource:
    mov rax, -EV_RESOURCE
    ret

# Copy header as separately metered reads+writes. Carries one byte at budget1.
FN pg_header_copy_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + GPC_units], 16
    jae .Lpg_header_pending
    cmp qword ptr [rbx + GPC_cursor], 256
    jae 3f
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_cursor]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpg_header_pending
    mov [rbx + GPC_copybyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_header]
    add rsi, [rbx + GPC_cursor]
    mov rdx, [rbx + GPC_copybyte]
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpg_header_pending
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_cursor]
    jmp 1b
3:  mov qword ptr [rbx + GPC_cursor], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_fieldvalue], 0
    mov qword ptr [rbx + GPC_phase], GPC_HEADER_DECODE
    inc qword ptr [rbx + GPC_units]
.Lpg_header_pending:
    mov eax, 1
    EPILOGUE

# Decode one initialized cached header byte at a time. No wire scalar bulk load.
FN pg_header_decode_step
    PROLOGUE
    mov rbx, rdi
.Lpg_header_field:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpg_header_pending
    mov rax, [rbx + GPC_fieldindex]
    cmp rax, 32
    jae .Lpg_header_decoded
    imul rax, 24
    lea r12, [rip + pg_header_fields]
    add r12, rax
    mov r13, [r12 + 16]
.Lpg_header_byte:
    lea rsi, [rbx + GPC_header]
    add rsi, [rbx + GPC_cursor]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpg_header_pending
    mov rcx, [rbx + GPC_fieldbyte]
    cmp r13, 1
    je .Lpg_header_magic
    cmp r13, 9
    je .Lpg_header_reserved
    shl rcx, 3
    shl rax, cl
    or [rbx + GPC_fieldvalue], rax
    jmp .Lpg_header_advance
.Lpg_header_magic:
    lea rdx, [rip + pg_gp_magic]
    cmp al, [rdx + rcx]
    jne .Lpg_header_bad
    jmp .Lpg_header_advance
.Lpg_header_reserved:
    test eax, eax
    jne .Lpg_header_bad
.Lpg_header_advance:
    inc qword ptr [rbx + GPC_cursor]
    inc qword ptr [rbx + GPC_fieldbyte]
    mov rax, [rbx + GPC_fieldbyte]
    cmp rax, [r12]
    jb .Lpg_header_byte
    mov rax, [rbx + GPC_fieldvalue]
    cmp r13, 2
    jne 1f
    cmp rax, 1
    jne .Lpg_header_bad
1:  cmp r13, 3
    jne 2f
    cmp rax, 256
    jne .Lpg_header_bad
2:  cmp r13, 4
    jne 3f
    cmp rax, [rbx + GPC_length]
    jne .Lpg_header_bad
3:  cmp r13, 5
    jne 4f
    cmp rax, [rbx + GPC_source]
    jne .Lpg_header_bad
4:  cmp r13, 6
    jne 5f
    cmp rax, [rbx + GPC_mode]
    jne .Lpg_header_bad
5:  cmp r13, 7
    jne 6f
    cmp rax, 255
    ja .Lpg_header_bad
6:  cmp r13, 8
    jne 7f
    test rax, rax
    js .Lpg_header_bad
    cmp qword ptr [rbx + GPC_mode], 1
    jne 7f
    test rax, rax
    jne .Lpg_header_bad
7:  mov rcx, [r12 + 8]
    test rcx, rcx
    jz 8f
    mov [rbx + rcx], rax
8:  mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_fieldvalue], 0
    inc qword ptr [rbx + GPC_fieldindex]
    inc qword ptr [rbx + GPC_units]
    jmp .Lpg_header_field
.Lpg_header_decoded:
    mov qword ptr [rbx + GPC_layoutindex], 0
    mov qword ptr [rbx + GPC_phase], GPC_LAYOUT
    mov eax, 1
    EPILOGUE
.Lpg_header_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    EPILOGUE

# Canonical layout uses decoded native scalars only. One bounded section/unit.
FN pg_layout_step
    PROLOGUE
    mov rbx, rdi
.Lpg_layout_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpg_header_pending
    mov rax, [rbx + GPC_layoutindex]
    cmp rax, 0
    je .Lpg_layout_words
    cmp rax, 1
    je .Lpg_layout_regions
    cmp rax, 2
    je .Lpg_layout_lines
    cmp rax, 3
    je .Lpg_layout_arrays
    cmp rax, 4
    jne .Lpg_header_bad
    mov qword ptr [rbx + GPC_arrayindex], 0
    mov qword ptr [rbx + GPC_occupied], 0
    mov qword ptr [rbx + GPC_stringbytes], 0
    mov qword ptr [rbx + GPC_wordindex], 0
    mov qword ptr [rbx + GPC_phase], GPC_RSTART_INIT
    inc qword ptr [rbx + GPC_units]
    mov eax, 1
    EPILOGUE
.Lpg_layout_words:
    mov qword ptr [rbx + GPC_canonical], 256
    mov rax, [rbx + GPC_regions]
    add rax, [rbx + GPC_lines]
    cmp rax, 4096
    ja .Lpg_header_bad
    mov rax, [rbx + GPC_wcap]
    test rax, rax
    jnz 1f
    mov rcx, [rbx + GPC_parsercount]
    or rcx, [rbx + GPC_declaredoccupied]
    or rcx, [rbx + GPC_words]
    or rcx, [rbx + GPC_wordsbytes]
    jnz .Lpg_header_bad
    jmp .Lpg_layout_next
1:  cmp rax, 64
    jb .Lpg_header_bad
    cmp rax, 131072
    ja .Lpg_header_bad
    lea rcx, [rax - 1]
    test rcx, rax
    jnz .Lpg_header_bad
    mov rcx, [rbx + GPC_parsercount]
    test rcx, rcx
    jz .Lpg_header_bad
    cmp rcx, 65536
    ja .Lpg_header_bad
    mov rdx, rax
    shr rdx, 1
    cmp rcx, rdx
    ja .Lpg_header_bad
    mov rdx, [rbx + GPC_declaredoccupied]
    test rdx, rdx
    jz .Lpg_header_bad
    cmp rdx, rcx
    ja .Lpg_header_bad
    shl rax, 4
    cmp rax, [rbx + GPC_wordsbytes]
    jne .Lpg_header_bad
    cmp qword ptr [rbx + GPC_words], 256
    jne .Lpg_header_bad
    add [rbx + GPC_canonical], rax
    jmp .Lpg_layout_next
.Lpg_layout_regions:
    mov rax, [rbx + GPC_regions]
    mov rdx, [rbx + GPC_regionoffset]
    mov rcx, [rbx + GPC_regionbytes]
    imul rax, 40
    jmp .Lpg_layout_vector
.Lpg_layout_lines:
    mov rax, [rbx + GPC_lines]
    mov rdx, [rbx + GPC_lineoffset]
    mov rcx, [rbx + GPC_linebytes]
    imul rax, 24
.Lpg_layout_vector:
    test rax, rax
    jnz 1f
    or rcx, rdx
    jnz .Lpg_header_bad
    jmp .Lpg_layout_next
1:  cmp rax, rcx
    jne .Lpg_header_bad
    cmp rdx, [rbx + GPC_canonical]
    jne .Lpg_header_bad
    add [rbx + GPC_canonical], rax
    jmp .Lpg_layout_next
.Lpg_layout_arrays:
    cmp qword ptr [rbx + GPC_arraybytes], 576
    jne .Lpg_header_bad
    mov rax, [rbx + GPC_canonical]
    cmp [rbx + GPC_arrays], rax
    jne .Lpg_header_bad
    add rax, 576
    mov [rbx + GPC_pool], rax
    cmp rax, [rbx + GPC_length]
    ja .Lpg_header_bad
    mov rcx, [rbx + GPC_length]
    sub rcx, rax
    cmp rcx, 4
    jb .Lpg_header_bad
    mov rdx, [rbx + GPC_sourcebytes]
    add rdx, [rbx + GPC_declaredoccupied]
    add rdx, 5
    cmp rcx, rdx
    ja .Lpg_header_bad
.Lpg_layout_next:
    inc qword ptr [rbx + GPC_layoutindex]
    inc qword ptr [rbx + GPC_units]
    jmp .Lpg_layout_again

.section .rodata
.p2align 3
pg_gp_magic: .ascii "RHGPR1\0\0"
pg_header_fields:
    .quad 8, 0, 1
    .quad 4, 0, 2
    .quad 4, 0, 3
    .quad 8, 0, 4
    .quad 4, 0, 5
    .quad 4, 0, 6
    .quad 8, GPC_flags, 7
    .quad 8, GPC_warnings, 8
    .quad 4, GPC_wcap, 0
    .quad 4, GPC_parsercount, 0
    .quad 4, GPC_regions, 0
    .quad 4, GPC_lines, 0
    .quad 8, GPC_spans, 0
    .quad 8, GPC_spans + 8, 0
    .quad 8, GPC_spans + 16, 0
    .quad 8, GPC_spans + 24, 0
    .quad 8, GPC_spans + 32, 0
    .quad 8, GPC_spans + 40, 0
    .quad 8, GPC_spans + 48, 0
    .quad 8, GPC_spans + 56, 0
    .quad 8, GPC_spans + 64, 0
    .quad 8, GPC_spans + 72, 0
    .quad 8, GPC_words, 0
    .quad 8, GPC_wordsbytes, 0
    .quad 8, GPC_regionoffset, 0
    .quad 8, GPC_regionbytes, 0
    .quad 8, GPC_lineoffset, 0
    .quad 8, GPC_linebytes, 0
    .quad 8, GPC_arrays, 0
    .quad 8, GPC_arraybytes, 0
    .quad 4, GPC_declaredoccupied, 0
    .quad 44, 0, 9

# One phase helper per call; its bounded loops consume the shared byte/unit ledger.
FN pg_validate_step
    test rdi, rdi
    jz .Lpg_step_api
    lea rax, [rsi - 1]
    cmp rax, 65535
    ja .Lpg_step_api
    cmp qword ptr [rdi + GPC_state], GPC_NEW
    je .Lpg_step_api
    cmp qword ptr [rdi + GPC_state], GPC_FAILED
    ja .Lpg_step_api
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov [rbx + GPC_budget], rsi
    mov qword ptr [rbx + GPC_bytes], 0
    mov qword ptr [rbx + GPC_units], 0
    cmp qword ptr [rbx + GPC_state], GPC_VALID
    je .Lpg_step_valid
    cmp qword ptr [rbx + GPC_state], GPC_FAILED
    je .Lpg_step_failed
    mov rax, [rbx + GPC_phase]
    test rax, rax
    jz .Lpg_step_copy
    cmp rax, GPC_HEADER_DECODE
    je .Lpg_step_decode
    cmp rax, GPC_LAYOUT
    je .Lpg_step_layout
    cmp rax, GPC_RSTART_INIT
    je .Lpg_step_arrays
    cmp rax, GPC_WCHAR_INIT
    je .Lpg_step_arrays
    cmp rax, GPC_REGIONS
    je .Lpg_step_rules
    cmp rax, GPC_LINES
    je .Lpg_step_rules
    cmp rax, GPC_IDENT
    je .Lpg_step_arrays
    cmp rax, GPC_PREFIX
    je .Lpg_step_arrays
    cmp rax, GPC_RSTART_CHECK
    je .Lpg_step_arrays
    cmp rax, GPC_WCHAR_CHECK
    je .Lpg_step_arrays
    cmp rax, GPC_FIELDS
    je .Lpg_step_fields
    cmp rax, GPC_WORDS
    je .Lpg_step_words
    cmp rax, GPC_REACHABILITY
    je .Lpg_step_reach
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    jmp .Lpg_step_checked
.Lpg_step_copy:
    call pg_header_copy_step
    jmp .Lpg_step_checked
.Lpg_step_decode:
    call pg_header_decode_step
    jmp .Lpg_step_checked
.Lpg_step_layout:
    call pg_layout_step
    jmp .Lpg_step_checked
.Lpg_step_rules:
    call pg_rule_step
    jmp .Lpg_step_checked
.Lpg_step_arrays:
    call pg_arrays_step
    jmp .Lpg_step_checked
.Lpg_step_fields:
    call pg_fields_step
    jmp .Lpg_step_checked
.Lpg_step_words:
    call pg_words_step
    jmp .Lpg_step_checked
.Lpg_step_reach:
    call pg_reach_step
.Lpg_step_checked:
    cmp [rbx + GPC_bytes], r12
    ja .Lpg_step_overrun
    cmp qword ptr [rbx + GPC_units], 16
    ja .Lpg_step_overrun
    cmp qword ptr [rbx + GPC_state], GPC_VALID
    je .Lpg_step_valid
    cmp qword ptr [rbx + GPC_state], GPC_FAILED
    je .Lpg_step_failed
    mov eax, 1
    jmp .Lpg_step_result
.Lpg_step_overrun:
    mov rdi, rbx
    mov rsi, -EV_BAD_PREPARE
    call pg_fail
.Lpg_step_failed:
    mov rax, [rbx + GPC_error]
    jmp .Lpg_step_result
.Lpg_step_valid:
    xor eax, eax
.Lpg_step_result:
    mov rdx, [rbx + GPC_bytes]
    mov rcx, [rbx + GPC_units]
    EPILOGUE
.Lpg_step_api:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
