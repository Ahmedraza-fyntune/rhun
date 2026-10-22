# debug adapter wire: the adapter's process (spawned as the user, outside any sandbox), its pipes,
# Content-Length framing in both directions, its error output, and a log of the last messages for
# failing tests (print-dap-log). dap.s gives meaning to the messages.
.include "rhun.inc"

.equ DAP_LOG_N, 50
.equ DAP_LOG_TEXT, 300
.equ DAP_ETAIL_LINES, 20
.equ DAP_LINE_MAX, 4096

STRUCT
F DLG_dir, 4             # '>' to the adapter, '<' from it, '!' a note
F DLG_sid, 4
F DLG_len, 4             # the message's full length
F DLG_n, 4               # bytes kept
F DLG_text, DAP_LOG_TEXT
ENDSTRUCT DLG_SIZE

.bss
.p2align 3
dlog: .zero DLG_SIZE * DAP_LOG_N
dlog_next: .long 0
dlog_count: .long 0
.p2align 3
hdr: .zero 64
errchunk: .zero 4096

.text

# ---------------- the process ----------------

# dap_spawn(ds) -> rax 0, or -errno: starts the adapter from DS_args with three pipes through the
#   tasks group's user-process helper (uproc.s: outside every sandbox, a process group of its own
#   that dies with rhun on Linux, a job object on Windows), with the user's login environment plus
#   RHUN_DEBUG_SESSION, in the project folder (else the extension's). Adapters start nowhere else.
FN dap_spawn
    PROLOGUE 96
    mov rbx, rdi
    mov dword ptr [rsp], -1             # in: child reads [rsp], rhun writes [rsp+4]
    mov dword ptr [rsp + 4], -1
    mov dword ptr [rsp + 8], -1         # out: rhun reads [rsp+8], child writes [rsp+12]
    mov dword ptr [rsp + 12], -1
    mov dword ptr [rsp + 16], -1        # err
    mov dword ptr [rsp + 20], -1
    mov qword ptr [rsp + 24], 0         # argv
    mov qword ptr [rsp + 32], 0         # envp
    # argv from the NUL-separated words
    mov eax, [rbx + DS_nargs]
    lea rdi, [rax*8 + 8]
    call mem_alloc
    mov [rsp + 24], rax
    mov r12, rax
    mov r13, [rbx + DS_args + SB_ptr]
    xor r14d, r14d
1:  cmp r14d, [rbx + DS_nargs]
    jae 2f
    mov [r12 + r14*8], r13
    mov rdi, r13
    call strlen
    lea r13, [r13 + rax + 1]
    inc r14d
    jmp 1b
2:  mov qword ptr [r12 + r14*8], 0
    # RHUN_DEBUG_SESSION=ID
    lea rdi, [rsp + 48]
    lea rsi, [rip + .Lenv_session]
    call cstr_copy
    mov r15, rax
    mov rdi, rax
    mov esi, [rbx + DS_id]
    call fmt_u64
    mov byte ptr [r15 + rax], 0
    lea rax, [rsp + 48]
    mov [rip + env_extra], rax
    mov qword ptr [rip + env_extra + 8], 0
    lea rdi, [rip + env_extra]
    xor esi, esi
    xor edx, edx
    call uproc_env_make
    mov [rsp + 32], rax
    cmp dword ptr [rip + g_remote], 0     # remote hosts: the adapter runs on the host (vfs.s)
    jne .Lsp_remote
    # pipes
    lea rdi, [rsp]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Lsp_fail
    lea rdi, [rsp + 8]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Lsp_fail
    lea rdi, [rsp + 16]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Lsp_fail
    # the folder
    mov rdx, [rip + g_project]
    test rdx, rdx
    jnz 3f
    mov rax, [rbx + DS_dbg_ext]
    mov rdx, [rax + EXT_dir]
