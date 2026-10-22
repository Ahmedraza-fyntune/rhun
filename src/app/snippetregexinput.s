# Validated regex inputs and scalar predicates. Buffers remain owned by the caller.
.include "rhun.inc"
.text
# snippet_regex_open(ctx, program, programlen, input, inputlen) -> 1 or sticky failure
FN snippet_regex_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov qword ptr [rbx + RX_hasmatch], 0
    mov qword ptr [rbx + RX_ready], 0
    mov qword ptr [rbx + RX_pc], -1
    cmp qword ptr [rbx + RX_error], 0
    jne .Lrxo_bad
    mov qword ptr [rbx + RX_errbyte], 0
    call snippet_regex_clock
    test eax, eax
    jz .Lrxo_bad
    cmp r13, 262144
    ja .Lrxo_program_size
    cmp r15, 4194304
    ja .Lrxo_input
    mov rdi, rbx
    lea rsi, [r13 + r15 + 1]
    call snippet_regex_spend
    test eax, eax
    jz .Lrxo_bad
    mov rdi, r12
    mov rsi, r13
    call snippet_regex_validate
    test eax, eax
    jz .Lrxo_program
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz .Lrxo_bad
    mov [rbx + RX_program], r12
    mov [rbx + RX_plen], r13
    mov [rbx + RX_input], r14
    mov [rbx + RX_ilen], r15
    mov eax, [r12 + 12]
    mov [rbx + RX_flags], rax
    mov eax, [r12 + 16]
    mov [rbx + RX_ncaps], rax
    inc eax
    shl eax, 1
    mov [rbx + RX_nslots], rax
    mov eax, [r12 + 20]
    mov [rbx + RX_ncode], rax
    mov eax, [r12 + 24]
    mov [rbx + RX_nclasses], rax
    mov eax, [r12 + 28]
    mov [rbx + RX_nranges], rax
    mov eax, [r12 + 32]
    mov [rbx + RX_nrepeats], rax
    shl rax, 1
    add rax, [rbx + RX_nslots]
    mov [rbx + RX_nvalues], rax
    lea rax, [r12 + 48]
    mov [rbx + RX_code], rax
    mov rcx, [rbx + RX_ncode]
    shl rcx, 4
    add rax, rcx
    mov [rbx + RX_classes], rax
    mov rcx, [rbx + RX_nclasses]
    lea rax, [rax + rcx*8]
    mov [rbx + RX_ranges], rax
    mov rcx, [rbx + RX_nranges]
    lea rax, [rax + rcx*8]
    mov [rbx + RX_repeats], rax
    mov r12, r14
    mov r13, r15
    xor r14d, r14d
    xor r15d, r15d
.Lrxo_scan:
    cmp r14, r13
    jae .Lrxo_values
    lea rdi, [r12 + r14]
    mov rsi, r13
    sub rsi, r14
    call utf8_decode
    cmp eax, 0x10ffff
    ja .Lrxo_input
    cmp eax, 0xd800
    jb 1f
    cmp eax, 0xdfff
    jbe .Lrxo_input
1:  cmp eax, 0xfffd
    jne 2f
    cmp edx, 1
    je .Lrxo_input
2:  add r14, rdx
    inc r15
    cmp r15, 1024
    jb .Lrxo_scan
    xor r15d, r15d
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz .Lrxo_bad
    jmp .Lrxo_scan
.Lrxo_values:
    mov rdi, rbx
    mov rsi, [rbx + RX_nvalues]
    call snippet_regex_spend
    test eax, eax
    jz .Lrxo_bad
    lea rdi, [rbx + RX_values]
    mov rcx, [rbx + RX_nvalues]
    mov rax, -1
    rep stosq
    mov qword ptr [rbx + RX_ntrail], 0
    mov qword ptr [rbx + RX_nbranches], 0
    mov qword ptr [rbx + RX_ncalls], 0
    mov rdi, rbx
    call snippet_regex_clock
    test eax, eax
    jz .Lrxo_bad
    mov qword ptr [rbx + RX_ready], 1
    mov eax, 1
    EPILOGUE
.Lrxo_program_size:
    mov edx, 40
.Lrxo_program:
    mov [rbx + RX_errbyte], rdx
    mov esi, RX_PROGRAM_ERROR
    jmp .Lrxo_fail
.Lrxo_input:
    mov esi, RX_INPUT_ERROR
.Lrxo_fail:
    mov rdi, rbx
    call snippet_regex_fail
.Lrxo_bad:
    xor eax, eax
    EPILOGUE

# snippet_regex_boundary(ctx, byte offset) -> valid
FN snippet_regex_boundary
    xor eax, eax
    cmp rsi, [rdi + RX_ilen]
    ja 8f
    je 9f
    mov rcx, [rdi + RX_input]
    movzx ecx, byte ptr [rcx + rsi]
    and ecx, 0xc0
    cmp ecx, 0x80
    je 8f
9:  mov eax, 1
8:  ret
# snippet_regex_scalar(ctx, pos, backward) -> eax cp, rdx next pos, ecx present
FN snippet_regex_scalar
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jnz 1f
    cmp r12, [rbx + RX_ilen]
    je 8f
    jmp 2f
