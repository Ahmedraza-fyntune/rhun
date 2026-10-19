.include "rhun.inc"
.include "app/themecapture.inc"
.text
tcoit_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 336
    cmp qword ptr [rip + g_argc], 3
    jne tcoit_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 16]
    call parse_u64
    cmp rdx, rsi
    jne tcoit_fail
    mov r12, rax
    mov r15, [rip + g_mem_live]
    mov rdi, rsp
    mov esi, 90
    mov edx, TOB_SIZE
    call memset
    call time_ms
    lea rcx, [rax + 10000]
    mov [rsp + 312], rcx
    mov rdi, [rbx + 8]
    mov rsi, r12
    mov rdx, rsp
    call tc_omarchy_capture
    mov [rsp + 240], rax
    mov [rsp + 248], rdx
    or rax, rdx
    jz 2f
    xor ecx, ecx
1:  cmp byte ptr [rsp + rcx], 90
    jne tcoit_fail
    inc ecx
    cmp ecx, TOB_SIZE
    jb 1b
    mov rdi, rsp
    xor esi, esi
    mov edx, TOB_SIZE
    call memset
2:  mov edi, 1
    lea rsi, [rsp + 240]
    mov edx, 16
    call write_all
    mov edi, 1
    mov rsi, rsp
    mov edx, TOB_SIZE
    call write_all
    mov edi, 1
    mov rsi, [rsp + TOB_name]
    mov rdx, [rsp + TOB_raw_length]
    call write_all
    lea rdi, [rsp + TOB_name]
    mov rsi, [rsp + 312]
    call tc_file_release
    test rax, rax
    jnz tcoit_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcoit_fail
    cmp r15, [rip + g_mem_live]
    jne tcoit_fail
    xor eax, eax
    EPILOGUE
