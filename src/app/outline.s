# The Outline sidebar section (language-features.md 1.5): the active document's symbols (v1 12e,
# asked of the language's symbols provider that rhun would use without asking: the saved choice
# or the only one running) as a tree, nested by depth. Asked when the section is on screen and
# the document changed (half a second after edits, at once for another document); the row of the
# innermost symbol around the cursor (else the last one starting before it) is the tree's cursor
# while the editor has the keyboard; Enter goes to a symbol. The section appears, collapsed, the
# first time the active document has such a provider, or with focus_outline.
#
#   outline_tick(), outline_timeout() -> ms, outline_reply(ext, id, ok, body, len) -> eax 1 when it
#   answered the Outline's request, outline_ext_gone(ext), outline_dump(sb), cmd_focus_outline
.include "rhun.inc"

.equ OL_DEBOUNCE, 500           # ms after an edit
.equ OL_MAX, 10000              # symbols in an answer
.equ OL_BODY_MAX, 1048576
.equ PP_SYMS, 3                 # the symbols kind of the provider choices (extproviders.s)

# a symbol
STRUCT
F OLS_l1, 4
F OLS_c1, 4
F OLS_l2, 4
F OLS_c2, 4
F OLS_depth, 4
F OLS_parent, 4                 # index, -1 for a top-level one
F OLS_first, 4                  # first child, -1
F OLS_next, 4                   # next sibling, -1
F OLS_name, 8                   # offsets in ol_bytes, cstrs
F OLS_detail, 8
F OLS_node, 4
F OLS_pad, 4
ENDSTRUCT OLS_SIZE

.data
.p2align 2
ol_place: .long -1

.bss
.p2align 3
ol_tree: .quad 0
ol_doc: .quad 0                 # the document the rows are of (DOC_id), its version and language
ol_version: .quad 0
ol_lang: .quad 0
ol_due: .quad 0                 # when to ask (time_ms), 0: not wanted
ol_ext: .quad 0                 # the request out: its provider and id
ol_id: .quad 0
ol_ask_doc: .quad 0             # what it asks about
ol_ask_version: .quad 0
ol_ask_lang: .quad 0
ol_has: .long 0                 # 1: rows of a document; 2: it has no provider
ol_curpos: .quad 0              # the cursor's position the tree's cursor was set for
ol_curdoc: .quad 0
ol_syms: .zero VEC_SIZE         # OLS records
ol_top: .long 0                 # the first top-level symbol, -1 for none
ol_pad: .long 0
ol_stack: .zero 4 * 66          # build's open symbols
ol_bytes: .zero SB_SIZE
ol_buf: .zero SB_SIZE           # a request line, an id
ol_tmp: .zero 16

.text

# ensure(): the section and its tree, made once (collapsed: it opens when the user wants it)
ensure:
    PROLOGUE
    cmp dword ptr [rip + ol_place], 0
    jge 9f
    lea rdi, [rip + tree_ops]
    xor esi, esi
    call tree_new
    mov [rip + ol_tree], rax
    mov edi, PLACE_SIDEBAR
    lea rsi, [rip + .Lname]
    lea rdx, [rip + .Ltitle]
    lea rcx, [rip + place_ops]
    xor r8d, r8d
    call place_add
    mov [rip + ol_place], eax
    test eax, eax
    js 9f
    mov edi, eax
    mov esi, 1
    call place_set_collapsed
9:  EPILOGUE

# FN cmd_focus_outline(): the Outline section, expanded, with the keyboard; asked at once
FN cmd_focus_outline
    PROLOGUE
    call ensure
    mov edi, [rip + ol_place]
    test edi, edi
    js 9f
    mov esi, 1
    call place_show
    mov qword ptr [rip + ol_version], -1     # whatever it showed: asked again
9:  EPILOGUE

# FN outline_tick(): create the section when there is something to show, ask when the shown
# document changed, follow the cursor
FN outline_tick
    PROLOGUE
    call lf_active_doc
    mov rbx, rax
    test rbx, rbx
    jz 9f
    cmp dword ptr [rip + ol_place], 0
    jge 1f
    mov edi, PP_SYMS
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jz 9f
    call ensure
1:  mov edi, [rip + ol_place]
    call place_visible
    test eax, eax
    jz 9f
    # another document, version or language than the rows show: asked (soon)
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + ol_doc]
    jne 2f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + ol_version]
    jne 3f
    mov rax, [rbx + DOC_language_revision]
    cmp rax, [rip + ol_lang]
    jne 2f
    jmp 6f
2:  mov rax, [rbx + DOC_id]     # another document: its rows go now (they name the other's
    cmp rax, [rip + ol_doc]     # places), asked at once
    je 21f
    mov qword ptr [rip + ol_syms + VEC_len], 0
    mov dword ptr [rip + ol_has], 0
    mov qword ptr [rip + ol_curdoc], 0
    mov rdi, [rip + ol_tree]
    call tree_clear
    mov dword ptr [rip + g_dirty], 1
21: call time_ms
    mov [rip + ol_due], rax
    jmp 4f
3:  cmp qword ptr [rip + ol_due], 0
    jne 4f
    call time_ms
    add rax, OL_DEBOUNCE
    mov [rip + ol_due], rax
4:  mov rax, [rbx + DOC_id]
    mov [rip + ol_doc], rax
    mov rax, [rbx + DOC_version]
    mov [rip + ol_version], rax
    mov rax, [rbx + DOC_language_revision]
    mov [rip + ol_lang], rax
6:  cmp qword ptr [rip + ol_due], 0
    je 7f
    call time_ms
    cmp rax, [rip + ol_due]
    jb 7f
    cmp qword ptr [rip + ol_id], 0
    jne 7f                      # the answer before comes first
    mov rdi, rbx
    call ask
7:  mov rdi, rbx
    call follow
9:  EPILOGUE

# FN outline_timeout() -> ms until the Outline wants a tick, or -1
FN outline_timeout
    mov rax, [rip + ol_due]
    test rax, rax
    jz 8f
    cmp qword ptr [rip + ol_id], 0
    jne 8f
    push rax
    push rax
    mov edi, [rip + ol_place]   # not on screen: the tick does not ask, so nothing is due (it
    call place_visible          # asks when the section shows again)
    test eax, eax
    jnz 2f
    pop rax
    pop rax
    jmp 8f
2:  call time_ms
    pop rcx
    pop rcx
    sub rcx, rax
    jns 1f
    xor ecx, ecx
1:  mov eax, ecx
    ret
8:  mov eax, -1
    ret

# ask(doc): "symbols DOC VERSION LINE COL invoked -" to the provider rhun would use
ask:
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rip + ol_due], 0
    mov edi, 1
    call query_room
    test eax, eax
    jz 9f
    mov edi, PP_SYMS
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jnz 1f
    mov dword ptr [rip + ol_has], 2      # nobody to ask
    mov qword ptr [rip + ol_syms + VEC_len], 0
    mov rdi, [rip + ol_tree]
    call tree_clear
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
1:  mov r12, rax
    lea rdi, [rip + ol_buf]
    call sb_clear
    lea rdi, [rip + ol_buf]
    lea rsi, [rip + .Lv_symbols]
    call sb_push_cstr
    lea rdi, [rip + ol_buf]
    mov rsi, [rbx + DOC_id]
    call sb_push_u64
    lea rdi, [rip + ol_buf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ol_buf]
    mov rsi, [rbx + DOC_version]
    call sb_push_u64
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lf_line_col
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + ol_buf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ol_buf]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + ol_buf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ol_buf]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + ol_buf]
    lea rsi, [rip + .Linvoked]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rip + ol_buf + SB_ptr]
    mov rcx, [rip + ol_buf + SB_len]
    call extproto_host_send
    test rax, rax
    jz 9f
    mov [rip + ol_id], rax
    mov [rip + ol_ext], r12
    mov rcx, [rbx + DOC_id]
    mov [rip + ol_ask_doc], rcx
    mov rcx, [rbx + DOC_version]
    mov [rip + ol_ask_version], rcx
    mov rcx, [rbx + DOC_language_revision]
    mov [rip + ol_ask_lang], rcx
    mov rdi, r12
    mov rsi, rax
    mov edx, PK_SYMBOLS
    mov ecx, QO_LANGFEAT
    call query_track
9:  EPILOGUE

# FN outline_reply(ext, id, ok, body, len) -> eax 1 when it answered the Outline's request
FN outline_reply
    PROLOGUE
    cmp rsi, [rip + ol_id]
    jne 8f
    test rsi, rsi
    jz 8f
    cmp rdi, [rip + ol_ext]
    jne 8f
    mov qword ptr [rip + ol_id], 0
    mov rbx, rdi
    test edx, edx
    jz 7f                       # an error or no answer in time: the rows stay
    mov rax, [rip + ol_ask_doc]
    cmp rax, [rip + ol_doc]
    jne 7f                      # about a document it no longer shows (the tick asks again)
    mov rdi, rcx
    mov rsi, r8
    call parse
    test eax, eax
    jnz 1f
    mov rdi, rbx
    mov esi, PK_SYMBOLS
    call query_dropped
    jmp 7f
1:  mov dword ptr [rip + ol_has], 1
    call build
    mov qword ptr [rip + ol_curpos], -1      # the cursor's row again
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# parse(body, len) -> eax 1 with ol_syms and ol_bytes holding the symbols, 0 when the body breaks the
# rules (they keep what they held)
parse:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    cmp rsi, OL_BODY_MAX
    ja 8f
    mov edx, OL_MAX
    call lf_head
    test rax, rax
    js 8f
    mov r15, rax
    mov qword ptr [rip + ol_syms + VEC_len], 0
    lea rdi, [rip + ol_bytes]
    call sb_clear
1:  test r15, r15
    jz 7f
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call lf_four
    test eax, eax
    jz 8f
    lea rax, [rip + lf_tmp4]
    mov rcx, [rax]
    mov [rip + ol_tmp], rcx
    mov rcx, [rax + 8]
    mov [rip + ol_tmp + 8], rcx
    call ps_word                # KIND (not kept)
    test rdx, rdx
    jz 8f
    call ps_num                 # DEPTH
    test edx, edx
    jz 8f
    cmp rax, 64
    ja 8f
    mov [rsp + 16], rax
    call ps_num                 # NAME_LEN
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 1000
    ja 8f
    mov r12, rax
    call ps_num                 # DETAIL_LEN
    test edx, edx
    jz 8f
    cmp rax, 1000
    ja 8f
    mov r13, rax
    call ps_eol
    test eax, eax
    jz 8f
    mov rdi, r12
    call take_str
    test rax, rax
    js 8f
    mov [rsp + 24], rax
    mov rdi, r13
    call take_str
    test rax, rax
    js 8f
    mov [rsp + 32], rax
    lea rdi, [rip + ol_syms]
    mov esi, OLS_SIZE
    call vec_push
    mov ecx, [rip + ol_tmp]
    mov [rax + OLS_l1], ecx
    mov ecx, [rip + ol_tmp + 4]
    mov [rax + OLS_c1], ecx
    mov ecx, [rip + ol_tmp + 8]
    mov [rax + OLS_l2], ecx
    mov ecx, [rip + ol_tmp + 12]
    mov [rax + OLS_c2], ecx
    mov rcx, [rsp + 16]
    mov [rax + OLS_depth], ecx
    mov rcx, [rsp + 24]
    mov [rax + OLS_name], rcx
    mov rcx, [rsp + 32]
    mov [rax + OLS_detail], rcx
    mov dword ptr [rax + OLS_node], -1
    jmp 1b
7:  mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne 8f
    mov eax, 1
    EPILOGUE
8:  mov qword ptr [rip + ol_syms + VEC_len], 0
    xor eax, eax
    EPILOGUE

# take_str(n) -> rax the offset of a copy of the next n body bytes in ol_bytes (one line), or -1
take_str:
    PROLOGUE
    mov r12, rdi
    call lf_take
    test rax, rax
    jz 8f
    mov r13, rax
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    movzx eax, byte ptr [r13 + rcx]
    cmp eax, 10
    je 8f
    cmp eax, 13
    je 8f
    test eax, eax
    jz 8f
    inc rcx
    jmp 1b
2:  mov r14, [rip + ol_bytes + SB_len]
    lea rdi, [rip + ol_bytes]
    mov rsi, r13
    mov rdx, r12
    call sb_push
    lea rdi, [rip + ol_bytes]
    xor esi, esi
    call sb_push_byte
    mov rax, r14
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# build(): the rows from ol_syms: each symbol's parent is the last one before it of a smaller depth
build:
    PROLOGUE 16
    mov r12, [rip + ol_syms + VEC_len]
    mov dword ptr [rip + ol_top], -1
    # parents, with a stack of the open ones (depths rise along it, so it holds at most 65)
    xor r15d, r15d              # the stack's height
    xor ebx, ebx
1:  cmp rbx, r12
    jae 3f
    imul r13, rbx, OLS_SIZE
    add r13, [rip + ol_syms + VEC_ptr]
    mov dword ptr [r13 + OLS_first], -1
    mov dword ptr [r13 + OLS_next], -1
2:  test r15, r15
    jz 21f
    lea rax, [rip + ol_stack]
    mov eax, [rax + r15*4 - 4]
    imul rax, rax, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    mov ecx, [rax + OLS_depth]
    cmp ecx, [r13 + OLS_depth]
    jb 21f
    dec r15
    jmp 2b
21: mov dword ptr [r13 + OLS_parent], -1
    test r15, r15
    jz 22f
    lea rax, [rip + ol_stack]
    mov eax, [rax + r15*4 - 4]
    mov [r13 + OLS_parent], eax
22: cmp r15, 65
    jae 23f
    lea rax, [rip + ol_stack]
    mov [rax + r15*4], ebx
    inc r15
23: inc rbx
    jmp 1b
3:  # sibling lists in document order (built backwards); the top level's starts at ol_top
    mov rbx, r12
4:  test rbx, rbx
    jz 5f
    dec rbx
    imul r13, rbx, OLS_SIZE
    add r13, [rip + ol_syms + VEC_ptr]
    movsxd rax, dword ptr [r13 + OLS_parent]
    test rax, rax
    js 41f
    imul rax, rax, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    mov ecx, [rax + OLS_first]
    mov [r13 + OLS_next], ecx
    mov [rax + OLS_first], ebx
    jmp 4b
41: mov ecx, [rip + ol_top]
    mov [r13 + OLS_next], ecx
    mov [rip + ol_top], ebx
    jmp 4b
5:  # the top level, then each symbol's children
    mov rdi, [rip + ol_tree]
    xor esi, esi
    call tree_kids_begin
    movsxd r14, dword ptr [rip + ol_top]
6:  test r14, r14
    js 7f
    mov rdi, r14
    call row
    imul rax, r14, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    movsxd r14, dword ptr [rax + OLS_next]
    jmp 6b
7:  mov rdi, [rip + ol_tree]
    xor esi, esi
    call tree_kids_end
    xor ebx, ebx
8:  cmp rbx, r12
    jae 9f
    imul r13, rbx, OLS_SIZE
    add r13, [rip + ol_syms + VEC_ptr]
    inc rbx
    movsxd r14, dword ptr [r13 + OLS_first]
    test r14, r14
    js 8b
    mov esi, [r13 + OLS_node]
    test esi, esi
    js 8b
    mov rdi, [rip + ol_tree]
    call tree_kids_begin
81: mov rdi, r14
    call row
    imul rax, r14, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    movsxd r14, dword ptr [rax + OLS_next]
    test r14, r14
    jns 81b
    mov rdi, [rip + ol_tree]
    xor esi, esi
    call tree_kids_end
    jmp 8b
9:  EPILOGUE

# row(i): symbol i's row (inside a tree_kids_begin): its id is its parent's and its name, with a
# count when siblings share the name, so the rows keep their state as the file changes
row:
    PROLOGUE
    mov rbx, rdi
    imul r12, rbx, OLS_SIZE
    add r12, [rip + ol_syms + VEC_ptr]
    lea rdi, [rip + ol_buf]
    call sb_clear
    mov rdi, rbx
    call push_id
    mov rsi, [r12 + OLS_name]
    add rsi, [rip + ol_bytes + SB_ptr]
    mov r13, rsi
    mov rdi, rsi
    call strlen
    mov r8, rax
    mov r9d, KIDS_LEAF
    cmp dword ptr [r12 + OLS_first], -1
    je 1f
    mov r9d, KIDS_OPEN
1:  mov rdi, [rip + ol_tree]
    mov rsi, [rip + ol_buf + SB_ptr]
    mov rdx, [rip + ol_buf + SB_len]
    mov rcx, r13
    call tree_kid
    test eax, eax
    js 9f
    imul r12, rbx, OLS_SIZE
    add r12, [rip + ol_syms + VEC_ptr]
    mov [r12 + OLS_node], eax
    mov r14d, eax
    mov rdi, [rip + ol_tree]
    mov esi, eax
    lea rdx, [rbx + 1]
    call tree_set_user
    mov rsi, [r12 + OLS_detail]
    add rsi, [rip + ol_bytes + SB_ptr]
    mov r13, rsi
    mov rdi, rsi
    call strlen
    mov rcx, rax
    mov rdi, [rip + ol_tree]
    mov esi, r14d
    mov rdx, r13
    call tree_set_desc
9:  EPILOGUE

# push_id(i): ol_buf gets symbol i's path of names (parents first), each with "#N" when N earlier
# siblings have the same name (counted along at most 200 siblings, else "@" and its index)
push_id:
    PROLOGUE
    mov rbx, rdi
    imul r12, rbx, OLS_SIZE
    add r12, [rip + ol_syms + VEC_ptr]
    movsxd rdi, dword ptr [r12 + OLS_parent]
    test rdi, rdi
    js 1f
    call push_id
    imul r12, rbx, OLS_SIZE
    add r12, [rip + ol_syms + VEC_ptr]
1:  lea rdi, [rip + ol_buf]
    mov esi, 1
    call sb_push_byte
    mov rsi, [r12 + OLS_name]
    add rsi, [rip + ol_bytes + SB_ptr]
    lea rdi, [rip + ol_buf]
    call sb_push_cstr
    # its earlier siblings of the same name
    movsxd r14, dword ptr [rip + ol_top]
    movsxd rax, dword ptr [r12 + OLS_parent]
    test rax, rax
    js 2f
    imul rax, rax, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    movsxd r14, dword ptr [rax + OLS_first]
2:  xor r13d, r13d              # same names
    xor r15d, r15d              # steps
3:  cmp r14, rbx
    je 5f
    test r14, r14
    js 5f
    inc r15
    cmp r15, 200
    ja 6f
    imul rax, r14, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    movsxd r14, dword ptr [rax + OLS_next]
    mov rdi, [rax + OLS_name]
    add rdi, [rip + ol_bytes + SB_ptr]
    mov rsi, [r12 + OLS_name]
    add rsi, [rip + ol_bytes + SB_ptr]
    call strcmp_eq
    add r13, rax
    jmp 3b
5:  test r13, r13
    jz 9f
    lea rdi, [rip + ol_buf]
    mov esi, '#'
    call sb_push_byte
    lea rdi, [rip + ol_buf]
    mov rsi, r13
    call sb_push_u64
    jmp 9f
6:  lea rdi, [rip + ol_buf]
    mov esi, '@'
    call sb_push_byte
    lea rdi, [rip + ol_buf]
    mov rsi, rbx
    call sb_push_u64
9:  EPILOGUE

# follow(doc): while the editor has the keyboard, the tree's cursor is the symbol around the cursor
follow:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + ol_has], 1
    jne 9f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + ol_doc]
    jne 9f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lf_line_col
    mov r12, rax                # the cursor's line and column
    mov r13, rdx
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + ol_curpos]
    jne 1f
    cmp rbx, [rip + ol_curdoc]
    je 9f
1:  mov [rip + ol_curpos], rax
    mov [rip + ol_curdoc], rbx
    mov r14, -1                 # the innermost one around the cursor
    mov r15, -1                 # the last one starting before it
    xor ecx, ecx
2:  cmp rcx, [rip + ol_syms + VEC_len]
    jae 5f
    imul rax, rcx, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    mov edx, [rax + OLS_l1]     # starts at or before the cursor?
    cmp rdx, r12
    ja 4f
    jb 3f
    mov edx, [rax + OLS_c1]
    cmp rdx, r13
    ja 4f
3:  mov r15, rcx
    mov edx, [rax + OLS_l2]     # and ends at or after it?
    cmp rdx, r12
    jb 4f
    ja 31f
    mov edx, [rax + OLS_c2]
    cmp rdx, r13
    jb 4f
31: mov r14, rcx
4:  inc rcx
    jmp 2b
5:  test r14, r14
    jns 6f
    mov r14, r15
    test r14, r14
    js 9f
6:  imul rax, r14, OLS_SIZE
    add rax, [rip + ol_syms + VEC_ptr]
    mov esi, [rax + OLS_node]
    test esi, esi
    js 9f
    mov r12d, esi
    mov rdi, [rip + ol_tree]
    call tree_set_cursor
    mov rdi, [rip + ol_tree]
    mov esi, r12d
    call tree_reveal
9:  EPILOGUE

# activate(ctx, tr, node): the symbol's start in the editor, nothing selected
activate:
    PROLOGUE
    mov rdi, rsi
    mov esi, edx
    call tree_user
    test rax, rax
    jz 9f
    lea rbx, [rax - 1]
    mov rdi, [rip + ol_doc]
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
    imul r13, rbx, OLS_SIZE
    add r13, [rip + ol_syms + VEC_ptr]
    mov rdi, r12
    mov esi, [r13 + OLS_l1]
    mov edx, [r13 + OLS_c1]
    call lf_pos_near
    mov [r12 + DOC_cur], rax
    mov [r12 + DOC_anchor], rax
    call ed_touch
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# place_draw(ctx, x, y, w, h): the rows, or why there are none
place_draw:
    PROLOGUE 16
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    lea r8, [rip + .Lnone]
    cmp dword ptr [rip + ol_has], 2
    je 1f
    lea r8, [rip + .Lempty]
    cmp qword ptr [rip + ol_syms + VEC_len], 0
    jne 2f
1:  lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 4]
    M ecx, MI_ROW
    COLOR r9d, T_MUTED
    call ui_text_c
    EPILOGUE
2:  call place_focused
    xor r9d, r9d
    cmp eax, [rip + ol_place]
    sete r9b
    mov rdi, [rip + ol_tree]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call tree_draw
    EPILOGUE

# place_key(ctx, keysym, cp, mods) -> eax taken: Escape goes to the editor, the rest is the tree's
place_key:
    cmp esi, KEY_ESCAPE
    jne 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    ret
1:  mov rdi, [rip + ol_tree]
    jmp tree_key

# FN outline_ext_gone(ext): its program ended: its request is not waited for
FN outline_ext_gone
    cmp rdi, [rip + ol_ext]
    jne 1f
    mov qword ptr [rip + ol_id], 0
    mov qword ptr [rip + ol_ext], 0
    mov qword ptr [rip + ol_version], -1   # asked again (of whoever serves then)
1:  ret

# FN outline_dump(sb): print-outline: "outline doc=ID version=V symbols=N", then the rows;
# "outline=none" before the section exists
FN outline_dump
    PROLOGUE
    mov r12, rdi
    cmp dword ptr [rip + ol_place], 0
    jge 1f
    mov rdi, r12
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
    EPILOGUE
1:  mov rdi, r12
    lea rsi, [rip + .Ld_doc]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + ol_doc]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_symbols]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + ol_syms + VEC_len]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_visible]
    call sb_push_cstr
    mov edi, [rip + ol_place]
    call place_visible
    mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + ol_tree]
    mov rsi, r12
    call tree_dump
    EPILOGUE

.section .rodata
.p2align 3
place_ops: .quad place_draw, place_key, 0, 0, 0, 0
tree_ops: .quad activate, 0, 0, 0, 0, 0, 0, 0
.Lname: .asciz "outline"
.Ltitle: .asciz "Outline"
.Lv_symbols: .asciz "symbols "
.Linvoked: .asciz " invoked -"
.Lnone: .asciz "No symbols provider for this file"
.Lempty: .asciz "No symbols"
.Ld_none: .asciz "outline=none\n"
.Ld_doc: .asciz "outline doc="
.Ld_symbols: .asciz " symbols="
.Ld_visible: .asciz " visible="
