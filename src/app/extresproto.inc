# The resources group's messages (docs/extensions/v1.1.md: idle, secrets, urls, uris, files,
# scoped-settings, workspace-folders), part of extproto.s: it uses the line's fields, the replies
# and `cur`. The group's features are agreed like the others but kept in the extension's EL row
# (EL_features, RF_* bits), beside EXT_features.
.text

# res_features(ext) -> eax the group's features named after "hello 1" that rhun knows
res_features:
    PROLOGUE 16
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 8f
    mov r15, rax
    mov dword ptr [r15 + EL_features], 0
    mov edi, 2
    call rest_from
    mov r12, rax
    mov r13, rdx
1:  test r13, r13
    jz 7f
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 7f
    mov r14, rax
    mov [rsp], rdx
    xor ebx, ebx
2:  lea rax, [rip + res_feature_names]
    mov rdx, [rax + rbx*8]
    test rdx, rdx
    jz 1b
    mov rdi, r14
    mov rsi, [rsp]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov ecx, ebx
    mov eax, 1
    shl eax, cl
    or [r15 + EL_features], eax
3:  inc ebx
    jmp 2b
7:  mov eax, [r15 + EL_features]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# res_features_out(ext): " NAME" for each of the group's agreed features, onto the features line
res_features_out:
    PROLOGUE
    call extres_row
    test rax, rax
    jz 9f
    mov r12d, [rax + EL_features]
    xor ebx, ebx
1:  lea rax, [rip + res_feature_names]
    mov r13, [rax + rbx*8]
    test r13, r13
    jz 9f
    mov eax, r12d
    mov ecx, ebx
    shr eax, cl
    test eax, 1
    jz 2f
    mov edi, ' '
    call out_byte
    mov rdi, r13
    call out_cstr
2:  inc ebx
    jmp 1b
9:  EPILOGUE

# res_agreed(bit) -> eax 1 when cur agreed the group's feature, else 0 after "error ID unknown"
res_agreed:
    PROLOGUE
    mov ebx, edi
    mov rdi, [rip + cur]
    call extres_row
    test rax, rax
    jz 8f
    test [rax + EL_features], ebx
    jz 8f
    mov eax, 1
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    xor eax, eax
    EPILOGUE

# FN extres_feat(ext, bit) -> eax 1 when the extension agreed the group's feature
FN extres_feat
    push rbx
    mov ebx, esi
    call extres_row
    test rax, rax
    jz 8f
    test [rax + EL_features], ebx
    jz 8f
    mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# extproto_prompt_owner() -> the extension whose prompt is open, or 0
FN extproto_prompt_owner
    xor eax, eax
    cmp qword ptr [rip + pr_id], 0
    je 1f
    mov rax, [rip + pr_ext]
1:  ret

# ---------------- idle ----------------

# ID busy yes|no -> ok ID: while yes, an idle = stop extension is never stopped for idleness
h_res_busy:
    PROLOGUE
    mov edi, RF_IDLE
    call res_agreed
    test eax, eax
    jz 9f
    mov edi, 2
    lea rsi, [rip + .Lo_yes]
    call field_is
    mov r12d, eax
    test eax, eax
    jnz 1f
    mov edi, 2
    lea rsi, [rip + .Lo_no]
    call field_is
    test eax, eax
    jz 8f
1:  cmp qword ptr [rip + nfields], 3
    jne 8f
    mov rdi, [rip + cur]
    mov esi, r12d
    call extres_busy
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

.section .rodata
.p2align 3
# the group's feature names; bit i of EL_features is entry i (RF_*)
res_feature_names:
    .quad .Lres_f_idle, .Lres_f_secrets, .Lres_f_urls, .Lres_f_uris, .Lres_f_files
    .quad .Lres_f_scoped, .Lres_f_folders, 0
.Lres_f_idle: .asciz "idle"
.Lres_f_secrets: .asciz "secrets"
.Lres_f_urls: .asciz "urls"
.Lres_f_uris: .asciz "uris"
.Lres_f_files: .asciz "files"
.Lres_f_scoped: .asciz "scoped-settings"
.Lres_f_folders: .asciz "workspace-folders"
.Lres_v_busy: .asciz "busy"
.text
