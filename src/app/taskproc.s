# Parent side of the gated process service. All process lifetime waits are nonblocking.
.include "rhun.inc"
.include "app/taskproc.inc"
.bss
.p2align 4
kp_slots: .zero KX_SIZE * KP_MAX
kp_serial: .quad 0
.text
FN kp_find
    test rdi, rdi
    jle 8f
    lea rax, [rip + kp_slots]
    mov ecx, KP_MAX
1:  cmp [rax + KX_id], rdi
    je 9f
    add rax, KX_SIZE
    dec ecx
    jnz 1b
8:  xor eax, eax
9:  ret

# Bounded C string length excluding NUL, or -EINVAL. Borrowed pointers must be readable.
kp_length:
    test rdi, rdi
    jz 8f
    xor eax, eax
1:  cmp byte ptr [rdi + rax], 0
    je 9f
    cmp rax, rsi
    jae 8f
    inc rax
    jmp 1b
8:  mov rax, -22
9:  ret

# Serialize a bounded pointer vector as u32 length plus UTF8 bytes including NUL.
# kp_vector(out, vector, maximumCount, aggregateCap, envMode) -> bytes/-errno, rdx count.
kp_vector:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    test r12, r12
    jz .Lkp_vector_invalid
1:  mov rcx, [rsp + 8]
    mov r15, [r12 + rcx*8]
    test r15, r15
    jz 6f
    cmp rcx, r13
    jae .Lkp_vector_big
    mov rdi, r15
    mov esi, 16384
    cmp qword ptr [rsp], 0
    je 2f
    mov esi, 131071
2:  call kp_length
    test rax, rax
    js .Lkp_vector_invalid
    mov [rsp + 24], rax
    cmp qword ptr [rsp], 0
    jne 21f
    cmp qword ptr [rsp + 8], 0
    jne 3f
    test rax, rax
    jz .Lkp_vector_invalid
    jmp 3f
21: test rax, rax
    jz .Lkp_vector_invalid
.ifdef WINDOWS
    cmp byte ptr [r15], '='
    jne 211f
    cmp rax, 4
    jb .Lkp_vector_invalid
    cmp byte ptr [r15 + 2], ':'
    jne .Lkp_vector_invalid
    cmp byte ptr [r15 + 3], '='
    jne .Lkp_vector_invalid
    movzx ecx, byte ptr [r15 + 1]
    or ecx, 32
    sub ecx, 'a'
    cmp ecx, 25
    ja .Lkp_vector_invalid
    jmp 3f
211:
.endif
    xor ecx, ecx
22: cmp rcx, rax
    jae .Lkp_vector_invalid
    cmp byte ptr [r15 + rcx], '='
    je 23f
    inc rcx
    jmp 22b
23: test rcx, rcx
    jz .Lkp_vector_invalid
3:  mov rdi, r15
    mov rsi, [rsp + 24]
    call snippet_utf8_valid
    test eax, eax
    jz .Lkp_vector_invalid
    mov rax, [rsp + 24]
    inc rax
    add [rsp + 16], rax
    cmp [rsp + 16], r14
    ja .Lkp_vector_big
    mov [rbx], eax
    lea rdi, [rbx + 4]
    mov rsi, r15
    mov rdx, rax
    call memcpy
    mov rax, [rsp + 24]
    lea rbx, [rbx + rax + 5]
    inc qword ptr [rsp + 8]
    jmp 1b
6:  mov rax, [rsp + 8]
    lea rax, [rax*4]
    add rax, [rsp + 16]
    mov rdx, [rsp + 8]
    EPILOGUE
.Lkp_vector_big:
    mov rax, -7
    xor edx, edx
    EPILOGUE
