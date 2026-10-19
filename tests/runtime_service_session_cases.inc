.include "app/extruntimeservice.inc"
.bss
.p2align 3
rts_done: .quad 0
rts_table: .quad 0
rts_exts: .zero RT_SLOT_COUNT * EXT_SIZE
rts_oldvec: .zero VEC_SIZE
rts_result: .zero RTC_SIZE
rts_output: .quad 0
rts_stage: .quad 0
rts_earefs: .quad 0
rts_hirefs: .quad 0
rts_session: .quad 0
rts_epoch: .quad 0
rts_oldcounter: .quad 0
rts_live: .quad 0
rts_now: .quad 0
rts_eafault: .quad 0
rts_hifault: .quad 0
rts_dropcalls: .quad 0
rts_diag: .zero 32
.text
rts_bind_hook:
    PROLOGUE
    call ext_activation_host_running_bind_check
    test rax, rax
    jnz 1f
    cmp qword ptr [rip + rts_done], 0
    jne 1f
    mov qword ptr [rip + rts_done], 1
    call rts_cases
    xor eax, eax
1:  EPILOGUE
rts_cases:
    PROLOGUE
    mov qword ptr [rip + rts_stage], 201
    mov qword ptr [rip + rts_now], 100
    mov rax, [rip + g_mem_live]
    mov [rip + rts_live], rax
    lea rdi, [rip + rts_oldvec]
    lea rsi, [rip + g_exts]
    mov edx, VEC_SIZE
    call memcpy
    xor r12d, r12d
1:  imul rax, r12, EXT_SIZE
    lea rbx, [rip + rts_exts]
    add rbx, rax
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_host_child_in], -1
    mov dword ptr [rbx + EXT_host_child_out], -1
    inc r12
    cmp r12, RT_SLOT_COUNT
    jb 1b
    lea rdi, [rip + rts_exts + 17 * EXT_SIZE]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memcpy
    lea rax, [rip + rts_exts]
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_cap], RT_SLOT_COUNT
    mov qword ptr [rip + g_exts + VEC_len], RT_SLOT_COUNT
    lea rdi, [rip + rts_result]
    call rt_table_create
    test rax, rax
    jnz rts_fail
    cmp qword ptr [rip + rts_result + RTC_primary], 0
    jne rts_fail
    cmp qword ptr [rip + rts_result + RTC_cleanup], 0
    jne rts_fail
    cmp qword ptr [rip + rts_result + RTC_orphanEO], 0
    jne rts_fail
    mov rbx, [rip + rts_result + RTC_owner]
    test rbx, rbx
    jz rts_fail
    mov [rip + rts_table], rbx
    mov r12d, 1000
2:  mov rdi, rbx
    mov esi, 1
    call rt_table_init_step
    test rax, rax
    js rts_fail
    cmp rax, 1
    je 3f
    dec r12
    jnz 2b
    jmp rts_fail
