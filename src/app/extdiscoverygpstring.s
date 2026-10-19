# Metered canonical UTF8 string checks. No whole-string helper or source IO.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.text
# ctx,decoded offset,len,strictName. Pure range checks before the first byte read.
FN pg_string_begin
    cmp rsi, [rdi + GPC_stringcursor]
    jne .Lpgs_bad
    cmp rdx, [rdi + GPC_sourcebytes]
    ja .Lpgs_bad
    mov rax, rsi
    add rax, rdx
    jc .Lpgs_bad
    inc rax
    jz .Lpgs_bad
    cmp rax, [rdi + GPC_length]
    ja .Lpgs_bad
    mov rax, [rdi + GPC_stringbytes]
    add rax, rdx
    jc .Lpgs_bad
    cmp rax, [rdi + GPC_sourcebytes]
    ja .Lpgs_bad
    mov [rdi + GPC_stringlen], rdx
    mov [rdi + GPC_stringstrict], rcx
    mov qword ptr [rdi + GPC_stringread], 0
    mov qword ptr [rdi + GPC_utf8remaining], 0
    mov qword ptr [rdi + GPC_stringstate], 0
    xor eax, eax
    ret

# One already-metered byte, native decoder scalars only. No pointer follows.
FN pg_utf8_push
    movzx eax, sil
    cmp qword ptr [rdi + GPC_utf8remaining], 0
    jne .Lpgs_continuation
    cmp eax, 128
    jb .Lpgs_scalar
    cmp eax, 0xc2
    jb .Lpgs_bad
    cmp eax, 0xdf
    jbe .Lpgs_two
    cmp eax, 0xef
    jbe .Lpgs_three
    cmp eax, 0xf4
    ja .Lpgs_bad
    mov qword ptr [rdi + GPC_utf8remaining], 3
    mov qword ptr [rdi + GPC_utf8min], 0x10000
    mov qword ptr [rdi + GPC_utf8lower], 0x80
    mov qword ptr [rdi + GPC_utf8upper], 0xbf
    cmp eax, 0xf0
    jne 1f
    mov qword ptr [rdi + GPC_utf8lower], 0x90
1:  cmp eax, 0xf4
    jne 2f
    mov qword ptr [rdi + GPC_utf8upper], 0x8f
2:  and eax, 7
    mov [rdi + GPC_utf8scalar], rax
    xor eax, eax
    ret
.Lpgs_three:
    mov qword ptr [rdi + GPC_utf8remaining], 2
    mov qword ptr [rdi + GPC_utf8min], 0x800
    mov qword ptr [rdi + GPC_utf8lower], 0x80
    mov qword ptr [rdi + GPC_utf8upper], 0xbf
    cmp eax, 0xe0
    jne 1f
    mov qword ptr [rdi + GPC_utf8lower], 0xa0
1:  cmp eax, 0xed
    jne 2f
    mov qword ptr [rdi + GPC_utf8upper], 0x9f
2:  and eax, 15
    mov [rdi + GPC_utf8scalar], rax
    xor eax, eax
    ret
.Lpgs_two:
    mov qword ptr [rdi + GPC_utf8remaining], 1
    mov qword ptr [rdi + GPC_utf8min], 0x80
    mov qword ptr [rdi + GPC_utf8lower], 0x80
    mov qword ptr [rdi + GPC_utf8upper], 0xbf
    and eax, 31
    mov [rdi + GPC_utf8scalar], rax
    xor eax, eax
    ret
.Lpgs_continuation:
    cmp rax, [rdi + GPC_utf8lower]
    jb .Lpgs_bad
    cmp rax, [rdi + GPC_utf8upper]
    ja .Lpgs_bad
    and eax, 63
    mov r8, [rdi + GPC_utf8scalar]
    shl r8, 6
    or rax, r8
    mov [rdi + GPC_utf8scalar], rax
    mov qword ptr [rdi + GPC_utf8lower], 0x80
    mov qword ptr [rdi + GPC_utf8upper], 0xbf
    dec qword ptr [rdi + GPC_utf8remaining]
    jnz .Lpgs_ok
    cmp rax, [rdi + GPC_utf8min]
    jb .Lpgs_bad
    cmp rax, 0x10ffff
    ja .Lpgs_bad
    lea r8, [rax - 0xd800]
    cmp r8, 0x7ff
    jbe .Lpgs_bad
.Lpgs_scalar:
    mov [rdi + GPC_utf8scalar], rax
    cmp eax, 32
    jae 1f
    test rdx, rdx
    jnz .Lpgs_bad
    cmp eax, 9
    je .Lpgs_ok
    cmp eax, 10
    je .Lpgs_ok
    cmp eax, 13
    jne .Lpgs_bad
    jmp .Lpgs_ok
