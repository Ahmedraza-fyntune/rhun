# editor presentation: code lens (feature code-lens). rhun asks every matching provider for the
# document's lenses (present.s: when it becomes active, 500 ms after edits, 100 ms after a scroll
# leaves the lines asked about, whose titles the provider fills in); an answer replaces all of that
# provider's lenses. A line with lenses gets a row above it (wrap.s's rows: line_breaks puts it
# first, draw_wrapped draws it here), its titles in the small face at the line's indentation,
# " | " between them, eight at most; a title not resolved yet is drawn "…". A click runs the
# lens's command; the pointer resting on it shows its tip. When lenses come or go on the view's
# top line the text stays where it was.
.include "rhun.inc"

.equ LENS_SHOWN, 8

.bss
.p2align 3
ln_new: .zero VEC_SIZE          # an answer's lenses
ln_tmp: .zero VEC_SIZE
.globl g_wb_lens
g_wb_lens: .long 0              # 1: wb_starts' row 0 is a lens row (line_breaks)
.p2align 3
li_n: .quad 0                   # lens_items: the items of a line's lens row
li_buf: .zero LENS_SHOWN * 24   # lens index, x0, x1 (x0, x1 from the row's text start)
li_x: .quad 0                   # the row's first item's x on screen
tipbuf: .zero 1024 + 8

.text

# ---------------- answers ----------------

# FN lens_reply(doc, ext, body, len, version, PQR*) -> eax 1 taken, 0 dropped: "N" LF, then per
# lens "LINE TITLE_LEN EXTRA_LEN" LF TITLE EXTRA. Every lens of the document: they replace the
# provider's.
FN lens_reply
    PROLOGUE 64
    mov r13, rdi                # doc
    mov [rsp], rsi              # ext
    mov rbx, rdx
    lea r12, [rdx + rcx]
    mov [rsp + 8], r8           # version
    lea rdi, [rip + ln_new]
    call ln_vec_clear
    call present_num
    test edx, edx
    jz .Llr_drop
    cmp rax, LENS_MAX
    ja .Llr_drop
    mov r14, rax
.Llr_lens:
    test r14, r14
    jz .Llr_done
    dec r14
    call present_num            # LINE
    test edx, edx
    jz .Llr_drop
    test rax, rax
    jz .Llr_drop
    mov [rsp + 16], rax
    call present_num            # TITLE_LEN
    test edx, edx
    jz .Llr_drop
    cmp rax, LENS_TITLE_MAX
    ja .Llr_drop
    mov [rsp + 24], rax
    call present_num            # EXTRA_LEN
    test edx, edx
    jz .Llr_drop
    cmp rax, LENS_EXTRA_MAX
    ja .Llr_drop
    mov [rsp + 32], rax
    cmp byte ptr [rbx - 1], 10
    jne .Llr_drop
    add rax, [rsp + 24]
    mov rcx, r12
    sub rcx, rbx
    cmp rax, rcx
    ja .Llr_drop
    # a title is one line
    mov rcx, [rsp + 24]
    xor eax, eax
1:  cmp rax, rcx
    jae 2f
    cmp byte ptr [rbx + rax], 0x20
    jb .Llr_drop
    inc rax
    jmp 1b
2:  # its line's start in the text
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    dec rdx
    xor ecx, ecx
    mov r8d, GR_RIGHT
    call tape_map_lc
    test rax, rax
    js .Llr_drop
    mov [rsp + 40], rax
    mov rdi, r13
    mov rsi, rax
    call doc_line_of
    mov rdi, r13
    mov rsi, rax
    call doc_line_start
    mov [rsp + 40], rax
    mov rdi, [rsp + 24]
    add rdi, [rsp + 32]
    inc rdi
    call mem_alloc
    mov r15, rax
    mov rdi, r15
    mov rsi, rbx
    mov rdx, [rsp + 24]
    add rdx, [rsp + 32]
    call memcpy
    add rbx, [rsp + 24]
    add rbx, [rsp + 32]
    lea rdi, [rip + ln_new]
    mov esi, LNS_SIZE
    call vec_push
    mov rcx, [rsp + 40]
    mov [rax + LNS_pos], rcx
    mov rcx, [rsp]
    mov [rax + LNS_owner], rcx
    mov [rax + LNS_blob], r15
    mov rcx, [rsp + 24]
    mov [rax + LNS_tlen], ecx
    mov rcx, [rsp + 32]
    mov [rax + LNS_xlen], ecx
    jmp .Llr_lens
