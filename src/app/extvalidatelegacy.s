# Isolated helper-only source proof. No managed tree ID is produced by this module.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Recheck every exact accepted source, then complete current flat asset membership.
# root borrowed, EP ready and owned by caller. Returns primary,secondary cleanup.
FN prep_legacy_verify_sources
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 104], 0
    xor r13d, r13d
.Leplvs_source:
    cmp r13, [r12 + EP_sources + VEC_len]
    jae .Leplvs_plan
    imul r14, r13, SR_SIZE
    add r14, [r12 + EP_sources + VEC_ptr]
    test qword ptr [r14 + SR_roles], SR_EXTERNAL
    jz 1f
    mov rdi, [r14 + SR_path]
    mov esi, ER_FILE
    call prep_legacy_open_absolute
    jmp 2f
1:  mov rdi, rbx
    mov rsi, [r14 + SR_path]
    mov rdx, [r14 + SR_len]
    call prep_legacy_open_relative
2:  test rax, rax
    js .Leplvs_open_error
    mov r15, rax
    mov rdi, rax
    mov rsi, rsp
    xor edx, edx
    call prep_hash_file
    mov [rsp + 96], rax
    test rax, rax
    jnz 3f
    mov rdi, rsp
    lea rsi, [r14 + SR_size]
    mov edx, 48
    call memeq
    test eax, eax
    jnz 3f
    mov qword ptr [rsp + 96], -EV_CHANGED
3:  mov rdi, r15
    call ext_root_close
    mov [rsp + 104], rax
    cmp qword ptr [rsp + 96], 0
    jne .Leplvs_return
    test rax, rax
    js .Leplvs_return
    inc r13
    jmp .Leplvs_source
.Leplvs_plan:
    mov rdi, rbx
    mov rsi, [r12 + EP_ext + EXT_dir]
    mov rdx, [r12 + EP_ext + EXT_owner]
    mov rcx, [r12 + EP_ext + EXT_name]
    call ext_prepare_alloc_legacy
    test rax, rax
    jz .Leplvs_alloc_error
    mov r13, rax
    mov rdi, rax
    call prep_asset_plan
    mov [rsp + 96], rax
    test rax, rax
    jnz .Leplvs_release_plan
    mov rax, [r13 + EP_plan + VEC_len]
    cmp rax, [r12 + EP_plan + VEC_len]
    jne .Leplvs_changed_plan
    xor r14d, r14d
.Leplvs_compare:
    cmp r14, [r12 + EP_plan + VEC_len]
    jae .Leplvs_release_plan
    imul rax, r14, AP_SIZE
    mov r15, [r12 + EP_plan + VEC_ptr]
    add r15, rax
    add rax, [r13 + EP_plan + VEC_ptr]
    mov [rsp + 64], rax
    mov rcx, [rax + AP_len]
    cmp rcx, [r15 + AP_len]
    jne .Leplvs_changed_plan
    mov rdi, [rax + AP_path]
    mov rsi, [r15 + AP_path]
    mov rdx, rcx
    call memeq
    test eax, eax
    jz .Leplvs_changed_plan
    mov rdi, [rsp + 64]
    add rdi, AP_kind
    lea rsi, [r15 + AP_kind]
    mov edx, 24              # kind,size,exec, all from actual current objects
    call memeq
    test eax, eax
    jz .Leplvs_changed_plan
    inc r14
    jmp .Leplvs_compare
.Leplvs_changed_plan:
    mov qword ptr [rsp + 96], -EV_CHANGED
.Leplvs_release_plan:
    mov rdi, r13
    call ext_prepare_release
    mov [rsp + 104], rax
.Leplvs_return:
    mov rax, [rsp + 96]
    mov rdx, [rsp + 104]
    test rax, rax
    jnz 4f
    mov rax, rdx
4:  EPILOGUE
.Leplvs_open_error:
    mov [rsp + 96], rax
    mov [rsp + 104], rdx
    jmp .Leplvs_return
.Leplvs_alloc_error:
    mov rax, rdx
    mov rdx, rcx
    EPILOGUE

# Fresh full legacy preparation plus exact final source/membership check.
# Returns ready owned EP with commitment stored at EP_legacy_source, or0/RDXprimary/RCXcleanup.
FN prep_legacy_validate_ep
    PROLOGUE 64
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    mov r8, -1
    call ext_prepare_begin_legacy
    test rax, rax
    jz .Leplve_done
    mov rbx, rax
1:  mov rdi, rbx
    call ext_prepare_step
    cmp rax, 1
    je 1b
    test rax, rax
    jnz .Leplve_fail
    mov rdi, rbx
    lea rsi, [rbx + EP_legacy_source]
    call ext_prepare_source_commitment
    test rax, rax
    jnz .Leplve_fail
    mov rsi, [rsp + 32]
    test rsi, rsi
    jz 2f
    lea rdi, [rbx + EP_legacy_source]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Leplve_changed
2:  mov rdi, [rsp]
    mov rsi, rbx
    call prep_legacy_verify_sources
    test rax, rax
    jnz .Leplve_fail
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call prep_legacy_anchor_check
    test rax, rax
    jnz .Leplve_fail
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
.Leplve_done:
    EPILOGUE
.Leplve_changed:
    mov rax, -EV_CHANGED
    xor edx, edx
.Leplve_fail:
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call ext_prepare_release
    test r13, r13
    jnz 3f
    mov r13, rax
3:  mov rdx, r12
    mov rcx, r13
    xor eax, eax
    EPILOGUE

# rootBorrowed,DIR,owner,name,expectedSourceOr0,out32 ->primary/cleanup. Untouched output on error.
FN ext_validate_legacy_from_root_result
    PROLOGUE 48
    mov rbx, r9
    call prep_legacy_validate_ep
    test rax, rax
    jz 2f
    mov r12, rax
    lea rsi, [rax + EP_legacy_source]
    mov rdi, rsp
    mov edx, 32
    call memcpy
    mov rdi, r12
    call ext_prepare_release
    mov rdx, rax
    test rax, rax
    jnz 3f
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 32
    call memcpy
    xor eax, eax
    xor edx, edx
3:  EPILOGUE
2:  mov rax, rdx
    mov rdx, rcx
    EPILOGUE
