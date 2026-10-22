# The peek view (language-features.md 1.5): the locations of Peek Definition and its siblings in a
# read-only box under the cursor's line, over the editor's text: a header ("name - folder   2 of 5
# x"), the target file with syntax colors, line numbers and the location's range highlighted, and
# with several locations a list on the right grouped by file. Up/Down move in the list (scroll the
# code with one location), PageUp/PageDown scroll the code, Enter opens the location, F4/shift+F4
# cycle, Escape or x closes, any other key closes it and goes on to the editor; a double click in
# the code opens there. A file that is not open is loaded without a tab (at most 8 MB; the last 4
# are kept); an open one is shown live.
#
# It paints its lines itself (syntax colors, tabs, wide characters) instead of sharing editor.s's
# row painter, which carries the editor's own per-frame state (selections, brackets, the caret).
#
#   peek_begin(title cstr, serial), peek_loc(path cstr, range ptr, preview ptr, len), peek_end():
#   the locations of a query (the same serial refills an open peek and keeps its choice)
#   peek_draw(), peek_key(keysym, cp, mods) -> eax taken, peek_blocks_editor() -> eax 1 while the
#   pointer is over it, peek_close(), peek_dump(sb)
.include "rhun.inc"

.equ PV_ROWS, 18                # code rows at most
.equ PV_CACHE, 4                # files kept loaded without a tab
.equ PV_FILE_MAX, 8388608
.equ ID_PV, 0x6c2000            # + n: its buttons; ID_PV + 16 + i: list row i

# a location
STRUCT
F PVL_path, 8                   # offsets in pv_bytes, cstrs
F PVL_prev, 8
F PVL_l1, 4
F PVL_c1, 4
F PVL_l2, 4
F PVL_c2, 4
ENDSTRUCT PVL_SIZE

.bss
.p2align 3
pv_open: .long 0
pv_sel: .long 0                 # the chosen location
pv_serial: .quad 0              # the query that filled it
pv_origin: .quad 0              # the editor's DOC under it, and its cursor then
pv_origin_cur: .quad 0
pv_title: .quad 0               # cstr: what it shows ("definition", ...)
pv_scroll: .quad 0              # the code's first line (0-based)
pv_target: .quad 0              # DOC* of the chosen location, 0 when it could not be loaded
pv_tpath: .quad 0               # the path offset it was loaded for, plus 1 (0: none)
pv_locs: .zero VEC_SIZE         # PVL records
pv_bytes: .zero SB_SIZE
pv_cache: .zero 8 * PV_CACHE    # DOC*s loaded without a tab
pv_cseq: .zero 8 * PV_CACHE     # when each was last used
pv_seq: .quad 0
pv_rect: .zero 16               # the box last drawn: x, y, w, h
pv_code: .zero 16               # its code area: x, y, w, h
pv_rows: .long 0                # code rows shown
pv_listtop: .long 0             # the list's first row shown
pv_cls: .zero SB_SIZE           # a line's syntax classes
pv_buf: .zero SB_SIZE           # header text, numbers
pv_num: .zero 32

.text

# ---------------- the locations ----------------

# FN peek_begin(title cstr, serial): locations come next; an open peek of the same query keeps its
# choice
FN peek_begin
    mov [rip + pv_title], rdi
    cmp dword ptr [rip + pv_open], 0
    je 1f
    cmp [rip + pv_serial], rsi
    je 2f
1:  mov dword ptr [rip + pv_sel], 0
    mov dword ptr [rip + pv_listtop], 0
2:  mov [rip + pv_serial], rsi
    mov qword ptr [rip + pv_locs + VEC_len], 0
    mov qword ptr [rip + pv_tpath], 0
    lea rdi, [rip + pv_bytes]
    jmp sb_clear

# pv_str(ptr, len) -> rax the offset of a copy in pv_bytes, as a cstr
pv_str:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + pv_bytes + SB_len]
    lea rdi, [rip + pv_bytes]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + pv_bytes]
    xor esi, esi
    call sb_push_byte
    mov rax, rbx
    EPILOGUE

# FN peek_loc(path cstr, range ptr (4 dwords), preview ptr, len): the same path as the location
# before shares its copy (the list groups by it)
FN peek_loc
    PROLOGUE 16
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rbx, rdi
    mov rax, [rip + pv_locs + VEC_len]
    test rax, rax
    jz 1f
    dec rax
    imul rax, rax, PVL_SIZE
    add rax, [rip + pv_locs + VEC_ptr]
    mov rsi, [rax + PVL_path]
    mov [rsp], rsi
    add rsi, [rip + pv_bytes + SB_ptr]
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jnz 2f
1:  mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call pv_str
    mov [rsp], rax
