# A stable complete physical-row census supplies the debt class timer.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeremove.inc"
.include "app/extruntimedebtscan.inc"
.text
# Pure VOID, caller already checked TABLE. Leaf producers inline these two stores.
FN rt_debt_scan_invalidate
    mov qword ptr [rdi + RT_debtScanValid], 0
    mov qword ptr [rdi + RT_debtScanDirty], 1
    ret

# Held ready TABLE and census scalar invariants ->0/-EINVAL, no mutation.
FN rt_debt_scan_check
    PROLOGUE
    mov rbx, rdi
    call rt_table_is_owned
    test eax, eax
    jz .Ldsc_bad
    cmp qword ptr [rbx + PO_ready], 1
    jne .Ldsc_bad
    test qword ptr [rbx + RT_flags], RTF_BUILDING | RTF_MEMORY_ONLY
    jnz .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanDirty], 1
    ja .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanActive], 1
    ja .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanValid], 1
    ja .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanHasDue], 1
    ja .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanCursor], RT_ROW_COUNT
    ja .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanHasDue], 0
    je 1f
    cmp qword ptr [rbx + RT_debtScanMin], 0
    jl .Ldsc_bad
1:  cmp qword ptr [rbx + RT_debtScanValid], 0
    je .Ldsc_ok
    mov rax, [rbx + RT_debtScanDirty]
    or rax, [rbx + RT_debtScanActive]
    jnz .Ldsc_bad
    cmp qword ptr [rbx + RT_debtScanCursor], RT_ROW_COUNT
    jne .Ldsc_bad
.Ldsc_ok:
    xor eax, eax
    EPILOGUE
.Ldsc_bad:
    mov rax, -22
    EPILOGUE

# TABLE,budget1..16 ->AX0 pending/1 complete/-errno,DXvisited<=budget,CX0.
FN rt_debt_scan_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
    lea rax, [r12 - 1]
    cmp rax, 16
    jae .Ldss_bad
    call rt_debt_scan_check
    test rax, rax
    jnz .Ldss_bad
    cmp qword ptr [rbx + RT_debtScanValid], 1
    je .Ldss_ready
    cmp qword ptr [rbx + RT_debtScanActive], 0
    je .Ldss_begin
    cmp qword ptr [rbx + RT_debtScanDirty], 0
    je .Ldss_loop
.Ldss_begin:
    mov qword ptr [rbx + RT_debtScanValid], 0
    mov qword ptr [rbx + RT_debtScanCursor], 0
    mov qword ptr [rbx + RT_debtScanMin], 0
    mov qword ptr [rbx + RT_debtScanHasDue], 0
    mov qword ptr [rbx + RT_debtScanActive], 1
    mov qword ptr [rbx + RT_debtScanDirty], 0
.Ldss_loop:
    mov r14, [rbx + RT_debtScanCursor]
    cmp r14, RT_ROW_COUNT
    jae .Ldss_finish
    cmp r13, r12
    jae .Ldss_pending
    lea rax, [r14 + 1]
    mov [rbx + RT_debtScanCursor], rax
    inc r13
    imul r14, r14, RT_ROW_SIZE
    lea r14, [rbx + r14 + RT_rows]
    mov rax, [r14 + RTR_state]
    cmp rax, RTR_DEBT
    ja .Ldss_corrupt
    jne .Ldss_loop
    mov rdx, [r14 + RTR_debtDue]
    cmp rdx, -1
    jl .Ldss_corrupt
    je .Ldss_loop
    cmp qword ptr [rbx + RT_debtScanHasDue], 0
    je .Ldss_min
    cmp rdx, [rbx + RT_debtScanMin]
    jae .Ldss_loop
.Ldss_min:
    mov [rbx + RT_debtScanMin], rdx
    mov qword ptr [rbx + RT_debtScanHasDue], 1
    jmp .Ldss_loop
.Ldss_finish:
    # No callbacks or yields between dirty observation and cache publication.
    cmp qword ptr [rbx + RT_debtScanDirty], 0
    jne .Ldss_pending
    mov qword ptr [rbx + RT_debtScanActive], 0
    mov qword ptr [rbx + RT_debtScanValid], 1
.Ldss_ready:
    mov eax, 1
    jmp .Ldss_return
.Ldss_pending:
    xor eax, eax
    jmp .Ldss_return
.Ldss_corrupt:
    mov qword ptr [rbx + RT_debtScanValid], 0
    mov qword ptr [rbx + RT_debtScanActive], 0
    mov qword ptr [rbx + RT_debtScanDirty], 1
    mov rax, -71
    jmp .Ldss_return
.Ldss_bad:
    mov rax, -22
.Ldss_return:
    mov rdx, r13
    xor ecx, ecx
    EPILOGUE

# TABLE,now ->AXabsoluteDueOr0,DXcomplete0/1,CXrunnable0/1;negativeAX on API error.
FN rt_debt_timeout
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    js .Ldst_bad
    call rt_debt_scan_check
    test rax, rax
    jnz .Ldst_bad
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    cmp qword ptr [rbx + RT_debtScanValid], 1
    jne .Ldst_return
    mov edx, 1
    cmp qword ptr [rbx + RT_debtScanHasDue], 0
    je .Ldst_return
    mov rax, [rbx + RT_debtScanMin]
    cmp rax, r12
    ja .Ldst_return
    xor eax, eax
    mov ecx, 1
    jmp .Ldst_return
.Ldst_bad:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
.Ldst_return:
    EPILOGUE
