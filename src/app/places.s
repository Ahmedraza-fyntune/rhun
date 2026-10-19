# places: where views show. The sidebar stacks sections (the explorer first), the bottom panel shows
# the terminal sessions and, after them, view tabs, and the right column shows the agents panel and
# side tabs. Built-in code and extension views register the same way: place_add with a table of
# callbacks (PLO in rhun.inc); the slot index is the item's id. A sidebar with the explorer alone is
# drawn exactly as before there were sections.
.include "rhun.inc"

.equ ID_SB_HEAD, 0x5d0000        # + id: a section's header
.equ ID_PT_TAB, 0x5d1000         # + id: a panel view tab
.equ ID_PT_X, 0x5d2000           # + id: its close button
.equ ID_SD_TAB, 0x5d3000         # + id: a side tab
.equ ID_SD_AGENTS, 0x5d3fff      # the side strip's Agents tab

.bss
.p2align 3
.globl g_places, g_place_focus, g_panel_cur, g_side_cur, g_explorer_place
g_places: .zero PL_SIZE * PL_MAX
place_seq: .long 0
.p2align 3
sb_order: .zero 4 * PL_MAX      # the sidebar's sections in order, while it is drawn
pt_order: .zero 4 * PL_MAX      # the panel's view tabs
sd_order: .zero 4 * PL_MAX      # the side tabs
order: .zero 4 * PL_MAX         # scratch for the commands
upper: .zero 128                # scratch: a section title in capitals

.data
.p2align 2
g_place_focus: .long -1         # the item with the keyboard while g_focus is FOCUS_VIEW
g_panel_cur: .long -1           # the panel's chosen view tab, -1: the terminals
g_side_cur: .long -1            # the right column's chosen side tab, -1: the agents panel
g_explorer_place: .long -1
last_focus: .long -1            # the item whose focus(1) was called last

.text

# ---------------- the registry ----------------

# place_at(id) -> rax PL* or 0 when the id names no item
FN place_at
    xor eax, eax
    cmp edi, PL_MAX
    jae 1f
    imul eax, edi, PL_SIZE
    lea rcx, [rip + g_places]
    add rax, rcx
    cmp dword ptr [rax + PL_place], 0
    jne 1f
    xor eax, eax
1:  ret

# place_add(place, name cstr, title cstr, ops, ctx) -> eax its id, or -1 when every slot is taken.
#   The name and title are copied; ops must outlive the item. Sections start expanded, weight 1.
FN place_add
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    xor ecx, ecx
1:  cmp ecx, PL_MAX
    jae 8f
    imul eax, ecx, PL_SIZE
    lea rdx, [rip + g_places]
    cmp dword ptr [rdx + rax + PL_place], 0
    je 2f
    inc ecx
    jmp 1b
2:  push rcx
    push rcx
    lea rdi, [rdx + rax]
    xor esi, esi
    mov edx, PL_SIZE
    call memset
    mov rdi, r12
    call dup_cstr
    mov r12, rax
    mov rdi, r13
    call dup_cstr
    mov r13, rax
    pop rcx
    pop rcx
    imul eax, ecx, PL_SIZE
    lea rdx, [rip + g_places]
    add rax, rdx
    mov [rax + PL_place], ebx
    mov [rax + PL_ops], r14
    mov [rax + PL_ctx], r15
    mov [rax + PL_name], r12
    mov [rax + PL_title], r13
    mov dword ptr [rax + PL_icon], -1
    mov dword ptr [rax + PL_weight], 1
    mov edx, [rip + place_seq]
    mov [rax + PL_seq], edx
    inc dword ptr [rip + place_seq]
    mov dword ptr [rip + g_dirty], 1
    mov eax, ecx
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# place_remove(id): the item leaves its place; the keyboard, the chosen tab and visibility let go
#   of it without calling it again
FN place_remove
    PROLOGUE
    mov ebx, edi
    call place_at
    test rax, rax
    jz 9f
    mov r12, rax
    cmp [rip + last_focus], ebx
    jne 1f
    mov dword ptr [rip + last_focus], -1
1:  cmp [rip + g_place_focus], ebx
    jne 2f
    mov dword ptr [rip + g_place_focus], -1
    cmp dword ptr [rip + g_focus], FOCUS_VIEW
    jne 2f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
2:  cmp [rip + g_panel_cur], ebx
    jne 3f
    mov dword ptr [rip + g_panel_cur], -1
3:  cmp [rip + g_side_cur], ebx
    jne 4f
    mov dword ptr [rip + g_side_cur], -1
4:  mov rdi, [r12 + PL_name]
    call mem_free
    mov rdi, [r12 + PL_title]
    call mem_free
    mov rdi, r12
    xor esi, esi
    mov edx, PL_SIZE
    call memset
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# place_set_title(id, ptr, len): what its header or tab says
FN place_set_title
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call place_at
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, [rbx + PL_title]
    call mem_free
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx + PL_title], rax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# place_set_badge(id, n): the count beside its title (0 hides it)
FN place_set_badge
    push rsi
    call place_at
    pop rsi
    test rax, rax
    jz 1f
    mov [rax + PL_badge], esi
    mov dword ptr [rip + g_dirty], 1
1:  ret

# place_set_icon(id, IC_* or -1): the icon on its panel or side tab
FN place_set_icon
    push rsi
    call place_at
    pop rsi
    test rax, rax
    jz 1f
    mov [rax + PL_icon], esi
    mov dword ptr [rip + g_dirty], 1
