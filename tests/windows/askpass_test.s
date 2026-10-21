# ssh's askpass on Windows (src/win/askpipe.s, remoteui.s): this test is the window. It makes the
# pipe, starts build/windows/rhun.com as ssh would (RHUN_ASKPASS naming the pipe, the question as
# its argument), reads the question up to its NUL, answers, and rhun.com prints the answer on its
# standard output and exits 0. (A second pipe of the same name cannot be made first on Windows,
# which stops squatting; Wine does not check that, so it is not asserted.)
# Exit code: 0, or the failed step's number.
.include "win.inc"
.bss
.p2align 3
buf: .zero 4096
argv: .zero 32
envx: .zero 16
tsp: .zero 16
.text
FN main
    PROLOGUE 16
    mov ebx, 1
    lea rdi, [rip + .Lname]
    mov esi, 1
    call win_pipe_server
    test rax, rax
    js .Lfail
    mov r12d, eax               # the waiting instance
    inc ebx
    lea rdi, [rip + .Lname]     # nobody makes it new again (Windows refuses; Wine does not check)
    mov esi, 1
    call win_pipe_server
    test rax, rax
    js 11f
    mov edi, eax
    SYS SYS_close
11:
    # rhun.com as ssh's askpass program
    inc ebx
    lea rax, [rip + .Lexe]
    mov [rip + argv], rax
    lea rax, [rip + .Lquestion]
    mov [rip + argv + 8], rax
    mov qword ptr [rip + argv + 16], 0
    lea rax, [rip + .Lenv]
    mov [rip + envx], rax
    mov qword ptr [rip + envx + 8], 0
    lea rdi, [rip + envx]
    call env_make
    mov rsi, rax
    lea rdi, [rip + argv]
    xor edx, edx
    call run_piped
    test rax, rax
    jle .Lfail
    mov r13d, eax               # pid
    mov r14d, edx               # its output
    # its connection
    inc ebx
    xor r15d, r15d
1:  mov edi, r12d
    call win_pipe_accept
    test rax, rax
    js .Lfail
    jnz 2f
    call nap
    inc r15d
    cmp r15d, 1000
    jb 1b
    jmp .Lfail
2:  # the question, up to its NUL
    inc ebx
    xor r15d, r15d              # bytes
    mov qword ptr [rsp], 0      # naps
3:  mov edi, r12d
    lea rsi, [rip + buf]
    add rsi, r15
    mov edx, 4000
    sub edx, r15d
    SYS SYS_read
    cmp rax, -11
    je 4f
    test rax, rax
    jle .Lfail
    add r15, rax
    lea rdi, [rip + buf]
    cmp byte ptr [rdi + r15 - 1], 0
    je 5f
    jmp 3b
4:  call nap
    inc qword ptr [rsp]
    cmp qword ptr [rsp], 1000
    jb 3b
    jmp .Lfail
5:  inc ebx
    lea rdi, [rip + buf]
    lea rsi, [rip + .Lquestion]
    call strcmp_eq
    test eax, eax
    jz .Lfail
    # the answer, read before the instance closes
    inc ebx
    mov edi, r12d
    lea rsi, [rip + .Lanswer]
    mov edx, 7
    call write_all
    test rax, rax
    js .Lfail
    mov edi, r12d
    SYS SYS_fsync
    mov edi, r12d
    SYS SYS_close
    # what rhun.com printed, and its exit
    inc ebx
    xor r15d, r15d
6:  mov edi, r14d
    lea rsi, [rip + buf]
    add rsi, r15
    mov edx, 4000
    sub edx, r15d
    SYS SYS_read
    cmp rax, -11
    jne 7f
    call nap
    jmp 6b
7:  test rax, rax
    js .Lfail
    jz 8f
    add r15, rax
    jmp 6b
8:  lea rdi, [rip + buf]
    mov byte ptr [rdi + r15], 0
    lea rsi, [rip + .Lprinted]
    call strcmp_eq
    test eax, eax
    jz .Lfail
    inc ebx
    mov edi, r13d
    xor esi, esi
    call proc_wait
    test eax, eax
    jnz .Lfail
    lea rdi, [rip + .Lok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov edi, ebx
    call sys_exit

# nap(): 5 ms
nap:
    sub rsp, 8
    mov qword ptr [rip + tsp], 0
    mov qword ptr [rip + tsp + 8], 5000000
    lea rdi, [rip + tsp]
    xor esi, esi
    mov eax, 35                 # nanosleep
    XSYS
    add rsp, 8
    ret

.section .rodata
.Lname: .asciz "\\\\.\\pipe\\rhun-askpass-test-5b1e"
.Lenv: .asciz "RHUN_ASKPASS=\\\\.\\pipe\\rhun-askpass-test-5b1e"
.Lexe: .asciz "build/windows/rhun.com"
.Lquestion: .asciz "pw@host's password: "
.Lanswer: .ascii "ys3cret"
.Lprinted: .asciz "s3cret\n"
.Lok: .asciz "ok askpass\n"
