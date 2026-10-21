# debug view: the sidebar's Variables, Watch, Call Stack and Breakpoints sections and the bottom
# panel's Debug Console tab (places.s, rtree.s), filled from the session model (dap.s, bp.s), and
# the debugger's commands (F5 and friends, keys.s)
.include "rhun.inc"

.equ DV_SECTIONS, 4
.equ DV_HISTORY_MAX, 100
.equ ID_DCON_INPUT, 0x5e0001
.equ ID_DCON_SCROLL, 0x5e0002
.equ ID_DV_ADDWATCH, 0x5e0003
.equ ID_DV_COLLAPSE, 0x5e0004

.bss
.p2align 3
trees: .zero 8 * DV_SECTIONS    # TR* of Variables, Watch, Call Stack, Breakpoints
synced: .zero 4 * DV_SECTIONS   # the generation each was filled at
idb: .zero SB_SIZE              # a node's id
lab: .zero SB_SIZE              # its label
desc: .zero SB_SIZE
dv_made: .long 0
dv_shown: .long 0               # the user's Show/Hide (debug_show)
.p2align 3
cin: .zero TF_SIZE              # the console's input line
history: .zero SB_SIZE          # its entries, one per line, oldest first
cscroll: .long 0                # console: pixels scrolled up from the end
.globl g_dsel
g_dsel: .zero SB_SIZE           # the selected configuration's name (NUL-terminated), empty: the first
prompt_kind: .long 0            # DP_* while the palette asks for the debugger
prompt_bp: .long 0              # the breakpoint (id) a prompt edits
.p2align 3
prompt_path: .zero SB_SIZE
cfg_first: .zero SB_SIZE        # launch.ini's names, for the status bar
cfg_prev: .zero SB_SIZE         # the names before the last read
tb_rects: .zero 16 * 8          # the toolbar's buttons as last drawn: icon, x, y, size
tb_n: .long 0
cfg_checked: .quad 0
menu_line: .long 0              # a line for the next cursor_line (the gutter menu), 0 none
menu_target: .long 0
ctx_gen: .long 0

.data
.globl g_dv_places, g_debug_show_on_start, g_debug_keys_in_terminal
g_debug_keys_in_terminal: .long 1   # [debug] keys_in_terminal
g_dv_places: .long -1, -1, -1, -1, -1   # the four sections, then the console tab
g_debug_show_on_start: .long 1  # [debug] show_on_start
hist_at: .long -1               # console history: Up/Down position, -1 at the input

.equ DP_COND, 1
.equ DP_HIT, 2
.equ DP_LOG, 3
.equ DP_WATCH, 4
.equ DP_FUNCTION, 5

.text

# ---------------- registration ----------------

# dview_ensure(): the sections and the console tab exist (once)
FN dview_ensure
    PROLOGUE
    cmp dword ptr [rip + dv_made], 0
    jne 9f
    mov dword ptr [rip + dv_made], 1
    xor ebx, ebx
1:  cmp ebx, DV_SECTIONS
    jae 2f
    lea rax, [rip + tree_ops]
    mov rdi, [rax + rbx*8]
    mov esi, ebx                # ctx: the section
    call tree_new
    lea rcx, [rip + trees]
    mov [rcx + rbx*8], rax
    mov edi, PLACE_SIDEBAR
    lea rax, [rip + section_names]
    mov rsi, [rax + rbx*8]
    lea rax, [rip + section_titles]
    mov rdx, [rax + rbx*8]
    lea rcx, [rip + section_ops]
    mov r8d, ebx
    call place_add
    lea rcx, [rip + g_dv_places]
    mov [rcx + rbx*4], eax
    inc ebx
    jmp 1b
2:  mov edi, PLACE_PANEL
    lea rsi, [rip + .Ln_console]
    lea rdx, [rip + .Lt_console]
    lea rcx, [rip + console_ops]
    xor r8d, r8d
    call place_add
    mov [rip + g_dv_places + 16], eax
    mov edi, eax
    mov esi, IC_TERMINAL
    call place_set_icon
    mov dword ptr [rip + cin + TF_id], ID_DCON_INPUT
    # they start hidden; dview_show shows them (on start, or Ctrl+Shift+Y)
    xor ebx, ebx
3:  lea rax, [rip + g_dv_places]
    mov edi, [rax + rbx*4]
    mov esi, 1
    call place_set_hidden
    inc ebx
    cmp ebx, 5
    jb 3b
    mov dword ptr [rip + dv_shown], 0
9:  EPILOGUE

# dview_session_started(): a session began: the view shows ([debug] show_on_start)
FN dview_session_started
    PROLOGUE
    call dview_ensure
    cmp dword ptr [rip + g_debug_show_on_start], 0
    je 9f
    mov dword ptr [rip + dv_shown], 0
    call dview_show
9:  EPILOGUE

# dview_show(): Show/Hide the sections and the console (Ctrl+Shift+Y)
FN dview_show
    PROLOGUE
    call dview_ensure
    xor eax, eax
    cmp dword ptr [rip + dv_shown], 0
    sete al
    mov [rip + dv_shown], eax
    mov r12d, eax
    xor ebx, ebx
1:  cmp ebx, 5
    jae 2f
    lea rax, [rip + g_dv_places]
    mov edi, [rax + rbx*4]
    mov esi, r12d
    xor esi, 1
    call place_set_hidden
    inc ebx
    jmp 1b
2:  test r12d, r12d
    jnz 3f
    # hidden: a section or the console with the keyboard gives it back to the editor
    cmp dword ptr [rip + g_focus], FOCUS_VIEW
    jne 9f
    call place_focused
    xor ebx, ebx
21: lea rcx, [rip + g_dv_places]
    cmp eax, [rcx + rbx*4]
    je 22f
    inc ebx
    cmp ebx, 5
    jb 21b
    jmp 9f
22: mov dword ptr [rip + g_focus], FOCUS_EDITOR
    jmp 9f
3:  mov edi, [rip + g_dv_places]
    xor esi, esi
    call place_show
    mov edi, [rip + g_dv_places + 16]
    xor esi, esi
    call place_show
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# dview_tree(section) -> rax its TR*, or 0 before the view exists (tests)
FN dview_tree
    xor eax, eax
    cmp edi, DV_SECTIONS
    jae 1f
    lea rax, [rip + trees]
    mov rax, [rax + rdi*8]
1:  ret

# dview_sync_all(): every tree filled now (tests look at them without drawing)
FN dview_sync_all
    PROLOGUE
    cmp dword ptr [rip + dv_made], 0
    je 9f
    xor ebx, ebx
1:  cmp ebx, DV_SECTIONS
    jae 9f
    mov edi, ebx
    call sync
    inc ebx
    jmp 1b
9:  EPILOGUE

# ---------------- sections ----------------

# section_draw(ctx = section, x, y, w, h)
section_draw:
    PROLOGUE 16
    mov ebx, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov edi, ebx
    call sync
    call place_focused
    lea rcx, [rip + g_dv_places]
    xor r9d, r9d
    cmp eax, [rcx + rbx*4]
    sete r9b
    lea rax, [rip + trees]
    mov rdi, [rax + rbx*8]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call tree_draw
    EPILOGUE

# section_key(ctx, keysym, cp, mods) -> eax: the tree's keys; Delete removes a watch or breakpoint
section_key:
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    cmp r12d, KEY_DELETE
    jne 1f
    mov edi, ebx
    call delete_cursor
    test eax, eax
    jnz 9f
1:  lea rax, [rip + trees]
    mov rdi, [rax + rbx*8]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tree_key
9:  EPILOGUE

# section_actions(ctx, right, y, h) -> eax the x left of its header buttons: Watch has + (add),
#   Variables a collapse-all
section_actions:
    PROLOGUE 16
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov eax, r12d
    cmp ebx, 1
    jne 9f
    M ecx, MI_24
    sub r12d, ecx
    mov edi, ID_DV_ADDWATCH
    mov esi, r12d
    mov edx, r13d
    mov r8d, r14d
    mov r9d, IC_PLUS
    call ui_icon_btn
    test eax, UB_CLICK
    jz 1f
    call cmd_debug_add_watch
1:  mov eax, r12d
9:  EPILOGUE

# delete_cursor(section) -> eax 1 when Delete removed the watch or breakpoint under the cursor
delete_cursor:
    PROLOGUE
    mov ebx, edi
    lea rax, [rip + trees]
    mov r12, [rax + rbx*8]
    mov rdi, r12
    call tree_cursor
    test eax, eax
    js 8f
    mov r13d, eax
    mov rdi, r12
    mov esi, r13d
    call tree_node_id
    mov r14, rax
    mov r15, rdx
    cmp ebx, 1
    jne 2f
    # a watch root: "watch:EXPR"
    cmp r15, 6
    jbe 8f
    mov rdi, r14
    mov esi, 6
    lea rdx, [rip + .Lwatch_prefix]
    call str_eq_cstr
    test eax, eax
    jz 8f
    xor ecx, ecx
1:  lea rax, [r14 + 6 + rcx]
    cmp rcx, r15
    jae 11f
    inc rcx
    jmp 1b
11: lea rdi, [r14 + 6]
    lea rsi, [r15 - 6]
    call dap_watch_remove
    call bp_save_soon
    mov eax, 1
    EPILOGUE
