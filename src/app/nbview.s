# notebooks: the tab (nbdoc.s keeps the model). A toolbar (Run All, Interrupt, Restart, Clear
# Outputs, the kernel button), then the cells one under the other: a code cell's execution count
# ([12], [*] while it runs) left of its source, which is drawn by the editor itself
# (editor_draw_cell), and its outputs under it (nbout.s). The selected cell has a bar at its left;
# in edit mode its frame is accented and it has the keyboard, so g_doc is its document. Only cells
# on screen are drawn; heights are kept per cell until its text, outputs or the width change.
.include "rhun.inc"

.equ ID_NB_TB, 0x7b00           # + toolbar button
.equ ID_NB_SCROLL, 0x7b20
.equ ID_NB_TEXT, 0x7b21         # a failed notebook's Open as Text
.equ ID_NB_RUN, 0x7c00          # + visible cell: its run button (the count column)
.equ TB_RUNALL, 0
.equ TB_INTERRUPT, 1
.equ TB_RESTART, 2
.equ TB_CLEAR, 3
.equ TB_KERNEL, 4

.bss
.p2align 3
nv_boxoff: .long 0              # px from the tab's left to a cell's frame
nv_boxw: .long 0                # the frame's width
nv_prompt: .long 0              # the count column's width
nv_pady: .long 0                # above and below a cell's lines, in its frame
nv_gap: .long 0                 # under a cell
nv_ogap: .long 0                # between a cell's frame and its outputs
nv_top: .long 0                 # above the first cell
nv_sbw: .long 0                 # the scrollbar
nv_scroll32: .long 0            # NB_scroll for ui_scrollbar
nv_slot: .long 0                # cells drawn this frame (ids of their buttons)
nv_oslot: .long 0               # outputs drawn this frame
.p2align 3
nv_text: .quad 0                # a notebook that opens as text after the frame
nv_ex: .long 0                  # the keyboard cell's editor, drawn after the others
nv_ey: .long 0
nv_ew: .long 0
nv_eh: .long 0
.p2align 3
nv_edoc: .quad 0
tmp: .zero SB_SIZE
numbuf: .zero 32

.text

# nb_metrics(w): the cells' geometry for a tab w px wide
nb_metrics:
    M eax, MI_16
    mov ecx, [rip + g_cw]
    imul ecx, ecx, 6
    add ecx, [rip + g_mt + 4*MI_8]
    mov [rip + nv_prompt], ecx
    add eax, ecx
    mov [rip + nv_boxoff], eax
    M ecx, MI_12
    mov [rip + nv_sbw], ecx
    mov edx, edi
    sub edx, eax
    sub edx, ecx
    sub edx, [rip + g_mt + 4*MI_16]
    cmp edx, [rip + g_mt + 4*MI_40]
    jge 1f
    M edx, MI_40
1:  mov [rip + nv_boxw], edx
    M eax, MI_6
    mov [rip + nv_pady], eax
    M eax, MI_12
    mov [rip + nv_gap], eax
    M eax, MI_4
    mov [rip + nv_ogap], eax
    M eax, MI_12
    mov [rip + nv_top], eax
    ret

# cell_box_h(cl) -> eax px of the cell's frame: its lines and the padding
cell_box_h:
    mov rax, [rdi + CL_doc]
    mov rax, [rax + DOC_nlines]
    imul eax, [rip + g_lh]
    add eax, [rip + nv_pady]
    add eax, [rip + nv_pady]
    ret

# nb_cell_height(cl) -> rax px the cell takes, the gap under it included (kept in CL_h)
FN nb_cell_height
    PROLOGUE
    mov rbx, rdi
    # what the height depends on
    mov rax, [rbx + CL_doc]
    mov rax, [rax + DOC_version]
    imul rax, rax, 1000003
    mov rcx, [rbx + CL_outrev]
    shl rcx, 40
    xor rax, rcx
    mov ecx, [rip + nv_boxw]
    xor rax, rcx
    mov ecx, [rip + g_lh]
    shl rcx, 24
    xor rax, rcx
    mov ecx, [rbx + CL_collapsed]
    shl rcx, 62
    xor rax, rcx
    mov ecx, [rip + g_cw]
    shl rcx, 32
    xor rax, rcx
    mov r12, rax
    cmp rax, [rbx + CL_hkey]
    jne 1f
    cmp qword ptr [rbx + CL_h], 0
    jne 8f
1:  mov rdi, rbx
    call cell_box_h
    mov r13d, eax
    cmp qword ptr [rbx + CL_outs + VEC_len], 0
    je 4f
    add r13d, [rip + nv_ogap]
    cmp dword ptr [rbx + CL_collapsed], 0
    je 2f
    add r13d, [rip + g_lh]
    add r13d, [rip + g_mt + 4*MI_8]
    jmp 4f
