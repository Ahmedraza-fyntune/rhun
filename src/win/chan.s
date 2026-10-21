# socketpair(2) on Windows, for remote windows (remote.s): every remote program is a pair of
# descriptors whose bytes stay in this process. Each end reads what the other wrote; both live in
# the descriptor table as FD_CHAN (FD_handle the end, 0 or 1; FD_aux the shared CP record) and work
# with read, write, poll, close, shutdown and F_DUPFD like a Unix socket's. Nothing else can hold
# them: they are never handed to a child process.
.include "win.inc"

.equ CP_HIGH, 4194304           # bytes an end may have waiting for its reader before writes wait

STRUCT
F CP_buf, 2 * SB_SIZE           # [end]: what that end has to read
F CP_off, 16                    # [end]: how much of it was read
F CP_refs, 8                    # [end]: descriptors of that end
F CP_shut, 8                    # [end]: 1 once that end writes no more (shutdown or closed)
ENDSTRUCT CP_SIZE

.text

# ws_socketpair(domain, type | flags, proto, sv) -> 0 or -errno
FN ws_socketpair
    PROLOGUE 16
    mov r12d, esi
    mov r13, rcx
    mov edi, CP_SIZE
    call mem_alloc
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, CP_SIZE
    call memset
    xor r14d, r14d              # O_NONBLOCK or 0
    test r12d, SOCK_NONBLOCK
    jz 1f
    mov r14d, O_NONBLOCK
1:  xor edi, edi
    mov esi, FD_CHAN
    mov edx, r14d
    call win_fd_alloc
    test rax, rax
    js 7f
    mov r15d, eax
    mov qword ptr [r8 + FD_handle], 0
    mov qword ptr [r8 + FD_write], 0
    mov [r8 + FD_aux], rbx
    mov edi, 1
    mov esi, FD_CHAN
    mov edx, r14d
    call win_fd_alloc
    test rax, rax
    js 6f
    mov qword ptr [r8 + FD_handle], 1
    mov qword ptr [r8 + FD_write], 1
    mov [r8 + FD_aux], rbx
    mov dword ptr [rbx + CP_refs], 1
    mov dword ptr [rbx + CP_refs + 4], 1
    mov [r13], r15d
    mov [r13 + 4], eax
    xor eax, eax
    EPILOGUE
6:  mov [rsp], rax
    mov edi, r15d
    call win_fd
    mov dword ptr [rax + FD_kind], 0
    mov rdi, rbx
    call mem_free
    mov rax, [rsp]
    EPILOGUE
7:  mov [rsp], rax
    mov rdi, rbx
    call mem_free
    mov rax, [rsp]
    EPILOGUE
8:  mov rax, -12
    EPILOGUE

# win_chan_read(FD*, buf, len) -> bytes, 0 at the end (the other end writes no more), -EAGAIN
FN win_chan_read
    PROLOGUE
    mov rbx, [rdi + FD_aux]
    mov r12, [rdi + FD_handle]  # this end
    mov r13, rsi
    mov r14, rdx
    mov rax, r12
    imul rax, rax, SB_SIZE
    lea r15, [rbx + CP_buf + rax]
    mov rcx, [r15 + SB_len]
    sub rcx, [rbx + CP_off + r12*8]
    jz 5f
    cmp r14, rcx
    cmova r14, rcx
    mov rdi, r13
    mov rsi, [r15 + SB_ptr]
    add rsi, [rbx + CP_off + r12*8]
    mov rdx, r14
    call memcpy
    add [rbx + CP_off + r12*8], r14
    mov rax, [rbx + CP_off + r12*8]
    cmp rax, [r15 + SB_len]
    jne 1f
    mov qword ptr [rbx + CP_off + r12*8], 0
    mov qword ptr [r15 + SB_len], 0
    jmp 2f
1:  cmp rax, 1048576            # read far into it: what is left moves to the front
    jb 2f
    mov rdi, [r15 + SB_ptr]
    mov rsi, rdi
    add rsi, rax
    mov rdx, [r15 + SB_len]
    sub rdx, rax
    mov [r15 + SB_len], rdx
    mov qword ptr [rbx + CP_off + r12*8], 0
    call memmove
2:  mov rax, r14
    EPILOGUE
5:  mov rax, r12
    xor rax, 1
    xor ecx, ecx
    cmp dword ptr [rbx + CP_shut + rax*4], 0
    jne 6f
    mov rcx, -11                # EAGAIN: nothing yet (a blocking read cannot wait here either)
6:  mov rax, rcx
    EPILOGUE