2:  cmp ebx, 3
    jne 8f
    mov rdi, r12
    mov esi, r13d
    call tree_user
    test eax, eax
    jz 8f
    cmp eax, 0x40000000
    jae 8f                      # an exception filter
    lea edi, [rax - 1]
    call bp_index_of_id
    test eax, eax
    js 8f
    mov edi, eax
    call bp_remove
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sync(section): the tree filled from the model when it changed
sync:
    PROLOGUE
    mov ebx, edi
    mov eax, [rip + g_dap_gen]
    add eax, [rip + g_bp_gen]
    lea rcx, [rip + synced]
    cmp [rcx + rbx*4], eax
    je 9f
    mov [rcx + rbx*4], eax
    lea rax, [rip + trees]
    mov r12, [rax + rbx*8]
    lea rax, [rip + sync_fns]
    mov rdi, r12
    call [rax + rbx*8]
9:  EPILOGUE

# ---------------- Variables and Watch ----------------

# sync_vars(tr): the focused session's scopes and the variables opened under them
sync_vars:
    xor esi, esi
    jmp sync_roots
# sync_watch(tr): the watch expressions; their values and children while paused
sync_watch:
    mov esi, 1
sync_roots:
    PROLOGUE 16
    mov r12, rdi
    mov [rsp], esi              # 1: watch roots
    call dap_focused
    mov rbx, rax
    mov rdi, r12
    xor esi, esi
    call tree_kids_begin
    test rbx, rbx
    jz 5f
    cmp dword ptr [rsp], 0
    je 1f
    cmp dword ptr [rbx + DS_state], DSS_PAUSED
    je 1f
    test dword ptr [rbx + DS_flags], DSF_STALE
    jz 5f
1:  xor r13d, r13d
2:  cmp r13, [rbx + DS_vars + VEC_len]
    jae 3f
    mov rdi, rbx
    mov esi, r13d
    call root_kind
    cmp eax, [rsp]
    jne 21f
    mov rdi, r12
    mov rsi, rbx
    mov edx, r13d
    call list_vn
21: inc r13
    jmp 2b
3:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    xor r13d, r13d
4:  cmp r13, [rbx + DS_vars + VEC_len]
    jae 9f
    mov rdi, rbx
    mov esi, r13d
    call root_kind
    cmp eax, [rsp]
    jne 41f
    mov rdi, r12
    mov rsi, rbx
    mov edx, r13d
    call list_children
41: inc r13
    jmp 4b
5:  # no values to show: the watch expressions alone
    cmp dword ptr [rsp], 0
    je 8f
    xor r13d, r13d
6:  mov edi, r13d
    call dap_watch_text
    test rax, rax
    jz 8f
    mov r14, rax
    mov r15, rdx
    lea rdi, [rip + idb]
    lea rsi, [rip + .Lwatch_prefix]
    call sb_setc
    lea rdi, [rip + idb]
    mov rsi, r14
    mov rdx, r15
    call sb_push
    mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    mov rcx, r14
    mov r8, r15
    mov r9d, KIDS_LEAF
    call tree_kid
    test eax, eax
    js 7f
    mov rdi, r12
    mov esi, eax
    lea rdx, [rip + .Lnot_available]
    mov ecx, .Lnot_available_end - .Lnot_available
    call tree_set_desc
7:  inc r13d
    jmp 6b
8:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
9:  EPILOGUE

# root_kind(ds, node) -> eax 0 a scope, 1 a watch result, -1 not a root
root_kind:
    push rbx
    call vn_node
    mov rcx, rax
    mov eax, -1
    cmp dword ptr [rcx + VN_parent], -1
    jne 1f
    mov eax, [rcx + VN_flags]
    and eax, VNF_WATCH
    setnz al
    movzx eax, al
1:  pop rbx
    ret

# list_vn(tr, ds, node): one tree_kid for a variable node: id its path, label "name = value", desc its
#   type; children open as the model has them
list_vn:
    PROLOGUE 16
    mov r12, rdi
    mov rbx, rsi
    mov r13d, edx
    mov rdi, rbx
    mov esi, r13d
    call dap_node_path
    lea rdi, [rip + idb]
    mov rsi, [rip + g_nodep + SB_ptr]
    mov rdx, [rip + g_nodep + SB_len]
    call sb_set
    mov rdi, rbx
    mov esi, r13d
    call vn_node
    mov r14, rax
    # label
    lea rdi, [rip + lab]
    call sb_clear
    mov ecx, [r14 + VN_name]
    mov rsi, [rbx + DS_strs + SB_ptr]
    add rsi, rcx
    mov edx, [r14 + VN_namelen]
    lea rdi, [rip + lab]
    call sb_push
    cmp dword ptr [r14 + VN_valuelen], 0
    je 1f
    lea rdi, [rip + lab]
    lea rsi, [rip + .Leq]
    call sb_push_cstr
    mov ecx, [r14 + VN_value]
    mov rsi, [rbx + DS_strs + SB_ptr]
    add rsi, rcx
    mov edx, [r14 + VN_valuelen]
    lea rdi, [rip + lab]
    call sb_push
1:  mov r9d, KIDS_LEAF
    cmp qword ptr [r14 + VN_ref], 0
    je 2f
    mov r9d, KIDS_CLOSED
    test dword ptr [r14 + VN_flags], VNF_EXPANDED
    jz 2f
    mov r9d, KIDS_OPEN
2:  mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    mov rcx, [rip + lab + SB_ptr]
    mov r8, [rip + lab + SB_len]
    call tree_kid
    test eax, eax
    js 9f
    mov r15d, eax
    mov rdi, r12
    mov esi, r15d
    lea edx, [r13 + 1]
    call tree_set_user
    mov ecx, [r14 + VN_type]
    mov rdx, [rbx + DS_strs + SB_ptr]
    add rdx, rcx
    mov ecx, [r14 + VN_typelen]
    mov rdi, r12
    mov esi, r15d
    call tree_set_desc
    mov edx, -1
    test dword ptr [rbx + DS_flags], DSF_STALE
    jz 3f
    mov edx, T_MUTED
3:  test dword ptr [r14 + VN_flags], VNF_ERROR
    jz 4f
    mov edx, T_ERROR
4:  mov rdi, r12
    mov esi, r15d
    call tree_set_color
9:  EPILOGUE

# list_children(tr, ds, node): the open node's children listed under it, and theirs
list_children:
    PROLOGUE 16
    mov r12, rdi
    mov rbx, rsi
    mov r13d, edx
    mov rdi, rbx
    mov esi, r13d
    call vn_node
    test dword ptr [rax + VN_flags], VNF_EXPANDED
    jz 9f
    mov r14d, [rax + VN_kid0]
    test r14d, r14d
    js 9f
    mov r15d, [rax + VN_nkids]
    add r15d, r14d
    mov rdi, rbx
    mov esi, r13d
    call dap_node_path
    mov rdi, r12
    mov rsi, [rip + g_nodep + SB_ptr]
    mov rdx, [rip + g_nodep + SB_len]
    call tree_find
    test eax, eax
    js 9f
    mov rdi, r12
    mov esi, eax
    call tree_kids_begin
    mov [rsp], r14d
1:  cmp r14d, r15d
    jae 2f
    mov rdi, r12
    mov rsi, rbx
    mov edx, r14d
    call list_vn
    inc r14d
    jmp 1b
2:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    mov r14d, [rsp]
3:  cmp r14d, r15d
    jae 9f
    mov rdi, r12
    mov rsi, rbx
    mov edx, r14d
    call list_children
    inc r14d
    jmp 3b
9:  EPILOGUE

# vars_expand(ctx, tr, node, on): the user opened or closed a variable
vars_expand:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    call dap_focused
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, r12
    mov esi, r13d
    call tree_user
    test eax, eax
    jz 9f
    lea esi, [rax - 1]
    cmp rsi, [rbx + DS_vars + VEC_len]
    jae 9f
    mov rdi, rbx
    test r14d, r14d
    jz 1f
    call vn_expand
    jmp 9f
1:  call vn_collapse
9:  EPILOGUE

# vars_load(ctx, tr, node): an open node on screen wants its children
vars_load:
    mov ecx, 1
    jmp vars_expand

# ---------------- Call Stack ----------------

# sync_stack(tr): sessions, the focused session's threads, the focused thread's frames
sync_stack:
    PROLOGUE 32
    mov r12, rdi
    mov rdi, r12
    xor esi, esi
    call tree_kids_begin
    xor r13d, r13d
1:  cmp r13d, DS_MAX
    jae 3f
    mov edi, r13d
    call dap_slot
    mov rbx, rax
    cmp dword ptr [rbx + DS_state], DSS_FREE
    je 2f
    # id s<ID>, label the name, desc the state
    lea rdi, [rip + idb]
    call sb_clear
    lea rdi, [rip + idb]
    mov esi, 's'
    call sb_push_byte
    lea rdi, [rip + idb]
    mov esi, [rbx + DS_id]
    call sb_push_u64
    mov rcx, [rbx + DS_name]
    test rcx, rcx
    jnz 11f
    lea rcx, [rip + .Lunnamed]
11: mov rdi, rcx
    call strlen
    mov r8, rax
    mov rcx, [rbx + DS_name]
    test rcx, rcx
    jnz 12f
    lea rcx, [rip + .Lunnamed]
12: mov r9d, KIDS_OPEN
    cmp qword ptr [rbx + DS_threads + VEC_len], 0
    jne 13f
    cmp qword ptr [rbx + DS_frames + VEC_len], 0
    jne 13f
    mov r9d, KIDS_LEAF
