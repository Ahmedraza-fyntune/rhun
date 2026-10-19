# Native failure results and allocator failures preserve precise outstanding ownership.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.globl rf_mode, rf_native_calls, rf_unmap_calls, rf_fail_unmap, rf_stat_fault
.p2align 3
rf_mode: .quad 0
rf_native_calls: .quad 0
rf_unmap_calls: .quad 0
rf_fail_unmap: .quad 0
rf_stat_fault: .quad 0
.text
FN main
    PROLOGUE 80
    mov rax, [rip + g_mem_live]
    mov [rsp + 64], rax
    cmp qword ptr [rip + g_argc], 2
    je .Lrf_args
    cmp qword ptr [rip + g_argc], 3
    jne .Lrf_bad
.Lrf_args:
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    movzx r15d, byte ptr [rax]
    sub r15d, '0'
    cmp r15, 1
    jb .Lrf_bad
    cmp r15, 7
    ja .Lrf_bad
    je .Lrf_owned_slot
    cmp r15, 3
    ja .Lrf_memory
    mov [rip + rf_mode], r15
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lrf_bad
    mov rbx, rax
    mov qword ptr [rbx + EO_lease], 123
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    mov rdi, rbx
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrf_bad
    mov r12, rax
    mov rdi, rbx
    call ext_prepare_owner_release
    cmp qword ptr [rip + rf_native_calls], 0
    jne .Lrf_bad
    mov rdi, r12
    call grammar_prepare_release_deferred
    cmp rdx, 1
    jne .Lrf_bad
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrf_bad
    cmp qword ptr [rip + rf_native_calls], 0
    jne .Lrf_bad
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrf_bad
    cmp qword ptr [rip + rf_native_calls], 1
    jne .Lrf_bad
    cmp qword ptr [rsp + 24], -5
    jne .Lrf_bad
    cmp r15, 3
    je .Lrf_drain
    cmp qword ptr [rsp + 16], 1
    jne .Lrf_bad
    cmp qword ptr [rbx + EO_lease], 123
    jne .Lrf_bad
    call ext_prepare_retire_charge
    cmp rax, 128
    jne .Lrf_bad
    call ext_prepare_retire_ack
    cmp rax, -16
    jne .Lrf_bad
    mov edi, 64
    call ext_prepare_retire_retry_known
    cmp r15, 2
    je .Lrf_unknown
    cmp rax, 1
    jne .Lrf_bad
    jmp .Lrf_drain
.Lrf_unknown:
    test rax, rax
    jnz .Lrf_bad
    mov edi, 64
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrf_bad
    cmp qword ptr [rsp], 0
    jne .Lrf_bad
    cmp qword ptr [rsp + 16], 1
    jne .Lrf_bad
    cmp qword ptr [rip + rf_native_calls], 1
    jne .Lrf_bad
    # Unknown disposition remains quarantined and charged through process exit.
    call ext_prepare_retire_charge
    cmp rax, 128
    jne .Lrf_bad
    mov rax, [rip + g_mem_live]
    sub rax, [rsp + 64]
    cmp rax, 1
    jne .Lrf_bad
    xor eax, eax
    EPILOGUE
.Lrf_owned_slot:
    cmp qword ptr [rip + g_argc], 3
    jne .Lrf_bad
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    call ext_root_open
    test rax, rax
    js .Lrf_bad
    mov rbx, rax
    mov qword ptr [rip + rf_native_calls], 0
    mov qword ptr [rip + rf_stat_fault], 1
    mov rdi, rbx
    mov rax, [rip + g_argv]
    mov rsi, [rax + 16]
    lea rdx, [rip + rf_owner]
    lea rcx, [rip + rf_name]
    call ext_prepare_alloc
    test rax, rax
    jnz .Lrf_bad
    cmp rdx, -5
    jne .Lrf_bad
    test rcx, rcx
    jnz .Lrf_bad
    cmp qword ptr [rip + rf_native_calls], 1
    jne .Lrf_bad
    mov rdi, rbx
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    jnz .Lrf_bad
    mov rdi, rbx
    call ext_root_close
    test rax, rax
    jnz .Lrf_bad
    cmp rdx, 1
    jne .Lrf_bad
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lrf_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 64]
    jne .Lrf_bad
    xor eax, eax
    EPILOGUE
