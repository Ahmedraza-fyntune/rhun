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
.equ HL_LONG, 65536             # bytes: longer lines are left out of the occurrence fallback

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
    jne 0f
    mov rax, [rbx + DOC_version]
    cmp [rip + hl_ver], rax
    je 2f
    # an edit: the ranges go, the caret's word is due again
    mov [rip + hl_ver], rax
    call hl_clear
    mov qword ptr [rip + hl_cur], -1
    jmp 2f
0:  # another document: its ranges go, and its caret's word waits for the caret to move (a
    # document just opened or switched to stays as it is)
    mov [rip + hl_docp], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + hl_ver], rax
    call hl_clear
    mov qword ptr [rip + hl_due], 0
    mov rax, [rbx + DOC_cur]
    mov [rip + hl_cur], rax
    jmp 9f
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
# (rdx 0: none, also for one longer than HL_WORD_MAX: the scan stops there, as a minified line's
# tail is not read per keystroke)
hl_word_at:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DOC_cur]
    mov r13, r12                # start
1:  test r13, r13
    jz 2f
    mov rax, r12
    sub rax, r13
    cmp rax, HL_WORD_MAX
    ja 8f
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
    mov rax, r14
    sub rax, r13
    cmp rax, HL_WORD_MAX
    ja 8f
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
8:  xor edx, edx
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
    cmp dword ptr [rip + ce_pending], 0
    je 0f
    call color_prompt           # a swatch's prompt, now that its press is over
0:  cmp qword ptr [rip + hl_due], 0
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
    call doc_line_start
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    sub rax, [rsp + 8]
    inc r12
    cmp rax, HL_LONG            # a minified line is not scanned (nor its gap moved)
    ja .Lho_line
    mov rdi, rbx
    lea rsi, [r12 - 1]
    call doc_line_text
    mov r14, rax                # text
    mov r15, rdx                # len
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

# hl_put_pos(rsi pos; rbx doc, r12 sb): "L:C" (1-based); hl_put_pos_ext for ghost.s
.globl hl_put_pos_ext
hl_put_pos_ext:
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

# ---------------- colors (feature document-colors) ----------------
# Every matching provider is asked about the lines around the view (present.s); an answer replaces
# that provider's colors. A color shows a swatch, a two-cell inlay before it; a click on it asks
# for a new color (#rrggbb or #rrggbbaa) and the provider answers `color-edit` with the edit.

.bss
.p2align 3
cl_new: .zero VEC_SIZE
vi_swatch: .zero VI_SIZE
ce_ext: .quad 0                 # the color-edit request waited for
ce_id: .quad 0
ce_doc: .quad 0                 # the swatch the prompt is for: DOC_id, its color's index
ce_index: .quad 0
ce_pending: .long 0             # a swatch was pressed: its prompt opens at the next tick
ce_line: .zero SB_SIZE
ce_hex: .zero 16

.text

# FN color_reply(doc, ext, body, len, version, PQR*) -> eax 1 taken, 0 dropped: "N" LF, then N lines
# "L1 C1 L2 C2 RRGGBBAA"
FN color_reply
    PROLOGUE 64
    mov r13, rdi
    mov [rsp], rsi              # ext
    mov rbx, rdx
    lea r12, [rdx + rcx]
    mov [rsp + 8], r8           # version
    mov qword ptr [rip + cl_new + VEC_len], 0
    call present_num
    test edx, edx
    jz 8f
    cmp rax, CLR_MAX
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
    mov [rsp + 16 + r15*8], rax
    inc r15d
    jmp 2b
3:  call present_word
    cmp rdx, 8
    jne 8f
    mov rdi, rax
    mov rsi, rdx
    call parse_hex
    cmp rdx, 8
    jne 8f
    mov [rsp + 48], rax         # RRGGBBAA
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8d, GR_RIGHT
    call tape_map_lc
    test rax, rax
    js 8f
    mov [rsp + 56], rax
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 40]
    mov r8d, GR_LEFT
    call tape_map_lc
    test rax, rax
    js 8f
    cmp rax, [rsp + 56]
    jb 1b
    push rax
    push rax
    lea rdi, [rip + cl_new]
    mov esi, CLR_SIZE
    call vec_push
    pop rcx
    pop rcx
    mov [rax + CLR_end], rcx
    mov rcx, [rsp + 56]
    mov [rax + CLR_start], rcx
    mov rcx, [rsp]
    mov [rax + CLR_owner], rcx
    mov rcx, [rsp + 48]
    mov [rax + CLR_rgba], ecx
    jmp 1b
