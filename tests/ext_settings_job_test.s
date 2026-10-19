.include "rhun.inc"
.include "app/extsettingsjob.inc"
.section .rodata
ecjt_marker: .asciz "--extension-settings-worker"
ecjt_tag: .quad 17,29,0,0
ecjt_delta: .long 10,6,3,0
    .ascii "owner/toolpinnedyes"
.bss
ecjt_inject: .quad 0
ecjt_injected: .quad 0
.data
ecjt_sigact: .quad 1,0,0,0
.text
ecjt_fail:
    mov edi, 73
    call sys_exit
# frame(kind,length,round)->unsealed object.
ecjt_frame:
    PROLOGUE
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + ecjt_tag]
    call ext_settings_frame_new
    test rax, rax
    jz ecjt_fail
    EPILOGUE
# Empty current-round command; return a sealed owned object.
ecjt_empty:
    PROLOGUE
    xor esi, esi
    call ecjt_frame
    mov rbx, rax
    mov rdi, rax
    call ext_settings_frame_seal
    test rax, rax
    jnz ecjt_fail
    mov rax, rbx
    EPILOGUE
# One fault observation from the real retained child, without altering its authority.
FN ecjt_observation_poll
    PROLOGUE
    call ext_settings_native_poll
    cmp qword ptr [rip + ecjt_inject], 0
    je 1f
    cmp qword ptr [rip + ecjt_injected], 0
    jne 1f
    mov qword ptr [rip + ecjt_injected], 1
    mov rcx, -5
1:  EPILOGUE
FN main
    PROLOGUE 256
    mov edi, 13
    lea rsi, [rip + ecjt_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    cmp qword ptr [rip + g_argc], 2
    jb ecjt_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + ecjt_marker]
    call strcmp_eq
    test eax, eax
    jz .Lecjt_parent
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call ext_settings_worker_main
    EPILOGUE
.Lecjt_parent:
    cmp qword ptr [rip + g_argc], 5
    jne ecjt_fail
    call ecjf_null
    mov r15, [rip + g_mem_live]
    mov qword ptr [rsp + 232], 0
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call parse_u64
    cmp rax, 1048576
    ja ecjt_fail
    mov [rsp + 224], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 32]
    lea rsi, [rsp + 160]
    call ext_validate_unhex
    test rax, rax
    jnz ecjt_fail
    mov rax, [rip + g_argv]
    mov rbx, [rax + 8]
    mov rax, [rax + 16]
    mov [rsp + 72], rax
    mov rdi, rax
    call strlen
    cmp rax, 2
    ja ecjt_fail
    mov [rsp + 64], rax
    mov rsi, rax
    mov rdi, [rsp + 72]
    call parse_u64
    cmp rdx, [rsp + 64]
    jne ecjt_fail
    mov r14, rax
    cmp r14, 1
    jb ecjt_fail
    cmp r14, 14
    ja ecjt_fail
    mov rdi, rbx
    call strlen
    cmp rax, 4095
    ja ecjt_fail
    mov [rsp + 64], rax
    lea rsi, [rax + 56]
    cmp r14, 2
    je 1f
    cmp r14, 6
    je 1f
    cmp r14, 7
    je 1f
    cmp r14, 8
    je 1f
    cmp r14, 13
    jne 2f
1:  add rsi, 35
2:  mov edi, EW_REQUEST
    xor edx, edx
    call ecjt_frame
    mov r12, rax
    mov eax, 3
    cmp r14, 1
    je 7f
    cmp r14, 12
    jne 3f
7:  mov eax, 1
3:  cmp r14, 2
    je 4f
    cmp r14, 6
    je 4f
    cmp r14, 7
    je 4f
    cmp r14, 8
    je 4f
    cmp r14, 13
    jne 5f
4:  mov eax, 2
    mov dword ptr [r12 + EJF_body + 4], 1
5:  mov [r12 + EJF_body], eax
    mov rax, [rsp + 64]
    mov [r12 + EJF_body + 8], eax
    lea rdi, [r12 + EJF_body + 56]
    mov rsi, rbx
    mov rdx, rax
    call memcpy
    cmp dword ptr [r12 + EJF_body], 2
    jne 6f
    mov rax, [rsp + 64]
    lea rdi, [r12 + EJF_body + 56 + rax]
    lea rsi, [rip + ecjt_delta]
    mov edx, 35
    call memcpy
