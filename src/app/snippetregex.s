# Portable snippet regex bytecode. Validation never executes or retains its input.
.include "rhun.inc"
.text
# snippet_regex_validate(ptr, len) -> eax valid, edx error byte offset (zero on success)
FN snippet_regex_validate
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov edx, esi
    cmp rsi, 48
    jb .Lrxv_bad
    mov edx, 40
    cmp rsi, 262144
    ja .Lrxv_bad
    xor edx, edx
    cmp dword ptr [rbx], 0x58524e52
    jne .Lrxv_bad
    mov edx, 4
    cmp dword ptr [rbx + 4], 1
    jne .Lrxv_bad
    mov edx, 8
    cmp dword ptr [rbx + 8], 0x00100000
    jne .Lrxv_bad
    mov edx, 44
    cmp dword ptr [rbx + 44], 0
    jne .Lrxv_bad
    mov r13d, [rbx + 20]
    mov edx, 20
    test r13d, r13d
    jz .Lrxv_bad
    cmp r13d, 8192
    ja .Lrxv_bad
    mov edx, 24
    cmp dword ptr [rbx + 24], 256
    ja .Lrxv_bad
    mov edx, 28
    cmp dword ptr [rbx + 28], 8192
    ja .Lrxv_bad
    mov edx, 32
    cmp dword ptr [rbx + 32], 256
    ja .Lrxv_bad
    mov rax, r13
    shl rax, 4
    lea rcx, [rbx + rax + 48]
    mov [rsp], rcx                 # class array
    mov ecx, [rbx + 24]
    shl rcx, 3
    add rax, rcx
    lea rcx, [rbx + rax + 48]
    mov [rsp + 8], rcx             # range array
    mov ecx, [rbx + 28]
    shl rcx, 3
    add rax, rcx
    lea rcx, [rbx + rax + 48]
    mov [rsp + 16], rcx            # repeat array
    mov ecx, [rbx + 32]
    shl rcx, 4
    add rax, rcx
    add rax, 48
    mov edx, 40
    cmp rax, r12
    jne .Lrxv_bad
    mov ecx, [rbx + 40]
    cmp rax, rcx
    jne .Lrxv_bad
    mov edx, 12
    test dword ptr [rbx + 12], -128
    jnz .Lrxv_bad
    mov eax, [rbx + 16]
    mov edx, 16
    cmp eax, 64
    ja .Lrxv_bad
    inc eax
    shl eax, 1
    mov [rsp + 24], rax            # capture slot bound
    mov edx, 36
    cmp [rbx + 36], r13d
    jae .Lrxv_bad
    xor r14d, r14d
    lea r15, [rbx + 48]
.Lrxv_code:
    cmp r14, r13
    jae .Lrxv_classes_begin
    mov eax, [r15]
    cmp eax, 0
    je .Lrxv_match
    cmp eax, 1
    je .Lrxv_char
    cmp eax, 2
    je .Lrxv_dot
    cmp eax, 3
    je .Lrxv_set
    cmp eax, 4
    je .Lrxv_assert
    cmp eax, 5
    je .Lrxv_save
    cmp eax, 6
    je .Lrxv_clear
    cmp eax, 7
    je .Lrxv_split
    cmp eax, 8
    je .Lrxv_jump
    cmp eax, 9
    je .Lrxv_reference
    cmp eax, 10
    je .Lrxv_repeat_start
    cmp eax, 11
    je .Lrxv_repeat_test
    cmp eax, 12
    je .Lrxv_repeat_next
    cmp eax, 13
    je .Lrxv_look
    cmp eax, 14
    je .Lrxv_scoped_assert
    cmp eax, 15
    je .Lrxv_scoped_reference
    jmp .Lrxv_bad_op
.Lrxv_match:
    mov eax, [r15 + 4]
    or eax, [r15 + 8]
    or eax, [r15 + 12]
    jnz .Lrxv_bad_x
    jmp .Lrxv_next
