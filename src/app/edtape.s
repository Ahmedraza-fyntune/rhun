# editor presentation: a document's presentation state (DOC_pres) and its edit tape. Every raw
# edit of a document that has the state goes into a ring of its last TAPE_N edits, so a position an
# extension computed for an older version can be moved onto the current text (tape_map,
# tape_map_lc: read-only answers show at their moved place), and one routine moves every stored
# position with an edit (shift_points) by one gravity per kind:
#   GR_RIGHT  an insert at the position moves it (range starts, marks, glyph-lane entries)
#   GR_LEFT   an insert at the position leaves it (range ends)
#   a deletion covering a position collapses it to the deletion's start; later ones move back.
# doc.s's edit hooks (ext_note_insert/delete) stay on once any document has the state.
.include "rhun.inc"

.bss
.p2align 3
.globl g_pres_ever
g_pres_ever: .long 0            # a document got presentation state (ext_hooks_update counts it)
.p2align 3
pd_line: .quad 0                # pres_pre_delete: where the coming deletion starts, and what it
pd_col: .quad 0                 #   removes, read by pres_note_delete after it happened
pd_nl: .quad 0
pd_tail: .quad 0

.text

# pres_ensure(doc) -> rax its DOC_pres, made when missing (the tape starts at the current version)
FN pres_ensure
    mov rax, [rdi + DOC_pres]
    test rax, rax
    jz 1f
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov edi, PRS_SIZE
    call mem_alloc
    mov r12, rax
    mov edi, TAPE_N * TE_SIZE
    call mem_alloc
    mov [r12 + PRS_tape], rax
    mov rax, [rbx + DOC_version]
    mov [r12 + PRS_tbase], rax
    mov qword ptr [r12 + PRS_gen], 1
    mov [rbx + DOC_pres], r12
    call pres_enable
    mov rax, r12
    EPILOGUE

# pres_enable(): documents keep an edit tape from their next edit on (an extension that may answer
# about older versions is running, or a document has presentation state)
FN pres_enable
    cmp dword ptr [rip + g_pres_ever], 0
    jne 1f
    mov dword ptr [rip + g_pres_ever], 1
    jmp ext_hooks_update
1:  ret

# pres_free(doc): the document is closing
FN pres_free
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DOC_pres]
    test r12, r12
    jz 9f
    mov rdi, rbx
    call deco_doc_gone
    mov qword ptr [rbx + DOC_pres], 0
    mov rdi, [r12 + PRS_tape]
    call mem_free
    lea rdi, [r12 + PRS_deco]
    call vec_free
    mov rdi, [r12 + PRS_dpool + SB_ptr]
    call mem_free
    lea rdi, [r12 + PRS_glyphs]
    call vec_free
    xor r13d, r13d              # the folds' collapsed texts
1:  cmp r13, [r12 + PRS_folds + VEC_len]
    jae 2f
    imul rax, r13, FLD_SIZE
    add rax, [r12 + PRS_folds + VEC_ptr]
    mov rdi, [rax + FLD_text]
    call mem_free
    inc r13
    jmp 1b
2:  lea rdi, [r12 + PRS_folds]
    call vec_free
    lea rdi, [r12 + PRS_hid]
    call vec_free
    lea rdi, [r12 + PRS_fr]     # a folding provider's ranges (present.s)
    call fr_vec_clear
    lea rdi, [r12 + PRS_fr]
    call vec_free
    mov rdi, r12                # semantic tokens (semtok.s)
    call semtok_free
    mov rdi, r12                # inlay hints (inlay.s)
    call inlay_free
    mov rdi, r12                # code lens (lens.s)
    call lens_free
    mov rdi, r12
    call mem_free
9:  EPILOGUE

# pres_touch(doc): what the document shows changed (its state's generation moves on)
FN pres_touch
    mov rax, [rdi + DOC_pres]
    test rax, rax
    jz 1f
    inc qword ptr [rax + PRS_gen]
1:  mov dword ptr [rip + g_dirty], 1
    ret

# ---------------- the tape ----------------

# pres_pre_delete(doc, pos, len): raw_delete calls it before it deletes: where the deletion starts
# (line and column) and the line feeds it removes, which the text no longer shows afterwards
FN pres_pre_delete
    cmp dword ptr [rip + g_pres_ever], 0
    jne 1f
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call pres_ensure            # a tape from before this deletion
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov rcx, r12
    sub rcx, rax
    mov [rip + pd_line], r14
    mov [rip + pd_col], rcx
    mov rdi, rbx
    lea rsi, [r12 + r13]
    call doc_line_of
    mov r15, rax
    sub rax, r14
    mov [rip + pd_nl], rax
    mov [rip + pd_tail], r13
    test rax, rax
    jz 9f
    mov rdi, rbx
    mov rsi, r15
    call doc_line_start
    lea rcx, [r12 + r13]
    sub rcx, rax
    mov [rip + pd_tail], rcx
