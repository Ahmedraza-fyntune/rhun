# Counted oracle cases, exact work accounting, suspension, validation and ABI preservation.
.include "rhun.inc"
.include "app/keycombo.inc"
.bss
.p2align 3
kct_before: .quad 0
kct_state: .zero KC_SIZE
kct_after: .quad 0
kct_snapshot: .zero KC_SIZE
kct_valid: .zero KC_SIZE
kct_digest: .zero 32
kct_digest_after: .zero 32
kct_file: .quad 0
kct_filelen: .quad 0
kct_header: .quad 0
kct_case: .quad 0
kct_count: .quad 0
kct_key: .quad 0
kct_mods: .quad 0
kct_scanned: .quad 0
kct_tokens: .quad 0
kct_calls: .quad 0
kct_bytes: .quad 0
kct_applications: .quad 0
kct_live: .quad 0
kct_stage: .quad 0
.text
kct_fail:
    mov rdi, [rip + kct_stage]
    add rdi, 70
    call sys_exit
    ud2
# Exact-source test link replaces the four scanner reads with this independent observer.
FN kct_observed_read
    test r12, r12
    jz kct_fail
    movzx eax, byte ptr [r8 + rcx]
    ret

kct_begin:
    PROLOGUE 32
    mov [rsp + 24], rbp
    mov ebx, 17
    mov r12d, 34
    mov r13d, 51
    mov r14d, 68
    mov r15d, 85
    call keys_combo_begin
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    cmp rbx, 17
    jne kct_fail
    cmp r12, 34
    jne kct_fail
    cmp r13, 51
    jne kct_fail
    cmp r14, 68
    jne kct_fail
    cmp r15, 85
    jne kct_fail
    cmp rbp, [rsp + 24]
    jne kct_fail
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE

kct_step:
    PROLOGUE 32
    mov [rsp + 24], rbp
    mov ebx, 17
    mov r12d, 34
    mov r13d, 51
    mov r14d, 68
    mov r15d, 85
    call keys_combo_step
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    cmp rbx, 17
    jne kct_fail
    cmp r12, 34
    jne kct_fail
    cmp r13, 51
    jne kct_fail
    cmp r14, 68
    jne kct_fail
    cmp r15, 85
    jne kct_fail
    cmp rbp, [rsp + 24]
    jne kct_fail
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE

kct_result:
    PROLOGUE 32
    mov [rsp + 24], rbp
    mov ebx, 17
    mov r12d, 34
    mov r13d, 51
    mov r14d, 68
    mov r15d, 85
    call keys_combo_result
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    cmp rbx, 17
    jne kct_fail
    cmp r12, 34
    jne kct_fail
    cmp r13, 51
    jne kct_fail
    cmp r14, 68
    jne kct_fail
    cmp r15, 85
    jne kct_fail
    cmp rbp, [rsp + 24]
    jne kct_fail
    mov rax, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    EPILOGUE

kct_capture:
    lea rdi, [rip + kct_snapshot]
    lea rsi, [rip + kct_state]
    mov edx, KC_SIZE
    jmp memcpy
kct_unchanged:
    cmp rax, -22
    jne kct_fail
    test rdx, rdx
    jnz kct_fail
    test rcx, rcx
    jnz kct_fail
    lea rdi, [rip + kct_snapshot]
    lea rsi, [rip + kct_state]
    mov edx, KC_SIZE
    call memeq
    test eax, eax
    jz kct_fail
    ret
kct_same_begin:
    cmp rax, -22
    jne kct_fail
    lea rdi, [rip + kct_snapshot]
    lea rsi, [rip + kct_state]
    mov edx, KC_SIZE
    call memeq
    test eax, eax
    jz kct_fail
    ret

kct_invalid:
    PROLOGUE
    mov qword ptr [rip + kct_stage], 4
    lea rdi, [rip + kct_state]
    mov esi, 165
    mov edx, KC_SIZE
    call memset
    call kct_capture
    # Begin validates the whole span and state address before writing a byte.
    lea rdi, [rip + kct_state]
    xor esi, esi
    mov edx, 1
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_ab]
    mov rdx, -1
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_ab]
    mov edx, KC_CAP + 1
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_ab]
    mov rdx, 0x100000002
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state]
    mov rsi, -8
    mov edx, 16
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state]
    mov rsi, rdi
    mov edx, 1
    call kct_begin
    call kct_same_begin
    lea rdi, [rip + kct_state + 1]
    lea rsi, [rip + kct_ab]
    mov edx, 2
    call kct_begin
    call kct_same_begin
    mov rdi, -8
    lea rsi, [rip + kct_ab]
    mov edx, 2
    call kct_begin
    call kct_same_begin
    # Zero storage has not been initialized, despite looking like an empty span.
    lea rdi, [rip + kct_state]
    xor esi, esi
    mov edx, KC_SIZE
    call memset
    call kct_capture
    lea rdi, [rip + kct_state]
    mov esi, 1
    mov edx, 1
    call kct_step
    call kct_unchanged
    # Invalid budgets take precedence over completed-state idempotence.
    lea rdi, [rip + kct_state]
    xor esi, esi
    xor edx, edx
    call kct_begin
    test rax, rax
    jnz kct_fail
    call kct_capture
    xor r12d, r12d
