# notebooks: rendered Markdown and pictures (wider-parity design A4). A markup cell that is not
# being edited shows its Markdown rendered (markdown.s); a `rich` output shows its rich document
# (md_from_body) and a `picture` output its 12a picture (pic_new/pic_draw), scaled down to the
# column's width. Links in either open through md_open_link.
.include "rhun.inc"

.equ ID_NB_MD, 0x200000         # + slot * 4096: a rendered block's links (the slot: blocks drawn)
.equ NBM_PIC_H, 240             # a picture's logical height when its output names none
.equ NBM_PIC_MAXPX, 1 << 24     # a wider picture is rendered whole before it is scaled down

.bss
.p2align 3
nbm_slot: .long 0               # rendered blocks drawn this frame
nbm_pad: .long 0
nbm_sb: .zero SB_SIZE

.text

# nb_md_frame(): a new frame's blocks get their link ids from the first slot again
FN nb_md_frame
    mov dword ptr [rip + nbm_slot], 0
    ret

# nb_mark_edit(nb): NBC_edit on the cell in edit mode (its source shows), off on the others
FN nb_mark_edit
    mov rdx, [rdi + NB_sel]
    mov r8d, [rdi + NB_editing]
    xor ecx, ecx
1:  cmp rcx, [rdi + NB_cells + VEC_len]
    jae 9f
    mov rax, [rdi + NB_cells + VEC_ptr]
    mov rax, [rax + rcx*8]
    xor r9d, r9d
    cmp rcx, rdx
    jne 2f
    mov r9d, r8d
2:  mov [rax + NBC_edit], r9d
    inc rcx
    jmp 1b
9:  ret

# nb_cell_md(cl) -> rax its rendered Markdown, or 0: a code cell, or a markup cell with only
#   blanks. Made again when its text changed; relative links name the notebook's folder.
FN nb_cell_md
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + NBC_kind], NBCK_MARKUP
    jne 8f
    mov r12, [rbx + NBC_doc]
    mov rax, [r12 + DOC_version]
    inc rax
    cmp rax, [rbx + NBC_mdver]
    je 7f
    mov [rbx + NBC_mdver], rax
    mov rdi, [rbx + NBC_md]
    mov qword ptr [rbx + NBC_md], 0
    test rdi, rdi
    jz 1f
    call md_free
1:  mov rdi, r12
    call doc_len
    mov r13, rax
    test r13, r13
    jz 7f
    mov rdi, r13
    call mem_alloc
    mov r14, rax
    mov rdi, r12
    xor esi, esi
    mov rdx, r13
    mov rcx, r14
    call doc_copy
    # only blanks: the source shows (an empty line to type in)
    xor ecx, ecx
2:  cmp rcx, r13
    jae 6f
    cmp byte ptr [r14 + rcx], ' '
    ja 3f
    inc rcx
    jmp 2b
3:  mov rdi, r14
    mov rsi, r13
    call md_new
    mov [rbx + NBC_md], rax
    mov rdi, rax
    call nbm_base
6:  mov rdi, r14
    call mem_free
7:  mov rax, [rbx + NBC_md]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nbm_base(md): relative links and images name the active notebook's folder
nbm_base:
    PROLOGUE
    mov rbx, rdi
    call nb_active
    test rax, rax
    jz 9f
    mov rax, [rax + NB_host]
    mov r12, [rax + DOC_path]
    test r12, r12
    jz 9f
    mov rdi, r12
    call strlen
    # up to the last separator
1:  test rax, rax
    jz 9f
    dec rax
    cmp byte ptr [r12 + rax], '/'
    je 2f
    cmp byte ptr [r12 + rax], 92
    jne 1b
2:  mov rdx, rax
    test rdx, rdx
    jnz 3f
    inc rdx                     # the root folder keeps its /
3:  mov rdi, rbx
    mov rsi, r12
    call md_set_base
9:  EPILOGUE

# nb_cell_rendered(cl) -> eax 1 when it shows rendered Markdown: a markup cell with text, not in
#   edit mode
FN nb_cell_rendered
    push rbx
    mov rbx, rdi
    xor eax, eax
    cmp dword ptr [rbx + NBC_edit], 0
    jne 9f
    call nb_cell_md
    test rax, rax
    setnz al
    movzx eax, al
