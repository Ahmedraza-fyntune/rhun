# editor presentation: decorations (feature `decorations`, docs/extensions/v1.1.md). Extensions
# register styles by name (`decoration-type`) and put ranges of them on documents (`decorate`):
# text color, background, whole-line background, border, underline, strikethrough, faded text,
# an icon in the gutter's left lane, a tick in the scrollbar, and a tip. Ranges keep byte positions
# that move with edits (deco_shift, the edit tape's gravity), and replies about an older version are
# moved onto the current text (tape_map_lc).
#
# Drawing: deco_frame collects the ranges that touch the visible lines once per change (the window,
# in priority order); per row draw_line asks deco_row_back (backgrounds, before the selection),
# deco_span_color (text colors, in its glyph loop) and deco_row_front (strike, underline, border,
# after the glyphs, under the diagnostics' underlines); editor_draw asks deco_line_back for whole-line
# backgrounds and deco_scroll_ticks for the scrollbar; the gutter asks deco_gutter_icon/_tip.
.include "rhun.inc"

.equ SP_MAX, 256                # color spans per row
.equ MF_MAX, 64                 # faded parts from tagged marks per row
.equ SP_SIZE, 24                # from, to (offsets in the line), color, flags
.equ SPF_COLOR, 1
.equ SPF_FADED, 2
.equ VIS_EVERY_MS, 100          # `0 visible` at most this often

.data
.p2align 3
.globl g_deco_gen
g_deco_gen: .quad 1             # bumped when a type changes or goes
.bss
.p2align 3
.globl g_dtypes
g_dtypes: .zero VEC_SIZE        # DT
dt_seq: .long 0
.p2align 3
# the window: the frame's ranges in priority order, as (key << 32 | range index)
dw_keys: .quad 0
dw_cap: .quad 0
dw_n: .quad 0
dw_doc: .quad 0
dw_ver: .quad 0
dw_gen: .quad 0
dw_tgen: .quad 0
dw_l1: .quad 0
dw_l2: .quad 0
dw_over: .long 0                # more ranges touched the lines than the window holds
pieces: .long 0                 # pieces drawn this frame
# the row's text-color spans
.globl g_deco_spans
g_deco_spans: .long 0
sp_i: .quad 0
.globl g_row_fx
g_row_fx: .long 0               # the row has text-color spans or faded parts (deco_span_color)
.p2align 3
mf_n: .quad 0                   # the row's faded parts from tagged marks
mf_i: .quad 0
mf_buf: .zero MF_MAX * 16
sp_buf: .zero SP_MAX * SP_SIZE
sp_tmp: .zero SP_MAX * SP_SIZE
# scrollbar ticks, per pixel row of the track
tk_doc: .quad 0
tk_ver: .quad 0
tk_gen: .quad 0
tk_tgen: .quad 0
tk_h: .quad 0
tk_lines: .quad 0
tk_rows: .quad 0                # u32 argb per row
tk_prio: .quad 0                # u8 per row
tk_cap: .quad 0
# a decorate request being parsed
nr: .zero VEC_SIZE              # DR
npool: .zero SB_SIZE
.p2align 3
tipbuf: .zero DECO_TIP_MAX + 1
# the visible event
vis_doc: .quad 0                # what the editor shows (doc id, lines 1-based)
vis_l1: .quad 0
vis_l2: .quad 0
vis_sent_doc: .quad 0
vis_sent_l1: .quad 0
vis_sent_l2: .quad 0
vis_at: .quad 0                 # time_ms of the last event
evbuf: .zero 96

.text

# ---------------- types ----------------

# dt_find(owner, name ptr, len) -> rax DT* or 0
dt_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rip + g_dtypes + VEC_len]
    jae 8f
    imul r15, r14, DTY_SIZE
    add r15, [rip + g_dtypes + VEC_ptr]
    inc r14
    cmp [r15 + DTY_owner], rbx
    jne 1b
    mov rdi, r12
    mov rsi, r13
    lea rdx, [r15 + DTY_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ID decoration-type NAME LEN + body -> ok ID: the extension's style NAME, new or replaced
FN h_decoration_type
    PROLOGUE 128
    call xp_cur
    mov rbx, rax
    FEAT_TEST rbx, FEAT_DECORATIONS
    jz .Lht_unknown
    call xp_nfields
    cmp rax, 4
    jb .Lht_syntax
    mov edi, 2
    call xp_field
    mov r12, rax                # name
    mov r13, rdx
    mov rdi, rax
    mov rsi, rdx
    call name_ok
    test eax, eax
    jz .Lht_syntax
    # the style into a scratch type first: a bad line leaves the old one as it was
    lea rdi, [rip + dt_scratch]
    xor esi, esi
    mov edx, DTY_SIZE
    call memset
    mov dword ptr [rip + dt_scratch + DTY_prio], 50
    mov dword ptr [rip + dt_scratch + DTY_bwidth], 1
    call xp_body
    mov rdi, rax
    mov rsi, rdx
    call type_parse
    test rax, rax
    jnz .Lht_badline
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call dt_find
    test rax, rax
    jnz .Lht_replace
    # a new one: within the caps, in a free slot or a new one
    xor r14d, r14d              # this extension's
    xor r15d, r15d              # in all
    xor ecx, ecx
1:  cmp rcx, [rip + g_dtypes + VEC_len]
    jae 2f
    imul rax, rcx, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    inc rcx
    cmp qword ptr [rax + DTY_owner], 0
    je 1b
    inc r15d
    cmp [rax + DTY_owner], rbx
    jne 1b
    inc r14d
    jmp 1b
2:  cmp r14d, DTY_MAX_EXT
    jae .Lht_toobig
    cmp r15d, DTY_MAX
    jae .Lht_toobig
    xor ecx, ecx
3:  cmp rcx, [rip + g_dtypes + VEC_len]
    jae 4f
    imul rax, rcx, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    inc rcx
    cmp qword ptr [rax + DTY_owner], 0
    je 5f
    jmp 3b
4:  lea rdi, [rip + g_dtypes]
    mov esi, DTY_SIZE
    call vec_push
5:  mov r14, rax
    inc dword ptr [rip + dt_seq]
    mov eax, [rip + dt_seq]
    mov [rip + dt_scratch + DTY_seq], eax
    jmp .Lht_store
.Lht_replace:
    mov r14, rax
    mov eax, [r14 + DTY_seq]
    mov [rip + dt_scratch + DTY_seq], eax
.Lht_store:
    mov rdi, r14
    lea rsi, [rip + dt_scratch]
    mov edx, DTY_SIZE
    call memcpy
    mov [r14 + DTY_owner], rbx
    lea rdi, [r14 + DTY_name]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [r14 + DTY_name + r13], 0
    inc qword ptr [rip + g_deco_gen]
    mov dword ptr [rip + g_dirty], 1
    call xp_cur_id
    mov rdi, rax
    call xp_reply_ok
    EPILOGUE
.Lht_badline:
    # "syntax line N"
    mov r12, rax
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_line]
    mov rdx, r12
    call xp_reply_error_u64
    EPILOGUE
.Lht_toobig:
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_toobig_types]
    call xp_reply_error
    EPILOGUE
.Lht_unknown:
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_unknown]
    call xp_reply_error
    EPILOGUE
.Lht_syntax:
    call xp_cur_id
    mov rdi, rax
    call xp_reply_syntax
    EPILOGUE

# name_ok(ptr, len) -> eax 1 for 1-40 bytes of [a-z0-9_-]
name_ok:
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 40
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
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 1b
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    jbe 1b
    ret
8:  mov eax, 1
9:  ret

# type_parse(ptr, len) -> rax 0, or the 1-based number of the first line it cannot read; fills
# dt_scratch
type_parse:
    PROLOGUE 48
    mov rbx, rdi
    lea rax, [rdi + rsi]
    mov [rsp + 16], rax         # end (the key parsers take r14 and r15)
    mov qword ptr [rsp], 0      # line number
.Ltp_line:
    cmp rbx, [rsp + 16]
    jae .Ltp_ok
    inc qword ptr [rsp]
    mov rax, rbx
1:  cmp rax, [rsp + 16]
    jae 2f
    cmp byte ptr [rax], 10
    je 2f
    inc rax
    jmp 1b
2:  mov [rsp + 8], rax          # line end
    mov r12, rbx                # the rest of the line
    mov r13, rax
    sub r13, rbx
    mov rdi, r12
    mov rsi, r13
    call trim
    mov r12, rax
    mov r13, rdx
    test r13, r13
    jz .Ltp_next                # blank lines are fine
    call tp_word                # the key
    test rdx, rdx
    jz .Ltp_bad
    mov rdi, rax
    mov rsi, rdx
    call key_index
    test eax, eax
    js .Ltp_bad
    lea rcx, [rip + key_fns]
    call [rcx + rax*8]
    test eax, eax
    jz .Ltp_bad
    test r13, r13               # nothing may follow
    jnz .Ltp_bad
.Ltp_next:
    mov rbx, [rsp + 8]
    inc rbx
    jmp .Ltp_line
.Ltp_ok:
    xor eax, eax
    EPILOGUE
.Ltp_bad:
    mov rax, [rsp]
    EPILOGUE

# tp_word() -> rax, rdx the next word of the line (r12, r13 advance past it and its spaces)
tp_word:
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    ret

# key_index(ptr, len) -> eax index in key_names, or -1
key_index:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rax, [rip + key_names]
    mov rdx, [rax + r13*8]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 9f
    inc r13d
    jmp 1b
8:  mov eax, -1
    EPILOGUE
9:  mov eax, r13d
    EPILOGUE