2:  mov rdi, r13
    mov rsi, r14
    call pv_str
    mov [rsp + 8], rax
    lea rdi, [rip + pv_locs]
    mov esi, PVL_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + PVL_path], rcx
    mov rcx, [rsp + 8]
    mov [rax + PVL_prev], rcx
    mov ecx, [r12]
    mov [rax + PVL_l1], ecx
    mov ecx, [r12 + 4]
    mov [rax + PVL_c1], ecx
    mov ecx, [r12 + 8]
    mov [rax + PVL_l2], ecx
    mov ecx, [r12 + 12]
    mov [rax + PVL_c2], ecx
    EPILOGUE

# FN peek_end(): the box opens on the editor's document (or shows what came since)
FN peek_end
    PROLOGUE
    mov rax, [rip + pv_locs + VEC_len]
    test rax, rax
    jz 9f
    mov ecx, [rip + pv_sel]
    cmp rcx, rax
    jb 1f
    mov dword ptr [rip + pv_sel], 0
1:  cmp dword ptr [rip + pv_open], 0
    jne 2f
    mov rax, [rip + g_doc]
    test rax, rax
    jz 9f
    mov [rip + pv_origin], rax
    mov rcx, [rax + DOC_cur]
    mov [rip + pv_origin_cur], rcx
    mov dword ptr [rip + pv_open], 1
2:  call choose
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN peek_close()
FN peek_close
    mov dword ptr [rip + pv_open], 0
    mov qword ptr [rip + pv_target], 0
    mov dword ptr [rip + g_dirty], 1
    ret

# loc(i) -> rax PVL*
loc:
    imul rax, rdi, PVL_SIZE
    add rax, [rip + pv_locs + VEC_ptr]
    ret

# choose(): the chosen location's file loaded, the code scrolled to it
choose:
    PROLOGUE
    mov edi, [rip + pv_sel]
    call loc
    mov rbx, rax
    mov rdi, [rbx + PVL_path]
    add rdi, [rip + pv_bytes + SB_ptr]
    call load
    mov [rip + pv_target], rax
    mov rax, [rbx + PVL_path]
    inc rax
    mov [rip + pv_tpath], rax
    mov eax, [rbx + PVL_l1]     # a third of the way down
    dec eax
    mov ecx, [rip + pv_rows]
    test ecx, ecx
    jnz 1f
    mov ecx, PV_ROWS
1:  push rax
    mov eax, ecx
    xor edx, edx
    mov ecx, 3
    div ecx
    mov ecx, eax
    pop rax
    sub eax, ecx
    jns 2f
    xor eax, eax
2:  mov [rip + pv_scroll], rax
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# load(path cstr) -> rax the DOC to show: an open document ("#ID", or the file's tab), else a copy
# loaded without a tab (kept among the last 4), or 0
load:
    PROLOGUE
    mov rbx, rdi
    cmp byte ptr [rbx], '#'
    jne 1f
    mov rdi, rbx
    call lf_doc_ref
    test rax, rax
    js 8f
    mov rdi, rax
    call extproto_doc
    EPILOGUE
1:  mov rdi, rbx
    call app_find_tab
    test rax, rax
    js 2f
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 2f
    mov rax, [rax + TAB_doc]
    EPILOGUE
2:  # loaded before?
    xor r12d, r12d
3:  cmp r12, PV_CACHE
    jae 4f
    lea rax, [rip + pv_cache]
    mov r13, [rax + r12*8]
    test r13, r13
    jz 31f
    mov rsi, [r13 + DOC_path]
    test rsi, rsi
    jz 31f
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jz 31f
    inc qword ptr [rip + pv_seq]
    mov rax, [rip + pv_seq]
    lea rcx, [rip + pv_cseq]
    mov [rcx + r12*8], rax
    mov rax, r13
    EPILOGUE
31: inc r12
    jmp 3b
4:  call doc_new
    mov r13, rax
    mov rdi, r13
    mov rsi, rbx
    call doc_load
    test rax, rax
    jnz 7f
    mov rdi, r13
    call doc_len
    cmp rax, PV_FILE_MAX
    ja 7f
    or dword ptr [r13 + DOC_flags], DF_READONLY
    mov rdi, r13
    call doc_sync_grammar
    # its slot: an empty one, else the least recently used that is not shown
    xor r12d, r12d
    mov r14, -1
    mov r15, -1
5:  cmp r12, PV_CACHE
    jae 6f
    lea rax, [rip + pv_cache]
    mov rcx, [rax + r12*8]
    test rcx, rcx
    jz 62f
    cmp rcx, [rip + pv_target]
    je 51f
    lea rax, [rip + pv_cseq]
    mov rax, [rax + r12*8]
    cmp rax, r15
    jae 51f
    mov r15, rax
    mov r14, r12
51: inc r12
    jmp 5b
6:  test r14, r14
    js 7f                       # every slot shows something (cannot happen with 4)
    mov r12, r14
    lea rax, [rip + pv_cache]
    mov rdi, [rax + r12*8]
    call doc_free
62: lea rax, [rip + pv_cache]
    mov [rax + r12*8], r13
    inc qword ptr [rip + pv_seq]
    mov rax, [rip + pv_seq]
    lea rcx, [rip + pv_cseq]
    mov [rcx + r12*8], rax
    mov rax, r13
    EPILOGUE
7:  mov rdi, r13
    call doc_free
8:  xor eax, eax
    EPILOGUE

# ---------------- keys ----------------

# FN peek_key(keysym, cp, mods) -> eax 1 when the peek took the key (the editor has the keyboard)
FN peek_key
    cmp dword ptr [rip + pv_open], 0
    jne 1f
    xor eax, eax
    ret
1:  PROLOGUE
    mov r12d, edi
    mov r13d, edx
    # modifier keys alone do nothing
    cmp r12d, 0xffe1
    jb 2f
    cmp r12d, 0xffee
    jbe 8f
2:  mov rax, [rip + pv_locs + VEC_len]
    mov r14, rax
    cmp r12d, KEY_ESCAPE
    jne 3f
    call peek_close
    jmp 7f
3:  cmp r12d, KEY_RETURN
    je 31f
    cmp r12d, KEY_KP_ENTER
    jne 4f
31: mov edi, [rip + pv_sel]
    call open_loc
    jmp 7f
4:  cmp r12d, KEY_F1 + 3        # F4, shift+F4
    jne 5f
    mov eax, [rip + pv_sel]
    test r13d, MOD_SHIFT
    jnz 41f
    inc eax
    cmp rax, r14
    jb 42f
    xor eax, eax
    jmp 42f
41: dec eax
    jns 42f
    lea eax, [r14 - 1]
42: mov [rip + pv_sel], eax
    call choose
    jmp 7f
5:  cmp r12d, KEY_DOWN
    je 51f
    cmp r12d, KEY_UP
    jne 6f
51: cmp r14, 1
    ja 52f
    mov eax, 1                  # one location: the code scrolls
    cmp r12d, KEY_DOWN
    je 53f
    mov eax, -1
53: mov edi, eax
    call scroll_code
    jmp 7f
52: mov eax, [rip + pv_sel]
    cmp r12d, KEY_DOWN
    jne 54f
    inc eax
    cmp rax, r14
    jb 55f
    jmp 7f
54: test eax, eax
    jz 7f
    dec eax
55: mov [rip + pv_sel], eax
    call choose
    jmp 7f
6:  cmp r12d, KEY_PAGEDOWN
    je 61f
    cmp r12d, KEY_PAGEUP
    jne 69f
61: mov eax, [rip + pv_rows]
    dec eax
    jg 62f
    mov eax, 1
62: cmp r12d, KEY_PAGEDOWN
    je 63f
    neg eax
63: mov edi, eax
    call scroll_code
    jmp 7f
69: call peek_close              # any other key: the editor's
8:  xor eax, eax
    EPILOGUE
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE

# scroll_code(lines): the code moves, within the target's lines
scroll_code:
    movsxd rax, edi
    add rax, [rip + pv_scroll]
    jns 1f
    xor eax, eax
1:  mov rcx, [rip + pv_target]
    test rcx, rcx
    jz 2f
    mov rcx, [rcx + DOC_nlines]
    dec rcx
    cmp rax, rcx
    jbe 2f
    mov rax, rcx
2:  mov [rip + pv_scroll], rax
    mov dword ptr [rip + g_dirty], 1
    ret

# open_loc(i): location i opens in its tab with its range selected; the peek closes
open_loc:
    PROLOGUE
    call loc
    mov rbx, rax
    call peek_close
    mov rdi, [rbx + PVL_path]
    add rdi, [rip + pv_bytes + SB_ptr]
    call lf_open_path
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, r12
    mov esi, [rbx + PVL_l1]
    mov edx, [rbx + PVL_c1]
    call lf_pos_near
    mov r13, rax
    mov rdi, r12
    mov esi, [rbx + PVL_l2]
    mov edx, [rbx + PVL_c2]
    call lf_pos_near
    cmp rax, r13
    jae 1f
    mov rax, r13
1:  mov [r12 + DOC_anchor], r13
    mov [r12 + DOC_cur], rax
    call ed_touch
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- drawing ----------------

# FN peek_blocks_editor() -> eax 1 while the pointer is over the open peek (the editor leaves its
# input alone)
FN peek_blocks_editor
    xor eax, eax
    cmp dword ptr [rip + pv_open], 0
    je 1f
    mov rax, [rip + g_doc]
    cmp rax, [rip + pv_origin]
    mov eax, 0
    jne 1f
    mov edi, [rip + pv_rect]
    mov esi, [rip + pv_rect + 4]
    mov edx, [rip + pv_rect + 8]
    mov ecx, [rip + pv_rect + 12]
    jmp ui_in
