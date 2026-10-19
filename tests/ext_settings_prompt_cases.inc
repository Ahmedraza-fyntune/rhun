# Helper eligibility only. Actual delayed prompt/ABA tests belong to caller hooks.
.section .rodata
eb_five: .asciz "5"
epr_owner_fields: .quad EXT_metadata_owner, EXT_identity_owner, EXT_activation_owner
.bss
.p2align 3
epr_sdefs: .zero SD_SIZE * 3
.text
epr_error:
    PROLOGUE
    mov r14, rdx
    mov r8d, 999
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_prompt_resolve
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, r14
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    EPILOGUE
epr_legacy_valid:
    PROLOGUE
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_prompt_resolve
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, 127
    jne vt_fail
    or rdx, rcx
    jnz vt_fail
    cmp r8, 2
    jne vt_fail
    EPILOGUE
epr_prepared_valid:
    PROLOGUE
    mov r14, [rdi + EXT_metadata_owner]
    mov r15, rdx
    mov r13, [rip + esv_live_model]
    mov qword ptr [rip + esv_live_model], 0
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_prompt_resolve
    mov qword ptr [rip + av_read_poison], 0
    mov [rip + esv_live_model], r13
    cmp rax, 127
    jne vt_fail
    cmp rdx, r14
    jne vt_fail
    cmp r8, r15
    jne vt_fail
    test rcx, rcx
    jnz vt_fail
    EPILOGUE
epr_legacy_cases:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 200
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 0
    jne vt_fail
    mov edi, EXT_SIZE * 128
    call mem_alloc_try
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_len], 128
    mov qword ptr [rip + g_exts + VEC_cap], 128
    lea rbx, [rax + EXT_SIZE * 127]
    lea rax, [rip + epr_sdefs]
    mov [rbx + EXT_sdefs + VEC_ptr], rax
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 3
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 3
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    call epr_legacy_valid
    lea rdi, [r12 + 1]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, r12
    inc rdi
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -22
    call epr_error
    mov rdi, rbx
    mov esi, 1
    mov rdx, -22
    call epr_error
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 1]
    mov rdx, -22
    call epr_error
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 2
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -22
    call epr_error
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 3
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 257
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 257
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -22
    call epr_error
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 3
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 3
    mov qword ptr [rip + vt_stage], 201
    xor r13d, r13d
1:  lea rax, [rip + epr_owner_fields]
    mov r15, [rax + r13 * 8]
    mov qword ptr [rbx + r15], 1
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -116
    call epr_error
    mov qword ptr [rbx + r15], 0
    inc r13
    cmp r13, 3
    jb 1b
    mov dword ptr [rbx + EXT_activation_required], 1
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -116
    call epr_error
    mov dword ptr [rbx + EXT_activation_required], 0
    mov qword ptr [rip + vt_stage], 202
    mov dword ptr [rbx + EXT_status], ES_REMOVED
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -116
    call epr_error
    mov dword ptr [rbx + EXT_status], 0
    # Same staged bytes can never re-enter fallback after the one-way latch.
    mov qword ptr [rip + vt_stage], 203
    call ext_catalog_begin_prepared_pure
    mov rdi, rbx
    lea rsi, [rip + epr_sdefs + 2 * SD_SIZE]
    mov rdx, -116
    call epr_error
    # Malformed global authority is refused; restore only the already-active latch1.
    mov qword ptr [rip + g_ext_prepared_catalog_active], 2
    mov rdi, rbx
    mov esi, 1
    mov rdx, -116
    call epr_error
    mov qword ptr [rip + g_ext_prepared_catalog_active], 1
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_cap], 0
    mov rdi, r12
    call mem_free
    EPILOGUE
