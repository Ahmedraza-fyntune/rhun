# Early native keeper mode. Never initializes editor, contributions or a project.
.include "rhun.inc"
.include "app/taskproc.inc"
.bss
.p2align 4
kh_context: .zero KH_SIZE
.section .rodata
kh_flag: .asciz "--process-keeper"
kh_version: .asciz "v1"
.text

# Exact positive63-bit canonical decimal, no sign, whitespace or overflow.
FN kp_parse_positive
    xor eax, eax
    xor ecx, ecx
    cmp byte ptr [rdi], '0'
    je 8f
1:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 9f
    cmp ecx, 19
    jae 8f
    sub edx, '0'
    cmp edx, 9
    ja 8f
    mov r8, 922337203685477580
    cmp rax, r8
    ja 8f
    jne 2f
    cmp edx, 7
    ja 8f
2:  imul rax, rax, 10
    add rax, rdx
    inc ecx
    jmp 1b
8:  xor eax, eax
9:  ret

FN keeper_helper_entry
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jb .Lkh_not_helper
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + kh_flag]
    call strcmp_eq
    test eax, eax
    jz .Lkh_not_helper
.ifdef WINDOWS
    cmp qword ptr [rip + g_argc], 8
.else
    cmp qword ptr [rip + g_argc], 4
.endif
    jne .Lkh_bad_arguments
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    lea rsi, [rip + kh_version]
    call strcmp_eq
    test eax, eax
    jz .Lkh_bad_arguments
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call kp_parse_positive
    test rax, rax
    jle .Lkh_bad_arguments
    lea rbx, [rip + kh_context]
    mov [rbx + KH_nonce], rax
    lea rdi, [rbx + KH_native]
    call kp_native_init
    mov qword ptr [rbx + KH_stdio], 0
    mov qword ptr [rbx + KH_stdio + 8], 1
    mov qword ptr [rbx + KH_stdio + 16], 3
    mov qword ptr [rbx + KH_stdio + 24], 4
    mov qword ptr [rbx + KH_stdio + 32], 5
    mov qword ptr [rbx + KH_scan], -1
    mov qword ptr [rbx + KH_lease], -1
    mov qword ptr [rbx + KH_gate], -1
    mov qword ptr [rbx + KH_setup], -1
    mov qword ptr [rbx + KH_txused], -1
    mov dword ptr [rbx + KH_exit], -1
    mov qword ptr [rbx + KH_expected], 24
    mov qword ptr [rbx + KH_dirty], 1
    call time_ms
    add rax, 10000
    mov [rbx + KH_deadline], rax
    mov rdi, rbx
    call kp_helper_adopt
    test rax, rax
    js .Lkh_initial_fail
    mov edi, KP_FRAME_MAX + 8720 + 1048576
    call mem_alloc_try
    test rax, rax
    jz .Lkh_nomem
    mov [rbx + KH_frame], rax
    lea rcx, [rax + KP_FRAME_MAX]
    mov [rbx + KH_argv], rcx
    add rcx, 520
    mov [rbx + KH_envp], rcx
    add rcx, 8200
    mov [rbx + KH_work], rcx
.Lkh_loop:
    test dword ptr [rbx + KH_flags], KP_DONE
    jnz .Lkh_flush
    call time_ms
    test dword ptr [rbx + KH_flags], KP_STARTED
    jnz 1f
    cmp rax, [rbx + KH_deadline]
    jb 1f
    mov rdi, rbx
    mov esi, -110
    call kh_fail
    jmp .Lkh_tick
1:  cmp qword ptr [rbx + KH_stopping], 0
    jne .Lkh_tick
    test dword ptr [rbx + KH_flags], KP_FAILED | KP_DONE
    jnz .Lkh_tick
    cmp dword ptr [rbx + KH_eof], 0
    jne .Lkh_tick
    mov rdi, rbx
    call kh_control
    test rax, rax
    jns .Lkh_tick
    cmp rax, -11
    je .Lkh_tick
    cmp rax, -125
    jne 11f
    test dword ptr [rbx + KH_flags], KP_STARTED
    jz 11f
    mov rdi, rbx
    call kp_target_stop
    jmp .Lkh_tick
11: mov rdi, rbx
    mov esi, eax
    call kh_fail
.Lkh_tick:
    cmp qword ptr [rbx + KH_initialized], 0
    je .Lkh_flush
    cmp qword ptr [rbx + KH_prepare_pending], 0
    je 121f
    test dword ptr [rbx + KH_flags], KP_DONE
    jnz .Lkh_flush
    test dword ptr [rbx + KH_flags], KP_FAILED
    jnz 121f
    mov rdi, rbx
    call kp_extension_prepare
    cmp rax, -11
    jne 122f
    cmp qword ptr [rbx + KH_native_attempted], 0
    je .Lkh_flush
122: test rax, rax
    jns 121f
    mov rdi, rbx
    mov esi, eax
    call kh_fail
    jmp .Lkh_flush
121: mov rdi, rbx
    call kp_target_poll
    test rax, rax
    jns 2f
    mov rdi, rbx
    mov esi, eax
    call kh_fail
2:  cmp dword ptr [rbx + KH_start], 0
    je .Lkh_flush
    test dword ptr [rbx + KH_flags], KP_STARTED | KP_FAILED | KP_DONE
    jnz .Lkh_flush
    test dword ptr [rbx + KH_flags], KP_READY
    jz .Lkh_flush
    mov rdi, rbx
    call kp_helper_alive
    test rax, rax
    jz 3f
    cmp rax, -11
    je .Lkh_flush
    mov rdi, rbx
    mov esi, eax
    call kh_fail
    jmp .Lkh_flush
3:  mov rdi, rbx
    cmp qword ptr [rbx + KH_mode], KP_EXTENSION
    jne 31f
    call kp_extension_start
    jmp 32f
31: call kp_target_start
32:
    cmp rax, -11
    je .Lkh_flush
    test rax, rax
    js .Lkh_start_failed
    or dword ptr [rbx + KH_flags], KP_STARTED
    mov qword ptr [rbx + KH_dirty], 1
    jmp .Lkh_flush
.Lkh_start_failed:
    mov rdi, rbx
    mov esi, eax
    call kh_fail
.Lkh_flush:
    test dword ptr [rbx + KH_flags], KP_DONE
    jz 41f
    mov rdi, rbx
    call kh_final_cleanup
41: mov rdi, rbx
    call kh_flush
    test dword ptr [rbx + KH_flags], KP_DONE
    jz 4f
    test rax, rax
    jnz .Lkh_finished
4:  test rax, rax
    jns 5f
    mov dword ptr [rbx + KH_eof], 1
    mov rdi, rbx
    mov esi, -32
    call kh_fail
5:  mov rdi, rbx
    call kp_helper_pause
    jmp .Lkh_loop
.Lkh_nomem:
    mov rax, -12
.Lkh_initial_fail:
    mov rdi, rbx
    mov esi, eax
    call kh_fail
    jmp .Lkh_flush
.Lkh_finished:
    mov rdi, rbx
    mov esi, 8
    call kh_close_field
    xor eax, eax
    cmp qword ptr [rbx + KH_cleanup], 0
    je 1f
    mov eax, 111
1:  EPILOGUE
.Lkh_not_helper:
    mov rax, -1
    EPILOGUE
.Lkh_bad_arguments:
    mov eax, 2
    EPILOGUE

# Complete frame control parsing. The current target argv/env remains in the immutable INIT body.
kh_control:
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rbx + KH_stopping], 0
    jne .Lkh_control_ok
    test dword ptr [rbx + KH_flags], KP_FAILED | KP_DONE
    jnz .Lkh_control_ok
    mov qword ptr [rsp], 65536
1:  cmp dword ptr [rbx + KH_start], 0
    jne .Lkh_control_alive
    mov rax, [rbx + KH_rxlen]
    mov rsi, [rbx + KH_frame]
    cmp qword ptr [rbx + KH_initialized], 0
    je 101f
    lea rsi, [rbx + KH_startframe]
