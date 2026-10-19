# Pure owned intent queue. UI integration and helper transport are separate layers.
.include "rhun.inc"
.include "app/extsettingsqueue.inc"
.text
# create()->queue or0,RDX error. Epoch starts at1 and never wraps.
FN ext_settings_queue_create
    PROLOGUE
    mov edi, EQ_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz 1f
    mov rbx, rax
    mov qword ptr [rbx + EQ_epoch], 1
    mov qword ptr [rbx + EQ_head], -1
    mov qword ptr [rbx + EQ_tail], -1
    mov edi, EQ_SIZE
    call prep_alloc_charge
    mov [rbx + EQ_charge], rax
    mov rax, rbx
    xor edx, edx
    EPILOGUE
1:  xor eax, eax
    mov rdx, -12
    EPILOGUE

# find(queue,section,seclen,key,keylen)->borrowed current cell or0.
FN ext_settings_queue_find
    PROLOGUE 48
    mov rbx, rdi
    test rbx, rbx
    jz .Leqf_invalid
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    call ext_settings_queue_identity_hash
    test rdx, rdx
    jnz .Leqf_invalid
    mov [rsp + 32], rax
    xor r12d, r12d
1:  cmp r12, EQ_MAX
    jae 4f
    imul rax, r12, EQ_SLOT
    mov r13, [rbx + rax + EQ_slots + EQS_cell]
    test r13, r13
    jz 3f
    mov rax, [rsp + 32]
    cmp [r13 + EQC_hash], rax
    jne 3f
    mov rax, [rsp + 8]
    cmp [r13 + EC_seclen], rax
    jne 3f
    mov rax, [rsp + 24]
    cmp [r13 + EC_keylen], rax
    jne 3f
    mov rdi, [r13 + EC_section]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call memeq
    test eax, eax
    jz 3f
    mov rdi, [r13 + EC_key]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call memeq
    test eax, eax
    jnz 5f
3:  inc r12
    jmp 1b
4:  xor eax, eax
    mov rdx, [rsp + 32]
    EPILOGUE
5:  mov rax, r13
    mov rdx, [rsp + 32]
    EPILOGUE
.Leqf_invalid:
    xor eax, eax
    xor edx, edx
    EPILOGUE

# Internal stable-slot unlink. No ownership or allocation changes.
eq_unlink:
    imul rax, rsi, EQ_SLOT
    lea rax, [rdi + rax + EQ_slots]
    mov rcx, [rax + EQS_prev]
    mov rdx, [rax + EQS_next]
    test rcx, rcx
    js 1f
    imul r8, rcx, EQ_SLOT
    mov [rdi + r8 + EQ_slots + EQS_next], rdx
    jmp 2f
1:  mov [rdi + EQ_head], rdx
2:  test rdx, rdx
    js 3f
    imul r8, rdx, EQ_SLOT
    mov [rdi + r8 + EQ_slots + EQS_prev], rcx
    ret
3:  mov [rdi + EQ_tail], rcx
    ret

# Append retired cell, transferring the queue reference without freeing bytes.
eq_retire:
    mov qword ptr [rsi + EQC_next], 0
    mov rax, [rdi + EQ_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + EQC_next], rsi
    jmp 2f
1:  mov [rdi + EQ_retired], rsi
2:  mov [rdi + EQ_retired_tail], rsi
    inc qword ptr [rdi + EQ_retired_count]
    ret

# put(queue,EC*)->0/-errno. Validate and own all bytes before replacing intent.
FN ext_settings_queue_put
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    # Known native identity and schema keys are small; cap lookup byte work.
    cmp qword ptr [r12 + EC_seclen], 1024
    ja .Leqp_large
    cmp qword ptr [r12 + EC_keylen], 256
    ja .Leqp_large
    mov rdi, r12
    call ext_choices_validate_delta
    test rax, rax
    js .Leqp_done
    cmp qword ptr [rbx + EQ_epoch], 0
    je .Leqp_overflow
    mov rax, 0x7fffffffffffffff
    cmp [rbx + EQ_seq], rax
    jae .Leqp_overflow
    cmp [rbx + EQ_epoch], rax
    jae .Leqp_overflow
    mov rdi, rbx
    mov rsi, [r12 + EC_section]
    mov rdx, [r12 + EC_seclen]
    mov rcx, [r12 + EC_key]
    mov r8, [r12 + EC_keylen]
    call ext_settings_queue_find
    mov [rsp + 40], rdx
    mov r13, rax
    mov r14, -1
    xor ecx, ecx
