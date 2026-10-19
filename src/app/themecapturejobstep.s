# Bounded native progress and incremental result adoption. No parent source/path IO.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturejob.inc"
.include "app/extstorejob.inc"
.text
# Latch cleanup without replacing a primary, and stop accepting success.
tcj_cleanup_abort:
    PROLOGUE
    mov rbx, rdi
    call tc_job_cleanup
    mov qword ptr [rbx + TCJ_closing], 1
    mov qword ptr [rbx + TCJ_state], TCJS_CLOSING
    cmp qword ptr [rbx + TCJ_native], 0
    jne 1f
    mov qword ptr [rbx + TCJ_state], TCJS_FAILED
1:  EPILOGUE
# A destructor attempt is the entire step, never mixed with poll/read/write work.
tcj_native_retire:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + TCJ_native]
    call ext_settings_native_free
    mov r12, rdx
    mov r13, rcx
    test rax, rax
    jns 1f
    cmp rax, -16
    jne 90f
    test r12, r12
    jnz 90f
    test r13, r13
    jz 1f
90: mov rdi, rbx
    mov rsi, rax
    call tcj_cleanup_abort
1:  test r12, r12
    jnz .Ltcjn_consumed
    cmp r13, 1
    jne .Ltcjn_progress
    mov qword ptr [rbx + TCJ_cleanup_only], 1
    mov rax, [rbx + TCJ_retry_delay]
    test rax, rax
    jnz 2f
    mov eax, 8
2:  add rax, rax
    cmp rax, 1000
    jbe 3f
    mov eax, 1000
3:  mov [rbx + TCJ_retry_delay], rax
    add rax, [rbx + TCJ_now]
    jno 4f
    mov rax, 9223372036854775807
4:  mov [rbx + TCJ_retry_due], rax
    mov qword ptr [rbx + TCJ_retire_requested], 1
    EPILOGUE
.Ltcjn_progress:
    mov qword ptr [rbx + TCJ_cleanup_only], 0
    mov qword ptr [rbx + TCJ_retire_requested], 0
    EPILOGUE
.Ltcjn_consumed:
    mov qword ptr [rbx + TCJ_native], 0
    mov qword ptr [rbx + TCJ_native_retired], 1
    mov qword ptr [rbx + TCJ_retire_requested], 0
    mov qword ptr [rbx + TCJ_cleanup_only], 0
    mov rdi, [rbx + TCJ_reservation]
    call tc_charge_release
    test rax, rax
    js 5f
    mov qword ptr [rbx + TCJ_reservation], 0
    jmp 6f
5:  mov rdi, rbx
    mov rsi, rax
    call tcj_cleanup_abort
6:  mov rax, [rbx + TCJ_primary]
    or rax, [rbx + TCJ_cleanup]
    or rax, [rbx + TCJ_closing]
    jnz .Ltcjn_failed
    cmp qword ptr [rbx + TCJ_authority], ESJ_REAPED
    jne .Ltcjn_protocol
    cmp qword ptr [rbx + TCJ_exit], 0
    jne .Ltcjn_protocol
    cmp qword ptr [rbx + TCJ_eof], 7
    jne .Ltcjn_protocol
    cmp qword ptr [rbx + TCJ_input_closed], 1
    jne .Ltcjn_protocol
    cmp qword ptr [rbx + TCJ_tx_pending], 0
    jne .Ltcjn_protocol
    mov rax, [rbx + TCJ_result]
    mov rcx, [rbx + TCJ_used]
    mov [rax + TCS_length], rcx
    mov qword ptr [rbx + TCJ_state], TCJS_DECODING
    EPILOGUE
.Ltcjn_protocol:
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
.Ltcjn_failed:
    mov qword ptr [rbx + TCJ_state], TCJS_FAILED
    EPILOGUE

# step(job,now,byteBudget,currentContext)->1pending/0terminal, primary, cleanup.
FN theme_capture_job_step
    test rdi, rdi
    jz .Ltcjst_bad_leaf
    test rsi, rsi
    js .Ltcjst_bad_leaf
    test rdx, rdx
    jz .Ltcjst_bad_leaf
    cmp rdx, 65536
    ja .Ltcjst_bad_leaf
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsp
    cmp rsi, [rbx + TCJ_now]
    jl .Ltcjst_bad
    cmp qword ptr [rbx + TCJ_state], TCJS_TAKEN
    ja .Ltcjst_bad
    mov [rbx + TCJ_now], rsi
    mov [r12 + TCB_bytes], rdx
    mov qword ptr [r12 + TCB_calls], 16
    cmp qword ptr [rbx + TCJ_state], TCJS_TAKEN
    je .Ltcjst_terminal
    cmp qword ptr [rbx + TCJ_state], TCJS_FAILED
    je .Ltcjst_terminal
    cmp [rbx + TCJ_context], rcx
    je 1f
    mov rdi, rbx
    mov rsi, -116
    call tc_job_error
