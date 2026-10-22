# socketpair on Windows (src/win/chan.s), as remote windows use it: bytes written at one end are
# read at the other, poll says so, an empty end answers EAGAIN, shutdown and close end the other
# side's reading (POLLHUP once closed), F_DUPFD makes a second descriptor of the same end, and the
# record is freed with the last descriptor. Exit code: 0, or the failed step's number.
.include "win.inc"
.bss
.p2align 3
sv: .zero 8
buf: .zero 64
pfd: .zero 16
.text
FN main
    PROLOGUE
    mov r15, [rip + g_mem_live]
    mov ebx, 1
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    lea r10, [rip + sv]
    SYS SYS_socketpair
    test rax, rax
    jnz .Lfail
    # nothing yet: EAGAIN, not readable, writable
    inc ebx
    mov edi, [rip + sv]
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, -11
    jne .Lfail
    inc ebx
    mov edi, [rip + sv]
    mov esi, POLLIN | POLLOUT
    call poll_one
    cmp eax, POLLOUT
    jne .Lfail
    # one way, then the other
    inc ebx
    mov edi, [rip + sv]
    lea rsi, [rip + .Lhello]
    mov edx, 5
    SYS SYS_write
    cmp rax, 5
    jne .Lfail
    inc ebx
    mov edi, [rip + sv + 4]
    mov esi, POLLIN
    call poll_one
    cmp eax, POLLIN
    jne .Lfail
    inc ebx
    mov edi, [rip + sv + 4]
    lea rsi, [rip + buf]
    mov edx, 3
    SYS SYS_read
    cmp rax, 3
    jne .Lfail
    cmp word ptr [rip + buf], 0x6568     # "he"
    jne .Lfail
    inc ebx
    mov edi, [rip + sv + 4]
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 2
    jne .Lfail
    # a second descriptor of end 1 writes as end 1
    inc ebx
    mov edi, [rip + sv + 4]
    xor esi, esi                # F_DUPFD
    mov edx, 3
    SYS SYS_fcntl
    test rax, rax
    js .Lfail
    mov r12d, eax
    inc ebx
    mov edi, r12d
    lea rsi, [rip + .Lhello]
    mov edx, 5
    SYS SYS_write
    cmp rax, 5
    jne .Lfail
    inc ebx
    mov edi, [rip + sv]
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 5
    jne .Lfail
    # end 1 shuts its writing: end 0 reads the end (0), not EAGAIN
    inc ebx
    mov edi, r12d
    mov esi, SHUT_WR
    SYS SYS_shutdown
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, [rip + sv]
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, r12d
    lea rsi, [rip + .Lhello]
    mov edx, 5
    SYS SYS_write
    cmp rax, -32                # EPIPE: it shut its own writing
    jne .Lfail
    # end 1's descriptors close: end 0 sees POLLHUP and cannot write
    inc ebx
    mov edi, r12d
    SYS SYS_close
    mov edi, [rip + sv + 4]
    SYS SYS_close
    mov edi, [rip + sv]
    mov esi, POLLIN | POLLOUT
    call poll_one
    test eax, POLLHUP
    jz .Lfail
    inc ebx
    mov edi, [rip + sv]
    lea rsi, [rip + .Lhello]
    mov edx, 5
    SYS SYS_write
    cmp rax, -32
    jne .Lfail
    # the last descriptor frees the record
    inc ebx
    mov edi, [rip + sv]
    SYS SYS_close
    cmp r15, [rip + g_mem_live]
    jne .Lfail
    lea rdi, [rip + .Lok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov edi, ebx
    call sys_exit

# poll_one(fd, events) -> eax its revents (no waiting)
poll_one:
    push rbx
    mov [rip + pfd], edi
    mov [rip + pfd + 4], si
    mov word ptr [rip + pfd + 6], 0
    lea rdi, [rip + pfd]
    mov esi, 1
    xor edx, edx
    SYS SYS_poll
    movzx eax, word ptr [rip + pfd + 6]
    pop rbx
    ret

.section .rodata
.Lhello: .ascii "hello"
.Lok: .asciz "ok channels\n"
