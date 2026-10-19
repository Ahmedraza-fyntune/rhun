# Raw and dirty known fields share counted matching; unknown fields remain in their owners.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.section .rodata
esvf_pinned: .ascii "pinned"
esvf_disabled: .ascii "disabled"
esvf_setting: .ascii "setting."
.text
FN esv_raw_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + EV_phase]
    cmp rax, EVP_RAW_NEXT
    je .Lraw_next
    cmp rax, EVP_RAW_SECTION
    je .Lraw_section
    cmp rax, EVP_RAW_KEY
    je .Lraw_key
    cmp rax, EVP_RAW_LOOKUP
    je .Lraw_lookup
    cmp rax, EVP_RAW_COMPARE
    je .Lraw_compare
    jmp .Lraw_bad
.Lraw_next:
    cmp qword ptr [rbx + EV_phasesleft], 0
    je .Lraw_return
    mov rdi, [rbx + EV_cursor]
    mov rsi, [rbx + EV_bytesleft]
    mov rdx, [rbx + EV_phasesleft]
    call ext_settings_ini_step_budget
    cmp rdx, [rbx + EV_bytesleft]
    ja .Lraw_bad
    cmp rcx, [rbx + EV_phasesleft]
    ja .Lraw_bad
    sub [rbx + EV_bytesleft], rdx
    sub [rbx + EV_phasesleft], rcx
    test rax, rax
    js .Lraw_done
    jz .Lraw_return
    cmp rax, 2
    je 1f
    cmp rax, 1
    jne .Lraw_bad
    mov rdi, [rbx + EV_cursor]
    lea rsi, [rbx + EV_rawsection]
    call ext_settings_ini_row
    test rax, rax
    jnz .Lraw_done
    mov qword ptr [rbx + EV_workflags], EVF_RAW
    mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_rawkind], 0
    mov qword ptr [rbx + EV_phase], EVP_RAW_SECTION
    jmp .Lraw_return
1:  mov qword ptr [rbx + EV_dirtyslot], 0
    mov qword ptr [rbx + EV_phase], EVP_DIRTY_NEXT
    jmp .Lraw_return
.Lraw_section:
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lraw_input_error
    mov r12, [rax + EC_section]
    mov rax, [rax + EC_seclen]
    cmp [rbx + EV_seclen], rax
    jne .Lraw_skip
    mov r13, [rbx + EV_section]
1:  mov rcx, [rbx + EV_matchpos]
    cmp rcx, [rbx + EV_seclen]
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lraw_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp al, [r13 + rcx]
    jne .Lraw_skip
    inc qword ptr [rbx + EV_matchpos]
    jmp 1b
2:  mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_phase], EVP_RAW_KEY
    jmp .Lraw_return
.Lraw_key:
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lraw_input_error
    mov r12, [rax + EC_key]
    mov r13, [rax + EC_keylen]
    cmp qword ptr [rbx + EV_rawkind], 0
    jne 3f
    cmp r13, 6
    je 1f
    cmp r13, 8
    je 2f
    jb .Lraw_skip
    mov qword ptr [rbx + EV_rawkind], 3
    jmp 3f
1:  mov qword ptr [rbx + EV_rawkind], 1
    jmp 3f
2:  mov qword ptr [rbx + EV_rawkind], 2
3:  mov r14d, 8
    lea r15, [rip + esvf_setting]
    cmp qword ptr [rbx + EV_rawkind], 3
    je 4f
    lea r15, [rip + esvf_disabled]
    cmp qword ptr [rbx + EV_rawkind], 2
    je 4f
    lea r15, [rip + esvf_pinned]
    mov r14d, 6
4:  mov rcx, [rbx + EV_matchpos]
    cmp rcx, r14
    jae .Lraw_prefix_done
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lraw_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp al, [r15 + rcx]
    jne .Lraw_skip
    inc qword ptr [rbx + EV_matchpos]
    jmp 4b
.Lraw_prefix_done:
    cmp qword ptr [rbx + EV_rawkind], 3
    jne .Lraw_normalize
    cmp qword ptr [rbx + EV_scanpos], 0
    jne 1f
    mov qword ptr [rbx + EV_scanpos], 8
    mov qword ptr [rbx + EV_hash], 5381
1:  mov rcx, [rbx + EV_scanpos]
    cmp rcx, r13
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lraw_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    mov rdx, [rbx + EV_hash]
    mov r8, rdx
    shl rdx, 5
    add rdx, r8
    xor rdx, rax
    mov [rbx + EV_hash], rdx
    inc qword ptr [rbx + EV_scanpos]
    jmp 1b
2:  mov rax, [rbx + EV_hash]
    and eax, ESV_BUCKETS - 1
    mov [rbx + EV_probe], rax
    mov qword ptr [rbx + EV_phase], EVP_RAW_LOOKUP
    jmp .Lraw_return
.Lraw_lookup:
    mov rcx, [rbx + EV_probe]
    mov rax, [rbx + EV_buckets + rcx * 8]
    test rax, rax
    jz .Lraw_skip
    dec rax
    mov [rbx + EV_rowindex], rax
    imul r12, rax, EVR_SIZE
    lea r12, [rbx + r12 + EV_rows]
    mov rax, [rbx + EV_hash]
    cmp [r12 + EVR_hash], rax
    jne .Lraw_probe_next
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lraw_input_error
    mov rax, [rax + EC_keylen]
    sub rax, 8
    cmp [r12 + EVR_keylen], rax
    jne .Lraw_probe_next
    mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_phase], EVP_RAW_COMPARE
    jmp .Lraw_return
.Lraw_compare:
    mov rdi, rbx
    call esv_input_fields
    test rax, rax
    jz .Lraw_input_error
    mov r12, [rax + EC_key]
    add r12, 8
    imul r13, [rbx + EV_rowindex], EVR_SIZE
    lea r13, [rbx + r13 + EV_rows]
    mov r14, [r13 + EVR_key]
1:  mov rcx, [rbx + EV_matchpos]
    cmp rcx, [r13 + EVR_keylen]
    jae .Lraw_normalize
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lraw_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp al, [r14 + rcx]
    jne .Lraw_probe_next
    inc qword ptr [rbx + EV_matchpos]
    jmp 1b
.Lraw_probe_next:
    inc qword ptr [rbx + EV_probe]
    and qword ptr [rbx + EV_probe], ESV_BUCKETS - 1
    mov qword ptr [rbx + EV_phase], EVP_RAW_LOOKUP
    jmp .Lraw_return
.Lraw_normalize:
    mov qword ptr [rbx + EV_subphase], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_seen], 0
    mov qword ptr [rbx + EV_number], 0
    mov qword ptr [rbx + EV_phase], EVP_NORMALIZE
    jmp .Lraw_return
.Lraw_skip:
    mov rdi, rbx
    call esv_field_advance
    jmp .Lraw_done
.Lraw_input_error:
    mov rax, rdx
    jmp .Lraw_done
.Lraw_return:
    xor eax, eax
.Lraw_done:
    EPILOGUE
.Lraw_bad:
    mov rax, -22
    EPILOGUE
