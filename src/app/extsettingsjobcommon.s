# Error channels, fixed proof classification and explicit frame retirement.
.include "rhun.inc"
.include "app/extsettingsjob.inc"
.text
# latch(job,negative,protocol0|1): observation never implies process collection.
FN ecj_error
    test rsi, rsi
    js 1f
    mov rsi, -5
1:  cmp qword ptr [rdi + ECJ_error], 0
    jne 2f
    mov [rdi + ECJ_error], rsi
2:  mov qword ptr [rdi + ECJ_closing], 1
    test edx, edx
    jz 3f
    mov qword ptr [rdi + ECJ_protocol_failed], 1
    mov qword ptr [rdi + ECJ_phase], ECJP_FAILED
3:  xor eax, eax
    ret
FN ecj_cleanup
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + ECJ_cleanup], 0
    jne 1f
    mov [rdi + ECJ_cleanup], rsi
1:  xor eax, eax
    ret
FN ecj_observation
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + ECJ_observation], 0
    jne 1f
    mov [rdi + ECJ_observation], rsi
1:  xor eax, eax
    ret

FN ecj_drop_tx
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ECJ_tx]
    call ext_settings_frame_free
    cmp rcx, 1
    jne .Lecjd_refused
    mov qword ptr [rbx + ECJ_tx], 0
    mov qword ptr [rbx + ECJ_tx_offset], 0
    mov qword ptr [rbx + ECJ_tx_pending], 0
    mov qword ptr [rbx + ECJ_tx_chunk], 0
    mov rdi, rbx
    mov rsi, rdx
    call ecj_cleanup
    EPILOGUE
FN ecj_drop_rx
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ECJ_rx]
    call ext_settings_frame_free
    cmp rcx, 1
    jne .Lecjd_refused
    mov qword ptr [rbx + ECJ_rx], 0
    mov qword ptr [rbx + ECJ_rx_offset], 0
    mov qword ptr [rbx + ECJ_hash_active], 0
    mov rdi, rbx
    mov rsi, rdx
    call ecj_cleanup
    EPILOGUE
.Lecjd_refused:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call ecj_cleanup
    mov rax, r12
    EPILOGUE

# Called only after capsule consumed (or fully settled NULL start). No native authority remains.
FN ecj_finalize
    PROLOGUE
    mov rbx, rdi
    call ecj_row
    mov r12, rax
    mov rdi, rbx
    mov rsi, [rbx + ECJ_result_cleanup]
    call ecj_cleanup
    mov rdi, rbx
    mov rsi, [rbx + ECJ_result_observation]
    call ecj_observation
    xor r13d, r13d                  # Strict complete terminal proof, independent of errno.
    cmp qword ptr [rbx + ECJ_result_seen], 1
    jne 1f
    cmp qword ptr [rbx + ECJ_protocol_failed], 0
    jne 1f
    cmp qword ptr [rbx + ECJ_eof], 7
    jne 1f
    cmp qword ptr [rbx + ECJ_authority], 2
    jne 1f
    cmp qword ptr [rbx + ECJ_exit], 0
    jne 1f
    cmp qword ptr [rbx + ECJ_launch_count], 0
    jne 1f
    mov r13d, 1
1:  test qword ptr [r12 + ECJR_flags], ECJR_COMMITTED
    jnz .Lecjf_committed
    test qword ptr [r12 + ECJR_flags], ECJR_POSSIBLE
    jz .Lecjf_before_possible
    test r13d, r13d
    jz .Lecjf_uncertain
    cmp qword ptr [rbx + ECJ_result_state], ECJS_PRECOMMIT_FAILED
    jne .Lecjf_uncertain
    mov rax, [rbx + ECJ_result_primary]
    mov [r12 + ECJR_primary], rax
    mov qword ptr [r12 + ECJR_state], ECJS_PRECOMMIT_FAILED
    or qword ptr [r12 + ECJR_flags], ECJR_DEFINITE
    jmp .Lecjf_terminal
.Lecjf_uncertain:
    mov qword ptr [r12 + ECJR_state], ECJS_UNCERTAIN
    mov rax, [rbx + ECJ_result_primary]
    test rax, rax
    js 2f
    mov rax, [rbx + ECJ_error]
    test rax, rax
    js 2f
    mov rax, -117
2:  mov [r12 + ECJR_primary], rax
    jmp .Lecjf_terminal
.Lecjf_before_possible:
    or qword ptr [r12 + ECJR_flags], ECJR_DEFINITE
    test r13d, r13d
    jz 3f
    mov rax, [rbx + ECJ_result_state]
    cmp rax, ECJS_READ_OK
    je 4f
    cmp rax, ECJS_PRECOMMIT_FAILED
    je 4f
    cmp rax, ECJS_CANCELED
    jne 3f
