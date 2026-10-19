# Two structural channels use the reviewed fixture's fake keeper/FD model.
# EA/HI/EP refs, session capture/bind, credits and all typed releases are REAL.
# Actual process lifetime/child receipts are independently covered by native driver.
.bss
.p2align 3
rpl_peer_ext_saved: .zero EXT_SIZE
rpl_peer_slot_saved: .zero RT_SLOT_SIZE
rpl_peer_ext: .quad 0
rpl_peer_slot: .quad 0
rpl_peer_session: .quad 0
rpl_peer_old_ea: .quad 0
rpl_peer_old_ep: .quad 0
rpl_peer_old_hi: .quad 0
rpl_fair_rounds: .quad 0
.text
rpl_peer_consumed:
    test rax, rax
    jnz rpl_fail
    cmp rdx, 1
    jne rpl_fail
    ret
rpl_peer_add:
    PROLOGUE
    lea r14, [rbx + RT_slots + 18 * RT_SLOT_SIZE]
    mov [rip + rpl_peer_slot], r14
    mov r15, [rbx + RT_stableExtBase]
    add r15, 18 * EXT_SIZE
    mov [rip + rpl_peer_ext], r15
    lea rdi, [rip + rpl_peer_ext_saved]
    mov rsi, r15
    mov edx, EXT_SIZE
    call memcpy
    lea rdi, [rip + rpl_peer_slot_saved]
    mov rsi, r14
    mov edx, RT_SLOT_SIZE
    call memcpy
    mov rdi, [r13 + EXT_activation_owner]
    call ext_activation_owner_retain
    test rax, rax
    jnz rpl_fail
    mov rdi, [r13 + EXT_identity_owner]
    call ext_host_identity_retain
    test rax, rax
    jnz rpl_fail
    mov rdi, [r13 + EXT_metadata_owner]
    call ext_prepare_retain
    test rax, rax
    jnz rpl_fail
    mov rdi, r15
    mov rsi, r13
    mov edx, EXT_SIZE
    call memcpy
    mov qword ptr [r15 + EXT_wq + SB_ptr], 0
    mov qword ptr [r15 + EXT_wq + SB_len], 0
    mov qword ptr [r15 + EXT_wq + SB_cap], 0
    mov qword ptr [r15 + EXT_wq_off], 0
    mov qword ptr [r15 + EXT_rbuf + SB_ptr], 0
    mov qword ptr [r15 + EXT_rbuf + SB_len], 0
    mov qword ptr [r15 + EXT_rbuf + SB_cap], 0
    mov qword ptr [r15 + EXT_body], 0
    mov dword ptr [r15 + EXT_status], ES_STARTING
    mov dword ptr [r15 + EXT_start_armed], 0
    mov dword ptr [r15 + EXT_startaccepted], 0
    mov rdi, rbx
    mov esi, 18
    mov rdx, [r15 + EXT_activation_owner]
    mov rcx, [r15 + EXT_keeper]
    lea r8, [rip + rpl_peer_session]
    call rt_session_begin
    test rax, rax
    jnz rpl_fail
    # Structural model advances the already-owned native channel to accepted HELLO.
    mov dword ptr [r15 + EXT_status], ES_RUNNING
    mov dword ptr [r15 + EXT_start_armed], 1
    mov dword ptr [r15 + EXT_startaccepted], 1
    mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    call rt_session_bind
    test rax, rax
    jnz rpl_fail
    EPILOGUE
rpl_peer_freeze:
    PROLOGUE
    mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    mov ecx, 2
    call rt_credit_begin
    test rax, rax
    jnz rpl_fail
    mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    mov ecx, RTRSP_OK
    mov r8d, 100
    call rt_reply_freeze
    test rax, rax
    jnz rpl_fail
    EPILOGUE