1:  ret

# FN peek_draw(): the box under the cursor's line (after the editor, before its overlays)
FN peek_draw
    PROLOGUE 64
    cmp dword ptr [rip + pv_open], 0
    je .Lpd_ret
    # it belongs to the editor's document as it was: another tab or a moved cursor closes it
    mov rbx, [rip + g_doc]
    cmp rbx, [rip + pv_origin]
    jne .Lpd_close
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + pv_origin_cur]
    jne .Lpd_close
    cmp qword ptr [rip + pv_locs + VEC_len], 0
    je .Lpd_close
    # the geometry: rows, then the box under the caret's row
    mov eax, [rip + g_ed_h]
    imul eax, eax, 45
    xor edx, edx
    mov ecx, 100
    div ecx
    xor edx, edx
    div dword ptr [rip + g_lh]
    cmp eax, PV_ROWS
    jbe 1f
    mov eax, PV_ROWS
1:  cmp eax, 3
    jge 2f
    mov eax, 3
2:  mov [rip + pv_rows], eax
    imul eax, [rip + g_lh]
    M ecx, MI_ROW
    add eax, ecx
    M ecx, MI_4
    lea eax, [rax + rcx*2]
    mov [rsp + 12], eax         # h
    mov eax, [rip + g_ed_y]
    cmp dword ptr [rip + g_caret_ok], 0
    je 3f
    mov eax, [rip + g_caret_y]
    add eax, [rip + g_lh]
3:  mov [rsp + 4], eax          # y
    # room below: the editor scrolls so the cursor's line stays above the box
    mov ecx, [rip + g_ed_y]
    add ecx, [rip + g_ed_h]
    add eax, [rsp + 12]
    sub eax, ecx
    jle 4f
    xor edx, edx                # the lines it lacks
    add eax, [rip + g_lh]
    dec eax
    div dword ptr [rip + g_lh]
    mov r12d, eax
    imul eax, [rip + g_lh]
    sub [rsp + 4], eax
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne 31f
    movsxd rax, r12d
    shl rax, 8
    add [rbx + DOC_scrolly], rax
    jmp 32f
31: mov rdi, rbx
    mov esi, eax
    call scroll_by_px
32: mov dword ptr [rip + g_dirty], 1
4:  mov eax, [rip + g_ed_x]
    mov [rsp], eax              # x
    mov eax, [rip + g_ed_w]
    sub eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 8], eax          # w
    lea rax, [rip + pv_rect]
    mov ecx, [rsp]
    mov [rax], ecx
    mov ecx, [rsp + 4]
    mov [rax + 4], ecx
    mov ecx, [rsp + 8]
    mov [rax + 8], ecx
    mov ecx, [rsp + 12]
    mov [rax + 12], ecx
    # the frame
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    xor r8d, r8d
    COLOR r9d, T_ACCENT
    COLOR eax, T_PANEL
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    call draw_header
    # the code, and the list beside it with several locations
    mov eax, [rsp + 8]
    cmp qword ptr [rip + pv_locs + VEC_len], 1
    je 5f
    imul eax, eax, 2
    xor edx, edx
    mov ecx, 3
    div ecx
5:  mov [rsp + 16], eax         # the code's width
    M ecx, MI_ROW
    mov edx, [rsp + 4]
    add edx, ecx
    lea rax, [rip + pv_code]
    mov ecx, [rsp]
    add ecx, [rip + g_mt + 4*MI_4]
    mov [rax], ecx
    mov [rax + 4], edx
    mov ecx, [rsp + 16]
    sub ecx, [rip + g_mt + 4*MI_8]
    mov [rax + 8], ecx
    mov ecx, [rip + pv_rows]
    imul ecx, [rip + g_lh]
    mov [rax + 12], ecx
    call draw_code
    cmp qword ptr [rip + pv_locs + VEC_len], 1
    je 6f
    mov edi, [rsp]
    add edi, [rsp + 16]
    mov esi, [rip + pv_code + 4]
    mov edx, [rsp + 8]
    sub edx, [rsp + 16]
    mov ecx, [rip + pv_code + 12]
    call draw_list
6:  # the wheel over it scrolls the code
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz .Lpd_ret
    call wheel_xy
    test edx, edx
    jz 7f
    mov eax, edx
    cdq
    idiv dword ptr [rip + g_lh]
    test eax, eax
    jnz 61f
    mov eax, 1
    test edx, edx
    jns 61f
    mov eax, -1
61: mov edi, eax
    call scroll_code
7:  # a double click in the code opens its line
    mov edi, ID_PV + 1
    mov esi, [rip + pv_code]
    mov edx, [rip + pv_code + 4]
    mov ecx, [rip + pv_code + 8]
    mov r8d, [rip + pv_code + 12]
    call ui_btn
    test eax, UB_DOUBLE
    jz .Lpd_ret
    call open_clicked
    jmp .Lpd_ret
