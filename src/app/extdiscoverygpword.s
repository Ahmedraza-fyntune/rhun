# Physical word records are decoded as offsets. No wire value is a pointer.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.text
# ctx,physical ordinal,local decoded target kind. No payload work or allocation.
FN pg_word_record_begin
    cmp rsi, [rdi + GPC_wcap]
    jae .Lpgw_bad
    cmp rdx, GPC_candidate
    je 1f
    cmp rdx, GPC_probeoffset
    jne .Lpgw_bad
1:  shl rsi, 4
    add rsi, [rdi + GPC_words]
    mov [rdi + GPC_recordoffset], rsi
    mov [rdi + GPC_decodebase], rdx
    mov qword ptr [rdi + GPC_recordstate], 0
    mov qword ptr [rdi + GPC_recordread], 0
    mov qword ptr [rdi + GPC_fieldbyte], 0
    mov qword ptr [rdi + GPC_fieldvalue], 0
    mov qword ptr [rdi + GPC_comparehave], 0
    xor eax, eax
    ret

FN pg_word_record_step
    PROLOGUE
    mov rbx, rdi
.Lpgw_record_again:
    cmp qword ptr [rbx + GPC_recordstate], 2
    je .Lpgw_record_done
    cmp qword ptr [rbx + GPC_recordstate], 1
    je .Lpgw_decode
    cmp qword ptr [rbx + GPC_recordread], 16
    jae 3f
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_recordoffset]
    add rsi, [rbx + GPC_recordread]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgw_pending
    mov [rbx + GPC_copybyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_record]
    add rsi, [rbx + GPC_recordread]
    mov rdx, [rbx + GPC_copybyte]
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpgw_pending
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_recordread]
    jmp .Lpgw_record_again
3:  mov qword ptr [rbx + GPC_recordstate], 1
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_fieldvalue], 0
.Lpgw_decode:
    lea rsi, [rbx + GPC_record]
    add rsi, [rbx + GPC_fieldbyte]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgw_pending
    mov rcx, [rbx + GPC_fieldbyte]
    cmp rcx, 8
    jb 1f
    and ecx, 3
1:  shl ecx, 3
    shl rax, cl
    or [rbx + GPC_fieldvalue], rax
    mov rcx, [rbx + GPC_fieldbyte]
    mov rdx, [rbx + GPC_decodebase]
    cmp rcx, 7
    je 2f
    add rdx, 8
    cmp rcx, 11
    je 2f
    add rdx, 8
    cmp rcx, 15
    jne 3f
2:  mov rax, [rbx + GPC_fieldvalue]
    mov [rbx + rdx], rax
    mov qword ptr [rbx + GPC_fieldvalue], 0
3:  inc qword ptr [rbx + GPC_fieldbyte]
    cmp qword ptr [rbx + GPC_fieldbyte], 16
    jb .Lpgw_record_again
    mov qword ptr [rbx + GPC_recordstate], 2
.Lpgw_record_done:
    xor eax, eax
    EPILOGUE
.Lpgw_pending:
    mov eax, 1
    EPILOGUE

FN pg_words_step
    PROLOGUE
    mov rbx, rdi
.Lpgw_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpgw_pending
    mov rsi, [rbx + GPC_recordindex]
    cmp rsi, [rbx + GPC_wcap]
    jae .Lpgw_end
    mov rax, [rbx + GPC_fieldindex]
    cmp rax, 1
    je .Lpgw_read
    cmp rax, 2
    je .Lpgw_validate
    cmp rax, 3
    je .Lpgw_string
    test rax, rax
    jnz .Lpgw_step_bad
    mov rdi, rbx
    mov edx, GPC_candidate
    call pg_word_record_begin
    test rax, rax
    js .Lpgw_exit
    mov qword ptr [rbx + GPC_fieldindex], 1
.Lpgw_read:
    mov rdi, rbx
    call pg_word_record_step
    test rax, rax
    js .Lpgw_exit
    jnz .Lpgw_pending
    mov qword ptr [rbx + GPC_fieldindex], 2
.Lpgw_validate:
    mov rsi, [rbx + GPC_candidate]
    mov rdx, [rbx + GPC_candidatelength]
    test rsi, rsi
    jnz 1f
    or rdx, [rbx + GPC_candidateclass]
    jnz .Lpgw_step_bad
    jmp .Lpgw_complete
1:  test rdx, rdx
    jz .Lpgw_step_bad
    cmp qword ptr [rbx + GPC_candidateclass], C_COUNT
    jae .Lpgw_step_bad
    mov rdi, rbx
    xor ecx, ecx
    call pg_string_begin
    test rax, rax
    js .Lpgw_exit
    mov qword ptr [rbx + GPC_fieldindex], 3
.Lpgw_string:
    mov rdi, rbx
    call pg_string_step
    test rax, rax
    js .Lpgw_exit
    jnz .Lpgw_pending
    inc qword ptr [rbx + GPC_occupied]
.Lpgw_complete:
    inc qword ptr [rbx + GPC_recordindex]
    mov rax, [rbx + GPC_recordindex]
    mov [rbx + GPC_wordindex], rax
    mov qword ptr [rbx + GPC_fieldindex], 0
    inc qword ptr [rbx + GPC_units]
    jmp .Lpgw_again
.Lpgw_end:
    mov rax, [rbx + GPC_occupied]
    cmp rax, [rbx + GPC_declaredoccupied]
    jne .Lpgw_step_bad
    mov rax, [rbx + GPC_stringcursor]
    cmp rax, [rbx + GPC_length]
    jne .Lpgw_step_bad
    mov rax, [rbx + GPC_stringbytes]
    cmp rax, [rbx + GPC_sourcebytes]
    ja .Lpgw_step_bad
    mov qword ptr [rbx + GPC_phase], GPC_REACHABILITY
    mov qword ptr [rbx + GPC_wordindex], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_probes], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_units]
    mov eax, 1
.Lpgw_exit:
    EPILOGUE
.Lpgw_step_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    EPILOGUE
.Lpgw_bad:
    mov rsi, -EV_BAD_GRAMMAR
    jmp pg_fail