3:  mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    mov ecx, [rsp]
    mov r8d, [rsp + 12]
    mov r9d, [rsp + 20]
    xor eax, eax                        # no terminal: a session of its own
    push rax
    push rax
    call uproc_spawn
    add rsp, 16
    mov r14, rax
    # the child's ends
    mov edi, [rsp]
    SYS SYS_close
    mov edi, [rsp + 12]
    SYS SYS_close
    mov edi, [rsp + 20]
    SYS SYS_close
    mov dword ptr [rsp], -1
    mov dword ptr [rsp + 12], -1
    mov dword ptr [rsp + 20], -1
    test r14, r14
    js .Lsp_fail_rax
    mov [rbx + DS_pid], r14d
    mov eax, [rsp + 4]
    mov [rbx + DS_in], eax
    mov eax, [rsp + 8]
    mov [rbx + DS_out], eax
    mov eax, [rsp + 16]
    mov [rbx + DS_err], eax
    mov edi, [rbx + DS_in]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    mov edi, [rbx + DS_out]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    mov edi, [rbx + DS_err]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    mov rdi, rbx
    call dap_watch
    xor r14d, r14d
    jmp .Lsp_done
.Lsp_remote:
    # an adapter the extension ships runs from its folder on the host (remoteext.s)
    mov rdi, [rbx + DS_dbg_ext]
    mov rsi, [rsp + 24]
    test rdi, rdi
    jz 1f
    call remote_ext_argv
    mov rdi, rax
    jmp 2f
1:  mov rdi, rsi
    xor edx, edx
2:  lea eax, [rdx*8 + 2]       # its error output apart; 8: argv[0] a path there
    mov rsi, [rsp + 32]
    mov rdx, [rip + g_project]
    xor ecx, ecx
    xor r8d, r8d
    push rax
    push rax
    call vfs_uproc_spawn
    add rsp, 16
    mov r14, rax
    test rax, rax
    js .Lsp_done
    mov [rbx + DS_pid], r14d
    mov [rbx + DS_out], edx
    mov [rbx + DS_err], ecx
    mov edi, edx                # the input: a second descriptor of the same socket
    xor esi, esi                # F_DUPFD
    mov edx, 3
    SYS SYS_fcntl
    mov [rbx + DS_in], eax
    mov edi, eax
    mov esi, 2                  # F_SETFD FD_CLOEXEC
    mov edx, 1
    SYS SYS_fcntl
    mov rdi, rbx
    call dap_watch
    xor r14d, r14d
    jmp .Lsp_done
.Lsp_fail:
    mov r14, rax
.Lsp_fail_rax:
    lea r12, [rsp]
    xor r13d, r13d
4:  mov edi, [r12 + r13*4]
    test edi, edi
    js 41f
    SYS SYS_close
41: inc r13d
    cmp r13d, 6
    jb 4b
.Lsp_done:
    mov rdi, [rsp + 24]
    call mem_free
    mov rdi, [rsp + 32]
    test rdi, rdi
    jz 5f
    call mem_free
5:  mov rax, r14
    EPILOGUE

# dap_watch(ds): the event loop reads its output and error output; its input is watched only while
#   bytes wait to go out
FN dap_watch
    push rbx
    mov rbx, rdi
    mov edi, [rbx + DS_out]
    test edi, edi
    js 1f
    mov esi, POLLIN
    lea rdx, [rip + dap_on_out]
    mov rcx, rbx
    call watch_add
    mov dword ptr [rbx + DS_reading], 1
1:  mov edi, [rbx + DS_err]
    test edi, edi
    js 2f
    mov esi, POLLIN
    lea rdx, [rip + dap_on_err]
    mov rcx, rbx
    call watch_add
2:  mov edi, [rbx + DS_in]
    test edi, edi
    js 3f
    xor esi, esi
    lea rdx, [rip + dap_on_in]
    mov rcx, rbx
    call watch_add
3:  pop rbx
    ret

# dap_close_fds(ds): stop watching and close its pipes and sockets
FN dap_close_fds
    push rbx
    push r12
    push r13
    mov rbx, rdi
    lea r12, [rbx + DS_in]
    xor r13d, r13d
1:  mov edi, [r12 + r13*4]
    test edi, edi
    js 2f
    call watch_remove
    mov edi, [r12 + r13*4]
    SYS SYS_close
    mov dword ptr [r12 + r13*4], -1
