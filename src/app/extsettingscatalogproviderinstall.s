# Private hash lookup and inline cell installation; no live provider state mutates.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.text
cp_provider_lookup_block:
    test qword ptr [rdi + CP_workflags], PPF_LOOKBASE
    jz cp_provider_target
    mov rax, [rdi + CP_baseline]
    ret
FN cp_provider_install
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + CP_ppphase]
    cmp rax, PPS_LOOKUP
    je .Lppi_lookup
    cmp rax, PPS_MATCH
    je .Lppi_match
    cmp rax, PPS_LANG_COPY
    je .Lppi_lang_copy
    cmp rax, PPS_OWNER_COPY
    je .Lppi_owner_copy
    cmp rax, PPS_INSTALL
    je .Lppi_install
    mov rax, -22
    jmp .Lppi_return
.Lppi_lookup:
    call cp_provider_lookup_block
    mov r12, rax
    mov rcx, [rbx + CP_probe]
    mov rax, [r12 + PB_buckets + rcx * 8]
    test rax, rax
    jz .Lppi_miss
    dec rax
    mov [rbx + CP_ppindex], rax
    imul r13, rax, PBM_SIZE
    lea r13, [r12 + PB_meta + r13]
    mov rcx, [rbx + CP_hash]
    cmp [r13 + PBM_hash], rcx
    jne .Lppi_probe_next
    mov rcx, [rbx + CP_pplanglen]
    cmp [r13 + PBM_langlen], rcx
    jne .Lppi_probe_next
    imul rax, PBR_SIZE
    mov rcx, [rbx + CP_ppkind]
    cmp [r12 + PB_rows + rax + PBR_kind], rcx
    jne .Lppi_probe_next
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_MATCH
    jmp .Lppi_zero
.Lppi_match:
    call cp_provider_lookup_block
    mov r12, rax
    mov rdi, rbx
    call cp_provider_fields
    test rax, rax
    jz .Lppi_input_error
    mov r13, [rax + EC_key]
    add r13, [rbx + CP_ppprefix]
    inc r13
    imul rax, [rbx + CP_ppindex], PBR_SIZE
    mov r14, [r12 + PB_rows + rax + PBR_language]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, [rbx + CP_pplanglen]
    jae .Lppi_matched
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppi_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r14 + rcx]
    jne .Lppi_probe_next
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
.Lppi_matched:
    test qword ptr [rbx + CP_workflags], PPF_LOOKBASE
    jnz .Lppi_fallback
    test qword ptr [rbx + CP_workflags], PPF_BAD
    jnz .Lppi_skip
    cmp qword ptr [rbx + CP_ppremove], 0
    jne .Lppi_remove
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_OWNER_COPY
    jmp .Lppi_zero
.Lppi_miss:
    test qword ptr [rbx + CP_workflags], PPF_LOOKBASE
    jnz .Lppi_skip
    test qword ptr [rbx + CP_workflags], PPF_BAD
    jz .Lppi_new
    mov rcx, [rbx + CP_probe]
    mov [rbx + CP_ppinitrow], rcx
    or qword ptr [rbx + CP_workflags], PPF_LOOKBASE
    mov rax, [rbx + CP_hash]
    and eax, 1023
    mov [rbx + CP_probe], rax
    jmp .Lppi_zero
.Lppi_new:
    cmp qword ptr [rbx + CP_ppremove], 0
    jne .Lppi_skip
    mov rcx, [rbx + CP_probe]
    mov [rbx + CP_ppinitrow], rcx
    jmp .Lppi_new_row
.Lppi_fallback:
    imul rax, [rbx + CP_ppindex], PBR_SIZE
    cmp qword ptr [r12 + PB_rows + rax + PBR_owner], 0
    je .Lppi_skip
    mov rax, [rbx + CP_ppindex]
    mov [rbx + CP_ppfallbackindex], rax
    imul rax, PBM_SIZE
    mov rax, [r12 + PB_meta + rax + PBM_ownerlen]
    mov [rbx + CP_ppownerlen], rax
    and qword ptr [rbx + CP_workflags], -13
    or qword ptr [rbx + CP_workflags], PPF_FALLBACK
    mov rdi, rbx
    call cp_provider_target
    mov r12, rax
.Lppi_new_row:
    mov rax, [r12 + PB_count]
    cmp rax, 512
    jae .Lppi_large
    mov [rbx + CP_ppindex], rax
    or qword ptr [rbx + CP_workflags], PPF_NEW
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_ppphase], PPS_LANG_COPY
    jmp .Lppi_zero
.Lppi_probe_next:
    inc qword ptr [rbx + CP_probe]
    and qword ptr [rbx + CP_probe], 1023
    mov qword ptr [rbx + CP_ppphase], PPS_LOOKUP
    jmp .Lppi_zero
