# Single-use isolated managed validator. No UI, extension initialization or process execution.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
FN ext_validate
    mov r8, rcx
    xor ecx, ecx
FN ext_validate_bound
    PROLOGUE 96
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    call ext_root_open
    test rax, rax
    js .Levv_done
    mov [rsp + 64], rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    mov r9, rsp
    call ext_validate_from_root_result
    mov r12, rax
    mov r13, rdx
    mov rdi, [rsp + 64]
    call ext_root_close
    test rax, rax
    jns 1f
    test r13, r13
    jnz 1f
    mov r13, rax
1:  test r12, r12
    jnz 2f
    mov r12, r13
2:  test r12, r12
    jnz 3f
    mov rdi, r15
    mov rsi, rsp
    mov edx, 32
    call memcpy
3:  mov rax, r12
    mov rdx, r13
.Levv_done:
    EPILOGUE

FN ext_validate_from_root
    mov r9, r8
    xor r8d, r8d
FN ext_validate_from_root_bound
    PROLOGUE 80
    mov rbx, r9
    mov r9, rsp
    call ext_validate_from_root_result
    mov r12, rax
    mov r13, rdx
    test rax, rax
    jnz 1f
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 32
    call memcpy
1:  mov rax, r12
    mov rdx, r13
    EPILOGUE

# Fully prepared manifest/assets stay live until the matching complete tree is accepted.
# root borrowed, DIR, owner, name, expectedSourceOr0, outResult64.
FN ext_validate_from_root_result
    PROLOGUE 160
    mov [rsp + 64], rdi
    mov [rsp + 72], r8
    mov [rsp + 80], r9
    mov r8, -1
    call ext_prepare_begin
    test rax, rax
    jz .Levfr_begin_error
    mov rbx, rax
1:  mov rdi, rbx
    call ext_prepare_step
    cmp rax, 1
    je 1b
    test rax, rax
    jnz .Levfr_release
    mov rdi, rbx
    lea rsi, [rsp + 32]
    call ext_prepare_source_commitment
    test rax, rax
    jnz .Levfr_release
    mov rsi, [rsp + 72]
    test rsi, rsi
    jz 2f
    lea rdi, [rsp + 32]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Levfr_changed
2:  mov rdi, [rsp + 64]
    call ext_root_reopen_dir
    test rax, rax
    js .Levfr_open_error
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    mov rdx, [rbx + EP_sources + VEC_ptr]
    mov rcx, [rbx + EP_sources + VEC_len]
    call ext_validate_tree_bound
    mov r13, rax
    mov r14, rdx
    mov rdi, r12
    call ext_root_close
    test r14, r14
    jnz 3f
    mov r14, rax
3:  mov rdi, rbx
    mov rsi, r14
    call prep_note_cleanup
    mov rax, r13
.Levfr_release:
    mov r12, rax
    mov rdi, rbx
    call ext_prepare_release
    mov r13, rax
    test r12, r12
    jnz 4f
    mov r12, r13
4:  test r12, r12
    jnz 5f
    mov rdi, [rsp + 80]
    mov rsi, rsp
    mov edx, 64
    call memcpy
5:  mov rax, r12
    mov rdx, r13
    EPILOGUE
.Levfr_changed:
    mov rax, -EV_CHANGED
    jmp .Levfr_release
.Levfr_open_error:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
    mov rax, r12
    jmp .Levfr_release
.Levfr_begin_error:
    mov rax, rdx
    mov rdx, rcx
    EPILOGUE

# Exact lowercase hexadecimal source input, no partial acceptance.
FN ext_validate_unhex
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, 64
    call ext_root_length
    cmp rax, 64
    jne 8f
    xor r13d, r13d
1:  movzx edi, byte ptr [rbx + r13]
    call evv_nibble
    test eax, eax
    js 8f
    mov r14d, eax
    shl r14d, 4
    movzx edi, byte ptr [rbx + r13 + 1]
    call evv_nibble
    test eax, eax
    js 8f
    or eax, r14d
    mov rcx, r13
    shr rcx, 1
    mov [r12 + rcx], al
    add r13, 2
    cmp r13, 64
    jb 1b
    xor eax, eax
    EPILOGUE
8:  mov rax, -EV_USAGE
    EPILOGUE
evv_nibble:
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

FN ext_validate_hex
    mov r8, rdi
    mov r9, rsi
    lea r10, [rip + evv_hex]
    xor ecx, ecx
1:  movzx eax, byte ptr [r9 + rcx]
    mov edx, eax
    shr eax, 4
    and edx, 15
    mov al, [r10 + rax]
    mov dl, [r10 + rdx]
    mov [r8 + rcx*2], al
    mov [r8 + rcx*2 + 1], dl
    inc rcx
    cmp rcx, 32
    jb 1b
    mov eax, 64
    ret

# One bounded ASCII result line and a process exit status. No untrusted bytes are printed.
FN ext_validate_print
    PROLOGUE 96
    mov rbx, rdi
    test rbx, rbx
    jnz 1f
    mov word ptr [rsp], 0x6b6f # ok
    mov byte ptr [rsp + 2], ' '
    lea rdi, [rsp + 3]
    call ext_validate_hex
    mov byte ptr [rsp + 67], 10
    mov r12d, 68
    jmp 2f
1:  mov dword ptr [rsp], 0x6f727265 # erro
    mov word ptr [rsp + 4], 0x2072 # r space
    mov rsi, rbx
    neg rsi
    lea rdi, [rsp + 6]
    call fmt_u64
    mov byte ptr [rdi], 10
    lea r12, [rax + 7]
2:  mov edi, 1
    mov rsi, rsp
    mov rdx, r12
    call write_all
    test rax, rax
    jnz 3f
    xor eax, eax
    test rbx, rbx
    setnz al
    EPILOGUE
3:  mov eax, 1
    EPILOGUE

FN ext_validate_main
    PROLOGUE 64
    mov rbx, rsi
    xor r12d, r12d
    cmp rdi, 5
    je 1f
    cmp rdi, 6
    jne .Levm_usage
    mov rdi, [rbx + 40]
    lea rsi, [rsp + 32]
    call ext_validate_unhex
    test rax, rax
    jnz .Levm_usage
    lea r12, [rsp + 32]
1:  mov rdi, [rbx + 8]
    lea rsi, [rip + evv_option]
    call strcmp_eq
    test eax, eax
    jz .Levm_usage
    mov rdi, [rbx + 16]
    mov rsi, [rbx + 24]
    mov rdx, [rbx + 32]
    mov rcx, r12
    mov r8, rsp
    call ext_validate_bound
    mov rdi, rax
    mov rsi, rsp
    call ext_validate_print
    EPILOGUE
.Levm_usage:
    mov rdi, -EV_USAGE
    xor esi, esi
    call ext_validate_print
    EPILOGUE
.section .rodata
evv_hex: .ascii "0123456789abcdef"
evv_option: .asciz "--validate-extension"