# key parsers: read the rest of the line (r12, r13) into dt_scratch -> eax 1, or 0
k_color:
    mov r14d, DTYF_COLOR
    lea r15, [rip + dt_scratch + DTY_color]
    jmp k_one_color
k_background:
    mov r14d, DTYF_BG
    lea r15, [rip + dt_scratch + DTY_bg]
    jmp k_one_color
k_linebg:
    mov r14d, DTYF_LINEBG
    lea r15, [rip + dt_scratch + DTY_linebg]
    jmp k_one_color
k_scrollbar:
    mov r14d, DTYF_SCROLL
    lea r15, [rip + dt_scratch + DTY_scroll]
k_one_color:
    push r14
    push r15
    call tp_word
    pop r15
    pop r14
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r15
    xor ecx, ecx
    call color_parse
    test eax, eax
    jz 9f
    or [rip + dt_scratch + DTY_flags], r14d
    mov eax, 1
9:  ret
k_border:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    call small_int
    cmp eax, 1
    jl 8f
    cmp eax, 3
    jg 8f
    mov [rip + dt_scratch + DTY_bwidth], eax
    mov r14d, DTYF_BORDER
    lea r15, [rip + dt_scratch + DTY_border]
    jmp k_one_color
8:  xor eax, eax
    ret
k_underline:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + ustyle_names]
    call word_index
    test eax, eax
    jle 8f
    mov [rip + dt_scratch + DTY_ustyle], eax
    mov r14d, DTYF_UNDER
    lea r15, [rip + dt_scratch + DTY_under]
    jmp k_one_color
8:  xor eax, eax
    ret
k_strike:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + dt_scratch + DTY_strike]
    mov ecx, 1                  # "-": the text's color
    call color_parse
    test eax, eax
    jz 9f
    or dword ptr [rip + dt_scratch + DTY_flags], DTYF_STRIKE
    mov eax, 1
9:  ret
k_faded:
    or dword ptr [rip + dt_scratch + DTY_flags], DTYF_FADED
    mov eax, 1
    ret
k_before:
    mov r14d, DTYF_BEFORE
    lea r15, [rip + dt_scratch + DTY_before]
    jmp k_two_colors
k_after:
    mov r14d, DTYF_AFTER
    lea r15, [rip + dt_scratch + DTY_after]
k_two_colors:
    # COLOR BACKGROUND (- for none)
    push r14
    push r15
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    mov rdx, [rsp]
    xor ecx, ecx
    call color_parse
    test eax, eax
    jz 8f
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    mov rdx, [rsp]
    add rdx, 2 * DCS_SIZE        # DTY_beforebg follows DTY_before, DTY_afterbg DTY_after
    mov ecx, 2                  # "-": none
    call color_parse
    test eax, eax
    jz 8f
    pop r15
    pop r14
    or [rip + dt_scratch + DTY_flags], r14d
    mov eax, 1
    ret
8:  pop r15
    pop r14
    xor eax, eax
    ret
k_width:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    call small_int
    test eax, eax
    js 8f
    cmp eax, 200
    jg 8f
    mov [rip + dt_scratch + DTY_width], eax
    mov eax, 1
    ret
8:  xor eax, eax
    ret
k_gutter:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + shape_names]
    call word_index
    test eax, eax
    jle 8f
    mov [rip + dt_scratch + DTY_gshape], eax
    mov r14d, DTYF_GUTTER
    lea r15, [rip + dt_scratch + DTY_gutter]
    jmp k_one_color
8:  xor eax, eax
    ret
k_grow:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + grow_names]
    call word_index
    test eax, eax
    jle 8f
    dec eax
    mov [rip + dt_scratch + DTY_grow], eax
    mov eax, 1
    ret
8:  xor eax, eax
    ret
k_priority:
    call tp_word
    mov rdi, rax
    mov rsi, rdx
    call small_int
    test eax, eax
    js 8f
    cmp eax, 100
    jg 8f
    mov [rip + dt_scratch + DTY_prio], eax
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# small_int(ptr, len) -> eax the decimal number (at most 6 digits), or -1
small_int:
    test rsi, rsi
    jz 8f
    cmp rsi, 6
    ja 8f
    push rsi
    call parse_u64
    pop rsi
    cmp rdx, rsi
    jne 8f
    ret
8:  mov eax, -1
    ret

# word_index(ptr, len, names) -> eax 1-based index of the word in a 0-ended list of cstrs, or 0
word_index:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  mov rdx, [r13 + r14*8]
    test rdx, rdx
    jz 8f
    inc r14d
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov eax, r14d
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# color_parse(ptr, len, COLOR*, dash) -> eax 1 when the word is SPEC or SPEC|SPEC (dark | light);
# dash 1: "-" is the text's color, 2: "-" is none
FN color_parse
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], ecx
    test r12, r12
    jz 8f
    cmp r12, 1
    jne 1f
    cmp byte ptr [rbx], '-'
    jne 1f
    cmp dword ptr [rsp], 0
    je 8f
    mov eax, DCSK_TEXT
    cmp dword ptr [rsp], 1
    je 11f
    mov eax, DCSK_NONE
11: mov byte ptr [r13 + DCS_kind], al
    mov byte ptr [r13 + DCS_SIZE + DCS_kind], al
    mov eax, 1
    EPILOGUE
1:  # a bar splits dark from light
    xor ecx, ecx
2:  cmp rcx, r12
    jae 3f
    cmp byte ptr [rbx + rcx], '|'
    je 4f
    inc rcx
    jmp 2b
3:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call spec_parse
    test eax, eax
    jz 8f
    mov rax, [r13]
    mov [r13 + DCS_SIZE], rax
    mov eax, 1
    EPILOGUE
4:  mov r14, rcx
    mov rdi, rbx
    mov rsi, rcx
    mov rdx, r13
    call spec_parse
    test eax, eax
    jz 8f
    lea rdi, [rbx + r14 + 1]
    mov rsi, r12
    sub rsi, r14
    dec rsi
    lea rdx, [r13 + DCS_SIZE]
    call spec_parse
    test eax, eax
    jz 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# spec_parse(ptr, len, CS*) -> eax 1 for #rrggbb, #rrggbbaa, SLOT or SLOT/PCT
spec_parse:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz 8f
    cmp byte ptr [rbx], '#'
    jne 3f
    cmp r12, 7
    je 1f
    cmp r12, 9
    jne 8f
1:  lea rdi, [rbx + 1]
    lea rsi, [r12 - 1]
    call parse_hex
    lea rcx, [r12 - 1]
    cmp rdx, rcx
    jne 8f
    cmp r12, 9
    je 2f
    or eax, 0xff000000          # #rrggbb: opaque
    jmp 21f
2:  # #rrggbbaa -> aarrggbb
    mov ecx, eax
    shr eax, 8
    shl ecx, 24
    or eax, ecx
21: mov [r13 + DCS_value], eax
    mov byte ptr [r13 + DCS_kind], DCSK_ARGB
    mov byte ptr [r13 + DCS_pct], 100
    mov eax, 1
    EPILOGUE
3:  # a slot name, maybe /PCT
    mov r14, r12
    xor ecx, ecx
4:  cmp rcx, r12
    jae 5f
    cmp byte ptr [rbx + rcx], '/'
    je 41f
    inc rcx
    jmp 4b
41: mov r14, rcx
5:  mov rdi, rbx
    mov rsi, r14
    call theme_slot_find
    test eax, eax
    js 8f
    mov [r13 + DCS_value], eax
    mov byte ptr [r13 + DCS_kind], DCSK_SLOT
    mov byte ptr [r13 + DCS_pct], 100
    cmp r14, r12
    je 7f
    lea rdi, [rbx + r14 + 1]
    mov rsi, r12
    sub rsi, r14
    dec rsi
    call small_int
    test eax, eax
    js 8f
    cmp eax, 100
    ja 8f
    mov [r13 + DCS_pct], al
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# deco_color(COLOR*) -> eax argb for the theme shown (0: none; DCSK_TEXT gives 1)
FN deco_color
    lea rax, [rdi + DCS_SIZE]
    cmp dword ptr [rip + g_theme_dark], 0
    cmove rdi, rax
    movzx ecx, byte ptr [rdi + DCS_kind]
    cmp ecx, DCSK_ARGB
    je 1f
    cmp ecx, DCSK_SLOT
    je 2f
    xor eax, eax
    cmp ecx, DCSK_TEXT
    jne 9f
    mov eax, 1
9:  ret
1:  mov eax, [rdi + DCS_value]
    ret
2:  mov eax, [rdi + DCS_value]
    lea rdx, [rip + g_theme]
    mov eax, [rdx + rax*4]
    movzx ecx, byte ptr [rdi + DCS_pct]
    cmp ecx, 100
    jae 9b
    mov edx, eax
    shr edx, 24
    imul edx, ecx
    mov r8d, 100
    push rax
    mov eax, edx
    xor edx, edx
    div r8d
    mov edx, eax
    pop rax
    and eax, 0xffffff
    shl edx, 24
    or eax, edx
    ret

# ---------------- ranges ----------------

