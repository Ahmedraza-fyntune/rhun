# Request-file fixture. The native worker parser, never editor initialization.
.include "rhun.inc"
.include "app/extchoices.inc"
.include "app/extsettingswire.inc"
.bss
.p2align 3
swt_out: .zero EC_BATCH * EC_SIZE
swt_result: .zero 32
swt_header: .zero EW_HEADER
swt_encoder: .zero EWE_SIZE
swt_tag: .zero EWT_SIZE
swt_live: .quad 0
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne .Lswt_fail
    mov rax, [rip + g_mem_live]
    mov [rip + swt_live], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, EW_LIMIT + 128
    call file_read_limited_try
    test rax, rax
    jz .Lswt_fail
    mov rbx, rax
    mov r12, rdx
    cmp rdx, 8
    jb .Lswt_fail
    mov rax, [rbx]
    cmp rax, 1
    je .Lswt_check
    cmp rax, 2
    je .Lswt_delta
    cmp rax, 3
    je .Lswt_encode
    jmp .Lswt_fail
.Lswt_check:
    cmp r12, 8 + EWT_SIZE + EW_HEADER
    jne .Lswt_fail
    lea rdi, [rbx + 8 + EWT_SIZE]
    lea rsi, [rbx + 8]
    call ext_settings_wire_check
    mov [rip + swt_result], rax
    test rax, rax
    js .Lswt_write
    mov [rip + swt_result + 8], rdx
    mov [rip + swt_result + 16], r8
    mov [rip + swt_result + 24], r9
    jmp .Lswt_write
.Lswt_delta:
    cmp r12, 16
    jb .Lswt_fail
    mov rdx, [rbx + 8]
    lea rdi, [rbx + 16]
    mov rsi, r12
    sub rsi, 16
    lea rcx, [rip + swt_out]
    call ext_settings_wire_deltas
    mov [rip + swt_result], rax
    jmp .Lswt_write
.Lswt_encode:
    cmp r12, 8 + EWT_SIZE + 24
    jne .Lswt_fail
    lea rax, [rbx + 8]
    mov [rip + swt_encoder + EWE_tag], rax
    mov rax, [rbx + 40]
    mov [rip + swt_encoder + EWE_kind], rax
    mov rax, [rbx + 48]
    mov [rip + swt_encoder + EWE_length], rax
    mov rax, [rbx + 56]
    mov [rip + swt_encoder + EWE_round], rax
    lea rdi, [rip + swt_header]
    lea rsi, [rip + swt_encoder]
    call ext_settings_wire_encode
    mov [rip + swt_result], rax
    test rax, rax
    js .Lswt_write
    mov edi, 1
    lea rsi, [rip + swt_header]
    mov edx, EW_HEADER
    call write_all
    jmp .Lswt_cleanup
.Lswt_write:
    mov edi, 1
    lea rsi, [rip + swt_result]
    mov edx, 32
    call write_all
.Lswt_cleanup:
    mov rdi, rbx
    call mem_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + swt_live]
    jne .Lswt_fail
    xor eax, eax
    EPILOGUE
.Lswt_fail:
    mov edi, 70
    jmp sys_exit
