# editor presentation: headless control commands (pres_ctl, in control.s's ctl_tables). Lines and columns are 1-based, columns in bytes, as in the protocol.
#   print-viewport              "view mode=lines|wrap top=L off=N rows=R content=PX"
#   print-xy LINE COL           "X Y": the caret's x at that position and its row's middle
#   print-hit X Y               "text L C" | "left-lane L" | "digits L" | "fold-lane L" | "git L" | "none"
#   print-present deco|types|glyphs|tape
#   glyph-test                  a test kind in the left lane (clicks toggle a circle; logged)
#   glyph LINE SHAPE            the test kind's glyph on a line (0 removes)
.include "rhun.inc"

.bss
.p2align 3
args: .quad 0, 0                # the rest of the command line: ptr, len
outp: .quad 0                   # what the command prints into
test_kind: .long 0
.p2align 3
clicks: .zero SB_SIZE           # the test kind's clicks, "L button" each
keys: .zero VEC_SIZE
nbuf: .zero 32

.text

#   probe-plant stale|under     the frame probes' positive controls (headless.s)
# take_args(out, rest, len): a command's output buffer and arguments (control.s's ctl_tables call
# each command with them)
take_args:
    mov [rip + outp], rdi
    mov [rip + args], rsi
    mov [rip + args + 8], rdx
    ret

# arg_word() -> rax, rdx the next word of the arguments
arg_word:
    mov rdi, [rip + args]
    mov rsi, [rip + args + 8]
    call next_word
    add [rip + args], rcx
    sub [rip + args + 8], rcx
    ret

# arg_int() -> rax the next argument as a number (0 when missing)
arg_int:
    call arg_word
    mov rdi, rax
    mov rsi, rdx
    jmp parse_u64

# out_cstr(s), out_u64(v), out_byte(b)
out_cstr:
    mov rsi, rdi
    mov rdi, [rip + outp]
    jmp sb_push_cstr
out_u64:
    mov rsi, rdi
    mov rdi, [rip + outp]
    jmp sb_push_u64
out_byte:
    mov esi, edi
    mov rdi, [rip + outp]
    jmp sb_push_byte
out_bytes:
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + outp]
    jmp sb_push

# frame(): a frame drawn, so the layout is the current one
frame:
    mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rip + g_headless], 0
    je 1f
    PCALL P_draw
1:  ret

# ---------------- print-view ----------------

c_print_view:
    call take_args
    PROLOGUE
    call frame
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    lea rdi, [rip + .Ls_view_lines]
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 1f
    lea rdi, [rip + .Ls_view_wrap]
1:  call out_cstr
    mov rdi, [rbx + DOC_scrolly]
    shr rdi, 8
    inc rdi
    call out_u64
    lea rdi, [rip + .Ls_off]
    call out_cstr
    mov rdi, [rbx + DOC_scrolly]
    and edi, 255
    cmp dword ptr [rip + cfg_word_wrap], 0
    je 2f
    mov rdi, [rbx + DOC_woff]
2:  call out_u64
    lea rdi, [rip + .Ls_rows]
    call out_cstr
    mov eax, [rip + g_ed_h]
    xor edx, edx
    div dword ptr [rip + g_lh]
    mov edi, eax
    call out_u64
    lea rdi, [rip + .Ls_content]
    call out_cstr
    mov rdi, [rbx + DOC_nlines]
    inc rdi
    movsxd rax, dword ptr [rip + g_lh]
    imul rdi, rax
    call out_u64
    mov edi, 10
    call out_byte
9:  xor eax, eax
    EPILOGUE

# ---------------- print-xy ----------------

c_print_xy:
    call take_args
    PROLOGUE
    call arg_int
    mov r13, rax                # line
    call arg_int
    mov r14, rax                # col
    call frame
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 8f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call mark_pos
    test rax, rax
    js 8f
    mov r15, rax
    dec r13
    # y: rows from the top line (lines mode)
    mov rax, [rbx + DOC_scrolly]
    mov rcx, rax
    sar rax, 8
    mov rdx, r13
    sub rdx, rax
    movsxd rax, dword ptr [rip + g_lh]
    imul rdx, rax
    and ecx, 255
    imul ecx, [rip + g_lh]
    shr ecx, 8
    sub rdx, rcx
    movsxd rax, dword ptr [rip + g_ed_y]
    add rdx, rax
    mov eax, [rip + g_lh]
    shr eax, 1
    add rdx, rax
    mov r12, rdx
    # x: the columns before it
    mov rdi, rbx
    mov rsi, r13
    call doc_line_text
    mov rdi, rax
    xor esi, esi
    lea rdx, [r14 - 1]
    call seg_cols
    imul eax, [rip + g_cw]
    add eax, [rip + g_ed_tx]
    sub rax, [rbx + DOC_scrollx]
    mov rdi, rax
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r12
    call out_u64
    mov edi, 10
    call out_byte
    xor eax, eax
    EPILOGUE
