.ifndef NCF_MODE
.equ NCF_MODE, 12
.endif
.include "rhun.inc"
.include "app/extstore.inc"
.bss
.p2align 3
ncu_target: .quad 0
ncu_fault: .quad 0
ncu_calls: .quad 0
.text
ncu_fail:
    mov edi, 73
    call sys_exit
FN ncu_munmap
    cmp rdi, [rip + ncu_target]
    jne 1f
    inc qword ptr [rip + ncu_calls]
    cmp qword ptr [rip + ncu_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN mem_alloc_try
    PROLOGUE
    mov rbx, rdi
.if NCF_MODE == 13
    cmp rdi, ESO_SIZE
    jne 1f
    cmp qword ptr [rip + ncu_target], 0
    je 1f
    xor eax, eax
    EPILOGUE
1:
.endif
    call ncu_real_alloc
    cmp rbx, ESR_SIZE * 256
    jne 2f
    test rax, rax
    jz 2f
    lea rcx, [rax - 16]
    mov [rip + ncu_target], rcx
2:  EPILOGUE
FN main
    PROLOGUE 32
    mov r15, [rip + g_mem_live]
    mov edi, ESW_HEADER_SIZE + ESR_SIZE*256 + ESO_SIZE
    call mem_alloc_try
    test rax, rax
    jz ncu_fail
    mov r12, rax
    mov rcx, 0x00524f5453454852
    mov [rax], rcx
    mov dword ptr [rax + 8], 1
    mov dword ptr [rax + 12], ESW_HEADER_SIZE
    mov dword ptr [rax + 16], 256
    mov dword ptr [rax + 20], 1
    mov qword ptr [rip + ncu_fault], 1
    mov qword ptr [rsp], 0x1234
    mov rdi, rax
    mov esi, ESW_HEADER_SIZE + ESR_SIZE*256 + ESO_SIZE
    lea rdx, [rax + 48]
    mov rcx, rsp
    call ext_store_snapshot_unpack_owned_try
    test rax, rax
    jnz ncu_fail
.if NCF_MODE == 13
    cmp rdx, -12
.else
    cmp rdx, -5
.endif
    jne ncu_fail
    cmp rcx, -5
    jne ncu_fail
    mov rbx, [rsp]
    cmp rbx, 4096
    jb ncu_fail
    lea rax, [r15 + 3]
    cmp [rip + g_mem_live], rax
    jne ncu_fail
    cmp qword ptr [rip + ncu_calls], 1
    jne ncu_fail
    mov rax, [rbx + ESS_entries + VEC_ptr]
    sub rax, 16
    cmp rax, [rip + ncu_target]
    jne ncu_fail
    cmp qword ptr [rax + 8], ESR_SIZE*256
    jne ncu_fail
    mov rdi, rbx
    call ext_store_snapshot_free_try
    cmp rax, -5
    jne ncu_fail
    test rdx, rdx
    jnz ncu_fail
    cmp qword ptr [rip + ncu_calls], 2
    jne ncu_fail
    mov qword ptr [rip + ncu_fault], 0
    mov rdi, rbx
    call ext_store_snapshot_free_try
    test rax, rax
    jnz ncu_fail
    cmp rdx, 1
    jne ncu_fail
    mov rdi, r12
    call prep_cleanup_free
    test rax, rax
    jnz ncu_fail
    cmp rdx, 1
    jne ncu_fail
    cmp [rip + g_mem_live], r15
    jne ncu_fail
    xor eax, eax
    EPILOGUE
