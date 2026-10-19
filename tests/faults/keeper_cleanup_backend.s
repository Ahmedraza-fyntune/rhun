# Windows backend memory ownership, including childless and actual-created helper paths.
.bss
kcb_owner: .quad 0
kcb_target: .quad 0
kcb_unmaps: .quad 0
kcb_now: .quad 0
kcb_base: .quad 0
kcb_timecalls: .quad 0
.text
FN kcb_capture
    mov [rip + kcb_owner], rdi
    ret
FN time_ms
.if KCB_MODE == 3
    inc qword ptr [rip + kcb_timecalls]
    cmp qword ptr [rip + kcb_timecalls], 1
    je 1f
    mov qword ptr [rip + kcb_now], 2000
1:
.endif
    mov rax, [rip + kcb_now]
    ret
FN mem_alloc_try
    PROLOGUE
    mov r12, rdi
    call kcb_real_alloc
    cmp qword ptr [rip + kcb_owner], 0
    je 1f
    cmp r12, 65536
    jne 1f
    mov [rip + kcb_target], rax
1:  EPILOGUE
FN kcb_munmap
    lea rcx, [rdi + 16]
    cmp rcx, [rip + kcb_target]
    jne 1f
    inc qword ptr [rip + kcb_unmaps]
    cmp qword ptr [rip + kcb_unmaps], 1
    jne 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
kcb_parent:
    test rax, rax
    jle .Ltkp_fail
    mov [rip + tkp_handle], rax
.if KCB_MODE == 0
    cmp rdx, -5
.else
    cmp rdx, -13
.endif
    jne .Ltkp_fail
    cmp rcx, -5
    jne .Ltkp_fail
    mov r13, [rip + kcb_owner]
    cmp qword ptr [rip + kcb_unmaps], 1
    jne .Ltkp_fail
    mov rax, [rip + kcb_target]
    test rax, rax
    jz .Ltkp_fail
    cmp [r13 + KX_native + KB_mem], rax
    jne .Ltkp_fail
    cmp qword ptr [rax - 16], 64
    jb .Ltkp_fail
    cmp qword ptr [r13 + KX_sent], 0
    jne .Ltkp_fail
.if KCB_MODE == 0
    cmp qword ptr [r13 + KX_native_state], KN_OWNED
    jne .Ltkp_fail
.else
    cmp qword ptr [r13 + KX_native_state], KN_NONE
    jne .Ltkp_fail
    cmp qword ptr [r13 + KX_helper], 0
    jne .Ltkp_fail
    cmp qword ptr [r13 + KX_frame], 0
    jne .Ltkp_fail
.endif

.if KCB_MODE == 3
    # A scheduling pause already made the old deadline due inside prepare.
    # Only an explicit operation-level skip can retain the first failed mapping.
    cmp qword ptr [rip + kcb_timecalls], 2
    jb .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -5
    jne .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
    cmp qword ptr [rip + kcb_unmaps], 2
    jne .Ltkp_fail
    mov rax, [rip + kcb_base]
    cmp [rip + g_mem_live], rax
    jne .Ltkp_fail
    lea rdi, [rip + tkp_ok]
    call log_cstr
    xor eax, eax
    jmp .Ltkp_return
.endif
    mov r14d, 2000
1:  mov rdi, [rip + tkp_handle]
    call keeper_poll
    test rax, rax
    js .Ltkp_fail
    test eax, KP_STARTED
    jnz .Ltkp_fail
    cmp qword ptr [r13 + KX_lifetime_ready], 0
    jne 2f
    mov ecx, 5
    call kcb_pause
    dec r14
    jnz 1b
    jmp .Ltkp_fail
2:  mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -5
    jne .Ltkp_fail
    test rdx, rdx
    jnz .Ltkp_fail
    cmp qword ptr [rip + kcb_unmaps], 1
    jne .Ltkp_fail
    mov rax, [rip + kcb_base]
    inc rax
    cmp [rip + g_mem_live], rax
    jne .Ltkp_fail
    mov qword ptr [rip + kcb_now], 1016
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -5
    jne .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
    cmp qword ptr [rip + kcb_unmaps], 2
    jne .Ltkp_fail
    mov rax, [rip + kcb_base]
    cmp [rip + g_mem_live], rax
    jne .Ltkp_fail
    lea rdi, [rip + tkp_ok]
    call log_cstr
    xor eax, eax
    jmp .Ltkp_return

FN kcb_pause
    PROLOGUE 96
    API Sleep
    EPILOGUE
