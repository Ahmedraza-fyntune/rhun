# TCP sockets on Windows, through Winsock: socket, connect, bind, listen, accept4, getsockname,
# getpeername, setsockopt, getsockopt and shutdown as Linux has them, for the debugger's TCP
# adapters (dapwire.s) and forwarded ports (remotefwd.s). A socket is a descriptor of kind WSK_KIND:
# FD_handle the SOCKET, FD_aux its WSK record, which the descriptors F_DUPFD makes share (the last
# one closes the socket). sys.s routes read, write, close and fcntl here, and window.s's poll
# samples sockets as it samples pipes (WSAPoll, select, never waiting). Addresses are in Linux's
# numbering (AF_INET 2, AF_INET6 10; Windows calls AF_INET6 23, the layouts are the same) and
# errors are Linux errno values. A nonblocking connect answers EINPROGRESS, then EALREADY until it
# is done, then 0 (or why it failed) and EISCONN after, whatever Windows says to a repeated connect.
.include "win.inc"

STRUCT
F WSK_sock, 8                   # the SOCKET
F WSK_refs, 4                   # descriptors of it
F WSK_state, 4                  # WSK_CONNECTING, WSK_SHUT_RD, WSK_SHUT_WR, WSK_REUSE
F WSK_err, 4                    # why a connect failed (errno), until connect or SO_ERROR says it
F WSK_pad, 4
ENDSTRUCT WSK_SIZE
.equ WSK_CONNECTING, 1          # a nonblocking connect not reported done by connect yet
.equ WSK_SHUT_RD, 2
.equ WSK_SHUT_WR, 4
.equ WSK_REUSE, 8               # SO_REUSEADDR was set (see ws_setsockopt)

# Windows' numbers
.equ WSK_AF_INET6, 23
.equ WSK_SOL_SOCKET, 0xffff
.equ WSK_SO_ERROR, 0x1007
.equ WSK_FIONBIO, 0x8004667e
.equ WSK_MSG_PEEK, 2
.equ WSK_POLLERR, 0x1
.equ WSK_POLLHUP, 0x2
.equ WSK_POLLWRNORM, 0x10
.equ WSK_POLLRDNORM, 0x100
.equ WSK_EWOULDBLOCK, 10035
.equ WSK_ADDR_MAX, 128          # room for any address (sockaddr_storage)

.bss
.p2align 3
wsk_started: .long 0            # 1 once WSAStartup worked
.p2align 3
wsk_data: .zero 512             # WSADATA

.text

# wsk_errno(Winsock error code) -> rax the negative Linux errno
wsk_errno:
    lea eax, [rdi - 10035]
    cmp eax, 30
    ja 1f
    lea rcx, [rip + wsk_errnos]
    movzx eax, byte ptr [rcx + rax]
    neg rax
    ret
1:  mov rax, -4
    cmp edi, 10004              # WSAEINTR
    je 9f
    mov rax, -9
    cmp edi, 10009              # WSAEBADF
    je 9f
    mov rax, -13
    cmp edi, 10013              # WSAEACCES (also a port Windows reserves)
    je 9f
    mov rax, -14
    cmp edi, 10014              # WSAEFAULT
    je 9f
    mov rax, -22
    cmp edi, 10022              # WSAEINVAL
    je 9f
    mov rax, -24
    cmp edi, 10024              # WSAEMFILE
    je 9f
    mov rax, -12
    cmp edi, 8                  # WSA_NOT_ENOUGH_MEMORY
    je 9f
    mov rax, -5                 # EIO for the rest (WSANOTINITIALISED, WSASYSCALLFAILURE, ...)
9:  ret

# wsk_error() -> rax the negative Linux errno for WSAGetLastError (clobbers rdi)
wsk_error:
    sub rsp, 40
    API WSAGetLastError
    add rsp, 40
    mov edi, eax
    jmp wsk_errno

