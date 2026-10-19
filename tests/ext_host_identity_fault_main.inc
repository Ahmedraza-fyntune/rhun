FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + hi_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + hi_charge], rax
    mov r12d, 1
.Lhif_attempt:
    mov [rip + hi_stage], r12
    mov [rip + hif_fail], r12
    mov qword ptr [rip + hif_calls], 0
    mov qword ptr [rip + hif_armed], 1
    call hif_new
    mov qword ptr [rip + hif_armed], 0
    test rax, rax
    jnz .Lhif_bad
    test rdx, rdx
    jns .Lhif_bad
    cmp [rip + hif_calls], r12
    jne .Lhif_bad
    call hif_drain
    inc r12
    cmp r12, 2
    jbe .Lhif_attempt
    mov qword ptr [rip + hi_stage], 3
    mov qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    call hif_new
    mov rbx, rax
    mov r13, rdx
    mov rax, [rip + hi_charge]
    mov [rip + prep_total_charge], rax
    test rbx, rbx
    jnz .Lhif_bad
    test r13, r13
    jns .Lhif_bad
    call hif_drain
    mov qword ptr [rip + hi_stage], 4
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_state]
    mov ecx, 2
    call ext_host_identity_create
    test rax, rax
    jnz .Lhif_bad
    cmp rdx, -22
    jne .Lhif_bad
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_empty]
    mov ecx, HI_DIAGNOSTIC
    call ext_host_identity_create
    test rax, rax
    jz .Lhif_bad
    test rdx, rdx
    jnz .Lhif_bad
    mov rbx, rax
    mov rdi, rax
    call ext_host_identity_state
    test rax, rax
    jz .Lhif_bad
    cmp byte ptr [rax], 0
    jne .Lhif_bad
    mov rdi, rbx
    call ext_host_identity_release
    test rax, rax
    jnz .Lhif_bad
    cmp rdx, 1
    jne .Lhif_bad
    call hif_drain
    xor eax, eax
    EPILOGUE
.Lhif_bad:
    mov rax, [rip + hi_stage]
    EPILOGUE
hif_new:
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hi_name]
    lea rdx, [rip + hi_state]
    xor ecx, ecx
    jmp ext_host_identity_create
hif_drain:
    PROLOGUE
    mov rbx, 64
1:  mov edi, 1
    lea rsi, [rip + hi_status]
    call ext_prepare_retire_step
    test rax, rax
    js .Lhif_abort
    cmp qword ptr [rip + hi_status], 1
    ja .Lhif_abort
    cmp qword ptr [rip + hi_status + 16], 0
    jne .Lhif_abort
    cmp qword ptr [rip + hi_status + 24], 0
    jne .Lhif_abort
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp .Lhif_abort
2:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + hi_live]
    jne .Lhif_abort
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + hi_charge]
    jne .Lhif_abort
    lea rdi, [rip + hi_owner]
    lea rsi, [rip + hif_expected_owner]
    call strcmp_eq
    test eax, eax
    jz .Lhif_abort
    lea rdi, [rip + hi_name]
    lea rsi, [rip + hif_expected_name]
    call strcmp_eq
    test eax, eax
    jz .Lhif_abort
    lea rdi, [rip + hi_state]
    lea rsi, [rip + hif_expected_state]
    call strcmp_eq
    test eax, eax
    jz .Lhif_abort
    EPILOGUE
.Lhif_abort:
    mov edi, 90
    jmp sys_exit
FN mem_alloc_try
    cmp qword ptr [rip + hif_armed], 1
    jne hif_real_alloc
    inc qword ptr [rip + hif_calls]
    mov rax, [rip + hif_calls]
    cmp rax, [rip + hif_fail]
    jne hif_real_alloc
    xor eax, eax
    ret
.bss
.p2align 3
hif_armed: .quad 0
hif_fail: .quad 0
hif_calls: .quad 0
.section .rodata
hif_expected_owner: .asciz "owner"
hif_expected_name: .asciz "name"
.ifdef WINDOWS
hif_expected_state: .asciz "C:/state"
.else
hif_expected_state: .asciz "/state"
.endif
.text