.Lpd_close:
    call peek_close
.Lpd_ret:
    EPILOGUE

# open_clicked(): the line under the pointer in the code opens in its tab
open_clicked:
    PROLOGUE
    mov eax, [rip + g_my]
    sub eax, [rip + pv_code + 4]
    js 9f
    xor edx, edx
    div dword ptr [rip + g_lh]
    add rax, [rip + pv_scroll]
    mov r12, rax
    mov edi, [rip + pv_sel]
    call loc
    mov rbx, rax
    call peek_close
    mov rdi, [rbx + PVL_path]
    add rdi, [rip + pv_bytes + SB_ptr]
    call lf_open_path
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r13
    lea rsi, [r12 + 1]
    mov edx, 1
    call lf_pos_near
    mov [r13 + DOC_cur], rax
    mov [r13 + DOC_anchor], rax
    call ed_touch
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# draw_header(): "name - folder" at the left, "2 of 5" and x at the right (pv_rect)
draw_header:
    PROLOGUE 16
    mov edi, [rip + pv_sel]
    call loc
    mov rbx, rax
    mov r12, [rbx + PVL_path]
    add r12, [rip + pv_bytes + SB_ptr]
    mov rdi, r12
    call name_of
    mov r13, rax
    lea rdi, [rip + pv_buf]
    call sb_clear
    lea rdi, [rip + pv_buf]
    mov rsi, r13
    call sb_push_cstr
    # the folder, relative to the project
    mov r14, r13
    sub r14, r12
    jz 2f
    dec r14                     # without the separator
    mov r15, r12
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 1f
    call strlen
    cmp rax, r14
    ja 1f
    mov [rsp], rax
    mov rdi, r12
    mov rsi, r14
    mov rdx, [rip + g_project]
    mov rcx, rax
    call str_starts
    test eax, eax
    jz 1f
    mov rax, [rsp]
    cmp rax, r14
    je 2f
    lea r15, [r12 + rax + 1]
    mov r14, r13
    sub r14, r15
    dec r14
1:  lea rdi, [rip + pv_buf]
    lea rsi, [rip + .Ldash]
    call sb_push_cstr
    lea rdi, [rip + pv_buf]
    mov rsi, r15
    mov rdx, r14
    call sb_push
2:  lea rdi, [rip + pv_buf]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + g_face_small]
    mov esi, [rip + pv_rect]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rip + pv_rect + 4]
    M ecx, MI_ROW
    mov r8, [rip + pv_buf + SB_ptr]
    COLOR r9d, T_FG
    call ui_text_c
    # x
    M eax, MI_24
    mov esi, [rip + pv_rect]
    add esi, [rip + pv_rect + 8]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_4]
    mov [rsp], esi
    mov edi, ID_PV
    mov edx, [rip + pv_rect + 4]
    M ecx, MI_24
    M r8d, MI_ROW
    mov r9d, IC_CLOSE
    call ui_icon_btn
    test eax, UB_CLICK
    jz 3f
    call peek_close
3:  # "2 of 5" (and the kind)
    lea rdi, [rip + pv_buf]
    call sb_clear
    mov rsi, [rip + pv_title]
    test rsi, rsi
    jz 31f
    lea rdi, [rip + pv_buf]
    call sb_push_cstr
    lea rdi, [rip + pv_buf]
    lea rsi, [rip + .Lgap]
    call sb_push_cstr
31: lea rdi, [rip + pv_buf]
    mov esi, [rip + pv_sel]
    inc esi
    call sb_push_u64
    lea rdi, [rip + pv_buf]
    lea rsi, [rip + .Lof]
    call sb_push_cstr
    lea rdi, [rip + pv_buf]
    mov rsi, [rip + pv_locs + VEC_len]
    call sb_push_u64
    lea rdi, [rip + g_face_small]
    mov rsi, [rip + pv_buf + SB_ptr]
    mov rdx, [rip + pv_buf + SB_len]
    call text_width
    mov esi, [rsp]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_8]
    lea rdi, [rip + pv_buf]
    xor eax, eax
    push rsi
    push rsi
    xor esi, esi
    call sb_push_byte
    pop rsi
    pop rsi
    lea rdi, [rip + g_face_small]
    mov edx, [rip + pv_rect + 4]
    M ecx, MI_ROW
    mov r8, [rip + pv_buf + SB_ptr]
    COLOR r9d, T_MUTED
    call ui_text_c
    EPILOGUE

# name_of(path cstr) -> rax its last part
name_of:
    mov rax, rdi
    mov rcx, rdi
1:  movzx edx, byte ptr [rcx]
    test edx, edx
    jz 9f
    inc rcx
    cmp edx, '/'
    je 2f
    cmp edx, '\\'
    jne 1b
2:  mov rax, rcx
    jmp 1b
9:  ret

# draw_code(): the target's lines from pv_scroll in pv_code: numbers, then the text with its syntax
# colors, the chosen location's range behind it
draw_code:
    PROLOGUE 64
    mov rbx, [rip + pv_target]
    test rbx, rbx
    jnz 1f
    lea rdi, [rip + g_face_small]
    mov esi, [rip + pv_code]
    mov edx, [rip + pv_code + 4]
    M ecx, MI_ROW
    lea r8, [rip + .Lunreadable]
    COLOR r9d, T_MUTED
    call ui_text_c
    EPILOGUE
1:  mov edi, [rip + pv_code]
    mov esi, [rip + pv_code + 4]
    mov edx, [rip + pv_code + 8]
    mov ecx, [rip + pv_code + 12]
    call gfx_clip_push
    mov rax, [rbx + DOC_nlines]
    mov rcx, [rip + pv_scroll]
    cmp rcx, rax
    jb 11f
    lea rcx, [rax - 1]
    mov [rip + pv_scroll], rcx
11: mov rsi, rcx
    add esi, [rip + pv_rows]
    mov rdi, rbx
    call syntax_prepare
    # the numbers' width: the digits of the last line shown, and a space
    mov rax, [rip + pv_scroll]
    add eax, [rip + pv_rows]
    lea rdi, [rip + pv_num]
    mov rsi, rax
    call fmt_u64
    inc eax
    imul eax, [rip + g_cw]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp], eax              # the numbers' width, with room before them
    mov eax, [rip + pv_code]
    add eax, [rsp]
    add eax, [rip + g_cw]
    mov [rsp + 4], eax          # the text's x
    mov edi, [rip + pv_sel]
    call loc
    mov r15, rax                # the chosen location
    xor r12d, r12d              # the row
2:  cmp r12d, [rip + pv_rows]
    jae 8f
    mov r13, [rip + pv_scroll]
    add r13, r12
    cmp r13, [rbx + DOC_nlines]
    jae 8f
    mov eax, r12d
    imul eax, [rip + g_lh]
    add eax, [rip + pv_code + 4]
    mov [rsp + 8], eax          # y
    # inside the location (when it is this file): the range's background
    mov rax, [r15 + PVL_path]
    inc rax
    cmp rax, [rip + pv_tpath]
    jne 4f
    lea rax, [r13 + 1]
    cmp eax, [r15 + PVL_l1]
    jb 4f
    cmp eax, [r15 + PVL_l2]
    ja 4f
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    xor ecx, ecx                # from: the range's start on its first line, else the line's start
    lea rax, [r13 + 1]
    cmp eax, [r15 + PVL_l1]
    jne 31f
    mov ecx, [r15 + PVL_c1]
    dec ecx
31: mov rdx, [rsp + 24]         # to: its end on its last line, else the line's end
    cmp eax, [r15 + PVL_l2]
    jne 32f
    mov edx, [r15 + PVL_c2]
    dec edx
    cmp rdx, [rsp + 24]
    jbe 32f
    mov rdx, [rsp + 24]
32: cmp rcx, rdx
    jb 33f
    lea rdx, [rcx + 1]          # an empty range: one cell
33: mov [rsp + 32], rdx
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, rcx
    call cols_to
    mov [rsp + 40], eax
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call cols_to
    sub eax, [rsp + 40]
    jg 34f
    mov eax, 1
34: imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, [rsp + 40]
    imul edi, [rip + g_cw]
    add edi, [rsp + 4]
    mov esi, [rsp + 8]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_MATCH
    call gfx_fill
4:  # the number
    lea rdi, [rip + pv_num]
    lea rsi, [r13 + 1]
    call fmt_u64
    mov r14, rax
    lea rdi, [rip + g_face_code]
    lea rsi, [rip + pv_num]
    mov rdx, rax
    call text_width
    mov esi, [rip + pv_code]
    add esi, [rsp]
    sub esi, eax
    COLOR r9d, T_LINENO
    lea rax, [r13 + 1]
    cmp eax, [r15 + PVL_l1]
    jne 41f
    COLOR r9d, T_LINENO_ACTIVE
41: lea rdi, [rip + g_face_code]
    mov edx, [rsp + 8]
    add edx, [rip + g_base]
    lea rcx, [rip + pv_num]
    mov r8, r14
    call text_draw
    # the text
    mov rdi, rbx
    mov rsi, r13
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    call paint_line
    inc r12d
    jmp 2b
8:  call gfx_clip_pop
    EPILOGUE

# cols_to(text, len, to) -> eax the columns of text's first `to` bytes (tabs to the tab width, wide
# characters two)
cols_to:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, r12
    jbe 1f
    mov r13, r12
1:  xor r14d, r14d              # the byte
    xor r15d, r15d              # the column
2:  cmp r14, r13
    jae 9f
    movzx eax, byte ptr [rbx + r14]
    cmp eax, 9
    jne 3f
    mov eax, r15d
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    mov eax, [rip + g_tab_width]
    sub eax, edx
    add r15d, eax
    inc r14
    jmp 2b
3:  cmp eax, 0x80
    jae 4f
    inc r15d
    inc r14
    jmp 2b
4:  lea rdi, [rbx + r14]
    mov rsi, r12
    sub rsi, r14
    call utf8_decode
    push rdx
    push rdx
    mov edi, eax
    call cp_width
    add r15d, eax
    pop rdx
    pop rdx
    test edx, edx
    jnz 5f
    mov edx, 1
5:  add r14, rdx
    jmp 2b
9:  mov eax, r15d
    EPILOGUE

# paint_line(doc, line, x, y): a line's text in its syntax colors
paint_line:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx              # x
    mov [rsp + 4], ecx          # y
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov r14, rax
    mov r15, rdx
    lea rdi, [rip + pv_cls]
    mov qword ptr [rdi + SB_len], 0
    lea rsi, [r15 + 16]
    call sb_reserve
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rcx, r15
    mov r8, [rip + pv_cls + SB_ptr]
    call syntax_line
    mov eax, [rsp + 4]
    add eax, [rip + g_base]
    mov [rsp + 8], eax          # the baseline
    xor r13d, r13d              # the byte
    mov dword ptr [rsp + 12], 0 # the column
1:  cmp r13, r15
    jae 9f
    mov eax, [rsp + 12]
    imul eax, [rip + g_cw]
    add eax, [rsp]
    cmp eax, [rip + g_cv + CV_cx1]
    jge 9f
    mov [rsp + 16], eax         # x
    movzx eax, byte ptr [r14 + r13]
    cmp eax, 9
    jne 2f
    mov eax, [rsp + 12]
    xor edx, edx
    div dword ptr [rip + g_tab_width]
    mov eax, [rip + g_tab_width]
    sub eax, edx
    add [rsp + 12], eax
    inc r13
    jmp 1b
2:  cmp eax, ' '
    jne 3f
    inc dword ptr [rsp + 12]
    inc r13
    jmp 1b
3:  lea rdi, [r14 + r13]
    mov rsi, r15
    sub rsi, r13
    call utf8_decode
    test edx, edx
    jnz 31f
    mov edx, 1
31: mov [rsp + 20], edx         # its bytes
    mov [rsp + 24], eax         # the code point
    mov rcx, [rip + pv_cls + SB_ptr]
    movzx ecx, byte ptr [rcx + r13]
    lea rdx, [rip + g_theme]
    mov r9d, [rdx + rcx*4 + 4*T_SYN]
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 16]
    mov edx, [rsp + 8]
    lea rcx, [r14 + r13]
    mov r8d, [rsp + 20]
    call text_draw
    mov edi, [rsp + 24]
    call cp_width
    add [rsp + 12], eax
    mov eax, [rsp + 20]
    add r13, rax
    jmp 1b
9:  EPILOGUE

# draw_list(x, y, w, h): the locations grouped by file, the chosen one marked; a click chooses
draw_list:
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    # the separator
    M edx, MI_1
    mov ecx, [rsp + 12]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    # the rows: a file row before each new path, then its locations; the chosen one stays in view
    call list_row_of_sel
    mov ecx, [rip + pv_rows]
    mov edx, [rip + pv_listtop]
    cmp eax, edx
    jge 1f
    mov [rip + pv_listtop], eax
    jmp 2f
1:  add edx, ecx
    cmp eax, edx
    jl 2f
    sub eax, ecx
    inc eax
    mov [rip + pv_listtop], eax
2:  xor r12d, r12d              # the row
    xor r13d, r13d              # the location
    mov r14, -1                 # the path before
3:  cmp r13, [rip + pv_locs + VEC_len]
    jae 9f
    mov rdi, r13
    call loc
    mov rbx, rax
    mov rax, [rbx + PVL_path]
    cmp rax, r14
    je 4f
    mov r14, rax
    # a file row
    mov eax, r12d
    sub eax, [rip + pv_listtop]
    js 31f
    cmp eax, [rip + pv_rows]
    jae 9f
    imul eax, [rip + g_lh]
    add eax, [rsp + 4]
    mov [rsp + 16], eax
    mov rdi, [rbx + PVL_path]
    add rdi, [rip + pv_bytes + SB_ptr]
    call name_of
    mov r8, rax
    mov edx, [rsp + 16]
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov ecx, [rip + g_lh]
    COLOR r9d, T_MUTED
    call ui_text_c
