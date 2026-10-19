# Pure preflight for fixed-slot dirty acknowledgement in a composite publication.
.include "rhun.inc"
.include "app/extsettingsqueue.inc"
.text
# Owned immutable active batch ->0/-errno. No object or global mutation.
FN ext_settings_batch_ack_check
    PROLOGUE
    mov r12, rdi
    test r12, r12
    jz .Lqac_invalid
    mov rbx, [r12 + EQB_queue]
    test rbx, rbx
    jz .Lqac_invalid
    cmp qword ptr [rbx + EQ_epoch], 0
    jle .Lqac_overflow
    mov rax, 0x7fffffffffffffff
    cmp [rbx + EQ_epoch], rax
    jae .Lqac_overflow
    cmp [rbx + EQ_batch], r12
    jne .Lqac_stale
    cmp qword ptr [rbx + EQ_seq], 0
    jle .Lqac_invalid
    cmp [rbx + EQ_seq], rax
    ja .Lqac_invalid
    mov r13, [r12 + EQB_count]
    test r13, r13
    jz .Lqac_invalid
    cmp r13, EC_BATCH
    ja .Lqac_invalid
    xor r14d, r14d
1:  imul rax, r14, EQB_ROW
    lea r15, [r12 + rax + EQB_rows]
    cmp qword ptr [r15 + EQBR_slot], EQ_MAX
    jae .Lqac_invalid
    mov rax, [r15 + EQBR_seq]
    test rax, rax
    jle .Lqac_invalid
    cmp rax, [rbx + EQ_seq]
    ja .Lqac_invalid
    inc r14
    cmp r14, r13
    jb 1b
    xor eax, eax
    EPILOGUE
.Lqac_overflow:
    mov rax, -75
    EPILOGUE
.Lqac_stale:
    mov rax, -116
    EPILOGUE
.Lqac_invalid:
    mov rax, -22
    EPILOGUE