13: mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    call tree_kid
    test eax, eax
    js 2f
    mov r14d, eax
    mov rdi, r12
    mov esi, eax
    lea edx, [r13 + 1]
    call tree_set_user
    mov rdi, rbx
    call session_desc
    mov rdi, r12
    mov esi, r14d
    mov rdx, [rip + desc + SB_ptr]
    mov rcx, [rip + desc + SB_len]
    call tree_set_desc
2:  inc r13d
    jmp 1b
3:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    # under each session: its threads (the stopped one with its frames)
    xor r13d, r13d
4:  cmp r13d, DS_MAX
    jae 9f
    mov edi, r13d
    call dap_slot
    mov rbx, rax
    cmp dword ptr [rbx + DS_state], DSS_FREE
    je 5f
    mov rdi, r12
    mov rsi, rbx
    call list_threads
5:  inc r13d
    jmp 4b
9:  EPILOGUE

# session_desc(ds): desc = its state (and why it stopped)
session_desc:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + desc]
    call sb_clear
    mov edi, [rbx + DS_state]
    call dap_state_name
    lea rdi, [rip + desc]
    mov rsi, rax
    call sb_push_cstr
    cmp dword ptr [rbx + DS_state], DSS_PAUSED
    jne 9f
    mov rsi, [rbx + DS_reason]
    test rsi, rsi
    jz 9f
    lea rdi, [rip + desc]
    lea rsi, [rip + .Lon]
    call sb_push_cstr
    lea rdi, [rip + desc]
    mov rsi, [rbx + DS_reason]
    call sb_push_cstr
9:  EPILOGUE

# list_threads(tr, ds)
list_threads:
    PROLOGUE 16
    mov r12, rdi
    mov rbx, rsi
    lea rdi, [rip + idb]
    call sb_clear
    lea rdi, [rip + idb]
    mov esi, 's'
    call sb_push_byte
    lea rdi, [rip + idb]
    mov esi, [rbx + DS_id]
    call sb_push_u64
    mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    call tree_find
    test eax, eax
    js 9f
    mov [rsp], eax
    mov rdi, r12
    mov esi, eax
    call tree_kids_begin
    xor r13d, r13d
1:  cmp r13, [rbx + DS_threads + VEC_len]
    jae 2f
    imul r14, r13, THR_SIZE
    add r14, [rbx + DS_threads + VEC_ptr]
    call thread_id
    mov ecx, [r14 + THR_name]
    add rcx, [rbx + DS_strs + SB_ptr]
    mov r8d, [r14 + THR_namelen]
    mov r9d, KIDS_LEAF
    mov rax, [r14 + THR_id]
    cmp rax, [rbx + DS_thread]
    jne 11f
    mov r9d, KIDS_OPEN
11: mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    call tree_kid
    inc r13
    jmp 1b
2:  # frames without a thread list yet: directly under the session
    cmp qword ptr [rbx + DS_threads + VEC_len], 0
    jne 3f
    mov rdi, r12
    xor esi, esi
    call tree_kids_end
    mov rdi, r12
    mov esi, [rsp]
    mov rdx, rbx
    call list_frames
    EPILOGUE
3:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    # the focused thread's frames
    xor r13d, r13d
4:  cmp r13, [rbx + DS_threads + VEC_len]
    jae 9f
    imul r14, r13, THR_SIZE
    add r14, [rbx + DS_threads + VEC_ptr]
    mov rax, [r14 + THR_id]
    cmp rax, [rbx + DS_thread]
    jne 5f
    call thread_id
    mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    call tree_find
    test eax, eax
    js 9f
    mov rdi, r12
    mov esi, eax
    mov rdx, rbx
    call list_frames
    jmp 9f
5:  inc r13
    jmp 4b
9:  EPILOGUE
# thread_id: idb = "s<ID>/t<thread id>" for thread r14 of session rbx
thread_id:
    lea rdi, [rip + idb]
    call sb_clear
    lea rdi, [rip + idb]
    mov esi, 's'
    call sb_push_byte
    lea rdi, [rip + idb]
    mov esi, [rbx + DS_id]
    call sb_push_u64
    lea rdi, [rip + idb]
    lea rsi, [rip + .Lslash_t]
    call sb_push_cstr
    lea rdi, [rip + idb]
    mov rsi, [r14 + THR_id]
    jmp sb_push_u64

# list_frames(tr, parent node, ds): frame nodes "s<ID>/f<I>", label the function, desc file:line;
#   the focused one marked
list_frames:
    PROLOGUE 16
    mov r12, rdi
    mov [rsp], esi
    mov rbx, rdx
    mov rdi, r12
    mov esi, [rsp]
    call tree_kids_begin
    xor r13d, r13d
1:  cmp r13, [rbx + DS_frames + VEC_len]
    jae 8f
    imul r14, r13, FR_SIZE
    add r14, [rbx + DS_frames + VEC_ptr]
    lea rdi, [rip + idb]
    call sb_clear
    lea rdi, [rip + idb]
    mov esi, 's'
    call sb_push_byte
    lea rdi, [rip + idb]
    mov esi, [rbx + DS_id]
    call sb_push_u64
    lea rdi, [rip + idb]
    lea rsi, [rip + .Lslash_f]
    call sb_push_cstr
    lea rdi, [rip + idb]
    mov rsi, r13
    call sb_push_u64
    mov ecx, [r14 + FR_name]
    add rcx, [rbx + DS_strs + SB_ptr]
    mov r8d, [r14 + FR_namelen]
    mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    mov r9d, KIDS_LEAF
    call tree_kid
    test eax, eax
    js 7f
    mov r15d, eax
    mov rdi, r12
    mov esi, r15d
    lea rdx, [r13 + 1]
    call tree_set_user
    # desc: basename:line
    lea rdi, [rip + desc]
    call sb_clear
    mov ecx, [r14 + FR_path]
    mov rdi, [rbx + DS_strs + SB_ptr]
    add rdi, rcx
    mov esi, [r14 + FR_pathlen]
    call path_basename
    lea rdi, [rip + desc]
    mov rsi, rax
    call sb_push
    cmp dword ptr [r14 + FR_line], 0
    je 2f
    lea rdi, [rip + desc]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + desc]
    mov esi, [r14 + FR_line]
    call sb_push_u64
2:  mov rdi, r12
    mov esi, r15d
    mov rdx, [rip + desc + SB_ptr]
    mov rcx, [rip + desc + SB_len]
    call tree_set_desc
    mov edx, -1
    cmp r13d, [rbx + DS_frame]
    jne 3f
    mov rdi, r12
    mov esi, r15d
    mov edx, IC_ARROW_UP + 0     # the focused frame
    mov edx, IC_CHEV_R
    mov ecx, T_WARNING
    call tree_set_icon
    jmp 7f
3:  cmp dword ptr [r14 + FR_hint], 0
    je 7f
    mov rdi, r12
    mov esi, r15d
    mov edx, T_MUTED
    call tree_set_color
7:  inc r13
    jmp 1b
8:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    EPILOGUE

# stack_activate(ctx, tr, node): a session node focuses that session; a frame node focuses the frame
stack_activate:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov rdi, r12
    mov esi, r13d
    call tree_node_id
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    mov esi, r13d
    call tree_user
    test eax, eax
    jz 9f
    mov ebx, eax
    # "s<ID>" alone: a session; "s<ID>/f<I>": a frame of that session (focused first)
    mov rcx, r15
1:  test rcx, rcx
    jz 2f
    cmp byte ptr [r14 + rcx - 1], '/'
    je 3f
    dec rcx
    jmp 1b
2:  lea edi, [rbx - 1]
    call dap_focus_slot
    jmp 9f
3:  cmp byte ptr [r14 + rcx], 'f'
    jne 9f
    # the session's id: the digits after the leading s
    xor edi, edi
    mov rdx, 1
4:  cmp rdx, rcx
    jae 5f
    movzx eax, byte ptr [r14 + rdx]
    sub eax, '0'
    cmp eax, 9
    ja 5f
    imul edi, edi, 10
    add edi, eax
    inc rdx
    jmp 4b
5:  call dap_slot_of_id
    test rax, rax
    jz 9f
    mov r15, rax
    mov rdi, rax
    call dap_focus_ds
    mov rdi, r15
    lea esi, [rbx - 1]
    call dap_focus_frame
9:  EPILOGUE

# ---------------- Breakpoints ----------------

# sync_bps(tr): a node per breakpoint (checkbox: enabled; desc: its condition, hit count or log
#   message; icon: as the focused session reports it), then the exception filters
sync_bps:
    PROLOGUE 16
    mov r12, rdi
    call bp_ensure_loaded
    mov rdi, r12
    xor esi, esi
    call tree_kids_begin
    mov eax, [rip + g_dfocus]
    mov [rsp], eax
    xor r13d, r13d
1:  call bp_count
    cmp r13, rax
    jae 5f
    mov rdi, r13
    call bp_row
    mov rbx, rax
    lea rdi, [rip + idb]
    call sb_clear
    lea rdi, [rip + idb]
    mov esi, 'b'
    call sb_push_byte
    lea rdi, [rip + idb]
    mov esi, [rbx + BP_id]
    call sb_push_u64
    # label: file:line, or the function's name()
    lea rdi, [rip + lab]
    call sb_clear
    mov rdi, [rbx + BP_path]
    call strlen
    cmp dword ptr [rbx + BP_kind], 0
    jne 11f
    mov rdi, [rbx + BP_path]
    mov rsi, rax
    call path_basename
    lea rdi, [rip + lab]
    mov rsi, rax
    call sb_push
    lea rdi, [rip + lab]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + lab]
    mov esi, [rbx + BP_line]
    call sb_push_u64
    jmp 12f
