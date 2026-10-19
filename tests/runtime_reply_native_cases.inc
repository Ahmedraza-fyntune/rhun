.bss
.p2align 3
rcn_result: .zero RTC_SIZE
rcn_table: .quad 0
rcn_session: .quad 0
rcn_deadline: .quad 0
rcn_receipt: .quad 0
rpn_refuse_ea: .quad 0
rpn_ea_drop_calls: .quad 0
rpn_session_now: .quad 0
rpn_session_due: .quad 0
rpn_native_diag: .quad 0
.include "app/extruntimeadmit.inc"
.include "app/extruntimereply.inc"
.text
# Real keeper and parser-established HELLO. This fixture alone owns the stable EXT array.
rcn_actual:
    PROLOGUE
    mov qword ptr [rip + tek_stage], 100
    xor r12d, r12d
1:  imul rax, r12, EXT_SIZE
    lea rbx, [rip + lc_extension]
    add rbx, rax
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_host_child_in], -1
    mov dword ptr [rbx + EXT_host_child_out], -1
    inc r12
    cmp r12, RT_SLOT_COUNT
    jb 1b
    call lc_reset
    call lc_start
    mov qword ptr [rip + tek_stage], 101
    mov qword ptr [rip + tek_stage], 110
    lea rdi, [rip + rcn_result]
    call rt_table_create
    test rax, rax
    jnz .Ltek_fail
    mov qword ptr [rip + tek_stage], 111
    mov rbx, [rip + rcn_result + RTC_primary]
    or rbx, [rip + rcn_result + RTC_cleanup]
    or rbx, [rip + rcn_result + RTC_orphanEO]
    jnz .Ltek_fail
    mov rbx, [rip + rcn_result + RTC_owner]
    test rbx, rbx
    jz .Ltek_fail
    mov [rip + rcn_table], rbx
    mov qword ptr [rip + rcn_result + RTC_owner], 0
    mov r12d, 1000
2:  mov qword ptr [rip + tek_stage], 112
    mov rdi, rbx
    mov esi, 16
    call rt_table_init_step
    test rax, rax
    js .Ltek_fail
    cmp rax, 1
    je 3f
    dec r12
    jnz 2b
    jmp .Ltek_fail
3:  mov qword ptr [rip + tek_stage], 113
    lea rax, [rip + lc_extension]
    mov [rbx + RT_stableExtBase], rax
    mov qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    mov qword ptr [rbx + RT_flags], 0
    mov [rip + g_activeRT], rbx
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + lc_extension + EXT_activation_owner]
    mov rcx, [rip + lc_extension + EXT_keeper]
    lea r8, [rip + rcn_session]
    mov qword ptr [rip + tek_stage], 114
    call rt_session_begin
    test rax, rax
    jnz .Ltek_fail
    # The fixture's coordinator withheld only auto-arm until real session refs existed.
    lea rdi, [rip + lc_extension]
    mov rax, [rip + lc_extension + EXT_activation_plan]
    mov rsi, [rax + KE_expected]
    mov rdx, [rax + KE_context]
    call ext_arm_plan
    test rax, rax
    jnz .Ltek_fail
    call lc_wait_accepted
    mov qword ptr [rip + tek_stage], 102
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_bind
    cmp rax, -116
    jne .Ltek_fail
    test qword ptr [rbx + RT_slots + RTS_flags], RTSF_CHANNEL_BOUND
    jnz .Ltek_fail
    call lc_prehello_observe
    call lc_wait_running
    mov qword ptr [rip + tek_stage], 103
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_bind
    test rax, rax
    jnz .Ltek_fail
    test qword ptr [rbx + RT_slots + RTS_flags], RTSF_CHANNEL_BOUND
    jz .Ltek_fail
    call time_ms
    mov r8, rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov ecx, 0x7fffffff
    call rt_credit_begin
    test rax, rax
    jnz .Ltek_fail
    call time_ms
    mov r8, rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov ecx, RTRSP_OK
    call rt_reply_freeze
    test rax, rax
    jnz .Ltek_fail
    # Logical withdrawal and TABLE closure revoke actions but retain this native channel.
    mov dword ptr [rip + lc_extension + EXT_catalog_state], 2
    mov dword ptr [rip + lc_extension + EXT_disabled], 1
    mov dword ptr [rip + lc_extension + EXT_activation_stale], 1
    mov rdi, rbx
    call rt_root_close
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_check
    cmp rax, -116
    jne .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_channel_check
    test rax, rax
    jnz .Ltek_fail
    lea rax, [rip + lc_extension]
    cmp rdx, rax
    jne .Ltek_fail
    mov qword ptr [rip + tek_stage], 104
