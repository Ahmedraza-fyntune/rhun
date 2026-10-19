# Private fault-only wrappers. Every delegated real handle still closes normally.
.bss
.p2align 3
est_renamed: .quad 0
est_close_failed: .quad 0
est_reopens: .quad 0
est_reads: .quad 0
est_scans: .quad 0
est_file_opens: .quad 0
est_after_precommit: .quad 0
est_destructor_stage: .quad 0
est_identities: .quad 0
.text
FN ext_store_raw_rename
.if EST_FAULT_MODE == 100
    mov rax, -5
    ret
.endif
.if EST_FAULT_MODE == 103
    # Create an invalid colliding completed name without replacing the pending file.
    PROLOGUE
    mov rsi, rdx
    mov edx, 1
    mov ecx, 7
    mov r8d, 0600
    call ext_root_open_at
    test rax, rax
    js 1f
    mov rdi, rax
    call ext_root_close
1:  mov rax, -17
    EPILOGUE
.endif
.if EST_FAULT_MODE == 104
    mov qword ptr [rip + est_renamed], 1
    mov rax, -5
    ret
.endif
    PROLOGUE
    call ext_store_test_real_rename
    test rax, rax
    jnz 1f
    mov qword ptr [rip + est_renamed], 1
.if EST_FAULT_MODE != 150
    mov rax, -5
.endif
1:  EPILOGUE

FN ext_root_read
.if EST_FAULT_MODE == 150
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
.endif
.if EST_FAULT_MODE == 133
    mov rax, -5
    ret
.endif
.if EST_FAULT_MODE == 134
    mov qword ptr [rip + est_renamed], 1
    mov rax, -13
    ret
.endif
.if EST_FAULT_MODE == 102
    cmp qword ptr [rip + est_renamed], 0
    je 1f
    mov rax, -13
    ret
1:
.endif
.if EST_FAULT_MODE == 114
    cmp qword ptr [rip + est_renamed], 0
    je 1f
    xor eax, eax
    ret
1:
.endif
    jmp ext_store_test_real_read

FN ext_root_open_at
.if EST_FAULT_MODE == 160
    cmp qword ptr [rip + est_destructor_stage], 0
    je 9f
    mov rax, -13
    mov rdx, -9
    ret
9:
.endif
.if EST_FAULT_MODE == 150
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
.endif
.if EST_FAULT_MODE >= 130
.if EST_FAULT_MODE <= 132
    cmp rdx, 1
    jne 8f
    inc qword ptr [rip + est_file_opens]
    mov rax, EST_FAULT_MODE - 129
    cmp [rip + est_file_opens], rax
    ja 8f
    mov rax, -2
    xor edx, edx
    ret
8:
.endif
.endif
.if EST_FAULT_MODE == 135
    cmp rdx, 1
    jne 8f
    mov rax, -2
    mov rdx, -5
    ret
8:
.endif
.if EST_FAULT_MODE == 104
    cmp qword ptr [rip + est_renamed], 0
    je 1f
    mov rax, -13
    xor edx, edx
    ret
1:
.endif
    jmp ext_store_test_real_open_at

.ifdef WINDOWS
FN win_ext_root_open_prepared_at
.if EST_FAULT_MODE == 104
    cmp qword ptr [rip + est_renamed], 0
    je 1f
    mov rax, -13
    xor edx, edx
    ret
1:
.endif
    jmp ext_store_test_real_prepared_at
.endif

FN ext_root_close
    PROLOGUE
    call ext_store_test_real_close
.if EST_FAULT_MODE == 105 || EST_FAULT_MODE == 134
    cmp qword ptr [rip + est_renamed], 0
    je 1f
    cmp qword ptr [rip + est_close_failed], 0
    jne 1f
    mov qword ptr [rip + est_close_failed], 1
    mov rax, -5
1:
.endif
    EPILOGUE

FN ext_root_reopen_dir
.if EST_FAULT_MODE >= 150
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
.endif
.if EST_FAULT_MODE == 111
    inc qword ptr [rip + est_reopens]
    cmp qword ptr [rip + est_reopens], 4
    jne 1f
    mov rax, -12
    xor edx, edx
    ret
1:
.endif
    jmp ext_store_test_real_reopen

FN ext_store_raw_write
.if EST_FAULT_MODE == 106
    xor eax, eax
    ret
.endif
    jmp ext_store_test_real_write
FN ext_store_raw_sync
.if EST_FAULT_MODE == 107
    mov rax, -5
    ret
.endif
    jmp ext_store_test_real_sync
FN ext_store_raw_unlink
.if EST_FAULT_MODE == 109
    mov rax, -5
    xor edx, edx
    ret
.endif
    jmp ext_store_test_real_unlink

FN est_fault_scan
    PROLOGUE
    inc qword ptr [rip + est_scans]
    mov r12, [rip + est_scans]
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
.if EST_FAULT_MODE >= 120
.if EST_FAULT_MODE <= 122
    cmp r12, EST_FAULT_MODE - 119
    jne 1f
    mov rax, -5
1:
.endif
.endif
    EPILOGUE

.if EST_FAULT_MODE >= 150
FN mem_alloc_try
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
    jmp ext_store_test_real_alloc_try
FN mem_alloc
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
    jmp ext_store_test_real_alloc
.ifdef WINDOWS
FN est_convert
    cmp qword ptr [rip + est_after_precommit], 0
    jne esww_fail
    jmp qword ptr [rip + __imp_MultiByteToWideChar]
.endif
.endif

.if EST_FAULT_MODE == 161
FN ext_root_identity
    inc qword ptr [rip + est_identities]
    cmp qword ptr [rip + est_identities], 4
    jb 1f
    mov rax, -5
    ret
1:  jmp ext_store_test_real_identity
.endif
.if EST_FAULT_MODE == 162
FN est_before_reopen
    PROLOGUE 16
    mov edi, 1
    lea rsi, [rip + est_reopen_ready]
    mov edx, 6
    call write_all
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne esww_fail
    EPILOGUE
.section .rodata
est_reopen_ready: .ascii "READY\n"
.endif
