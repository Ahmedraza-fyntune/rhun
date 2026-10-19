.include "rhun.inc"
.section .rodata
ef_ok: .asciz "ok bounded extension flush\n"
.data
ef_data: .ascii "0123456789abcdef"
.bss
.p2align 3
ef_ext: .zero EXT_SIZE
ef_calls: .quad 0
ef_mode: .quad 0
ef_events: .quad 0
ef_total: .quad 0
ef_stage: .quad 0
.text
FN main
    PROLOGUE
    lea rbx, [rip + ef_ext]
    mov dword ptr [rbx + EXT_in], 9999
    lea rax, [rip + ef_data]
    mov [rbx + EXT_wq + SB_ptr], rax
    mov qword ptr [rbx + EXT_wq + SB_len], 16
    mov qword ptr [rbx + EXT_wq + SB_cap], 16
    # Repeated interruptions consume attempts rather than spin.
    mov qword ptr [rip + ef_stage], 1
    mov rdi, rbx
    mov esi, 16
    mov edx, 16
    call ext_flush_quota
    test rax, rax
    jnz .Lef_fail
    cmp qword ptr [rip + ef_calls], 16
    jne .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne .Lef_fail
    cmp qword ptr [rip + ef_events], POLLOUT
    jne .Lef_fail
    # Partial writes cannot exceed a byte quota, including the last request.
    mov qword ptr [rip + ef_stage], 2
    mov qword ptr [rip + ef_calls], 0
    mov qword ptr [rip + ef_mode], 1
    mov rdi, rbx
    mov esi, 7
    mov edx, 16
    call ext_flush_quota
    test rax, rax
    jnz .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 7
    jne .Lef_fail
    cmp qword ptr [rip + ef_total], 7
    jne .Lef_fail
    cmp qword ptr [rip + ef_calls], 3
    jne .Lef_fail
    # Full pipe preserves prefix and POLLOUT.
    mov qword ptr [rip + ef_stage], 3
    mov qword ptr [rip + ef_mode], 2
    mov rdi, rbx
    mov esi, 16
    mov edx, 16
    call ext_flush_quota
    test rax, rax
    jnz .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 7
    jne .Lef_fail
    cmp qword ptr [rip + ef_events], POLLOUT
    jne .Lef_fail
    # Empty completion resets the counters and disables readiness.
    mov qword ptr [rip + ef_stage], 4
    mov qword ptr [rip + ef_mode], 1
    mov rdi, rbx
    mov esi, 65536
    mov edx, 16
    call ext_flush_quota
    test rax, rax
    jnz .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne .Lef_fail
    cmp qword ptr [rbx + EXT_wq + SB_len], 0
    jne .Lef_fail
    cmp qword ptr [rip + ef_events], 0
    jne .Lef_fail
    # Native failure and missing nonblocking mode prohibit every write.
    mov qword ptr [rip + ef_stage], 5
    mov qword ptr [rbx + EXT_wq + SB_len], 16
    mov qword ptr [rip + ef_calls], 0
    mov qword ptr [rip + ef_mode], 3
    mov rdi, rbx
    mov esi, 16
    mov edx, 16
    call ext_flush_quota
    cmp rax, -13
    jne .Lef_fail
    cmp qword ptr [rip + ef_calls], 0
    jne .Lef_fail
    mov qword ptr [rip + ef_mode], 4
    mov rdi, rbx
    mov esi, 16
    mov edx, 16
    call ext_flush_quota
    cmp rax, -11
    jne .Lef_fail
    cmp qword ptr [rip + ef_calls], 0
    jne .Lef_fail
    # Impossible native overcount cannot advance or clear pending bytes.
    mov qword ptr [rip + ef_stage], 6
    mov qword ptr [rip + ef_mode], 5
    mov rdi, rbx
    mov esi, 7
    mov edx, 16
    call ext_flush_quota
    cmp rax, -32
    jne .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne .Lef_fail
    cmp qword ptr [rbx + EXT_in_closed_at], 100
    jne .Lef_fail
    mov qword ptr [rbx + EXT_in_closed_at], 0
    mov qword ptr [rip + ef_mode], 6
    mov rdi, rbx
    mov esi, 7
    mov edx, 16
    call ext_flush_quota
    cmp rax, -32
    jne .Lef_fail
    cmp qword ptr [rbx + EXT_wq_off], 0
    jne .Lef_fail
    # Invalid ranges never touch the descriptor.
    mov qword ptr [rip + ef_stage], 7
    mov qword ptr [rbx + EXT_in_closed_at], 0
    mov qword ptr [rip + ef_calls], 0
    mov rdi, rbx
    xor esi, esi
    mov edx, 16
    call ext_flush_quota
    cmp rax, -22
    jne .Lef_fail
    cmp qword ptr [rip + ef_calls], 0
    jne .Lef_fail
    mov rdi, rbx
    mov esi, 1
    mov edx, 17
    call ext_flush_quota
    cmp rax, -22
    jne .Lef_fail
    lea rdi, [rip + ef_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lef_fail:
    mov rdi, [rip + ef_stage]
    add edi, 30
    SYS SYS_exit_group
    ud2

FN ef_fcntl
    cmp qword ptr [rip + ef_mode], 3
    je 2f
    cmp qword ptr [rip + ef_mode], 4
    je 1f
    mov eax, O_NONBLOCK
    ret
1:  xor eax, eax
    ret
2:  mov rax, -13
    ret

FN ef_write
    inc qword ptr [rip + ef_calls]
    mov rax, [rip + ef_mode]
    test eax, eax
    jz 1f
    cmp eax, 2
    je 2f
    cmp eax, 5
    je 3f
    cmp eax, 6
    je 4f
    mov eax, 3
    cmp rax, rdx
    cmova rax, rdx
    add [rip + ef_total], rax
    ret
1:  mov rax, -EINTR
    ret
2:  mov rax, -EAGAIN
    ret
3:  lea rax, [rdx + 1]
    ret
4:  mov rax, -32
    ret

FN ef_watch
    mov [rip + ef_events], rsi
    ret
FN ef_time
    mov eax, 100
    ret
