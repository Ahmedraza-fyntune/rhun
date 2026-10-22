# File icon themes (docs/extensions/v1.1.md "File icon themes"): an extension's
# icon-themes/NAME.icons (INI: title, fallback, [icons], [files], [extensions], [languages],
# [folders], [folders_open]) gives the explorer's icons, as PNGs (drawn as they are, or their alpha
# as a mask in a theme color) or rhun's own icons. The setting [ui] file_icons chooses rhun (the
# default), none or OWNER/NAME/THEME; Select File Icon Theme previews while it is open.
#
# For other parts of rhun:
#   iconth_gen() -> eax a number that changes whenever the icons do (explorer caches compare it)
#   iconth_file(name) / iconth_folder(name, open) -> eax ITV_RHUN (-1: rhun's own), ITV_NONE, a
#     rhun icon (icon | theme slot << 8) or ITV_IMAGE | slot << 16 | icon (slot 0xff: as it is)
#   iconth_draw(value, x, y, size): an ITV_IMAGE icon
.include "rhun.inc"

.equ ITH_ext, 0
.equ ITH_name, 8                # owned cstr: the file's name without .icons
.equ ITH_id, 16                 # owned cstr: OWNER/NAME/THEME
.equ ITH_dir, 24                # owned cstr: the folder of the .icons file
.equ ITH_title, 32              # owned cstr
.equ ITH_fallback, 40           # 1: a miss before "file" is rhun's icon
.equ ITH_file, 44               # icon indices, or -1
.equ ITH_folder, 48
.equ ITH_folder_open, 52
.equ ITH_icons, 56              # VEC of ICO
.equ ITH_maps, 56 + VEC_SIZE    # VEC of MAP
.equ ITH_SIZE, 56 + 2 * VEC_SIZE

.equ ICO_name, 0                # owned cstr
.equ ICO_path, 8                # owned cstr relative to ITH_dir, or 0 for rhun's icon
.equ ICO_rhun, 16               # rhun's icon
.equ ICO_color, 20              # a theme slot, or -1 (a PNG as it is; rhun's icon: grey)
.equ ICO_pic, 24                # PIC
.equ ICO_SIZE, 24 + PIC_SIZE

.equ MAP_kind, 0                # MK_*
.equ MAP_icon, 4                # ICO index (-1 until resolved)
.equ MAP_key, 8                 # owned cstr
.equ MAP_name, 16               # owned cstr: the icon's name, until resolved
.equ MAP_SIZE, 24
.equ MK_FILES, 1
.equ MK_EXTS, 2
.equ MK_LANGS, 3
.equ MK_FOLDERS, 4
.equ MK_FOLDERS_OPEN, 5

.equ ITH_FILE_MAX, 262144
.equ ITH_ICONS_MAX, 512
.equ ITH_MAPS_MAX, 4096
.equ ITH_THEMES_MAX, 64
.equ ITH_PNG_MAX, 65536
.equ ITH_PNG_DIM, 256

.data
.p2align 3
ith_preview: .quad -1           # Select File Icon Theme's row while it is open, or -1
ith_gen: .long 1
.bss
.p2align 3
ith_list: .zero VEC_SIZE        # ITH records
ith_mode: .long 0               # ITM_*
ith_cur: .quad 0                # the theme drawn (ITM_THEME)
ith_seen: .quad 0               # the setting's value last resolved (its pointer)
ith_seen_gen: .quad 0           # and the themes' generation then
ith_list_gen: .quad 0
ith_load_ext: .quad 0
ith_buf: .zero 256              # the setting's value as Select File Icon Theme writes it
ith_tmp: .zero SB_SIZE

.equ ITM_RHUN, 0
.equ ITM_NONE, 1
.equ ITM_THEME, 2

.text

# ---------------------------------------------------------------- loading

# FN iconth_add_dir(ext): the themes in the extension's icon-themes folder (its earlier ones go)
FN iconth_add_dir
    PROLOGUE
    mov rbx, rdi
    call iconth_ext_gone
    mov [rip + ith_load_ext], rbx
    mov rdi, [rbx + EXT_dir]
    lea rsi, [rip + .Ldir_icons]
    call path_join
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + .Lsuffix]
    lea rdx, [rip + ith_load]
    call dir_each_suffix
    mov rdi, r12
    call mem_free
    mov qword ptr [rip + ith_load_ext], 0
    EPILOGUE

