# Startup-only path spelling capture. No lazy UI qualification or filesystem normalization.
.include "rhun.inc"
.include "app/themecapture.inc"
.bss
.p2align 3
tc_start_state: .zero 8
tc_start_length: .zero 8
tc_start_cwd: .zero 4096
.text
FN theme_capture_startup_begin
    cmp qword ptr [rip + tc_start_state], 0
    jne .Ltcs_busy
    PROLOGUE
    lea rdi, [rip + tc_start_cwd]
.ifdef WINDOWS
    call win_tc_startup_cwd
.else
    mov esi, 4096
    SYS SYS_getcwd
.endif
    test rax, rax
    js .Ltcs_begin_done
    lea rdi, [rip + tc_start_cwd]
    call tc_path_len
    test rax, rax
    js .Ltcs_begin_done
    mov [rip + tc_start_length], rax
    mov qword ptr [rip + tc_start_state], 1
    xor eax, eax
.Ltcs_begin_done:
    EPILOGUE
.Ltcs_busy:
    mov rax, -16
    ret
FN theme_capture_startup_seal
    cmp qword ptr [rip + tc_start_state], 1
    jne .Ltcs_busy
    mov qword ptr [rip + tc_start_state], 2
    xor eax, eax
    ret
# snapshot(rawCstr)->owned ordinary absolute Cstr/errno. Small legacy allocator owner.
# The base owner accounts this allocation; release through ordinary mem_free is infallible.
FN theme_capture_path_snapshot
    cmp qword ptr [rip + tc_start_state], 1
    jne .Ltcs_path_busy
    PROLOGUE
    mov rbx, rdi
    mov esi, TC_PATH_MAX
    call ext_root_length
    test rax, rax
    jle .Ltcs_path_bad_length
    mov r12, rax
.ifdef WINDOWS
    mov rdi, rbx
    mov rsi, r12
    call win_tc_startup_path
    EPILOGUE
.else
    xor r13d, r13d
    cmp byte ptr [rbx], '/'
    je 1f
    mov r13, [rip + tc_start_length]
    cmp r13, 1
    je 1f
    inc r13
1:  mov r14, r12
    add r14, r13
    cmp r14, TC_PATH_MAX
    ja .Ltcs_path_long
    lea rdi, [r14 + 1]
    call mem_alloc_try
    test rax, rax
    jz .Ltcs_path_oom
    mov r15, rax
    test r13, r13
    jz 3f
    mov rdi, r15
    lea rsi, [rip + tc_start_cwd]
    mov rdx, [rip + tc_start_length]
    call memcpy
    cmp r13, 1
    je 3f
    mov byte ptr [r15 + r13 - 1], '/'
3:  lea rdi, [r15 + r13]
    mov rsi, rbx
    lea rdx, [r12 + 1]
    call memcpy
    mov rax, r15
    xor edx, edx
    EPILOGUE
.endif
.Ltcs_path_bad_length:
    test rax, rax
    js 4f
    mov rax, -22
4:  mov rdx, rax
    xor eax, eax
    EPILOGUE
.Ltcs_path_long:
    mov rdx, -36
    jmp .Ltcs_path_null
.Ltcs_path_oom:
    mov rdx, -12
.Ltcs_path_null:
    xor eax, eax
    EPILOGUE
.Ltcs_path_busy:
    xor eax, eax
    mov rdx, -16
    ret
