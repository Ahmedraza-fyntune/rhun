# editor presentation: inline completion, ghost text (feature inline-complete). After a typing
# pause (inline_complete_delay) or with alt+\, the language's provider is asked for the text that
# could follow the caret (`inline-complete DOC VERSION LINE COL typed|invoked`). The first item
# whose range holds the caret and agrees with the text around it shows: its first line in the
# `ghost` color after the caret (a VK_GHOST inlay), the others as rows below the line (wrap.s's
# rows: line_breaks puts them before the next line, lens.s draws them; after the last line,
# ghost_tail_draw). Tab takes it all (after the
# completion list and a snippet's fields), ctrl+Right its next word; typing what it shows keeps it,
# any other edit or caret move, or Escape, dismisses it.
.include "rhun.inc"

.equ GH_ITEMS, 8
.equ GH_TEXT_MAX, 65536
.equ GH_LINES, 50
.equ GH_EXTRA_MAX, 65536

.bss
.p2align 3
gh_doc: .quad 0                 # the document the ghost is in (0: none)
gh_ver: .quad 0                 # its version
gh_caret: .quad 0               # the caret it follows
gh_text: .quad 0                # owned: the item's text
gh_tlen: .quad 0
gh_off: .quad 0                 # the ghost: the text from here, gh_glen bytes
gh_glen: .quad 0
gh_start: .quad 0               # the item's range in the text
gh_end: .quad 0
gh_extra: .quad 0               # owned: its extra records (command, edit)
gh_xlen: .quad 0
gh_ext: .quad 0                 # its provider
gh_line: .quad 0                # the caret's line
.globl gh_rows
gh_rows: .quad 0                # lines after the first: rows below gh_line
gh_due: .quad 0                 # time_ms a typed request is due (0: not)
gh_req_ext: .quad 0             # the request out
gh_req_id: .quad 0
gh_req_ver: .quad 0
gh_req_caret: .quad 0
gh_seen_ver: .quad 0            # the version and caret ghost_frame last saw
gh_seen_cur: .quad 0
gh_seen_doc: .quad 0
gh_lbuf: .zero SB_SIZE
vi_gh: .zero VI_SIZE
gh_cmp: .zero 256

.text

# ---------------- showing ----------------

# FN ghost_frame(doc): a frame of the document: edits and caret moves keep, trim or dismiss the
# ghost, and a typing pause schedules a request
FN ghost_frame
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    cmp [rip + gh_seen_doc], rbx
    je 1f
    mov [rip + gh_seen_doc], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + gh_seen_ver], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + gh_seen_cur], rax
    call ghost_dismiss
    jmp 9f
1:  mov rax, [rbx + DOC_version]
    cmp rax, [rip + gh_seen_ver]
    je 5f
    # an edit: a typed character the ghost starts with keeps it, shorter
    mov [rip + gh_seen_ver], rax
    mov r12, [rbx + DOC_cur]
    mov [rip + gh_seen_cur], r12
    cmp qword ptr [rip + gh_doc], rbx
    jne 4f
    mov r13, r12
    sub r13, [rip + gh_caret]   # the bytes typed since
    jbe 3f
    cmp r13, [rip + gh_glen]
    jae 3f
    cmp r13, 256
    ja 3f
    mov rdi, rbx
    mov rsi, [rip + gh_caret]
    mov rdx, r13
    lea rcx, [rip + gh_cmp]
    call doc_copy
    lea rdi, [rip + gh_cmp]
    mov rsi, r13
    mov rdx, [rip + gh_text]
    add rdx, [rip + gh_off]
    mov rcx, r13
    call str_eq
    test eax, eax
    jz 3f
    mov rax, r12
    sub rax, [rip + gh_caret]
    add [rip + gh_off], rax
    sub [rip + gh_glen], rax
    mov [rip + gh_caret], r12
    mov rax, [rbx + DOC_version]
    mov [rip + gh_ver], rax
    call ghost_layout
    jmp 4f
