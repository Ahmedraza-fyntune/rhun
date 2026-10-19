# Exact logical identity grammar and injective on-disk names.
.include "rhun.inc"
.include "app/extstore.inc"
.text
# ext_store_identity_check(ptr,length) -> 1/0. Never scan past counted input.
FN ext_store_identity_check
    test rdi, rdi
    jz .Lesi_bad
    test rsi, rsi
    jz .Lesi_bad
    cmp rsi, 100
    ja .Lesi_bad
    cmp byte ptr [rdi], '.'
    je .Lesi_bad
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    cmp eax, '.'
    je 3f
    cmp eax, '_'
    je 3f
    cmp eax, '-'
    je 3f
    mov edx, eax
    sub edx, '0'
    cmp edx, 9
    jbe 3f
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    ja .Lesi_bad
3:  inc rcx
    cmp rcx, rsi
    jb 1b
    mov eax, 1
    ret
.Lesi_bad:
    xor eax, eax
    ret

# ext_store_identity_len(cstr) -> supported length or0. At most101 input bytes.
FN ext_store_identity_len
    test rdi, rdi
    jz .Lesi_bad
    xor esi, esi
1:  cmp byte ptr [rdi + rsi], 0
    je 2f
    inc esi
    cmp esi, 101
    jb 1b
    jmp .Lesi_bad
2:  PROLOGUE
    mov rbx, rsi
    call ext_store_identity_check
    test eax, eax
    jz 3f
    mov rax, rbx
3:  EPILOGUE

# ext_store_identity_encode(dst201,ptr,length) -> encoded count or0 unchanged.
# Destination/source are disjoint. Canonical lowercase encoding preserves case.
FN ext_store_identity_encode
    test rdi, rdi
    jz .Lesi_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    mov rsi, rdx
    call ext_store_identity_check
    test eax, eax
    jz 3f
    xor ecx, ecx
    lea r8, [rip + hexdigits]
1:  movzx edx, byte ptr [r12 + rcx]
    mov eax, edx
    shr eax, 4
    mov al, [r8 + rax]
    mov [rbx + rcx*2], al
    and edx, 15
    mov al, [r8 + rdx]
    mov [rbx + rcx*2 + 1], al
    inc rcx
    cmp rcx, r13
    jb 1b
    lea rax, [r13*2]
    mov byte ptr [rbx + rax], 0
3:  EPILOGUE

# ext_store_identity_decode(dst101,encoded,count) -> decoded count or0 unchanged.
FN ext_store_identity_decode
    test rdi, rdi
    jz .Lesi_bad
    test rsi, rsi
    jz .Lesi_bad
    cmp rdx, 2
    jb .Lesi_bad
    cmp rdx, 200
    ja .Lesi_bad
    test dl, 1
    jnz .Lesi_bad
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    shr r13, 1
    xor r14d, r14d
1:  movzx eax, byte ptr [r12 + r14*2]
    call .Lesi_nibble
    cmp eax, 15
    ja 8f
    shl eax, 4
    mov r15d, eax
    movzx eax, byte ptr [r12 + r14*2 + 1]
    call .Lesi_nibble
    cmp eax, 15
    ja 8f
    or eax, r15d
    mov [rsp + r14], al
    inc r14
    cmp r14, r13
    jb 1b
    mov byte ptr [rsp + r13], 0
    mov rdi, rsp
    mov rsi, r13
    call ext_store_identity_check
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [r13 + 1]
    call memcpy
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
.Lesi_nibble:
    sub eax, '0'
    cmp eax, 9
    jbe 1f
    sub eax, 'a' - '0'
    cmp eax, 5
    ja 2f
    add eax, 10
1:  ret
2:  mov eax, 255
    ret

# ext_store_id_check(readable64) ->1/0, no NUL/length access outside64 bytes.
FN ext_store_id_check
    test rdi, rdi
    jz .Lesi_bad
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    call .Lesi_nibble
    cmp eax, 15
    ja .Lesi_bad
    inc ecx
    cmp ecx, 64
    jb 1b
    mov eax, 1
    ret

