# Fallible owned copies and vectors for private extension preparation.
# Callers own valid source/vector allocations; invalid input and allocation failure return 0.
.include "rhun.inc"
.text

# mem_dup_try(source, length) -> owned NUL-terminated copy, or 0.
FN mem_dup_try
    mov rax, (1 << 40) - 1
    cmp rsi, rax
    jae .Lmtry_zero
    test rsi, rsi
    jz 1f
    test rdi, rdi
    jz .Lmtry_zero
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsi + 1]
    call mem_alloc_try
    test rax, rax
    jz 2f
    mov rdi, rax
    mov rsi, rbx
    mov rcx, r12
    rep movsb                  # allocation is zeroed, including the terminator
2:  EPILOGUE
.Lmtry_zero:
    xor eax, eax
    ret

# vec_reserve_try(vec, minimum_count, item_size) -> 1/0. Length never changes.
# Existing capacity bytes survive growth. No metadata/payload changes on failure.
FN vec_reserve_try
    test rdi, rdi
    jz .Lmtry_zero
    test rdx, rdx
    jz .Lmtry_zero
    mov rax, 1 << 40
    cmp rdx, rax
    jae .Lmtry_zero
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, (1 << 40) - 1
    xor edx, edx
    div r13
    mov r15, rax               # greatest count with bytes < 1 TiB
    cmp r12, r15
    ja .Lmtry_reserve_bad
    mov r14, [rbx + VEC_cap]
    cmp r14, r15
    ja .Lmtry_reserve_bad
    cmp [rbx + VEC_len], r14
    ja .Lmtry_reserve_bad
    mov rdi, [rbx + VEC_ptr]
    mov [rsp], rdi
    test r14, r14
    jnz .Lmtry_reserve_owned
    test rdi, rdi
    jnz .Lmtry_reserve_bad
    mov qword ptr [rsp + 8], 0
    jmp .Lmtry_reserve_capacity
.Lmtry_reserve_owned:
    test rdi, rdi
    jz .Lmtry_reserve_bad
    mov rax, r14
    imul rax, r13             # both count products are guarded by division above
    mov [rsp + 8], rax
    call mem_capacity
    cmp [rsp + 8], rax
    ja .Lmtry_reserve_bad
.Lmtry_reserve_capacity:
    cmp r12, r14
    jbe .Lmtry_reserve_ok
    lea rax, [r14 + r14]      # old cap <= 2^40-1, so doubling cannot overflow
    mov edx, 8
    cmp rax, rdx
    cmovb rax, rdx
    cmp rax, r12
    cmovb rax, r12
    cmp rax, r15
    cmova rax, r15
    mov [rsp + 16], rax
    imul rax, r13
    mov rdi, rax
    call mem_alloc_try
    test rax, rax
    jz .Lmtry_reserve_bad
    mov [rsp + 24], rax
    mov rdi, rax
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call memcpy
    mov rax, [rsp + 24]
    mov [rbx + VEC_ptr], rax
    mov rax, [rsp + 16]
    mov [rbx + VEC_cap], rax
    mov rdi, [rsp]
    call mem_free
.Lmtry_reserve_ok:
    mov eax, 1
    EPILOGUE
.Lmtry_reserve_bad:
    xor eax, eax
    EPILOGUE

# vec_push_try(vec, item_size) -> new zeroed slot or 0 unchanged.
FN vec_push_try
    test rdi, rdi
    jz .Lmtry_zero
    cmp qword ptr [rdi + VEC_len], -1
    je .Lmtry_zero
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdx, rsi
    mov rsi, [rdi + VEC_len]
    inc rsi
    call vec_reserve_try
    test eax, eax
    jz 1f
    mov rax, [rbx + VEC_len]
    imul rax, r12
    add rax, [rbx + VEC_ptr]
    mov r13, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, r12
    call memset
    inc qword ptr [rbx + VEC_len]
    mov rax, r13
1:  EPILOGUE