6:  mov rdi, r12
    call ext_settings_frame_seal
    test rax, rax
    jnz ecjt_fail
    mov rdi, r12
    call ext_settings_job_begin
    test rax, rax
    jz ecjt_fail
    test rdx, rdx
    jnz ecjt_fail
    mov r12, rax
    cmp qword ptr [r12 + ECJ_phase], ECJP_TERMINAL
    je ecjf_fail
    cmp qword ptr [r12 + ECJ_native], 0
    je ecjf_fail
    cmp qword ptr [r12 + ECJ_reservation], ESM_NATIVE_RESERVE
    jne ecjf_fail
    cmp qword ptr [r12 + ECJ_tx], 0
    je ecjf_fail
    mov rdi, r12
    call ecjf_busy
    mov rdi, r12
    xor esi, esi
    mov edx, 97
    mov ecx, 2
    call ext_settings_job_step
    cmp rax, -22
    jne ecjt_fail
    test rdx, rdx
    jnz ecjt_fail
    test rcx, rcx
    jnz ecjt_fail
    xor r13d, r13d                # A refused owned command stays here until accepted.
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0    # hold goal1, held2, released3
    mov qword ptr [rsp + 24], 0    # held observation count
    mov qword ptr [rsp + 32], 0    # test-only external kill issued
    call time_ms
    add rax, 20000
    mov [rsp], rax
.Lecjt_loop:
    call time_ms
    cmp rax, [rsp]
    jae ecjt_fail
    mov rsi, rax
    mov rdi, r12
    mov edx, 97
    cmp r14, 6
    je 7f
    cmp r14, 7
    jne 6f
7:  cmp qword ptr [r12 + ECJ_phase], ECJP_COMMIT
    jne 6f
    mov edx, 1
6:  cmp r14, 12
    jb 8f
    mov edx, 65536
8:  mov [rsp + 8], rdx
    mov ecx, 16
    cmp r14, 2
    jne 9f
    mov ecx, 8
9:  mov [rsp + 56], rcx
    call ext_settings_job_step
    cmp rdx, [rsp + 8]
    ja ecjt_fail
    cmp rcx, [rsp + 56]
    ja ecjt_fail
    test rax, rax
    js ecjt_fail
    cmp rax, 1
    je .Lecjt_terminal
    cmp r14, 6
    je 7f
    cmp r14, 7
    jne .Lecjt_pending_command
7:
    cmp qword ptr [rsp + 32], 0
    jne .Lecjt_pending_command
    cmp qword ptr [r12 + ECJ_possible], 0
    je .Lecjt_pending_command
    # Require actual positive, incomplete COMMIT delivery, not merely a copied queue.
    cmp qword ptr [r12 + ECJ_tx_offset], 0
    je .Lecjt_pending_command
    cmp qword ptr [r12 + ECJ_tx_offset], EW_HEADER
    jae ecjt_fail
    # Test-only external death. Production never kills after possible submission.
    cmp r14, 7
    je 8f
    mov rdi, [r12 + ECJ_native]
    call ext_settings_native_kill
    test rax, rax
    jnz ecjt_fail
8:  mov qword ptr [rsp + 32], 1
    mov rdi, r12
    call ext_settings_job_cancel
.Lecjt_pending_command:
    test r13, r13
    jz .Lecjt_delivery
    mov rdi, r12
    mov rsi, r13
    call ext_settings_job_command
    cmp rax, -11
    je .Lecjt_delivery
    test rax, rax
    jnz ecjt_fail
    xor r13d, r13d
.Lecjt_delivery:
    mov rdi, r12
    call ext_settings_job_take_frame
    test rax, rax
    jz .Lecjt_hold
    mov rbx, rax
    cmp qword ptr [rbx + EJF_kind], EW_SNAPSHOT
    jne 6f
    cmp qword ptr [rbx + EJF_body], 1
    jne ecjt_fail
    mov rax, [rsp + 224]
    cmp [rbx + EJF_body + 8], rax
    jne ecjt_fail
    lea rdi, [rbx + EJF_body + 48]
    mov rsi, rax
    lea rdx, [rsp + 192]
    call sha256_hash
    cmp eax, 1
    jne ecjt_fail
    lea rdi, [rsp + 192]
    lea rsi, [rsp + 160]
    mov edx, 32
    call memeq
    test eax, eax
    jz ecjt_fail
    mov qword ptr [rsp + 232], 1
6:  mov rax, [rbx + EJF_kind]
    mov [rsp + 40], rax
    mov rax, [rbx + EJF_round]
    mov [rsp + 48], rax
    mov rdi, rbx
    call ext_settings_frame_free
    test rax, rax
    jnz ecjt_fail
    cmp qword ptr [rsp + 40], EW_SNAPSHOT
    je .Lecjt_snapshot
    cmp qword ptr [rsp + 40], EW_PREPARED
    je .Lecjt_prepared
    cmp qword ptr [rsp + 40], EW_COMMITTED
    je .Lecjt_committed
    jmp ecjt_fail