1:  lea rax, [rip + kct_bad_budgets]
    mov rsi, [rax + r12]
    mov rdx, [rax + r12 + 8]
    lea rdi, [rip + kct_state]
    call kct_step
    call kct_unchanged
    add r12, 16
    cmp r12, 128
    jb 1b
    # A range of corrupt state invariants is rejected without repairing/mutating it.
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_ab]
    mov edx, 2
    call kct_begin
    lea rdi, [rip + kct_valid]
    lea rsi, [rip + kct_state]
    mov edx, KC_SIZE
    call memcpy
    xor r12d, r12d
2:  lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_valid]
    mov edx, KC_SIZE
    call memcpy
    lea rax, [rip + kct_bad_states]
    mov rcx, [rax + r12]
    mov rdx, [rax + r12 + 8]
    lea rax, [rip + kct_state]
    mov [rax + rcx], rdx
    call kct_capture
    lea rdi, [rip + kct_state]
    mov esi, 1
    mov edx, 1
    call kct_step
    call kct_unchanged
    add r12, 16
    cmp r12, 160
    jb 2b
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_hex]
    mov edx, 3
    call kct_begin
    lea rdi, [rip + kct_state]
    mov esi, 3
    mov edx, 1
    call kct_step
    cmp rax, 1
    jne kct_fail
    cmp qword ptr [rip + kct_state + KC_phase], KC_NUMERIC
    jne kct_fail
    lea rdi, [rip + kct_valid]
    lea rsi, [rip + kct_state]
    mov edx, KC_SIZE
    call memcpy
    xor r12d, r12d
.Lkct_active_phase:
    xor r13d, r13d
.Lkct_active_length:
    lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_valid]
    mov edx, KC_SIZE
    call memcpy
    lea rax, [rip + kct_active_phases]
    mov rax, [rax + r12*8]
    mov [rip + kct_state + KC_phase], rax
    mov [rip + kct_state + KC_length], r13
    call kct_capture
    lea rdi, [rip + kct_state]
    mov esi, 1
    mov edx, 1
    call kct_step
    call kct_unchanged
    add r13, 2
    cmp r13, 4
    jb .Lkct_active_length
    inc r12
    cmp r12, 5
    jb .Lkct_active_phase
    mov r13d, KC_NUMERIC
.Lkct_numeric_phase:
    xor r12d, r12d
3:  lea rdi, [rip + kct_state]
    lea rsi, [rip + kct_valid]
    mov edx, KC_SIZE
    call memcpy
    mov [rip + kct_state + KC_phase], r13
    lea rax, [rip + kct_bad_numbers]
    mov rcx, [rax + r12]
    mov rdx, [rax + r12 + 8]
    lea rax, [rip + kct_state]
    mov [rax + rcx], rdx
    call kct_capture
    lea rdi, [rip + kct_state]
    mov esi, 1
    mov edx, 1
    call kct_step
    call kct_unchanged
    add r12, 16
    cmp r12, 80
    jb 3b
    inc r13
    cmp r13, KC_FINISH
    jbe .Lkct_numeric_phase
    EPILOGUE

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + kct_live], rax
    mov qword ptr [rip + kct_stage], 1
    cmp qword ptr [rip + g_argc], 2
    jne kct_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz kct_fail
    cmp rdx, 8
    jb kct_fail
    mov [rip + kct_file], rax
    mov [rip + kct_filelen], rdx
    mov r12, rax
    lea r13, [rax + rdx]
    mov rcx, [rax]
    mov [rip + kct_count], rcx
    add r12, 8
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + kct_digest]
    call sha256_hash
    cmp eax, 1
    jne kct_fail
.Lkct_case:
    mov rax, [rip + kct_case]
    cmp rax, [rip + kct_count]
    jae .Lkct_cases_done
    mov qword ptr [rip + kct_stage], 2
    mov rax, r13
    sub rax, r12
    cmp rax, 56
    jb kct_fail
    mov [rip + kct_header], r12
    mov rdx, [r12]
    add r12, 56
    mov rax, r13
    sub rax, r12
    cmp rdx, rax
    ja kct_fail
    cmp rdx, KC_CAP
    ja kct_fail
    mov rdi, r12
    mov rsi, rdx
    call parse_combo
    mov [rip + kct_key], rax
    mov [rip + kct_mods], rdx
    mov rax, [rip + kct_header]
    cmp qword ptr [rax + 32], -1
    je 4f
    mov rcx, [rip + kct_key]
    cmp rcx, [rax + 32]
    jne kct_fail
    mov rcx, [rip + kct_mods]
    cmp rcx, [rax + 40]
    jne kct_fail
