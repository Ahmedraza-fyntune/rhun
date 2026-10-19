# Prepare a candidate, expose immutable views, then revalidate against the held anchor.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
ept_header: .zero 128
ept_result: .zero 96
ept_palette: .zero 4 * T_COUNT
ept_defined: .zero 16
ept_kind: .quad 0
.text
FN main
    PROLOGUE 48
    cmp qword ptr [rip + g_argc], 4
    jne .Lept_bad
    mov rbx, [rip + g_argv]
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov rdi, [rbx + 8]
    mov r12, -1
    call ext_root_open
    test rax, rax
    js .Lept_initial_fail
    mov r12, rax
    mov rdi, rax
    mov rsi, [rbx + 8]
    mov rdx, [rbx + 16]
    mov rcx, [rbx + 24]
    mov r8, -1
    call ext_prepare_begin
    test rax, rax
    jz .Lept_begin_fail
    mov r13, rax
1:  mov rdi, r13
    call ext_prepare_step
    cmp rax, 1
    je 1b
    test rax, rax
    jnz .Lept_step_fail
    mov rdi, r13
    call ext_prepare_ext
    test rax, rax
    jz .Lept_bad
    cmp dword ptr [rax + EXT_hello], 0
    jne .Lept_bad
    cmp dword ptr [rax + EXT_manifest_ok], 1
    jne .Lept_bad
    mov rdi, r13
    call ext_prepare_commands
    mov [rip + ept_header + 16], rdx
    mov rdi, r13
    call ext_prepare_grammars
    mov [rip + ept_header + 24], rdx
    mov rdi, r13
    call ext_prepare_themes
    mov [rip + ept_header + 32], rdx
    mov rdi, r13
    call ept_themes_check
    test eax, eax
    jnz .Lept_bad
    mov rdi, r13
    call ext_prepare_sources
    mov [rip + ept_header + 40], rdx
    mov rax, [r13 + PO_eo]
    mov rax, [rax + EO_used]
    mov [rip + ept_header + 56], rax
    mov rdi, r13
    lea rsi, [rip + ept_header + 64]
    call ext_prepare_source_commitment
    mov [rip + ept_header], rax
    mov edi, 1
    lea rsi, [rip + ept_header]
    mov edx, 128
    call write_all
    test rax, rax
    jnz .Lept_bad
    xor edi, edi
    lea rsi, [rsp + 8]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lept_bad
    mov rdi, r13
    call ept_themes_check
    test eax, eax
    jnz .Lept_bad
    mov rdi, r12
    mov rsi, [rbx + 8]
    mov rdx, [rbx + 16]
    mov rcx, [rbx + 24]
    lea r8, [rip + ept_header + 64]
    lea r9, [rip + ept_result + 16]
    call ext_validate_from_root_result
    mov [rip + ept_result], rax
    mov [rip + ept_result + 8], rdx
    mov rdi, r13
    call ext_prepare_release
    mov [rip + ept_result + 80], rax
    jmp .Lept_finish
.Lept_step_fail:
    mov [rip + ept_header], rax
    mov [rip + ept_header + 8], rdx
    mov rdi, r13
    call ext_prepare_release
    mov [rip + ept_result + 80], rax
    jmp .Lept_failed_header
.Lept_initial_fail:
    mov [rip + ept_header], rax
    mov [rip + ept_header + 8], rdx
    jmp .Lept_failed_header
.Lept_begin_fail:
    mov [rip + ept_header], rdx
    mov [rip + ept_header + 8], rcx
.Lept_failed_header:
    mov edi, 1
    lea rsi, [rip + ept_header]
    mov edx, 128
    call write_all
.Lept_finish:
    test r12, r12
    js 2f
    mov rdi, r12
    call ext_root_close
    cmp qword ptr [rip + ept_result + 80], 0
    jne 2f
    mov [rip + ept_result + 80], rax
2:  cmp qword ptr [rip + ept_result + 80], 0
    je 3f
    lea rdi, [rip + ept_result + 16]
    xor esi, esi
    mov edx, 64
    call memset
3:  mov rax, [rip + g_mem_live]
    sub rax, [rsp]
    mov [rip + ept_result + 88], rax
    mov edi, 1
    lea rsi, [rip + ept_result]
    mov edx, 96
    call write_all
    xor eax, eax
    EPILOGUE
.Lept_bad:
    mov eax, 1
    EPILOGUE

# Compatible TH prefix contains a stable ID and immutable accepted source through EP lifetime.
ept_themes_check:
    PROLOGUE
    mov rbx, rdi
    call ext_prepare_themes
    mov r12, rax
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, r13
    jae 8f
    imul r15, r14, PT_SIZE
    add r15, r12
    cmp qword ptr [r15 + TH_id], 0
    je 9f
    cmp qword ptr [r15 + TH_name], 0
    je 9f
    cmp qword ptr [r15 + TH_src], 0
    je 9f
    cmp [r15 + TH_owner], rbx
    jne 9f
    lea rdi, [rip + ept_palette]
    lea rsi, [rip + ept_defined]
    lea rdx, [rip + ept_kind]
    mov rcx, [r15 + TH_src]
    mov r8, [r15 + TH_len]
    mov r9d, 1
    call theme_parse_into
    test rax, rax
    jnz 9f
    lea rdi, [rip + ept_palette]
    lea rsi, [r15 + PT_palette]
    mov edx, 4 * T_COUNT
    call memeq
    test eax, eax
    jz 9f
    mov eax, [rip + ept_kind]
    cmp eax, [r15 + TH_dark]
    jne 9f
    inc r14
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
