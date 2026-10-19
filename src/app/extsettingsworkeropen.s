# Only the isolated helper opens configuration paths or locks.
.include "rhun.inc"
.include "app/extsettingsworker.inc"
.text
FN sw_cleanup_latch
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + SW_cleanup], 0
    jne 1f
    mov [rdi + SW_cleanup], rsi
1:  ret

# open(ctx)->0/-errno. READ may own an exact absent snapshot without a guard.
FN sw_open
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rbx + SW_mode], 1
    jne 1f
    xor r12d, r12d
    jmp 2f
1:  mov r12d, 1
2:  lea rdi, [rbx + SW_request + SWR_path]
    mov rsi, r12
    mov rdx, r12
    call ext_choices_guard_try
    mov [rbx + SW_guard], rax
    mov r13, rdx
    mov r14, r8
    mov rdi, rbx
    mov rsi, r8
    call sw_cleanup_latch
    cmp qword ptr [rbx + SW_guard], 0
    jne .Lswo_guard_open
    cmp r13, -2
    jne .Lswo_failed
    test r14, r14
    jnz .Lswo_failed
    test r12, r12
    jnz .Lswo_create
    # Distinguish absent config directory from existing directory without its lock.
    lea rdi, [rbx + SW_request + SWR_path]
    call ext_root_open
    mov r13, rax
    mov r14, rdx
    test rax, rax
    jns .Lswo_existing_read
    cmp rax, -2
    jne .Lswo_probe_error
    test r14, r14
    jnz .Lswo_probe_error
    mov edi, ECS_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lswo_nomem
    mov [rbx + SW_snapshot], rax
    mov r12, rax
    mov edi, 1
    call mem_alloc_try
    test rax, rax
    jz .Lswo_nomem
    mov [r12 + ECS_bytes], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [r12 + ECS_digest]
    call sha256_hash
    test eax, eax
    jz .Lswo_io
    xor eax, eax
    EPILOGUE
.Lswo_existing_read:
    mov rdi, r13
    call ext_root_close
    mov [rsp], rax
    test r14, r14
    js .Lswo_probe_error
    test rax, rax
    js .Lswo_return
    jmp .Lswo_retry
.Lswo_create:
    lea rdi, [rbx + SW_request + SWR_path]
    call sw_create_path
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, rdx
    call sw_cleanup_latch
    mov rax, [rsp]
    test rax, rax
    js .Lswo_return
.Lswo_retry:
    lea rdi, [rbx + SW_request + SWR_path]
    mov esi, 1
    mov edx, 1
    call ext_choices_guard_try
    mov [rbx + SW_guard], rax
    mov r13, rdx
    mov r14, r8
    mov rdi, rbx
    mov rsi, r8
    call sw_cleanup_latch
    cmp qword ptr [rbx + SW_guard], 0
    je .Lswo_failed
.Lswo_guard_open:
    test r13, r13
    js .Lswo_failed
    test r14, r14
    js .Lswo_failed
    xor eax, eax
.Lswo_return:
    EPILOGUE
.Lswo_probe_error:
    mov rdi, rbx
    mov rsi, r14
    call sw_cleanup_latch
    mov rax, r13
    test rax, rax
    js .Lswo_return
    mov rax, r14
    EPILOGUE
.Lswo_failed:
    mov rax, r13
    test rax, rax
    js .Lswo_return
    mov rax, r14
    test rax, rax
    js .Lswo_return
.Lswo_io:
    mov rax, -5
    EPILOGUE
.Lswo_nomem:
    mov rax, -12
    EPILOGUE

FN sw_snapshot_take
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + SW_snapshot], 0
    jne 1f
    mov rdi, [rbx + SW_guard]
    call ext_choices_snapshot_try
    mov [rbx + SW_snapshot], rax
    mov r12, rdx
    mov rdi, rbx
    mov rsi, r8
    call sw_cleanup_latch
    cmp qword ptr [rbx + SW_snapshot], 0
    jne 1f
    mov rax, r12
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

FN sw_snapshot_free
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + SW_snapshot]
    mov qword ptr [rbx + SW_snapshot], 0
    call ext_choices_snapshot_free
    EPILOGUE

# final cleanup consumes only proven memory/native ownership, never infers from time.
FN sw_cleanup_all
    PROLOGUE
    mov rbx, rdi
    call sw_cleanup_candidate
    mov rdi, rbx
    call sw_snapshot_free
    mov rdi, rbx
    call sw_body_free
.Lswo_guard_cleanup:
    mov r12, [rbx + SW_guard]
    test r12, r12
    jz 2f
    # Candidate cleanup proved ECG_active0, so guard_free consumes even on close errno.
    cmp qword ptr [r12 + ECG_active], 0
    jne 3f
    mov qword ptr [rbx + SW_guard], 0
    mov rdi, r12
    call ext_choices_guard_free
    mov rdi, rbx
    mov rsi, rax
    call sw_cleanup_latch
2:  xor eax, eax
    EPILOGUE
3:  call ext_store_job_retire_wait
    mov rdi, rbx
    call sw_cleanup_candidate
    jmp .Lswo_guard_cleanup
