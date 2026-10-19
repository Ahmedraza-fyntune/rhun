# Private off-UI settings candidate. Every acquired resource remains in ECP on failure.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extstore.inc"
.include "app/extchoices.inc"
.include "app/extchoicesdisk.inc"
.section .rodata
.Lecp_prefix: .asciz ".extensions-"
.Lecp_suffix: .asciz ".pending"
.Lecp_destination: .asciz "extensions.ini"
.bss
.p2align 3
ecp_serial: .quad 0
.text

# begin_try(exclusive ECG)->ECP/0,primary,cleanup. No file I/O or guard mutation on failure.
FN ext_choices_begin_try
    test rdi, rdi
    jz .Lecp_begin_invalid
    cmp qword ptr [rdi + ECG_exclusive], 1
    jne .Lecp_begin_invalid
    cmp qword ptr [rdi + ECG_root], -1
    je .Lecp_begin_invalid
    cmp qword ptr [rdi + ECG_lock], -1
    je .Lecp_begin_invalid
    cmp qword ptr [rdi + ECG_token], 0
    je .Lecp_begin_invalid
    cmp qword ptr [rdi + ECG_active], 0
    jne .Lecp_begin_busy
    cmp qword ptr [rdi + ECG_uncertain], 0
    jne .Lecp_begin_uncertain
    cmp qword ptr [rdi + ECG_epoch], 0
    je .Lecp_begin_overflow
    cmp qword ptr [rdi + ECG_epoch], -1
    je .Lecp_begin_overflow
    PROLOGUE
    mov rbx, rdi
    mov edi, ECP_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lecp_begin_nomem
    mov r12, rax
    mov [rax + ECP_guard], rbx
    mov rcx, [rbx + ECG_epoch]
    mov [rax + ECP_epoch], rcx
    mov qword ptr [rax + ECP_source], -1
    lea rdi, [rax + ECP_delete]
    call ext_store_unlink_init
    mov edi, EC_LIMIT + 1
    call mem_alloc_try
    test rax, rax
    jz 1f
    mov [r12 + ECP_scratch], rax
    mov [rbx + ECG_active], r12
    mov rax, r12
    xor edx, edx
    xor r8d, r8d
    EPILOGUE
1:  mov rdi, r12
    call mem_free
.Lecp_begin_nomem:
    xor eax, eax
    mov rdx, -12
    xor r8d, r8d
    EPILOGUE
.Lecp_begin_invalid:
    xor eax, eax
    mov rdx, -22
    xor r8d, r8d
    ret
.Lecp_begin_busy:
    xor eax, eax
    mov rdx, -16
    xor r8d, r8d
    ret
.Lecp_begin_uncertain:
    xor eax, eax
    mov rdx, -117
    xor r8d, r8d
    ret
.Lecp_begin_overflow:
    xor eax, eax
    mov rdx, -75
    xor r8d, r8d
    ret

# ecp_current(ECP)->1/0, allocation-free guard identity/epoch check.
FN ext_choices_current
    test rdi, rdi
    jz 2f
    mov rax, [rdi + ECP_guard]
    test rax, rax
    jz 2f
    cmp [rax + ECG_active], rdi
    jne 2f
    cmp qword ptr [rax + ECG_exclusive], 1
    jne 2f
    mov rcx, [rdi + ECP_epoch]
    test rcx, rcx
    jz 2f
    cmp [rax + ECG_epoch], rcx
    jne 2f
    mov eax, 1
    ret
2:  xor eax, eax
    ret

# prepare_try(ECP,deltas,count)->0/-errno,RDX first cleanup. Failure keeps ECP owned.
FN ext_choices_prepare_try
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_choices_current
    test eax, eax
    jz .Lecp_prepare_stale
    cmp qword ptr [rbx + ECP_state], ECP_NEW
    jne .Lecp_prepare_invalid
    mov rdi, [rbx + ECP_guard]
    call ext_choices_snapshot_try
    test rax, rax
    jz .Lecp_prepare_snapshot_error
    mov [rbx + ECP_old], rax
    mov rdi, [rax + ECS_bytes]
    mov rsi, [rax + ECS_length]
    mov rdx, r12
    mov rcx, r13
    call ext_choices_merge
    test rax, rax
    jz .Lecp_prepare_merge_error
    mov [rbx + ECP_bytes], rax
    mov [rbx + ECP_length], rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rbx + ECP_digest]
    call sha256_hash
    test eax, eax
    jz .Lecp_prepare_io
    mov r12, [rbx + ECP_old]
    cmp qword ptr [r12 + ECS_exists], 1
    jne .Lecp_prepare_stage
    mov rax, [r12 + ECS_length]
    cmp [rbx + ECP_length], rax
    jne .Lecp_prepare_stage
    mov rdi, [r12 + ECS_bytes]
    mov rsi, [rbx + ECP_bytes]
    mov rdx, rax
    call memeq
    test eax, eax
    jz .Lecp_prepare_stage
    mov qword ptr [rbx + ECP_noop], 1
    jmp .Lecp_prepare_ready
.Lecp_prepare_stage:
    mov rdi, rbx
    call ext_choices_security_prepare
    test rax, rax
    js .Lecp_prepare_error
    mov r12d, 8
.Lecp_prepare_name:
    cmp qword ptr [rip + ecp_serial], -1
    je .Lecp_prepare_overflow
    inc qword ptr [rip + ecp_serial]
    lea rdi, [rbx + ECP_name]
    lea rsi, [rip + .Lecp_prefix]
    call cstr_copy
    mov [rsp], rax
    call ext_store_raw_pid
    mov rsi, rax
    mov rdi, [rsp]
    call fmt_u64
    mov byte ptr [rdi], '-'
    inc rdi
    mov rsi, [rip + ecp_serial]
    call fmt_u64
    lea rsi, [rip + .Lecp_suffix]
    call cstr_copy
    # ASCII generated names fit80 bytes; precompute UTF16 without heap/path conversion.
    xor ecx, ecx
1:  movzx eax, byte ptr [rbx + rcx + ECP_name]
    mov word ptr [rbx + rcx*2 + ECP_wide], ax
    test eax, eax
    jz 2f
    inc rcx
    cmp rcx, 79
    jb 1b
    jmp .Lecp_prepare_io
2:  add rcx, rcx
    mov [rbx + ECP_wide_length], rcx
    mov rax, [rbx + ECP_guard]
    mov rdi, [rax + ECG_root]
    lea rsi, [rbx + ECP_name]
    lea rdx, [rbx + ECP_wide]
    mov r8, [rbx + ECP_security]
    call ext_choices_raw_create
    cmp rax, -17
    jne .Lecp_prepare_created
    dec r12d
    jnz .Lecp_prepare_name
.Lecp_prepare_created:
    test rax, rax
    js .Lecp_prepare_error
    mov [rbx + ECP_source], rax    # ownership handoff precedes any classification.
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lecp_prepare_error
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Lecp_prepare_io
    cmp qword ptr [rsp + ER_size], 0
    jne .Lecp_prepare_io
    mov rdi, [rbx + ECP_source]
    lea rsi, [rbx + ECP_identity]
    call ext_root_identity
    test rax, rax
    js .Lecp_prepare_error
    mov qword ptr [rbx + ECP_identity_known], 1
    xor r12d, r12d
.Lecp_prepare_write:
    cmp r12, [rbx + ECP_length]
    jae .Lecp_prepare_sync
    mov rdi, [rbx + ECP_source]
    mov rsi, [rbx + ECP_bytes]
    add rsi, r12
    mov r13, [rbx + ECP_length]
    sub r13, r12
    cmp r13, 65536
    jbe 1f
    mov r13d, 65536
1:  mov rdx, r13
    call ext_store_raw_write
    cmp rax, -EINTR
    je .Lecp_prepare_write
    test rax, rax
    js .Lecp_prepare_error
    jz .Lecp_prepare_io
    cmp rax, r13
    ja .Lecp_prepare_io
    add r12, rax
    jmp .Lecp_prepare_write
.Lecp_prepare_sync:
    mov rdi, [rbx + ECP_source]
    call ext_store_raw_sync
    cmp rax, -EINTR
    je .Lecp_prepare_sync
    test rax, rax
    js .Lecp_prepare_error
    # Fixed native destination buffer: header20 plus14 UTF16 basename characters.
    mov byte ptr [rbx + ECP_rename], 1
    mov rax, [rbx + ECP_guard]
    mov rax, [rax + ECG_root]
    mov [rbx + ECP_rename + 8], rax
    mov dword ptr [rbx + ECP_rename + 16], 28
    xor ecx, ecx
    lea rdx, [rip + .Lecp_destination]
1:  movzx eax, byte ptr [rdx + rcx]
    mov word ptr [rbx + rcx*2 + ECP_rename + 20], ax
    inc rcx
    cmp rcx, 14
    jb 1b
.Lecp_prepare_ready:
    mov qword ptr [rbx + ECP_state], ECP_PREPARED
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lecp_prepare_snapshot_error:
    mov [rbx + ECP_cleanup_error], r8
.Lecp_prepare_merge_error:
    mov rax, rdx
    jmp .Lecp_prepare_error
.Lecp_prepare_overflow:
    mov rax, -75
    jmp .Lecp_prepare_error
.Lecp_prepare_io:
    mov rax, -5
.Lecp_prepare_error:
    mov [rbx + ECP_result], rax
    mov qword ptr [rbx + ECP_state], ECP_FAILED
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecp_prepare_stale:
    mov rax, -116
    xor edx, edx
    EPILOGUE
.Lecp_prepare_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
