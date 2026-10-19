# notebooks: the keyboard (Jupyter's command and edit modes), the commands, running cells, and what
# the headless tests print and drive (print-notebook, print-nb-output, nb-mode, nb-select, nb-run).
#
#   edit mode     Esc command mode; Shift+Enter run and select below; Ctrl+Enter run; Alt+Enter run
#                 and insert below; Up on the first line / Down on the last: the previous/next cell
#   command mode  Enter edit; Up/k, Down/j select; a/b insert above/below; d d delete; z undo the
#                 last cell operation; m/y markup/code; Alt+Up/Down move; i i interrupt; 0 0
#                 restart (asks); o outputs shown or hidden; the Enter variants as in edit mode
# Every one of them is also a command (notebook.*) in the palette.
.include "rhun.inc"

.equ TWICE_MS, 1000             # d d, i i, 0 0: the second press within this

.bss
.p2align 3
tmp: .zero SB_SIZE

.text

# ---------------- selection and modes ----------------

# nb_select_mode(nb, i, editing): cell i selected (clamped), in edit (1) or command (0) mode
FN nb_select_mode
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rax, [rbx + NB_cells + VEC_len]
    test rax, rax
    jz 9f
    dec rax
    test r12, r12
    jns 1f
    xor r12d, r12d
1:  cmp r12, rax
    jbe 2f
    mov r12, rax
2:  cmp r12, [rbx + NB_sel]
    je 3f
    call vim_leave
    mov [rbx + NB_sel], r12
3:  mov [rbx + NB_editing], r13d
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov rdi, rbx
    call nb_sync_active
    call time_ms
    mov [rip + g_blink_t0], rax
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_select(nb, i): cell i selected in command mode and brought into view
FN nb_select
    push rbx
    mov rbx, rdi
    xor edx, edx
    call nb_select_mode
    mov dword ptr [rbx + NB_reveal], 1
    pop rbx
    ret

# nb_edit(nb): edit mode in the selected cell, its cursor in view
FN nb_edit
    push rbx
    mov rbx, rdi
    mov rsi, [rbx + NB_sel]
    mov edx, 1
    call nb_select_mode
    mov dword ptr [rbx + NB_reveal], 1
    mov dword ptr [rip + g_reveal], 1
    pop rbx
    ret

# nb_cross(nb, dir): edit mode moves to the cell above (-1, the cursor on its last line) or below
#   (1, its first line), keeping the column
nb_cross:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call nb_sel_cell
    mov r13, [rax + NBC_doc]
    mov rdi, r13
    mov rsi, [r13 + DOC_cur]
    call doc_col_of
    mov r14d, eax
    mov rsi, [rbx + NB_sel]
    add rsi, r12
    mov rdi, rbx
    mov edx, 1
    call nb_select_mode
    mov rdi, rbx
    call nb_sel_cell
    mov r13, [rax + NBC_doc]
    xor esi, esi
    test r12, r12
    jns 1f
    mov rsi, [r13 + DOC_nlines]
    dec rsi
1:  mov rdi, r13
    mov edx, r14d
    call doc_pos_at_col
    mov [r13 + DOC_cur], rax
    mov [r13 + DOC_anchor], rax
    mov qword ptr [r13 + DOC_prefx], -1
    mov dword ptr [rbx + NB_reveal], 1
    mov dword ptr [rip + g_reveal], 1
    EPILOGUE

# ---------------- running ----------------

# nb_run(nb, i) -> eax 1 when cell i runs (or is markup): a new run, its outputs cleared, "0 nb-run"
#   now or once the extension runs
FN nb_run
    PROLOGUE
    mov rbx, rdi
    call nb_cell
    test rax, rax
    jz 8f
    mov r12, rax
    cmp dword ptr [r12 + NBC_kind], NBCK_CODE
    jne 7f
    mov rdi, [rbx + NB_ext]
    mov esi, EXT_pv_nbkernel
    call ext_pv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 'n'
    jne 1f
    lea rdi, [rip + .Lno_runs]
    call app_toast
    jmp 8f
