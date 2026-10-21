# the views group's --script / --control commands (control.s dispatches here), and a built-in demo
# of the place and tree APIs that the tests drive:
#   print-sidebar | print-panel-tabs | print-side-tabs   the places' items (place_dump)
#   print-view NAME|VIEW      a retained view's tree rows (or a built-in item's tree: places-demo)
#   view-show NAME            a place item (its name, or a declared view's key) shown, with the keyboard
#   view-focus NAME           the keyboard to it
#   places-demo               a built-in sidebar section and panel tab filled with tree_kid
.include "rhun.inc"

.bss
.p2align 3
demo_tree: .quad 0
tmpsb: .zero SB_SIZE
.data
demo_side: .long -1
demo_panel: .long -1

.text

# the commands for control.s's ctl_tables: fn(out, rest, rest len) -> rax 0
c_print_sidebar:
    xor eax, eax
    jmp c_views
c_print_panel_tabs:
    mov eax, 1
    jmp c_views
c_print_side_tabs:
    mov eax, 2
    jmp c_views
c_print_view:
    mov eax, 3
    jmp c_views
c_view_show:
    mov eax, 4
    jmp c_views
c_view_focus:
    mov eax, 5
    jmp c_views
c_places_demo:
    mov eax, 6
    jmp c_views
c_print_log:
    mov eax, 7
    jmp c_views

# print-form NAME|VIEW: a form view's fields (form_dump)
c_print_form:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call views_flush
    mov rdi, r12
    mov rsi, r13
    call rview_form_of
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rbx
    call form_dump
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lnone]
    call sb_push_cstr
    EPILOGUE

# print-notes: the notification cards and the progress entries (notify_dump)
c_print_notes:
    PROLOGUE
    mov rbx, rdi
    call views_flush
    mov rdi, rbx
    call notify_dump
    EPILOGUE

# note-press N B: card N among those shown (0 the oldest) has button B (1-3), close or cancel pressed
c_note_press:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call views_flush
    mov rdi, r12
    mov rsi, r13
    call parse_u64
    test rdx, rdx
    jz 8f
    mov r14, rax
    add r12, rdx
    sub r13, rdx
    cmp r13, 2
    jb 8f
    cmp byte ptr [r12], ' '
    jne 8f
    inc r12
    dec r13
    xor r15d, r15d
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lw_close]
    call str_eq_cstr
    test eax, eax
    jnz 2f
    mov r15d, -1
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lw_cancel]
    call str_eq_cstr
    test eax, eax
    jnz 2f
    mov rdi, r12
    mov rsi, r13
    call parse_u64
    cmp rdx, r13
    jne 8f
    mov r15d, eax
2:  mov edi, r14d
    mov esi, r15d
    call notify_press_test
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lnone]
    call sb_push_cstr
    EPILOGUE

c_views:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, eax
    call views_flush            # what a command looks at is drawn first
    mov rdi, rbx
    mov esi, r14d
    mov rdx, r12
    mov rcx, r13
    call views_control
    xor eax, eax
    EPILOGUE

# views_flush(): a frame now when one is due (control.s's flush_frame: headless and the Windows
#   renderer draw synchronously)
views_flush:
.ifndef WINDOWS
    cmp dword ptr [rip + g_headless], 0
    je 1f
.endif
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

# views_control(sb, which, ptr, len): command `which` (0 print-sidebar, 1 print-panel-tabs,
#   2 print-side-tabs, 3 print-view, 4 view-show, 5 view-focus, 6 places-demo) with its argument
FN views_control
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    cmp r12d, 0
    jne 1f
    mov rdi, rbx
    mov esi, PLACE_SIDEBAR
    call place_dump
    jmp 9f
1:  cmp r12d, 1
    jne 2f
    mov rdi, rbx
    lea rsi, [rip + .Lterminals]
    call sb_push_cstr
    mov rdi, rbx
    call term_count
    mov rsi, rax
    mov rdi, rbx
    call sb_push_u64
    cmp dword ptr [rip + g_panel_cur], -1
    jne 11f
    mov rdi, rbx
    lea rsi, [rip + .Lchosen]
    call sb_push_cstr
11: mov rdi, rbx
    lea rsi, [rip + .Lopen]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + g_term_open]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov esi, PLACE_PANEL
    call place_dump
    jmp 9f
2:  cmp r12d, 2
    jne 3f
    mov rdi, rbx
    mov esi, PLACE_SIDE
    call place_dump
    jmp 9f
3:  cmp r12d, 3
    jne 4f
    mov rdi, r13
    mov rsi, r14
    call tree_by_name
    test rax, rax
    jz 8f
    mov r15, rax
    mov rdi, rbx
    lea rsi, [rip + .Lat]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r15 + TR_rect]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r15 + TR_rect + 4]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lsize]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r15 + TR_rect + 8]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 'x'
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r15 + TR_rect + 12]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lscroll]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r15 + TR_scroll]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lrowh]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + g_mt + 4*MI_ROW]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    mov rdi, r15
    mov rsi, rbx
    call tree_dump
    jmp 9f