.Lkp_vector_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# Prepare owns a slot as soon as an OS child exists, including all setup failure paths.
FN keeper_prepare
    PROLOGUE 48
    mov r12, rdi
    test r12, r12
    jz .Lkp_prepare_invalid
    cmp qword ptr [r12 + KP_mode], KP_TASK
    je 101f
    cmp qword ptr [r12 + KP_mode], KP_EXTENSION
    jne .Lkp_prepare_unsupported
    cmp qword ptr [r12 + KP_auth], 0
    je .Lkp_prepare_invalid
    cmp qword ptr [r12 + KP_auth_len], 331
    jb .Lkp_prepare_invalid
    cmp qword ptr [r12 + KP_auth_len], 49152
    ja .Lkp_prepare_invalid
    jmp 102f
101: cmp qword ptr [r12 + KP_auth_len], 0
    jne .Lkp_prepare_invalid
102:
    mov rax, [r12 + KP_stdout]
    xor rax, [r12 + KP_stderr]
    # Capture must apply to both channels. Supplied descriptors can differ.
    cmp qword ptr [r12 + KP_stdout], -1
    je 1f
    cmp qword ptr [r12 + KP_stderr], -1
    je .Lkp_prepare_invalid
    jmp 2f
1:  cmp qword ptr [r12 + KP_stderr], -1
    jne .Lkp_prepare_invalid
2:  lea rax, [rip + kp_slots]
    mov ecx, KP_MAX
    xor edx, edx
21: cmp qword ptr [rax + KX_id], 0
    je 22f
    mov rsi, [r12 + KP_mode]
    cmp [rax + KX_mode], rsi
    jne 22f
    inc edx
22: add rax, KX_SIZE
    dec ecx
    jnz 21b
    mov ecx, KP_TASK_MAX
    cmp qword ptr [r12 + KP_mode], KP_TASK
    je 221f
    mov ecx, KP_EXTENSION_MAX
221: cmp edx, ecx
    jb 23f
    mov rax, -11
    jmp .Lkp_prepare_clean_error
23: mov rax, 0x7fffffffffffffff
    cmp [rip + kp_serial], rax
    jae .Lkp_prepare_overflow
    lea rbx, [rip + kp_slots]
    mov ecx, KP_MAX
3:  cmp qword ptr [rbx + KX_id], 0
    je 4f
    add rbx, KX_SIZE
    dec ecx
    jnz 3b
    mov rax, -11
    jmp .Lkp_prepare_clean_error
4:  mov rdi, rbx
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    mov qword ptr [rbx + KX_control], -1
    mov qword ptr [rbx + KX_status], -1
    mov qword ptr [rbx + KX_output], -1
    mov qword ptr [rbx + KX_launchfd], -1
    mov dword ptr [rbx + KX_exit], -1
    mov qword ptr [rbx + KX_lease], -1
    mov rax, [r12 + KP_mode]
    mov [rbx + KX_mode], rax
    lea rdi, [rbx + KX_native]
    call kp_native_init
    mov edi, KP_FRAME_MAX
    call mem_alloc_try
    test rax, rax
    jz .Lkp_prepare_nomem
    mov [rbx + KX_frame], rax
    inc qword ptr [rip + kp_serial]
    mov rdx, [rip + kp_serial]
    mov [rbx + KX_id], rdx
    mov r13, rax
    xor esi, esi
    mov rdi, r13
    mov edx, 56
    call memset
    mov rax, 0x314c5443504b4852
    mov [r13], rax
    mov dword ptr [r13 + 16], 1
    mov eax, [r12 + KP_mode]
    mov [r13 + 36], eax
    mov rdi, [r12 + KP_cwd]
    mov esi, 4095
    call kp_length
    test rax, rax
    jle .Lkp_prepare_invalid_owned
    mov r15, rax
.ifndef WINDOWS
    mov rdi, [r12 + KP_cwd]
    cmp byte ptr [rdi], '/'
    jne .Lkp_prepare_invalid_owned
