.include "rhun.inc"
.include "app/extvalidate.inc"
.text
FN main
    PROLOGUE 32
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 3
    jne 2f
    mov rdi, [rbx + 8]
    lea rsi, [rip + evt_tree]
    call strcmp_eq
    test eax, eax
    jz 2f
    mov rdi, [rbx + 16]
    call ext_root_open
    test rax, rax
    js 1f
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_validate_tree
    mov r13, rax
    mov rdi, r12
    call ext_root_close
    test r13, r13
    jnz 11f
    mov r13, rax
11: mov rax, r13
1:  mov rdi, rax
    mov rsi, rsp
    call ext_validate_print
    EPILOGUE
2:  mov rdi, [rip + g_argc]
    mov rsi, rbx
    call ext_validate_main
    EPILOGUE
.section .rodata
evt_tree: .asciz "--tree"