1:  inc qword ptr [rip + g_nb_run_seq]
    mov rax, [rip + g_nb_run_seq]
    mov [r12 + NBC_run], rax
    mov dword ptr [r12 + NBC_state], NBRUN_QUEUED
    mov rdi, rbx
    mov rsi, r12
    call nb_clear_outputs
    mov dword ptr [r12 + NBC_unsent], 0
    mov rdi, rbx
    mov rsi, r12
    call nb_send_run
    test eax, eax
    jnz 7f
    mov dword ptr [r12 + NBC_unsent], 1
    mov rdi, [rbx + NB_ext]
    call nb_ext_start_idle
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_ext_start_idle(ext): a notebook's extension starts when it is idle or crashed
nb_ext_start_idle:
    mov eax, [rdi + EXT_status]
    cmp eax, ES_IDLE
    je 1f
    cmp eax, ES_CRASHED
    jne 9f
1:  jmp ext_start
9:  ret

# nb_run_next(nb): run the selected cell and select the one below, a new one past the last
FN nb_run_next
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + NB_sel]
    mov rsi, r12
    call nb_run
    lea r13, [r12 + 1]
    cmp r13, [rbx + NB_cells + VEC_len]
    jb 1f
    mov rdi, rbx
    mov rsi, r13
    mov edx, NBCK_CODE
    call nb_insert_cell
    mov rdi, rbx
    call nb_edit
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, r13
    call nb_select
    EPILOGUE

# nb_run_insert(nb): run the selected cell and insert a code cell below it, to edit
FN nb_run_insert
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + NB_sel]
    mov rsi, r12
    call nb_run
    mov rdi, rbx
    lea rsi, [r12 + 1]
    mov edx, NBCK_CODE
    call nb_insert_cell
    mov rdi, rbx
    call nb_edit
    EPILOGUE

# nb_run_stay(nb): run the selected cell, which stays selected, in command mode
FN nb_run_stay
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + NB_sel]
    call nb_run
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_select
    EPILOGUE

# nb_run_all(nb): every code cell, in order
FN nb_run_all
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rdi, rbx
    mov rsi, r12
    call nb_run
    test eax, eax
    jz 9f
    inc r12
    jmp 1b
9:  EPILOGUE

# nb_interrupt(nb): "0 nb-interrupt NB"
FN nb_interrupt
    lea rsi, [rip + .Lv_interrupt]
    jmp nb_send_simple

# nb_restart_ask(nb): Restart asks first, then "0 nb-restart NB"
FN nb_restart_ask
    lea rdi, [rip + .Lrestart_q]
    lea rsi, [rip + .Lrestart_line]
    lea rdx, [rip + .Lrestart_btn]
    lea rcx, [rip + nb_restart_now]
    jmp app_confirm

# nb_restart_now(): the active notebook's kernel restarts (the dialog's button)
FN nb_restart_now
    call nb_active
    test rax, rax
    jz 9f
    mov rdi, rax
    lea rsi, [rip + .Lv_restart]
    jmp nb_send_simple
9:  ret

# nb_kernel_pick(nb): the kernel button: the extension offers kernels (choose), once it runs
FN nb_kernel_pick
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lv_kernel]
    call nb_send_simple
    test eax, eax
    jnz 9f
    mov rdi, [rbx + NB_ext]
    call nb_ext_start_idle
    lea rdi, [rip + .Lstarting]
    call app_toast
9:  EPILOGUE

# nb_clear_all(nb): every cell's outputs go
FN nb_clear_all
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rsi, [rax + r12*8]
    mov rdi, rbx
    call nb_clear_outputs
    inc r12
    jmp 1b
9:  EPILOGUE

