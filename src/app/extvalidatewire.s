# Exact bounded anchored validator receipt. No process state or pointers cross the wire.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatewire.inc"
.text
# receipt_check(bytes,len,tag64,treeOr0,sourceOr0,out64)->primary/RDXcleanup.
FN ext_validate_receipt_check
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    cmp rsi, EVR_SIZE
    jne .Levr_bad
    mov rax, 0x00314c4156454852
    cmp [rbx], rax
    jne .Levr_bad
    cmp dword ptr [rbx + 8], 1
    jne .Levr_bad
    cmp dword ptr [rbx + 12], EVR_SIZE
    jne .Levr_bad
    xor ecx, ecx
1:  cmp qword ptr [rbx + EVR_reserved + rcx], 0
    jne .Levr_bad
    add rcx, 8
    cmp rcx, 32
    jb 1b
    lea rdi, [rbx + EVR_tag]
    mov rsi, r12
    mov edx, 64
    call memeq
    test eax, eax
    jz .Levr_bad
    mov rax, [rbx + EVR_primary]
    mov rdx, [rbx + EVR_secondary]
    test rax, rax
    jg .Levr_bad
    cmp rax, -4095
    jl .Levr_bad
    test rdx, rdx
    jg .Levr_bad
    cmp rdx, -4095
    jl .Levr_bad
    mov rcx, rax
    or rcx, rdx
    jz .Levr_success
    xor ecx, ecx
2:  cmp qword ptr [rbx + EVR_tree + rcx], 0
    jne .Levr_bad
    add rcx, 8
    cmp rcx, 64
    jb 2b
    test rax, rax
    jnz .Levr_done
    mov rax, rdx
.Levr_done:
    EPILOGUE
.Levr_success:
    test r13, r13
    jz 3f
    lea rdi, [rbx + EVR_tree]
    mov rsi, r13
    mov edx, 32
    call memeq
    test eax, eax
    jz .Levr_bad
3:  test r14, r14
    jz 4f
    lea rdi, [rbx + EVR_source]
    mov rsi, r14
    mov edx, 32
    call memeq
    test eax, eax
    jz .Levr_bad
4:  mov rdi, r15
    lea rsi, [rbx + EVR_tree]
    mov edx, EV_RESULT_SIZE
    call memcpy
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Levr_bad:
    mov rax, -EV_CHANGED
    xor edx, edx
    EPILOGUE

# Strict full unsigned decimal, overflow checked before multiply. RDX=0 or usage.
evr_decimal:
    PROLOGUE
    mov rbx, rdi
    mov esi, 20
    call ext_root_length
    test rax, rax
    jle 8f
    mov r12, rax
    xor ecx, ecx
    xor eax, eax
    mov r8, 1844674407370955161
1:  movzx edx, byte ptr [rbx + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 8f
    cmp rax, r8
    ja 8f
    jne 2f
    cmp edx, 5
    ja 8f
2:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    cmp rcx, r12
    jb 1b
    xor edx, edx
    EPILOGUE
8:  xor eax, eax
    mov rdx, -EV_USAGE
    EPILOGUE

# Counted exact lowercase hex decoder for owned nonce/source storage.
evr_unhex:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdx
    call ext_root_length
    cmp rax, r13
    jne 8f
    xor r14d, r14d
1:  movzx edi, byte ptr [rbx + r14]
    call evr_nibble
    test eax, eax
    js 8f
    mov r15d, eax
    shl r15d, 4
    movzx edi, byte ptr [rbx + r14 + 1]
    call evr_nibble
    test eax, eax
    js 8f
    or eax, r15d
    mov rcx, r14
    shr rcx, 1
    mov [r12 + rcx], al
    add r14, 2
    cmp r14, r13
    jb 1b
    xor eax, eax
    EPILOGUE
8:  mov rax, -EV_USAGE
    EPILOGUE
evr_nibble:
    mov eax, edi
    sub eax, '0'
    cmp eax, 9
    jbe 1f
    mov eax, edi
    sub eax, 'a'
    cmp eax, 5
    ja 8f
    add eax, 10
1:  ret
8:  mov rax, -1
    ret

# Exact argc10 early helper, before application initialization.
FN ext_validate_anchored_main
    PROLOGUE 304
    mov rbx, rsi
    mov r12, -1
    mov r13, -EV_USAGE
    xor r14d, r14d
    mov [rsp + 288], rdi
    mov rdi, rsp
    xor esi, esi
    mov edx, 288
    call memset
    mov rax, 0x00314c4156454852
    mov [rsp], rax
    mov dword ptr [rsp + 8], 1
    mov dword ptr [rsp + 12], EVR_SIZE
    cmp qword ptr [rsp + 288], 10
    jne .Levra_emit
    mov rdi, [rbx + 8]
    lea rsi, [rip + evr_option]
    call strcmp_eq
    test eax, eax
    jz .Levra_emit
    mov rdi, [rbx + 16]
    call evr_decimal
    test rdx, rdx
    jnz .Levra_emit
    test rax, rax
    js .Levra_emit
.ifndef WINDOWS
    cmp rax, 0x7fffffff
    ja .Levra_emit
.endif
    mov r12, rax
    mov rdi, [rbx + 48]
    call evr_decimal
    test rdx, rdx
    jnz .Levra_close
    test rax, rax
    jz .Levra_close
    mov [rsp + EVR_tag], rax
    mov rdi, [rbx + 56]
    call evr_decimal
    test rdx, rdx
    jnz .Levra_close
    test rax, rax
    jz .Levra_close
    mov [rsp + EVR_tag + 8], rax
    mov rdi, [rbx + 64]
    lea rsi, [rsp + EVR_tag + 16]
    mov edx, 32
    call evr_unhex
    test rax, rax
    jnz .Levra_close
    mov rdi, r12
    lea rsi, [rsp + EVR_tag + 32]
    call ext_root_identity
    test rax, rax
    js .Levra_error
    xor r15d, r15d
    mov rdi, [rbx + 72]
    cmp word ptr [rdi], '-'
    je 1f
    lea rsi, [rsp + 256]
    mov edx, 64
    call evr_unhex
    test rax, rax
    jnz .Levra_close
    lea r15, [rsp + 256]
1:  mov rdi, r12
    mov rsi, [rbx + 24]
    mov rdx, [rbx + 32]
    mov rcx, [rbx + 40]
    mov r8, r15
    lea r9, [rsp + 192]
    call ext_validate_from_root_result
    mov r13, rax
    mov r14, rdx
    jmp .Levra_close
.Levra_error:
    mov r13, rax
.Levra_close:
    mov rdi, r12
    mov r12, -1
    call ext_root_close
    test r14, r14
    jnz 2f
    mov r14, rax
2:  test r13, r13
    jnz .Levra_emit
    mov r13, r14
.Levra_emit:
    mov [rsp + EVR_primary], r13
    mov [rsp + EVR_secondary], r14
    test r13, r13
    jnz 3f
    test r14, r14
    jnz 3f
    lea rdi, [rsp + EVR_tree]
    lea rsi, [rsp + 192]
    mov edx, 64
    call memcpy
3:  mov edi, 1
    mov rsi, rsp
    mov edx, EVR_SIZE
    call write_all
    test rax, rax
    jnz 4f
    xor eax, eax
    test r13, r13
    setnz al
    EPILOGUE
4:  mov eax, 1
    EPILOGUE
.section .rodata
evr_option: .asciz "--validate-extension-anchored"
