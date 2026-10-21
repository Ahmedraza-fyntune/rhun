# notebooks: drawing a cell's outputs (nbdoc.s keeps them). Text in the code face, wrapped at the
# column width, with SGR colors for ansi items (0/1/2/3/4/7/22-24/27/30-37/39/40-47/49/90-97/
# 100-107 and 38/48 with ;5 and ;2; every other escape is left out); the first NB_TEXT_LINES lines,
# then "N more lines · Open in Tab". PNG, JPEG and GIF images decoded once and scaled to the
# width: one image pixel is one logical pixel unless the output says otherwise, never wider than
# the column. Errors and stderr get a tinted bar.
.include "rhun.inc"

.equ ID_NB_MORE, 0x7d00         # + visible output: its "Open in Tab"
.equ TA_BOLD, 1
.equ TA_DIM, 2
.equ TA_ITALIC, 4
.equ TA_UNDER, 8
.equ TA_INVERSE, 16

.bss
.p2align 3
tx_p: .quad 0                   # the text being walked: the next byte and the end
tx_e: .quad 0
tx_rs: .quad 0                  # the run of bytes not drawn yet (one style, one row), 0 none
tx_cols: .long 0                # columns of a row
tx_col: .long 0                 # the column the next character goes to
tx_rcol: .long 0                # the run's first column
tx_row: .long 0                 # rows finished
tx_lines: .long 0               # lines finished
tx_draw: .long 0                # 1 draws, 0 measures
tx_ansi: .long 0                # escapes are read (ansi items)
tx_x0: .long 0                  # where row 0 column 0 is drawn
tx_y0: .long 0
tx_fg: .long 0                  # SGR state: colors as cells hold them (0, TC_IDX | i, TC_RGB | rgb)
tx_bg: .long 0
tx_attr: .long 0                # TA_*
tx_deffg: .long 0               # the text color for fg 0
tx_np: .long 0                  # SGR parameters
tx_params: .zero 4 * 16
.p2align 3
.globl g_nb_more_ou
g_nb_more_ou: .quad 0           # an output whose "Open in Tab" was clicked this frame
tmp: .zero SB_SIZE

.text

# ---------------- text ----------------

# tx_walk(ptr, len, cols, draw, ansi) -> eax visual rows, edx 1 when text is left after the first
#   NB_TEXT_LINES rows; draws from (tx_x0, tx_y0) when draw is 1
FN nb_tx_walk
    PROLOGUE
    mov [rip + tx_p], rdi
    add rdi, rsi
    mov [rip + tx_e], rdi
    cmp edx, 1
    jge 1f
    mov edx, 1
1:  mov [rip + tx_cols], edx
    mov [rip + tx_draw], ecx
    mov [rip + tx_ansi], r8d
    xor eax, eax
    mov [rip + tx_rs], rax
    mov [rip + tx_col], eax
    mov [rip + tx_row], eax
    mov [rip + tx_lines], eax
    mov [rip + tx_fg], eax
    mov [rip + tx_bg], eax
    mov [rip + tx_attr], eax
    xor r15d, r15d              # stopped at the line cap
.Ltw_loop:
    mov rbx, [rip + tx_p]
    cmp rbx, [rip + tx_e]
    jae .Ltw_end
    movzx eax, byte ptr [rbx]
    cmp eax, 0x1b
    jne 1f
    cmp dword ptr [rip + tx_ansi], 0
    je 1f
    call tx_flush
    call tx_escape
    jmp .Ltw_loop
1:  cmp eax, 10
    jne 2f
    call tx_flush
    inc qword ptr [rip + tx_p]
    inc dword ptr [rip + tx_row]
    mov dword ptr [rip + tx_col], 0
    inc dword ptr [rip + tx_lines]
    jmp .Ltw_rowcap
2:  cmp eax, 9
    jne 3f
    call tx_flush
    inc qword ptr [rip + tx_p]
    mov eax, [rip + tx_col]
    add eax, 8
    and eax, -8
    cmp eax, [rip + tx_cols]
    jbe 21f
    inc dword ptr [rip + tx_row]
    mov dword ptr [rip + tx_col], 0
    jmp .Ltw_rowcap