1:  cmp eax, 127
    jb .Lpgs_ok
    cmp eax, 160
    jb .Lpgs_bad
.Lpgs_ok:
    xor eax, eax
    ret

# ctx -> 0 complete/1pending/negative. Character+terminator bytes each metered.
FN pg_string_step
    PROLOGUE
    mov rbx, rdi
1:  cmp qword ptr [rbx + GPC_stringstate], 2
    je .Lpgs_complete
    cmp qword ptr [rbx + GPC_stringstate], 1
    je .Lpgs_terminator
    mov rax, [rbx + GPC_stringread]
    cmp rax, [rbx + GPC_stringlen]
    jae .Lpgs_end_bytes
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_stringcursor]
    add rsi, rax
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgs_pending
    test eax, eax
    jz .Lpgs_step_bad
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rbx + GPC_stringstrict]
    call pg_utf8_push
    test rax, rax
    js .Lpgs_exit
    inc qword ptr [rbx + GPC_stringread]
    jmp 1b
.Lpgs_end_bytes:
    cmp qword ptr [rbx + GPC_utf8remaining], 0
    jne .Lpgs_step_bad
    mov qword ptr [rbx + GPC_stringstate], 1
.Lpgs_terminator:
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_stringcursor]
    add rsi, [rbx + GPC_stringlen]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgs_pending
    test eax, eax
    jne .Lpgs_step_bad
    mov rax, [rbx + GPC_stringlen]
    add [rbx + GPC_stringbytes], rax
    inc rax
    add [rbx + GPC_stringcursor], rax
    mov qword ptr [rbx + GPC_stringstate], 2
.Lpgs_complete:
    xor eax, eax
.Lpgs_exit:
    EPILOGUE
.Lpgs_pending:
    mov eax, 1
    EPILOGUE
.Lpgs_step_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    EPILOGUE

FN pg_fields_step
    PROLOGUE
    mov rbx, rdi
.Lpgf_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpgf_pending
    cmp qword ptr [rbx + GPC_fieldindex], 5
    jae .Lpgf_next
    cmp qword ptr [rbx + GPC_fieldtarget], 0
    jne .Lpgf_string
    mov rax, [rbx + GPC_fieldindex]
    shl rax, 4
    lea rax, [rbx + rax + GPC_spans]
    mov rsi, [rax]
    mov rdx, [rax + 8]
    test rsi, rsi
    jnz 1f
    test rdx, rdx
    jnz .Lpgs_step_bad
    cmp qword ptr [rbx + GPC_fieldindex], 4
    jne .Lpgs_step_bad
    inc qword ptr [rbx + GPC_fieldindex]
    inc qword ptr [rbx + GPC_units]
    jmp .Lpgf_again
1:  xor ecx, ecx
    cmp qword ptr [rbx + GPC_fieldindex], 4
    jne 2f
    test rdx, rdx
    jz .Lpgs_step_bad
2:  cmp qword ptr [rbx + GPC_fieldindex], 0
    jne 3f
    cmp qword ptr [rbx + GPC_mode], 1
    jne 3f
    test rdx, rdx
    jz .Lpgs_step_bad
    cmp rdx, 128
    ja .Lpgs_step_bad
    mov ecx, 1
3:  mov rdi, rbx
    call pg_string_begin
    test rax, rax
    js .Lpgs_exit
    mov qword ptr [rbx + GPC_fieldtarget], 1
.Lpgf_string:
    mov rdi, rbx
    call pg_string_step
    test rax, rax
    js .Lpgs_exit
    jnz .Lpgf_pending
    inc qword ptr [rbx + GPC_fieldindex]
    inc qword ptr [rbx + GPC_units]
    mov qword ptr [rbx + GPC_fieldtarget], 0
    jmp .Lpgf_again
.Lpgf_next:
    mov qword ptr [rbx + GPC_phase], GPC_WORDS
    mov qword ptr [rbx + GPC_recordindex], 0
    mov qword ptr [rbx + GPC_recordread], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_fieldvalue], 0
    mov qword ptr [rbx + GPC_fieldtarget], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    mov qword ptr [rbx + GPC_occupied], 0
    inc qword ptr [rbx + GPC_units]
.Lpgf_pending:
    mov eax, 1
    EPILOGUE
.Lpgs_bad:
    mov rsi, -EV_BAD_GRAMMAR
    jmp pg_fail