# Both128byte queues are owned actual allocations. Prior bytes are modeled drained.
rpl_fill_small_queue:
    PROLOGUE
    mov r15, rdi
    mov rdi, [r15 + EXT_wq + SB_ptr]
    test rdi, rdi
    jnz 1f
    mov edi, 128
    call mem_alloc_try
    test rax, rax
    jz rpl_fail
    mov [r15 + EXT_wq + SB_ptr], rax
    mov qword ptr [r15 + EXT_wq + SB_cap], 128
    mov rdi, rax
1:  mov esi, 0x4b
    mov edx, 128
    call memset
    mov qword ptr [r15 + EXT_wq + SB_len], 128
    mov qword ptr [r15 + EXT_wq_off], 6
    EPILOGUE
rpl_peer_drop:
    PROLOGUE
    mov r15, [rip + rpl_peer_ext]
    mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    mov ecx, 77
    call rt_session_end
    test rax, rax
    jnz rpl_fail
    lea rdi, [r15 + EXT_wq]
    call sb_free
    mov qword ptr [r15 + EXT_wq_off], 0
    # No OS resource was ever attached to this structural fixture peer.
    mov qword ptr [r15 + EXT_keeper], 0
    mov dword ptr [r15 + EXT_pid], 0
    mov dword ptr [r15 + EXT_status], ES_STOPPED
    mov dword ptr [r15 + EXT_in], -1
    mov dword ptr [r15 + EXT_out], -1
    mov dword ptr [r15 + EXT_log], -1
    mov dword ptr [r15 + EXT_host_child_in], -1
    mov dword ptr [r15 + EXT_host_child_out], -1
    mov rdi, r15
    xor esi, esi
    lea rdx, [rip + rpl_peer_old_ea]
    call ext_activation_host_swap
    call rpl_peer_consumed
    mov rdi, [rip + rpl_peer_old_ea]
    call ext_activation_owner_release
    call rpl_peer_consumed
    mov qword ptr [rip + rpl_peer_old_ea], 0
    mov r14d, 3
1:  mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    mov ecx, 100
    call rt_session_cleanup_step
    test rax, rax
    js rpl_fail
    dec r14
    jnz 1b
    cmp rax, 1
    jne rpl_fail
    mov dword ptr [r15 + EXT_catalog_state], 2
    mov rdi, r15
    lea rsi, [rip + rpl_peer_old_ep]
    call ext_slot_metadata_take
    call rpl_peer_consumed
    mov rdi, [rip + rpl_peer_old_ep]
    call ext_prepare_release_deferred
    call rpl_peer_consumed
    mov qword ptr [rip + rpl_peer_old_ep], 0
    mov rdi, r15
    lea rsi, [rip + rpl_peer_old_hi]
    call ext_host_identity_take
    call rpl_peer_consumed
    mov rdi, [rip + rpl_peer_old_hi]
    call ext_host_identity_release
    call rpl_peer_consumed
    mov qword ptr [rip + rpl_peer_old_hi], 0
    mov rdi, r15
    lea rsi, [rip + rpl_peer_ext_saved]
    mov edx, EXT_SIZE
    call memcpy
    mov rdi, [rip + rpl_peer_slot]
    lea rsi, [rip + rpl_peer_slot_saved]
    mov edx, RT_SLOT_SIZE
    call memcpy
    EPILOGUE
rpl_fair_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 203
    mov qword ptr [rip + rpl_due], 100
    call rpl_peer_add
    mov qword ptr [rip + rpl_fair_rounds], 16
    mov qword ptr [rbx + RT_replyCursor], 17
