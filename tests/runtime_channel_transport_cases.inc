.bss
.p2align 3
rch_transport_saved: .zero EXT_SIZE
rch_transport_slot: .zero RT_SLOT_SIZE
rch_inject: .quad 0
rch_alloc_fail: .quad 0
rch_write_mode: .quad 0
rch_fcntl_mode: .quad 0
rch_write_calls: .quad 0
rch_fcntl_calls: .quad 0
rch_events: .quad 0
rch_written: .quad 0
rch_received: .zero 65536
.text
FN rch_alloc
    cmp qword ptr [rip + rch_alloc_fail], 0
    je mem_alloc_try
    xor eax, eax
    ret
FN rch_watch
    cmp qword ptr [rip + rch_inject], 0
    je watch_set_events
    mov [rip + rch_events], rsi
    xor eax, eax
    ret
FN rch_time
    cmp qword ptr [rip + rch_inject], 0
    je time_ms
    xor eax, eax
    ret
FN rch_fcntl
    cmp qword ptr [rip + rch_inject], 0
    je 9f
    inc qword ptr [rip + rch_fcntl_calls]
    mov rax, [rip + rch_fcntl_mode]
    test rax, rax
    jz 1f
    cmp rax, 1
    je 2f
    cmp rax, 2
    je 3f
    mov rax, -32
    ret
1:  mov eax, O_NONBLOCK
    ret
2:  mov rax, -13
    ret
3:  xor eax, eax
    ret
9:  SYS SYS_fcntl
    ret
FN rch_write
    cmp qword ptr [rip + rch_inject], 0
    je 9f
    inc qword ptr [rip + rch_write_calls]
    mov rax, [rip + rch_write_mode]
    test rax, rax
    jz 1f
    cmp rax, 1
    je 2f
    cmp rax, 2
    je 3f
    cmp rax, 3
    je 4f
    cmp rax, 4
    je 5f
    cmp rax, 5
    je 6f
    lea rax, [rdx + 1]
    ret
1:  mov rax, -EINTR
    ret
2:  PROLOGUE
    mov r12, rdx
    cmp r12, 3
    jbe 21f
    mov r12d, 3
21: lea rdi, [rip + rch_received]
    add rdi, [rip + rch_written]
    mov rdx, r12
    call memcpy
    add [rip + rch_written], r12
    mov rax, r12
    EPILOGUE
3:  mov rax, -EAGAIN
    ret
4:  mov rax, -5
    ret
5:  mov rax, -32
    ret
6:  xor eax, eax
    ret
9:  SYS SYS_write
    ret
rch_enqueue:
    # RSI bytes,RDX length. Each transport call independently proves TABLE/session.
    mov rcx, rsi
    mov r8, rdx
    mov r9, rdx
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    jmp ext_send_enqueue_channel_bounded
rch_flush:
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 65536
    mov r8d, 16
    jmp ext_flush_channel_quota
