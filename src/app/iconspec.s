# named icons for status items, menu items and buttons: a built-in icon by name ("play",
# "chevron-right") or an extension's own PNG from its manifest's [icons] ("ext:logo"). An [icons]
# PNG whose pixels are all grey is drawn as a mask in the text's color, otherwise as it is.
#
# For other parts of rhun:
#   icon_spec_draw(spec, len, ext, x, y, size, argb) -> eax 1 when it drew the icon
#   icon_spec_known(spec, len, ext) -> eax 1 when the name is an icon (for "$(NAME)" in text)
.include "rhun.inc"

# an [icons] entry (ei_list[extension index])
.equ EI_name, 0                 # owned cstr
.equ EI_path, 8                 # owned cstr, relative to the extension's folder
.equ EI_state, 16               # 0 not read, 1 read, 2 cannot be shown
.equ EI_grey, 20                # 1: a mask
.equ EI_img, 24                 # IMG
.equ EI_size, 24 + IMG_SIZE     # the size of the kept copy
.equ EI_px, 32 + IMG_SIZE       # the kept copy, or 0
.equ EI_SIZE, 40 + IMG_SIZE
.equ EI_MAX, 32                 # [icons] entries per extension
.equ EI_DRAW_MAX, 64            # pixels a side an icon is drawn at, at most

.bss
.p2align 3
ei_list: .zero EXT_CAP * VEC_SIZE
ei_tint: .zero EI_DRAW_MAX * EI_DRAW_MAX * 4

.text

# ei_vec(ext) -> rax its VEC of EI records, or 0
ei_vec:
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    cmp rax, EXT_CAP
    jae 8f
    imul rax, rax, VEC_SIZE
    lea rcx, [rip + ei_list]
    add rax, rcx
    ret
8:  xor eax, eax
    ret

# FN iconspec_manifest_kv(ext, ini) -> eax 1 for an [icons] line: NAME = PNG
FN iconspec_manifest_kv
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Ls_icons]
    call ini_sec_is
    test eax, eax
    jz 8f
    mov rdi, [r12 + INI_key]
    mov rsi, [r12 + INI_keylen]
    call ei_name_ok
    test eax, eax
    jz 7f
    mov rdi, rbx
    call ei_vec
    test rax, rax
    jz 9f
    mov r13, rax
    cmp qword ptr [r13 + VEC_len], EI_MAX
    jae 7f
    mov rdi, r13
    mov esi, EI_SIZE
    call vec_push
    mov r14, rax
    mov rdi, r14
    xor esi, esi
    mov edx, EI_SIZE
    call memset
    mov rdi, [r12 + INI_key]
    mov rsi, [r12 + INI_keylen]
    call mem_dup
    mov [r14 + EI_name], rax
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call trim
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov [r14 + EI_path], rax
9:  mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lp_icon]
    call contrib_problem_line
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ei_name_ok(ptr, len) -> eax 1 for 1 to 40 of [a-z0-9_-]
ei_name_ok:
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 40
    ja 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    inc rcx
    cmp dl, '_'
    je 2f
    cmp dl, '-'
    je 2f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 2f
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    ja 9f
2:  cmp rcx, rsi
    jb 1b
    mov eax, 1
9:  ret

# FN iconspec_ext_gone(ext): its [icons] go
FN iconspec_ext_gone
    PROLOGUE
    call ei_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    imul r13, r12, EI_SIZE
    add r13, [rbx + VEC_ptr]
    inc r12
    mov rdi, [r13 + EI_name]
    call mem_free
    mov rdi, [r13 + EI_path]
    call mem_free
    mov rdi, [r13 + EI_px]
    call mem_free
    cmp dword ptr [r13 + EI_state], 1
    jne 1b
    lea rdi, [r13 + EI_img]
    call image_free
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
9:  EPILOGUE

# ei_find(ext, name, len) -> rax its EI, or 0
ei_find:
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    test rdi, rdi
    jz 8f
    call ei_vec
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 8f
    imul r15, r14, EI_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + EI_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# builtin_icon(name, len) -> eax IC_* of a built-in icon's name, or -1
builtin_icon:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + icon_names]
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

# FN icon_spec_known(spec, len, ext) -> eax 1 when spec names an icon: a built-in one, or ext:NAME
#   of the extension's [icons]
FN icon_spec_known
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lext_colon]
    mov ecx, 4
    call str_starts
    test eax, eax
    jnz 1f
    mov rdi, r12
    mov rsi, r13
    call builtin_icon
    not eax
    shr eax, 31                 # -1 -> 0, an index -> 1
    EPILOGUE
1:  mov rdi, rbx
    lea rsi, [r12 + 4]
    lea rdx, [r13 - 4]
    call ei_find
    test rax, rax
    setnz al
    movzx eax, al
    EPILOGUE

# FN icon_spec_draw(spec, len, ext, x, y, size, argb) -> eax 1 when it drew the icon, size x size at
#   x, y: a built-in one in argb, an [icons] PNG as it is (all grey: a mask in argb)
FN icon_spec_draw
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov [rsp], ecx              # x
    mov [rsp + 4], r8d          # y
    mov [rsp + 8], r9d          # size
    mov eax, [rbp + 16]         # argb, the 7th argument
    mov [rsp + 12], eax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lext_colon]
    mov ecx, 4
    call str_starts
    test eax, eax
    jnz 2f
    mov rdi, r12
    mov rsi, r13
    call builtin_icon
    test eax, eax
    js 8f
    mov edi, eax
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call icon_draw
    mov eax, 1
    EPILOGUE
2:  mov rdi, rbx
    lea rsi, [r12 + 4]
    lea rdx, [r13 - 4]
    call ei_find
    test rax, rax
    jz 8f
    mov r14, rax
    mov eax, [rsp + 8]
    lea ecx, [rax - 1]
    cmp ecx, EI_DRAW_MAX - 1
    ja 8f
    # read once
    cmp dword ptr [r14 + EI_state], 0
    jne 3f
    mov dword ptr [r14 + EI_state], 2
    mov rdi, [rbx + EXT_dir]
    mov rsi, [r14 + EI_path]
    mov edx, ICON_MAXBYTES
    mov ecx, ICON_MAXDIM
    lea r8, [r14 + EI_img]
    call png_icon_read
    test eax, eax
    jz 8f
    mov dword ptr [r14 + EI_state], 1
    mov rdi, r14
    call ei_check_grey
3:  cmp dword ptr [r14 + EI_state], 1
    jne 8f
    # the kept copy at this size
    mov eax, [rsp + 8]
    cmp [r14 + EI_size], eax
    jne 4f
    cmp qword ptr [r14 + EI_px], 0
    jne 5f
4:  mov rdi, [r14 + EI_px]
    call mem_free
    mov qword ptr [r14 + EI_px], 0
    lea rdi, [r14 + EI_img]
    mov esi, [rsp + 8]
    call icon_fit
    test rax, rax
    jz 8f
    mov [r14 + EI_px], rax
    mov eax, [rsp + 8]
    mov [r14 + EI_size], eax
5:  mov rsi, [r14 + EI_px]
    cmp dword ptr [r14 + EI_grey], 0
    je 7f
    # a mask: its alpha in argb's color
    mov ecx, [rsp + 8]
    imul ecx, ecx
    lea rdi, [rip + ei_tint]
    mov r8d, [rsp + 12]
6:  test ecx, ecx
    jz 61f
    dec ecx
    movzx eax, byte ptr [rsi + rcx*4 + 3]   # alpha
    mov r9d, r8d
    shr r9d, 24
    imul eax, r9d
    xor edx, edx
    mov r10d, 255
    div r10d                    # alpha scaled by argb's alpha
    mov r11d, eax
    shl r11d, 24
    mov r9d, r8d
    and r9d, 255
    imul r9d, eax
    push rax
    mov eax, r9d
    xor edx, edx
    div r10d
    or r11d, eax
    pop rax
    mov r9d, r8d
    shr r9d, 8
    and r9d, 255
    imul r9d, eax
    push rax
    mov eax, r9d
    xor edx, edx
    div r10d
    shl eax, 8
    or r11d, eax
    pop rax
    mov r9d, r8d
    shr r9d, 16
    and r9d, 255
    imul r9d, eax
    mov eax, r9d
    xor edx, edx
    div r10d
    shl eax, 16
    or r11d, eax
    mov [rdi + rcx*4], r11d
    jmp 6b
61: lea rsi, [rip + ei_tint]
7:  mov rdx, rsi                # gfx_blit(x, y, px, w, h)
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, ecx
    call gfx_blit
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ei_check_grey(ei): EI_grey 1 when every pixel has red = green = blue
ei_check_grey:
    mov rsi, [rdi + EI_img + IMG_px]
    mov eax, [rdi + EI_img + IMG_w]
    imul eax, [rdi + EI_img + IMG_h]
    mov ecx, eax
    mov dword ptr [rdi + EI_grey], 0
1:  test ecx, ecx
    jz 2f
    dec ecx
    mov eax, [rsi + rcx*4]
    movzx edx, al
    mov r8d, eax
    shr r8d, 8
    movzx r8d, r8b
    cmp edx, r8d
    jne 9f
    shr eax, 16
    movzx eax, al
    cmp edx, eax
    jne 9f
    jmp 1b
2:  mov dword ptr [rdi + EI_grey], 1
9:  ret

.section .rodata
.p2align 3
# the built-in icons an extension can name: name, IC_*
icon_names:
    .quad .Ln_chevron_right, IC_CHEV_R, .Ln_chevron_down, IC_CHEV_D, .Ln_chevron_up, IC_CHEV_UP
    .quad .Ln_folder, IC_FOLDER, .Ln_file, IC_FILE, .Ln_close, IC_CLOSE, .Ln_search, IC_SEARCH
    .quad .Ln_spark, IC_SPARK, .Ln_dot, IC_DOT, .Ln_plus, IC_PLUS, .Ln_minus, IC_MINUS
    .quad .Ln_check, IC_CHECK, .Ln_terminal, IC_TERMINAL, .Ln_back, IC_BACK, .Ln_user, IC_USER
    .quad .Ln_arrow_up, IC_ARROW_UP, .Ln_arrow_down, IC_ARROW_DN, .Ln_refresh, IC_REFRESH
    .quad .Ln_sync, IC_REFRESH, .Ln_branch, IC_BRANCH, .Ln_discard, IC_DISCARD
    .quad .Ln_file_plus, IC_FILE_PLUS, .Ln_folder_plus, IC_FOLDER_PLUS, .Ln_sliders, IC_SLIDERS
    .quad .Ln_play, IC_PLAY, .Ln_stop, IC_STOP, .Ln_debug, IC_DEBUG, .Ln_bug, IC_BUG
    .quad .Ln_warning, IC_WARNING, .Ln_error, IC_ERROR, .Ln_info, IC_INFO, .Ln_bell, IC_BELL
    .quad .Ln_gear, IC_GEAR, .Ln_edit, IC_EDIT, .Ln_trash, IC_TRASH, .Ln_eye, IC_EYE, .Ln_pin, IC_PIN
    .quad .Ln_lock, IC_LOCK, .Ln_copy, IC_COPY, .Ln_filter, IC_FILTER, .Ln_list, IC_LIST
    .quad .Ln_beaker, IC_BEAKER, .Ln_cloud, IC_CLOUD, .Ln_more, IC_MORE, .Ln_extensions, IC_PUZZLE
    .quad 0, 0
.Ln_chevron_right: .asciz "chevron-right"
.Ln_chevron_down: .asciz "chevron-down"
.Ln_chevron_up: .asciz "chevron-up"
.Ln_folder: .asciz "folder"
.Ln_file: .asciz "file"
.Ln_close: .asciz "close"
.Ln_search: .asciz "search"
.Ln_spark: .asciz "spark"
.Ln_dot: .asciz "dot"
.Ln_plus: .asciz "plus"
.Ln_minus: .asciz "minus"
.Ln_check: .asciz "check"
.Ln_terminal: .asciz "terminal"
.Ln_back: .asciz "back"
.Ln_user: .asciz "user"
.Ln_arrow_up: .asciz "arrow-up"
.Ln_arrow_down: .asciz "arrow-down"
.Ln_refresh: .asciz "refresh"
.Ln_sync: .asciz "sync"
.Ln_branch: .asciz "branch"
.Ln_discard: .asciz "discard"
.Ln_file_plus: .asciz "file-plus"
.Ln_folder_plus: .asciz "folder-plus"
.Ln_sliders: .asciz "sliders"
.Ln_play: .asciz "play"
.Ln_stop: .asciz "stop"
.Ln_debug: .asciz "debug"
.Ln_bug: .asciz "bug"
.Ln_warning: .asciz "warning"
.Ln_error: .asciz "error"
.Ln_info: .asciz "info"
.Ln_bell: .asciz "bell"
.Ln_gear: .asciz "gear"
.Ln_edit: .asciz "edit"
.Ln_trash: .asciz "trash"
.Ln_eye: .asciz "eye"
.Ln_pin: .asciz "pin"
.Ln_lock: .asciz "lock"
.Ln_copy: .asciz "copy"
.Ln_filter: .asciz "filter"
.Ln_list: .asciz "list"
.Ln_beaker: .asciz "beaker"
.Ln_cloud: .asciz "cloud"
.Ln_more: .asciz "more"
.Ln_extensions: .asciz "extensions"
.Ls_icons: .asciz "icons"
.Lext_colon: .asciz "ext:"
.Lp_icon: .asciz "not NAME = PNG (NAME: 1 to 40 of a-z 0-9 _ -), or more than 32 icons"
