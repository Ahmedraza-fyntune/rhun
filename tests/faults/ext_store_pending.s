# Private import-hook fixture. No pending native work survives the owned context.
.include "rhun.inc"
.include "app/extstore.inc"
.bss
.p2align 3
esp_iosb: .quad 0
esp_polls: .quad 0
esp_closes: .quad 0
esp_context: .zero ESU_SIZE
.text
esp_fail:
    mov edi, 78
    call sys_exit
FN esp_set_information
    cmp qword ptr [rsp + 40], 13
    jne esp_fail
    lea rax, [rip + esp_context + ESU_iosb]
    cmp rdx, rax
    jne esp_fail
    lea rax, [rip + esp_context + ESU_disposition]
    cmp r8, rax
    jne esp_fail
    cmp r9, 1
    jne esp_fail
    mov [rip + esp_iosb], rdx
    mov eax, 0x103
    ret
FN esp_wait
    inc qword ptr [rip + esp_polls]
    cmp qword ptr [rip + esp_polls], 1
    jne 1f
    mov eax, -1
    ret
1:  cmp qword ptr [rip + esp_polls], 2
    jne 2f
    mov eax, 258
    ret
2:  mov rax, [rip + esp_iosb]
    mov qword ptr [rax], 0
    xor eax, eax
    ret
FN ext_root_close
    inc qword ptr [rip + esp_closes]
    jmp ext_store_test_real_close
FN main
    PROLOGUE 64
    cmp qword ptr [rip + g_argc], 2
    jne esp_fail
    mov r15, [rip + g_mem_live]
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call ext_root_open
    test rax, rax
    js esp_fail
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + esp_name]
    mov edx, 1
    mov ecx, 15
    mov r8d, 0600
    call ext_root_open_at
    test rax, rax
    js esp_fail
    mov r13, rax
    lea rdi, [rip + esp_context]
    call ext_store_unlink_init
    mov rdi, r13
    lea rsi, [rip + esp_context]
    call ext_store_unlink_handle_try
    cmp rax, -115
    jne esp_fail
    cmp qword ptr [rip + esp_context + ESU_pending], 1
    jne esp_fail
    cmp qword ptr [rip + esp_context + ESU_raw], r13
    jne esp_fail
    # A busy context rejects ownership transfer before touching the incoming raw.
    mov rdi, r12
    lea rsi, [rip + esp_context]
    call ext_store_unlink_handle_try
    cmp rax, -16
    jne esp_fail
    lea rdi, [rip + esp_context]
    call ext_store_unlink_poll
    cmp rax, -115
    jne esp_fail
    cmp qword ptr [rip + esp_context + ESU_observation], -5
    jne esp_fail
    cmp qword ptr [rip + esp_closes], 0
    jne esp_fail
    mov rdi, r13
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    jnz esp_fail
    lea rdi, [rip + esp_context]
    call ext_store_unlink_poll
    cmp rax, -115
    jne esp_fail
    cmp qword ptr [rip + esp_closes], 0
    jne esp_fail
    lea rdi, [rip + esp_context]
    call ext_store_unlink_poll
    test rax, rax
    jnz esp_fail
    test rdx, rdx
    jnz esp_fail
    cmp qword ptr [rip + esp_closes], 1
    jne esp_fail
    cmp qword ptr [rip + esp_context + ESU_pending], 0
    jne esp_fail
    cmp qword ptr [rip + esp_context + ESU_raw], -1
    jne esp_fail
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jnz esp_fail
    cmp r15, [rip + g_mem_live]
    jne esp_fail
    xor eax, eax
    EPILOGUE
.section .rodata
esp_name: .asciz "pending"
