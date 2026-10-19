# Private worker transport and native candidate retirement. Never UI callbacks.
.include "rhun.inc"
.include "app/extsettingsworker.inc"
.text
FN sw_deadline_set
    PROLOGUE
    mov rbx, rdi
    call time_ms
    add rax, 10000
    jnc 1f
    mov rax, -1
1:  mov [rbx + SW_deadline], rax
    xor eax, eax
    EPILOGUE
FN sw_deadline_check
    PROLOGUE
    mov rbx, rdi
    call time_ms
    cmp rax, [rbx + SW_deadline]
    jae 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -110
    EPILOGUE

# exact_read(ctx,bytes,count)->0,1EOF before any byte,-71 partialEOF/-errno.
# Only idle WAIT_NEXT may suspend the deadline until its first command byte.
FN sw_read_exact
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, r13
    jae 6f
    cmp qword ptr [rbx + SW_idle_hold], 1
    je 2f
    mov rdi, rbx
    call sw_deadline_check
    test rax, rax
    js 9f
2:  lea rdi, [rbx + SW_io]
    lea rsi, [r12 + r14]
    mov r15, r13
    sub r15, r14
    cmp r15, 65536
    jbe 3f
    mov r15d, 65536
3:  mov rdx, r15
    call ext_settings_worker_io_read
    cmp rax, -11
    je 7f
    cmp rax, -4
    je 7f
    test rax, rax
    js 9f
    jz 8f
    cmp rax, r15
    ja .Lsw_read_bad
    add r14, rax
    cmp qword ptr [rbx + SW_idle_hold], 1
    jne 1b
    mov qword ptr [rbx + SW_idle_hold], 0
    mov rdi, rbx
    call sw_deadline_set
    jmp 1b
6:  xor eax, eax
9:  EPILOGUE
7:  call ext_store_job_retire_wait
    jmp 1b
8:  test r14, r14
    jnz .Lsw_read_bad
    mov eax, 1
    EPILOGUE
.Lsw_read_bad:
    mov rax, -71
    EPILOGUE

# send_exact(ctx,bytes,count)->0/-errno. Caller sets a finite delivery deadline.
FN sw_send_exact
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, r13
    jae 6f
    mov rdi, rbx
    call sw_deadline_check
    test rax, rax
    js 9f
    mov r15, r13
    sub r15, r14
    cmp r15, 65536
    jbe 2f
    mov r15d, 65536
2:  lea rdi, [rbx + SW_io]
    lea rsi, [r12 + r14]
    mov rdx, r15
    call ext_settings_worker_io_write
    cmp rax, -11
    je 7f
    cmp rax, -4
    je 7f
    test rax, rax
    jle 8f
    cmp rax, r15
    ja 8f
    add r14, rax
    jmp 1b
6:  xor eax, eax
9:  EPILOGUE
7:  call ext_store_job_retire_wait
    jmp 1b
8:  mov rax, -5
    EPILOGUE

FN sw_body_free
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + SW_body]
    mov qword ptr [rbx + SW_body], 0
    mov qword ptr [rbx + SW_length], 0
    call mem_free
    EPILOGUE

# read_frame(ctx)->0,1cleanEOF,-errno; owned body survives every error until cleanup.
FN sw_read_frame
    PROLOGUE
    mov rbx, rdi
    call sw_body_free
    mov rdi, rbx
    lea rsi, [rbx + SW_header]
    mov edx, EW_HEADER
    call sw_read_exact
    test rax, rax
    jnz 9f
    lea rdi, [rbx + SW_header]
    mov rsi, rbx
    call ext_settings_wire_check
    test rax, rax
    js 9f
    mov [rbx + SW_kind], rdx
    mov [rbx + SW_length], r8
    mov [rbx + SW_frame_round], r9
    test r8, r8
    jz 9f
    mov rdi, r8
    call mem_alloc_try
    test rax, rax
    jz 8f
    mov [rbx + SW_body], rax
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rbx + SW_length]
    call sw_read_exact
    cmp rax, 1
    jne 9f
    mov rax, -71
9:  EPILOGUE
8:  mov rax, -12
    EPILOGUE

# emit_header(ctx,kind,bodylen,round)->0/-errno.
FN sw_emit_header
    PROLOGUE
    mov rbx, rdi
    mov [rbx + SW_encoder + EWE_tag], rdi
    mov [rbx + SW_encoder + EWE_kind], rsi
    mov [rbx + SW_encoder + EWE_length], rdx
    mov [rbx + SW_encoder + EWE_round], rcx
    lea rdi, [rbx + SW_header]
    lea rsi, [rbx + SW_encoder]
    call ext_settings_wire_encode
    test rax, rax
    js 9f
    mov rdi, rbx
    lea rsi, [rbx + SW_header]
    mov edx, EW_HEADER
    call sw_send_exact
