# Prepared three-slot config ownership. No live config/global intent mutation.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintentmigration.inc"
.bss
.globl g_theme_intent_migration
g_theme_intent_migration: .zero 8
.text
# prepare(ownedLiveTI,freshActualTIR128)->TCM*/primary/cleanup.
# NULL leaves TI borrowed. Every nonNULL result consumes exactly its caller reference.
FN theme_intent_migration_prepare
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Ltcm_bad
    test r12, r12
    jz .Ltcm_bad
    cmp qword ptr [rbx + TI_state], TI_LIVE
    jne .Ltcm_bad
    cmp qword ptr [rbx + TI_refs], 0
    je .Ltcm_bad
    cmp qword ptr [rbx + TI_values], 0
    je .Ltcm_bad
    cmp qword ptr [rbx + TI_values + 8], 0
    je .Ltcm_bad
    cmp qword ptr [rbx + TI_values + 16], 0
    je .Ltcm_bad
    cmp qword ptr [rip + g_theme_intent_migration], 0
    jne .Ltcm_busy
    lea rdi, [rbx + TI_guard]
    mov rsi, r12
    mov edx, TIR_SIZE
    call memeq
    test eax, eax
    jz .Ltcm_stale
    # Only an exactly matching trusted actual capture authorizes header inspection.
    cmp [r12 + 64], rbx
    je .Ltcm_bad
    xor r13d, r13d
.Ltcm_headers:
    cmp r13, 3
    jae .Ltcm_allocate
    mov r14, [r12 + 40 + r13*8]
    mov qword ptr [rsp + r13*8], 0
    test r14, r14
    jz .Ltcm_header_next
    test r14, 15
    jnz .Ltcm_bad
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    cmp r14, [r12 + 40 + rcx*8]
    je .Ltcm_bad
    inc rcx
    jmp 1b
2:  mov rax, [r14 - 16]
    cmp rax, 11
    jbe 3f
    cmp rax, 69632
    jb .Ltcm_bad
    test rax, 4095
    jnz .Ltcm_bad
    cmp rax, TC_MEMORY_CAP
    ja .Ltcm_limit
3:  mov rdi, r14
    call mem_capacity
    cmp [r14 - 8], rax
    ja .Ltcm_bad
    add rax, 16
    mov [rsp + r13*8], rax
.Ltcm_header_next:
    inc r13
    jmp .Ltcm_headers
.Ltcm_allocate:
    mov edi, TCM_SIZE
    call tc_alloc_try
    test rax, rax
    jz .Ltcm_oom
    mov r14, rax
    mov [rip + g_theme_intent_migration], r14
    mov [r14 + TCM_new_ti], rbx
    mov qword ptr [r14 + TCM_owned], 64
    mov qword ptr [r14 + TCM_state], TCM_RETIRING
    lea rdi, [r14 + TCM_guard]
    mov rsi, r12
    mov edx, TIR_SIZE
    call memcpy
    mov rax, [r12 + 64]
    mov [r14 + TCM_old_ti], rax
    xor r13d, r13d
.Ltcm_reserve:
    cmp r13, 3
    jae .Ltcm_strings_begin
    mov rax, [r12 + 40 + r13*8]
    mov [r14 + TCM_old + r13*8], rax
    mov rdi, [rsp + r13*8]
    test rdi, rdi
    jz .Ltcm_reserve_next
    call tc_charge_reserve
    test rax, rax
    js .Ltcm_failed_owner
    mov rax, [rsp + r13*8]
    mov [r14 + TCM_old_charge + r13*8], rax
    bts qword ptr [r14 + TCM_reservations], r13
.Ltcm_reserve_next:
    inc r13
    jmp .Ltcm_reserve
.Ltcm_strings_begin:
    xor r13d, r13d
