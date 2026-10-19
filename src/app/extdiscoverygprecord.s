# Bounded inline rule and byte-array checks. Scratch is read only after copy.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.if REG_SIZE != 40
.error "typed grammar REG schema changed"
.endif
.text
FN pg_rule_step
    PROLOGUE
    mov rbx, rdi
.Lpgr_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpgr_pending
    mov r12d, 40
    mov r13, [rbx + GPC_regions]
    mov r14, [rbx + GPC_regionoffset]
    cmp qword ptr [rbx + GPC_phase], GPC_REGIONS
    je 1f
    mov r12d, 24
    mov r13, [rbx + GPC_lines]
    mov r14, [rbx + GPC_lineoffset]
1:  mov rax, [rbx + GPC_recordindex]
    cmp rax, r13
    jae .Lpgr_next_phase
    mov rcx, [rbx + GPC_fieldindex]
    test rcx, rcx
    jz .Lpgr_copy
    cmp rcx, 1
    je .Lpgr_metadata
    cmp rcx, 2
    je .Lpgr_tokens
    cmp rcx, 3
    jne .Lpgr_bad
    cmp r12, 40
    jne .Lpgr_bad
    mov rdi, rbx
    lea rsi, [rbx + GPC_rstart]
    add rsi, [rbx + GPC_tokenfirst]
    mov edx, 1
    call pg_write_byte
    test rax, rax
    jz .Lpgr_pending
    jmp .Lpgr_complete
.Lpgr_copy:
    cmp [rbx + GPC_recordread], r12
    jae 3f
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    imul rax, r12
    add rax, r14
    add rax, [rbx + GPC_recordread]
    add rax, [rbx + GPC_wire]
    mov rdi, rbx
    mov rsi, rax
    call pg_read_byte
    test rdx, rdx
    jz .Lpgr_pending
    mov [rbx + GPC_copybyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_record]
    add rsi, [rbx + GPC_recordread]
    mov rdx, [rbx + GPC_copybyte]
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpgr_pending
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_recordread]
    jmp .Lpgr_again
3:  mov qword ptr [rbx + GPC_fieldindex], 1
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_fieldvalue], 0
    jmp .Lpgr_again
.Lpgr_metadata:
    lea rsi, [rbx + GPC_record + 32]
    cmp r12, 40
    je 1f
    lea rsi, [rbx + GPC_record + 16]
1:  add rsi, [rbx + GPC_fieldbyte]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgr_pending
    mov rcx, [rbx + GPC_fieldbyte]
    cmp r12, 40
    jne .Lpgr_line_metadata
    test rcx, rcx
    jnz 2f
    cmp eax, 15
    ja .Lpgr_bad
    mov [rbx + GPC_tokenslen], rax
2:  cmp rcx, 1
    jne 3f
    cmp eax, 15
    ja .Lpgr_bad
    mov [rbx + GPC_tokenelen], rax
3:  cmp rcx, 2
    jne 4f
    cmp eax, C_COUNT
    jae .Lpgr_bad
4:  cmp rcx, 4
    jb 5f
    cmp rcx, 5
    ja 6f
    cmp eax, 1
    ja .Lpgr_bad
    jmp 5f
6:  test eax, eax
    jne .Lpgr_bad
5:  jmp .Lpgr_metadata_advance
.Lpgr_line_metadata:
    and ecx, 3
    shl ecx, 3
    shl rax, cl
    or [rbx + GPC_fieldvalue], rax
    mov rcx, [rbx + GPC_fieldbyte]
    cmp rcx, 3
    jne 1f
    mov rax, [rbx + GPC_fieldvalue]
    cmp rax, 15
    ja .Lpgr_bad
    mov [rbx + GPC_tokenslen], rax
    mov qword ptr [rbx + GPC_fieldvalue], 0
1:  cmp rcx, 7
    jne .Lpgr_metadata_advance
    cmp qword ptr [rbx + GPC_fieldvalue], C_COUNT
    jae .Lpgr_bad
.Lpgr_metadata_advance:
    inc qword ptr [rbx + GPC_fieldbyte]
    cmp qword ptr [rbx + GPC_fieldbyte], 8
    jb .Lpgr_again
    mov qword ptr [rbx + GPC_fieldindex], 2
    mov qword ptr [rbx + GPC_fieldbyte], 0
    jmp .Lpgr_again
.Lpgr_tokens:
    mov r13, [rbx + GPC_fieldbyte]
    lea rsi, [rbx + GPC_record]
    add rsi, r13
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgr_pending
    test r13, r13
    jnz 1f
    mov [rbx + GPC_tokenfirst], rax
1:  mov rcx, [rbx + GPC_tokenslen]
    cmp r13, 16
    jb 2f
    mov rcx, [rbx + GPC_tokenelen]
2:  mov rdx, r13
    and edx, 15
    cmp rdx, rcx
    jb 3f
    test eax, eax
    jne .Lpgr_bad
    jmp 4f
3:  test eax, eax
    jz .Lpgr_bad
4:  inc qword ptr [rbx + GPC_fieldbyte]
    mov ecx, 32
    cmp r12, 40
    je 5f
    mov ecx, 16
5:  cmp [rbx + GPC_fieldbyte], rcx
    jb .Lpgr_again
    cmp r12, 40
    jne .Lpgr_complete
    mov qword ptr [rbx + GPC_fieldindex], 3
    jmp .Lpgr_again
.Lpgr_complete:
    inc qword ptr [rbx + GPC_recordindex]
    inc qword ptr [rbx + GPC_units]
    mov qword ptr [rbx + GPC_recordread], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    jmp .Lpgr_again