4:  cmp r12d, 4
    jne 5f
    mov rdi, r13
    mov rsi, r14
    call place_by_name
    cmp eax, -1
    je 8f
    mov edi, eax
    mov esi, 1
    call place_show
    jmp 9f
5:  cmp r12d, 5
    jne 6f
    mov rdi, r13
    mov rsi, r14
    call place_by_name
    cmp eax, -1
    je 8f
    mov edi, eax
    call place_focus
    jmp 9f
6:  cmp r12d, 6
    jne 7f
    call places_demo
    jmp 9f
7:  mov rdi, r13                # print-log NAME|VIEW
    mov rsi, r14
    call rview_log_of
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rbx
    call log_dump
    jmp 9f
8:  mov rdi, rbx
    lea rsi, [rip + .Lnone]
    call sb_push_cstr
9:  EPILOGUE

# place_by_name(ptr, len) -> eax the item named so, or whose name ends in ".NAME", or -1
place_by_name:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call place_find
    cmp eax, -1
    jne 9f
    xor ebx, ebx
1:  cmp ebx, PL_MAX
    jae 8f
    mov edi, ebx
    call place_at
    test rax, rax
    jz 2f
    mov r14, [rax + PL_name]
    mov rdi, r14
    call strlen
    lea rcx, [r13 + 1]
    cmp rax, rcx
    jb 2f
    sub rax, rcx
    cmp byte ptr [r14 + rax], '.'
    jne 2f
    lea rdi, [r14 + rax + 1]
    mov rsi, r13
    mov rdx, r12
    mov rcx, r13
    call str_eq
    test eax, eax
    jz 2f
    mov eax, ebx
    EPILOGUE
2:  inc ebx
    jmp 1b
8:  mov eax, -1
9:  EPILOGUE

# tree_by_name(ptr, len) -> rax a retained view's TR*, or the demo's for "demo", or 0
tree_by_name:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdx, [rip + .Ldemo]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov rax, [rip + demo_tree]
    EPILOGUE
1:  mov rdi, r12
    mov rsi, r13
    call rview_tree_of
    EPILOGUE

# ---------------- the built-in demo ----------------

# places_demo(): a sidebar section "Demo" and a panel tab "Demo" sharing a tree of fruit and
#   vegetables; the vegetables load lazily (TRO_load); activating a node toasts its label
places_demo:
    PROLOGUE
    cmp qword ptr [rip + demo_tree], 0
    jne 9f
    lea rdi, [rip + demo_tree_ops]
    xor esi, esi
    call tree_new
    mov [rip + demo_tree], rax
    mov rbx, rax
    mov rdi, rbx
    xor esi, esi
    call tree_kids_begin
    mov rdi, rbx
    lea rsi, [rip + .Lfruit]
    mov edx, 5
    lea rcx, [rip + .Lfruit_l]
    mov r8d, 5
    mov r9d, KIDS_OPEN
    call tree_kid
    mov r12d, eax
    mov rdi, rbx
    lea rsi, [rip + .Lveg]
    mov edx, 3
    lea rcx, [rip + .Lveg_l]
    mov r8d, 10
    mov r9d, KIDS_CLOSED
    call tree_kid
    mov rdi, rbx
    xor esi, esi
    call tree_kids_end
    mov rdi, rbx
    mov esi, r12d
    mov edx, 2
    call tree_set_badge
    mov rdi, rbx
    mov esi, r12d
    call tree_kids_begin
    mov rdi, rbx
    lea rsi, [rip + .Lapple]
    mov edx, 5
    lea rcx, [rip + .Lapple_l]
    mov r8d, 5
    xor r9d, r9d
    call tree_kid
    mov r13d, eax
    mov rdi, rbx
    mov esi, r13d
    lea rdx, [rip + .Lred]
    mov ecx, 3
    call tree_set_desc
    mov rdi, rbx
    mov esi, r13d
    mov edx, IC_DOT
    mov ecx, T_ERROR
    call tree_set_icon
    mov rdi, rbx
    lea rsi, [rip + .Lbanana]
    mov edx, 6
    lea rcx, [rip + .Lbanana_l]
    mov r8d, 6
    xor r9d, r9d
    call tree_kid
    mov rdi, rbx
    xor esi, esi
    call tree_kids_end
    mov edi, PLACE_SIDEBAR
    lea rsi, [rip + .Ldemo]
    lea rdx, [rip + .Ldemo_t]
    lea rcx, [rip + demo_place_ops]
    xor r8d, r8d
    call place_add
    mov [rip + demo_side], eax
    mov edi, PLACE_PANEL
    lea rsi, [rip + .Ldemo_panel]
    lea rdx, [rip + .Ldemo_t]
    lea rcx, [rip + demo_place_ops]
    mov r8d, 1
    call place_add
    mov [rip + demo_panel], eax
    mov edi, eax
    mov esi, IC_SEARCH
    call place_set_icon
    mov edi, [rip + demo_panel]
    mov esi, 2
    call place_set_badge
