# Portable regex VM. Each dispatch and every variable-length operation spends shared work.
.include "rhun.inc"
.text
# snippet_regex_repeat_state(ctx, id) -> rax key, rdx count, rcx previous position
FN snippet_regex_repeat_state
    PROLOGUE
    mov rbx, rdi
    lea r12, [rsi + rsi]
    add r12, [rbx + RX_nslots]
    mov r13, [rbx + r12*8 + RX_values]
    mov r14, [rbx + r12*8 + RX_values + 8]
    cmp r13, 0x7fffffff
    ja 7f
    mov rsi, r14
    call snippet_regex_boundary
    test eax, eax
    jz 7f
    jmp 9f
7:  mov rdi, rbx
    mov esi, RX_STATE_ERROR
    call snippet_regex_fail
9:  mov rax, r12
    mov rdx, r13
    mov rcx, r14
    EPILOGUE

# snippet_regex_find(ctx, start byte) -> 1 found, 0 no match, -1 terminal failure
FN snippet_regex_find
    PROLOGUE 16
    mov rbx, rdi
    mov r14, rsi
    mov qword ptr [rbx + RX_hasmatch], 0
    mov qword ptr [rbx + RX_pc], -1
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    cmp qword ptr [rbx + RX_ready], 0
    je .Lrxm_state
    call snippet_regex_clock
    test eax, eax
    jz .Lrxm_error
    mov rdi, rbx
    mov rsi, r14
    call snippet_regex_boundary
    test eax, eax
    jz .Lrxm_start
    mov rdi, rbx
    xor esi, esi
    call snippet_regex_rewind
    test eax, eax
    jz .Lrxm_error
    mov qword ptr [rbx + RX_nbranches], 0
    mov qword ptr [rbx + RX_ncalls], 0
    mov [rbx + RX_attempt], r14
.Lrxm_candidate:
    mov rax, [rbx + RX_program]
    mov eax, [rax + 36]
    mov [rbx + RX_pc], rax
    mov rax, [rbx + RX_attempt]
    mov [rbx + RX_pos], rax
    mov qword ptr [rbx + RX_backward], 0
.Lrxm_loop:
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxm_error
    mov r12, [rbx + RX_pc]
    shl r12, 4
    add r12, [rbx + RX_code]
    mov eax, [r12]
    cmp eax, 0
    je .Lrxm_match
    cmp eax, 3
    jbe .Lrxm_scalar
    cmp eax, 4
    je .Lrxm_assert
    cmp eax, 5
    je .Lrxm_save
    cmp eax, 6
    je .Lrxm_clear
    cmp eax, 7
    je .Lrxm_split
    cmp eax, 8
    je .Lrxm_jump
    cmp eax, 9
    je .Lrxm_reference
    cmp eax, 10
    je .Lrxm_rstart
    cmp eax, 11
    je .Lrxm_rtest
    cmp eax, 12
    je .Lrxm_rnext
    cmp eax, 13
    je .Lrxm_look
    cmp eax, 14
    je .Lrxm_scoped_assert
    cmp eax, 15
    je .Lrxm_scoped_reference
    jmp .Lrxm_state
.Lrxm_match:
    cmp qword ptr [rbx + RX_ncalls], 0
    jne 1f
    mov rdi, rbx
    call snippet_regex_result
    test eax, eax
    jz .Lrxm_error
    mov eax, 1
    EPILOGUE
1:  mov rdi, rbx
    call snippet_regex_return
    test eax, eax
    jz .Lrxm_backtrack
    jmp .Lrxm_loop
.Lrxm_scalar:
    mov rdi, rbx
    mov rsi, [rbx + RX_pos]
    mov rdx, [rbx + RX_backward]
    call snippet_regex_scalar
    test ecx, ecx
    jz .Lrxm_backtrack
    mov [rsp], rax
    mov [rsp + 8], rdx
    cmp dword ptr [r12], 1
    jne 1f
    mov rdi, rbx
    mov rsi, rax
    call snippet_regex_case
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    cmp eax, [r12 + 4]
    jne .Lrxm_backtrack
    jmp .Lrxm_consumed
1:  cmp dword ptr [r12], 2
    jne 2f
    test qword ptr [rbx + RX_flags], 8
    jnz .Lrxm_consumed
    mov edi, eax
    call snippet_regex_line
    test eax, eax
    jnz .Lrxm_backtrack
    jmp .Lrxm_consumed
2:  mov rdi, rbx
    mov esi, [r12 + 4]
    mov rdx, [rsp]
    call snippet_regex_class
    test eax, eax
    jz .Lrxm_backtrack
.Lrxm_consumed:
    mov rax, [rsp + 8]
    mov [rbx + RX_pos], rax
    jmp .Lrxm_next
.Lrxm_assert:
    mov rdi, rbx
    mov esi, [r12 + 4]
    call snippet_regex_assert
    test eax, eax
    jz .Lrxm_backtrack
    jmp .Lrxm_next
.Lrxm_scoped_assert:
    mov rdi, rbx
    mov esi, [r12 + 4]
    mov edx, [r12 + 8]
    call snippet_regex_scoped_assert
    test eax, eax
    jz .Lrxm_backtrack
    jmp .Lrxm_next
