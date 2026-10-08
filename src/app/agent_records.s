# Bounded metadata transport shared by the index worker and agents panel.
.include "rhun.inc"
.text

# agent_table_find(table, mask, path) -> AS* or 0, exact path identity.
FN agent_table_find
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, r14
    call strlen
    mov rsi, rax
    mov rdi, r14
    call hash_line
    mov rbx, rax
1:  and rbx, r13
    mov r15, [r12 + rbx*8]
    test r15, r15
    jz 2f
    mov rdi, [r15 + AS_path]
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jnz 3f
    inc rbx
    jmp 1b
2:  xor eax, eax
    EPILOGUE
3:  mov rax, r15
    EPILOGUE

# agent_table_put(table, mask, AS*). Caller ensures uniqueness and spare capacity.
FN agent_table_put
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, [r14 + AS_path]
    call strlen
    mov rsi, rax
    mov rdi, [r14 + AS_path]
    call hash_line
1:  and rax, r13
    cmp qword ptr [r12 + rax*8], 0
    je 2f
    inc rax
    jmp 1b
2:  mov [r12 + rax*8], r14
    EPILOGUE

FN agent_records_free
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [r12 + VEC_len]
    jae 2f
    mov rax, [r12 + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call agent_session_free
    inc rbx
    jmp 1b
2:  mov rdi, r12
    call vec_free
    EPILOGUE

# agent_record_encode(sb, AS*): 88-byte fixed header, then four byte strings.
FN agent_record_encode
    PROLOGUE 96
    mov r12, rdi
    mov r13, rsi
    mov eax, [r13 + AS_kind]
    mov [rsp], rax
    mov eax, [r13 + AS_pad]     # worker completed both bounded title reads
    shl eax, 1
    or eax, [r13 + AS_titled]
    mov ecx, [r13 + AS_replaced]
    shl ecx, 2
    or eax, ecx
    mov [rsp + 8], rax
    mov rax, [r13 + AS_recency]
    mov [rsp + 16], rax
    mov rax, [r13 + AS_stamp]
    mov [rsp + 24], rax
    mov rax, [r13 + AS_prefix_hash]
    mov [rsp + 64], rax
    mov rax, [r13 + AS_title_off]
    mov [rsp + 72], rax
    mov rax, [r13 + AS_title_rev]
    mov [rsp + 80], rax
    xor ebx, ebx
1:  lea rax, [rip + record_fields]
    mov ecx, [rax + rbx*4]
    mov rdi, [r13 + rcx]
    xor eax, eax
    test rdi, rdi
    jz 2f
    call strlen
2:  mov [rsp + rbx*8 + 32], rax
    inc ebx
    cmp ebx, 4
    jb 1b
    mov rdi, r12
    mov rsi, rsp
    mov edx, 88
    call sb_push
    xor ebx, ebx
3:  lea rax, [rip + record_fields]
    mov ecx, [rax + rbx*4]
    mov rsi, [r13 + rcx]
    mov rdx, [rsp + rbx*8 + 32]
    mov rdi, r12
    call sb_push
    inc ebx
    cmp ebx, 4
    jb 3b
    EPILOGUE

# agent_records_decode(packet, bytes, out VEC*) -> 1 valid, 0 invalid.
# Caller validates magic. No mutation escapes until the entire packet is valid.
FN agent_records_decode
    PROLOGUE 48
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r13, 32
    jb .Ldecode_bad
    cmp r13, 1 << 26
    ja .Ldecode_bad
    mov rax, [r12 + 8]
    cmp rax, 100000
    ja .Ldecode_bad
    cmp rax, [r12 + 16]
    ja .Ldecode_bad
    lea rcx, [r13 - 32]
    cmp rcx, [r12 + 24]
    jne .Ldecode_bad
    mov [rsp], rax             # records left
    mov ebx, 16
1:  lea rcx, [rax*2]
    cmp rbx, rcx
    ja 2f
    shl rbx, 1
    jmp 1b
2:  lea rdi, [rbx*8]
    call mem_alloc
    mov [rsp + 8], rax         # temporary uniqueness table
    dec rbx
    mov [rsp + 16], rbx
    add r12, 32
    sub r13, 32
.Ldecode_record:
    cmp qword ptr [rsp], 0
    je .Ldecode_end
    cmp r13, 88
    jb .Ldecode_fail
    mov rax, [r12]
    dec rax
    cmp rax, 2                  # kinds 1 to 3
    ja .Ldecode_fail
    cmp qword ptr [r12 + 8], 7
    ja .Ldecode_fail
    cmp qword ptr [r12 + 32], 0
    je .Ldecode_fail
    cmp qword ptr [r12 + 72], 0
    js .Ldecode_fail
    mov r15d, 88
    xor ebx, ebx
3:  mov rax, [r12 + rbx*8 + 32]
    cmp rax, 4096
    ja .Ldecode_fail
    cmp ebx, 2
    jne 4f
    cmp rax, 120
    ja .Ldecode_fail
4:  add r15, rax
    inc ebx
    cmp ebx, 4
    jb 3b
    cmp r15, r13
    ja .Ldecode_fail
    mov [rsp + 24], r15
    lea rax, [r12 + 88]
    mov ecx, r15d
    sub ecx, 88
5:  test ecx, ecx
    jz 6f
    cmp byte ptr [rax], 0
    je .Ldecode_fail
    inc rax
    dec ecx
    jmp 5b
6:  mov edi, AS_SIZE
    call mem_alloc
    mov r15, rax
    mov rax, [r12]
    mov [r15 + AS_kind], eax
    mov rax, [r12 + 8]
    mov ecx, eax
    shr ecx, 2
    mov [r15 + AS_replaced], ecx
    mov ecx, eax
    and ecx, 1
    mov [r15 + AS_titled], ecx
    shr eax, 1
    and eax, 1
    mov [r15 + AS_pad], eax
    mov rax, [r12 + 16]
    mov [r15 + AS_recency], rax
    xor edx, edx
    mov ecx, 1000000000
    div rcx
    mov [r15 + AS_mtime], rax
    mov rax, [r12 + 24]
    mov [r15 + AS_stamp], rax
    mov rax, [r12 + 64]
    mov [r15 + AS_prefix_hash], rax
    mov rax, [r12 + 72]
    mov [r15 + AS_title_off], rax
    mov rax, [r12 + 80]
    mov [r15 + AS_title_rev], rax
    lea rax, [r12 + 88]
    mov [rsp + 32], rax
    xor ebx, ebx
7:  mov rsi, [r12 + rbx*8 + 32]
    test rsi, rsi
    jz 8f
    mov rdi, [rsp + 32]
    add [rsp + 32], rsi
    call mem_dup
    lea rcx, [rip + record_fields]
    mov ecx, [rcx + rbx*4]
    mov [r15 + rcx], rax
8:  inc ebx
    cmp ebx, 4
    jb 7b
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, [r15 + AS_path]
    call agent_table_find
    test rax, rax
    jz 9f
    mov rdi, r15
    call agent_session_free
    jmp .Ldecode_fail
9:  mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, r15
    call agent_table_put
    mov rdi, r14
    mov esi, 8
    call vec_push
    mov [rax], r15
    mov rax, [rsp + 24]
    add r12, rax
    sub r13, rax
    dec qword ptr [rsp]
    jmp .Ldecode_record
.Ldecode_end:
    test r13, r13
    jnz .Ldecode_fail
    mov rdi, [rsp + 8]
    call mem_free
    mov eax, 1
    EPILOGUE
.Ldecode_fail:
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, r14
    call agent_records_free
.Ldecode_bad:
    xor eax, eax
    EPILOGUE

.section .rodata
record_fields: .long AS_path, AS_cwd, AS_title, AS_worktree