3:  call ghost_dismiss
4:  # a typing pause asks again
    cmp dword ptr [rip + cfg_inline_complete], 0
    je 9f
    mov rax, [rbx + DOC_cur]
    cmp rax, [rbx + DOC_anchor]
    jne 9f
    call time_ms
    mov ecx, [rip + cfg_inline_complete_delay]
    add rax, rcx
    mov [rip + gh_due], rax
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
5:  mov rax, [rbx + DOC_cur]
    cmp rax, [rip + gh_seen_cur]
    je 9f
    mov [rip + gh_seen_cur], rax
    mov qword ptr [rip + gh_due], 0
    cmp rax, [rip + gh_caret]
    je 9f
    call ghost_dismiss          # the caret moved away
9:  EPILOGUE

# ghost_dismiss(): the ghost goes, and the request waited for
ghost_dismiss:
    sub rsp, 8
    cmp qword ptr [rip + gh_doc], 0
    je 1f
    mov qword ptr [rip + gh_doc], 0
    mov qword ptr [rip + gh_rows], 0
    mov rdi, [rip + gh_text]
    call mem_free
    mov rdi, [rip + gh_extra]
    call mem_free
    mov qword ptr [rip + gh_text], 0
    mov qword ptr [rip + gh_extra], 0
    mov rdi, [rip + gh_seen_doc]
    call pres_touch
1:  cmp qword ptr [rip + gh_req_ext], 0
    je 2f
    mov rdi, [rip + gh_req_ext]
    mov rsi, [rip + gh_req_id]
    mov qword ptr [rip + gh_req_ext], 0
    call query_withdraw
2:  add rsp, 8
    ret

# ghost_layout(): gh_line and gh_rows for the ghost now shown
ghost_layout:
    push rbx
    mov rdi, [rip + gh_doc]
    mov rsi, [rip + gh_caret]
    call doc_line_of
    mov [rip + gh_line], rax
    xor ecx, ecx
    mov rdx, [rip + gh_text]
    add rdx, [rip + gh_off]
    mov rbx, [rip + gh_glen]
1:  test rbx, rbx
    jz 2f
    cmp byte ptr [rdx], 10
    jne 11f
    inc ecx
11: inc rdx
    dec rbx
    jmp 1b
2:  # (rows below the last line sit after it: ghost_tail_draw)
    mov [rip + gh_rows], rcx
    mov rdi, [rip + gh_doc]
    call pres_touch
    pop rbx
    ret

# FN ghost_line_inlays(doc, line): the ghost's first line after the caret, to vt_add
FN ghost_line_inlays
    cmp [rip + gh_doc], rdi
    jne 9f
    cmp [rip + gh_line], rsi
    jne 9f
    cmp qword ptr [rip + gh_glen], 0
    je 9f
    PROLOGUE
    mov rbx, rdi
    call doc_line_start
    lea rdi, [rip + vi_gh]
    mov rcx, [rip + gh_caret]
    sub rcx, rax
    mov [rdi + VI_off], rcx
    mov rax, [rip + gh_text]
    add rax, [rip + gh_off]
    mov [rdi + VI_text], rax
    xor ecx, ecx                # its first line
