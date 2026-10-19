.bss
.p2align 3
.globl qa_poison
.globl qa_publish_guard
qa_poison: .quad 0
qa_publish_guard: .quad 0
qa_once: .quad 0
qa_stage: .quad 0
qa_qcopy: .zero EQ_SIZE
qa_bcopy: .zero EQB_SIZE
.text
.globl qa_pure_fail
qa_pure_fail:
    mov edi, 78
    jmp sys_exit
qa_fail:
    mov rdi, [rip + qa_stage]
    jmp sys_exit
# batch,expected -> exact result and byte-for-byte no mutation to queue/batch.
qa_expect:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + EQB_queue]
    lea rdi, [rip + qa_qcopy]
    mov rsi, r13
    mov edx, EQ_SIZE
    call memcpy
    lea rdi, [rip + qa_bcopy]
    mov rsi, rbx
    mov edx, EQB_SIZE
    call memcpy
    mov qword ptr [rip + qa_poison], 1
    mov rdi, rbx
    call ext_settings_batch_ack_check
    mov qword ptr [rip + qa_poison], 0
    cmp rax, r12
    jne qa_fail
    lea rdi, [rip + qa_qcopy]
    mov rsi, r13
    mov edx, EQ_SIZE
    call memeq
    test eax, eax
    jz qa_fail
    lea rdi, [rip + qa_bcopy]
    mov rsi, rbx
    mov edx, EQB_SIZE
    call memeq
    test eax, eax
    jz qa_fail
    EPILOGUE
qa_faults:
    PROLOGUE 32
    mov r12, rdi
    mov rbx, [r12 + EQB_queue]
    mov qword ptr [rip + qa_stage], 70
    xor esi, esi
    call qa_expect
    mov rax, [rbx + EQ_epoch]
    mov [rsp], rax
    mov qword ptr [rip + qa_stage], 71
    mov qword ptr [rbx + EQ_epoch], 0
    mov rdi, r12
    mov rsi, -75
    call qa_expect
    mov rax, 0x7fffffffffffffff
    mov [rbx + EQ_epoch], rax
    mov rdi, r12
    mov rsi, -75
    call qa_expect
    mov rax, [rsp]
    mov [rbx + EQ_epoch], rax
    mov qword ptr [rip + qa_stage], 72
    mov qword ptr [rbx + EQ_batch], 0
    mov rdi, r12
    mov rsi, -116
    call qa_expect
    mov [rbx + EQ_batch], r12
    mov qword ptr [rip + qa_stage], 73
    mov rax, [r12 + EQB_count]
    mov [rsp], rax
    mov qword ptr [r12 + EQB_count], 0
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov qword ptr [r12 + EQB_count], EC_BATCH + 1
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov rax, [rsp]
    mov [r12 + EQB_count], rax
    mov qword ptr [rip + qa_stage], 74
    mov rax, [r12 + EQB_rows + EQBR_slot]
    mov [rsp], rax
    mov qword ptr [r12 + EQB_rows + EQBR_slot], EQ_MAX
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov rax, [rsp]
    mov [r12 + EQB_rows + EQBR_slot], rax
    mov qword ptr [rip + qa_stage], 75
    mov rax, [r12 + EQB_rows + EQBR_seq]
    mov [rsp], rax
    mov qword ptr [r12 + EQB_rows + EQBR_seq], 0
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov rax, [rbx + EQ_seq]
    inc rax
    mov [r12 + EQB_rows + EQBR_seq], rax
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov rax, [rsp]
    mov [r12 + EQB_rows + EQBR_seq], rax
    mov qword ptr [rip + qa_stage], 76
    mov rax, [rbx + EQ_seq]
    mov [rsp], rax
    mov qword ptr [rbx + EQ_seq], 0
    mov rdi, r12
    mov rsi, -22
    call qa_expect
    mov rax, 0x7fffffffffffffff
    mov [rbx + EQ_seq], rax
    mov rdi, r12
    xor esi, esi
    call qa_expect
    mov rax, [rsp]
    mov [rbx + EQ_seq], rax
    EPILOGUE
# The original full queue fixture now publishes with this explicit checked pair.
qa_pair:
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rip + qa_once], 0
    jne 1f
    mov qword ptr [rip + qa_once], 1
    call qa_faults
1:  mov qword ptr [rip + qa_stage], 77
    mov rdi, rbx
    xor esi, esi
    call qa_expect
    mov r12, [rbx + EQB_queue]
    mov rax, [r12 + EQ_epoch]
    mov [rsp], rax
    mov rax, [r12 + EQ_count]
    mov [rsp + 8], rax
    mov qword ptr [rip + qa_poison], 1
    mov qword ptr [rip + qa_publish_guard], 1
    mov rdi, rbx
    call ext_settings_batch_ack_publish
    mov qword ptr [rip + qa_publish_guard], 0
    mov qword ptr [rip + qa_poison], 0
    mov rax, [rsp]
    mov rcx, [rsp + 8]
    cmp [r12 + EQ_count], rcx
    je 2f
    inc rax
2:  cmp [r12 + EQ_epoch], rax
    jne qa_fail
    xor eax, eax
    EPILOGUE