2:  inc r13d
    cmp r13d, 6                 # DS_in, DS_out, DS_err, DS_aout, DS_ain, DS_csock are adjacent
    jb 1b
    mov dword ptr [rbx + DS_reading], 0
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- tcp ----------------

# sa_make(buf, IPv4 address in network order, port): a Linux sockaddr_in (16 bytes)
sa_make:
    mov dword ptr [rdi], DSK_AF_INET    # the family; the port follows
    mov eax, edx
    shr eax, 8
    mov [rdi + 2], al                   # network order
    mov [rdi + 3], dl
    mov [rdi + 4], esi
    mov qword ptr [rdi + 8], 0
    ret

# dap_pick_port() -> eax a free loopback port, or -errno: bound to 127.0.0.1:0, read back, closed
#   (the adapter binds it next). In a remote window the adapter listens on the host: the host's
#   agent picks one there (an agent without freeport: one free here)
FN dap_pick_port
    PROLOGUE 48
    cmp dword ptr [rip + g_remote], 0
    je 1f
    lea rdi, [rip + .Lv_freeport]
    mov esi, .Lv_freeport_end - .Lv_freeport
    xor edx, edx
    xor ecx, ecx
    call remote_call
    test rax, rax
    jnz 1f
    mov rdi, [rip + g_remote_reply + SB_ptr]
    mov rsi, [rip + g_remote_reply + SB_len]
    call parse_u64
    test edx, edx
    jz 1f
    test eax, eax
    jz 1f
    cmp eax, 65535
    jbe 9f
1:  mov edi, DSK_AF_INET
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js 9f
    mov r12d, eax
    lea rdi, [rsp]
    mov esi, DAP_LOOPBACK
    xor edx, edx
    call sa_make
    mov edi, r12d
    lea rsi, [rsp]
    mov edx, 16
    SYS SYS_bind
    test rax, rax
    js 8f
    mov dword ptr [rsp + 16], 16
    mov edi, r12d
    lea rsi, [rsp]
    lea rdx, [rsp + 16]
    SYS DSK_getsockname
    test rax, rax
    js 8f
    movzx eax, byte ptr [rsp + 2]
    shl eax, 8
    movzx ecx, byte ptr [rsp + 3]
    or eax, ecx
    jnz 8f
    mov rax, -EIO               # no port came back
8:  mov r13, rax
    mov edi, r12d
    SYS SYS_close
    mov rax, r13
9:  EPILOGUE

# dap_tcp_split(ds): a tcp adapter was spawned with three pipes: its output becomes console lines
#   (DS_aout) and its input is only kept (DS_ain, closed at the end) until the socket connects
FN dap_tcp_split
    push rbx
    mov rbx, rdi
    mov edi, [rbx + DS_out]
    call watch_remove
    mov edi, [rbx + DS_in]
    call watch_remove
    mov eax, [rbx + DS_out]
    mov [rbx + DS_aout], eax
    mov eax, [rbx + DS_in]
    mov [rbx + DS_ain], eax
    mov dword ptr [rbx + DS_out], -1
    mov dword ptr [rbx + DS_in], -1
    mov dword ptr [rbx + DS_reading], 0
    mov edi, [rbx + DS_aout]
    mov esi, POLLIN
    lea rdx, [rip + dap_on_aout]
    mov rcx, rbx
    call watch_add
    pop rbx
    ret

# dap_connect_try(ds) -> eax 1 connected (the socket is its input and output from now on), 0 not
#   yet (refused or in progress: try again), or -errno when there is no socket at all. A
#   nonblocking connect is asked again rather than polled (poll is the window system's on macOS):
#   EALREADY means in progress; EISCONN means done, which macOS also says after a refusal, so
#   getpeername decides
FN dap_connect_try
    PROLOGUE 32
    mov rbx, rdi
    # a remote window: the adapter listens on the host's loopback, which the host connects to
    cmp dword ptr [rip + g_remote], 0
    je 1f
    cmp dword ptr [rbx + DS_addr], DAP_LOOPBACK
    je .Lct_remote
1:  mov r12d, [rbx + DS_csock]
    test r12d, r12d
    jns 2f
    mov edi, DSK_AF_INET
    mov esi, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js 9f
    mov r12d, eax
    mov [rbx + DS_csock], eax
