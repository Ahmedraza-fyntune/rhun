# Fallible counted snapshots for private package preparation. Ancestors must be
# validated separately; the open rejects links only in the final component.
.include "rhun.inc"
.text
# file_read_limited_try(path, max) -> owned NUL-terminated bytes, count;
# on failure -> 0, negative errno. Read at most the initial regular-file size.
FN file_read_limited_try
    test rdi, rdi
    jz .Lfrt_invalid
    mov rax, 0x7ffffffffffffffe
    cmp rsi, rax
    ja .Lfrt_invalid
    PROLOGUE 144
    mov r15, rsi
.ifdef WINDOWS
    call win_open_read_try
.else
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW
    xor edx, edx
    SYS SYS_open
.endif
    test rax, rax
    js .Lfrt_fail
    mov ebx, eax
    mov edi, eax
    mov rsi, rsp
    SYS SYS_fstat
    test rax, rax
    js .Lfrt_close_fail
    mov ecx, [rsp + 24]
    and ecx, 0xf000
    cmp ecx, 0x8000
    je 1f
    mov rax, -22
    cmp ecx, 0x4000
    jne .Lfrt_close_fail
    mov rax, -21
    jmp .Lfrt_close_fail
1:  mov r12, [rsp + 48]
    cmp r12, r15
    ja .Lfrt_oversized
    lea rdi, [r12 + 1]
    call mem_alloc_try
    test rax, rax
    jz .Lfrt_oom
    mov r13, rax
    xor r14d, r14d
.Lfrt_read:
    cmp r14, r12
    jae .Lfrt_done
    mov edi, ebx
    lea rsi, [r13 + r14]
    mov rdx, r12
    sub rdx, r14
    SYS SYS_read
    cmp rax, -EINTR
    je .Lfrt_read
    test rax, rax
    js .Lfrt_free_fail
    jz .Lfrt_done
    add r14, rax
    jmp .Lfrt_read
.Lfrt_done:
    mov byte ptr [r13 + r14], 0
    mov edi, ebx
    SYS SYS_close
    mov rax, r13
    mov rdx, r14
    EPILOGUE
.Lfrt_free_fail:
    mov r15, rax
    mov rdi, r13
    call mem_free
    jmp .Lfrt_close
.Lfrt_oom:
    mov rax, -12
    jmp .Lfrt_close_fail
.Lfrt_oversized:
    mov rax, -27
.Lfrt_close_fail:
    mov r15, rax
.Lfrt_close:
    mov edi, ebx
    SYS SYS_close
    mov rax, r15
.Lfrt_fail:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.Lfrt_invalid:
    mov rdx, -22
    xor eax, eax
    ret