.if RPN_SCENARIO == 0
    # A quarantined retained real FD must not be mistaken for dead/abandoned.
    mov qword ptr [rip + lc_extension + EXT_in_closed_at], 1
    call rpn_reply_step
    cmp qword ptr [rbx + RT_slots + RTS_delivery], RTDEL_WAIT
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_replyID], 0x7fffffff
    jne .Ltek_fail
    mov qword ptr [rip + tek_stage], 154
    mov qword ptr [rip + lc_extension + EXT_in_closed_at], 0
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_reply_wake
    test rax, rax
    jnz .Ltek_fail
    mov qword ptr [rip + tek_stage], 155
    call rpn_reply_step
    cmp rax, 1
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_delivery], RTDEL_QUEUED
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_replyID], 0
    jne .Ltek_fail
    mov qword ptr [rip + tek_stage], 156
    call rpn_reply_step
    test rax, rax
    jnz .Ltek_fail
    mov qword ptr [rip + tek_stage], 157
    call rpn_operation_step
    cmp rax, 1
    jne .Ltek_fail
    test qword ptr [rbx + RT_slots + RTS_flags], RTSF_OP_CREDIT
    jnz .Ltek_fail
    call rpn_reply_step
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov ecx, 65536
    mov r8d, 16
    call ext_flush_channel_quota
    test rax, rax
    jnz .Ltek_fail
    mov qword ptr [rip + tek_stage], 160
    mov rdi, [rip + tek_plan + KE_state]
    lea rsi, [rip + rcn_receipt_name]
    call path_join
    mov [rip + rcn_receipt], rax
    call time_ms
    add rax, 5000
    mov [rip + rcn_deadline], rax
4:  mov rdi, [rip + rcn_receipt]
    call file_type
    cmp eax, 0x8000
    je 5f
    call time_ms
    cmp rax, [rip + rcn_deadline]
    jae .Ltek_fail
    # No ordinary tick/stop can preempt this isolated delivery test's revoked host.
    xor edi, edi
    xor esi, esi
    mov edx, 1
    SYS SYS_poll
    jmp 4b
5:  mov rdi, [rip + rcn_receipt]
    call mem_free
    mov qword ptr [rip + rcn_receipt], 0
    # Keep the child alive beyond the first match and every operation cleanup step.
    mov qword ptr [rip + tek_stage], 106
    call rpn_reply_step
    test rax, rax
    jnz .Ltek_fail
    call rpn_operation_step
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    lea rcx, [rip + rpn_end]
    mov r8d, 11
    mov r9d, 11
    call ext_send_enqueue_channel_bounded
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov ecx, 65536
    mov r8d, 16
    call ext_flush_channel_quota
    test rax, rax
    jnz .Ltek_fail
    mov rdi, [rip + tek_plan + KE_state]
    lea rsi, [rip + rpn_complete]
    call path_join
    mov [rip + rcn_receipt], rax
    call time_ms
    add rax, 5000
    mov [rip + rcn_deadline], rax
.Lrpn_complete_wait:
    mov rdi, [rip + rcn_receipt]
    call file_stamp
    cmp rdx, 1
    je .Lrpn_complete
    call time_ms
    cmp rax, [rip + rcn_deadline]
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 1
    SYS SYS_poll
    jmp .Lrpn_complete_wait
.Lrpn_complete:
    mov rdi, [rip + rcn_receipt]
    call mem_free
    mov qword ptr [rip + rcn_receipt], 0
