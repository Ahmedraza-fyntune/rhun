# Private legacy theme header/palette parity without a registry or file reread.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
elt_result: .zero 1024
elt_plan: .zero AP_SIZE
.text
FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    cmp qword ptr [rip + g_argc], 2
    jne .Lelt_bad
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, 65537
    call file_read_limited_try
    test rax, rax
    jz .Lelt_bad
    mov r12, rax
    mov r13, rdx
    mov rdi, -1
    lea rsi, [rip + elt_dir]
    lea rdx, [rip + elt_owner]
    lea rcx, [rip + elt_name]
    call ext_prepare_alloc_legacy
    test rax, rax
    jz .Lelt_bad
    mov rbx, rax
    lea rax, [rip + elt_stem]
    mov [rip + elt_plan + AP_name], rax
    lea rax, [rip + elt_path]
    mov [rip + elt_plan + AP_path], rax
    mov qword ptr [rip + elt_plan + AP_len], 19
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rip + elt_plan]
    call prep_theme_product
    mov [rip + elt_result], rax
    test rax, rax
    jnz 2f
    mov r14, [rbx + EP_themeviews + VEC_ptr]
    mov eax, [r14 + TH_dark]
    mov [rip + elt_result + 8], rax
    mov rdi, [r14 + TH_name]
    call strlen
    mov [rip + elt_result + 16], rax
    cmp rax, 800
    ja .Lelt_bad
    lea rdi, [rip + elt_result + 32]
    mov rsi, [r14 + TH_name]
    mov rdx, rax
    call memcpy
2:  mov rdi, rbx
    call ext_prepare_release
    mov [rip + elt_result + 1008], rax
    mov rdi, r12
    call mem_free
    mov rax, [rip + g_mem_live]
    sub rax, [rsp]
    mov [rip + elt_result + 1016], rax
    mov edi, 1
    lea rsi, [rip + elt_result]
    mov edx, 1024
    call write_all
    xor eax, eax
    EPILOGUE
.Lelt_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
elt_dir: .asciz "/legacy/payload"
elt_owner: .asciz "fixture"
elt_name: .asciz "example"
elt_stem: .asciz "sample"
elt_path: .asciz "themes/sample.theme"
