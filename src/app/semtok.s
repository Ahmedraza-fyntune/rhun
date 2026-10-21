# editor presentation: semantic tokens (feature semantic-tokens). An extension registers legends
# (semantic-legend: its token types and modifiers, each optionally NAME=EFFECT); rhun asks the
# language's provider for the active document's tokens (present.s: when it becomes active and
# 150 ms after edits, with the last result's id so the provider may answer a delta) and draws each
# token's class over its line's syntax classes, with strike, underline and faded effects.
#
# The last result's ints are kept as a delta's base; the tokens themselves are positions (STK, sorted
# by start) that move with edits until the next answer. An answer about an older version only
# updates the base: the request the edit scheduled brings positions for the current text.
.include "rhun.inc"

# a legend
STRUCT
F SLG_owner, 8                  # EXT*, 0 for a free slot
F SLG_ntypes, 4
F SLG_nmods, 4
F SLG_name, 72                  # cstr, 1-64 bytes
F SLG_tcls, SEMT_TYPES            # a type's class, STK_KEEP: the syntax class stays
F SLG_tfx, SEMT_TYPES             # a type's effects (STKF_*)
F SLG_mcls, SEMT_MODS             # a modifier's class effect: STK_KEEP none, MC_LIBRARY defaultLibrary's
F SLG_mfx, SEMT_MODS              # a modifier's effects
ENDSTRUCT SLG_SIZE
.equ MC_LIBRARY, 254            # function, type, variable become builtin

# a document's tokens (PRS_tks)
STRUCT
F STS_ext, 8                    # the provider the result came from
F STS_legend, 8                 # the result's legend: its index + 1
F STS_ints, VEC_SIZE            # u32: the last result's ints, a delta's base
F STS_toks, VEC_SIZE            # STK, sorted by start
F STS_result, 72                # the last result's id, "" for none (no delta asked for)
ENDSTRUCT STS_SIZE

.bss
.p2align 3
.globl g_legends
g_legends: .zero VEC_SIZE       # SLG
ints_new: .zero VEC_SIZE        # an answer's ints being built
ov_buf: .zero SB_SIZE           # a line's classes with its tokens over them
.globl g_tkfx_n, g_tkfx_doc, g_tkfx_line
g_tkfx_doc: .quad 0             # the line the effects below are for
g_tkfx_line: .quad 0
g_tkfx_n: .quad 0
.globl g_tkfx
g_tkfx: .zero SEMT_FX_MAX * 24     # effects of the line's tokens: start, end (offsets), fx, class
lg_scratch: .zero SLG_SIZE

.text

# ---------------- legends ----------------

# FN h_semantic_legend(): ID semantic-legend LEGEND LEN + body: line 1 the token types, line 2 the
# modifiers, NAME or NAME=EFFECT separated by spaces
FN h_semantic_legend
    PROLOGUE 48
    call xp_cur
    mov rbx, rax
    FEAT_TEST rbx, FEAT_SEMANTIC_TOKENS
    jz .Lhl_unknown
    call xp_nfields
    cmp rax, 4
    jb .Lhl_syntax
    mov edi, 2
    call xp_field
    mov r12, rax                # legend name
    mov r13, rdx
    mov rdi, rax
    mov rsi, rdx
    call id_ok
    test eax, eax
    jz .Lhl_syntax
    lea rdi, [rip + lg_scratch]
    xor esi, esi
    mov edx, SLG_SIZE
    call memset
    call xp_body
    mov r14, rax
    lea r15, [rax + rdx]        # end
    # line 1: types
    mov rdi, r14
    mov rsi, r15
    xor edx, edx
    call lg_line
    test rax, rax
    js .Lhl_fail
    mov r14, rax
    mov rdi, r14
    mov rsi, r15
    mov edx, 1
    call lg_line
    test rax, rax
    js .Lhl_fail
    cmp rax, r15
    jne .Lhl_syntax             # a third line
    # replace this extension's legend of that name, or take a slot
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call lg_find
    test rax, rax
    jnz 5f
    xor ecx, ecx                # its legends
    xor edx, edx
1:  cmp rdx, [rip + g_legends + VEC_len]
    jae 2f
    imul rax, rdx, SLG_SIZE
    add rax, [rip + g_legends + VEC_ptr]
    inc rdx
    cmp [rax + SLG_owner], rbx
    jne 1b
    inc ecx
    jmp 1b
2:  cmp ecx, SEMT_LEGENDS
    jae .Lhl_toobig
    xor edx, edx                # a free slot
3:  cmp rdx, [rip + g_legends + VEC_len]
    jae 4f
    imul rax, rdx, SLG_SIZE
    add rax, [rip + g_legends + VEC_ptr]
    inc rdx
    cmp qword ptr [rax + SLG_owner], 0
    je 5f
    jmp 3b
4:  lea rdi, [rip + g_legends]
    mov esi, SLG_SIZE
    call vec_push
5:  mov [rsp], rax
    mov rdi, rax
    lea rsi, [rip + lg_scratch]
    mov edx, SLG_SIZE
    call memcpy
    mov rax, [rsp]
    mov [rax + SLG_owner], rbx
    lea rdi, [rax + SLG_name]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, [rsp]
    mov byte ptr [rax + SLG_name + r13], 0
    call xp_cur_id
    mov rdi, rax
    call xp_reply_ok
    EPILOGUE
