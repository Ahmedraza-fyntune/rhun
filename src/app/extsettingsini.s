# Resumable counted INI spans over immutable helper-validated complete bytes.
.include "rhun.inc"
.include "app/extsettingsini.inc"
.text
FN ext_settings_ini_begin
    test rdi, rdi
    jz .Lesi_bad_begin
    cmp qword ptr [rdi + ESB_ready], 1
    jne .Lesi_bad_begin
    cmp qword ptr [rdi + ESB_refs], 0
    jle .Lesi_bad_begin
    PROLOGUE
    mov rbx, rdi
    mov edi, ESI_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz 2f
    mov r12, rax
    mov rdi, rbx
    call ext_settings_snapshot_retain
    test rax, rax
    js 1f
    mov [r12 + ESI_snapshot], rbx
    mov qword ptr [r12 + ESI_phase], ESIP_SCAN
    mov rax, r12
    xor edx, edx
    EPILOGUE
1:  mov rbx, rax
    mov rdi, r12
    call ext_settings_memory_free
    mov rdx, rbx
    xor eax, eax
2:  EPILOGUE
.Lesi_bad_begin:
    xor eax, eax
    mov rdx, -22
    ret
FN ext_settings_ini_free
    test rdi, rdi
    jz 1f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ESI_snapshot]
    call ext_settings_snapshot_release
    mov rdi, rbx
    call ext_settings_memory_free
    EPILOGUE
1:  xor eax, eax
    ret
FN ext_settings_ini_advance
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + ESI_phase], ESIP_ROW
    jne 1f
    mov rax, [rdi + ESI_pos]
    mov [rdi + ESI_start], rax
    mov qword ptr [rdi + ESI_phase], ESIP_SCAN
    xor eax, eax
    ret
1:  mov rax, -22
    ret
# row(cursor,out48), spans borrowed from the cursor's retained immutable snapshot.
FN ext_settings_ini_row
    test rdi, rdi
    jz 2f
    test rsi, rsi
    jz 2f
    cmp qword ptr [rdi + ESI_phase], ESIP_ROW
    jne 1f
    mov rax, [rdi + ESI_section]
    mov [rsi], rax
    mov rax, [rdi + ESI_seclen]
    mov [rsi + 8], rax
    mov rax, [rdi + ESI_snapshot]
    mov rax, [rax + ESB_bytes]
    mov rcx, [rdi + ESI_keyleft]
    lea rdx, [rax + rcx]
    mov [rsi + 16], rdx
    mov rdx, [rdi + ESI_keyright]
    sub rdx, rcx
    mov [rsi + 24], rdx
    mov rcx, [rdi + ESI_valleft]
    add rax, rcx
    mov [rsi + 32], rax
    mov rdx, [rdi + ESI_valright]
    sub rdx, rcx
    mov [rsi + 40], rdx
    xor eax, eax
    ret
1:  mov rax, -11
    ret
2:  mov rax, -22
    ret

# step(cursor,budget1..65536)->0pending/1row/2done/-errno,
# RDX actual byte inspections, RCX phase actions. A ready row is never overwritten.
FN ext_settings_ini_step
    mov edx, 1024
    jmp ext_settings_ini_step_budget
# Internal composition entry. Both budgets are shared remaining allowances.
# RDX transitions1..1024 on entry; returned RDX bytes, RCX actual phase actions.
FN ext_settings_ini_step_budget
    test rdx, rdx
    jz .Lesi_invalid
    cmp rdx, 1024
    ja .Lesi_invalid
    test rdi, rdi
    jz .Lesi_invalid
    test rsi, rsi
    jz .Lesi_invalid
    cmp rsi, 65536
    ja .Lesi_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rsi
    mov [rsp + 16], rdx
    xor r13d, r13d
    mov qword ptr [rsp + 8], 0
    mov r14, [rbx + ESI_snapshot]
    mov r15, [r14 + ESB_bytes]
.Lesi_loop:
    cmp r13, [rsp + 16]
    jae .Lesi_pending
    mov rax, [rbx + ESI_phase]
    cmp rax, ESIP_ROW
    je .Lesi_row
    cmp rax, ESIP_DONE
    je .Lesi_done
    cmp rax, ESIP_FAILED
    je .Lesi_failed
    test r12, r12
    jz .Lesi_pending
    cmp [rsp + 8], rax
    je 1f
    inc r13
    mov [rsp + 8], rax
1:  cmp rax, ESIP_SCAN
    je .Lesi_scan
    cmp rax, ESIP_CLASSIFY
    je .Lesi_classify
    cmp rax, ESIP_CLOSE
    je .Lesi_close
    cmp rax, ESIP_SPLIT
    je .Lesi_split
    # Trim phases share a persisted pair of offsets, no whole-span helper.
    cmp rax, ESIP_LEFT
    je .Lesi_line_left
    cmp rax, ESIP_RIGHT
    je .Lesi_line_right
    cmp rax, ESIP_SECLEFT
    je .Lesi_sec_left
    cmp rax, ESIP_SECRIGHT
    je .Lesi_sec_right
    cmp rax, ESIP_KEYLEFT
    je .Lesi_key_left
    cmp rax, ESIP_KEYRIGHT
    je .Lesi_key_right
    cmp rax, ESIP_VALLEFT
    je .Lesi_val_left
    cmp rax, ESIP_VALRIGHT
    je .Lesi_val_right
    jmp .Lesi_protocol
.Lesi_scan:
    mov rcx, [rbx + ESI_pos]
    cmp rcx, [r14 + ESB_length]
    ja .Lesi_protocol
    je .Lesi_eof_line
    movzx eax, byte ptr [r15 + rcx]
    dec r12
    inc qword ptr [rbx + ESI_pos]
    cmp eax, 10
    jne .Lesi_loop
    mov [rbx + ESI_end], rcx
    jmp .Lesi_line_ready
.Lesi_eof_line:
    cmp [rbx + ESI_start], rcx
    je .Lesi_mark_done
    mov [rbx + ESI_end], rcx
.Lesi_line_ready:
    mov rax, [rbx + ESI_start]
    mov [rbx + ESI_left], rax
    mov rax, [rbx + ESI_end]
    mov [rbx + ESI_right], rax
    mov qword ptr [rbx + ESI_phase], ESIP_LEFT
    jmp .Lesi_loop
.Lesi_line_left:
    lea r8, [rbx + ESI_left]
    lea r9, [rbx + ESI_right]
    mov r10d, ESIP_RIGHT
    jmp .Lesi_trim_left
.Lesi_sec_left:
    lea r8, [rbx + ESI_left]
    lea r9, [rbx + ESI_right]
    mov r10d, ESIP_SECRIGHT
    jmp .Lesi_trim_left
.Lesi_key_left:
    lea r8, [rbx + ESI_keyleft]
    lea r9, [rbx + ESI_keyright]
    mov r10d, ESIP_KEYRIGHT
    jmp .Lesi_trim_left
.Lesi_val_left:
    lea r8, [rbx + ESI_valleft]
    lea r9, [rbx + ESI_valright]
    mov r10d, ESIP_VALRIGHT
.Lesi_trim_left:
    mov rcx, [r8]
    cmp rcx, [r9]
    ja .Lesi_protocol
    je .Lesi_trim_next
    movzx eax, byte ptr [r15 + rcx]
    dec r12
    cmp eax, ' '
    je .Lesi_left_more
    cmp eax, 9
    je .Lesi_left_more
    cmp eax, 13
    jne .Lesi_trim_next
.Lesi_left_more:
    inc qword ptr [r8]
    jmp .Lesi_loop
.Lesi_trim_next:
    mov [rbx + ESI_phase], r10
    jmp .Lesi_loop
.Lesi_line_right:
    lea r8, [rbx + ESI_left]
    lea r9, [rbx + ESI_right]
    mov r10d, ESIP_CLASSIFY
    jmp .Lesi_trim_right
.Lesi_sec_right:
    lea r8, [rbx + ESI_left]
    lea r9, [rbx + ESI_right]
    xor r10d, r10d
    jmp .Lesi_trim_right
.Lesi_key_right:
    lea r8, [rbx + ESI_keyleft]
    lea r9, [rbx + ESI_keyright]
    mov r10d, ESIP_VALLEFT
    jmp .Lesi_trim_right
.Lesi_val_right:
    lea r8, [rbx + ESI_valleft]
    lea r9, [rbx + ESI_valright]
    mov r10d, ESIP_ROW
.Lesi_trim_right:
    mov rcx, [r9]
    cmp rcx, [r8]
    jb .Lesi_protocol
    je .Lesi_right_done
    movzx eax, byte ptr [r15 + rcx - 1]
    dec r12
    cmp eax, ' '
    je .Lesi_right_more
    cmp eax, 9
    je .Lesi_right_more
    cmp eax, 13
    jne .Lesi_right_done
.Lesi_right_more:
    dec qword ptr [r9]
    jmp .Lesi_loop
.Lesi_right_done:
    cmp qword ptr [rbx + ESI_phase], ESIP_KEYRIGHT
    jne 1f
    mov rax, [r8]
    cmp rax, [r9]
    je .Lesi_protocol
1:  test r10, r10
    jnz .Lesi_trim_next
    mov rax, [rbx + ESI_left]
    lea rcx, [r15 + rax]
    mov [rbx + ESI_section], rcx
    mov rcx, [rbx + ESI_right]
    sub rcx, rax
    mov [rbx + ESI_seclen], rcx
    jmp .Lesi_skip_line
.Lesi_classify:
    mov rcx, [rbx + ESI_left]
    cmp rcx, [rbx + ESI_right]
    je .Lesi_skip_line
    movzx eax, byte ptr [r15 + rcx]
    dec r12
    cmp eax, '#'
    je .Lesi_skip_line
    cmp eax, ';'
    je .Lesi_skip_line
    cmp eax, '['
    jne .Lesi_split_ready
    mov qword ptr [rbx + ESI_phase], ESIP_CLOSE
    jmp .Lesi_loop
.Lesi_close:
    mov rcx, [rbx + ESI_right]
    movzx eax, byte ptr [r15 + rcx - 1]
    dec r12
    cmp eax, ']'
    jne .Lesi_split_ready
    inc qword ptr [rbx + ESI_left]
    dec qword ptr [rbx + ESI_right]
    mov qword ptr [rbx + ESI_phase], ESIP_SECLEFT
    jmp .Lesi_loop
.Lesi_split_ready:
    mov rax, [rbx + ESI_left]
    mov [rbx + ESI_cursor], rax
    mov qword ptr [rbx + ESI_phase], ESIP_SPLIT
    jmp .Lesi_loop
.Lesi_split:
    mov rcx, [rbx + ESI_cursor]
    cmp rcx, [rbx + ESI_right]
    jae .Lesi_protocol
    movzx eax, byte ptr [r15 + rcx]
    dec r12
    cmp eax, '='
    je .Lesi_equal
    inc qword ptr [rbx + ESI_cursor]
    jmp .Lesi_loop
.Lesi_equal:
    mov rax, [rbx + ESI_left]
    mov [rbx + ESI_keyleft], rax
    mov [rbx + ESI_keyright], rcx
    inc rcx
    mov [rbx + ESI_valleft], rcx
    mov rax, [rbx + ESI_right]
    mov [rbx + ESI_valright], rax
    mov qword ptr [rbx + ESI_phase], ESIP_KEYLEFT
    jmp .Lesi_loop
.Lesi_skip_line:
    mov rax, [rbx + ESI_pos]
    mov [rbx + ESI_start], rax
    mov qword ptr [rbx + ESI_phase], ESIP_SCAN
    jmp .Lesi_loop
.Lesi_mark_done:
    mov qword ptr [rbx + ESI_phase], ESIP_DONE
.Lesi_done:
    mov eax, 2
    jmp .Lesi_return
.Lesi_protocol:
    mov qword ptr [rbx + ESI_error], -22
    mov qword ptr [rbx + ESI_phase], ESIP_FAILED
.Lesi_failed:
    mov rax, [rbx + ESI_error]
    jmp .Lesi_return
.Lesi_pending:
    xor eax, eax
    jmp .Lesi_return
.Lesi_row:
    mov eax, 1
.Lesi_return:
    mov rdx, [rsp]
    sub rdx, r12
    mov rcx, r13
    EPILOGUE
.Lesi_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