21: mov [rip + tx_col], eax
    jmp .Ltw_loop
3:  cmp eax, 32
    jb 31f
    cmp eax, 127
    jne 4f
31: call tx_flush
    inc qword ptr [rip + tx_p]
    jmp .Ltw_loop
4:  mov rdi, rbx
    mov rsi, [rip + tx_e]
    sub rsi, rbx
    call utf8_decode
    mov r12d, edx               # bytes
    mov edi, eax
    call cp_width
    mov r13d, eax               # columns
    mov eax, [rip + tx_col]
    add eax, r13d
    cmp eax, [rip + tx_cols]
    jbe 5f
    cmp dword ptr [rip + tx_col], 0
    je 5f
    call tx_flush
    inc dword ptr [rip + tx_row]
    mov dword ptr [rip + tx_col], 0
    cmp dword ptr [rip + tx_row], NB_TEXT_LINES
    jae .Ltw_capped
5:  cmp qword ptr [rip + tx_rs], 0
    jne 6f
    mov rax, [rip + tx_p]
    mov [rip + tx_rs], rax
    mov eax, [rip + tx_col]
    mov [rip + tx_rcol], eax
6:  add [rip + tx_col], r13d
    add [rip + tx_p], r12
    jmp .Ltw_loop
.Ltw_rowcap:
    cmp dword ptr [rip + tx_row], NB_TEXT_LINES
    jb .Ltw_loop
.Ltw_capped:
    mov rax, [rip + tx_p]
    cmp rax, [rip + tx_e]
    jae .Ltw_end
    mov r15d, 1                 # text is left: a row says how much
.Ltw_end:
    call tx_flush
    mov eax, [rip + tx_row]
    cmp dword ptr [rip + tx_col], 0
    je 7f
    inc eax
7:  mov edx, r15d
    EPILOGUE

# tx_flush(): the run drawn (draw mode), and forgotten
tx_flush:
    PROLOGUE 16
    mov r12, [rip + tx_rs]
    test r12, r12
    jz 9f
    mov qword ptr [rip + tx_rs], 0
    cmp dword ptr [rip + tx_draw], 0
    je 9f
    mov r13, [rip + tx_p]
    sub r13, r12                # bytes
    jle 9f
    # the row's y; rows outside the clip are not drawn
    mov eax, [rip + tx_row]
    imul eax, [rip + g_lh]
    add eax, [rip + tx_y0]
    mov r14d, eax
    mov ecx, eax
    add ecx, [rip + g_lh]
    cmp ecx, [rip + g_cv + CV_cy0]
    jle 9f
    cmp eax, [rip + g_cv + CV_cy1]
    jge 9f
    mov eax, [rip + tx_rcol]
    imul eax, [rip + g_cw]
    add eax, [rip + tx_x0]
    mov r15d, eax               # x
    # colors
    mov edi, [rip + tx_fg]
    mov esi, [rip + tx_deffg]
    call nb_color
    mov ebx, eax
    mov edi, [rip + tx_bg]
    xor esi, esi
    call nb_color
    mov [rsp], eax              # background, 0 none
    test dword ptr [rip + tx_attr], TA_INVERSE
    jz 1f
    mov ecx, [rsp]
    test ecx, ecx
    jnz 11f
    COLOR ecx, T_BG
11: mov [rsp], ebx
    mov ebx, ecx
1:  test dword ptr [rip + tx_attr], TA_DIM
    jz 2f
    mov edi, ebx
    COLOR esi, T_BG
    mov edx, 100
    call color_mix
    mov ebx, eax
2:  mov ecx, [rsp]
    test ecx, ecx
    jz 3f
    # the background under the run's columns
    mov eax, [rip + tx_col]
    sub eax, [rip + tx_rcol]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, r15d
    mov esi, r14d
    mov r8d, ecx
    mov ecx, [rip + g_lh]
    call gfx_fill