9:  EPILOGUE

# pres_note_insert(doc, pos, ptr, len): an insert happened (ext_note_insert)
FN pres_note_insert
    cmp dword ptr [rip + g_pres_ever], 0
    jne 1f
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp qword ptr [rbx + DOC_pres], 0
    jne 2f
    call pres_ensure            # a tape from before this insert
    mov rcx, [rbx + DOC_version]
    dec rcx
    mov [rax + PRS_tbase], rcx
2:  call tape_next
    mov r15, rax
    mov [r15 + TE_pos], r12
    mov qword ptr [r15 + TE_del], 0
    mov [r15 + TE_ins], r14
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov [r15 + TE_line], rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov rcx, r12
    sub rcx, rax
    mov [r15 + TE_col], rcx
    # the line feeds of the inserted text and its bytes after the last one
    xor ecx, ecx
    xor edx, edx
    mov r8, r14                 # tail
2:  cmp rcx, r14
    jae 3f
    cmp byte ptr [r13 + rcx], 10
    jne 21f
    inc rdx
    mov r8, r14
    sub r8, rcx
    dec r8
21: inc rcx
    jmp 2b
3:  mov [r15 + TE_nl], rdx
    mov [r15 + TE_tail], r8
    mov rdi, rbx
    mov rsi, r15
    call pres_shift
    EPILOGUE

# pres_note_delete(doc, pos, len): a deletion happened (ext_note_delete; pres_pre_delete ran before)
FN pres_note_delete
    cmp qword ptr [rdi + DOC_pres], 0
    jne 1f
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call tape_next
    mov [rax + TE_pos], r12
    mov [rax + TE_del], r13
    mov qword ptr [rax + TE_ins], 0
    mov rcx, [rip + pd_line]
    mov [rax + TE_line], rcx
    mov rcx, [rip + pd_col]
    mov [rax + TE_col], rcx
    mov rcx, [rip + pd_nl]
    mov [rax + TE_nl], rcx
    mov rcx, [rip + pd_tail]
    mov [rax + TE_tail], rcx
    mov rdi, rbx
    mov rsi, rax
    call pres_shift
    EPILOGUE

# tape_next(rbx doc) -> rax the ring's next entry, its version set; the oldest one goes when full
tape_next:
    mov rdx, [rbx + DOC_pres]
    mov rax, [rdx + PRS_tn]
    mov rcx, rax
    and ecx, TAPE_N - 1
    imul rcx, rcx, TE_SIZE
    add rcx, [rdx + PRS_tape]
    cmp rax, TAPE_N
    jb 1f
    mov r8, [rcx + TE_version]  # the edit it held can no longer be replayed: positions of that
    mov [rdx + PRS_tbase], r8    # version and later still can
1:  inc qword ptr [rdx + PRS_tn]
    mov r8, [rbx + DOC_version]
    mov [rcx + TE_version], r8
    mov rax, rcx
    ret

# pres_shift(doc, entry): every stored position of the document moves with the edit
pres_shift:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call deco_shift
    mov rdi, rbx
    mov rsi, r12
    call gutter_shift
    mov rdi, rbx
    mov rsi, r12
    call fold_shift
    mov rdi, rbx
    mov rsi, r12
    call semtok_shift
    mov rdi, rbx
    mov rsi, r12
    call inlay_shift
    mov rdi, rbx
    mov rsi, r12
    call lens_shift
    EPILOGUE

# tape_shift(value, pos, del, ins, gravity) -> rax the value after the edit (one of del and ins is
# 0). Clobbers rax and r9 only.
FN tape_shift
    mov rax, rdi
    test rcx, rcx
    jz 2f
    cmp rax, rsi
    jb 9f
    ja 1f
    test r8d, r8d               # at the position: GR_RIGHT moves
    jnz 9f
1:  add rax, rcx
    ret
2:  lea r9, [rsi + rdx]         # the deletion's end
    cmp rax, r9
    jb 3f
    sub rax, rdx
    ret
3:  cmp rax, rsi
    jbe 9f
    mov rax, rsi                # inside: to the start
9:  ret

# shift_points(field, n, stride, gravity, entry): n positions, stride bytes apart starting at
# field, moved with the edit of a tape entry
FN shift_points
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15, r8
    mov rsi, [r15 + TE_pos]
    mov rdx, [r15 + TE_del]
    mov rcx, [r15 + TE_ins]
    mov r8d, r14d
1:  test r12, r12
    jz 9f
    mov rdi, [rbx]
    call tape_shift
    mov [rbx], rax
    add rbx, r13
    dec r12
    jmp 1b
9:  EPILOGUE

# tape_first(ps, version) -> rax the index of the first entry after that version, or -1 when the
# tape cannot replay from it (older than the ring, or newer than the text)
tape_first:
    cmp rsi, [rdi + PRS_tbase]
    jb 8f
    mov rax, [rdi + PRS_tn]
    xor ecx, ecx
    cmp rax, TAPE_N
    jbe 1f
    lea rcx, [rax - TAPE_N]
