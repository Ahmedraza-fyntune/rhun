# updates: the latest version from the GitHub releases, checked in the background with curl or wget;
# the release's install.sh installs it, and rhun restarts into it
.include "rhun.inc"

.text

# ver_valid(ptr, len) -> 1 for MAJOR.MINOR.PATCH with an optional -suffix of [0-9A-Za-z.], at most
# 31 bytes
FN ver_valid
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 31
    ja 9f
    add rsi, rdi                # end
    xor ecx, ecx                # fields read
1:  # a field: digits
    cmp rdi, rsi
    jae 9f
    movzx edx, byte ptr [rdi]
    sub edx, '0'
    cmp edx, 9
    ja 9f
2:  inc rdi
    cmp rdi, rsi
    jae 3f
    movzx edx, byte ptr [rdi]
    sub edx, '0'
    cmp edx, 9
    jbe 2b
3:  inc ecx
    cmp ecx, 3
    je 4f
    cmp rdi, rsi
    jae 9f
    cmp byte ptr [rdi], '.'
    jne 9f
    inc rdi
    jmp 1b
4:  cmp rdi, rsi
    je 8f
    cmp byte ptr [rdi], '-'
    jne 9f
    inc rdi
    cmp rdi, rsi
    jae 9f                      # a dash with nothing after it
5:  movzx edx, byte ptr [rdi]
    cmp edx, '.'
    je 6f
    mov r8d, edx
    sub r8d, '0'
    cmp r8d, 9
    jbe 6f
    or edx, 0x20
    sub edx, 'a'
    cmp edx, 25
    ja 9f
6:  inc rdi
    cmp rdi, rsi
    jb 5b
8:  mov eax, 1
9:  ret

# ver_cmp(a cstr, b cstr) -> -1, 0 or 1: the numbers compared field by field
FN ver_cmp
    PROLOGUE 64
    mov r12, rsi
    lea rsi, [rsp]
    call ver_fields
    mov rdi, r12
    lea rsi, [rsp + 32]
    call ver_fields
    xor ecx, ecx
1:  mov rax, [rsp + rcx*8]
    cmp rax, [rsp + 32 + rcx*8]
    ja 2f
    jb 3f
    inc ecx
    cmp ecx, 4
    jb 1b
    xor eax, eax
    EPILOGUE
2:  mov eax, 1
    EPILOGUE
3:  mov eax, -1
    EPILOGUE

# ver_fields(cstr, out): up to 4 dot-separated numbers into out[0..3], 0 for those missing; stops at
# anything else, so a -suffix does not count
ver_fields:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    mov [r12], rax
    mov [r12 + 8], rax
    mov [r12 + 16], rax
    mov [r12 + 24], rax
    xor r13d, r13d
1:  movzx eax, byte ptr [rbx]
    sub eax, '0'
    cmp eax, 9
    ja 9f
    mov rdi, rbx
    mov esi, 20
    call parse_u64
    mov [r12 + r13*8], rax
    add rbx, rdx
    inc r13d
    cmp r13d, 4
    jae 9f
    cmp byte ptr [rbx], '.'
    jne 9f
    inc rbx
    jmp 1b
9:  EPILOGUE