1:  cmp rcx, EQ_MAX
    jae .Leqp_slots_done
    imul rdx, rcx, EQ_SLOT
    mov rax, [rbx + rdx + EQ_slots + EQS_cell]
    test r13, r13
    jz 2f
    cmp rax, r13
    je 3f
    jmp 4f
2:  test rax, rax
    jz 3f
4:  inc rcx
    jmp 1b
3:  mov r14, rcx
.Leqp_slots_done:
    test r14, r14
    js .Leqp_full
    mov r15, [r12 + EC_seclen]
    add r15, [r12 + EC_keylen]
    jc .Leqp_large
    xor eax, eax
    cmp qword ptr [r12 + EC_remove], 0
    jne 5f
    mov rax, [r12 + EC_vallen]
5:  add r15, rax
    jc .Leqp_large
    mov rdx, [rbx + EQ_payload]
    test r13, r13
    jz 6f
    sub rdx, [r13 + EC_seclen]
    sub rdx, [r13 + EC_keylen]
    sub rdx, [r13 + EC_vallen]
6:  add rdx, r15
    jc .Leqp_large
    cmp rdx, EC_LIMIT
    ja .Leqp_large
    mov [rsp], rdx            # resulting current payload
    lea rdi, [r15 + EQC_SIZE + 3]
    call prep_alloc_charge
    test rax, rax
    jz .Leqp_large
    mov [rsp + 8], rax
    add rax, [rbx + EQ_charge]
    jc .Leqp_large
    cmp rax, EQ_CAP
    ja .Leqp_large
    lea rdi, [r15 + EQC_SIZE + 3]
    call ext_settings_memory_try
    test rax, rax
    jz .Leqp_oom
    mov [rsp + 16], rax
    mov rdx, [rsp + 8]
    mov [rax + EQC_charge], rdx
    mov qword ptr [rax + EQC_refs], 1
    mov rdx, [rbx + EQ_seq]
    inc rdx
    mov [rax + EQC_seq], rdx
    mov rdx, [rsp + 40]
    mov [rax + EQC_hash], rdx
    mov rdx, [r12 + EC_remove]
    mov [rax + EC_remove], rdx
    lea r15, [rax + EQC_SIZE]
    mov [rax + EC_section], r15
    mov rdx, [r12 + EC_seclen]
    mov [rax + EC_seclen], rdx
    mov rdi, r15
    mov rsi, [r12 + EC_section]
    call memcpy
    add r15, [r12 + EC_seclen]
    inc r15
    mov rax, [rsp + 16]
    mov [rax + EC_key], r15
    mov rdx, [r12 + EC_keylen]
    mov [rax + EC_keylen], rdx
    mov rdi, r15
    mov rsi, [r12 + EC_key]
    call memcpy
    add r15, [r12 + EC_keylen]
    inc r15
    mov rax, [rsp + 16]
    mov [rax + EC_value], r15
    cmp qword ptr [r12 + EC_remove], 0
    jne .Leqp_publish
    mov rdx, [r12 + EC_vallen]
    mov [rax + EC_vallen], rdx
    mov rdi, r15
    mov rsi, [r12 + EC_value]
    call memcpy
.Leqp_publish:
    test r13, r13
    jz 7f
    mov rdi, rbx
    mov rsi, r14
    call eq_unlink
    mov rdi, rbx
    mov rsi, r13
    call eq_retire
    jmp 8f
7:  inc qword ptr [rbx + EQ_count]
8:  imul rax, r14, EQ_SLOT
    lea rax, [rbx + rax + EQ_slots]
    mov rcx, [rsp + 16]
    mov [rax + EQS_cell], rcx
    mov qword ptr [rax + EQS_next], -1
    mov rdx, [rbx + EQ_tail]
    mov [rax + EQS_prev], rdx
    test rdx, rdx
    js 9f
    imul rdx, rdx, EQ_SLOT
    mov [rbx + rdx + EQ_slots + EQS_next], r14
    jmp 10f
9:  mov [rbx + EQ_head], r14
10: mov [rbx + EQ_tail], r14
    mov rax, [rsp]
    mov [rbx + EQ_payload], rax
    mov rax, [rsp + 8]
    add [rbx + EQ_charge], rax
    inc qword ptr [rbx + EQ_seq]
    inc qword ptr [rbx + EQ_epoch]
    xor eax, eax