5:  cmp rbx, r12
    jne 8f
    # the provider's colors become these
    mov rdi, r13
    call pres_ensure
    mov r15, rax
    xor ecx, ecx                # read
    xor edx, edx                # write
6:  cmp rcx, [r15 + PRS_colors + VEC_len]
    jae 7f
    imul rsi, rcx, CLR_SIZE
    add rsi, [r15 + PRS_colors + VEC_ptr]
    inc rcx
    mov rax, [rsp]
    cmp [rsi + CLR_owner], rax
    je 6b
    imul rdi, rdx, CLR_SIZE
    add rdi, [r15 + PRS_colors + VEC_ptr]
    inc rdx
    mov rax, [rsi]
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    mov [rdi + 24], rax
    jmp 6b
7:  mov [r15 + PRS_colors + VEC_len], rdx
    xor r14d, r14d
71: cmp r14, [rip + cl_new + VEC_len]
    jae 72f
    lea rdi, [r15 + PRS_colors]
    mov esi, CLR_SIZE
    call vec_push
    imul rsi, r14, CLR_SIZE
    add rsi, [rip + cl_new + VEC_ptr]
    mov rdi, rax
    mov edx, CLR_SIZE
    call memcpy
    inc r14
    jmp 71b
72: mov rdi, r13
    call pres_touch
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN color_line_inlays(doc, line): the line's swatches, to vt_add
FN color_line_inlays
    PROLOGUE 16
    cmp dword ptr [rip + cfg_color_swatches], 0
    je 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    cmp qword ptr [r13 + PRS_colors + VEC_len], 0
    je 9f
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov [rsp + 8], rax
    xor r14d, r14d
1:  cmp r14, [r13 + PRS_colors + VEC_len]
    jae 9f
    imul r15, r14, CLR_SIZE
    add r15, [r13 + PRS_colors + VEC_ptr]
    inc r14
    mov rax, [r15 + CLR_start]
    cmp rax, [rsp]
    jb 1b
    cmp rax, [rsp + 8]
    ja 1b
    lea rdi, [rip + vi_swatch]
    sub rax, [rsp]
    mov [rdi + VI_off], rax
    lea rax, [rip + .Lswatch]
    mov [rdi + VI_text], rax
    mov dword ptr [rdi + VI_len], 2
    mov dword ptr [rdi + VI_cells], 2
    mov byte ptr [rdi + VI_side], VS_BEFORE
    mov byte ptr [rdi + VI_kind], VK_SWATCH
    mov word ptr [rdi + VI_flags], 0
    lea rax, [r14 - 1]
    mov [rdi + VI_ref], rax
    mov dword ptr [rdi + VI_prio], 255
    COLOR eax, T_FG
    mov [rdi + VI_fg], eax
    # the color over the editor's background, by its alpha
    mov eax, [r15 + CLR_rgba]
    movzx ecx, al               # alpha
    shr eax, 8                  # rrggbb
    COLOR edx, T_BG
    push rdi
    push rdi
    mov edi, edx
    mov esi, eax
    imul eax, ecx, 100
    add eax, 127
    xor edx, edx
    mov ecx, 255
    div ecx
    mov edx, eax                # percent, 100 at alpha 255
    call color_mix_pct
    pop rdi
    pop rdi
    or eax, 0xff000000
    mov [rdi + VI_bg], eax
    call vt_add
    jmp 1b
9:  EPILOGUE

# color_mix_pct(argb a, rgb b, pct) -> eax b over a at pct percent
color_mix_pct:
    push rbx
    push r12
    mov ebx, edi
    mov r12d, esi
    xor eax, eax
    mov ecx, 16
1:  mov r8d, ebx
    shr r8d, cl
    and r8d, 255
    mov r9d, r12d
    shr r9d, cl
    and r9d, 255
    sub r9d, r8d
    imul r9d, edx
    mov r10d, 100
    push rax
    push rdx
    mov eax, r9d
    cdq
    idiv r10d
    mov r9d, eax
    pop rdx
    pop rax
    add r8d, r9d
    and r8d, 255
    shl r8d, cl
    or eax, r8d
    sub ecx, 8
    jns 1b
    pop r12
    pop rbx
    ret