.Llr_done:
    cmp rbx, r12
    jne .Llr_drop
    mov rdi, r13
    mov rsi, [rsp]
    call lens_merge
    test eax, eax
    jz .Llr_drop
    mov eax, 1
    EPILOGUE
.Llr_drop:
    lea rdi, [rip + ln_new]
    call ln_vec_clear
    xor eax, eax
    EPILOGUE

# lens_merge(doc, ext) -> eax 1: the provider's lenses become ln_new's, sorted by position; the
# view's top line keeps its place
lens_merge:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    call pres_ensure
    mov r12, rax
    # the top line before: whether it had a lens row
    mov qword ptr [rsp + 8], 0
    cmp rbx, [rip + g_doc]
    jne 1f
    mov rdi, rbx
    call fold_view_sync
    call rows_mode
    test eax, eax
    jz 0f
    call top_row                # rax line, rdx rows into it (1/256)
    test rax, rax
    jnz 3f
    test rdx, rdx
    jz 4f
3:  mov rdi, rbx
    mov rsi, rax
    call lens_has
    mov [rsp + 8], rax
    jmp 1f
0:  cmp qword ptr [rbx + DOC_scrolly], 0
    jne 1f
4:  mov qword ptr [rsp + 8], -1 # the document's top stays the top: its lens row shows
1:  # the others' lenses, then the new ones
    mov qword ptr [rip + ln_tmp + VEC_len], 0
    xor r13d, r13d
2:  cmp r13, [r12 + PRS_lens + VEC_len]
    jae 4f
    imul r14, r13, LNS_SIZE
    add r14, [r12 + PRS_lens + VEC_ptr]
    inc r13
    mov rax, [rsp]
    cmp [r14 + LNS_owner], rax
    jne 3f
    mov rdi, [r14 + LNS_blob]
    call mem_free
    jmp 2b
3:  lea rdi, [rip + ln_tmp]
    mov esi, LNS_SIZE
    call vec_push
    mov rdi, rax
    mov rsi, r14
    mov edx, LNS_SIZE
    call memcpy
    jmp 2b
4:  xor r13d, r13d
5:  cmp r13, [rip + ln_new + VEC_len]
    jae 6f
    imul r14, r13, LNS_SIZE
    add r14, [rip + ln_new + VEC_ptr]
    inc r13
    lea rdi, [rip + ln_tmp]
    mov esi, LNS_SIZE
    call vec_push
    mov rdi, rax
    mov rsi, r14
    mov edx, LNS_SIZE
    call memcpy
    jmp 5b
6:  mov qword ptr [rip + ln_new + VEC_len], 0
    # sorted by position, stable (insertion: answers are near sorted)
    mov r13, [rip + ln_tmp + VEC_ptr]
    mov r14, [rip + ln_tmp + VEC_len]
    mov r15d, 1
7:  cmp r15, r14
    jae 9f
    mov rcx, r15
71: test rcx, rcx
    jz 8f
    imul rax, rcx, LNS_SIZE
    add rax, r13
    mov rdx, [rax - LNS_SIZE + LNS_pos]
    cmp rdx, [rax + LNS_pos]
    jbe 8f
    # swap rcx - 1 and rcx
    mov r8, [rax - LNS_SIZE]
    mov r9, [rax]
    mov [rax - LNS_SIZE], r9
    mov [rax], r8
    mov r8, [rax - LNS_SIZE + 8]
    mov r9, [rax + 8]
    mov [rax - LNS_SIZE + 8], r9
    mov [rax + 8], r8
    mov r8, [rax - LNS_SIZE + 16]
    mov r9, [rax + 16]
    mov [rax - LNS_SIZE + 16], r9
    mov [rax + 16], r8
    mov r8, [rax - LNS_SIZE + 24]
    mov r9, [rax + 24]
    mov [rax - LNS_SIZE + 24], r9
    mov [rax + 24], r8
    dec rcx
    jmp 71b
8:  inc r15
    jmp 7b
