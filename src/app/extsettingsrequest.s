# Exact counted REQUEST bytes. No filesystem, native process or borrowed UI state.
.include "rhun.inc"
.include "app/extsettingsrequest.inc"
.text
# begin(SRQ40,outESQ64)->owned unsealed frame/NULL,RDX error.
# Cursor remains unchanged on every refusal; caller retains batch throughout encoding.
FN ext_settings_request_begin
    test rdi, rdi
    jz .Lreq_bad_leaf
    test rsi, rsi
    jz .Lreq_bad_leaf
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + SRQ_length]
    test r13, r13
    jz .Lreq_bad
    cmp r13, 4095
    ja .Lreq_bad
    mov rdi, [rbx + SRQ_path]
    test rdi, rdi
    jz .Lreq_bad
    mov rax, rdi
    add rax, r13
    jc .Lreq_bad
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0
    je .Lreq_bad
    inc rcx
    cmp rcx, r13
    jb 1b
    mov rsi, r13
    call snippet_utf8_valid
    test eax, eax
    jz .Lreq_bad
    mov rax, [rbx + SRQ_mode]
    cmp rax, 1
    jb .Lreq_bad
    cmp rax, 3
    ja .Lreq_bad
    mov [rsp + 16], rax
    mov r14, [rbx + SRQ_batch]
    mov qword ptr [rsp], 0
    lea r15, [r13 + 56]
    cmp rax, 2
    je .Lreq_batch
    test r14, r14
    jnz .Lreq_bad
    jmp .Lreq_allocate
.Lreq_batch:
    test r14, r14
    jz .Lreq_bad
    mov rax, [r14 + EQB_count]
    test rax, rax
    jz .Lreq_bad
    cmp rax, EC_BATCH
    ja .Lreq_bad
    mov [rsp], rax
    xor ecx, ecx
    xor r10d, r10d
.Lreq_measure:
    cmp rcx, [rsp]
    jae .Lreq_allocate
    imul rax, rcx, EQB_ROW
    mov rdx, [r14 + rax + EQB_rows + EQBR_cell]
    test rdx, rdx
    jz .Lreq_bad
    mov rax, [rdx + EC_seclen]
    test rax, rax
    jz .Lreq_bad
    cmp rax, 1024
    ja .Lreq_bad
    cmp qword ptr [rdx + EC_section], 0
    je .Lreq_bad
    mov r8, [rdx + EC_keylen]
    test r8, r8
    jz .Lreq_bad
    cmp r8, 256
    ja .Lreq_bad
    cmp qword ptr [rdx + EC_key], 0
    je .Lreq_bad
    add rax, r8
    jc .Lreq_large
    mov r8, [rdx + EC_vallen]
    cmp r8, EC_LIMIT
    ja .Lreq_large
    cmp qword ptr [rdx + EC_remove], 1
    ja .Lreq_bad
    jne 1f
    test r8, r8
    jnz .Lreq_bad
1:  test r8, r8
    jz 2f
    cmp qword ptr [rdx + EC_value], 0
    je .Lreq_bad
2:  add rax, r8
    jc .Lreq_large
    add r10, rax
    jc .Lreq_large
    cmp r10, EC_LIMIT
    ja .Lreq_large
    add rax, 16
    add r15, rax
    jc .Lreq_large
    cmp r15, EW_LIMIT
    ja .Lreq_large
    inc rcx
    jmp .Lreq_measure
.Lreq_allocate:
    mov rdi, [rbx + SRQ_tag]
    mov esi, EW_REQUEST
    mov rdx, r15
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz .Lreq_return
    mov r15, rax
    mov eax, [rsp + 16]
    mov [r15 + EJF_body], eax
    mov eax, [rsp]
    mov [r15 + EJF_body + 4], eax
    mov [r15 + EJF_body + 8], r13d
    mov dword ptr [r15 + EJF_body + 12], 0
    mov qword ptr [r15 + EJF_body + 16], 0
    mov qword ptr [r15 + EJF_body + 24], 0
    mov qword ptr [r15 + EJF_body + 32], 0
    mov qword ptr [r15 + EJF_body + 40], 0
    mov qword ptr [r15 + EJF_body + 48], 0
    lea rdi, [r15 + EJF_body + 56]
    mov rsi, [rbx + SRQ_path]
    mov rdx, r13
    call memcpy
    mov [r12 + ESQ_frame], r15
    mov [r12 + ESQ_batch], r14
    mov rax, [rsp]
    mov [r12 + ESQ_count], rax
    mov qword ptr [r12 + ESQ_row], 0
    mov qword ptr [r12 + ESQ_span], 0
    mov qword ptr [r12 + ESQ_offset], 0
    add r13, 56
    mov [r12 + ESQ_pos], r13
    mov rax, ESQ_ACTIVE
    mov [r12 + ESQ_magic], rax
    mov rax, r15
    xor edx, edx
.Lreq_return:
    EPILOGUE
.Lreq_bad:
    mov rdx, -22
    jmp .Lreq_null
.Lreq_large:
    mov rdx, -27
.Lreq_null:
    xor eax, eax
    EPILOGUE
.Lreq_bad_leaf:
    xor eax, eax
    mov rdx, -22
    ret
