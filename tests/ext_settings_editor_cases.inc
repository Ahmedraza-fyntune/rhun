# Pure predicate double for hostile-input ordering; not actual HI integration.
.bss
eb_calls: .quad 0
eb_allow: .quad 0
eb_vector: .quad 0
eb_slot: .quad 0
eb_sd: .quad 0
eb_ordinal: .quad 0
.section .rodata
eb_five: .asciz "5"
eb_ten: .asciz "10"
.text
FN eb_metadata_predicate
    inc qword ptr [rip + eb_calls]
    xor eax, eax
    cmp rdi, [rip + eb_slot]
    je 1f
    cmp rdi, [rip + eb_vector]
    jne 2f
1:  mov rax, [rip + eb_allow]
2:  ret
# Metadata success is independent of effective-model readiness.
eb_resolve_valid:
    PROLOGUE
    mov r12, rdi
    mov rdi, [rip + eb_slot]
    mov r13, [rdi + EXT_metadata_owner]
    mov rsi, [rip + eb_sd]
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_resolve
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, [rip + eb_ordinal]
    jne vt_fail
    cmp rdx, r13
    jne vt_fail
    cmp r8, r12
    jne vt_fail
    EPILOGUE
eb_resolve_error:
    PROLOGUE
    mov r12, rdx
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_resolve
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, r12
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    EPILOGUE
eb_error:
    PROLOGUE
    mov rbx, rdx
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_value
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jnz vt_fail
    cmp rdx, rbx
    jne vt_fail
    test rcx, rcx
    jnz vt_fail
    EPILOGUE
eb_value:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    mov rdi, [rip + eb_slot]
    mov rsi, [rip + eb_sd]
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_value
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jz vt_fail
    test rdx, rdx
    jnz vt_fail
    cmp rcx, r12
    jne vt_fail
    mov rdi, rax
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jz vt_fail
    EPILOGUE
# Exact scalar flags contract, including clear booleans on getter error.
eb_flags:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, [rip + eb_slot]
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_flags
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, r12
    jne vt_fail
    cmp rdx, r13
    jne vt_fail
    cmp rcx, r14
    jne vt_fail
    EPILOGUE
# Borrow only an already-retained fixture EP for a synchronous installed slot.
eb_set_slot:
    mov [rip + eb_ordinal], rsi
    mov rax, [rip + eb_vector]
    imul rsi, rsi, EXT_SIZE
    add rax, rsi
    mov [rip + eb_slot], rax
    mov [rax + EXT_metadata_owner], rdi
    mov rcx, [rdi + EP_ext + EXT_sdefs + VEC_ptr]
    mov [rax + EXT_sdefs + VEC_ptr], rcx
    mov [rip + eb_sd], rcx
    mov rcx, [rdi + EP_ext + EXT_sdefs + VEC_len]
    mov [rax + EXT_sdefs + VEC_len], rcx
    mov rcx, [rdi + EP_ext + EXT_sdefs + VEC_cap]
    mov [rax + EXT_sdefs + VEC_cap], rcx
    ret
