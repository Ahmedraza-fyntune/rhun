# the Extensions page (a tab, like chrome://extensions): a card per extension with its On/Off
# switch, Details and Remove; the details show what it may do in plain words, the pin, its
# commands and its own settings ([settings] in its manifest), and Remove.
.include "rhun.inc"
.equ ID_XP, 0x7100              # + 0x00 install, 0x01 back, 0x02 pin, 0x03 remove, 0x04 restart,
                                #   0x10 + i*4 + k: a card's toggle, details, remove, restart
.equ ID_XS, 0x7300              # + i*8 + k: a setting's controls (choice options k..)
.equ ID_XM, 0x5a0000            # extension management: + 1 check, + 2 update all, + 3 update,
                                #   + 4 what's new, + 5 roll back, + 6 search, + 7 installed,
                                #   + 8 browse, + 9 refresh; + 0x1000 + i: a card's Update;
                                #   + 0x2000 + i: a Browse card's button
.equ XB_SHOWN, 100              # Browse cards drawn (the search narrows the rest)

.bss
.p2align 3
.globl g_xp_detail
g_xp_detail: .quad 0            # the extension whose details are shown, or 0 for the list
xp_scroll: .long 0
xp_content_h: .long 0
xp_x: .long 0                   # the column
xp_w: .long 0
xp_y: .long 0                   # the running y
xp_bx: .long 0                  # a row of buttons: the next x
xp_prompt_sd: .quad 0           # the text setting being edited
xp_line: .zero SB_SIZE
xp_buf: .zero 256

.text

# cmd_extensions(): the Extensions page, in its tab (focused if it is open)
FN cmd_extensions
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 2f
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_EXT
    je 3f
    inc rbx
    jmp 1b
2:  mov dword ptr [rip + xp_scroll], 0
    xor edi, edi
    mov esi, TAB_EXT
    call app_add_tab
    jmp 9f
3:  mov rdi, rbx
    call app_activate_tab
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# extpage_show(ext): the page with that extension's details (0: the list)
FN extpage_show
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rip + xp_prompt_sd], 0
    test rbx, rbx
    jz 1f
    call ext_is_visible
    test eax, eax
    jnz 1f
    xor ebx, ebx
1:  mov [rip + g_xp_detail], rbx
    mov dword ptr [rip + xp_scroll], 0
    call cmd_extensions
    EPILOGUE

# extpage_forget(): the extension shown in detail was removed: back to the list
FN extpage_forget
    push rbx
    mov rdi, [rip + g_xp_detail]
    test rdi, rdi
    jz 1f
    call ext_is_visible
    test eax, eax
    jnz 1f
    mov qword ptr [rip + g_xp_detail], 0
    mov qword ptr [rip + xp_prompt_sd], 0
    mov dword ptr [rip + xp_scroll], 0
1:  pop rbx
    ret

# extpage_draw(x, y, w, h)
FN extpage_draw
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    call extres_page_seen       # resources group: CPU and memory are sampled while it shows
    call extpage_forget
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_BG
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    # the wheel scrolls; the scroll stays within the content
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    mov eax, [rip + g_scroll_y]
    add [rip + xp_scroll], eax
1:  mov eax, [rip + xp_content_h]
    sub eax, [rsp + 12]
    jns 2f
    xor eax, eax
2:  cmp [rip + xp_scroll], eax
    jle 3f
    mov [rip + xp_scroll], eax
3:  cmp dword ptr [rip + xp_scroll], 0
    jge 4f
    mov dword ptr [rip + xp_scroll], 0
4:  # the column: 720 wide at most, centered
    mov edi, 720
    call sc
    mov ecx, [rsp + 8]
    sub ecx, [rip + g_mt + 4*MI_32]
    sub ecx, [rip + g_mt + 4*MI_32]
    cmp eax, ecx
    cmovg eax, ecx
    mov ecx, 1
    cmp eax, ecx
    cmovl eax, ecx
    mov [rip + xp_w], eax
    mov ecx, [rsp + 8]
    sub ecx, eax
    sar ecx, 1
    add ecx, [rsp]
    mov [rip + xp_x], ecx
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_32]
    sub eax, [rip + xp_scroll]
    mov [rip + xp_y], eax
    mov [rsp + 16], eax         # the top, for the content's height
    mov rax, [rip + g_xp_detail]
    test rax, rax
    jz 5f
    call draw_detail
    jmp 6f
5:  call draw_list
6:  mov eax, [rip + xp_y]
    add eax, [rip + g_mt + 4*MI_48]
    sub eax, [rsp + 16]
    mov [rip + xp_content_h], eax
    call gfx_clip_pop
    EPILOGUE

# ---------------- the list ----------------

draw_list:
    PROLOGUE 16
    # "Extensions", and on the right Check for updates and the Install menu
    lea rdi, [rip + g_face_big]
    mov esi, [rip + xp_x]
    mov edx, [rip + xp_y]
    M ecx, MI_40
    lea r8, [rip + .Lt_title]
    COLOR r9d, T_FG
    call ui_text_c
    lea rdi, [rip + .Lb_install]
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    mov [rsp], esi              # the Install button's x
    mov edx, [rip + xp_y]
    M eax, MI_40
    sub eax, [rip + g_mt + 4*MI_32]
    sar eax, 1
    add edx, eax
    mov [rsp + 4], edx          # the buttons' y
    mov edi, ID_XP
    lea rcx, [rip + .Lb_install]
    mov r8d, 1                  # the accent
    call button
    test eax, UB_CLICK
    jz 1f
    lea rdi, [rip + install_items]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    add edx, [rip + g_mt + 4*MI_32]
    call ctx_menu_open
1:  lea rdi, [rip + .Lb_check]
    call label_width
    mov esi, [rsp]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_6]
    mov edi, ID_XM + 1
    mov edx, [rsp + 4]
    lea rcx, [rip + .Lb_check]
    xor r8d, r8d
    call button
    test eax, UB_CLICK
    jz 11f
    call cmd_check_extensions
11: M eax, MI_40
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Lt_intro]
    COLOR edx, T_MUTED
    mov ecx, MI_28
    call line_text
    M eax, MI_16
    add [rip + xp_y], eax
    call draw_switch            # extension management: Installed | Browse
    cmp dword ptr [rip + g_xp_browse], 0
    je 12f
    call draw_browse
    EPILOGUE
12: call draw_updates
    # the cards
    xor r13d, r13d              # visible ones drawn
    xor r12d, r12d
2:  cmp r12, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 2b
    inc r13d
    lea edi, [r12 - 1]
    call draw_card
    jmp 2b
8:  test r13d, r13d
    jnz 9f
    M eax, MI_16
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lt_none]
    COLOR edx, T_MUTED
    mov ecx, MI_28
    call line_text
9:  EPILOGUE

# draw_card(index): rbx the EXT
draw_card:
    PROLOGUE 48
    mov r15d, edi
    mov [rsp + 40], edi         # its index
    shl r15d, 2
    add r15d, ID_XP + 0x10      # this card's ids
    # its height: 28 badge row, 24 description, a problem line, 32 buttons, padding
    M eax, MI_16
    mov r12d, eax               # padding
    M r13d, MI_28
    add r13d, [rip + g_mt + 4*MI_4]     # under the description's lines (counted below)
    add r13d, [rip + g_mt + 4*MI_32]
    add r13d, [rip + g_mt + 4*MI_8]
    add r13d, r12d
    add r13d, r12d
    mov rdi, rbx
    call ext_problem
    mov [rsp], rax
    test rax, rax
    jz 1f
    add r13d, [rip + g_mt + 4*MI_24]
1:  # a description longer than the card is wide takes more lines
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + EXT_desc]
    test rsi, rsi
    jnz 11f
    lea rsi, [rip + .Lt_no_desc]
11: mov edx, [rip + xp_x]
    add edx, r12d
    call para_lines
    imul eax, [rip + g_mt + 4*MI_20]
    add r13d, eax
    mov eax, [rip + xp_y]
    mov [rsp + 8], eax          # the card's top
    mov edi, [rip + xp_x]
    mov esi, eax
    mov edx, [rip + xp_w]
    mov ecx, r13d
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    COLOR eax, T_PANEL
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    # badge, title, version
    mov eax, [rip + xp_x]
    add eax, r12d
    mov [rsp + 12], eax         # the inner x
    mov edi, eax
    mov esi, [rsp + 8]
    add esi, r12d
    M edx, MI_28
    mov rcx, rbx
    call badge
    mov rdi, rbx
    call ext_title
    mov r8, rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 12]
    add esi, [rip + g_mt + 4*MI_28]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 8]
    add edx, r12d
    M ecx, MI_28
    COLOR r9d, T_FG
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_12]
    mov esi, eax
    lea rdi, [rip + g_face_small]
    mov edx, [rsp + 8]
    add edx, r12d
    M ecx, MI_28
    mov r8, [rbx + EXT_version]
    test r8, r8
    jnz 2f
    lea r8, [rip + .Lempty]
2:  COLOR r9d, T_MUTED
    call ui_text_c
    # the switch on the right
    mov edi, r15d
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, r12d
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rsp + 8]
    add edx, r12d
    add edx, [rip + g_mt + 4*MI_4]
    mov ecx, [rbx + EXT_disabled]
    xor ecx, 1
    call ui_toggle
    test eax, eax
    jz 3f
    mov rdi, rbx
    mov esi, [rbx + EXT_disabled]
    xor esi, 1
    call ext_set_disabled
3:  # the description
    mov eax, [rsp + 8]
    add eax, r12d
    add eax, [rip + g_mt + 4*MI_28]
    mov [rip + xp_y], eax
    mov eax, [rsp + 12]
    mov [rsp + 16], eax
    mov rsi, [rbx + EXT_desc]
    test rsi, rsi
    jnz 4f
    lea rsi, [rip + .Lt_no_desc]
4:  lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_20
    mov r8d, [rsp + 12]
    call para
    mov eax, [rip + g_mt + 4*MI_4]
    add [rip + xp_y], eax
    # a problem, in red
    mov rsi, [rsp]
    test rsi, rsi
    jz 5f
    lea rdi, [rip + g_face_small]
    COLOR edx, T_ERROR
    mov ecx, MI_24
    mov r8d, [rsp + 12]
    call text_at
5:  # Details, Remove, and Restart after a problem
    M eax, MI_8
    add [rip + xp_y], eax
    mov eax, [rsp + 12]
    mov [rip + xp_bx], eax
    lea edi, [r15 + 1]
    lea rsi, [rip + .Lb_details]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 6f
    mov [rip + g_xp_detail], rbx
    mov dword ptr [rip + xp_scroll], 0
    mov dword ptr [rip + g_dirty], 1
6:  lea edi, [r15 + 2]
    lea rsi, [rip + .Lb_remove]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 7f
    mov rdi, rbx
    call ext_remove_ask
7:  cmp qword ptr [rsp], 0
    je 71f
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 71f
    lea edi, [r15 + 3]
    lea rsi, [rip + .Lb_restart]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 71f
    mov rdi, rbx
    call ext_restart_now
