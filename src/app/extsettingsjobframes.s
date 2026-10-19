# Fixed receive-state checks and incremental snapshot digest verification.
.include "rhun.inc"
.include "app/extsettingsjob.inc"
.text
FN ecj_row
    imul rax, [rdi + ECJ_round], ECJ_ROW
    lea rax, [rdi + rax + ECJ_ledger]
    ret

# Complete frame becomes independently owned by the one-slot delivery mailbox.
ecj_deliver:
    mov rax, [rdi + ECJ_rx]
    mov qword ptr [rax + EJF_sealed], 1
    mov [rdi + ECJ_delivery], rax
    mov qword ptr [rdi + ECJ_rx], 0
    mov qword ptr [rdi + ECJ_rx_offset], 0
    mov qword ptr [rdi + ECJ_hash_active], 0
    xor eax, eax
    ret

# Validated receipt diagnostics also govern the job's clean publication boundary.
# They initiate retirement without changing an already proven COMMITTED outcome.
# diagnostics(job,cleanup,observation). No native operation is issued here.
ecj_receipt_diagnostics:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ecj_cleanup
    mov rdi, rbx
    mov rsi, r13
    call ecj_observation
    mov rsi, r12
    test rsi, rsi
    js 1f
    mov rsi, r13
    test rsi, rsi
    jns 2f
1:  mov rdi, rbx
    xor edx, edx
    call ecj_error
2:  xor eax, eax
    EPILOGUE

# validate(job)->0accepted/hashstarted or-EPROTO. Complete owned body only.
FN ecj_receive_validate
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + ECJ_rx]
    test r12, r12
    jz .Lecjv_bad
    cmp qword ptr [rbx + ECJ_result_seen], 0
    jne .Lecjv_bad
    cmp qword ptr [rbx + ECJ_delivery], 0
    jne .Lecjv_bad
    mov rax, [r12 + EJF_round]
    cmp [rbx + ECJ_round], rax
    jne .Lecjv_bad
    call ecj_row
    mov r14, rax
    mov rax, [r12 + EJF_kind]
    cmp rax, EW_SNAPSHOT
    je .Lecjv_snapshot
    cmp rax, EW_COMMITTED
    je .Lecjv_committed
    cmp rax, EW_PREPARED
    je .Lecjv_prepared
    cmp rax, EW_DISCARDED
    je .Lecjv_discarded
    cmp rax, EW_RESULT
    je .Lecjv_result
    jmp .Lecjv_bad
.Lecjv_snapshot:
    mov rax, [rbx + ECJ_phase]
    cmp rax, ECJP_READ_SNAPSHOT
    jb .Lecjv_bad
    cmp rax, ECJP_TX_SNAPSHOT
    ja .Lecjv_bad
    mov r13d, 48
    jmp .Lecjv_snapshot_prefix
.Lecjv_committed:
    cmp qword ptr [rbx + ECJ_phase], ECJP_COMMIT
    jne .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_POSSIBLE
    jz .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_COMMITTED
    jnz .Lecjv_bad
    cmp qword ptr [r12 + EJF_body], ECJS_COMMITTED
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 8], 0
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 16], 0
    jg .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 24], 0
    jg .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 32], 1
    jne .Lecjv_bad
    mov r13d, 80
.Lecjv_snapshot_prefix:
    lea r15, [r12 + EJF_body + r13 - 48]
    mov eax, [r15]
    cmp eax, 1
    ja .Lecjv_bad
    cmp dword ptr [r15 + 4], 0
    jne .Lecjv_bad
    mov rdx, [r15 + 8]
    cmp rdx, 1048576
    ja .Lecjv_bad
    test eax, eax
    jnz 1f
    test rdx, rdx
    jnz .Lecjv_bad
1:  lea rcx, [rdx + r13]
    cmp [r12 + EJF_length], rcx
    jne .Lecjv_bad
    cmp r13, 80
    jne 2f
    cmp [r14 + ECJR_length], rdx
    jne .Lecjv_bad
2:  mov [rbx + ECJ_hash_length], rdx
    mov [rbx + ECJ_hash_start], r13
    mov qword ptr [rbx + ECJ_hash_offset], 0
    mov qword ptr [rbx + ECJ_hash_active], 1
    lea rdi, [rbx + ECJ_sha]
    call sha256_init
    xor eax, eax
    EPILOGUE