.endif
    mov rdi, [r12 + KP_cwd]
    mov rsi, r15
    call snippet_utf8_valid
    test eax, eax
    jz .Lkp_prepare_invalid_owned
    inc r15
    mov [r13 + 24], r15d
    lea rdi, [r13 + 56]
    mov rsi, [r12 + KP_cwd]
    mov rdx, r15
    call memcpy
    lea r14, [r13 + r15 + 56]
    mov rdi, r14
    mov rsi, [r12 + KP_argv]
    mov edx, 64
    mov ecx, 65536
    xor r8d, r8d
    call kp_vector
    test rax, rax
    js .Lkp_prepare_fail_owned
    test rdx, rdx
    jz .Lkp_prepare_invalid_owned
    mov [r13 + 28], edx
    add r14, rax
    mov rsi, [r12 + KP_envp]
    test rsi, rsi
    jnz 5f
    mov rsi, [rip + g_envp]
5:  mov rdi, r14
    mov edx, 1024
    mov ecx, 131072
    mov r8d, 1
    call kp_vector
    test rax, rax
    js .Lkp_prepare_fail_owned
    mov [r13 + 40], edx
    add r14, rax
    cmp qword ptr [r12 + KP_mode], KP_EXTENSION
    jne 501f
    mov rax, r14
    sub rax, r13
    add rax, [r12 + KP_auth_len]
    cmp rax, KP_FRAME_MAX
    ja .Lkp_prepare_big_owned
    mov rdi, r14
    mov rsi, [r12 + KP_auth]
    mov rdx, [r12 + KP_auth_len]
    call memcpy
    mov eax, [r12 + KP_auth_len]
    mov [r13 + 32], eax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call kp_parent_auth_attach
    test rax, rax
    js .Lkp_prepare_fail_owned
    add r14, [r12 + KP_auth_len]
501: sub r14, r13
    cmp r14, KP_FRAME_MAX
    ja .Lkp_prepare_big_owned
    mov [rbx + KX_length], r14
    lea rax, [r14 - 24]
    mov [r13 + 20], eax
    mov rax, [rbx + KX_id]
    mov [r13 + 8], rax
    mov rdi, rbx
    mov rsi, r12
    call kp_backend_prepare
    mov r15, rax
    mov rdi, rbx
    mov rsi, rdx
    call kp_note_cleanup
    test r15, r15
    js 502f
    cmp qword ptr [rbx + KX_cleanup], 0
    jne 503f
    mov rax, [rbx + KX_id]
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
503: mov r15, [rbx + KX_cleanup]
502: mov rax, r15
    jmp .Lkp_prepare_fail_owned
.Lkp_prepare_big_owned:
    mov rax, -7
    jmp .Lkp_prepare_fail_owned
.Lkp_prepare_invalid_owned:
    mov rax, -22
.Lkp_prepare_fail_owned:
    mov r15, rax
    mov [rbx + KX_error], eax
    # Backend scratch has already received its one cleanup pass this operation.
    xor edx, edx
    xor ecx, ecx
910: or rdx, [rbx + rcx*8 + KX_native + KB_mem]
    inc ecx
    cmp ecx, 8
    jb 910b
    test rdx, rdx
    jz 9101f
    mov qword ptr [rbx + KX_cleanup_skip_once], 1
    mov qword ptr [rbx + KX_retry_delay], 16
    call time_ms
    add rax, 16
    mov [rbx + KX_retry_due], rax
9101:
    mov qword ptr [rbx + KX_prepare_failed], 1
    mov qword ptr [rbx + KX_transport_bad], 1
    mov qword ptr [rbx + KX_no_target], 1
    or dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
    cmp qword ptr [rbx + KX_native_state], KN_NONE
    jne 911f
    mov dword ptr [rbx + KX_reaped], 1
    mov qword ptr [rbx + KX_status_eof], 1
    mov qword ptr [rbx + KX_lifetime_ready], 1
    or dword ptr [rbx + KX_flags], KP_DONE
    mov r12, [rbx + KX_id]
    mov rdi, r12
    call keeper_close_checked
    mov r14, rax
    cmp rdx, 1
    je 912f
    mov rax, r12
    mov rdx, r15
    mov rcx, [rbx + KX_cleanup]
    EPILOGUE
911: mov rdi, rbx
    call kp_backend_abort
    mov rax, [rbx + KX_id]
    mov rdx, r15
    mov rcx, [rbx + KX_cleanup]
    EPILOGUE
