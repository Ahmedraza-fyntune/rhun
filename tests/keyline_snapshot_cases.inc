.include "app/keylinesnapshot.inc"
.bss
.p2align 3
ksti_ksi: .quad 0
ksti_epoch: .quad 0
ksti_cg: .quad 0
ksti_cursor: .zero KSC_SIZE
ksti_row: .zero 32
ksti_old: .quad 0
ksti_partial: .quad 0
ksti_alloc_entry: .quad 0
ksti_copied: .quad 0
ksti_copy_active: .quad 0
.text
FN ksti_source_copy
    add [rip + ksti_copied], rdx
    mov rax, [rip + cgbt_all_alloc_calls]
    cmp rax, [rip + ksti_alloc_entry]
    jne cgbt_fail
    jmp memcpy
FN ksti_append_guard
    cmp qword ptr [rip + ksti_copy_active], 0
    je 1f
    lea rax, [rdx - 1]
    cmp rax, 4095
    ja cgbt_fail
    add [rip + ksti_copied], rdx
    mov rax, [rip + cgbt_all_alloc_calls]
    cmp rax, [rip + ksti_alloc_entry]
    jne cgbt_fail
1:  ret
ksti_step:
    PROLOGUE
    mov rax, [rip + cgbt_all_alloc_calls]
    mov [rip + ksti_alloc_entry], rax
    mov qword ptr [rip + ksti_copied], 0
    mov rdi, [rip + ksti_ksi]
    mov esi, 16
    call keyline_snapshot_step
    mov r12, rax
    mov r13, rdx
    cmp r13, 16
    ja cgbt_fail
    mov rax, r13
    shl rax, 12
    cmp [rip + ksti_copied], rax
    ja cgbt_fail
    mov rax, [rip + cgbt_all_alloc_calls]
    sub rax, [rip + ksti_alloc_entry]
    cmp rax, 1
    ja cgbt_fail
    mov rax, r12
    mov rdx, r13
    EPILOGUE
ksti_capture:
    PROLOGUE
    call ksti_begin
    mov r15d, 200000
1:  call ksti_step
    test rax, rax
    js cgbt_fail
    jz 2f
    dec r15
    jnz 1b
    jmp cgbt_fail
2:  mov rax, [rip + ksti_ksi]
    EPILOGUE
ksti_drain:
    PROLOGUE
    mov r15d, 200000
1:  mov edi, 1
    lea rsi, [rip + cgbt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgbt_fail
    cmp qword ptr [rip + cgbt_retire], 1
    ja cgbt_fail
    cmp qword ptr [rip + cgbt_retire + 16], 0
    jne cgbt_fail
    test rax, rax
    jz 2f
    dec r15
    jnz 1b
    jmp cgbt_fail
2:  EPILOGUE
ksti_write_load:
    PROLOGUE
    mov r12, rdi
    call config_path
    mov rdi, r12
    call strlen
    mov r13, rax
    call config_path
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call file_write_all
    test rax, rax
    js cgbt_fail
    call config_load
    cmp qword ptr [rip + g_keylines + VEC_len], 2
    jne cgbt_fail
    EPILOGUE
ksti_old_row:
    PROLOGUE
    mov rdi, [rip + ksti_old]
    xor esi, esi
    lea rdx, [rip + ksti_row]
    call keyline_snapshot_row
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rip + ksti_row + 8], 10
    jne cgbt_fail
    mov rdi, [rip + ksti_row]
    lea rsi, [rip + ksti_combo9]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    mov rax, [rip + g_keylines + VEC_ptr]
    mov rax, [rax]
    cmp [rip + ksti_row], rax
    je cgbt_fail
    EPILOGUE
