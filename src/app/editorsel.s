# Multiple selections: the commands, keys and mouse gestures that make several selections, motion
# over all of them, and their drawing. The primary selection stays in DOC_cur/DOC_anchor and is the
# one added last; the others are DOC_selections' block in the order they were added
# (docselection.s), so removing the last selection makes the one before it primary. Edits at every
# selection are the engine's (docbatch.s and the planners in editortype.s and its neighbours).
.include "rhun.inc"

.equ SEL_MAX, DOC_SELECTIONS_MAX
.equ BOX_COLS_MAX, 1 << 20       # a column box reaches no further right than this

# this frame's secondary selections, sorted by start (sel_frame)
STRUCT
F SF_start, 8
F SF_end, 8
F SF_cur, 8
ENDSTRUCT SF_SIZE

.bss
.p2align 3
sel_pairs: .zero DMP_SIZE*(SEL_MAX + 1)   # {cur, anchor} pairs being built, the primary first
sel_cols: .zero 8*(SEL_MAX + 1)           # sel_move: the preferred column each one moved with
# the secondaries' preferred columns for vertical motion, by caret position, for one document version
sc_doc: .quad 0                 # DOC_id, 0 none
sc_ver: .quad 0
sc_n: .quad 0
sc_list: .zero 16*SEL_MAX       # {position, column}
sf_n: .quad 0
sf_list: .zero SF_SIZE*SEL_MAX
sf_carets: .quad 0              # the secondary carets the rows drew: x, y (dwords), position
sf_caret: .zero 16*SEL_MAX
# ctrl+d: a selection made from the word at the cursor looks for whole words of the same case
sn_doc: .quad 0                 # DOC_id, 0 none
sn_ver: .quad 0
sn_start: .quad 0
sn_end: .quad 0
# the column box: keyboard column select continues the box it left, shift+alt+drag builds one
box_doc: .quad 0                # DOC_id of the box the keys left, 0 none
box_ver: .quad 0
box_pos: .quad 0                # where it left the primary caret
box_line0: .quad 0              # the corner it grows from
box_col0: .quad 0
box_line1: .quad 0              # the corner that moves (the primary's)
box_col1: .quad 0
box_drag: .long 0               # a shift+alt drag is building the box
.p2align 3
am_before: .zero 8*SEL_MAX      # select all matches: the last matches before the primary (a ring)
am_after: .zero 8*SEL_MAX       # and the first ones from it

.text

# ---------------- the selection set ----------------

# sel_collect(doc, dest) -> rax count: every selection as {cur, anchor} pairs, the primary first
FN sel_collect
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_selections_count
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r13
    jae 9f
    mov rdi, rbx
    mov rsi, r14
    call doc_selections_get
    mov rcx, r14
    shl rcx, 4
    mov [r12 + rcx + DMP_cur], rax
    mov [r12 + rcx + DMP_anchor], rdx
    inc r14
    jmp 1b
9:  mov rax, r13
    EPILOGUE

# sel_install(doc, pairs, count) -> rax selections installed, 0 when a position was invalid.
# Overlapping selections merge (docranges.s); a merged one keeps the place in the order and the
# direction of the earliest of them, so the primary stays primary. At most SEL_MAX are kept.
FN sel_install
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, SEL_MAX
    jbe 1f
    mov r13, SEL_MAX
1:  mov rdi, rbx
    call doc_selections_count
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_ranges_new
    test rax, rax
    jz .Lsi_fail
    mov r14, rax
    xor r15d, r15d
.Lsi_direction:
    cmp r15, [r14 + DNS_count]
    jae .Lsi_order
    mov rax, r15
    shl rax, 5
    lea rdi, [r14 + rax + DNS_ranges]
    mov rax, [rdi + DMR_index]
    shl rax, 4
    mov rcx, [r12 + rax + DMP_cur]
    mov rdx, [r12 + rax + DMP_anchor]
    mov r8, rcx
    mov r9, rdx
    cmp r8, r9
    jbe 2f
    xchg r8, r9
2:  cmp r8, [rdi + DMR_start]
    jne 3f
    cmp r9, [rdi + DMR_end]
    jne 3f
    mov [rdi + DMR_caret], rcx  # unchanged: as it was
    jmp 4f
3:  mov rax, [rdi + DMR_end]    # merged: the caret at the end it pointed to
    cmp rcx, rdx
    jae 31f
    mov rax, [rdi + DMR_start]
31: mov [rdi + DMR_caret], rax
4:  inc r15
    jmp .Lsi_direction
.Lsi_order:
    lea rdi, [r14 + DNS_ranges]
    mov rsi, [r14 + DNS_count]
    mov edx, DMR_index
    call doc_ranges_sort
    lea r12, [rip + sel_pairs]  # the input was copied into the ranges
    xor ecx, ecx
5:  cmp rcx, [r14 + DNS_count]
    jae 6f
    mov rax, rcx
    shl rax, 5
    lea rdi, [r14 + rax + DNS_ranges]
    mov rax, rcx
    shl rax, 4
    mov rdx, [rdi + DMR_caret]
    mov [r12 + rax + DMP_cur], rdx
    mov rsi, [rdi + DMR_end]
    cmp rdx, rsi
    jne 51f
    mov rsi, [rdi + DMR_start]
51: mov [r12 + rax + DMP_anchor], rsi
    inc rcx
    jmp 5b
6:  mov r15, [r14 + DNS_count]
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, r15
    call doc_selections_set
    test eax, eax
    jz .Lsi_fail
    # a second selection ends a snippet session: its fields are about one caret
    cmp r15, 1
    jbe 7f
    cmp qword ptr [rsp], 1
    ja 7f
    mov rdi, rbx
    call snippet_forget
7:  mov dword ptr [rip + g_dirty], 1
    mov rax, r15
    EPILOGUE
.Lsi_fail:
    xor eax, eax
    EPILOGUE