.Leqp_done:
    EPILOGUE
.Leqp_oom:
    mov rax, -12
    EPILOGUE
.Leqp_large:
    mov rax, -27
    EPILOGUE
.Leqp_full:
    mov rax, -28
    EPILOGUE
.Leqp_overflow:
    mov rax, -75
    EPILOGUE

# batch(queue)->owned batch or0,RDXerror. Oldest fields first, at most128.
FN ext_settings_queue_batch
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EQ_batch], 0
    jne .Leqb_busy
    cmp qword ptr [rbx + EQ_count], 0
    je .Leqb_empty
    mov edi, EQB_SIZE
    call prep_alloc_charge
    mov r12, rax
    add rax, [rbx + EQ_charge]
    jc .Leqb_large
    cmp rax, EQ_CAP
    ja .Leqb_large
    mov edi, EQB_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Leqb_oom
    mov r13, rax
    mov [rax + EQB_queue], rbx
    mov [rax + EQB_charge], r12
    add [rbx + EQ_charge], r12
    mov [rbx + EQ_batch], r13
    mov r14, [rbx + EQ_head]
    xor r15d, r15d
1:  test r14, r14
    js 2f
    cmp r15, EC_BATCH
    jae 2f
    imul rax, r14, EQ_SLOT
    lea rcx, [rbx + rax + EQ_slots]
    mov rdx, [rcx + EQS_cell]
    imul rax, r15, EQB_ROW
    mov [r13 + rax + EQB_rows + EQBR_slot], r14
    mov [r13 + rax + EQB_rows + EQBR_cell], rdx
    mov rsi, [rdx + EQC_seq]
    mov [r13 + rax + EQB_rows + EQBR_seq], rsi
    inc qword ptr [rdx + EQC_refs]
    inc r15
    mov r14, [rcx + EQS_next]
    jmp 1b
2:  mov [r13 + EQB_count], r15
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Leqb_busy:
    mov rdx, -16
    jmp .Leqb_error
.Leqb_empty:
    mov rdx, -11
    jmp .Leqb_error
.Leqb_large:
    mov rdx, -27
    jmp .Leqb_error
.Leqb_oom:
    mov rdx, -12
.Leqb_error:
    xor eax, eax
    EPILOGUE

# Checked convenience wrapper. Composite callers use explicit check+VOID publish.
FN ext_settings_batch_ack
    PROLOGUE
    mov rbx, rdi
    call ext_settings_batch_ack_check
    test rax, rax
    jnz 1f
    mov rdi, rbx
    call ext_settings_batch_ack_publish
    xor eax, eax
1:  EPILOGUE

# VOID, immediately after complete composite preflight, no intervening mutation.
# Fixed <=128 slot/sequence actions, no lookup, normalization, allocation or free.
FN ext_settings_batch_ack_publish
    PROLOGUE
    mov r12, rdi
    mov rbx, [r12 + EQB_queue]
    xor r13d, r13d
    xor r15d, r15d
1:  cmp r13, [r12 + EQB_count]
    jae 4f
    imul rax, r13, EQB_ROW
    lea r14, [r12 + rax + EQB_rows]
    mov rsi, [r14 + EQBR_slot]
    imul rax, rsi, EQ_SLOT
    lea r14, [rbx + rax + EQ_slots]
    mov rdx, [r14 + EQS_cell]
    test rdx, rdx
    jz 3f
    imul rax, r13, EQB_ROW
    mov rcx, [r12 + rax + EQB_rows + EQBR_seq]
    cmp [rdx + EQC_seq], rcx
    jne 3f
    mov rdi, rbx
    call eq_unlink
    mov rsi, [r14 + EQS_cell]
    mov qword ptr [r14 + EQS_cell], 0
    mov rax, [rsi + EC_seclen]
    add rax, [rsi + EC_keylen]
    add rax, [rsi + EC_vallen]
    sub [rbx + EQ_payload], rax
    dec qword ptr [rbx + EQ_count]
    mov rdi, rbx
    call eq_retire
    mov r15d, 1
3:  inc r13
    jmp 1b
4:  test r15d, r15d
    jz 5f
    inc qword ptr [rbx + EQ_epoch]
5:  xor eax, eax
    EPILOGUE

FN ext_settings_batch_free
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + EQB_queue]
    xor r13d, r13d
1:  cmp r13, [rbx + EQB_count]
    jae 2f
    imul rax, r13, EQB_ROW
    mov rax, [rbx + rax + EQB_rows + EQBR_cell]
    dec qword ptr [rax + EQC_refs]
    inc r13
    jmp 1b
2:  mov rax, [rbx + EQB_charge]
    sub [r12 + EQ_charge], rax
    mov qword ptr [r12 + EQ_batch], 0
    mov rdi, rbx
    call ext_settings_memory_free
    EPILOGUE

# gc(queue)->ownership units retired,RDX first cleanup. At most64 examined.
FN ext_settings_queue_gc
    PROLOGUE 16
    mov rbx, rdi
    mov r12, [rbx + EQ_retired_count]
    cmp r12, 64
    jbe 1f
    mov r12d, 64
1:  xor r13d, r13d
    xor r15d, r15d
2:  test r12, r12
    jz 6f
    dec r12
    mov r14, [rbx + EQ_retired]
    mov rax, [r14 + EQC_next]
    mov [rbx + EQ_retired], rax
    test rax, rax
    jnz 3f
    mov qword ptr [rbx + EQ_retired_tail], 0
3:  dec qword ptr [rbx + EQ_retired_count]
    cmp qword ptr [r14 + EQC_refs], 1
    je 4f
    mov rdi, rbx
    mov rsi, r14
    call eq_retire
    jmp 2b
4:  mov rax, [r14 + EQC_charge]
    mov [rsp], rax
    mov rdi, r14
    call ext_settings_memory_free
    cmp rcx, 1
    jne 7f
    mov rax, [rsp]
    sub [rbx + EQ_charge], rax
    test rdx, rdx
    jns 5f
    test r15, r15
    jnz 5f
    mov r15, rdx
5:  inc r13
    jmp 2b
7:  mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    call eq_retire
6:  mov rax, r13
    mov rdx, r15
    EPILOGUE

# discard_step(queue)->remaining current fields, <=64 stable slots examined.
# Explicit user discard/teardown only. Never called for an ambiguous commit.
FN ext_settings_queue_discard_step
    cmp qword ptr [rdi + EQ_batch], 0
    jne .Leqd_busy
    PROLOGUE
    mov rbx, rdi
    xor r15d, r15d
    xor r12d, r12d
1:  cmp r12, 64
    jae 4f
    mov r13, [rbx + EQ_cursor]
    lea rax, [r13 + 1]
    and eax, EQ_MAX - 1
    mov [rbx + EQ_cursor], rax
    imul rax, r13, EQ_SLOT
    lea r14, [rbx + rax + EQ_slots]
    cmp qword ptr [r14 + EQS_cell], 0
    je 3f
    mov rdi, rbx
    mov rsi, r13
    call eq_unlink
    mov rsi, [r14 + EQS_cell]
    mov qword ptr [r14 + EQS_cell], 0
    mov rax, [rsi + EC_seclen]
    add rax, [rsi + EC_keylen]
    add rax, [rsi + EC_vallen]
    sub [rbx + EQ_payload], rax
    dec qword ptr [rbx + EQ_count]
    mov rdi, rbx
    call eq_retire
    mov r15d, 1
3:  inc r12
    jmp 1b
4:  test r15d, r15d
    jz 5f
    cmp qword ptr [rbx + EQ_epoch], 0
    je 5f
    mov rax, 0x7fffffffffffffff
    cmp [rbx + EQ_epoch], rax
    jae 6f
    inc qword ptr [rbx + EQ_epoch]
    jmp 5f
6:  mov qword ptr [rbx + EQ_epoch], 0
5:  mov rax, [rbx + EQ_count]
    EPILOGUE
.Leqd_busy:
    mov rax, -16
    ret

# free(queue)->0/-EBUSY; no implicit discard, batch release or unbounded GC.
FN ext_settings_queue_free
    cmp qword ptr [rdi + EQ_count], 0
    jne 1f
    cmp qword ptr [rdi + EQ_batch], 0
    jne 1f
    cmp qword ptr [rdi + EQ_retired], 0
    jne 1f
    PROLOGUE
    call ext_settings_memory_free
    EPILOGUE
1:  mov rax, -16
    ret
