# SHA-256, FIPS 180-4 sections 4.1.2, 4.2.2 and 6.2. Caller-owned streaming context.
# No heap or shared mutable state. Input/output must not overlap the context.
.include "rhun.inc"
.section .rodata
.p2align 2
sh256_k:
    .long 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5
    .long 0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5
    .long 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3
    .long 0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174
    .long 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc
    .long 0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da
    .long 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7
    .long 0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967
    .long 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13
    .long 0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85
    .long 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3
    .long 0xd192e819,0xd6990624,0xf40e3585,0x106aa070
    .long 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5
    .long 0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3
    .long 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208
    .long 0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
sh256_initial:
    .long 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
    .long 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
.text

# sha256_init(ctx): reset, including the buffer and reserved bytes.
FN sha256_init
    mov r8, rdi
    mov ecx, SH256_SIZE
    xor eax, eax
    rep stosb
    mov rdi, r8
    lea rsi, [rip + sh256_initial]
    mov ecx, 32
    rep movsb
    ret

# Internal active-context check. The context's allocation/lifetime is caller-owned.
.Lsh256_valid:
    cmp qword ptr [rdi + SH256_finalized], 0
    jne .Lsh256_invalid
    mov rax, [rdi + SH256_bytes]
    mov rcx, SH256_BYTES_MAX
    cmp rax, rcx
    ja .Lsh256_invalid
    mov rdx, [rdi + SH256_used]
    cmp rdx, 63
    ja .Lsh256_invalid
    and eax, 63
    cmp rax, rdx
    jne .Lsh256_invalid
    mov eax, 1
    ret
.Lsh256_invalid:
    xor eax, eax
    ret

# sha256_update(ctx, source, length) -> 1, or 0 with the context unchanged.
FN sha256_update
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call .Lsh256_valid
    test eax, eax
    jz .Lsh256_update_bad
    test r13, r13
    jz .Lsh256_update_ok
    test r12, r12
    jz .Lsh256_update_bad
    mov rax, SH256_BYTES_MAX
    sub rax, [rbx + SH256_bytes]
    cmp r13, rax
    ja .Lsh256_update_bad
    add [rbx + SH256_bytes], r13
    mov r14, [rbx + SH256_used]
    test r14, r14
    jz .Lsh256_update_blocks
    mov r15d, 64
    sub r15, r14
    cmp r15, r13
    cmova r15, r13
    lea rdi, [rbx + SH256_block]
    add rdi, r14
    mov rsi, r12
    mov rcx, r15
    rep movsb
    add r12, r15
    sub r13, r15
    add r14, r15
    cmp r14, 64
    jb .Lsh256_update_used
    mov rdi, rbx
    lea rsi, [rbx + SH256_block]
    call .Lsh256_compress
.Lsh256_update_blocks:
    cmp r13, 64
    jb .Lsh256_update_tail
    mov rdi, rbx
    mov rsi, r12
    call .Lsh256_compress
    add r12, 64
    sub r13, 64
    jmp .Lsh256_update_blocks
.Lsh256_update_tail:
    mov r14, r13
    lea rdi, [rbx + SH256_block]
    mov rsi, r12
    mov rcx, r13
    rep movsb
.Lsh256_update_used:
    mov [rbx + SH256_used], r14
.Lsh256_update_ok:
    mov eax, 1
    EPILOGUE
.Lsh256_update_bad:
    xor eax, eax
    EPILOGUE

# sha256_final(ctx, output32) -> 1. A second final or invalid state returns 0 unchanged.
FN sha256_final
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .Lsh256_final_bad
    call .Lsh256_valid
    test eax, eax
    jz .Lsh256_final_bad
    mov r13, [rbx + SH256_used]
    lea rdi, [rbx + SH256_block]
    mov byte ptr [rdi + r13], 0x80
    inc r13
    add rdi, r13
    mov ecx, 64
    sub rcx, r13
    xor eax, eax
    rep stosb
    cmp r13, 56
    jbe .Lsh256_final_length
    mov rdi, rbx
    lea rsi, [rbx + SH256_block]
    call .Lsh256_compress
    lea rdi, [rbx + SH256_block]
    mov ecx, 64
    xor eax, eax
    rep stosb