# sel_normalize(doc) -> rax count: overlapping selections merge, equal carets become one
FN sel_normalize
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + sel_pairs]
    call sel_collect
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, rax
    call sel_install
    EPILOGUE

# sel_add(doc, cur, anchor) -> eax 1 when added: the new selection becomes primary
FN sel_add
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_selections_count
    cmp rax, SEL_MAX
    jae 8f
    mov rdi, rbx
    lea rsi, [rip + sel_pairs + DMP_SIZE]
    call sel_collect
    lea rdx, [rax + 1]
    mov [rip + sel_pairs + DMP_cur], r12
    mov [rip + sel_pairs + DMP_anchor], r13
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    call sel_install
    test rax, rax
    setnz al
    movzx eax, al
    EPILOGUE
8:  lea rdi, [rip + .Lsel_full]
    call app_toast
    xor eax, eax
    EPILOGUE

# sel_remove(doc, index): that selection goes (index 0, the primary: the one added before it is primary)
FN sel_remove
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rip + sel_pairs]
    call sel_collect
    mov r13, rax
    cmp r13, 1
    jbe 9f
    cmp r12, r13
    jae 9f
    mov rdi, r12
    shl rdi, 4
    lea rax, [rip + sel_pairs]
    add rdi, rax
    lea rsi, [rdi + DMP_SIZE]
    mov rdx, r13
    sub rdx, r12
    dec rdx
    shl rdx, 4
    call memmove
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    lea rdx, [r13 - 1]
    call sel_install
    mov qword ptr [rbx + DOC_prefx], -1
9:  EPILOGUE

# sel_collapse(doc): back to the primary selection alone
FN sel_collapse
    cmp qword ptr [rdi + DOC_selections], 0
    je 1f
    mov dword ptr [rip + g_dirty], 1
    jmp doc_selections_clear
1:  ret

# ed_single(): a command about one place (not written for several selections) collapses the active
# document's selections to the primary first, so it never acts beside a stale set
FN ed_single
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    jmp sel_collapse
1:  ret

# sel_escape(doc) -> eax 1 when Escape went to the selections: several collapse to the primary
FN sel_escape
    xor eax, eax
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + DOC_selections], 0
    je 1f
    PROLOGUE
    call sel_collapse
    call ed_touch
    mov eax, 1
    EPILOGUE
1:  ret

# ---------------- motion ----------------

# sel_move(kind, extend): ed_move's motion for every selection of the active document. Each moves
# alone as the primary would, with its own preferred column; overlapping ones then merge.
FN sel_move
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    mov r12d, edi
    mov r13d, esi
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    call sel_collect
    mov r14, rax
    mov rax, [rbx + DOC_selections]
    mov [rsp], rax              # the block, set aside while each moves alone
    mov qword ptr [rbx + DOC_selections], 0
    mov rax, [rbx + DOC_prefx]
    mov [rsp + 8], rax
    xor r15d, r15d
.Lsm_each:
    cmp r15, r14
    jae .Lsm_moved
    mov rax, r15
    shl rax, 4
    lea rcx, [rip + sel_pairs]
    mov rdx, [rcx + rax + DMP_cur]
    mov [rbx + DOC_cur], rdx
    mov rdx, [rcx + rax + DMP_anchor]
    mov [rbx + DOC_anchor], rdx
    mov rax, [rsp + 8]
    test r15, r15
    jz 1f
    cmp rax, -1                 # the primary's column is gone: so are the others'
    je 1f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call sel_col_lookup
1:  mov [rbx + DOC_prefx], rax
    mov edi, r12d
    mov esi, r13d
    call ed_move
    mov rax, r15
    shl rax, 4
    lea rcx, [rip + sel_pairs]
    mov rdx, [rbx + DOC_cur]
    mov [rcx + rax + DMP_cur], rdx
    mov rdx, [rbx + DOC_anchor]
    mov [rcx + rax + DMP_anchor], rdx
    lea rcx, [rip + sel_cols]
    mov rdx, [rbx + DOC_prefx]
    mov [rcx + r15*8], rdx
    inc r15
    jmp .Lsm_each
.Lsm_moved:
    mov rax, [rsp]
    mov [rbx + DOC_selections], rax
    mov rdi, rbx
    mov rsi, r14
    call sel_col_store
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, r14
    call sel_install
    mov rax, [rip + sel_cols]
    mov [rbx + DOC_prefx], rax
    call ed_touch
    EPILOGUE

# sel_col_store(doc, count): the secondaries' preferred columns (sel_cols) by where their carets are
sel_col_store:
    mov rax, [rdi + DOC_id]
    mov [rip + sc_doc], rax
    mov rax, [rdi + DOC_version]
    mov [rip + sc_ver], rax
    lea rax, [rsi - 1]
    mov [rip + sc_n], rax
    lea r8, [rip + sel_pairs]
    lea r9, [rip + sel_cols]
    lea r10, [rip + sc_list]
    mov ecx, 1
1:  cmp rcx, rsi
    jae 2f
    mov rax, rcx
    shl rax, 4
    mov rdx, [r8 + rax + DMP_cur]
    mov [r10 + rax - 16], rdx
    mov rdx, [r9 + rcx*8]
    mov [r10 + rax - 8], rdx
    inc rcx
    jmp 1b
2:  ret

# sel_col_lookup(doc, caret position) -> rax the preferred column a secondary there moved with, or -1
sel_col_lookup:
    mov rax, [rdi + DOC_id]
    cmp rax, [rip + sc_doc]
    jne 8f
    mov rax, [rdi + DOC_version]
    cmp rax, [rip + sc_ver]
    jne 8f
    lea r8, [rip + sc_list]
    xor ecx, ecx
1:  cmp rcx, [rip + sc_n]
    jae 8f
    mov rax, rcx
    shl rax, 4
    cmp [r8 + rax], rsi
    je 2f
    inc rcx
    jmp 1b
