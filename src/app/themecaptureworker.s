# Closed early helper. No app initialization, settings, registry or palette publication.
.include "rhun.inc"
.include "app/themecapture.inc"
.text
FN theme_capture_worker_main
    PROLOGUE 144
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsp
    xor esi, esi
    mov edx, 144
    call memset
    mov qword ptr [rip + g_theme_capture_limit], TC_HELPER_CAP
    call time_ms
    lea r14, [rax + 10000]
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp + 32]
    call theme_capture_worker_arguments
    test rax, rax
    js .Ltcw_fail
    mov rdi, rsp
    call ext_settings_worker_io_init
    test rax, rax
    js .Ltcw_fail
    mov edi, TC_INPUT_CAP + 1
    call tc_alloc_try
    test rax, rax
    jz .Ltcw_fail
    mov [rsp + 64], rax
    xor r13d, r13d
.Ltcw_read:
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcw_fail
    mov rdi, rsp
    mov rsi, [rsp + 64]
    add rsi, r13
    mov edx, TC_INPUT_CAP + 1
    sub rdx, r13
    cmp rdx, 65536
    jbe 1f
    mov edx, 65536
1:  call ext_settings_worker_io_read
    cmp rax, -EINTR
    je .Ltcw_wait_read
    cmp rax, -11
    je .Ltcw_wait_read
    test rax, rax
    js .Ltcw_fail
    jz .Ltcw_input_done
    add r13, rax
    cmp r13, TC_INPUT_CAP
    ja .Ltcw_fail
    jmp .Ltcw_read
.Ltcw_wait_read:
    call tc_helper_wait
    jmp .Ltcw_read
.Ltcw_input_done:
    mov rdi, [rsp + 64]
    mov rsi, r13
    call tc_request_validate
    test rax, rax
    js .Ltcw_fail
    mov rdi, [rsp + 64]
    add rdi, 32
    lea rsi, [rsp + 32]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Ltcw_fail
    mov rdi, [rsp + 64]
    mov rsi, r13
    lea rdx, [rsp + 80]
    mov rcx, r14
    call tc_capture_build
    test rax, rax
    jnz .Ltcw_fail
    test rdx, rdx
    jnz .Ltcw_fail
    xor r13d, r13d
.Ltcw_write:
    cmp r13, [rsp + 88]
    jae .Ltcw_finish
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcw_fail
    mov rdi, rsp
    mov rsi, [rsp + 80]
    add rsi, r13
    mov rdx, [rsp + 88]
    sub rdx, r13
    cmp rdx, 65536
    jbe 2f
    mov edx, 65536
2:  call ext_settings_worker_io_write
    cmp rax, -EINTR
    je .Ltcw_wait_write
    cmp rax, -11
    je .Ltcw_wait_write
    test rax, rax
    jle .Ltcw_fail
    add r13, rax
    jmp .Ltcw_write
.Ltcw_wait_write:
    call tc_helper_wait
    jmp .Ltcw_write
.Ltcw_finish:
    lea rdi, [rsp + 80]
    mov rsi, r14
    call tc_file_release
    mov [rsp + 104], rax
    lea rdi, [rsp + 64]
    mov rsi, r14
    call tc_file_release
    or rax, [rsp + 104]
    jnz .Ltcw_exit_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne .Ltcw_exit_fail
    xor eax, eax
    EPILOGUE
.Ltcw_fail:
    # Process exit remains the owner if bounded cleanup cannot complete.
    lea rdi, [rsp + 80]
    mov rsi, r14
    call tc_file_release
    lea rdi, [rsp + 64]
    mov rsi, r14
    call tc_file_release
.Ltcw_exit_fail:
    mov eax, 70
    EPILOGUE
