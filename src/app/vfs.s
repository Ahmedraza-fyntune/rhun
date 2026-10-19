# workspace access: files, folders, watches and programs of the project, local or on the host of a
# remote window (remote.s). Workspace code calls these instead of sys.s and proc.s; rhun's own
# config, state, themes and installed extensions keep the direct functions. Each one is the local
# function when the window is not remote.
.include "rhun.inc"

.bss
.p2align 3
vfs_pending: .zero SB_SIZE      # watch events from the host, waiting for vfs_tick: WD MASK LEN name

.text

# ---------------- programs ----------------

# vfs_run_piped(argv, envp, cwd) -> as run_piped
FN vfs_run_piped
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    jmp vfs_run_piped_input

# vfs_run_piped_input(argv, envp, cwd, ptr, len, errors) -> as run_piped_input: rax pid or -errno,
#   edx the descriptor to read the program's output from. In a remote window the program runs on
#   the host, found by its name in the host's PATH.
FN vfs_run_piped_input
    cmp dword ptr [rip + g_remote], 0
    je run_piped_input
    push rbx
    mov rbx, r8                 # input length
    mov r10d, r9d               # errors: 1 merges them with the output, else /dev/null
    mov r9, rcx                 # input
    mov r8d, -1
    test r10d, 1
    jz 1f
    mov r8d, -2
1:  xor ecx, ecx                # flags: a pipe, argv[0] by name
    push rbx
    push rbx
    call remote_spawn
    add rsp, 16
    pop rbx
    ret

# vfs_pty_spawn(argv, envp, cwd, cols, rows) -> rax pid (or -errno), edx the master (nonblocking).
#   In a remote window an empty argv (argv[0] == 0 or "") is the user's shell on the host.
FN vfs_pty_spawn
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov [rsp], ecx
    mov [rsp + 4], r8d
    cmp dword ptr [rip + g_remote], 0
    jne 5f
.ifdef WINDOWS
    mov rax, -38
    EPILOGUE
.else
    mov edi, ecx
    mov esi, r8d
    call pty_open
    test eax, eax
    js 8f
    mov ebx, eax                # master
    mov r15d, edx               # slave
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov ecx, r15d
    mov r8d, r15d
    mov r9d, r15d
    push 1
    push 1
    call proc_spawn
    add rsp, 16
    mov [rsp + 8], rax
    mov edi, r15d
    SYS SYS_close
    mov rax, [rsp + 8]
    test rax, rax
    jg 2f
    mov edi, ebx
    SYS SYS_close
    mov rax, [rsp + 8]
    test rax, rax
    jnz 9f
    mov rax, -5
    EPILOGUE
2:  mov edx, ebx
    EPILOGUE
8:  mov rax, -5
    EPILOGUE
.endif
5:  # flags: a pty, columns in bits 8-23, rows from bit 24
    mov ecx, [rsp]
    and ecx, 0xffff
    shl ecx, 8
    mov eax, [rsp + 4]
    and eax, 0xff
    shl eax, 24
    or ecx, eax
    or ecx, 1
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov r8d, -1
    xor r9d, r9d
    push 0
    push 0
    call remote_spawn
    add rsp, 16
9:  EPILOGUE

# ---------------- watch events from the host ----------------

# vfs_remote_event(wd, mask, name ptr, len): an inotify event of a remote watch; kept for vfs_tick
#   (it comes in the middle of the stream's parsing, where nothing else may run)
FN vfs_remote_event
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp qword ptr [rip + vfs_pending + SB_len], 4194304
    jae 9f                      # nobody takes them: drop
    lea rdi, [rip + vfs_pending]
    mov esi, 16
    call sb_reserve
    mov [rax], ebx
    mov [rax + 4], r12d
    mov [rax + 8], r14
    add qword ptr [rip + vfs_pending + SB_len], 16
    lea rdi, [rip + vfs_pending]
    mov rsi, r13
    mov rdx, r14
    call sb_push
9:  EPILOGUE

# vfs_remote_lost(): the connection went: pending events are stale
FN vfs_remote_lost
    sub rsp, 8
    lea rdi, [rip + vfs_pending]
    call sb_clear
    add rsp, 8
    ret