# nb_runs_tick(nb): runs asked while the extension did not run go out once it does; an extension
#   that cannot run cancels them
FN nb_runs_tick
    PROLOGUE
    mov rbx, rdi
    mov r13, [rbx + NB_ext]
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r14, [rax + r12*8]
    inc r12
    cmp dword ptr [r14 + NBC_unsent], 0
    je 1b
    mov eax, [r13 + EXT_status]
    cmp eax, ES_RUNNING
    je 2f
    cmp eax, ES_STARTING
    je 1b
    cmp eax, ES_STOPPING
    je 1b
    cmp eax, ES_IDLE
    je 1b
    mov dword ptr [r14 + NBC_unsent], 0
    mov dword ptr [r14 + NBC_state], NBRUN_CANCELLED
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r14
    call nb_send_run
    test eax, eax
    jnz 3f
    mov dword ptr [r14 + NBC_state], NBRUN_CANCELLED    # running, but it does not speak notebooks
3:  mov dword ptr [r14 + NBC_unsent], 0
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
9:  EPILOGUE

# ---------------- keys ----------------

# twice(nb, key) -> eax 1 when the key is the second of two presses in a row within TWICE_MS
twice:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call time_ms
    mov rcx, rax
    sub rcx, [rbx + NB_lastkeyt]
    mov [rbx + NB_lastkeyt], rax
    cmp [rbx + NB_lastkey], r12
    jne 1f
    cmp rcx, TWICE_MS
    ja 1f
    mov qword ptr [rbx + NB_lastkey], 0
    mov eax, 1
    EPILOGUE
1:  mov [rbx + NB_lastkey], r12
    xor eax, eax
    EPILOGUE

# nb_key(keysym, cp, mods) -> eax 1 when the notebook took the key (app_on_key asks it before the
#   bindings while a notebook tab has the keyboard)
FN nb_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    call nb_active
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 8f
    mov rdi, rbx
    call nb_sel_cell
    test rax, rax
    jz 8f
    mov r15, rax
    # the Enter variants, in both modes
    cmp r12d, KEY_RETURN
    je 1f
    cmp r12d, KEY_KP_ENTER
    jne 2f
1:  test r14d, MOD_ALT
    jz 11f
    mov rdi, rbx
    call nb_run_insert
    jmp 7f
11: test r14d, MOD_CTRL | MOD_SUPER
    jz 12f
    mov rdi, rbx
    call nb_run_stay
    jmp 7f
12: test r14d, MOD_SHIFT
    jz 13f
    mov rdi, rbx
    call nb_run_next
    jmp 7f
13: cmp dword ptr [rbx + NB_editing], 0
    jne 8f
    mov rdi, rbx
    call nb_edit
    jmp 7f
2:  cmp dword ptr [rbx + NB_editing], 0
    je .Lnk_command
    # edit mode: Esc, and Up/Down across cells
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER | MOD_SHIFT
    jnz 8f
    cmp r12d, KEY_ESCAPE
    jne 3f
    cmp dword ptr [rip + cfg_vim], 0
    je 21f
    cmp dword ptr [rip + g_vim_mode], VM_NORMAL
    jne 8f
21: mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_select
    jmp 7f
3:  cmp r12d, KEY_UP
    jne 4f
    cmp qword ptr [rbx + NB_sel], 0
    je 8f
    mov r13, [r15 + NBC_doc]
    mov rdi, r13
    mov rsi, [r13 + DOC_cur]
    call doc_line_of
    test rax, rax
    jnz 8f
    mov rdi, rbx
    mov rsi, -1
    call nb_cross
    jmp 7f
4:  cmp r12d, KEY_DOWN
    jne 8f
    mov rax, [rbx + NB_sel]
    inc rax
    cmp rax, [rbx + NB_cells + VEC_len]
    jae 8f
    mov r13, [r15 + NBC_doc]
    mov rdi, r13
    mov rsi, [r13 + DOC_cur]
    call doc_line_of
    mov rcx, [r13 + DOC_nlines]
    dec rcx
    cmp rax, rcx
    jb 8f
    mov rdi, rbx
    mov esi, 1
    call nb_cross
    jmp 7f
.Lnk_command:
    test r14d, MOD_ALT
    jz 1f
    cmp r12d, KEY_UP
    jne 60f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    mov rdx, -1
    call nb_move_cell
    jmp 7f
60: cmp r12d, KEY_DOWN
    jne 8f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    mov edx, 1
    call nb_move_cell
    jmp 7f