101: add rsi, rax
    mov rdx, [rbx + KH_expected]
    sub rdx, rax
    cmp rdx, [rsp]
    jbe 2f
    mov rdx, [rsp]
2:  xor edi, edi
    SYS SYS_read
    cmp rax, -4
    je .Lkh_control_again
    cmp rax, -11
    je .Lkh_control_ok
    test rax, rax
    jle .Lkh_control_error
    sub [rsp], rax
    add [rbx + KH_rxlen], rax
    mov rax, [rbx + KH_rxlen]
    cmp rax, [rbx + KH_expected]
    jne 7f
    mov r12, [rbx + KH_frame]
    cmp qword ptr [rbx + KH_initialized], 0
    je 102f
    lea r12, [rbx + KH_startframe]
102: mov rax, 0x314c5443504b4852
    cmp [r12], rax
    jne .Lkh_control_bad
    mov rax, [rbx + KH_nonce]
    cmp [r12 + 8], rax
    jne .Lkh_control_bad
    cmp qword ptr [rbx + KH_initialized], 0
    jne 5f
    cmp dword ptr [r12 + 16], 1
    jne .Lkh_control_bad
    cmp qword ptr [rbx + KH_expected], 24
    jne 4f
    mov eax, [r12 + 20]
    cmp eax, 33
    jb .Lkh_control_bad
    cmp eax, KP_INIT_MAX
    ja .Lkh_control_bad
    add rax, 24
    mov [rbx + KH_expected], rax
    jmp 7f
4:  mov rdi, rbx
    call kh_parse
    test rax, rax
    js .Lkh_control_return
    mov qword ptr [rbx + KH_initialized], 1
    cmp qword ptr [rbx + KH_mode], KP_EXTENSION
    jne 41f
    mov qword ptr [rbx + KH_prepare_pending], 1
    jmp 42f
41: mov rdi, rbx
    call kp_target_prepare
    test rax, rax
    js .Lkh_control_return
42:
    mov qword ptr [rbx + KH_rxlen], 0
    mov qword ptr [rbx + KH_expected], 24
    jmp 7f
5:  cmp dword ptr [r12 + 16], 2
    jne .Lkh_control_bad
    test dword ptr [rbx + KH_flags], KP_READY
    jz .Lkh_control_bad
    cmp qword ptr [rbx + KH_mode], KP_EXTENSION
    je 51f
    cmp dword ptr [r12 + 20], 0
    jne .Lkh_control_bad
    jmp 54f
51: cmp dword ptr [r12 + 20], 168
    jne .Lkh_control_bad
    cmp qword ptr [rbx + KH_expected], 24
    jne 52f
    mov qword ptr [rbx + KH_expected], 192
    jmp 7f
52: mov rdi, [rbx + KH_authctx]
    lea rsi, [r12 + 24]
    mov rdx, [r12 + 184]
    call kp_extension_check_start
    test rax, rax
    js .Lkh_control_return
    lea rax, [r12 + 24]
    mov [rbx + KH_start_expected], rax
54: mov dword ptr [rbx + KH_start], 1
    jmp .Lkh_control_alive
7:  cmp qword ptr [rsp], 0
    jne 1b
.Lkh_control_ok:
    xor eax, eax
.Lkh_control_return:
    EPILOGUE
.Lkh_control_alive:
    mov rdi, rbx
    call kp_helper_alive
    EPILOGUE
.Lkh_control_again:
    mov rax, -11
    EPILOGUE
.Lkh_control_error:
    test rax, rax
    js .Lkh_control_return
    mov dword ptr [rbx + KH_eof], 1
    mov rax, -125
    EPILOGUE
.Lkh_control_bad:
    mov rax, -71
    EPILOGUE

# Final non-consuming availability check is represented by read: EAGAIN is live and empty.
# Any byte after START is invalid. EOF takes precedence over a buffered START in both modes.
FN kp_helper_alive
    PROLOGUE 16
    mov rbx, rdi
    test dword ptr [rbx + KH_flags], KP_STARTED
    jnz 11f
    call time_ms
    cmp rax, [rbx + KH_deadline]
    jb 11f
    mov rax, -110
    EPILOGUE
