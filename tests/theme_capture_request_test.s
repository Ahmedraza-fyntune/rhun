.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/themecapture.inc"
.section .rodata
tct_nonce: .quad 0x0807060504030201, 0x100f0e0d0c0b0a09
.text
tct_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 256
    cmp qword ptr [rip + g_argc], 4
    jne tct_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 8]
    mov r12, rax
    call parse_u64
    cmp rdx, r12
    jne tct_fail
    mov r14, rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 208], rax
    mov rdi, rsp
    xor esi, esi
    mov edx, 208
    call memset
    mov qword ptr [rsp + TCFG_job], 1
    mov qword ptr [rsp + TCFG_context], 2
    mov rax, [rip + tct_nonce]
    mov [rsp + TCFG_nonce], rax
    mov rax, [rip + tct_nonce + 8]
    mov [rsp + TCFG_nonce + 8], rax
    cmp r14, 6
    jne 1f
    mov rax, 0x7fffffffffffffff
    mov [rsp + TCFG_job], rax
1:  cmp r14, 7
    jne 2f
    mov rax, 0x8000000000000000
    mov [rsp + TCFG_job], rax
2:  cmp r14, 8
    jne 3f
    mov qword ptr [rsp + TCFG_job], 0
3:  cmp r14, 9
    jne 4f
    mov rax, 0x8000000000000000
    mov [rsp + TCFG_context], rax
4:  cmp r14, 10
    jne 5f
    mov qword ptr [rsp + TCFG_nonce], 0
    mov qword ptr [rsp + TCFG_nonce + 8], 0
5:  cmp r14, 1
    je 51f
    cmp r14, 14
    je 51f
    cmp r14, 15
    je 51f
    cmp r14, 16
    jne 6f
51: mov dword ptr [rsp + TCFG_scope], 1
6:  cmp r14, 2
    jne 7f
    mov dword ptr [rsp + TCFG_scope], 2
    mov dword ptr [rsp + TCFG_expected_scope], 1
7:  cmp r14, 11
    jne 8f
    mov dword ptr [rsp + TCFG_scope], 3
8:  cmp r14, 12
    je 81f
    cmp r14, 14
    jne 9f
81: mov dword ptr [rsp + TCFG_expected_scope], 1
9:  cmp r14, 15
    jne 10f
    mov dword ptr [rsp + TCFG_expected_scope], 2
10: cmp r14, 2
    je 101f
    cmp r14, 12
    je 101f
    cmp r14, 13
    je 101f
    cmp r14, 15
    jne 11f
101: lea rdi, [rsp + TCFG_expected]
    mov esi, 187
    mov edx, 32
    call memset
11: cmp r14, 21
    jne 12f
    mov qword ptr [rip + g_theme_capture_limit], 0
12: cmp r14, 22
    jne 13f
    mov qword ptr [rip + g_theme_capture_limit], 128
13: mov rsi, [rbx + 24]
    cmp word ptr [rsi], '-'
    jne 14f
    xor esi, esi
14: mov rdi, rsp
    call theme_capture_request_begin
    test rax, rax
    jnz 15f
    mov [rsp + 128], rdx
    xor r13d, r13d
    jmp .Ltct_output
15: mov r13, rax
    cmp r14, 1
    je .Ltct_seal
    cmp r14, 16
    je .Ltct_seal
    cmp r14, 18
    je .Ltct_seal
    xor r15d, r15d
.Ltct_add:
    mov rdi, r13
    mov rsi, r15
    mov rdx, [rbx + 16]
    call theme_capture_request_add
    mov [rsp + 136], rax
    test rax, rax
    jz 151f
    cmp qword ptr [r13 + TCQ_count], 0
    je .Ltct_output
    jmp .Ltct_seal
151: inc r15
    cmp r14, 3
    je 17f
    cmp r14, 4
    jne 18f
17: cmp r15, TC_SOURCE_MAX
    jb .Ltct_add
    cmp r14, 4
    jne .Ltct_seal
    jmp .Ltct_add
18: cmp r14, 5
    jne .Ltct_seal
    mov rdi, r13
    xor esi, esi
    mov rdx, [rbx + 16]
    call theme_capture_request_add
    mov [rsp + 136], rax
.Ltct_seal:
    mov rdi, r13
    call theme_capture_request_seal
    mov [rsp + 128], rax
    test rax, rax
    jnz .Ltct_output
    mov rax, [r13 + TCQ_length]
    mov [rsp + 144], rax
    cmp r14, 17
    jne .Ltct_output
    mov rdi, r13
    mov esi, 1
    mov rdx, [rbx + 16]
    call theme_capture_request_add
    mov [rsp + 136], rax
    mov rdi, r13
    call theme_capture_request_seal
    test rax, rax
    jnz tct_fail
.Ltct_output:
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 152], rax
    mov edi, 1
    lea rsi, [rsp + 128]
    mov edx, 32
    call write_all
    test rax, rax
    jnz tct_fail
    cmp qword ptr [rsp + 144], 0
    je 1f
    mov edi, 1
    mov rsi, [r13 + TCQ_wire]
    mov rdx, [rsp + 144]
    call write_all
    test rax, rax
    jnz tct_fail
1:  mov rdi, r13
    call theme_capture_request_free
    test rax, rax
    jnz tct_fail
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 160], rax
    test rax, rax
    jnz tct_fail
    mov rax, [rip + g_mem_live]
    sub rax, [rsp + 208]
    mov [rsp + 168], rax
    test rax, rax
    jnz tct_fail
    mov edi, 1
    lea rsi, [rsp + 160]
    mov edx, 16
    call write_all
    test rax, rax
    jnz tct_fail
    xor eax, eax
    EPILOGUE
