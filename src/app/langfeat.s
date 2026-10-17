# language features from extensions (docs/extensions/v1.md, 12d to 12h): Go to Definition, Find All
# References, Go to Symbol, code actions, rename and format. A query asks the providers, waits for
# their answers (state only while extproto's pump runs; the tick finishes it), then shows a list in
# the palette, goes to a place, or applies a workspace edit.
.include "rhun.inc"

.equ LF_DEF, 1
.equ LF_REFS, 2
.equ LF_SYMS, 3
.equ LF_ACTS, 4
.equ LF_RENAME, 5
.equ LF_FORMAT, 6
.equ LF_MAX, 10000              # locations or symbols in one answer
.equ LF_ACTS_MAX, 1000
.equ LF_BODY_MAX, 1048576
.equ WS_BODY_MAX, 4194304       # a workspace edit (12g)
.equ WS_FILES_MAX, 1000
.equ WS_EDITS_MAX, 100000
.equ WS_SORT_MAX, 5000          # a file's edits out of order are sorted up to this many
.equ LR_MAX, 64

# a request rhun waits on
STRUCT
F LR_ext, 8
F LR_id, 8
F LR_session, 4
F LR_pad, 4
ENDSTRUCT LR_SIZE

# a result: a location, a symbol or an action
STRUCT
F LS_ext, 8                     # who gave it (an action's data goes back to it)
F LS_path, 8                    # offset in lf_bytes of its path, a cstr ("#ID" for a document), or -1: the asked document
F LS_l1, 4
F LS_c1, 4
F LS_l2, 4
F LS_c2, 4
F LS_label, 8                   # offset of the palette's label (cstr)
F LS_detail, 8                  # offset of the detail (cstr), or -1
F LS_edit, 8                    # an action's workspace edit: offset and length
F LS_elen, 8
F LS_data, 8                    # and the bytes it sends back
F LS_dlen, 8
F LS_rank, 4                    # the order: lower first
F LS_pad, 4
ENDSTRUCT LS_SIZE

# a group of a workspace edit: one file
STRUCT
F WG_path, 8                    # its PATH bytes
F WG_plen, 8
F WG_version, 8                 # -1: not open
F WG_doc, 8                     # DOC* once resolved
F WG_first, 8                   # its edits: we[first .. first + count)
F WG_count, 8
ENDSTRUCT WG_SIZE

# an edit of a workspace edit
STRUCT
F WE_l1, 4
F WE_c1, 4
F WE_l2, 4
F WE_c2, 4
F WE_start, 8                   # byte offsets, once resolved
F WE_end, 8
F WE_text, 8
F WE_len, 8
ENDSTRUCT WE_SIZE

.bss
.p2align 3
lf_kind: .long 0                # the query in flight (LF_*), 0 for none
lf_session: .long 0
lf_ready: .long 0               # every provider answered: the tick finishes it
lf_list_kind: .long 0           # what the palette's list shows
lf_doc: .quad 0                 # the document asked about, and its id
lf_doc_id: .quad 0
lf_deadline: .quad 0
lf_ws_ext: .quad 0
lf_reqs: .zero VEC_SIZE         # LR records
lf_res: .zero VEC_SIZE          # LS records
lf_bytes: .zero SB_SIZE         # their strings
lf_ws: .zero SB_SIZE            # a workspace edit to apply (rename, format)
lf_line: .zero SB_SIZE          # a request being built
lf_name: .zero SB_SIZE          # the new name of a rename
lf_err: .zero 256               # what the rename provider said instead
wg_vec: .zero VEC_SIZE          # a workspace edit being applied
we_vec: .zero VEC_SIZE
lf_path: .zero 4100             # a path as a cstr

.text

# ---------------- helpers ----------------

# lf_focused_doc() -> rax g_doc when a document tab's editor has the keyboard, else 0
lf_focused_doc:
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 8f
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rax, [rip + g_doc]
    ret
8:  xor eax, eax
    ret

# lf_is_word(byte) -> eax 1 for a letter, a digit, _ or a byte of a multibyte character
lf_is_word:
    cmp edi, 0x80
    jae 1f
    cmp edi, '_'
    je 1f
    mov eax, edi
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 26
    jb 1f
    mov eax, edi
    sub eax, '0'
    cmp eax, 10
    jb 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

# lf_pos(doc, line, col) -> rax byte offset of a 1-based line and byte column, or -1 when it is not
# in the text (or inside a character)
lf_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz 8f
    test r13, r13
    jz 8f
    cmp r12, [rbx + DOC_nlines]
    ja 8f
    dec r12
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    lea rcx, [r14 + r13 - 1]
    cmp rcx, rax
    ja 8f
    mov r15, rcx
    cmp rcx, rax
    je 1f                       # the line's end
    mov rdi, rbx
    mov rsi, rcx
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
1:  mov rax, r15
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# lf_pos_near(doc, line, col) -> rax the offset of the nearest place in the text: a line past the
# end is the last, a column past the end of its line that end, inside a character its start
lf_pos_near:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jnz 1f
    mov r12d, 1
1:  cmp r12, [rbx + DOC_nlines]
    jbe 2f
    mov r12, [rbx + DOC_nlines]
2:  test r13, r13
    jnz 3f
    mov r13d, 1
3:  dec r12
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    lea r15, [r14 + r13 - 1]
    cmp r15, rax
    jbe 4f
    mov r15, rax
4:  cmp r15, r14
    jbe 5f
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    jne 5f
    dec r15
    jmp 4b
5:  mov rax, r15
    EPILOGUE

# lf_line_col(doc, pos) -> rax 1-based line, rdx 1-based byte column
lf_line_col:
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

# lf_push_num(sb, n) and lf_push_sp(sb): a number, a space
lf_push_num:
    jmp sb_push_u64
lf_push_sp:
    mov esi, ' '
    jmp sb_push_byte

# lf_str(ptr, len) -> rax the offset in lf_bytes of a copy, as a cstr
lf_str:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + lf_bytes + SB_len]
    lea rdi, [rip + lf_bytes]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + lf_bytes]
    xor esi, esi
    call sb_push_byte
    mov rax, rbx
    EPILOGUE

# lf_cancel_all(): "0 cancel ID" for the requests still out, and forget them
lf_cancel_all:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + lf_reqs + VEC_len]
    jae 2f
    imul rax, rbx, LR_SIZE
    add rax, [rip + lf_reqs + VEC_ptr]
    inc rbx
    mov rdi, [rax + LR_ext]
    mov rsi, [rax + LR_id]
    cmp dword ptr [rdi + EXT_status], ES_RUNNING
    jne 1b
    call extproto_send_cancel
    jmp 1b
2:  mov qword ptr [rip + lf_reqs + VEC_len], 0
    EPILOGUE

# lf_reset(): the query before goes, and the list it showed
lf_reset:
    push rbx
    call lf_cancel_all
    call palette_results_close
    mov dword ptr [rip + lf_kind], 0
    mov dword ptr [rip + lf_ready], 0
    mov dword ptr [rip + lf_list_kind], 0
    mov qword ptr [rip + lf_res + VEC_len], 0
    lea rdi, [rip + lf_bytes]
    call sb_clear
    lea rdi, [rip + lf_ws]
    call sb_clear
    mov byte ptr [rip + lf_err], 0
    pop rbx
    ret

