# soft wrap: lines are split into visual rows at the editor width (breaking after spaces)
# scroll position in wrap mode: top line = DOC_scrolly >> 8, DOC_woff = 1/256 rows into it (see top_offset)
.include "rhun.inc"

.equ MAXROWS, 65536

.bss
.p2align 3
.globl wb_starts, wb_rows
wb_starts: .zero 4 * (MAXROWS + 66)    # byte offset of each row in the line, last = length (and up to 64 rows before it: lens.s)
wb_rows: .long 0

.text

# wrap_cols() -> text columns available
FN wrap_cols
    mov eax, [rip + g_ed_w]
    sub eax, [rip + g_ed_tx]
    add eax, [rip + g_ed_x]
    sub eax, [rip + g_mt + 4*MI_24]
    cdq
    mov ecx, [rip + g_cw]
    test ecx, ecx
    jz 1f
    idiv ecx
    cmp eax, 8
    jge 2f
1:  mov eax, 8
2:  ret

# break_text(text, len, cols) -> rows; fills wb_starts
FN break_text
    PROLOGUE 32
    mov r12, rdi                # text
    mov r13, rsi                # len
    mov [rsp], edx              # cols
    xor ebx, ebx                # rows
    xor r14d, r14d              # row start
.Lbt_row:
    lea rax, [rip + wb_starts]
    mov [rax + rbx*4], r14d
    inc ebx
    cmp ebx, MAXROWS
    jae .Lbt_done
    xor r15d, r15d              # col
    mov rcx, r14                # i
    mov qword ptr [rsp + 8], -1 # after the last space
.Lbt_ch:
    cmp rcx, r13
    jae .Lbt_done
    movzx eax, byte ptr [r12 + rcx]
    mov edx, 1                  # bytes
    cmp al, 9
    jne 1f
    mov eax, r15d
    push rcx
    push rdx
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    mov eax, [rip + g_tab_width]
    sub eax, edx
    pop rdx
    pop rcx
    jmp 3f
1:  cmp al, 0x80
    jb 2f
    push rcx
    push rcx
    lea rdi, [r12 + rcx]
    mov rsi, r13
    sub rsi, rcx
    call utf8_decode
    mov [rsp], edx
    mov edi, eax
    call cp_width
    pop rdx
    pop rcx
    jmp 3f
2:  mov eax, 1
3:  # eax = width, edx = bytes; the inlays at its gap are glued to it (vtext.s)
    cmp qword ptr [rip + bt_n], 0
    je 31f
    mov rdi, rcx
    mov r8d, eax
    call vt_bt_at
    add eax, r8d
31: lea r8d, [r15 + rax]
    cmp r8d, [rsp]
    jle 5f
    cmp rcx, r14
    je 5f
    cmp byte ptr [r12 + rcx], ' '   # spaces hang past the edge
    je 5f
    # wrap: after the last space of this row if any
    mov r9, [rsp + 8]
    cmp r9, r14
    jle 4f
    mov r14, r9
    jmp .Lbt_row
4:  mov r14, rcx
    jmp .Lbt_row
5:  mov r15d, r8d
    cmp byte ptr [r12 + rcx], ' '
    jne 6f
    lea r9, [rcx + 1]
    mov [rsp + 8], r9
6:  add rcx, rdx
    jmp .Lbt_ch
.Lbt_done:
    lea rax, [rip + wb_starts]
    mov [rax + rbx*4], r13d
    mov [rip + wb_rows], ebx
    mov eax, ebx
    EPILOGUE

# line_breaks(doc, line) -> rows (wb_starts filled)
# (a line a fold hides has no rows; without word wrap a line is one row: the view scrolls by rows
# because of folds, fold.s; a line with code lenses has a lens row first, lens.s, g_wb_lens)
FN line_breaks
    push rbx
    push rdi
    push rsi
    mov dword ptr [rip + g_wb_lens], 0
    call fold_hidden
    test eax, eax
    jnz 8f
    mov rdi, [rsp + 8]
    mov rsi, [rsp]
    call vt_bt_set              # its inlays count (vtext.s)
    mov rdi, [rsp + 8]
    mov rsi, [rsp]
    call doc_line_text
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 7f
    mov rbx, rax
    push rdx
    push rdx
    call wrap_cols
    mov edx, eax
    pop rsi
    pop rsi
    mov rdi, rbx
    call break_text
    jmp 6f