2:  mov rax, [r8 + rax + 8]
    ret
8:  mov rax, -1
    ret

# ---------------- commands ----------------

# Add Cursor Above / Below: a caret a line above the topmost caret (below the bottommost) at the
# primary's preferred column; it becomes the primary
FN cmd_add_cursor_above
    mov edi, -1
    jmp sel_add_vertical
FN cmd_add_cursor_below
    mov edi, 1
sel_add_vertical:
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    movsxd r12, edi
    mov rax, [rbx + DOC_prefx]
    cmp rax, -1
    jne 1f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
1:  mov [rsp], rax              # the column
    mov rdi, rbx
    call doc_selections_count
    mov r13, rax
    xor r14d, r14d
    mov r15, -1                 # the outermost caret's line
2:  cmp r14, r13
    jae 4f
    mov rdi, rbx
    mov rsi, r14
    call doc_selections_get
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    inc r14
    cmp r15, -1
    je 3f
    test r12, r12
    js 21f
    cmp rax, r15
    jbe 2b
    jmp 3f
21: cmp rax, r15
    jae 2b
3:  mov r15, rax
    jmp 2b
4:  add r15, r12
    js 9f
    cmp r15, [rbx + DOC_nlines]
    jae 9f
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rsp]
    call doc_pos_at_col
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rax
    call sel_add
    test eax, eax
    jz 9f
    mov rax, [rsp]
    mov [rbx + DOC_prefx], rax
    call ed_touch
9:  EPILOGUE

# Remove Last Selection: the primary goes, the one added before it is primary
FN cmd_remove_last_selection
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + DOC_selections], 0
    je 9f
    mov rdi, rbx
    xor esi, esi
    call sel_remove
    call ed_touch
9:  EPILOGUE

# sel_text(doc, start, end) -> rax owned copy of the bytes (the search moves the gap), rdx length
sel_text:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    sub r13, r12
    lea rdi, [r13 + 1]
    call mem_alloc
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call doc_copy
    mov rax, r14
    mov rdx, r13
    EPILOGUE

# sel_word_mode(doc) -> eax 1 when ctrl+d's matches are whole words of the same case: the first of
# these selections came from the word at the cursor, and the text has not changed since
sel_word_mode:
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    mov rcx, [rbx + DOC_id]
    cmp rcx, [rip + sn_doc]
    jne 9f
    mov rcx, [rbx + DOC_version]
    cmp rcx, [rip + sn_ver]
    jne 9f
    call doc_selections_count
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, r12
    jae 8f
    mov rdi, rbx
    mov rsi, r13
    call doc_selections_get
    inc r13
    cmp rax, rdx
    jbe 2f
    xchg rax, rdx
2:  cmp rax, [rip + sn_start]
    jne 1b
    cmp rdx, [rip + sn_end]
    jne 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# sel_word_note(doc, start, end): this selection came from the word at the cursor
sel_word_note:
    mov rax, [rdi + DOC_id]
    mov [rip + sn_doc], rax
    mov rax, [rdi + DOC_version]
    mov [rip + sn_ver], rax
    mov [rip + sn_start], rsi
    mov [rip + sn_end], rdx
    ret

# sel_overlaps(doc, start, end) -> eax 1 when a selection shares a byte with [start, end) or equals it
sel_overlaps:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_selections_count
    mov r14, rax
    xor r15d, r15d
1:  cmp r15, r14
    jae 8f
    mov rdi, rbx
    mov rsi, r15
    call doc_selections_get
    inc r15
    cmp rax, rdx
    jbe 2f
    xchg rax, rdx
2:  cmp rax, r12
    jne 3f
    cmp rdx, r13
    je 7f
3:  cmp rax, r13
    jae 1b
    cmp rdx, r12
    jbe 1b
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sel_whole_word(doc, start, end) -> eax 1 when no identifier character touches [start, end)
sel_whole_word:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz 1f
    lea rsi, [r12 - 1]
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jnz 8f
1:  mov rdi, rbx
    call doc_len
    cmp r13, rax
    jae 2f
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jnz 8f
2:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sel_find_next(doc, needle, length, from, word) -> rax the next match at or after from, wrapping
# to the start, that overlaps no selection (and is a whole word when word is set), -1 when none.
# The needle must not point into the document.
sel_find_next:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx              # from
    mov [rsp + 8], r8d          # word
    mov dword ptr [rsp + 12], 0 # wrapped
    mov r14, rcx                # where the search goes on
    test r13, r13
    jz 8f
1:  mov rdi, rbx
    call doc_len
    mov r15, rax
    cmp r14, r15
    ja 5f
    mov rdi, rbx
    call doc_contiguous
    lea rdi, [rax + r14]
    mov rsi, r15
    sub rsi, r14
    mov rdx, r12
    mov rcx, r13
    call str_find
    test rax, rax
    js 5f
    add rax, r14
    cmp dword ptr [rsp + 12], 0
    je 2f
    cmp rax, [rsp]              # past the wrap: up to where it began
    jae 8f
2:  mov [rsp + 16], rax
    lea r14, [rax + 1]
    cmp dword ptr [rsp + 8], 0
    je 3f
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rax + r13]
    call sel_whole_word
    test eax, eax
    jz 1b
3:  mov rdi, rbx
    mov rsi, [rsp + 16]
    lea rdx, [rsi + r13]
    call sel_overlaps
    test eax, eax
    jnz 1b
    mov rax, [rsp + 16]
    EPILOGUE
5:  cmp dword ptr [rsp + 12], 0
    jne 8f
    mov dword ptr [rsp + 12], 1
    xor r14d, r14d
    jmp 1b
8:  mov rax, -1
    EPILOGUE

