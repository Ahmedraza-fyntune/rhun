# menus with extensions' items (manifest [menu.LOCATION] and [submenu.NAME]): the editor,
# explorer, tab and terminal context menus and an extension's own menu take the items of every
# extension whose when clause holds for the menu's target, grouped, ordered, with one level of
# submenus. A clicked item runs its command with FROM menu and the body "TARGET" LF ARGS.
#
# For other parts of rhun:
#   menu_open_editor(), menu_open_explorer(items, node), menu_open_root(items),
#   menu_open_tab(items, tab), menu_open_terminal(items, n): open a built-in menu with the
#   extensions' items (each sets the target first)
#   menu_contrib(loc, CT*, target line, len, add fn(label, len, icon cstr, row)) and
#   menu_contrib_run(row): the items of a location for buttons the views part draws
.include "rhun.inc"

.equ MLOC_EDITOR, 1
.equ MLOC_EXPLORER, 2
.equ MLOC_TAB, 3
.equ MLOC_TERMINAL, 4
.equ MLOC_EXTENSION, 5
.equ MLOC_EDITOR_TITLE, 6
.equ MLOC_VIEW_TITLE, 7
.equ MLOC_VIEW_ITEM, 8
.equ MLOC_VIEW_ITEM_INLINE, 9
.equ MLOC_SUB, 10               # an item of a [submenu.NAME]
# an extension's menu item (mi_list[extension index])
.equ MI_loc, 0
.equ MI_order, 4
.equ MI_name, 8                 # owned cstr
.equ MI_cmd, 16                 # owned cstr, or 0: the item's name
.equ MI_group, 24               # owned cstr, or 0: the extension's name
.equ MI_when, 32                # WC*, or 0
.equ MI_args, 40                # owned cstr, or 0
.equ MI_sub, 48                 # owned cstr: the submenu it opens, or 0
.equ MI_parent, 56              # owned cstr: the submenu it is in (MLOC_SUB)
.equ MI_bad, 64                 # 1: its clause does not compile (it never shows)
.equ MI_SIZE, 72
.equ MI_PER_LOC, 16             # items per extension per location
# a submenu (sm_list[extension index])
.equ SM_name, 0
.equ SM_title, 8
.equ SM_SIZE, 16
# a menu row (mn_rows): built-in, or an extension's item or submenu
.equ MR_kind, 0                 # 0 built-in or a line, 1 an item, 2 a submenu
.equ MR_ext, 8
.equ MR_mi, 16
.equ MR_SIZE, 24
.equ MN_ROWS, 160
.equ MN_EXT_ROWS, 32            # extension items in one menu
.equ MN_LABEL, 80
# a candidate while a menu is made
.equ MC_mi, 0
.equ MC_ext, 8
.equ MC_cmd, 16
.equ MC_group, 24               # cstr
.equ MC_index, 32               # the extension's index
.equ MC_SIZE, 40

.bss
.p2align 3
mi_list: .zero EXT_CAP * VEC_SIZE
sm_list: .zero EXT_CAP * VEC_SIZE
mn_items: .zero MN_ROWS * 16 + 16   # (label, handler) pairs for ctx_menu_open, 0-ended
mn_rows: .zero MN_ROWS * MR_SIZE
mn_count: .quad 0
mn_labels: .zero MN_EXT_ROWS * MN_LABEL
mn_nlabels: .quad 0
mn_cands: .zero MN_EXT_ROWS * MC_SIZE
mn_ncands: .quad 0
mn_cand_tmp: .zero MC_SIZE
mn_target: .zero MTG_SIZE        # the menu's target, for clauses and the body
mn_line: .zero SB_SIZE          # its TARGET line
mn_path: .zero 4096
mn_doc: .quad 0                 # the DOC id the invocation is about, 0: the active one
mn_x: .long 0
mn_y: .long 0
mn_body: .zero SB_SIZE
mn_sb: .zero SB_SIZE

.text

# ---------------------------------------------------------------- the manifest

# mi_vec(ext) / sm_vec(ext) -> rax its VEC, or 0
mi_vec:
    lea rsi, [rip + mi_list]
    jmp 1f
sm_vec:
    lea rsi, [rip + sm_list]
1:  mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    cmp rax, EXT_CAP
    jae 8f
    imul rax, rax, VEC_SIZE
    add rax, rsi
    ret
8:  xor eax, eax
    ret

# FN menu_manifest_kv(ext, ini) -> eax 1 when the line is in a [menu.LOCATION] or [submenu.NAME]
FN menu_manifest_kv
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [r12 + INI_sec]
    mov rsi, [r12 + INI_seclen]
    lea rdx, [rip + .Lmenu_dot]
    mov ecx, 5
    call str_starts
    test eax, eax
    jnz .Lmm_menu
    mov rdi, [r12 + INI_sec]
    mov rsi, [r12 + INI_seclen]
    lea rdx, [rip + .Lsubmenu_dot]
    mov ecx, 8
    call str_starts
    test eax, eax
    jnz .Lmm_sub
    xor eax, eax
    EPILOGUE