ksti_begin:
    PROLOGUE
    call keyline_snapshot_begin
    test rax, rax
    jz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    test rcx, rcx
    jnz cgbt_fail
    mov [rip + ksti_ksi], rax
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 0
    call config_load
    cmp qword ptr [rip + g_keylines + VEC_len], 2
    jne cgbt_fail
    call config_key_source_epoch
    test rax, rax
    jle cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    mov [rip + ksti_epoch], rax
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    # Hold a sealed snapshot across actual raw-source destruction and reuse.
    mov qword ptr [rip + cgbt_stage], 1
    call ksti_capture
    mov [rip + ksti_old], rax
    call ksti_old_row
    call ksti_begin
    mov [rip + ksti_partial], rax
    mov rdi, rax
    mov esi, 1
    call keyline_snapshot_step
    cmp rax, 1
    jne cgbt_fail
    mov qword ptr [rip + cgbt_stage], 2
    lea rdi, [rip + ksti_config_b]
    call ksti_write_load
    call config_key_source_epoch
    cmp rax, [rip + ksti_epoch]
    jle cgbt_fail
    call ksti_step
    cmp rax, -116
    jne cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    cmp qword ptr [rip + ksti_copied], 0
    jne cgbt_fail
    mov rdi, [rip + ksti_partial]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    call ksti_old_row
    mov rdi, [rip + ksti_old]
    mov rsi, [rip + ksti_epoch]
    call keyline_snapshot_check
    test rax, rax
    jnz cgbt_fail
    mov rdi, [rip + ksti_old]
    mov esi, 16
    call keyline_snapshot_step
    test rax, rax
    jnz cgbt_fail
    test rdx, rdx
    jnz cgbt_fail
    # The actual CG input API copies the fresh immutable source before sealing.
    mov qword ptr [rip + cgbt_stage], 3
    call ksti_capture
    call cgbt_new
    mov [rip + ksti_cg], rax
    mov rsi, rax
    mov rdi, [rip + ksti_ksi]
    lea rdx, [rip + ksti_cursor]
    call keyline_snapshot_copy_begin
    test rax, rax
    jnz cgbt_fail
    mov r15d, 200000
.Lksti_copy:
    mov rax, [rip + cgbt_all_alloc_calls]
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
    jz .Lksti_copy_done
    dec r15
    jnz .Lksti_copy
    jmp cgbt_fail
.Lksti_copy_done:
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
    lea rdi, [rip + ksti_cursor]
    xor esi, esi
    mov edx, KSC_SIZE
    call memset
    mov rdi, [rip + ksti_ksi]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call ksti_drain
    lea rdi, [rip + ksti_config_a]
    call ksti_write_load
    mov qword ptr [rip + cgbt_stage], 4
    mov rbx, [rip + ksti_cg]
    cmp qword ptr [rbx + CG_nkeys], 2
    jne cgbt_fail
    mov rdi, [rbx + CG_keylines]
    lea rsi, [rip + ksti_combo8]
    call strcmp_eq
    test eax, eax
    jz cgbt_fail
    call ksti_old_row
    mov rdi, rbx
    call command_generation_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rdi, [rip + ksti_old]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    call config_key_source_epoch
    mov [rip + ksti_epoch], rax
    # A failed capture remains owned, and check normalizes owner failure to EINVAL.
    mov qword ptr [rip + cgbt_stage], 6
    call ksti_begin
    mov qword ptr [rip + cgbt_alloc_calls], 0
    mov qword ptr [rip + cgbt_alloc_fault], 1
    mov rdi, [rip + ksti_ksi]
    mov esi, 1
    call keyline_snapshot_step
    cmp rax, -12
    jne cgbt_fail
    cmp rdx, 1
    jne cgbt_fail
    mov qword ptr [rip + cgbt_alloc_fault], 0
    mov rdi, [rip + ksti_ksi]
    mov rsi, [rip + ksti_epoch]
    call keyline_snapshot_check
    cmp rax, -22
    jne cgbt_fail
    mov rdi, [rip + ksti_ksi]
    call keyline_snapshot_release
    cmp rdx, 1
    jne cgbt_fail
    call cgbt_drain
    lea rdi, [rip + ksti_ok]
    call strlen
    mov rdx, rax
    lea rsi, [rip + ksti_ok]
    mov edi, 1
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
ksti_ok: .asciz "ok owned keyline snapshots and reload lifetimes\n"
ksti_combo9: .asciz "ctrl+alt+9"
ksti_combo8: .asciz "ctrl+alt+8"
ksti_config_a: .asciz "[keys]\nctrl+alt+9 = none\nmalformed line\nctrl+q = quit\n"
ksti_config_b: .asciz "[keys]\nctrl+alt+8 = none\nctrl+w = quit\n"
