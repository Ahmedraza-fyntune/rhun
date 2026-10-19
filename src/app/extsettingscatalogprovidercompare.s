# Compare active maps, not row order or harmless explicit automatic tombstones.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
FN cp_provider_compare
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CP_provider]
    mov r13, [rbx + CP_baseline]
    mov rax, [rbx + CP_ppphase]
    cmp rax, PPS_COMPARE_BEGIN
    je .Lppc_begin
    cmp rax, PPS_COMPARE_NEXT
    je .Lppc_next
    cmp rax, PPS_COMPARE_LOOKUP
    je .Lppc_lookup
    cmp rax, PPS_COMPARE_LANG
    je .Lppc_language
    cmp rax, PPS_COMPARE_OWNER
    je .Lppc_owner
    mov rax, -22
    jmp .Lppc_return
.Lppc_begin:
    mov qword ptr [rbx + CP_ppdiff], 0
    mov rax, [r12 + PB_active]
    cmp [r13 + PB_active], rax
    jne .Lppc_diff
    mov qword ptr [rbx + CP_ppsourceindex], 0
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_NEXT
    jmp .Lppc_zero
.Lppc_next:
    mov rcx, [rbx + CP_ppsourceindex]
    cmp rcx, [r12 + PB_count]
    jae .Lppc_finish
    imul rax, rcx, PBR_SIZE
    lea r14, [r12 + PB_rows + rax]
    cmp qword ptr [r14 + PBR_owner], 0
    je .Lppc_advance
    mov rax, [r14 + PBR_kind]
    mov [rbx + CP_ppkind], rax
    imul rax, rcx, PBM_SIZE
    mov rcx, [r12 + PB_meta + rax + PBM_hash]
    mov [rbx + CP_hash], rcx
    and ecx, 1023
    mov [rbx + CP_probe], rcx
    mov rax, [r12 + PB_meta + rax + PBM_langlen]
    mov [rbx + CP_pplanglen], rax
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_LOOKUP
    jmp .Lppc_zero
.Lppc_lookup:
    mov rcx, [rbx + CP_probe]
    mov rax, [r13 + PB_buckets + rcx * 8]
    test rax, rax
    jz .Lppc_diff
    dec rax
    mov [rbx + CP_ppoldrow], rax
    imul rcx, rax, PBM_SIZE
    lea r15, [r13 + PB_meta + rcx]
    mov rcx, [rbx + CP_hash]
    cmp [r15 + PBM_hash], rcx
    jne .Lppc_probe_next
    mov rcx, [rbx + CP_pplanglen]
    cmp [r15 + PBM_langlen], rcx
    jne .Lppc_probe_next
    imul rax, PBR_SIZE
    mov rcx, [rbx + CP_ppkind]
    cmp [r13 + PB_rows + rax + PBR_kind], rcx
    jne .Lppc_probe_next
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_LANG
    jmp .Lppc_zero
.Lppc_language:
    imul rax, [rbx + CP_ppsourceindex], PBR_SIZE
    mov r14, [r12 + PB_rows + rax + PBR_language]
    imul rax, [rbx + CP_ppoldrow], PBR_SIZE
    mov r15, [r13 + PB_rows + rax + PBR_language]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, [rbx + CP_pplanglen]
    jae 2f
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppc_zero
    movzx eax, byte ptr [r14 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r15 + rcx]
    jne .Lppc_probe_next
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
2:  imul rax, [rbx + CP_ppoldrow], PBR_SIZE
    cmp qword ptr [r13 + PB_rows + rax + PBR_owner], 0
    je .Lppc_diff
    imul rax, [rbx + CP_ppoldrow], PBM_SIZE
    mov rax, [r13 + PB_meta + rax + PBM_ownerlen]
    imul rcx, [rbx + CP_ppsourceindex], PBM_SIZE
    cmp [r12 + PB_meta + rcx + PBM_ownerlen], rax
    jne .Lppc_diff
    mov [rbx + CP_ppownerlen], rax
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_OWNER
    jmp .Lppc_zero
.Lppc_owner:
    imul rax, [rbx + CP_ppsourceindex], PBR_SIZE
    mov r14, [r12 + PB_rows + rax + PBR_owner]
    imul rax, [rbx + CP_ppoldrow], PBR_SIZE
    mov r15, [r13 + PB_rows + rax + PBR_owner]
1:  mov rcx, [rbx + CP_scanpos]
    cmp rcx, [rbx + CP_ppownerlen]
    jae .Lppc_advance
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppc_zero
    movzx eax, byte ptr [r14 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r15 + rcx]
    jne .Lppc_diff
    inc qword ptr [rbx + CP_scanpos]
    jmp 1b
.Lppc_probe_next:
    inc qword ptr [rbx + CP_probe]
    and qword ptr [rbx + CP_probe], 1023
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_LOOKUP
    jmp .Lppc_zero
.Lppc_advance:
    inc qword ptr [rbx + CP_ppsourceindex]
    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_NEXT
    jmp .Lppc_zero
.Lppc_diff:
    mov qword ptr [rbx + CP_ppdiff], 1
.Lppc_finish:
    mov rax, [rbx + CP_providerepoch]
    cmp qword ptr [rbx + CP_ppdiff], 0
    je 1f
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jae .Lppc_overflow
    inc rax
1:  mov [rbx + CP_newprovider], rax
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_phase], CPP_FINAL
.Lppc_zero:
    xor eax, eax
.Lppc_return:
    EPILOGUE
.Lppc_overflow:
    mov rax, -75
    EPILOGUE