1:  cmp rcx, [rip + gh_glen]
    jae 2f
    cmp byte ptr [rax + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov [rdi + VI_len], ecx
    mov dword ptr [rdi + VI_cells], 0
    mov byte ptr [rdi + VI_side], VS_AFTER
    mov byte ptr [rdi + VI_kind], VK_GHOST
    mov word ptr [rdi + VI_flags], 0
    mov qword ptr [rdi + VI_ref], 0
    mov dword ptr [rdi + VI_prio], 255
    COLOR eax, T_GHOST
    mov [rdi + VI_fg], eax
    mov dword ptr [rdi + VI_bg], 0
    test ecx, ecx
    jz 3f
    call vt_add
3:  EPILOGUE
9:  ret

# FN ghost_rows_before(doc, line) -> eax the ghost's rows that sit before this line (its lines after
# the first, below the caret's line)
FN ghost_rows_before
    xor eax, eax
    cmp [rip + gh_doc], rdi
    jne 9f
    mov rcx, [rip + gh_line]
    inc rcx
    cmp rcx, rsi
    jne 9f
    mov rax, [rip + gh_rows]
9:  ret

# FN ghost_tail_draw(doc, y): below the document's last line (drawn down to y), the ghost's lines
# after the first when the ghost is on that line (there is no next line to put them before)
FN ghost_tail_draw
    cmp [rip + gh_doc], rdi
    jne 9f
    cmp qword ptr [rip + gh_rows], 0
    je 9f
    mov rax, [rdi + DOC_nlines]
    dec rax
    cmp [rip + gh_line], rax
    jne 9f
    PROLOGUE
    mov r12d, esi
    xor ebx, ebx
1:  cmp rbx, [rip + gh_rows]
    jae 8f
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r12d, eax
    jge 8f
    mov edi, ebx
    mov esi, r12d
    call ghost_row_draw
    add r12d, [rip + g_lh]
    inc ebx
    jmp 1b
8:  EPILOGUE
9:  ret

# FN ghost_row_draw(row, y): the ghost's line row + 1 (its second line for row 0) at y
FN ghost_row_draw
    PROLOGUE
    mov r12, rdi
    mov r13d, esi
    mov rbx, [rip + gh_text]
    add rbx, [rip + gh_off]
    mov r14, [rip + gh_glen]
    lea r15, [rbx + r14]        # end
    # past row + 1 line feeds
    lea rcx, [r12 + 1]
1:  test rcx, rcx
    jz 3f
2:  cmp rbx, r15
    jae 9f
    inc rbx
    cmp byte ptr [rbx - 1], 10
    jne 2b
    dec rcx
    jmp 1b
3:  mov rcx, rbx
4:  cmp rcx, r15
    jae 5f
    cmp byte ptr [rcx], 10
    je 5f
    inc rcx
    jmp 4b
5:  sub rcx, rbx
    jz 9f
    mov r8, rcx
    mov rax, [rip + gh_doc]
    mov esi, [rip + g_ed_tx]
    sub esi, [rax + DOC_scrollx]
    lea rdi, [rip + g_face_code]
    mov edx, r13d
    add edx, [rip + g_base]
    mov rcx, rbx
    COLOR r9d, T_GHOST
    call text_draw
9:  EPILOGUE

# ---------------- asking ----------------

# FN ghost_timeout() -> eax ms until a typed request is due, or -1
FN ghost_timeout
    mov rax, [rip + gh_due]
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

# FN ghost_tick(): a typing pause over: the provider is asked (typed)
FN ghost_tick
    cmp qword ptr [rip + gh_due], 0
    je 9f
    sub rsp, 8
    call time_ms
    add rsp, 8
    cmp rax, [rip + gh_due]
    jb 9f
    mov qword ptr [rip + gh_due], 0
    xor edi, edi
    jmp ghost_ask
9:  ret

# FN cmd_inline_complete(): alt+\: the provider is asked now (invoked)
FN cmd_inline_complete
    mov edi, 1
    jmp ghost_ask

# ghost_ask(invoked): "inline-complete DOC VERSION LINE COL typed|invoked" to the language's provider
ghost_ask:
    PROLOGUE 16
    mov [rsp], edi
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + DOC_diff], 0
    jne 9f
    mov edi, PP_INLINE
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jz 9f
    mov r15, rax
    cmp qword ptr [rip + gh_req_ext], 0
    je 1f
    mov rdi, [rip + gh_req_ext]
    mov rsi, [rip + gh_req_id]
    mov qword ptr [rip + gh_req_ext], 0
    call query_withdraw