7:  lea rax, [rip + wb_starts]
    mov dword ptr [rax], 0
    mov [rax + 4], edx
    mov dword ptr [rip + wb_rows], 1
    mov eax, 1
6:  pop rsi
    pop rdi
    pop rbx
    mov edx, eax
    jmp lens_row_add            # a code lens row first (lens.s)
8:  pop rsi
    pop rdi
    lea rax, [rip + wb_starts]
    mov dword ptr [rax], 0
    mov dword ptr [rip + wb_rows], 0
    xor eax, eax
    pop rbx
    ret

# row_of(off, rows, is_last_char_line) -> row containing byte offset off (a break offset starts the next row)
row_of:
    lea r8, [rip + wb_starts]
    mov eax, esi
    dec eax
1:  test eax, eax
    jz 2f
    cmp edi, [r8 + rax*4]
    jae 2f
    dec eax
    jmp 1b
2:  ret

# pos_in_row(doc, line, row, col) -> document position at visual column col of that row (needs wb_starts)
FN pos_in_row
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], ecx
    mov qword ptr [rip + g_vt_hit], 0
    call vt_bt_set              # the line's inlays (vtext.s)
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov r14, rax
    lea rax, [rip + wb_starts]
    mov ecx, [rax + r13*4]      # from
    mov r15d, [rax + r13*4 + 4] # to
    # the break position itself belongs to the next row unless it is the last row
    lea edx, [r13 + 1]
    cmp edx, [rip + wb_rows]
    jae 1f
    cmp r15d, ecx
    je 1f
    dec r15d
1:  xor ebx, ebx                # col
.Lpr_ch:
    cmp ecx, r15d
    jae .Lpr_end
    movzx eax, byte ptr [r14 + rcx]
    mov edx, 1
    cmp al, 9
    jne 2f
    mov eax, ebx
    push rcx
    push rdx
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    mov eax, [rip + g_tab_width]
    sub eax, edx
    pop rdx
    pop rcx
    jmp 4f
2:  cmp al, 0x80
    jb 3f
    push rcx
    push rcx
    lea rdi, [r14 + rcx]
    mov esi, 4
    call utf8_decode
    mov [rsp], edx
    mov edi, eax
    call cp_width
    pop rdx
    pop rcx
    jmp 4f
3:  mov eax, 1
4:  # the inlays at its gap: the target on one of them is the gap
    cmp qword ptr [rip + bt_n], 0
    je 41f
    push rax
    push rdx
    push rcx
    push rcx
    mov rdi, rcx
    mov esi, [rsp + 32]
    sub esi, ebx
    call vt_bt_hit
    mov r8d, edx
    pop rcx
    pop rcx
    pop rdx
    pop r9
    add ebx, eax
    test r8d, r8d
    jnz .Lpr_done
    mov eax, r9d
41: # stop if the target column lies in this character (nearest edge)
    lea r8d, [rbx + rax]
    cmp r8d, [rsp]
    jle 5f
    mov r9d, [rsp]
    sub r9d, ebx
    add r9d, r9d
    cmp r9d, eax
    jl .Lpr_done
    add ecx, edx
    jmp .Lpr_done
5:  mov ebx, r8d
    add ecx, edx
    jmp .Lpr_ch
.Lpr_end:
    # the row's end: on the last row, the inlays at the line's end (a fold's pill, vtext.s)
    cmp qword ptr [rip + bt_n], 0
    je .Lpr_done
    lea edx, [r13 + 1]
    cmp edx, [rip + wb_rows]
    jb .Lpr_done
    push rcx
    push rcx
    mov rdi, rcx
    mov esi, [rsp + 16]
    sub esi, ebx
    call vt_bt_hit
    pop rcx
    pop rcx
.Lpr_done:
    mov eax, ecx
    add rax, [rsp + 8]
    EPILOGUE

# seg_cols(text, from, to) -> visual columns of text[from..to) with tab stops relative to from
FN seg_cols
    xor ecx, ecx
# seg_cols_from(text, from, to, column at from) -> column at to, keeping the row's tab stops
FN seg_cols_from
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov ebx, ecx
1:  cmp r13, r14
    jae 9f
    movzx eax, byte ptr [r12 + r13]
    cmp al, 9
    jne 2f
    mov eax, ebx
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    mov eax, [rip + g_tab_width]
    sub eax, edx
    add ebx, eax
    inc r13
    jmp 1b
