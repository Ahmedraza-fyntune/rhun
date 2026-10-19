# Render a validated replacement program against one current match or no captures.
.include "rhun.inc"
.text
# render(TF*, hascaptures) -> bool
FN snippet_transform_render
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov r14, [rbx + SC_rx]
    mov r12, [rbx + TXF_format]
    add r12, 32
    mov r15, [rbx + TXF_nrecords]
    xor r13d, r13d
.Ltr_loop:
    cmp qword ptr [r14 + RX_error], 0
    jne .Ltr_bad
    cmp r13, r15
    jae .Ltr_ok
    mov qword ptr [r14 + RX_tstage], TRANSFORM_FORMAT
    mov [r14 + RX_trecord], r13
    mov qword ptr [r14 + RX_pc], -1
    mov qword ptr [r14 + RX_errbyte], -1
    mov rdi, r14
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Ltr_bad
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    cmp qword ptr [rsp], 0
    je .Ltr_dispatch
    mov eax, [r12 + 4]
    cmp rax, [r14 + RX_ncaps]
    ja .Ltr_dispatch
    shl rax, 4
    lea rax, [r14 + rax + RX_captures]
    mov rcx, [rax]
    cmp rcx, -1
    je .Ltr_dispatch
    mov rdx, [rax + 8]
    sub rdx, rcx
    mov rax, [rbx + TXF_desc]
    add rcx, [rax + TD_input]
    mov [rsp + 8], rcx
    mov [rsp + 16], rdx
.Ltr_dispatch:
    mov eax, [r12]
    cmp eax, 0
    je .Ltr_a
    cmp eax, 1
    je .Ltr_capture
    cmp eax, 8
    jbe .Ltr_case
    cmp eax, 9
    je .Ltr_if
    cmp eax, 10
    je .Ltr_else
    cmp qword ptr [rsp + 16], 0
    jne .Ltr_a
    mov esi, [r12 + 16]
    add rsi, [rbx + TXF_blob]
    mov edx, [r12 + 20]
    jmp .Ltr_output
.Ltr_if:
    cmp qword ptr [rsp + 16], 0
    jne .Ltr_a
    xor esi, esi
    xor edx, edx
    jmp .Ltr_output
.Ltr_else:
    cmp qword ptr [rsp + 16], 0
    je .Ltr_a
.Ltr_capture:
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    jmp .Ltr_output
.Ltr_a:
    mov esi, [r12 + 8]
    add rsi, [rbx + TXF_blob]
    mov edx, [r12 + 12]
.Ltr_output:
    mov rdi, rbx
    mov rcx, r13
    call snippet_transform_output
    test eax, eax
    jz .Ltr_bad
    jmp .Ltr_next
.Ltr_case:
    mov qword ptr [r14 + RX_tstage], TRANSFORM_CASE
    mov [r14 + RX_trecord], r13
    mov rdi, r14
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov ecx, [r12]
    call snippet_case_convert
    mov [rbx + TXF_temp], rax
    mov [rbx + TXF_temp_len], rdx
    test ecx, ecx
    jz .Ltr_bad
    mov rdi, rbx
    mov rsi, rax
    mov rcx, r13
    call snippet_transform_output
    # The temporary is owned independently of the final append's success.
    mov rdi, [rbx + TXF_temp]
    call mem_free
    mov qword ptr [rbx + TXF_temp], 0
.Ltr_next:
    inc r13
    add r12, 24
    jmp .Ltr_loop
.Ltr_bad:
    xor eax, eax
    EPILOGUE
.Ltr_ok:
    mov eax, 1
    EPILOGUE
