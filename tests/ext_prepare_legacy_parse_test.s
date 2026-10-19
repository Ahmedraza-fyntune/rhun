# Pure legacy callbacks/defaults, exact ownership and no published commands.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
elpm_output: .zero 2048
.text
FN main
    PROLOGUE 48
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    cmp qword ptr [rip + g_argc], 2
    jne .Lelpm_bad
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, 65537
    call file_read_limited_try
    test rax, rax
    jz .Lelpm_bad
    mov r12, rax
    mov r13, rdx
    mov rdi, -1
    lea rsi, [rip + elpm_dir]
    lea rdx, [rip + elpm_owner]
    lea rcx, [rip + elpm_name]
    call ext_prepare_alloc_legacy
    test rax, rax
    jz .Lelpm_bad
    mov rbx, rax
 .ifdef WINDOWS
    mov rdi, rbx
    lea rsi, [rip + elpm_cwd]
    mov edx, 'C'
    call prep_legacy_set_context
    test rax, rax
    js .Lelpm_bad
.endif
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call prep_legacy_manifest
    mov [rip + elpm_output], rax
    mov rax, [rbx + EP_ext + EXT_sdefs + VEC_len]
    mov [rip + elpm_output + 8], rax
    xor r14d, r14d
1:  cmp r14, [rbx + EP_ext + EXT_sdefs + VEC_len]
    jae 3f
    cmp r14, 12
    jae 3f
    imul r15, r14, SD_SIZE
    add r15, [rbx + EP_ext + EXT_sdefs + VEC_ptr]
    mov rdi, [r15 + SD_value]
    test rdi, rdi
    jz 3f
    call strlen
    cmp rax, 63
    ja .Lelpm_bad
    imul rdi, r14, 64
    lea rdx, [rip + elpm_output + 16]
    add rdi, rdx
    mov rsi, [r15 + SD_value]
    mov rdx, rax
    call memcpy
    inc r14
    jmp 1b
3:  mov rax, [rbx + EP_commands + VEC_len]
    mov [rip + elpm_output + 2000], rax
    mov rax, [rip + g_ext_cmds + VEC_len]
    mov [rip + elpm_output + 2008], rax
    mov rdi, rbx
    call ext_prepare_release
    mov [rip + elpm_output + 2040], rax
    mov rdi, r12
    call mem_free
    mov rax, [rip + g_mem_live]
    sub rax, [rsp]
    mov [rip + elpm_output + 2032], rax
    mov edi, 1
    lea rsi, [rip + elpm_output]
    mov edx, 2048
    call write_all
    xor eax, eax
    EPILOGUE
.Lelpm_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
elpm_cwd: .asciz "C:/legacy"
elpm_dir: .asciz "/legacy/payload"
elpm_owner: .asciz "fixture"
elpm_name: .asciz "example"
