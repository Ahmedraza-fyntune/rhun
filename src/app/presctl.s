# editor presentation: headless control commands (pres_ctl, in control.s's ctl_tables). Lines and columns are 1-based, columns in bytes, as in the protocol.
#   print-viewport              "view mode=lines|wrap top=L off=N rows=R content=PX"
#   print-xy LINE COL           "X Y": the caret's x at that position and its row's middle
#   print-hit X Y               "text L C" | "left-lane L" | "digits L" | "fold-lane L" | "git L" | "none"
#   print-present deco|types|glyphs|tape|folds|ranges|tokens
#   print-classes LINE          "classes L C1-C2=K ...": the classes the line is drawn in; "fx C1-C2=F"
#   glyph-test                  a test kind in the left lane (clicks toggle a circle; logged):
#                               "glyph-kind N", its kind number
#   glyph LINE SHAPE            the test kind's glyph on a line (0 removes)
.include "rhun.inc"

.bss
.p2align 3
pc_cls: .zero SB_SIZE           # print-classes: the line's syntax classes
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
    call rows_mode
    test eax, eax
    jz 1f
    lea rdi, [rip + .Ls_view_rows]
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
    call rows_mode
    test eax, eax
    jz 2f
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
    mov rdi, rbx
    call fold_scroll_rows
    lea rdi, [rax + 1]
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
    cmp dword ptr [rip + cfg_word_wrap], 0
    jne 5f
    call rows_mode
    test eax, eax
    jz 1f
    # y in rows (folds, code lens rows): wrap_xy's row, x as for lines
    mov rdi, rbx
    mov rsi, r15
    call wrap_xy
    add edx, [rip + g_ed_y]
    mov ecx, [rip + g_lh]
    shr ecx, 1
    add edx, ecx
    movsxd r12, edx
    jmp 2f
1:  # y: rows from the top line (lines mode)
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
2:  # x: by the caret's rule over the line's inlays (vtext.s)
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [r14 - 1]
    call vt_line_x
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
5:  # wrapped lines
    mov rdi, rbx
    mov rsi, r15
    call wrap_xy
    add eax, [rip + g_ed_tx]
    add edx, [rip + g_ed_y]
    mov ecx, [rip + g_lh]
    shr ecx, 1
    add edx, ecx
    mov r12d, edx
    mov edi, eax
    call out_u64
    mov edi, ' '
    call out_byte
    mov edi, r12d
    call out_u64
    mov edi, 10
    call out_byte
    xor eax, eax
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
    cmp qword ptr [rip + g_vt_hit], 0
    je 3f
    lea rdi, [rip + .Ls_inlay]  # "inlay KIND L C": an inlay at that gap
    call out_cstr
    call vt_hit_kind
    lea rcx, [rip + kind_words]
    mov rdi, [rcx + rax*8]
    call out_cstr
    lea rdi, [rip + .Ls_space]
3:  call out_cstr
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

# ---------------- print-classes ----------------

# print-classes LINE: "classes L C1-C2=K ..." the classes the line is drawn in (syntax and semantic
# tokens; runs, 1-based byte columns), then "fx C1-C2=F" for each token effect
c_print_classes:
    call take_args
    PROLOGUE 16
    call arg_int
    mov r12, rax
    call frame
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    test r12, r12
    jz 9f
    dec r12
    cmp r12, [rbx + DOC_nlines]
    jae 9f
    mov rdi, rbx
    mov rsi, r12
    call syntax_prepare
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov r14, rax
    mov r15, rdx
    lea rdi, [rip + pc_cls]
    mov qword ptr [rdi + SB_len], 0
    lea rsi, [r15 + 16]
    call sb_reserve
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rcx, r15
    mov r8, [rip + pc_cls + SB_ptr]
    call syntax_line
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rcx, [rip + pc_cls + SB_ptr]
    mov r8, r15
    call semtok_line
    mov r13, rax
    lea rdi, [rip + .Ls_classes]
    call out_cstr
    lea rdi, [r12 + 1]
    call out_u64
    xor r14d, r14d              # run start
1:  cmp r14, r15
    jae 3f
    movzx eax, byte ptr [r13 + r14]
    lea rcx, [r14 + 1]
2:  cmp rcx, r15
    jae 21f
    cmp [r13 + rcx], al
    jne 21f
    inc rcx
    jmp 2b