2:  lea rdi, [rsp]
    mov esi, [rbx + DS_addr]
    mov edx, [rbx + DS_port]
    call sa_make
    mov edi, r12d
    lea rsi, [rsp]
    mov edx, 16
    SYS SYS_connect
    test rax, rax
    jz 5f
    cmp rax, -DSK_EISCONN
    je 3f
    cmp rax, -DSK_EINPROGRESS
    je 4f
    cmp rax, -DSK_EALREADY
    je 4f
    cmp rax, -EINTR
    je 4f
    jmp 31f
3:  # EISCONN: connected, or (macOS) refused after all: only a connected socket has a peer
    mov dword ptr [rsp + 16], 16
    mov edi, r12d
    lea rsi, [rsp]
    lea rdx, [rsp + 16]
    SYS DSK_getpeername
    test rax, rax
    jz 5f
31: # refused (nobody listens yet) or failed: a new socket next time
    mov edi, r12d
    SYS SYS_close
    mov dword ptr [rbx + DS_csock], -1
4:  xor eax, eax
    EPILOGUE
5:  # connected: reads and writes go through two descriptors of the one socket, each watched
    mov dword ptr [rbx + DS_csock], -1
    mov [rbx + DS_out], r12d
    mov edi, r12d
    mov esi, DSK_F_DUPFD
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 6f
    mov [rbx + DS_in], eax
    mov edi, eax
    mov esi, DSK_F_SETFD
    mov edx, DSK_FD_CLOEXEC
    SYS SYS_fcntl
    mov edi, [rbx + DS_out]
    mov esi, POLLIN
    lea rdx, [rip + dap_on_out]
    mov rcx, rbx
    call watch_add
    mov dword ptr [rbx + DS_reading], 1
    mov edi, [rbx + DS_in]
    xor esi, esi
    lea rdx, [rip + dap_on_in]
    mov rcx, rbx
    call watch_add
    # what waited goes out now
    mov edi, [rbx + DS_in]
    xor esi, esi
    mov rdx, rbx
    call dap_on_in
    mov eax, 1
    EPILOGUE
6:  mov r13, rax
    mov edi, r12d
    SYS SYS_close
    mov dword ptr [rbx + DS_out], -1
    mov rax, r13
9:  EPILOGUE
.Lct_remote:
    # one attempt at a time: a socketpair whose other end the host's connection carries
    #   (remote_sock_connect); refused, it is tried again on the next tick
    mov eax, [rbx + DS_rconn]
    cmp eax, 2
    je 13f
    cmp eax, 1
    je 4b                       # the host is still connecting
    cmp eax, 3
    jne 11f
    mov edi, [rbx + DS_csock]
    SYS SYS_close
    mov dword ptr [rbx + DS_csock], -1
    mov dword ptr [rbx + DS_rconn], 0
    jmp 4b
11: mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    lea r10, [rsp]
    SYS SYS_socketpair
    test rax, rax
    js 9b
    mov eax, [rsp]
    mov [rbx + DS_csock], eax
    inc dword ptr [rbx + DS_rtry]
    mov dword ptr [rbx + DS_rconn], 1
    mov rdi, rbx
    call dap_slot_index
    mov ecx, [rbx + DS_rtry]    # slot | attempt << 8 | session id << 32
    and ecx, 0xffffff
    shl rcx, 8
    or rcx, rax
    mov eax, [rbx + DS_id]
    shl rax, 32
    or rcx, rax
    mov edi, [rsp + 4]
    mov esi, [rbx + DS_port]
    lea rdx, [rip + rconn_done]
    call remote_sock_connect    # it owns the other end, also when it fails
    test rax, rax
    jns 4b
    mov dword ptr [rbx + DS_rconn], 3     # no channel now: again on the next tick
    jmp 4b
13: mov r12d, [rbx + DS_csock]
    mov dword ptr [rbx + DS_rconn], 0
    jmp 5b

