.include "rhun.inc"
.section .rodata
.p2align 3
sht_vectors:
    .quad sht_abc,0,sht_empty_digest
    .quad sht_abc,3,sht_abc_digest
    .quad sht_long,56,sht_long_digest
    .quad 0,0,0
# NIST SHA256.pdf one-block and two-block examples.
sht_empty_digest:
    .byte 0xe3,0xb0,0xc4,0x42,0x98,0xfc,0x1c,0x14,0x9a,0xfb,0xf4,0xc8,0x99,0x6f,0xb9,0x24
    .byte 0x27,0xae,0x41,0xe4,0x64,0x9b,0x93,0x4c,0xa4,0x95,0x99,0x1b,0x78,0x52,0xb8,0x55
sht_abc_digest:
    .byte 0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23
    .byte 0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad
sht_long_digest:
    .byte 0x24,0x8d,0x6a,0x61,0xd2,0x06,0x38,0xb8,0xe5,0xc0,0x26,0x93,0x0c,0x3e,0x60,0x39
    .byte 0xa3,0x3c,0xe4,0x59,0x64,0xff,0x21,0x67,0xf6,0xec,0xed,0xd4,0x19,0xdb,0x06,0xc1
sht_million_digest:
    .byte 0xcd,0xc7,0x6e,0x5c,0x99,0x14,0xfb,0x92,0x81,0xa1,0xc7,0xe2,0x84,0xd7,0x3e,0x67
    .byte 0xf1,0x80,0x9a,0x48,0xa4,0x97,0x20,0x0e,0x04,0x6d,0x39,0xcc,0xc7,0x11,0x2c,0xd0
sht_abc: .ascii "abc"
sht_long: .ascii "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
sht_ok: .asciz "ok native streaming SHA-256\n"
.bss
.p2align 3
sht_ctx: .zero SH256_SIZE
sht_other: .zero SH256_SIZE
sht_snapshot: .zero SH256_SIZE
sht_out: .zero 32
sht_expected: .zero 32
sht_guarded: .zero 48
sht_output_snapshot: .zero 48
sht_pattern: .zero 131
sht_a: .zero 1000
sht_hex: .zero 65
sht_stage: .quad 0
sht_live: .quad 0
.text
sht_fail:
    mov rdi, [rip + sht_stage]
    inc edi
    call sys_exit
sht_check:
    cmp eax, 1
    jne sht_fail
    ret
sht_equal:
    mov edx, 32
    call memeq
    test eax, eax
    jz sht_fail
    ret
sht_capture:
    PROLOGUE
    lea rdi, [rip + sht_snapshot]
    lea rsi, [rip + sht_ctx]
    mov edx, SH256_SIZE
    call memcpy
    lea rdi, [rip + sht_output_snapshot]
    lea rsi, [rip + sht_guarded]
    mov edx, 48
    call memcpy
    EPILOGUE
sht_unchanged:
    test eax, eax
    jnz sht_fail
    lea rdi, [rip + sht_snapshot]
    lea rsi, [rip + sht_ctx]
    mov edx, SH256_SIZE
    call memeq
    test eax, eax
    jz sht_fail
    lea rdi, [rip + sht_output_snapshot]
    lea rsi, [rip + sht_guarded]
    mov edx, 48
    call memeq
    test eax, eax
    jz sht_fail
    ret
sht_init:
    lea rdi, [rip + sht_ctx]
    jmp sha256_init
sht_update:
    lea rdi, [rip + sht_ctx]
    call sha256_update
    jmp sht_check
sht_final:
    lea rdi, [rip + sht_ctx]
    lea rsi, [rip + sht_out]
    call sha256_final
    jmp sht_check
sht_balanced:
    mov rax, [rip + sht_live]
    cmp rax, [rip + g_mem_live]
    jne sht_fail
    ret
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + sht_live], rax
    cmp qword ptr [rip + g_argc], 1
    jne sht_file
    lea r15, [rip + sht_vectors]
.Lsht_known:
    mov rbx, [r15]
    test rbx, rbx
    jz .Lsht_splits
    inc qword ptr [rip + sht_stage]
    mov rdi, rbx
    mov rsi, [r15 + 8]
    lea rdx, [rip + sht_out]
    call sha256_hash
    call sht_check
    lea rdi, [rip + sht_out]
    mov rsi, [r15 + 16]
    call sht_equal
    call sht_init
    xor r12d, r12d
1:  cmp r12, [r15 + 8]
    jae 2f
    lea rsi, [rbx + r12]
    mov edx, 1
    call sht_update
    inc r12
    jmp 1b