rch_transport:
    PROLOGUE
    mov qword ptr [rip + rts_stage], 245
    lea rdi, [rip + rch_transport_saved]
    mov rsi, r13
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + rch_transport_slot]
    mov rsi, r14
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov qword ptr [rip + rch_inject], 1
    mov dword ptr [r13 + EXT_catalog_state], 2
    mov dword ptr [r13 + EXT_disabled], 1
    mov dword ptr [r13 + EXT_activation_stale], 1
    mov qword ptr [r13 + EXT_wq + SB_ptr], 0
    mov qword ptr [r13 + EXT_wq + SB_cap], 0
    mov qword ptr [r13 + EXT_wq + SB_len], 0
    mov qword ptr [r13 + EXT_wq_off], 0
    mov qword ptr [r13 + EXT_in_closed_at], 0
    call rts_check
    cmp rax, -116
    jne rts_fail
    mov qword ptr [rip + rch_alloc_fail], 1
    lea rsi, [rip + rch_old]
    mov edx, 3
    call rch_enqueue
    cmp rax, -12
    jne rts_fail
    mov rax, [r13 + EXT_wq + SB_ptr]
    or rax, [r13 + EXT_wq + SB_cap]
    or rax, [r13 + EXT_wq + SB_len]
    or rax, [r13 + EXT_wq_off]
    jnz rts_fail
    mov qword ptr [rip + rch_alloc_fail], 0
    lea rsi, [rip + rch_old]
    mov edx, 3
    call rch_enqueue
    test rax, rax
    jnz rts_fail
    lea rsi, [rip + rch_reply]
    mov edx, 8
    call rch_enqueue
    test rax, rax
    jnz rts_fail
    mov qword ptr [rip + rts_stage], 246
    mov qword ptr [rip + rch_write_calls], 0
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 7
    mov r8d, 3
    call ext_flush_channel_quota
    test rax, rax
    jnz rts_fail
    cmp qword ptr [rip + rch_write_calls], 3
    jne rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 0
    jne rts_fail
    mov qword ptr [rip + rch_write_calls], 0
    mov qword ptr [rip + rch_write_mode], 1
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 7
    mov r8d, 16
    call ext_flush_channel_quota
    test rax, rax
    jnz rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 7
    jne rts_fail
    cmp qword ptr [rip + rch_written], 7
    jne rts_fail
    cmp qword ptr [rip + rch_write_calls], 3
    jne rts_fail
    mov qword ptr [rip + rch_write_mode], 2
    call rch_flush
    test rax, rax
    jnz rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 7
    jne rts_fail
    mov qword ptr [rip + rch_write_mode], 1
    call rch_flush
    test rax, rax
    jnz rts_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 0
    jne rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 0
    jne rts_fail
    cmp qword ptr [rip + rch_events], 0
    jne rts_fail
    lea rdi, [rip + rch_received]
    lea rsi, [rip + rch_expected_order]
    mov edx, 11
    call memeq
    test eax, eax
    jz rts_fail
    # Tail pressure requires an explicit bounded compaction, preserving accepted order.
    mov qword ptr [rip + rts_stage], 247
    mov qword ptr [r13 + EXT_wq + SB_cap], 12
    lea rsi, [rip + rch_prefix]
    mov edx, 12
    call rch_enqueue
    test rax, rax
    jnz rts_fail
    mov qword ptr [r13 + EXT_wq_off], 4
    lea rsi, [rip + rch_old]
    mov edx, 3
    call rch_enqueue
    cmp rax, -11
    jne rts_fail
    cmp qword ptr [r13 + EXT_wq + SB_len], 12
    jne rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 4
    jne rts_fail
    mov rdi, r13
    mov esi, 7
    call ext_send_queue_compact_bounded
    cmp rax, -11
    jne rts_fail
    mov rdi, r13
    mov esi, 8
    call ext_send_queue_compact_bounded
    test rax, rax
    jnz rts_fail
    lea rsi, [rip + rch_old]
    mov edx, 3
    call rch_enqueue
    test rax, rax
    jnz rts_fail
    mov qword ptr [rip + rch_written], 0
    call rch_flush
    test rax, rax
    jnz rts_fail
    lea rdi, [rip + rch_received]
    lea rsi, [rip + rch_compacted_order]
    mov edx, 11
    call memeq
    test eax, eax
    jz rts_fail
    mov qword ptr [r13 + EXT_wq + SB_cap], 65536
    mov rsi, [r13 + EXT_wq + SB_ptr]
    mov edx, 1
    call rch_enqueue
    cmp rax, -22
    jne rts_fail
    # Preserve raw native failures. Legacy timestamps only quarantine later calls.
    mov qword ptr [rip + rts_stage], 248
    mov r12d, 3
.Lrch_error_loop:
    mov [rip + rch_write_mode], r12
    mov qword ptr [r13 + EXT_in_closed_at], 0
    mov qword ptr [r13 + EXT_wq + SB_len], 8
    mov qword ptr [r13 + EXT_wq_off], 0
    mov qword ptr [rip + rch_write_calls], 0
    call rch_flush
    mov r15, -5
    cmp r12, 4
    jne 1f
    mov r15, -32
1:  cmp rax, r15
    jne rts_fail
    cmp qword ptr [rip + rch_write_calls], 1
    jne rts_fail
    cmp qword ptr [r13 + EXT_in_closed_at], 1
    jne rts_fail
    cmp qword ptr [r13 + EXT_wq_off], 0
    jne rts_fail
    call rch_flush
    cmp rax, -11
    jne rts_fail
    cmp qword ptr [rip + rch_write_calls], 1
    jne rts_fail
    inc r12
    cmp r12, 7
    jb .Lrch_error_loop
    mov qword ptr [rip + rts_stage], 249
    mov qword ptr [r13 + EXT_in_closed_at], 0
    mov qword ptr [rip + rch_write_calls], 0
    mov qword ptr [rip + rch_fcntl_mode], 1
    call rch_flush
    cmp rax, -13
    jne rts_fail
    mov qword ptr [rip + rch_fcntl_mode], 2
    call rch_flush
    cmp rax, -11
    jne rts_fail
    mov qword ptr [rip + rch_fcntl_mode], 3
    call rch_flush
    cmp rax, -5
    jne rts_fail
    cmp qword ptr [rip + rch_write_calls], 0
    jne rts_fail
    cmp qword ptr [r13 + EXT_in_closed_at], 0
    jne rts_fail
    mov qword ptr [rip + rch_fcntl_mode], 0
    mov dword ptr [r13 + EXT_host_cleanup_mask], 1
    call rch_flush
    cmp rax, -11
    jne rts_fail
    cmp qword ptr [rip + rch_write_calls], 0
    jne rts_fail
    mov dword ptr [r13 + EXT_host_cleanup_mask], 0
    # Restore only test-owned state; the queue allocation is separately released once.
    mov rdi, [r13 + EXT_wq + SB_ptr]
    call mem_free
    mov rdi, r13
    lea rsi, [rip + rch_transport_saved]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, r14
    lea rsi, [rip + rch_transport_slot]
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov qword ptr [rip + rch_inject], 0
    EPILOGUE
.section .rodata
rch_old: .ascii "old"
rch_reply: .ascii "response"
rch_expected_order: .ascii "oldresponse"
rch_prefix: .ascii "ABCDEFGHIJKL"
rch_compacted_order: .ascii "EFGHIJKLold"
