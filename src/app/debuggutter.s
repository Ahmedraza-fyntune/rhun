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

.section .rodata
.Lbreakpoint: .asciz "Breakpoint"
.Lif: .asciz ", if "
.Lhit: .asciz ", hit count "
.Llog: .asciz ", logs "
.Ldash: .asciz " - "
.p2align 3
tip_parts: .quad BP_cond, .Lif, BP_hit, .Lhit, BP_log, .Llog, 0, 0