3:  lea rdi, [rip + g_face_code]
    mov esi, r15d
    mov edx, r14d
    add edx, [rip + g_base]
    mov rcx, r12
    mov r8, r13
    mov r9d, ebx
    call text_draw
    test dword ptr [rip + tx_attr], TA_BOLD
    jz 4f
    # bold: once more a physical pixel to the right, as the terminal does
    lea rdi, [rip + g_face_code]
    lea esi, [r15 + 1]
    mov edx, r14d
    add edx, [rip + g_base]
    mov rcx, r12
    mov r8, r13
    mov r9d, ebx
    call text_draw
4:  test dword ptr [rip + tx_attr], TA_UNDER
    jz 9f
    mov eax, [rip + tx_col]
    sub eax, [rip + tx_rcol]
    imul eax, [rip + g_cw]
    mov edx, eax
    mov edi, r15d
    mov esi, r14d
    add esi, [rip + g_base]
    add esi, [rip + g_mt + 4*MI_2]
    M ecx, MI_1
    mov r8d, ebx
    call gfx_fill
9:  EPILOGUE

# tx_escape(): an escape at tx_p: SGR applied, everything else left out
tx_escape:
    PROLOGUE
    mov rbx, [rip + tx_p]
    mov r12, [rip + tx_e]
    inc rbx                     # ESC
    cmp rbx, r12
    jae 9f
    movzx eax, byte ptr [rbx]
    cmp eax, '['
    je .Lte_csi
    cmp eax, ']'
    je .Lte_osc
    inc rbx                     # ESC and one byte
    jmp 9f
.Lte_osc:
    # to BEL or ESC backslash
    inc rbx
1:  cmp rbx, r12
    jae 9f
    movzx eax, byte ptr [rbx]
    inc rbx
    cmp eax, 7
    je 9f
    cmp eax, 0x1b
    jne 1b
    cmp rbx, r12
    jae 9f
    cmp byte ptr [rbx], '\\'
    jne 1b
    inc rbx
    jmp 9f
.Lte_csi:
    inc rbx
    mov dword ptr [rip + tx_np], 0
    xor r13d, r13d              # the parameter being read
    xor r14d, r14d              # a private marker or an intermediate byte was seen
    xor r15d, r15d              # digits in it
2:  cmp rbx, r12
    jae 9f
    movzx eax, byte ptr [rbx]
    inc rbx
    lea ecx, [rax - '0']
    cmp ecx, 9
    ja 3f
    imul r13d, r13d, 10
    add r13d, ecx
    cmp r13d, 0xffffff
    jbe 21f
    mov r13d, 0xffffff
21: inc r15d
    jmp 2b
3:  cmp eax, ';'
    je 31f
    cmp eax, ':'
    jne 4f
31: call tx_param
    xor r13d, r13d
    xor r15d, r15d
    jmp 2b
4:  cmp eax, 0x40
    jb 41f
    cmp eax, 0x7e
    ja 41f
    # the final byte
    cmp eax, 'm'
    jne 9f
    test r14d, r14d
    jnz 9f
    call tx_param
    call tx_sgr
    jmp 9f
41: mov r14d, 1                 # ? > < = and intermediates: not an SGR rhun applies
    jmp 2b
9:  mov [rip + tx_p], rbx
    EPILOGUE

# tx_param(): r13d onto tx_params (the CSI being read)
tx_param:
    mov eax, [rip + tx_np]
    cmp eax, 16
    jae 1f
    lea rcx, [rip + tx_params]
    mov [rcx + rax*4], r13d
    inc dword ptr [rip + tx_np]
1:  ret

# tx_sgr(): tx_params applied to the SGR state
tx_sgr:
    push rbx
    push r12
    xor ebx, ebx
    lea r12, [rip + tx_params]
.Lts_next:
    cmp ebx, [rip + tx_np]
    jae .Lts_done
    mov eax, [r12 + rbx*4]
    inc ebx
    test eax, eax
    jnz 1f
    mov dword ptr [rip + tx_fg], 0
    mov dword ptr [rip + tx_bg], 0
    mov dword ptr [rip + tx_attr], 0
    jmp .Lts_next
1:  cmp eax, 1
    jne 2f
    or dword ptr [rip + tx_attr], TA_BOLD
    jmp .Lts_next
2:  cmp eax, 2
    jne 3f
    or dword ptr [rip + tx_attr], TA_DIM
    jmp .Lts_next