.Lhl_fail:
    cmp rax, -2
    je .Lhl_toobig
.Lhl_syntax:
    call xp_cur_id
    mov rdi, rax
    call xp_reply_syntax
    EPILOGUE
.Lhl_toobig:
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_toobig_legend]
    call xp_reply_error
    EPILOGUE
.Lhl_unknown:
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_unknown]
    call xp_reply_error
    EPILOGUE

# lg_line(ptr, end, mods) -> rax the next line's start, -1 for a bad name or effect, -2 for too
# many: one line of names into lg_scratch's types (mods 0) or modifiers (1)
lg_line:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    xor r15d, r15d              # names
.Lll_word:
    cmp rbx, r12
    jae .Lll_done
    movzx eax, byte ptr [rbx]
    cmp eax, 10
    je .Lll_eol
    cmp eax, ' '
    jne 1f
    inc rbx
    jmp .Lll_word
1:  mov r13, rbx                # the word
2:  cmp rbx, r12
    jae 3f
    movzx eax, byte ptr [rbx]
    cmp eax, ' '
    je 3f
    cmp eax, 10
    je 3f
    inc rbx
    jmp 2b
3:  mov r14, rbx
    sub r14, r13                # its length
    # NAME[=EFFECT]
    xor ecx, ecx
4:  cmp rcx, r14
    jae 5f
    cmp byte ptr [r13 + rcx], '='
    je 5f
    inc rcx
    jmp 4b
5:  mov [rsp + 8], rcx          # the name's length
    mov rdi, r13
    mov rsi, rcx
    call id_ok
    test eax, eax
    jz .Lll_bad
    mov eax, SEMT_TYPES
    cmp dword ptr [rsp], 0
    je 6f
    mov eax, SEMT_MODS
6:  cmp r15d, eax
    jae .Lll_many
    # the default: rhun's table
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov edx, [rsp]
    call lg_default             # -> eax class, edx effects
    mov [rsp + 16], eax
    mov [rsp + 20], edx
    mov rcx, [rsp + 8]
    cmp rcx, r14
    jae 7f
    # =EFFECT
    lea rdi, [r13 + rcx + 1]
    mov rsi, r14
    sub rsi, rcx
    dec rsi
    call effect_of              # -> eax class or STK_KEEP, edx effects; eax -1 unknown
    cmp eax, -1
    je .Lll_bad
    mov [rsp + 16], eax
    mov [rsp + 20], edx
7:  lea rax, [rip + lg_scratch]
    mov ecx, [rsp + 16]
    mov edx, [rsp + 20]
    cmp dword ptr [rsp], 0
    jne 8f
    mov [rax + SLG_tcls + r15], cl
    mov [rax + SLG_tfx + r15], dl
    inc r15d
    mov [rax + SLG_ntypes], r15d
    jmp .Lll_word
8:  mov [rax + SLG_mcls + r15], cl
    mov [rax + SLG_mfx + r15], dl
    inc r15d
    mov [rax + SLG_nmods], r15d
    jmp .Lll_word
.Lll_eol:
    inc rbx
.Lll_done:
    mov rax, rbx
    EPILOGUE
.Lll_bad:
    mov rax, -1
    EPILOGUE
.Lll_many:
    mov rax, -2
    EPILOGUE

# lg_default(ptr, len, mods) -> eax class (STK_KEEP or MC_LIBRARY), edx effects: rhun's table
lg_default:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test edx, edx
    jnz .Lld_mod
    lea r13, [rip + type_table]
1:  mov rdx, [r13]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add r13, 16
    jmp 1b
2:  mov eax, [r13 + 8]
    xor edx, edx
    EPILOGUE
.Lld_mod:
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lm_deprecated]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov eax, STK_KEEP
    mov edx, STKF_STRIKE
    EPILOGUE
3:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lm_library]
    call str_eq_cstr
    test eax, eax
    jz 8f
    mov eax, MC_LIBRARY
    xor edx, edx
    EPILOGUE
8:  mov eax, STK_KEEP
    xor edx, edx
    EPILOGUE

# effect_of(ptr, len) -> eax a class (STK_KEEP for a style or -), edx effects; eax -1 when unknown
effect_of:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13d, C_COUNT
    jae 2f
    lea rax, [rip + class_names]
    mov rdx, [rax + r13*8]
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 7f
    inc r13d
    jmp 1b
2:  xor r13d, r13d
3:  lea rax, [rip + style_names]
    mov rdx, [rax + r13*8]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 4f
    inc r13d
    jmp 3b
4:  lea rax, [rip + style_bits]
    movzx edx, byte ptr [rax + r13]
    mov eax, STK_KEEP
    EPILOGUE
7:  mov eax, r13d
    xor edx, edx
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# id_ok(ptr, len) -> eax 1 for 1-64 bytes of [A-Za-z0-9_.-]
id_ok:
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 64
    ja 9f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 8f
    movzx edx, byte ptr [rdi + rcx]
    inc rcx
    cmp dl, '_'
    je 1b
    cmp dl, '-'
    je 1b
    cmp dl, '.'
    je 1b
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 1b
    or dl, 0x20
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    jbe 1b
    ret
8:  mov eax, 1
9:  ret