.Ltcm_string:
    cmp r13, 3
    jae .Ltcm_view
    # A NULL requested slot stays NULL, preserving null versus empty config semantics.
    cmp qword ptr [rbx + TI_values + r13*8], 0
    je .Ltcm_string_next
    mov r15, [rbx + TI_lengths + r13*8]
    lea rdi, [r15 + 1]
    call tc_alloc_try
    test rax, rax
    jz .Ltcm_owned_oom
    mov [r14 + TCM_new + r13*8], rax
    bts qword ptr [r14 + TCM_owned], r13
    mov rdi, rax
    call mem_capacity
    add rax, 16
    mov [r14 + TCM_new_charge + r13*8], rax
    add [r14 + TCM_new_total], rax
    mov rdi, [r14 + TCM_new + r13*8]
    mov rsi, [rbx + TI_values + r13*8]
    lea rdx, [r15 + 1]
    call memcpy
.Ltcm_string_next:
    inc r13
    jmp .Ltcm_string
.Ltcm_view:
    xor r13d, r13d
4:  mov rax, [r14 + TCM_new + r13*8]
    mov [r14 + TCM_view + r13*8], rax
    mov [r14 + TCM_view + 24 + r13*8], rax
    mov rax, [r14 + TCM_old + r13*8]
    mov [r14 + TCM_view + 72 + r13*8], rax
    inc r13
    cmp r13, 3
    jb 4b
    mov rax, [rbx + TI_values + 24]
    mov [r14 + TCM_view + 48], rax
    mov rax, [rbx + TI_values + 32]
    mov [r14 + TCM_view + 56], rax
    mov [r14 + TCM_view + 64], rbx
    mov rax, [r14 + TCM_old_ti]
    mov [r14 + TCM_view + 96], rax
    mov rax, [rbx + TI_effects]
    mov [r14 + TCM_view + 104], rax
    mov rax, [rbx + TI_context]
    mov [r14 + TCM_view + 112], rax
    mov rax, [rbx + TI_config]
    mov [r14 + TCM_view + 120], rax
    mov qword ptr [r14 + TCM_state], TCM_READY
    mov rax, r14
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltcm_owned_oom:
    mov rax, -12
.Ltcm_failed_owner:
    mov [r14 + TCM_primary], rax
    mov rdx, rax
    mov rax, r14
    xor ecx, ecx
    EPILOGUE
.Ltcm_bad:
    mov rdx, -22
    jmp .Ltcm_null
.Ltcm_busy:
    mov rdx, -16
    jmp .Ltcm_null
.Ltcm_stale:
    mov rdx, -116
    jmp .Ltcm_null
.Ltcm_limit:
    mov rdx, -7
    jmp .Ltcm_null
.Ltcm_oom:
    mov rdx, -12
.Ltcm_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# Pure final check. No old allocator header or borrowed string is inspected here.
FN theme_intent_migration_check
    test rdi, rdi
    jz 2f
    test rsi, rsi
    jz 2f
    cmp qword ptr [rdi + TCM_state], TCM_READY
    jne 2f
    PROLOGUE
    lea rdi, [rdi + TCM_guard]
    mov edx, TIR_SIZE
    call memeq
    test eax, eax
    jz 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -116
    EPILOGUE
2:  mov rax, -22
    ret
# view(plan)->borrowed fixed128 publication record, READY only.
FN theme_intent_migration_view
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + TCM_state], TCM_READY
    jne 1f
    lea rax, [rdi + TCM_view]
    xor edx, edx
    ret
1:  xor eax, eax
    mov rdx, -22
    ret
# Infallible, preflighted publication ownership mark. Root already installed all live fields.
# No check, allocation, native IO, callback, retain/release or fallible call is permitted here.
FN theme_intent_migration_mark_committed
    mov rax, [rdi + TCM_new_total]
    sub [rip + g_theme_capture_charge], rax
    mov qword ptr [rdi + TCM_new_total], 0
    mov qword ptr [rdi + TCM_new], 0
    mov qword ptr [rdi + TCM_new + 8], 0
    mov qword ptr [rdi + TCM_new + 16], 0
    mov qword ptr [rdi + TCM_new_ti], 0
    mov rax, [rdi + TCM_reservations]
    shl rax, 3
    cmp qword ptr [rdi + TCM_old_ti], 0
    je 1f
    or rax, 128
1:  mov [rdi + TCM_owned], rax
    mov qword ptr [rdi + TCM_reservations], 0
    mov qword ptr [rdi + TCM_committed], 1
    mov qword ptr [rdi + TCM_state], TCM_COMMITTED
    ret
