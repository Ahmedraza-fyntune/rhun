# Regex branch and assertion control flow. Parent alternatives survive child assertions.
.include "rhun.inc"
.text
# snippet_regex_backtrack(ctx) -> 1 resume, 0 exhausted or terminal failure
FN snippet_regex_backtrack
    PROLOGUE
    mov rbx, rdi
.Lrxb_loop:
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxb_none
    xor r12d, r12d
    mov rax, [rbx + RX_ncalls]
    test rax, rax
    jz 1f
    dec rax
    imul rax, rax, 48
    lea r13, [rbx + rax + RX_calls]
    mov r12, [r13 + 24]
1:  cmp [rbx + RX_nbranches], r12
    ja .Lrxb_branch
    cmp qword ptr [rbx + RX_ncalls], 0
    je .Lrxb_none
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxb_none
    dec qword ptr [rbx + RX_ncalls]
    mov rdi, rbx
    mov rsi, [r13 + 16]
    call snippet_regex_rewind
    test eax, eax
    jz .Lrxb_none
    mov rax, [r13]
    mov [rbx + RX_pc], rax
    mov rax, [r13 + 8]
    mov [rbx + RX_pos], rax
    mov rax, [r13 + 32]
    mov [rbx + RX_backward], rax
    cmp qword ptr [r13 + 40], 0
    je .Lrxb_loop
    mov eax, 1
    EPILOGUE
.Lrxb_branch:
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxb_none
    dec qword ptr [rbx + RX_nbranches]
    mov rax, [rbx + RX_nbranches]
    imul rax, rax, 24
    lea r12, [rbx + rax + RX_branches]
    mov rdi, rbx
    mov rsi, [r12 + 16]
    call snippet_regex_rewind
    test eax, eax
    jz .Lrxb_none
    mov rax, [r12]
    mov [rbx + RX_pc], rax
    mov rax, [r12 + 8]
    mov [rbx + RX_pos], rax
    mov eax, 1
    EPILOGUE
.Lrxb_none:
    xor eax, eax
    EPILOGUE
# snippet_regex_call(ctx, subpc, continuation, flags) -> 1
FN snippet_regex_call
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rax, [rbx + RX_ncalls]
    cmp rax, RX_CALL_MAX
    jae 7f
    imul rax, rax, 48
    lea rax, [rbx + rax + RX_calls]
    mov [rax], r13
    mov rcx, [rbx + RX_pos]
    mov [rax + 8], rcx
    mov rcx, [rbx + RX_ntrail]
    mov [rax + 16], rcx
    mov rcx, [rbx + RX_nbranches]
    mov [rax + 24], rcx
    mov rcx, [rbx + RX_backward]
    mov [rax + 32], rcx
    mov rcx, r14
    and ecx, 1
    mov [rax + 40], rcx
    inc qword ptr [rbx + RX_ncalls]
    shr r14, 1
    and r14d, 1
    mov [rbx + RX_backward], r14
    mov [rbx + RX_pc], r12
    mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_CALL_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
# Child MATCH resolves only the assertion. Positive captures remain reversible by the parent.
FN snippet_regex_return
    PROLOGUE
    mov rbx, rdi
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    dec qword ptr [rbx + RX_ncalls]
    mov rax, [rbx + RX_ncalls]
    imul rax, rax, 48
    lea r12, [rbx + rax + RX_calls]
    mov rax, [r12]
    mov [rbx + RX_pc], rax
    mov rax, [r12 + 8]
    mov [rbx + RX_pos], rax
    mov rax, [r12 + 24]
    mov [rbx + RX_nbranches], rax
    mov rax, [r12 + 32]
    mov [rbx + RX_backward], rax
    cmp qword ptr [r12 + 40], 0
    je 9f
    mov rdi, rbx
    mov rsi, [r12 + 16]
    call snippet_regex_rewind
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
# snippet_regex_reference(ctx, group) -> match. Undefined/open captures match empty.
FN snippet_regex_reference
    PROLOGUE 32
    mov rbx, rdi
    shl rsi, 1
    mov r12, [rbx + rsi*8 + RX_values]
    mov r13, [rbx + rsi*8 + RX_values + 8]
    cmp r12, -1
    je .Lrxr_yes
    cmp r13, -1
    je .Lrxr_yes
    cmp r12, r13
    ja .Lrxr_state
    mov rsi, r12
    call snippet_regex_boundary
    test eax, eax
    jz .Lrxr_state
    mov rdi, rbx
    mov rsi, r13
    call snippet_regex_boundary
    test eax, eax
    jz .Lrxr_state
    mov r14, r12
    cmp qword ptr [rbx + RX_backward], 0
    je 1f
    mov r14, r13
1:  mov r15, [rbx + RX_pos]
.Lrxr_loop:
    cmp qword ptr [rbx + RX_backward], 0
    jne 2f
    cmp r14, r13
    je .Lrxr_done
    jmp 3f
2:  cmp r14, r12
    je .Lrxr_done
3:  mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz .Lrxr_no
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [rbx + RX_backward]
    call snippet_regex_scalar
    test ecx, ecx
    jz .Lrxr_state
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [rbx + RX_backward]
    call snippet_regex_scalar
    test ecx, ecx
    jz .Lrxr_no
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rdi, rbx
    mov rsi, [rsp]
    call snippet_regex_case
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, [rsp + 16]
    call snippet_regex_case
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxr_no
    cmp rax, [rsp]
    jne .Lrxr_no
    mov r14, [rsp + 8]
    mov r15, [rsp + 24]
    jmp .Lrxr_loop
.Lrxr_done:
    mov [rbx + RX_pos], r15
.Lrxr_yes:
    mov eax, 1
    EPILOGUE
.Lrxr_state:
    mov rdi, rbx
    mov esi, RX_STATE_ERROR
    call snippet_regex_fail
.Lrxr_no:
    xor eax, eax
    EPILOGUE
# Validate and publish a top-level match. No complete-pair check occurs inside LOOK.
FN snippet_regex_result
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + RX_ncaps]
    inc rsi
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rax, [rbx + RX_attempt]
    mov [rbx + RX_start], rax
    mov [rbx + RX_captures], rax
    mov rax, [rbx + RX_pos]
    mov [rbx + RX_end], rax
    mov [rbx + RX_captures + 8], rax
    mov r12d, 1
1:  cmp r12, [rbx + RX_ncaps]
    ja 6f
    mov rax, r12
    shl rax, 4
    mov r13, [rbx + rax + RX_values]
    mov r14, [rbx + rax + RX_values + 8]
    cmp r13, -1
    jne 2f
    cmp r14, -1
    je 5f
    jmp 7f
2:  cmp r14, -1
    je 7f
    cmp r13, r14
    ja 7f
    mov rdi, rbx
    mov rsi, r13
    call snippet_regex_boundary
    test eax, eax
    jz 7f
    mov rdi, rbx
    mov rsi, r14
    call snippet_regex_boundary
    test eax, eax
    jz 7f
5:  mov rax, r12
    shl rax, 4
    mov [rbx + rax + RX_captures], r13
    mov [rbx + rax + RX_captures + 8], r14
    inc r12
    jmp 1b
6:  mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz 8f
    mov qword ptr [rbx + RX_hasmatch], 1
    mov eax, 1
    EPILOGUE
7:  mov rdi, rbx
    mov esi, RX_STATE_ERROR
    call snippet_regex_fail
8:  xor eax, eax
    EPILOGUE
