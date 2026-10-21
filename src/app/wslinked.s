# feature linked-editing (v1.1.md): in an HTML tag, renaming the opening tag's name renames the
# closing one as you type. When the cursor has rested 150 ms inside a word of a document a linked
# provider matches, rhun asks it for the ranges that change together; its answer becomes a native
# snippet session (snippet*.s) of one group, the cursor's range its primary field and the others
# its mirrors, marked SN_linked: Tab and shift+Tab pass through, a character outside the word set
# ends it before it is typed, and its ranges are outlined while it lives.
.include "rhun.inc"

.equ LK_REST, 150               # ms the cursor rests before rhun asks
.equ LK_WAIT, 1000              # ms it waits for the answer (the query's kind says so too)
.equ LK_RANGES_MAX, 64
.equ LK_DOC_MAX, 4194304        # a larger document is not linked (the session reads its text)

.bss
.p2align 3
lk_doc_id: .quad 0              # where the cursor rests: document, version, offset, since when
lk_ver: .quad 0
lk_cur: .quad 0
lk_since: .quad 0
lk_asked: .quad 0               # 1: that place was asked about already
lk_ext: .quad 0                 # the request out, or 0
lk_id: .quad 0
lk_words: .zero 256             # an answer's characters that may be typed (ASCII), 1 each: its
                                # session keeps them as bits (SN_lwords)
lk_ranges: .zero 16 * LK_RANGES_MAX     # an answer's ranges: start, end
lk_text: .zero SB_SIZE          # the document's text while a session is made

.text

# lk_reset(): a new place: whatever was asked for the old one goes
lk_reset:
    push rbx
    mov rdi, [rip + lk_ext]
    test rdi, rdi
    jz 1f
    mov rsi, [rip + lk_id]
    mov qword ptr [rip + lk_ext], 0
    call query_withdraw
1:  mov qword ptr [rip + lk_asked], 0
    pop rbx
    ret

# lk_provider(doc) -> rax the first running extension that agreed linked-editing and whose linked
# patterns match the document, or 0
lk_provider:
    PROLOGUE
    mov r13, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 8f
    imul r12, rbx, EXT_SIZE
    add r12, [rip + g_exts + VEC_ptr]
    inc rbx
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne 1b
    FEAT_TEST r12, FEAT_LINKED_EDITING
    jz 1b
    mov rdi, r12
    mov esi, EXT_pv_linked
    call ext_pv
    test rax, rax
    jz 1b
    mov rdi, rax
    mov rsi, r13
    call extproto_matches
    test eax, eax
    jz 1b
    mov rax, r12
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lk_in_word(doc, pos) -> eax 1 when a letter, digit, _ or non-ASCII byte is at or before pos
lk_in_word:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call doc_len
    cmp r12, rax
    jae 1f
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jnz 9f
1:  test r12, r12
    jz 8f
    mov rdi, rbx
    lea rsi, [r12 - 1]
    call doc_byte
    mov edi, eax
    call is_ident
    test eax, eax
    jnz 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# lk_live(doc) -> rax the document's linked session, or 0 (each document keeps its own: the
# session and its word characters live in its snippet node)
lk_live:
    mov rax, [rdi + DOC_snippet]
    test rax, rax
    jz 8f
    cmp qword ptr [rax + SN_linked], 0
    jne 9f
8:  xor eax, eax
9:  ret

