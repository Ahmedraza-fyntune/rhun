# Line commands at several selections: Duplicate Line, Delete Line, Move Line Up/Down, Toggle
# Comment, Insert Line Above and Select Line act on the lines the selections cover, as one undo
# step through the batch API (docbatch.s). One selection keeps editor.s's own commands; Insert
# Line Below is ed_move and ed_newline, which already act at every selection.
.include "rhun.inc"

.equ LN_MAX, DOC_SELECTIONS_MAX

# a selection and the lines it covers (sel_lines' rule: an end at a later line's start leaves it)
STRUCT
F LS_cur, 8
F LS_anchor, 8
F LS_first, 8
F LS_last, 8
ENDSTRUCT LS_SIZE

.bss
.p2align 3
ln_n: .quad 0                   # selections, the primary first
ln_sels: .zero LS_SIZE*LN_MAX
ln_nblocks: .quad 0             # the lines they cover as sorted, separate blocks
ln_blocks: .zero 16*LN_MAX      # {first, last}
ln_order: .zero 8*LN_MAX        # the selections' indices sorted by first line
ln_shift: .zero 8*LN_MAX        # Move Line: how far each block goes
ln_nedits: .quad 0
ln_edits: .zero DBE_SIZE*DOC_BATCH_EDITS_MAX
ln_pairs: .zero DMP_SIZE*LN_MAX
ln_text: .zero SB_SIZE          # the edits' bytes; DBE_text holds an offset into it until ln_apply

.text

# ln_gather(doc, adjacent): every selection's lines, and their union as blocks; with adjacent set,
# blocks that touch (the next starts on the line after) are one block too
ln_gather:
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    call doc_selections_count
    mov [rip + ln_n], rax
    xor r12d, r12d
1:  cmp r12, [rip + ln_n]
    jae 3f
    mov rdi, rbx
    mov rsi, r12
    call doc_selections_get
    imul r13, r12, LS_SIZE
    lea rcx, [rip + ln_sels]
    add r13, rcx
    mov [r13 + LS_cur], rax
    mov [r13 + LS_anchor], rdx
    cmp rax, rdx
    jbe 2f
    xchg rax, rdx
2:  mov r14, rax                # start
    mov r15, rdx                # end
    mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    mov [r13 + LS_first], rax
    mov rdi, rbx
    mov rsi, r15
    call doc_line_of
    mov [r13 + LS_last], rax
    cmp rax, [r13 + LS_first]
    je 21f
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    cmp rax, r15
    jne 21f
    dec qword ptr [r13 + LS_last]
21: inc r12
    jmp 1b
3:  mov rdi, rbx
    mov esi, [rsp]
    call ln_regroup
9:  mov qword ptr [rip + ln_nedits], 0
    lea rdi, [rip + ln_text]
    call sb_clear
    EPILOGUE

# ln_block_of(line) -> rax index of the block that holds the line (blocks hold every selection's)
ln_block_of:
    xor eax, eax
    mov rcx, [rip + ln_nblocks]
    lea r8, [rip + ln_blocks]
1:  mov rdx, rcx
    sub rdx, rax
    cmp rdx, 1
    jbe 9f
    lea rdx, [rax + rcx]
    shr rdx, 1
    mov r9, rdx
    shl r9, 4
    cmp [r8 + r9], rdi
    ja 2f
    mov rax, rdx
    jmp 1b
2:  mov rcx, rdx
    jmp 1b
9:  ret

# ln_edit(start, end, offset of the bytes in ln_text, length) -> eax 0 past the batch's limit
ln_edit:
    mov rax, [rip + ln_nedits]
    cmp rax, DOC_BATCH_EDITS_MAX
    jae 8f
    shl rax, 5
    lea r8, [rip + ln_edits]
    mov [r8 + rax + DBE_start], rdi
    mov [r8 + rax + DBE_end], rsi
    mov [r8 + rax + DBE_text], rdx
    mov [r8 + rax + DBE_len], rcx
    inc qword ptr [rip + ln_nedits]
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ln_copy(doc, start, end): those bytes of the document onto ln_text
ln_copy:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    sub r13, r12
    lea rdi, [rip + ln_text]
    mov rsi, r13
    call sb_reserve
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_copy
    add [rip + ln_text + SB_len], r13
    EPILOGUE

ln_newline:
    lea rdi, [rip + ln_text]
    mov esi, 10
    jmp sb_push_byte

# ln_map(position) -> where it is after the edits: a position where text is inserted stays before
# it, one in deleted text goes to the start of what replaced it
ln_map:
    mov rax, rdi
    xor ecx, ecx
    lea r8, [rip + ln_edits]
1:  cmp rcx, [rip + ln_nedits]
    jae 9f
    mov rdx, rcx
    shl rdx, 5
    cmp rdi, [r8 + rdx + DBE_end]
    jb 2f
    mov r9, [r8 + rdx + DBE_end]
    cmp r9, [r8 + rdx + DBE_start]
    jne 11f
    cmp rdi, r9                 # an insertion here: before it
    je 9f
11: add rax, [r8 + rdx + DBE_len]
    sub rax, [r8 + rdx + DBE_end]
    add rax, [r8 + rdx + DBE_start]
    inc rcx
    jmp 1b
2:  cmp rdi, [r8 + rdx + DBE_start]
    jbe 9f
    sub rax, rdi                # inside: the replacement's start
    add rax, [r8 + rdx + DBE_start]
9:  ret

# ln_pair(index, cur, anchor): a final selection
ln_pair:
    shl rdi, 4
    lea rax, [rip + ln_pairs]
    mov [rax + rdi + DMP_cur], rsi
    mov [rax + rdi + DMP_anchor], rdx
    ret

# ln_apply(doc, pairs) -> eax 1 when the edits were made as one undo step with those selections
# (merged where they meet); errors are shown
ln_apply:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea r8, [rip + ln_edits]
    xor ecx, ecx
1:  cmp rcx, [rip + ln_nedits]
    jae 2f
    mov rdx, rcx
    shl rdx, 5
    inc rcx
    cmp qword ptr [r8 + rdx + DBE_len], 0
    je 1b
    mov rax, [rip + ln_text + SB_ptr]
    add [r8 + rdx + DBE_text], rax
    jmp 1b
2:  mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    lea rsi, [rip + ln_edits]
    mov rdx, [rip + ln_nedits]
    lea rcx, [rip + ln_pairs]
    mov r8, r12
    call doc_selections_apply
    mov r13d, eax
    mov [rsp + 8], edx
    lea rdi, [rip + ln_text]
    call sb_free
    test r13d, r13d
    jz 8f
    mov rdi, rbx
    call sel_normalize
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    mov eax, 1
    EPILOGUE
8:  mov edi, [rsp + 8]
    call editor_multi_error
    xor eax, eax
    EPILOGUE

# lines_limit(): a command over more lines than one batch takes
lines_limit:
    mov edi, 2
    jmp editor_multi_error

# ---------------- the commands ----------------

# Delete Line: the lines go (at the end of the document, the newline before them); a caret at the
# start of the line that takes their place
FN lines_delete
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    mov esi, 1
    call ln_gather
    xor r12d, r12d
.Lld_block:
    cmp r12, [rip + ln_nblocks]
    jae .Lld_pairs
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r13, [rcx + rax]        # first
    mov r14, [rcx + rax + 8]    # last
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov r15, rax
    lea rsi, [r14 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 1f
    mov rdi, rbx
    call doc_line_start
    jmp 2f
1:  test r15, r15
    jz 11f
    dec r15
11: mov rdi, rbx
    call doc_len
2:  mov rdi, r15
    mov rsi, rax
    xor edx, edx
    xor ecx, ecx
    call ln_edit
    inc r12
    jmp .Lld_block
.Lld_pairs:
    # a caret a block, the primary's block first
    lea rax, [rip + ln_sels]
    mov rdi, [rax + LS_first]
    call ln_block_of
    mov [rsp], rax
    xor r12d, r12d              # block
    mov r13d, 1                 # next pair (0: the primary's)
.Lld_pair:
    cmp r12, [rip + ln_nblocks]
    jae .Lld_apply
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r14, [rcx + rax]
    mov r15, [rcx + rax + 8]
    lea rsi, [r15 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 1f
    mov rdi, rbx
    call doc_line_start
    jmp 3f
1:  xor eax, eax
    test r14, r14
    jz 3f
    mov rdi, rbx
    lea rsi, [r14 - 1]
    call doc_line_start
3:  mov rdi, rax
    call ln_map
    mov rsi, rax
    mov rdx, rax
    mov rdi, r13
    cmp r12, [rsp]
    jne 4f
    xor edi, edi
    dec r13
4:  inc r13
    call ln_pair
    inc r12
    jmp .Lld_pair
.Lld_apply:
    mov rdi, rbx
    mov rsi, [rip + ln_nblocks]
    call ln_apply
    EPILOGUE

# Duplicate Line: a copy of the lines below them; the selections go onto the copy
FN lines_duplicate
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    xor esi, esi
    call ln_gather
    xor r12d, r12d
.Ldu_block:
    cmp r12, [rip + ln_nblocks]
    jae .Ldu_pairs
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov rdi, rbx
    mov rsi, [rcx + rax]
    call doc_line_start
    mov r13, rax
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov rdi, rbx
    mov rsi, [rcx + rax + 8]
    call doc_line_end
    mov r14, rax
    mov r15, [rip + ln_text + SB_len]
    call ln_newline
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call ln_copy
    mov rdi, r14
    mov rsi, r14
    mov rdx, r15
    mov rcx, [rip + ln_text + SB_len]
    sub rcx, r15
    call ln_edit
    inc r12
    jmp .Ldu_block
.Ldu_pairs:
    xor r12d, r12d
.Ldu_pair:
    cmp r12, [rip + ln_n]
    jae .Ldu_apply
    imul r13, r12, LS_SIZE
    lea rax, [rip + ln_sels]
    add r13, rax
    mov rdi, [r13 + LS_first]
    call ln_block_of
    mov r14, rax
    shl r14, 5                  # the block's edit (one each)
    lea rax, [rip + ln_edits]
    add r14, rax
    mov rdi, [r13 + LS_cur]
    call .Ldu_onto
    mov [rsp], rax
    mov rdi, [r13 + LS_anchor]
    call .Ldu_onto
    mov rdx, rax
    mov rsi, [rsp]
    mov rdi, r12
    call ln_pair
    inc r12
    jmp .Ldu_pair
.Ldu_apply:
    mov rdi, rbx
    mov rsi, [rip + ln_n]
    call ln_apply
    EPILOGUE
# .Ldu_onto(rdi position in the block of edit r14) -> rax that position in the copy
.Ldu_onto:
    push rdi
    call ln_map
    pop rdi
    cmp rdi, [r14 + DBE_start]
    ja 1f
    add rax, [r14 + DBE_len]    # at or before the insertion: the copy follows
1:  ret

# lines_move(direction): the blocks of lines and the line above (-1) or below (1) them change
# places; nothing moves when one block is at the edge
FN lines_move_up
    mov rdi, -1
    jmp lines_move
FN lines_move_down
    mov edi, 1
lines_move:
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    mov [rsp + 40], rdi
    mov rdi, rbx
    mov esi, 1
    call ln_gather
    cmp qword ptr [rsp + 40], 0
    jg 1f
    cmp qword ptr [rip + ln_blocks], 0
    je .Lmv_ret
    jmp 2f
1:  mov rax, [rip + ln_nblocks]
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov rax, [rcx + rax - 16 + 8]
    inc rax
    cmp rax, [rbx + DOC_nlines]
    jae .Lmv_ret
2:  xor r12d, r12d
.Lmv_block:
    cmp r12, [rip + ln_nblocks]
    jae .Lmv_pairs
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r13, [rcx + rax]        # first
    mov r14, [rcx + rax + 8]    # last
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov [rsp], rax              # the block's start
    mov rdi, rbx
    mov rsi, r14
    call doc_line_end
    mov [rsp + 8], rax          # its end
    lea r15, [r14 + 1]          # the other line
    cmp qword ptr [rsp + 40], 0
    jg 3f
    lea r15, [r13 - 1]
3:  mov rdi, rbx
    mov rsi, r15
    call doc_line_start
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, r15
    call doc_line_end
    mov [rsp + 24], rax
    mov r15, [rip + ln_text + SB_len]
    cmp qword ptr [rsp + 40], 0
    jg 4f
    # up: the block, a newline, the line that was above it
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call ln_copy
    call ln_newline
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call ln_copy
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 8]
    jmp 5f
4:  # down: the line that was below it, a newline, the block
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call ln_copy
    call ln_newline
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call ln_copy
    mov rdi, [rsp]
    mov rsi, [rsp + 24]
5:  mov rdx, r15
    mov rcx, [rip + ln_text + SB_len]
    sub rcx, r15
    call ln_edit
    mov rax, [rsp + 24]         # the other line and its newline: how far the block goes
    sub rax, [rsp + 16]
    inc rax
    cmp qword ptr [rsp + 40], 0
    jg 51f
    neg rax
51: lea rcx, [rip + ln_shift]
    mov [rcx + r12*8], rax
    inc r12
    jmp .Lmv_block
.Lmv_pairs:
    # every selection moves with its block by the other line and its newline (no further than
    # the end of the text: a block moved to the end has no newline after it)
    mov rdi, rbx
    call doc_len
    mov [rsp + 32], rax
    xor r12d, r12d
.Lmv_pair:
    cmp r12, [rip + ln_n]
    jae .Lmv_apply
    imul r13, r12, LS_SIZE
    lea rax, [rip + ln_sels]
    add r13, rax
    mov rdi, [r13 + LS_first]
    call ln_block_of
    lea rcx, [rip + ln_shift]
    mov rcx, [rcx + rax*8]
    mov rsi, [r13 + LS_cur]
    add rsi, rcx
    cmp rsi, [rsp + 32]
    jbe 6f
    mov rsi, [rsp + 32]
6:  mov rdx, [r13 + LS_anchor]
    add rdx, rcx
    cmp rdx, [rsp + 32]
    jbe 7f
    mov rdx, [rsp + 32]
7:  mov rdi, r12
    call ln_pair
    inc r12
    jmp .Lmv_pair
.Lmv_apply:
    mov rdi, rbx
    mov rsi, [rip + ln_n]
    call ln_apply
.Lmv_ret:
    EPILOGUE

# Toggle Comment: the grammar's line comment token at the indentation of every non-blank line the
# selections cover (the least of each block), or off all of them when all have it
FN lines_comment
    PROLOGUE 48
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call doc_language
    test rax, rax
    jz .Lco_ret
    mov rcx, [rax + GR_commentlen]
    test rcx, rcx
    jz .Lco_ret
    mov rdx, [rax + GR_comment]
    mov [rsp], rdx              # token
    mov [rsp + 8], rcx
    mov rdi, rbx
    xor esi, esi
    call ln_gather
    # the token and a space, the bytes of every insertion
    lea rdi, [rip + ln_text]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call sb_push
    lea rdi, [rip + ln_text]
    mov esi, ' '
    call sb_push_byte
    # all non-blank lines commented: uncomment
    mov dword ptr [rsp + 16], 1
    xor r12d, r12d
.Lco_scan_block:
    cmp r12, [rip + ln_nblocks]
    jae .Lco_edits
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r13, [rcx + rax]
    mov r14, [rcx + rax + 8]
1:  cmp r13, r14
    ja 3f
    mov rdi, rbx
    mov rsi, r13
    call line_indent
    mov r15, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    cmp r15, rdx
    je 2f
    lea rdi, [rax + r15]
    mov rsi, rdx
    sub rsi, r15
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call str_starts
    test eax, eax
    jnz 2f
    mov dword ptr [rsp + 16], 0
2:  inc r13
    jmp 1b
3:  inc r12
    jmp .Lco_scan_block
.Lco_edits:
    xor r12d, r12d
.Lco_block:
    cmp r12, [rip + ln_nblocks]
    jae .Lco_pairs
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r13, [rcx + rax]
    mov r14, [rcx + rax + 8]
    # the block's least indentation
    mov qword ptr [rsp + 24], -1
    mov [rsp + 32], r13
4:  mov rax, [rsp + 32]
    cmp rax, r14
    ja 6f
    mov rdi, rbx
    mov rsi, rax
    call line_indent
    mov r15, rax
    mov rdi, rbx
    mov rsi, [rsp + 32]
    call doc_line_text
    cmp r15, rdx
    je 5f
    cmp r15, [rsp + 24]
    jae 5f
    mov [rsp + 24], r15
5:  inc qword ptr [rsp + 32]
    jmp 4b
6:  # a line's edit
    cmp r13, r14
    ja .Lco_next_block
    mov rdi, rbx
    mov rsi, r13
    call line_indent
    mov r15, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    cmp r15, rdx
    je .Lco_next_line
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    cmp dword ptr [rsp + 16], 0
    je 8f
    # off: the token and one space after it
    add r15, rax
    mov rdx, [rsp + 8]
    lea rsi, [r15 + rdx]
    mov rdi, rbx
    mov [rsp + 40], rdx
    call doc_byte
    mov rdx, [rsp + 40]
    cmp al, ' '
    jne 7f
    inc rdx
7:  mov rdi, r15
    lea rsi, [r15 + rdx]
    xor edx, edx
    xor ecx, ecx
    call ln_edit
    jmp 9f
8:  add rax, [rsp + 24]
    mov rdi, rax
    mov rsi, rax
    xor edx, edx                # the token and a space at ln_text's start
    mov rcx, [rsp + 8]
    inc rcx
    call ln_edit
9:  test eax, eax
    jz .Lco_limit
.Lco_next_line:
    inc r13
    jmp 6b
.Lco_next_block:
    inc r12
    jmp .Lco_block
.Lco_pairs:
    cmp qword ptr [rip + ln_nedits], 0
    je .Lco_free
    xor r12d, r12d
10: cmp r12, [rip + ln_n]
    jae 11f
    imul r13, r12, LS_SIZE
    lea rax, [rip + ln_sels]
    add r13, rax
    mov rdi, [r13 + LS_cur]
    call ln_map
    mov r14, rax
    mov rdi, [r13 + LS_anchor]
    call ln_map
    mov rdx, rax
    mov rsi, r14
    mov rdi, r12
    call ln_pair
    inc r12
    jmp 10b
11: mov rdi, rbx
    mov rsi, [rip + ln_n]
    call ln_apply
    jmp .Lco_ret
.Lco_limit:
    call lines_limit
.Lco_free:
    lea rdi, [rip + ln_text]
    call sb_free
.Lco_ret:
    EPILOGUE

# Insert Line Above: an empty line above each caret's line with that line's indentation (a level
# more above a closing bracket), the caret at its end
FN lines_newline_above
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    xor esi, esi
    call ln_gather
    # the carets' lines, sorted, each once: the selections' cursors this time
    xor r12d, r12d
1:  cmp r12, [rip + ln_n]
    jae 2f
    imul r13, r12, LS_SIZE
    lea rax, [rip + ln_sels]
    add r13, rax
    mov rdi, rbx
    mov rsi, [r13 + LS_cur]
    call doc_line_of
    mov [r13 + LS_first], rax
    mov [r13 + LS_last], rax
    inc r12
    jmp 1b
2:  mov rdi, rbx
    xor esi, esi
    call ln_regroup
    xor r12d, r12d
.Lna_block:
    cmp r12, [rip + ln_nblocks]
    jae .Lna_pairs
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + ln_blocks]
    mov r13, [rcx + rax]        # the line
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r13
    call line_indent
    mov r15, rax
    cmp rax, 200
    jbe 3f
    mov eax, 200
3:  mov [rsp], rax              # indentation copied
    mov rax, [rip + ln_text + SB_len]
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r14
    lea rdx, [r14 + 0]
    add rdx, [rsp]
    call ln_copy
    lea rsi, [r14 + r15]
    mov rdi, rbx
    call doc_byte
    cmp eax, '}'
    je 4f
    cmp eax, ')'
    je 4f
    cmp eax, ']'
    jne 6f
4:  cmp dword ptr [rip + g_insert_spaces], 0
    jne 5f
    lea rdi, [rip + ln_text]
    mov esi, 9
    call sb_push_byte
    jmp 6f
5:  mov ecx, [rip + g_tab_width]
    cmp ecx, 16
    jbe 51f
    mov ecx, 16
51: mov [rsp + 16], rcx
52: cmp qword ptr [rsp + 16], 0
    je 6f
    lea rdi, [rip + ln_text]
    mov esi, ' '
    call sb_push_byte
    dec qword ptr [rsp + 16]
    jmp 52b
6:  call ln_newline
    mov rdi, r14
    mov rsi, r14
    mov rdx, [rsp + 8]
    mov rcx, [rip + ln_text + SB_len]
    sub rcx, rdx
    call ln_edit
    inc r12
    jmp .Lna_block
.Lna_pairs:
    # a caret a line, at the end of the new line's indentation; the primary's first
    lea rax, [rip + ln_sels]
    mov rdi, [rax + LS_first]
    call ln_block_of
    mov [rsp + 16], rax
    xor r12d, r12d
    mov r13d, 1
.Lna_pair:
    cmp r12, [rip + ln_nblocks]
    jae .Lna_apply
    mov r14, r12
    shl r14, 5
    lea rax, [rip + ln_edits]
    add r14, rax
    mov rdi, [r14 + DBE_start]
    call ln_map
    add rax, [r14 + DBE_len]
    dec rax
    mov rsi, rax
    mov rdx, rax
    mov rdi, r13
    cmp r12, [rsp + 16]
    jne 7f
    xor edi, edi
    dec r13
7:  inc r13
    call ln_pair
    inc r12
    jmp .Lna_pair
.Lna_apply:
    mov rdi, rbx
    mov rsi, [rip + ln_nblocks]
    call ln_apply
    EPILOGUE

# ln_regroup(doc, adjacent): ln_gather's order and blocks again, from the lines in ln_sels
ln_regroup:
    PROLOGUE 16
    mov [rsp], esi
    xor r12d, r12d
1:  cmp r12, [rip + ln_n]
    jae 3f
    imul r13, r12, LS_SIZE
    lea rcx, [rip + ln_sels]
    add r13, rcx
    mov rcx, r12
    lea r8, [rip + ln_order]
    lea r9, [rip + ln_sels]
2:  test rcx, rcx
    jz 21f
    mov rdx, [r8 + rcx*8 - 8]
    imul rdx, rdx, LS_SIZE
    mov rax, [r9 + rdx + LS_first]
    cmp rax, [r13 + LS_first]
    jbe 21f
    mov rax, [r8 + rcx*8 - 8]
    mov [r8 + rcx*8], rax
    dec rcx
    jmp 2b
21: mov [r8 + rcx*8], r12
    inc r12
    jmp 1b
3:  mov qword ptr [rip + ln_nblocks], 0
    xor r12d, r12d
    lea r14, [rip + ln_blocks]
4:  cmp r12, [rip + ln_n]
    jae 9f
    lea rax, [rip + ln_order]
    mov rax, [rax + r12*8]
    imul rax, rax, LS_SIZE
    lea rcx, [rip + ln_sels]
    mov r8, [rcx + rax + LS_first]
    mov r9, [rcx + rax + LS_last]
    inc r12
    mov rcx, [rip + ln_nblocks]
    test rcx, rcx
    jz 6f
    shl rcx, 4
    mov rax, [r14 + rcx - 16 + 8]
    cmp r8, rax
    jbe 5f
    cmp dword ptr [rsp], 0
    je 6f
    lea rdx, [rax + 1]
    cmp r8, rdx
    jne 6f
5:  cmp r9, rax
    jbe 4b
    mov [r14 + rcx - 16 + 8], r9
    jmp 4b
6:  mov rcx, [rip + ln_nblocks]
    shl rcx, 4
    mov [r14 + rcx], r8
    mov [r14 + rcx + 8], r9
    inc qword ptr [rip + ln_nblocks]
    jmp 4b
9:  EPILOGUE

# Select Line: each selection grows to its whole lines, and by one more line when it already
# selected something
FN lines_select
    PROLOGUE
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    xor esi, esi
    call ln_gather
    xor r12d, r12d
1:  cmp r12, [rip + ln_n]
    jae 4f
    imul r13, r12, LS_SIZE
    lea rax, [rip + ln_sels]
    add r13, rax
    mov r14, [r13 + LS_last]
    mov rax, [r13 + LS_cur]
    cmp rax, [r13 + LS_anchor]
    je 2f
    inc r14
2:  mov rdi, rbx
    mov rsi, [r13 + LS_first]
    call doc_line_start
    mov r15, rax
    lea rsi, [r14 + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 3f
    mov rdi, rbx
    call doc_line_start
    jmp 31f
3:  mov rdi, rbx
    call doc_len
31: mov rsi, rax
    mov rdx, r15
    mov rdi, r12
    call ln_pair
    inc r12
    jmp 1b
4:  mov rdi, rbx
    lea rsi, [rip + ln_pairs]
    mov rdx, [rip + ln_n]
    call sel_install
    call ed_touch
    EPILOGUE
