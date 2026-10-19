# completion lists and signature help from extensions (docs/extensions/v1.md, 12b and 12c): asking
# the providers, merging and filtering their items, the list under the cursor and putting the
# chosen item in; the signature above the cursor. Answers arrive inside extproto's pump, so they
# only change state here: whatever has to be sent goes out from the frame (complete_draw) or the
# tick, never from complete_reply.
.include "rhun.inc"

.equ CP_CHOICES, 1
.equ CP_SHOW, 50                # items kept after filtering, best first
.equ CP_ROWS, 10                # rows the list shows at once
.equ CP_TYPED_MS, 150           # the pause after typing in a word before the list is asked for
.equ CP_QMAX, 256               # the filter text: longer filters nothing
.equ HR_MAX, 64                 # requests waiting for answers
.equ AE_MAX, 64                 # edits an accepted item makes, its own and its extra ones
.equ HR_COMPLETE, 1
.equ HR_SIGNATURE, 2
.equ HR_RESOLVE, 3              # complete-resolve: HR_req holds the item's serial
.equ CK_COUNT, 17               # item kinds (kind_names)
.equ DOC_LINES_MAX, 14          # the documentation beside the list
.equ SG_LINES_MAX, 6            # the signature's documentation

# an item of the list
STRUCT
F CI_ext, 8                     # EXT* that gave it
F CI_o1, 8                      # the range it replaces, byte offsets, as it was asked for
F CI_o2, 8
F CI_req, 8                     # the cursor when it was asked for: o2 past it moves with typing
F CI_off, 8                     # its bytes in cp_bytes: label, insert, detail, extra
F CI_llen, 4
F CI_ilen, 4
F CI_dlen, 4
F CI_xlen, 4
F CI_kind, 4
F CI_flags, 4                   # CF_*: what its complete-items records say
F CI_serial, 4                  # unique for the session: a resolve answer finds its item by it
F CI_pad, 4
F CI_r2, 8                      # the replace range's end (as CI_o2; it starts at CI_o1), or -1
F CI_ver, 8                     # the document's version the list was asked at
ENDSTRUCT CI_SIZE
# complete-items (docs/extensions/v1.1.md): an item's flags from its EXTRA records
.equ CF_PRESELECT, 1
.equ CF_DEPRECATED, 2
.equ CF_ADJUST, 4               # later lines of INSERT get the insertion line's indentation
.equ CF_AFTER_SIG, 8            # signature help after accepting
.equ CF_AFTER_COMPLETE, 16      # a new list after accepting
.equ CF_RESOLVE, 32             # it has resolve data
.equ CF_RESOLVE_EDITS, 64       # its resolve answer may add edits: accepting waits for it
.equ CF_RESOLVED, 128           # its resolve answer came (or failed)
.equ CF_REPLACE, 256            # a replace range
.equ CF_FILTER, 512             # a filter text
.equ CF_RESOLVING, 1024         # its resolve request is out
.equ CF_COMMIT, 2048            # commit characters
.equ CF_SUFFIX, 4096
.equ CP_RESOLVE_MS, 60          # the pause after a selection before its item is resolved
.equ CP_WAIT_MS, 500            # how long accepting waits for a resolve that may add edits

# a request rhun sent and waits on
STRUCT
F HR_ext, 8
F HR_id, 8
F HR_kind, 4                    # HR_COMPLETE, HR_SIGNATURE
F HR_session, 4                 # cp_session or sg_session when it went out
F HR_req, 8                     # the cursor then
F HR_language_revision, 8
F HR_version, 8                 # the document's version then
F HR_parts, 4                   # query-part brought some of its items
F HR_pad, 4
ENDSTRUCT HR_SIZE

.data
.p2align 3
cp_qo1: .quad -1                # the offset cp_q was copied from, the cursor then, its length
cp_hover: .long -1              # the row under the pointer
.long 0

.bss
.p2align 3
cp_source: .long 0              # 0 providers, CP_CHOICES native literal values
.globl cp_open, sg_open
cp_open: .long 0                # 0 closed, 1 asked, 2 items to show
cp_session: .long 0             # each new list: answers for an older one are dropped
cp_doc: .quad 0                 # the session's DOC* and its id (a freed DOC's address can return)
cp_doc_id: .quad 0
cp_language_revision: .quad 0
cp_start: .quad 0               # where the word starts; the filter text runs from it to the cursor
cp_tail: .quad 0                # bytes after the cursor: the same while the user types in the word
cp_seen_cur: .quad 0            # the cursor and version the list was filtered for
cp_seen_ver: .quad 0
cp_due: .quad 0                 # time_ms when the list is asked for after typing (0: not due)
cp_more: .long 0                # a provider cut its list short: typing asks again
cp_reask: .long 0               # ask again from the frame (an answer came in the pump)
cp_sel: .long 0                 # the selected row
cp_top: .long 0                 # the first row shown
cp_nshown: .long 0
cp_choice_identity: .quad 0
cp_choice_activation: .quad 0
cp_choice_primary: .quad 0
cp_shown: .zero 4 * SN_OPTIONS_MAX     # item indices, best first
cp_scores: .zero 4 * SN_OPTIONS_MAX
cp_rect: .zero 16               # where the list was drawn: x y w h (h 0: nowhere)
cp_items: .zero VEC_SIZE        # CI records
cp_bytes: .zero SB_SIZE         # their text
cp_new_items: .zero VEC_SIZE    # an answer being merged
cp_new_bytes: .zero SB_SIZE
cp_reqs: .zero VEC_SIZE         # HR records
cp_q: .zero CP_QMAX             # the filter text
cp_qlen: .quad 0
cp_qcur: .quad 0
cp_serial: .long 0              # the last item serial given
cp_parse_lf: .long 0            # the provider of the list being parsed agreed complete-items
cp_parse_ver: .quad 0           # the version it was asked at
cp_res_due: .quad 0             # time_ms when the selected item is resolved (0: not due)
cp_res_serial: .long 0          # the item whose resolve request is out (0: none)
cp_wait_serial: .long 0         # the item an accept waits for (0: none)
cp_wait_until: .quad 0
cp_wait_replace: .long 0        # that accept's range: 1 the replace range
cp_wait_ready: .long 0          # its resolve answer came (the tick accepts)
cp_wait_char: .long 0           # a commit character typed after the accept, 0 for none
cp_pad2: .long 0
cp_room: .quad 0                # the items a final answer after parts may still bring (-1: any)
sg_count: .long 0               # signature-list: the signatures and the one shown
sg_index: .long 0
sg_list: .zero SB_SIZE          # the answer's records
sg_ctr: .zero 16                # "2/3"
sg_ctrlen: .long 0
sgl_tmp: .zero 16
sg_open: .long 0                # the signature shows
sg_wait: .long 0                # a request for it is out
sg_again: .long 0               # something changed while it was out: ask again when it answers
sg_session: .long 0
sg_from: .long 0                # the active parameter's bytes in the signature (-1: none)
sg_to: .long 0
sg_doc: .quad 0                 # the DOC* and id it is for
sg_doc_id: .quad 0
sg_language_revision: .quad 0
sg_cur: .quad 0                 # the cursor and version it was last asked for
sg_ver: .quad 0
sg_ext: .quad 0                 # EXT* that answers
sg_text: .zero SB_SIZE          # the signature, LF, the documentation
sg_siglen: .quad 0              # the signature's bytes in sg_text
sg_rect: .zero 16
# the answer parser: where it is, the end of the body and of the current line
.globl ps_ptr, ps_end, ps_lend
ps_ptr: .quad 0
ps_end: .quad 0
ps_lend: .quad 0
ps_doc: .quad 0
ps_rline: .quad 0               # the request's cursor line (0-based) and how far the cursor has moved
ps_delta: .quad 0               # since (typing in the word): positions are turned into the request's
ps_req: .quad 0                 # its cursor offset, for mapping positions back into the live text

.text

# ---------------- helpers ----------------

# is_word(byte) -> eax 1 for a letter, a digit, _ or a byte of a multibyte character
is_word:
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

# word_start(doc, pos) -> rax the start of the word that ends at pos
word_start:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
1:  test r12, r12
    jz 2f
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_byte
    mov edi, eax
    call is_word
    test eax, eax
    jz 2f
    dec r12
    jmp 1b
2:  mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

# trig_has(list, ch) -> eax 1 when ch is one of the list's characters (". :" style, ASCII)
trig_has:
    test rdi, rdi
    jz 8f
    cmp esi, 128
    jae 8f
1:  movzx eax, byte ptr [rdi]
    test eax, eax
    jz 8f
    cmp eax, ' '
    je 4f
    cmp eax, esi
    jne 3f
    movzx ecx, byte ptr [rdi + 1]
    test ecx, ecx
    jz 9f
    cmp ecx, ' '
    je 9f
3:  inc rdi                     # the rest of this word
    movzx eax, byte ptr [rdi]
    test eax, eax
    jz 8f
    cmp eax, ' '
    jne 3b
4:  inc rdi
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# focused_doc() -> rax g_doc when a document tab's editor has the keyboard, else 0
focused_doc:
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

# doc_alive() -> eax 1 when cp_doc is still the open document it was (answers arrive between frames)
doc_alive:
    PROLOGUE
    mov rdi, [rip + cp_doc_id]
    call extproto_doc
    test rax, rax
    jz 1f
    cmp rax, [rip + cp_doc]
    jne 1f
    mov rdi, rax
    mov rsi, [rip + cp_language_revision]
    call doc_language_matches
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

sg_doc_alive:
    PROLOGUE
    mov rdi, [rip + sg_doc_id]
    call extproto_doc
    test rax, rax
    jz 1f
    cmp rax, [rip + sg_doc]
    jne 1f
    mov rdi, rax
    mov rsi, [rip + sg_language_revision]
    call doc_language_matches
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

# Normal tick only. Preserve fresh sessions created after the language changed.
FN complete_language_changed
    PROLOGUE
    mov rbx, rdi
    cmp [rip + cp_doc], rbx
    jne 1f
    mov rax, [rbx + DOC_language_revision]
    cmp [rip + cp_language_revision], rax
    je 1f
    call cp_close
1:  cmp [rip + sg_doc], rbx
    jne 2f
    mov rax, [rbx + DOC_language_revision]
    cmp [rip + sg_language_revision], rax
    je 2f
    call sg_close
2:  EPILOGUE

# providers_any() -> eax 1 when an extension that is running or starting provides completion or
# signature help (one still starting asks once it has: typing in the meantime keeps the timer)
providers_any:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
    mov edx, [rbx + EXT_status]
    cmp edx, ES_RUNNING
    je 2f
    cmp edx, ES_STARTING
    je 2f
    cmp edx, ES_IDLE
    jne 1b
2:  mov rdi, rbx
    mov esi, EXT_pv_complete
    call ext_pv
    test rax, rax
    jnz 9f
    mov rdi, rbx
    mov esi, EXT_pv_signature
    call ext_pv
    test rax, rax
    jz 1b
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# req_remove(i): drop cp_reqs[i]
req_remove:
    mov rax, [rip + cp_reqs + VEC_len]
    dec rax
    mov [rip + cp_reqs + VEC_len], rax
    sub rax, rdi
    jz 9f
    imul rdx, rax, HR_SIZE
    imul rsi, rdi, HR_SIZE
    add rsi, [rip + cp_reqs + VEC_ptr]
    mov rdi, rsi
    add rsi, HR_SIZE
    jmp memmove
9:  ret

# cancel_kind(kind): "0 cancel ID" for every request of that kind still out, and forget them
cancel_kind:
    PROLOGUE
    mov r12d, edi
    xor ebx, ebx
1:  cmp rbx, [rip + cp_reqs + VEC_len]
    jae 9f
    imul rax, rbx, HR_SIZE
    add rax, [rip + cp_reqs + VEC_ptr]
    cmp [rax + HR_kind], r12d
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, [rax + HR_ext]
    mov rsi, [rax + HR_id]
    call query_withdraw
    mov rdi, rbx
    call req_remove
    jmp 1b
9:  EPILOGUE

# line_col(doc, pos) -> rax 1-based line, rdx 1-based byte column
line_col:
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

# ---------------- asking ----------------

# ask(kind cstr, ch, only_trig) -> eax the number of providers asked: "ID complete DOC VERSION
# LINE COL KIND CHAR" to each running provider whose patterns match cp_doc (with only_trig, to those
# whose triggers hold ch)
ask:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], esi
    mov [rsp + 12], edx
    mov dword ptr [rsp + 16], 0
    mov r15, [rip + cp_doc]
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    FEAT_TEST rbx, FEAT_COMPLETE
    jz 1b
    mov rdi, rbx
    mov esi, EXT_pv_complete
    call ext_pv
    mov rdi, rax
    mov rsi, r15
    call extproto_matches
    test eax, eax
    jz 1b
    cmp dword ptr [rsp + 12], 0
    je 2f
    mov rdi, rbx
    mov esi, EXT_pv_ctrig
    call ext_pv
    mov rdi, rax
    mov esi, [rsp + 8]
    call trig_has
    test eax, eax
    jz 1b
2:  cmp qword ptr [rip + cp_reqs + VEC_len], HR_MAX
    jae 9f
    mov rdi, rbx
    lea rsi, [rip + .Lv_complete]
    mov rdx, r15
    mov rcx, [rsp]
    mov r8d, [rsp + 8]
    call extproto_host_request
    test rax, rax
    jz 1b
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, PK_COMPLETE
    mov ecx, QO_COMPLETE
    call query_track
    lea rdi, [rip + cp_reqs]
    mov esi, HR_SIZE
    call vec_push
    mov [rax + HR_ext], rbx
    mov [rax + HR_id], r12
    mov dword ptr [rax + HR_kind], HR_COMPLETE
    mov ecx, [rip + cp_session]
    mov [rax + HR_session], ecx
    mov rcx, [r15 + DOC_cur]
    mov [rax + HR_req], rcx
    mov rcx, [r15 + DOC_language_revision]
    mov [rax + HR_language_revision], rcx
    mov rcx, [r15 + DOC_version]
    mov [rax + HR_version], rcx
    inc dword ptr [rsp + 16]
    jmp 1b
9:  mov eax, [rsp + 16]
    EPILOGUE

# cp_begin(kind, ch, only_trig): a new list for the word at the cursor of the focused document
cp_begin:
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], esi
    mov r12d, edx
    call cp_close
    call focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    call doc_sync_grammar
    test rax, rax
    js 9f
    mov rax, [rbx + DOC_language_revision]
    test rax, rax
    jz 9f
    mov [rip + cp_language_revision], rax
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 9f                      # not with a selection
    inc dword ptr [rip + cp_session]
    mov [rip + cp_doc], rbx
    mov rax, [rbx + DOC_id]
    mov [rip + cp_doc_id], rax
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_start
    mov [rip + cp_start], rax
    mov rdi, rbx
    call doc_len
    sub rax, [rbx + DOC_cur]
    mov [rip + cp_tail], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + cp_seen_cur], rax
    mov rax, [rbx + DOC_version]
    mov [rip + cp_seen_ver], rax
    mov dword ptr [rip + cp_open], 1
    mov dword ptr [rip + cp_more], 0
    mov dword ptr [rip + cp_reask], 0
    mov qword ptr [rip + g_edit_lo], -1     # edits before the list do not count against it
    mov qword ptr [rip + g_edit_hi], 0
    mov rdi, [rsp]
    mov esi, [rsp + 8]
    mov edx, r12d
    call ask
    test eax, eax
    jnz 9f
    call cp_close               # nobody to ask
9:  EPILOGUE

# cp_close(): the list goes; requests still out are cancelled
cp_close:
    push rbx
    mov dword ptr [rip + cp_open], 0
    mov dword ptr [rip + cp_source], 0
    mov dword ptr [rip + cp_nshown], 0
    mov dword ptr [rip + cp_sel], 0
    mov dword ptr [rip + cp_top], 0
    mov dword ptr [rip + cp_more], 0
    mov dword ptr [rip + cp_reask], 0
    mov qword ptr [rip + cp_due], 0
    mov dword ptr [rip + cp_rect + 12], 0
    mov qword ptr [rip + cp_items + VEC_len], 0
    lea rdi, [rip + cp_bytes]
    call sb_clear
    mov qword ptr [rip + cp_qo1], -1
    mov edi, HR_COMPLETE
    call cancel_kind
    mov edi, HR_RESOLVE
    call cancel_kind
    mov qword ptr [rip + cp_res_due], 0
    mov dword ptr [rip + cp_res_serial], 0
    mov dword ptr [rip + cp_wait_serial], 0
    mov dword ptr [rip + cp_wait_ready], 0
    mov dword ptr [rip + cp_wait_char], 0
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# FN complete_typed(cp): the user typed cp in the editor and it went in
FN complete_typed
    PROLOGUE
    mov r12d, edi
    call focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp qword ptr [rbx + DOC_selections], 0
    jne 9f                      # several selections: no automatic completion (multi-cursor)
    call providers_any
    test eax, eax
    jz 9f
    # signature help: one of its triggers asks
    mov edi, r12d
    call sig_trigger
    # completion: a word grows, a trigger character starts a list, anything else ends it
    cmp r12d, 0x80
    jae 1f
    mov edi, r12d
    call is_word
    test eax, eax
    jz 3f
1:  cmp dword ptr [rip + cp_open], 0
    jne 9f                      # the open list follows the word as frames come
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_start
    mov rcx, [rbx + DOC_cur]
    sub rcx, rax
    cmp rcx, 2
    jb 9f
    call time_ms
    add rax, CP_TYPED_MS
    mov [rip + cp_due], rax
    jmp 9f
3:  lea rdi, [rip + .Lk_trigger]
    mov esi, r12d
    mov edx, 1
    call cp_begin
9:  EPILOGUE

# FN cmd_complete(): ctrl+space, the list at once
FN cmd_complete
    call ed_single              # completion is about one place (multi-cursor)
    push rbx
    call focused_doc
    test rax, rax
    jz 1f
    mov rdi, rax
    call snippet_complete_collapse
1:
    lea rdi, [rip + .Lk_invoked]
    mov esi, '-'
    xor edx, edx
    call cp_begin
    pop rbx
    ret

# FN complete_timeout() -> ms until the typed list is due, the selected item is resolved or a
# waiting accept goes ahead, or -1
FN complete_timeout
    push rbx
    push r12
    push r13
    mov rbx, [rip + cp_due]
    mov rcx, [rip + cp_res_due]
    test rbx, rbx
    jz 1f
    test rcx, rcx
    jz 2f
    cmp rcx, rbx
    jae 2f
1:  mov rbx, rcx
2:  cmp dword ptr [rip + cp_wait_serial], 0
    je 3f
    mov rcx, [rip + cp_wait_until]
    cmp dword ptr [rip + cp_wait_ready], 0
    je 21f
    xor ecx, ecx
    inc ecx
21: test rbx, rbx
    jz 22f
    cmp rcx, rbx
    jae 3f
