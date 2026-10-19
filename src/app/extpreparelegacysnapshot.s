# Helper-only initial source/asset snapshot. Pure importer consumes only this owned transcript.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extpreparelegacy.inc"
.text
# Accepted immutable data span for a manifest/asset SR. External selected source has no data.
FN prep_legacy_source_bytes
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [r12 + SR_roles], SR_MANIFEST
    jne 1f
    mov rax, [rbx + EP_manifest]
    mov rdx, [rbx + EP_manifestlen]
    EPILOGUE
1:  cmp qword ptr [r12 + SR_roles], SR_LAUNCH | SR_EXTERNAL
    je .Leplsb_external
    xor r13d, r13d
2:  cmp r13, [rbx + EP_plan + VEC_len]
    jae .Leplsb_bad
    imul r14, r13, AP_SIZE
    add r14, [rbx + EP_plan + VEC_ptr]
    mov rdx, [r14 + AP_len]
    cmp rdx, [r12 + SR_len]
    jne 3f
    mov rdi, [r14 + AP_path]
    mov rsi, [r12 + SR_path]
    call memeq
    test eax, eax
    jnz 4f
3:  inc r13
    jmp 2b
4:  mov rax, [r14 + AP_bytes]
    mov rdx, [r14 + AP_byteslen]
    test rax, rax
    jz .Leplsb_bad
    EPILOGUE
.Leplsb_external:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Leplsb_bad:
    xor eax, eax
    mov rdx, -EV_BAD_PREPARE
    EPILOGUE

# rootBorrowed,DIR,owner,name,tag64,out{ownedPtr,len}->primary/secondary. Output untouched on failure.
FN ext_legacy_snapshot_build
    PROLOGUE 160
    mov [rsp], rdi
    mov [rsp + 8], r8
    mov [rsp + 16], r9
    mov qword ptr [rsp + 24], 0
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    xor r8d, r8d
    call prep_legacy_validate_ep
    test rax, rax
    jz .Lepls_initial_error
    mov rbx, rax
    mov rdi, [rsp]
    lea rsi, [rsp + 80]
    call ext_root_identity
    test rax, rax
    js .Lepls_fail
    mov rsi, [rsp + 8]
    add rsi, 32
    lea rdi, [rsp + 80]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lepls_changed
    mov rdi, [rbx + EP_ext + EXT_prog]
    call strlen
    mov [rsp + 48], rax
    mov r12, rax
    mov rdi, [rbx + EP_ext + EXT_script]
    xor eax, eax
    test rdi, rdi
    jz 1f
    call strlen
1:  mov [rsp + 56], rax
    lea r12, [r12 + rax + LS_HEADER]
    xor r13d, r13d
.Lepls_size:
    cmp r13, [rbx + EP_sources + VEC_len]
    jae .Lepls_alloc
    imul r14, r13, SR_SIZE
    add r14, [rbx + EP_sources + VEC_ptr]
    add r12, LR_SIZE
    jc .Lepls_resource
    add r12, [r14 + SR_len]
    jc .Lepls_resource
    cmp qword ptr [r14 + SR_roles], SR_LAUNCH | SR_EXTERNAL
    je 2f
    add r12, [r14 + SR_size]
    jc .Lepls_resource
2:  cmp r12, LS_CAP
    ja .Lepls_resource
    inc r13
    jmp .Lepls_size