# ---------------- asking ----------------

# lf_start(kind): ask the providers of the focused document
lf_start:
    PROLOGUE 16
    mov r12d, edi
    call lf_focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    call lf_reset
    mov [rip + lf_kind], r12d
    inc dword ptr [rip + lf_session]
    mov [rip + lf_doc], rbx
    mov rax, [rbx + DOC_id]
    mov [rip + lf_doc_id], rax
    call time_ms
    lea rcx, [rip + lf_waits]
    add rax, [rcx + r12*8]
    mov [rip + lf_deadline], rax
    # the request: VERB DOC VERSION, then what the kind takes
    lea rdi, [rip + lf_line]
    call sb_clear
    lea rax, [rip + lf_verbs]
    mov rsi, [rax + r12*8]
    lea rdi, [rip + lf_line]
    call sb_push_cstr
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    mov rsi, [rbx + DOC_id]
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    mov rsi, [rbx + DOC_version]
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    cmp r12d, LF_ACTS
    je 3f
    cmp r12d, LF_FORMAT
    je 4f
    # LINE COL KIND CHAR: the cursor
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lf_line_col
    mov [rsp], rdx
    lea rdi, [rip + lf_line]
    mov rsi, rax
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    mov rsi, [rsp]
    call lf_push_num
    lea rdi, [rip + lf_line]
    lea rsi, [rip + .Linvoked]
    call sb_push_cstr
    cmp r12d, LF_RENAME
    jne 21f
    lea rdi, [rip + lf_line]
    mov rsi, [rip + lf_name + SB_ptr]
    mov rdx, [rip + lf_name + SB_len]
    call sb_push
    jmp 5f
21: lea rdi, [rip + lf_line]
    mov esi, '-'
    call sb_push_byte
    jmp 5f
3:  # L1 C1 L2 C2: the selection, or the cursor
    mov rdi, rbx
    call ed_sel
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov rsi, rax
    call lf_line_col
    mov [rsp], rdx
    lea rdi, [rip + lf_line]
    mov rsi, rax
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    mov rsi, [rsp]
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call lf_line_col
    mov [rsp], rdx
    lea rdi, [rip + lf_line]
    mov rsi, rax
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    mov rsi, [rsp]
    call lf_push_num
    jmp 5f
4:  # TAB_WIDTH SPACES: the document's own settings
    call ext_options_apply
    lea rdi, [rip + lf_line]
    mov esi, [rip + g_tab_width]
    call lf_push_num
    lea rdi, [rip + lf_line]
    call lf_push_sp
    lea rdi, [rip + lf_line]
    lea rsi, [rip + .Lyes]
    cmp dword ptr [rip + g_insert_spaces], 0
    jne 41f
    lea rsi, [rip + .Lno]
41: call sb_push_cstr
5:  # to every provider of it whose patterns match (the first, for one-provider kinds)
    xor r13d, r13d
    mov dword ptr [rsp + 8], 0