# sel_words(doc) -> eax 1 when it selected words: every empty selection on a word becomes that word
# (ctrl+d and ctrl+shift+l with nothing selected); the primary's word is remembered for whole-word
# matches. 0 when the primary is not on a word.
sel_words:
    PROLOGUE 16
    mov rbx, rdi
    mov rsi, [rbx + DOC_cur]
    call word_at
    cmp rax, rdx
    je 8f
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    call sel_collect
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, r12
    jae 3f
    mov r14, r13
    shl r14, 4
    lea rax, [rip + sel_pairs]
    add r14, rax
    mov rsi, [r14 + DMP_cur]
    cmp rsi, [r14 + DMP_anchor]
    jne 2f
    mov rdi, rbx
    call word_at
    cmp rax, rdx
    je 2f
    mov [r14 + DMP_anchor], rax
    mov [r14 + DMP_cur], rdx
2:  inc r13
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, r12
    call sel_install
    mov rdi, rbx
    call ed_sel
    mov rsi, rax
    mov rdi, rbx
    call sel_word_note
    call ed_touch
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Select Word or Add Next Match (ctrl+d): nothing selected selects the word at the cursor; else the
# next occurrence of the primary's text after it becomes a new primary selection
FN cmd_select_next
    xor esi, esi
    jmp sel_next
# Move Selection to Next Match: the primary moves to the next occurrence, the others stay
FN sel_next_skip
    mov esi, 1
sel_next:
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov [rsp + 24], esi         # skip
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 1f
    mov rdi, rbx
    call sel_words
    jmp 9f
1:  mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call sel_word_mode
    mov [rsp + 16], eax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call sel_text
    mov r14, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, r13
    mov r8d, [rsp + 16]
    call sel_find_next
    mov [rsp], rax
    mov rdi, r14
    call mem_free
    mov rax, [rsp]
    test rax, rax
    js 8f
    lea rsi, [rax + r15]
    mov rdx, rax
    cmp dword ptr [rsp + 24], 0
    jne 2f
    mov rdi, rbx
    call sel_add
    jmp 3f
2:  mov [rbx + DOC_cur], rsi
    mov [rbx + DOC_anchor], rdx
    mov rdi, rbx
    call sel_normalize
3:  mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp 9f
8:  lea rdi, [rip + .Lsel_none]
    call app_toast
9:  EPILOGUE

# Select All Matches (ctrl+shift+l): every occurrence of the primary's text (of the word at the
# cursor when nothing is selected) becomes a selection; past SEL_MAX, the ones nearest the primary
FN cmd_select_all_matches
    PROLOGUE 80
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Lam_ret
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 1f
    mov rdi, rbx
    call sel_words
    test eax, eax
    jz .Lam_ret
    mov rdi, rbx
    call ed_sel
1:  mov [rsp], rax              # the primary's start
    mov [rsp + 8], rdx          # and end
    mov rdi, rbx
    call sel_word_mode
    mov [rsp + 16], eax
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call sel_text
    mov r12, rax                # needle (owned)
    mov r13, rdx
    xor eax, eax
    mov [rsp + 24], rax         # matches before the primary (the last SEL_MAX kept in a ring)
    mov [rsp + 32], rax         # matches after it
    mov [rsp + 40], rax         # where the search goes on
    mov [rsp + 48], rax         # 1: matches were left out
.Lam_scan:
    mov rdi, rbx
    call doc_len
    mov r15, rax
    mov r14, [rsp + 40]
    cmp r14, r15
    ja .Lam_pick
    mov rdi, rbx
    call doc_contiguous
    lea rdi, [rax + r14]
    mov rsi, r15
    sub rsi, r14
    mov rdx, r12
    mov rcx, r13
    call str_find
    test rax, rax
    js .Lam_pick
    lea r14, [rax + r14]
    lea rax, [r14 + 1]
    mov [rsp + 40], rax
    cmp dword ptr [rsp + 16], 0
    je 2f
    mov rdi, rbx
    mov rsi, r14
    lea rdx, [r14 + r13]
    call sel_whole_word
    test eax, eax
    jz .Lam_scan
2:  lea rax, [r14 + r13]        # matches do not overlap each other
    mov [rsp + 40], rax
    cmp rax, [rsp]
    jbe 3f
    cmp r14, [rsp + 8]
    jb .Lam_scan                # the primary itself, or across it
    mov rax, [rsp + 32]
    cmp rax, SEL_MAX - 1
    jae .Lam_more
    lea rcx, [rip + am_after]
    mov [rcx + rax*8], r14
    inc qword ptr [rsp + 32]
    jmp .Lam_scan
3:  mov rax, [rsp + 24]
    and eax, SEL_MAX - 1
    lea rcx, [rip + am_before]
    mov [rcx + rax*8], r14
    inc qword ptr [rsp + 24]
    jmp .Lam_scan
.Lam_more:
    mov qword ptr [rsp + 48], 1
.Lam_pick:
    mov rdi, r12
    call mem_free
    # the primary first, then the nearest on either side
    lea r15, [rip + sel_pairs]
    mov rax, [rsp]
    mov [r15 + DMP_anchor], rax
    mov rax, [rsp + 8]
    mov [r15 + DMP_cur], rax
    mov r14d, 1                 # pairs
    mov rax, [rsp + 24]
    cmp rax, SEL_MAX
    jbe 4f
    mov qword ptr [rsp + 48], 1
    mov eax, SEL_MAX
4:  mov [rsp + 56], rax         # before ones kept
    xor eax, eax
    mov [rsp + 64], rax         # before ones taken (the newest first)
    mov [rsp + 72], rax         # after ones taken
.Lam_take:
    cmp r14, SEL_MAX
    jae .Lam_install
    mov rcx, [rsp + 72]
    cmp rcx, [rsp + 32]
    jae .Lam_before             # no after ones left
    lea rax, [rip + am_after]
    mov rdx, [rax + rcx*8]
    mov rax, [rsp + 64]
    cmp rax, [rsp + 56]
    jae .Lam_after              # no before ones left
    call .Lam_newest
    sub rdx, [rsp + 8]          # the gap after: the match's start - the primary's end
    mov r8, [rsp]
    sub r8, rax
    sub r8, r13                 # the gap before: the primary's start - the match's end
    cmp rdx, r8
    jbe .Lam_after
.Lam_before:
    mov rax, [rsp + 64]
    cmp rax, [rsp + 56]
    jae .Lam_install
    call .Lam_newest
    inc qword ptr [rsp + 64]
    jmp .Lam_add
.Lam_after:
    mov rcx, [rsp + 72]
    lea r8, [rip + am_after]
    mov rax, [r8 + rcx*8]
    inc qword ptr [rsp + 72]
.Lam_add:
    mov rcx, r14
    shl rcx, 4
    mov [r15 + rcx + DMP_anchor], rax
    add rax, r13
    mov [r15 + rcx + DMP_cur], rax
    inc r14
    jmp .Lam_take
.Lam_install:
    mov rax, [rsp + 64]
    cmp rax, [rsp + 24]
    jb 5f
    mov rax, [rsp + 72]
    cmp rax, [rsp + 32]
    jae 6f
5:  mov qword ptr [rsp + 48], 1
6:  mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call sel_install
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    cmp qword ptr [rsp + 48], 0
    je .Lam_ret
    lea rdi, [rip + .Lsel_nearest]
    call app_toast
.Lam_ret:
    EPILOGUE
# .Lam_newest -> rax the newest before match not taken yet ([rsp + 64] of them are; frame + 8)
.Lam_newest:
    mov rax, [rsp + 8 + 24]
    sub rax, [rsp + 8 + 64]
    dec rax
    and eax, SEL_MAX - 1
    lea r8, [rip + am_before]
    mov rax, [r8 + rax*8]
    ret

# Add Cursors to Line Ends (shift+alt+i): a caret at the end of every line a selection covers but its
# last, and one where the selection ends on that last line unless it ends at its start
FN cmd_cursors_to_line_ends
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call doc_selections_count
    mov [rsp], rax              # selections
    mov qword ptr [rsp + 8], 0  # which one
    mov qword ptr [rsp + 16], 0 # carets the primary gave
    mov qword ptr [rsp + 24], 0 # past SEL_MAX
    xor r15d, r15d              # carets
    # the carets go after the current selections in sel_pairs' last part: built at its start
.Lle_sel:
    mov rax, [rsp + 8]
    cmp rax, [rsp]
    jae .Lle_done
    mov rdi, rbx
    mov rsi, rax
    call doc_selections_get
    cmp rax, rdx
    je .Lle_next                # empty: none
    jb 1f
    xchg rax, rdx
1:  mov r12, rax                # start
    mov r13, rdx                # end
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r14, rax                # line
    mov rdi, rbx
    mov rsi, r13
    call doc_line_of
    mov [rsp + 32], rax         # last line
2:  cmp r14, [rsp + 32]
    jae 3f
    mov rdi, rbx
    mov rsi, r14
    call doc_line_end
    call .Lle_put
    inc r14
    jmp 2b
3:  mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    cmp r13, rax
    je .Lle_next
    mov rax, r13
    call .Lle_put
.Lle_next:
    cmp qword ptr [rsp + 8], 0
    jne 4f
    mov [rsp + 16], r15
4:  inc qword ptr [rsp + 8]
    jmp .Lle_sel
.Lle_done:
    test r15, r15
    jz 9f
    # the primary's last caret is primary
    mov rax, [rsp + 16]
    test rax, rax
    jz 5f
    dec rax
    shl rax, 4
    lea rcx, [rip + sel_pairs]
    mov rdx, [rcx + rax]
    mov r8, [rcx]
    mov [rcx], rdx
    mov [rcx + DMP_anchor], rdx
    mov [rcx + rax], r8
    mov [rcx + rax + DMP_anchor], r8
5:  mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, r15
    call sel_install
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    cmp qword ptr [rsp + 24], 0
    je 9f
    lea rdi, [rip + .Lsel_full]
    call app_toast
9:  EPILOGUE
# .Lle_put(rax position): one more caret (r15 counts them)
.Lle_put:
    cmp r15, SEL_MAX
    jae 1f
    mov rcx, r15
    shl rcx, 4
    lea rdx, [rip + sel_pairs]
    mov [rdx + rcx + DMP_cur], rax
    mov [rdx + rcx + DMP_anchor], rax
    inc r15
    ret
1:  mov qword ptr [rsp + 8 + 24], 1
    ret

# Column Select Up/Down/Left/Right (ctrl+shift+alt+arrows): a box of selections, one a line, grows
# from the primary caret; the keys continue the box they left
FN cmd_column_select_up
    mov rdi, -1
    xor esi, esi
    jmp sel_column
FN cmd_column_select_down
    mov edi, 1
    xor esi, esi
    jmp sel_column
FN cmd_column_select_left
    xor edi, edi
    mov rsi, -1
    jmp sel_column
FN cmd_column_select_right
    xor edi, edi
    mov esi, 1
sel_column:
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov r12, rdi
    mov r13, rsi
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + box_doc]
    jne 1f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + box_ver]
    jne 1f
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + box_pos]
    je 2f
1:  mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov [rip + box_line0], rax
    mov [rip + box_line1], rax
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
    mov [rip + box_col0], rax
    mov [rip + box_col1], rax
2:  mov rax, [rip + box_line1]
    add rax, r12
    js 3f
    cmp rax, [rbx + DOC_nlines]
    jae 3f
    mov [rip + box_line1], rax
3:  mov rax, [rip + box_col1]
    add rax, r13
    js 4f
    cmp rax, BOX_COLS_MAX
    ja 4f
    mov [rip + box_col1], rax
4:  mov rdi, rbx
    call sel_box_build
    call ed_touch