# ith_load(path, name): one .icons file
ith_load:
    PROLOGUE 64
    mov r12, rdi
    mov r13, rsi
    cmp qword ptr [rip + ith_list + VEC_len], ITH_THEMES_MAX
    jae 9f
    mov rdi, r12
    mov esi, ITH_FILE_MAX       # a larger file is refused before its bytes are read
    call file_read_limited
    test rax, rax
    jz 9f
    mov r14, rax
    mov r15, rdx
    lea rdi, [rip + ith_list]
    mov esi, ITH_SIZE
    call vec_push
    mov rbx, rax
    mov rax, [rip + ith_load_ext]
    mov [rbx + ITH_ext], rax
    mov dword ptr [rbx + ITH_file], -1
    mov dword ptr [rbx + ITH_folder], -1
    mov dword ptr [rbx + ITH_folder_open], -1
    # its name: the file name without .icons
    mov rdi, r13
    call strlen
    lea rsi, [rax - 6]
    mov rdi, r13
    call mem_dup
    mov [rbx + ITH_name], rax
    mov rdi, rax
    call strlen
    mov [rsp + 48], rax
    # its id: OWNER/NAME/THEME
    lea rdi, [rip + ith_tmp]
    call sb_clear
    mov rax, [rbx + ITH_ext]
    lea rdi, [rip + ith_tmp]
    mov rsi, [rax + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + ith_tmp]
    mov esi, '/'
    call sb_push_byte
    mov rax, [rbx + ITH_ext]
    lea rdi, [rip + ith_tmp]
    mov rsi, [rax + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + ith_tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + ith_tmp]
    mov rsi, [rbx + ITH_name]
    call sb_push_cstr
    mov rdi, [rip + ith_tmp + SB_ptr]
    mov rsi, [rip + ith_tmp + SB_len]
    call mem_dup
    mov [rbx + ITH_id], rax
    # its folder
    mov rdi, r12
    call strlen
    mov rsi, rax
    mov rdi, r12
    call path_dirlen
    mov rsi, rax
    mov rdi, r12
    call mem_dup
    mov [rbx + ITH_dir], rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call ith_parse
    cmp qword ptr [rbx + ITH_title], 0
    jne 1f
    mov rdi, [rbx + ITH_name]
    mov rsi, [rsp + 48]
    call mem_dup
    mov [rbx + ITH_title], rax
1:  inc qword ptr [rip + ith_list_gen]
8:  mov rdi, r14
    call mem_free
9:  EPILOGUE

# ith_parse(theme, text, len): its keys; mappings resolved to icons at the end
ith_parse:
    PROLOGUE 96                 # 0 the INI iterator
    mov rbx, rdi
    lea rdi, [rsp]
    call ini_init
.Lip_next:
    lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz .Lip_done
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call trim
    mov r12, rax                # the value
    mov r13, rdx
    cmp qword ptr [rsp + INI_seclen], 0
    jne 2f
    # top level: title, fallback
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_title]
    call ini_key_is
    test eax, eax
    jz 1f
    mov rdi, [rbx + ITH_title]
    call mem_free
    mov rdi, r12
    mov rsi, r13
    cmp rsi, 80
    jbe 11f
    mov esi, 80
11: call mem_dup
    mov [rbx + ITH_title], rax
    jmp .Lip_next
1:  lea rdi, [rsp]
    lea rsi, [rip + .Lk_fallback]
    call ini_key_is
    test eax, eax
    jz .Lip_next
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lv_rhun]
    call str_eq_cstr
    mov [rbx + ITH_fallback], eax
    jmp .Lip_next
2:  lea rdi, [rsp]
    lea rsi, [rip + .Ls_icons]
    call ini_sec_is
    test eax, eax
    jz 3f
    mov rdi, rbx
    mov rsi, [rsp + INI_key]
    mov rdx, [rsp + INI_keylen]
    mov rcx, r12
    mov r8, r13
    call ith_icon
    jmp .Lip_next
3:  # a mapping section
    xor r14d, r14d
    lea r15, [rip + map_secs]