22: mov rbx, rcx
3:  test rbx, rbx
    jz 8f
    call time_ms
    sub rbx, rax
    jns 4f
    xor ebx, ebx
4:  mov eax, ebx
    pop r13
    pop r12
    pop rbx
    ret
8:  mov eax, -1
    pop r13
    pop r12
    pop rbx
    ret

# FN complete_tick(): the typed list when its pause is over; complete-items: the selected item's
# resolve, and the accept that waited for one
FN complete_tick
    push rbx
    cmp dword ptr [rip + cp_wait_serial], 0
    je 2f
    cmp dword ptr [rip + cp_wait_ready], 0
    jne 1f
    call time_ms
    cmp rax, [rip + cp_wait_until]
    jb 2f
1:  call cp_wait_accept
2:  mov rbx, [rip + cp_res_due]
    test rbx, rbx
    jz 3f
    call time_ms
    cmp rax, rbx
    jb 3f
    mov qword ptr [rip + cp_res_due], 0
    call selected_item
    test rax, rax
    jz 3f
    mov rdi, rax
    call res_send
3:  mov rbx, [rip + cp_due]
    test rbx, rbx
    jz 9f
    call time_ms
    cmp rax, rbx
    jb 9f
    mov qword ptr [rip + cp_due], 0
    cmp dword ptr [rip + cp_open], 0
    jne 9f
    call focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_start
    mov rcx, [rbx + DOC_cur]
    sub rcx, rax
    cmp rcx, 2
    jb 9f                       # the word went while it waited
    # A provider may need longer than the typing pause to finish its handshake. Keep the
    # request due while a matching one starts, rather than losing the first completion.
    push r12
    push r13
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 3f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, r13
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [r13 + EXT_status], ES_STARTING
    jne 1b
    mov rdi, r13
    mov esi, EXT_pv_complete
    call ext_pv
    mov rdi, rax
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 1b
    call time_ms
    add rax, 50
    mov [rip + cp_due], rax
    pop r13
    pop r12
    jmp 9f
3:  pop r13
    pop r12
    lea rdi, [rip + .Lk_typed]
    mov esi, '-'
    xor edx, edx
    call cp_begin
9:  pop rbx
    ret

# ---------------- answers ----------------

# FN complete_reply(ext, id, ok, body, len) -> eax 1 when it was a completion's or a signature's
# request (called from extproto's pump: state only)
FN complete_reply
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov r14, rcx
    mov r15, r8
    xor r13d, r13d
1:  cmp r13, [rip + cp_reqs + VEC_len]
    jae 8f                      # not a completion's or a signature's
    imul rax, r13, HR_SIZE
    add rax, [rip + cp_reqs + VEC_ptr]
    cmp [rax + HR_ext], rbx
    jne 2f
    cmp [rax + HR_id], r12
    je 3f
2:  inc r13
    jmp 1b
3:  mov ecx, [rax + HR_kind]
    mov [rsp + 4], ecx
    mov ecx, [rax + HR_session]
    mov [rsp + 8], ecx
    mov rcx, [rax + HR_req]
    mov [rsp + 16], rcx
    mov rcx, [rax + HR_language_revision]
    mov [rsp + 24], rcx
    mov rcx, [rax + HR_version]
    mov [rip + cp_parse_ver], rcx
    mov ecx, [rax + HR_parts]
    mov [rsp + 12], ecx
    mov rdi, r13
    call req_remove
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 9f
    mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rsp + 4], HR_SIGNATURE
    je 5f
    cmp dword ptr [rsp + 4], HR_RESOLVE
    jne 4f
    mov eax, [rsp + 8]          # complete-items: an item's resolve answer
    cmp eax, [rip + cp_session]
    jne 9f
    mov edi, [rsp + 16]
    mov esi, [rsp]
    mov rdx, r14
    mov rcx, r15
    call res_answer
    jmp 9f
4:  # a list, for the session still open
    cmp dword ptr [rsp], 0
    je 9f                       # an error adds nothing
    mov eax, [rsp + 8]
    cmp eax, [rip + cp_session]
    jne 9f
    cmp dword ptr [rip + cp_open], 0
    je 9f
    mov rax, [rsp + 24]
    cmp rax, [rip + cp_language_revision]
    jne 9f
    call doc_alive
    test eax, eax
    jz 9f                       # closed meanwhile: the next frame ends the list
    # after parts, the query's caps count the rest too (query_final_room)
    mov qword ptr [rip + cp_room], -1
    cmp dword ptr [rsp + 12], 0
    je 41f
    call query_final_room
    mov [rip + cp_room], rax
    cmp r15, rdx
    jbe 41f
    mov rdi, rbx
    mov esi, PK_COMPLETE
    call query_dropped
    jmp 9f
41: mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, [rsp + 16]
    mov r8d, [rsp + 12]         # after parts: the rest joins them
    call cp_merge_mode
    test rax, rax
    jns 9f
    mov rdi, rbx
    mov esi, PK_COMPLETE
    call query_dropped
    jmp 9f
5:  mov eax, [rsp + 8]
    cmp eax, [rip + sg_session]
    jne 9f
    mov dword ptr [rip + sg_wait], 0
    mov rax, [rsp + 24]
    cmp rax, [rip + sg_language_revision]
    jne 9f
    call sg_doc_alive
    test eax, eax
    jz 9f
    cmp dword ptr [rsp], 0
    je 51f
    mov rdi, r14
    mov rsi, r15
    FEAT_TEST rbx, FEAT_SIGNATURE_LIST
    jz 50f
    call sgl_set
    jmp 52f
50: mov dword ptr [rip + sg_count], 0
    call sg_set
    jmp 52f
51: mov dword ptr [rip + sg_open], 0
52: # moved since it was asked: ask again from the frame, whatever this answer did
    mov rax, [rip + g_doc]
    cmp rax, [rip + sg_doc]
    jne 9f
    mov rcx, [rax + DOC_cur]
    cmp rcx, [rip + sg_cur]
    jne 53f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rip + sg_ver]
    je 9f
53: mov dword ptr [rip + sg_again], 1
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN complete_ext_gone(ext): an extension stopped: its requests and items go (no messages: this
# runs while processes are reaped)
FN complete_ext_gone
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rip + cp_reqs + VEC_len]
    jae 2f
    imul rax, r12, HR_SIZE
    add rax, [rip + cp_reqs + VEC_ptr]
    cmp [rax + HR_ext], rbx
    je 11f
    inc r12
    jmp 1b
11: mov rdi, r12
    call req_remove
    jmp 1b
2:  # Native choices own their text and are unrelated to this process.
    cmp dword ptr [rip + cp_source], CP_CHOICES
    je 3f
    # its items
    mov rdi, rbx
    call keep_others
    lea rdi, [rip + cp_new_items]
    lea rsi, [rip + cp_items]
    call swap24
    lea rdi, [rip + cp_new_bytes]
    lea rsi, [rip + cp_bytes]
    call swap24
    mov qword ptr [rip + cp_qo1], -1
    cmp dword ptr [rip + cp_open], 0
    je 3f
    call doc_alive
    test eax, eax
    jz 3f
    call cp_filter
3:  cmp [rip + sg_ext], rbx
    jne 9f
    mov dword ptr [rip + sg_open], 0
    mov dword ptr [rip + sg_wait], 0
    mov qword ptr [rip + sg_ext], 0
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# swap24(a, b): exchange two VEC or SB records
swap24:
    mov rax, [rdi]
    mov rcx, [rsi]
    mov [rdi], rcx
    mov [rsi], rax
    mov rax, [rdi + 8]
    mov rcx, [rsi + 8]
    mov [rdi + 8], rcx
    mov [rsi + 8], rax
    mov rax, [rdi + 16]
    mov rcx, [rsi + 16]
    mov [rdi + 16], rcx
    mov [rsi + 16], rax
    ret

# keep_others(ext): cp_new_items and cp_new_bytes get the items of every other extension
keep_others:
    PROLOGUE
    mov r14, rdi
    mov qword ptr [rip + cp_new_items + VEC_len], 0
    lea rdi, [rip + cp_new_bytes]
    call sb_clear
    xor ebx, ebx
1:  cmp rbx, [rip + cp_items + VEC_len]
    jae 9f
    imul r12, rbx, CI_SIZE
    add r12, [rip + cp_items + VEC_ptr]
    inc rbx
    cmp [r12 + CI_ext], r14
    je 1b
    lea rdi, [rip + cp_new_items]
    mov esi, CI_SIZE
    call vec_push
    mov r13, rax
    # the record, then its bytes at their new place
    mov rdi, r13
    mov rsi, r12
    mov edx, CI_SIZE
    call memcpy
    mov rax, [rip + cp_new_bytes + SB_len]
    mov [r13 + CI_off], rax
    mov edx, [r12 + CI_llen]
    add edx, [r12 + CI_ilen]
    add edx, [r12 + CI_dlen]
    add edx, [r12 + CI_xlen]
    mov rsi, [r12 + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    lea rdi, [rip + cp_new_bytes]
    call sb_push
    jmp 1b
9:  EPILOGUE

# cp_merge_mode(ext, body, len, req, append) -> rax the items taken, or -1 when the body breaks the
# rules (nothing changes): an extension's list replaces what it said before in this session, or
# (append 1: the parts of one answer after its first) joins it
cp_merge_mode:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov [rsp + 16], r8d
    call ext_is_visible
    test eax, eax
    jz 8f
    cmp r13, CP_BODY_MAX
    ja 8f
    xor eax, eax
    FEAT_TEST rbx, FEAT_COMPLETE_ITEMS
    setnz al
    mov [rip + cp_parse_lf], eax
    mov rdi, rbx
    cmp dword ptr [rsp + 16], 0
    je 1f
    xor edi, edi                # keep every item, its own too
1:  call keep_others
    mov rax, [rip + cp_new_items + VEC_len]
    mov [rsp + 24], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rsp]
    call cp_parse
    test eax, eax
    jz 8f
    mov [rsp + 8], edx
    mov rax, [rip + cp_new_items + VEC_len]
    sub rax, [rsp + 24]
    mov rcx, [rip + cp_room]    # past the query's cap: what fits is kept
    test rcx, rcx
    js 2f
    cmp rax, rcx
    jbe 2f
    sub rax, rcx
    sub [rip + cp_new_items + VEC_len], rax
    mov rax, rcx
2:  mov qword ptr [rip + cp_room], -1
    mov [rsp + 24], rax
    or [rip + cp_more], edx
    lea rdi, [rip + cp_new_items]
    lea rsi, [rip + cp_items]
    call swap24
    lea rdi, [rip + cp_new_bytes]
    lea rsi, [rip + cp_bytes]
    call swap24
    mov qword ptr [rip + cp_qo1], -1
    call cp_filter
    cmp dword ptr [rsp + 8], 0
    je 9f
    mov rax, [rip + cp_doc]
    mov rcx, [rax + DOC_cur]
    cmp rcx, [rsp]
    je 9f
    mov dword ptr [rip + cp_reask], 1   # cut short for what was typed before: ask again
9:  mov rax, [rsp + 24]
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# ---- the answer's parser: globals ps_ptr, ps_end, ps_lend ----

# ps_line() -> eax 1 with ps_lend at the LF ending the line from ps_ptr, 0 when there is none
FN ps_line
    mov rax, [rip + ps_ptr]
    mov rcx, [rip + ps_end]
1:  cmp rax, rcx
    jae 8f
    cmp byte ptr [rax], 10
    je 2f
    inc rax
    jmp 1b
2:  mov [rip + ps_lend], rax
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ps_word() -> rax ptr, rdx len of the next word of the line (rdx 0 at its end); moves past it and
# one space
FN ps_word
    mov rax, [rip + ps_ptr]
    mov rcx, [rip + ps_lend]
    mov rdx, rax
1:  cmp rdx, rcx
    jae 2f
    cmp byte ptr [rdx], ' '
    je 2f
    inc rdx
    jmp 1b
2:  mov r8, rdx
    sub rdx, rax
    cmp r8, rcx
    jae 3f
    inc r8                      # the space
3:  mov [rip + ps_ptr], r8
    ret

# ps_num() -> rax value, edx 1 when the next word is a number of at most 10 digits
FN ps_num
    push rbx
    call ps_word
    test rdx, rdx
    jz 8f
    cmp rdx, 10
    ja 8f
    mov rbx, rdx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    cmp rdx, rbx
    jne 8f
    mov edx, 1
    pop rbx
    ret
8:  xor eax, eax
    xor edx, edx
    pop rbx
    ret

# ps_snum() -> rax value (-1 allowed), edx 1 when the next word is one
ps_snum:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_lend]
    jae ps_num
    cmp byte ptr [rax], '-'
    jne ps_num
    inc qword ptr [rip + ps_ptr]
    push rbx
    call ps_num
    neg rax
    pop rbx
    ret

# ps_eol() -> eax 1 when the line is used up; ps_ptr moves past its LF
FN ps_eol
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_lend]
    jne 8f
    inc rax
    mov [rip + ps_ptr], rax
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ps_pos() -> rax the byte offset of the next two words LINE COL in the document as it was when
# asked (ps_doc now, less ps_delta from the request's line on: only typing at its cursor has
# happened since), or -1 when it is not in it
ps_pos:
    push rbx
    push r12
    push r13
    call ps_num
    test edx, edx
    jz 8f
    mov r12, rax
    call ps_num
    test edx, edx
    jz 8f
    mov r13, rax
    test r12, r12
    jz 8f
    test r13, r13
    jz 8f
    mov rbx, [rip + ps_doc]
    cmp r12, [rbx + DOC_nlines]
    ja 8f
    dec r12
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    push rax
    push rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    pop rcx
    pop rcx                     # the line's end
    cmp r12, [rip + ps_rline]
    jb 2f
    je 1f
    sub rax, [rip + ps_delta]   # past the request's line: the typing moved it
1:  sub rcx, [rip + ps_delta]
2:  lea rax, [rax + r13 - 1]
    cmp rax, rcx
    jg 8f
    # Check the character boundary in the live text, where positions after the request's
    # cursor moved with subsequent typing. Never split a UTF-8 sequence with an edit.
    mov r13, rax
    mov r12, rax
    cmp r12, [rip + ps_req]
    jb 3f
    add r12, [rip + ps_delta]
3:  mov rdi, rbx
    call doc_len
    cmp r12, rax
    ja 8f
    je 4f
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
4:  mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret
8:  mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

# req_coords(doc, req): ps_doc, ps_rline and ps_delta for positions asked at req
req_coords:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov [rip + ps_doc], rbx
    mov [rip + ps_req], r12
    mov rax, [rbx + DOC_cur]
    sub rax, r12
    mov [rip + ps_delta], rax
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]    # deleting in the word may put the old offset on the next line
    call doc_line_of
    mov [rip + ps_rline], rax
    pop r13
    pop r12
    pop rbx
    ret

# extra_ok(ptr, len) -> eax 1 when the bytes are whole records: a header line whose last word is a
# length of at most 10 digits, then that many bytes
extra_ok:
    PROLOGUE
    mov r12, rdi
    lea r13, [rdi + rsi]
1:  cmp r12, r13
    jae 8f
    mov rbx, r12
2:  cmp rbx, r13
    jae 9f
    cmp byte ptr [rbx], 10
    je 3f
    inc rbx
    jmp 2b
3:  mov r14, rbx
4:  cmp r14, r12
    je 5f
    cmp byte ptr [r14 - 1], ' '
    je 5f
    dec r14
    jmp 4b
5:  mov r15, rbx
    sub r15, r14
    jz 9f
    cmp r15, 10
    ja 9f
    mov rdi, r14
    mov rsi, r15
    call parse_u64
    cmp rdx, r15
    jne 9f
    lea rcx, [rbx + 1]
    mov rdx, r13
    sub rdx, rcx
    cmp rax, rdx
    ja 9f
    lea r12, [rcx + rax]
    jmp 1b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# one_line(ptr, len) -> eax 1 when the bytes hold no line break
one_line:
    test rsi, rsi
    jz 9f
    movzx eax, byte ptr [rdi]
    cmp eax, 10
    je 8f
    cmp eax, 13
    je 8f
    inc rdi
    dec rsi
    jmp one_line
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# cp_parse(ext, body, len, req) -> eax 1 with the items appended to cp_new_items/cp_new_bytes and
# edx MORE, or eax 0 (section 12b: "N MORE", then N items, each a header line and its bytes)
cp_parse:
    PROLOGUE 64
    mov [rsp], rdi              # ext
    mov [rsp + 8], rcx          # req
    mov [rsp + 56], rsi
    mov [rsp + 48], rdx
    mov rdi, [rip + cp_doc]
    mov rsi, rcx
    call req_coords
    mov rsi, [rsp + 56]
    mov [rip + ps_ptr], rsi
    add rsi, [rsp + 48]
    mov [rip + ps_end], rsi
    call ps_line
    test eax, eax
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    cmp rax, CP_MAX_ITEMS
    ja 8f
    mov r15, rax                # N
    call ps_num
    test edx, edx
    jz 8f
    cmp rax, 1
    ja 8f
    mov [rsp + 16], eax         # MORE
    call ps_eol
    test eax, eax
    jz 8f
.Lcpp_item:
    test r15, r15
    jz .Lcpp_end
    dec r15
    call ps_line
    test eax, eax
    jz 8f
    call ps_pos
    test rax, rax
    js 8f
    mov [rsp + 24], rax         # o1
    call ps_pos
    test rax, rax
    js 8f
    mov [rsp + 32], rax         # o2
    cmp rax, [rsp + 24]
    jb 8f
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call kind_of
    mov [rsp + 40], eax
    call ps_num
    test edx, edx
    jz 8f
    mov r12, rax                # label
    call ps_num
    test edx, edx
    jz 8f
    mov r13, rax                # insert
    call ps_num
    test edx, edx
    jz 8f
    mov r14, rax                # detail
    call ps_num
    test edx, edx
    jz 8f
    mov rbx, rax                # extra
    call ps_eol
    test eax, eax
    jz 8f
    # the bytes are there, the label and the detail are one line each
    mov rax, r12
    add rax, r13
    add rax, r14
    add rax, rbx
    mov rcx, [rip + ps_end]
    sub rcx, [rip + ps_ptr]
    cmp rax, rcx
    ja 8f
    mov [rsp + 48], rax
    mov rdi, [rip + ps_ptr]
    mov rsi, r12
    call one_line
    test eax, eax
    jz 8f
    mov rdi, [rip + ps_ptr]
    add rdi, r12
    add rdi, r13
    mov rsi, r14
    call one_line
    test eax, eax
    jz 8f
    mov rdi, [rip + ps_ptr]
    add rdi, r12
    add rdi, r13
    add rdi, r14
    mov rsi, rbx
    call extra_ok
    test eax, eax
    jz 8f
    # the record
    lea rdi, [rip + cp_new_items]
    mov esi, CI_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + CI_ext], rcx
    mov rcx, [rsp + 24]
    mov [rax + CI_o1], rcx
    mov rcx, [rsp + 32]
    mov [rax + CI_o2], rcx
    mov rcx, [rsp + 8]
    mov [rax + CI_req], rcx
    mov rcx, [rip + cp_new_bytes + SB_len]
    mov [rax + CI_off], rcx
    mov [rax + CI_llen], r12d
    mov [rax + CI_ilen], r13d
    mov [rax + CI_dlen], r14d
    mov [rax + CI_xlen], ebx
    mov ecx, [rsp + 40]
    mov [rax + CI_kind], ecx
    # complete-items: its serial, version, flags and replace range
    mov rcx, [rip + cp_parse_ver]
    mov [rax + CI_ver], rcx
    mov qword ptr [rax + CI_r2], -1
    inc dword ptr [rip + cp_serial]
    mov ecx, [rip + cp_serial]
    mov [rax + CI_serial], ecx
    cmp dword ptr [rip + cp_parse_lf], 0
    je 11f
    mov rdi, rax
    mov rsi, [rip + ps_ptr]
    add rsi, r12
    add rsi, r13
    add rsi, r14
    mov edx, ebx
    call ci_scan