912: mov rax, r15
    xor edx, edx
    mov rcx, r14
    EPILOGUE
.Lkp_prepare_nomem:
    mov rax, -12
    jmp .Lkp_prepare_clean_error
.Lkp_prepare_invalid:
    mov rax, -22
    jmp .Lkp_prepare_clean_error
.Lkp_prepare_unsupported:
    mov rax, -95
    jmp .Lkp_prepare_clean_error
.Lkp_prepare_overflow:
    mov rax, -75
    jmp .Lkp_prepare_clean_error

# No owned resource ever existed on these refusals: both cleanup outputs are empty.
.Lkp_prepare_clean_error:
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

FN keeper_stop
    PROLOGUE
    call kp_find
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rbx
    xor esi, esi
    call kp_close_field
    test rax, rax
    jns 9f
    or dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
    mov qword ptr [rbx + KX_transport_bad], 1
9:  EPILOGUE
8:  mov rax, -2
    xor edx, edx
    EPILOGUE

# Never queues a START. A short write closes control and becomes a permanent service failure.
FN keeper_start
    PROLOGUE 32
    call kp_find
    test rax, rax
    jz .Lkp_start_missing
    mov rbx, rax
    cmp qword ptr [rbx + KX_mode], KP_TASK
    jne .Lkp_start_unsupported
    cmp qword ptr [rax + KX_accepted], 0
    jne .Lkp_start_already
    test dword ptr [rax + KX_flags], KP_FAILED | KP_DONE | KP_DEFERRED
    jnz .Lkp_start_bad
    test dword ptr [rax + KX_flags], KP_READY
    jz .Lkp_start_again
    mov rdi, [rax + KX_control]
    test rdi, rdi
    js .Lkp_start_bad
    mov rax, 0x314c5443504b4852
    mov [rsp], rax
    mov rax, [rbx + KX_id]
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], 2
    mov rsi, rsp
    mov edx, 24
    SYS SYS_write
    cmp rax, 24
    je .Lkp_start_ok
    cmp rax, -11
    je .Lkp_start_again
    cmp rax, -4
    je .Lkp_start_again
    test rax, rax
    js 1f
    mov rax, -5
1:  mov [rbx + KX_error], eax
    or dword ptr [rbx + KX_flags], KP_FAILED
    mov rdi, [rbx + KX_id]
    call keeper_stop
.Lkp_start_bad:
    movsxd rax, dword ptr [rbx + KX_error]
    test rax, rax
    js 2f
    mov rax, -5
2:  EPILOGUE
.Lkp_start_again:
    xor eax, eax
    EPILOGUE
.Lkp_start_ok:
    mov qword ptr [rbx + KX_accepted], 1
.Lkp_start_already:
    mov eax, 1
    EPILOGUE
.Lkp_start_unsupported:
    mov rax, -95
    EPILOGUE
.Lkp_start_missing:
    mov rax, -2
    EPILOGUE

FN keeper_read
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    test rbx, rbx
    jz 7f
    test r12, r12
    jz 7f
    cmp r12, 65536
    ja 7f
    call kp_find
    test rax, rax
    jz 8f
    mov r13, rax
    test qword ptr [rax + KX_close_unknown], 4
    jnz 61f
    test qword ptr [rax + KX_close_known], 4
    jnz 61f
    cmp qword ptr [rax + KX_prepare_failed], 0
    jne 61f
    mov rdi, [rax + KX_output]
    test rdi, rdi
    js 6f
    mov rsi, rbx
    mov rdx, r12
    SYS SYS_read
    EPILOGUE
6:  mov rax, -95
    EPILOGUE
61: mov rax, [r13 + KX_cleanup]
    test rax, rax
    js 62f
    movsxd rax, dword ptr [r13 + KX_error]
    test rax, rax
    js 62f
    mov rax, -32
62: EPILOGUE
7:  mov rax, -22
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# Internal transport failure retains lifetime ownership and closes the only control writer.
kp_parent_fail:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + KX_error], 0
    jne 1f
    mov [rbx + KX_error], esi
1:  or dword ptr [rbx + KX_flags], KP_FAILED
    # An earlier NO_TARGET frame is not a promise about subsequent creation.
    cmp qword ptr [rbx + KX_prepare_failed], 0
    jne 2f
    cmp qword ptr [rbx + KX_preexec_failed], 0
    jne 2f
    mov qword ptr [rbx + KX_no_target], 0
2:  mov rdi, [rbx + KX_id]
    call keeper_stop
    EPILOGUE

# Decode one complete private status frame. No unvalidated field reaches recovery state.
kp_status:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rbx + KX_rx]
    mov rax, 0x31415453504b4852
    cmp [r12], rax
    jne 8f
    mov rax, [rbx + KX_id]
    cmp [r12 + 8], rax
    jne 8f
    mov eax, [r12 + 16]
    test eax, -128
    jnz 8f
    mov edx, [rbx + KX_flags]
    # Parent may have latched its own FAILED/DEFERRED independently of helper frames.
    and edx, KP_READY | KP_STARTED | KP_DONE | KP_EXIT_KNOWN | KP_CREATING
    mov ecx, eax
    and ecx, edx
    cmp ecx, edx
    jne 8f
    test eax, KP_STARTED
    jz 1f
    test eax, KP_READY
    jz 8f
    cmp qword ptr [rbx + KX_accepted], 0
    je 8f
1:  mov edx, [r12 + 20]
    test eax, KP_FAILED
    jz 2f
    cmp edx, -1
    jg 8f
    cmp edx, -4095
    jl 8f
    jmp 3f
2:  test edx, edx
    jnz 8f
3:  cmp qword ptr [r12 + 56], 0
    jne 8f
    cmp qword ptr [rbx + KX_mode], KP_EXTENSION
    je 301f
    cmp qword ptr [r12 + 40], 0
    jne 8f
    cmp qword ptr [r12 + 48], 0
    jne 8f
    test eax, KP_CREATING
    jnz 8f
    jmp 304f
301: cmp dword ptr [r12 + 40], CONFINED_TCP
    ja 8f
    cmp dword ptr [r12 + 44], EXITC_SANDBOX
    ja 8f
    mov rcx, [r12 + 48]
    test rcx, rcx
    jz 302f
    cmp rcx, [rbx + KX_context]
    jne 8f
    jmp 303f
302: test eax, KP_CREATING | KP_READY | KP_STARTED
    jnz 8f
303: test eax, KP_READY
    jz 304f
    test eax, KP_CREATING
    jz 8f
304:
    mov rdx, [r12 + 32]
    test eax, KP_READY
    jz 4f
    test rdx, rdx
    jle 8f
.ifdef WINDOWS
    mov rcx, 0xffffffff
    cmp rdx, rcx
.else
    cmp rdx, 0x7fffffff
.endif
    ja 8f
4:  mov rcx, [rbx + KX_target]
    test rcx, rcx
    jz 5f
    cmp rdx, rcx
    jne 8f
5:  test eax, KP_DONE | KP_EXIT_KNOWN
    jz 51f
    cmp dword ptr [r12 + 24], 255
    ja 8f
    jmp 6f
51: cmp dword ptr [r12 + 24], -1
    jne 8f
6:  test dword ptr [rbx + KX_wireflags], KP_DONE
    jz 61f
    mov r13d, eax
    mov r14, rdx
    lea rdi, [rbx + KX_lastframe]
    mov rsi, r12
    mov edx, 64
    call memeq
    test eax, eax
    jz 8f
    mov eax, r13d
    mov rdx, r14
61: mov [rbx + KX_wireflags], eax
    or [rbx + KX_flags], eax
    cmp qword ptr [rbx + KX_mode], KP_EXTENSION
    jne 62f
    test eax, KP_CREATING
    jz 611f
    mov qword ptr [rbx + KX_no_target], 0
    jmp 612f
611: mov qword ptr [rbx + KX_no_target], 1
612: mov ecx, [r12 + 40]
    mov [rbx + KX_confined], ecx
    mov ecx, [r12 + 44]
    mov [rbx + KX_confine_reason], ecx
62:
    mov eax, [r12 + 24]
    mov [rbx + KX_exit], eax
    mov eax, [r12 + 28]
    mov [rbx + KX_raw], eax
    mov [rbx + KX_target], rdx
    cmp dword ptr [rbx + KX_error], 0
    jne 7f
    mov eax, [r12 + 20]
    mov [rbx + KX_error], eax
7:  lea rdi, [rbx + KX_lastframe]
    mov rsi, r12
    mov edx, 64
    call memcpy
    xor eax, eax
    EPILOGUE
8:  mov rax, -71
    EPILOGUE

# keeper_poll(handle) -> cumulative flags, edx normalized exit, r8d errno, r9d raw exit.
FN keeper_poll
    PROLOGUE 16
    call kp_find
    test rax, rax
    jz .Lkp_poll_missing
    mov rbx, rax
    cmp qword ptr [rbx + KX_lifetime_ready], 0
    jne .Lkp_poll_result
    cmp qword ptr [rbx + KX_native_state], KN_NONE
    je .Lkp_poll_result
    cmp qword ptr [rbx + KX_prepare_failed], 0
    jne .Lkp_poll_status
    test dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
    jnz .Lkp_poll_status
    mov rdi, [rbx + KX_control]
    test rdi, rdi
    js .Lkp_poll_status
    mov rax, [rbx + KX_sent]
    cmp rax, [rbx + KX_length]
    jae .Lkp_poll_status
    mov rsi, [rbx + KX_frame]
    add rsi, rax
    mov rdx, [rbx + KX_length]
    sub rdx, rax
    cmp rdx, 65536
    jbe 1f
    mov edx, 65536
1:  SYS SYS_write
    test rax, rax
    jg 2f
    cmp rax, -11
    je .Lkp_poll_status
    cmp rax, -4
    je .Lkp_poll_status
    test rax, rax
    js 11f
    mov rax, -5
11: mov rdi, rbx
    mov esi, eax
    call kp_parent_fail
    jmp .Lkp_poll_status
2:  add [rbx + KX_sent], rax
.Lkp_poll_status:
    mov qword ptr [rsp], 4096
3:  cmp qword ptr [rbx + KX_status_failed], 0
    jne .Lkp_poll_native
    test qword ptr [rbx + KX_close_unknown], 2
    jnz .Lkp_poll_native
    test qword ptr [rbx + KX_close_known], 2
    jnz .Lkp_poll_native
    cmp qword ptr [rsp], 0
    je .Lkp_poll_native
    cmp qword ptr [rbx + KX_status_eof], 0
    jne .Lkp_poll_native
    mov rax, [rbx + KX_rxlen]
    lea rsi, [rbx + KX_rx + rax]
    mov edx, 64
    sub rdx, rax
    mov rdi, [rbx + KX_status]
    SYS SYS_read
    cmp rax, -11
    je .Lkp_poll_native
    cmp rax, -4
    je .Lkp_poll_native
    test rax, rax
    jle 5f
    sub [rsp], rax
    add [rbx + KX_rxlen], rax
    cmp qword ptr [rbx + KX_rxlen], 64
    jne 3b
    mov rdi, rbx
    call kp_status
    mov qword ptr [rbx + KX_rxlen], 0
    test rax, rax
    jz 3b
    mov rdi, rbx
    mov esi, eax
    call kp_parent_fail
    or dword ptr [rbx + KX_flags], KP_DEFERRED
    mov qword ptr [rbx + KX_protocol_bad], 1
    jmp .Lkp_status_close_failed
5:  test rax, rax
    js .Lkp_status_read_failed
    # Only an actual zero-length read establishes status EOF.
    mov qword ptr [rbx + KX_status_eof], 1
    cmp qword ptr [rbx + KX_rxlen], 0
    je .Lkp_poll_native
    mov rax, -71
