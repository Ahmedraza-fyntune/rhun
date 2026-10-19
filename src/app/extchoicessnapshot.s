# Complete immutable settings reads, with independent missing-file and digest metadata.
.include "rhun.inc"
.include "app/extchoices.inc"
.include "app/extchoicesdisk.inc"
.include "app/extvalidate.inc"
.section .rodata
.Lecs_file: .asciz "extensions.ini"
.text

# Read exactly the previously stated size plus an EOF probe, then check size again.
# ec_choices_read_exact(raw,buffer(size+1),size)->0/-errno. No handle ownership transfer.
FN ext_choices_read_exact
    cmp rdx, EC_LIMIT
    ja .Lecs_read_large
    test rsi, rsi
    jz .Lecs_read_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, r13
    jae .Lecs_probe
    mov rdi, rbx
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    cmp rdx, 65536
    jbe 2f
    mov edx, 65536
2:  mov rcx, r14
    call ext_root_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js .Lecs_read_done
    jz .Lecs_read_changed
    mov rdx, r13
    sub rdx, r14
    cmp rax, rdx
    ja .Lecs_read_io
    add r14, rax
    jmp 1b
.Lecs_probe:
    mov rdi, rbx
    lea rsi, [r12 + r13]
    mov edx, 1
    mov rcx, r13
    call ext_root_read
    cmp rax, -EINTR
    je .Lecs_probe
    test rax, rax
    js .Lecs_read_done
    jnz .Lecs_read_changed
    mov rdi, rbx
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lecs_read_done
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lecs_read_changed
    cmp [rsp + ER_size], r13
    jne .Lecs_read_changed
    mov byte ptr [r12 + r13], 0
    xor eax, eax
    jmp .Lecs_read_done
.Lecs_read_changed:
    mov rax, -11
    jmp .Lecs_read_done
.Lecs_read_io:
    mov rax, -5
.Lecs_read_done:
    EPILOGUE
.Lecs_read_large:
    mov rax, -27
    ret
.Lecs_read_invalid:
    mov rax, -22
    ret

# snapshot_try(ECG)->ECS/0,primary,first cleanup in R8.
FN ext_choices_snapshot_try
    test rdi, rdi
    jz .Lecs_invalid
    PROLOGUE 48
    mov rbx, rdi
    xor r12d, r12d
    mov r13, -1
    xor r14d, r14d
    xor r15d, r15d
    cmp qword ptr [rbx + ECG_root], -1
    je .Lecs_bad_guard
    cmp qword ptr [rbx + ECG_lock], -1
    je .Lecs_bad_guard
    cmp qword ptr [rbx + ECG_token], 0
    je .Lecs_bad_guard
    mov edi, ECS_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lecs_nomem
    mov r12, rax
    mov rax, [rbx + ECG_token]
    mov [r12 + ECS_token], rax
    mov rax, [rbx + ECG_epoch]
    mov [r12 + ECS_epoch], rax
    mov rdi, [rbx + ECG_root]
    lea rsi, [rip + .Lecs_file]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    cmp rax, -2
    je .Lecs_missing
    test rax, rax
    js .Lecs_open_error
    mov r13, rax
    mov qword ptr [r12 + ECS_exists], 1
    mov rdi, r13
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lecs_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lecs_bad_guard
    mov rax, [rsp + ER_size]
    cmp rax, EC_LIMIT
    ja .Lecs_large
    mov [r12 + ECS_length], rax
    lea rdi, [rax + 1]
    call mem_alloc_try
    test rax, rax
    jz .Lecs_nomem
    mov [r12 + ECS_bytes], rax
    mov rdi, r13
    mov rsi, rax
    mov rdx, [r12 + ECS_length]
    call ext_choices_read_exact
    test rax, rax
    js .Lecs_error
    mov rdi, r13
    lea rsi, [r12 + ECS_identity]
    call ext_root_identity
    test rax, rax
    js .Lecs_error
    mov rdi, r13
    mov r13, -1                # A close error does not authorize reusing its numeric handle.
    call ext_root_close
    test rax, rax
    js .Lecs_error
    jmp .Lecs_validate
.Lecs_missing:
    test rdx, rdx
    jnz .Lecs_open_error
    mov edi, 1
    call mem_alloc_try
    test rax, rax
    jz .Lecs_nomem
    mov [r12 + ECS_bytes], rax
.Lecs_validate:
    mov rdi, [r12 + ECS_bytes]
    mov rsi, [r12 + ECS_length]
    call ext_choices_validate
    test rax, rax
    js .Lecs_error
    mov rdi, [r12 + ECS_bytes]
    mov rsi, [r12 + ECS_length]
    lea rdx, [r12 + ECS_digest]
    call sha256_hash
    test eax, eax
    jz .Lecs_hash_error
    mov rax, r12
    xor edx, edx
    xor r8d, r8d
    EPILOGUE
.Lecs_open_error:
    mov r14, rdx
    jmp .Lecs_error
.Lecs_hash_error:
    mov rax, -5
    jmp .Lecs_error
.Lecs_nomem:
    mov rax, -12
    jmp .Lecs_error
.Lecs_large:
    mov rax, -27
    jmp .Lecs_error
.Lecs_bad_guard:
    mov rax, -22
.Lecs_error:
    mov r15, rax
    mov rdi, r13
    mov r13, -1
    cmp rdi, -1
    je 1f
    call ext_root_close
    test r14, r14
    jnz 1f
    mov r14, rax
1:  mov rdi, r12
    call ext_choices_snapshot_free
    xor eax, eax
    mov rdx, r15
    mov r8, r14
    EPILOGUE
.Lecs_invalid:
    xor eax, eax
    mov rdx, -22
    xor r8d, r8d
    ret