2:  cmp al, 0x80
    jb 3f
    lea rdi, [r12 + r13]
    mov rsi, r14
    sub rsi, r13
    call utf8_decode
    add r13, rdx
    mov edi, eax
    call cp_width
    add ebx, eax
    jmp 1b
3:  inc ebx
    inc r13
    jmp 1b
9:  mov eax, ebx
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# cursor_row(doc) -> rax line, edx row, ecx column within the row (wb_starts filled for that line)
FN cursor_row
    PROLOGUE 16
    mov rbx, rdi
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r13, [rbx + DOC_cur]
    sub r13, rax                # offset in line
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    mov r14d, eax
    mov edi, r13d
    mov esi, r14d
    call row_of
    mov r15d, eax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    lea rcx, [rip + wb_starts]
    mov esi, [rcx + r15*4]
    mov r14d, esi
    mov rdi, rax
    mov rdx, r13
    call seg_cols
    mov ecx, eax
    cmp qword ptr [rip + bt_n], 0
    je 1f
    push rcx
    push rcx
    mov edi, r14d               # and the inlays before the caret (vtext.s)
    mov rsi, r13
    call vt_bt_before
    pop rcx
    pop rcx
    add ecx, eax
1:  mov rax, r12
    mov edx, r15d
    EPILOGUE

# line_px(doc, line) -> height of the line in pixels
line_px:
    push rbx
    call line_breaks
    imul eax, [rip + g_lh]
    pop rbx
    ret

# scroll_by_px(doc, dy): move the wrapped view by dy pixels (kept in 1/256 rows so small steps add up)
FN scroll_by_px
    PROLOGUE 16
    mov rbx, rdi
    movsxd r15, esi
    test r15, r15
    jz 9f
    mov rax, r15
    shl rax, 8
    cqo
    movsxd rcx, dword ptr [rip + g_lh]
    idiv rcx
    test rax, rax
    jnz 1f
    mov eax, 1
    test r15, r15
    jns 1f
    mov rax, -1
1:  mov r15, rax                # delta
    mov r12, [rbx + DOC_scrolly]
    shr r12, 8                  # line
    xor r13d, r13d              # offset into it
    cmp r12, [rbx + DOC_wtop]
    jne 2f
    mov r13, [rbx + DOC_woff]
2:  add r13, r15
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    shl eax, 8
    mov r14d, eax               # size of the line
.Lsp_loop:
    test r13, r13
    jns 3f
    test r12, r12
    jz 4f
    dec r12
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    shl eax, 8
    mov r14d, eax
    add r13, rax
    jmp .Lsp_loop
4:  xor r13d, r13d
    jmp 6f
3:  cmp r13, r14
    jl 6f
    lea rax, [r12 + 1]
    cmp rax, [rbx + DOC_nlines]
    jae 5f
    sub r13, r14
    inc r12
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    shl eax, 8
    mov r14d, eax
    jmp .Lsp_loop
5:  lea r13, [r14 - 256]        # last line: its last row on top at most
6:  mov [rbx + DOC_woff], r13
    mov [rbx + DOC_wtop], r12
    shl r12, 8
    mov [rbx + DOC_scrolly], r12
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# wrap_clamp(doc): without scroll_past_end keep the view filled down to the last row
FN wrap_clamp
    PROLOGUE
    mov rbx, rdi
    call top_offset
    neg eax
    movsxd r13, eax             # px from the view top to the start of line r12
    mov r12, [rbx + DOC_scrolly]
    shr r12, 8
    movsxd r14, dword ptr [rip + g_ed_h]
1:  cmp r13, r14
    jge 9f
    cmp r12, [rbx + DOC_nlines]
    jae 2f
    mov rdi, rbx
    mov rsi, r12
    call line_px
    add r13, rax
    inc r12
    jmp 1b
2:  # the end is above the bottom edge: put the last row there
    mov rsi, [rbx + DOC_nlines]
    dec rsi
    mov rdi, rbx
    call line_breaks
    lea edx, [rax - 1]
    mov rsi, [rbx + DOC_nlines]
    dec rsi
    mov rdi, rbx
    call set_top_row
    mov esi, [rip + g_ed_h]
    sub esi, [rip + g_lh]
    neg esi
    mov rdi, rbx
    call scroll_by_px
9:  EPILOGUE

# top_offset(doc) -> px from the top line's first row to the view top
FN top_offset
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov rsi, [rbx + DOC_scrolly]
    shr rsi, 8
    xor r12d, r12d
    cmp rsi, [rbx + DOC_wtop]
    jne 1f
    mov r12, [rbx + DOC_woff]
    call line_breaks
    shl eax, 8
    cmp r12, rax
    jb 1f
    lea r12, [rax - 256]
1:  mov rax, r12
    imul eax, [rip + g_lh]
    shr eax, 8
    add rsp, 8
    pop r12
    pop rbx
    ret

# reveal_wrap(doc): keep the cursor row inside the view
FN reveal_wrap
    PROLOGUE 16
    mov rbx, rdi
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 0f
    mov qword ptr [rbx + DOC_scrollx], 0
0:
    mov rdi, rbx
    call cursor_row
    mov r12, rax                # cursor line
    mov r13d, edx               # cursor row
    mov r14, [rbx + DOC_scrolly]
    shr r14, 8                  # top line
    cmp r12, r14
    jb .Lrw_top
    # y of the cursor row relative to the view top
    mov rdi, rbx
    call top_offset
    neg eax
    movsxd r15, eax
    mov rcx, r12
    sub rcx, r14
    mov eax, [rip + g_ed_h]
    xor edx, edx
    div dword ptr [rip + g_lh]
    cmp rcx, rax
    ja .Lrw_bottom              # far below: no need to measure
    mov [rsp], r14
1:  mov rax, [rsp]
    cmp rax, r12
    jae 2f
    mov rdi, rbx
    mov rsi, rax
    call line_px
    add r15, rax
    inc qword ptr [rsp]
    jmp 1b
2:  mov eax, r13d
    imul eax, [rip + g_lh]
    add r15, rax                # cursor row y
    js .Lrw_top
    mov eax, [rip + g_lh]
    add rax, r15
    movsxd rcx, dword ptr [rip + g_ed_h]
    cmp rax, rcx
    jle .Lrw_ret
.Lrw_bottom:
    # cursor row at the top, then scroll up by the view height minus two rows
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call set_top_row
    mov esi, [rip + g_ed_h]
    sub esi, [rip + g_lh]
    sub esi, [rip + g_lh]
    neg esi
    mov rdi, rbx
    call scroll_by_px
    jmp .Lrw_ret
.Lrw_top:
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call set_top_row
.Lrw_ret:
    EPILOGUE

# center_wrap(doc): the cursor row in the middle of the view, counting wrapped rows above it
FN center_wrap
    push rbx
    mov rbx, rdi
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 0f
    mov qword ptr [rbx + DOC_scrollx], 0
0:
    call cursor_row
    mov rdi, rbx
    mov rsi, rax
    call set_top_row
    mov esi, [rip + g_ed_h]
    sub esi, [rip + g_lh]
    sar esi, 1
    neg esi
    mov rdi, rbx
    pop rbx
    jmp scroll_by_px

# set_top_row(doc, line, row): scroll so that row of line is the first visible
set_top_row:
    mov [rdi + DOC_wtop], rsi
    shl edx, 8
    mov [rdi + DOC_woff], rdx
    shl rsi, 8
    mov [rdi + DOC_scrolly], rsi
    ret

# wrap_pos_at(doc, px, py) -> position under the point
FN wrap_pos_at
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    mov r13d, edx
    sub r13d, [rip + g_ed_y]    # y relative to the view
    mov rdi, rbx
    call top_offset
    add r13d, eax               # y relative to the top line's first row
    mov r12, [rbx + DOC_scrolly]
    shr r12, 8
    test r13d, r13d
    jns 1f
    xor r13d, r13d
1:  cmp r12, [rbx + DOC_nlines]
    jae .Lwp_end
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    mov r14d, eax
    imul eax, [rip + g_lh]
    cmp r13d, eax
    jl 2f
    sub r13d, eax
    inc r12
    jmp 1b
