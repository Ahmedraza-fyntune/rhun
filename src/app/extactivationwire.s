# Build the existing keeper authorization directly in charged inline storage.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extactivation.inc"
.section .rodata
ea_empty: .asciz ""
.text
FN ea_wire_build
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rbx + EA_plan]
    mov edx, KE_SIZE
    call memcpy
    lea r13, [rbx + EA_wire]
    mov rax, KA_MAGIC
    mov [r13], rax
    mov dword ptr [r13 + 8], 1
    mov eax, [r12 + KE_kind]
    mov [r13 + 12], eax
    mov eax, [r12 + KE_needs]
    mov [r13 + 16], eax
    mov eax, [r12 + KE_fallback]
    mov [r13 + 20], eax
    mov rax, [r12 + KE_context]
    mov [r13 + 24], rax
    mov rsi, [r12 + KE_expected]
    test rsi, rsi
    jz 1f
    lea rdi, [r13 + 32]
    mov edx, EXI_SIZE
    call memcpy
1:  mov rsi, [r12 + KE_id]
    test rsi, rsi
    jz 2f
    mov rdi, rsi
    mov esi, 64
    call ext_root_length
    cmp rax, 64
    jne 8f
    lea rdi, [r13 + 192]
    mov rsi, [r12 + KE_id]
    mov edx, 64
    call memcpy
2:  lea r14, [r13 + KA_HEADER]
    xor r15d, r15d
3:  mov rsi, [r12 + r15*8]
    test rsi, rsi
    jnz 4f
    lea rsi, [rip + ea_empty]
4:  mov [rsp], rsi
    mov rdi, rsi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    js 9f
    inc rax
    mov [r13 + r15*4 + 276], eax
    mov [rsp + 8], rax
    lea rcx, [r14 + rax]
    sub rcx, r13
    cmp rcx, KA_MAX
    ja 8f
    mov rdi, r14
    mov rsi, [rsp]
    mov rdx, rax
    call memcpy
    add r14, [rsp + 8]
    inc r15
    cmp r15, 10
    jb 3b
    mov dword ptr [r13 + 316], 1
    mov byte ptr [r14], 0
    inc r14
    sub r14, r13
    mov [rbx + EA_wirelen], r14
    mov rdi, r13
    mov rsi, r14
    call kp_auth_parse
    test rax, rax
    js 9f
    mov r12, rax
    xor ecx, ecx
5:  mov rdx, [r12 + AX_strings + rcx*8]
    mov [rbx + EA_plan + rcx*8], rdx
    inc rcx
    cmp rcx, 10
    jb 5b
    mov rax, [r12 + AX_expected]
    mov [rbx + EA_plan + KE_expected], rax
    mov rax, [r12 + AX_id]
    mov [rbx + EA_plan + KE_id], rax
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