2:  call sht_final
    lea rdi, [rip + sht_out]
    mov rsi, [r15 + 16]
    call sht_equal
    add r15, 24
    jmp .Lsht_known
.Lsht_splits:
    inc qword ptr [rip + sht_stage]
    lea rbx, [rip + sht_pattern + 1]
    xor ecx, ecx
1:  imul eax, ecx, 73
    add eax, 19
    mov [rbx + rcx], al
    inc ecx
    cmp ecx, 129
    jb 1b
    xor r12d, r12d
2:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + sht_expected]
    call sha256_hash
    call sht_check
    xor r13d, r13d
3:  call sht_init
    mov rsi, rbx
    mov rdx, r13
    call sht_update
    lea rsi, [rbx + r13]
    mov rdx, r12
    sub rdx, r13
    call sht_update
    call sht_final
    lea rdi, [rip + sht_out]
    lea rsi, [rip + sht_expected]
    call sht_equal
    call sht_balanced
    inc r13
    cmp r13, r12
    jbe 3b
    inc r12
    cmp r12, 129
    jbe 2b

    # Independent contexts interleaved through partial and final calls.
    inc qword ptr [rip + sht_stage]
    call sht_init
    lea rdi, [rip + sht_other]
    call sha256_init
    lea rsi, [rip + sht_abc]
    mov edx, 1
    call sht_update
    lea rdi, [rip + sht_other]
    lea rsi, [rip + sht_long]
    mov edx, 56
    call sha256_update
    call sht_check
    lea rsi, [rip + sht_abc + 1]
    mov edx, 2
    call sht_update
    call sht_final
    lea rdi, [rip + sht_out]
    lea rsi, [rip + sht_abc_digest]
    call sht_equal
    lea rdi, [rip + sht_other]
    lea rsi, [rip + sht_out]
    call sha256_final
    call sht_check
    lea rdi, [rip + sht_out]
    lea rsi, [rip + sht_long_digest]
    call sht_equal

    inc qword ptr [rip + sht_stage]
    lea rdi, [rip + sht_a]
    mov esi, 'a'
    mov edx, 1000
    call memset
    call sht_init
    mov r12d, 1000
1:  lea rsi, [rip + sht_a]
    mov edx, 1000
    call sht_update
    dec r12d
    jnz 1b
    call sht_final
    lea rdi, [rip + sht_out]
    lea rsi, [rip + sht_million_digest]
    call sht_equal

    # Finalized calls reject and preserve context and guarded output bytes.
    inc qword ptr [rip + sht_stage]
    lea rdi, [rip + sht_guarded]
    mov esi, 0xa5
    mov edx, 48
    call memset
    call sht_capture
    lea rdi, [rip + sht_ctx]
    lea rsi, [rip + sht_guarded + 8]
    call sha256_final
    call sht_unchanged
    xor ecx, ecx