1:  test r12, r12
    jz 8f
2:  mov esi, 4
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov r14, [rbx + RX_input]
    mov r15, r12
    test r13, r13
    jz 4f
    dec r15
3:  movzx eax, byte ptr [r14 + r15]
    and eax, 0xc0
    cmp eax, 0x80
    jne 4f
    dec r15
    jmp 3b
4:  lea rdi, [r14 + r15]
    mov rsi, [rbx + RX_ilen]
    sub rsi, r15
    call utf8_decode
    test r13, r13
    jnz 5f
    add rdx, r15
    jmp 6f
5:  mov rdx, r15
6:  mov ecx, 1
    EPILOGUE
8:  xor eax, eax
    mov rdx, r12
    xor ecx, ecx
    EPILOGUE
# Canonicalization without a VM budget, for already charged scalar operations.
FN snippet_regex_canonical
    PROLOGUE
    mov r12d, edi
    mov r13, rsi
    test r13, 2
    jz 8f
    test r13, 16
    jz 1f
    call snippet_unicode_fold
    EPILOGUE
1:  call snippet_unicode_upper
    test rdx, rdx
    jz 8f
    mov r14, rdx
    mov rdi, rax
    mov rsi, rdx
    call utf8_decode
    cmp rdx, r14
    jne 8f
    cmp r12d, 128
    jb 9f
    cmp eax, 128
    jb 8f
9:  EPILOGUE
8:  mov eax, r12d
    EPILOGUE
# snippet_regex_case(ctx, cp) -> eax canonical cp (check ctx.error before use)
FN snippet_regex_case
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test qword ptr [rbx + RX_flags], 2
    jz 8f
    mov esi, 16
    call snippet_regex_spend
    test eax, eax
    jz 8f
    mov rdi, r12
    mov rsi, [rbx + RX_flags]
    call snippet_regex_canonical
    EPILOGUE
8:  mov eax, r12d
    EPILOGUE
FN snippet_regex_line
    cmp edi, 10
    je 9f
    cmp edi, 13
    je 9f
    cmp edi, 0x2028
    je 9f
    cmp edi, 0x2029
    je 9f
    xor eax, eax
    ret
9:  mov eax, 1
    ret
# snippet_regex_class(ctx, class id, cp) -> membership
FN snippet_regex_class
    PROLOGUE 16
    mov rbx, rdi
    mov r13, rdx
    mov rax, [rbx + RX_classes]
    mov ecx, [rax + rsi*8]
    mov r15d, [rax + rsi*8 + 4]
    mov rax, [rbx + RX_ranges]
    lea rax, [rax + rcx*8]
    mov [rsp], rax
    mov [rsp + 8], r15
    xor r14d, r14d
1:  cmp r14, r15
    jae 3f
    mov rdi, rbx
    mov esi, 1
    call snippet_regex_spend
    test eax, eax
    jz 8f
    lea r12, [r14 + r15]
    shr r12, 1
    mov rax, [rsp]
    cmp [rax + r12*8 + 4], r13d
    jb 2f
    mov r15, r12
    jmp 1b
2:  lea r14, [r12 + 1]
    jmp 1b
3:  cmp r14, [rsp + 8]
    jae 8f
    mov rax, [rsp]
    cmp [rax + r14*8], r13d
    ja 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# snippet_regex_word(ctx, pos, backward) -> word character adjacent to a boundary
FN snippet_regex_word
    PROLOGUE
    mov rbx, rdi
    call snippet_regex_scalar
    test ecx, ecx
    jz 8f
    mov rdi, rbx
    mov esi, eax
    call snippet_regex_case
    cmp qword ptr [rbx + RX_error], 0
    jne 8f
    cmp eax, '_'
    je 9f
    cmp eax, '0'
    jb 8f
    cmp eax, '9'
    jbe 9f
    cmp eax, 'A'
    jb 8f
    cmp eax, 'Z'
    jbe 9f
    cmp eax, 'a'
    jb 8f
    cmp eax, 'z'
    ja 8f
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# snippet_regex_assert(ctx, kind) -> assertion
FN snippet_regex_assert
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 1
    je 1f
    cmp r12, 2
    je 2f
    mov rsi, [rbx + RX_pos]
    mov edx, 1
    call snippet_regex_word
    mov r13, rax
    mov rdi, rbx
    mov rsi, [rbx + RX_pos]
    xor edx, edx
    call snippet_regex_word
    xor eax, r13d
    cmp r12, 3
    je 7f
    xor eax, 1
7:  EPILOGUE
1:  cmp qword ptr [rbx + RX_pos], 0
    je 9f
    test qword ptr [rbx + RX_flags], 4
    jz 8f
    mov rsi, [rbx + RX_pos]
    mov edx, 1
    jmp 3f
2:  mov rax, [rbx + RX_pos]
    cmp rax, [rbx + RX_ilen]
    je 9f
    test qword ptr [rbx + RX_flags], 4
    jz 8f
    mov rsi, rax
    xor edx, edx
3:  mov rdi, rbx
    call snippet_regex_scalar
    test ecx, ecx
    jz 8f
    mov edi, eax
    call snippet_regex_line
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
