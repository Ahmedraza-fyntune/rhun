# One native replacement, exact ambiguous-error reconciliation, no inverse or blind retry.
.include "rhun.inc"
.include "app/extchoicesdisk.inc"
.section .rodata
.Lecc_final: .asciz "extensions.ini"
.text

# matches_old(ECP,ECR)->1/0, comparing complete bytes and existence, not only a digest.
ecc_matches_old:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + ECP_old]
    mov rax, [r13 + ECS_exists]
    cmp [r12 + ECR_exists], rax
    jne 1f
    mov rdx, [r13 + ECS_length]
    cmp [r12 + ECR_length], rdx
    jne 1f
    mov rdi, [rbx + ECP_scratch]
    mov rsi, [r13 + ECS_bytes]
    call memeq
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

# Terminal result helper, called only after actual native completion is established.
ecc_finish:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jnz .Lecc_reconcile
    mov qword ptr [rbx + ECP_consumed], 1
    jmp .Lecc_committed
.Lecc_reconcile:
    mov [rbx + ECP_native_error], r12
    mov rdi, rbx
    mov rsi, rsp
    call ext_choices_read_final
    test rax, rax
    js .Lecc_reconcile_error
    cmp qword ptr [rsp + ECR_exists], 1
    jne .Lecc_old
    mov rdx, [rbx + ECP_length]
    cmp [rsp + ECR_length], rdx
    jne .Lecc_old
    mov rdi, [rbx + ECP_scratch]
    mov rsi, [rbx + ECP_bytes]
    call memeq
    test eax, eax
    jz .Lecc_old
    lea rdi, [rsp + ECR_identity]
    lea rsi, [rbx + ECP_identity]
    mov edx, 32
    call memeq
    mov [rbx + ECP_consumed], rax
.Lecc_committed:
    mov qword ptr [rbx + ECP_state], ECP_COMMITTED
    mov qword ptr [rbx + ECP_result], 0
    xor eax, eax
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_old:
    mov rdi, rbx
    mov rsi, rsp
    call ecc_matches_old
    test eax, eax
    jz .Lecc_uncertain
    mov qword ptr [rbx + ECP_state], ECP_FAILED
    mov [rbx + ECP_result], r12
    mov rax, r12
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_reconcile_error:
    mov [rbx + ECP_reconcile_error], rax
    mov rdi, rbx
    mov rsi, rax
    call ext_choices_record_cleanup
.Lecc_uncertain:
    mov qword ptr [rbx + ECP_state], ECP_UNCERTAIN
    mov qword ptr [rbx + ECP_result], -117
    mov rax, [rbx + ECP_guard]
    mov qword ptr [rax + ECG_uncertain], 1
    mov rax, -117
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE

# commit_try(ECP,pureFreshFn,user)->0/-errno,RDX cleanup/observation diagnostic.
# Callback(user) runs only before publication; zero accepts, negative refuses.
FN ext_choices_commit_try
    test rdi, rdi
    jz .Lecc_invalid
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rbx + ECP_state], ECP_COMMITTED
    jae .Lecc_stored
    cmp qword ptr [rbx + ECP_state], ECP_PENDING
    je .Lecc_pending_stored
    cmp qword ptr [rbx + ECP_state], ECP_PREPARED
    jne .Lecc_invalid_owned
    mov rdi, rbx
    call ext_choices_current
    test eax, eax
    jz .Lecc_stale
    mov rdi, rbx
    mov rsi, rsp
    call ext_choices_read_final
    test rax, rax
    js .Lecc_fail_secondary
    mov rdi, rbx
    mov rsi, rsp
    call ecc_matches_old
    test eax, eax
    jz .Lecc_changed
    cmp qword ptr [rbx + ECP_noop], 1
    je .Lecc_final_fresh
    mov rdi, rbx
    call ext_choices_stage_check
    test rax, rax
    js .Lecc_fail_secondary
.Lecc_final_fresh:
    # Rechecks above may block. Freshness must be the final pre-issue decision.
    test r12, r12
    jz 1f
    mov rdi, r13
    call r12
    test rax, rax
    js .Lecc_fail
    jnz .Lecc_invalid_attempt
1:  cmp qword ptr [rbx + ECP_noop], 1
    je .Lecc_noop
    # Persistent request bytes are initialized before issuing any operation.
    mov qword ptr [rbx + ECP_iosb], 0x103
    mov qword ptr [rbx + ECP_iosb + 8], 0
    mov rax, [rbx + ECP_guard]
    mov rdi, [rax + ECG_root]
    lea rsi, [rbx + ECP_name]
    lea rdx, [rip + .Lecc_final]
    mov rcx, [rbx + ECP_source]
    lea r8, [rbx + ECP_rename]
    lea r9, [rbx + ECP_iosb]
    call ext_choices_raw_replace
.ifdef WINDOWS
    cmp rax, -115
    je .Lecc_issued_pending
.endif
    mov rdi, rbx
    mov rsi, rax
    call ecc_finish
    EPILOGUE
.Lecc_noop:
    mov qword ptr [rbx + ECP_state], ECP_COMMITTED
    mov qword ptr [rbx + ECP_result], 0
    xor eax, eax
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_issued_pending:
    mov qword ptr [rbx + ECP_state], ECP_PENDING
.Lecc_pending_stored:
    mov rax, -115
    mov rdx, [rbx + ECP_observation]
    EPILOGUE
.Lecc_stored:
    mov rax, [rbx + ECP_result]
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_changed:
    mov rax, -11
    jmp .Lecc_fail
.Lecc_stale:
    mov rax, -116
    jmp .Lecc_fail
.Lecc_invalid_attempt:
    mov rax, -22
    jmp .Lecc_fail
.Lecc_fail_secondary:
    mov r12, rax
    mov rdi, rbx
    mov rsi, rdx
    xor edx, edx
    call ext_choices_record_cleanup
    mov rax, r12
.Lecc_fail:
    mov [rbx + ECP_result], rax
    mov qword ptr [rbx + ECP_state], ECP_FAILED
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
.Lecc_invalid_owned:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lecc_invalid:
    mov rax, -22
    xor edx, edx
    ret

# commit_poll(ECP)->0/completed-error/-115,RDX observation failure while retained.
FN ext_choices_commit_poll
    test rdi, rdi
    jz .Lecc_invalid
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + ECP_state], ECP_PENDING
    jne 2f
    mov rdi, [rbx + ECP_source]
    lea rsi, [rbx + ECP_iosb]
    call ext_choices_raw_replace_poll
    cmp rax, -115
    jne 1f
    test rdx, rdx
    jns 3f
    mov [rbx + ECP_observation], rdx
3:  mov rdx, [rbx + ECP_observation]
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, rax
    call ecc_finish
    EPILOGUE
2:  cmp qword ptr [rbx + ECP_state], ECP_COMMITTED
    jb 4f
    mov rax, [rbx + ECP_result]
    mov rdx, [rbx + ECP_cleanup_error]
    EPILOGUE
4:  mov rax, -22
    xor edx, edx
    EPILOGUE
