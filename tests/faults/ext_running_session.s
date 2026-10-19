.bss
.p2align 3
.globl ss_hot
ss_hot: .quad 0
ss_hi: .quad 0
ss_saved: .zero EXT_SIZE
.text
ss_retain_identity:
    mov rdi, [rip + af_host + EXT_identity_owner]
    mov [rip + ss_hi], rdi
    jmp ext_host_identity_retain
ss_release_identity:
    mov rdi, [rip + ss_hi]
    jmp ext_host_identity_release
ss_call:
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    mov edx, 123
    jmp ss_check
# Exact input tuple preserved; hot flag never encloses full admission comparisons.
ss_check:
    PROLOGUE
    mov rcx, [rip + ss_hi]
    mov qword ptr [rip + ss_hot], 1
    call ext_activation_host_running_session_check
    mov qword ptr [rip + ss_hot], 0
    EPILOGUE
ss_bind:
    lea rdi, [rip + af_host]
    mov rsi, [rip + af_ea]
    mov edx, 123
    mov rcx, [rip + ss_hi]
    jmp ext_activation_host_running_bind_check
# A structurally valid separately retained HI with unequal bytes cannot establish a grant.
ss_mismatch:
    PROLOGUE 40
    lea rbx, [rip + af_host]
    mov rax, [rbx + EXT_identity_owner]
    mov [rsp], rax
    lea rdi, [rip + af_other]
    lea rsi, [rip + af_name]
    lea rdx, [rip + af_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz .Laf_abort
    test rdx, rdx
    jnz .Laf_abort
    mov r12, rax
    mov rdi, rax
    call ext_host_identity_retain
    test rax, rax
    jnz .Laf_abort
    mov [rbx + EXT_identity_owner], r12
    mov rax, [r12 + HI_owner]
    mov [rbx + EXT_owner], rax
    mov rax, [r12 + HI_name]
    mov [rbx + EXT_name], rax
    mov rax, [r12 + HI_state]
    mov [rbx + EXT_state], rax
    mov rdi, rbx
    mov rsi, [rip + af_ea]
    mov edx, 123
    mov rcx, r12
    call ext_activation_host_running_bind_check
    cmp rax, -116
    jne .Laf_abort
    mov rax, [rsp]
    mov [rbx + EXT_identity_owner], rax
    mov rcx, [rax + HI_owner]
    mov [rbx + EXT_owner], rcx
    mov rcx, [rax + HI_name]
    mov [rbx + EXT_name], rcx
    mov rcx, [rax + HI_state]
    mov [rbx + EXT_state], rcx
    mov rdi, r12
    call ext_host_identity_release
    call af_consumed
    mov rdi, r12
    call ext_host_identity_release
    call af_consumed
    call af_drain
    EPILOGUE
# Managed kinds bind through actual ready managed EA/EP/HI too.
ss_managed:
    PROLOGUE
    lea rdi, [rip + ss_saved]
    lea rsi, [rip + af_host]
    mov edx, EXT_SIZE
    call memcpy
    mov r12, [rip + af_host + EXT_activation_owner]
    mov rdi, r12
    call ext_activation_owner_retain
    test rax, rax
    jnz .Laf_abort
    call ss_retain_identity
    test rax, rax
    jnz .Laf_abort
    lea rbx, [rip + af_host]
    mov qword ptr [rbx + EXT_keeper], 123
    mov dword ptr [rbx + EXT_in], 124
    mov dword ptr [rbx + EXT_out], 125
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_startaccepted], 1
    mov rdi, rbx
    mov rsi, r12
    mov edx, 123
    mov rcx, [rip + ss_hi]
    call ext_activation_host_running_bind_check
    test rax, rax
    jnz .Laf_abort
    mov rdi, rbx
    mov rsi, r12
    mov edx, 123
    call ss_check
    test rax, rax
    jnz .Laf_abort
    lea rdi, [rip + af_host]
    lea rsi, [rip + ss_saved]
    mov edx, EXT_SIZE
    call memcpy
    call ss_release_identity
    call af_consumed
    mov rdi, r12
    call ext_activation_owner_release
    call af_consumed
    EPILOGUE
.globl ss_forbidden
ss_forbidden:
    mov edi, 193
    call sys_exit
