# Copy immutable key inputs from a retained ready CG without using mutable config.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/commandgeneration.inc"
.include "app/keylinesnapshot.inc"
.text
FN command_generation_key_copy_begin
    mov r8d, KSC_CG
    jmp keyline_copy_begin
# source,kind ->0/-errno, count/base on success; both outputs0 on refusal.
FN keyline_copy_source
    PROLOGUE
    mov rbx, rdi
    cmp rsi, KSC_KSI
    je .Lkcpy_ksi
    cmp rsi, KSC_CG
    jne .Lkcpy_invalid
    call cg_active
    test rax, rax
    jnz .Lkcpy_error
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz .Lkcpy_error
    cmp qword ptr [rbx + PO_ready], 1
    jne .Lkcpy_invalid
    cmp qword ptr [rbx + CG_phase], CG_READY
    jne .Lkcpy_invalid
    mov rdx, [rbx + CG_nkeys]
    cmp rdx, CG_KEY_CAP
    ja .Lkcpy_invalid
    lea rcx, [rbx + CG_keylines]
    xor eax, eax
    EPILOGUE
.Lkcpy_ksi:
    call ksi_ready
    test rax, rax
    jnz .Lkcpy_error
    mov rdx, [rbx + KSI_nrows]
    lea rcx, [rbx + KSI_rows]
    xor eax, eax
    EPILOGUE
.Lkcpy_invalid:
    mov rax, -22
.Lkcpy_error:
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