8:  lea rdi, [rip + .Ls_none]
    call out_cstr
    mov rax, -1
    EPILOGUE

# ---------------- print-hit ----------------

c_print_hit:
    call take_args
    PROLOGUE
    call arg_int
    mov r13, rax
    call arg_int
    mov r14, rax
    call frame
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 8f
    mov edi, r13d
    mov esi, r14d
    call gutter_hit
    test eax, eax
    jz 2f
    lea rcx, [rip + lane_words]
    mov rdi, [rcx + rax*8]
    push rdx
    push rdx
    call out_cstr
    pop rdi
    pop rdi
    inc rdi
    call out_u64
    jmp 7f
2:  cmp r13d, [rip + g_ed_tx]
    jl 8f
    cmp r14d, [rip + g_ed_y]
    jl 8f
    mov eax, [rip + g_ed_y]
    add eax, [rip + g_ed_h]
    cmp r14d, eax
    jge 8f
    mov rdi, rbx
    mov esi, r13d
    mov edx, r14d
    call pos_at_point_editor
    mov r15, rax
    lea rdi, [rip + .Ls_text]
    call out_cstr
    mov rdi, rbx
    mov rsi, r15
    call put_pos
7:  mov edi, 10
    call out_byte
    xor eax, eax
    EPILOGUE
8:  lea rdi, [rip + .Ls_none]
    call out_cstr
    xor eax, eax
    EPILOGUE

# put_pos(doc, pos): "L C" (1-based line and byte column)
put_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    lea rdi, [rax + 1]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov rdi, r12
    sub rdi, rax
    inc rdi
    call out_u64
    EPILOGUE

# put_lc(doc, pos): "L:C"
put_lc:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    lea rdi, [rax + 1]
    call out_u64
    mov edi, ':'
    call out_byte
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov rdi, r12
    sub rdi, rax
    inc rdi
    call out_u64
    EPILOGUE

# ---------------- print-present ----------------

c_print_present:
    call take_args
    PROLOGUE
    call arg_word
    mov r12, rax
    mov r13, rdx
    call frame
    mov rbx, [rip + g_doc]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_types]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_types
    test rbx, rbx
    jz 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_deco]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_deco
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_glyphs]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_glyphs
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_tape]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_tape
9:  xor eax, eax
    EPILOGUE
.Lpp_types:
    xor r12d, r12d
1:  cmp r12, [rip + g_dtypes + VEC_len]
    jae 9b
    imul r13, r12, DTY_SIZE
    add r13, [rip + g_dtypes + VEC_ptr]
    inc r12
    mov rax, [r13 + DTY_owner]
    test rax, rax
    jz 1b
    lea rdi, [rip + .Ls_type]
    call out_cstr
    mov rax, [r13 + DTY_owner]
    mov rdi, [rax + EXT_owner]
    call out_cstr
    mov edi, '/'
    call out_byte
    mov rax, [r13 + DTY_owner]
    mov rdi, [rax + EXT_name]
    call out_cstr
    mov edi, ' '
    call out_byte
    lea rdi, [r13 + DTY_name]
    call out_cstr
    lea rdi, [rip + .Ls_flags]
    call out_cstr
    mov edi, [r13 + DTY_flags]
    call out_u64
    lea rdi, [rip + .Ls_prio]
    call out_cstr
    mov edi, [r13 + DTY_prio]
    call out_u64
    mov edi, 10
    call out_byte
    jmp 1b
.Lpp_deco:
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 9b
    # sorted by start: keys start << 20 | index
    mov qword ptr [rip + keys + VEC_len], 0
    xor r12d, r12d
2:  cmp r12, [r14 + PS_deco + VEC_len]
    jae 3f
    imul rax, r12, DR_SIZE
    add rax, [r14 + PS_deco + VEC_ptr]
    mov r13, [rax + DR_start]
    shl r13, 20
    or r13, r12
    inc r12
    lea rdi, [rip + keys]
    mov esi, 8
    call vec_push
    mov [rax], r13
    jmp 2b