3:  cmp eax, 3
    jne 4f
    or dword ptr [rip + tx_attr], TA_ITALIC
    jmp .Lts_next
4:  cmp eax, 4
    jne 5f
    or dword ptr [rip + tx_attr], TA_UNDER
    jmp .Lts_next
5:  cmp eax, 7
    jne 6f
    or dword ptr [rip + tx_attr], TA_INVERSE
    jmp .Lts_next
6:  cmp eax, 22
    jne 7f
    and dword ptr [rip + tx_attr], ~(TA_BOLD | TA_DIM)
    jmp .Lts_next
7:  cmp eax, 23
    jne 8f
    and dword ptr [rip + tx_attr], ~TA_ITALIC
    jmp .Lts_next
8:  cmp eax, 24
    jne 9f
    and dword ptr [rip + tx_attr], ~TA_UNDER
    jmp .Lts_next
9:  cmp eax, 27
    jne 10f
    and dword ptr [rip + tx_attr], ~TA_INVERSE
    jmp .Lts_next
10: lea ecx, [rax - 30]
    cmp ecx, 7
    ja 11f
    or ecx, TC_IDX
    mov [rip + tx_fg], ecx
    jmp .Lts_next
11: cmp eax, 39
    jne 12f
    mov dword ptr [rip + tx_fg], 0
    jmp .Lts_next
12: lea ecx, [rax - 40]
    cmp ecx, 7
    ja 13f
    or ecx, TC_IDX
    mov [rip + tx_bg], ecx
    jmp .Lts_next
13: cmp eax, 49
    jne 14f
    mov dword ptr [rip + tx_bg], 0
    jmp .Lts_next
14: lea ecx, [rax - 90]
    cmp ecx, 7
    ja 15f
    add ecx, 8
    or ecx, TC_IDX
    mov [rip + tx_fg], ecx
    jmp .Lts_next
15: lea ecx, [rax - 100]
    cmp ecx, 7
    ja 16f
    add ecx, 8
    or ecx, TC_IDX
    mov [rip + tx_bg], ecx
    jmp .Lts_next
16: cmp eax, 38
    je 17f
    cmp eax, 48
    jne .Lts_next
17: # 38;5;N or 38;2;R;G;B (48 for the background)
    mov r8d, eax
    cmp ebx, [rip + tx_np]
    jae .Lts_done
    mov eax, [r12 + rbx*4]
    inc ebx
    cmp eax, 5
    jne 18f
    cmp ebx, [rip + tx_np]
    jae .Lts_done
    mov ecx, [r12 + rbx*4]
    inc ebx
    and ecx, 255
    or ecx, TC_IDX
    jmp 19f
18: cmp eax, 2
    jne .Lts_next
    lea eax, [rbx + 3]
    cmp eax, [rip + tx_np]
    ja .Lts_done
    mov ecx, [r12 + rbx*4]
    and ecx, 255
    shl ecx, 8
    mov eax, [r12 + rbx*4 + 4]
    and eax, 255
    or ecx, eax
    shl ecx, 8
    mov eax, [r12 + rbx*4 + 8]
    and eax, 255
    or ecx, eax
    or ecx, TC_RGB
    add ebx, 3
19: cmp r8d, 38
    jne 20f
    mov [rip + tx_fg], ecx
    jmp .Lts_next
20: mov [rip + tx_bg], ecx
    jmp .Lts_next
.Lts_done:
    pop r12
    pop rbx
    ret

# nb_color(value, default) -> argb: a color as a terminal cell holds it (the theme's 16 terminal
#   colors, the 256-color cube and grays, or RGB), default for 0
FN nb_color
    mov eax, edi
    shr eax, 24
    jz 8f
    cmp eax, 1
    jne 7f
    movzx edi, dil
    cmp edi, 16
    jae 1f
    lea rax, [rip + g_theme]
    mov eax, [rax + rdi*4 + 4*T_TERM]
    ret