# wsk_start() -> rax 0, or -errno when Winsock does not start; the first socket starts it
wsk_start:
    xor eax, eax
    cmp dword ptr [rip + wsk_started], 0
    jne 9f
    sub rsp, 40
    mov ecx, 0x0202             # Winsock 2.2
    lea rdx, [rip + wsk_data]
    API WSAStartup
    add rsp, 40
    test eax, eax
    jnz 1f
    mov dword ptr [rip + wsk_started], 1
9:  ret
1:  mov edi, eax                # WSAStartup returns its error
    jmp wsk_errno

# wsk_lookup(fd) -> rax the socket's descriptor, or -EBADF, or -ENOTSOCK for another kind
wsk_lookup:
    call win_fd
    test rax, rax
    jz 1f
    cmp dword ptr [rax + FD_kind], WSK_KIND
    jne 2f
    ret
1:  mov rax, -9
    ret
2:  mov rax, -88
    ret

# wsk_addr_in(Linux address, its length, buffer of WSK_ADDR_MAX) -> rax its length for Windows, or
#   -errno: AF_INET (16 bytes) and AF_INET6 (28) in Windows' numbering
wsk_addr_in:
    test rdi, rdi
    jz 8f
    movzx eax, word ptr [rdi]
    cmp eax, AF_INET
    je 1f
    cmp eax, AF_INET6
    jne 7f
    cmp esi, 28
    jb 8f
    mov rax, [rdi + 16]
    mov [rdx + 16], rax
    mov eax, [rdi + 24]
    mov [rdx + 24], eax
    mov rax, [rdi]
    mov [rdx], rax
    mov rax, [rdi + 8]
    mov [rdx + 8], rax
    mov word ptr [rdx], WSK_AF_INET6
    mov eax, 28
    ret
1:  cmp esi, 16
    jb 8f
    mov rax, [rdi]
    mov [rdx], rax
    mov rax, [rdi + 8]
    mov [rdx + 8], rax
    mov eax, 16
    ret
7:  mov rax, -97                # EAFNOSUPPORT
    ret
8:  mov rax, -22
    ret

# wsk_addr_out(Windows address, its length, Linux buffer | 0, length pointer | 0): the address in
#   Linux's numbering, at most *length bytes of it, and *length its whole length (as Linux reports
#   an address cut short)
wsk_addr_out:
    test rdx, rdx
    jz 9f
    test rcx, rcx
    jz 9f
    cmp word ptr [rdi], WSK_AF_INET6
    jne 1f
    mov word ptr [rdi], AF_INET6
1:  mov eax, [rcx]              # the room
    mov [rcx], esi
    cmp eax, esi
    cmova eax, esi
    xor ecx, ecx
2:  cmp ecx, eax
    jae 9f
    mov r8b, [rdi + rcx]
    mov [rdx + rcx], r8b
    inc ecx
    jmp 2b
9:  ret

# wsk_nonblock(SOCKET, on) -> rax 0 or -errno: its blocking mode (FIONBIO)
wsk_nonblock:
    sub rsp, 56
    mov [rsp + 40], esi
    mov rcx, rdi
    mov edx, WSK_FIONBIO
    lea r8, [rsp + 40]
    API ioctlsocket
    add rsp, 56
    test eax, eax
    jnz wsk_error
    ret

# wsk_new(SOCKET, nonblocking) -> rax a descriptor of it, or -errno (the socket is closed then)
wsk_new:
    PROLOGUE 96
    mov rbx, rdi
    mov r12d, esi
    mov edi, WSK_SIZE
    call mem_alloc
    test rax, rax
    jz 8f
    mov r13, rax
    mov [r13 + WSK_sock], rbx
    mov dword ptr [r13 + WSK_refs], 1
    mov dword ptr [r13 + WSK_state], 0
    mov qword ptr [r13 + WSK_err], 0
    mov edx, O_RDWR
    test r12d, r12d
    jz 1f
    or edx, O_NONBLOCK
1:  mov rdi, rbx
    mov esi, WSK_KIND
    call win_fd_alloc
    test rax, rax
    js 7f
    mov [r8 + FD_aux], r13
    EPILOGUE
7:  mov r14, rax
    mov rdi, r13
    call mem_free
    jmp 9f
8:  mov r14, -12
9:  mov rcx, rbx
    API closesocket
    mov rax, r14
    EPILOGUE

# wsk_connect_check(WSK) -> rax 1 connected, 0 still connecting, or -errno when it failed (kept in
#   WSK_err; no longer connecting). select without waiting tells a failed connect on every Windows
#   (WSAPoll does not before Windows 10 2004).
wsk_connect_check:
    PROLOGUE 160
    mov rbx, rdi
    mov rax, [rbx + WSK_sock]
    mov qword ptr [rsp + 96], 1         # fd_set: writable (count, then the socket)
    mov [rsp + 104], rax
    mov qword ptr [rsp + 112], 1        # fd_set: failed
    mov [rsp + 120], rax
    mov qword ptr [rsp + 128], 0        # timeval: no wait
    xor ecx, ecx
    xor edx, edx
    lea r8, [rsp + 96]
    lea r9, [rsp + 112]
    lea rax, [rsp + 128]
    mov [rsp + 32], rax
    API select
    cmp eax, -1
    jne 1f
    call wsk_error
    jmp 9f
1:  cmp dword ptr [rsp + 112], 0
    jne 3f
    xor eax, eax
    cmp dword ptr [rsp + 96], 0
    je 9f
    mov eax, 1
    jmp 9f
3:  # failed: why
    mov dword ptr [rsp + 136], 0
    mov dword ptr [rsp + 140], 4
    mov rcx, [rbx + WSK_sock]
    mov edx, WSK_SOL_SOCKET
    mov r8d, WSK_SO_ERROR
    lea r9, [rsp + 136]
    lea rax, [rsp + 140]
    mov [rsp + 32], rax
    API getsockopt
    mov rax, -111               # ECONNREFUSED when Windows does not say
    mov edi, [rsp + 136]
    test edi, edi
    jz 4f
    call wsk_errno
4:  and dword ptr [rbx + WSK_state], ~WSK_CONNECTING
    mov ecx, eax
    neg ecx
    mov [rbx + WSK_err], ecx
9:  EPILOGUE

# ---------------- the system calls ----------------

# socket(domain, type | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol) -> fd or -errno: AF_INET or
#   AF_INET6. CLOEXEC holds anyway: children get only the handles proc_spawn lists for them.
FN ws_socket
    PROLOGUE 96
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    call wsk_start
    test rax, rax
    js 9f
    mov ecx, AF_INET
    cmp r12d, AF_INET
    je 1f
    mov ecx, WSK_AF_INET6
    cmp r12d, AF_INET6
    je 1f
    mov rax, -97                # EAFNOSUPPORT
    jmp 9f
1:  mov edx, r13d
    and edx, 0xf                # SOCK_STREAM and SOCK_DGRAM have the same numbers there
    mov r8d, r14d
    API socket
    cmp rax, -1
    jne 2f
    call wsk_error
    jmp 9f
2:  mov rbx, rax
    xor r15d, r15d
    test r13d, SOCK_NONBLOCK
    jz 3f
    mov r15d, 1
    mov rdi, rbx
    mov esi, 1
    call wsk_nonblock
    test rax, rax
    jns 3f
    mov r15, rax
    mov rcx, rbx
    API closesocket
    mov rax, r15
    jmp 9f
3:  mov rdi, rbx
    mov esi, r15d
    call wsk_new
9:  EPILOGUE

# connect(fd, address, length) -> 0 or -errno. Nonblocking: EINPROGRESS, then EALREADY until it is
#   done, then 0 or why it failed, EISCONN after. 0.0.0.0 is this machine, as Linux reads it.
FN ws_connect
    PROLOGUE 224
    mov r12, rsi
    mov r13d, edx
    call wsk_lookup
    test rax, rax
    js 9f
    mov rbx, [rax + FD_aux]
    test dword ptr [rbx + WSK_state], WSK_CONNECTING
    jz 2f
    mov rdi, rbx
    call wsk_connect_check
    test rax, rax
    jz 1f
    js 11f
    and dword ptr [rbx + WSK_state], ~WSK_CONNECTING
    jmp 8f
1:  mov rax, -114               # EALREADY
    jmp 9f