2:  xor r14d, r14d
3:  cmp r14, [rbx + CL_outs + VEC_len]
    jae 4f
    mov rax, [rbx + CL_outs + VEC_ptr]
    mov rdi, [rax + r14*8]
    inc r14
    mov esi, [rip + nv_boxw]
    call nb_ou_height
    add r13d, eax
    jmp 3b
4:  add r13d, [rip + nv_gap]
    mov [rbx + CL_h], r13
    mov [rbx + CL_hkey], r12
8:  mov rax, [rbx + CL_h]
    EPILOGUE

# nb_cell_top(nb, i) -> rax px from the top of the cells to cell i's top
FN nb_cell_top
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, [rip + nv_top]
    xor r14d, r14d
1:  cmp r14, r12
    jae 9f
    cmp r14, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rdi, [rax + r14*8]
    inc r14
    call nb_cell_height
    add r13, rax
    jmp 1b
9:  mov rax, r13
    EPILOGUE

# ---------------- drawing ----------------

# nb_draw(x, y, w, h): the active notebook tab
FN nb_draw
    PROLOGUE 96
    mov [rsp], edi              # x
    mov [rsp + 4], esi          # y
    mov [rsp + 8], edx          # w
    mov [rsp + 12], ecx         # h
    call nb_active
    mov rbx, rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_BG
    call gfx_fill
    test rbx, rbx
    jz .Lnd_ret
    mov rdi, rbx
    call nb_sync_dirty
    # the toolbar
    M eax, MI_40
    mov [rsp + 16], eax         # its height
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, eax
    call nb_toolbar
    mov eax, [rsp + 4]
    add eax, [rsp + 16]
    mov [rsp + 20], eax         # cells' top
    mov eax, [rsp + 12]
    sub eax, [rsp + 16]
    mov [rsp + 24], eax         # their height
    # the file changed on disk while the notebook had changes
    mov rax, [rbx + NB_host]
    test dword ptr [rax + DOC_flags], DF_DISK_CHANGED
    jz 1f
    M r12d, MI_28
    mov edi, [rsp]
    mov esi, [rsp + 20]
    mov edx, [rsp + 8]
    mov ecx, r12d
    COLOR r8d, T_PANEL
    call gfx_fill
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, [rsp + 20]
    mov ecx, r12d
    lea r8, [rip + .Ldisk]
    COLOR r9d, T_WARNING
    call ui_text_c
    add [rsp + 20], r12d
    sub [rsp + 24], r12d
1:  cmp dword ptr [rsp + 24], 0
    jle .Lnd_ret
    cmp dword ptr [rbx + NB_state], NBS_READY
    je 2f
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 20]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 24]
    call nb_draw_state
    jmp .Lnd_ret
2:  mov edi, [rsp + 8]
    call nb_metrics
    # every cell's height (kept), and all of them
    xor r12d, r12d
    mov r13d, [rip + nv_top]
3:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 4f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rdi, [rax + r12*8]
    inc r12
    call nb_cell_height
    add r13, rax
    jmp 3b
4:  add r13d, [rip + g_mt + 4*MI_48]
    mov [rbx + NB_total], r13
    # the wheel over the cells
    mov edi, [rsp]
    mov esi, [rsp + 20]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 24]
    call ui_in
    test eax, eax
    jz 5f
    call wheel_xy
    movsxd rdx, edx
    test rdx, rdx
    jz 5f
    add [rbx + NB_scroll], rdx
    mov dword ptr [rip + g_dirty], 1
5:  mov rdi, rbx
    mov esi, [rsp + 24]
    call nb_reveal
    # in range
    mov rax, [rbx + NB_total]
    movsxd rcx, dword ptr [rsp + 24]
    sub rax, rcx
    jns 51f
    xor eax, eax
51: cmp [rbx + NB_scroll], rax
    jle 52f
    mov [rbx + NB_scroll], rax
52: cmp qword ptr [rbx + NB_scroll], 0
    jge 53f
    mov qword ptr [rbx + NB_scroll], 0
