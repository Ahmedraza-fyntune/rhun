# EP settings and shared GP owners retire one unit at a time, including retained readers.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
FN main
    PROLOGUE 64
    mov rax, [rip + g_mem_live]
    mov [rsp + 32], rax
    mov rdi, -1
    lea rsi, [rip + graph_dir]
    lea rdx, [rip + graph_owner]
    lea rcx, [rip + graph_name]
    call ext_prepare_alloc
    test rax, rax
    jz .Lgraph_bad
    mov rbx, rax
    mov rdi, rax
    call ext_prepare_enable_deferred
    test rax, rax
    jnz .Lgraph_bad
    xor r12d, r12d
1:  mov rdi, [rbx + PO_eo]
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lgraph_bad
    mov r13, rax
    mov r14d, 8
2:  mov rdi, r13
    mov esi, 80
    call prep_owned_alloc
    test rax, rax
    jz .Lgraph_bad
    dec r14
    jnz 2b
    mov rdi, rbx
    lea rsi, [rbx + EP_grammars]
    mov edx, 8
    call prep_owned_vec_push
    test rax, rax
    jz .Lgraph_bad
    mov [rax], r13
    inc r12
    cmp r12, 64
    jb 1b
    mov qword ptr [r13 + PO_ready], 1
    mov rdi, r13
    call grammar_prepare_retain
    test rax, rax
    jnz .Lgraph_bad
    mov [rsp + 40], r13
    xor r12d, r12d
3:  mov rdi, rbx
    lea rsi, [rbx + EP_ext + EXT_sdefs]
    mov edx, SD_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lgraph_bad
    mov r13, rax
    or dword ptr [r13 + SD_pad], 1
    mov rdi, rbx
    lea rsi, [rip + graph_value]
    mov edx, 3
    call prep_value_dup
    test rax, rax
    jz .Lgraph_bad
    mov [r13 + SD_value], rax
    inc r12
    cmp r12, 256
    jb 3b
    mov r15, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov [rsp + 48], rax
    mov rdi, rbx
    call ext_prepare_release_deferred
    test rax, rax
    jnz .Lgraph_bad
    cmp rdx, 1
    jne .Lgraph_bad
    cmp [rip + g_mem_live], r15
    jne .Lgraph_bad
    call ext_prepare_retire_charge
    cmp rax, [rsp + 48]
    jne .Lgraph_bad
    call .Lgraph_drain
    mov rax, [rip + g_mem_live]
    sub rax, [rsp + 32]
    cmp rax, 10
    jne .Lgraph_bad
    mov rdi, [rsp + 40]
    call grammar_prepare_release_deferred
    test rax, rax
    jnz .Lgraph_bad
    cmp rdx, 1
    jne .Lgraph_bad
    call .Lgraph_drain
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lgraph_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 32]
    jne .Lgraph_bad
    xor eax, eax
    EPILOGUE
.Lgraph_bad:
    mov eax, 1
    EPILOGUE
# A separate small frame owns output32. No access to freed EP/GP payloads.
.Lgraph_drain:
    PROLOGUE 32
    xor r12d, r12d
4:  mov r15, [rip + g_mem_live]
    mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    test rax, rax
    js .Lgraph_drain_bad
    mov r13, rax
    cmp qword ptr [rsp + 16], 0
    jne .Lgraph_drain_bad
    cmp qword ptr [rsp + 24], 0
    jne .Lgraph_drain_bad
    mov rax, [rip + g_mem_live]
    cmp rax, r15
    ja .Lgraph_drain_bad
    sub r15, rax
    cmp r15, 1
    ja .Lgraph_drain_bad
    inc r12
    cmp r12, 1600
    ja .Lgraph_drain_bad
    test r13, r13
    jnz 4b
    EPILOGUE
.Lgraph_drain_bad:
    mov edi, 1
    SYS SYS_exit_group
.section .rodata
graph_dir: .asciz "/private/payload"
graph_owner: .asciz "fixture"
graph_name: .asciz "example"
graph_value: .asciz "yes"