# ID decorate DOC VERSION NAME FROM TO N LEN + body -> ok ID: the extension's ranges of NAME whose
# first line is in FROM..TO (0 0: all) replaced by the body's N records
FN h_decorate
    PROLOGUE 112
    call xp_cur
    mov rbx, rax
    FEAT_TEST rbx, FEAT_DECORATIONS
    jz .Lhd_unknown
    mov edi, NEEDS_DOC_READ
    call xp_need
    test eax, eax
    jz .Lhd_ret
    call xp_nfields
    cmp rax, 9
    jb .Lhd_syntax
    mov edi, 2
    call xp_arg_doc
    test rax, rax
    jz .Lhd_ret
    mov r12, rax                # doc
    cmp qword ptr [r12 + DOC_diff], 0
    jne .Lhd_readonly
    mov edi, 3
    call xp_field_u64
    test edx, edx
    jz .Lhd_syntax
    mov [rsp], rax              # version
    cmp rax, [r12 + DOC_version]
    je 1f
    ja .Lhd_stale
    mov rcx, [r12 + DOC_pres]
    test rcx, rcx
    jz .Lhd_stale
    cmp rax, [rcx + PRS_tbase]
    jb .Lhd_stale
1:  mov edi, 4
    call xp_field
    mov rdi, rbx
    mov rsi, rax
    call dt_find
    test rax, rax
    jz .Lhd_notype
    sub rax, [rip + g_dtypes + VEC_ptr]
    xor edx, edx
    mov ecx, DTY_SIZE
    div rcx
    mov [rsp + 8], eax          # type index
    mov edi, 5
    call xp_field_u64
    test edx, edx
    jz .Lhd_syntax
    mov [rsp + 16], rax         # FROM
    mov edi, 6
    call xp_field_u64
    test edx, edx
    jz .Lhd_syntax
    mov [rsp + 24], rax         # TO
    mov edi, 7
    call xp_field_u64
    test edx, edx
    jz .Lhd_syntax
    cmp rax, DECO_MAX_MSG
    ja .Lhd_toobig
    mov [rsp + 32], rax         # N
    # the records into nr and npool
    mov qword ptr [rip + nr + VEC_len], 0
    mov qword ptr [rip + npool + SB_len], 0
    call xp_body
    mov r13, rax
    lea r14, [rax + rdx]        # end
.Lhd_rec:
    mov rax, [rip + nr + VEC_len]
    cmp rax, [rsp + 32]
    jae .Lhd_parsed
    # L1 C1 L2 C2 BEFORE_LEN AFTER_LEN TIP_LEN EXTRA_LEN LF
    xor r15d, r15d
2:  mov rdi, r13
    mov rsi, r14
    call rec_num
    test edx, edx
    jz .Lhd_syntax
    mov r13, rcx
    mov [rsp + 40 + r15*8], rax
    inc r15d
    cmp r15d, 8
    jae 3f
    cmp r13, r14
    jae .Lhd_syntax
    cmp byte ptr [r13], ' '
    jne .Lhd_syntax
    inc r13
    jmp 2b
3:  cmp r13, r14
    jae .Lhd_syntax
    cmp byte ptr [r13], 10
    jne .Lhd_syntax
    inc r13
    # text lengths within their caps, and in the body
    cmp qword ptr [rsp + 72], DECO_TEXT_MAX
    ja .Lhd_toobig
    cmp qword ptr [rsp + 80], DECO_TEXT_MAX
    ja .Lhd_toobig
    cmp qword ptr [rsp + 88], DECO_TIP_MAX
    ja .Lhd_toobig
    mov rax, [rsp + 72]
    add rax, [rsp + 80]
    add rax, [rsp + 88]
    mov rcx, [rsp + 40 + 7*8]
    cmp rcx, DECO_EXTRA_MAX
    ja .Lhd_toobig
    add rax, rcx
    mov rcx, r14
    sub rcx, r13
    cmp rax, rcx
    ja .Lhd_syntax
    # before and after: one line each, no control characters
    mov rcx, [rsp + 72]
    add rcx, [rsp + 80]
    xor edx, edx
4:  cmp rdx, rcx
    jae 5f
    cmp byte ptr [r13 + rdx], 32
    jb .Lhd_syntax
    inc rdx
    jmp 4b
5:  # the positions
    mov rdi, r12
    mov rsi, [rsp + 40]
    mov rdx, [rsp + 48]
    mov rcx, [rsp]
    mov r8d, GR_RIGHT
    call rec_pos
    test rax, rax
    js .Lhd_badpos
    mov r15, rax
    mov rdi, r12
    mov rsi, [rsp + 56]
    mov rdx, [rsp + 64]
    mov rcx, [rsp]
    mov r8d, GR_LEFT
    call rec_pos
    test rax, rax
    js .Lhd_badpos
    cmp rax, r15
    jb .Lhd_badpos
    push rax
    push rax
    lea rdi, [rip + nr]
    mov esi, DR_SIZE
    call vec_push
    pop rcx
    pop rcx
    mov [rax + DR_start], r15
    mov [rax + DR_end], rcx
    mov ecx, [rsp + 8]
    mov [rax + DR_type], ecx
    cmp r15, [rax + DR_end]
    jne 6f
    or dword ptr [rax + DR_flags], DRF_WASEMPTY
6:  mov rcx, [rip + npool + SB_len]
    mov [rax + DR_text], ecx
    mov rcx, [rsp + 72]
    mov [rax + DR_blen], cx
    mov rcx, [rsp + 80]
    mov [rax + DR_alen], cx
    mov rcx, [rsp + 88]
    mov [rax + DR_tlen], cx
    mov rcx, [rsp + 40 + 7*8]
    mov [rax + DR_xlen], ecx
    mov rdx, [rsp + 72]
    add rdx, [rsp + 80]
    add rdx, [rsp + 88]
    add rdx, rcx
    push rdx
    push rdx
    lea rdi, [rip + npool]
    mov rsi, r13
    call sb_push
    pop rdx
    pop rdx
    add r13, rdx
    jmp .Lhd_rec
.Lhd_parsed:
    cmp r13, r14
    jne .Lhd_syntax             # more than N records
    # FROM and TO of an older version: moved like positions
    mov rax, [rsp + 16]
    or rax, [rsp + 24]
    jz 7f
    cmp qword ptr [rsp + 16], 0
    je .Lhd_syntax
    mov rax, [rsp + 24]
    cmp rax, [rsp + 16]
    jb .Lhd_syntax
    mov rax, [rsp]
    cmp rax, [r12 + DOC_version]
    je 7f
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 16]
    dec rdx
    xor ecx, ecx
    mov r8d, GR_RIGHT
    call tape_map_lc
    mov rdi, r12
    mov rsi, rax
    call doc_line_of
    inc rax
    mov [rsp + 16], rax
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 24]
    dec rdx
    xor ecx, ecx
    mov r8d, GR_RIGHT
    call tape_map_lc
    mov rdi, r12
    mov rsi, rax
    call doc_line_of
    inc rax
    mov [rsp + 24], rax
7:  # the caps: this extension's ranges on the document and all of them, after the replacement
    mov rdi, r12
    call pres_ensure
    mov r15, rax
    xor ecx, ecx
    xor r8d, r8d                # this extension's that stay
    xor r9d, r9d                # all that stay
8:  cmp rcx, [r15 + PRS_deco + VEC_len]
    jae 9f
    imul rax, rcx, DR_SIZE
    add rax, [r15 + PRS_deco + VEC_ptr]
    inc rcx
    push rcx
    push r8
    push r9
    push rax
    mov rdi, r12
    mov rsi, rax
    mov edx, [rsp + 8 + 32]     # (type index, under the four pushes)
    mov rcx, [rsp + 16 + 32]
    mov r8, [rsp + 24 + 32]
    call replaced
    pop rdx
    pop r9
    pop r8
    pop rcx
    test eax, eax
    jnz 8b
    inc r9d
    mov eax, [rdx + DR_type]
    imul rax, rax, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    cmp [rax + DTY_owner], rbx
    jne 8b
    inc r8d
    jmp 8b
9:  mov rax, [rip + nr + VEC_len]
    add r8, rax
    add r9, rax
    cmp r8, DECO_MAX_MSG
    ja .Lhd_toobig
    cmp r9, DECO_MAX_DOC
    ja .Lhd_toobig
    # out with the replaced ranges, in with the new
    xor ecx, ecx
10: cmp rcx, [r15 + PRS_deco + VEC_len]
    jae 11f
    imul rax, rcx, DR_SIZE
    add rax, [r15 + PRS_deco + VEC_ptr]
    push rcx
    push rax
    mov rdi, r12
    mov rsi, rax
    mov edx, [rsp + 8 + 16]
    mov rcx, [rsp + 16 + 16]
    mov r8, [rsp + 24 + 16]
    call replaced
    pop rsi
    pop rcx
    test eax, eax
    jz 101f
    mov rdi, r15
    mov rdx, rcx
    push rcx
    push rcx
    call dr_drop
    pop rcx
    pop rcx
    jmp 10b
101:inc rcx
    jmp 10b
11: mov r13, [r15 + PRS_dpool + SB_len]   # the new texts' offset in the pool
    lea rdi, [r15 + PRS_dpool]
    mov rsi, [rip + npool + SB_ptr]
    mov rdx, [rip + npool + SB_len]
    call sb_push
    xor r14d, r14d
12: cmp r14, [rip + nr + VEC_len]
    jae 13f
    lea rdi, [r15 + PRS_deco]
    mov esi, DR_SIZE
    call vec_push
    imul rsi, r14, DR_SIZE
    add rsi, [rip + nr + VEC_ptr]
    mov rdi, rax
    push rax
    push rax
    mov edx, DR_SIZE
    call memcpy
    pop rax
    pop rax
    add [rax + DR_text], r13d
    inc r14
    jmp 12b
13: mov rdi, r12
    call pres_touch
    call xp_cur_id
    mov rdi, rax
    call xp_reply_ok
.Lhd_ret:
    EPILOGUE