53: mov eax, [rsp + 20]
    mov [rbx + NB_vy], eax
    mov eax, [rsp + 24]
    mov [rbx + NB_vh], eax
    # a press picks the cell under it first: in its text, edit mode with the keyboard there
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 20]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 24]
    call nb_press
    # the cells on screen
    mov edi, [rsp]
    mov esi, [rsp + 20]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 24]
    call gfx_clip_push
    mov dword ptr [rip + nv_slot], 0
    mov dword ptr [rip + nv_oslot], 0
    mov qword ptr [rip + nv_edoc], 0
    movsxd r14, dword ptr [rsp + 20]
    mov eax, [rip + nv_top]
    add r14, rax
    sub r14, [rbx + NB_scroll]  # y of the cell
    movsxd r15, dword ptr [rsp + 20]
    movsxd rax, dword ptr [rsp + 24]
    add r15, rax                # the view's bottom
    xor r12d, r12d
6:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 7f
    cmp r14, r15
    jge 7f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r13, [rax + r12*8]
    mov rdi, r13
    call nb_cell_height
    mov [rsp + 32], rax
    mov dword ptr [r13 + CL_y], -1
    movsxd rcx, dword ptr [rsp + 20]
    lea rdx, [r14 + rax]
    cmp rdx, rcx
    jle 61f                     # above the view
    mov [r13 + CL_y], r14d
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    mov ecx, [rsp]
    mov r8d, r14d
    call nb_draw_cell
61: add r14, [rsp + 32]
    inc r12
    jmp 6b
7:  # cells below the view are not on screen
    cmp r12, [rbx + NB_cells + VEC_len]
    jae 71f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rax, [rax + r12*8]
    mov dword ptr [rax + CL_y], -1
    inc r12
    jmp 7b
71: # the cell with the keyboard last: the completion list and the caret follow the last editor drawn
    mov rdi, [rip + nv_edoc]
    test rdi, rdi
    jz 72f
    mov esi, [rip + nv_ex]
    mov edx, [rip + nv_ey]
    mov ecx, [rip + nv_ew]
    mov r8d, [rip + nv_eh]
    mov r9d, 1
    call editor_draw_cell
72: call gfx_clip_pop
    # the scrollbar
    mov rax, [rbx + NB_scroll]
    mov ecx, 0x7fffffff
    cmp rax, rcx
    cmova rax, rcx
    mov [rip + nv_scroll32], eax
    mov eax, [rsp + 24]
    push rax
    mov rax, [rbx + NB_total]
    mov ecx, 0x7fffffff
    cmp rax, rcx
    cmova rax, rcx
    push rax
    mov edi, ID_NB_SCROLL
    mov esi, [rsp + 16]
    add esi, [rsp + 16 + 8]
    sub esi, [rip + nv_sbw]
    mov edx, [rsp + 16 + 20]
    mov ecx, [rip + nv_sbw]
    mov r8d, [rsp + 16 + 24]
    lea r9, [rip + nv_scroll32]
    call ui_scrollbar
    add rsp, 16
    cmp dword ptr [rip + g_active], ID_NB_SCROLL
    jne .Lnd_after
    movsxd rax, dword ptr [rip + nv_scroll32]
    mov [rbx + NB_scroll], rax
.Lnd_after:
    # what a click asked for that changes the tabs: after the frame's drawing
    mov rdi, [rip + g_nb_more_ou]
    test rdi, rdi
    jz 8f
    mov qword ptr [rip + g_nb_more_ou], 0
    call nb_output_tab
8:
.Lnd_ret:
    mov rdi, [rip + nv_text]
    test rdi, rdi
    jz 9f
    mov qword ptr [rip + nv_text], 0
    call nb_open_as_text
9:  EPILOGUE

# nb_reveal(nb, view h): the selected cell into view after it changed, and the cursor's line while
#   it is edited
nb_reveal:
    PROLOGUE 16
    mov rbx, rdi
    movsxd r12, esi
    cmp dword ptr [rbx + NB_reveal], 0
    je 2f
    mov dword ptr [rbx + NB_reveal], 0
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_cell_top
    mov r13, rax                # top
    mov rdi, rbx
    call nb_sel_cell
    test rax, rax
    jz 2f
    mov rdi, rax
    call nb_cell_height
    lea r14, [r13 + rax]        # bottom
    mov eax, [rip + nv_top]
    mov rcx, r13
    sub rcx, rax
    cmp rcx, [rbx + NB_scroll]
    jge 1f
    mov [rbx + NB_scroll], rcx
    jmp 2f
1:  mov rax, r14
    sub rax, r12
    cmp rax, [rbx + NB_scroll]
    jle 2f
    cmp rax, rcx                # a cell taller than the view shows its top
    cmovg rax, rcx
    mov [rbx + NB_scroll], rax
2:  # the line with the cursor
    cmp dword ptr [rbx + NB_editing], 0
    je 9f
    mov rdi, rbx
    call nb_sel_cell
    test rax, rax
    jz 9f
    mov r13, [rax + CL_doc]
    test dword ptr [r13 + DOC_flags], DF_REVEAL
    jnz 3f
    cmp dword ptr [rip + g_reveal], 0
    je 9f
