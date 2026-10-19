# Prepared bindings can yield within long combinations and numeric key names.
.include "rhun.inc"
.include "app/keycombo.inc"
.text
# Numerical range validation only. Readability and exclusive ownership are caller contracts.
kc_span:
    test rdi, rdi
    jz .Lkc_invalid
    test dil, 7
    jnz .Lkc_invalid
    mov r8, rdi
    add r8, KC_SIZE
    jc .Lkc_invalid
    cmp rdx, KC_CAP
    ja .Lkc_invalid
    test rdx, rdx
    jz .Lkc_valid
    test rsi, rsi
    jz .Lkc_invalid
    mov r9, rsi
    add r9, rdx
    jc .Lkc_invalid
    cmp rsi, r8
    jae .Lkc_valid
    cmp r9, rdi
    ja .Lkc_invalid
.Lkc_valid:
    xor eax, eax
    ret
.Lkc_invalid:
    mov rax, -22
    ret

FN keys_combo_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call kc_span
    test rax, rax
    js 9f
    mov rdi, rbx
    xor esi, esi
    mov edx, KC_SIZE
    call memset
    mov [rbx + KC_ptr], r12
    mov [rbx + KC_len], r13
    mov qword ptr [rbx + KC_magic], KC_MAGIC
    test r13, r13
    jnz 8f
    mov qword ptr [rbx + KC_phase], KC_DONE
8:  xor eax, eax
9:  EPILOGUE

kc_validate:
    test rdi, rdi
    jz .Lkc_invalid
    test dil, 7
    jnz .Lkc_invalid
    mov rax, rdi
    add rax, KC_SIZE
    jc .Lkc_invalid
    cmp qword ptr [rdi + KC_magic], KC_MAGIC
    jne .Lkc_invalid
    cmp qword ptr [rdi + KC_reserved], 0
    jne .Lkc_invalid
    cmp qword ptr [rdi + KC_phase], KC_FINISH
    ja .Lkc_invalid
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rdi + KC_ptr]
    mov rdx, [rdi + KC_len]
    call kc_span
    test rax, rax
    js .Lkcv_exit
    mov r8, [rbx + KC_cursor]
    cmp r8, [rbx + KC_len]
    ja .Lkcv_invalid
    mov r9, [rbx + KC_start]
    cmp r9, r8
    ja .Lkcv_invalid
    mov rax, r8
    sub rax, r9
    cmp [rbx + KC_length], rax
    ja .Lkcv_invalid
    mov rcx, [rbx + KC_phase]
    cmp rcx, KC_DONE
    je .Lkcv_done
    test rcx, rcx
    jz .Lkcv_valid
    cmp qword ptr [rbx + KC_length], 0
    je .Lkcv_invalid
    cmp [rbx + KC_length], rax
    jne .Lkcv_invalid
    cmp rcx, KC_NUMERIC
    jb .Lkcv_valid
    mov ecx, 2
    cmp qword ptr [rbx + KC_kind], 1
    je 1f
    cmp qword ptr [rbx + KC_kind], 2
    jne .Lkcv_invalid
    mov ecx, 1
1:  cmp [rbx + KC_position], rcx
    jb .Lkcv_invalid
    mov rax, [rbx + KC_position]
    cmp rax, [rbx + KC_length]
    ja .Lkcv_invalid
    jmp .Lkcv_valid
.Lkcv_done:
    cmp r8, [rbx + KC_len]
    jne .Lkcv_invalid
.Lkcv_valid:
    xor eax, eax
    jmp .Lkcv_exit
.Lkcv_invalid:
    mov rax, -22
.Lkcv_exit:
    EPILOGUE

# state, scan-byte budget1..4096, application budget1..16. Fixed lookup reads separately bounded.
FN keys_combo_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .Lkcs_invalid
    cmp r12, 4096
    ja .Lkcs_invalid
    test r13, r13
    jz .Lkcs_invalid
    cmp r13, 16
    ja .Lkcs_invalid
    call kc_validate
    test rax, rax
    js .Lkcs_invalid
    xor r14d, r14d
    xor r15d, r15d
.Lkcs_loop:
    mov rax, [rbx + KC_phase]
    cmp rax, KC_DONE
    je .Lkcs_done
    test r13, r13
    jnz .Lkcs_dispatch
    test rax, rax
    jz .Lkcs_possible_end
    cmp rax, KC_SEPARATOR
    jne .Lkcs_pending
.Lkcs_possible_end:
    mov rax, [rbx + KC_cursor]
    cmp rax, [rbx + KC_len]
    je .Lkcs_complete
    jmp .Lkcs_pending
.Lkcs_dispatch:
    test rax, rax
    jz .Lkcs_next
    cmp rax, KC_SCAN
    je .Lkcs_scan
    cmp rax, KC_APPLY
    je .Lkcs_apply
    cmp rax, KC_SEPARATOR
    je .Lkcs_separator
    cmp rax, KC_NUMERIC
    je .Lkcs_numeric
    jmp .Lkcs_finish
.Lkcs_next:
    mov rcx, [rbx + KC_cursor]
    cmp rcx, [rbx + KC_len]
    je .Lkcs_complete
    test r12, r12
    jz .Lkcs_pending
    mov r8, [rbx + KC_ptr]
    movzx eax, byte ptr [r8 + rcx]
    dec r12
    inc r14
    mov [rbx + KC_start], rcx
    inc rcx
    mov [rbx + KC_cursor], rcx
    mov qword ptr [rbx + KC_length], 1
    mov qword ptr [rbx + KC_phase], KC_SCAN
    cmp al, '+'
    jne .Lkcs_loop
    mov qword ptr [rbx + KC_phase], KC_APPLY
    jmp .Lkcs_loop
