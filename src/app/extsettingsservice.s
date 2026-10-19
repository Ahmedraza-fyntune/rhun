# Owned settings domain construction. No filesystem IO or live editor adoption.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.bss
.p2align 3
.globl settings_service_current
settings_service_current: .quad 0
.text
# create(SVI40 borrowed for this call)->owned SVC/NULL,RDX primary.
# Three bounded allocations and a <=4095-byte path copy precede global publication.
FN ext_settings_service_create
    test rdi, rdi
    jz .Lsvc_bad_leaf
    cmp qword ptr [rip + settings_service_current], 0
    jne .Lsvc_exists_leaf
    cmp qword ptr [rip + esv_service_queue], 0
    jne .Lsvc_exists_leaf
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + SVI_length]
    test r12, r12
    jz .Lsvc_bad
    cmp r12, 4095
    ja .Lsvc_bad
    cmp qword ptr [rbx + SVI_context], 0
    jle .Lsvc_bad
    mov rdi, [rbx + SVI_path]
    test rdi, rdi
    jz .Lsvc_bad
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0
    je .Lsvc_bad
    inc rcx
    cmp rcx, r12
    jb 1b
    mov edi, SV_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz .Lsvc_empty
    mov r13, rax
    mov rdx, SVC_MAGIC
    mov [rax + SV_magic], rdx
    mov qword ptr [rax + SV_refs], 1
    mov rax, [rbx + SVI_context]
    mov [r13 + SV_context], rax
    mov [r13 + SV_length], r12
    mov rax, [rbx + SVI_nonce]
    mov [r13 + SV_nonce], rax
    mov rax, [rbx + SVI_nonce + 8]
    mov [r13 + SV_nonce + 8], rax
    lea rdi, [r12 + 1]
    call ext_settings_memory_try
    test rax, rax
    jz .Lsvc_abort
    mov [r13 + SV_path], rax
    mov rdi, rax
    mov rsi, [rbx + SVI_path]
    mov rdx, r12
    call memcpy
    mov rdi, [r13 + SV_path]
    mov byte ptr [rdi + r12], 0
    call ext_settings_worker_path
    test rax, rax
    js .Lsvc_abort_primary
    call ext_settings_queue_create
    test rax, rax
    jz .Lsvc_abort
    mov [r13 + SV_queue], rax
    mov rdi, rax
    mov rsi, [r13 + SV_context]
    call ext_settings_model_context_init
    test rax, rax
    js .Lsvc_abort_primary
    # No rejecting operation follows the borrowed queue/context publication.
    mov qword ptr [r13 + SV_state], SV_LIVE
    mov [rip + settings_service_current], r13
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lsvc_abort:
    mov rax, rdx
.Lsvc_abort_primary:
    mov [r13 + SV_primary], rax
    mov r14, rax
    mov rdi, r13
    call settings_service_abort
    xor eax, eax
    mov rdx, r14
    EPILOGUE
.Lsvc_bad:
    mov rdx, -22
.Lsvc_empty:
    xor eax, eax
    EPILOGUE
.Lsvc_bad_leaf:
    xor eax, eax
    mov rdx, -22
    ret
.Lsvc_exists_leaf:
    xor eax, eax
    mov rdx, -114
    ret