3:  mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_cell_top
    mov r14, rax
    mov rdi, r13
    mov rsi, [r13 + DOC_cur]
    call doc_line_of
    movsxd rcx, dword ptr [rip + g_lh]
    imul rax, rcx
    add r14, rax
    mov eax, [rip + nv_pady]
    add r14, rax                # the line's top
    mov rax, r14
    sub rax, rcx
    cmp rax, [rbx + NB_scroll]
    jge 4f
    mov [rbx + NB_scroll], rax
    jmp 9f
4:  lea rax, [r14 + rcx*2]
    sub rax, r12
    cmp rax, [rbx + NB_scroll]
    jle 9f
    mov [rbx + NB_scroll], rax
9:  EPILOGUE

# nb_press(nb, x, y, w, h): a left press over the cells selects the cell under it; one in a cell's
#   text gives it the keyboard (edit mode), which its editor then places
nb_press:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    test dword ptr [rip + g_pressed], (1 << BTN_LEFT) | (1 << BTN_RIGHT)
    jz 9f
    mov edi, esi
    mov esi, edx
    mov edx, ecx
    sub edx, [rip + nv_sbw]
    mov ecx, r8d
    call ui_in
    test eax, eax
    jz 9f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    # the cell under the pointer
    movsxd r14, dword ptr [rsp + 4]
    mov eax, [rip + nv_top]
    add r14, rax
    sub r14, [rbx + NB_scroll]
    movsxd r15, dword ptr [rip + g_my]
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r13, [rax + r12*8]
    mov rdi, r13
    call nb_cell_height
    lea rcx, [r14 + rax]
    cmp r15, rcx
    jl 2f
    mov r14, rcx
    inc r12
    jmp 1b
2:  # in its frame's text?
    xor ecx, ecx
    mov eax, [rsp]
    add eax, [rip + nv_boxoff]
    cmp [rip + g_mx], eax
    jl 3f
    add eax, [rip + nv_boxw]
    cmp [rip + g_mx], eax
    jge 3f
    mov rdi, r13
    call cell_box_h
    add rax, r14
    cmp r15, rax
    jge 3f
    mov ecx, 1
3:  test dword ptr [rip + g_pressed], 1 << BTN_RIGHT
    jz 31f
    test ecx, ecx
    jz 31f
    cmp r12, [rbx + NB_sel]     # a right press in the edited cell's text is its editor's menu
    jne 31f
    cmp dword ptr [rbx + NB_editing], 0
    jne 9f
31: mov rdi, rbx
    mov rsi, r12
    mov edx, ecx
    call nb_select_mode
9:  EPILOGUE

# nb_draw_state(nb, x, y, w, h): a notebook that is not open yet, or could not be
nb_draw_state:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    lea rdi, [rip + tmp]
    call sb_clear
    cmp dword ptr [rbx + NB_state], NBS_FAILED
    je 2f
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lopening]
    call sb_push_cstr
    mov rax, [rbx + NB_host]
    lea rdi, [rip + tmp]
    mov rsi, [rax + DOC_name]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lellipsis]
    call sb_push_cstr
    mov r12d, [rsp + 12]
    shr r12d, 1
    sub r12d, [rip + g_mt + 4*MI_20]
    add r12d, [rsp + 4]
    COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, r12d
    mov ecx, [rsp + 16 + 8]
    M r8d, MI_40
    mov r9, [rip + tmp + SB_ptr]
    call ui_text_center
    add rsp, 16
    EPILOGUE
2:  # why, and a way to the file as text
    lea rdi, [rip + tmp]
    lea rsi, [rbx + NB_err]
    mov rsi, [rsi + SB_ptr]
    test rsi, rsi
    jnz 21f
    lea rsi, [rip + .Lcannot]
21: call sb_push_cstr
    mov eax, [rsp + 12]
    shr eax, 1
    sub eax, [rip + g_mt + 4*MI_40]
    add eax, [rsp + 4]
    mov [rsp + 16], eax
    COLOR eax, T_ERROR
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 16]
    mov ecx, [rsp + 16 + 8]
    M r8d, MI_32
    mov r9, [rip + tmp + SB_ptr]
    call ui_text_center
    add rsp, 16
    # the button
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lopen_text]
    mov rdx, 12
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov r12d, eax               # its width
    mov esi, [rsp + 8]
    sub esi, r12d
    shr esi, 1
    add esi, [rsp]
    mov r13d, esi
    mov edx, [rsp + 16]
    add edx, [rip + g_mt + 4*MI_40]
    mov r14d, edx
    mov edi, ID_NB_TEXT
    mov ecx, r12d
    M r8d, MI_32
    call ui_btn
    mov r15d, eax
    test eax, UB_CLICK
    jz 3f
    mov [rip + nv_text], rbx
