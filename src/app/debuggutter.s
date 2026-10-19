# debugger in the editor: breakpoints and the current line in the gutter's left lane (gutter.s
# kinds), the current line's background, and clicks in the lane (toggle; right click: a menu)
.include "rhun.inc"

.equ DG_DOCS, 256

.data
dg_kind_bp: .long 0             # gutter kinds, 0 until registered
dg_kind_line: .long 0
.p2align 3
.globl g_dg_doc, g_dg_line
g_dg_doc: .quad 0               # the paused frame's document and line (zero-based), 0 / -1
g_dg_line: .quad -1
dg_line_slot: .long T_WARNING   # the arrow's color: the top frame, else another one
.bss
.p2align 3
hv_doc: .quad 0                 # the position last evaluated (or found to hold nothing)
hv_pos: .quad 0
hv_gen: .quad 0                 # stop_key when it was
hv_expr: .zero 260
hv_text: .zero 1040             # its answer, empty while none
hv_expr_sb: .zero SB_SIZE
.p2align 3
dg_docs: .zero 16 * DG_DOCS     # documents synced: DOC*, the generation they were filled at
dg_gen: .long 0                 # the generation of what was last asked for
dg_line_gen: .long 0
tipb: .zero 512

.text

# dg_kinds(): the two gutter kinds, registered once
dg_kinds:
    PROLOGUE
    cmp dword ptr [rip + dg_kind_bp], 0
    jne 9f
    mov edi, GK_PRIO_BREAKPOINT
    mov esi, GK_EMPTY | GK_RESERVE
    lea rdx, [rip + dg_click]
    lea rcx, [rip + dg_tip]
    mov r8d, GS_DOT | (T_ERROR << 8) | (GF_FAINT << 16)
    call gutter_kind
    mov [rip + dg_kind_bp], eax
    mov edi, GK_PRIO_DEBUG_LINE
    xor esi, esi
    lea rdx, [rip + dg_click]
    xor ecx, ecx
    xor r8d, r8d
    call gutter_kind
    mov [rip + dg_kind_line], eax
9:  EPILOGUE

# dg_tick(): every frame: the open documents' breakpoint glyphs and the current line follow the model
FN dg_tick
    PROLOGUE
    call dg_kinds
    cmp dword ptr [rip + dg_kind_bp], 0
    je 9f
    mov eax, [rip + g_bp_gen]
    add eax, [rip + g_dap_gen]
    mov [rip + dg_gen], eax
    # each tab's document
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 5f
    imul rax, rbx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 4f
    cmp qword ptr [r12 + DOC_path], 0
    je 4f
    mov rdi, r12
    call doc_synced
    test eax, eax
    jnz 4f
    mov rdi, r12
    call dg_fill
4:  inc rbx
    jmp 1b
5:  call dg_current
9:  EPILOGUE

# doc_synced(doc) -> eax 1 when its glyphs are of the current generation; else it is marked so
doc_synced:
    lea rcx, [rip + dg_docs]
    xor edx, edx
    mov r8d, -1                 # a free slot
1:  cmp edx, DG_DOCS
    jae 3f
    mov rax, [rcx]
    cmp rax, rdi
    je 2f
    test rax, rax
    jnz 11f
    cmp r8d, -1
    jne 11f
    mov r8d, edx
11: add rcx, 16
    inc edx
    jmp 1b
2:  mov eax, [rip + dg_gen]
    cmp [rcx + 8], eax
    mov [rcx + 8], eax
    sete al
    movzx eax, al
    ret
3:  # not seen: a slot (the first free, else the first)
    xor edx, edx
    cmp r8d, -1
    je 4f
    mov edx, r8d
4:  shl edx, 4
    lea rcx, [rip + dg_docs]
    mov [rcx + rdx], rdi
    mov eax, [rip + dg_gen]
    mov [rcx + rdx + 8], eax
    xor eax, eax
    ret

# dg_fill(doc): its breakpoint glyphs, from the breakpoints of its file
dg_fill:
    PROLOGUE
    mov r12, rdi
    mov rdi, r12
    mov esi, [rip + dg_kind_bp]
    call gutter_glyph_clear
    call bp_ensure_loaded
    xor ebx, ebx
1:  call bp_count
    cmp rbx, rax
    jae 9f
    mov rdi, rbx
    call bp_row
    mov r13, rax
    cmp dword ptr [r13 + BP_kind], 0
    jne 2f
    mov rdi, [r13 + BP_path]
    mov rsi, [r12 + DOC_path]
    call strcmp_eq
    test eax, eax
    jz 2f
    mov rdi, r13
    call bp_glyph
    mov ecx, eax
    mov edx, [r13 + BP_line]
    dec edx
    mov rdi, r12
    mov esi, [rip + dg_kind_bp]
    call gutter_glyph_set
2:  inc rbx
    jmp 1b
