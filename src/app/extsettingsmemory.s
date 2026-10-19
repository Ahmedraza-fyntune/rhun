# Aggregate settings ownership, including retained snapshots, jobs and intent cells.
.include "rhun.inc"
.include "app/extsettingsmemory.inc"
.bss
.p2align 3
esm_charge: .quad 0
esm_retired_head: .quad 0
esm_retired_tail: .quad 0
esm_retired_count: .quad 0
esm_retired_bytes: .quad 0
esm_cleanup: .quad 0
esm_retry_delay: .quad 0
esm_retry_due: .quad 0
.text
FN ext_settings_memory_total
    mov rax, [rip + esm_charge]
    ret
# reserve(bytes)->0/-ENOMEM. The caller owns the exact reservation until release.
FN ext_settings_memory_reserve
    test rdi, rdi
    jz 1f
    cmp rdi, ESM_CAP
    ja 1f
    mov rax, [rip + esm_charge]
    add rax, rdi
    jc 1f
    cmp rax, ESM_CAP
    ja 1f
    mov [rip + esm_charge], rax
    xor eax, eax
    ret
1:  mov rax, -12
    ret
FN ext_settings_memory_release
    test rdi, rdi
    jz 1f
    cmp [rip + esm_charge], rdi
    jb 1f
    sub [rip + esm_charge], rdi
    xor eax, eax
    ret
1:  mov rax, -22
    ret
# try(bytes)->owned zeroed bytes/NULL,RDX error. Charge actual allocator size.
FN ext_settings_memory_try
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 3f
    cmp rbx, ESM_CAP - 16
    ja 3f
    lea rdi, [rbx + 16]
    call prep_alloc_charge
    test rax, rax
    jz 3f
    mov r12, rax
    mov rdi, r12
    call ext_settings_memory_reserve
    test rax, rax
    js 3f
    lea rdi, [rbx + 16]
    call mem_alloc_try
    test rax, rax
    jz 2f
    mov [rax], r12
    mov rdx, ESM_MAGIC
    mov [rax + 8], rdx
    add rax, 16
    xor edx, edx
    EPILOGUE
2:  mov rdi, r12
    call ext_settings_memory_release
3:  xor eax, eax
    mov rdx, -12
    EPILOGUE
# Append a still-mapped failed LARGE release. Its native header owns exact charge.
# prefix0 becomes next only after transfer; prefix8 remains RETIRED until actual release.
esm_append_retired:
    mov qword ptr [rdi], 0
    mov rax, [rip + esm_retired_tail]
    test rax, rax
    jz 1f
    mov [rax], rdi
    jmp 2f
1:  mov [rip + esm_retired_head], rdi
2:  mov [rip + esm_retired_tail], rdi
    inc qword ptr [rip + esm_retired_count]
    add [rip + esm_retired_bytes], rsi
    test rdx, rdx
    jns 3f
    cmp qword ptr [rip + esm_cleanup], 0
    jne 3f
    mov [rip + esm_cleanup], rdx
3:  ret
# schedule(now,delay), checked absolute monotonic deadline.
esm_schedule:
    mov [rip + esm_retry_delay], rsi
    add rdi, rsi
    jnc 1f
    mov rdi, -1
1:  mov [rip + esm_retry_due], rdi
    ret

# free(currently owned accessible allocation orNULL): RAX0 ownership accepted/-EINVAL,
# RDX native cleanup, RCX consumed. Failed native release transfers into this disposer.
# Already unmapped/reused stale pointers are outside the owned-pointer precondition.
FN ext_settings_memory_free
    test rdi, rdi
    jz .Lesm_free_null
    PROLOGUE
    lea rbx, [rdi - 16]
    mov rax, ESM_MAGIC
    cmp [rbx + 8], rax
    jne .Lesm_free_invalid
    mov r12, [rbx]
    test r12, r12
    jz .Lesm_free_invalid
    cmp [rip + esm_charge], r12
    jb .Lesm_free_invalid
    mov rax, ESM_RETIRED
    mov [rbx + 8], rax
    mov rdi, rbx
    call prep_cleanup_free
    test rdx, rdx
    jz .Lesm_free_retained
    # Successful unmap may have removed the prefix. Use only captured accounting.
    sub [rip + esm_charge], r12
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    EPILOGUE
.Lesm_free_retained:
    mov r13, rax
    test r13, r13
    js 1f
    mov r13, -5
1:  mov r14, [rip + esm_retired_count]
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call esm_append_retired
    test r14, r14
    jnz 2f
    call time_ms
    mov rdi, rax
    mov esi, ESM_RETRY_MIN
    call esm_schedule