4:  mov rsi, [r15 + r14*8]
    test rsi, rsi
    jz .Lip_next
    inc r14d
    lea rdi, [rsp]
    call ini_sec_is
    test eax, eax
    jz 4b
    cmp qword ptr [rbx + ITH_maps + VEC_len], ITH_MAPS_MAX
    jae .Lip_next
    test r13, r13
    jz .Lip_next
    lea rdi, [rbx + ITH_maps]
    mov esi, MAP_SIZE
    call vec_push
    mov r15, rax
    mov [r15 + MAP_kind], r14d
    mov dword ptr [r15 + MAP_icon], -1
    mov rdi, [rsp + INI_key]
    mov rsi, [rsp + INI_keylen]
    call mem_dup
    mov [r15 + MAP_key], rax
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r15 + MAP_name], rax
    jmp .Lip_next
.Lip_done:
    # the special icons and the mappings, by name
    mov rdi, rbx
    lea rsi, [rip + .Ln_file]
    call ith_icon_index
    mov [rbx + ITH_file], eax
    mov rdi, rbx
    lea rsi, [rip + .Ln_folder]
    call ith_icon_index
    mov [rbx + ITH_folder], eax
    mov rdi, rbx
    lea rsi, [rip + .Ln_folder_open]
    call ith_icon_index
    mov [rbx + ITH_folder_open], eax
    xor r14d, r14d
5:  cmp r14, [rbx + ITH_maps + VEC_len]
    jae 9f
    imul r15, r14, MAP_SIZE
    add r15, [rbx + ITH_maps + VEC_ptr]
    inc r14
    mov rdi, rbx
    mov rsi, [r15 + MAP_name]
    call ith_icon_index
    mov [r15 + MAP_icon], eax
    mov rdi, [r15 + MAP_name]
    call mem_free
    mov qword ptr [r15 + MAP_name], 0
    jmp 5b
9:  EPILOGUE

# ith_icon(theme, name, nlen, value, vlen): an [icons] line: PNG [COLOR] or rhun:ICON [COLOR]
ith_icon:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    cmp qword ptr [rbx + ITH_icons + VEC_len], ITH_ICONS_MAX
    jae 9f
    test r13, r13
    jz 9f
    mov rdi, r14
    mov rsi, r15
    call next_word
    test rdx, rdx
    jz 9f
    mov [rsp], rax              # the source
    mov [rsp + 8], rdx
    add r14, rcx
    sub r15, rcx
    lea rdi, [rbx + ITH_icons]
    mov esi, ICO_SIZE
    call vec_push
    mov rbx, rax                # (the icon from here on)
    mov dword ptr [rbx + ICO_color], -1
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx + ICO_name], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Lrhun_colon]
    mov ecx, 5
    call str_starts
    test eax, eax
    jz 1f
    mov rdi, [rsp]
    add rdi, 5
    mov rsi, [rsp + 8]
    sub rsi, 5
    call file_icon_named
    test eax, eax
    jns 11f
    mov eax, IC_F_DEFAULT
11: mov [rbx + ICO_rhun], eax
    jmp 2f
1:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [rbx + ICO_path], rax
2:  mov rdi, r14
    mov rsi, r15
    call next_word
    test rdx, rdx
    jz 9f
    mov rdi, rax
    mov rsi, rdx
    call file_color_named
    mov [rbx + ICO_color], eax
9:  EPILOGUE

# ith_icon_index(theme, name cstr) -> eax its icon's index, or -1
ith_icon_index:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, [rbx + ITH_icons + VEC_len]
    jae 8f
    imul rax, r13, ICO_SIZE
    add rax, [rbx + ITH_icons + VEC_ptr]
    mov rdi, [rax + ICO_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 2f
    inc r13
    jmp 1b
2:  mov eax, r13d
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# ith_free(theme): what it owns
ith_free:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ITH_name]
    call mem_free
    mov rdi, [rbx + ITH_id]
    call mem_free
    mov rdi, [rbx + ITH_dir]
    call mem_free
    mov rdi, [rbx + ITH_title]
    call mem_free
    xor r12d, r12d
1:  cmp r12, [rbx + ITH_icons + VEC_len]
    jae 2f
    imul r13, r12, ICO_SIZE
    add r13, [rbx + ITH_icons + VEC_ptr]
    inc r12
    mov rdi, [r13 + ICO_name]
    call mem_free
    mov rdi, [r13 + ICO_path]
    call mem_free
    mov rdi, [r13 + ICO_pic + PIC_img + IMG_px]
    call mem_free
    mov rdi, [r13 + ICO_pic + PIC_px]
    call mem_free
    jmp 1b