3:  mov rdi, [rip + keys + VEC_ptr]
    mov rsi, [rip + keys + VEC_len]
    call sort_u64
    xor r12d, r12d
4:  cmp r12, [rip + keys + VEC_len]
    jae 9b
    mov rax, [rip + keys + VEC_ptr]
    mov r13, [rax + r12*8]
    inc r12
    and r13d, 0xfffff
    imul r13, r13, DR_SIZE
    add r13, [r14 + PS_deco + VEC_ptr]
    lea rdi, [rip + .Ls_deco_sp]
    call out_cstr
    mov eax, [r13 + DR_type]
    imul rax, rax, DTY_SIZE
    add rax, [rip + g_dtypes + VEC_ptr]
    lea rdi, [rax + DTY_name]
    call out_cstr
    mov edi, ' '
    call out_byte
    mov rdi, rbx
    mov rsi, [r13 + DR_start]
    call put_lc
    mov edi, '-'
    call out_byte
    mov rdi, rbx
    mov rsi, [r13 + DR_end]
    call put_lc
    # its texts
    mov r15d, [r13 + DR_text]
    add r15, [r14 + PS_dpool + SB_ptr]
    movzx esi, word ptr [r13 + DR_blen]
    lea rdi, [rip + .Ls_before]
    call put_text
    movzx esi, word ptr [r13 + DR_alen]
    lea rdi, [rip + .Ls_after]
    call put_text
    movzx esi, word ptr [r13 + DR_tlen]
    lea rdi, [rip + .Ls_tip]
    call put_text
    mov edi, 10
    call out_byte
    jmp 4b
.Lpp_glyphs:
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 6f
    xor r12d, r12d
5:  cmp r12, [r14 + PS_glyphs + VEC_len]
    jae 6f
    imul r13, r12, GLE_SIZE
    add r13, [r14 + PS_glyphs + VEC_ptr]
    inc r12
    lea rdi, [rip + .Ls_glyph]
    call out_cstr
    mov rdi, rbx
    mov rsi, [r13 + GLE_pos]
    call doc_line_of
    lea rdi, [rax + 1]
    call out_u64
    lea rdi, [rip + .Ls_kind]
    call out_cstr
    mov edi, [r13 + GLE_kind]
    call out_u64
    lea rdi, [rip + .Ls_shape]
    call out_cstr
    movzx edi, byte ptr [r13 + GLE_glyph]
    call out_u64
    mov edi, 10
    call out_byte
    jmp 5b
6:  cmp qword ptr [rip + clicks + SB_len], 0
    je 9b
    mov rdi, [rip + clicks + SB_ptr]
    mov rsi, [rip + clicks + SB_len]
    call out_bytes
    jmp 9b
.Lpp_tape:
    mov r14, [rbx + DOC_pres]
    lea rdi, [rip + .Ls_tape_sp]
    call out_cstr
    xor edi, edi
    test r14, r14
    jz 7f
    mov rdi, [r14 + PS_tn]
7:  call out_u64
    lea rdi, [rip + .Ls_base]
    call out_cstr
    xor edi, edi
    test r14, r14
    jz 71f
    mov rdi, [r14 + PS_tbase]
71: call out_u64
    lea rdi, [rip + .Ls_version]
    call out_cstr
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, 10
    call out_byte
    jmp 9b

# put_text(label, len; r15 the text, advanced): " label=TEXT" when there is text
put_text:
    test esi, esi
    jz 9f
    push rsi
    push rsi
    call out_cstr
    pop rsi
    pop rsi
    push rsi
    push rsi
    mov rdi, r15
    call out_bytes
    pop rsi
    pop rsi
9:  add r15, rsi
    ret

# probe-plant stale|under: the next frame's probe finds a planted fault (headless.s)
c_probe_plant:
    call take_args
.ifndef WINDOWS
    PROLOGUE
    call arg_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Ls_stale]
    call str_eq_cstr
    mov ecx, 2
    sub ecx, eax
    mov [rip + g_probe_plant], ecx
    mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
.else
    xor eax, eax
    ret
.endif

# ---------------- the test kind ----------------