1:  ret

# place_set_busy(id, on): a spinner in its header or tab
FN place_set_busy
    push rsi
    call place_at
    pop rsi
    test rax, rax
    jz 2f
    and dword ptr [rax + PL_flags], ~PLF_BUSY
    test esi, esi
    jz 1f
    or dword ptr [rax + PL_flags], PLF_BUSY
1:  mov dword ptr [rip + g_dirty], 1
2:  ret

# place_set_collapsed(id, on): a sidebar section shows only its header (1) or its body too
FN place_set_collapsed
    push rsi
    call place_at
    pop rsi
    test rax, rax
    jz 2f
    and dword ptr [rax + PL_flags], ~PLF_COLLAPSED
    test esi, esi
    jz 1f
    or dword ptr [rax + PL_flags], PLF_COLLAPSED
1:  mov dword ptr [rip + g_dirty], 1
2:  ret

# place_set_hidden(id, on): left out of its place (1) until shown again
FN place_set_hidden
    push rsi
    call place_at
    pop rsi
    test rax, rax
    jz 2f
    and dword ptr [rax + PL_flags], ~PLF_HIDDEN
    test esi, esi
    jz 1f
    or dword ptr [rax + PL_flags], PLF_HIDDEN
1:  mov dword ptr [rip + g_dirty], 1
2:  ret

# place_visible(id) -> eax 1 when it was drawn last frame
FN place_visible
    call place_at
    test rax, rax
    jz 1f
    mov eax, [rax + PL_flags]
    shr eax, 4                  # PLF_VISIBLE
    and eax, 1
1:  ret

# place_show(id, focus): its place opens on it: the sidebar shows with the section expanded, the
#   panel opens on the tab, the right column on the side tab; focus 1 also gives it the keyboard
FN place_show
    PROLOGUE
    mov ebx, edi
    mov r13d, esi
    call place_at
    test rax, rax
    jz 9f
    mov r12, rax
    and dword ptr [r12 + PL_flags], ~(PLF_HIDDEN | PLF_COLLAPSED)
    mov eax, [r12 + PL_place]
    cmp eax, PLACE_SIDEBAR
    jne 1f
    mov dword ptr [rip + g_show_side], 1
    jmp 5f
1:  cmp eax, PLACE_PANEL
    jne 2f
    mov dword ptr [rip + g_term_open], 1
    mov [rip + g_panel_cur], ebx
    jmp 5f
2:  cmp eax, PLACE_SIDE
    jne 5f
    mov dword ptr [rip + g_show_agents], 1
    mov [rip + g_side_cur], ebx
5:  test r13d, r13d
    jz 8f
    mov edi, ebx
    call place_focus
8:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# place_focus(id): the keyboard to the item (the explorer's section: the explorer itself)
FN place_focus
    push rbx
    mov ebx, edi
    call place_at
    test rax, rax
    jz 9f
    cmp ebx, [rip + g_explorer_place]
    jne 1f
    pop rbx
    jmp cmd_focus_explorer
1:  mov [rip + g_place_focus], ebx
    mov dword ptr [rip + g_focus], FOCUS_VIEW
    mov dword ptr [rip + g_dirty], 1
9:  pop rbx
    ret

# place_focused() -> eax the item with the keyboard, or -1
FN place_focused
    mov eax, -1
    cmp dword ptr [rip + g_focus], FOCUS_VIEW
    jne 1f
    mov eax, [rip + g_place_focus]
1:  ret

# place_key(keysym, cp, mods) -> eax 1 when the item with the keyboard took the key; Escape it does
#   not take sends the keyboard back to the editor
FN place_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov edi, [rip + g_place_focus]
    call place_at
    test rax, rax
    jz 7f
    mov rbx, rax
    mov rdi, rbx
    call column_shown
    test eax, eax
    jz 71f
    mov rax, [rbx + PL_ops]
    mov rax, [rax + PLO_key]
    test rax, rax
    jz 6f
    mov rdi, [rbx + PL_ctx]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call rax
    test eax, eax
    jnz 9f
6:  cmp r12d, KEY_ESCAPE
    jne 8f
7:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov eax, 1
    EPILOGUE
71: mov dword ptr [rip + g_focus], FOCUS_EDITOR   # its column was hidden: the editor's again
8:  xor eax, eax
9:  EPILOGUE

# column_shown(PL*) -> eax 0 when the column or panel holding the item is hidden (a tab or a hidden
#   item of rhun's own: 1)
column_shown:
    mov eax, 1
    mov ecx, [rdi + PL_place]
    cmp ecx, PLACE_SIDEBAR
    jne 1f
    mov eax, [rip + g_show_side]
    ret
1:  cmp ecx, PLACE_PANEL
    jne 2f
    mov eax, [rip + g_term_open]
    ret
2:  cmp ecx, PLACE_SIDE
    jne 3f
    mov eax, [rip + g_show_agents]
3:  ret

# place_call_focus(id, on): its focus callback
place_call_focus:
    push rbx
    mov ebx, esi
    call place_at
    test rax, rax
    jz 9f
    mov rcx, [rax + PL_ops]
    mov rcx, [rcx + PLO_focus]
    test rcx, rcx
    jz 9f
    mov rdi, [rax + PL_ctx]
    mov esi, ebx
    call rcx
9:  pop rbx
    ret

