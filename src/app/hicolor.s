# editor presentation: document highlights (feature document-highlights) and, without a provider,
# the other occurrences of the word under the caret. When the caret rests in a word with nothing
# selected (250 ms), the language's provider is asked (`highlights DOC VERSION LINE COL`); its
# ranges are drawn behind the text in the theme's `highlight` color (`highlight_write` for writes).
# They go when the caret leaves them all, and with any edit. Without a provider, and with
# `highlight_occurrences` on, the word's whole-word occurrences around the caret are drawn instead.
.include "rhun.inc"

.equ HL_PAUSE, 250
.equ HL_SCAN, 400               # lines each way the occurrence fallback looks at
.equ HL_WORD_MAX, 200

.bss
.p2align 3
.globl g_hl_doc
g_hl_doc:
hl_docp: .quad 0                # the document the ranges are on
hl_ver: .quad 0                 # its version
hl_due: .quad 0                 # time_ms the caret's word is due to be asked about (0: not)
.globl g_hl
g_hl: .zero VEC_SIZE            # HLR: start, end, kind (0 read or text, 1 write)
hl_new: .zero VEC_SIZE
hl_word: .zero HL_WORD_MAX + 8

.data
.p2align 3
hl_cur: .quad -1                # the caret when last looked at

.text

# FN hl_frame(doc): a frame of the document: its highlights follow the caret and the text
FN hl_frame
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    cmp [rip + hl_docp], rbx
    jne 1f
    mov rax, [rbx + DOC_version]
    cmp [rip + hl_ver], rax
    je 2f
1:  # another document or an edit: the ranges go, the caret's word is due again
    mov [rip + hl_docp], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + hl_ver], rax
    call hl_clear
    mov qword ptr [rip + hl_cur], -1
2:  mov rax, [rbx + DOC_cur]
    cmp rax, [rip + hl_cur]
    je 9f
    mov [rip + hl_cur], rax
    # the caret left every range: they go
    cmp qword ptr [rip + g_hl + VEC_len], 0
    je 4f
    xor ecx, ecx
3:  cmp rcx, [rip + g_hl + VEC_len]
    jae 31f
    imul rdx, rcx, 24
    add rdx, [rip + g_hl + VEC_ptr]
    inc rcx
    cmp rax, [rdx]
    jb 3b
    cmp rax, [rdx + 8]
    ja 3b
    jmp 4f                      # still inside one: they stay (the word is asked about again)
31: call hl_clear
4:  mov qword ptr [rip + hl_due], 0
    mov rax, [rbx + DOC_cur]
    cmp rax, [rbx + DOC_anchor]
    jne 9f                      # a selection: nothing
    mov rdi, rbx
    call hl_word_at
    test rdx, rdx
    jz 9f
    call time_ms
    add rax, HL_PAUSE
    mov [rip + hl_due], rax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# hl_clear(): the ranges go
hl_clear:
    cmp qword ptr [rip + g_hl + VEC_len], 0
    je 1f
    mov qword ptr [rip + g_hl + VEC_len], 0
    mov dword ptr [rip + g_dirty], 1
1:  ret

# hl_word_at(doc) -> rax the start, rdx the length of the word the caret is in or at the end of
# (rdx 0: none)
hl_word_at:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DOC_cur]
    mov r13, r12                # start
1:  test r13, r13
    jz 2f
    mov rdi, rbx
    lea rsi, [r13 - 1]
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jz 2f
    dec r13
    jmp 1b
2:  mov r14, r12                # end
    mov rdi, rbx
    call doc_len
    mov r15, rax
3:  cmp r14, r15
    jae 4f
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jz 4f
    inc r14
    jmp 3b
4:  mov rax, r13
    mov rdx, r14
    sub rdx, r13
    cmp rdx, HL_WORD_MAX
    jbe 9f
    xor edx, edx
9:  EPILOGUE

# FN hl_timeout() -> eax ms until the caret's word is due, or -1
FN hl_timeout
    mov rax, [rip + hl_due]
    test rax, rax
    jz 8f
    push rbx
    mov rbx, rax
    call time_ms
    sub rbx, rax
    mov eax, ebx
    pop rbx
    test eax, eax
    jns 9f
    xor eax, eax