c_glyph_test:
    call take_args
    PROLOGUE
    cmp dword ptr [rip + test_kind], 0
    jne 9f
    mov edi, 30
    mov esi, GK_EMPTY | GK_RESERVE
    lea rdx, [rip + test_click]
    lea rcx, [rip + test_tip]
    mov r8d, GS_CIRCLE | T_ERROR << 8
    call gutter_kind
    mov [rip + test_kind], eax
9:  xor eax, eax
    EPILOGUE

c_glyph:
    call take_args
    PROLOGUE
    call arg_int
    mov r12, rax
    call arg_int
    mov r13, rax
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 9f
    cmp dword ptr [rip + test_kind], 0
    je 9f
    test r12, r12
    jz 9f
    mov esi, [rip + test_kind]
    lea rdx, [r12 - 1]
    mov ecx, r13d
    test ecx, ecx
    jz 1f
    or ecx, T_ACCENT << 8
1:  call gutter_glyph_set
9:  xor eax, eax
    EPILOGUE

# test_click(doc, line, button, glyph): toggles a red circle; "click L BUTTON GLYPH" is logged
test_click:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    lea rdi, [rip + clicks]
    lea rsi, [rip + .Ls_click]
    call sb_push_cstr
    lea rdi, [rip + clicks]
    lea rsi, [r12 + 1]
    call sb_push_u64
    lea rdi, [rip + clicks]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + clicks]
    mov esi, r13d
    call sb_push_u64
    lea rdi, [rip + clicks]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + clicks]
    movzx esi, r14b
    call sb_push_u64
    lea rdi, [rip + clicks]
    mov esi, 10
    call sb_push_byte
    cmp r13d, BTN_LEFT
    jne 9f
    xor ecx, ecx
    test r14d, r14d
    jnz 1f
    mov ecx, GS_CIRCLE | T_ERROR << 8
1:  mov rdi, rbx
    mov esi, [rip + test_kind]
    mov rdx, r12
    call gutter_glyph_set
9:  EPILOGUE

# test_tip(doc, line, glyph) -> rax the tooltip
test_tip:
    lea rax, [rip + .Ls_test_tip]
    ret

.section .rodata
.p2align 3
.globl pres_ctl
pres_ctl:                       # (control.s's ctl_tables)
    .quad .Lc_print_view, c_print_view, .Lc_print_xy, c_print_xy, .Lc_print_hit, c_print_hit
    .quad .Lc_print_present, c_print_present, .Lc_glyph_test, c_glyph_test, .Lc_glyph, c_glyph
    .quad .Lc_probe_plant, c_probe_plant
    .quad 0, 0
lane_words: .quad 0, .Ls_left, .Ls_digits, .Ls_fold, .Ls_git
.Lc_print_view: .asciz "print-viewport"
.Lc_print_xy: .asciz "print-xy"
.Lc_print_hit: .asciz "print-hit"
.Lc_print_present: .asciz "print-present"
.Lc_glyph_test: .asciz "glyph-test"
.Lc_glyph: .asciz "glyph"
.Lc_probe_plant: .asciz "probe-plant"
.Ls_stale: .asciz "stale"
.Ls_view_lines: .asciz "view mode=lines top="
.Ls_view_wrap: .asciz "view mode=wrap top="
.Ls_off: .asciz " off="
.Ls_rows: .asciz " rows="
.Ls_content: .asciz " content="
.Ls_none: .asciz "none\n"
.Ls_text: .asciz "text "
.Ls_left: .asciz "left-lane "
.Ls_digits: .asciz "digits "
.Ls_fold: .asciz "fold-lane "
.Ls_git: .asciz "git "
.Ls_types: .asciz "types"
.Ls_deco: .asciz "deco"
.Ls_glyphs: .asciz "glyphs"
.Ls_tape: .asciz "tape"
.Ls_type: .asciz "type "
.Ls_flags: .asciz " flags="
.Ls_prio: .asciz " prio="
.Ls_deco_sp: .asciz "deco "
.Ls_before: .asciz " before="
.Ls_after: .asciz " after="
.Ls_tip: .asciz " tip="
.Ls_glyph: .asciz "glyph "
.Ls_kind: .asciz " kind="
.Ls_shape: .asciz " shape="
.Ls_click: .asciz "click "
.Ls_test_tip: .asciz "Test glyph"
.Ls_tape_sp: .asciz "tape edits="
.Ls_base: .asciz " base="
.Ls_version: .asciz " version="