# win_chan_write(FD*, buf, len) -> bytes taken, -EAGAIN when the other end has too much waiting,
#   -EPIPE when it is gone or this end shut its writing
FN win_chan_write
    PROLOGUE
    mov rbx, [rdi + FD_aux]
    mov r12, [rdi + FD_handle]
    mov r13, rsi
    mov r14, rdx
    mov rax, -32
    cmp dword ptr [rbx + CP_shut + r12*4], 0
    jne 9f
    mov rcx, r12
    xor rcx, 1                  # the other end
    cmp dword ptr [rbx + CP_refs + rcx*4], 0
    je 9f
    mov rax, rcx
    imul rax, rax, SB_SIZE
    lea r15, [rbx + CP_buf + rax]
    mov rax, [r15 + SB_len]
    sub rax, [rbx + CP_off + rcx*8]
    mov rdx, CP_HIGH
    sub rdx, rax
    jg 1f
    mov rax, -11
    test r14, r14
    jnz 9f
    xor eax, eax
    jmp 9f
1:  cmp r14, rdx
    cmova r14, rdx
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call sb_push
    mov rax, r14
9:  EPILOGUE

# win_chan_events(FD*, events) -> revents: POLLIN with bytes or at the end, POLLHUP once the other
#   end is closed, POLLOUT while the other end takes more
FN win_chan_events
    mov r8, [rdi + FD_aux]
    mov r9, [rdi + FD_handle]
    mov r10, r9
    xor r10, 1
    xor eax, eax
    # readable
    mov rcx, r9
    imul rcx, rcx, SB_SIZE
    mov rdx, [r8 + CP_buf + rcx + SB_len]
    sub rdx, [r8 + CP_off + r9*8]
    jnz 1f
    cmp dword ptr [r8 + CP_shut + r10*4], 0
    je 2f
1:  test esi, POLLIN
    jz 2f
    or eax, POLLIN
2:  cmp dword ptr [r8 + CP_refs + r10*4], 0
    jne 3f
    or eax, POLLHUP
    ret
3:  test esi, POLLOUT
    jz 9f
    cmp dword ptr [r8 + CP_shut + r9*4], 0
    jne 9f
    mov rcx, r10
    imul rcx, rcx, SB_SIZE
    mov rdx, [r8 + CP_buf + rcx + SB_len]
    sub rdx, [r8 + CP_off + r10*8]
    cmp rdx, CP_HIGH
    jae 9f
    or eax, POLLOUT
9:  ret

# win_chan_close(FD*): one descriptor of its end less; the last one ends the end's writing, and the
#   record goes with the last descriptor of both
FN win_chan_close
    push rbx
    mov rbx, [rdi + FD_aux]
    mov rcx, [rdi + FD_handle]
    mov dword ptr [rdi + FD_kind], 0
    dec dword ptr [rbx + CP_refs + rcx*4]
    jnz 9f
    mov dword ptr [rbx + CP_shut + rcx*4], 1
    cmp dword ptr [rbx + CP_refs], 0
    jne 9f
    cmp dword ptr [rbx + CP_refs + 4], 0
    jne 9f
    lea rdi, [rbx + CP_buf]
    call sb_free
    lea rdi, [rbx + CP_buf + SB_SIZE]
    call sb_free
    mov rdi, rbx
    call mem_free
9:  pop rbx
    xor eax, eax
    ret

# win_chan_dup(FD*) -> a new descriptor of the same end, or -errno
FN win_chan_dup
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx + FD_handle]
    mov esi, FD_CHAN
    mov edx, [rbx + FD_flags]
    call win_fd_alloc
    test rax, rax
    js 9f
    mov r12, [rbx + FD_aux]
    mov [r8 + FD_aux], r12
    mov rcx, [rbx + FD_handle]
    inc dword ptr [r12 + CP_refs + rcx*4]
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# ws_shutdown(fd, how) -> 0 or -errno: SHUT_WR (1) or SHUT_RDWR (2) ends a channel's writing
FN ws_shutdown
    push rbx
    call win_fd
    test rax, rax
    jz 8f
    cmp dword ptr [rax + FD_kind], FD_CHAN
    jne 7f
    xor ecx, ecx
    cmp esi, 1
    jb 6f                       # SHUT_RD: nothing to do here
    mov rdx, [rax + FD_aux]
    mov rcx, [rax + FD_handle]
    mov dword ptr [rdx + CP_shut + rcx*4], 1
    xor ecx, ecx
6:  mov rax, rcx
    pop rbx
    ret
7:  mov rax, -88                # ENOTSOCK
    pop rbx
    ret
8:  mov rax, -9
    pop rbx
    ret