.Lrxv_char:
    mov eax, [r15 + 4]
    cmp eax, 0x10ffff
    ja .Lrxv_bad_x
    cmp eax, 0xd800
    jb .Lrxv_yz
    cmp eax, 0xdfff
    jbe .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_dot:
    mov eax, [r15 + 4]
    or eax, [r15 + 8]
    or eax, [r15 + 12]
    jnz .Lrxv_bad_x
    jmp .Lrxv_fallthrough
.Lrxv_set:
    mov eax, [r15 + 4]
    cmp eax, [rbx + 24]
    jae .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_assert:
    mov eax, [r15 + 4]
    test eax, eax
    jz .Lrxv_bad_x
    cmp eax, 4
    ja .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_save:
    mov eax, [r15 + 4]
    cmp eax, 2
    jb .Lrxv_bad_x
    cmp rax, [rsp + 24]
    jae .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_clear:
    mov eax, [r15 + 4]
    cmp eax, 2
    jb .Lrxv_bad_x
    test eax, 1
    jnz .Lrxv_bad_x
    mov ecx, [r15 + 8]
    test ecx, ecx
    jz .Lrxv_bad_x
    test ecx, 1
    jnz .Lrxv_bad_x
    add rax, rcx
    cmp rax, [rsp + 24]
    ja .Lrxv_bad_x
    cmp dword ptr [r15 + 12], 0
    jne .Lrxv_bad_z
    jmp .Lrxv_fallthrough
.Lrxv_split:
    cmp [r15 + 4], r13d
    jae .Lrxv_bad_x
    cmp [r15 + 8], r13d
    jae .Lrxv_bad_y
    cmp dword ptr [r15 + 12], 0
    jne .Lrxv_bad_z
    jmp .Lrxv_next
.Lrxv_jump:
    cmp [r15 + 4], r13d
    jae .Lrxv_bad_x
    mov eax, [r15 + 8]
    or eax, [r15 + 12]
    jnz .Lrxv_bad_y
    jmp .Lrxv_next
.Lrxv_reference:
    mov eax, [r15 + 4]
    test eax, eax
    jz .Lrxv_bad_x
    cmp eax, [rbx + 16]
    ja .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_scoped_assert:
    mov eax, [r15 + 4]
    test eax, eax
    jz .Lrxv_bad_x
    cmp eax, 4
    ja .Lrxv_bad_x
    test dword ptr [r15 + 8], -7
    jnz .Lrxv_bad_y
    jmp .Lrxv_scoped_z
.Lrxv_scoped_reference:
    mov eax, [r15 + 4]
    test eax, eax
    jz .Lrxv_bad_x
    cmp eax, [rbx + 16]
    ja .Lrxv_bad_x
    test dword ptr [r15 + 8], -3
    jnz .Lrxv_bad_y
.Lrxv_scoped_z:
    cmp dword ptr [r15 + 12], 0
    jne .Lrxv_bad_z
    jmp .Lrxv_fallthrough
.Lrxv_repeat_start:
    mov eax, [r15 + 4]
    cmp eax, [rbx + 32]
    jae .Lrxv_bad_x
    jmp .Lrxv_yz
.Lrxv_repeat_test:
    mov eax, [r15 + 4]
    cmp eax, [rbx + 32]
    jae .Lrxv_bad_x
    cmp [r15 + 8], r13d
    jae .Lrxv_bad_y
    cmp [r15 + 12], r13d
    jae .Lrxv_bad_z
    jmp .Lrxv_next
.Lrxv_repeat_next:
    mov eax, [r15 + 4]
    cmp eax, [rbx + 32]
    jae .Lrxv_bad_x
    cmp [r15 + 8], r13d
    jae .Lrxv_bad_y
    cmp dword ptr [r15 + 12], 0
    jne .Lrxv_bad_z
    jmp .Lrxv_next
.Lrxv_look:
    cmp [r15 + 4], r13d
    jae .Lrxv_bad_x
    cmp [r15 + 8], r13d
    jae .Lrxv_bad_y
    test dword ptr [r15 + 12], -4
    jnz .Lrxv_bad_z
    jmp .Lrxv_next