.Lhd_unknown:
    lea rsi, [rip + .Le_unknown]
    jmp .Lhd_error
.Lhd_readonly:
    lea rsi, [rip + .Le_readonly]
    jmp .Lhd_error
.Lhd_notype:
    lea rsi, [rip + .Le_notype]
    jmp .Lhd_error
.Lhd_badpos:
    lea rsi, [rip + .Le_badpos]
    jmp .Lhd_error
.Lhd_toobig:
    lea rsi, [rip + .Le_toobig]
.Lhd_error:
    push rsi
    push rsi
    call xp_cur_id
    pop rsi
    pop rsi
    mov rdi, rax
    call xp_reply_error
    EPILOGUE
.Lhd_stale:
    call xp_cur_id
    mov rdi, rax
    lea rsi, [rip + .Le_stale]
    mov rdx, [r12 + DOC_version]
    call xp_reply_error_u64
    EPILOGUE
.Lhd_syntax:
    call xp_cur_id
    mov rdi, rax
    call xp_reply_syntax
    EPILOGUE

# replaced(doc, DR*, type, from, to) -> eax 1 when a decorate of that type and lines replaces the
# range (lines 1-based, 0 0: all)
replaced:
    xor eax, eax
    cmp [rsi + DR_type], edx
    jne 9f
    mov eax, 1
    mov rdx, rcx
    or rdx, r8
    jz 9f
    push rcx
    push r8
    mov rsi, [rsi + DR_start]
    call doc_line_of
    inc rax
    pop r8
    pop rcx
    cmp rax, rcx
    jb 8f
    cmp rax, r8
    ja 8f
    mov eax, 1
    ret
8:  xor eax, eax
9:  ret

# rec_num(ptr, end) -> rax the decimal number at ptr, rcx after it, edx 1 (0: none or too long)
rec_num:
    xor eax, eax
    xor edx, edx
    mov rcx, rdi
1:  cmp rcx, rsi
    jae 9f
    movzx r8d, byte ptr [rcx]
    sub r8d, '0'
    cmp r8d, 9
    ja 9f
    mov r9, rcx
    sub r9, rdi
    cmp r9, 12
    jae 8f
    imul rax, rax, 10
    add rax, r8
    inc rcx
    mov edx, 1
    jmp 1b
8:  xor edx, edx
9:  ret

# rec_pos(doc, line, col, version, gravity) -> rax the byte position of a 1-based LINE COL in that
# version's text, moved to the current text, or -1
rec_pos:
    PROLOGUE
    mov rbx, rdi
    test rsi, rsi
    jz 8f
    test rdx, rdx
    jz 8f
    cmp rcx, [rbx + DOC_version]
    je 1f
    dec rsi
    dec rdx
    xchg rsi, rcx               # tape_map_lc(doc, version, line, col, gravity)
    xchg rdx, rcx
    call tape_map_lc
    EPILOGUE
1:  call mark_pos
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# dr_drop(ps, DR*, index): the range goes (the last takes its place); its texts become garbage
dr_drop:
    mov rax, rdi
    movzx ecx, word ptr [rsi + DR_blen]
    movzx r8d, word ptr [rsi + DR_alen]
    add ecx, r8d
    movzx r8d, word ptr [rsi + DR_tlen]
    add ecx, r8d
    add ecx, [rsi + DR_xlen]
    add [rax + PRS_dgarbage], rcx
    mov rcx, [rax + PRS_deco + VEC_len]
    dec rcx
    mov [rax + PRS_deco + VEC_len], rcx
    imul rcx, rcx, DR_SIZE
    add rcx, [rax + PRS_deco + VEC_ptr]
    cmp rcx, rsi
    je 9f
    mov r8, [rcx]
    mov [rsi], r8
    mov r8, [rcx + 8]
    mov [rsi + 8], r8
    mov r8, [rcx + 16]
    mov [rsi + 16], r8
    mov r8, [rcx + 24]
    mov [rsi + 24], r8
    mov r8, [rcx + 32]
    mov [rsi + 32], r8
9:  ret

# pool_compact(ps): the pool keeps only the texts ranges use, once garbage is most of it
pool_compact:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + PRS_dgarbage]
    cmp rax, 1048576
    jb 9f
    mov rcx, [rbx + PRS_dpool + SB_len]
    shr rcx, 1
    cmp rax, rcx
    jb 9f
    mov qword ptr [rip + npool + SB_len], 0
    xor r12d, r12d
1:  cmp r12, [rbx + PRS_deco + VEC_len]
    jae 2f
    imul r13, r12, DR_SIZE
    add r13, [rbx + PRS_deco + VEC_ptr]
    inc r12
    movzx edx, word ptr [r13 + DR_blen]
    movzx ecx, word ptr [r13 + DR_alen]
    add edx, ecx
    movzx ecx, word ptr [r13 + DR_tlen]
    add edx, ecx
    add edx, [r13 + DR_xlen]
    mov esi, [r13 + DR_text]
    add rsi, [rbx + PRS_dpool + SB_ptr]
    mov rax, [rip + npool + SB_len]
    mov [r13 + DR_text], eax
    lea rdi, [rip + npool]
    call sb_push
    jmp 1b
2:  mov qword ptr [rbx + PRS_dpool + SB_len], 0
    lea rdi, [rbx + PRS_dpool]
    mov rsi, [rip + npool + SB_ptr]
    mov rdx, [rip + npool + SB_len]
    call sb_push
    mov qword ptr [rbx + PRS_dgarbage], 0
9:  EPILOGUE

# deco_shift(doc, entry): the ranges move with an edit; emptied ones go
FN deco_shift
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    xor r14d, r14d
.Lds_each:
    cmp r14, [r13 + PRS_deco + VEC_len]
    jae .Lds_done
    imul r15, r14, DR_SIZE
    add r15, [r13 + PRS_deco + VEC_ptr]
    mov eax, [r15 + DR_type]
    imul rax, rax, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    mov r9d, [rax + DTY_grow]
    # the edges' gravity: a growing edge takes an insert at it
    mov r10d, GR_RIGHT
    test r9d, DG_START
    jz 1f
    mov r10d, GR_LEFT
1:  mov r11d, GR_LEFT
    test r9d, DG_END
    jz 2f
    mov r11d, GR_RIGHT
2:  mov rax, [r15 + DR_start]
    cmp rax, [r15 + DR_end]
    jne 3f
    test r9d, r9d
    jnz 3f
    mov r10d, GR_RIGHT          # an empty range moves whole
    mov r11d, GR_RIGHT
3:  push r11
    push r11
    mov rdi, [r15 + DR_start]
    mov rsi, [r12 + TE_pos]
    mov rdx, [r12 + TE_del]
    mov rcx, [r12 + TE_ins]
    mov r8d, r10d
    call tape_shift
    mov r10, rax
    pop r11
    pop r11
    push r10
    push r10
    mov rdi, [r15 + DR_end]
    mov rsi, [r12 + TE_pos]
    mov rdx, [r12 + TE_del]
    mov rcx, [r12 + TE_ins]
    mov r8d, r11d
    call tape_shift
    pop r10
    pop r10
    # a deletion: an emptied range goes; an empty one strictly inside it too
    cmp qword ptr [r12 + TE_del], 0
    je 6f
    mov rcx, [r15 + DR_start]
    cmp rcx, [r15 + DR_end]
    je 4f
    cmp r10, rax
    jne 6f
    jmp 5f
4:  mov rdx, [r12 + TE_pos]
    cmp rcx, rdx
    jbe 6f
    add rdx, [r12 + TE_del]
    cmp rcx, rdx
    jae 6f
5:  mov rdi, r13
    mov rsi, r15
    call dr_drop
    jmp .Lds_each
6:  mov [r15 + DR_start], r10
    mov [r15 + DR_end], rax
    inc r14
    jmp .Lds_each
.Lds_done:
    mov rdi, r13
    call pool_compact
    EPILOGUE

# deco_clear_owner(ext): the extension stopped: its types and ranges go, on every document
FN deco_clear_owner
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 5f
    imul rax, r12, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r12
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 1b
    mov r13, [rax + DOC_pres]
    test r13, r13
    jz 1b
    inc qword ptr [r13 + PRS_gen]
    xor r14d, r14d
2:  cmp r14, [r13 + PRS_deco + VEC_len]
    jae 1b
    imul rsi, r14, DR_SIZE
    add rsi, [r13 + PRS_deco + VEC_ptr]
    mov eax, [rsi + DR_type]
    imul rax, rax, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    cmp [rax + DTY_owner], rbx
    je 3f
    inc r14
    jmp 2b
3:  mov rdi, r13
    call dr_drop
    jmp 2b
5:  xor ecx, ecx
6:  cmp rcx, [rip + g_dtypes + VEC_len]
    jae 7f
    imul rax, rcx, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    inc rcx
    cmp [rax + DTY_owner], rbx
    jne 6b
    mov qword ptr [rax + DTY_owner], 0
    jmp 6b
7:  inc qword ptr [rip + g_deco_gen]
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# deco_doc_gone(doc): caches that name the document forget it
FN deco_doc_gone
    cmp [rip + dw_doc], rdi
    jne 1f
    mov qword ptr [rip + dw_doc], 0
    mov qword ptr [rip + dw_n], 0
1:  cmp [rip + tk_doc], rdi
    jne 2f
    mov qword ptr [rip + tk_doc], 0
2:  ret

# ---------------- the frame's window ----------------

# type_of(range index in eax, r13 ps) -> rax DT*, rcx DR*
type_of:
    imul rcx, rax, DR_SIZE
    add rcx, [r13 + PRS_deco + VEC_ptr]
    mov eax, [rcx + DR_type]
    imul rax, rax, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    ret