# FN color_click(doc, index) -> eax 1: a swatch pressed: the prompt for its new color opens once
# the press is over (hl_tick: the press would close a palette opened under it)
FN color_click
    mov rax, [rdi + DOC_pres]
    test rax, rax
    jz 8f
    cmp rsi, [rax + PRS_colors + VEC_len]
    jae 8f
    mov rax, [rdi + DOC_id]
    mov [rip + ce_doc], rax
    mov [rip + ce_index], rsi
    mov dword ptr [rip + ce_pending], 1
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# color_prompt(): the pending swatch's prompt, with its color filled in
color_prompt:
    PROLOGUE
    mov dword ptr [rip + ce_pending], 0
    mov rdi, [rip + ce_doc]
    call extproto_doc
    test rax, rax
    jz 8f
    mov rbx, rax
    mov r12, [rip + ce_index]
    mov rax, [rbx + DOC_pres]
    test rax, rax
    jz 8f
    cmp r12, [rax + PRS_colors + VEC_len]
    jae 8f
    imul r13, r12, CLR_SIZE
    add r13, [rax + PRS_colors + VEC_ptr]
    lea rdi, [rip + ce_hex]
    mov byte ptr [rdi], '#'
    inc rdi
    mov esi, [r13 + CLR_rgba]
    or rsi, [rip + .Lce_one]    # (eight digits: the leading one is dropped)
    call fmt_hex
    lea rdi, [rip + ce_hex + 1] # "1rrggbbaa" -> "rrggbbaa"
    lea rsi, [rip + ce_hex + 2]
    mov edx, 8
    call memmove
    lea rdi, [rip + .Lce_label]
    mov esi, PROMPT_COLOR
    lea rdx, [rip + ce_hex]
    mov ecx, 9
    call palette_ext_prompt_open
    call palette_field
    mov rdi, rax
    call tf_select_all
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN color_prompt_done(ptr, len): the prompt's answer: "#rrggbb" or "#rrggbbaa" (# optional) goes
# to the color's provider as color-edit
FN color_prompt_done
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 9f
    cmp byte ptr [rbx], '#'
    jne 1f
    inc rbx
    dec r12
1:  cmp r12, 6
    je 2f
    cmp r12, 8
    jne 7f
2:  mov rdi, rbx
    mov rsi, r12
    call parse_hex
    cmp rdx, r12
    jne 7f
    cmp r12, 8
    je 3f
    shl rax, 8
    or rax, 0xff