11: lea rdi, [rip + lab]
    mov rsi, [rbx + BP_path]
    call sb_push_cstr
    lea rdi, [rip + lab]
    lea rsi, [rip + .Lparens]
    call sb_push_cstr
12: mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    mov rcx, [rip + lab + SB_ptr]
    mov r8, [rip + lab + SB_len]
    mov r9d, KIDS_LEAF
    call tree_kid
    test eax, eax
    js 4f
    mov r14d, eax
    mov rdi, r12
    mov esi, r14d
    mov edx, [rbx + BP_id]
    inc edx
    call tree_set_user
    mov rdi, r12
    mov esi, r14d
    mov edx, [rbx + BP_enabled]
    call tree_set_check
    # desc
    lea rdi, [rip + desc]
    call sb_clear
    lea rsi, [rip + .Lif]
    mov rdx, [rbx + BP_cond]
    call desc_opt
    lea rsi, [rip + .Lhits]
    mov rdx, [rbx + BP_hit]
    call desc_opt
    lea rsi, [rip + .Llog]
    mov rdx, [rbx + BP_log]
    call desc_opt
    mov ecx, [rsp]
    test ecx, ecx
    js 2f
    mov rsi, [rbx + BP_msg + rcx*8]
    test rsi, rsi
    jz 2f
    lea rsi, [rip + .Lsep]
    mov rdx, [rbx + BP_msg + rcx*8]
    call desc_opt
2:  mov rdi, r12
    mov esi, r14d
    mov rdx, [rip + desc + SB_ptr]
    mov rcx, [rip + desc + SB_len]
    call tree_set_desc
    # icon: red dot; hollow (muted) when unverified, a warning color when rejected, grey disabled
    mov ecx, T_ERROR
    cmp dword ptr [rbx + BP_enabled], 0
    jne 21f
    mov ecx, T_MUTED
    jmp 3f
21: mov eax, [rsp]
    test eax, eax
    js 3f
    mov eax, [rbx + BP_ver + rax*4]
    cmp eax, 1
    jne 22f
    mov ecx, T_MUTED
    jmp 3f
22: cmp eax, 3
    jne 3f
    mov ecx, T_WARNING
3:  mov rdi, r12
    mov esi, r14d
    mov edx, IC_DOT
    call tree_set_icon
4:  inc r13
    jmp 1b
5:  # the focused session's exception filters
    call dap_focused
    test rax, rax
    jz 8f
    mov rbx, rax
    mov r13, [rbx + DS_filters + SB_ptr]
    mov r15, [rbx + DS_filters + SB_len]
    add r15, r13
    xor r14d, r14d              # filter index
6:  cmp r13, r15
    jae 8f
    # FILTER \t LABEL \t DEFAULT \n
    mov rcx, r13
61: cmp byte ptr [rcx], 9
    je 62f
    inc rcx
    jmp 61b
62: mov [rsp + 8], rcx
    lea rdi, [rip + idb]
    lea rsi, [rip + .Lx_prefix]
    call sb_setc
    lea rdi, [rip + idb]
    mov rsi, r13
    mov rdx, [rsp + 8]
    sub rdx, r13
    call sb_push
    mov rcx, [rsp + 8]
    inc rcx
    mov rdx, rcx
63: cmp byte ptr [rdx], 9
    je 64f
    inc rdx
    jmp 63b
64: mov r8, rdx
    sub r8, rcx
    push rdx
    push rdx
    mov rdi, r12
    mov rsi, [rip + idb + SB_ptr]
    mov rdx, [rip + idb + SB_len]
    mov r9d, KIDS_LEAF
    call tree_kid
    pop rdx
    pop rdx
    movzx ecx, byte ptr [rdx + 1]
    sub ecx, '0'
    lea r13, [rdx + 3]          # past "\tD\n"
    test eax, eax
    js 66f
    push rcx
    push rax
    mov rdi, r12
    mov esi, eax
    lea edx, [r14 + 0x40000001]
    call tree_set_user
    # checked: the user's choice, else the adapter's default
    mov rdi, rbx
    mov rsi, [rip + idb + SB_ptr]
    add rsi, 2
    mov rdx, [rip + idb + SB_len]
    sub rdx, 2
    call exc_enabled
    pop rsi
    pop rcx
    cmp eax, -1
    jne 65f
    mov eax, ecx
65: mov edx, eax
    mov rdi, r12
    call tree_set_check
66: inc r14d
    jmp 6b
8:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    EPILOGUE
# desc_opt: rdx (cstr or 0) appended to desc after the label rsi
desc_opt:
    test rdx, rdx
    jz 1f
    push rdx
    push rdx
    cmp qword ptr [rip + desc + SB_len], 0
    je 2f
    push rsi
    push rsi
    lea rdi, [rip + desc]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    pop rsi
2:  lea rdi, [rip + desc]
    call sb_push_cstr
    pop rsi
    pop rsi
    lea rdi, [rip + desc]
    jmp sb_push_cstr
1:  ret

# bps_check(ctx, tr, node, state): a checkbox: a breakpoint enabled or not, an exception filter on
#   or off for the focused session's debugger type
bps_check:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov rdi, r12
    mov esi, r13d
    call tree_user
    test eax, eax
    jz 9f
    cmp eax, 0x40000000
    jae 2f
    lea edi, [rax - 1]
    call bp_index_of_id
    test eax, eax
    js 9f
    mov edi, eax
    mov esi, r14d
    call bp_enable
    jmp 9f
2:  call dap_focused
    test rax, rax
    jz 9f
    mov edi, [rax + DS_dbg]
    call dbg_row
    mov rbx, [rax + DBG_type]
    mov rdi, r12
    mov esi, r13d
    call tree_node_id
    lea rsi, [rax + 2]          # "x:FILTER"
    lea rdx, [rdx - 2]
    mov rdi, rbx
    mov ecx, r14d
    call bp_exc_set
9:  EPILOGUE

# bps_activate(ctx, tr, node): a line breakpoint's file opens at its line
bps_activate:
    PROLOGUE
    mov rdi, rsi
    mov esi, edx
    call tree_user
    test eax, eax
    jz 9f
    cmp eax, 0x40000000
    jae 9f
    lea edi, [rax - 1]
    call bp_index_of_id
    test eax, eax
    js 9f
    mov edi, eax
    call bp_row
    mov rbx, rax
    cmp dword ptr [rbx + BP_kind], 0
    jne 9f
    mov rdi, [rbx + BP_path]
    call app_open_file
    test rax, rax
    js 9f
    mov edi, [rbx + BP_line]
    mov esi, 1
    call app_goto_line
9:  EPILOGUE

# ---------------- the console ----------------

# console_draw(ctx, x, y, w, h): the lines (the last at the bottom, colored by category) and the
#   input line
console_draw:
    PROLOGUE 48
    mov [rsp], esi              # x
    mov [rsp + 4], edx          # y
    mov [rsp + 8], ecx          # w
    mov [rsp + 12], r8d         # h
    mov edi, esi
    mov esi, edx
    mov edx, ecx
    mov ecx, r8d
    COLOR r8d, T_PANEL
    call gfx_fill
    # the input line at the bottom
    M eax, MI_ROW
    mov [rsp + 16], eax         # row height
    mov ecx, [rsp + 4]
    add ecx, [rsp + 12]
    sub ecx, eax
    mov [rsp + 20], ecx         # input y
    call place_focused
    xor r9d, r9d
    cmp eax, [rip + g_dv_places + 16]
    sete r9b
    lea rdi, [rip + cin]
    mov esi, [rsp]
    M eax, MI_8
    add esi, eax
    mov edx, [rsp + 20]
    mov ecx, [rsp + 8]
    M eax, MI_16
    sub ecx, eax
    mov r8d, [rsp + 16]
    lea rax, [rip + .Lph_eval]
    push rax
    push rax
    call ui_textfield
    add rsp, 16
    # the lines, from the last up
    mov eax, [rip + g_face_code + FACE_lineh]
    mov [rsp + 24], eax         # line height
    # scrolled up into history: the newest lines move down, below the view (clipped)
    call dcon_count
    imul eax, [rsp + 24]
    mov ecx, [rsp + 20]
    sub ecx, [rsp + 4]          # the lines' room
    sub eax, ecx
    jns 61f
    xor eax, eax
61: cmp [rip + cscroll], eax
    jle 62f
    mov [rip + cscroll], eax    # no further than the oldest line
62: mov ecx, [rsp + 20]
    add ecx, [rip + cscroll]
    mov [rsp + 28], ecx         # bottom of the next line up
    mov esi, [rsp + 4]
    mov ecx, [rsp + 20]
    sub ecx, esi
    mov edi, [rsp]
    mov edx, [rsp + 8]
    call gfx_clip_push
    call dcon_count
    mov r12, rax                # lines