1:  mov rdi, rbx
    call pres_ensure
    lea rdi, [rip + gh_lbuf]
    call sb_clear
    lea rdi, [rip + gh_lbuf]
    lea rsi, [rip + .Lv_inline]
    call sb_push_cstr
    lea rdi, [rip + gh_lbuf]
    mov rsi, [rbx + DOC_id]
    call sb_push_u64
    lea rdi, [rip + gh_lbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + gh_lbuf]
    mov rsi, [rbx + DOC_version]
    call sb_push_u64
    lea rdi, [rip + gh_lbuf]
    mov rsi, rbx
    xor edx, edx
    xor ecx, ecx
    call hl_args                # " LINE COL" of the caret (hicolor.s)
    lea rsi, [rip + .Lk_typed]
    cmp dword ptr [rsp], 0
    je 2f
    lea rsi, [rip + .Lk_invoked]
2:  lea rdi, [rip + gh_lbuf]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, rbx
    mov rdx, [rip + gh_lbuf + SB_ptr]
    mov rcx, [rip + gh_lbuf + SB_len]
    call extproto_host_send
    test rax, rax
    jz 9f
    mov [rip + gh_req_id], rax
    mov [rip + gh_req_ext], r15
    mov rcx, [rbx + DOC_version]
    mov [rip + gh_req_ver], rcx
    mov rcx, [rbx + DOC_cur]
    mov [rip + gh_req_caret], rcx
    mov rdi, r15
    mov rsi, rax
    mov edx, PK_INLINE
    mov ecx, QO_PRESENT
    call query_track
9:  EPILOGUE

# FN ghost_reply(ext, id, ok, body, len) -> eax 1 when it answered the inline-complete request:
# "N" LF, then up to 8 items "L1 C1 L2 C2 TEXT_LEN EXTRA_LEN" LF TEXT EXTRA
FN ghost_reply
    xor eax, eax
    cmp [rip + gh_req_ext], rdi
    jne 9f
    cmp [rip + gh_req_id], rsi
    jne 9f
    mov qword ptr [rip + gh_req_ext], 0
    test edx, edx
    jz 8f
    PROLOGUE 64
    mov [rsp], rdi              # ext
    mov rbx, rcx
    lea r12, [rcx + r8]
    mov r13, [rip + g_doc]
    test r13, r13
    jz 7f
    mov rax, [r13 + DOC_version]
    cmp rax, [rip + gh_req_ver]
    jne 7f                      # the text changed meanwhile: of no use
    mov rax, [r13 + DOC_cur]
    cmp rax, [rip + gh_req_caret]
    jne 7f
    call present_num
    test edx, edx
    jz 7f
    cmp rax, GH_ITEMS
    ja 7f
    mov r14, rax
1:  test r14, r14
    jz 7f
    dec r14
    xor r15d, r15d
2:  cmp r15d, 6
    jae 3f
    call present_num
    test edx, edx
    jz 7f
    mov [rsp + 8 + r15*8], rax
    inc r15d
    jmp 2b
3:  # [rsp+8..40]: L1 C1 L2 C2 TEXT_LEN EXTRA_LEN
    mov rax, [rsp + 40]
    add rax, [rsp + 48]
    mov rcx, r12
    sub rcx, rbx
    cmp rax, rcx
    ja 7f
    mov rdi, r13
    lea rsi, [rsp]
    call ghost_try              # -> eax 1 shown
    mov r15d, eax
    mov rax, [rsp + 40]
    add rax, [rsp + 48]
    add rbx, rax
    test r15d, r15d
    jnz 6f
    jmp 1b
6:  mov dword ptr [rip + g_dirty], 1
7:  mov eax, 1
    EPILOGUE
8:  mov eax, 1
9:  ret

