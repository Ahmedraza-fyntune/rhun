# Allocation-free rooted rechecks use only ECP-owned buffers and prepared names.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extchoices.inc"
.include "app/extchoicesdisk.inc"
.section .rodata
.Lecf_name: .asciz "extensions.ini"
.p2align 1
.Lecf_wide: .short 'e','x','t','e','n','s','i','o','n','s','.','i','n','i'
.text
FN ext_choices_open_final
    mov rax, [rdi + ECP_guard]
    mov rdi, [rax + ECG_root]
.ifdef WINDOWS
    lea rsi, [rip + .Lecf_wide]
    mov edx, 28
    mov ecx, ER_FILE
    xor r8d, r8d
    jmp win_ext_root_open_prepared_at
.else
    lea rsi, [rip + .Lecf_name]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    jmp ext_root_open_at
.endif

FN ext_choices_open_stage
    mov rax, rdi
    mov rdi, [rax + ECP_guard]
    mov rdi, [rdi + ECG_root]
.ifdef WINDOWS
    lea rsi, [rax + ECP_wide]
    mov rdx, [rax + ECP_wide_length]
    mov ecx, ER_FILE
    xor r8d, r8d
    jmp win_ext_root_open_prepared_at
.else
    lea rsi, [rax + ECP_name]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    jmp ext_root_open_at
.endif

# read_final(ECP,ECRout48)->0/-errno,RDX first close failure. Scratch contains exact bytes.
FN ext_choices_read_final
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, -1
    xor r14d, r14d
    mov rdi, r12
    xor esi, esi
    mov edx, ECR_SIZE
    call memset
    mov rdi, rbx
    call ext_choices_open_final
    cmp rax, -2
    jne 1f
    test rdx, rdx
    jnz .Lecf_open_error
    mov rax, [rbx + ECP_scratch]
    mov byte ptr [rax], 0
    xor eax, eax
    xor edx, edx
    EPILOGUE
1:  test rax, rax
    js .Lecf_open_error
    mov r13, rax
    mov qword ptr [r12 + ECR_exists], 1
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lecf_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lecf_invalid
    mov rdx, [rsp + ER_size]
    cmp rdx, EC_LIMIT
    ja .Lecf_large
    mov [r12 + ECR_length], rdx
    mov rdi, r13
    mov rsi, [rbx + ECP_scratch]
    call ext_choices_read_exact
    test rax, rax
    js .Lecf_error
    mov rdi, r13
    lea rsi, [r12 + ECR_identity]
    call ext_root_identity
    test rax, rax
    js .Lecf_error
    mov rdi, r13
    mov r13, -1
    call ext_root_close
    xor edx, edx
    EPILOGUE
.Lecf_open_error:
    mov r14, rdx
    jmp .Lecf_error
.Lecf_invalid:
    mov rax, -22
    jmp .Lecf_error
.Lecf_large:
    mov rax, -27
.Lecf_error:
    mov r15, rax
    cmp r13, -1
    je 1f
    mov rdi, r13
    mov r13, -1
    call ext_root_close
    test r14, r14
    jnz 1f
    mov r14, rax
1:  mov rax, r15
    mov rdx, r14
    EPILOGUE

# stage_identity(ECP)->0 same owned named object,1 clean absence,negative failure.
FN ext_choices_stage_identity
    PROLOGUE 32
    mov rbx, rdi
    mov r12, -1
    xor r13d, r13d
    mov rdi, [rbx + ECP_source]
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    js .Lecsi_primary
    lea rdi, [rbx + ECP_identity]
    mov rsi, rsp
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lecsi_stale
    mov rdi, rbx
    call ext_choices_open_stage
    cmp rax, -2
    jne 1f
    test rdx, rdx
    jnz .Lecsi_open_error
    mov eax, 1
    xor edx, edx
    EPILOGUE
1:  test rax, rax
    js .Lecsi_open_error
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_identity
    test rax, rax
    js .Lecsi_primary
    lea rdi, [rbx + ECP_identity]
    mov rsi, rsp
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lecsi_stale
    xor r14d, r14d
    jmp .Lecsi_close
.Lecsi_open_error:
    mov r13, rdx
    jmp .Lecsi_primary
.Lecsi_stale:
    mov rax, -116
.Lecsi_primary:
    mov r14, rax
.Lecsi_close:
    cmp r12, -1
    je 2f
    mov rdi, r12
    mov r12, -1
    call ext_root_close
    test r14, r14
    jnz 1f
    mov r14, rax
    jmp 2f
1:  test r13, r13
    jnz 2f
    mov r13, rax
2:  mov rax, r14
    mov rdx, r13
    EPILOGUE

# stage_check(ECP)->0/-errno. Reads through retained source AND verifies its rooted name.
FN ext_choices_stage_check
    PROLOGUE 32
    mov rbx, rdi
    mov rdi, [rbx + ECP_source]
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lecsc_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lecsc_stale
    mov rdx, [rbx + ECP_length]
    cmp [rsp + ER_size], rdx
    jne .Lecsc_stale
    mov rdi, [rbx + ECP_source]
    mov rsi, [rbx + ECP_scratch]
    call ext_choices_read_exact
    test rax, rax
    js .Lecsc_error
    mov rdi, [rbx + ECP_scratch]
    mov rsi, [rbx + ECP_bytes]
    mov rdx, [rbx + ECP_length]
    call memeq
    test eax, eax
    jz .Lecsc_stale
    mov rdi, rbx
    call ext_choices_stage_identity
    cmp rax, 1
    jne 1f
.Lecsc_stale:
    mov rax, -116
.Lecsc_error:
    xor edx, edx
1:  EPILOGUE