11: lea rdi, [rip + cp_new_bytes]
    mov rsi, [rip + ps_ptr]
    mov rdx, [rsp + 48]
    call sb_push
    mov rax, [rsp + 48]
    add [rip + ps_ptr], rax
    jmp .Lcpp_item
.Lcpp_end:
    # exactly N items: nothing after them
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne 8f
    mov eax, 1
    mov edx, [rsp + 16]
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# kind_of(ptr, len) -> eax the kind's index (0, text, for one rhun does not know)
kind_of:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp ebx, CK_COUNT
    jae 8f
    lea rax, [rip + kind_names]
    mov rdx, [rax + rbx*8]
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 9f
    inc ebx
    jmp 1b
8:  xor ebx, ebx
9:  mov eax, ebx
    EPILOGUE

# ---------------- filtering ----------------

# item(i) -> rax CI*
item:
    imul rax, rdi, CI_SIZE
    add rax, [rip + cp_items + VEC_ptr]
    ret

# query_for(o1): cp_q and cp_qlen, the text from o1 to cp_doc's cursor (empty when the cursor is
# before it or the text is longer than CP_QMAX)
query_for:
    cmp dword ptr [rip + cp_source], CP_CHOICES
    jne 0f
    mov qword ptr [rip + cp_qlen], 0
    ret
0:  push rbx
    mov rax, [rip + cp_doc]
    mov rcx, [rax + DOC_cur]
    cmp rdi, [rip + cp_qo1]
    jne 1f
    cmp rcx, [rip + cp_qcur]
    je 9f
1:  mov [rip + cp_qo1], rdi
    mov [rip + cp_qcur], rcx
    mov qword ptr [rip + cp_qlen], 0
    sub rcx, rdi
    jbe 9f
    cmp rcx, CP_QMAX
    ja 9f
    mov [rip + cp_qlen], rcx
    mov rsi, rdi
    mov rdi, rax
    mov rdx, rcx
    lea rcx, [rip + cp_q]
    call doc_copy
9:  pop rbx
    ret

# cp_filter(): cp_shown from the items that match what was typed in the word, best first
cp_filter:
    PROLOGUE 32
    mov qword ptr [rip + cp_qo1], -1
    mov dword ptr [rip + cp_nshown], 0
    mov dword ptr [rip + cp_sel], 0
    mov dword ptr [rip + cp_top], 0
    mov r15, [rip + cp_doc]
    mov rax, [r15 + DOC_cur]
    mov [rsp], rax              # the cursor
    xor ebx, ebx
.Lcf_each:
    cmp rbx, [rip + cp_items + VEC_len]
    jae .Lcf_done
    mov rdi, rbx
    call item
    mov r12, rax
    mov rdi, [r12 + CI_o1]
    call query_for
    mov rdi, r12
    call item_match_text        # complete-items: its filter text, else its label
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + cp_q]
    mov rcx, [rip + cp_qlen]
    call fuzzy
    test eax, eax
    js .Lcf_next
    # into the best CP_SHOW, after those that score as high (the providers' order stays)
    mov r13d, eax
    xor ecx, ecx
3:  cmp ecx, [rip + cp_nshown]
    jae 4f
    lea rdx, [rip + cp_scores]
    cmp [rdx + rcx*4], r13d
    jl 4f
    inc ecx
    jmp 3b
4:  cmp ecx, CP_SHOW
    jae .Lcf_next
    # shift the rest down one (the last falls off when full)
    mov edx, [rip + cp_nshown]
    cmp edx, CP_SHOW
    jae 5f
    inc dword ptr [rip + cp_nshown]
    jmp 6f
5:  dec edx
6:  cmp edx, ecx
    jbe 7f
    lea r8, [rip + cp_shown]
    lea r9, [rip + cp_scores]
    mov eax, [r8 + rdx*4 - 4]
    mov [r8 + rdx*4], eax
    mov eax, [r9 + rdx*4 - 4]
    mov [r9 + rdx*4], eax
    dec edx
    jmp 6b
7:  lea r8, [rip + cp_shown]
    lea r9, [rip + cp_scores]
    mov [r8 + rcx*4], ebx
    mov [r9 + rcx*4], r13d
.Lcf_next:
    inc rbx
    jmp .Lcf_each
.Lcf_done:
    mov rax, [rsp]
    mov [rip + cp_seen_cur], rax
    mov rax, [r15 + DOC_version]
    mov [rip + cp_seen_ver], rax
    mov eax, 1
    cmp dword ptr [rip + cp_nshown], 0
    je 8f
    mov eax, 2
8:  mov [rip + cp_open], eax
    mov dword ptr [rip + cp_hover], -1
    mov dword ptr [rip + g_dirty], 1
    # complete-items: a preselected item that passed is selected first, and gets resolved
    xor ebx, ebx
81: cmp ebx, [rip + cp_nshown]
    jae 83f
    lea rax, [rip + cp_shown]
    mov edi, [rax + rbx*4]
    call item
    test dword ptr [rax + CI_flags], CF_PRESELECT
    jnz 82f
    inc ebx
    jmp 81b
82: mov edi, ebx
    call cp_select
83: call res_schedule
    EPILOGUE

# cp_check(): each frame: the list follows the word being typed; moving away, a selection, an
# edit elsewhere or another document ends it
cp_check:
    PROLOGUE
    cmp dword ptr [rip + cp_source], CP_CHOICES
    jne 0f
    call cp_choice_check
    test rax, rax
    jz 7f
    jmp 9f
0:  cmp dword ptr [rip + cp_open], 0
    je 9f
    call focused_doc
    test rax, rax
    jz 7f
    mov rbx, rax
    cmp rbx, [rip + cp_doc]
    jne 7f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + cp_doc_id]
    jne 7f
    call doc_alive
    test eax, eax
    jz 7f
    mov rdi, rbx
    call ed_sel
    cmp rax, rdx
    jne 7f
    mov r12, [rbx + DOC_cur]
    cmp r12, [rip + cp_start]
    jb 7f
    mov rdi, rbx
    call doc_len
    sub rax, r12
    cmp rax, [rip + cp_tail]
    jne 7f
    # only word characters between the word's start and the cursor
    mov r13, [rip + cp_start]
1:  cmp r13, r12
    jae 2f
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    mov edi, eax
    call is_word
    test eax, eax
    jz 7f
    inc r13
    jmp 1b
2:  # what was typed since it was filtered: every edit since started in the word
    cmp r12, [rip + cp_seen_cur]
    jne 3f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + cp_seen_ver]
    je 4f
3:  mov rax, [rbx + DOC_version]
    cmp rax, [rip + cp_seen_ver]
    je 31f
    mov rax, [rip + g_edit_lo]
    cmp rax, [rip + cp_start]
    jb 7f
    cmp qword ptr [rip + g_edit_hi], r12
    ja 7f
31: mov qword ptr [rip + g_edit_lo], -1
    mov qword ptr [rip + g_edit_hi], 0
    call cp_filter
    cmp dword ptr [rip + cp_more], 0
    je 4f
    mov dword ptr [rip + cp_reask], 1
4:  # a list cut short is asked for again, once nothing is out for this session
    cmp dword ptr [rip + cp_reask], 0
    je 9f
    xor ecx, ecx
5:  cmp rcx, [rip + cp_reqs + VEC_len]
    jae 6f
    imul rax, rcx, HR_SIZE
    add rax, [rip + cp_reqs + VEC_ptr]
    inc rcx
    cmp dword ptr [rax + HR_kind], HR_COMPLETE
    jne 5b
    jmp 9f
6:  mov dword ptr [rip + cp_reask], 0
    mov dword ptr [rip + cp_more], 0
    lea rdi, [rip + .Lk_incomplete]
    mov esi, '-'
    xor edx, edx
    call ask
    jmp 9f
7:  call cp_close
9:  EPILOGUE

# ---------------- signature help ----------------

# Automatic signature help resolves quietly. Explicit requests use the provider chooser.
sig_provider:
    push rbx
    call focused_doc
    test rax, rax
    jz 9f
    mov rsi, rax
    mov edi, 7
    call ext_provider_running
9:  pop rbx
    ret

# sig_active_provider() -> the current session's provider, validated without rerouting it.
sig_active_provider:
    PROLOGUE
    call focused_doc
    test rax, rax
    jz 8f
    cmp rax, [rip + sg_doc]
    jne 8f
    mov rcx, [rax + DOC_id]
    cmp rcx, [rip + sg_doc_id]
    jne 8f
    call sg_doc_alive
    test eax, eax
    jz 8f
    mov rax, [rip + sg_doc]
    mov rbx, [rip + sg_ext]
    test rbx, rbx
    jz 8f
    mov rdi, rbx
    mov esi, 7
    mov rdx, rax
    call ext_provider_supports
    test eax, eax
    jz 8f
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sig_trigger(ch): a typed character that is one of the provider's triggers asks
sig_trigger:
    PROLOGUE
    mov r12d, edi
    mov eax, [rip + sg_open]
    or eax, [rip + sg_wait]
    or eax, [rip + sg_again]
    jz 1f
    call sig_active_provider
    test rax, rax
    jnz 2f
    call sg_close
    jmp 9f
1:  call sig_provider
2:
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov esi, EXT_pv_strig
    call ext_pv
    mov rdi, rax
    mov esi, r12d
    call trig_has
    test eax, eax
    jz 9f
    mov rdi, rbx
    lea rsi, [rip + .Lk_trigger]
    mov edx, r12d
    call sig_ask
9:  EPILOGUE

# sig_ask(ext, kind, ch): "ID signature DOC VERSION LINE COL KIND CHAR"
sig_ask:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call ext_is_visible
    test eax, eax
    jz 9f
    call focused_doc
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, r14
    call doc_sync_grammar
    test rax, rax
    js 9f
    mov rax, [r14 + DOC_language_revision]
    test rax, rax
    jz 9f
    mov [rip + sg_language_revision], rax
    cmp qword ptr [rip + cp_reqs + VEC_len], HR_MAX
    jae 9f
    # a new help (not an update) starts a session: answers for older ones are dropped
    lea rdi, [rip + .Lk_update]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 1f
    mov edi, HR_SIGNATURE
    call cancel_kind
    inc dword ptr [rip + sg_session]
1:  mov [rip + sg_ext], rbx
    mov [rip + sg_doc], r14
    mov rax, [r14 + DOC_id]
    mov [rip + sg_doc_id], rax
    mov rax, [r14 + DOC_cur]
    mov [rip + sg_cur], rax
    mov rax, [r14 + DOC_version]
    mov [rip + sg_ver], rax
    mov dword ptr [rip + sg_again], 0
    mov rdi, rbx
    lea rsi, [rip + .Lv_signature]
    FEAT_TEST rbx, FEAT_SIGNATURE_LIST
    jz 2f
    lea rsi, [rip + .Lv_signatures]   # signature-list: every overload
2:  mov rdx, r14
    mov rcx, r12
    mov r8d, r13d
    call extproto_host_request
    test rax, rax
    jz 9f
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    mov edx, PK_SIGNATURE
    mov ecx, QO_COMPLETE
    call query_track
    lea rdi, [rip + cp_reqs]
    mov esi, HR_SIZE
    call vec_push
    mov [rax + HR_ext], rbx
    mov [rax + HR_id], r15
    mov dword ptr [rax + HR_kind], HR_SIGNATURE
    mov ecx, [rip + sg_session]
    mov [rax + HR_session], ecx
    mov rcx, [r14 + DOC_cur]
    mov [rax + HR_req], rcx
    mov rcx, [r14 + DOC_language_revision]
    mov [rax + HR_language_revision], rcx
    mov dword ptr [rip + sg_wait], 1
9:  EPILOGUE

# FN cmd_signature_help(): ctrl+shift+space
FN cmd_signature_help
    push rbx
    call sg_close
    mov edi, 7
    xor esi, esi
    call ext_provider_begin
    pop rbx
    ret

FN complete_signature_start
    lea rsi, [rip + .Lk_invoked]
    mov edx, '-'
    jmp sig_ask

# sg_set(body, len): "FROM TO", the signature, the documentation; an empty body hides it
sg_set:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    test r13, r13
    jz 8f
    cmp r13, SG_BODY_MAX
    ja 8f
    mov [rip + ps_ptr], r12
    lea rax, [r12 + r13]
    mov [rip + ps_end], rax
    call ps_line
    test eax, eax
    jz 8f
    call ps_snum
    test edx, edx
    jz 8f
    mov r14, rax
    call ps_snum
    test edx, edx
    jz 8f
    mov r15, rax
    call ps_eol
    test eax, eax
    jz 8f
    # the signature: up to the next LF or the end
    mov rbx, [rip + ps_ptr]
    mov rcx, rbx
1:  cmp rcx, [rip + ps_end]
    jae 2f
    cmp byte ptr [rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  sub rcx, rbx
    mov [rip + sg_siglen], rcx
    # the active parameter within it, or none
    cmp r14, 0
    jl 3f
    cmp r15, r14
    jl 3f
    cmp r15, rcx
    jg 3f
    mov [rip + sg_from], r14d
    mov [rip + sg_to], r15d
    jmp 4f
3:  mov dword ptr [rip + sg_from], -1
    mov dword ptr [rip + sg_to], -1
4:  lea rdi, [rip + sg_text]
    call sb_clear
    lea rdi, [rip + sg_text]
    mov rsi, rbx
    mov rdx, [rip + ps_end]
    sub rdx, rbx
    call sb_push
    mov dword ptr [rip + sg_open], 1
    EPILOGUE
8:  mov dword ptr [rip + sg_open], 0
    EPILOGUE

# sg_check(): each frame: help that shows follows edits and the cursor (an update request when
# nothing is out); another document or tab hides it
sg_check:
    PROLOGUE
    mov eax, [rip + sg_open]
    or eax, [rip + sg_wait]
    or eax, [rip + sg_again]
    jz 9f
    call focused_doc
    test rax, rax
    jz 7f
    mov rbx, rax
    cmp rbx, [rip + sg_doc]
    jne 7f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + sg_doc_id]
    jne 7f
    call sg_doc_alive
    test eax, eax
    jz 7f
    mov rax, [rip + sg_ext]
    test rax, rax
    jz 7f
    call sig_active_provider
    test rax, rax
    jz 7f
    cmp dword ptr [rip + sg_wait], 0
    jne 9f                      # asked: the answer says what comes next
    cmp dword ptr [rip + sg_open], 0
    jne 51f
    cmp dword ptr [rip + sg_again], 0
    je 9f
51: mov rax, [rbx + DOC_cur]
    cmp rax, [rip + sg_cur]
    jne 1f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + sg_ver]
    je 9f
1:  cmp dword ptr [rip + sg_wait], 0
    jne 9f                      # asked when the answer comes (sg_cur still differs)
    mov rdi, [rip + sg_ext]
    lea rsi, [rip + .Lk_update]
    mov edx, '-'
    call sig_ask
    jmp 9f
7:  call sg_close
9:  EPILOGUE

# sg_close(): the help goes
sg_close:
    push rbx
    mov dword ptr [rip + sg_count], 0
    mov dword ptr [rip + sg_open], 0
    mov dword ptr [rip + sg_wait], 0
    mov dword ptr [rip + sg_again], 0
    mov dword ptr [rip + sg_rect + 12], 0
    mov edi, HR_SIGNATURE
    call cancel_kind
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# ---------------- keys and accepting ----------------

# FN complete_key(keysym, cp, mods) -> eax 1 when the list or the help took the key
FN complete_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    # complete-items: an accept waiting for its item's resolve goes ahead at the next key; Enter
    # or Tab again is taken, anything else then does what it does
    cmp dword ptr [rip + cp_wait_serial], 0
    je 0f
    call cp_wait_accept
    cmp r12d, KEY_RETURN
    je 9f
    cmp r12d, KEY_KP_ENTER
    je 9f
    cmp r12d, KEY_TAB
    je 9f
    jmp 8f
0:  cmp dword ptr [rip + cp_source], CP_CHOICES
    jne .Lcpk_ordinary
    call cp_choice_check
    test rax, rax
    jnz .Lcpk_choice
    call cp_close
    jmp .Lcpk_ordinary
.Lcpk_choice:
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .Lcpk_close_choice
    cmp r12d, KEY_ISO_LEFT_TAB
    je .Lcpk_previous
    cmp r12d, KEY_TAB
    jne 0f
    test r14d, MOD_SHIFT
    jnz .Lcpk_previous
0:  test r14d, MOD_SHIFT
    jnz .Lcpk_close_choice
    cmp r12d, KEY_UP
    je .Lcpk_ordinary
    cmp r12d, KEY_DOWN
    je .Lcpk_ordinary
    cmp r12d, KEY_PAGEUP
    je .Lcpk_ordinary
    cmp r12d, KEY_PAGEDOWN
    je .Lcpk_ordinary
    cmp r12d, KEY_RETURN
    je .Lcpk_ordinary
    cmp r12d, KEY_KP_ENTER
    je .Lcpk_ordinary
    cmp r12d, KEY_TAB
    je .Lcpk_ordinary
    cmp r12d, KEY_ESCAPE
    je .Lcpk_ordinary
.Lcpk_close_choice:
    call cp_close
    jmp 8f
.Lcpk_previous:
    mov rbx, [rip + cp_doc]
    call cp_close
    mov rdi, rbx
    mov esi, -1
    call snippet_step
    jmp 9f
.Lcpk_ordinary:
    # complete-items: shift+Enter uses the other range; a commit character of the selected item
    # accepts it, and the character is typed after it
    cmp dword ptr [rip + cp_source], CP_CHOICES
    je .Lcpk_plain
    cmp dword ptr [rip + cp_rect + 12], 0
    je .Lcpk_plain
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .Lcpk_plain
    cmp r14d, MOD_SHIFT
    jne .Lcpk_commit
    cmp r12d, KEY_RETURN
    je 0f
    cmp r12d, KEY_KP_ENTER
    jne .Lcpk_commit