.Lecjv_prepared:
    cmp qword ptr [rbx + ECJ_phase], ECJP_PREPARATION
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 40], 0
    jne .Lecjv_bad
    mov rax, [r12 + EJF_body + 32]
    cmp rax, 1048576
    ja .Lecjv_bad
    mov [r14 + ECJR_length], rax
    lea rdi, [r14 + ECJR_digest]
    lea rsi, [r12 + EJF_body]
    mov edx, 32
    call memcpy
    or qword ptr [r14 + ECJR_flags], ECJR_PREPARED
    mov qword ptr [rbx + ECJ_phase], ECJP_PREPARED
    mov rax, [rbx + ECJ_now]
    add rax, 10000
    mov [rbx + ECJ_deadline], rax
    mov rdi, rbx
    call ecj_deliver
    EPILOGUE
.Lecjv_discarded:
    cmp qword ptr [rbx + ECJ_phase], ECJP_ABORT
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body], 6
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 8], 0
    jne .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 16], 0
    jg .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 24], 0
    jg .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_POSSIBLE
    jnz .Lecjv_bad
    or qword ptr [r14 + ECJR_flags], ECJR_DISCARDED
    mov qword ptr [r14 + ECJR_state], 6
    mov rax, [r12 + EJF_body + 16]
    mov [r14 + ECJR_cleanup], rax
    mov rax, [r12 + EJF_body + 24]
    mov [r14 + ECJR_observation], rax
    mov qword ptr [rbx + ECJ_phase], ECJP_IDLE
    mov qword ptr [rbx + ECJ_deadline], 0
    mov rdi, rbx
    mov rsi, [r14 + ECJR_cleanup]
    mov rdx, [r14 + ECJR_observation]
    call ecj_receipt_diagnostics
    mov rdi, rbx
    call ecj_deliver
    EPILOGUE
.Lecjv_result:
    cmp qword ptr [r12 + EJF_body + 16], 0
    jg .Lecjv_bad
    cmp qword ptr [r12 + EJF_body + 24], 0
    jg .Lecjv_bad
    mov rax, [r12 + EJF_body]
    mov rdx, [r12 + EJF_body + 8]
    cmp rax, ECJS_READ_OK
    je .Lecjv_read_ok
    cmp rax, ECJS_COMMITTED
    je .Lecjv_commit_ok
    test rdx, rdx
    jns .Lecjv_bad
    cmp rax, ECJS_PRECOMMIT_FAILED
    je .Lecjv_definite
    cmp rax, ECJS_UNCERTAIN
    je .Lecjv_uncertain
    cmp rax, ECJS_CANCELED
    jne .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_DISCARDED
    jz .Lecjv_bad
    cmp qword ptr [rbx + ECJ_phase], ECJP_RELEASE
    je .Lecjv_result_accept
    cmp qword ptr [rbx + ECJ_closing], 0
    je .Lecjv_bad
    jmp .Lecjv_result_accept
.Lecjv_read_ok:
    test rdx, rdx
    jnz .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_SNAPSHOT
    jz .Lecjv_bad
    cmp qword ptr [rbx + ECJ_round], 0
    jne .Lecjv_bad
    cmp qword ptr [rbx + ECJ_mode], 1
    je .Lecjv_result_accept
    cmp qword ptr [rbx + ECJ_mode], 3
    jne .Lecjv_bad
    cmp qword ptr [rbx + ECJ_phase], ECJP_RELEASE
    je .Lecjv_result_accept
    cmp qword ptr [rbx + ECJ_closing], 0
    je .Lecjv_bad
    jmp .Lecjv_result_accept
.Lecjv_commit_ok:
    test rdx, rdx
    jnz .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_COMMITTED
    jz .Lecjv_bad
    cmp qword ptr [rbx + ECJ_phase], ECJP_RELEASE
    je .Lecjv_result_accept
    cmp qword ptr [rbx + ECJ_closing], 0
    jne .Lecjv_result_accept
    cmp qword ptr [r12 + EJF_body + 16], 0
    js .Lecjv_result_accept
    cmp qword ptr [r12 + EJF_body + 24], 0
    jns .Lecjv_bad
    jmp .Lecjv_result_accept
.Lecjv_definite:
    test qword ptr [r14 + ECJR_flags], ECJR_COMMITTED
    jnz .Lecjv_bad
    jmp .Lecjv_result_accept
.Lecjv_uncertain:
    test qword ptr [r14 + ECJR_flags], ECJR_POSSIBLE
    jz .Lecjv_bad
    test qword ptr [r14 + ECJR_flags], ECJR_COMMITTED
    jnz .Lecjv_bad
