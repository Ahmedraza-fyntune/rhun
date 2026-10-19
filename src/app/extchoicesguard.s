# Native off-UI settings lock. Never unlink or replace the lock's stable inode.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extchoicesdisk.inc"
.section .rodata
.Lecg_lock: .asciz "extensions.lock"
.bss
.p2align 3
ecg_instance: .quad 0
.text

# guard_free(ECG) ->0/first close error, EBUSY leaves ownership unchanged.
FN ext_choices_guard_free
    test rdi, rdi
    jz .Lecg_free_empty
    cmp qword ptr [rdi + ECG_active], 0
    jne .Lecg_busy
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    mov rdi, [rbx + ECG_lock]
    mov qword ptr [rbx + ECG_lock], -1
    cmp rdi, -1
    je 1f
    call ext_root_close
    mov r12, rax
1:  mov rdi, [rbx + ECG_root]
    mov qword ptr [rbx + ECG_root], -1
    cmp rdi, -1
    je 2f
    call ext_root_close
    test r12, r12
    jnz 2f
    mov r12, rax
2:  mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
.Lecg_free_empty:
    xor eax, eax
    ret
.Lecg_busy:
    mov rax, -16
    ret

# guard_try(configDir,exclusive,create)->owned ECG/0,primary,first cleanup in R8.
FN ext_choices_guard_try
    cmp rsi, 1
    ja .Lecg_invalid
    cmp rdx, 1
    ja .Lecg_invalid
    test rdx, rdx
    jz 1f
    test rsi, rsi
    jz .Lecg_invalid
1:  test rdi, rdi
    jz .Lecg_invalid
    cmp qword ptr [rip + ecg_instance], -1
    je .Lecg_overflow
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    mov edi, ECG_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lecg_nomem
    mov r15, rax
    mov qword ptr [rax + ECG_root], -1
    mov qword ptr [rax + ECG_lock], -1
    mov [rax + ECG_exclusive], r12
    mov qword ptr [rax + ECG_epoch], 1
    mov rdi, rbx
    call ext_root_open
    test rax, rax
    js .Lecg_open_failed
    mov [r15 + ECG_root], rax
.Lecg_open_lock:
    mov rdi, [r15 + ECG_root]
    lea rsi, [rip + .Lecg_lock]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    cmp rax, -2
    jne .Lecg_lock_opened
    test rdx, rdx
    jnz .Lecg_open_failed
    test r13, r13
    jz .Lecg_open_failed
    xor r13d, r13d
    mov rdi, [r15 + ECG_root]
    lea rsi, [rip + .Lecg_lock]
    mov edx, ER_FILE
    mov ecx, ER_WRITE | ER_CREATE | ER_EXCL
    mov r8d, 0600
    call ext_root_open_at
    cmp rax, -17
    jne .Lecg_lock_opened
    test rdx, rdx
    jnz .Lecg_open_failed
    jmp .Lecg_open_lock
.Lecg_lock_opened:
    test rax, rax
    js .Lecg_open_failed
    mov [r15 + ECG_lock], rax
    mov rdi, rax
    mov rsi, r12
    call ext_store_raw_lock
    test rax, rax
    js .Lecg_failed
    inc qword ptr [rip + ecg_instance]
    mov rax, [rip + ecg_instance]
    mov [r15 + ECG_token], rax
    mov rax, r15
    xor edx, edx
    xor r8d, r8d
    EPILOGUE
.Lecg_open_failed:
    mov r14, rdx             # Rooted open reports classification cleanup separately.
.Lecg_failed:
    mov r13, rax
    mov rdi, r15
    call ext_choices_guard_free
    test r14, r14
    jnz 1f
    mov r14, rax
1:  xor eax, eax
    mov rdx, r13
    mov r8, r14
    EPILOGUE
.Lecg_nomem:
    xor eax, eax
    mov rdx, -12
    xor r8d, r8d
    EPILOGUE
.Lecg_invalid:
    xor eax, eax
    mov rdx, -22
    xor r8d, r8d
    ret
.Lecg_overflow:
    xor eax, eax
    mov rdx, -75
    xor r8d, r8d
    ret

# Memory-only snapshots can outlive their guard. Binding uses nonreused numeric tokens.
FN ext_choices_snapshot_free
    test rdi, rdi
    jz 1f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + ECS_bytes]
    call mem_free
    mov rdi, rbx
    call mem_free
    EPILOGUE
1:  ret

# Only a post-ECP complete snapshot can resolve a sticky publication uncertainty.
FN ext_choices_reconcile_accept
    test rdi, rdi
    jz .Lecg_accept_no
    test rsi, rsi
    jz .Lecg_accept_no
    cmp qword ptr [rdi + ECG_active], 0
    jne .Lecg_accept_no
    cmp qword ptr [rdi + ECG_uncertain], 0
    je .Lecg_accept_no
    mov rax, [rdi + ECG_token]
    test rax, rax
    jz .Lecg_accept_no
    cmp [rsi + ECS_token], rax
    jne .Lecg_accept_no
    mov rax, [rdi + ECG_epoch]
    test rax, rax
    jz .Lecg_accept_no
    cmp [rsi + ECS_epoch], rax
    jne .Lecg_accept_no
    mov qword ptr [rdi + ECG_uncertain], 0
    xor eax, eax
    ret
.Lecg_accept_no:
    mov rax, -116
    ret