.Lrpl_fair_round:
    mov rdi, r13
    call rpl_fill_small_queue
    mov rdi, [rip + rpl_peer_ext]
    call rpl_fill_small_queue
    call rpl_freeze
    call rpl_peer_freeze
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 18
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    mov r14, [rip + rpl_peer_slot]
    cmp qword ptr [r14 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    # Earlier peer becomes hot again before the later peer gets its opportunity.
    mov qword ptr [r13 + EXT_wq_off], 5
    call rpl_freeze
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 1
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 19
    jne rpl_fail
    cmp qword ptr [r14 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    mov qword ptr [rbx + RT_cleanupCursor], 18
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rt_operation_cleanup_step
    cmp rax, 1
    jne rpl_fail
    call rpl_reply_step
    cmp rax, 1
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    # Complete127 ordinary visits from18 back to17, including complete wraps.
    mov r14d, 7
1:  mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    test rax, rax
    jnz rpl_fail
    cmp rdx, 16
    jne rpl_fail
    dec r14
    jnz 1b
    mov rdi, rbx
    mov esi, 100
    mov edx, 15
    call rt_reply_step
    test rax, rax
    jnz rpl_fail
    cmp rdx, 15
    jne rpl_fail
    cmp qword ptr [rbx + RT_replyCursor], 17
    jne rpl_fail
    dec qword ptr [rip + rpl_fair_rounds]
    jnz .Lrpl_fair_round
    call rpl_cumulative_cases
    call rpl_peer_drop
    call rpl_restore
    call tt_drain
    call tt_census
    EPILOGUE

# First peer appends5. The next peer cannot compact65531 and append5 in the same slice.
rpl_cumulative_cases:
    PROLOGUE
    mov qword ptr [rip + rpl_stage], 206
    mov rdi, r13
    call rpl_fill_small_queue
    mov qword ptr [r13 + EXT_wq + SB_len], 0
    mov qword ptr [r13 + EXT_wq_off], 0
    mov r15, [rip + rpl_peer_ext]
    lea rdi, [r15 + EXT_wq]
    call sb_free
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz rpl_fail
    mov r15, [rip + rpl_peer_ext]
    mov [r15 + EXT_wq + SB_ptr], rax
    mov qword ptr [r15 + EXT_wq + SB_cap], 65536
    mov qword ptr [r15 + EXT_wq + SB_len], 65536
    mov qword ptr [r15 + EXT_wq_off], 5
    mov rdi, rax
    mov esi, 0x4b
    mov edx, 65536
    call memset
    call rpl_freeze
    call rpl_peer_freeze
    mov qword ptr [rip + rpl_copy_bytes], 0
    mov qword ptr [rip + rpl_compactions], 0
    mov qword ptr [rbx + RT_replyCursor], 17
    mov rdi, rbx
    mov esi, 100
    mov edx, 16
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp rdx, 16
    jne rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 5
    jne rpl_fail
    cmp qword ptr [rip + rpl_compactions], 0
    jne rpl_fail
    cmp qword ptr [r12 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    mov r14, [rip + rpl_peer_slot]
    cmp qword ptr [r14 + RTS_delivery], RTDEL_WAIT
    jne rpl_fail
    mov r15, [rip + rpl_peer_ext]
    cmp qword ptr [r15 + EXT_wq_off], 5
    jne rpl_fail
    cmp qword ptr [r15 + EXT_wq + SB_len], 65536
    jne rpl_fail
    call rpl_cleanup_step
    cmp rax, 1
    jne rpl_fail
    mov rdi, rbx
    mov esi, 18
    mov rdx, [rip + rpl_peer_session]
    call rt_reply_wake
    test rax, rax
    jnz rpl_fail
    mov qword ptr [rip + rpl_copy_bytes], 0
    mov qword ptr [rbx + RT_replyCursor], 18
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rt_reply_step
    cmp rax, 1
    jne rpl_fail
    cmp qword ptr [rip + rpl_copy_bytes], 65536
    jne rpl_fail
    cmp qword ptr [r14 + RTS_delivery], RTDEL_QUEUED
    jne rpl_fail
    mov qword ptr [rbx + RT_cleanupCursor], 18
    mov rdi, rbx
    mov esi, 100
    mov edx, 1
    call rt_operation_cleanup_step
    cmp rax, 1
    jne rpl_fail
    # Peer queue will be reused by the following fairness rounds, with its cap128.
    mov r15, [rip + rpl_peer_ext]
    lea rdi, [r15 + EXT_wq]
    call sb_free
    mov qword ptr [r15 + EXT_wq_off], 0
    EPILOGUE
