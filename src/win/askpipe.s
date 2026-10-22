# Named pipes for ssh's askpass on Windows (remoteui.s): the window listens on a pipe only its own
# user may open, local clients only; rhun run by ssh as SSH_ASKPASS connects to it with the question
# and prints the answer. Both ends are descriptors of the table (FD_PIPE) for read, write and close.
.include "win.inc"

.text

# win_pipe_server(name UTF-8, first) -> fd of an instance not connected yet (non-blocking), or
#   -errno. first: the name must be new (FILE_FLAG_FIRST_PIPE_INSTANCE), so nobody else made it
FN win_pipe_server
    PROLOGUE 128
    mov r12d, esi
    call win_wide
    test rax, rax
    jz 8f
    mov rbx, rax
    lea rdi, [rip + .Lsddl]
    call win_wide
    test rax, rax
    jz 7f
    mov r13, rax
    # the owner only: D:P(A;;GA;;;OW)
    mov rcx, r13
    mov edx, 1                  # SDDL_REVISION_1
    lea r8, [rsp + 96]
    xor r9d, r9d
    API ConvertStringSecurityDescriptorToSecurityDescriptorW
    mov r14d, eax
    mov rdi, r13
    call mem_free
    test r14d, r14d
    jz 7f
    mov dword ptr [rsp + 104], 24           # SECURITY_ATTRIBUTES
    mov rax, [rsp + 96]
    mov [rsp + 112], rax
    mov dword ptr [rsp + 120], 0
    mov rcx, rbx
    mov edx, 3                  # PIPE_ACCESS_DUPLEX
    test r12d, r12d
    jz 1f
    or edx, 0x80000             # FILE_FLAG_FIRST_PIPE_INSTANCE
1:  mov r8d, 1 | 8              # PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS (byte mode)
    mov r9d, 255                # PIPE_UNLIMITED_INSTANCES
    mov dword ptr [rsp + 32], 4096
    mov dword ptr [rsp + 40], 4096
    mov dword ptr [rsp + 48], 0
    lea rax, [rsp + 104]
    mov [rsp + 56], rax
    API CreateNamedPipeW
    mov r14, rax
    mov rcx, [rsp + 96]
    API LocalFree
    mov rdi, rbx
    call mem_free
    cmp r14, -1
    je 6f
    mov rdi, r14
    mov esi, FD_PIPE
    mov edx, O_NONBLOCK
    call win_fd_alloc
    test rax, rax
    jns 9f
    mov rbx, rax
    mov rcx, r14
    API CloseHandle
    mov rax, rbx
    EPILOGUE
6:  call win_error
    EPILOGUE
7:  mov rdi, rbx
    call mem_free
8:  mov rax, -22
9:  EPILOGUE

# win_pipe_accept(fd) -> 1 when a client has connected to that instance, 0 while none, -errno
FN win_pipe_accept
    PROLOGUE 96
    call win_fd
    test rax, rax
    jz 8f
    mov rcx, [rax + FD_handle]
    xor edx, edx
    API ConnectNamedPipe
    test eax, eax
    jnz 1f
    API GetLastError
    cmp eax, 535                # ERROR_PIPE_CONNECTED
    je 1f
    cmp eax, 536                # ERROR_PIPE_LISTENING
    je 2f
    cmp eax, 232                # ERROR_NO_DATA: it came and went
    je 3f
    call win_error
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
2:  xor eax, eax
    EPILOGUE
3:  mov rax, -32
    EPILOGUE
8:  mov rax, -9
    EPILOGUE

# win_pipe_open(name UTF-8) -> fd of the client end (blocking), or -errno; a busy pipe is waited
#   for up to 5 s
FN win_pipe_open
    PROLOGUE 96
    call win_wide
    test rax, rax
    jz 8f
    mov rbx, rax
    xor r12d, r12d              # waited once
1:  mov rcx, rbx
    mov edx, 0xC0000000         # GENERIC_READ | GENERIC_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp + 32], 3 # OPEN_EXISTING
    mov dword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    jne 3f
    API GetLastError
    cmp eax, 231                # ERROR_PIPE_BUSY
    jne 2f
    test r12d, r12d
    jnz 2f
    inc r12d
    mov rcx, rbx
    mov edx, 5000
    API WaitNamedPipeW
    jmp 1b
2:  call win_error
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rax, r12
    EPILOGUE
3:  mov r13, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r13
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    test rax, rax
    jns 9f
    mov r12, rax
    mov rcx, r13
    API CloseHandle
    mov rax, r12
    EPILOGUE
8:  mov rax, -22
9:  EPILOGUE

.section .rodata
.Lsddl: .asciz "D:P(A;;GA;;;OW)"