# FN ws_linked_tick(): the cursor's place followed; after it rested 150 ms inside a word of a
# matching document, with one selection and no field session, the provider is asked
FN ws_linked_tick
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Llt_none
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne .Llt_none
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + lk_doc_id]
    jne .Llt_moved
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + lk_ver]
    jne .Llt_moved
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + lk_cur]
    jne .Llt_moved
    cmp qword ptr [rip + lk_asked], 0
    jne 9f
    call time_ms
    sub rax, [rip + lk_since]
    cmp rax, LK_REST
    jb 9f
    mov qword ptr [rip + lk_asked], 1
    # one caret, no field session, inside a word, a provider, a document that fits
    cmp qword ptr [rbx + DOC_selections], 0
    jne 9f
    mov rax, [rbx + DOC_cur]
    cmp rax, [rbx + DOC_anchor]
    jne 9f
    cmp qword ptr [rbx + DOC_snippet], 0
    jne 9f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 9f
    mov rdi, rbx
    call doc_len
    cmp rax, LK_DOC_MAX
    ja 9f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lk_in_word
    test eax, eax
    jz 9f
    mov rdi, rbx
    call lk_provider
    test rax, rax
    jz 9f
    mov r12, rax
    # "linked DOC VERSION LINE COL"
    lea rdi, [rip + lk_text]
    call sb_clear
    lea rdi, [rip + lk_text]
    lea rsi, [rip + .Lv_linked]
    call sb_push_cstr
    lea rdi, [rip + lk_text]
    mov rsi, [rbx + DOC_id]
    call sb_push_u64
    lea rdi, [rip + lk_text]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lk_text]
    mov rsi, [rbx + DOC_version]
    call sb_push_u64
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lf_line_col_pub
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + lk_text]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lk_text]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + lk_text]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lk_text]
    mov rsi, r14
    call sb_push_u64
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rip + lk_text + SB_ptr]
    mov rcx, [rip + lk_text + SB_len]
    xor r8d, r8d
    xor r9d, r9d
    call extproto_host_send_body
    test rax, rax
    jz 9f
    mov [rip + lk_ext], r12
    mov [rip + lk_id], rax
    mov rdi, r12
    mov rsi, rax
    mov edx, PK_LINKED
    mov ecx, QO_LINKED
    call query_track
    jmp 9f
.Llt_moved:
    call lk_reset
    mov rax, [rbx + DOC_id]
    mov [rip + lk_doc_id], rax
    mov rax, [rbx + DOC_version]
    mov [rip + lk_ver], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + lk_cur], rax
    call time_ms
    mov [rip + lk_since], rax
    jmp 9f
.Llt_none:
    cmp qword ptr [rip + lk_doc_id], 0
    je 9f
    call lk_reset
    mov qword ptr [rip + lk_doc_id], 0
9:  EPILOGUE

# FN ws_linked_timeout() -> ms until the resting cursor is asked about, or -1
FN ws_linked_timeout
    mov rax, -1
    cmp qword ptr [rip + lk_doc_id], 0
    je 9f
    cmp qword ptr [rip + lk_asked], 0
    jne 9f
    push rbx
    call time_ms
    mov rcx, [rip + lk_since]
    add rcx, LK_REST
    sub rcx, rax
    jns 1f
    xor ecx, ecx
1:  mov rax, rcx
    pop rbx
9:  ret

# FN ws_linked_reply(ext, id, ok, body, len) -> eax 1 when it answered rhun's linked request: its
# ranges (at the version asked, equal text, not overlapping, one holding the cursor) become a
# linked session; an answer that breaks a rule, or comes for another place, is dropped
FN ws_linked_reply
    PROLOGUE 48
    cmp rdi, [rip + lk_ext]
    jne .Llr_not
    cmp rsi, [rip + lk_id]
    jne .Llr_not
    mov qword ptr [rip + lk_ext], 0
    test edx, edx
    jz .Llr_done
    mov [rsp], rdi
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    # the place asked about, still where the cursor is
    mov rdi, [rip + lk_doc_id]
    call extproto_doc
    test rax, rax
    jz .Llr_done
    mov rbx, rax
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + lk_ver]
    jne .Llr_done
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + lk_cur]
    jne .Llr_done
    cmp rax, [rbx + DOC_anchor]
    jne .Llr_done
    cmp qword ptr [rbx + DOC_snippet], 0
    jne .Llr_done
    cmp qword ptr [rbx + DOC_selections], 0
    jne .Llr_done
    # "N", then N lines "L1 C1 L2 C2"
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov edx, LK_RANGES_MAX
    call lf_head
    test rax, rax
    js .Llr_done
    mov r12, rax                # N
    test r12, r12
    jz .Llr_done                # none
    cmp r12, 2
    jb .Llr_done
    xor r13d, r13d
    mov r15, -1                 # the range holding the cursor
