# Units use fake native IDs. Real protected lifecycles are a separate combined gate.
.include "rhun.inc"
.include "app/taskproc.inc"
.include "app/taskauth.inc"
.bss
.p2align 3
hf_host: .zero EXT_SIZE
hf_info: .zero 64
hf_stage: .quad 0
hf_reads: .quad 0
hf_bytes: .quad 0
hf_after: .quad 0
hf_poll_calls: .quad 0
hf_close_calls: .quad 0
hf_fd_calls: .quad 0
hf_consumed: .quad 0
hf_bad: .quad 0
hf_disposition: .quad 0
hf_cleanup: .quad 0
hf_primary: .long 0
hf_exit: .long 0
hf_fd_disposition: .quad 0
hf_fd_status: .quad 0
hf_guard: .quad 0
hf_wait_calls: .quad 0
hf_kill_calls: .quad 0
hf_child: .quad 0
hf_plan: .zero KE_SIZE
hf_prepare_result: .quad 0
hf_prepare_cleanup: .quad 0
hf_live: .quad 0
.text
FN main
    PROLOGUE
    mov qword ptr [rip + hf_stage], 1
    call hf_setup
    # Collected failed writer: consume keeper first, then get real EOF next slice.
    mov qword ptr [rip + hf_info + 8], -5
    mov qword ptr [rip + hf_cleanup], -5
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_host + EXT_keeper], 0
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_stdout_eof], 0
    jne .Lhf_bad
    cmp qword ptr [rip + hf_host + EXT_fbytes], 1
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    mov esi, 100
    call ext_host_keeper_timeout
    cmp rax, 16
    jne .Lhf_bad
    mov qword ptr [rip + hf_after], 0
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhf_bad
    cmp edx, -5
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_stdout_eof], 1
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_retiring], 2
    jne .Lhf_bad
    cmp qword ptr [rip + hf_bad], 0
    jne .Lhf_bad
    cmp qword ptr [rip + hf_close_calls], 1
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_close_calls], 1
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 2
    call hf_setup
    # Healthy completion drains every byte and true EOF before close.
    mov qword ptr [rip + hf_bytes], 70000
    mov qword ptr [rip + hf_after], 0
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_reads], 4
    jne .Lhf_bad
    cmp qword ptr [rip + hf_close_calls], 0
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhf_bad
    test edx, edx
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_bytes], 0
    jne .Lhf_bad
    cmp qword ptr [rip + hf_reads], 6
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 3
    call hf_setup
    # Unknown keeper ownership: bounded drain then EAGAIN, no quarantine clock.
    mov qword ptr [rip + hf_info + 8], -5
    mov qword ptr [rip + hf_info + 16], 1
    mov qword ptr [rip + hf_disposition], 2
    mov qword ptr [rip + hf_cleanup], -5
    mov qword ptr [rip + hf_bytes], 70000
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    lea rdi, [rip + hf_host]
    mov esi, 100
    call ext_host_keeper_timeout
    cmp rax, 16
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_host + EXT_fbytes], 0
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    mov esi, 100
    call ext_host_keeper_timeout
    cmp rax, -1
    jne .Lhf_bad
    cmp qword ptr [rip + hf_host + EXT_keeper], 123
    jne .Lhf_bad
    # Memory deadline remains exact and is not restarted by the timeout query.
    mov qword ptr [rip + hf_info + 48], 1
    mov qword ptr [rip + hf_info + 40], 250
    lea rdi, [rip + hf_host]
    mov esi, 100
    call ext_host_keeper_timeout
    cmp rax, 150
    jne .Lhf_bad
    cmp qword ptr [rip + hf_info + 40], 250
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 4
    call hf_setup
    # A terminal read failure and consumed raw close never pretend to be EOF.
    mov qword ptr [rip + hf_after], -5
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhf_bad
    cmp edx, -5
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_stdout_eof], 0
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_retiring], 4
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 5
    call hf_setup
    # A failed raw close stays owned, is never read/retried, and blocks finalization.
    mov qword ptr [rip + hf_after], -5
    mov qword ptr [rip + hf_fd_disposition], 2
    mov qword ptr [rip + hf_fd_status], -9
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_out], 42
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_host_cleanup_mask], 2
    jne .Lhf_bad
    cmp qword ptr [rip + hf_fd_calls], 1
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_fd_calls], 1
    jne .Lhf_bad
    cmp qword ptr [rip + hf_reads], 1
    jne .Lhf_bad
    cmp qword ptr [rip + hf_bad], 0
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 6
    call hf_setup
    mov dword ptr [rip + hf_primary], -13
    mov qword ptr [rip + hf_cleanup], -5
    mov qword ptr [rip + hf_after], 0
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhf_bad
    cmp edx, -13
    jne .Lhf_bad
    # Nonzero target exit also outranks cleanup diagnostic.
    call hf_setup
    mov dword ptr [rip + hf_exit], 7
    mov qword ptr [rip + hf_cleanup], -5
    mov qword ptr [rip + hf_after], 0
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    cmp eax, 1
    jne .Lhf_bad
    cmp edx, 7
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 7
    call hf_setup
    mov qword ptr [rip + hf_info + 24], 1
    mov qword ptr [rip + hf_disposition], 0
    mov qword ptr [rip + hf_cleanup], -5
    mov qword ptr [rip + hf_after], 0
    lea rdi, [rip + hf_host]
    call ext_host_keeper_collect
    test eax, eax
    jnz .Lhf_bad
    cmp qword ptr [rip + hf_host + EXT_keeper], 123
    jne .Lhf_bad
    cmp qword ptr [rip + hf_close_calls], 1
    jne .Lhf_bad
    lea rdi, [rip + hf_host]
    mov esi, 100
    call ext_host_keeper_timeout
    cmp rax, -1
    jne .Lhf_bad
    mov qword ptr [rip + hf_stage], 8
    call hf_setup
    mov qword ptr [rip + hf_host + EXT_keeper], 0
    mov dword ptr [rip + hf_host + EXT_host_cleanup_mask], 2
    lea rax, [rip + hf_host]
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov qword ptr [rip + g_exts + VEC_cap], 1
.ifndef WINDOWS
    # A real unrelated child must survive the keeper-zero shutdown window.
    mov edi, 17
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    SYS 57
    test rax, rax
    js .Lhf_bad
    jz .Lhf_child
    mov [rip + hf_child], rax
