# New prepared hosts own both ends before any fallible flag operation.
.include "rhun.inc"
.text
# EXT,pair0stdin/1stdout ->0/-errno. Failure may leave explicitly owned endpoints.
FN ext_host_pipe_create
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Lhpc_bad
    cmp r12, 1
    ja .Lhpc_bad
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lhpc_bad
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lhpc_busy
    lea r13, [rbx + EXT_host_child_in]
    lea r14, [rbx + EXT_in]
    test r12, r12
    jz 1f
    lea r13, [rbx + EXT_out]
    lea r14, [rbx + EXT_host_child_out]
1:  cmp dword ptr [r13], 0
    jns .Lhpc_busy
    cmp dword ptr [r14], 0
    jns .Lhpc_busy
    lea rdi, [rsp]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Lhpc_done
    mov eax, [rsp]
    mov [r13], eax
    mov eax, [rsp + 4]
    mov [r14], eax
.ifndef WINDOWS
    # Darwin's compatibility adapter ignores its own set-fd failures.
    # Check explicit CLOEXEC installation only after both ends have host owners.
    mov edi, [r13]
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
    test rax, rax
    js .Lhpc_done
    mov edi, [r14]
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
    test rax, rax
    js .Lhpc_done
.endif
    xor eax, eax
.Lhpc_done:
    EPILOGUE
.Lhpc_bad:
    mov rax, -22
    EPILOGUE
.Lhpc_busy:
    mov rax, -16
    EPILOGUE
