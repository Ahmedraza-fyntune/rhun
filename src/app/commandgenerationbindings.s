.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/keycombo.inc"
.include "app/commandgeneration.inc"
.equ CGB_DEFAULT_BEGIN, 21
.equ CGB_DEFAULT_LENGTH, 22
.equ CGB_WORD, 23
.equ CGB_COMBO, 24
.equ CGB_BIND, 25
.equ CGB_USER_BEGIN, 26
.text
# Deterministic full packed-key hash. Exact64 equality, never hash-only routing.
FN cg_binding_hash
    mov rax, rdi
    mov rcx, rax
    shr rcx, 33
    xor rax, rcx
    mov rcx, 0xff51afd7ed558ccd
    imul rax, rcx
    mov rcx, rax
    shr rcx, 33
    xor rax, rcx
    mov rcx, 0xc4ceb9fe1a85ec53
    imul rax, rcx
    mov rcx, rax
    shr rcx, 33
    xor rax, rcx
    and eax, CG_BINDING_MAP_CAP - 1
    ret
# CG -> choose final target CMD or static none, then enter bounded binding probe.
FN cg_binding_begin
    PROLOGUE
    mov rbx, rdi
    mov eax, [rbx + CG_kc + KC_key]
    test eax, eax
    jz .Lcgbi_next
    mov edx, [rbx + CG_kc + KC_mods]
    cmp qword ptr [rbx + CG_wordmode], 1
    jne 1f
    test edx, edx
    jz .Lcgbi_next
1:  shl rax, 32
    or rax, rdx
    mov [rbx + CG_packed], rax
    mov rdi, rax
    call cg_binding_hash
    mov [rbx + CG_bindingindex], rax
    mov qword ptr [rbx + CG_probe], 0
    mov qword ptr [rbx + CG_phase], CGB_BIND
    xor eax, eax
    EPILOGUE
.Lcgbi_next:
    mov rdi, rbx
    call cg_binding_next
    xor eax, eax
    EPILOGUE
FN cg_binding_next
    cmp qword ptr [rdi + CG_wordmode], 2
    je 1f
    mov qword ptr [rdi + CG_phase], CGB_WORD
    ret
1:  inc qword ptr [rdi + CG_userindex]
    mov qword ptr [rdi + CG_phase], CGB_USER_BEGIN
    ret

FN cg_bindings_one
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + CG_phase]
    cmp rax, CGB_DEFAULT_BEGIN
    je .Lcgbd_begin
    cmp rax, CGB_DEFAULT_LENGTH
    je .Lcgbd_length
    cmp rax, CGB_WORD
    je .Lcgbd_word
    cmp rax, CGB_COMBO
    je .Lcgbd_combo
    cmp rax, CGB_BIND
    je .Lcgbd_bind
    mov rdi, rbx
    call cg_user_one
    EPILOGUE
