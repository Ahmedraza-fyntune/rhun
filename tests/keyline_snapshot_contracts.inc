.bss
.p2align 3
kstc_allocs: .quad 0
kstc_live: .quad 0
kstc_epoch: .quad 0
kstc_before: .zero 32
.text
kstc_pure_begin:
    mov rax, [rip + cgbt_all_alloc_calls]
    mov [rip + kstc_allocs], rax
    mov rax, [rip + g_mem_live]
    mov [rip + kstc_live], rax
    ret
kstc_pure_end:
    mov rax, [rip + cgbt_all_alloc_calls]
    cmp rax, [rip + kstc_allocs]
    jne cgbt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + kstc_live]
    jne cgbt_fail
    ret
kstc_refused_row:
    PROLOGUE
    lea rdi, [rip + ksti_row]
    mov esi, 0xa5
    mov edx, 32
    call memset
    mov rdi, [rip + ksti_old]
    mov esi, 2
    lea rdx, [rip + ksti_row]
    call keyline_snapshot_row
    cmp rax, -22
    jne cgbt_fail
    xor ecx, ecx
1:  lea rdx, [rip + ksti_row]
    cmp byte ptr [rdx + rcx], 0xa5
    jne cgbt_fail
    inc rcx
    cmp rcx, 32
    jb 1b
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
    mov qword ptr [rip + cgbt_stage], 20
    call ksti_capture
    mov [rip + ksti_old], rax
    call config_key_source_epoch
    mov [rip + kstc_epoch], rax
    call kstc_pure_begin
    mov rdi, [rip + ksti_old]
    call keyline_snapshot_count
    cmp rax, 2
    jne cgbt_fail
    call kstc_refused_row
    mov rdi, [rip + ksti_old]
    xor esi, esi
    xor edx, edx
    call keyline_snapshot_row
    cmp rax, -22
    jne cgbt_fail
    mov rdi, [rip + ksti_old]
    mov rsi, [rip + kstc_epoch]
    inc rsi
    call keyline_snapshot_check
    cmp rax, -116
    jne cgbt_fail
    mov rbx, [rip + ksti_old]
    mov qword ptr [rbx + PO_refs], -1
    mov rdi, rbx
    call keyline_snapshot_retain
    cmp rax, -75
    jne cgbt_fail
    cmp qword ptr [rbx + PO_refs], -1
    jne cgbt_fail
    mov qword ptr [rbx + PO_refs], 1
    mov rdi, rbx
    call keyline_snapshot_retain
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne cgbt_fail
    mov rdi, rbx
    call keyline_snapshot_release
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgbt_fail
    mov rdi, rbx
    xor esi, esi
    call keyline_snapshot_step
    cmp rax, -22
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    cmp qword ptr [rbx + PO_error], 0
    jne cgbt_fail
    mov qword ptr [rbx + KSI_magic], 0
    mov rdi, rbx
    call keyline_snapshot_release
    cmp rax, -22
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne cgbt_fail
    mov rdi, rbx
    mov rsi, [rip + kstc_epoch]
    call keyline_snapshot_check
    cmp rax, -22
    jne cgbt_fail
    mov qword ptr [rbx + KSI_magic], KSI_MAGIC
    call ksti_old_row
    call kstc_pure_end
    # Loading invalidates a partial capture before a single borrowed byte.
    mov qword ptr [rip + cgbt_stage], 21
    call ksti_begin
    mov [rip + ksti_partial], rax
    mov rdi, rax
    call keyline_snapshot_retain
    cmp rax, -22
    jne cgbt_fail
    call config_key_source_begin
    test rax, rax
    jnz cgbt_fail
    call kstc_pure_begin
    call keyline_snapshot_begin
    test rax, rax
    jnz cgbt_fail
    cmp rdx, -116
    jne cgbt_fail
    test rcx, rcx
    jnz cgbt_fail
    call ksti_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    cmp qword ptr [rip + ksti_copied], 0
    jne cgbt_fail
    call ksti_old_row
    call kstc_pure_end
    call config_key_source_end
    mov rdi, [rip + ksti_partial]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    # Epoch saturation permanently refuses fresh capture until test-only reset.
    mov qword ptr [rip + cgbt_stage], 22
    mov rdi, 0x7fffffffffffffff
    call ksti_seed_epoch
    call config_key_source_begin
    cmp rax, -75
    jne cgbt_fail
    call config_key_source_end
    call config_key_source_epoch
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    call kstc_pure_begin
    call keyline_snapshot_begin
    test rax, rax
    jnz cgbt_fail
    cmp rdx, -116
    jne cgbt_fail
    call config_key_source_begin
    cmp rax, -75
    jne cgbt_fail
    call config_key_source_end
    call ksti_old_row
    mov rdi, [rip + ksti_old]
    mov rsi, [rip + kstc_epoch]
    call keyline_snapshot_check
    test rax, rax
    jnz cgbt_fail
    mov rdi, [rip + ksti_old]
    mov esi, 1
    call keyline_snapshot_step
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    call kstc_pure_end
    mov rdi, [rip + kstc_epoch]
    call ksti_seed_epoch
    # Nonempty or competing destination input refuses before cursor writes.
    mov qword ptr [rip + cgbt_stage], 23
    call cgbt_new
    mov [rip + ksti_cg], rax
    mov rbx, rax
    mov qword ptr [rbx + CG_nkeys], 1
    mov rdi, [rip + ksti_old]
    mov rsi, rbx
    lea rdx, [rip + ksti_cursor]
    call keyline_snapshot_copy_begin
    cmp rax, -22
    jne cgbt_fail
    lea rdi, [rip + ksti_cursor]
    xor ecx, ecx
