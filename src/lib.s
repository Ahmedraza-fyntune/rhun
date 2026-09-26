# strings, numbers, utf-8
.include "rhun.inc"

.text

# memcpy(dst, src, n) -> dst
FN memcpy
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    ret

# memmove(dst, src, n) -> dst
FN memmove
    mov rax, rdi
    mov rcx, rdx
    cmp rdi, rsi
    jbe 1f
    lea r8, [rsi + rdx]
    cmp rdi, r8
    jae 1f
    lea rsi, [rsi + rdx - 1]
    lea rdi, [rdi + rdx - 1]
    std
    rep movsb
    cld
    ret
1:  rep movsb
    ret

# memset(dst, byte, n) -> dst
FN memset
    mov r8, rdi
    mov eax, esi
    mov rcx, rdx
    rep stosb
    mov rax, r8
    ret

# memset32(dst, u32, count)
FN memset32
    mov eax, esi
    mov rcx, rdx
    rep stosd
    ret

# memeq(a, b, n) -> 1 if equal
FN memeq
    mov rcx, rdx
    xor eax, eax
    repe cmpsb
    sete al
    ret

# strlen(s) -> n
FN strlen
    mov rax, rdi
1:  cmp byte ptr [rax], 0
    je 2f
    inc rax
    jmp 1b
2:  sub rax, rdi
    ret

# str_eq(a, alen, b, blen) -> 1 if equal
FN str_eq
    xor eax, eax
    cmp rsi, rcx
    jne 1f
    mov rcx, rsi
    mov rsi, rdx
    repe cmpsb
    sete al
1:  ret

# str_eq_cstr(a, alen, cstr) -> 1 if equal
FN str_eq_cstr
    xor eax, eax
1:  test rsi, rsi
    jz 2f
    mov cl, [rdx]
    test cl, cl
    jz 3f
    cmp cl, [rdi]
    jne 3f
    inc rdi
    inc rdx
    dec rsi
    jmp 1b
2:  cmp byte ptr [rdx], 0
    sete al
3:  ret

# str_ieq(a, alen, b, blen) -> 1 if equal ignoring ascii case
FN str_ieq
    xor eax, eax
    cmp rsi, rcx
    jne 3f
1:  test rsi, rsi
    jz 2f
    movzx r8d, byte ptr [rdi]
    movzx r9d, byte ptr [rdx]
    lea r10d, [r8 - 'A']
    cmp r10d, 25
    ja 4f
    or r8d, 0x20
4:  lea r10d, [r9 - 'A']
    cmp r10d, 25
    ja 5f
    or r9d, 0x20
5:  cmp r8d, r9d
    jne 3f
    inc rdi
    inc rdx
    dec rsi
    jmp 1b
2:  mov eax, 1
3:  ret

# str_starts(s, slen, prefix, plen) -> 1 if s starts with prefix
FN str_starts
    xor eax, eax
    cmp rsi, rcx
    jb 1f
    test rcx, rcx
    jz 2f
    mov rsi, rdx
    repe cmpsb
    jne 1f
2:  mov eax, 1
1:  ret

# str_ends(s, slen, suffix, sfxlen) -> 1 if s ends with suffix
FN str_ends
    xor eax, eax
    cmp rsi, rcx
    jb 1f
    add rdi, rsi
    sub rdi, rcx
    mov rsi, rdx
    test rcx, rcx
    jz 2f
    repe cmpsb
    sete al
1:  ret
2:  mov eax, 1
    ret

# str_find(hay, hlen, needle, nlen) -> index or -1
FN str_find
    push rbx
    push r12
    test rcx, rcx
    jz .Lsf_zero
    mov r8, rsi
    sub r8, rcx                 # last start
    jb .Lsf_none
    xor r9d, r9d
    movzx r10d, byte ptr [rdx]
.Lsf_loop:
    cmp r9, r8
    ja .Lsf_none
    cmp r10b, [rdi + r9]
    jne .Lsf_next
    mov r11, 1
.Lsf_cmp:
    cmp r11, rcx
    jae .Lsf_found
    lea rbx, [r9 + r11]
    movzx eax, byte ptr [rdi + rbx]
    cmp al, [rdx + r11]
    jne .Lsf_next
    inc r11
    jmp .Lsf_cmp
.Lsf_next:
    inc r9
    jmp .Lsf_loop