1:  cmp edi, 232
    jae 2f
    sub edi, 16
    mov eax, edi
    xor edx, edx
    mov ecx, 36
    div ecx
    mov r8d, edx
    call cube
    mov r9d, eax
    mov eax, r8d
    xor edx, edx
    mov ecx, 6
    div ecx
    mov r8d, edx
    call cube
    shl r9d, 8
    or r9d, eax
    mov eax, r8d
    call cube
    shl r9d, 8
    or eax, r9d
    or eax, 0xff000000
    ret
2:  sub edi, 232
    imul eax, edi, 10
    add eax, 8
    imul eax, eax, 0x010101
    or eax, 0xff000000
    ret
7:  mov eax, edi
    and eax, 0xffffff
    or eax, 0xff000000
    ret
8:  mov eax, esi
    ret
cube:
    test eax, eax
    jz 1f
    imul eax, eax, 40
    add eax, 55
1:  ret

# nb_strip(ptr, len, sb): the text without escapes (ansi), for a tab of its own
FN nb_strip
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov r13, rdx
1:  cmp rbx, r12
    jae 9f
    movzx eax, byte ptr [rbx]
    cmp eax, 0x1b
    jne 2f
    mov [rip + tx_p], rbx
    mov [rip + tx_e], r12
    call tx_escape
    mov rbx, [rip + tx_p]
    jmp 1b
2:  inc rbx
    mov rdi, r13
    mov esi, eax
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# ---------------- outputs ----------------

# ou_text_cols(w) -> eax columns of a text output w px wide
ou_text_cols:
    mov eax, edi
    sub eax, [rip + g_mt + 4*MI_8]
    sub eax, [rip + g_mt + 4*MI_8]
    cdq
    mov ecx, [rip + g_cw]
    test ecx, ecx
    jz 1f
    idiv ecx
1:  cmp eax, 1
    jge 2f
    mov eax, 1
2:  ret

# nb_ou_height(ou, w) -> eax px of the output drawn w px wide
FN nb_ou_height
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rax, [rbx + NBO_show]
    test rax, rax
    js .Loh_row
    imul rax, rax, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov r13, rax
    mov eax, [r13 + NBI_type]
    cmp eax, NBIT_ANSI
    ja .Loh_image
    mov edi, r12d
    call ou_text_cols
    mov edx, eax
    mov rdi, [r13 + NBI_data + SB_ptr]
    mov rsi, [r13 + NBI_data + SB_len]
    xor ecx, ecx
    xor r8d, r8d
    cmp dword ptr [r13 + NBI_type], NBIT_ANSI
    sete r8b
    call nb_tx_walk
    add eax, edx                # "N more lines"
    imul eax, [rip + g_lh]
    jmp .Loh_pad
.Loh_image:
    mov rdi, rbx
    mov esi, r12d
    call nb_ou_image
    test eax, eax
    jz .Loh_row
    mov eax, [rbx + NBO_ih]
    jmp .Loh_pad
.Loh_row:
    mov eax, [rip + g_lh]
.Loh_pad:
    add eax, [rip + g_mt + 4*MI_4]
    add eax, [rip + g_mt + 4*MI_4]
    EPILOGUE

# nb_ou_image(ou, w) -> eax 1 with NBO_img scaled for a column w px wide, 0 when it cannot be shown
FN nb_ou_image
    PROLOGUE 48
    mov rbx, rdi
    mov r12d, esi
    sub r12d, [rip + g_mt + 4*MI_8]
    sub r12d, [rip + g_mt + 4*MI_8]
    cmp r12d, 1
    jge 1f
    mov r12d, 1
1:  cmp dword ptr [rbx + NBO_ierr], 0
    jne 8f
    cmp qword ptr [rbx + NBO_img], 0
    je 2f
    cmp [rbx + NBO_ikey], r12d
    je 7f
    mov rdi, [rbx + NBO_img]
    call mem_free
    mov qword ptr [rbx + NBO_img], 0
2:  mov rax, [rbx + NBO_show]
    imul rax, rax, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov r13, rax
    mov rdi, [r13 + NBI_data + SB_ptr]
    mov rsi, [r13 + NBI_data + SB_len]
    test rdi, rdi
    jz 6f
    lea rdx, [rip + .Lnopath]
    call image_sniff
    cmp eax, IMF_PNG
    je 3f
    cmp eax, IMF_JPEG
    je 3f
    cmp eax, IMF_GIF
    jne 6f
