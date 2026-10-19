# Complete bounded request validation runs in the isolated worker before source IO.
.include "rhun.inc"
.include "app/themecapture.inc"
.text
FN tc_request_validate
    PROLOGUE 4224
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Ltcc_bad
    cmp r12, TC_HEADER_SIZE
    jb .Ltcc_bad
    cmp r12, TC_INPUT_CAP
    ja .Ltcc_large
    mov rax, 0x0031514552544852
    cmp [rbx], rax
    jne .Ltcc_bad
    cmp dword ptr [rbx + 8], 1
    jne .Ltcc_bad
    cmp dword ptr [rbx + 12], TC_HEADER_SIZE
    jne .Ltcc_bad
    cmp [rbx + 16], r12
    jne .Ltcc_bad
    cmp dword ptr [rbx + 24], TC_SOURCE_MAX
    ja .Ltcc_bad
    cmp qword ptr [rbx + 32], 0
    jle .Ltcc_bad
    cmp qword ptr [rbx + 40], 0
    jle .Ltcc_bad
    mov rax, [rbx + 48]
    or rax, [rbx + 56]
    jz .Ltcc_bad
    cmp dword ptr [rbx + 100], T_COUNT
    jne .Ltcc_bad
    mov r13d, [rbx + 28]
    test r13d, r13d
    jz 1f
    cmp r13d, 1
    je 2f
    cmp r13d, 3
    jne .Ltcc_bad
    mov r13d, TC_SCOPE_FULL
    jmp 2f
1:  cmp dword ptr [rbx + 96], 0
    jne .Ltcc_bad
    cmp dword ptr [rbx + 24], 0
    je .Ltcc_bad
2:  cmp dword ptr [rbx + 104], r13d
    ja .Ltcc_bad
    mov rax, [rbx + 128]
    or rax, [rbx + 136]
    or rax, [rbx + 144]
    or rax, [rbx + 152]
    cmp dword ptr [rbx + 104], 0
    je 3f
    test rax, rax
    jz .Ltcc_bad
    jmp 4f
3:  test rax, rax
    jnz .Ltcc_bad
4:  lea rdi, [rbx + 108]
    mov esi, 20
    call tc_bytes_zero
    test eax, eax
    jz .Ltcc_bad
    lea rdi, [rbx + 160]
    mov esi, 96
    call tc_bytes_zero
    test eax, eax
    jz .Ltcc_bad
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rsp
    call tc_request_digest
    test eax, eax
    jz .Ltcc_io
    mov rdi, rsp
    lea rsi, [rbx + 64]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Ltcc_bad
    mov r14d, [rbx + 96]
    test r13d, r13d
    jz 5f
    test r14d, r14d
    jz .Ltcc_bad
    cmp r14d, TC_DIR_MAX
    ja .Ltcc_bad
    lea rax, [r14 + TC_HEADER_SIZE]
    cmp rax, r12
    ja .Ltcc_bad
    lea rdi, [rsp + 128]
    lea rsi, [rbx + TC_HEADER_SIZE]
    mov rdx, r14
    call memcpy
    mov byte ptr [rsp + 128 + r14], 0
    lea rdi, [rsp + 128]
    call tc_path_len
    cmp rax, r14
    jne .Ltcc_bad
5:  add r14, TC_HEADER_SIZE
    mov qword ptr [rsp + 80], 0
.Ltcc_row:
    mov eax, [rbx + 24]
    cmp [rsp + 80], rax
    jae .Ltcc_done
    lea rax, [r14 + TC_REQUEST_ROW]
    cmp rax, r12
    ja .Ltcc_bad
    cmp qword ptr [rbx + r14 + 8], 0
    jne .Ltcc_bad
    mov r13d, [rbx + r14]
    mov r15d, [rbx + r14 + 4]
    test r15, r15
    jz .Ltcc_bad
    cmp r15, TC_PATH_MAX
    ja .Ltcc_bad
    add rax, r15
    cmp rax, r12
    ja .Ltcc_bad
    mov [rsp + 88], rax
    xor ecx, ecx
6:  cmp rcx, [rsp + 80]
    jae 7f
    cmp [rsp + 32 + rcx*4], r13d
    je .Ltcc_bad
    inc rcx
    jmp 6b
7:  mov [rsp + 32 + rcx*4], r13d
    lea rdi, [rsp + 128]
    lea rsi, [rbx + r14 + TC_REQUEST_ROW]
    mov rdx, r15
    call memcpy
    mov byte ptr [rsp + 128 + r15], 0
    lea rdi, [rsp + 128]
    call tc_path_len
    cmp rax, r15
    jne .Ltcc_bad
    mov r14, [rsp + 88]
    inc qword ptr [rsp + 80]
    jmp .Ltcc_row
.Ltcc_done:
    cmp r14, r12
    jne .Ltcc_bad
    xor eax, eax
    EPILOGUE
.Ltcc_bad:
    mov rax, -22
    EPILOGUE
.Ltcc_large:
    mov rax, -7
    EPILOGUE
.Ltcc_io:
    mov rax, -5
    EPILOGUE
FN tc_bytes_zero
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 0
    jne 3f
    inc rcx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret
