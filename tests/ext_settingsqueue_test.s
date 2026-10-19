.include "rhun.inc"
.include "app/extsettingsqueue.inc"
.include "app/extsettingsmemory.inc"
.section .rodata
sq_section: .ascii "owner/a"
sq_key: .ascii "setting.a"
sq_one: .ascii "one"
sq_two: .ascii "two"
sq_bad: .ascii "bad=key"
sq_ok: .asciz "ok owned settings queue\n"
.bss
.p2align 3
sq_delta: .zero EC_SIZE
sq_keybuf: .zero 32
sq_stage: .quad 0
sq_live: .quad 0
sq_fail_alloc: .quad 0
.text
FN main
    PROLOGUE
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
    lea rax, [rip + sq_key]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 9
    lea rax, [rip + sq_one]
    mov [r12 + EC_value], rax
    mov qword ptr [r12 + EC_vallen], 3
    mov qword ptr [rip + sq_stage], 1
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 1
    jne .Lsq_fail
    call sq_find
    test rax, rax
    jz .Lsq_fail
    cmp qword ptr [rax + EQC_seq], 1
    jne .Lsq_fail
    mov r13, rax
    # Other retained settings owners share the same hard physical allocation cap.
    call ext_settings_memory_total
    test rax, rax
    jz .Lsq_fail
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz .Lsq_fail
    call sq_put
    cmp rax, -12
    jne .Lsq_fail
    call sq_find
    cmp rax, r13
    jne .Lsq_fail
    cmp qword ptr [rbx + EQ_seq], 1
    jne .Lsq_fail
    call ext_settings_queue_create
    test rax, rax
    jnz .Lsq_fail
    cmp rdx, -12
    jne .Lsq_fail
    mov rdi, r14
    call ext_settings_memory_release
    test rax, rax
    jnz .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz .Lsq_fail
    mov r14, rax
    mov rdi, rbx
    call ext_settings_queue_discard_step
    cmp rax, -16
    jne .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_free
    cmp rax, -16
    jne .Lsq_fail
    # Newer same-key intent survives the old immutable batch acknowledgement.
    mov qword ptr [rip + sq_stage], 2
    lea rax, [rip + sq_two]
    mov [r12 + EC_value], rax
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 1
    jne .Lsq_fail
    call sq_find
    cmp qword ptr [rax + EQC_seq], 2
    jne .Lsq_fail
    mov rdi, [r13 + EC_value]
    lea rsi, [rip + sq_one]
    mov edx, 3
    call memeq
    test eax, eax
    jz .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_gc
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_free
    mov rdi, rbx
    call ext_settings_queue_gc
    cmp rax, 1
    jne .Lsq_fail
    # Acknowledged cells stay alive until batch closure, including repeated ACK.
    mov qword ptr [rip + sq_stage], 3
    mov rdi, rbx
    call ext_settings_queue_batch
    mov r14, rax
    mov rdi, r14
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 0
    jne .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_gc
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_free
    mov rdi, rbx
    call ext_settings_queue_gc
    cmp rax, 1
    jne .Lsq_fail
    # Removal never reads an ignored value pointer or length.
    mov qword ptr [rip + sq_stage], 4
    mov qword ptr [r12 + EC_remove], 1
    mov qword ptr [r12 + EC_value], -1
    mov qword ptr [r12 + EC_vallen], -1
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    call sq_find
    cmp qword ptr [rax + EC_vallen], 0
    jne .Lsq_fail
    mov r13, rax
    lea rax, [rip + sq_bad]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 7
    call sq_put
    cmp rax, -22
    jne .Lsq_fail
    lea rax, [rip + sq_key]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 9
    call sq_find
    cmp rax, r13
    jne .Lsq_fail
.ifdef TEST_SETTINGS_QUEUE_FAULT
    mov qword ptr [rip + sq_stage], 5
    mov qword ptr [rip + sq_fail_alloc], 1
    call sq_put
    cmp rax, -12
    jne .Lsq_fail
    call sq_find
    cmp rax, r13
    jne .Lsq_fail
    mov qword ptr [rip + sq_fail_alloc], 1
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jnz .Lsq_fail
    cmp rdx, -12
    jne .Lsq_fail
    cmp qword ptr [rbx + EQ_batch], 0
    jne .Lsq_fail
