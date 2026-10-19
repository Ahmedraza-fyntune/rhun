# Runtime command suppliers remain owned while a prepared command view borrows their strings.
.include "rhun.inc"
.include "app/extruntime.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
ro_last_incarnation: .quad 0
.text
# Count a readable C string within limit, including the byte at limit.
ro_length:
    test rdi, rdi
    jz 8f
    xor eax, eax
1:  cmp rax, rsi
    ja 8f
    cmp byte ptr [rdi + rax], 0
    je 9f
    inc rax
    jmp 1b
8:  mov rax, -1
9:  ret

# ext_runtime_new(config64)->owned RO/NULL, RDX0/-errno. One allocation, no borrowed data.
FN ext_runtime_new
    PROLOGUE 48
    mov rbx, rdi
    test rbx, rbx
    jz .Lro_invalid
    cmp qword ptr [rbx + ROC_target], 0
    je .Lro_invalid
    mov rax, [rbx + ROC_session]
    test rax, rax
    jle .Lro_invalid
    mov rax, 0x7fffffffffffffff
    cmp [rip + ro_last_incarnation], rax
    jae .Lro_overflow
    mov rdi, [rbx + ROC_owner]
    mov esi, RO_LIMIT
    call ro_length
    test rax, rax
    jle .Lro_invalid
    mov [rsp], rax
    mov rdi, [rbx + ROC_name]
    mov esi, RO_LIMIT
    call ro_length
    test rax, rax
    jle .Lro_invalid
    mov [rsp + 8], rax
    mov rdi, [rbx + ROC_key]
    mov esi, 40
    call ro_length
    test rax, rax
    jle .Lro_invalid
    mov [rsp + 16], rax
    mov r12, rax
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp al, '_'
    je 2f
    sub al, '0'
    cmp al, 9
    jbe 2f
    sub al, 'a' - '0'
    cmp al, 25
    ja .Lro_invalid
2:  cmp rcx, r12
    jb 1b
    mov rdi, [rbx + ROC_title]
    mov esi, RO_LIMIT
    call ro_length
    test rax, rax
    js .Lro_invalid
    mov [rsp + 24], rax
    mov r12, [rbx + ROC_keyslen]
    cmp r12, RO_LIMIT
    ja .Lro_invalid
    mov [rsp + 32], r12
    test r12, r12
    jz 4f
    mov rdi, [rbx + ROC_keys]
    test rdi, rdi
    jz .Lro_invalid
    xor ecx, ecx
3:  cmp byte ptr [rdi + rcx], 0
    je .Lro_invalid
    inc rcx
    cmp rcx, r12
    jb 3b
4:  mov rdi, RO_SIZE + 7
    add rdi, [rsp]
    jc .Lro_invalid
    mov rax, [rsp + 8]
    add rax, [rsp + 16]
    jc .Lro_invalid
    add rax, rax
    jc .Lro_invalid
    add rdi, rax
    jc .Lro_invalid
    add rdi, [rsp + 24]
    jc .Lro_invalid
    add rdi, r12
    jc .Lro_invalid
    mov [rsp + 40], rdi
    mov edi, 5
    lea rsi, [rip + ext_runtime_retire_one]
    xor edx, edx
    call ext_prepare_retire_register_kind
    test rax, rax
    js .Lro_register_failed
    mov rdi, [rsp + 40]
    mov esi, 5
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jz .Lro_failed
    mov r13, rax
    mov qword ptr [rax + RO_refs], 1
    mov rcx, [rbx + ROC_target]
    mov [rax + RO_target], rcx
    mov rcx, [rbx + ROC_session]
    mov [rax + RO_session], rcx
    inc qword ptr [rip + ro_last_incarnation]
    mov rcx, [rip + ro_last_incarnation]
    mov [rax + RO_incarnation], rcx
    mov qword ptr [rax + RO_live], 1
    mov rcx, [rsp]
    mov [rax + RO_ownerlen], rcx
    mov rcx, [rsp + 8]
    mov [rax + RO_namelen], rcx
    mov rcx, [rsp + 16]
    mov [rax + RO_keylen], rcx
    mov rcx, [rsp + 24]
    mov [rax + RO_titlelen], rcx
    mov [rax + RO_keyslen], r12
    mov rcx, [rsp + 40]
    mov [rax + RO_allocsize], rcx
    mov qword ptr [rax + 88], 0
    lea r14, [rax + RO_SIZE]
    xor r15d, r15d