1:  test r12, r12
    jz 4f
    mov eax, [rsp + 28]
    cmp eax, [rsp + 4]
    jle 4f
    dec r12
    mov rdi, r12
    call dcon_get
    mov r13, rax
    mov r14, rdx
    mov edi, ecx
    call cat_color
    mov r15d, eax
    mov eax, [rsp + 28]
    sub eax, [rsp + 24]
    mov [rsp + 28], eax
    # the category of an input line shows as "> "
    mov edi, [rsp]
    M eax, MI_8
    add edi, eax
    mov [rsp + 32], edi
    mov rdi, r12
    call dcon_get
    cmp ecx, DCON_INPUT
    jne 2f
    lea rdi, [rip + g_face_code]
    mov esi, [rsp + 32]
    mov edx, [rsp + 28]
    mov ecx, [rsp + 24]
    lea r8, [rip + .Lgt]
    mov r9d, r15d
    call ui_text_c
    mov [rsp + 32], eax
2:  lea rdi, [rip + g_face_code]
    mov esi, [rsp + 32]
    mov edx, [rsp + 28]
    mov ecx, [rsp + 24]
    mov r8, r13
    mov r9, r14
    push r15
    push r15
    call ui_text_v
    add rsp, 16
    jmp 1b
4:  call gfx_clip_pop
    # the wheel scrolls the lines
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 9f
    mov eax, [rip + g_scroll_y]
    test eax, eax
    jz 9f
    imul eax, [rsp + 24]
    neg eax
    add eax, [rip + cscroll]
    jns 5f
    xor eax, eax
5:  mov [rip + cscroll], eax
    mov dword ptr [rip + g_scroll_y], 0
9:  EPILOGUE

# cat_color(category) -> eax argb
cat_color:
    lea rax, [rip + cat_slots]
    cmp edi, DCON_RESULT
    jbe 1f
    xor edi, edi
1:  movzx ecx, byte ptr [rax + rdi]
    lea rax, [rip + g_theme]
    mov eax, [rax + rcx*4]
    ret

# dview_console_field() -> rax the Debug Console's input field when the console has the keyboard,
#   else 0 (focused_field: paste and the clipboard reach it)
FN dview_console_field
    sub rsp, 8
    call place_focused
    add rsp, 8
    cmp dword ptr [rip + g_dv_places + 16], 0
    jl 1f                       # the console was never made
    cmp eax, [rip + g_dv_places + 16]
    jne 1f
    lea rax, [rip + cin]
    ret
1:  xor eax, eax
    ret

# console_key(ctx, keysym, cp, mods) -> eax: the input line; Enter evaluates, Up/Down history
console_key:
    PROLOGUE
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    cmp r12d, KEY_RETURN
    je 1f
    cmp r12d, KEY_KP_ENTER
    je 1f
    cmp r12d, KEY_UP
    je 2f
    cmp r12d, KEY_DOWN
    je 3f
    lea rdi, [rip + cin]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tf_key
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE                    # what the field did not take (F5, F10, Escape) goes on to the keys
1:  lea rdi, [rip + cin]
    call tf_text
    test rdx, rdx
    jz 8f
    mov rbx, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, r15
    call history_add
    lea rdi, [rip + cin]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    call dap_eval
    lea rdi, [rip + cin]
    call tf_clear
    mov dword ptr [rip + hist_at], -1
    mov dword ptr [rip + cscroll], 0
    jmp 8f
2:  mov edi, 1
    call history_move
    jmp 8f
3:  mov edi, -1
    call history_move
8:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE

# history_add(ptr, len): an entry (newline-free), the oldest dropped past 100
history_add:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + history]
    mov rsi, r12
    mov rdx, r13
    call sb_push_clean_bp
    lea rdi, [rip + history]
    mov esi, 10
    call sb_push_byte
    # count
    mov rdi, [rip + history + SB_ptr]
    mov rsi, [rip + history + SB_len]
    xor ecx, ecx
    xor edx, edx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 10
    jne 11f
    inc edx
11: inc rcx
    jmp 1b
2:  cmp edx, DV_HISTORY_MAX
    jbe 9f
    xor ecx, ecx
3:  cmp byte ptr [rdi + rcx], 10
    je 4f
    inc rcx
    jmp 3b
4:  inc rcx
    sub rsi, rcx
    mov [rip + history + SB_len], rsi
    mov rdx, rsi
    lea rsi, [rdi + rcx]
    call memmove
9:  EPILOGUE

# history_move(dir): Up (1) the older entry, Down (-1) the newer one, into the input line
history_move:
    PROLOGUE
    mov ebx, edi
    # entries
    mov rdi, [rip + history + SB_ptr]
    mov rsi, [rip + history + SB_len]
    xor ecx, ecx
    xor r12d, r12d
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 10
    jne 11f
    inc r12d
11: inc rcx
    jmp 1b
2:  test r12d, r12d
    jz 9f
    mov eax, [rip + hist_at]
    cmp eax, -1
    jne 3f
    mov eax, r12d               # one past the newest
3:  sub eax, ebx
    js 9f
    cmp eax, r12d
    jb 4f
    mov dword ptr [rip + hist_at], -1
    lea rdi, [rip + cin]
    call tf_clear
    jmp 9f
4:  mov [rip + hist_at], eax
    # entry eax
    mov rdi, [rip + history + SB_ptr]
    xor ecx, ecx
5:  test eax, eax
    jz 6f
    cmp byte ptr [rdi + rcx], 10
    jne 51f
    dec eax
51: inc rcx
    jmp 5b
6:  lea rsi, [rdi + rcx]
    xor edx, edx
7:  cmp byte ptr [rsi + rdx], 10
    je 8f
    inc rdx
    jmp 7b
8:  lea rdi, [rip + cin]
    call tf_set
9:  EPILOGUE

# ---------------- prompts ----------------

# ask(kind, label cstr, initial cstr or 0): the palette's text prompt for the debugger
ask:
    PROLOGUE
    mov [rip + prompt_kind], edi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov esi, PROMPT_DEBUG
    call prompt_open
    test r13, r13
    jnz 1f
    call palette_field
    mov rdi, rax
    call tf_clear
    jmp 9f
1:  mov rdi, r13
    call strlen
    mov rdx, rax
    call palette_field
    mov rdi, rax
    mov rsi, r13
    call tf_set
9:  EPILOGUE

# dview_prompt_done(ptr, len): the palette's prompt for the debugger was accepted
FN dview_prompt_done
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + lab]
    mov rsi, r12
    mov rdx, r13
    call sb_set
    mov eax, [rip + prompt_kind]
    mov dword ptr [rip + prompt_kind], 0
    cmp eax, DP_WATCH
    jne 1f
    mov rdi, r12
    mov rsi, r13
    call dap_watch_add
    call bp_save_soon
    jmp 9f
1:  cmp eax, DP_FUNCTION
    jne 2f
    test r13, r13
    jz 9f
    mov rdi, [rip + lab + SB_ptr]
    xor esi, esi
    call bp_function
    jmp 9f
2:  # a breakpoint's condition, hit count or log message: empty removes it
    mov ebx, eax
    mov rdi, [rip + prompt_path + SB_ptr]
    test rdi, rdi
    jz 9f
    mov esi, [rip + prompt_bp]
    call bp_find
    test eax, eax
    jns 3f
    mov rdi, [rip + prompt_path + SB_ptr]
    mov esi, [rip + prompt_bp]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call bp_set
    test eax, eax
    js 9f
3:  mov edi, eax
    mov esi, ebx
    mov rdx, [rip + lab + SB_ptr]
    call bp_set_option
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# prompt_on_line(kind, label, option offset): asks for a breakpoint option on the cursor's line
prompt_on_line:
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    call cursor_line
    test eax, eax
    jz 9f
    mov [rip + prompt_bp], eax
    xor r14d, r14d              # initial text
    mov rdi, [rip + prompt_path + SB_ptr]
    mov esi, eax
    call bp_find
    test eax, eax
    js 1f
    mov edi, eax
    call bp_row
    mov r14, [rax + r13]
1:  mov edi, ebx
    mov rsi, r12
    mov rdx, r14
    call ask
9:  EPILOGUE

# cursor_line() -> eax the active document's cursor line (one-based) with prompt_path its path, or
#   0 without a file
cursor_line:
    PROLOGUE
    mov eax, [rip + menu_line]
    test eax, eax
    jz 1f
    mov dword ptr [rip + menu_line], 0     # the gutter menu's line (prompt_path is set)
    EPILOGUE
1:  mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 8f
    mov rsi, [rbx + DOC_path]
    test rsi, rsi
    jz 8f
    lea rdi, [rip + prompt_path]
    call sb_setc
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    inc eax
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sb_setc(sb, cstr): exactly the cstr, NUL-terminated
sb_setc:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    add rsp, 8
    pop r12
    pop rbx
    ret

# sb_set(sb, ptr, len): exactly these bytes, NUL-terminated
sb_set:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- commands ----------------

# dview_bp_menu(doc, line): the gutter's right-click menu for a line (zero-based): add a breakpoint,
#   a conditional one or a logpoint there, or edit, disable or remove the one there
FN dview_bp_menu
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rsi, [rbx + DOC_path]
    test rsi, rsi
    jz 9f
    lea rdi, [rip + prompt_path]
    call sb_setc
    lea eax, [r12 + 1]
    mov [rip + menu_target], eax
    mov rdi, [rip + prompt_path + SB_ptr]
    mov esi, eax
    call bp_find
    lea rdi, [rip + menu_add]
    test eax, eax
    js 1f
    lea rdi, [rip + menu_edit]