.endif
    mov qword ptr [rip + tek_stage], 105
    # Actual native shutdown and EOF, never status alone, precede RT owner cleanup.
    mov dword ptr [rip + lc_extension + EXT_disabled], 0
    mov dword ptr [rip + lc_extension + EXT_activation_stale], 0
    mov dword ptr [rip + lc_extension + EXT_catalog_state], 1
    lea rdi, [rip + lc_extension]
    lea rsi, [rip + lc_stop_text]
    call ext_kill
    call lc_wait
    # Checked native-quiet host take consumes obsolete arm/plan ownership before FREE.
    # The RT still owns its independent EA and HI references through this transfer.
    call lc_owner_take
    mov qword ptr [rip + tek_owned_plan], 0
    mov rbx, [rip + rcn_table]
.if RPN_SCENARIO == 1
    mov qword ptr [rip + tek_stage], 107
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_channel_quiet_check
    test rax, rax
    jnz .Ltek_fail
    lea rax, [rip + lc_extension]
    cmp rdx, rax
    jne .Ltek_fail
    call rpn_reply_step
    cmp rax, 1
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_delivery], RTDEL_ABANDONED
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_outcome], RTRSP_OK + 1
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_replyID], 0
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_ea], 0
    je .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_hi], 0
    je .Ltek_fail
    call rpn_operation_step
    cmp rax, 1
    jne .Ltek_fail
    # Reply work is idle, but retained supplier cleanup has an independent timer.
    mov qword ptr [rip + tek_stage], 108
    call time_ms
    mov [rip + rpn_session_now], rax
    mov qword ptr [rip + rpn_refuse_ea], 1
    mov qword ptr [rip + rpn_native_diag], -5
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov rcx, rax
    call rt_session_cleanup_step
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
    mov [rip + rpn_session_due], rcx
    mov rax, [rip + rpn_session_now]
    add rax, 16
    cmp rcx, rax
    jne .Ltek_fail
    cmp qword ptr [rip + rpn_ea_drop_calls], 1
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_ea], 0
    je .Ltek_fail
    mov rdi, rbx
    mov rsi, [rip + rpn_session_now]
    call rt_reply_timeout
    test rax, rax
    jnz .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    mov rcx, [rip + rpn_session_now]
    call rt_session_cleanup_step
    test rax, rax
    jnz .Ltek_fail
    test rdx, rdx
    jnz .Ltek_fail
    cmp rcx, [rip + rpn_session_due]
    jne .Ltek_fail
    cmp qword ptr [rip + rpn_ea_drop_calls], 1
    jne .Ltek_fail
    cmp qword ptr [rbx + RT_slots + RTS_ea], 0
    je .Ltek_fail
    # Advancing only to the returned due time must finish without a new native event.
    mov rax, [rip + rpn_session_due]
    mov [rip + rpn_session_now], rax
.endif
    mov rbx, [rip + rcn_table]
    mov r12d, 1000
6:  mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
.if RPN_SCENARIO == 1
    mov rcx, [rip + rpn_session_now]
.else
    call time_ms
    mov rcx, rax
.endif
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call rt_session_cleanup_step
    test rax, rax
    js .Ltek_fail
    cmp rax, 1
    je 7f
    dec r12
    jnz 6b
    jmp .Ltek_fail
7:  cmp qword ptr [rbx + RT_slots + RTS_flags], 0
    jne .Ltek_fail
    call rt_closing_finish
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
    mov qword ptr [rip + rcn_table], 0
    lea rdi, [rip + lc_extension + EXT_wq]
    call sb_free
    lea rdi, [rip + lc_extension + EXT_rbuf]
    call sb_free
    call lc_metadata_drop
    call lc_retire_pump
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Ltek_fail
    cmp qword ptr [rip + g_activeRT], 0
    jne .Ltek_fail
    cmp qword ptr [rip + g_closingRT], 0
    jne .Ltek_fail
    EPILOGUE

rpn_reply_step:
    PROLOGUE 16
    mov r12d, 8