3:  mov edi, r13d
    mov esi, r14d
    mov edx, r12d
    M ecx, MI_32
    M r8d, MI_RADIUS
    COLOR r9d, T_PANEL
    test r15d, UB_HOVER
    jz 4f
    COLOR r9d, T_HOVER
4:  call gfx_round_rect
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r13d
    mov edx, r14d
    mov ecx, r12d
    M r8d, MI_32
    lea r9, [rip + .Lopen_text]
    call ui_text_center
    add rsp, 16
    EPILOGUE

# nb_toolbar(nb, x, y, w, h): Run All, Interrupt, Restart, Clear Outputs; the kernel at the right
nb_toolbar:
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov edi, esi
    mov esi, edx
    mov edx, ecx
    mov ecx, r8d
    COLOR r8d, T_PANEL
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    add esi, [rsp + 12]
    sub esi, [rip + g_mt + 4*MI_1]
    mov edx, [rsp + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 9f
    mov r12d, [rsp]
    add r12d, [rip + g_mt + 4*MI_8]
    xor r13d, r13d
1:  cmp r13d, TB_KERNEL
    jae 2f
    lea rax, [rip + tb_labels]
    mov rcx, [rax + r13*8]
    lea edi, [r13 + ID_NB_TB]
    mov esi, r12d
    mov edx, [rsp + 4]
    mov r8d, [rsp + 12]
    call tb_button
    add r12d, edx
    test eax, UB_CLICK
    jz 11f
    mov rdi, rbx
    mov esi, r13d
    call nb_toolbar_click
11: inc r13d
    jmp 1b
2:  # the kernel: a dot for its state, then its label
    lea rdi, [rip + tmp]
    call sb_clear
    lea rsi, [rbx + NB_kernel]
    cmp qword ptr [rsi + SB_len], 0
    je 21f
    mov rsi, [rsi + SB_ptr]
    jmp 22f
21: lea rsi, [rip + .Lno_kernel]
    mov rax, [rbx + NB_ext]
    mov rax, [rax + EXT_pv_nbkernel]
    test rax, rax
    jz 22f
    cmp byte ptr [rax], 'n'
    jne 22f
    lea rsi, [rip + .Lviewer]
22: lea rdi, [rip + tmp]
    call sb_push_cstr
    lea rdi, [rip + g_face_small]
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    call text_width
    add eax, [rip + g_mt + 4*MI_32]
    mov r14d, eax               # the button's width
    mov r12d, [rsp]
    add r12d, [rsp + 8]
    sub r12d, eax
    sub r12d, [rip + g_mt + 4*MI_8]
    M eax, MI_28
    mov r15d, [rsp + 12]
    sub r15d, eax
    shr r15d, 1
    add r15d, [rsp + 4]         # its y
    mov edi, ID_NB_TB + TB_KERNEL
    mov esi, r12d
    mov edx, r15d
    mov ecx, r14d
    M r8d, MI_28
    call ui_btn
    mov [rsp + 16], eax
    test eax, UB_HOVER
    jz 3f
    mov edi, r12d
    mov esi, r15d
    mov edx, r14d
    M ecx, MI_28
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
    mov edi, CUR_POINTER
    call ui_set_cursor
3:  test dword ptr [rsp + 16], UB_CLICK
    jz 4f
    mov rdi, rbx
    mov esi, TB_KERNEL
    call nb_toolbar_click
4:  # the dot
    mov eax, [rbx + NB_kstate]
    COLOR r9d, T_MUTED
    cmp eax, NBK_IDLE
    jne 41f
    COLOR r9d, T_SUCCESS
41: cmp eax, NBK_BUSY
    jne 42f
    COLOR r9d, T_WARNING
42: cmp eax, NBK_DEAD
    jne 43f
    COLOR r9d, T_ERROR
43: M eax, MI_8
    mov edi, r12d
    add edi, [rip + g_mt + 4*MI_10]
    M ecx, MI_28
    sub ecx, eax
    shr ecx, 1
    lea esi, [r15 + rcx]
    mov edx, eax
    mov ecx, eax
    mov r8d, eax
    shr r8d, 1
    call gfx_round_rect
    lea rdi, [rip + g_face_small]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_24]
    mov edx, r15d
    M ecx, MI_28
    mov r8, [rip + tmp + SB_ptr]
    COLOR r9d, T_FG
    call ui_text_c
9:  EPILOGUE

