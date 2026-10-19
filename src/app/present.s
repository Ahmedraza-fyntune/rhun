# editor presentation: asking providers. The active document's folding ranges, semantic tokens,
# inlay hints, code lens, colors and highlights are asked for when it becomes active, after edits
# (each kind after its own pause), and after a scroll that leaves the lines a kind was asked for.
# One request per (document, kind, provider) is out at a time: a newer one withdraws the older
# (`0 cancel`). Requests go out from present_tick, never from the reply pump; answers only change
# state and set g_dirty. Every request is tracked by the query engine (query.s, QO_PRESENT).
#
# Single-provider kinds (folding, tokens, highlights) use the language's provider (v1.1 single-
# provider selection, never a chooser for these automatic uses); hints, lens and colors merge
# every matching provider. An answer about an older version is moved onto the current text
# through the edit tape (edtape.s).
.include "rhun.inc"

.equ PQ_FOLDING, 0
.equ PQ_TOKENS, 1
.equ PQ_HINTS, 2
.equ PQ_LENS, 3
.equ PQ_COLORS, 4
.equ PQ_HIGHLIGHTS, 5
.equ PQ_COUNT, 6
.equ PQR_MAX, 64                 # presentation requests out at once

# a kind
STRUCT
F PQK_verb, 8                   # the request's verb
F PQK_reply, 8                  # fn(doc, ext, body, len, PQR*) -> eax 1 applied, 0 dropped
F PQK_args, 8                   # fn(sb, doc, l1l2*): the line's fields after DOC VERSION, or 0
F PQK_pv, 8                     # EXT offset of its [provides] key
F PQK_feat, 4
F PQK_pp, 4                     # PP_* kind for one provider per language, -1: every provider
F PQK_pk, 4
F PQK_edit, 4                   # ms after the last edit
F PQK_scroll, 4                 # 1: a scroll out of the asked lines asks again
F PQK_pad, 4
ENDSTRUCT PQK_SIZE

# a request out
STRUCT
F PQR_ext, 8
F PQR_id, 8
F PQR_doc, 8                     # DOC_id
F PQR_kind, 8
F PQR_ver, 8                     # the version it asked about
F PQR_l1, 8                      # the lines it asked about (0-based, inclusive)
F PQR_l2, 8
ENDSTRUCT PQR_SIZE

.bss
.p2align 3
pq_doc: .quad 0                 # DOC_id of the document the kinds are scheduled for (the active one)
pq_ver: .quad 0
pq_due: .zero 8 * PQ_COUNT      # time_ms each kind is due (0: not)
pq_l1: .zero 8 * PQ_COUNT       # the lines each was last asked about
pq_l2: .zero 8 * PQ_COUNT
vis_l1: .quad 0                 # the lines on screen
vis_l2: .quad 0
pqr_vec: .zero VEC_SIZE         # PQR
pq_line: .zero SB_SIZE
.globl g_pq_any
g_pq_any: .long 0               # an extension agreed a kind rhun asks for

.text

# present_kind_row(kind) -> rax PQK*
present_kind_row:
    imul rax, rdi, PQK_SIZE
    lea rcx, [rip + pq_table]
    add rax, rcx
    ret

# present_hello(ext): an extension agreed its features: the active document is asked again
FN present_hello
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12d, PQ_COUNT
    jae 9f
    mov edi, r12d
    call present_kind_row
    mov esi, [rax + PQK_feat]
    mov rdi, rbx
    call ext_feature
    test eax, eax
    jz 2f
    mov dword ptr [rip + g_pq_any], 1
    mov dword ptr [rip + g_dirty], 1    # a frame tells which document is active
    lea rax, [rip + pq_due]
    mov qword ptr [rax + r12*8], 1      # due at once
2:  inc r12d
    jmp 1b
9:  EPILOGUE

# present_frame(doc, first, last): the frame shows these lines of the active document: schedule
FN present_frame
    cmp dword ptr [rip + g_pq_any], 0
    je 0f
    test rdi, rdi
    jnz 1f
0:  ret
1:  PROLOGUE
    mov rbx, rdi
    mov [rip + vis_l1], rsi
    mov [rip + vis_l2], rdx
    cmp qword ptr [rbx + DOC_diff], 0
    jne 9f
    call time_ms
    mov r15, rax
    mov rax, [rbx + DOC_id]
    cmp [rip + pq_doc], rax
    je 2f
    # a newly active document: every kind at once, the last one's requests withdrawn
    mov [rip + pq_doc], rax
    mov rdi, rax
    call present_withdraw_others
    mov rax, [rbx + DOC_version]
    mov [rip + pq_ver], rax
    xor ecx, ecx
11: lea rax, [rip + pq_due]
    mov qword ptr [rax + rcx*8], 1
    lea rax, [rip + pq_l1]
    mov qword ptr [rax + rcx*8], -1
    inc ecx
    cmp ecx, PQ_COUNT
    jb 11b
    jmp 9f
2:  mov rax, [rbx + DOC_version]
    cmp [rip + pq_ver], rax
    je 4f
    # edited: each kind after its pause
    mov [rip + pq_ver], rax
    xor r12d, r12d
3:  mov edi, r12d
    call present_kind_row
    mov ecx, [rax + PQK_edit]
    add rcx, r15
    lea rax, [rip + pq_due]
    mov [rax + r12*8], rcx
    inc r12d
    cmp r12d, PQ_COUNT
    jb 3b
4:  # scrolled out of the lines a kind was asked about
    xor r12d, r12d
5:  mov edi, r12d
    call present_kind_row
    cmp dword ptr [rax + PQK_scroll], 0
    je 6f
    lea rax, [rip + pq_l1]
    mov rcx, [rax + r12*8]
    cmp rcx, -1
    je 6f
    cmp [rip + vis_l1], rcx
    jb 51f
    lea rax, [rip + pq_l2]
    mov rcx, [rax + r12*8]
    cmp [rip + vis_l2], rcx
    jbe 6f
51: lea rax, [rip + pq_due]
    cmp qword ptr [rax + r12*8], 0
    jne 6f
    lea rcx, [r15 + 100]
    mov [rax + r12*8], rcx
6:  inc r12d
    cmp r12d, PQ_COUNT
    jb 5b
9:  EPILOGUE

# present_timeout() -> eax ms until a kind is due, or -1
FN present_timeout
    PROLOGUE
    mov ebx, -1
    cmp dword ptr [rip + g_pq_any], 0
    je 9f
    cmp qword ptr [rip + pq_doc], 0
    je 9f
    call time_ms
    mov r12, rax
    xor ecx, ecx
1:  lea rax, [rip + pq_due]
    mov rdx, [rax + rcx*8]
    inc ecx
    test rdx, rdx
    jz 2f
    sub rdx, r12
    jns 11f
    xor edx, edx
11: cmp ebx, -1
    je 12f
    cmp edx, ebx
    jge 2f
12: mov ebx, edx
2:  cmp ecx, PQ_COUNT
    jb 1b
9:  mov eax, ebx
    EPILOGUE

# present_tick(): the kinds that are due ask their providers
FN present_tick
    PROLOGUE
    cmp dword ptr [rip + g_pq_any], 0
    je 9f
    mov rbx, [rip + g_doc]      # only the active document is asked about
    test rbx, rbx
    jz 9f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + pq_doc]
    jne 9f
    call time_ms
    mov r13, rax
    xor r12d, r12d
1:  lea rax, [rip + pq_due]
    mov rcx, [rax + r12*8]
    test rcx, rcx
    jz 2f
    cmp rcx, r13
    ja 2f
    mov qword ptr [rax + r12*8], 0
    mov rdi, rbx
    mov esi, r12d
    call present_ask
2:  inc r12d
    cmp r12d, PQ_COUNT
    jb 1b
9:  EPILOGUE