9:  test rax, rax
    jns 8f
    mov qword ptr [rbx + SW_transport_failed], 1
8:  EPILOGUE

# emit_payload(ctx,bytes,count)->0/-errno; no more frames after any partial send error.
FN sw_emit_payload
    PROLOGUE
    mov rbx, rdi
    call sw_send_exact
    test rax, rax
    jns 1f
    mov qword ptr [rbx + SW_transport_failed], 1
1:  EPILOGUE

# emit_snapshot(ctx,ECS,round)->0/-errno. Prefix48 then complete immutable bytes.
FN sw_emit_snapshot
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov esi, EW_SNAPSHOT
    mov rdx, [r12 + ECS_length]
    add rdx, 48
    mov rcx, r13
    call sw_emit_header
    test rax, rax
    js 9f
    mov rax, [r12 + ECS_exists]
    mov [rsp], rax
    mov rax, [r12 + ECS_length]
    mov [rsp + 8], rax
    lea rdi, [rsp + 16]
    lea rsi, [r12 + ECS_digest]
    mov edx, 32
    call memcpy
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 48
    call sw_emit_payload
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, [r12 + ECS_bytes]
    mov rdx, [r12 + ECS_length]
    call sw_emit_payload
9:  EPILOGUE

# Remember last announced complete file authority while retaining its config EX guard.
FN sw_announce
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + ECS_exists]
    mov [rbx + SW_announced_exists], rax
    mov rax, [r12 + ECS_length]
    mov [rbx + SW_announced_length], rax
    lea rdi, [rbx + SW_announced_digest]
    lea rsi, [r12 + ECS_digest]
    mov edx, 32
    call memcpy
    EPILOGUE

# baseline(ctx,ECS)->0/-ESTALE. Explicit reconciliation is bound to this locked file.
FN sw_baseline_check
    cmp qword ptr [rdi + SW_request + SWR_flags], 0
    je 1f
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rsi + ECS_exists]
    cmp [rbx + SW_request + SWR_exists], rax
    jne 2f
    lea rdi, [rbx + SW_request + SWR_digest]
    lea rsi, [r12 + ECS_digest]
    mov edx, 32
    call memeq
    test eax, eax
    jz 2f
    xor eax, eax
    EPILOGUE
2:  mov rax, -116
    EPILOGUE
1:  xor eax, eax
    ret

# Compiled-in pure pre-issue predicate, called after every blocking native recheck.
FN sw_fresh
    PROLOGUE
    mov rbx, rdi
    call sw_deadline_check
    test rax, rax
    js 1f
    lea rdi, [rbx + SW_io]
    call ext_settings_worker_io_probe
1:  EPILOGUE

# cleanup_candidate(ctx)->0. Actual pending publication/delete/security owns its storage.
# Diagnostic errors are latched separately; neither deadline nor control EOF ends this loop.
FN sw_cleanup_candidate
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + SW_candidate]
    test r12, r12
    jz 8f
1:  cmp qword ptr [r12 + ECP_state], ECP_PENDING
    jne 2f
    mov rdi, r12
    call ext_choices_commit_poll
    test rdx, rdx
    jns 3f
    mov [rbx + SW_observation], rdx
3:  cmp qword ptr [r12 + ECP_state], ECP_PENDING
    je 7f
2:  mov rdi, r12
    call ext_choices_cleanup_step
    test rdx, rdx
    jns 4f
    cmp qword ptr [rbx + SW_cleanup], 0
    jne 4f
    mov [rbx + SW_cleanup], rdx
4:  cmp rax, -115
    je 7f
    test rax, rax
    jnz 7f
    # cleanup0 plus nonpending state prove free's consuming preconditions.
    mov qword ptr [rbx + SW_candidate], 0
    mov rdi, r12
    call ext_choices_free
    test rax, rax
    jns 8f
    cmp qword ptr [rbx + SW_cleanup], 0
    jne 8f
    mov [rbx + SW_cleanup], rax
    jmp 8f
7:  call ext_store_job_retire_wait
    jmp 1b
8:  xor eax, eax
    EPILOGUE

# A completed terminal command may be followed by quiet input or EOF, never more bytes.
FN sw_terminal_probe
    PROLOGUE
    lea rdi, [rdi + SW_io]
    call ext_settings_worker_io_probe
    cmp rax, -125
    jne 1f
    xor eax, eax
1:  EPILOGUE