9:  # ln_tmp becomes the document's
    lea rdi, [r12 + PRS_lens]
    lea rsi, [rip + ln_tmp]
    call vec_swap
    mov rdi, rbx
    call pres_touch
    # the top line after: its text row stays where it was
    cmp rbx, [rip + g_doc]
    jne 10f
    mov rdi, rbx
    call fold_view_sync
    call rows_mode
    test eax, eax
    jz 10f
    cmp qword ptr [rsp + 8], -1
    je 10f
    call top_row
    mov r13, rax
    mov r14, rdx
    mov rdi, rbx
    mov rsi, r13
    call lens_has
    cmp rax, [rsp + 8]
    je 10f
    test rax, rax
    jz 91f
    add r14, 256
    jmp 92f
91: sub r14, 256
    jns 92f
    xor r14d, r14d
92: mov [rbx + DOC_wtop], r13
    mov [rbx + DOC_woff], r14
    shl r13, 8
    mov [rbx + DOC_scrolly], r13
10: mov eax, 1
    EPILOGUE

# top_row(rbx doc) -> rax the view's top line, rdx the 1/256 rows into it (rows mode)
top_row:
    mov rax, [rbx + DOC_scrolly]
    shr rax, 8
    xor edx, edx
    cmp rax, [rbx + DOC_wtop]
    jne 1f
    mov rdx, [rbx + DOC_woff]
1:  ret

# vec_swap(a, b): their contents change places
vec_swap:
    mov rax, [rdi]
    mov rcx, [rsi]
    mov [rdi], rcx
    mov [rsi], rax
    mov rax, [rdi + 8]
    mov rcx, [rsi + 8]
    mov [rdi + 8], rcx
    mov [rsi + 8], rax
    mov rax, [rdi + 16]
    mov rcx, [rsi + 16]
    mov [rdi + 16], rcx
    mov [rsi + 16], rax
    ret

# ln_vec_clear(vec): its lenses and their blobs go
ln_vec_clear:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    imul rax, r12, LNS_SIZE
    add rax, [rbx + VEC_ptr]
    mov rdi, [rax + LNS_blob]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
    EPILOGUE

# ---------------- rows ----------------

# lens_first(doc, line) -> rax the index of the line's first lens, rdx 1 when it has one (lenses on;
# PRS present)
lens_first:
    PROLOGUE
    xor edx, edx
    cmp dword ptr [rip + cfg_code_lens], 0
    je 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    cmp qword ptr [r13 + PRS_lens + VEC_len], 0
    je 9f
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r15, rax
    xor ecx, ecx
    mov rdx, [r13 + PRS_lens + VEC_len]
1:  cmp rcx, rdx
    jae 2f
    lea rsi, [rcx + rdx]
    shr rsi, 1
    imul rdi, rsi, LNS_SIZE
    add rdi, [r13 + PRS_lens + VEC_ptr]
    cmp [rdi + LNS_pos], r14
    jae 11f
    lea rcx, [rsi + 1]
    jmp 1b
11: mov rdx, rsi
    jmp 1b
2:  mov rax, rcx
    xor edx, edx
    cmp rcx, [r13 + PRS_lens + VEC_len]
    jae 9f
    imul rdi, rcx, LNS_SIZE
    add rdi, [r13 + PRS_lens + VEC_ptr]
    cmp [rdi + LNS_pos], r15
    ja 9f
    mov edx, 1
9:  EPILOGUE

# FN lens_has(doc, line) -> rax 1 when the line has a lens row
FN lens_has
    sub rsp, 8
    call lens_first
    add rsp, 8
    mov eax, edx
    ret

# FN lens_row_add(doc, line, rows) -> eax rows, with rows put first in wb_starts for the ghost text's
# lines below the line before (ghost.s) and the line's lenses (g_wb_lens: how many)
FN lens_row_add
    mov dword ptr [rip + g_wb_lens], 0
    mov eax, edx
    test eax, eax
    jz 9f
    push rbx
    push r12
    push r13
    mov ebx, edx                # rows
    mov r12, rdi
    mov r13, rsi
    call ghost_rows_before
    push rax
    mov rdi, r12
    mov rsi, r13
    call lens_has
    pop rcx
    add eax, ecx                # the rows put first
    mov r8d, eax
    mov eax, ebx
    pop r13
    pop r12
    pop rbx
    test r8d, r8d
    jz 9f
    cmp r8d, 64                 # (far fewer than MAXROWS)
    ja 9f
    lea rcx, [rip + wb_starts]
    mov r9d, eax                # entries rows + 1, moved up r8
1:  mov r10d, [rcx + r9*4]
    lea r11d, [r9 + r8]
    mov [rcx + r11*4], r10d
    test r9d, r9d
    jz 2f
    dec r9d
    jmp 1b
2:  xor r9d, r9d
3:  mov dword ptr [rcx + r9*4], 0
    inc r9d
    cmp r9d, r8d
    jb 3b
    add eax, r8d
    mov [rip + wb_rows], eax
    mov [rip + g_wb_lens], r8d
9:  ret

# FN lens_row_take(doc, line, y) -> eax the rows wb_starts had first (lens_row_add): the ghost
# text's rows (ghost.s) and the line's lens row are drawn from y and taken out of wb_starts
# (draw_wrapped then draws the text rows below them)
FN lens_row_take
    xor eax, eax
    cmp dword ptr [rip + g_wb_lens], 0
    je 9f
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov eax, [rip + g_wb_lens]
    mov [rsp + 8], eax
    # the rows that follow move down
    lea rcx, [rip + wb_starts]
    mov r8d, [rip + wb_rows]
    sub r8d, eax
    xor r9d, r9d
1:  cmp r9d, r8d
    ja 2f
    lea r10d, [r9 + rax]
    mov r10d, [rcx + r10*4]
    mov [rcx + r9*4], r10d
    inc r9d
    jmp 1b
2:  mov [rip + wb_rows], r8d
    mov dword ptr [rip + g_wb_lens], 0
    # the ghost text's rows
    mov rdi, rbx
    mov rsi, r12
    call ghost_rows_before
    mov r14d, eax
    xor r15d, r15d
3:  cmp r15d, r14d
    jae 4f
    mov edi, r15d
    mov esi, r13d
    call ghost_row_draw
    add r13d, [rip + g_lh]
    inc r15d
    jmp 3b
4:  cmp r14d, [rsp + 8]
    jae 8f                      # no lens row
    # visible?
    mov eax, r13d
    add eax, [rip + g_lh]
    cmp eax, [rip + g_ed_y]
    jle 8f
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r13d, eax
    jge 8f
    mov rdi, rbx
    mov rsi, r12
    call lens_items
    xor r14d, r14d
3:  cmp r14, [rip + li_n]
    jae 8f
    imul r15, r14, 24
    lea rax, [rip + li_buf]
    add r15, rax
    test r14, r14
    jz 4f
    # " | " before it
    mov edi, [r15 + 8]
    sub edi, [rip + sep_w]
    add rdi, [rip + li_x]
    mov esi, r13d
    lea rdx, [rip + .Lsep]
    mov ecx, .Lsep_end - .Lsep
    call lens_text
4:  mov rdi, rbx
    mov rsi, [r15]
    call lens_title
    mov edi, [r15 + 8]
    add rdi, [rip + li_x]
    mov esi, r13d
    mov rcx, rdx
    mov rdx, rax
    call lens_text
    inc r14
    jmp 3b
8:  mov eax, [rsp + 8]
    EPILOGUE
9:  ret

# lens_text(x, y, ptr, len): small text in the code lens color, centered in the row at y
lens_text:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    lea rbx, [rip + g_face_small]
    mov eax, [rip + g_lh]
    sub eax, [rbx + FACE_ascent]
    sub eax, [rbx + FACE_descent]
    sar eax, 1
    add eax, r13d
    add eax, [rbx + FACE_ascent]
    mov edx, eax
    mov rdi, rbx
    mov esi, r12d
    mov rcx, r14
    mov r8, r15
    COLOR r9d, T_CODELENS
    call text_draw
    EPILOGUE

# lens_title(doc, index) -> rax, rdx the lens's title, "…" when not resolved yet
lens_title:
    mov rax, [rdi + DOC_pres]
    imul rsi, rsi, LNS_SIZE
    add rsi, [rax + PRS_lens + VEC_ptr]
    mov edx, [rsi + LNS_tlen]
    mov rax, [rsi + LNS_blob]
    test edx, edx
    jnz 1f
    lea rax, [rip + .Lunresolved]
    mov edx, .Lunresolved_end - .Lunresolved
1:  ret