71: # extension management: Update to 0.1.2
    mov rdi, rbx
    call update_label
    test rax, rax
    jz 8f
    mov edi, [rsp + 40]
    add edi, ID_XM + 0x1000
    mov rsi, rax
    mov edx, 1
    call row_button
    test eax, UB_CLICK
    jz 8f
    mov rdi, rbx
    call extupdate_update
8:  # resources group: memory and CPU while it runs (extres.s), at the right of the buttons
    lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call extres_card_cost
    test eax, eax
    jz 81f
    call line_cstr
    mov r14, rax
    mov rdi, rax
    call label_width_small
    mov r8d, [rip + xp_x]
    add r8d, [rip + xp_w]
    sub r8d, r12d
    sub r8d, eax
    lea rdi, [rip + g_face_small]
    mov rsi, r14
    COLOR edx, T_MUTED
    mov ecx, MI_32
    call text_at_keep
81: mov eax, [rsp + 8]
    add eax, r13d
    add eax, [rip + g_mt + 4*MI_12]
    mov [rip + xp_y], eax
    EPILOGUE

# ---------------- the details ----------------

draw_detail:
    PROLOGUE 32
    mov rbx, [rip + g_xp_detail]
    # "← Extensions"
    lea rdi, [rip + .Lt_title]
    call label_width
    add eax, [rip + g_mt + 4*MI_28]
    mov r12d, eax
    mov edi, ID_XP + 1
    mov esi, [rip + xp_x]
    mov edx, [rip + xp_y]
    mov ecx, r12d
    M r8d, MI_28
    call ui_btn
    mov [rsp], eax
    mov edi, [rip + xp_x]
    mov esi, [rip + xp_y]
    M edx, MI_20
    M ecx, MI_28
    mov r8d, IC_BACK
    COLOR r9d, T_ACCENT
    call draw_icon
    lea rdi, [rip + g_face_ui]
    mov esi, [rip + xp_x]
    add esi, [rip + g_mt + 4*MI_24]
    mov edx, [rip + xp_y]
    M ecx, MI_28
    lea r8, [rip + .Lt_title]
    COLOR r9d, T_ACCENT
    call ui_text_c
    test dword ptr [rsp], UB_CLICK
    jz 1f
    mov qword ptr [rip + g_xp_detail], 0
    mov dword ptr [rip + xp_scroll], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
1:  M eax, MI_40
    add [rip + xp_y], eax
    # badge, title, switch
    mov edi, [rip + xp_x]
    mov esi, [rip + xp_y]
    M edx, MI_40
    mov rcx, rbx
    call badge
    mov rdi, rbx
    call ext_title
    mov r8, rax
    lea rdi, [rip + g_face_big]
    mov esi, [rip + xp_x]
    add esi, [rip + g_mt + 4*MI_40]
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, [rip + xp_y]
    M ecx, MI_40
    COLOR r9d, T_FG
    call ui_text_c
    mov edi, ID_XP + 5
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rip + xp_y]
    add edx, [rip + g_mt + 4*MI_8]
    mov ecx, [rbx + EXT_disabled]
    xor ecx, 1
    call ui_toggle
    test eax, eax
    jz 2f
    mov rdi, rbx
    mov esi, [rbx + EXT_disabled]
    xor esi, 1
    call ext_set_disabled
2:  M eax, MI_48
    add [rip + xp_y], eax
    # "Version V · by OWNER · github.com/OWNER/NAME"
    lea rdi, [rip + xp_line]
    call sb_clear
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_version]
    call sb_push_cstr
    mov rsi, [rbx + EXT_version]
    test rsi, rsi
    jz 3f
    lea rdi, [rip + xp_line]
    call sb_push_cstr
3:  mov rdi, rbx
    call push_source            # extension management: where it came from, an update
    call line_cstr
    mov rsi, rax
    lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    mov rsi, [rbx + EXT_desc]
    test rsi, rsi
    jz 4f
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_FG
    mov ecx, MI_24
    mov r8d, [rip + xp_x]
    call para
    mov eax, [rip + g_mt + 4*MI_4]
    add [rip + xp_y], eax
4:  # a problem, with Restart
    mov rdi, rbx
    call ext_problem
    test rax, rax
    jz 5f
    mov rsi, rax
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_ERROR
    mov ecx, MI_28
    call line_text
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 5f
    mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    mov edi, ID_XP + 4
    lea rsi, [rip + .Lb_restart]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 41f
    mov rdi, rbx
    call ext_restart_now
41: M eax, MI_8
    add [rip + xp_y], eax
5:  mov rdi, rbx
    call draw_versions          # extension management: Update, What's new, Roll back
    test eax, eax
    jz 51f
    EPILOGUE                    # it rolled back: the record shown changed
51:
    # resources group: how it runs and what it costs (extres.s)
    lea rsi, [rip + .Ls_resources]
    call section
    xor r12d, r12d
55: lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rip + xp_line]
    call extres_page_line
    test eax, eax
    jz 57f
    call line_cstr
    mov rsi, rax
    lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    inc r12d
    jmp 55b
57: # what it may do
    lea rsi, [rip + .Ls_permissions]
    call section
    mov rdi, rbx
    call draw_permissions
    mov rdi, rbx
    call draw_run_allowed
    mov rdi, rbx
    call draw_pack              # extension management: a pack's members
    test eax, eax
    jz 53f
    EPILOGUE                    # a member's button changed the records
53:
    # wsedit: the user's standing permission to change project files (workspace edits), with a
    # switch that takes it back
    cmp dword ptr [rbx + EXT_edits], 0
    je 51f
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lt_edits]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov edi, ID_XP + 6
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rip + xp_y]
    add edx, [rip + g_mt + 4*MI_4]
    mov ecx, 1
    call ui_toggle
    test eax, eax
    jz 52f
    mov rdi, rbx
    xor esi, esi
    call ext_set_edits
52: M eax, MI_28
    add [rip + xp_y], eax
51:
    mov rdi, rbx                # resources group: its passwords and tokens (extpageres.inc)
    call draw_res_secrets
    mov rdi, rbx                # and its links
    call draw_res_links
    # the pin
    lea rsi, [rip + .Ls_toolbar]
    call section
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lt_pin]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov edi, ID_XP + 2
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rip + xp_y]
    add edx, [rip + g_mt + 4*MI_4]
    mov ecx, [rbx + EXT_pinned]
    call ui_toggle
    test eax, eax
    jz 6f
    mov rdi, rbx
    mov esi, [rbx + EXT_pinned]
    xor esi, 1
    call ext_set_pinned
6:  M eax, MI_28
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Lt_pin_desc]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    # its commands
    mov rdi, rbx
    call draw_commands
    # the language features it provides, with the session's numbers (query.s)
    mov rdi, rbx
    call draw_langfeat
    # its own settings
    cmp qword ptr [rbx + EXT_sdefs + VEC_len], 0
    je 7f
    lea rsi, [rip + .Ls_settings]
    call section
    mov rdi, rbx
    call draw_settings
7:  # Remove
    M eax, MI_24
    add [rip + xp_y], eax
    mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    mov edi, ID_XP + 3
    lea rsi, [rip + .Lb_remove_ext]
    mov edx, 2                  # in red
    call row_button
    test eax, UB_CLICK
    jz 8f
    mov rdi, rbx
    call ext_remove_ask
8:  M eax, MI_32
    add [rip + xp_y], eax
    EPILOGUE

# draw_permissions(ext): ext_needs_words split at ", " into a line each, then how rhun holds it
draw_permissions:
    PROLOGUE 16
    mov rbx, rdi
    lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call ext_needs_words
    call line_cstr
    mov r12, rax
1:  cmp byte ptr [r12], 0
    je 5f
    # up to ", " or the end
    xor ecx, ecx
2:  cmp byte ptr [r12 + rcx], 0
    je 3f
    cmp byte ptr [r12 + rcx], ','
    jne 21f
    cmp byte ptr [r12 + rcx + 1], ' '
    je 3f
21: inc rcx
    jmp 2b
3:  mov r13, rcx
    mov al, [r12 + rcx]
    mov [rsp], al
    mov byte ptr [r12 + rcx], 0
    # "•  Capital first"
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lbullet]
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    mov rcx, 200
    call cstr_copy_cap
    lea rsi, [rip + xp_buf]
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_FG
    mov ecx, MI_28
    call line_text
    mov al, [rsp]
    mov [r12 + r13], al
    lea r12, [r12 + r13]
    cmp byte ptr [r12], 0
    je 5f
    add r12, 2
    jmp 1b
5:  # rhun holds it to them, or says it cannot here
    lea rsi, [rip + .Lt_held]
.ifdef WINDOWS
    lea rsi, [rip + .Lt_windows]
.endif
    cmp qword ptr [rbx + EXT_confine_why], 0
    je 6f
    lea rsi, [rip + .Lt_not_held]
6:  cmp dword ptr [rbx + EXT_wasm_run], 0      # WebAssembly: its host holds it everywhere (extwasm.s)
    je 7f
    lea rsi, [rip + .Lt_wasm]
7:  lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    EPILOGUE

# draw_run_allowed(ext): the projects it may run programs in as you (runallow.s), with Forget
draw_run_allowed:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + xp_line]
    call sb_clear
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_runs_in]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call run_allow_projects
    test eax, eax
    jz 9f
    call line_cstr
    mov rsi, rax
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_FG
    mov ecx, MI_28
    call line_text
    mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    mov edi, ID_XP + 0x0e
    lea rsi, [rip + .Lb_forget]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 1f
    mov rdi, rbx
    call run_forget
1:  M eax, MI_40
    add [rip + xp_y], eax
9:  EPILOGUE

# cstr_copy_cap(dst, src, max): src with its first letter upper case, at most max bytes
cstr_copy_cap:
    xor edx, edx
1:  cmp rdx, rcx
    jae 2f
    mov al, [rsi + rdx]
    test al, al
    jz 2f
    test edx, edx
    jnz 11f
    cmp al, 'a'
    jb 11f
    cmp al, 'z'
    ja 11f
    sub al, 32
11: mov [rdi + rdx], al
    inc rdx
    jmp 1b
2:  mov byte ptr [rdi + rdx], 0
    ret

# draw_commands(ext): "Commands": each title and its keys
draw_commands:
    PROLOGUE 16
    mov rbx, rdi
    mov rax, rbx
    lea rcx, [rip + g_exts]
    sub rax, [rcx + VEC_ptr]
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    mov r14, rax                # its index
    xor r13d, r13d              # shown
    xor r12d, r12d
1:  cmp r12, [rip + g_ext_cmds + VEC_len]
    jae 8f
    mov rax, [rip + g_ext_owner + VEC_ptr]
    cmp [rax + r12*8], r14
    jne 7f
    test r13d, r13d
    jnz 2f
    lea rsi, [rip + .Ls_commands]
    call section