.Lrf_memory:
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lrf_bad
    mov rbx, rax
    cmp r15, 6
    je .Lrf_orphan
    mov rdi, rbx
    call ext_prepare_owner_enable_deferred
    mov esi, PO_SIZE
    cmp r15, 5
    jne 1f
    mov esi, 100000
1:  mov rdi, rbx
    call prep_object_create
    test rax, rax
    jz .Lrf_bad
    mov r12, rax
    cmp r15, 4
    jne 2f
    mov rdi, r12
    mov esi, 100000
    call prep_owned_alloc
    test rax, rax
    jz .Lrf_bad
2:  mov r13, [r12 + PO_allocs]
    mov rdi, r13
    cmp r15, 5
    jne 3f
    sub rdi, RD_SIZE
3:  mov rax, [rdi - 16]
    mov [rsp + 48], rax
    mov [rsp + 56], rdi
    mov r14, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov [rsp + 40], rax
    mov rdi, rbx
    call ext_prepare_owner_release
    mov qword ptr [rip + rf_fail_unmap], 1
    mov rdi, r12
    call prep_owned_dispose
    cmp rdx, 1
    jne .Lrf_bad
    mov edi, 64
    mov rsi, rsp
    call ext_prepare_retire_step
    cmp rax, 1
    jne .Lrf_bad
    cmp qword ptr [rsp + 16], 1
    jne .Lrf_bad
    cmp [rip + g_mem_live], r14
    jne .Lrf_bad
    cmp [r12 + PO_allocs], r13
    jne .Lrf_bad
    mov rdi, [rsp + 56]
    mov rax, [rdi - 16]
    cmp rax, [rsp + 48]
    jne .Lrf_bad
    call ext_prepare_retire_charge
    cmp rax, [rsp + 40]
    jne .Lrf_bad
    cmp qword ptr [rip + rf_unmap_calls], 1
    jne .Lrf_bad
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne .Lrf_bad
    jmp .Lrf_drain
.Lrf_orphan:
    mov edi, 90016
    call mem_alloc_try
    test rax, rax
    jz .Lrf_bad
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + rf_source]
    mov edx, 5
    call memcpy
    lea rdi, [r12 + 5]
    mov ecx, 90000
4:  mov byte ptr [rdi], 97
    inc rdi
    dec rcx
    jnz 4b
    mov byte ptr [rdi], 10
    mov qword ptr [rip + rf_fail_unmap], 1
    mov rdi, r12
    mov esi, 90006
    mov rdx, rbx
    call grammar_parse_prepare
    test rax, rax
    jnz .Lrf_bad
    cmp rdx, -EV_BAD_GRAMMAR
    jne .Lrf_bad
    cmp rcx, -5
    jne .Lrf_bad
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call ext_prepare_owner_release
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne .Lrf_bad
.Lrf_drain:
    mov edi, 64
    mov rsi, rsp
    call ext_prepare_retire_step
    test rax, rax
    js .Lrf_bad
    cmp qword ptr [rsp + 16], 0
    jne .Lrf_bad
    cmp qword ptr [rsp + 24], -5
    jne .Lrf_bad
    test rax, rax
    jnz .Lrf_drain
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lrf_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 64]
    jne .Lrf_bad
    call ext_prepare_retire_ack
    test rax, rax
    jnz .Lrf_bad
    mov rdi, rsp
    call ext_prepare_retire_status
    cmp qword ptr [rsp + 24], 0
    jne .Lrf_bad
    xor eax, eax
    EPILOGUE
.Lrf_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
rf_owner: .asciz "fixture"
rf_name: .asciz "example"
rf_source: .ascii "name="
rf_source_end:
