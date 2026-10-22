# remote hosts, forwarded ports (the design's E5): a port on the host's loopback is reached here at
# 127.0.0.1:LOCAL. remote_forward listens on LOCAL (the same number when it is free, never below
# 1024) and every connection accepted becomes a channel the agent connects to the host's port
# (remote_sock_open, ragent.s's connect). remote_forward_url turns an extension's loopback URL into
# the one that reaches it from here (resources' external-uri asks). The listeners stay while the
# connection is down; a connection accepted then is closed.
.include "rhun.inc"

.equ FW_MAX, 16
.equ FW_TRIES, 50               # ports tried above the first choice

STRUCT
F FW_rport, 4                   # the host's port, 0 for a free entry
F FW_lport, 4                   # ours
F FW_fd, 4                      # the listener
F FW_pad, 4
ENDSTRUCT FW_SIZE

.bss
.p2align 3
fw_tab: .zero FW_SIZE * FW_MAX
fw_sb: .zero SB_SIZE
fw_addr: .zero 16

.text

# remote_forward(port) -> eax the local port that reaches the host's port, or -errno
FN remote_forward
    PROLOGUE
    mov r12d, edi
    mov eax, -22
    test r12d, r12d
    jle 9f
    cmp r12d, 65535
    jg 9f
    mov edi, r12d
    call fw_find
    test rax, rax
    jz 1f
    mov eax, [rax + FW_lport]
    jmp 9f
1:  lea rbx, [rip + fw_tab]
    xor ecx, ecx
2:  cmp dword ptr [rbx + FW_rport], 0
    je 3f
    add rbx, FW_SIZE
    inc ecx
    cmp ecx, FW_MAX
    jb 2b
    mov eax, -28                # ENOSPC
    jmp 9f
3:  # a listener on 127.0.0.1: the same number, else the next free one
    mov r13d, r12d
    cmp r13d, 1024
    jae 4f
    add r13d, 10000             # 80 is 10080 here: low ports need privileges
4:  xor r14d, r14d
5:  mov edi, AF_INET
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js 9f
    mov r15d, eax
    mov edi, r13d
    call fw_set_addr
    mov edi, r15d
    lea rsi, [rip + fw_addr]
    mov edx, 16
    SYS SYS_bind
    test rax, rax
    js 6f
    mov edi, r15d
    mov esi, 16
    SYS SYS_listen
    test rax, rax
    jns 7f
6:  mov edi, r15d
    SYS SYS_close
    inc r13d
    inc r14d
    cmp r13d, 65535
    ja 61f
    cmp r14d, FW_TRIES
    jb 5b
61: mov eax, -98                # EADDRINUSE
    jmp 9f
7:  mov [rbx + FW_rport], r12d
    mov [rbx + FW_lport], r13d
    mov [rbx + FW_fd], r15d
    mov edi, r15d
    mov esi, POLLIN
    lea rdx, [rip + fw_on_accept]
    mov rcx, rbx
    call watch_add
    lea rdi, [rip + fw_sb]
    call sb_clear
    lea rdi, [rip + fw_sb]
    mov esi, r12d
    call sb_push_u64
    lea rdi, [rip + fw_sb]
    lea rsi, [rip + .Ll_to]
    call sb_push_cstr
    lea rdi, [rip + fw_sb]
    mov esi, r13d
    call sb_push_u64
    lea rdi, [rip + fw_sb]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + .Ll_forward]
    mov rsi, [rip + fw_sb + SB_ptr]
    call remote_log2
    mov dword ptr [rip + g_dirty], 1
    mov eax, r13d
9:  EPILOGUE

# fw_set_addr(port): fw_addr = 127.0.0.1:port (struct sockaddr_in)
fw_set_addr:
    xor eax, eax
    mov [rip + fw_addr], rax
    mov [rip + fw_addr + 8], rax
    mov word ptr [rip + fw_addr], AF_INET
    mov eax, edi
    shr eax, 8
    mov ecx, edi
    shl ecx, 8
    or eax, ecx
    mov [rip + fw_addr + 2], ax
    mov dword ptr [rip + fw_addr + 4], 0x0100007f
    ret