.Lmm_menu:
    mov rdi, [r12 + INI_sec]
    add rdi, 5
    mov rsi, [r12 + INI_seclen]
    sub rsi, 5
    call loc_find
    test eax, eax
    jz .Lmm_bad_loc
    mov r13d, eax
    xor r14d, r14d              # no parent
    jmp .Lmm_item
.Lmm_sub:
    mov r14, [r12 + INI_sec]
    add r14, 8
    mov r15, [r12 + INI_seclen]
    sub r15, 8
    mov rdi, r14
    mov rsi, r15
    call cmd_name_ok
    test eax, eax
    jz .Lmm_bad_line
    mov r13d, MLOC_SUB
    # title = TEXT
    mov rdi, r12
    lea rsi, [rip + .Ltitle]
    call ini_key_is
    test eax, eax
    jz .Lmm_item
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call sm_slot
    test rax, rax
    jz .Lmm_done
    mov [rsp], rax
    mov rdi, [rax + SM_title]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    mov edx, 60
    cmp rsi, rdx
    cmova rsi, rdx
    call mem_dup
    mov rcx, [rsp]
    mov [rcx + SM_title], rax
    jmp .Lmm_done
.Lmm_item:
    # ITEM.FIELD
    mov rdi, [r12 + INI_key]
    mov rsi, [r12 + INI_keylen]
    mov rcx, rsi
1:  test rcx, rcx
    jz .Lmm_bad_line
    dec rcx
    cmp byte ptr [rdi + rcx], '.'
    jne 1b
    mov [rsp], rcx              # ITEM's length
    mov rsi, rcx
    call cmd_name_ok
    test eax, eax
    jz .Lmm_bad_line
    mov rdi, rbx
    mov esi, r13d
    mov rdx, [r12 + INI_key]
    mov rcx, [rsp]
    mov r8, r14
    mov r9, r15
    call mi_slot
    test rax, rax
    jz .Lmm_full
    mov [rsp + 8], rax
    # the field
    mov rax, [r12 + INI_key]
    add rax, [rsp]
    inc rax
    mov [rsp + 16], rax
    mov rcx, [r12 + INI_keylen]
    sub rcx, [rsp]
    dec rcx
    mov [rsp + 24], rcx
    lea r15, [rip + mi_fields]
2:  mov rdx, [r15]
    test rdx, rdx
    jz .Lmm_bad_line
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call str_eq_cstr
    test eax, eax
    jnz 3f
    add r15, 16
    jmp 2b
3:  mov rax, [r15 + 8]          # the field's offset, or -1 for order, -2 for when
    cmp rax, -1
    je .Lmm_order
    cmp rax, -2
    je .Lmm_when
    cmp rax, MI_sub
    jne 4f
    cmp r13d, MLOC_SUB
    je .Lmm_nested
4:  mov rcx, [rsp + 8]
    lea r15, [rcx + rax]
    mov rdi, [r15]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call mem_dup
    mov [r15], rax
    jmp .Lmm_done
.Lmm_order:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call when_number
    test edx, edx
    jz .Lmm_bad_line
    mov rcx, [rsp + 8]
    mov [rcx + MI_order], eax
    jmp .Lmm_done
.Lmm_when:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    mov rdx, rbx
    call when_compile
    test rax, rax
    jz .Lmm_when_bad
    mov rcx, [rsp + 8]
    mov rdi, [rcx + MI_when]
    mov [rcx + MI_when], rax
    call when_free
    jmp .Lmm_done
.Lmm_when_bad:
    mov rdi, rbx
    mov rsi, r12
    call contrib_problem_when
    # a clause that does not compile drops the item
    mov rcx, [rsp + 8]
    mov dword ptr [rcx + MI_bad], 1
    jmp .Lmm_done
.Lmm_bad_loc:
    lea rdx, [rip + .Lp_location]
    jmp .Lmm_problem
.Lmm_full:
    lea rdx, [rip + .Lp_full]
    jmp .Lmm_problem
.Lmm_nested:
    lea rdx, [rip + .Lp_nested]
    jmp .Lmm_problem
.Lmm_bad_line:
    lea rdx, [rip + .Lp_line]
.Lmm_problem:
    mov rdi, rbx
    mov rsi, r12
    call contrib_problem_line
.Lmm_done:
    mov eax, 1
    EPILOGUE

# loc_find(ptr, len) -> eax the MLOC_* of a location name, or 0
loc_find:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + loc_names]
    mov r14d, 1
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 9f
    add rbx, 8
    inc r14d
    jmp 1b
8:  xor r14d, r14d
9:  mov eax, r14d
    EPILOGUE

# sm_slot(ext, name, len) -> rax the extension's submenu NAME, made when absent
sm_slot:
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call sm_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 2f
    imul r15, r14, SM_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + SM_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
2:  mov rdi, rbx
    mov esi, SM_SIZE
    call vec_push
    mov r15, rax
    mov qword ptr [r15 + SM_title], 0
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r15 + SM_name], rax
    mov rax, r15