1:  mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call ctx_menu_open
9:  EPILOGUE

# the menu's items: each acts on the menu's line (menu_line is consumed by cursor_line)
mi_target:
    mov eax, [rip + menu_target]
    mov [rip + menu_line], eax
    ret
mi_add:
    call mi_target
    jmp cmd_debug_toggle_breakpoint
mi_condition:
    call mi_target
    jmp cmd_debug_condition
mi_hit:
    call mi_target
    jmp cmd_debug_hit_count
mi_log:
    call mi_target
    jmp cmd_debug_logpoint
mi_disable:
    call mi_target
    jmp cmd_debug_disable_breakpoint
mi_remove:
    call mi_target
    jmp cmd_debug_toggle_breakpoint

# cmd_debug_start (F5): continue the focused paused session, else start the selected configuration
#   (the first in launch.ini until one is selected)
FN cmd_debug_start
    PROLOGUE
    call dap_focused
    test rax, rax
    jz 1f
    cmp dword ptr [rax + DS_state], DSS_PAUSED
    jne 1f
    xor edi, edi
    call dap_resume
    EPILOGUE
1:  xor edi, edi
    call start_selected
    EPILOGUE

# cmd_debug_run (Ctrl+F5): the selected configuration without debugging
FN cmd_debug_run
    mov edi, 1
    jmp start_selected

# start_selected(nodebug)
start_selected:
    PROLOGUE
    mov ebx, edi
    # the selection stands while launch.ini (this project's) still has it
    lea rdi, [rip + lab]
    call sb_clear
    lea rdi, [rip + lab]
    call dcfg_names
    mov r12, [rip + g_dsel + SB_len]
    test r12, r12
    jz 4f
    mov r13, [rip + lab + SB_ptr]
    mov r14, r13
    add r14, [rip + lab + SB_len]
5:  cmp r13, r14
    jae 4f                      # gone: the first one instead
    mov rcx, r13
51: cmp byte ptr [rcx], 10
    je 52f
    inc rcx
    jmp 51b
52: mov r15, rcx
    sub rcx, r13
    cmp rcx, r12
    jne 53f
    mov rdi, r13
    mov rsi, [rip + g_dsel + SB_ptr]
    mov rdx, r12
    call memeq
    test eax, eax
    jnz 2f
53: lea r13, [r15 + 1]
    jmp 5b
4:  # the first configuration
    mov rsi, [rip + lab + SB_ptr]
    mov rcx, [rip + lab + SB_len]
    test rcx, rcx
    jz 3f
    xor edx, edx
1:  cmp byte ptr [rsi + rdx], 10
    je 11f
    inc rdx
    jmp 1b
11: lea rdi, [rip + g_dsel]
    call sb_set
2:  mov rdi, [rip + g_dsel + SB_ptr]
    mov rsi, [rip + g_dsel + SB_len]
    mov edx, ebx
    call dap_start
    EPILOGUE
3:  # no launch.ini: dap_start says so
    lea rdi, [rip + .Lnone]
    xor esi, esi
    mov edx, ebx
    call dap_start
    EPILOGUE

FN cmd_debug_stop
    jmp dap_stop

FN cmd_debug_pause
    jmp dap_pause

FN cmd_debug_step_over
    mov edi, 1
    jmp dap_resume
FN cmd_debug_step_into
    mov edi, 2
    jmp dap_resume
FN cmd_debug_step_out
    mov edi, 3
    jmp dap_resume
FN cmd_debug_continue
    xor edi, edi
    jmp dap_resume

# cmd_debug_restart: Stop, then the same configuration again once it ended
FN cmd_debug_restart
    jmp dap_restart

FN cmd_debug_show
    jmp dview_show

# cmd_debug_toggle_breakpoint (F9): on the cursor's line
FN cmd_debug_toggle_breakpoint
    PROLOGUE
    call cursor_line
    test eax, eax
    jz 9f
    mov rdi, [rip + prompt_path + SB_ptr]
    mov esi, eax
    call bp_toggle
9:  EPILOGUE

FN cmd_debug_condition
    mov edi, DP_COND
    lea rsi, [rip + .Lq_cond]
    mov edx, BP_cond
    jmp prompt_on_line
FN cmd_debug_hit_count
    mov edi, DP_HIT
    lea rsi, [rip + .Lq_hit]
    mov edx, BP_hit
    jmp prompt_on_line
FN cmd_debug_logpoint
    mov edi, DP_LOG
    lea rsi, [rip + .Lq_log]
    mov edx, BP_log
    jmp prompt_on_line

# cmd_debug_disable_breakpoint: the cursor line's breakpoint on or off
FN cmd_debug_disable_breakpoint
    PROLOGUE
    call cursor_line
    test eax, eax
    jz 9f
    mov rdi, [rip + prompt_path + SB_ptr]
    mov esi, eax
    call bp_find
    test eax, eax
    js 9f
    mov ebx, eax
    mov edi, eax
    call bp_row
    mov esi, [rax + BP_enabled]
    xor esi, 1
    mov edi, ebx
    call bp_enable
9:  EPILOGUE

FN cmd_debug_remove_all_breakpoints
    jmp bp_clear_all

FN cmd_debug_add_function_breakpoint
    mov edi, DP_FUNCTION
    lea rsi, [rip + .Lq_function]
    xor edx, edx
    jmp ask

FN cmd_debug_add_watch
    mov edi, DP_WATCH
    lea rsi, [rip + .Lq_watch]
    xor edx, edx
    jmp ask

# cmd_debug_evaluate_selection: the selection (or the word at the cursor) into the console
FN cmd_debug_evaluate_selection
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov r12, [rbx + DOC_cur]
    mov r13, [rbx + DOC_anchor]
    cmp r12, r13
    jbe 1f
    xchg r12, r13
1:  mov r14, r13
    sub r14, r12
    jz 9f
    cmp r14, 4096
    ja 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call doc_range
    mov rdi, rax
    mov rsi, r14
    call dap_eval
9:  EPILOGUE

FN cmd_debug_focus_console
    PROLOGUE
    call dview_ensure
    mov edi, [rip + g_dv_places + 16]
    mov esi, 1
    call place_show
    EPILOGUE

# cmd_debug_open_configurations: PROJECT/.rhun/launch.ini in a tab (created with a template comment)
FN cmd_debug_open_configurations
    PROLOGUE
    mov rsi, [rip + g_project]
    test rsi, rsi
    jz 9f
    lea rdi, [rip + lab]
    call sb_setc
    lea rdi, [rip + lab]
    lea rsi, [rip + .Lf_launch]
    call sb_push_cstr
    lea rdi, [rip + lab]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + lab + SB_ptr]
    call file_missing
    test eax, eax
    jz 1f
    mov rdi, [rip + lab + SB_ptr]
    call mkdir_parent
    mov rdi, [rip + lab + SB_ptr]
    lea rsi, [rip + .Ltemplate]
    mov edx, .Ltemplate_end - .Ltemplate
    call file_write_all
1:  mov rdi, [rip + lab + SB_ptr]
    call app_open_file
9:  EPILOGUE


# ---------------- the title bar's toolbar and the status bar's item ----------------

.equ ID_DBG_TB, 0x5e0100        # + button

# dview_toolbar(left, y, width, h, right) -> eax 1 when the toolbar took the title's place: a session
#   picker (with more than one session), Continue or Pause, Step Over, Into and Out, Restart, Stop;
#   a session without debugging has Restart and Stop only
FN dview_toolbar
    PROLOGUE 64
    mov dword ptr [rip + tb_n], 0
    mov [rsp], edi              # left limit
    mov [rsp + 4], esi          # y
    mov [rsp + 8], edx          # the title bar's width
    mov [rsp + 12], ecx         # h
    mov [rsp + 16], r8d         # right limit
    call dap_focused
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp dword ptr [rbx + DS_state], DSS_ENDED
    je 8f
    # the buttons for this session
    lea r12, [rip + tb_debug]
    cmp dword ptr [rbx + DS_nodebug], 0
    je 1f
    lea r12, [rip + tb_nodebug]
1:  xor r13d, r13d              # count
2:  cmp qword ptr [r12 + r13*8], 0
    je 3f
    inc r13d
    jmp 2b
3:  M eax, MI_28
    mov [rsp + 20], eax         # button size
    M ecx, MI_2
    add eax, ecx
    imul eax, r13d
    mov [rsp + 24], eax         # buttons' width
    # the picker: the session's name, when there are several
    mov dword ptr [rsp + 28], 0
    call dap_live_count
    cmp eax, 1
    jbe 4f
    mov rsi, [rbx + DS_name]
    test rsi, rsi
    jz 4f
    mov rdi, rsi
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + DS_name]
    mov rdx, rax
    call text_width
    M ecx, MI_16
    add eax, ecx
    mov [rsp + 28], eax
4:  mov eax, [rsp + 24]
    add eax, [rsp + 28]
    mov [rsp + 32], eax         # total
    mov ecx, [rsp + 8]
    sub ecx, eax
    sar ecx, 1                  # centered
    cmp ecx, [rsp]
    jge 41f
    mov ecx, [rsp]