1:  cmp qword ptr [rbx + TCJ_state], TCJS_READY
    je .Ltcjst_terminal
    cmp qword ptr [rbx + TCJ_state], TCJS_FAILED
    je .Ltcjst_terminal
    mov rax, [rbx + TCJ_now]
    cmp rax, [rbx + TCJ_deadline]
    jb 2f
    mov rdi, rbx
    mov rsi, -110
    call tc_job_error
2:  cmp qword ptr [rbx + TCJ_state], TCJS_FAILED
    je .Ltcjst_terminal
    cmp qword ptr [rbx + TCJ_state], TCJS_DECODING
    je .Ltcjst_decode
    cmp qword ptr [rbx + TCJ_native], 0
    je .Ltcjst_missing_native
    cmp qword ptr [rbx + TCJ_cleanup_only], 0
    je 3f
    mov rax, [rbx + TCJ_now]
    cmp rax, [rbx + TCJ_retry_due]
    jb .Ltcjst_pending
3:  cmp qword ptr [rbx + TCJ_retire_requested], 0
    je .Ltcjst_poll
    mov rdi, rbx
    call tcj_native_retire
    cmp qword ptr [rbx + TCJ_state], TCJS_FAILED
    je .Ltcjst_terminal
    jmp .Ltcjst_pending
.Ltcjst_decode:
    mov rdi, [rbx + TCJ_result]
    lea rsi, [rbx + TCJ_decode]
    mov rdx, [r12 + TCB_bytes]
    call tc_result_decode_step
    cmp rdx, [r12 + TCB_bytes]
    ja .Ltcjst_protocol
    sub [r12 + TCB_bytes], rdx
    mov [rsp + 32], rax
    mov [rsp + 40], rcx
    test rcx, rcx
    jns 91f
    mov rdi, rbx
    mov rsi, rcx
    call tcj_cleanup_abort
91: mov rax, [rsp + 32]
    test rax, rax
    js .Ltcjst_error
    cmp qword ptr [rsp + 40], 0
    jl .Ltcjst_terminal
    jg .Ltcjst_protocol
    cmp rax, 1
    je .Ltcjst_pending
    test rax, rax
    jnz .Ltcjst_protocol
    mov qword ptr [rbx + TCJ_state], TCJS_READY
    jmp .Ltcjst_terminal
.Ltcjst_decode_cleanup:
    mov rdi, rbx
    mov rsi, rcx
    call tcj_cleanup_abort
    jmp .Ltcjst_terminal
.Ltcjst_poll:
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    call ext_settings_native_poll
    cmp rax, ESJ_LOST
    ja .Ltcjst_poll_invalid
    mov [rbx + TCJ_authority], rax
    mov [rbx + TCJ_exit], rdx
    test rcx, rcx
    jns 4f
    cmp qword ptr [rbx + TCJ_observation], 0
    jne 30f
    mov [rbx + TCJ_observation], rcx
30: mov rdi, rbx
    mov rsi, rcx
    call tc_job_error
4:  cmp qword ptr [rbx + TCJ_authority], ESJ_LOST
    je .Ltcjst_lost
    cmp qword ptr [rbx + TCJ_authority], ESJ_NONE
    je .Ltcjst_none
    cmp qword ptr [rbx + TCJ_authority], ESJ_REAPED
    jne .Ltcjst_close
    cmp qword ptr [rbx + TCJ_closing], 0
    jne .Ltcjst_close
    cmp qword ptr [rbx + TCJ_exit], 0
    jne .Ltcjst_child_error
    cmp qword ptr [rbx + TCJ_input_closed], 1
    jne .Ltcjst_poll_protocol
    cmp qword ptr [rbx + TCJ_tx_pending], 0
    jne .Ltcjst_poll_protocol
    jmp .Ltcjst_close
.Ltcjst_poll_invalid:
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
    jmp .Ltcjst_close
.Ltcjst_lost:
    mov rdi, rbx
    mov rsi, -10
    call tc_job_error
    jmp .Ltcjst_close
.Ltcjst_none:
    mov rax, [rbx + TCJ_primary]
    or rax, [rbx + TCJ_cleanup]
    jnz .Ltcjst_close