.Lrxm_save:
    mov rdi, rbx
    mov esi, [r12 + 4]
    mov rdx, [rbx + RX_pos]
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    jmp .Lrxm_next
.Lrxm_clear:
    mov r13d, [r12 + 4]
    mov r14d, [r12 + 8]
    add r14, r13
1:  cmp r13, r14
    jae .Lrxm_next
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxm_error
    mov rdi, rbx
    mov rsi, r13
    mov rdx, -1
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    inc r13
    jmp 1b
.Lrxm_split:
    mov rdi, rbx
    mov esi, [r12 + 8]
    call snippet_regex_branch
    test eax, eax
    jz .Lrxm_error
.Lrxm_jump:
    mov eax, [r12 + 4]
    mov [rbx + RX_pc], rax
    jmp .Lrxm_loop
.Lrxm_reference:
    mov rdi, rbx
    mov esi, [r12 + 4]
    call snippet_regex_reference
    test eax, eax
    jz .Lrxm_backtrack
    jmp .Lrxm_next
.Lrxm_scoped_reference:
    mov rdi, rbx
    mov esi, [r12 + 4]
    mov edx, [r12 + 8]
    call snippet_regex_scoped_reference
    test eax, eax
    jz .Lrxm_backtrack
    jmp .Lrxm_next
.Lrxm_rstart:
    mov r13d, [r12 + 4]
    shl r13, 1
    add r13, [rbx + RX_nslots]
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    mov rdi, rbx
    lea rsi, [r13 + 1]
    mov rdx, [rbx + RX_pos]
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    jmp .Lrxm_next
.Lrxm_rtest:
    mov rdi, rbx
    mov esi, [r12 + 4]
    call snippet_regex_repeat_state
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    mov r13, rax
    mov r14, rdx
    mov r15d, [r12 + 4]
    shl r15, 4
    add r15, [rbx + RX_repeats]
    mov eax, [r15 + 4]
    cmp r14, rax
    jae .Lrxm_rexit
    mov rdi, rbx
    lea rsi, [r13 + 1]
    mov rdx, [rbx + RX_pos]
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    mov eax, [r15]
    cmp r14, rax
    jb .Lrxm_rbody
    test dword ptr [r15 + 8], 1
    jnz 1f
    mov rdi, rbx
    mov esi, [r12 + 12]
    call snippet_regex_branch
    test eax, eax
    jz .Lrxm_error
    jmp .Lrxm_rbody
1:  mov rdi, rbx
    mov esi, [r12 + 8]
    call snippet_regex_branch
    test eax, eax
    jz .Lrxm_error
.Lrxm_rexit:
    mov eax, [r12 + 12]
    mov [rbx + RX_pc], rax
    jmp .Lrxm_loop
.Lrxm_rbody:
    mov eax, [r12 + 8]
    mov [rbx + RX_pc], rax
    jmp .Lrxm_loop
.Lrxm_rnext:
    mov rdi, rbx
    mov esi, [r12 + 4]
    call snippet_regex_repeat_state
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    mov r13, rax
    mov r14, rdx
    cmp rcx, [rbx + RX_pos]
    jne 1f
    mov eax, [r12 + 4]
    shl rax, 4
    add rax, [rbx + RX_repeats]
    mov eax, [rax]
    cmp r14, rax
    jae .Lrxm_backtrack
1:  cmp r14, 0x7fffffff
    je .Lrxm_state
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [r14 + 1]
    call snippet_regex_write
    test eax, eax
    jz .Lrxm_error
    mov eax, [r12 + 8]
    mov [rbx + RX_pc], rax
    jmp .Lrxm_loop
.Lrxm_look:
    mov rdi, rbx
    mov esi, [r12 + 4]
    mov edx, [r12 + 8]
    mov ecx, [r12 + 12]
    call snippet_regex_call
    test eax, eax
    jz .Lrxm_error
    jmp .Lrxm_loop
.Lrxm_next:
    inc qword ptr [rbx + RX_pc]
    jmp .Lrxm_loop
.Lrxm_backtrack:
    mov rdi, rbx
    call snippet_regex_backtrack
    test eax, eax
    jnz .Lrxm_loop
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxm_error
    mov rdi, rbx
    xor esi, esi
    call snippet_regex_rewind
    test eax, eax
    jz .Lrxm_error
    mov qword ptr [rbx + RX_nbranches], 0
    mov qword ptr [rbx + RX_ncalls], 0
    test qword ptr [rbx + RX_flags], 32
    jnz .Lrxm_none
    mov rax, [rbx + RX_attempt]
    cmp rax, [rbx + RX_ilen]
    je .Lrxm_none
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxm_error
    mov rdi, rbx
    mov rsi, [rbx + RX_attempt]
    xor edx, edx
    call snippet_regex_scalar
    test ecx, ecx
    jz .Lrxm_error
    mov [rbx + RX_attempt], rdx
    jmp .Lrxm_candidate
.Lrxm_none:
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz .Lrxm_error
    xor eax, eax
    EPILOGUE
.Lrxm_state:
    mov esi, RX_STATE_ERROR
    jmp 1f
.Lrxm_start:
    mov esi, RX_START_ERROR
1:  mov rdi, rbx
    call snippet_regex_fail
.Lrxm_error:
    mov rax, -1
    EPILOGUE
