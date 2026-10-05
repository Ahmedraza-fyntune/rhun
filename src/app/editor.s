# editor view: rendering, mouse, keyboard editing on the active document
.include "rhun.inc"

.equ ID_EDITOR, 0x1001
.equ ID_EDSCROLL, 0x1002
.equ BLINK_MS, 530              # each half of the caret's blink
.equ BLINK_FOR, 30000           # it blinks this long after the last caret activity, then stays on

.bss
.p2align 3
.globl g_doc, g_reveal, g_blink_t0
.globl cmd_select_all_matches, cmd_cursor_up, cmd_cursor_down
.globl cursors_clear, cursors_add, cursors_normalize
.globl ed_multi_type, ed_multi_backspace, ed_multi_delete_fwd, ed_multi_newline, ed_multi_move
.globl g_carets_buf, g_carets_cnt
g_doc: .quad 0
g_reveal: .long 0
g_ed_x: .long 0
g_ed_y: .long 0
g_ed_w: .long 0
g_ed_h: .long 0
g_ed_tx: .long 0                # x of column 0 (before horizontal scroll)
g_dragging: .long 0
.p2align 3
g_blink_t0: .quad 0
blink_seen: .long 0             # the half of the blink the last frame was asked for
classes: .zero SB_SIZE          # per-byte syntax class for the line being drawn
clip_sb: .zero SB_SIZE
.globl g_ed_find, g_ed_find_case
g_ed_find: .zero SB_SIZE        # find highlight text (set by the find bar)
g_ed_find_case: .long 0
.p2align 3
g_carets_buf: .space 8 * 1024
g_carets_cnt: .long 0
.p2align 3
g_curs_scratch: .zero VEC_SIZE

.text

# ed_sel(doc) -> rax start, rdx end
FN ed_sel
    mov rax, [rdi + DOC_cur]
    mov rdx, [rdi + DOC_anchor]
    cmp rax, rdx
    jbe 1f
    xchg rax, rdx
1:  ret

# ed_touch(): cursor activity (reveal + solid caret)
FN ed_touch
    mov dword ptr [rip + g_reveal], 1
    mov dword ptr [rip + g_dirty], 1
    call time_ms
    mov [rip + g_blink_t0], rax
    ret

# ed_set_cursor(doc, pos, extend)
FN ed_set_cursor
    mov [rdi + DOC_cur], rsi
    test edx, edx
    jnz 1f
    mov [rdi + DOC_anchor], rsi
1:  jmp ed_touch

# ed_delete_sel(doc, editkind) -> 1 if something was deleted
FN ed_delete_sel
    READONLY_RET rdi
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13d, esi
    call ed_sel
    cmp rax, rdx
    je 1f
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    sub rdx, rax
    mov ecx, r13d
    call doc_delete
    mov [rbx + DOC_cur], r12
    mov [rbx + DOC_anchor], r12
    mov eax, 1
    jmp 2f
1:  xor eax, eax
2:  pop r13
    pop r12
    pop rbx
    ret

# ed_insert(doc, ptr, len, editkind): replace selection with text, cursor after it
FN ed_insert
    READONLY_RET rdi
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    call ed_sel
    cmp rax, rdx
    je 1f
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    xor esi, esi
    call ed_delete_sel
    mov r15, [rbx + DOC_cur]
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_end_group
    jmp 2f
1:  mov r15, [rbx + DOC_cur]
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    mov r8d, r14d
    call doc_insert
2:  add r15, r13
    mov [rbx + DOC_cur], r15
    mov [rbx + DOC_anchor], r15
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    EPILOGUE

# line_indent(doc, line) -> rax = bytes of leading blanks, edx = visual columns
FN line_indent
    PROLOGUE
    mov rbx, rdi
    call doc_line_text
    mov r12, rax
    mov r13, rdx
    xor ecx, ecx
    xor r14d, r14d              # columns
1:  cmp rcx, r13
    jae 3f
    movzx eax, byte ptr [r12 + rcx]
    cmp al, ' '
    jne 2f
    inc r14d
    inc rcx
    jmp 1b
2:  cmp al, 9
    jne 3f
    mov eax, r14d
    xor edx, edx
    div dword ptr [rip + cfg_tab_width]
    mov eax, [rip + cfg_tab_width]
    sub eax, edx
    add r14d, eax
    inc rcx
    jmp 1b
3:  mov rax, rcx
    mov edx, r14d
    EPILOGUE

# ---- motions ----

# ed_move(kind, extend) ; kind: 0 left 1 right 2 up 3 down 4 home 5 end 6 wordl 7 wordr 8 pgup 9 pgdn 10 docstart 11 docend
FN ed_move
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Lmv_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_move
    PROLOGUE 16
    mov rbx, rax
    mov r12d, edi
    mov r13d, esi
    mov r14, [rbx + DOC_cur]
    # collapsing a selection with left/right
    test r13d, r13d
    jnz 1f
    cmp r12d, 1
    ja 1f
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 1f
    mov r14, rax
    test r12d, r12d
    jz .Lmv_set_h
    mov r14, rdx
    jmp .Lmv_set_h
1:  lea rax, [rip + .Lmv_table]
    mov eax, r12d
    cmp eax, 0
    je .Lmv_left
    cmp eax, 1
    je .Lmv_right
    cmp eax, 2
    je .Lmv_up
    cmp eax, 3
    je .Lmv_down
    cmp eax, 4
    je .Lmv_home
    cmp eax, 5
    je .Lmv_end
    cmp eax, 6
    je .Lmv_wordl
    cmp eax, 7
    je .Lmv_wordr
    cmp eax, 8
    je .Lmv_pgup
    cmp eax, 9
    je .Lmv_pgdn
    cmp eax, 10
    je .Lmv_start
    jmp .Lmv_endd
.Lmv_left:
    mov rdi, rbx
    mov rsi, r14
    call doc_prev_char
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_right:
    mov rdi, rbx
    mov rsi, r14
    call doc_next_char
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_wordl:
    mov rdi, rbx
    mov rsi, r14
    call doc_word_left
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_wordr:
    mov rdi, rbx
    mov rsi, r14
    call doc_word_right
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_home:
    # smart home: first non-blank, then column 0
    mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    call doc_line_start
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r15
    call line_indent
    add rax, [rsp]
    cmp r14, rax
    je 2f
    mov r14, rax
    jmp .Lmv_set_h
2:  mov r14, [rsp]
    jmp .Lmv_set_h
.Lmv_end:
    mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_end
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_start:
    xor r14d, r14d
    jmp .Lmv_set_h
.Lmv_endd:
    mov rdi, rbx
    call doc_len
    mov r14, rax
    jmp .Lmv_set_h
.Lmv_up:
    mov r15, -1
    jmp .Lmv_vert
.Lmv_down:
    mov r15, 1
    jmp .Lmv_vert
.Lmv_pgup:
    call page_lines
    neg rax
    mov r15, rax
    jmp .Lmv_vert
.Lmv_pgdn:
    call page_lines
    mov r15, rax
.Lmv_vert:
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne .Lmv_wrap
    cmp qword ptr [rbx + DOC_prefx], -1
    jne 3f
    mov rdi, rbx
    mov rsi, r14
    call doc_col_of
    mov [rbx + DOC_prefx], rax
3:  mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    add rax, r15
    jns 4f
    # above the first line: go to start
    xor r14d, r14d
    jmp .Lmv_set_v
4:  cmp rax, [rbx + DOC_nlines]
    jb 5f
    mov rdi, rbx
    call doc_len
    mov r14, rax
    jmp .Lmv_set_v
5:  mov rdi, rbx
    mov rsi, rax
    mov rdx, [rbx + DOC_prefx]
    call doc_pos_at_col
    mov r14, rax
    jmp .Lmv_set_v
.Lmv_wrap:
    # one visual row at a time; r15 = signed row count
    cmp qword ptr [rbx + DOC_prefx], -1
    jne 41f
    mov rdi, rbx
    call cursor_row
    mov [rbx + DOC_prefx], rcx
41: mov rax, [rbx + DOC_cur]
    mov [rsp], rax
    mov [rbx + DOC_cur], r14
42: test r15, r15
    jz 44f
    mov esi, 1
    mov rax, r15
    test rax, rax
    jns 43f
    mov rsi, -1
43: sub r15, rsi
    mov rdi, rbx
    mov rdx, [rbx + DOC_prefx]
    call wrap_move
    mov [rbx + DOC_cur], rax
    jmp 42b
44: mov r14, [rbx + DOC_cur]
    mov rax, [rsp]
    mov [rbx + DOC_cur], rax
    jmp .Lmv_set_v
.Lmv_set_h:
    mov qword ptr [rbx + DOC_prefx], -1
.Lmv_set_v:
    mov rdi, rbx
    mov rsi, r14
    mov edx, r13d
    mov [rbx + DOC_cur], rsi
    test edx, edx
    jnz 6f
    mov [rbx + DOC_anchor], rsi
6:  call ed_touch
.Lmv_ret:
    EPILOGUE
.Lmv_fast_ret:
    ret
.Lmv_table:

# page_lines() -> visible lines - 1 (at least 1)
page_lines:
    mov eax, [rip + g_ed_h]
    xor edx, edx
    mov ecx, [rip + g_lh]
    test ecx, ecx
    jz 1f
    div ecx
    dec eax
    cmp eax, 1
    jge 2f
1:  mov eax, 1
2:  ret

# ---- editing ----

# ed_type(cp): insert a typed character (auto-pairs, closing bracket overtype)
FN ed_type
    READONLY_RET
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Lty_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_type
    PROLOGUE 32
    mov rbx, rax
    mov r12d, edi
    mov edi, r12d
    lea rsi, [rsp]
    call utf8_encode
    mov r13, rax
    cmp dword ptr [rip + cfg_auto_pairs], 0
    je .Lty_plain
    # overtype a closing char that is already there
    cmp r12d, ')'
    je 1f
    cmp r12d, ']'
    je 1f
    cmp r12d, '}'
    je 1f
    cmp r12d, '"'
    je 1f
    cmp r12d, 0x27
    je 1f
    cmp r12d, '`'
    jne 2f
1:  mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 2f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_byte
    cmp eax, r12d
    jne 2f
    mov rsi, [rbx + DOC_cur]
    inc rsi
    mov rdi, rbx
    xor edx, edx
    call ed_set_cursor
    jmp .Lty_ret
2:  # opening char -> insert pair
    lea r14, [rip + pair_open]
    xor ecx, ecx
3:  movzx eax, byte ptr [r14 + rcx]
    test eax, eax
    jz .Lty_plain
    cmp eax, r12d
    je 4f
    inc ecx
    jmp 3b
4:  lea rax, [rip + pair_close]
    movzx r15d, byte ptr [rax + rcx]
    # quotes only pair when the next char is not a word char and the previous isn't either
    cmp r12d, '"'
    je 41f
    cmp r12d, 0x27
    je 41f
    cmp r12d, '`'
    jne 5f
41: mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 5f
    mov rsi, [rbx + DOC_cur]
    test rsi, rsi
    jz 42f
    dec rsi
    mov rdi, rbx
    call doc_byte
    cmp eax, r12d
    je .Lty_plain
    mov edi, eax
    call is_ident
    test eax, eax
    jnz .Lty_plain
42: mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jnz .Lty_plain
5:  # with a selection: wrap it
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 6f
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov [rsp + 24], r15b
    lea rdx, [rsp + 24]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, [rsp + 8]
    lea rdx, [rsp]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_end_group
    mov rax, [rsp + 8]
    inc rax
    mov [rbx + DOC_anchor], rax
    mov rax, [rsp + 16]
    inc rax
    mov [rbx + DOC_cur], rax
    call ed_touch
    jmp .Lty_ret
6:  # only pair before whitespace / closing chars / end
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_byte
    test eax, eax
    jz 7f
    cmp eax, 10
    je 7f
    cmp eax, ' '
    je 7f
    cmp eax, 9
    je 7f
    cmp eax, ')'
    je 7f
    cmp eax, ']'
    je 7f
    cmp eax, '}'
    je 7f
    cmp eax, ','
    je 7f
    cmp eax, ';'
    jne .Lty_plain
7:  mov [rsp + 1], r15b
    mov rdi, rbx
    lea rsi, [rsp]
    mov edx, 2
    mov ecx, EK_TYPE
    call ed_insert
    dec qword ptr [rbx + DOC_cur]
    dec qword ptr [rbx + DOC_anchor]
    jmp .Lty_ret
.Lty_plain:
    mov rdi, rbx
    lea rsi, [rsp]
    mov rdx, r13
    mov ecx, EK_TYPE
    call ed_insert
.Lty_ret:
    EPILOGUE
.Lty_fast_ret:
    ret

# ed_newline(): newline keeping indentation, extra level after an opening bracket or ':'
FN ed_newline
    READONLY_RET
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Lnl_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_newline
    PROLOGUE 32
    mov rbx, rax
    lea rdi, [rsp]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call line_indent
    mov r13, rax                # indent bytes
    lea rdi, [rsp]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r13
    call doc_range
    lea rdi, [rsp]
    mov rsi, rax
    mov rdx, r13
    call sb_push
    # char before the cursor (skipping blanks)
    mov rdi, rbx
    call ed_sel
    mov r15, rax
1:  cmp r15, r14
    jbe 3f
    mov rdi, rbx
    lea rsi, [r15 - 1]
    call doc_byte
    cmp al, ' '
    je 2f
    cmp al, 9
    jne 4f
2:  dec r15
    jmp 1b
4:  cmp al, '{'
    je 5f
    cmp al, '('
    je 5f
    cmp al, '['
    je 5f
    cmp al, ':'
    jne 3f
    mov rcx, [rbx + DOC_lang]
    test rcx, rcx
    jz 3f
    test qword ptr [rcx + GR_flags], GF_COLON
    jz 3f
5:  mov [rsp + 24], eax
    call push_indent_unit
    # between a pair "{|}": put the closer on its own line
    mov rdi, rbx
    call ed_sel
    mov rsi, rdx
    mov rdi, rbx
    call doc_byte
    mov ecx, [rsp + 24]
    cmp ecx, '{'
    jne 51f
    cmp eax, '}'
    je 52f
51: cmp ecx, '('
    jne 53f
    cmp eax, ')'
    je 52f
53: cmp ecx, '['
    jne 3f
    cmp eax, ']'
    jne 3f
52: mov r15, [rsp + SB_len]     # cursor goes here
    lea rdi, [rsp]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r13
    call doc_range
    lea rdi, [rsp]
    mov rsi, rax
    mov rdx, r13
    call sb_push
    mov rdi, rbx
    mov rsi, [rsp + SB_ptr]
    mov rdx, [rsp + SB_len]
    xor ecx, ecx
    call ed_insert
    mov rax, [rsp + SB_len]
    sub rax, r15
    sub [rbx + DOC_cur], rax
    sub [rbx + DOC_anchor], rax
    jmp 9f
