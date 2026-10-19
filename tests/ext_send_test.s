.include "rhun.inc"
.bss
.p2align 3
est_ext: .zero EXT_SIZE
est_pipe: .zero 8
est_sigact: .zero 32
est_read: .zero 16
est_drain: .zero 4096
est_pad: .zero 4096
est_large: .zero 65536
est_live: .quad 0
est_stage: .quad 0
.section .rodata
est_binary: .byte 'a',0,'b'
est_prefix: .ascii "sent!TAIL"
est_combined: .byte 'T','A','I','L','a',0,'b'
est_ok: .asciz "ok checked extension enqueue\n"
.text
est_fail:
    mov edi, [rip + est_stage]
    add edi, 100
    call sys_exit
est_zero:
    test rax, rax
    jnz est_fail
    ret
est_send:
    lea rdi, [rip + est_ext]
    jmp ext_send_checked
est_receive:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov edi, [rip + est_pipe]
    lea rsi, [rip + est_read]
    mov rdx, r13
    SYS SYS_read
    cmp rax, r13
    jne est_fail
    lea rdi, [rip + est_read]
    mov rsi, r13
    mov rdx, r12
    mov rcx, r13
    call str_eq
    cmp eax, 1
    jne est_fail
    EPILOGUE

# Fill an actual nonblocking pipe, retain a queued suffix, then drain/flush it in order.
est_backpressure:
    PROLOGUE
    mov qword ptr [rip + est_stage], 80
    mov edi, [rip + est_pipe]
    mov esi, 4
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test rax, rax
    js est_fail
    mov edi, [rip + est_pipe + 4]
    mov esi, 4
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test rax, rax
    js est_fail
    lea rdi, [rip + est_pad]
    mov qword ptr [rip + est_stage], 81
    mov esi, 'P'
    mov edx, 4096
    call memset
    lea rdi, [rip + est_large]
    mov rax, 0x76374657d2e72a19
    xor ecx, ecx
1:  rol rax, 7
    xor rax, rcx
    imul rax, rax, 1103515245
    add rax, 12345
    mov rdx, rax
    shr rdx, 32
    mov [rdi + rcx], dl
    inc ecx
    cmp ecx, 65536
    jb 1b
    xor r12d, r12d             # total P bytes accepted by the native pipe
    mov r13d, 4096
.Lest_fill:
    mov qword ptr [rip + est_stage], 82
    cmp r12, 2097152
    jae est_fail
    mov edi, [rip + est_pipe + 4]
    lea rsi, [rip + est_pad]
    mov rdx, r13
    SYS SYS_write
    cmp rax, -EINTR
    je .Lest_fill
    cmp rax, -EAGAIN
    je .Lest_full
    test rax, rax
    jle est_fail
    add r12, rax
    jmp .Lest_fill
.Lest_full:
    cmp r13, 1
    je .Lest_enqueue_full
    mov r13d, 1                # fill any remainder smaller than PIPE_BUF
    jmp .Lest_fill
.Lest_enqueue_full:
    mov qword ptr [rip + est_stage], 83
    lea rsi, [rip + est_large]
    mov edx, 65536
    call est_send
    call est_zero
    mov rax, [rip + est_ext + EXT_wq + SB_len]
    sub rax, [rip + est_ext + EXT_wq_off]
    cmp rax, 65536
    jne est_fail
    xor r13d, r13d             # stream bytes read so far
    mov qword ptr [rip + est_stage], 84
    xor r15d, r15d             # bounded read/flush rounds
.Lest_drain:
    mov qword ptr [rip + est_stage], 85
    inc r15
    cmp r15, 4096
    ja est_fail
    mov edi, [rip + est_pipe]
    lea rsi, [rip + est_drain]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je .Lest_drain
    cmp rax, -EAGAIN
    je .Lest_flush
    test rax, rax
    jle est_fail
    mov r14, rax
    xor ecx, ecx
    lea r8, [rip + est_drain]
.Lest_bytes:
    lea rax, [r13 + rcx]
    cmp rax, r12
    jae .Lest_q
    cmp byte ptr [r8 + rcx], 'P'
    jne est_fail
    jmp .Lest_next_byte
.Lest_q:
    sub rax, r12
    cmp rax, 65536
    jae est_fail
    lea rdx, [rip + est_large]
    movzx eax, byte ptr [rdx + rax]
    cmp [r8 + rcx], al
    jne est_fail
.Lest_next_byte:
    inc rcx
    cmp rcx, r14
    jb .Lest_bytes
    add r13, r14
.Lest_flush:
    xor esi, esi
    xor edx, edx
    call est_send
    call est_zero
    cmp r15, 1
    jne .Lest_total
    mov qword ptr [rip + est_stage], 86
.ifndef WINDOWS
    cmp qword ptr [rip + est_ext + EXT_wq_off], 0
    je est_fail                # the first freed chunk permitted a real partial write
.endif
    # Windows/Wine may retain the whole queued write until it fits. Both forms
    # must preserve the exact suffix; the byte-wise oracle below checks either.
    mov rax, [rip + est_ext + EXT_wq_off]
    cmp rax, [rip + est_ext + EXT_wq + SB_len]
    jae est_fail