4:  mov [r12 + ECJR_state], rax
    mov rax, [rbx + ECJ_result_primary]
    mov [r12 + ECJR_primary], rax
    jmp .Lecjf_terminal
3:  mov qword ptr [r12 + ECJR_state], ECJS_PRECOMMIT_FAILED
    mov rax, [rbx + ECJ_error]
    test rax, rax
    js 5f
    mov rax, [rbx + ECJ_start_error]
    test rax, rax
    js 5f
    mov rax, -71
5:  mov [r12 + ECJR_primary], rax
    jmp .Lecjf_terminal
.Lecjf_committed:
    mov qword ptr [r12 + ECJR_state], ECJS_COMMITTED
    mov qword ptr [r12 + ECJR_primary], 0
    mov rsi, [rbx + ECJ_error]
    mov rdi, rbx
    call ecj_cleanup
    test r13d, r13d
    jnz .Lecjf_terminal
    mov rdi, rbx
    mov rsi, -71
    call ecj_cleanup
.Lecjf_terminal:
    mov rax, [r12 + ECJR_state]
    mov [rbx + ECJ_state], rax
    mov rax, [rbx + ECJ_cleanup]
    mov [r12 + ECJR_cleanup], rax
    mov rax, [rbx + ECJ_observation]
    mov [r12 + ECJR_observation], rax
    mov qword ptr [rbx + ECJ_phase], ECJP_TERMINAL
    xor eax, eax
    EPILOGUE

# status(job,out64): state,primary,cleanup,observation,round,flags,authority,exit.
# flags: terminal1, nativeConsumed2, retainedGuard4, publicationHold8, resultSeen16, possible32.
FN ext_settings_job_status
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ecj_row
    mov r13, rax
    mov rax, [rbx + ECJ_state]
    mov [r12], rax
    mov rax, [rbx + ECJ_error]
    cmp qword ptr [rbx + ECJ_state], ECJS_COMMITTED
    jne 1f
    xor eax, eax
1:  cmp qword ptr [rbx + ECJ_phase], ECJP_TERMINAL
    jne 2f
    mov rax, [r13 + ECJR_primary]
2:  mov [r12 + 8], rax
    mov rax, [rbx + ECJ_cleanup]
    mov [r12 + 16], rax
    mov rax, [rbx + ECJ_observation]
    mov [r12 + 24], rax
    mov rax, [rbx + ECJ_round]
    mov [r12 + 32], rax
    xor eax, eax
    cmp qword ptr [rbx + ECJ_phase], ECJP_TERMINAL
    jne 3f
    or eax, 1
3:  cmp qword ptr [rbx + ECJ_native], 0
    jne 4f
    or eax, 2
4:  cmp qword ptr [rbx + ECJ_hold], 0
    je 5f
    or eax, 8
5:  cmp qword ptr [rbx + ECJ_result_seen], 0
    je 6f
    or eax, 16
6:  test qword ptr [r13 + ECJR_flags], ECJR_POSSIBLE
    jz 7f
    or eax, 32
7:  cmp qword ptr [rbx + ECJ_mode], 3
    jne 8f
    cmp qword ptr [rbx + ECJ_phase], ECJP_IDLE
    jne 8f
    cmp qword ptr [rbx + ECJ_native], 0
    je 8f
    cmp qword ptr [rbx + ECJ_authority], 1
    jne 8f
    cmp qword ptr [rbx + ECJ_error], 0
    jne 8f
    cmp qword ptr [rbx + ECJ_observation], 0
    jne 8f
    cmp qword ptr [rbx + ECJ_closing], 0
    jne 8f
    cmp qword ptr [rbx + ECJ_result_seen], 0
    jne 8f
    or eax, 4
8:  mov [r12 + 40], rax
    mov rax, [rbx + ECJ_authority]
    mov [r12 + 48], rax
    mov rax, [rbx + ECJ_exit]
    mov [r12 + 56], rax
    xor eax, eax
    EPILOGUE

# receipt(job,round0..3,out80)->0/-EINVAL. Caller-owned fixed copy, never a borrowed pointer.
FN ext_settings_job_receipt
    cmp rsi, 3
    ja 1f
    imul rax, rsi, ECJ_ROW
    lea rsi, [rdi + rax + ECJ_ledger]
    PROLOGUE
    mov rdi, rdx
    mov edx, ECJ_ROW
    call memcpy
    xor eax, eax
    EPILOGUE
1:  mov rax, -22
    ret