# fw_find(port) -> rax the entry forwarding the host's port, or 0
fw_find:
    lea rax, [rip + fw_tab]
    xor ecx, ecx
1:  cmp [rax + FW_rport], edi
    je 9f
    add rax, FW_SIZE
    inc ecx
    cmp ecx, FW_MAX
    jb 1b
    xor eax, eax
9:  ret

# remote_unforward(port) -> eax 0, or -ENOENT when it is not forwarded; 0 stops every forward
FN remote_unforward
    PROLOGUE
    mov r12d, edi
    mov r13d, -2
    lea rbx, [rip + fw_tab]
    xor r14d, r14d
1:  mov eax, [rbx + FW_rport]
    test eax, eax
    jz 2f
    test r12d, r12d
    jz 11f
    cmp eax, r12d
    jne 2f
11: mov edi, [rbx + FW_fd]
    call watch_remove
    mov edi, [rbx + FW_fd]
    SYS SYS_close
    mov dword ptr [rbx + FW_rport], 0
    xor r13d, r13d
2:  add rbx, FW_SIZE
    inc r14d
    cmp r14d, FW_MAX
    jb 1b
    mov dword ptr [rip + g_dirty], 1
    mov eax, r13d
    EPILOGUE

# fw_on_accept(fd, revents, entry): each connection waiting goes to the host
fw_on_accept:
    PROLOGUE
    mov rbx, rdx
1:  mov edi, [rbx + FW_fd]
    xor esi, esi
    xor edx, edx
    mov r10d, SOCK_CLOEXEC | SOCK_NONBLOCK
    SYS SYS_accept4
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    mov edi, eax
    mov esi, [rbx + FW_rport]
    call remote_sock_open       # it owns the connection, also when it refuses
    jmp 1b
9:  EPILOGUE

# remote_forwards_count() -> eax how many ports are forwarded
FN remote_forwards_count
    lea rcx, [rip + fw_tab]
    xor eax, eax
    xor edx, edx
1:  cmp dword ptr [rcx + FW_rport], 0
    je 2f
    inc eax
2:  add rcx, FW_SIZE
    inc edx
    cmp edx, FW_MAX
    jb 1b
    ret

# remote_forwards_dump(sb): " forwards=R:L,R:L" when any (print-remote)
FN remote_forwards_dump
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + fw_tab]
    xor r13d, r13d              # written
    xor r14d, r14d
1:  cmp dword ptr [rbx + FW_rport], 0
    je 3f
    mov rdi, r12
    lea rsi, [rip + .Ld_forwards]
    test r13d, r13d
    jz 2f
    lea rsi, [rip + .Ld_comma]
2:  call sb_push_cstr
    mov r13d, 1
    mov rdi, r12
    mov esi, [rbx + FW_rport]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + FW_lport]
    call sb_push_u64
3:  add rbx, FW_SIZE
    inc r14d
    cmp r14d, FW_MAX
    jb 1b
    EPILOGUE

# remote_forward_url(url ptr, len) -> rax the URL that reaches it from here (cstr, mem_alloc'd: the
#   caller frees it), or 0 when it is not an http(s) URL of the host's loopback (127.0.0.1,
#   localhost, [::1], 0.0.0.0) or its port could not be forwarded. A loopback name stays as it was
#   given ([::1] and 0.0.0.0 become 127.0.0.1); the path and what follows stay.
FN remote_forward_url
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    call remote_is_up
    test eax, eax
    jz 8f
    # the scheme: http:// (port 80) or https:// (443)
    mov ebx, 80
    lea r14, [rip + .Lu_http]
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov ecx, 7
    call str_istarts
    test eax, eax
    jnz 1f
    mov ebx, 443
    lea r14, [rip + .Lu_https]
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov ecx, 8
    call str_istarts
    test eax, eax
    jz 8f
