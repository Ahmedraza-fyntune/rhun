# Bounded regex scratch state, reversible writes and shared batch limits.
.include "rhun.inc"
.text
# snippet_regex_new(work, absolute monotonic deadline us; zero disables time) -> owned RX* or 0
FN snippet_regex_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp rdi, RX_WORK_MAX
    ja 8f
    mov edi, RX_SIZE
    call mem_alloc_try
    test rax, rax
    jz 8f
    mov [rax + RX_work], r12
    mov [rax + RX_deadline], r13
    mov qword ptr [rax + RX_pc], -1
    mov qword ptr [rax + RX_errpc], -1
    sub r12, 1024
    jnc 1f
    xor r12d, r12d
1:  mov [rax + RX_clockat], r12
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
FN snippet_regex_free
    jmp mem_free

# Sticky failure: existing diagnostics win. Never leave a publishable result.
FN snippet_regex_fail
    mov qword ptr [rdi + RX_hasmatch], 0
    cmp qword ptr [rdi + RX_error], 0
    jne 1f
    mov [rdi + RX_error], rsi
    mov rax, [rdi + RX_pc]
    mov [rdi + RX_errpc], rax
1:  xor eax, eax
    ret
# Check time even when too little work has occurred to reach a periodic threshold.
FN snippet_regex_clock
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + RX_error], 0
    jne 8f
    cmp qword ptr [rbx + RX_deadline], 0
    je 9f
    call time_us
    cmp rax, [rbx + RX_deadline]
    jb 9f
    mov rdi, rbx
    mov esi, RX_TIME_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
# snippet_regex_spend(ctx, units) -> 1, or terminal work/deadline failure
FN snippet_regex_spend
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + RX_error], 0
    jne 8f
    cmp rsi, [rbx + RX_work]
    ja 7f
    sub [rbx + RX_work], rsi
    cmp qword ptr [rbx + RX_deadline], 0
    je 9f
    mov rax, [rbx + RX_work]
    cmp rax, [rbx + RX_clockat]
    ja 9f
    sub rax, 1024
    jnc 1f
    xor eax, eax
1:  mov [rbx + RX_clockat], rax
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz 8f
9:  mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_WORK_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE

# snippet_regex_write(ctx, value key, value) -> 1. Every changed word is reversible.
FN snippet_regex_write
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rbx + RX_error], 0
    jne 8f
    cmp r12, [rbx + RX_nvalues]
    jae 7f
    cmp [rbx + r12*8 + RX_values], r13
    je 9f
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rcx, [rbx + RX_ntrail]
    cmp rcx, RX_TRAIL_MAX
    jae 6f
    mov rax, rcx
    shl rax, 4
    lea rax, [rbx + rax + RX_trail]
    mov [rax], r12
    mov rdx, [rbx + r12*8 + RX_values]
    mov [rax + 8], rdx
    inc rcx
    mov [rbx + RX_ntrail], rcx
    mov [rbx + r12*8 + RX_values], r13
9:  mov eax, 1
    EPILOGUE
6:  mov esi, RX_TRAIL_ERROR
    jmp 1f
7:  mov esi, RX_STATE_ERROR
1:  mov rdi, rbx
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
# snippet_regex_rewind(ctx, previous trail size) -> 1
FN snippet_regex_rewind
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, [rbx + RX_ntrail]
    ja 7f
1:  cmp qword ptr [rbx + RX_error], 0
    jne 8f
    cmp r12, [rbx + RX_ntrail]
    je 9f
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    dec qword ptr [rbx + RX_ntrail]
    mov rax, [rbx + RX_ntrail]
    shl rax, 4
    lea rax, [rbx + rax + RX_trail]
    mov rcx, [rax]
    mov rdx, [rax + 8]
    mov [rbx + rcx*8 + RX_values], rdx
    jmp 1b
7:  mov rdi, rbx
    mov esi, RX_STATE_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
# snippet_regex_branch(ctx, fallback pc) -> 1
FN snippet_regex_branch
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rax, [rbx + RX_nbranches]
    cmp rax, RX_BRANCH_MAX
    jae 7f
    imul rax, rax, 24
    lea rax, [rbx + rax + RX_branches]
    mov [rax], r12
    mov rcx, [rbx + RX_pos]
    mov [rax + 8], rcx
    mov rcx, [rbx + RX_ntrail]
    mov [rax + 16], rcx
    inc qword ptr [rbx + RX_nbranches]
    mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_BRANCH_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
