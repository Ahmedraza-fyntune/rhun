# Scalar scans share the outer ledger. Integer formatting also advances with budget1.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.section .rodata
esvs_yes: .ascii "yes"
esvs_no: .ascii "no"
.text
FN esv_scalar_step
    PROLOGUE
    mov rbx, rdi
    call esv_input_fields
    test rax, rax
    jz .Lscalar_input_error
    mov r12, [rax + EC_value]
    mov rax, [rbx + EV_normtype]
    cmp rax, SDT_STRING
    je .Lscalar_string
    cmp rax, SDT_BOOL
    je .Lscalar_bool
    cmp rax, SDT_INT
    je .Lscalar_int
    mov rax, -22
    jmp .Lscalar_done
.Lscalar_string:
    mov rax, [rbx + EV_subphase]
    cmp rax, 1
    je .Lscalar_left
    cmp rax, 2
    je .Lscalar_right
    cmp rax, 3
    je .Lscalar_text
    jmp .Lscalar_invalid
.Lscalar_left:
    mov rcx, [rbx + EV_normleft]
    cmp rcx, [rbx + EV_normright]
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp eax, ' '
    je 1f
    cmp eax, 9
    jne 2f
1:  inc qword ptr [rbx + EV_normleft]
    jmp .Lscalar_left
2:  mov qword ptr [rbx + EV_subphase], 2
    jmp .Lscalar_return
.Lscalar_right:
    mov rcx, [rbx + EV_normright]
    cmp rcx, [rbx + EV_normleft]
    jbe 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    movzx eax, byte ptr [r12 + rcx - 1]
    dec qword ptr [rbx + EV_bytesleft]
    cmp eax, ' '
    je 1f
    cmp eax, 9
    jne 2f
1:  dec qword ptr [rbx + EV_normright]
    jmp .Lscalar_right
2:  mov rax, [rbx + EV_normleft]
    mov [rbx + EV_scanpos], rax
    mov qword ptr [rbx + EV_subphase], 3
    jmp .Lscalar_return
.Lscalar_text:
    mov rcx, [rbx + EV_scanpos]
    cmp rcx, [rbx + EV_normright]
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp eax, 10
    je .Lscalar_invalid
    cmp eax, 13
    je .Lscalar_invalid
    inc qword ptr [rbx + EV_scanpos]
    jmp .Lscalar_text
2:  mov rax, [rbx + EV_normright]
    sub rax, [rbx + EV_normleft]
    mov [rbx + EV_worklen], rax
    jmp .Lscalar_accept
.Lscalar_bool:
    mov r13, [rbx + EV_normright]
    lea r14, [rip + esvs_no]
    cmp r13, 2
    je 1f
    cmp r13, 3
    jne .Lscalar_invalid
    lea r14, [rip + esvs_yes]
1:  mov rcx, [rbx + EV_scanpos]
    cmp rcx, r13
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp al, [r14 + rcx]
    jne .Lscalar_invalid
    inc qword ptr [rbx + EV_scanpos]
    jmp 1b
2:  xor eax, eax
    cmp r13, 3
    sete al
    mov [rbx + EV_number], rax
    mov [rbx + EV_worklen], r13
    jmp .Lscalar_accept
.Lscalar_int:
    cmp qword ptr [rbx + EV_subphase], 2
    je .Lscalar_format
    cmp qword ptr [rbx + EV_normright], 0
    je .Lscalar_invalid
1:  mov rcx, [rbx + EV_scanpos]
    cmp rcx, [rbx + EV_normright]
    jae .Lscalar_clamp
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    sub eax, '0'
    cmp eax, 9
    ja .Lscalar_invalid
    mov rdx, [rbx + EV_number]
    cmp rdx, 214748364
    ja 3f
    jb 2f
    cmp eax, 7
    ja 3f
2:  imul rdx, rdx, 10
    add rdx, rax
    jmp 4f
3:  mov edx, 2147483647
4:  mov [rbx + EV_number], rdx
    inc qword ptr [rbx + EV_scanpos]
    jmp 1b
.Lscalar_clamp:
    mov rax, [rbx + EV_number]
    cmp rax, [rbx + EV_min]
    cmovb rax, [rbx + EV_min]
    cmp rax, [rbx + EV_max]
    cmova rax, [rbx + EV_max]
    mov [rbx + EV_number], rax
    mov qword ptr [rbx + EV_normleft], 16
    mov qword ptr [rbx + EV_subphase], 2
    jmp .Lscalar_return
.Lscalar_format:
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lscalar_return
    mov rax, [rbx + EV_number]
    xor edx, edx
    mov ecx, 10
    div rcx
    mov [rbx + EV_number], rax
    add edx, '0'
    dec qword ptr [rbx + EV_normleft]
    mov rcx, [rbx + EV_normleft]
    mov [rbx + EV_decimal + rcx], dl
    dec qword ptr [rbx + EV_bytesleft]
    test rax, rax
    jnz .Lscalar_format
    mov eax, 16
    sub rax, [rbx + EV_normleft]
    mov [rbx + EV_worklen], rax
    or qword ptr [rbx + EV_workflags], EVF_DECIMAL
.Lscalar_accept:
    mov rdi, rbx
    call esv_norm_accept
    jmp .Lscalar_done
.Lscalar_invalid:
    mov rdi, rbx
    call esv_norm_invalid
    jmp .Lscalar_done
.Lscalar_return:
    xor eax, eax
.Lscalar_done:
    EPILOGUE
.Lscalar_input_error:
    mov rax, rdx
    EPILOGUE
