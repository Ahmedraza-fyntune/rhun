.include "rhun.inc"
.globl mu_fail_unmap, mu_unmap_calls
.bss
.p2align 3
mu_fail_map: .quad 0
mu_map_calls: .quad 0
mu_fail_unmap: .quad 0
mu_unmap_calls: .quad 0
mu_baseline: .quad 0
mu_header: .quad 0
mu_poison_map: .quad 0
mu_bump_first: .quad 0
mu_callee_bad: .quad 0
.text
FN os_map_try
    PROLOGUE
    inc qword ptr [rip + mu_map_calls]
    cmp qword ptr [rip + mu_fail_map], 0
    jne 8f
    mov rbx, rdi
    call mu_map_real
    test rax, rax
    jz 9f
    cmp qword ptr [rip + mu_poison_map], 0
    je 9f
    mov r12, rax
    mov rdi, rax
    mov esi, 0xa5
    mov rdx, rbx
    call memset
    mov rax, r12
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne .Lmu_fail
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    cmp byte ptr [rax + 1], 0
    jne .Lmu_fail
    movzx eax, byte ptr [rax]
    sub eax, '0'
    cmp eax, 7
    ja .Lmu_fail
    mov r14d, eax
    mov rax, [rip + g_mem_live]
    mov [rip + mu_baseline], rax
    mov qword ptr [rip + mu_map_calls], 0
    mov qword ptr [rip + mu_unmap_calls], 0
    test r14d, r14d
    jz .Lmu_classes
    cmp r14d, 3
    je .Lmu_unmap
    cmp r14d, 4
    je .Lmu_bounds
    cmp r14d, 6
    jae .Lmu_poison
    # Private allocator state only. Existing startup allocations stay valid.
    lea rdi, [rip + free_lists]
    xor esi, esi
    mov edx, 96
    call memset
    mov qword ptr [rip + chunk_ptr], 0
    mov qword ptr [rip + chunk_end], 0
    mov qword ptr [rip + mu_map_calls], 0
    mov qword ptr [rip + mu_fail_map], 1
    mov edi, 16
    cmp r14d, 1
    je 1f
    mov edi, 65521
1:  mov rbx, rdi
    cmp r14d, 5
    jne 8f
    call mu_fatal_checked
    jmp .Lmu_fail
8:  call mu_raw_checked
    test rax, rax
    jnz .Lmu_fail
    cmp qword ptr [rip + mu_map_calls], 1
    jne .Lmu_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + mu_baseline]
    jne .Lmu_fail
    cmp qword ptr [rip + chunk_ptr], 0
    jne .Lmu_fail
    cmp qword ptr [rip + chunk_end], 0
    jne .Lmu_fail
    lea rsi, [rip + free_lists]
    xor ecx, ecx
2:  cmp qword ptr [rsi + rcx*8], 0
    jne .Lmu_fail
    inc rcx
    cmp rcx, 12
    jb 2b
    mov qword ptr [rip + mu_fail_map], 0
    mov rdi, rbx
    call mu_raw_checked
    test rax, rax
    jz .Lmu_fail
    mov rdi, rax
    call prep_cleanup_free
    test rax, rax
    jnz .Lmu_fail
    cmp rdx, 1
    jne .Lmu_fail
    jmp .Lmu_pass
.Lmu_classes:
    xor r12d, r12d
    mov r14, 0x123456789abcdef0
.Lmu_class:
    mov ebx, 32
    mov ecx, r12d
    shl rbx, cl
    sub rbx, 16
    mov rdi, rbx
    call mu_fatal_checked
    test rax, rax
    jz .Lmu_fail
    mov r15, rax
    mov rdi, rax
    mov esi, 0xa5
    mov rdx, rbx
    call memset
    mov rdi, r15
    call mem_free
    mov rdi, rbx
    call mu_raw_checked
    cmp rax, r15
    jne .Lmu_fail
    mov rax, 0x123456789abcdef0
    cmp r14, rax
    jne .Lmu_fail
    cmp [r15 - 16], r12
    jne .Lmu_fail
    cmp [r15 - 8], rbx
    jne .Lmu_fail
    mov rdi, r15
    call mem_capacity
    cmp rax, rbx
    jne .Lmu_fail
    mov rax, [rip + mu_baseline]
    inc rax
    cmp [rip + g_mem_live], rax
    jne .Lmu_fail
    # Free-list linkage may replace the first8 bytes. Every other byte must survive.
    mov ecx, 8
3:  cmp byte ptr [r15 + rcx], 0xa5
    jne .Lmu_fail
    inc rcx
    cmp rcx, rbx
    jb 3b
    mov rdi, r15
    call mem_free
    mov rdi, rbx
    call mu_fatal_checked
    cmp rax, r15
    jne .Lmu_fail
    xor ecx, ecx
4:  cmp byte ptr [r15 + rcx], 0
    jne .Lmu_fail
    inc rcx
    cmp rcx, rbx
    jb 4b
    mov rdi, r15
    mov esi, 0xa5
    mov rdx, rbx
    call memset
    mov rdi, r15
    call mem_free
    mov rdi, rbx
    call mu_zero_checked
    cmp rax, r15
    jne .Lmu_fail
    xor ecx, ecx