1:  cmp r13, r12
    jae 3f
    call ps_line
    test eax, eax
    jz .Llr_done
    call lf_four
    test eax, eax
    jz .Llr_done
    call ps_eol
    test eax, eax
    jz .Llr_done
    lea rcx, [rip + lf_tmp4]
    mov rdi, rbx
    mov esi, [rcx]
    mov edx, [rcx + 4]
    call lf_pos
    test rax, rax
    js .Llr_done
    mov r14, rax
    lea rcx, [rip + lf_tmp4]
    mov rdi, rbx
    mov esi, [rcx + 8]
    mov edx, [rcx + 12]
    call lf_pos
    test rax, rax
    js .Llr_done
    cmp rax, r14
    jb .Llr_done
    mov rcx, r13
    shl rcx, 4
    lea rdx, [rip + lk_ranges]
    mov [rdx + rcx], r14
    mov [rdx + rcx + 8], rax
    mov rdx, [rip + lk_cur]
    cmp rdx, r14
    jb 2f
    cmp rdx, rax
    ja 2f
    cmp r15, -1
    jne 2f
    mov r15, r13
2:  inc r13
    jmp 1b
3:  cmp r15, -1
    je .Llr_done
    # the word record: the characters besides letters, digits and non-ASCII ("-_.:" by default)
    lea rdi, [rip + lk_words]
    xor esi, esi
    mov edx, 256
    call memset
    lea rsi, [rip + .Ldefault_word]
    mov ecx, 4
    lea rdi, [rip + lk_words]
4:  movzx eax, byte ptr [rsi]
    mov byte ptr [rdi + rax], 1
    inc rsi
    dec ecx
    jnz 4b
.Llr_records:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jae 6f
    call ps_line
    test eax, eax
    jz .Llr_done
    call ps_word
    mov r13, rax
    mov r14, rdx
    call ps_num
    test edx, edx
    jz .Llr_done
    mov [rsp + 24], rax         # its length
    call ps_eol
    test eax, eax
    jz .Llr_done
    mov rdi, [rsp + 24]
    call lf_take
    test rax, rax
    jz .Llr_done
    mov [rsp + 32], rax
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lr_word]
    call str_eq_cstr
    test eax, eax
    jz .Llr_records             # another record: skipped
    lea rdi, [rip + lk_words]
    xor esi, esi
    mov edx, 256
    call memset
    mov rsi, [rsp + 32]
    mov rcx, [rsp + 24]
5:  test rcx, rcx
    jz .Llr_records
    movzx eax, byte ptr [rsi]
    cmp eax, 0x80
    jae 51f
    cmp eax, 0x20
    jbe 51f
    lea rdx, [rip + lk_words]
    mov byte ptr [rdx + rax], 1
51: inc rsi
    dec rcx
    jmp 5b
6:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call lk_start
.Llr_done:
    mov eax, 1
    EPILOGUE
.Llr_not:
    xor eax, eax
    EPILOGUE

# lk_start(doc, n, primary): a linked session over lk_ranges: one group, the primary range its
# first field; the snippet engine checks that the ranges have equal text and do not overlap (an
# answer that breaks that makes no session); the cursor stays where it is
lk_start:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    # the text the fields are checked against: the document's
    lea rdi, [rip + lk_text]
    call sb_clear
    mov rdi, rbx
    call doc_len
    mov r14, rax
    lea rdi, [rip + lk_text]
    lea rsi, [rax + 1]
    call sb_reserve
    mov rdi, rbx
    xor esi, esi
    mov rdx, r14
    mov rcx, rax
    call doc_copy
    mov [rip + lk_text + SB_len], r14
    mov rdi, [rip + lk_text + SB_ptr]
    mov rsi, r14
    call snippet_new
    mov r15, rax
    # the primary first, then the others: group 1
    mov rcx, r13
    shl rcx, 4
    lea rax, [rip + lk_ranges]
    mov rdi, r15
    mov esi, 1
    mov rdx, [rax + rcx]
    mov rcx, [rax + rcx + 8]
    xor r8d, r8d
    call snippet_add
    xor r14d, r14d
