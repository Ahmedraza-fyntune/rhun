# Pure fixed-capacity request builder. Never reads files or follows a global registry.
.include "rhun.inc"
.include "app/themecapture.inc"
.section .rodata
tcq_flags: .byte 0, 1, 3
tcq_zero_digest: .zero 32
.text
FN theme_capture_request_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Ltcq_bad
    cmp qword ptr [rbx + TCFG_job], 0
    jle .Ltcq_bad
    cmp qword ptr [rbx + TCFG_context], 0
    jle .Ltcq_bad
    mov rax, [rbx + TCFG_nonce]
    or rax, [rbx + TCFG_nonce + 8]
    jz .Ltcq_bad
    cmp qword ptr [rbx + TCFG_reserved], 0
    jne .Ltcq_bad
    mov r13d, [rbx + TCFG_scope]
    cmp r13d, TC_SCOPE_FULL
    ja .Ltcq_bad
    mov r14d, [rbx + TCFG_expected_scope]
    cmp r14d, r13d
    ja .Ltcq_bad
    mov rax, [rbx + TCFG_expected]
    or rax, [rbx + TCFG_expected + 8]
    or rax, [rbx + TCFG_expected + 16]
    or rax, [rbx + TCFG_expected + 24]
    test r14d, r14d
    jz 1f
    test rax, rax
    jz .Ltcq_bad
    jmp 2f
1:  test rax, rax
    jnz .Ltcq_bad
2:  xor r15d, r15d
    test r13d, r13d
    jnz 3f
    test r12, r12
    jnz .Ltcq_bad
    jmp 4f
3:  mov rdi, r12
    call tc_path_len
    test rax, rax
    js .Ltcq_error
    cmp rax, TC_DIR_MAX
    ja .Ltcq_long
    mov r15, rax
4:  mov edi, TCQ_SIZE
    call tc_alloc_try
    test rax, rax
    jz .Ltcq_oom
    mov r13, rax
    mov edi, TC_INPUT_CAP
    call tc_alloc_try
    test rax, rax
    jz .Ltcq_wire_oom
    mov [r13 + TCQ_wire], rax
    mov r14, rax
    mov rax, 0x0031514552544852
    mov [r14], rax
    mov dword ptr [r14 + 8], 1
    mov dword ptr [r14 + 12], TC_HEADER_SIZE
    lea rax, [r15 + TC_HEADER_SIZE]
    mov [r13 + TCQ_length], rax
    mov [r14 + 16], rax
    mov eax, [rbx + TCFG_scope]
    mov [r13 + TCQ_scope], rax
    lea rcx, [rip + tcq_flags]
    movzx eax, byte ptr [rcx + rax]
    mov [r14 + 28], eax
    mov eax, [rbx + TCFG_expected_scope]
    mov [r13 + TCQ_expected_scope], rax
    mov [r14 + 104], eax
    mov [r14 + 96], r15d
    mov dword ptr [r14 + 100], T_COUNT
    lea rdi, [r14 + 32]
    mov rsi, rbx
    mov edx, 32
    call memcpy
    lea rdi, [r14 + 128]
    lea rsi, [rbx + TCFG_expected]
    mov edx, 32
    call memcpy
    test r15, r15
    jz 5f
    lea rdi, [r14 + TC_HEADER_SIZE]
    mov rsi, r12
    mov rdx, r15
    call memcpy
5:  mov rax, r13
    xor edx, edx
    EPILOGUE
.Ltcq_wire_oom:
    mov rdi, r13
    call tc_free
.Ltcq_oom:
    mov rax, -12
    jmp .Ltcq_error
.Ltcq_long:
    mov rax, -36
    jmp .Ltcq_error
.Ltcq_bad:
    mov rax, -22
.Ltcq_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE

FN theme_capture_request_add
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    mov r12, rdx
    test rbx, rbx
    jz .Ltcqa_bad
    cmp qword ptr [rbx + TCQ_state], TCQ_BUILDING
    jne .Ltcqa_bad
    mov rax, r13
    shr rax, 32
    jnz .Ltcqa_bad
    cmp qword ptr [rbx + TCQ_count], TC_SOURCE_MAX
    jae .Ltcqa_large
    mov rdi, r12
    call tc_path_len
    test rax, rax
    js .Ltcqa_out
    mov r15, rax
    mov r14, [rbx + TCQ_wire]
    mov eax, [r14 + 96]
    lea r8, [r14 + rax + TC_HEADER_SIZE]
    mov rcx, [rbx + TCQ_count]
1:  test rcx, rcx
    jz 2f
    cmp [r8], r13d
    je .Ltcqa_exists
    mov eax, [r8 + 4]
    lea r8, [r8 + rax + TC_REQUEST_ROW]
    dec rcx
    jmp 1b