11: mov dword ptr [rbx + WSK_err], 0    # said now
    jmp 9f
2:  mov eax, [rbx + WSK_err]    # a failure poll saw, not said yet
    test eax, eax
    jz 3f
    mov dword ptr [rbx + WSK_err], 0
    neg rax
    jmp 9f
3:  mov rdi, r12
    mov esi, r13d
    lea rdx, [rsp + 96]
    call wsk_addr_in
    test rax, rax
    js 9f
    mov r14, rax
    cmp word ptr [rsp + 96], AF_INET
    jne 4f
    cmp dword ptr [rsp + 100], 0
    jne 4f
    mov dword ptr [rsp + 100], 0x0100007f
4:  mov rcx, [rbx + WSK_sock]
    lea rdx, [rsp + 96]
    mov r8d, r14d
    API connect
    test eax, eax
    jz 8f
    call wsk_error
    cmp rax, -11                # WSAEWOULDBLOCK: on its way
    jne 9f
    or dword ptr [rbx + WSK_state], WSK_CONNECTING
    mov rax, -115               # EINPROGRESS
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# bind(fd, address, length) -> 0 or -errno
FN ws_bind
    PROLOGUE 224
    mov r12, rsi
    mov r13d, edx
    call wsk_lookup
    test rax, rax
    js 9f
    mov rbx, rax
    mov rdi, r12
    mov esi, r13d
    lea rdx, [rsp + 96]
    call wsk_addr_in
    test rax, rax
    js 9f
    mov rcx, [rbx + FD_handle]
    lea rdx, [rsp + 96]
    mov r8d, eax
    API bind
    test eax, eax
    jz 8f
    call wsk_error
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# listen(fd, backlog) -> 0 or -errno
FN ws_listen
    PROLOGUE 96
    mov r12d, esi
    call wsk_lookup
    test rax, rax
    js 9f
    mov rcx, [rax + FD_handle]
    mov edx, r12d
    API listen
    test eax, eax
    jz 8f
    call wsk_error
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# accept(fd, address | 0, length pointer | 0) -> fd or -errno
FN ws_accept
    xor ecx, ecx
    jmp ws_accept4

# accept4(fd, address | 0, length pointer | 0, SOCK_NONBLOCK | SOCK_CLOEXEC) -> fd or -errno; the
#   new socket is nonblocking only when the flags say so (Windows would hand the listener's mode on)
FN ws_accept4
    PROLOGUE 240
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    call wsk_lookup
    test rax, rax
    js 9f
    mov dword ptr [rsp + 224], WSK_ADDR_MAX
    mov rcx, [rax + FD_handle]
    lea rdx, [rsp + 96]
    lea r8, [rsp + 224]
    API accept
    cmp rax, -1
    jne 1f
    call wsk_error
    jmp 9f
1:  mov rbx, rax
    xor r15d, r15d
    test r14d, SOCK_NONBLOCK
    setnz r15b
    mov rdi, rbx
    mov esi, r15d
    call wsk_nonblock
    test rax, rax
    jns 2f
    mov r15, rax
    mov rcx, rbx
    API closesocket
    mov rax, r15
    jmp 9f
2:  mov rdi, rbx
    mov esi, r15d
    call wsk_new
    test rax, rax
    js 9f
    mov r15, rax
    lea rdi, [rsp + 96]
    mov esi, [rsp + 224]
    mov rdx, r12
    mov rcx, r13
    call wsk_addr_out
    mov rax, r15
9:  EPILOGUE

# getsockname(fd, address, length pointer) and getpeername -> 0 or -errno
.macro WSK_NAME name, api
FN \name
    PROLOGUE 240
    mov r12, rsi
    mov r13, rdx
    call wsk_lookup
    test rax, rax
    js 9f
    mov dword ptr [rsp + 224], WSK_ADDR_MAX
    mov rcx, [rax + FD_handle]
    lea rdx, [rsp + 96]
    lea r8, [rsp + 224]
    API \api
    test eax, eax
    jz 1f
    call wsk_error
    jmp 9f
