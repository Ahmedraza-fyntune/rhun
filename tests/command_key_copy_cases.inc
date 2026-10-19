.globl cgbt_context
.bss
.p2align 3
kcti_source: .quad 0
kcti_case: .quad 0
kcti_budget: .quad 0
.text
kcti_refused:
    cmp rax, -22
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    test rcx, rcx
    jnz cgbt_fail
    ret
kcti_reset:
    PROLOGUE
    lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    EPILOGUE
kcti_drop_dest:
    PROLOGUE
    call kcti_reset
    mov rdi, [rip + ksti_cg]
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    EPILOGUE
kcti_copy:
    PROLOGUE
    call cgbt_new
    mov [rip + ksti_cg], rax
    mov rsi, rax
    mov rdi, [rip + kcti_source]
    lea rdx, [rip + ksti_cursor]
    call command_generation_key_copy_begin
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rip + ksti_cursor + KSC_kind], KSC_CG
    jne cgbt_fail
    mov r15d, 200000
1:  mov rax, [rip + cgbt_all_alloc_calls]
    mov [rip + ksti_alloc_entry], rax
    mov qword ptr [rip + ksti_copied], 0
    mov qword ptr [rip + ksti_copy_active], 1
    lea rdi, [rip + ksti_cursor]
    mov r13, [rip + kcti_budget]
    mov rsi, r13
    call keyline_snapshot_copy_step
    mov qword ptr [rip + ksti_copy_active], 0
    test rax, rax
    js cgbt_fail
    cmp rdx, r13
    ja cgbt_fail
    xor qword ptr [rip + kcti_budget], 17
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
2:  EPILOGUE
kcti_equal:
    PROLOGUE
    mov r13, [rip + kcti_source]
    mov r14, [rip + ksti_cg]
    mov r15, [r13 + CG_nkeys]
    cmp [r14 + CG_nkeys], r15
    jne cgbt_fail
    add r13, CG_keylines
    add r14, CG_keylines
    xor r12d, r12d
1:  cmp r12, r15
    jae 3f
    mov rax, [r13 + 8]
    cmp [r14 + 8], rax
    jne cgbt_fail
    mov rdi, [r13]
    mov rsi, [r14]
    cmp rdi, rsi
    je cgbt_fail
    cmp byte ptr [rsi + rax], 0
    jne cgbt_fail
    mov rdx, rax
    call memeq
    test eax, eax
    jz cgbt_fail
    mov rax, [r13 + 24]
    cmp [r14 + 24], rax
    jne cgbt_fail
    mov rdi, [r13 + 16]
    mov rsi, [r14 + 16]
    cmp rdi, rsi
    je cgbt_fail
    cmp byte ptr [rsi + rax], 0
    jne cgbt_fail
    mov rdx, rax
    call memeq
    test eax, eax
    jz cgbt_fail
    add r13, 32
    add r14, 32
    inc r12
    jmp 1b
