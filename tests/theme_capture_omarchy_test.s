.include "rhun.inc"
.include "app/themecapture.inc"
.bss
.p2align 3
tcot_input: .zero 65537
.section .rodata
tcot_dir: .ascii "/theme"
.text
tcot_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 80
    cmp qword ptr [rip + g_argc], 2
    jne tcot_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 8]
    call parse_u64
    cmp rdx, rsi
    jne tcot_fail
    mov r12, rax
    xor r13d, r13d
1:  xor edi, edi
    lea rsi, [rip + tcot_input]
    add rsi, r13
    mov edx, 65537
    sub rdx, r13
    SYS SYS_read
    test rax, rax
    js tcot_fail
    jz 2f
    add r13, rax
    cmp r13, 65537
    jb 1b
    jmp tcot_fail
2:  cmp r12, 3
    jae .Ltcot_proof
    lea rdi, [rip + tcot_input]
    mov rsi, r13
    test r12, r12
    jnz 3f
    call tc_omarchy_effective
    mov rdx, rax
    lea rbx, [rip + tcot_input]
    jmp 5f
3:  cmp r12, 1
    jne 4f
    call theme_capture_omarchy_alias
    mov rbx, rax
    jmp 5f
4:  call tc_omarchy_light
    mov [rsp], rax
    mov edi, 1
    mov rsi, rsp
    mov edx, 8
    call write_all
    xor eax, eax
    EPILOGUE
5:  test rdx, rdx
    js tcot_fail
    mov [rsp], rdx
    mov r14, rdx
    mov edi, 1
    mov rsi, rsp
    mov edx, 8
    call write_all
    mov edi, 1
    mov rsi, rbx
    mov rdx, r14
    call write_all
    xor eax, eax
    EPILOGUE
.Ltcot_proof:
    cmp r13, 144
    jne tcot_fail
    lea rdi, [rip + tcot_dir]
    mov esi, 6
    lea rdx, [r12 - 2]
    lea rcx, [rip + tcot_input]
    lea r8, [rsp + 8]
    call tc_omarchy_proof
    mov [rsp], rax
    mov edi, 1
    mov rsi, rsp
    mov edx, 40
    call write_all
    xor eax, eax
    EPILOGUE
