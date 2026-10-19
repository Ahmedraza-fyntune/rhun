# Genuine immutable supplier buffers at the exact build-time source and word limits.
.bss
.p2align 3
cgbt_limit_bytes: .zero 1024 * 1024 + 2
cgbt_builtin_bytes: .quad 0
cgbt_builtin_words: .quad 0
cgbt_builtin_bindings: .quad 0
cgbt_heavy_bindings: .quad 0
.globl cgbt_builtin_override
cgbt_builtin_override: .quad 0
cgbt_builtin_table: .zero 1026 * CMD_SIZE
.text
# buffer,length,rows,lastLength -> CG retaining a real ready EP and ledger-owned PCs.
cgbt_keys_owner:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    call cgbt_new
    mov rbx, rax
    lea rdi, [rip + cgbt_one]
    lea rsi, [rip + cgbt_tool]
    xor edx, edx
    call cgbt_ep
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + cgbt_run]
    lea rdx, [rip + cgbt_dupval]
    call cgbt_command
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call prep_owned_dup
    test rax, rax
    jz cgbt_fail
    mov r14, rax
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 24]
    call prep_owned_dup
    test rax, rax
    jz cgbt_fail
    mov r15, rax
    mov r13, [r12 + EP_commands]
    mov rdi, r12
    imul rsi, [rsp + 16], PC_SIZE
    call prep_owned_alloc
    test rax, rax
    jz cgbt_fail
    mov [r12 + EP_commands], rax
    mov rcx, [rsp + 16]
    mov [r12 + EP_commands + VEC_len], rcx
    mov [r12 + EP_commands + VEC_cap], rcx
    mov [r12 + EP_ext + EXT_ncmd], ecx
    mov [rsp], rax
1:  mov rdi, [rsp]
    mov rsi, r13
    mov edx, PC_SIZE
    call memcpy
    mov rax, [rsp]
    mov [rax + CMD_keys], r14
    add qword ptr [rsp], PC_SIZE
    dec qword ptr [rsp + 16]
    jnz 1b
    mov [rax + CMD_keys], r15
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_exts + 17 * EXT_SIZE]
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    mov rax, rbx
    EPILOGUE
cgbt_build_limits:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 17
    call cgbt_new
    mov rbx, rax
    mov rdi, rax
    call cgbt_build
    test rax, rax
    jnz cgbt_fail
    mov rax, [rbx + CG_defaultbytes]
    mov [rip + cgbt_builtin_bytes], rax
    mov rax, [rbx + CG_wordtokens]
    mov [rip + cgbt_builtin_words], rax
    mov rax, [rbx + CG_bindings + VEC_len]
    mov [rip + cgbt_builtin_bindings], rax
    mov rdi, rbx
    call cgbt_abort
    # Whitespace still counts as source bytes. Exact1MiB succeeds, next byte refuses.
    xor r14d, r14d
.Lcgbtl_source:
    lea rdi, [rip + cgbt_limit_bytes]
    mov esi, ' '
    mov edx, 1024 * 1024 + 1
    call memset
    lea rsi, [r14 + 1024 * 1024]
    lea rdi, [rip + cgbt_limit_bytes]
    mov edx, 1
    mov rcx, rsi
    call cgbt_keys_owner
    mov rbx, rax
    # Mutation after capture proves the long strings belong to EP, not this fixture buffer.
    mov byte ptr [rip + cgbt_limit_bytes], '!'
    mov rdi, rbx
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtl_source
    # A single unknown key word at KC_CAP is valid to ignore, one extra byte is resource failure.
    xor r14d, r14d
.Lcgbtl_word:
    mov qword ptr [rip + cgbt_stage], 18
    lea rdi, [rip + cgbt_limit_bytes]
    mov esi, 'z'
    mov edx, KC_CAP + 1
    call memset
    lea rdi, [rip + cgbt_limit_bytes]
    lea rsi, [r14 + KC_CAP]
    mov edx, 1
    mov rcx, rsi
    call cgbt_keys_owner
    mov rbx, rax
    mov rdi, rax
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtl_word
    # Exactly16MiB aggregate defaults including actual builtins, then one extra byte.
    xor r14d, r14d
.Lcgbtl_bytes:
    mov qword ptr [rip + cgbt_stage], 19
    lea rdi, [rip + cgbt_limit_bytes]
    mov esi, ' '
    mov edx, 1024 * 1024
    call memset
    lea rdi, [rip + cgbt_limit_bytes]
    mov esi, 1024 * 1024
    mov edx, 16
    mov ecx, 1024 * 1024
    sub rcx, [rip + cgbt_builtin_bytes]
    add rcx, r14
    call cgbt_keys_owner
    mov rbx, rax
    mov rdi, rax
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + CG_defaultbytes], 16 * 1024 * 1024
    jne cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtl_bytes
    # Actual words, including the builtins, reach262144; the next token must refuse.
    xor r14d, r14d
.Lcgbtl_tokens:
    mov qword ptr [rip + cgbt_stage], 20
    mov r15d, 262144
    sub r15, [rip + cgbt_builtin_words]
    add r15, r14
    lea rdi, [rip + cgbt_limit_bytes]
    mov rcx, r15