31: inc r12d
4:  # a location row: "LINE:COL  preview"
    mov eax, r12d
    sub eax, [rip + pv_listtop]
    js 6f
    cmp eax, [rip + pv_rows]
    jae 9f
    imul eax, [rip + g_lh]
    add eax, [rsp + 4]
    mov [rsp + 16], eax
    cmp r13d, [rip + pv_sel]
    jne 41f
    mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_1]
    mov esi, eax
    mov edx, [rsp + 8]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_SELECTION
    call gfx_fill
41: lea edi, [r13 + ID_PV + 16]
    mov esi, [rsp]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 8]
    mov r8d, [rip + g_lh]
    call ui_btn
    test eax, UB_CLICK
    jz 42f
    mov [rip + pv_sel], r13d
    call choose
42: lea rdi, [rip + pv_buf]
    call sb_clear
    lea rdi, [rip + pv_buf]
    mov esi, [rbx + PVL_l1]
    call sb_push_u64
    lea rdi, [rip + pv_buf]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + pv_buf]
    mov esi, [rbx + PVL_c1]
    call sb_push_u64
    lea rdi, [rip + pv_buf]
    lea rsi, [rip + .Lgap]
    call sb_push_cstr
    mov rsi, [rbx + PVL_prev]
    add rsi, [rip + pv_bytes + SB_ptr]
    lea rdi, [rip + pv_buf]
    call sb_push_cstr
    lea rdi, [rip + pv_buf]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 16]
    mov ecx, [rip + g_lh]
    mov r8, [rip + pv_buf + SB_ptr]
    COLOR r9d, T_FG
    call ui_text_c
6:  inc r12d
    inc r13
    jmp 3b
9:  call gfx_clip_pop
    EPILOGUE

# list_row_of_sel() -> eax the list row of the chosen location (file rows counted)
list_row_of_sel:
    PROLOGUE
    xor eax, eax                # rows
    xor ecx, ecx
    mov rdx, -1
1:  cmp rcx, [rip + pv_locs + VEC_len]
    jae 9f
    imul r8, rcx, PVL_SIZE
    add r8, [rip + pv_locs + VEC_ptr]
    mov r8, [r8 + PVL_path]
    cmp r8, rdx
    je 2f
    mov rdx, r8
    inc eax
2:  cmp ecx, [rip + pv_sel]
    je 9f
    inc eax
    inc rcx
    jmp 1b
9:  EPILOGUE

# FN peek_dump(sb): print-peek: "peek=closed", or "peek open kind=K file=NAME first=LINE sel=I/N"
# and a line per location ("loc PATH:L:C PREVIEW", "*" before the chosen one)
FN peek_dump
    PROLOGUE
    mov r12, rdi
    cmp dword ptr [rip + pv_open], 0
    jne 1f
    mov rdi, r12
    lea rsi, [rip + .Ld_closed]
    call sb_push_cstr
    EPILOGUE
1:  mov rdi, r12
    lea rsi, [rip + .Ld_open]
    call sb_push_cstr
    mov rsi, [rip + pv_title]
    test rsi, rsi
    jz 11f
    mov rdi, r12
    call sb_push_cstr
11: mov rdi, r12
    lea rsi, [rip + .Ld_file]
    call sb_push_cstr
    mov rax, [rip + pv_target]
    lea rsi, [rip + .Ld_unread]
    test rax, rax
    jz 12f
    mov rsi, [rax + DOC_name]
12: mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_first]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + pv_scroll]
    inc rsi
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_sel]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rip + pv_sel]
    inc esi
    call sb_push_u64
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rip + pv_locs + VEC_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor ebx, ebx
2:  cmp rbx, [rip + pv_locs + VEC_len]
    jae 9f
    mov rdi, rbx
    call loc
    mov r13, rax
    mov rdi, r12
    lea rsi, [rip + .Ld_loc]
    cmp ebx, [rip + pv_sel]
    jne 21f
    lea rsi, [rip + .Ld_locsel]
21: call sb_push_cstr
    mov rdi, [r13 + PVL_path]
    add rdi, [rip + pv_bytes + SB_ptr]
    call name_of
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [r13 + PVL_l1]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [r13 + PVL_c1]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, [r13 + PVL_prev]
    add rsi, [rip + pv_bytes + SB_ptr]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc rbx
    jmp 2b
9:  EPILOGUE

.section .rodata
.Ldash: .asciz " - "
.Lgap: .asciz "  "
.Lof: .asciz " of "
.Lunreadable: .asciz "This file could not be read"
.Ld_closed: .asciz "peek=closed\n"
.Ld_open: .asciz "peek open kind="
.Ld_file: .asciz " file="
.Ld_unread: .asciz "-"
.Ld_first: .asciz " first="
.Ld_sel: .asciz " sel="
.Ld_loc: .asciz "  loc "
.Ld_locsel: .asciz "* loc "
