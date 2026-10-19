.include "rhun.inc"
.include "app/extsettingsjob.inc"
.section .rodata
ecjf_tag: .quad 17,29,0,0
ecjf_payload: .ascii "hello"
ecjf_ok: .ascii "ok settings correlated receipts and incremental digest\n"
.text
ecjf_fail:
    mov edi, 74
    call sys_exit
# New complete receive frame for current owned context; body starts zeroed.
ecjf_frame:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + ecjf_tag]
    call ext_settings_frame_new
    test rax, rax
    jz ecjf_fail
    mov [rbx + ECJ_rx], rax
    EPILOGUE
# Complete any pending five-byte snapshot using exactly one payload-byte per step.
ecjf_hash:
    PROLOGUE
    mov rbx, rdi
    mov r12d, 5
1:  mov rdi, rbx
    mov esi, 1
    call ecj_hash_step
    cmp rdx, 1
    jne ecjf_fail
    dec r12
    jz 2f
    test rax, rax
    jnz ecjf_fail
    jmp 1b
2:  cmp rax, 1
    jne ecjf_fail
    EPILOGUE
FN main
    PROLOGUE 64
    mov r15, [rip + g_mem_live]
    mov edi, ECJ_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz ecjf_fail
    mov rbx, rax
    mov qword ptr [rbx + ECJ_mode], 1
    mov qword ptr [rbx + ECJ_phase], ECJP_READ_SNAPSHOT
    mov rdi, rbx
    mov esi, EW_SNAPSHOT
    mov edx, 53
    xor ecx, ecx
    call ecjf_frame
    mov r12, rax
    mov qword ptr [r12 + EJF_body], 1
    mov qword ptr [r12 + EJF_body + 8], 5
    lea rdi, [rip + ecjf_payload]
    mov esi, 5
    lea rdx, [r12 + EJF_body + 16]
    call sha256_hash
    cmp eax, 1
    jne ecjf_fail
    lea rdi, [r12 + EJF_body + 48]
    lea rsi, [rip + ecjf_payload]
    mov edx, 5
    call memcpy
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    jnz ecjf_fail
    cmp qword ptr [rbx + ECJ_hash_active], 1
    jne ecjf_fail
    mov rdi, rbx
    call ecjf_hash
    cmp qword ptr [rbx + ECJ_phase], ECJP_RESULT
    jne ecjf_fail
    mov rdi, rbx
    call ext_settings_job_take_frame
    cmp rax, r12
    jne ecjf_fail
    cmp qword ptr [rax + EJF_sealed], 1
    jne ecjf_fail
    mov rdi, rax
    call ext_settings_frame_free
    # A new SAVE round prepares the exact digest which COMMITTED must later prove.
    mov qword ptr [rbx + ECJ_mode], 2
    mov qword ptr [rbx + ECJ_round], 1
    mov qword ptr [rbx + ECJ_phase], ECJP_PREPARATION
    mov rdi, rbx
    mov esi, EW_PREPARED
    mov edx, 48
    mov ecx, 1
    call ecjf_frame
    mov r12, rax
    lea rdi, [rip + ecjf_payload]
    mov esi, 5
    lea rdx, [r12 + EJF_body]
    call sha256_hash
    mov qword ptr [r12 + EJF_body + 32], 5
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    jnz ecjf_fail
    cmp qword ptr [rbx + ECJ_phase], ECJP_PREPARED
    jne ecjf_fail
    mov rdi, rbx
    call ext_settings_job_take_frame
    mov rdi, rax
    call ext_settings_frame_free
    mov rdi, rbx
    call ecj_row
    or qword ptr [rax + ECJR_flags], ECJR_POSSIBLE
    mov qword ptr [rbx + ECJ_phase], ECJP_COMMIT
    mov rdi, rbx
    mov esi, EW_COMMITTED
    mov edx, 85
    mov ecx, 1
    call ecjf_frame
    mov r12, rax
    mov qword ptr [r12 + EJF_body], 3
    mov qword ptr [r12 + EJF_body + 16], -5
    mov qword ptr [r12 + EJF_body + 24], -6
    mov qword ptr [r12 + EJF_body + 32], 1
    mov qword ptr [r12 + EJF_body + 40], 5
    lea rdi, [rip + ecjf_payload]
    mov esi, 5
    lea rdx, [r12 + EJF_body + 48]
    call sha256_hash
    lea rdi, [r12 + EJF_body + 80]
    lea rsi, [rip + ecjf_payload]
    mov edx, 5
    call memcpy
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    jnz ecjf_fail
    mov rdi, rbx
    call ecjf_hash
    cmp qword ptr [rbx + ECJ_state], 3
    jne ecjf_fail
    cmp qword ptr [rbx + ECJ_phase], ECJP_IDLE
    jne ecjf_fail
    mov rdi, rbx
    call ecj_row
    test qword ptr [rax + ECJR_flags], ECJR_COMMITTED
    jz ecjf_fail
    mov rdi, rbx
    call ext_settings_job_take_frame
    mov rdi, rax
    call ext_settings_frame_free
    # A proven commit retains truth, but its diagnostics forbid a clean hold.
    mov qword ptr [rbx + ECJ_mode], 3
    mov qword ptr [rbx + ECJ_native], 1
    mov qword ptr [rbx + ECJ_authority], 1
    mov rdi, rbx
    mov rsi, rsp
    call ext_settings_job_status
    cmp qword ptr [rsp], ECJS_COMMITTED
    jne ecjf_fail
    cmp qword ptr [rsp + 8], 0
    jne ecjf_fail
    cmp qword ptr [rsp + 16], -5
    jne ecjf_fail
    cmp qword ptr [rsp + 24], -6
    jne ecjf_fail
    mov rdi, rbx
    call ext_settings_job_hold
    cmp rax, -16
    jne ecjf_fail
    cmp qword ptr [rbx + ECJ_closing], 1
    jne ecjf_fail
    mov qword ptr [rbx + ECJ_closing], 0
    mov qword ptr [rbx + ECJ_error], 0
    mov qword ptr [rbx + ECJ_cleanup], 0
    mov qword ptr [rbx + ECJ_observation], 0
    # A discarded round also exposes diagnostics before any index can be issued.
    mov qword ptr [rbx + ECJ_round], 2
    mov qword ptr [rbx + ECJ_phase], ECJP_ABORT
    mov rdi, rbx
    mov esi, EW_DISCARDED
    mov edx, 32
    mov ecx, 2
    call ecjf_frame
    mov qword ptr [rax + EJF_body], 6
    mov qword ptr [rax + EJF_body + 16], -12
    mov qword ptr [rax + EJF_body + 24], -13
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    jnz ecjf_fail
    mov rdi, rbx
    call ext_settings_job_take_frame
    mov rdi, rax
    call ext_settings_frame_free
    mov rdi, rbx
    mov rsi, rsp
    call ext_settings_job_status
    cmp qword ptr [rsp + 16], -12
    jne ecjf_fail
    cmp qword ptr [rsp + 24], -13
    jne ecjf_fail
    mov rdi, rbx
    call ext_settings_job_hold
    cmp rax, -16
    jne ecjf_fail
    cmp qword ptr [rbx + ECJ_closing], 1
    jne ecjf_fail
    mov qword ptr [rbx + ECJ_native], 0
    mov qword ptr [rbx + ECJ_closing], 0
    mov qword ptr [rbx + ECJ_error], 0
    mov qword ptr [rbx + ECJ_cleanup], 0
    mov qword ptr [rbx + ECJ_observation], 0
    # An old round's commit cannot qualify a new round's RESULT(COMMITTED).
    mov qword ptr [rbx + ECJ_round], 3
    mov qword ptr [rbx + ECJ_phase], ECJP_COMMIT
    mov rdi, rbx
    call ecj_row
    or qword ptr [rax + ECJR_flags], ECJR_POSSIBLE
    mov rdi, rbx
    mov esi, EW_RESULT
    mov edx, 32
    mov ecx, 3
    call ecjf_frame
    mov r12, rax
    mov qword ptr [r12 + EJF_body], 3
    mov rdi, rbx
    call ecj_receive_validate
    cmp rax, -71
    jne ecjf_fail
    cmp qword ptr [rbx + ECJ_result_seen], 0
    jne ecjf_fail
    mov qword ptr [r12 + EJF_body], 2
    mov qword ptr [r12 + EJF_body + 8], -125
    mov rdi, rbx
    call ecj_receive_validate
    test rax, rax
    jnz ecjf_fail
    cmp qword ptr [rbx + ECJ_result_state], 2
    jne ecjf_fail
    mov rdi, rbx
    call ecj_row
    test qword ptr [rax + ECJR_flags], ECJR_DEFINITE
    jnz ecjf_fail              # EOF/exit proof is still missing, so not definitive yet.
    mov rdi, rbx
    call ext_settings_memory_free
    test rax, rax
    jnz ecjf_fail
    call ext_settings_memory_total
    test rax, rax
    jnz ecjf_fail
    cmp [rip + g_mem_live], r15
    jne ecjf_fail
    mov edi, 1
    lea rsi, [rip + ecjf_ok]
    mov edx, 55
    call write_all
    xor eax, eax
    EPILOGUE
