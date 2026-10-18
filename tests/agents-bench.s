# Native agents-panel performance probe. Linked to the current application objects.
.include "rhun.inc"
.bss
.p2align 3
bench_ts: .zero 16
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 5
    jne 1f
    call agent_index_main
    EPILOGUE
1:  call raster_init
    call app_init
    mov edi, 1280
    mov esi, 800
    call headless_init
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    mov [rip + g_project], rax
    call git_set_project
    call bench_ns
    mov r12, rax
    call agents_set_project
    call bench_ns
    sub rax, r12
    mov rsi, rax
    lea rdi, [rip + label_queue]
    call bench_report
    call bench_wait
    test eax, eax
    jnz 9f
    call bench_ns
    sub rax, r12
    mov rsi, rax
    lea rdi, [rip + label_ready]
    call bench_report
    PCALL P_draw
    call bench_ns
    mov r12, rax
    mov ebx, 100
2:  call agents_poll
    dec ebx
    jnz 2b
    call bench_ns
    sub rax, r12
    mov rsi, rax
    lea rdi, [rip + label_poll]
    call bench_report
    call bench_ns
    mov r12, rax
    mov ebx, 10
3:  call agents_scan
    dec ebx
    jnz 3b
    call bench_ns
    sub rax, r12
    mov rsi, rax
    lea rdi, [rip + label_request]
    call bench_report
    call bench_wait
    test eax, eax
    jnz 9f
    call bench_ns
    mov r12, rax
    mov ebx, 100
4:  PCALL P_draw
    dec ebx
    jnz 4b
    call bench_ns
    sub rax, r12
    mov rsi, rax
    lea rdi, [rip + label_frame]
    call bench_report
    call agents_shutdown
    xor eax, eax
    EPILOGUE
9:  call agents_shutdown
    mov eax, 1
    EPILOGUE

bench_wait:
    PROLOGUE
    call time_ms
    lea r12, [rax + 30000]
1:  call agents_busy
    test eax, eax
    jz 2f
    call time_ms
    cmp rax, r12
    jae 3f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
2:  xor eax, eax
    EPILOGUE
3:  mov eax, 1
    EPILOGUE

bench_ns:
    mov edi, CLOCK_MONOTONIC
    lea rsi, [rip + bench_ts]
    SYS SYS_clock_gettime
    mov rax, [rip + bench_ts]
    imul rax, rax, 1000000000
    add rax, [rip + bench_ts + 8]
    ret
bench_report:
    push rbx
    mov rbx, rsi
    call log_cstr
    mov rdi, rbx
    call log_u64
    call log_nl
    pop rbx
    ret
.section .rodata
label_queue: .asciz "queue_ns="
label_ready: .asciz "ready_ns="
label_poll: .asciz "polls100_ns="
label_request: .asciz "requests10_ns="
label_frame: .asciz "frames100_ns="