.Lepls_alloc:
    mov rdi, r12
    call mem_alloc_try
    test rax, rax
    jz .Lepls_oom
    mov [rsp + 24], rax
    mov [rsp + 32], r12
    mov rdi, rax
    xor esi, esi
    mov rdx, r12
    call memset
    mov r15, [rsp + 24]
    mov rax, 0x00003153534c4852 # RHLSS1 plus two NUL
    mov [r15], rax
    mov dword ptr [r15 + 8], 1
    mov dword ptr [r15 + 12], LS_HEADER
    mov [r15 + LS_total], r12
    mov eax, [rbx + EP_sources + VEC_len]
    mov [r15 + LS_count], eax
    mov rdi, r15
    add rdi, LS_tag
    mov rsi, [rsp + 8]
    mov edx, 64
    call memcpy
    lea rdi, [r15 + LS_source]
    lea rsi, [rbx + EP_legacy_source]
    mov edx, 32
    call memcpy
    mov eax, [rsp + 48]
    mov [r15 + LS_programlen], eax
    mov eax, [rsp + 56]
    mov [r15 + LS_scriptlen], eax
    mov eax, [rbx + EP_legacy_drive]
    mov [r15 + LS_drive], eax
    add r15, LS_HEADER
    mov rdi, r15
    mov rsi, [rbx + EP_ext + EXT_prog]
    mov rdx, [rsp + 48]
    call memcpy
    add r15, [rsp + 48]
    mov rdx, [rsp + 56]
    test rdx, rdx
    jz 3f
    mov rdi, r15
    mov rsi, [rbx + EP_ext + EXT_script]
    call memcpy
    add r15, [rsp + 56]
3:  xor r13d, r13d
.Lepls_record:
    cmp r13, [rbx + EP_sources + VEC_len]
    jae .Lepls_complete
    imul r14, r13, SR_SIZE
    add r14, [rbx + EP_sources + VEC_ptr]
    mov eax, [r14 + SR_len]
    mov [r15 + LR_pathlen], eax
    mov eax, [r14 + SR_roles]
    mov [r15 + LR_roles], eax
    mov rax, [r14 + SR_size]
    mov [r15 + LR_size], rax
    mov eax, [r14 + SR_exec]
    mov [r15 + LR_exec], eax
    lea rdi, [r15 + LR_hash]
    lea rsi, [r14 + SR_hash]
    mov edx, 32
    call memcpy
    mov rdi, rbx
    mov rsi, r14
    call prep_legacy_source_bytes
    test rdx, rdx
    js .Lepls_fail_dx
    mov [rsp + 64], rax
    mov [rsp + 72], rdx
    mov [r15 + LR_datalen], rdx
    add r15, LR_SIZE
    mov rdi, r15
    mov rsi, [r14 + SR_path]
    mov rdx, [r14 + SR_len]
    call memcpy
    add r15, [r14 + SR_len]
    cmp qword ptr [r14 + SR_roles], SR_LAUNCH | SR_EXTERNAL
    je 4f
    mov rdi, r15
    mov rsi, [rsp + 64]
    mov rdx, [rsp + 72]
    cmp rdx, [r14 + SR_size]
    jne .Lepls_changed
    call memcpy
    mov rdi, r15
    mov rsi, [rsp + 72]
    lea rdx, [rsp + 112]
    call prep_hash_bytes
    lea rdi, [rsp + 112]
    lea rsi, [r14 + SR_hash]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lepls_changed
    add r15, [rsp + 72]
4:  inc r13
    jmp .Lepls_record
.Lepls_complete:
    sub r15, [rsp + 24]
    cmp r15, [rsp + 32]
    jne .Lepls_changed
    xor r12d, r12d
    jmp .Lepls_release
.Lepls_fail_dx:
    mov rax, rdx
.Lepls_fail:
    mov r12, rax
.Lepls_release:
    mov rdi, rbx
    call ext_prepare_release
    mov rdx, rax
    test r12, r12
    jnz .Lepls_discard
    test rax, rax
    jnz .Lepls_discard
    mov rdi, [rsp + 16]
    mov rax, [rsp + 24]
    mov [rdi], rax
    mov rax, [rsp + 32]
    mov [rdi + 8], rax
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lepls_discard:
    mov [rsp + 40], rdx
    mov rdi, [rsp + 24]
    call mem_free
    mov rdx, [rsp + 40]
    mov rax, r12
    test rax, rax
    jnz 5f
    mov rax, rdx
5:  EPILOGUE
.Lepls_changed:
    mov rax, -EV_CHANGED
    jmp .Lepls_fail
.Lepls_resource:
    mov rax, -EV_RESOURCE
    jmp .Lepls_fail
.Lepls_oom:
    mov rax, -12
    jmp .Lepls_fail
.Lepls_initial_error:
    mov rax, rdx
    mov rdx, rcx
    EPILOGUE
