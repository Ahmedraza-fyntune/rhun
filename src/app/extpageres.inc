# The resources group's parts of an extension's details page, part of extpage.s: its passwords
# and tokens (the keys, never the values, each with Forget) and where they are kept.
.equ ID_XR_FORGET, 0x7d40       # + i: Forget for the i-th key; ID_XP + 7: Forget all
.equ ID_XR_LINKS, 0x7d3f        # the open-links-without-asking switch
.text

# draw_res_links(ext): "Opens links without asking" with a switch, once the user chose Always
# for its open-url prompt
draw_res_links:
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    test dword ptr [rax + EL_flags], ELF_OPEN_URLS
    jz 9f
    M eax, MI_8
    add [rip + xp_y], eax
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lxr_open_urls]
    COLOR edx, T_FG
    mov ecx, MI_28
    mov r8d, [rip + xp_x]
    call text_at_keep
    mov edi, ID_XR_LINKS
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, [rip + g_mt + 4*MI_20]
    sub esi, [rip + g_mt + 4*MI_14]
    mov edx, [rip + xp_y]
    add edx, [rip + g_mt + 4*MI_4]
    mov ecx, 1
    call ui_toggle
    test eax, eax
    jz 1f
    mov rdi, rbx
    call extres_open_urls_revoke
1:  M eax, MI_28
    add [rip + xp_y], eax
9:  EPILOGUE

# draw_res_secrets(ext): "Passwords and tokens" for an extension with [needs] secrets = yes
draw_res_secrets:
    PROLOGUE 16
    mov rbx, rdi
    test dword ptr [rbx + EXT_needs], NEEDS_SECRETS
    jz 9f
    lea rsi, [rip + .Lxr_secrets]
    call section
    mov rdi, rbx
    call extres_row
    test rax, rax
    jz 9f
    mov r12, rax
    mov r13, [r12 + EL_skeys]
    test r13, r13
    jnz 2f
    # not read yet: the store is asked once
    test dword ptr [r12 + EL_flags], ELF_SKEYS_ASKED
    jnz 1f
    mov rdi, rbx
    call secrets_keys_refresh
1:  lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Lxr_looking]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    jmp 7f
2:  cmp byte ptr [r13], 0
    jne 3f
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Lxr_none]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
    jmp 7f
3:  xor r14d, r14d              # the key's index
4:  cmp byte ptr [r13], 0
    je 6f
    # the key, up to its LF, into xp_buf
    xor ecx, ecx
41: movzx eax, byte ptr [r13 + rcx]
    test eax, eax
    jz 42f
    cmp eax, 10
    je 42f
    cmp ecx, 200
    jae 42f
    lea rdx, [rip + xp_buf]
    mov [rdx + rcx], al
    inc ecx
    jmp 41b
42: lea rdx, [rip + xp_buf]
    mov byte ptr [rdx + rcx], 0
    lea r13, [r13 + rcx]
    cmp byte ptr [r13], 10
    jne 43f
    inc r13
43: lea rdi, [rip + g_face_ui]
    lea rsi, [rip + xp_buf]
    COLOR edx, T_FG
    mov ecx, MI_32
    mov r8d, [rip + xp_x]
    call text_at_keep
    lea rdi, [rip + .Lxr_forget]
    call label_width
    mov esi, [rip + xp_x]
    add esi, [rip + xp_w]
    sub esi, eax
    lea edi, [r14 + ID_XR_FORGET]
    mov edx, [rip + xp_y]
    lea rcx, [rip + .Lxr_forget]
    xor r8d, r8d
    call button
    test eax, UB_CLICK
    jz 5f
    mov rdi, rbx
    lea rsi, [rip + xp_buf]
    call secrets_forget         # the list may be gone after this: the next frame draws it again
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
5:  M eax, MI_40
    add [rip + xp_y], eax
    inc r14d
    cmp r14d, SECRET_KEYS_MAX
    jb 4b
6:  mov eax, [rip + xp_x]
    mov [rip + xp_bx], eax
    mov edi, ID_XP + 7
    lea rsi, [rip + .Lxr_forget_all]
    mov edx, 2
    call row_button
    test eax, UB_CLICK
    jz 61f
    mov rdi, rbx
    xor esi, esi
    call secrets_forget
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
61: M eax, MI_40
    add [rip + xp_y], eax
7:  call secrets_where
    mov rsi, rax
    lea rdi, [rip + g_face_small]
    COLOR edx, T_MUTED
    mov ecx, MI_24
    call line_text
9:  EPILOGUE

.section .rodata
.Lxr_secrets: .asciz "Passwords and tokens"
.Lxr_looking: .asciz "Looking in the keychain\xe2\x80\xa6"
.Lxr_none: .asciz "None stored."
.Lxr_forget: .asciz "Forget"
.Lxr_forget_all: .asciz "Forget all"
.Lxr_open_urls: .asciz "Opens links in your browser without asking"
.text