0:  mov edi, [rip + cfg_complete_replace]
    xor edi, 1
    call cp_accept_key
    jmp 9f
.Lcpk_commit:
    cmp dword ptr [rip + cfg_complete_commit], 0
    je .Lcpk_plain
    cmp r13d, 0x21
    jb .Lcpk_plain
    cmp r13d, 0x7e
    ja .Lcpk_plain
    call selected_item
    test rax, rax
    jz .Lcpk_plain
    test dword ptr [rax + CI_flags], CF_COMMIT
    jz .Lcpk_plain
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + .Lx_commit]
    call item_record
    test rax, rax
    jz .Lcpk_plain
1:  test rdx, rdx
    jz .Lcpk_plain
    dec rdx
    movzx ecx, byte ptr [rax + rdx]
    cmp ecx, r13d
    jne 1b
    mov eax, [rbx + CI_flags]
    and eax, CF_RESOLVE_EDITS | CF_RESOLVED
    cmp eax, CF_RESOLVE_EDITS
    jne 2f
    mov [rip + cp_wait_char], r13d  # it waits for its resolve; the character follows the accept
    mov edi, [rip + cfg_complete_replace]
    call cp_accept_key
    jmp 9f
2:  call cp_accept
    jmp 8f                      # the editor types the character
.Lcpk_plain:
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER | MOD_SHIFT
    jnz 8f
    # Escape withdraws what was asked and not shown yet, and leaves the key to the editor
    cmp r12d, KEY_ESCAPE
    jne 71f
    cmp dword ptr [rip + cp_rect + 12], 0
    jne 71f
    mov eax, [rip + cp_open]
    or rax, [rip + cp_due]
    jz 72f
    call cp_close
72: cmp dword ptr [rip + sg_open], 0
    jne 71f
    mov eax, [rip + sg_wait]
    or eax, [rip + sg_again]
    jz 8f
    call sg_close
    jmp 8f
71:
    cmp dword ptr [rip + cp_open], 2
    jne 7f
    mov ebx, [rip + cp_nshown]
    test ebx, ebx
    jz 7f
    cmp dword ptr [rip + cp_rect + 12], 0
    je 7f                       # not on screen: the editor has the keys
    mov eax, [rip + cp_sel]
    cmp r12d, KEY_UP
    jne 1f
    dec eax
    jns 6f
    lea eax, [rbx - 1]
    jmp 6f
1:  cmp r12d, KEY_DOWN
    jne 2f
    inc eax
    cmp eax, ebx
    jb 6f
    xor eax, eax
    jmp 6f
2:  cmp r12d, KEY_PAGEUP
    jne 3f
    sub eax, CP_ROWS
    jns 6f
    xor eax, eax
    jmp 6f
3:  cmp r12d, KEY_PAGEDOWN
    jne 4f
    add eax, CP_ROWS
    cmp eax, ebx
    jb 6f
    lea eax, [rbx - 1]
    jmp 6f
4:  cmp r12d, KEY_RETURN
    je 41f
    cmp r12d, KEY_KP_ENTER
    je 41f
    cmp r12d, KEY_TAB
    jne 5f
41: cmp dword ptr [rip + cp_source], CP_CHOICES
    jne 42f
    xor edi, edi
    cmp r12d, KEY_TAB
    sete dil
    call cp_choice_accept
    jmp 9f
42: mov edi, [rip + cfg_complete_replace]
    call cp_accept_key
    jmp 9f
5:  cmp r12d, KEY_ESCAPE
    jne 7f
    call cp_close
    jmp 9f
6:  mov edi, eax
    call cp_select
    jmp 9f
7:  cmp r12d, KEY_ESCAPE
    jne 71f
    cmp dword ptr [rip + sg_open], 0
    je 8f
    call sg_close
    jmp 9f
71: # signature-list: Up and Down switch overloads while help with several shows
    cmp dword ptr [rip + sg_open], 0
    je 8f
    cmp dword ptr [rip + sg_count], 1
    jbe 8f
    mov eax, [rip + sg_index]
    cmp r12d, KEY_UP
    jne 72f
    dec eax
    jns 73f
    mov eax, [rip + sg_count]
    dec eax
    jmp 73f
72: cmp r12d, KEY_DOWN
    jne 8f
    inc eax
    cmp eax, [rip + sg_count]
    jb 73f
    xor eax, eax
73: mov edi, eax
    call sgl_show
    jmp 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# cp_select(row): the selection moves there, the rows scroll to show it
cp_select:
    mov [rip + cp_sel], edi
    cmp edi, [rip + cp_top]
    jge 1f
    mov [rip + cp_top], edi
1:  mov eax, [rip + cp_top]
    add eax, CP_ROWS
    cmp edi, eax
    jl 2f
    lea eax, [rdi - CP_ROWS + 1]
    mov [rip + cp_top], eax
2:  mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rip + cp_source], CP_CHOICES
    je 3f
    jmp res_schedule            # complete-items: the newly selected item is resolved
3:  ret

# cp_accept_key(replace): Enter or Tab: an item whose resolve answer may add edits (an import)
# waits for it, up to CP_WAIT_MS (the tick, or the next key, accepts); others go in at once
cp_accept_key:
    push rbx
    mov ebx, edi
    cmp dword ptr [rip + cp_source], CP_CHOICES
    je 8f
    call selected_item
    test rax, rax
    jz 8f
    mov ecx, [rax + CI_flags]
    and ecx, CF_RESOLVE_EDITS | CF_RESOLVED
    cmp ecx, CF_RESOLVE_EDITS
    jne 8f
    mov ecx, [rax + CI_serial]
    mov [rip + cp_wait_serial], ecx
    mov [rip + cp_wait_replace], ebx
    mov dword ptr [rip + cp_wait_ready], 0
    push rax
    push rax
    call time_ms
    add rax, CP_WAIT_MS
    mov [rip + cp_wait_until], rax
    pop rdi
    pop rdi
    call res_send               # unless it is out already
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret
8:  mov esi, ebx
    pop rbx
    jmp cp_accept_mode

# cp_accept(): the selected item goes in over its insert range (its replace range with
# [editor] complete_replace); cp_accept_mode(replace) chooses
cp_accept:
    mov esi, [rip + cfg_complete_replace]
cp_accept_mode:
    cmp dword ptr [rip + cp_source], CP_CHOICES
    jne 0f
    xor edi, edi
    jmp cp_choice_accept
0:  push rsi
    push rsi
    call selected_item
    pop rsi
    pop rsi
    test rax, rax
    jz cp_close
    mov rdi, rax

# cp_accept_ci(CI*, replace): the item goes in: its range (insert, or replace when it has one and
# replace is 1), extended to the cursor by what was typed since, and its extra edits, as one undo
# step; then what its after records ask for
cp_accept_ci:
    PROLOGUE 160
    mov qword ptr [rsp + 96], 0   # validated snippet candidate, owned until attached
    mov r12, rdi
    mov [rsp + 128], esi        # the replace range
    mov qword ptr [rsp + 152], 0    # its flags once it went in (after signature, after complete)
    mov eax, [r12 + CI_ilen]
    mov [rsp + 136], rax        # the text's length (adjust may change it)
    mov qword ptr [rsp + 144], 0    # the indentation adjust adds to each later line
    mov rdi, [r12 + CI_ext]
    call ext_is_visible
    test eax, eax
    jz 8f
    call focused_doc
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp rbx, [rip + cp_doc]
    jne 8f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + cp_doc_id]
    jne 8f
    call doc_alive
    test eax, eax
    jz 8f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 8f
    mov r13, [rbx + DOC_cur]
    mov rax, r13
    sub rax, [r12 + CI_req]
    mov [rsp], rax              # typed since it was asked for
    # the item's range
    mov r14, [r12 + CI_o1]
    mov r15, [r12 + CI_o2]
    cmp dword ptr [rsp + 128], 0
    je 0f
    test dword ptr [r12 + CI_flags], CF_REPLACE
    jz 0f
    mov r15, [r12 + CI_r2]
0:  cmp r15, [r12 + CI_req]
    jb 1f
    add r15, [rsp]
1:  cmp r15, r13
    jae 2f
    mov r15, r13
2:  mov rdi, rbx
    call doc_len
    cmp r15, rax
    jbe 3f
    mov r15, rax
3:  cmp r14, r15
    ja 8f
    # the edits: the item's first, then its extra ones that touch none of those before
    mov qword ptr [rip + ae_n], 0
    mov rax, [r12 + CI_off]
    add rax, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add rax, rcx                # the insert text
    mov [rsp + 64], rax         # the item's text, to know its record after sorting
    # complete-items adjust: the lines after the first get the insertion line's indentation
    # (not for snippet fields, whose offsets the text keeps)
    test dword ptr [r12 + CI_flags], CF_ADJUST
    jz 0f
    mov rdi, r12
    lea rsi, [rip + .Lx_field]
    call item_record
    test rax, rax
    jnz 0f
    mov rax, [r12 + CI_off]     # item_record used the parser: the text again
    add rax, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add rax, rcx
    mov [rsp + 64], rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [rsp + 64]
    mov ecx, [r12 + CI_ilen]
    call cp_adjust
    mov [rsp + 64], rax
    mov [rsp + 136], rdx
    mov [rsp + 144], rcx
0:  mov rdi, r14
    mov rsi, r15
    mov rdx, [rsp + 64]
    mov rcx, [rsp + 136]
    call ae_add
    mov rax, [r12 + CI_off]
    add rax, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add rax, rcx
    mov ecx, [r12 + CI_ilen]
    add rax, rcx
    mov ecx, [r12 + CI_dlen]
    add rax, rcx
    mov [rip + ps_ptr], rax
    mov ecx, [r12 + CI_xlen]
    add rax, rcx
    mov [rip + ps_end], rax
    mov rax, [r12 + CI_ext]
    FEAT_TEST rax, FEAT_SNIPPETS
    jz .Lcpa_no_fields
    mov rdi, [rsp + 64]
    mov esi, [r12 + CI_ilen]
    mov rdx, [rip + ps_ptr]
    mov ecx, [r12 + CI_xlen]
    xor r8d, r8d
    mov rax, [r12 + CI_ext]
    mov r9d, [rax + EXT_features]
    call snippet_decode_fields
    mov [rsp + 96], rax
.Lcpa_no_fields:
    mov rdi, rbx
    mov rsi, [r12 + CI_req]
    call req_coords
    mov qword ptr [rsp + 72], -1    # the cursor's offset in the item's text: none (at its end)
4:  call ps_line
    test eax, eax
    jz 5f
    call ps_word
    mov [rsp + 80], rax
    mov [rsp + 88], rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lx_edit]
    call str_eq_cstr
    test eax, eax
    jz 40f
    call ps_pos
    mov [rsp + 8], rax
    call ps_pos
    mov [rsp + 16], rax
    call ps_num
    test edx, edx
    jz 5f
    mov [rsp + 24], rax
    call ps_eol
    test eax, eax
    jz 5f
    mov rcx, [rip + ps_end]
    sub rcx, [rip + ps_ptr]
    cmp [rsp + 24], rcx
    ja 5f
    mov rax, [rip + ps_ptr]
    mov [rsp + 32], rax         # its text
    mov rcx, [rsp + 24]
    add [rip + ps_ptr], rcx
    # positions that are there, after the cursor moved by what was typed
    mov rdi, [rsp + 8]
    test rdi, rdi
    js 4b
    mov rsi, [rsp + 16]
    test rsi, rsi
    js 4b
    cmp rdi, [r12 + CI_req]
    jb 42f
    add rdi, [rsp]
42: cmp rsi, [r12 + CI_req]
    jb 43f
    add rsi, [rsp]
43: cmp rdi, rsi
    ja 4b
    mov [rsp + 8], rdi
    mov [rsp + 16], rsi
    mov rdi, rbx
    call doc_len
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    cmp rsi, rax
    ja 4b                       # not in the document as it is
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 24]
    call ae_add
    jmp 4b
40: # cursor OFFSET 0: where the cursor goes in the item's text
    mov rdi, [rsp + 80]
    mov rsi, [rsp + 88]
    lea rdx, [rip + .Lx_cursor]
    call str_eq_cstr
    test eax, eax
    jz 41f
    call ps_num
    test edx, edx
    jz 5f
    mov [rsp + 48], rax
    call ps_num
    test edx, edx
    jz 5f
    test rax, rax
    jnz 5f                      # no bytes follow it
    call ps_eol
    test eax, eax
    jz 5f
    mov rax, [rsp + 48]
    mov ecx, [r12 + CI_ilen]
    cmp rax, rcx
    ja 4b                       # past the text: left out
    jae 401f
    mov rdx, [rsp + 64]
    movzx edx, byte ptr [rdx + rax]
    and edx, 0xc0
    cmp edx, 0x80
    je 4b                       # inside a character: left out
401:mov [rsp + 72], rax
    jmp 4b
41: # another record: its last word is its length
    mov rax, [rip + ps_lend]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 56], 0
44: call ps_word
    test rdx, rdx
    jz 45f
    mov [rsp + 56], rax
    mov [rsp + 48], rdx
    jmp 44b
45: mov rdi, [rsp + 56]
    test rdi, rdi
    jz 5f
    mov rsi, [rsp + 48]
    call parse_u64
    cmp rdx, [rsp + 48]
    jne 5f
    mov rcx, [rsp + 40]
    inc rcx
    add rcx, rax
    cmp rcx, [rip + ps_end]
    ja 5f
    mov [rip + ps_ptr], rcx
    jmp 4b
5:  # Preserve the main insertion line before any additional edits move it.
    mov rsi, [rsp + 96]
    test rsi, rsi
    jz .Lcpa_indent_done
    cmp qword ptr [rsi + SN_transform], 0
    je .Lcpa_indent_done
    mov rdi, rbx
    mov rdx, r14
    call snippet_capture_indent
    test eax, eax
    jnz .Lcpa_indent_done
    mov rdi, [rsp + 96]
    mov qword ptr [rsp + 96], 0
    call snippet_free_node
.Lcpa_indent_done:
    # From the last to the first, so each edit's offsets hold when it is made.
    call ae_sort
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 112], rax
    mov rdx, -1
    xor ecx, ecx
    xor r8d, r8d
.Lcpa_bounds:
    cmp r8, [rip + ae_n]
    jae .Lcpa_scope
    imul rax, r8, 32
    lea rdi, [rip + ae_list]
    add rax, rdi
    cmp [rax], rdx
    cmovb rdx, [rax]
    cmp [rax + 8], rcx
    cmova rcx, [rax + 8]
    inc r8
    jmp .Lcpa_bounds
.Lcpa_scope:
    mov rdi, rbx
    mov rsi, [rsp + 96]
    call snippet_insertion_begin
    mov rdi, rbx
    call doc_begin_group
    xor r13d, r13d
6:  cmp r13, [rip + ae_n]
    jae 7f
    imul rax, r13, 32
    lea rcx, [rip + ae_list]
    add rax, rcx
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [rax]
    mov rdx, [rax + 8]
    call snippet_replace_range
    mov rax, [rsp + 8]
    mov rdx, [rax + 8]
    sub rdx, [rax]
    jz 61f
    mov rdi, rbx
    mov rsi, [rax]
    mov ecx, EK_OTHER
    call doc_delete
61: mov rax, [rsp + 8]
    mov rcx, [rax + 24]
    test rcx, rcx
    jz 62f
    mov rdi, rbx
    mov rsi, [rax]
    mov rdx, [rax + 16]
    mov r8d, EK_OTHER
    call doc_insert
62: mov rdi, rbx
    call snippet_replace_done
    inc r13
    jmp 6b
7:  mov rdi, rbx
    call doc_end_group
    # the cursor after the item's text, moved by the edits made before it
    mov rax, [rsp + 136]
    lea r13, [r14 + rax]
    xor ecx, ecx
71: cmp rcx, [rip + ae_n]
    jae 72f
    imul rax, rcx, 32
    lea rdx, [rip + ae_list]
    add rax, rdx
    inc rcx
    cmp [rax], r14
    jb 73f
    ja 71b
    mov rdx, [rax + 16]         # at the item's start: an insert there that is not the item
    cmp rdx, [rsp + 64]
    je 71b
    mov rdx, [rax + 8]
    cmp rdx, [rax]
    jne 71b
73: add r13, [rax + 24]
    add r13, [rax]
    sub r13, [rax + 8]
    jmp 71b
72: mov rax, [rsp + 136]
    mov rcx, r13
    sub rcx, rax
    mov [rsp + 104], rcx        # actual inserted start after earlier additional edits
    mov rax, [rsp + 72]
    test rax, rax
    js 74f
    mov rcx, [rsp + 136]        # a cursor record: that far into the item's text
    sub r13, rcx
    cmp qword ptr [rsp + 144], 0
    je 73f
    # adjusted: the indentation added before it moves it on
    mov rdx, rax
    xor r8d, r8d
    mov r9, [r12 + CI_off]
    add r9, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add r9, rcx
75: test rdx, rdx
    jz 76f
    dec rdx
    cmp byte ptr [r9 + rdx], 10
    jne 75b
    add r8, [rsp + 144]
    jmp 75b
76: add rax, r8
73: add r13, rax
74: mov [rbx + DOC_cur], r13
    mov [rbx + DOC_anchor], r13
    mov rdi, rbx
    mov rsi, [rsp + 104]
    call snippet_insertion_finish
    mov [rsp + 104], rax
    cmp qword ptr [rsp + 96], 0
    je .Lcpa_attached
    mov rdi, rbx
    mov rsi, [rsp + 96]
    mov rdx, [rsp + 104]
    mov qword ptr [rsp + 96], 0
    call snippet_push
    mov rdi, rbx
    mov rsi, [rsp + 112]
    call snippet_record_after
.Lcpa_attached:
    call ed_touch
    mov eax, [r12 + CI_flags]
    mov [rsp + 152], rax
8:  mov rdi, [rsp + 96]
    call snippet_free_node
    call cp_close
    # complete-items: after signature asks for signature help, after complete for a new list
    test dword ptr [rsp + 152], CF_AFTER_COMPLETE
    jz 81f
    lea rdi, [rip + .Lk_invoked]
    mov esi, '-'
    xor edx, edx
    call cp_begin
81: test dword ptr [rsp + 152], CF_AFTER_SIG
    jz 82f
    call sig_provider
    test rax, rax
    jz 82f
    mov rdi, rax
    lea rsi, [rip + .Lk_invoked]
    mov edx, '-'
    call sig_ask
82: EPILOGUE

# cp_adjust(doc, pos, text, len) -> rax the text with the indentation of the line at pos after each
# of its line breaks (in cp_adj), rdx its length, rcx the indentation's length
cp_adjust:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rdi, [rip + cp_adj]
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r15, rax                # the line's start; its indentation runs to the first other byte
    xor r12d, r12d
