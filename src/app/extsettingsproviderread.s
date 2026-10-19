# Effective preferences include unavailable owners; absence never redirects them.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.section .rodata
sar_section: .ascii "providers"
sar_symbols: .ascii "symbols."
sar_rename: .ascii "rename."
sar_format: .ascii "format."
sar_signature: .ascii "signature."
.text
# Counted owner cstr ->0/-EINVAL, preserving existing provider identity grammar.
settings_provider_owner:
    test rdi, rdi
    jz .Lsaro_bad
    test rsi, rsi
    jz .Lsaro_bad
    cmp rsi, 201
    ja .Lsaro_bad
    cmp byte ptr [rdi + rsi], 0
    jne .Lsaro_bad
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
1:  cmp rcx, rsi
    jae 4f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp eax, '/'
    jne 2f
    test r9, r9
    jz .Lsaro_bad
    inc r8
    cmp r8, 1
    ja .Lsaro_bad
    xor r9d, r9d
    jmp 1b
2:  inc r9
    cmp eax, '.'
    je 1b
    cmp eax, '-'
    je 1b
    cmp eax, '_'
    je 1b
    cmp eax, '0'
    jb .Lsaro_bad
    cmp eax, '9'
    jbe 1b
    or eax, 32
    sub eax, 'a'
    cmp eax, 26
    jb 1b
    jmp .Lsaro_bad
4:  test r9, r9
    jz .Lsaro_bad
    cmp r8, 1
    jne .Lsaro_bad
    xor eax, eax
    ret
.Lsaro_bad:
    mov rax, -22
    ret

# kind,counted language,len ->owner/NULL,RDXerror,RCXpresence,R8ownerlen.
# All live result bytes must be copied before yielding or mutating intent.
FN ext_settings_effective_provider
    PROLOGUE 192
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp rbx, 3
    je 1f
    cmp rbx, 5
    je 1f
    cmp rbx, 6
    je 1f
    cmp rbx, 7
    jne .Lsar_invalid
1:  test r12, r12
    jz .Lsar_invalid
    test r13, r13
    jz .Lsar_invalid
    cmp r13, 128
    ja .Lsar_invalid
    mov rdi, r12
    mov rsi, r13
    call snippet_utf8_valid
    test eax, eax
    jz .Lsar_invalid
    mov r15d, 177573
    xor r15, rbx
    xor ecx, ecx
2:  cmp rcx, r13
    jae .Lsar_model
    movzx eax, byte ptr [r12 + rcx]
    cmp eax, 32
    jb .Lsar_invalid
    cmp eax, '='
    je .Lsar_invalid
    cmp eax, '['
    je .Lsar_invalid
    cmp eax, ']'
    je .Lsar_invalid
    mov rdx, r15
    shl r15, 5
    add r15, rdx
    xor r15, rax
    inc rcx
    jmp 2b
.Lsar_model:
    cmp qword ptr [rip + esv_provider_epoch], 0
    jle .Lsar_stale
    call settings_active_model
    test rax, rax
    jz .Lsar_refusal
    mov r14, rax
    lea rsi, [rip + sar_symbols]
    mov edx, 8
    cmp rbx, 3
    je 1f
    lea rsi, [rip + sar_signature]
    mov edx, 10
    cmp rbx, 7
    je 1f
    lea rsi, [rip + sar_rename]
    cmp rbx, 5
    je 11f
    lea rsi, [rip + sar_format]
11: mov edx, 7
1:  mov [rsp + 144], rdx
    mov rdi, rsp
    call memcpy
    mov rax, [rsp + 144]
    lea rdi, [rsp + rax]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov r8, [rsp + 144]
    add r8, r13
    mov rdi, [rip + esv_service_queue]
    lea rsi, [rip + sar_section]
    mov edx, 9
    mov rcx, rsp
    call ext_settings_queue_find
    test rax, rax
    jz .Lsar_baseline
    mov rbx, rax
    mov rax, [rbx + EQC_seq]
    test rax, rax
    jle .Lsar_stale
    mov rcx, [rip + esv_service_queue]
    cmp rax, [rcx + EQ_seq]
    ja .Lsar_stale
    cmp qword ptr [rbx + EC_remove], 0
    je .Lsar_dirty_owner
    cmp qword ptr [rbx + EC_remove], 1
    jne .Lsar_invalid
    xor eax, eax
    xor r8d, r8d
    mov ecx, 1
    xor edx, edx
    EPILOGUE
.Lsar_dirty_owner:
    mov rdi, [rbx + EC_value]
    mov rsi, [rbx + EC_vallen]
    call settings_provider_owner
    test rax, rax
    jnz .Lsar_error
    mov rax, [rbx + EC_value]
    mov r8, [rbx + EC_vallen]
    mov ecx, 1
    xor edx, edx
    EPILOGUE
.Lsar_baseline:
    mov r14, [r14 + ELM_providers]
    test r14, r14
    jz .Lsar_absent
    cmp qword ptr [r14 + PB_count], 512
    ja .Lsar_stale
    mov rax, r15
    and eax, 1023
    mov [rsp + 152], rax
    mov qword ptr [rsp + 160], 1024
.Lsar_probe:
    mov rcx, [rsp + 152]
    mov rax, [r14 + PB_buckets + rcx * 8]
    test rax, rax
    jz .Lsar_absent
    dec rax
    cmp rax, [r14 + PB_count]
    jae .Lsar_stale
    mov [rsp + 168], rax
    imul rcx, rax, PBM_SIZE
    cmp [r14 + PB_meta + rcx + PBM_hash], r15
    jne .Lsar_next
    cmp [r14 + PB_meta + rcx + PBM_langlen], r13
    jne .Lsar_next
    imul rax, PBR_SIZE
    cmp [r14 + PB_rows + rax + PBR_kind], rbx
    jne .Lsar_next
    mov rdi, [r14 + PB_rows + rax + PBR_language]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jz .Lsar_next
    mov rax, [rsp + 168]
    imul rcx, rax, PBM_SIZE
    mov r8, [r14 + PB_meta + rcx + PBM_ownerlen]
    imul rax, PBR_SIZE
    mov rax, [r14 + PB_rows + rax + PBR_owner]
    mov ecx, 1
    xor edx, edx
    EPILOGUE
.Lsar_next:
    inc qword ptr [rsp + 152]
    and qword ptr [rsp + 152], 1023
    dec qword ptr [rsp + 160]
    jnz .Lsar_probe
.Lsar_stale:
    mov rax, -116
    jmp .Lsar_error
.Lsar_invalid:
    mov rax, -22
.Lsar_error:
    mov rdx, rax
.Lsar_refusal:
    xor eax, eax
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
.Lsar_absent:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
