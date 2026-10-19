# Direct ownership/budget/vector invariants, without application initialization.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
op_vec: .zero VEC_SIZE
op_live: .quad 0
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + op_live], rax
    mov edi, 63
    call ext_prepare_owner_create
    test rax, rax
    jnz .Lop_bad
    cmp rdx, -EV_RESOURCE
    jne .Lop_bad
    mov edi, 384              # prefixed EO128 plus minimal private object256
    call ext_prepare_owner_create
    test rax, rax
    jz .Lop_bad
    mov rbx, rax
    mov rdi, rax
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lop_bad
    mov r12, rax
    cmp qword ptr [rbx + EO_used], 384
    jne .Lop_bad
    mov rdi, r12
    mov esi, 1
    call prep_owned_alloc
    test rax, rax
    jnz .Lop_bad
    cmp qword ptr [r12 + PO_error], -EV_RESOURCE
    jne .Lop_bad
    mov rdi, r12
    call prep_owned_dispose
    cmp qword ptr [rbx + EO_used], 128
    jne .Lop_bad
    mov rdi, rbx
    call ext_prepare_owner_release
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lop_bad
    mov rbx, rax
    mov rdi, rax
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lop_bad
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + op_text]
    mov edx, 3
    call prep_owned_dup
    test rax, rax
    jz .Lop_bad
    cmp dword ptr [rax], 0x00636261
    jne .Lop_bad
    mov rdi, r12
    mov rsi, rax
    call prep_owned_free
    test rax, rax
    jnz .Lop_bad
    xor r13d, r13d
1:  cmp r13, 100
    jae 2f
    mov rdi, r12
    lea rsi, [rip + op_vec]
    mov edx, 8
    call prep_owned_vec_push
    test rax, rax
    jz .Lop_bad
    cmp qword ptr [rax], 0
    jne .Lop_bad
    mov [rax], r13
    inc r13
    jmp 1b
2:  xor r13d, r13d
3:  cmp r13, 100
    jae 4f
    mov rax, [rip + op_vec + VEC_ptr]
    cmp [rax + r13*8], r13
    jne .Lop_bad
    inc r13
    jmp 3b
4:  mov rax, [rip + op_vec + VEC_ptr]
    mov [rsp], rax
    mov rax, [rip + op_vec + VEC_len]
    mov [rsp + 8], rax
    mov rax, [rip + op_vec + VEC_cap]
    mov [rsp + 16], rax
    mov rdi, r12
    mov rsi, PREP_CAP
    call prep_owned_alloc
    test rax, rax
    jnz .Lop_bad
    mov rdi, r12
    lea rsi, [rip + op_vec]
    mov edx, 8
    call prep_owned_vec_push
    test rax, rax
    jnz .Lop_bad
    mov rax, [rsp]
    cmp rax, [rip + op_vec + VEC_ptr]
    jne .Lop_bad
    mov rax, [rsp + 8]
    cmp rax, [rip + op_vec + VEC_len]
    jne .Lop_bad
    mov rax, [rsp + 16]
    cmp rax, [rip + op_vec + VEC_cap]
    jne .Lop_bad
    mov rdi, r12
    call prep_owned_dispose
    cmp qword ptr [rbx + EO_used], 128
    jne .Lop_bad
    mov rdi, rbx
    call ext_prepare_owner_release
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + op_live]
    jne .Lop_bad
    xor eax, eax
    EPILOGUE
.Lop_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
op_text: .asciz "abc"