1:  cmp qword ptr [rdi + rcx*8], 0
    jne cgbt_fail
    inc rcx
    cmp rcx, 8
    jb 1b
    mov qword ptr [rbx + CG_nkeys], 0
    mov rdi, [rip + ksti_old]
    mov rsi, rbx
    lea rdx, [rip + ksti_cursor]
    call keyline_snapshot_copy_begin
    test rax, rax
    jnz cgbt_fail
    mov qword ptr [rbx + CG_nkeys], 1
    mov r12, [rip + cgbt_all_alloc_calls]
    lea rdi, [rip + ksti_cursor]
    mov esi, 1
    call keyline_snapshot_copy_step
    cmp rax, -22
    jne cgbt_fail
    cmp [rip + cgbt_all_alloc_calls], r12
    jne cgbt_fail
    mov qword ptr [rbx + CG_nkeys], 0
    lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    mov rdi, rbx
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, [rip + ksti_old]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    # KSI preserves counted NUL; actual CG append rejects it before readiness.
    mov qword ptr [rip + cgbt_stage], 24
    lea rax, [rip + kstc_nul]
    mov [rip + kstl_rows], rax
    mov qword ptr [rip + kstl_rows + 8], 3
    mov edi, 1
    call kstl_source
    call ksti_capture
    mov rbx, [rip + ksti_ksi]
    mov rax, [rbx + KSI_rows]
    cmp byte ptr [rax], 'a'
    jne cgbt_fail
    cmp byte ptr [rax + 1], 0
    jne cgbt_fail
    cmp byte ptr [rax + 2], 'b'
    jne cgbt_fail
    call cgbt_new
    mov [rip + ksti_cg], rax
    mov rsi, rax
    mov rdi, [rip + ksti_ksi]
    lea rdx, [rip + ksti_cursor]
    call keyline_snapshot_copy_begin
    test rax, rax
    jnz cgbt_fail
    lea rdi, [rip + ksti_cursor]
    mov esi, 1
    call keyline_snapshot_copy_step
    cmp rax, 1
    jne cgbt_fail
    lea rdi, [rip + ksti_cursor]
    mov esi, 1
    call keyline_snapshot_copy_step
    cmp rax, -22
    jne cgbt_fail
    mov rbx, [rip + ksti_cg]
    cmp qword ptr [rbx + PO_ready], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nkeys], 0
    jne cgbt_fail
    lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    call kstl_drop_both
    call kstl_restore
    lea rdi, [rip + kstc_ok]
    call strlen
    mov rdx, rax
    lea rsi, [rip + kstc_ok]
    mov edi, 1
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
kstc_nul: .byte 'a', 0, 'b'
kstc_ok: .asciz "ok keyline getter, source and cursor contracts\n"
