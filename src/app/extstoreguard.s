# Parent-owned root guards. Acquisition is nonblocking; cancellation never vetoes cleanup.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extvalidate.inc"
.section .rodata
.Lesg_lock_name: .asciz ".change.lock"
.text
FN ext_store_cancel
    mov rax, [rdi + ESG_cancel]
    test rax, rax
    jz 2f
    PROLOGUE
    mov rdi, [rdi + ESG_user]
    call rax
    test rax, rax
    jle 1f
    mov rax, -22
1:  EPILOGUE
2:  xor eax, eax
    ret

# ext_store_guard_free(ESG) -> first close failure or0; always release all ownership.
FN ext_store_guard_free
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + ESG_prepared], 0
    je 4f
    mov rax, -16
    ret
4:  PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    mov rdi, [rbx + ESG_lock]
    cmp rdi, -1
    je 1f
    mov qword ptr [rbx + ESG_lock], -1
    call ext_root_close
    mov r12, rax
1:  mov rdi, [rbx + ESG_root]
    cmp rdi, -1
    je 2f
    mov qword ptr [rbx + ESG_root], -1
    call ext_root_close
    test r12, r12
    jnz 2f
    mov r12, rax
2:  mov rdi, [rbx + ESG_path]
    call mem_free
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
3:  xor eax, eax
    ret

# ext_store_guard_try(root,exclusive,create,cancelFn,user)->ESG,0,0 or0,primary,cleanup.
FN ext_store_guard_try
    cmp rsi, 1
    ja .Lesg_invalid
    cmp rdx, 1
    ja .Lesg_invalid
    test rdx, rdx
    jz 1f
    test rsi, rsi
    jz .Lesg_invalid
1:  PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov qword ptr [rsp + 16], 0
    xor r15d, r15d
    call dir_scan_path_check
    test rax, rax
    js .Lesg_path_bad
    mov edi, ESG_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lesg_oom
    mov r15, rax
    mov qword ptr [rax + ESG_root], -1
    mov qword ptr [rax + ESG_lock], -1
    mov [rax + ESG_exclusive], r12
    mov qword ptr [rax + ESG_epoch], 1
    mov rcx, [rsp]
    mov [rax + ESG_cancel], rcx
    mov rcx, [rsp + 8]
    mov [rax + ESG_user], rcx
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup_try
    test rax, rax
    jz .Lesg_oom
    mov [r15 + ESG_path], rax
    mov rdi, r15
    call ext_store_cancel
    test rax, rax
    js .Lesg_path_bad
    mov rdi, [r15 + ESG_path]
    call ext_root_open
    test rax, rax
    jns .Lesg_adapter_ok1
    test rdx, rdx
    jns .Lesg_adapter_ok1
    mov [rsp + 16], rdx
    jmp .Lesg_path_bad
.Lesg_adapter_ok1:
    test rax, rax
    js .Lesg_path_bad
    mov [r15 + ESG_root], rax
.Lesg_read_lock:
    mov rdi, r15
    call ext_store_cancel
    test rax, rax
    js .Lesg_path_bad
    mov rdi, [r15 + ESG_root]
    lea rsi, [rip + .Lesg_lock_name]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    jns .Lesg_adapter_ok2
    test rdx, rdx
    jns .Lesg_adapter_ok2
    mov [rsp + 16], rdx
    jmp .Lesg_path_bad
.Lesg_adapter_ok2:
    cmp rax, -2
    jne .Lesg_opened
    test r13, r13
    jz .Lesg_path_bad
    xor r13d, r13d              # one create attempt; EEXIST reopens once
    mov rdi, r15
    call ext_store_cancel
    test rax, rax
    js .Lesg_path_bad
    mov rdi, [r15 + ESG_root]
    lea rsi, [rip + .Lesg_lock_name]
    mov edx, ER_FILE
    mov ecx, ER_WRITE | ER_CREATE | ER_EXCL
    mov r8d, 0600
    call ext_root_open_at
    test rax, rax
    jns .Lesg_adapter_ok3
    test rdx, rdx
    jns .Lesg_adapter_ok3
    mov [rsp + 16], rdx
    jmp .Lesg_path_bad
.Lesg_adapter_ok3:
    cmp rax, -17
    je .Lesg_read_lock
.Lesg_opened:
    test rax, rax
    js .Lesg_path_bad
    mov [r15 + ESG_lock], rax
    mov rdi, r15
    call ext_store_cancel
    test rax, rax
    js .Lesg_path_bad
    mov rdi, [r15 + ESG_lock]
    mov rsi, r12
    call ext_store_raw_lock
    test rax, rax
    js .Lesg_path_bad
    mov rax, r15
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesg_oom:
    mov rax, -12
.Lesg_path_bad:
    mov r14, rax
    mov rdi, r15
    call ext_store_guard_free
    mov rcx, [rsp + 16]
    test rcx, rcx
    jnz 9f
    mov rcx, rax
9:  mov rdx, r14
    xor eax, eax
    EPILOGUE
.Lesg_invalid:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    ret