# places_frame_end(): after a frame is drawn: focus(0|1) for the keyboard's moves, visible(0|1)
#   for the items that came on or went off screen
FN places_frame_end
    PROLOGUE
    call place_focused          # an item whose column went away gives the keyboard back
    mov edi, eax
    call place_at
    test rax, rax
    jz 1f
    mov rdi, rax
    call column_shown
    test eax, eax
    jnz 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
1:  call place_focused
    mov ebx, eax
    cmp ebx, [rip + last_focus]
    je 3f
    mov edi, [rip + last_focus]
    mov [rip + last_focus], ebx
    xor esi, esi
    call place_call_focus
    mov edi, ebx
    mov esi, 1
    call place_call_focus
3:  xor r12d, r12d
4:  cmp r12d, PL_MAX
    jae 9f
    imul eax, r12d, PL_SIZE
    lea rbx, [rip + g_places]
    add rbx, rax
    cmp dword ptr [rbx + PL_place], 0
    je 7f
    mov eax, [rbx + PL_flags]
    mov ecx, eax
    and eax, PLF_DRAWN
    shr eax, 3
    and ecx, PLF_VISIBLE
    shr ecx, 4
    and dword ptr [rbx + PL_flags], ~PLF_DRAWN
    test eax, eax
    jnz 5f
    mov dword ptr [rbx + PL_w], 0     # not drawn: tests find no rectangle
5:  cmp eax, ecx
    je 7f
    mov r13d, eax
    and dword ptr [rbx + PL_flags], ~PLF_VISIBLE
    test eax, eax
    jz 6f
    or dword ptr [rbx + PL_flags], PLF_VISIBLE
6:  mov rax, [rbx + PL_ops]
    mov rax, [rax + PLO_visible]
    test rax, rax
    jz 7f
    mov rdi, [rbx + PL_ctx]
    mov esi, r13d
    call rax
7:  inc r12d
    jmp 4b
9:  EPILOGUE

# place_list(place, buf) -> eax how many items of that place are not hidden, their ids in buf (u32
#   each, PL_MAX at most) in registration order
place_list:
    PROLOGUE
    mov ebx, edi
    mov r14, rsi
    xor r12d, r12d              # count
    xor r13d, r13d              # slot
1:  cmp r13d, PL_MAX
    jae 5f
    imul eax, r13d, PL_SIZE
    lea rcx, [rip + g_places]
    add rcx, rax
    cmp [rcx + PL_place], ebx
    jne 4f
    test dword ptr [rcx + PL_flags], PLF_HIDDEN
    jnz 4f
    # insertion by seq
    mov r8d, [rcx + PL_seq]
    mov r9d, r12d
2:  test r9d, r9d
    jz 3f
    mov r10, r14
    mov eax, [r10 + r9*4 - 4]
    imul eax, eax, PL_SIZE
    lea rdx, [rip + g_places]
    cmp [rdx + rax + PL_seq], r8d
    jbe 3f
    mov eax, [r10 + r9*4 - 4]
    mov [r10 + r9*4], eax
    dec r9d
    jmp 2b
3:  mov [r14 + r9*4], r13d
    inc r12d
4:  inc r13d
    jmp 1b
5:  mov eax, r12d
    EPILOGUE

# place_mark_drawn(PL*, x, y, w, h)
place_mark_drawn:
    or dword ptr [rdi + PL_flags], PLF_DRAWN
    mov [rdi + PL_x], esi
    mov [rdi + PL_y], edx
    mov [rdi + PL_w], ecx
    mov [rdi + PL_h], r8d
    ret

# place_body(id, x, y, w, h): the item's body, clipped; a press inside first gives it the keyboard
FN place_body
    PROLOGUE 32
    mov ebx, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    call place_at
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, r12
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call place_mark_drawn
    cmp dword ptr [rsp + 8], 0
    jle 9f
    cmp dword ptr [rsp + 12], 0
    jle 9f
    test dword ptr [rip + g_pressed], (1 << BTN_LEFT) | (1 << BTN_RIGHT)
    jz 1f
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    cmp ebx, [rip + g_explorer_place]
    je 1f                       # the explorer's rows set its own focus
    mov edi, ebx
    call place_focus
1:  mov edi, [rsp]             # its background: the panel's in the sidebar and the side column,
    mov esi, [rsp + 4]          # the editor's in the bottom panel and a tab
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_PANEL
    cmp dword ptr [r12 + PL_place], PLACE_PANEL
    je 11f
    cmp dword ptr [r12 + PL_place], PLACE_TAB
    jne 12f
11: COLOR r8d, T_BG
12: call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    mov rax, [r12 + PL_ops]
    mov rax, [rax + PLO_draw]
    test rax, rax
    jz 2f
    mov rdi, [r12 + PL_ctx]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call rax
2:  call gfx_clip_pop
9:  EPILOGUE

# badge_draw(x, y, h, n) -> eax the width it took: the count in a small rounded pill
FN badge_draw
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    lea rdi, [rsp + 16]
    mov esi, ecx
    call fmt_u64
    mov [rsp + 12], eax
    mov byte ptr [rsp + 16 + rax], 0
    lea rdi, [rip + g_face_small]
    lea rsi, [rsp + 16]
    mov edx, [rsp + 12]
    call text_width
    add eax, [rip + g_mt + 4*MI_10]
    M ecx, MI_16
    cmp eax, ecx
    cmovl eax, ecx
    mov [rsp + 40], eax         # pill width
    mov edi, [rsp]
    mov esi, [rsp + 8]
    sub esi, ecx
    sar esi, 1
    add esi, [rsp + 4]
    mov [rsp + 44], esi
    mov edx, eax
    M r8d, MI_8
    COLOR r9d, T_HOVER
    call gfx_round_rect
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    mov edx, [rsp + 44]
    mov ecx, [rsp + 40]
    M r8d, MI_16
    lea r9, [rsp + 16]
    COLOR eax, T_FG
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    mov eax, [rsp + 40]
    EPILOGUE