9:  EPILOGUE

# bp_glyph(bp) -> eax its glyph: a dot (grey when disabled), a ring while the focused session has not
#   verified it, a circle with a bar for a condition or hit count, a diamond for a logpoint, a
#   warning when the adapter rejected it
bp_glyph:
    mov eax, GS_DOT | (T_ERROR << 8)
    cmp qword ptr [rdi + BP_cond], 0
    jne 1f
    cmp qword ptr [rdi + BP_hit], 0
    je 2f
1:  mov eax, GS_CIRCLE_BAR | (T_ERROR << 8)
2:  cmp qword ptr [rdi + BP_log], 0
    je 3f
    mov eax, GS_DIAMOND | (T_ERROR << 8)
3:  cmp dword ptr [rdi + BP_enabled], 0
    jne 4f
    and eax, 0xff
    or eax, T_MUTED << 8
    ret
4:  mov ecx, [rip + g_dfocus]
    test ecx, ecx
    js 9f
    mov edx, [rdi + BP_ver + rcx*4]
    cmp edx, 1
    jne 5f
    and eax, 0xff00
    or eax, GS_RING
    ret
5:  cmp edx, 3
    jne 9f
    mov eax, GS_CIRCLE_TRI | (T_WARNING << 8)
9:  ret

# dg_current(): the arrow on the paused frame's line (when its file is open), its background
dg_current:
    PROLOGUE
    mov eax, [rip + g_dap_gen]
    cmp eax, [rip + dg_line_gen]
    je 9f
    mov [rip + dg_line_gen], eax
    xor edi, edi
    mov esi, [rip + dg_kind_line]
    call gutter_glyph_clear
    mov qword ptr [rip + g_dg_doc], 0
    mov qword ptr [rip + g_dg_line], -1
    call dap_focused
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + DS_state], DSS_PAUSED
    jne 9f
    mov rdi, rbx
    call dap_frame_ptr
    test rax, rax
    jz 9f
    mov r12, rax
    cmp dword ptr [r12 + FR_pathlen], 0
    je 9f
    cmp dword ptr [r12 + FR_line], 0
    je 9f
    mov rdi, rbx
    mov esi, [r12 + FR_path]
    mov edx, [r12 + FR_pathlen]
    call dap_pool_z
    mov rdi, rax
    call app_find_tab
    test rax, rax
    js 9f
    imul rax, rax, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz 9f
    mov eax, [r12 + FR_line]
    dec eax
    mov [rip + g_dg_doc], r13
    mov [rip + g_dg_line], rax
    mov ecx, GS_ARROW | (T_WARNING << 8)
    cmp dword ptr [rbx + DS_frame], 0
    je 1f
    mov ecx, GS_ARROW | (T_SUCCESS << 8)
1:  mov [rip + dg_line_slot], ecx
    mov rdi, r13
    mov esi, [rip + dg_kind_line]
    mov edx, eax
    call gutter_glyph_set
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# dbg_line_back(doc, line, y, h): the paused frame's line gets a background (the editor's line loop,
#   beside decorations' whole-line backgrounds)
FN dbg_line_back
    cmp [rip + g_dg_doc], rdi
    jne 1f
    cmp [rip + g_dg_line], rsi
    jne 1f
    push rbx
    push r12
    push r13
    mov r12d, edx
    mov r13d, ecx
    mov eax, [rip + dg_line_slot]
    shr eax, 8
    and eax, 0xff
    lea rcx, [rip + g_theme]
    mov edi, [rcx + rax*4]
    mov esi, 0x30
    call color_alpha
    mov r8d, eax
    mov edi, [rip + g_ed_tx]
    sub edi, [rip + g_mt + 4*MI_4]
    mov edx, [rip + g_ed_x]
    add edx, [rip + g_ed_w]
    sub edx, edi
    mov esi, r12d
    mov ecx, r13d
    call gfx_fill
    pop r13
    pop r12
    pop rbx
1:  ret

# dg_click(doc, line, button, glyph): a left press toggles the line's breakpoint; a right press opens
#   the breakpoint menu
dg_click:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rsi, [rbx + DOC_path]
    test rsi, rsi
    jz 9f
    cmp r13d, BTN_RIGHT
    je 2f
    mov rdi, rsi
    lea esi, [r12 + 1]
    call bp_toggle
    jmp 9f
2:  mov rdi, rbx
    mov rsi, r12
    call dview_bp_menu
9:  EPILOGUE

# dg_tip(doc, line, glyph) -> rax the breakpoint's tooltip: its condition, hit count, log message,
#   or what the adapter said
dg_tip:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 8f
    lea esi, [rsi + 1]
    call bp_find
    test eax, eax
    js 8f
    mov edi, eax
    call bp_row
    mov r12, rax
    lea rdi, [rip + tipb]
    lea rsi, [rip + .Lbreakpoint]
    call cstr_copy
    mov r13, rax
    lea r14, [rip + tip_parts]
