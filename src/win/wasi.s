# Windows parts of rhun --wasm-host's WASI layer (src/wasm/wasi.s): random bytes, waiting for the
# standard input, sleeping.
.include "win.inc"

.text
# wasi_os_random(buf, len) -> 0 or -errno
FN wasi_os_random
    PROLOGUE 96
    xor ecx, ecx
    mov rdx, rdi
    mov r8d, esi
    mov r9d, 2                          # BCRYPT_USE_SYSTEM_PREFERRED_RNG
    API BCryptGenRandom
    test eax, eax
    js 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -5
    EPILOGUE

# wasi_os_wait_read(fd, timeout ms or -1) -> rax 1 when it can be read (or has ended), 0. A pipe is
# peeked every millisecond (anonymous pipes cannot be waited on); anything else reads at once.
FN wasi_os_wait_read
    PROLOGUE 112
    mov r12d, edi
    mov r13, rsi
    API GetTickCount64
    mov r14, rax
1:  mov edi, r12d
    call win_fd
    test rax, rax
    jz 8f
    mov rcx, [rax + FD_handle]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp + 80], 0
    lea rax, [rsp + 80]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    API PeekNamedPipe
    test eax, eax
    jz 8f                               # not a pipe, or its writer is gone: a read answers
    cmp dword ptr [rsp + 80], 0
    jne 8f
    test r13, r13
    jz 9f
    js 2f
    API GetTickCount64
    sub rax, r14
    cmp rax, r13
    jae 9f
2:  mov ecx, 1
    API Sleep
    jmp 1b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# wasi_os_sleep_ms(ms)
FN wasi_os_sleep_ms
    PROLOGUE 96
    mov rcx, rdi
    API Sleep
    EPILOGUE
