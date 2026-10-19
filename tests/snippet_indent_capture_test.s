.include "rhun.inc"
.text
FN main
    PROLOGUE 48
    mov r15, [rip + g_mem_live]
    lea r13, [rip + cases]
    mov qword ptr [rsp + 24], 1
.Lsi_case:
    cmp qword ptr [r13], 0
    je .Lsi_owned
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r13]
    mov rcx, [r13 + 8]
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov r14, [r13 + 16]
    shr r14, 1
    mov rsi, r14
    lea rdx, [rip + x]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, r14
    mov edx, 1
    xor ecx, ecx
    call doc_delete
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov qword ptr [rbx + DOC_cur], 1
    mov qword ptr [rbx + DOC_anchor], 2
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov r12, rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13 + 16]
    call snippet_capture_indent
    cmp eax, 1
    jne .Lsi_fail
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz .Lsi_fail
    mov rax, [r13 + 32]
    cmp [r12 + SN_indentbytes], rax
    jne .Lsi_fail
    mov rdi, [r12 + SN_indent]
    test rax, rax
    jz .Lsi_empty
    test rdi, rdi
    jz .Lsi_fail
    cmp qword ptr [rdi + SC_refs], 1
    jne .Lsi_fail
    cmp [rdi + SC_bytes], rax
    jne .Lsi_fail
    add rdi, SC_DATA
    mov rsi, [r13 + 24]
    mov rdx, rax
    call memeq
    test eax, eax
    jz .Lsi_fail
    jmp .Lsi_case_done
.Lsi_empty:
    test rdi, rdi
    jnz .Lsi_fail
.Lsi_case_done:
    mov rdi, [rsp]
    call mem_free
    mov rdi, r12
    call snippet_free_node
    mov rdi, rbx
    call doc_free
    add r13, 40
    inc qword ptr [rsp + 24]
    jmp .Lsi_case
.Lsi_owned:
    mov qword ptr [rsp + 24], 100
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + line]
    mov ecx, 8
    xor r8d, r8d
    call doc_insert
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, 4
    call snippet_capture_indent
    cmp eax, 1
    jne .Lsi_fail
    mov r14, [r12 + SN_indent]
    mov rdi, r12
    call snippet_clone_chain
    mov [rsp + 8], rax
    cmp [rax + SN_indent], r14
    jne .Lsi_fail
    cmp qword ptr [r14 + SC_refs], 2
    jne .Lsi_fail
    # Subsequent document edits cannot change the original owned prefix.
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + x]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    lea rdi, [r14 + SC_DATA]
    lea rsi, [rip + line]
    mov edx, 4
    call memeq
    test eax, eax
    jz .Lsi_fail
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call snippet_capture_indent
    cmp eax, 1
    jne .Lsi_fail
    cmp qword ptr [r12 + SN_indent], 0
    jne .Lsi_fail
    cmp qword ptr [r12 + SN_indentbytes], 0
    jne .Lsi_fail
    cmp qword ptr [r14 + SC_refs], 1
    jne .Lsi_fail
    mov rdi, [rsp + 8]
    call snippet_free_chain
    mov rdi, rbx
    xor esi, esi
    mov edx, 1
    xor ecx, ecx
    call doc_delete
    # A prefix exactly filling the remaining shared budget succeeds.
    mov qword ptr [r12 + SN_choicebytes], SN_BYTES_MAX - 5
    mov qword ptr [r12 + SN_transformbytes], 1
    mov rdi, rbx
    mov rsi, r12
    mov edx, 8             # text immediately after the exact allowed prefix
    call snippet_capture_indent
    cmp eax, 1
    jne .Lsi_fail
    cmp qword ptr [r12 + SN_indentbytes], 4
    jne .Lsi_fail
    inc qword ptr [r12 + SN_choicebytes]
    mov rdi, r12
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, 4
    call snippet_capture_indent
    test eax, eax
    jnz .Lsi_fail
    mov rdi, r12
    mov rsi, [rsp]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz .Lsi_fail
    mov rdi, [r12 + SN_indent]
    cmp qword ptr [rdi + SC_refs], 1
    jne .Lsi_fail
    mov rdi, [rsp]
    call mem_free
    # Overflowing other retained classes is rejected before any source scan.
    mov qword ptr [r12 + SN_choicebytes], -1
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call snippet_capture_indent
    test eax, eax
    jnz .Lsi_fail
    mov qword ptr [r12 + SN_choicebytes], 0
    mov qword ptr [r12 + SN_transformbytes], 0
    mov rdi, r12
    call snippet_free_node
    mov rdi, rbx
    call doc_free
    # Null candidates require no document access. Oversized allocations read no input.
    xor edi, edi
    xor esi, esi
    mov rdx, -1
    call snippet_capture_indent
    cmp eax, 1
    jne .Lsi_fail
    mov rdi, 1 << 40
    call snippet_indent_alloc
    test rax, rax
    jnz .Lsi_fail
    mov rdi, -1
    call snippet_indent_alloc
    test rax, rax
    jnz .Lsi_fail
    mov rdi, -24
    call snippet_indent_alloc
    test rax, rax
    jnz .Lsi_fail
    cmp [rip + g_mem_live], r15
    jne .Lsi_fail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lsi_fail:
    lea rdi, [rip + failed]
    call log_cstr
    mov eax, 1
    EPILOGUE
.section .rodata
ok: .asciz "ok snippet indentation capture\n"
failed: .asciz "FAIL snippet indentation capture\n"
line: .ascii " \t  tail"
x: .ascii "x"
multiline: .ascii "abc\n\t x\n"
nbsp: .ascii "\xc2\xa0 x"
formfeed: .ascii " \x0c x"
unicode: .ascii "  \xc3\xa9 x"
.p2align 3
cases:
    .quad line, 8, 0, line, 0
    .quad line, 8, 1, line, 1
    .quad line, 8, 2, line, 2
    .quad line, 8, 4, line, 4
    .quad line, 8, 8, line, 4
    .quad multiline, 8, 6, multiline + 4, 2
    .quad multiline, 8, 8, multiline, 0
    .quad nbsp, 4, 4, nbsp, 0
    .quad formfeed, 4, 4, formfeed, 1
    .quad unicode, 6, 6, unicode, 2
    .quad 0