.endif
    call ext_shutdown
    cmp qword ptr [rip + hf_wait_calls], 0
    jne .Lhf_bad
    cmp qword ptr [rip + hf_kill_calls], 0
    jne .Lhf_bad
    cmp qword ptr [rip + hf_reads], 0
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_retiring], 1
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_out], 42
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_stdout_eof], 0
    jne .Lhf_bad
.ifndef WINDOWS
    mov rdi, [rip + hf_child]
    mov esi, 1
    call proc_wait
    cmp eax, -1
    jne .Lhf_bad
    mov rdi, [rip + hf_child]
    mov esi, SIGTERM
    SYS SYS_kill
    mov rdi, [rip + hf_child]
    xor esi, esi
    call proc_wait
.endif
    mov qword ptr [rip + hf_stage], 9
    mov rax, [rip + g_mem_live]
    mov [rip + hf_live], rax
    call hf_prepare_setup
    mov qword ptr [rip + hf_prepare_result], -13
    mov qword ptr [rip + hf_prepare_cleanup], -5
    lea rdi, [rip + hf_host]
    call hf_prepare_call
    cmp rax, -13
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_host_cleanup_error], -5
    jne .Lhf_bad
    mov dword ptr [rip + hf_host + EXT_host_cleanup_error], -9
    mov qword ptr [rip + hf_prepare_result], 123
    lea rdi, [rip + hf_host]
    call hf_prepare_call
    cmp rax, 123
    jne .Lhf_bad
    cmp dword ptr [rip + hf_host + EXT_host_cleanup_error], -9
    jne .Lhf_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + hf_live]
    jne .Lhf_bad
    xor eax, eax
    EPILOGUE
.Lhf_child:
    xor edi, edi
    xor esi, esi
    mov edx, 2000
    SYS SYS_poll
    xor eax, eax
    EPILOGUE
.Lhf_bad:
    mov rax, [rip + hf_stage]
    EPILOGUE
hf_setup:
    PROLOGUE
    lea rdi, [rip + hf_host]
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    lea rdi, [rip + hf_info]
    xor esi, esi
    mov edx, 64
    call memset
    mov qword ptr [rip + hf_info + 56], 1
    mov dword ptr [rip + hf_host + EXT_in], -1
    mov dword ptr [rip + hf_host + EXT_out], 42
    mov dword ptr [rip + hf_host + EXT_log], -1
    mov dword ptr [rip + hf_host + EXT_retiring], 1
    mov dword ptr [rip + hf_host + EXT_status], ES_STOPPING
    mov dword ptr [rip + hf_host + EXT_activation_required], 1
    mov qword ptr [rip + hf_host + EXT_keeper], 123
    mov qword ptr [rip + hf_reads], 0
    mov qword ptr [rip + hf_bytes], 0
    mov qword ptr [rip + hf_after], -11
    mov qword ptr [rip + hf_poll_calls], 0
    mov qword ptr [rip + hf_close_calls], 0
    mov qword ptr [rip + hf_fd_calls], 0
    mov qword ptr [rip + hf_consumed], 0
    mov qword ptr [rip + hf_bad], 0
    mov qword ptr [rip + hf_disposition], 1
    mov qword ptr [rip + hf_cleanup], 0
    mov dword ptr [rip + hf_primary], 0
    mov dword ptr [rip + hf_exit], 0
    mov qword ptr [rip + hf_fd_disposition], 1
    mov qword ptr [rip + hf_fd_status], 0
    EPILOGUE