11:
    xor edi, edi
    mov rsi, rsp
    mov edx, 1
    SYS SYS_read
    cmp rax, -11
    je 1f
    cmp rax, -4
    je 2f
    test rax, rax
    jg 3f
    js 9f
    mov dword ptr [rbx + KH_eof], 1
    mov rax, -125
9:  EPILOGUE
1:  xor eax, eax
    EPILOGUE
2:  mov rax, -11
    EPILOGUE
3:  mov rax, -71
    EPILOGUE

# Preserve first failure; a closed-gate target is still owned until native lifetime proof.
kh_fail:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + KH_error], 0
    jne 1f
    mov [rbx + KH_error], esi
1:  or dword ptr [rbx + KH_flags], KP_FAILED
    mov qword ptr [rbx + KH_dirty], 1
    test dword ptr [rbx + KH_flags], KP_DONE
    jnz 9f
    mov rdi, rbx
    call kp_target_stop
9:  xor eax, eax
    EPILOGUE

# At most one partially sent and one latest status. Every write is bounded and nonblocking.
FN kh_flush
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + KH_txused], -1
    jne 2f
    cmp qword ptr [rbx + KH_dirty], 0
    je 6f
    lea rdi, [rbx + KH_tx]
    xor esi, esi
    mov edx, 64
    call memset
    mov rax, 0x31415453504b4852
    mov [rbx + KH_tx], rax
    mov rax, [rbx + KH_nonce]
    mov [rbx + KH_tx + 8], rax
    mov eax, [rbx + KH_flags]
    mov [rbx + KH_tx + 16], eax
    mov eax, [rbx + KH_error]
    mov [rbx + KH_tx + 20], eax
    mov eax, [rbx + KH_exit]
    mov [rbx + KH_tx + 24], eax
    mov eax, [rbx + KH_raw]
    mov [rbx + KH_tx + 28], eax
    mov rax, [rbx + KH_target]
    cmp qword ptr [rbx + KH_group_ready], 0
    jne 1f
    xor eax, eax
1:  mov [rbx + KH_tx + 32], rax
    mov eax, [rbx + KH_confined]
    mov [rbx + KH_tx + 40], eax
    mov eax, [rbx + KH_confine_reason]
    mov [rbx + KH_tx + 44], eax
    mov rax, [rbx + KH_context]
    mov [rbx + KH_tx + 48], rax
    mov qword ptr [rbx + KH_txused], 0
    mov qword ptr [rbx + KH_dirty], 0
2:  mov rax, [rbx + KH_txused]
    lea rsi, [rbx + KH_tx + rax]
    mov edx, 64
    sub rdx, rax
    mov edi, 1
    SYS SYS_write
    cmp rax, -11
    je 7f
    cmp rax, -4
    je 7f
    test rax, rax
    jle 8f
    add [rbx + KH_txused], rax
    cmp qword ptr [rbx + KH_txused], 64
    jne 7f
    mov qword ptr [rbx + KH_txused], -1
    cmp qword ptr [rbx + KH_dirty], 0
    jne 7f
6:  mov eax, 1
    EPILOGUE
7:  xor eax, eax
    EPILOGUE
8:  mov rax, -32
    EPILOGUE

# Framed vectors contain no pointer values. Cursor/end bounds precede every load.
# kh_vector(cursor,end,count,aggregateCap,envMode,outPointers) -> nextCursor/-errno.
kh_vector:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r9
    mov [rsp], r8
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
1:  mov rax, [rsp + 8]
    cmp rax, r13
    jae 6f
    lea rax, [rbx + 4]
    cmp rax, r12
    ja 8f
    mov eax, [rbx]
    test eax, eax
    jz 8f
    cmp rax, 16385
    jbe 2f
    cmp qword ptr [rsp], 0
    je 8f
2:  add [rsp + 16], rax
    cmp [rsp + 16], r14
    ja 8f
    mov [rsp + 24], rax
    add rbx, 4
    lea rdx, [rbx + rax]
    cmp rdx, r12
    ja 8f
    mov [rsp + 32], rdx
    cmp byte ptr [rdx - 1], 0
    jne 8f
    dec rax
    mov [rsp + 40], rax
    xor ecx, ecx
