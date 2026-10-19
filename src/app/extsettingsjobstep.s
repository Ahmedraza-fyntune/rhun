# Bounded native settings progress. This module never reads or writes config files.
.include "rhun.inc"
.include "app/extsettingsjob.inc"
.text
# stdout framing, sharing the same byte and capsule-attempt budget.
FN ecj_stdout_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
.Lecjs_loop:
    test qword ptr [rbx + ECJ_eof], 1
    jnz .Lecjs_done
    cmp qword ptr [r12 + ECB_bytes], 0
    je .Lecjs_done
    cmp qword ptr [rbx + ECJ_protocol_failed], 0
    jne .Lecjs_discard
    cmp qword ptr [rbx + ECJ_delivery], 0
    jne .Lecjs_done
    cmp qword ptr [rbx + ECJ_hash_active], 0
    jne .Lecjs_hash
    cmp qword ptr [rbx + ECJ_result_seen], 0
    jne .Lecjs_discard
    mov r13, [rbx + ECJ_rx]
    test r13, r13
    jnz .Lecjs_body
    mov r14, EW_HEADER
    sub r14, [rbx + ECJ_rx_offset]
    jc .Lecjs_protocol
    jz .Lecjs_header_ready
    mov rax, [rbx + ECJ_rx_offset]
    lea r15, [rbx + ECJ_header + rax]
    jmp .Lecjs_read
.Lecjs_body:
    mov r14, [r13 + EJF_length]
    sub r14, [rbx + ECJ_rx_offset]
    jc .Lecjs_protocol
    jz .Lecjs_body_ready
    mov rax, [rbx + ECJ_rx_offset]
    lea r15, [r13 + EJF_body + rax]
.Lecjs_read:
    cmp qword ptr [r12 + ECB_calls], 2
    jb .Lecjs_done
    mov rax, [r12 + ECB_bytes]
    cmp r14, rax
    cmova r14, rax
    sub qword ptr [r12 + ECB_calls], 2
    mov rdi, [rbx + ECJ_native]
    xor esi, esi
    mov rdx, r15
    mov rcx, r14
    call ext_settings_native_read
    cmp rax, -11
    je .Lecjs_done
    cmp rax, -4
    je .Lecjs_done
    test rax, rax
    js .Lecjs_native_error
    jz .Lecjs_eof
    cmp rax, r14
    ja .Lecjs_protocol
    sub [r12 + ECB_bytes], rax
    add [rbx + ECJ_rx_offset], rax
    jmp .Lecjs_loop
.Lecjs_header_ready:
    lea rdi, [rbx + ECJ_header]
    mov rsi, rbx
    call ext_settings_wire_check
    test rax, rax
    js .Lecjs_protocol
    mov rdi, rbx
    mov rsi, rdx
    mov rdx, r8
    mov rcx, r9
    call ext_settings_frame_new
    test rax, rax
    jz .Lecjs_alloc_error
    mov [rbx + ECJ_rx], rax
    mov qword ptr [rbx + ECJ_rx_offset], 0
    jmp .Lecjs_loop
.Lecjs_body_ready:
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    js .Lecjs_protocol
    jmp .Lecjs_loop
.Lecjs_hash:
    mov rdi, rbx
    mov rsi, [r12 + ECB_bytes]
    call ecj_hash_step
    cmp rdx, [r12 + ECB_bytes]
    ja .Lecjs_protocol
    sub [r12 + ECB_bytes], rdx
    test rax, rax
    js .Lecjs_protocol
    jmp .Lecjs_loop
.Lecjs_discard:
    # After RESULT, even one trailing byte invalidates a clean terminal proof.
    cmp qword ptr [r12 + ECB_calls], 2
    jb .Lecjs_done
    mov r14, [r12 + ECB_bytes]
    cmp r14, 4096
    jbe 1f
    mov r14d, 4096
1:  sub qword ptr [r12 + ECB_calls], 2
    mov rdi, [rbx + ECJ_native]
    xor esi, esi
    lea rdx, [rbx + ECJ_scratch]
    mov rcx, r14
    call ext_settings_native_read
    cmp rax, -11
    je .Lecjs_done
    cmp rax, -4
    je .Lecjs_done
    test rax, rax
    js .Lecjs_native_error
    jz .Lecjs_eof
    cmp rax, r14
    ja .Lecjs_protocol
    sub [r12 + ECB_bytes], rax
    cmp qword ptr [rbx + ECJ_protocol_failed], 0
    jne .Lecjs_loop
    jmp .Lecjs_protocol
