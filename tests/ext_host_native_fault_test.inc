# Windows native boundary faults. Unknown close remains owned until process exit.
.include "win.inc"
.bss
.p2align 3
hn_mode: .quad 0
hn_calls: .quad 0
hn_creates: .quad 0
hn_closes: .quad 0
hn_pair: .quad 0
hn_record: .quad 0
hn_saved: .zero FD_SIZE
hn_fd: .quad 0
hn_expected: .quad 0
hn_stage: .quad 0
hn_large: .quad 0
hn_path: .quad 0
hn_live: .quad 0
.text
FN main
    PROLOGUE 96
    # Record the first available slot. No native resource is acquired.
    xor edi, edi
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    test rax, rax
    js .Lhnf_bad
    mov [rip + hn_expected], rax
    mov rdi, r8
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    mov qword ptr [rip + hn_mode], 1
.Lhnf_refusals:
    mov rax, [rip + hn_mode]
    mov [rip + hn_stage], rax
    mov qword ptr [rip + hn_calls], 0
    mov qword ptr [rip + hn_creates], 0
    mov qword ptr [rip + hn_closes], 0
    mov rax, 0x1234567812345678
    mov [rip + hn_pair], rax
    lea rdi, [rip + hn_pair]
    mov esi, O_CLOEXEC
    call ws_pipe
    test rax, rax
    jns .Lhnf_bad
    mov rax, 0x1234567812345678
    cmp [rip + hn_pair], rax
    jne .Lhnf_bad
    cmp qword ptr [rip + hn_closes], 0
    jne .Lhnf_bad
    xor eax, eax
    cmp qword ptr [rip + hn_mode], 3
    sete al
    cmp [rip + hn_creates], rax
    jne .Lhnf_bad
    # Both reservations must be available again, with the original first slot.
    xor edi, edi
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    cmp rax, [rip + hn_expected]
    jne .Lhnf_bad
    mov rdi, r8
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    # The second reserved slot must also be reusable.
    xor edi, edi
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    mov rbx, r8
    mov r13, rax
    xor edi, edi
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    lea rcx, [r13 + 1]
    cmp rax, rcx
    jne .Lhnf_bad
    mov rdi, r8
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    mov rdi, rbx
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    inc qword ptr [rip + hn_mode]
    cmp qword ptr [rip + hn_mode], 4
    jb .Lhnf_refusals
    mov qword ptr [rip + hn_mode], 0
    lea rdi, [rip + hn_pair]
    mov esi, O_CLOEXEC
    call ws_pipe
    test rax, rax
    jnz .Lhnf_bad
    mov edi, [rip + hn_pair]
    call win_fd
    mov [rip + hn_record], rax
    mov [rip + hn_fd], rdi
    mov qword ptr [rip + hn_stage], 4
    # Refuse a mapping-backed path before any native close.
    mov edi, 65521
    call mem_alloc
    mov [rip + hn_large], rax
    mov rbx, [rip + hn_record]
    mov [rbx + FD_path], rax
    mov rdi, [rip + hn_fd]
    call ext_fd_close_checked
    cmp rax, -7
    jne .Lhnf_bad
    test rdx, rdx
    jnz .Lhnf_bad
    cmp qword ptr [rip + hn_closes], 0
    jne .Lhnf_bad
    mov rbx, [rip + hn_record]
    mov rax, [rip + hn_large]
    cmp [rbx + FD_path], rax
    jne .Lhnf_bad
    mov qword ptr [rbx + FD_path], 0
    mov rdi, rax
    call mem_free
    mov rax, [rip + g_mem_live]
    mov [rip + hn_live], rax
    # Largest small path block can be freed after confirmed consumption.
    mov edi, 65520
    call mem_alloc
    mov rbx, [rip + hn_record]
    mov [rbx + FD_path], rax
    mov rdi, [rip + hn_fd]
    call ext_fd_close_checked
    test rax, rax
    jnz .Lhnf_bad
    cmp rdx, 1
    jne .Lhnf_bad
    cmp qword ptr [rip + hn_closes], 1
    jne .Lhnf_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + hn_live]
    jne .Lhnf_bad
    mov rbx, [rip + hn_record]
    cmp dword ptr [rbx + FD_kind], 0
    jne .Lhnf_bad
    # Unsupported type and absent fd are known refusals, without native close.
    mov edi, [rip + hn_pair + 4]
    call win_fd
    mov [rip + hn_record], rax
    mov [rip + hn_fd], rdi
    mov dword ptr [rax + FD_kind], FD_DIR
    call ext_fd_close_checked
    cmp rax, -22
    jne .Lhnf_bad
    test rdx, rdx
    jnz .Lhnf_bad
    cmp qword ptr [rip + hn_closes], 1
    jne .Lhnf_bad
    mov rbx, [rip + hn_record]
    mov dword ptr [rbx + FD_kind], FD_PIPE
    mov qword ptr [rip + hn_stage], 5
    # Preserve every byte on an uncertain native close, including the path owner.
    mov edi, 64
    call mem_alloc
    mov [rip + hn_path], rax
    mov rdi, rax
    mov esi, 0x55
    mov edx, 64
    call memset
    mov rax, [rip + g_mem_live]
    mov [rip + hn_live], rax
    mov rax, [rip + hn_path]
    mov rbx, [rip + hn_record]
    mov [rbx + FD_path], rax
    lea rdi, [rip + hn_saved]
    mov rsi, rbx
    mov edx, FD_SIZE
    call memcpy
    mov qword ptr [rip + hn_mode], 4
    mov rdi, [rip + hn_fd]
    call ext_fd_close_checked
    test rax, rax
    jns .Lhnf_bad
    cmp rdx, 2
    jne .Lhnf_bad
    cmp qword ptr [rip + hn_closes], 2
    jne .Lhnf_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + hn_live]
    jne .Lhnf_bad
    mov rax, [rip + hn_path]
    xor ecx, ecx
1:  cmp byte ptr [rax + rcx], 0x55
    jne .Lhnf_bad
    inc ecx
    cmp ecx, 64
    jb 1b
    lea rdi, [rip + hn_saved]
    mov rsi, [rip + hn_record]
    mov edx, FD_SIZE
    call memeq
    test rax, rax
    jz .Lhnf_bad
    xor edi, edi
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    cmp rax, [rip + hn_fd]
    je .Lhnf_bad
    test rax, rax
    js .Lhnf_bad
    mov rdi, r8
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    # Never retry the unknown handle. This isolated process retains the quarantine.
    xor eax, eax
    EPILOGUE
.Lhnf_bad:
    mov rax, [rip + hn_stage]
    test rax, rax
    jnz 1f
    mov eax, 99
1:  EPILOGUE

FN hn_alloc
    inc qword ptr [rip + hn_calls]
    mov rax, [rip + hn_calls]
    cmp rax, [rip + hn_mode]
    jne win_fd_alloc
    cmp rax, 2
    ja win_fd_alloc
    mov rax, -24
    ret
FN hn_create
    inc qword ptr [rip + hn_creates]
    cmp qword ptr [rip + hn_mode], 3
    jne 1f
    # The API may leave arbitrary output cells when it reports failure.
    mov qword ptr [rcx], 0x1234
    mov qword ptr [rdx], 0x5678
    sub rsp, 40
    mov ecx, 8
    API SetLastError
    xor eax, eax
    add rsp, 40
    ret
1:  jmp [rip + __imp_CreatePipe]
FN hn_close
    inc qword ptr [rip + hn_closes]
    cmp qword ptr [rip + hn_mode], 4
    jne 1f
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    xor eax, eax
    add rsp, 40
    ret
1:  jmp [rip + __imp_CloseHandle]