41: mov edx, ecx
    add edx, eax
    cmp edx, [rsp + 16]
    jg 8f                       # no room: the title stays
    mov r14d, ecx               # x
    # the picker cycles the focused session
    cmp dword ptr [rsp + 28], 0
    je 5f
    mov edi, ID_DBG_TB + 15
    mov esi, r14d
    mov edx, [rsp + 4]
    mov ecx, [rsp + 28]
    mov r8d, [rsp + 12]
    call ui_btn
    mov r15d, eax
    lea rdi, [rip + g_face_small]
    mov esi, r14d
    M eax, MI_8
    add esi, eax
    mov edx, [rsp + 4]
    mov ecx, [rsp + 12]
    mov r8, [rbx + DS_name]
    COLOR r9d, T_FG
    call ui_text_c
    test r15d, UB_CLICK
    jz 42f
    call focus_next_session
42: add r14d, [rsp + 28]
5:  xor r15d, r15d
6:  cmp r15d, r13d
    jae 7f
    mov rax, [r12 + r15*8]      # the button's entry: icon, command, tooltip
    mov [rsp + 40], rax
    mov eax, [rax]              # icon
    # Continue becomes Pause while the program runs
    cmp eax, IC_PLAY
    jne 61f
    cmp dword ptr [rbx + DS_state], DSS_RUNNING
    jne 61f
    lea rcx, [rip + tbe_pause]
    mov [rsp + 40], rcx
    mov eax, IC_DBG_PAUSE
61: lea edi, [r15 + ID_DBG_TB]
    mov esi, r14d
    mov edx, [rsp + 12]
    sub edx, [rsp + 20]
    sar edx, 1
    add edx, [rsp + 4]
    mov [rsp + 36], edx
    mov ecx, [rsp + 20]
    mov r8d, [rsp + 20]
    mov r9d, eax
    # where it is, for tests (print-debug-toolbar)
    push rax
    push rdx
    mov ecx, [rip + tb_n]
    cmp ecx, 8
    jae 63f
    inc dword ptr [rip + tb_n]
    shl ecx, 4
    lea r8, [rip + tb_rects]
    mov [r8 + rcx], eax
    mov [r8 + rcx + 4], r14d
    mov [r8 + rcx + 8], edx
    mov eax, [rsp + 16 + 20]
    mov [r8 + rcx + 12], eax
63: pop rdx
    pop rax
    mov ecx, [rsp + 20]
    mov r8d, [rsp + 20]
    mov r9d, eax
    call ui_icon_btn
    mov r8d, eax
    lea edi, [r15 + ID_DBG_TB]
    mov esi, r14d
    mov edx, [rsp + 36]
    add edx, [rsp + 20]
    mov ecx, [rsp + 20]
    mov rax, [rsp + 40]
    mov r9, [rax + 16]
    call tip_note_text
    test eax, UB_CLICK
    jz 62f
    mov rax, [rsp + 40]
    call [rax + 8]
62: add r14d, [rsp + 20]
    M eax, MI_2
    add r14d, eax
    inc r15d
    jmp 6b
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# dview_toolbar_dump(sb): "button ICON x y size" for each toolbar button as last drawn
FN dview_toolbar_dump
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12d, [rip + tb_n]
    jae 9f
    mov r13d, r12d
    shl r13d, 4
    lea r14, [rip + tb_rects]
    add r14, r13
    mov rdi, rbx
    lea rsi, [rip + .Lbutton]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r14]
    call sb_push_u64
    xor r15d, r15d
2:  mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r14 + 4 + r15*4]
    call sb_push_u64
    inc r15d
    cmp r15d, 3
    jb 2b
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    inc r12d
    jmp 1b
9:  EPILOGUE

# focus_next_session(): the toolbar's picker: the next live session is focused
focus_next_session:
    PROLOGUE
    mov ebx, [rip + g_dfocus]
    mov r12d, DS_MAX
1:  inc ebx
    cmp ebx, DS_MAX
    jb 2f
    xor ebx, ebx
2:  mov edi, ebx
    call dap_slot
    mov ecx, [rax + DS_state]
    test ecx, ecx
    jz 3f
    cmp ecx, DSS_ENDED
    je 3f
    mov edi, ebx
    call dap_focus_slot
    EPILOGUE
3:  dec r12d
    jnz 1b
    EPILOGUE

# dview_status_item(x, y, h) -> eax the x after it: the focused session's state ("Run: paused
#   (breakpoint) a.c:3"), else "▶ CONFIG" for the configuration F5 starts; a click shows the debug view,
#   or starts it
.equ ID_DBG_STATUS, 0x5e0110
FN dview_status_item
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov ebx, edi
    lea rdi, [rip + lab]
    call sb_clear
    call dap_focused
    test rax, rax
    jz 5f
    mov r12, rax
    mov rsi, [r12 + DS_name]
    test rsi, rsi
    jz 1f
    lea rdi, [rip + lab]
    call sb_push_cstr
    lea rdi, [rip + lab]
    lea rsi, [rip + .Lcolon_sp]
    call sb_push_cstr
1:  mov edi, [r12 + DS_state]
    call status_word
    lea rdi, [rip + lab]
    mov rsi, rax
    call sb_push_cstr
    cmp dword ptr [r12 + DS_state], DSS_PAUSED
    jne 2f
    mov rsi, [r12 + DS_reason]
    test rsi, rsi
    jz 11f
    lea rdi, [rip + lab]
    lea rsi, [rip + .Lparen_open]
    call sb_push_cstr
    lea rdi, [rip + lab]
    mov rsi, [r12 + DS_reason]
    call sb_push_cstr
    lea rdi, [rip + lab]
    mov esi, ')'
    call sb_push_byte
11: mov rdi, r12
    call dap_frame_ptr
    test rax, rax
    jz 2f
    mov r13, rax
    cmp dword ptr [r13 + FR_pathlen], 0
    je 2f
    lea rdi, [rip + lab]
    mov esi, ' '
    call sb_push_byte
    mov ecx, [r13 + FR_path]
    mov rdi, [r12 + DS_strs + SB_ptr]
    add rdi, rcx
    mov esi, [r13 + FR_pathlen]
    call path_basename
    lea rdi, [rip + lab]
    mov rsi, rax
    call sb_push
    lea rdi, [rip + lab]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + lab]
    mov esi, [r13 + FR_line]
    call sb_push_u64
2:  jmp 7f
5:  # no session: the configuration F5 starts, when the project has some
    call status_config
    test eax, eax
    jz 9f
7:  lea rdi, [rip + lab]
    call sb_z_dv
    lea rdi, [rip + g_face_small]
    mov rsi, rax
    mov rdx, [rip + lab + SB_len]
    call text_width
    M ecx, MI_16
    add eax, ecx
    mov r14d, eax               # its width
    mov edi, ID_DBG_STATUS
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, r14d
    mov r8d, [rsp + 8]
    call ui_btn
    mov r15d, eax
    test eax, UB_HOVER
    jz 71f
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, r14d
    mov ecx, [rsp + 8]
    COLOR r8d, T_HOVER
    call gfx_fill
71: lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    M eax, MI_8
    add esi, eax
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8, [rip + lab + SB_ptr]
    COLOR r9d, T_ACCENT
    call ui_text_c
    test r15d, UB_CLICK
    jz 8f
    call dap_focused
    test rax, rax
    jz 72f
    call dview_show_on
    jmp 8f
72: call cmd_debug_start
8:  mov eax, [rsp]
    add eax, r14d
    EPILOGUE
9:  mov eax, [rsp]
    EPILOGUE

# status_word(state) -> cstr as the status bar says it
status_word:
    lea rax, [rip + .Lw_starting]
    cmp edi, DSS_RUNNING
    jne 1f
    lea rax, [rip + .Lw_running]
1:  cmp edi, DSS_PAUSED
    jne 2f
    lea rax, [rip + .Lw_paused]
2:  cmp edi, DSS_TERMINATING
    jne 3f
    lea rax, [rip + .Lw_stopping]
3:  cmp edi, DSS_ENDED
    jne 4f
    lea rax, [rip + .Lw_ended]
4:  cmp edi, DSS_APPROVAL
    jne 5f
    lea rax, [rip + .Lw_waiting]
5:  ret

# status_config() -> eax 1 with lab = "▶ CONFIG": the selected configuration, else launch.ini's
#   first (read again at most every 2 s)
status_config:
    PROLOGUE
    mov rsi, [rip + g_dsel + SB_ptr]
    mov rdx, [rip + g_dsel + SB_len]
    test rdx, rdx
    jnz 2f
    mov rsi, [rip + cfg_first + SB_ptr]
    mov rcx, [rip + cfg_first + SB_len]
    test rcx, rcx
    jz 8f
    xor edx, edx
11: cmp byte ptr [rsi + rdx], 10
    je 2f
    inc rdx
    jmp 11b
2:  push rsi
    push rdx
    lea rdi, [rip + lab]
    lea rsi, [rip + .Lplay]
    call sb_push_cstr
    pop rdx
    pop rsi
    lea rdi, [rip + lab]
    call sb_push
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# cfg_refresh(): launch.ini's names for the status bar, read again at most every 2 s from the tick
#   (never from drawing: in a remote window reading the file is a round trip)
cfg_refresh:
    PROLOGUE
    call time_ms
    mov rbx, rax
    mov rcx, [rip + cfg_checked]
    test rcx, rcx
    jz 1f
    sub rax, rcx
    cmp rax, 2000
    jb 9f