6:  cmp r13, [rip + g_exts + VEC_len]
    jae 8f
    imul r14, r13, EXT_SIZE
    add r14, [rip + g_exts + VEC_ptr]
    inc r13
    cmp dword ptr [r14 + EXT_status], ES_RUNNING
    jne 6b
    lea rax, [rip + lf_feats]
    mov eax, [rax + r12*4]
    test [r14 + EXT_features], eax
    jz 6b
    lea rax, [rip + lf_pvs]
    mov rax, [rax + r12*8]
    mov rdi, [r14 + rax]
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 6b
    cmp qword ptr [rip + lf_reqs + VEC_len], LR_MAX
    jae 8f
    mov rdi, r14
    mov rsi, rbx
    mov rdx, [rip + lf_line + SB_ptr]
    mov rcx, [rip + lf_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz 6b
    mov r15, rax
    lea rdi, [rip + lf_reqs]
    mov esi, LR_SIZE
    call vec_push
    mov [rax + LR_ext], r14
    mov [rax + LR_id], r15
    mov ecx, [rip + lf_session]
    mov [rax + LR_session], ecx
    inc dword ptr [rsp + 8]
    lea rax, [rip + lf_single]
    cmp byte ptr [rax + r12], 0
    je 6b
8:  cmp dword ptr [rsp + 8], 0
    jne 9f
    # nobody to ask
    mov dword ptr [rip + lf_kind], 0
    lea rax, [rip + lf_none]
    mov rdi, [rax + r12*8]
    call app_toast
9:  EPILOGUE

FN cmd_definition
    mov edi, LF_DEF
    jmp lf_start_cmd
FN cmd_references
    mov edi, LF_REFS
    jmp lf_start_cmd
FN cmd_symbols
    mov edi, LF_SYMS
    jmp lf_start_cmd
FN cmd_code_actions
    mov edi, LF_ACTS
    jmp lf_start_cmd
FN cmd_format_document
    mov edi, LF_FORMAT
lf_start_cmd:
    push rbx
    call lf_start
    pop rbx
    ret

# FN langfeat_rename_start() -> eax 1 when the focused document has a rename provider: the palette
# asks for the new name, the word under the cursor filled in (F2 renames the file otherwise)
FN langfeat_rename_start
    PROLOGUE 16
    call lf_focused_doc
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 8f
    imul r14, r13, EXT_SIZE
    add r14, [rip + g_exts + VEC_ptr]
    inc r13
    cmp dword ptr [r14 + EXT_status], ES_RUNNING
    jne 1b
    test dword ptr [r14 + EXT_features], FEAT_RENAME
    jz 1b
    mov rdi, [r14 + EXT_pv_rename]
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 1b
    # the word under the cursor
    mov r12, [rbx + DOC_cur]
2:  test r12, r12
    jz 3f
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_byte
    mov edi, eax
    call lf_is_word
    test eax, eax
    jz 3f
    dec r12
    jmp 2b
3:  mov r13, [rbx + DOC_cur]
    mov rdi, rbx
    call doc_len
    mov r14, rax
4:  cmp r13, r14
    jae 5f
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    mov edi, eax
    call lf_is_word
    test eax, eax
    jz 5f
    inc r13
    jmp 4b
5:  sub r13, r12
    cmp r13, 200
    jbe 6f
    xor r13d, r13d              # not a word anyone renames
6:  lea rdi, [rip + lf_name]
    call sb_clear
    lea rdi, [rip + lf_name]
    mov rsi, r13
    call sb_reserve
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    call doc_copy
    mov [rip + lf_name + SB_len], r13
    lea rdi, [rip + .Lrename_to]
    mov esi, PROMPT_RENAME_SYMBOL
    mov rdx, [rip + lf_name + SB_ptr]
    mov rcx, r13
    call palette_ext_prompt_open
    call palette_field
    mov rdi, rax
    call tf_select_all
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN langfeat_rename_to(ptr, len): the palette's answer: the new name, then the request
FN langfeat_rename_to
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    test r13, r13
    jz 9f
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    movzx eax, byte ptr [r12 + rcx]
    inc rcx
    cmp eax, ' '
    ja 1b
    lea rdi, [rip + .Lname_spaces]
    call app_toast
    jmp 9f
2:  lea rdi, [rip + lf_name]
    call sb_clear
    lea rdi, [rip + lf_name]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov edi, LF_RENAME
    call lf_start
9:  EPILOGUE

# ---------------- answers ----------------

# FN langfeat_reply(ext, id, ok, body, len): an extension answered (from extproto's pump: state
# only; an error's body is its CODE TEXT)
FN langfeat_reply
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov r14, rcx
    mov r15, r8
    xor r13d, r13d
1:  cmp r13, [rip + lf_reqs + VEC_len]
    jae 9f
    imul rax, r13, LR_SIZE
    add rax, [rip + lf_reqs + VEC_ptr]
    cmp [rax + LR_ext], rbx
    jne 2f
    cmp [rax + LR_id], r12
    je 3f
2:  inc r13
    jmp 1b
3:  mov ecx, [rax + LR_session]
    mov [rsp + 4], ecx
    # its record goes
    mov rax, [rip + lf_reqs + VEC_len]
    dec rax
    mov [rip + lf_reqs + VEC_len], rax
    sub rax, r13
    jz 4f
    imul rdx, rax, LR_SIZE
    imul rsi, r13, LR_SIZE
    add rsi, [rip + lf_reqs + VEC_ptr]
    mov rdi, rsi
    add rsi, LR_SIZE
    call memmove
4:  mov eax, [rsp + 4]
    cmp eax, [rip + lf_session]
    jne 9f
    mov eax, [rip + lf_kind]
    test eax, eax
    jz 9f
    cmp dword ptr [rsp], 0
    je 6f
    cmp eax, LF_SYMS
    je 51f
    cmp eax, LF_ACTS
    je 52f
    cmp eax, LF_RENAME
    jae 53f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call lf_parse_locations
    jmp 7f
51: mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call lf_parse_symbols
    jmp 7f
52: mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call lf_parse_actions
    jmp 7f
53: # rename, format: the workspace edit, applied when the query finishes
    cmp r15, WS_BODY_MAX
    ja 7f
    lea rdi, [rip + lf_ws]
    call sb_clear
    lea rdi, [rip + lf_ws]
    mov rsi, r14
    mov rdx, r15
    call sb_push
    mov [rip + lf_ws_ext], rbx
    jmp 7f
6:  # an error: a rename's text (after the code) is the user's to read
    cmp eax, LF_RENAME
    jne 7f
62: test r15, r15
    jz 7f
    dec r15
    movzx eax, byte ptr [r14]
    inc r14
    cmp eax, ' '
    jne 62b
    mov rcx, r15
    cmp rcx, 200
    jbe 61f
    mov ecx, 200
61: lea rdi, [rip + lf_err]
    mov rsi, r14
    mov rdx, rcx
    push rcx
    push rcx
    call memcpy
    pop rcx
    pop rcx
    lea rax, [rip + lf_err]
    mov byte ptr [rax + rcx], 0
7:  # the last answer of the session: the tick finishes the query
    xor ecx, ecx
71: cmp rcx, [rip + lf_reqs + VEC_len]
    jae 72f
    imul rax, rcx, LR_SIZE
    add rax, [rip + lf_reqs + VEC_ptr]
    inc rcx
    mov edx, [rax + LR_session]
    cmp edx, [rip + lf_session]
    je 9f
    jmp 71b
72: mov dword ptr [rip + lf_ready], 1
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# lf_check_lines(body, len, n_max) -> eax N when the body starts with "N LF" (N at most n_max), with
# ps_ptr past that line; -1 otherwise
lf_head:
    PROLOGUE
    mov rbx, rdx
    mov [rip + ps_ptr], rdi
    lea rax, [rdi + rsi]
    mov [rip + ps_end], rax
    call ps_line
    test eax, eax
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    cmp rax, rbx
    ja 8f
    mov r12, rax
    call ps_eol
    test eax, eax
    jz 8f
    mov rax, r12
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# lf_take(n) -> rax ptr of the next n bytes of the body (ps_ptr moves past them), or 0 when there are
# not that many
lf_take:
    mov rax, [rip + ps_end]
    sub rax, [rip + ps_ptr]
    cmp rdi, rax
    ja 8f
    mov rax, [rip + ps_ptr]
    add [rip + ps_ptr], rdi
    ret
8:  xor eax, eax
    ret

# lf_four() -> eax 1 with the next four numbers in lf_tmp4 (dwords)
lf_four:
    push rbx
    xor ebx, ebx
1:  cmp ebx, 4
    jae 2f
    call ps_num
    test edx, edx
    jz 8f
    lea rcx, [rip + lf_tmp4]
    mov [rcx + rbx*4], eax
    inc ebx
    jmp 1b
2:  mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# lf_rollback(results, bytes): an answer that broke the rules leaves nothing behind
lf_rollback:
    mov [rip + lf_res + VEC_len], rdi
    mov [rip + lf_bytes + SB_len], rsi
    ret

# lf_parse_locations(ext, body, len): "N", then L1 C1 L2 C2 PATH_LEN TEXT_LEN and the bytes
lf_parse_locations:
    PROLOGUE 48
    mov [rsp], rdi
    mov rax, [rip + lf_res + VEC_len]
    mov [rsp + 8], rax
    mov rax, [rip + lf_bytes + SB_len]
    mov [rsp + 16], rax
    cmp rdx, LF_BODY_MAX
    ja 8f
    mov rdi, rsi
    mov rsi, rdx
    mov edx, LF_MAX
    call lf_head
    test rax, rax
    js 8f
    mov r15, rax
1:  test r15, r15
    jz 9f
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call lf_four
    test eax, eax
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f                       # a location has a path
    cmp rax, 4096
    ja 8f
    mov r12, rax
    call ps_num
    test edx, edx
    jz 8f
    mov r13, rax
    call ps_eol
    test eax, eax
    jz 8f
    mov rdi, r12
    call lf_take
    test rax, rax
    jz 8f
    mov r14, rax                # the path
    mov rdi, r13
    call lf_take
    test rax, rax
    jz 8f
    mov rbx, rax                # the preview
    # the record: its path, its label "name:line  preview", the folder as its detail
    mov rdi, r14
    mov rsi, r12
    call lf_str
    mov [rsp + 24], rax
    mov rdi, rbx
    mov rsi, r13
    call lf_location_label
    mov [rsp + 32], rax
    mov [rsp + 40], rdx
    lea rdi, [rip + lf_res]
    mov esi, LS_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + LS_ext], rcx
    mov rcx, [rsp + 24]
    mov [rax + LS_path], rcx
    lea rcx, [rip + lf_tmp4]
    mov edx, [rcx]
    mov [rax + LS_l1], edx
    mov edx, [rcx + 4]
    mov [rax + LS_c1], edx
    mov edx, [rcx + 8]
    mov [rax + LS_l2], edx
    mov edx, [rcx + 12]
    mov [rax + LS_c2], edx
    mov rcx, [rsp + 32]
    mov [rax + LS_label], rcx
    mov rcx, [rsp + 40]
    mov [rax + LS_detail], rcx
    jmp 1b
