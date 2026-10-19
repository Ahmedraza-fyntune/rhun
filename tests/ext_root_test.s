# Raw binary fixture: status, neutral stat, identity, 16-byte prefix, read count.
.include "rhun.inc"
.include "app/extvalidate.inc"
.bss
.p2align 3
ert_result: .zero 96
ert_root: .quad 0
ert_outer: .quad 0
ert_inner: .quad 0
ert_again: .quad 0
ert_did: .quad 0
.text
ert_count:
    inc qword ptr [rdi]
    xor eax, eax
    ret
ert_outer_callback:
    inc qword ptr [rip + ert_outer]
    cmp qword ptr [rip + ert_did], 0
    jne 9f
    mov qword ptr [rip + ert_did], 1
    PROLOGUE
    mov rdi, [rip + ert_root]
    call ext_root_reopen_dir
    test rax, rax
    js 8f
    mov rbx, rax
    mov rdi, rax
    mov esi, 1048576
    lea rdx, [rip + ert_count]
    lea rcx, [rip + ert_inner]
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    mov r12, rax
    mov rdi, rbx
    call ext_root_close
    test r12, r12
    jnz 7f
    EPILOGUE
7:  mov rax, r12
8:  EPILOGUE
9:  xor eax, eax
    ret
FN main
    PROLOGUE
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 3
    jb .Lert_usage
    mov rdi, [rbx + 8]
    call ext_root_open
    test rax, rax
    js .Lert_error
    mov r12, rax
    mov [rip + ert_root], rax
    mov rdi, [rbx + 16]
    lea rsi, [rip + ert_scan]
    call strcmp_eq
    test eax, eax
    jnz .Lert_scan
    mov rdi, [rbx + 16]
    lea rsi, [rip + ert_self]
    call strcmp_eq
    test eax, eax
    jnz .Lert_self
    mov r13d, ER_ANY
    xor r14d, r14d
    cmp qword ptr [rip + g_argc], 4
    jb 1f
    mov rdi, [rbx + 24]
    call strlen
    mov rdi, [rbx + 24]
    mov rsi, rax
    call parse_u64
    mov r13, rax
1:  cmp qword ptr [rip + g_argc], 5
    jb 2f
    mov rdi, [rbx + 32]
    call strlen
    mov rdi, [rbx + 32]
    mov rsi, rax
    call parse_u64
    mov r14, rax
2:  mov rdi, r12
    mov rsi, [rbx + 16]
    mov rdx, r13
    mov rcx, r14
    mov r8d, 0x180             # 0600
    cmp r13, ER_DIR
    jne 3f
    mov r8d, 0x1c0             # 0700
3:  call ext_root_open_at
    jmp .Lert_child
.Lert_self:
    mov rdi, r12
    call ext_root_reopen_dir
.Lert_child:
    test rax, rax
    js .Lert_root_error
    mov r13, rax
    mov rdi, rax
    lea rsi, [rip + ert_result + 8]
    call ext_root_stat
    test rax, rax
    js .Lert_child_error
    mov rdi, r13
    lea rsi, [rip + ert_result + 40]
    call ext_root_identity
    test rax, rax
    js .Lert_child_error
    cmp qword ptr [rip + ert_result + 8 + ER_kind], ER_FILE
    jne 4f
    mov rdi, r13
    lea rsi, [rip + ert_result + 72]
    mov edx, 16
    xor ecx, ecx
    call ext_root_read
    test rax, rax
    js .Lert_child_error
    mov [rip + ert_result + 88], rax
4:  mov rdi, r13
    call ext_root_close
    test rax, rax
    jns .Lert_final_close
    mov rdx, rax
    jmp .Lert_root_error
.Lert_final_close:
    mov rdi, r12
    call ext_root_close
    mov rdx, rax
    jmp .Lert_error
.Lert_child_error:
    mov r14, rax
    mov rdi, r13
    call ext_root_close
    mov rdx, rax
    mov rax, r14
.Lert_root_error:
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    call ext_root_close
    test r15, r15
    jnz .Lert_have_cleanup
    test rax, rax
    jns .Lert_have_cleanup
    mov r15, rax
.Lert_have_cleanup:
    mov rdx, r15
    mov rax, r14
.Lert_error:
    test rax, rax
    js .Lert_secondary
    xor edx, edx
.Lert_secondary:
    mov [rip + ert_result + 32], rdx
    mov [rip + ert_result], rax
    mov edi, 1
    lea rsi, [rip + ert_result]
    mov edx, 96
    call write_all
    xor eax, eax
    EPILOGUE
.Lert_usage:
    mov rax, -22
    jmp .Lert_error
.Lert_scan:
    mov rdi, r12
    mov esi, 1048576
    lea rdx, [rip + ert_outer_callback]
    xor ecx, ecx
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    mov [rip + ert_result], rax
    mov rdi, r12
    call ext_root_reopen_dir
    test rax, rax
    js .Lert_root_error
    mov r13, rax
    mov rdi, rax
    mov esi, 1048576
    lea rdx, [rip + ert_count]
    lea rcx, [rip + ert_again]
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    test rax, rax
    js .Lert_child_error
    mov rdi, r13
    call ext_root_close
    mov rdi, r12
    call ext_root_close
    mov rax, [rip + ert_outer]
    mov [rip + ert_result + 8], rax
    mov rax, [rip + ert_inner]
    mov [rip + ert_result + 16], rax
    mov rax, [rip + ert_again]
    mov [rip + ert_result + 24], rax
    mov rax, [rip + ert_result]
    jmp .Lert_error
.section .rodata
ert_scan: .asciz "--scan"
ert_self: .asciz "--self"
