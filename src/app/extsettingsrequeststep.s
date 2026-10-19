# Incremental exact row bytes. No source lookup after immutable batch capture.
.include "rhun.inc"
.include "app/extsettingsrequest.inc"
.text
# step(frame,batch,cursor,budget1..65536)->0pending/1done/-errno,
# RDX emitted bytes,RCX transitions. The caller owns frame/batch through this call.
FN ext_settings_request_step
    test rdi, rdi
    jz .Lrqs_bad_leaf
    test rdx, rdx
    jz .Lrqs_bad_leaf
    test rcx, rcx
    jz .Lrqs_bad_leaf
    cmp rcx, 65536
    ja .Lrqs_bad_leaf
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor r15d, r15d
    mov qword ptr [rsp], 0
    cmp [r13 + ESQ_frame], rbx
    jne .Lrqs_bad
    cmp [r13 + ESQ_batch], r12
    jne .Lrqs_bad
    mov rax, ESQ_DONE
    cmp [r13 + ESQ_magic], rax
    je .Lrqs_done
    mov rax, ESQ_ACTIVE
    cmp [r13 + ESQ_magic], rax
    jne .Lrqs_bad
    cmp qword ptr [rbx + EJF_sealed], 0
    jne .Lrqs_bad
    cmp qword ptr [rbx + EJF_kind], EW_REQUEST
    jne .Lrqs_bad
    cmp qword ptr [rbx + EJF_length], EW_LIMIT
    ja .Lrqs_bad
    mov eax, [rbx + EJF_body + 8]
    test eax, eax
    jz .Lrqs_bad
    cmp eax, 4095
    ja .Lrqs_bad
    add rax, 56
    cmp [r13 + ESQ_pos], rax
    jb .Lrqs_bad
    mov rax, [rbx + EJF_length]
    cmp [r13 + ESQ_pos], rax
    ja .Lrqs_bad
    mov rax, [r13 + ESQ_count]
    cmp rax, EC_BATCH
    ja .Lrqs_bad
    cmp [r13 + ESQ_row], rax
    ja .Lrqs_bad
    cmp qword ptr [r13 + ESQ_span], 3
    ja .Lrqs_bad
    mov ecx, [rbx + EJF_body + 4]
    cmp rax, rcx
    jne .Lrqs_bad
    test r12, r12
    jz .Lrqs_empty
    test rax, rax
    jz .Lrqs_bad
    cmp [r12 + EQB_count], rax
    jne .Lrqs_bad
    cmp dword ptr [rbx + EJF_body], 2
    jne .Lrqs_bad
    jmp .Lrqs_next
.Lrqs_empty:
    test rax, rax
    jnz .Lrqs_bad
    mov eax, [rbx + EJF_body]
    cmp eax, 1
    je .Lrqs_next
    cmp eax, 3
    jne .Lrqs_bad
.Lrqs_next:
    cmp qword ptr [rsp], 1024
    jae .Lrqs_pending
    mov rax, [r13 + ESQ_row]
    cmp rax, [r13 + ESQ_count]
    je .Lrqs_finish
    imul rax, rax, EQB_ROW
    mov rcx, [r12 + rax + EQB_rows + EQBR_cell]
    test rcx, rcx
    jz .Lrqs_bad
    mov rax, [r13 + ESQ_span]
    test rax, rax
    jz .Lrqs_header
    cmp rax, 1
    je .Lrqs_section
    cmp rax, 2
    je .Lrqs_key
    mov rsi, [rcx + EC_value]
    mov rdx, [rcx + EC_vallen]
    jmp .Lrqs_span
.Lrqs_section:
    mov rsi, [rcx + EC_section]
    mov rdx, [rcx + EC_seclen]
    jmp .Lrqs_span
.Lrqs_key:
    mov rsi, [rcx + EC_key]
    mov rdx, [rcx + EC_keylen]
    jmp .Lrqs_span
.Lrqs_header:
    mov eax, [rcx + EC_seclen]
    mov [rsp + 48], eax
    mov eax, [rcx + EC_keylen]
    mov [rsp + 52], eax
    mov eax, [rcx + EC_vallen]
    mov [rsp + 56], eax
    mov eax, [rcx + EC_remove]
    mov [rsp + 60], eax
    lea rsi, [rsp + 48]
    mov edx, 16
.Lrqs_span:
    mov rax, [r13 + ESQ_offset]
    cmp rax, rdx
    ja .Lrqs_bad
    je .Lrqs_advance
    test r14, r14
    jz .Lrqs_pending
    test rsi, rsi
    jz .Lrqs_bad
    sub rdx, rax
    cmp rdx, r14
    cmova rdx, r14
    add rsi, rax
    jc .Lrqs_bad
    mov rcx, [rbx + EJF_length]
    sub rcx, [r13 + ESQ_pos]
    cmp rdx, rcx
    ja .Lrqs_bad
    mov [rsp + 32], rdx
    mov rdi, [r13 + ESQ_pos]
    lea rdi, [rbx + rdi + EJF_body]
    call memcpy
    mov rax, [rsp + 32]
    add [r13 + ESQ_offset], rax
    add [r13 + ESQ_pos], rax
    add r15, rax
    sub r14, rax
    inc qword ptr [rsp]
    jmp .Lrqs_next
.Lrqs_advance:
    mov qword ptr [r13 + ESQ_offset], 0
    inc qword ptr [r13 + ESQ_span]
    cmp qword ptr [r13 + ESQ_span], 4
    jne 1f
    mov qword ptr [r13 + ESQ_span], 0
    inc qword ptr [r13 + ESQ_row]
1:  inc qword ptr [rsp]
    jmp .Lrqs_next
.Lrqs_finish:
    cmp qword ptr [r13 + ESQ_span], 0
    jne .Lrqs_bad
    cmp qword ptr [r13 + ESQ_offset], 0
    jne .Lrqs_bad
    mov rax, [rbx + EJF_length]
    cmp [r13 + ESQ_pos], rax
    jne .Lrqs_bad
    mov rdi, rbx
    call ext_settings_frame_seal
    inc qword ptr [rsp]
    test rax, rax
    js .Lrqs_return
    mov rax, ESQ_DONE
    mov [r13 + ESQ_magic], rax
    mov eax, 1
    jmp .Lrqs_return
.Lrqs_done:
    cmp qword ptr [rbx + EJF_kind], EW_REQUEST
    jne .Lrqs_bad
    cmp qword ptr [rbx + EJF_sealed], 1
    jne .Lrqs_bad
    mov eax, 1
    jmp .Lrqs_return
.Lrqs_pending:
    xor eax, eax
.Lrqs_return:
    mov rdx, r15
    mov rcx, [rsp]
    EPILOGUE
.Lrqs_bad:
    mov rax, -22
    jmp .Lrqs_return
.Lrqs_bad_leaf:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
