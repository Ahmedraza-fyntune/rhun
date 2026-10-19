.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.section .rodata
.p2align 3
fop_modes:
    .quad fop_unit_name,1,0
    .quad fop_hold_sh,2,0
    .quad fop_hold_ex,2,1
    .quad fop_probe_sh,3,0
    .quad fop_probe_ex,3,1
    .quad fop_publish,4,0
    .quad fop_before,5,0
    .quad fop_after,6,0
    .quad fop_null_source,7,0
    .quad fop_null_dest,8,0
    .quad fop_oom1,9,1
    .quad fop_oom2,9,2
    .quad fop_api_before,10,1
    .quad fop_api_after,10,2
    .quad fop_invalid_source,11,0
    .quad fop_invalid_dest,12,0
    .quad 0,0,0
fop_unit_name: .asciz "locks"
fop_hold_sh: .asciz "hold-sh"
fop_hold_ex: .asciz "hold-ex"
fop_probe_sh: .asciz "probe-sh"
fop_probe_ex: .asciz "probe-ex"
fop_publish: .asciz "publish"
fop_before: .asciz "before"
fop_after: .asciz "after"
fop_null_source: .asciz "null-source"
fop_null_dest: .asciz "null-dest"
fop_oom1: .asciz "oom1"
fop_oom2: .asciz "oom2"
fop_api_before: .asciz "api-before"
fop_api_after: .asciz "api-after"
fop_invalid_source: .asciz "invalid-source"
fop_invalid_dest: .asciz "invalid-dest"
fop_bad_utf8: .byte 0xc0,0xaf,0
fop_ready: .ascii "READY\n"
fop_released: .ascii "RELEASED\n"
fop_ok: .asciz "ok file locks\n"
.bss
.p2align 3
fop_stage: .quad 0
fop_path_calls: .quad 0
fop_path_fail: .quad 0
fop_move_fault: .quad 0
.text
fop_fail:
    mov edi, [rip + fop_stage]
    add edi, 100
    call sys_exit
fop_zero:
    test rax, rax
    jnz fop_fail
    ret
fop_busy:
    cmp rax, -11
    jne fop_fail
    ret
fop_open:
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js fop_fail
    ret
fop_gate:
    PROLOGUE 16
    mov edi, 1
    lea rsi, [rip + fop_ready]
    mov edx, 6
    call write_all
    call fop_zero
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne fop_fail
    EPILOGUE
.ifdef TEST_FILE_OPS_FAULT
FN fop_path
    inc qword ptr [rip + fop_path_calls]
    mov rax, [rip + fop_path_calls]
    cmp rax, [rip + fop_path_fail]
    jne 1f
    xor eax, eax
    mov rdx, -12
    ret
1:  jmp win_file_path_try
FN fop_move
    cmp qword ptr [rip + fop_move_fault], 1
    je 1f
    PROLOGUE 96
    API MoveFileExW
    test eax, eax
    jz 2f
    cmp qword ptr [rip + fop_move_fault], 2
    jne 2f
    mov ecx, 5
    API SetLastError
    xor eax, eax
2:  EPILOGUE
1:  sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
.endif

fop_unit:
    PROLOGUE 144
    mov rbx, rdi
    mov qword ptr [rip + fop_stage], 1
    call fop_open
    mov r12, rax
    mov rdi, rbx
    call fop_open
    mov r13, rax
    mov rdi, rbx
    call fop_open
    mov r14, rax
    mov edi, r12d
    mov rsi, -1
    call file_lock_try
    cmp rax, -22
    jne fop_fail
    mov edi, r12d
    mov rsi, 1<<32
    call file_lock_try
    cmp rax, -22
    jne fop_fail
    mov edi, -1
    xor esi, esi
    call file_lock_try
    cmp rax, -9
    jne fop_fail
    mov edi, -1
    call file_lock_release
    cmp rax, -9
    jne fop_fail
    mov qword ptr [rip + fop_stage], 2
    mov edi, r12d
    xor esi, esi
    call file_lock_try
    call fop_zero
    mov edi, r13d
    xor esi, esi
    call file_lock_try
    call fop_zero
    mov edi, r14d
    mov esi, 1
    call file_lock_try
    call fop_busy
    mov edi, r12d
    call file_lock_release
    call fop_zero
    mov edi, r14d
    mov esi, 1
    call file_lock_try
    call fop_busy
    mov edi, r13d
    call file_lock_release
    call fop_zero
    mov qword ptr [rip + fop_stage], 3
    mov edi, r14d
    mov esi, 1
    call file_lock_try
    call fop_zero
    mov edi, r12d
    xor esi, esi
    call file_lock_try
    call fop_busy
    mov edi, r14d
    call file_lock_release
    call fop_zero
    mov edi, r14d
    mov rsi, rsp
    SYS SYS_fstat
    call fop_zero
    mov edi, r12d
    xor esi, esi
    call file_lock_try
    call fop_zero
    mov edi, r12d
    call file_lock_release
    call fop_zero
    mov qword ptr [rip + fop_stage], 4
    mov edi, r14d
    mov esi, 1
    call file_lock_try
    call fop_zero
    mov edi, r14d
    SYS SYS_close
    call fop_zero
    mov edi, r13d
    mov esi, 1
    call file_lock_try
    call fop_zero
    mov edi, r13d
    call file_lock_release
    call fop_zero
    mov edi, r12d
    SYS SYS_close
    call fop_zero
    mov edi, r13d
    SYS SYS_close
    call fop_zero
    xor eax, eax
    EPILOGUE

