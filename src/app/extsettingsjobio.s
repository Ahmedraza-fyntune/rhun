# Bounded control progress. Publication hold prevents parent-induced guard release.
.include "rhun.inc"
.include "app/extsettingsjob.inc"
.text
# close_step(job,budget): no hidden waits and no close/kill while publication is held.
FN ecj_close_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + ECJ_closing], 0
    je 8f
    cmp qword ptr [rbx + ECJ_hold], 0
    jne 8f
    cmp qword ptr [r12 + ECB_calls], 0
    je 8f
    dec qword ptr [r12 + ECB_calls]
    mov rdi, [rbx + ECJ_native]
    call ext_settings_native_close_input
    test rax, rax
    jns 1f
    cmp rax, -115
    je 1f
    mov rdi, rbx
    mov rsi, rax
    call ecj_cleanup
1:  cmp qword ptr [rbx + ECJ_possible], 0
    jne 8f
    cmp qword ptr [rbx + ECJ_authority], 1
    jne 8f
    cmp qword ptr [rbx + ECJ_killed], 0
    jne 8f
    cmp qword ptr [r12 + ECB_calls], 0
    je 8f
    dec qword ptr [r12 + ECB_calls]
    mov rdi, [rbx + ECJ_native]
    call ext_settings_native_kill
    test rax, rax
    js 2f
    mov qword ptr [rbx + ECJ_killed], 1
    jmp 8f
2:  mov rdi, rbx
    mov rsi, rax
    call ecj_cleanup
8:  xor eax, eax
    EPILOGUE

# tx_step(job,budget): account old native debt, then at most one copied queued chunk.
FN ecj_tx_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [r12 + ECB_calls], 0
    je .Lecjt_done
    cmp qword ptr [r12 + ECB_bytes], 0
    je .Lecjt_done
    dec qword ptr [r12 + ECB_calls]
    mov rdi, [rbx + ECJ_native]
    mov rsi, [r12 + ECB_bytes]
    call ext_settings_native_write_poll
    mov r13, rax
    cmp rdx, [r12 + ECB_bytes]
    ja .Lecjt_protocol
    cmp rcx, 1
    ja .Lecjt_protocol
    sub [r12 + ECB_bytes], rdx
    test r13, r13
    js .Lecjt_error
    cmp r13, 1
    ja .Lecjt_protocol
    cmp qword ptr [rbx + ECJ_tx_pending], 0
    je .Lecjt_queue
    test r13, r13
    jz .Lecjt_done
    mov rax, [rbx + ECJ_tx_chunk]
    add [rbx + ECJ_tx_offset], rax
    jc .Lecjt_protocol
    mov qword ptr [rbx + ECJ_tx_pending], 0
    mov qword ptr [rbx + ECJ_tx_chunk], 0
.Lecjt_queue:
    cmp qword ptr [rbx + ECJ_closing], 0
    jne .Lecjt_done
    cmp qword ptr [rbx + ECJ_hold], 0
    jne .Lecjt_done
    mov r13, [rbx + ECJ_tx]
    test r13, r13
    jz .Lecjt_done
    cmp qword ptr [rbx + ECJ_tx_pending], 0
    jne .Lecjt_done
    mov r14, [r13 + EJF_length]
    add r14, EW_HEADER
    sub r14, [rbx + ECJ_tx_offset]
    jc .Lecjt_protocol
    jnz 1f
    mov rdi, rbx
    call ecj_drop_tx
    jmp .Lecjt_done
1:  cmp qword ptr [r12 + ECB_calls], 0
    je .Lecjt_done
    mov rax, [r12 + ECB_bytes]
    test rax, rax
    jz .Lecjt_done
    cmp r14, rax
    cmova r14, rax
    dec qword ptr [r12 + ECB_calls]
    mov rax, [rbx + ECJ_tx_offset]
    lea rsi, [r13 + EJF_header + rax]
    mov rdi, [rbx + ECJ_native]
    mov rdx, r14
    call ext_settings_native_write_begin
    test rax, rax
    js .Lecjt_begin_error
    jz .Lecjt_done
    cmp rax, 1
    jne .Lecjt_protocol
    sub [r12 + ECB_bytes], r14
    mov [rbx + ECJ_tx_chunk], r14
    mov qword ptr [rbx + ECJ_tx_pending], 1
    cmp qword ptr [r13 + EJF_kind], EW_COMMIT
    jne .Lecjt_done
    # The queued chunk is already capsule-owned. Mark before any further call/yield.
    mov qword ptr [rbx + ECJ_possible], 1
    mov rax, [rbx + ECJ_round]
    imul rax, rax, ECJ_ROW
    or qword ptr [rbx + rax + ECJ_ledger + ECJR_flags], ECJR_POSSIBLE
.Lecjt_done:
    xor eax, eax
    EPILOGUE
.Lecjt_protocol:
    mov rdi, rbx
    mov rsi, -71
    mov edx, 1
    call ecj_error
    jmp .Lecjt_done
.Lecjt_begin_error:
    mov r13, rax
.Lecjt_error:
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    call ecj_error
    jmp .Lecjt_done

# One stderr/launch read, worstcase two pipe APIs. No unbounded diagnostics buffering.
FN ecj_aux_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    bt qword ptr [rbx + ECJ_eof], r13
    jc .Lecja_done
    cmp qword ptr [r12 + ECB_calls], 2
    jb .Lecja_done
    mov r14, [r12 + ECB_bytes]
    test r14, r14
    jz .Lecja_done
    cmp r14, 4096
    jbe 1f
    mov r14d, 4096
1:  cmp r13, 2
    jne 2f
    cmp r14, 8
    jbe 2f
    mov r14d, 8
2:  sub qword ptr [r12 + ECB_calls], 2
    mov rdi, [rbx + ECJ_native]
    mov rsi, r13
    lea rdx, [rbx + ECJ_scratch]
    mov rcx, r14
    call ext_settings_native_read
    cmp rax, -11
    je .Lecja_done
    cmp rax, -4
    je .Lecja_done
    test rax, rax
    js .Lecja_error
    jz .Lecja_eof
    cmp rax, r14
    ja .Lecja_protocol
    sub [r12 + ECB_bytes], rax
    cmp r13, 2
    je .Lecja_launch
    add [rbx + ECJ_stderr_count], rax
    jc .Lecja_protocol
    cmp qword ptr [rbx + ECJ_stderr_count], 4096
    ja .Lecja_protocol
    jmp .Lecja_done
.Lecja_launch:
    mov r14, [rbx + ECJ_launch_count]
    lea rcx, [r14 + rax]
    cmp rcx, 4
    ja .Lecja_protocol
    mov [rbx + ECJ_launch_count], rcx
    lea rdi, [rbx + ECJ_launch_bytes + r14]
    lea rsi, [rbx + ECJ_scratch]
    mov rdx, rax
    call memcpy
    jmp .Lecja_done
.Lecja_eof:
    bts qword ptr [rbx + ECJ_eof], r13
    cmp r13, 2
    jne .Lecja_done
    mov rax, [rbx + ECJ_launch_count]
    test rax, rax
    jz .Lecja_done
    cmp rax, 4
    jne .Lecja_protocol
    movsxd rax, dword ptr [rbx + ECJ_launch_bytes]
    cmp rax, -4095
    jl .Lecja_protocol
    test rax, rax
    jns .Lecja_protocol
.Lecja_error:
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call ecj_error
    jmp .Lecja_done
.Lecja_protocol:
    mov rdi, rbx
    mov rsi, -71
    mov edx, 1
    call ecj_error
.Lecja_done:
    xor eax, eax
    EPILOGUE
