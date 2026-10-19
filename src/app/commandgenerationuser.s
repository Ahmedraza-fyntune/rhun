.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/keycombo.inc"
.include "app/commandgeneration.inc"
.equ CGB_COMBO, 24
.equ CGB_USER_BEGIN, 26
.equ CGB_BUILTIN, 27
.equ CGB_BUILTIN_EQUAL, 28
.equ CGB_DELIMITERS, 29
.equ CGB_USER_HASH_INIT, 30
.equ CGB_USER_HASH_DATA, 31
.equ CGB_USER_HASH_FINAL, 32
.equ CGB_USER_MAP, 33
.equ CGB_USER_EQUAL, 34
.equ CGB_ALIAS, 35
.text
FN cg_user_one
    PROLOGUE 16
    mov rbx, rdi
    mov rax, [rbx + CG_phase]
    cmp rax, CGB_USER_BEGIN
    je .Lcgu_begin
    cmp rax, CGB_BUILTIN
    je .Lcgu_builtin
    cmp rax, CGB_BUILTIN_EQUAL
    je .Lcgu_builtin_equal
    cmp rax, CGB_DELIMITERS
    je .Lcgu_delimiters
    cmp rax, CGB_ALIAS
    je .Lcgu_alias
    cmp rax, CGB_USER_HASH_INIT
    je .Lcgu_hash_init
    cmp rax, CGB_USER_HASH_DATA
    je .Lcgu_hash_data
    cmp rax, CGB_USER_HASH_FINAL
    je .Lcgu_hash_final
    cmp rax, CGB_USER_MAP
    je .Lcgu_map
    cmp rax, CGB_USER_EQUAL
    je .Lcgu_equal
    mov rax, -22
    EPILOGUE
.Lcgu_begin:
    mov r12, [rbx + CG_userindex]
    cmp r12, [rbx + CG_nkeys]
    jae .Lcgu_complete
    shl r12, 5
    lea r12, [rbx + r12 + CG_keylines]
    mov rax, [r12 + 16]
    mov [rbx + CG_wordsource], rax
    mov rax, [r12 + 24]
    mov [rbx + CG_wordlength], rax
    lea rdi, [rbx + CG_kc]
    mov rsi, [r12]
    mov rdx, [r12 + 8]
    call keys_combo_begin
    test rax, rax
    js .Lcgu_return
    mov qword ptr [rbx + CG_phase], CGB_COMBO
    jmp .Lcgu_continue
.Lcgu_builtin:
    mov r12, [rbx + CG_resolvercursor]
    shl r12, 5
    lea rax, [rip + g_commands]
    add r12, rax
    cmp qword ptr [r12 + CMD_name], 0
    je .Lcgu_builtin_done
    cmp qword ptr [rbx + CG_resolvercursor], 1024
    jae .Lcgu_resource
    mov [rbx + CG_currentcmd], r12
    mov qword ptr [rbx + CG_compareoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_BUILTIN_EQUAL
    jmp .Lcgu_continue
.Lcgu_builtin_equal:
    mov r12, [rbx + CG_currentcmd]
    mov r12, [r12 + CMD_name]
    mov r13, [rbx + CG_wordsource]
    mov r14, [rbx + CG_compareoffset]
    xor r15d, r15d
1:  cmp r15, 4096
    jae 3f
    movzx eax, byte ptr [r12 + r14]
    inc r15
    cmp r14, [rbx + CG_wordlength]
    je 2f
    test eax, eax
    jz .Lcgu_builtin_next
    cmp al, [r13 + r14]
    jne .Lcgu_builtin_next
    inc r14
    jmp 1b
2:  test eax, eax
    jnz .Lcgu_builtin_next
    mov rax, [rbx + CG_currentcmd]
    jmp .Lcgu_selected
3:  mov [rbx + CG_compareoffset], r14
    jmp .Lcgu_continue
.Lcgu_builtin_next:
    inc qword ptr [rbx + CG_resolvercursor]
    mov qword ptr [rbx + CG_phase], CGB_BUILTIN
    jmp .Lcgu_continue
.Lcgu_builtin_done:
    mov qword ptr [rbx + CG_slash], -1
    mov qword ptr [rbx + CG_dot], -1
    mov qword ptr [rbx + CG_scanoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_DELIMITERS
    jmp .Lcgu_continue
.Lcgu_delimiters:
    mov r12, [rbx + CG_wordsource]
    mov r13, [rbx + CG_scanoffset]
    xor r14d, r14d
1:  cmp r13, [rbx + CG_wordlength]
    jae .Lcgu_delimiters_end
    cmp r14, 4096
    jae 4f
    movzx eax, byte ptr [r12 + r13]
    inc r14
    cmp al, '/'
    je .Lcgu_qualified
    cmp al, '.'
    jne 3f
    cmp qword ptr [rbx + CG_dot], -1
    jne 3f
    mov [rbx + CG_dot], r13
3:  inc r13
    jmp 1b
4:  mov [rbx + CG_scanoffset], r13
    jmp .Lcgu_continue
.Lcgu_qualified:
    test r13, r13
    jz .Lcgu_missing
    cmp r13, 100
    ja .Lcgu_missing
    mov [rbx + CG_slash], r13
    lea rax, [r12 + r13 + 1]
    mov [rbx + CG_source], rax
    mov rax, [rbx + CG_wordlength]
    sub rax, r13
    dec rax
    mov [rbx + CG_sourcelen], rax
    mov qword ptr [rbx + CG_hashkind], 1
    mov qword ptr [rbx + CG_phase], CGB_USER_HASH_INIT
    jmp .Lcgu_continue
.Lcgu_delimiters_end:
    mov rax, [rbx + CG_dot]
    test rax, rax
    jle .Lcgu_missing
    cmp rax, 100
    ja .Lcgu_missing
    mov qword ptr [rbx + CG_resolvercursor], 0
    mov qword ptr [rbx + CG_resolved], 0
    mov qword ptr [rbx + CG_phase], CGB_ALIAS
    jmp .Lcgu_continue
.Lcgu_alias:
    mov r12, [rbx + CG_resolvercursor]
    cmp r12, [rbx + CG_nslots]
    jae .Lcgu_alias_done
    inc qword ptr [rbx + CG_resolvercursor]
    imul r13, r12, CS_SIZE
    lea r13, [rbx + r13 + CG_slots]
    mov rdx, [rbx + CG_dot]
    cmp [r13 + CS_namelen], rdx
    jne .Lcgu_continue
    mov rdi, [rbx + CG_wordsource]
    mov rsi, [r13 + CS_name]
    call memeq
    test eax, eax
    jz .Lcgu_continue
    cmp qword ptr [rbx + CG_resolved], 0
    jne .Lcgu_missing
    inc r12
    mov [rbx + CG_resolved], r12
    jmp .Lcgu_continue
.Lcgu_alias_done:
    cmp qword ptr [rbx + CG_resolved], 0
    je .Lcgu_missing
    mov rax, [rbx + CG_wordsource]
    mov [rbx + CG_source], rax
    mov rax, [rbx + CG_wordlength]
    mov [rbx + CG_sourcelen], rax
    mov qword ptr [rbx + CG_hashkind], 0
    mov qword ptr [rbx + CG_phase], CGB_USER_HASH_INIT
    jmp .Lcgu_continue
.Lcgu_hash_init:
    lea rdi, [rbx + CG_sha]
    call sha256_init
    mov byte ptr [rsp], 'O'
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    mov byte ptr [rsp], 'Q'
1:  lea rdi, [rbx + CG_sha]
    mov rsi, rsp
    mov edx, 1
    call sha256_update
    test eax, eax
    jz .Lcgu_invalid
    cmp qword ptr [rbx + CG_hashkind], 0
    jne 2f
    mov rax, [rbx + CG_resolved]
    dec rax
    imul rax, rax, CS_SIZE
    lea rsi, [rbx + rax + CG_slots + CS_ordinal]
    mov edx, 8
    lea rdi, [rbx + CG_sha]
    call sha256_update
    test eax, eax
    jz .Lcgu_invalid
    jmp 3f
2:  lea rdi, [rbx + CG_sha]
    mov rsi, [rbx + CG_wordsource]
    mov rdx, [rbx + CG_slash]
    call sha256_update
    test eax, eax
    jz .Lcgu_invalid
    mov byte ptr [rsp], 0
    lea rdi, [rbx + CG_sha]
    mov rsi, rsp
    mov edx, 1
    call sha256_update
    test eax, eax
    jz .Lcgu_invalid
3:  mov qword ptr [rbx + CG_hashoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_USER_HASH_DATA
    jmp .Lcgu_continue
.Lcgu_hash_data:
    mov r12, [rbx + CG_hashoffset]
    mov r13, [rbx + CG_sourcelen]
    sub r13, r12
    mov edx, 4096
    cmp r13, rdx
    cmovb rdx, r13
    mov r13, rdx
    mov rsi, [rbx + CG_source]
    add rsi, r12
    lea rdi, [rbx + CG_sha]
    call sha256_update
    test eax, eax
    jz .Lcgu_invalid
    add r12, r13
    mov [rbx + CG_hashoffset], r12
    cmp r12, [rbx + CG_sourcelen]
    jb .Lcgu_continue
    mov qword ptr [rbx + CG_phase], CGB_USER_HASH_FINAL
    jmp .Lcgu_continue
.Lcgu_hash_final:
    lea rdi, [rbx + CG_sha]
    lea rsi, [rbx + CG_digest]
    call sha256_final
    test eax, eax
    jz .Lcgu_invalid
    mov rax, [rbx + CG_digest]
    mov rdx, [rbx + CG_routecap]
    dec rdx
    and rax, rdx
    mov [rbx + CG_probe], rax
    mov qword ptr [rbx + CG_hashoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_USER_MAP
    jmp .Lcgu_continue
.Lcgu_map:
    mov r12, [rbx + CG_owned]
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    mov r12, [rbx + CG_qualified]
1:  imul r13, [rbx + CG_probe], 24
    add r12, r13
    mov r13, [r12 + 8]
    test r13, r13
    jz .Lcgu_missing
    mov rax, [rbx + CG_digest]
    cmp [r12], rax
    jne .Lcgu_map_next
    dec r13
    mov [rbx + CG_comparerow], r13
    shl r13, 6
    mov r14, r13
    add r13, [rbx + CG_metadata]
    add r14, [rbx + CG_authority + VEC_ptr]
    mov rax, [rbx + CG_sourcelen]
    cmp [r13 + CM_wirelen], rax
    jne .Lcgu_map_next
    cmp qword ptr [rbx + CG_hashkind], 0
    jne .Lcgu_map_owner
    mov rax, [rbx + CG_resolved]
    dec rax
    cmp [r13 + CM_slot], rax
    jne .Lcgu_map_next
    jmp .Lcgu_map_compare
.Lcgu_map_owner:
    mov rdx, [rbx + CG_slash]
    imul rax, [r13 + CM_slot], CS_SIZE
    cmp [rbx + rax + CG_slots + CS_ownerlen], rdx
    jne .Lcgu_map_next
    mov rdi, [rbx + CG_wordsource]
    mov rsi, [r14 + 24]
    call memeq
    test eax, eax
    jz .Lcgu_map_next
.Lcgu_map_compare:
    mov qword ptr [rbx + CG_compareoffset], 0
    mov qword ptr [rbx + CG_phase], CGB_USER_EQUAL
    jmp .Lcgu_continue
.Lcgu_equal:
    mov r12, [rbx + CG_compareoffset]
    mov r13, [rbx + CG_sourcelen]
    sub r13, r12
    mov edx, 2048
    cmp r13, rdx
    cmovb rdx, r13
    mov r13, rdx
    mov rdi, [rbx + CG_source]
    add rdi, r12
    mov rsi, [rbx + CG_comparerow]
    shl rsi, 5
    add rsi, [rbx + CG_commands + VEC_ptr]
    mov rsi, [rsi + CMD_name]
    add rsi, r12
    call memeq
    test eax, eax
    jz .Lcgu_map_next
    add r12, r13
    mov [rbx + CG_compareoffset], r12
    cmp r12, [rbx + CG_sourcelen]
    jb .Lcgu_continue
    cmp qword ptr [rbx + CG_hashkind], 0
    je 1f
    imul r12, [rbx + CG_probe], 24
    add r12, [rbx + CG_qualified]
    cmp qword ptr [r12 + 16], 1
    jne .Lcgu_missing
1:  mov rax, [rbx + CG_comparerow]
    shl rax, 5
    add rax, [rbx + CG_commands + VEC_ptr]
    jmp .Lcgu_selected
.Lcgu_map_next:
    inc qword ptr [rbx + CG_hashoffset]
    mov rax, [rbx + CG_hashoffset]
    cmp rax, [rbx + CG_routecap]
    jae .Lcgu_resource
    mov rax, [rbx + CG_routecap]
    dec rax
    inc qword ptr [rbx + CG_probe]
    and [rbx + CG_probe], rax
    mov qword ptr [rbx + CG_phase], CGB_USER_MAP
    jmp .Lcgu_continue
.Lcgu_missing:
    call keys_none_command
.Lcgu_selected:
    mov [rbx + CG_bindingcmd], rax
    mov rdi, rbx
    call cg_binding_begin
    EPILOGUE
.Lcgu_complete:
    mov qword ptr [rbx + CG_phase], CG_READY
.Lcgu_continue:
    xor eax, eax
.Lcgu_return:
    EPILOGUE
.Lcgu_invalid:
    mov rax, -22
    EPILOGUE
.Lcgu_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