2:  inc r13d
    imul r15, r12, CMD_SIZE
    add r15, [rip + g_ext_cmds + VEC_ptr]
    # the title without " (Extension)"
    mov rsi, [r15 + CMD_title]
    lea rdi, [rip + xp_buf]
    call copy_title
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + xp_buf]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov rdi, r15
    call keys_for
    test rax, rax
    jz 3f
    mov [rsp], rax
    mov rdi, rax
    call label_width_small
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    lea rdi, [rip + g_face_small]
    mov edx, [rip + xp_y]
    M ecx, MI_28
    mov r8, [rsp]
    COLOR r9d, T_MUTED
    call ui_text_c
3:  M eax, MI_28
    add [rip + xp_y], eax
7:  inc r12
    jmp 1b
8:  EPILOGUE

# draw_langfeat(ext): "Language features": each kind it provides, its file patterns in force and
# its numbers this session, in the warning color when slow or failing (query.s)
draw_langfeat:
    PROLOGUE 16
    mov rbx, rdi
    xor r12d, r12d              # the kind
    xor r13d, r13d              # rows shown
1:  cmp r12d, PK_COUNT
    jae 9f
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rip + xp_line]
    call query_kind_label
    test eax, eax
    jz 7f
    test r13d, r13d
    jnz 2f
    lea rsi, [rip + .Ls_langfeat]
    call section
2:  inc r13d
    lea rdi, [rip + g_face_ui]
    mov rsi, [rip + xp_line + SB_ptr]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rip + xp_line]
    call query_kind_numbers
    mov rdi, [rip + xp_line + SB_ptr]
    call label_width_small
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    mov [rsp], esi
    mov rdi, rbx
    mov esi, r12d
    call query_kind_warn
    COLOR r9d, T_MUTED
    test eax, eax
    jz 3f
    COLOR r9d, T_WARNING
3:  mov esi, [rsp]
    lea rdi, [rip + g_face_small]
    mov edx, [rip + xp_y]
    M ecx, MI_28
    mov r8, [rip + xp_line + SB_ptr]
    call ui_text_c
    M eax, MI_28
    add [rip + xp_y], eax
7:  inc r12d
    jmp 1b
9:  EPILOGUE

# copy_title(dst, title): up to the last " (" (the extension's name that the palette adds)
copy_title:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    push rsi
    call strlen
    pop rsi
    mov rcx, rax
1:  cmp rcx, 2
    jb 2f
    cmp byte ptr [rsi + rcx - 2], ' '
    jne 11f
    cmp byte ptr [rsi + rcx - 1], '('
    je 3f
11: dec rcx
    jmp 1b
2:  mov rcx, rax                # no suffix: the whole title
    jmp 4f
3:  sub rcx, 2
4:  cmp rcx, 60
    jbe 5f
    mov ecx, 60
5:  mov rdi, rbx
    mov rdx, rcx
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    mov byte ptr [rbx + rdx], 0
    pop rbx
    ret

# draw_settings(ext): a row per setting: its title and description, its control on the right
draw_settings:
    PROLOGUE 48
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + EXT_sdefs + VEC_len]
    jae 9f
    imul r13, r12, SD_SIZE
    add r13, [rbx + EXT_sdefs + VEC_ptr]
    mov r15d, r12d
    shl r15d, 3
    add r15d, ID_XS             # this row's ids
    inc r12
    mov eax, [rip + xp_y]
    mov [rsp], eax              # the row's top
    # the title (or the key) and the description under it
    mov rsi, [r13 + SD_title]
    test rsi, rsi
    jnz 2f
    mov rsi, [r13 + SD_key]
2:  lea rdi, [rip + g_face_ui]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov rsi, [r13 + SD_desc]
    test rsi, rsi
    jz 3f
    M eax, MI_24
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    mov r8d, [rip + xp_x]
    call text_at_keep
    M eax, MI_4
    sub [rip + xp_y], eax
3:  # the control, on the first line's right
    mov eax, [rip + xp_y]
    mov [rsp + 4], eax
    mov eax, [rsp]
    mov [rip + xp_y], eax
    mov eax, [r13 + SD_type]
    cmp eax, SDT_BOOL
    je .Lds_bool
    cmp eax, SDT_INT
    je .Lds_int
    cmp eax, SDT_CHOICE
    je .Lds_choice
    jmp .Lds_string
.Lds_bool:
    mov rdi, [r13 + SD_value]
    lea rsi, [rip + .Lyes]
    call strcmp_eq
    mov [rsp + 8], eax
    mov edi, r15d
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rip + xp_y]
    add edx, [rip + g_mt + 4*MI_4]
    mov ecx, [rsp + 8]
    call ui_toggle
    test eax, eax
    jz .Lds_next
    lea rdx, [rip + .Lyes]
    cmp dword ptr [rsp + 8], 0
    je 4f
    lea rdx, [rip + .Lno]
4:  mov rdi, rbx
    mov rsi, r13
    call ext_setting_set
    jmp .Lds_next
.Lds_int:
    # [-] value [+]
    mov rdi, [r13 + SD_value]
    call strlen
    mov rdi, [r13 + SD_value]
    mov rsi, rax
    call parse_u64
    mov [rsp + 8], eax
    M eax, MI_28
    mov ecx, [rip + xp_x]
    add ecx, [rip + xp_w]
    sub ecx, eax
    mov [rsp + 12], ecx         # the + button's x
    sub ecx, [rip + g_mt + 4*MI_48]
    mov [rsp + 16], ecx         # the value's x
    sub ecx, eax
    mov [rsp + 20], ecx         # the - button's x
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rip + xp_y]
    M ecx, MI_48
    M r8d, MI_28
    mov r9, [r13 + SD_value]
    COLOR eax, T_FG
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    lea edi, [r15 + 1]
    mov esi, [rsp + 20]
    mov edx, IC_MINUS
    call icon_button
    test eax, UB_CLICK
    jz 5f
    mov eax, [rsp + 8]
    dec eax
    jmp 6f
5:  lea edi, [r15 + 2]
    mov esi, [rsp + 12]
    mov edx, IC_PLUS
    call icon_button
    test eax, UB_CLICK
    jz .Lds_next
    mov eax, [rsp + 8]
    inc eax
6:  cmp eax, [r13 + SD_min]
    jge 61f
    mov eax, [r13 + SD_min]
61: cmp eax, [r13 + SD_max]
    jle 62f
    mov eax, [r13 + SD_max]
62: lea rdi, [rip + xp_buf]
    mov esi, eax
    call fmt_u64
    mov byte ptr [rdi], 0
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + xp_buf]
    call ext_setting_set
    jmp .Lds_next
.Lds_choice:
    # the options as a row of buttons, right-aligned; the chosen one highlighted
    mov rdi, r13
    call choice_width
    mov ecx, [rip + xp_x]
    add ecx, [rip + xp_w]
    sub ecx, eax
    mov [rip + xp_bx], ecx
    mov r14, [r13 + SD_opts]
    mov dword ptr [rsp + 8], 0  # the option's number
7:  test r14, r14
    jz .Lds_next
    cmp byte ptr [r14], 0
    je .Lds_next
    mov rdi, r14
    call word_cstr              # the option into xp_buf, r14 after it
    mov r14, rdx
    mov rdi, [r13 + SD_value]
    lea rsi, [rip + xp_buf]
    call strcmp_eq
    mov edx, 3                  # chosen
    test eax, eax
    jnz 71f
    xor edx, edx
71: mov edi, r15d
    add edi, 3
    add edi, [rsp + 8]
    inc dword ptr [rsp + 8]
    lea rsi, [rip + xp_buf]
    call row_button
    test eax, UB_CLICK
    jz 7b
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + xp_buf]
    call ext_setting_set
    jmp 7b
.Lds_string:
    # the value, and Change
    lea rdi, [rip + .Lb_change]
    call label_width
    mov ecx, [rip + xp_x]
    add ecx, [rip + xp_w]
    sub ecx, eax
    mov [rip + xp_bx], ecx
    mov [rsp + 8], ecx
    # the value, right-aligned before the button, at most a third of the column
    mov rdi, [r13 + SD_value]
    call label_width
    mov ecx, [rip + xp_w]
    mov r8d, 3
    push rax
    mov eax, ecx
    xor edx, edx
    div r8d
    mov ecx, eax
    pop rax
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 12], eax
    mov edi, [rsp + 8]
    sub edi, eax
    sub edi, [rip + g_mt + 4*MI_8]
    mov [rsp + 16], edi
    mov esi, [rip + xp_y]
    mov edx, eax
    M ecx, MI_28
    call gfx_clip_push
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rip + xp_y]
    M ecx, MI_28
    mov r8, [r13 + SD_value]
    COLOR r9d, T_MUTED
    call ui_text_c
    call gfx_clip_pop
    mov edi, r15d
    lea rsi, [rip + .Lb_change]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz .Lds_next
    mov rdi, rbx
    mov rsi, r13
    call extpage_setting_prompt_open
.Lds_next:
    # the row ends below its description
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_28]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rip + xp_y], eax
    mov rdi, rbx                # resources group: a workspace's value in force, with Open
    mov rsi, r13
    lea edx, [r12 - 1]
    call draw_res_override
    jmp 1b
9:  EPILOGUE

# One synchronous opening slice. Capture the association only after palette replacement
# has invalidated its predecessor and the exact current row has been revalidated.
FN extpage_setting_prompt_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call setting_prompt_valid
    test rax, rax
    js .Lxpo_done
    mov r13, [r12 + SD_title]
    test r13, r13
    jnz 1f
    mov r13, [r12 + SD_key]
1:  mov rdi, [r12 + SD_value]
    call strlen
    mov rcx, rax
    mov rdi, r13
    mov esi, PROMPT_EXT_SETTING
    mov rdx, [r12 + SD_value]
    call palette_ext_prompt_open
    mov rdi, rbx
    mov rsi, r12
    call setting_prompt_valid
    test rax, rax
    js .Lxpo_refused
    mov [rip + xp_prompt_sd], r12
    xor eax, eax
.Lxpo_done:
    EPILOGUE
.Lxpo_refused:
    mov r13, rax
    call palette_close_extensions_pure
    mov rax, r13
    EPILOGUE

