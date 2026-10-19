.include "rhun.inc"
.text
FN main
    PROLOGUE TXF_SIZE+TD_SIZE
    mov r15, [rip + g_mem_live]
    mov rbx, rsp
    lea r14, [rbx + TXF_SIZE]
    # Two successful calls consume one shared budget and detach all borrows.
    mov edi, 300
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov r13d, 2
.Lta_shared:
    mov rdi, r12
    lea rsi, [rip + desc]
    call snippet_transform_execute
    cmp ecx, 1
    jne .Lta_bad
    cmp rdx, 1
    jne .Lta_bad
    cmp byte ptr [rax], 120
    jne .Lta_bad
    mov rdi, rax
    call mem_free
    cmp qword ptr [r12 + RX_ready], 0
    jne .Lta_bad
    cmp qword ptr [r12 + RX_program], 0
    jne .Lta_bad
    cmp qword ptr [r12 + RX_input], 0
    jne .Lta_bad
    dec r13
    jnz .Lta_shared
    cmp qword ptr [r12 + RX_work], 0
    jne .Lta_bad
    mov rdi, r12
    lea rsi, [rip + desc]
    call snippet_transform_execute
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_error], RX_WORK_ERROR
    jne .Lta_bad
    cmp qword ptr [r12 + RX_tstage], TRANSFORM_FORMAT
    jne .Lta_bad
    mov qword ptr [r12 + RX_tstage], 77
    mov qword ptr [r12 + RX_trecord], 88
    mov qword ptr [r12 + RX_errbyte], 42
    mov qword ptr [r12 + RX_ready], 1
    mov rdi, r12
    xor esi, esi
    call snippet_transform_execute
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_tstage], 77
    jne .Lta_bad
    cmp qword ptr [r12 + RX_trecord], 88
    jne .Lta_bad
    cmp qword ptr [r12 + RX_errbyte], 42
    jne .Lta_bad
    cmp qword ptr [r12 + RX_ready], 1
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    # An empty input may have a null pointer, including a no-match result.
    mov edi, 116
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + empty_desc]
    call snippet_transform_execute
    cmp ecx, 1
    jne .Lta_bad
    or rax, rdx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_work], 0
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    # Malformed raw format bytes report validator offsets and retain no views.
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + bad_desc]
    call snippet_transform_execute
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_error], RX_REPLACEMENT_ERROR
    jne .Lta_bad
    cmp qword ptr [r12 + RX_tstage], TRANSFORM_FORMAT
    jne .Lta_bad
    cmp qword ptr [r12 + RX_errbyte], 0
    jne .Lta_bad
    cmp qword ptr [r12 + RX_work], 9968
    jne .Lta_bad
    cmp qword ptr [r12 + RX_ready], 0
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    # Argument length checks happen before reading even the format header.
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov rdi, r14
    lea rsi, [rip + empty_desc]
    mov ecx, TD_SIZE
    rep movsb
    mov qword ptr [r14 + TD_format], 0
    mov qword ptr [r14 + TD_flen], 31
    mov rdi, r12
    mov rsi, r14
    call snippet_transform_execute
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_error], RX_REPLACEMENT_ERROR
    jne .Lta_bad
    cmp qword ptr [r12 + RX_work], 10000
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    # The entry clock rejects an expired batch before matcher input reads.
    mov edi, 10000
    mov esi, 1
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov rdi, r12
    lea rsi, [rip + desc]
    call snippet_transform_execute
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_error], RX_TIME_ERROR
    jne .Lta_bad
    cmp qword ptr [r12 + RX_tstage], TRANSFORM_FORMAT
    jne .Lta_bad
    cmp qword ptr [r12 + RX_work], 10000
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    # Finish must free final, intermediate and pending case buffers on timeout.
    mov rdi, rbx
    mov ecx, TXF_SIZE/8
    xor eax, eax
    rep stosq
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lta_bad
    mov r12, rax
    mov [rbx + SC_rx], rax
    mov rdi, rbx
    lea rsi, [rbx + SC_out]
    lea rdx, [rip + input]
    mov ecx, 1
    mov r8d, 4194304
    call snippet_case_append
    test eax, eax
    jz .Lta_bad
    mov rdi, rbx
    lea rsi, [rbx + SC_prep]
    lea rdx, [rip + input]
    mov ecx, 1
    mov r8d, 8388608
    call snippet_case_append
    test eax, eax
    jz .Lta_bad
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz .Lta_bad
    mov [rbx + TXF_temp], rax
    mov qword ptr [r12 + RX_deadline], 1
    mov qword ptr [r12 + RX_ready], 1
    lea rax, [rip + regex]
    mov [r12 + RX_program], rax
    mov rdi, rbx
    call snippet_transform_finish
    or rax, rdx
    or rax, rcx
    jnz .Lta_bad
    cmp qword ptr [r12 + RX_error], RX_TIME_ERROR
    jne .Lta_bad
    cmp qword ptr [r12 + RX_tstage], TRANSFORM_OUTPUT
    jne .Lta_bad
    cmp qword ptr [rbx + TXF_temp], 0
    jne .Lta_bad
    cmp qword ptr [rbx + SC_out + SB_ptr], 0
    jne .Lta_bad
    cmp qword ptr [rbx + SC_prep + SB_ptr], 0
    jne .Lta_bad
    cmp qword ptr [r12 + RX_ready], 0
    jne .Lta_bad
    cmp qword ptr [r12 + RX_program], 0
    jne .Lta_bad
    mov rdi, r12
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lta_bad
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lta_bad:
    lea rdi, [rip + bad]
    call log_cstr
    mov eax, 1
    EPILOGUE
.section .rodata
ok: .asciz "ok snippet transform API\n"
bad: .asciz "failed snippet transform API\n"
input: .byte 97
.p2align 3
regex:
.long 0x58524e52,1,0x00100000,0,0,2,0,0,0,0,80,0
.long 1,97,0,0
.long 0,0,0,0
format:
.long 0x46524e52,1,0x00100000,1,1,57,0,0
.long 0,0,0,1,0,0
.byte 120
.p2align 3
empty_format:
.long 0x46524e52,1,0x00100000,0,0,32,0,0
bad_format: .zero 32
.p2align 3
desc: .quad regex,80,format,57,input,1
empty_desc: .quad regex,80,empty_format,32,0,0
bad_desc: .quad regex,80,bad_format,32,0,0