# ---------------- the sidebar ----------------

# sidebar_draw(x, y, w, h): the explorer alone as it always was; with other sections, each its header
#   (chevron, title in capitals, badge, its actions while the pointer is over it or it has the
#   keyboard) and, when expanded, its body; the expanded bodies share the height by weight
FN sidebar_draw
    PROLOGUE 64
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov edi, PLACE_SIDEBAR
    lea rsi, [rip + sb_order]
    call place_list
    mov [rsp + 16], eax         # sections
    cmp eax, 1
    ja .Lsd_stack
    jb 1f
    mov eax, [rip + sb_order]
    cmp eax, [rip + g_explorer_place]
    jne .Lsd_stack
1:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call explorer_draw
    mov edi, [rip + g_explorer_place]
    call place_at
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call place_mark_drawn
    jmp 9f
.Lsd_stack:
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_PANEL
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    # height left for bodies, and the expanded sections' weights
    M eax, MI_28
    imul eax, [rsp + 16]
    mov ecx, [rsp + 12]
    sub ecx, eax
    xor eax, eax
    test ecx, ecx
    cmovs ecx, eax
    mov [rsp + 20], ecx         # body height to share
    xor r12d, r12d
    xor r13d, r13d              # total weight
2:  cmp r12d, [rsp + 16]
    jae 3f
    lea rax, [rip + sb_order]
    mov edi, [rax + r12*4]
    call place_at
    test dword ptr [rax + PL_flags], PLF_COLLAPSED
    jnz 21f
    add r13d, [rax + PL_weight]
21: inc r12d
    jmp 2b
3:  mov [rsp + 24], r13d
    mov dword ptr [rsp + 28], 0 # weight drawn so far
    mov dword ptr [rsp + 32], 0 # body height given so far
    mov eax, [rsp + 4]
    mov [rsp + 36], eax         # y
    xor r12d, r12d
.Lsd_section:
    cmp r12d, [rsp + 16]
    jae .Lsd_done
    lea rax, [rip + sb_order]
    mov ebx, [rax + r12*4]
    mov edi, ebx
    call place_at
    mov r14, rax
    # its body height: its share of what is left, the last one taking the rest
    xor r15d, r15d
    test dword ptr [r14 + PL_flags], PLF_COLLAPSED
    jnz 4f
    mov eax, [rsp + 28]
    add eax, [r14 + PL_weight]
    mov [rsp + 28], eax
    imul eax, [rsp + 20]
    xor edx, edx
    mov ecx, [rsp + 24]
    test ecx, ecx
    jz 4f
    div ecx
    sub eax, [rsp + 32]
    mov r15d, eax
    add [rsp + 32], eax
4:  mov eax, [rsp + 36]
    mov [r14 + PL_hy], eax
    mov edi, ebx
    mov esi, [rsp]
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    mov r8d, r12d
    call section_header
    M eax, MI_28
    add [rsp + 36], eax
    test r15d, r15d
    jz 5f
    mov edi, ebx
    mov esi, [rsp]
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    mov r8d, r15d
    call place_body
    add [rsp + 36], r15d
5:  inc r12d
    jmp .Lsd_section
.Lsd_done:
    call gfx_clip_pop
9:  EPILOGUE

# section_header(id, x, y, w, index): a section's header row; a click toggles it
section_header:
    PROLOGUE 48
    mov ebx, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    call place_at
    mov r12, rax
    M r15d, MI_28
    test dword ptr [rsp + 12], -1
    jz 1f
    mov edi, [rsp]              # a line between sections
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
1:  lea edi, [rbx + ID_SB_HEAD]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, r15d
    call ui_btn
    mov [rsp + 16], eax
    test eax, UB_CLICK
    jz 2f
    xor dword ptr [r12 + PL_flags], PLF_COLLAPSED
    mov dword ptr [rip + g_dirty], 1
2:  # chevron
    M ecx, MI_16
    mov edi, IC_CHEV_D
    test dword ptr [r12 + PL_flags], PLF_COLLAPSED
    jz 21f
    mov edi, IC_CHEV_R
21: mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, r15d
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    # the title in capitals (ASCII letters), at most 120 bytes
    mov rsi, [r12 + PL_title]
    lea rdi, [rip + upper]
    xor ecx, ecx
3:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 4f
    cmp ecx, 120
    jae 4f
    lea edx, [rax - 'a']
    cmp edx, 25
    ja 31f
    sub eax, 32
31: mov [rdi + rcx], al
    inc ecx
    jmp 3b
4:  mov byte ptr [rdi + rcx], 0
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_24]
    mov edx, [rsp + 4]
    mov ecx, r15d
    lea r8, [rip + upper]
    COLOR r9d, T_MUTED
    test dword ptr [rsp + 16], UB_HOVER
    jz 41f
    COLOR r9d, T_FG
41: call ui_text_c
    mov r13d, eax               # x after the title
    cmp dword ptr [r12 + PL_badge], 0
    je 5f
    mov edi, r13d
    add edi, [rip + g_mt + 4*MI_6]
    mov esi, [rsp + 4]
    mov edx, r15d
    mov ecx, [r12 + PL_badge]
    call badge_draw