9:  ret
8:  mov eax, -1
    ret

# FN hl_tick(): the caret's word, when due: the language's provider is asked, or its occurrences
# are found
FN hl_tick
    PROLOGUE
    cmp qword ptr [rip + hl_due], 0
    je 9f
    call time_ms
    cmp rax, [rip + hl_due]
    jb 9f
    mov qword ptr [rip + hl_due], 0
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp rbx, [rip + hl_docp]
    jne 9f
    mov edi, PP_HIGHLIGHTS
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jz 1f
    mov rdi, rbx
    mov esi, PQ_HIGHLIGHTS
    call present_ask_now
    jmp 9f
1:  cmp dword ptr [rip + cfg_highlight_occurrences], 0
    je 9f
    mov rdi, rbx
    call hl_occurrences
9:  EPILOGUE

# FN hl_args(sb, doc, l1l2*, ext): " LINE COL" of the caret (1-based, byte column)
FN hl_args
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rsi, [r12 + DOC_cur]
    mov rdi, r12
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    lea rsi, [r13 + 1]
    mov rdi, rbx
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, r13
    call doc_line_start
    mov rsi, [r12 + DOC_cur]
    sub rsi, rax
    inc rsi
    mov rdi, rbx
    call sb_push_u64
    EPILOGUE

# FN hl_reply(doc, ext, body, len, version, PQR*) -> eax 1 taken, 0 dropped: "N" LF, then N lines
# "L1 C1 L2 C2 KIND" (KIND text, read or write)
FN hl_reply
    PROLOGUE 64
    mov r13, rdi
    mov rbx, rdx
    lea r12, [rdx + rcx]
    mov [rsp], r8
    mov qword ptr [rip + hl_new + VEC_len], 0
    cmp r13, [rip + hl_docp]
    jne 8f                      # (the caret's document only)
    call present_num
    test edx, edx
    jz 8f
    cmp rax, HL_MAX
    ja 8f
    mov r14, rax
1:  test r14, r14
    jz 5f
    dec r14
    xor r15d, r15d
2:  cmp r15d, 4
    jae 3f
    call present_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    dec rax
    mov [rsp + 8 + r15*8], rax
    inc r15d
    jmp 2b
3:  call present_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lk_write]
    call str_eq_cstr
    mov [rsp + 40], rax
    # the positions, from the version asked about
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    mov r8d, GR_RIGHT
    call tape_map_lc
    test rax, rax
    js 8f
    mov [rsp + 48], rax
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 24]
    mov rcx, [rsp + 32]
    mov r8d, GR_LEFT
    call tape_map_lc
    test rax, rax
    js 8f
    cmp rax, [rsp + 48]
    jb 1b
    mov [rsp + 56], rax
    lea rdi, [rip + hl_new]
    mov esi, 24
    call vec_push
    mov rcx, [rsp + 48]
    mov [rax], rcx
    mov rcx, [rsp + 56]
    mov [rax + 8], rcx
    mov rcx, [rsp + 40]
    mov [rax + 16], rcx
    jmp 1b
5:  cmp rbx, r12
    jne 8f
    lea rdi, [rip + g_hl]
    lea rsi, [rip + hl_new]
    call hl_swap
    mov qword ptr [rip + hl_new + VEC_len], 0
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# hl_swap(a, b): two vectors change places
hl_swap:
    mov ecx, 3
1:  mov rax, [rdi]
    mov rdx, [rsi]
    mov [rdi], rdx
    mov [rsi], rax
    add rdi, 8
    add rsi, 8
    dec ecx
    jnz 1b
    ret

# hl_occurrences(doc): the caret's word's whole-word occurrences on the lines around it
hl_occurrences:
    PROLOGUE 32
    mov rbx, rdi
    call hl_word_at
    test rdx, rdx
    jz 9f
    mov [rsp], rdx              # its length
    mov rdi, rbx                # the word, copied out
    mov rsi, rax
    lea rcx, [rip + hl_word]
    call doc_copy               # doc_copy(doc, pos, len, dst)
    mov qword ptr [rip + hl_new + VEC_len], 0
    mov rsi, [rbx + DOC_cur]
    mov rdi, rbx
    call doc_line_of
    mov r12, rax
    sub r12, HL_SCAN
    jns 1f
    xor r12d, r12d
