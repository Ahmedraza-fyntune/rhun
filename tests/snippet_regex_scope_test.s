.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    mov r15, [rip + g_mem_live]
    xor r14d, r14d
.Lscope_case:
    mov edi, 10000
    xor esi, esi
    call snippet_regex_new
    test rax, rax
    jz .Lscope_fail
    mov rbx, rax
    lea rax, [rip + text]
    mov [rbx + RX_input], rax
    mov qword ptr [rbx + RX_ilen], 2
    mov qword ptr [rbx + RX_flags], 16
    mov qword ptr [rbx + RX_ncaps], 1
    mov qword ptr [rbx + RX_nvalues], 4
    mov qword ptr [rbx + RX_values + 16], 0
    mov qword ptr [rbx + RX_values + 24], 1
    mov qword ptr [rbx + RX_pos], 1
    mov qword ptr [rbx + RX_hasmatch], 1
    mov eax, r14d
    and eax, 3
    mov [rsp], rax
    cmp eax, 2
    jne 1f
    mov qword ptr [rbx + RX_work], 0
1:  cmp eax, 3
    jne 2f
    mov qword ptr [rbx + RX_deadline], 1
    mov qword ptr [rbx + RX_clockat], 10000
2:  mov rdi, rbx
    cmp r14, 4
    jae .Lscope_assert
    mov esi, 1
    mov edx, 2
    cmp qword ptr [rsp], 1
    jne 3f
    xor edx, edx
3:  call snippet_regex_scoped_reference
    jmp .Lscope_check
.Lscope_assert:
    mov esi, 4
    mov edx, 6
    cmp qword ptr [rsp], 1
    jne 4f
    mov esi, 3
4:  call snippet_regex_scoped_assert
.Lscope_check:
    cmp qword ptr [rbx + RX_flags], 16
    jne .Lscope_fail
    cmp qword ptr [rsp], 2
    je .Lscope_work
    cmp qword ptr [rsp], 3
    je .Lscope_time
    cmp qword ptr [rbx + RX_error], 0
    jne .Lscope_fail
    mov rcx, [rsp]
    xor ecx, 1
    cmp rax, rcx
    jne .Lscope_fail
    jmp .Lscope_free
.Lscope_work:
    cmp qword ptr [rbx + RX_error], RX_WORK_ERROR
    jne .Lscope_fail
    jmp .Lscope_unpublished
.Lscope_time:
    cmp qword ptr [rbx + RX_error], RX_TIME_ERROR
    jne .Lscope_fail
.Lscope_unpublished:
    cmp qword ptr [rbx + RX_hasmatch], 0
    jne .Lscope_fail
.Lscope_free:
    mov rdi, rbx
    call snippet_regex_free
    cmp r15, [rip + g_mem_live]
    jne .Lscope_fail
    inc r14
    cmp r14, 8
    jb .Lscope_case
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lscope_fail:
    lea rdi, [rip + failed]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE
.section .rodata
text: .ascii "Aa"
ok: .asciz "ok snippet regex scoped flags\n"
failed: .asciz "failed snippet regex scoped flags case "