# lg_find(ext, ptr, len) -> rax SLG* of its legend of that name, or 0
lg_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rip + g_legends + VEC_len]
    jae 8f
    imul r15, r14, SLG_SIZE
    add r15, [rip + g_legends + VEC_ptr]
    inc r14
    cmp [r15 + SLG_owner], rbx
    jne 1b
    mov rdi, r12
    mov rsi, r13
    lea rdx, [r15 + SLG_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- requests ----------------

# FN semtok_huge(doc) -> eax 1 when the document is asked about in ranges (200,000 lines, 8 MB)
FN semtok_huge
    xor eax, eax
    cmp qword ptr [rdi + DOC_nlines], SEMT_HUGE_LINES
    ja 1f
    push rdi
    call doc_len
    pop rdi
    cmp rax, SEMT_HUGE_BYTES
    seta al
    movzx eax, al
    ret
1:  mov eax, 1
    ret

# FN semtok_args(sb, doc, l1l2*, ext): " PREV": the last result's id from that provider, or "-";
# for a document asked about in ranges " L1 L2"
FN semtok_args
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, r12
    call semtok_huge
    test eax, eax
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call present_args_window
    EPILOGUE
1:  mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rax, [r12 + DOC_pres]
    test rax, rax
    jz 2f
    mov rax, [rax + PRS_tks]
    test rax, rax
    jz 2f
    cmp [rax + STS_ext], r14
    jne 2f
    cmp byte ptr [rax + STS_result], 0
    je 2f
    lea rsi, [rax + STS_result]
    mov rdi, rbx
    call sb_push_cstr
    EPILOGUE
2:  mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
    EPILOGUE

# sts_of(doc) -> rax the document's STS, made on first use
sts_of:
    PROLOGUE
    mov rbx, rdi
    call pres_ensure
    mov r12, rax
    mov rax, [r12 + PRS_tks]
    test rax, rax
    jnz 9f
    mov edi, STS_SIZE
    call mem_alloc
    mov [r12 + PRS_tks], rax
9:  EPILOGUE

# ---------------- answers ----------------

# FN semtok_reply(doc, ext, body, len, version) -> eax 1 taken, 0 dropped: "RESULT LEGEND full N" LF
# and 5N ints, "RESULT LEGEND delta K" LF and K edits "START DEL N" LF + N ints, or "RESULT LEGEND
# range N" LF and 5N ints
FN semtok_reply
    PROLOGUE 64
    mov r13, rdi                # doc
    mov [rsp], rsi              # ext
    mov rbx, rdx
    lea r12, [rdx + rcx]
    mov [rsp + 8], r8           # the version asked about
    mov qword ptr [rip + ints_new + VEC_len], 0
    call present_word           # RESULT
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    cmp rdx, 1
    jne 1f
    cmp byte ptr [rax], '-'
    je 2f
1:  mov rdi, rax
    mov rsi, rdx
    call id_ok
    test eax, eax
    jz .Lsr_drop
2:  call present_word           # LEGEND
    mov rdi, [rsp]
    mov rsi, rax
    call lg_find
    test rax, rax
    jz .Lsr_drop
    sub rax, [rip + g_legends + VEC_ptr]
    xor edx, edx
    mov ecx, SLG_SIZE
    div rcx
    inc rax
    mov [rsp + 32], rax         # its index + 1
    call present_word           # MODE
    mov [rsp + 40], rax
    mov [rsp + 48], rdx
    call present_num            # N or K
    test edx, edx
    jz .Lsr_drop
    mov r14, rax
    mov rdi, [rsp + 40]
    mov rsi, [rsp + 48]
    lea rdx, [rip + .Lmode_delta]
    call str_eq_cstr
    test eax, eax
    jnz .Lsr_delta
    mov rdi, [rsp + 40]
    mov rsi, [rsp + 48]
    lea rdx, [rip + .Lmode_full]
    call str_eq_cstr
    test eax, eax
    jnz 3f
    mov rdi, [rsp + 40]
    mov rsi, [rsp + 48]
    lea rdx, [rip + .Lmode_range]
    call str_eq_cstr
    test eax, eax
    jz .Lsr_drop
    mov qword ptr [rsp + 24], 0 # a range's result is no delta's base
3:  cmp r14, SEMT_TOKENS
    ja .Lsr_drop
    imul r14, r14, 5
    call ints_read
    test eax, eax
    jz .Lsr_drop
    jmp .Lsr_have
.Lsr_delta:
    cmp r14, SEMT_DELTA
    ja .Lsr_drop
    call delta_apply
    test eax, eax
    jz .Lsr_broken
.Lsr_have:
    # nothing after the ints but white space
4:  cmp rbx, r12
    jae 5f
    movzx eax, byte ptr [rbx]
    inc rbx
    cmp eax, ' '
    je 4b
    cmp eax, 10
    je 4b
    jmp .Lsr_drop
5:  mov rdi, r13
    call sts_of
    mov r15, rax
    # the new base
    mov rax, [rip + ints_new + VEC_ptr]
    mov rcx, [r15 + STS_ints + VEC_ptr]
    mov [r15 + STS_ints + VEC_ptr], rax
    mov [rip + ints_new + VEC_ptr], rcx
    mov rax, [rip + ints_new + VEC_len]
    mov [r15 + STS_ints + VEC_len], rax
    mov rax, [rip + ints_new + VEC_cap]
    mov rcx, [r15 + STS_ints + VEC_cap]
    mov [r15 + STS_ints + VEC_cap], rax
    mov [rip + ints_new + VEC_cap], rcx
    mov qword ptr [rip + ints_new + VEC_len], 0
    mov rax, [rsp]
    mov [r15 + STS_ext], rax
    mov rax, [rsp + 32]
    mov [r15 + STS_legend], rax
    mov byte ptr [r15 + STS_result], 0
    mov rdx, [rsp + 24]
    test rdx, rdx
    jz 6f
    mov rsi, [rsp + 16]
    cmp rdx, 1
    jne 51f
    cmp byte ptr [rsi], '-'
    je 6f
51: lea rdi, [r15 + STS_result]
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    mov byte ptr [r15 + STS_result + rdx], 0
6:  # positions, when the answer is about the current text
    mov rax, [rsp + 8]
    cmp rax, [r13 + DOC_version]
    jne 7f
    mov rdi, r13
    mov rsi, r15
    call toks_build
    mov rdi, r13
    call pres_touch
7:  mov eax, 1
    EPILOGUE
.Lsr_broken:
    # a delta rhun cannot apply: the tokens go and the next request asks with -
    mov rdi, r13
    call sts_of
    mov byte ptr [rax + STS_result], 0
    mov qword ptr [rax + STS_toks + VEC_len], 0
    mov qword ptr [rax + STS_ints + VEC_len], 0
    mov rdi, r13
    call pres_touch
    mov edi, PQ_TOKENS
    call present_due_now
.Lsr_drop:
    xor eax, eax
    EPILOGUE

# ints_read(rbx cursor, r12 end, r14 count) -> eax 1 when r14 u32 ints were appended to ints_new
ints_read:
    push r15
    mov r15, r14
1:  test r15, r15
    jz 8f
    call present_num
    test edx, edx
    jz 9f
    mov rcx, 0xffffffff
    cmp rax, rcx
    ja 9f
    push rax
    push rax
    lea rdi, [rip + ints_new]
    mov esi, 4
    call vec_push
    pop rcx
    pop rcx
    mov [rax], ecx
    dec r15
    jmp 1b
8:  mov eax, 1
    pop r15
    ret
9:  xor eax, eax
    pop r15
    ret

# delta_apply(rbx cursor, r12 end, r13 doc, r14 K) -> eax 1 when the K edits, applied to the
# document's base, made ints_new (rbx moves on)
delta_apply:
    push r15
    push r14
    push rbp
    sub rsp, 16                 # [rsp] the base's ints copied so far, [rsp + 8] START
    mov rax, [r13 + DOC_pres]
    test rax, rax
    jz 8f
    mov r15, [rax + PRS_tks]
    test r15, r15
    jz 8f
    cmp byte ptr [r15 + STS_result], 0
    je 8f                       # no base
    mov qword ptr [rsp], 0
.Lda_edit:
    test r14, r14
    jz .Lda_tail
    dec r14
    call present_num            # START
    test edx, edx
    jz 8f
    cmp rax, [rsp]
    jb 8f                       # not sorted, or overlapping
    cmp rax, [r15 + STS_ints + VEC_len]
    ja 8f
    mov [rsp + 8], rax
    call present_num            # DEL
    test edx, edx
    jz 8f
    mov rbp, rax
    mov rcx, [rsp + 8]
    add rcx, rbp
    cmp rcx, [r15 + STS_ints + VEC_len]
    ja 8f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call copy_old
    mov rcx, [rsp + 8]
    add rcx, rbp
    mov [rsp], rcx              # DEL skipped
    call present_num            # N
    test edx, edx
    jz 8f
    push r14
    push r14
    mov r14, rax
    call ints_read
    pop r14
    pop r14
    test eax, eax
    jz 8f
    cmp qword ptr [rip + ints_new + VEC_len], SEMT_TOKENS * 5
    ja 8f
    jmp .Lda_edit
.Lda_tail:
    mov rdi, [rsp]
    mov rsi, [r15 + STS_ints + VEC_len]
    call copy_old
    mov rax, [rip + ints_new + VEC_len]
    cmp rax, SEMT_TOKENS * 5
    ja 8f
    xor edx, edx
    mov ecx, 5
    div rcx
    test rdx, rdx
    jnz 8f
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 16
    pop rbp
    pop r14
    pop r15
    ret

# copy_old(from, to; r15 STS): the base's ints [from, to) appended to ints_new
copy_old:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  cmp rbx, r12
    jae 9f
    lea rdi, [rip + ints_new]
    mov esi, 4
    call vec_push
    mov rcx, [r15 + STS_ints + VEC_ptr]
    mov ecx, [rcx + rbx*4]
    mov [rax], ecx
    inc rbx
    jmp 1b
9:  EPILOGUE

# toks_build(doc, STS): the base's ints as positions in the text
toks_build:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [r12 + STS_toks + VEC_len], 0
    mov rax, [r12 + STS_legend]
    dec rax
    imul rax, rax, SLG_SIZE
    add rax, [rip + g_legends + VEC_ptr]
    mov [rsp], rax              # the legend
    xor r13d, r13d              # int index
    xor r14d, r14d              # line
    xor r15d, r15d              # column
    mov qword ptr [rsp + 8], -1 # the line whose start and end are below
.Ltb_tok:
    lea rax, [r13 + 5]
    cmp rax, [r12 + STS_ints + VEC_len]
    ja 9f
    mov rsi, [r12 + STS_ints + VEC_ptr]
    lea rsi, [rsi + r13*4]
    add r13, 5
    mov eax, [rsi]              # DLINE
    mov ecx, [rsi + 4]          # DCOL
    test eax, eax
    jz 1f
    add r14, rax
    mov r15, rcx
    jmp 2f
1:  add r15, rcx
2:  cmp r14, [rbx + DOC_nlines]
    jae 9f
    cmp r14, [rsp + 8]
    je 3f
    mov [rsp + 8], r14
    mov rdi, rbx
    mov rsi, r14
    call doc_line_start
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, r14
    call doc_line_end
    mov [rsp + 24], rax
    mov rsi, [r12 + STS_ints + VEC_ptr]
    lea rsi, [rsi + r13*4 - 20]
3:  mov rax, [rsp + 16]
    add rax, r15                # start
    cmp rax, [rsp + 24]
    jae .Ltb_tok
    mov [rsp + 32], rax
    mov ecx, [rsi + 8]          # LEN
    add rcx, rax
    cmp rcx, [rsp + 24]
    jbe 4f
    mov rcx, [rsp + 24]
4:  mov [rsp + 40], rcx
    # class and effects
    mov eax, [rsi + 12]         # TYPE
    mov rdx, [rsp]
    cmp eax, [rdx + SLG_ntypes]
    jae .Ltb_tok
    movzx r8d, byte ptr [rdx + SLG_tcls + rax]
    movzx r9d, byte ptr [rdx + SLG_tfx + rax]
    mov r10d, [rsi + 16]        # MODS
    test r10d, r10d
    jz 6f
    xor ecx, ecx
    xor r11d, r11d              # a modifier's class taken
5:  cmp ecx, [rdx + SLG_nmods]
    jae 6f
    cmp ecx, 32
    jae 6f
    bt r10d, ecx
    jnc 55f
    movzx eax, byte ptr [rdx + SLG_mfx + rcx]
    or r9d, eax
    test r11d, r11d
    jnz 55f
    movzx eax, byte ptr [rdx + SLG_mcls + rcx]
    cmp eax, STK_KEEP
    je 55f
    cmp eax, MC_LIBRARY
    jne 54f
    cmp r8d, C_FUNCTION
    je 53f
    cmp r8d, C_TYPE
    je 53f
    cmp r8d, C_VARIABLE
    jne 55f
53: mov eax, C_BUILTIN
54: mov r8d, eax
    mov r11d, 1
55: inc ecx
    jmp 5b
6:  cmp r8d, STK_KEEP
    jne 7f
    test r9d, r9d
    jz .Ltb_tok                 # nothing to draw
7:  # a start inside a character is dropped; an end inside one moves back to its start
    mov [rsp + 44], r8b
    mov [rsp + 45], r9b
    mov rdi, rbx
    mov rsi, [rsp + 32]
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je .Ltb_tok
71: mov rsi, [rsp + 40]
    cmp rsi, [rsp + 24]
    jae 72f
    mov rdi, rbx
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    jne 72f
    dec qword ptr [rsp + 40]
    jmp 71b
72: mov rax, [rsp + 40]
    cmp rax, [rsp + 32]
    jbe .Ltb_tok
    lea rdi, [r12 + STS_toks]
    mov esi, STK_SIZE
    call vec_push
    mov rcx, [rsp + 32]
    mov [rax + STK_start], rcx
    mov rdx, [rsp + 40]
    sub rdx, rcx
    mov [rax + STK_len], edx
    movzx ecx, byte ptr [rsp + 44]
    mov [rax + STK_cls], cl
    movzx ecx, byte ptr [rsp + 45]
    mov [rax + STK_fx], cl
    jmp .Ltb_tok
9:  EPILOGUE

# ---------------- edits ----------------

# FN semtok_shift(doc, entry): the tokens move with an edit; text typed inside one joins it, a
# token whose text is deleted goes (it keeps no length)
FN semtok_shift
    mov rax, [rdi + DOC_pres]
    mov rax, [rax + PRS_tks]
    test rax, rax
    jz 9f
    mov rcx, [rax + STS_toks + VEC_len]
    test rcx, rcx
    jz 9f
    push rbx
    push r12
    mov r8, [rax + STS_toks + VEC_ptr]
    mov r9, [rsi + TE_pos]
    mov r10, [rsi + TE_ins]
    mov r11, [rsi + TE_del]
    test r10, r10
    jz .Lss_del
1:  mov rax, [r8 + STK_start]
    cmp rax, r9
    jb 2f
    add rax, r10                # at or after the insert
    mov [r8 + STK_start], rax
    jmp 3f
2:  mov edx, [r8 + STK_len]
    add rdx, rax
    cmp rdx, r9
    jbe 3f
    add [r8 + STK_len], r10d    # inside it
3:  add r8, STK_SIZE
    dec rcx
    jnz 1b
    jmp 8f
.Lss_del:
    lea r12, [r9 + r11]         # the deletion's end
4:  mov rax, [r8 + STK_start]
    mov edx, [r8 + STK_len]
    add rdx, rax                # end
    cmp rax, r12
    jb 5f
    sub rax, r11                # after it
    mov [r8 + STK_start], rax
    jmp 7f
5:  cmp rdx, r9
    jbe 7f                      # before it
    # overlapping: what is left of [start, end)
    cmp rax, r9
    jae 51f
    mov rbx, rax
    jmp 52f
51: mov rbx, r9
52: cmp rdx, r12
    jae 53f
    mov rdx, r9
    cmp rdx, rbx
    jae 54f
    mov rdx, rbx
    jmp 54f
53: sub rdx, r11
54: mov [r8 + STK_start], rbx
    sub rdx, rbx
    mov [r8 + STK_len], edx
7:  add r8, STK_SIZE
    dec rcx
    jnz 4b
8:  pop r12
    pop rbx
9:  ret

# ---------------- drawing ----------------

# FN semtok_line(doc, line, lstart, cls, len) -> rax the classes to draw the line with: cls, or a
# copy with the line's tokens over it; the tokens' effects go to g_tkfx
FN semtok_line
    PROLOGUE 16
    mov rbx, rdi
    mov [rip + g_tkfx_doc], rdi
    mov [rip + g_tkfx_line], rsi
    mov qword ptr [rip + g_tkfx_n], 0
    mov r12, rdx                # lstart
    mov r13, rcx                # cls
    mov r14, r8                 # len
    mov rax, r13
    cmp dword ptr [rip + cfg_semantic_highlighting], 0
    je 9f
    mov rdx, [rbx + DOC_pres]
    test rdx, rdx
    jz 9f
    mov r15, [rdx + PRS_tks]
    test r15, r15
    jz 9f
    cmp qword ptr [r15 + STS_toks + VEC_len], 0
    je 9f
    # the first token starting at or after the line's start
    xor ecx, ecx
    mov rdx, [r15 + STS_toks + VEC_len]
1:  cmp rcx, rdx
    jae 2f
    lea rsi, [rcx + rdx]
    shr rsi, 1
    mov rdi, rsi
    shl rdi, 4
    add rdi, [r15 + STS_toks + VEC_ptr]
    cmp [rdi + STK_start], r12
    jae 11f
    lea rcx, [rsi + 1]
    jmp 1b
11: mov rdx, rsi
    jmp 1b
2:  mov [rsp], rcx
    cmp rcx, [r15 + STS_toks + VEC_len]
    jae .Lsl_none
    mov rdi, rcx
    shl rdi, 4
    add rdi, [r15 + STS_toks + VEC_ptr]
    lea rax, [r12 + r14]
    cmp [rdi + STK_start], rax
    jae .Lsl_none               # none on this line
    # a copy of the classes
    lea rdi, [rip + ov_buf]
    mov qword ptr [rdi + SB_len], 0
    lea rsi, [r14 + 16]
    call sb_reserve
    mov rdi, [rip + ov_buf + SB_ptr]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rcx, [rsp]
3:  cmp rcx, [r15 + STS_toks + VEC_len]
    jae 8f
    mov rdi, rcx
    shl rdi, 4
    add rdi, [r15 + STS_toks + VEC_ptr]
    inc rcx
    mov rax, [rdi + STK_start]
    sub rax, r12                # offset
    cmp rax, r14
    jae 8f
    mov edx, [rdi + STK_len]
    test edx, edx
    jz 3b
    add rdx, rax
    cmp rdx, r14
    jbe 4f
    mov rdx, r14
4:  movzx r8d, byte ptr [rdi + STK_cls]
    cmp r8d, STK_KEEP
    je 6f
    mov r9, [rip + ov_buf + SB_ptr]
    mov r10, rax
5:  cmp r10, rdx
    jae 6f
    mov [r9 + r10], r8b
    inc r10
    jmp 5b
6:  movzx r9d, byte ptr [rdi + STK_fx]
    test r9d, r9d
    jz 3b
    mov r10, [rip + g_tkfx_n]
    cmp r10, SEMT_FX_MAX
    jae 3b
    imul r10, r10, 24
    lea r11, [rip + g_tkfx]
    add r11, r10
    mov [r11], rax
    mov [r11 + 8], rdx
    mov [r11 + 16], r9d
    mov r9, [rip + ov_buf + SB_ptr]
    movzx r9d, byte ptr [r9 + rax]
    mov [r11 + 20], r9d         # the class drawn there (its color for the line)
    inc qword ptr [rip + g_tkfx_n]
    jmp 3b
8:  mov rax, [rip + ov_buf + SB_ptr]
    EPILOGUE
.Lsl_none:
    mov rax, r13
9:  EPILOGUE

# ---------------- lifetime ----------------

# FN semtok_free(PRS): its tokens go
FN semtok_free
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + PRS_tks]
    test r12, r12
    jz 9f
    mov qword ptr [rbx + PRS_tks], 0
    lea rdi, [r12 + STS_ints]
    call vec_free
    lea rdi, [r12 + STS_toks]
    call vec_free
    mov rdi, r12
    call mem_free
9:  EPILOGUE

# FN semtok_ext_gone(ext): its legends go, and the tokens it provided
FN semtok_ext_gone
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + g_legends + VEC_len]
    jae 2f
    imul rax, r13, SLG_SIZE
    add rax, [rip + g_legends + VEC_ptr]
    inc r13
    cmp [rax + SLG_owner], r12
    jne 1b
    mov qword ptr [rax + SLG_owner], 0
    jmp 1b
2:  xor r13d, r13d
3:  cmp r13, [rip + g_tabs + VEC_len]
    jae 9f
    imul rax, r13, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r13
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 3b
    mov rbx, [rax + TAB_doc]
    test rbx, rbx
    jz 3b
    mov rdi, [rbx + DOC_pres]
    test rdi, rdi
    jz 3b
    mov rax, [rdi + PRS_tks]
    test rax, rax
    jz 3b
    cmp [rax + STS_ext], r12
    jne 3b
    call semtok_free
    mov rdi, rbx
    call pres_touch
    jmp 3b
9:  EPILOGUE

# ---------------- headless ----------------

# FN semtok_dump(doc, sb): "tokens OWNER/NAME legend=L result=R ints=N toks=M" (or "tokens none"),
# then up to 64 "tk L C LEN cls=K fx=F" (1-based)
FN semtok_dump
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Ld_tokens]
    call sb_push_cstr
    mov rax, [rbx + DOC_pres]
    test rax, rax
    jz 8f
    mov r13, [rax + PRS_tks]
    test r13, r13
    jz 8f
    mov rax, [r13 + STS_ext]
    test rax, rax
    jz 8f
    mov rsi, [rax + EXT_name]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_legend]
    call sb_push_cstr
    mov rax, [r13 + STS_legend]
    dec rax
    imul rax, rax, SLG_SIZE
    add rax, [rip + g_legends + VEC_ptr]
    lea rsi, [rax + SLG_name]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_result]
    call sb_push_cstr
    lea rsi, [r13 + STS_result]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_ints]
    call sb_push_cstr
    mov rsi, [r13 + STS_ints + VEC_len]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_toks]
    call sb_push_cstr
    mov rsi, [r13 + STS_toks + VEC_len]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor r14d, r14d