.Lpgr_next_phase:
    cmp r12, 40
    jne 1f
    mov qword ptr [rbx + GPC_phase], GPC_LINES
    mov qword ptr [rbx + GPC_recordindex], 0
    mov qword ptr [rbx + GPC_recordread], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    jmp 2f
1:  mov qword ptr [rbx + GPC_phase], GPC_IDENT
    mov qword ptr [rbx + GPC_arrayindex], 0
    mov qword ptr [rbx + GPC_firstnul], -1
    mov qword ptr [rbx + GPC_comparehave], 0
2:  inc qword ptr [rbx + GPC_units]
.Lpgr_pending:
    mov eax, 1
    EPILOGUE
.Lpgr_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    EPILOGUE

FN pg_arrays_step
    PROLOGUE
    mov rbx, rdi
.Lpga_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpga_pending
    mov r12, [rbx + GPC_arrayindex]
    mov r13, [rbx + GPC_phase]
    cmp r13, GPC_RSTART_INIT
    je .Lpga_zero
    cmp r13, GPC_WCHAR_INIT
    je .Lpga_classify
    cmp r13, GPC_IDENT
    je .Lpga_small_array
    cmp r13, GPC_PREFIX
    je .Lpga_small_array
    cmp r13, GPC_RSTART_CHECK
    je .Lpga_compare
    cmp r13, GPC_WCHAR_CHECK
    je .Lpga_compare
    jmp .Lpgr_bad
.Lpga_zero:
    cmp r12, 256
    jae 1f
    lea rsi, [rbx + GPC_rstart]
    add rsi, r12
    xor edx, edx
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpga_pending
    inc qword ptr [rbx + GPC_arrayindex]
    jmp .Lpga_again
1:  mov qword ptr [rbx + GPC_arrayindex], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    mov qword ptr [rbx + GPC_phase], GPC_WCHAR_INIT
    inc qword ptr [rbx + GPC_units]
    jmp .Lpga_pending
.Lpga_classify:
    cmp r12, 256
    jae 3f
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    cmp qword ptr [rbx + GPC_budget], 0
    je .Lpga_pending
    dec qword ptr [rbx + GPC_budget]
    inc qword ptr [rbx + GPC_bytes]
    mov rdi, r12
    call is_ident
    mov [rbx + GPC_copybyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_wchar]
    add rsi, r12
    mov rdx, [rbx + GPC_copybyte]
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpga_pending
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_arrayindex]
    jmp .Lpga_again
3:  mov qword ptr [rbx + GPC_recordindex], 0
    mov qword ptr [rbx + GPC_recordread], 0
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_fieldbyte], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    mov qword ptr [rbx + GPC_phase], GPC_REGIONS
    inc qword ptr [rbx + GPC_units]
    jmp .Lpga_pending
.Lpga_small_array:
    cmp r12, 32
    jae .Lpga_small_done
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_arrays]
    cmp r13, GPC_IDENT
    je 1f
    add rsi, 32
1:  add rsi, r12
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpga_pending
    cmp qword ptr [rbx + GPC_firstnul], -1
    jne 4f
    test eax, eax
    jnz 3f
    cmp r12, 30
    ja .Lpgr_bad
    mov [rbx + GPC_firstnul], r12
    jmp 4f
3:  cmp r13, GPC_IDENT
    jne 4f
    mov [rbx + GPC_copybyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_wchar]
    add rsi, [rbx + GPC_copybyte]
    mov edx, 1
    mov rdi, rbx
    call pg_write_byte
    test rax, rax
    jz .Lpga_pending
    mov qword ptr [rbx + GPC_comparehave], 0
4:  inc qword ptr [rbx + GPC_arrayindex]
    jmp .Lpga_again
.Lpga_small_done:
    cmp qword ptr [rbx + GPC_firstnul], -1
    je .Lpgr_bad
    mov qword ptr [rbx + GPC_arrayindex], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    cmp r13, GPC_IDENT
    jne 1f
    mov qword ptr [rbx + GPC_firstnul], -1
    mov qword ptr [rbx + GPC_phase], GPC_PREFIX
    jmp 2f
1:  mov qword ptr [rbx + GPC_phase], GPC_RSTART_CHECK
2:  inc qword ptr [rbx + GPC_units]
    jmp .Lpga_pending
.Lpga_compare:
    cmp r12, 256
    jae .Lpga_compare_done
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 2f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_arrays]
    add rsi, 64
    cmp r13, GPC_RSTART_CHECK
    je 1f
    add rsi, 256
1:  add rsi, r12
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpga_pending
    mov [rbx + GPC_comparebyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
2:  lea rsi, [rbx + GPC_rstart]
    cmp r13, GPC_RSTART_CHECK
    je 3f
    lea rsi, [rbx + GPC_wchar]
3:  add rsi, r12
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpga_pending
    cmp rax, [rbx + GPC_comparebyte]
    jne .Lpgr_bad
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_arrayindex]
    jmp .Lpga_again
.Lpga_compare_done:
    mov qword ptr [rbx + GPC_arrayindex], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    cmp r13, GPC_RSTART_CHECK
    jne 1f
    mov qword ptr [rbx + GPC_phase], GPC_WCHAR_CHECK
    jmp 2f
1:  mov qword ptr [rbx + GPC_phase], GPC_FIELDS
    mov rax, [rbx + GPC_pool]
    mov [rbx + GPC_stringcursor], rax
    mov qword ptr [rbx + GPC_fieldindex], 0
    mov qword ptr [rbx + GPC_fieldtarget], 0
    mov qword ptr [rbx + GPC_stringread], 0
    mov qword ptr [rbx + GPC_utf8remaining], 0
2:  inc qword ptr [rbx + GPC_units]
.Lpga_pending:
    mov eax, 1
    EPILOGUE
