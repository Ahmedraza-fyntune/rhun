.include "win.inc"
.section .rodata
wpt_ok: .asciz "ok fallible Windows path\n"
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 3
    jne wpt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov r12, [rax + 16]
    mov r13, [rip + g_mem_live]
    call win_file_path_try
    test rax, rax
    jz wpt_fail
    test rdx, rdx
    jnz wpt_fail
    mov rbx, rax
    mov rdi, rax
    call win_utf8
    test rax, rax
    jz wpt_fail
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz wpt_fail
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    call mem_free
    cmp r13, [rip + g_mem_live]
    jne wpt_fail
    lea rdi, [rip + wpt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
wpt_fail:
    mov edi, 1
    call sys_exit
