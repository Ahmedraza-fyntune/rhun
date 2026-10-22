.include "win.inc"
.section .rodata
wfn_ok: .asciz "ok Windows nonblocking flags\n"
wfn_byte: .ascii "x"
.bss
.p2align 3
wfn_fd: .quad 0
wfn_slot: .quad 0
wfn_fail: .quad 0
wfn_calls: .quad 0
wfn_mode: .quad 0
wfn_badwrite: .quad 0
wfn_stage: .quad 0
.text
FN main
    PROLOGUE
    mov edi, 0x1234
    mov esi, FD_PIPE
    xor edx, edx
    call win_fd_alloc
    test rax, rax
    js .Lwfn_fail
    mov [rip + wfn_fd], rax
    mov [rip + wfn_slot], r8
    mov dword ptr [r8 + FD_wend], 1
    mov qword ptr [rip + wfn_stage], 1
    mov qword ptr [rip + wfn_fail], 1
    mov rdi, rax
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    call ws_fcntl
    test rax, rax
    js 1f
    mov rdi, [rip + wfn_fd]
    lea rsi, [rip + wfn_byte]
    mov edx, 1
    call ws_write
    jmp .Lwfn_fail
1:  cmp rax, -13
    jne .Lwfn_fail
    mov rbx, [rip + wfn_slot]
    cmp dword ptr [rbx + FD_flags], 0
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_mode], 0
    jne .Lwfn_fail
    mov qword ptr [rip + wfn_stage], 2
    mov rdi, [rip + wfn_fd]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    call ws_fcntl
    test rax, rax
    jnz .Lwfn_fail
    cmp dword ptr [rbx + FD_flags], O_NONBLOCK
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_mode], 1
    jne .Lwfn_fail
    mov rdi, [rip + wfn_fd]
    mov esi, 3
    xor edx, edx
    call ws_fcntl
    cmp rax, O_NONBLOCK
    jne .Lwfn_fail
    mov qword ptr [rip + wfn_stage], 3
    mov qword ptr [rip + wfn_fail], 1
    mov rdi, [rip + wfn_fd]
    mov esi, F_SETFL
    xor edx, edx
    call ws_fcntl
    cmp rax, -13
    jne .Lwfn_fail
    cmp dword ptr [rbx + FD_flags], O_NONBLOCK
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_mode], 1
    jne .Lwfn_fail
    mov qword ptr [rip + wfn_stage], 4
    mov rdi, [rip + wfn_fd]
    mov esi, F_SETFL
    xor edx, edx
    call ws_fcntl
    test rax, rax
    jnz .Lwfn_fail
    cmp dword ptr [rbx + FD_flags], 0
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_mode], 0
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_calls], 4
    jne .Lwfn_fail
    mov qword ptr [rip + wfn_stage], 5
    mov dword ptr [rbx + FD_wend], 0
    mov rdi, [rip + wfn_fd]
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    call ws_fcntl
    test rax, rax
    jnz .Lwfn_fail
    cmp dword ptr [rbx + FD_flags], O_NONBLOCK
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_calls], 4
    jne .Lwfn_fail
    mov rdi, [rip + wfn_fd]
    mov esi, 3
    xor edx, edx
    call ws_fcntl
    cmp rax, O_NONBLOCK
    jne .Lwfn_fail
    cmp qword ptr [rip + wfn_badwrite], 0
    jne .Lwfn_fail
    mov rdi, rbx
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    lea rdi, [rip + wfn_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lwfn_fail:
    mov rdi, [rip + wfn_stage]
    call sys_exit

FN wfn_SetNamedPipeHandleState
    cmp rcx, 0x1234
    jne 9f
    CALLBACK 96
    inc qword ptr [rip + wfn_calls]
    cmp qword ptr [rip + wfn_fail], 0
    je 1f
    mov qword ptr [rip + wfn_fail], 0
    mov ecx, 5
    API SetLastError
    xor eax, eax
    jmp 2f
1:  mov eax, [rdx]
    mov [rip + wfn_mode], rax
    mov eax, 1
2:  CALLBACK_END 96
9:  jmp qword ptr [rip + __imp_SetNamedPipeHandleState]

FN wfn_WriteFile
    cmp rcx, 0x1234
    jne 9f
    inc qword ptr [rip + wfn_badwrite]
    mov dword ptr [r9], 1
    mov eax, 1
    ret
9:  jmp qword ptr [rip + __imp_WriteFile]