1:  test r14d, MOD_CTRL | MOD_SUPER
    jnz 8f
    cmp r12d, KEY_UP
    je .Lnk_up
    cmp r12d, 'k'
    je .Lnk_up
    cmp r12d, KEY_DOWN
    je .Lnk_down
    cmp r12d, 'j'
    je .Lnk_down
    cmp r12d, KEY_HOME
    jne 2f
    mov rdi, rbx
    xor esi, esi
    call nb_select
    jmp 7f
2:  cmp r12d, KEY_END
    jne 3f
    mov rdi, rbx
    mov rsi, [rbx + NB_cells + VEC_len]
    dec rsi
    call nb_select
    jmp 7f
3:  cmp r12d, KEY_PAGEUP
    jne 4f
    movsxd rax, dword ptr [rbx + NB_vh]
    sub [rbx + NB_scroll], rax
    jmp 7f
4:  cmp r12d, KEY_PAGEDOWN
    jne 5f
    movsxd rax, dword ptr [rbx + NB_vh]
    add [rbx + NB_scroll], rax
    jmp 7f
5:  cmp r12d, KEY_ESCAPE
    je 7f
    test r14d, MOD_ALT
    jnz 8f
    cmp r12d, 'a'
    jne 51f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    mov edx, NBCK_CODE
    call nb_insert_cell
    jmp 7f
51: cmp r12d, 'b'
    jne 52f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    inc rsi
    mov edx, NBCK_CODE
    call nb_insert_cell
    jmp 7f
52: cmp r12d, 'd'
    jne 53f
    mov rdi, rbx
    mov esi, 'd'
    call twice
    test eax, eax
    jz 7f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_delete_cell
    jmp 7f
53: cmp r12d, 'z'
    jne 54f
    mov rdi, rbx
    call nb_undo_op
    jmp 7f
54: cmp r12d, 'm'
    jne 55f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    mov edx, NBCK_MARKUP
    call nb_set_kind
    jmp 7f
55: cmp r12d, 'y'
    jne 56f
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    mov edx, NBCK_CODE
    call nb_set_kind
    jmp 7f
56: cmp r12d, 'i'
    jne 57f
    mov rdi, rbx
    mov esi, 'i'
    call twice
    test eax, eax
    jz 7f
    mov rdi, rbx
    call nb_interrupt
    jmp 7f
57: cmp r12d, '0'
    jne 58f
    mov rdi, rbx
    mov esi, '0'
    call twice
    test eax, eax
    jz 7f
    mov rdi, rbx
    call nb_restart_ask
    jmp 7f
58: cmp r12d, 'o'
    jne 59f
    xor dword ptr [r15 + NBC_collapsed], 1
    jmp 7f
59: # other characters do nothing in command mode
    cmp r13d, 32
    jb 8f
    jmp 7f
.Lnk_up:
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    dec rsi
    call nb_select
    jmp 7f
.Lnk_down:
    mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    inc rsi
    call nb_select
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- commands ----------------

# nb_cmd_target() -> the active notebook when it is open, else 0 (a toast says so)
nb_cmd_target:
    push rbx
    call nb_active
    test rax, rax
    jz 8f
    cmp dword ptr [rax + NB_state], NBS_READY
    jne 8f
    pop rbx
    ret
8:  lea rdi, [rip + .Lnot_notebook]
    call app_toast
    xor eax, eax
    pop rbx
    ret

.macro NBCMD name, fn
FN \name
    call nb_cmd_target
    test rax, rax
    jz 1f
    mov rdi, rax
    jmp \fn
1:  ret
.endm

