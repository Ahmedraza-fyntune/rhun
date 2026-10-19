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

# ---------------- secrets ----------------

# ID secret-get KEY -> ok ID 1 LEN + value, or ok ID 0 0 when nothing is stored
h_res_secret_get:
    mov edi, SO_GET
    jmp res_secret
# ID secret-set KEY LEN + value -> ok ID
h_res_secret_set:
    mov edi, SO_SET
    jmp res_secret
# ID secret-delete KEY -> ok ID (also when nothing was stored)
h_res_secret_delete:
    mov edi, SO_DELETE
    jmp res_secret
# ID secret-keys -> ok ID LEN + the keys, each followed by LF
h_res_secret_keys:
    mov edi, SO_KEYS

# res_secret(op): checks, then the request joins the queue (secrets.s answers it)
res_secret:
    PROLOGUE 80
    mov r12d, edi
    mov edi, RF_SECRETS
    call res_agreed
    test eax, eax
    jz 9f
    mov rbx, [rip + cur]
    test dword ptr [rbx + EXT_needs], NEEDS_SECRETS
    jnz 1f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lres_e_needs_secrets]
    call reply_error
    jmp 9f
1:  mov eax, 3
    cmp r12d, SO_SET
    jne 11f
    mov eax, 4
11: cmp r12d, SO_KEYS
    jne 12f
    mov eax, 2
12: cmp [rip + nfields], rax
    jne 8f
    xor r13d, r13d
    cmp r12d, SO_KEYS
    je 3f
    # KEY: [a-z0-9_.-], 1 to 64 bytes
    lea r8, [rip + fields]
    mov rsi, [r8 + 32]
    mov rdx, [r8 + 40]
    test rdx, rdx
    jz 8f
    cmp rdx, SECRET_KEY_MAX
    ja 8f
    xor ecx, ecx
2:  movzx eax, byte ptr [rsi + rcx]
    mov [rsp + rcx], al
    lea edi, [rax - 'a']
    cmp edi, 25
    jbe 21f
    lea edi, [rax - '0']
    cmp edi, 9
    jbe 21f
    cmp eax, '_'
    je 21f
    cmp eax, '.'
    je 21f
    cmp eax, '-'
    jne 8f
21: inc rcx
    cmp rcx, rdx
    jb 2b
    mov byte ptr [rsp + rcx], 0
    lea r13, [rsp]
    cmp r12d, SO_SET
    jne 3f
    cmp qword ptr [rip + body_len], SECRET_VALUE_MAX
    jbe 3f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lres_e_value_big]
    call reply_error
    jmp 9f
3:  mov rdi, rbx
    mov rsi, [rip + cur_id]
    mov edx, r12d
    mov rcx, r13
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    call secrets_queue
    test rax, rax
    jns 9f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lres_e_secret_busy]
    call reply_error
    jmp 9f
8:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# FN extproto_secret_reply(sr): the store's answer to a secret request (secrets.s)
FN extproto_secret_reply
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + cur]
    mov rax, [rbx + SR_ext]
    mov [rip + cur], rax
    mov eax, [rbx + SR_status]
    lea rsi, [rip + .Lres_e_refused]
    cmp eax, SS_REFUSED
    je 7f
    lea rsi, [rip + .Lres_e_nostore]
    cmp eax, SS_NOSTORE
    je 7f
    lea rsi, [rip + .Lres_e_keys_big]
    cmp eax, SS_TOOBIG
    je 7f
    mov eax, [rbx + SR_op]
    cmp eax, SO_GET
    je 1f
    cmp eax, SO_KEYS
    je 2f
    mov rdi, [rbx + SR_id]
    call reply_ok
    jmp 9f
1:  call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rbx + SR_id]
    call out_u64
    cmp dword ptr [rbx + SR_status], SS_NONE
    jne 11f
    lea rdi, [rip + .Lres_none]
    call out_cstr
    call out_end
    jmp 9f
11: lea rdi, [rip + .Lres_one]
    call out_cstr
    jmp 3f
2:  call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rbx + SR_id]
    call out_u64
    mov edi, ' '
    call out_byte
3:  mov rdi, [rbx + SR_outlen]
    call out_u64
    mov edi, 10
    call out_byte
    lea rdi, [rbx + SR_buf]
    mov rsi, [rbx + SR_outlen]
    call out_bytes
    call out_end
    jmp 9f
7:  mov rdi, [rbx + SR_id]
    call reply_error
9:  mov [rip + cur], r12
    EPILOGUE

.section .rodata
.Lres_v_secret_get: .asciz "secret-get"
.Lres_v_secret_set: .asciz "secret-set"
.Lres_v_secret_delete: .asciz "secret-delete"
.Lres_v_secret_keys: .asciz "secret-keys"
.Lres_e_needs_secrets: .asciz "needs secrets=yes"
.Lres_e_value_big: .asciz "toobig a value is at most 8192 bytes"
.Lres_e_keys_big: .asciz "toobig 64 keys"
.Lres_e_secret_busy: .asciz "busy 8 secret requests are waiting"
.Lres_e_refused: .asciz "refused the keychain is locked, or access was cancelled or denied"
.Lres_e_nostore: .asciz "refused no keychain is available"
.Lres_none: .asciz " 0 0\n"
.Lres_one: .asciz " 1 "
.text

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