2:  mov rdi, [rbx + ITH_icons + VEC_ptr]
    call mem_free
    xor r12d, r12d
3:  cmp r12, [rbx + ITH_maps + VEC_len]
    jae 4f
    imul r13, r12, MAP_SIZE
    add r13, [rbx + ITH_maps + VEC_ptr]
    inc r12
    mov rdi, [r13 + MAP_key]
    call mem_free
    mov rdi, [r13 + MAP_name]
    call mem_free
    jmp 3b
4:  mov rdi, [rbx + ITH_maps + VEC_ptr]
    call mem_free
    EPILOGUE

# FN iconth_ext_gone(ext): its themes go
FN iconth_ext_gone
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + ith_list + VEC_len]
1:  test r12, r12
    jz 9f
    dec r12
    imul r13, r12, ITH_SIZE
    add r13, [rip + ith_list + VEC_ptr]
    cmp [r13 + ITH_ext], rbx
    jne 1b
    mov rdi, r13
    call ith_free
    mov rdx, [rip + ith_list + VEC_len]
    sub rdx, r12
    dec rdx
    imul rdx, rdx, ITH_SIZE
    mov rdi, r13
    lea rsi, [r13 + ITH_SIZE]
    call memmove
    dec qword ptr [rip + ith_list + VEC_len]
    inc qword ptr [rip + ith_list_gen]
    mov qword ptr [rip + ith_cur], 0    # resolved again
    mov qword ptr [rip + ith_seen], -1
    jmp 1b
9:  EPILOGUE

# ---------------------------------------------------------------- the theme in use

# ith_find(id cstr) -> rax the theme of that id whose extension is on, or 0
ith_find:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + ith_list + VEC_len]
    jae 8f
    imul r13, rbx, ITH_SIZE
    add r13, [rip + ith_list + VEC_ptr]
    inc rbx
    mov rdi, [r13 + ITH_id]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [r13 + ITH_ext]
    call ext_is_visible
    test eax, eax
    jz 8f
    mov rax, [r13 + ITH_ext]
    cmp dword ptr [rax + EXT_disabled], 0
    jne 8f
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ith_resolve(): ith_mode and ith_cur from the preview row or the setting; ith_gen changes with them
ith_resolve:
    PROLOGUE
    mov rax, [rip + ith_preview]
    cmp rax, -1
    je 1f
    # a row of Select File Icon Theme: 0 rhun, 1 none, 2 + a theme's index
    mov ecx, ITM_RHUN
    xor edx, edx
    cmp rax, 1
    jb 5f
    mov ecx, ITM_NONE
    je 5f
    sub rax, 2
    cmp rax, [rip + ith_list + VEC_len]
    jae 4f
    imul rdx, rax, ITH_SIZE
    add rdx, [rip + ith_list + VEC_ptr]
    mov ecx, ITM_THEME
    jmp 5f
1:  call ith_sig                # the themes and whether their extensions are on
    mov rcx, rax
    mov rax, [rip + cfg_file_icons]
    cmp rax, [rip + ith_seen]
    jne 2f
    cmp rcx, [rip + ith_seen_gen]
    je 9f
2:  mov [rip + ith_seen], rax
    mov [rip + ith_seen_gen], rcx
    mov rbx, rax
    mov ecx, ITM_RHUN
    xor edx, edx
    test rbx, rbx
    jz 5f
    cmp byte ptr [rbx], 0
    je 5f
    mov rdi, rbx
    lea rsi, [rip + .Lv_rhun]
    call strcmp_eq
    mov ecx, ITM_RHUN
    xor edx, edx
    test eax, eax
    jnz 5f
    mov rdi, rbx
    lea rsi, [rip + .Lv_none]
    call strcmp_eq
    mov ecx, ITM_NONE
    xor edx, edx
    test eax, eax
    jnz 5f
    mov rdi, rbx
    call ith_find
    mov rdx, rax
    mov ecx, ITM_THEME
    test rax, rax
    jnz 5f
4:  mov ecx, ITM_RHUN           # a missing or turned-off theme: rhun's, the setting kept
    xor edx, edx
5:  cmp ecx, [rip + ith_mode]
    jne 6f
    cmp rdx, [rip + ith_cur]
    je 9f
