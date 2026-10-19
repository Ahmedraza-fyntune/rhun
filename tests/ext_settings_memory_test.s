.include "rhun.inc"
.include "app/extsettingsmemory.inc"
.include "app/extsettingsframe.inc"
.section .rodata
esm_test_tag: .quad 17,29,0,0
esm_test_ok: .ascii "ok settings aggregate allocation and owned frames\n"
.equ ESM_TEST_LEN, 50
.text
esm_test_fail:
    mov edi, 72
    call sys_exit
FN main
    PROLOGUE
    mov r15, [rip + g_mem_live]
    mov edi, ESM_CAP
    call ext_settings_memory_reserve
    test rax, rax
    jnz esm_test_fail
    mov edi, 1
    call ext_settings_memory_try
    test rax, rax
    jnz esm_test_fail
    cmp rdx, -12
    jne esm_test_fail
    call ext_settings_memory_total
    cmp rax, ESM_CAP
    jne esm_test_fail
    mov edi, ESM_CAP
    call ext_settings_memory_release
    test rax, rax
    jnz esm_test_fail
    mov edi, 1
    call ext_settings_memory_try
    test rax, rax
    jz esm_test_fail
    mov rbx, rax
    cmp byte ptr [rbx], 0
    jne esm_test_fail
    call ext_settings_memory_total
    cmp rax, 64
    jne esm_test_fail
    mov rdi, rbx
    call ext_settings_memory_free
    test rax, rax
    jnz esm_test_fail
    call ext_settings_memory_total
    test rax, rax
    jnz esm_test_fail
    mov edi, 1
    call ext_settings_memory_release
    cmp rax, -22
    jne esm_test_fail
    lea rdi, [rip + esm_test_tag]
    mov esi, EW_PREPARED
    mov edx, 48
    mov ecx, 1
    call ext_settings_frame_new
    test rax, rax
    jz esm_test_fail
    mov rbx, rax
    cmp qword ptr [rbx + EJF_length], 48
    jne esm_test_fail
    cmp qword ptr [rbx + EJF_sealed], 0
    jne esm_test_fail
    cmp qword ptr [rbx + EJF_body], 0
    jne esm_test_fail
    inc qword ptr [rbx + EJF_length]
    mov rdi, rbx
    call ext_settings_frame_seal
    cmp rax, -71
    jne esm_test_fail
    cmp qword ptr [rbx + EJF_sealed], 0
    jne esm_test_fail
    dec qword ptr [rbx + EJF_length]
    mov rdi, rbx
    call ext_settings_frame_seal
    test rax, rax
    jnz esm_test_fail
    mov rdi, rbx
    call ext_settings_frame_seal
    cmp rax, -71
    jne esm_test_fail
    mov rdi, rbx
    call ext_settings_frame_free
    test rax, rax
    jnz esm_test_fail
    lea rdi, [rip + esm_test_tag]
    mov esi, EW_PREPARED
    mov rdx, -1
    mov ecx, 1
    call ext_settings_frame_new
    test rax, rax
    jnz esm_test_fail
    cmp rdx, -71
    jne esm_test_fail
    call ext_settings_memory_total
    test rax, rax
    jnz esm_test_fail
    cmp [rip + g_mem_live], r15
    jne esm_test_fail
    mov edi, 1
    lea rsi, [rip + esm_test_ok]
    mov edx, ESM_TEST_LEN
    call write_all
    xor eax, eax
    EPILOGUE
