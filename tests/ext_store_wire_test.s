.include "rhun.inc"
.include "app/extstore.inc"
.section .rodata
eswt_tag:
    .quad 7,9
    .ascii "aaaaaaaaaaaaaaaa"
    .ascii "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
eswt_id: .ascii "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
eswt_previous: .ascii "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
eswt_Foo: .asciz "Foo"
eswt_foo: .asciz "foo"
eswt_con: .asciz "CON."
eswt_bad: .asciz "bad"
eswt_z: .asciz "z"
eswt_empty: .asciz "empty"
eswt_ok: .asciz "ok\n"
eswt_rejected: .asciz "rejected\n"
.text
eswt_fail:
    mov edi, 72
    call sys_exit
eswt_alloc:
    call mem_alloc_try
    test rax, rax
    jz eswt_fail
    ret
FN main
    PROLOGUE 64
    mov r15, [rip + g_mem_live]
    cmp qword ptr [rip + g_argc], 1
    jne .Leswt_unpack
    mov edi, ESS_SIZE
    call eswt_alloc
    mov rbx, rax
    mov edi, 4 * ESR_SIZE
    call eswt_alloc
    mov r12, rax
    mov [rbx + ESS_entries + VEC_ptr], rax
    mov qword ptr [rbx + ESS_entries + VEC_len], 4
    mov qword ptr [rbx + ESS_entries + VEC_cap], 4
    mov qword ptr [rbx + ESS_identity_count], 4
    mov qword ptr [rbx + ESS_root_entries], 2
    mov qword ptr [rbx + ESS_live], 1
    mov edi, 2 * ESO_SIZE
    call eswt_alloc
    mov r13, rax
    mov [rbx + ESS_owners + VEC_ptr], rax
    mov qword ptr [rbx + ESS_owners + VEC_len], 2
    mov qword ptr [rbx + ESS_owners + VEC_cap], 2
    lea rdi, [rbx + ESS_tag + EST_root_id]
    lea rsi, [rip + eswt_tag + EST_root_id]
    mov edx, 32
    call memcpy
    mov rdi, r13
    lea rsi, [rip + eswt_foo]
    call cstr_copy
    mov qword ptr [r13 + ESO_entries], 2
    lea rdi, [r13 + ESO_SIZE]
    lea rsi, [rip + eswt_Foo]
    call cstr_copy
    mov qword ptr [r13 + ESO_SIZE + ESO_entries], 2
    mov rdi, r12
    lea rsi, [rip + eswt_foo]
    call cstr_copy
    lea rdi, [r12 + ESR_name]
    lea rsi, [rip + eswt_z]
    call cstr_copy
    mov qword ptr [r12 + ESR_generation], 2
    mov qword ptr [r12 + ESR_entries], 2
    lea rdi, [r12 + ESR_index]
    mov esi, 2
    mov edx, EXI_REMOVED
    xor ecx, ecx
    xor r8d, r8d
    call ext_index_pack
    test eax, eax
    jz eswt_fail
    lea rdi, [r12 + ESR_SIZE]
    lea rsi, [rip + eswt_Foo]
    call cstr_copy
    lea rdi, [r12 + ESR_SIZE + ESR_name]
    lea rsi, [rip + eswt_con]
    call cstr_copy
    mov qword ptr [r12 + ESR_SIZE + ESR_generation], 1
    mov qword ptr [r12 + ESR_SIZE + ESR_entries], 1
    lea rdi, [r12 + ESR_SIZE + ESR_index]
    mov esi, 1
    mov edx, EXI_ACTIVE
    lea rcx, [rip + eswt_id]
    lea r8, [rip + eswt_previous]
    call ext_index_pack
    test eax, eax
    jz eswt_fail
    lea rdi, [r12 + ESR_SIZE * 2]
    lea rsi, [rip + eswt_foo]
    call cstr_copy
    lea rdi, [r12 + ESR_SIZE * 2 + ESR_name]
    lea rsi, [rip + eswt_empty]
    call cstr_copy
    mov qword ptr [r12 + ESR_SIZE * 2 + ESR_entries], 1
    lea rdi, [r12 + ESR_SIZE * 3]
    lea rsi, [rip + eswt_Foo]
    call cstr_copy
    lea rdi, [r12 + ESR_SIZE * 3 + ESR_name]
    lea rsi, [rip + eswt_bad]
    call cstr_copy
    mov qword ptr [r12 + ESR_SIZE * 3 + ESR_status], -5
    mov qword ptr [r12 + ESR_SIZE * 3 + ESR_generation], 9
    mov rdi, rbx
    lea rsi, [rip + eswt_tag]
    call ext_store_snapshot_pack_try
    test rax, rax
    jz eswt_fail
    mov r13, rax
    mov [rsp], rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + eswt_tag]
    call ext_store_snapshot_unpack_try
    test rax, rax
    jz eswt_fail
    cmp qword ptr [rax + ESS_proof_guard], 0
    jne eswt_fail
    cmp qword ptr [rax + ESS_proof_epoch], 0
    jne eswt_fail
    mov rdi, rax
    call ext_store_snapshot_free
    mov edi, 1
    mov rsi, r13
    mov rdx, [rsp]
    call write_all
    test rax, rax
    jnz eswt_fail
    mov rdi, r13
    call mem_free
    mov rdi, rbx
    call ext_store_snapshot_free
    jmp .Leswt_done
.Leswt_unpack:
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, ESW_WIRE_MAX
    call file_read_limited_try
    test rax, rax
    jnz 9f
    cmp rdx, -27
    jne eswt_fail
    lea rdi, [rip + eswt_rejected]
    call log_cstr
    jmp .Leswt_done
9:
    mov rbx, rax
    mov r12, rdx
    mov r13d, 32
1:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + eswt_tag]
    call ext_store_snapshot_unpack_try
    mov r14, rax
    mov rdi, rax
    call ext_store_snapshot_free
    dec r13
    jnz 1b
    mov rdi, rbx
    call mem_free
    lea rdi, [rip + eswt_rejected]
    test r14, r14
    jz 2f
    lea rdi, [rip + eswt_ok]
2:  call log_cstr
.Leswt_done:
    cmp r15, [rip + g_mem_live]
    jne eswt_fail
    xor eax, eax
    EPILOGUE
