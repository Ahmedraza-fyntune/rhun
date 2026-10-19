# extensions' status bar items (manifest [status], feature status-items): text with icons
# ("$(play) Run"), a tooltip, a color or a background, a when clause and a command a click runs
# (FROM ref). Up to 8 per extension, left or right of the status bar, ordered by priority (higher
# further left on both sides); together they take at most 40 % of the bar, the lowest priorities
# dropping first. v1's status text is the item _v1 (right, priority 0, muted, no command).
.include "rhun.inc"

.equ SI_ext, 0
.equ SI_name, 8                 # owned cstr
.equ SI_text, 16                # owned cstr, or 0
.equ SI_tip, 24                 # owned cstr, or 0
.equ SI_cname, 32               # owned cstr: the command (its local name), or 0
.equ SI_args, 40                # owned bytes (NUL after them), or 0
.equ SI_alen, 48
.equ SI_when, 56                # WC*, or 0
.equ SI_prio, 64                # -1000 to 1000
.equ SI_align, 68               # 0 right, 1 left
.equ SI_color, 72               # T_* of the text
.equ SI_bg, 76                  # T_* of a background, or 0
.equ SI_flags, 80
.equ SI_shown, 84               # drawn this frame
.equ SI_x, 88                   # where (print-status)
.equ SI_y, 92
.equ SI_w, 96
.equ SI_h, 100
.equ SI_width, 104              # its content's width this frame
.equ SI_SIZE, 112
.equ SIF_MANIFEST, 1            # from [status]: kept while the extension is installed
.equ SIF_HIDDEN, 2              # a manifest item status-remove hid until the program stops
.equ SIF_V1, 4                  # v1's status text
.equ SIF_BAD, 8                 # its clause does not compile: never shown
.equ SI_PER_EXT, 8
.equ SI_TEXT_MAX, 120
.equ SI_TIP_MAX, 500
.equ SI_ICONS_MAX, 4
.equ SI_CUT, 240                # logical pixels of one item's content, at most
.equ ID_STATUS_ITEM, 0x7d00     # + index: an item's button

.bss
.p2align 3
si_items: .zero VEC_SIZE        # SI records
si_order: .zero 8 * 512         # the visible ones, sorted (an index each)
si_norder: .quad 0
si_sb: .zero SB_SIZE
si_name: .zero 64
sm_draw: .long 0                # si_measure's state
sm_x: .long 0
sm_y: .long 0
sm_h: .long 0
sm_argb: .long 0
sm_icons: .long 0
sm_width: .long 0

.text

# si_at(i) -> rax the SI record
si_at:
    imul rax, rdi, SI_SIZE
    add rax, [rip + si_items + VEC_ptr]
    ret

# si_find(ext, name, len) -> rax the extension's item NAME, or 0
si_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rip + si_items + VEC_len]
    jae 8f
    mov rdi, r14
    call si_at
    mov r15, rax
    inc r14
    cmp [r15 + SI_ext], rbx
    jne 1b
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + SI_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# si_count(ext) -> rax its items, v1's text aside
si_count:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + si_items + VEC_len]
    jae 9f
    imul rdx, rcx, SI_SIZE
    add rdx, [rip + si_items + VEC_ptr]
    inc rcx
    cmp [rdx + SI_ext], rdi
    jne 1b
    test dword ptr [rdx + SI_flags], SIF_V1
    jnz 1b
    inc rax
    jmp 1b
9:  ret

# si_new(ext, name, len) -> rax a new item (right, priority 0, muted)
si_new:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rip + si_items]
    mov esi, SI_SIZE
    call vec_push
    mov r14, rax
    mov rdi, r14
    xor esi, esi
    mov edx, SI_SIZE
    call memset
    mov [r14 + SI_ext], rbx
    mov dword ptr [r14 + SI_color], T_MUTED
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r14 + SI_name], rax
    mov dword ptr [rip + g_dirty], 1
    mov rax, r14
    EPILOGUE

# si_free_fields(si): its strings and clause go
si_free_fields:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + SI_name]
    call mem_free
    mov rdi, [rbx + SI_text]
    call mem_free
    mov rdi, [rbx + SI_tip]
    call mem_free
    mov rdi, [rbx + SI_cname]
    call mem_free
    mov rdi, [rbx + SI_args]
    call mem_free
    mov rdi, [rbx + SI_when]
    call when_free
    pop rbx
    ret

# si_clear_content(si): what a runtime status-item replaces (not the name)
si_clear_content:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + SI_text]
    call mem_free
    mov rdi, [rbx + SI_tip]
    call mem_free
    mov rdi, [rbx + SI_cname]
    call mem_free
    mov rdi, [rbx + SI_args]
    call mem_free
    mov rdi, [rbx + SI_when]
    call when_free
    xor eax, eax
    mov [rbx + SI_text], rax
    mov [rbx + SI_tip], rax
    mov [rbx + SI_cname], rax
    mov [rbx + SI_args], rax
    mov [rbx + SI_alen], rax
    mov [rbx + SI_when], rax
    mov dword ptr [rbx + SI_bg], 0
    mov dword ptr [rbx + SI_color], T_MUTED
    pop rbx
    ret

# si_remove_at(i): the item goes from the table
si_remove_at:
    PROLOGUE
    mov rbx, rdi
    call si_at
    mov r12, rax
    mov rdi, rax
    call si_free_fields
    mov rdi, r12
    lea rsi, [r12 + SI_SIZE]
    mov rdx, [rip + si_items + VEC_len]
    sub rdx, rbx
    dec rdx
    imul rdx, rdx, SI_SIZE
    call memmove
    dec qword ptr [rip + si_items + VEC_len]
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# si_drop(ext, all): its runtime items go and its manifest items show again; all: every item
si_drop:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rip + si_items + VEC_len]
1:  test r13, r13
    jz 9f
    dec r13
    mov rdi, r13
    call si_at
    cmp [rax + SI_ext], rbx
    jne 1b
    test r12d, r12d
    jnz 2f
    test dword ptr [rax + SI_flags], SIF_MANIFEST
    jz 2f
    and dword ptr [rax + SI_flags], ~SIF_HIDDEN
    jmp 1b
2:  mov rdi, r13
    call si_remove_at
    jmp 1b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN status_ext_stopped(ext) / status_ext_gone(ext)
FN status_ext_stopped
    xor esi, esi
    jmp si_drop
FN status_ext_gone
    mov esi, 1
    jmp si_drop

# si_color_name(ptr, len) -> eax the T_* of a color name (fg muted accent error warning success), or -1
si_color_name:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + color_names]
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add rbx, 16
    jmp 1b
2:  mov eax, [rbx + 8]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# si_text_set(si, ptr, len): its text, cut at SI_TEXT_MAX bytes and at a line end
si_text_set:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    cmp byte ptr [r12 + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov r13, rcx
    mov edi, r13d
    mov rsi, r12
    mov edx, SI_TEXT_MAX
    call utf8_cut
    mov r13, rax
    mov rdi, [rbx + SI_text]
    call mem_free
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx + SI_text], rax
    EPILOGUE

# ---------------------------------------------------------------- the manifest

# FN status_manifest_kv(ext, ini) -> eax 1 for a [status] line: ITEM.FIELD = VALUE (text tooltip
#   command args align priority color background when)
FN status_manifest_kv
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Ls_status]
    call ini_sec_is
    test eax, eax
    jz .Lsm_no
    # ITEM.FIELD
    mov rdi, [r12 + INI_key]
    mov rsi, [r12 + INI_keylen]
    mov rcx, rsi
1:  test rcx, rcx
    jz .Lsm_bad
    dec rcx
    cmp byte ptr [rdi + rcx], '.'
    jne 1b
    mov [rsp], rcx
    mov rsi, rcx
    call cmd_name_ok
    test eax, eax
    jz .Lsm_bad
    mov rdi, rbx
    mov rsi, [r12 + INI_key]
    mov rdx, [rsp]
    call si_find
    test rax, rax
    jnz 2f
    mov rdi, rbx
    call si_count
    cmp rax, SI_PER_EXT
    jae .Lsm_full
    mov rdi, rbx
    mov rsi, [r12 + INI_key]
    mov rdx, [rsp]
    call si_new
    or dword ptr [rax + SI_flags], SIF_MANIFEST
2:  mov r13, rax
    mov r14, [r12 + INI_key]
    add r14, [rsp]
    inc r14                     # the field
    mov r15, [r12 + INI_keylen]
    sub r15, [rsp]
    dec r15
    lea rcx, [rip + .Lf_text]
    call .Lsm_is
    jnz .Lsm_text
    lea rcx, [rip + .Lf_tooltip]
    call .Lsm_is
    jnz .Lsm_tooltip
    lea rcx, [rip + .Lf_command]
    call .Lsm_is
    jnz .Lsm_command
    lea rcx, [rip + .Lf_args]
    call .Lsm_is
    jnz .Lsm_args
    lea rcx, [rip + .Lf_align]
    call .Lsm_is
    jnz .Lsm_align
    lea rcx, [rip + .Lf_priority]
    call .Lsm_is
    jnz .Lsm_priority
    lea rcx, [rip + .Lf_color]
    call .Lsm_is
    jnz .Lsm_color
    lea rcx, [rip + .Lf_background]
    call .Lsm_is
    jnz .Lsm_background
    lea rcx, [rip + .Lf_when]
    call .Lsm_is
    jnz .Lsm_when
.Lsm_bad:
    lea rdx, [rip + .Lp_status]
    jmp .Lsm_problem
.Lsm_full:
    lea rdx, [rip + .Lp_full]
.Lsm_problem:
    mov rdi, rbx
    mov rsi, r12
    call contrib_problem_line
.Lsm_yes:
    mov eax, 1
    EPILOGUE
.Lsm_no:
    xor eax, eax
    EPILOGUE
# .Lsm_is(rcx cstr) -> ZF clear when the field (r14, r15) is that name
.Lsm_is:
    mov rdi, r14
    mov rsi, r15
    mov rdx, rcx
    call str_eq_cstr
    test eax, eax
    ret
.Lsm_text:
    mov rdi, r13
    mov rsi, [r12 + INI_val]
    mov rdx, [r12 + INI_vallen]
    call si_text_set
    jmp .Lsm_yes
.Lsm_tooltip:
    mov rdi, [r13 + SI_tip]
    call mem_free
    mov edi, [r12 + INI_vallen]
    mov rsi, [r12 + INI_val]
    mov edx, SI_TIP_MAX
    call utf8_cut
    mov rdi, [r12 + INI_val]
    mov rsi, rax
    call mem_dup
    mov [r13 + SI_tip], rax
    jmp .Lsm_yes
.Lsm_command:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call cmd_name_ok
    test eax, eax
    jz .Lsm_bad
    mov rdi, [r13 + SI_cname]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call mem_dup
    mov [r13 + SI_cname], rax
    jmp .Lsm_yes
.Lsm_args:
    mov rax, [r12 + INI_vallen]
    cmp rax, CRF_ARGS_MAX
    ja .Lsm_bad
    mov [r13 + SI_alen], rax
    mov rdi, [r13 + SI_args]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call mem_dup
    mov [r13 + SI_args], rax
    jmp .Lsm_yes
.Lsm_align:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + .Lv_left]
    call str_eq_cstr
    mov [r13 + SI_align], eax
    test eax, eax
    jnz .Lsm_yes
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + .Lv_right]
    call str_eq_cstr
    test eax, eax
    jz .Lsm_bad
    jmp .Lsm_yes
.Lsm_priority:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call when_number
    test edx, edx
    jz .Lsm_bad
    cmp rax, -1000
    jl .Lsm_bad
    cmp rax, 1000
    jg .Lsm_bad
    mov [r13 + SI_prio], eax
    jmp .Lsm_yes
.Lsm_color:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call si_color_name
    test eax, eax
    js .Lsm_bad
    mov [r13 + SI_color], eax
    jmp .Lsm_yes
.Lsm_background:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call si_color_name
    cmp eax, T_ERROR
    je 3f
    cmp eax, T_WARNING
    jne .Lsm_bad
3:  mov [r13 + SI_bg], eax
    jmp .Lsm_yes
.Lsm_when:
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    mov rdx, rbx
    call when_compile
    test rax, rax
    jz 4f
    mov rdi, [r13 + SI_when]
    mov [r13 + SI_when], rax
    call when_free
    and dword ptr [r13 + SI_flags], ~SIF_BAD
    jmp .Lsm_yes
4:  or dword ptr [r13 + SI_flags], SIF_BAD
    mov rdi, rbx
    mov rsi, r12
    call contrib_problem_when
    jmp .Lsm_yes

# ---------------------------------------------------------------- the protocol

# FN status_item_set(ext, name, len, body, blen) -> eax 0 set, 1 too many items, 2 syntax: the body
#   "ALIGN PRIORITY TEXT_LEN TOOLTIP_LEN EXTRA_LEN" LF TEXT TOOLTIP EXTRA (status-item)
FN status_item_set
    PROLOGUE 160
    # [rsp] name, [rsp + 8] its length, [rsp + 16] the header's LF, [rsp + 24] TEXT,
    # [rsp + 32 + 8 * i] the three lengths, [rsp + 56] the item, [rsp + 64 + 16 * i] the words
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov r12, rcx                # the body
    lea r13, [rcx + r8]         # its end
    mov rdi, rsi
    mov rsi, rdx
    call cmd_name_ok
    test eax, eax
    jz .Lss_syntax
    mov rax, r12
1:  cmp rax, r13
    jae .Lss_syntax
    cmp byte ptr [rax], 10
    je 2f
    inc rax
    jmp 1b
2:  mov [rsp + 16], rax
    mov rdi, r12
    mov rsi, rax
    sub rsi, r12
    lea rdx, [rsp + 64]
    call si_words
    cmp eax, 5
    jne .Lss_syntax
    # ALIGN
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lv_left]
    call str_eq_cstr
    mov r14d, eax               # 1 left
    test eax, eax
    jnz 3f
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lv_right]
    call str_eq_cstr
    test eax, eax
    jz .Lss_syntax
3:  mov rdi, [rsp + 80]         # PRIORITY
    mov rsi, [rsp + 88]
    call when_number
    test edx, edx
    jz .Lss_syntax
    cmp rax, -1000
    jl .Lss_syntax
    cmp rax, 1000
    jg .Lss_syntax
    mov r15d, eax
    # TEXT_LEN, TOOLTIP_LEN, EXTRA_LEN: they use the body exactly
    xor ecx, ecx
4:  cmp ecx, 3
    jae 5f
    mov rax, rcx
    shl rax, 4
    mov rdi, [rsp + 96 + rax]
    mov rsi, [rsp + 104 + rax]
    mov [rsp + 56], rcx
    call si_u32
    mov rcx, [rsp + 56]
    test edx, edx
    jz .Lss_syntax
    mov [rsp + 32 + rcx*8], rax
    inc ecx
    jmp 4b
5:  cmp qword ptr [rsp + 32], SI_TEXT_MAX
    ja .Lss_syntax
    cmp qword ptr [rsp + 40], SI_TIP_MAX
    ja .Lss_syntax
    mov rax, [rsp + 16]
    inc rax
    mov [rsp + 24], rax         # TEXT
    add rax, [rsp + 32]
    add rax, [rsp + 40]
    add rax, [rsp + 48]
    cmp rax, r13
    jne .Lss_syntax
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    call si_line_ok
    test eax, eax
    jz .Lss_syntax
    # the item: replaced, or new within the cap
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call si_find
    test rax, rax
    jnz 6f
    mov rdi, rbx
    call si_count
    cmp rax, SI_PER_EXT
    jae .Lss_full
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call si_new
6:  mov [rsp + 56], rax
    # EXTRA first: a bad record changes nothing of an item that was there
    mov rdi, rbx
    mov rsi, [rsp + 24]
    add rsi, [rsp + 32]
    add rsi, [rsp + 40]
    mov rdx, [rsp + 48]
    mov rcx, rax
    call si_extra
    test eax, eax
    jnz .Lss_syntax_drop
    mov rax, [rsp + 56]
    and dword ptr [rax + SI_flags], ~SIF_HIDDEN
    mov [rax + SI_align], r14d
    mov [rax + SI_prio], r15d
    mov rdi, rax
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call si_text_set
    mov rax, [rsp + 56]
    mov rdi, [rax + SI_tip]
    call mem_free
    mov rax, [rsp + 56]
    mov qword ptr [rax + SI_tip], 0
    cmp qword ptr [rsp + 40], 0
    je 7f
    mov rdi, [rsp + 24]
    add rdi, [rsp + 32]
    mov rsi, [rsp + 40]
    call mem_dup
    mov rcx, [rsp + 56]
    mov [rcx + SI_tip], rax
7:  mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
.Lss_syntax_drop:
    # a new item with a bad record does not stay
    mov rax, [rsp + 56]
    cmp qword ptr [rax + SI_text], 0
    jne .Lss_syntax
    test dword ptr [rax + SI_flags], SIF_MANIFEST
    jnz .Lss_syntax
    sub rax, [rip + si_items + VEC_ptr]
    xor edx, edx
    mov ecx, SI_SIZE
    div rcx
    mov rdi, rax
    call si_remove_at
.Lss_syntax:
    mov eax, 2
    EPILOGUE
.Lss_full:
    mov eax, 1
    EPILOGUE

# si_extra(ext, ptr, len, si) -> eax 0, or 1 for a record that breaks the rules: "command NAME
#   ARGS_LEN" + ARGS, "color NAME 0", "background NAME 0", "when LEN" + clause; others are skipped
si_extra:
    PROLOGUE 176
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    mov [rsp], rcx              # the item
    # parsed first into locals: [rsp + 8] CRF, [rsp + 16] color, [rsp + 20] background, [rsp + 24] WC, [rsp + 32] color or background?
    xor eax, eax
    mov [rsp + 8], rax
    mov dword ptr [rsp + 16], -1
    mov dword ptr [rsp + 20], -1
    mov [rsp + 24], rax
.Lsx_next:
    cmp r12, r13
    jae .Lsx_apply
    # the record's line
    mov rax, r12
1:  cmp rax, r13
    jae .Lsx_bad
    cmp byte ptr [rax], 10
    je 2f
    inc rax
    jmp 1b
2:  mov r14, rax                # its LF
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    lea rdx, [rsp + 64]
    call si_words               # up to 5 words at [rsp + 64]
    cmp eax, 2
    jb .Lsx_bad
    mov r15d, eax
    # the last word is LEN; the bytes follow the line
    dec eax
    shl eax, 4
    mov rdi, [rsp + 64 + rax]
    mov rsi, [rsp + 72 + rax]
    call si_u32
    test edx, edx
    jz .Lsx_bad
    mov [rsp + 144], rax         # LEN
    lea rcx, [r14 + 1]
    mov rdx, r13
    sub rdx, rcx
    cmp rax, rdx
    ja .Lsx_bad
    mov [rsp + 152], rcx        # the bytes
    # command NAME ARGS_LEN
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lx_command]
    call str_eq_cstr
    test eax, eax
    jz 3f
    cmp qword ptr [rsp + 8], 0
    jne .Lsx_bad                # twice
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    sub rdx, r12
    call cmdref_parse
    test rax, rax
    jz .Lsx_bad
    mov [rsp + 8], rax
    add r12, rdx
    jmp .Lsx_next
3:  # color NAME 0 / background NAME 0
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lx_color]
    call str_eq_cstr
    mov [rsp + 32], eax
    test eax, eax
    jnz 31f
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lx_background]
    call str_eq_cstr
    test eax, eax
    jz 4f
31: cmp r15d, 3
    jne .Lsx_bad
    cmp qword ptr [rsp + 144], 0
    jne .Lsx_bad
    mov rdi, [rsp + 80]
    mov rsi, [rsp + 88]
    call si_color_name
    test eax, eax
    js .Lsx_bad
    cmp dword ptr [rsp + 32], 0
    je 32f
    mov [rsp + 16], eax
    jmp 33f
32: cmp eax, T_ERROR
    je 34f
    cmp eax, T_WARNING
    jne .Lsx_bad
34: mov [rsp + 20], eax
33: lea r12, [r14 + 1]
    jmp .Lsx_next
4:  # when LEN + clause
    mov rdi, [rsp + 64]
    mov rsi, [rsp + 72]
    lea rdx, [rip + .Lx_when]
    call str_eq_cstr
    test eax, eax
    jz 5f
    cmp r15d, 2
    jne .Lsx_bad
    cmp qword ptr [rsp + 24], 0
    jne .Lsx_bad
    mov rdi, [rsp + 152]
    mov rsi, [rsp + 144]
    mov rdx, rbx
    call when_compile
    test rax, rax
    jz .Lsx_bad
    mov [rsp + 24], rax
    jmp 6f
5:  # another record: skipped
6:  mov r12, [rsp + 152]
    add r12, [rsp + 144]
    jmp .Lsx_next
.Lsx_apply:
    mov r14, [rsp]
    mov rdi, r14
    call si_clear_content
    mov rax, [rsp + 8]
    test rax, rax
    jz 7f
    lea rdi, [rax + CRF_name]
    call dup_cstr
    mov [r14 + SI_cname], rax
    mov rax, [rsp + 8]
    mov rcx, [rax + CRF_len]
    mov [r14 + SI_alen], rcx
    lea rdi, [rax + CRF_SIZE]
    mov rsi, rcx
    call mem_dup
    mov [r14 + SI_args], rax
    mov rdi, [rsp + 8]
    call cmdref_free
7:  mov eax, [rsp + 16]
    test eax, eax
    js 8f
    mov [r14 + SI_color], eax
8:  mov eax, [rsp + 20]
    test eax, eax
    js 81f
    mov [r14 + SI_bg], eax
81: mov rax, [rsp + 24]
    mov [r14 + SI_when], rax
    xor eax, eax
    EPILOGUE
.Lsx_bad:
    mov rdi, [rsp + 8]
    call cmdref_free
    mov rdi, [rsp + 24]
    call when_free
    mov eax, 1
    EPILOGUE

# si_words(ptr, len, out) -> eax the space-separated words (at most 5), their (ptr, len) in out
si_words:
    PROLOGUE
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov rbx, rdx
    xor r14d, r14d
1:  cmp r12, r13
    jae 9f
    cmp byte ptr [r12], ' '
    jne 2f
    inc r12
    jmp 1b
2:  cmp r14d, 5
    jae 8f
    mov rax, r12
3:  cmp rax, r13
    jae 4f
    cmp byte ptr [rax], ' '
    je 4f
    inc rax
    jmp 3b
4:  mov rcx, r14
    shl rcx, 4
    mov [rbx + rcx], r12
    mov rdx, rax
    sub rdx, r12
    mov [rbx + rcx + 8], rdx
    inc r14d
    mov r12, rax
    jmp 1b
8:  mov r14d, 99                # too many
9:  mov eax, r14d
    EPILOGUE

# si_u32(ptr, len) -> rax a decimal number of at most 9 digits, edx 1 when it is one
si_u32:
    xor eax, eax
    xor edx, edx
    test rsi, rsi
    jz 9f
    cmp rsi, 9
    ja 9f
    xor ecx, ecx
1:  movzx r8d, byte ptr [rdi + rcx]
    sub r8d, '0'
    cmp r8d, 9
    ja 8f
    imul rax, rax, 10
    add rax, r8
    inc rcx
    cmp rcx, rsi
    jb 1b
    mov edx, 1
9:  ret
8:  xor eax, eax
    xor edx, edx
    ret

# si_line_ok(ptr, len) -> eax 1 for one line of UTF-8 without control characters
si_line_ok:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp eax, 0x20
    jb 8f
    cmp eax, 0x7f
    je 8f
    jmp 1b
2:  jmp snippet_utf8_valid
8:  xor eax, eax
    ret

# FN status_item_remove(ext, name, len) -> eax 0: a runtime item goes, a manifest item hides until
#   the program stops; an unknown name changes nothing
FN status_item_remove
    PROLOGUE
    call si_find
    test rax, rax
    jz 9f
    test dword ptr [rax + SI_flags], SIF_MANIFEST
    jz 1f
    or dword ptr [rax + SI_flags], SIF_HIDDEN
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
1:  sub rax, [rip + si_items + VEC_ptr]
    xor edx, edx
    mov ecx, SI_SIZE
    div rcx
    mov rdi, rax
    call si_remove_at
9:  xor eax, eax
    EPILOGUE

# FN status_v1_set(ext, text cstr or 0): v1's status text as the item _v1
FN status_v1_set
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    lea rsi, [rip + .Lv1]
    mov edx, 3
    call si_find
    mov r13, rax
    test r12, r12
    jnz 1f
    test r13, r13
    jz 9f
    sub r13, [rip + si_items + VEC_ptr]
    mov rax, r13
    xor edx, edx
    mov ecx, SI_SIZE
    div rcx
    mov rdi, rax
    call si_remove_at
    jmp 9f
1:  test r13, r13
    jnz 2f
    mov rdi, rbx
    lea rsi, [rip + .Lv1]
    mov edx, 3
    call si_new
    mov r13, rax
    or dword ptr [r13 + SI_flags], SIF_V1
2:  mov rdi, r12
    call strlen
    mov rdx, rax
    mov rdi, r13
    mov rsi, r12
    call si_text_set
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------------------------------------------------------- drawing

# si_visible(si) -> eax 1 when the item shows: its extension installed and on (a runtime item: its
#   program running), not hidden, its clause true (keys as of the last ctx_refresh)
si_visible:
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    test dword ptr [rbx + SI_flags], SIF_HIDDEN | SIF_BAD
    jnz 9f
    cmp qword ptr [rbx + SI_text], 0
    je 9f
    mov rdi, [rbx + SI_ext]
    cmp dword ptr [rdi + EXT_disabled], 0
    jne 8f
    call ext_is_visible
    test eax, eax
    jz 9f
    test dword ptr [rbx + SI_flags], SIF_MANIFEST
    jnz 1f
    mov rax, [rbx + SI_ext]
    cmp dword ptr [rax + EXT_status], ES_RUNNING
    jne 8f
1:  mov rdi, [rbx + SI_when]
    mov eax, 1
    test rdi, rdi
    jz 9f
    call when_eval_fresh
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# si_before(a, b) -> eax 1 when item a goes first: higher priority, then its extension's order,
#   then its name
si_before:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + SI_prio]
    cmp eax, [r12 + SI_prio]
    jg 7f
    jl 8f
    mov rax, [rbx + SI_ext]
    cmp rax, [r12 + SI_ext]
    jb 7f
    ja 8f
    mov rdi, [rbx + SI_name]
    mov rsi, [r12 + SI_name]
    call strcmp_less
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# strcmp_less(a, b) -> eax 1 when a sorts before b by bytes
strcmp_less:
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    movzx edx, byte ptr [rsi + rcx]
    cmp eax, edx
    jb 7f
    ja 8f
    test eax, eax
    jz 8f
    inc rcx
    jmp 1b
7:  mov eax, 1
    ret
8:  xor eax, eax
    ret

# si_measure(si, draw?, x, y, h, argb) -> eax the content's width: icons "$(NAME)" (at most 4) and
#   text in the small face; draws it at x when asked
si_measure:
    PROLOGUE 16
    mov rbx, rdi
    mov [rip + sm_draw], esi
    mov [rip + sm_x], edx
    mov [rip + sm_y], ecx
    mov [rip + sm_h], r8d
    mov [rip + sm_argb], r9d
    mov dword ptr [rip + sm_icons], 0
    mov dword ptr [rip + sm_width], 0
    mov r12, [rbx + SI_text]
    mov rdi, r12
    call strlen
    lea r13, [r12 + rax]        # the end
    mov r14, r12                # the run of text not drawn yet
.Lsm2_scan:
    cmp r12, r13
    jae .Lsm2_flush_end
    cmp byte ptr [r12], '$'
    jne 1f
    lea rax, [r12 + 1]
    cmp rax, r13
    jae 1f
    cmp byte ptr [rax], '('
    jne 1f
    cmp dword ptr [rip + sm_icons], SI_ICONS_MAX
    jae 1f
    # the name up to ")"
    lea r15, [r12 + 2]
    mov rax, r15
2:  cmp rax, r13
    jae 1f
    cmp byte ptr [rax], ')'
    je 3f
    inc rax
    jmp 2b
3:  mov [rsp], rax              # the ")"
    mov rdi, r15
    mov rsi, rax
    sub rsi, r15
    mov rdx, [rbx + SI_ext]
    call icon_spec_known
    test eax, eax
    jz 1f
    # the text before it, then the icon
    mov rdi, r14
    mov rsi, r12
    sub rsi, r14
    call si_run_text
    M eax, MI_14
    mov [rsp + 8], eax
    cmp dword ptr [rip + sm_draw], 0
    je 4f
    mov rdi, r15
    mov rsi, [rsp]
    sub rsi, r15
    mov rdx, [rbx + SI_ext]
    mov ecx, [rip + sm_x]
    mov r8d, [rip + sm_h]
    sub r8d, [rsp + 8]
    sar r8d, 1
    add r8d, [rip + sm_y]
    mov r9d, [rsp + 8]
    mov eax, [rip + sm_argb]
    push rax
    push rax
    call icon_spec_draw
    add rsp, 16
4:  mov eax, [rsp + 8]
    add eax, [rip + g_mt + 4*MI_4]
    add [rip + sm_x], eax
    add [rip + sm_width], eax
    inc dword ptr [rip + sm_icons]
    mov r12, [rsp]
    inc r12
    mov r14, r12
    jmp .Lsm2_scan
1:  inc r12
    jmp .Lsm2_scan
.Lsm2_flush_end:
    mov rdi, r14
    mov rsi, r13
    sub rsi, r14
    call si_run_text
    mov eax, [rip + sm_width]
    EPILOGUE

# si_run_text(ptr, len): a run of si_measure's text, measured and drawn when asked
si_run_text:
    test rsi, rsi
    jz 9f
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + g_face_small]
    mov rsi, r12
    mov rdx, r13
    call text_width
    mov r14d, eax
    cmp dword ptr [rip + sm_draw], 0
    je 1f
    lea rdi, [rip + g_face_small]
    mov esi, [rip + sm_x]
    mov edx, [rip + sm_y]
    mov ecx, [rip + sm_h]
    mov r8, r12
    mov r9, r13
    mov eax, [rip + sm_argb]
    push rax
    push rax
    call ui_text_v
    add rsp, 16
1:  add [rip + sm_x], r14d
    add [rip + sm_width], r14d
    EPILOGUE
9:  ret

# si_collect(bar w): si_order holds the items that show this frame, best first, within 40 % of the
#   bar (the lowest priorities drop first); widths measured
si_collect:
    PROLOGUE
    mov r15d, edi
    imul r15d, r15d, 40
    mov eax, r15d
    xor edx, edx
    mov ecx, 100
    div ecx
    mov r15d, eax               # the budget
    call ctx_refresh
    mov qword ptr [rip + si_norder], 0
    xor ebx, ebx
1:  cmp rbx, [rip + si_items + VEC_len]
    jae 3f
    mov rdi, rbx
    call si_at
    mov r12, rax
    mov dword ptr [r12 + SI_shown], 0
    mov rdi, r12
    call si_visible
    test eax, eax
    jz 2f
    cmp qword ptr [rip + si_norder], 512
    jae 3f
    # sorted insert
    mov r13, [rip + si_norder]
4:  test r13, r13
    jz 5f
    lea rax, [rip + si_order]
    mov rdi, [rax + r13*8 - 8]
    call si_at
    mov rsi, rax
    mov rdi, r12
    call si_before
    test eax, eax
    jz 5f
    lea rax, [rip + si_order]
    mov rcx, [rax + r13*8 - 8]
    mov [rax + r13*8], rcx
    dec r13
    jmp 4b
5:  lea rax, [rip + si_order]
    mov [rax + r13*8], rbx
    inc qword ptr [rip + si_norder]
2:  inc rbx
    jmp 1b
3:  # widths, within the budget
    xor r14d, r14d              # used
    xor ebx, ebx
6:  cmp rbx, [rip + si_norder]
    jae 9f
    lea rax, [rip + si_order]
    mov rdi, [rax + rbx*8]
    call si_at
    mov r12, rax
    inc rbx
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call si_measure
    mov r13d, eax
    mov edi, SI_CUT
    call sc
    cmp r13d, eax
    cmova r13d, eax
    mov [r12 + SI_width], r13d
    lea eax, [r13 + 0]
    add eax, [rip + g_mt + 4*MI_20]
    add eax, r14d
    cmp eax, r15d
    ja 6b                       # this one does not fit; a smaller one after it may
    mov r14d, eax
    mov dword ptr [r12 + SI_shown], 1
    jmp 6b
9:  EPILOGUE

# si_draw_item(si, index, x, y, h) -> eax its button's width: the background, the content (cut with
#   "…" past SI_CUT), hover, tooltip and a click
si_draw_item:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi              # index
    mov [rsp + 4], edx          # x: the content's left
    mov [rsp + 8], ecx          # y
    mov [rsp + 12], r8d         # h
    mov eax, [rbx + SI_width]
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 16], eax         # the button's width
    mov eax, [rsp + 4]
    sub eax, [rip + g_mt + 4*MI_6]
    mov [rbx + SI_x], eax
    mov eax, [rsp + 8]
    add eax, [rip + g_mt + 4*MI_3]
    mov [rbx + SI_y], eax
    mov eax, [rsp + 16]
    mov [rbx + SI_w], eax
    mov eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_6]
    mov [rbx + SI_h], eax
    mov edi, [rsp]
    add edi, ID_STATUS_ITEM
    mov esi, [rbx + SI_x]
    mov edx, [rbx + SI_y]
    mov ecx, [rbx + SI_w]
    mov r8d, [rbx + SI_h]
    call ui_btn
    mov r12d, eax
    # the background: an error or warning color, or the hover of an item with a command
    mov eax, [rbx + SI_bg]
    test eax, eax
    jnz 1f
    test r12d, UB_HOVER
    jz 2f
    cmp qword ptr [rbx + SI_cname], 0
    je 2f
    mov eax, T_HOVER
1:  lea rcx, [rip + g_theme]
    mov r9d, [rcx + rax*4]
    mov edi, [rbx + SI_x]
    mov esi, [rbx + SI_y]
    mov edx, [rbx + SI_w]
    mov ecx, [rbx + SI_h]
    M r8d, MI_RADIUS
    call gfx_round_rect
2:  test r12d, UB_HOVER
    jz 3f
    cmp qword ptr [rbx + SI_cname], 0
    je 3f
    mov dword ptr [rip + g_cursor], CUR_POINTER
3:  mov rax, [rbx + SI_tip]
    test rax, rax
    jz 31f
    mov edi, [rsp]
    add edi, ID_STATUS_ITEM
    mov esi, [rbx + SI_x]
    mov edx, [rsp + 8]
    mov ecx, [rbx + SI_w]
    mov r8d, r12d
    mov r9, rax
    call tip_note_text
31: # the content, clipped to its width
    mov edi, [rsp + 4]
    mov esi, [rsp + 8]
    mov edx, [rbx + SI_width]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    mov eax, [rbx + SI_color]
    cmp dword ptr [rbx + SI_bg], 0
    je 4f
    mov eax, T_ACCENT_FG        # readable on the error or warning color
4:  lea rcx, [rip + g_theme]
    mov r9d, [rcx + rax*4]
    mov rdi, rbx
    mov esi, 1
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call si_measure
    call gfx_clip_pop
    # a click runs its command (FROM ref); one gone meanwhile toasts
    test r12d, UB_CLICK
    jz 9f
    mov rdi, rbx
    call si_run
9:  mov eax, [rsp + 16]
    EPILOGUE

# si_run(si): its command, FROM ref, ARGS as the body
si_run:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + SI_cname]
    test rsi, rsi
    jz 9f
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rdi, [rbx + SI_ext]
    mov rsi, [rbx + SI_cname]
    mov rcx, [rbx + SI_args]
    mov r8, [rbx + SI_alen]
    test rcx, rcx
    jnz 1f
    lea rcx, [rip + .Lv1]
    xor r8d, r8d
1:  call cmdref_new
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    call cmdref_invoke
    mov rdi, r12
    call cmdref_free
9:  EPILOGUE

# FN status_items_right(x right, y, h, bar w) -> eax the x left of them: the right-aligned items,
#   the lowest priority rightmost
FN status_items_right
    PROLOGUE 16
    mov r12d, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov edi, ecx
    call si_collect
    mov r13, [rip + si_norder]
1:  test r13, r13
    jz 9f
    dec r13
    lea rax, [rip + si_order]
    mov rdi, [rax + r13*8]
    mov r14, rdi
    call si_at
    mov rbx, rax
    cmp dword ptr [rbx + SI_shown], 0
    je 1b
    cmp dword ptr [rbx + SI_align], 0
    jne 1b
    sub r12d, [rip + g_mt + 4*MI_12]
    sub r12d, [rbx + SI_width]
    mov rdi, rbx
    mov esi, r14d
    mov edx, r12d
    mov ecx, [rsp]
    mov r8d, [rsp + 4]
    call si_draw_item
    sub r12d, [rip + g_mt + 4*MI_8]
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# FN status_items_left(x, y, h, limit) -> eax the x after them: the left-aligned items, the highest
#   priority leftmost, up to limit
FN status_items_left
    PROLOGUE 16
    mov r12d, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    xor r13d, r13d
