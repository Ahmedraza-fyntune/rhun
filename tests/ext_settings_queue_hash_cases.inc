# Independent cache audit, genuine full-hash collision, and counted lookup work.
.bss
.p2align 3
.globl qh_force_zero
.globl qh_counting
.globl qh_bytes
qh_force_zero: .quad 0
qh_counting: .quad 0
qh_bytes: .quad 0
qh_old: .quad 0
qh_batch: .quad 0
qh_longkey: .zero 256
.section .rodata
qh_a: .ascii "a3"
qh_b: .ascii "bP"
qh_section:
.ascii "oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo/nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn"
qh_ok: .asciz "ok queue identity cache, collisions and bounded comparison work\n"
.text
# Reference recurrence deliberately uses integer multiplication instead of shifts.
# Valid owned EC input only. Test forcing zero mirrors a valid zero-hash algorithm.
qh_reference:
    cmp qword ptr [rip + qh_force_zero], 0
    jne .Lqhr_zero
    mov eax, 5381
    mov r8, [rdi + EC_section]
    mov r9, [rdi + EC_seclen]
    xor ecx, ecx
1:  imul rax, rax, 33
    movzx edx, byte ptr [r8 + rcx]
    xor rax, rdx
    inc rcx
    cmp rcx, r9
    jb 1b
    imul rax, rax, 33
    xor rax, r9
    imul rax, rax, 33
    xor rax, 255
    mov r8, [rdi + EC_key]
    mov r9, [rdi + EC_keylen]
    xor ecx, ecx
2:  imul rax, rax, 33
    movzx edx, byte ptr [r8 + rcx]
    xor rax, rdx
    inc rcx
    cmp rcx, r9
    jb 2b
    imul rax, rax, 33
    xor rax, r9
    ret
.Lqhr_zero:
    xor eax, eax
    ret

# Audit every live and retired cell, including cells retained by immutable batches.
qh_audit:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  imul rax, r12, EQ_SLOT
    mov r13, [rbx + EQ_slots + rax + EQS_cell]
    test r13, r13
    jz 2f
    mov rdi, r13
    call qh_reference
    cmp [r13 + EQC_hash], rax
    jne .Lqha_bad
2:  inc r12
    cmp r12, EQ_MAX
    jb 1b
    mov r12, [rbx + EQ_retired_count]
    mov r13, [rbx + EQ_retired]
3:  test r12, r12
    jz 4f
    test r13, r13
    jz .Lqha_bad
    mov rdi, r13
    call qh_reference
    cmp [r13 + EQC_hash], rax
    jne .Lqha_bad
    mov r13, [r13 + EQC_next]
    dec r12
    jmp 3b
4:  test r13, r13
    jnz .Lqha_bad
    xor eax, eax
    EPILOGUE
.Lqha_bad:
    mov rax, -22
    EPILOGUE
qh_check:
    PROLOGUE
    mov rdi, rbx
    call qh_audit
    test rax, rax
    jnz .Lsq_fail
    EPILOGUE
qh_key_a:
    lea rax, [rip + qh_a]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 2
    ret
qh_key_b:
    lea rax, [rip + qh_b]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 2
    ret
qh_ack_all:
    PROLOGUE
    mov rbx, rdi
    call ext_settings_queue_batch
    test rax, rax
    jz .Lsq_fail
    mov r12, rax
    mov rdi, rax
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r12
    call ext_settings_batch_free
    mov rdi, rbx
    call ext_settings_queue_gc
    EPILOGUE