2:  xor eax, eax
    mov rdx, r13
    mov ecx, 1
    EPILOGUE
.Lesm_free_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesm_free_null:
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    ret

# gc(maxAttempts1..64): RAX completed native releases,RDX cleanup,RCX attempts.
# Visit at most the initial census, so a permanently failing entry is tried once per call.
FN ext_settings_memory_gc
    test rdi, rdi
    jz .Lesm_gc_invalid
    cmp rdi, 64
    ja .Lesm_gc_invalid
    PROLOGUE 32
    mov r12, [rip + esm_retired_count]
    cmp r12, rdi
    cmova r12, rdi
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    test r12, r12
    jz .Lesm_gc_return
    call time_ms
    mov [rsp], rax
    cmp rax, [rip + esm_retry_due]
    jb .Lesm_gc_return
.Lesm_gc_loop:
    test r12, r12
    jz .Lesm_gc_schedule
    dec r12
    mov rbx, [rip + esm_retired_head]
    # Only failed large checked frees can enter this list, with intact native headers.
    mov rax, [rbx - 16]
    cmp rax, 64
    jb .Lesm_gc_corrupt
    cmp rax, ESM_CAP
    ja .Lesm_gc_corrupt
    mov [rsp + 16], rax
    mov rax, [rbx]
    mov [rip + esm_retired_head], rax
    test rax, rax
    jnz 1f
    mov qword ptr [rip + esm_retired_tail], 0
1:  dec qword ptr [rip + esm_retired_count]
    mov rax, [rsp + 16]
    sub [rip + esm_retired_bytes], rax
    inc r14
    mov rdi, rbx
    call prep_cleanup_free
    test rdx, rdx
    jz .Lesm_gc_failed
    # No prefix access after success.
    mov rax, [rsp + 16]
    sub [rip + esm_charge], rax
    inc r13
    jmp .Lesm_gc_loop
.Lesm_gc_failed:
    test rax, rax
    js 2f
    mov rax, -5
2:  test r15, r15
    jnz 3f
    mov r15, rax
3:  mov rdi, rbx
    mov rsi, [rsp + 16]
    mov rdx, rax
    call esm_append_retired
    jmp .Lesm_gc_loop
.Lesm_gc_corrupt:
    mov r15, -22
    cmp qword ptr [rip + esm_cleanup], 0
    jne .Lesm_gc_schedule
    mov [rip + esm_cleanup], r15
.Lesm_gc_schedule:
    cmp qword ptr [rip + esm_retired_count], 0
    je 6f
    mov esi, ESM_RETRY_MIN
    test r15, r15
    jns 5f
    mov rsi, [rip + esm_retry_delay]
    add rsi, rsi
    cmp rsi, ESM_RETRY_MAX
    jbe 5f
    mov esi, ESM_RETRY_MAX
5:  mov rdi, [rsp]
    call esm_schedule
    jmp .Lesm_gc_return
6:  mov qword ptr [rip + esm_retry_delay], ESM_RETRY_MIN
    mov qword ptr [rip + esm_retry_due], 0
.Lesm_gc_return:
    mov rax, r13
    mov rdx, r15
    mov rcx, r14
    EPILOGUE
.Lesm_gc_invalid:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret

# One fixed clock observation. A permanent native error cannot force a busy loop.
FN ext_settings_memory_timeout
    cmp qword ptr [rip + esm_retired_count], 0
    je 3f
    PROLOGUE
    call time_ms
    mov rdx, [rip + esm_retry_due]
    sub rdx, rax
    jbe 1f
    mov eax, ESM_RETRY_MAX
    cmp rdx, rax
    cmovb rax, rdx
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
3:  mov rax, -1
    ret
FN ext_settings_memory_pending
    mov rax, [rip + esm_retired_count]
    ret
# status(out32): charged,retired count,retired bytes,first cleanup.
FN ext_settings_memory_status
    mov rax, [rip + esm_charge]
    mov [rdi], rax
    mov rax, [rip + esm_retired_count]
    mov [rdi + 8], rax
    mov rax, [rip + esm_retired_bytes]
    mov [rdi + 16], rax
    mov rax, [rip + esm_cleanup]
    mov [rdi + 24], rax
    xor eax, eax
    ret
FN ext_settings_memory_ack_cleanup
    cmp qword ptr [rip + esm_retired_count], 0
    jne 1f
    mov qword ptr [rip + esm_cleanup], 0
    xor eax, eax
    ret
1:  mov rax, -16
    ret