9:  pop rbx
    ret

# nb_md_draw(md, x, y, w, h) -> eax 1 when a link was clicked: the document, h px tall at (x, y),
#   drawn where the canvas's clip lets it be; the link clicked is followed (or named in a toast
#   when rhun cannot follow it)
FN nb_md_draw
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov eax, edx
    add eax, r8d
    mov [rsp + 12], eax         # bottom
    mov eax, [rsp + 4]
    cmp eax, [rip + g_cv + CV_cy0]
    jge 1f
    mov eax, [rip + g_cv + CV_cy0]
1:  mov [rsp + 16], eax         # visible top
    mov ecx, [rsp + 12]
    cmp ecx, [rip + g_cv + CV_cy1]
    jle 2f
    mov ecx, [rip + g_cv + CV_cy1]
2:  sub ecx, eax
    jle 8f
    mov [rsp + 20], ecx         # visible height
    mov eax, [rip + nbm_slot]
    inc dword ptr [rip + nbm_slot]
    and eax, 255
    shl eax, 12
    add eax, ID_NB_MD
    push rax
    push rax
    mov rdi, rbx
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 16]
    mov ecx, [rsp + 16 + 8]
    mov r8d, [rsp + 16 + 20]
    mov r9d, [rsp + 16 + 16]
    sub r9d, [rsp + 16 + 4]     # the part above the view
    call md_draw
    add rsp, 16
    test eax, eax
    js 8f
    mov r12d, eax
    mov rdi, rbx
    mov esi, r12d
    call md_open_link
    test eax, eax
    jnz 7f
    # a link rhun cannot follow (an anchor, another scheme, a file that is not there)
    mov rdi, rbx
    mov esi, r12d
    call md_link
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + nbm_sb]
    call sb_clear
    lea rdi, [rip + nbm_sb]
    lea rsi, [rip + .Lno_link]
    call sb_push_cstr
    lea rdi, [rip + nbm_sb]
    mov rsi, r13
    mov rdx, r14
    cmp rdx, 200
    jbe 3f
    mov edx, 200
3:  call sb_push
    lea rdi, [rip + nbm_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + nbm_sb + SB_ptr]
    call app_toast
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- pictures ----------------

# nb_pic_size(item, w) -> eax px wide, edx px tall: a picture's size in a column w px wide, its
#   logical W H (the column, 240 when the output names none) scaled down to the column
FN nb_pic_size
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    cmp r12d, 1
    jge 1f
    mov r12d, 1
1:  mov edi, [rbx + NBI_w]
    test edi, edi
    jz 2f
    call sc
    mov r13d, eax
    jmp 3f
2:  mov r13d, r12d
3:  mov edi, [rbx + NBI_h]
    test edi, edi
    jnz 4f
    mov edi, NBM_PIC_H
4:  call sc
    mov r14d, eax
    cmp r13d, r12d
    jbe 5f
    mov eax, r14d               # wider than the column: down to its width
    imul rax, r12
    xor edx, edx
    div r13
    mov r14d, eax
    mov r13d, r12d
5:  cmp r13d, 1
    jge 51f
    mov r13d, 1
51: cmp r14d, 1
    jge 52f
    mov r14d, 1
52: cmp r14d, 8192
    jbe 53f
    mov r14d, 8192
53: mov eax, r13d
    mov edx, r14d
    EPILOGUE

# nb_pic_draw(ou, item, x, y, w): the output's picture at (x, y) in a column w px wide; a picture
#   wider than the column is rendered whole and scaled down (kept in NBO_img until the width, the
#   theme, the scale, the faces or an image change)
FN nb_pic_draw
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov [rsp + 8], r8d
    mov r13, [rbx + NBO_pic]
    test r13, r13
    jz 9f
    call nb_active              # image shapes name the notebook's extension's handles
    test rax, rax
    jz 1f
    mov rax, [rax + NB_ext]
    mov [r13 + VW_ext], rax
1:  mov rdi, r12
    mov esi, [rsp + 8]
    call nb_pic_size
    mov [rsp + 12], eax         # w shown
    mov [rsp + 16], edx         # h shown
    # its size unscaled
    mov edi, [r12 + NBI_w]
    test edi, edi
    jz 2f
    call sc
    jmp 3f
