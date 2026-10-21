# TCP sockets on Windows (src/win/sock.s), as the debugger's TCP adapters and forwarded ports use
# them, on 127.0.0.1: a listener on a port the system picks, a nonblocking connect (EINPROGRESS,
# POLLOUT, then 0 and EISCONN), accept4 with the peer's address, getsockname and getpeername,
# EAGAIN, read and write, F_DUPFD, poll over a channel and sockets in one call, a timed poll,
# O_NONBLOCK switched by fcntl, shutdown (the end is POLLIN without POLLHUP, EPIPE for the side that
# shut), POLLHUP once both directions are shut, a refused connect (POLLERR | POLLHUP, SO_ERROR
# ECONNREFUSED), AF_INET6 addresses in Linux's numbering when the system has ::1, and every record
# freed. Exit code: 0, or the failed step's number.
.include "win.inc"
.bss
.p2align 3
addr: .zero 32
addr2: .zero 32
alen: .long 0
lport: .long 0                  # the listener's port, network order
one: .long 0
opt: .long 0
optlen: .long 0
sv: .zero 8
buf: .zero 64
pfds: .zero 24
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov dword ptr [rip + one], 1
    # 1-2: not a socket, no descriptor at all
    mov ebx, 1
    mov edi, 1
    call name_of
    cmp rax, -88                # ENOTSOCK
    jne .Lfail
    inc ebx
    mov edi, 999
    call name_of
    cmp rax, -9                 # EBADF
    jne .Lfail
    # 3-7: a listener on 127.0.0.1, its port picked by the system
    inc ebx
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lfail
    mov r12d, eax
    inc ebx
    mov edi, r12d
    mov esi, SOL_SOCKET
    mov edx, 2                  # SO_REUSEADDR
    lea r10, [rip + one]
    mov r8d, 4
    SYS 54                      # setsockopt
    test rax, rax
    jnz .Lfail
    inc ebx
    mov dword ptr [rip + addr], AF_INET     # port 0
    mov dword ptr [rip + addr + 4], 0x0100007f
    mov edi, r12d
    lea rsi, [rip + addr]
    mov edx, 16
    SYS SYS_bind
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, r12d
    mov esi, 4
    SYS SYS_listen
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, r12d
    call name_of
    test rax, rax
    jnz .Lfail
    cmp dword ptr [rip + alen], 16
    jne .Lfail
    cmp word ptr [rip + addr], AF_INET
    jne .Lfail
    cmp word ptr [rip + addr + 2], 0
    je .Lfail
    cmp dword ptr [rip + addr + 4], 0x0100007f
    jne .Lfail
    movzx eax, word ptr [rip + addr + 2]
    mov [rip + lport], eax
    # 8-9: nobody waits yet
    inc ebx
    mov edi, r12d
    xor esi, esi
    xor edx, edx
    mov r10d, SOCK_NONBLOCK
    SYS SYS_accept4
    cmp rax, -11
    jne .Lfail
    inc ebx
    mov edi, r12d
    mov esi, POLLIN
    xor edx, edx
    call poll_wait
    test eax, eax
    jnz .Lfail
    # 10-15: a nonblocking connect
    inc ebx
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_NONBLOCK
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lfail
    mov r13d, eax
    inc ebx
    mov edi, r13d
    call peer_of
    cmp rax, -107               # ENOTCONN
    jne .Lfail
    inc ebx
    mov edi, r13d
    call connect_listener
    mov r15, rax                # 0 at once, or EINPROGRESS
    test rax, rax
    jz 1f
    cmp rax, -115
    jne .Lfail
1:  inc ebx
    mov edi, r13d
    mov esi, POLLOUT | POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLOUT
    jne .Lfail
    inc ebx
    mov edi, r13d
    call connect_listener
    test r15, r15
    jz 2f
    test rax, rax               # done: 0 once, as Linux says it
    jnz .Lfail
    jmp 3f
2:  cmp rax, -106
    jne .Lfail
