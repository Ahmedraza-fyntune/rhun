# No display connection: production X11 wire code writes to an anonymous file.
.include "rhun.inc"
.section .rodata
.p2align 3
xw_builder_vectors:
    .quad 8,0,65535,0,0,24
    .quad 8,3,65535,0,1,24
    .quad 32,3,65535,0,1,24
    .quad 8,65512,65535,0,1,24
    .quad 8,65513,65535,0,1,24
    .quad 8,262116,65535,0,1,24
    .quad 8,262117,65537,1,1,28
    .quad 8,262117,65535,0,1,0
    .quad 8,262117,65536,1,1,0
    .quad 8,2097152,1048576,1,1,28
    .quad 8,3,7,0,1,24
    .quad 8,3,6,0,1,0
    .quad 8,0,5,0,0,0
    .quad 8,3,0,1,1,0
    .quad 16,3,65535,1,1,0
    .quad 8,1,65535,1,0,0
    .quad 8,67108865,4294967295,1,2,0
    .quad 32,16777217,4294967295,1,2,0
    .quad 32,18446744073709551615,4294967295,1,2,0
    .quad 8,18446744073709551615,4294967295,1,2,0
    .quad 32,0,6,0,0,24
    .quad 0
xw_queue_lengths: .quad 1,65535,65536,65537,262144,2097152,0
xw_prefix: .ascii "pre"
xw_suffix: .ascii "after"
xw_source: .ascii "owned"
xw_name: .asciz "rhun-x11-wire"
xw_ok: .asciz "ok X11 bounded wire requests\n"
.bss
.p2align 3
xw_payload: .quad 0
xw_guard: .quad 0
xw_expected: .zero SB_SIZE
.text

xw_reset:
    PROLOGUE
    mov edi, [rip + x_wire_fd]
    xor esi, esi
    SYS SYS_ftruncate
    test rax, rax
    js xw_failed
    mov edi, [rip + x_wire_fd]
    xor esi, esi
    xor edx, edx
    SYS SYS_lseek
    test rax, rax
    js xw_failed
    mov dword ptr [rip + x_wire_output_len], 0
    mov dword ptr [rip + x_wire_sequence], 0
    lea rdi, [rip + x_wire_input]
    mov rsi, [rip + xw_guard]
    mov edx, 262144
    call memcpy
    lea rdi, [rip + xw_expected]
    call sb_clear
    EPILOGUE

# Compare the complete flushed stream, sequence count, input guard and EOF.
xw_verify:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    cmp edx, [rip + x_wire_sequence]
    jne xw_failed
    cmp dword ptr [rip + x_wire_output_len], 65536
    ja xw_failed
    call x_flush
    cmp dword ptr [rip + x_wire_output_len], 0
    jne xw_failed
    lea rdi, [rip + x_wire_input]
    mov rsi, [rip + xw_guard]
    mov edx, 262144
    call memeq
    test eax, eax
    jz xw_failed
    mov edi, [rip + x_wire_fd]
    xor esi, esi
    xor edx, edx
    SYS SYS_lseek
    test rax, rax
    js xw_failed
    lea rdi, [r12 + 1]
    call mem_alloc
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r12
    jae 2f
    mov edi, [rip + x_wire_fd]
    lea rsi, [r13 + r14]
    mov rdx, r12
    sub rdx, r14
    SYS SYS_read
    test rax, rax
    jle xw_failed
    add r14, rax
    jmp 1b
2:  mov edi, [rip + x_wire_fd]
    lea rsi, [rsp]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jnz xw_failed
    mov rdi, r13
    mov rsi, rbx
    mov rdx, r12
    call memeq
    test eax, eax
    jz xw_failed
    mov rdi, r13
    call mem_free
    EPILOGUE

xw_expected_push:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + xw_expected]
    jmp sb_push
xw_prefix_queue:
    lea rdi, [rip + xw_prefix]
    mov esi, 3
    jmp x_req_raw
xw_prefix_expected:
    lea rdi, [rip + xw_prefix]
    mov esi, 3
    jmp xw_expected_push
xw_expected_verify:
    mov rdi, [rip + xw_expected + SB_ptr]
    mov rsi, [rip + xw_expected + SB_len]
    jmp xw_verify

FN main
    PROLOGUE 80
    mov r15d, 1
    lea rdi, [rip + xw_name]
    mov esi, 1
    SYS 319                    # memfd_create, MFD_CLOEXEC
    test rax, rax
    js xw_failed
    mov [rip + x_wire_fd], eax
    mov edi, 2097152
    call mem_alloc
    mov [rip + xw_payload], rax
    xor ecx, ecx