# present_ask(doc, kind): its providers are asked (the window: the lines on screen and one screen
# more each way)
present_ask:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov edi, r12d
    call present_kind_row
    mov r13, rax
    # the window
    mov rax, [rip + vis_l2]
    sub rax, [rip + vis_l1]
    inc rax
    mov rcx, [rip + vis_l1]
    sub rcx, rax
    jns 1f
    xor ecx, ecx
1:  mov [rsp], rcx
    mov rcx, [rip + vis_l2]
    add rcx, rax
    mov rdx, [rbx + DOC_nlines]
    dec rdx
    cmp rcx, rdx
    cmova rcx, rdx
    mov [rsp + 8], rcx
    lea rax, [rip + pq_l1]      # a scroll out of the window asks again
    mov rcx, [rsp]
    mov [rax + r12*8], rcx
    lea rax, [rip + pq_l2]
    mov rcx, [rsp + 8]
    mov [rax + r12*8], rcx
    mov esi, [r13 + PQK_pp]
    test esi, esi
    js 3f
    # one provider: the language's
    mov edi, esi
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rbx
    mov edx, r12d
    mov rcx, [rsp]
    mov r8, [rsp + 8]
    call present_send
    jmp 9f
3:  # every matching provider
    xor r14d, r14d
4:  cmp r14, [rip + g_exts + VEC_len]
    jae 9f
    imul r15, r14, EXT_SIZE
    add r15, [rip + g_exts + VEC_ptr]
    inc r14
    cmp dword ptr [r15 + EXT_status], ES_RUNNING
    jne 4b
    mov rdi, r15
    mov esi, [r13 + PQK_feat]
    call ext_feature
    test eax, eax
    jz 4b
    mov rdi, r15
    mov rsi, [r13 + PQK_pv]
    call ext_pv
    test rax, rax
    jz 4b
    mov rdi, rax
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 4b
    mov rdi, r15
    mov rsi, rbx
    mov edx, r12d
    mov rcx, [rsp]
    mov r8, [rsp + 8]
    call present_send
    jmp 4b
9:  EPILOGUE

# present_send(ext, doc, kind, l1, l2): "ID VERB DOC VERSION ARGS", the older one withdrawn
present_send:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], rcx
    mov [rsp + 8], r8
    # its older request goes
    xor r14d, r14d
1:  cmp r14, [rip + pqr_vec + VEC_len]
    jae 3f
    imul r15, r14, PQR_SIZE
    add r15, [rip + pqr_vec + VEC_ptr]
    cmp [r15 + PQR_ext], rbx
    jne 2f
    cmp [r15 + PQR_kind], r13
    jne 2f
    mov rax, [r12 + DOC_id]
    cmp [r15 + PQR_doc], rax
    jne 2f
    mov rdi, rbx
    mov rsi, [r15 + PQR_id]
    call query_withdraw
    mov rdi, r14
    call pqr_drop
    jmp 1b
2:  inc r14
    jmp 1b
3:  cmp qword ptr [rip + pqr_vec + VEC_len], PQR_MAX
    jae 9f
    mov edi, 1
    call query_room
    test eax, eax
    jz 9f
    mov rdi, r12                # answers about this version move through the edit tape
    call pres_ensure
    # the line
    mov edi, r13d
    call present_kind_row
    mov r14, rax
    lea rdi, [rip + pq_line]
    call sb_clear
    lea rdi, [rip + pq_line]
    mov rsi, [r14 + PQK_verb]
    call sb_push_cstr
    lea rdi, [rip + pq_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + pq_line]
    mov rsi, [r12 + DOC_id]
    call sb_push_u64
    lea rdi, [rip + pq_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + pq_line]
    mov rsi, [r12 + DOC_version]
    call sb_push_u64
    mov rax, [r14 + PQK_args]
    test rax, rax
    jz 4f
    lea rdi, [rip + pq_line]
    mov rsi, r12
    lea rdx, [rsp]              # (l1, l2)
    call rax
