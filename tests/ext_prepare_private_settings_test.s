# Private parsed metadata rejects live mutation; independent value clones stay mutable.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov rdi, -1
    lea rsi, [rip + ps_dir]
    lea rdx, [rip + ps_owner]
    lea rcx, [rip + ps_name]
    call ext_prepare_alloc
    test rax, rax
    jz .Lps_bad
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + ps_source]
    mov edx, ps_end - ps_source
    call ext_manifest_parse_owned
    test rax, rax
    jnz .Lps_bad
    mov rdi, rbx
    call ext_prepare_defaults
    test rax, rax
    jnz .Lps_bad
    cmp qword ptr [rbx + EP_ext + EXT_sdefs + VEC_len], 1
    jne .Lps_bad
    mov r12, [rbx + EP_ext + EXT_sdefs + VEC_ptr]
    test dword ptr [r12 + SD_pad], 1
    jz .Lps_bad
    mov r13, [r12 + SD_value]
    call ext_prepare_retire_charge
    mov [rsp + 8], rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 16], rax
    lea rdi, [rip + ps_changed]
    call dup_cstr
    mov rdi, r12
    mov rsi, rax
    call sdef_take_value
    cmp [r12 + SD_value], r13
    jne .Lps_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 16]
    jne .Lps_bad
    mov eax, [rip + g_dirty]
    mov [rsp + 24], eax
    lea rdi, [rbx + EP_ext]
    mov rsi, r12
    lea rdx, [rip + ps_changed]
    call ext_setting_set
    mov eax, [rip + g_dirty]
    cmp eax, [rsp + 24]
    jne .Lps_bad
    cmp [r12 + SD_value], r13
    jne .Lps_bad
    mov edi, SD_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lps_bad
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    mov edx, SD_SIZE
    call memcpy
    and dword ptr [r14 + SD_pad], -2
    mov rdi, r13
    call dup_cstr
    mov [r14 + SD_value], rax
    lea rdi, [rip + ps_changed]
    call dup_cstr
    mov rdi, r14
    mov rsi, rax
    call sdef_take_value
    mov rdi, [r14 + SD_value]
    lea rsi, [rip + ps_changed]
    call strcmp_eq
    test eax, eax
    jz .Lps_bad
    cmp [r12 + SD_value], r13
    jne .Lps_bad
    mov rdi, r13
    lea rsi, [rip + ps_original]
    call strcmp_eq
    test eax, eax
    jz .Lps_bad
    call ext_prepare_retire_charge
    cmp rax, [rsp + 8]
    jne .Lps_bad
    mov rdi, [r14 + SD_value]
    call mem_free
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    call ext_prepare_release
    test rax, rax
    jnz .Lps_bad
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Lps_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lps_bad
    xor eax, eax
    EPILOGUE
.Lps_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
ps_dir: .asciz "/private/payload"
ps_owner: .asciz "fixture"
ps_name: .asciz "example"
ps_changed: .asciz "new"
ps_original: .asciz "original"
ps_source: .ascii "[settings]\nlabel.type=string\nlabel.default=original\n"
ps_end:
