# Expand and Shrink Selection (docs/extensions/v1.1.md, "selection-ranges"): each selection grows
# to the smallest range of its chain that strictly contains it; shrink goes back through the
# selections before; any other change of the selections or the text forgets the chain. The chains
# come from the document's selection-ranges provider (one request for every selection's cursor);
# without one, or without an answer within a second (the kind's hard limit), rhun's own chain is
# used: the word, the line's text without its indentation, the whole line, the document.
#
#   cmd_expand_selection, cmd_shrink_selection, selrange_reply(ext, id, ok, body, len) -> eax 1
#   when it answered the selection-ranges request (the pump), selrange_ext_gone(ext)
.include "rhun.inc"

.equ SR_SELS, 64                # selections with a chain
.equ SR_CHAIN, 66               # ranges in a chain (64 from the provider, room for ours)
.equ SR_STACK, 32               # shrink steps kept

.bss
.p2align 3
sr_doc: .quad 0                 # the chains' document (DOC*, id, version)
sr_docid: .quad 0
sr_version: .quad 0
sr_n: .quad 0                   # selections with chains
sr_counts: .zero 4 * SR_SELS
sr_ranges: .zero 16 * SR_CHAIN * SR_SELS     # start, end; innermost first
sr_last: .zero 16 * SR_SELS     # the selections as they were installed last ({cur, anchor})
sr_last_n: .quad 0
sr_stack: .zero 16 * SR_SELS * SR_STACK      # the selections before each step
sr_stack_n: .zero 8 * SR_STACK
sr_depth: .quad 0
sr_ext: .quad 0                 # the request out: provider, id
sr_id: .quad 0
sr_pairs: .zero 16 * SR_SELS    # the selections now
sr_npairs: .quad 0
sr_body: .zero SB_SIZE
sr_line: .zero SB_SIZE

.text

# chain(i) -> rax the first range of selection i's chain
chain:
    imul rax, rdi, 16 * SR_CHAIN
    lea rcx, [rip + sr_ranges]
    add rax, rcx
    ret

# collect(doc): sr_pairs = its selections (at most SR_SELS)
collect:
    PROLOGUE
    mov rbx, rdi
    call doc_selections_count
    cmp rax, SR_SELS
    jbe 1f
    mov eax, SR_SELS
1:  mov r12, rax
    xor r13d, r13d
2:  cmp r13, r12
    jae 3f
    mov rdi, rbx
    mov rsi, r13
    call doc_selections_get
    mov rcx, r13
    shl rcx, 4
    lea r8, [rip + sr_pairs]
    mov [r8 + rcx], rax
    mov [r8 + rcx + 8], rdx
    inc r13
    jmp 2b
3:  mov [rip + sr_npairs], r12
    EPILOGUE

# same_as_last(doc) -> eax 1 when the chains are about this document as it is and its selections
# are the ones last installed
same_as_last:
    xor eax, eax
    cmp rdi, [rip + sr_doc]
    jne 9f
    mov rcx, [rdi + DOC_id]
    cmp rcx, [rip + sr_docid]
    jne 9f
    mov rcx, [rdi + DOC_version]
    cmp rcx, [rip + sr_version]
    jne 9f
    mov rcx, [rip + sr_npairs]
    cmp rcx, [rip + sr_last_n]
    jne 9f
    shl rcx, 1
    lea rsi, [rip + sr_pairs]
    lea rdx, [rip + sr_last]
1:  test rcx, rcx
    jz 2f
    dec rcx
    mov r8, [rsi + rcx*8]
    cmp r8, [rdx + rcx*8]
    jne 9f
    jmp 1b
2:  mov eax, 1
9:  ret

# forget(doc): new chains begin for the document as it is (none yet)
forget:
    mov [rip + sr_doc], rdi
    mov rax, [rdi + DOC_id]
    mov [rip + sr_docid], rax
    mov rax, [rdi + DOC_version]
    mov [rip + sr_version], rax
    mov qword ptr [rip + sr_n], 0
    mov qword ptr [rip + sr_depth], 0
    mov qword ptr [rip + sr_last_n], 0
    ret

# FN cmd_expand_selection(): shift+alt+Right
FN cmd_expand_selection
    PROLOGUE
    call lf_focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    call collect
    mov rdi, rbx
    call same_as_last
    test eax, eax
    jz 1f
    cmp qword ptr [rip + sr_n], 0
    je 1f
    mov rdi, rbx
    call step                   # the chains it has
    jmp 9f
1:  mov rdi, rbx
    call forget
    cmp qword ptr [rip + sr_id], 0
    jne 9f                      # asked already: the answer expands
    mov rdi, rbx
    call ask
    test eax, eax
    jnz 9f
    mov rdi, rbx                # nobody to ask: rhun's own chains
    call own_chains
    mov rdi, rbx
    call step
9:  EPILOGUE

# FN cmd_shrink_selection(): shift+alt+Left: the selections before the last expansion
FN cmd_shrink_selection
    PROLOGUE
    call lf_focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    call collect
    mov rdi, rbx
    call same_as_last
    test eax, eax
    jz 9f
    mov rax, [rip + sr_depth]
    test rax, rax
    jz 9f
    dec rax
    mov [rip + sr_depth], rax
    lea rcx, [rip + sr_stack_n]
    mov r12, [rcx + rax*8]
    imul rsi, rax, 16 * SR_SELS
    lea rcx, [rip + sr_stack]
    add rsi, rcx
    mov rdi, rbx
    mov rdx, r12
    call install
9:  EPILOGUE

# install(doc, pairs, n): the selections go in; sr_last remembers what came of them
install:
    PROLOGUE
    mov rbx, rdi
    call sel_install
    mov rdi, rbx
    call ed_touch_doc
    mov rdi, rbx
    call collect
    mov rcx, [rip + sr_npairs]
    mov [rip + sr_last_n], rcx
    lea rdi, [rip + sr_last]
    lea rsi, [rip + sr_pairs]
    shl rcx, 4
    mov rdx, rcx
    call memcpy
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ed_touch_doc(doc): the editor shows the caret (when it is the editor's document)
ed_touch_doc:
    cmp rdi, [rip + g_doc]
    jne 1f
    jmp ed_touch
1:  ret

# step(doc): each selection grows to the smallest range of its chain that strictly contains it;
# the selections before are kept for shrink
step:
    PROLOGUE 16
    mov rbx, rdi
    # the selections before
    mov rax, [rip + sr_depth]
    cmp rax, SR_STACK
    jb 1f
    lea rdi, [rip + sr_stack]   # full: the oldest goes
    lea rsi, [rdi + 16 * SR_SELS]
    mov edx, 16 * SR_SELS * (SR_STACK - 1)
    call memmove
    lea rdi, [rip + sr_stack_n]
    lea rsi, [rdi + 8]
    mov edx, 8 * (SR_STACK - 1)
    call memmove
    mov qword ptr [rip + sr_depth], SR_STACK - 1
    mov rax, SR_STACK - 1
1:  mov rcx, [rip + sr_npairs]
    lea rdx, [rip + sr_stack_n]
    mov [rdx + rax*8], rcx
    imul rdi, rax, 16 * SR_SELS
    lea rdx, [rip + sr_stack]
    add rdi, rdx
    lea rsi, [rip + sr_pairs]
    shl rcx, 4
    mov rdx, rcx
    call memcpy
    # each one grows
    xor r12d, r12d
    xor r15d, r15d              # changed
2:  cmp r12, [rip + sr_npairs]
    jae 6f
    cmp r12, [rip + sr_n]
    jae 6f
    mov rax, r12
    shl rax, 4
    lea r13, [rip + sr_pairs]
    add r13, rax
    mov rax, [r13]              # a, b: the selection's start and end
    mov rcx, [r13 + 8]
    cmp rax, rcx
    jbe 3f
    xchg rax, rcx
3:  mov [rsp], rax
    mov [rsp + 8], rcx
    mov rdi, r12
    call chain
    mov r14, rax
    lea rcx, [rip + sr_counts]
    mov ecx, [rcx + r12*4]
4:  test ecx, ecx
    jz 5f
    dec ecx
    mov rax, [r14]
    mov rdx, [r14 + 8]
    add r14, 16
    cmp rax, [rsp]
    ja 4b
    cmp rdx, [rsp + 8]
    jb 4b
    cmp rax, [rsp]
    jne 41f
    cmp rdx, [rsp + 8]
    je 4b                       # the same: not larger
41: mov [r13 + 8], rax          # anchor at its start, the caret at its end
    mov [r13], rdx
    inc r15d
5:  inc r12
    jmp 2b
6:  test r15d, r15d
    jz 9f
    inc qword ptr [rip + sr_depth]
    mov rdi, rbx
    lea rsi, [rip + sr_pairs]
    mov rdx, [rip + sr_npairs]
    call install
9:  EPILOGUE

# own_chains(doc): rhun's chain for each selection: the word at its caret, the line's text without
# indentation, the whole line, the document
own_chains:
    PROLOGUE 16
    mov rbx, rdi
    mov rax, [rip + sr_npairs]
    mov [rip + sr_n], rax
    xor r12d, r12d
1:  cmp r12, [rip + sr_npairs]
    jae 9f
    mov rdi, r12
    call chain
    mov r13, rax
    xor r14d, r14d              # ranges
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + sr_pairs]
    mov r15, [rcx + rax]        # the caret
    # the word
    mov rdi, rbx
    mov rsi, r15
    call word_at
    cmp rax, rdx
    jae 2f
    mov [r13], rax
    mov [r13 + 8], rdx
    inc r14d
2:  # the line's text, without indentation
    mov rdi, rbx
    mov rsi, r15
    call doc_line_of
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_line_end
    mov rcx, rax                # its end (the line feed)
    mov rdx, [rsp + 8]
3:  cmp rdx, rcx
    jae 4f
    push rcx
    push rdx
    mov rdi, rbx
    mov rsi, rdx
    call doc_byte
    pop rdx
    pop rcx
    cmp eax, ' '
    je 31f
    cmp eax, 9
    jne 4f
31: inc rdx
    jmp 3b
4:  mov rax, r14
    shl rax, 4
    mov [r13 + rax], rdx
    mov [r13 + rax + 8], rcx
    inc r14d
    # the whole line, with its line feed
    mov rdi, rbx
    call doc_len
    mov r8, rax
    mov rcx, rax
    mov rax, [rsp]
    inc rax
    cmp rax, [rbx + DOC_nlines]
    jae 5f
    mov rdi, rbx
    mov rsi, rax
    push r8
    push r8
    call doc_line_start
    pop r8
    pop r8
    mov rcx, rax
5:  mov rax, r14
    shl rax, 4
    mov rdx, [rsp + 8]
    mov [r13 + rax], rdx
    mov [r13 + rax + 8], rcx
    inc r14d
    # the document
    mov rax, r14
    shl rax, 4
    mov qword ptr [r13 + rax], 0
    mov [r13 + rax + 8], r8
    inc r14d
    lea rcx, [rip + sr_counts]
    mov [rcx + r12*4], r14d
    inc r12
    jmp 1b
9:  EPILOGUE

# ask(doc) -> eax 1 when "selection-ranges DOC VERSION N LEN" + each caret's "LINE COL" went to the
# document's provider
ask:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 8f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, r13
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, r13
    mov esi, FEAT_SELECTION_RANGES
    call ext_feature
    test eax, eax
    jz 1b
    mov rdi, r13
    mov esi, EXT_pv_selection_ranges
    call ext_pv
    mov rdi, rax
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 1b
    # the body: each caret's LINE COL
    lea rdi, [rip + sr_body]
    call sb_clear
    xor r14d, r14d
2:  cmp r14, [rip + sr_npairs]
    jae 3f
    mov rax, r14
    shl rax, 4
    lea rcx, [rip + sr_pairs]
    mov rsi, [rcx + rax]
    mov rdi, rbx
    call lf_line_col
    mov r15, rdx
    lea rdi, [rip + sr_body]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + sr_body]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + sr_body]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + sr_body]
    mov esi, 10
    call sb_push_byte
    inc r14
    jmp 2b
3:  lea rdi, [rip + sr_line]
    call sb_clear
    lea rdi, [rip + sr_line]
    lea rsi, [rip + .Lv_sel]
    call sb_push_cstr
    lea rdi, [rip + sr_line]
    mov rsi, [rbx + DOC_id]
    call sb_push_u64
    lea rdi, [rip + sr_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + sr_line]
    mov rsi, [rbx + DOC_version]
    call sb_push_u64
    lea rdi, [rip + sr_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + sr_line]
    mov rsi, [rip + sr_npairs]
    call sb_push_u64
    lea rdi, [rip + sr_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + sr_line]
    mov rsi, [rip + sr_body + SB_len]
    call sb_push_u64
    mov rdi, r13
    mov rsi, rbx
    mov rdx, [rip + sr_line + SB_ptr]
    mov rcx, [rip + sr_line + SB_len]
    mov r8, [rip + sr_body + SB_ptr]
    mov r9, [rip + sr_body + SB_len]
    call extproto_host_send_body
    test rax, rax
    jz 8f
    mov [rip + sr_id], rax
    mov [rip + sr_ext], r13
    mov rdi, r13
    mov rsi, rax
    mov edx, PK_SELECTION
    mov ecx, QO_LANGFEAT
    call query_track
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN selrange_reply(ext, id, ok, body, len) -> eax 1 when it answered the selection-ranges request:
# the chains (or rhun's own after an error or no answer in time), then the first step
FN selrange_reply
    PROLOGUE 16
    cmp rsi, [rip + sr_id]
    jne 8f
    test rsi, rsi
    jz 8f
    cmp rdi, [rip + sr_ext]
    jne 8f
    mov qword ptr [rip + sr_id], 0
    mov r12, rdi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    mov rdi, [rip + sr_docid]
    call extproto_doc
    test rax, rax
    jz 7f
    cmp rax, [rip + sr_doc]
    jne 7f
    mov rbx, rax
    mov rcx, [rbx + DOC_version]
    cmp rcx, [rip + sr_version]
    jne 7f                      # changed meanwhile: the answer is not about this text
    mov rdi, rbx                # the selections must be the ones asked about
    call collect
    test r13d, r13d
    jz 5f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call parse
    test eax, eax
    jnz 6f
    mov rdi, r12
    mov esi, PK_SELECTION
    call query_dropped
5:  mov rdi, rbx                # rhun's own
    call own_chains
6:  mov rdi, rbx
    call step
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# parse(doc, body, len) -> eax 1 with the chains, 0 when the body breaks the rules: N groups, each "M"
# LF and M lines "L1 C1 L2 C2", innermost first; a group's ranges after one that does not contain
# the one before are left out (equal ones skipped)
parse:
    PROLOGUE 32
    mov rbx, rdi
    mov [rip + ps_ptr], rsi
    lea rax, [rsi + rdx]
    mov [rip + ps_end], rax
    mov qword ptr [rip + sr_n], 0
    xor r12d, r12d              # the group
1:  mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jae 7f
    cmp r12, SR_SELS
    jae 8f
    call ps_line
    test eax, eax
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 64
    ja 8f
    mov r15, rax                # M
    call ps_eol
    test eax, eax
    jz 8f
    mov rdi, r12
    call chain
    mov r13, rax
    xor r14d, r14d              # kept
    mov dword ptr [rsp + 16], 0 # broken: the rest of the group is read and left out
2:  test r15, r15
    jz 6f
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call lf_four
    test eax, eax
    jz 8f
    call ps_eol
    test eax, eax
    jz 8f
    cmp dword ptr [rsp + 16], 0
    jne 2b
    lea rax, [rip + lf_tmp4]
    mov rdi, rbx
    mov esi, [rax]
    mov edx, [rax + 4]
    call lf_pos
    test rax, rax
    js 5f
    mov [rsp], rax
    lea rax, [rip + lf_tmp4]
    mov rdi, rbx
    mov esi, [rax + 8]
    mov edx, [rax + 12]
    call lf_pos
    test rax, rax
    js 5f
    cmp rax, [rsp]
    jb 5f
    mov [rsp + 8], rax
    test r14, r14
    jz 4f
    mov rax, r14                # it must contain the one before
    dec rax
    shl rax, 4
    mov rcx, [r13 + rax]
    mov rdx, [r13 + rax + 8]
    cmp [rsp], rcx
    ja 5f
    cmp [rsp + 8], rdx
    jb 5f
    cmp [rsp], rcx
    jne 4f
    cmp [rsp + 8], rdx
    je 2b                       # equal: skipped
4:  mov rax, r14
    shl rax, 4
    mov rcx, [rsp]
    mov [r13 + rax], rcx
    mov rcx, [rsp + 8]
    mov [r13 + rax + 8], rcx
    inc r14
    jmp 2b
5:  mov dword ptr [rsp + 16], 1
    jmp 2b
6:  lea rcx, [rip + sr_counts]
    mov [rcx + r12*4], r14d
    inc r12
    jmp 1b
7:  mov rax, r12                # groups not given: nothing for those selections
8:  test r12, r12
    jz 81f
    mov rcx, [rip + ps_ptr]
    cmp rcx, [rip + ps_end]
    jb 81f
    mov rcx, r12
2:  cmp rcx, [rip + sr_npairs]
    jae 3f
    lea rdx, [rip + sr_counts]
    mov dword ptr [rdx + rcx*4], 0
    inc rcx
    jmp 2b
3:  mov rax, [rip + sr_npairs]
    mov [rip + sr_n], rax
    mov eax, 1
    EPILOGUE
81: xor eax, eax
    EPILOGUE

# FN selrange_ext_gone(ext): its request is not waited for
FN selrange_ext_gone
    cmp rdi, [rip + sr_ext]
    jne 1f
    mov qword ptr [rip + sr_id], 0
    mov qword ptr [rip + sr_ext], 0
1:  ret

.section .rodata
.Lv_sel: .asciz "selection-ranges "