1:  cmp r14, [r13 + STS_toks + VEC_len]
    jae 9f
    cmp r14, 64
    jae 9f
    mov r15, r14
    shl r15, 4
    add r15, [r13 + STS_toks + VEC_ptr]
    inc r14
    mov rdi, r12
    lea rsi, [rip + .Ld_tk]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r15 + STK_start]
    call doc_line_of
    push rax
    push rax
    lea rsi, [rax + 1]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    pop rsi
    pop rsi
    mov rdi, rbx
    call doc_line_start
    mov rsi, [r15 + STK_start]
    sub rsi, rax
    inc rsi
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov esi, [r15 + STK_len]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_cls]
    call sb_push_cstr
    movzx esi, byte ptr [r15 + STK_cls]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_fx]
    call sb_push_cstr
    movzx esi, byte ptr [r15 + STK_fx]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
8:  mov rdi, r12
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
9:  EPILOGUE

.section .rodata
.Le_unknown: .asciz "unknown no such request"
.Le_toobig_legend: .asciz "toobig 8 legends per extension, 256 types, 64 modifiers"
.Lm_deprecated: .asciz "deprecated"
.Lm_library: .asciz "defaultLibrary"
.Lmode_full: .asciz "full"
.Lmode_delta: .asciz "delta"
.Lmode_range: .asciz "range"
.Ld_tokens: .asciz "tokens "
.Ld_none: .asciz "none\n"
.Ld_legend: .asciz " legend="
.Ld_result: .asciz " result="
.Ld_ints: .asciz " ints="
.Ld_toks: .asciz " toks="
.Ld_tk: .asciz "tk "
.Ld_cls: .asciz " cls="
.Ld_fx: .asciz " fx="
# class names (C_* order) and style effects, as a legend's EFFECT names them
.p2align 3
class_names: .quad .Lc0, .Lc1, .Lc2, .Lc3, .Lc4, .Lc5, .Lc6, .Lc7, .Lc8, .Lc9
    .quad .Lc10, .Lc11, .Lc12, .Lc13, .Lc14, .Lc15, .Lc16, .Lc17, .Lc18, .Lc19
style_names: .quad .Ls_strike, .Ls_underline, .Ls_faded, .Ls_none, 0
style_bits: .byte STKF_STRIKE, STKF_UNDER, STKF_FADED, 0
.p2align 3
.Lc0: .asciz "text"
.Lc1: .asciz "keyword"
.Lc2: .asciz "type"
.Lc3: .asciz "function"
.Lc4: .asciz "string"
.Lc5: .asciz "number"
.Lc6: .asciz "comment"
.Lc7: .asciz "constant"
.Lc8: .asciz "operator"
.Lc9: .asciz "punctuation"
.Lc10: .asciz "preproc"
.Lc11: .asciz "variable"
.Lc12: .asciz "builtin"
.Lc13: .asciz "attribute"
.Lc14: .asciz "tag"
.Lc15: .asciz "heading"
.Lc16: .asciz "inserted"
.Lc17: .asciz "deleted"
.Lc18: .asciz "escape"
.Lc19: .asciz "link"
.Ls_strike: .asciz "strike"
.Ls_underline: .asciz "underline"
.Ls_faded: .asciz "faded"
.Ls_none: .asciz "-"
# rhun's table: LSP token types and the class each draws in
.p2align 3
type_table:
    .quad .Ltt_namespace, C_TYPE
    .quad .Ltt_type, C_TYPE
    .quad .Ltt_class, C_TYPE
    .quad .Ltt_enum, C_TYPE
    .quad .Ltt_interface, C_TYPE
    .quad .Ltt_struct, C_TYPE
    .quad .Ltt_typeParameter, C_TYPE
    .quad .Ltt_concept, C_TYPE
    .quad .Ltt_typeAlias, C_TYPE
    .quad .Ltt_union, C_TYPE
    .quad .Ltt_builtinType, C_BUILTIN
    .quad .Ltt_parameter, C_VARIABLE
    .quad .Ltt_variable, C_VARIABLE
    .quad .Ltt_property, C_VARIABLE
    .quad .Ltt_event, C_VARIABLE
    .quad .Ltt_enumMember, C_CONSTANT
    .quad .Ltt_const, C_CONSTANT
    .quad .Ltt_static, C_CONSTANT
    .quad .Ltt_boolean, C_CONSTANT
    .quad .Ltt_label, C_CONSTANT
    .quad .Ltt_function, C_FUNCTION
    .quad .Ltt_method, C_FUNCTION
    .quad .Ltt_macro, C_PREPROC
    .quad .Ltt_decorator, C_ATTRIBUTE
    .quad .Ltt_attribute, C_ATTRIBUTE
    .quad .Ltt_builtinAttribute, C_ATTRIBUTE
    .quad .Ltt_derive, C_ATTRIBUTE
    .quad .Ltt_keyword, C_KEYWORD
    .quad .Ltt_modifier, C_KEYWORD
    .quad .Ltt_selfKeyword, C_KEYWORD
    .quad .Ltt_selfTypeKeyword, C_KEYWORD
    .quad .Ltt_lifetime, C_KEYWORD
    .quad .Ltt_comment, C_COMMENT
    .quad .Ltt_string, C_STRING
    .quad .Ltt_number, C_NUMBER
    .quad .Ltt_regexp, C_ESCAPE
    .quad .Ltt_escapeSequence, C_ESCAPE
    .quad .Ltt_formatSpecifier, C_ESCAPE
    .quad .Ltt_operator, C_OPERATOR
    .quad .Ltt_arithmetic, C_OPERATOR
    .quad .Ltt_bitwise, C_OPERATOR
    .quad .Ltt_comparison, C_OPERATOR
    .quad .Ltt_logical, C_OPERATOR
    .quad .Ltt_bracket, C_PUNCT
    .quad .Ltt_brace, C_PUNCT
    .quad .Ltt_parenthesis, C_PUNCT
    .quad .Ltt_punctuation, C_PUNCT
    .quad .Ltt_angle, C_PUNCT
    .quad .Ltt_colon, C_PUNCT
    .quad .Ltt_comma, C_PUNCT
    .quad .Ltt_dot, C_PUNCT
    .quad .Ltt_semicolon, C_PUNCT
    .quad 0, 0