1:  mov rcx, [r14]
    test rcx, rcx
    jz 3f
    mov rsi, [r12 + rcx]
    test rsi, rsi
    jz 2f
    mov rdi, r13
    mov rsi, [r14 + 8]
    call cstr_copy
    mov rdi, rax
    mov rcx, [r14]
    mov rsi, [r12 + rcx]
    lea rdx, [rip + tipb + 400]
    call copy_max_dg
    mov r13, rax
2:  add r14, 16
    jmp 1b
3:  mov ecx, [rip + g_dfocus]
    test ecx, ecx
    js 4f
    mov rsi, [r12 + BP_msg + rcx*8]
    test rsi, rsi
    jz 4f
    mov rdi, r13
    lea rsi, [rip + .Ldash]
    call cstr_copy
    mov rdi, rax
    mov ecx, [rip + g_dfocus]
    mov rsi, [r12 + BP_msg + rcx*8]
    lea rdx, [rip + tipb + 500]
    call copy_max_dg
4:  lea rax, [rip + tipb]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# copy_max_dg(dst, src, limit) -> end
copy_max_dg:
1:  cmp rdi, rdx
    jae 2f
    mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rdi
    inc rsi
    jmp 1b
2:  mov byte ptr [rdi], 0
    mov rax, rdi
    ret


# ---------------- hover evaluation ----------------

# dg_hover_tick(): while the focused session is paused and the pointer has rested 500 ms on an
#   identifier (or inside the selection), the expression there is evaluated in the focused frame
FN dg_hover_tick
    PROLOGUE
    mov rbx, [rip + g_hover_doc]
    test rbx, rbx
    jz 8f
    cmp [rip + hv_doc], rbx
    jne 1f
    mov rax, [rip + g_hover_pos]
    cmp [rip + hv_pos], rax
    jne 1f
    call stop_key
    cmp [rip + hv_gen], rax
    je 9f                       # asked already (or nothing to ask) for this position and stop
1:  call time_ms
    sub rax, [rip + g_hover_since]
    cmp rax, HOVER_REST_MS
    jb 9f
    mov [rip + hv_doc], rbx
    mov rax, [rip + g_hover_pos]
    mov [rip + hv_pos], rax
    call stop_key
    mov [rip + hv_gen], rax
    mov byte ptr [rip + hv_text], 0
    mov dword ptr [rip + g_dirty], 1
    call dap_focused
    test rax, rax
    jz 9f
    mov r12, rax
    cmp dword ptr [r12 + DS_state], DSS_PAUSED
    jne 9f
    mov rdi, rbx
    mov rsi, [rip + g_hover_pos]
    call hover_expr
    test eax, eax
    jz 9f
    mov rdi, r12
    lea rsi, [rip + hv_expr]
    call dap_hover_eval
    EPILOGUE
8:  mov qword ptr [rip + hv_doc], 0
    mov byte ptr [rip + hv_text], 0
9:  EPILOGUE

# dg_hover_due() -> ms until dg_hover_tick has work, or -1
FN dg_hover_due
    mov rax, [rip + g_hover_doc]
    test rax, rax
    jz 8f
    cmp [rip + hv_doc], rax
    jne 1f
    mov rax, [rip + g_hover_pos]
    cmp [rip + hv_pos], rax
    jne 1f
    push rbx
    call stop_key
    pop rbx
    cmp [rip + hv_gen], rax
    je 8f
1:  push rbx
    call dap_focused
    pop rbx
    test rax, rax
    jz 8f
    cmp dword ptr [rax + DS_state], DSS_PAUSED
    jne 8f
    push rbx
    call time_ms
    pop rbx
    mov rcx, [rip + g_hover_since]
    add rcx, HOVER_REST_MS
    sub rcx, rax
    jns 2f
    xor ecx, ecx
2:  mov eax, ecx
    ret
8:  mov eax, -1
    ret

# stop_key() -> rax which stop the focused session is at: its id << 32 | its epoch (0 without one)
stop_key:
    push rbx
    call dap_focused
    test rax, rax
    jz 1f
    mov ecx, [rax + DS_id]
    shl rcx, 32
    mov eax, [rax + DS_epoch]
    or rax, rcx
1:  pop rbx
    ret

# hover_expr(doc, pos) -> eax 1 with hv_expr (NUL-terminated): the selection when pos is inside it
#   (one line, 256 bytes at most), else the identifier at pos with the member chain to its left
#   (a.b->c)
hover_expr:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + hv_expr_sb]
    call sb_clear
    mov r13, [rbx + DOC_cur]
    mov r14, [rbx + DOC_anchor]
    cmp r13, r14
    je 2f
    jb 1f
    xchg r13, r14