6:  mov [rip + ith_mode], ecx
    mov [rip + ith_cur], rdx
    inc dword ptr [rip + ith_gen]
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ith_sig() -> rax what the theme in use depends on besides the setting: the list's generation and
#   which themes' extensions are on
ith_sig:
    mov rax, [rip + ith_list_gen]
    shl rax, 32
    xor ecx, ecx
1:  cmp rcx, [rip + ith_list + VEC_len]
    jae 9f
    imul rdx, rcx, ITH_SIZE
    add rdx, [rip + ith_list + VEC_ptr]
    mov rdx, [rdx + ITH_ext]
    inc rcx
    cmp dword ptr [rdx + EXT_status], ES_REMOVED
    je 2f
    cmp dword ptr [rdx + EXT_disabled], 0
    jne 2f
    mov r8d, 1
    shl r8, cl
    xor rax, r8
2:  jmp 1b
9:  ret

# FN iconth_gen() -> eax the icons' generation (explorer caches compare it)
FN iconth_gen
    sub rsp, 8
    call ith_resolve
    mov eax, [rip + ith_gen]
    add rsp, 8
    ret

# ith_value(icon index) -> eax the value of an icon of the theme in use, or ITV_RHUN for -1
ith_value:
    mov eax, ITV_RHUN
    test edi, edi
    js 9f
    mov rcx, [rip + ith_cur]
    imul rax, rdi, ICO_SIZE
    add rax, [rcx + ITH_icons + VEC_ptr]
    cmp qword ptr [rax + ICO_path], 0
    jne 2f
    # rhun's icon, in its color (grey without one)
    mov ecx, [rax + ICO_color]
    test ecx, ecx
    jns 1f
    mov ecx, T_ICON + 8
1:  mov eax, [rax + ICO_rhun]
    shl ecx, 8
    or eax, ecx
    ret
2:  mov ecx, [rax + ICO_color]
    test ecx, ecx
    jns 3f
    mov ecx, 0xff
3:  shl ecx, 16
    mov eax, edi
    or eax, ecx
    or eax, ITV_IMAGE
9:  ret

# ith_map(kind, name ptr, len, by suffix?) -> eax the icon index of the best mapping, or -1: the
#   key equal to the name ignoring case, or (by suffix) the longest key that ends the name after a dot
ith_map:
    PROLOGUE 16
    mov [rsp], edi
    mov r12, rsi
    mov r13, rdx
    mov [rsp + 4], ecx
    mov rbx, [rip + ith_cur]
    mov dword ptr [rsp + 8], -1     # the best icon
    mov dword ptr [rsp + 12], 0     # and its key's length
    xor r14d, r14d
1:  cmp r14, [rbx + ITH_maps + VEC_len]
    jae 9f
    imul r15, r14, MAP_SIZE
    add r15, [rbx + ITH_maps + VEC_ptr]
    inc r14
    mov eax, [rsp]
    cmp [r15 + MAP_kind], eax
    jne 1b
    cmp dword ptr [r15 + MAP_icon], 0
    jl 1b
    mov rdi, [r15 + MAP_key]
    call strlen
    cmp dword ptr [rsp + 4], 0
    jne 3f
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + MAP_key]
    mov rcx, rax
    call str_ieq
    test eax, eax
    jz 1b
    mov eax, [r15 + MAP_icon]
    mov [rsp + 8], eax
    jmp 9f
3:  # ".KEY" ends the name, KEY longer than the best one's
    cmp eax, [rsp + 12]
    jbe 1b
    lea rcx, [rax + 1]
    cmp rcx, r13
    ja 1b
    mov rdx, r13
    sub rdx, rcx                # the dot
    cmp byte ptr [r12 + rdx], '.'
    jne 1b
    push rax
    push rax
    lea rdi, [r12 + rdx + 1]
    mov rsi, rax
    mov rdx, [r15 + MAP_key]
    mov rcx, rax
    call str_ieq
    pop rcx
    pop rcx
    test eax, eax
    jz 1b
    mov [rsp + 12], ecx
    mov eax, [r15 + MAP_icon]
    mov [rsp + 8], eax
    jmp 1b
9:  mov eax, [rsp + 8]
    EPILOGUE

# FN iconth_file(name cstr) -> eax a file's icon value (see the header)
FN iconth_file
    PROLOGUE 16
    mov rbx, rdi
    call ith_resolve
    mov eax, ITV_RHUN
    cmp dword ptr [rip + ith_mode], ITM_RHUN
    je 9f
    mov eax, ITV_NONE
    cmp dword ptr [rip + ith_mode], ITM_NONE
    je 9f
    mov rdi, rbx
    call strlen
    mov r12, rax
    mov edi, MK_FILES
    mov rsi, rbx
    mov rdx, r12
    xor ecx, ecx
    call ith_map
    test eax, eax
    jns 5f
    mov edi, MK_EXTS
    mov rsi, rbx
    mov rdx, r12
    mov ecx, 1
    call ith_map
    test eax, eax
    jns 5f
    # the language rhun gives the name
    mov rdi, rbx
    mov rsi, r12
    call syntax_for_name
    test rax, rax
    jz 4f
    mov rsi, [rax + GR_name]
    test rsi, rsi
    jz 4f
    mov rdi, rsi
    mov [rsp], rsi
    call strlen
    mov edi, MK_LANGS
    mov rsi, [rsp]
    mov rdx, rax
    xor ecx, ecx
    call ith_map
    test eax, eax
    jns 5f
4:  mov rcx, [rip + ith_cur]
    mov eax, ITV_RHUN
    cmp dword ptr [rcx + ITH_fallback], 0
    jne 9f                      # fallback = rhun: rhun's icon
    mov eax, [rcx + ITH_file]
5:  mov edi, eax
    test eax, eax
    js 9f
    call ith_value
9:  EPILOGUE

# FN iconth_folder(name cstr, open) -> eax a folder's icon value (see the header)
FN iconth_folder
    PROLOGUE
    mov rbx, rdi
    mov r13d, esi
    call ith_resolve
    mov eax, ITV_RHUN
    cmp dword ptr [rip + ith_mode], ITM_RHUN
    je 9f
    mov eax, ITV_NONE
    cmp dword ptr [rip + ith_mode], ITM_NONE
    je 9f
    mov rdi, rbx
    call strlen
    mov r12, rax
    mov edi, MK_FOLDERS
    test r13d, r13d
    jz 1f
    mov edi, MK_FOLDERS_OPEN
1:  mov rsi, rbx
    mov rdx, r12
    xor ecx, ecx
    call ith_map
    test eax, eax
    jns 5f
    mov rcx, [rip + ith_cur]
    mov eax, [rcx + ITH_folder]
    test r13d, r13d
    jz 5f
    mov eax, [rcx + ITH_folder_open]
    test eax, eax
    jns 5f
    mov eax, [rcx + ITH_folder]
5:  mov edi, eax
    mov eax, ITV_RHUN
    test edi, edi
    js 9f
    call ith_value
9:  EPILOGUE

# FN iconth_draw(value, x, y, size) -> eax 1 when it drew an ITV_IMAGE icon of the theme in use, 0
#   when it cannot be shown (the caller draws rhun's icon instead)
FN iconth_draw
    PROLOGUE 16
    mov r12d, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov rbx, [rip + ith_cur]
    test rbx, rbx
    jz 9f
    movzx eax, r12w
    cmp rax, [rbx + ITH_icons + VEC_len]
    jae 9f
    imul r13, rax, ICO_SIZE
    add r13, [rbx + ITH_icons + VEC_ptr]
    lea r14, [r13 + ICO_pic]
    cmp dword ptr [r14 + PIC_state], 0
    jne 1f
    mov dword ptr [r14 + PIC_state], 2
    mov rdi, [rbx + ITH_dir]
    mov rsi, [r13 + ICO_path]
    mov edx, ITH_PNG_MAX
    mov ecx, ITH_PNG_DIM
    lea r8, [r14 + PIC_img]
    call png_icon_read
    test eax, eax
    jz 9f
    mov dword ptr [r14 + PIC_state], 1
1:  cmp dword ptr [r14 + PIC_state], 1
    jne 9f
    # a color: its alpha as a mask in that color
    mov eax, r12d
    shr eax, 16
    and eax, 0xff
    xor ecx, ecx
    mov edx, -1
    cmp eax, 0xff
    je 2f
    mov ecx, 1
    lea rdx, [rip + g_theme]
    mov edx, [rdx + rax*4]
2:  mov [r14 + PIC_mask], ecx
    mov rdi, r14
    mov esi, [rsp]
    mov ecx, [rsp + 8]
    mov r8d, edx
    mov edx, [rsp + 4]
    call icon_png_draw
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# ---------------------------------------------------------------- Select File Icon Theme