1:  mov rax, [rbx + RT_replyCursor]
    mov [rsp], rax
    call time_ms
    mov rdi, rbx
    mov rsi, rax
    mov edx, 16
    call rt_reply_step
    test rax, rax
    js 2f
    cmp qword ptr [rsp], 0
    je 2f
    dec r12
    jnz 1b
    mov rax, -5
2:  EPILOGUE
rpn_operation_step:
    PROLOGUE 16
    mov r12d, 8
1:  mov rax, [rbx + RT_cleanupCursor]
    mov [rsp], rax
    call time_ms
    mov rdi, rbx
    mov rsi, rax
    mov edx, 16
    call rt_operation_cleanup_step
    test rax, rax
    js 2f
    cmp qword ptr [rsp], 0
    je 2f
    dec r12
    jnz 1b
    mov rax, -5
2:  EPILOGUE
# Child reads actual stdin through final marker; startup bytes precede first reply.
rcn_child_receipt:
    PROLOGUE 272
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
.Lrpn_read:
    xor edi, edi
    lea rsi, [rsp + 256]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lrcn_child_bad
    inc r14
    cmp r14, 1048576
    ja .Lrcn_child_bad
    mov al, [rsp + 256]
    cmp r12, 256
    jae .Lrpn_overflow
    mov [rsp + r12], al
    inc r12
    jmp .Lrpn_newline
.Lrpn_overflow:
    mov r15d, 1
.Lrpn_newline:
    cmp al, 10
    jne .Lrpn_read
    test r15, r15
    jnz .Lrpn_other
    cmp r12, 14
    jne .Lrpn_marker
    mov rdi, rsp
    lea rsi, [rip + rcn_reply]
    mov edx, 14
    call memeq
    test eax, eax
    jz .Lrpn_marker
    inc r13
    cmp r13, 1
    jne .Lrpn_next
    lea rdi, [rip + rcn_receipt_name]
    call rpn_child_mark
    jmp .Lrpn_next
.Lrpn_marker:
    cmp r12, 11
    jne .Lrpn_other
    mov rdi, rsp
    lea rsi, [rip + rpn_end]
    mov edx, 11
    call memeq
    test eax, eax
    jz .Lrpn_other
    cmp r13, 1
    jne .Lrcn_child_bad
    lea rdi, [rip + rpn_complete]
    call rpn_child_mark
    xor eax, eax
    EPILOGUE
.Lrpn_other:
    # After first reply, only the exact reply or final marker is legal.
    test r13, r13
    jnz .Lrcn_child_bad
.Lrpn_next:
    xor r12d, r12d
    xor r15d, r15d
    jmp .Lrpn_read
.Lrcn_child_bad:
    mov edi, 119
    call sys_exit
    ud2
# Name -> actual state receipt containing the independently observed count '1'.
rpn_child_mark:
    PROLOGUE 16
    mov rsi, rdi
    mov rdi, rbx
    call path_join
    mov r12, rax
    mov rdi, rax
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js .Lrcn_child_bad
    mov r13, rax
    # Expose file creation before contents deliberately. Parent must wait for size1.
    xor edi, edi
    xor esi, esi
    mov edx, 20
    SYS SYS_poll
    mov rdi, r13
    lea rsi, [rip + rpn_one]
    mov edx, 1
    SYS SYS_write
    cmp rax, 1
    jne .Lrcn_child_bad
    mov rdi, r13
    SYS SYS_close
    test rax, rax
    js .Lrcn_child_bad
    mov rdi, r12
    call mem_free
    EPILOGUE
.section .rodata
rcn_reply: .ascii "ok 2147483647\n"
rcn_receipt_name: .asciz "channel-received"
rpn_end: .ascii "reply-done\n"
rpn_complete: .asciz "channel-complete"
rpn_one: .ascii "1"

.text
FN ext_activation_owner_release
    cmp qword ptr [rip + rpn_refuse_ea], 0
    je rpn_real_ea_release
    inc qword ptr [rip + rpn_ea_drop_calls]
    mov qword ptr [rip + rpn_refuse_ea], 0
    mov rax, -5
    xor edx, edx
    ret