3:  mov [rsp], rax              # RRGGBBAA
    mov rdi, [rip + ce_doc]
    call extproto_doc
    test rax, rax
    jz 9f
    mov r13, rax
    mov rax, [r13 + DOC_pres]
    test rax, rax
    jz 9f
    mov rcx, [rip + ce_index]
    cmp rcx, [rax + PRS_colors + VEC_len]
    jae 9f
    imul r14, rcx, CLR_SIZE
    add r14, [rax + PRS_colors + VEC_ptr]
    # "color-edit DOC VERSION L1 C1 L2 C2 RRGGBBAA"
    lea rdi, [rip + ce_line]
    call sb_clear
    lea rdi, [rip + ce_line]
    lea rsi, [rip + .Lv_color_edit]
    call sb_push_cstr
    lea rdi, [rip + ce_line]
    mov rsi, [r13 + DOC_id]
    call sb_push_u64
    lea rdi, [rip + ce_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ce_line]
    mov rsi, [r13 + DOC_version]
    call sb_push_u64
    mov rsi, [r14 + CLR_start]
    call ce_pos
    mov rsi, [r14 + CLR_end]
    call ce_pos
    lea rdi, [rip + ce_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ce_hex]
    mov rsi, [rsp]
    or rsi, [rip + .Lce_one]
    call fmt_hex
    lea rdi, [rip + ce_line]
    lea rsi, [rip + ce_hex + 1]
    mov edx, 8
    call sb_push
    mov r15, [r14 + CLR_owner]
    mov rdi, r15
    mov rsi, r13
    mov rdx, [rip + ce_line + SB_ptr]
    mov rcx, [rip + ce_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz 9f
    mov [rip + ce_id], rax
    mov [rip + ce_ext], r15
    mov rdi, r15
    mov rsi, rax
    mov edx, PK_COLOR_EDIT
    mov ecx, QO_PRESENT
    call query_track
    jmp 9f
7:  lea rdi, [rip + .Lce_bad]
    call app_toast
9:  EPILOGUE

# ce_pos(rsi pos; r13 doc): " L C" (1-based) to ce_line
ce_pos:
    push r15
    push r14
    sub rsp, 8
    mov r15, rsi
    mov rdi, r13
    call doc_line_of
    mov r14, rax
    lea rdi, [rip + ce_line]
    mov esi, ' '
    call sb_push_byte
    lea rsi, [r14 + 1]
    lea rdi, [rip + ce_line]
    call sb_push_u64
    lea rdi, [rip + ce_line]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r13
    mov rsi, r14
    call doc_line_start
    mov rsi, r15
    sub rsi, rax
    inc rsi
    lea rdi, [rip + ce_line]
    call sb_push_u64
    add rsp, 8
    pop r14
    pop r15
    ret

# FN color_edit_reply(ext, id, ok, body, len) -> eax 1 when it answered the color-edit request: the
# workspace edit is made
FN color_edit_reply
    xor eax, eax
    cmp [rip + ce_ext], rdi
    jne 9f
    cmp [rip + ce_id], rsi
    jne 9f
    mov qword ptr [rip + ce_ext], 0
    test edx, edx
    jz 8f
    PROLOGUE
    mov rax, rdi
    mov rdi, rcx
    mov rsi, r8
    mov rdx, rax
    lea rcx, [rip + .Lce_title]
    call ws_apply_from
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  mov eax, 1
9:  ret

# FN color_ext_gone(ext): its colors go
FN color_ext_gone
    PROLOGUE
    mov r12, rdi
    cmp [rip + ce_ext], r12
    jne 0f
    mov qword ptr [rip + ce_ext], 0
0:  xor r13d, r13d
1:  cmp r13, [rip + g_tabs + VEC_len]
    jae 9f
    imul rax, r13, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r13
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rbx, [rax + TAB_doc]
    test rbx, rbx
    jz 1b
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 1b
    xor ecx, ecx
    xor edx, edx
2:  cmp rcx, [r14 + PRS_colors + VEC_len]
    jae 3f
    imul rsi, rcx, CLR_SIZE
    add rsi, [r14 + PRS_colors + VEC_ptr]
    inc rcx
    cmp [rsi + CLR_owner], r12
    je 2b
    imul rdi, rdx, CLR_SIZE
    add rdi, [r14 + PRS_colors + VEC_ptr]
    inc rdx
    mov rax, [rsi]
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    mov [rdi + 24], rax
    jmp 2b
3:  cmp rdx, [r14 + PRS_colors + VEC_len]
    je 1b
    mov [r14 + PRS_colors + VEC_len], rdx
    mov rdi, rbx
    call pres_touch
    jmp 1b
9:  EPILOGUE

# FN color_shift(doc, entry): colors move with the text
FN color_shift
    PROLOGUE
    mov rax, [rdi + DOC_pres]
    mov r14, [rax + PRS_colors + VEC_len]
    test r14, r14
    jz 9f
    mov r15, [rax + PRS_colors + VEC_ptr]
    mov r12, rsi
    mov rsi, [r12 + TE_pos]
    mov rdx, [r12 + TE_del]
    mov rcx, [r12 + TE_ins]
1:  mov rdi, [r15 + CLR_start]
    mov r8d, GR_RIGHT
    call tape_shift
    mov [r15 + CLR_start], rax
    mov rdi, [r15 + CLR_end]
    mov r8d, GR_LEFT
    call tape_shift
    mov [r15 + CLR_end], rax
    add r15, CLR_SIZE
    dec r14
    jnz 1b
9:  EPILOGUE

# FN color_dump(doc, sb): "color L1:C1-L2:C2 RRGGBBAA" per color
FN color_dump
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    xor r15d, r15d
1:  cmp r15, [r13 + PRS_colors + VEC_len]
    jae 9f
    imul r14, r15, CLR_SIZE
    add r14, [r13 + PRS_colors + VEC_ptr]
    inc r15
    mov rdi, r12
    lea rsi, [rip + .Ls_color]
    call sb_push_cstr
    mov rsi, [r14 + CLR_start]
    call hl_put_pos
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov rsi, [r14 + CLR_end]
    call hl_put_pos
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ce_hex]
    mov esi, [r14 + CLR_rgba]
    or rsi, [rip + .Lce_one]
    call fmt_hex
    mov rdi, r12
    lea rsi, [rip + ce_hex + 1]
    mov edx, 8
    call sb_push
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
.Lce_one: .quad 0x100000000
.Lswatch: .ascii "  "
.Lce_label: .asciz "Color (#rrggbb or #rrggbbaa)"
.Lce_bad: .asciz "A color is #rrggbb or #rrggbbaa"
.Lce_title: .asciz "Change Color"
.Lv_color_edit: .asciz "color-edit "
.Ls_color: .asciz "color "