.Lrxv_yz:
    mov eax, [r15 + 8]
    or eax, [r15 + 12]
    jnz .Lrxv_bad_y
.Lrxv_fallthrough:
    lea rax, [r14 + 1]
    cmp rax, r13
    jae .Lrxv_bad_op
.Lrxv_next:
    inc r14
    add r15, 16
    jmp .Lrxv_code
.Lrxv_classes_begin:
    xor r12d, r12d                # class index
    xor r14d, r14d                # next range index
.Lrxv_class:
    cmp r12d, [rbx + 24]
    jae .Lrxv_ranges_end
    mov r15, [rsp]
    lea r15, [r15 + r12*8]
    mov eax, [r15]
    cmp rax, r14
    jne .Lrxv_bad_op
    mov r8d, [r15 + 4]
    lea rax, [r14 + r8]
    mov ecx, [rbx + 28]
    cmp rax, rcx
    ja .Lrxv_bad_op
    xor r9d, r9d
    xor r11d, r11d                # previous range end, ignored on first row
.Lrxv_range:
    cmp r9, r8
    jae .Lrxv_class_next
    lea rax, [r14 + r9]
    mov r15, [rsp + 8]
    lea r15, [r15 + rax*8]
    mov eax, [r15]
    mov ecx, [r15 + 4]
    cmp eax, ecx
    ja .Lrxv_bad_op
    cmp ecx, 0x10ffff
    ja .Lrxv_bad_op
    cmp eax, 0xd800
    jb 1f
    cmp eax, 0xdfff
    jbe .Lrxv_bad_op
1:  cmp ecx, 0xd800
    jb 2f
    cmp ecx, 0xdfff
    jbe .Lrxv_bad_op
2:  cmp eax, 0xd800
    jae 3f
    cmp ecx, 0xdfff
    ja .Lrxv_bad_op
3:  test r9, r9
    jz 4f
    inc r11d
    cmp eax, r11d
    jbe .Lrxv_bad_op
4:  mov r11d, ecx
    inc r9
    jmp .Lrxv_range
.Lrxv_class_next:
    add r14, r8
    inc r12
    jmp .Lrxv_class
.Lrxv_ranges_end:
    cmp r14d, [rbx + 28]
    jne .Lrxv_unowned
    xor r12d, r12d
.Lrxv_repeat:
    cmp r12d, [rbx + 32]
    jae .Lrxv_ok
    mov r15, r12
    shl r15, 4
    add r15, [rsp + 16]
    mov eax, [r15]
    cmp eax, 0x7fffffff
    ja .Lrxv_bad_op
    mov ecx, [r15 + 4]
    cmp ecx, -1
    je 1f
    cmp ecx, 0x7fffffff
    ja .Lrxv_bad_x
    cmp ecx, eax
    jb .Lrxv_bad_x
1:  test dword ptr [r15 + 8], -2
    jnz .Lrxv_bad_y
    cmp dword ptr [r15 + 12], 0
    jne .Lrxv_bad_z
    inc r12
    jmp .Lrxv_repeat
.Lrxv_unowned:
    mov r15, [rsp + 8]
    lea r15, [r15 + r14*8]
.Lrxv_bad_op:
    mov rdx, r15
    sub rdx, rbx
    jmp .Lrxv_bad
.Lrxv_bad_x:
    lea rdx, [r15 + 4]
    sub rdx, rbx
    jmp .Lrxv_bad
.Lrxv_bad_y:
    lea rdx, [r15 + 8]
    sub rdx, rbx
    jmp .Lrxv_bad
.Lrxv_bad_z:
    lea rdx, [r15 + 12]
    sub rdx, rbx
.Lrxv_bad:
    xor eax, eax
    EPILOGUE
.Lrxv_ok:
    mov eax, 1
    xor edx, edx
    EPILOGUE
