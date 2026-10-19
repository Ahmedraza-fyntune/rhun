# Pure bounded receipt parser, output remains untouched on any failure.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatewire.inc"
.bss
.p2align 3
ewt_result: .zero 80
.text
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne 8f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, 329
    call file_read_limited_try
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp rdx, 328
    jne 7f
    lea rdi, [rip + ewt_result + 16]
    mov esi, 0x55
    mov edx, 64
    call memset
    lea rdi, [rbx + 8]
    mov rsi, [rbx]
    lea rdx, [rbx + 200]
    lea rcx, [rbx + 296]
    lea r8, [rip + ewt_result + 16]
    call ext_validate_legacy_receipt_check
    mov [rip + ewt_result], rax
    mov [rip + ewt_result + 8], rdx
    mov rdi, rbx
    call mem_free
    mov edi, 1
    lea rsi, [rip + ewt_result]
    mov edx, 80
    call write_all
    xor eax, eax
    EPILOGUE
7:  mov rdi, rbx
    call mem_free
8:  mov eax, 1
    EPILOGUE
