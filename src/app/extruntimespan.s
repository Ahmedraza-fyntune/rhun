# Numeric span checks for native caller-owned outputs; no source bytes are scanned.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# out,len,source,len ->0 disjoint/-EINVAL. All endpoints checked before comparison.
FN rt_spans_disjoint
    test rdi, rdi
    jz .Lrspan_bad
    test rsi, rsi
    jz .Lrspan_bad
    mov r8, rdi
    add r8, rsi
    jc .Lrspan_bad
    test rcx, rcx
    jz .Lrspan_ok
    test rdx, rdx
    jz .Lrspan_bad
    mov r9, rdx
    add r9, rcx
    jc .Lrspan_bad
    cmp r8, rdx
    jbe .Lrspan_ok
    cmp rdi, r9
    jae .Lrspan_ok
.Lrspan_bad:
    mov rax, -22
    ret
.Lrspan_ok:
    xor eax, eax
    ret

# out,width,typed PO ->0 disjoint/-EINVAL. TABLE has5, EA/HI1 allocation each.
# A corrupt/oversized ledger refuses after at most16 nodes, without an output write.
FN rt_output_disjoint_po
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [r13 + PO_allocs]
    mov r15d, 16
    mov qword ptr [rsp], 0
1:  test r14, r14
    jz 4f
    mov rax, [r14 + AO_charge]
    cmp rax, 32
    jb .Lrpo_bad
    mov rdx, r14
    sub rdx, 16
    jc .Lrpo_bad
    lea rcx, [r13 - AO_SIZE]
    cmp r14, rcx
    jne 2f
    sub rdx, RD_SIZE
    jc .Lrpo_bad
    mov qword ptr [rsp], 1
2:  mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    call rt_spans_disjoint
    test rax, rax
    jnz .Lrpo_done
    mov r14, [r14 + AO_next]
    dec r15
    jnz 1b
    test r14, r14
    jnz .Lrpo_bad
4:  cmp qword ptr [rsp], 1
    jne .Lrpo_bad
    mov rax, [r13 + PO_eo]
    lea rdx, [rax - RD_SIZE - 16]
    mov rcx, [rdx]
    # Every EO has a fixed128-byte creation block in the existing allocator.
    cmp rcx, 2
    jne .Lrpo_bad
    mov ecx, 128
    mov rdi, rbx
    mov rsi, r12
    call rt_spans_disjoint
.Lrpo_done:
    EPILOGUE
.Lrpo_bad:
    mov rax, -22
    EPILOGUE