9:  EPILOGUE

# sm_find(ext, name cstr) -> rax the submenu, or 0
sm_find:
    PROLOGUE
    mov r12, rsi
    call sm_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 8f
    imul r15, r14, SM_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, [r15 + SM_name]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# mi_slot(ext, loc, name, len, parent, plen) -> rax the item, made when absent; 0 when the
#   location has MI_PER_LOC items of this extension already
mi_slot:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov r12, rdx
    mov r13, rcx
    mov [rsp + 8], r8
    mov [rsp + 16], r9
    call mi_vec
    test rax, rax
    jz 8f
    mov r14, rax
    xor r15d, r15d
    mov dword ptr [rsp + 24], 0 # the location's items
1:  cmp r15, [r14 + VEC_len]
    jae 3f
    imul rbx, r15, MI_SIZE
    add rbx, [r14 + VEC_ptr]
    inc r15
    mov eax, [rsp]
    cmp [rbx + MI_loc], eax
    jne 1b
    inc dword ptr [rsp + 24]
    cmp eax, MLOC_SUB
    jne 2f
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, [rbx + MI_parent]
    call str_eq_cstr
    test eax, eax
    jz 1b
2:  mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + MI_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, rbx
    EPILOGUE
3:  cmp dword ptr [rsp + 24], MI_PER_LOC
    jae 8f
    mov rdi, r14
    mov esi, MI_SIZE
    call vec_push
    mov rbx, rax
    mov rdi, rbx
    xor esi, esi
    mov edx, MI_SIZE
    call memset
    mov eax, [rsp]
    mov [rbx + MI_loc], eax
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx + MI_name], rax
    cmp qword ptr [rsp + 8], 0
    je 4f
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    call mem_dup
    mov [rbx + MI_parent], rax
4:  mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN menu_ext_gone(ext): its items and submenus go; an open menu showing them closes
FN menu_ext_gone
    PROLOGUE
    mov r12, rdi
    # an open menu with its rows
    call ctx_menu_list
    lea rcx, [rip + mn_items]
    cmp rax, rcx
    jne 2f
    xor ecx, ecx
1:  cmp rcx, [rip + mn_count]
    jae 2f
    imul rax, rcx, MR_SIZE
    lea rdx, [rip + mn_rows]
    inc rcx
    cmp [rdx + rax + MR_ext], r12
    jne 1b
    call ctx_menu_close
2:  mov rdi, r12
    call mi_vec
    test rax, rax
    jz 5f
    mov rbx, rax
    xor r13d, r13d
3:  cmp r13, [rbx + VEC_len]
    jae 4f
    imul r14, r13, MI_SIZE
    add r14, [rbx + VEC_ptr]
    inc r13
    mov rdi, [r14 + MI_name]
    call mem_free
    mov rdi, [r14 + MI_cmd]
    call mem_free
    mov rdi, [r14 + MI_group]
    call mem_free
    mov rdi, [r14 + MI_when]
    call when_free
    mov rdi, [r14 + MI_args]
    call mem_free
    mov rdi, [r14 + MI_sub]
    call mem_free
    mov rdi, [r14 + MI_parent]
    call mem_free
    jmp 3b
4:  mov qword ptr [rbx + VEC_len], 0
5:  mov rdi, r12
    call sm_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r13d, r13d
6:  cmp r13, [rbx + VEC_len]
    jae 7f
    imul r14, r13, SM_SIZE
    add r14, [rbx + VEC_ptr]
    inc r13
    mov rdi, [r14 + SM_name]
    call mem_free
    mov rdi, [r14 + SM_title]
    call mem_free
    jmp 6b
7:  mov qword ptr [rbx + VEC_len], 0
9:  EPILOGUE

# FN menu_has(ext, loc) -> eax 1 when the extension has items for the location
FN menu_has
    PROLOGUE
    mov r12d, esi
    call mi_vec
    test rax, rax
    jz 8f
    mov rbx, rax
    xor ecx, ecx
1:  cmp rcx, [rbx + VEC_len]
    jae 8f
    imul rax, rcx, MI_SIZE
    add rax, [rbx + VEC_ptr]
    inc rcx
    cmp [rax + MI_loc], r12d
    jne 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------------------------------------------------------- making a menu

# mi_command(ext, mi) -> rax the command the item runs now: NAME its own, rhun.NAME a built-in,
#   EXT.NAME another extension's; 0 when there is none
mi_command:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rsi + MI_cmd]
    test r12, r12
    jnz 1f
    mov r12, [rsi + MI_name]
1:  mov rdi, r12
    call strlen
    mov r13, rax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lrhun_dot]
    mov ecx, 5
    call str_starts
    test eax, eax
    jz 2f
    lea rdi, [r12 + 5]
    lea rsi, [r13 - 5]
    call cmd_find               # built-ins come first in its search
    EPILOGUE
2:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ldot]
    mov ecx, 1
    call str_find
    test rax, rax
    js 3f
    mov rdi, r12
    mov rsi, r13
    call cmd_find
    EPILOGUE
3:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_cmd_local
    EPILOGUE

# mn_push(label, handler, kind, ext, mi): one more row
mn_push:
    mov rax, [rip + mn_count]
    cmp rax, MN_ROWS
    jae 9f
    lea r10, [rip + mn_items]
    mov r11, rax
    shl r11, 4
    mov [r10 + r11], rdi
    mov [r10 + r11 + 8], rsi
    imul r11, rax, MR_SIZE
    lea r10, [rip + mn_rows]
    add r10, r11
    mov [r10 + MR_kind], rdx
    mov [r10 + MR_ext], rcx
    mov [r10 + MR_mi], r8
    inc qword ptr [rip + mn_count]
9:  ret

# mn_label(src cstr, cut suffix?, chevron?) -> rax a label of the menu (at most 60 bytes): up to
#   the last " (" when asked (a command's title without "(Extension)"), " ›" after a submenu's
mn_label:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov r14, rdi
    mov rax, [rip + mn_nlabels]
    cmp rax, MN_EXT_ROWS
    jae 8f
    inc qword ptr [rip + mn_nlabels]
    imul rbx, rax, MN_LABEL
    lea rcx, [rip + mn_labels]
    add rbx, rcx
    mov rdi, r14
    call strlen
    mov rcx, rax
    test r12d, r12d
    jz 3f
    mov rsi, rcx
1:  cmp rsi, 2
    jb 3f
    cmp byte ptr [r14 + rsi - 2], ' '
    jne 2f
    cmp byte ptr [r14 + rsi - 1], '('
    jne 2f
    lea rcx, [rsi - 2]
    jmp 3f
2:  dec rsi
    jmp 1b
3:  cmp rcx, 60
    jbe 4f
    mov edi, ecx
    mov rsi, r14
    mov edx, 60
    call utf8_cut
    mov rcx, rax
4:  mov rdi, rbx
    mov rsi, r14
    mov rdx, rcx
    push rcx
    push rcx
    call memcpy
    pop rcx
    pop rcx
    lea rdi, [rbx + rcx]
    mov byte ptr [rdi], 0
    test r13d, r13d
    jz 5f
    lea rsi, [rip + .Lchevron]
    call cstr_copy
5:  mov rax, rbx
    EPILOGUE
8:  lea rax, [rip + .Ldot]
    EPILOGUE

# mc_less(a, b) -> eax 1 when candidate a sorts before b: group, order, extension, item name
mc_less:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + MC_group]
    mov rsi, [r12 + MC_group]
    call strcmp_order
    test eax, eax
    jnz 8f
    mov rax, [rbx + MC_mi]
    mov rcx, [r12 + MC_mi]
    mov eax, [rax + MI_order]
    cmp eax, [rcx + MI_order]
    jl 7f
    jg 6f
    mov eax, [rbx + MC_index]
    cmp eax, [r12 + MC_index]
    jb 7f
    ja 6f
    mov rax, [rbx + MC_mi]
    mov rcx, [r12 + MC_mi]
    mov rdi, [rax + MI_name]
    mov rsi, [rcx + MI_name]
    call strcmp_order
    test eax, eax
    js 7f
6:  xor eax, eax
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  shr eax, 31                 # negative: a first
    EPILOGUE

# strcmp_order(a, b) -> eax < 0, 0, > 0 by bytes
strcmp_order:
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    movzx edx, byte ptr [rsi + rcx]
    sub eax, edx
    jnz 9f
    test edx, edx
    jz 9f
    inc rcx
    jmp 1b
9:  ret

# mn_collect(loc, parent cstr or 0, only ext or 0): the candidates of a location whose command
#   exists and is enabled and whose clause holds for mn_target, sorted
mn_collect:
    PROLOGUE 16
    mov [rsp], edi
    mov r12, rsi
    mov [rsp + 8], rdx
    mov qword ptr [rip + mn_ncands], 0
    lea rdi, [rip + mn_target]
    call ctx_push_target
    xor r13d, r13d              # the extension's index
1:  cmp r13, [rip + g_exts + VEC_len]
    jae .Lmc_sort
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    mov rax, [rsp + 8]
    test rax, rax
    jz 11f
    cmp rax, rbx
    jne 1b
11: mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 1b
    mov rdi, rbx
    call mi_vec
    test rax, rax
    jz 1b
    mov r14, rax
    xor r15d, r15d
2:  cmp r15, [r14 + VEC_len]
    jae 1b
    imul rsi, r15, MI_SIZE
    add rsi, [r14 + VEC_ptr]
    inc r15
    mov eax, [rsp]
    cmp [rsi + MI_loc], eax
    jne 2b
    cmp dword ptr [rsi + MI_bad], 0
    jne 2b
    cmp eax, MLOC_SUB
    jne 3f
    push rsi
    push rsi
    mov rdi, r12
    mov rsi, [rsi + MI_parent]
    call strcmp_eq
    pop rsi
    pop rsi
    test eax, eax
    jz 2b
3:  cmp qword ptr [rip + mn_ncands], MN_EXT_ROWS
    jae .Lmc_sort
    lea rax, [rip + mn_cand_tmp]
    mov [rax + MC_mi], rsi
    mov [rax + MC_ext], rbx
    mov qword ptr [rax + MC_cmd], 0
    mov ecx, r13d
    dec ecx
    mov [rax + MC_index], ecx
    mov rcx, [rsi + MI_group]
    test rcx, rcx
    jnz 4f
    mov rcx, [rbx + EXT_name]
4:  mov [rax + MC_group], rcx
    # a submenu needs no command; an item's must exist and be enabled
    cmp qword ptr [rsi + MI_sub], 0
    jne 5f
    mov rdi, rbx
    call mi_command
    test rax, rax
    jz 2b
    lea rcx, [rip + mn_cand_tmp]
    mov [rcx + MC_cmd], rax
    mov rdi, rax
    call cmd_enabled
    test eax, eax
    jz 2b
5:  lea rax, [rip + mn_cand_tmp]
    mov rax, [rax + MC_mi]
    mov rdi, [rax + MI_when]
    test rdi, rdi
    jz 6f
    call when_eval_fresh
    test eax, eax
    jz 2b
6:  mov rax, [rip + mn_ncands]
    imul rdi, rax, MC_SIZE
    lea rcx, [rip + mn_cands]
    add rdi, rcx
    lea rsi, [rip + mn_cand_tmp]
    mov edx, MC_SIZE
    call memcpy
    inc qword ptr [rip + mn_ncands]
    jmp 2b
.Lmc_sort:
    call ctx_pop_target
    # insertion sort: few items
    mov r13d, 1
7:  cmp r13, [rip + mn_ncands]
    jae 9f
    mov r14, r13
8:  test r14, r14
    jz 81f
    imul rbx, r14, MC_SIZE
    lea rcx, [rip + mn_cands]
    add rbx, rcx
    lea rdi, [rbx]
    lea rsi, [rbx - MC_SIZE]
    call mc_less
    test eax, eax
    jz 81f
    # swap rbx and rbx - MC_SIZE
    lea rdi, [rip + mn_cand_tmp]
    mov rsi, rbx
    mov edx, MC_SIZE
    call memcpy
    mov rdi, rbx
    lea rsi, [rbx - MC_SIZE]
    mov edx, MC_SIZE
    call memcpy
    lea rdi, [rbx - MC_SIZE]
    lea rsi, [rip + mn_cand_tmp]
    mov edx, MC_SIZE
    call memcpy
    dec r14
    jmp 8b
81: inc r13
    jmp 7b
9:  EPILOGUE

# mn_build(loc, static items or 0, parent cstr or 0, only ext or 0): mn_items from the built-in
#   items and the extensions' (a line between groups)
mn_build:
    PROLOGUE 16
    mov [rsp], edi
    mov rbx, rsi
    mov r12, rdx
    mov r13, rcx
    mov qword ptr [rip + mn_count], 0
    mov qword ptr [rip + mn_nlabels], 0
    test rbx, rbx
    jz 2f
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 2f
    mov rsi, [rbx + 8]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call mn_push
    add rbx, 16
    jmp 1b
2:  mov edi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call mn_collect
    xor r14d, r14d              # the candidate
    xor r15d, r15d              # the last group
3:  cmp r14, [rip + mn_ncands]
    jae 8f
    imul rbx, r14, MC_SIZE
    lea rax, [rip + mn_cands]
    add rbx, rax
    inc r14
    # a line before a new group (not at the top)
    cmp qword ptr [rip + mn_count], 0
    je 4f
    test r15, r15
    jz 31f
    mov rdi, r15
    mov rsi, [rbx + MC_group]
    call strcmp_eq
    test eax, eax
    jnz 4f
31: mov rax, [rip + mn_count]
    shl rax, 4
    lea rcx, [rip + mn_items]
    cmp qword ptr [rcx + rax - 8], 0
    je 4f                       # a line is there already
    lea rdi, [rip + .Lline]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call mn_push
4:  mov r15, [rbx + MC_group]
    mov rax, [rbx + MC_mi]
    mov rsi, [rax + MI_sub]
    test rsi, rsi
    jnz 5f
    # an item: its command's title
    mov rax, [rbx + MC_cmd]
    mov rdi, [rax + CMD_title]
    mov esi, 1
    xor edx, edx
    call mn_label
    mov rdi, rax
    lea rsi, [rip + menu_run_row]
    mov edx, 1
    jmp 6f
5:  # a submenu: its title (or its name)
    mov rdi, [rbx + MC_ext]
    call sm_find
    mov rdi, [rbx + MC_mi]
    mov rdi, [rdi + MI_sub]
    test rax, rax
    jz 51f
    cmp qword ptr [rax + SM_title], 0
    je 51f
    mov rdi, [rax + SM_title]