3:  mov [rip + g_activeRT], rbx
    mov qword ptr [rip + rts_result + RTC_owner], 0
    lea rax, [rip + rts_exts]
    mov [rbx + RT_stableExtBase], rax
    mov qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT
    mov qword ptr [rbx + RT_flags], 0
    lea r13, [rip + rts_exts + 17 * EXT_SIZE]
    lea r14, [rbx + RT_slots + 17 * RT_SLOT_SIZE]
    mov rax, [rip + af_ea]
    mov rcx, [rax + PO_refs]
    mov [rip + rts_earefs], rcx
    mov rax, [rip + ss_hi]
    mov rcx, [rax + PO_refs]
    mov [rip + rts_hirefs], rcx
    mov dword ptr [r13 + EXT_status], ES_STARTING
    mov dword ptr [r13 + EXT_startaccepted], 0
    mov dword ptr [r13 + EXT_start_armed], 0
    mov rax, [rip + rt_last_session]
    mov [rip + rts_oldcounter], rax
    mov qword ptr [rip + rts_output], 0x1234
    mov qword ptr [rip + rts_stage], 202
    mov rax, [rip + ss_hi]
    mov qword ptr [rax + PO_refs], -1
    call rts_begin
    mov r12, rax
    mov rax, [rip + ss_hi]
    mov rcx, [rip + rts_hirefs]
    mov [rax + PO_refs], rcx
    cmp r12, -75
    jne rts_fail
    call rts_unchanged
    mov qword ptr [rip + rts_stage], 203
    mov rax, [rip + af_ea]
    mov qword ptr [rax + PO_refs], -1
    call rts_begin
    mov r12, rax
    mov rax, [rip + af_ea]
    mov rcx, [rip + rts_earefs]
    mov [rax + PO_refs], rcx
    cmp r12, -75
    jne rts_fail
    call rts_unchanged
    mov qword ptr [rip + rts_stage], 204
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + af_ea]
    mov ecx, 123
    mov r8, rbx
    call rt_session_begin
    cmp rax, -22
    jne rts_fail
    call rts_unchanged
    mov qword ptr [rip + rts_stage], 205
    mov rax, 0x7fffffffffffffff
    mov [rip + rt_last_session], rax
    call rts_begin
    mov r12, rax
    mov rax, [rip + rts_oldcounter]
    mov [rip + rt_last_session], rax
    cmp r12, -75
    jne rts_fail
    call rts_unchanged
    mov qword ptr [rip + rts_stage], 206
    mov qword ptr [rbx + RT_barrierState], 1
    call rts_begin
    mov qword ptr [rbx + RT_barrierState], 0
    cmp rax, -16
    jne rts_fail
    call rts_unchanged
    mov qword ptr [rip + rts_stage], 207
    call rts_begin
    test rax, rax
    jnz rts_fail
    mov rax, [rip + rts_output]
    test rax, rax
    jle rts_fail
    cmp rax, [rip + rts_oldcounter]
    jbe rts_fail
    mov [rip + rts_session], rax
    cmp [r14 + RTS_session], rax
    jne rts_fail
    cmp qword ptr [r14 + RTS_state], RTS_ACTIVE
    jne rts_fail
    cmp qword ptr [r14 + RTS_grantSession], 0
    jne rts_fail
    mov rax, [rip + af_ea]
    mov rcx, [rip + rts_earefs]
    inc rcx
    cmp [rax + PO_refs], rcx
    jne rts_fail
    mov rax, [rip + ss_hi]
    mov rcx, [rip + rts_hirefs]
    inc rcx
    cmp [rax + PO_refs], rcx
    jne rts_fail
    mov qword ptr [rip + rts_stage], 208
    mov dword ptr [r13 + EXT_status], ES_RUNNING
    mov dword ptr [r13 + EXT_startaccepted], 1
    call rts_check
    cmp rax, -116
    jne rts_fail
    mov qword ptr [rip + rts_stage], 209
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    call rt_session_bind
    test rax, rax
    jnz rts_fail
    call rts_check
    test rax, rax
    jnz rts_fail
    mov qword ptr [rip + rts_stage], 210
    mov qword ptr [r13 + EXT_keeper], 444
    call rts_check
    mov qword ptr [r13 + EXT_keeper], 123
    cmp rax, -116
    jne rts_fail
    mov qword ptr [rip + rts_stage], 211
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    inc rdx
    mov ecx, 29
    call rt_session_end
    cmp rax, -116
    jne rts_fail
    call rts_check
    test rax, rax
    jnz rts_fail
    mov qword ptr [rip + rts_stage], 212
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 29
    call rt_session_end
    test rax, rax
    jnz rts_fail
    cmp qword ptr [r14 + RTS_grantSession], 0
    jne rts_fail
    cmp qword ptr [r14 + RTS_state], RTS_DRAINING
    jne rts_fail
    mov rax, [r14 + RTS_flags]
    and eax, RTSF_STOP_REQUIRED | RTSF_PARSER_PAUSED
    cmp eax, RTSF_STOP_REQUIRED | RTSF_PARSER_PAUSED
    jne rts_fail
    call rts_check
    cmp rax, -116
    jne rts_fail
    mov rax, [rip + rt_authority_epoch]
    mov [rip + rts_epoch], rax
    mov rdi, rbx
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov ecx, 999
    call rt_session_end
    test rax, rax
    jnz rts_fail
    mov rax, [rip + rts_epoch]
    cmp [rip + rt_authority_epoch], rax
    jne rts_fail
    mov rax, [r14 + RTS_flags]
    shr rax, 32
    cmp eax, 29
    jne rts_fail
    mov qword ptr [rip + rts_stage], 213
    mov rdi, rbx
    call rt_root_close
    test rax, rax
    jnz rts_fail
    cmp qword ptr [rip + g_activeRT], 0
    jne rts_fail
    cmp [rip + g_closingRT], rbx
    jne rts_fail
    call rt_closing_finish
    cmp rax, -16
    jne rts_fail
    cmp rdx, 0
    jne rts_fail
    mov qword ptr [rip + rts_stage], 214
    call rts_cleanup
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
    cmp rcx, -1
    jne rts_fail
    cmp qword ptr [r14 + RTS_ea], 0
    je rts_fail
    cmp qword ptr [r14 + RTS_hi], 0
    je rts_fail
    # Model native collection only on our private historical host, never the fixture host.
    mov qword ptr [r13 + EXT_keeper], 0
    mov dword ptr [r13 + EXT_pid], 0
    mov dword ptr [r13 + EXT_in], -1
    mov dword ptr [r13 + EXT_out], -1
    mov dword ptr [r13 + EXT_log], -1
    mov dword ptr [r13 + EXT_host_child_in], -1
    mov dword ptr [r13 + EXT_host_child_out], -1
    mov dword ptr [r13 + EXT_status], ES_IDLE
    mov dword ptr [r13 + EXT_retiring], 2
    mov dword ptr [r13 + EXT_stdout_eof], 1
    mov qword ptr [rip + rts_stage], 215
    mov qword ptr [r13 + EXT_wq + SB_len], 1
    call rts_cleanup
    mov qword ptr [r13 + EXT_wq + SB_len], 0
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
    cmp rcx, -1
    jne rts_fail
    cmp qword ptr [r14 + RTS_ea], 0
    je rts_fail
    # Every residual protocol buffer separately prevents owner retirement.
    mov qword ptr [r13 + EXT_rbuf + SB_len], 1
    call rts_cleanup
    mov qword ptr [r13 + EXT_rbuf + SB_len], 0
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
    mov qword ptr [r13 + EXT_wq_off], 1
    call rts_cleanup
    mov qword ptr [r13 + EXT_wq_off], 0
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
    mov qword ptr [r13 + EXT_body], 1
    call rts_cleanup
    mov qword ptr [r13 + EXT_body], 0
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
.if RTS_TEST_SCENARIO == 1
    mov qword ptr [rip + rts_eafault], 1
    mov qword ptr [rip + rts_hifault], 1
    mov qword ptr [rip + rts_stage], 218
    call rts_cleanup
    call rts_refused