.Lecjs_eof:
    or qword ptr [rbx + ECJ_eof], 1
    cmp qword ptr [rbx + ECJ_result_seen], 1
    jne .Lecjs_protocol
    cmp qword ptr [rbx + ECJ_rx], 0
    jne .Lecjs_protocol
    cmp qword ptr [rbx + ECJ_rx_offset], 0
    jne .Lecjs_protocol
    jmp .Lecjs_done
.Lecjs_alloc_error:
    mov rax, rdx
.Lecjs_native_error:
    mov rdi, rbx
    mov rsi, rax
    mov edx, 1                     # Framing cannot be reused after a failed read.
    call ecj_error
    jmp .Lecjs_done
.Lecjs_protocol:
    mov rdi, rbx
    mov rsi, -71
    mov edx, 1
    call ecj_error
.Lecjs_done:
    xor eax, eax
    EPILOGUE

# step(job,now,bytes1..65536,capsuleAttempts8..16)->0pending/1terminal/-EINVAL.
# RDX payload bytes charged, RCX weighted capsule attempts. Native free is a dedicated step.
FN ext_settings_job_step
    test rdi, rdi
    jz .Lecjp_invalid
    test rdx, rdx
    jz .Lecjp_invalid
    cmp rdx, 65536
    ja .Lecjp_invalid
    cmp rcx, 8
    jb .Lecjp_invalid
    cmp rcx, 16
    ja .Lecjp_invalid
    PROLOGUE 48
    mov rbx, rdi
    mov [rbx + ECJ_now], rsi
    mov [rsp + ECB_bytes], rdx
    mov [rsp + ECB_initial_bytes], rdx
    mov [rsp + ECB_calls], rcx
    mov [rsp + ECB_initial_calls], rcx
    cmp qword ptr [rbx + ECJ_phase], ECJP_TERMINAL
    je .Lecjp_return
    cmp qword ptr [rbx + ECJ_native], 0
    je .Lecjp_finish
    cmp qword ptr [rbx + ECJ_cleanup_only], 0
    je 1f
    mov rax, [rbx + ECJ_now]
    cmp rax, [rbx + ECJ_retry_due]
    jb .Lecjp_return
    jmp .Lecjp_free_step
1:  cmp qword ptr [rbx + ECJ_retiring], 2
    je .Lecjp_free_step
    # Poll at most once, charging the Windows wait+exit pair conservatively.
    cmp qword ptr [rsp + ECB_calls], 2
    jb .Lecjp_after_poll
    sub qword ptr [rsp + ECB_calls], 2
    mov rdi, [rbx + ECJ_native]
    call ext_settings_native_poll
    cmp rax, 3
    ja .Lecjp_bad_poll
    mov [rbx + ECJ_authority], rax
    mov [rbx + ECJ_exit], rdx
    test rax, rax
    jz 1f
    mov qword ptr [rbx + ECJ_ever_child], 1
1:  mov r12, rcx
    mov rdi, rbx
    mov rsi, r12
    call ecj_observation
    test r12, r12
    jns .Lecjp_after_poll
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call ecj_error                 # Hold suppresses control close until index terminal.
.Lecjp_after_poll:
    cmp qword ptr [rbx + ECJ_deadline], 0
    je .Lecjp_drop
    cmp qword ptr [rbx + ECJ_hold], 0
    jne .Lecjp_drop
    cmp qword ptr [rbx + ECJ_possible], 0
    jne .Lecjp_drop
    mov rax, [rbx + ECJ_now]
    cmp rax, [rbx + ECJ_deadline]
    jb .Lecjp_drop
    mov rdi, rbx
    mov rsi, -110
    xor edx, edx
    call ecj_error
.Lecjp_drop:
    cmp qword ptr [rbx + ECJ_closing], 0
    je 2f
    mov rdi, rbx
    call ecj_drop_tx
2:  cmp qword ptr [rbx + ECJ_protocol_failed], 0
    je 3f
    mov rdi, rbx
    call ecj_drop_rx
