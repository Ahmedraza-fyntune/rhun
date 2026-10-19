.include "rhun.inc"
.include "app/themecapture.inc"
.text
tcst_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 2
    je 10f
    cmp qword ptr [rip + g_argc], 3
    jne tcst_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    SYS SYS_chdir
    test rax, rax
    js tcst_fail
10:
    mov r15, [rip + g_mem_live]
    mov edi, 1
    call theme_capture_path_snapshot
    test rax, rax
    jnz tcst_fail
    cmp rdx, -16
    jne tcst_fail
    call theme_capture_startup_seal
    cmp rax, -16
    jne tcst_fail
    call theme_capture_startup_begin
    test rax, rax
    jnz tcst_fail
    call theme_capture_startup_begin
    cmp rax, -16
    jne tcst_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call theme_capture_path_snapshot
    mov r12, rax
    mov [rsp], rdx
    mov qword ptr [rsp + 8], 0
    test r12, r12
    jz 1f
    mov rdi, r12
    call tc_path_len
    test rax, rax
    js tcst_fail
    mov [rsp + 8], rax
1:  mov edi, 1
    mov rsi, rsp
    mov edx, 16
    call write_all
    mov edi, 1
    mov rsi, r12
    mov rdx, [rsp + 8]
    call write_all
    call theme_capture_startup_seal
    test rax, rax
    jnz tcst_fail
    # Poison raw pointer proves sealed entry refuses before any lazy qualification or scan.
    mov edi, 1
    call theme_capture_path_snapshot
    test rax, rax
    jnz tcst_fail
    cmp rdx, -16
    jne tcst_fail
    call theme_capture_startup_begin
    cmp rax, -16
    jne tcst_fail
    call theme_capture_startup_seal
    cmp rax, -16
    jne tcst_fail
    mov rdi, r12
    call mem_free
    cmp r15, [rip + g_mem_live]
    jne tcst_fail
    xor eax, eax
    EPILOGUE