5:  mov rsi, [rbx + r15*8 + ROC_owner]
    mov rdx, [rsp + r15*8]
    mov rdi, r14
    test rdx, rdx
    jz 6f
    call memcpy
6:  add r14, [rsp + r15*8]
    mov byte ptr [r14], 0
    inc r14
    inc r15
    cmp r15, 5
    jb 5b
    # Keep the flattened wire spelling independently owned, without aliasing identity fields.
    mov rdi, r14
    mov rsi, [rbx + ROC_name]
    mov rdx, [rsp + 8]
    call memcpy
    add r14, [rsp + 8]
    mov byte ptr [r14], '.'
    inc r14
    mov rdi, r14
    mov rsi, [rbx + ROC_key]
    mov rdx, [rsp + 16]
    inc rdx
    call memcpy
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lro_invalid:
    mov rdx, -22
    jmp .Lro_failed
.Lro_overflow:
    mov rdx, -75
    jmp .Lro_failed
.Lro_register_failed:
    mov rdx, rax
.Lro_failed:
    xor eax, eax
    EPILOGUE

FN ext_runtime_retain
    test rdi, rdi
    jz .Lro_ref_invalid
    cmp qword ptr [rdi + RO_refs], 0
    je .Lro_ref_invalid
    cmp qword ptr [rdi + RO_refs], -1
    je .Lro_ref_overflow
    inc qword ptr [rdi + RO_refs]
    xor eax, eax
    ret
.Lro_ref_invalid:
    mov rax, -22
    ret
.Lro_ref_overflow:
    mov rax, -75
    ret

# Last drop transfers to the charged scheduler. Failed transfer preserves the caller reference.
FN ext_runtime_release_deferred
FN ext_runtime_release
    mov edx, 1
    test rdi, rdi
    jz .Lro_release_ok
    cmp qword ptr [rdi + RO_refs], 0
    je .Lro_release_invalid
    cmp qword ptr [rdi + RO_refs], 1
    je .Lro_release_last
    dec qword ptr [rdi + RO_refs]
.Lro_release_ok:
    xor eax, eax
    ret
.Lro_release_invalid:
    xor edx, edx
    mov rax, -22
    ret
.Lro_release_last:
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + RO_refs], 0
    lea rdi, [rbx - RD_SIZE]
    call ext_prepare_retire_enqueue_custom
    test rax, rax
    js .Lro_release_restore
    mov edx, 1
    xor eax, eax
    EPILOGUE
.Lro_release_restore:
    mov qword ptr [rbx + RO_refs], 1
    xor edx, edx
    EPILOGUE

# One checked free per scheduler unit. Success leaves no readable record.
FN ext_runtime_retire_one
    jmp ext_prepare_retire_free_custom

FN ext_runtime_revoke
    mov qword ptr [rdi + RO_live], 0
    ret
FN ext_runtime_incarnation
    mov rax, [rdi + RO_incarnation]
    ret

# Borrow a field under a retained RO, including revoked records for diagnostics.
FN ext_runtime_get
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp rsi, 5
    ja 9f
    lea rax, [rdi + RO_SIZE]
    xor ecx, ecx
1:  cmp rcx, rsi
    je 9f
    add rax, [rdi + rcx*8 + RO_ownerlen]
    inc rax
    inc rcx
    jmp 1b
9:  ret

# RO,field,cstr,limit -> exact equality. Does not grant authority by itself.
ro_equal:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    mov rsi, rcx
    call ro_length
    cmp rax, [rbx + r12*8 + RO_ownerlen]
    jne 8f
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call ext_runtime_get
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call memeq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# RO,targetEXT,session,owner,name,key ->1/0. Exact process session and identity, never aliases.
FN ext_runtime_matches
    PROLOGUE
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    test rbx, rbx
    jz .Lro_no
    cmp qword ptr [rbx + RO_live], 1
    jne .Lro_no
    cmp [rbx + RO_target], rsi
    jne .Lro_no
    test rdx, rdx
    jle .Lro_no
    cmp [rbx + RO_session], rdx
    jne .Lro_no
    xor esi, esi
    mov rdx, r12
    mov ecx, RO_LIMIT
    call ro_equal
    test eax, eax
    jz .Lro_no
    mov rdi, rbx
    mov esi, 1
    mov rdx, r13
    mov ecx, RO_LIMIT
    call ro_equal
    test eax, eax
    jz .Lro_no
    mov rdi, rbx
    mov esi, 2
    mov rdx, r14
    mov ecx, 40
    call ro_equal
    EPILOGUE
.Lro_no:
    xor eax, eax
    EPILOGUE