NBCMD cmd_nb_run_cell, nb_run_stay
NBCMD cmd_nb_run_next, nb_run_next
NBCMD cmd_nb_run_insert, nb_run_insert
NBCMD cmd_nb_run_all, nb_run_all
NBCMD cmd_nb_interrupt, nb_interrupt
NBCMD cmd_nb_restart, nb_restart_ask
NBCMD cmd_nb_kernel, nb_kernel_pick
NBCMD cmd_nb_clear_outputs, nb_clear_all
NBCMD cmd_nb_undo_cell, nb_undo_op
NBCMD cmd_nb_edit, nb_edit
NBCMD cmd_nb_command_mode, nb_command_mode
NBCMD cmd_nb_insert_above, nb_insert_above
NBCMD cmd_nb_insert_below, nb_insert_below
NBCMD cmd_nb_delete_cell, nb_delete_sel
NBCMD cmd_nb_to_markup, nb_to_markup
NBCMD cmd_nb_to_code, nb_to_code
NBCMD cmd_nb_move_up, nb_move_up
NBCMD cmd_nb_move_down, nb_move_down
NBCMD cmd_nb_toggle_outputs, nb_toggle_outputs

FN cmd_nb_open_as_text
    call nb_active
    test rax, rax
    jz 1f
    mov rdi, rax
    jmp nb_open_as_text
1:  ret

nb_command_mode:
    mov rsi, [rdi + NB_sel]
    jmp nb_select
nb_insert_above:
    mov rsi, [rdi + NB_sel]
    mov edx, NBCK_CODE
    jmp nb_insert_cell
nb_insert_below:
    mov rsi, [rdi + NB_sel]
    inc rsi
    mov edx, NBCK_CODE
    jmp nb_insert_cell
nb_delete_sel:
    mov rsi, [rdi + NB_sel]
    jmp nb_delete_cell
nb_to_markup:
    mov rsi, [rdi + NB_sel]
    mov edx, NBCK_MARKUP
    jmp nb_set_kind
nb_to_code:
    mov rsi, [rdi + NB_sel]
    mov edx, NBCK_CODE
    jmp nb_set_kind
nb_move_up:
    mov rsi, [rdi + NB_sel]
    mov rdx, -1
    jmp nb_move_cell
nb_move_down:
    mov rsi, [rdi + NB_sel]
    mov edx, 1
    jmp nb_move_cell
nb_toggle_outputs:
    push rbx
    call nb_sel_cell
    test rax, rax
    jz 1f
    xor dword ptr [rax + NBC_collapsed], 1
    mov dword ptr [rip + g_dirty], 1
1:  pop rbx
    ret

# ---------------- when-clause keys (when.s calls them: rax the value's bytes, rdx their length) ----

# notebookFocus: a notebook tab has the keyboard
FN ck_nb_focus
    call nb_active
    test rax, rax
    jz 8f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 8f
    lea rax, [rip + .Lw_true]
    mov edx, 4
    ret
8:  lea rax, [rip + .Lw_false]
    mov edx, 5
    ret

# notebookCellEditing: and its selected cell is in edit mode
FN ck_nb_editing
    call nb_active
    test rax, rax
    jz 8f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 8f
    cmp dword ptr [rax + NB_editing], 0
    je 8f
    lea rax, [rip + .Lw_true]
    mov edx, 4
    ret
8:  lea rax, [rip + .Lw_false]
    mov edx, 5
    ret

# notebookCellType: "code" or "markup" for the selected cell, empty outside a notebook
FN ck_nb_cell_type
    call nb_active
    test rax, rax
    jz 8f
    mov rdi, rax
    call nb_sel_cell
    test rax, rax
    jz 8f
    cmp dword ptr [rax + NBC_kind], NBCK_CODE
    jne 1f
    lea rax, [rip + .Lw_code]
    mov edx, 4
    ret
1:  lea rax, [rip + .Lw_markup]
    mov edx, 6
    ret
8:  lea rax, [rip + .Lw_false]
    xor edx, edx
    ret

# notebookKernelState: none, idle, busy, starting or dead; empty outside a notebook
FN ck_nb_kernel_state
    call nb_active
    test rax, rax
    jz 8f
    mov eax, [rax + NB_kstate]
    lea rcx, [rip + kernel_names]
    mov rdi, [rcx + rax*8]
    push rdi
    call strlen
    mov rdx, rax
    pop rax
    ret
8:  lea rax, [rip + .Lw_false]
    xor edx, edx
    ret

# ---------------- tests: print and drive ----------------

