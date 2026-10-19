.section .rodata
av_010: .asciz "010"
av_011: .asciz "011"
av_11: .asciz "11"
av_10: .asciz "10"
av_7: .asciz "7"
av_0007: .asciz "0007"
av_count_key: .ascii "setting.count"
av_later: .asciz "later"
av_providers: .ascii "[providers]\nformat.py=old/tool\nformat.*=wild/tool\nformat.collision9=first/tool\nformat.collision180=second/tool\n"
av_providers_end:
.equ AV_PROVIDERS_LEN, 111
av_collision: .ascii "collision180"
av_collision_owner: .asciz "second/tool"
av_py: .ascii "py"
av_missing: .ascii "missing"
av_wild: .ascii "*"
av_wild_owner: .asciz "wild/tool"
av_pinned: .ascii "pinned"
av_disabled: .ascii "disabled"
av_empty: .asciz ""
av_bad_utf8: .byte 0xc0,0x80,0
av_edge: .asciz " space "
av_nul: .byte 'a',0,'b',0
av_upper: .asciz "YES"
av_100: .asciz "100"
av_zero: .asciz "0"
.p2align 3
av_canonical_table:
    .quad 0,0,av_empty,0,0
    .quad 0,0,av_bad_utf8,2,-22
    .quad 0,0,av_edge,7,-22
    .quad 0,0,av_nul,3,-22
    .quad 0,0,vt_text,16,0
    .quad 0,1,vt_yes,3,0
    .quad 0,1,av_upper,3,-22
    .quad 0,2,vt_99,2,0
    .quad 0,2,av_100,3,-22
    .quad 0,2,av_zero,1,-22
    .quad 0,2,av_0007,4,-22
    .quad 0,3,vt_red,3,0
    .quad 0,3,vt_green,5,-22
    .quad 1,3,vt_green,5,0
    .quad 0,0,1,65536,-22
    .quad 0,256,1,0,-22
av_canonical_end:
.equ AV_CANONICAL_COUNT, 16
av_ok: .ascii "ok installed settings authority and canonical dirty overlays\n"
.equ AV_OK_LEN, 61
.bss
.p2align 3
.globl av_read_poison
av_read_poison: .quad 0
.text
.globl av_poison_fail
av_poison_fail:
    mov qword ptr [rip + vt_stage], 170
    jmp vt_fail
