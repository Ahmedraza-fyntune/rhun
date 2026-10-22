# Private native operation substitutes. Product objects are never replaced.
.text
FN dst_open
    cmp qword ptr [rip + dst_mode], 10
    je 1f
    SYS SYS_open
    ret
1:  mov rax, -13
    ret
FN dst_close
    PROLOGUE
    SYS SYS_close
    cmp qword ptr [rip + dst_mode], 13
    je 1f
    cmp qword ptr [rip + dst_mode], 16
    je 1f
    cmp qword ptr [rip + dst_mode], 17
    je 1f
    cmp qword ptr [rip + dst_mode], 14
    jne 2f
1:  mov rax, -5
2:  EPILOGUE
FN dst_read
    mov rax, [rip + dst_mode]
    cmp rax, 10
    jb .Ldst_real
    cmp rax, 13
    je .Ldst_real
    cmp rax, 15
    jne 1f
    inc qword ptr [rip + dst_native_reads]
    cmp qword ptr [rip + dst_native_reads], 1
    jne .Ldst_real
    mov rax, -4
    ret
1:  cmp rax, 11
    je .Ldst_eio
    cmp rax, 14
    je .Ldst_eacces
    cmp rax, 12
    je .Ldst_valid
    cmp rax, 20
    jb .Ldst_real
    cmp rax, 28
    ja .Ldst_real
    inc qword ptr [rip + dst_native_reads]
    cmp qword ptr [rip + dst_native_reads], 1
    ja .Ldst_eof
    cmp rax, 20
    je .Ldst_big
    cmp rax, 21
    je .Ldst_short
    # Every remaining synthetic batch starts with a valid record for "a".
    mov word ptr [rsi + 16], 24
    mov word ptr [rsi + 19], 'a'
    cmp rax, 22
    jne 2f
    mov word ptr [rsi + 16], 0
2:  cmp rax, 23
    jne 3f
    mov word ptr [rsi + 16], 25
3:  cmp rax, 24
    jne 4f
    mov dword ptr [rsi + 19], 0x61616161
    mov byte ptr [rsi + 23], 'a'
4:  cmp rax, 25
    jne 5f
    mov byte ptr [rsi + 19], 0
5:  cmp rax, 26
    jne 6f
    mov word ptr [rsi + 19], '/'
6:  cmp rax, 27
    jne 7f
    # A record can be bounded yet exceed the scanner's basename limit.
    PROLOGUE
    mov rbx, rsi
    lea rdi, [rsi + 19]
    mov esi, 'a'
    mov edx, 4096
    call memset
    mov byte ptr [rbx + 4115], 0
    mov word ptr [rbx + 16], 4116
    mov eax, 4116
    EPILOGUE
7:  cmp rax, 28
    jne 8f
    # A valid record followed by a one-byte truncated header.
    mov eax, 25
    ret
8:  mov eax, 24
    ret
.Ldst_valid:
    inc qword ptr [rip + dst_native_reads]
    cmp qword ptr [rip + dst_native_reads], 1
    jne .Ldst_eio
    mov word ptr [rsi + 16], 24
    mov word ptr [rsi + 19], 'a'
    mov eax, 24
    ret
.Ldst_eof:
    xor eax, eax
    ret
.Ldst_eacces:
    mov rax, -13
    ret
.Ldst_eio:
    mov rax, -5
    ret
.Ldst_big:
    mov eax, 32769
    ret
.Ldst_short:
    mov eax, 19
    ret
.Ldst_real:
    SYS SYS_getdents64
    ret