8:  mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    call lf_rollback
9:  EPILOGUE

# lf_location_label(preview, len) -> rax the label's offset ("name:line  preview"), rdx the
# detail's (the folder) for the location whose path offset is at [rsp + 24 + 16 + 8] of the caller
# and its first line in lf_tmp4
lf_location_label:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov rax, [rbp + 16 + 24]    # the caller's path offset
    add rax, [rip + lf_bytes + SB_ptr]
    mov rbx, rax                # the path (cstr; lf_bytes does not move until the next push)
    mov rdi, rax
    call strlen
    mov r14, rax
    # the name: after the last / or \\
    mov r15, r14
1:  test r15, r15
    jz 2f
    movzx eax, byte ptr [rbx + r15 - 1]
    cmp eax, '/'
    je 2f
    cmp eax, '\\'
    je 2f
    dec r15
    jmp 1b
2:  # the label, built in lf_line then copied in (lf_bytes moves as it grows)
    lea rdi, [rip + lf_line]
    call sb_clear
    lea rdi, [rip + lf_line]
    lea rsi, [rbx + r15]
    mov rdx, r14
    sub rdx, r15
    call sb_push
    lea rdi, [rip + lf_line]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + lf_line]
    mov esi, [rip + lf_tmp4]
    call sb_push_u64
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    # the preview without its indentation or line breaks, at most 200 bytes
30: test r13, r13
    jz 33f
    movzx eax, byte ptr [r12]
    cmp eax, ' '
    je 34f
    cmp eax, 9
    jne 33f
34: inc r12
    dec r13
    jmp 30b
33: xor ecx, ecx
3:  cmp rcx, r13
    jae 4f
    cmp rcx, 200
    jae 4f
    movzx esi, byte ptr [r12 + rcx]
    cmp esi, 10
    je 31f
    cmp esi, 13
    je 31f
    cmp esi, 9
    jne 32f
31: mov esi, ' '
32: push rcx
    push rcx
    lea rdi, [rip + lf_line]
    call sb_push_byte
    pop rcx
    pop rcx
    inc rcx
    jmp 3b
4:  # the folder, relative to the project when inside it
    mov [rsp], r15
    mov rdi, [rip + lf_line + SB_ptr]
    mov rsi, [rip + lf_line + SB_len]
    call lf_str
    mov [rsp + 8], rax
    mov rax, [rbp + 16 + 24]
    add rax, [rip + lf_bytes + SB_ptr]
    mov rbx, rax
    mov r15, [rsp]
    test r15, r15
    jz 6f
    dec r15                     # without the separator
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 5f
    call strlen
    cmp rax, r15
    ja 5f
    mov rdi, rbx
    mov rsi, [rip + g_project]
    mov rdx, rax
    push rax
    push rax
    call str_starts_raw
    pop rcx
    pop rcx
    test eax, eax
    jz 5f
    cmp rcx, r15
    je 6f                       # the project's own folder: no detail
    cmp byte ptr [rbx + rcx], '/'
    je 51f
    cmp byte ptr [rbx + rcx], '\\'
    jne 5f
51: lea rdi, [rbx + rcx + 1]
    mov rsi, r15
    sub rsi, rcx
    dec rsi
    jmp 52f
5:  mov rdi, rbx
    mov rsi, r15
52: call lf_str
    mov rdx, rax
    mov rax, [rsp + 8]
    EPILOGUE
6:  mov rax, [rsp + 8]
    mov rdx, -1
    EPILOGUE

# str_starts_raw(s, prefix, n) -> eax 1 when s begins with the n bytes of prefix
str_starts_raw:
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 9f
    movzx eax, byte ptr [rdi + rcx]
    cmp al, [rsi + rcx]
    jne 8f
    inc rcx
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# lf_parse_symbols(ext, body, len): "N", then L1 C1 L2 C2 KIND DEPTH NAME_LEN DETAIL_LEN and bytes
lf_parse_symbols:
    PROLOGUE 48
    mov [rsp], rdi
    mov rax, [rip + lf_res + VEC_len]
    mov [rsp + 8], rax
    mov rax, [rip + lf_bytes + SB_len]
    mov [rsp + 16], rax
    cmp rdx, LF_BODY_MAX
    ja 8f
    mov rdi, rsi
    mov rsi, rdx
    mov edx, LF_MAX
    call lf_head
    test rax, rax
    js 8f
    mov r15, rax
1:  test r15, r15
    jz 9f
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call lf_four
    test eax, eax
    jz 8f
    call ps_word                # the kind
    test rdx, rdx
    jz 8f
    cmp rdx, 40
    ja 8f
    mov [rsp + 24], rax
    mov [rsp + 32], rdx
    call ps_num                 # the depth
    test edx, edx
    jz 8f
    cmp rax, 40
    jbe 11f
    mov eax, 40
11: mov rbx, rax
    call ps_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 1000
    ja 8f
    mov r12, rax                # the name's length
    call ps_num
    test edx, edx
    jz 8f
    cmp rax, 1000
    ja 8f
    mov r13, rax                # the detail's
    call ps_eol
    test eax, eax
    jz 8f
    mov rdi, r12
    call lf_take
    test rax, rax
    jz 8f
    mov r14, rax
    mov rdi, r13
    call lf_take
    test rax, rax
    jz 8f
    mov [rsp + 40], rax
    # the label: two spaces a level, then the name; the detail: the kind and the provider's detail
    lea rdi, [rip + lf_line]
    call sb_clear
2:  test rbx, rbx
    jz 3f
    dec rbx
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    jmp 2b
3:  lea rdi, [rip + lf_line]
    mov rsi, r14
    mov rdx, r12
    call sb_push
    mov rdi, [rip + lf_line + SB_ptr]
    mov rsi, [rip + lf_line + SB_len]
    call lf_str
    mov r14, rax                # the label's offset
    lea rdi, [rip + lf_line]
    call sb_clear
    lea rdi, [rip + lf_line]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call sb_push
    test r13, r13
    jz 4f
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lf_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lf_line]
    mov rsi, [rsp + 40]
    mov rdx, r13
    call sb_push
4:  mov rdi, [rip + lf_line + SB_ptr]
    mov rsi, [rip + lf_line + SB_len]
    call lf_str
    mov r12, rax
    lea rdi, [rip + lf_res]
    mov esi, LS_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + LS_ext], rcx
    mov qword ptr [rax + LS_path], -1
    lea rcx, [rip + lf_tmp4]
    mov edx, [rcx]
    mov [rax + LS_l1], edx
    mov edx, [rcx + 4]
    mov [rax + LS_c1], edx
    mov edx, [rcx + 8]
    mov [rax + LS_l2], edx
    mov edx, [rcx + 12]
    mov [rax + LS_c2], edx
    mov [rax + LS_label], r14
    mov [rax + LS_detail], r12
    jmp 1b
8:  mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    call lf_rollback
9:  EPILOGUE

# lf_parse_actions(ext, body, len): "N", then KIND TITLE_LEN EDIT_LEN DATA_LEN and the bytes
lf_parse_actions:
    PROLOGUE 48
    mov [rsp], rdi
    mov rax, [rip + lf_res + VEC_len]
    mov [rsp + 8], rax
    mov rax, [rip + lf_bytes + SB_len]
    mov [rsp + 16], rax
    cmp rdx, WS_BODY_MAX
    ja 8f
    mov rdi, rsi
    mov rsi, rdx
    mov edx, LF_ACTS_MAX
    call lf_head
    test rax, rax
    js 8f
    mov r15, rax
1:  test r15, r15
    jz 9f
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call ps_word                # the kind
    test rdx, rdx
    jz 8f
    cmp rdx, 40
    ja 8f
    mov [rsp + 24], rax
    mov [rsp + 32], rdx
    call ps_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 1000
    ja 8f
    mov r12, rax                # the title's length
    call ps_num
    test edx, edx
    jz 8f
    mov r13, rax                # the edit's
    call ps_num
    test edx, edx
    jz 8f
    mov r14, rax                # the data's
    call ps_eol
    test eax, eax
    jz 8f
    mov rdi, r12
    call lf_take
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r12
    call lf_str
    mov [rsp + 40], rax         # the title
    mov rdi, r13
    call lf_take
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r13
    call lf_str
    mov rbx, rax                # the edit (kept whole, checked when chosen)
    mov rdi, r14
    call lf_take
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r14
    call lf_str
    mov r12, rax                # the data
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    call lf_str
    mov [rsp + 24], rax         # the kind, its detail
    lea rdi, [rip + lf_res]
    mov esi, LS_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + LS_ext], rcx
    mov qword ptr [rax + LS_path], -1
    mov rcx, [rsp + 40]
    mov [rax + LS_label], rcx
    mov rcx, [rsp + 24]
    mov [rax + LS_detail], rcx
    mov [rax + LS_edit], rbx
    mov [rax + LS_elen], r13
    mov [rax + LS_data], r12
    mov [rax + LS_dlen], r14
    # quick fixes first
    mov rdx, [rsp + 24]
    add rdx, [rip + lf_bytes + SB_ptr]
    xor ecx, ecx
    cmp dword ptr [rdx], 0x63697571     # "quic"
    je 11f
    mov ecx, 1
11: mov [rax + LS_rank], ecx
    jmp 1b
8:  mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    call lf_rollback
9:  EPILOGUE

# ---------------- finishing ----------------

# FN langfeat_timeout() -> ms until the query in flight is given up, or -1
FN langfeat_timeout
    push rbx
    cmp dword ptr [rip + lf_kind], 0
    je 8f
    cmp dword ptr [rip + lf_ready], 0
    jne 7f
    mov rbx, [rip + lf_deadline]
    call time_ms
    sub rbx, rax
    jns 1f
7:  xor ebx, ebx
1:  mov eax, ebx
    pop rbx
    ret
8:  mov eax, -1
    pop rbx
    ret

# FN langfeat_tick(): a query whose answers are in, or whose time is up, is finished
FN langfeat_tick
    push rbx
    cmp dword ptr [rip + lf_kind], 0
    je 9f
    cmp dword ptr [rip + lf_ready], 0
    jne 1f
    call time_ms
    cmp rax, [rip + lf_deadline]
    jb 9f
1:  call lf_cancel_all
    call lf_finish
9:  pop rbx
    ret

# lf_finish(): what the answers mean for the user
lf_finish:
    PROLOGUE
    mov ebx, [rip + lf_kind]
    mov dword ptr [rip + lf_kind], 0
    mov dword ptr [rip + lf_ready], 0
    mov dword ptr [rip + g_dirty], 1
    mov r12, [rip + lf_res + VEC_len]
    cmp ebx, LF_RENAME
    je .Lfn_rename
    cmp ebx, LF_FORMAT
    je .Lfn_format
    test r12, r12
    jnz 1f
    lea rax, [rip + lf_empty]
    mov rdi, [rax + rbx*8]
    call app_toast
    jmp 9f
1:  cmp ebx, LF_DEF
    jne 2f
    cmp r12, 1
    jne 2f
    xor edi, edi
    call lf_goto                # one definition: there at once
    jmp 9f
2:  call lf_sort
    mov [rip + lf_list_kind], ebx
    lea rax, [rip + lf_lists]
    mov rdi, [rax + rbx*8]
    call palette_results_open
    xor r13d, r13d
3:  cmp r13, [rip + lf_res + VEC_len]
    jae 4f
    imul rax, r13, LS_SIZE
    add rax, [rip + lf_res + VEC_ptr]
    mov r14, rax
    mov rdi, [r14 + LS_label]
    add rdi, [rip + lf_bytes + SB_ptr]
    call strlen
    mov rsi, rax
    mov rdi, [r14 + LS_label]
    add rdi, [rip + lf_bytes + SB_ptr]
    xor edx, edx
    mov rax, [r14 + LS_detail]
    test rax, rax
    js 31f
    mov rdx, rax
    add rdx, [rip + lf_bytes + SB_ptr]
31: mov rcx, r13
    call palette_results_add
    inc r13
    jmp 3b
4:  call palette_results_ready
    jmp 9f
.Lfn_rename:
    cmp byte ptr [rip + lf_err], 0
    je 5f
    lea rdi, [rip + lf_err]
    call app_toast
    jmp 9f
5:  cmp qword ptr [rip + lf_ws + SB_len], 0
    jne 6f
    lea rdi, [rip + .Lnothing_renamed]
    call app_toast
    jmp 9f
6:  mov rdi, [rip + lf_ws + SB_ptr]
    mov rsi, [rip + lf_ws + SB_len]
    call ws_apply
    test eax, eax
    jz 9f
    lea rdi, [rip + .Lrenamed]
    call app_toast
    jmp 9f
.Lfn_format:
    cmp qword ptr [rip + lf_ws + SB_len], 0
    je 9f
    mov rdi, [rip + lf_ws + SB_ptr]
    mov rsi, [rip + lf_ws + SB_len]
    call ws_apply
9:  EPILOGUE

# lf_sort(): the results in their order: by rank (actions), and locations of this document first
# (insertion sort; a long list keeps the providers' order)
lf_sort:
    PROLOGUE 16
    mov r12, [rip + lf_res + VEC_len]
    cmp r12, 2000
    ja 9f
    # the ranks of locations: 0 in the asked document, 1 elsewhere
    xor ebx, ebx
1:  cmp rbx, r12
    jae 2f
    imul r13, rbx, LS_SIZE
    add r13, [rip + lf_res + VEC_ptr]
    inc rbx
    mov rax, [r13 + LS_path]
    test rax, rax
    js 1b
    add rax, [rip + lf_bytes + SB_ptr]
    mov rdi, rax
    call lf_is_asked_doc
    xor eax, 1
    mov [r13 + LS_rank], eax
    jmp 1b