# lens_items(doc, line): li_buf, li_n: the line's lenses (eight at most) and their x ranges; li_x
# the first one's x on screen (the text's left edge, scrolled, plus the line's indentation)
lens_items:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [rip + li_n], 0
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Lsep]
    mov edx, .Lsep_end - .Lsep
    call text_width
    mov [rip + sep_w], eax
    mov rdi, rbx
    mov rsi, r12
    call line_indent            # -> edx its columns
    imul edx, [rip + g_cw]
    mov eax, [rip + g_ed_tx]
    sub eax, [rbx + DOC_scrollx]
    add eax, edx
    movsxd rax, eax
    mov [rip + li_x], rax
    mov rdi, rbx
    mov rsi, r12
    call lens_first
    test edx, edx
    jz 9f
    mov r13, rax                # the lens index
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r14, rax
    xor r15d, r15d              # x
1:  mov rax, [rbx + DOC_pres]
    cmp r13, [rax + PRS_lens + VEC_len]
    jae 9f
    imul rcx, r13, LNS_SIZE
    add rcx, [rax + PRS_lens + VEC_ptr]
    cmp [rcx + LNS_pos], r14
    ja 9f
    cmp qword ptr [rip + li_n], LENS_SHOWN
    jae 9f
    mov rax, [rip + li_n]
    test rax, rax
    jz 2f
    add r15d, [rip + sep_w]
2:  imul rcx, rax, 24
    lea rdx, [rip + li_buf]
    add rcx, rdx
    mov [rcx], r13
    mov [rcx + 8], r15
    mov [rsp], rcx
    mov rdi, rbx
    mov rsi, r13
    call lens_title
    lea rdi, [rip + g_face_small]
    mov rsi, rax
    call text_width
    add r15d, eax
    mov rcx, [rsp]
    mov [rcx + 16], r15
    inc qword ptr [rip + li_n]
    inc r13
    jmp 1b
9:  EPILOGUE

# ---------------- pointer ----------------

# FN lens_hit(doc, line, x): the pointer at x on the line's lens row: the item under it becomes the
# inlay hit (vt_hit_set, VK_LENS: ref the line, off the item), or nothing when between items
FN lens_hit
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    movsxd r13, edx
    call lens_items
    sub r13, [rip + li_x]
    xor ecx, ecx
1:  cmp rcx, [rip + li_n]
    jae 9f
    imul rax, rcx, 24
    lea rdx, [rip + li_buf]
    add rax, rdx
    inc rcx
    cmp r13, [rax + 8]
    jl 1b
    cmp r13, [rax + 16]
    jge 1b
    dec rcx
    mov edi, VK_LENS
    mov rsi, r12
    mov rdx, rcx
    call vt_hit_set
9:  EPILOGUE

# lens_at(doc, line, item) -> rax LNS* of that item of the line's lens row, or 0
lens_at:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call lens_first
    test edx, edx
    jz 8f
    add rax, r13
    mov rcx, [rbx + DOC_pres]
    cmp rax, [rcx + PRS_lens + VEC_len]
    jae 8f
    imul rax, rax, LNS_SIZE
    add rax, [rcx + PRS_lens + VEC_ptr]
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    cmp [r14 + LNS_pos], rax
    ja 8f
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN lens_tip(doc, line, item) -> rax the lens's tip (a cstr in tipbuf), or 0: its "tip LEN" record
FN lens_tip
    PROLOGUE
    call lens_at
    test rax, rax
    jz 8f
    mov rbx, rax
    mov edi, [rbx + LNS_tlen]
    add rdi, [rbx + LNS_blob]
    mov esi, [rbx + LNS_xlen]
    lea rdx, [rip + .Ls_tip]
    call extra_find
    test rax, rax
    jz 8f
    # "tip LEN" LF TEXT
    push rbx
    push r12
    mov rbx, rax
    lea r12, [rax + rdx]
    call present_word
    call present_num
    mov rcx, rbx
    mov r8, r12
    sub r8, rbx                 # the bytes left
    pop r12
    pop rbx
    test edx, edx
    jz 8f
    cmp byte ptr [rcx - 1], 10
    jne 8f
    cmp rax, r8
    ja 8f
    cmp rax, 1024
    jbe 1f
    mov eax, 1024
1:  lea rdi, [rip + tipbuf]
    mov byte ptr [rdi + rax], 0
    mov rsi, rcx
    mov rdx, rax
    call memcpy
    lea rax, [rip + tipbuf]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN lens_click(doc, line, item) -> eax 1 when the lens had a command and it ran
