# Import owns immutable transcript bytes. Pure steps must never reopen the payload.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extpreparelegacy.inc"
.bss
.p2align 3
eli_result: .zero 160
eli_armed: .quad 0
eli_fail_at: .quad 0
eli_alloc_count: .quad 0
eli_io_calls: .quad 0
.text
FN main
    PROLOGUE 80
    mov rax, [rip + g_mem_live]
    mov [rsp + 64], rax
    cmp qword ptr [rip + g_argc], 6
    je .Lelit_args
    cmp qword ptr [rip + g_argc], 7
    jne .Lelit_bad
.Lelit_args:
    mov r15, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 7
    jne .Lelit_input
    mov rdi, [r15 + 48]
    call strlen
    mov rsi, rax
    mov rdi, [r15 + 48]
    call parse_u64
    mov [rip + eli_fail_at], rax
.Lelit_input:
    mov rdi, [r15 + 8]
    mov esi, LS_CAP + 73
    call file_read_limited_try
    test rax, rax
    jz .Lelit_bad
    mov r12, rax
    mov r13, rdx
    cmp r13, 72
    jb .Lelit_bad
    mov rax, [r15 + 16]
    mov [rsp + LI_dir], rax
    mov rax, [r15 + 24]
    mov [rsp + LI_owner], rax
    mov rax, [r15 + 32]
    mov [rsp + LI_name], rax
    lea rax, [r12 + 8]
    mov [rsp + LI_tag], rax
    mov qword ptr [rsp + LI_lease], -1
    mov rax, [r12]
    mov [rsp + LI_drive], rax
    mov rax, [r15 + 40]
    mov [rsp + LI_cwd], rax
    lea rdi, [r12 + 72]
    lea rsi, [r13 - 72]
    mov rdx, rsp
    mov qword ptr [rip + eli_armed], 1
    call ext_prepare_import_legacy
    test rax, rax
    jz .Lelit_begin_error
    mov rbx, rax
    mov rdi, r12
    call mem_free
    xor r12d, r12d
1:  mov rdi, rbx
    call ext_prepare_step
    cmp rax, 1
    je 1b
    mov [rip + eli_result], rax
    mov [rip + eli_result + 8], rdx
    test rax, rax
    jnz .Lelit_release
    mov rdi, rbx
    call ext_prepare_commands
    mov [rip + eli_result + 16], rdx
    mov rdi, rbx
    call ext_prepare_grammars
    mov [rip + eli_result + 24], rdx
    mov rdi, rbx
    call ext_prepare_themes
    mov [rip + eli_result + 32], rdx
    mov rdi, rbx
    call ext_prepare_sources
    mov [rip + eli_result + 40], rdx
    mov rdi, rbx
    call ext_prepare_kind
    mov [rip + eli_result + 48], rax
    mov rax, [rbx + PO_eo]
    mov rax, [rax + EO_used]
    mov [rip + eli_result + 56], rax
    mov rdi, rbx
    lea rsi, [rip + eli_result + 64]
    call ext_prepare_source_commitment
    test rax, rax
    jnz .Lelit_bad
    mov rax, [rbx + EP_root]
    mov [rip + eli_result + 96], rax
    mov rax, [rbx + EP_syntax]
    mov [rip + eli_result + 104], rax
    mov rax, [rbx + EP_themes]
    mov [rip + eli_result + 112], rax
.Lelit_release:
    mov rdi, rbx
    call ext_prepare_release
    mov [rip + eli_result + 128], rax
    jmp .Lelit_finish
.Lelit_begin_error:
    mov [rip + eli_result], rdx
    mov [rip + eli_result + 8], rcx
.Lelit_finish:
    mov qword ptr [rip + eli_armed], 0
    mov eax, [rip + eli_alloc_count]
    mov [rip + eli_result + 120], eax
    mov eax, [rip + eli_io_calls]
    mov [rip + eli_result + 124], eax
    mov rdi, r12
    call mem_free
    mov rax, [rip + g_mem_live]
    sub rax, [rsp + 64]
    mov [rip + eli_result + 136], rax
    mov rax, [rip + g_ext_cmds + VEC_len]
    mov [rip + eli_result + 144], rax
    mov rax, [rip + g_grammars + VEC_len]
    mov [rip + eli_result + 152], rax
    mov edi, 1
    lea rsi, [rip + eli_result]
    mov edx, 160
    call write_all
    xor eax, eax
    EPILOGUE
.Lelit_bad:
    mov eax, 1
    EPILOGUE
