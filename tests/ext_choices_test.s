# Counted native merge fixture, driven by ext-choices.py. No editor initialization.
.include "rhun.inc"
.include "app/extchoices.inc"
.section .rodata
.p2align 3
ect_registers:
    .quad 0x1234567887654321, 0x2234567887654322, 0x3234567887654323
    .quad 0x4234567887654324, 0x5234567887654325
ect_probe_section: .ascii "probe"
ect_probe_key: .ascii "k"
ect_probe_expected: .ascii "[probe]\nk=\n"
.bss
.p2align 3
ect_deltas: .zero EC_BATCH*EC_SIZE
ect_saved_deltas: .zero EC_BATCH*EC_SIZE
ect_probe: .zero EC_SIZE
ect_status: .quad 0
ect_live: .quad 0
ect_wire: .quad 0
ect_copy: .quad 0
ect_length: .quad 0
ect_fail_alloc: .quad 0
ect_allocations: .quad 0
.text
FN ect_alloc
    inc qword ptr [rip + ect_allocations]
    cmp qword ptr [rip + ect_fail_alloc], 0
    je 1f
    xor eax, eax
    ret
1:  jmp mem_alloc_try

# Check every preserved register on ordinary, rejected and faulted merges.
ect_call:
    PROLOGUE 32
    mov [rsp], rbp
    mov rbx, [rip + ect_registers]
    mov r12, [rip + ect_registers + 8]
    mov r13, [rip + ect_registers + 16]
    mov r14, [rip + ect_registers + 24]
    mov r15, [rip + ect_registers + 32]
    call ext_choices_merge
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    cmp rbp, [rsp]
    jne .Lect_fail
    cmp rbx, [rip + ect_registers]
    jne .Lect_fail
    cmp r12, [rip + ect_registers + 8]
    jne .Lect_fail
    cmp r13, [rip + ect_registers + 16]
    jne .Lect_fail
    cmp r14, [rip + ect_registers + 24]
    jne .Lect_fail
    cmp r15, [rip + ect_registers + 32]
    jne .Lect_fail
    mov rax, [rsp + 8]
    mov rdx, [rsp + 16]
    EPILOGUE

ect_edges:
    PROLOGUE
    xor edi, edi
    xor esi, esi
    call ext_choices_validate
    test rax, rax
    jnz .Lect_fail
    xor edi, edi
    mov esi, 1
    call ext_choices_validate
    cmp rax, -22
    jne .Lect_fail
    xor edi, edi
    mov esi, EC_LIMIT + 1
    call ext_choices_validate
    cmp rax, -27
    jne .Lect_fail
    lea rax, [rip + ect_probe_section]
    mov [rip + ect_probe + EC_section], rax
    mov qword ptr [rip + ect_probe + EC_seclen], 5
    lea rax, [rip + ect_probe_key]
    mov [rip + ect_probe + EC_key], rax
    mov qword ptr [rip + ect_probe + EC_keylen], 1
    # NULL empty input and NULL empty value must both be accepted.
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + ect_probe]
    mov ecx, 1
    call ect_call
    test rax, rax
    jz .Lect_fail
    mov rbx, rax
    cmp rdx, 11
    jne .Lect_fail
    cmp byte ptr [rax + 11], 0
    jne .Lect_fail
    mov rdi, rax
    lea rsi, [rip + ect_probe_expected]
    mov edx, 11
    call memeq
    test eax, eax
    jz .Lect_fail
    mov rdi, rbx
    call mem_free
    # A removal must ignore even an unreadable, oversized value span.
    mov qword ptr [rip + ect_probe + EC_remove], 1
    mov qword ptr [rip + ect_probe + EC_value], 1
    mov qword ptr [rip + ect_probe + EC_vallen], -1
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + ect_probe]
    mov ecx, 1
    call ect_call
    test rax, rax
    jz .Lect_fail
    test rdx, rdx
    jnz .Lect_fail
    cmp byte ptr [rax], 0
    jne .Lect_fail
    mov rdi, rax
    call mem_free
    xor edi, edi
    mov esi, 1
    lea rdx, [rip + ect_probe]
    mov ecx, 1
    call ect_call
    test rax, rax
    jnz .Lect_fail
    cmp rdx, -22
    jne .Lect_fail
    xor edi, edi
    xor esi, esi
    xor edx, edx
    mov ecx, 1
    call ect_call
    test rax, rax
    jnz .Lect_fail
    cmp rdx, -22
    jne .Lect_fail
    mov qword ptr [rip + ect_allocations], 0
    EPILOGUE

FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 2
    jne .Lect_fail
    mov rax, [rip + g_mem_live]
    mov [rip + ect_live], rax
    call ect_edges
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, 8*EC_LIMIT
    call file_read_limited_try
    test rax, rax
    jz .Lect_fail
    mov [rip + ect_wire], rax
    mov [rip + ect_length], rdx
    mov rdi, rax
    mov rsi, rdx
    call mem_dup_try
    test rax, rax
    jz .Lect_fail
    mov [rip + ect_copy], rax
    mov rbx, [rip + ect_wire]
    mov r15, [rip + ect_length]
    cmp r15, 24
    jb .Lect_fail
    add r15, rbx
    mov r12, [rbx]
    mov r13, [rbx + 8]
    mov rax, [rbx + 16]
    mov [rip + ect_fail_alloc], rax
    lea r14, [rbx + 24]
    mov [rsp], r14
    mov rax, r15
    sub rax, r14
    cmp r12, rax
    ja .Lect_fail
    add r14, r12
    mov qword ptr [rsp + 8], 0
    cmp r13, EC_BATCH
    ja .Lect_call                # API must reject count before reading any records.
.Lect_decode:
    mov rax, [rsp + 8]
    cmp rax, r13
    jae .Lect_call
    cmp rax, EC_BATCH
    jae .Lect_call
    mov rdx, r15
    sub rdx, r14
    cmp rdx, 32
    jb .Lect_fail
    imul rax, rax, EC_SIZE
    lea rdi, [rip + ect_deltas]
    add rdi, rax
    mov rax, [r14]
    mov [rdi + EC_seclen], rax
    mov rcx, [r14 + 8]
    mov [rdi + EC_keylen], rcx
    mov rdx, [r14 + 16]
    mov [rdi + EC_vallen], rdx
    mov rsi, [r14 + 24]
    mov [rdi + EC_remove], rsi
    add r14, 32
    mov [rdi + EC_section], r14
    mov rsi, r15
    sub rsi, r14
    cmp rax, rsi
    ja .Lect_fail
    add r14, rax
    mov [rdi + EC_key], r14
    mov rsi, r15
    sub rsi, r14
    cmp rcx, rsi
    ja .Lect_fail
    add r14, rcx
    mov [rdi + EC_value], r14
    mov rsi, r15
    sub rsi, r14
    cmp rdx, rsi
    ja .Lect_fail
    add r14, rdx
    inc qword ptr [rsp + 8]
    jmp .Lect_decode
.Lect_call:
    lea rdi, [rip + ect_saved_deltas]
    lea rsi, [rip + ect_deltas]
    mov edx, EC_BATCH*EC_SIZE
    call memcpy
    mov rdi, [rsp]
    mov rsi, r12
    lea rdx, [rip + ect_deltas]
    mov rcx, r13
    call ect_call
    mov r12, rax
    mov r13, rdx
    test rax, rax
    jz 1f
    test rdx, rdx
    js .Lect_fail
    cmp rdx, EC_LIMIT
    ja .Lect_fail
    cmp byte ptr [rax + rdx], 0
    jne .Lect_fail
    jmp 2f
1:  test rdx, rdx
    jns .Lect_fail
2:  mov [rip + ect_status], r13
    lea rdi, [rip + ect_deltas]
    lea rsi, [rip + ect_saved_deltas]
    mov edx, EC_BATCH*EC_SIZE
    call memeq
    test eax, eax
    jz .Lect_fail
    mov rdi, [rip + ect_wire]
    mov rsi, [rip + ect_copy]
    mov rdx, [rip + ect_length]
    call memeq
    test eax, eax
    jz .Lect_fail
    mov edi, 1
    lea rsi, [rip + ect_status]
    mov edx, 8
    call write_all
    test rax, rax
    js .Lect_fail
    test r12, r12
    jz 3f
    mov edi, 1
    mov rsi, r12
    mov rdx, r13
    call write_all
    test rax, rax
    js .Lect_fail
3:  mov rdi, r12
    call mem_free
    mov rdi, [rip + ect_wire]
    call mem_free
    mov rdi, [rip + ect_copy]
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + ect_live]
    jne .Lect_fail
    xor edi, edi
    call sys_exit
.Lect_fail:
    mov edi, 126
    call sys_exit