# deco_frame(doc, first line, last line): the ranges that touch the lines, in priority order
FN deco_frame
    PROLOGUE 16
    mov rbx, rdi
    mov dword ptr [rip + pieces], 0
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz .Ldf_none
    cmp qword ptr [r13 + PRS_deco + VEC_len], 0
    je .Ldf_none
    cmp rdx, [rbx + DOC_nlines]
    jb 1f
    mov rdx, [rbx + DOC_nlines]
    dec rdx
1:  cmp [rip + dw_doc], rbx
    jne 2f
    mov rax, [rbx + DOC_version]
    cmp [rip + dw_ver], rax
    jne 2f
    mov rax, [r13 + PRS_gen]
    cmp [rip + dw_gen], rax
    jne 2f
    mov rax, [rip + g_deco_gen]
    cmp [rip + dw_tgen], rax
    jne 2f
    cmp [rip + dw_l1], rsi
    jne 2f
    cmp [rip + dw_l2], rdx
    je .Ldf_ret
2:  mov [rip + dw_doc], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + dw_ver], rax
    mov rax, [r13 + PRS_gen]
    mov [rip + dw_gen], rax
    mov rax, [rip + g_deco_gen]
    mov [rip + dw_tgen], rax
    mov [rip + dw_l1], rsi
    mov [rip + dw_l2], rdx
    mov qword ptr [rip + dw_n], 0
    mov dword ptr [rip + dw_over], 0
    mov r12, rdx
    mov rdi, rbx
    call doc_line_start
    mov r14, rax                # lo
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r15, rax                # hi (the last line's line feed)
    cmp qword ptr [rip + dw_cap], DECO_PIECES
    jae 3f
    mov edi, DECO_PIECES * 8
    call mem_alloc
    mov [rip + dw_keys], rax
    mov qword ptr [rip + dw_cap], DECO_PIECES
3:  xor r12d, r12d
.Ldf_each:
    cmp r12, [r13 + PRS_deco + VEC_len]
    jae .Ldf_sort
    mov eax, r12d
    call type_of
    inc r12
    cmp qword ptr [rax + DTY_owner], 0
    je .Ldf_each
    cmp [rcx + DR_start], r15
    ja .Ldf_each
    cmp [rcx + DR_end], r14
    jb .Ldf_each
    mov rdx, [rip + dw_n]
    cmp rdx, DECO_PIECES
    jae .Ldf_over
    # key: priority, the extension's order, the type's registration
    movzx r8d, byte ptr [rax + DTY_prio]
    shl r8, 56
    mov r9, [rax + DTY_owner]
    sub r9, [rip + g_exts + VEC_ptr]
    shr r9, 6                   # (EXT_SIZE is larger than 64: monotone in the index)
    and r9d, 0xfff
    shl r9, 44
    or r8, r9
    mov r9d, [rax + DTY_seq]
    and r9d, 0xfff
    shl r9, 32
    or r8, r9
    lea r9, [r12 - 1]
    or r8, r9
    mov rax, [rip + dw_keys]
    mov [rax + rdx*8], r8
    inc qword ptr [rip + dw_n]
    jmp .Ldf_each
.Ldf_over:
    mov dword ptr [rip + dw_over], 1
    jmp .Ldf_each
.Ldf_sort:
    mov rdi, [rip + dw_keys]
    mov rsi, [rip + dw_n]
    call sort_u64
.Ldf_ret:
    EPILOGUE
.Ldf_none:
    mov qword ptr [rip + dw_n], 0
    mov qword ptr [rip + dw_doc], 0
    EPILOGUE

# ---------------- drawing ----------------

# win_at(i, r13 ps) -> rax DT*, rcx DR* of the window's i-th range
win_at:
    mov rax, [rip + dw_keys]
    mov eax, [rax + rdi*8]
    jmp type_of

# deco_line_back(doc, line, y, h): whole-line backgrounds of the ranges that touch the line
FN deco_line_back
    PROLOGUE 32
    cmp qword ptr [rip + dw_n], 0
    je 9f
    cmp [rip + dw_doc], rdi
    jne 9f
    mov rbx, rdi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov r13, [rbx + DOC_pres]
    mov rdi, rbx
    mov r12, rsi
    call doc_line_start
    mov r14, rax                # line start
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r15, rax                # its line feed
    xor r12d, r12d
1:  cmp r12, [rip + dw_n]
    jae 9f
    mov rdi, r12
    call win_at
    inc r12
    test dword ptr [rax + DTY_flags], DTYF_LINEBG
    jz 1b
    cmp [rcx + DR_start], r15
    ja 1b
    mov rdx, [rcx + DR_end]
    cmp rdx, r14
    jb 1b
    jne 2f
    cmp rdx, [rcx + DR_start]   # ending at the line's start: only an empty range is on it
    jne 1b
2:  lea rdi, [rax + DTY_linebg]
    call deco_color
    mov r8d, eax
    mov edi, [rip + g_ed_tx]
    sub edi, [rip + g_mt + 4*MI_4]
    mov edx, [rip + g_ed_x]
    add edx, [rip + g_ed_w]
    sub edx, edi
    mov esi, [rsp]
    mov ecx, [rsp + 4]
    call gfx_fill
    jmp 1b
9:  EPILOGUE

# row_clip(DR* rcx) -> rax, rdx the range's part of the row as offsets in the line (signed; rax >= rdx:
# none)
row_clip:
    mov rax, [rcx + DR_start]
    sub rax, [rip + g_row_lstart]
    mov rdx, [rcx + DR_end]
    sub rdx, [rip + g_row_lstart]
    cmp rax, [rip + g_row_from]
    jge 1f
    mov rax, [rip + g_row_from]
1:  cmp rdx, [rip + g_row_to]
    jle 2f
    mov rdx, [rip + g_row_to]
2:  ret

# piece_x(offset) -> eax the x of a byte offset of the row
piece_x:
    mov rdx, rdi
    mov rdi, [rip + g_row_text]
    mov rsi, [rip + g_row_from]
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rip + g_row_x]
    ret

# deco_row_back(): the row's backgrounds (behind the selection), and its text-color spans
FN deco_row_back
    PROLOGUE 32
    mov dword ptr [rip + g_deco_spans], 0
    mov qword ptr [rip + sp_i], 0
    mov dword ptr [rip + g_row_fx], 0
    mov rbx, [rip + g_row_doc]
    call marks_fx               # diagnostics tagged unnecessary fade their text
    cmp qword ptr [rip + dw_n], 0
    je 9f
    cmp [rip + dw_doc], rbx
    jne 9f
    mov r13, [rbx + DOC_pres]
    xor r12d, r12d
1:  cmp r12, [rip + dw_n]
    jae 9f
    mov rdi, r12
    call win_at
    inc r12
    mov r14, rax                # DT*
    mov r15, rcx                # DR*
    test dword ptr [r14 + DTY_flags], DTYF_COLOR | DTYF_FADED
    jz 2f
    call row_clip
    cmp rax, rdx
    jge 2f
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r14
    call span_paint
2:  test dword ptr [r14 + DTY_flags], DTYF_BG
    jz 1b
    mov rcx, r15
    call row_clip
    cmp rax, rdx
    jge 1b
    call piece_count
    jz 1b
    mov [rsp], rdx
    mov rdi, rax
    call piece_x
    mov [rsp + 8], eax
    mov rdi, [rsp]
    call piece_x
    sub eax, [rsp + 8]
    jle 1b
    mov [rsp + 12], eax
    lea rdi, [r14 + DTY_bg]
    call deco_color
    mov r8d, eax
    mov edi, [rsp + 8]
    mov esi, [rip + g_row_y]
    mov edx, [rsp + 12]
    mov ecx, [rip + g_lh]
    call gfx_fill
    jmp 1b
9:  mov eax, [rip + g_deco_spans]
    add eax, [rip + mf_n]
    mov [rip + g_row_fx], eax
    EPILOGUE

# marks_fx(rbx doc): the row's parts that marks tagged unnecessary cover, as sorted, merged
# intervals in mf_buf (offsets in the line)
marks_fx:
    PROLOGUE
    mov qword ptr [rip + mf_n], 0
    mov qword ptr [rip + mf_i], 0
    mov r12, [rbx + DOC_xmarks]
    test r12, r12
    jz 9f
    xor r13d, r13d
1:  cmp r13, [r12 + VEC_len]
    jae 5f
    imul r14, r13, MK_SIZE
    add r14, [r12 + VEC_ptr]
    inc r13
    test dword ptr [r14 + MK_pad], MKT_UNNECESSARY
    jz 1b
    mov rdi, r14
    call mark_live
    test eax, eax
    jz 1b
    mov rax, [r14 + MK_start]
    sub rax, [rip + g_row_lstart]
    mov rdx, [r14 + MK_end]
    sub rdx, [rip + g_row_lstart]
    cmp rax, [rip + g_row_from]
    jge 2f
    mov rax, [rip + g_row_from]
2:  cmp rdx, [rip + g_row_to]
    jle 3f
    mov rdx, [rip + g_row_to]
3:  cmp rax, rdx
    jge 1b
    # insert sorted by start
    mov rcx, [rip + mf_n]
    cmp rcx, MF_MAX
    jae 1b
    lea r8, [rip + mf_buf]
4:  test rcx, rcx
    jz 41f
    mov r10, rcx
    shl r10, 4
    mov r9, [r8 + r10 - 16]
    cmp r9, rax
    jle 41f
    mov [r8 + r10], r9
    mov r9, [r8 + r10 - 8]
    mov [r8 + r10 + 8], r9
    dec rcx
    jmp 4b