1:  lea rdi, [rsp + 96]
    mov esi, [rsp + 224]
    mov rdx, r12
    mov rcx, r13
    call wsk_addr_out
    xor eax, eax
9:  EPILOGUE
.endm
WSK_NAME ws_getsockname, getsockname
WSK_NAME ws_getpeername, getpeername

# wsk_opt(level, name) -> eax Windows' level and edx its name for an option both have, or eax -1:
#   SO_KEEPALIVE, SO_SNDBUF, SO_RCVBUF, SO_TYPE, TCP_NODELAY
wsk_opt:
    cmp edi, SOL_SOCKET
    jne 5f
    mov eax, WSK_SOL_SOCKET
    mov edx, 8                  # SO_KEEPALIVE
    cmp esi, 9
    je 9f
    mov edx, 0x1001             # SO_SNDBUF
    cmp esi, 7
    je 9f
    mov edx, 0x1002             # SO_RCVBUF
    cmp esi, 8
    je 9f
    mov edx, 0x1008             # SO_TYPE (SOCK_STREAM and SOCK_DGRAM are the same numbers)
    cmp esi, 3
    je 9f
    jmp 8f
5:  cmp edi, 6                  # IPPROTO_TCP: TCP_NODELAY is 1 on both
    jne 8f
    mov eax, 6
    mov edx, 1
    cmp esi, 1
    je 9f
8:  mov eax, -1
9:  ret

# setsockopt(fd, level, name, value, length) -> 0 or -errno: SO_REUSEADDR is only kept (Windows
#   binds a port whose old connections wait in TIME_WAIT without it, and its own SO_REUSEADDR
#   would let a second listener take the port, which Linux refuses); the options wsk_opt maps
FN ws_setsockopt
    PROLOGUE 96
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15d, r8d
    call wsk_lookup
    test rax, rax
    js 9f
    mov rbx, rax
    cmp r12d, SOL_SOCKET
    jne 2f
    cmp r13d, 2                 # SO_REUSEADDR
    jne 2f
    mov rax, -22
    cmp r15d, 4
    jb 9f
    mov rcx, [rbx + FD_aux]
    and dword ptr [rcx + WSK_state], ~WSK_REUSE
    cmp dword ptr [r14], 0
    je 8f
    or dword ptr [rcx + WSK_state], WSK_REUSE
    jmp 8f
2:  mov edi, r12d
    mov esi, r13d
    call wsk_opt
    cmp eax, -1
    jne 3f
    mov rax, -92                # ENOPROTOOPT
    jmp 9f
3:  mov rcx, [rbx + FD_handle]
    mov r8d, edx
    mov edx, eax
    mov r9, r14
    mov [rsp + 32], r15
    API setsockopt
    test eax, eax
    jz 8f
    call wsk_error
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# getsockopt(fd, level, name, value, length pointer) -> 0 or -errno: SO_ERROR (why a connect
#   failed, said once), SO_REUSEADDR, and the options wsk_opt maps
FN ws_getsockopt
    PROLOGUE 96
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    call wsk_lookup
    test rax, rax
    js 9f
    mov rbx, rax
    cmp r12d, SOL_SOCKET
    jne 3f
    cmp r13d, 4                 # SO_ERROR
    jne 2f
    mov rdi, [rbx + FD_aux]
    test dword ptr [rdi + WSK_state], WSK_CONNECTING
    jz 1f
    call wsk_connect_check      # a connect that failed since keeps its errno
1:  mov rcx, [rbx + FD_aux]
    mov eax, [rcx + WSK_err]
    mov dword ptr [rcx + WSK_err], 0
    jmp 7f
2:  cmp r13d, 2                 # SO_REUSEADDR
    jne 3f
    mov rcx, [rbx + FD_aux]
    mov eax, [rcx + WSK_state]
    and eax, WSK_REUSE
    shr eax, 3
7:  mov ecx, eax
    mov rax, -22
    cmp dword ptr [r15], 4
    jb 9f
    mov [r14], ecx
    mov dword ptr [r15], 4
    jmp 8f
3:  mov edi, r12d
    mov esi, r13d
    call wsk_opt
    cmp eax, -1
    jne 4f
    mov rax, -92                # ENOPROTOOPT
    jmp 9f