1:  lea rsi, [r15 + r12]
    mov rdi, rbx
    push rsi
    push rsi
    call doc_len
    pop rsi
    pop rsi
    cmp rsi, rax
    jae 2f
    mov rdi, rbx
    call doc_byte
    cmp eax, ' '
    je 11f
    cmp eax, 9
    jne 2f
11: inc r12
    cmp r12, 256
    jb 1b
2:  xor ecx, ecx                # the text, the indentation after each LF
3:  cmp rcx, r14
    jae 5f
    push rcx
    push rcx
    lea rdi, [rip + cp_adj]
    movzx esi, byte ptr [r13 + rcx]
    call sb_push_byte
    pop rcx
    pop rcx
    cmp byte ptr [r13 + rcx], 10
    jne 4f
    push rcx
    push rcx
    lea rdi, [rip + cp_adj]
    mov rsi, r12
    call sb_reserve
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, rax
    call doc_copy
    add [rip + cp_adj + SB_len], r12
    pop rcx
    pop rcx
4:  inc rcx
    jmp 3b
5:  mov rax, [rip + cp_adj + SB_ptr]
    mov rdx, [rip + cp_adj + SB_len]
    mov rcx, r12
    EPILOGUE

# ae_add(start, end, ptr, len): one edit of the item being accepted, unless it overlaps one before
ae_add:
    mov rax, [rip + ae_n]
    cmp rax, AE_MAX
    jae 9f
    xor r8d, r8d
1:  cmp r8, rax
    jae 2f
    imul r9, r8, 32
    lea r10, [rip + ae_list]
    add r9, r10
    inc r8
    # overlapping unless one ends where (or before) the other starts
    cmp rsi, [r9]
    jbe 1b
    cmp rdi, [r9 + 8]
    jae 1b
    ret
2:  imul r9, rax, 32
    lea r10, [rip + ae_list]
    add r9, r10
    mov [r9], rdi
    mov [r9 + 8], rsi
    mov [r9 + 16], rdx
    mov [r9 + 24], rcx
    inc qword ptr [rip + ae_n]
9:  ret

# ae_sort(): last position first, with replacements before insertions at the same start
ae_sort:
    mov rcx, 1
1:  cmp rcx, [rip + ae_n]
    jae 9f
    mov rdx, rcx
2:  test rdx, rdx
    jz 3f
    imul r8, rdx, 32
    lea r9, [rip + ae_list]
    add r8, r9
    mov rax, [r8]
    cmp rax, [r8 - 32]
    jb 3f
    ja 5f
    mov rax, [r8 + 8]
    cmp rax, [r8 - 24]
    jbe 3f
5:  # swap the two records
    mov r10, 0
4:  mov rax, [r8 + r10]
    mov r11, [r8 + r10 - 32]
    mov [r8 + r10], r11
    mov [r8 + r10 - 32], rax
    add r10, 8
    cmp r10, 32
    jb 4b
    dec rdx
    jmp 2b
3:  inc rcx
    jmp 1b
9:  ret

# ---------------- complete-items (language features) ----------------

# rec_begin(ptr, len): the EXTRA records from ptr are iterated with rec_next
rec_begin:
    mov [rip + rec_after], rdi
    add rdi, rsi
    mov [rip + ps_end], rdi
    ret

# rec_next() -> eax 1 for the next record: rec_name/rec_nlen its name, ps_ptr at the fields after
# it (ps_lend ends them), rec_body/rec_blen its bytes; 0 at the end or at a broken record
rec_next:
    push rbx
    mov rax, [rip + rec_after]
    mov [rip + ps_ptr], rax
    call ps_line
    test eax, eax
    jz 8f
    # its last word is its length
    mov rbx, [rip + ps_lend]
    mov rcx, rbx
1:  cmp rcx, [rip + ps_ptr]
    je 8f
    cmp byte ptr [rcx - 1], ' '
    je 2f
    dec rcx
    jmp 1b
2:  mov rdi, rcx
    mov rsi, rbx
    sub rsi, rcx
    jz 8f
    cmp rsi, 10
    ja 8f
    push rsi
    push rsi
    call parse_u64
    pop rsi
    pop rsi
    cmp rdx, rsi
    jne 8f
    lea rcx, [rbx + 1]
    mov [rip + rec_body], rcx
    mov [rip + rec_blen], rax
    add rcx, rax
    cmp rcx, [rip + ps_end]
    ja 8f
    mov [rip + rec_after], rcx
    call ps_word
    mov [rip + rec_name], rax
    mov [rip + rec_nlen], rdx
    mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# rec_is(cstr) -> eax 1 when the current record has that name
rec_is:
    mov rdx, rdi
    mov rdi, [rip + rec_name]
    mov rsi, [rip + rec_nlen]
    jmp str_eq_cstr

# item_extra(CI*) -> rax ptr, rdx len of the item's EXTRA records
item_extra:
    mov rax, [rdi + CI_off]
    add rax, [rip + cp_bytes + SB_ptr]
    mov ecx, [rdi + CI_llen]
    add rax, rcx
    mov ecx, [rdi + CI_ilen]
    add rax, rcx
    mov ecx, [rdi + CI_dlen]
    add rax, rcx
    mov edx, [rdi + CI_xlen]
    ret

# item_record(CI*, name cstr) -> rax ptr, rdx len of the first record of that name's bytes, rax 0
# when it has none (ps_ptr is then at the record's fields)
item_record:
    PROLOGUE
    mov r12, rsi
    call item_extra
    mov rdi, rax
    mov rsi, rdx
    call rec_begin
1:  call rec_next
    test eax, eax
    jz 8f
    mov rdi, r12
    call rec_is
    test eax, eax
    jz 1b
    mov rax, [rip + rec_body]
    mov rdx, [rip + rec_blen]
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# ci_scan(CI*, extra ptr, len): the item's flags and replace range from its complete-items
# records (cp_parse's position mapping is in force; its parser state is kept)
ci_scan:
    PROLOGUE 32
    mov rbx, rdi
    mov rax, [rip + ps_ptr]
    mov [rsp], rax
    mov rax, [rip + ps_end]
    mov [rsp + 8], rax
    mov rax, [rip + ps_lend]
    mov [rsp + 16], rax
    mov rdi, rsi
    mov rsi, rdx
    call rec_begin
.Lcs_next:
    call rec_next
    test eax, eax
    jz .Lcs_done
    lea rdi, [rip + .Lx_preselect]
    call rec_is
    mov ecx, CF_PRESELECT
    test eax, eax
    jnz .Lcs_flag
    lea rdi, [rip + .Lx_deprecated]
    call rec_is
    mov ecx, CF_DEPRECATED
    test eax, eax
    jnz .Lcs_flag
    lea rdi, [rip + .Lx_adjust]
    call rec_is
    mov ecx, CF_ADJUST
    test eax, eax
    jnz .Lcs_flag
    lea rdi, [rip + .Lx_filter]
    call rec_is
    mov ecx, CF_FILTER
    test eax, eax
    jnz .Lcs_line
    lea rdi, [rip + .Lx_suffix]
    call rec_is
    mov ecx, CF_SUFFIX
    test eax, eax
    jnz .Lcs_line
    lea rdi, [rip + .Lx_commit]
    call rec_is
    test eax, eax
    jnz .Lcs_commit
    lea rdi, [rip + .Lx_after]
    call rec_is
    test eax, eax
    jnz .Lcs_after
    lea rdi, [rip + .Lx_resolve]
    call rec_is
    test eax, eax
    jnz .Lcs_resolve
    lea rdi, [rip + .Lx_replace]
    call rec_is
    test eax, eax
    jnz .Lcs_replace
    jmp .Lcs_next
.Lcs_flag:
    or [rbx + CI_flags], ecx
    jmp .Lcs_next
.Lcs_line:                      # filter, suffix: one line of text
    mov [rsp + 24], ecx
    mov rdi, [rip + rec_body]
    mov rsi, [rip + rec_blen]
    call one_line
    test eax, eax
    jz .Lcs_next
    mov ecx, [rsp + 24]
    or [rbx + CI_flags], ecx
    jmp .Lcs_next
.Lcs_commit:                    # 1 to 16 printable ASCII characters
    mov rcx, [rip + rec_blen]
    test rcx, rcx
    jz .Lcs_next
    cmp rcx, 16
    ja .Lcs_next
    mov rdx, [rip + rec_body]
1:  movzx eax, byte ptr [rdx + rcx - 1]
    cmp eax, 0x21
    jb .Lcs_next
    cmp eax, 0x7e
    ja .Lcs_next
    dec rcx
    jnz 1b
    or dword ptr [rbx + CI_flags], CF_COMMIT
    jmp .Lcs_next
.Lcs_after:                     # after signature 0, after complete 0
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lx_signature]
    call str_eq_cstr
    test eax, eax
    jz 1f
    or dword ptr [rbx + CI_flags], CF_AFTER_SIG
    jmp .Lcs_next
1:  mov rax, [rip + ps_ptr]
    sub rax, 9
    mov rdi, rax
    mov esi, 8
    lea rdx, [rip + .Lx_complete]
    call str_eq_cstr
    test eax, eax
    jz .Lcs_next
    or dword ptr [rbx + CI_flags], CF_AFTER_COMPLETE
    jmp .Lcs_next
.Lcs_resolve:                   # resolve EDITS LEN + at most 16 KB of data
    cmp qword ptr [rip + rec_blen], 16384
    ja .Lcs_next
    call ps_num
    test edx, edx
    jz .Lcs_next
    cmp rax, 1
    ja .Lcs_next
    or dword ptr [rbx + CI_flags], CF_RESOLVE
    test rax, rax
    jz .Lcs_next
    or dword ptr [rbx + CI_flags], CF_RESOLVE_EDITS
    jmp .Lcs_next
.Lcs_replace:                   # replace L1 C1 L2 C2 0: it starts where the insert range does
    call ps_pos
    test rax, rax
    js .Lcs_next
    cmp rax, [rbx + CI_o1]
    jne .Lcs_next
    call ps_pos
    test rax, rax
    js .Lcs_next
    cmp rax, [rbx + CI_o1]
    jb .Lcs_next
    mov [rbx + CI_r2], rax
    or dword ptr [rbx + CI_flags], CF_REPLACE
    jmp .Lcs_next
.Lcs_done:
    mov rax, [rsp]
    mov [rip + ps_ptr], rax
    mov rax, [rsp + 8]
    mov [rip + ps_end], rax
    mov rax, [rsp + 16]
    mov [rip + ps_lend], rax
    EPILOGUE

# item_match_text(CI*) -> rax ptr, rdx len: what typing filters and ranks the item by: its filter
# text, else its label
item_match_text:
    PROLOGUE
    mov rbx, rdi
    test dword ptr [rbx + CI_flags], CF_FILTER
    jz 1f
    lea rsi, [rip + .Lx_filter]
    call item_record
    test rax, rax
    jnz 9f
1:  mov rax, [rbx + CI_off]
    add rax, [rip + cp_bytes + SB_ptr]
    mov edx, [rbx + CI_llen]
9:  EPILOGUE

# item_by_serial(serial) -> rax the item's index, or -1
item_by_serial:
    xor eax, eax
1:  cmp rax, [rip + cp_items + VEC_len]
    jae 8f
    imul rcx, rax, CI_SIZE
    add rcx, [rip + cp_items + VEC_ptr]
    cmp [rcx + CI_serial], edi
    je 9f
    inc rax
    jmp 1b
8:  mov rax, -1
9:  ret

# selected_item() -> rax the selected row's CI*, or 0
selected_item:
    xor eax, eax
    cmp dword ptr [rip + cp_open], 2
    jne 9f
    mov ecx, [rip + cp_sel]
    cmp ecx, [rip + cp_nshown]
    jae 9f
    lea rax, [rip + cp_shown]
    mov edi, [rax + rcx*4]
    jmp item
9:  ret

# res_schedule(): the selected item is resolved after a short pause (it may be shown only briefly)
res_schedule:
    push rbx
    call selected_item
    test rax, rax
    jz 8f
    mov ecx, [rax + CI_flags]
    and ecx, CF_RESOLVE | CF_RESOLVED | CF_RESOLVING
    cmp ecx, CF_RESOLVE
    jne 8f
    call time_ms
    add rax, CP_RESOLVE_MS
    mov [rip + cp_res_due], rax
    pop rbx
    ret
8:  mov qword ptr [rip + cp_res_due], 0
    pop rbx
    ret

# res_send(CI*): "ID complete-resolve DOC VERSION LEN" + its resolve data to its provider; the
# resolve out for another item is withdrawn
res_send:
    PROLOGUE 16
    mov rbx, rdi
    mov eax, [rbx + CI_flags]
    and eax, CF_RESOLVE | CF_RESOLVED | CF_RESOLVING
    cmp eax, CF_RESOLVE
    jne 9f
    mov rdi, [rbx + CI_ext]
    call ext_is_visible
    test eax, eax
    jz 9f
    mov edi, 1
    call query_room
    test eax, eax
    jz 9f
    call res_withdraw
    mov r12d, [rbx + CI_serial]
    mov rdi, rbx
    lea rsi, [rip + .Lx_resolve]
    call item_record
    test rax, rax
    jz 9f
    mov r13, rax                # the data
    mov r14, rdx
    lea rdi, [rip + cp_res_line]
    call sb_clear
    lea rdi, [rip + cp_res_line]
    lea rsi, [rip + .Lv_resolve]
    call sb_push_cstr
    mov rax, [rip + cp_doc]
    lea rdi, [rip + cp_res_line]
    mov rsi, [rax + DOC_id]
    call sb_push_u64
    lea rdi, [rip + cp_res_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cp_res_line]
    mov rsi, [rbx + CI_ver]
    call sb_push_u64
    lea rdi, [rip + cp_res_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cp_res_line]
    mov rsi, r14
    call sb_push_u64
    mov rdi, [rbx + CI_ext]
    mov rsi, [rip + cp_doc]
    mov rdx, [rip + cp_res_line + SB_ptr]
    mov rcx, [rip + cp_res_line + SB_len]
    mov r8, r13
    mov r9, r14
    call extproto_host_send_body
    test rax, rax
    jz 9f
    mov r15, rax
    or dword ptr [rbx + CI_flags], CF_RESOLVING
    mov [rip + cp_res_serial], r12d
    mov rbx, [rbx + CI_ext]
    mov rdi, rbx
    mov rsi, r15
    mov edx, PK_RESOLVE
    mov ecx, QO_COMPLETE
    call query_track
    lea rdi, [rip + cp_reqs]
    mov esi, HR_SIZE
    call vec_push
    mov [rax + HR_ext], rbx
    mov [rax + HR_id], r15
    mov dword ptr [rax + HR_kind], HR_RESOLVE
    mov ecx, [rip + cp_session]
    mov [rax + HR_session], ecx
    mov [rax + HR_req], r12
9:  EPILOGUE

# res_withdraw(): the resolve out is not wanted any more: its item may be resolved again later
res_withdraw:
    push rbx
    mov edi, [rip + cp_res_serial]
    test edi, edi
    jz 1f
    mov dword ptr [rip + cp_res_serial], 0
    call item_by_serial
    test rax, rax
    js 1f
    mov rdi, rax
    call item
    and dword ptr [rax + CI_flags], ~CF_RESOLVING
1:  mov edi, HR_RESOLVE
    call cancel_kind
    pop rbx
    ret

# res_answer(serial, ok, body, len): its resolve answer (from extproto's pump: state only): EXTRA
# records doc, detail, edit and after join the item; field, choice and cursor records drop it
res_answer:
    PROLOGUE 32
    mov r12d, edi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    cmp [rip + cp_res_serial], r12d
    jne 1f
    mov dword ptr [rip + cp_res_serial], 0
1:  mov edi, r12d
    call item_by_serial
    test rax, rax
    js 9f
    mov rdi, rax
    call item
    mov rbx, rax
    and dword ptr [rbx + CI_flags], ~CF_RESOLVING
    or dword ptr [rbx + CI_flags], CF_RESOLVED
    test r13d, r13d
    jz 8f
    test r15, r15
    jz 8f
    cmp r15, 65536
    ja 8f
    # whole records, none of them a field, choice or cursor; a detail one line
    mov rdi, r14
    mov rsi, r15
    call extra_ok
    test eax, eax
    jz 7f
    mov qword ptr [rsp], 0      # its detail record, if any
    mov rdi, r14
    mov rsi, r15
    call rec_begin
2:  call rec_next
    test eax, eax
    jz 3f
    lea rdi, [rip + .Lx_field]
    call rec_is
    test eax, eax
    jnz 7f
    lea rdi, [rip + .Lx_choice]
    call rec_is
    test eax, eax
    jnz 7f
    lea rdi, [rip + .Lx_cursor]
    call rec_is
    test eax, eax
    jnz 7f
    lea rdi, [rip + .Lx_detail]
    call rec_is
    test eax, eax
    jz 2b
    mov rdi, [rip + rec_body]
    mov rsi, [rip + rec_blen]
    call one_line
    test eax, eax
    jz 7f
    mov rax, [rip + rec_body]
    mov [rsp], rax
    mov rax, [rip + rec_blen]
    mov [rsp + 8], rax
    jmp 2b
