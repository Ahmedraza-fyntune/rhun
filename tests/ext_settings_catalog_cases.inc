# Appended after the real ESV fixture helpers by the dedicated test driver.
# The synthetic ready EPs authorize only normalization/lifetime tests.
.include "app/extsettingscatalog.inc"
.equ CT_SOURCE_A_LEN, 247
.equ CT_SOURCE_B_LEN, 190
.equ CT_SOURCE_C_LEN, 187
.equ CT_CAPACITY_512_LEN, 8204
.equ CT_CAPACITY_513_LEN, 8220
.bss
.p2align 3
ct_schema_b: .quad 0
ct_source_b_ref: .quad 0
ct_source_c_ref: .quad 0
ct_live_owner: .quad 0
.globl ct_poison
ct_poison: .quad 0
ct_extra_eps: .zero 128 * 8
ct_rows: .zero 128 * ECSR_SIZE
ct_tuple: .zero 64
ct_epochs: .zero 40
.section .rodata
ct_source_a: .ascii "[fixture/example]\nsetting.text=snow 雪 = still\n[providers]\nformat.py=old/tool\nformat.py=bad\nformat.*=wild/tool\nsymbols.*=other/tool\nsignature.lang=missing/tool\nrename.py=tool/rename\ncomplete.py=unknown/preserved\n[absent/tool]\nsetting.opaque=keep\n"
ct_source_b: .ascii "[providers]\nrename.py=tool/rename\nsignature.lang=missing/tool\nsymbols.*=other/tool\nformat.*=wild/tool\nformat.py=old/tool\n[fixture/example]\nsetting.text=bad\n[absent/tool]\nsetting.opaque=keep\n"
ct_source_c: .ascii "[fixture/example]\nsetting.text=bad\n[providers]\nformat.py=old/tool\nformat.*=wild/tool\nsymbols.*=other/tool\nsignature.lang=next/tool\nrename.py=tool/rename\n[absent/tool]\nsetting.opaque=keep\n"
ct_format_py: .asciz "py"
ct_owner_old: .asciz "old/tool"
ct_owner_new: .asciz "new/tool"
ct_owner_next: .asciz "next/tool"
ct_language: .asciz "lang"
ct_provider_section: .ascii "providers"
ct_provider_key: .ascii "format.py"
ct_ok: .ascii "ok whole sparse settings models and provider publication\n"
.equ CT_OK_LEN, 57
.text
# Counted public request. Names are caller-owned only for this synchronous call.
ct_prepare:
    PROLOGUE ECSCP_SIZE
    mov [rsp + ECSCP_source], rdi
    mov [rsp + ECSCP_rows], rsi
    mov [rsp + ECSCP_count], rdx
    mov rax, [rip + esv_registry_epoch]
    mov [rsp + ECSCP_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [rsp + ECSCP_model], rax
    mov rax, [rip + esv_service_queue]
    mov rax, [rax + EQ_epoch]
    mov [rsp + ECSCP_dirty], rax
    mov rdi, rsp
    call ext_settings_catalog_prepare
    EPILOGUE
# A one-row complete intended set, including sparse historical slot127/64.
ct_one_row:
    lea rax, [rip + ct_rows]
    mov [rax + ECSR_view], rdi
    mov [rax + ECSR_slot], rsi
    lea rcx, [rip + vt_owner]
    mov [rax + ECSR_owner], rcx
    lea rcx, [rip + vt_name]
    mov [rax + ECSR_name], rcx
    ret
ct_build_plan:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 4000000
1:  mov rdi, rbx
    mov rsi, r12
    call ext_settings_catalog_step
    cmp rdx, r12
    ja vt_fail
    cmp rcx, 1024
    ja vt_fail
    cmp r8, 64
    ja vt_fail
    test rax, rax
    js vt_fail
    cmp rax, 1
    je 2f
    or rdx, rcx
    or rdx, r8
    jz vt_fail
    dec r13
    jnz 1b
    jmp vt_fail
2:  mov rdi, rbx
    call ext_settings_catalog_check
    test rax, rax
    jnz vt_fail
    mov rax, rbx
    EPILOGUE
# Publish after all preflight. Return independently owned new model and old caller ref.
ct_activate:
    PROLOGUE
    mov rbx, rdi
    call ext_settings_catalog_model
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov rdi, rbx
    call ext_settings_catalog_check
    test rax, rax
    jnz vt_fail
    mov qword ptr [rip + ct_poison], 1
    mov rdi, rbx
    call ext_settings_catalog_publish
    mov qword ptr [rip + ct_poison], 0
    mov r13, [rip + ct_live_owner]
    mov [rip + ct_live_owner], r12
    mov rdi, rbx
    call ext_settings_catalog_check
    cmp rax, -114
    jne vt_fail
    mov rdi, rbx
    call ext_settings_catalog_model
    test rax, rax
    jnz vt_fail
    cmp rdx, -114
    jne vt_fail
    mov rdi, rbx
    call ext_settings_catalog_release
    test rax, rax
    jnz vt_fail
    mov rax, r12
    mov rdx, r13
    EPILOGUE
# Verify exact retained provider tuple without depending on vector insertion order.
ct_provider:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call ext_settings_model_providers
    test rax, rax
    jz vt_fail
    mov r15, rax
    mov rbx, rdx
1:  test rbx, rbx
    jz vt_fail
    dec rbx
    cmp [r15 + PBR_kind], r12
    jne 2f
    mov rdi, [r15 + PBR_language]
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 2f
    mov rdi, [r15 + PBR_owner]
    test rdi, rdi
    jz vt_fail
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jz vt_fail
    EPILOGUE
2:  add r15, PBR_SIZE
    jmp 1b
ct_put_provider:
    PROLOGUE EC_SIZE
    lea rax, [rip + ct_provider_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 9
    lea rax, [rip + ct_provider_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 9
    lea rax, [rip + ct_owner_new]
    mov [rsp + EC_value], rax
    mov qword ptr [rsp + EC_vallen], 8
    mov qword ptr [rsp + EC_remove], 0
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    call ext_settings_provider_changed
    test rax, rax
    jnz vt_fail
    EPILOGUE
# Fixture pump keeps each collector's one-unit contract and the EO/ESM census.
ct_gc:
    PROLOGUE 32
    mov r12d, 10000
1:  mov edi, 1
    call ext_settings_catalog_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_fail
    mov edi, 1
    call ext_settings_model_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_fail
    mov edi, 1
    call ext_settings_view_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_fail
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    ja vt_fail
    test rdx, rdx
    js vt_fail
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    test rax, rax
    js vt_fail
    cmp qword ptr [rsp + 16], 0
    jne vt_fail
    dec r12
    jnz 1b
    call ext_settings_catalog_pending
    test rax, rax
    jnz vt_fail
    call ext_settings_model_pending
    test rax, rax
    jnz vt_fail
    call ext_settings_view_pending
    test rax, rax
    jnz vt_fail
    EPILOGUE
FN main
    PROLOGUE 32
    mov r15, [rip + g_mem_live]
    mov qword ptr [rip + vt_stage], 130
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
    mov [rip + ct_schema_b], rax
    lea rdi, [rip + ct_source_a]
    mov esi, CT_SOURCE_A_LEN
    call vt_snapshot
    mov [rip + vt_source], rax
    mov rdi, [rip + vt_schema_a]
    mov rsi, rax
    mov edx, 1
    call vt_build
    mov [rip + vt_view], rax
    mov rdi, rax
    mov esi, 127
    call ct_one_row
    call ct_constructor_cases
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov qword ptr [rip + vt_stage], 131
    mov rdi, rax
    mov esi, 1
    call ct_build_plan
    mov rdi, rbx
    lea rsi, [rip + ct_tuple]
    call ext_settings_catalog_context
    test rax, rax
    jnz vt_fail
    cmp qword ptr [rip + ct_tuple + 40], 2
    jne vt_fail
    cmp qword ptr [rip + ct_tuple + 48], 2
    jne vt_fail
    cmp qword ptr [rip + ct_tuple + 56], 2
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    test rdx, rdx
    jnz vt_fail
    mov rdi, rax
    mov esi, 6
    lea rdx, [rip + ct_format_py]
    lea rcx, [rip + ct_owner_old]
    call ct_provider
    mov rdi, [rip + vt_view]
    call ext_settings_view_check
    cmp rax, -116
    jne vt_fail
    mov rdi, [rip + vt_view]
    xor esi, esi
    lea rdx, [rip + vt_text]
    call vt_value
    mov rdi, [rip + vt_view]
    call ext_settings_view_release
    mov rdi, [rip + vt_schema_a]
    call ext_prepare_release_deferred
    mov qword ptr [rip + vt_schema_a], 0
    mov rdi, [rip + vt_source]
    call ext_settings_snapshot_release
    mov qword ptr [rip + vt_source], 0
    call ct_gc
    # A different schema gets a fresh sparse slot; the old owned model remains readable.
    mov qword ptr [rip + vt_stage], 132
    lea rdi, [rip + ct_source_b]
    mov esi, CT_SOURCE_B_LEN
    call vt_snapshot
    mov [rip + ct_source_b_ref], rax
    mov rdi, [rip + ct_schema_b]
    mov rsi, rax
    mov edx, 7
    call vt_build
    mov r12, rax
    mov rdi, rax
    mov esi, 64
    call ct_one_row
    mov rdi, [rip + ct_source_b_ref]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    cmp qword ptr [rbx + CP_newprovider], 2
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    mov r13, rdx
    call ct_gc
    mov rdi, r13
    mov esi, 127
    call ext_settings_model_view
    test rax, rax
    jz vt_fail
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + vt_text]
    call vt_value
    mov rdi, r13
    call ext_settings_model_release
    mov rdi, r12
    xor esi, esi
    lea rdx, [rip + vt_20]
    call vt_value
    mov rdi, r12
    call ext_settings_view_release
    # Accepted local provider choice counts once, not again when its model is installed.
    mov qword ptr [rip + vt_stage], 133
    call ct_put_provider
    cmp qword ptr [rip + esv_provider_epoch], 3
    jne vt_fail
    mov rdi, [rip + ct_schema_b]
    mov rsi, [rip + ct_source_b_ref]
    mov edx, 7
    call vt_build
    mov r12, rax
    mov rdi, rax
    mov esi, 64
    call ct_one_row
    mov rdi, [rip + ct_source_b_ref]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    cmp qword ptr [rbx + CP_newprovider], 3
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rdi, [rip + ct_live_owner]
    mov esi, 6
    lea rdx, [rip + ct_format_py]
    lea rcx, [rip + ct_owner_new]
    call ct_provider
    mov rdi, r12
    call ext_settings_view_release
    # Fresh unrelated external provider data changes the epoch while preserving local intent.
    mov qword ptr [rip + vt_stage], 134
    lea rdi, [rip + ct_source_c]
    mov esi, CT_SOURCE_C_LEN
    call vt_snapshot
    mov [rip + ct_source_c_ref], rax
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 65536
    call ct_build_plan
    cmp qword ptr [rbx + CP_newprovider], 4
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rdi, [rip + ct_live_owner]
    mov esi, 6
    lea rdx, [rip + ct_format_py]
    lea rcx, [rip + ct_owner_new]
    call ct_provider
    mov rdi, [rip + ct_live_owner]
    mov esi, 7
    lea rdx, [rip + ct_language]
    lea rcx, [rip + ct_owner_next]
    call ct_provider
    mov rdi, [rip + ct_live_owner]
    mov esi, 64
    call ext_settings_model_view
    test rax, rax
    jnz vt_fail
    test rdx, rdx
    jnz vt_fail
    call ct_provider_cases
    call ct_stale_cases
    call ct_capacity_cases
    call ct_full128
.ifdef VT_FAULTS
    call ct_native_failure
.endif
    # Model/plan/metadata disposal is independent from original caller input arrays.
    mov qword ptr [rip + vt_stage], 135
    mov rdi, [rip + esv_live_model]
    mov qword ptr [rip + esv_live_model], 0
    call ext_settings_model_release
    mov rdi, [rip + ct_live_owner]
    call ext_settings_model_release
    mov rdi, [rip + ct_schema_b]
    call ext_prepare_release_deferred
    mov rdi, [rip + ct_source_b_ref]
    call ext_settings_snapshot_release
    mov rdi, [rip + ct_source_c_ref]
    call ext_settings_snapshot_release
    call ct_gc
    call vt_queue_clear
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_free
    test rax, rax
    jnz vt_fail
    mov qword ptr [rip + esv_service_queue], 0
 .ifdef VT_FAULTS
    mov qword ptr [rip + vt_stage], 150
    mov qword ptr [rsp], 0
    mov [rsp + 8], r15
    mov edi, PB_SIZE + 16
    call prep_alloc_charge
    mov [rsp + 16], rax
    mov rdi, rsp
    call vt_retained_check
.endif
    call ext_settings_memory_total
    test rax, rax
    jnz vt_fail
    cmp [rip + g_mem_live], r15
    jne vt_fail
    mov edi, 1
    lea rsi, [rip + ct_ok]
    mov edx, CT_OK_LEN
    call write_all
    xor eax, eax
    EPILOGUE

.section .rodata
ct_short_owner: .asciz "fixtur"
.text
ct_empty_plan:
    xor esi, esi
    xor edx, edx
    jmp ct_prepare
ct_named_schema:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, -1
    lea rsi, [rip + vt_dir]
    mov rdx, r12
    mov rcx, r13
    call ext_prepare_alloc
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + vt_schema1]
    mov edx, VT_SCHEMA1_LEN
    call ext_manifest_parse_owned
    test rax, rax
    jnz vt_fail
    mov rdi, rbx
    call ext_prepare_defaults
    test rax, rax
    jnz vt_fail
    mov qword ptr [rbx + PO_ready], 1
    mov rax, rbx
    EPILOGUE
ct_long_identity_cases:
    PROLOGUE 224
    mov qword ptr [rip + vt_stage], 145
    # Real package identities are limited to100 bytes each. At128 rows the
    # synchronous constructor compares at most25856 bytes, below its64KiB cap.
    mov rdi, rsp
    mov esi, 'a'
    mov edx, 100
    call memset
    mov byte ptr [rsp + 100], 0
    lea rdi, [rsp + 112]
    mov esi, 'b'
    mov edx, 100
    call memset
    mov byte ptr [rsp + 212], 0
    mov rdi, rsp
    lea rsi, [rsp + 112]
    call ct_named_schema
    mov r12, rax
    mov rdi, rax
    mov rsi, [rip + vt_source]
    mov edx, 7
    call vt_build
    mov r13, rax
    xor ecx, ecx
1:  imul rax, rcx, ECSR_SIZE
    lea rdx, [rip + ct_rows]
    add rdx, rax
    mov [rdx + ECSR_view], r13
    mov [rdx + ECSR_slot], rcx
    mov [rdx + ECSR_owner], rsp
    lea rax, [rsp + 112]
    mov [rdx + ECSR_name], rax
    inc rcx
    cmp rcx, 128
    jb 1b
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 128
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    # No caller identity bytes survive constructor return.
    mov rdi, rsp
    xor esi, esi
    mov edx, 224
    call memset
    mov rdi, rbx
    mov rsi, -22
    call ct_plan_error
    mov rdi, r13
    call ext_settings_view_release
    mov rdi, r12
    call ext_prepare_release_deferred
    call ct_gc
    mov rdi, [rip + vt_view]
    mov esi, 127
    call ct_one_row
    EPILOGUE
ct_name:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rdi], 0x6c6f6f74
    add rdi, 4
    call fmt_u64
    mov byte ptr [rdi], 0
    mov rax, rbx
    EPILOGUE
ct_full128:
    PROLOGUE 64
    mov qword ptr [rip + vt_stage], 144
    xor r14d, r14d
1:  lea rdi, [rsp + 32]
    mov rsi, r14
    call ct_name
    mov rsi, rax
    lea rdi, [rip + vt_owner]
    call ct_named_schema
    mov r12, rax
    lea rcx, [rip + ct_extra_eps]
    mov [rcx + r14 * 8], rax
    mov rdi, rax
    mov rsi, [rip + ct_source_c_ref]
    mov edx, 65536
    call vt_build
    imul rcx, r14, ECSR_SIZE
    lea r13, [rip + ct_rows]
    add r13, rcx
    mov [r13 + ECSR_view], rax
    mov eax, 127
    sub rax, r14
    mov [r13 + ECSR_slot], rax
    mov rax, [r12 + EP_ext + EXT_owner]
    mov [r13 + ECSR_owner], rax
    mov rax, [r12 + EP_ext + EXT_name]
    mov [r13 + ECSR_name], rax
    inc r14
    cmp r14, 128
    jb 1b
    mov rdi, [rip + ct_source_c_ref]
    lea rsi, [rip + ct_rows]
    mov edx, 128
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    # Producer rows, name pointers, view refs and EP refs may all be discarded now.
    xor r14d, r14d
2:  imul rcx, r14, ECSR_SIZE
    lea rax, [rip + ct_rows]
    mov rdi, [rax + rcx + ECSR_view]
    call ext_settings_view_release
    lea rax, [rip + ct_extra_eps]
    mov rdi, [rax + r14 * 8]
    mov qword ptr [rax + r14 * 8], 0
    call ext_prepare_release_deferred
    inc r14
    cmp r14, 128
    jb 2b
    lea rdi, [rip + ct_rows]
    xor esi, esi
    mov edx, 128 * ECSR_SIZE
    call memset
    mov rdi, rbx
    mov esi, 65536
    call ct_build_plan
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    call ct_gc
    xor r14d, r14d
3:  mov rdi, [rip + ct_live_owner]
    mov rsi, r14
    call ext_settings_model_view
    test rax, rax
    jz vt_fail
    mov r12, rax
    mov rdi, rax
    mov esi, 2
    lea rdx, [rip + vt_five]
    call vt_value
    lea rdi, [rsp + 32]
    mov esi, 127
    sub rsi, r14
    call ct_name
    mov rsi, rax
    mov rdi, [r12 + EV_ep]
    mov rdi, [rdi + EP_ext + EXT_name]
    call strcmp_eq
    test eax, eax
    jz vt_fail
    inc r14
    cmp r14, 128
    jb 3b
    EPILOGUE
ct_provider_cases:
    PROLOGUE EC_SIZE
    mov qword ptr [rip + vt_stage], 138
    lea rax, [rip + ct_provider_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 9
    lea rax, [rip + ct_provider_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 9
    mov qword ptr [rsp + EC_value], 0
    mov qword ptr [rsp + EC_vallen], 0
    mov qword ptr [rsp + EC_remove], 1
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    call ext_settings_provider_changed
    test rax, rax
    jnz vt_fail
    mov r13, [rip + esv_provider_epoch]
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    cmp [rbx + CP_newprovider], r13
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    mov rdi, [rip + ct_live_owner]
    call ext_settings_model_providers
    cmp rdx, 5
    jne vt_fail
    mov r12, rax
    mov r13, rdx
1:  cmp qword ptr [r12 + PBR_kind], 6
    jne 2f
    mov rdi, [r12 + PBR_language]
    lea rsi, [rip + ct_format_py]
    call strcmp_eq
    test eax, eax
    jz 2f
    cmp qword ptr [r12 + PBR_owner], 0
    jne vt_fail
    jmp 3f
2:  add r12, PBR_SIZE
    dec r13
    jnz 1b
    jmp vt_fail
3:  # Bad known dirty owner refuses preparation and remains queued.
    lea rax, [rip + vt_bad]
    mov [rsp + EC_value], rax
    mov qword ptr [rsp + EC_vallen], 3
    mov qword ptr [rsp + EC_remove], 0
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rdi, rax
    mov rsi, -22
    call ct_plan_error
    mov rax, [rip + vt_queue]
    cmp qword ptr [rax + EQ_count], 1
    jne vt_fail
    call vt_queue_clear
    call ct_gc
    # A real provider-map difference cannot wrap the provider epoch.
    mov qword ptr [rip + vt_stage], 139
    mov r12, [rip + esv_provider_epoch]
    mov rax, 0x7fffffffffffffff
    mov [rip + esv_provider_epoch], rax
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rdi, rax
    mov rsi, -75
    call ct_plan_error
    mov rax, 0x7fffffffffffffff
    cmp [rip + esv_provider_epoch], rax
    jne vt_fail
    mov [rip + esv_provider_epoch], r12
    call ct_gc
    EPILOGUE
ct_stale_cases:
    PROLOGUE EC_SIZE
    mov qword ptr [rip + vt_stage], 140
    xor r14d, r14d
1:  mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call ext_settings_catalog_step
    test rax, rax
    jnz vt_fail
    lea r12, [rip + esv_cfg_context]
    cmp r14, 0
    je 2f
    lea r12, [rip + esv_registry_epoch]
    cmp r14, 1
    je 2f
    lea r12, [rip + esv_model_epoch]
    cmp r14, 2
    je 2f
    lea r12, [rip + esv_provider_epoch]
    cmp r14, 3
    je 2f
    mov r12, [rip + vt_queue]
    add r12, EQ_epoch
2:  inc qword ptr [r12]
    mov rdi, rbx
    mov esi, 65536
    call ext_settings_catalog_step
    cmp rax, -116
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    dec qword ptr [r12]
    mov rdi, rbx
    call ext_settings_catalog_release
    inc r14
    cmp r14, 5
    jb 1b
    call ct_gc
    # Retire the actual dirty cell while the builder is paused inside its bytes.
    call ct_put_provider
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov r14d, 4000000
3:  mov rdi, rbx
    mov esi, 1
    call ext_settings_catalog_step
    test rax, rax
    jnz vt_fail
    cmp qword ptr [rbx + CP_phase], CPP_PROVIDERS
    jne 4f
    cmp qword ptr [rbx + CP_ppphase], PPS_LANGUAGE
    jne 4f
    test qword ptr [rbx + CP_workflags], PPF_DIRTY
    jnz 5f
4:  dec r14
    jnz 3b
    jmp vt_fail
5:  lea rax, [rip + ct_provider_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 9
    lea rax, [rip + ct_provider_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 9
    lea rax, [rip + ct_owner_new]
    mov [rsp + EC_value], rax
    mov qword ptr [rsp + EC_vallen], 8
    mov qword ptr [rsp + EC_remove], 0
    mov rdi, [rip + vt_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz vt_fail
    mov rdi, [rip + vt_queue]
    call ext_settings_queue_gc
    test rdx, rdx
    js vt_fail
    mov rdi, rbx
    mov esi, 65536
    call ext_settings_catalog_step
    cmp rax, -116
    jne vt_fail
    or rdx, rcx
    or rdx, r8
    jnz vt_fail
    mov rdi, rbx
    call ext_settings_catalog_release
    call vt_queue_clear
    call ct_gc
    EPILOGUE
ct_capacity_cases:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 141
    lea rdi, [rip + ct_capacity_512]
    mov esi, CT_CAPACITY_512_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, rax
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    mov rdi, rbx
    call ext_settings_catalog_model
    test rax, rax
    jz vt_fail
    mov r13, rax
    mov rdi, rax
    call ext_settings_model_providers
    cmp rdx, 512
    jne vt_fail
    mov rdi, r13
    call ext_settings_model_release
    mov rdi, rbx
    call ext_settings_catalog_release
    mov rdi, r12
    call ext_settings_snapshot_release
    call ct_gc
    mov qword ptr [rip + vt_stage], 142
    lea rdi, [rip + ct_capacity_513]
    mov esi, CT_CAPACITY_513_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, rax
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rdi, rax
    mov rsi, -7
    call ct_plan_error
    mov rdi, r12
    call ext_settings_snapshot_release
    call ct_gc
    EPILOGUE
.ifdef VT_FAULTS
ct_native_failure:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 143
    mov qword ptr [rip + vt_now], 1000
    mov rdi, [rip + ct_source_c_ref]
    call ct_empty_plan
    test rax, rax
    jz vt_fail
    mov rbx, rax
    mov qword ptr [rip + vt_fail_unmap], 1
    mov rdi, rax
    mov esi, 7
    call ct_build_plan
    cmp qword ptr [rbx + CP_cleanup], 0
    jge vt_fail
    cmp qword ptr [rip + vt_fail_unmap], 0
    jne vt_fail
    call ext_settings_memory_pending
    cmp rax, 1
    jne vt_fail
    mov rdi, rbx
    call ct_activate
    mov rdi, rdx
    call ext_settings_model_release
    call ct_gc
    EPILOGUE
.endif
ct_refusal:
    PROLOGUE
    mov r12, rcx
    call ct_prepare
    test rax, rax
    jnz vt_fail
    cmp rdx, r12
    jne vt_fail
    EPILOGUE
ct_plan_error:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 1000000
1:  mov rdi, rbx
    mov esi, 7
    call ext_settings_catalog_step
    test rax, rax
    jnz 2f
    dec r13
    jnz 1b
    jmp vt_fail
2:  cmp rax, r12
    jne vt_fail
    mov rdi, rbx
    call ext_settings_catalog_release
    test rax, rax
    jnz vt_fail
    EPILOGUE
ct_constructor_cases:
    PROLOGUE
    mov qword ptr [rip + vt_stage], 136
    xor edi, edi
    xor esi, esi
    xor edx, edx
    mov rcx, -11
    call ct_refusal
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 129
    mov rcx, -22
    call ct_refusal
    mov rdi, [rip + vt_source]
    xor esi, esi
    mov edx, 1
    mov rcx, -22
    call ct_refusal
    mov qword ptr [rip + ct_rows + ECSR_slot], 128
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -22
    call ct_refusal
    mov qword ptr [rip + ct_rows + ECSR_slot], 127
    lea rax, [rip + ct_short_owner]
    mov [rip + ct_rows + ECSR_owner], rax
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -22
    call ct_refusal
    mov rdi, [rip + vt_view]
    mov esi, 127
    call ct_one_row
    lea rdi, [rip + ct_rows + ECSR_SIZE]
    lea rsi, [rip + ct_rows]
    mov edx, ECSR_SIZE
    call memcpy
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 2
    mov rcx, -22
    call ct_refusal
    # Same identity in two different historical slots rejects during bounded hashing.
    mov qword ptr [rip + ct_rows + ECSR_SIZE + ECSR_slot], 0
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 2
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rdi, rax
    mov rsi, -22
    call ct_plan_error
    # Byte-identical source data cannot substitute for the required shared ESB object.
    lea rdi, [rip + ct_source_a]
    mov esi, CT_SOURCE_A_LEN
    call vt_snapshot
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -116
    call ct_refusal
    mov rdi, r12
    call ext_settings_snapshot_release
    call ct_gc
    mov qword ptr [rip + vt_stage], 137
    mov r12, [rip + vt_view]
    mov r13, [r12 + EV_refs]
    mov rax, 0x7fffffffffffffff
    mov [r12 + EV_refs], rax
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -75
    call ct_refusal
    mov [r12 + EV_refs], r13
    mov rax, 0x7fffffffffffffff
    mov r12, [rip + esv_registry_epoch]
    mov [rip + esv_registry_epoch], rax
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -75
    call ct_refusal
    mov [rip + esv_registry_epoch], r12
    mov rax, 0x7fffffffffffffff
    mov r12, [rip + esv_model_epoch]
    mov [rip + esv_model_epoch], rax
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -75
    call ct_refusal
    mov [rip + esv_model_epoch], r12
    call ext_settings_memory_total
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz vt_fail
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    mov rcx, -12
    call ct_refusal
    mov rdi, r14
    call ext_settings_memory_release
    mov rdi, [rip + vt_source]
    lea rsi, [rip + ct_rows]
    mov edx, 1
    call ct_prepare
    test rax, rax
    jz vt_fail
    mov rbx, rax
    call ext_settings_memory_total
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz vt_fail
    mov rdi, rbx
    mov esi, 7
    call ext_settings_catalog_step
    cmp rax, -12
    jne vt_fail
    cmp r8, 1
    jne vt_fail
    mov rdi, r14
    call ext_settings_memory_release
    mov rdi, rbx
    call ext_settings_catalog_release
    call ct_gc
    call ct_long_identity_cases
    EPILOGUE

.section .rodata
ct_capacity_512: .ascii "[providers]\nformat.k000=x/y\nformat.k001=x/y\nformat.k002=x/y\nformat.k003=x/y\nformat.k004=x/y\nformat.k005=x/y\nformat.k006=x/y\nformat.k007=x/y\nformat.k008=x/y\nformat.k009=x/y\nformat.k010=x/y\nformat.k011=x/y\nformat.k012=x/y\nformat.k013=x/y\nformat.k014=x/y\nformat.k015=x/y\nformat.k016=x/y\nformat.k017=x/y\nformat.k018=x/y\nformat.k019=x/y\nformat.k020=x/y\nformat.k021=x/y\nformat.k022=x/y\nformat.k023=x/y\nformat.k024=x/y\nformat.k025=x/y\nformat.k026=x/y\nformat.k027=x/y\nformat.k028=x/y\nformat.k029=x/y\nformat.k030=x/y\nformat.k031=x/y\nformat.k032=x/y\nformat.k033=x/y\nformat.k034=x/y\nformat.k035=x/y\nformat.k036=x/y\nformat.k037=x/y\nformat.k038=x/y\nformat.k039=x/y\nformat.k040=x/y\nformat.k041=x/y\nformat.k042=x/y\nformat.k043=x/y\nformat.k044=x/y\nformat.k045=x/y\nformat.k046=x/y\nformat.k047=x/y\nformat.k048=x/y\nformat.k049=x/y\nformat.k050=x/y\nformat.k051=x/y\nformat.k052=x/y\nformat.k053=x/y\nformat.k054=x/y\nformat.k055=x/y\nformat.k056=x/y\nformat.k057=x/y\nformat.k058=x/y\nformat.k059=x/y\nformat.k060=x/y\nformat.k061=x/y\nformat.k062=x/y\nformat.k063=x/y\nformat.k064=x/y\nformat.k065=x/y\nformat.k066=x/y\nformat.k067=x/y\nformat.k068=x/y\nformat.k069=x/y\nformat.k070=x/y\nformat.k071=x/y\nformat.k072=x/y\nformat.k073=x/y\nformat.k074=x/y\nformat.k075=x/y\nformat.k076=x/y\nformat.k077=x/y\nformat.k078=x/y\nformat.k079=x/y\nformat.k080=x/y\nformat.k081=x/y\nformat.k082=x/y\nformat.k083=x/y\nformat.k084=x/y\nformat.k085=x/y\nformat.k086=x/y\nformat.k087=x/y\nformat.k088=x/y\nformat.k089=x/y\nformat.k090=x/y\nformat.k091=x/y\nformat.k092=x/y\nformat.k093=x/y\nformat.k094=x/y\nformat.k095=x/y\nformat.k096=x/y\nformat.k097=x/y\nformat.k098=x/y\nformat.k099=x/y\nformat.k100=x/y\nformat.k101=x/y\nformat.k102=x/y\nformat.k103=x/y\nformat.k104=x/y\nformat.k105=x/y\nformat.k106=x/y\nformat.k107=x/y\nformat.k108=x/y\nformat.k109=x/y\nformat.k110=x/y\nformat.k111=x/y\nformat.k112=x/y\nformat.k113=x/y\nformat.k114=x/y\nformat.k115=x/y\nformat.k116=x/y\nformat.k117=x/y\nformat.k118=x/y\nformat.k119=x/y\nformat.k120=x/y\nformat.k121=x/y\nformat.k122=x/y\nformat.k123=x/y\nformat.k124=x/y\nformat.k125=x/y\nformat.k126=x/y\nformat.k127=x/y\nformat.k128=x/y\nformat.k129=x/y\nformat.k130=x/y\nformat.k131=x/y\nformat.k132=x/y\nformat.k133=x/y\nformat.k134=x/y\nformat.k135=x/y\nformat.k136=x/y\nformat.k137=x/y\nformat.k138=x/y\nformat.k139=x/y\nformat.k140=x/y\nformat.k141=x/y\nformat.k142=x/y\nformat.k143=x/y\nformat.k144=x/y\nformat.k145=x/y\nformat.k146=x/y\nformat.k147=x/y\nformat.k148=x/y\nformat.k149=x/y\nformat.k150=x/y\nformat.k151=x/y\nformat.k152=x/y\nformat.k153=x/y\nformat.k154=x/y\nformat.k155=x/y\nformat.k156=x/y\nformat.k157=x/y\nformat.k158=x/y\nformat.k159=x/y\nformat.k160=x/y\nformat.k161=x/y\nformat.k162=x/y\nformat.k163=x/y\nformat.k164=x/y\nformat.k165=x/y\nformat.k166=x/y\nformat.k167=x/y\nformat.k168=x/y\nformat.k169=x/y\nformat.k170=x/y\nformat.k171=x/y\nformat.k172=x/y\nformat.k173=x/y\nformat.k174=x/y\nformat.k175=x/y\nformat.k176=x/y\nformat.k177=x/y\nformat.k178=x/y\nformat.k179=x/y\nformat.k180=x/y\nformat.k181=x/y\nformat.k182=x/y\nformat.k183=x/y\nformat.k184=x/y\nformat.k185=x/y\nformat.k186=x/y\nformat.k187=x/y\nformat.k188=x/y\nformat.k189=x/y\nformat.k190=x/y\nformat.k191=x/y\nformat.k192=x/y\nformat.k193=x/y\nformat.k194=x/y\nformat.k195=x/y\nformat.k196=x/y\nformat.k197=x/y\nformat.k198=x/y\nformat.k199=x/y\nformat.k200=x/y\nformat.k201=x/y\nformat.k202=x/y\nformat.k203=x/y\nformat.k204=x/y\nformat.k205=x/y\nformat.k206=x/y\nformat.k207=x/y\nformat.k208=x/y\nformat.k209=x/y\nformat.k210=x/y\nformat.k211=x/y\nformat.k212=x/y\nformat.k213=x/y\nformat.k214=x/y\nformat.k215=x/y\nformat.k216=x/y\nformat.k217=x/y\nformat.k218=x/y\nformat.k219=x/y\nformat.k220=x/y\nformat.k221=x/y\nformat.k222=x/y\nformat.k223=x/y\nformat.k224=x/y\nformat.k225=x/y\nformat.k226=x/y\nformat.k227=x/y\nformat.k228=x/y\nformat.k229=x/y\nformat.k230=x/y\nformat.k231=x/y\nformat.k232=x/y\nformat.k233=x/y\nformat.k234=x/y\nformat.k235=x/y\nformat.k236=x/y\nformat.k237=x/y\nformat.k238=x/y\nformat.k239=x/y\nformat.k240=x/y\nformat.k241=x/y\nformat.k242=x/y\nformat.k243=x/y\nformat.k244=x/y\nformat.k245=x/y\nformat.k246=x/y\nformat.k247=x/y\nformat.k248=x/y\nformat.k249=x/y\nformat.k250=x/y\nformat.k251=x/y\nformat.k252=x/y\nformat.k253=x/y\nformat.k254=x/y\nformat.k255=x/y\nformat.k256=x/y\nformat.k257=x/y\nformat.k258=x/y\nformat.k259=x/y\nformat.k260=x/y\nformat.k261=x/y\nformat.k262=x/y\nformat.k263=x/y\nformat.k264=x/y\nformat.k265=x/y\nformat.k266=x/y\nformat.k267=x/y\nformat.k268=x/y\nformat.k269=x/y\nformat.k270=x/y\nformat.k271=x/y\nformat.k272=x/y\nformat.k273=x/y\nformat.k274=x/y\nformat.k275=x/y\nformat.k276=x/y\nformat.k277=x/y\nformat.k278=x/y\nformat.k279=x/y\nformat.k280=x/y\nformat.k281=x/y\nformat.k282=x/y\nformat.k283=x/y\nformat.k284=x/y\nformat.k285=x/y\nformat.k286=x/y\nformat.k287=x/y\nformat.k288=x/y\nformat.k289=x/y\nformat.k290=x/y\nformat.k291=x/y\nformat.k292=x/y\nformat.k293=x/y\nformat.k294=x/y\nformat.k295=x/y\nformat.k296=x/y\nformat.k297=x/y\nformat.k298=x/y\nformat.k299=x/y\nformat.k300=x/y\nformat.k301=x/y\nformat.k302=x/y\nformat.k303=x/y\nformat.k304=x/y\nformat.k305=x/y\nformat.k306=x/y\nformat.k307=x/y\nformat.k308=x/y\nformat.k309=x/y\nformat.k310=x/y\nformat.k311=x/y\nformat.k312=x/y\nformat.k313=x/y\nformat.k314=x/y\nformat.k315=x/y\nformat.k316=x/y\nformat.k317=x/y\nformat.k318=x/y\nformat.k319=x/y\nformat.k320=x/y\nformat.k321=x/y\nformat.k322=x/y\nformat.k323=x/y\nformat.k324=x/y\nformat.k325=x/y\nformat.k326=x/y\nformat.k327=x/y\nformat.k328=x/y\nformat.k329=x/y\nformat.k330=x/y\nformat.k331=x/y\nformat.k332=x/y\nformat.k333=x/y\nformat.k334=x/y\nformat.k335=x/y\nformat.k336=x/y\nformat.k337=x/y\nformat.k338=x/y\nformat.k339=x/y\nformat.k340=x/y\nformat.k341=x/y\nformat.k342=x/y\nformat.k343=x/y\nformat.k344=x/y\nformat.k345=x/y\nformat.k346=x/y\nformat.k347=x/y\nformat.k348=x/y\nformat.k349=x/y\nformat.k350=x/y\nformat.k351=x/y\nformat.k352=x/y\nformat.k353=x/y\nformat.k354=x/y\nformat.k355=x/y\nformat.k356=x/y\nformat.k357=x/y\nformat.k358=x/y\nformat.k359=x/y\nformat.k360=x/y\nformat.k361=x/y\nformat.k362=x/y\nformat.k363=x/y\nformat.k364=x/y\nformat.k365=x/y\nformat.k366=x/y\nformat.k367=x/y\nformat.k368=x/y\nformat.k369=x/y\nformat.k370=x/y\nformat.k371=x/y\nformat.k372=x/y\nformat.k373=x/y\nformat.k374=x/y\nformat.k375=x/y\nformat.k376=x/y\nformat.k377=x/y\nformat.k378=x/y\nformat.k379=x/y\nformat.k380=x/y\nformat.k381=x/y\nformat.k382=x/y\nformat.k383=x/y\nformat.k384=x/y\nformat.k385=x/y\nformat.k386=x/y\nformat.k387=x/y\nformat.k388=x/y\nformat.k389=x/y\nformat.k390=x/y\nformat.k391=x/y\nformat.k392=x/y\nformat.k393=x/y\nformat.k394=x/y\nformat.k395=x/y\nformat.k396=x/y\nformat.k397=x/y\nformat.k398=x/y\nformat.k399=x/y\nformat.k400=x/y\nformat.k401=x/y\nformat.k402=x/y\nformat.k403=x/y\nformat.k404=x/y\nformat.k405=x/y\nformat.k406=x/y\nformat.k407=x/y\nformat.k408=x/y\nformat.k409=x/y\nformat.k410=x/y\nformat.k411=x/y\nformat.k412=x/y\nformat.k413=x/y\nformat.k414=x/y\nformat.k415=x/y\nformat.k416=x/y\nformat.k417=x/y\nformat.k418=x/y\nformat.k419=x/y\nformat.k420=x/y\nformat.k421=x/y\nformat.k422=x/y\nformat.k423=x/y\nformat.k424=x/y\nformat.k425=x/y\nformat.k426=x/y\nformat.k427=x/y\nformat.k428=x/y\nformat.k429=x/y\nformat.k430=x/y\nformat.k431=x/y\nformat.k432=x/y\nformat.k433=x/y\nformat.k434=x/y\nformat.k435=x/y\nformat.k436=x/y\nformat.k437=x/y\nformat.k438=x/y\nformat.k439=x/y\nformat.k440=x/y\nformat.k441=x/y\nformat.k442=x/y\nformat.k443=x/y\nformat.k444=x/y\nformat.k445=x/y\nformat.k446=x/y\nformat.k447=x/y\nformat.k448=x/y\nformat.k449=x/y\nformat.k450=x/y\nformat.k451=x/y\nformat.k452=x/y\nformat.k453=x/y\nformat.k454=x/y\nformat.k455=x/y\nformat.k456=x/y\nformat.k457=x/y\nformat.k458=x/y\nformat.k459=x/y\nformat.k460=x/y\nformat.k461=x/y\nformat.k462=x/y\nformat.k463=x/y\nformat.k464=x/y\nformat.k465=x/y\nformat.k466=x/y\nformat.k467=x/y\nformat.k468=x/y\nformat.k469=x/y\nformat.k470=x/y\nformat.k471=x/y\nformat.k472=x/y\nformat.k473=x/y\nformat.k474=x/y\nformat.k475=x/y\nformat.k476=x/y\nformat.k477=x/y\nformat.k478=x/y\nformat.k479=x/y\nformat.k480=x/y\nformat.k481=x/y\nformat.k482=x/y\nformat.k483=x/y\nformat.k484=x/y\nformat.k485=x/y\nformat.k486=x/y\nformat.k487=x/y\nformat.k488=x/y\nformat.k489=x/y\nformat.k490=x/y\nformat.k491=x/y\nformat.k492=x/y\nformat.k493=x/y\nformat.k494=x/y\nformat.k495=x/y\nformat.k496=x/y\nformat.k497=x/y\nformat.k498=x/y\nformat.k499=x/y\nformat.k500=x/y\nformat.k501=x/y\nformat.k502=x/y\nformat.k503=x/y\nformat.k504=x/y\nformat.k505=x/y\nformat.k506=x/y\nformat.k507=x/y\nformat.k508=x/y\nformat.k509=x/y\nformat.k510=x/y\nformat.k511=x/y\n"

.section .rodata
ct_capacity_513: .ascii "[providers]\nformat.k000=x/y\nformat.k001=x/y\nformat.k002=x/y\nformat.k003=x/y\nformat.k004=x/y\nformat.k005=x/y\nformat.k006=x/y\nformat.k007=x/y\nformat.k008=x/y\nformat.k009=x/y\nformat.k010=x/y\nformat.k011=x/y\nformat.k012=x/y\nformat.k013=x/y\nformat.k014=x/y\nformat.k015=x/y\nformat.k016=x/y\nformat.k017=x/y\nformat.k018=x/y\nformat.k019=x/y\nformat.k020=x/y\nformat.k021=x/y\nformat.k022=x/y\nformat.k023=x/y\nformat.k024=x/y\nformat.k025=x/y\nformat.k026=x/y\nformat.k027=x/y\nformat.k028=x/y\nformat.k029=x/y\nformat.k030=x/y\nformat.k031=x/y\nformat.k032=x/y\nformat.k033=x/y\nformat.k034=x/y\nformat.k035=x/y\nformat.k036=x/y\nformat.k037=x/y\nformat.k038=x/y\nformat.k039=x/y\nformat.k040=x/y\nformat.k041=x/y\nformat.k042=x/y\nformat.k043=x/y\nformat.k044=x/y\nformat.k045=x/y\nformat.k046=x/y\nformat.k047=x/y\nformat.k048=x/y\nformat.k049=x/y\nformat.k050=x/y\nformat.k051=x/y\nformat.k052=x/y\nformat.k053=x/y\nformat.k054=x/y\nformat.k055=x/y\nformat.k056=x/y\nformat.k057=x/y\nformat.k058=x/y\nformat.k059=x/y\nformat.k060=x/y\nformat.k061=x/y\nformat.k062=x/y\nformat.k063=x/y\nformat.k064=x/y\nformat.k065=x/y\nformat.k066=x/y\nformat.k067=x/y\nformat.k068=x/y\nformat.k069=x/y\nformat.k070=x/y\nformat.k071=x/y\nformat.k072=x/y\nformat.k073=x/y\nformat.k074=x/y\nformat.k075=x/y\nformat.k076=x/y\nformat.k077=x/y\nformat.k078=x/y\nformat.k079=x/y\nformat.k080=x/y\nformat.k081=x/y\nformat.k082=x/y\nformat.k083=x/y\nformat.k084=x/y\nformat.k085=x/y\nformat.k086=x/y\nformat.k087=x/y\nformat.k088=x/y\nformat.k089=x/y\nformat.k090=x/y\nformat.k091=x/y\nformat.k092=x/y\nformat.k093=x/y\nformat.k094=x/y\nformat.k095=x/y\nformat.k096=x/y\nformat.k097=x/y\nformat.k098=x/y\nformat.k099=x/y\nformat.k100=x/y\nformat.k101=x/y\nformat.k102=x/y\nformat.k103=x/y\nformat.k104=x/y\nformat.k105=x/y\nformat.k106=x/y\nformat.k107=x/y\nformat.k108=x/y\nformat.k109=x/y\nformat.k110=x/y\nformat.k111=x/y\nformat.k112=x/y\nformat.k113=x/y\nformat.k114=x/y\nformat.k115=x/y\nformat.k116=x/y\nformat.k117=x/y\nformat.k118=x/y\nformat.k119=x/y\nformat.k120=x/y\nformat.k121=x/y\nformat.k122=x/y\nformat.k123=x/y\nformat.k124=x/y\nformat.k125=x/y\nformat.k126=x/y\nformat.k127=x/y\nformat.k128=x/y\nformat.k129=x/y\nformat.k130=x/y\nformat.k131=x/y\nformat.k132=x/y\nformat.k133=x/y\nformat.k134=x/y\nformat.k135=x/y\nformat.k136=x/y\nformat.k137=x/y\nformat.k138=x/y\nformat.k139=x/y\nformat.k140=x/y\nformat.k141=x/y\nformat.k142=x/y\nformat.k143=x/y\nformat.k144=x/y\nformat.k145=x/y\nformat.k146=x/y\nformat.k147=x/y\nformat.k148=x/y\nformat.k149=x/y\nformat.k150=x/y\nformat.k151=x/y\nformat.k152=x/y\nformat.k153=x/y\nformat.k154=x/y\nformat.k155=x/y\nformat.k156=x/y\nformat.k157=x/y\nformat.k158=x/y\nformat.k159=x/y\nformat.k160=x/y\nformat.k161=x/y\nformat.k162=x/y\nformat.k163=x/y\nformat.k164=x/y\nformat.k165=x/y\nformat.k166=x/y\nformat.k167=x/y\nformat.k168=x/y\nformat.k169=x/y\nformat.k170=x/y\nformat.k171=x/y\nformat.k172=x/y\nformat.k173=x/y\nformat.k174=x/y\nformat.k175=x/y\nformat.k176=x/y\nformat.k177=x/y\nformat.k178=x/y\nformat.k179=x/y\nformat.k180=x/y\nformat.k181=x/y\nformat.k182=x/y\nformat.k183=x/y\nformat.k184=x/y\nformat.k185=x/y\nformat.k186=x/y\nformat.k187=x/y\nformat.k188=x/y\nformat.k189=x/y\nformat.k190=x/y\nformat.k191=x/y\nformat.k192=x/y\nformat.k193=x/y\nformat.k194=x/y\nformat.k195=x/y\nformat.k196=x/y\nformat.k197=x/y\nformat.k198=x/y\nformat.k199=x/y\nformat.k200=x/y\nformat.k201=x/y\nformat.k202=x/y\nformat.k203=x/y\nformat.k204=x/y\nformat.k205=x/y\nformat.k206=x/y\nformat.k207=x/y\nformat.k208=x/y\nformat.k209=x/y\nformat.k210=x/y\nformat.k211=x/y\nformat.k212=x/y\nformat.k213=x/y\nformat.k214=x/y\nformat.k215=x/y\nformat.k216=x/y\nformat.k217=x/y\nformat.k218=x/y\nformat.k219=x/y\nformat.k220=x/y\nformat.k221=x/y\nformat.k222=x/y\nformat.k223=x/y\nformat.k224=x/y\nformat.k225=x/y\nformat.k226=x/y\nformat.k227=x/y\nformat.k228=x/y\nformat.k229=x/y\nformat.k230=x/y\nformat.k231=x/y\nformat.k232=x/y\nformat.k233=x/y\nformat.k234=x/y\nformat.k235=x/y\nformat.k236=x/y\nformat.k237=x/y\nformat.k238=x/y\nformat.k239=x/y\nformat.k240=x/y\nformat.k241=x/y\nformat.k242=x/y\nformat.k243=x/y\nformat.k244=x/y\nformat.k245=x/y\nformat.k246=x/y\nformat.k247=x/y\nformat.k248=x/y\nformat.k249=x/y\nformat.k250=x/y\nformat.k251=x/y\nformat.k252=x/y\nformat.k253=x/y\nformat.k254=x/y\nformat.k255=x/y\nformat.k256=x/y\nformat.k257=x/y\nformat.k258=x/y\nformat.k259=x/y\nformat.k260=x/y\nformat.k261=x/y\nformat.k262=x/y\nformat.k263=x/y\nformat.k264=x/y\nformat.k265=x/y\nformat.k266=x/y\nformat.k267=x/y\nformat.k268=x/y\nformat.k269=x/y\nformat.k270=x/y\nformat.k271=x/y\nformat.k272=x/y\nformat.k273=x/y\nformat.k274=x/y\nformat.k275=x/y\nformat.k276=x/y\nformat.k277=x/y\nformat.k278=x/y\nformat.k279=x/y\nformat.k280=x/y\nformat.k281=x/y\nformat.k282=x/y\nformat.k283=x/y\nformat.k284=x/y\nformat.k285=x/y\nformat.k286=x/y\nformat.k287=x/y\nformat.k288=x/y\nformat.k289=x/y\nformat.k290=x/y\nformat.k291=x/y\nformat.k292=x/y\nformat.k293=x/y\nformat.k294=x/y\nformat.k295=x/y\nformat.k296=x/y\nformat.k297=x/y\nformat.k298=x/y\nformat.k299=x/y\nformat.k300=x/y\nformat.k301=x/y\nformat.k302=x/y\nformat.k303=x/y\nformat.k304=x/y\nformat.k305=x/y\nformat.k306=x/y\nformat.k307=x/y\nformat.k308=x/y\nformat.k309=x/y\nformat.k310=x/y\nformat.k311=x/y\nformat.k312=x/y\nformat.k313=x/y\nformat.k314=x/y\nformat.k315=x/y\nformat.k316=x/y\nformat.k317=x/y\nformat.k318=x/y\nformat.k319=x/y\nformat.k320=x/y\nformat.k321=x/y\nformat.k322=x/y\nformat.k323=x/y\nformat.k324=x/y\nformat.k325=x/y\nformat.k326=x/y\nformat.k327=x/y\nformat.k328=x/y\nformat.k329=x/y\nformat.k330=x/y\nformat.k331=x/y\nformat.k332=x/y\nformat.k333=x/y\nformat.k334=x/y\nformat.k335=x/y\nformat.k336=x/y\nformat.k337=x/y\nformat.k338=x/y\nformat.k339=x/y\nformat.k340=x/y\nformat.k341=x/y\nformat.k342=x/y\nformat.k343=x/y\nformat.k344=x/y\nformat.k345=x/y\nformat.k346=x/y\nformat.k347=x/y\nformat.k348=x/y\nformat.k349=x/y\nformat.k350=x/y\nformat.k351=x/y\nformat.k352=x/y\nformat.k353=x/y\nformat.k354=x/y\nformat.k355=x/y\nformat.k356=x/y\nformat.k357=x/y\nformat.k358=x/y\nformat.k359=x/y\nformat.k360=x/y\nformat.k361=x/y\nformat.k362=x/y\nformat.k363=x/y\nformat.k364=x/y\nformat.k365=x/y\nformat.k366=x/y\nformat.k367=x/y\nformat.k368=x/y\nformat.k369=x/y\nformat.k370=x/y\nformat.k371=x/y\nformat.k372=x/y\nformat.k373=x/y\nformat.k374=x/y\nformat.k375=x/y\nformat.k376=x/y\nformat.k377=x/y\nformat.k378=x/y\nformat.k379=x/y\nformat.k380=x/y\nformat.k381=x/y\nformat.k382=x/y\nformat.k383=x/y\nformat.k384=x/y\nformat.k385=x/y\nformat.k386=x/y\nformat.k387=x/y\nformat.k388=x/y\nformat.k389=x/y\nformat.k390=x/y\nformat.k391=x/y\nformat.k392=x/y\nformat.k393=x/y\nformat.k394=x/y\nformat.k395=x/y\nformat.k396=x/y\nformat.k397=x/y\nformat.k398=x/y\nformat.k399=x/y\nformat.k400=x/y\nformat.k401=x/y\nformat.k402=x/y\nformat.k403=x/y\nformat.k404=x/y\nformat.k405=x/y\nformat.k406=x/y\nformat.k407=x/y\nformat.k408=x/y\nformat.k409=x/y\nformat.k410=x/y\nformat.k411=x/y\nformat.k412=x/y\nformat.k413=x/y\nformat.k414=x/y\nformat.k415=x/y\nformat.k416=x/y\nformat.k417=x/y\nformat.k418=x/y\nformat.k419=x/y\nformat.k420=x/y\nformat.k421=x/y\nformat.k422=x/y\nformat.k423=x/y\nformat.k424=x/y\nformat.k425=x/y\nformat.k426=x/y\nformat.k427=x/y\nformat.k428=x/y\nformat.k429=x/y\nformat.k430=x/y\nformat.k431=x/y\nformat.k432=x/y\nformat.k433=x/y\nformat.k434=x/y\nformat.k435=x/y\nformat.k436=x/y\nformat.k437=x/y\nformat.k438=x/y\nformat.k439=x/y\nformat.k440=x/y\nformat.k441=x/y\nformat.k442=x/y\nformat.k443=x/y\nformat.k444=x/y\nformat.k445=x/y\nformat.k446=x/y\nformat.k447=x/y\nformat.k448=x/y\nformat.k449=x/y\nformat.k450=x/y\nformat.k451=x/y\nformat.k452=x/y\nformat.k453=x/y\nformat.k454=x/y\nformat.k455=x/y\nformat.k456=x/y\nformat.k457=x/y\nformat.k458=x/y\nformat.k459=x/y\nformat.k460=x/y\nformat.k461=x/y\nformat.k462=x/y\nformat.k463=x/y\nformat.k464=x/y\nformat.k465=x/y\nformat.k466=x/y\nformat.k467=x/y\nformat.k468=x/y\nformat.k469=x/y\nformat.k470=x/y\nformat.k471=x/y\nformat.k472=x/y\nformat.k473=x/y\nformat.k474=x/y\nformat.k475=x/y\nformat.k476=x/y\nformat.k477=x/y\nformat.k478=x/y\nformat.k479=x/y\nformat.k480=x/y\nformat.k481=x/y\nformat.k482=x/y\nformat.k483=x/y\nformat.k484=x/y\nformat.k485=x/y\nformat.k486=x/y\nformat.k487=x/y\nformat.k488=x/y\nformat.k489=x/y\nformat.k490=x/y\nformat.k491=x/y\nformat.k492=x/y\nformat.k493=x/y\nformat.k494=x/y\nformat.k495=x/y\nformat.k496=x/y\nformat.k497=x/y\nformat.k498=x/y\nformat.k499=x/y\nformat.k500=x/y\nformat.k501=x/y\nformat.k502=x/y\nformat.k503=x/y\nformat.k504=x/y\nformat.k505=x/y\nformat.k506=x/y\nformat.k507=x/y\nformat.k508=x/y\nformat.k509=x/y\nformat.k510=x/y\nformat.k511=x/y\nformat.k512=x/y\n"

.text
FN ct_poison_fail
    mov qword ptr [rip + vt_stage], 146
    jmp vt_fail
