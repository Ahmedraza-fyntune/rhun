.include "rhun.inc"
.include "app/themecapturecandidate.inc"
.bss
.p2align 3
tclt_rows: .zero 65536 * 16
.text
tclt_fail:
    mov edi, 73
    call sys_exit
tclt_number:
    PROLOGUE
    cmp byte ptr [rdi], 45
    jne 90f
    cmp byte ptr [rdi + 1], 49
    jne tclt_fail
    cmp byte ptr [rdi + 2], 0
    jne tclt_fail
    mov rax, -1
    EPILOGUE
90: mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne tclt_fail
    EPILOGUE
FN main
    PROLOGUE 512
    cmp qword ptr [rip + g_argc], 8
    jne tclt_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    call tclt_number
    mov r12, rax
    mov rdi, [rbx + 16]
    call tclt_number
    mov r13, rax
    mov rdi, rsp
    xor esi, esi
    mov edx, 512
    call memset
    mov [rsp + 304], r12
    mov [rsp + 312], r13
    mov rdi, [rbx + 56]
    call tclt_number
    mov [rsp + 16], rax
    lea rax, [rip + tclt_rows]
    mov [rsp], rax
    mov qword ptr [rsp + 8], 3
    mov qword ptr [rsp + 24], 1
    xor r14d, r14d
1:  mov rdi, [rbx + 32 + r14*8]
    call strlen
    mov rdx, [rbx + 32 + r14*8]
    mov rcx, r14
    shl rcx, 4
    lea rsi, [rip + tclt_rows]
    mov [rsi + rcx], rdx
    mov [rsi + rcx + 8], rax
    inc r14
    cmp r14, 3
    jb 1b
    cmp r12, 3
    jne 3f
    lea rdi, [rip + tclt_rows]
    mov rax, [rdi]
    mov rdx, [rdi + 8]
    mov rsi, [rdi + 32]
    mov rcx, [rdi + 40]
    xor r14d, r14d
2:  mov r8, r14
    shl r8, 4
    mov [rdi + r8], rax
    mov [rdi + r8 + 8], rdx
    inc r14
    cmp r14, 65536
    jb 2b
    mov [rdi + 65535*16], rsi
    mov [rdi + 65535*16 + 8], rcx
    mov qword ptr [rsp + 8], 65536
3:  cmp r12, 4
    jne 4f
    mov qword ptr [rsp + 8], 65537
4:  cmp r12, 9
    jne 91f
    mov qword ptr [rsp], -8
91: cmp r12, 10
    jne 92f
    mov qword ptr [rsp + 24], 0
92: cmp r12, 1
    je .Ltclt_fallback
    cmp r12, 2
    je .Ltclt_fallback
    mov rdi, [rbx + 24]
    call strlen
    mov rcx, rax
    mov rdx, [rbx + 24]
    mov rsi, rsp
    lea rdi, [rsp + 32]
    call theme_capture_candidate_begin
    jmp .Ltclt_begun
.Ltclt_fallback:
    lea rdi, [rsp + 32]
    mov rsi, rsp
    lea rdx, [r12 - 1]
    call theme_capture_fallback_begin
.Ltclt_begun:
    mov [rsp + 224], rax
    test rax, rax
    js .Ltclt_emit
    cmp r12, 8
    jne .Ltclt_loop
    lea rdi, [rsp + 32]
    mov esi, 1
    xor edx, edx
    call theme_capture_candidate_step
    cmp rax, -22
    jne tclt_fail
    or rdx, rcx
    jnz tclt_fail
.Ltclt_loop:
    lea rdi, [rsp + 32]
    mov esi, 1
    mov rdx, r13
    cmp qword ptr [rsp + 304], 6
    je .Ltclt_initial_one
    cmp qword ptr [rsp + 304], 7
    jne .Ltclt_call
.Ltclt_initial_one:
    cmp qword ptr [rsp + 272], 0
    jne .Ltclt_poison
    mov edx, 1
    jmp .Ltclt_call
.Ltclt_poison:
    mov qword ptr [rsp + 32 + TCL_query], 1
    mov qword ptr [rsp + 32 + TCL_current], 1
    cmp qword ptr [rsp + 304], 6
    jne 5f
    mov esi, 2
    jmp .Ltclt_call
5:  call theme_capture_candidate_cancel
    lea rdi, [rsp + 32]
    mov esi, 1
    mov rdx, r13
.Ltclt_call:
    call theme_capture_candidate_step
    mov [rsp + 232], rax
    cmp rdx, r13
    ja tclt_fail
    cmp rcx, 16
    ja tclt_fail
    add [rsp + 256], rdx
    add [rsp + 264], rcx
    inc qword ptr [rsp + 272]
    cmp [rsp + 280], rdx
    jae 6f
    mov [rsp + 280], rdx
6:  cmp [rsp + 288], rcx
    jae 7f
    mov [rsp + 288], rcx
7:  cmp qword ptr [rsp + 272], 1000000
    ja tclt_fail
    cmp qword ptr [rsp + 232], 1
    je .Ltclt_loop
    lea rdi, [rsp + 32]
    lea rsi, [rsp + 192]
    call theme_capture_candidate_status
    test rax, rax
    jnz tclt_fail
    cmp qword ptr [rsp + 192], 1
    jne tclt_fail
    mov rax, [rsp + 200]
    mov [rsp + 240], rax
    mov rax, [rsp + 208]
    mov [rsp + 248], rax
    lea rdi, [rsp + 32]
    mov esi, 2
    mov rdx, r13
    call theme_capture_candidate_step
    cmp rax, [rsp + 232]
    jne tclt_fail
    or rdx, rcx
    jnz tclt_fail
    lea rdi, [rsp + 32]
    lea rsi, [rsp + 192]
    call theme_capture_candidate_status
    test rax, rax
    jnz tclt_fail
    mov rax, [rsp + 200]
    cmp rax, [rsp + 240]
    jne tclt_fail
.Ltclt_emit:
    mov edi, 1
    lea rsi, [rsp + 224]
    mov edx, 80
    call write_all
    test rax, rax
    jnz tclt_fail
    xor eax, eax
    EPILOGUE