1:  lea r13, [rax + HL_SCAN]
    cmp r13, [rbx + DOC_nlines]
    jb .Lho_line
    mov r13, [rbx + DOC_nlines]
.Lho_line:
    cmp r12, r13
    jae .Lho_done
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov r14, rax                # text
    mov r15, rdx                # len
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp + 8], rax
    inc r12
    xor ecx, ecx                # offset
2:  mov rax, rcx
    add rax, [rsp]
    cmp rax, r15
    ja .Lho_line
    # a match at rcx, on word boundaries
    mov [rsp + 16], rcx
    lea rdi, [r14 + rcx]
    mov rsi, [rsp]
    lea rdx, [rip + hl_word]
    mov rcx, rsi
    call str_eq
    mov rcx, [rsp + 16]
    test eax, eax
    jz 4f
    test rcx, rcx
    jz 3f
    movzx edi, byte ptr [r14 + rcx - 1]
    call is_ident
    mov rcx, [rsp + 16]
    test eax, eax
    jnz 4f
3:  mov rax, rcx
    add rax, [rsp]
    cmp rax, r15
    jae 31f
    movzx edi, byte ptr [r14 + rax]
    call is_ident
    mov rcx, [rsp + 16]
    test eax, eax
    jnz 4f
31: cmp qword ptr [rip + hl_new + VEC_len], HL_MAX
    jae .Lho_done
    lea rdi, [rip + hl_new]
    mov esi, 24
    call vec_push
    mov rcx, [rsp + 16]
    mov rdx, [rsp + 8]
    add rdx, rcx
    mov [rax], rdx
    add rdx, [rsp]
    mov [rax + 8], rdx
    mov qword ptr [rax + 16], 0
    add rcx, [rsp]
    jmp 2b
4:  inc rcx
    jmp 2b
.Lho_done:
    # a lone occurrence (the word itself) is not worth drawing
    cmp qword ptr [rip + hl_new + VEC_len], 2
    jb 9f
    lea rdi, [rip + g_hl]
    lea rsi, [rip + hl_new]
    call hl_swap
    mov dword ptr [rip + g_dirty], 1
9:  mov qword ptr [rip + hl_new + VEC_len], 0
    EPILOGUE

# FN hl_dump(sb): "highlight L1:C1-L2:C2 KIND" per range of the active document
FN hl_dump
    PROLOGUE 16
    mov r12, rdi
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp rbx, [rip + hl_docp]
    jne 9f
    xor r13d, r13d
1:  cmp r13, [rip + g_hl + VEC_len]
    jae 9f
    imul r14, r13, 24
    add r14, [rip + g_hl + VEC_ptr]
    inc r13
    mov rdi, r12
    lea rsi, [rip + .Ls_highlight]
    call sb_push_cstr
    mov rsi, [r14]
    call hl_put_pos
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov rsi, [r14 + 8]
    call hl_put_pos
    lea rsi, [rip + .Ls_text]
    cmp qword ptr [r14 + 16], 0
    je 2f
    lea rsi, [rip + .Ls_write]
2:  mov rdi, r12
    call sb_push_cstr
    jmp 1b
9:  EPILOGUE

# hl_put_pos(rsi pos; rbx doc, r12 sb): "L:C" (1-based)
hl_put_pos:
    push r15
    push r14
    sub rsp, 8
    mov r15, rsi
    mov rdi, rbx
    call doc_line_of
    mov r14, rax
    lea rsi, [rax + 1]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    mov rsi, r15
    sub rsi, rax
    inc rsi
    mov rdi, r12
    call sb_push_u64
    add rsp, 8
    pop r14
    pop r15
    ret

.section .rodata
.Lk_write: .asciz "write"
.Ls_highlight: .asciz "highlight "
.Ls_text: .asciz " text\n"
.Ls_write: .asciz " write\n"
