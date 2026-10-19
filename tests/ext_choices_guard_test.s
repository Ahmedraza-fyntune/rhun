.include "rhun.inc"
.include "app/extchoicesdisk.inc"
.bss
.p2align 3
cgt_reply: .zero 64
cgt_live: .quad 0
cgt_hold: .zero 8
cgt_fault: .quad 0
cgt_allocs: .quad 0
cgt_closes: .quad 0
cgt_opens: .quad 0
cgt_trailer: .zero 24
.text
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 5
    je 1f
    cmp qword ptr [rip + g_argc], 6
    jne .Lcgt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 40]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 40]
    call parse_u64
    mov [rip + cgt_fault], rax
1:
    mov rax, [rip + g_mem_live]
    mov [rip + cgt_live], rax
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 16]
    call parse_u64
    mov [rsp], rax
    mov rdi, [rbx + 24]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 24]
    call parse_u64
    mov rdx, rax
    mov rsi, [rsp]
    mov rdi, [rbx + 8]
    call ext_choices_guard_try
    mov r12, rax
    mov [rip + cgt_reply], rdx
    mov [rip + cgt_reply + 8], r8
    test rax, rax
    jz .Lcgt_send
    mov rdi, rax
    call ext_choices_snapshot_try
    mov r13, rax
    mov [rip + cgt_reply], rdx
    mov [rip + cgt_reply + 8], r8
    test rax, rax
    jz .Lcgt_send
    mov rax, [r13 + ECS_exists]
    mov [rip + cgt_reply + 16], rax
    mov rax, [r13 + ECS_length]
    mov [rip + cgt_reply + 24], rax
    lea rdi, [rip + cgt_reply + 32]
    lea rsi, [r13 + ECS_digest]
    mov edx, 32
    call memcpy
.Lcgt_send:
    mov edi, 1
    lea rsi, [rip + cgt_reply]
    mov edx, 64
    call write_all
    test rax, rax
    js .Lcgt_fail
    cmp qword ptr [rip + cgt_reply], 0
    jne 1f
    test r13, r13
    jz .Lcgt_fail
    mov edi, 1
    mov rsi, [r13 + ECS_bytes]
    mov rdx, [r13 + ECS_length]
    call write_all
    test rax, rax
    js .Lcgt_fail
1:  mov rdi, [rbx + 32]
    cmp byte ptr [rdi], '1'
    jne 2f
    xor edi, edi
    lea rsi, [rip + cgt_hold]
    mov edx, 1
    SYS SYS_read
2:  xor edi, edi
    test r12, r12
    jz 3f
    mov rdi, r13
    call ext_choices_snapshot_free
    mov rdi, r12
    call ext_choices_guard_free
    mov [rip + cgt_trailer], rax
3:  mov rax, [rip + cgt_allocs]
    mov [rip + cgt_trailer + 8], rax
    mov rax, [rip + cgt_opens]
    mov [rip + cgt_trailer + 16], rax
    mov edi, 1
    lea rsi, [rip + cgt_trailer]
    mov edx, 24
    call write_all
    test rax, rax
    js .Lcgt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cgt_live]
    jne .Lcgt_fail
    xor edi, edi
    call sys_exit
.Lcgt_fail:
    mov edi, 125
    call sys_exit

FN cgt_alloc
    inc qword ptr [rip + cgt_allocs]
    mov rax, [rip + cgt_allocs]
    cmp rax, [rip + cgt_fault]
    je 1f
    jmp mem_alloc_try
1:  xor eax, eax
    ret
FN cgt_close
    PROLOGUE
    call ext_root_close
    inc qword ptr [rip + cgt_closes]
    cmp qword ptr [rip + cgt_closes], 1
    jne 1f
    mov rcx, [rip + cgt_fault]
    cmp rcx, 101
    je 2f
    cmp rcx, 301
    je 2f
    cmp rcx, 401
    je 2f
    cmp rcx, 501
    jne 1f
2:  mov rax, -9
1:  EPILOGUE
FN cgt_read
    cmp qword ptr [rip + cgt_fault], 201
    je 1f
    cmp qword ptr [rip + cgt_fault], 301
    je 1f
    cmp qword ptr [rip + cgt_fault], 202
    je 2f
    jmp ext_root_read
1:  mov rax, -5
    ret
2:  xor eax, eax
    ret
FN cgt_stat
    cmp qword ptr [rip + cgt_fault], 401
    jne 1f
    mov rax, -5
    ret
1:  jmp ext_root_stat
FN cgt_identity
    cmp qword ptr [rip + cgt_fault], 501
    jne 1f
    mov rax, -5
    ret
1:  jmp ext_root_identity
FN cgt_open
    inc qword ptr [rip + cgt_opens]
    cmp qword ptr [rip + cgt_fault], 601
    jne 1f
    mov rax, -2
    mov rdx, -9
    ret
1:  cmp qword ptr [rip + cgt_fault], 602
    jne 3f
    cmp qword ptr [rip + cgt_opens], 1
    jne 2f
    mov rax, -2
    xor edx, edx
    ret
2:  mov rax, -17
    mov rdx, -9
    ret
3:  jmp ext_root_open_at
