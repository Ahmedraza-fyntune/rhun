.include "rhun.inc"
.include "app/extstore.inc"
.text
eskt_fail:
    mov edi, 75
    call sys_exit
FN main
    PROLOGUE 960
    cmp qword ptr [rip + g_argc], 4
    jne eskt_fail
    mov r15, [rip + g_mem_live]
    mov rbx, [rip + g_argv]
    lea rdi, [rsp + 800]
    xor esi, esi
    mov edx, 128
    call memset
    mov rdi, [rbx + 8]
    mov rsi, [rbx + 16]
    mov rdx, [rbx + 24]
    mov rcx, rsp
    xor r8d, r8d
    xor r9d, r9d
    call ext_store_lookup_try
    lea rsi, [rsp + 800]
    call eskt_result
    mov rdi, [rbx + 8]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call ext_store_guard_try
    test rax, rax
    jz eskt_fail
    mov r12, rax
    mov rdi, rax
    mov rsi, [rbx + 16]
    mov rdx, [rbx + 24]
    lea rcx, [rsp + 400]
    call ext_store_lookup_guard
    lea rsi, [rsp + 824]
    call eskt_result
    mov rdi, rsp
    lea rsi, [rsp + 400]
    mov edx, ESR_SIZE
    call memeq
    test eax, eax
    jz eskt_fail
    mov rdi, r12
    mov rsi, [rbx + 16]
    mov rdx, [rbx + 24]
    xor ecx, ecx
    cmp qword ptr [rsp + ESR_generation], 0
    je 1f
    lea rcx, [rsp + ESR_index]
1:  call ext_store_selection_matches
    mov [rsp + 848], rax
    mov [rsp + 856], rdx
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz eskt_fail
    cmp r15, [rip + g_mem_live]
    jne eskt_fail
    mov edi, 1
    lea rsi, [rsp + 800]
    mov edx, 64
    call write_all
    test rax, rax
    jnz eskt_fail
    xor eax, eax
    EPILOGUE
# Validate pointer/error convention without exposing an address in fixture bytes.
eskt_result:
    test rax, rax
    jz 2f
    test rdx, rdx
    jnz eskt_fail
    test rcx, rcx
    jnz eskt_fail
    mov qword ptr [rsi], 1
    mov [rsi + 8], rdx
    mov [rsi + 16], rcx
    ret
2:  test rdx, rdx
    jns eskt_fail
    mov qword ptr [rsi], 0
    mov [rsi + 8], rdx
    mov [rsi + 16], rcx
    ret