.Ltcjst_child_error:
    mov rdi, rbx
    mov rsi, -5
    call tc_job_error
    jmp .Ltcjst_close
.Ltcjst_poll_protocol:
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
.Ltcjst_close:
    cmp qword ptr [rbx + TCJ_closing], 0
    je .Ltcjst_tx
    cmp qword ptr [rbx + TCJ_input_closed], 0
    jne 5f
    mov qword ptr [rbx + TCJ_input_closed], 1
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    call ext_settings_native_close_input
    test rax, rax
    jns 5f
    cmp rax, -115
    jne 40f
    mov qword ptr [rbx + TCJ_input_closed], 2
    jmp 5f
40: mov rdi, rbx
    mov rsi, rax
    call tcj_cleanup_abort
5:  cmp qword ptr [rbx + TCJ_authority], ESJ_OWNED
    jne .Ltcjst_tx
    cmp qword ptr [rbx + TCJ_killed], 0
    jne .Ltcjst_tx
    mov qword ptr [rbx + TCJ_killed], 1
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    call ext_settings_native_kill
    test rax, rax
    jns .Ltcjst_tx
    cmp qword ptr [rbx + TCJ_observation], 0
    jne 6f
    mov [rbx + TCJ_observation], rax
6:  mov rdi, rbx
    mov rsi, rax
    call tc_job_error
.Ltcjst_tx:
    cmp qword ptr [r12 + TCB_bytes], 0
    je .Ltcjst_reads
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    mov rsi, [r12 + TCB_bytes]
    call ext_settings_native_write_poll
    cmp rdx, [r12 + TCB_bytes]
    ja .Ltcjst_io_protocol
    sub [r12 + TCB_bytes], rdx
    cmp rcx, 1
    ja .Ltcjst_io_protocol
    test rax, rax
    js .Ltcjst_tx_error
    cmp rax, 1
    ja .Ltcjst_io_protocol
    test rax, rax
    jz .Ltcjst_reads
    cmp qword ptr [rbx + TCJ_tx_pending], 0
    je .Ltcjst_queue
    mov rax, [rbx + TCJ_tx_chunk]
    add [rbx + TCJ_tx_offset], rax
    mov qword ptr [rbx + TCJ_tx_pending], 0
    mov qword ptr [rbx + TCJ_tx_chunk], 0
.Ltcjst_queue:
    cmp qword ptr [rbx + TCJ_closing], 0
    jne .Ltcjst_reads
    cmp qword ptr [rbx + TCJ_authority], ESJ_OWNED
    jne .Ltcjst_reads
    mov rax, [rbx + TCJ_request]
    mov r14, [rax + TCQ_length]
    sub r14, [rbx + TCJ_tx_offset]
    jc .Ltcjst_io_protocol
    jz .Ltcjst_input_eof
    cmp r14, [r12 + TCB_bytes]
    cmova r14, [r12 + TCB_bytes]
    test r14, r14
    jz .Ltcjst_reads
    mov rsi, [rax + TCQ_wire]
    add rsi, [rbx + TCJ_tx_offset]
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    mov rdx, r14
    call ext_settings_native_write_begin
    test rax, rax
    js .Ltcjst_tx_error
    jz .Ltcjst_reads
    cmp rax, 1
    jne .Ltcjst_io_protocol
    sub [r12 + TCB_bytes], r14
    mov [rbx + TCJ_tx_chunk], r14
    mov qword ptr [rbx + TCJ_tx_pending], 1
    jmp .Ltcjst_reads
.Ltcjst_input_eof:
    cmp qword ptr [rbx + TCJ_input_closed], 0
    jne .Ltcjst_reads
    mov qword ptr [rbx + TCJ_input_closed], 1
    dec qword ptr [r12 + TCB_calls]
    mov rdi, [rbx + TCJ_native]
    call ext_settings_native_close_input
    test rax, rax
    jns .Ltcjst_reads
    cmp rax, -115
    jne 7f
    mov qword ptr [rbx + TCJ_input_closed], 2
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
    jmp .Ltcjst_reads
7:  mov rdi, rbx
    mov rsi, rax
    call tcj_cleanup_abort
    jmp .Ltcjst_reads
.Ltcjst_tx_error:
    mov rdi, rbx
    mov rsi, rax
    call tc_job_error
    jmp .Ltcjst_reads
.Ltcjst_io_protocol:
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
.Ltcjst_reads:
    xor r15d, r15d