4:  mov rdi, rbx
    mov rsi, r12
    mov rdx, [rip + pq_line + SB_ptr]
    mov rcx, [rip + pq_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz 9f
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    mov edx, [r14 + PQK_pk]
    mov ecx, QO_PRESENT
    call query_track
    lea rdi, [rip + pqr_vec]
    mov esi, PQR_SIZE
    call vec_push
    mov [rax + PQR_ext], rbx
    mov [rax + PQR_id], r15
    mov rcx, [r12 + DOC_id]
    mov [rax + PQR_doc], rcx
    mov [rax + PQR_kind], r13
    mov rcx, [r12 + DOC_version]
    mov [rax + PQR_ver], rcx
    mov rcx, [rsp]
    mov [rax + PQR_l1], rcx
    mov rcx, [rsp + 8]
    mov [rax + PQR_l2], rcx
9:  EPILOGUE

# present_withdraw_others(doc id): requests about other documents are withdrawn
present_withdraw_others:
    PROLOGUE
    mov rbx, rdi
    xor r14d, r14d
1:  cmp r14, [rip + pqr_vec + VEC_len]
    jae 9f
    imul r15, r14, PQR_SIZE
    add r15, [rip + pqr_vec + VEC_ptr]
    cmp [r15 + PQR_doc], rbx
    je 2f
    mov rdi, [r15 + PQR_ext]
    mov rsi, [r15 + PQR_id]
    call query_withdraw
    mov rdi, r14
    call pqr_drop
    jmp 1b
2:  inc r14
    jmp 1b
9:  EPILOGUE

# pqr_drop(index): the request record goes (the last takes its place)
pqr_drop:
    mov rax, [rip + pqr_vec + VEC_len]
    dec rax
    mov [rip + pqr_vec + VEC_len], rax
    cmp rdi, rax
    je 9f
    imul rsi, rax, PQR_SIZE
    add rsi, [rip + pqr_vec + VEC_ptr]
    imul rdi, rdi, PQR_SIZE
    add rdi, [rip + pqr_vec + VEC_ptr]
    mov edx, PQR_SIZE
    jmp memcpy
9:  ret

# present_reply(ext, id, ok, body, len) -> eax 1 when it answered a presentation request
FN present_reply
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], rcx
    mov [rsp + 8], r8
    xor r14d, r14d
1:  cmp r14, [rip + pqr_vec + VEC_len]
    jae 8f
    imul r15, r14, PQR_SIZE
    add r15, [rip + pqr_vec + VEC_ptr]
    cmp [r15 + PQR_ext], rbx
    jne 2f
    cmp [r15 + PQR_id], r12
    je 3f
2:  inc r14
    jmp 1b
3:  lea rdi, [rsp + 16]         # a copy: the record goes before the answer is read
    mov rsi, r15
    mov edx, PQR_SIZE
    call memcpy
    mov rdi, r14
    call pqr_drop
    test r13d, r13d
    jz 7f                       # an error: nothing changes
    mov rdi, [rsp + 16 + PQR_doc]
    call extproto_doc
    test rax, rax
    jz 7f                       # closed meanwhile
    mov r15, rax
    mov rdi, [rsp + 16 + PQR_kind]
    call present_kind_row
    mov rdi, r15
    mov rsi, rbx
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    lea r8, [rsp + 16]
    call [rax + PQK_reply]
    test eax, eax
    jnz 6f
    mov rdi, [rsp + 16 + PQR_kind]
    call present_kind_row
    mov esi, [rax + PQK_pk]
    mov rdi, rbx
    call query_dropped
    jmp 7f
6:  mov dword ptr [rip + g_dirty], 1
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# present_ext_gone(ext): its requests are forgotten (the query engine forgets its own)
FN present_ext_gone
    PROLOGUE
    mov rbx, rdi
    xor r14d, r14d
1:  cmp r14, [rip + pqr_vec + VEC_len]
    jae 9f
    imul rax, r14, PQR_SIZE
    add rax, [rip + pqr_vec + VEC_ptr]
    cmp [rax + PQR_ext], rbx
    jne 2f
    mov rdi, r14
    call pqr_drop
    jmp 1b