# FN iconth_list(add fn(label, len, detail, data)): rows: rhun, None, the themes ("TITLE" and
#   OWNER/NAME); -> eax the row of the setting's choice
FN iconth_list
    PROLOGUE
    mov r15, rdi
    lea rdi, [rip + .Lrow_rhun]
    mov esi, 4
    lea rdx, [rip + .Ld_builtin]
    xor ecx, ecx
    call r15
    lea rdi, [rip + .Lrow_none]
    mov esi, 4
    lea rdx, [rip + .Ld_noicons]
    mov ecx, 1
    call r15
    xor ebx, ebx
1:  cmp rbx, [rip + ith_list + VEC_len]
    jae 2f
    imul r12, rbx, ITH_SIZE
    add r12, [rip + ith_list + VEC_ptr]
    inc rbx
    mov rdi, [r12 + ITH_title]
    call strlen
    mov rdi, [r12 + ITH_title]
    mov rsi, rax
    mov rdx, [r12 + ITH_id]
    lea rcx, [rbx + 1]          # 2 + its index
    call r15
    jmp 1b
2:  # the setting's row
    mov qword ptr [rip + ith_seen], -1
    mov rax, [rip + ith_preview]
    mov qword ptr [rip + ith_preview], -1
    push rax
    push rax
    call ith_resolve
    pop rax
    pop rax
    mov [rip + ith_preview], rax
    xor eax, eax
    cmp dword ptr [rip + ith_mode], ITM_NONE
    jne 3f
    mov eax, 1
3:  cmp dword ptr [rip + ith_mode], ITM_THEME
    jne 9f
    mov rax, [rip + ith_cur]
    sub rax, [rip + ith_list + VEC_ptr]
    xor edx, edx
    mov ecx, ITH_SIZE
    div rcx
    add eax, 2
9:  EPILOGUE

# FN iconth_preview(row or -1): the icons of a row of the list while it is open; -1 the setting's
FN iconth_preview
    mov [rip + ith_preview], rdi
    mov qword ptr [rip + ith_seen], -1      # (the setting is read again after a preview)
    jmp ith_resolve

# FN iconth_choose(row): the row becomes the setting [ui] file_icons
FN iconth_choose
    PROLOGUE
    lea rsi, [rip + .Lv_rhun]
    cmp rdi, 1
    jb 2f
    lea rsi, [rip + .Lv_none]
    je 2f
    sub rdi, 2
    cmp rdi, [rip + ith_list + VEC_len]
    jae 9f
    imul rax, rdi, ITH_SIZE
    add rax, [rip + ith_list + VEC_ptr]
    mov rsi, [rax + ITH_id]
2:  lea rdi, [rip + ith_buf]
    mov rcx, rsi
    xor edx, edx
3:  mov al, [rcx + rdx]
    mov [rdi + rdx], al
    test al, al
    jz 4f
    inc edx
    cmp edx, 254
    jb 3b
    mov byte ptr [rdi + rdx], 0
4:  mov [rip + cfg_file_icons], rdi
    mov qword ptr [rip + ith_seen], -1
    mov dword ptr [rip + g_settings_changed], 1
    mov qword ptr [rip + ith_preview], -1
    call ith_resolve
9:  EPILOGUE

# FN cmd_select_file_icon_theme(): the list of icon themes, previewed as the selection moves
FN cmd_select_file_icon_theme
    jmp palette_icon_themes

# ---------------------------------------------------------------- print-icon

# FN iconth_dump(out sb, name cstr, kind 0 file, 1 folder, 2 open folder): "icon=rhun:NAME
#   color=COLOR", "icon=theme:ID:NAME" or "icon=none"
FN iconth_dump
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    mov r13d, edx
    test r13d, r13d
    jnz 1f
    mov rdi, rbx
    call iconth_file
    jmp 2f
1:  mov rdi, rbx
    lea esi, [r13 - 1]
    call iconth_folder
2:  mov r14d, eax
    mov rdi, r12
    lea rsi, [rip + .Lp_icon]
    call sb_push_cstr
    cmp r14d, ITV_NONE
    jne 3f
    mov rdi, r12
    lea rsi, [rip + .Lv_none]
    call sb_push_cstr
    jmp 8f
