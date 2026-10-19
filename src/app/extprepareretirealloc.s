# Exact preparation block accounting and checked allocator consumption.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.globl prep_total_charge
.p2align 3
prep_total_charge: .quad 0
.text
# The main thread performs no yield between admission and allocation/charge commit.
FN prep_global_admit
    test rdi, rdi
    jz 8f
    mov rax, [rip + prep_total_charge]
    add rax, rdi
    jc 8f
    cmp rax, PREP_TOTAL_CAP
    ja 8f
    xor eax, eax
    ret
8:  mov rax, -EV_RESOURCE
    ret

FN ext_prepare_retire_charge
    mov rax, [rip + prep_total_charge]
    ret

# Raw allocator payload pointer, not an adjusted EO/PO pointer.
FN prep_pointer_charge
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov rcx, [rdi - 16]
    mov rax, rcx
    cmp rcx, 64
    jae 9f
    mov eax, 32
    shl rax, cl
9:  ret

# 0/-errno, RDX1 consumed or0 known unconsumed. Failure preserves allocator header.
FN prep_cleanup_free
    test rdi, rdi
    jnz 1f
    xor eax, eax
    mov edx, 1
    ret
1:  PROLOGUE
    mov rbx, [rdi - 16]
    call mem_free
    cmp rbx, 64
    jb 2f
    test rax, rax
    jns 2f
    inc qword ptr [rip + g_mem_live]
    xor edx, edx
    EPILOGUE
2:  xor eax, eax
    mov edx, 1
    EPILOGUE

# Caller retains EO through this call, including after disposing an orphan GP.
FN prep_owner_note_cleanup
    test rsi, rsi
    jns 9f
    cmp qword ptr [rdi - RD_SIZE + RD_diagnostic], 0
    jne 9f
    mov [rdi - RD_SIZE + RD_diagnostic], rsi
9:  ret