21: mov [rsp], rcx
    mov [rsp + 8], rax
    mov edi, ' '
    call out_byte
    lea rdi, [r14 + 1]
    call out_u64
    mov edi, '-'
    call out_byte
    mov rdi, [rsp]
    call out_u64
    mov edi, '='
    call out_byte
    mov rdi, [rsp + 8]
    call out_u64
    mov r14, [rsp]
    jmp 1b
3:  mov edi, 10
    call out_byte
    xor r14d, r14d
4:  cmp r14, [rip + g_tkfx_n]
    jae 9f
    imul r13, r14, 24
    lea rax, [rip + g_tkfx]
    add r13, rax
    inc r14
    lea rdi, [rip + .Ls_fx]
    call out_cstr
    mov rdi, [r13]
    inc rdi
    call out_u64
    mov edi, '-'
    call out_byte
    mov rdi, [r13 + 8]
    call out_u64
    mov edi, '='
    call out_byte
    mov edi, [r13 + 16]
    call out_u64
    mov edi, 10
    call out_byte
    jmp 4b
9:  xor eax, eax
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
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_folds]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_folds
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_ranges]
    call str_eq_cstr
    test eax, eax
    jnz .Lpp_ranges
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_tokens]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov rdi, rbx                # semantic tokens (semtok.s)
    mov rsi, [rip + outp]
    call semtok_dump
    jmp 9f
1:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_hints]
    call str_eq_cstr
    test eax, eax
    jz 2f
    mov rdi, rbx                # inlay hints (inlay.s)
    mov rsi, [rip + outp]
    call inlay_dump
    jmp 9f
2:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_lenses]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov rdi, rbx                # code lens (lens.s)
    mov rsi, [rip + outp]
    call lens_dump
    jmp 9f
3:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_highlights]
    call str_eq_cstr
    test eax, eax
    jz 4f
    mov rdi, [rip + outp]       # the caret's highlights (hicolor.s)
    call hl_dump
    jmp 9f
4:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_colors]
    call str_eq_cstr
    test eax, eax
    jz 5f
    mov rdi, rbx                # colors (hicolor.s)
    mov rsi, [rip + outp]
    call color_dump
    jmp 9f
5:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_ghost]
    call str_eq_cstr
    test eax, eax
    jz 9f
    mov rdi, [rip + outp]       # inline completion (ghost.s)
    call ghost_dump
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
2:  cmp r12, [r14 + PRS_deco + VEC_len]
    jae 3f
    imul rax, r12, DR_SIZE
    add rax, [r14 + PRS_deco + VEC_ptr]
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
    add r13, [r14 + PRS_deco + VEC_ptr]
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
    add r15, [r14 + PRS_dpool + SB_ptr]
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
5:  cmp r12, [r14 + PRS_glyphs + VEC_len]
    jae 6f
    imul r13, r12, GLE_SIZE
    add r13, [r14 + PRS_glyphs + VEC_ptr]
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
    mov rdi, [r14 + PRS_tn]
7:  call out_u64
    lea rdi, [rip + .Ls_base]
    call out_cstr
    xor edi, edi
    test r14, r14
    jz 71f
    mov rdi, [r14 + PRS_tbase]
71: call out_u64
    lea rdi, [rip + .Ls_version]
    call out_cstr
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, 10
    call out_byte
    jmp 9b

# "fold H-E" for each fold (1-based header and last hidden line), then "hidden N"
.Lpp_folds:
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 9f
    xor r12d, r12d
1:  cmp r12, [r14 + PRS_folds + VEC_len]
    jae 2f
    imul r13, r12, FLD_SIZE
    add r13, [r14 + PRS_folds + VEC_ptr]
    inc r12
    lea rdi, [rip + .Ls_fold_sp]
    call out_cstr
    mov rdi, rbx
    mov rsi, [r13 + FLD_a]
    call doc_line_of
    lea rdi, [rax + 1]
    call out_u64
    mov edi, '-'
    call out_byte
    mov rdi, rbx
    mov rsi, [r13 + FLD_b]
    call doc_line_of
    lea rdi, [rax + 1]
    call out_u64
    mov rdi, [r13 + FLD_text]
    call text_out
    mov edi, 10
    call out_byte
    jmp 1b
2:  lea rdi, [rip + .Ls_hidden]
    call out_cstr
    mov rdi, rbx
    mov rsi, [rbx + DOC_nlines]
    call fold_hidden_before
    mov rdi, rax
    call out_u64
    mov edi, 10
    call out_byte
9:  xor eax, eax
    EPILOGUE

