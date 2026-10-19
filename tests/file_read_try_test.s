# Counted snapshots and cleanup, driven by file-read-try.py. Fault wrappers are
# linked only into a private executable; production objects are never replaced.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.section .rodata
.p2align 3
# name, cap, expected count/errno, allocation to fail, IO/API fault
ftr_cases:
    .quad ftr_empty,0,0,0,0
    .quad ftr_exact,3,3,0,0
    .quad ftr_larger,4,3,0,0
    .quad ftr_over,2,-27,0,0
    .quad ftr_zero,0,-27,0,0
    .quad ftr_negative,-1,-22,0,0
    .quad ftr_max,0x7fffffffffffffff,-22,0,0
    .quad ftr_null,3,-22,0,0
    .quad ftr_missing,3,-2,0,0
    .quad ftr_directory,3,-21,0,0
    .quad ftr_fifo,3,-22,0,0
    .quad ftr_link,3,-40,0,0
    .quad ftr_invalid_utf8,3,-22,0,0
    .quad ftr_long_input,3,-36,0,0
    .quad ftr_oom1,3,-12,1,0
    .quad ftr_oom2,3,-12,2,0
    .quad ftr_oom3,3,-12,3,0
    .quad ftr_stat_error,3,-5,0,1
    .quad ftr_read_error,3,-5,0,2
    .quad ftr_interrupt,3,3,0,3
    .quad ftr_short,3,1,0,4
    .quad ftr_eof,3,0,0,5
    .quad ftr_snapshot,3,1,0,6
    .quad ftr_partial_error,3,-5,0,7
    .quad ftr_type_error,3,-5,0,8
    .quad ftr_info_error,3,-5,0,9
    .quad ftr_wrong_type,3,-22,0,10
    .quad ftr_reparse,3,-40,0,11
    .quad ftr_open_error,3,-13,0,12
    .quad ftr_full,3,-24,0,13
    .quad 0,0,0,0,0
ftr_empty: .asciz "empty"
ftr_exact: .asciz "exact"
ftr_larger: .asciz "larger"
ftr_over: .asciz "over"
ftr_zero: .asciz "zero"
ftr_negative: .asciz "negative"
ftr_max: .asciz "max"
ftr_null: .asciz "null"
ftr_missing: .asciz "missing"
ftr_directory: .asciz "directory"
ftr_fifo: .asciz "fifo"
ftr_link: .asciz "link"
ftr_invalid_utf8: .asciz "invalid-utf8"
ftr_long_input: .asciz "long-input"
ftr_oom1: .asciz "oom1"
ftr_oom2: .asciz "oom2"
ftr_oom3: .asciz "oom3"
ftr_stat_error: .asciz "stat-error"
ftr_read_error: .asciz "read-error"
ftr_interrupt: .asciz "interrupt"
ftr_short: .asciz "short"
ftr_eof: .asciz "eof"
ftr_snapshot: .asciz "snapshot"
ftr_partial_error: .asciz "partial-error"
ftr_type_error: .asciz "type-error"
ftr_info_error: .asciz "info-error"
ftr_wrong_type: .asciz "wrong-type"
ftr_reparse: .asciz "reparse"
ftr_open_error: .asciz "open-error"
ftr_full: .asciz "full"
ftr_ok: .asciz "ok fallible file read\n"
ftr_bad_utf8: .byte 0xc0,0xaf,0
.bss
.p2align 3
ftr_live: .quad 0
ftr_stage: .quad 0
ftr_calls: .quad 0
ftr_fail_at: .quad 0
ftr_io: .quad 0
ftr_reads: .quad 0
ftr_bad_path: .zero 4097
.ifdef WINDOWS
ftr_handles: .quad 0
ftr_count: .quad 0
ftr_last_handle: .quad 0
ftr_saved_fds: .zero FD_SIZE*FD_MAX
.endif
.text
ftr_fail:
    mov rdi, [rip + ftr_stage]
    call sys_exit
.ifdef TEST_FILE_TRY_FAULT
FN ftr_alloc
    inc qword ptr [rip + ftr_calls]
    mov rax, [rip + ftr_calls]
    cmp rax, [rip + ftr_fail_at]
    je 1f
    jmp mem_alloc_try
1:  xor eax, eax
    ret
FN ftr_stat
    cmp qword ptr [rip + ftr_io], 1
    je 9f
    SYS SYS_fstat
    test rax, rax
    js 8f
    cmp qword ptr [rip + ftr_io], 6
    jne 8f
    mov qword ptr [rsi + 48], 1
8:  ret
9:  mov rax, -5
    ret
FN ftr_read
    inc qword ptr [rip + ftr_reads]
    cmp qword ptr [rip + ftr_io], 2
    je 9f
    cmp qword ptr [rip + ftr_io], 3
    jne 1f
    cmp qword ptr [rip + ftr_reads], 1
    jne 8f
    mov rax, -4
    ret
1:  cmp qword ptr [rip + ftr_io], 5
    je 7f
    cmp qword ptr [rip + ftr_io], 4
    je 2f
    cmp qword ptr [rip + ftr_io], 7
    jne 8f
    cmp qword ptr [rip + ftr_reads], 1
    jne 9f
2:  cmp qword ptr [rip + ftr_reads], 1
    jne 7f
    mov edx, 1
8:  SYS SYS_read
    ret
7:  xor eax, eax
    ret
9:  mov rax, -5
    ret
.ifdef WINDOWS
# Private native-ABI stubs, called at the API sites in pathtry.s.
FN ftr_file_type
    cmp qword ptr [rip + ftr_io], 8
    je ftr_api_error
    cmp qword ptr [rip + ftr_io], 10
    jne 1f
    mov eax, 2
    ret
1:  jmp qword ptr [rip + __imp_GetFileType]
FN ftr_file_info
    cmp qword ptr [rip + ftr_io], 9
    je ftr_api_error
    cmp qword ptr [rip + ftr_io], 11
    jne 1f
    mov dword ptr [rdx], 0x400
    mov eax, 1
    ret
1:  jmp qword ptr [rip + __imp_GetFileInformationByHandle]
FN ftr_create_file
    cmp qword ptr [rip + ftr_io], 12
    jne 1f
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    mov rax, -1
    ret
1:  PROLOGUE 96
    mov rax, [rbp + 48]
    mov [rsp + 32], rax
    mov rax, [rbp + 56]
    mov [rsp + 40], rax
    mov rax, [rbp + 64]
    mov [rsp + 48], rax
    API CreateFileW
    cmp rax, -1
    je 2f
    mov rbx, rax
    mov [rip + ftr_last_handle], rax
    # Calibrate the native validity oracle on the actual live handle. Wine 10
    # stubs process handle counts, so counts alone cannot prove cleanup there.
    mov rcx, rax
    lea rdx, [rip + ftr_count]
    API GetHandleInformation
    test eax, eax
    jz ftr_fail
    mov rax, rbx
2:  EPILOGUE
ftr_api_error:
    sub rsp, 40
    mov ecx, 1117
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif
.endif
.ifdef WINDOWS
ftr_handle_closed:
    PROLOGUE 96
    mov rcx, [rip + ftr_last_handle]
    test rcx, rcx
    jz 1f
    lea rdx, [rip + ftr_count]
    API GetHandleInformation
    test eax, eax
    jnz ftr_fail
    API GetLastError
    cmp eax, 6
    jne ftr_fail
1:  EPILOGUE
ftr_handle_count:
    PROLOGUE 96
    mov rcx, -1
    lea rdx, [rip + ftr_count]
    API GetProcessHandleCount
    test eax, eax
    jz ftr_fail
    mov eax, [rip + ftr_count]
    EPILOGUE
.endif
FN main
    PROLOGUE
    mov qword ptr [rip + ftr_stage], 1
    cmp qword ptr [rip + g_argc], 3
    jne ftr_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov r13, [rax + 16]
    lea rbx, [rip + ftr_cases]
1:  mov rsi, [rbx]
    test rsi, rsi
    jz ftr_fail
    mov rdi, r13
    call strcmp_eq
    test eax, eax
    jnz 2f
    add rbx, 40
    jmp 1b
2:  mov rax, [rip + g_mem_live]
    mov [rip + ftr_live], rax
    lea rax, [rip + ftr_null]
    cmp [rbx], rax
    jne 21f
    xor r12d, r12d
21: lea rax, [rip + ftr_invalid_utf8]
    cmp [rbx], rax
    jne 22f
    lea r12, [rip + ftr_bad_utf8]
22: lea rax, [rip + ftr_long_input]
    cmp [rbx], rax
    jne 23f
    lea rdi, [rip + ftr_bad_path]
    mov esi, 'a'
    mov edx, 4096
    call memset
    lea r12, [rip + ftr_bad_path]
23:
.ifdef WINDOWS
    # Warm lazy OS state before capturing the handle baseline.
    mov rdi, r12
    mov rsi, [rbx + 8]
    call file_read_limited_try
    mov rdi, rax
    call mem_free
    call ftr_handle_count
    call ftr_handle_count
    mov [rip + ftr_handles], rax
    mov r14d, 2048
.else
    mov r14d, 64
.endif
3:  mov qword ptr [rip + ftr_stage], 2
    mov qword ptr [rip + ftr_calls], 0
    mov qword ptr [rip + ftr_reads], 0
.ifdef WINDOWS
    mov qword ptr [rip + ftr_last_handle], 0
.endif
    mov rax, [rbx + 24]
    mov [rip + ftr_fail_at], rax
    mov rax, [rbx + 32]
    mov [rip + ftr_io], rax
.ifdef WINDOWS
    cmp rax, 13
    jne 31f
    lea rdi, [rip + ftr_saved_fds]
    lea rsi, [rip + win_fds]
    mov edx, FD_SIZE*FD_MAX
    call memcpy
    lea rax, [rip + win_fds + 3*FD_SIZE]
    mov ecx, FD_MAX-3
30: cmp dword ptr [rax + FD_kind], 0
    jne 301f
    mov dword ptr [rax + FD_kind], FD_FILE
301:add rax, FD_SIZE
    dec ecx
    jnz 30b
31:
.endif
    mov rdi, r12
    mov rsi, [rbx + 8]
    call file_read_limited_try
    mov r15, rax
    mov r13, rdx
.ifdef WINDOWS
    cmp qword ptr [rip + ftr_io], 13
    jne 32f
    # Restore even on failure before logging or calling descriptor APIs.
    lea rdi, [rip + win_fds]
    lea rsi, [rip + ftr_saved_fds]
    mov edx, FD_SIZE*FD_MAX
    call memcpy
32:
.endif
    mov rcx, [rbx + 16]
    cmp r13, rcx
    jne ftr_fail
    test rcx, rcx
    js 5f
    test r15, r15
    jz ftr_fail
    cmp byte ptr [r15 + r13], 0
    jne ftr_fail
    test r13, r13
    jz 4f
    cmp byte ptr [r15], 'a'
    jne ftr_fail
    cmp r13, 1
    je 4f
    cmp byte ptr [r15 + 1], 0
    jne ftr_fail
    cmp byte ptr [r15 + 2], 'z'
    jne ftr_fail
4:  mov rdi, r15
    call mem_free
    jmp 6f
5:  test r15, r15
    jnz ftr_fail
6:  mov qword ptr [rip + ftr_stage], 3
    mov rax, [rip + ftr_live]
    cmp rax, [rip + g_mem_live]
    jne ftr_fail
.ifdef TEST_FILE_TRY_FAULT
    # Reject oversize before content allocation; invalid arguments before open.
    mov rax, [rbx + 16]
    cmp rax, -22
    jne 61f
    test r12, r12
    jz 60f
    cmp qword ptr [rbx + 8], 3
    je 61f
60: cmp qword ptr [rip + ftr_calls], 0
    jne ftr_fail
61: cmp rax, -27
    jne 62f
.ifdef WINDOWS
    cmp qword ptr [rip + ftr_calls], 1
.else
    cmp qword ptr [rip + ftr_calls], 0
.endif
    jne ftr_fail
62:
.endif
.ifdef WINDOWS
.ifdef TEST_FILE_TRY_FAULT
    call ftr_handle_closed
.endif
    call ftr_handle_count
    cmp rax, [rip + ftr_handles]
    jne ftr_fail
.endif
    dec r14d
    jnz 3b
.ifdef TEST_FILE_TRY_FAULT
    mov rax, [rbx + 24]
    or rax, [rbx + 32]
    jz 7f
    # Retry in this same process after every injected failure group.
    mov qword ptr [rip + ftr_stage], 4
    mov qword ptr [rip + ftr_fail_at], 0
    mov qword ptr [rip + ftr_io], 0
    mov rdi, r12
    mov esi, 3
    call file_read_limited_try
    test rax, rax
    jz ftr_fail
    cmp rdx, 3
    jne ftr_fail
    cmp byte ptr [rax], 'a'
    jne ftr_fail
    cmp byte ptr [rax + 1], 0
    jne ftr_fail
    cmp byte ptr [rax + 2], 'z'
    jne ftr_fail
    cmp byte ptr [rax + 3], 0
    jne ftr_fail
    mov rdi, rax
    call mem_free
    mov rax, [rip + ftr_live]
    cmp rax, [rip + g_mem_live]
    jne ftr_fail
.ifdef WINDOWS
    call ftr_handle_closed
    call ftr_handle_count
    cmp rax, [rip + ftr_handles]
    jne ftr_fail
.endif
7:
.endif
    lea rdi, [rip + ftr_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