# setting_prompt_valid(ext, sd) -> rax 0 when ext is a record of g_exts that was not removed and sd
# one of its settings, -EINVAL otherwise (the prompt outlived them). Clobbers rax, rcx, rdx.
setting_prompt_valid:
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    test rdx, rdx
    jnz 8f
    cmp rax, [rip + g_exts + VEC_len]
    jae 8f
    cmp dword ptr [rdi + EXT_status], ES_REMOVED
    je 8f
    mov rax, rsi
    sub rax, [rdi + EXT_sdefs + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, SD_SIZE
    div rcx
    test rdx, rdx
    jnz 8f
    cmp rax, [rdi + EXT_sdefs + VEC_len]
    jae 8f
    xor eax, eax
    ret
8:  mov rax, -22
    ret

# extpage_prompt_done(ptr, len): the text setting's new value
FN extpage_prompt_done
    PROLOGUE
    mov r13, rdi
    mov r14, rsi
    mov rbx, [rip + g_xp_detail]
    mov r12, [rip + xp_prompt_sd]
    mov qword ptr [rip + xp_prompt_sd], 0
    mov rdi, rbx
    mov rsi, r12
    call setting_prompt_valid
    test rax, rax
    js 9f
    lea rdi, [rip + xp_line]
    call sb_clear
    lea rdi, [rip + xp_line]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    call line_cstr
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call ext_setting_set
9:  EPILOGUE

# word_cstr(ptr) -> rax xp_buf with the word at ptr (spaces skipped), rdx after it
word_cstr:
1:  cmp byte ptr [rdi], ' '
    jne 2f
    inc rdi
    jmp 1b
2:  xor ecx, ecx
3:  mov al, [rdi + rcx]
    test al, al
    jz 4f
    cmp al, ' '
    je 4f
    cmp ecx, 60
    jae 4f
    lea rdx, [rip + xp_buf]
    mov [rdx + rcx], al
    inc ecx
    jmp 3b
4:  lea rax, [rip + xp_buf]
    mov byte ptr [rax + rcx], 0
    lea rdx, [rdi + rcx]
    ret

# choice_width(sd) -> the width of its row of option buttons
choice_width:
    PROLOGUE
    mov r12, [rdi + SD_opts]
    xor r13d, r13d
    test r12, r12
    jz 9f
1:  cmp byte ptr [r12], 0
    je 9f
    mov rdi, r12
    call word_cstr
    mov r12, rdx
    cmp byte ptr [rax], 0
    je 9f
    mov rdi, rax
    call label_width
    add r13d, eax
    add r13d, [rip + g_mt + 4*MI_6]
    jmp 1b
9:  mov eax, r13d
    EPILOGUE

# ---------------- pieces ----------------

# ext_title(ext) -> its title, or its name
FN ext_title
    PROLOGUE
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz .Lxp_title_empty
    mov rax, [rbx + EXT_title]
    test rax, rax
    jnz .Lxp_title_done
    mov rax, [rbx + EXT_name]
.Lxp_title_done:
    EPILOGUE
.Lxp_title_empty:
    lea rax, [rip + .Lempty]
    EPILOGUE

# ext_problem(ext) -> what is wrong, in words, or 0 (a stop the user asked for is not a problem)
FN ext_problem
    mov eax, [rdi + EXT_status]
    cmp eax, ES_FAILED
    je 1f
    cmp eax, ES_CRASHED
    je 1f
    cmp eax, ES_STOPPED
    je 1f
    xor eax, eax
    ret
1:  mov rax, [rdi + EXT_reason]
    test rax, rax
    jnz 2f
    lea rax, [rip + .Lt_stopped]
2:  ret

# badge(x, y, size, ext): a rounded square in a color of its own with the title's first letter
FN badge
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, rcx
    # its icon, on the manifest's color when it names one
    mov rdi, rbx
    mov esi, r14d
    call ext_icon
    test rax, rax
    jz 4f
    mov [rsp + 8], rax
    mov r9d, [rbx + EXT_color]
    test r9d, r9d
    jz 5f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    shr r8d, 2
    call gfx_round_rect
5:  mov edi, r12d
    mov esi, r13d
    mov rdx, [rsp + 8]
    mov ecx, r14d
    mov r8d, r14d
    call gfx_blit
    EPILOGUE
4:  # no icon: the manifest's color, or one of eight a hash of the name picks, and the letter
    mov r15d, [rbx + EXT_color]
    test r15d, r15d
    jnz 21f
    mov rsi, [rbx + EXT_name]
    xor eax, eax
1:  movzx ecx, byte ptr [rsi]
    test ecx, ecx
    jz 2f
    imul eax, eax, 31
    add eax, ecx
    inc rsi
    jmp 1b
2:  and eax, 7
    lea rcx, [rip + badge_colors]
    mov r15d, [rcx + rax*4]
21: mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    shr r8d, 2
    mov r9d, r15d
    call gfx_round_rect
    # the letter
    mov rdi, rbx
    call ext_title
    movzx eax, byte ptr [rax]
    cmp al, 'a'
    jb 3f
    cmp al, 'z'
    ja 3f
    sub al, 32
3:  mov [rsp], al
    mov byte ptr [rsp + 1], 0
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r14d
    lea r9, [rsp]
    mov eax, 0xffffffff
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    EPILOGUE

# draw_icon(x, y, w, h, icon, argb): an icon centered in the box
draw_icon:
    PROLOGUE
    mov eax, edi
    mov edi, r8d
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov esi, eax
    call ui_icon_center
    EPILOGUE

# section(title cstr in rsi): a gap and a header in the accent color
section:
    PROLOGUE
    M eax, MI_24
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_ACCENT
    mov ecx, MI_28
    call line_text
    M eax, MI_4
    add [rip + xp_y], eax
    EPILOGUE

# line_text(face, cstr, argb, height index): at the column's left, xp_y moves down
line_text:
    mov r8d, [rip + xp_x]
# para(face, cstr, argb, height index, x): the text wrapped at spaces to fit between x and the
# column's right edge less as much as x is in from its left edge (a card's padding), a line each
# at xp_y, which moves down
para:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx              # color
    mov r13d, ecx               # height index
    mov [rsp + 4], r8d          # x
    call para_width
    mov r14d, eax
1:  test r12, r12
    jz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    call wrap_next
    mov r15, rdx                # where the next line starts, or 0
    mov [rsp + 8], rax          # its bytes
    mov edi, [rsp + 4]          # a word wider than the line stays inside it
    mov esi, [rip + xp_y]
    mov edx, r14d
    lea rcx, [rip + g_mt]
    mov ecx, [rcx + r13*4]
    call gfx_clip_push
    mov rdi, rbx
    mov esi, [rsp + 4]
    mov edx, [rip + xp_y]
    lea rcx, [rip + g_mt]
    mov ecx, [rcx + r13*4]
    mov r9, [rsp + 8]
    mov r8, r12
    mov eax, [rsp]
    push rax
    push rax
    call ui_text_v
    add rsp, 16
    call gfx_clip_pop
    lea rax, [rip + g_mt]
    mov eax, [rax + r13*4]
    add [rip + xp_y], eax
    mov r12, r15
    jmp 1b
9:  EPILOGUE

# para_lines(face, cstr, x) -> how many lines para draws the text in (at least 1)
para_lines:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r8d, edx
    call para_width
    mov r14d, eax
    xor r13d, r13d
1:  inc r13d
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    call wrap_next
    mov r12, rdx
    test r12, r12
    jnz 1b
    mov eax, r13d
    EPILOGUE

# para_width(x in r8d) -> eax the width para wraps to: the column less 2 * (x - its left edge)
para_width:
    mov eax, r8d
    sub eax, [rip + xp_x]
    shl eax, 1
    neg eax
    add eax, [rip + xp_w]
    cmp eax, 16
    jge 1f
    mov eax, 16
1:  ret

# wrap_next(face, cstr, width) -> rax the bytes of the first line that fit (whole words; a word
# wider than the line on its own), rdx the next line's start, 0 after the last
wrap_next:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d              # the bytes that fit so far
    xor r15d, r15d              # the next word's start
1:  mov rcx, r15                # its end
2:  movzx eax, byte ptr [r12 + rcx]
    test eax, eax
    jz 3f
    cmp eax, ' '
    je 3f
    inc rcx
    jmp 2b
3:  push rcx
    push rcx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call text_width
    pop rcx
    pop rcx
    cmp eax, r13d
    jle 4f
    test r14, r14
    jnz 5f                      # this word goes to the next line
4:  mov r14, rcx
    cmp byte ptr [r12 + rcx], 0
    je 5f
    lea r15, [rcx + 1]
    cmp eax, r13d
    jle 1b                      # a word wider than the line ends it on its own
5:  # the next line: after the spaces
    mov rdx, r14
6:  cmp byte ptr [r12 + rdx], ' '
    jne 7f
    inc rdx
    jmp 6b
7:  cmp byte ptr [r12 + rdx], 0
    je 8f
    add rdx, r12
    mov rax, r14
    EPILOGUE
8:  xor edx, edx
    mov rax, r14
    EPILOGUE

# text_at(face, cstr, argb, height index, x): at x, clipped to the column; xp_y moves down
text_at:
    PROLOGUE
    mov r12d, ecx
    call text_at_keep
    lea rax, [rip + g_mt]
    mov eax, [rax + r12*4]
    add [rip + xp_y], eax
    EPILOGUE

# text_at_keep(face, cstr, argb, height index, x): as text_at, xp_y stays (r13 the height index)
text_at_keep:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r14d, edx
    mov r13d, ecx
    mov r15d, r8d
    mov edi, r15d
    mov esi, [rip + xp_y]
    mov edx, [rip + xp_x]
    add edx, [rip + xp_w]
    sub edx, r15d
    lea rax, [rip + g_mt]
    mov ecx, [rax + r13*4]
    mov [rsp], ecx
    call gfx_clip_push
    mov rdi, rbx
    mov esi, r15d
    mov edx, [rip + xp_y]
    mov ecx, [rsp]
    mov r8, r12
    mov r9d, r14d
    call ui_text_c
    call gfx_clip_pop
    EPILOGUE

# label_width(cstr) -> its width in the ui face plus a button's padding
label_width:
    PROLOGUE
    mov rbx, rdi
    call strlen
    lea rdi, [rip + g_face_ui]
    mov rsi, rbx
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    EPILOGUE

# label_width_small(cstr) -> its width in the small face
label_width_small:
    PROLOGUE
    mov rbx, rdi
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, rbx
    mov rdx, rax
    call text_width
    EPILOGUE

# button(id, x, y, label, style) -> UB bits: a framed button 32 high, style 0 plain, 1 the accent,
# 2 red text, 3 chosen (a choice's selected option)
button:
    PROLOGUE 32
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov [rsp], r8d
    mov rdi, rcx
    call label_width
    mov r15d, eax
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, r15d
    M r8d, MI_32
    call ui_btn
    mov [rsp + 4], eax
    COLOR eax, T_PANEL
    COLOR r9d, T_BORDER
    cmp dword ptr [rsp], 1
    jne 1f
    COLOR eax, T_ACCENT
    mov r9d, eax
1:  cmp dword ptr [rsp], 3
    jne 2f
    COLOR eax, T_ACTIVE
2:  test dword ptr [rsp + 4], UB_HOVER
    jz 3f
    cmp dword ptr [rsp], 1
    je 3f
    COLOR eax, T_HOVER
3:  push rax
    push rax
    mov edi, r12d
    mov esi, r13d
    mov edx, r15d
    M ecx, MI_32
    M r8d, MI_RADIUS
    call gfx_frame
    add rsp, 16
    COLOR eax, T_FG
    cmp dword ptr [rsp], 1
    jne 4f
    COLOR eax, T_BG
4:  cmp dword ptr [rsp], 2
    jne 5f
    COLOR eax, T_ERROR
5:  push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r15d
    M r8d, MI_32
    mov r9, r14
    call ui_text_center
    add rsp, 16
    test dword ptr [rsp + 4], UB_CLICK
    jz 6f
    mov dword ptr [rip + g_dirty], 1
6:  mov eax, [rsp + 4]
    mov edx, r15d
    EPILOGUE

# row_button(id, label, style) -> UB bits: a button at xp_bx, xp_y; xp_bx moves right
row_button:
    PROLOGUE
    mov r12d, edi
    mov r13, rsi
    mov r14d, edx
    mov edi, r12d
    mov esi, [rip + xp_bx]
    mov edx, [rip + xp_y]
    mov rcx, r13
    mov r8d, r14d
    call button
    add edx, [rip + g_mt + 4*MI_6]
    add [rip + xp_bx], edx
    EPILOGUE

# icon_button(id, x, icon) -> UB bits: a 28 px square button with an icon, at xp_y
icon_button:
    PROLOGUE 16
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov edi, ebx
    mov esi, r12d
    mov edx, [rip + xp_y]
    M ecx, MI_28
    M r8d, MI_28
    mov r9d, r13d
    call ui_icon_btn
    mov [rsp], eax
    test eax, UB_CLICK
    jz 1f
    mov dword ptr [rip + g_dirty], 1
1:  mov eax, [rsp]
    EPILOGUE

# line_cstr() -> xp_line as a cstr
line_cstr:
    push rbx
    lea rdi, [rip + xp_line]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + xp_line + SB_len]
    mov rax, [rip + xp_line + SB_ptr]
    pop rbx
    ret

