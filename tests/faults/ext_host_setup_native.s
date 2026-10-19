# Actual lifecycle foundation, with one selected closed-gate setup fault.
.bss
.p2align 3
hs_armed: .quad 0
hs_pipe_calls: .quad 0
hs_log_calls: .quad 0
hs_watch_calls: .quad 0
hs_faults: .quad 0
hs_close_faults: .quad 0
hs_kx: .quad 0
hs_returned_keeper: .quad 0
hs_returned_primary: .quad 0
hs_returned_cleanup: .quad 0
hs_close_id: .quad 0
hs_close_calls: .quad 0
.text
hs_case:
    PROLOGUE
    mov qword ptr [rip + tek_stage], 101
    call lc_reset
    mov qword ptr [rip + hs_armed], 1
    call lc_start
    lea rbx, [rip + lc_extension]
    mov qword ptr [rip + tek_stage], 102
    cmp dword ptr [rbx + EXT_startaccepted], 0
    jne .Ltek_fail
.if HS_MODE >= 16
    cmp qword ptr [rip + hs_faults], 2
.else
    cmp qword ptr [rip + hs_faults], 1
.endif
    jne .Ltek_fail
.if HS_MODE >= 9 && HS_MODE <= 15 && HS_MODE != 11
    cmp qword ptr [rip + hs_returned_keeper], 0
    jle .Ltek_fail
    # The start failure may already have completed checked native collection.
    mov rdi, [rbx + EXT_keeper]
    test rdi, rdi
    jnz .Lhs_keeper_installed
    mov rdi, [rip + hs_returned_keeper]
    call kp_find
    test rax, rax
    jnz .Ltek_fail
    jmp .Lhs_keeper_owned_or_collected
.Lhs_keeper_installed:
    cmp rdi, [rip + hs_returned_keeper]
    jne .Ltek_fail
.Lhs_keeper_owned_or_collected:
    cmp qword ptr [rbx + EXT_activation_owner], 0
    je .Ltek_fail
    cmp qword ptr [rbx + EXT_metadata_owner], 0
    je .Ltek_fail
.if HS_MODE == 15
    cmp qword ptr [rip + hs_returned_primary], -13
    jne .Ltek_fail
    cmp qword ptr [rip + hs_returned_cleanup], -13
    jne .Ltek_fail
.endif
.if HS_MODE == 13
    mov rdi, rbx
    mov esi, 4
    call ext_host_retry_known
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
.endif
    call time_ms
    lea r12, [rax + 10000]
1:  call ext_tick
    cmp dword ptr [rbx + EXT_startaccepted], 0
    jne .Ltek_fail
    cmp qword ptr [rbx + EXT_keeper], 0
    je 2f
    call time_ms
    cmp rax, r12
    jae .Ltek_fail
    xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp 1b
2:  cmp dword ptr [rbx + EXT_pid], 0
    jne .Ltek_fail
.if HS_MODE == 14
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 16
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_host_cleanup_error], -5
    jne .Ltek_fail
    cmp qword ptr [rip + hs_close_calls], 1
    jne .Ltek_fail
    mov rdi, rbx
    mov esi, 4
    call ext_host_retry_known
    cmp rdx, 2
    jne .Ltek_fail
    cmp qword ptr [rip + hs_close_calls], 1
    jne .Ltek_fail
    mov rdi, rbx
    call ext_host_prepared_timeout
    cmp rax, -1
    jne .Ltek_fail
    call ext_prepare_retire_charge
    test rax, rax
    jle .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + lc_old_ea]
    call ext_activation_host_swap
    cmp rax, -16
    jne .Ltek_fail
    test rdx, rdx
    jnz .Ltek_fail
    call lc_no_marker
    xor eax, eax
    EPILOGUE
.endif
    cmp dword ptr [rbx + EXT_stdout_eof], 1
    je 3f
    cmp dword ptr [rbx + EXT_retiring], 4
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jns .Ltek_fail
3:
.if HS_MODE == 9 || HS_MODE == 10
    cmp dword ptr [rbx + EXT_host_setup_error], -28
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_finish_code], -28
    jne .Ltek_fail
.endif
.if HS_MODE == 12 || HS_MODE == 13
    cmp dword ptr [rbx + EXT_host_cleanup_error], -5
    jne .Ltek_fail
.endif
.if HS_MODE == 13
    cmp qword ptr [rip + hs_close_calls], 2
    jne .Ltek_fail
.endif
.else
    cmp qword ptr [rbx + EXT_keeper], 0
    jne .Ltek_fail
    cmp qword ptr [rip + hs_returned_keeper], 0
    jg .Ltek_fail
    cmp dword ptr [rbx + EXT_pid], 0
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Ltek_fail
    # No-child setup debt is terminal only after explicit checked consumption.
.if HS_MODE >= 16
    cmp dword ptr [rbx + EXT_retiring], 3
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_host_setup_error], -24
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_host_cleanup_error], -5
    jne .Ltek_fail
.if HS_MODE == 16
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 8
    jne .Ltek_fail
    mov r13d, 8
11: call ext_tick
    dec r13d
    jnz 11b
    cmp qword ptr [rip + hs_close_calls], 1
    jne .Ltek_fail
    mov rdi, rbx
    mov esi, 3
    call ext_host_retry_known
    cmp rdx, 2
    jne .Ltek_fail
    cmp qword ptr [rip + hs_close_calls], 1
    jne .Ltek_fail
    mov rdi, rbx
    call ext_host_prepared_timeout
    cmp rax, -1
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Ltek_fail
    call ext_prepare_retire_charge
    test rax, rax
    jle .Ltek_fail
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + lc_old_ea]
    call ext_activation_host_swap
    cmp rax, -16
    jne .Ltek_fail
    test rdx, rdx
    jnz .Ltek_fail
    call lc_no_marker
    xor eax, eax
    EPILOGUE
.else
.if HS_MODE == 17
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 2048
    jne .Ltek_fail
    mov rdi, rbx
    mov esi, 3
    call ext_host_retry_known
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
.endif
    call ext_tick
    cmp dword ptr [rbx + EXT_retiring], 4
    jne .Ltek_fail
    cmp dword ptr [rbx + EXT_stdout_eof], 0
    jne .Ltek_fail
.endif
.else
    cmp dword ptr [rbx + EXT_retiring], 0
    jne .Ltek_fail
.endif
.if HS_MODE == 1 || HS_MODE == 2 || HS_MODE == 8 || HS_MODE >= 16
    cmp dword ptr [rbx + EXT_finish_code], -24
.else
.if HS_MODE == 7
    cmp dword ptr [rbx + EXT_finish_code], -13
.else
.if HS_MODE == 11
    cmp dword ptr [rbx + EXT_finish_code], -12
.else
    cmp dword ptr [rbx + EXT_finish_code], -5
.endif
.endif
.endif
    jne .Ltek_fail
.endif
    mov qword ptr [rip + tek_stage], 103
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Ltek_fail
    call lc_no_marker
    call lc_owner_take
    mov qword ptr [rip + tek_owned_plan], 0
    call lc_metadata_drop
    mov qword ptr [rip + lc_ep], 0
    call lc_retire_pump
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Ltek_fail
    xor eax, eax
    EPILOGUE

FN hs_pipe
    cmp qword ptr [rip + hs_armed], 0
    je hs_real_pipe
    inc qword ptr [rip + hs_pipe_calls]
.if HS_MODE == 1 || HS_MODE == 8
    cmp qword ptr [rip + hs_pipe_calls], 1
.else
.if HS_MODE == 2 || HS_MODE >= 16
    cmp qword ptr [rip + hs_pipe_calls], 2
.else
    jmp hs_real_pipe
.endif
.endif
    jne hs_real_pipe
    inc qword ptr [rip + hs_faults]
    mov rax, -24
    ret
