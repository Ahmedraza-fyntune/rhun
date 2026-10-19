# Bounded enqueue-only path. Native flushing and large generic queue compaction are separate.
.include "rhun.inc"
.text
# ext_send_enqueue_bounded(ext,bytes,len,budget1..65536)->0/-errno.
# Payload is disjoint from the queue allocation. Acceptance means owned ordered bytes, not receipt.
FN ext_send_enqueue_bounded
    test rdi, rdi
    jz .Leqb_invalid_fast
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    call ext_can_act
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    test eax, eax
    jz .Leqb_closed_fast
    test dword ptr [rdi + EXT_host_cleanup_mask], (1 << 0) | (1 << 8)
    jnz .Leqb_closed_fast
    cmp dword ptr [rdi + EXT_retiring], 0
    jne .Leqb_closed_fast
    cmp dword ptr [rdi + EXT_status], ES_RUNNING
    jne .Leqb_closed_fast
    cmp dword ptr [rdi + EXT_in], 0
    jl .Leqb_closed_fast
    cmp qword ptr [rdi + EXT_in_closed_at], 0
    jne .Leqb_closed_fast
.Leqb_payload:
    test rsi, rsi
    jz .Leqb_invalid_fast
    test rdx, rdx
    jz .Leqb_invalid_fast
    test rcx, rcx
    jz .Leqb_invalid_fast
    cmp rcx, 65536
    ja .Leqb_invalid_fast
    cmp rdx, rcx
    ja .Leqb_invalid_fast
    mov rax, rsi
    add rax, rdx
    jc .Leqb_invalid_fast
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + EXT_wq + SB_len]
    mov rcx, [rbx + EXT_wq_off]
    cmp rcx, r14
    ja .Leqb_invalid
    mov rdx, [rbx + EXT_wq + SB_cap]
    cmp r14, rdx
    ja .Leqb_invalid
    mov r15, [rbx + EXT_wq + SB_ptr]
    test rdx, rdx
    jnz 11f
    test r15, r15
    jnz .Leqb_invalid
    jmp 1f
11: test r15, r15
    jz .Leqb_invalid
    mov r8, r15
    add r8, rdx
    jc .Leqb_invalid
    cmp r12, r8
    jae 1f
    cmp rax, r15
    ja .Leqb_invalid
1:  mov r8, r14
    sub r8, rcx
    add r8, r13
    jc .Leqb_full
    cmp r8, EXT_WQ_HARD
    jae .Leqb_full
    cmp r14, rcx
    je .Leqb_empty
    mov rax, r14
    add rax, r13
    jc .Leqb_invalid
    cmp rax, rdx
    ja .Leqb_full
    mov [rsp + 16], rax
    lea rdi, [r15 + r14]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, [rsp + 16]
    mov [rbx + EXT_wq + SB_len], rax
    jmp .Leqb_watch
.Leqb_empty:
    cmp r13, rdx
    ja .Leqb_reserve
    test r15, r15
    jz .Leqb_invalid
    mov rdi, r15
    mov rsi, r12
    mov rdx, r13
    call memcpy
    jmp .Leqb_empty_commit
.Leqb_reserve:
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz .Leqb_nomem
    mov [rsp + 8], rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov rax, [rsp + 8]
    mov [rbx + EXT_wq + SB_ptr], rax
    mov qword ptr [rbx + EXT_wq + SB_cap], 65536
    test r15, r15
    jz .Leqb_empty_commit
    mov rdi, r15
    call mem_free
.Leqb_empty_commit:
    mov [rbx + EXT_wq + SB_len], r13
    mov qword ptr [rbx + EXT_wq_off], 0
.Leqb_watch:
    mov edi, [rbx + EXT_in]
    mov esi, POLLOUT
    call watch_set_events
    xor eax, eax
    EPILOGUE
.Leqb_full:
    mov rax, -11
    EPILOGUE
.Leqb_nomem:
    mov rax, -12
    EPILOGUE
.Leqb_invalid:
    mov rax, -22
    EPILOGUE
.Leqb_closed_fast:
    mov rax, -32
    ret
.Leqb_invalid_fast:
    mov rax, -22
    ret

# TABLE,ordinal,session,bytes,len,budget ->0/-errno. No public unchecked bypass.
FN ext_send_enqueue_channel_bounded
    PROLOGUE
    mov rbx, rcx
    mov r12, r8
    mov r13, r9
    call rt_session_channel_check
    test rax, rax
    jnz 1f
    mov rdi, rdx
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r13
    call .Leqb_payload
1:  EPILOGUE
