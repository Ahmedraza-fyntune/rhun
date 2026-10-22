# Canonical RFC 4648 Base64 keeps compiled programs inside text completion APIs.
.include "rhun.inc"
.text
# value(ASCII byte) -> 0..63 or -1. No whitespace or alternate alphabet.
FN snippet_base64_value
    mov eax, edi
    sub eax, 'A'
    cmp eax, 25
    jbe 9f
    mov eax, edi
    sub eax, 'a'
    cmp eax, 25
    ja 1f
    add eax, 26
    ret
1:  mov eax, edi
    sub eax, '0'
    cmp eax, 9
    ja 2f
    add eax, 52
    ret
2:  mov eax, 62
    cmp edi, '+'
    je 9f
    mov eax, 63
    cmp edi, '/'
    je 9f
    mov eax, -1
9:  ret

# decode(readable ASCII bytes, len) -> owned bytes, len, ecx success.
# All failures free output and return 0/0/0. Empty input succeeds without allocation.
FN snippet_base64_decode
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    xor r14d, r14d
    cmp rsi, 5592408
    ja .Lb64_bad
    test rsi, 3
    jnz .Lb64_bad
    test rsi, rsi
    jz .Lb64_empty
    mov r13, rsi
    shr r13, 2
    imul r13, r13, 3
    cmp byte ptr [rbx + r12 - 1], '='
    jne 1f
    dec r13
    cmp byte ptr [rbx + r12 - 2], '='
    jne 1f
    dec r13
1:  cmp r13, SN_BYTES_MAX
    ja .Lb64_bad
    mov rdi, r13
    cmp rdi, 65536
    jae 2f
    mov edi, 65536
2:  call mem_alloc_try
    test rax, rax
    jz .Lb64_bad
    mov r14, rax
    xor r15d, r15d
    mov qword ptr [rsp], 0      # output position
.Lb64_quartet:
    movzx edi, byte ptr [rbx + r15]
    call snippet_base64_value
    test eax, eax
    js .Lb64_bad
    shl eax, 18
    mov [rsp + 16], rax
    movzx edi, byte ptr [rbx + r15 + 1]
    call snippet_base64_value
    test eax, eax
    js .Lb64_bad
    shl eax, 12
    or [rsp + 16], rax
    movzx edi, byte ptr [rbx + r15 + 2]
    cmp edi, '='
    jne .Lb64_third
    cmp byte ptr [rbx + r15 + 3], '='
    jne .Lb64_bad
    lea rax, [r15 + 4]
    cmp rax, r12
    jne .Lb64_bad
    test qword ptr [rsp + 16], 0xf000
    jnz .Lb64_bad
    mov r8d, 1
    jmp .Lb64_emit
.Lb64_third:
    call snippet_base64_value
    test eax, eax
    js .Lb64_bad
    shl eax, 6
    or [rsp + 16], rax
    movzx edi, byte ptr [rbx + r15 + 3]
    cmp edi, '='
    jne .Lb64_fourth
    lea rax, [r15 + 4]
    cmp rax, r12
    jne .Lb64_bad
    test qword ptr [rsp + 16], 0xc0
    jnz .Lb64_bad
    mov r8d, 2
    jmp .Lb64_emit
.Lb64_fourth:
    call snippet_base64_value
    test eax, eax
    js .Lb64_bad
    or [rsp + 16], rax
    mov r8d, 3
.Lb64_emit:
    mov rdx, [rsp]
    lea rcx, [rdx + r8]
    cmp rcx, r13
    ja .Lb64_bad
    mov [rsp], rcx
    add rdx, r14
    mov rax, [rsp + 16]
    shr rax, 16
    mov [rdx], al
    cmp r8, 1
    je .Lb64_next
    mov rax, [rsp + 16]
    shr rax, 8
    mov [rdx + 1], al
    cmp r8, 2
    je .Lb64_next
    mov rax, [rsp + 16]
    mov [rdx + 2], al
.Lb64_next:
    add r15, 4
    cmp r15, r12
    jb .Lb64_quartet
    cmp [rsp], r13
    jne .Lb64_bad
    mov rax, r14
    mov rdx, r13
    mov ecx, 1
    EPILOGUE
.Lb64_empty:
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    EPILOGUE
.Lb64_bad:
    mov rdi, r14
    call mem_free
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