41: mov rdi, rcx
    shl rdi, 4
    mov [r8 + rdi], rax
    mov [r8 + rdi + 8], rdx
    inc qword ptr [rip + mf_n]
    jmp 1b
5:  # overlapping ones merged
    lea r8, [rip + mf_buf]
    xor ecx, ecx                # read
    xor edx, edx                # write
6:  cmp rcx, [rip + mf_n]
    jae 8f
    mov rax, rcx
    shl rax, 4
    mov r9, [r8 + rax]
    mov r10, [r8 + rax + 8]
    inc rcx
    test rdx, rdx
    jz 7f
    mov rax, rdx
    shl rax, 4
    cmp r9, [r8 + rax - 8]
    jg 7f
    cmp r10, [r8 + rax - 8]
    jle 6b
    mov [r8 + rax - 8], r10
    jmp 6b
7:  mov rax, rdx
    shl rax, 4
    mov [r8 + rax], r9
    mov [r8 + rax + 8], r10
    inc rdx
    jmp 6b
8:  mov [rip + mf_n], rdx
9:  EPILOGUE

# piece_count() -> ZF 1 when the frame's piece budget is spent (keeps rax, rdx)
piece_count:
    cmp dword ptr [rip + pieces], DECO_PIECES
    jae 1f
    inc dword ptr [rip + pieces]    # (never 0: ZF is clear)
    ret
1:  cmp eax, eax
    ret

# span_paint(from, to, DT*): the type's text color over [from, to) of the row's spans (the later,
# higher-priority one wins where they overlap)
span_paint:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov rbx, rdx
    xor r14d, r14d              # the span's color and flags
    xor r15d, r15d
    test dword ptr [rbx + DTY_flags], DTYF_COLOR
    jz 1f
    lea rdi, [rbx + DTY_color]
    call deco_color
    mov r14d, eax
    or r15d, SPF_COLOR
1:  test dword ptr [rbx + DTY_flags], DTYF_FADED
    jz 2f
    or r15d, SPF_FADED
2:  # the old list into sp_tmp, parts outside [from, to) kept, the new span in its place
    lea rdi, [rip + sp_tmp]
    lea rsi, [rip + sp_buf]
    mov edx, [rip + g_deco_spans]
    imul edx, edx, SP_SIZE
    call memcpy
    mov r12d, [rip + g_deco_spans]      # old count
    xor r13d, r13d              # written
    xor ecx, ecx                # read
    xor r8d, r8d                # inserted
3:  cmp ecx, r12d
    jae .Lsp_tail
    imul r9, rcx, SP_SIZE
    lea r10, [rip + sp_tmp]
    add r9, r10
    inc ecx
    mov rax, [r9 + 8]           # its to
    cmp rax, [rsp]
    jbe .Lsp_keep               # wholly before
    mov rax, [r9]
    cmp rax, [rsp + 8]
    jb 4f
    # wholly after: the new one first
    test r8d, r8d
    jnz .Lsp_keep
    call .Lsp_new
    jmp .Lsp_keep
4:  # overlapping: its part before, the new one, its part after
    mov rax, [r9]
    cmp rax, [rsp]
    jae 5f
    call .Lsp_copy
    mov rax, [rsp]
    mov [r10 + 8], rax
5:  test r8d, r8d
    jnz 6f
    call .Lsp_new
6:  mov rax, [r9 + 8]
    cmp rax, [rsp + 8]
    jbe 3b
    call .Lsp_copy
    mov rax, [rsp + 8]
    mov [r10], rax
    jmp 3b
.Lsp_keep:
    call .Lsp_copy
    jmp 3b
.Lsp_tail:
    test r8d, r8d
    jnz 7f
    call .Lsp_new
7:  mov [rip + g_deco_spans], r13d
    EPILOGUE
# .Lsp_copy: span r9 to the output -> r10 its copy
.Lsp_copy:
    cmp r13d, SP_MAX
    jae 1f
    imul r10, r13, SP_SIZE
    lea rax, [rip + sp_buf]
    add r10, rax
    mov rax, [r9]
    mov [r10], rax
    mov rax, [r9 + 8]
    mov [r10 + 8], rax
    mov rax, [r9 + 16]
    mov [r10 + 16], rax
    inc r13d
    ret
1:  lea r10, [rip + sp_spare]
    ret
.Lsp_new:
    mov r8d, 1
    cmp r13d, SP_MAX
    jae 1f
    imul r10, r13, SP_SIZE
    lea rax, [rip + sp_buf]
    add r10, rax
    mov rax, [rsp + 8 + 8]      # (the caller's frame, under the return address)
    mov [r10 + 8], rax
    mov rax, [rsp + 8]
    mov [r10], rax
    mov [r10 + 16], r14d
    mov [r10 + 20], r15d
    inc r13d
1:  ret

# deco_span_color(offset, color) -> eax the text color of the glyph at a byte offset of the row: a
# decoration's color, faded halfway to the background; offsets come in ascending order
FN deco_span_color
    mov eax, esi
    xor r9d, r9d                # faded
    mov rcx, [rip + sp_i]
1:  cmp ecx, [rip + g_deco_spans]
    jae 4f
    imul rdx, rcx, SP_SIZE
    lea r8, [rip + sp_buf]
    add rdx, r8
    cmp [rdx + 8], rdi
    ja 2f
    inc rcx
    jmp 1b
2:  cmp [rdx], rdi
    ja 4f
    test dword ptr [rdx + 20], SPF_COLOR
    jz 3f
    mov eax, [rdx + 16]
3:  test dword ptr [rdx + 20], SPF_FADED
    jz 4f
    mov r9d, 1
4:  mov [rip + sp_i], rcx
    # the marks' faded parts
    mov rcx, [rip + mf_i]
    lea r8, [rip + mf_buf]
5:  cmp rcx, [rip + mf_n]
    jae 7f
    mov rdx, rcx
    shl rdx, 4
    cmp [r8 + rdx + 8], rdi
    ja 6f
    inc rcx
    jmp 5b
6:  cmp [r8 + rdx], rdi
    ja 7f
    mov r9d, 1
7:  mov [rip + mf_i], rcx
    test r9d, r9d
    jz 9f
    COLOR r8d, T_BG
    and eax, 0xfefefe
    and r8d, 0xfefefe
    shr eax, 1
    shr r8d, 1
    add eax, r8d
    or eax, 0xff000000
9:  ret

# deco_row_front(): the row's strikethroughs, underlines and borders (over the glyphs)
FN deco_row_front
    PROLOGUE 48
    call marks_strike           # diagnostics tagged deprecated
    cmp qword ptr [rip + dw_n], 0
    je 9f
    mov rbx, [rip + g_row_doc]
    cmp [rip + dw_doc], rbx
    jne 9f
    mov r13, [rbx + DOC_pres]
    xor r12d, r12d
.Lrf_each:
    cmp r12, [rip + dw_n]
    jae 9f
    mov rdi, r12
    call win_at
    inc r12
    test dword ptr [rax + DTY_flags], DTYF_STRIKE | DTYF_UNDER | DTYF_BORDER
    jz .Lrf_each
    mov r14, rax
    call row_clip
    cmp rax, rdx
    jge .Lrf_each
    call piece_count
    jz .Lrf_each
    mov [rsp], rdx
    mov rdi, rax
    call piece_x
    mov [rsp + 8], eax          # x
    mov rdi, [rsp]
    call piece_x
    sub eax, [rsp + 8]
    jle .Lrf_each
    mov [rsp + 12], eax         # w
    test dword ptr [r14 + DTY_flags], DTYF_STRIKE
    jz 1f
    lea rdi, [r14 + DTY_strike]
    call deco_color
    cmp eax, 1
    jne 11f
    COLOR eax, T_FG             # "-": the text's color
11: mov r8d, eax
    mov edi, [rsp + 8]
    mov esi, [rip + g_lh]
    shr esi, 1
    add esi, [rip + g_row_y]
    mov edx, [rsp + 12]
    M ecx, MI_1
    call gfx_fill
1:  test dword ptr [r14 + DTY_flags], DTYF_UNDER
    jz 2f
    lea rdi, [r14 + DTY_under]
    call deco_color
    mov edi, [r14 + DTY_ustyle]
    mov esi, eax
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    mov r8d, [rip + g_row_y]
    call underline_draw
2:  test dword ptr [r14 + DTY_flags], DTYF_BORDER
    jz .Lrf_each
    lea rdi, [r14 + DTY_border]
    call deco_color
    mov [rsp + 16], eax
    mov eax, [r14 + DTY_bwidth]
    imul eax, [rip + g_mt + 4*MI_1]
    mov [rsp + 20], eax
    # four sides
    mov edi, [rsp + 8]
    mov esi, [rip + g_row_y]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 20]
    mov r8d, [rsp + 16]
    call gfx_fill
    mov edi, [rsp + 8]
    mov esi, [rip + g_row_y]
    add esi, [rip + g_lh]
    sub esi, [rsp + 20]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 20]
    mov r8d, [rsp + 16]
    call gfx_fill
    mov edi, [rsp + 8]
    mov esi, [rip + g_row_y]
    mov edx, [rsp + 20]
    mov ecx, [rip + g_lh]
    mov r8d, [rsp + 16]
    call gfx_fill
    mov edi, [rsp + 8]
    add edi, [rsp + 12]
    sub edi, [rsp + 20]
    mov esi, [rip + g_row_y]
    mov edx, [rsp + 20]
    mov ecx, [rip + g_lh]
    mov r8d, [rsp + 16]
    call gfx_fill
    jmp .Lrf_each
