# Original insertion indentation belongs to the session, independent of later edits.
.include "rhun.inc"
.text
# Allocate an immutable common-header block, without reading source bytes.
FN snippet_indent_alloc
    PROLOGUE
    mov r12, rdi
    add rdi, SC_DATA + 16     # include the allocator's own header in the guard
    jc 8f
    sub rdi, 16
    cmp rdi, 65536
    jae 1f
    mov edi, 65536
1:  call mem_alloc_try
    test rax, rax
    jz 8f
    mov qword ptr [rax + SC_refs], 1
    mov [rax + SC_bytes], r12
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# capture(doc, candidate or 0, validated insertion position) -> bool.
# All failure paths preserve the old prefix and every document field.
FN snippet_capture_indent
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .Lsic_ok
    mov rax, [r12 + SN_choicebytes]
    add rax, [r12 + SN_transformbytes]
    jc .Lsic_bad
    cmp rax, SN_BYTES_MAX
    ja .Lsic_bad
    mov r14d, SN_BYTES_MAX
    sub r14, rax
    mov rsi, r13
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov [rsp], rax
    mov r15, rax
.Lsic_scan:
    cmp r15, r13
    jae .Lsic_copy
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    cmp eax, ' '
    je 1f
    cmp eax, 9
    jne .Lsic_copy
1:  test r14, r14
    jz .Lsic_bad
    dec r14
    inc r15
    jmp .Lsic_scan
.Lsic_copy:
    sub r15, [rsp]
    xor r14d, r14d
    test r15, r15
    jz .Lsic_swap
    mov rdi, r15
    call snippet_indent_alloc
    test rax, rax
    jz .Lsic_bad
    mov r14, rax
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, r15
    lea rcx, [rax + SC_DATA]
    call doc_copy
.Lsic_swap:
    mov rdi, [r12 + SN_indent]
    mov [r12 + SN_indent], r14
    mov [r12 + SN_indentbytes], r15
    test rdi, rdi
    jz .Lsic_ok
    dec qword ptr [rdi + SC_refs]
    jnz .Lsic_ok
    call mem_free
.Lsic_ok:
    mov eax, 1
    EPILOGUE
.Lsic_bad:
    xor eax, eax
    EPILOGUE
