# A cache filter only. Lookup always verifies exact counted identity on a match.
.include "rhun.inc"
.text
# section,seclen,key,keylen ->uint64 hash,RDX0/-EINVAL.
FN ext_settings_queue_identity_hash
    test rdi, rdi
    jz .Lsqh_bad
    test rsi, rsi
    jz .Lsqh_bad
    cmp rsi, 1024
    ja .Lsqh_bad
    test rdx, rdx
    jz .Lsqh_bad
    test rcx, rcx
    jz .Lsqh_bad
    cmp rcx, 256
    ja .Lsqh_bad
    mov r8, rsi
    mov r9, rcx
    mov r10, rdx
    mov eax, 5381
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    mov r11, rax
    shl rax, 5
    add rax, r11
    xor rax, rdx
    inc rcx
    cmp rcx, r8
    jb 1b
    mov r11, rax
    shl rax, 5
    add rax, r11
    xor rax, r8
    mov r11, rax
    shl rax, 5
    add rax, r11
    xor rax, 255
    xor ecx, ecx
2:  movzx edx, byte ptr [r10 + rcx]
    mov r11, rax
    shl rax, 5
    add rax, r11
    xor rax, rdx
    inc rcx
    cmp rcx, r9
    jb 2b
    mov r11, rax
    shl rax, 5
    add rax, r11
    xor rax, r9
    xor edx, edx
    ret
.Lsqh_bad:
    xor eax, eax
    mov rdx, -22
    ret
