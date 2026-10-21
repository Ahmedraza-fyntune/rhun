# headless control commands of remote windows (control.s's ctl_tables):
#   print-remote              remote=KIND host=H state=S channels=N rtt=MS in=B out=B procs=P [error=TEXT]
#   remote-connect SPEC [PATH] this window becomes a remote window (as --remote SPEC PATH)
#   remote-drop               the transport is killed, as a dropped connection
#   remote-reconnect          Reconnect
#   wait-remote [SECONDS]     until the connection is up, failed or lost (60 s unless given)
#   print-explorer            the explorer's rows as shown (indented by depth, folders end in /)
#   remote-forward PORT       the host's port forwarded: "forward=PORT local=LOCAL" or "forward-error=ERRNO"
#   remote-unforward PORT     it stops (0: all of them)
#   print-forward-url URL     remote_forward_url's answer: "url=URL", or "url=-" for none
.include "rhun.inc"

.text

# each fn(out sb, rest, rest len) -> rax 0
.section .rodata
.p2align 3
.globl remote_ctl
remote_ctl:
    .quad .Lc_print_remote, c_print_remote, .Lc_remote_connect, c_remote_connect
    .quad .Lc_remote_drop, c_remote_drop, .Lc_remote_reconnect, c_remote_reconnect
    .quad .Lc_wait_remote, c_wait_remote, .Lc_print_explorer, c_print_explorer
    .quad .Lc_remote_forward, c_remote_forward, .Lc_remote_unforward, c_remote_unforward
    .quad .Lc_print_forward_url, c_print_forward_url
    .quad 0, 0
.Lc_print_remote: .asciz "print-remote"
.Lc_remote_connect: .asciz "remote-connect"
.Lc_remote_drop: .asciz "remote-drop"
.Lc_remote_reconnect: .asciz "remote-reconnect"
.Lc_wait_remote: .asciz "wait-remote"
.Lc_print_explorer: .asciz "print-explorer"
.Lc_remote_forward: .asciz "remote-forward"
.Lc_remote_unforward: .asciz "remote-unforward"
.Lc_print_forward_url: .asciz "print-forward-url"
.Lk_forward: .asciz "forward="
.Lk_local: .asciz " local="
.Lk_forward_error: .asciz "forward-error="
.Lk_url: .asciz "url="
.Lk_none: .asciz "-"
.text

c_print_remote:
    sub rsp, 8
    call remote_dump
    add rsp, 8
    xor eax, eax
    ret

c_remote_connect:
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov r12, rax
    mov r13, rdx
    mov rdi, rax
    mov rsi, rdx
    call next_word
    mov rbx, rcx                # consumed
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r14, rax                # SPEC
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r15, rax                # PATH ("" for the home folder)
    mov rdi, r14
    mov rsi, r15
    call remote_start
    mov rdi, r14
    call mem_free
    mov rdi, r15
    call mem_free
    xor eax, eax
    EPILOGUE

c_remote_drop:
    sub rsp, 8
    call remote_drop
    add rsp, 8
    xor eax, eax
    ret

c_remote_reconnect:
    sub rsp, 8
    call remote_reconnect
    add rsp, 8
    xor eax, eax
    ret

c_wait_remote:
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    test rax, rax
    jnz 1f
    mov eax, 60
1:  imul r13, rax, 1000
    call time_ms
    add r13, rax
2:  mov eax, [rip + g_remote_state]
    cmp eax, 6                  # RS_UP and after
    jae 3f
    test eax, eax
    jz 3f
    call time_ms
    cmp rax, r13
    jae 3f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 2b
3:  call app_tick               # the tick that opens the project
    xor eax, eax
    EPILOGUE

c_print_explorer:
    sub rsp, 8
    call explorer_dump
    add rsp, 8
    xor eax, eax
    ret

# rc_port(rest, len) -> rax the number given
rc_port:
    sub rsp, 8
    call trim
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    add rsp, 8
    ret

c_remote_forward:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call rc_port
    mov r12, rax
    mov edi, eax
    call remote_forward
    movsxd r13, eax
    test r13, r13
    jle 1f
    mov rdi, rbx
    lea rsi, [rip + .Lk_forward]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lk_local]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r13
    call sb_push_u64
    jmp 2f
1:  mov rdi, rbx
    lea rsi, [rip + .Lk_forward_error]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r13
    neg rsi
    call sb_push_u64
2:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

c_remote_unforward:
    sub rsp, 8
    mov rdi, rsi
    mov rsi, rdx
    call rc_port
    mov edi, eax
    call remote_unforward
    add rsp, 8
    xor eax, eax
    ret

c_print_forward_url:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call remote_forward_url
    mov r12, rax
    mov rdi, rbx
    lea rsi, [rip + .Lk_url]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lk_none]
    test r12, r12
    jz 1f
    mov rsi, r12
1:  call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    call mem_free
    xor eax, eax
    EPILOGUE