.Lsf_found:
    mov rax, r9
    pop r12
    pop rbx
    ret
.Lsf_zero:
    xor eax, eax
    pop r12
    pop rbx
    ret
.Lsf_none:
    mov rax, -1
    pop r12
    pop rbx
    ret

# str_ifind: same as str_find, ascii case-insensitive
FN str_ifind
    push rbx
    push r12
    push r13
    test rcx, rcx
    jz .Lsif_zero
    mov r8, rsi
    sub r8, rcx
    jb .Lsif_none
    xor r9d, r9d
.Lsif_loop:
    cmp r9, r8
    ja .Lsif_none
    xor r11d, r11d
.Lsif_cmp:
    cmp r11, rcx
    jae .Lsif_found
    lea rbx, [r9 + r11]
    movzx eax, byte ptr [rdi + rbx]
    movzx r12d, byte ptr [rdx + r11]
    lea r13d, [rax - 'A']
    cmp r13d, 25
    ja 1f
    or eax, 0x20
1:  lea r13d, [r12 - 'A']
    cmp r13d, 25
    ja 2f
    or r12d, 0x20
2:  cmp eax, r12d
    jne .Lsif_next
    inc r11
    jmp .Lsif_cmp
.Lsif_next:
    inc r9
    jmp .Lsif_loop
.Lsif_found:
    mov rax, r9
    jmp .Lsif_ret
.Lsif_zero:
    xor eax, eax
    jmp .Lsif_ret
.Lsif_none:
    mov rax, -1
.Lsif_ret:
    pop r13
    pop r12
    pop rbx
    ret

# fmt_u64(buf, value) -> len
FN fmt_u64
    mov rax, rsi
    mov r8, rdi
    lea rsi, [rsp - 32]
    mov rcx, rsi
    mov r9d, 10
1:  xor edx, edx
    div r9
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz 1b
    mov rdx, rsi
    sub rdx, rcx                # len
    mov rax, rdx
    mov rsi, rcx
    mov rdi, r8
    mov rcx, rdx
    rep movsb
    ret

# fmt_hex(buf, value) -> len (lowercase, no prefix)
FN fmt_hex
    mov rax, rsi
    lea rcx, [rsp - 32]
    mov rsi, rcx
1:  mov edx, eax
    and edx, 15
    lea r8, [rip + hexdigits]
    mov dl, [r8 + rdx]
    dec rcx
    mov [rcx], dl
    shr rax, 4
    jnz 1b
    mov rdx, rsi
    sub rdx, rcx
    mov rax, rdx
    mov rsi, rcx
    mov rcx, rdx
    rep movsb
    ret

.section .rodata
.globl hexdigits
hexdigits: .ascii "0123456789abcdef"
.text

# parse_u64(ptr, len) -> rax value, rdx = digits consumed
FN parse_u64
    xor eax, eax
    xor edx, edx
1:  cmp rdx, rsi
    jae 2f
    movzx ecx, byte ptr [rdi + rdx]
    sub ecx, '0'
    cmp ecx, 9
    ja 2f
    imul rax, rax, 10
    add rax, rcx
    inc rdx
    jmp 1b
2:  ret

# parse_hex(ptr, len) -> rax value, rdx = digits consumed
FN parse_hex
    xor eax, eax
    xor edx, edx
1:  cmp rdx, rsi
    jae 3f
    movzx ecx, byte ptr [rdi + rdx]
    lea r8d, [rcx - '0']
    cmp r8d, 9
    jbe 2f
    or ecx, 0x20
    lea r8d, [rcx - 'a']
    cmp r8d, 5
    ja 3f
    add r8d, 10
2:  shl rax, 4
    add rax, r8
    inc rdx
    jmp 1b
3:  ret

# utf8_decode(ptr, avail) -> eax codepoint, edx length (>=1). invalid -> U+FFFD
FN utf8_decode
    test rsi, rsi
    jz .Lud_bad0
    movzx eax, byte ptr [rdi]
    cmp eax, 0x80
    jb .Lud_one
    cmp eax, 0xc2
    jb .Lud_bad
    cmp eax, 0xe0
    jb .Lud_two
    cmp eax, 0xf0
    jb .Lud_three
    cmp eax, 0xf5
    jb .Lud_four
    jmp .Lud_bad
.Lud_one:
    mov edx, 1
    ret