2:  mov rax, [rbx + TCQ_length]
    lea rdx, [rax + r15 + TC_REQUEST_ROW]
    cmp rdx, TC_INPUT_CAP
    ja .Ltcqa_large
    mov [r14 + rax], r13d
    mov [r14 + rax + 4], r15d
    lea rdi, [r14 + rax + TC_REQUEST_ROW]
    mov rsi, r12
    mov rdx, r15
    call memcpy
    add r15, TC_REQUEST_ROW
    add [rbx + TCQ_length], r15
    mov rax, [rbx + TCQ_length]
    mov [r14 + 16], rax
    inc qword ptr [rbx + TCQ_count]
    mov eax, [rbx + TCQ_count]
    mov [r14 + 24], eax
    xor eax, eax
.Ltcqa_out:
    EPILOGUE
.Ltcqa_bad:
    mov rax, -22
    EPILOGUE
.Ltcqa_large:
    mov rax, -7
    EPILOGUE
.Ltcqa_exists:
    mov rax, -17
    EPILOGUE

FN theme_capture_request_seal
    PROLOGUE 32
    mov rbx, rdi
    test rbx, rbx
    jz 8f
    cmp qword ptr [rbx + TCQ_state], TCQ_SEALED
    je 7f
    cmp qword ptr [rbx + TCQ_state], TCQ_BUILDING
    jne 8f
    cmp qword ptr [rbx + TCQ_count], 0
    jne 1f
    cmp qword ptr [rbx + TCQ_scope], TC_SCOPE_NONE
    je 8f
1:  mov rdi, [rbx + TCQ_wire]
    mov rsi, [rbx + TCQ_length]
    mov rdx, rsp
    call tc_request_digest
    test eax, eax
    jz 9f
    mov rdi, [rbx + TCQ_wire]
    add rdi, 64
    mov rsi, rsp
    mov edx, 32
    call memcpy
    mov qword ptr [rbx + TCQ_state], TCQ_SEALED
7:  xor eax, eax
    EPILOGUE
8:  mov rax, -22
    EPILOGUE
9:  mov rax, -5
    EPILOGUE
# Caller keeps the request and its borrowed wire until consumed1.
FN theme_capture_request_free
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + TCQ_state], TCQ_OWNED
    je 2f
    jmp tc_request_dispose
1:  xor eax, eax
    mov edx, 1
    ret
2:  mov rax, -16
    xor edx, edx
    ret
FN tc_request_dispose
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 1f
    mov qword ptr [rbx + TCQ_state], TCQ_RETIRING
    mov rdi, [rbx + TCQ_wire]
    call tc_free
    test rdx, rdx
    jnz 2f
    cmp qword ptr [rbx + TCQ_cleanup], 0
    jne 3f
    mov [rbx + TCQ_cleanup], rax
3:  mov rax, [rbx + TCQ_cleanup]
    xor edx, edx
    EPILOGUE
2:  mov qword ptr [rbx + TCQ_wire], 0
    mov r12, [rbx + TCQ_cleanup]
.if TCQ_SIZE > 65520
.error "TCQ small self free must be infallible after final wire release"
.endif
    mov rdi, rbx
    call tc_free
    mov rax, r12
    mov edx, 1
    EPILOGUE
1:  xor eax, eax
    mov edx, 1
    EPILOGUE
# Hash immutable request with only its digest field replaced by32 zero bytes.
FN tc_request_digest
    PROLOGUE SH256_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, TC_HEADER_SIZE
    jb 9f
    cmp r12, TC_INPUT_CAP
    ja 9f
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    mov rsi, rbx
    mov edx, 64
    call sha256_update
    test eax, eax
    jz 9f
    mov rdi, rsp
    lea rsi, [rip + tcq_zero_digest]
    mov edx, 32
    call sha256_update
    test eax, eax
    jz 9f
    mov rdi, rsp
    lea rsi, [rbx + 96]
    lea rdx, [r12 - 96]
    call sha256_update
    test eax, eax
    jz 9f
    mov rdi, rsp
    mov rsi, r13
    call sha256_final
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# Cstr path length or negative errno. No filesystem/cwd lookup or normalization.
FN tc_path_len
    PROLOGUE
    mov rbx, rdi
    mov esi, TC_PATH_MAX
    call ext_root_length
    test rax, rax
    jle 9f
    mov r12, rax
.ifdef WINDOWS
    mov rdi, rbx
    mov rsi, rax
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    cmp byte ptr [rbx + 1], ':'
    jne .Ltcp_unc
    movzx eax, byte ptr [rbx]
    and eax, -33
    sub eax, 'A'
    cmp eax, 25
    ja 8f
    mov al, [rbx + 2]
    cmp al, '/'
    je 71f
    cmp al, 92
    jne 8f
71: mov edx, 3
    jmp 72f
