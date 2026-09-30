# Native process and pseudoconsole integration. Used by tests/windows.py.
.include "rhun.inc"
.bss
buf: .zero 65536
.text
FN main
    PROLOGUE 80
    mov rax, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 2
    jb .Lfail
    mov rdi, [rax + 8]
    lea rsi, [rip + .Lecho]
    call strcmp_eq
    test eax, eax
    jnz .Lchild
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + .Lpty]
    call strcmp_eq
    test eax, eax
    jnz .Lpty_run
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + .Lfont]
    call strcmp_eq
    test eax, eax
    jnz .Lfont_run
    mov rax, [rip + g_argv]
    mov rax, [rax]
    mov [rsp], rax
    lea rax, [rip + .Lecho]
    mov [rsp + 8], rax
    lea rax, [rip + .Lempty]
    mov [rsp + 16], rax
    lea rax, [rip + .Lspaces]
    mov [rsp + 24], rax
    lea rax, [rip + .Lquotes]
    mov [rsp + 32], rax
    lea rax, [rip + .Lunicode]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    lea rdi, [rip + .Lextras]
    call env_make
    mov rbx, rax
    mov rdi, rsp
    mov rsi, rbx
    xor edx, edx
    call run_piped
    mov r12, rax
    mov r13d, edx
    mov rdi, rbx
    call mem_free
    test r12, r12
    js .Lfail
    mov dword ptr [rsp + 64], 0
    jmp .Lread_start
.Lpty_run:
    lea rdi, [rip + .Lcmd]
    call proc_which
    test rax, rax
    jz .Lfail
    mov [rsp], rax
    lea rax, [rip + .Ld]
    mov [rsp + 8], rax
    lea rax, [rip + .Lq]
    mov [rsp + 16], rax
    lea rax, [rip + .Lc]
    mov [rsp + 24], rax
    lea rax, [rip + .Lcommand]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    mov edi, 80
    mov esi, 24
    call pty_open
    test eax, eax
    js .Lfail
    mov r13d, eax
    mov r14d, edx
    mov edi, eax
    mov esi, 100
    mov edx, 30
    xor ecx, ecx
    xor r8d, r8d
    call pty_resize
    mov rdi, rsp
    mov rsi, [rip + g_envp]
    xor edx, edx
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, r14d
    push 1
    push 1
    call proc_spawn
    add rsp, 16
    mov r12, rax
    mov edi, r14d
    SYS SYS_close
    mov rdi, [rsp]
    call mem_free
    test r12, r12
    js .Lclose_fail
    mov dword ptr [rsp + 64], 1
.Lread_start:
    call time_ms
    mov r15, rax
    mov dword ptr [rsp + 68], -1
.Lread:
    mov edi, r13d
    lea rsi, [rip + buf]
    mov edx, 65536
    SYS SYS_read
    test rax, rax
    jg .Lwrite
    cmp rax, -11
    je .Lwait
    test rax, rax
    jnz .Lclose_fail
    jmp .Ldone
.Lwrite:
    mov edi, 1
    lea rsi, [rip + buf]
    mov rdx, rax
    call write_all
.Lwait:
    cmp dword ptr [rsp + 68], -1
    jne 1f
    mov edi, r12d
    mov esi, 1
    call proc_wait
    mov [rsp + 68], eax
1:  call time_ms
    sub rax, r15
    cmp rax, 10000
    jae .Lclose_fail
    cmp rax, 500
    jb 2f
    cmp dword ptr [rsp + 68], 0
    je .Ldone
2:  xor edi, edi
    xor esi, esi
    mov edx, 10
    SYS SYS_poll
    jmp .Lread
.Ldone:
    cmp dword ptr [rsp + 68], -1
    jne 1f
    mov edi, r12d
    xor esi, esi
    call proc_wait
    mov [rsp + 68], eax
1:  mov edi, r13d
    SYS SYS_close
    mov eax, [rsp + 68]
    EPILOGUE
.Lclose_fail:
    mov edi, r13d
    SYS SYS_close
.Lfail:
    mov eax, 1
    EPILOGUE
.Lchild:
    mov r12d, 2
1:  cmp r12, [rip + g_argc]
    jae 2f
    mov rax, [rip + g_argv]
    mov rdi, [rax + r12*8]
    call print_line
    inc r12
    jmp 1b
2:  lea rdi, [rip + .Lenv]
    call getenv
    test rax, rax
    jz .Lfail
    mov rdi, rax
    call print_line
    xor eax, eax
    EPILOGUE
.Lfont_run:
    cmp qword ptr [rip + g_argc], 3
    jb .Lfail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    call file_read_all
    test rax, rax
    jz .Lfail
    mov rdi, rax
    mov rsi, rdx
    call font_load
    test rax, rax
    jz .Lfail
    mov rdi, rax
    mov esi, 'A'
    cmp qword ptr [rip + g_argc], 4
    jb 1f
    mov esi, 0x65e5
1:  call font_glyph_index
    test eax, eax
    jz .Lfail
    xor eax, eax
    EPILOGUE
print_line:
    push rbx
    mov rbx, rdi
    call strlen
    mov edi, 1
    mov rsi, rbx
    mov rdx, rax
    call write_all
    mov edi, 1
    lea rsi, [rip + .Lnewline]
    mov edx, 1
    call write_all
    pop rbx
    ret
.section .rodata
.Lecho: .asciz "echo"
.Lpty: .asciz "pty"
.Lfont: .asciz "font"
.Lempty: .asciz ""
.Lspaces: .asciz "two words"
.Lquotes: .asciz "a\\\"b\\"
.Lunicode: .asciz "caf\303\251 \346\227\245\346\234\254"
.Lenv: .asciz "RHUN_TEST_VALUE"
.Lextra: .asciz "RHUN_TEST_VALUE=space and \303\251"
.Lextras: .quad .Lextra,0
.Lnewline: .byte 10
.Lcmd: .asciz "cmd.exe"
.Ld: .asciz "/d"
.Lq: .asciz "/q"
.Lc: .asciz "/c"
.Lcommand: .asciz "echo RHUN_CONPTY_OK"