3:  mov edx, eax
    mov rdi, [r13 + NBI_data + SB_ptr]
    mov rsi, [r13 + NBI_data + SB_len]
    lea rcx, [rsp]
    call image_decode
    test eax, eax
    jnz 6f
    # the size to show: its logical size (the output's, or one image pixel each) at the scale
    mov eax, [r13 + NBI_w]
    mov ecx, [r13 + NBI_h]
    test eax, eax
    jnz 31f
    mov eax, [rsp + IMG_w]
    mov ecx, [rsp + IMG_h]
    jmp 32f
31: test ecx, ecx
    jnz 32f
    mov ecx, [rsp + IMG_h]      # a width alone keeps the image's proportions
    imul ecx, eax
    mov eax, ecx
    xor edx, edx
    div dword ptr [rsp + IMG_w]
    mov ecx, eax
    mov eax, [r13 + NBI_w]
32: mov [rsp + 24], ecx
    mov edi, eax
    call sc
    mov r14d, eax               # w
    mov edi, [rsp + 24]
    call sc
    mov r15d, eax               # h
    cmp r14d, r12d
    jbe 4f
    # wider than the column: down to its width
    mov eax, r15d
    imul eax, r12d
    xor edx, edx
    div r14d
    mov r15d, eax
    mov r14d, r12d
4:  cmp r14d, 1
    jge 41f
    mov r14d, 1
41: cmp r15d, 1
    jge 42f
    mov r15d, 1
42: cmp r15d, 8192
    jbe 43f
    mov r15d, 8192
43: mov rdi, [rsp + IMG_px]
    mov esi, [rsp + IMG_w]
    mov edx, [rsp + IMG_h]
    mov ecx, r14d
    mov r8d, r15d
    call nb_scale
    mov [rbx + NBO_img], rax
    lea rdi, [rsp]
    call image_free
    cmp qword ptr [rbx + NBO_img], 0
    je 6f
    mov [rbx + NBO_iw], r14d
    mov [rbx + NBO_ih], r15d
    mov [rbx + NBO_ikey], r12d
7:  mov eax, 1
    EPILOGUE
6:  mov dword ptr [rbx + NBO_ierr], 1
8:  xor eax, eax
    EPILOGUE

# nb_scale(px, sw, sh, dw, dh) -> dw x dh premultiplied ARGB (owned), or 0: each pixel the average
#   of the source pixels it covers (the nearest one when it covers less than one)
FN nb_scale
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], esi              # sw
    mov [rsp + 4], edx          # sh
    mov [rsp + 8], ecx          # dw
    mov [rsp + 12], r8d         # dh
    mov eax, ecx
    imul rax, r8
    shl rax, 2
    mov rdi, rax
    call mem_alloc_try
    test rax, rax
    jz 9f
    mov [rsp + 16], rax         # dst
    mov r12, rax
    mov dword ptr [rsp + 24], 0 # dy
.Lsc_row:
    mov eax, [rsp + 24]
    cmp eax, [rsp + 12]
    jae .Lsc_done
    imul eax, [rsp + 4]
    xor edx, edx
    div dword ptr [rsp + 12]
    mov [rsp + 28], eax         # y0
    mov eax, [rsp + 24]
    inc eax
    imul eax, [rsp + 4]
    xor edx, edx
    div dword ptr [rsp + 12]
    cmp eax, [rsp + 28]
    ja 1f
    mov eax, [rsp + 28]
    inc eax
1:  mov [rsp + 32], eax         # y1
    mov dword ptr [rsp + 36], 0 # dx
.Lsc_col:
    mov eax, [rsp + 36]
    cmp eax, [rsp + 8]
    jae .Lsc_nextrow
    imul eax, [rsp]
    xor edx, edx
    div dword ptr [rsp + 8]
    mov r13d, eax               # x0
    mov eax, [rsp + 36]
    inc eax
    imul eax, [rsp]
    xor edx, edx
    div dword ptr [rsp + 8]
    cmp eax, r13d
    ja 2f
    lea eax, [r13 + 1]
