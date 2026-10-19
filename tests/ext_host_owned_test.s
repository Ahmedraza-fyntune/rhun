# Every prepared endpoint has a retained host field before later operations.
.include "rhun.inc"
.section .rodata
ho_bytes: .ascii "hostpipe"
.bss
.p2align 3
ho_host: .zero EXT_SIZE
ho_buf: .zero 8
ho_live: .quad 0
ho_stage: .quad 0
.text
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + ho_live], rax
    mov qword ptr [rip + ho_stage], 1
    lea rbx, [rip + ho_host]
    mov dword ptr [rbx + EXT_in], -1
    mov dword ptr [rbx + EXT_out], -1
    mov dword ptr [rbx + EXT_log], -1
    mov dword ptr [rbx + EXT_host_child_in], -1
    mov dword ptr [rbx + EXT_host_child_out], -1
    mov dword ptr [rbx + EXT_activation_required], 1
    mov rdi, rbx
    xor esi, esi
    call ext_host_pipe_create
    test rax, rax
    jnz .Lhot_bad
    mov rdi, rbx
    mov esi, 1
    call ext_host_pipe_create
    test rax, rax
    jnz .Lhot_bad
    # Refusal does not overwrite or acquire over an owned pair.
    mov rdi, rbx
    mov esi, 1
    call ext_host_pipe_create
    cmp rax, -16
    jne .Lhot_bad
    mov edi, [rbx + EXT_in]
    lea rsi, [rip + ho_bytes]
    mov edx, 8
    SYS SYS_write
    cmp rax, 8
    jne .Lhot_bad
    mov edi, [rbx + EXT_host_child_in]
    lea rsi, [rip + ho_buf]
    mov edx, 8
    SYS SYS_read
    cmp rax, 8
    jne .Lhot_bad
    lea rdi, [rip + ho_buf]
    lea rsi, [rip + ho_bytes]
    mov edx, 8
    call memeq
    test eax, eax
    jz .Lhot_bad
    mov edi, [rbx + EXT_host_child_out]
    lea rsi, [rip + ho_bytes]
    mov edx, 8
    SYS SYS_write
    cmp rax, 8
    jne .Lhot_bad
    mov edi, [rbx + EXT_out]
    lea rsi, [rip + ho_buf]
    mov edx, 8
    SYS SYS_read
    cmp rax, 8
    jne .Lhot_bad
    mov rdi, rbx
    xor esi, esi
    mov edx, 1
    call ext_host_log_open
    test rax, rax
    jnz .Lhot_bad
    mov qword ptr [rip + ho_stage], 2
    xor r12d, r12d
1:  mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    test rax, rax
    jnz .Lhot_bad
    cmp rdx, 1
    jne .Lhot_bad
    mov rdi, rbx
    mov rsi, r12
    call ext_host_close_field
    test rax, rax
    jnz .Lhot_bad
    cmp rdx, 1
    jne .Lhot_bad
    inc r12
    cmp r12, 5
    jb 1b
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lhot_bad
    cmp dword ptr [rbx + EXT_host_cleanup_error], 0
    jne .Lhot_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + ho_live]
    jne .Lhot_bad
    xor eax, eax
    EPILOGUE
.Lhot_bad:
    mov rax, [rip + ho_stage]
    EPILOGUE