.endif
.if RTS_TEST_SCENARIO == 2
    mov qword ptr [rip + rts_eafault], 2
    mov qword ptr [rip + rts_hifault], 2
.endif
    mov qword ptr [rip + rts_stage], 216
    call rts_cleanup
    test rax, rax
    jnz rts_fail
    cmp rdx, 1
    jne rts_fail
    cmp qword ptr [r14 + RTS_ea], 0
    jne rts_fail
    cmp qword ptr [r14 + RTS_hi], 0
    je rts_fail
.if RTS_TEST_SCENARIO == 1
    mov qword ptr [rip + rts_stage], 219
    call rts_cleanup
    call rts_refused
    mov qword ptr [rip + rts_stage], 216
.endif
    call rts_cleanup
    test rax, rax
    jnz rts_fail
    cmp rdx, 1
    jne rts_fail
    cmp qword ptr [r14 + RTS_hi], 0
    jne rts_fail
    call rts_cleanup
    cmp rax, 1
    jne rts_fail
    cmp rdx, 1
    jne rts_fail
    xor r12d, r12d
4:  cmp qword ptr [r14 + r12], 0
    jne rts_fail
    add r12, 8
    cmp r12, RT_SLOT_SIZE
    jb 4b
    mov rax, [rip + af_ea]
    mov rcx, [rip + rts_earefs]
    cmp [rax + PO_refs], rcx
    jne rts_fail
    mov rax, [rip + ss_hi]
    mov rcx, [rip + rts_hirefs]
    cmp [rax + PO_refs], rcx
    jne rts_fail
    mov qword ptr [rip + rts_stage], 220
    mov qword ptr [rbx + RT_stableExtBase], 1
    mov rdi, rbx
    call rt_table_native_quiet_check
    cmp rax, -16
    jne rts_fail
    call rt_closing_finish
    cmp rax, -16
    jne rts_fail
    cmp [rip + g_closingRT], rbx
    jne rts_fail
    lea rax, [rip + rts_exts]
    mov [rbx + RT_stableExtBase], rax
    mov qword ptr [rip + rts_stage], 217
    call rt_closing_finish
    test rax, rax
    jnz rts_fail
    cmp rdx, 1
    jne rts_fail
    cmp qword ptr [rip + g_closingRT], 0
    jne rts_fail
.if RTS_TEST_SCENARIO == 0
    call af_drain
.else
    mov r12d, 4096
5:  mov edi, 1
    lea rsi, [rip + rts_diag]
    call ext_prepare_retire_step
    test rax, rax
    js rts_fail
    cmp qword ptr [rip + rts_diag], 1
    ja rts_fail
    cmp qword ptr [rip + rts_diag + 16], 0
    jne rts_fail
    cmp qword ptr [rip + rts_diag + 24], -5
    jne rts_fail
    test rax, rax
    jz 6f
    dec r12
    jnz 5b
    jmp rts_fail
6:  call ext_prepare_retire_ack
    test rax, rax
    jnz rts_fail
.endif
    mov rax, [rip + g_mem_live]
    cmp [rip + rts_live], rax
    jne rts_fail
    lea rdi, [rip + g_exts]
    lea rsi, [rip + rts_oldvec]
    mov edx, VEC_SIZE
    call memcpy
    EPILOGUE
rts_begin:
    mov rdi, [rip + rts_table]
    mov esi, 17
    mov rdx, [rip + af_ea]
    mov ecx, 123
    lea r8, [rip + rts_output]
    jmp rt_session_begin
rts_check:
    PROLOGUE
    mov rdi, [rip + rts_table]
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov qword ptr [rip + ss_hot], 1
    call rt_session_check
    mov qword ptr [rip + ss_hot], 0
    EPILOGUE
rts_cleanup:
    mov rdi, [rip + rts_table]
    mov esi, 17
    mov rdx, [rip + rts_session]
    mov rcx, [rip + rts_now]
    jmp rt_session_cleanup_step
rts_unchanged:
    cmp qword ptr [rip + rts_output], 0x1234
    jne rts_fail
    cmp qword ptr [r14 + RTS_ea], 0
    jne rts_fail
    cmp qword ptr [r14 + RTS_hi], 0
    jne rts_fail
    cmp qword ptr [r14 + RTS_state], RTS_FREE
    jne rts_fail
    mov rax, [rip + rt_last_session]
    cmp [rip + rts_oldcounter], rax
    jne rts_fail
    mov rax, [rip + af_ea]
    mov rcx, [rip + rts_earefs]
    cmp [rax + PO_refs], rcx
    jne rts_fail
    mov rax, [rip + ss_hi]
    mov rcx, [rip + rts_hirefs]
    cmp [rax + PO_refs], rcx
    jne rts_fail
    ret
rts_fail:
    mov rdi, [rip + rts_stage]
    jmp sys_exit

# Refusal preserves both owning fields, and the scheduler must not retry before due.
rts_refused:
    PROLOGUE
    test rax, rax
    jnz rts_fail
    cmp rdx, 1
    jne rts_fail
    mov rax, [rip + rts_now]
    add rax, 16
    cmp rcx, rax
    jne rts_fail
    cmp [r14 + RTS_retryDue], rax
    jne rts_fail
    cmp qword ptr [r14 + RTS_backoff], 16
    jne rts_fail
    mov r12, [rip + rts_dropcalls]
    call rts_cleanup
    test rax, rax
    jnz rts_fail
    test rdx, rdx
    jnz rts_fail
    cmp [rip + rts_dropcalls], r12
    jne rts_fail
    mov [rip + rts_now], rcx
    EPILOGUE
FN ext_activation_owner_release
    inc qword ptr [rip + rts_dropcalls]
    cmp qword ptr [rip + rts_eafault], 0
    je rts_real_ea_release
    cmp qword ptr [rip + rts_eafault], 2
    je 1f
    mov qword ptr [rip + rts_eafault], 0
    mov rax, -5
    xor edx, edx
    ret
1:  PROLOGUE
    mov qword ptr [rip + rts_eafault], 0
    call rts_real_ea_release
    cmp rdx, 1
    jne rts_fail
    mov rax, -5
    EPILOGUE
FN ext_host_identity_release
    inc qword ptr [rip + rts_dropcalls]
    cmp qword ptr [rip + rts_hifault], 0
    je rts_real_hi_release
    cmp qword ptr [rip + rts_hifault], 2
    je 1f
    mov qword ptr [rip + rts_hifault], 0
    mov rax, -5
    xor edx, edx
    ret
1:  PROLOGUE
    mov qword ptr [rip + rts_hifault], 0
    call rts_real_hi_release
    cmp rdx, 1
    jne rts_fail
    mov rax, -5
    EPILOGUE