1:  mov byte ptr [rax + rcx], cl
    inc ecx
    cmp ecx, 2097152
    jb 1b
    mov edi, 262144
    call mem_alloc
    mov [rip + xw_guard], rax
    mov rdi, rax
    mov esi, 0xa5
    mov edx, 262144
    call memset
    lea rdi, [rip + xw_expected]
    mov esi, 2097216
    call sb_reserve
    mov rax, [rip + g_mem_live]
    mov [rsp + 64], rax

    lea r12, [rip + xw_queue_lengths]
.Lxw_queue:
    mov r14, [r12]
    test r14, r14
    jz .Lxw_queue_order
    call xw_reset
    mov rdi, [rip + xw_payload]
    mov rsi, r14
    call x_req
    xor eax, eax
    cmp r14, 65536
    cmovbe rax, r14
    cmp eax, [rip + x_wire_output_len]
    jne xw_failed
    mov rdi, [rip + xw_payload]
    mov rsi, r14
    mov edx, 1
    call xw_verify
    mov rax, [rsp + 64]
    cmp rax, [rip + g_mem_live]
    jne xw_failed
    add r12, 8
    inc r15
    jmp .Lxw_queue
.Lxw_queue_order:
    mov r15d, 20
    call xw_reset
    mov rdi, [rip + xw_payload]
    mov esi, 65535
    call x_req
    mov rdi, [rip + xw_payload]
    add rdi, 65535
    mov esi, 2
    call x_req
    cmp dword ptr [rip + x_wire_output_len], 2
    jne xw_failed
    mov rdi, [rip + xw_payload]
    mov esi, 65537
    mov edx, 2
    call xw_verify
    inc r15
    call xw_reset
    call xw_prefix_queue
    xor edi, edi
    xor esi, esi
    call x_req_raw
    cmp dword ptr [rip + x_wire_output_len], 3
    jne xw_failed
    mov rdi, [rip + xw_payload]
    mov esi, 2097152
    call x_req
    lea rdi, [rip + xw_suffix]
    mov esi, 5
    call x_req
    call xw_prefix_expected
    mov rdi, [rip + xw_payload]
    mov esi, 2097152
    call xw_expected_push
    lea rdi, [rip + xw_suffix]
    mov esi, 5
    call xw_expected_push
    mov edx, 2
    call xw_expected_verify
    inc r15
    call xw_reset
    mov rdi, [rip + xw_payload]
    mov esi, 131073
    call x_req_raw
    mov rdi, [rip + xw_payload]
    mov esi, 131073
    xor edx, edx
    call xw_verify

    lea r12, [rip + xw_builder_vectors]
    mov r15d, 100
.Lxw_builder:
    cmp qword ptr [r12], 0
    je .Lxw_owned
    call xw_reset
    mov eax, [r12 + 16]
    mov [rip + x_wire_max_request], eax
    mov eax, [r12 + 24]
    mov [rip + x_wire_big_requests], eax
    mov edi, 0x11223344
    mov esi, 0x55667788
    mov edx, 0x99aabbcc
    mov ecx, [r12]
    mov r8, [r12 + 32]
    cmp r8, 1
    jne 1f
    mov r8, [rip + xw_payload]
    jmp 2f
1:  cmp r8, 2
    jne 2f
    mov r8d, 1
2:  mov r9, [r12 + 8]
    call x_property_request
    cmp qword ptr [r12 + 40], 0
    je .Lxw_builder_reject
    test rax, rax
    jz xw_failed
    mov r13, rax
    mov r14, rdx
    cmp byte ptr [r13], 18
    jne xw_failed
    cmp byte ptr [r13 + 1], 0
    jne xw_failed
    mov rbx, r13
    mov rax, r14
    shr rax, 2
    cmp qword ptr [r12 + 40], 24
    jne .Lxw_builder_big
    cmp [r13 + 2], ax
    jne xw_failed
    jmp .Lxw_builder_fields
.Lxw_builder_big:
    cmp word ptr [r13 + 2], 0
    jne xw_failed
    cmp [r13 + 4], eax
    jne xw_failed
    add rbx, 4
.Lxw_builder_fields:
    cmp dword ptr [rbx + 4], 0x11223344
    jne xw_failed
    cmp dword ptr [rbx + 8], 0x55667788
    jne xw_failed
    cmp dword ptr [rbx + 12], 0x99aabbcc
    jne xw_failed
    mov eax, [r12]
    cmp [rbx + 16], al
    jne xw_failed
    cmp byte ptr [rbx + 17], 0
    jne xw_failed
    cmp word ptr [rbx + 18], 0
    jne xw_failed
    mov rdx, [r12 + 8]
    cmp [rbx + 20], edx
    jne xw_failed
    cmp qword ptr [r12], 32
    jne 1f
    shl rdx, 2