1:  mov word ptr [rdi], 0x2061
    add rdi, 2
    dec rcx
    jnz 1b
    lea rdi, [rip + cgbt_limit_bytes]
    lea rsi, [r15 * 2 - 1]
    mov edx, 1
    mov rcx, rsi
    call cgbt_keys_owner
    mov rbx, rax
    mov rdi, rax
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + CG_wordtokens], 262144
    jne cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtl_tokens
    # Real unique numeric keys reach65536 bindings; no synthetic table count.
    # Small collision cases above already prove wrap. Use real hash for this large cap case.
    mov qword ptr [rip + cgbt_heavy_bindings], 1
    xor r14d, r14d
.Lcgbtl_bindings:
    mov qword ptr [rip + cgbt_stage], 21
    mov r15d, 65536
    sub r15, [rip + cgbt_builtin_bindings]
    add r15, r14
    lea rdi, [rip + cgbt_limit_bytes]
    xor r8d, r8d
.Lcgbtl_key:
    lea rsi, [rip + cgbt_numeric_prefix]
    mov ecx, 7
1:  mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz 1b
    lea r9, [r8 + 0x020000]
    mov ecx, 20
    lea r10, [rip + cgbt_limit_hex]
2:  mov rax, r9
    shr rax, cl
    and eax, 15
    mov al, [r10 + rax]
    mov [rdi], al
    inc rdi
    sub ecx, 4
    jns 2b
    mov byte ptr [rdi], ' '
    inc rdi
    inc r8
    cmp r8, r15
    jb .Lcgbtl_key
    lea rdi, [rip + cgbt_limit_bytes]
    imul rsi, r15, 14
    dec rsi
    mov edx, 1
    mov rcx, rsi
    call cgbt_keys_owner
    mov rbx, rax
    mov rdi, rax
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + CG_bindings + VEC_len], 65536
    jne cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtl_bindings
    mov qword ptr [rip + cgbt_heavy_bindings], 0
    call cgbt_builtin_limits
    call cgbt_owner_budget
    EPILOGUE
.section .rodata
cgbt_numeric_prefix: .ascii "ctrl+0x"

.text
cgbt_builtin_limits:
    PROLOGUE
    xor r14d, r14d
.Lcgbtbi_case:
    mov qword ptr [rip + cgbt_stage], 28
    lea rdi, [rip + cgbt_builtin_table]
    xor esi, esi
    mov edx, 1026 * CMD_SIZE
    call memset
    lea rdi, [rip + cgbt_builtin_table]
    lea rcx, [r14 + 1024]
    lea r8, [rip + cgbt_synthetic_name]
    lea r9, [rip + cgbt_synthetic_empty]
    lea r10, [rip + cgbt_synthetic_fn]
1:  mov [rdi + CMD_name], r8
    mov [rdi + CMD_keys], r9
    mov [rdi + CMD_fn], r10
    mov [rdi + CMD_title], r8
    add rdi, CMD_SIZE
    dec rcx
    jnz 1b
    call cgbt_new
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + cgbt_long_combo]
    lea rdx, [rip + cgbt_missing_builtin]
    call cgbt_line
    lea rax, [rip + cgbt_builtin_table]
    mov [rip + cgbt_builtin_override], rax
    mov rdi, rbx
    call cgbt_build
    test r14, r14
    jnz 1f
    test rax, rax
    jnz cgbt_fail
    cmp qword ptr [rbx + CG_bindings + VEC_len], 1
    jne cgbt_fail
    mov r12, [rbx + CG_bindings]
    call keys_none_command
    cmp [r12 + KB_cmd], rax
    jne cgbt_fail
    jmp 2f
1:  cmp rax, -EV_RESOURCE
    jne cgbt_fail
2:  mov qword ptr [rip + cgbt_builtin_override], 0
    mov rdi, rbx
    call cgbt_abort
    inc r14
    cmp r14, 2
    jb .Lcgbtbi_case
    EPILOGUE
cgbt_owner_budget:
    PROLOGUE
    mov qword ptr [rip + cgbt_stage], 29
    call cgbt_new
    mov rbx, rax
    mov r12, [rax + PO_eo]
    mov r13, [r12 + EO_cap]
    mov rax, [r12 + EO_used]
    mov [r12 + EO_cap], rax
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    call command_generation_key_begin
    cmp rax, -EV_RESOURCE
    jne cgbt_fail
    cmp qword ptr [rbx + CG_openkey], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_nkeys], 0
    jne cgbt_fail
    cmp qword ptr [rbx + CG_keybytes], 0
    jne cgbt_fail
    mov rax, [r12 + EO_cap]
    cmp [r12 + EO_used], rax
    jne cgbt_fail
    mov [r12 + EO_cap], r13
    mov rdi, rbx
    call cgbt_abort
    EPILOGUE
cgbt_synthetic_fn:
    ret
.section .rodata
cgbt_synthetic_name: .asciz "synthetic"
cgbt_synthetic_empty: .asciz ""
cgbt_missing_builtin: .asciz "no-such-builtin"