eb_cases:
    PROLOGUE 16
    mov qword ptr [rip + eb_allow], 1
    mov qword ptr [rip + vt_stage], 180
    mov edi, EXT_SIZE * 128
    call mem_alloc_try
    test rax, rax
    jz vt_fail
    mov [rip + eb_vector], rax
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_len], 128
    mov qword ptr [rip + g_exts + VEC_cap], 128
    lea rbx, [rax + EXT_SIZE * 127]
    mov [rip + eb_slot], rbx
    mov qword ptr [rip + eb_ordinal], 127
    mov r12, [rip + vt_schema_a]
    mov [rbx + EXT_metadata_owner], r12
    mov rax, [r12 + EP_ext + EXT_sdefs + VEC_ptr]
    mov [rbx + EXT_sdefs + VEC_ptr], rax
    mov [rip + eb_sd], rax
    mov rax, [r12 + EP_ext + EXT_sdefs + VEC_len]
    mov [rbx + EXT_sdefs + VEC_len], rax
    mov rax, [r12 + EP_ext + EXT_sdefs + VEC_cap]
    mov [rbx + EXT_sdefs + VEC_cap], rax
    lea rdi, [rip + vt_base]
    call eb_value
    mov qword ptr [rip + av_read_poison], 1
    mov rdi, rbx
    call ext_setting_flags
    mov qword ptr [rip + av_read_poison], 0
    or rax, rdx
    or rax, rcx
    jnz vt_fail
    # Nonzero SD ordinals must translate to their exact own-schema row.
    mov rax, [rip + eb_sd]
    mov [rsp + 8], rax
    add qword ptr [rip + eb_sd], 2 * SD_SIZE
    mov edi, 2
    call eb_resolve_valid
    lea rdi, [rip + eb_five]
    call eb_value
    mov rax, [rsp + 8]
    mov [rip + eb_sd], rax
    lea rdi, [rip + av_empty]
    xor esi, esi
    call av_text
    lea rdi, [rip + av_empty]
    call eb_value
    lea rdi, [rip + vt_base]
    mov esi, 4
    call av_text
    mov qword ptr [rip + vt_stage], 188
    lea rdi, [rip + vt_yes]
    mov esi, 3
    lea rdx, [rip + av_pinned]
    mov ecx, 6
    xor r8d, r8d
    call av_put
    mov edi, 1
    xor esi, esi
    xor edx, edx
    call eb_flags
    lea rdi, [rip + vt_yes]
    mov esi, 3
    lea rdx, [rip + av_disabled]
    mov ecx, 8
    xor r8d, r8d
    call av_put
    mov edi, 1
    mov esi, 1
    xor edx, edx
    call eb_flags
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + av_pinned]
    mov ecx, 6
    mov r8d, 1
    call av_put
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + av_disabled]
    mov ecx, 8
    mov r8d, 1
    call av_put
    mov qword ptr [rip + vt_stage], 181
    mov qword ptr [rip + eb_calls], 0
    mov edi, 1
    mov esi, 1
    mov rdx, -22
    call eb_resolve_error
    xor edi, edi
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov edi, 1
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov rdi, [rip + eb_vector]
    dec rdi
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov rdi, [rip + eb_vector]
    add rdi, EXT_SIZE * 128
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov rdi, rbx
    inc rdi
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov qword ptr [rip + g_exts + VEC_len], 129
    mov rdi, rbx
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov qword ptr [rip + g_exts + VEC_len], 128
    cmp qword ptr [rip + eb_calls], 0
    jne vt_fail
    mov qword ptr [rip + vt_stage], 182
    mov rdi, rbx
    mov esi, 1
    mov rdx, -22
    call eb_resolve_error
    mov rdi, rbx
    xor esi, esi
    mov rdx, -22
    call eb_error
    mov rdi, rbx
    mov esi, 1
    mov rdx, -22
    call eb_error
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    dec rsi
    mov rdx, -22
    call eb_error
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    inc rsi
    mov rdx, -22
    call eb_error
    mov rdi, rbx
    mov rsi, [rbx + EXT_sdefs + VEC_len]
    imul rsi, rsi, SD_SIZE
    add rsi, [rip + eb_sd]
    mov rdx, -22
    call eb_error
    mov qword ptr [rip + vt_stage], 183
    mov qword ptr [rip + eb_allow], 0
    mov rdi, rbx
    mov esi, 1
    mov rdx, -116
    call eb_resolve_error
    mov rdi, rbx
    mov esi, 1
    mov rdx, -116
    call eb_error
    mov rdi, rbx
    call ext_setting_flags
    test rax, rax
    jnz vt_fail
    test rdx, rdx
    jnz vt_fail
    cmp rcx, -116
    jne vt_fail
    mov qword ptr [rip + eb_allow], 1
    mov qword ptr [rip + vt_stage], 184
    inc qword ptr [rbx + EXT_sdefs + VEC_ptr]
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    mov rdx, -116
    call eb_error
    dec qword ptr [rbx + EXT_sdefs + VEC_ptr]
    inc qword ptr [rbx + EXT_sdefs + VEC_len]
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    mov rdx, -116
    call eb_error
    dec qword ptr [rbx + EXT_sdefs + VEC_len]
    inc qword ptr [rbx + EXT_sdefs + VEC_cap]
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    mov rdx, -116
    call eb_error
    dec qword ptr [rbx + EXT_sdefs + VEC_cap]
    mov rax, [rip + vt_schema_b]
    mov [rbx + EXT_metadata_owner], rax
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    mov rdx, -116
    call eb_error
    mov [rbx + EXT_metadata_owner], r12
    # New queue intent must override immutable SD default authority.
    mov qword ptr [rip + vt_stage], 186
    lea rdi, [rip + av_010]
    mov esi, 3
    call av_text
    lea rdi, [rip + av_010]
    call eb_value
    lea rdi, [rip + vt_base]
    mov esi, 4
    call av_text
    lea rdi, [rip + vt_base]
    call eb_value
    mov qword ptr [rip + vt_stage], 185
    mov rdi, [rip + eb_vector]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, [rip + eb_vector]
    mov rsi, [rip + eb_sd]
    mov rdx, -116
    call eb_error
    mov rax, [rip + esv_live_model]
    mov [rsp], rax
    mov qword ptr [rip + esv_live_model], 0
    xor edi, edi
    call eb_resolve_valid
    mov rdi, rbx
    mov rsi, [rip + eb_sd]
    mov rdx, -11
    call eb_error
    xor edi, edi
    xor esi, esi
    mov rdx, -11
    call eb_flags
    mov rax, [rsp]
    mov [rip + esv_live_model], rax
    # Replacement integer schema must normalize old string intent before reads.
    mov qword ptr [rip + vt_stage], 187
    lea rdi, [rip + av_010]
    mov esi, 3
    call av_text
    mov rdi, [rip + vt_schema_b]
    mov rsi, [rip + vt_source]
    mov edx, 64
    call av_model
    mov rdi, [rip + vt_schema_b]
    mov esi, 64
    call eb_set_slot
    lea rdi, [rip + eb_ten]
    call eb_value
    # A real empty descriptor still permits effective pin/disable reads.
    lea rdi, [rip + av_empty]
    xor esi, esi
    call vt_schema
    mov r14, rax
    mov rdi, rax
    mov rsi, [rip + vt_source]
    mov edx, 64
    call av_model
    mov rdi, r14
    mov esi, 64
    call eb_set_slot
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call eb_flags
    mov rdi, [rip + eb_slot]
    mov esi, 1
    mov rdx, -22
    call eb_error
    # Restore the original active fixture map and effective base before returning.
    lea rdi, [rip + vt_base]
    mov esi, 4
    call av_text
    mov rdi, [rip + vt_schema_a]
    mov rsi, [rip + vt_source]
    mov edx, 127
    call av_model
    mov rdi, [rip + vt_schema_a]
    mov esi, 127
    call eb_set_slot
    lea rdi, [rip + vt_base]
    call eb_value
    mov rdi, r14
    call ext_prepare_release_deferred
    call vt_gc
    mov rdi, [rip + eb_vector]
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_cap], 0
    call mem_free
    EPILOGUE
