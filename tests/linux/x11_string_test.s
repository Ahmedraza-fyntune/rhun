.include "rhun.inc"
.include "plat/x11.inc"
.section .rodata
.p2align 3
# source, counted length, expected representation (nil means refusal), expected count
xs_vectors:
    .quad xs_ascii,5,xs_ascii,5
    .quad xs_latin,6,xs_encoded,3
    .quad 0,0,xs_ascii,0
    .quad 0,1,0,0
    .quad xs_ascii,67108865,0,0
    .quad xs_bad,1,0,0
    .quad xs_bad,2,0,0
    .quad xs_overlong,2,0,0
    .quad xs_truncated,1,0,0
    .quad xs_surrogate,3,0,0
    .quad xs_water,3,0,0
    .quad xs_nul,3,0,0
    .quad xs_replacement,3,0,0
    .quad -1
xs_ascii: .ascii "A\tB\nZ"
xs_latin: .byte 0xc2,0xa0,0xc3,0xa9,0xc3,0xbf
xs_encoded: .byte 0xa0,0xe9,0xff
xs_bad: .byte 0xff,0xff
xs_overlong: .byte 0xc0,0xa0
xs_truncated: .byte 0xc3
xs_surrogate: .byte 0xed,0xa0,0x80
xs_water: .byte 0xe6,0xb0,0xb4
xs_nul: .byte 0x41,0,0x42
xs_replacement: .byte 0xef,0xbf,0xbd
xs_name: .asciz "rhun-string"
xs_ok: .ascii "ok X11 legacy STRING conversion\n"
.bss
.p2align 3
xs_stage: .quad 0
xs_live: .quad 0
xs_encoded_cp: .zero 8
xs_event: .zero 32
xs_wire: .zero 128
.text
xs_fail:
    mov edi, [rip + xs_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  SYS SYS_exit_group

# Check pure supported/convert results, including terminator, input and output ownership.
xs_check:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    call x_string_supported
    xor edx, edx
    test r13, r13
    setnz dl
    cmp eax, edx
    jne xs_fail
    mov rdi, rbx
    mov rsi, r12
    call x_string_convert
    test r13, r13
    jz .Lxs_expect_bad
    test rax, rax
    jz xs_fail
    cmp rdx, r14
    jne xs_fail
    mov r15, rax
    cmp rax, rbx
    je xs_fail
    cmp byte ptr [r15 + r14], 0
    jne xs_fail
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call memeq
    test eax, eax
    jz xs_fail
    mov rdi, r15
    call mem_free
    jmp .Lxs_check_live
.Lxs_expect_bad:
    test rax, rax
    jnz xs_fail
    test rdx, rdx
    jnz xs_fail
.Lxs_check_live:
    mov rax, [rsp]
    cmp rax, [rip + g_mem_live]
    jne xs_fail
    EPILOGUE

# Real selection serving queues the exact property followed by its SelectionNotify.
# args: source, source length, target, expected data, expected count, expected type (0 refusal)
xs_serve:
    PROLOGUE 64
    mov [rip + x_wire_clipboard + SB_ptr], rdi
    mov [rip + x_wire_clipboard + SB_len], rsi
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    mov [rsp], edx
    mov r15, [rip + g_mem_live]
    mov dword ptr [rip + x_wire_sequence], 0
    mov dword ptr [rip + x_wire_output_len], 0
    lea rdi, [rip + xs_event]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rip + xs_event], 30
    mov dword ptr [rip + xs_event + 4], 0x111
    mov dword ptr [rip + xs_event + 8], 0x555
    mov dword ptr [rip + xs_event + 12], 0x222
    mov dword ptr [rip + xs_event + 16], 0x333
    mov eax, [rsp]
    mov [rip + xs_event + 20], eax
    mov dword ptr [rip + xs_event + 24], 0x444
    lea rdi, [rip + xs_event]
    call x_serve_selection
    test r14, r14
    jz .Lxs_serve_confirmed
    cmp dword ptr [rip + x_send_slots + XS_state], XS_INITIAL
    jne xs_fail
    cmp dword ptr [rip + x_send_slots + XS_notified], 0
    jne xs_fail
    lea rdi, [rsp + 8]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp + 8], 1
    mov eax, [rip + x_send_slots + XS_fence_seq]
    mov [rsp + 10], ax
    lea rdi, [rsp + 8]
    mov esi, 32
    call x_send_reply
    cmp eax, 1
    jne xs_fail
.Lxs_serve_confirmed:
    cmp r15, [rip + g_mem_live]
    jne xs_fail
    lea rbx, [rip + x_wire_output]
    xor r15d, r15d
    test r14, r14
    jz .Lxs_notify
    cmp byte ptr [rbx], 18
    jne xs_fail
    cmp byte ptr [rbx + 1], 0
    jne xs_fail
    cmp dword ptr [rbx + 4], 0x222
    jne xs_fail
    cmp dword ptr [rbx + 8], 0x444
    jne xs_fail
    cmp [rbx + 12], r14d
    jne xs_fail
    mov r15, r13
    cmp r14, 4
    jne 1f
    shl r15, 2
    cmp byte ptr [rbx + 16], 32
    jne xs_fail
    jmp 2f
1:  cmp byte ptr [rbx + 16], 8
    jne xs_fail
2:  cmp [rbx + 20], r13d
    jne xs_fail
    lea rdi, [rbx + 24]
    mov rsi, r12
    mov rdx, r15
    call memeq
    test eax, eax
    jz xs_fail
    add r15, 3
    and r15, -4
    add r15, 24
    movzx eax, word ptr [rbx + 2]
    shl eax, 2
    cmp rax, r15
    jne xs_fail
    cmp dword ptr [rbx + r15], 0x0001002b
    jne xs_fail
    add r15, 4