FN main
    PROLOGUE
    mov qword ptr [rip + sq_stage], 10
    mov rax, [rip + g_mem_live]
    mov [rip + sq_live], rax
    call ext_settings_queue_create
    test rax, rax
    jz .Lsq_fail
    mov rbx, rax
    lea r12, [rip + sq_delta]
    lea rax, [rip + sq_section]
    mov [r12 + EC_section], rax
    mov qword ptr [r12 + EC_seclen], 7
    lea rax, [rip + sq_one]
    mov [r12 + EC_value], rax
    mov qword ptr [r12 + EC_vallen], 3
    call qh_key_a
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    mov rcx, 0xa4656e1be0bd3dc2
    cmp rdx, rcx
    jne .Lsq_fail
    cmp [rax + EQC_hash], rcx
    jne .Lsq_fail
    mov [rip + qh_old], rax
    call qh_check
    # Independently injected stale/missing caches must fail the audit.
    mov rax, [rip + qh_old]
    xor qword ptr [rax + EQC_hash], 1
    mov rdi, rbx
    call qh_audit
    cmp rax, -22
    jne .Lsq_fail
    mov rax, [rip + qh_old]
    xor qword ptr [rax + EQC_hash], 1
    call qh_check
    call qh_key_b
    lea rax, [rip + sq_two]
    mov [r12 + EC_value], rax
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 2
    jne .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    cmp rax, [rip + qh_old]
    je .Lsq_fail
    mov rcx, 0xa4656e1be0bd3dc2
    cmp rdx, rcx
    jne .Lsq_fail
    cmp [rax + EQC_hash], rcx
    jne .Lsq_fail
    # Values are copied owned spans, not the source pointers.
    mov rdi, [rax + EC_value]
    lea rsi, [rip + sq_two]
    mov edx, 3
    call memeq
    test eax, eax
    jz .Lsq_fail
    call qh_check
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz .Lsq_fail
    cmp qword ptr [rax + EQB_count], 2
    jne .Lsq_fail
    mov [rip + qh_batch], rax
    # Rewrite only a3. Both identities have the same section, lengths and hash.
    mov qword ptr [rip + sq_stage], 11
    call qh_key_a
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 2
    jne .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    cmp rax, [rip + qh_old]
    je .Lsq_fail
    cmp qword ptr [rax + EQC_seq], 3
    jne .Lsq_fail
    call qh_check
    mov rax, [rip + qh_old]
    mov qword ptr [rax + EQC_hash], 0
    mov rdi, rbx
    call qh_audit
    cmp rax, -22
    jne .Lsq_fail
    mov rax, [rip + qh_old]
    mov rcx, 0xa4656e1be0bd3dc2
    mov [rax + EQC_hash], rcx
    call qh_check
    mov rdi, [rip + qh_batch]
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    mov rdi, [rip + qh_batch]
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 1
    jne .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    cmp qword ptr [rax + EQC_seq], 3
    jne .Lsq_fail
    call qh_key_b
    call sq_find
    test rax, rax
    jnz .Lsq_fail
    mov rcx, 0xa4656e1be0bd3dc2
    cmp rdx, rcx
    jne .Lsq_fail
    mov rax, [rip + qh_old]
    mov rdi, [rax + EC_value]
    lea rsi, [rip + sq_one]
    mov edx, 3
    call memeq
    test eax, eax
    jz .Lsq_fail
    call qh_check
    mov rdi, [rip + qh_batch]
    call ext_settings_batch_free
    mov rdi, rbx
    call ext_settings_queue_gc
    cmp qword ptr [rbx + EQ_retired_count], 0
    jne .Lsq_fail
    mov rdi, rbx
    call qh_ack_all
    cmp qword ptr [rbx + EQ_count], 0
    jne .Lsq_fail
    # Reuse a previously occupied slot for a distinct identity and fresh cache.
    mov qword ptr [rip + sq_stage], 12
    lea rax, [rip + sq_key]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 9
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    mov rcx, 0x0b3c02cb1a444842
    cmp rdx, rcx
    jne .Lsq_fail
    cmp [rax + EQC_hash], rcx
    jne .Lsq_fail
    call qh_check
    call qh_key_a
    call sq_find
    test rax, rax
    jnz .Lsq_fail
    mov rdi, rbx
    call qh_ack_all
    # Invalid bounds are refused before dereferencing deliberately invalid bytes.
    mov qword ptr [rip + sq_stage], 13
    mov edi, 1
    mov esi, 1025
    mov edx, 1
    mov ecx, 1
    call ext_settings_queue_identity_hash
    test rax, rax
    jnz .Lsq_fail
    cmp rdx, -22
    jne .Lsq_fail
    mov edi, 1
    mov esi, 1
    mov edx, 1
    mov ecx, 257
    call ext_settings_queue_identity_hash
    cmp rdx, -22
    jne .Lsq_fail
    xor edi, edi
    mov esi, 1
    mov edx, 1
    mov ecx, 1
    call ext_settings_queue_identity_hash
    cmp rdx, -22
    jne .Lsq_fail
    mov edi, 1
    xor esi, esi
    mov edx, 1
    mov ecx, 1
    call ext_settings_queue_identity_hash
    cmp rdx, -22
    jne .Lsq_fail
    mov edi, 1
    mov esi, 1
    xor edx, edx
    mov ecx, 1
    call ext_settings_queue_identity_hash
    cmp rdx, -22
    jne .Lsq_fail
    mov edi, 1
    mov esi, 1
    mov edx, 1
    xor ecx, ecx
    call ext_settings_queue_identity_hash
    cmp rdx, -22
    jne .Lsq_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 1025
    mov ecx, 1
    mov r8d, 1
    call ext_settings_queue_find
    test rax, rax
    jnz .Lsq_fail
    test rdx, rdx
    jnz .Lsq_fail
    xor edi, edi
    mov esi, 1
    mov edx, 1
    mov ecx, 1
    mov r8d, 1
    call ext_settings_queue_find
    test rax, rax
    jnz .Lsq_fail
    test rdx, rdx
    jnz .Lsq_fail
    # Hash zero is an ordinary filter value, still requiring exact identity.
    mov qword ptr [rip + sq_stage], 14
    mov qword ptr [rip + qh_force_zero], 1
    call qh_key_a
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    call qh_key_b
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 2
    jne .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    test rdx, rdx
    jnz .Lsq_fail
    call qh_key_a
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 2
    jne .Lsq_fail
    call qh_check
    mov rdi, rbx
    call qh_ack_all
    mov qword ptr [rip + qh_force_zero], 0
    # Full512 long sections/maximal256-byte keys. Constructor copies the buffer.
    mov qword ptr [rip + sq_stage], 15
    lea rdi, [rip + qh_longkey]
    mov esi, 'k'
    mov edx, 253
    call memset
    lea rax, [rip + qh_section]
    mov [r12 + EC_section], rax
    mov qword ptr [r12 + EC_seclen], 201
    lea rax, [rip + qh_longkey]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 256
    xor r15d, r15d
