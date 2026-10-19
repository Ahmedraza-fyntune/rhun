.include "rhun.inc"
.include "app/themecapture.inc"
.bss
.p2align 3
tcbt_request: .zero TC_INPUT_CAP + 1
.text
tcbt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 64
    mov qword ptr [rip + g_theme_capture_limit], TC_HELPER_CAP
    xor r12d, r12d
1:  xor edi, edi
    lea rsi, [rip + tcbt_request]
    add rsi, r12
    mov edx, TC_INPUT_CAP + 1
    sub rdx, r12
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js tcbt_fail
    jz 2f
    add r12, rax
    cmp r12, TC_INPUT_CAP
    jbe 1b
    jmp tcbt_fail
2:  mov r15, [rip + g_mem_live]
    call time_ms
    lea rcx, [rax + 10000]
    mov [rsp + 16], rcx
    lea rdi, [rip + tcbt_request]
    mov rsi, r12
    mov rdx, rsp
    call tc_capture_build
    test rax, rax
    jnz tcbt_fail
    test rdx, rdx
    jnz tcbt_fail
    mov edi, 1
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call write_all
    test rax, rax
    jnz tcbt_fail
    mov rdi, rsp
    mov rsi, [rsp + 16]
    call tc_file_release
    test rax, rax
    jnz tcbt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcbt_fail
    cmp [rip + g_mem_live], r15
    jne tcbt_fail
    xor eax, eax
    EPILOGUE
