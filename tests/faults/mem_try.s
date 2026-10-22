# Linked only against a private allocator copy with its state exported.
.include "rhun.inc"
.bss
.p2align 3
mtf_fail_map: .quad 0
mtf_calls: .quad 0
mtf_call_before: .quad 0
mtf_live: .quad 0
mtf_lists: .zero 96
mtf_chunk: .quad 0
mtf_end: .quad 0
mtf_snapshot_live: .quad 0
mtf_ptrs: .zero 16 * 8
.text
FN os_map_try
    inc qword ptr [rip + mtf_calls]
    cmp qword ptr [rip + mtf_fail_map], 0
    je mtf_real_os_map_try
    xor eax, eax
    ret
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne mtf_fail
    # Windows entry may already own allocations. Keep them valid but force this test's
    # next small allocation to require a new chunk; private state is never product state.
    mov rax, [rip + g_mem_live]
    mov [rip + mtf_live], rax
    lea rdi, [rip + free_lists]
    xor esi, esi
    mov edx, 96
    call memset
    mov qword ptr [rip + chunk_ptr], 0
    mov qword ptr [rip + chunk_end], 0
    mov qword ptr [rip + mtf_calls], 0
    call mtf_snapshot
    mov rax, [rip + g_argv]
    mov r12, [rax + 8]
    mov rdi, r12
    lea rsi, [rip + mtf_small]
    call strcmp_eq
    test eax, eax
    jnz .Lmtf_small
    mov rdi, r12
    lea rsi, [rip + mtf_chunk_mode]
    call strcmp_eq
    test eax, eax
    jnz .Lmtf_chunk
    mov rdi, r12
    lea rsi, [rip + mtf_large]
    call strcmp_eq
    test eax, eax
    jnz .Lmtf_large
    mov qword ptr [rip + mtf_fail_map], 1
    mov rdi, r12
    lea rsi, [rip + mtf_fatal_small]
    call strcmp_eq
    test eax, eax
    jz 1f
    mov edi, 16
    call mem_alloc
    jmp mtf_fail
1:  mov rdi, r12
    lea rsi, [rip + mtf_fatal_large]
    call strcmp_eq
    test eax, eax
    jz 2f
    mov edi, 65521
    call mem_alloc
    jmp mtf_fail
2:  mov rdi, r12
    lea rsi, [rip + mtf_fatal_map]
    call strcmp_eq
    test eax, eax
    jz mtf_fail
    mov edi, 4096
    call os_map
    jmp mtf_fail
.Lmtf_small:
    mov qword ptr [rip + mtf_fail_map], 1
    mov edi, 16
    call mem_alloc_try
    test rax, rax
    jnz mtf_fail
    call mtf_same
    test eax, eax
    jz mtf_fail
    cmp qword ptr [rip + mtf_calls], 1
    jne mtf_fail
    mov qword ptr [rip + mtf_fail_map], 0
    mov edi, 16
    call mem_alloc_try
    test rax, rax
    jz mtf_fail
    mov r15, rax
    mov rdi, rax
    mov esi, 0xa5
    mov edx, 16
    call memset
    mov rdi, r15
    call mem_free
    mov qword ptr [rip + mtf_fail_map], 1
    mov rax, [rip + mtf_calls]
    mov [rip + mtf_call_before], rax
    mov edi, 16
    call mem_alloc_try
    test rax, rax
    jz mtf_fail
    mov r15, rax
    call mtf_zero
    test eax, eax
    jz mtf_fail
    mov rax, [rip + mtf_calls]
    cmp rax, [rip + mtf_call_before]
    jne mtf_fail
    mov rdi, r15
    call mem_free
    jmp mtf_pass
.Lmtf_chunk:
    xor r12d, r12d
1:  mov edi, 65520
    call mem_alloc_try
    test rax, rax
    jz mtf_fail
    lea rcx, [rip + mtf_ptrs]
    mov [rcx + r12*8], rax
    inc r12
    cmp r12, 16
    jb 1b
    call mtf_snapshot
    mov qword ptr [rip + mtf_fail_map], 1
    mov edi, 16
    call mem_alloc_try
    test rax, rax
    jnz mtf_fail
    call mtf_same
    test eax, eax
    jz mtf_fail
    mov rdi, [rip + mtf_ptrs + 15*8]
    mov esi, 0xa5
    mov edx, 65520
    call memset
    mov rdi, [rip + mtf_ptrs + 15*8]
    call mem_free
    mov rax, [rip + mtf_calls]
    mov [rip + mtf_call_before], rax
    mov edi, 65520
    call mem_alloc_try
    test rax, rax
    jz mtf_fail
    mov [rip + mtf_ptrs + 15*8], rax
    mov r15, rax
    call mtf_zero
    test eax, eax
    jz mtf_fail
    mov rax, [rip + mtf_calls]
    cmp rax, [rip + mtf_call_before]
    jne mtf_fail
    xor r12d, r12d
2:  lea rax, [rip + mtf_ptrs]
    mov rdi, [rax + r12*8]
    call mem_free
    inc r12
    cmp r12, 16
    jb 2b
    jmp mtf_pass
.Lmtf_large:
    mov qword ptr [rip + mtf_fail_map], 1
    mov edi, 65521
    call mem_alloc_try
    test rax, rax
    jnz mtf_fail
    call mtf_same
    test eax, eax
    jz mtf_fail
    cmp qword ptr [rip + mtf_calls], 1
    jne mtf_fail
    mov qword ptr [rip + mtf_fail_map], 0
    mov edi, 65521
    call mem_alloc_try
    test rax, rax
    jz mtf_fail
    mov r15, rax
    call mtf_zero
    test eax, eax
    jz mtf_fail
    mov rdi, r15
    call mem_free
mtf_pass:
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + mtf_live]
    jne mtf_fail
    lea rdi, [rip + mtf_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
mtf_fail:
    mov eax, 90
    EPILOGUE
mtf_snapshot:
    PROLOGUE
    lea rdi, [rip + mtf_lists]
    lea rsi, [rip + free_lists]
    mov edx, 96
    call memcpy
    mov rax, [rip + chunk_ptr]
    mov [rip + mtf_chunk], rax
    mov rax, [rip + chunk_end]
    mov [rip + mtf_end], rax
    mov rax, [rip + g_mem_live]
    mov [rip + mtf_snapshot_live], rax
    EPILOGUE
mtf_same:
    PROLOGUE
    lea rdi, [rip + mtf_lists]
    lea rsi, [rip + free_lists]
    mov edx, 96
    call memeq
    test eax, eax
    jz 8f
    mov rax, [rip + chunk_ptr]
    cmp rax, [rip + mtf_chunk]
    jne 8f
    mov rax, [rip + chunk_end]
    cmp rax, [rip + mtf_end]
    jne 8f
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + mtf_snapshot_live]
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
mtf_zero:
    PROLOGUE
    mov rdi, r15
    call mem_capacity
    xor ecx, ecx
1:  cmp rcx, rax
    jae 2f
    cmp byte ptr [r15 + rcx], 0
    jne 8f
    inc rcx
    jmp 1b
2:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
.section .rodata
mtf_small: .asciz "small"
mtf_chunk_mode: .asciz "chunk"
mtf_large: .asciz "large"
mtf_fatal_small: .asciz "fatal-small"
mtf_fatal_large: .asciz "fatal-large"
mtf_fatal_map: .asciz "fatal-map"
mtf_ok: .asciz "ok allocation faults\n"