2:  mov r14d, eax               # x1
    # sums of a, r, g, b and the count
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r15d, r15d
    mov ecx, [rsp + 28]
3:  cmp ecx, [rsp + 32]
    jae 6f
    mov eax, ecx
    imul eax, [rsp]
    add eax, r13d
    lea rsi, [rbx + rax*4]
    mov edi, r13d
4:  cmp edi, r14d
    jae 5f
    mov eax, [rsi]
    add rsi, 4
    mov edx, eax
    shr edx, 24
    add r8d, edx
    mov edx, eax
    shr edx, 16
    and edx, 255
    add r9d, edx
    mov edx, eax
    shr edx, 8
    and edx, 255
    add r10d, edx
    and eax, 255
    add r11d, eax
    inc r15d
    inc edi
    jmp 4b
5:  inc ecx
    jmp 3b
6:  mov ecx, r15d
    mov eax, r8d
    xor edx, edx
    div ecx
    shl eax, 24
    mov edi, eax
    mov eax, r9d
    xor edx, edx
    div ecx
    shl eax, 16
    or edi, eax
    mov eax, r10d
    xor edx, edx
    div ecx
    shl eax, 8
    or edi, eax
    mov eax, r11d
    xor edx, edx
    div ecx
    or edi, eax
    mov [r12], edi
    add r12, 4
    inc dword ptr [rsp + 36]
    jmp .Lsc_col
.Lsc_nextrow:
    inc dword ptr [rsp + 24]
    jmp .Lsc_row
.Lsc_done:
    mov rax, [rsp + 16]
9:  EPILOGUE

# nb_ou_draw(ou, x, y, w, slot): the output in its rect (its height is nb_ou_height's); slot numbers
#   the visible output for its "Open in Tab" button
FN nb_ou_draw
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], esi              # x
    mov [rsp + 4], edx          # y
    mov [rsp + 8], ecx          # w
    mov [rsp + 12], r8d         # slot
    mov rdi, rbx
    mov esi, ecx
    call nb_ou_height
    mov [rsp + 16], eax         # h
    # errors and stderr: a tint and a bar at the left
    mov eax, [rbx + NBO_kind]
    xor r12d, r12d
    cmp eax, NBOK_ERROR
    jne 1f
    COLOR r12d, T_ERROR
1:  cmp eax, NBOK_STDERR
    jne 2f
    COLOR r12d, T_WARNING
2:  test r12d, r12d
    jz 3f
    mov edi, r12d
    mov esi, 24
    call color_alpha
    mov r8d, eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 16]
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    M edx, MI_2
    mov ecx, [rsp + 16]
    mov r8d, r12d
    call gfx_fill
3:  mov rax, [rbx + NBO_show]
    test rax, rax
    js .Lod_none
    imul rax, rax, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov r13, rax
    mov eax, [r13 + NBI_type]
    cmp eax, NBIT_ANSI
    ja .Lod_image
    # text
    mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rip + tx_x0], eax
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_4]
    mov [rip + tx_y0], eax
    COLOR eax, T_FG
    mov [rip + tx_deffg], eax
    mov edi, [rsp + 8]
    call ou_text_cols
    mov edx, eax
    mov rdi, [r13 + NBI_data + SB_ptr]
    mov rsi, [r13 + NBI_data + SB_len]
    mov ecx, 1
    xor r8d, r8d
    cmp dword ptr [r13 + NBI_type], NBIT_ANSI
    sete r8b
    call nb_tx_walk
    mov [rsp + 20], eax         # rows
    test edx, edx
    jz 9f
    # the lines not shown, and the button that opens all of them in a tab
    lea rdi, [rip + tmp]
    call sb_clear
    mov esi, [rip + tx_lines]
    mov rax, [rbx + NBO_lines]
    sub rax, rsi
    jle 31f
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lmore]
    call sb_push_cstr
    jmp 32f
31: lea rdi, [rip + tmp]
    lea rsi, [rip + .Lmore_text]
    call sb_push_cstr
