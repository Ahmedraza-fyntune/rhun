# Pending user commands retain exact identity, never command-vector indices.
.include "rhun.inc"
.include "app/extpending.inc"
.bss
.p2align 3
pn_last_revision: .quad 0
.globl ext_pending_shutting_down
ext_pending_shutting_down: .quad 0
.text
# Bounded readable C string ->length or-1. Never reads beyond limit+1.
pn_length:
    test rdi, rdi
    jz 8f
    xor eax, eax
1:  cmp rax, rsi
    ja 8f
    cmp byte ptr [rdi + rax], 0
    je 9f
    inc rax
    jmp 1b
8:  mov rax, -1
9:  ret

# ext_pending_new(targetEXT,wireCstr)->owned PN/NULL,RDX0/-errno.
FN ext_pending_new
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Lpn_invalid
    call ext_has_identity
    test eax, eax
    jz .Lpn_invalid
    cmp qword ptr [rip + ext_pending_shutting_down], 0
    jne .Lpn_closed
    mov rax, 0x7fffffffffffffff
    cmp [rip + pn_last_revision], rax
    jae .Lpn_overflow
    mov rdi, [rbx + EXT_owner]
    mov esi, PN_LIMIT
    call pn_length
    test rax, rax
    jle .Lpn_invalid
    mov [rsp], rax
    mov rdi, [rbx + EXT_name]
    mov esi, PN_LIMIT
    call pn_length
    test rax, rax
    jle .Lpn_invalid
    mov [rsp + 8], rax
    mov rdi, r12
    mov esi, 2 * PN_LIMIT + 1
    call pn_length
    test rax, rax
    js .Lpn_invalid
    sub rax, [rsp + 8]
    sub rax, 1
    jbe .Lpn_invalid
    cmp rax, PN_LIMIT
    ja .Lpn_invalid
    mov [rsp + 16], rax
    mov rcx, [rsp + 8]
    cmp byte ptr [r12 + rcx], '.'
    jne .Lpn_invalid
    lea rax, [r12 + rcx + 1]
    mov [rsp + 24], rax
    mov rdi, r12
    mov rsi, [rbx + EXT_name]
    mov rdx, rcx
    call memeq
    test eax, eax
    jz .Lpn_invalid
    mov rdi, [rsp]
    add rdi, [rsp + 8]
    jc .Lpn_invalid
    add rdi, [rsp + 16]
    jc .Lpn_invalid
    add rdi, PN_SIZE + 3
    jc .Lpn_invalid
    mov [rsp + 32], rdi
    call mem_alloc_try
    test rax, rax
    jz .Lpn_oom
    mov r13, rax
    mov qword ptr [rax + PN_refs], 1
    mov [rax + PN_target], rbx
    inc qword ptr [rip + pn_last_revision]
    mov rcx, [rip + pn_last_revision]
    mov [rax + PN_revision], rcx
    mov rcx, [rsp]
    mov [rax + PN_ownerlen], rcx
    mov rcx, [rsp + 8]
    mov [rax + PN_namelen], rcx
    mov rcx, [rsp + 16]
    mov [rax + PN_keylen], rcx
    mov rcx, [rsp + 32]
    mov [rax + PN_size], rcx
    mov qword ptr [rax + 56], 0
    lea r14, [rax + PN_SIZE]
    mov rdi, r14
    mov rsi, [rbx + EXT_owner]
    mov rdx, [rsp]
    inc rdx
    call memcpy
    add r14, [rsp]
    inc r14
    mov rdi, r14
    mov rsi, [rbx + EXT_name]
    mov rdx, [rsp + 8]
    inc rdx
    call memcpy
    add r14, [rsp + 8]
    inc r14
    mov rdi, r14
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 16]
    inc rdx
    call memcpy
    mov rax, r13
    xor edx, edx
    EPILOGUE
.Lpn_invalid:
    mov rdx, -22
    jmp .Lpn_failed
.Lpn_closed:
    mov rdx, -32
    jmp .Lpn_failed
.Lpn_overflow:
    mov rdx, -75
    jmp .Lpn_failed
.Lpn_oom:
    mov rdx, -12
.Lpn_failed:
    xor eax, eax
    EPILOGUE

FN ext_pending_retain
    test rdi, rdi
    jz .Lpn_ref_invalid
    cmp qword ptr [rdi + PN_refs], 0
    je .Lpn_ref_invalid
    cmp qword ptr [rdi + PN_refs], -1
    je .Lpn_ref_overflow
    inc qword ptr [rdi + PN_refs]
    xor eax, eax
    ret
.Lpn_ref_overflow:
    mov rax, -75
    ret
.Lpn_ref_invalid:
    mov rax, -22
    ret

FN ext_pending_release
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi + PN_refs], 0
    je .Lpn_ref_invalid
    dec qword ptr [rdi + PN_refs]
    jnz 9f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + PN_inv]
    call mem_free
    mov rdi, rbx
    call mem_free
    xor eax, eax
    EPILOGUE
9:  xor eax, eax
    ret

# Detach before normal cleanup. Future pure publication queues the taken reference instead.
FN ext_pending_take
    mov rax, [rdi + EXT_pending]
    mov qword ptr [rdi + EXT_pending], 0
    ret
FN ext_pending_clear
    mov rax, [rdi + EXT_pending]
    mov qword ptr [rdi + EXT_pending], 0
    mov rdi, rax
    jmp ext_pending_release

# ext_pending_matches(PN,live targetEXT,wireCstr)->1/0. All comparisons are byte exact.
FN ext_pending_matches
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    call ext_has_identity
    test eax, eax
    jz .Lpn_no
    test rbx, rbx
    jz .Lpn_no
    cmp [rbx + PN_target], r12
    jne .Lpn_no
    mov rdi, [r12 + EXT_owner]
    mov esi, PN_LIMIT
    call pn_length
    cmp rax, [rbx + PN_ownerlen]
    jne .Lpn_no
    mov rdx, rax
    lea rdi, [rbx + PN_SIZE]
    mov rsi, [r12 + EXT_owner]
    call memeq
    test eax, eax
    jz .Lpn_no
    lea r14, [rbx + PN_SIZE + 1]
    add r14, [rbx + PN_ownerlen]
    mov rdi, [r12 + EXT_name]
    mov esi, PN_LIMIT
    call pn_length
    cmp rax, [rbx + PN_namelen]
    jne .Lpn_no
    mov rdx, rax
    mov rdi, r14
    mov rsi, [r12 + EXT_name]
    call memeq
    test eax, eax
    jz .Lpn_no
    mov rdi, r13
    mov esi, 2 * PN_LIMIT + 1
    call pn_length
    mov rcx, [rbx + PN_namelen]
    add rcx, [rbx + PN_keylen]
    inc rcx
    cmp rax, rcx
    jne .Lpn_no
    mov rdx, [rbx + PN_namelen]
    cmp byte ptr [r13 + rdx], '.'
    jne .Lpn_no
    mov rdi, r13
    mov rsi, r14
    call memeq
    test eax, eax
    jz .Lpn_no
    mov rdx, [rbx + PN_namelen]
    lea rdi, [r13 + rdx + 1]
    lea rsi, [r14 + rdx + 1]
    mov rdx, [rbx + PN_keylen]
    call memeq
    EPILOGUE
.Lpn_no:
    xor eax, eax
    EPILOGUE