3:  mov rdi, rbx
    mov rsi, [rsp + SB_ptr]
    mov rdx, [rsp + SB_len]
    xor ecx, ecx
    call ed_insert
9:  lea rdi, [rsp]
    call sb_free
.Lnl_ret:
    EPILOGUE
.Lnl_fast_ret:
    ret

# push_indent_unit(): append one indentation unit to the sb at [rsp+8] of the caller frame
push_indent_unit:
    lea rdi, [rsp + 8]
    cmp dword ptr [rip + cfg_insert_spaces], 0
    je 2f
    push rbx
    push rdi
    mov ebx, [rip + cfg_tab_width]
1:  mov rdi, [rsp]
    mov esi, ' '
    call sb_push_byte
    dec ebx
    jnz 1b
    pop rdi
    pop rbx
    ret
2:  mov esi, 9
    jmp sb_push_byte

# ed_backspace(word)
FN ed_backspace
    READONLY_RET
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Lbs_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_backspace
    PROLOGUE 16
    mov rbx, rax
    mov r12d, edi
    mov rdi, rbx
    mov esi, EK_BACK
    call ed_delete_sel
    test eax, eax
    jnz 8f
    mov r13, [rbx + DOC_cur]
    test r13, r13
    jz 9f
    mov rdi, rbx
    mov rsi, r13
    test r12d, r12d
    jz 1f
    call doc_word_left
    jmp 5f
1:  # inside leading blanks with spaces indentation: remove to previous tab stop
    call doc_prev_char
    mov r14, rax
    cmp dword ptr [rip + cfg_insert_spaces], 0
    je 4f
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    cmp al, ' '
    jne 4f
    mov rdi, rbx
    mov rsi, r13
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r15, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_col_of
    test eax, eax
    jz 4f
    # only when everything before the cursor is blank
    mov rcx, r15
2:  cmp rcx, r13
    jae 3f
    push rcx
    mov rdi, rbx
    mov rsi, rcx
    call doc_byte
    pop rcx
    cmp al, ' '
    jne 4f
    inc rcx
    jmp 2b
3:  mov rdi, rbx
    mov rsi, r13
    call doc_col_of
    dec eax
    xor edx, edx
    div dword ptr [rip + cfg_tab_width]
    imul eax, [rip + cfg_tab_width]
    mov rcx, r13
    sub rcx, r15                # current col (all spaces)
    sub rcx, rax
    mov rax, r13
    sub rax, rcx
    jmp 5f
4:  mov rax, r14
    # delete an empty auto pair "(|)"
    cmp dword ptr [rip + cfg_auto_pairs], 0
    je 5f
    push rax
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    mov r15d, eax
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    lea rdi, [rip + pair_open]
    xor ecx, ecx
6:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 7f
    cmp edx, r15d
    jne 61f
    lea rdx, [rip + pair_close]
    movzx edx, byte ptr [rdx + rcx]
    cmp edx, eax
    jne 61f
    pop rax
    mov rdi, rbx
    mov rsi, rax
    mov edx, 2
    mov ecx, EK_BACK
    mov r13, rax
    call doc_delete
    jmp 71f
61: inc ecx
    jmp 6b
7:  pop rax
5:  mov rdx, r13
    sub rdx, rax
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    mov ecx, EK_BACK
    call doc_delete
71: mov [rbx + DOC_cur], r13
    mov [rbx + DOC_anchor], r13
8:  mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
9:  EPILOGUE
.Lbs_fast_ret:
    ret

# ed_delete_fwd(word)
FN ed_delete_fwd
    READONLY_RET
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Ldel_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_delete_fwd
    PROLOGUE
    mov rbx, rax
    mov r12d, edi
    mov rdi, rbx
    mov esi, EK_DEL
    call ed_delete_sel
    test eax, eax
    jnz 8f
    mov r13, [rbx + DOC_cur]
    mov rdi, rbx
    mov rsi, r13
    test r12d, r12d
    jz 1f
    call doc_word_right
    jmp 2f
1:  call doc_next_char
2:  mov rdx, rax
    sub rdx, r13
    jz 8f
    mov rdi, rbx
    mov rsi, r13
    mov ecx, EK_DEL
    call doc_delete
    mov [rbx + DOC_cur], r13
    mov [rbx + DOC_anchor], r13
8:  mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
9:  EPILOGUE
.Ldel_fast_ret:
    ret

# sel_lines(doc) -> rax first line, rdx last line (selection end at column 0 excluded)
sel_lines:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call ed_sel
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r12, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_of
    cmp rax, r12
    je 1f
    push rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov rcx, rax
    pop rax
    cmp rcx, r13
    jne 1f
    dec rax
1:  mov rdx, rax
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

# ed_indent(dir): +1 indent selected lines, -1 outdent
FN ed_indent
    READONLY_RET
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Lin_ret
    mov [rsp + 32], edi
    mov rdi, rbx
    call sel_lines
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call doc_begin_group
    # unit
    lea rdi, [rsp]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    call push_indent_unit_rsp
.Lin_line:
    cmp r12, r13
    ja .Lin_done
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    cmp dword ptr [rsp + 32], 0
    jl .Lin_out
    # skip empty lines
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    cmp rax, r14
    je .Lin_next
    mov rax, [rbx + DOC_cur]
    mov r15, [rbx + DOC_anchor]
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [rsp + SB_ptr]
    mov rcx, [rsp + SB_len]
    xor r8d, r8d
    call doc_insert
    jmp .Lin_next
.Lin_out:
    mov rdi, rbx
    mov rsi, r12
    call line_indent
    test rax, rax
    jz .Lin_next
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    mov edx, 1
    cmp al, 9
    je 1f
    mov edx, [rip + cfg_tab_width]
    cmp rdx, r15
    cmova rdx, r15
1:  mov rdi, rbx
    mov rsi, r14
    xor ecx, ecx
    call doc_delete
.Lin_next:
    inc r12
    jmp .Lin_line
.Lin_done:
    mov rdi, rbx
    call doc_end_group
    lea rdi, [rsp]
    call sb_free
    call ed_touch
.Lin_ret:
    EPILOGUE

push_indent_unit_rsp:
    # sb lives at [rsp+8] relative to our caller's frame after the call
    jmp push_indent_unit

# ed_tab(): indent selection spanning lines, else insert indentation at the cursor
FN ed_tab
    READONLY_RET
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + DOC_cursors + VEC_len], 0
    jz 10f
    mov edi, 9
    call ed_multi_type
    jmp 9f
10: mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 1f
    mov rdi, rbx
    call sel_lines
    cmp rax, rdx
    je 1f
    mov edi, 1
    call ed_indent
    jmp 9f
1:  cmp dword ptr [rip + cfg_insert_spaces], 0
    jne 2f
    mov byte ptr [rsp], 9
    mov edx, 1
    jmp 3f
2:  mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
    xor edx, edx
    div dword ptr [rip + cfg_tab_width]
    mov eax, [rip + cfg_tab_width]
    sub eax, edx
    mov edx, eax
    lea rdi, [rsp]
    mov ecx, edx
    mov al, ' '
    rep stosb
3:  mov rdi, rbx
    lea rsi, [rsp]
    xor ecx, ecx
    call ed_insert
9:  EPILOGUE

# ---- clipboard / line commands ----

# selection text or whole current line (with newline) -> clip_sb ; eax = 1 if it was a whole line
copy_to_clip:
    cmp qword ptr [rdi + DOC_cursors + VEC_len], 0
    jne copy_multi_to_clip
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + clip_sb]
    call sb_clear
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 1f
    mov r12, rax
    mov r13, rdx
    xor r15d, r15d
    jmp 2f
