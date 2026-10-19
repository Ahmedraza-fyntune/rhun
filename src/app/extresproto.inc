# The resources group's messages (docs/extensions/v1.1.md: idle, secrets, urls, uris, files,
# scoped-settings, workspace-folders), part of extproto.s: it uses the line's fields, the replies
# and `cur`.
.text

# res_agreed(feature) -> eax 1 when cur agreed the feature (FEAT_*), else 0 after "error ID unknown"
res_agreed:
    PROLOGUE
    mov esi, edi
    mov rdi, [rip + cur]
    call ext_feature
    test eax, eax
    jnz 9f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    xor eax, eax
9:  EPILOGUE

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
    mov edi, FEAT_IDLE
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
    mov edi, FEAT_SECRETS
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

# ---------------- uris and virtual documents (vdoc.s) ----------------

# FN extproto_host_line(ext, line ptr, len) -> rax the id of "ID LINE" sent to the extension, or 0:
# a request about no document (content)
FN extproto_host_line
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    cmp qword ptr [rbx + EXT_hreq], 2147483647
    jae 8f
    mov r12, [rip + cur]
    mov [rip + cur], rbx
    inc qword ptr [rbx + EXT_hreq]
    mov r15, [rbx + EXT_hreq]
    call out_begin
    mov rdi, r15
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r13
    mov rsi, r14
    call out_bytes
    mov edi, 10
    call out_byte
    call out_end
    mov [rip + cur], r12
    test rax, rax
    js 8f
    mov rdi, r13
    mov rsi, r14
    call next_word
    mov rcx, rdx
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r15
    call extres_req_sent
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extproto_content_closed(ext, uri cstr): "0 content-closed URI"
FN extproto_content_closed
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    mov r12, [rip + cur]
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lres_ev_closed]
    call out_cstr
    mov rdi, r13
    call out_cstr
    mov edi, 10
    call out_byte
    call out_end
    mov [rip + cur], r12
    EPILOGUE

# ID content-changed URI -> ok ID: an open virtual document of the extension is asked again
h_res_content_changed:
    PROLOGUE
    mov edi, FEAT_URIS
    call res_agreed
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 8f
    mov edi, 2
    call rest_from
    mov rbx, rax
    mov r12, rdx
    mov rdi, rax
    mov rsi, rdx
    call uri_scheme_len
    test rax, rax
    jz 8f
    mov rdi, [rip + cur]
    mov rsi, rbx
    mov rdx, r12
    call vdoc_changed
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# res_open_uri(ptr, len, line, col) -> rax -1 when open's resource was a URI and the request is
# answered; else rax, rdx the resource to open as a path (a file: URI decoded, or as it came)
res_open_uri:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, [rip + cur]
    mov esi, FEAT_URIS
    call ext_feature
    test eax, eax
    jz 7f
    mov rdi, rbx
    mov rsi, r12
    call uri_scheme_len
    test rax, rax
    jz 7f
    mov rdi, rbx
    mov rsi, r12
    call uri_file_path
    test rax, rax
    jz 1f
    EPILOGUE
1:  cmp r12, 5
    jb 2f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lres_file_colon]
    mov ecx, 5
    call str_starts
    test eax, eax
    jnz 6f                      # a file: URI that is no local path
2:  mov rdi, [rip + cur]
    mov rsi, rbx
    mov rdx, r12
    mov ecx, r13d
    mov r8d, r14d
    call vdoc_open
    test rax, rax
    js 5f
    mov rsi, [rax + DOC_id]
    mov rdi, [rip + cur_id]
    call reply_ok_u64
    mov rax, -1
    EPILOGUE
5:  lea rsi, [rip + .Le_nofile]
    cmp rax, -27
    jne 51f
    lea rsi, [rip + .Lres_e_vdocs]
51: mov rdi, [rip + cur_id]
    call reply_error
    mov rax, -1
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nofile]
    call reply_error
    mov rax, -1
    EPILOGUE
7:  mov rax, rbx
    mov rdx, r12
    EPILOGUE

# FN extproto_uri_segment(doc) -> rax the cstr subscriptions match a virtual document by (its URI's
# last segment), or 0 for an ordinary document
FN extproto_uri_segment
    mov rax, [rdi + DOC_uri]
    test rax, rax
    jz 9f
    mov rdi, rax
    jmp uri_last_segment
9:  ret

.section .rodata
.Lres_v_content_changed: .asciz "content-changed"
.Lres_ev_closed: .asciz "0 content-closed "
.Lres_file_colon: .asciz "file:"
.Lres_e_vdocs: .asciz "toobig too many virtual documents are open"
.text

.section .rodata
.Lres_v_busy: .asciz "busy"
.text
