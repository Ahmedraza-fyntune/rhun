# Memory-only bounded compaction of an exclusively owned native output queue.
.include "rhun.inc"
.text
# EXT,budget1..65536 ->0/-EINVAL/-EAGAIN. Refusals leave every queue byte intact.
FN ext_send_queue_compact_bounded
    test rdi, rdi
    jz .Lqcb_bad
    test rsi, rsi
    jz .Lqcb_bad
    cmp rsi, 65536
    ja .Lqcb_bad
    mov rcx, [rdi + EXT_wq_off]
    mov rax, [rdi + EXT_wq + SB_len]
    cmp rcx, rax
    ja .Lqcb_bad
    mov rdx, [rdi + EXT_wq + SB_cap]
    cmp rax, rdx
    ja .Lqcb_bad
    mov r8, [rdi + EXT_wq + SB_ptr]
    test rdx, rdx
    jnz 1f
    test r8, r8
    jnz .Lqcb_bad
    jmp .Lqcb_ok
1:  test r8, r8
    jz .Lqcb_bad
    add rdx, r8
    jc .Lqcb_bad
    test rcx, rcx
    jz .Lqcb_ok
    sub rax, rcx
    jz .Lqcb_empty
    cmp rax, rsi
    ja .Lqcb_again
    PROLOGUE
    mov rbx, rdi
    mov r12, rax
    mov rdi, r8
    lea rsi, [r8 + rcx]
    mov rdx, r12
    call memmove
    mov [rbx + EXT_wq + SB_len], r12
    mov qword ptr [rbx + EXT_wq_off], 0
    xor eax, eax
    EPILOGUE
.Lqcb_empty:
    mov qword ptr [rdi + EXT_wq + SB_len], 0
    mov qword ptr [rdi + EXT_wq_off], 0
.Lqcb_ok:
    xor eax, eax
    ret
.Lqcb_bad:
    mov rax, -22
    ret
.Lqcb_again:
    mov rax, -11
    ret