.Ltt_namespace: .asciz "namespace"
.Ltt_type: .asciz "type"
.Ltt_class: .asciz "class"
.Ltt_enum: .asciz "enum"
.Ltt_interface: .asciz "interface"
.Ltt_struct: .asciz "struct"
.Ltt_typeParameter: .asciz "typeParameter"
.Ltt_concept: .asciz "concept"
.Ltt_typeAlias: .asciz "typeAlias"
.Ltt_union: .asciz "union"
.Ltt_builtinType: .asciz "builtinType"
.Ltt_parameter: .asciz "parameter"
.Ltt_variable: .asciz "variable"
.Ltt_property: .asciz "property"
.Ltt_event: .asciz "event"
.Ltt_enumMember: .asciz "enumMember"
.Ltt_const: .asciz "const"
.Ltt_static: .asciz "static"
.Ltt_boolean: .asciz "boolean"
.Ltt_label: .asciz "label"
.Ltt_function: .asciz "function"
.Ltt_method: .asciz "method"
.Ltt_macro: .asciz "macro"
.Ltt_decorator: .asciz "decorator"
.Ltt_attribute: .asciz "attribute"
.Ltt_builtinAttribute: .asciz "builtinAttribute"
.Ltt_derive: .asciz "derive"
.Ltt_keyword: .asciz "keyword"
.Ltt_modifier: .asciz "modifier"
.Ltt_selfKeyword: .asciz "selfKeyword"
.Ltt_selfTypeKeyword: .asciz "selfTypeKeyword"
.Ltt_lifetime: .asciz "lifetime"
.Ltt_comment: .asciz "comment"
.Ltt_string: .asciz "string"
.Ltt_number: .asciz "number"
.Ltt_regexp: .asciz "regexp"
.Ltt_escapeSequence: .asciz "escapeSequence"
.Ltt_formatSpecifier: .asciz "formatSpecifier"
.Ltt_operator: .asciz "operator"
.Ltt_arithmetic: .asciz "arithmetic"
.Ltt_bitwise: .asciz "bitwise"
.Ltt_comparison: .asciz "comparison"
.Ltt_logical: .asciz "logical"
.Ltt_bracket: .asciz "bracket"
.Ltt_brace: .asciz "brace"
.Ltt_parenthesis: .asciz "parenthesis"
.Ltt_punctuation: .asciz "punctuation"
.Ltt_angle: .asciz "angle"
.Ltt_colon: .asciz "colon"
.Ltt_comma: .asciz "comma"
.Ltt_dot: .asciz "dot"
.Ltt_semicolon: .asciz "semicolon"
