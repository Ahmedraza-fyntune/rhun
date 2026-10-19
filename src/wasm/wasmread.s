# WebAssembly binary reading: LEB128 numbers, bytes, names, and the failure exit.
# The readers take the cursor in r12 and the end of the readable bytes in r13, advance r12 and
# change only rax, rcx and rdx; a malformed or truncated number fails the whole load (wasm_fail).
.include "rhun.inc"
.include "wasm/wasm.inc"

.bss
.p2align 3
.globl g_wasm_err
g_wasm_err: .quad 0                 # why the last load failed (a C string)
.globl g_wasm_fail_rsp, g_wasm_fail_rbp, g_wasm_fail_ip
g_wasm_fail_rsp: .quad 0            # where wasm_fail returns to: the load's stack, frame, label
g_wasm_fail_rbp: .quad 0
g_wasm_fail_ip: .quad 0

.text
# wasm_fail(msg cstr): abandons the load in progress; it returns 0 with g_wasm_err set
FN wasm_fail
    mov [rip + g_wasm_err], rdi
    mov rsp, [rip + g_wasm_fail_rsp]
    mov rbp, [rip + g_wasm_fail_rbp]
    jmp [rip + g_wasm_fail_ip]

FN wasm_fail_eof
    lea rdi, [rip + .Lm_eof]
    jmp wasm_fail
FN wasm_fail_long
    lea rdi, [rip + .Lm_long]
    jmp wasm_fail
FN wasm_fail_large
    lea rdi, [rip + .Lm_large]
    jmp wasm_fail

# wasm_byte -> eax
FN wasm_byte
    cmp r12, r13
    jae wasm_fail_eof
    movzx eax, byte ptr [r12]
    inc r12
    ret

# wasm_u32 -> eax (unsigned LEB128, at most 5 bytes)
FN wasm_u32
    push rbx
    xor eax, eax
    xor ecx, ecx
1:  cmp r12, r13
    jae wasm_fail_eof
    movzx ebx, byte ptr [r12]
    inc r12
    cmp ecx, 28
    je 2f
    mov edx, ebx
    and edx, 0x7f
    shl edx, cl
    or eax, edx
    add ecx, 7
    test ebx, 0x80
    jnz 1b
    pop rbx
    ret
2:  test ebx, 0x80
    jnz wasm_fail_long
    test ebx, 0x70
    jnz wasm_fail_large
    shl ebx, 28
    or eax, ebx
    pop rbx
    ret

# wasm_s32, wasm_s33, wasm_s64 -> rax: signed LEB128, sign-extended to 64 bits. The last byte
# a width allows (the fifth, or the tenth) has no continuation bit, and its bits past the width
# repeat the sign bit.
FN wasm_s32
    push rbx
    push r8
    push r9
    mov r8d, 28                     # the last byte's shift
    mov r9d, 3                      # the sign bit's place in it
    jmp .Lsleb
FN wasm_s33
    push rbx
    push r8
    push r9
    mov r8d, 28
    mov r9d, 4
    jmp .Lsleb
FN wasm_s64
    push rbx
    push r8
    push r9
    mov r8d, 63
    xor r9d, r9d
.Lsleb:
    xor eax, eax
    xor ecx, ecx
1:  cmp r12, r13
    jae wasm_fail_eof
    movzx ebx, byte ptr [r12]
    inc r12
    cmp ecx, r8d
    je 3f
    mov rdx, rbx
    and edx, 0x7f
    shl rdx, cl
    or rax, rdx
    add ecx, 7
    test ebx, 0x80
    jnz 1b
    test ebx, 0x40
    jz 2f
    mov rdx, -1
    shl rdx, cl
    or rax, rdx
2:  pop r9
    pop r8
    pop rbx
    ret
3:  test ebx, 0x80
    jnz wasm_fail_long
    # the sign bit and the bits above it: all zeros or all ones
    push rdi
    mov edx, ebx
    mov ecx, r9d
    shr edx, cl
    mov edi, 0x7f
    shr edi, cl
    test edx, edx
    jz 4f
    cmp edx, edi
    jne wasm_fail_large