# nb_dump(sb): print-notebook: a line per cell, then the notebook's state
FN nb_dump
    PROLOGUE 16
    mov r12, rdi
    call nb_active
    mov rbx, rax
    test rbx, rbx
    jnz 1f
    mov rdi, r12
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
    EPILOGUE
1:  cmp dword ptr [rbx + NB_state], NBS_READY
    je 2f
    mov rdi, r12
    lea rsi, [rip + .Ld_opening]
    cmp dword ptr [rbx + NB_state], NBS_OPENING
    je 11f
    lea rsi, [rip + .Ld_failed]
11: call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NB_err + SB_ptr]
    test rsi, rsi
    jz 12f
    call sb_push_cstr
12: mov rdi, r12
    mov esi, 10
    call sb_push_byte
    EPILOGUE
2:  xor r13d, r13d
3:  cmp r13, [rbx + NB_cells + VEC_len]
    jae 5f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r14, [rax + r13*8]
    mov rdi, r12
    lea rsi, [rip + .Ld_cell]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_id]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + NBC_id]
    call sb_push_u64
    lea rsi, [rip + .Ld_code]
    cmp dword ptr [r14 + NBC_kind], NBCK_CODE
    je 31f
    lea rsi, [rip + .Ld_markup]
31: mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_lang]
    call sb_push_cstr
    mov rdi, [r14 + NBC_doc]
    call doc_language
    lea rsi, [rip + .Ldash]
    test rax, rax
    jz 32f
    mov rsi, [rax + GR_name]
32: mov rdi, r12
    call nb_push_word
    mov rdi, r12
    lea rsi, [rip + .Ld_lines]
    call sb_push_cstr
    mov rax, [r14 + NBC_doc]
    mov rdi, r12
    mov rsi, [rax + DOC_nlines]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_count]
    call sb_push_cstr
    mov rsi, [r14 + NBC_count]
    test rsi, rsi
    js 33f
    mov rdi, r12
    call sb_push_u64
    jmp 34f
33: mov rdi, r12
    mov esi, '-'
    call sb_push_byte
34: mov rdi, r12
    lea rsi, [rip + .Ld_state]
    call sb_push_cstr
    mov eax, [r14 + NBC_state]
    lea rcx, [rip + run_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_outputs]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + NBC_outs + VEC_len]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_sel]
    call sb_push_cstr
    xor esi, esi
    cmp r13, [rbx + NB_sel]
    sete sil
    add esi, '0'
    mov rdi, r12
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Ld_editing]
    call sb_push_cstr
    xor esi, esi
    cmp r13, [rbx + NB_sel]
    jne 35f
    mov esi, [rbx + NB_editing]
35: add esi, '0'
    mov rdi, r12
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Ld_hidden]
    call sb_push_cstr
    mov esi, [r14 + NBC_collapsed]
    add esi, '0'
    mov rdi, r12
    call sb_push_byte
    # where its frame was drawn (for clicks), -1 off screen
    mov rdi, r12
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    movsxd rsi, dword ptr [r14 + NBC_y]
    test rsi, rsi
    js 36f
    call nb_frame_x
    mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + NBC_y]
    call sb_push_u64
    jmp 37f
36: mov rdi, r12
    lea rsi, [rip + .Ld_minus]
    call sb_push_cstr
37: mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r13
    jmp 3b
5:  call nb_active
    mov rdi, rax
    call nb_sync_dirty
    mov [rsp], eax
    mov rdi, r12
    lea rsi, [rip + .Ld_dirty]
    call sb_push_cstr
    mov esi, [rsp]
    add esi, '0'
    mov rdi, r12
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Ld_mode]
    call sb_push_cstr
    lea rsi, [rip + .Ld_command]
    cmp dword ptr [rbx + NB_editing], 0
    je 51f
    lea rsi, [rip + .Ld_edit]
51: mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_undo]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NB_undo + VEC_len]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_kstate]
    call sb_push_cstr
    mov eax, [rbx + NB_kstate]
    lea rcx, [rip + kernel_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_kernel]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NB_kernel + SB_ptr]
    mov rdx, [rbx + NB_kernel + SB_len]
    call sb_push
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# nb_push_word(sb, cstr): the name with spaces as _
nb_push_word:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  movzx esi, byte ptr [r12]
    test esi, esi
    jz 9f
    inc r12
    cmp esi, ' '
    jne 2f
    mov esi, '_'