1:  cmp r14, r12
    jae 2f
    cmp r14, r13
    je 11f
    mov rcx, r14
    shl rcx, 4
    lea rax, [rip + lk_ranges]
    mov rdi, r15
    mov esi, 1
    mov rdx, [rax + rcx]
    mov rcx, [rax + rcx + 8]
    xor r8d, r8d
    call snippet_add
11: inc r14
    jmp 1b
2:  mov rdi, r15
    call snippet_validate
    test eax, eax
    jz 8f
    mov qword ptr [r15 + SN_linked], 1
    # its word characters, as bits in the node (lk_words is the answer's, shared)
    mov qword ptr [r15 + SN_lwords], 0
    mov qword ptr [r15 + SN_lwords + 8], 0
    xor r14d, r14d
21: lea rax, [rip + lk_words]
    cmp byte ptr [rax + r14], 0
    je 22f
    mov rdx, r14
    shr rdx, 6                  # its quad
    mov ecx, r14d
    and ecx, 63
    mov eax, 1
    shl rax, cl
    or [r15 + SN_lwords + rdx*8], rax
22: inc r14d
    cmp r14d, 128
    jb 21b
    mov rax, [rbx + DOC_cur]
    mov [rsp], rax
    mov rax, [rbx + DOC_anchor]
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r15
    xor edx, edx
    call snippet_push           # selects the primary field: the caret goes back where it was
    mov rax, [rsp]
    mov [rbx + DOC_cur], rax
    mov rax, [rsp + 8]
    mov [rbx + DOC_anchor], rax
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
8:  mov rdi, r15
    call snippet_free_node
    EPILOGUE

# FN ws_linked_typed(doc, codepoint): before a character is typed: in a linked session, one that
# is not a letter, digit, non-ASCII or one of its word characters ends the session first (it is
# not mirrored)
FN ws_linked_typed
    push rbx
    mov rbx, rdi
    call lk_live
    test rax, rax
    jz 9f
    cmp esi, 0x80
    jae 9f
    mov edi, esi
    push rsi
    push rsi
    call is_ident
    pop rsi
    pop rsi
    test eax, eax
    jnz 9f
    mov rax, [rbx + DOC_snippet]
    mov ecx, esi
    mov edx, esi
    shr edx, 6
    mov rax, [rax + SN_lwords + rdx*8]
    and ecx, 63
    shr rax, cl
    test eax, 1
    jnz 9f                      # one of its word characters
    mov rdi, rbx
    call snippet_forget
9:  pop rbx
    ret

# FN ws_linked_passes(doc) -> eax 1 when the document's field session is a linked one (Tab and
# shift+Tab are not its: they reach the editor)
FN ws_linked_passes
    call lk_live
    test rax, rax
    setnz al
    movzx eax, al
    ret

# FN ws_linked_row(line text, line start, row from, row to, x of column 0, y): draw_line's row of
# the active document: a thin outline around each live range of its linked session on the row
# (its ends placed through the row's inlays, vt_x)
FN ws_linked_row
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8d
    mov [rsp + 36], r9d
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 9f
    call lk_live
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r12d, r12d
1:  cmp r12, [rbx + SN_nfields]
    jae 9f
    imul r13, r12, SF_SIZE
    lea r13, [rbx + r13 + SN_fields]
    inc r12
    test qword ptr [r13 + SF_flags], 1
    jz 1b
    # the part of [start, end) on this row: [row from, row to) of the line
    mov rax, [r13 + SF_start]
    sub rax, [rsp + 8]
    mov rcx, [r13 + SF_end]
    sub rcx, [rsp + 8]
    cmp rcx, [rsp + 16]
    jl 1b
    cmp rax, [rsp + 24]
    jg 1b
    cmp rax, [rsp + 16]
    jge 2f
    mov rax, [rsp + 16]
2:  cmp rcx, [rsp + 24]
    jle 3f
    mov rcx, [rsp + 24]
