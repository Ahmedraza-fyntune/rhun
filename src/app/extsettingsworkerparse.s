# Pure helper argument/request validation before any settings operation.
.include "rhun.inc"
.include "app/extsettingsworker.inc"
.section .rodata
.Lswp_marker: .asciz "--extension-settings-worker"
.Lswp_version: .asciz "v1"
.text
# positive63 decimal, exact bounded input ->RAX number or0, RDX error.
swp_number:
    PROLOGUE
    mov rbx, rdi
    mov esi, 19
    call ext_root_length
    test rax, rax
    jle 3f
    mov r12, rax
    xor eax, eax
    xor ecx, ecx
1:  movzx edx, byte ptr [rbx + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 3f
    mov r8, 922337203685477580
    cmp rax, r8
    ja 3f
    jb 2f
    cmp edx, 7
    ja 3f
2:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    cmp rcx, r12
    jb 1b
    test rax, rax
    jz 3f
    xor edx, edx
    EPILOGUE
3:  xor eax, eax
    mov rdx, -22
    EPILOGUE

swp_nibble:
    mov eax, edi
    sub eax, '0'
    cmp eax, 9
    jbe 1f
    mov eax, edi
    sub eax, 'a'
    cmp eax, 5
    ja 2f
    add eax, 10
1:  ret
2:  mov rax, -1
    ret

# arguments(argc,argv,outTag32)->0/-EINVAL. No environment or global state.
FN ext_settings_worker_arguments
    cmp rdi, 6
    jne .Lswp_bad_leaf
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    mov rdi, [rbx + 8]
    lea rsi, [rip + .Lswp_marker]
    call strcmp_eq
    test eax, eax
    jz .Lswp_bad
    mov rdi, [rbx + 16]
    lea rsi, [rip + .Lswp_version]
    call strcmp_eq
    test eax, eax
    jz .Lswp_bad
    mov rdi, [rbx + 24]
    call swp_number
    test rdx, rdx
    jnz .Lswp_bad
    mov [r12 + EWT_job], rax
    mov rdi, [rbx + 32]
    call swp_number
    test rdx, rdx
    jnz .Lswp_bad
    mov [r12 + EWT_context], rax
    mov r13, [rbx + 40]
    mov rdi, r13
    mov esi, 32
    call ext_root_length
    cmp rax, 32
    jne .Lswp_bad
    xor r14d, r14d
1:  movzx edi, byte ptr [r13 + r14]
    call swp_nibble
    test rax, rax
    js .Lswp_bad
    mov r15d, eax
    shl r15d, 4
    inc r14
    movzx edi, byte ptr [r13 + r14]
    call swp_nibble
    test rax, rax
    js .Lswp_bad
    or eax, r15d
    mov rcx, r14
    shr rcx, 1
    mov [r12 + rcx + EWT_nonce], al
    inc r14
    cmp r14, 32
    jb 1b
    xor eax, eax
    EPILOGUE
.Lswp_bad:
    mov rax, -22
    EPILOGUE
.Lswp_bad_leaf:
    mov rax, -22
    ret

# path(owned mutable cstr)->0/-errno,RDX native-root prefix length on success.
# Entire basename validation precedes any later creating walk. No filesystem access.
FN ext_settings_worker_path
    PROLOGUE 32
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lswp_path_bad
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call snippet_utf8_valid
    test eax, eax
    jz .Lswp_path_bad
    mov qword ptr [rsp], 1
    mov qword ptr [rsp + 8], 0 # required UNC root components
    mov r13d, 1
.ifdef WINDOWS
    mov rdi, rbx
    call kp_path_absolute
    test eax, eax
    jz .Lswp_path_bad
    cmp byte ptr [rbx + 1], ':'
    jne 1f
    mov qword ptr [rsp], 3
    mov r13d, 3
    jmp 2f
1:  mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 2
    mov r13d, 2
2:
.else
    cmp byte ptr [rbx], '/'
    jne .Lswp_path_bad
.endif
    xor r15d, r15d
.Lswp_path_next:
    cmp r13, r12
    jae .Lswp_path_end
    mov al, [rbx + r13]
    cmp al, '/'
    je .Lswp_path_skip
.ifdef WINDOWS
    cmp al, 92
    je .Lswp_path_skip
.endif
    mov r14, r13
.Lswp_path_scan:
    cmp r13, r12
    jae .Lswp_path_name
    mov al, [rbx + r13]
    cmp al, '/'
    je .Lswp_path_name
.ifdef WINDOWS
    cmp al, 92
    je .Lswp_path_name
.endif
    inc r13
    jmp .Lswp_path_scan
.Lswp_path_name:
    mov al, [rbx + r13]
    mov [rsp + 16], rax
    mov byte ptr [rbx + r13], 0
    lea rdi, [rbx + r14]
    call ext_root_name
    mov rdx, [rsp + 16]
    mov [rbx + r13], dl
    test rax, rax
    js .Lswp_path_done
    inc r15
    cmp r15, 256
    ja .Lswp_path_large
    cmp qword ptr [rsp + 8], 0
    je .Lswp_path_next
    dec qword ptr [rsp + 8]
    jz 8f
    cmp r13, r12
    jae .Lswp_path_bad
    inc r13
    jmp .Lswp_path_next
8:  mov [rsp], r13
    jmp .Lswp_path_next
.Lswp_path_skip:
    # UNC server/share may not contain empty or device-prefix components.
    cmp qword ptr [rsp + 8], 0
    jne .Lswp_path_bad
    inc r13
    jmp .Lswp_path_next
.Lswp_path_end:
    cmp qword ptr [rsp + 8], 0
    jne .Lswp_path_bad
    mov rdx, [rsp]
    xor eax, eax
.Lswp_path_done:
    EPILOGUE
.Lswp_path_large:
    mov rax, -36
    EPILOGUE
.Lswp_path_bad:
    mov rax, -22
    EPILOGUE

# request(body,length,outSWR)->0/-EPROTO. EC spans borrow immutable body bytes.
FN ext_settings_worker_request
    cmp rsi, 56
    jb .Lswp_protocol_leaf
    cmp rsi, EW_LIMIT
    ja .Lswp_protocol_leaf
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov eax, [rbx]
    cmp eax, 1
    jb .Lswp_protocol
    cmp eax, 3
    ja .Lswp_protocol
    mov [r13 + SWR_mode], rax
    mov eax, [rbx + 4]
    cmp eax, EC_BATCH
    ja .Lswp_protocol
    mov [r13 + SWR_count], rax
    mov eax, [rbx + 12]
    cmp eax, 1
    ja .Lswp_protocol
    mov [r13 + SWR_flags], rax
    mov rdx, [rbx + 16]
    cmp rdx, 1
    ja .Lswp_protocol
    mov [r13 + SWR_exists], rdx
    test eax, eax
    jnz 1f
    test rdx, rdx
    jnz .Lswp_protocol
    mov rax, [rbx + 24]
    or rax, [rbx + 32]
    or rax, [rbx + 40]
    or rax, [rbx + 48]
    jnz .Lswp_protocol
1:  lea rdi, [r13 + SWR_digest]
    lea rsi, [rbx + 24]
    mov edx, 32
    call memcpy
    mov r14d, [rbx + 8]
    test r14, r14
    jz .Lswp_protocol
    cmp r14, 4095
    ja .Lswp_protocol
    lea rax, [r14 + 56]
    cmp rax, r12
    ja .Lswp_protocol
    xor ecx, ecx
2:  cmp byte ptr [rbx + rcx + 56], 0
    je .Lswp_protocol
    inc rcx
    cmp rcx, r14
    jb 2b
    lea rdi, [r13 + SWR_path]
    lea rsi, [rbx + 56]
    mov rdx, r14
    call memcpy
    mov byte ptr [r13 + r14 + SWR_path], 0
    lea rdi, [r13 + SWR_path]
    call ext_settings_worker_path
    test rax, rax
    js .Lswp_protocol
    lea r15, [r14 + 56]
    cmp qword ptr [r13 + SWR_mode], 2
    je 3f
    cmp qword ptr [r13 + SWR_count], 0
    jne .Lswp_protocol
    cmp r15, r12
    jne .Lswp_protocol
    xor eax, eax
    EPILOGUE
3:  lea rdi, [rbx + r15]
    mov rsi, r12
    sub rsi, r15
    mov rdx, [r13 + SWR_count]
    lea rcx, [r13 + SWR_delta]
    call ext_settings_wire_deltas
    EPILOGUE
.Lswp_protocol:
    mov rax, -71
    EPILOGUE
.Lswp_protocol_leaf:
    mov rax, -71
    ret