.Lecjt_snapshot:
    cmp r14, 3
    je .Lecjt_release
    cmp r14, 4
    je .Lecjt_hold_goal
    cmp r14, 9
    je .Lecjt_idle_poll_error
    cmp r14, 10
    je .Lecjt_hold_goal
    cmp r14, 5
    je 9f
    cmp r14, 11
    je 9f
    cmp r14, 14
    jne .Lecjt_hold
9:  mov edi, EW_DELTA
    mov esi, 43
    mov edx, 1
    call ecjt_frame
    mov r13, rax
    mov dword ptr [r13 + EJF_body], 1
    lea rdi, [r13 + EJF_body + 8]
    lea rsi, [rip + ecjt_delta]
    mov edx, 35
    call memcpy
    mov rdi, r13
    call ext_settings_frame_seal
    test rax, rax
    jnz ecjt_fail
    jmp .Lecjt_hold
.Lecjt_idle_poll_error:
    mov qword ptr [rip + ecjt_inject], 1
    jmp .Lecjt_hold
.Lecjt_prepared:
    test r13, r13
    jnz ecjt_fail
    mov edi, EW_COMMIT
    mov rdx, [rsp + 48]
    call ecjt_empty
    mov r13, rax
    jmp .Lecjt_hold
.Lecjt_committed:
    cmp r14, 5
    je .Lecjt_hold_goal
    cmp r14, 11
    je .Lecjt_hold_goal
    cmp r14, 6
    je ecjt_fail
.Lecjt_release:
    test r13, r13
    jnz ecjt_fail
    mov edi, EW_RELEASE
    mov rdx, [rsp + 48]
    call ecjt_empty
    mov r13, rax
    jmp .Lecjt_hold
.Lecjt_hold_goal:
    mov qword ptr [rsp + 16], 1
.Lecjt_hold:
    cmp qword ptr [rsp + 16], 1
    jne .Lecjt_held
    mov rdi, r12
    call ext_settings_job_hold
    cmp rax, -16
    je .Lecjt_wait
    test rax, rax
    jnz ecjt_fail
    mov qword ptr [rsp + 16], 2
    cmp r14, 10
    jae .Lecjt_inject_held_poll
    mov rdi, r12
    call ext_settings_job_cancel
    jmp .Lecjt_test_held_api
.Lecjt_inject_held_poll:
    mov qword ptr [rip + ecjt_inject], 1
.Lecjt_test_held_api:
    mov rdi, r12
    call ecjf_busy
    mov edi, EW_RELEASE
    mov rdx, [r12 + ECJ_round]
    call ecjt_empty
    mov rbx, rax
    mov rdi, r12
    mov rsi, rbx
    call ext_settings_job_command
    cmp rax, -16
    jne ecjt_fail
    mov rdi, rbx
    call ext_settings_frame_free
.Lecjt_held:
    cmp qword ptr [rsp + 16], 2
    jne .Lecjt_wait
    cmp qword ptr [r12 + ECJ_native], 0
    je ecjt_fail
    cmp qword ptr [r12 + ECJ_authority], 1
    jne ecjt_fail
    test qword ptr [r12 + ECJ_eof], 1
    jnz ecjt_fail
    inc qword ptr [rsp + 24]
    cmp qword ptr [rsp + 24], 20
    jb .Lecjt_wait
    mov rdi, r12
    call ext_settings_job_release_hold
    test rax, rax
    jnz ecjt_fail
    mov qword ptr [rsp + 16], 3
.Lecjt_wait:
    mov rdi, r12
    call ext_settings_job_timeout
    mov rdx, rax
    cmp qword ptr [r12 + ECJ_cleanup_only], 0
    je 9f
    cmp qword ptr [r12 + ECJ_native], 0
    je ecjt_fail
    cmp qword ptr [r12 + ECJ_reservation], ESM_NATIVE_RESERVE
    jne ecjt_fail
    cmp rdx, 1
    jb ecjt_fail
    cmp rdx, 1000
    ja ecjt_fail
    jmp 8f
9:  cmp qword ptr [r12 + ECJ_hold], 0
    je 7f
    cmp rdx, 16
    jne ecjt_fail
    jmp 8f
7:  cmp rdx, 1
    je 8f
    cmp rdx, 16
    jne ecjt_fail
8:  xor edi, edi
    xor esi, esi
    SYS SYS_poll
    jmp .Lecjt_loop