3:  # the item's bytes again at the end: label, insert, the detail (the new one), the old records
    # and the answer's
    mov rdi, rbx
    call item_extra
    mov [rsp + 16], rax         # its old records, before the detail's length changes
    mov [rsp + 24], rdx
    lea rdi, [rip + cp_res_line]
    call sb_clear
    mov rsi, [rbx + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov edx, [rbx + CI_llen]
    add edx, [rbx + CI_ilen]
    lea rdi, [rip + cp_res_line]
    call sb_push
    cmp qword ptr [rsp], 0
    je 4f
    lea rdi, [rip + cp_res_line]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call sb_push
    mov eax, [rsp + 8]
    mov [rbx + CI_dlen], eax
    jmp 5f
4:  mov rsi, [rbx + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov eax, [rbx + CI_llen]
    add rsi, rax
    mov eax, [rbx + CI_ilen]
    add rsi, rax
    mov edx, [rbx + CI_dlen]
    lea rdi, [rip + cp_res_line]
    call sb_push
5:  lea rdi, [rip + cp_res_line]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call sb_push
    lea rdi, [rip + cp_res_line]
    mov rsi, r14
    mov rdx, r15
    call sb_push
    add [rbx + CI_xlen], r15d
    mov rax, [rip + cp_bytes + SB_len]
    mov [rbx + CI_off], rax
    lea rdi, [rip + cp_bytes]
    mov rsi, [rip + cp_res_line + SB_ptr]
    mov rdx, [rip + cp_res_line + SB_len]
    call sb_push
    # an after record in the answer
    mov rdi, r14
    mov rsi, r15
    call rec_begin
6:  call rec_next
    test eax, eax
    jz 8f
    lea rdi, [rip + .Lx_after]
    call rec_is
    test eax, eax
    jz 6b
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lx_signature]
    call str_eq_cstr
    mov ecx, CF_AFTER_SIG
    test eax, eax
    jnz 61f
    mov ecx, CF_AFTER_COMPLETE
61: or [rbx + CI_flags], ecx
    jmp 6b
7:  mov rdi, [rbx + CI_ext]
    mov esi, PK_RESOLVE
    call query_dropped
8:  cmp [rip + cp_wait_serial], r12d
    jne 9f
    mov dword ptr [rip + cp_wait_ready], 1     # the waiting accept goes ahead (the tick)
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# cp_wait_accept(): the accept that waited for its item's resolve goes ahead, with what came
cp_wait_accept:
    push rbx
    push r12
    sub rsp, 8
    mov edi, [rip + cp_wait_serial]
    mov ebx, [rip + cp_wait_replace]
    mov r12d, [rip + cp_wait_char]
    mov dword ptr [rip + cp_wait_serial], 0
    mov dword ptr [rip + cp_wait_ready], 0
    mov dword ptr [rip + cp_wait_char], 0
    call item_by_serial
    test rax, rax
    js 8f
    mov rdi, rax
    call item
    mov rdi, rax
    mov esi, ebx
    call cp_accept_ci
    jmp 7f
8:  call cp_close
7:  test r12d, r12d             # the commit character that waited goes in after the item
    jz 9f
    call focused_doc
    test rax, rax
    jz 9f
    mov edi, r12d
    call ed_type
    mov edi, r12d
    call complete_typed
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# FN complete_part(ext, id, body, len) -> rax the items a part of a pending completion request
# brought (query-part, from extproto's pump: state only), or -1 when it breaks the rules
FN complete_part
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r14, rdx
    mov r15, rcx
    xor r13d, r13d
1:  cmp r13, [rip + cp_reqs + VEC_len]
    jae 7f
    imul rax, r13, HR_SIZE
    add rax, [rip + cp_reqs + VEC_ptr]
    inc r13
    cmp [rax + HR_ext], rbx
    jne 1b
    cmp [rax + HR_id], r12
    jne 1b
    cmp dword ptr [rax + HR_kind], HR_COMPLETE
    jne 7f
    mov ecx, [rax + HR_session]
    cmp ecx, [rip + cp_session]
    jne 7f
    cmp dword ptr [rip + cp_open], 0
    je 7f
    mov rcx, [rax + HR_language_revision]
    cmp rcx, [rip + cp_language_revision]
    jne 7f
    mov [rsp], rax
    call doc_alive
    test eax, eax
    jz 7f
    mov rax, [rsp]
    mov ecx, [rax + HR_parts]   # the first part replaces what it said before, later ones add
    mov [rsp + 16], ecx
    mov dword ptr [rax + HR_parts], 1
    mov rdx, [rax + HR_version]
    mov [rip + cp_parse_ver], rdx
    mov qword ptr [rip + cp_room], -1
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, [rax + HR_req]
    mov r8d, [rsp + 16]
    call cp_merge_mode
    EPILOGUE
7:  xor eax, eax                # nobody waits for it any more: taken, and dropped
    EPILOGUE

# ---------------- drawing ----------------

# FN complete_hole(): at the frame's start: the list drawn last frame keeps the pointer from what
# is drawn under it this frame
FN complete_hole
    mov eax, [rip + cp_rect + 12]
    mov [rip + g_hole2 + 12], eax
    mov eax, [rip + cp_rect]
    mov [rip + g_hole2], eax
    mov eax, [rip + cp_rect + 4]
    mov [rip + g_hole2 + 4], eax
    mov eax, [rip + cp_rect + 8]
    mov [rip + g_hole2 + 8], eax
    ret

# FN complete_draw(): the frame's list and signature help, over everything but menus and dialogs
FN complete_draw
    PROLOGUE
    call cp_choice_pending
    call cp_check
    call sg_check
    mov dword ptr [rip + g_hole2 + 12], 0   # the list's rows take the pointer themselves
    mov dword ptr [rip + cp_rect + 12], 0
    mov dword ptr [rip + sg_rect + 12], 0
    cmp dword ptr [rip + g_caret_ok], 0
    je 9f
    cmp dword ptr [rip + sg_open], 0
    je 1f
    call sg_draw
1:  cmp dword ptr [rip + cp_open], 2
    jne 9f
    cmp dword ptr [rip + cp_nshown], 0
    je 9f
    call cp_draw
9:  EPILOGUE

# baseline(face, y, h) -> eax the baseline of a line of the face centered in [y, y + h)
baseline:
    mov eax, edx
    sub eax, [rdi + FACE_ascent]
    sub eax, [rdi + FACE_descent]
    sar eax, 1
    add eax, esi
    add eax, [rdi + FACE_ascent]
    ret

# cp_draw(): the list under the word (above it when there is no room below)
cp_draw:
    PROLOGUE 96
    # the rows' height, the widest label and detail
    mov eax, [rip + g_lh]
    add eax, [rip + g_mt + 4*MI_4]
    mov [rsp], eax              # row height
    xor eax, eax
    mov [rsp + 4], eax          # label width
    mov [rsp + 8], eax          # detail width
    xor ebx, ebx
1:  cmp ebx, [rip + cp_nshown]
    jae 2f
    lea rax, [rip + cp_shown]
    mov edi, [rax + rbx*4]
    call item
    mov r12, rax
    lea rdi, [rip + g_face_code]
    mov rsi, [r12 + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov edx, [r12 + CI_llen]
    call text_width
    mov r13d, eax
    test dword ptr [r12 + CI_flags], CF_SUFFIX
    jz 13f
    mov rdi, r12                # complete-items: the suffix follows the label
    lea rsi, [rip + .Lx_suffix]
    call item_record
    mov rsi, rax
    lea rdi, [rip + g_face_code]
    call text_width
    add r13d, eax
    add r13d, [rip + g_mt + 4*MI_4]
13: cmp r13d, [rsp + 4]
    jle 11f
    mov [rsp + 4], r13d
11: lea rdi, [rip + g_face_small]
    mov rsi, [r12 + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov eax, [r12 + CI_llen]
    add rsi, rax
    mov eax, [r12 + CI_ilen]
    add rsi, rax
    mov edx, [r12 + CI_dlen]
    call text_width
    cmp eax, [rsp + 8]
    jle 12f
    mov [rsp + 8], eax
12: inc ebx
    jmp 1b
2:  M eax, MI_64
    imul eax, eax, 3
    cmp [rsp + 8], eax
    jle 21f
    mov [rsp + 8], eax          # details give way
21: # the width: badge, label, detail, padding
    M eax, MI_4
    add eax, eax
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 12], eax         # the label's x within the list
    add eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_8]
    cmp dword ptr [rsp + 8], 0
    je 22f
    add eax, [rip + g_mt + 4*MI_24]
    add eax, [rsp + 8]
22: M ecx, MI_64
    imul ecx, ecx, 3
    cmp eax, ecx
    cmovl eax, ecx
    mov ecx, [rip + g_editor_rect + 8]
    sub ecx, [rip + g_mt + 4*MI_16]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 16], eax         # w
    # rows shown and the height
    mov eax, [rip + cp_nshown]
    cmp eax, CP_ROWS
    jbe 23f
    mov eax, CP_ROWS
23: mov [rsp + 20], eax         # rows
    imul eax, [rsp]
    M ecx, MI_4
    lea eax, [rax + rcx*2]
    mov [rsp + 24], eax         # h
    # x: the labels line up with the word being typed
    mov rbx, [rip + cp_doc]
    mov rsi, [rip + cp_start]
    mov rdx, [rbx + DOC_cur]
    sub rdx, rsi
    xor eax, eax
    cmp rdx, CP_QMAX
    ja 24f
    test rdx, rdx
    jz 24f
    mov [rsp + 40], rdx
    mov rdi, rbx
    call doc_range
    lea rdi, [rip + g_face_code]
    mov rsi, rax
    mov rdx, [rsp + 40]
    call text_width
24: mov ecx, [rip + g_caret_x]
    sub ecx, eax
    sub ecx, [rsp + 12]
    mov eax, [rip + g_cv + CV_w]
    sub eax, [rsp + 16]
    sub eax, [rip + g_mt + 4*MI_4]
    cmp ecx, eax
    cmovg ecx, eax
    mov eax, [rip + g_editor_rect]
    cmp ecx, eax
    cmovl ecx, eax
    mov [rsp + 28], ecx         # x
    # y: below the line, or above it when the editor ends first
    mov eax, [rip + g_caret_y]
    add eax, [rip + g_lh]
    mov ecx, eax
    add ecx, [rsp + 24]
    mov edx, [rip + g_editor_rect + 4]
    add edx, [rip + g_editor_rect + 12]
    cmp ecx, edx
    jle 25f
    mov ecx, [rip + g_caret_y]
    sub ecx, [rsp + 24]
    cmp ecx, [rip + g_editor_rect + 4]
    jl 25f
    mov eax, ecx
25: mov [rsp + 32], eax         # y
    # the card
    mov edi, [rsp + 28]
    mov esi, [rsp + 32]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 24]
    M r8d, MI_8
    M r9d, MI_2
    M eax, MI_RADIUS
    push rax
    push rax
    call ui_card_shadow
    add rsp, 16
    mov eax, [rsp + 28]
    mov [rip + cp_rect], eax
    mov eax, [rsp + 32]
    mov [rip + cp_rect + 4], eax
    mov eax, [rsp + 16]
    mov [rip + cp_rect + 8], eax
    mov eax, [rsp + 24]
    mov [rip + cp_rect + 12], eax
    # the wheel scrolls the rows
    mov edi, [rsp + 28]
    mov esi, [rsp + 32]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 24]
    call ui_in
    test eax, eax
    jz 3f
    mov eax, [rip + g_scroll_y]
    test eax, eax
    jz 3f
    mov dword ptr [rip + g_scroll_y], 0
    mov ecx, [rip + cp_top]
    test eax, eax
    jg 26f
    inc ecx
    jmp 27f
26: dec ecx
27: mov eax, [rip + cp_nshown]
    sub eax, [rsp + 20]
    cmp ecx, eax
    cmovg ecx, eax
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    mov [rip + cp_top], ecx
3:  # the rows
    mov dword ptr [rsp + 36], -1    # a row clicked
    xor ebx, ebx
.Lcd_row:
    cmp ebx, [rsp + 20]
    jae .Lcd_rows_done
    mov eax, ebx
    imul eax, [rsp]
    add eax, [rsp + 32]
    add eax, [rip + g_mt + 4*MI_4]
    mov r13d, eax               # the row's y
    mov r14d, ebx
    add r14d, [rip + cp_top]    # the row
    lea rax, [rip + cp_shown]
    mov edi, [rax + r14*4]
    call item
    mov r12, rax
    lea edi, [rbx + ID_COMPLETE]
    mov esi, [rsp + 28]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, r13d
    mov ecx, [rsp + 16]
    sub ecx, [rip + g_mt + 4*MI_4]
    sub ecx, [rip + g_mt + 4*MI_4]
    mov r8d, [rsp]
    call ui_btn
    mov r15d, eax
    test r15d, UB_CLICK
    jz 31f
    mov [rsp + 36], r14d
31: # the selected row, the one under the pointer
    COLOR r9d, T_ACTIVE
    cmp r14d, [rip + cp_sel]
    je 32f
    test r15d, UB_HOVER
    jz 33f
    COLOR r9d, T_HOVER
32: mov edi, [rsp + 28]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, r13d
    mov edx, [rsp + 16]
    sub edx, [rip + g_mt + 4*MI_4]
    sub edx, [rip + g_mt + 4*MI_4]
    mov ecx, [rsp]
    M r8d, MI_4
    call gfx_round_rect
33: # the kind's badge: its letter in its color, on a tint of it
    mov eax, [r12 + CI_kind]
    lea rcx, [rip + kind_colors]
    movzx eax, byte ptr [rcx + rax]
    lea rcx, [rip + g_theme]
    mov eax, [rcx + rax*4]
    mov [rsp + 40], eax
    and eax, 0x00ffffff
    or eax, 0x33000000
    mov r9d, eax
    mov edi, [rsp + 28]
    add edi, [rip + g_mt + 4*MI_4]
    add edi, [rip + g_mt + 4*MI_6]
    mov [rsp + 44], edi
    mov esi, [rsp]
    sub esi, [rip + g_mt + 4*MI_16]
    sar esi, 1
    add esi, r13d
    mov [rsp + 48], esi
    M edx, MI_16
    M ecx, MI_16
    M r8d, MI_4
    call gfx_round_rect
    mov eax, [r12 + CI_kind]
    lea rcx, [rip + kind_letters]
    lea r9, [rcx + rax*2]
    mov eax, [rsp + 40]
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 44 + 16]
    mov edx, [rsp + 48 + 16]
    M ecx, MI_16
    mov r8d, ecx
    call ui_text_center
    add rsp, 16
    # the detail's width in this row
    xor eax, eax
    mov [rsp + 60], eax
    cmp dword ptr [r12 + CI_dlen], 0
    je 35f
    mov rsi, [r12 + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov eax, [r12 + CI_llen]
    add rsi, rax
    mov eax, [r12 + CI_ilen]
    add rsi, rax
    lea rdi, [rip + g_face_small]
    mov edx, [r12 + CI_dlen]
    call text_width
    mov edx, [rsp + 8]
    cmp eax, edx
    cmovg eax, edx
    mov [rsp + 60], eax
35: # the label, what was typed in it in the accent color, clipped to what the detail leaves
    mov edi, [rsp + 28]
    add edi, [rsp + 12]
    mov [rsp + 52], edi         # its x
    mov esi, r13d
    mov edx, [rsp + 16]
    sub edx, [rsp + 12]
    sub edx, [rip + g_mt + 4*MI_8]
    sub edx, [rsp + 60]
    cmp dword ptr [rsp + 60], 0
    je 36f
    sub edx, [rip + g_mt + 4*MI_8]
36: mov ecx, [rsp]
    call gfx_clip_push
    mov rdi, [r12 + CI_o1]
    call query_for
    lea rdi, [rip + g_face_code]
    mov esi, r13d
    mov edx, [rsp]
    call baseline
    mov [rsp + 68], eax
    mov esi, eax
    mov edi, [rsp + 52]
    mov rdx, r12
    call draw_label
    mov [rsp + 64], eax
    call cp_label_extras        # complete-items: struck when deprecated, the suffix, the wait
    call gfx_clip_pop
    # the detail at the right, muted
    mov eax, [rsp + 60]
    test eax, eax
    jz 34f
    mov rsi, [r12 + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add rsi, rcx
    mov ecx, [r12 + CI_ilen]
    add rsi, rcx
    mov [rsp + 56], rsi
    mov ecx, [rsp + 28]
    add ecx, [rsp + 16]
    sub ecx, [rip + g_mt + 4*MI_4]
    sub ecx, [rip + g_mt + 4*MI_8]
    sub ecx, eax
    mov eax, [rsp + 8]
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, ecx
    mov edx, r13d
    mov ecx, [rsp + 16]
    mov r8, [rsp + 56 + 16]
    mov r9d, [r12 + CI_dlen]
    call ui_text_v_fit
    add rsp, 16
34: inc ebx
    jmp .Lcd_row
.Lcd_rows_done:
    # the documentation of the selected item beside the list
    mov edi, [rsp + 28]
    mov esi, [rsp + 32]
    mov edx, [rsp + 16]
    call cp_doc_draw
    mov eax, [rsp + 36]
    test eax, eax
    js 9f
    mov edi, eax
    call cp_select
    call cp_accept
9:  EPILOGUE

# draw_label(x, baseline, CI*): the label in the code face, the bytes the filter text matched
# (in order, ASCII, any case) in the accent color
draw_label:
    PROLOGUE 32
    mov [rsp], edi              # pen
    mov [rsp + 4], esi          # baseline
    mov r12, rdx
    mov r13, [r12 + CI_off]
    add r13, [rip + cp_bytes + SB_ptr]
    mov r14d, [r12 + CI_llen]
    xor ebx, ebx                # byte
    xor r15d, r15d              # query byte
1:  cmp ebx, r14d
    jae 9f
    # this run: matched or not, as its first byte is
    mov edi, ebx
    call lmatch
    mov [rsp + 8], eax
    add r15d, eax
    lea ecx, [rbx + 1]
2:  cmp ecx, r14d
    jae 3f
    push rcx
    push rcx
    mov edi, ecx
    call lmatch
    pop rcx
    pop rcx
    cmp eax, [rsp + 8]
    jne 3f
    add r15d, eax
    inc ecx
    jmp 2b
3:  mov [rsp + 12], ecx
    COLOR r9d, T_FG
    cmp dword ptr [rsp + 8], 0
    je 4f
    COLOR r9d, T_ACCENT
4:  lea rdi, [rip + g_face_code]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    lea rcx, [r13 + rbx]
    mov r8d, [rsp + 12]
    sub r8d, ebx
    call text_draw
    mov [rsp], eax
    mov ebx, [rsp + 12]
    jmp 1b
9:  mov eax, [rsp]
    EPILOGUE

# cp_label_extras(): cp_draw's row: r12 the item, [rsp + 8 + 52] the label's x, + 64 the pen after
# it, + 68 the baseline: a line through a deprecated label, the suffix muted, "…" while accepting
# waits for its resolve
cp_label_extras:
    PROLOGUE 16
    mov eax, [rbp + 16 + 52]
    mov [rsp], eax              # the label's x
    mov eax, [rbp + 16 + 64]
    mov [rsp + 4], eax          # the pen
    mov eax, [rbp + 16 + 68]
    mov [rsp + 8], eax          # the baseline
    test dword ptr [r12 + CI_flags], CF_DEPRECATED
    jz 1f
    mov edi, [rsp]
    mov esi, [rsp + 8]
    mov eax, [rip + g_face_code + FACE_ascent]
    imul eax, eax, 3
    sar eax, 3
    sub esi, eax
    mov edx, [rsp + 4]
    sub edx, edi
    M ecx, MI_1
    COLOR r8d, T_FG
    call gfx_fill
1:  test dword ptr [r12 + CI_flags], CF_SUFFIX
    jz 2f
    mov rdi, r12
    lea rsi, [rip + .Lx_suffix]
    call item_record
    test rax, rax
    jz 2f
    mov rcx, rax
    mov r8, rdx
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 8]
    COLOR r9d, T_MUTED
    call text_draw
    mov [rsp + 4], eax
2:  mov eax, [r12 + CI_serial]
    cmp dword ptr [rip + cp_wait_serial], 0
    je 9f
    cmp eax, [rip + cp_wait_serial]
    jne 9f
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 8]
    lea rcx, [rip + .Lx_ellipsis]
    mov r8d, 3
    COLOR r9d, T_MUTED
    call text_draw
9:  EPILOGUE

# lmatch(i) -> eax 1 when label byte i (r13 the label) is the next query byte (r15d of cp_q)
lmatch:
    xor eax, eax
    cmp r15, [rip + cp_qlen]
    jae 9f
    movzx ecx, byte ptr [r13 + rdi]
    cmp ecx, 0x80
    jae 9f
    lea rdx, [rip + cp_q]
    movzx edx, byte ptr [rdx + r15]
    lea r8d, [rcx - 'A']
    cmp r8d, 25
    ja 1f
    or ecx, 0x20