1:  mov rdi, r14
    call strlen
    mov r15, rax                # the scheme's length (with //)
    # the host: one of the loopback names
    lea rdi, [r12 + r15]
    mov rsi, r13
    sub rsi, r15
    call fw_loopback            # rax its length, rdx the name to write
    test rax, rax
    jz 8f
    mov [rsp], rdx
    add r15, rax
    # :PORT, or the scheme's
    cmp r15, r13
    jae 3f
    cmp byte ptr [r12 + r15], ':'
    jne 3f
    lea rdi, [r12 + r15 + 1]
    mov rsi, r13
    sub rsi, r15
    dec rsi
    call parse_u64
    test rdx, rdx
    jz 8f
    mov ebx, eax
    lea r15, [r15 + rdx + 1]
3:  # then nothing, a path, a query or a fragment
    cmp r15, r13
    jae 4f
    movzx eax, byte ptr [r12 + r15]
    cmp eax, '/'
    je 4f
    cmp eax, '?'
    je 4f
    cmp eax, '#'
    jne 8f
4:  mov edi, ebx
    call remote_forward
    test eax, eax
    jle 8f
    mov [rsp + 8], eax
    lea rdi, [rip + fw_sb]
    call sb_clear
    lea rdi, [rip + fw_sb]
    mov rsi, r14
    call sb_push_cstr
    lea rdi, [rip + fw_sb]
    mov rsi, [rsp]
    call sb_push_cstr
    lea rdi, [rip + fw_sb]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + fw_sb]
    mov esi, [rsp + 8]
    call sb_push_u64
    lea rdi, [rip + fw_sb]
    lea rsi, [r12 + r15]
    mov rdx, r13
    sub rdx, r15
    call sb_push
    mov rdi, [rip + fw_sb + SB_ptr]
    mov rsi, [rip + fw_sb + SB_len]
    call mem_dup
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# fw_loopback(ptr, len) -> rax the length of the loopback name it starts with (0 for none), rdx the
#   name the local URL uses
fw_loopback:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + fw_hosts]
1:  mov r14, [rbx]
    test r14, r14
    jz 8f
    mov rdi, r14
    call strlen
    mov r15, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call str_istarts
    test eax, eax
    jz 2f
    # the name ends there
    cmp r15, r13
    jae 3f
    movzx eax, byte ptr [r12 + r15]
    cmp eax, ':'
    je 3f
    cmp eax, '/'
    je 3f
    cmp eax, '?'
    je 3f
    cmp eax, '#'
    je 3f
2:  add rbx, 16
    jmp 1b
3:  mov rax, r15
    mov rdx, [rbx + 8]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# str_istarts(ptr, len, prefix, prefix len) -> eax 1 when ptr starts with prefix, ASCII case ignored
str_istarts:
    xor eax, eax
    cmp rsi, rcx
    jb 9f
    xor r8d, r8d
1:  cmp r8, rcx
    jae 8f
    movzx r9d, byte ptr [rdi + r8]
    movzx r10d, byte ptr [rdx + r8]
    lea r11d, [r9 - 'A']
    cmp r11d, 26
    jae 2f
    or r9d, 0x20
2:  lea r11d, [r10 - 'A']
    cmp r11d, 26
    jae 3f
    or r10d, 0x20
3:  cmp r9d, r10d
    jne 9f
    inc r8
    jmp 1b
8:  mov eax, 1
9:  ret

.section .rodata
.Ll_forward: .asciz "forwarding "
.Ll_to: .asciz " to 127.0.0.1:"
.Ld_forwards: .asciz " forwards="
.Ld_comma: .asciz ","
.Lu_http: .asciz "http://"
.Lu_https: .asciz "https://"
.Lh_v4: .asciz "127.0.0.1"
.Lh_local: .asciz "localhost"
.Lh_v6: .asciz "[::1]"
.Lh_any: .asciz "0.0.0.0"
.p2align 3
fw_hosts:
    .quad .Lh_v4, .Lh_v4, .Lh_local, .Lh_local, .Lh_v6, .Lh_v4, .Lh_any, .Lh_v4, 0, 0
