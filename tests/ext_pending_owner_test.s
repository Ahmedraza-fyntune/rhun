# Owned tuple data, boundaries, refcounts, allocation refusal and nonreused revisions.
.include "rhun.inc"
.include "app/extpending.inc"
.bss
.p2align 3
pno_ext: .zero EXT_SIZE
pno_other: .zero EXT_SIZE
pno_long_owner: .zero PN_LIMIT + 2
pno_long_wire: .zero PN_LIMIT + 4
pno_stage: .quad 0
pno_fail_alloc: .quad 0
pno_live: .quad 0
.data
pno_owner: .asciz "o"
pno_name: .asciz "a"
pno_wire: .asciz "a.b.c"
.text
FN pno_alloc
    cmp qword ptr [rip + pno_fail_alloc], 0
    jne 1f
    jmp mem_alloc_try
1:  xor eax, eax
    ret
FN pno_set_revision
    ret
pno_bad:
    mov rdi, [rip + pno_stage]
    add rdi, 70
    call sys_exit
    ud2
pno_create:
    lea rdi, [rip + pno_ext]
    lea rsi, [rip + pno_wire]
    jmp ext_pending_new
pno_match:
    mov rdi, r12
    lea rsi, [rip + pno_ext]
    lea rdx, [rip + pno_wire]
    jmp ext_pending_matches
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + pno_live], rax
    lea rbx, [rip + pno_ext]
    lea rax, [rip + pno_owner]
    mov [rbx + EXT_owner], rax
    mov [rip + pno_other + EXT_owner], rax
    lea rax, [rip + pno_name]
    mov [rbx + EXT_name], rax
    mov [rip + pno_other + EXT_name], rax
    mov qword ptr [rip + pno_stage], 1
    call pno_create
    test rax, rax
    jz pno_bad
    test rdx, rdx
    jnz pno_bad
    mov r12, rax
    cmp qword ptr [rax + PN_refs], 1
    jne pno_bad
    cmp [rax + PN_target], rbx
    jne pno_bad
    cmp qword ptr [rax + PN_ownerlen], 1
    jne pno_bad
    cmp qword ptr [rax + PN_namelen], 1
    jne pno_bad
    cmp qword ptr [rax + PN_keylen], 3
    jne pno_bad
    call pno_match
    cmp rax, 1
    jne pno_bad
    mov byte ptr [rip + pno_wire + 2], 'z'
    call pno_match
    test rax, rax
    jnz pno_bad
    cmp byte ptr [r12 + PN_SIZE + 4], 'b'
    jne pno_bad
    mov byte ptr [rip + pno_wire + 2], 'b'
    mov byte ptr [rip + pno_owner], 'p'
    call pno_match
    test rax, rax
    jnz pno_bad
    mov byte ptr [rip + pno_owner], 'o'
    mov rdi, r12
    lea rsi, [rip + pno_other]
    lea rdx, [rip + pno_wire]
    call ext_pending_matches
    test rax, rax
    jnz pno_bad
    mov qword ptr [rip + pno_stage], 2
    mov rdi, r12
    call ext_pending_retain
    test rax, rax
    jnz pno_bad
    cmp qword ptr [r12 + PN_refs], 2
    jne pno_bad
    mov rdi, r12
    call ext_pending_release
    cmp qword ptr [r12 + PN_refs], 1
    jne pno_bad
    mov qword ptr [r12 + PN_refs], -1
    mov rdi, r12
    call ext_pending_retain
    cmp rax, -75
    jne pno_bad
    cmp qword ptr [r12 + PN_refs], -1
    jne pno_bad
    mov qword ptr [r12 + PN_refs], 1
    mov [rbx + EXT_pending], r12
    mov rdi, rbx
    call ext_pending_take
    cmp rax, r12
    jne pno_bad
    cmp qword ptr [rbx + EXT_pending], 0
    jne pno_bad
    mov [rbx + EXT_pending], rax
    mov rdi, rbx
    call ext_pending_clear
    cmp qword ptr [rbx + EXT_pending], 0
    jne pno_bad
    mov qword ptr [rip + pno_stage], 3
    mov qword ptr [rip + pno_fail_alloc], 1
    call pno_create
    test rax, rax
    jnz pno_bad
    cmp rdx, -12
    jne pno_bad
    mov qword ptr [rip + pno_fail_alloc], 0
    lea rdi, [rip + pno_ext]
    lea rsi, [rip + pno_wrong]
    call ext_pending_new
    test rax, rax
    jnz pno_bad
    cmp rdx, -22
    jne pno_bad
    lea rdi, [rip + pno_ext]
    lea rsi, [rip + pno_empty_key]
    call ext_pending_new
    test rax, rax
    jnz pno_bad
    cmp rdx, -22
    jne pno_bad
    mov qword ptr [rip + pno_stage], 4
    lea rdi, [rip + pno_long_owner]
    mov esi, 'o'
    mov edx, PN_LIMIT + 1
    call memset
    mov byte ptr [rip + pno_long_owner + PN_LIMIT], 0
    lea rax, [rip + pno_long_owner]
    mov [rbx + EXT_owner], rax
    call pno_create
    test rax, rax
    jz pno_bad
    cmp qword ptr [rax + PN_ownerlen], PN_LIMIT
    jne pno_bad
    mov rdi, rax
    call ext_pending_release
    mov byte ptr [rip + pno_long_owner + PN_LIMIT], 'o'
    call pno_create
    test rax, rax
    jnz pno_bad
    cmp rdx, -22
    jne pno_bad
    lea rax, [rip + pno_owner]
    mov [rbx + EXT_owner], rax
    mov qword ptr [rip + pno_stage], 5
    lea rdi, [rip + pno_long_wire]
    mov esi, 'b'
    mov edx, PN_LIMIT + 3
    call memset
    mov byte ptr [rip + pno_long_wire], 'a'
    mov byte ptr [rip + pno_long_wire + 1], '.'
    mov byte ptr [rip + pno_long_wire + PN_LIMIT + 2], 0
    mov rdi, rbx
    lea rsi, [rip + pno_long_wire]
    call ext_pending_new
    test rax, rax
    jz pno_bad
    cmp qword ptr [rax + PN_keylen], PN_LIMIT
    jne pno_bad
    mov rdi, rax
    call ext_pending_release
    mov byte ptr [rip + pno_long_wire + PN_LIMIT + 2], 'b'
    mov rdi, rbx
    lea rsi, [rip + pno_long_wire]
    call ext_pending_new
    test rax, rax
    jnz pno_bad
    cmp rdx, -22
    jne pno_bad
    mov qword ptr [rip + pno_stage], 6
    mov rdi, 0x7fffffffffffffff
    call pno_set_revision
    call pno_create
    test rax, rax
    jnz pno_bad
    cmp rdx, -75
    jne pno_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + pno_live]
    jne pno_bad
    lea rdi, [rip + pno_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + pno_ok]
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
pno_wrong: .asciz "z.x"
pno_empty_key: .asciz "a."
pno_ok: .asciz "ok pending command ownership and failures\n"