# tb_button(id, x, y, cstr, bar h) -> eax UB bits, edx the width it took: a text button
tb_button:
    PROLOGUE 32
    mov [rsp], edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov [rsp + 4], r8d
    mov rdi, rcx
    call strlen
    mov rdx, rax
    lea rdi, [rip + g_face_small]
    mov rsi, r14
    call text_width
    add eax, [rip + g_mt + 4*MI_16]
    mov r15d, eax               # width
    M eax, MI_28
    mov ebx, [rsp + 4]
    sub ebx, eax
    shr ebx, 1
    add ebx, r13d               # y
    mov edi, [rsp]
    mov esi, r12d
    mov edx, ebx
    mov ecx, r15d
    M r8d, MI_28
    call ui_btn
    mov [rsp + 8], eax
    test eax, UB_HOVER
    jz 1f
    mov edi, r12d
    mov esi, ebx
    mov edx, r15d
    M ecx, MI_28
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    test dword ptr [rsp + 8], UB_HELD
    jz 2f
    COLOR r9d, T_ACTIVE
2:  call gfx_round_rect
    mov edi, CUR_POINTER
    call ui_set_cursor
1:  lea rdi, [rip + g_face_small]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, ebx
    M ecx, MI_28
    mov r8, r14
    COLOR r9d, T_FG
    call ui_text_c
    mov eax, [rsp + 8]
    lea edx, [r15 + 0]
    add edx, [rip + g_mt + 4*MI_4]
    EPILOGUE

# nb_toolbar_click(nb, button)
nb_toolbar_click:
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    cmp esi, TB_RUNALL
    je nb_run_all
    cmp esi, TB_INTERRUPT
    je nb_interrupt
    cmp esi, TB_RESTART
    je nb_restart_ask
    cmp esi, TB_CLEAR
    je nb_clear_all
    jmp nb_kernel_pick

# nb_draw_cell(nb, cl, i, x, y): one cell at y (a frame of its lines, then its outputs)
nb_draw_cell:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], ecx              # x
    mov [rsp + 4], r8d          # y
    mov rdi, r12
    call cell_box_h
    mov [rsp + 8], eax          # frame's height
    mov rdi, r12
    call nb_cell_height
    mov [rsp + 12], eax
    mov eax, [rsp]
    add eax, [rip + nv_boxoff]
    mov [rsp + 16], eax         # frame's x
    xor r14d, r14d              # selected: 1, with the keyboard: 2
    cmp r13, [rbx + NB_sel]
    jne 1f
    mov r14d, 1
    cmp dword ptr [rbx + NB_editing], 0
    je 1f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 1f
    mov r14d, 2
1:  mov [rsp + 20], r14d
    # the selection bar
    test r14d, r14d
    jz 2f
    mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, [rsp + 4]
    M edx, MI_4
    mov ecx, [rsp + 12]
    sub ecx, [rip + nv_gap]
    COLOR r8d, T_ACCENT
    cmp r14d, 2
    je 11f
    mov edi, r8d
    mov esi, 140
    call color_alpha
    mov r8d, eax
    mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, [rsp + 4]
    M edx, MI_4
    mov ecx, [rsp + 12]
    sub ecx, [rip + nv_gap]
11: call gfx_fill
2:  # the frame
    COLOR eax, T_BG
    push rax
    push rax
    mov edi, [rsp + 16 + 16]
    mov esi, [rsp + 16 + 4]
    mov edx, [rip + nv_boxw]
    mov ecx, [rsp + 16 + 8]
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    cmp dword ptr [rsp + 16 + 20], 2
    jne 21f
    COLOR r9d, T_ACCENT
21: call gfx_frame
    add rsp, 16
    # the count column of a code cell, and its run button
    cmp dword ptr [r12 + CL_kind], CLK_CODE
    jne 3f
    mov rdi, rbx
    mov rsi, r12
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    mov r8d, [rsp + 8]
    call nb_draw_prompt
3:  # its text: the part on screen, by the editor
    mov eax, [rsp + 16]
    add eax, [rip + g_border]
    mov [rsp + 24], eax         # editor x
    mov ecx, [rip + nv_boxw]
    sub ecx, [rip + g_border]
    sub ecx, [rip + g_border]
    mov [rsp + 28], ecx         # editor w
    mov eax, [rsp + 4]
    add eax, [rip + nv_pady]
    mov [rsp + 32], eax         # its lines' top
    mov eax, [rsp + 8]
    sub eax, [rip + nv_pady]
    sub eax, [rip + nv_pady]
    add eax, [rsp + 32]
    mov [rsp + 36], eax         # their bottom
    mov eax, [rsp + 32]
    cmp eax, [rip + g_cv + CV_cy0]
    jge 31f
    mov eax, [rip + g_cv + CV_cy0]