.Lest_total:
    mov qword ptr [rip + est_stage], 87
    lea rax, [r12 + 65536]
    cmp r13, rax
    jb .Lest_drain
    jne est_fail
    cmp qword ptr [rip + est_ext + EXT_wq + SB_len], 0
    jne est_fail
    cmp qword ptr [rip + est_ext + EXT_wq_off], 0
    jne est_fail
    mov edi, [rip + est_pipe]
    lea rsi, [rip + est_read]
    mov edx, 1
    SYS SYS_read
    cmp rax, -EAGAIN
    jne est_fail
    EPILOGUE
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + est_live], rax
    mov qword ptr [rip + est_sigact], 1
    mov edi, 13
    lea rsi, [rip + est_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    lea rdi, [rip + est_pipe]
    xor esi, esi
    SYS SYS_pipe2
    test rax, rax
    js est_fail
    mov eax, [rip + est_pipe + 4]
    mov [rip + est_ext + EXT_in], eax
    mov dword ptr [rip + est_ext + EXT_status], ES_RUNNING
    mov edi, [rip + est_pipe]
    mov esi, 4
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test rax, rax
    js est_fail
    mov edi, [rip + est_pipe + 4]
    mov esi, 4
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test rax, rax
    js est_fail
    mov qword ptr [rip + est_stage], 1
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    call est_zero
    lea rdi, [rip + est_binary]
    mov esi, 3
    call est_receive
    mov qword ptr [rip + est_stage], 2
    xor esi, esi
    xor edx, edx
    call est_send
    call est_zero
    mov qword ptr [rip + est_stage], 3
    xor esi, esi
    mov edx, 1
    call est_send
    cmp rax, -22
    jne est_fail
    mov qword ptr [rip + est_stage], 4
    mov dword ptr [rip + est_ext + EXT_status], ES_STOPPED
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    cmp rax, -32
    jne est_fail
    mov dword ptr [rip + est_ext + EXT_status], ES_RUNNING
    mov qword ptr [rip + est_ext + EXT_in_closed_at], 1
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    cmp rax, -32
    jne est_fail
    mov qword ptr [rip + est_ext + EXT_in_closed_at], 0
    mov dword ptr [rip + est_ext + EXT_in], -1
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    cmp rax, -32
    jne est_fail
    mov eax, [rip + est_pipe + 4]
    mov [rip + est_ext + EXT_in], eax
    mov qword ptr [rip + est_stage], 5
    mov qword ptr [rip + est_ext + EXT_wq + SB_len], EXT_WQ_HARD - 1
    mov qword ptr [rip + est_ext + EXT_full_since], 123
    lea rsi, [rip + est_binary]
    mov edx, 1
    call est_send
    cmp rax, -11
    jne est_fail
    cmp qword ptr [rip + est_ext + EXT_wq + SB_len], EXT_WQ_HARD - 1
    jne est_fail
    # the queue at its hard limit: not reading, so the next tick stops the program
    call time_ms
    sub rax, 10000
    cmp [rip + est_ext + EXT_full_since], rax
    jg est_fail
    mov qword ptr [rip + est_ext + EXT_wq + SB_len], 0
    mov qword ptr [rip + est_ext + EXT_full_since], 0
    lea rsi, [rip + est_binary]
    mov rdx, -1
    call est_send
    cmp rax, -11
    jne est_fail
    mov qword ptr [rip + est_ext + EXT_full_since], 0
    mov qword ptr [rip + est_stage], 6
    mov qword ptr [rip + est_ext + EXT_wq + SB_len], 5
    mov qword ptr [rip + est_ext + EXT_wq_off], 6
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    cmp rax, -22
    jne est_fail
    mov qword ptr [rip + est_ext + EXT_wq + SB_len], 0
    mov qword ptr [rip + est_ext + EXT_wq_off], 0
    mov qword ptr [rip + est_stage], 7
    mov rdi, [rip + est_ext + EXT_wq + SB_ptr]
    lea rsi, [rip + est_prefix]
    mov edx, 9
    call memcpy
    mov qword ptr [rip + est_ext + EXT_wq + SB_len], 9
    mov qword ptr [rip + est_ext + EXT_wq_off], 5
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    call est_zero
    lea rdi, [rip + est_combined]
    mov esi, 7
    call est_receive
    mov qword ptr [rip + est_stage], 8
    call est_backpressure
    mov qword ptr [rip + est_stage], 9
    mov edi, [rip + est_pipe]
    SYS SYS_close
    lea rsi, [rip + est_binary]
    mov edx, 3
    call est_send
    cmp rax, -32
    jne est_fail
    cmp qword ptr [rip + est_ext + EXT_in_closed_at], 0
    je est_fail
    mov edi, [rip + est_pipe + 4]
    SYS SYS_close
    mov rdi, [rip + est_ext + EXT_wq + SB_ptr]
    call mem_free
    mov rax, [rip + est_live]
    cmp rax, [rip + g_mem_live]
    jne est_fail
    lea rdi, [rip + est_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