3:  mov [rsp + 40], rcx
    # x of both ends through the row's inlays (vtext.s: draw_line set the row up), as a selection's
    mov rdi, rax
    mov esi, VTM_RIGHT          # after the inlays at its start
    call vt_x
    mov r14d, eax               # x
    mov rdi, [rsp + 40]
    mov esi, VTM_LEFT           # before those at its end
    call vt_x
    mov r15d, eax
    sub r15d, r14d              # width
    jg 4f
    mov r15d, 1                 # an empty range still shows where it is
4:  # top, bottom, left, right
    mov edi, r14d
    mov esi, [rsp + 36]
    mov edx, r15d
    mov ecx, 1
    COLOR r8d, T_MUTED
    call gfx_fill
    mov edi, r14d
    mov esi, [rsp + 36]
    add esi, [rip + g_lh]
    dec esi
    mov edx, r15d
    mov ecx, 1
    COLOR r8d, T_MUTED
    call gfx_fill
    mov edi, r14d
    mov esi, [rsp + 36]
    mov edx, 1
    mov ecx, [rip + g_lh]
    COLOR r8d, T_MUTED
    call gfx_fill
    mov edi, r14d
    add edi, r15d
    dec edi
    mov esi, [rsp + 36]
    mov edx, 1
    mov ecx, [rip + g_lh]
    COLOR r8d, T_MUTED
    call gfx_fill
    jmp 1b
9:  EPILOGUE

# FN ws_linked_print(sb): print-linked: "linked=N" and "L1 C1 L2 C2" per live range (the primary
# first), or "linked=none"
FN ws_linked_print
    PROLOGUE
    mov r15, rdi
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 8f
    mov r14, rdi
    call lk_live
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r12d, r12d              # live ranges
    xor ecx, ecx
1:  cmp rcx, [rbx + SN_nfields]
    jae 2f
    imul rax, rcx, SF_SIZE
    inc rcx
    test qword ptr [rbx + rax + SN_fields + SF_flags], 1
    jz 1b
    inc r12
    jmp 1b
2:  mov rdi, r15
    lea rsi, [rip + .Lp_linked]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, r12
    call sb_push_u64
    mov rdi, r15
    mov esi, 10
    call sb_push_byte
    xor r12d, r12d
3:  cmp r12, [rbx + SN_nfields]
    jae 9f
    imul r13, r12, SF_SIZE
    lea r13, [rbx + r13 + SN_fields]
    inc r12
    test qword ptr [r13 + SF_flags], 1
    jz 3b
    mov rdi, r14
    mov rsi, [r13 + SF_start]
    call lf_line_col_pub
    mov [rsp], rdx
    mov rdi, r15
    mov rsi, rax
    call sb_push_u64
    mov rdi, r15
    mov esi, ' '
    call sb_push_byte
    mov rdi, r15
    mov rsi, [rsp]
    call sb_push_u64
    mov rdi, r15
    mov esi, ' '
    call sb_push_byte
    mov rdi, r14
    mov rsi, [r13 + SF_end]
    call lf_line_col_pub
    mov [rsp], rdx
    mov rdi, r15
    mov rsi, rax
    call sb_push_u64
    mov rdi, r15
    mov esi, ' '
    call sb_push_byte
    mov rdi, r15
    mov rsi, [rsp]
    call sb_push_u64
    mov rdi, r15
    mov esi, 10
    call sb_push_byte
    jmp 3b
8:  mov rdi, r15
    lea rsi, [rip + .Lp_none]
    call sb_push_cstr
9:  EPILOGUE

# lf_line_col_pub(doc, pos) -> rax 1-based line, rdx 1-based byte column
lf_line_col_pub:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov rdx, r12
    sub rdx, rax
    inc rdx
    lea rax, [r13 + 1]
    pop r13
    pop r12
    pop rbx
    ret

.section .rodata
.Lv_linked: .asciz "linked "
.Lr_word: .asciz "word"
.Ldefault_word: .ascii "-_.:"
.Lp_linked: .asciz "linked="
.Lp_none: .asciz "linked=none\n"
