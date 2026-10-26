# Window placement parser, atomic save and repeated bounded reads without a display.
.include "rhun.inc"
.bss
record: .zero WPOS_SIZE
.text
FN main
    PROLOGUE
    lea rdi, [rip + record]
    mov esi, 0xa5
    mov edx, WPOS_SIZE
    call memset
    cmp qword ptr [rip + g_argc], 2
    jb 2f
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + save]
    call strcmp_eq
    test eax, eax
    jz 1f
    lea rdi, [rip + record]
    lea rsi, [rip + fixture]
    mov edx, WPOS_SIZE
    call memcpy
    jmp 11f
1:  mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + save_invalid]
    call strcmp_eq
    test eax, eax
    jz 2f
11: lea rdi, [rip + backend]
    lea rsi, [rip + record]
    call window_state_save
2:  lea rdi, [rip + backend]
    lea rsi, [rip + record]
    call window_state_load
    mov r14d, eax
    mov r15, [rip + g_mem_live]
    mov r13d, 64
3:  lea rdi, [rip + backend]
    lea rsi, [rip + record]
    call window_state_load
    cmp eax, r14d
    jne 9f
    cmp [rip + g_mem_live], r15
    jne 9f
    dec r13d
    jnz 3b
    test r14d, r14d
    jz 4f
    lea rdi, [rip + valid]
    call log_cstr
    lea rdi, [rip + record]
    mov esi, WPOS_SIZE
    call log_write
    jmp 8f
4:  lea rdi, [rip + record]
    mov ecx, WPOS_SIZE
5:  cmp byte ptr [rdi], 0xa5
    jne 9f
    inc rdi
    dec ecx
    jnz 5b
    lea rdi, [rip + invalid]
    call log_cstr
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
.section .rodata
backend: .asciz "fixture"
save: .asciz "save"
save_invalid: .asciz "save-invalid"
valid: .asciz "valid\n"
invalid: .asciz "invalid\n"
fixture: .long WPOS_MAGIC, -200, 120, 900, 640, 3