.Ltcp_unc:
    cmp r12, 5
    jb 8f
    mov al, [rbx]
    cmp al, '/'
    je 1f
    cmp al, 92
    jne 8f
1:  mov al, [rbx + 1]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne 8f
2:  mov r13d, 2
3:  cmp r13, r12
    jae 8f
    mov al, [rbx + r13]
    cmp al, '/'
    je 4f
    cmp al, 92
    je 4f
    inc r13
    jmp 3b
4:  cmp r13, 2
    je 8f
    cmp r13, 3
    jne 41f
    mov al, [rbx + 2]
    cmp al, '.'
    je 8f
    cmp al, '?'
    je 8f
41: cmp r13, 4
    jne 42f
    cmp word ptr [rbx + 2], 0x2e2e
    je 8f
42: inc r13
    mov r14, r13
5:  cmp r14, r12
    jae 6f
    mov al, [rbx + r14]
    cmp al, '/'
    je 6f
    cmp al, 92
    je 6f
    inc r14
    jmp 5b
6:  mov rax, r14
    sub rax, r13
    jz 8f
    cmp rax, 1
    jne 61f
    cmp byte ptr [rbx + r13], '.'
    je 8f
61: cmp rax, 2
    jne 711f
    cmp word ptr [rbx + r13], 0x2e2e
    je 8f
711: mov rdx, r14
72: mov rdi, rbx
    mov rsi, r12
    call tc_win_no_devices
    test eax, eax
    jz 8f
.else
    cmp byte ptr [rbx], '/'
    jne 8f
.endif
7:  mov rax, r12
    EPILOGUE
8:  mov rax, -22
    EPILOGUE
9:  test rax, rax
    js 10f
    mov rax, -22
10: EPILOGUE

.ifdef WINDOWS
# File components after the volume cannot spell DOS/console device aliases.
# The UTF8 path was already validated. UNC server/share are volume names, not files.
FN tc_win_no_devices
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  cmp r13, r12
    jae 9f
    mov al, [rbx + r13]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne 3f
2:  inc r13
    jmp 1b
3:  mov r14, r13
4:  cmp r14, r12
    jae 5f
    mov al, [rbx + r14]
    cmp al, '/'
    je 5f
    cmp al, 92
    je 5f
    inc r14
    jmp 4b
5:  mov r15, r13
51: cmp r15, r14
    jae 52f
    mov al, [rbx + r15]
    cmp al, '.'
    je 52f
    cmp al, ':'
    je 52f
    inc r15
    jmp 51b
52: cmp r15, r13
    jbe 6f
    cmp byte ptr [rbx + r15 - 1], ' '
    jne 6f
    dec r15
    jmp 52b
6:  mov rcx, r15
    sub rcx, r13
    cmp rcx, 3
    jb 8f
    mov eax, [rbx + r13]
    and eax, 0x00ffffff
    or eax, 0x00202020
    cmp rcx, 3
    jne 61f
    cmp eax, 0x006e6f63
    je 10f
    cmp eax, 0x006e7270
    je 10f
    cmp eax, 0x00787561
    je 10f
    cmp eax, 0x006c756e
    je 10f
    jmp 8f
61: cmp rcx, 4
    je 62f
    cmp rcx, 5
    jne 65f
62: cmp eax, 0x006d6f63
    je 63f
    cmp eax, 0x0074706c
    jne 8f
63: cmp rcx, 5
    je 64f
    mov al, [rbx + r13 + 3]
    cmp al, '1'
    jb 8f
    cmp al, '9'
    jbe 10f
    jmp 8f
64: cmp byte ptr [rbx + r13 + 3], 0xc2
    jne 8f
    mov al, [rbx + r13 + 4]
    cmp al, 0xb9
    je 10f
    cmp al, 0xb2
    je 10f
    cmp al, 0xb3
    je 10f
    jmp 8f
65: cmp rcx, 6
    je 66f
    cmp rcx, 7
    jne 8f
    mov eax, [rbx + r13]
    or eax, 0x20202020
    cmp eax, 0x6f6e6f63
    jne 8f
    movzx eax, word ptr [rbx + r13 + 4]
    or eax, 0x2020
    cmp eax, 0x7475
    jne 8f
    cmp byte ptr [rbx + r13 + 6], '$'
    je 10f
    jmp 8f
66: mov eax, [rbx + r13]
    or eax, 0x20202020
    cmp eax, 0x696e6f63
    jne 8f
    mov al, [rbx + r13 + 4]
    or al, 32
    cmp al, 'n'
    jne 8f
    cmp byte ptr [rbx + r13 + 5], '$'
    je 10f
8:  mov r13, r14
    jmp 1b
9:  mov eax, 1
    EPILOGUE
10: xor eax, eax
    EPILOGUE
.endif