1:  cmp r12, r13
    jb 2f
    cmp r12, r14
    jae 2f
    mov r15, r14
    sub r15, r13
    cmp r15, 256
    ja 2f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r15
    call doc_range
    xor ecx, ecx
11: cmp rcx, r15
    jae 12f
    cmp byte ptr [rax + rcx], 10
    je 2f
    inc rcx
    jmp 11b
12: mov rsi, rax
    mov rdx, r15
    jmp 7f
2:  # the identifier at pos
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov r14, r12
    sub r14, rax                # the column
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    mov r13, rax                # the line's bytes
    mov r15, rdx                # their length
    cmp r14, r15
    jae 8f
    movzx edi, byte ptr [r13 + r14]
    call hv_ident
    test eax, eax
    jz 8f
    mov rcx, r14                # end
3:  inc rcx
    cmp rcx, r15
    jae 31f
    push rcx
    push rcx
    movzx edi, byte ptr [r13 + rcx]
    call hv_ident
    pop rcx
    pop rcx
    test eax, eax
    jnz 3b
31: mov [rsp], rcx
    mov rcx, r14                # start
4:  test rcx, rcx
    jz 6f
    push rcx
    push rcx
    movzx edi, byte ptr [r13 + rcx - 1]
    call hv_ident
    pop rcx
    pop rcx
    test eax, eax
    jz 5f
    dec rcx
    jmp 4b
5:  # a member chain: "." or "->" before the identifier, then another identifier
    cmp byte ptr [r13 + rcx - 1], '.'
    jne 51f
    cmp rcx, 2
    jb 6f
    lea rdx, [rcx - 1]
    jmp 52f
51: cmp rcx, 3
    jb 6f
    cmp byte ptr [r13 + rcx - 1], '>'
    jne 6f
    cmp byte ptr [r13 + rcx - 2], '-'
    jne 6f
    lea rdx, [rcx - 2]
52: push rcx
    push rdx
    movzx edi, byte ptr [r13 + rdx - 1]
    call hv_ident
    pop rdx
    pop rcx
    test eax, eax
    jz 6f
    mov rcx, rdx
    jmp 4b
6:  lea rsi, [r13 + rcx]
    mov rdx, [rsp]
    sub rdx, rcx
7:  cmp rdx, 255
    ja 8f
    lea rdi, [rip + hv_expr]
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rax, [rip + hv_expr]
    mov byte ptr [rax + rdx], 0
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# hv_ident(byte) -> eax 1 for an identifier byte (is_ident, and $ for shells and PHP)
hv_ident:
    cmp edi, '$'
    je 1f
    jmp is_ident
1:  mov eax, 1
    ret

# dg_hover_answer(ptr, len, type ptr, len): the evaluation's answer: "EXPR = VALUE  TYPE"
FN dg_hover_answer
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    lea rdi, [rip + hv_text]
    lea rsi, [rip + hv_expr]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Lhv_eq]
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    mov rcx, r13
    lea rdx, [rip + hv_text + 900]
    call memcpy_dg
    test r15, r15
    jz 1f
    mov rdi, rax
    lea rsi, [rip + .Lhv_sp]
    call cstr_copy
    mov rdi, rax
    mov rsi, r14
    mov rcx, r15
    lea rdx, [rip + hv_text + 1000]
    call memcpy_dg
1:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# memcpy_dg(dst, src, limit, n) -> end: n bytes (a newline as a space), stopping at limit, NUL
memcpy_dg:
1:  test rcx, rcx
    jz 2f
    cmp rdi, rdx
    jae 2f
    mov al, [rsi]
    cmp al, 10
    jne 11f
    mov al, ' '
11: mov [rdi], al
    inc rdi
    inc rsi
    dec rcx
    jmp 1b
2:  mov byte ptr [rdi], 0
    mov rax, rdi
    ret

# dg_hover_text() -> rax the debugger's hover for the rest position, or 0 (ext_hover_tip shows it
#   alone while paused)
FN dg_hover_text
    xor eax, eax
    mov rcx, [rip + g_hover_doc]
    test rcx, rcx
    jz 1f
    cmp [rip + hv_doc], rcx
    jne 1f
    mov rcx, [rip + g_hover_pos]
    cmp [rip + hv_pos], rcx
    jne 1f
    cmp byte ptr [rip + hv_text], 0
    je 1f
    lea rax, [rip + hv_text]
1:  ret

.section .rodata
.Lhv_eq: .asciz " = "
.Lhv_sp: .asciz "  "
.Lbreakpoint: .asciz "Breakpoint"
.Lif: .asciz ", if "
.Lhit: .asciz ", hit count "
.Llog: .asciz ", logs "
.Ldash: .asciz " - "
.p2align 3
tip_parts: .quad BP_cond, .Lif, BP_hit, .Lhit, BP_log, .Llog, 0, 0