3:  mov rdi, rbx
    mov rsi, rsp
    call ecj_close_step
    mov rdi, rbx
    mov rsi, rsp
    call ecj_tx_step
    cmp qword ptr [rbx + ECJ_retiring], 1
    je .Lecjp_retire_next
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 1
    call ecj_aux_step
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 2
    call ecj_aux_step
    mov rdi, rbx
    mov rsi, rsp
    call ecj_stdout_step
    cmp qword ptr [rbx + ECJ_authority], 2
    je .Lecjp_collected
    cmp qword ptr [rbx + ECJ_authority], 3
    je .Lecjp_collected
    # Owned ABORTING capsule can have no child, but still retain pending connect/security.
    cmp qword ptr [rbx + ECJ_start_error], 0
    jge .Lecjp_return
    cmp qword ptr [rbx + ECJ_ever_child], 0
    jne .Lecjp_return
    cmp qword ptr [rbx + ECJ_authority], 0
    jne .Lecjp_return
    jmp .Lecjp_retire_next
.Lecjp_collected:
    cmp qword ptr [rbx + ECJ_eof], 7
    jne .Lecjp_return
.Lecjp_retire_next:
    mov qword ptr [rbx + ECJ_retiring], 2
    jmp .Lecjp_return
.Lecjp_bad_poll:
    mov rdi, rbx
    mov rsi, -71
    mov edx, 1
    call ecj_error
    jmp .Lecjp_after_poll
.Lecjp_free_step:
    # No other capsule call in this step. The callee has a fixed, reviewed close list.
    dec qword ptr [rsp + ECB_calls]
    mov rdi, [rbx + ECJ_native]
    call ext_settings_native_free
    mov r12, rdx
    mov r13, rcx                # Opaque free classification, not capsule offsets.
    cmp r13, 1
    je 3f
    cmp rax, -16
    je 4f
3:  mov rdi, rbx
    mov rsi, rax
    call ecj_cleanup
4:  test r12, r12
    jnz 5f
    cmp r13, 1
    je .Lecjp_cleanup_delay
    cmp qword ptr [rbx + ECJ_cleanup_only], 0
    jne .Lecjp_cleanup_regressed
    mov qword ptr [rbx + ECJ_retiring], 1
    jmp .Lecjp_return
.Lecjp_cleanup_regressed:
    # Once terminal-only is proven, no new child/IO/debt can legitimately appear.
    mov rdi, rbx
    mov rsi, -71
    call ecj_cleanup
.Lecjp_cleanup_delay:
    mov qword ptr [rbx + ECJ_cleanup_only], 1
    mov qword ptr [rbx + ECJ_retiring], 2
    mov rax, [rbx + ECJ_retry_delay]
    test rax, rax
    jz 6f
    add rax, rax
    cmp rax, 1000
    jbe 7f
    mov eax, 1000
    jmp 7f
6:  mov eax, 16
7:  mov [rbx + ECJ_retry_delay], rax
    add rax, [rbx + ECJ_now]
    jnc 8f
    mov rax, -1
8:  mov [rbx + ECJ_retry_due], rax
    jmp .Lecjp_return
5:  cmp r12, 1
    jne .Lecjp_bad_poll
    mov qword ptr [rbx + ECJ_cleanup_only], 0
    mov qword ptr [rbx + ECJ_retry_delay], 0
    mov qword ptr [rbx + ECJ_retry_due], 0
.Lecjp_finish:
    mov rdi, rbx
    call ecj_native_consumed
    mov rdi, rbx
    call ecj_drop_tx
    test rax, rax
    js .Lecjp_return
    mov rdi, rbx
    call ecj_drop_rx
    test rax, rax
    js .Lecjp_return
    mov rdi, rbx
    call ecj_finalize
.Lecjp_return:
    xor eax, eax
    cmp qword ptr [rbx + ECJ_phase], ECJP_TERMINAL
    sete al
    mov rdx, [rsp + ECB_initial_bytes]
    sub rdx, [rsp + ECB_bytes]
    mov rcx, [rsp + ECB_initial_calls]
    sub rcx, [rsp + ECB_calls]
    EPILOGUE
.Lecjp_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