FN lens_click
    PROLOGUE 16
    mov r15, rdi
    call lens_at
    test rax, rax
    jz 8f
    mov rbx, rax
    mov edi, [rbx + LNS_tlen]
    add rdi, [rbx + LNS_blob]
    mov esi, [rbx + LNS_xlen]
    lea rdx, [rip + .Ls_command]
    call extra_find
    test rax, rax
    jz 8f
    mov rdi, [rbx + LNS_owner]
    mov rsi, rax
    call cmdref_parse
    test rax, rax
    jz 8f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, [r15 + DOC_id]
    call cmdref_invoke
    mov rdi, [rsp]
    call cmdref_free
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- edits ----------------

# FN lens_shift(doc, entry): lenses move with the text (a line typed at a lens's line start pushes
# the lens down with it)
FN lens_shift
    PROLOGUE
    mov rax, [rdi + DOC_pres]
    mov r14, [rax + PRS_lens + VEC_len]
    test r14, r14
    jz 9f
    mov r15, [rax + PRS_lens + VEC_ptr]
    mov r12, rsi
    mov rsi, [r12 + TE_pos]
    mov rdx, [r12 + TE_del]
    mov rcx, [r12 + TE_ins]
    mov r8d, GR_RIGHT
1:  mov rdi, [r15 + LNS_pos]
    call tape_shift
    mov [r15 + LNS_pos], rax
    add r15, LNS_SIZE
    dec r14
    jnz 1b
9:  EPILOGUE

# ---------------- lifetime ----------------

# FN lens_free(PRS): its lenses go
FN lens_free
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rbx + PRS_lens]
    call ln_vec_clear
    lea rdi, [rbx + PRS_lens]
    call vec_free
    EPILOGUE

# FN lens_ext_gone(ext): the lenses it provided go
FN lens_ext_gone
    PROLOGUE 16
    mov r12, rdi
    xor r13d, r13d
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
    xor r15d, r15d
    mov qword ptr [rsp], 0
2:  cmp r15, [r14 + PRS_lens + VEC_len]
    jae 4f
    imul rsi, r15, LNS_SIZE
    add rsi, [r14 + PRS_lens + VEC_ptr]
    inc r15
    cmp [rsi + LNS_owner], r12
    jne 3f
    mov rdi, [rsi + LNS_blob]
    call mem_free
    jmp 2b
3:  mov rdi, [rsp]
    inc qword ptr [rsp]
    imul rdi, rdi, LNS_SIZE
    add rdi, [r14 + PRS_lens + VEC_ptr]
    cmp rdi, rsi
    je 2b
    mov edx, LNS_SIZE
    call memcpy
    jmp 2b
4:  mov rax, [rsp]
    cmp rax, [r14 + PRS_lens + VEC_len]
    je 1b
    mov [r14 + PRS_lens + VEC_len], rax
    mov rdi, rbx
    call pres_touch
    jmp 1b
9:  EPILOGUE

# ---------------- headless ----------------

# FN lens_dump(doc, sb): "lens L TITLE" per lens ("…" unresolved), " +command" with a command
FN lens_dump
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    xor r14d, r14d
1:  cmp r14, [r13 + PRS_lens + VEC_len]
    jae 9f
    imul r15, r14, LNS_SIZE
    add r15, [r13 + PRS_lens + VEC_ptr]
    mov rdi, r12
    lea rsi, [rip + .Ls_lens]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r15 + LNS_pos]
    call doc_line_of
    lea rsi, [rax + 1]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    call lens_title
    mov rdi, r12
    mov rsi, rax
    call sb_push
    mov edi, [r15 + LNS_tlen]
    add rdi, [r15 + LNS_blob]
    mov esi, [r15 + LNS_xlen]
    lea rdx, [rip + .Ls_command]
    call extra_find
    test rax, rax
    jz 2f
    mov rdi, r12
    lea rsi, [rip + .Ls_pcommand]
    call sb_push_cstr
2:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r14
    jmp 1b
9:  EPILOGUE

.data
.p2align 2
sep_w: .long 0                  # " | " in the small face

.section .rodata
.Lsep: .ascii " | "
.Lsep_end:
.Lunresolved: .ascii "\342\200\246"
.Lunresolved_end:
.Ls_tip: .asciz "tip"
.Ls_command: .asciz "command"
.Ls_lens: .asciz "lens "
.Ls_pcommand: .asciz " +command"