.Lud_two:
    cmp rsi, 2
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x1f
    shl eax, 6
    and ecx, 0x3f
    or eax, ecx
    mov edx, 2
    ret
.Lud_three:
    cmp rsi, 3
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    movzx r9d, byte ptr [rdi + 2]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r9d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x0f
    shl eax, 12
    and ecx, 0x3f
    shl ecx, 6
    or eax, ecx
    and r9d, 0x3f
    or eax, r9d
    cmp eax, 0x800
    jb .Lud_bad
    mov edx, 3
    ret
.Lud_four:
    cmp rsi, 4
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    movzx r9d, byte ptr [rdi + 2]
    movzx r10d, byte ptr [rdi + 3]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r9d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r10d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x07
    shl eax, 18
    and ecx, 0x3f
    shl ecx, 12
    or eax, ecx
    and r9d, 0x3f
    shl r9d, 6
    or eax, r9d
    and r10d, 0x3f
    or eax, r10d
    cmp eax, 0x10000
    jb .Lud_bad
    mov edx, 4
    ret
.Lud_bad:
    mov eax, 0xfffd
    mov edx, 1
    ret
.Lud_bad0:
    xor eax, eax
    mov edx, 1
    ret

# utf8_encode(cp, out) -> length
FN utf8_encode
    cmp edi, 0x80
    jb .Lue_1
    cmp edi, 0x800
    jb .Lue_2
    cmp edi, 0x10000
    jb .Lue_3
    mov eax, edi
    shr eax, 18
    or al, 0xf0
    mov [rsi], al
    mov eax, edi
    shr eax, 12
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, edi
    shr eax, 6
    and al, 0x3f
    or al, 0x80
    mov [rsi + 2], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 3], al
    mov eax, 4
    ret
.Lue_1:
    mov [rsi], dil
    mov eax, 1
    ret
.Lue_2:
    mov eax, edi
    shr eax, 6
    or al, 0xc0
    mov [rsi], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, 2
    ret
.Lue_3:
    mov eax, edi
    shr eax, 12
    or al, 0xe0
    mov [rsi], al
    mov eax, edi
    shr eax, 6
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 2], al
    mov eax, 3
    ret

# is_ident(byte) -> 1 for [A-Za-z0-9_] and bytes >= 0x80
FN is_ident
    movzx eax, dil
    cmp eax, 0x80
    jae 1f
    lea rcx, [rip + ident_table]
    movzx eax, byte ptr [rcx + rax]
    ret
1:  mov eax, 1
    ret

# is_space(byte) -> 1 for space/tab
FN is_space
    xor eax, eax
    cmp dil, ' '
    je 1f
    cmp dil, 9
    jne 2f
1:  mov eax, 1
2:  ret

# to_lower(byte) -> byte
FN to_lower
    movzx eax, dil
    lea ecx, [rax - 'A']
    cmp ecx, 25
    ja 1f
    or eax, 0x20
1:  ret

.section .rodata
.globl ident_table
ident_table:
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0
    .byte 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    .byte 1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1
    .byte 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    .byte 1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0
.text

# path_basename(path, len) -> rax ptr, rdx len
FN path_basename
    lea rax, [rdi + rsi]
    mov rdx, rsi
1:  cmp rax, rdi
    je 2f
    cmp byte ptr [rax - 1], '/'
    je 2f
    dec rax
    jmp 1b
2:  lea rdx, [rdi + rsi]
    sub rdx, rax
    ret

# path_dirlen(path, len) -> length of directory part (without trailing /)
FN path_dirlen
    mov rax, rsi
1:  test rax, rax
    jz 2f
    cmp byte ptr [rdi + rax - 1], '/'
    je 3f
    dec rax
    jmp 1b
3:  dec rax
2:  ret

# path_ext(path, len) -> rax ptr, rdx len of extension after last '.' in basename (len 0 if none)
FN path_ext
    push rdi
    push rsi
    call path_basename
    pop rsi
    pop rdi
    mov r8, rax
    lea rcx, [rax + rdx]
    mov r9, rcx
1:  cmp rcx, r8
    je 2f
    dec rcx
    cmp byte ptr [rcx], '.'
    jne 1b
    cmp rcx, r8
    je 2f
    lea rax, [rcx + 1]
    mov rdx, r9
    sub rdx, rax
    ret
2:  mov rax, r9
    xor edx, edx
    ret