1:  mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r12, rax
    lea rsi, [r14 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 3f
    mov rdi, rbx
    call doc_line_start
    mov r13, rax
    jmp 4f
3:  mov rdi, rbx
    call doc_len
    mov r13, rax
4:  mov r15d, 1
2:  mov rsi, r13
    sub rsi, r12
    lea rdi, [rip + clip_sb]
    call sb_reserve
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    sub rdx, r12
    call doc_copy
    mov rax, r13
    sub rax, r12
    add [rip + clip_sb + SB_len], rax
    # whole last line without newline: add one so paste works line-wise
    test r15d, r15d
    jz 5f
    mov rax, [rip + clip_sb + SB_len]
    test rax, rax
    jz 5f
    mov rcx, [rip + clip_sb + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je 5f
    lea rdi, [rip + clip_sb]
    mov esi, 10
    call sb_push_byte
5:  mov rdi, [rip + clip_sb + SB_ptr]
    mov rsi, [rip + clip_sb + SB_len]
    PCALL P_clip_set
    mov eax, r15d
    mov [rip + g_clip_line], eax
    EPILOGUE

FN cmd_copy
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    call copy_to_clip
1:  ret

FN cmd_cut
    READONLY_RET
    push rbx
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call copy_to_clip
    test eax, eax
    jz 1f
    # whole line
    call cmd_delete_line
    jmp 9f
1:  mov rdi, rbx
    xor esi, esi
    call ed_delete_sel
    call ed_touch
9:  pop rbx
    ret

FN cmd_paste
    PCALL P_clip_get
    ret

# ed_paste(ptr, len): line-wise when the clipboard came from a whole-line copy of ours
FN ed_paste
    READONLY_RET
    test rsi, rsi
    jz .Lpst_fast_ret
    mov rax, [rip + g_doc]
    test rax, rax
    jz .Lpst_fast_ret
    cmp qword ptr [rax + DOC_cursors + VEC_len], 0
    jne ed_multi_paste
    PROLOGUE
    mov rbx, rax
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    mov rsi, r13
    call ed_clip_linewise
    test eax, eax
    jz 1f
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 1f
    # insert above the current line, keep cursor column
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r12
    mov rcx, r13
    xor r8d, r8d
    call doc_insert
    # the insert moved a cursor past the line start; one at the line start stays before the text
    cmp [rbx + DOC_cur], r14
    jne 2f
    add [rbx + DOC_cur], r13
    add [rbx + DOC_anchor], r13
2:  call ed_touch
    jmp 9f
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call ed_insert
9:  EPILOGUE
.Lpst_fast_ret:
    ret

FN cmd_select_all
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    mov qword ptr [rdi + DOC_anchor], 0
    push rdi
    call doc_len
    pop rdi
    mov [rdi + DOC_cur], rax
    jmp ed_touch
1:  ret

# select the current line(s), extending on repeat
FN cmd_select_line
    push rbx
    push r12
    push r13
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call sel_lines
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 1f
    # already selecting whole lines -> extend by one
    inc r13
1:  mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rbx + DOC_anchor], rax
    lea rsi, [r13 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 2f
    mov rdi, rbx
    call doc_line_start
    jmp 3f
2:  mov rdi, rbx
    call doc_len
3:  mov [rbx + DOC_cur], rax
    call ed_touch
9:  pop r13
    pop r12
    pop rbx
    ret

# word_at(doc, pos) -> rax start, rdx end (empty when not on a word)
FN word_at
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rsi
1:  test r12, r12
    jz 2f
    mov rdi, rbx
    lea rsi, [r12 - 1]
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jz 2f
    dec r12
    jmp 1b
2:  mov rdi, rbx
    call doc_len
    mov r14, rax
3:  cmp r13, r14
    jae 4f
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jz 4f
    inc r13
    jmp 3b
4:  mov rax, r12
    mov rdx, r13
    EPILOGUE

# ctrl+d: select word, or the next occurrence of the selection
FN cmd_select_next
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne .Lsn_has_sel
    cmp qword ptr [rbx + DOC_cursors + VEC_len], 0
    jne .Lsn_has_sel

    # No selection currently: select word at cursor
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_at
    cmp rax, rdx
    je 9f
    mov [rbx + DOC_anchor], rax
    mov [rbx + DOC_cur], rdx
    call ed_touch
    jmp 9f

.Lsn_has_sel:
    mov rdi, rbx
    call cursors_collect_all
    test rax, rax
    jz 9f
    mov r12, [rdx + CURS_cur]
    mov r13, [rdx + CURS_anchor]
    mov rax, r12
    cmp r13, rax
    cmovb rax, r13             # needle start
    mov rdx, r12
    cmp r13, rdx
    cmova rdx, r13             # needle end
    cmp rax, rdx
    je 9f
    mov r14, rax               # needle pos
    mov r15, rdx
    sub r15, r14               # needle len

    # Find maximum end position among all cursors
    mov rcx, [rip + g_curs_scratch + VEC_len]
    mov r8, [rip + g_curs_scratch + VEC_ptr]
    xor rsi, rsi
.Lsn_find_max:
    test rcx, rcx
    jz .Lsn_do_search
    mov rax, [r8 + CURS_cur]
    mov rdx, [r8 + CURS_anchor]
    cmp rdx, rax
    cmova rax, rdx
    cmp rax, rsi
    cmova rsi, rax
    add r8, CURS_SIZE
    dec rcx
    jmp .Lsn_find_max

.Lsn_do_search:
    mov rdi, rbx
    mov rdx, rsi               # from
    mov rsi, r15               # needle len
    mov rcx, r14               # needle pos in doc
    call find_in_doc
    test rax, rax
    js 9f

    # Check if match rax already exists
    mov r12, rax
    mov rcx, [rip + g_curs_scratch + VEC_len]
    mov r8, [rip + g_curs_scratch + VEC_ptr]
.Lsn_check_dup:
    test rcx, rcx
    jz .Lsn_add_match
    mov rax, [r8 + CURS_cur]
    mov rdx, [r8 + CURS_anchor]
    cmp rdx, rax
    cmovb rax, rdx
    cmp rax, r12
    je 9f
    add r8, CURS_SIZE
    dec rcx
    jmp .Lsn_check_dup

.Lsn_add_match:
    mov rdi, rbx
    lea rsi, [r12 + r15]
    mov rdx, r12
    mov rcx, -1
    call cursors_add
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ctrl+shift+l: select all occurrences of selection
FN cmd_select_all_matches
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne .Lsam_has_sel
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_at
    cmp rax, rdx
    je 9f
    mov [rbx + DOC_anchor], rax
    mov [rbx + DOC_cur], rdx
.Lsam_has_sel:
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    je 9f
    mov r12, rax                # start
    mov r13, rdx
    sub r13, r12                # len
    lea rdi, [r13 + 1]
    call mem_alloc
    mov [rsp], rax              # needle buf
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    call doc_copy

    mov qword ptr [rbx + DOC_cursors + VEC_len], 0

    mov rdi, rbx
    call doc_contiguous
    mov [rsp + 8], rax          # doc text
    mov rdi, rbx
    call doc_len
    mov [rsp + 16], rax         # doc len

    xor r14, r14                # search offset
.Lsam_loop:
    cmp r14, [rsp + 16]
    jae .Lsam_done
    mov rdi, [rsp + 8]
    add rdi, r14
    mov rsi, [rsp + 16]
    sub rsi, r14
    mov rdx, [rsp]
    mov rcx, r13
    call str_find
    test rax, rax
    js .Lsam_done
    add rax, r14                # match pos
    mov r15, rax
    cmp r15, r12
    je .Lsam_next
    mov rdi, rbx
    lea rsi, [r15 + r13]
    mov rdx, r15
    mov rcx, -1
    call cursors_add
.Lsam_next:
    add r15, r13
    mov r14, r15
    jmp .Lsam_loop

.Lsam_done:
    mov rdi, [rsp]
    call mem_free
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ctrl+alt+Up: add cursor above
FN cmd_cursor_up
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call cursors_collect_all
    test rax, rax
    jz 9f
    mov r12, [rdx + CURS_cur]
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    test rax, rax
    jz 9f
    dec rax
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_col_of
    mov r14, rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call doc_pos_at_col
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rax
    mov rcx, r14
    call cursors_add
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ctrl+alt+Down: add cursor below
FN cmd_cursor_down
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call cursors_collect_all
    test rax, rax
    jz 9f
    dec rax
    imul rax, rax, CURS_SIZE
    add rax, rdx
    mov r12, [rax + CURS_cur]
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    inc rax
    cmp rax, [rbx + DOC_nlines]
    jae 9f
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_col_of
    mov r14, rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call doc_pos_at_col
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rax
    mov rcx, r14
    call cursors_add
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# cursors_clear(doc)
FN cursors_clear
    mov qword ptr [rdi + DOC_cursors + VEC_len], 0
    ret

# cursors_add(doc, cur, anchor, prefx)
FN cursors_add
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    lea rdi, [rbx + DOC_cursors]
    mov esi, CURS_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + CURS_cur], rcx
    mov rcx, [rsp + 8]
    mov [rax + CURS_anchor], rcx
    mov rcx, [rsp + 16]
    mov [rax + CURS_prefx], rcx
    EPILOGUE

# cursors_collect_all(doc) -> rax = count, rdx = ptr in g_curs_scratch
cursors_collect_all:
    PROLOGUE 16
    mov rbx, rdi
    mov qword ptr [rip + g_curs_scratch + VEC_len], 0

    # Push primary cursor
    lea rdi, [rip + g_curs_scratch]
    mov esi, CURS_SIZE
    call vec_push
    mov rcx, [rbx + DOC_cur]
    mov [rax + CURS_cur], rcx
    mov rcx, [rbx + DOC_anchor]
    mov [rax + CURS_anchor], rcx
    mov rcx, [rbx + DOC_prefx]
    mov [rax + CURS_prefx], rcx

    # Push all secondary cursors
    mov r12, [rbx + DOC_cursors + VEC_len]
    test r12, r12
    jz .Lcca_sort
    xor r13, r13
.Lcca_copy_loop:
    cmp r13, r12
    jae .Lcca_sort
    imul r14, r13, CURS_SIZE
    add r14, [rbx + DOC_cursors + VEC_ptr]
    lea rdi, [rip + g_curs_scratch]
    mov esi, CURS_SIZE
    call vec_push
    mov rcx, [r14 + CURS_cur]
    mov [rax + CURS_cur], rcx
    mov rcx, [r14 + CURS_anchor]
    mov [rax + CURS_anchor], rcx
    mov rcx, [r14 + CURS_prefx]
    mov [rax + CURS_prefx], rcx
    inc r13
    jmp .Lcca_copy_loop

.Lcca_sort:
    mov r12, [rip + g_curs_scratch + VEC_len]
    mov r13, [rip + g_curs_scratch + VEC_ptr]
    cmp r12, 1
    jbe .Lcca_done

    # Insertion sort by min(cur, anchor)
    mov r14, 1
.Lcca_isort_outer:
    cmp r14, r12
    jae .Lcca_dedup
    imul rax, r14, CURS_SIZE
    add rax, r13
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov r10, [rax + CURS_prefx]
    mov r11, r8
    cmp r9, r11
    cmovb r11, r9

    mov r15, r14
.Lcca_isort_inner:
    test r15, r15
    jz .Lcca_isort_place
    lea rax, [r15 - 1]
    imul rax, rax, CURS_SIZE
    add rax, r13
    mov rcx, [rax + CURS_cur]
    mov rdx, [rax + CURS_anchor]
    mov rsi, rcx
    cmp rdx, rsi
    cmovb rsi, rdx
    cmp rsi, r11
    jbe .Lcca_isort_place

    imul rdi, r15, CURS_SIZE
    add rdi, r13
    mov [rdi + CURS_cur], rcx
    mov [rdi + CURS_anchor], rdx
    mov rax, [rax + CURS_prefx]
    mov [rdi + CURS_prefx], rax
    dec r15
    jmp .Lcca_isort_inner

.Lcca_isort_place:
    imul rdi, r15, CURS_SIZE
    add rdi, r13
    mov [rdi + CURS_cur], r8
    mov [rdi + CURS_anchor], r9
    mov [rdi + CURS_prefx], r10
    inc r14
    jmp .Lcca_isort_outer

.Lcca_dedup:
    xor r15, r15
    mov r14, 1
.Lcca_dedup_loop:
    cmp r14, r12
    jae .Lcca_dedup_done
    imul rax, r15, CURS_SIZE
    add rax, r13
    imul rdx, r14, CURS_SIZE
    add rdx, r13

    mov rcx, [rax + CURS_cur]
    mov r8, [rax + CURS_anchor]
    mov rsi, rcx
    cmp r8, rsi
    cmovb rsi, r8              # min1
    mov rdi, rcx
    cmp r8, rdi
    cmova rdi, r8              # max1

    mov rcx, [rdx + CURS_cur]
    mov r8, [rdx + CURS_anchor]
    mov r9, rcx
    cmp r8, r9
    cmovb r9, r8               # min2
    mov r10, rcx
    cmp r8, r10
    cmova r10, r8              # max2

    cmp rsi, rdi
    jne 1f
    cmp r9, r10
    jne 1f
    cmp rsi, r9
    je .Lcca_skip_item
    jmp .Lcca_keep_item

1:  cmp rdi, r9
    jb .Lcca_keep_item
    cmp r10, rdi
    cmova rdi, r10
    mov [rax + CURS_cur], rdi
    mov [rax + CURS_anchor], rsi
    jmp .Lcca_skip_item

.Lcca_keep_item:
    inc r15
    imul rdi, r15, CURS_SIZE
    add rdi, r13
    mov rcx, [rdx + CURS_cur]
    mov [rdi + CURS_cur], rcx
    mov rcx, [rdx + CURS_anchor]
    mov [rdi + CURS_anchor], rcx
    mov rcx, [rdx + CURS_prefx]
    mov [rdi + CURS_prefx], rcx

.Lcca_skip_item:
    inc r14
    jmp .Lcca_dedup_loop

.Lcca_dedup_done:
    inc r15
    mov [rip + g_curs_scratch + VEC_len], r15

.Lcca_done:
    mov rax, [rip + g_curs_scratch + VEC_len]
    mov rdx, [rip + g_curs_scratch + VEC_ptr]
    EPILOGUE

# cursors_normalize(doc)
FN cursors_normalize
    PROLOGUE 16
    mov rbx, rdi
    call cursors_collect_all
    test rax, rax
    jz 9f
    mov r12, rax                # count
    mov r13, rdx                # ptr

    # Write back primary cursor
    mov rcx, [r13 + CURS_cur]
    mov [rbx + DOC_cur], rcx
    mov rcx, [r13 + CURS_anchor]
    mov [rbx + DOC_anchor], rcx
    mov rcx, [r13 + CURS_prefx]
    mov [rbx + DOC_prefx], rcx

    # Write back secondaries
    mov qword ptr [rbx + DOC_cursors + VEC_len], 0
    cmp r12, 1
    jbe 9f
    mov r14, 1
.Lcn_loop:
    cmp r14, r12
    jae 9f
    imul rax, r14, CURS_SIZE
    add rax, r13
    mov rdi, rbx
    mov rsi, [rax + CURS_cur]
    mov rdx, [rax + CURS_anchor]
    mov rcx, [rax + CURS_prefx]
    call cursors_add
    inc r14
    jmp .Lcn_loop
9:  EPILOGUE

# cursors_move_one(doc, cur, anchor, prefx, kind, extend) -> rax = new_cur, rdx = new_anchor, rcx = new_prefx
cursors_move_one:
    PROLOGUE 48
    mov [rsp], r9d              # extend
    mov rbx, rdi
    mov r12, rsi                # cur
    mov r13, rdx                # anchor
    mov r14, rcx                # prefx
    mov r15d, r8d               # kind

    # Selection collapse on left/right without extend
    test r9d, r9d
    jnz .Lcmo_dispatch
    cmp r15d, 1
    ja .Lcmo_dispatch
    cmp r12, r13
    je .Lcmo_dispatch
    mov rax, r12
    cmp r13, rax
    cmovb rax, r13             # min(cur, anchor)
    test r15d, r15d
    jz .Lcmo_set_cur           # left: min
    mov rax, r12
    cmp r13, rax
    cmova rax, r13             # right: max
    jmp .Lcmo_set_cur

.Lcmo_dispatch:
    cmp r15d, 0
    je .Lcmo_left
    cmp r15d, 1
    je .Lcmo_right
    cmp r15d, 2
    je .Lcmo_up
    cmp r15d, 3
    je .Lcmo_down
    cmp r15d, 4
    je .Lcmo_home
    cmp r15d, 5
    je .Lcmo_end
    cmp r15d, 6
    je .Lcmo_wordl
    cmp r15d, 7
    je .Lcmo_wordr
    cmp r15d, 8
    je .Lcmo_pgup
    cmp r15d, 9
    je .Lcmo_pgdn
    cmp r15d, 10
    je .Lcmo_start
    jmp .Lcmo_endd

.Lcmo_left:
    mov rdi, rbx
    mov rsi, r12
    call doc_prev_char
    jmp .Lcmo_set_cur

.Lcmo_right:
    mov rdi, rbx
    mov rsi, r12
    call doc_next_char
    jmp .Lcmo_set_cur

.Lcmo_wordl:
    mov rdi, rbx
    mov rsi, r12
    call doc_word_left
    jmp .Lcmo_set_cur

.Lcmo_wordr:
    mov rdi, rbx
    mov rsi, r12
    call doc_word_right
    jmp .Lcmo_set_cur

.Lcmo_home:
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    call doc_line_start
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r15
    call line_indent
    add rax, [rsp + 8]
    cmp rax, r12
    je 1f
    jmp .Lcmo_set_cur
1:  mov rax, [rsp + 8]
    jmp .Lcmo_set_cur

.Lcmo_end:
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_end
    jmp .Lcmo_set_cur

.Lcmo_start:
    xor eax, eax
    jmp .Lcmo_set_cur

.Lcmo_endd:
    mov rdi, rbx
    call doc_len
    jmp .Lcmo_set_cur

.Lcmo_up:
    mov r15, -1
    jmp .Lcmo_vert

.Lcmo_down:
    mov r15, 1
    jmp .Lcmo_vert

.Lcmo_pgup:
    call page_lines
    neg rax
    mov r15, rax
    jmp .Lcmo_vert

.Lcmo_pgdn:
    call page_lines
    mov r15, rax

.Lcmo_vert:
    cmp r14, -1
    jne 2f
    mov rdi, rbx
    mov rsi, r12
    call doc_col_of
    mov r14, rax
2:  mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    add rax, r15
    jns 3f
    xor eax, eax
    jmp .Lcmo_vert_done
3:  cmp rax, [rbx + DOC_nlines]
    jb 4f
    mov rdi, rbx
    call doc_len
    jmp .Lcmo_vert_done
4:  mov rdi, rbx
    mov rsi, rax
    mov rdx, r14
    call doc_pos_at_col
.Lcmo_vert_done:
    mov rdx, r13
    cmp dword ptr [rsp], 0
    cmove rdx, rax
    mov rcx, r14
    EPILOGUE

.Lcmo_set_cur:
    mov rdx, r13
    cmp dword ptr [rsp], 0
    cmove rdx, rax
    mov rcx, -1
    EPILOGUE

# ed_multi_move(kind, extend)
FN ed_multi_move
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov [rsp], edi              # kind
    mov [rsp + 8], esi          # extend

    # Move primary cursor
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    mov rdx, [rbx + DOC_anchor]
    mov rcx, [rbx + DOC_prefx]
    mov r8d, [rsp]
    mov r9d, [rsp + 8]
    call cursors_move_one
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rdx
    mov [rbx + DOC_prefx], rcx

    # Move all secondary cursors
    mov r12, [rbx + DOC_cursors + VEC_len]
    test r12, r12
    jz .Lmm_done
    mov r14, [rbx + DOC_cursors + VEC_ptr]
    xor r13, r13
.Lmm_loop:
    cmp r13, r12
    jae .Lmm_done
    mov rdi, rbx
    mov rsi, [r14 + CURS_cur]
    mov rdx, [r14 + CURS_anchor]
    mov rcx, [r14 + CURS_prefx]
    mov r8d, [rsp]
    mov r9d, [rsp + 8]
    call cursors_move_one
    mov [r14 + CURS_cur], rax
    mov [r14 + CURS_anchor], rdx
    mov [r14 + CURS_prefx], rcx
    add r14, CURS_SIZE
    inc r13
    jmp .Lmm_loop

.Lmm_done:
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ed_multi_type(cp)
FN ed_multi_type
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov r12d, edi               # cp
    mov edi, r12d
    lea rsi, [rsp]
    call utf8_encode
    mov r13, rax                # utf8 len

    mov rdi, rbx
    call cursors_collect_all
    mov r14, rax                # count
    mov r15, rdx                # ptr
    test r14, r14
    jz 9f

    # Group contiguous typing within 1500ms together
    call time_ms
    mov rcx, rax
    sub rcx, [rbx + DOC_lastedit]
    cmp qword ptr [rbx + DOC_lastkind], EK_TYPE
    jne .Lmt_new_group
    cmp rcx, 1500
    ja .Lmt_new_group
    cmp byte ptr [rsp], ' '
    je .Lmt_new_group
    cmp byte ptr [rsp], 10
    je .Lmt_new_group
    or dword ptr [rbx + DOC_flags], 1
    jmp .Lmt_group_ready

.Lmt_new_group:
    inc qword ptr [rbx + DOC_group]
    or dword ptr [rbx + DOC_flags], 1

.Lmt_group_ready:
    mov r12, r14
.Lmt_loop:
    test r12, r12
    jz .Lmt_done
    dec r12
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov rsi, r8
    cmp r9, rsi
    cmovb rsi, r9               # start
    mov rdi, r8
    cmp r9, rdi
    cmova rdi, r9               # end
    mov rcx, rdi
    sub rcx, rsi                # sel_len

    test rcx, rcx
    jz 1f
    push rsi
    push rcx
    mov rdi, rbx
    mov rdx, rcx
    mov ecx, EK_TYPE
    call doc_delete
    pop rcx
    pop rsi
1:  push rsi
    push rcx
    mov rdi, rbx
    lea rdx, [rsp + 16]
    mov rcx, r13
    mov r8d, EK_TYPE
    call doc_insert
    pop rcx
    pop rsi

    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, rsi
    add rdx, r13
    mov [rax + CURS_anchor], rdx
    mov rdx, r13
    sub rdx, rcx
    mov [rax + CURS_prefx], rdx
    jmp .Lmt_loop

.Lmt_done:
    and dword ptr [rbx + DOC_flags], -2
    mov qword ptr [rbx + DOC_lastkind], EK_TYPE
    call time_ms
    mov [rbx + DOC_lastedit], rax

    xor rsi, rsi
    xor r12, r12
.Lmt_shift:
    cmp r12, r14
    jae .Lmt_writeback
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rax + CURS_anchor]
    add rdx, rsi
    mov [rax + CURS_cur], rdx
    mov [rax + CURS_anchor], rdx
    add rsi, [rax + CURS_prefx]
    mov qword ptr [rax + CURS_prefx], -1
    inc r12
    jmp .Lmt_shift

.Lmt_writeback:
    mov rax, [r15 + CURS_cur]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov qword ptr [rbx + DOC_prefx], -1
    lea rax, [r14 - 1]
    mov [rbx + DOC_cursors + VEC_len], rax
    cmp r14, 1
    jbe 2f
    mov rdi, [rbx + DOC_cursors + VEC_ptr]
    lea rsi, [r15 + CURS_SIZE]
    imul rdx, rax, CURS_SIZE
    call memcpy
2:  mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ed_multi_backspace(word)
FN ed_multi_backspace
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov [rsp], edi              # word

    mov rdi, rbx
    call cursors_collect_all
    mov r14, rax                # count
    mov r15, rdx                # ptr
    test r14, r14
    jz 9f

    mov rdi, rbx
    call doc_begin_group

    mov r12, r14
.Lmb_loop:
    test r12, r12
    jz .Lmb_done
    dec r12
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov rsi, r8
    cmp r9, rsi
    cmovb rsi, r9               # start
    mov rdi, r8
    cmp r9, rdi
    cmova rdi, r9               # end
    mov rcx, rdi
    sub rcx, rsi                # sel_len

    test rcx, rcx
    jz 1f
    push rsi
    push rcx
    mov rdi, rbx
    mov rdx, rcx
    mov ecx, EK_BACK
    call doc_delete
    pop rcx
    pop rsi
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov [rax + CURS_anchor], rsi
    neg rcx
    mov [rax + CURS_prefx], rcx
    jmp .Lmb_loop

1:  test rsi, rsi
    jz 2f
    mov [rsp + 8], rsi
    cmp dword ptr [rsp], 0
    je 11f
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call doc_word_left
    jmp 12f
11: mov rdi, rbx
    mov rsi, [rsp + 8]
    call doc_prev_char
12: mov r13, rax                # prev pos
    mov rdx, [rsp + 8]
    sub rdx, r13                # del len
    mov rdi, rbx
    mov rsi, r13
    mov ecx, EK_BACK
    push rdx
    call doc_delete
    pop rdx
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov [rax + CURS_anchor], r13
    neg rdx
    mov [rax + CURS_prefx], rdx
    jmp .Lmb_loop

2:  imul rax, r12, CURS_SIZE
    add rax, r15
    mov qword ptr [rax + CURS_anchor], 0
    mov qword ptr [rax + CURS_prefx], 0
    jmp .Lmb_loop

.Lmb_done:
    mov rdi, rbx
    call doc_end_group

    xor rsi, rsi
    xor r12, r12
.Lmb_shift:
    cmp r12, r14
    jae .Lmb_writeback
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rax + CURS_anchor]
    add rdx, rsi
    mov [rax + CURS_cur], rdx
    mov [rax + CURS_anchor], rdx
    add rsi, [rax + CURS_prefx]
    mov qword ptr [rax + CURS_prefx], -1
    inc r12
    jmp .Lmb_shift

.Lmb_writeback:
    mov rax, [r15 + CURS_cur]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov qword ptr [rbx + DOC_prefx], -1
    lea rax, [r14 - 1]
    mov [rbx + DOC_cursors + VEC_len], rax
    cmp r14, 1
    jbe 3f
    mov rdi, [rbx + DOC_cursors + VEC_ptr]
    lea rsi, [r15 + CURS_SIZE]
    imul rdx, rax, CURS_SIZE
    call memcpy
3:  mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ed_multi_delete_fwd(word)
FN ed_multi_delete_fwd
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov [rsp], edi              # word

    mov rdi, rbx
    call cursors_collect_all
    mov r14, rax                # count
    mov r15, rdx                # ptr
    test r14, r14
    jz 9f

    mov rdi, rbx
    call doc_begin_group

    mov r12, r14
.Lmdf_loop:
    test r12, r12
    jz .Lmdf_done
    dec r12
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov rsi, r8
    cmp r9, rsi
    cmovb rsi, r9               # start
    mov rdi, r8
    cmp r9, rdi
    cmova rdi, r9               # end
    mov rcx, rdi
    sub rcx, rsi                # sel_len

    test rcx, rcx
    jz 1f
    push rsi
    push rcx
    mov rdi, rbx
    mov rdx, rcx
    mov ecx, EK_DEL
    call doc_delete
    pop rcx
    pop rsi
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov [rax + CURS_anchor], rsi
    neg rcx
    mov [rax + CURS_prefx], rcx
    jmp .Lmdf_loop

1:  mov [rsp + 8], rsi
    mov rdi, rbx
    call doc_len
    cmp [rsp + 8], rax
    jae 2f
    cmp dword ptr [rsp], 0
    je 11f
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call doc_word_right
    jmp 12f
11: mov rdi, rbx
    mov rsi, [rsp + 8]
    call doc_next_char
12: mov r13, rax                # next pos
    mov rdx, r13
    sub rdx, [rsp + 8]          # del len
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov ecx, EK_DEL
    push rdx
    call doc_delete
    pop rdx
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rcx, [rsp + 8]
    mov [rax + CURS_anchor], rcx
    neg rdx
    mov [rax + CURS_prefx], rdx
    jmp .Lmdf_loop

2:  imul rax, r12, CURS_SIZE
    add rax, r15
    mov rcx, [rsp + 8]
    mov [rax + CURS_anchor], rcx
    mov qword ptr [rax + CURS_prefx], 0
    jmp .Lmdf_loop

.Lmdf_done:
    mov rdi, rbx
    call doc_end_group

    xor rsi, rsi
    xor r12, r12
.Lmdf_shift:
    cmp r12, r14
    jae .Lmdf_writeback
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rax + CURS_anchor]
    add rdx, rsi
    mov [rax + CURS_cur], rdx
    mov [rax + CURS_anchor], rdx
    add rsi, [rax + CURS_prefx]
    mov qword ptr [rax + CURS_prefx], -1
    inc r12
    jmp .Lmdf_shift

.Lmdf_writeback:
    mov rax, [r15 + CURS_cur]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov qword ptr [rbx + DOC_prefx], -1
    lea rax, [r14 - 1]
    mov [rbx + DOC_cursors + VEC_len], rax
    cmp r14, 1
    jbe 3f
    mov rdi, [rbx + DOC_cursors + VEC_ptr]
    lea rsi, [r15 + CURS_SIZE]
    imul rdx, rax, CURS_SIZE
    call memcpy
3:  mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ed_multi_newline()
FN ed_multi_newline
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f

    mov rdi, rbx
    call cursors_collect_all
    mov r14, rax                # count
    mov r15, rdx                # ptr
    test r14, r14
    jz 9f

    mov rdi, rbx
    call doc_begin_group

    mov r12, r14
.Lmn_loop:
    test r12, r12
    jz .Lmn_done
    dec r12
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov rsi, r8
    cmp r9, rsi
    cmovb rsi, r9               # start
    mov rdi, r8
    cmp r9, rdi
    cmova rdi, r9               # end
    mov rcx, rdi
    sub rcx, rsi                # sel_len

    test rcx, rcx
    jz 1f
    push rsi
    push rcx
    mov rdi, rbx
    mov rdx, rcx
    mov ecx, EK_OTHER
    call doc_delete
    pop rcx
    pop rsi
1:  push rsi
    push rcx
    mov byte ptr [rsp + 16], 10 # newline '\n'
    mov rdi, rbx
    lea rdx, [rsp + 16]
    mov rcx, 1
    mov r8d, EK_OTHER
    call doc_insert
    pop rcx                     # sel_len
    pop rsi                     # start

    imul rax, r12, CURS_SIZE
    add rax, r15
    lea rdx, [rsi + 1]
    mov [rax + CURS_anchor], rdx # local pos
    mov rdx, 1
    sub rdx, rcx                # delta = 1 - sel_len
    mov [rax + CURS_prefx], rdx
    jmp .Lmn_loop

.Lmn_done:
    mov rdi, rbx
    call doc_end_group

    xor rsi, rsi
    xor r12, r12
.Lmn_shift:
    cmp r12, r14
    jae .Lmn_writeback
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rax + CURS_anchor]
    add rdx, rsi
    mov [rax + CURS_cur], rdx
    mov [rax + CURS_anchor], rdx
    add rsi, [rax + CURS_prefx]
    mov qword ptr [rax + CURS_prefx], -1
    inc r12
    jmp .Lmn_shift

.Lmn_writeback:
    mov rax, [r15 + CURS_cur]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov qword ptr [rbx + DOC_prefx], -1
    lea rax, [r14 - 1]
    mov [rbx + DOC_cursors + VEC_len], rax
    cmp r14, 1
    jbe 2f
    mov rdi, [rbx + DOC_cursors + VEC_ptr]
    lea rsi, [r15 + CURS_SIZE]
    imul rdx, rax, CURS_SIZE
    call memcpy
2:  mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# ed_multi_paste(ptr, len)
FN ed_multi_paste
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov [rsp], rdi              # paste ptr
    mov [rsp + 8], rsi          # paste len
    test rsi, rsi
    jz 9f

    mov rdi, rbx
    call cursors_collect_all
    mov r14, rax                # count
    mov r15, rdx                # ptr
    test r14, r14
    jz 9f

    mov rdi, rbx
    call doc_begin_group

    mov r12, r14
.Lmp_loop:
    test r12, r12
    jz .Lmp_done
    dec r12
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov r8, [rax + CURS_cur]
    mov r9, [rax + CURS_anchor]
    mov rsi, r8
    cmp r9, rsi
    cmovb rsi, r9               # start
    mov rdi, r8
    cmp r9, rdi
    cmova rdi, r9               # end
    mov rcx, rdi
    sub rcx, rsi                # sel_len

    test rcx, rcx
    jz 1f
    push rsi
    push rcx
    mov rdi, rbx
    mov rdx, rcx
    xor ecx, ecx
    call doc_delete
    pop rcx
    pop rsi
1:  push rsi
    push rcx
    mov rdi, rbx
    mov rdx, [rsp + 16]         # paste ptr
    mov rcx, [rsp + 24]         # paste len
    xor r8d, r8d
    call doc_insert
    pop rcx                     # sel_len
    pop rsi                     # start

    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rsp + 8]          # paste len
    lea r8, [rsi + rdx]
    mov [rax + CURS_anchor], r8 # local pos
    sub rdx, rcx                # paste_len - sel_len
    mov [rax + CURS_prefx], rdx
    jmp .Lmp_loop

.Lmp_done:
    mov rdi, rbx
    call doc_end_group

    xor rsi, rsi
    xor r12, r12
.Lmp_shift:
    cmp r12, r14
    jae .Lmp_writeback
    imul rax, r12, CURS_SIZE
    add rax, r15
    mov rdx, [rax + CURS_anchor]
    add rdx, rsi
    mov [rax + CURS_cur], rdx
    mov [rax + CURS_anchor], rdx
    add rsi, [rax + CURS_prefx]
    mov qword ptr [rax + CURS_prefx], -1
    inc r12
    jmp .Lmp_shift

.Lmp_writeback:
    mov rax, [r15 + CURS_cur]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov qword ptr [rbx + DOC_prefx], -1
    lea rax, [r14 - 1]
    mov [rbx + DOC_cursors + VEC_len], rax
    cmp r14, 1
    jbe 2f
    mov rdi, [rbx + DOC_cursors + VEC_ptr]
    lea rsi, [r15 + CURS_SIZE]
    imul rdx, rax, CURS_SIZE
    call memcpy
2:  mov rdi, rbx
    call cursors_normalize
    call ed_touch
9:  EPILOGUE

# copy_multi_to_clip: copies all selections to clipboard separated by newlines
copy_multi_to_clip:
    PROLOGUE
    mov rbx, rdi
    call cursors_collect_all
    mov r12, rax                # count
    mov r13, rdx                # ptr
    test r12, r12
    jz .Lcmc_none
    lea rdi, [rip + clip_sb]
    call sb_clear
    xor r14, r14                # i
.Lcmc_loop:
    cmp r14, r12
    jae .Lcmc_done
    imul rax, r14, CURS_SIZE
    add rax, r13
    mov rsi, [rax + CURS_cur]
    mov rdx, [rax + CURS_anchor]
    mov r8, rsi
    cmp rdx, r8
    cmovb r8, rdx               # start
    mov r9, rsi
    cmp rdx, r9
    cmova r9, rdx               # end
    mov r15, r9
    sub r15, r8                 # len
    test r15, r15
    jz .Lcmc_next
    cmp qword ptr [rip + clip_sb + SB_len], 0
    jz 2f
    lea rdi, [rip + clip_sb]
    mov esi, 10
    call sb_push_byte
2:  lea rdi, [rip + clip_sb]
    mov rsi, r15
    call sb_reserve
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r8
    mov rdx, r15
    call doc_copy
    add [rip + clip_sb + SB_len], r15
.Lcmc_next:
    inc r14
    jmp .Lcmc_loop
.Lcmc_done:
    cmp qword ptr [rip + clip_sb + SB_len], 0
    jz .Lcmc_none
    mov rdi, [rip + clip_sb + SB_ptr]
    mov rsi, [rip + clip_sb + SB_len]
    PCALL P_clip_set
    xor eax, eax
    mov [rip + g_clip_line], eax
    EPILOGUE
.Lcmc_none:
    xor eax, eax
    EPILOGUE

# ed_record_caret(x, y)
ed_record_caret:
    mov ecx, [rip + g_carets_cnt]
    cmp ecx, 1024
    jge 1f
    lea r8, [rip + g_carets_buf]
    mov [r8 + rcx*8], edi
    mov [r8 + rcx*8 + 4], esi
    inc dword ptr [rip + g_carets_cnt]
1:  ret

# find_in_doc(doc, needle_len, from, needle_pos_in_doc) -> match pos or -1 (wraps)
find_in_doc:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rdi, [r12 + 1]
    call mem_alloc
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    mov rcx, r15
    call doc_copy
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    mov r8d, 1
    call doc_search
    mov r12, rax
    mov rdi, r15
    call mem_free
    mov rax, r12
    EPILOGUE

# doc_search(doc, needle, nlen, from, case_sensitive) -> pos or -1 ; searches forward, wraps
FN doc_search
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8d
    test r13, r13
    jz .Lds_none
    mov rdi, rbx
    call doc_len
    mov r15, rax
    mov rdi, rbx
    call doc_contiguous
    mov [rsp + 8], rax
    # search [from, len)
    mov rdi, rax
    add rdi, r14
    mov rsi, r15
    sub rsi, r14
    jb .Lds_wrap
    mov rdx, r12
    mov rcx, r13
    cmp dword ptr [rsp], 0
    je 1f
    call str_find
    jmp 2f
1:  call str_ifind
2:  test rax, rax
    js .Lds_wrap
    add rax, r14
    EPILOGUE
.Lds_wrap:
    mov rdi, [rsp + 8]
    mov rsi, r14
    add rsi, r13
    cmp rsi, r15
    cmova rsi, r15
    mov rdx, r12
    mov rcx, r13
    cmp dword ptr [rsp], 0
    je 3f
    call str_find
    EPILOGUE
3:  call str_ifind
    EPILOGUE
.Lds_none:
    mov rax, -1
    EPILOGUE

FN cmd_duplicate_line
    READONLY_RET
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call sel_lines
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_end
    mov r15, rax
    # text = "\n" + lines, inserted at end of last line
    mov rdx, r15
    sub rdx, r14
    lea rdi, [rdx + 2]
    call mem_alloc
    mov [rsp], rax
    mov byte ptr [rax], 10
    lea rcx, [rax + 1]
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    sub rdx, r14
    call doc_copy
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rsp]
    mov rcx, r15
    sub rcx, r14
    inc rcx
    mov [rsp + 8], rcx
    xor r8d, r8d
    call doc_insert
    # onto the copy; the insert already moved what was past the end of the last line
    mov rax, [rsp + 8]
    cmp [rbx + DOC_cur], r15
    ja 1f
    add [rbx + DOC_cur], rax
1:  cmp [rbx + DOC_anchor], r15
    ja 2f
    add [rbx + DOC_anchor], rax
2:  mov rdi, [rsp]
    call mem_free
    call ed_touch
9:  EPILOGUE

FN cmd_delete_line
    READONLY_RET
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call sel_lines
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    lea rsi, [r13 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 1f
    mov rdi, rbx
    call doc_line_start
    mov r15, rax
    jmp 2f
1:  # last line: also remove the preceding newline
    mov rdi, rbx
    call doc_len
    mov r15, rax
    test r14, r14
    jz 2f
    dec r14
2:  mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    sub rdx, r14
    xor ecx, ecx
    call doc_delete
    mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rbx + DOC_prefx]
    cmp rdx, -1
    jne 3f
    xor edx, edx
3:  call doc_pos_at_col
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    call ed_touch
9:  EPILOGUE

# ed_move_lines(dir): move selected lines up (-1) or down (1)
FN ed_move_lines
    READONLY_RET
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Lml_ret
    mov [rsp + 40], edi
    mov rdi, rbx
    call sel_lines
    mov r12, rax                # first
    mov r13, rdx                # last
    cmp dword ptr [rsp + 40], 0
    jg 1f
    test r12, r12
    jz .Lml_ret
    lea r14, [r12 - 1]          # other line (above)
    jmp 2f
1:  lea r14, [r13 + 1]
    cmp r14, [rbx + DOC_nlines]
    jae .Lml_ret
2:  # block text [start(first), end(last)) and other line text
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp], rax              # block start
    mov rdi, rbx
    mov rsi, r13
    call doc_line_end
    mov [rsp + 8], rax          # block end
    mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, r14
    call doc_line_end
    mov [rsp + 24], rax         # other end
    mov rdi, rbx
    call doc_begin_group
    mov r15, [rbx + DOC_cur]
    mov rax, [rbx + DOC_anchor]
    mov [rsp + 32], rax
    # remove the other line (with its separating newline) and re-insert it on the other side
    mov rdx, [rsp + 24]
    sub rdx, [rsp + 16]         # other length
    push rdx
    push rdx
    lea rdi, [rdx + 2]
    call mem_alloc
    mov r14, rax
    pop rdx
    pop rdx
    mov [rsp + 24], rdx         # reuse: other length
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rcx, r14
    call doc_copy
    cmp dword ptr [rsp + 40], 0
    jg 3f
    # up: delete "other\n" before the block, insert "\nother" after the block
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    inc rdx
    xor ecx, ecx
    call doc_delete
    lea rdi, [r14 + 1]
    mov rsi, r14
    mov rdx, [rsp + 24]
    call memmove
    mov byte ptr [r14], 10
    mov rsi, [rsp + 8]
    sub rsi, [rsp + 24]
    dec rsi
    mov rdi, rbx
    mov rdx, r14
    mov rcx, [rsp + 24]
    inc rcx
    xor r8d, r8d
    call doc_insert
    mov rax, [rsp + 24]
    inc rax
    sub r15, rax
    sub [rsp + 32], rax
    jmp 4f
3:  # down: delete "\nother" after the block, insert "other\n" before the block
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 24]
    inc rdx
    xor ecx, ecx
    call doc_delete
    mov rax, [rsp + 24]
    mov byte ptr [r14 + rax], 10
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, r14
    mov rcx, [rsp + 24]
    inc rcx
    xor r8d, r8d
    call doc_insert
    mov rax, [rsp + 24]
    inc rax
    add r15, rax
    add [rsp + 32], rax
4:  # A selection ending at the next line's start includes a newline. At EOF,
    # the moved block has no following newline, so that endpoint must stop there.
    mov rdi, rbx
    call doc_len
    cmp r15, rax
    cmova r15, rax
    mov [rbx + DOC_cur], r15
    mov rcx, [rsp + 32]
    cmp rcx, rax
    cmova rcx, rax
    mov [rbx + DOC_anchor], rcx
    mov rdi, rbx
    call doc_end_group
    mov rdi, r14
    call mem_free
    call ed_touch
.Lml_ret:
    EPILOGUE

# toggle line comments using the grammar's comment token
FN cmd_toggle_comment
    READONLY_RET
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Ltc_ret
    mov rax, [rbx + DOC_lang]
    test rax, rax
    jz .Ltc_ret
    mov rcx, [rax + GR_commentlen]
    test rcx, rcx
    jz .Ltc_ret
    mov rdx, [rax + GR_comment]
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov rdi, rbx
    call sel_lines
    mov r12, rax
    mov r13, rdx
    # all non-blank lines commented? -> uncomment
    mov r14, r12
    mov dword ptr [rsp + 16], 1
    mov qword ptr [rsp + 24], 1000000     # min indent columns
1:  cmp r14, r13
    ja 3f
    mov rdi, rbx
    mov rsi, r14
    call line_indent
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    call doc_line_text
    cmp r15, rdx
    je 2f                       # blank line
    cmp r15, [rsp + 24]
    jae 11f
    mov [rsp + 24], r15
11: lea rdi, [rax + r15]
    mov rsi, rdx
    sub rsi, r15
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call str_starts
    test eax, eax
    jnz 2f
    mov dword ptr [rsp + 16], 0
2:  inc r14
    jmp 1b
3:  mov rdi, rbx
    call doc_begin_group
    mov r14, r12
.Ltc_line:
    cmp r14, r13
    ja .Ltc_done
    mov rdi, rbx
    mov rsi, r14
    call line_indent
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    call doc_line_text
    cmp r15, rdx
    je .Ltc_next
    mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    cmp dword ptr [rsp + 16], 0
    je .Ltc_add
    # remove token and one following space
    add rax, r15
    mov r15, rax
    mov rdx, [rsp + 8]
    lea rsi, [r15 + rdx]
    mov rdi, rbx
    push rdx
    push rdx
    call doc_byte
    pop rdx
    pop rdx
    cmp al, ' '
    jne 4f
    inc rdx
4:  mov rdi, rbx
    mov rsi, r15
    xor ecx, ecx
    call doc_delete
    jmp .Ltc_next
.Ltc_add:
    add rax, [rsp + 24]
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    lea rdx, [rip + .Lspace]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    xor r8d, r8d
    call doc_insert
.Ltc_next:
    inc r14
    jmp .Ltc_line
.Ltc_done:
    mov rdi, rbx
    call doc_end_group
    call ed_touch
.Ltc_ret:
    EPILOGUE

FN cmd_undo
    READONLY_RET
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    call doc_undo
    jmp ed_touch
1:  ret

FN cmd_redo
    READONLY_RET
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    call doc_redo
    jmp ed_touch
1:  ret

# ---- drawing ----

# editor_metrics(doc) -> eax gutter width
editor_gutter:
    cmp qword ptr [rdi + DOC_diff], 0
    jne diffview_gutter
    cmp dword ptr [rip + cfg_line_numbers], 0
    je 2f
    mov rax, [rdi + DOC_nlines]
    mov ecx, 1
    mov r8d, 10
1:  cmp rax, r8
    jb 3f
    xor edx, edx
    div r8
    inc ecx
    jmp 1b
3:  cmp ecx, 3
    jge 4f
    mov ecx, 3
4:  imul ecx, [rip + g_cw]
    lea eax, [rcx + 0]
    add eax, [rip + g_mt + 4*MI_24]
    add eax, [rip + g_mt + 4*MI_8]
    ret
2:  M eax, MI_16
    ret

# clamp_scroll(doc)
clamp_scroll:
    mov rax, [rdi + DOC_nlines]
    cmp dword ptr [rip + cfg_scroll_past_end], 0
    jne 1f
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne wrap_clamp
    # last line at the bottom
    mov ecx, [rip + g_ed_h]
    xor edx, edx
    push rax
    mov eax, ecx
    mov ecx, [rip + g_lh]
    div ecx
    mov rcx, rax
    pop rax
    sub rax, rcx
    jns 2f
    xor eax, eax
    jmp 2f
1:  dec rax
2:  shl rax, 8
    cmp [rdi + DOC_scrolly], rax
    jle 3f
    mov [rdi + DOC_scrolly], rax
3:  cmp qword ptr [rdi + DOC_scrolly], 0
    jge 4f
    mov qword ptr [rdi + DOC_scrolly], 0
4:  cmp qword ptr [rdi + DOC_scrollx], 0
    jge 5f
    mov qword ptr [rdi + DOC_scrollx], 0
5:  ret

# reveal(doc): scroll so the cursor is visible
reveal:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r12, rax                # line
    mov eax, [rip + g_ed_h]
    xor edx, edx
    div dword ptr [rip + g_lh]
    mov r13, rax                # visible lines
    cmp r13, 3
    jl 1f
    sub r13, 2                  # keep a line of margin
1:  mov rax, r12
    dec rax
    jns 2f
    xor eax, eax
2:  shl rax, 8
    cmp [rbx + DOC_scrolly], rax
    jle 3f
    mov [rbx + DOC_scrolly], rax
3:  mov rax, r12
    sub rax, r13
    jns 4f
    xor eax, eax
4:  shl rax, 8
    cmp [rbx + DOC_scrolly], rax
    jge 5f
    mov [rbx + DOC_scrolly], rax
5:  # horizontal
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
    imul eax, [rip + g_cw]
    mov r14d, eax
    mov rdi, rbx
    call editor_gutter
    mov ecx, [rip + g_ed_w]
    sub ecx, eax
    sub ecx, [rip + g_mt + 4*MI_32]
    mov eax, r14d
    sub rax, [rbx + DOC_scrollx]
    cmp eax, ecx
    jle 6f
    mov eax, r14d
    sub eax, ecx
    mov [rbx + DOC_scrollx], rax
6:  movsxd rax, r14d
    cmp rax, [rbx + DOC_scrollx]
    jge 7f
    # going left: back to column 0 when the cursor fits, else center it
    movsxd rdx, ecx
    xor esi, esi
    cmp rax, rdx
    jl 61f
    sar rdx, 1
    mov rsi, rax
    sub rsi, rdx
61: mov [rbx + DOC_scrollx], rsi
7:  mov rdi, rbx
    call clamp_scroll
    EPILOGUE

# pos_at_point(doc, px, py) -> pos
pos_at_point:
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne wrap_pos_at
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    # line
    mov eax, r13d
    sub eax, [rip + g_ed_y]
    # g_lh is 32 bits: a 64-bit multiply would take g_cw along as its high half
    movsxd rcx, dword ptr [rip + g_lh]
    imul rcx, [rbx + DOC_scrolly]
    sar rcx, 8
    add eax, ecx
    jns 1f
    xor eax, eax
1:  xor edx, edx
    div dword ptr [rip + g_lh]
    mov r14, rax
    cmp r14, [rbx + DOC_nlines]
    jb 2f
    mov rdi, rbx
    call doc_len
    jmp 9f
2:  # column
    mov eax, r12d
    sub eax, [rip + g_ed_tx]
    add eax, [rbx + DOC_scrollx]
    mov ecx, [rip + g_cw]
    shr ecx, 1
    add eax, ecx
    jns 3f
    xor eax, eax
3:  xor edx, edx
    div dword ptr [rip + g_cw]
    mov rdi, rbx
    mov rsi, r14
    mov edx, eax
    call doc_pos_at_col
9:  EPILOGUE

# drag_scroll(rbx doc, esi px)
drag_scroll:
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 1f
    mov rdi, rbx
    jmp scroll_by_px
1:  movsxd rax, esi
    shl rax, 8
    cqo
    movsxd rcx, dword ptr [rip + g_lh]
    idiv rcx
    add [rbx + DOC_scrolly], rax
    mov dword ptr [rip + g_dirty], 1
    ret

# draw_wrapped(doc): visible lines as wrapped rows
draw_wrapped:
    PROLOGUE 64
    mov rbx, rdi
    mov rdi, rbx
    call vim_sel
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov [rsp + 8], rax          # cursor line
    mov rdi, rbx
    call git_doc_marks
    mov [rsp], rax
    mov rdi, rbx
    call top_offset
    mov r13d, [rip + g_ed_y]
    sub r13d, eax               # y of the first row of the top line
    mov r12, [rbx + DOC_scrolly]
    shr r12, 8
.Ldw_line:
    cmp r12, [rbx + DOC_nlines]
    jae .Ldw_ret
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r13d, eax
    jge .Ldw_ret
    mov rdi, rbx
    mov rsi, r12
    call line_breaks
    mov r14d, eax               # rows
    # current line highlight across all its rows
    cmp dword ptr [rip + cfg_highlight_line], 0
    je 12f
    cmp r12, [rsp + 8]
    jne 12f
    mov rax, [rsp + 16]
    cmp rax, [rsp + 24]
    jne 12f
    mov edi, [rip + g_ed_x]
    mov esi, r13d
    mov edx, [rip + g_ed_w]
    mov ecx, [rip + g_lh]
    imul ecx, r14d
    COLOR r8d, T_LINE_HL
    call gfx_fill
12: mov rdi, r12
    mov esi, r13d
    mov edx, [rip + g_lh]
    imul edx, r14d
    call draw_disk_range
    # line number on the first row
    cmp qword ptr [rbx + DOC_diff], 0
    jne .Ldw_diff
    cmp dword ptr [rip + cfg_line_numbers], 0
    je 1f
    lea rdi, [rsp + 40]
    lea rsi, [r12 + 1]
    call fmt_u64
    mov r15, rax
    lea rdi, [rip + g_face_code]
    lea rsi, [rsp + 40]
    mov rdx, rax
    call text_width
    mov esi, [rip + g_ed_tx]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_16]
    COLOR r9d, T_LINENO
    cmp r12, [rsp + 8]
    jne 11f
    COLOR r9d, T_LINENO_ACTIVE
11: lea rdi, [rip + g_face_code]
    mov edx, r13d
    add edx, [rip + g_base]
    lea rcx, [rsp + 40]
    mov r8, r15
    call text_draw
1:  mov rax, [rsp]
    test rax, rax
    jz 13f
    movzx edi, byte ptr [rax + r12]
    test edi, edi
    jz 13f
    mov esi, r13d
    mov edx, [rip + g_lh]
    imul edx, r14d
    call mark_draw
13: xor r15d, r15d              # row
.Ldw_row:
    cmp r15d, r14d
    jae .Ldw_next
    mov eax, r13d
    add eax, [rip + g_lh]
    cmp eax, [rip + g_ed_y]
    jl .Ldw_rownext
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r13d, eax
    jge .Ldw_ret
    lea rax, [rip + wb_starts]
    mov ecx, [rax + r15*4]
    mov [rip + dl_from], ecx
    mov ecx, [rax + r15*4 + 4]
    mov [rip + dl_to], ecx
    lea eax, [r15 + 1]
    xor ecx, ecx
    cmp eax, r14d
    sete cl
    mov [rip + dl_last], ecx
    # draw_line re-reads the line text, keep the row table
    mov edi, [rip + g_ed_tx]
    sub edi, [rip + g_mt + 4*MI_4]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_x]
    add edx, [rip + g_ed_w]
    sub edx, edi
    mov ecx, [rip + g_ed_h]
    call gfx_clip_push
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    lea rcx, [rsp + 16]
    call draw_line
    call gfx_clip_pop
.Ldw_rownext:
    add r13d, [rip + g_lh]
    inc r15d
    jmp .Ldw_row
.Ldw_next:
    inc r12
    jmp .Ldw_line
.Ldw_diff:
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov ecx, [rip + g_lh]
    imul ecx, r14d
    call diffview_line
    test eax, eax
    jz 13b
    mov eax, [rip + g_lh]
    imul eax, r14d
    add r13d, eax
    jmp .Ldw_next
.Ldw_ret:
    mov dword ptr [rip + dl_from], 0
    mov dword ptr [rip + dl_to], -1
    mov dword ptr [rip + dl_last], 1
    EPILOGUE

# mark_draw(mark, y, h): git change bar left of the text
mark_draw:
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, [rip + g_ed_tx]
    sub r14d, [rip + g_mt + 4*MI_12]
    test ebx, GM_ADD | GM_MOD
    jz 1f
    COLOR r8d, T_GIT_ADD
    test ebx, GM_MOD
    jz 11f
    COLOR r8d, T_GIT_MOD
11: mov edi, r14d
    mov esi, r12d
    M edx, MI_3
    mov ecx, r13d
    call gfx_fill
1:  test ebx, GM_DELUP
    jz 2f
    mov esi, r12d
    call del_wedge
2:  test ebx, GM_DELDOWN
    jz 9f
    lea esi, [r12 + r13]
    call del_wedge
9:  EPILOGUE
# del_wedge(y in esi): a small triangle pointing into the text where lines were deleted (r14d x)
del_wedge:
    push rbx
    push r12
    push r15
    mov r12d, esi
    M r15d, MI_4
    xor ebx, ebx
1:  cmp ebx, r15d
    jge 2f
    mov edi, r14d
    add edi, ebx
    mov ecx, r15d
    sub ecx, ebx                # half height of this column
    mov esi, r12d
    sub esi, ecx
    add ecx, ecx
    mov edx, 1
    COLOR r8d, T_GIT_DEL
    call gfx_fill
    inc ebx
    jmp 1b
2:  pop r15
    pop r12
    pop rbx
    ret

# editor_draw(x, y, w, h)
FN editor_draw
    PROLOGUE 112
    mov rbx, [rip + g_doc]
    mov [rip + g_ed_x], edi
    mov [rip + g_ed_y], esi
    mov [rip + g_ed_w], edx
    mov [rip + g_ed_h], ecx
    # background
    COLOR r8d, T_BG
    call gfx_fill
    test rbx, rbx
    jz .Led_ret
    call disk_colors
    mov edi, [rip + g_ed_x]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_w]
    mov ecx, [rip + g_ed_h]
    call gfx_clip_push
    call disk_warning
    mov rdi, rbx
    call editor_gutter
    mov [rsp], eax              # gutter width
    add eax, [rip + g_ed_x]
    mov [rip + g_ed_tx], eax
    # ---- input ----
    mov edi, [rip + g_ed_x]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_w]
    mov ecx, [rip + g_ed_h]
    call ui_in
    test eax, eax
    jz .Led_noinput
    mov eax, [rip + g_mx]
    cmp eax, [rip + g_ed_tx]
    jl 1f
    mov dword ptr [rip + g_cursor], CUR_TEXT
1:  # wheel
    mov eax, [rip + g_scroll_y]
    test eax, eax
    jz 2f
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 11f
    mov rdi, rbx
    mov esi, eax
    call scroll_by_px
    jmp 2f
11: movsxd rax, eax
    shl rax, 8
    cqo
    movsxd rcx, dword ptr [rip + g_lh]
    idiv rcx
    add [rbx + DOC_scrolly], rax
    mov dword ptr [rip + g_dirty], 1
2:  mov eax, [rip + g_scroll_x]
    test eax, eax
    jz 3f
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne 3f
    movsxd rax, eax
    add [rbx + DOC_scrollx], rax
    mov dword ptr [rip + g_dirty], 1
3:  # right click: menu (moves the cursor unless clicking inside the selection)
    test dword ptr [rip + g_pressed], 1 << BTN_RIGHT
    jz 31f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call vim_export
    mov rdi, rbx
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call pos_at_point
    mov r12, rax
    mov rdi, rbx
    call ed_sel
    cmp r12, rax
    jb 32f
    cmp r12, rdx
    jbe 33f
32: mov [rbx + DOC_cur], r12
    mov [rbx + DOC_anchor], r12
    mov qword ptr [rbx + DOC_cursors + VEC_len], 0
33: lea rdi, [rip + editor_menu]
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call ctx_menu_open
    jmp .Led_noinput
31: # mouse press in the text area
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz .Led_noinput
    mov eax, [rip + g_ed_x]
    add eax, [rip + g_ed_w]
    sub eax, [rip + g_mt + 4*MI_12]
    cmp [rip + g_mx], eax
    jge .Led_noinput
    mov edi, ID_EDITOR
    mov [rip + g_active], edi
    mov dword ptr [rip + g_dragging], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call vim_click
    mov rdi, rbx
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call pos_at_point
    mov r12, rax
    test dword ptr [rip + g_mods], MOD_ALT
    jz 311f
    # Alt + Click: add cursor at clicked position
    mov dword ptr [rip + g_dragging], 0
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r12
    mov rcx, -1
    call cursors_add
    mov rdi, rbx
    call cursors_normalize
    call ed_touch
    mov dword ptr [rip + g_reveal], 0
    jmp .Led_noinput
311:
    test dword ptr [rip + g_mods], MOD_SHIFT
    jnz 312f
    mov qword ptr [rbx + DOC_cursors + VEC_len], 0
312:
    mov eax, [rip + g_clicks]
    cmp eax, 2
    je .Led_dbl
    cmp eax, 3
    je .Led_tri
    mov rdi, rbx
    mov rsi, r12
    mov edx, [rip + g_mods]
    and edx, MOD_SHIFT
    call ed_set_cursor
    mov qword ptr [rbx + DOC_prefx], -1
    mov dword ptr [rip + g_reveal], 0
    jmp .Led_noinput
.Led_dbl:
    mov qword ptr [rbx + DOC_cursors + VEC_len], 0
    mov dword ptr [rip + g_dragging], 0
    mov rdi, rbx
    mov rsi, r12
    call word_at
    mov [rbx + DOC_anchor], rax
    mov [rbx + DOC_cur], rdx
    mov [rip + sel_word_a], rax
    mov [rip + sel_word_b], rdx
    call ed_touch
    mov dword ptr [rip + g_reveal], 0
    jmp .Led_noinput
.Led_tri:
    mov qword ptr [rbx + DOC_cursors + VEC_len], 0
    mov dword ptr [rip + g_dragging], 0
    mov [rbx + DOC_cur], r12
    mov [rbx + DOC_anchor], r12
    call cmd_select_line
    mov dword ptr [rip + g_reveal], 0
.Led_noinput:
    # drag selection
    cmp dword ptr [rip + g_dragging], 0
    je 4f
    test dword ptr [rip + g_mdown], 1 << BTN_LEFT
    jnz 5f
    mov dword ptr [rip + g_dragging], 0
    jmp 4f
5:  mov rdi, rbx
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call pos_at_point
    cmp rax, [rbx + DOC_cur]
    je 6f
    mov [rbx + DOC_cur], rax
    mov dword ptr [rip + g_dirty], 1
    call time_ms
    mov [rip + g_blink_t0], rax
6:  # autoscroll when dragging outside
    mov eax, [rip + g_my]
    cmp eax, [rip + g_ed_y]
    jge 61f
    mov esi, [rip + g_lh]
    shr esi, 2
    neg esi
    call drag_scroll
61: mov eax, [rip + g_my]
    mov ecx, [rip + g_ed_y]
    add ecx, [rip + g_ed_h]
    cmp eax, ecx
    jl 4f
    mov esi, [rip + g_lh]
    shr esi, 2
    call drag_scroll
4:  cmp dword ptr [rip + cfg_vim], 0
    je 45f
    cmp dword ptr [rip + g_dragging], 0
    jne 45f
    mov rdi, rbx
    call vim_view
45: cmp dword ptr [rip + g_reveal], 0
    je 7f
    mov dword ptr [rip + g_reveal], 0
    mov rdi, rbx
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 71f
    call reveal_wrap
    jmp 7f
71: call reveal
7:  mov rdi, rbx
    call clamp_scroll
    # syntax states for everything visible
    mov rsi, [rbx + DOC_scrolly]
    shr rsi, 8
    mov eax, [rip + g_ed_h]
    xor edx, edx
    div dword ptr [rip + g_lh]
    mov [rip + g_ed_h_lines], eax
    lea rsi, [rsi + rax + 2]
    mov rdi, rbx
    call syntax_prepare
    # ---- lines ----
    mov qword ptr [rip + cls_doc], 0
    mov rdi, rbx
    call match_brackets
    mov dword ptr [rip + g_caret_ok], 0
    mov dword ptr [rip + g_carets_cnt], 0
    mov dword ptr [rip + dl_from], 0
    mov dword ptr [rip + dl_to], -1
    mov dword ptr [rip + dl_last], 1
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 72f
    mov qword ptr [rbx + DOC_scrollx], 0
    mov rdi, rbx
    call draw_wrapped
    jmp .Led_lines_done
72: mov rax, [rbx + DOC_scrolly]
    mov rcx, rax
    shr rax, 8
    mov r12, rax                # first line
    and ecx, 255
    imul ecx, [rip + g_lh]
    shr ecx, 8
    mov eax, [rip + g_ed_y]
    sub eax, ecx
    mov r13d, eax               # y of first line
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov [rsp + 8], rax          # cursor line
    mov rdi, rbx
    call vim_sel
    mov [rsp + 16], rax         # sel start
    mov [rsp + 24], rdx         # sel end
    mov dword ptr [rsp + 32], 0 # last indent (for blank lines)
    mov rdi, rbx
    call git_doc_marks
    mov [rsp + 96], rax
.Led_line:
    cmp r12, [rbx + DOC_nlines]
    jae .Led_lines_done
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r13d, eax
    jge .Led_lines_done
    # current line highlight
    cmp dword ptr [rip + cfg_highlight_line], 0
    je 1f
    cmp r12, [rsp + 8]
    jne 1f
    mov rax, [rsp + 16]
    cmp rax, [rsp + 24]
    jne 1f
    mov edi, [rip + g_ed_x]
    mov esi, r13d
    mov edx, [rip + g_ed_w]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_LINE_HL
    call gfx_fill
1:  mov rdi, r12
    mov esi, r13d
    mov edx, [rip + g_lh]
    call draw_disk_range
    # line number
    cmp qword ptr [rbx + DOC_diff], 0
    jne .Led_diffline
    cmp dword ptr [rip + cfg_line_numbers], 0
    je 2f
    lea rdi, [rsp + 40]
    lea rsi, [r12 + 1]
    call fmt_u64
    mov r14, rax
    lea rdi, [rip + g_face_code]
    lea rsi, [rsp + 40]
    mov rdx, rax
    call text_width
    mov esi, [rip + g_ed_tx]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_16]
    COLOR r9d, T_LINENO
    cmp r12, [rsp + 8]
    jne 11f
    COLOR r9d, T_LINENO_ACTIVE
11: lea rdi, [rip + g_face_code]
    mov edx, r13d
    add edx, [rip + g_base]
    lea rcx, [rsp + 40]
    mov r8, r14
    call text_draw
2:  # git change mark
    mov rax, [rsp + 96]
    test rax, rax
    jz 21f
    movzx edi, byte ptr [rax + r12]
    test edi, edi
    jz 21f
    mov esi, r13d
    mov edx, [rip + g_lh]
    call mark_draw
21: # text area clip
    mov edi, [rip + g_ed_tx]
    sub edi, [rip + g_mt + 4*MI_4]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_x]
    add edx, [rip + g_ed_w]
    sub edx, edi
    mov ecx, [rip + g_ed_h]
    call gfx_clip_push
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    lea rcx, [rsp + 16]
    call draw_line
    call gfx_clip_pop
.Led_adv:
    add r13d, [rip + g_lh]
    inc r12
    jmp .Led_line
.Led_diffline:
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov ecx, [rip + g_lh]
    call diffview_line
    test eax, eax
    jz 21b
    jmp .Led_adv
.Led_lines_done:
    # caret
    mov rdi, rbx
    call draw_caret
    # gutter separator shadow when scrolled horizontally
    cmp qword ptr [rbx + DOC_scrollx], 0
    je 8f
    mov edi, [rip + g_ed_tx]
    sub edi, [rip + g_mt + 4*MI_4]
    mov esi, [rip + g_ed_y]
    M edx, MI_1
    mov ecx, [rip + g_ed_h]
    COLOR r8d, T_BORDER
    call gfx_fill
8:  # scrollbar
    mov rax, [rbx + DOC_nlines]
    add eax, 1
    imul eax, [rip + g_lh]
    cmp dword ptr [rip + cfg_scroll_past_end], 0
    je 81f
    add eax, [rip + g_ed_h]
    sub eax, [rip + g_lh]
81: mov [rsp + 48], eax         # content px
    mov rax, [rbx + DOC_scrolly]
    imul eax, [rip + g_lh]
    sar eax, 8
    mov [rsp + 52], eax         # offset px
    mov eax, [rip + g_ed_h]
    push rax
    mov eax, [rsp + 48 + 8]
    push rax
    mov edi, ID_EDSCROLL
    mov esi, [rip + g_ed_x]
    add esi, [rip + g_ed_w]
    M eax, MI_12
    sub esi, eax
    mov edx, [rip + g_ed_y]
    mov ecx, eax
    mov r8d, [rip + g_ed_h]
    lea r9, [rsp + 52 + 16]
    call ui_scrollbar
    add rsp, 16
    # scrollbar drag writes pixels back
    cmp dword ptr [rip + g_active], ID_EDSCROLL
    jne 91f
    mov eax, [rsp + 52]
    movsxd rax, eax
    shl rax, 8
    cqo
    movsxd rcx, dword ptr [rip + g_lh]
    idiv rcx
    mov [rbx + DOC_scrolly], rax
91: # a thin edge also signals changes outside the visible lines, without moving the view
    mov r8d, [rip + disk_edge]
    test r8d, r8d
    jz 92f
    mov edi, [rip + g_ed_x]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_w]
    M ecx, MI_2
    call gfx_fill
92: call gfx_clip_pop
.Led_ret:
    EPILOGUE

# disk_colors(): compute the active file's fade once per frame
disk_colors:
    mov dword ptr [rip + disk_edge], 0
    mov dword ptr [rip + disk_tint], 0
    mov rax, [rip + g_doc]
    cmp qword ptr [rax + DOC_disk_until], 0
    je 2f
    push rbx
    mov rbx, rax
    call time_ms
    mov rcx, [rbx + DOC_disk_until]
    sub rcx, rax
    jle 1f
    imul rax, rcx, 255
    xor edx, edx
    mov ecx, DISK_FADE_MS
    div rcx
    cmp eax, 255
    jbe 3f
    mov eax, 255
3:  COLOR ecx, T_ACCENT
    and ecx, 0x00ffffff
    mov edx, eax
    shl edx, 24
    or edx, ecx
    mov [rip + disk_edge], edx
    shr eax, 2                 # line tint starts at 25% opacity, beneath text and selection
    shl eax, 24
    or eax, ecx
    mov [rip + disk_tint], eax
1:  pop rbx
2:  ret

# draw_disk_range(line, y, height): one inexpensive range check per visible logical line
draw_disk_range:
    mov r8d, [rip + disk_tint]
    test r8d, r8d
    jz 1f
    mov rax, [rip + g_doc]
    cmp rdi, [rax + DOC_disk_lo]
    jb 1f
    cmp rdi, [rax + DOC_disk_hi]
    jae 1f
    mov ecx, edx
    mov edi, [rip + g_ed_x]
    mov edx, [rip + g_ed_w]
    jmp gfx_fill
1:  ret

# disk_warning(): an inline warning only for a conflict; keep all local edits in the code view
disk_warning:
    PROLOGUE
    mov rax, [rip + g_doc]
    test dword ptr [rax + DOC_flags], DF_DISK_CHANGED
    jz 9f
    M ebx, MI_28
    mov eax, ebx
    add eax, ebx
    cmp [rip + g_ed_h], eax
    jl 9f
    mov edi, [rip + g_ed_x]
    mov esi, [rip + g_ed_y]
    mov edx, [rip + g_ed_w]
    mov ecx, ebx
    COLOR r8d, T_PANEL
    call gfx_fill
    lea rdi, [rip + g_face_small]
    mov esi, [rip + g_ed_x]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rip + g_ed_y]
    mov ecx, ebx
    lea r8, [rip + .Ldisk_warning]
    COLOR r9d, T_WARNING
    call ui_text_c
    mov edi, [rip + g_ed_x]
    mov esi, [rip + g_ed_y]
    add esi, ebx
    sub esi, [rip + g_mt + 4*MI_1]
    mov edx, [rip + g_ed_w]
    M ecx, MI_1
    COLOR r8d, T_WARNING
    call gfx_fill
    add [rip + g_ed_y], ebx
    sub [rip + g_ed_h], ebx
9:  EPILOGUE

# draw_line(doc, line, y, selrange*): draws bytes [dl_from, dl_to) of the line as one visual row
draw_line:
    PROLOGUE 128
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx              # y
    mov rax, [rcx]
    mov [rsp + 8], rax          # sel start
    mov rax, [rcx + 8]
    mov [rsp + 16], rax         # sel end
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp + 24], rax         # line start pos
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov r14, rax
    mov r15, rdx
    # segment
    mov eax, [rip + dl_to]
    cmp rax, r15
    jbe 1f
    mov rax, r15
1:  mov [rsp + 32], rax         # to (offset)
    mov eax, [rip + dl_from]
    mov [rsp + 96], rax         # from (offset)
    # classes for the whole line (cached across the rows of one line)
    cmp [rip + cls_doc], rbx
    jne 2f
    cmp [rip + cls_line], r12
    jne 2f
    mov rax, [rbx + DOC_version]
    cmp [rip + cls_ver], rax
    jne 2f
    mov rax, [rbx + DOC_svalid]
    cmp [rip + cls_svalid], rax
    je 3f
2:  mov [rip + cls_doc], rbx
    mov [rip + cls_line], r12
    mov rax, [rbx + DOC_version]
    mov [rip + cls_ver], rax
    mov rax, [rbx + DOC_svalid]
    mov [rip + cls_svalid], rax
    lea rdi, [rip + classes]
    mov qword ptr [rdi + SB_len], 0
    lea rsi, [r15 + 16]
    call sb_reserve
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rcx, r15
    mov r8, [rip + classes + SB_ptr]
    call syntax_line
3:  # x origin
    mov eax, [rip + g_ed_tx]
    sub eax, [rbx + DOC_scrollx]
    mov [rsp + 40], eax
    # ---- selection ----
    mov rax, [rsp + 8]
    cmp rax, [rsp + 16]
    je .Ldl_nosel
    mov rcx, [rsp + 24]
    add rcx, [rsp + 96]         # row start pos
    mov rdx, [rsp + 24]
    add rdx, [rsp + 32]         # row end pos
    cmp rax, rcx
    cmovb rax, rcx              # a = max(S, row start)
    mov r8, [rsp + 16]
    xor r9d, r9d                # extra cell for the newline
    cmp r8, rdx
    jbe 4f
    mov r8, rdx                 # b = min(E, row end)
    cmp dword ptr [rip + dl_last], 0
    je 4f
    mov r9d, 1
4:  cmp rax, r8
    ja .Ldl_nosel
    jb 5f
    test r9d, r9d
    jz .Ldl_nosel
5:  mov [rsp + 48], r8
    mov [rsp + 60], r9d
    mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, rax
    sub rdx, [rsp + 24]
    mov [rsp + 104], rdx
    call seg_cols
    mov [rsp + 56], eax         # start col
    mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, [rsp + 48]
    sub rdx, [rsp + 24]
    call seg_cols
    add eax, [rsp + 60]
    sub eax, [rsp + 56]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, [rsp + 56]
    imul edi, [rip + g_cw]
    add edi, [rsp + 40]
    mov esi, [rsp]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_SELECTION
    call gfx_fill
.Ldl_nosel:
    cmp qword ptr [rbx + DOC_cursors + VEC_len], 0
    jz .Ldl_sec_sel_done
    xor r13, r13
.Ldl_sec_sel_loop:
    cmp r13, [rbx + DOC_cursors + VEC_len]
    jae .Ldl_sec_sel_done
    imul rax, r13, CURS_SIZE
    add rax, [rbx + DOC_cursors + VEC_ptr]
    mov rsi, [rax + CURS_cur]
    mov rdx, [rax + CURS_anchor]
    mov rax, rsi
    cmp rdx, rax
    cmovb rax, rdx
    mov r8, rsi
    cmp rdx, r8
    cmova r8, rdx
    cmp rax, r8
    je .Ldl_sec_sel_next

    mov rcx, [rsp + 24]
    add rcx, [rsp + 96]
    mov rdx, [rsp + 24]
    add rdx, [rsp + 32]
    cmp rax, rcx
    cmovb rax, rcx
    xor r9d, r9d
    cmp r8, rdx
    jbe 41f
    mov r8, rdx
    cmp dword ptr [rip + dl_last], 0
    je 41f
    mov r9d, 1
41: cmp rax, r8
    ja .Ldl_sec_sel_next
    jb 51f
    test r9d, r9d
    jz .Ldl_sec_sel_next
51: mov [rsp + 48], r8
    mov [rsp + 60], r9d
    mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, rax
    sub rdx, [rsp + 24]
    mov [rsp + 104], rdx
    call seg_cols
    mov [rsp + 56], eax
    mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, [rsp + 48]
    sub rdx, [rsp + 24]
    call seg_cols
    add eax, [rsp + 60]
    sub eax, [rsp + 56]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, [rsp + 56]
    imul edi, [rip + g_cw]
    add edi, [rsp + 40]
    mov esi, [rsp]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_SELECTION
    call gfx_fill
.Ldl_sec_sel_next:
    inc r13
    jmp .Ldl_sec_sel_loop
.Ldl_sec_sel_done:
    # ---- find matches ----
    mov rcx, [rip + g_ed_find + SB_len]
    test rcx, rcx
    jz .Ldl_nofind
    mov rax, [rsp + 96]
    mov [rsp + 112], rax        # byte offset whose column is known
    mov dword ptr [rsp + 120], 0
    xor r13d, r13d
6:  lea rdi, [r14 + r13]
    mov rsi, r15
    sub rsi, r13
    jbe .Ldl_nofind
    mov rdx, [rip + g_ed_find + SB_ptr]
    mov rcx, [rip + g_ed_find + SB_len]
    call find_raw
62: test rax, rax
    js .Ldl_nofind
    add r13, rax
    cmp r13, [rsp + 32]
    jae .Ldl_nofind
    # clip [m, m+n) to the row
    mov rax, r13
    mov rdx, r13
    add rdx, [rip + g_ed_find + SB_len]
    mov rcx, [rsp + 96]
    cmp rax, rcx
    cmovb rax, rcx
    mov rcx, [rsp + 32]
    cmp rdx, rcx
    cmova rdx, rcx
    cmp rax, rdx
    jae 63f
    mov [rsp + 48], rdx
    mov [rsp + 104], rax
    mov rdi, r14
    mov rsi, [rsp + 112]
    mov rdx, rax
    mov ecx, [rsp + 120]
    call seg_cols_from
    mov [rsp + 56], eax
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    cmp eax, [rip + g_cv + CV_cx1]
    jge .Ldl_nofind             # later matches are also outside the view
    mov rdi, r14
    mov rsi, [rsp + 104]
    mov rdx, [rsp + 48]
    mov ecx, [rsp + 56]
    call seg_cols_from
    mov [rsp + 120], eax
    mov rcx, [rsp + 48]
    mov [rsp + 112], rcx
    sub eax, [rsp + 56]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, [rsp + 56]
    imul edi, [rip + g_cw]
    add edi, [rsp + 40]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_1]
    mov ecx, [rip + g_lh]
    sub ecx, [rip + g_mt + 4*MI_2]
    M r8d, MI_3
    COLOR r9d, T_MATCH
    call gfx_round_rect
63: add r13, [rip + g_ed_find + SB_len]
    jmp 6b
.Ldl_nofind:
    # ---- bracket pair ----
    mov qword ptr [rsp + 112], 0
.Ldl_br:
    mov rcx, [rsp + 112]
    cmp rcx, 2
    jae .Ldl_nobr
    inc qword ptr [rsp + 112]
    lea rax, [rip + g_br]
    mov rax, [rax + rcx*8]
    sub rax, [rsp + 24]
    js .Ldl_br
    cmp rax, [rsp + 96]
    jb .Ldl_br
    cmp rax, [rsp + 32]
    jae .Ldl_br
    mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, rax
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    mov edi, eax
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_1]
    mov edx, [rip + g_cw]
    mov ecx, [rip + g_lh]
    sub ecx, [rip + g_mt + 4*MI_2]
    COLOR r8d, T_MUTED
    call draw_box
    jmp .Ldl_br
.Ldl_nobr:
    # ---- caret position ----
    mov rax, [rbx + DOC_cur]
    sub rax, [rsp + 24]
    js 7f
    cmp rax, [rsp + 96]
    jb 7f
    cmp rax, [rsp + 32]
    jb 71f
    ja 7f
    cmp dword ptr [rip + dl_last], 0
    je 7f
71: mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, rax
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    mov [rip + g_caret_x], eax
    mov eax, [rsp]
    mov [rip + g_caret_y], eax
    mov dword ptr [rip + g_caret_ok], 1
    mov edi, [rip + g_caret_x]
    mov esi, [rip + g_caret_y]
    call ed_record_caret
7:  cmp qword ptr [rbx + DOC_cursors + VEC_len], 0
    jz .Ldl_sec_caret_done
    xor r13, r13
