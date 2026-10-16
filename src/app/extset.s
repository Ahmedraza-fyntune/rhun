# Settings > Extensions: one block per extension after the settings table (settings.s calls
# ext_settings_draw and ext_settings_dump): title and version, state with its reason, what it
# needs in words, how it is confined, and the buttons Stop/Restart, Disable/Enable, Run
# unconfined/Confine.
.include "rhun.inc"
.equ ID_EXT_BTN, 0x5e00         # + index*8 + button

.bss
.p2align 3
line: .zero SB_SIZE
ex_x: .long 0                   # the block's left edge
ex_y: .long 0                   # the running y
ex_bx: .long 0                  # the next button's x
ex_idx: .long 0                 # the extension's index (button ids)

.text

# ext_settings_draw(x, y, w) -> eax: the height drawn
FN ext_settings_draw
    PROLOGUE
    mov [rip + ex_x], edi
    mov [rip + ex_y], esi
    mov r14d, esi
    cmp qword ptr [rip + g_exts + VEC_len], 0
    je .Lxd_done
    # the section's title
    lea rdi, [rip + g_face_ui]
    mov esi, [rip + ex_x]
    mov edx, [rip + ex_y]
    M ecx, MI_28
    lea r8, [rip + .Lt_extensions]
    COLOR r9d, T_ACCENT        # a section header, like the table's
    call ui_text_c
    M eax, MI_32
    add [rip + ex_y], eax
    xor r13d, r13d
.Lxd_ext:
    cmp r13, [rip + g_exts + VEC_len]
    jae .Lxd_done
    mov [rip + ex_idx], r13d
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    # "Title  version  owner/name"
    lea rdi, [rip + line]
    call sb_clear
    mov rsi, [rbx + EXT_title]
    test rsi, rsi
    jnz 1f
    mov rsi, [rbx + EXT_name]
1:  lea rdi, [rip + line]
    call sb_push_cstr
    mov rsi, [rbx + EXT_version]
    test rsi, rsi
    jz 2f
    lea rdi, [rip + line]
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    lea rdi, [rip + line]
    mov rsi, [rbx + EXT_version]
    call sb_push_cstr
2:  lea rdi, [rip + line]
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    lea rdi, [rip + line]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + line]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + line]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    mov edi, MI_24
    COLOR esi, T_FG
    call draw_line
    # the state, with its reason
    lea rdi, [rip + line]
    call sb_clear
    mov edi, [rbx + EXT_status]
    call ext_state_name
    lea rdi, [rip + line]
    mov rsi, rax
    call sb_push_cstr
    mov rsi, [rbx + EXT_reason]
    test rsi, rsi
    jz 3f
    lea rdi, [rip + line]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    lea rdi, [rip + line]
    mov rsi, [rbx + EXT_reason]
    call sb_push_cstr
3:  mov edi, MI_20
    COLOR esi, T_MUTED
    call draw_line
    # what it needs
    lea rdi, [rip + line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + line]
    call ext_needs_words
    mov edi, MI_20
    COLOR esi, T_MUTED
    call draw_line
    # how it is held
    lea rdi, [rip + line]
    call sb_clear
    mov rdi, rbx
    lea rsi, [rip + line]
    call ext_confined_words
    mov edi, MI_20
    COLOR esi, T_MUTED
    call draw_line
    # the buttons
    M eax, MI_6
    add [rip + ex_y], eax
    mov eax, [rip + ex_x]
    mov [rip + ex_bx], eax
    mov eax, [rbx + EXT_status]
    cmp eax, ES_DISABLED
    je 5f                       # a disabled extension has only Enable
    lea rdi, [rip + .Lb_stop]
    cmp eax, ES_RUNNING
    je 4f
    cmp eax, ES_STARTING
    je 4f
    lea rdi, [rip + .Lb_restart]
4:  xor esi, esi
    call button
    test eax, eax
    jz 5f
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 41f
    cmp eax, ES_STARTING
    je 41f
    mov rdi, rbx
    call ext_restart
    jmp 5f
41: mov rdi, rbx
    call ext_stop_user
5:  lea rdi, [rip + .Lb_disable]
    cmp dword ptr [rbx + EXT_disabled], 0
    je 6f
    lea rdi, [rip + .Lb_enable]
6:  mov esi, 1
    call button
    test eax, eax
    jz 7f
    mov esi, [rbx + EXT_disabled]
    xor esi, 1
    mov rdi, rbx
    call ext_set_disabled
7:  cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    lea rdi, [rip + .Lb_unconfined]
    cmp dword ptr [rbx + EXT_unconfined], 0
    je 71f
    lea rdi, [rip + .Lb_confine]
71: mov esi, 2
    call button
    test eax, eax
    jz 8f
    mov esi, [rbx + EXT_unconfined]
    xor esi, 1
    mov rdi, rbx
    call ext_set_unconfined
8:  M eax, MI_32
    add [rip + ex_y], eax
    M eax, MI_20
    add [rip + ex_y], eax
    inc r13
    jmp .Lxd_ext
.Lxd_done:
    mov eax, [rip + ex_y]
    sub eax, r14d
    EPILOGUE

# draw_line(MI height index, argb): the text in `line` at ex_x, ex_y; ex_y moves down
draw_line:
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    lea rdi, [rip + line]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + line + SB_len]
    lea rax, [rip + g_mt]
    mov r13d, [rax + rbx*4]     # the row height
    lea rdi, [rip + g_face_ui]
    mov esi, [rip + ex_x]
    mov edx, [rip + ex_y]
    mov ecx, r13d
    mov r8, [rip + line + SB_ptr]
    mov r9d, r12d
    call ui_text_c
    add [rip + ex_y], r13d
    EPILOGUE