2:  inc r14
    jmp 1b
9:  mov rdi, rbx
    call fold_ext_gone
    EPILOGUE

# ---------------- answers ----------------

# ans_num(rbx cursor, r12 end) -> rax the decimal number at the cursor, edx 1 (0: none); the cursor
# moves past it and one separator (space or line feed)
ans_num:
    xor eax, eax
    xor edx, edx
1:  cmp rbx, r12
    jae 3f
    movzx ecx, byte ptr [rbx]
    sub ecx, '0'
    cmp ecx, 9
    ja 2f
    imul rax, rax, 10
    add rax, rcx
    inc rbx
    mov edx, 1
    jmp 1b
2:  test edx, edx
    jz 3f
    movzx ecx, byte ptr [rbx]
    cmp ecx, ' '
    je 21f
    cmp ecx, 10
    jne 3f
21: inc rbx
3:  ret

# ans_word(rbx cursor, r12 end) -> rax, rdx a word up to the next space or line feed (passed)
ans_word:
    mov rax, rbx
1:  cmp rbx, r12
    jae 2f
    movzx ecx, byte ptr [rbx]
    cmp ecx, ' '
    je 2f
    cmp ecx, 10
    je 2f
    inc rbx
    jmp 1b
2:  mov rdx, rbx
    sub rdx, rax
    cmp rbx, r12
    jae 3f
    inc rbx
3:  ret

# reply_folding(doc, ext, body, len, PQR*) -> eax 1: "N" LF, then N lines "START END KIND TEXT_LEN"
# LF TEXT (lines 1-based; START+1..END can hide). The document's ranges replace the indentation's.
# A range START >= END is left out; a broken answer is dropped whole.
reply_folding:
    PROLOGUE 64
    mov r13, rdi                # doc
    mov [rsp + 48], rsi         # ext
    mov rbx, rdx
    lea r12, [rdx + rcx]        # end
    mov rax, [r8 + PQR_ver]
    mov [rsp], rax              # the version asked about
    lea rdi, [rip + fr_new]
    call fr_vec_clear
    call ans_num
    test edx, edx
    jz 8f
    cmp rax, FRG_MAX
    ja 8f
    mov r14, rax                # N
.Lrf_each:
    test r14, r14
    jz .Lrf_done
    dec r14
    call ans_num
    test edx, edx
    jz 8f
    mov [rsp + 8], rax          # START
    call ans_num
    test edx, edx
    jz 8f
    mov [rsp + 16], rax         # END
    call ans_word               # KIND
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call fr_kind
    mov [rsp + 24], eax
    call ans_num
    test edx, edx
    jz 8f
    cmp rax, FRG_TEXT_MAX
    ja 8f
    mov rcx, r12
    sub rcx, rbx
    cmp rax, rcx
    ja 8f
    mov [rsp + 32], rax         # TEXT_LEN
    mov [rsp + 40], rbx         # TEXT
    xor ecx, ecx                # one line: no control characters
1:  cmp rcx, rax
    jae 2f
    cmp byte ptr [rbx + rcx], 0x20
    jb 8f
    cmp byte ptr [rbx + rcx], 0x7f
    je 8f
    inc rcx
    jmp 1b
2:  add rbx, rax
    mov rax, [rsp + 8]
    test rax, rax
    jz .Lrf_each
    cmp rax, [rsp + 16]
    jae .Lrf_each               # not START < END: left out
    # the lines in the version asked about, moved onto the text: their line feeds now
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call rf_line_end
    test rax, rax
    js 8f
    mov r15, rax
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 16]
    call rf_line_end
    test rax, rax
    js 8f
    cmp rax, r15
    jbe .Lrf_each               # edits since joined them
    mov [rsp + 56], rax
    lea rdi, [rip + fr_new]
    mov esi, FRG_SIZE
    call vec_push
    mov r15, rax
    mov rcx, [rsp + 56]
    mov [r15 + FRG_b], rcx
    mov ecx, [rsp + 24]
    mov [r15 + FRG_kind], ecx
    mov rsi, [rsp + 32]
    test rsi, rsi
    jz 3f
    mov rdi, [rsp + 40]
    call mem_dup
    mov [r15 + FRG_text], rax