.Lqh_fill:
    call qh_numeric
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    inc r15
    cmp r15, EQ_MAX
    jb .Lqh_fill
    cmp qword ptr [rbx + EQ_count], EQ_MAX
    jne .Lsq_fail
    call qh_check
    call qh_numeric
    call sq_put
    cmp rax, -28
    jne .Lsq_fail
    # Count exact requested comparison bytes, with no wall-clock CI threshold.
    mov qword ptr [rip + sq_stage], 16
    mov qword ptr [rip + qh_bytes], 0
    mov qword ptr [rip + qh_counting], 1
    xor r15d, r15d
.Lqh_read:
    call qh_numeric
    call sq_find
    test rax, rax
    jz .Lsq_fail
    inc r15
    cmp r15, EQ_MAX
    jb .Lqh_read
    mov qword ptr [rip + qh_counting], 0
    # Allow real collisions without masking a full unfiltered long-span scan.
    cmp qword ptr [rip + qh_bytes], EQ_MAX * 457 * 4
    ja .Lsq_fail
    cmp qword ptr [rip + qh_bytes], EQ_MAX * 457
    jb .Lsq_fail
    call qh_check
    call sq_clear
    mov rdi, rbx
    call ext_settings_queue_free
    test rax, rax
    jnz .Lsq_fail
    call ext_settings_memory_total
    test rax, rax
    jnz .Lsq_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + sq_live]
    jne .Lsq_fail
    # Existing permanent baseline covers cap/allocator/serial refusal and ACKs.
    call original_settings_queue_main
    test rax, rax
    jnz .Lsq_fail
    lea rdi, [rip + qh_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE

# R15 in0..512 -> fixed-width decimal suffix; preserve all callee-saved state.
qh_numeric:
    mov rax, r15
    xor edx, edx
    mov ecx, 100
    div rcx
    add al, '0'
    mov byte ptr [rip + qh_longkey + 253], al
    mov rax, rdx
    xor edx, edx
    mov ecx, 10
    div rcx
    add al, '0'
    add dl, '0'
    mov byte ptr [rip + qh_longkey + 254], al
    mov byte ptr [rip + qh_longkey + 255], dl
    ret