.Lkp_status_read_failed:
    mov rdi, rbx
    mov esi, eax
    call kp_parent_fail
    mov qword ptr [rbx + KX_protocol_bad], 1
.Lkp_status_close_failed:
    mov qword ptr [rbx + KX_transport_bad], 1
    mov qword ptr [rbx + KX_status_failed], 1
    mov rdi, rbx
    mov esi, 1
    call kp_close_field
.Lkp_poll_native:
    mov rdi, rbx
    call kp_backend_poll
    cmp dword ptr [rbx + KX_reaped], 0
    je .Lkp_poll_result
    mov rdi, rbx
    call kp_cleanup_terminal
    test eax, eax
    jz 201f
    mov qword ptr [rbx + KX_lifetime_ready], 1
    jmp .Lkp_poll_result
201: # A parent cleanup error cannot poison a healthy status stream still draining.
    cmp qword ptr [rbx + KX_status_eof], 0
    jne 202f
    cmp qword ptr [rbx + KX_status_failed], 0
    je .Lkp_poll_result
202: cmp qword ptr [rbx + KX_transport_bad], 0
    jne .Lkp_poll_recover
    cmp qword ptr [rbx + KX_status_eof], 0
    je .Lkp_poll_result
    test dword ptr [rbx + KX_flags], KP_DONE
    jz .Lkp_poll_recover
    cmp qword ptr [rbx + KX_protocol_bad], 0
    jne .Lkp_poll_recover
    cmp dword ptr [rbx + KX_helper_exit], 0
    je .Lkp_poll_result
.Lkp_poll_recover:
    mov qword ptr [rbx + KX_protocol_bad], 1
    mov rdi, rbx
    mov esi, -5
    call kp_parent_fail
    or dword ptr [rbx + KX_flags], KP_DEFERRED
    mov rdi, rbx
    call kp_backend_recover
    test eax, eax
    jz .Lkp_poll_result
    mov qword ptr [rbx + KX_recovered], 1
    mov qword ptr [rbx + KX_lifetime_ready], 1
    or dword ptr [rbx + KX_flags], KP_DONE
    test dword ptr [rbx + KX_flags], KP_EXIT_KNOWN
    jnz .Lkp_poll_result
    mov dword ptr [rbx + KX_exit], 255
    mov dword ptr [rbx + KX_raw], 0
.Lkp_poll_result:
    mov eax, [rbx + KX_flags]
    cmp qword ptr [rbx + KX_protocol_bad], 0
    je 61f
    cmp qword ptr [rbx + KX_recovered], 0
    je 7f
61: cmp qword ptr [rbx + KX_lifetime_ready], 0
    jne 8f
    cmp dword ptr [rbx + KX_reaped], 0
    je 7f
    cmp qword ptr [rbx + KX_status_eof], 0
    je 7f
    test eax, KP_DONE
    jz 7f
    mov qword ptr [rbx + KX_lifetime_ready], 1
    jmp 8f
7:  and eax, -5
8:  mov edx, [rbx + KX_exit]
    mov r8d, [rbx + KX_error]
    test r8d, r8d
    js 81f
    mov r8d, [rbx + KX_cleanup]
81: mov r9d, [rbx + KX_raw]
    EPILOGUE
.Lkp_poll_missing:
    mov rax, -2
    mov edx, -1
    mov r8d, -2
    xor r9d, r9d
    EPILOGUE

# Healthy callers drain capture first. Failed transport never fabricates EOF.
FN keeper_close_checked
    PROLOGUE 16
    mov r12, rdi
    call kp_find
    test rax, rax
    jz .Lkcc_missing
    mov rbx, rax
    cmp qword ptr [rbx + KX_lifetime_ready], 0
    jne 1f
    mov rdi, r12
    call keeper_poll
    cmp qword ptr [rbx + KX_lifetime_ready], 0
    je .Lkcc_busy
1:  mov qword ptr [rbx + KX_retiring], 1
    xor r13d, r13d