3:  cmp rcx, rax
    jae 4f
    cmp byte ptr [rbx + rcx], 0
    je 8f
    inc rcx
    jmp 3b
4:  cmp qword ptr [rsp], 0
    jne 41f
    cmp qword ptr [rsp + 8], 0
    jne 5f
    test rax, rax
    jz 8f
    jmp 5f
41:
.ifdef WINDOWS
    cmp byte ptr [rbx], '='
    jne 411f
    cmp rax, 4
    jb 8f
    cmp byte ptr [rbx + 2], ':'
    jne 8f
    cmp byte ptr [rbx + 3], '='
    jne 8f
    movzx ecx, byte ptr [rbx + 1]
    or ecx, 32
    sub ecx, 'a'
    cmp ecx, 25
    ja 8f
    jmp 5f
411:
.endif
    xor ecx, ecx
42: cmp rcx, rax
    jae 8f
    cmp byte ptr [rbx + rcx], '='
    je 43f
    inc rcx
    jmp 42b
43: test rcx, rcx
    jz 8f
5:  mov rdi, rbx
    mov rsi, [rsp + 40]
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    mov rax, [rsp + 8]
    mov [r15 + rax*8], rbx
    inc qword ptr [rsp + 8]
    mov rbx, [rsp + 32]
    jmp 1b
6:  mov rax, [rsp + 8]
    mov qword ptr [r15 + rax*8], 0
    mov rax, rbx
    EPILOGUE
8:  mov rax, -71
    EPILOGUE

kh_parse:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, [rbx + KH_frame]
    mov rax, [rbx + KH_expected]
    cmp rax, 58
    jb 8f
    lea r13, [r12 + rax]
    mov eax, [r12 + 36]
    cmp eax, KP_TASK
    je 701f
    cmp eax, KP_EXTENSION
    jne 7f
    cmp dword ptr [r12 + 32], 331
    jb 8f
    cmp dword ptr [r12 + 32], 49152
    ja 8f
    jmp 702f
701: cmp dword ptr [r12 + 32], 0
    jne 8f
702:
    cmp dword ptr [r12 + 44], 0
    jne 8f
    cmp qword ptr [r12 + 48], 0
    jne 8f
    mov eax, [r12 + 24]
    cmp eax, 2
    jb 8f
    cmp eax, 4096
    ja 8f
    lea r14, [r12 + 56]
    lea r15, [r14 + rax]
    cmp r15, r13
    ja 8f
    cmp byte ptr [r15 - 1], 0
    jne 8f
.ifndef WINDOWS
    cmp byte ptr [r14], '/'
    jne 8f
.endif
    mov rdi, r14
    mov rsi, rax
    dec rsi
    mov [rsp], rsi
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    xor ecx, ecx
1:  cmp rcx, [rsp]
    jae 2f
    cmp byte ptr [r14 + rcx], 0
    je 8f
    inc rcx
    jmp 1b
2:  mov [rbx + KH_cwd], r14
    mov eax, [r12 + 36]
    mov [rbx + KH_mode], rax
    mov edx, [r12 + 28]
    test edx, edx
    jz 8f
    cmp edx, 64
    ja 8f
    mov rdi, r15
    mov rsi, r13
    mov ecx, 65536
    xor r8d, r8d
    mov r9, [rbx + KH_argv]
    call kh_vector
    test rax, rax
    js 9f
    mov rdi, rax
    mov rsi, r13
    mov edx, [r12 + 40]
    cmp edx, 1024
    ja 8f
    mov ecx, 131072
    mov r8d, 1
    mov r9, [rbx + KH_envp]
    call kh_vector
    test rax, rax
    js 9f
    mov ecx, [r12 + 32]
    lea rdx, [rax + rcx]
    cmp rdx, r13
    jne 8f
    mov [rbx + KH_auth], rax
    mov [rbx + KH_auth_len], rcx
    xor eax, eax
9:  EPILOGUE
7:  mov rax, -95
    EPILOGUE
8:  mov rax, -71
    EPILOGUE
