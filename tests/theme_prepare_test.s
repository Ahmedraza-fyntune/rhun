# All built-in palette parity and private parsing with poisoned active state.
.include "rhun.inc"
.include "app/extvalidate.inc"
.bss
.p2align 3
tpt_palette: .zero 4 * T_COUNT
tpt_defined: .zero 16
tpt_kind: .quad 0
tpt_result: .zero 24
tpt_saved: .zero 4 * T_COUNT
.text
tpt_all:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + themes_count]
    jae .Ltpta_ok
    imul r12, rbx, 24
    lea rax, [rip + themes_table]
    add r12, rax
    mov rdi, [r12 + 8]
    mov rsi, [r12 + 16]
    sub rsi, rdi
    call theme_load
    mov r13d, [rip + g_theme_dark]
    lea rdi, [rip + tpt_saved]
    lea rsi, [rip + g_theme]
    mov edx, 4 * T_COUNT
    call memcpy
    lea rdi, [rip + tpt_palette]
    lea rsi, [rip + tpt_defined]
    lea rdx, [rip + tpt_kind]
    mov rcx, [r12 + 8]
    mov r8, [r12 + 16]
    sub r8, rcx
    mov r9d, 1
    call theme_parse_into
    test rax, rax
    jnz .Ltpta_bad
    cmp r13d, [rip + tpt_kind]
    jne .Ltpta_bad
    cmp r13d, [rip + g_theme_dark]
    jne .Ltpta_bad
    lea rdi, [rip + tpt_saved]
    lea rsi, [rip + g_theme]
    mov edx, 4 * T_COUNT
    call memeq
    test eax, eax
    jz .Ltpta_bad
    lea rdi, [rip + tpt_palette]
    lea rsi, [rip + g_theme]
    mov edx, 4 * T_COUNT
    call memeq
    test eax, eax
    jz .Ltpta_bad
    cmp qword ptr [rip + g_themes + VEC_len], 0
    jne .Ltpta_bad
    inc rbx
    jmp 1b
.Ltpta_ok:
    xor eax, eax
    EPILOGUE
.Ltpta_bad:
    mov eax, 1
    EPILOGUE
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne .Ltpt_bad
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    lea rsi, [rip + tpt_all_arg]
    call strcmp_eq
    test eax, eax
    jz 1f
    call tpt_all
    EPILOGUE
1:  mov rdi, [rbx + 8]
    mov esi, 65537
    call file_read_limited_try
    test rax, rax
    jz .Ltpt_bad
    mov r12, rax
    mov r13, rdx
    lea rdi, [rip + g_theme]
    mov esi, 0xa5
    mov edx, 4 * T_COUNT
    call memset
    mov dword ptr [rip + g_theme_dark], 42
    lea rdi, [rip + tpt_saved]
    lea rsi, [rip + g_theme]
    mov edx, 4 * T_COUNT
    call memcpy
    lea rdi, [rip + tpt_palette]
    lea rsi, [rip + tpt_defined]
    lea rdx, [rip + tpt_kind]
    mov rcx, r12
    mov r8, r13
    mov r9d, 1
    call theme_parse_into
    mov [rip + tpt_result], rax
    mov rdi, r12
    call mem_free
    lea rdi, [rip + tpt_saved]
    lea rsi, [rip + g_theme]
    mov edx, 4 * T_COUNT
    call memeq
    test eax, eax
    jz .Ltpt_bad
    cmp dword ptr [rip + g_theme_dark], 42
    jne .Ltpt_bad
    cmp qword ptr [rip + g_themes + VEC_len], 0
    jne .Ltpt_bad
    mov qword ptr [rip + tpt_result + 8], 1
    mov eax, [rip + tpt_kind]
    mov [rip + tpt_result + 16], rax
    mov edi, 1
    lea rsi, [rip + tpt_result]
    mov edx, 24
    call write_all
    xor eax, eax
    EPILOGUE
.Ltpt_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
tpt_all_arg: .asciz "--all"
