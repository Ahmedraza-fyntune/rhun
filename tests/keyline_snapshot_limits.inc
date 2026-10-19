.bss
.p2align 3
kstl_saved_source: .zero 24
kstl_rows: .zero (KSI_MAX_ROWS + 1) * 32
kstl_bytes: .zero KC_CAP + 1
kstl_length: .quad 0
kstl_field_offset: .quad 0
kstl_map: .quad 0
kstl_header: .quad 0
kstl_fault: .quad 0
kstl_calls: .quad 0
.text
FN ksti_native_unmap
    cmp rdi, [rip + kstl_map]
    jne 1f
    inc qword ptr [rip + kstl_calls]
    cmp qword ptr [rip + kstl_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
# Controlled fixture source only. Restore before any actual config_load or exit.
kstl_source:
    PROLOGUE
    mov r12, rdi
    call config_key_source_begin
    lea rdi, [rip + kstl_saved_source]
    lea rsi, [rip + g_keylines]
    mov edx, 24
    call memcpy
    lea rax, [rip + kstl_rows]
    mov [rip + g_keylines + VEC_ptr], rax
    mov [rip + g_keylines + VEC_len], r12
    mov qword ptr [rip + g_keylines + VEC_cap], KSI_MAX_ROWS + 1
    call config_key_source_end
    EPILOGUE
kstl_restore:
    PROLOGUE
    call config_key_source_begin
    lea rdi, [rip + g_keylines]
    lea rsi, [rip + kstl_saved_source]
    mov edx, 24
    call memcpy
    call config_key_source_end
    EPILOGUE
kstl_release:
    PROLOGUE
    mov rdi, [rip + ksti_ksi]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    EPILOGUE
kstl_copy:
    PROLOGUE
    call cgbt_new
    mov [rip + ksti_cg], rax
    lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    mov rdi, [rip + ksti_ksi]
    mov rsi, [rip + ksti_cg]
    lea rdx, [rip + ksti_cursor]
    call keyline_snapshot_copy_begin
    test rax, rax
    jnz cgbt_fail
    mov r15d, 200000
1:  mov rax, [rip + cgbt_all_alloc_calls]
    mov [rip + ksti_alloc_entry], rax
    mov qword ptr [rip + ksti_copied], 0
    mov qword ptr [rip + ksti_copy_active], 1
    lea rdi, [rip + ksti_cursor]
    mov esi, 16
    call keyline_snapshot_copy_step
    mov qword ptr [rip + ksti_copy_active], 0
    test rax, rax
    js cgbt_fail
    cmp rdx, 16
    ja cgbt_fail
    mov r12, rax
    mov rax, rdx
    shl rax, 12
    cmp [rip + ksti_copied], rax
    ja cgbt_fail
    mov rax, [rip + cgbt_all_alloc_calls]
    sub rax, [rip + ksti_alloc_entry]
    cmp rax, 1
    ja cgbt_fail
    test r12, r12
    jz 2f
    dec r15
    jnz 1b
    jmp cgbt_fail
2:  lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    EPILOGUE
kstl_drop_both:
    PROLOGUE
    mov rdi, [rip + ksti_cg]
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call kstl_release
    EPILOGUE
FN main
    PROLOGUE
    call config_load
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    # Empty snapshot and completed empty-copy cursor perform no key allocation.
    mov qword ptr [rip + cgbt_stage], 10
    xor edi, edi
    call kstl_source
    call ksti_capture
    call kstl_copy
    mov rbx, [rip + ksti_cg]
    cmp qword ptr [rbx + CG_nkeys], 0
    jne cgbt_fail
    call kstl_drop_both
    call kstl_restore
    # Both user-field boundaries, including the real parser's full KC_CAP.
    mov qword ptr [rip + kstl_length], 65536
.Lkstl_field:
    mov qword ptr [rip + cgbt_stage], 11
    lea rdi, [rip + kstl_bytes]
    mov esi, 'x'
    mov edx, KC_CAP + 1
    call memset
    lea rax, [rip + kstl_bytes]
    lea rdx, [rip + kstl_rows]
    mov qword ptr [rdx], 0
    mov qword ptr [rdx + 8], 0
    mov qword ptr [rdx + 16], 0
    mov qword ptr [rdx + 24], 0
    add rdx, [rip + kstl_field_offset]
    mov [rdx], rax
    mov rax, [rip + kstl_length]
    mov [rdx + 8], rax
    mov edi, 1
    call kstl_source
    call ksti_capture
    mov rbx, [rip + ksti_ksi]
    add rbx, [rip + kstl_field_offset]
    mov rax, [rip + kstl_length]
    cmp [rbx + KSI_rows + 8], rax
    jne cgbt_fail
    mov rdx, [rbx + KSI_rows]
    cmp byte ptr [rdx + rax - 1], 'x'
    jne cgbt_fail
    cmp byte ptr [rdx + rax], 0
    jne cgbt_fail
    call kstl_copy
    mov rbx, [rip + ksti_cg]
    add rbx, [rip + kstl_field_offset]
    mov rax, [rip + kstl_length]
    cmp [rbx + CG_keylines + 8], rax
    jne cgbt_fail
    call kstl_drop_both
    call kstl_restore
    cmp qword ptr [rip + kstl_length], KC_CAP
    je .Lkstl_next_field
    mov qword ptr [rip + kstl_length], KC_CAP
    jmp .Lkstl_field
.Lkstl_next_field:
    cmp qword ptr [rip + kstl_field_offset], 16
    je .Lkstl_over_field
    mov qword ptr [rip + kstl_field_offset], 16
    mov qword ptr [rip + kstl_length], 65536
    jmp .Lkstl_field
.Lkstl_over_field:
    mov qword ptr [rip + cgbt_stage], 12
    mov qword ptr [rip + kstl_rows], 1
    mov qword ptr [rip + kstl_rows + 8], KC_CAP + 1
    mov qword ptr [rip + kstl_rows + 16], 0
    mov qword ptr [rip + kstl_rows + 24], 0
    mov edi, 1
    call kstl_source
    call ksti_begin
    call ksti_step
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [rip + ksti_copied], 0
    jne cgbt_fail
    call kstl_release
    call kstl_restore
    mov qword ptr [rip + kstl_rows], 0
    mov qword ptr [rip + kstl_rows + 8], 0
    mov qword ptr [rip + kstl_rows + 16], 1
    mov qword ptr [rip + kstl_rows + 24], KC_CAP + 1
    mov edi, 1
    call kstl_source
    call ksti_begin
    call ksti_step
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [rip + ksti_copied], 0
    jne cgbt_fail
    call kstl_release
    call kstl_restore
    # Row cap rejects before following ptr1 or attempting any allocation.
    mov qword ptr [rip + cgbt_stage], 13
    mov edi, KSI_MAX_ROWS + 1
    call kstl_source
    mov qword ptr [rip + g_keylines + VEC_ptr], 1
    mov r12, [rip + cgbt_all_alloc_calls]
    call keyline_snapshot_begin
    test rax, rax
    jnz cgbt_fail
    cmp rdx, -EV_RESOURCE
    jne cgbt_fail
    cmp [rip + cgbt_all_alloc_calls], r12
    jne cgbt_fail
    call kstl_restore
    # Exactly1MiB succeeds, the extra counted byte refuses before source copy.
    mov qword ptr [rip + cgbt_stage], 14
    lea rdi, [rip + kstl_rows]
    xor esi, esi
    mov edx, (KSI_MAX_ROWS + 1) * 32
    call memset
    lea rax, [rip + kstl_rows]
    xor ecx, ecx
1:  lea rdx, [rip + kstl_bytes]
    mov [rax], rdx
    mov qword ptr [rax + 8], KC_CAP
    add rax, 32
    inc rcx
    cmp rcx, 5
    jb 1b
    mov [rax], rdx
    mov qword ptr [rax + 8], KSI_MAX_BYTES - 5 * KC_CAP
    mov edi, 6
    call kstl_source
    call ksti_capture
    mov rbx, [rip + ksti_ksi]
    cmp qword ptr [rbx + KSI_bytes], KSI_MAX_BYTES
    jne cgbt_fail
    call kstl_release
    call kstl_restore
    inc qword ptr [rip + kstl_rows + 5 * 32 + 8]
    mov qword ptr [rip + kstl_rows + 5 * 32], 1
    mov edi, 6
    call kstl_source
    call ksti_begin
    mov r15d, 200000
2:  call ksti_step
    cmp rax, 1
    jne 6f
    dec r15
    jnz 2b
    jmp cgbt_fail
6:
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    call kstl_release
    call kstl_restore
    # Full4096 empty rows reach real key_finish without append(0).
    mov qword ptr [rip + cgbt_stage], 15
    lea rdi, [rip + kstl_rows]
    xor esi, esi
    mov edx, (KSI_MAX_ROWS + 1) * 32
    call memset
    mov edi, KSI_MAX_ROWS
    call kstl_source
    call ksti_capture
    call kstl_copy
    mov rbx, [rip + ksti_cg]
    cmp qword ptr [rbx + CG_nkeys], KSI_MAX_ROWS
    jne cgbt_fail
    mov rdi, rbx
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    # Fail real creation-map unmap. The last generic ledger entry remains owned.
    mov qword ptr [rip + cgbt_stage], 16
    mov rbx, [rip + ksti_ksi]
    lea rax, [rbx - RD_PO_BACK - 16]
    mov [rip + kstl_map], rax
    mov rcx, [rax]
    mov [rip + kstl_header], rcx
    cmp rcx, 65536
    jbe cgbt_fail
    mov qword ptr [rip + kstl_fault], 1
    mov rdi, rbx
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    mov r15d, 200000
3:  mov r12, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov r13, rax
    mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + kstl_calls], 0
    jne 4f
    dec r15
    jnz 3b
    jmp cgbt_fail
4:  cmp qword ptr [rip + kstl_calls], 1
    jne cgbt_fail
    cmp [rip + g_mem_live], r12
    jne cgbt_fail
    call ext_prepare_retire_charge
    cmp rax, r13
    jne cgbt_fail
    mov rax, [rip + kstl_map]
    mov rcx, [rip + kstl_header]
    cmp [rax], rcx
    jne cgbt_fail
    mov r15d, 100
5:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    cmp qword ptr [rip + kstl_calls], 1
    jne cgbt_fail
    dec r15
    jnz 5b
    mov qword ptr [rip + kstl_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    cmp qword ptr [rip + kstl_calls], 2
    jne cgbt_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz cgbt_fail
    call kstl_restore
    lea rdi, [rip + kstl_ok]
    call strlen
    mov rdx, rax
    lea rsi, [rip + kstl_ok]
    mov edi, 1
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
kstl_ok: .asciz "ok keyline bounds, zero spans and native retirement\n"
