# Package lease transfers only on begin success and survives EP through retained GP.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
FN main
    PROLOGUE 64
    cmp qword ptr [rip + g_argc], 2
    jne .Leplt_bad
    mov rbx, [rip + g_argv]
    mov rbx, [rbx + 8]
    mov rax, [rip + g_mem_live]
    mov [rsp + 32], rax
    mov rdi, rbx
    call ext_root_open
    test rax, rax
    js .Leplt_bad
    mov r12, rax
    mov rdi, rax
    call ext_root_reopen_dir
    test rax, rax
    js .Leplt_bad
    mov r13, rax
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rip + eplt_bad_owner]
    lea rcx, [rip + eplt_name]
    mov r8, r13
    call ext_prepare_begin
    test rax, rax
    jnz .Leplt_bad
    cmp rdx, -EV_BAD_ID
    jne .Leplt_bad
    mov rdi, r13
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    js .Leplt_bad
    mov rdi, r12
    mov rsi, rbx
    lea rdx, [rip + eplt_owner]
    lea rcx, [rip + eplt_name]
    mov r8, r13
    call ext_prepare_begin
    test rax, rax
    jz .Leplt_bad
    mov r14, rax
1:  mov rdi, r14
    call ext_prepare_step
    cmp rax, 1
    je 1b
    test rax, rax
    jnz .Leplt_bad
    mov rdi, r14
    call ext_prepare_grammars
    test rdx, rdx
    jz .Leplt_bad
    mov r15, [rax]
    mov rdi, r15
    call grammar_prepare_retain
    test rax, rax
    jnz .Leplt_bad
    mov rdi, r14
    call ext_prepare_release
    test rax, rax
    jnz .Leplt_bad
    mov rdi, r13
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    js .Leplt_bad
    mov rdi, r15
    call grammar_prepare_gr
    test rax, rax
    jz .Leplt_bad
    cmp qword ptr [rax + GR_name], 0
    je .Leplt_bad
    mov rdi, r15
    call grammar_prepare_release
    test rax, rax
    jnz .Leplt_bad
    mov rdi, r13
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    jns .Leplt_bad
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jnz .Leplt_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 32]
    jne .Leplt_bad
    xor eax, eax
    EPILOGUE
.Leplt_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
eplt_owner: .asciz "fixture"
eplt_bad_owner: .asciz ".invalid"
eplt_name: .asciz "example"
