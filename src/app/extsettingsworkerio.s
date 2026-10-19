# Helper-only borrowed standard pipes. No virtual FD kind assumptions or UI polling.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.equ SIO_in, 0
.equ SIO_out, 8
.equ SIO_ready, 16
.text
# io_init(zeroed IO24)->0/-errno. Borrowed std handles live through helper exit.
FN ext_settings_worker_io_init
    PROLOGUE 176
    mov rbx, rdi
    mov qword ptr [rbx + SIO_ready], 0
.ifdef WINDOWS
    mov ecx, -10
    API GetStdHandle
    test rax, rax
    jz .Lswio_badfd
    cmp rax, -1
    je .Lswio_badfd
    mov [rbx + SIO_in], rax
    mov rcx, rax
    API GetFileType
    cmp eax, 3                # FILE_TYPE_PIPE
    jne .Lswio_badpipe
    mov ecx, -11
    API GetStdHandle
    test rax, rax
    jz .Lswio_badfd
    cmp rax, -1
    je .Lswio_badfd
    mov [rbx + SIO_out], rax
    mov rcx, rax
    API GetFileType
    cmp eax, 3
    jne .Lswio_badpipe
    mov dword ptr [rsp + 80], 1 # PIPE_NOWAIT, real write-handle state, checked.
    mov rcx, [rbx + SIO_out]
    lea rdx, [rsp + 80]
    xor r8d, r8d
    xor r9d, r9d
    API SetNamedPipeHandleState
    test eax, eax
    jz .Lswio_native_error
.else
    mov qword ptr [rbx + SIO_in], 0
    mov qword ptr [rbx + SIO_out], 1
    xor r12d, r12d
1:  mov rdi, r12
    mov rsi, rsp
    SYS SYS_fstat
    test rax, rax
    js .Lswio_done
    mov eax, [rsp + 24]
    and eax, 0170000
    cmp eax, 0010000           # FIFO/pipe only
    jne .Lswio_badpipe
    mov rdi, r12
    mov esi, 3
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js .Lswio_done
    mov rdx, rax
    or edx, O_NONBLOCK
    mov rdi, r12
    mov esi, 4
    SYS SYS_fcntl
    test rax, rax
    js .Lswio_done
    mov rdi, r12
    mov esi, 3
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js .Lswio_done
    test eax, O_NONBLOCK
    jz .Lswio_badpipe
    inc r12
    cmp r12, 2
    jb 1b
.endif
    mov qword ptr [rbx + SIO_ready], 1
    xor eax, eax
.Lswio_done:
    EPILOGUE
.Lswio_badfd:
    mov rax, -9
    EPILOGUE
.Lswio_badpipe:
    mov rax, -22
    EPILOGUE
.ifdef WINDOWS
.Lswio_native_error:
    call win_error
    EPILOGUE
.endif

# io_read(IO,buf,count1..65536)->bytes/0EOF/-errno. One raw read, no wait/retry.
FN ext_settings_worker_io_read
    test rdx, rdx
    jz .Lswio_invalid
    cmp rdx, 65536
    ja .Lswio_invalid
    cmp qword ptr [rdi + SIO_ready], 1
    jne .Lswio_unready
.ifdef WINDOWS
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rcx, [rbx + SIO_in]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp + 80]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    API PeekNamedPipe
    test eax, eax
    jz .Lswio_read_error
    mov eax, [rsp + 80]
    test eax, eax
    jz .Lswio_again_owned
    cmp r13, rax
    cmova r13, rax
    mov rcx, [rbx + SIO_in]
    mov rdx, r12
    mov r8d, r13d
    lea r9, [rsp + 80]
    mov qword ptr [rsp + 32], 0
    API ReadFile
    test eax, eax
    jz .Lswio_read_error
    mov eax, [rsp + 80]
    cmp rax, r13
    ja .Lswio_io_error
    EPILOGUE
.Lswio_read_error:
    API GetLastError
    cmp eax, 109
    je .Lswio_eof
    cmp eax, 232
    je .Lswio_eof
    call win_error
    EPILOGUE
.Lswio_eof:
    xor eax, eax
    EPILOGUE
.Lswio_again_owned:
    mov rax, -11
    EPILOGUE
.Lswio_io_error:
    mov rax, -5
    EPILOGUE
.else
    mov rdi, [rdi + SIO_in]
    SYS SYS_read
    ret
.endif

# io_write(IO,bytes,count1..65536)->positive progress/-errno. Never returns false EOF.
FN ext_settings_worker_io_write
    test rdx, rdx
    jz .Lswio_invalid
    cmp rdx, 65536
    ja .Lswio_invalid
    cmp qword ptr [rdi + SIO_ready], 1
    jne .Lswio_unready
.ifdef WINDOWS
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, 4096
    jbe .Lswio_write_count_ready
    mov r13d, 4096
.Lswio_write_count_ready:
    mov rcx, [rbx + SIO_out]
    mov rdx, r12
    mov r8d, r13d
    lea r9, [rsp + 80]
    mov qword ptr [rsp + 32], 0
    API WriteFile
    test eax, eax
    jz .Lswio_write_error
    mov eax, [rsp + 80]
    cmp rax, r13
    ja .Lswio_write_bad
    test rax, rax
    jz .Lswio_write_again
    EPILOGUE
.Lswio_write_error:
    API GetLastError
    cmp eax, 109
    je .Lswio_broken
    cmp eax, 232
    je .Lswio_broken
    call win_error
    EPILOGUE
.Lswio_broken:
    mov rax, -32
    EPILOGUE
.Lswio_write_bad:
    mov rax, -5
    EPILOGUE
.Lswio_write_again:
    mov rax, -11
    EPILOGUE
.else
    mov rdi, [rdi + SIO_out]
    SYS SYS_write
    test rax, rax
    jz .Lswio_again
    ret
.endif
.Lswio_invalid:
    mov rax, -22
    ret
.Lswio_unready:
    mov rax, -9
    ret
.Lswio_again:
    mov rax, -11
    ret

# io_probe(IO)->0 quiet/-125 controlEOF/-71 unexpected bytes/-errno.
FN ext_settings_worker_io_probe
    PROLOGUE 16
    mov rsi, rsp
    mov edx, 1
    call ext_settings_worker_io_read
    cmp rax, -11
    je 1f
    test rax, rax
    js 3f
    jz 2f
    mov rax, -71
3:  EPILOGUE
1:  xor eax, eax
    EPILOGUE
2:  mov rax, -125
    EPILOGUE