1:  mov [rip + cfg_checked], rbx
    lea rdi, [rip + cfg_prev]
    lea rsi, [rip + cfg_first]
    call sb_copy_dv
    lea rdi, [rip + cfg_first]
    call sb_clear
    lea rdi, [rip + cfg_first]
    call dcfg_names
    mov rdx, [rip + cfg_first + SB_len]
    cmp rdx, [rip + cfg_prev + SB_len]
    jne 2f
    mov rdi, [rip + cfg_first + SB_ptr]
    mov rsi, [rip + cfg_prev + SB_ptr]
    test rdx, rdx
    jz 9f
    call memeq
    test eax, eax
    jnz 9f
2:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# sb_copy_dv(dst, src)
sb_copy_dv:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call sb_clear
    mov rdi, rbx
    mov rsi, [r12 + SB_ptr]
    mov rdx, [r12 + SB_len]
    call sb_push
    add rsp, 8
    pop r12
    pop rbx
    ret

# sb_z_dv(sb) -> its bytes NUL-terminated
sb_z_dv:
    push rbx
    mov rbx, rdi
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    mov rax, [rbx + SB_ptr]
    pop rbx
    ret

# dview_show_on(): the debug view shown (not toggled)
FN dview_show_on
    PROLOGUE
    call dview_ensure
    mov dword ptr [rip + dv_shown], 0
    call dview_show
    EPILOGUE

# ---------------- context keys and the terminal ----------------

# dview_context(): debugState, inDebugMode and debugType for when clauses, from the focused session
FN dview_context
    PROLOGUE
    call cfg_refresh
    mov eax, [rip + g_dap_gen]
    cmp eax, [rip + ctx_gen]
    je 9f
    mov [rip + ctx_gen], eax
    lea r12, [rip + .Ls_inactive]
    xor r13d, r13d              # in debug mode
    lea r14, [rip + .Lnone]     # type
    call dap_focused
    test rax, rax
    jz 5f
    mov rbx, rax
    mov eax, [rbx + DS_state]
    cmp eax, DSS_ENDED
    je 5f
    mov r13d, 1
    mov edi, [rbx + DS_dbg]
    call dbg_row
    mov r14, [rax + DBG_type]
    lea r12, [rip + .Ls_initializing]
    mov eax, [rbx + DS_state]
    cmp eax, DSS_RUNNING
    jne 1f
    lea r12, [rip + .Ls_running]
1:  cmp eax, DSS_PAUSED
    jne 5f
    lea r12, [rip + .Ls_stopped]
5:  mov rdi, r12
    call strlen
    mov edi, CTX_DEBUG_STATE
    mov rsi, r12
    mov rdx, rax
    call ctx_set
    mov edi, CTX_IN_DEBUG_MODE
    mov esi, r13d
    call ctx_set_bool
    mov rdi, r14
    call strlen
    mov edi, CTX_DEBUG_TYPE
    mov rsi, r14
    mov rdx, rax
    call ctx_set
9:  EPILOGUE

# dview_terminal_key(keysym, mods) -> eax 1 when the key is the debugger's now: while a session
#   lives, Continue, Pause, Stop, Restart and the steps reach rhun even from the terminal
#   ([debug] keys_in_terminal)
FN dview_terminal_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    cmp dword ptr [rip + g_debug_keys_in_terminal], 0
    je 8f
    call dap_live_count
    test eax, eax
    jz 8f
    mov edi, r12d
    mov esi, r13d
    call keys_lookup
    test rax, rax
    jz 8f
    lea rcx, [rip + term_cmds]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 8f
    cmp rax, rdx
    je 9f
    add rcx, 8
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

.section .rodata
.Ln_variables: .asciz "debug.variables"
.Ln_watch: .asciz "debug.watch"
.Ln_stack: .asciz "debug.callstack"
.Ln_breakpoints: .asciz "debug.breakpoints"
.Ln_console: .asciz "debug.console"
.Lt_variables: .asciz "Variables"
.Lt_watch: .asciz "Watch"
.Lt_stack: .asciz "Call Stack"
.Lt_breakpoints: .asciz "Breakpoints"
.Lt_console: .asciz "Debug Console"
.Lwatch_prefix: .asciz "watch:"
.Lx_prefix: .asciz "x:"
.Lnot_available: .ascii "not available"
.Lnot_available_end:
.Leq: .asciz " = "
.Lon: .asciz " on "
.Lunnamed: .asciz "session"
.Lslash_t: .asciz "/t"
.Lslash_f: .asciz "/f"
.Lparens: .asciz "()"
.Lif: .asciz "if "
.Lhits: .asciz "hit "
.Llog: .asciz "log "
.Lsep: .asciz "-"
.Lgt: .asciz "> "
.Lph_eval: .asciz "Evaluate in the paused frame"
.Lnone: .asciz ""
.Lq_cond: .asciz "Break when (expression)"
.Lq_hit: .asciz "Break when the hit count is (e.g. >= 5; the debugger's syntax)"
.Lq_log: .asciz "Log message ({expression} is replaced)"
.Lq_function: .asciz "Break on function (name)"
.Lq_watch: .asciz "Watch expression"
.Lf_launch: .asciz "/.rhun/launch.ini"
.Ltemplate: .ascii "# Launch configurations for rhun's debugger: one section per configuration.\n"
    .ascii "# type names a debugger an installed extension provides; other keys are its launch\n"
    .ascii "# arguments. See the guide's Debugging chapter.\n"
    .ascii "#\n# [Run]\n# type = go\n# program = ${project}\n"
.Ltemplate_end:
.Lbutton: .asciz "button "
.Lcolon_sp: .asciz ": "
.Lparen_open: .asciz " ("
.Lplay: .byte 0xe2, 0x96, 0xb6, 0x20, 0
.Lw_starting: .asciz "starting"
.Lw_running: .asciz "running"
.Lw_paused: .asciz "paused"
.Lw_stopping: .asciz "stopping"
.Lw_ended: .asciz "ended"
.Lw_waiting: .asciz "waiting for your answer"
.Ls_inactive: .asciz "inactive"
.Ls_initializing: .asciz "initializing"
.Ls_running: .asciz "running"
.Ls_stopped: .asciz "stopped"
.Lt_continue: .asciz "Continue (F5)"
.Lt_pause: .asciz "Pause (F6)"
.Lt_over: .asciz "Step Over (F10)"
.Lt_into: .asciz "Step Into (F11)"
.Lt_out: .asciz "Step Out (Shift+F11)"
.Lt_restart: .asciz "Restart (Ctrl+Shift+F5)"
.Lt_stop: .asciz "Stop (Shift+F5)"
.p2align 3
# toolbar entries: icon (qword), command, tooltip
tbe_continue: .quad IC_PLAY, cmd_debug_continue, .Lt_continue
tbe_pause: .quad IC_DBG_PAUSE, cmd_debug_pause, .Lt_pause
tbe_over: .quad IC_DBG_OVER, cmd_debug_step_over, .Lt_over
tbe_into: .quad IC_DBG_INTO, cmd_debug_step_into, .Lt_into
tbe_out: .quad IC_DBG_OUT, cmd_debug_step_out, .Lt_out
tbe_restart: .quad IC_REFRESH, cmd_debug_restart, .Lt_restart
tbe_stop: .quad IC_STOP, cmd_debug_stop, .Lt_stop
.Lm_add: .asciz "Add Breakpoint"
.Lm_cond: .asciz "Add Conditional Breakpoint..."
.Lm_log: .asciz "Add Logpoint..."
.Lm_editcond: .asciz "Edit Condition..."
.Lm_edithit: .asciz "Edit Hit Count..."
.Lm_editlog: .asciz "Edit Log Message..."
.Lm_disable: .asciz "Enable or Disable Breakpoint"
.Lm_remove: .asciz "Remove Breakpoint"
.p2align 3
menu_add: .quad .Lm_add, mi_add, .Lm_cond, mi_condition, .Lm_log, mi_log, 0
menu_edit: .quad .Lm_editcond, mi_condition, .Lm_edithit, mi_hit, .Lm_editlog, mi_log
    .quad .Lm_disable, mi_disable, .Lm_remove, mi_remove, 0
tb_debug: .quad tbe_continue, tbe_over, tbe_into, tbe_out, tbe_restart, tbe_stop, 0
tb_nodebug: .quad tbe_restart, tbe_stop, 0
term_cmds: .quad cmd_debug_start, cmd_debug_stop, cmd_debug_pause, cmd_debug_continue
    .quad cmd_debug_step_over, cmd_debug_step_into, cmd_debug_step_out, cmd_debug_restart, 0
cat_slots:
    .byte T_FG, T_ERROR, T_MUTED, T_WARNING, T_MUTED, T_ERROR, T_MUTED, T_ACCENT, T_FG
.p2align 3
section_names: .quad .Ln_variables, .Ln_watch, .Ln_stack, .Ln_breakpoints
section_titles: .quad .Lt_variables, .Lt_watch, .Lt_stack, .Lt_breakpoints
sync_fns: .quad sync_vars, sync_watch, sync_stack, sync_bps
section_ops: .quad section_draw, section_key, 0, 0, section_actions, 0
console_ops: .quad console_draw, console_key, 0, 0, 0, 0
vars_tree_ops: .quad 0, vars_expand, 0, 0, 0, 0, 0, vars_load
stack_tree_ops: .quad stack_activate, 0, 0, 0, 0, 0, 0, 0
bps_tree_ops: .quad bps_activate, 0, 0, bps_check, 0, 0, 0, 0
tree_ops: .quad vars_tree_ops, vars_tree_ops, stack_tree_ops, bps_tree_ops
