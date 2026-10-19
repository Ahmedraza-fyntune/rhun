# Nonblocking parent input for the fixed settings helper.
.include "rhun.inc"
.include "app/extstorejob.inc"
.include "app/extsettingsnative.inc"
.ifndef WINDOWS
.text
FN ext_settings_native_close_input
    test rdi, rdi
    jz .Lecnp_bad
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + ECN_closing], 1
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
    mov rdi, [rbx + ECN_input]
    mov qword ptr [rbx + ECN_input], -1
    test rdi, rdi
    js 1f
    SYS SYS_close
    test rax, rax
    jns 2f
    cmp qword ptr [rbx + ECN_cleanup], 0
    jne 2f
    mov [rbx + ECN_cleanup], rax
2:  EPILOGUE
1:  xor eax, eax
    EPILOGUE
.Lecnp_bad:
    mov rax, -22
    ret
FN ext_settings_native_write_poll
    PROLOGUE
    mov rbx, rdi
    xor r13d, r13d
    test rbx, rbx
    jz .Lecnp_poll_bad
    test rsi, rsi
    jz .Lecnp_poll_bad
    cmp rsi, 65536
    ja .Lecnp_poll_bad
    mov rax, [rbx + ECN_write_error]
    test rax, rax
    js .Lecnp_poll_return
    mov r12, [rbx + ECN_length]
    test r12, r12
    jz .Lecnp_poll_done
    sub r12, [rbx + ECN_offset]
    cmp r12, rsi
    jbe 1f
    mov r12, rsi
1:  mov rdi, [rbx + ECN_input]
    lea rsi, [rbx + ECN_chunk]
    add rsi, [rbx + ECN_offset]
    mov rdx, r12
    mov qword ptr [rbx + ECN_submitted], 1
    SYS SYS_write
    cmp rax, -11
    je .Lecnp_poll_pending
    cmp rax, -4
    je .Lecnp_poll_pending
    test rax, rax
    js .Lecnp_poll_error
    jz .Lecnp_poll_io
    cmp rax, r12
    ja .Lecnp_poll_io
    mov r13, rax
    add [rbx + ECN_offset], rax
    mov rax, [rbx + ECN_offset]
    cmp rax, [rbx + ECN_length]
    jb .Lecnp_poll_pending
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
.Lecnp_poll_done:
    mov eax, 1
    jmp .Lecnp_poll_return
.Lecnp_poll_pending:
    xor eax, eax
    jmp .Lecnp_poll_return
.Lecnp_poll_io:
    mov rax, -5
.Lecnp_poll_error:
    mov [rbx + ECN_write_error], rax
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
.Lecnp_poll_return:
    mov rdx, r13
    mov rcx, [rbx + ECN_submitted]
    EPILOGUE
.Lecnp_poll_bad:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.endif
