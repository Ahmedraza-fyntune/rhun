# Bounded nonblocking protocol output. The compatibility wrapper lives in ext.s.
.include "rhun.inc"
.text
# ext_flush_quota(ext,bytes1..65536,attempts1..16)->0/-errno.
# Every write, including EINTR, consumes one attempt. Pending bytes keep POLLOUT.
FN ext_flush_quota
    test rdi, rdi
    jz .Lef_invalid_leaf
    test rsi, rsi
    jz .Lef_invalid_leaf
    cmp rsi, 65536
    ja .Lef_invalid_leaf
    test rdx, rdx
    jz .Lef_invalid_leaf
    cmp rdx, 16
    ja .Lef_invalid_leaf
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_can_act
    test eax, eax
    jz .Lef_closed
    test dword ptr [rbx + EXT_host_cleanup_mask], (1 << 0) | (1 << 8)
    jnz .Lef_closed
    cmp dword ptr [rbx + EXT_in], 0
    jl .Lef_closed
    cmp qword ptr [rbx + EXT_in_closed_at], 0
    jne .Lef_closed
    xor r15d, r15d
.Lef_core:
    mov rax, [rbx + EXT_wq + SB_len]
    cmp rax, [rbx + EXT_wq + SB_cap]
    ja .Lef_invalid
    cmp [rbx + EXT_wq_off], rax
    ja .Lef_invalid
    je .Lef_empty
    mov rdx, [rbx + EXT_wq + SB_ptr]
    test rdx, rdx
    jz .Lef_invalid
    add rdx, [rbx + EXT_wq + SB_cap]
    jc .Lef_invalid
    # Never enter a native write unless nonblocking mode was actually committed.
    mov edi, [rbx + EXT_in]
    mov esi, 3                 # F_GETFL
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    jns 91f
    test r15, r15
    jz .Lef_return
    cmp rax, -32
    jne .Lef_return
    mov rax, -5
    jmp .Lef_return
91:
    test eax, O_NONBLOCK
    jz .Lef_nonblock
.Lef_write:
    mov r14, [rbx + EXT_wq + SB_len]
    sub r14, [rbx + EXT_wq_off]
    jz .Lef_empty
    test r12, r12
    jz .Lef_pending
    test r13, r13
    jz .Lef_pending
    cmp r14, r12
    cmova r14, r12
    mov rdx, r14
    mov rsi, [rbx + EXT_wq + SB_ptr]
    add rsi, [rbx + EXT_wq_off]
    mov edi, [rbx + EXT_in]
    dec r13
    SYS SYS_write
    cmp rax, -EINTR
    je .Lef_write
    cmp rax, -EAGAIN
    je .Lef_pending
    test rax, rax
    jle .Lef_write_error
    cmp rax, r14
    ja .Lef_write_error
    add [rbx + EXT_wq_off], rax
    sub r12, rax
    jmp .Lef_write
.Lef_empty:
    lea rdi, [rbx + EXT_wq]
    call sb_clear
    mov qword ptr [rbx + EXT_wq_off], 0
    mov qword ptr [rbx + EXT_full_since], 0
    mov edi, [rbx + EXT_in]
    xor esi, esi
    call watch_set_events
    xor eax, eax
    EPILOGUE
.Lef_pending:
    mov edi, [rbx + EXT_in]
    mov esi, POLLOUT
    call watch_set_events
    mov rax, [rbx + EXT_wq + SB_len]
    sub rax, [rbx + EXT_wq_off]
    cmp rax, EXT_WQ_MAX
    jb .Lef_below
    cmp qword ptr [rbx + EXT_full_since], 0
    jne .Lef_ok
    call time_ms
    mov [rbx + EXT_full_since], rax
.Lef_ok:
    xor eax, eax
    EPILOGUE
.Lef_below:
    mov qword ptr [rbx + EXT_full_since], 0
    jmp .Lef_ok
# Legacy mode retains its old mapping. Channel mode returns EPIPE only from write EPIPE.
.Lef_write_error:
    test r15, r15
    jz .Lef_broken
    mov r14, rax
    test r14, r14
    js 92f
    mov r14, -5
92: call time_ms
    cmp rax, 1
    jge 93f
    mov eax, 1
93: mov [rbx + EXT_in_closed_at], rax
    mov rax, r14
    EPILOGUE
.Lef_broken:
    call time_ms
    mov [rbx + EXT_in_closed_at], rax
.Lef_closed:
    mov rax, -32
    EPILOGUE
.Lef_nonblock:
    mov rax, -11
    EPILOGUE
.Lef_invalid:
    mov rax, -22
.Lef_return:
    EPILOGUE
.Lef_invalid_leaf:
    mov rax, -22
    ret

# TABLE,ordinal,session,bytes,attempts ->0/-errno. Only this proved entry selects channel mode.
FN ext_flush_channel_quota
    PROLOGUE
    mov r12, rcx
    mov r13, r8
    test r12, r12
    jz .Lef_channel_bad
    cmp r12, 65536
    ja .Lef_channel_bad
    test r13, r13
    jz .Lef_channel_bad
    cmp r13, 16
    ja .Lef_channel_bad
    call rt_session_channel_check
    test rax, rax
    jnz .Lef_channel_return
    mov rbx, rdx
    mov r15d, 1
    jmp .Lef_core
.Lef_channel_bad:
    mov rax, -22
.Lef_channel_return:
    EPILOGUE