9:  EPILOGUE

# sel_box_build(doc): one selection a line between the box's corners, from column col0 to col1
# (tabs expanded); lines that end left of the box are skipped, but the moving corner's. That one is
# primary; the box is remembered for the next column key.
sel_box_build:
    PROLOGUE 32
    mov rbx, rdi
    mov rax, [rip + box_col0]
    mov rcx, [rip + box_col1]
    cmp rax, rcx
    jbe 1f
    xchg rax, rcx
1:  mov [rsp], rax              # left column
    mov r12, [rip + box_line1]  # line
    mov r13, 1                  # step toward line0
    cmp r12, [rip + box_line0]
    jbe 2f
    mov r13, -1
2:  xor r14d, r14d              # pairs
    lea r15, [rip + sel_pairs]
.Lbb_line:
    cmp r14, SEL_MAX
    jae .Lbb_done
    cmp r12, [rip + box_line1]
    je 3f
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov rdi, rbx
    mov rsi, rax
    call doc_col_of
    cmp rax, [rsp]
    jb .Lbb_skip
3:  mov rdi, rbx
    mov rsi, r12
    mov rdx, [rip + box_col0]
    call doc_pos_at_col
    mov rcx, r14
    shl rcx, 4
    mov [r15 + rcx + DMP_anchor], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rip + box_col1]
    call doc_pos_at_col
    mov rcx, r14
    shl rcx, 4
    mov [r15 + rcx + DMP_cur], rax
    inc r14
.Lbb_skip:
    cmp r12, [rip + box_line0]
    je .Lbb_done
    add r12, r13
    jmp .Lbb_line
.Lbb_done:
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call sel_install
    mov rax, [rbx + DOC_id]
    mov [rip + box_doc], rax
    mov rax, [rbx + DOC_version]
    mov [rip + box_ver], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + box_pos], rax
    mov qword ptr [rbx + DOC_prefx], -1
    EPILOGUE

# ---------------- mouse ----------------

# sel_press(doc, pos, clicks) -> eax 0 for the editor's own click (a plain click collapses the
# selections first), 1 when handled and a drag may follow, 2 when handled without a drag.
# The multi-cursor modifier (alt, or ctrl with multi_cursor_modifier = ctrl): a click adds a caret
# or removes the caret it is on, a double click adds the word; with shift a drag selects a box.
FN sel_press
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov dword ptr [rip + box_drag], 0
    mov eax, MOD_ALT
    cmp dword ptr [rip + cfg_multi_cursor_modifier], 0
    je 1f
    mov eax, MOD_CTRL
1:  mov ecx, [rip + g_mods]
    test ecx, eax
    jz .Lsp_plain
    test ecx, MOD_SHIFT
    jnz .Lsp_box
    cmp r13d, 2
    je .Lsp_word
    cmp r13d, 1
    jne .Lsp_plain
    # a caret here goes (unless it is the only one), else one is added
    mov rdi, rbx
    call doc_selections_count
    mov r14, rax
    xor r15d, r15d
2:  cmp r15, r14
    jae 4f
    mov rdi, rbx
    mov rsi, r15
    call doc_selections_get
    cmp rax, r12
    jne 3f
    cmp r14, 1
    je .Lsp_done
    mov rdi, rbx
    mov rsi, r15
    call sel_remove
    jmp .Lsp_done
3:  inc r15
    jmp 2b
4:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r12
    call sel_add
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    mov dword ptr [rip + g_reveal], 0
    mov eax, 1
    EPILOGUE
.Lsp_word:
    # the second click of a double click: the caret the first one added becomes its word
    mov rdi, rbx
    mov rsi, r12
    call word_at
    cmp rax, rdx
    je .Lsp_done
    cmp [rbx + DOC_cur], r12
    jne 5f
    cmp [rbx + DOC_anchor], r12
    jne 5f
    mov [rbx + DOC_anchor], rax
    mov [rbx + DOC_cur], rdx
    mov rdi, rbx
    call sel_normalize
    jmp .Lsp_done
5:  mov rdi, rbx
    mov rsi, rdx
    mov rdx, rax
    call sel_add
.Lsp_done:
    call ed_touch
    mov dword ptr [rip + g_reveal], 0
    mov eax, 2
    EPILOGUE
.Lsp_box:
    mov rdi, rbx
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call sel_box_point
    mov [rip + box_line0], rax
    mov [rip + box_line1], rax
    mov [rip + box_col0], rdx
    mov [rip + box_col1], rdx
    mov dword ptr [rip + box_drag], 1
    mov rdi, rbx
    call sel_box_build
    call ed_touch
    mov dword ptr [rip + g_reveal], 0
    mov eax, 1
    EPILOGUE
.Lsp_plain:
    mov rdi, rbx
    call sel_collapse
    xor eax, eax
    EPILOGUE

# sel_box_point(doc, px, py) -> rax line, rdx column under the point (past the line's end too)
sel_box_point:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    call pos_at_point
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    mov r15, rax
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne 2f
    mov eax, r12d
    sub eax, [rip + g_ed_tx]
    add eax, [rbx + DOC_scrollx]
    mov ecx, [rip + g_cw]
    shr ecx, 1
    add eax, ecx
    jns 1f
    xor eax, eax
1:  xor edx, edx
    div dword ptr [rip + g_cw]
    mov edx, eax
    mov rax, r15
    EPILOGUE
2:  mov rdi, rbx
    mov rsi, r14
    call doc_col_of
    mov rdx, rax
    mov rax, r15
    EPILOGUE

# sel_drag(doc, px, py) -> eax 1 when the drag builds a column box (the editor's drag stays out)
FN sel_drag
    xor eax, eax
    cmp dword ptr [rip + box_drag], 0
    je 9f
    PROLOGUE
    mov rbx, rdi
    call sel_box_point
    cmp rax, [rip + box_line1]
    jne 1f
    cmp rdx, [rip + box_col1]
    je 2f
