.include "rhun.inc"
.text
FN main
    PROLOGUE
    mov r15, [rip + g_mem_live]
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lfail
    mov rbx, rax
    xor r14d, r14d
    cmp qword ptr [rbx + RX_ready], 0
    jne .Lfail
    cmp qword ptr [rbx + RX_clockat], 8976
    jne .Lfail
    mov qword ptr [rbx + RX_nvalues], 4
    mov qword ptr [rbx + RX_values], -1
    mov qword ptr [rbx + RX_values + 8], -1
    mov qword ptr [rbx + RX_values + 16], -1
    mov qword ptr [rbx + RX_values + 24], -1
    mov rdi, rbx
    mov esi, 3
    call snippet_regex_spend
    test eax, eax
    jz .Lfail
    mov r14d, 1
    mov rdi, rbx
    xor esi, esi
    mov edx, 5
    call snippet_regex_write
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_ntrail], 1
    jne .Lfail
    cmp qword ptr [rbx + RX_values], 5
    jne .Lfail
    mov rdi, rbx
    xor esi, esi
    mov edx, 5
    call snippet_regex_write
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_work], 9996
    jne .Lfail
    mov rdi, rbx
    mov esi, 1
    mov edx, 7
    call snippet_regex_write
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_ntrail], 2
    jne .Lfail
    mov r14d, 2
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_rewind
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_values], 5
    jne .Lfail
    cmp qword ptr [rbx + RX_values + 8], -1
    jne .Lfail
    mov rdi, rbx
    xor esi, esi
    call snippet_regex_rewind
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_values], -1
    jne .Lfail
    cmp qword ptr [rbx + RX_work], 9993
    jne .Lfail
    mov r14d, 3
    mov qword ptr [rbx + RX_pos], 33
    mov rdi, rbx
    mov esi, 2
    call snippet_regex_branch
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_nbranches], 1
    jne .Lfail
    cmp qword ptr [rbx + RX_branches], 2
    jne .Lfail
    cmp qword ptr [rbx + RX_branches + 8], 33
    jne .Lfail
    cmp qword ptr [rbx + RX_branches + 16], 0
    jne .Lfail
    mov r14d, 4
    mov rdi, rbx
    mov esi, 4
    mov edx, 10
    call snippet_regex_write
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rbx + RX_error], RX_STATE_ERROR
    jne .Lfail
    mov rdi, rbx
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lfail
    mov r14d, 5
    xor edi, edi
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lfail
    mov rbx, rax
    cmp qword ptr [rbx + RX_clockat], 0
    jne .Lfail
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rbx + RX_work], 0
    jne .Lfail
    cmp qword ptr [rbx + RX_error], RX_WORK_ERROR
    jne .Lfail
    mov rdi, rbx
    mov esi, RX_TIME_ERROR
    call snippet_regex_fail
    cmp qword ptr [rbx + RX_error], RX_WORK_ERROR
    jne .Lfail
    mov rdi, rbx
    call snippet_regex_free
    mov r14d, 6
    mov edi, RX_WORK_MAX + 1
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jnz .Lfail
    mov rdi, -1
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jnz .Lfail
    call time_us
    mov rsi, rax
    mov edi, 10000
    call snippet_regex_new
    test rax, rax
    jz .Lfail
    mov rbx, rax
    mov qword ptr [rbx + RX_hasmatch], 1
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rbx + RX_hasmatch], 0
    jne .Lfail
    cmp qword ptr [rbx + RX_error], RX_TIME_ERROR
    jne .Lfail
    mov rdi, rbx
    call snippet_regex_free
    xor edi, edi
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lfail
    mov r14d, 7
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lfail
    mov rbx, rax
    mov rdi, rbx
    lea rsi, [rip + program]
    mov edx, 80
    lea rcx, [rip + text]
    mov r8d, 7
    call snippet_regex_open
    test eax, eax
    jz .Lfail
    cmp qword ptr [rbx + RX_ready], 1
    jne .Lfail
    cmp qword ptr [rbx + RX_nvalues], 2
    jne .Lfail
    cmp qword ptr [rbx + RX_values], -1
    jne .Lfail
    cmp qword ptr [rbx + RX_work], 9910
    jne .Lfail
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_boundary
    test eax, eax
    jnz .Lfail
    mov rdi, rbx
    mov esi, 2
    call snippet_regex_boundary
    test eax, eax
    jz .Lfail
    mov r14d, 8
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call snippet_regex_scalar
    cmp eax, 0xe9
    jne .Lfail
    cmp rdx, 2
    jne .Lfail
    cmp ecx, 1
    jne .Lfail
    mov rdi, rbx
    mov esi, 7
    mov edx, 1
    call snippet_regex_scalar
    cmp eax, 0x212a
    jne .Lfail
    cmp rdx, 4
    jne .Lfail
    cmp ecx, 1
    jne .Lfail
    mov rdi, rbx
    mov esi, 4
    mov edx, 1
    call snippet_regex_scalar
    cmp eax, 10
    jne .Lfail
    cmp rdx, 3
    jne .Lfail
    mov rdi, rbx
    mov esi, 7
    xor edx, edx
    call snippet_regex_scalar
    test ecx, ecx
    jnz .Lfail
    mov r14d, 9
    mov rdi, rbx
    mov esi, 0x212a
    call snippet_regex_case
    cmp eax, 'k'
    jne .Lfail
    mov qword ptr [rbx + RX_flags], 2
    mov rdi, rbx
    mov esi, 0x212a
    call snippet_regex_case
    cmp eax, 0x212a
    jne .Lfail
    mov qword ptr [rbx + RX_flags], 18
    mov qword ptr [rbx + RX_pos], 4
    mov rdi, rbx
    mov esi, 3
    call snippet_regex_assert
    test eax, eax
    jz .Lfail
    mov qword ptr [rbx + RX_flags], 2
    mov rdi, rbx
    mov esi, 3
    call snippet_regex_assert
    test eax, eax
    jnz .Lfail
    mov qword ptr [rbx + RX_flags], 22
    mov qword ptr [rbx + RX_pos], 3
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_assert
    test eax, eax
    jz .Lfail
    mov qword ptr [rbx + RX_pos], 2
    mov rdi, rbx
    mov esi, 2
    call snippet_regex_assert
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    lea rsi, [rip + classprogram]
    mov edx, 112
    lea rcx, [rip + text]
    mov r8d, 7
    call snippet_regex_open
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    xor esi, esi
    mov edx, 0x212a
    call snippet_regex_class
    test eax, eax
    jz .Lfail
    mov rdi, rbx
    xor esi, esi
    mov edx, 0xe9
    call snippet_regex_class
    test eax, eax
    jnz .Lfail
    mov r14d, 10
    mov rdi, rbx
    lea rsi, [rip + program]
    mov edx, 80
    lea rcx, [rip + invalidtext]
    mov r8d, 1
    call snippet_regex_open
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rbx + RX_error], RX_INPUT_ERROR
    jne .Lfail
    cmp qword ptr [rbx + RX_ready], 0
    jne .Lfail
    mov rdi, rbx
    lea rsi, [rip + program]
    mov edx, 80
    lea rcx, [rip + text]
    mov r8d, 7
    call snippet_regex_open
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rbx + RX_error], RX_INPUT_ERROR
    jne .Lfail
    mov rdi, rbx
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lfail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    lea rdi, [rip + failed]
    call log_cstr
    mov edi, r14d
    add edi, '0'
    push rdi
    mov rdi, rsp
    mov esi, 1
    call log_write
    pop rdi
    lea rdi, [rip + newline]
    call log_cstr
    mov eax, 1
    EPILOGUE
.section .rodata
ok: .asciz "ok snippet regex state\n"
failed: .asciz "failed snippet regex state stage "
newline: .asciz "\n"

.p2align 3
program:
.long 0x58524e52,1,0x00100000,18,0,2,0,0,0,0,80,0
.long 1,107,0,0,0,0,0,0
classprogram:
.long 0x58524e52,1,0x00100000,18,0,2,1,3,0,0,112,0
.long 3,0,0,0,0,0,0,0
.long 0,3
.long 75,75,107,107,0x212a,0x212a
text: .byte 0xc3,0xa9,13,10,0xe2,0x84,0xaa
invalidtext: .byte 0xff