# rconn_done(slot | attempt << 8 | session id << 32, 0 connected | 1 refused): the host's answer to a
#   connection; the next tick goes on (connect_tick). A slot made anew meanwhile has another id
FN dap_rconn_answer             # (tests: debug-connect-answer)
rconn_done:
    PROLOGUE
    mov r12, rdi
    mov r13d, esi
    movzx edi, r12b
    cmp edi, DS_MAX
    jae 9f
    call dap_slot
    mov rbx, rax
    mov rax, r12
    shr rax, 32
    cmp eax, [rbx + DS_id]
    jne 9f
    shr r12, 8
    and r12d, 0xffffff
    mov eax, [rbx + DS_rtry]
    and eax, 0xffffff
    cmp r12d, eax
    jne 9f
    cmp dword ptr [rbx + DS_rconn], 1
    jne 9f
    mov eax, 2
    test r13d, r13d
    jz 1f
    mov eax, 3
1:  mov [rbx + DS_rconn], eax
    test r13d, r13d
    jnz 2f
    mov qword ptr [rbx + DS_deadline], 0  # connected: at once
2:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ---------------- reading ----------------

# dap_on_out(fd, revents, ds): its output into DS_rbuf, at most 8 MiB + 64 KiB unparsed; a full
#   buffer stops the watch until dap.s has parsed some
dap_on_out:
    PROLOGUE
    mov r12d, edi
    mov rbx, rdx
    mov r13d, 4                 # reads per wakeup
1:  mov r14, DAP_BODY_MAX + 65536
    sub r14, [rbx + DS_rbuf + SB_len]
    jg 2f
    mov edi, r12d
    xor esi, esi
    call watch_set_events
    mov dword ptr [rbx + DS_reading], 0
    jmp 9f
2:  cmp r14, 65536
    jbe 3f
    mov r14d, 65536
3:  lea rdi, [rbx + DS_rbuf]
    mov rsi, r14
    call sb_reserve
    mov edi, r12d
    mov rsi, rax
    mov rdx, r14
    SYS SYS_read
    cmp rax, -EINTR
    je 3b
    test rax, rax
    jg 4f
    cmp rax, -EAGAIN
    je 9f
    # end of output (or an error): dap.s notices DSF_EOF
    or dword ptr [rbx + DS_flags], DSF_EOF
    mov edi, r12d
    call watch_remove
    mov edi, r12d
    SYS SYS_close
    mov dword ptr [rbx + DS_out], -1
    mov dword ptr [rbx + DS_reading], 0
    call time_ms
    mov [rbx + DS_exited_at], rax
    jmp 9f
4:  add [rbx + DS_rbuf + SB_len], rax
    dec r13d
    jnz 1b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# dap_resume_reading(ds): watch its output again once there is room
FN dap_resume_reading
    cmp dword ptr [rdi + DS_reading], 0
    jne 1f
    mov eax, [rdi + DS_out]
    test eax, eax
    js 1f
    mov dword ptr [rdi + DS_reading], 1
    mov edi, eax
    mov esi, POLLIN
    jmp watch_set_events
1:  ret

# dap_on_err(fd, revents, ds): its error output, line by line, to the console (adapter:) and the
#   last 20 lines kept for a crash message
dap_on_err:
    mov ecx, DS_err
    jmp on_lines
# dap_on_aout(fd, revents, ds): a tcp adapter's standard output, as its error output is
dap_on_aout:
    mov ecx, DS_aout
on_lines:
    PROLOGUE 16
    mov r12d, edi
    mov rbx, rdx
    mov r15d, ecx               # the field that holds this fd
    # a tcp adapter's standard output is where the program it starts writes (Delve's debuggee);
    #   each stream keeps its own line in progress
    mov dword ptr [rsp], DCON_ADAPTER
    mov dword ptr [rsp + 4], DS_ebuf
    cmp ecx, DS_aout
    jne 1f
    mov dword ptr [rsp], DCON_STDOUT
    mov dword ptr [rsp + 4], DS_obuf
1:  mov edi, r12d
    lea rsi, [rip + errchunk]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jg 2f
    cmp rax, -EAGAIN
    je 9f
    # closed: what is left is a last line
    mov rdi, rbx
    mov esi, [rsp]              # the category
    mov edx, [rsp + 4]          # the line in progress
    call err_flush
    mov edi, r12d
    call watch_remove
    mov edi, r12d
    SYS SYS_close
    mov dword ptr [rbx + r15], -1
    jmp 9f
2:  mov r13, rax
    lea r14, [rip + errchunk]
3:  test r13, r13
    jz 9f
    movzx esi, byte ptr [r14]
    inc r14
    dec r13
    cmp esi, 10
    jne 4f
    mov rdi, rbx
    mov esi, [rsp]              # the category
    mov edx, [rsp + 4]          # the line in progress
    call err_flush
    jmp 3b
4:  mov eax, [rsp + 4]
    lea rdi, [rbx + rax]
    call sb_push_byte
    mov eax, [rsp + 4]
    cmp qword ptr [rbx + rax + SB_len], DAP_LINE_MAX
    jb 3b
    mov rdi, rbx
    mov esi, [rsp]              # the category
    mov edx, [rsp + 4]          # the line in progress
    call err_flush
    jmp 3b
9:  EPILOGUE

# err_flush(ds, category, DS_ebuf | DS_obuf): that line in progress, if any, to the console and the
#   tail
err_flush:
    PROLOGUE
    mov rbx, rdi
    mov r14d, esi
    mov r15d, edx
    mov r12, [rbx + r15 + SB_ptr]
    mov r13, [rbx + r15 + SB_len]
    test r13, r13
    jz 9f
    cmp byte ptr [r12 + r13 - 1], 13
    jne 1f
    dec r13
1:  mov edi, [rbx + DS_id]
    mov esi, r14d
    mov rdx, r12
    mov rcx, r13
    call dcon_line
    # the tail: at most 20 lines
    lea rdi, [rbx + DS_etail]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rbx + DS_etail]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + DS_etail + SB_ptr]
    mov rsi, [rbx + DS_etail + SB_len]
    xor ecx, ecx
    xor edx, edx
2:  cmp rcx, rsi
    jae 3f
    cmp byte ptr [rdi + rcx], 10
    jne 21f
    inc edx
21: inc rcx
    jmp 2b
3:  cmp edx, DAP_ETAIL_LINES
    jbe 8f
    # drop the first line
    xor ecx, ecx
4:  cmp byte ptr [rdi + rcx], 10
    je 5f
    inc rcx
    jmp 4b
5:  inc rcx
    sub rsi, rcx
    mov [rbx + DS_etail + SB_len], rsi
    mov rdx, rsi
    lea rsi, [rdi + rcx]
    call memmove
8:  lea rdi, [rbx + r15]
    call sb_clear
9:  EPILOGUE

# ---------------- writing ----------------

# dap_send(ds, body ptr, len) -> eax 1, 0 when the adapter is not reading (4 MiB queued) or gone
FN dap_send
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp dword ptr [rbx + DS_in], 0
    jge 1f
    cmp dword ptr [rbx + DS_state], DSS_CONNECTING
    jne 8f                      # gone; while it connects, requests wait in the queue
1:  mov rax, [rbx + DS_wq + SB_len]
    sub rax, [rbx + DS_wq_off]
    add rax, r13
    cmp rax, DAP_WQ_MAX
    ja 8f
    mov edi, '>'
    mov esi, [rbx + DS_id]
    mov rdx, r12
    mov rcx, r13
    call dap_log
    lea rdi, [rip + hdr]
    lea rsi, [rip + .Lcl]
    call cstr_copy
    mov r14, rax
    mov rdi, rax
    mov rsi, r13
    call fmt_u64
    add r14, rax
    mov dword ptr [r14], 0x0a0d0a0d
    add r14, 4
    lea rax, [rip + hdr]
    sub r14, rax
    lea rdi, [rbx + DS_wq]
    lea rsi, [rip + hdr]
    mov rdx, r14
    call sb_push
    lea rdi, [rbx + DS_wq]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    # try at once; the rest waits for POLLOUT
    mov edi, [rbx + DS_in]
    xor esi, esi
    mov rdx, rbx
    call dap_on_in
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# dap_on_in(fd, revents, ds): write what is queued
dap_on_in:
    PROLOGUE
    mov rbx, rdx
1:  mov edi, [rbx + DS_in]
    test edi, edi
    js 9f
    mov rsi, [rbx + DS_wq + SB_ptr]
    add rsi, [rbx + DS_wq_off]
    mov rdx, [rbx + DS_wq + SB_len]
    sub rdx, [rbx + DS_wq_off]
    jz 5f
    SYS SYS_write
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 4f
    test rax, rax
    js 6f
    add [rbx + DS_wq_off], rax
    jmp 1b
4:  mov edi, [rbx + DS_in]
    mov esi, POLLOUT
    call watch_set_events
    jmp 9f
5:  lea rdi, [rbx + DS_wq]
    call sb_clear
    mov qword ptr [rbx + DS_wq_off], 0
    mov edi, [rbx + DS_in]
    xor esi, esi
    call watch_set_events
    jmp 9f
6:  # the adapter closed its input: nothing more goes out
    lea rdi, [rbx + DS_wq]
    call sb_clear
    mov qword ptr [rbx + DS_wq_off], 0
    mov edi, [rbx + DS_in]
    call watch_remove
    mov edi, [rbx + DS_in]
    SYS SYS_close
    mov dword ptr [rbx + DS_in], -1
9:  EPILOGUE

# ---------------- framing ----------------

# dap_frame(ds) -> rax the next message's body, rdx its length, rcx the bytes it takes (header
#   included); rax 0 when none is complete yet; rax -1 when the output is not DAP (rdx a reason).
#   Bytes before a header (a program printing to the adapter's output) go to the console.
FN dap_frame
    PROLOGUE
    mov rbx, rdi
1:  mov r12, [rbx + DS_rbuf + SB_ptr]
    mov r13, [rbx + DS_rbuf + SB_len]
    test r13, r13
    jz .Lfr_none
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lcl_name]
    mov ecx, 15
    call str_ifind
    test rax, rax
    jz 3f
    jns 2f
    # no header: complete lines are junk; a partial one may be a header in progress
    mov rcx, r13
11: test rcx, rcx
    jz .Lfr_none
    cmp byte ptr [r12 + rcx - 1], 10
    je 12f
    dec rcx
    jmp 11b
12: mov rax, rcx
2:  # rax junk bytes before the header
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call junk_lines
    mov rdi, rbx
    mov rsi, r14
    call dap_drop
    jmp 1b
3:  # the header's end within 1 KiB
    mov r14, r13
    cmp r14, DAP_HEADER_MAX
    jbe 31f
    mov r14d, DAP_HEADER_MAX
31: mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lcrlf2]
    mov ecx, 4
    call str_find
    test rax, rax
    jns 4f
    cmp r13, DAP_HEADER_MAX
    jb .Lfr_none
    lea rdx, [rip + .Lr_header]
    jmp .Lfr_bad
4:  lea r15, [rax + 4]          # body offset
    # the length: after "Content-Length:" and blanks
    lea rdi, [r12 + 15]
    mov rsi, rax
    sub rsi, 15
5:  test rsi, rsi
    jz 51f
    cmp byte ptr [rdi], ' '
    jne 51f
    inc rdi
    dec rsi
    jmp 5b
51: call parse_u64
    test rdx, rdx
    jz 6f
    cmp rdx, 12
    ja 6f
    cmp rax, DAP_BODY_MAX
    ja 7f
    lea rcx, [r15 + rax]
    cmp r13, rcx
    jb .Lfr_none
    mov rdx, rax
    lea rax, [r12 + r15]
    EPILOGUE
6:  lea rdx, [rip + .Lr_length]
    jmp .Lfr_bad
7:  lea rdx, [rip + .Lr_big]
.Lfr_bad:
    mov rax, -1
    EPILOGUE
.Lfr_none:
    xor eax, eax
    EPILOGUE

# junk_lines(ds, ptr, len): bytes outside the framing, as adapter: lines (at most 4 KiB)
junk_lines:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, DAP_LINE_MAX
    jbe 1f
    mov r13d, DAP_LINE_MAX