# ext_store_join(dst4096,parent,basename) ->0/-errno. Disjoint counted C strings.
# Internal caller supplies a validated single component or static relative suffix.
FN ext_store_join
    test rdi, rdi
    jz .Lesi_invalid
    test rsi, rsi
    jz .Lesi_invalid
    test rdx, rdx
    jz .Lesi_invalid
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp byte ptr [r12 + r14], 0
    je 2f
    inc r14
    cmp r14, 4096
    jb 1b
    jmp 8f
2:  xor r15d, r15d
3:  cmp byte ptr [r13 + r15], 0
    je 4f
    inc r15
    cmp r15, 4096
    jb 3b
    jmp 8f
4:  test r14, r14
    jz 7f
    mov al, [r12 + r14 - 1]
    cmp al, '/'
    je 7f
.ifdef WINDOWS
    cmp al, 92
    je 7f
.endif
    inc r14
7:  lea rax, [r14 + r15]
    cmp rax, 4095
    ja 8f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    test r14, r14
    jz 71f
    cmp byte ptr [r12 + r14 - 1], 0
    jne 71f
    dec rdx
71: call memcpy
    cmp rdx, r14
    je 72f
    mov byte ptr [rbx + r14 - 1], '/'
72: lea rdi, [rbx + r14]
    mov rsi, r13
    lea rdx, [r15 + 1]
    call memcpy
    xor eax, eax
    EPILOGUE
8:  mov rax, -36
    EPILOGUE
.Lesi_invalid:
    mov rax, -22
    ret

# ext_store_package_path(dst4096,root,owner,name,id64)->0/-errno.
# Formatting only; actual opens must use rooted raw handles.
FN ext_store_package_path
    test rdi, rdi
    jz .Lesi_invalid
    PROLOGUE 8688
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, rsi
    call dir_scan_path_check
    test rax, rax
    js 8f
    cmp byte ptr [r12], 0
    je 7f
    mov rdi, r13
    call ext_store_identity_len
    test rax, rax
    jz 7f
    mov rdi, rsp
    mov rsi, r13
    mov rdx, rax
    call ext_store_identity_encode
    mov rdi, r14
    call ext_store_identity_len
    test rax, rax
    jz 7f
    lea rdi, [rsp + 208]
    mov rsi, r14
    mov rdx, rax
    call ext_store_identity_encode
    mov rdi, r15
    call ext_store_id_check
    test eax, eax
    jz 7f
    lea rdi, [rsp + 416]
    mov rsi, r15
    mov edx, 64
    call memcpy
    mov byte ptr [rsp + 480], 0
    lea rdi, [rsp + 496]
    mov rsi, r12
    lea rdx, [rip + .Lesi_packages]
    call ext_store_join
    test rax, rax
    js 8f
    lea rdi, [rsp + 4592]
    lea rsi, [rsp + 496]
    mov rdx, rsp
    call ext_store_join
    test rax, rax
    js 8f
    lea rdi, [rsp + 496]
    lea rsi, [rsp + 4592]
    lea rdx, [rsp + 208]
    call ext_store_join
    test rax, rax
    js 8f
    lea rdi, [rsp + 4592]
    lea rsi, [rsp + 496]
    lea rdx, [rsp + 416]
    call ext_store_join
    test rax, rax
    js 8f
    lea rdi, [rsp + 4592]
    call strlen
    mov rdi, rbx
    lea rsi, [rsp + 4592]
    lea rdx, [rax + 1]
    call memcpy
    xor eax, eax
    jmp 8f
7:  mov rax, -22
8:  EPILOGUE

# ext_store_payload_path(dst4096,root,owner,name,id64)->0/-errno.
FN ext_store_payload_path
    PROLOGUE 4112
    mov rbx, rdi
    lea rdi, [rsp + 16]
    call ext_store_package_path
    test rax, rax
    js 1f
    mov rdi, rbx
    lea rsi, [rsp + 16]
    lea rdx, [rip + .Lesi_payload]
    call ext_store_join
1:  EPILOGUE
.section .rodata
.Lesi_packages: .asciz ".packages"
.Lesi_payload: .asciz "payload"