1:  mov [rip + box_line1], rax
    mov [rip + box_col1], rdx
    mov rdi, rbx
    call sel_box_build
2:  mov eax, 1
    EPILOGUE
9:  ret

# sel_drag_end(doc): the button came up: a box is done, an alt+drag's selection merges with others
FN sel_drag_end
    mov dword ptr [rip + box_drag], 0
    cmp qword ptr [rdi + DOC_selections], 0
    je 1f
    jmp sel_normalize
1:  ret

# ---------------- drawing ----------------

# sel_frame(doc): before the rows are drawn: the secondary selections sorted by start
FN sel_frame
    PROLOGUE
    mov qword ptr [rip + sf_n], 0
    mov qword ptr [rip + sf_carets], 0
    mov r12, [rdi + DOC_selections]
    test r12, r12
    jz 9f
    mov r13, [r12 + DMS_count]
    xor r14d, r14d
    lea r15, [rip + sf_list]
1:  cmp r14, r13
    jae 9f
    cmp r14, SEL_MAX
    jae 9f
    mov rax, r14
    shl rax, 4
    mov rcx, [r12 + rax + DMS_DATA + DMP_cur]
    mov rdx, [r12 + rax + DMS_DATA + DMP_anchor]
    mov r8, rcx
    mov r9, rdx
    cmp r8, r9
    jbe 2f
    xchg r8, r9
2:  mov rbx, [rip + sf_n]       # insertion: later starts move up
3:  test rbx, rbx
    jz 4f
    imul rax, rbx, SF_SIZE
    cmp [r15 + rax - SF_SIZE + SF_start], r8
    jbe 4f
    mov rdx, [r15 + rax - SF_SIZE + SF_start]
    mov [r15 + rax + SF_start], rdx
    mov rdx, [r15 + rax - SF_SIZE + SF_end]
    mov [r15 + rax + SF_end], rdx
    mov rdx, [r15 + rax - SF_SIZE + SF_cur]
    mov [r15 + rax + SF_cur], rdx
    dec rbx
    jmp 3b
4:  imul rax, rbx, SF_SIZE
    mov [r15 + rax + SF_start], r8
    mov [r15 + rax + SF_end], r9
    mov [r15 + rax + SF_cur], rcx
    inc qword ptr [rip + sf_n]
    inc r14
    jmp 1b
9:  EPILOGUE

# sel_first(position) -> rax index of the first of this frame's selections that ends at or after it
sel_first:
    xor eax, eax
    mov rcx, [rip + sf_n]
    lea r9, [rip + sf_list]
1:  cmp rax, rcx
    jae 9f
    lea rdx, [rax + rcx]
    shr rdx, 1
    imul r8, rdx, SF_SIZE
    cmp [r9 + r8 + SF_end], rdi
    jae 2f
    lea rax, [rdx + 1]
    jmp 1b
2:  mov rcx, rdx
    jmp 1b
9:  ret

# sel_row(line text, line start, row from, row to, x of column 0, y): draw_line's row of the active
# document: the secondary selections' fills, as the primary's, and where their carets go
FN sel_row
    PROLOGUE 48
    cmp qword ptr [rip + sf_n], 0
    je .Lsr_ret
    mov r12, rdi
    mov r13, rsi
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8d
    mov [rsp + 20], r9d
    lea rdi, [r13 + rdx]
    call sel_first
    mov r14, rax
.Lsr_next:
    cmp r14, [rip + sf_n]
    jae .Lsr_ret
    imul rax, r14, SF_SIZE
    lea r15, [rip + sf_list]
    add r15, rax
    mov rax, [rsp + 8]
    add rax, r13                # row end
    cmp [r15 + SF_start], rax
    ja .Lsr_ret
    mov rax, [r15 + SF_start]
    cmp rax, [r15 + SF_end]
    je .Lsr_caret
    mov rcx, [rsp]
    add rcx, r13                # row start
    cmp rax, rcx
    cmovb rax, rcx              # a = max(S, row start)
    mov rdx, [rsp + 8]
    add rdx, r13
    mov r8, [r15 + SF_end]
    xor r9d, r9d                # an extra cell for the newline
    cmp r8, rdx
    jbe 1f
    mov r8, rdx                 # b = min(E, row end)
    cmp dword ptr [rip + dl_last], 0
    je 1f
    mov r9d, 1
1:  cmp rax, r8
    ja .Lsr_caret
    jb 2f
    test r9d, r9d
    jz .Lsr_caret
2:  mov [rsp + 24], r8
    mov [rsp + 32], r9d
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, rax
    sub rdx, r13
    call seg_cols
    mov [rsp + 36], eax         # start column
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 24]
    sub rdx, r13
    call seg_cols
    add eax, [rsp + 32]
    sub eax, [rsp + 36]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, [rsp + 36]
    imul edi, [rip + g_cw]
    add edi, [rsp + 16]
    mov esi, [rsp + 20]
    mov ecx, [rip + g_lh]
    COLOR r8d, T_SELECTION
    call gfx_fill
.Lsr_caret:
    mov rax, [r15 + SF_cur]
    sub rax, r13
    js 4f
    cmp rax, [rsp]
    jb 4f
    cmp rax, [rsp + 8]
    jb 3f
    ja 4f
    cmp dword ptr [rip + dl_last], 0
    je 4f
3:  cmp qword ptr [rip + sf_carets], SEL_MAX
    jae 4f
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, rax
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rsp + 16]
    mov rcx, [rip + sf_carets]
    shl rcx, 4
    lea rdx, [rip + sf_caret]
    mov [rdx + rcx], eax
    mov eax, [rsp + 20]
    mov [rdx + rcx + 4], eax
    mov rax, [r15 + SF_cur]
    mov [rdx + rcx + 8], rax
    inc qword ptr [rip + sf_carets]
