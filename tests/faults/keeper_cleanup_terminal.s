.include "rhun.inc"
.include "app/taskproc.inc"
.text
FN main
    PROLOGUE KX_SIZE
    mov rdi, rsp
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    mov qword ptr [rsp + KX_native_state], KN_REAPED
    mov dword ptr [rsp + KX_reaped], 1
    mov qword ptr [rsp + KX_status_eof], 1
    mov dword ptr [rsp + KX_helper_exit], 111
    mov dword ptr [rsp + KX_wireflags], KP_DONE | KP_FAILED | KP_DEFERRED
    mov dword ptr [rsp + KX_lastframe + 20], -13
.if KCT_CASE == 1
    mov qword ptr [rsp + KX_native_state], KN_LOST
.endif
.if KCT_CASE == 2
    mov qword ptr [rsp + KX_native_state], KN_OWNED
.endif
.if KCT_CASE == 3
    mov dword ptr [rsp + KX_reaped], 0
.endif
.if KCT_CASE == 4
    mov qword ptr [rsp + KX_status_eof], 0
.endif
.if KCT_CASE == 5
    mov qword ptr [rsp + KX_protocol_bad], 1
.endif
.if KCT_CASE == 6
    mov dword ptr [rsp + KX_helper_exit], 112
.endif
.if KCT_CASE == 7
    mov dword ptr [rsp + KX_wireflags], KP_FAILED | KP_DEFERRED
.endif
.if KCT_CASE == 8
    mov dword ptr [rsp + KX_wireflags], KP_DONE | KP_DEFERRED
.endif
.if KCT_CASE == 9
    mov dword ptr [rsp + KX_wireflags], KP_DONE | KP_FAILED
.endif
.if KCT_CASE == 10
    mov dword ptr [rsp + KX_lastframe + 20], 0
.endif
.if KCT_CASE == 11
    mov dword ptr [rsp + KX_lastframe + 20], -4096
.endif
.if KCT_CASE == 12
    mov dword ptr [rsp + KX_lastframe + 20], 1
.endif
.if KCT_CASE == 13
    mov dword ptr [rsp + KX_helper_exit], 0
.endif
.if KCT_CASE == 14
    mov dword ptr [rsp + KX_helper_exit], 0
    mov dword ptr [rsp + KX_wireflags], 0
.endif
    mov rdi, rsp
    call kp_cleanup_terminal
.if KCT_CASE == 0 || KCT_CASE == 13
    cmp eax, 1
.else
    test eax, eax
.endif
    jne 1f
    cmp qword ptr [rsp + KX_lifetime_ready], 0
    jne 1f
    xor eax, eax
    EPILOGUE
1:  mov edi, 73
    call sys_exit