1:  lea r8d, [rdx - 'A']
    cmp r8d, 25
    ja 2f
    or edx, 0x20
2:  cmp ecx, edx
    jne 9f
    mov eax, 1
9:  ret

# item_doc(CI*) -> rax ptr, rdx len of the documentation in the item's extra records (len 0: none);
# the last doc record, so a resolve answer's documentation replaces the list's
item_doc:
    PROLOGUE 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov r12, rdi
    mov rax, [r12 + CI_off]
    add rax, [rip + cp_bytes + SB_ptr]
    mov ecx, [r12 + CI_llen]
    add rax, rcx
    mov ecx, [r12 + CI_ilen]
    add rax, rcx
    mov ecx, [r12 + CI_dlen]
    add rax, rcx
    mov [rip + ps_ptr], rax
    mov ecx, [r12 + CI_xlen]
    add rax, rcx
    mov [rip + ps_end], rax
1:  call ps_line
    test eax, eax
    jz 8f
    mov rbx, [rip + ps_lend]
    # the record's last word is its length
    xor r13d, r13d
    xor r14d, r14d
    call ps_word
    mov r15, rax                # its name
2:  call ps_word
    test rdx, rdx
    jz 3f
    mov r13, rax
    mov r14, rdx
    jmp 2b
3:  test r13, r13
    jz 8f
    mov rdi, r13
    mov rsi, r14
    call parse_u64
    cmp rdx, r14
    jne 8f
    lea rcx, [rbx + 1]          # its bytes
    lea rdx, [rcx + rax]
    cmp rdx, [rip + ps_end]
    ja 8f
    mov [rip + ps_ptr], rdx
    # "doc LEN"
    cmp byte ptr [r15], 'd'
    jne 1b
    cmp byte ptr [r15 + 1], 'o'
    jne 1b
    cmp byte ptr [r15 + 2], 'c'
    jne 1b
    cmp byte ptr [r15 + 3], ' '
    jne 1b
    mov [rsp], rcx
    mov [rsp + 8], rax
    jmp 1b
8:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE

# wrap(face, ptr, len, maxw, x, y, lh, argb, lines left, draw) -> eax lines it takes (drawn when draw
# is 1): paragraphs at LF, lines broken at the last space that fits
# (args: rdi face, rsi ptr, rdx len, ecx maxw, r8d x, r9d y, [stack] lh, argb, max lines, draw)
wrap:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], ecx
    mov [rsp + 4], r8d
    mov [rsp + 8], r9d
    mov eax, [rbp + 16]
    mov [rsp + 12], eax         # lh
    mov eax, [rbp + 24]
    mov [rsp + 16], eax         # argb
    mov eax, [rbp + 32]
    mov [rsp + 20], eax         # lines at most
    mov eax, [rbp + 40]
    mov [rsp + 24], eax         # draw
    xor r15d, r15d              # lines
1:  test r13, r13
    jz 9f
    cmp r15d, [rsp + 20]
    jae 9f
    # this paragraph's end
    xor r14d, r14d
2:  cmp r14, r13
    jae 3f
    cmp byte ptr [r12 + r14], 10
    je 3f
    inc r14
    jmp 2b
3:  mov [rsp + 32], r14         # the paragraph's length
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov ecx, [rsp]
    call text_fit
    mov r14, rax
    cmp r14, [rsp + 32]
    jae 5f
    # break at the last space that fits
    mov rcx, r14
4:  test rcx, rcx
    jz 41f
    cmp byte ptr [r12 + rcx], ' '
    je 42f
    dec rcx
    jmp 4b
41: test r14, r14
    jnz 5f
    mov r14d, 1                 # not even one character fits: one anyway
    jmp 5f
42: mov r14, rcx
5:  cmp dword ptr [rsp + 24], 0
    je 6f
    mov eax, [rsp + 16]
    push rax
    push rax
    mov rdi, rbx
    mov esi, [rsp + 4 + 16]
    mov edx, r15d
    imul edx, [rsp + 12 + 16]
    add edx, [rsp + 8 + 16]
    mov ecx, [rsp + 12 + 16]
    mov r8, r12
    mov r9, r14
    call ui_text_v
    add rsp, 16
6:  inc r15d
    add r12, r14
    sub r13, r14
    # past the space or the line break where it broke
    test r13, r13
    jz 9f
    movzx eax, byte ptr [r12]
    cmp eax, ' '
    je 7f
    cmp eax, 10
    jne 1b
7:  inc r12
    dec r13
    jmp 1b
9:  mov eax, r15d
    EPILOGUE

# cp_doc_draw(x, y, w): the selected item's detail and documentation beside the list at x, y, w
cp_doc_draw:
    PROLOGUE 64
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov eax, [rip + cp_sel]
    lea rcx, [rip + cp_shown]
    mov edi, [rcx + rax*4]
    call item
    mov r12, rax
    mov rdi, r12
    call item_doc
    mov r13, rax
    mov r14, rdx                # the documentation
    mov eax, [r12 + CI_dlen]
    or rax, r14
    jz 9f                       # nothing to tell
    # its width; right of the list, else left of it
    M eax, MI_64
    imul eax, eax, 6
    mov ecx, [rip + g_cv + CV_w]
    shr ecx, 1
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 12], eax         # pw
    mov ecx, [rsp]
    add ecx, [rsp + 8]
    add ecx, [rip + g_mt + 4*MI_4]
    mov edx, ecx
    add edx, eax
    mov r8d, [rip + g_cv + CV_w]
    sub r8d, [rip + g_mt + 4*MI_4]
    cmp edx, r8d
    jle 1f
    mov ecx, [rsp]
    sub ecx, eax
    sub ecx, [rip + g_mt + 4*MI_4]
    js 9f
1:  mov [rsp + 16], ecx         # px
    # its height: the detail's line, then the documentation's
    M eax, MI_8
    mov ecx, [rsp + 12]
    sub ecx, eax
    sub ecx, eax
    mov [rsp + 20], ecx         # the text's width
    xor r15d, r15d
    cmp dword ptr [r12 + CI_dlen], 0
    je 2f
    mov r15d, [rip + g_face_code + FACE_lineh]
2:  mov [rsp + 24], r15d        # the detail's height
    xor eax, eax
    test r14, r14
    jz 3f
    xor eax, eax
    push rax
    mov eax, DOC_LINES_MAX
    push rax
    xor eax, eax
    push rax
    mov eax, [rip + g_face_small + FACE_lineh]
    push rax
    lea rdi, [rip + g_face_small]
    mov rsi, r13
    mov rdx, r14
    mov ecx, [rsp + 20 + 32]
    xor r8d, r8d
    xor r9d, r9d
    call wrap
    add rsp, 32
    imul eax, [rip + g_face_small + FACE_lineh]
3:  mov [rsp + 28], eax         # the documentation's height
    add eax, [rsp + 24]
    M ecx, MI_8
    lea eax, [rax + rcx*2]
    cmp dword ptr [rsp + 24], 0
    je 4f
    cmp dword ptr [rsp + 28], 0
    je 4f
    add eax, [rip + g_mt + 4*MI_4]
4:  mov [rsp + 32], eax         # ph
    mov edi, [rsp + 16]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov ecx, eax
    M r8d, MI_8
    M r9d, MI_2
    M eax, MI_RADIUS
    push rax
    push rax
    call ui_card_shadow
    add rsp, 16
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 36], eax         # the next line's y
    cmp dword ptr [rsp + 24], 0
    je 5f
    mov eax, [rsp + 20]
    push rax
    COLOR eax, T_FG
    push rax
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 16 + 16]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 36 + 16]
    mov ecx, [rsp + 24 + 16]
    mov r8, [r12 + CI_off]
    add r8, [rip + cp_bytes + SB_ptr]
    mov eax, [r12 + CI_llen]
    add r8, rax
    mov eax, [r12 + CI_ilen]
    add r8, rax
    mov r9d, [r12 + CI_dlen]
    call ui_text_v_fit
    add rsp, 16
    mov eax, [rsp + 24]
    add eax, [rip + g_mt + 4*MI_4]
    add [rsp + 36], eax
5:  test r14, r14
    jz 9f
    mov eax, 1
    push rax
    mov eax, DOC_LINES_MAX
    push rax
    COLOR eax, T_MUTED
    push rax
    mov eax, [rip + g_face_small + FACE_lineh]
    push rax
    lea rdi, [rip + g_face_small]
    mov rsi, r13
    mov rdx, r14
    mov ecx, [rsp + 20 + 32]
    mov r8d, [rsp + 16 + 32]
    add r8d, [rip + g_mt + 4*MI_8]
    mov r9d, [rsp + 36 + 32]
    call wrap
    add rsp, 32
9:  EPILOGUE

# sg_draw(): the signature above the cursor, the active parameter in the accent color, then its
# documentation
sg_draw:
    PROLOGUE 64
    mov r12, [rip + sg_text + SB_ptr]
    mov r13, [rip + sg_siglen]
    mov r14, [rip + sg_text + SB_len]
    sub r14, r13                # the documentation, after the signature's LF
    jz 1f
    dec r14
1:  lea r15, [r12 + r13 + 1]
    # signature-list: "2/3" before the signature when there are several
    xor eax, eax
    cmp dword ptr [rip + sg_count], 1
    jbe 11f
    lea rdi, [rip + g_face_code]
    lea rsi, [rip + sg_ctr]
    mov edx, [rip + sg_ctrlen]
    call text_width
    add eax, [rip + g_mt + 4*MI_8]
11: mov [rsp + 40], eax
    # the width
    lea rdi, [rip + g_face_code]
    mov rsi, r12
    mov rdx, r13
    call text_width
    add eax, [rsp + 40]
    M ecx, MI_8
    lea eax, [rax + rcx*2]
    M ecx, MI_64
    imul ecx, ecx, 5
    cmp eax, ecx
    cmovl eax, ecx
    mov ecx, [rip + g_editor_rect + 8]
    sub ecx, [rip + g_mt + 4*MI_16]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp], eax              # w
    M ecx, MI_8
    sub eax, ecx
    sub eax, ecx
    mov [rsp + 4], eax          # the text's width
    # the documentation's lines
    xor eax, eax
    test r14, r14
    jz 2f
    xor eax, eax
    push rax
    mov eax, SG_LINES_MAX
    push rax
    xor eax, eax
    push rax
    mov eax, [rip + g_face_small + FACE_lineh]
    push rax
    lea rdi, [rip + g_face_small]
    mov rsi, r15
    mov rdx, r14
    mov ecx, [rsp + 4 + 32]
    xor r8d, r8d
    xor r9d, r9d
    call wrap
    add rsp, 32
    imul eax, [rip + g_face_small + FACE_lineh]
    test eax, eax
    jz 2f
    add eax, [rip + g_mt + 4*MI_4]
2:  mov [rsp + 8], eax          # its height
    add eax, [rip + g_face_code + FACE_lineh]
    M ecx, MI_6
    lea eax, [rax + rcx*2]
    mov [rsp + 12], eax         # h
    # above the line, or below it at the top of the editor
    mov ecx, [rip + g_caret_x]
    sub ecx, [rip + g_mt + 4*MI_8]
    mov edx, [rip + g_cv + CV_w]
    sub edx, [rsp]
    sub edx, [rip + g_mt + 4*MI_4]
    cmp ecx, edx
    cmovg ecx, edx
    mov edx, [rip + g_editor_rect]
    cmp ecx, edx
    cmovl ecx, edx
    mov [rsp + 16], ecx         # x
    mov eax, [rip + g_caret_y]
    sub eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_4]
    cmp eax, [rip + g_editor_rect + 4]
    jge 3f
    mov eax, [rip + g_caret_y]
    add eax, [rip + g_lh]
    add eax, [rip + g_mt + 4*MI_4]
3:  mov [rsp + 20], eax         # y
    mov edi, [rsp + 16]
    mov esi, eax
    mov edx, [rsp]
    mov ecx, [rsp + 12]
    M r8d, MI_8
    M r9d, MI_2
    M eax, MI_RADIUS
    push rax
    push rax
    call ui_card_shadow
    add rsp, 16
    mov eax, [rsp + 16]
    mov [rip + sg_rect], eax
    mov eax, [rsp + 20]
    mov [rip + sg_rect + 4], eax
    mov eax, [rsp]
    mov [rip + sg_rect + 8], eax
    mov eax, [rsp + 12]
    mov [rip + sg_rect + 12], eax
    # the signature: before the parameter, the parameter, after it
    mov edi, [rsp + 16]
    add edi, [rip + g_mt + 4*MI_8]
    mov esi, [rsp + 20]
    add esi, [rip + g_mt + 4*MI_6]
    mov edx, [rsp + 4]
    mov ecx, [rip + g_face_code + FACE_lineh]
    call gfx_clip_push
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 20]
    add esi, [rip + g_mt + 4*MI_6]
    mov edx, [rip + g_face_code + FACE_lineh]
    call baseline
    mov [rsp + 24], eax
    mov eax, [rsp + 16]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 28], eax         # the pen
    cmp dword ptr [rsp + 40], 0
    je 31f
    lea rdi, [rip + g_face_code]
    mov esi, eax
    mov edx, [rsp + 24]
    lea rcx, [rip + sg_ctr]
    mov r8d, [rip + sg_ctrlen]
    COLOR r9d, T_MUTED
    call text_draw
    mov eax, [rsp + 16]
    add eax, [rip + g_mt + 4*MI_8]
    add eax, [rsp + 40]
    mov [rsp + 28], eax
31: movsxd rbx, dword ptr [rip + sg_from]
    movsxd rax, dword ptr [rip + sg_to]
    test rbx, rbx
    jns 4f
    mov rbx, r13                # no parameter: all of it before one
    mov rax, r13
4:  mov [rsp + 32], rax
    mov rdx, rbx
    mov rcx, r12
    COLOR r9d, T_FG
    call sg_run
    mov rdx, [rsp + 32]
    sub rdx, rbx
    lea rcx, [r12 + rbx]
    COLOR r9d, T_ACCENT
    call sg_run
    mov rax, [rsp + 32]
    mov rdx, r13
    sub rdx, rax
    lea rcx, [r12 + rax]
    COLOR r9d, T_FG
    call sg_run
    call gfx_clip_pop
    # the documentation
    test r14, r14
    jz 9f
    mov eax, 1
    push rax
    mov eax, SG_LINES_MAX
    push rax
    COLOR eax, T_MUTED
    push rax
    mov eax, [rip + g_face_small + FACE_lineh]
    push rax
    lea rdi, [rip + g_face_small]
    mov rsi, r15
    mov rdx, r14
    mov ecx, [rsp + 4 + 32]
    mov r8d, [rsp + 16 + 32]
    add r8d, [rip + g_mt + 4*MI_8]
    mov r9d, [rsp + 20 + 32]
    add r9d, [rip + g_mt + 4*MI_6]
    add r9d, [rip + g_face_code + FACE_lineh]
    add r9d, [rip + g_mt + 4*MI_4]
    call wrap
    add rsp, 32
9:  EPILOGUE

# sg_run(rcx ptr, rdx len, r9d argb): a piece of the signature at the pen ([rsp + 28] of sg_draw's
# frame), the pen moved past it
sg_run:
    test rdx, rdx
    jz 9f
    push rbx
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 8 + 8 + 28]
    mov r8, rdx
    mov edx, [rsp + 8 + 8 + 24]
    call text_draw
    mov [rsp + 8 + 8 + 28], eax
    pop rbx
9:  ret

# ---------------- signature-list (language features) ----------------

# sgl_set(body, len): "N ACTIVE", then N records "FROM TO SIG_LEN DOC_LEN" + SIG + DOC (at most 32);
# an empty or broken body hides the help
sgl_set:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov dword ptr [rip + sg_count], 0
    test r13, r13
    jz 8f
    cmp r13, SG_BODY_MAX
    ja 8f
    mov [rip + ps_ptr], r12
    lea rax, [r12 + r13]
    mov [rip + ps_end], rax
    call ps_line
    test eax, eax
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 32
    ja 8f
    mov r14, rax                # N
    call ps_num
    test edx, edx
    jz 8f
    mov r15, rax                # ACTIVE
    call ps_eol
    test eax, eax
    jz 8f
    # every record whole, its signature one line
    mov rbx, r14
1:  test rbx, rbx
    jz 2f
    dec rbx
    call ps_line
    test eax, eax
    jz 8f
    call ps_snum
    test edx, edx
    jz 8f
    call ps_snum
    test edx, edx
    jz 8f
    call ps_num
    test edx, edx
    jz 8f
    mov [rip + sgl_tmp], rax
    call ps_num
    test edx, edx
    jz 8f
    mov [rip + sgl_tmp + 8], rax
    call ps_eol
    test eax, eax
    jz 8f
    mov rax, [rip + sgl_tmp]
    add rax, [rip + sgl_tmp + 8]
    mov rcx, [rip + ps_end]
    sub rcx, [rip + ps_ptr]
    cmp rax, rcx
    ja 8f
    mov rdi, [rip + ps_ptr]
    mov rsi, [rip + sgl_tmp]
    call one_line
    test eax, eax
    jz 8f
    mov rax, [rip + sgl_tmp]
    add rax, [rip + sgl_tmp + 8]
    add [rip + ps_ptr], rax
    jmp 1b
2:  mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne 8f
    lea rdi, [rip + sg_list]
    call sb_clear
    lea rdi, [rip + sg_list]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov [rip + sg_count], r14d
    cmp r15, r14
    jb 3f
    xor r15d, r15d
3:  mov edi, r15d
    call sgl_show
    EPILOGUE
8:  mov dword ptr [rip + sg_open], 0
    EPILOGUE

# sgl_show(i): signature i of sg_list is the one the help shows (as a 12c answer through sg_set),
# with "i+1/N" before it
sgl_show:
    PROLOGUE
    mov r12d, edi
    mov [rip + sg_index], edi
    mov rax, [rip + sg_list + SB_ptr]
    mov [rip + ps_ptr], rax
    add rax, [rip + sg_list + SB_len]
    mov [rip + ps_end], rax
    call ps_line                # past "N ACTIVE"
    mov rax, [rip + ps_lend]
    inc rax
    mov [rip + ps_ptr], rax
    mov ebx, -1
1:  inc ebx
    call ps_line
    test eax, eax
    jz 9f
    call ps_snum
    mov r13, rax                # FROM
    call ps_snum
    mov r14, rax                # TO
    call ps_num
    mov r15, rax                # SIG_LEN
    call ps_num
    mov [rip + sgl_tmp + 8], rax    # DOC_LEN
    call ps_eol
    cmp ebx, r12d
    je 2f
    mov rax, r15
    add rax, [rip + sgl_tmp + 8]
    add [rip + ps_ptr], rax
    jmp 1b
