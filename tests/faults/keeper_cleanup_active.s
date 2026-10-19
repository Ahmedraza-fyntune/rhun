.section .rodata
kpo_null: .asciz "/dev/null"
.bss
kpo_owner: .quad 0
kpo_target: .quad 0
kpo_calls: .quad 0
kpo_reads: .quad 0
kpo_signals: .quad 0
kpo_record: .zero 64
.text
FN kpo_read
    cmp qword ptr [rip + kpo_calls], 0
    je 1f
    cmp rdi, [rip + kpo_target]
    jne 1f
    inc qword ptr [rip + kpo_reads]
1:  SYS SYS_read
    ret
FN kpo_signal
    inc qword ptr [rip + kpo_signals]
.ifdef WINDOWS
    PROLOGUE 96
    API TerminateProcess
    EPILOGUE
.else
    SYS SYS_kill
    ret
.endif
FN ext_fd_close_checked
    cmp qword ptr [rip + kpo_owner], 0
    je kpo_real_close
    cmp rdi, [rip + kpo_target]
    jne kpo_real_close
    PROLOGUE 96
    inc qword ptr [rip + kpo_calls]
.ifdef WINDOWS
    call win_fd
    mov rcx, [rax + FD_handle]
    API CloseHandle
    test eax, eax
    jz .Ltkp_fail
.else
    call kpo_real_close
    test rax, rax
    jnz .Ltkp_fail
.endif
    mov rax, -13
    mov edx, 2
    EPILOGUE

.ifdef WINDOWS
FN kpo_pause
    PROLOGUE 96
    API Sleep
    EPILOGUE
.endif