1:  mov rax, rcx
    ret
8:  mov rax, -1
    ret

# tape_map(doc, version, pos, gravity) -> rax the position in the current text of a position in
# the text of an older version, or -1 when the tape no longer reaches back to that version
FN tape_map
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    cmp r12, [rbx + DOC_version]
    je .Ltm_done
    ja .Ltm_fail
    mov rdi, [rbx + DOC_pres]
    test rdi, rdi
    jz .Ltm_fail
    mov rsi, r12
    call tape_first
    test rax, rax
    js .Ltm_fail
    mov r15, rax
1:  mov rdx, [rbx + DOC_pres]
    cmp r15, [rdx + PRS_tn]
    jae .Ltm_done
    mov rax, r15
    and eax, TAPE_N - 1
    imul rax, rax, TE_SIZE
    add rax, [rdx + PRS_tape]
    inc r15
    cmp [rax + TE_version], r12
    jbe 1b
    mov rdi, r13
    mov rsi, [rax + TE_pos]
    mov rdx, [rax + TE_del]
    mov rcx, [rax + TE_ins]
    mov r8d, r14d
    call tape_shift
    mov r13, rax
    jmp 1b
.Ltm_done:
    mov rdi, rbx
    call doc_len
    cmp r13, rax
    cmova r13, rax
    mov rax, r13
    EPILOGUE
.Ltm_fail:
    mov rax, -1
    EPILOGUE

# tape_map_lc(doc, version, line, col, gravity) -> rax the byte position in the current text of a
# 0-based line and byte column of an older version's text, or -1 when the tape no longer reaches
# back to it. The point moves through each edit as a line and column; the result is clamped to
# its line and moved to the start of a character it would fall inside.
FN tape_map_lc
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx                # line
    mov r14, rcx                # col
    mov [rsp], r8d
    cmp r12, [rbx + DOC_version]
    je .Ltl_pos
    ja .Ltl_fail
    mov rdi, [rbx + DOC_pres]
    test rdi, rdi
    jz .Ltl_fail
    mov rsi, r12
    call tape_first
    test rax, rax
    js .Ltl_fail
    mov r15, rax
.Ltl_entry:
    mov rdx, [rbx + DOC_pres]
    cmp r15, [rdx + PRS_tn]
    jae .Ltl_pos
    mov rax, r15
    and eax, TAPE_N - 1
    imul rax, rax, TE_SIZE
    add rax, [rdx + PRS_tape]
    inc r15
    cmp [rax + TE_version], r12
    jbe .Ltl_entry
    mov rsi, [rax + TE_line]
    mov rdi, [rax + TE_col]
    mov r8, [rax + TE_nl]
    mov r9, [rax + TE_tail]
    cmp qword ptr [rax + TE_ins], 0
    je .Ltl_del
    # an insert at (Lp, Cp): a point before it (or at it, with GR_LEFT) stays
    cmp r13, rsi
    jb .Ltl_entry
    ja 2f
    cmp r14, rdi
    jb .Ltl_entry
    ja 1f
    cmp dword ptr [rsp], GR_LEFT
    je .Ltl_entry
1:  # on its line, after it: the inserted text's last line ends where the point's column was
    test r8, r8
    jnz 11f
    add r14, r9
    jmp .Ltl_entry
11: sub r14, rdi
    add r14, r9
    add r13, r8
    jmp .Ltl_entry
2:  add r13, r8
    jmp .Ltl_entry
.Ltl_del:
    # a deletion from (Lp, Cp) to (Lp + nl, nl ? tail : Cp + del)
    mov r10, rsi
    add r10, r8                 # Le
    mov r11, r9                 # Ce
    test r8, r8
    jnz 3f
    mov r11, rdi
    add r11, [rax + TE_del]
3:  # at or before the start: stays
    cmp r13, rsi
    jb .Ltl_entry
    ja 4f
    cmp r14, rdi
    jbe .Ltl_entry
4:  # before the end: to the start
    cmp r13, r10
    jb 5f
    ja 6f
    cmp r14, r11
    jae 7f
5:  mov r13, rsi
    mov r14, rdi
    jmp .Ltl_entry
7:  # on the end's line: it joins the start's line
    mov r13, rsi
    sub r14, r11
    add r14, rdi
    jmp .Ltl_entry
6:  sub r13, r8
    jmp .Ltl_entry
.Ltl_pos:
    # the line and column in the current text
    cmp r13, [rbx + DOC_nlines]
    jb 1f
    mov rdi, rbx
    call doc_len
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov r12, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_end
    sub rax, r12
    cmp r14, rax
    cmova r14, rax
    add r12, r14
2:  test r14, r14
    jz 3f
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    jne 3f
    dec r12
    dec r14
    jmp 2b
3:  mov rax, r12
    EPILOGUE
.Ltl_fail:
    mov rax, -1
    EPILOGUE