# ghost_try(doc, frame; rbx the item's text) -> eax 1 when the item fits the caret and shows; frame
# is ghost_reply's: [0] ext, [8..48] L1 C1 L2 C2 TEXT_LEN EXTRA_LEN
ghost_try:
    PROLOGUE 32
    mov r13, rdi
    mov r14, rsi
    mov rax, [r14 + 40]
    cmp rax, GH_TEXT_MAX
    ja 8f
    test rax, rax
    jz 8f
    cmp qword ptr [r14 + 48], GH_EXTRA_MAX
    ja 8f
    # the range in the text
    mov rdi, r13
    mov rsi, [r14 + 8]
    mov rdx, [r14 + 16]
    call mark_pos
    test rax, rax
    js 8f
    mov [rsp], rax              # start
    mov rdi, r13
    mov rsi, [r14 + 24]
    mov rdx, [r14 + 32]
    call mark_pos
    test rax, rax
    js 8f
    mov [rsp + 8], rax          # end
    mov rcx, [r13 + DOC_cur]
    cmp rcx, [rsp]
    jb 8f
    cmp rcx, rax
    ja 8f
    # the text before the caret is TEXT's start
    mov rdx, rcx
    sub rdx, [rsp]              # bytes before the caret
    cmp rdx, [r14 + 40]
    ja 8f
    mov [rsp + 16], rdx
    mov rdi, rdx
    inc rdi
    call mem_alloc
    mov r15, rax
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 16]
    mov rcx, r15
    call doc_copy
    mov rdi, r15
    mov rsi, [rsp + 16]
    mov rdx, rbx
    mov rcx, [rsp + 16]
    call str_eq
    push rax
    push rax
    mov rdi, r15
    call mem_free
    pop rax
    pop rax
    test eax, eax
    jz 8f
    # the text after the caret is the end of the rest
    mov rdx, [rsp + 8]
    sub rdx, [r13 + DOC_cur]    # bytes after the caret
    mov rcx, [r14 + 40]
    sub rcx, [rsp + 16]         # the rest's length
    cmp rdx, rcx
    ja 8f
    mov [rsp + 24], rdx
    mov rdi, rdx
    inc rdi
    call mem_alloc
    mov r15, rax
    mov rdi, r13
    mov rsi, [r13 + DOC_cur]
    mov rdx, [rsp + 24]
    mov rcx, r15
    call doc_copy
    mov rsi, [r14 + 40]
    sub rsi, [rsp + 24]
    lea rdx, [rbx + rsi]        # the text's last bytes
    mov rdi, r15
    mov rsi, [rsp + 24]
    mov rcx, rsi
    call str_eq
    push rax
    push rax
    mov rdi, r15
    call mem_free
    pop rax
    pop rax
    test eax, eax
    jz 8f
    # the ghost: what is left between them, at most GH_LINES lines
    mov rcx, [r14 + 40]
    sub rcx, [rsp + 16]
    sub rcx, [rsp + 24]
    jz 8f
    mov rdx, rbx
    add rdx, [rsp + 16]
    xor eax, eax
    xor r8d, r8d
1:  cmp r8, rcx
    jae 2f
    cmp byte ptr [rdx + r8], 10
    jne 11f
    inc eax
11: inc r8
    jmp 1b
2:  cmp eax, GH_LINES
    jae 8f
    # it shows
    push rcx
    push rcx
    call ghost_dismiss
    pop rcx
    pop rcx
    mov [rip + gh_glen], rcx
    mov rax, [rsp + 16]
    mov [rip + gh_off], rax
    mov rdi, rbx
    mov rsi, [r14 + 40]
    call mem_dup
    mov [rip + gh_text], rax
    mov rax, [r14 + 40]
    mov [rip + gh_tlen], rax
    mov rdi, rbx
    add rdi, [r14 + 40]
    mov rsi, [r14 + 48]
    call mem_dup
    mov [rip + gh_extra], rax
    mov rax, [r14 + 48]
    mov [rip + gh_xlen], rax
    mov rax, [rsp]
    mov [rip + gh_start], rax
    mov rax, [rsp + 8]
    mov [rip + gh_end], rax
    mov rax, [r14]
    mov [rip + gh_ext], rax
    mov [rip + gh_doc], r13
    mov rax, [r13 + DOC_version]
    mov [rip + gh_ver], rax
    mov rax, [r13 + DOC_cur]
    mov [rip + gh_caret], rax
    call ghost_layout
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- accepting ----------------

