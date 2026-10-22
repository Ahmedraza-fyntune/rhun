# contributions group: the Extensions page's "Contributions" block (like VS Code's Feature
# Contributions): what an extension adds, under a heading per kind (Commands, Keys, Menus, Status
# bar, Settings, Languages, File icon themes, Views), a row each with a detail line, and the entries
# of its manifest that were dropped (Problems). Rows are made again for each frame that shows them.
#
# A part that lists its own records makes a row with contrib_page_text / contrib_page_text_n (the
# row's text), contrib_page_part (" · " before the next part of the detail, when there is one),
# contrib_page_detail / contrib_page_detail_n, contrib_page_tone (1 a warning, 2 an error) and
# contrib_page_end; the heading set before shows with its first row:
#   keys_page_rows (keys.s), menu_page_rows (menu.s), status_page_rows (statusitems.s),
#   syntax_page_rows (syntax.s), langconf_page_rows (langconf.s), iconth_page_rows (iconth.s),
#   rview_page_rows (rview.s)
.include "rhun.inc"
.equ CP_ROWS, 300
.equ CP_TEXT, 65536
.equ CP_PART, 400               # bytes of a row's text or its detail, at most
STRUCT
F CPR_kind, 4                   # 0 a heading, 1 a row
F CPR_tone, 4
F CPR_text, 4                   # offsets in cp_text
F CPR_detail, 4                 # or -1
ENDSTRUCT CPR_SIZE

.bss
.p2align 3
cp_rows: .zero CP_ROWS * CPR_SIZE
cp_n: .quad 0
cp_len: .quad 0
cp_head: .quad 0                # the heading waiting for its first row, or 0
cp_more: .quad 0                # rows that did not fit
cp_tl: .quad 0
cp_dl: .quad 0
cp_tone: .long 0
cp_pad: .long 0
cp_t: .zero CP_PART + 8         # the row being made
cp_d: .zero CP_PART + 8
cp_text: .zero CP_TEXT

.text

# FN contrib_page_head(cstr): the heading of the rows that follow (a string that stays)
FN contrib_page_head
    mov [rip + cp_head], rdi
    ret

# FN contrib_page_text(cstr) / contrib_page_text_n(ptr, len): more of the row's text
FN contrib_page_text
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call contrib_page_text_n
    EPILOGUE
FN contrib_page_text_n
    PROLOGUE
    lea rdx, [rip + cp_t]
    lea rcx, [rip + cp_tl]
    call cp_append
    EPILOGUE

# FN contrib_page_detail(cstr) / contrib_page_detail_n(ptr, len): more of the row's detail
FN contrib_page_detail
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call contrib_page_detail_n
    EPILOGUE
FN contrib_page_detail_n
    PROLOGUE
    lea rdx, [rip + cp_d]
    lea rcx, [rip + cp_dl]
    call cp_append
    EPILOGUE

# FN contrib_page_part(): " · " when the detail has something already
FN contrib_page_part
    PROLOGUE
    cmp qword ptr [rip + cp_dl], 0
    je 9f
    lea rdi, [rip + .Ldot]
    mov esi, 4
    lea rdx, [rip + cp_d]
    lea rcx, [rip + cp_dl]
    call cp_append
9:  EPILOGUE

# FN contrib_page_detail_int(value): a signed number onto the detail
FN contrib_page_detail_int
    PROLOGUE 32
    mov rbx, rdi
    test rbx, rbx
    jns 1f
    lea rdi, [rip + .Lminus]
    call contrib_page_detail
    neg rbx
1:  mov rdi, rbx
    mov rsi, rsp
    call fmt_u64_to
    mov rdi, rsp
    mov rsi, rax
    call contrib_page_detail_n
    EPILOGUE

# FN contrib_page_tone(tone): the row's color (the strongest asked for)
FN contrib_page_tone
    cmp edi, [rip + cp_tone]
    jbe 1f
    mov [rip + cp_tone], edi
1:  ret

# FN contrib_page_title(title cstr): the row's text, a command's title without the " (Extension)"
#   the palette adds
FN contrib_page_title
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    mov rcx, rax
1:  cmp rcx, 2
    jb 3f
    cmp byte ptr [rbx + rcx - 2], ' '
    jne 2f
    cmp byte ptr [rbx + rcx - 1], '('
    jne 2f
    lea r12, [rcx - 2]
    jmp 3f
2:  dec rcx
    jmp 1b
3:  mov rdi, rbx
    mov rsi, r12
    call contrib_page_text_n
    EPILOGUE

# cp_append(ptr, len, buffer, length var): as much as the buffer still holds, cut at a character's
#   start; control characters as spaces
cp_append:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdx, CP_PART
    sub rdx, [r14]
    jbe 9f
    mov rdi, r12
    mov rsi, rbx
    call utf8_cut
    mov r12, rax
    mov rdi, [r14]
    add rdi, r13
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rdi, [r14]
    add rdi, r13
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp byte ptr [rdi + rcx], 0x20
    jae 11f
    mov byte ptr [rdi + rcx], ' '
11: inc rcx
    jmp 1b
2:  add [r14], r12
9:  EPILOGUE

# FN contrib_page_end(): the row made (with its heading first, when that has not shown yet)
FN contrib_page_end
    PROLOGUE
    mov rax, [rip + cp_tl]
    or rax, [rip + cp_dl]
    jz 8f
    mov rax, [rip + cp_head]
    test rax, rax
    jz 1f
    # the heading, with room for its row
    mov rcx, [rip + cp_n]
    add rcx, 2
    cmp rcx, CP_ROWS
    ja 7f
    mov rdi, rax
    call strlen
    mov rdx, rax
    xor edi, edi
    xor esi, esi
    mov rcx, [rip + cp_head]
    mov r8, -1
    xor r9d, r9d
    call cp_store
    test eax, eax
    jz 7f
    mov qword ptr [rip + cp_head], 0
1:  mov edi, 1
    mov esi, [rip + cp_tone]
    mov rdx, [rip + cp_tl]
    lea rcx, [rip + cp_t]
    mov r8, [rip + cp_dl]
    test r8, r8
    jnz 2f
    mov r8, -1
2:  lea r9, [rip + cp_d]
    call cp_store
    test eax, eax
    jnz 8f
7:  inc qword ptr [rip + cp_more]
8:  mov qword ptr [rip + cp_tl], 0
    mov qword ptr [rip + cp_dl], 0
    mov dword ptr [rip + cp_tone], 0
    EPILOGUE

# cp_store(kind, tone, text len, text, detail len or -1, detail) -> eax 1 when it fit
cp_store:
    PROLOGUE 16
    mov [rsp], edi
    mov [rsp + 4], esi
    mov rbx, rdx
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    mov rax, [rip + cp_n]
    cmp rax, CP_ROWS
    jae 8f
    lea rax, [rbx + 2]
    test r13, r13
    js 1f
    add rax, r13
1:  add rax, [rip + cp_len]
    cmp rax, CP_TEXT
    ja 8f
    imul r15, [rip + cp_n], CPR_SIZE
    lea rax, [rip + cp_rows]
    add r15, rax
    mov eax, [rsp]
    mov [r15 + CPR_kind], eax
    mov eax, [rsp + 4]
    mov [r15 + CPR_tone], eax
    mov rax, [rip + cp_len]
    mov [r15 + CPR_text], eax
    mov rdi, r12
    mov rsi, rbx
    call cp_keep
    mov dword ptr [r15 + CPR_detail], -1
    test r13, r13
    js 2f
    mov rax, [rip + cp_len]
    mov [r15 + CPR_detail], eax
    mov rdi, r14
    mov rsi, r13
    call cp_keep
2:  inc qword ptr [rip + cp_n]
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# cp_keep(ptr, len): onto cp_text, NUL-ended
cp_keep:
    PROLOGUE
    mov rbx, rsi
    mov rsi, rdi
    lea rdi, [rip + cp_text]
    add rdi, [rip + cp_len]
    mov rdx, rbx
    call memcpy
    lea rdi, [rip + cp_text]
    add rdi, [rip + cp_len]
    mov byte ptr [rdi + rbx], 0
    lea rax, [rbx + 1]
    add [rip + cp_len], rax
    EPILOGUE

# FN contrib_page_build(ext) -> rax the rows: every part's, in the page's order
FN contrib_page_build
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    mov [rip + cp_n], rax
    mov [rip + cp_len], rax
    mov [rip + cp_head], rax
    mov [rip + cp_more], rax
    mov [rip + cp_tl], rax
    mov [rip + cp_dl], rax
    mov [rip + cp_tone], eax
    lea rdi, [rip + .Lh_commands]
    call contrib_page_head
    mov rdi, rbx
    call cp_commands
    lea rdi, [rip + .Lh_keys]
    call contrib_page_head
    mov rdi, rbx
    call keys_page_rows
    lea rdi, [rip + .Lh_menus]
    call contrib_page_head
    mov rdi, rbx
    call menu_page_rows
    lea rdi, [rip + .Lh_status]
    call contrib_page_head
    mov rdi, rbx
    call status_page_rows
    lea rdi, [rip + .Lh_settings]
    call contrib_page_head
    mov rdi, rbx
    call cp_settings
    lea rdi, [rip + .Lh_languages]
    call contrib_page_head
    mov rdi, rbx
    call syntax_page_rows
    mov rdi, rbx
    call langconf_page_rows
    lea rdi, [rip + .Lh_icons]
    call contrib_page_head
    mov rdi, rbx
    call iconth_page_rows
    lea rdi, [rip + .Lh_views]
    call contrib_page_head
    mov rdi, rbx
    call rview_page_rows
    lea rdi, [rip + .Lh_problems]
    call contrib_page_head
    mov rdi, rbx
    call cp_problems
    # what did not fit
    mov rax, [rip + cp_more]
    test rax, rax
    jz 9f
    mov qword ptr [rip + cp_head], 0
    mov rax, [rip + cp_n]       # the last row's place and its text's room
    test rax, rax
    jz 1f
    dec rax
    mov [rip + cp_n], rax
    imul rax, rax, CPR_SIZE
    lea rcx, [rip + cp_rows]
    mov eax, [rcx + rax + CPR_text]
    mov [rip + cp_len], rax
1:  inc qword ptr [rip + cp_more]
    lea rdi, [rip + .Lmore]
    call contrib_page_text
    mov rdi, [rip + cp_more]
    lea rsi, [rip + cp_t]
    add rsi, [rip + cp_tl]
    call fmt_u64_to
    add [rip + cp_tl], rax
    lea rdi, [rip + .Lmore_rows]
    call contrib_page_text
    call contrib_page_end
9:  mov rax, [rip + cp_n]
    EPILOGUE

# fmt_u64_to(value, dst) -> rax the digits written
fmt_u64_to:
    PROLOGUE 32
    mov rax, rdi
    mov rbx, rsi
    lea r12, [rsp + 31]
    xor r13d, r13d
    mov ecx, 10
1:  xor edx, edx
    div rcx
    add dl, '0'
    dec r12
    mov [r12], dl
    inc r13
    test rax, rax
    jnz 1b
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, r13
    EPILOGUE

# FN contrib_page_at(i) -> eax kind (0 heading, 1 row; -1 past the end), rdx text, rcx detail
#   or 0, r8d tone
FN contrib_page_at
    cmp rdi, [rip + cp_n]
    jae 8f
    imul rdi, rdi, CPR_SIZE
    lea rax, [rip + cp_rows]
    add rdi, rax
    lea r9, [rip + cp_text]
    mov edx, [rdi + CPR_text]
    add rdx, r9
    xor ecx, ecx
    movsxd rax, dword ptr [rdi + CPR_detail]
    test rax, rax
    js 1f
    lea rcx, [r9 + rax]
1:  mov r8d, [rdi + CPR_tone]
    mov eax, [rdi + CPR_kind]
    ret
8:  mov eax, -1
    ret

# FN contrib_page_dump(out sb, ext): print-ext-page-contributions: "head TEXT" and
#   "row plain|warning|error TEXT[ -- DETAIL]" lines
FN contrib_page_dump
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    call contrib_page_build
    xor ebx, ebx
1:  mov rdi, rbx
    call contrib_page_at
    cmp eax, -1
    je 9f
    inc rbx
    mov r13, rdx
    mov r14, rcx
    mov r15d, r8d
    lea rsi, [rip + .Ld_head]
    test eax, eax
    jz 2f
    lea rsi, [rip + .Ld_row]
    mov rdi, r12
    call sb_push_cstr
    lea rax, [rip + cp_tones]
    mov rsi, [rax + r15*8]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    call sb_push_cstr
    test r14, r14
    jz 3f
    mov rdi, r12
    lea rsi, [rip + .Ld_sep]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r14
    call sb_push_cstr
3:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# ---------------- the parts listed here ----------------

# cp_commands(ext): each of its commands: the title; its name and its key in force
cp_commands:
    PROLOGUE
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    mov r14, rax                # its index
    xor r12d, r12d
1:  cmp r12, [rip + g_ext_cmds + VEC_len]
    jae 9f
    mov rax, [rip + g_ext_owner + VEC_ptr]
    cmp [rax + r12*8], r14
    jne 7f
    imul r15, r12, CMD_SIZE
    add r15, [rip + g_ext_cmds + VEC_ptr]
    mov rdi, [r15 + CMD_title]
    call contrib_page_title
    mov rdi, [r15 + CMD_name]
    call contrib_page_detail
    mov rdi, r15
    call keys_for
    test rax, rax
    jz 2f
    mov rbx, rax
    call contrib_page_part
    mov rdi, rbx
    call contrib_page_detail
2:  call contrib_page_end
7:  inc r12
    jmp 1b
9:  EPILOGUE

# cp_settings(ext): each of its settings ([settings]): the title; its key, kind, default, options
cp_settings:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + EXT_sdefs + VEC_len]
    jae 9f
    imul r13, r12, SD_SIZE
    add r13, [rbx + EXT_sdefs + VEC_ptr]
    inc r12
    mov rdi, [r13 + SD_title]
    test rdi, rdi
    jnz 2f
    mov rdi, [r13 + SD_key]
2:  call contrib_page_text
    mov rdi, [r13 + SD_key]
    call contrib_page_detail
    call contrib_page_part
    mov eax, [r13 + SD_type]
    and eax, 3
    lea rcx, [rip + sdt_words]
    mov rdi, [rcx + rax*8]
    call contrib_page_detail
    cmp dword ptr [r13 + SD_type], SDT_CHOICE
    jne 3f
    mov rdi, [r13 + SD_opts]
    test rdi, rdi
    jz 3f
    mov r14, rdi
    lea rdi, [rip + .Lsp_of]
    call contrib_page_detail
    mov rdi, r14
    call contrib_page_detail
3:  mov rdi, [r13 + SD_default]
    test rdi, rdi
    jz 4f
    cmp byte ptr [rdi], 0
    je 4f
    mov r14, rdi
    call contrib_page_part
    lea rdi, [rip + .Ldefault]
    call contrib_page_detail
    mov rdi, r14
    call contrib_page_detail
4:  call contrib_page_end
    jmp 1b
9:  EPILOGUE

# cp_problems(ext): the entries of its manifest that were dropped, in the error color
cp_problems:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  mov rdi, rbx
    mov rsi, r12
    call contrib_problem_at
    test rax, rax
    jz 9f
    inc r12
    mov rdi, rax
    call contrib_page_text
    mov edi, 2
    call contrib_page_tone
    call contrib_page_end
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
cp_tones: .quad .Lt_plain, .Lt_warning, .Lt_error
sdt_words: .quad .Lsdt_string, .Lsdt_bool, .Lsdt_int, .Lsdt_choice
.Lt_plain: .asciz "plain "
.Lt_warning: .asciz "warning "
.Lt_error: .asciz "error "
.Ld_head: .asciz "head "
.Ld_row: .asciz "row "
.Ld_sep: .asciz " -- "
.Ldot: .asciz " \302\267 "
.Lh_commands: .asciz "Commands"
.Lh_keys: .asciz "Keys"
.Lh_menus: .asciz "Menus"
.Lh_status: .asciz "Status bar"
.Lh_settings: .asciz "Settings"
.Lh_languages: .asciz "Languages"
.Lh_icons: .asciz "File icon themes"
.Lh_views: .asciz "Views"
.Lh_problems: .asciz "Problems"
.Lsdt_string: .asciz "text"
.Lsdt_bool: .asciz "on or off"
.Lsdt_int: .asciz "number"
.Lsdt_choice: .asciz "choice"
.Lsp_of: .asciz " of "
.Ldefault: .asciz "default "
.Lmore: .asciz "and "
.Lminus: .asciz "-"
.Lmore_rows: .asciz " more"