2:  mov rbx, 1
3:  cmp rbx, r12
    jae 9f
    mov r13, rbx
4:  test r13, r13
    jz 5f
    imul r14, r13, LS_SIZE
    add r14, [rip + lf_res + VEC_ptr]
    mov eax, [r14 + LS_rank]
    cmp eax, [r14 - LS_SIZE + LS_rank]
    jge 5f
    # swap the two records
    xor ecx, ecx
41: mov rax, [r14 + rcx]
    mov rdx, [r14 + rcx - LS_SIZE]
    mov [r14 + rcx], rdx
    mov [r14 + rcx - LS_SIZE], rax
    add ecx, 8
    cmp ecx, LS_SIZE
    jb 41b
    dec r13
    jmp 4b
5:  inc rbx
    jmp 3b
9:  EPILOGUE

# lf_is_asked_doc(path cstr) -> eax 1 when it names the asked document ("#ID" or its path)
lf_is_asked_doc:
    push rbx
    mov rbx, rdi
    cmp byte ptr [rbx], '#'
    jne 1f
    lea rdi, [rbx + 1]
    call strlen
    mov rsi, rax
    lea rdi, [rbx + 1]
    call parse_u64
    xor ecx, ecx
    cmp rax, [rip + lf_doc_id]
    sete cl
    mov eax, ecx
    pop rbx
    ret
1:  mov rdi, [rip + lf_doc_id]
    call extproto_doc
    test rax, rax
    jz 8f
    mov rsi, [rax + DOC_path]
    test rsi, rsi
    jz 8f
    mov rdi, rbx
    call strcmp_eq
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# FN langfeat_chosen(i): the user chose result i of the palette's list
FN langfeat_chosen
    PROLOGUE
    cmp rdi, [rip + lf_res + VEC_len]
    jae 9f
    mov rbx, rdi
    cmp dword ptr [rip + lf_list_kind], LF_ACTS
    je 1f
    mov rdi, rbx
    call lf_goto
    jmp 9f
1:  imul r12, rbx, LS_SIZE
    add r12, [rip + lf_res + VEC_ptr]
    cmp qword ptr [r12 + LS_elen], 0
    je 2f
    mov rdi, [r12 + LS_edit]
    add rdi, [rip + lf_bytes + SB_ptr]
    mov rsi, [r12 + LS_elen]
    call ws_apply
    test eax, eax
    jz 9f                       # an edit that cannot be made: nothing more either
2:  cmp qword ptr [r12 + LS_dlen], 0
    je 9f
    mov rdi, [r12 + LS_ext]
    mov rsi, [r12 + LS_data]
    add rsi, [rip + lf_bytes + SB_ptr]
    mov rdx, [r12 + LS_dlen]
    call extproto_send_action
9:  EPILOGUE

# lf_goto(i): the editor at result i: its file open, its range selected
lf_goto:
    PROLOGUE
    imul rbx, rdi, LS_SIZE
    add rbx, [rip + lf_res + VEC_ptr]
    mov rax, [rbx + LS_path]
    test rax, rax
    js 1f
    add rax, [rip + lf_bytes + SB_ptr]
    mov rdi, rax
    call lf_open_path
    test rax, rax
    jz 9f
    mov r12, rax
    jmp 2f
1:  mov rdi, [rip + lf_doc_id]
    call extproto_doc
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    call doc_tab
    test rax, rax
    js 9f
    mov rdi, rax
    call app_activate_tab
2:  mov rdi, r12
    mov esi, [rbx + LS_l1]
    mov edx, [rbx + LS_c1]
    call lf_pos_near
    mov r13, rax
    mov rdi, r12
    mov esi, [rbx + LS_l2]
    mov edx, [rbx + LS_c2]
    call lf_pos_near
    cmp rax, r13
    jae 3f
    mov rax, r13
3:  mov [r12 + DOC_anchor], r13
    mov [r12 + DOC_cur], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call ed_touch
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# lf_open_path(path cstr) -> rax the DOC of "#ID" or of the file, its tab active, or 0
lf_open_path:
    PROLOGUE
    mov rbx, rdi
    cmp byte ptr [rbx], '#'
    jne 1f
    lea rdi, [rbx + 1]
    call strlen
    mov rsi, rax
    lea rdi, [rbx + 1]
    call parse_u64
    mov rdi, rax
    call extproto_doc
    test rax, rax
    jz 8f
    mov r12, rax
    mov rdi, rax
    call doc_tab
    test rax, rax
    js 8f
    mov rdi, rax
    call app_activate_tab
    mov rax, r12
    EPILOGUE
1:  mov rdi, rbx
    call app_open_file
    test rax, rax
    js 8f
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rax, [rax + TAB_doc]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- workspace edits (12g) ----------------

# ws_fail(cstr) -> eax 0: says why nothing changed
ws_fail:
    push rbx
    call app_toast
    xor eax, eax
    pop rbx
    ret

# FN ws_apply(body, len) -> eax 1 when every edit was made, 0 when none was (and a toast says why):
# "N", then per file PATH_LEN VERSION M and the path, then M edits L1 C1 L2 C2 LEN and the text
FN ws_apply
    PROLOGUE 48
    mov qword ptr [rip + wg_vec + VEC_len], 0
    mov qword ptr [rip + we_vec + VEC_len], 0
    cmp rsi, WS_BODY_MAX
    ja .Lws_bad
    mov edx, WS_FILES_MAX
    call lf_head
    test rax, rax
    js .Lws_bad
    mov r15, rax                # groups
    # read the groups and their edits
.Lws_group:
    test r15, r15
    jz .Lws_read
    dec r15
    call ps_line
    test eax, eax
    jz .Lws_bad
    call ps_num
    test edx, edx
    jz .Lws_bad
    test rax, rax
    jz .Lws_bad
    cmp rax, 4096
    ja .Lws_bad
    mov r12, rax                # the path's length
    call ps_word                # the version, or -
    test rdx, rdx
    jz .Lws_bad
    mov r13, -1
    cmp rdx, 1
    jne 1f
    cmp byte ptr [rax], '-'
    je 2f
1:  cmp rdx, 18
    ja .Lws_bad
    mov rbx, rdx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    cmp rdx, rbx
    jne .Lws_bad
    mov r13, rax
2:  call ps_num
    test edx, edx
    jz .Lws_bad
    mov r14, rax                # the edits
    call ps_eol
    test eax, eax
    jz .Lws_bad
    mov rdi, r12
    call lf_take
    test rax, rax
    jz .Lws_bad
    mov rbx, rax
    lea rdi, [rip + wg_vec]
    mov esi, WG_SIZE
    call vec_push
    mov [rax + WG_path], rbx
    mov [rax + WG_plen], r12
    mov [rax + WG_version], r13
    mov rcx, [rip + we_vec + VEC_len]
    mov [rax + WG_first], rcx
    mov [rax + WG_count], r14
    mov rcx, [rip + we_vec + VEC_len]
    add rcx, r14
    cmp rcx, WS_EDITS_MAX
    ja .Lws_bad