51: xor esi, esi
    mov edx, 1
    call mn_label
    mov rdi, rax
    lea rsi, [rip + menu_sub_row]
    mov edx, 2
6:  mov rcx, [rbx + MC_ext]
    mov r8, [rbx + MC_mi]
    call mn_push
    jmp 3b
8:  # no trailing line
    mov rax, [rip + mn_count]
    test rax, rax
    jz 9f
    shl rax, 4
    lea rcx, [rip + mn_items]
    cmp qword ptr [rcx + rax - 8], 0
    jne 9f
    dec qword ptr [rip + mn_count]
9:  mov rax, [rip + mn_count]
    shl rax, 4
    lea rcx, [rip + mn_items]
    xor edx, edx
    mov [rcx + rax], rdx
    mov [rcx + rax + 8], rdx
    EPILOGUE

# mn_show(loc, static items, x, y): build and open
mn_show:
    PROLOGUE
    mov [rip + mn_x], edx
    mov [rip + mn_y], ecx
    xor edx, edx
    xor ecx, ecx
    call mn_build
    lea rdi, [rip + mn_items]
    mov esi, [rip + mn_x]
    mov edx, [rip + mn_y]
    call ctx_menu_open
    EPILOGUE

# ---------------------------------------------------------------- running a row

# menu_run_row(): the clicked item's command, FROM menu, the body "TARGET" LF ARGS, about the
#   target's document; a command gone meanwhile toasts
menu_run_row:
    PROLOGUE
    mov eax, [rip + g_menu_index]
    cmp rax, [rip + mn_count]
    jae 9f
    imul rax, rax, MR_SIZE
    lea rcx, [rip + mn_rows]
    add rax, rcx
    mov rbx, [rax + MR_ext]
    mov r12, [rax + MR_mi]
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call mi_command
    test rax, rax
    jz 8f
    mov r13, rax
    lea rdi, [rip + mn_body]
    call sb_clear
    lea rdi, [rip + mn_body]
    mov rsi, [rip + mn_line + SB_ptr]
    mov rdx, [rip + mn_line + SB_len]
    call sb_push
    lea rdi, [rip + mn_body]
    mov esi, 10
    call sb_push_byte
    mov rsi, [r12 + MI_args]
    test rsi, rsi
    jz 1f
    lea rdi, [rip + mn_body]
    call sb_push_cstr
1:  mov rdi, r13
    mov esi, INV_MENU
    mov rdx, [rip + mn_body + SB_ptr]
    mov rcx, [rip + mn_body + SB_len]
    mov r8, [rip + mn_doc]
    call cmd_invoke
9:  EPILOGUE
8:  lea rdi, [rip + .Lgone]
    call app_toast
    EPILOGUE

# menu_sub_row(): the clicked submenu opens in place of the menu, for the same target
menu_sub_row:
    PROLOGUE
    mov eax, [rip + g_menu_index]
    cmp rax, [rip + mn_count]
    jae 9f
    imul rax, rax, MR_SIZE
    lea rcx, [rip + mn_rows]
    add rax, rcx
    mov rbx, [rax + MR_ext]
    mov r12, [rax + MR_mi]
    mov edi, MLOC_SUB
    xor esi, esi
    mov rdx, [r12 + MI_sub]
    mov rcx, rbx
    call mn_build
    cmp qword ptr [rip + mn_count], 0
    je 9f
    lea rdi, [rip + mn_items]
    mov esi, [rip + mn_x]
    mov edx, [rip + mn_y]
    call ctx_menu_open
9:  EPILOGUE

# FN menu_row_note(i) -> rax " [OWNER/NAME]" or " >" for the open menu's row i (print-menu), or 0
FN menu_row_note
    PROLOGUE
    mov ebx, edi
    call ctx_menu_list
    lea rcx, [rip + mn_items]
    cmp rax, rcx
    jne 8f
    cmp rbx, [rip + mn_count]
    jae 8f
    imul rax, rbx, MR_SIZE
    lea rcx, [rip + mn_rows]
    add rax, rcx
    mov rdx, [rax + MR_kind]
    test rdx, rdx
    jz 8f
    lea rcx, [rip + .Lsub_note]
    cmp rdx, 2
    je 7f
    mov r12, [rax + MR_ext]
    lea rdi, [rip + mn_sb]
    call sb_clear
    lea rdi, [rip + mn_sb]
    lea rsi, [rip + .Lnote_open]
    call sb_push_cstr
    lea rdi, [rip + mn_sb]
    mov rsi, [r12 + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + mn_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + mn_sb]
    mov rsi, [r12 + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + mn_sb]
    lea rsi, [rip + .Lnote_close]
    call sb_push_cstr
    mov rcx, [rip + mn_sb + SB_ptr]