FN hs_log
    inc qword ptr [rip + hs_log_calls]
.if HS_MODE == 7
    mov qword ptr [rip + hs_faults], 1
    mov rax, -13
    ret
.else
.if HS_MODE == 8
    cmp qword ptr [rip + hs_log_calls], 1
    jne hs_real_log
    mov rax, -13
    ret
.else
    jmp hs_real_log
.endif
.endif
FN hs_nonblock_out
.if HS_MODE == 3
    inc qword ptr [rip + hs_faults]
    mov rax, -5
    ret
.else
    SYS SYS_fcntl
    ret
.endif
FN hs_nonblock_in
.if HS_MODE == 4
    inc qword ptr [rip + hs_faults]
    mov rax, -5
    ret
.else
    SYS SYS_fcntl
    ret
.endif
FN hs_cloexec_first
.if HS_MODE == 5
    cmp qword ptr [rip + hs_faults], 0
    jne 1f
    inc qword ptr [rip + hs_faults]
    mov rax, -5
    ret
1:
.endif
    SYS SYS_fcntl
    ret
FN hs_cloexec_second
.if HS_MODE == 6
    cmp qword ptr [rip + hs_faults], 0
    jne 1f
    inc qword ptr [rip + hs_faults]
    mov rax, -5
    ret
1:
.endif
    SYS SYS_fcntl
    ret
FN hs_watch
    cmp qword ptr [rip + hs_armed], 0
    je hs_real_watch
    inc qword ptr [rip + hs_watch_calls]
.if HS_MODE == 9
    cmp qword ptr [rip + hs_watch_calls], 1
.else
.if HS_MODE == 10
    cmp qword ptr [rip + hs_watch_calls], 2
.else
    jmp hs_real_watch
.endif
.endif
    jne hs_real_watch
    inc qword ptr [rip + hs_faults]
    xor eax, eax
    ret
FN hs_prepare
.if HS_MODE == 11
    inc qword ptr [rip + hs_faults]
    mov rax, -12
    xor edx, edx
    xor ecx, ecx
    ret
.else
    PROLOGUE
    call keeper_prepare
    mov [rip + hs_returned_keeper], rax
    mov [rip + hs_returned_primary], rdx
    mov [rip + hs_returned_cleanup], rcx
    EPILOGUE
.endif
FN hs_capture
    mov [rip + hs_kx], rdi
    ret
FN hs_close
.if HS_MODE == 12 || HS_MODE == 13 || HS_MODE == 14 || HS_MODE >= 16
.if HS_MODE >= 16
    cmp edi, [rip + lc_extension + EXT_host_child_in]
.else
    cmp edi, [rip + lc_extension + EXT_host_child_out]
.endif
    jne hs_real_close
    cmp qword ptr [rip + hs_close_id], 0
    jne 1f
    mov [rip + hs_close_id], rdi
1:  inc qword ptr [rip + hs_close_calls]
    cmp qword ptr [rip + hs_close_faults], 0
    jne hs_real_close
.else
.if HS_MODE == 15
    mov rax, [rip + hs_kx]
    test rax, rax
    jz hs_real_close
    cmp qword ptr [rax + KX_native_state], KN_OWNED
    jne hs_real_close
    cmp qword ptr [rax + KX_sent], 0
    jne hs_real_close
    cmp qword ptr [rip + hs_close_faults], 0
    jne hs_real_close
.else
    jmp hs_real_close
.endif
.endif
    inc qword ptr [rip + hs_faults]
    inc qword ptr [rip + hs_close_faults]
.if HS_MODE == 13 || HS_MODE == 17
    mov rax, -5
    xor edx, edx
    ret
.else
    PROLOGUE
    call hs_real_close
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
.if HS_MODE == 15
    mov rax, -13
.else
    mov rax, -5
.endif
.if HS_MODE == 14 || HS_MODE == 16
    mov edx, 2
.else
    mov edx, 1
.endif
    EPILOGUE
.endif