4:  mov rcx, [rbx + FD_handle]
    mov r8d, edx
    mov edx, eax
    mov r9, r14
    mov [rsp + 32], r15
    API getsockopt
    test eax, eax
    jz 8f
    call wsk_error
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# shutdown(fd, how) -> 0 or -errno: a socket's (SHUT_RD 0, SHUT_WR 1, SHUT_RDWR 2, Windows' numbers
#   too), else a channel's (chan.s)
FN ws_sock_shutdown
    call win_fd
    test rax, rax
    jz ws_shutdown
    cmp dword ptr [rax + FD_kind], WSK_KIND
    jne ws_shutdown
    PROLOGUE 96
    mov rbx, [rax + FD_aux]
    mov r12d, esi
    mov rcx, [rax + FD_handle]
    mov edx, esi
    API shutdown
    test eax, eax
    jz 1f
    call wsk_error
    jmp 9f
1:  mov eax, WSK_SHUT_RD
    cmp r12d, 1
    jne 2f
    mov eax, WSK_SHUT_WR
2:  cmp r12d, 2
    jne 3f
    mov eax, WSK_SHUT_RD | WSK_SHUT_WR
3:  or [rbx + WSK_state], eax
    xor eax, eax
9:  EPILOGUE

# ---------------- descriptors (sys.s, window.s) ----------------

# win_sock_read(FD*, buf, len) -> bytes, 0 at the end, -EAGAIN, or -errno
FN win_sock_read
    PROLOGUE 96
    mov rbx, rdi
    mov r12, [rbx + FD_aux]
    xor eax, eax
    test dword ptr [r12 + WSK_state], WSK_SHUT_RD
    jnz 9f                      # its reading shut: the end, as Linux reads it
    mov r8, rdx
    mov eax, 0x7fffffff
    cmp r8, rax
    cmova r8, rax
    mov rdx, rsi
    mov rcx, [rbx + FD_handle]
    xor r9d, r9d
    API recv
    cmp eax, -1
    je 1f
    mov eax, eax
    jmp 9f
1:  call wsk_error
    jmp wsk_io_error

# win_sock_write(FD*, buf, len) -> bytes taken, -EAGAIN, -EPIPE once its writing is shut, or -errno
FN win_sock_write
    PROLOGUE 96
    mov rbx, rdi
    mov r12, [rbx + FD_aux]
    mov rax, -32
    test dword ptr [r12 + WSK_state], WSK_SHUT_WR
    jnz 9f
    mov r8, rdx
    mov eax, 0x7fffffff
    cmp r8, rax
    cmova r8, rax
    mov rdx, rsi
    mov rcx, [rbx + FD_handle]
    xor r9d, r9d
    API send
    cmp eax, -1
    je 1f
    mov eax, eax
    jmp 9f
1:  call wsk_error
    cmp rax, -108               # WSAESHUTDOWN: EPIPE, as Linux says it
    jne wsk_io_error
    mov rax, -32
    jmp 9f
# the end of win_sock_read and win_sock_write (r12 the WSK): a read after shutdown is the end; a
#   socket still connecting says EAGAIN, as Linux's would
wsk_io_error:
    cmp rax, -108               # WSAESHUTDOWN
    jne 1f
    xor eax, eax
    jmp 9f
1:  cmp rax, -107               # WSAENOTCONN
    jne 9f
    test dword ptr [r12 + WSK_state], WSK_CONNECTING
    jz 9f
    mov rax, -11
9:  EPILOGUE

# win_sock_close(FD*): one descriptor less; the last one closes the socket
FN win_sock_close
    PROLOGUE 96
    mov rbx, [rdi + FD_aux]
    mov dword ptr [rdi + FD_kind], 0
    dec dword ptr [rbx + WSK_refs]
    jnz 9f
    mov rcx, [rbx + WSK_sock]
    API closesocket
    mov rdi, rbx
    call mem_free
9:  xor eax, eax
    EPILOGUE