FN hf_poll
    cmp qword ptr [rip + hf_consumed], 0
    jne hf_dead_id
    inc qword ptr [rip + hf_poll_calls]
    mov eax, KP_DONE
    mov edx, [rip + hf_exit]
    mov r8d, [rip + hf_primary]
    test r8d, r8d
    js 1f
    mov r8d, [rip + hf_cleanup]
1:  ret
FN hf_info_get
    movsxd rax, dword ptr [rip + hf_primary]
    mov [rip + hf_info], rax
    cmp qword ptr [rip + hf_consumed], 0
    jne hf_dead_id
    PROLOGUE
    mov rdi, rsi
    lea rsi, [rip + hf_info]
    mov edx, 64
    call memcpy
    xor eax, eax
    EPILOGUE
FN hf_close
    cmp qword ptr [rip + hf_consumed], 0
    jne hf_dead_id
    inc qword ptr [rip + hf_close_calls]
    mov rdx, [rip + hf_disposition]
    cmp rdx, 1
    jne 1f
    mov qword ptr [rip + hf_consumed], 1
1:  mov rax, [rip + hf_cleanup]
    ret
hf_dead_id:
    inc qword ptr [rip + hf_bad]
    mov rax, -2
    xor edx, edx
    ret
FN hf_read
    inc qword ptr [rip + hf_reads]
    mov rax, [rip + hf_bytes]
    test rax, rax
    jz 1f
    cmp rax, rdx
    jbe 2f
    mov rax, rdx
2:  sub [rip + hf_bytes], rax
    ret
1:  mov rax, [rip + hf_after]
    ret
FN hf_fd_close
    inc qword ptr [rip + hf_fd_calls]
    mov rax, [rip + hf_fd_status]
    mov rdx, [rip + hf_fd_disposition]
    ret

FN hf_wait
    inc qword ptr [rip + hf_wait_calls]
    mov eax, -1
    ret
FN hf_kill
    inc qword ptr [rip + hf_kill_calls]
    mov rax, -5
    ret
FN hf_loop
    xor eax, eax
    ret

hf_prepare_setup:
    PROLOGUE
    lea rdi, [rip + hf_host]
    xor esi, esi
    mov edx, EXT_SIZE
    call memset
    lea rdi, [rip + hf_plan]
    xor esi, esi
    mov edx, KE_SIZE
    call memset
    lea rax, [rip + hf_plan]
    mov [rip + hf_host + EXT_activation_plan], rax
    lea rax, [rip + hf_owner]
    mov [rip + hf_host + EXT_owner], rax
    mov [rip + hf_plan + KE_owner], rax
    lea rax, [rip + hf_name]
    mov [rip + hf_host + EXT_name], rax
    mov [rip + hf_plan + KE_name], rax
    lea rax, [rip + hf_state]
    mov [rip + hf_host + EXT_state], rax
    mov [rip + hf_plan + KE_state], rax
    mov rax, [rip + g_project]
    mov [rip + hf_plan + KE_project], rax
    lea rdi, [rip + hf_home_key]
    call getenv
    mov [rip + hf_plan + KE_home], rax
    call ext_activation_epoch_get
    mov [rip + hf_plan + KE_context], rax
    EPILOGUE
FN hf_activation_check
    xor eax, eax
    ret
FN hf_auth
    PROLOGUE
    mov edi, 16
    call mem_alloc
    mov edx, 16
    EPILOGUE
FN hf_prepare
    mov rax, [rip + hf_prepare_result]
    mov rdx, -13
    mov rcx, [rip + hf_prepare_cleanup]
    ret
FN hf_auth_free
    PROLOGUE
    call mem_free
    mov ecx, 0x11223344
    mov eax, 0x55667788
    EPILOGUE
.section .rodata
hf_owner: .asciz "owner"
hf_name: .asciz "extension"
hf_home_key: .asciz "HOME"
.ifdef WINDOWS
hf_state: .asciz "C:/state"
.else
hf_state: .asciz "/state"
.endif