4:  inc r14
    jmp .Lsr_next
.Lsr_ret:
    EPILOGUE

# sel_carets(doc, x where the text starts): after the rows: the secondary carets, blinking with the
# primary's (a block in vim's normal and visual modes)
FN sel_carets
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    cmp qword ptr [rip + sf_carets], 0
    je 9f
    cmp dword ptr [rip + g_vim_cmdline], 0
    jne 9f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    xor r12d, r12d
1:  cmp r12, [rip + sf_carets]
    jae 9f
    mov rax, r12
    shl rax, 4
    lea r13, [rip + sf_caret]
    add r13, rax
    inc r12
    mov edi, [r13]
    cmp edi, [rsp]
    jl 1b
    cmp dword ptr [rip + cfg_vim], 0
    je 2f
    cmp dword ptr [rip + g_vim_mode], VM_INSERT
    jne 3f
2:  M edx, MI_2
    cmp dword ptr [rip + cfg_smooth_caret], 0
    jne 21f
    M edx, MI_1
21: mov esi, [r13 + 4]
    mov ecx, [rip + g_lh]
    call ed_caret_draw
    jmp 1b
3:  mov rdi, rbx
    mov rsi, [r13 + 8]
    mov edx, [r13]
    mov ecx, [r13 + 4]
    call sel_block
    jmp 1b
9:  EPILOGUE

# sel_block(doc, pos, x, y): vim's block caret: the character in the background color on the caret's
sel_block:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov r14d, [rip + g_cw]      # width
    xor r15d, r15d              # bytes to draw
    call doc_len
    mov r13, rax
    sub r13, r12
    jz 2f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 4
    cmp r13, 4
    cmovb rdx, r13
    mov [rsp + 8], rdx
    call doc_range
    movzx ecx, byte ptr [rax]
    cmp ecx, ' '
    jbe 2f
    mov r13, rax
    mov rdi, rax
    mov rsi, [rsp + 8]
    call utf8_decode
    mov r15d, edx
    mov edi, eax
    call cp_width
    imul r14d, eax
    xor ecx, ecx                # doc_range may reuse its scratch: keep the bytes
1:  mov al, [r13 + rcx]
    mov [rsp + 16 + rcx], al
    inc ecx
    cmp ecx, r15d
    jb 1b
2:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, r14d
    mov ecx, [rip + g_lh]
    call ed_caret_draw
    test r15d, r15d
    jz 9f
    call ed_caret_shown
    test eax, eax
    jz 9f
    lea rdi, [rip + g_face_code]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    add edx, [rip + g_base]
    lea rcx, [rsp + 16]
    mov r8d, r15d
    COLOR r9d, T_BG
    call text_draw
9:  EPILOGUE

# sel_line_tint(doc, line) -> eax 1 when a secondary caret (an empty selection) is on the line: it
# gets the current-line tint as the primary's line does
FN sel_line_tint
    xor eax, eax
    cmp qword ptr [rip + sf_n], 0
    je 9f
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_start
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r14, rax
    mov rdi, r13
    call sel_first
    lea r9, [rip + sf_list]
1:  cmp rax, [rip + sf_n]
    jae 8f
    imul rcx, rax, SF_SIZE
    mov rdx, [r9 + rcx + SF_start]
    cmp rdx, r14
    ja 8f
    inc rax
    cmp rdx, [r9 + rcx + SF_end]
    jne 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  ret

# sel_status(doc, sb): the status bar's "  N selections" after the position, with several
FN sel_status
    PROLOGUE
    mov rbx, rsi
    call doc_selections_count
    cmp rax, 1
    jbe 9f
    mov r12, rax
    mov rdi, rbx
    lea rsi, [rip + .Lsel_gap]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lsel_word]
    call sb_push_cstr
9:  EPILOGUE

# ---------------- control (--script) ----------------

# sel_state(doc, sb): print-state's " sels=N" with several selections
FN sel_state
    PROLOGUE
    mov rbx, rsi
    call doc_selections_count
    cmp rax, 1
    jbe 9f
    mov r12, rax
    mov rdi, rbx
    lea rsi, [rip + .Lsel_sels_sp]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
9:  EPILOGUE

# sel_dump(doc, sb): print-selections: "sels=N", then "L1 C1 L2 C2" a selection (anchor, then
# cursor; lines and byte columns from 1), the primary first
FN sel_dump
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Lsel_sels]
    call sb_push_cstr
    xor r13d, r13d
    test rbx, rbx
    jz 1f
    mov rdi, rbx
    call doc_selections_count
    mov r13, rax
1:  mov rdi, r12
    mov rsi, r13
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor r14d, r14d
2:  cmp r14, r13
    jae 9f
    mov rdi, rbx
    mov rsi, r14
    call doc_selections_get
    mov r15, rax
    mov rsi, rdx
    call .Lsd_point
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, r15
    call .Lsd_point
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r14
    jmp 2b
9:  EPILOGUE
# .Lsd_point(rsi position): "LINE COL" into r12's sb (rbx doc)
.Lsd_point:
    push r15
    push r14
    sub rsp, 8
    mov r14, rsi
    mov rdi, rbx
    call doc_line_of
    mov r15, rax
    mov rdi, r12
    lea rsi, [rax + 1]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r15
    call doc_line_start
    mov rsi, r14
    sub rsi, rax
    inc rsi
    mov rdi, r12
    call sb_push_u64
    add rsp, 8
    pop r14
    pop r15
    ret

.section .rodata
.Lsel_full: .asciz "At most 512 selections."
.Lsel_none: .asciz "No more matches"
.Lsel_nearest: .asciz "Selected the 512 matches nearest the cursor."
.Lsel_gap: .asciz "  "
.Lsel_word: .asciz " selections"
.Lsel_sels: .asciz "sels="
.Lsel_sels_sp: .asciz " sels="