.Lcgbd_begin:
    mov r12, [rbx + CG_row]
    cmp qword ptr [rbx + CG_wordmode], 0
    jne .Lcgbd_extension
    shl r12, 5
    lea rax, [rip + g_commands]
    add r12, rax
    cmp qword ptr [r12 + CMD_name], 0
    je .Lcgbd_begin_extensions
    cmp qword ptr [rbx + CG_row], 1024
    jae .Lcgbd_resource
    mov [rbx + CG_currentcmd], r12
    mov rax, [r12 + CMD_keys]
    test rax, rax
    jz .Lcgbd_invalid
    mov [rbx + CG_wordsource], rax
    mov qword ptr [rbx + CG_scanoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_DEFAULT_LENGTH
    jmp .Lcgbd_continue
.Lcgbd_begin_extensions:
    mov qword ptr [rbx + CG_wordmode], 1
    mov qword ptr [rbx + CG_row], 0
    jmp .Lcgbd_continue
.Lcgbd_extension:
    cmp r12, [rbx + CG_ncommands]
    jae .Lcgbd_begin_users
    mov rdi, rbx
    call cg_row_addresses
    mov [rbx + CG_currentcmd], rax
    mov rax, [rax + CMD_keys]
    mov [rbx + CG_wordsource], rax
    mov rax, [rdx + CM_keyslen]
    mov [rbx + CG_wordlength], rax
    jmp .Lcgbd_words_begin
.Lcgbd_begin_users:
    mov qword ptr [rbx + CG_wordmode], 2
    mov qword ptr [rbx + CG_userindex], 0
    mov qword ptr [rbx + CG_phase], CGB_USER_BEGIN
    jmp .Lcgbd_continue
.Lcgbd_length:
    mov r12, [rbx + CG_wordsource]
    mov r13, [rbx + CG_scanoffset]
    xor r14d, r14d
1:  cmp r13, CG_STRING_CAP
    ja .Lcgbd_resource
    cmp byte ptr [r12 + r13], 0
    je 2f
    inc r13
    inc r14
    cmp r14, 4096
    jb 1b
    mov [rbx + CG_scanoffset], r13
    jmp .Lcgbd_continue
2:  mov [rbx + CG_wordlength], r13
.Lcgbd_words_begin:
    mov rax, [rbx + CG_wordlength]
    add rax, [rbx + CG_defaultbytes]
    cmp rax, 16 * 1024 * 1024
    ja .Lcgbd_resource
    mov [rbx + CG_defaultbytes], rax
    mov qword ptr [rbx + CG_wordcursor], 0
    mov qword ptr [rbx + CG_wordstart], -1
    mov qword ptr [rbx + CG_phase], CGB_WORD
    jmp .Lcgbd_continue
.Lcgbd_word:
    mov r12, [rbx + CG_wordsource]
    mov r13, [rbx + CG_wordcursor]
    mov r14, [rbx + CG_wordstart]
    xor r15d, r15d
.Lcgbd_word_loop:
    cmp r13, [rbx + CG_wordlength]
    jae .Lcgbd_word_end
    cmp r15, 4096
    jae .Lcgbd_word_pending
    movzx eax, byte ptr [r12 + r13]
    inc r15
    cmp al, ' '
    je .Lcgbd_word_space
    cmp al, 9
    je .Lcgbd_word_space
    cmp r14, -1
    jne 1f
    mov r14, r13
1:  inc r13
    mov rax, r13
    sub rax, r14
    cmp rax, KC_CAP
    ja .Lcgbd_resource
    jmp .Lcgbd_word_loop
.Lcgbd_word_space:
    cmp r14, -1
    jne .Lcgbd_word_ready
    inc r13
    jmp .Lcgbd_word_loop
.Lcgbd_word_end:
    cmp r14, -1
    jne .Lcgbd_word_ready
    inc qword ptr [rbx + CG_row]
    mov qword ptr [rbx + CG_phase], CGB_DEFAULT_BEGIN
    jmp .Lcgbd_continue
.Lcgbd_word_pending:
    mov [rbx + CG_wordcursor], r13
    mov [rbx + CG_wordstart], r14
    jmp .Lcgbd_continue
.Lcgbd_word_ready:
    cmp qword ptr [rbx + CG_wordtokens], 262144
    jae .Lcgbd_resource
    inc qword ptr [rbx + CG_wordtokens]
    mov [rbx + CG_wordcursor], r13
    mov qword ptr [rbx + CG_wordstart], -1
    lea rdi, [rbx + CG_kc]
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call keys_combo_begin
    test rax, rax
    js .Lcgbd_return
    mov qword ptr [rbx + CG_phase], CGB_COMBO
    jmp .Lcgbd_continue
.Lcgbd_combo:
    lea rdi, [rbx + CG_kc]
    mov esi, 4096
    mov edx, 1
    call keys_combo_step
    test rax, rax
    js .Lcgbd_return
    jnz .Lcgbd_continue
    cmp qword ptr [rbx + CG_wordmode], 2
    je .Lcgbd_user_resolve
    mov rax, [rbx + CG_currentcmd]
    mov [rbx + CG_bindingcmd], rax
    mov rdi, rbx
    call cg_binding_begin
    EPILOGUE
.Lcgbd_user_resolve:
    mov qword ptr [rbx + CG_resolvercursor], 0
    mov qword ptr [rbx + CG_compareoffset], 0
    mov qword ptr [rbx + CG_phase], 27
    jmp .Lcgbd_continue
.Lcgbd_bind:
    mov r12, [rbx + CG_bindingindex]
    shl r12, 4
    add r12, [rbx + CG_bindingmap]
    mov r13, [rbx + CG_packed]
    cmp qword ptr [r12 + 8], 0
    je .Lcgbd_bind_insert
    cmp [r12], r13
    jne .Lcgbd_bind_advance
    cmp qword ptr [rbx + CG_wordmode], 1
    je .Lcgbd_bind_next
    mov rax, [r12 + 8]
    dec rax
    shl rax, 4
    add rax, [rbx + CG_bindings + VEC_ptr]
    mov rdx, [rbx + CG_bindingcmd]
    mov [rax + KB_cmd], rdx
    jmp .Lcgbd_bind_next
.Lcgbd_bind_insert:
    mov rax, [rbx + CG_bindings + VEC_len]
    cmp rax, CG_BINDING_CAP
    jae .Lcgbd_resource
    mov [r12], r13
    lea rdx, [rax + 1]
    mov [r12 + 8], rdx
    mov [rbx + CG_bindings + VEC_len], rdx
    shl rax, 4
    add rax, [rbx + CG_bindings + VEC_ptr]
    mov [rax], r13
    mov rdx, [rbx + CG_bindingcmd]
    mov [rax + KB_cmd], rdx
.Lcgbd_bind_next:
    mov rsi, [r12 + 8]
    dec rsi
    mov rdi, rbx
    call cg_defaults_note
    test rax, rax
    js .Lcgbd_return
    mov rdi, rbx
    call cg_binding_next
    jmp .Lcgbd_continue
.Lcgbd_bind_advance:
    inc qword ptr [rbx + CG_probe]
    cmp qword ptr [rbx + CG_probe], CG_BINDING_MAP_CAP
    jae .Lcgbd_resource
    inc qword ptr [rbx + CG_bindingindex]
    and qword ptr [rbx + CG_bindingindex], CG_BINDING_MAP_CAP - 1
.Lcgbd_continue:
    xor eax, eax
.Lcgbd_return:
    EPILOGUE
.Lcgbd_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lcgbd_invalid:
    mov rax, -22
    EPILOGUE