7:  mov rax, rcx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN menu_row_cmd(i) -> rax the command of the open menu's extension row i (its shortcut), or 0
FN menu_row_cmd
    PROLOGUE
    mov ebx, edi
    call ctx_menu_list
    lea rcx, [rip + mn_items]
    cmp rax, rcx
    jne 8f
    cmp rbx, [rip + mn_count]
    jae 8f
    imul rax, rbx, MR_SIZE
    lea rcx, [rip + mn_rows]
    add rax, rcx
    cmp qword ptr [rax + MR_kind], 1
    jne 8f
    mov rdi, [rax + MR_ext]
    mov rsi, [rax + MR_mi]
    call mi_command
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------------------------------------------------------- targets

# mt_begin(kind cstr, doc, path cstr or 0): mn_target and the TARGET line "KIND"
mt_begin:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rax, [rip + mn_target]
    mov [rax + MTG_kind], rbx
    mov [rax + MTG_doc], r12
    mov qword ptr [rax + MTG_tabkind], 0
    mov qword ptr [rax + MTG_path], 0
    test r13, r13
    jz 1f
    lea rdi, [rip + mn_path]
    mov rsi, r13
    call cstr_copy
    lea rax, [rip + mn_target]
    lea rcx, [rip + mn_path]
    mov [rax + MTG_path], rcx
1:  mov qword ptr [rip + mn_doc], 0
    test r12, r12
    jz 2f
    mov rax, [r12 + DOC_id]
    mov [rip + mn_doc], rax
2:  lea rdi, [rip + mn_line]
    call sb_clear
    lea rdi, [rip + mn_line]
    mov rsi, rbx
    call sb_push_cstr
    EPILOGUE

# mt_word(cstr): " WORD" on the TARGET line
mt_word:
    push rdi
    lea rdi, [rip + mn_line]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    lea rdi, [rip + mn_line]
    jmp sb_push_cstr
# mt_num(value): " N"
mt_num:
    push rdi
    lea rdi, [rip + mn_line]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    lea rdi, [rip + mn_line]
    jmp sb_push_u64
# mt_pos(doc, pos): " LINE COL" (one-based)
mt_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    lea rdi, [rax + 1]
    call mt_num
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov rdi, r12
    sub rdi, rax
    inc rdi
    call mt_num
    EPILOGUE

# FN menu_open_editor(): the editor's menu for the active document, its selection the target
FN menu_open_editor
    PROLOGUE
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    lea rdi, [rip + .Lk_editor]
    mov rsi, rbx
    mov rdx, [rbx + DOC_path]
    call mt_begin
    mov rdi, [rbx + DOC_version]
    call mt_num
    mov rdi, rbx
    call ed_sel
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r12
    call mt_pos
    mov rdi, rbx
    mov rsi, r13
    call mt_pos
    mov edi, MLOC_EDITOR
    lea rsi, [rip + editor_menu]
    mov edx, [rip + g_mx]
    mov ecx, [rip + g_my]
    call mn_show
9:  EPILOGUE

# FN menu_open_explorer(items, path, folder?): an explorer row's menu: "file PATH" or "folder PATH"
FN menu_open_explorer
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    lea rdi, [rip + .Lk_file]
    test edx, edx
    jz 1f
    lea rdi, [rip + .Lk_folder]
1:  xor esi, esi
    mov rdx, rbx
    call mt_begin
    lea rdi, [rip + mn_path]
    call mt_word
    mov edi, MLOC_EXPLORER
    mov rsi, r12
    mov edx, [rip + g_mx]
    mov ecx, [rip + g_my]
    call mn_show
    EPILOGUE

# FN menu_open_root(items): the menu of the explorer's empty area: "root PATH" (the project)
FN menu_open_root
    PROLOGUE
    mov r12, rdi
    lea rdi, [rip + .Lk_root]
    xor esi, esi
    mov rdx, [rip + g_project]
    call mt_begin
    lea rdi, [rip + mn_path]
    call mt_word
    mov edi, MLOC_EXPLORER
    mov rsi, r12
    mov edx, [rip + g_mx]
    mov ecx, [rip + g_my]
    call mn_show
    EPILOGUE

# FN menu_open_tab(items, tab index): a tab's menu: "tab doc DOC PATH", "tab image PATH",
#   "tab view VIEW", "tab settings", "tab git", "tab extensions"
FN menu_open_tab
    PROLOGUE
    mov r12, rdi
    mov rax, rsi
    imul rax, rax, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    mov rbx, rax
    xor r13d, r13d              # the document
    mov rax, [rbx + TAB_kind]
    cmp rax, TAB_DOC
    je 1f
    cmp rax, TAB_IMAGE
    jne 2f
1:  mov r13, [rbx + TAB_doc]
2:  xor edx, edx
    test r13, r13
    jz 3f
    mov rdx, [r13 + DOC_path]
3:  lea rdi, [rip + .Lk_tab]
    mov rsi, r13
    call mt_begin
    mov rdi, [rbx + TAB_kind]
    call ctx_tab_kind_name
    lea rcx, [rip + mn_target]
    mov [rcx + MTG_tabkind], rax
    test rax, rax
    jz 7f
    mov rdi, rax
    call mt_word
    mov rax, [rbx + TAB_kind]
    cmp rax, TAB_DOC
    jne 4f
    mov rdi, [r13 + DOC_id]
    call mt_num
    lea rdi, [rip + .Ldash]
    cmp qword ptr [r13 + DOC_path], 0
    je 31f
    lea rdi, [rip + mn_path]