.Lxs_notify:
    add rbx, r15
    cmp byte ptr [rbx], 25
    jne xs_fail
    cmp word ptr [rbx + 2], 11
    jne xs_fail
    cmp dword ptr [rbx + 4], 0x222
    jne xs_fail
    cmp byte ptr [rbx + 12], 31
    jne xs_fail
    mov eax, [rsp]
    cmp [rbx + 28], eax
    jne xs_fail
    xor eax, eax
    mov edx, 1
    test r14, r14
    jz 3f
    mov eax, 0x444
    add edx, 2
3:  cmp [rbx + 32], eax
    jne xs_fail
    cmp [rip + x_wire_sequence], edx
    jne xs_fail
    add r15, 44
    cmp r15d, [rip + x_wire_output_len]
    jne xs_fail
    EPILOGUE

FN main
    PROLOGUE 32
    mov qword ptr [rip + xs_stage], 1
    lea rdi, [rip + xs_name]
    xor esi, esi
    mov eax, 319
    XSYS
    test eax, eax
    js xs_fail
    mov [rip + x_wire_fd], eax
    mov dword ptr [rip + x_wire_targets_atom], 0x100
    mov dword ptr [rip + x_wire_utf8_atom], 0x101
    mov dword ptr [rip + x_wire_max_request], 65535
    mov dword ptr [rip + x_send_main_window], 0x555
    mov dword ptr [rip + x_paste_clipboard_atom], 0x333
    mov dword ptr [rip + x_paste_owned], 1
    mov rax, [rip + g_mem_live]
    mov [rip + xs_live], rax
    lea r15, [rip + xs_vectors]
.Lxs_vector:
    cmp qword ptr [r15], -1
    je .Lxs_points
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    mov rcx, [r15 + 24]
    call xs_check
    add r15, 32
    inc qword ptr [rip + xs_stage]
    jmp .Lxs_vector
.Lxs_points:
    xor ebx, ebx
.Lxs_cp:
    mov edi, ebx
    lea rsi, [rip + xs_encoded_cp]
    call utf8_encode
    mov r12d, eax
    xor r13d, r13d
    cmp ebx, 0xa0
    jae 1f
    cmp ebx, 0x7e
    ja 2f
    cmp ebx, 0x20
    jae 1f
    cmp ebx, 9
    je 1f
    cmp ebx, 10
    jne 2f
1:  mov r13d, 1
2:  mov [rsp], bl
    lea rdi, [rip + xs_encoded_cp]
    mov rsi, r12
    xor edx, edx
    test r13d, r13d
    jz 3f
    mov rdx, rsp
3:  mov rcx, r13
    call xs_check
    inc ebx
    inc qword ptr [rip + xs_stage]
    cmp ebx, 256
    jb .Lxs_cp

    # Exact input budget is accepted and the byte beyond it is rejected before reading.
    mov edi, 67108864
    call mem_alloc
    mov rbx, rax
    mov rdi, rax
    mov esi, 0x41
    mov edx, 67108864
    call memset
    mov rdi, rbx
    mov esi, 67108864
    call x_string_convert
    test rax, rax
    jz xs_fail
    mov r12, rax
    cmp rdx, 67108864
    jne xs_fail
    cmp byte ptr [r12 + 67108864], 0
    jne xs_fail
    mov rdi, rax
    mov rsi, rbx
    mov edx, 67108864
    call memeq
    test eax, eax
    jz xs_fail
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call mem_free
    inc qword ptr [rip + xs_stage]

    # Owned result survives source replacement/free.
    lea rdi, [rip + xs_latin]
    mov esi, 6
    call mem_dup
    mov rbx, rax
    mov rdi, rax
    mov esi, 6
    call x_string_convert
    mov r12, rax
    cmp rdx, 3
    jne xs_fail
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    lea rsi, [rip + xs_encoded]
    mov edx, 3
    call memeq
    test eax, eax
    jz xs_fail
    mov rdi, r12
    call mem_free
    inc qword ptr [rip + xs_stage]

    lea rdi, [rip + xs_latin]
    mov esi, 6
    mov edx, 31
    lea rcx, [rip + xs_encoded]
    mov r8d, 3
    mov r9d, 31
    call xs_serve
    lea rdi, [rip + xs_water]
    mov esi, 3
    mov edx, 31
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call xs_serve
    lea rdi, [rip + xs_nul]
    mov esi, 3
    mov edx, 0x101
    lea rcx, [rip + xs_nul]
    mov r8d, 3
    mov r9d, 0x101
    call xs_serve
    xor edi, edi
    xor esi, esi
    mov edx, 31
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, 31
    call xs_serve
    lea rdi, [rip + xs_latin]
    mov esi, 6
    mov edx, 0x100
    lea rcx, [rip + xs_targets]
    mov r8d, 3
    mov r9d, 4
    call xs_serve
    lea rdi, [rip + xs_nul]
    mov esi, 3
    mov edx, 0x100
    lea rcx, [rip + xs_targets]
    mov r8d, 2
    mov r9d, 4
    call xs_serve
    mov rax, [rip + xs_live]
    cmp rax, [rip + g_mem_live]
    jne xs_fail
    mov edi, [rip + x_wire_fd]
    SYS SYS_close
    mov edi, 1
    lea rsi, [rip + xs_ok]
    mov edx, 32
    call write_all
    xor edi, edi
    SYS SYS_exit_group
.section .rodata
xs_targets: .long 0x100,0x101,31
