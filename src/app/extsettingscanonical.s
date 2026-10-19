# Verification only. Accepted local values must already be canonical.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingscatalog.inc"
.text
# readyEP,index,countedValue,len,copiedKeyLen ->0/-EINVAL.
FN ext_settings_canonical_value
    PROLOGUE
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    test rdi, rdi
    jz .Lsc_bad
    cmp qword ptr [rdi + PO_ready], 1
    jne .Lsc_bad
    cmp qword ptr [rdi + PO_refs], 0
    jle .Lsc_bad
    mov rax, [rdi + EP_ext + EXT_sdefs + VEC_len]
    cmp rax, ESV_MAX
    ja .Lsc_bad
    cmp rsi, rax
    jae .Lsc_bad
    imul rax, rsi, SD_SIZE
    mov rbx, [rdi + EP_ext + EXT_sdefs + VEC_ptr]
    test rbx, rbx
    jz .Lsc_bad
    add rbx, rax
    test r12, r12
    jz .Lsc_bad
    test r14, r14
    jz .Lsc_bad
    mov rax, r14
    add rax, r13
    jc .Lsc_bad
    add rax, 12
    jc .Lsc_bad
    cmp rax, EXT_LINE_MAX
    ja .Lsc_bad
    cmp byte ptr [r12 + r13], 0
    jne .Lsc_bad
    mov eax, [rbx + SD_type]
    cmp eax, SDT_STRING
    je .Lsc_string
    cmp eax, SDT_BOOL
    je .Lsc_bool
    cmp eax, SDT_INT
    je .Lsc_int
    cmp eax, SDT_CHOICE
    je .Lsc_choice
    jmp .Lsc_bad
.Lsc_string:
    mov rdi, r12
    mov rsi, r13
    call snippet_utf8_valid
    test eax, eax
    jz .Lsc_bad
    test r13, r13
    jz .Lsc_ok
    movzx eax, byte ptr [r12]
    cmp eax, ' '
    je .Lsc_bad
    cmp eax, 9
    je .Lsc_bad
    movzx eax, byte ptr [r12 + r13 - 1]
    cmp eax, ' '
    je .Lsc_bad
    cmp eax, 9
    je .Lsc_bad
    xor ecx, ecx
1:  cmp rcx, r13
    jae .Lsc_ok
    movzx eax, byte ptr [r12 + rcx]
    cmp eax, 127
    je .Lsc_bad
    cmp eax, 32
    jae 2f
    cmp eax, 9
    jne .Lsc_bad
2:  inc rcx
    jmp 1b
.Lsc_bool:
    cmp r13, 2
    jne 1f
    cmp word ptr [r12], 0x6f6e
    je .Lsc_ok
    jmp .Lsc_bad
1:  cmp r13, 3
    jne .Lsc_bad
    cmp word ptr [r12], 0x6579
    jne .Lsc_bad
    cmp byte ptr [r12 + 2], 's'
    je .Lsc_ok
    jmp .Lsc_bad
.Lsc_int:
    test r13, r13
    jz .Lsc_bad
    cmp r13, 10
    ja .Lsc_bad
    cmp r13, 1
    je 1f
    cmp byte ptr [r12], '0'
    je .Lsc_bad
1:  xor ecx, ecx
    xor edx, edx
2:  cmp rcx, r13
    jae 3f
    movzx eax, byte ptr [r12 + rcx]
    sub eax, '0'
    cmp eax, 9
    ja .Lsc_bad
    imul rdx, rdx, 10
    add rdx, rax
    inc rcx
    jmp 2b
3:  cmp rdx, 2147483647
    ja .Lsc_bad
    mov eax, [rbx + SD_min]
    cmp rdx, rax
    jb .Lsc_bad
    mov eax, [rbx + SD_max]
    cmp rdx, rax
    ja .Lsc_bad
    jmp .Lsc_ok
.Lsc_choice:
    mov r14, [rbx + SD_opts]
    test r14, r14
    jz .Lsc_bad
    xor r15d, r15d
.Lsc_option_next:
    cmp r15, EC_LIMIT
    jae .Lsc_bad
    movzx eax, byte ptr [r14 + r15]
    test eax, eax
    jz .Lsc_bad
    cmp eax, ' '
    je .Lsc_option_skip
    cmp eax, 9
    je .Lsc_option_skip
    mov rbx, r15
.Lsc_option_length:
    cmp r15, EC_LIMIT
    jae .Lsc_bad
    movzx eax, byte ptr [r14 + r15]
    test eax, eax
    jz .Lsc_option_compare
    cmp eax, ' '
    je .Lsc_option_compare
    cmp eax, 9
    je .Lsc_option_compare
    inc r15
    jmp .Lsc_option_length
.Lsc_option_compare:
    mov rax, r15
    sub rax, rbx
    cmp rax, r13
    jne .Lsc_option_next
    xor ecx, ecx
1:  cmp rcx, r13
    jae .Lsc_ok
    lea rdx, [r14 + rbx]
    movzx eax, byte ptr [rdx + rcx]
    cmp al, [r12 + rcx]
    jne .Lsc_option_next
    inc rcx
    jmp 1b
.Lsc_option_skip:
    inc r15
    jmp .Lsc_option_next
.Lsc_ok:
    xor eax, eax
    EPILOGUE
.Lsc_bad:
    mov rax, -22
    EPILOGUE