2:  # "FROM TO" LF SIG LF DOC
    lea rdi, [rip + cp_res_line]
    call sb_clear
    mov rax, r13
    test rax, rax
    jns 21f
    lea rdi, [rip + cp_res_line]
    mov esi, '-'
    call sb_push_byte
    mov eax, 1
21: lea rdi, [rip + cp_res_line]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + cp_res_line]
    mov esi, ' '
    call sb_push_byte
    mov rax, r14
    test rax, rax
    jns 22f
    lea rdi, [rip + cp_res_line]
    mov esi, '-'
    call sb_push_byte
    mov eax, 1
22: lea rdi, [rip + cp_res_line]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + cp_res_line]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cp_res_line]
    mov rsi, [rip + ps_ptr]
    mov rdx, r15
    call sb_push
    lea rdi, [rip + cp_res_line]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cp_res_line]
    mov rsi, [rip + ps_ptr]
    add rsi, r15
    mov rdx, [rip + sgl_tmp + 8]
    call sb_push
    mov rdi, [rip + cp_res_line + SB_ptr]
    mov rsi, [rip + cp_res_line + SB_len]
    call sg_set
    # the counter
    lea rdi, [rip + sg_ctr]
    lea esi, [r12 + 1]
    call fmt_u64
    lea rcx, [rip + sg_ctr]
    mov byte ptr [rcx + rax], '/'
    lea rdi, [rcx + rax + 1]
    mov rbx, rax
    mov esi, [rip + sg_count]
    call fmt_u64
    lea eax, [rbx + rax + 1]
    mov [rip + sg_ctrlen], eax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ---------------- for the tests ----------------

# FN complete_dump(sb): "complete open=O items=N shown=S sel=I labels=A|B|..." and
# "signature open=O from=F to=T text=SIGNATURE"
FN complete_dump
    PROLOGUE
    mov r12, rdi
    mov rdi, r12
    lea rsi, [rip + .Ld_open]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rip + cp_open]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_items]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + cp_items + VEC_len]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_shown]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rip + cp_nshown]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_sel]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rip + cp_sel]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_labels]
    call sb_push_cstr
    xor ebx, ebx
1:  cmp ebx, [rip + cp_nshown]
    jae 2f
    test ebx, ebx
    jz 11f
    mov rdi, r12
    mov esi, '|'
    call sb_push_byte
11: lea rax, [rip + cp_shown]
    mov edi, [rax + rbx*4]
    call item
    mov rsi, [rax + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov edx, [rax + CI_llen]
    mov rdi, r12
    call sb_push
    inc ebx
    jmp 1b
2:  mov rdi, r12
    call cp_dump_selected       # complete-items: the selected item
    mov rdi, r12
    lea rsi, [rip + .Ld_sig]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rip + sg_open]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_from]
    call sb_push_cstr
    movsxd rax, dword ptr [rip + sg_from]
    test rax, rax
    jns 3f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov eax, 1
3:  mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_to]
    call sb_push_cstr
    movsxd rax, dword ptr [rip + sg_to]
    test rax, rax
    jns 4f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov eax, 1
4:  mov rdi, r12
    mov esi, eax
    call sb_push_u64
    cmp dword ptr [rip + sg_count], 1
    jbe 41f
    mov rdi, r12                # signature-list: " overload=2/3"
    lea rsi, [rip + .Ld_overload]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + sg_ctr]
    mov edx, [rip + sg_ctrlen]
    call sb_push
41: mov rdi, r12
    lea rsi, [rip + .Ld_text]
    call sb_push_cstr
    cmp dword ptr [rip + sg_open], 0
    je 5f
    mov rdi, r12
    mov rsi, [rip + sg_text + SB_ptr]
    mov rdx, [rip + sg_siglen]
    call sb_push
5:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# cp_dump_selected(sb): "\nselected label=L detail=D doc=TEXT resolved=0|1 replace=0|1
# commit=CHARS suffix=S deprecated=0|1 waiting=0|1" (doc with its line breaks as \n)
cp_dump_selected:
    PROLOGUE
    mov r12, rdi
    call selected_item
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + .Ld_selected]
    call sb_push_cstr
    mov rsi, [rbx + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov edx, [rbx + CI_llen]
    mov rdi, r12
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_detail]
    call sb_push_cstr
    mov rsi, [rbx + CI_off]
    add rsi, [rip + cp_bytes + SB_ptr]
    mov eax, [rbx + CI_llen]
    add rsi, rax
    mov eax, [rbx + CI_ilen]
    add rsi, rax
    mov edx, [rbx + CI_dlen]
    mov rdi, r12
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_doc]
    call sb_push_cstr
    mov rdi, rbx
    call item_doc
    mov r13, rax
    mov r14, rdx
1:  test r14, r14
    jz 3f
    movzx esi, byte ptr [r13]
    inc r13
    dec r14
    cmp esi, 10
    jne 2f
    mov rdi, r12
    mov esi, 92
    call sb_push_byte
    mov esi, 'n'
2:  mov rdi, r12
    call sb_push_byte
    jmp 1b
3:  mov rdi, r12
    lea rsi, [rip + .Ld_resolved]
    call sb_push_cstr
    mov esi, [rbx + CI_flags]
    shr esi, 7                  # CF_RESOLVED
    and esi, 1
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_replace]
    call sb_push_cstr
    mov esi, [rbx + CI_flags]
    shr esi, 8                  # CF_REPLACE
    and esi, 1
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_commit]
    call sb_push_cstr
    test dword ptr [rbx + CI_flags], CF_COMMIT
    jz 4f
    mov rdi, rbx
    lea rsi, [rip + .Lx_commit]
    call item_record
    mov rsi, rax
    mov rdi, r12
    call sb_push
4:  mov rdi, r12
    lea rsi, [rip + .Ld_suffix]
    call sb_push_cstr
    test dword ptr [rbx + CI_flags], CF_SUFFIX
    jz 5f
    mov rdi, rbx
    lea rsi, [rip + .Lx_suffix]
    call item_record
    mov rsi, rax
    mov rdi, r12
    call sb_push
5:  mov rdi, r12
    lea rsi, [rip + .Ld_deprecated]
    call sb_push_cstr
    mov esi, [rbx + CI_flags]
    shr esi, 1                  # CF_DEPRECATED
    and esi, 1
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_waiting]
    call sb_push_cstr
    xor esi, esi
    mov eax, [rbx + CI_serial]
    cmp eax, [rip + cp_wait_serial]
    jne 6f
    inc esi
6:  mov rdi, r12
    call sb_push_u64
9:  EPILOGUE

.bss
.p2align 3
rec_after: .quad 0              # rec_next: where the next EXTRA record starts, the current one's
rec_name: .quad 0               # name and bytes
rec_nlen: .quad 0
rec_body: .quad 0
rec_blen: .quad 0
cp_res_line: .zero SB_SIZE      # a resolve request or an item's bytes being rebuilt
cp_adj: .zero SB_SIZE           # an adjusted item text
ae_n: .quad 0                   # the edits of the item being accepted: start end ptr len
ae_list: .zero 32 * AE_MAX

.section .rodata
.p2align 3
kind_names: .quad .Lck_text, .Lck_method, .Lck_function, .Lck_field, .Lck_variable, .Lck_class
    .quad .Lck_struct, .Lck_interface, .Lck_module, .Lck_property, .Lck_enum, .Lck_keyword
    .quad .Lck_snippet, .Lck_constant, .Lck_value, .Lck_file, .Lck_folder
# the badge's letter and color per kind
kind_letters: .ascii "t\0m\0f\0d\0v\0C\0S\0I\0M\0p\0E\0k\0s\0c\0V\0F\0D\0"
kind_colors: .byte T_MUTED, T_ICON + 5, T_ICON + 5, T_ICON + 4, T_ICON + 4, T_ICON + 1, T_ICON + 1
    .byte T_ICON + 7, T_ICON + 3, T_ICON + 4, T_ICON + 2, T_MUTED, T_ICON + 6, T_ICON + 2
    .byte T_ICON + 4, T_MUTED, T_MUTED
.Lck_text: .asciz "text"
.Lck_method: .asciz "method"
.Lck_function: .asciz "function"
.Lck_field: .asciz "field"
.Lck_variable: .asciz "variable"
.Lck_class: .asciz "class"
.Lck_struct: .asciz "struct"
.Lck_interface: .asciz "interface"
.Lck_module: .asciz "module"
.Lck_property: .asciz "property"
.Lck_enum: .asciz "enum"
.Lck_keyword: .asciz "keyword"
.Lck_snippet: .asciz "snippet"
.Lck_constant: .asciz "constant"
.Lck_value: .asciz "value"
.Lck_file: .asciz "file"
.Lck_folder: .asciz "folder"
.Lv_complete: .asciz "complete"
.Lv_signature: .asciz "signature"
.Lv_signatures: .asciz "signatures"
.Lk_typed: .asciz "typed"
.Lk_trigger: .asciz "trigger"
.Lk_invoked: .asciz "invoked"
.Lk_incomplete: .asciz "incomplete"
.Lk_update: .asciz "update"
.Lx_edit: .asciz "edit"
.Lx_cursor: .asciz "cursor"
.Lx_preselect: .asciz "preselect"
.Lx_deprecated: .asciz "deprecated"
.Lx_adjust: .asciz "adjust"
.Lx_filter: .asciz "filter"
.Lx_suffix: .asciz "suffix"
.Lx_commit: .asciz "commit"
.Lx_after: .asciz "after"
.Lx_signature: .asciz "signature"
.Lx_complete: .asciz "complete"
.Lx_resolve: .asciz "resolve"
.Lx_replace: .asciz "replace"
.Lx_field: .asciz "field"
.Lx_choice: .asciz "choice"
.Lx_detail: .asciz "detail"
.Lx_ellipsis: .asciz "\342\200\246"
.Lv_resolve: .asciz "complete-resolve "
.Ld_open: .asciz "complete open="
.Ld_items: .asciz " items="
.Ld_shown: .asciz " shown="
.Ld_sel: .asciz " sel="
.Ld_labels: .asciz " labels="
.Ld_sig: .asciz "\nsignature open="
.Ld_from: .asciz " from="
.Ld_to: .asciz " to="
.Ld_text: .asciz " text="
.Ld_overload: .asciz " overload="
.Ld_selected: .asciz "\nselected label="
.Ld_detail: .asciz " detail="
.Ld_doc: .asciz " doc="
.Ld_resolved: .asciz " resolved="
.Ld_replace: .asciz " replace="
.Ld_commit: .asciz " commit="
.Ld_suffix: .asciz " suffix="
.Ld_deprecated: .asciz " deprecated="
.Ld_waiting: .asciz " waiting="

# ---------------- native snippet choices ----------------
.text

# The current live top must match the popup's immutable activation snapshot.
cp_choice_check:
    PROLOGUE
    call focused_doc
    test rax, rax
    jz 8f
    cmp rax, [rip + cp_doc]
    jne 8f
    mov rcx, [rax + DOC_id]
    cmp rcx, [rip + cp_doc_id]
    jne 8f
    mov rbx, rax
    call doc_alive
    test eax, eax
    jz 8f
    mov rax, rbx
    mov rcx, [rax + DOC_version]
    cmp rcx, [rip + cp_seen_ver]
    jne 8f
    mov rdi, rax
    call snippet_check
    test rax, rax
    jz 8f
    mov rcx, [rax + SN_identity]
    cmp rcx, [rip + cp_choice_identity]
    jne 8f
    mov rcx, [rax + SN_activation]
    cmp rcx, [rip + cp_choice_activation]
    jne 8f
    mov rcx, [rax + SN_active]
    cmp rcx, [rip + cp_choice_primary]
    jne 8f
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Open only from the editor's own frame. Inactive documents and palettes keep focus.
cp_choice_pending:
    PROLOGUE
    cmp dword ptr [rip + cp_open], 0
    jne 9f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call snippet_check
    test rax, rax
    jz 9f
    cmp qword ptr [rax + SN_choice_pending], 0
    je 9f
    mov qword ptr [rax + SN_choice_pending], 0
    mov rsi, rax
    mov rdi, rbx
    call cp_choice_begin
9:  EPILOGUE

FN cmd_snippet_choose
    PROLOGUE
    call focused_doc
    test rax, rax
    jz 9f
    mov rdi, rax
    call snippet_check
    test rax, rax
    jz 9f
    mov rdi, rax
    call snippet_activate
    call cp_close
9:  EPILOGUE

# Build owned synthetic completion rows. No EXT or mutable snippet pointers are retained.
cp_choice_begin:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    call doc_sync_grammar
    test rax, rax
    js .Lccb_done
    mov rax, [rbx + DOC_language_revision]
    test rax, rax
    jz .Lccb_done
    mov [rip + cp_language_revision], rax
    mov rdi, r12
    call snippet_choice_get
    test rax, rax
    jz .Lccb_done
    mov [rsp], rax              # next option header
    add rdx, rax
    mov [rsp + 8], rdx          # options end
    mov [rsp + 16], rcx         # count
    call cp_close
    inc dword ptr [rip + cp_session]
    mov dword ptr [rip + cp_source], CP_CHOICES
    mov [rip + cp_doc], rbx
    mov rax, [rbx + DOC_id]
    mov [rip + cp_doc_id], rax
    mov rax, [rbx + DOC_version]
    mov [rip + cp_seen_ver], rax
    mov rax, [r12 + SN_identity]
    mov [rip + cp_choice_identity], rax
    mov rax, [r12 + SN_activation]
    mov [rip + cp_choice_activation], rax
    mov rax, [r12 + SN_active]
    mov [rip + cp_choice_primary], rax
    mov qword ptr [rip + cp_qlen], 0
    xor r13d, r13d
.Lccb_row:
    cmp r13, [rsp + 16]
    jae .Lccb_ready
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call snippet_choice_option
    test rcx, rcx
    jz .Lccb_bad
    mov [rsp], rcx
    mov [rsp + 24], rax         # full option bytes
    mov [rsp + 32], rdx
    mov [rsp + 40], rax         # label bytes
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 2f
    cmp rcx, 256
    jae 2f
    cmp byte ptr [rax + rcx], 10
    je 2f
    cmp byte ptr [rax + rcx], 13
    je 2f
    inc rcx
    jmp 1b
2:  cmp rcx, rdx
    jae 4f
3:  test rcx, rcx
    jz 4f
    movzx esi, byte ptr [rax + rcx]
    and esi, 0xc0
    cmp esi, 0x80
    jne 4f
    dec rcx
    jmp 3b
4:  test rcx, rcx
    jnz 6f
    lea rax, [rip + .Lchoice_empty]
    mov ecx, 7
    cmp qword ptr [rsp + 32], 0
    je 5f
    lea rax, [rip + .Lchoice_blank]
    mov ecx, 12
5:  mov [rsp + 40], rax
6:  mov [rsp + 48], rcx
    mov rax, [rip + cp_bytes + SB_len]
    add rax, rcx
    add rax, [rsp + 32]
    jc .Lccb_bad
    cmp rax, SN_BYTES_MAX + 65536
    ja .Lccb_bad
    lea rdi, [rip + cp_items]
    mov esi, CI_SIZE
    call vec_push
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, CI_SIZE
    call memset
    mov rax, [rip + cp_bytes + SB_len]
    mov [r15 + CI_off], rax
    mov rax, [rsp + 48]
    mov [r15 + CI_llen], eax
    mov rax, [rsp + 32]
    mov [r15 + CI_ilen], eax
    mov dword ptr [r15 + CI_kind], 12
    lea rdi, [rip + cp_bytes]
    mov rsi, [rsp + 40]
    mov rdx, [rsp + 48]
    call sb_push
    lea rdi, [rip + cp_bytes]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call sb_push
    lea rax, [rip + cp_shown]
    mov [rax + r13*4], r13d
    inc r13
    jmp .Lccb_row
.Lccb_ready:
    mov [rip + cp_nshown], r13d
    mov dword ptr [rip + cp_open], 2
    mov dword ptr [rip + cp_hover], -1
    mov dword ptr [rip + g_dirty], 1
    jmp .Lccb_done
.Lccb_bad:
    call cp_close
.Lccb_done:
    EPILOGUE

# Replace the whole active primary. Tab also advances exactly once after mirror propagation.
cp_choice_accept:
    PROLOGUE 64
    mov [rsp], edi             # advance after acceptance
    call cp_choice_check
    test rax, rax
    jz .Lcca_close
    mov rbx, [rip + cp_doc]
    mov rcx, [rax + SN_active]
    imul rcx, rcx, SF_SIZE
    lea r12, [rax + rcx + SN_fields]
    mov eax, [rip + cp_sel]
    cmp eax, [rip + cp_nshown]
    jae .Lcca_close
    lea rcx, [rip + cp_shown]
    mov edi, [rcx + rax*4]
    call item
    mov r14d, [rax + CI_ilen]
    mov r13, [rax + CI_off]
    mov ecx, [rax + CI_llen]
    add r13, rcx
    add r13, [rip + cp_bytes + SB_ptr]
    mov rax, [rbx + DOC_cur]
    mov [rsp + 8], rax
    mov rax, [rbx + DOC_anchor]
    mov [rsp + 16], rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 24], rax
    # Same bytes are a navigation operation, without touching an old undo record.
    mov rdx, [r12 + SF_end]
    sub rdx, [r12 + SF_start]
    cmp rdx, r14
    jne .Lcca_edit
    mov rdi, rbx
    mov rsi, [r12 + SF_start]
    call doc_range
    mov rdi, rax
    mov rsi, r13
    mov rcx, r14
    test rcx, rcx
    jz .Lcca_same
    repe cmpsb
    je .Lcca_same
.Lcca_edit:
    mov rdi, rbx
    call snippet_user_begin
    mov rax, [r12 + SF_start]
    mov [rbx + DOC_anchor], rax
    mov rax, [r12 + SF_end]
    mov [rbx + DOC_cur], rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov ecx, EK_OTHER
    call ed_insert
    mov rdi, rbx
    call snippet_user_end
    mov rax, [rsp + 24]
    cmp rax, [rbx + DOC_undo + VEC_len]
    jae .Lcca_next
    imul rax, rax, UR_SIZE
    add rax, [rbx + DOC_undo + VEC_ptr]
    mov rcx, [rsp + 8]
    mov [rax + UR_cur], rcx
    mov rcx, [rsp + 16]
    mov [rax + UR_anchor], rcx
    jmp .Lcca_next
.Lcca_same:
    mov rax, [r12 + SF_end]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
.Lcca_next:
    call cp_close
    cmp dword ptr [rsp], 0
    je 1f
    mov rdi, rbx
    mov esi, 1
    call snippet_step
1:  mov rdi, rbx
    mov rsi, [rsp + 24]
    call snippet_record_after
    call ed_touch
    EPILOGUE
.Lcca_close:
    call cp_close
    EPILOGUE
.section .rodata
.Lchoice_empty: .ascii "(empty)"
.Lchoice_blank: .ascii "(blank line)"