.Lecjv_result_accept:
    mov [rbx + ECJ_result_state], rax
    mov [rbx + ECJ_result_primary], rdx
    mov rax, [r12 + EJF_body + 16]
    mov [rbx + ECJ_result_cleanup], rax
    mov rax, [r12 + EJF_body + 24]
    mov [rbx + ECJ_result_observation], rax
    mov qword ptr [rbx + ECJ_result_seen], 1
    mov qword ptr [rbx + ECJ_phase], ECJP_RESULT
    mov rdi, r12
    call ext_settings_frame_free
    cmp rcx, 1
    jne .Lecjv_bad
    mov rdi, rbx
    mov rsi, rdx
    call ecj_cleanup
    mov qword ptr [rbx + ECJ_rx], 0
    mov qword ptr [rbx + ECJ_rx_offset], 0
    xor eax, eax
    EPILOGUE
.Lecjv_bad:
    mov rax, -71
    EPILOGUE

# hash_step(job,budget1..65536)->0pending/1delivered/-EPROTO,RDX charged hash bytes.
FN ecj_hash_step
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov qword ptr [rsp + 32], 0
    cmp qword ptr [rbx + ECJ_hash_active], 1
    jne .Lecjh_bad
    test r12, r12
    jz .Lecjh_bad
    cmp r12, 65536
    ja .Lecjh_bad
    mov r13, [rbx + ECJ_rx]
    test r13, r13
    jz .Lecjh_bad
    mov r14, [rbx + ECJ_hash_length]
    sub r14, [rbx + ECJ_hash_offset]
    jc .Lecjh_bad
    cmp r14, r12
    cmova r14, r12
    test r14, r14
    jz .Lecjh_final
    mov rax, [rbx + ECJ_hash_start]
    add rax, [rbx + ECJ_hash_offset]
    lea rsi, [r13 + EJF_body + rax]
    lea rdi, [rbx + ECJ_sha]
    mov rdx, r14
    call sha256_update
    test eax, eax
    jz .Lecjh_bad
    add [rbx + ECJ_hash_offset], r14
    mov [rsp + 32], r14
    mov rax, [rbx + ECJ_hash_offset]
    cmp rax, [rbx + ECJ_hash_length]
    je .Lecjh_final
    xor eax, eax
    mov rdx, [rsp + 32]
    EPILOGUE
.Lecjh_final:
    lea rdi, [rbx + ECJ_sha]
    mov rsi, rsp
    call sha256_final
    test eax, eax
    jz .Lecjh_bad
    mov rax, [rbx + ECJ_hash_start]
    lea rdi, [r13 + EJF_body + rax - 32]
    mov rsi, rsp
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lecjh_bad
    mov rdi, rbx
    call ecj_row
    mov r14, rax
    cmp qword ptr [r13 + EJF_kind], EW_COMMITTED
    je .Lecjh_committed
    or qword ptr [r14 + ECJR_flags], ECJR_SNAPSHOT
    mov rax, [rbx + ECJ_phase]
    cmp rax, ECJP_SAVE_SNAPSHOT
    je .Lecjh_save
    cmp rax, ECJP_TX_SNAPSHOT
    je .Lecjh_idle
    cmp rax, ECJP_READ_SNAPSHOT
    jne .Lecjh_bad
    mov qword ptr [rbx + ECJ_phase], ECJP_RESULT
    jmp .Lecjh_deliver
.Lecjh_save:
    mov qword ptr [rbx + ECJ_phase], ECJP_PREPARATION
    jmp .Lecjh_deliver
.Lecjh_committed:
    lea rdi, [r14 + ECJR_digest]
    mov rsi, rsp
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lecjh_bad
    or qword ptr [r14 + ECJR_flags], ECJR_COMMITTED
    mov qword ptr [r14 + ECJR_state], ECJS_COMMITTED
    mov rax, [r13 + EJF_body + 16]
    mov [r14 + ECJR_cleanup], rax
    mov rax, [r13 + EJF_body + 24]
    mov [r14 + ECJR_observation], rax
    mov qword ptr [rbx + ECJ_state], ECJS_COMMITTED
    mov rdi, rbx
    mov rsi, [r14 + ECJR_cleanup]
    mov rdx, [r14 + ECJR_observation]
    call ecj_receipt_diagnostics
.Lecjh_idle:
    mov qword ptr [rbx + ECJ_phase], ECJP_IDLE
    mov qword ptr [rbx + ECJ_deadline], 0
.Lecjh_deliver:
    mov rdi, rbx
    call ecj_deliver
    mov eax, 1
    mov rdx, [rsp + 32]
    EPILOGUE
.Lecjh_bad:
    mov rax, -71
    mov rdx, [rsp + 32]
    EPILOGUE