# win_sock_dup(FD*) -> a new descriptor of the same socket, or -errno
FN win_sock_dup
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + FD_handle]
    mov esi, WSK_KIND
    mov edx, [rbx + FD_flags]
    call win_fd_alloc
    test rax, rax
    js 9f
    mov rcx, [rbx + FD_aux]
    mov [r8 + FD_aux], rcx
    inc dword ptr [rcx + WSK_refs]
9:  pop rbx
    ret

# win_sock_setfl(FD*, flags) -> 0 or -errno: O_NONBLOCK sets the socket's mode, then the flags
FN win_sock_setfl
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov rdi, [rbx + FD_handle]
    xor esi, esi
    test r12d, O_NONBLOCK
    setnz sil
    call wsk_nonblock
    test rax, rax
    js 9f
    mov [rbx + FD_flags], r12d
    xor eax, eax
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# win_sock_events(FD*, events) -> revents as Linux polls a TCP socket: POLLIN with bytes, at the
#   end or with a connection to accept; POLLOUT while it takes more; POLLERR | POLLHUP for a failed
#   connect or a reset connection; POLLHUP once both directions are shut. The other side's orderly
#   close is POLLIN alone (read says 0), so a watch asking nothing is not woken by it.
FN win_sock_events
    PROLOGUE 112
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rbx + FD_aux]
    xor r15d, r15d
    test dword ptr [r13 + WSK_state], WSK_CONNECTING
    jz 1f
    mov rdi, r13
    call wsk_connect_check
    test rax, rax
    jz 9f                       # still connecting
    jns 1f                      # connected: as any socket
.Lev_failed:
    mov r15d, POLLOUT | POLLERR | POLLHUP
    jmp 8f
1:  cmp dword ptr [r13 + WSK_err], 0
    jne .Lev_failed
    mov rax, [rbx + FD_handle]
    mov [rsp + 96], rax
    mov dword ptr [rsp + 104], WSK_POLLRDNORM | WSK_POLLWRNORM   # events; revents 0
    lea rcx, [rsp + 96]
    mov edx, 1
    xor r8d, r8d
    API WSAPoll
    cmp eax, -1
    jne 2f
    mov r15d, POLLERR
    jmp 8f
2:  movzx r14d, word ptr [rsp + 106]
    test r14d, WSK_POLLRDNORM
    jz 3f
    or r15d, POLLIN
3:  test r14d, WSK_POLLWRNORM
    jz 4f
    test dword ptr [r13 + WSK_state], WSK_SHUT_WR
    jnz 4f
    or r15d, POLLOUT
4:  test dword ptr [r13 + WSK_state], WSK_SHUT_RD
    jz 5f
    or r15d, POLLIN
5:  test r14d, WSK_POLLHUP | WSK_POLLERR
    jz 7f
    # closed or reset: bytes still to read or an orderly end are POLLIN (with POLLHUP when this
    # side shut its writing too); a reset fails the peek
    mov rcx, [rbx + FD_handle]
    lea rdx, [rsp + 108]
    mov r8d, 1
    mov r9d, WSK_MSG_PEEK
    API recv
    cmp eax, -1
    je 6f
    or r15d, POLLIN
    test eax, eax
    jnz 7f
    test dword ptr [r13 + WSK_state], WSK_SHUT_WR
    jz 7f
    or r15d, POLLHUP
    jmp 7f
6:  API WSAGetLastError
    cmp eax, WSK_EWOULDBLOCK
    je 7f
    or r15d, POLLIN | POLLERR | POLLHUP
7:  mov eax, [r13 + WSK_state]
    and eax, WSK_SHUT_RD | WSK_SHUT_WR
    cmp eax, WSK_SHUT_RD | WSK_SHUT_WR
    jne 8f
    or r15d, POLLHUP
8:  or r12d, POLLERR | POLLHUP  # reported whatever was asked
    and r15d, r12d
9:  mov eax, r15d
    EPILOGUE

.section .rodata
# Linux errno for WSAEWOULDBLOCK (10035) .. WSAEHOSTUNREACH (10065)
wsk_errnos:
    .byte 11, 115, 114, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100
    .byte 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 40, 36, 112, 113