# FN ghost_key(keysym, cp, mods) -> eax 1 taken: Tab takes the ghost, ctrl+Right its next word,
# Escape dismisses it
FN ghost_key
    mov rax, [rip + gh_doc]
    test rax, rax
    jz 8f
    cmp rax, [rip + g_doc]
    jne 8f
    cmp edi, KEY_TAB
    jne 1f
    test edx, MOD_SHIFT | MOD_CTRL | MOD_ALT
    jnz 8f
    jmp ghost_accept
1:  cmp edi, KEY_ESCAPE
    jne 2f
    sub rsp, 8
    call ghost_dismiss
    add rsp, 8
    mov eax, 1
    ret
2:  cmp edi, KEY_RIGHT
    jne 8f
    and edx, MOD_SHIFT | MOD_CTRL | MOD_ALT
    cmp edx, MOD_CTRL
    jne 8f
    jmp ghost_accept_word
8:  xor eax, eax
    ret

# ghost_accept() -> eax 1: the item's text replaces its range, its edits are made at the exact
# version, its command runs; one undo step
ghost_accept:
    PROLOGUE 16
    mov rbx, [rip + gh_doc]
    mov rdi, rbx
    call doc_begin_group
    # the item's edits first (they are about the text as answered)
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + gh_ver]
    jne 1f
    call ghost_edits
1:  mov rdi, rbx
    mov rsi, [rip + gh_start]
    mov rdx, [rip + gh_end]
    sub rdx, rsi
    jz 2f
    mov ecx, EK_OTHER
    call doc_delete
2:  mov rdi, rbx
    mov rsi, [rip + gh_start]
    mov rdx, [rip + gh_text]
    mov rcx, [rip + gh_tlen]
    mov r8d, EK_OTHER
    call doc_insert
    mov rsi, [rip + gh_start]
    add rsi, [rip + gh_tlen]
    mov rdi, rbx
    xor edx, edx
    call ed_set_cursor
    mov rdi, rbx
    call doc_end_group
    # its command
    mov rdi, [rip + gh_extra]
    mov rsi, [rip + gh_xlen]
    lea rdx, [rip + .Ls_command]
    call extra_find
    test rax, rax
    jz 3f
    mov rdi, [rip + gh_ext]
    mov rsi, rax
    call cmdref_parse
    test rax, rax
    jz 3f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, [rbx + DOC_id]
    call cmdref_invoke
    mov rdi, [rsp]
    call cmdref_free
3:  mov rax, [rbx + DOC_version]
    mov [rip + gh_seen_ver], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + gh_seen_cur], rax
    call ghost_dismiss
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE

# ghost_edits(): the item's "edit L1 C1 L2 C2 LEN" records, from the last, in the document as it was
ghost_edits:
    PROLOGUE
    mov rdi, [rip + gh_extra]
    mov rsi, [rip + gh_xlen]
    call edits_read             # (inlay.s: ev_rec, positions 0-based)
    test rax, rax
    jle 9f
    mov r12, rax
1:  test r12, r12
    jz 9f
    dec r12
    imul r13, r12, 48
    lea rax, [rip + ev_rec]
    add r13, rax
    mov rbx, [rip + gh_doc]
    mov rdi, rbx
    mov rsi, [r13]
    inc rsi
    mov rdx, [r13 + 8]
    inc rdx
    call mark_pos
    test rax, rax
    js 1b
    mov r14, rax
    mov rdi, rbx
    mov rsi, [r13 + 16]
    inc rsi
    mov rdx, [r13 + 24]
    inc rdx
    call mark_pos
    test rax, rax
    js 1b
    cmp rax, r14
    jb 1b
    # an edit before the item's range moves it
    mov r15, rax
    sub r15, r14                # deleted
    mov rdx, r15
    test rdx, rdx
    jz 2f
    mov rdi, rbx
    mov rsi, r14
    mov ecx, EK_OTHER
    call doc_delete
2:  mov rdi, rbx
    mov rsi, r14
    mov rdx, [r13 + 32]
    mov rcx, [r13 + 40]
    mov r8d, EK_OTHER
    call doc_insert
    cmp r14, [rip + gh_start]
    ja 1b
    mov rax, [r13 + 40]
    sub rax, r15
    add [rip + gh_start], rax
    add [rip + gh_end], rax
    jmp 1b
9:  EPILOGUE

# ghost_accept_word() -> eax 1: the ghost's text up to the end of its next word is typed in
ghost_accept_word:
    PROLOGUE
    mov rbx, [rip + gh_doc]
    mov r12, [rip + gh_text]
    add r12, [rip + gh_off]
    mov r13, [rip + gh_glen]
    xor ecx, ecx
1:  cmp rcx, r13                # spaces first
    jae 3f
    movzx edi, byte ptr [r12 + rcx]
    cmp edi, ' '
    je 11f
    cmp edi, 9
    jne 2f
11: inc rcx
    jmp 1b
2:  cmp rcx, r13                # then the word
    jae 3f
    push rcx
    push rcx
    movzx edi, byte ptr [r12 + rcx]
    call is_ident
    pop rcx
    pop rcx
    test eax, eax
    jz 21f
    inc rcx
    jmp 2b
21: test rcx, rcx
    jnz 3f
    inc rcx                     # one character of punctuation
3:  mov r14, rcx
    mov rdi, rbx
    mov rsi, [rip + gh_caret]
    mov rdx, r12
    mov rcx, r14
    mov r8d, EK_TYPE
    call doc_insert
    mov rsi, [rip + gh_caret]
    add rsi, r14
    mov rdi, rbx
    xor edx, edx
    call ed_set_cursor          # ghost_frame then finds it typed and keeps the rest
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE

# FN ghost_ext_gone(ext): its ghost and request go
FN ghost_ext_gone
    cmp [rip + gh_req_ext], rdi
    jne 1f
    mov qword ptr [rip + gh_req_ext], 0
1:  cmp [rip + gh_ext], rdi
    jne 9f
    jmp ghost_dismiss
9:  ret

# FN ghost_dump(sb): "ghost L C TEXT" (line feeds as \n) for the ghost shown, or "ghost none"
FN ghost_dump
    PROLOGUE
    mov r12, rdi
    mov rdi, r12
    lea rsi, [rip + .Ls_ghost]
    call sb_push_cstr
    mov rbx, [rip + gh_doc]
    test rbx, rbx
    jz 8f
    mov rsi, [rip + gh_caret]
    call hl_put_pos_ext
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov r13, [rip + gh_text]
    add r13, [rip + gh_off]
    xor r14d, r14d
1:  cmp r14, [rip + gh_glen]
    jae 2f
    movzx esi, byte ptr [r13 + r14]
    inc r14
    cmp esi, 10
    jne 11f
    mov rdi, r12
    mov esi, '\\'
    call sb_push_byte
    mov esi, 'n'
11: mov rdi, r12
    call sb_push_byte
    jmp 1b
2:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Ls_none]
    call sb_push_cstr
    EPILOGUE

.section .rodata
.Lv_inline: .asciz "inline-complete "
.Lk_typed: .asciz " typed"
.Lk_invoked: .asciz " invoked"
.Ls_command: .asciz "command"
.Ls_ghost: .asciz "ghost "
.Ls_none: .asciz "none\n"