3:  inc ebx
    mov edi, r13d
    call connect_listener
    cmp rax, -106               # EISCONN after
    jne .Lfail
    # 16-19: accepted, with the client's address
    inc ebx
    mov edi, r12d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    inc ebx
    mov dword ptr [rip + alen], 32
    mov edi, r12d
    lea rsi, [rip + addr2]
    lea rdx, [rip + alen]
    mov r10d, SOCK_NONBLOCK | SOCK_CLOEXEC
    SYS SYS_accept4
    test rax, rax
    js .Lfail
    mov r14d, eax
    cmp dword ptr [rip + alen], 16
    jne .Lfail
    cmp word ptr [rip + addr2], AF_INET
    jne .Lfail
    cmp dword ptr [rip + addr2 + 4], 0x0100007f
    jne .Lfail
    inc ebx
    mov edi, r13d               # the client's own port is the one accept4 reported
    call name_of
    test rax, rax
    jnz .Lfail
    mov ax, [rip + addr + 2]
    cmp ax, [rip + addr2 + 2]
    jne .Lfail
    inc ebx
    mov edi, r13d
    call peer_of
    test rax, rax
    jnz .Lfail
    movzx eax, word ptr [rip + addr + 2]
    cmp eax, [rip + lport]
    jne .Lfail
    # 20-24: bytes one way
    inc ebx
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, -11
    jne .Lfail
    inc ebx
    mov edi, r14d
    mov esi, POLLIN | POLLOUT
    xor edx, edx
    call poll_wait
    cmp eax, POLLOUT
    jne .Lfail
    inc ebx
    mov edi, r13d
    lea rsi, [rip + .Lhello]
    mov edx, 5
    SYS SYS_write
    cmp rax, 5
    jne .Lfail
    inc ebx
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    inc ebx
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 5
    jne .Lfail
    cmp dword ptr [rip + buf], 0x6c6c6568   # "hell"
    jne .Lfail
    # 25-27: a second descriptor of the client keeps the socket when the first closes
    inc ebx
    mov edi, r13d
    xor esi, esi                # F_DUPFD
    mov edx, 3
    SYS SYS_fcntl
    test rax, rax
    js .Lfail
    mov r15d, eax
    inc ebx
    mov edi, r13d
    SYS SYS_close
    test rax, rax
    jnz .Lfail
    mov edi, r15d
    lea rsi, [rip + .Lhello]
    mov edx, 3
    SYS SYS_write
    cmp rax, 3
    jne .Lfail
    inc ebx
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 3
    jne .Lfail
    # 28-29: a channel, the accepted socket and the listener in one poll
    inc ebx
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_NONBLOCK
    xor edx, edx
    lea r10, [rip + sv]
    SYS SYS_socketpair
    test rax, rax
    jnz .Lfail
    mov edi, [rip + sv]
    lea rsi, [rip + .Lhello]
    mov edx, 1
    SYS SYS_write
    mov edi, r15d
    lea rsi, [rip + .Lhello]
    mov edx, 1
    SYS SYS_write
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    inc ebx
    mov eax, [rip + sv + 4]
    mov [rip + pfds], eax
    mov [rip + pfds + 8], r14d
    mov [rip + pfds + 16], r12d
    mov dword ptr [rip + pfds + 4], POLLIN
    mov dword ptr [rip + pfds + 12], POLLIN
    mov dword ptr [rip + pfds + 20], POLLIN
    lea rdi, [rip + pfds]
    mov esi, 3
    xor edx, edx
    SYS SYS_poll
    cmp rax, 2
    jne .Lfail
    cmp word ptr [rip + pfds + 6], POLLIN
    jne .Lfail
    cmp word ptr [rip + pfds + 14], POLLIN
    jne .Lfail
    cmp word ptr [rip + pfds + 22], 0
    jne .Lfail
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 1
    jne .Lfail
    # 30: nothing comes: a poll of 100 ms waits about that long and says 0
    inc ebx
    call time_ms
    mov [rsp + 16], rax
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 100
    call poll_wait
    test eax, eax
    jnz .Lfail
    call time_ms
    sub rax, [rsp + 16]
    cmp rax, 80                 # GetTickCount64 steps by 16 ms
    jb .Lfail
    # 31-33: blocking, then nonblocking again
    inc ebx
    mov edi, r14d
    mov esi, F_SETFL
    mov edx, O_RDWR
    SYS SYS_fcntl
    test rax, rax
    jnz .Lfail
    mov edi, r14d
    mov esi, 3                  # F_GETFL
    SYS SYS_fcntl
    test eax, O_NONBLOCK
    jnz .Lfail
    inc ebx
    mov edi, r15d
    lea rsi, [rip + .Lhello]
    mov edx, 2
    SYS SYS_write
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    mov edi, r14d               # waiting bytes: a blocking read returns them
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 2
    jne .Lfail
    inc ebx
    mov edi, r14d
    mov esi, F_SETFL
    mov edx, O_RDWR | O_NONBLOCK
    SYS SYS_fcntl
    test rax, rax
    jnz .Lfail
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, -11
    jne .Lfail
    # 34-38: the client shuts its writing: the end is POLLIN, not POLLHUP, and reads 0
    inc ebx
    mov edi, r15d
    mov esi, SHUT_WR
    SYS SYS_shutdown
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, r14d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    mov edi, r14d               # a watch asking nothing is not woken by it
    xor esi, esi
    xor edx, edx
    call poll_wait
    test eax, eax
    jnz .Lfail
    inc ebx
    mov edi, r14d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    test rax, rax
    jnz .Lfail
    inc ebx
    mov edi, r15d
    lea rsi, [rip + .Lhello]
    mov edx, 1
    SYS SYS_write
    cmp rax, -32                # EPIPE: it shut its own writing
    jne .Lfail
    inc ebx
    mov edi, r14d               # the other way still flows
    lea rsi, [rip + .Lhello]
    mov edx, 4
    SYS SYS_write
    cmp rax, 4
    jne .Lfail
    mov edi, r15d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN
    jne .Lfail
    mov edi, r15d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    cmp rax, 4
    jne .Lfail
    # 39-40: both directions shut: POLLHUP
    inc ebx
    mov edi, r14d
    mov esi, SHUT_WR
    SYS SYS_shutdown
    test rax, rax
    jnz .Lfail
    mov edi, r15d
    mov esi, POLLIN
    mov edx, 5000
    call poll_wait
    cmp eax, POLLIN | POLLHUP
    jne .Lfail
    inc ebx
    mov edi, r15d
    lea rsi, [rip + buf]
    mov edx, 64
    SYS SYS_read
    test rax, rax
    jnz .Lfail
    mov edi, r15d
    SYS SYS_close
    mov edi, r14d
    SYS SYS_close
    mov edi, r12d
    SYS SYS_close
    # 41-43: nobody listens there now: refused
    inc ebx
    mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_NONBLOCK
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lfail
    mov r13d, eax
    mov edi, r13d
    call connect_listener
    cmp rax, -111               # ECONNREFUSED at once
    je 5f
    cmp rax, -115
    jne .Lfail
    inc ebx
    mov edi, r13d
    mov esi, POLLOUT
    mov edx, 5000               # Windows tries again for about 2 s
    call poll_wait
    cmp eax, POLLOUT | POLLERR | POLLHUP
    jne .Lfail
    inc ebx
    mov dword ptr [rip + opt], 0
    mov dword ptr [rip + optlen], 4
    mov edi, r13d
    mov esi, SOL_SOCKET
    mov edx, 4                  # SO_ERROR
    lea r10, [rip + opt]
    lea r8, [rip + optlen]
    SYS 55                      # getsockopt
    test rax, rax
    jnz .Lfail
    cmp dword ptr [rip + opt], 111
    jne .Lfail
    cmp dword ptr [rip + optlen], 4
    jne .Lfail