.Ltcjst_read_loop:
    cmp r15, 3
    jae .Ltcjst_check_retire
    cmp qword ptr [r12 + TCB_bytes], 0
    je .Ltcjst_check_retire
    cmp qword ptr [r12 + TCB_calls], 2
    jb .Ltcjst_check_retire
    mov r14, [rbx + TCJ_read_stream]
    inc qword ptr [rbx + TCJ_read_stream]
    cmp qword ptr [rbx + TCJ_read_stream], 3
    jb 8f
    mov qword ptr [rbx + TCJ_read_stream], 0
8:  inc r15
    bt qword ptr [rbx + TCJ_eof], r14
    jc .Ltcjst_read_loop
    lea rdx, [rbx + TCJ_scratch]
    mov ecx, 4096
    mov qword ptr [rsp + 16], 0
    test r14, r14
    jnz .Ltcjst_read_count
    cmp qword ptr [rbx + TCJ_closing], 0
    jne .Ltcjst_read_count
    mov rcx, TC_OUTPUT_CAP
    sub rcx, [rbx + TCJ_used]
    jc .Ltcjst_io_protocol
    jz .Ltcjst_overflow_probe
    mov rax, [rbx + TCJ_result]
    mov rdx, [rax + TCS_wire]
    add rdx, [rbx + TCJ_used]
    mov qword ptr [rsp + 16], 1
    jmp .Ltcjst_read_count
.Ltcjst_overflow_probe:
    mov ecx, 1
.Ltcjst_read_count:
    cmp rcx, [r12 + TCB_bytes]
    cmova rcx, [r12 + TCB_bytes]
    mov [rsp + 24], rcx
    sub qword ptr [r12 + TCB_calls], 2
    mov rdi, [rbx + TCJ_native]
    mov rsi, r14
    call ext_settings_native_read
    cmp rax, -EINTR
    je .Ltcjst_read_loop
    cmp rax, -11
    je .Ltcjst_read_loop
    test rax, rax
    js .Ltcjst_read_error
    jz .Ltcjst_read_eof
    cmp rax, [rsp + 24]
    ja .Ltcjst_io_protocol
    sub [r12 + TCB_bytes], rax
    test r14, r14
    jnz .Ltcjst_read_protocol
    cmp qword ptr [rsp + 16], 1
    jne .Ltcjst_discarded
    add [rbx + TCJ_used], rax
    jmp .Ltcjst_read_loop
.Ltcjst_discarded:
    cmp qword ptr [rbx + TCJ_closing], 0
    jne .Ltcjst_read_loop
    mov rdi, rbx
    mov rsi, -7
    call tc_job_error
    jmp .Ltcjst_read_loop
.Ltcjst_read_error:
    mov rdi, rbx
    mov rsi, rax
    call tc_job_error
    jmp .Ltcjst_read_loop
.Ltcjst_read_protocol:
    mov rdi, rbx
    mov rsi, -71
    call tc_job_error
    jmp .Ltcjst_read_loop
.Ltcjst_read_eof:
    bts qword ptr [rbx + TCJ_eof], r14
    jmp .Ltcjst_read_loop
.Ltcjst_check_retire:
    cmp qword ptr [rbx + TCJ_authority], ESJ_OWNED
    je .Ltcjst_pending
    cmp qword ptr [rbx + TCJ_closing], 0
    jne 9f
    cmp qword ptr [rbx + TCJ_eof], 7
    jne .Ltcjst_pending
    cmp qword ptr [rbx + TCJ_input_closed], 1
    jne .Ltcjst_pending
    cmp qword ptr [rbx + TCJ_tx_pending], 0
    jne .Ltcjst_pending
9:  mov qword ptr [rbx + TCJ_retire_requested], 1
    jmp .Ltcjst_pending
.Ltcjst_protocol:
    mov rax, -71
.Ltcjst_error:
    mov rdi, rbx
    mov rsi, rax
    call tc_job_error
    cmp qword ptr [rbx + TCJ_native], 0
    je .Ltcjst_terminal
    jmp .Ltcjst_pending
.Ltcjst_missing_native:
    mov rdi, rbx
    mov rsi, -5
    call tc_job_error
.Ltcjst_terminal:
    xor eax, eax
    mov rdx, [rbx + TCJ_primary]
    mov rcx, [rbx + TCJ_cleanup]
    EPILOGUE
.Ltcjst_pending:
    mov eax, 1
    mov rdx, [rbx + TCJ_primary]
    mov rcx, [rbx + TCJ_cleanup]
    EPILOGUE
.Ltcjst_bad:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltcjst_bad_leaf:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