# Counted arbitrary intent fixture. Production native setters canonicalize first.
av_put:
    PROLOGUE EC_SIZE
    lea rax, [rip + vt_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 15
    mov [rsp + EC_value], rdi
    mov [rsp + EC_vallen], rsi
    mov [rsp + EC_key], rdx
    mov [rsp + EC_keylen], rcx
    mov [rsp + EC_remove], r8
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    EPILOGUE
av_text:
    lea rdx, [rip + vt_key]
    mov ecx, 12
    xor r8d, r8d
    jmp av_put
# EP,source,stableSlot -> install through real catalog model ownership.
av_model:
    PROLOGUE
    mov r13, rdx
    mov r14, rsi
    mov edx, 7
    call vt_build
    mov r12, rax
    mov rdi, rax
    mov rsi, r13
    call ct_one_row
    mov rdi, r14
    mov rsi, rax
    mov edx, 1
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rdi, r12
    call ext_settings_view_release
    call ct_gc
    EPILOGUE
# slot,EP,index,expectedcstr verifies borrowed bytes immediately, without mutation.
av_value:
    PROLOGUE
    mov rbx, rcx
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_effective_value
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jz vt_fail
    test rdx, rdx
    jnz vt_fail
    mov rdi, rax
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jz vt_fail
    EPILOGUE
av_error:
    PROLOGUE
    mov rbx, rcx
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_effective_value
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jnz vt_fail
    cmp rdx, rbx
    jne vt_fail
    test rcx, rcx
    jnz vt_fail
    EPILOGUE
av_provider_put:
    PROLOGUE EC_SIZE
    mov [rsp + EC_value], rdi
    mov [rsp + EC_vallen], rsi
    mov [rsp + EC_remove], rdx
    lea rax, [rip + ct_provider_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 9
    lea rax, [rip + ct_provider_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 9
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    call ext_settings_provider_changed
    test rax, rax
    jnz vt_fail
    EPILOGUE
av_provider_expect:
    PROLOGUE
    mov r12, rcx
    mov r13, r8
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_effective_provider
    mov qword ptr [rip + av_read_poison], 0
    test rdx, rdx
    jnz vt_fail
    cmp rcx, r13
    jne vt_fail
    test r12, r12
    jnz 1f
    test rax, rax
    jnz vt_fail
    EPILOGUE
1:  test rax, rax
    jz vt_fail
    mov rdi, rax
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz vt_fail
    EPILOGUE
av_flags_expect:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_effective_flags
    mov qword ptr [rip + av_read_poison], 0
    test rcx, rcx
    jnz vt_fail
    cmp rax, r12
    jne vt_fail
    cmp rdx, r13
    jne vt_fail
    EPILOGUE
av_provider_flags:
    PROLOGUE 32
    mov qword ptr [rip + vt_stage], 166
    mov edi, 6
    lea rsi, [rip + av_py]
    mov edx, 2
    lea rcx, [rip + ct_owner_old]
    mov r8d, 1
    call av_provider_expect
    mov edi, 6
    lea rsi, [rip + av_missing]
    mov edx, 7
    xor ecx, ecx
    xor r8d, r8d
    call av_provider_expect
    mov edi, 6
    lea rsi, [rip + av_collision]
    mov edx, 12
    lea rcx, [rip + av_collision_owner]
    mov r8d, 1
    call av_provider_expect
    xor edi, edi
    xor esi, esi
    call av_flags_expect
    lea rdi, [rip + vt_yes]
    mov esi, 3
    lea rdx, [rip + av_pinned]
    mov ecx, 6
    xor r8d, r8d
    call av_put
    lea rdi, [rip + vt_yes]
    mov esi, 3
    lea rdx, [rip + av_disabled]
    mov ecx, 8
    xor r8d, r8d
    call av_put
    mov edi, 1
    mov esi, 1
    call av_flags_expect
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + av_disabled]
    mov ecx, 8
    mov r8d, 1
    call av_put
    mov edi, 1
    xor esi, esi
    call av_flags_expect
    lea rdi, [rip + vt_bad]
    mov esi, 3
    lea rdx, [rip + av_pinned]
    mov ecx, 6
    xor r8d, r8d
    call av_put
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    call ext_settings_effective_flags
    cmp rcx, -22
    jne vt_fail
    or rax, rdx
    jnz vt_fail
    lea rdi, [rip + vt_yes]
    mov esi, 3
    lea rdx, [rip + av_pinned]
    mov ecx, 6
    xor r8d, r8d
    call av_put
    lea rdi, [rip + ct_owner_new]
    mov esi, 8
    xor edx, edx
    call av_provider_put
    mov edi, 6
    lea rsi, [rip + av_py]
    mov edx, 2
    call ext_settings_effective_provider
    test rdx, rdx
    jnz vt_fail
    cmp rcx, 1
    jne vt_fail
    cmp r8, 8
    jne vt_fail
    mov [rsp], rax
    mov edi, 9
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov rdi, rax
    mov rsi, [rsp]
    mov edx, 9
    call memcpy
    mov r14, [rip + esv_live_model]
    mov rdi, r14
    call ext_settings_model_retain
    test rax, rax
    jnz vt_fail
    lea rdi, [rip + ct_owner_next]
    mov esi, 9
    xor edx, edx
    call av_provider_put
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_gc
    test rdx, rdx
    jnz vt_fail
    mov rax, [rip + vt_queue]
    cmp qword ptr [rax + EQ_retired_count], 0
    jne vt_fail
    mov rdi, r12
    lea rsi, [rip + ct_owner_new]
    call strcmp_eq
    test eax, eax
    jz vt_fail
    mov rdi, r12
    call ext_settings_memory_free
    cmp rcx, 1
    jne vt_fail
    mov rdi, r14
    call ext_settings_model_release
    lea rdi, [rip + vt_bad]
    mov esi, 3
    xor edx, edx
    call av_provider_put
    mov edi, 6
    lea rsi, [rip + av_py]
    mov edx, 2
    call ext_settings_effective_provider
    test rax, rax
    jnz vt_fail
    cmp rdx, -22
    jne vt_fail
    or rcx, r8
    jnz vt_fail
    mov r13, [rip + esv_provider_epoch]
    mov qword ptr [rip + esv_provider_epoch], 0
    mov edi, 6
    lea rsi, [rip + av_py]
    mov edx, 2
    call ext_settings_effective_provider
    test rax, rax
    jnz vt_fail
    cmp rdx, -116
    jne vt_fail
    mov [rip + esv_provider_epoch], r13
    xor edi, edi
    xor esi, esi
    mov edx, 1
    call av_provider_put
    mov edi, 6
    lea rsi, [rip + av_py]
    mov edx, 2
    xor ecx, ecx
    mov r8d, 1
    call av_provider_expect
    mov edi, 6
    lea rsi, [rip + av_wild]
    mov edx, 1
    lea rcx, [rip + av_wild_owner]
    mov r8d, 1
    call av_provider_expect
    EPILOGUE
av_canonical_cases:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 167
    lea r14, [rip + av_canonical_table]
    mov r12d, AV_CANONICAL_COUNT
1:  mov rdi, [rip + vt_schema_a]
    cmp qword ptr [r14], 0
    je 2f
    mov rdi, [rip + vt_schema_b]
2:  mov rsi, [r14 + 8]
    mov rdx, [r14 + 16]
    mov rcx, [r14 + 24]
    mov r13, [r14 + 32]
    mov r8d, 4
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_canonical_value
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, r13
    jne vt_fail
    add r14, 40
    dec r12
    jnz 1b
    mov edi, 65522
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 'a'
    mov edx, 65521
    call memset
    mov byte ptr [rbx + 65520], 0
    mov byte ptr [rbx + 65521], 0
    mov rdi, [rip + vt_schema_a]
    xor esi, esi
    mov rdx, rbx
    mov ecx, 65520
    mov r8d, 4
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_canonical_value
    mov qword ptr [rip + av_read_poison], 0
    test rax, rax
    jnz vt_fail
    mov byte ptr [rbx + 65520], 'a'
    mov rdi, [rip + vt_schema_a]
    xor esi, esi
    mov rdx, rbx
    mov ecx, 65521
    mov r8d, 4
    mov qword ptr [rip + av_read_poison], 1
    call ext_settings_canonical_value
    mov qword ptr [rip + av_read_poison], 0
    cmp rax, -22
    jne vt_fail
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    jne vt_fail
    EPILOGUE
FN main
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 160
    mov r15, [rip + g_mem_live]
    call ext_settings_queue_create
    test rax, rax
    jz vt_fail
    mov [rip + vt_queue], rax
    mov rdi, rax
    mov esi, 29
    call ext_settings_model_context_init
    test rax, rax
    jnz vt_fail
    lea rdi, [rip + vt_schema1]
    mov esi, VT_SCHEMA1_LEN
    call vt_schema
    mov [rip + vt_schema_a], rax
    lea rdi, [rip + vt_schema2]
    mov esi, VT_SCHEMA2_LEN
    call vt_schema
    mov [rip + vt_schema_b], rax
    lea rdi, [rip + av_providers]
    mov esi, AV_PROVIDERS_LEN
    call vt_snapshot
    mov [rip + vt_source], rax
    mov rdi, [rip + vt_schema_a]
    mov rsi, rax
    mov edx, 127
    call av_model
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    xor edx, edx
    lea rcx, [rip + vt_base]
    call av_value
    call av_provider_flags
    mov qword ptr [rip + vt_stage], 161
    lea rdi, [rip + av_010]
    mov esi, 3
    call av_text
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    xor edx, edx
    call ext_settings_effective_value
    test rax, rax
    jz vt_fail
    test rdx, rdx
    jnz vt_fail
    cmp rcx, 3
    jne vt_fail
    mov [rsp], rax
    mov edi, 4
    call ext_settings_memory_try
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov rdi, rax
    mov rsi, [rsp]
    mov edx, 4
    call memcpy
    mov r13, [rip + esv_live_model]
    mov rdi, r13
    call ext_settings_model_retain
    test rax, rax
    jnz vt_fail
    lea rdi, [rip + av_later]
    mov esi, 5
    call av_text
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_gc
    test rdx, rdx
    jnz vt_fail
    # The old borrowed pointer is never used after GC. The copied bytes survive
    # independently while retaining the old model did not retain its queue cell.
    mov rdi, r12
    lea rsi, [rip + av_010]
    call strcmp_eq
    test eax, eax
    jz vt_fail
    mov rdi, r12
    call ext_settings_memory_free
    cmp rcx, 1
    jne vt_fail
    mov qword ptr [rip + vt_stage], 162
    lea rdi, [rip + av_0007]
    mov esi, 4
    lea rdx, [rip + av_count_key]
    mov ecx, 13
    xor r8d, r8d
    call av_put
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    mov edx, 2
    mov rcx, -22
    call av_error
    lea rdi, [rip + av_7]
    mov esi, 1
    lea rdx, [rip + av_count_key]
    mov ecx, 13
    xor r8d, r8d
    call av_put
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    mov edx, 2
    lea rcx, [rip + av_7]
    call av_value
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + av_count_key]
    mov ecx, 13
    mov r8d, 1
    call av_put
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    mov edx, 2
    lea rcx, [rip + vt_five]
    call av_value
    mov qword ptr [rip + vt_stage], 163
    lea rdi, [rip + av_010]
    mov esi, 3
    call av_text
    mov rdi, [rip + vt_schema_b]
    mov rsi, [rip + vt_source]
    mov edx, 64
    call av_model
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    xor edx, edx
    lea rcx, [rip + av_10]
    call av_value
    mov edi, 127
    mov rsi, [rip + vt_schema_a]
    xor edx, edx
    mov rcx, -116
    call av_error
    mov rdi, r13
    call ext_settings_model_release
    lea rdi, [rip + av_11]
    mov esi, 2
    call av_text
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    xor edx, edx
    lea rcx, [rip + av_11]
    call av_value
    lea rdi, [rip + av_011]
    mov esi, 3
    call av_text
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    xor edx, edx
    mov rcx, -22
    call av_error
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + vt_key]
    mov ecx, 12
    mov r8d, 1
    call av_put
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    xor edx, edx
    lea rcx, [rip + vt_20]
    call av_value
    mov qword ptr [rip + vt_stage], 164
    mov edi, 64
    mov esi, 1
    xor edx, edx
    mov rcx, -116
    call av_error
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    mov edx, 256
    mov rcx, -22
    call av_error
    inc qword ptr [rip + esv_registry_epoch]
    mov edi, 64
    mov rsi, [rip + vt_schema_b]
    xor edx, edx
    mov rcx, -116
    call av_error
    dec qword ptr [rip + esv_registry_epoch]
    call av_canonical_cases
    mov qword ptr [rip + vt_stage], 165
    mov rdi, [rip + esv_live_model]
    mov qword ptr [rip + esv_live_model], 0
    call ext_settings_model_release
    mov rdi, [rip + ct_live_owner]
    call ext_settings_model_release
    mov rdi, [rip + vt_schema_a]
    call ext_prepare_release_deferred
    mov rdi, [rip + vt_schema_b]
    call ext_prepare_release_deferred
    mov rdi, [rip + vt_source]
    call ext_settings_snapshot_release
    call ct_gc
    call vt_queue_clear
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_free
    test rax, rax
    jnz vt_fail
    mov qword ptr [rip + esv_service_queue], 0
    call ext_settings_memory_total
    test rax, rax
    jnz vt_fail
    cmp [rip + g_mem_live], r15
    jne vt_fail
    mov edi, 1
    lea rsi, [rip + av_ok]
    mov edx, AV_OK_LEN
    call write_all
    xor edi, edi
    call sys_exit