3:  EPILOGUE
kcti_source_from_ksi:
    PROLOGUE
    call kstl_copy
    mov rdi, [rip + ksti_cg]
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov rax, [rip + ksti_cg]
    mov [rip + kcti_source], rax
    mov rdi, [rip + ksti_ksi]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + kcti_budget], 1
    call config_load
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    mov qword ptr [rip + cgbt_stage], 30
    call ksti_capture
    # A real KSI with plausible CG scalar fields still has the wrong owner kind.
    mov rbx, [rip + ksti_ksi]
    mov r12, [rbx + KSI_creation]
    mov qword ptr [rbx + CG_phase], CG_READY
    mov rdi, rbx
    mov esi, KSC_CG
    call keyline_copy_source
    call kcti_refused
    mov [rbx + KSI_creation], r12
    xor edi, edi
    mov esi, KSC_CG
    call keyline_copy_source
    call kcti_refused
    mov qword ptr [rip + cgbt_stage], 31
    call cgbt_new
    mov rbx, rax
    mov qword ptr [rbx + CG_phase], CG_READY
    mov rdi, rbx
    mov esi, KSC_CG
    call keyline_copy_source
    call kcti_refused
    mov qword ptr [rbx + CG_phase], CG_INPUT
    mov rdi, rbx
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    call kcti_source_from_ksi
    mov qword ptr [rip + cgbt_stage], 32
    mov rdi, [rip + kcti_source]
    mov esi, KSC_CG
    call keyline_copy_source
    test rax, rax
    jnz cgbt_fail
    cmp rdx, 2
    jne cgbt_fail
    mov rbx, [rip + kcti_source]
    lea rax, [rbx + CG_keylines]
    cmp rcx, rax
    jne cgbt_fail
    mov rdi, rbx
    mov esi, 99
    call keyline_copy_source
    call kcti_refused
    mov qword ptr [rbx + CG_nkeys], CG_KEY_CAP + 1
    mov rdi, rbx
    mov esi, KSC_CG
    call keyline_copy_source
    call kcti_refused
    mov qword ptr [rbx + CG_nkeys], 2
    mov qword ptr [rbx - RD_PO_BACK + RD_state], RD_READY + RDF_PO
    mov rdi, rbx
    mov esi, KSC_CG
    call keyline_copy_source
    call kcti_refused
    mov qword ptr [rbx - RD_PO_BACK + RD_state], RDF_PO
    mov qword ptr [rip + cgbt_stage], 33
    call kcti_copy
    call kcti_equal
    mov rdi, [rip + ksti_cg]
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    lea rdi, [rip + ksti_cursor]
    mov esi, 16
    call keyline_snapshot_copy_step
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    call kcti_drop_dest
    # Stale source intent remains valid owned input after actual config reload.
    mov qword ptr [rip + cgbt_stage], 34
    lea rdi, [rip + ksti_config_b]
    call ksti_write_load
    inc qword ptr [rip + cgbt_context]
    mov rdi, [rip + kcti_source]
    mov esi, KSC_CG
    call keyline_copy_source
    test rax, rax
    jnz cgbt_fail
    # Real destination allocation failure leaves the held source unchanged.
    mov qword ptr [rip + cgbt_stage], 36
    mov rbx, [rip + kcti_source]
    mov r12, [rbx + PO_refs]
    mov r13, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov r14, rax
    call cgbt_new
    mov [rip + ksti_cg], rax
    mov rsi, rax
    mov rdi, [rip + kcti_source]
    lea rdx, [rip + ksti_cursor]
    call command_generation_key_copy_begin
    test rax, rax
    jnz cgbt_fail
    mov qword ptr [rip + cgbt_alloc_calls], 0
    mov qword ptr [rip + cgbt_alloc_fault], 1
    lea rdi, [rip + ksti_cursor]
    mov esi, 16
    call keyline_snapshot_copy_step
    cmp rax, -12
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    mov qword ptr [rip + cgbt_alloc_fault], 0
    mov r15, [rip + cgbt_all_alloc_calls]
    lea rdi, [rip + ksti_cursor]
    mov esi, 16
    call keyline_snapshot_copy_step
    cmp rax, -12
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    cmp [rip + cgbt_all_alloc_calls], r15
    jne cgbt_fail
    call kcti_drop_dest
    mov rbx, [rip + kcti_source]
    cmp [rbx + PO_refs], r12
    jne cgbt_fail
    cmp qword ptr [rbx + PO_error], 0
    jne cgbt_fail
    cmp qword ptr [rbx + PO_ready], 1
    jne cgbt_fail
    cmp [rip + g_mem_live], r13
    jne cgbt_fail
    call ext_prepare_retire_charge
    cmp rax, r14
    jne cgbt_fail
    mov qword ptr [rip + cgbt_stage], 34
    call kcti_copy
    call kcti_equal
    call kcti_reset
    mov rdi, [rip + kcti_source]
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    mov rbx, [rip + ksti_cg]
    mov rdi, [rbx + CG_keylines]
    lea rsi, [rip + ksti_combo9]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rdi, rbx
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    call kcti_drop_dest
    call cgbt_drain
    # Real sealed source/destination at0/4096 rows, both field caps and1MiB.
    mov qword ptr [rip + cgbt_stage], 35
    mov qword ptr [rip + kcti_case], 0
.Lkcti_cap:
    lea rdi, [rip + kstl_rows]
    xor esi, esi
    mov edx, (KSI_MAX_ROWS + 1) * 32
    call memset
    mov rax, [rip + kcti_case]
    test rax, rax
    jz .Lkcti_empty
    cmp rax, 1
    je .Lkcti_all_empty
    lea rdi, [rip + kstl_bytes]
    mov esi, 'x'
    mov edx, KC_CAP
    call memset
    cmp qword ptr [rip + kcti_case], 6
    je .Lkcti_mib
    mov rax, [rip + kcti_case]
    mov edx, 65536
    test al, 1
    jz 1f
    mov edx, KC_CAP
1:  lea rcx, [rip + kstl_rows]
    cmp rax, 4
    jb 2f
    add rcx, 16
2:  lea rax, [rip + kstl_bytes]
    mov [rcx], rax
    mov [rcx + 8], rdx
    mov edi, 1
    jmp .Lkcti_capture
.Lkcti_mib:
    lea rax, [rip + kstl_rows]
    lea rdx, [rip + kstl_bytes]
    xor ecx, ecx
3:  mov [rax], rdx
    mov qword ptr [rax + 8], KC_CAP
    add rax, 32
    inc rcx
    cmp rcx, 5
    jb 3b
    mov [rax], rdx
    mov qword ptr [rax + 8], KSI_MAX_BYTES - 5 * KC_CAP
    mov edi, 6
    jmp .Lkcti_capture
.Lkcti_all_empty:
    mov edi, CG_KEY_CAP
    jmp .Lkcti_capture
.Lkcti_empty:
    xor edi, edi
.Lkcti_capture:
    call kstl_source
    call ksti_capture
    call kcti_source_from_ksi
    call kcti_copy
    call kcti_equal
    call kcti_reset
    mov rdi, [rip + kcti_source]
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    mov rdi, [rip + ksti_cg]
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    call kcti_drop_dest
    call kstl_restore
    call cgbt_drain
    inc qword ptr [rip + kcti_case]
    cmp qword ptr [rip + kcti_case], 7
    jb .Lkcti_cap
    lea rdi, [rip + kcti_ok]
    call strlen
    mov rdx, rax
    lea rsi, [rip + kcti_ok]
    mov edi, 1
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
kcti_ok: .asciz "ok immutable command-generation keyline copy and owner lifetimes\n"