32:
    mov eax, [rsp + 20]
    imul eax, [rip + g_lh]
    add eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_4]
    mov [rsp + 24], eax         # the row's y
    lea rdi, [rip + g_face_code]
    mov esi, [rip + tx_x0]
    mov edx, eax
    add edx, [rip + g_base]
    mov rcx, [rip + tmp + SB_ptr]
    mov r8, [rip + tmp + SB_len]
    COLOR r9d, T_MUTED
    call text_draw
    mov [rsp + 28], eax         # the button's x
    lea rdi, [rip + .Lopen_tab]
    call strlen
    imul eax, [rip + g_cw]
    mov [rsp + 32], eax
    mov edi, [rsp + 12]
    and edi, 255
    add edi, ID_NB_MORE
    mov esi, [rsp + 28]
    mov edx, [rsp + 24]
    mov ecx, [rsp + 32]
    mov r8d, [rip + g_lh]
    call ui_btn
    mov [rsp + 36], eax
    test eax, UB_CLICK
    jz 4f
    mov [rip + g_nb_more_ou], rbx
4:  test dword ptr [rsp + 36], UB_HOVER
    jz 5f
    mov edi, CUR_POINTER
    call ui_set_cursor
5:  lea rdi, [rip + .Lopen_tab]
    call strlen
    mov r8, rax
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 28]
    mov edx, [rsp + 24]
    add edx, [rip + g_base]
    lea rcx, [rip + .Lopen_tab]
    COLOR r9d, T_ACCENT
    call text_draw
    jmp 9f
.Lod_image:
    mov rdi, rbx
    mov esi, [rsp + 8]
    call nb_ou_image
    test eax, eax
    jz .Lod_none
    mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_8]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov rdx, [rbx + NBO_img]
    mov ecx, [rbx + NBO_iw]
    mov r8d, [rbx + NBO_ih]
    call gfx_blit
    jmp 9f
.Lod_none:
    # nothing rhun can draw: the first item's type
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lnot_shown]
    call sb_push_cstr
    cmp qword ptr [rbx + NBO_items + VEC_len], 0
    je 7f
    mov rax, [rbx + NBO_items + VEC_ptr]
    mov rsi, [rax + NBI_name]
    test rsi, rsi
    jnz 6f
    mov ecx, [rax + NBI_type]
    dec ecx
    js 7f
    lea rax, [rip + nb_nit_names]
    mov rsi, [rax + rcx*8]
6:  lea rdi, [rip + tmp]
    call sb_push_cstr
7:  lea rdi, [rip + tmp]
    mov esi, ')'
    call sb_push_byte
    lea rdi, [rip + g_face_code]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 4]
    add edx, [rip + g_mt + 4*MI_4]
    add edx, [rip + g_base]
    mov rcx, [rip + tmp + SB_ptr]
    mov r8, [rip + tmp + SB_len]
    COLOR r9d, T_MUTED
    call text_draw
9:  EPILOGUE

# nb_output_tab(ou): its whole text in a read-only tab of its own
FN nb_output_tab
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + NBO_show]
    test rax, rax
    js 9f
    imul rax, rax, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov r12, rax
    lea rdi, [rip + tmp]
    call sb_clear
    mov rdi, [r12 + NBI_data + SB_ptr]
    mov rsi, [r12 + NBI_data + SB_len]
    lea rdx, [rip + tmp]
    call nb_strip
    call doc_new
    mov r13, rax
    mov rdi, r13
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Lnopath]
    xor edx, edx
1:  call doc_replace_all
    or dword ptr [r13 + DOC_flags], DF_READONLY
    lea rax, [rip + .Loutput_name]
    mov [r13 + DOC_name], rax
    mov qword ptr [r13 + DOC_cur], 0
    mov qword ptr [r13 + DOC_anchor], 0
    mov rdi, r13
    mov esi, TAB_DOC
    call app_add_tab
9:  EPILOGUE

.section .rodata
.Lnopath: .asciz ""
.Lmore: .asciz " more lines \302\267 "
.Lmore_text: .asciz "more \302\267 "
.Lopen_tab: .asciz "Open in Tab"
.Lnot_shown: .asciz "(an output rhun cannot show: "
.Loutput_name: .asciz "Output"