31: mov ecx, [rsp + 36]
    cmp ecx, [rip + g_cv + CV_cy1]
    jle 32f
    mov ecx, [rip + g_cv + CV_cy1]
32: cmp ecx, eax
    jle 4f
    mov [rsp + 40], eax         # visible top
    sub ecx, eax
    mov [rsp + 44], ecx         # visible height
    # how much of it is above the view, in 1/256 lines
    mov r15, [r12 + CL_doc]
    sub eax, [rsp + 32]
    movsxd rax, eax
    shl rax, 8
    cqo
    movsxd rcx, dword ptr [rip + g_lh]
    idiv rcx
    mov [r15 + DOC_scrolly], rax
    cmp dword ptr [rsp + 20], 2
    jne 33f
    # the keyboard's cell is drawn after the others
    mov [rip + nv_edoc], r15
    mov eax, [rsp + 24]
    mov [rip + nv_ex], eax
    mov eax, [rsp + 40]
    mov [rip + nv_ey], eax
    mov eax, [rsp + 28]
    mov [rip + nv_ew], eax
    mov eax, [rsp + 44]
    mov [rip + nv_eh], eax
    jmp 4f
33: mov rdi, r15
    mov esi, [rsp + 24]
    mov edx, [rsp + 40]
    mov ecx, [rsp + 28]
    mov r8d, [rsp + 44]
    xor r9d, r9d
    call editor_draw_cell
4:  # its outputs
    cmp qword ptr [r12 + CL_outs + VEC_len], 0
    je 9f
    mov eax, [rsp + 4]
    add eax, [rsp + 8]
    add eax, [rip + nv_ogap]
    mov r14d, eax               # y
    cmp dword ptr [r12 + CL_collapsed], 0
    je 5f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [r12 + CL_outs + VEC_len]
    call sb_push_u64
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lhidden]
    call sb_push_cstr
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, r14d
    add edx, [rip + g_mt + 4*MI_4]
    add edx, [rip + g_base]
    mov rcx, [rip + tmp + SB_ptr]
    mov r8, [rip + tmp + SB_len]
    COLOR r9d, T_MUTED
    call text_draw
    jmp 9f
5:  xor r15d, r15d
6:  cmp r15, [r12 + CL_outs + VEC_len]
    jae 9f
    cmp r14d, [rip + g_cv + CV_cy1]
    jge 9f
    mov rax, [r12 + CL_outs + VEC_ptr]
    mov r13, [rax + r15*8]
    inc r15
    mov rdi, r13
    mov esi, [rip + nv_boxw]
    call nb_ou_height
    mov [rsp + 48], eax
    lea ecx, [r14 + rax]
    cmp ecx, [rip + g_cv + CV_cy0]
    jle 61f
    mov rdi, r13
    mov esi, [rsp + 16]
    mov edx, r14d
    mov ecx, [rip + nv_boxw]
    mov r8d, [rip + nv_oslot]
    call nb_ou_draw
    inc dword ptr [rip + nv_oslot]
61: add r14d, [rsp + 48]
    jmp 6b
9:  EPILOGUE

# nb_draw_prompt(nb, cl, x, y, frame h): "[12]", "[*]" while it runs, "[ ]" before; a run triangle
#   while the pointer is over the column, which runs the cell when clicked
nb_draw_prompt:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov [rsp + 8], r8d
    mov eax, [rip + nv_slot]
    inc dword ptr [rip + nv_slot]
    and eax, 255
    lea edi, [rax + ID_NB_RUN]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 4]
    mov ecx, [rip + nv_prompt]
    mov r8d, [rsp + 8]
    call ui_btn
    mov [rsp + 12], eax
    test eax, UB_CLICK
    jz 1f
    # the run, after the press selected the cell
    mov rdi, rbx
    mov rsi, r12
    call nb_cell_index
    mov rdi, rbx
    mov rsi, rax
    call nb_run
1:  lea rdi, [rip + numbuf]
    mov byte ptr [rdi], '['
    inc rdi
    mov eax, [r12 + CL_state]
    cmp eax, RUN_QUEUED
    je 2f
    cmp eax, RUN_RUNNING
    je 2f
    mov rsi, [r12 + CL_count]
    test rsi, rsi
    js 3f
    call fmt_u64
    lea rdi, [rip + numbuf + 1]
    add rdi, rax
    jmp 4f
2:  mov byte ptr [rdi], '*'
    inc rdi
    jmp 4f
3:  mov byte ptr [rdi], ' '
    inc rdi
