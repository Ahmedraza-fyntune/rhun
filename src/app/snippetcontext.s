# Read-only context for a validated document insertion range.
.include "rhun.inc"
.text

# snippet_context(doc, start, len) -> owned UTF-8 body in rax, len in rdx.
# Caller validates range boundaries/version. -1: size limit; -2: invalid UTF-8.
# Copy only returned ranges, without moving the document's gap or selection.
FN snippet_context
    PROLOGUE 224
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsp
    xor esi, esi
    mov edx, 224
    call memset
    # Six source pointers (document offsets for selected/line/indent), then
    # eleven header numbers: position, settings, six byte lengths.
    mov [rsp + 32], r12
    mov [rsp + 168], r13
    cmp r13, SN_BYTES_MAX
    ja .Lsc_large
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    lea rcx, [rax + 1]
    mov [rsp + 128], rcx
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, rax
    mov [rsp + 40], rax
    mov [rsp + 64], rax
    mov rcx, r12
    sub rcx, rax
    inc rcx
    mov [rsp + 136], rcx
    mov rsi, [rsp + 128]
    dec rsi
    mov rdi, rbx
    call doc_line_end
    sub rax, r14
    mov [rsp + 176], rax
    cmp rax, SN_BYTES_MAX
    ja .Lsc_large
    mov rdi, [rbx + DOC_path]
    mov [rsp + 48], rdi
    test rdi, rdi
    jz 1f
    call strlen
    mov [rsp + 184], rax
1:  mov rdi, [rip + g_project]
    mov [rsp + 56], rdi
    test rdi, rdi
    jz 2f
    call strlen
    mov [rsp + 192], rax
2:  mov rdi, rbx
    call doc_language
    test rax, rax
    jz 3f
    mov rcx, [rax + GR_comment]
    mov [rsp + 72], rcx
    mov rcx, [rax + GR_commentlen]
    mov [rsp + 208], rcx
3:  xor r15d, r15d
    xor eax, eax
4:  add rax, [rsp + r15*8 + 168]
    jc .Lsc_large
    cmp rax, SN_BYTES_MAX
    ja .Lsc_large
    inc r15
    cmp r15, 6
    jb 4b
    # Leading whitespace is bounded by the returned line and insertion point.
    mov r15, r14
5:  cmp r15, r12
    jae 7f
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    cmp eax, ' '
    je 6f
    cmp eax, 9
    jne 7f
6:  inc r15
    jmp 5b
7:  sub r15, r14
    mov [rsp + 200], r15
    mov rdi, rbx
    mov esi, OPT_TAB
    call ext_doc_option
    test eax, eax
    jnz 8f
    mov eax, [rip + cfg_tab_width]
8:  mov [rsp + 144], rax
    mov rdi, rbx
    mov esi, OPT_SPACES
    call ext_doc_option
    cmp eax, 2
    je 10f
    cmp eax, 1
    je 9f
    cmp dword ptr [rip + cfg_insert_spaces], 0
    jne 10f
9:  xor eax, eax
    jmp 11f
10: mov eax, 1
11: mov [rsp + 152], rax
    xor eax, eax
    cmp dword ptr [rbx + DOC_crlf], 0
    setne al
    mov [rsp + 160], rax
    mov rdi, rsp
    lea rsi, [rip + .Lcontext]
    call sb_push_cstr
    xor r15d, r15d
.Lsc_header:
    mov rdi, rsp
    mov esi, ' '
    call sb_push_byte
    mov rdi, rsp
    mov rsi, [rsp + r15*8 + 128]
    call sb_push_u64
    inc r15
    cmp r15, 11
    jb .Lsc_header
    mov rdi, rsp
    mov esi, 10
    call sb_push_byte
    mov rax, [rsp + SB_len]
    xor r15d, r15d
.Lsc_size:
    add rax, [rsp + r15*8 + 168]
    jc .Lsc_large
    cmp rax, SN_BYTES_MAX
    ja .Lsc_large
    inc r15
    cmp r15, 6
    jb .Lsc_size
    mov rsi, rax
    sub rsi, [rsp + SB_len]
    mov rdi, rsp
    call sb_reserve
    xor r15d, r15d
.Lsc_part:
    mov r14, [rsp + r15*8 + 168]
    mov rdi, rsp
    mov rsi, r14
    call sb_reserve
    mov r13, rax
    cmp r15, 0
    je .Lsc_doc
    cmp r15, 1
    je .Lsc_doc
    cmp r15, 4
    je .Lsc_doc
    test r14, r14
    jz .Lsc_utf8
    mov rdi, r13
    mov rsi, [rsp + r15*8 + 32]
    mov rdx, r14
    call memcpy
    jmp .Lsc_utf8
.Lsc_doc:
    mov rdi, rbx
    mov rsi, [rsp + r15*8 + 32]
    mov rdx, r14
    mov rcx, r13
    call doc_copy
.Lsc_utf8:
    mov rdi, r13
    mov rsi, r14
    call snippet_utf8_valid
    test eax, eax
    jz .Lsc_bad_utf8
    add [rsp + SB_len], r14
    inc r15
    cmp r15, 6
    jb .Lsc_part
    mov rax, [rsp + SB_ptr]
    mov rdx, [rsp + SB_len]
    mov byte ptr [rax + rdx], 0
    EPILOGUE
.Lsc_large:
    mov r12, -1
    jmp .Lsc_error
.Lsc_bad_utf8:
    mov r12, -2
.Lsc_error:
    mov rdi, rsp
    call sb_free
    mov rax, r12
    xor edx, edx
    EPILOGUE

.section .rodata
.Lcontext: .asciz "context 1"
