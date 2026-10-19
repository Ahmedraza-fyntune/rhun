# An extension's launch inputs: the strings copied into its argv and environment for one start,
# freed once the program has been spawned (the vectors keep their buffers from start to start).
.include "rhun.inc"
.bss
.p2align 3
launch_argv: .quad 0
launch_env: .quad 0
launch_error: .quad 0           # the first failure, sticky until the next begin
launch_strings: .zero VEC_SIZE  # the copies, freed by ext_launch_scratch_end
.text
# ext_launch_scratch_begin(argv vec, env vec) -> rax 0, rdx 1 (ext_launch_scratch_end is due)
FN ext_launch_scratch_begin
    mov [rip + launch_argv], rdi
    mov [rip + launch_env], rsi
    mov qword ptr [rdi + VEC_len], 0
    mov qword ptr [rsi + VEC_len], 0
    mov qword ptr [rip + launch_error], 0
    xor eax, eax
    mov edx, 1
    ret

# ext_launch_scratch_error() -> rax the first failure (-ENOMEM), 0 when there was none
FN ext_launch_scratch_error
    mov rax, [rip + launch_error]
    ret

# ext_launch_scratch_push(vec, 8) -> a new zeroed slot, or 0 (the failure is kept)
FN ext_launch_scratch_push
    cmp qword ptr [rip + launch_error], 0
    jne launch_fail
    push rbx
    call vec_push_try
    pop rbx
    test rax, rax
    jz launch_fail
    ret
launch_fail:
    mov qword ptr [rip + launch_error], -12
    xor eax, eax
    ret

# ext_launch_scratch_dup(ptr, len) -> a NUL-terminated copy freed by the end, or 0
FN ext_launch_scratch_dup
    cmp qword ptr [rip + launch_error], 0
    jne launch_fail
    PROLOGUE
    call mem_dup_try
    test rax, rax
    jz 8f
    mov rbx, rax
    lea rdi, [rip + launch_strings]
    mov esi, 8
    call vec_push_try
    test rax, rax
    jz 7f
    mov [rax], rbx
    mov rax, rbx
    EPILOGUE
7:  mov rdi, rbx
    call mem_free
8:  call launch_fail
    EPILOGUE

# ext_launch_scratch_end(): the copies are freed and both vectors are empty again
FN ext_launch_scratch_end
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + launch_strings + VEC_len]
    jae 2f
    mov rax, [rip + launch_strings + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + launch_strings + VEC_len], 0
    mov rax, [rip + launch_argv]
    test rax, rax
    jz 3f
    mov qword ptr [rax + VEC_len], 0
3:  mov rax, [rip + launch_env]
    test rax, rax
    jz 4f
    mov qword ptr [rax + VEC_len], 0
4:  xor eax, eax
    EPILOGUE