FN main
    PROLOGUE 144
    cmp qword ptr [rip + g_argc], 3
    jb fop_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 16]
    mov r13, [rax + 8]
    lea rbx, [rip + fop_modes]
1:  mov rsi, [rbx]
    test rsi, rsi
    jz fop_fail
    mov rdi, r13
    call strcmp_eq
    test eax, eax
    jnz 2f
    add rbx, 24
    jmp 1b
2:  mov r15, [rip + g_mem_live]
    cmp qword ptr [rbx + 8], 1
    jne 3f
    mov rdi, r12
    call fop_unit
    cmp r15, [rip + g_mem_live]
    jne fop_fail
    lea rdi, [rip + fop_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
3:  cmp qword ptr [rbx + 8], 3
    ja .Lfop_publish
    mov rdi, r12
    call fop_open
    mov r14, rax
    mov edi, eax
    mov rsi, [rbx + 16]
    call file_lock_try
    mov r13, rax
    cmp qword ptr [rbx + 8], 3
    je 4f
    call fop_zero
    call fop_gate
    mov edi, r14d
    call file_lock_release
    call fop_zero
    # Keep the original descriptor open after explicit release until the parent
    # has probed again. This distinguishes unlock from eventual close cleanup.
    mov edi, 1
    lea rsi, [rip + fop_released]
    mov edx, 9
    call write_all
    call fop_zero
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne fop_fail
4:  mov edi, r14d
    SYS SYS_close
    call fop_zero
    cmp r15, [rip + g_mem_live]
    jne fop_fail
    mov rax, r13
    jmp .Lfop_status
.Lfop_publish:
    cmp qword ptr [rip + g_argc], 4
    jb fop_fail
    mov rax, [rip + g_argv]
    mov r13, [rax + 24]
    cmp qword ptr [rbx + 8], 9
    jne 5f
    mov rax, [rbx + 16]
    mov [rip + fop_path_fail], rax
5:  cmp qword ptr [rbx + 8], 10
    jne 6f
    mov rax, [rbx + 16]
    mov [rip + fop_move_fault], rax
6:  cmp qword ptr [rbx + 8], 5
    jne 7f
    call fop_gate
7:  mov rdi, r12
    mov rsi, r13
    cmp qword ptr [rbx + 8], 7
    jne 71f
    xor edi, edi
71: cmp qword ptr [rbx + 8], 8
    jne 72f
    xor esi, esi
72: cmp qword ptr [rbx + 8], 11
    jne 73f
    lea rdi, [rip + fop_bad_utf8]
73: cmp qword ptr [rbx + 8], 12
    jne 74f
    lea rsi, [rip + fop_bad_utf8]
74: call file_publish_new
    mov r14, rax
    cmp r15, [rip + g_mem_live]
    jne fop_fail
    cmp qword ptr [rbx + 8], 6
    jne 8f
    call fop_zero
    call fop_gate
8:  cmp qword ptr [rbx + 8], 9
    jne 9f
    cmp r14, -12
    jne fop_fail
    mov qword ptr [rip + fop_path_fail], 0
    mov rdi, r12
    mov rsi, r13
    call file_publish_new
    call fop_zero
    cmp r15, [rip + g_mem_live]
    jne fop_fail
9:  mov rax, r14
.Lfop_status:
    test rax, rax
    jns 10f
    neg rax
10: EPILOGUE