3:  cmp r14d, ITV_RHUN
    je 4f
    test r14d, ITV_IMAGE
    jz 4f
    mov rdi, r12
    lea rsi, [rip + .Lp_theme]
    call sb_push_cstr
    mov rax, [rip + ith_cur]
    mov rdi, r12
    mov rsi, [rax + ITH_id]
    call sb_push_cstr
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    movzx eax, r14w
    mov rcx, [rip + ith_cur]
    imul rax, rax, ICO_SIZE
    add rax, [rcx + ITH_icons + VEC_ptr]
    mov rdi, r12
    mov rsi, [rax + ICO_name]
    call sb_push_cstr
    jmp 8f
4:  # rhun's icon: ITV_RHUN asks file_icon (folders: rhun's folder)
    cmp r14d, ITV_RHUN
    jne 5f
    test r13d, r13d
    jnz 41f
    mov rdi, rbx
    call file_icon
    shl edx, 8
    or eax, edx
    mov r14d, eax
    jmp 5f
41: mov r14d, IC_FOLDER | (T_ACCENT << 8)
    mov rdi, r12
    lea rsi, [rip + .Lp_rhun_folder]
    call sb_push_cstr
    jmp 8f
5:  mov rdi, r12
    lea rsi, [rip + .Lp_rhun]
    call sb_push_cstr
    movzx edi, r14b
    call file_icon_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_color]
    call sb_push_cstr
    mov eax, r14d
    shr eax, 8
    and eax, 0xff
    mov edi, eax
    call file_color_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
8:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# FN iconth_page_rows(ext): the extension page's File icon themes rows (contribpage.s): each
#   theme's title; its setting value, its icons, whether it is the one chosen
FN iconth_page_rows
    PROLOGUE
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + ith_list + VEC_len]
    jae 9f
    imul r12, rbx, ITH_SIZE
    add r12, [rip + ith_list + VEC_ptr]
    inc rbx
    cmp [r12 + ITH_ext], r15
    jne 1b
    mov rdi, [r12 + ITH_title]
    test rdi, rdi
    jz 2f
    cmp byte ptr [rdi], 0
    jne 3f
2:  mov rdi, [r12 + ITH_name]
3:  call contrib_page_text
    mov rdi, [r12 + ITH_id]
    call contrib_page_detail
    call contrib_page_part
    mov rdi, [r12 + ITH_icons + VEC_len]
    call contrib_page_detail_int
    lea rdi, [rip + .Lpg_icons]
    cmp qword ptr [r12 + ITH_icons + VEC_len], 1
    jne 31f
    lea rdi, [rip + .Lpg_icon]
31: call contrib_page_detail
    mov rdi, [rip + cfg_file_icons]
    test rdi, rdi
    jz 4f
    mov rsi, [r12 + ITH_id]
    call strcmp_eq
    test eax, eax
    jz 4f
    call contrib_page_part
    lea rdi, [rip + .Lpg_in_use]
    call contrib_page_detail
4:  call contrib_page_end
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
map_secs: .quad .Ls_files, .Ls_exts, .Ls_langs, .Ls_folders, .Ls_folders_open, 0
.Ldir_icons: .asciz "icon-themes"
.Lsuffix: .asciz ".icons"
.Lk_title: .asciz "title"
.Lk_fallback: .asciz "fallback"
.Lv_rhun: .asciz "rhun"
.Lv_none: .asciz "none"
.Ls_icons: .asciz "icons"
.Ls_files: .asciz "files"
.Ls_exts: .asciz "extensions"
.Ls_langs: .asciz "languages"
.Ls_folders: .asciz "folders"
.Ls_folders_open: .asciz "folders_open"
.Ln_file: .asciz "file"
.Ln_folder: .asciz "folder"
.Ln_folder_open: .asciz "folder_open"
.Lrhun_colon: .asciz "rhun:"
.Lrow_rhun: .asciz "rhun"
.Lrow_none: .asciz "None"
.Ld_builtin: .asciz "built-in"
.Ld_noicons: .asciz "no file icons"
.Lp_icon: .asciz "icon="
.Lp_theme: .asciz "theme:"
.Lp_rhun: .asciz "rhun:"
.Lp_rhun_folder: .asciz "rhun:folder color=accent"
.Lp_color: .asciz " color="
.Lpg_icons: .asciz " icons"
.Lpg_icon: .asciz " icon"
.Lpg_in_use: .asciz "in use"