# button(label cstr, k) -> 1 when clicked: a button at ex_bx, ex_y, MI_32 high; ex_bx moves right
button:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    call strlen
    lea rdi, [rip + g_face_ui]
    mov rsi, rbx
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov r13d, eax               # width
    mov eax, [rip + ex_idx]
    shl eax, 3
    add eax, r12d
    add eax, ID_EXT_BTN
    mov edi, eax
    mov esi, [rip + ex_bx]
    mov edx, [rip + ex_y]
    mov ecx, r13d
    M r8d, MI_32
    call ui_btn
    mov r14d, eax
    COLOR r9d, T_INPUT
    test eax, UB_HOVER
    jz 1f
    COLOR r9d, T_HOVER
1:  mov edi, [rip + ex_bx]
    mov esi, [rip + ex_y]
    mov edx, r13d
    M ecx, MI_32
    M r8d, MI_RADIUS
    call gfx_round_rect
    lea rdi, [rip + g_face_ui]
    mov esi, [rip + ex_bx]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rip + ex_y]
    M ecx, MI_32
    mov r8, rbx
    COLOR r9d, T_FG
    call ui_text_c
    mov eax, r13d
    add eax, [rip + g_mt + 4*MI_8]
    add [rip + ex_bx], eax
    xor eax, eax
    test r14d, UB_CLICK
    jz 9f
    mov eax, 1
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ext_needs_words(ext, sb): "documents: write, project: read, runs gofmt rustfmt, no network"
FN ext_needs_words
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, [rbx + EXT_needs]
    lea rsi, [rip + .Ln_docs_none]
    test r13d, NEEDS_DOC_WRITE
    jz 1f
    lea rsi, [rip + .Ln_docs_write]
    jmp 2f
1:  test r13d, NEEDS_DOC_READ
    jz 2f
    lea rsi, [rip + .Ln_docs_read]
2:  mov rdi, r12
    call sb_push_cstr
    lea rsi, [rip + .Ln_proj_none]
    test r13d, NEEDS_PROJECT_WRITE
    jz 3f
    lea rsi, [rip + .Ln_proj_write]
    jmp 4f
3:  test r13d, NEEDS_PROJECT_READ
    jz 4f
    lea rsi, [rip + .Ln_proj_read]
4:  mov rdi, r12
    call sb_push_cstr
    test r13d, NEEDS_HOME_READ
    jz 5f
    mov rdi, r12
    lea rsi, [rip + .Ln_home]
    call sb_push_cstr
5:  lea rsi, [rip + .Ln_net_no]
    test r13d, NEEDS_NETWORK
    jz 6f
    lea rsi, [rip + .Ln_net_yes]
6:  mov rdi, r12
    call sb_push_cstr
    test r13d, NEEDS_TERMINAL
    jz 7f
    mov rdi, r12
    lea rsi, [rip + .Ln_terminal]
    call sb_push_cstr
7:  mov rsi, [rbx + EXT_runs]
    test rsi, rsi
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Ln_runs]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + EXT_runs]
    call sb_push_cstr
9:  EPILOGUE

# ext_confined_words(ext, sb): how the program is held
FN ext_confined_words
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
.ifdef WINDOWS
    lea rsi, [rip + .Lc_windows]
    jmp 8f
.endif
    cmp dword ptr [rbx + EXT_unconfined], 0
    je 1f
    lea rsi, [rip + .Lc_choice]
    jmp 8f
1:  mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 2f
    cmp eax, ES_STARTING
    je 2f
    lea rsi, [rip + .Lc_when]
    jmp 8f
2:  mov eax, [rbx + EXT_confined]
    lea rsi, [rip + .Lc_full]
    cmp eax, CONFINED_FULL
    je 8f
    lea rsi, [rip + .Lc_tcp]
    cmp eax, CONFINED_TCP
    je 8f
    lea rsi, [rip + .Lc_none]
    mov rdi, r12
    call sb_push_cstr
    mov rsi, [rbx + EXT_confine_why]
    test rsi, rsi
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    mov rsi, [rbx + EXT_confine_why]
8:  mov rdi, r12
    call sb_push_cstr
9:  EPILOGUE

# ext_settings_dump(sb): one line per extension for print-settings, "extensions.OWNER/NAME"
FN ext_settings_dump
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    mov rdi, r12
    lea rsi, [rip + .Ld_prefix]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lt_extensions: .asciz "Extensions"
.Lsep: .asciz "  "
.Lcolon: .asciz ": "
.Lb_stop: .asciz "Stop"
.Lb_restart: .asciz "Restart"
.Lb_disable: .asciz "Disable"
.Lb_enable: .asciz "Enable"
.Lb_unconfined: .asciz "Run unconfined"
.Lb_confine: .asciz "Confine"
.Ln_docs_none: .asciz "no access to documents"
.Ln_docs_read: .asciz "reads open documents"
.Ln_docs_write: .asciz "reads and changes open documents"
.Ln_proj_none: .asciz ", no access to the project"
.Ln_proj_read: .asciz ", reads the project"
.Ln_proj_write: .asciz ", reads and writes the project"
.Ln_home: .asciz ", reads your home folder"
.Ln_net_no: .asciz ", no network"
.Ln_net_yes: .asciz ", network"
.Ln_terminal: .asciz ", proposes terminal commands"
.Ln_runs: .asciz ", runs: "
.Lc_windows: .asciz "not confined: Windows runs it with your rights"
.Lc_choice: .asciz "runs unconfined (your choice)"
.Lc_when: .asciz "confined by the kernel when it runs"
.Lc_full: .asciz "confined: files and network as declared"
.Lc_tcp: .asciz "confined: files as declared; network cut by TCP rules only (user namespaces unavailable)"
.Lc_none: .asciz "running unconfined"
.Ld_prefix: .asciz "extensions."
