.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturedecode.inc"
.bss
.p2align 3
tcdrt_input: .zero TC_INPUT_CAP + TC_OUTPUT_CAP + 17
.text
tcdrt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 416
    cmp qword ptr [rip + g_argc], 2
    jne tcdrt_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 8]
    call parse_u64
    cmp rdx, rsi
    jne tcdrt_fail
    test rax, rax
    jz tcdrt_fail
    cmp rax, 65536
    ja tcdrt_fail
    mov r14, rax
    mov r15, [rip + g_mem_live]
    mov rdi, rsp
    xor esi, esi
    mov edx, 416
    call memset
    mov [rsp + 256], r14
    xor r12d, r12d
1:  xor edi, edi
    lea rsi, [rip + tcdrt_input]
    add rsi, r12
    mov edx, TC_INPUT_CAP + TC_OUTPUT_CAP + 17
    sub rdx, r12
    cmp rdx, 65536
    jbe 2f
    mov edx, 65536
2:  SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js tcdrt_fail
    jz 3f
    add r12, rax
    cmp r12, TC_INPUT_CAP + TC_OUTPUT_CAP + 16
    jbe 1b
    jmp tcdrt_fail
3:  cmp r12, 16
    jb tcdrt_fail
    lea rbx, [rip + tcdrt_input]
    mov rax, [rbx]
    cmp rax, TC_INPUT_CAP
    ja tcdrt_fail
    mov rcx, [rbx + 8]
    cmp rcx, TC_OUTPUT_CAP + 1
    ja tcdrt_fail
    add rcx, rax
    add rcx, 16
    cmp rcx, r12
    jne tcdrt_fail
    mov rdi, TCQ_SIZE
    call tc_alloc_try
    test rax, rax
    jz tcdrt_fail
    mov r13, rax
    mov qword ptr [r13 + TCQ_state], TCQ_OWNED
    mov rdi, [rbx]
    inc rdi
    call tc_alloc_try
    test rax, rax
    jz tcdrt_fail
    mov [r13 + TCQ_wire], rax
    mov rdi, rax
    lea rsi, [rbx + 16]
    mov rdx, [rbx]
    mov [r13 + TCQ_length], rdx
    call memcpy
    mov rdi, [r13 + TCQ_wire]
    mov rsi, [r13 + TCQ_length]
    call tc_request_validate
    test rax, rax
    jnz tcdrt_fail
    call tc_result_alloc
    test rax, rax
    jz tcdrt_fail
    mov r12, rax
    mov [r12 + TCS_request], r13
    mov qword ptr [r12 + TCS_reservation], 1
    mov qword ptr [rip + g_theme_capture_results], 1
    mov rdi, [rbx + 8]
    inc rdi
    call tc_alloc_try
    test rax, rax
    jz tcdrt_fail
    mov [r12 + TCS_wire], rax
    mov rdi, rax
    mov rsi, [rbx]
    lea rsi, [rbx + rsi + 16]
    mov rdx, [rbx + 8]
    mov [r12 + TCS_length], rdx
    call memcpy
.Ltcdrt_loop:
    mov rdi, r12
    mov rsi, rsp
    mov rdx, [rsp + 256]
    call tc_result_decode_step
    cmp rdx, [rsp + 256]
    ja tcdrt_fail
    mov [rsp + 336], rax
    mov [rsp + 344], rcx
    add [rsp + 352], rdx
    inc qword ptr [rsp + 360]
    cmp [rsp + 368], rdx
    jae 4f
    mov [rsp + 368], rdx
4:  cmp qword ptr [rsp + 360], 2000000
    ja tcdrt_fail
    cmp rax, 1
    jne .Ltcdrt_terminal
    test rcx, rcx
    jnz tcdrt_fail
    cmp qword ptr [r12 + TCS_validated], 0
    jne tcdrt_fail
    jmp .Ltcdrt_loop
.Ltcdrt_terminal:
    mov rax, [r12 + TCS_validated]
    mov [rsp + 376], rax
    mov rax, [r12 + TCS_state]
    mov [rsp + 384], rax
    mov rax, [r12 + TCS_count]
    mov [rsp + 392], rax
    mov rax, [rsp + 336]
    or rax, [rsp + 344]
    jz 5f
    cmp qword ptr [r12 + TCS_validated], 0
    jne tcdrt_fail
    mov rdi, r12
    xor esi, esi
    lea rdx, [rsp + 272]
    call theme_capture_result_row
    cmp rax, -16
    jne tcdrt_fail
    jmp 6f
5:  cmp qword ptr [r12 + TCS_validated], 1
    jne tcdrt_fail
6:  mov edi, 1
    lea rsi, [rsp + 336]
    mov edx, 64
    call write_all
    test rax, rax
    jnz tcdrt_fail
.Ltcdrt_release:
    mov rdi, r12
    call theme_capture_result_release
    test rax, rax
    jnz tcdrt_fail
    test rdx, rdx
    jz .Ltcdrt_release
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcdrt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcdrt_fail
    cmp r15, [rip + g_mem_live]
    jne tcdrt_fail
    xor eax, eax
    EPILOGUE