2:  mov eax, [rsp + 8]
3:  mov [rsp + 20], eax
    mov edi, [r12 + NBI_h]
    test edi, edi
    jnz 31f
    mov edi, NBM_PIC_H
31: call sc
    mov [rsp + 24], eax         # h unscaled
    mov eax, [rsp + 20]
    cmp eax, [rsp + 12]
    jbe 6f                      # it fits: drawn as it is
    mov eax, [rsp + 20]
    mov ecx, [rsp + 24]
    imul rax, rcx
    cmp rax, NBM_PIC_MAXPX
    ja 6f                       # too big to render whole: its left part, at the column's size
    # what the scaled pixels are for
    mov eax, [rsp + 8]
    mov rcx, [rip + g_theme_cur]
    imul rcx, rcx, 1000003
    add rax, rcx
    mov ecx, [rip + g_face_gen]
    imul rcx, rcx, 7919
    add rax, rcx
    mov ecx, [rip + vimg_gen]
    shl rcx, 40
    add rax, rcx
    mov ecx, [rip + g_s]
    shl rcx, 20
    xor rax, rcx
    or rax, 1
    mov [rsp + 32], rax
    cmp qword ptr [rbx + NBO_img], 0
    je 4f
    cmp [rbx + NBO_pkey], rax
    je 5f
4:  mov edi, [rsp]              # rendered whole where nothing shows
    mov esi, [rsp + 4]
    xor edx, edx
    xor ecx, ecx
    call gfx_clip_push
    mov rdi, r13
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 20]
    mov r8d, [rsp + 24]
    call pic_draw
    call gfx_clip_pop
    mov rdi, [r13 + VW_px]
    test rdi, rdi
    jz 9f
    mov rdi, [rbx + NBO_img]
    mov qword ptr [rbx + NBO_img], 0
    call mem_free
    mov rdi, [r13 + VW_px]
    mov esi, [r13 + VW_pw]
    mov edx, [r13 + VW_ph]
    mov ecx, [rsp + 12]
    mov r8d, [rsp + 16]
    call nb_scale
    test rax, rax
    jz 9f
    mov [rbx + NBO_img], rax
    mov eax, [rsp + 12]
    mov [rbx + NBO_iw], eax
    mov eax, [rsp + 16]
    mov [rbx + NBO_ih], eax
    mov rax, [rsp + 32]
    mov [rbx + NBO_pkey], rax
5:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov rdx, [rbx + NBO_img]
    mov ecx, [rbx + NBO_iw]
    mov r8d, [rbx + NBO_ih]
    call gfx_blit
    jmp 9f
6:  mov eax, [rsp + 12]
    mov [rbx + NBO_iw], eax
    mov eax, [rsp + 16]
    mov [rbx + NBO_ih], eax
    mov rdi, r13
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 12]
    mov r8d, [rsp + 16]
    call pic_draw
9:  EPILOGUE

# ---------------- for the tests ----------------

# nb_dump_md(sb, i): cell i's rendered Markdown: "md cell=I rendered=R at=X,Y" and md_dump's
#   lines, or "md=none"
FN nb_dump_md
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call nb_active
    test rax, rax
    jz 8f
    push rax
    push rax
    mov rdi, rax
    call nb_mark_edit
    pop rax
    pop rax
    cmp r12, [rax + NB_cells + VEC_len]
    jae 8f
    mov rcx, [rax + NB_cells + VEC_ptr]
    mov r13, [rcx + r12*8]
    mov rdi, r13
    call nb_cell_md
    test rax, rax
    jz 8f
    mov r14, rax
    mov rdi, rbx
    lea rsi, [rip + .Ld_md]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_rendered]
    call sb_push_cstr
    mov rdi, r13
    call nb_cell_rendered
    lea esi, [rax + '0']
    mov rdi, rbx
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NBC_mdx]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r13 + NBC_mdy]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    mov rdi, r14
    mov rsi, rbx
    call md_dump
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
    EPILOGUE

.section .rodata
.Lno_link: .asciz "rhun cannot open this link: "
.Ld_md: .asciz "md cell="
.Ld_rendered: .asciz " rendered="
.Ld_at: .asciz " at="
.Ld_none: .asciz "md=none\n"