3:  test r14, r14
    jz .Lws_group
    dec r14
    call ps_line
    test eax, eax
    jz .Lws_bad
    call lf_four
    test eax, eax
    jz .Lws_bad
    call ps_num
    test edx, edx
    jz .Lws_bad
    mov r12, rax
    call ps_eol
    test eax, eax
    jz .Lws_bad
    mov rdi, r12
    call lf_take
    test rax, rax
    jz .Lws_bad
    mov rbx, rax
    lea rdi, [rip + we_vec]
    mov esi, WE_SIZE
    call vec_push
    lea rcx, [rip + lf_tmp4]
    mov edx, [rcx]
    mov [rax + WE_l1], edx
    mov edx, [rcx + 4]
    mov [rax + WE_c1], edx
    mov edx, [rcx + 8]
    mov [rax + WE_l2], edx
    mov edx, [rcx + 12]
    mov [rax + WE_c2], edx
    mov [rax + WE_text], rbx
    mov [rax + WE_len], r12
    jmp 3b
.Lws_read:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne .Lws_bad
    # the documents: open ones by id or path at their versions; files that are not open come next
    mov rax, [rip + g_doc]
    mov [rsp + 16], rax         # the document to come back to
    xor ebx, ebx
.Lws_find:
    cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lws_open
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov qword ptr [r12 + WG_doc], 0
    mov rdi, r12
    call ws_path
    test eax, eax
    jz .Lws_badpath
    cmp byte ptr [rip + lf_path], '#'
    jne 4f
    lea rdi, [rip + lf_path + 1]
    call strlen
    mov rsi, rax
    lea rdi, [rip + lf_path + 1]
    call parse_u64
    mov rdi, rax
    call extproto_doc
    test rax, rax
    jz .Lws_gone
    mov [r12 + WG_doc], rax
    jmp 5f
4:  lea rdi, [rip + lf_path]
    call app_find_tab
    test rax, rax
    js 41f
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lws_badpath
    mov rax, [rax + TAB_doc]
    mov [r12 + WG_doc], rax
    jmp 5f
41: cmp qword ptr [r12 + WG_version], -1
    jne .Lws_gone               # it was open when the edit was made
    jmp .Lws_find
5:  mov rax, [r12 + WG_doc]
    mov rcx, [r12 + WG_version]
    cmp rcx, -1
    je .Lws_find
    cmp rcx, [rax + DOC_version]
    jne .Lws_stale
    jmp .Lws_find
.Lws_open:
    # files that are not open open in tabs of their own
    xor ebx, ebx
6:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lws_check
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    cmp qword ptr [r12 + WG_doc], 0
    jne 6b
    mov rdi, r12
    call ws_path
    lea rdi, [rip + lf_path]
    call app_open_file
    test rax, rax
    js .Lws_unreadable
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lws_unreadable
    mov rax, [rax + TAB_doc]
    mov [r12 + WG_doc], rax
    jmp 6b
.Lws_check:
    # every range in its text, in order, none over another
    xor ebx, ebx
7:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lws_apply
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov r13, [r12 + WG_doc]
    test dword ptr [r13 + DOC_flags], DF_READONLY
    jnz .Lws_readonly
    mov r14, [r12 + WG_first]
    mov r15, r14
    add r15, [r12 + WG_count]
71: cmp r14, r15
    jae 72f
    imul rax, r14, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov [rsp], rax
    mov rdi, r13
    mov esi, [rax + WE_l1]
    mov edx, [rax + WE_c1]
    call lf_pos
    test rax, rax
    js .Lws_badrange
    mov rcx, [rsp]
    mov [rcx + WE_start], rax
    mov rdi, r13
    mov esi, [rcx + WE_l2]
    mov edx, [rcx + WE_c2]
    call lf_pos
    test rax, rax
    js .Lws_badrange
    mov rcx, [rsp]
    mov [rcx + WE_end], rax
    cmp rax, [rcx + WE_start]
    jb .Lws_badrange
    inc r14
    jmp 71b
72: mov rdi, r12
    call ws_sort
    test eax, eax
    jz .Lws_toomany
    mov rdi, r12
    call ws_overlap
    test eax, eax
    jnz .Lws_overlap
    jmp 7b
.Lws_apply:
    # each file as one undo step, from its last edit to its first
    xor ebx, ebx
8:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lws_done
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov rdi, r12
    call ws_apply_group
    jmp 8b
.Lws_done:
    # back to the document the user was in
    mov rdi, [rsp + 16]
    test rdi, rdi
    jz 81f
    call doc_tab
    test rax, rax
    js 81f
    mov rdi, rax
    call app_activate_tab
81: mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
.Lws_bad:
    lea rdi, [rip + .Lws_e_bad]
    jmp .Lws_out
.Lws_badpath:
    lea rdi, [rip + .Lws_e_path]
    jmp .Lws_out
.Lws_gone:
    lea rdi, [rip + .Lws_e_gone]
    jmp .Lws_out
.Lws_stale:
    lea rdi, [rip + .Lws_e_stale]
    jmp .Lws_out
.Lws_unreadable:
    lea rdi, [rip + .Lws_e_open]
    jmp .Lws_out
.Lws_readonly:
    lea rdi, [rip + .Lws_e_readonly]
    jmp .Lws_out
.Lws_badrange:
    lea rdi, [rip + .Lws_e_range]
    jmp .Lws_out
.Lws_toomany:
    lea rdi, [rip + .Lws_e_many]
    jmp .Lws_out
.Lws_overlap:
    lea rdi, [rip + .Lws_e_overlap]
.Lws_out:
    call ws_fail
    EPILOGUE

# ws_path(WG*) -> eax 1 with its path in lf_path as a cstr, 0 when it holds a NUL or is too long
ws_path:
    mov rsi, [rdi + WG_path]
    mov rcx, [rdi + WG_plen]
    cmp rcx, 4096
    ja 8f
    lea rdx, [rip + lf_path]
    xor eax, eax
1:  cmp rax, rcx
    jae 2f
    movzx r8d, byte ptr [rsi + rax]
    test r8d, r8d
    jz 8f
    mov [rdx + rax], r8b
    inc rax
    jmp 1b
2:  mov byte ptr [rdx + rax], 0
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ws_sort(WG*) -> eax 1 with its edits by start (an insertion keeps its place among equals), 0
# when they are out of order and too many to sort
ws_sort:
    PROLOGUE
    mov rbx, [rdi + WG_first]
    mov r12, [rdi + WG_count]
    # already in order?
    mov rcx, 1
1:  cmp rcx, r12
    jae 8f
    lea rax, [rbx + rcx]
    imul rax, rax, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov rdx, [rax + WE_start]
    cmp rdx, [rax - WE_SIZE + WE_start]
    jb 2f
    inc rcx
    jmp 1b
2:  cmp r12, WS_SORT_MAX
    ja 9f
    mov r13, 1