9:  EPILOGUE

# marks_strike(): a line through the row's parts that marks tagged deprecated cover
marks_strike:
    PROLOGUE 16
    mov rbx, [rip + g_row_doc]
    mov r12, [rbx + DOC_xmarks]
    test r12, r12
    jz 9f
    xor r13d, r13d
1:  cmp r13, [r12 + VEC_len]
    jae 9f
    imul r14, r13, MK_SIZE
    add r14, [r12 + VEC_ptr]
    inc r13
    test dword ptr [r14 + MK_pad], MKT_DEPRECATED
    jz 1b
    mov rdi, r14
    call mark_live
    test eax, eax
    jz 1b
    mov rax, [r14 + MK_start]
    sub rax, [rip + g_row_lstart]
    mov rdx, [r14 + MK_end]
    sub rdx, [rip + g_row_lstart]
    cmp rax, [rip + g_row_from]
    jge 2f
    mov rax, [rip + g_row_from]
2:  cmp rdx, [rip + g_row_to]
    jle 3f
    mov rdx, [rip + g_row_to]
3:  cmp rax, rdx
    jge 1b
    mov [rsp], rdx
    mov rdi, rax
    call piece_x
    mov r15d, eax
    mov rdi, [rsp]
    call piece_x
    sub eax, r15d
    jle 1b
    mov edx, eax
    mov edi, r15d
    mov esi, [rip + g_lh]
    shr esi, 1
    add esi, [rip + g_row_y]
    M ecx, MI_1
    COLOR r8d, T_FG
    call gfx_fill
    jmp 1b
9:  EPILOGUE

# underline_draw(style, argb, x, w, row y): a line under [x, x + w) in one of the US_* styles
FN underline_draw
    PROLOGUE 32
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    add r15d, [rip + g_lh]
    sub r15d, [rip + g_mt + 4*MI_2]     # the base line of the underline
    M eax, MI_1
    mov [rsp], eax              # thickness
    cmp ebx, US_DOUBLE
    je .Lud_double
    cmp ebx, US_DOTTED
    je .Lud_dotted
    cmp ebx, US_DASHED
    je .Lud_dashed
    cmp ebx, US_SQUIGGLE
    je .Lud_squiggle
    mov edi, r13d
    mov esi, r15d
    mov edx, r14d
    mov ecx, [rsp]
    mov r8d, r12d
    call gfx_fill
    EPILOGUE
.Lud_double:
    mov edi, r13d
    mov esi, r15d
    mov edx, r14d
    mov ecx, [rsp]
    mov r8d, r12d
    call gfx_fill
    mov edi, r13d
    mov esi, r15d
    sub esi, [rsp]
    sub esi, [rsp]
    mov edx, r14d
    mov ecx, [rsp]
    mov r8d, r12d
    call gfx_fill
    EPILOGUE
.Lud_dotted:
    mov eax, [rsp]
    mov [rsp + 4], eax          # on
    add eax, eax
    mov [rsp + 8], eax          # period
    jmp .Lud_dash
.Lud_dashed:
    mov eax, [rsp]
    lea eax, [rax + rax*2]
    mov [rsp + 4], eax
    mov eax, [rsp]
    imul eax, eax, 5
    mov [rsp + 8], eax
.Lud_dash:
    xor ebx, ebx
1:  cmp ebx, r14d
    jge 9f
    mov edx, [rsp + 4]
    mov eax, r14d
    sub eax, ebx
    cmp edx, eax
    cmovg edx, eax
    lea edi, [r13 + rbx]
    mov esi, r15d
    mov ecx, [rsp]
    mov r8d, r12d
    call gfx_fill
    add ebx, [rsp + 8]
    jmp 1b
.Lud_squiggle:
    # a zigzag: a pixel column at a time, up and down over two thicknesses
    xor ebx, ebx
2:  cmp ebx, r14d
    jge 9f
    mov eax, ebx
    xor edx, edx
    mov ecx, [rsp]
    shl ecx, 2                  # the period: four thicknesses
    div ecx
    mov eax, edx                # phase in the period
    mov ecx, [rsp]
    shl ecx, 1
    cmp eax, ecx
    jl 3f
    shl ecx, 1
    sub ecx, eax
    mov eax, ecx
3:  mov esi, r15d
    sub esi, eax
    add esi, [rsp]
    lea edi, [r13 + rbx]
    mov edx, 1
    mov ecx, [rsp]
    mov r8d, r12d
    call gfx_fill
    inc ebx
    jmp 2b
9:  EPILOGUE

# ---------------- gutter, scrollbar, tips ----------------

# deco_gutter_icon(doc, line) -> eax GS_* shape (0: none), edx argb: the highest-priority icon of
# the ranges that start on the line
FN deco_gutter_icon
    PROLOGUE
    xor r14d, r14d
    xor r15d, r15d
    cmp qword ptr [rip + dw_n], 0
    je 9f
    cmp [rip + dw_doc], rdi
    jne 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    xor ecx, ecx
    push rcx
    push rcx
1:  mov rcx, [rsp]
    cmp rcx, [rip + dw_n]
    jae 8f
    mov rdi, rcx
    inc qword ptr [rsp]
    call win_at
    test dword ptr [rax + DTY_flags], DTYF_GUTTER
    jz 1b
    push rax
    push rax
    mov rdi, rbx
    mov rsi, [rcx + DR_start]
    call doc_line_of
    mov rcx, rax
    pop rax
    pop rax
    cmp rcx, r12
    jne 1b
    mov r14d, [rax + DTY_gshape] # later ones are higher
    lea rdi, [rax + DTY_gutter]
    call deco_color
    mov r15d, eax
    jmp 1b
8:  pop rcx
    pop rcx
9:  mov eax, r14d
    mov edx, r15d
    EPILOGUE

# deco_gutter_tip(doc, line) -> rax the tip of the highest-priority icon on the line, or 0
FN deco_gutter_tip
    PROLOGUE 16
    xor r14d, r14d
    cmp qword ptr [rip + dw_n], 0
    je 9f
    cmp [rip + dw_doc], rdi
    jne 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    mov qword ptr [rsp], 0
1:  mov rdi, [rsp]
    cmp rdi, [rip + dw_n]
    jae 8f
    inc qword ptr [rsp]
    call win_at
    test dword ptr [rax + DTY_flags], DTYF_GUTTER
    jz 1b
    cmp word ptr [rcx + DR_tlen], 0
    je 1b
    mov r15, rcx
    mov rdi, rbx
    mov rsi, [rcx + DR_start]
    call doc_line_of
    cmp rax, r12
    jne 1b
    mov r14, r15
    jmp 1b
8:  test r14, r14
    jz 9f
    mov rdi, r14
    call tip_copy
    mov r14, rax
9:  mov rax, r14
    EPILOGUE

# tip_copy(DR* rdi, r13 ps) -> rax tipbuf with the range's tip
tip_copy:
    movzx edx, word ptr [rdi + DR_tlen]
    mov esi, [rdi + DR_text]
    movzx ecx, word ptr [rdi + DR_blen]
    add esi, ecx
    movzx ecx, word ptr [rdi + DR_alen]
    add esi, ecx
    add rsi, [r13 + PRS_dpool + SB_ptr]
    push rdx
    lea rdi, [rip + tipbuf]
    call memcpy
    pop rdx
    lea rax, [rip + tipbuf]
    mov byte ptr [rax + rdx], 0
    ret

# deco_tip_at(doc, pos) -> rax the tip of the highest-priority range holding the position, or 0
FN deco_tip_at
    PROLOGUE
    xor r14d, r14d
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    xor r15d, r15d
    mov r8, -1                  # the best priority so far
1:  cmp r15, [r13 + PRS_deco + VEC_len]
    jae 8f
    mov eax, r15d
    call type_of
    inc r15
    cmp qword ptr [rax + DTY_owner], 0
    je 1b
    cmp word ptr [rcx + DR_tlen], 0
    je 1b
    cmp [rcx + DR_start], r12
    ja 1b
    mov rdx, [rcx + DR_end]
    cmp rdx, r12
    ja 2f
    jb 1b
    cmp rdx, [rcx + DR_start]   # an empty range at the position holds it
    jne 1b
2:  movzx edx, byte ptr [rax + DTY_prio]
    cmp rdx, r8
    jl 1b
    mov r8, rdx
    mov r14, rcx
    jmp 1b
8:  test r14, r14
    jz 9f
    mov rdi, r14
    call tip_copy
    mov r14, rax
9:  mov rax, r14
    EPILOGUE

# deco_scroll_ticks(doc, x, y, w, h): the ranges' ticks in the vertical scrollbar's track
FN deco_scroll_ticks
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    cmp qword ptr [r13 + PRS_deco + VEC_len], 0
    je 9f
    cmp r8d, 4
    jl 9f
    movsxd r12, r8d             # rows
    # computed again only when something they depend on changed
    cmp [rip + tk_doc], rbx
    jne 1f
    mov rax, [rbx + DOC_version]
    cmp [rip + tk_ver], rax
    jne 1f
    mov rax, [r13 + PRS_gen]
    cmp [rip + tk_gen], rax
    jne 1f
    mov rax, [rip + g_deco_gen]
    cmp [rip + tk_tgen], rax
    jne 1f
    cmp [rip + tk_h], r12
    jne 1f
    mov rax, [rbx + DOC_nlines]
    cmp [rip + tk_lines], rax
    je .Ltk_draw