3:  mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call rf_line_end
    mov [r15 + FRG_a], rax
    jmp .Lrf_each
.Lrf_done:
    cmp rbx, r12
    jne 8f                      # bytes after the last range
    mov rdi, r13
    mov rsi, [rsp + 48]
    call fold_ranges_set        # fold.s takes fr_new
    mov eax, 1
    EPILOGUE
8:  lea rdi, [rip + fr_new]
    call fr_vec_clear
    xor eax, eax
    EPILOGUE

# rf_line_end(doc, version, line 1-based) -> rax that line's line feed in the current text, or -1
# when the tape no longer reaches the version
rf_line_end:
    PROLOGUE
    mov rbx, rdi
    dec rdx
    xor ecx, ecx
    mov r8d, GR_RIGHT
    call tape_map_lc
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_end
9:  EPILOGUE

# fr_kind(ptr, len) -> eax FRK_*
fr_kind:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdx, [rip + .Lfk_region]
    call str_eq_cstr
    mov ecx, FRK_REGION
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lfk_comment]
    call str_eq_cstr
    mov ecx, FRK_COMMENT
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lfk_imports]
    call str_eq_cstr
    mov ecx, FRK_IMPORTS
    test eax, eax
    jnz 9f
    xor ecx, ecx
9:  mov eax, ecx
    EPILOGUE

# fr_vec_clear(vec): its ranges and their texts go
FN fr_vec_clear
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    imul rax, r12, FRG_SIZE
    add rax, [rbx + VEC_ptr]
    mov rdi, [rax + FRG_text]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
    EPILOGUE

.section .rodata
.p2align 3
# the kinds: verb, reply, args, feature, provider kind, query kind, pause after edits, scroll
pq_table:
    .quad .Lv_folding, reply_folding, 0, EXT_pv_folding
    .long FEAT_FOLDING_RANGES, PP_FOLDING, PK_FOLDING, 500, 0, 0
    .quad .Lv_tokens, reply_none, 0, EXT_pv_semantic_tokens
    .long FEAT_SEMANTIC_TOKENS, PP_TOKENS, PK_TOKENS, 150, 0, 0
    .quad .Lv_hints, reply_none, args_window, EXT_pv_inlay_hints
    .long FEAT_INLAY_HINTS, -1, PK_HINTS, 250, 1, 0
    .quad .Lv_lens, reply_none, args_window, EXT_pv_code_lens
    .long FEAT_CODE_LENS, -1, PK_LENS, 500, 1, 0
    .quad .Lv_colors, reply_none, args_window, EXT_pv_colors
    .long FEAT_DOC_COLORS, -1, PK_COLORS, 500, 1, 0
    .quad .Lv_highlights, reply_none, 0, EXT_pv_highlights
    .long FEAT_DOC_HIGHLIGHTS, PP_HIGHLIGHTS, PK_HIGHLIGHTS, 250, 0, 0
.Lv_folding: .asciz "folding-ranges"
.Lv_tokens: .asciz "semantic-tokens"
.Lv_hints: .asciz "inlay-hints"
.Lv_lens: .asciz "code-lens"
.Lv_colors: .asciz "colors"
.Lv_highlights: .asciz "highlights"
.Lfk_region: .asciz "region"
.Lfk_comment: .asciz "comment"
.Lfk_imports: .asciz "imports"

.text
# reply_none(...) -> eax 0: a kind not taken yet
reply_none:
    xor eax, eax
    ret

# args_window(sb, doc, l1l2*): " L1 L2" (1-based)
args_window:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r12]
    inc rsi
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r12 + 8]
    inc rsi
    call sb_push_u64
    EPILOGUE

.bss
.p2align 3
.globl fr_new
fr_new: .zero VEC_SIZE          # an answer's ranges, before fold.s takes them
