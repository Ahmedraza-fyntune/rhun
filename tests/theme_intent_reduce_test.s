.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintent.inc"
.bss
.p2align 3
tirt_input: .zero 65536
.text
tirt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 512
    mov r15, [rip + g_mem_live]
    xor r13d, r13d
1:  xor edi, edi
    lea rsi, [rip + tirt_input]
    add rsi, r13
    mov edx, 65536
    sub rdx, r13
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js tirt_fail
    jz 2f
    add r13, rax
    cmp r13, 65536
    jb 1b
    jmp tirt_fail
2:  cmp r13, 144
    jb tirt_fail
    mov rdi, rsp
    xor esi, esi
    mov edx, 512
    call memset
    lea rbx, [rip + tirt_input]
    mov rax, [rbx]
    mov [rsp + TIR_keys], rax
    mov rax, [rbx + 8]
    mov [rsp + TIR_system], rax
    mov eax, [rbx + 16]
    mov [rsp + TIR_palette_dark], eax
    mov qword ptr [rsp + TIR_context], 1
    mov qword ptr [rsp + TIR_config], 2
    mov qword ptr [rsp + TIR_catalog], 3
    mov qword ptr [rsp + TIR_pending_dark], 1
    mov [rsp + 496], r13
    mov r14d, 144
    xor r12d, r12d
3:  cmp r12, 6
    jae 6f
    movsxd rcx, dword ptr [rbx + 24 + r12*4]
    cmp rcx, -1
    je 5f
    cmp rcx, 4096
    ja tirt_fail
    lea rax, [r14 + rcx + 1]
    cmp rax, [rsp + 496]
    ja tirt_fail
    cmp byte ptr [rbx + rax - 1], 0
    jne tirt_fail
    lea rdx, [rbx + r14]
    cmp r12, 5
    jne 4f
    mov [rsp + TIR_current], rdx
    jmp 8f
4:  mov [rsp + r12*8], rdx
8:  mov r14, rax
5:  inc r12
    jmp 3b
6:  mov rdi, rsp
    call theme_intent_capture
    test rax, rax
    jz tirt_fail
    test rdx, rdx
    jnz tirt_fail
    test rcx, rcx
    jnz tirt_fail
    mov r12, rax
    lea rdi, [rsp + 128]
    lea rsi, [rbx + 64]
    mov edx, 80
    call memcpy
    lea rax, [rbx + r14]
    mov [rsp + 128 + 16], rax
    mov rax, [rsp + 128 + 24]
    add rax, r14
    cmp rax, [rsp + 496]
    jne tirt_fail
    mov rdi, r12
    lea rsi, [rsp + 128]
    call theme_intent_reduce
    mov r14, rax
    mov [rsp + 352], rdx
    mov [rsp + 360], rcx
    mov edi, 1
    lea rsi, [rsp + 352]
    mov edx, 16
    call write_all
    mov rax, [rsp + 352]
    or rax, [rsp + 360]
    jnz .Ltirt_retire
    test r14, r14
    jz tirt_fail
    mov rdi, r14
    lea rsi, [rsp + 208]
    call theme_intent_view
    test rax, rax
    jnz tirt_fail
    mov rdi, r14
    call theme_intent_effective_slot
    mov [rsp + 368], rax
    mov edi, 1
    lea rsi, [rsp + 208 + 96]
    mov edx, 48
    call write_all
    mov edi, 1
    lea rsi, [rsp + 368]
    mov edx, 8
    call write_all
    mov edi, 1
    lea rsi, [rsp + 208 + 48]
    mov edx, 48
    call write_all
    xor r13d, r13d
    xor ecx, ecx
7:  cmp qword ptr [rsp + 208 + rcx*8], 0
    je 9f
    bts r13, rcx
9:  inc ecx
    cmp ecx, 6
    jb 7b
    mov [rsp + 368], r13
    mov edi, 1
    lea rsi, [rsp + 368]
    mov edx, 8
    call write_all
    xor r13d, r13d
10: mov rsi, [rsp + 208 + r13*8]
    mov rdx, [rsp + 208 + 48 + r13*8]
    mov edi, 1
    call write_all
    inc r13
    cmp r13, 6
    jb 10b
.Ltirt_retire:
    mov rdi, r14
    call theme_intent_release
    test rdx, rdx
    jz .Ltirt_retire
    mov rdi, r12
    call theme_intent_release
    test rax, rax
    jnz tirt_fail
    cmp rdx, 1
    jne tirt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tirt_fail
    cmp r15, [rip + g_mem_live]
    jne tirt_fail
    xor eax, eax
    EPILOGUE
