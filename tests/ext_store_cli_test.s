.include "rhun.inc"
.include "app/extstore.inc"
.text
FN main
    PROLOGUE 320
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    cmp rdi, 3
    jne 3f
    mov rbx, rsi
    mov rdi, [rsi + 8]
    lea rsi, [rip + esc_owned]
    call strcmp_eq
    test eax, eax
    jnz 5f
    mov rdi, [rbx + 8]
    lea rsi, [rip + esc_borrowed]
    call strcmp_eq
    test eax, eax
    jz 4f
    mov r15, [rip + g_mem_live]
    mov rdi, [rbx + 16]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 16]
    call parse_u64
    cmp rdx, rsi
    jne 4f
    mov r12, rax
    mov rdi, rsp
    xor esi, esi
    mov edx, EST_SIZE
    call memset
    mov qword ptr [rsp + EST_epoch], 7
    mov qword ptr [rsp + EST_job], 9
    mov rdi, r12
    mov rsi, rsp
    mov edx, 1
    call ext_store_snapshot_emit_root
    test rax, rax
    jnz 4f
    test rdx, rdx
    jnz 4f
    mov rdi, r12
    lea rsi, [rsp + 64]
    call ext_root_identity
    test rax, rax
    jnz 4f
    cmp r15, [rip + g_mem_live]
    jne 4f
    xor eax, eax
    EPILOGUE
5:  mov r15, [rip + g_mem_live]
    mov rdi, [rbx + 16]
    call ext_root_open
    test rax, rax
    js 4f
    mov r12, rax
    lea rdi, [rsp + 96]
    mov rsi, rax
    call fmt_u64
    mov byte ptr [rsp + rax + 96], 0
    mov rax, [rbx]
    mov [rsp + 128], rax
    lea rax, [rip + esc_flag]
    mov [rsp + 136], rax
    lea rax, [rsp + 96]
    mov [rsp + 144], rax
    lea rax, [rip + esc_epoch]
    mov [rsp + 152], rax
    lea rax, [rip + esc_job]
    mov [rsp + 160], rax
    lea rax, [rip + esc_nonce]
    mov [rsp + 168], rax
    mov edi, 6
    lea rsi, [rsp + 128]
    call ext_store_snapshot_main
    test rax, rax
    jnz 4f
    mov rdi, r12
    lea rsi, [rsp + 64]
    call ext_root_stat
    test rax, rax
    jns 4f
    cmp r15, [rip + g_mem_live]
    jne 4f
    xor eax, eax
    EPILOGUE
3:  call ext_store_snapshot_main
    EPILOGUE
4:  mov eax, 1
    EPILOGUE
.section .rodata
esc_borrowed: .asciz "--emit-borrowed"
esc_owned: .asciz "--emit-owned-root"
esc_flag: .asciz "--extension-store-snapshot"
esc_epoch: .asciz "7"
esc_job: .asciz "9"
esc_nonce: .asciz "000102030405060708090a0b0c0d0e0f"