5:  test dword ptr [r12 + PL_flags], PLF_BUSY
    jz 6f
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 4]
    mov ecx, r15d
    lea r8, [rip + .Lbusy]
    COLOR r9d, T_MUTED
    call ui_text_c
6:  # its actions while the pointer is over it or it has the keyboard
    mov rax, [r12 + PL_ops]
    cmp qword ptr [rax + PLO_actions], 0
    je 9f
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, r15d
    add ecx, [r12 + PL_h]
    call ui_in
    test eax, eax
    jnz 7f
    call place_focused
    cmp eax, ebx
    je 7f
    cmp ebx, [rip + g_explorer_place]
    jne 9f
    cmp dword ptr [rip + g_focus], FOCUS_EXPLORER
    jne 9f
7:  mov rax, [r12 + PL_ops]
    mov rax, [rax + PLO_actions]
    mov rdi, [r12 + PL_ctx]
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 4]
    mov ecx, r15d
    call rax
9:  EPILOGUE

# ---------------- the panel ----------------

# panel_tab_width(PL*) -> eax: icon, title (at most 200 points), badge, close button
panel_tab_width:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + PL_title]
    mov rdi, rsi
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + PL_title]
    mov rdx, rax
    call text_width
    mov r12d, eax
    mov edi, 200
    call sc
    cmp r12d, eax
    cmovg r12d, eax
    add r12d, [rip + g_mt + 4*MI_20]
    cmp dword ptr [rbx + PL_icon], 0
    jl 1f
    add r12d, [rip + g_mt + 4*MI_20]
1:  cmp dword ptr [rbx + PL_badge], 0
    je 2f
    add r12d, [rip + g_mt + 4*MI_24]
2:  mov rax, [rbx + PL_ops]
    cmp qword ptr [rax + PLO_close], 0
    je 3f
    add r12d, [rip + g_mt + 4*MI_20]
3:  mov eax, r12d
    EPILOGUE

# places_panel_tabs_width() -> eax: what the panel's view tabs and their separator take in its strip
FN places_panel_tabs_width
    PROLOGUE
    mov edi, PLACE_PANEL
    lea rsi, [rip + pt_order]
    call place_list
    mov r13d, eax
    xor r12d, r12d
    test r13d, r13d
    jz 9f
    M r12d, MI_12               # the separator
    xor ebx, ebx
1:  cmp ebx, r13d
    jae 9f
    lea rax, [rip + pt_order]
    mov edi, [rax + rbx*4]
    call place_at
    mov rdi, rax
    call panel_tab_width
    add r12d, eax
    inc ebx
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# places_panel_tabs(x, y, right, h, sessions) -> eax the x after them: the panel's view tabs in its
#   strip after the terminal sessions (header_draw), a separator between when there are sessions
FN places_panel_tabs
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov [rsp + 16], r8d
    mov edi, PLACE_PANEL
    lea rsi, [rip + pt_order]
    call place_list
    mov [rsp + 20], eax
    xor ecx, ecx                # no tab drawn yet (tests: place_dump's tab lines)
91: cmp ecx, eax
    jae 92f
    lea rdx, [rip + pt_order]
    mov edx, [rdx + rcx*4]
    imul edx, edx, PL_SIZE
    lea r8, [rip + g_places]
    mov dword ptr [r8 + rdx + PL_pad], 0
    inc ecx
    jmp 91b
92: test eax, eax
    jz .Lpt_ret
    cmp dword ptr [rsp + 16], 0
    je 1f
    mov edi, [rsp]              # the separator
    add edi, [rip + g_mt + 4*MI_6]
    mov esi, [rsp + 12]
    sar esi, 2
    add esi, [rsp + 4]
    M edx, MI_1
    mov ecx, [rsp + 12]
    sar ecx, 1
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + g_mt + 4*MI_12]
    add [rsp], eax
1:  xor r12d, r12d
.Lpt_tab:
    cmp r12d, [rsp + 20]
    jae .Lpt_ret
    lea rax, [rip + pt_order]
    mov ebx, [rax + r12*4]
    mov edi, ebx
    call place_at
    mov r13, rax
    mov rdi, r13
    call panel_tab_width
    mov r14d, eax
    mov eax, [rsp]
    add eax, r14d
    cmp eax, [rsp + 8]
    jg .Lpt_ret                 # no room: not cut off with its close button out of reach
    mov eax, [rsp]
    inc eax
    mov [r13 + PL_pad], eax     # where it was drawn (tests)
    mov [r13 + PL_hy], r14d
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, r14d
    mov ecx, [rsp + 12]
    call ui_in
    mov [rsp + 24], eax         # hover anywhere on the tab
    lea edi, [rbx + ID_PT_TAB]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, r14d
    mov rax, [r13 + PL_ops]
    cmp qword ptr [rax + PLO_close], 0
    je 2f
    sub ecx, [rip + g_mt + 4*MI_20]
2:  mov r8d, [rsp + 12]
    call ui_btn
    test eax, UB_PRESS
    jz 3f
    mov edi, ebx
    mov esi, 1
    call place_show