.Ldl_sec_caret_loop:
    cmp r13, [rbx + DOC_cursors + VEC_len]
    jae .Ldl_sec_caret_done
    imul rax, r13, CURS_SIZE
    add rax, [rbx + DOC_cursors + VEC_ptr]
    mov rax, [rax + CURS_cur]
    sub rax, [rsp + 24]
    js .Ldl_sec_cnext
    cmp rax, [rsp + 96]
    jb .Ldl_sec_cnext
    cmp rax, [rsp + 32]
    jb 72f
    ja .Ldl_sec_cnext
    cmp dword ptr [rip + dl_last], 0
    je .Ldl_sec_cnext
72: mov rdi, r14
    mov rsi, [rsp + 96]
    mov rdx, rax
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    mov edi, eax
    mov esi, [rsp]
    call ed_record_caret
.Ldl_sec_cnext:
    inc r13
    jmp .Ldl_sec_caret_loop
.Ldl_sec_caret_done:  # ---- glyphs ----
    mov r13, [rsp + 96]         # byte index
    mov dword ptr [rsp + 64], 0 # column
    mov eax, [rsp]
    add eax, [rip + g_base]
    mov [rsp + 72], eax         # baseline
    mov eax, [rip + g_cv + CV_cx1]
    mov [rsp + 76], eax
.Ldl_glyph:
    cmp r13, [rsp + 32]
    jae .Ldl_guides
    mov eax, [rsp + 64]
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    cmp eax, [rsp + 76]
    jge .Ldl_guides
    mov [rsp + 80], eax         # x
    movzx eax, byte ptr [r14 + r13]
    cmp al, 9
    jne 8f
    mov eax, [rsp + 64]
    xor edx, edx
    div dword ptr [rip + cfg_tab_width]
    mov eax, [rip + cfg_tab_width]
    sub eax, edx
    mov [rsp + 84], eax
    cmp dword ptr [rip + cfg_whitespace], 0
    je 81f
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 80]
    mov edx, [rsp + 72]
    lea rcx, [rip + .Ltab_arrow]
    mov r8d, 3
    COLOR r9d, T_GUIDE
    call text_draw
81: mov eax, [rsp + 84]
    add [rsp + 64], eax
    inc r13
    jmp .Ldl_glyph
8:  cmp al, ' '
    jne 9f
    cmp dword ptr [rip + cfg_whitespace], 0
    je 82f
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 80]
    mov edx, [rsp + 72]
    lea rcx, [rip + .Lmiddot]
    mov r8d, 2
    COLOR r9d, T_GUIDE
    call text_draw
82: inc dword ptr [rsp + 64]
    inc r13
    jmp .Ldl_glyph
9:  lea rdi, [r14 + r13]
    mov rsi, r15
    sub rsi, r13
    call utf8_decode
    mov [rsp + 84], edx         # byte length
    mov [rsp + 88], eax         # codepoint
    mov rcx, [rip + classes + SB_ptr]
    movzx ecx, byte ptr [rcx + r13]
    lea rdx, [rip + g_theme]
    mov r9d, [rdx + rcx*4 + 4*T_SYN]
    mov r8d, [rsp + 84]
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 80]
    mov edx, [rsp + 72]
    lea rcx, [r14 + r13]
    call text_draw
    mov edi, [rsp + 88]
    call cp_width
    add [rsp + 64], eax
    mov eax, [rsp + 84]
    add r13, rax
    jmp .Ldl_glyph
.Ldl_guides:
    cmp dword ptr [rip + cfg_indent_guides], 0
    je .Ldl_ret
    cmp qword ptr [rsp + 96], 0
    jne .Ldl_ret
    # indent columns of this line (blank lines reuse the previous one)
    mov rdi, rbx
    mov rsi, r12
    call line_indent
    cmp rax, r15
    jne 10f
    mov edx, [rip + last_indent]
10: mov [rip + last_indent], edx
    mov ecx, [rip + cfg_tab_width]
    mov [rsp + 64], ecx
11: mov eax, [rsp + 64]
    cmp eax, [rip + last_indent]
    jg .Ldl_ret
    sub eax, [rip + cfg_tab_width]
    imul eax, [rip + g_cw]
    add eax, [rsp + 40]
    mov edi, eax
    mov esi, [rsp]
    M edx, MI_1
    mov ecx, [rip + g_lh]
    COLOR r8d, T_GUIDE
    call gfx_fill
    mov eax, [rip + cfg_tab_width]
    add [rsp + 64], eax
    jmp 11b
.Ldl_ret:
    EPILOGUE

# draw_box(x, y, w, h, argb): 1px outline, softened
draw_box:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r8d
    and ebx, 0xffffff
    or ebx, 0xa0000000
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, [rip + g_border]
    mov r8d, ebx
    call gfx_fill
    mov edi, r12d
    lea esi, [r13 + r15]
    sub esi, [rip + g_border]
    mov edx, r14d
    mov ecx, [rip + g_border]
    mov r8d, ebx
    call gfx_fill
    mov edi, r12d
    mov esi, r13d
    add esi, [rip + g_border]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, [rip + g_border]
    sub ecx, [rip + g_border]
    mov r8d, ebx
    call gfx_fill
    lea edi, [r12 + r14]
    sub edi, [rip + g_border]
    mov esi, r13d
    add esi, [rip + g_border]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, [rip + g_border]
    sub ecx, [rip + g_border]
    mov r8d, ebx
    call gfx_fill
    EPILOGUE

# match_brackets(doc): g_br = the bracket at or before the cursor and its partner, else -1
match_brackets:
    PROLOGUE 32
    mov rbx, rdi
    mov qword ptr [rip + g_br], -1
    mov qword ptr [rip + g_br + 8], -1
    cmp dword ptr [rip + cfg_match_brackets], 0
    je 9f
    mov r12, [rbx + DOC_cur]
    cmp r12, [rbx + DOC_anchor]
    jne 9f
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    call bracket_kind
    test edx, edx
    jnz 1f
    test r12, r12
    jz 9f
    dec r12
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    call bracket_kind
    test edx, edx
    jz 9f
1:  mov r13d, eax               # this bracket
    mov r14d, ecx               # its partner
    movsxd r15, edx             # direction
    mov [rsp], r12
    mov qword ptr [rsp + 8], 0  # depth
    mov qword ptr [rsp + 16], 100000
2:  dec qword ptr [rsp + 16]
    js 9f
    add r12, r15
    js 9f
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    test eax, eax
    jz 9f
    cmp eax, r13d
    jne 3f
    inc qword ptr [rsp + 8]
    jmp 2b
3:  cmp eax, r14d
    jne 2b
    dec qword ptr [rsp + 8]
    jns 2b
    mov rax, [rsp]
    mov [rip + g_br], rax
    mov [rip + g_br + 8], r12
9:  EPILOGUE

# bracket_kind(eax byte) -> eax byte, ecx partner, edx +1 opening / -1 closing / 0 none
bracket_kind:
    lea r8, [rip + .Lbrackets]
    xor edx, edx
1:  movzx ecx, byte ptr [r8 + rdx]
    test ecx, ecx
    jz 3f
    cmp eax, ecx
    je 2f
    inc edx
    jmp 1b
2:  test edx, 1
    jnz 4f
    movzx ecx, byte ptr [r8 + rdx + 1]
    mov edx, 1
    ret
4:  movzx ecx, byte ptr [r8 + rdx - 1]
    mov edx, -1
    ret
3:  xor edx, edx
    ret

# draw_caret(doc): at the position recorded by draw_line
draw_caret:
    PROLOGUE 32
    mov rbx, rdi
    cmp dword ptr [rip + g_caret_ok], 0
    je 9f
    cmp dword ptr [rip + g_vim_cmdline], 0
    jne 9f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    cmp dword ptr [rip + g_win_focused], 0
    je 9f
    # off in the odd halves of the blink, on when it does not blink
    call ed_blink_phase
    cmp eax, -1
    je 1f
    test eax, 1
    jnz 9f
1:  mov edi, [rip + g_caret_x]
    cmp edi, [rip + g_ed_tx]
    jl 9f
    # vim: a block over the character outside insert mode
    cmp dword ptr [rip + cfg_vim], 0
    je 11f
    mov eax, [rip + g_vim_mode]
    cmp eax, VM_INSERT
    je 11f
    cmp eax, VM_NORMAL
    jne draw_block
    mov rax, [rbx + DOC_cur]
    cmp rax, [rbx + DOC_anchor]
    je draw_block
11: M edx, MI_2
    cmp dword ptr [rip + cfg_smooth_caret], 0
    jne 2f
    M edx, MI_1
2:  mov ecx, [rip + g_lh]
    COLOR r8d, T_CURSOR
    mov r12d, [rip + g_carets_cnt]
    test r12d, r12d
    jz .Ldc_fallback
    mov [rsp], edx
    mov [rsp + 8], ecx
    mov [rsp + 16], r8d
    xor r13d, r13d
.Ldc_loop:
    cmp r13d, r12d
    jae 9f
    lea rax, [rip + g_carets_buf]
    mov edi, [rax + r13*8]
    mov esi, [rax + r13*8 + 4]
    cmp edi, [rip + g_ed_tx]
    jl .Ldc_next
    mov edx, [rsp]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 16]
    call gfx_fill
.Ldc_next:
    inc r13d
    jmp .Ldc_loop
.Ldc_fallback:
    mov edi, [rip + g_caret_x]
    mov esi, [rip + g_caret_y]
    call gfx_fill
9:  EPILOGUE

# draw_block: tail of draw_caret (rbx doc): the character at the cursor in the background color on the cursor color
draw_block:
    mov r12, [rbx + DOC_cur]
    mov rdi, rbx
    call doc_len
    mov r13, rax
    sub r13, r12                # bytes left
    mov r14d, [rip + g_cw]      # width
    xor r15d, r15d              # bytes to draw
    test r13, r13
    jz 3f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 4
    cmp r13, 4
    cmovb rdx, r13
    mov [rsp + 8], rdx
    call doc_range
    mov [rsp], rax
    movzx ecx, byte ptr [rax]
    cmp ecx, ' '
    jbe 3f
    mov rdi, rax
    mov rsi, [rsp + 8]
    call utf8_decode
    mov r15d, edx
    mov edi, eax
    call cp_width
    imul r14d, eax
    # doc_range may reuse its scratch buffer: keep the bytes
    mov rsi, [rsp]
    xor ecx, ecx
4:  mov al, [rsi + rcx]
    mov [rsp + 8 + rcx], al
    inc ecx
    cmp ecx, r15d
    jb 4b
3:  mov edi, [rip + g_caret_x]
    mov esi, [rip + g_caret_y]
    mov edx, r14d
    mov ecx, [rip + g_lh]
    COLOR r8d, T_CURSOR
    call gfx_fill
    test r15d, r15d
    jz 9f
    lea rdi, [rip + g_face_code]
    mov esi, [rip + g_caret_x]
    mov edx, [rip + g_caret_y]
    add edx, [rip + g_base]
    lea rcx, [rsp + 8]
    mov r8d, r15d
    COLOR r9d, T_BG
    call text_draw
9:  EPILOGUE

# ed_clip_set(ptr, len, linewise): the text becomes the clipboard; linewise text pastes as whole lines
FN ed_clip_set
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    lea rdi, [rip + clip_sb]
    call sb_clear
    lea rdi, [rip + clip_sb]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, [rip + clip_sb + SB_ptr]
    mov rsi, [rip + clip_sb + SB_len]
    PCALL P_clip_set
    mov [rip + g_clip_line], r14d
    EPILOGUE

# ed_clip_linewise(ptr, len) -> 1 when the text is our last whole-line copy
FN ed_clip_linewise
    xor eax, eax
    cmp dword ptr [rip + g_clip_line], 0
    je 1f
    cmp rsi, [rip + clip_sb + SB_len]
    jne 1f
    mov rdx, rsi
    mov rsi, [rip + clip_sb + SB_ptr]
    jmp memeq
1:  ret

# blink_elapsed() -> ms since the last caret activity, -1 if the caret does not blink (turned off,
# not focused, BLINK_FOR idle)
blink_elapsed:
    cmp qword ptr [rip + g_doc], 0
    je 1f
    cmp dword ptr [rip + cfg_cursor_blink], 0
    je 1f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 1f
    cmp dword ptr [rip + g_win_focused], 0
    je 1f
    call time_ms
    sub rax, [rip + g_blink_t0]
    cmp rax, BLINK_FOR
    jbe 2f
1:  mov rax, -1
2:  ret

# ed_blink_timeout() -> ms until the caret toggles, -1 if not blinking
FN ed_blink_timeout
    call blink_elapsed
    test rax, rax
    js 1f
    xor edx, edx
    mov ecx, BLINK_MS
    div rcx
    mov eax, BLINK_MS
    sub eax, edx
1:  ret

# ed_blink_phase() -> the half of the blink the caret is in (odd: off), -1 if not blinking
FN ed_blink_phase
    call blink_elapsed
    test rax, rax
    js 1f
    xor edx, edx
    mov ecx, BLINK_MS
    div rcx
1:  ret

# ed_blink_tick(): a frame each time the caret turns on or off, and when it stops blinking
FN ed_blink_tick
    call ed_blink_phase
    cmp eax, [rip + blink_seen]
    je 1f
    mov [rip + blink_seen], eax
    mov dword ptr [rip + g_dirty], 1
1:  ret

.section .rodata
.Lem1: .asciz "Cut"
.Ldisk_warning: .asciz "Changed on disk. Unsaved edits kept."
.Lem2: .asciz "Copy"
.Lem3: .asciz "Paste"
.Lem4: .asciz "Select All"
.Lem5: .asciz "Toggle Comment"
.Lem6: .asciz "Go to File"
.p2align 3
editor_menu:
    .quad .Lem1, cmd_cut, .Lem2, cmd_copy, .Lem3, cmd_paste, .Lem4, cmd_select_all
    .quad .Lem5, cmd_toggle_comment, .Lem6, cmd_quick_open, 0, 0
pair_open: .asciz "([{\"'`"
pair_close: .asciz ")]}\"'`"
.Lspace: .ascii " "
.Ltab_arrow: .ascii "\342\206\222"
.Lmiddot: .ascii "\302\267"
.Lbrackets: .asciz "()[]{}"
.data
dl_to: .long -1
.p2align 3
g_br: .quad -1, -1
.bss
.p2align 3
sel_word_a: .quad 0
disk_edge: .long 0
disk_tint: .long 0
sel_word_b: .quad 0
last_indent: .long 0
.globl g_ed_x, g_ed_y, g_ed_w, g_ed_h, g_ed_tx
.globl g_caret_x, g_caret_y, g_caret_ok
g_caret_x: .long 0
g_caret_y: .long 0
g_caret_ok: .long 0
dl_from: .long 0
dl_last: .long 0
.p2align 3
cls_doc: .quad 0
cls_line: .quad 0
cls_ver: .quad 0
cls_svalid: .quad 0
.globl g_clip_line, g_mods
g_clip_line: .long 0
g_mods: .long 0
