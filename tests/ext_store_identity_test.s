.include "rhun.inc"
.include "app/extstore.inc"
.section .rodata
esi_good: .asciz "Foo.-_9"
esi_encoded: .asciz "466f6f2e2d5f39"
esi_upper: .asciz "466F6f"
esi_badhex: .asciz "2f"
esi_dot: .asciz ".foo"
esi_unicode: .byte 0xc3,0xa9,0
esi_root: .asciz "/root"
esi_root_slash: .asciz "/root/"
esi_child: .asciz "child"
esi_joined: .asciz "/root/child"
esi_id: .ascii "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
esi_payload: .asciz "/root/.packages/466f6f2e2d5f39/466f6f2e2d5f39/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/payload"
esi_ok: .asciz "ok managed store identity\n"
.bss
esi_bytes: .zero 104
esi_hex: .zero 208
esi_path: .zero 4096
.text
esi_fail:
    mov edi, 71
    call sys_exit
FN main
    PROLOGUE
    lea rdi, [rip + esi_hex]
    lea rsi, [rip + esi_good]
    mov edx, 7
    call ext_store_identity_encode
    cmp rax, 14
    jne esi_fail
    lea rdi, [rip + esi_hex]
    lea rsi, [rip + esi_encoded]
    call strcmp_eq
    test eax, eax
    jz esi_fail
    lea rdi, [rip + esi_bytes]
    lea rsi, [rip + esi_hex]
    mov edx, 14
    call ext_store_identity_decode
    cmp rax, 7
    jne esi_fail
    lea rdi, [rip + esi_bytes]
    lea rsi, [rip + esi_good]
    call strcmp_eq
    test eax, eax
    jz esi_fail
    lea rdi, [rip + esi_bytes]
    lea rsi, [rip + esi_upper]
    mov edx, 6
    call ext_store_identity_decode
    test eax, eax
    jnz esi_fail
    lea rdi, [rip + esi_bytes]
    lea rsi, [rip + esi_badhex]
    mov edx, 2
    call ext_store_identity_decode
    test eax, eax
    jnz esi_fail
    lea rdi, [rip + esi_dot]
    call ext_store_identity_len
    test eax, eax
    jnz esi_fail
    lea rdi, [rip + esi_unicode]
    call ext_store_identity_len
    test eax, eax
    jnz esi_fail
    lea rdi, [rip + esi_bytes]
    mov esi, 'a'
    mov edx, 100
    call memset
    lea rdi, [rip + esi_bytes]
    call ext_store_identity_len
    cmp rax, 100
    jne esi_fail
    mov byte ptr [rip + esi_bytes + 100], 'a'
    lea rdi, [rip + esi_bytes]
    call ext_store_identity_len
    test eax, eax
    jnz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_root]
    lea rdx, [rip + esi_child]
    call ext_store_join
    test rax, rax
    jnz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_joined]
    call strcmp_eq
    test eax, eax
    jz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_root_slash]
    lea rdx, [rip + esi_child]
    call ext_store_join
    test rax, rax
    jnz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_joined]
    call strcmp_eq
    test eax, eax
    jz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_root]
    lea rdx, [rip + esi_good]
    lea rcx, [rip + esi_good]
    lea r8, [rip + esi_id]
    call ext_store_payload_path
    test rax, rax
    jnz esi_fail
    lea rdi, [rip + esi_path]
    lea rsi, [rip + esi_payload]
    call strcmp_eq
    test eax, eax
    jz esi_fail
    lea rdi, [rip + esi_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
