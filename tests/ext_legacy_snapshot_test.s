# Isolated full initial snapshot fixture, caller's actual anchor remains live until explicit close.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extpreparelegacy.inc"
.data
.p2align 3
els_tag: .quad 1,2
    .zero 48
.bss
.p2align 3
els_result: .zero 192
els_info: .zero 16
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 4
    jne .Lelst_bad
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    mov esi, ER_DIR
    call prep_legacy_open_absolute
    test rax, rax
    js .Lelst_bad
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + els_tag + 32]
    call ext_root_identity
    test rax, rax
    js .Lelst_bad
    mov rdi, r12
    mov rsi, [rbx + 8]
    mov rdx, [rbx + 16]
    mov rcx, [rbx + 24]
    lea r8, [rip + els_tag]
    lea r9, [rip + els_info]
    call ext_legacy_snapshot_build
    mov r13, rax
    mov r14, rdx
    mov rdi, r12
    call ext_root_close
    test r14, r14
    jnz 1f
    mov r14, rax
1:  test r13, r13
    jnz .Lelst_error
    test r14, r14
    jnz .Lelst_error
    mov edi, 1
    mov rsi, [rip + els_info]
    mov rdx, [rip + els_info + 8]
    call write_all
    mov r12, rax
    mov rdi, [rip + els_info]
    call mem_free
    mov rax, r12
    EPILOGUE
.Lelst_error:
    mov [rip + els_result + LS_primary], r13
    mov [rip + els_result + LS_secondary], r14
    mov rdi, [rip + els_info]
    call mem_free
    mov edi, 1
    lea rsi, [rip + els_result]
    mov edx, LS_HEADER
    call write_all
    xor eax, eax
    EPILOGUE
.Lelst_bad:
    mov eax, 1
    EPILOGUE
