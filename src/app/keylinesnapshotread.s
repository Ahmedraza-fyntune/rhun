.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/keylinesnapshot.inc"
.text
FN keyline_snapshot_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ksi_ready
    test rax, rax
    jnz .Lkscheck_invalid
    test r12, r12
    jle 8f
    cmp [rbx + KSI_epoch], r12
    jne 8f
9:  EPILOGUE
8:  mov rax, -116
    EPILOGUE
.Lkscheck_invalid:
    mov rax, -22
    EPILOGUE
FN keyline_snapshot_count
    PROLOGUE
    mov rbx, rdi
    call ksi_ready
    test rax, rax
    jnz 9f
    mov rax, [rbx + KSI_nrows]
9:  EPILOGUE
FN keyline_snapshot_row
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz 8f
    call ksi_ready
    test rax, rax
    jnz 9f
    cmp r12, [rbx + KSI_nrows]
    jae 8f
    shl r12, 5
    lea rsi, [rbx + r12 + KSI_rows]
    mov rdi, r13
    mov edx, 32
    call memcpy
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