3:  cmp r13, r12
    jae 8f
    mov r14, r13
4:  test r14, r14
    jz 6f
    lea rax, [rbx + r14]
    imul rax, rax, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov rdx, [rax + WE_start]
    cmp rdx, [rax - WE_SIZE + WE_start]
    jae 6f
    xor ecx, ecx
5:  mov rdx, [rax + rcx]
    mov r8, [rax + rcx - WE_SIZE]
    mov [rax + rcx], r8
    mov [rax + rcx - WE_SIZE], rdx
    add ecx, 8
    cmp ecx, WE_SIZE
    jb 5b
    dec r14
    jmp 4b
6:  inc r13
    jmp 3b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# ws_overlap(WG*) -> eax 1 when one of its (sorted) edits starts inside the one before
ws_overlap:
    mov rsi, [rdi + WG_first]
    mov rcx, 1
1:  cmp rcx, [rdi + WG_count]
    jae 8f
    lea rax, [rsi + rcx]
    imul rax, rax, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov rdx, [rax - WE_SIZE + WE_end]
    cmp rdx, [rax + WE_start]
    ja 9f
    inc rcx
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# ws_apply_group(WG*): its edits made, as one undo step (the cursor and the selection move with the
# text around them: doc_insert and doc_delete move them)
ws_apply_group:
    PROLOGUE 16
    mov r12, rdi
    mov rbx, [r12 + WG_doc]
    cmp qword ptr [r12 + WG_count], 0
    je 9f
    mov rdi, rbx
    call doc_begin_group
    mov r13, [r12 + WG_count]
1:  test r13, r13
    jz 8f
    dec r13
    mov rax, [r12 + WG_first]
    add rax, r13
    imul r14, rax, WE_SIZE
    add r14, [rip + we_vec + VEC_ptr]
    mov rdx, [r14 + WE_end]
    sub rdx, [r14 + WE_start]
    jz 2f
    mov rdi, rbx
    mov rsi, [r14 + WE_start]
    mov ecx, EK_OTHER
    call doc_delete
2:  cmp qword ptr [r14 + WE_len], 0
    je 1b
    mov rdi, rbx
    mov rsi, [r14 + WE_start]
    mov rdx, [r14 + WE_text]
    mov rcx, [r14 + WE_len]
    mov r8d, EK_OTHER
    call doc_insert
    jmp 1b
8:  mov rdi, rbx
    call doc_end_group
    call ed_touch
9:  EPILOGUE

# FN langfeat_ext_gone(ext): an extension stopped: its requests go (state only)
FN langfeat_ext_gone
    xor ecx, ecx
1:  cmp rcx, [rip + lf_reqs + VEC_len]
    jae 8f
    imul rax, rcx, LR_SIZE
    add rax, [rip + lf_reqs + VEC_ptr]
    cmp [rax + LR_ext], rdi
    je 2f
    inc rcx
    jmp 1b
2:  # the last record takes its place
    mov rdx, [rip + lf_reqs + VEC_len]
    dec rdx
    mov [rip + lf_reqs + VEC_len], rdx
    imul rdx, rdx, LR_SIZE
    add rdx, [rip + lf_reqs + VEC_ptr]
    mov r8, [rdx]
    mov [rax], r8
    mov r8, [rdx + 8]
    mov [rax + 8], r8
    mov r8, [rdx + 16]
    mov [rax + 16], r8
    jmp 1b
8:  # nothing more to wait for: the tick finishes the query with what came
    cmp dword ptr [rip + lf_kind], 0
    je 9f
    cmp qword ptr [rip + lf_reqs + VEC_len], 0
    jne 9f
    mov dword ptr [rip + lf_ready], 1
9:  ret

.bss
.p2align 2
lf_tmp4: .zero 16

.section .rodata
.p2align 3
# per kind (index LF_*): the verb, the feature, where its patterns are, how long it waits (ms), a
# toast when nobody provides it, a toast when nothing came, the list's placeholder; one provider?
lf_verbs: .quad 0, .Lv_definition, .Lv_references, .Lv_symbols, .Lv_actions, .Lv_rename, .Lv_format
lf_feats: .long 0, FEAT_DEFINITION, FEAT_REFERENCES, FEAT_SYMBOLS, FEAT_ACTIONS, FEAT_RENAME, FEAT_FORMAT
.p2align 3
lf_pvs: .quad 0, EXT_pv_definition, EXT_pv_references, EXT_pv_symbols, EXT_pv_actions, EXT_pv_rename, EXT_pv_format
lf_waits: .quad 0, 5000, 10000, 5000, 3000, 15000, 10000
lf_none: .quad 0, .Ln_def, .Ln_refs, .Ln_syms, .Ln_acts, .Ln_rename, .Ln_format
lf_empty: .quad 0, .Le_def, .Le_refs, .Le_syms, .Le_acts, 0, 0
lf_lists: .quad 0, .Ll_def, .Ll_refs, .Ll_syms, .Ll_acts, 0, 0
lf_single: .byte 0, 0, 0, 1, 0, 1, 1
.Lv_definition: .asciz "definition"
.Lv_references: .asciz "references"
.Lv_symbols: .asciz "symbols"
.Lv_actions: .asciz "actions"
.Lv_rename: .asciz "rename"
.Lv_format: .asciz "format"
.Linvoked: .asciz " invoked "
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.Ln_def: .asciz "No extension finds definitions in this file"
.Ln_refs: .asciz "No extension finds references in this file"
.Ln_syms: .asciz "No extension lists the symbols of this file"
.Ln_acts: .asciz "No extension offers code actions for this file"
.Ln_rename: .asciz "No extension renames symbols in this file"
.Ln_format: .asciz "No extension formats this file"
.Le_def: .asciz "No definition found"
.Le_refs: .asciz "No references found"
.Le_syms: .asciz "No symbols in this file"
.Le_acts: .asciz "No code actions here"
.Ll_def: .asciz "Go to definition"
.Ll_refs: .asciz "Go to reference"
.Ll_syms: .asciz "Go to symbol"
.Ll_acts: .asciz "Code action"
.Lrename_to: .asciz "New name"
.Lname_spaces: .asciz "A name cannot hold spaces"
.Lnothing_renamed: .asciz "Nothing to rename"
.Lrenamed: .asciz "Renamed: check the changed files and save them"
.Lws_e_bad: .asciz "The extension's edit could not be read: nothing changed"
.Lws_e_path: .asciz "The extension's edit names a file it cannot: nothing changed"
.Lws_e_gone: .asciz "A document the edit was made for is closed: nothing changed"
.Lws_e_stale: .asciz "A document changed since the edit was made: nothing changed"
.Lws_e_open: .asciz "A file the edit changes cannot be opened: nothing changed"
.Lws_e_readonly: .asciz "A file the edit changes is read-only: nothing changed"
.Lws_e_range: .asciz "The edit's ranges are not in the text: nothing changed"
.Lws_e_many: .asciz "Too many edits out of order in one file: nothing changed"
.Lws_e_overlap: .asciz "The edit's ranges overlap: nothing changed"