4:  pop rdi
    mov rdx, rbx
    and edx, 0x7f
    mov ecx, r8d
    shl rdx, cl
    or rax, rdx
    # sign-extend from the top bit of the width: 32, 33 or 64 bits
    lea ecx, [r8 + r9 + 1]
    cmp ecx, 64
    jae 2b
    neg ecx
    add ecx, 64
    shl rax, cl
    sar rax, cl
    jmp 2b

# wasm_count(item bytes at least, edi) -> eax: a count no larger than what the remaining bytes can hold
FN wasm_count
    call wasm_u32
    mov rcx, r13
    sub rcx, r12
    mov edx, eax
    imul rdx, rdi
    cmp rdx, rcx
    ja wasm_fail_eof
    ret

# wasm_bytes(n in edi) -> rax pointer to n bytes, which r12 then passes
FN wasm_bytes
    mov rax, r13
    sub rax, r12
    mov ecx, edi
    cmp rcx, rax
    ja wasm_fail_eof
    mov rax, r12
    add r12, rcx
    ret

# wasm_name -> rax pointer, rdx length: a vector of bytes in UTF-8
FN wasm_name
    call wasm_u32
    mov rcx, r13
    sub rcx, r12
    mov edx, eax
    cmp rdx, rcx
    ja wasm_fail_eof
    push rdi
    push rsi
    mov rdi, r12
    mov rsi, rdx
    add r12, rdx
    push rdi
    push rsi
    call wasm_utf8_ok
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    test eax, eax
    jz 1f
    mov rax, rcx
    ret
1:  lea rdi, [rip + .Lm_utf8]
    jmp wasm_fail

# wasm_utf8_ok(ptr, len) -> eax 1 when it is valid UTF-8: no overlong forms, no surrogates, at
# most U+10FFFF
FN wasm_utf8_ok
    add rsi, rdi                    # end
1:  cmp rdi, rsi
    jae 8f
    movzx eax, byte ptr [rdi]
    inc rdi
    cmp eax, 0x80
    jb 1b
    cmp eax, 0xc2
    jb 9f
    cmp eax, 0xe0
    jb 2f
    cmp eax, 0xf0
    jb 3f
    cmp eax, 0xf5
    jae 9f
    # four bytes: F0 90-BF, F1-F3 80-BF, F4 80-8F
    mov edx, 0x80
    mov ecx, 0xbf
    cmp eax, 0xf0
    jne 4f
    mov edx, 0x90
4:  cmp eax, 0xf4
    jne 5f
    mov ecx, 0x8f
5:  call .Lutf8_cont_range
    call .Lutf8_cont
    call .Lutf8_cont
    jmp 1b
3:  # three bytes: E0 A0-BF, ED 80-9F, others 80-BF
    mov edx, 0x80
    mov ecx, 0xbf
    cmp eax, 0xe0
    jne 6f
    mov edx, 0xa0
6:  cmp eax, 0xed
    jne 7f
    mov ecx, 0x9f
7:  call .Lutf8_cont_range
    call .Lutf8_cont
    jmp 1b
2:  call .Lutf8_cont
    jmp 1b
8:  mov eax, 1
    ret
9:  xor eax, eax
    ret
# the next byte within [edx, ecx], else the caller's caller answers 0
.Lutf8_cont_range:
    cmp rdi, rsi
    jae 1f
    movzx eax, byte ptr [rdi]
    cmp eax, edx
    jb 1f
    cmp eax, ecx
    ja 1f
    inc rdi
    ret
1:  add rsp, 8
    xor eax, eax
    ret
.Lutf8_cont:
    cmp rdi, rsi
    jae 1f
    movzx eax, byte ptr [rdi]
    and eax, 0xc0
    cmp eax, 0x80
    jne 1f
    inc rdi
    ret
1:  add rsp, 8
    xor eax, eax
    ret

.section .rodata
.Lm_eof: .asciz "unexpected end"
.Lm_long: .asciz "integer representation too long"
.Lm_large: .asciz "integer too large"
.Lm_utf8: .asciz "malformed UTF-8 encoding"
