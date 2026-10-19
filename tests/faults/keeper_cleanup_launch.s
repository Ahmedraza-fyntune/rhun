.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/taskproc.inc"
.bss
kcp_owner: .quad 0
kcp_faults: .quad 0
kcp_observe: .quad 0
.text
FN kcp_capture
    mov [rip + kcp_owner], rdi
    ret
FN ext_fd_close_checked
    PROLOGUE 96
    mov rbx, rdi
    mov r12, [rip + kcp_owner]
    test r12, r12
    jz 9f
    cmp qword ptr [r12 + KX_native_state], KN_OWNED
    jne 9f
    cmp qword ptr [r12 + KX_sent], 0
    jne 9f
    cmp qword ptr [rip + kcp_faults], 0
    jne 9f
    mov qword ptr [rip + kcp_faults], 1
.if KCP_DISP != 0
.ifdef WINDOWS
    mov rdi, rbx
    call win_fd
    test rax, rax
    jz 8f
    mov r13, rax
    mov rcx, [rax + FD_handle]
    API CloseHandle
    test eax, eax
    jz 8f
.if KCP_DISP == 1
    mov rdi, [r13 + FD_path]
    call mem_free
    mov rdi, r13
    xor esi, esi
    mov edx, FD_SIZE
    call memset
.endif
.else
    mov rdi, rbx
    call kcp_real_fd_close
    test rax, rax
    jnz 8f
.endif
.endif
    mov rax, -13
    mov edx, KCP_DISP
    EPILOGUE
9:  mov rdi, rbx
    call kcp_real_fd_close
    EPILOGUE
8:  mov edi, 73
    call sys_exit

# Observation failure is not native collection, even after the service was signaled.
FN kcp_wait
    cmp qword ptr [rip + kcp_observe], 0
    je 1f
.ifdef WINDOWS
    mov eax, -1
.else
    mov rax, -5
.endif
    ret
1:
.ifdef WINDOWS
    PROLOGUE 96
    API WaitForSingleObject
    EPILOGUE
.else
    SYS SYS_wait4
    ret
.endif