1:  cmp r13, [rip + si_norder]
    jae 9f
    lea rax, [rip + si_order]
    mov rdi, [rax + r13*8]
    mov r14, rdi
    inc r13
    call si_at
    mov rbx, rax
    cmp dword ptr [rbx + SI_shown], 0
    je 1b
    cmp dword ptr [rbx + SI_align], 0
    je 1b
    mov eax, r12d
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rbx + SI_width]
    add eax, [rip + g_mt + 4*MI_6]
    cmp eax, [rsp + 8]
    jg 2f
    mov edx, r12d
    add edx, [rip + g_mt + 4*MI_6]
    mov rdi, rbx
    mov esi, r14d
    mov ecx, [rsp]
    mov r8d, [rsp + 4]
    call si_draw_item
    add r12d, eax
    add r12d, [rip + g_mt + 4*MI_4]
    jmp 1b
2:  mov dword ptr [rbx + SI_shown], 0   # no room left of the file's items
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# FN status_dump(out sb): print-status: a line per item, "side=right prio=0 owner=O/N item=I
#   text=T tooltip=TT command=C shown=0|1 at=X,Y,W,H"
FN status_dump
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + si_items + VEC_len]
    jae 9f
    mov rdi, rbx
    call si_at
    mov r13, rax
    inc rbx
    mov rdi, r12
    lea rsi, [rip + .Ld_side]
    call sb_push_cstr
    lea rsi, [rip + .Lv_right]
    cmp dword ptr [r13 + SI_align], 0
    je 2f
    lea rsi, [rip + .Lv_left]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_prio]
    call sb_push_cstr
    movsxd rax, dword ptr [r13 + SI_prio]
    test rax, rax
    jns 3f
    push rax
    push rax
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    pop rax
    pop rax
    neg rax
3:  mov rdi, r12
    mov rsi, rax
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_owner]
    call sb_push_cstr
    mov rax, [r13 + SI_ext]
    mov rdi, r12
    mov rsi, [rax + EXT_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rax, [r13 + SI_ext]
    mov rdi, r12
    mov rsi, [rax + EXT_name]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_item]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r13 + SI_name]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_text]
    call sb_push_cstr
    mov rsi, [r13 + SI_text]
    test rsi, rsi
    jz 4f
    mov rdi, r12
    call sb_push_cstr
4:  mov rdi, r12
    lea rsi, [rip + .Ld_tooltip]
    call sb_push_cstr
    mov rsi, [r13 + SI_tip]
    test rsi, rsi
    jz 5f
    mov rdi, r12
    call si_push_line
5:  mov rdi, r12
    lea rsi, [rip + .Ld_command]
    call sb_push_cstr
    mov rsi, [r13 + SI_cname]
    test rsi, rsi
    jz 6f
    mov rdi, r12
    call sb_push_cstr
6:  mov rdi, r12
    lea rsi, [rip + .Ld_shown]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r13 + SI_shown]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    xor r14d, r14d
7:  mov rdi, r12
    mov esi, [r13 + SI_x + r14*4]
    call sb_push_u64
    inc r14d
    cmp r14d, 4
    jae 8f
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
    jmp 7b
8:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE
# si_push_line(sb, cstr): the text with line breaks as "\n"
si_push_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 9f
    inc r12
    cmp eax, 10
    jne 2f
    mov rdi, rbx
    mov esi, '\\'
    call sb_push_byte
    mov esi, 'n'
    jmp 3f
2:  mov esi, eax
3:  mov rdi, rbx
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
color_names: .quad .Lc_fg, T_FG, .Lc_muted, T_MUTED, .Lc_accent, T_ACCENT, .Lc_error, T_ERROR
    .quad .Lc_warning, T_WARNING, .Lc_success, T_SUCCESS, 0, 0
.Lc_fg: .asciz "fg"
.Lc_muted: .asciz "muted"
.Lc_accent: .asciz "accent"
.Lc_error: .asciz "error"
.Lc_warning: .asciz "warning"
.Lc_success: .asciz "success"
.Ls_status: .asciz "status"
.Lf_text: .asciz "text"
.Lf_tooltip: .asciz "tooltip"
.Lf_command: .asciz "command"
.Lf_args: .asciz "args"
.Lf_align: .asciz "align"
.Lf_priority: .asciz "priority"
.Lf_color: .asciz "color"
.Lf_background: .asciz "background"
.Lf_when: .asciz "when"
.Lv_left: .asciz "left"
.Lv_right: .asciz "right"
.Lv1: .asciz "_v1"
.Lx_command: .asciz "command"
.Lx_color: .asciz "color"
.Lx_background: .asciz "background"
.Lx_when: .asciz "when"
.Lp_status: .asciz "not ITEM.text, .tooltip, .command, .args, .align, .priority, .color, .background or .when"
.Lp_full: .asciz "more than 8 status items: dropped"
.Ld_side: .asciz "side="
.Ld_prio: .asciz " prio="
.Ld_owner: .asciz " owner="
.Ld_item: .asciz " item="
.Ld_text: .asciz " text="
.Ld_tooltip: .asciz " tooltip="
.Ld_command: .asciz " command="
.Ld_shown: .asciz " shown="
.Ld_at: .asciz " at="