.endif
    # Exhausted serials and allocation caps leave accepted intent unchanged.
    mov qword ptr [rip + sq_stage], 6
    mov r15, [rbx + EQ_seq]
    mov rax, 0x7fffffffffffffff
    mov [rbx + EQ_seq], rax
    call sq_put
    cmp rax, -75
    jne .Lsq_fail
    mov [rbx + EQ_seq], r15
    mov r15, [rbx + EQ_charge]
    mov qword ptr [rbx + EQ_charge], EQ_CAP
    call sq_put
    cmp rax, -27
    jne .Lsq_fail
    mov [rbx + EQ_charge], r15
    call sq_clear
    # Exactly512 distinct keys, then full; oldest128 batch remains immutable.
    mov qword ptr [rip + sq_stage], 7
    mov qword ptr [r12 + EC_remove], 0
    lea rax, [rip + sq_one]
    mov [r12 + EC_value], rax
    mov qword ptr [r12 + EC_vallen], 3
    xor r15d, r15d
1:  lea rdi, [rip + sq_keybuf]
    mov rsi, r15
    call fmt_u64
    mov [r12 + EC_keylen], rax
    lea rax, [rip + sq_keybuf]
    mov [r12 + EC_key], rax
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    inc r15
    cmp r15, EQ_MAX
    jb 1b
    cmp qword ptr [rbx + EQ_count], EQ_MAX
    jne .Lsq_fail
    lea rdi, [rip + sq_keybuf]
    mov esi, EQ_MAX
    call fmt_u64
    mov [r12 + EC_keylen], rax
    call sq_put
    cmp rax, -28
    jne .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz .Lsq_fail
    mov r14, rax
    cmp qword ptr [r14 + EQB_count], EC_BATCH
    jne .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jnz .Lsq_fail
    cmp rdx, -16
    jne .Lsq_fail
    # Rewrite key0 after capture. ACK removes127, leaving385.
    lea rdi, [rip + sq_keybuf]
    xor esi, esi
    call fmt_u64
    mov [r12 + EC_keylen], rax
    lea rax, [rip + sq_two]
    mov [r12 + EC_value], rax
    call sq_put
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_ack
    test rax, rax
    jnz .Lsq_fail
    cmp qword ptr [rbx + EQ_count], 385
    jne .Lsq_fail
    mov rdi, rbx
    call ext_settings_queue_gc
    test rax, rax
    jnz .Lsq_fail
    mov rdi, r14
    call ext_settings_batch_free
    mov qword ptr [rip + sq_stage], 8
    call sq_clear
    cmp qword ptr [rbx + EQ_payload], 0
    jne .Lsq_fail
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
    lea rdi, [rip + sq_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lsq_fail:
    mov rdi, [rip + sq_stage]
    add edi, 30
    jmp sys_exit

sq_put:
    mov rdi, rbx
    mov rsi, r12
    jmp ext_settings_queue_put
sq_find:
    mov rdi, rbx
    mov rsi, [r12 + EC_section]
    mov rdx, [r12 + EC_seclen]
    mov rcx, [r12 + EC_key]
    mov r8, [r12 + EC_keylen]
    jmp ext_settings_queue_find
sq_clear:
    PROLOGUE
    mov r12d, 8
1:  mov rdi, rbx
    call ext_settings_queue_discard_step
    test rax, rax
    js .Lsq_fail
    dec r12
    jnz 1b
2:  mov rdi, rbx
    call ext_settings_queue_gc
    cmp qword ptr [rbx + EQ_retired_count], 0
    jne 2b
    EPILOGUE

.ifdef TEST_SETTINGS_QUEUE_FAULT
FN sq_alloc
    cmp qword ptr [rip + sq_fail_alloc], 0
    je 1f
    mov qword ptr [rip + sq_fail_alloc], 0
    xor eax, eax
    ret
1:  jmp ext_settings_memory_try
.endif
