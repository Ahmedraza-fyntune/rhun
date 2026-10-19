# Portable replacement text programs. Validation allocates nothing and retains no caller data.
.include "rhun.inc"
.text
# snippet_replacement_validate(ptr, len) -> eax valid, edx error byte offset
FN snippet_replacement_validate
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov edx, esi
    cmp rsi, 32
    jb .Lrpv_bad
    mov edx, 20
    cmp rsi, 4194304
    ja .Lrpv_bad
    xor edx, edx
    cmp dword ptr [rbx], 0x46524e52
    jne .Lrpv_bad
    mov edx, 4
    cmp dword ptr [rbx + 4], 1
    jne .Lrpv_bad
    mov edx, 8
    cmp dword ptr [rbx + 8], 0x00100000
    jne .Lrpv_bad
    mov edx, 24
    cmp dword ptr [rbx + 24], 0
    jne .Lrpv_bad
    mov edx, 28
    cmp dword ptr [rbx + 28], 0
    jne .Lrpv_bad
    mov r13d, [rbx + 12]
    mov edx, 12
    cmp r13, 8192
    ja .Lrpv_bad
    imul rax, r13, 24
    add rax, 32
    mov [rsp + 16], rax          # blob offset
    lea rcx, [rbx + rax]
    mov [rsp], rcx               # blob pointer
    mov ecx, [rbx + 16]
    mov [rsp + 8], rcx           # blob bytes
    add rax, rcx
    mov edx, 20
    cmp rax, 4194304
    ja .Lrpv_bad
    cmp rax, r12
    jne .Lrpv_bad
    mov ecx, [rbx + 20]
    cmp rax, rcx
    jne .Lrpv_bad
    xor r14d, r14d
.Lrpv_utf8:
    cmp r14, [rsp + 8]
    jae .Lrpv_records
    mov rdi, [rsp]
    add rdi, r14
    mov rsi, [rsp + 8]
    sub rsi, r14
    call utf8_decode
    cmp eax, 0x10ffff
    ja .Lrpv_utf8_bad
    cmp eax, 0xd800
    jb 1f
    cmp eax, 0xdfff
    jbe .Lrpv_utf8_bad
1:  cmp eax, 0xfffd
    jne 2f
    cmp edx, 1
    je .Lrpv_utf8_bad
2:  add r14, rdx
    jmp .Lrpv_utf8
.Lrpv_utf8_bad:
    mov rdx, [rsp + 16]
    add rdx, r14
    jmp .Lrpv_bad
.Lrpv_records:
    xor r14d, r14d              # canonical string cursor
    lea r15, [rbx + 32]
.Lrpv_record:
    test r13, r13
    jz .Lrpv_tail
    mov r12d, [r15]
    cmp r12d, 11
    ja .Lrpv_op_bad
    mov eax, [r15 + 4]
    cmp eax, 0x7fffffff
    ja .Lrpv_index_bad
    test r12d, r12d
    jnz 1f
    test eax, eax
    jnz .Lrpv_index_bad
1:  xor r9d, r9d
    test r12d, r12d
    jz 2f
    cmp r12d, 9
    jb 3f
2:  mov r9d, 1
3:  mov rdi, rbx
    lea rsi, [r15 + 8]
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    mov r8, r14
    call snippet_replacement_span
    test eax, eax
    jz .Lrpv_bad
    mov r14, r8
    xor r9d, r9d
    cmp r12d, 11
    jne 4f
    mov r9d, 1
4:  mov rdi, rbx
    lea rsi, [r15 + 16]
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    mov r8, r14
    call snippet_replacement_span
    test eax, eax
    jz .Lrpv_bad
    mov r14, r8
    add r15, 24
    dec r13
    jmp .Lrpv_record
.Lrpv_tail:
    cmp r14, [rsp + 8]
    jne .Lrpv_tail_bad
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrpv_tail_bad:
    mov rdx, [rsp + 16]
    add rdx, r14
    jmp .Lrpv_bad
.Lrpv_op_bad:
    mov rdx, r15
    sub rdx, rbx
    jmp .Lrpv_bad
.Lrpv_index_bad:
    lea rdx, [r15 + 4]
    sub rdx, rbx
.Lrpv_bad:
    xor eax, eax
    EPILOGUE
# (program, offset/length field, UTF8 blob, blob len, cursor, used) -> eax valid, r8 cursor, edx error
# Whole-blob UTF8 and cursor bounds have been checked by the caller.
FN snippet_replacement_span
    mov r10, rdx
    mov r11d, [rsi]
    mov eax, [rsi + 4]
    test r9, r9
    jnz 1f
    or eax, r11d
    jnz .Lrps_offset
    jmp .Lrps_ok
1:  cmp r11, r8
    jne .Lrps_offset
    mov r11, rcx
    sub r11, r8
    cmp rax, r11
    ja .Lrps_length
    lea r11, [r8 + rax]
    cmp r8, rcx
    je 2f
    movzx eax, byte ptr [r10 + r8]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lrps_offset
2:  cmp r11, rcx
    je 3f
    movzx eax, byte ptr [r10 + r11]
    and eax, 0xc0
    cmp eax, 0x80
    je .Lrps_length
3:  mov r8, r11
.Lrps_ok:
    mov eax, 1
    xor edx, edx
    ret
.Lrps_length:
    lea rdx, [rsi + 4]
    sub rdx, rdi
    xor eax, eax
    ret
.Lrps_offset:
    mov rdx, rsi
    sub rdx, rdi
    xor eax, eax
    ret
