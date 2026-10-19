# Counted option-word normalization, with no retained schema pointer or whole-span scan.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.text
FN esv_choice_step
    PROLOGUE
    mov rbx, rdi
    call esv_input_fields
    test rax, rax
    jz .Lchoice_input_error
    mov r12, [rax + EC_value]
    imul rax, [rbx + EV_rowindex], SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    mov r13, [rax + SD_opts]
    test r13, r13
    jz .Lchoice_invalid
    mov rax, [rbx + EV_subphase]
    cmp rax, 1
    je .Lchoice_skip
    cmp rax, 2
    je .Lchoice_length
    cmp rax, 3
    je .Lchoice_compare
    jmp .Lchoice_invalid
.Lchoice_skip:
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lchoice_return
    mov rcx, [rbx + EV_optionpos]
    cmp rcx, EC_LIMIT
    jae .Lchoice_invalid
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    test eax, eax
    jz .Lchoice_invalid
    cmp eax, ' '
    je 1f
    cmp eax, 9
    je 1f
    mov [rbx + EV_seen], rcx
    mov qword ptr [rbx + EV_subphase], 2
    jmp .Lchoice_return
1:  inc qword ptr [rbx + EV_optionpos]
    jmp .Lchoice_skip
.Lchoice_length:
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lchoice_return
    mov rcx, [rbx + EV_optionpos]
    cmp rcx, EC_LIMIT
    jae .Lchoice_invalid
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    test eax, eax
    jz 2f
    cmp eax, ' '
    je 2f
    cmp eax, 9
    je 2f
    inc qword ptr [rbx + EV_optionpos]
    jmp .Lchoice_length
2:  mov rax, [rbx + EV_optionpos]
    sub rax, [rbx + EV_seen]
    mov [rbx + EV_optionlen], rax
    cmp rax, [rbx + EV_normright]
    jne 3f
    mov qword ptr [rbx + EV_optionmatch], 0
    mov qword ptr [rbx + EV_subphase], 3
    jmp .Lchoice_return
3:  mov qword ptr [rbx + EV_subphase], 1
    jmp .Lchoice_return
.Lchoice_compare:
    mov rcx, [rbx + EV_optionmatch]
    cmp rcx, [rbx + EV_optionlen]
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lchoice_return
    mov rax, [rbx + EV_seen]
    add rax, rcx
    movzx edx, byte ptr [r13 + rax]
    dec qword ptr [rbx + EV_bytesleft]
    cmp dl, [r12 + rcx]
    jne 1f
    inc qword ptr [rbx + EV_optionmatch]
    jmp .Lchoice_compare
1:  mov qword ptr [rbx + EV_subphase], 1
    jmp .Lchoice_return
2:  mov rax, [rbx + EV_normright]
    mov [rbx + EV_worklen], rax
    mov rdi, rbx
    call esv_norm_accept
    jmp .Lchoice_done
.Lchoice_invalid:
    mov rdi, rbx
    call esv_norm_invalid
    jmp .Lchoice_done
.Lchoice_return:
    xor eax, eax
.Lchoice_done:
    EPILOGUE
.Lchoice_input_error:
    mov rax, rdx
    EPILOGUE