.Lecjt_terminal:
    mov rdi, r12
    call ext_settings_job_timeout
    cmp rax, -1
    jne ecjt_fail
    test r13, r13
    jnz ecjt_fail
    mov rdi, r12
    lea rsi, [rsp + 80]
    call ext_settings_job_status
    mov rax, [rsp + 80]
    cmp r14, 1
    je .Lecjt_expect_read
    cmp r14, 12
    je .Lecjt_expect_read
    cmp r14, 3
    je .Lecjt_expect_read
    cmp r14, 4
    je .Lecjt_expect_cancel
    cmp r14, 6
    je .Lecjt_expect_uncertain
    cmp r14, 7
    je .Lecjt_expect_definite
    cmp r14, 8
    je .Lecjt_expect_open_failure
    cmp r14, 9
    je .Lecjt_expect_poll_failure
    cmp r14, 10
    je .Lecjt_expect_poll_failure
    cmp rax, 3
    jne ecjt_fail
    cmp qword ptr [rsp + 88], 0
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_read:
    cmp qword ptr [rsp + 232], 1
    jne ecjt_fail
    cmp rax, 1
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_cancel:
    cmp rax, 1
    je .Lecjt_dispose
    cmp rax, 2
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_uncertain:
    cmp rax, 4
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_poll_failure:
    cmp rax, 1
    je 9f
    cmp rax, 2
    jne ecjt_fail
    cmp qword ptr [rsp + 88], -5
    jne ecjt_fail
9:  cmp qword ptr [rsp + 104], -5
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_open_failure:
    cmp rax, 2
    jne ecjt_fail
    cmp qword ptr [rsp + 88], -20
    jne ecjt_fail
    cmp qword ptr [rsp + 112], 1
    jne ecjt_fail
    jmp .Lecjt_dispose
.Lecjt_expect_definite:
    cmp rax, 2
    jne ecjt_fail
    mov rdi, r12
    call ecj_row
    test qword ptr [rax + ECJR_flags], ECJR_DEFINITE
    jz ecjt_fail
    test qword ptr [rax + ECJR_flags], ECJR_POSSIBLE
    jz ecjt_fail
.Lecjt_dispose:
    test qword ptr [rsp + 120], 1
    jz ecjt_fail
    test qword ptr [rsp + 120], 2
    jz ecjt_fail
    mov rdi, r12
    call ecjf_terminal
    call ecjf_null
    call ext_settings_memory_total
    test rax, rax
    jnz ecjt_fail
    cmp [rip + g_mem_live], r15
    jne ecjt_fail
    mov edi, 1
    lea rsi, [rsp + 80]
    mov edx, 64
    call write_all
    xor eax, eax
    EPILOGUE

.text
# Every checked free return defines cleanup and consumed independently of input registers.
ecjf_fail:
    mov edi, 74
    call sys_exit
ecjf_null:
    PROLOGUE
    xor edi, edi
    mov rdx, 0x55555555
    mov rcx, -9
    call ext_settings_job_free
    test rax, rax
    jnz ecjf_fail
    test rdx, rdx
    jnz ecjf_fail
    cmp rcx, 1
    jne ecjf_fail
    EPILOGUE
ecjf_busy:
    PROLOGUE 32
    mov r12, rdi
    mov rax, [r12 + ECJ_native]
    mov [rsp], rax
    mov rax, [r12 + ECJ_reservation]
    mov [rsp + 8], rax
    mov rax, [r12 + ECJ_tx]
    mov [rsp + 16], rax
    call ext_settings_memory_total
    mov [rsp + 24], rax
    mov rdi, r12
    mov rdx, 0x55555555
    mov ecx, 1
    call ext_settings_job_free
    cmp rax, -16
    jne ecjf_fail
    test rcx, rcx
    jnz ecjf_fail
    test rdx, rdx
    jnz ecjf_fail
    mov rax, [rsp]
    cmp [r12 + ECJ_native], rax
    jne ecjf_fail
    mov rax, [rsp + 8]
    cmp [r12 + ECJ_reservation], rax
    jne ecjf_fail
    mov rax, [rsp + 16]
    cmp [r12 + ECJ_tx], rax
    jne ecjf_fail
    call ext_settings_memory_total
    cmp rax, [rsp + 24]
    jne ecjf_fail
    xor eax, eax
    EPILOGUE
ecjf_terminal:
    PROLOGUE
    mov rdx, 0x55555555
    mov rcx, -9
    call ext_settings_job_free
    test rax, rax
    jnz ecjf_fail
    test rdx, rdx
    jnz ecjf_fail
    cmp rcx, 1
    jne ecjf_fail
    xor eax, eax
    EPILOGUE