3:  # chosen: the line under it, accented while it has the keyboard
    COLOR r15d, T_MUTED
    cmp ebx, [rip + g_panel_cur]
    jne 4f
    COLOR r15d, T_FG
    mov edi, [rsp]
    mov esi, [rsp + 4]
    add esi, [rsp + 12]
    sub esi, [rip + g_mt + 4*MI_2]
    mov edx, r14d
    M ecx, MI_2
    COLOR r8d, T_MUTED
    call place_focused
    cmp eax, ebx
    jne 31f
    COLOR r8d, T_ACCENT
31: call gfx_fill
    jmp 5f
4:  cmp dword ptr [rsp + 24], 0
    je 5f
    COLOR r15d, T_FG
5:  mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_10]
    mov [rsp + 28], eax         # x of what comes next
    cmp dword ptr [r13 + PL_icon], 0
    jl 6f
    mov edi, [r13 + PL_icon]
    mov esi, [rsp + 28]
    M ecx, MI_16
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    mov r8d, r15d
    call icon_draw
    mov eax, [rip + g_mt + 4*MI_20]
    add [rsp + 28], eax
6:  mov edi, 200
    call sc
    mov [rsp + 32], eax
    mov rdi, [r13 + PL_title]
    call strlen
    mov r9, rax
    mov eax, [rsp + 32]
    push rax
    push r15
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 28]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 12]
    mov r8, [r13 + PL_title]
    call ui_text_v_fit
    add rsp, 16
    mov rdi, [r13 + PL_title]
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [r13 + PL_title]
    mov rdx, rax
    call text_width
    mov r8d, eax
    mov edi, 200
    call sc
    cmp r8d, eax
    cmovg r8d, eax
    add [rsp + 28], r8d
    cmp dword ptr [r13 + PL_badge], 0
    je 7f
    mov edi, [rsp + 28]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov ecx, [r13 + PL_badge]
    call badge_draw
7:  # its close button while the tab is hovered
    mov rax, [r13 + PL_ops]
    cmp qword ptr [rax + PLO_close], 0
    je 8f
    cmp dword ptr [rsp + 24], 0
    je 8f
    lea edi, [rbx + ID_PT_X]
    mov esi, [rsp]
    add esi, r14d
    sub esi, [rip + g_mt + 4*MI_20]
    M ecx, MI_16
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    mov r8d, ecx
    mov r9d, IC_CLOSE
    call ui_icon_btn
    test eax, UB_CLICK
    jz 8f
    mov rax, [r13 + PL_ops]
    mov rdi, [r13 + PL_ctx]
    call [rax + PLO_close]
    jmp .Lpt_ret                # the item may be gone
8:  add [rsp], r14d
    inc r12d
    jmp .Lpt_tab
.Lpt_ret:
    mov eax, [rsp]
    EPILOGUE

# places_panel_body(x, y, w, h) -> eax 1 when a view tab is chosen: it drew the panel's body (the
#   panel minus its strip) instead of a terminal
FN places_panel_body
    PROLOGUE 16
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov edi, [rip + g_panel_cur]
    call place_at
    test rax, rax
    jz 8f
    test dword ptr [rax + PL_flags], PLF_HIDDEN
    jnz 8f
    M eax, MI_28
    add eax, [rip + g_mt + 4*MI_2]
    mov edx, [rsp + 4]
    add edx, eax
    mov r8d, [rsp + 12]
    sub r8d, eax
    xor eax, eax
    test r8d, r8d
    cmovs r8d, eax
    mov edi, [rip + g_panel_cur]
    mov esi, [rsp]
    mov ecx, [rsp + 8]
    call place_body
    mov eax, 1
    EPILOGUE
8:  mov dword ptr [rip + g_panel_cur], -1
    xor eax, eax
    EPILOGUE

# places_panel_actions(right, y, h) -> eax the x left of them: the chosen view tab's title actions
#   in the panel's strip, left of its + and hide buttons
FN places_panel_actions
    mov ecx, edx
    mov edx, esi
    mov esi, edi
    mov edi, [rip + g_panel_cur]
    jmp item_actions

# item_actions(id, right, y, h) -> eax the x left of them: the item's actions callback
item_actions:
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call place_at
    test rax, rax
    jz 8f
    mov rcx, [rax + PL_ops]
    mov rcx, [rcx + PLO_actions]
    test rcx, rcx
    jz 8f
    mov rdi, [rax + PL_ctx]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov rax, [rax + PL_ops]
    call [rax + PLO_actions]
    EPILOGUE
8:  mov eax, r12d
    EPILOGUE

# places_panel_count() -> eax the panel's view tabs shown
FN places_panel_count
    mov edi, PLACE_PANEL
    lea rsi, [rip + order]
    jmp place_list

# places_panel_nth(n) -> eax the id of the panel's n-th view tab (after places_panel_count)
FN places_panel_nth
    lea rax, [rip + order]
    mov eax, [rax + rdi*4]
    ret

# places_panel_index() -> eax the chosen view tab's place among them, or -1
FN places_panel_index
    push rbx
    mov edi, PLACE_PANEL
    lea rsi, [rip + order]
    call place_list
    mov ecx, eax
    xor eax, eax
    mov edx, [rip + g_panel_cur]
1:  cmp eax, ecx
    jae 2f
    lea r8, [rip + order]
    cmp [r8 + rax*4], edx
    je 3f
    inc eax
    jmp 1b
2:  mov eax, -1
3:  pop rbx
    ret