# ext_needs_words(ext, sb): what it may do, in plain words joined by ", " ("read and change the
# files you have open, read the files in your project, run gofmt"), for the page and the install
# dialog
FN ext_needs_words
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, [rbx + EXT_needs]
    xor r14d, r14d              # items so far
    lea rsi, [rip + .Ln_docs_write]
    test r13d, NEEDS_DOC_WRITE
    jnz 1f
    lea rsi, [rip + .Ln_docs_read]
    test r13d, NEEDS_DOC_READ
    jz 2f
1:  call item
2:  lea rsi, [rip + .Ln_proj_write]
    test r13d, NEEDS_PROJECT_WRITE
    jnz 3f
    lea rsi, [rip + .Ln_proj_read]
    test r13d, NEEDS_PROJECT_READ
    jz 4f
3:  call item
4:  lea rsi, [rip + .Ln_home]
    test r13d, NEEDS_HOME_READ
    jz 5f
    call item
5:  lea rsi, [rip + .Ln_net]
    test r13d, NEEDS_NETWORK
    jz 6f
    call item
6:  lea rsi, [rip + .Ln_terminal]
    test r13d, NEEDS_TERMINAL
    jz 61f
    call item
61: lea rsi, [rip + .Ln_git]
    test r13d, NEEDS_GIT_READ
    jz 7f
    call item
7:  mov rsi, [rbx + EXT_runs]
    test rsi, rsi
    jz 8f
    cmp byte ptr [rsi], 0
    je 8f
    lea rsi, [rip + .Ln_runs]
    call item
    mov rdi, r12
    mov rsi, [rbx + EXT_runs]
    call sb_push_cstr
8:  lea rsi, [rip + .Ln_secrets]  # resources group
    test r13d, NEEDS_SECRETS
    jz 82f
    call item
82: mov rsi, [rbx + EXT_nb_kernels]  # notebooks: kernels run as the user
    test rsi, rsi
    jz 81f
    cmp byte ptr [rsi], 0
    je 81f
    lea rsi, [rip + .Ln_kernels]
    call item
    mov rdi, r12
    mov rsi, [rbx + EXT_nb_kernels]
    call sb_push_cstr
81: test r14d, r14d
    jnz 9f
    lea rsi, [rip + .Ln_nothing]
    call item
9:  EPILOGUE

# item(cstr): onto r12, after ", " when it is not the first (r14 counts)
item:
    push rsi
    push rsi
    test r14d, r14d
    jz 1f
    mov rdi, r12
    lea rsi, [rip + .Ln_sep]
    call sb_push_cstr
1:  pop rsi
    pop rsi
    inc r14d
    mov rdi, r12
    jmp sb_push_cstr

# ---------------- extension management: updates, where it came from, roll back ----------------

# draw_updates(): "2 updates available" with Update all, when there are any
draw_updates:
    PROLOGUE
    call extupdate_count
    test eax, eax
    jz 9f
    mov ebx, eax
    lea rdi, [rip + xp_buf]
    mov esi, ebx
    call fmt_u64
    lea rsi, [rip + .Lt_updates_avail]
    cmp ebx, 1
    jne 1f
    lea rsi, [rip + .Lt_update_avail]
1:  call cstr_copy
    lea rdi, [rip + .Lb_update_all]
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    mov edi, ID_XM + 2
    mov edx, [rip + xp_y]
    lea rcx, [rip + .Lb_update_all]
    mov r8d, 1
    call button
    test eax, UB_CLICK
    jz 2f
    call extupdate_update_all
2:  lea rdi, [rip + g_face_ui]
    lea rsi, [rip + xp_buf]
    COLOR edx, T_ACCENT
    mov ecx, MI_32
    mov r8d, [rip + xp_x]
    call text_at_keep
    M eax, MI_48
    add [rip + xp_y], eax
9:  EPILOGUE

# update_label(ext) -> rax "Update to 0.1.2" when an update is offered, else 0
update_label:
    PROLOGUE
    call extupdate_offer
    test rax, rax
    jz 9f
    mov rbx, rax
    lea rdi, [rip + xp_upd]
    lea rsi, [rip + .Lb_update_to]
    call cstr_copy
    mov rdi, rax
    mov rsi, rbx
    mov ecx, 60
1:  mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rdi
    inc rsi
    dec ecx
    jnz 1b
2:  mov byte ptr [rdi], 0
    lea rax, [rip + xp_upd]
9:  EPILOGUE

# push_source(ext): where it came from onto xp_line ("  ·  github.com/o/n", the archive, the folder,
# a link), and "  ·  0.1.2 available"
push_source:
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EXT_inst], 0
    je 1f
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_linked]
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    mov rsi, [rbx + EXT_dir]
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_development]
    call sb_push_cstr
    jmp 5f
1:  mov rdi, rbx
    lea rsi, [rip + .Lk_source]
    call extrec_get
    test rax, rax
    jz 4f
    lea r12, [rip + .Lt_from_archive]
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lv_archive]
    call str_eq_cstr
    test eax, eax
    jnz 2f
    mov rdi, rbx
    lea rsi, [rip + .Lk_source]
    call extrec_get
    lea r12, [rip + .Lt_from_folder]
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lv_folder]
    call str_eq_cstr
    test eax, eax
    jz 4f
2:  lea rdi, [rip + xp_line]
    mov rsi, r12
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lk_path]
    call extrec_get
    test rax, rax
    jz 5f
    lea rdi, [rip + xp_line]
    mov rsi, rax
    call sb_push
    jmp 5f
4:  lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_source]
    call sb_push_cstr
    mov rdi, rbx
    call ext_full_name
    lea rdi, [rip + xp_line]
    mov rsi, rax
    call sb_push_cstr
5:  mov rdi, rbx
    call extupdate_offer
    test rax, rax
    jz 9f
    mov r12, rax
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_dot]
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_available]
    call sb_push_cstr
9:  EPILOGUE

# from_github(ext) -> 1 when it came from a GitHub release (its record says so, or it has none)
from_github:
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    cmp qword ptr [rbx + EXT_inst], 0
    jne 9f
    mov rdi, rbx
    lea rsi, [rip + .Lk_source]
    call extrec_get
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lv_github]
    call str_eq_cstr
    EPILOGUE
8:  mov eax, 1
9:  EPILOGUE

# draw_versions(ext) -> eax 1 when Roll back was clicked (the record shown changes): Update to 0.1.2,
# What's new (its release page) and Roll back to 0.1.0, when they apply
draw_versions:
    PROLOGUE
    mov rbx, rdi
    xor r13d, r13d
    mov rdi, rbx
    call update_label
    mov r12, rax
    test r12, r12
    jnz 1f
    cmp qword ptr [rbx + EXT_prev], 0
    je 9f
1:  mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    M eax, MI_8
    add [rip + xp_y], eax
    test r12, r12
    jz 3f
    mov edi, ID_XM + 3
    mov rsi, r12
    mov edx, 1
    call row_button
    test eax, UB_CLICK
    jz 2f
    mov rdi, rbx
    call extupdate_update
2:  mov rdi, rbx
    call from_github
    test eax, eax
    jz 3f
    mov edi, ID_XM + 4
    lea rsi, [rip + .Lb_whats_new]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 3f
    lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call extupdate_release_url
    call line_cstr
    mov rdi, rax
    call desktop_open
3:  mov rsi, [rbx + EXT_prev]
    test rsi, rsi
    jz 8f
    lea rdi, [rip + xp_rb]
    push rsi
    push rsi
    lea rsi, [rip + .Lb_rollback_to]
    call cstr_copy
    pop rsi
    pop rsi
    mov rdi, rax
    mov ecx, 60
4:  mov al, [rsi]
    test al, al
    jz 5f
    mov [rdi], al
    inc rdi
    inc rsi
    dec ecx
    jnz 4b
5:  mov byte ptr [rdi], 0
    mov edi, ID_XM + 5
    lea rsi, [rip + xp_rb]
    xor edx, edx
    call row_button
    test eax, UB_CLICK
    jz 8f
    mov rdi, rbx
    call ext_rollback_ask
    mov r13d, 1
8:  M eax, MI_40
    add [rip + xp_y], eax
9:  mov eax, r13d
    EPILOGUE

.section .rodata
.p2align 3
install_items:
    .quad .Lm_github, cmd_install_extension, .Lm_folder, cmd_install_extension_folder
    .quad .Lm_link, cmd_link_extension_folder, .Lm_archive, cmd_install_extension_archive, 0, 0
.Lm_github: .asciz "From GitHub\342\200\246"
.Lm_folder: .asciz "From a Folder\342\200\246"
.Lm_link: .asciz "Link a Folder (development)\342\200\246"
.Lm_archive: .asciz "From an Archive\342\200\246"
.Lb_check: .asciz "Check for updates"
.Lb_update_all: .asciz "Update all"
.Lb_update_to: .asciz "Update to "
.Lb_whats_new: .asciz "What's new"
.Lb_rollback_to: .asciz "Roll back to "
.Lt_update_avail: .asciz " update available"
.Lt_updates_avail: .asciz " updates available"
.Lt_linked: .asciz "  \302\267  linked to "
.Lt_development: .asciz " (development)"
.Lt_from_archive: .asciz "  \302\267  from the archive "
.Lt_from_folder: .asciz "  \302\267  from the folder "
.Lt_dot: .asciz "  \302\267  "
.Lt_available: .asciz " available"
.Lk_source: .asciz "source"
.Lk_path: .asciz "path"
.Lv_archive: .asciz "archive"
.Lv_folder: .asciz "folder"
.Lv_github: .asciz "github"
.Ld_updates: .asciz "updates="
.Ld_versions: .asciz "versions update="
.Ld_previous: .asciz " previous="
.Ld_dash: .asciz "-"