4:  mov byte ptr [rdi], ']'
    inc rdi
    lea rax, [rip + numbuf]
    sub rdi, rax
    mov r13, rdi                # bytes
    lea rdi, [rip + g_face_code]
    lea rsi, [rip + numbuf]
    mov rdx, r13
    call text_width
    mov esi, [rsp]
    add esi, [rip + nv_boxoff]
    sub esi, [rip + g_mt + 4*MI_8]
    sub esi, eax
    mov r14d, esi
    COLOR r9d, T_MUTED
    mov eax, [r12 + CL_state]
    cmp eax, RUN_QUEUED
    je 41f
    cmp eax, RUN_RUNNING
    jne 42f
41: COLOR r9d, T_ACCENT
42: lea rdi, [rip + g_face_code]
    mov esi, r14d
    mov edx, [rsp + 4]
    add edx, [rip + nv_pady]
    add edx, [rip + g_base]
    lea rcx, [rip + numbuf]
    mov r8, r13
    call text_draw
    test dword ptr [rsp + 12], UB_HOVER
    jz 9f
    mov edi, CUR_POINTER
    call ui_set_cursor
    # a triangle pointing right, left of the count
    M r15d, MI_10               # its height
    mov eax, [rsp + 4]
    add eax, [rip + nv_pady]
    mov ecx, [rip + g_lh]
    sub ecx, r15d
    sar ecx, 1
    add eax, ecx
    mov [rsp + 16], eax         # top
    mov eax, r14d
    sub eax, [rip + g_mt + 4*MI_6]
    sub eax, r15d
    mov [rsp + 20], eax         # left
    xor r13d, r13d
5:  cmp r13d, r15d
    jae 9f
    # row r13: from the left, as wide as its distance from the nearer end
    mov eax, r13d
    mov ecx, r15d
    sub ecx, r13d
    dec ecx
    cmp eax, ecx
    cmova eax, ecx
    inc eax
    mov edx, eax
    mov edi, [rsp + 20]
    mov esi, [rsp + 16]
    add esi, r13d
    M ecx, MI_1
    COLOR r8d, T_ACCENT
    call gfx_fill
    inc r13d
    jmp 5b
9:  EPILOGUE

# nb_frame_x() -> x of the cells' frames in the active notebook (print-notebook's at=)
FN nb_frame_x
    mov eax, [rip + g_editor_rect]
    add eax, [rip + nv_boxoff]
    ret

# nb_cell_index(nb, cl) -> its index, or -1
FN nb_cell_index
    xor ecx, ecx
1:  cmp rcx, [rdi + NB_cells + VEC_len]
    jae 8f
    mov rax, [rdi + NB_cells + VEC_ptr]
    cmp [rax + rcx*8], rsi
    je 2f
    inc rcx
    jmp 1b
2:  mov rax, rcx
    ret
8:  mov rax, -1
    ret

# nb_open_as_text(nb): the notebook's tab closes and the file opens as text (its extension could not
#   read it, or the user asked); a notebook with changes stays
FN nb_open_as_text
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    call nb_sync_dirty
    test eax, eax
    jz 1f
    lea rdi, [rip + .Lsave_first]
    call app_toast
    jmp 9f
1:  mov rax, [rbx + NB_host]
    mov rdi, [rax + DOC_path]
    call dup_cstr
    mov r12, rax
    mov rdi, [rbx + NB_host]
    call doc_tab
    test rax, rax
    js 8f
    mov rdi, rax
    call app_close_tab_now
    mov dword ptr [rip + g_nb_open_text], 1
    mov rdi, r12
    call app_open_file
    mov dword ptr [rip + g_nb_open_text], 0
8:  mov rdi, r12
    call mem_free
9:  EPILOGUE

.section .rodata
.p2align 3
tb_labels: .quad .Ltb_runall, .Ltb_interrupt, .Ltb_restart, .Ltb_clear
.Ltb_runall: .asciz "Run All"
.Ltb_interrupt: .asciz "Interrupt"
.Ltb_restart: .asciz "Restart"
.Ltb_clear: .asciz "Clear Outputs"
.Lno_kernel: .asciz "Select Kernel"
.Lviewer: .asciz "Viewer"
.Lopening: .asciz "Opening "
.Lellipsis: .asciz "\342\200\246"
.Lcannot: .asciz "The notebook cannot be opened"
.Lopen_text: .asciz "Open as Text"
.Lhidden: .asciz " outputs hidden (o shows them)"
.Ldisk: .asciz "The file changed on disk. Save keeps these cells; Revert File reads it again."
.Lsave_first: .asciz "Save or revert the notebook's changes first"