# cmd_toggle_panel(): the panel shows with its last tab (a view tab starts no shell) or hides
FN cmd_toggle_panel
    cmp dword ptr [rip + g_term_open], 0
    je 2f
    mov dword ptr [rip + g_term_open], 0
    cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    je 1f
    call place_focused
    mov edi, eax
    call place_at
    test rax, rax
    jz 9f
    cmp dword ptr [rax + PL_place], PLACE_PANEL
    jne 9f
1:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  mov dword ptr [rip + g_dirty], 1
    ret
2:  mov edi, [rip + g_panel_cur]
    call place_at
    test rax, rax
    jz term_show
    mov edi, [rip + g_panel_cur]
    mov esi, 1
    jmp place_show

# ---------------- the right column ----------------

# side_draw(x, y, w, h): the agents panel; with side tabs a strip over it chooses between the agents
#   panel and them
FN side_draw
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov edi, PLACE_SIDE
    lea rsi, [rip + sd_order]
    call place_list
    mov [rsp + 16], eax
    test eax, eax
    jnz 1f
    mov dword ptr [rip + g_side_cur], -1
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call agents_draw
    EPILOGUE
1:  mov edi, [rip + g_side_cur]
    call place_at
    test rax, rax
    jz 11f
    test dword ptr [rax + PL_flags], PLF_HIDDEN
    jz 12f
11: mov dword ptr [rip + g_side_cur], -1
12: mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    M ecx, MI_28
    COLOR r8d, T_PANEL
    call gfx_fill
    mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 20], eax         # x
    # the agents panel's tab, then the side tabs
    mov r12d, -1
.Lsdt_tab:
    lea rbx, [rip + .Lagents]
    mov r14d, ID_SD_AGENTS
    cmp r12d, -1
    je 2f
    lea rax, [rip + sd_order]
    mov edi, [rax + r12*4]
    lea r14d, [rdi + ID_SD_TAB]
    call place_at
    mov rbx, [rax + PL_title]
2:  mov rdi, rbx
    call strlen
    mov r15, rax
    lea rdi, [rip + g_face_small]
    mov rsi, rbx
    mov rdx, r15
    call text_width
    mov r13d, eax
    mov edi, 160
    call sc
    cmp r13d, eax
    cmovg r13d, eax
    add r13d, [rip + g_mt + 4*MI_20]
    mov eax, [rsp + 20]
    add eax, r13d
    mov ecx, [rsp]
    add ecx, [rsp + 8]
    cmp eax, ecx
    jg .Lsdt_done
    mov edi, r14d
    mov esi, [rsp + 20]
    mov edx, [rsp + 4]
    mov ecx, r13d
    M r8d, MI_28
    call ui_btn
    mov [rsp + 24], eax
    test eax, UB_PRESS
    jz 3f
    cmp r12d, -1
    jne 21f
    mov dword ptr [rip + g_side_cur], -1
    mov dword ptr [rip + g_focus], FOCUS_AGENTS
    jmp 3f
21: lea rax, [rip + sd_order]
    mov edi, [rax + r12*4]
    mov esi, 1
    call place_show
3:  COLOR r9d, T_MUTED
    mov eax, -1
    cmp r12d, -1
    je 31f
    lea rax, [rip + sd_order]
    mov eax, [rax + r12*4]
31: cmp eax, [rip + g_side_cur]
    jne 4f
    COLOR r9d, T_FG
    push r9
    push r9
    mov edi, [rsp + 16 + 20]
    mov esi, [rsp + 16 + 4]
    add esi, [rip + g_mt + 4*MI_28]
    sub esi, [rip + g_mt + 4*MI_2]
    mov edx, r13d
    M ecx, MI_2
    COLOR r8d, T_ACCENT
    call gfx_fill
    pop r9
    pop r9
    jmp 5f
4:  test dword ptr [rsp + 24], UB_HOVER
    jz 5f
    COLOR r9d, T_FG
5:  mov eax, r9d
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 20]
    add esi, [rip + g_mt + 4*MI_10]
    mov edx, [rsp + 16 + 4]
    M ecx, MI_28
    mov r8, rbx
    mov r9, r15
    call ui_text_v
    add rsp, 16
    add [rsp + 20], r13d
    inc r12d
    cmp r12d, [rsp + 16]
    jb .Lsdt_tab
.Lsdt_done:
    cmp dword ptr [rip + g_side_cur], -1
    je 51f
    mov edi, [rip + g_side_cur] # the side view's title actions at the strip's right
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 4]
    M ecx, MI_28
    call item_actions
51: M eax, MI_28
    mov edx, [rsp + 4]
    add edx, eax                # the body under the strip
    mov r8d, [rsp + 12]
    sub r8d, eax
    xor eax, eax
    test r8d, r8d
    cmovs r8d, eax
    cmp dword ptr [rip + g_side_cur], -1
    jne 6f
    mov edi, [rsp]
    mov esi, edx
    mov edx, [rsp + 8]
    mov ecx, r8d
    call agents_draw
    EPILOGUE
6:  mov edi, [rip + g_side_cur]
    mov esi, [rsp]
    mov ecx, [rsp + 8]
    call place_body
    EPILOGUE

# cmd_toggle_side(): the right column on its last side tab, or hidden when it shows one
FN cmd_toggle_side
    cmp dword ptr [rip + g_show_agents], 0
    je 1f
    cmp dword ptr [rip + g_side_cur], -1
    je 1f
    mov dword ptr [rip + g_show_agents], 0
    mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rip + g_focus], FOCUS_VIEW   # a hidden view gives the keyboard back
    jne 9f
    call place_focused
    mov edi, eax
    call place_at
    test rax, rax
    jz 9f
    cmp dword ptr [rax + PL_place], PLACE_SIDE
    jne 9f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    ret
1:  mov edi, [rip + g_side_cur]
    call place_at
    test rax, rax
    jnz 2f
    mov edi, PLACE_SIDE
    lea rsi, [rip + order]
    call place_list
    test eax, eax
    jz 9f
    mov eax, [rip + order]
    mov [rip + g_side_cur], eax
2:  mov edi, [rip + g_side_cur]
    mov esi, 1
    jmp place_show
9:  ret

# ---------------- tests ----------------

# place_find(ptr, len) -> eax the id of the item with that name, or -1
FN place_find
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp ebx, PL_MAX
    jae 8f
    mov edi, ebx
    call place_at
    test rax, rax
    jz 2f
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rax + PL_name]
    call str_eq_cstr
    test eax, eax
    jnz 3f
2:  inc ebx
    jmp 1b
3:  mov eax, ebx
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# place_dump(sb, place): a line per item of the place in order:
#   "NAME title=T flags at=X,Y size=WxH [collapsed] [hidden] [chosen] [focus] badge=N"
FN place_dump
    PROLOGUE
    mov rbx, rdi
    mov r15d, esi
    xor r12d, r12d
1:  cmp r12d, PL_MAX
    jae 9f
    # in registration order, hidden ones too: a pass per seq would be slow; slots are few
    mov edi, r12d
    call place_at
    test rax, rax
    jz 8f
    cmp [rax + PL_place], r15d
    jne 8f
    mov r13, rax
    mov rdi, rbx
    mov rsi, [r13 + PL_name]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_title]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + PL_title]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + PL_x]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r13 + PL_y]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_size]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + PL_w]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 'x'
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r13 + PL_h]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_badge]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + PL_badge]
    call sb_push_u64
    test dword ptr [r13 + PL_flags], PLF_COLLAPSED
    jz 2f
    mov rdi, rbx
    lea rsi, [rip + .Ld_collapsed]
    call sb_push_cstr
2:  test dword ptr [r13 + PL_flags], PLF_HIDDEN
    jz 3f
    mov rdi, rbx
    lea rsi, [rip + .Ld_hidden]
    call sb_push_cstr
3:  test dword ptr [r13 + PL_flags], PLF_VISIBLE
    jz 4f
    mov rdi, rbx
    lea rsi, [rip + .Ld_visible]
    call sb_push_cstr
4:  cmp r15d, PLACE_PANEL
    jne 41f
    cmp r12d, [rip + g_panel_cur]
    jne 5f
    mov rdi, rbx
    lea rsi, [rip + .Ld_chosen]
    call sb_push_cstr
    jmp 5f
41: cmp r15d, PLACE_SIDE
    jne 5f
    cmp r12d, [rip + g_side_cur]
    jne 5f
    mov rdi, rbx
    lea rsi, [rip + .Ld_chosen]
    call sb_push_cstr
5:  call place_focused
    cmp eax, r12d
    jne 6f
    mov rdi, rbx
    lea rsi, [rip + .Ld_focus]
    call sb_push_cstr
6:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    cmp r15d, PLACE_PANEL       # a panel tab drawn in the strip: "tab NAME x=X w=W"
    jne 8f
    cmp dword ptr [rip + g_term_open], 0
    je 8f
    cmp dword ptr [r13 + PL_pad], 0
    je 8f
    mov rdi, rbx
    lea rsi, [rip + .Ld_tab]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + PL_name]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_x]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + PL_pad]
    dec esi
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_w]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + PL_hy]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
8:  inc r12d
    jmp 1b
9:  EPILOGUE

.section .rodata
.Ld_tab: .asciz "tab "
.Ld_x: .asciz " x="
.Ld_w: .asciz " w="
.Lbusy: .asciz "\342\200\246"
.Lagents: .asciz "Agents"
.Ld_title: .asciz " title="
.Ld_at: .asciz " at="
.Ld_size: .asciz " size="
.Ld_badge: .asciz " badge="
.Ld_collapsed: .asciz " collapsed"
.Ld_hidden: .asciz " hidden"
.Ld_visible: .asciz " visible"
.Ld_chosen: .asciz " chosen"
.Ld_focus: .asciz " focus"
.text

# panel_view_focused() -> eax 1 when the keyboard is in one of the panel's view tabs
FN panel_view_focused
    call place_focused
    mov edi, eax
    call place_at
    test rax, rax
    jz 1f
    cmp dword ptr [rax + PL_place], PLACE_PANEL
    jne 1f
    mov eax, 1
    ret
1:  xor eax, eax
    ret

# views_timeout() -> ms until something of the views group is due (a wait for children times out),
#   or -1
FN views_timeout
    jmp rview_timeout

# views_tick(): what is due
FN views_tick
    jmp rview_tick

# places_init(): the explorer, the sidebar's first section
FN places_init
    PROLOGUE
    mov edi, PLACE_SIDEBAR
    lea rsi, [rip + .Lexp_name]
    lea rdx, [rip + .Lexp_title]
    lea rcx, [rip + explorer_ops]
    xor r8d, r8d
    call place_add
    mov [rip + g_explorer_place], eax
    EPILOGUE

.section .rodata
.Lexp_name: .asciz "explorer"
.Lexp_title: .asciz "Explorer"
.p2align 3
explorer_ops:
    .quad explorer_body_draw, 0, 0, 0, explorer_actions, 0
