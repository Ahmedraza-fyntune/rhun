.bss
.p2align 3
rcn_result: .zero RTC_SIZE
rcn_table: .quad 0
rcn_session: .quad 0
rcn_deadline: .quad 0
rcn_receipt: .quad 0
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
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    lea rcx, [rip + rcn_reply]
    mov r8d, 14
    mov r9d, 14
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
5:  mov qword ptr [rip + tek_stage], 105
    mov rdi, [rip + rcn_receipt]
    call mem_free
    mov qword ptr [rip + rcn_receipt], 0
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
    mov r12d, 1000
6:  mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + rcn_session]
    call time_ms
    mov rcx, rax
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

# Child reads the real inherited stdin, including normal startup frames, until exact reply.
rcn_child_receipt:
    PROLOGUE 16
    xor r12d, r12d
    xor r13d, r13d
1:  xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lrcn_child_bad
    lea rax, [rip + rcn_reply]
    mov cl, [rsp]
    cmp cl, [rax + r12]
    jne 2f
    inc r12
    cmp r12, 14
    je 3f
    jmp 21f
2:  xor r12d, r12d
    cmp cl, byte ptr [rax]
    jne 21f
    inc r12
21: inc r13
    cmp r13, 65536
    jb 1b
    jmp .Lrcn_child_bad
3:  mov rdi, rbx
    lea rsi, [rip + rcn_receipt_name]
    call path_join
    mov r12, rax
    mov rdi, rax
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js .Lrcn_child_bad
    mov rdi, rax
    SYS SYS_close
    mov rdi, r12
    call mem_free
    xor eax, eax
    EPILOGUE
.Lrcn_child_bad:
    mov edi, 119
    call sys_exit
    ud2
.section .rodata
rcn_reply: .ascii "ok 2147483647\n"
rcn_receipt_name: .asciz "channel-received"
