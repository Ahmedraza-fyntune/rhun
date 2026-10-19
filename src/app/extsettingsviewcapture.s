# Schema and identity captures use retained EP plus numeric cursors only.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.text
FN esv_capture_step
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + EV_phase]
    cmp rax, EVP_ID_OWNER
    je .Lcap_owner
    cmp rax, EVP_ID_NAME
    je .Lcap_name
    cmp rax, EVP_ID_ALLOC
    je .Lcap_id_alloc
    cmp rax, EVP_ID_COPY
    je .Lcap_id_copy
    cmp rax, EVP_PREVIOUS
    je .Lcap_previous
    cmp rax, EVP_KEY_SCAN
    je .Lcap_key_scan
    cmp rax, EVP_KEY_ALLOC
    je .Lcap_key_alloc
    cmp rax, EVP_KEY_COPY
    je .Lcap_key_copy
    cmp rax, EVP_KEY_INSERT
    je .Lcap_key_insert
    cmp rax, EVP_KEY_COMPARE
    je .Lcap_key_compare
    cmp rax, EVP_BASE_SCAN
    je .Lcap_base_scan
    cmp rax, EVP_BASE_ALLOC
    je .Lcap_base_alloc
    cmp rax, EVP_BASE_COPY
    je .Lcap_base_copy
    jmp .Lcap_bad
.Lcap_owner:
    mov rax, [rbx + EV_ep]
    mov r12, [rax + EP_ext + EXT_owner]
    jmp .Lcap_id_scan
.Lcap_name:
    mov rax, [rbx + EV_ep]
    mov r12, [rax + EP_ext + EXT_name]
.Lcap_id_scan:
    test r12, r12
    jz .Lcap_bad
1:  cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    mov rcx, [rbx + EV_scanpos]
    cmp rcx, EC_LIMIT
    jae .Lcap_large
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    test eax, eax
    jz 2f
    inc qword ptr [rbx + EV_scanpos]
    jmp 1b
2:  test rcx, rcx
    jz .Lcap_bad
    cmp qword ptr [rbx + EV_phase], EVP_ID_OWNER
    jne 3f
    mov [rbx + EV_ownerlen], rcx
    mov qword ptr [rbx + EV_phase], EVP_ID_NAME
    jmp 4f
3:  mov [rbx + EV_namelen], rcx
    mov qword ptr [rbx + EV_phase], EVP_ID_ALLOC
4:  mov qword ptr [rbx + EV_scanpos], 0
    jmp .Lcap_return
.Lcap_id_alloc:
    cmp qword ptr [rbx + EV_allocsleft], 0
    je .Lcap_return
    mov rdi, [rbx + EV_ownerlen]
    add rdi, [rbx + EV_namelen]
    jc .Lcap_large
    inc rdi
    cmp rdi, EC_LIMIT
    ja .Lcap_large
    mov [rbx + EV_seclen], rdi
    inc rdi
    dec qword ptr [rbx + EV_allocsleft]
    call ext_settings_memory_try
    test rax, rax
    jz .Lcap_alloc_error
    mov [rbx + EV_section], rax
    mov qword ptr [rbx + EV_copypos], 0
    mov qword ptr [rbx + EV_phase], EVP_ID_COPY
    jmp .Lcap_return
.Lcap_id_copy:
    mov rax, [rbx + EV_ep]
    mov r12, [rax + EP_ext + EXT_owner]
    mov r13, [rax + EP_ext + EXT_name]
    mov r14, [rbx + EV_section]
1:  mov rcx, [rbx + EV_copypos]
    cmp rcx, [rbx + EV_seclen]
    jae 4f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    cmp rcx, [rbx + EV_ownerlen]
    jb 2f
    je 3f
    mov rax, rcx
    sub rax, [rbx + EV_ownerlen]
    dec rax
    movzx eax, byte ptr [r13 + rax]
    jmp 5f
2:  movzx eax, byte ptr [r12 + rcx]
    jmp 5f
3:  mov eax, '/'
5:  mov [r14 + rcx], al
    dec qword ptr [rbx + EV_bytesleft]
    inc qword ptr [rbx + EV_copypos]
    jmp 1b
4:  mov qword ptr [rbx + EV_index], 0
    mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_phase], EVP_PREVIOUS
    jmp .Lcap_return
