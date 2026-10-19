.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/taskproc.inc"
.bss
kcs_pair: .zero 8
kcs_bytes: .zero 64
.text
FN kcs_read
.if KCS_CASE == 0
    mov rax, -5
    ret
.else
    SYS SYS_read
    ret
.endif
FN main
    PROLOGUE
    lea rbx, [rip + kp_slots]
    mov rdi, rbx
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    lea rdi, [rbx + KX_native]
    call kp_native_init
    mov qword ptr [rbx + KX_id], 123
    mov qword ptr [rbx + KX_mode], KP_EXTENSION
    mov qword ptr [rbx + KX_native_state], KN_REAPED
    mov dword ptr [rbx + KX_reaped], 1
    mov qword ptr [rbx + KX_no_target], 1
    mov qword ptr [rbx + KX_sent], 1
    mov dword ptr [rbx + KX_helper_exit], 111
    mov qword ptr [rbx + KX_control], -1
    mov qword ptr [rbx + KX_output], -1
    mov qword ptr [rbx + KX_launchfd], -1
    mov qword ptr [rbx + KX_lease], -1
.if KCS_CASE == 3
    mov qword ptr [rbx + KX_preexec_failed], 1
.endif
.if KCS_CASE == 4
    mov qword ptr [rbx + KX_prepare_failed], 1
.endif
    lea rdi, [rip + kcs_pair]
    mov esi, O_NONBLOCK | O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js 9f
    movsxd rax, dword ptr [rip + kcs_pair]
    mov [rbx + KX_status], rax
    movsxd rdi, dword ptr [rip + kcs_pair + 4]
    lea rsi, [rip + kcs_bytes]
.if KCS_CASE == 2
    mov edx, 3
.else
    mov edx, 64
.endif
    SYS SYS_write
    test rax, rax
    jle 9f
    movsxd rdi, dword ptr [rip + kcs_pair + 4]
    call ext_fd_close_checked
    test rax, rax
    jnz 9f
    mov edi, 123
    call keeper_poll
    test eax, KP_FAILED
    jz 9f
    cmp qword ptr [rbx + KX_status_failed], 1
    jne 9f
    cmp qword ptr [rbx + KX_protocol_bad], 1
    jne 9f
.if KCS_CASE == 2
    cmp qword ptr [rbx + KX_status_eof], 1
.else
    cmp qword ptr [rbx + KX_status_eof], 0
.endif
    jne 9f
.if KCS_CASE == 3 || KCS_CASE == 4
    cmp qword ptr [rbx + KX_no_target], 1
    jne 9f
    cmp qword ptr [rbx + KX_lifetime_ready], 1
.else
    cmp qword ptr [rbx + KX_no_target], 0
    jne 9f
    test eax, KP_DONE
    jnz 9f
    cmp qword ptr [rbx + KX_lifetime_ready], 0
.endif
    jne 9f
    # Test teardown only: no actual child was created by this synthetic record.
    mov qword ptr [rbx + KX_lifetime_ready], 1
    mov edi, 123
    call keeper_close_checked
    test rax, rax
    jnz 9f
    cmp rdx, 1
    jne 9f
    xor eax, eax
    EPILOGUE
9:  mov edi, 73
    call sys_exit