.bss
xp_upd: .zero 128               # "Update to 0.1.2"
xp_rb: .zero 128                # "Roll back to 0.1.0"

.text
# ---------------- extension management: Browse (the rhun extensions index) ----------------

# draw_switch(): "Installed (5) | Browse", and in Browse the index's age and Refresh on the right
draw_switch:
    PROLOGUE 16
    xor r12d, r12d              # installed
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 2f
    imul rax, rbx, EXT_SIZE
    add rax, [rip + g_exts + VEC_ptr]
    inc rbx
    cmp dword ptr [rax + EXT_status], ES_REMOVED
    je 1b
    inc r12d
    jmp 1b
2:  lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lb_installed_n]
    call cstr_copy
    mov rdi, rax
    mov esi, r12d
    call fmt_u64
    mov byte ptr [rdi], ')'
    mov byte ptr [rdi + 1], 0
    mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    mov edx, 3
    cmp dword ptr [rip + g_xp_browse], 0
    je 3f
    xor edx, edx
3:  mov edi, ID_XM + 7
    lea rsi, [rip + xp_buf]
    call row_button
    test eax, UB_CLICK
    jz 4f
    mov dword ptr [rip + g_xp_browse], 0
    mov dword ptr [rip + xp_scroll], 0
4:  xor edx, edx
    cmp dword ptr [rip + g_xp_browse], 0
    je 5f
    mov edx, 3
5:  mov edi, ID_XM + 8
    lea rsi, [rip + .Lb_browse]
    call row_button
    test eax, UB_CLICK
    jz 6f
    call extpage_browse
6:  cmp dword ptr [rip + g_xp_browse], 0
    je 8f
    # Refresh, and the index's age before it
    lea rdi, [rip + .Lb_refresh]
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    mov [rsp], esi
    mov edi, ID_XM + 9
    mov edx, [rip + xp_y]
    lea rcx, [rip + .Lb_refresh]
    xor r8d, r8d
    call button
    test eax, UB_CLICK
    jz 7f
    call extindex_refresh
7:  lea rdi, [rip + xp_line]
    call sb_clear
    call push_index_age
    call line_cstr
    mov r12, rax
    mov rdi, rax
    call label_width_small
    mov r8d, [rsp]
    sub r8d, eax
    sub r8d, [rip + g_mt + 4*MI_12]
    lea rdi, [rip + g_face_small]
    mov rsi, r12
    COLOR edx, T_MUTED
    mov ecx, MI_32
    call text_at_keep
8:  M eax, MI_48
    add [rip + xp_y], eax
    EPILOGUE

# push_index_age(): "Index updated 2 h ago", "Getting the index…" or "No index yet" onto xp_line
push_index_age:
    PROLOGUE
    call extindex_state
    test edx, edx
    jz 1f
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_getting_index]
    call sb_push_cstr
    EPILOGUE
1:  call extindex_fetched
    test rax, rax
    jnz 2f
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_no_index]
    call sb_push_cstr
    EPILOGUE
2:  mov rbx, rax
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_index_updated]
    call sb_push_cstr
    call time_now
    sub rax, rbx
    jns 3f
    xor eax, eax
3:  cmp rax, 60
    jae 4f
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_just_now]
    call sb_push_cstr
    EPILOGUE
4:  lea r12, [rip + .Lt_min_ago]
    mov ecx, 60
    cmp rax, 3600
    jb 5f
    lea r12, [rip + .Lt_h_ago]
    mov ecx, 3600
    cmp rax, 86400
    jb 5f
    lea r12, [rip + .Lt_days_ago]
    mov ecx, 86400
5:  xor edx, edx
    div rcx
    lea rdi, [rip + xp_line]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + xp_line]
    mov rsi, r12
    call sb_push_cstr
    EPILOGUE

# extpage_browse(): the Browse list (the index fetched when the cached copy is old)
FN extpage_browse
    PROLOGUE
    mov dword ptr [rip + g_xp_browse], 1
    mov qword ptr [rip + g_xp_detail], 0
    mov dword ptr [rip + xp_scroll], 0
    call extindex_browse_fetch
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# extpage_search(ptr, len): the Browse search's text (ext-search)
FN extpage_search
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + xp_search]
    mov rsi, rbx
    mov rdx, r12
    call tf_set
    mov dword ptr [rip + xp_scroll], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# draw_browse(): the search field, then a card per entry of the index that matches it
draw_browse:
    PROLOGUE 16
    mov dword ptr [rip + xp_search + TF_id], ID_XM + 6
    xor r9d, r9d
    cmp dword ptr [rip + g_focus], FOCUS_EXT_SEARCH
    jne 1f
    mov r9d, 1
1:  lea rax, [rip + .Lph_search]
    push rax
    push rax
    lea rdi, [rip + xp_search]
    mov esi, [rip + xp_x]
    mov edx, [rip + xp_y]
    mov ecx, [rip + xp_w]
    M r8d, MI_32
    call ui_textfield
    add rsp, 16
    test eax, UB_PRESS
    jz 2f
    mov dword ptr [rip + g_focus], FOCUS_EXT_SEARCH
    mov dword ptr [rip + g_dirty], 1
2:  M eax, MI_48
    add [rip + xp_y], eax
    call extindex_state
    cmp eax, 2
    jne 3f
    lea rsi, [rip + .Lt_index_newer]
    jmp .Ldb_line
3:  call extindex_count
    test eax, eax
    jnz 5f
    call extindex_state
    lea rsi, [rip + .Lt_getting_index]
    test edx, edx
    jnz .Ldb_line
    call extindex_error
    cmp byte ptr [rax], 0
    je 4f
    lea rdi, [rip + xp_line]
    call sb_clear
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_index_failed]
    call sb_push_cstr
    call extindex_error
    lea rdi, [rip + xp_line]
    mov rsi, rax
    call sb_push_cstr
    call line_cstr
    mov rsi, rax
    jmp .Ldb_line
4:  lea rsi, [rip + .Lt_index_empty]
    jmp .Ldb_line
5:  lea rdi, [rip + xp_search]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    call extindex_list
    cmp dword ptr [rip + g_xi_count], 0
    jne 6f
    lea rsi, [rip + .Lt_no_match]
    jmp .Ldb_line
6:  xor r12d, r12d
7:  cmp r12d, [rip + g_xi_count]
    jae 9f
    cmp r12d, XB_SHOWN
    jae 8f
    mov edi, r12d
    call draw_entry
    inc r12d
    jmp 7b
8:  # "and 40 more: search to narrow the list"
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lt_and]
    call cstr_copy
    mov rdi, rax
    mov esi, [rip + g_xi_count]
    sub esi, XB_SHOWN
    call fmt_u64
    lea rsi, [rip + .Lt_more]
    call cstr_copy
    lea rsi, [rip + xp_buf]
.Ldb_line:
    lea rdi, [rip + g_face_ui]
    COLOR edx, T_MUTED
    mov ecx, MI_28
    call line_text
9:  EPILOGUE

# entry_button(entry) -> eax XBB_*, rdx its label: Install, Installed, Update to X, Not for this
# system, Needs rhun X
.equ XBB_INSTALL, 0
.equ XBB_INSTALLED, 1
.equ XBB_UPDATE, 2
.equ XBB_UNAVAILABLE, 3
.equ XBB_NEWER, 4
entry_button:
    PROLOGUE
    mov rbx, rdi
    mov eax, XBB_UNAVAILABLE
    lea rdx, [rip + .Lb_unavailable]
    cmp qword ptr [rbx + XI_digest], 0
    je 9f
    mov rdi, [rbx + XI_rhun]
    test rdi, rdi
    jz 1f
    lea rsi, [rip + rhun_version]
    call ver_cmp
    cmp eax, 0
    jle 1f
    lea rdi, [rip + xp_eb]
    lea rsi, [rip + .Lb_needs_rhun]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + XI_rhun]
    mov ecx, 40
    call copy_cap
    mov eax, XBB_NEWER
    lea rdx, [rip + xp_eb]
    jmp 9f
1:  mov rdi, [rbx + XI_name]
    call strlen
    mov rdi, [rbx + XI_name]
    mov rsi, rax
    call ext_by_name
    test rax, rax
    jz 3f
    mov rdi, [rbx + XI_version]
    mov rsi, [rax + EXT_version]
    test rsi, rsi
    jz 2f
    call ver_cmp
    cmp eax, 0
    jle 2f
    lea rdi, [rip + xp_eb]
    lea rsi, [rip + .Lb_update_to]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + XI_version]
    mov ecx, 40
    call copy_cap
    mov eax, XBB_UPDATE
    lea rdx, [rip + xp_eb]
    jmp 9f
2:  mov eax, XBB_INSTALLED
    lea rdx, [rip + .Lb_installed]
    jmp 9f
3:  mov eax, XBB_INSTALL
    lea rdx, [rip + .Lb_install_one]
9:  EPILOGUE

# copy_cap(dst, src, max): at most max bytes and a NUL
copy_cap:
1:  mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rdi
    inc rsi
    dec ecx
    jnz 1b
2:  mov byte ptr [rdi], 0
    ret

# entry_click(entry, XBB_*): Install (the pinned version, its digest checked, the real manifest's
# dialog) or Update
entry_click:
    PROLOGUE 240
    mov rbx, rdi
    mov r12d, esi
    # owner and name apart
    mov rsi, [rbx + XI_name]
    xor ecx, ecx
1:  mov al, [rsi + rcx]
    test al, al
    jz 9f
    cmp al, '/'
    je 2f
    cmp ecx, 110
    jae 9f
    mov [rsp + rcx], al
    inc ecx
    jmp 1b
2:  mov byte ptr [rsp + rcx], 0
    lea rsi, [rsi + rcx + 1]
    lea rdi, [rsp + 120]
    mov ecx, 110
    call copy_cap
    lea rdi, [rsp]
    lea rsi, [rsp + 120]
    xor edx, edx
    mov ecx, IP_ADD
    cmp r12d, XBB_UPDATE
    jne 3f
    mov rdx, [rbx + XI_tag]
    mov ecx, IP_UPDATE
3:  call ext_install_github
9:  EPILOGUE