2:  mov eax, r13d
    xor edx, edx
    div dword ptr [rip + g_lh]
    mov r15d, eax               # row
    xor ecx, ecx                # a row put before the text (ghost text's, a code lens's: lens.s)?
    mov eax, [rip + g_wb_lens]
    cmp r15d, eax
    jae 22f
    dec eax
    cmp r15d, eax               # the last of them: the lens row, when there is one
    jne 22f
    mov ecx, 1
22: mov [rsp + 4], ecx
    mov eax, [rsp]
    sub eax, [rip + g_ed_tx]
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne 21f
    add eax, [rbx + DOC_scrollx]    # rows because of folds: lines scroll sideways
21: mov ecx, [rip + g_cw]
    shr ecx, 1
    add eax, ecx
    jns 3f
    xor eax, eax
3:  xor edx, edx
    div dword ptr [rip + g_cw]
    mov rdi, rbx
    mov rsi, r12
    mov edx, r15d
    mov ecx, eax
    call pos_in_row
    cmp dword ptr [rsp + 4], 0
    je 4f
    mov [rsp + 8], rax
    mov rdi, rbx                # the lens item under the pointer becomes the hit (lens.s)
    mov rsi, r12
    mov edx, [rsp]
    call lens_hit
    mov rax, [rsp + 8]
4:  EPILOGUE
.Lwp_end:
    mov rdi, rbx
    call doc_len
    EPILOGUE

# wrap_move(doc, dir, preferred col) -> new position one visual row up (-1) or down (+1)
FN wrap_move
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    call cursor_row
    mov r12, rax                # line
    mov r13d, edx               # row
    mov r14d, [rip + wb_rows]
    cmp dword ptr [rsp], 0
    jl .Lwm_up
    lea eax, [r13 + 1]
    cmp eax, r14d
    jae 1f
    mov edx, eax
    jmp .Lwm_go
1:  lea rsi, [r12 + 1]
    mov rdi, rbx
    call fold_next_visible      # over folded lines (fold.s)
    cmp rax, [rbx + DOC_nlines]
    jae .Lwm_end
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    mov edx, [rip + g_wb_lens]  # its first text row: past a code lens row (lens.s)
    jmp .Lwm_go
.Lwm_up:
    cmp r13d, [rip + g_wb_lens]
    jbe 2f
    lea edx, [r13 - 1]
    jmp .Lwm_go
2:  test r12, r12
    jz .Lwm_start
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call fold_prev_visible
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    lea edx, [rax - 1]
.Lwm_go:
    mov rdi, rbx
    mov rsi, r12
    mov ecx, [rsp + 4]
    call pos_in_row
    EPILOGUE
.Lwm_start:
    xor eax, eax
    EPILOGUE
.Lwm_end:
    mov rdi, rbx
    call doc_len
    EPILOGUE

# wrap_xy(doc, pos) -> eax the caret's x from the text's left edge, edx the y of its row's top from
# the view's top (inlays counted; for the headless print-xy)
FN wrap_xy
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax                # line
    mov rdi, rbx
    call top_offset
    neg eax
    movsxd r14, eax             # y
    mov r15, [rbx + DOC_scrolly]
    shr r15, 8
1:  cmp r15, r13
    jae 2f
    mov rdi, rbx
    mov rsi, r15
    call line_px
    add r14, rax
    inc r15
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    sub r12, rax                # offset in the line
    mov rdi, rbx
    mov rsi, r13
    call line_breaks
    mov edi, r12d
    mov esi, eax
    call row_of
    mov r15d, eax
    mov eax, r15d
    imul eax, [rip + g_lh]
    add r14, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    lea rcx, [rip + wb_starts]
    mov esi, [rcx + r15*4]
    mov [rsp], esi
    mov rdi, rax
    mov rdx, r12
    call seg_cols
    mov [rsp + 4], eax
    mov edi, [rsp]
    mov rsi, r12
    call vt_bt_before
    add eax, [rsp + 4]
    imul eax, [rip + g_cw]
    mov edx, r14d
    EPILOGUE

FN cmd_toggle_word_wrap
    xor dword ptr [rip + cfg_word_wrap], 1
    mov rax, [rip + g_doc]
    test rax, rax
    jz 1f
    mov qword ptr [rax + DOC_scrollx], 0
    and qword ptr [rax + DOC_scrolly], -256
    mov qword ptr [rax + DOC_woff], 0
1:  mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_reveal], 1
    mov dword ptr [rip + g_dirty], 1
    ret
