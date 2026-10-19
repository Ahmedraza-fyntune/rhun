# remote agent: `rhun --remote-agent`, the worker a remote window starts on the host over ssh or
# docker exec (remote.s bootstraps it). It is the same static Linux binary as the editor. It speaks
# the mux protocol (remote.s, top) on its standard input and output and runs what the window asks
# for: programs on pipes or pseudo-terminals, file system requests, watches, file lists and search.
# It opens no port and runs everything as the user it was started as.
.include "rhun.inc"

.ifndef WINDOWS

.equ AG_MAXCH, 1024             # channels (the client numbers them, MUX_MAXCH in remote.s)
.equ AG_WINDOW, 1048576         # flow control window of a channel, each way
.equ AG_READ, 65536             # bytes read from a program at a time
.equ AG_GRANT, 65536            # credit is returned once this much input was taken
.equ AG_WQ_HIGH, 16777216       # past this much queued output, programs are not read
.equ AG_MAXPOLL, 2200
.equ AG_ENV_MS, 5000            # the login shell's environment: how long it may take
.equ AG_REQ_MAX, 67108864       # a request's body at most (a file written in one piece)

# channel modes
.equ AM_FREE, 0
.equ AM_PIPE, 1                 # a program on pipes
.equ AM_PTY, 2                  # a program on a pseudo-terminal
.equ AM_ERR, 3                  # a program's error output, on a channel of its own
.equ AM_STREAM, 4               # a file list or search sent as data, then e

# channel flags
.equ ACF_IEOF, 1                # the client ended the input: close it once written
.equ ACF_OEOF, 2                # the output ended and e was sent
.equ ACF_EXITED, 4              # x was sent
.equ ACF_ICLOSED, 8             # the program's input is closed

# poll roles (low 3 bits of a pmap entry; the channel above them)
.equ PR_MUXIN, 0
.equ PR_MUXOUT, 1
.equ PR_OUT, 2
.equ PR_IN, 3
.equ PR_INOTIFY, 4

STRUCT
F AC_mode, 4
F AC_pid, 4                     # the program, 0 for none
F AC_in, 4                      # its input: a pipe's write end or the pty master; -1
F AC_out, 4                     # its output: a pipe's read end or the pty master; -1
F AC_flags, 4                   # ACF_*
F AC_status, 4                  # exit status once ACF_EXITED
F AC_credit, 8                  # bytes the client lets this side send on the channel
F AC_grant, 8                   # input written to the program and not yet credited back
F AC_ioff, 8                    # the written part of AC_ibuf
F AC_ibuf, SB_SIZE              # input the program has not taken yet
ENDSTRUCT AC_SIZE

.bss
.p2align 3
ag_ch: .zero AC_SIZE * AG_MAXCH
ag_rbuf: .zero SB_SIZE          # the mux stream from the client, not yet handled
ag_wq: .zero SB_SIZE            # the mux stream to the client, not yet written
ag_wq_off: .quad 0
ag_tmp: .zero SB_SIZE           # scratch: a reply's body
ag_toks: .zero 16 * 10
ag_ntok: .quad 0
ag_pfd: .zero 8 * AG_MAXPOLL
ag_pmap: .zero 4 * AG_MAXPOLL
ag_npoll: .quad 0
ag_quit: .long 0
ag_hash: .quad 0
ag_path: .zero 4096
ag_path2: .zero 4096
ag_statbuf: .zero 144
ag_envbuf: .quad 0              # the captured environment's strings (kept for the process's life)
ag_envv: .quad 0
ag_delay: .quad 0               # RHUN_REMOTE_DELAY_MS: every reply waits this long (tests)
ag_argv: .zero 8 * 260

.data
ag_inotify: .long -1
.bss
.p2align 3
ag_exclude: .quad 0
ag_walk_cb: .quad 0
ag_walk_max: .quad 0
ag_walk_n: .quad 0
ag_grep_bytes: .quad 0
ag_query: .quad 0
ag_query_len: .quad 0
ag_rel_len: .long 0
ag_depth: .long 0
ag_walk_stop: .long 0
ag_grep_case: .long 0
ag_rel: .zero 4200

.text

# remote_agent_main(): never returns
FN remote_agent_main
    PROLOGUE 16
    # only the stream: descriptors the shell left open (its script, the binary) close
    mov edi, 3
    mov esi, -1
    xor edx, edx
    SYS SYS_close_range
    call sys_file_capacity
    mov edi, 0
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    mov edi, 1
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    # every channel starts closed
    lea rbx, [rip + ag_ch]
    xor ecx, ecx
1:  mov dword ptr [rbx + AC_in], -1
    mov dword ptr [rbx + AC_out], -1
    add rbx, AC_SIZE
    inc ecx
    cmp ecx, AG_MAXCH
    jb 1b
    lea rdi, [rip + .Lenv_delay]
    call getenv
    test rax, rax
    jz 2f
    mov rbx, rax
    mov rdi, rax
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call parse_u64
    mov [rip + ag_delay], rax
2:  call ag_capture_env
    # hello rhun-remote VERSION HASH: the client checks that it is the binary it sent
    lea rdi, [rip + .Lself]
    call fnv_file
    mov [rip + ag_hash], rax
    lea rdi, [rip + ag_wq]
    lea rsi, [rip + .Lhello]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    lea rsi, [rip + rhun_version]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    mov esi, ' '
    call sb_push_byte
    mov rsi, [rip + ag_hash]
    call ag_push_hex
    lea rdi, [rip + ag_wq]
    mov esi, 10
    call sb_push_byte
.Lag_loop:
    cmp dword ptr [rip + ag_quit], 0
    jne .Lag_end
    call ag_poll
    call ag_reap
    jmp .Lag_loop
.Lag_end:
    # the window went away: its programs end with it
    lea rbx, [rip + ag_ch]
    xor r12d, r12d
3:  mov eax, [rbx + AC_mode]
    cmp eax, AM_PIPE
    je 4f
    cmp eax, AM_PTY
    jne 5f
4:  mov edi, [rbx + AC_pid]
    test edi, edi
    jle 5f
    test dword ptr [rbx + AC_flags], ACF_EXITED
    jnz 5f
    neg edi
    mov esi, SIGHUP
    SYS SYS_kill
    mov edi, [rbx + AC_pid]
    mov esi, SIGTERM
    SYS SYS_kill
5:  add rbx, AC_SIZE
    inc r12d
    cmp r12d, AG_MAXCH
    jb 3b
    xor edi, edi
    call sys_exit

# ag_push_hex(rsi value): 16 lowercase hex digits onto ag_wq
ag_push_hex:
    push rbx
    sub rsp, 32
    mov rbx, rsi
    mov ecx, 15
1:  mov eax, ebx
    and eax, 15
    lea rdx, [rip + .Lhex]
    mov al, [rdx + rax]
    mov [rsp + rcx], al
    shr rbx, 4
    dec ecx
    jns 1b
    lea rdi, [rip + ag_wq]
    mov rsi, rsp
    mov edx, 16
    call sb_push
    add rsp, 32
    pop rbx
    ret

# ag_capture_env(): the login shell's environment, for the programs this agent starts (a language
# server in ~/.cargo/bin is found as in the user's terminal). $SHELL -lc runs the profile, then cat
# prints the environment it was given. A shell that cannot do it in AG_ENV_MS, or prints no marker,
# leaves the agent's own environment.
ag_capture_env:
    PROLOGUE 48
    lea rdi, [rip + .Lshell]
    call getenv
    mov rbx, rax
    test rax, rax
    jz 1f
    cmp byte ptr [rax], '/'
    je 2f
1:  lea rbx, [rip + .Lbin_sh]
2:  mov [rsp], rbx
    lea rax, [rip + .Ldash_lc]
    mov [rsp + 8], rax
    lea rax, [rip + .Lenv_cmd]
    mov [rsp + 16], rax
    mov qword ptr [rsp + 24], 0
    lea rdi, [rsp]
    mov rsi, [rip + g_envp]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, 2                  # a session of its own: no terminal to ask anything on
    call run_piped_input
    test rax, rax
    jle 9f
    mov r12d, eax               # pid
    mov r13d, edx               # fd
    lea rdi, [rip + ag_tmp]
    call sb_clear
    call time_ms
    lea r14, [rax + AG_ENV_MS]
3:  call time_ms
    mov rdx, r14
    sub rdx, rax
    jle 5f
    mov [rsp + 32], r13d
    mov word ptr [rsp + 36], POLLIN
    mov word ptr [rsp + 38], 0
    lea rdi, [rsp + 32]
    mov esi, 1
    SYS SYS_poll
    lea rdi, [rip + ag_tmp]
    mov esi, 65536
    call sb_reserve
    mov rsi, rax
    mov edi, r13d
    mov edx, 65536
    SYS SYS_read
    cmp rax, -EAGAIN
    je 3b
    cmp rax, -EINTR
    je 3b
    test rax, rax
    jle 6f
    add [rip + ag_tmp + SB_len], rax
    cmp qword ptr [rip + ag_tmp + SB_len], 1048576
    jb 3b
    jmp 6f
5:  mov edi, r12d
    neg edi
    mov esi, SIGKILL
    SYS SYS_kill
    mov edi, r12d
    mov esi, SIGKILL
    SYS SYS_kill
    lea rdi, [rip + ag_tmp]
    call sb_clear
6:  mov edi, r13d
    SYS SYS_close
    mov edi, r12d
    xor esi, esi
    call proc_wait
    # the environment follows the marker line, NUL-separated
    mov rdi, [rip + ag_tmp + SB_ptr]
    mov rsi, [rip + ag_tmp + SB_len]
    test rdi, rdi
    jz 9f
    lea rdx, [rip + .Lenv_mark]
    mov ecx, 11
    call str_find
    test rax, rax
    js 9f
    add rax, 11
    mov rsi, [rip + ag_tmp + SB_len]
    sub rsi, rax
    jle 9f
    mov r14, rsi
    add rax, [rip + ag_tmp + SB_ptr]
    mov rdi, rax
    call mem_dup                # NUL-terminated after its last entry
    mov [rip + ag_envbuf], rax
    mov r15, rax
    # count the entries, then point at them
    xor ecx, ecx
    xor edx, edx
    xor ebx, ebx
7:  cmp rdx, r14
    jae 71f
    cmp byte ptr [r15 + rdx], 0
    jne 72f
    inc rbx
72: inc rdx
    jmp 7b
71: lea rdi, [rbx + 2]
    shl rdi, 3
    call mem_alloc
    mov [rip + ag_envv], rax
    mov rdi, rax
    xor ecx, ecx                # entries kept
    xor edx, edx                # offset
8:  cmp rdx, r14
    jae 81f
    lea rsi, [r15 + rdx]
    cmp byte ptr [rsi], 0
    je 82f
    mov [rdi + rcx*8], rsi
    inc rcx
82: inc rdx                     # past this entry and its NUL
    cmp byte ptr [r15 + rdx - 1], 0
    jne 82b
    jmp 8b
81: mov qword ptr [rdi + rcx*8], 0
    test rcx, rcx
    jz 9f
    mov [rip + g_envp], rdi
9:  lea rdi, [rip + ag_tmp]
    call sb_clear
    EPILOGUE

# ---------------- the loop ----------------

# ag_poll(): wait for the client, the programs and the watches, and serve them
ag_poll:
    PROLOGUE
    xor ebx, ebx                # entries
    # the client's stream: read unless the queue to it is too long
    mov rax, [rip + ag_wq + SB_len]
    sub rax, [rip + ag_wq_off]
    cmp rax, AG_WQ_HIGH
    jae 1f
    xor edi, edi
    mov esi, POLLIN
    mov edx, PR_MUXIN
    call ag_padd
1:  mov rax, [rip + ag_wq + SB_len]
    cmp rax, [rip + ag_wq_off]
    je 2f
    mov edi, 1
    mov esi, POLLOUT
    mov edx, PR_MUXOUT
    call ag_padd
2:  mov edi, [rip + ag_inotify]
    test edi, edi
    js 3f
    mov esi, POLLIN
    mov edx, PR_INOTIFY
    call ag_padd
3:  # the channels
    lea r12, [rip + ag_ch]
    xor r13d, r13d
4:  cmp dword ptr [r12 + AC_mode], AM_FREE
    je 6f
    mov edi, [r12 + AC_out]
    test edi, edi
    js 5f
    test dword ptr [r12 + AC_flags], ACF_OEOF
    jnz 5f
    cmp qword ptr [r12 + AC_credit], 0
    jle 5f
    mov rax, [rip + ag_wq + SB_len]
    sub rax, [rip + ag_wq_off]
    cmp rax, AG_WQ_HIGH
    jae 5f
    mov esi, POLLIN
    mov edx, r13d
    shl edx, 3
    or edx, PR_OUT
    call ag_padd
5:  mov edi, [r12 + AC_in]
    test edi, edi
    js 6f
    test dword ptr [r12 + AC_flags], ACF_ICLOSED
    jnz 6f
    mov rax, [r12 + AC_ibuf + SB_len]
    cmp rax, [r12 + AC_ioff]
    je 6f
    mov esi, POLLOUT
    mov edx, r13d
    shl edx, 3
    or edx, PR_IN
    call ag_padd
6:  add r12, AC_SIZE
    inc r13d
    cmp r13d, AG_MAXCH
    jb 4b
    # programs that run are checked for their exit now and then
    mov edx, -1
    call ag_any_running
    test eax, eax
    jz 7f
    mov edx, 100
7:  lea rdi, [rip + ag_pfd]
    mov esi, ebx
    movsxd rdx, edx
    SYS SYS_poll
    test rax, rax
    jle 9f
    xor r12d, r12d
.Lap_disp:
    cmp r12d, ebx
    jae 9f
    lea rax, [rip + ag_pfd]
    movzx ecx, word ptr [rax + r12*8 + 6]
    test ecx, ecx
    jz .Lap_next
    lea rax, [rip + ag_pmap]
    mov eax, [rax + r12*4]
    mov edi, eax
    shr edi, 3                  # channel
    and eax, 7
    cmp eax, PR_MUXIN
    jne 10f
    call ag_read_client
    jmp .Lap_next
10: cmp eax, PR_MUXOUT
    jne 11f
    call ag_flush
    jmp .Lap_next
11: cmp eax, PR_OUT
    jne 12f
    call ag_read_program
    jmp .Lap_next
12: cmp eax, PR_IN
    jne 13f
    call ag_write_program
    jmp .Lap_next
13: call ag_read_inotify
.Lap_next:
    inc r12d
    jmp .Lap_disp
9:  EPILOGUE

# ag_padd(fd, events, role): one more poll entry (ebx counts them)
ag_padd:
    cmp ebx, AG_MAXPOLL
    jae 1f
    lea rax, [rip + ag_pfd]
    mov [rax + rbx*8], edi
    mov [rax + rbx*8 + 4], esi
    lea rax, [rip + ag_pmap]
    mov [rax + rbx*4], edx
    inc ebx
1:  ret

# ag_any_running() -> 1 while a program has not been reaped
ag_any_running:
    lea rcx, [rip + ag_ch]
    xor edx, edx
1:  mov eax, [rcx + AC_mode]
    cmp eax, AM_PIPE
    je 2f
    cmp eax, AM_PTY
    jne 3f
2:  cmp dword ptr [rcx + AC_pid], 0
    jle 3f
    test dword ptr [rcx + AC_flags], ACF_EXITED
    jz 4f
3:  add rcx, AC_SIZE
    inc edx
    cmp edx, AG_MAXCH
    jb 1b
    xor eax, eax
    ret
4:  mov eax, 1
    ret

# ag_reap(): programs that exited: x CH STATUS
ag_reap:
    PROLOGUE
    lea rbx, [rip + ag_ch]
    xor r12d, r12d
1:  mov eax, [rbx + AC_mode]
    cmp eax, AM_PIPE
    je 2f
    cmp eax, AM_PTY
    jne 3f
2:  mov edi, [rbx + AC_pid]
    test edi, edi
    jle 3f
    test dword ptr [rbx + AC_flags], ACF_EXITED
    jnz 3f
    mov esi, 1
    call proc_wait
    cmp eax, -1
    je 3f
    test eax, eax
    jns 4f
    mov eax, 255                # not a child any more (cannot happen): it is gone
4:  mov [rbx + AC_status], eax
    or dword ptr [rbx + AC_flags], ACF_EXITED
    lea rdi, [rip + ag_wq]
    lea rsi, [rip + .Lx]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    mov esi, r12d
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ag_wq]
    mov esi, [rbx + AC_status]
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, 10
    call sb_push_byte
    mov edi, r12d
    call ag_maybe_free
3:  add rbx, AC_SIZE
    inc r12d
    cmp r12d, AG_MAXCH
    jb 1b
    EPILOGUE

# ag_chan(ch) -> rax AC* (ch below AG_MAXCH)
ag_chan:
    mov eax, edi
    imul rax, rax, AC_SIZE
    lea rcx, [rip + ag_ch]
    add rax, rcx
    ret

# ag_maybe_free(ch): a channel whose program exited and whose output ended is forgotten
ag_maybe_free:
    push rbx
    call ag_chan
    mov rbx, rax
    mov eax, [rbx + AC_mode]
    cmp eax, AM_PIPE
    je 1f
    cmp eax, AM_PTY
    je 1f
    cmp eax, AM_FREE
    je 9f
    # error output and streams: once their output ended
    test dword ptr [rbx + AC_flags], ACF_OEOF
    jz 9f
    jmp 2f
1:  mov eax, [rbx + AC_flags]
    and eax, ACF_EXITED | ACF_OEOF
    cmp eax, ACF_EXITED | ACF_OEOF
    jne 9f
2:  mov rdi, rbx
    call ag_free
9:  pop rbx
    ret

# ag_free(AC*): close what is open and mark the channel free
ag_free:
    push rbx
    mov rbx, rdi
    mov edi, [rbx + AC_out]
    test edi, edi
    js 1f
    SYS SYS_close
1:  mov edi, [rbx + AC_in]
    test edi, edi
    js 2f
    cmp edi, [rbx + AC_out]
    je 2f
    test dword ptr [rbx + AC_flags], ACF_ICLOSED
    jnz 2f
    SYS SYS_close
2:  mov dword ptr [rbx + AC_in], -1
    mov dword ptr [rbx + AC_out], -1
    lea rdi, [rbx + AC_ibuf]
    call sb_free
    mov qword ptr [rbx + AC_ioff], 0
    mov qword ptr [rbx + AC_grant], 0
    mov qword ptr [rbx + AC_credit], 0
    mov dword ptr [rbx + AC_flags], 0
    mov dword ptr [rbx + AC_pid], 0
    mov dword ptr [rbx + AC_mode], AM_FREE
    pop rbx
    ret

# ---------------- the stream to the client ----------------

# ag_flush(): write what is queued; a full pipe waits for the next POLLOUT
ag_flush:
    PROLOGUE
1:  mov rdx, [rip + ag_wq + SB_len]
    mov rsi, [rip + ag_wq_off]
    sub rdx, rsi
    jz 8f
    add rsi, [rip + ag_wq + SB_ptr]
    mov edi, 1
    SYS SYS_write
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 7f
    add [rip + ag_wq_off], rax
    jmp 1b
7:  mov dword ptr [rip + ag_quit], 1     # the client is gone
8:  mov qword ptr [rip + ag_wq_off], 0
    mov qword ptr [rip + ag_wq + SB_len], 0
    EPILOGUE
9:  # keep the queue compact
    mov rax, [rip + ag_wq_off]
    cmp rax, 1048576
    jb 91f
    mov rdi, [rip + ag_wq + SB_ptr]
    mov rsi, rdi
    add rsi, rax
    mov rdx, [rip + ag_wq + SB_len]
    sub rdx, rax
    mov [rip + ag_wq + SB_len], rdx
    mov qword ptr [rip + ag_wq_off], 0
    call memmove
91: EPILOGUE

# ag_push_head(kind cstr, ch, value): "KIND CH VALUE\n" onto the queue
ag_push_head:
    push rbx
    push r12
    push r13
    mov rbx, rsi
    mov r12, rdx
    mov rsi, rdi
    lea rdi, [rip + ag_wq]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    mov rsi, rbx
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ag_wq]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, 10
    call sb_push_byte
    pop r13
    pop r12
    pop rbx
    ret

# ag_push_eof(ch): "e CH\n"
ag_push_eof:
    push rbx
    mov ebx, edi
    lea rdi, [rip + ag_wq]
    lea rsi, [rip + .Le]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    mov esi, ebx
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, 10
    call sb_push_byte
    pop rbx
    ret

# ag_ok(id, body, len): "ok ID LEN\n" and the body
ag_ok:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ag_delay_reply
    lea rdi, [rip + .Lok]
    mov rsi, rbx
    mov rdx, r13
    call ag_push_head
    test r13, r13
    jz 1f
    lea rdi, [rip + ag_wq]
    mov rsi, r12
    mov rdx, r13
    call sb_push
1:  pop r13
    pop r12
    pop rbx
    ret

# ag_error(id, -errno): "error ID ERRNO\n"
ag_error:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    neg r12
    call ag_delay_reply
    lea rdi, [rip + .Lerror]
    mov rsi, rbx
    mov rdx, r12
    call ag_push_head
    add rsp, 8
    pop r12
    pop rbx
    ret

# ag_reply(id, result): result < 0 is an error, else ok with ag_tmp's bytes
ag_reply:
    test rsi, rsi
    js ag_error
    mov rsi, [rip + ag_tmp + SB_ptr]
    mov rdx, [rip + ag_tmp + SB_len]
    jmp ag_ok

# ag_delay_reply(): RHUN_REMOTE_DELAY_MS, the latency tests' slow network
ag_delay_reply:
    mov rax, [rip + ag_delay]
    test rax, rax
    jz 1f
    sub rsp, 24
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [rsp], rax
    imul rdx, rdx, 1000000
    mov [rsp + 8], rdx
    mov rdi, rsp
    xor esi, esi
    mov eax, 35                 # nanosleep
    syscall
    add rsp, 24
1:  ret

# ---------------- the stream from the client ----------------

# ag_read_client(): read what came and handle every complete message
ag_read_client:
    PROLOGUE
1:  lea rdi, [rip + ag_rbuf]
    mov esi, 262144
    call sb_reserve
    mov rsi, rax
    xor edi, edi
    mov edx, 262144
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 2f
    test rax, rax
    jle 8f
    add [rip + ag_rbuf + SB_len], rax
    cmp rax, 262144
    je 1b
2:  # the messages
    xor r12d, r12d              # offset
3:  mov rdi, [rip + ag_rbuf + SB_ptr]
    add rdi, r12
    mov rsi, [rip + ag_rbuf + SB_len]
    sub rsi, r12
    jz 6f
    mov r13, rdi
    mov r14, rsi
    call mux_line
    test rax, rax
    jz 6f                       # not a whole line yet
    js 8f                       # a line too long: not the protocol
    mov r15, rax                # header with its LF
    mov rdi, r13
    lea rsi, [rax - 1]
    lea rdx, [rip + ag_toks]
    call mux_split
    mov [rip + ag_ntok], rax
    test rax, rax
    jz 5f
    call ag_body_len            # -> rax body bytes, -1 bad
    test rax, rax
    js 8f
    cmp rax, AG_REQ_MAX
    ja 8f
    lea rcx, [r15 + rax]
    cmp rcx, r14
    ja 6f                       # its body has not all come
    lea rdi, [r13 + r15]        # body
    mov rsi, rax
    push rcx
    push rcx
    call ag_message
    pop rcx
    pop rcx
    add r12, rcx
    jmp 3b
5:  add r12, r15                # an empty line
    jmp 3b
6:  # drop what was handled
    test r12, r12
    jz 9f
    mov rdi, [rip + ag_rbuf + SB_ptr]
    lea rsi, [rdi + r12]
    mov rdx, [rip + ag_rbuf + SB_len]
    sub rdx, r12
    mov [rip + ag_rbuf + SB_len], rdx
    call memmove
    jmp 9f
8:  mov dword ptr [rip + ag_quit], 1
9:  EPILOGUE

# ag_tok(i) -> rax ptr, rdx len of token i
ag_tok:
    mov eax, edi
    shl eax, 4
    lea rcx, [rip + ag_toks]
    mov rdx, [rcx + rax + 8]
    mov rax, [rcx + rax]
    ret

# ag_num(i) -> rax token i as a number
ag_num:
    call ag_tok
    mov rdi, rax
    mov rsi, rdx
    jmp parse_u64

# ag_body_len() -> bytes of body after the header in ag_toks, -1 for a malformed header
#   d CH LEN | e CH | w CH N | ID VERB ... LEN
ag_body_len:
    push rbx
    xor edi, edi
    call ag_tok
    cmp rdx, 1
    jne 2f
    mov bl, [rax]
    cmp bl, 'd'
    jne 1f
    cmp qword ptr [rip + ag_ntok], 3
    jne 8f
    mov edi, 2
    call ag_num
    pop rbx
    ret
1:  cmp bl, 'e'
    je 3f
    cmp bl, 'w'
    je 3f
2:  # a request: its last field is the body's length
    cmp qword ptr [rip + ag_ntok], 3
    jb 8f
    mov rdi, [rip + ag_ntok]
    dec edi
    call ag_num
    pop rbx
    ret
3:  xor eax, eax
    pop rbx
    ret
8:  mov rax, -1
    pop rbx
    ret

# ag_message(body, len): one message from the client, its header in ag_toks
ag_message:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor edi, edi
    call ag_tok
    cmp rdx, 1
    jne .Lam_request
    movzx ebx, byte ptr [rax]
    cmp ebx, 'd'
    je 1f
    cmp ebx, 'e'
    je 1f
    cmp ebx, 'w'
    jne .Lam_request
1:  mov edi, 1
    call ag_num
    cmp rax, AG_MAXCH
    jae 9f
    mov r14d, eax               # channel
    mov edi, eax
    call ag_chan
    mov r15, rax
    cmp ebx, 'd'
    je .Lam_data
    cmp ebx, 'e'
    je .Lam_eof
    cmp ebx, 'w'
    je .Lam_credit
    jmp 9f
.Lam_data:
    # input for the program: queued, written as it takes it
    mov eax, [r15 + AC_mode]
    cmp eax, AM_PIPE
    je 1f
    cmp eax, AM_PTY
    jne 9f
1:  test dword ptr [r15 + AC_flags], ACF_ICLOSED
    jz 2f
    # nobody reads it: the credit comes back at once
    lea rdi, [rip + .Lw]
    mov esi, r14d
    mov rdx, r13
    call ag_push_head
    jmp 9f
2:  lea rdi, [r15 + AC_ibuf]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov edi, r14d
    call ag_write_program
    jmp 9f
.Lam_eof:
    or dword ptr [r15 + AC_flags], ACF_IEOF
    mov edi, r14d
    call ag_write_program
    jmp 9f
.Lam_credit:
    mov edi, 2
    call ag_num
    add [r15 + AC_credit], rax
    jmp 9f
.Lam_request:
    mov rdi, r12
    mov rsi, r13
    call ag_request
9:  EPILOGUE

# ---------------- programs ----------------

# ag_write_program(ch): the queued input into the program, credit back to the client
ag_write_program:
    PROLOGUE
    mov r12d, edi
    call ag_chan
    mov rbx, rax
    test dword ptr [rbx + AC_flags], ACF_ICLOSED
    jnz 8f
    mov edi, [rbx + AC_in]
    test edi, edi
    js 8f
1:  mov rdx, [rbx + AC_ibuf + SB_len]
    mov rsi, [rbx + AC_ioff]
    sub rdx, rsi
    jz 5f
    add rsi, [rbx + AC_ibuf + SB_ptr]
    mov edi, [rbx + AC_in]
    SYS SYS_write
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 6f
    test rax, rax
    jle 4f
    add [rbx + AC_ioff], rax
    add [rbx + AC_grant], rax
    jmp 1b
4:  # the program closed its input: what it did not take counts as taken
    mov rax, [rbx + AC_ibuf + SB_len]
    sub rax, [rbx + AC_ioff]
    add [rbx + AC_grant], rax
    call ag_close_input
    jmp 6f
5:  mov qword ptr [rbx + AC_ioff], 0
    mov qword ptr [rbx + AC_ibuf + SB_len], 0
    test dword ptr [rbx + AC_flags], ACF_IEOF
    jz 6f
    call ag_close_input
6:  # credit back what was taken, a block at a time or once all is written
    mov rax, [rbx + AC_grant]
    test rax, rax
    jz 8f
    cmp rax, AG_GRANT
    jae 7f
    mov rcx, [rbx + AC_ibuf + SB_len]
    cmp rcx, [rbx + AC_ioff]
    jne 8f
7:  lea rdi, [rip + .Lw]
    mov esi, r12d
    mov rdx, [rbx + AC_grant]
    call ag_push_head
    mov qword ptr [rbx + AC_grant], 0
8:  EPILOGUE

# ag_close_input() (rbx AC*): the program's input ends. For a pty the client closed the terminal:
#   the master closes, which hangs up its session as a local terminal's close does
ag_close_input:
    or dword ptr [rbx + AC_flags], ACF_ICLOSED
    mov qword ptr [rbx + AC_ioff], 0
    mov qword ptr [rbx + AC_ibuf + SB_len], 0
    mov edi, [rbx + AC_in]
    test edi, edi
    js 1f
    SYS SYS_close
    cmp dword ptr [rbx + AC_mode], AM_PTY
    jne 1f
    mov dword ptr [rbx + AC_in], -1
    mov dword ptr [rbx + AC_out], -1
    or dword ptr [rbx + AC_flags], ACF_OEOF
    push rbx
    mov rax, rbx
    lea rcx, [rip + ag_ch]
    sub rax, rcx
    xor edx, edx
    mov ecx, AC_SIZE
    div rcx
    mov edi, eax
    call ag_maybe_free
    pop rbx
1:  ret

# ag_read_program(ch): output of the program, as far as the client's credit goes
ag_read_program:
    PROLOGUE
    mov r12d, edi
    call ag_chan
    mov rbx, rax
    mov r13, [rbx + AC_credit]
    cmp r13, AG_READ
    jbe 1f
    mov r13d, AG_READ
1:  test r13, r13
    jle 9f
    # header room first: "d CH LEN\n" is at most 32 bytes
    lea rdi, [rip + ag_wq]
    lea rsi, [r13 + 32]
    call sb_reserve
    lea r14, [rax + 32]         # read into place after the header's room
2:  mov edi, [rbx + AC_out]
    mov rsi, r14
    mov rdx, r13
    SYS SYS_read
    cmp rax, -EINTR
    je 2b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 5f                      # end (a pty answers EIO once its last program closed it)
    mov r15, rax
    sub [rbx + AC_credit], rax
    # write the header, then move the data next to it
    lea rdi, [rip + .Ld]
    mov esi, r12d
    mov rdx, r15
    call ag_push_head
    mov rdi, [rip + ag_wq + SB_ptr]
    add rdi, [rip + ag_wq + SB_len]
    mov rsi, r14
    mov rdx, r15
    call memmove
    add [rip + ag_wq + SB_len], r15
    jmp 9f
5:  or dword ptr [rbx + AC_flags], ACF_OEOF
    mov edi, r12d
    call ag_push_eof
    mov edi, r12d
    call ag_maybe_free
9:  EPILOGUE

# ag_request(body, len): ID VERB ... LEN
ag_request:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor edi, edi
    call ag_num
    mov r14, rax                # id
    mov edi, 1
    call ag_tok
    mov rbx, rax
    mov r15, rdx
    lea rdi, [rip + ag_tmp]
    call sb_clear
    # the verb table: name, handler(id, body, len)
    lea rcx, [rip + ag_verbs]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 8f
    push rcx
    push rcx
    mov rdi, rbx
    mov rsi, r15
    call str_eq_cstr
    pop rcx
    pop rcx
    test eax, eax
    jnz 2f
    add rcx, 16
    jmp 1b
2:  mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call [rcx + 8]
    jmp 9f
8:  mov rdi, r14
    mov rsi, -38                # ENOSYS: a verb this agent does not know
    call ag_error
9:  EPILOGUE

# ag_cstr_list(ptr, end, argv, max) -> rax entries, rdx past the empty string that ends them
#   NUL-terminated strings from ptr; an empty one (or the end) ends the list; argv gets a 0 after them
ag_cstr_list:
    push rbx
    xor eax, eax
1:  cmp rdi, rsi
    jae 4f
    cmp byte ptr [rdi], 0
    je 3f
    cmp rax, rcx
    jae 2f
    mov [rdx + rax*8], rdi
    inc rax
2:  cmp rdi, rsi
    jae 4f
    mov bl, [rdi]
    inc rdi
    test bl, bl
    jnz 2b
    jmp 1b
3:  inc rdi
4:  mov qword ptr [rdx + rax*8], 0
    mov rdx, rdi
    pop rbx
    ret

# spawn CH MODE ERRCH COLS ROWS LEN: CWD NUL, then ARGV entries ending with an empty one, then ENV
#   entries set on top of the login environment. MODE 0 pipe, 1 pty. ERRCH: 0 sends the error output
#   to /dev/null, CH merges it with the output, another channel carries it. An empty ARGV in a pty
#   is the user's shell. -> ok with the pid
ag_spawn:
    PROLOGUE 96
    mov [rsp], rdi              # id
    lea rax, [rsi + rdx]
    mov [rsp + 8], rax          # body end
    mov r12, rsi
    mov edi, 2
    call ag_num
    mov r13d, eax               # channel
    mov edi, 3
    call ag_num
    mov [rsp + 16], eax         # mode
    mov edi, 4
    call ag_num
    mov [rsp + 20], eax         # error channel
    mov edi, 5
    call ag_num
    mov [rsp + 24], eax         # cols
    mov edi, 6
    call ag_num
    mov [rsp + 28], eax         # rows
    mov rax, -22
    cmp r13d, AG_MAXCH
    jae .Las_err
    test r13d, r13d
    jz .Las_err
    mov edi, r13d
    call ag_chan
    mov rbx, rax
    mov rax, -16                # EBUSY: the channel is in use
    cmp dword ptr [rbx + AC_mode], AM_FREE
    jne .Las_err
    mov eax, [rsp + 20]
    cmp eax, r13d
    je 1f
    test eax, eax
    jz 1f
    cmp eax, AG_MAXCH
    jae .Las_inval
    mov edi, eax
    call ag_chan
    mov rcx, rax
    mov rax, -16
    cmp dword ptr [rcx + AC_mode], AM_FREE
    jne .Las_err
1:  # cwd
    mov [rsp + 32], r12
    mov rdi, r12
    mov rsi, [rsp + 8]
2:  cmp rdi, rsi
    jae .Las_inval
    cmp byte ptr [rdi], 0
    je 3f
    inc rdi
    jmp 2b
3:  inc rdi
    mov rsi, [rsp + 8]
    lea rdx, [rip + ag_argv]
    mov ecx, 200
    call ag_cstr_list
    mov [rsp + 40], rax         # argc
    mov [rsp + 48], rdx         # env entries start
    # the user's shell for an empty pty command
    test rax, rax
    jnz 4f
    cmp dword ptr [rsp + 16], 1
    jne .Las_inval
    lea rdi, [rip + .Lshell]
    call getenv
    test rax, rax
    jz 31f
    cmp byte ptr [rax], '/'
    je 32f
31: lea rax, [rip + .Lbin_sh]
32: lea rcx, [rip + ag_argv]
    mov [rcx], rax
    mov qword ptr [rcx + 8], 0
4:  # @self is this agent's own binary (the agents panel's index worker); a name without a slash is
    # looked up in the login PATH
    lea rax, [rip + ag_argv]
    mov rdi, [rax]
    lea rsi, [rip + .Lat_self]
    call strcmp_eq
    test eax, eax
    jz 41f
    lea rdi, [rip + .Lself]
    lea rsi, [rip + ag_path2]
    mov edx, 4095
    SYS SYS_readlink
    test rax, rax
    jle .Las_noent
    lea rdi, [rip + ag_path2]
    mov byte ptr [rdi + rax], 0
    call mem_dup_cstr
    jmp 42f
41: lea rax, [rip + ag_argv]
    mov rdi, [rax]
    call proc_which
42:
    test rax, rax
    jz .Las_noent
    mov [rsp + 56], rax         # path (freed below)
    # argv for the exec: argv[0] is the path to run
    lea rcx, [rip + ag_argv]
    mov rdx, [rcx]
    mov [rsp + 88], rdx         # the name as given
    mov [rcx], rax
    # the environment: the login one with the entries given set
    mov rdi, [rsp + 48]
    mov rsi, [rsp + 8]
    lea rdx, [rip + ag_argv + 202 * 8]
    mov ecx, 50
    call ag_cstr_list
    lea rdi, [rip + ag_argv + 202 * 8]
    call env_make
    mov [rsp + 64], rax         # envp (freed below)
    mov rax, [rsp + 32]
    cmp byte ptr [rax], 0
    jne 5f
    mov qword ptr [rsp + 32], 0
5:  cmp dword ptr [rsp + 16], 1
    je .Las_pty
    # pipe: the program's input and output
    lea rdi, [rsp + 72]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Las_free
    lea rdi, [rsp + 80]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Las_close1
    # its errors: /dev/null, merged, or a pipe of their own
    mov r14d, -1                # our end of an error pipe
    mov r15d, [rsp + 84]        # the program's error output
    mov eax, [rsp + 20]
    cmp eax, r13d
    je 7f
    test eax, eax
    jnz 6f
    lea rdi, [rip + .Ldevnull]
    mov esi, O_WRONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Las_close2
    mov r15d, eax
    jmp 7f
6:  lea rdi, [rsp + 88]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js .Las_close2
    mov r14d, [rsp + 88]
    mov r15d, [rsp + 92]
7:  lea rdi, [rip + ag_argv]
    mov rsi, [rsp + 64]
    mov rdx, [rsp + 32]
    mov ecx, [rsp + 72]
    mov r8d, [rsp + 84]
    mov r9d, r15d
    push 2                      # a session of its own (kill CH SIG 1 reaches its group)
    push 2
    call proc_spawn
    add rsp, 16
    mov [rsp + 88], rax
    mov edi, [rsp + 72]
    SYS SYS_close
    mov edi, [rsp + 84]
    SYS SYS_close
    cmp r15d, [rsp + 84]
    je 8f
    mov edi, r15d
    SYS SYS_close
8:  mov rax, [rsp + 88]
    test rax, rax
    jle .Las_fail_pipe
    mov [rbx + AC_pid], eax
    mov eax, [rsp + 76]
    mov [rbx + AC_in], eax
    mov eax, [rsp + 80]
    mov [rbx + AC_out], eax
    mov dword ptr [rbx + AC_mode], AM_PIPE
    mov edi, [rbx + AC_in]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    mov edi, [rbx + AC_out]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    test r14d, r14d
    js .Las_ok
    mov edi, [rsp + 20]
    call ag_chan
    mov dword ptr [rax + AC_mode], AM_ERR
    mov [rax + AC_out], r14d
    mov qword ptr [rax + AC_credit], AG_WINDOW
    mov edi, r14d
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    jmp .Las_ok
.Las_fail_pipe:
    mov edi, [rsp + 76]
    SYS SYS_close
    mov edi, [rsp + 80]
    SYS SYS_close
    test r14d, r14d
    js .Las_spawnerr
    mov edi, r14d
    SYS SYS_close
    jmp .Las_spawnerr
.Las_pty:
    mov edi, [rsp + 24]
    mov esi, [rsp + 28]
    call pty_open
    test eax, eax
    js .Las_free_eio
    mov r14d, eax               # master
    mov r15d, edx               # slave
    lea rdi, [rip + ag_argv]
    mov rsi, [rsp + 64]
    mov rdx, [rsp + 32]
    mov ecx, r15d
    mov r8d, r15d
    mov r9d, r15d
    push 1
    push 1
    call proc_spawn
    add rsp, 16
    mov [rsp + 88], rax
    mov edi, r15d
    SYS SYS_close
    mov rax, [rsp + 88]
    test rax, rax
    jg 9f
    mov edi, r14d
    SYS SYS_close
    jmp .Las_spawnerr
9:  mov [rbx + AC_pid], eax
    mov [rbx + AC_in], r14d
    mov [rbx + AC_out], r14d
    mov dword ptr [rbx + AC_mode], AM_PTY
.Las_ok:
    mov dword ptr [rbx + AC_flags], 0
    mov qword ptr [rbx + AC_credit], AG_WINDOW
    mov qword ptr [rbx + AC_ioff], 0
    mov qword ptr [rbx + AC_grant], 0
    lea rdi, [rip + ag_tmp]
    mov esi, [rbx + AC_pid]
    call sb_push_u64
    mov rdi, [rsp + 56]
    call mem_free
    mov rdi, [rsp + 64]
    call mem_free
    mov rdi, [rsp]
    xor esi, esi
    call ag_reply
    EPILOGUE
.Las_close2:
    mov edi, [rsp + 80]
    SYS SYS_close
    mov edi, [rsp + 84]
    SYS SYS_close
.Las_close1:
    mov edi, [rsp + 72]
    SYS SYS_close
    mov edi, [rsp + 76]
    SYS SYS_close
    mov rax, -24                # EMFILE
    jmp .Las_free_err
.Las_free_eio:
    mov rax, -5
    jmp .Las_free_err
.Las_spawnerr:
    mov rax, [rsp + 88]
    test rax, rax
    js .Las_free_err
.Las_free:
    mov rax, -5
.Las_free_err:
    mov [rsp + 88], rax
    mov rdi, [rsp + 56]
    call mem_free
    mov rdi, [rsp + 64]
    call mem_free
    mov rax, [rsp + 88]
    jmp .Las_err
.Las_noent:
    mov rax, -2
    jmp .Las_err
.Las_inval:
    mov rax, -22
.Las_err:
    mov rdi, [rsp]
    mov rsi, rax
    call ag_error
    EPILOGUE

# kill CH SIG GROUP 0: the program on CH (GROUP 1: its process group, as kill(-pid))
ag_kill:
    PROLOGUE
    mov r12, rdi
    mov edi, 2
    call ag_num
    cmp rax, AG_MAXCH
    jae 8f
    mov edi, eax
    call ag_chan
    mov rbx, rax
    mov edi, [rbx + AC_pid]
    test edi, edi
    jle 8f
    test dword ptr [rbx + AC_flags], ACF_EXITED
    jnz 7f                      # gone already (not reaped by anyone else: the pid is not reused)
    mov edi, 4
    call ag_num
    mov r13d, eax
    mov edi, 3
    call ag_num
    mov esi, eax
    mov edi, [rbx + AC_pid]
    test r13d, r13d
    jz 1f
    neg edi
1:  SYS SYS_kill
    mov rsi, rax
    mov rdi, r12
    call ag_reply
    EPILOGUE
7:  mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -3                 # ESRCH
    call ag_error
    EPILOGUE

# resize CH COLS ROWS 0: the pty's size
ag_resize:
    PROLOGUE
    mov r12, rdi
    mov edi, 2
    call ag_num
    cmp rax, AG_MAXCH
    jae 8f
    mov edi, eax
    call ag_chan
    mov rbx, rax
    cmp dword ptr [rbx + AC_mode], AM_PTY
    jne 8f
    mov edi, 3
    call ag_num
    mov r13d, eax
    mov edi, 4
    call ag_num
    mov edi, [rbx + AC_out]
    mov esi, r13d
    mov edx, eax
    xor ecx, ecx
    xor r8d, r8d
    call pty_resize
    mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -22
    call ag_error
    EPILOGUE

# close CH 0: the client forgets the channel; its descriptors close (a pty's program gets SIGHUP)
ag_close:
    PROLOGUE
    mov r12, rdi
    mov edi, 2
    call ag_num
    cmp rax, AG_MAXCH
    jae 8f
    test eax, eax
    jz 8f
    mov edi, eax
    call ag_chan
    mov rdi, rax
    call ag_free
8:  mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE

# cwd CH 0 -> the program's current folder (a terminal's links)
ag_cwd:
    PROLOGUE
    mov r12, rdi
    mov edi, 2
    call ag_num
    cmp rax, AG_MAXCH
    jae 8f
    mov edi, eax
    call ag_chan
    mov edi, [rax + AC_pid]
    test edi, edi
    jle 8f
    lea rsi, [rip + ag_path]
    mov edx, 4096
    call proc_cwd
    test rax, rax
    jle 8f
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_path]
    mov rdx, rax
    call sb_push
    mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -3
    call ag_error
    EPILOGUE

# info 0 -> "home=PATH\nshell=PATH\nuser=NAME\nhost=NAME\n"
ag_info:
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + .Linfo_keys]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 3f
    call getenv
    test rax, rax
    jz 2f
    mov r13, rax
    lea rdi, [rip + ag_tmp]
    mov rsi, [rbx + 8]
    call sb_push_cstr
    lea rdi, [rip + ag_tmp]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + ag_tmp]
    mov esi, 10
    call sb_push_byte
2:  add rbx, 16
    jmp 1b
3:  # the host's name
    sub rsp, 400
    mov rdi, rsp
    SYS SYS_uname
    test rax, rax
    js 4f
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + .Lk_host]
    call sb_push_cstr
    lea rdi, [rip + ag_tmp]
    lea rsi, [rsp + 65]         # utsname.nodename
    call sb_push_cstr
    lea rdi, [rip + ag_tmp]
    mov esi, 10
    call sb_push_byte
4:  add rsp, 400
    mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE

# quit 0: the agent exits (Disconnect)
ag_quitreq:
    sub rsp, 8
    xor esi, esi
    call ag_reply
    mov dword ptr [rip + ag_quit], 1
    call ag_flush
    add rsp, 8
    ret

# ---------------- file system ----------------

# ag_path_arg(ptr, len) -> rax ag_path (NUL-terminated), or 0 when too long or holding a NUL
ag_path_arg:
    test rsi, rsi
    jz 8f
    cmp rsi, 4095
    jae 8f
    push rsi
    push rdi
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + ag_path]
    call memcpy
    pop rdi
    pop rsi
    lea rax, [rip + ag_path]
    mov byte ptr [rax + rsi], 0
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    cmp byte ptr [rax + rcx], 0
    je 8f
    inc rcx
    jmp 1b
8:  xor eax, eax
9:  ret

# stat LEN / lstat LEN + path -> the 144-byte Linux struct stat
ag_stat_common:
    PROLOGUE
    mov r12, rdi
    mov ebx, ecx
    mov rdi, rsi
    mov rsi, rdx
    call ag_path_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    lea rsi, [rip + ag_statbuf]
    mov eax, ebx
    syscall
    test rax, rax
    js 7f
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_statbuf]
    mov edx, 144
    call sb_push
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36                # ENAMETOOLONG
    call ag_error
    EPILOGUE
ag_stat:
    mov ecx, 4                  # stat
    jmp ag_stat_common
ag_lstat:
    mov ecx, SYS_lstat
    jmp ag_stat_common

# realpath LEN + path -> the resolved path
ag_realpath:
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call ag_path_arg
    test rax, rax
    jz 8f
    # /proc/self/fd/N of an O_PATH open is the kernel's resolution
    mov rdi, rax
    mov esi, O_PATH | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 7f
    mov ebx, eax
    lea rdi, [rip + ag_path2]
    lea rsi, [rip + .Lproc_fd]
    call cstr_copy
    mov rdi, rax
    mov esi, ebx
    call fmt_u64
    mov byte ptr [rdi], 0
    lea rdi, [rip + ag_path2]
    lea rsi, [rip + ag_path]
    mov edx, 4095
    SYS SYS_readlink
    mov r13, rax
    mov edi, ebx
    SYS SYS_close
    mov rax, r13
    test rax, rax
    js 7f
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_path]
    mov rdx, r13
    call sb_push
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# readlink LEN + path -> the link's text
ag_readlink:
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call ag_path_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    lea rsi, [rip + ag_path2]
    mov edx, 4095
    SYS SYS_readlink
    test rax, rax
    js 7f
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_path2]
    mov rdx, rax
    call sb_push
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# read OFFSET MAX LEN + path -> at most MAX bytes (4 MB) from OFFSET; fewer at the end
ag_read:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov r15, rax                # offset
    mov edi, 3
    call ag_num
    mov rbx, rax                # max
    cmp rbx, 4194304
    jbe 1f
    mov ebx, 4194304
1:  mov rdi, r13
    mov rsi, r14
    call ag_path_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 7f
    mov r13d, eax
    lea rdi, [rip + ag_tmp]
    mov rsi, rbx
    call sb_reserve
    mov r14, rax
    xor ecx, ecx                # read so far
2:  cmp rcx, rbx
    jae 4f
    push rcx
    push rcx
    mov edi, r13d
    lea rsi, [r14 + rcx]
    mov rdx, rbx
    sub rdx, rcx
    lea r10, [r15 + rcx]
    SYS SYS_pread
    pop rcx
    pop rcx
    cmp rax, -EINTR
    je 2b
    test rax, rax
    js 3f
    jz 4f
    add rcx, rax
    jmp 2b
3:  mov rbx, rax
    mov edi, r13d
    SYS SYS_close
    mov rax, rbx
    jmp 7f
4:  mov [rip + ag_tmp + SB_len], rcx
    mov edi, r13d
    SYS SYS_close
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# write FLAGS MODE PLEN LEN + path + data: the file's new contents. FLAGS: 1 replace an existing file
#   through a temporary one in its folder (its mode kept), 2 create only (EEXIST when it is there),
#   4 append, 8 create or truncate (a write in parts: 8, then 4s). MODE: a new file's mode (octal)
ag_write:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov ebx, eax                # flags
    mov edi, 3
    call ag_tok
    mov rdi, rax
    mov rsi, rdx
    call parse_octal
    mov [rsp], eax              # mode
    mov edi, 4
    call ag_num
    mov r15, rax                # path length
    cmp r15, r14
    ja 8f
    mov rdi, r13
    mov rsi, r15
    call ag_path_arg
    test rax, rax
    jz 8f
    add r13, r15                # the data
    sub r14, r15
    test ebx, 4
    jnz .Law_append
    test ebx, 2
    jnz .Law_new
    test ebx, 8
    jnz .Law_trunc
    # the target's own file through its links, then a temporary file renamed over it
    lea rdi, [rip + ag_path]
    mov rsi, r13
    mov rdx, r14
    call file_write_all
    jmp 7f
.Law_new:
    lea rdi, [rip + ag_path]
    mov esi, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC
    mov edx, [rsp]
    SYS SYS_open
    jmp 5f
.Law_trunc:
    lea rdi, [rip + ag_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, [rsp]
    SYS SYS_open
    jmp 5f
.Law_append:
    lea rdi, [rip + ag_path]
    mov esi, O_WRONLY | O_APPEND | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
5:  test rax, rax
    js 7f
    mov ebx, eax
    mov edi, ebx
    mov rsi, r13
    mov rdx, r14
    call write_all
    mov r13, rax
    mov edi, ebx
    SYS SYS_close
    mov rax, r13
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -22
    call ag_error
    EPILOGUE

# parse_octal(ptr, len) -> eax
parse_octal:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx edx, byte ptr [rdi + rcx]
    sub edx, '0'
    cmp edx, 7
    ja 2f
    shl eax, 3
    or eax, edx
    inc rcx
    jmp 1b
2:  ret

# list LEN + path -> "T NAME\0" for each entry but . and .., T one of d f o, or for a symlink L when
#   it leads to a folder and l otherwise (dir_each follows links)
ag_list:
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call ag_path_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 7f
    mov ebx, eax
1:  mov edi, ebx
    lea rsi, [rip + ag_path2]
    mov edx, 4096
    SYS SYS_getdents64
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jle 6f
    mov r13, rax
    xor r14d, r14d
2:  cmp r14, r13
    jae 1b
    lea r15, [rip + ag_path2]
    add r15, r14
    movzx eax, word ptr [r15 + 16]   # d_reclen
    add r14, rax
    lea rdi, [r15 + 19]             # d_name
    cmp byte ptr [rdi], '.'
    jne 3f
    cmp byte ptr [rdi + 1], 0
    je 2b
    cmp byte ptr [rdi + 1], '.'
    jne 3f
    cmp byte ptr [rdi + 2], 0
    je 2b
3:  movzx eax, byte ptr [r15 + 18]   # d_type
    mov esi, 'o'
    cmp eax, 4
    jne 4f
    mov esi, 'd'
4:  cmp eax, 8
    jne 41f
    mov esi, 'f'
41: cmp eax, 10
    jne 42f
    push rsi
    push rsi
    lea rdi, [r15 + 19]
    call ag_link_kind
    pop rsi
    pop rsi
    mov esi, eax
42: test eax, eax                    # DT_UNKNOWN: ask
    jnz 43f
    push rsi
    push rsi
    lea rdi, [r15 + 19]
    call ag_type_at
    pop rsi
    pop rsi
    mov esi, eax
43: lea rdi, [rip + ag_tmp]
    call sb_push_byte
    lea rdi, [rip + ag_tmp]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ag_tmp]
    lea rsi, [r15 + 19]
    call sb_push_cstr
    lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    jmp 2b
6:  push rax
    push rax
    mov edi, ebx
    SYS SYS_close
    pop rax
    pop rax
    test rax, rax
    js 7f
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# ag_link_kind(name) -> 'L' when the symlink name in the folder ag_path leads to a folder, else 'l'
ag_link_kind:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + ag_path]
    mov rsi, rbx
    call path_join_tmp
    mov rdi, rax
    call file_is_dir
    mov ecx, 'l'
    test eax, eax
    jz 1f
    mov ecx, 'L'
1:  mov eax, ecx
    pop rbx
    ret

# ag_type_at(name) -> 'd' 'f' 'L' 'l' or 'o' for the entry name in the folder ag_path (lstat)
ag_type_at:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + ag_path]
    mov rsi, rbx
    call path_join_tmp
    mov rdi, rax
    lea rsi, [rip + ag_statbuf]
    SYS SYS_lstat
    mov ecx, 'o'
    test rax, rax
    js 9f
    mov eax, [rip + ag_statbuf + 24]
    and eax, 0xf000
    cmp eax, 0x4000
    jne 1f
    mov ecx, 'd'
1:  cmp eax, 0x8000
    jne 2f
    mov ecx, 'f'
2:  cmp eax, 0xa000
    jne 9f
    mov rdi, rbx
    pop rbx
    jmp ag_link_kind
9:  mov eax, ecx
    pop rbx
    ret

# mkdir PARENTS LEN + path: PARENTS 1 makes the folders on the way too
ag_mkdir:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov ebx, eax
    mov rdi, r13
    mov rsi, r14
    call ag_path_arg
    test rax, rax
    jz 8f
    test ebx, ebx
    jz 1f
    mov rdi, rax
    call mkdir_p
1:  lea rdi, [rip + ag_path]
    mov esi, 0755
    SYS SYS_mkdir
    test ebx, ebx
    jz 7f
    cmp rax, -17                # EEXIST is no failure with parents
    jne 7f
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# rename FLAGS PLEN LEN + from + to: FLAGS 1 refuses an existing destination
ag_rename:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov ebx, eax
    mov edi, 3
    call ag_num
    mov r15, rax
    cmp r15, r14
    jae 8f
    mov rdi, r13
    mov rsi, r15
    call ag_path_arg
    test rax, rax
    jz 8f
    lea rdi, [rip + ag_path2]
    lea rsi, [rip + ag_path]
    call cstr_copy
    lea rdi, [r13 + r15]
    mov rsi, r14
    sub rsi, r15
    call ag_path_arg
    test rax, rax
    jz 8f
    test ebx, 1
    jnz 1f
    lea rdi, [rip + ag_path2]
    lea rsi, [rip + ag_path]
    SYS SYS_rename
    jmp 7f
1:  mov edi, -100               # AT_FDCWD
    lea rsi, [rip + ag_path2]
    mov edx, -100
    lea r10, [rip + ag_path]
    mov r8d, 1                  # RENAME_NOREPLACE
    SYS SYS_renameat2
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -22
    call ag_error
    EPILOGUE

# remove RECURSIVE LEN + path: a file, an empty folder, or with RECURSIVE 1 a whole tree
ag_remove:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov ebx, eax
    mov rdi, r13
    mov rsi, r14
    call ag_path_arg
    test rax, rax
    jz 8f
    test ebx, ebx
    jz 1f
    mov rdi, rax
    call file_remove_tree
    jmp 7f
1:  mov rdi, rax
    SYS SYS_unlink
    cmp rax, -21                # EISDIR
    je 2f
    cmp rax, -1                 # EPERM: Linux's answer to unlink of a folder
    jne 7f
2:  lea rdi, [rip + ag_path]
    mov eax, 84                 # rmdir
    syscall
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# watch MASK LEN + path -> the watch descriptor; events come as v WD MASK LEN + name
ag_watch:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp dword ptr [rip + ag_inotify], 0
    jge 1f
    mov edi, IN_NONBLOCK | IN_CLOEXEC
    SYS SYS_inotify_init1
    test rax, rax
    js 7f
    mov [rip + ag_inotify], eax
1:  mov edi, 2
    call ag_num
    mov ebx, eax
    mov rdi, r13
    mov rsi, r14
    call ag_path_arg
    test rax, rax
    jz 8f
    mov edi, [rip + ag_inotify]
    mov rsi, rax
    mov edx, ebx
    SYS SYS_inotify_add_watch
    test rax, rax
    js 7f
    lea rdi, [rip + ag_tmp]
    mov rsi, rax
    call sb_push_u64
    xor eax, eax
7:  mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# unwatch WD 0
ag_unwatch:
    PROLOGUE
    mov r12, rdi
    mov edi, 2
    call ag_num
    mov esi, eax
    mov edi, [rip + ag_inotify]
    test edi, edi
    js 1f
    SYS SYS_inotify_rm_watch
1:  mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE

# ag_read_inotify(): v WD MASK LEN + name for each event
ag_read_inotify:
    PROLOGUE
1:  mov edi, [rip + ag_inotify]
    lea rsi, [rip + ag_path2]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jle 9f
    mov r12, rax
    xor r13d, r13d
2:  cmp r13, r12
    jae 1b
    lea rbx, [rip + ag_path2]
    add rbx, r13
    mov r14d, [rbx + 12]        # len
    lea r13, [r13 + r14 + 16]
    # the name without its NUL padding
    lea rdi, [rbx + 16]
    xor r15d, r15d
3:  cmp r15, r14
    jae 4f
    cmp byte ptr [rdi + r15], 0
    je 4f
    inc r15
    jmp 3b
4:  lea rdi, [rip + ag_wq]
    lea rsi, [rip + .Lv]
    call sb_push_cstr
    lea rdi, [rip + ag_wq]
    mov esi, [rbx]
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ag_wq]
    mov esi, [rbx + 4]
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ag_wq]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + ag_wq]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + ag_wq]
    lea rsi, [rbx + 16]
    mov rdx, r15
    call sb_push
    jmp 2b
9:  EPILOGUE

# access MODE LEN + path -> ok or the error of access(2) (W_OK 2: may it be written)
ag_access:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov ebx, eax
    mov rdi, r13
    mov rsi, r14
    call ag_path_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    mov esi, ebx
    SYS SYS_access
    mov rdi, r12
    mov rsi, rax
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -36
    call ag_error
    EPILOGUE

# stats LEN + paths, each with a NUL -> for each path in order: "o" and its 144-byte struct stat, or
#   "e" and its errno as 4 bytes (the agents panel polls its sessions in one request)
ag_stats:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea r14, [rsi + rdx]
1:  cmp r13, r14
    jae 8f
    mov rdi, r13
    call strlen
    mov r15, rax
    mov rdi, r13
    mov rsi, rax
    call ag_path_arg
    lea r13, [r13 + r15 + 1]
    mov rbx, -36
    test rax, rax
    jz 2f
    mov rdi, rax
    lea rsi, [rip + ag_statbuf]
    mov eax, 4
    syscall
    mov rbx, rax
    test rax, rax
    js 2f
    lea rdi, [rip + ag_tmp]
    mov esi, 'o'
    call sb_push_byte
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_statbuf]
    mov edx, 144
    call sb_push
    jmp 1b
2:  lea rdi, [rip + ag_tmp]
    mov esi, 'e'
    call sb_push_byte
    neg rbx
    mov [rip + ag_statbuf], ebx
    lea rdi, [rip + ag_tmp]
    lea rsi, [rip + ag_statbuf]
    mov edx, 4
    call sb_push
    jmp 1b
8:  mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE

# ---------------- file lists and search ----------------

# ag_walk_args(body, len) -> 1 with the root in ag_path2 and the excluded names in cfg_exclude
#   (explorer_excluded reads it): "ROOT\0EXCLUDES[\0QUERY]"; rdx the query (or 0), rcx its length
ag_walk_args:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + rsi]        # end
    mov rdi, rbx
1:  cmp rdi, r12
    jae 8f
    cmp byte ptr [rdi], 0
    je 2f
    inc rdi
    jmp 1b
2:  mov r13, rdi                # the root's NUL
    mov rax, rdi
    sub rax, rbx
    jz 8f
    cmp rax, 4000
    jae 8f
    lea rdi, [rip + ag_path2]
    mov rsi, rbx
    mov rdx, rax
    push rax
    push rax
    call memcpy
    pop rax
    pop rax
    lea rcx, [rip + ag_path2]
    mov byte ptr [rcx + rax], 0
    # the excluded names, to the next NUL or the end
    lea r14, [r13 + 1]
    mov rdi, r14
3:  cmp rdi, r12
    jae 4f
    cmp byte ptr [rdi], 0
    je 4f
    inc rdi
    jmp 3b
4:  mov r15, rdi
    mov rdi, r14
    mov rsi, r15
    sub rsi, r14
    call mem_dup
    xchg rax, [rip + ag_exclude]
    mov rdi, rax
    call mem_free
    mov rax, [rip + ag_exclude]
    mov [rip + cfg_exclude], rax
    # the query after it
    xor edx, edx
    xor ecx, ecx
    lea rax, [r15 + 1]
    cmp rax, r12
    ja 5f
    mov rdx, rax
    mov rcx, r12
    sub rcx, rax
5:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ag_walk(dir, cb): every file under dir as quick open walks the project (folders through links
#   too, at most 16 deep, excluded names skipped), cb(rel path cstr, its length, abs path cstr) until
#   ag_walk_stop; the relative path is built in ag_rel
ag_walk:
    PROLOGUE
    mov rbx, rdi
    mov [rip + ag_walk_cb], rsi
    mov dword ptr [rip + ag_rel_len], 0
    mov dword ptr [rip + ag_depth], 0
    mov dword ptr [rip + ag_walk_stop], 0
    mov rdi, rbx
    call ag_walk_dir
    EPILOGUE

ag_walk_dir:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + ag_depth], 16
    jae 9f
    inc dword ptr [rip + ag_depth]
    mov rdi, rbx
    lea rsi, [rip + ag_walk_entry]
    mov rdx, rbx
    call dir_each
    dec dword ptr [rip + ag_depth]
9:  EPILOGUE

# ag_walk_entry(dir, name, is_dir): dir_each's callback
ag_walk_entry:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    cmp dword ptr [rip + ag_walk_stop], 0
    jne 9f
    mov rdi, r13
    call explorer_excluded
    test eax, eax
    jnz 9f
    mov ebx, [rip + ag_rel_len]
    lea rdi, [rip + ag_rel]
    add rdi, rbx
    mov rsi, r13
    call cstr_copy
    lea rcx, [rip + ag_rel]
    sub rax, rcx
    mov r15, rax
    mov rdi, r12
    mov rsi, r13
    call path_join
    mov [rsp], rax
    test r14d, r14d
    jz 1f
    cmp r15, 4000
    jae 8f
    lea rax, [rip + ag_rel]
    mov byte ptr [rax + r15], '/'
    lea eax, [r15 + 1]
    mov [rip + ag_rel_len], eax
    mov rdi, [rsp]
    call ag_walk_dir
    mov [rip + ag_rel_len], ebx
    jmp 8f
1:  lea rdi, [rip + ag_rel]
    mov rsi, r15
    mov rdx, [rsp]
    call [rip + ag_walk_cb]
    lea rax, [rip + ag_rel]
    mov byte ptr [rax + rbx], 0
8:  mov rdi, [rsp]
    call mem_free
9:  EPILOGUE

# files MAX LEN + "ROOT\0EXCLUDES" -> the files under ROOT relative to it, each with a NUL (Go to
#   File's list), at most MAX
ag_files:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov [rip + ag_walk_max], rax
    mov qword ptr [rip + ag_walk_n], 0
    mov rdi, r13
    mov rsi, r14
    call ag_walk_args
    test eax, eax
    jz 8f
    lea rdi, [rip + ag_path2]
    call mem_dup_cstr
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + ag_files_one]
    call ag_walk
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -22
    call ag_error
    EPILOGUE

ag_files_one:
    push rbx
    mov rbx, rsi
    lea rsi, [rip + ag_rel]
    mov rdx, rbx
    lea rdi, [rip + ag_tmp]
    call sb_push
    lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    inc qword ptr [rip + ag_walk_n]
    mov rax, [rip + ag_walk_n]
    cmp rax, [rip + ag_walk_max]
    jb 1f
    mov dword ptr [rip + ag_walk_stop], 1
1:  pop rbx
    ret

# mem_dup_cstr(cstr) -> a copy
mem_dup_cstr:
    push rbx
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    pop rbx
    ret

# grep MAX FLAGS LEN + "ROOT\0EXCLUDES\0QUERY" -> find in files on the host: for each line holding
#   the query (FLAGS 1: case-sensitive, else ignoring case), "REL\0LINE\0COL\0LABEL\0" with LINE
#   from 0, COL the match's byte in it, LABEL the line as the palette shows it; at most MAX lines,
#   text files of at most 8 MB, 256 MB read in all
ag_grep:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, 2
    call ag_num
    mov [rip + ag_walk_max], rax
    mov edi, 3
    call ag_num
    mov [rip + ag_grep_case], eax
    mov qword ptr [rip + ag_walk_n], 0
    mov qword ptr [rip + ag_grep_bytes], 0
    mov rdi, r13
    mov rsi, r14
    call ag_walk_args
    test eax, eax
    jz 8f
    test rdx, rdx
    jz 8f
    test rcx, rcx
    jz 8f
    mov [rip + ag_query], rdx
    mov [rip + ag_query_len], rcx
    lea rdi, [rip + ag_path2]
    call mem_dup_cstr
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + ag_grep_file]
    call ag_walk
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    xor esi, esi
    call ag_reply
    EPILOGUE
8:  mov rdi, r12
    mov rsi, -22
    call ag_error
    EPILOGUE

# ag_grep_file(rel, rel len, abs): the lines of one file that hold the query
ag_grep_file:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov rdi, rdx
    mov esi, 8388608
    call file_read_limited
    test rax, rax
    jz 9f
    mov r12, rax                # text
    mov r13, rdx                # length
    add [rip + ag_grep_bytes], rdx
    cmp qword ptr [rip + ag_grep_bytes], 268435456
    jb 1f
    mov dword ptr [rip + ag_walk_stop], 1
1:  test r13, r13
    jz 8f
    # binary: a NUL in the first 8 KiB
    mov rdi, r12
    mov rcx, r13
    cmp rcx, 8192
    jbe 2f
    mov ecx, 8192
2:  xor eax, eax
    repne scasb
    je 8f
    xor r14d, r14d              # scan position
    xor r15d, r15d              # line
    xor ebx, ebx                # line start
.Lag_match:
    mov rax, [rip + ag_walk_n]
    cmp rax, [rip + ag_walk_max]
    jae .Lag_full
    lea rdi, [r12 + r14]
    mov rsi, r13
    sub rsi, r14
    jbe 8f
    mov rdx, [rip + ag_query]
    mov rcx, [rip + ag_query_len]
    cmp dword ptr [rip + ag_grep_case], 0
    je 3f
    call str_find
    jmp 4f
3:  call str_ifind
4:  test rax, rax
    js 8f
    add rax, r14
    mov [rsp + 16], rax         # the match
5:  cmp r14, rax
    jae 6f
    cmp byte ptr [r12 + r14], 10
    jne 51f
    inc r15
    lea rbx, [r14 + 1]
51: inc r14
    jmp 5b
6:  cmp r14, r13                # the line's end; the next search starts there
    jae 7f
    cmp byte ptr [r12 + r14], 10
    je 7f
    inc r14
    jmp 6b
7:  # "REL\0LINE\0COL\0"
    lea rdi, [rip + ag_tmp]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call sb_push
    lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + ag_tmp]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + ag_tmp]
    mov rsi, [rsp + 16]
    sub rsi, rbx
    call sb_push_u64
    lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    # the label: the line without its indent, starting near the match when it is far right, at most
    # 240 bytes, control bytes as blanks (as the palette's own search makes it)
    mov rax, rbx
71: cmp rax, [rsp + 16]
    jae 72f
    movzx ecx, byte ptr [r12 + rax]
    cmp cl, ' '
    je 711f
    cmp cl, 9
    jne 72f
711: inc rax
    jmp 71b
72: mov rcx, [rsp + 16]
    sub rcx, rax
    cmp rcx, 60
    jbe 74f
    mov rax, [rsp + 16]
    sub rax, 40
73: movzx ecx, byte ptr [r12 + rax]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne 74f
    inc rax
    jmp 73b
74: mov [rsp + 24], rax
    lea rcx, [rax + 240]
    cmp rcx, r14
    jbe 75f
    mov rcx, r14
    jmp 76f
75: movzx edx, byte ptr [r12 + rcx]
    and edx, 0xc0
    cmp edx, 0x80
    jne 76f
    inc rcx
    jmp 75b
76: sub rcx, rax
    mov [rsp + 32], rcx
    mov rax, [rip + ag_tmp + SB_len]
    mov [rsp + 40], rax
    lea rdi, [rip + ag_tmp]
    mov rsi, r12
    add rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call sb_push
    mov rdi, [rip + ag_tmp + SB_ptr]
    mov rcx, [rsp + 40]
77: cmp rcx, [rip + ag_tmp + SB_len]
    jae 78f
    cmp byte ptr [rdi + rcx], ' '
    jae 771f
    mov byte ptr [rdi + rcx], ' '
771: inc rcx
    jmp 77b
78: lea rdi, [rip + ag_tmp]
    xor esi, esi
    call sb_push_byte
    inc qword ptr [rip + ag_walk_n]
    jmp .Lag_match
.Lag_full:
    mov dword ptr [rip + ag_walk_stop], 1
8:  mov rdi, r12
    call mem_free
9:  EPILOGUE

.section .rodata
.p2align 3
ag_verbs:
    .quad .Lv_spawn, ag_spawn, .Lv_kill, ag_kill, .Lv_resize, ag_resize, .Lv_close, ag_close
    .quad .Lv_cwd, ag_cwd, .Lv_info, ag_info, .Lv_quit, ag_quitreq
    .quad .Lv_stat, ag_stat, .Lv_lstat, ag_lstat, .Lv_realpath, ag_realpath
    .quad .Lv_readlink, ag_readlink, .Lv_read, ag_read, .Lv_write, ag_write, .Lv_list, ag_list
    .quad .Lv_mkdir, ag_mkdir, .Lv_rename, ag_rename, .Lv_remove, ag_remove
    .quad .Lv_watch, ag_watch, .Lv_unwatch, ag_unwatch
    .quad .Lv_access, ag_access, .Lv_files, ag_files, .Lv_grep, ag_grep
    .quad .Lv_stats, ag_stats
    .quad 0, 0
.Linfo_keys:
    .quad .Lk_home_env, .Lk_home, .Lk_shell_env, .Lk_shell, .Lk_user_env, .Lk_user, 0, 0
.Lv_spawn: .asciz "spawn"
.Lv_kill: .asciz "kill"
.Lv_resize: .asciz "resize"
.Lv_close: .asciz "close"
.Lv_cwd: .asciz "cwd"
.Lv_info: .asciz "info"
.Lv_quit: .asciz "quit"
.Lv_stat: .asciz "stat"
.Lv_lstat: .asciz "lstat"
.Lv_realpath: .asciz "realpath"
.Lv_readlink: .asciz "readlink"
.Lv_read: .asciz "read"
.Lv_write: .asciz "write"
.Lv_list: .asciz "list"
.Lv_mkdir: .asciz "mkdir"
.Lv_rename: .asciz "rename"
.Lv_remove: .asciz "remove"
.Lv_watch: .asciz "watch"
.Lv_unwatch: .asciz "unwatch"
.Lv_access: .asciz "access"
.Lv_files: .asciz "files"
.Lv_grep: .asciz "grep"
.Lv_stats: .asciz "stats"
.Lk_home_env: .asciz "HOME"
.Lk_shell_env: .asciz "SHELL"
.Lk_user_env: .asciz "USER"
.Lk_home: .asciz "home="
.Lk_shell: .asciz "shell="
.Lk_user: .asciz "user="
.Lk_host: .asciz "host="
.Lhello: .asciz "hello rhun-remote "
.Lhex: .ascii "0123456789abcdef"
.Lself: .asciz "/proc/self/exe"
.Lat_self: .asciz "@self"
.Lproc_fd: .asciz "/proc/self/fd/"
.Lshell: .asciz "SHELL"
.Lbin_sh: .asciz "/bin/sh"
.Ldash_lc: .asciz "-lc"
.Lenv_cmd: .asciz "printf '\\n@rhun-env\\n'; exec cat /proc/self/environ"
.Lenv_mark: .ascii "\n@rhun-env\n"
.Lenv_delay: .asciz "RHUN_REMOTE_DELAY_MS"
.Ldevnull: .asciz "/dev/null"
.Lok: .asciz "ok "
.Lerror: .asciz "error "
.Ld: .asciz "d "
.Le: .asciz "e "
.Lw: .asciz "w "
.Lx: .asciz "x "
.Lv: .asciz "v "
.text

.else

# Windows hosts are not supported: the mode exits
FN remote_agent_main
    mov edi, 2
    call sys_exit

.endif