.Lppi_lang_copy:
    call cp_provider_fields
    test rax, rax
    jz .Lppi_input_error
    mov r13, [rax + EC_key]
    add r13, [rbx + CP_ppprefix]
    inc r13
    mov r14, [rbx + CP_pplanglen]
    mov rdi, rbx
    call cp_provider_target
    imul rcx, [rbx + CP_ppindex], 129
    lea r12, [rax + PB_language + rcx]
    mov r15d, PPS_OWNER_COPY
    jmp .Lppi_copy
.Lppi_owner_copy:
    test qword ptr [rbx + CP_workflags], PPF_FALLBACK
    jnz 1f
    call cp_provider_fields
    test rax, rax
    jz .Lppi_input_error
    mov r13, [rax + EC_value]
    jmp 2f
1:  mov rax, [rbx + CP_baseline]
    imul rcx, [rbx + CP_ppfallbackindex], 202
    lea r13, [rax + PB_owner + rcx]
2:  mov r14, [rbx + CP_ppownerlen]
    mov rdi, rbx
    call cp_provider_target
    imul rcx, [rbx + CP_ppindex], 202
    lea r12, [rax + PB_owner + rcx]
    mov r15d, PPS_INSTALL
.Lppi_copy:
    mov rcx, [rbx + CP_scanpos]
    cmp rcx, r14
    jae .Lppi_copy_end
    mov rdx, r14
    sub rdx, rcx
    mov rax, [rbx + CP_bytesleft]
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .Lppi_zero
    add r13, rcx
    mov rsi, r13
    lea rdi, [r12 + rcx]
    mov r12, rdx
    call memcpy
    add [rbx + CP_scanpos], r12
    sub [rbx + CP_bytesleft], r12
    # Re-derive destination next time; NUL itself consumes one copy-byte unit.
    jmp .Lppi_zero
.Lppi_copy_end:
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppi_zero
    mov byte ptr [r12 + rcx], 0
    dec qword ptr [rbx + CP_bytesleft]
    mov qword ptr [rbx + CP_scanpos], 0
    mov [rbx + CP_ppphase], r15
    jmp .Lppi_zero
.Lppi_remove:
    mov qword ptr [rbx + CP_ppphase], PPS_INSTALL
    jmp .Lppi_zero
.Lppi_install:
    call cp_provider_target
    mov r12, rax
    mov r13, [rbx + CP_ppindex]
    imul rax, r13, PBR_SIZE
    lea r14, [r12 + PB_rows + rax]
    imul rax, r13, PBM_SIZE
    lea r15, [r12 + PB_meta + rax]
    test qword ptr [rbx + CP_workflags], PPF_NEW
    jz 1f
    mov rcx, [rbx + CP_ppinitrow]
    lea rax, [r13 + 1]
    mov [r12 + PB_buckets + rcx * 8], rax
    inc qword ptr [r12 + PB_count]
    mov rax, [rbx + CP_ppkind]
    mov [r14 + PBR_kind], rax
    imul rax, r13, 129
    lea rax, [r12 + PB_language + rax]
    mov [r14 + PBR_language], rax
    mov rax, [rbx + CP_hash]
    mov [r15 + PBM_hash], rax
    mov rax, [rbx + CP_pplanglen]
    mov [r15 + PBM_langlen], rax
1:  cmp qword ptr [rbx + CP_ppremove], 0
    jne .Lppi_clear_owner
    cmp qword ptr [r14 + PBR_owner], 0
    jne 2f
    inc qword ptr [r12 + PB_active]
2:  imul rax, r13, 202
    lea rax, [r12 + PB_owner + rax]
    mov [r14 + PBR_owner], rax
    mov rax, [rbx + CP_ppownerlen]
    mov [r15 + PBM_ownerlen], rax
    mov eax, PBMF_RAW
    test qword ptr [rbx + CP_workflags], PPF_FALLBACK
    jz 3f
    mov eax, PBMF_FALLBACK
3:  test qword ptr [rbx + CP_workflags], PPF_DIRTY
    jz 4f
    mov eax, PBMF_DIRTY
4:  mov [r15 + PBM_flags], rax
    jmp .Lppi_skip
.Lppi_clear_owner:
    cmp qword ptr [r14 + PBR_owner], 0
    je 1f
    dec qword ptr [r12 + PB_active]
1:  mov qword ptr [r14 + PBR_owner], 0
    mov qword ptr [r15 + PBM_ownerlen], 0
    mov qword ptr [r15 + PBM_flags], PBMF_DIRTY
.Lppi_skip:
    mov rdi, rbx
    call cp_provider_advance
    jmp .Lppi_return
.Lppi_zero:
    xor eax, eax
.Lppi_return:
    EPILOGUE
.Lppi_input_error:
    mov rax, rdx
    EPILOGUE
.Lppi_large:
    mov rax, -7
    EPILOGUE