1:  mov [rip + tk_doc], rbx
    mov rax, [rbx + DOC_version]
    mov [rip + tk_ver], rax
    mov rax, [r13 + PRS_gen]
    mov [rip + tk_gen], rax
    mov rax, [rip + g_deco_gen]
    mov [rip + tk_tgen], rax
    mov [rip + tk_h], r12
    mov rax, [rbx + DOC_nlines]
    mov [rip + tk_lines], rax
    cmp r12, [rip + tk_cap]
    jbe 2f
    mov rdi, [rip + tk_rows]
    call mem_free
    mov rdi, [rip + tk_prio]
    call mem_free
    lea rdi, [r12*4]
    call mem_alloc
    mov [rip + tk_rows], rax
    mov rdi, r12
    call mem_alloc
    mov [rip + tk_prio], rax
    mov [rip + tk_cap], r12
2:  mov rdi, [rip + tk_rows]
    xor esi, esi
    lea rdx, [r12*4]
    call memset
    mov rdi, [rip + tk_prio]
    xor esi, esi
    mov rdx, r12
    call memset
    xor r14d, r14d
    xor r15d, r15d              # rows with a tick
3:  cmp r14, [r13 + PRS_deco + VEC_len]
    jae .Ltk_draw
    mov eax, r14d
    call type_of
    inc r14
    cmp qword ptr [rax + DTY_owner], 0
    je 3b
    test dword ptr [rax + DTY_flags], DTYF_SCROLL
    jz 3b
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, [rcx + DR_start]
    call doc_line_of
    # row = line * rows / (lines + 1)
    imul rax, r12
    mov rcx, [rbx + DOC_nlines]
    inc rcx
    xor edx, edx
    div rcx
    cmp rax, r12
    jb 4f
    lea rax, [r12 - 1]
4:  mov rdx, [rsp + 16]
    movzx ecx, byte ptr [rdx + DTY_prio]
    inc ecx                     # 1..101: 0 is empty
    mov rdi, [rip + tk_prio]
    movzx r8d, byte ptr [rdi + rax]
    test r8d, r8d
    jnz 5f
    cmp r15d, DECO_TICKS
    jae 3b
    inc r15d
5:  cmp ecx, r8d
    jb 3b
    mov [rdi + rax], cl
    mov [rsp + 20], rax
    lea rdi, [rdx + DTY_scroll]
    call deco_color
    mov rcx, [rsp + 20]
    mov rdi, [rip + tk_rows]
    mov [rdi + rcx*4], eax
    jmp 3b
.Ltk_draw:
    xor r14d, r14d
6:  cmp r14, r12
    jae 9f
    mov rax, [rip + tk_rows]
    mov r8d, [rax + r14*4]
    inc r14
    test r8d, r8d
    jz 6b
    mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_2]
    mov esi, [rsp + 4]
    add esi, r14d
    dec esi
    mov edx, [rsp + 8]
    sub edx, [rip + g_mt + 4*MI_4]
    M ecx, MI_2
    call gfx_fill
    jmp 6b
9:  EPILOGUE

# ---------------- the visible event ----------------

# deco_visible(doc, first, last): the lines the editor shows this frame (0-based; doc 0: none)
FN deco_visible
    xor eax, eax
    test rdi, rdi
    jz 1f
    mov rax, [rdi + DOC_id]
    inc rsi
    inc rdx
1:  cmp [rip + vis_doc], rax
    jne 2f
    cmp [rip + vis_l1], rsi
    jne 2f
    cmp [rip + vis_l2], rdx
    je 3f
2:  mov [rip + vis_doc], rax
    mov [rip + vis_l1], rsi
    mov [rip + vis_l2], rdx
3:  ret

# deco_visible_again(): an extension started: the visible event goes out again
FN deco_visible_again
    mov qword ptr [rip + vis_sent_doc], -1
    mov qword ptr [rip + vis_at], 0
    ret

# deco_visible_due() -> eax ms until the visible event is due, or -1
FN deco_visible_due
    mov rax, [rip + vis_doc]
    cmp rax, [rip + vis_sent_doc]
    jne 1f
    mov rax, [rip + vis_l1]
    cmp rax, [rip + vis_sent_l1]
    jne 1f
    mov rax, [rip + vis_l2]
    cmp rax, [rip + vis_sent_l2]
    jne 1f
    mov eax, -1
    ret
1:  sub rsp, 8
    call time_ms
    add rsp, 8
    mov rcx, [rip + vis_at]
    add rcx, VIS_EVERY_MS
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg eax, ecx
    ret

# deco_visible_tick(): "0 visible DOC L1 L2" to the extensions with decorations that know the
# document, when the lines changed and the last event is VIS_EVERY_MS old
FN deco_visible_tick
    PROLOGUE
    call deco_visible_due
    test eax, eax
    jnz 9f
    call time_ms
    mov [rip + vis_at], rax
    mov rax, [rip + vis_doc]
    mov [rip + vis_sent_doc], rax
    mov rax, [rip + vis_l1]
    mov [rip + vis_sent_l1], rax
    mov rax, [rip + vis_l2]
    mov [rip + vis_sent_l2], rax
    # the event's text
    lea rdi, [rip + evbuf]
    lea rsi, [rip + .Lev_visible]
    call cstr_copy
    mov rbx, rax
    mov rdi, rbx
    mov rsi, [rip + vis_doc]
    call fmt_u64
    add rbx, rax
    mov byte ptr [rbx], ' '
    inc rbx
    mov rdi, rbx
    mov rsi, [rip + vis_l1]
    call fmt_u64
    add rbx, rax
    mov byte ptr [rbx], ' '
    inc rbx
    mov rdi, rbx
    mov rsi, [rip + vis_l2]
    call fmt_u64
    add rbx, rax
    mov byte ptr [rbx], 10
    inc rbx
    lea rax, [rip + evbuf]
    sub rbx, rax
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 1b
    FEAT_TEST r13, FEAT_DECORATIONS
    jz 1b
    test dword ptr [r13 + EXT_needs], NEEDS_DOC_READ
    jz 1b
    mov rsi, [rip + vis_doc]
    test rsi, rsi
    jz 2f                       # none: everyone hears it
    mov rdi, r13
    call extproto_known
    test rax, rax
    jz 1b
    cmp qword ptr [rax + XK_phase], XP_NEED_OPEN
    je 1b
    cmp qword ptr [rax + XK_phase], XP_DORMANT
    je 1b
2:  mov rdi, r13
    lea rsi, [rip + evbuf]
    mov rdx, rbx
    call xp_send
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lev_visible: .asciz "0 visible "
.Le_unknown: .asciz "unknown no such request"
.Le_line: .asciz "syntax line "
.Le_toobig_types: .asciz "toobig 64 decoration types per extension, 512 in all"
.Le_toobig: .asciz "toobig more decorations than the caps allow"
.Le_readonly: .asciz "readonly a diff view"
.Le_notype: .asciz "syntax unknown decoration type"
.Le_badpos: .asciz "badpos position outside the document or inside a character"
.Le_stale: .asciz "stale "
.p2align 3
key_names: .quad .Lk_color, .Lk_background, .Lk_linebg, .Lk_border, .Lk_underline, .Lk_strike
    .quad .Lk_faded, .Lk_before, .Lk_after, .Lk_width, .Lk_gutter, .Lk_scrollbar, .Lk_grow
    .quad .Lk_priority, 0
key_fns: .quad k_color, k_background, k_linebg, k_border, k_underline, k_strike
    .quad k_faded, k_before, k_after, k_width, k_gutter, k_scrollbar, k_grow, k_priority
ustyle_names: .quad .Lu_solid, .Lu_double, .Lu_dotted, .Lu_dashed, .Lu_squiggle, 0
grow_names: .quad .Lg_none, .Lg_start, .Lg_end, .Lg_both, 0
# in GS_* order from 1
shape_names: .quad .Ls_dot, .Ls_circle, .Ls_ring, .Ls_square, .Ls_diamond, .Ls_triangle, .Ls_bar
    .quad .Ls_check, .Ls_cross, .Ls_plus, .Ls_minus, .Ls_arrow, 0
.Lk_color: .asciz "color"
.Lk_background: .asciz "background"
.Lk_linebg: .asciz "line-background"
.Lk_border: .asciz "border"
.Lk_underline: .asciz "underline"
.Lk_strike: .asciz "strike"
.Lk_faded: .asciz "faded"
.Lk_before: .asciz "before"
.Lk_after: .asciz "after"
.Lk_width: .asciz "width"
.Lk_gutter: .asciz "gutter"
.Lk_scrollbar: .asciz "scrollbar"
.Lk_grow: .asciz "grow"
.Lk_priority: .asciz "priority"
.Lu_solid: .asciz "solid"
.Lu_double: .asciz "double"
.Lu_dotted: .asciz "dotted"
.Lu_dashed: .asciz "dashed"
.Lu_squiggle: .asciz "squiggle"
.Lg_none: .asciz "none"
.Lg_start: .asciz "start"
.Lg_end: .asciz "end"
.Lg_both: .asciz "both"
.Ls_dot: .asciz "dot"
.Ls_circle: .asciz "circle"
.Ls_ring: .asciz "ring"
.Ls_square: .asciz "square"
.Ls_diamond: .asciz "diamond"
.Ls_triangle: .asciz "triangle"
.Ls_bar: .asciz "bar"
.Ls_check: .asciz "check"
.Ls_cross: .asciz "cross"
.Ls_plus: .asciz "plus"
.Ls_minus: .asciz "minus"
.Ls_arrow: .asciz "arrow"

.bss
.p2align 3
dt_scratch: .zero DTY_SIZE
sp_spare: .zero SP_SIZE
