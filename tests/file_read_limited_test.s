# Counted bounded reads and the legacy entry points, driven by file-read-limited.py.
.include "rhun.inc"
.bss
.p2align 3
frt_live: .quad 0
.ifdef TEST_FILE_READ_LIMITED_ALLOC
frt_allocs: .quad 0
.endif
.text
.ifdef TEST_FILE_READ_LIMITED_ALLOC
FN mem_alloc
    inc qword ptr [rip + frt_allocs]
    jmp frt_real_mem_alloc
.endif
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 3
    jne frt_fail
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov r13, [rax + 16]
    lea rbx, [rip + frt_cases]
1:  mov rsi, [rbx]
    test rsi, rsi
    jz frt_fail
    mov rdi, r13
    call strcmp_eq
    test eax, eax
    jnz 2f
    add rbx, 32
    jmp 1b
2:  mov rax, [rip + g_mem_live]
    mov [rip + frt_live], rax
    mov r14d, 64
3:  mov rdi, r12
    mov rsi, [rbx + 8]
    call qword ptr [rbx + 24]
    mov r15, rax
    mov rcx, [rbx + 16]
    test rcx, rcx
    js 5f
    test rax, rax
    jz frt_fail
    cmp rdx, rcx
    jne frt_free_fail
    cmp byte ptr [rax + rdx], 0
    jne frt_free_fail
    test rdx, rdx
    jz 4f
    cmp byte ptr [rax], 'a'
    jne frt_free_fail
    cmp byte ptr [rax + 1], 0
    jne frt_free_fail
    cmp byte ptr [rax + 2], 'z'
    jne frt_free_fail
4:  mov rdi, r15
    call mem_capacity
    cmp qword ptr [rbx + 8], 32
    jne 41f
    cmp rax, 36
    jb frt_free_fail
41: mov rdi, r15
    call mem_free
    jmp 6f
5:  test rax, rax
    jnz frt_free_fail
    cmp rdx, rcx
    jne frt_fail
.ifdef TEST_FILE_READ_LIMITED_ALLOC
    cmp qword ptr [rip + frt_allocs], 0
    jne frt_fail
.endif
6:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + frt_live]
    jne frt_fail
    dec r14d
    jnz 3b
    lea rdi, [rip + frt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
frt_free_fail:
    mov rdi, r15
    call mem_free
frt_fail:
    mov eax, 1
    EPILOGUE
.section .rodata
.p2align 3
# mode, limit/extra, expected length or negative errno, reader
frt_cases:
    .quad frt_empty, 0, 0, file_read_limited
    .quad frt_exact, 3, 3, file_read_limited
    .quad frt_larger, 4, 3, file_read_limited
    .quad frt_over, 2, -27, file_read_limited
    .quad frt_zero, 0, -27, file_read_limited
    .quad frt_negative, -1, -22, file_read_limited
    .quad frt_max, 0x7fffffffffffffff, -22, file_read_limited
    .quad frt_missing, 3, -2, file_read_limited
    .quad frt_directory, 3, -21, file_read_limited
    .quad frt_fifo, 3, -22, file_read_limited
    .quad frt_legacy, 0, 3, file_read_all
    .quad frt_extra, 32, 3, file_read_all_extra
    .quad 0, 0, 0, 0
frt_empty: .asciz "empty"
frt_exact: .asciz "exact"
frt_larger: .asciz "larger"
frt_over: .asciz "over"
frt_zero: .asciz "zero"
frt_negative: .asciz "negative"
frt_max: .asciz "max"
frt_missing: .asciz "missing"
frt_directory: .asciz "directory"
frt_fifo: .asciz "fifo"
frt_legacy: .asciz "legacy"
frt_extra: .asciz "extra"
frt_ok: .asciz "ok bounded file read\n"
