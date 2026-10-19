.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/themecapture.inc"
.text
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 2
    jne 9f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, TC_INPUT_CAP + 1
    call file_read_limited_try
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    call tc_request_validate
    mov [rsp], rax
    mov rdi, rbx
    call mem_free
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne 9f
    mov edi, 1
    mov rsi, rsp
    mov edx, 8
    call write_all
    test rax, rax
    jnz 9f
    xor eax, eax
    EPILOGUE
9:  mov edi, 73
    call sys_exit
