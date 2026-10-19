# Separate source-only legacy receipt and isolated anchored helper.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatewire.inc"
.text
FN ext_validate_legacy_receipt_check
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r15, r8
    cmp rsi, EVR_SIZE
    jne .Lelvr_bad
    mov rax, 0x314347454c4852
    cmp [rbx], rax
    jne .Lelvr_bad
    cmp dword ptr [rbx + 8], 1
    jne .Lelvr_bad
    cmp dword ptr [rbx + 12], EVR_SIZE
    jne .Lelvr_bad
    xor ecx, ecx
1:  cmp qword ptr [rbx + EVR_reserved + rcx], 0
    jne .Lelvr_bad
    add rcx, 8
    cmp rcx, 32
    jb 1b
    lea rdi, [rbx + EVR_tag]
    mov rsi, r12
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lelvr_bad
    xor ecx, ecx
.Lelvr_no_tree:
    cmp qword ptr [rbx + EVR_tree + rcx], 0
    jne .Lelvr_bad
    add rcx, 8
    cmp rcx, 32
    jb .Lelvr_no_tree
    mov rax, [rbx + EVR_primary]
    mov rdx, [rbx + EVR_secondary]
    test rax, rax
    jg .Lelvr_bad
    cmp rax, -4095
    jl .Lelvr_bad
    test rdx, rdx
    jg .Lelvr_bad
    cmp rdx, -4095
    jl .Lelvr_bad
    mov rcx, rax
    or rcx, rdx
    jz .Lelvr_success
    xor ecx, ecx
2:  cmp qword ptr [rbx + EVR_tree + rcx], 0
    jne .Lelvr_bad
    add rcx, 8
    cmp rcx, 64
    jb 2b
    test rax, rax
    jnz .Lelvr_done
    mov rax, rdx
.Lelvr_done:
    EPILOGUE
.Lelvr_success:
    test r13, r13
    jz 4f
    lea rdi, [rbx + EVR_source]
    mov rsi, r13
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lelvr_bad
4:  mov rdi, r15
    lea rsi, [rbx + EVR_source]
    mov edx, 32
    call memcpy
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lelvr_bad:
    mov rax, -EV_CHANGED
    xor edx, edx
    EPILOGUE

# Strict full unsigned decimal, overflow checked before multiply. RDX=0 or usage.
elvr_decimal:
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
elvr_unhex:
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
    call elvr_nibble
    test eax, eax
    js 8f
    mov r15d, eax
    shl r15d, 4
    movzx edi, byte ptr [rbx + r14 + 1]
    call elvr_nibble
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
elvr_nibble:
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
FN ext_validate_legacy_anchored_main
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
    mov rax, 0x314347454c4852
    mov [rsp], rax
    mov dword ptr [rsp + 8], 1
    mov dword ptr [rsp + 12], EVR_SIZE
    cmp qword ptr [rsp + 288], 10
    jne .Lelvra_emit
    mov rdi, [rbx + 8]
    lea rsi, [rip + elvr_option]
    call strcmp_eq
    test eax, eax
    jz .Lelvra_emit
    mov rdi, [rbx + 16]
    call elvr_decimal
    test rdx, rdx
    jnz .Lelvra_emit
    test rax, rax
    js .Lelvra_emit
.ifndef WINDOWS
    cmp rax, 0x7fffffff
    ja .Lelvra_emit
.endif
    mov r12, rax
    mov rdi, [rbx + 48]
    call elvr_decimal
    test rdx, rdx
    jnz .Lelvra_close
    test rax, rax
    jz .Lelvra_close
    mov [rsp + EVR_tag], rax
    mov rdi, [rbx + 56]
    call elvr_decimal
    test rdx, rdx
    jnz .Lelvra_close
    test rax, rax
    jz .Lelvra_close
    mov [rsp + EVR_tag + 8], rax
    mov rdi, [rbx + 64]
    lea rsi, [rsp + EVR_tag + 16]
    mov edx, 32
    call elvr_unhex
    test rax, rax
    jnz .Lelvra_close
    mov rdi, r12
    lea rsi, [rsp + EVR_tag + 32]
    call ext_root_identity
    test rax, rax
    js .Lelvra_error
    xor r15d, r15d
    mov rdi, [rbx + 72]
    cmp word ptr [rdi], '-'
    je 1f
    lea rsi, [rsp + 256]
    mov edx, 64
    call elvr_unhex
    test rax, rax
    jnz .Lelvra_close
    lea r15, [rsp + 256]
1:  call ext_store_job_legacy_child_context
    test rax, rax
    js .Lelvra_error
    mov rdi, r12
    mov rsi, [rbx + 24]
    mov rdx, [rbx + 32]
    mov rcx, [rbx + 40]
    mov r8, r15
    lea r9, [rsp + 192]
    call ext_validate_legacy_from_root_result
    mov r13, rax
    mov r14, rdx
    jmp .Lelvra_close
.Lelvra_error:
    mov r13, rax
.Lelvra_close:
    mov rdi, r12
    mov r12, -1
    call ext_root_close
    test r14, r14
    jnz 2f
    mov r14, rax
2:  test r13, r13
    jnz .Lelvra_emit
    mov r13, r14
.Lelvra_emit:
    mov [rsp + EVR_primary], r13
    mov [rsp + EVR_secondary], r14
    test r13, r13
    jnz 3f
    test r14, r14
    jnz 3f
    lea rdi, [rsp + EVR_source]
    lea rsi, [rsp + 192]
    mov edx, 32
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
elvr_option: .asciz "--validate-legacy-anchored"

.text
FN prep_legacy_decimal
    jmp elvr_decimal
FN prep_legacy_unhex
    jmp elvr_unhex
