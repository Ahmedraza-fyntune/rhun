# Actual HI/metadata predicate composition. Caller retains HI/EP through all reads.
.include "app/exthostidentity.inc"
.section .rodata
.ifdef WINDOWS
ebr_state: .asciz "C:/settings-fixture"
.else
ebr_state: .asciz "/settings-fixture"
.endif
.text
ebr_resolve_valid:
    PROLOGUE
    mov r12, rdx
    mov r13, [rdi + EXT_metadata_owner]
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_resolve_real
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, 127
    jne vt_fail
    cmp rdx, r13
    jne vt_fail
    cmp r8, r12
    jne vt_fail
    EPILOGUE
ebr_resolve_error:
    PROLOGUE
    mov r12, rdx
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_resolve_real
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, r12
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    EPILOGUE
ebr_schema:
    mov [rdi + EXT_metadata_owner], rsi
    mov rax, [rsi + EP_ext + EXT_sdefs + VEC_ptr]
    mov [rdi + EXT_sdefs + VEC_ptr], rax
    mov rax, [rsi + EP_ext + EXT_sdefs + VEC_len]
    mov [rdi + EXT_sdefs + VEC_len], rax
    mov rax, [rsi + EP_ext + EXT_sdefs + VEC_cap]
    mov [rdi + EXT_sdefs + VEC_cap], rax
    ret
ebr_value:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    call strlen
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_value_real
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jz vt_fail
    test rdx, rdx
    jnz vt_fail
    cmp rcx, r14
    jne vt_fail
    mov rdi, rax
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz vt_fail
    EPILOGUE
ebr_error:
    PROLOGUE
    mov rbx, rdx
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_value_real
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jnz vt_fail
    cmp rdx, rbx
    jne vt_fail
    test rcx, rcx
    jnz vt_fail
    EPILOGUE
ebr_cases:
    PROLOGUE 16
    mov qword ptr [rip + vt_stage], 190
    lea rdi, [rip + vt_owner]
    lea rsi, [rip + vt_name]
    lea rdx, [rip + ebr_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz vt_fail
    test rdx, rdx
    jnz vt_fail
    mov r14, rax
    mov rdi, rax
    call hi_is_ready
    cmp eax, 1
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
    mov [rbx + EXT_identity_owner], r14
    mov rax, [r14 + HI_owner]
    mov [rbx + EXT_owner], rax
    mov rax, [r14 + HI_name]
    mov [rbx + EXT_name], rax
    mov rax, [r14 + HI_state]
    mov [rbx + EXT_state], rax
    mov dword ptr [rbx + EXT_catalog_state], 1
    mov rdi, rbx
    mov rsi, [rip + vt_schema_a]
    call ebr_schema
    call ext_catalog_begin_prepared_pure
    mov rdi, rbx
    call ext_has_metadata
    cmp eax, 1
    jne vt_fail
    mov rdi, rbx
    mov rsi, [rbx + EXT_sdefs + VEC_ptr]
    lea rdx, [rip + vt_base]
    call ebr_value
    mov rdi, rbx
    mov rsi, [rbx + EXT_sdefs + VEC_ptr]
    add rsi, 2 * SD_SIZE
    mov edx, 2
    call ebr_resolve_valid
    mov rdi, rbx
    mov rsi, [rbx + EXT_sdefs + VEC_ptr]
    add rsi, 2 * SD_SIZE
    lea rdx, [rip + eb_five]
    call ebr_value
    mov rdi, rbx
    mov qword ptr [rip + av_read_poison], 1
    call ext_setting_flags_real
    mov qword ptr [rip + av_read_poison], 0
    or rax, rdx
    or rax, rcx
    jnz vt_fail
    # Real one-way withdrawal must precede an intentionally invalid SD.
    mov qword ptr [rip + vt_stage], 191
    mov rdi, r12
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, r12
    call ext_slot_hide_pure
    mov rdi, r12
    mov esi, 1
    mov rdx, -116
    call ebr_resolve_error
    mov rdi, r12
    mov esi, 1
    mov rdx, -116
    call ebr_error
    # Exact typed HI and owned string-pointer identity cannot be substituted.
    mov qword ptr [rip + vt_stage], 192
    lea rax, [rip + vt_name]
    mov [rbx + EXT_name], rax
    mov rdi, rbx
    mov esi, 1
    mov rdx, -116
    call ebr_error
    mov rax, [r14 + HI_name]
    mov [rbx + EXT_name], rax
    mov [rbx + EXT_metadata_owner], r14
    mov rdi, rbx
    mov esi, 1
    mov rdx, -116
    call ebr_error
    # An actual ready EP of the wrong active schema is refused after metadata proof.
    mov qword ptr [rip + vt_stage], 193
    mov rdi, rbx
    mov rsi, [rip + vt_schema_b]
    call ebr_schema
    mov rdi, rbx
    mov rsi, [rbx + EXT_sdefs + VEC_ptr]
    mov rdx, -116
    call ebr_error
    # No slot reference survives before the separately owned suppliers are released.
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_cap], 0
    mov rdi, r12
    call mem_free
    mov rdi, r14
    call ext_host_identity_release
    test rax, rax
    jnz vt_fail
    call vt_gc
    EPILOGUE
