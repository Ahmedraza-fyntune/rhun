# Checked enqueue for native operations that must not start after a refused reply.
.include "rhun.inc"
.text

# ext_send_checked(ext, bytes, length) -> 0 accepted, -EPIPE/-EAGAIN/-EINVAL.
# Acceptance means queued/written without a known pipe failure, not peer receipt.
# Same readable, disjoint payload and generic allocation policy as ext_send.
FN ext_send_checked
    test rdi, rdi
    jz .Lesc_invalid
    push rdi
    push rsi
    push rdx
    call ext_can_act
    pop rdx
    pop rsi
    pop rdi
    test eax, eax
    jz .Lesc_closed
    test dword ptr [rdi + EXT_host_cleanup_mask], (1 << 0) | (1 << 8)
    jnz .Lesc_closed
    cmp dword ptr [rdi + EXT_retiring], 0
    jne .Lesc_closed
    cmp dword ptr [rdi + EXT_status], ES_RUNNING
    jne .Lesc_closed
    cmp dword ptr [rdi + EXT_in], 0
    jl .Lesc_closed
    cmp qword ptr [rdi + EXT_in_closed_at], 0
    jne .Lesc_closed
    test rdx, rdx
    jz 1f
    test rsi, rsi
    jz .Lesc_invalid
1:  cmp rdx, EXT_WQ_HARD
    jae .Lesc_full
    mov rax, [rdi + EXT_wq + SB_len]
    mov rcx, [rdi + EXT_wq_off]
    cmp rcx, rax
    ja .Lesc_invalid
    sub rax, rcx
    cmp rax, EXT_WQ_HARD
    jae .Lesc_full
    add rax, rdx               # both operands are below the queue cap
    cmp rax, EXT_WQ_HARD
    jae .Lesc_full
    PROLOGUE
    mov rbx, rdi
    call ext_send
    mov rdi, rbx
    call ext_can_act
    test eax, eax
    jz 2f
    test dword ptr [rbx + EXT_host_cleanup_mask], (1 << 0) | (1 << 8)
    jnz 2f
    cmp dword ptr [rbx + EXT_retiring], 0
    jne 2f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 2f
    cmp dword ptr [rbx + EXT_in], 0
    jl 2f
    cmp qword ptr [rbx + EXT_in_closed_at], 0
    jne 2f
    xor eax, eax
    EPILOGUE
2:  mov rax, -32
    EPILOGUE
.Lesc_closed:
    mov rax, -32
    ret
.Lesc_full:
    mov rax, -11
    ret
.Lesc_invalid:
    mov rax, -22
    ret
