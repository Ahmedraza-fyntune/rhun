# Pure helper argument/request validation before any settings operation.
.include "rhun.inc"
.include "app/themecapture.inc"
.equ EWT_job, 0
.equ EWT_context, 8
.equ EWT_nonce, 16
.section .rodata
.Ltcwp_marker: .asciz "--theme-source-worker"
.Ltcwp_version: .asciz "v1"
.text
# positive63 decimal, exact bounded input ->RAX number or0, RDX error.
tcwp_number:
    PROLOGUE
    mov rbx, rdi
    mov esi, 19
    call ext_root_length
    test rax, rax
    jle 3f
    mov r12, rax
    xor eax, eax
    xor ecx, ecx
1:  movzx edx, byte ptr [rbx + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 3f
    mov r8, 922337203685477580
    cmp rax, r8
    ja 3f
    jb 2f
    cmp edx, 7
    ja 3f
2:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    cmp rcx, r12
    jb 1b
    test rax, rax
    jz 3f
    xor edx, edx
    EPILOGUE
3:  xor eax, eax
    mov rdx, -22
    EPILOGUE

tcwp_nibble:
    mov eax, edi
    sub eax, '0'
    cmp eax, 9
    jbe 1f
    mov eax, edi
    sub eax, 'a'
    cmp eax, 5
    ja 2f
    add eax, 10
1:  ret
2:  mov rax, -1
    ret

# arguments(argc,argv,outTag32)->0/-EINVAL. No environment or global state.
FN theme_capture_worker_arguments
    cmp rdi, 6
    jne .Ltcwp_bad_leaf
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    mov rdi, [rbx + 8]
    lea rsi, [rip + .Ltcwp_marker]
    call strcmp_eq
    test eax, eax
    jz .Ltcwp_bad
    mov rdi, [rbx + 16]
    lea rsi, [rip + .Ltcwp_version]
    call strcmp_eq
    test eax, eax
    jz .Ltcwp_bad
    mov rdi, [rbx + 24]
    call tcwp_number
    test rdx, rdx
    jnz .Ltcwp_bad
    mov [r12 + EWT_job], rax
    mov rdi, [rbx + 32]
    call tcwp_number
    test rdx, rdx
    jnz .Ltcwp_bad
    mov [r12 + EWT_context], rax
    mov r13, [rbx + 40]
    mov rdi, r13
    mov esi, 32
    call ext_root_length
    cmp rax, 32
    jne .Ltcwp_bad
    xor r14d, r14d
1:  movzx edi, byte ptr [r13 + r14]
    call tcwp_nibble
    test rax, rax
    js .Ltcwp_bad
    mov r15d, eax
    shl r15d, 4
    inc r14
    movzx edi, byte ptr [r13 + r14]
    call tcwp_nibble
    test rax, rax
    js .Ltcwp_bad
    or eax, r15d
    mov rcx, r14
    shr rcx, 1
    mov [r12 + rcx + EWT_nonce], al
    inc r14
    cmp r14, 32
    jb 1b
    mov rax, [r12 + 16]
    or rax, [r12 + 24]
    jz .Ltcwp_bad
    xor eax, eax
    EPILOGUE
.Ltcwp_bad:
    mov rax, -22
    EPILOGUE
.Ltcwp_bad_leaf:
    mov rax, -22
    ret