1:  test r13, r13
    jz 9f
    xor ecx, ecx
2:  cmp rcx, r13
    jae 3f
    cmp byte ptr [r12 + rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov r14, rcx
    mov rdx, r12
    mov rcx, r14
    test rcx, rcx
    jz 4f
    cmp byte ptr [rdx + rcx - 1], 13
    jne 31f
    dec rcx
31: mov edi, [rbx + DS_id]
    mov esi, DCON_ADAPTER
    call dcon_line
4:  lea r12, [r12 + r14 + 1]
    sub r13, r14
    jz 9f
    dec r13
    jmp 1b
9:  EPILOGUE

# dap_drop(ds, n): the first n unparsed bytes are done
FN dap_drop
    push rbx
    mov rbx, rdi
    mov rdx, [rbx + DS_rbuf + SB_len]
    sub rdx, rsi
    jbe 1f
    mov [rbx + DS_rbuf + SB_len], rdx
    mov rdi, [rbx + DS_rbuf + SB_ptr]
    add rsi, rdi
    call memmove
    pop rbx
    ret
1:  mov qword ptr [rbx + DS_rbuf + SB_len], 0
    pop rbx
    ret

# ---------------- the log ----------------

# dap_log(dir, session id, ptr, len): one entry of the last 50, abbreviated
FN dap_log
    PROLOGUE
    mov eax, [rip + dlog_next]
    imul rax, rax, DLG_SIZE
    lea rbx, [rip + dlog]
    add rbx, rax
    inc dword ptr [rip + dlog_next]
    cmp dword ptr [rip + dlog_next], DAP_LOG_N
    jb 1f
    mov dword ptr [rip + dlog_next], 0
1:  cmp dword ptr [rip + dlog_count], DAP_LOG_N
    jae 2f
    inc dword ptr [rip + dlog_count]
2:  mov [rbx + DLG_dir], edi
    mov [rbx + DLG_sid], esi
    mov [rbx + DLG_len], ecx
    cmp rcx, DAP_LOG_TEXT
    jbe 3f
    mov ecx, DAP_LOG_TEXT
3:  mov [rbx + DLG_n], ecx
    lea rdi, [rbx + DLG_text]
    mov rsi, rdx
    mov rdx, rcx
    call memcpy
    EPILOGUE

# dap_log_dump(sb): the entries, oldest first: "> 1 LEN TEXT" with control bytes as spaces
FN dap_log_dump
    PROLOGUE
    mov r12, rdi
    mov r13d, [rip + dlog_next]
    sub r13d, [rip + dlog_count]
    jns 1f
    add r13d, DAP_LOG_N
1:  xor r14d, r14d
2:  cmp r14d, [rip + dlog_count]
    jae 9f
    mov eax, r13d
    add eax, r14d
    cmp eax, DAP_LOG_N
    jb 3f
    sub eax, DAP_LOG_N
3:  imul rax, rax, DLG_SIZE
    lea rbx, [rip + dlog]
    add rbx, rax
    mov rdi, r12
    mov esi, [rbx + DLG_dir]
    call sb_push_byte
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + DLG_sid]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + DLG_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    xor r15d, r15d
4:  cmp r15d, [rbx + DLG_n]
    jae 5f
    movzx esi, byte ptr [rbx + DLG_text + r15]
    cmp esi, 0x20
    jae 41f
    mov esi, ' '
41: mov rdi, r12
    call sb_push_byte
    inc r15d
    jmp 4b
5:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r14d
    jmp 2b
9:  EPILOGUE

.bss
.p2align 3
env_extra: .zero 16

.section .rodata
.Lv_freeport: .ascii "freeport 0"
.Lv_freeport_end:
.Lenv_session: .asciz "RHUN_DEBUG_SESSION="
.Lcl: .asciz "Content-Length: "
.Lcl_name: .ascii "content-length:"
.Lcrlf2: .ascii "\r\n\r\n"
.Lr_header: .asciz "the debugger's output is not DAP (a header over 1 KB)"
.Lr_length: .asciz "the debugger's output is not DAP (no Content-Length)"
.Lr_big: .asciz "the debugger sent a message over 8 MB"