2:  mov rdi, rbx
    mov rsi, r13
    call kp_close_field
    inc r13
    cmp r13, 7
    jb 2b
    mov qword ptr [rsp], 0       # memory pass eligible unless its backoff is pending
    xor r14d, r14d
    xor ecx, ecx
21: or r14, [rbx + rcx*8 + KX_native + KB_mem]
    inc ecx
    cmp ecx, 8
    jb 21b
    or r14, [rbx + KX_frame]
    test r14, r14
    jz 3f
    cmp qword ptr [rbx + KX_retry_due], 0
    je 3f
    call time_ms
    cmp rax, [rbx + KX_retry_due]
    jae 3f
    mov qword ptr [rsp], 1
3:  cmp qword ptr [rbx + KX_cleanup_skip_once], 0
    je 301f
    mov qword ptr [rbx + KX_cleanup_skip_once], 0
    mov qword ptr [rsp], 1
301: lea rdi, [rbx + KX_native]
    mov rsi, [rsp]
    call kp_native_cleanup
    mov rdi, rbx
    mov rsi, rax
    call kp_note_cleanup
    cmp qword ptr [rsp], 0
    je 31f
    cmp qword ptr [rbx + KX_frame_cleanup_tried], 0
    jne 5f
31: mov rdi, [rbx + KX_frame]
    test rdi, rdi
    jz 5f
    mov qword ptr [rbx + KX_frame_cleanup_tried], 1
    call prep_cleanup_free
    mov rdi, rbx
    mov rsi, rax
    mov [rsp + 8], rdx
    call kp_note_cleanup
    cmp qword ptr [rsp + 8], 1
    jne 5f
    mov qword ptr [rbx + KX_frame], 0
5:  mov rdi, r12
    lea rsi, [rsp - 64]          # not used: inspect fixed slots locally below
    xor r14d, r14d
    xor ecx, ecx
6:  or r14, [rbx + rcx*8 + KX_native + KB_mem]
    inc ecx
    cmp ecx, 8
    jb 6b
    or r14, [rbx + KX_frame]
    test r14, r14
    jnz 61f
    mov qword ptr [rbx + KX_retry_due], 0
    mov qword ptr [rbx + KX_retry_delay], 0
    jmp 8f
61: cmp qword ptr [rsp], 0
    jne 8f
    mov rax, [rbx + KX_retry_delay]
    test rax, rax
    jnz 7f
    mov eax, 8
7:  add rax, rax
    cmp rax, 1000
    jbe 71f
    mov eax, 1000
71: mov [rbx + KX_retry_delay], rax
    mov r13, rax
    call time_ms
    add rax, r13
    mov [rbx + KX_retry_due], rax
8:  mov r13, [rbx + KX_close_unknown]
    or r13, [rbx + KX_native + KB_unknown]
    mov rax, [rbx + KX_close_known]
    or rax, [rbx + KX_native + KB_known]
    or r14, rax
    or r14, r13
    test r14, r14
    jnz .Lkcc_retained
    mov r12, [rbx + KX_cleanup]
    mov rdi, rbx
    xor esi, esi
    mov edx, KX_SIZE
    call memset
    mov rax, r12
    mov edx, 1
    EPILOGUE
.Lkcc_retained:
    mov rax, [rbx + KX_cleanup]
    test rax, rax
    js 9f
    mov rax, -16
9:  xor edx, edx
    test r13, r13
    jz 91f
    mov edx, 2
91: EPILOGUE
.Lkcc_busy:
    mov rax, -16
    xor edx, edx
    mov rcx, [rbx + KX_close_unknown]
    or rcx, [rbx + KX_native + KB_unknown]
    test rcx, rcx
    jz 92f
    mov edx, 2
92: EPILOGUE
.Lkcc_missing:
    mov rax, -2
    xor edx, edx
    EPILOGUE

# Old scalar ABI. New consumers must use checked status and consumed disposition.
FN keeper_close
    PROLOGUE
    call keeper_close_checked
    mov rcx, rax
    cmp rdx, 1
    jne 1f
    xor eax, eax
1:  EPILOGUE
