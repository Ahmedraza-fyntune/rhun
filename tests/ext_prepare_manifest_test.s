# Actual private callbacks, defaults, commands, provider merging and cleanup.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatemanifest.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
epm_result: .zero 64
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 3
    jne .Lepmt_bad
    mov rdi, [rbx + 8]
    mov esi, 65537
    call file_read_limited_try
    test rax, rax
    jz .Lepmt_bad
    mov r12, rax
    mov r13, rdx
    mov rdi, [rbx + 16]
    call ext_root_open
    test rax, rax
    js .Lepmt_bad
    mov r14, rax
    mov rdi, rax
    lea rsi, [rip + epmt_dir]
    lea rdx, [rip + epmt_owner]
    lea rcx, [rip + epmt_name]
    call ext_prepare_alloc
    mov r15, rax
    mov rdi, r14
    call ext_root_close
    test r15, r15
    jz .Lepmt_bad
    mov rdi, r15
    mov esi, MV_SIZE
    call prep_owned_alloc
    test rax, rax
    jz .Lepmt_bad
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + epmt_owner]
    lea rcx, [rip + epmt_name]
    mov r8, rax
    call ext_manifest_check_bytes
    test rax, rax
    jnz 2f
    mov rdi, r15
    mov rsi, r12
    mov rdx, r13
    call ext_manifest_parse_owned
    test rax, rax
    jnz 2f
    mov rdi, r15
    call ext_manifest_finish_owned
2:  mov [rip + epm_result], rax
    mov rax, [r15 + EP_commands + VEC_len]
    mov [rip + epm_result + 8], rax
    mov rax, [r15 + EP_ext + EXT_sdefs + VEC_len]
    mov [rip + epm_result + 16], rax
    test rax, rax
    jz 3f
    mov rax, [r15 + EP_ext + EXT_sdefs + VEC_ptr]
    mov rdi, [rax + SD_value]
    test rdi, rdi
    jz 3f
    call strlen
    mov edx, 8
    cmp rax, rdx
    cmovb rdx, rax
    mov rsi, [r15 + EP_ext + EXT_sdefs + VEC_ptr]
    mov rsi, [rsi + SD_value]
    lea rdi, [rip + epm_result + 24]
    call memcpy
3:  mov rax, [r15 + EP_ext + EXT_on]
    mov [rip + epm_result + 32], eax
    mov rdi, r15
    call ext_prepare_release
    mov [rip + epm_result + 40], rax
    mov rdi, r12
    call mem_free
    mov rax, [rip + g_mem_live]
    sub rax, [rsp]
    mov [rip + epm_result + 48], rax
    mov rax, [rip + g_ext_cmds + VEC_len]
    mov [rip + epm_result + 56], rax
    mov edi, 1
    lea rsi, [rip + epm_result]
    mov edx, 64
    SYS SYS_write
    xor eax, eax
    EPILOGUE
.Lepmt_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
epmt_dot: .asciz "/tmp"
epmt_dir: .asciz "/managed/payload"
epmt_owner: .asciz "fixture"
epmt_name: .asciz "example"