4:  mov qword ptr [rip + kct_before], 0x11223344
    mov qword ptr [rip + kct_after], 0x55667788
    lea rdi, [rip + kct_state]
    mov rsi, r12
    mov rax, [rip + kct_header]
    mov rdx, [rax]
    call kct_begin
    test rax, rax
    jnz kct_fail
    mov qword ptr [rip + kct_calls], 0
    mov qword ptr [rip + kct_scanned], 0
    mov qword ptr [rip + kct_tokens], 0
.Lkct_step:
    mov rax, [rip + kct_header]
    mov rsi, [rax + 8]
    test rsi, rsi
    jnz 5f
    mov rax, [rip + kct_calls]
    xor edx, edx
    mov ecx, 5
    div rcx
    lea rax, [rip + kct_byte_budgets]
    mov rsi, [rax + rdx*8]
5:  mov [rip + kct_bytes], rsi
    mov rax, [rip + kct_header]
    mov rdx, [rax + 16]
    test rdx, rdx
    jnz 6f
    mov rax, [rip + kct_calls]
    xor edx, edx
    mov ecx, 3
    div rcx
    lea rax, [rip + kct_token_budgets]
    mov rdx, [rax + rdx*8]
6:  mov [rip + kct_applications], rdx
    lea rdi, [rip + kct_state]
    call kct_step
    cmp rax, 1
    ja kct_fail
    cmp rdx, [rip + kct_bytes]
    ja kct_fail
    cmp rcx, [rip + kct_applications]
    ja kct_fail
    add [rip + kct_scanned], rdx
    add [rip + kct_tokens], rcx
    inc qword ptr [rip + kct_calls]
    cmp qword ptr [rip + kct_calls], 1000000
    ja kct_fail
    cmp qword ptr [rip + kct_before], 0x11223344
    jne kct_fail
    cmp qword ptr [rip + kct_after], 0x55667788
    jne kct_fail
    test rax, rax
    jnz .Lkct_step
    lea rdi, [rip + kct_state]
    call kct_result
    cmp rcx, 1
    jne kct_fail
    cmp rax, [rip + kct_key]
    jne kct_fail
    cmp rdx, [rip + kct_mods]
    jne kct_fail
    mov rax, [rip + kct_header]
    mov rcx, [rip + kct_tokens]
    cmp rcx, [rax + 24]
    jne kct_fail
    mov rcx, [rip + kct_scanned]
    cmp rcx, [rax + 48]
    jne kct_fail
    # Completed operations must not follow released input, even with nonempty original length.
    mov qword ptr [rip + kct_state + KC_ptr], 4096
    lea rdi, [rip + kct_state]
    mov esi, 1
    mov edx, 1
    call kct_step
    test rax, rax
    jnz kct_fail
    test rdx, rdx
    jnz kct_fail
    test rcx, rcx
    jnz kct_fail
    lea rdi, [rip + kct_state]
    call kct_result
    cmp rcx, 1
    jne kct_fail
    cmp rax, [rip + kct_key]
    jne kct_fail
    mov rax, [rip + kct_header]
    add r12, [rax]
    inc qword ptr [rip + kct_case]
    jmp .Lkct_case
.Lkct_cases_done:
    cmp r12, r13
    jne kct_fail
    mov rdi, [rip + kct_file]
    mov rsi, [rip + kct_filelen]
    lea rdx, [rip + kct_digest_after]
    call sha256_hash
    lea rdi, [rip + kct_digest]
    lea rsi, [rip + kct_digest_after]
    mov edx, 32
    call memeq
    test eax, eax
    jz kct_fail
    call kct_invalid
    mov rdi, [rip + kct_file]
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + kct_live]
    jne kct_fail
    lea rdi, [rip + kct_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + kct_ok]
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
kct_ok: .asciz "ok resumable key combinations\n"
kct_ab: .ascii "ab"
kct_hex: .ascii "0x0"
.p2align 3
kct_byte_budgets: .quad 1, 2, 3, 7, 4096
kct_token_budgets: .quad 1, 2, 16
kct_bad_budgets: .quad 0,1,4097,1,-1,1,1,0,1,17,1,-1,0x100000001,1,1,0x100000001
kct_bad_states:
    .quad KC_magic,0,KC_reserved,1,KC_phase,7,KC_len,KC_CAP+1
    .quad KC_cursor,3,KC_start,1,KC_length,1,KC_phase,KC_DONE
    .quad KC_len,0x100000002,KC_phase,0x100000000
kct_bad_numbers: .quad KC_position,0,KC_position,4,KC_kind,3,KC_position,0x100000002,KC_kind,0x100000001
kct_active_phases: .quad KC_SCAN,KC_APPLY,KC_SEPARATOR,KC_NUMERIC,KC_FINISH