.Lcap_previous:
    mov rax, [rbx + EV_oldmodel]
    test rax, rax
    jz .Lcap_keys_begin
    mov rcx, [rbx + EV_index]
    cmp rcx, 128
    jae .Lcap_previous_done
    mov r12, [rax + ELM_slots + rcx * 8]
    test r12, r12
    jz .Lcap_previous_next
    mov rax, [r12 + EV_seclen]
    cmp [rbx + EV_seclen], rax
    jne .Lcap_previous_next
    mov r13, [rbx + EV_section]
    mov r14, [r12 + EV_section]
1:  mov rcx, [rbx + EV_matchpos]
    cmp rcx, [rbx + EV_seclen]
    jae 2f
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    movzx eax, byte ptr [r13 + rcx]
    cmp al, [r14 + rcx]
    jne .Lcap_previous_mismatch
    dec qword ptr [rbx + EV_bytesleft]
    inc qword ptr [rbx + EV_matchpos]
    jmp 1b
2:  mov rdi, r12
    call ext_settings_view_retain
    test rax, rax
    js .Lcap_done
    mov [rbx + EV_previous], r12
.Lcap_previous_done:
    mov rdi, [rbx + EV_oldmodel]
    call ext_settings_model_release
    test rax, rax
    js .Lcap_done
    mov qword ptr [rbx + EV_oldmodel], 0
.Lcap_keys_begin:
    mov qword ptr [rbx + EV_index], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_hash], 5381
    mov qword ptr [rbx + EV_phase], EVP_KEY_SCAN
    jmp .Lcap_return
.Lcap_previous_mismatch:
    dec qword ptr [rbx + EV_bytesleft]
.Lcap_previous_next:
    inc qword ptr [rbx + EV_index]
    mov qword ptr [rbx + EV_matchpos], 0
    jmp .Lcap_return
.Lcap_key_scan:
    mov rax, [rbx + EV_index]
    cmp rax, [rbx + EV_count]
    jb 1f
    mov qword ptr [rbx + EV_phase], EVP_RAW_NEXT
    jmp .Lcap_return
1:  imul rax, SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    mov r12, [rax + SD_key]
    test r12, r12
    jz .Lcap_bad
2:  cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    mov rcx, [rbx + EV_scanpos]
    cmp rcx, EXT_LINE_MAX - 12
    ja .Lcap_large
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    test eax, eax
    jz 3f
    cmp eax, 32
    jbe .Lcap_bad
    cmp eax, 127
    je .Lcap_bad
    mov rdx, [rbx + EV_hash]
    mov r8, rdx
    shl rdx, 5
    add rdx, r8
    xor rdx, rax
    mov [rbx + EV_hash], rdx
    inc qword ptr [rbx + EV_scanpos]
    jmp 2b
3:  test rcx, rcx
    jz .Lcap_bad
    mov [rbx + EV_worklen], rcx
    mov qword ptr [rbx + EV_phase], EVP_KEY_ALLOC
    jmp .Lcap_return
.Lcap_key_alloc:
    mov r12d, EVP_KEY_COPY
    jmp .Lcap_alloc
.Lcap_base_alloc:
    mov r12d, EVP_BASE_COPY
.Lcap_alloc:
    cmp qword ptr [rbx + EV_allocsleft], 0
    je .Lcap_return
    mov rdi, [rbx + EV_worklen]
    inc rdi
    dec qword ptr [rbx + EV_allocsleft]
    call ext_settings_memory_try
    test rax, rax
    jz .Lcap_alloc_error
    mov [rbx + EV_work], rax
    mov qword ptr [rbx + EV_copypos], 0
    mov [rbx + EV_phase], r12
    jmp .Lcap_return
.Lcap_key_copy:
    mov r12d, SD_key
    jmp .Lcap_copy
.Lcap_base_copy:
    mov r12d, SD_value
.Lcap_copy:
    mov r13, [rbx + EV_index]
    imul rax, r13, SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    mov rsi, [rax + r12]
    mov rdx, [rbx + EV_worklen]
    sub rdx, [rbx + EV_copypos]
    jz .Lcap_copy_done
    mov rax, [rbx + EV_bytesleft]
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .Lcap_return
    mov r14, rdx
    add rsi, [rbx + EV_copypos]
    mov rdi, [rbx + EV_work]
    add rdi, [rbx + EV_copypos]
    call memcpy
    add [rbx + EV_copypos], r14
    sub [rbx + EV_bytesleft], r14
    mov rax, [rbx + EV_copypos]
    cmp rax, [rbx + EV_worklen]
    jne .Lcap_return
.Lcap_copy_done:
    imul r13, EVR_SIZE
    add r13, rbx
    add r13, EV_rows
    mov rax, [rbx + EV_work]
    mov rcx, [rbx + EV_worklen]
    mov qword ptr [rbx + EV_work], 0
    cmp r12, SD_key
    jne 1f
    mov [r13 + EVR_key], rax
    mov [r13 + EVR_keylen], rcx
    mov rax, [rbx + EV_hash]
    mov [r13 + EVR_hash], rax
    and eax, ESV_BUCKETS - 1
    mov [rbx + EV_probe], rax
    mov qword ptr [rbx + EV_phase], EVP_KEY_INSERT
    jmp .Lcap_return
1:  mov [r13 + EVR_base], rax
    mov [r13 + EVR_value], rax
    mov [r13 + EVR_baselen], rcx
    mov [r13 + EVR_vallen], rcx
    mov qword ptr [r13 + EVR_flags], EVR_ALIAS_BASE
    inc qword ptr [rbx + EV_index]
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_hash], 5381
    mov qword ptr [rbx + EV_phase], EVP_KEY_SCAN
    jmp .Lcap_return
.Lcap_key_insert:
    mov rcx, [rbx + EV_probe]
    mov rax, [rbx + EV_buckets + rcx * 8]
    test rax, rax
    jz 1f
    dec rax
    mov [rbx + EV_rowindex], rax
    mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_phase], EVP_KEY_COMPARE
    jmp .Lcap_return
1:  mov rax, [rbx + EV_index]
    inc rax
    mov [rbx + EV_buckets + rcx * 8], rax
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_phase], EVP_BASE_SCAN
    jmp .Lcap_return
.Lcap_key_compare:
    imul r12, [rbx + EV_index], EVR_SIZE
    lea r12, [rbx + r12 + EV_rows]
    imul r13, [rbx + EV_rowindex], EVR_SIZE
    lea r13, [rbx + r13 + EV_rows]
    mov rax, [r12 + EVR_hash]
    cmp [r13 + EVR_hash], rax
    jne .Lcap_probe_next
    mov rax, [r12 + EVR_keylen]
    cmp [r13 + EVR_keylen], rax
    jne .Lcap_probe_next
    mov r14, [r12 + EVR_key]
    mov r15, [r13 + EVR_key]
1:  mov rcx, [rbx + EV_matchpos]
    cmp rcx, [r12 + EVR_keylen]
    jae .Lcap_bad
    cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    movzx eax, byte ptr [r14 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    cmp al, [r15 + rcx]
    jne .Lcap_probe_next
    inc qword ptr [rbx + EV_matchpos]
    jmp 1b
.Lcap_probe_next:
    inc qword ptr [rbx + EV_probe]
    and qword ptr [rbx + EV_probe], ESV_BUCKETS - 1
    mov qword ptr [rbx + EV_phase], EVP_KEY_INSERT
    jmp .Lcap_return
.Lcap_base_scan:
    imul rax, [rbx + EV_index], SD_SIZE
    mov rcx, [rbx + EV_ep]
    add rax, [rcx + EP_ext + EXT_sdefs + VEC_ptr]
    mov r12, [rax + SD_value]
    test r12, r12
    jz .Lcap_base_empty
1:  cmp qword ptr [rbx + EV_bytesleft], 0
    je .Lcap_return
    mov rcx, [rbx + EV_scanpos]
    cmp rcx, EXT_LINE_MAX
    jae .Lcap_large
    movzx eax, byte ptr [r12 + rcx]
    dec qword ptr [rbx + EV_bytesleft]
    test eax, eax
    jz 2f
    cmp eax, 10
    je .Lcap_bad
    cmp eax, 13
    je .Lcap_bad
    inc qword ptr [rbx + EV_scanpos]
    jmp 1b
.Lcap_base_empty:
    xor ecx, ecx
2:  mov rax, [rbx + EV_index]
    imul rax, EVR_SIZE
    add rcx, [rbx + rax + EV_rows + EVR_keylen]
    jc .Lcap_large
    add rcx, 12
    jc .Lcap_large
    cmp rcx, EXT_LINE_MAX
    ja .Lcap_large
    mov rax, [rbx + EV_scanpos]
    mov [rbx + EV_worklen], rax
    mov qword ptr [rbx + EV_phase], EVP_BASE_ALLOC
.Lcap_return:
    xor eax, eax
.Lcap_done:
    EPILOGUE
.Lcap_alloc_error:
    mov rax, rdx
    EPILOGUE
.Lcap_bad:
    mov rax, -22
    EPILOGUE
.Lcap_large:
    mov rax, -27
    EPILOGUE