1:  mov [rsp], rdx
    mov rdi, r13
    add rdi, [r12 + 40]
    mov rsi, [rip + xw_payload]
    call memeq
    test eax, eax
    jz xw_failed
    mov rax, [rsp]
    add rax, [r12 + 40]
    mov rdx, [rsp]
    add rdx, 3
    and rdx, -4
    add rdx, [r12 + 40]
    cmp r14, rdx
    jne xw_failed
1:  cmp rax, r14
    jae 2f
    cmp byte ptr [r13 + rax], 0
    jne xw_failed
    inc rax
    jmp 1b
2:  mov rdi, r13
    mov rsi, r14
    call x_req
    mov rdi, r13
    mov rsi, r14
    mov edx, 1
    call xw_verify
    mov rdi, r13
    call mem_free
    jmp .Lxw_builder_next
.Lxw_builder_reject:
    test rax, rax
    jnz xw_failed
    test rdx, rdx
    jnz xw_failed
    cmp dword ptr [rip + x_wire_sequence], 0
    jne xw_failed
    cmp dword ptr [rip + x_wire_output_len], 0
    jne xw_failed
.Lxw_builder_next:
    mov rax, [rsp + 64]
    cmp rax, [rip + g_mem_live]
    jne xw_failed
    add r12, 48
    inc r15
    jmp .Lxw_builder

.Lxw_owned:
    mov r15d, 150
    call xw_reset
    mov dword ptr [rip + x_wire_max_request], 65535
    mov dword ptr [rip + x_wire_big_requests], 0
    lea rdi, [rip + xw_source]
    mov esi, 5
    call mem_dup
    mov rbx, rax
    mov edi, 1
    mov esi, 2
    mov edx, 3
    mov ecx, 8
    mov r8, rbx
    mov r9d, 5
    call x_property_request
    test rax, rax
    jz xw_failed
    mov r13, rax
    mov rdi, rbx
    call mem_free
    lea rdi, [r13 + 24]
    lea rsi, [rip + xw_source]
    mov edx, 5
    call memeq
    test eax, eax
    jz xw_failed
    mov rdi, r13
    call mem_free

    # Wrapper rejection must preserve an already queued prefix and its sequence.
    inc r15
    call xw_reset
    call xw_prefix_queue
    mov dword ptr [rip + x_wire_max_request], 0
    mov edi, 1
    mov esi, 2
    mov edx, 3
    mov ecx, 8
    mov r8, [rip + xw_payload]
    mov r9d, 3
    call x_change_prop
    test eax, eax
    jnz xw_failed
    cmp dword ptr [rip + x_wire_output_len], 3
    jne xw_failed
    lea rdi, [rip + xw_prefix]
    mov esi, 3
    xor edx, edx
    call xw_verify

    # Success may borrow the queued prefix as payload, but owns it before queue mutation.
    inc r15
    call xw_reset
    call xw_prefix_queue
    mov dword ptr [rip + x_wire_max_request], 65535
    mov edi, 1
    mov esi, 2
    mov edx, 3
    mov ecx, 8
    lea r8, [rip + xw_prefix]
    mov r9d, 3
    call x_property_request
    mov r13, rax
    mov r14, rdx
    test rax, rax
    jz xw_failed
    call xw_prefix_expected
    mov rdi, r13
    mov rsi, r14
    call xw_expected_push
    mov edi, 1
    mov esi, 2
    mov edx, 3
    mov ecx, 8
    lea r8, [rip + x_wire_output]
    mov r9d, 3
    call x_change_prop
    cmp eax, 1
    jne xw_failed
    mov edx, 1
    call xw_expected_verify
    mov rdi, r13
    call mem_free

.Lxw_done:
    mov qword ptr [rip + x_wire_clipboard + SB_ptr], 0
    mov qword ptr [rip + x_wire_clipboard + SB_len], 0
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    mov dword ptr [rip + x_wire_fd], -1
    mov rdi, [rip + xw_payload]
    call mem_free
    mov rdi, [rip + xw_guard]
    call mem_free
    lea rdi, [rip + xw_expected]
    call sb_free
    cmp qword ptr [rip + g_mem_live], 0
    jne xw_failed
    lea rdi, [rip + xw_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
xw_failed:
    mov edi, r15d
    SYS SYS_exit