1:  lea rdx, [rip + sht_guarded]
    cmp byte ptr [rdx + rcx], 0xa5
    jne sht_fail
    inc ecx
    cmp ecx, 48
    jb 1b
    lea rdi, [rip + sht_ctx]
    mov rsi, -1
    mov rdx, -1
    call sha256_update
    call sht_unchanged
    lea rdi, [rip + sht_ctx]
    xor esi, esi
    xor edx, edx
    call sha256_update
    call sht_unchanged

    # Reuse and NULL/zero input, including output guard bytes on success.
    inc qword ptr [rip + sht_stage]
    call sht_init
    xor esi, esi
    xor edx, edx
    call sht_update
    call sht_capture
    lea rdi, [rip + sht_ctx]
    xor esi, esi
    mov edx, 1
    call sha256_update
    call sht_unchanged
    lea rdi, [rip + sht_ctx]
    xor esi, esi
    call sha256_final
    call sht_unchanged
    lea rdi, [rip + sht_ctx]
    lea rsi, [rip + sht_guarded + 8]
    call sha256_final
    call sht_check
    lea rdi, [rip + sht_guarded + 8]
    lea rsi, [rip + sht_empty_digest]
    call sht_equal
    mov rax, 0xa5a5a5a5a5a5a5a5
    cmp [rip + sht_guarded], rax
    jne sht_fail
    cmp [rip + sht_guarded + 40], rax
    jne sht_fail

    # Reject overflow before touching deliberately invalid source addresses.
    inc qword ptr [rip + sht_stage]
    call sht_init
    mov rax, SH256_BYTES_MAX
    mov [rip + sht_ctx + SH256_bytes], rax
    mov qword ptr [rip + sht_ctx + SH256_used], 63
    call sht_capture
    lea rdi, [rip + sht_ctx]
    mov rsi, -1
    mov edx, 1
    call sha256_update
    call sht_unchanged
    lea rdi, [rip + sht_ctx]
    mov rsi, -1
    mov rdx, -1
    call sha256_update
    call sht_unchanged
    xor esi, esi
    xor edx, edx
    call sht_update
    call sht_final
    mov rax, 0xf8ffffffffffffff
    cmp [rip + sht_ctx + SH256_block + 56], rax
    jne sht_fail

    # A final representable byte succeeds. Invalid count, used and mismatch reject.
    inc qword ptr [rip + sht_stage]
    call sht_init
    mov rax, SH256_BYTES_MAX - 1
    mov [rip + sht_ctx + SH256_bytes], rax
    mov qword ptr [rip + sht_ctx + SH256_used], 62
    lea rsi, [rip + sht_abc]
    mov edx, 1
    call sht_update
    mov rax, SH256_BYTES_MAX
    cmp [rip + sht_ctx + SH256_bytes], rax
    jne sht_fail
    cmp qword ptr [rip + sht_ctx + SH256_used], 63
    jne sht_fail
    mov rax, 1 << 61
    mov [rip + sht_ctx + SH256_bytes], rax
    mov qword ptr [rip + sht_ctx + SH256_used], 0
    call sht_reject_state
    call sht_init
    mov qword ptr [rip + sht_ctx + SH256_used], 64
    call sht_reject_state
    call sht_init
    mov qword ptr [rip + sht_ctx + SH256_bytes], 1
    call sht_reject_state

    inc qword ptr [rip + sht_stage]
    call sht_capture
    xor edi, edi
    mov esi, 1
    lea rdx, [rip + sht_guarded]
    call sha256_hash
    call sht_unchanged
    mov rdi, -1
    mov rsi, -1
    lea rdx, [rip + sht_guarded]
    call sha256_hash
    call sht_unchanged
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call sha256_hash
    call sht_unchanged
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + sht_out]
    call sha256_hash
    call sht_check
    lea rdi, [rip + sht_out]
    lea rsi, [rip + sht_empty_digest]
    call sht_equal
    call sht_balanced
    lea rdi, [rip + sht_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE

sht_reject_state:
    PROLOGUE
    call sht_capture
    lea rdi, [rip + sht_ctx]
    mov rsi, -1
    mov rdx, -1
    call sha256_update
    call sht_unchanged
    lea rdi, [rip + sht_ctx]
    lea rsi, [rip + sht_guarded + 8]
    call sha256_final
    call sht_unchanged
    EPILOGUE

# Test driver only: bounded file and chunk size -> a single digest on stdout.
sht_file:
    cmp qword ptr [rip + g_argc], 3
    jne sht_fail
    mov rax, [rip + g_argv]
    mov rbx, [rax + 8]
    mov r12, [rax + 16]
    mov rdi, r12
    call strlen
    test rax, rax
    jz sht_fail
    cmp rax, 7
    ja sht_fail
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    call parse_u64
    cmp rdx, r13
    jne sht_fail
    test rax, rax
    jz sht_fail
    cmp rax, 2097152
    ja sht_fail
    mov r13, rax
    mov rdi, rbx
    mov esi, 2097152
    call file_read_limited
    test rax, rax
    jz sht_fail
    mov rbx, rax
    mov r12, rdx
    mov r14, rax
    call sht_init
1:  test r12, r12
    jz 2f
    mov r15, r13
    cmp r15, r12
    cmova r15, r12
    mov rsi, r14
    mov rdx, r15
    call sht_update
    add r14, r15
    sub r12, r15
    jmp 1b
2:  call sht_final
    mov rdi, rbx
    call mem_free
    call sht_balanced
    lea rbx, [rip + sht_out]
    lea r12, [rip + sht_hex]
    lea r13, [rip + hexdigits]
    xor ecx, ecx
3:  movzx eax, byte ptr [rbx + rcx]
    mov edx, eax
    shr eax, 4
    and edx, 15
    mov al, [r13 + rax]
    mov dl, [r13 + rdx]
    mov [r12 + rcx*2], al
    mov [r12 + rcx*2 + 1], dl
    inc ecx
    cmp ecx, 32
    jb 3b
    mov byte ptr [r12 + 64], 10
    mov edi, 1
    mov rsi, r12
    mov edx, 65
    call write_all
    test rax, rax
    jnz sht_fail
    xor eax, eax
    EPILOGUE