# draw_entry(i): a Browse card: badge, title, owner/name and version, its button; the description;
# what it can do
draw_entry:
    PROLOGUE 48
    mov [rsp + 40], edi
    call extindex_at
    mov rbx, rax
    M eax, MI_16
    mov r12d, eax               # padding
    # what it can do, in words (xp_line)
    mov rdi, rbx
    lea rsi, [rip + xp_pv]
    call extindex_entry_needs
    lea rdi, [rip + xp_perm]
    call sb_clear
    lea rdi, [rip + xp_perm]
    lea rsi, [rip + .Lt_can]
    call sb_push_cstr
    lea rdi, [rip + xp_pv]
    lea rsi, [rip + xp_perm]
    call ext_needs_words
    lea rdi, [rip + xp_perm]
    mov esi, '.'
    call sb_push_byte
    lea rdi, [rip + xp_perm]
    xor esi, esi
    call sb_push_byte
    # its height: the title row, the description's lines, the permissions' lines
    M r13d, MI_28
    add r13d, [rip + g_mt + 4*MI_4]
    add r13d, r12d
    add r13d, r12d
    mov rsi, [rip + xp_perm + SB_ptr]
    lea rdi, [rip + g_face_small]
    mov edx, [rip + xp_x]
    add edx, r12d
    call para_lines
    imul eax, [rip + g_mt + 4*MI_20]
    add r13d, eax
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + XI_desc]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Lt_no_desc]
1:  mov edx, [rip + xp_x]
    add edx, r12d
    call para_lines
    imul eax, [rip + g_mt + 4*MI_20]
    add r13d, eax
    mov eax, [rip + xp_y]
    mov [rsp + 8], eax          # the card's top
    mov edi, [rip + xp_x]
    mov esi, eax
    mov edx, [rip + xp_w]
    mov ecx, r13d
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    COLOR eax, T_PANEL
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    mov eax, [rip + xp_x]
    add eax, r12d
    mov [rsp + 12], eax         # the inner x
    # the badge: its color (or one from its name) and its title's letter
    mov edi, eax
    mov esi, [rsp + 8]
    add esi, r12d
    M edx, MI_28
    mov rcx, rbx
    call entry_badge
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 12]
    add esi, [rip + g_mt + 4*MI_28]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 8]
    add edx, r12d
    M ecx, MI_28
    mov r8, [rbx + XI_title]
    COLOR r9d, T_FG
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 16], eax
    # "owner/name · 0.2.2"
    lea rdi, [rip + xp_line]
    call sb_clear
    lea rdi, [rip + xp_line]
    mov rsi, [rbx + XI_name]
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    lea rsi, [rip + .Lt_dot_short]
    call sb_push_cstr
    lea rdi, [rip + xp_line]
    mov rsi, [rbx + XI_version]
    call sb_push_cstr
    call line_cstr
    mov r8, rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    mov edx, [rsp + 8]
    add edx, r12d
    M ecx, MI_28
    COLOR r9d, T_MUTED
    call ui_text_c
    # the button on the right
    mov rdi, rbx
    call entry_button
    mov [rsp + 20], eax
    mov r14, rdx
    mov rdi, r14
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, r12d
    sub esi, eax
    mov edx, [rsp + 8]
    add edx, r12d
    sub edx, [rip + g_mt + 4*MI_2]
    mov edi, [rsp + 40]
    add edi, ID_XM + 0x2000
    mov rcx, r14
    xor r8d, r8d
    cmp dword ptr [rsp + 20], XBB_UPDATE
    ja 2f
    cmp dword ptr [rsp + 20], XBB_INSTALLED
    je 2f
    mov r8d, 1                  # Install and Update in the accent
2:  call button
    test eax, UB_CLICK
    jz 3f
    mov esi, [rsp + 20]
    cmp esi, XBB_INSTALL
    je 21f
    cmp esi, XBB_UPDATE
    jne 3f
21: mov rdi, rbx
    call entry_click
3:  # the description, then what it can do
    mov eax, [rsp + 8]
    add eax, r12d
    add eax, [rip + g_mt + 4*MI_28]
    mov [rip + xp_y], eax
    mov rsi, [rbx + XI_desc]
    test rsi, rsi
    jnz 4f
    lea rsi, [rip + .Lt_no_desc]
4:  lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_20
    mov r8d, [rsp + 12]
    call para
    mov eax, [rip + g_mt + 4*MI_4]
    add [rip + xp_y], eax
    mov rsi, [rip + xp_perm + SB_ptr]
    lea rdi, [rip + g_face_small]
    COLOR edx, T_FG
    mov ecx, MI_20
    mov r8d, [rsp + 12]
    call para
    mov eax, [rsp + 8]
    add eax, r13d
    add eax, [rip + g_mt + 4*MI_12]
    mov [rip + xp_y], eax
    EPILOGUE

# entry_badge(x, y, size, entry): a rounded square in the entry's color (or one its name picks)
# with its title's first letter
entry_badge:
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, rcx
    mov r15d, [rbx + XI_color]
    test r15d, r15d
    jnz 2f
    mov rsi, [rbx + XI_name]
    xor eax, eax
1:  movzx ecx, byte ptr [rsi]
    test ecx, ecx
    jz 11f
    cmp ecx, '/'
    jne 12f
    xor eax, eax                # the name after the owner, as an installed one's badge
    inc rsi
    jmp 1b
12: imul eax, eax, 31
    add eax, ecx
    inc rsi
    jmp 1b
11: and eax, 7
    lea rcx, [rip + badge_colors]
    mov r15d, [rcx + rax*4]
2:  mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    shr r8d, 2
    mov r9d, r15d
    call gfx_round_rect
    mov rax, [rbx + XI_title]
    movzx eax, byte ptr [rax]
    cmp al, 'a'
    jb 3f
    cmp al, 'z'
    ja 3f
    sub al, 32
3:  mov [rsp], al
    mov byte ptr [rsp + 1], 0
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r14d
    lea r9, [rsp]
    mov eax, 0xffffffff
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    EPILOGUE

# ---------------- extension management: the Browse search's keys ----------------

# extpage_field() -> the search field while it has the keyboard, or 0
FN extpage_field
    lea rax, [rip + xp_search]
    ret

# extpage_key(keysym, char, mods) -> eax 1 when handled: Esc clears the search, then gives the keys
# back; Enter gives them back; the rest edits it
FN extpage_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    cmp r12d, KEY_ESCAPE
    jne 1f
    lea rdi, [rip + xp_search]
    call tf_text
    test rdx, rdx
    jz 2f
    lea rdi, [rip + xp_search]
    call tf_clear
    jmp 8f
1:  cmp r12d, KEY_RETURN
    je 2f
    cmp r12d, KEY_KP_ENTER
    jne 3f
2:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
    jmp 8f
3:  lea rdi, [rip + xp_search]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tf_key
    test eax, eax
    jz 9f
    mov dword ptr [rip + xp_scroll], 0
8:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
9:  EPILOGUE

# extpage_take_find() -> eax 1 when the Extensions page is in front: Find goes to Browse's search
FN extpage_take_find
    PROLOGUE
    xor ebx, ebx
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 9f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_EXT
    jne 9f
    cmp dword ptr [rip + g_xp_browse], 0
    jne 1f
    call extpage_browse
1:  mov qword ptr [rip + g_xp_detail], 0
    mov dword ptr [rip + g_focus], FOCUS_EXT_SEARCH
    lea rdi, [rip + xp_search]
    call tf_select_all
    mov dword ptr [rip + g_dirty], 1
    mov ebx, 1
9:  mov eax, ebx
    EPILOGUE

# extpage_browse_dump(sb): print-ext-browse: "index=N format=F fetching=0|1 [error=…]", then the
# entries the search shows, "OWNER/NAME VERSION button=install|installed|update|unavailable|newer"
FN extpage_browse_dump
    PROLOGUE
    mov r12, rdi
    call extindex_count
    mov r13d, eax
    mov r14d, edx
    mov rdi, r12
    lea rsi, [rip + .Ld_index]
    call sb_push_cstr
    mov rdi, r12
    mov esi, r13d
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_format]
    call sb_push_cstr
    mov rdi, r12
    mov esi, r14d
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_fetching]
    call sb_push_cstr
    call extindex_state
    mov rdi, r12
    mov esi, edx
    call sb_push_u64
    call extindex_error
    cmp byte ptr [rax], 0
    je 1f
    mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + .Ld_error]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, rbx
    call sb_push_cstr
1:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + xp_search]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    call extindex_list
    xor r13d, r13d
2:  cmp r13d, [rip + g_xi_count]
    jae 9f
    mov edi, r13d
    call extindex_at
    mov rbx, rax
    inc r13d
    mov rdi, r12
    mov rsi, [rbx + XI_name]
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + XI_version]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_button]
    call sb_push_cstr
    mov rdi, rbx
    call entry_button
    lea rcx, [rip + xbb_words]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 2b
9:  EPILOGUE

# extpage_browse_click(name ptr, len) -> eax 1 when the entry's button was pressed (ext-browse-install)
FN extpage_browse_click
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
1:  cmp r14d, [rip + g_xi_count]
    jae 8f
    mov edi, r14d
    call extindex_at
    mov rbx, rax
    inc r14d
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + XI_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rdi, rbx
    call entry_button
    cmp eax, XBB_INSTALL
    je 2f
    cmp eax, XBB_UPDATE
    jne 8f
2:  mov rdi, rbx
    mov esi, eax
    call entry_click
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
xbb_words: .quad .Lw_install, .Lw_installed, .Lw_update, .Lw_unavailable, .Lw_newer
.Lw_install: .asciz "install"
.Lw_installed: .asciz "installed"
.Lw_update: .asciz "update"
.Lw_unavailable: .asciz "unavailable"
.Lw_newer: .asciz "newer"
.Ld_index: .asciz "index="
.Ld_format: .asciz " format="
.Ld_fetching: .asciz " fetching="
.Ld_error: .asciz " error="
.Ld_button: .asciz " button="
.Lb_installed_n: .asciz "Installed ("
.Lb_browse: .asciz "Browse"
.Lb_refresh: .asciz "Refresh"
.Lb_installed: .asciz "Installed"
.Lb_install_one: .asciz "Install"
.Lb_unavailable: .asciz "Not for this system"
.Lb_needs_rhun: .asciz "Needs rhun "
.Lph_search: .asciz "Search extensions"
.Lt_getting_index: .asciz "Getting the index\342\200\246"
.Lt_no_index: .asciz "No index yet"
.Lt_index_updated: .asciz "Index updated "
.Lt_just_now: .asciz "just now"
.Lt_min_ago: .asciz " min ago"
.Lt_h_ago: .asciz " h ago"
.Lt_days_ago: .asciz " days ago"
.Lt_index_newer: .asciz "This index needs a newer rhun. Update rhun to browse."
.Lt_index_failed: .asciz "Couldn't get the index: "
.Lt_index_empty: .asciz "The index lists no extensions."
.Lt_no_match: .asciz "No extension matches the search."
.Lt_and: .asciz "And "
.Lt_more: .asciz " more: search to narrow the list."
.Lt_dot_short: .asciz "  \302\267  "
.Lt_can: .asciz "Can "

.bss
.p2align 3
.globl g_xp_browse
g_xp_browse: .long 0            # the list shows Browse (the index), not what is installed
.p2align 3
xp_search: .zero TF_SIZE        # Browse's search
xp_eb: .zero 128                # an entry's button label
xp_pv: .zero EXT_SIZE           # an entry's needs, for ext_needs_words
xp_perm: .zero SB_SIZE          # what an entry can do, in words

.text
# ---------------- extension management: a pack's members ----------------

