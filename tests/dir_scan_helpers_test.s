.include "rhun.inc"
.section .rodata
.p2align 3
dsu_paths:
    .quad dsu_empty,0
    .quad dsu_root,0
    .quad dsu_relative,0
    .quad dsu_ancestor,0
    .quad dsu_trailing,-22
    .quad dsu_twice,-22
    .quad dsu_double_root,-22
.ifdef WINDOWS
    .quad dsu_drive,0
    .quad dsu_backdrive,0
    .quad dsu_namespace,0
    .quad dsu_device,0
    .quad dsu_unc,0
    .quad dsu_unc_extended,0
    .quad dsu_unc_mixed_case,0
    .quad dsu_backunc,0
    .quad dsu_bad_namespace,-22
    .quad dsu_missing_share,-22
    .quad dsu_empty_component,-22
    .quad dsu_dot_share,-22
    .quad dsu_bad_drive,-22
    .quad dsu_bad_namespace_unc,-22
.endif
    .quad 0,0
dsu_empty: .asciz ""
dsu_root: .asciz "/"
dsu_relative: .asciz "relative"
dsu_ancestor: .asciz "link/."
dsu_trailing: .asciz "link/"
dsu_twice: .asciz "link//"
dsu_double_root: .asciz "//"
dsu_drive: .asciz "C:/"
dsu_backdrive: .byte 'C',':',92,0
dsu_namespace: .asciz "//?/C:/"
dsu_device: .asciz "//./C:/"
dsu_unc: .asciz "//server/share/"
dsu_unc_extended: .asciz "//?/UNC/server/share/"
dsu_unc_mixed_case: .asciz "//?/uNc/server/share/"
dsu_backunc: .byte 92,92,'s',92,'n',92,0
dsu_bad_namespace: .asciz "//?/foo/"
dsu_missing_share: .asciz "//server/"
dsu_empty_component: .asciz "//server//share/"
dsu_dot_share: .asciz "//server/../"
dsu_bad_drive: .asciz "1:/"
dsu_bad_namespace_unc: .asciz "//?/UNC/"
dsu_a: .asciz "a"
dsu_dot: .asciz "."
dsu_dotdot: .asciz ".."
dsu_hidden: .asciz ".pending"
dsu_slash: .asciz "a/b"
dsu_nul: .byte 'a',0,'b',0
dsu_ok: .asciz "ok strict directory helpers\n"
.bss
.p2align 3
dsu_guard: .zero 8
dsu_ctx: .zero DSC_SIZE
dsu_guard_end: .zero 8
dsu_mode: .quad 0
dsu_calls: .quad 0
dsu_long: .zero 4097
.text
dsu_fail:
    mov edi, 1
    call sys_exit
dsu_zero:
    test rax, rax
    jnz dsu_fail
    ret
dsu_callback:
    cmp rdi, 12345678
    jne dsu_fail
    inc qword ptr [rip + dsu_calls]
    mov rax, [rip + dsu_mode]
    ret
dsu_emit_a:
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_a]
    mov edx, 1
    jmp dir_scan_emit
FN main
    PROLOGUE
    lea rbx, [rip + dsu_paths]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 2f
    call dir_scan_path_check
    cmp rax, [rbx + 8]
    jne dsu_fail
    add rbx, 16
    jmp 1b
2:  xor edi, edi
    call dir_scan_path_check
    cmp rax, -22
    jne dsu_fail
    lea rdi, [rip + dsu_long]
    mov esi, 'a'
    mov edx, 4096
    call memset
    lea rdi, [rip + dsu_long]
    call dir_scan_path_check
    cmp rax, -36
    jne dsu_fail
    mov byte ptr [rip + dsu_long + 4095], 0
    lea rdi, [rip + dsu_long]
    call dir_scan_path_check
    call dsu_zero
    lea rdi, [rip + dsu_guard]
    mov esi, 0xa5
    mov edx, DSC_SIZE + 16
    call memset
    lea rdi, [rip + dsu_ctx]
    xor esi, esi
    mov edx, DSC_SIZE
    call memset
    mov qword ptr [rip + dsu_ctx + DSC_max], 2
    lea rax, [rip + dsu_callback]
    mov [rip + dsu_ctx + DSC_callback], rax
    mov qword ptr [rip + dsu_ctx + DSC_user], 12345678
    call dsu_emit_a
    call dsu_zero
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_dot]
    mov edx, 1
    call dir_scan_emit
    call dsu_zero
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_dotdot]
    mov edx, 2
    call dir_scan_emit
    call dsu_zero
    cmp qword ptr [rip + dsu_ctx + DSC_count], 1
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_hidden]
    mov edx, 8
    call dir_scan_emit
    call dsu_zero
    call dsu_emit_a
    cmp rax, -27
    jne dsu_fail
    cmp qword ptr [rip + dsu_calls], 2
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_nul]
    mov edx, 3
    call dir_scan_emit
    cmp rax, -5
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    lea rsi, [rip + dsu_slash]
    mov edx, 3
    call dir_scan_emit
    cmp rax, -5
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    xor esi, esi
    mov edx, 1
    call dir_scan_emit
    cmp rax, -5
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    mov esi, 1
    mov edx, 4096
    call dir_scan_emit
    cmp rax, -36
    jne dsu_fail
    lea rdi, [rip + dsu_ctx]
    mov esi, 1
    xor edx, edx
    call dir_scan_emit
    cmp rax, -5
    jne dsu_fail
    mov qword ptr [rip + dsu_ctx + DSC_max], 4
    mov qword ptr [rip + dsu_mode], 1
    call dsu_emit_a
    cmp rax, -22
    jne dsu_fail
    mov qword ptr [rip + dsu_mode], -125
    call dsu_emit_a
    cmp rax, -125
    jne dsu_fail
    cmp qword ptr [rip + dsu_calls], 4
    jne dsu_fail
    cmp qword ptr [rip + dsu_ctx + DSC_count], 4
    jne dsu_fail
    mov rax, 0xa5a5a5a5a5a5a5a5
    cmp [rip + dsu_guard], rax
    jne dsu_fail
    cmp [rip + dsu_guard_end], rax
    jne dsu_fail
    lea rdi, [rip + dsu_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