# "ranges indentation", or "ranges EXT" and "range H-E kind=K[ text=T]" for a provider's ranges
.Lpp_ranges:
    lea rdi, [rip + .Ls_ranges_sp]
    call out_cstr
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 1f
    mov rax, [r14 + PRS_frext]
    test rax, rax
    jnz 2f
1:  lea rdi, [rip + .Ls_indentation]
    call out_cstr
    jmp 9b
2:  mov rdi, [rax + EXT_name]
    call out_cstr
    mov edi, 10
    call out_byte
    xor r12d, r12d
3:  cmp r12, [r14 + PRS_fr + VEC_len]
    jae 9b
    imul r13, r12, FRG_SIZE
    add r13, [r14 + PRS_fr + VEC_ptr]
    inc r12
    lea rdi, [rip + .Ls_range_sp]
    call out_cstr
    mov rdi, rbx
    mov rsi, [r13 + FRG_a]
    call doc_line_of
    lea rdi, [rax + 1]
    call out_u64
    mov edi, '-'
    call out_byte
    mov rdi, rbx
    mov rsi, [r13 + FRG_b]
    call doc_line_of
    lea rdi, [rax + 1]
    call out_u64
    lea rdi, [rip + .Ls_kind]
    call out_cstr
    mov edi, [r13 + FRG_kind]
    call out_u64
    mov rdi, [r13 + FRG_text]
    call text_out
    mov edi, 10
    call out_byte
    jmp 3b

# text_out(cstr or 0): " text=T"
text_out:
    test rdi, rdi
    jz 9f
    push rdi
    lea rdi, [rip + .Ls_text_eq]
    call out_cstr
    pop rdi
    jmp out_cstr
9:  ret

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
9:  lea rdi, [rip + .Ls_glyph_kind]
    call out_cstr
    mov edi, [rip + test_kind]
    call out_u64
    mov edi, 10
    call out_byte
    xor eax, eax
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
    .quad .Lc_probe_plant, c_probe_plant, .Lc_print_classes, c_print_classes
    .quad 0, 0
lane_words: .quad 0, .Ls_left, .Ls_digits, .Ls_fold, .Ls_git
kind_words: .quad .Lk_ghost, .Lk_fold, .Lk_hint, .Lk_deco, .Lk_swatch, .Lk_lens
.Lc_print_view: .asciz "print-viewport"
.Lc_print_xy: .asciz "print-xy"
.Lc_print_hit: .asciz "print-hit"
.Lc_print_present: .asciz "print-present"
.Lc_glyph_test: .asciz "glyph-test"
.Lc_glyph: .asciz "glyph"
.Ls_glyph_kind: .asciz "glyph-kind "
.Lc_probe_plant: .asciz "probe-plant"
.Lc_print_classes: .asciz "print-classes"
.Ls_classes: .asciz "classes "
.Ls_fx: .asciz "fx "
.Ls_tokens: .asciz "tokens"
.Ls_hints: .asciz "hints"
.Ls_lenses: .asciz "lenses"
.Ls_highlights: .asciz "highlights"
.Ls_colors: .asciz "colors"
.Ls_ghost: .asciz "ghost"
.Ls_stale: .asciz "stale"
.Ls_view_lines: .asciz "view mode=lines top="
.Ls_view_wrap: .asciz "view mode=wrap top="
.Ls_view_rows: .asciz "view mode=rows top="
.Ls_off: .asciz " off="
.Ls_rows: .asciz " rows="
.Ls_content: .asciz " content="
.Ls_none: .asciz "none\n"
.Ls_text: .asciz "text "
.Ls_inlay: .asciz "inlay "
.Ls_space: .asciz " "
.Lk_ghost: .asciz "ghost"
.Lk_fold: .asciz "fold"
.Lk_hint: .asciz "hint"
.Lk_deco: .asciz "deco"
.Lk_lens: .asciz "lens"
.Lk_swatch: .asciz "swatch"
.Ls_left: .asciz "left-lane "
.Ls_digits: .asciz "digits "
.Ls_fold: .asciz "fold-lane "
.Ls_git: .asciz "git "
.Ls_types: .asciz "types"
.Ls_deco: .asciz "deco"
.Ls_glyphs: .asciz "glyphs"
.Ls_tape: .asciz "tape"
.Ls_folds: .asciz "folds"
.Ls_ranges: .asciz "ranges"
.Ls_ranges_sp: .asciz "ranges "
.Ls_range_sp: .asciz "range "
.Ls_indentation: .asciz "indentation\n"
.Ls_text_eq: .asciz " text="
.Ls_fold_sp: .asciz "fold "
.Ls_hidden: .asciz "hidden "
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