31: call mt_word
    jmp 7f
4:  cmp rax, TAB_IMAGE
    jne 5f
    lea rdi, [rip + mn_path]
    call mt_word
    jmp 7f
5:  cmp rax, TAB_VIEW
    jne 7f
    mov rdi, [rbx + TAB_flags]
    call extview_of_tab
    test rax, rax
    jz 7f
    mov edi, [rax + VW_id]
    call mt_num
7:  mov edi, MLOC_TAB
    mov rsi, r12
    mov edx, [rip + g_mx]
    mov ecx, [rip + g_my]
    call mn_show
    EPILOGUE

# FN menu_open_terminal(items, n): the terminal's menu: "terminal N" (one-based)
FN menu_open_terminal
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    lea rdi, [rip + .Lk_terminal]
    xor esi, esi
    xor edx, edx
    call mt_begin
    mov rdi, rbx
    call mt_num
    mov edi, MLOC_TERMINAL
    mov rsi, r12
    mov edx, [rip + g_mx]
    mov ecx, [rip + g_my]
    call mn_show
    EPILOGUE

# FN menu_open_extension(ext, x, y, settings handler) -> eax 1 when the extension has
#   [menu.extension]: its items, a line and Settings and details open as its menu
FN menu_open_extension
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], rcx
    mov esi, MLOC_EXTENSION
    call menu_has
    test eax, eax
    jz 9f
    lea rdi, [rip + .Lk_extension]
    xor esi, esi
    xor edx, edx
    call mt_begin
    mov eax, [rsp]
    mov [rip + mn_x], eax
    mov eax, [rsp + 4]
    mov [rip + mn_y], eax
    mov edi, MLOC_EXTENSION
    xor esi, esi
    xor edx, edx
    mov rcx, rbx
    call mn_build
    cmp qword ptr [rip + mn_count], 0
    je 1f
    lea rdi, [rip + .Lline]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call mn_push
1:  lea rdi, [rip + .Lsettings]
    mov rsi, [rsp + 8]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call mn_push
    mov rax, [rip + mn_count]
    shl rax, 4
    lea rcx, [rip + mn_items]
    mov qword ptr [rcx + rax], 0
    mov qword ptr [rcx + rax + 8], 0
    lea rdi, [rip + mn_items]
    mov esi, [rip + mn_x]
    mov edx, [rip + mn_y]
    call ctx_menu_open
    mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
loc_names: .quad .Ll_editor, .Ll_explorer, .Ll_tab, .Ll_terminal, .Ll_extension, .Ll_editor_title
    .quad .Ll_view_title, .Ll_view_item, .Ll_view_item_inline, 0
# ITEM.FIELD: the field's offset in MI, -1 order (a number), -2 when (a clause)
mi_fields: .quad .Lf_command, MI_cmd, .Lf_group, MI_group, .Lf_order, -1, .Lf_when, -2
    .quad .Lf_args, MI_args, .Lf_submenu, MI_sub, 0, 0
.Ll_editor: .asciz "editor"
.Ll_explorer: .asciz "explorer"
.Ll_tab: .asciz "tab"
.Ll_terminal: .asciz "terminal"
.Ll_extension: .asciz "extension"
.Ll_editor_title: .asciz "editor_title"
.Ll_view_title: .asciz "view_title"
.Ll_view_item: .asciz "view_item"
.Ll_view_item_inline: .asciz "view_item_inline"
.Lf_command: .asciz "command"
.Lf_group: .asciz "group"
.Lf_order: .asciz "order"
.Lf_when: .asciz "when"
.Lf_args: .asciz "args"
.Lf_submenu: .asciz "submenu"
.Lmenu_dot: .asciz "menu."
.Lsubmenu_dot: .asciz "submenu."
.Ltitle: .asciz "title"
.Lrhun_dot: .asciz "rhun."
.Ldot: .asciz "."
.Ldash: .asciz "-"
.Lline: .asciz "-"
.Lchevron: .asciz " \342\200\272"
.Lsettings: .asciz "Settings and details"
.Lgone: .asciz "This command is no longer available"
.Lsub_note: .asciz " >"
.Lnote_open: .asciz " ["
.Lnote_close: .asciz "]"
.Lk_editor: .asciz "editor"
.Lk_file: .asciz "file"
.Lk_folder: .asciz "folder"
.Lk_root: .asciz "root"
.Lk_tab: .asciz "tab"
.Lk_terminal: .asciz "terminal"
.Lk_extension: .asciz "extension"
.Lp_location: .asciz "unknown menu location"
.Lp_full: .asciz "more than 16 items for this location: dropped"
.Lp_nested: .asciz "a submenu inside a submenu"
.Lp_line: .asciz "not ITEM.command, .group, .order, .when, .args or .submenu"