9:  EPILOGUE

# demo_draw(ctx, x, y, w, h)
demo_draw:
    PROLOGUE 16
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov ebx, edi
    call place_focused
    xor r9d, r9d
    mov ecx, [rip + demo_side]
    test ebx, ebx
    jz 1f
    mov ecx, [rip + demo_panel]
1:  cmp eax, ecx
    sete r9b
    mov rdi, [rip + demo_tree]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call tree_draw
    EPILOGUE

# demo_key(ctx, keysym, cp, mods) -> eax
demo_key:
    mov rdi, [rip + demo_tree]
    jmp tree_key

# demo_activate(ctx, tr, node): "activated LABEL" as a toast
demo_activate:
    PROLOGUE
    mov rbx, rsi
    mov r12d, edx
    lea rdi, [rip + tmpsb]
    call sb_clear
    lea rdi, [rip + tmpsb]
    lea rsi, [rip + .Lactivated]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, r12d
    call tree_node_label
    lea rdi, [rip + tmpsb]
    mov rsi, rax
    call sb_push
    mov rdi, [rip + tmpsb + SB_ptr]
    call app_toast
    EPILOGUE

# demo_load(ctx, tr, node): the vegetables' children, given when asked for
demo_load:
    PROLOGUE
    mov rbx, rsi
    mov r12d, edx
    mov rdi, rbx
    mov esi, r12d
    call tree_kids_begin
    mov rdi, rbx
    lea rsi, [rip + .Lcarrot]
    mov edx, 6
    lea rcx, [rip + .Lcarrot_l]
    mov r8d, 6
    xor r9d, r9d
    call tree_kid
    mov rdi, rbx
    xor esi, esi
    call tree_kids_end
    EPILOGUE

.section .rodata
.p2align 3
.globl views_ctl
views_ctl:
    .quad .Lc_print_sidebar, c_print_sidebar, .Lc_print_panel_tabs, c_print_panel_tabs
    .quad .Lc_print_side_tabs, c_print_side_tabs, .Lc_print_view, c_print_view
    .quad .Lc_view_show, c_view_show, .Lc_view_focus, c_view_focus, .Lc_places_demo, c_places_demo
    .quad .Lc_print_log, c_print_log, .Lc_print_notes, c_print_notes, .Lc_note_press, c_note_press
    .quad .Lc_print_form, c_print_form
    .quad 0, 0
.Lc_print_sidebar: .asciz "print-sidebar"
.Lc_print_panel_tabs: .asciz "print-panel-tabs"
.Lc_print_side_tabs: .asciz "print-side-tabs"
.Lc_print_view: .asciz "print-view"
.Lc_view_show: .asciz "view-show"
.Lc_view_focus: .asciz "view-focus"
.Lc_places_demo: .asciz "places-demo"
.Lc_print_log: .asciz "print-log"
.Lc_print_notes: .asciz "print-notes"
.Lc_print_form: .asciz "print-form"
.Lc_note_press: .asciz "note-press"
.Lw_close: .asciz "close"
.Lw_cancel: .asciz "cancel"
.Lterminals: .asciz "terminals="
.Lchosen: .asciz " chosen"
.Lopen: .asciz " open="
.Lat: .asciz "at="
.Lsize: .asciz " size="
.Lscroll: .asciz " scroll="
.Lrowh: .asciz " rowh="
.Lnone: .asciz "none\n"
.Ldemo: .asciz "demo"
.Ldemo_panel: .asciz "demo-panel"
.Ldemo_t: .asciz "Demo"
.Lfruit: .ascii "fruit"
.Lfruit_l: .ascii "Fruit"
.Lveg: .ascii "veg"
.Lveg_l: .ascii "Vegetables"
.Lapple: .ascii "apple"
.Lapple_l: .ascii "Apple"
.Lred: .ascii "red"
.Lbanana: .ascii "banana"
.Lbanana_l: .ascii "Banana"
.Lcarrot: .ascii "carrot"
.Lcarrot_l: .ascii "Carrot"
.Lactivated: .asciz "activated "
.p2align 3
demo_place_ops: .quad demo_draw, demo_key, 0, 0, 0, 0
demo_tree_ops: .quad demo_activate, 0, 0, 0, 0, 0, 0, demo_load, 0