5:  mov edi, r13d
    SYS SYS_close
    # 44: AF_INET6 in Linux's numbering, when the system has ::1
    mov ebx, 44
    mov edi, AF_INET6
    mov esi, SOCK_STREAM
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js 7f
    mov r13d, eax
    lea rdi, [rip + addr]
    xor eax, eax
    mov ecx, 4
    rep stosq
    mov word ptr [rip + addr], AF_INET6
    mov byte ptr [rip + addr + 23], 1       # ::1
    mov edi, r13d
    lea rsi, [rip + addr]
    mov edx, 28
    SYS SYS_bind
    test rax, rax
    jnz 6f
    mov dword ptr [rip + alen], 32
    mov edi, r13d
    lea rsi, [rip + addr]
    lea rdx, [rip + alen]
    SYS DSK_getsockname
    test rax, rax
    jnz .Lfail
    cmp dword ptr [rip + alen], 28
    jne .Lfail
    cmp word ptr [rip + addr], AF_INET6
    jne .Lfail
    cmp byte ptr [rip + addr + 23], 1
    jne .Lfail
6:  mov edi, r13d
    SYS SYS_close
7:  # 45: every record freed
    mov ebx, 45
    mov edi, [rip + sv]
    SYS SYS_close
    mov edi, [rip + sv + 4]
    SYS SYS_close
    mov rax, [rsp]
    cmp rax, [rip + g_mem_live]
    jne .Lfail
    lea rdi, [rip + .Lok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov edi, ebx
    call sys_exit

# poll_wait(fd, events, ms) -> eax its revents
poll_wait:
    push rbx
    mov [rip + pfds], edi
    mov [rip + pfds + 4], si
    mov word ptr [rip + pfds + 6], 0
    lea rdi, [rip + pfds]
    mov esi, 1
    SYS SYS_poll
    movzx eax, word ptr [rip + pfds + 6]
    pop rbx
    ret

# name_of(fd) / peer_of(fd) -> rax getsockname's / getpeername's result into addr, alen
name_of:
    mov eax, DSK_getsockname
    jmp 1f
peer_of:
    mov eax, DSK_getpeername
1:  push rbx
    mov dword ptr [rip + alen], 16
    lea rsi, [rip + addr]
    lea rdx, [rip + alen]
    XSYS
    pop rbx
    ret

# connect_listener(fd) -> rax connect's result for 127.0.0.1 at the listener's port
connect_listener:
    push rbx
    mov dword ptr [rip + addr2], AF_INET
    mov eax, [rip + lport]
    mov [rip + addr2 + 2], ax
    mov dword ptr [rip + addr2 + 4], 0x0100007f
    mov qword ptr [rip + addr2 + 8], 0
    lea rsi, [rip + addr2]
    mov edx, 16
    SYS SYS_connect
    pop rbx
    ret

.section .rodata
.Lhello: .ascii "hello"
.Lok: .asciz "ok sockets\n"
