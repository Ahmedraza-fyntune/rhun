# Worker prepare/commit phases. One native issue per accepted complete COMMIT frame.
.include "rhun.inc"
.include "app/extsettingsworker.inc"
.text
FN sw_announced_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + ECS_exists]
    cmp [rbx + SW_announced_exists], rax
    jne 2f
    mov rax, [r12 + ECS_length]
    cmp [rbx + SW_announced_length], rax
    jne 2f
    lea rdi, [rbx + SW_announced_digest]
    lea rsi, [r12 + ECS_digest]
    mov edx, 32
    call memeq
    test eax, eax
    jz 2f
    xor eax, eax
    EPILOGUE
2:  mov rax, -116
    EPILOGUE

# prepare(ctx,initialSave0|1)->0/-errno, retaining candidate through every failure.
FN sw_prepare
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + SW_guard]
    call ext_choices_begin_try
    mov [rbx + SW_candidate], rax
    mov r13, rax
    mov r14, rdx
    mov rdi, rbx
    mov rsi, r8
    call sw_cleanup_latch
    test r13, r13
    jz .Lswp_error
    test r14, r14
    js .Lswp_error
    mov rdi, r13
    lea rsi, [rbx + SW_request + SWR_delta]
    mov rdx, [rbx + SW_request + SWR_count]
    call ext_choices_prepare_try
    mov r14, rax
    mov rdi, rbx
    mov rsi, rdx
    call sw_cleanup_latch
    # The merger owns its complete result; no EC span is used after prepare returns.
    mov rdi, rbx
    call sw_body_free
    test r14, r14
    jnz .Lswp_error
    mov rdi, rbx
    mov rsi, [r13 + ECP_old]
    test r12, r12
    jz 1f
    call sw_baseline_check
    jmp 2f
1:  call sw_announced_check
2:  test rax, rax
    js .Lswp_return
    mov qword ptr [rbx + SW_idle_hold], 0
    mov rdi, rbx
    call sw_deadline_set
    test r12, r12
    jz 3f
    mov rdi, rbx
    mov rsi, [r13 + ECP_old]
    mov rdx, [rbx + SW_round]
    call sw_emit_snapshot
    test rax, rax
    js .Lswp_return
    mov rdi, rbx
    mov rsi, [r13 + ECP_old]
    call sw_announce
3:  mov rdi, rsp
    lea rsi, [r13 + ECP_digest]
    mov edx, 32
    call memcpy
    mov rax, [r13 + ECP_length]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    mov rdi, rbx
    mov esi, EW_PREPARED
    mov edx, 48
    mov rcx, [rbx + SW_round]
    call sw_emit_header
    test rax, rax
    js .Lswp_return
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 48
    call sw_emit_payload
    test rax, rax
    js .Lswp_return
    mov rdi, rbx
    call sw_deadline_set
    xor eax, eax
.Lswp_return:
    EPILOGUE
.Lswp_error:
    mov rax, r14
    test rax, rax
    js .Lswp_return
    mov rax, -5
    EPILOGUE

FN sw_emit_discarded
    PROLOGUE 32
    mov rbx, rdi
    call sw_deadline_set
    mov qword ptr [rsp], SW_DISCARDED
    mov qword ptr [rsp + 8], 0
    mov rax, [rbx + SW_cleanup]
    mov [rsp + 16], rax
    mov rax, [rbx + SW_observation]
    mov [rsp + 24], rax
    mov rdi, rbx
    mov esi, EW_DISCARDED
    mov edx, 32
    mov rcx, [rbx + SW_round]
    call sw_emit_header
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 32
    call sw_emit_payload
9:  EPILOGUE

# commit(ctx)->0after complete receipt+candidate cleanup/-errno with precise SW result.
FN sw_commit
    PROLOGUE 48
    mov rbx, rdi
    mov r12, [rbx + SW_candidate]
    mov rdi, r12
    lea rsi, [rip + sw_fresh]
    mov rdx, rbx
    call ext_choices_commit_try
.Lswc_poll:
    cmp qword ptr [r12 + ECP_state], ECP_PENDING
    jne .Lswc_complete
    call ext_store_job_retire_wait
    mov rdi, r12
    call ext_choices_commit_poll
    jmp .Lswc_poll
.Lswc_complete:
    mov rdi, rbx
    mov rsi, [r12 + ECP_cleanup_error]
    call sw_cleanup_latch
    mov rax, [r12 + ECP_observation]
    mov [rbx + SW_observation], rax
    cmp qword ptr [r12 + ECP_state], ECP_COMMITTED
    jne .Lswc_not_committed
    cmp qword ptr [r12 + ECP_result], 0
    jne .Lswc_uncertain
    mov qword ptr [rbx + SW_state], SW_COMMITTED
    mov qword ptr [rbx + SW_primary], 0
    mov qword ptr [rbx + SW_idle_hold], 0
    mov rdi, rbx
    call sw_deadline_set
    mov rdi, rbx
    mov esi, EW_COMMITTED
    mov rdx, [r12 + ECP_length]
    add rdx, 80
    mov rcx, [rbx + SW_round]
    call sw_emit_header
    test rax, rax
    js .Lswc_return
    mov rdi, rbx
    lea rsi, [rbx + SW_result]
    mov edx, 32
    call sw_emit_payload
    test rax, rax
    js .Lswc_return
    mov qword ptr [rsp], 1       # committed target exists, including an empty new file.
    mov rax, [r12 + ECP_length]
    mov [rsp + 8], rax
    lea rdi, [rsp + 16]
    lea rsi, [r12 + ECP_digest]
    mov edx, 32
    call memcpy
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 48
    call sw_emit_payload
    test rax, rax
    js .Lswc_return
    mov rdi, rbx
    mov rsi, [r12 + ECP_bytes]
    mov rdx, [r12 + ECP_length]
    call sw_emit_payload
    test rax, rax
    js .Lswc_return
    mov qword ptr [rbx + SW_announced_exists], 1
    mov rax, [r12 + ECP_length]
    mov [rbx + SW_announced_length], rax
    lea rdi, [rbx + SW_announced_digest]
    lea rsi, [r12 + ECP_digest]
    mov edx, 32
    call memcpy
    mov rdi, rbx
    call sw_cleanup_candidate
    xor eax, eax
.Lswc_return:
    EPILOGUE
.Lswc_not_committed:
    cmp qword ptr [r12 + ECP_state], ECP_FAILED
    jne .Lswc_uncertain
    mov qword ptr [rbx + SW_state], SW_PRECOMMIT_FAILED
    mov rax, [r12 + ECP_result]
    test rax, rax
    js 1f
    mov rax, -5
1:  mov [rbx + SW_primary], rax
    EPILOGUE
.Lswc_uncertain:
    mov qword ptr [rbx + SW_state], SW_UNCERTAIN
    mov rax, [r12 + ECP_result]
    test rax, rax
    js 2f
    mov rax, -117
2:  mov [rbx + SW_primary], rax
    EPILOGUE
