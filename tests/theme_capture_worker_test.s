# Actual reexec through the closed native theme factory, complete helper IO and collection.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/extsettingsnative.inc"
.include "app/extstorejob.inc"
.section .rodata
tcwt_marker: .asciz "--theme-source-worker"
.bss
.p2align 3
tcwt_request: .zero TC_INPUT_CAP + 1
tcwt_output: .zero 65536
.text
tcwt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 112
    cmp qword ptr [rip + g_argc], 2
    jb .Ltcwt_parent
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + tcwt_marker]
    call strcmp_eq
    test eax, eax
    jz tcwt_fail
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call theme_capture_worker_main
    EPILOGUE
.Ltcwt_parent:
    cmp qword ptr [rip + g_argc], 1
    jne tcwt_fail
    call ext_store_job_legacy_cache_executable
    test rax, rax
    jnz tcwt_fail
    mov r15, [rip + g_mem_live]
    xor r12d, r12d
1:  xor edi, edi
    lea rsi, [rip + tcwt_request]
    add rsi, r12
    mov edx, TC_INPUT_CAP + 1
    sub rdx, r12
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js tcwt_fail
    jz 2f
    add r12, rax
    cmp r12, TC_INPUT_CAP
    jbe 1b
    jmp tcwt_fail
2:  mov qword ptr [rsp], 1
    mov qword ptr [rsp + 8], 2
    xor ecx, ecx
3:  lea eax, [rcx + 1]
    mov [rsp + 16 + rcx], al
    inc ecx
    cmp ecx, 16
    jb 3b
    mov rdi, rsp
    call theme_capture_native_start
    test rax, rax
    jz tcwt_fail
    or rdx, rcx
    jnz tcwt_fail
    mov r13, rax
    mov rdi, rax
    lea rsi, [rip + tcwt_request]
    mov rdx, r12
    call ext_settings_native_write_begin
    cmp rax, 1
    jne tcwt_fail
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 64], 0
    mov qword ptr [rsp + 72], 0
    call time_ms
    add rax, 10000
    mov [rsp + 56], rax
.Ltcwt_loop:
    call time_ms
    cmp rax, [rsp + 56]
    jae tcwt_fail
    cmp qword ptr [rsp + 32], 0
    jne .Ltcwt_read
    mov rdi, r13
    mov esi, 65536
    call ext_settings_native_write_poll
    test rax, rax
    js tcwt_fail
    jz .Ltcwt_read
    mov rdi, r13
    call ext_settings_native_close_input
    test rax, rax
    jnz tcwt_fail
    mov qword ptr [rsp + 32], 1
.Ltcwt_read:
    xor ebx, ebx
1:  bt qword ptr [rsp + 40], rbx
    jc 4f
    mov rdi, r13
    mov rsi, rbx
    lea rdx, [rip + tcwt_output]
    mov ecx, 65536
    call ext_settings_native_read
    cmp rax, -EINTR
    je 4f
    cmp rax, -11
    je 4f
    test rax, rax
    js tcwt_fail
    jz 3f
    test rbx, rbx
    jnz tcwt_fail
    mov edi, 1
    lea rsi, [rip + tcwt_output]
    mov rdx, rax
    call write_all
    test rax, rax
    jnz tcwt_fail
    jmp 4f
3:  bts qword ptr [rsp + 40], rbx
4:  inc ebx
    cmp ebx, 3
    jb 1b
    cmp qword ptr [rsp + 48], 0
    jne .Ltcwt_collected
    mov rdi, r13
    call ext_settings_native_poll
    test rcx, rcx
    jns .Ltcwt_observed
    cmp qword ptr [rsp + 64], 0
    jne 5f
    mov [rsp + 64], rcx
5:  cmp rax, ESJ_OWNED
    jne .Ltcwt_observed
    cmp qword ptr [rsp + 72], 0
    jne .Ltcwt_wait
    mov qword ptr [rsp + 72], 1
    mov rdi, r13
    call ext_settings_native_kill
    jmp .Ltcwt_wait
.Ltcwt_observed:
    cmp rax, ESJ_OWNED
    je .Ltcwt_wait
    cmp rax, ESJ_REAPED
    jne tcwt_fail
    cmp qword ptr [rsp + 64], 0
    jne 6f
    test rdx, rdx
    jnz tcwt_fail
6:  mov qword ptr [rsp + 48], 1
.Ltcwt_collected:
    cmp qword ptr [rsp + 40], 7
    jne .Ltcwt_wait
    cmp qword ptr [rsp + 32], 1
    jne tcwt_fail
    mov rdi, r13
    call ext_settings_native_free
    test rdx, rdx
    jz .Ltcwt_wait
    test rax, rax
    jnz tcwt_fail
    cmp r15, [rip + g_mem_live]
    jne tcwt_fail
    cmp qword ptr [rsp + 64], 0
    jne tcwt_fail
    xor eax, eax
    EPILOGUE
.Ltcwt_wait:
    call tc_helper_wait
    jmp .Ltcwt_loop