2:  mov rdi, rbx
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# nb_dump_output(sb, i, j): print-nb-output: cell i's output j, its kind, items and text (escapes
#   as \e), then <eoo>
FN nb_dump_output
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    call nb_active
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r13
    call nb_cell
    test rax, rax
    jz 8f
    cmp r14, [rax + NBC_outs + VEC_len]
    jae 8f
    mov rax, [rax + NBC_outs + VEC_ptr]
    mov rbx, [rax + r14*8]
    mov rdi, r12
    lea rsi, [rip + .Ld_kind]
    call sb_push_cstr
    mov eax, [rbx + NBO_kind]
    dec eax
    lea rcx, [rip + nb_ouk_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_oid]
    call sb_push_cstr
    mov rsi, [rbx + NBO_id]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Ldash]
1:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_items]
    call sb_push_cstr
    xor r13d, r13d
2:  cmp r13, [rbx + NBO_items + VEC_len]
    jae 3f
    test r13, r13
    jz 21f
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
21: imul rax, r13, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov rsi, [rax + NBI_name]
    test rsi, rsi
    jnz 22f
    mov ecx, [rax + NBI_type]
    dec ecx
    lea rax, [rip + nb_nit_names]
    mov rsi, [rax + rcx*8]
22: mov rdi, r12
    call sb_push_cstr
    inc r13
    jmp 2b
3:  mov rdi, r12
    lea rsi, [rip + .Ld_show]
    call sb_push_cstr
    mov rsi, [rbx + NBO_show]
    test rsi, rsi
    js 31f
    mov rdi, r12
    call sb_push_u64
    jmp 32f
31: mov rdi, r12
    lea rsi, [rip + .Ld_minus]
    call sb_push_cstr
32: mov rdi, r12
    lea rsi, [rip + .Ld_lines]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NBO_lines]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_bytes]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NBO_bytes]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_keep]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NBO_keep + SB_len]
    call sb_push_u64
    cmp dword ptr [rbx + NBO_ierr], 0
    je 33f
    mov rdi, r12
    lea rsi, [rip + .Ld_ierr]
    call sb_push_cstr
33: cmp qword ptr [rbx + NBO_img], 0
    je 34f
    mov rdi, r12
    lea rsi, [rip + .Ld_image]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rbx + NBO_iw]
    call sb_push_u64
    mov rdi, r12
    mov esi, 'x'
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + NBO_ih]
    call sb_push_u64
34: mov rdi, r12
    mov esi, 10
    call sb_push_byte
    # the text item shown
    mov rax, [rbx + NBO_show]
    test rax, rax
    js 7f
    imul rax, rax, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    cmp dword ptr [rax + NBI_type], NBIT_ANSI
    ja 7f
    mov r13, [rax + NBI_data + SB_ptr]
    mov r14, [rax + NBI_data + SB_len]
    xor r15d, r15d
4:  cmp r15, r14
    jae 6f
    movzx esi, byte ptr [r13 + r15]
    inc r15
    cmp esi, 0x1b
    jne 5f
    mov rdi, r12
    lea rsi, [rip + .Ld_esc]
    call sb_push_cstr
    jmp 4b
5:  mov rdi, r12
    call sb_push_byte
    jmp 4b
6:  test r14, r14
    jz 7f
    cmp byte ptr [r13 + r14 - 1], 10
    je 7f
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
7:  mov rdi, r12
    lea rsi, [rip + .Ld_eoo]
    call sb_push_cstr
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Ld_nooutput]
    call sb_push_cstr
    EPILOGUE

# nb_ctl_mode(ptr, len): nb-mode edit|command
FN nb_ctl_mode
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call nb_cmd_target
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ld_edit_word]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov rdi, rbx
    call nb_edit
    jmp 9f
1:  mov rdi, rbx
    mov rsi, [rbx + NB_sel]
    call nb_select
9:  EPILOGUE

# nb_ctl_select(i): nb-select I
FN nb_ctl_select
    push rbx
    mov rbx, rdi
    call nb_cmd_target
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rbx
    call nb_select
9:  pop rbx
    ret

# nb_ctl_output_tab(i, j): nb-output-tab I J (as the output's Open in Tab)
FN nb_ctl_output_tab
    PROLOGUE
    mov r12, rsi
    mov rbx, rdi
    call nb_cmd_target
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rbx
    call nb_cell
    test rax, rax
    jz 9f
    cmp r12, [rax + NBC_outs + VEC_len]
    jae 9f
    mov rax, [rax + NBC_outs + VEC_ptr]
    mov rdi, [rax + r12*8]
    call nb_output_tab
9:  EPILOGUE

# nb_ctl_run(i): nb-run I (as its run button)
FN nb_ctl_run
    push rbx
    mov rbx, rdi
    call nb_cmd_target
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rbx
    call nb_run
9:  pop rbx
    ret

.section .rodata
.p2align 3
run_names: .quad .Lr_none, .Lr_queued, .Lr_running, .Lr_done, .Lr_failed, .Lr_cancelled
kernel_names: .quad .Lr_none, .Lk_idle, .Lk_busy, .Lk_starting, .Lk_dead
.Lr_none: .asciz "none"
.Lr_queued: .asciz "queued"
.Lr_running: .asciz "running"
.Lr_done: .asciz "done"
.Lr_failed: .asciz "failed"
.Lr_cancelled: .asciz "cancelled"
.Lk_idle: .asciz "idle"
.Lk_busy: .asciz "busy"
.Lk_starting: .asciz "starting"
.Lk_dead: .asciz "dead"
.Lv_interrupt: .asciz "nb-interrupt"
.Lv_restart: .asciz "nb-restart"
.Lv_kernel: .asciz "nb-kernel"
.Lrestart_q: .asciz "Restart the kernel?"
.Lrestart_line: .asciz "Its variables are lost; the outputs stay."
.Lrestart_btn: .asciz "Restart"
.Lstarting: .asciz "The notebook's extension is starting"
.Lno_runs: .asciz "This notebook's extension does not run cells"
.Lnot_notebook: .asciz "No notebook is open in this tab"
.Ldash: .asciz "-"
.Lw_true: .asciz "true"
.Lw_false: .asciz "false"
.Lw_code: .asciz "code"
.Lw_markup: .asciz "markup"
.Ld_none: .asciz "notebook=none\n"
.Ld_opening: .asciz "notebook=opening error="
.Ld_failed: .asciz "notebook=failed error="
.Ld_cell: .asciz "cell="
.Ld_id: .asciz " id="
.Ld_code: .asciz " kind=code"
.Ld_markup: .asciz " kind=markup"
.Ld_lang: .asciz " lang="
.Ld_lines: .asciz " lines="
.Ld_count: .asciz " count="
.Ld_state: .asciz " state="
.Ld_outputs: .asciz " outputs="
.Ld_sel: .asciz " sel="
.Ld_editing: .asciz " editing="
.Ld_hidden: .asciz " hidden="
.Ld_at: .asciz " at="
.Ld_minus: .asciz "-1"
.Ld_dirty: .asciz "dirty="
.Ld_mode: .asciz " mode="
.Ld_command: .asciz "command"
.Ld_edit: .asciz "edit"
.Ld_edit_word: .asciz "edit"
.Ld_undo: .asciz " undo="
.Ld_kstate: .asciz " kstate="
.Ld_kernel: .asciz " kernel="
.Ld_kind: .asciz "output kind="
.Ld_oid: .asciz " id="
.Ld_items: .asciz " items="
.Ld_show: .asciz " show="
.Ld_bytes: .asciz " bytes="
.Ld_keep: .asciz " keep="
.Ld_ierr: .asciz " image=error"
.Ld_image: .asciz " image="
.Ld_esc: .asciz "\\e"
.Ld_eoo: .asciz "<eoo>\n"
.Ld_nooutput: .asciz "output=none\n<eoo>\n"
