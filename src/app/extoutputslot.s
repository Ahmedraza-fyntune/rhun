# Complete output spans, including allocation prefixes and allocator padding.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# out8, stable EXT, typed ACTIVE PO-or0, typed ACTIVE PO-or0 ->0/-EINVAL.
# Caller has already checked each object's exact type and immutable layout.
FN ext_owned_output_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test rbx, rbx
    jz .Los_bad
    test bl, 7
    jnz .Los_bad
    mov r15, rbx
    add r15, 8
    jc .Los_bad
    test r12, r12
    jz .Los_bad
    mov rax, r12
    add rax, EXT_SIZE
    jc .Los_bad
    cmp r15, r12
    jbe 1f
    cmp rbx, rax
    jb .Los_bad
1:  mov rdi, r13
    call .Los_object
    test eax, eax
    jnz .Los_bad
    mov rdi, r14
    call .Los_object
    test eax, eax
    jnz .Los_bad
    cmp qword ptr [rbx], 0
    jne .Los_bad
    xor eax, eax
    EPILOGUE
.Los_bad:
    mov rax, -22
    EPILOGUE
.Los_object:
    test rdi, rdi
    jz 9f
    mov r8, rdi
    sub r8, RD_PO_BACK + 16
    jc 8f
    mov r9, [rdi - AO_SIZE + AO_charge]
    cmp r9, RD_PO_BACK + 16 + PO_SIZE
    jb 8f
    cmp r9, PREP_TOTAL_CAP
    ja 8f
    add r9, r8
    jc 8f
    cmp r15, r8
    jbe 1f
    cmp rbx, r9
    jb 8f
1:  mov r8, [rdi + PO_eo]
    test r8, r8
    jz 8f
    mov r9, r8
    sub r8, RD_SIZE + 16
    jc 8f
    add r9, EO_SIZE
    jc 8f
    cmp r15, r8
    jbe 9f
    cmp rbx, r9
    jb 8f
9:  xor eax, eax
    ret
8:  mov eax, 1
    ret