.Lsh256_final_length:
    mov rax, [rbx + SH256_bytes]
    shl rax, 3
    bswap rax
    mov [rbx + SH256_block + 56], rax
    mov rdi, rbx
    lea rsi, [rbx + SH256_block]
    call .Lsh256_compress
    xor ecx, ecx
1:  mov eax, [rbx + rcx*4]
    bswap eax
    mov [r12 + rcx*4], eax
    inc ecx
    cmp ecx, 8
    jb 1b
    mov qword ptr [rbx + SH256_finalized], 1
    mov eax, 1
    EPILOGUE
.Lsh256_final_bad:
    xor eax, eax
    EPILOGUE

# sha256_hash(source, length, output32) -> 1/0, with output unchanged on error.
FN sha256_hash
    PROLOGUE SH256_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .Lsh256_hash_bad
    test r12, r12
    jz 1f
    test rbx, rbx
    jz .Lsh256_hash_bad
1:  mov rax, SH256_BYTES_MAX
    cmp r12, rax
    ja .Lsh256_hash_bad
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call sha256_update
    mov rdi, rsp
    mov rsi, r13
    call sha256_final
    EPILOGUE
.Lsh256_hash_bad:
    xor eax, eax
    EPILOGUE

# Compress one complete 64-byte block. Schedule and working words are private stack data.
.Lsh256_compress:
    PROLOGUE 272
    mov rbx, rdi
    xor ecx, ecx
1:  mov eax, [rsi + rcx*4]
    bswap eax
    mov [rsp + rcx*4], eax
    inc ecx
    cmp ecx, 16
    jb 1b
2:  mov eax, [rsp + rcx*4 - 60]
    mov edx, eax
    mov edi, eax
    ror eax, 7
    ror edx, 18
    shr edi, 3
    xor eax, edx
    xor eax, edi
    mov edx, [rsp + rcx*4 - 8]
    mov esi, edx
    mov edi, edx
    ror edx, 17
    ror esi, 19
    shr edi, 10
    xor edx, esi
    xor edx, edi
    add eax, edx
    add eax, [rsp + rcx*4 - 28]
    add eax, [rsp + rcx*4 - 64]
    mov [rsp + rcx*4], eax
    inc ecx
    cmp ecx, 64
    jb 2b
    mov r8d, [rbx]
    mov r9d, [rbx + 4]
    mov r10d, [rbx + 8]
    mov r11d, [rbx + 12]
    mov r12d, [rbx + 16]
    mov r13d, [rbx + 20]
    mov r14d, [rbx + 24]
    mov r15d, [rbx + 28]
    lea rsi, [rip + sh256_k]
    xor ecx, ecx
3:  # T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]
    mov eax, r12d
    mov edx, r12d
    ror eax, 6
    ror edx, 11
    xor eax, edx
    mov edx, r12d
    ror edx, 25
    xor eax, edx
    add eax, r15d
    mov edx, r13d
    xor edx, r14d
    and edx, r12d
    xor edx, r14d
    add eax, edx
    add eax, [rsi + rcx*4]
    add eax, [rsp + rcx*4]
    mov [rsp + 256], eax
    # T2 = Sigma0(a) + Maj(a,b,c)
    mov edi, r8d
    mov edx, r8d
    ror edi, 2
    ror edx, 13
    xor edi, edx
    mov edx, r8d
    ror edx, 22
    xor edi, edx
    mov edx, r8d
    and edx, r9d
    mov eax, r8d
    xor eax, r9d
    and eax, r10d
    xor eax, edx
    add edi, eax
    mov eax, [rsp + 256]
    mov r15d, r14d
    mov r14d, r13d
    mov r13d, r12d
    mov r12d, r11d
    add r12d, eax
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    mov r8d, eax
    add r8d, edi
    inc ecx
    cmp ecx, 64
    jb 3b
    add [rbx], r8d
    add [rbx + 4], r9d
    add [rbx + 8], r10d
    add [rbx + 12], r11d
    add [rbx + 16], r12d
    add [rbx + 20], r13d
    add [rbx + 24], r14d
    add [rbx + 28], r15d
    EPILOGUE