.Lkcs_scan:
    mov rcx, [rbx + KC_cursor]
    cmp rcx, [rbx + KC_len]
    je .Lkcs_token_ready
    test r12, r12
    jz .Lkcs_pending
    mov r8, [rbx + KC_ptr]
    movzx eax, byte ptr [r8 + rcx]
    dec r12
    inc r14
    cmp al, '+'
    je .Lkcs_token_ready
    inc qword ptr [rbx + KC_cursor]
    inc qword ptr [rbx + KC_length]
    jmp .Lkcs_loop
.Lkcs_token_ready:
    mov qword ptr [rbx + KC_phase], KC_APPLY
    jmp .Lkcs_loop
.Lkcs_apply:
    mov r8, [rbx + KC_ptr]
    add r8, [rbx + KC_start]
    mov rcx, [rbx + KC_length]
    cmp rcx, 2
    jbe .Lkcs_check_unicode
    cmp word ptr [r8], 0x7830
    je .Lkcs_start_hex
.Lkcs_check_unicode:
    cmp rcx, 5
    jb .Lkcs_lookup
    cmp byte ptr [r8], 'U'
    je .Lkcs_start_unicode
.Lkcs_lookup:
    mov rdi, r8
    mov rsi, rcx
    call keys_combo_token
    test edx, edx
    jz 1f
    or [rbx + KC_mods], edx
    jmp .Lkcs_applied
1:  mov [rbx + KC_key], eax
.Lkcs_applied:
    dec r13
    inc r15
    mov qword ptr [rbx + KC_phase], KC_SEPARATOR
    jmp .Lkcs_loop
.Lkcs_start_hex:
    mov qword ptr [rbx + KC_acc], 0
    mov qword ptr [rbx + KC_position], 2
    mov qword ptr [rbx + KC_kind], 1
    mov qword ptr [rbx + KC_phase], KC_NUMERIC
    jmp .Lkcs_loop
.Lkcs_start_unicode:
    mov qword ptr [rbx + KC_acc], 0
    mov qword ptr [rbx + KC_position], 1
    mov qword ptr [rbx + KC_kind], 2
    mov qword ptr [rbx + KC_phase], KC_NUMERIC
    jmp .Lkcs_loop
.Lkcs_separator:
    mov rcx, [rbx + KC_cursor]
    cmp rcx, [rbx + KC_len]
    je .Lkcs_complete
    test r12, r12
    jz .Lkcs_pending
    mov r8, [rbx + KC_ptr]
    movzx eax, byte ptr [r8 + rcx]
    dec r12
    inc r14
    cmp al, '+'
    jne 2f
    inc qword ptr [rbx + KC_cursor]
2:  mov qword ptr [rbx + KC_phase], KC_NEXT
    jmp .Lkcs_loop
.Lkcs_numeric:
    mov rcx, [rbx + KC_position]
    cmp rcx, [rbx + KC_length]
    je .Lkcs_number_ready
    test r12, r12
    jz .Lkcs_pending
    add rcx, [rbx + KC_start]
    mov r8, [rbx + KC_ptr]
    movzx eax, byte ptr [r8 + rcx]
    dec r12
    inc r14
    lea edx, [rax - '0']
    cmp edx, 9
    jbe .Lkcs_digit
    or eax, 32
    lea edx, [rax - 'a']
    cmp edx, 5
    ja .Lkcs_number_ready
    add edx, 10
.Lkcs_digit:
    mov rax, [rbx + KC_acc]
    shl rax, 4
    add rax, rdx
    mov [rbx + KC_acc], rax
    inc qword ptr [rbx + KC_position]
    jmp .Lkcs_loop
.Lkcs_number_ready:
    mov qword ptr [rbx + KC_phase], KC_FINISH
    jmp .Lkcs_loop
.Lkcs_finish:
    mov eax, [rbx + KC_acc]
    cmp qword ptr [rbx + KC_kind], 1
    je 3f
    mov rcx, [rbx + KC_position]
    cmp rcx, [rbx + KC_length]
    jne .Lkcs_name_fallback
    add eax, 0x1000000
    jmp 3f
.Lkcs_name_fallback:
    mov rdi, [rbx + KC_ptr]
    add rdi, [rbx + KC_start]
    mov rsi, [rbx + KC_length]
    call keysym_name_value
3:  mov [rbx + KC_key], eax
    jmp .Lkcs_applied
.Lkcs_complete:
    mov qword ptr [rbx + KC_phase], KC_DONE
.Lkcs_done:
    xor eax, eax
    jmp .Lkcs_result
.Lkcs_pending:
    mov eax, 1
.Lkcs_result:
    mov rdx, r14
    mov rcx, r15
    EPILOGUE
.Lkcs_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

FN keys_combo_result
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    test rdi, rdi
    jz 9f
    test dil, 7
    jnz 9f
    cmp qword ptr [rdi + KC_magic], KC_MAGIC
    jne 9f
    cmp qword ptr [rdi + KC_phase], KC_DONE
    jne 9f
    cmp qword ptr [rdi + KC_reserved], 0
    jne 9f
    mov r8, [rdi + KC_cursor]
    cmp r8, [rdi + KC_len]
    jne 9f
    mov eax, [rdi + KC_key]
    mov edx, [rdi + KC_mods]
    mov ecx, 1
9:  ret