# draw_pack(ext) -> eax 1 when a button was clicked: "In this pack": each member's title (or name)
# and state, with Remove for one installed and Install for one that is not
draw_pack:
    PROLOGUE 16
    mov rbx, rdi
    xor eax, eax
    mov r12, [rbx + EXT_pack]
    test r12, r12
    jz 9f
    lea rsi, [rip + .Ls_pack]
    call section
    xor r15d, r15d              # members
1:  mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call next_word
    add r12, rcx
    test rdx, rdx
    jz 8f
    cmp rdx, 200
    jae 1b
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + xp_buf]
    mov rsi, r13
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rax, [rip + xp_buf]
    mov byte ptr [rax + rdx], 0
    mov rdi, r13
    mov rsi, r14
    call ext_by_name
    mov [rsp], rax              # the member's record, or 0
    # its name, then its state on the right with its button
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + xp_buf]
    COLOR edx, T_FG
    mov ecx, MI_32
    mov r8d, [rip + xp_x]
    call text_at_keep
    lea rsi, [rip + .Lb_install_one]
    cmp qword ptr [rsp], 0
    je 2f
    lea rsi, [rip + .Lb_remove]
2:  mov [rsp + 8], rsi
    mov rdi, rsi
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    mov edi, r15d
    add edi, ID_XM + 0x3000
    mov edx, [rip + xp_y]
    mov rcx, [rsp + 8]
    xor r8d, r8d
    call button
    test eax, UB_CLICK
    jz 4f
    mov rdi, [rsp]
    test rdi, rdi
    jz 3f
    call ext_remove_ask
    mov eax, 1
    jmp 9f
3:  lea rdi, [rip + xp_buf]
    call strlen
    lea rdi, [rip + xp_buf]
    mov rsi, rax
    call ext_install_start
    mov eax, 1
    jmp 9f
4:  M eax, MI_40
    add [rip + xp_y], eax
    inc r15d
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# dump_pack(): rbx's "pack OWNER/NAME=installed|missing …" onto r12, when it is a pack
dump_pack:
    PROLOGUE
    mov r13, [rbx + EXT_pack]
    test r13, r13
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Ld_pack]
    call sb_push_cstr
1:  mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    call next_word
    add r13, rcx
    test rdx, rdx
    jz 8f
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    call sb_push
    mov rdi, r14
    mov rsi, r15
    call ext_by_name
    lea rsi, [rip + .Ld_missing]
    test rax, rax
    jz 2f
    lea rsi, [rip + .Ld_installed]
2:  mov rdi, r12
    call sb_push_cstr
    jmp 1b
8:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

.section .rodata
.Ls_pack: .asciz "In this pack"
.Ld_pack: .asciz "pack"
.Ld_installed: .asciz "=installed"
.Ld_missing: .asciz "=missing"

.text
# ---------------- for the tests: print-ext-page ----------------

# extpage_dump(sb): the list ("Title version on|off [problem]") or the details of one extension
FN extpage_dump
    PROLOGUE
    mov r12, rdi
    call extpage_forget
    mov rbx, [rip + g_xp_detail]
    test rbx, rbx
    jnz .Lxd_detail
    # extension management: "updates=N" when there are any
    call extupdate_count
    test eax, eax
    jz 0f
    mov r13d, eax
    mov rdi, r12
    lea rsi, [rip + .Ld_updates]
    call sb_push_cstr
    mov rdi, r12
    mov esi, r13d
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
0:  xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    call dump_head
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
.Lxd_detail:
    call dump_head
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Ld_pinned]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rbx + EXT_pinned]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    cmp dword ptr [rbx + EXT_edits], 0  # wsedit: the standing permission, when given
    je 51f
    mov rdi, r12
    lea rsi, [rip + .Ld_edits]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
51:
    # "badge=letter|icon|unreadable color=#rrggbb|-"
    mov rdi, rbx
    call ext_icon_state
    lea rsi, [rip + .Ld_badge_letter]
    cmp eax, 1
    jne 1f
    lea rsi, [rip + .Ld_badge_icon]
1:  cmp eax, 2
    jne 2f
    lea rsi, [rip + .Ld_badge_bad]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_color]
    call sb_push_cstr
    mov eax, [rbx + EXT_color]
    test eax, eax
    jnz 3f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    jmp 5f
3:  mov rdi, r12
    mov esi, '#'
    call sb_push_byte
    mov r13d, 20                # the six hex digits, high to low
4:  mov eax, [rbx + EXT_color]
    mov ecx, r13d
    shr eax, cl
    and eax, 15
    lea rcx, [rip + .Ld_hex]
    movzx esi, byte ptr [rcx + rax]
    mov rdi, r12
    call sb_push_byte
    sub r13d, 4
    jns 4b
5:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    # permissions, a line each
    lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call ext_needs_words
    mov rdi, r12
    lea rsi, [rip + .Ld_can]
    call sb_push_cstr
    call line_cstr
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Ld_held]
    call sb_push_cstr
    mov rdi, r12
    xor esi, esi
    cmp qword ptr [rbx + EXT_confine_why], 0
    sete sil
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    # where it may run programs as you: "runs-in=~/code/app, ~/b" when anywhere
    lea rdi, [rip + xp_line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + xp_line]
    call run_allow_projects
    test eax, eax
    jz 1f
    mov rdi, r12
    lea rsi, [rip + .Ld_runs_in]
    call sb_push_cstr
    call line_cstr
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
1:
    # settings
    xor r13d, r13d
2:  cmp r13, [rbx + EXT_sdefs + VEC_len]
    jae 7f
    imul r14, r13, SD_SIZE
    add r14, [rbx + EXT_sdefs + VEC_ptr]
    inc r13
    mov rdi, r12
    lea rsi, [rip + .Ld_setting]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + SD_key]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '='
    call sb_push_byte
    mov rdi, rbx                # resources group: the window value (a workspace's, extconfig.s)
    mov rsi, r14
    call extconfig_window
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx                # and the override line under it
    mov rsi, r14
    call extconfig_override
    test rax, rax
    jz 2b
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 2b
7: # extension management: a pack's members, "versions update=0.1.2|- previous=0.1.0|-"
    call dump_pack
    mov rdi, r12
    lea rsi, [rip + .Ld_versions]
    call sb_push_cstr
    mov rdi, rbx
    call extupdate_offer
    mov rsi, rax
    test rsi, rsi
    jnz 0f
    lea rsi, [rip + .Ld_dash]
0:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_previous]
    call sb_push_cstr
    mov rsi, [rbx + EXT_prev]
    test rsi, rsi
    jnz 0f
    lea rsi, [rip + .Ld_dash]
0:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

# dump_head(): rbx's "Title version on|off [problem]" onto r12
dump_head:
    PROLOGUE
    mov rdi, rbx
    call ext_title
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, [rbx + EXT_version]
    test rsi, rsi
    jz 1f
    mov rdi, r12
    call sb_push_cstr
1:  lea rsi, [rip + .Ld_on]
    cmp dword ptr [rbx + EXT_disabled], 0
    je 2f
    lea rsi, [rip + .Ld_off]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, rbx
    call ext_problem
    test rax, rax
    jz 9f
    push rax
    push rax
    mov rdi, r12
    lea rsi, [rip + .Ld_problem]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, r12
    call sb_push_cstr
9:  EPILOGUE

.section .rodata
.p2align 2
badge_colors: .long 0xff4f7fd9, 0xff3f9f6f, 0xffd9803f, 0xff9a6ad6, 0xffcf5050, 0xff2f9fae, 0xffb88a2a, 0xffc0508f
.Lt_title: .asciz "Extensions"
.Ln_docs_read: .asciz "read the files you have open"
.Ln_docs_write: .asciz "read and change the files you have open"
.Ln_proj_read: .asciz "read the files in your project"
.Ln_proj_write: .asciz "read and change the files in your project"
.Ln_home: .asciz "read the files in your home folder"
.Ln_net: .asciz "use the internet"
.Ln_terminal: .asciz "suggest terminal commands for you to run"
.Ln_git: .asciz "read the project's Git history"
.Ln_runs: .asciz "run "
.Ln_kernels: .asciz "run notebook kernels as you: "
.Ln_nothing: .asciz "only use its own commands and settings"
.Ln_secrets: .asciz "store passwords and tokens in your keychain"
.Ln_sep: .asciz ", "
.Lt_intro: .asciz "Extensions add commands, marks and tools to rhun. Each one gets only the access it asks for."
.Lt_none: .asciz "No extensions yet. Install one from GitHub, for example rhun-editor/showcase."
.Lt_no_desc: .asciz "No description"
.Lt_stopped: .asciz "Stopped"
.Lt_version: .asciz "Version "
.Lt_source: .asciz "  \302\267  github.com/"
.Lt_pin: .asciz "Pin to the title bar"
.Lt_pin_desc: .asciz "Its button sits next to the extensions button and lists its commands."
.Lt_held: .asciz "rhun holds it to these permissions."
.Lt_not_held: .asciz "This system cannot hold it to these permissions; it runs with yours."
.Lt_windows: .asciz "Windows cannot hold it to these permissions; it runs with yours."
.Lt_wasm: .asciz "It runs as WebAssembly: rhun holds it to these permissions on every system."
.Ls_permissions: .asciz "It can"
.Ls_resources: .asciz "Resources"
.Ls_toolbar: .asciz "Title bar"
.Ls_commands: .asciz "Commands"
.Ls_langfeat: .asciz "Language features"
.Ls_settings: .asciz "Settings"
.Lb_install: .asciz "Install \342\226\276"
.Lb_details: .asciz "Details"
.Lb_remove: .asciz "Remove"
.Lb_remove_ext: .asciz "Remove extension"
.Lb_restart: .asciz "Restart"
.Lb_change: .asciz "Change"
.Lbullet: .asciz "\342\200\242  "
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.Lempty: .asciz ""
.Ld_on: .asciz " on"
.Ld_off: .asciz " off"
.Ld_problem: .asciz " problem="
.Ld_pinned: .asciz "pinned="
.Ld_edits: .asciz "edits=yes"              # wsedit
.Lt_edits: .asciz "Can change files in your project (you allowed it)"
.Ld_badge_letter: .asciz "badge=letter"
.Ld_badge_icon: .asciz "badge=icon"
.Ld_badge_bad: .asciz "badge=unreadable"
.Ld_color: .asciz " color="
.Ld_hex: .ascii "0123456789abcdef"
.Ld_can: .asciz "can: "
.Ld_held: .asciz "held="
.Ld_runs_in: .asciz "runs-in="
.Lt_runs_in: .asciz "Runs programs as you in: "
.Lb_forget: .asciz "Forget"
.Ld_setting: .asciz "setting "

.text
# Delayed completion has no remaining source authority after replacement or cancellation.
# Preserve all registers and flags; callers may use this before their first mutation.
FN extpage_prompt_invalidate_pure
    mov qword ptr [rip + xp_prompt_sd], 0
    ret

.include "app/extpageres.inc"     # resources group: the details page's parts