5:  cmp byte ptr [r15 + rcx], 0
    jne .Lmu_fail
    inc rcx
    cmp rcx, rbx
    jb 5b
    mov rdi, r15
    call mem_free
    inc r12
    cmp r12, 12
    jb .Lmu_class
    # Large raw allocation still has the ordinary mapping/header/free contract.
    mov edi, 65521
    call mu_raw_checked
    test rax, rax
    jz .Lmu_fail
    mov r15, rax
    cmp qword ptr [r15 - 8], 65521
    jne .Lmu_fail
    mov rax, [r15 - 16]
    cmp rax, 65537
    jb .Lmu_fail
    test eax, 4095
    jnz .Lmu_fail
    mov rdi, r15
    call prep_cleanup_free
    test rax, rax
    jnz .Lmu_fail
    cmp rdx, 1
    jne .Lmu_fail
    jmp .Lmu_pass
.Lmu_unmap:
    mov edi, 65521
    call mu_raw_checked
    test rax, rax
    jz .Lmu_fail
    mov r15, rax
    mov rax, [r15 - 16]
    mov [rip + mu_header], rax
    mov byte ptr [r15], 0x63
    mov qword ptr [rip + mu_fail_unmap], 1
    mov rdi, r15
    call prep_cleanup_free
    cmp rax, -5
    jne .Lmu_fail
    test rdx, rdx
    jnz .Lmu_fail
    cmp qword ptr [rip + mu_unmap_calls], 1
    jne .Lmu_fail
    mov rax, [rip + mu_header]
    cmp [r15 - 16], rax
    jne .Lmu_fail
    cmp qword ptr [r15 - 8], 65521
    jne .Lmu_fail
    cmp byte ptr [r15], 0x63
    jne .Lmu_fail
    mov rax, [rip + mu_baseline]
    inc rax
    cmp [rip + g_mem_live], rax
    jne .Lmu_fail
    mov rdi, r15
    call prep_cleanup_free
    test rax, rax
    jnz .Lmu_fail
    cmp rdx, 1
    jne .Lmu_fail
    cmp qword ptr [rip + mu_unmap_calls], 2
    jne .Lmu_fail
    jmp .Lmu_pass
 .Lmu_poison:
    lea rdi, [rip + free_lists]
    xor esi, esi
    mov edx, 96
    call memset
    mov qword ptr [rip + chunk_ptr], 0
    mov qword ptr [rip + chunk_end], 0
    mov qword ptr [rip + mu_poison_map], 1
    mov ebx, 16
    cmp r14d, 6
    je 1f
    mov ebx, 65521
1:  mov rdi, rbx
    call mu_raw_checked
    test rax, rax
    jz .Lmu_fail
    mov r15, rax
    mov [rip + mu_bump_first], rax
    mov rdi, rax
    call mem_capacity
    mov r12, rax
    xor ecx, ecx
2:  cmp byte ptr [r15 + rcx], 0xa5
    jne .Lmu_fail
    inc rcx
    cmp rcx, r12
    jb 2b
    cmp qword ptr [rip + mu_map_calls], 1
    jne .Lmu_fail
    cmp r14d, 7
    je 4f
    # Keep the first block live, forcing another bump within the poisoned owned chunk.
    mov edi, 16
    call mu_raw_checked
    lea rcx, [r15 + 32]
    cmp rax, rcx
    jne .Lmu_fail
    mov r15, rax
    xor ecx, ecx
3:  cmp byte ptr [r15 + rcx], 0xa5
    jne .Lmu_fail
    inc rcx
    cmp rcx, 16
    jb 3b
    cmp qword ptr [rip + mu_map_calls], 1
    jne .Lmu_fail
    mov rdi, r15
    call prep_cleanup_free
    test rax, rax
    jnz .Lmu_fail
    cmp rdx, 1
    jne .Lmu_fail
4:  mov rdi, [rip + mu_bump_first]
    call prep_cleanup_free
    test rax, rax
    jnz .Lmu_fail
    cmp rdx, 1
    jne .Lmu_fail
    jmp .Lmu_pass
.Lmu_bounds:
    mov rdi, 1 << 40
    call mu_raw_checked
    test rax, rax
    jnz .Lmu_fail
    mov rdi, -1
    call mu_raw_checked
    test rax, rax
    jnz .Lmu_fail
    cmp qword ptr [rip + mu_map_calls], 0
    jne .Lmu_fail
.Lmu_pass:
    cmp qword ptr [rip + mu_callee_bad], 0
    jne .Lmu_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + mu_baseline]
    jne .Lmu_fail
    lea rdi, [rip + .Lmu_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lmu_fail:
    mov eax, 73
    EPILOGUE
FN mu_raw_checked
    lea rax, [rip + mem_alloc_uninit_try]
    jmp .Lmu_checked
FN mu_zero_checked
    lea rax, [rip + mem_alloc_try]
    jmp .Lmu_checked
FN mu_fatal_checked
    lea rax, [rip + mem_alloc]
.Lmu_checked:
    PROLOGUE
    mov rbx, 0x1234567800000001
    mov r12, 0x1234567800000002
    mov r13, 0x1234567800000003
    mov r14, 0x1234567800000004
    mov r15, 0x1234567800000005
    call rax
    mov r10, 0x1234567800000001
    cmp rbx, r10
    jne 8f
    mov r10, 0x1234567800000002
    cmp r12, r10
    jne 8f
    mov r10, 0x1234567800000003
    cmp r13, r10
    jne 8f
    mov r10, 0x1234567800000004
    cmp r14, r10
    jne 8f
    mov r10, 0x1234567800000005
    cmp r15, r10
    je 9f
8:  mov qword ptr [rip + mu_callee_bad], 1
9:  EPILOGUE
.section .rodata
.Lmu_ok: .asciz "ok mem-uninit\n"
