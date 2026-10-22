# Atomic private native transform execution. Borrowed programs last until return.
.include "rhun.inc"
.text
# Discard matcher views without touching the batch budget or first diagnostic.
FN snippet_transform_detach
    mov qword ptr [rdi + RX_ready], 0
    mov qword ptr [rdi + RX_hasmatch], 0
    mov qword ptr [rdi + RX_program], 0
    mov qword ptr [rdi + RX_plen], 0
    mov qword ptr [rdi + RX_code], 0
    mov qword ptr [rdi + RX_classes], 0
    mov qword ptr [rdi + RX_ranges], 0
    mov qword ptr [rdi + RX_repeats], 0
    mov qword ptr [rdi + RX_input], 0
    mov qword ptr [rdi + RX_ilen], 0
    ret
# output(TF*, ptr, len, record) -> bool
FN snippet_transform_output
    mov rax, [rdi + SC_rx]
    cmp qword ptr [rax + RX_error], 0
    jne 8f
    mov qword ptr [rax + RX_tstage], TRANSFORM_OUTPUT
    mov [rax + RX_trecord], rcx
    mov qword ptr [rax + RX_pc], -1
    mov qword ptr [rax + RX_errbyte], -1
    mov rcx, rdx
    mov rdx, rsi
    lea rsi, [rdi + SC_out]
    mov r8d, 4194304
    jmp snippet_case_append
8:  xor eax, eax
    ret
# finish(TF*) -> owned bytes, len, ecx success; every nonsticky exit uses this.
FN snippet_transform_finish
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + TXF_temp]
    call mem_free
    mov qword ptr [rbx + TXF_temp], 0
    mov rdi, [rbx + SC_rx]
    cmp qword ptr [rdi + RX_error], 0
    jne 1f
    mov qword ptr [rdi + RX_tstage], TRANSFORM_OUTPUT
    mov qword ptr [rdi + RX_trecord], -1
    mov qword ptr [rdi + RX_pc], -1
    mov qword ptr [rdi + RX_errbyte], -1
1:  mov rdi, rbx
    call snippet_case_finish
    mov r12, rax
    mov r13, rdx
    mov r14, rcx
    mov rdi, [rbx + SC_rx]
    call snippet_transform_detach
    test r14, r14
    jz 2f
    mov rax, [rbx + SC_rx]
    mov qword ptr [rax + RX_tstage], 0
    mov qword ptr [rax + RX_trecord], -1
2:  mov rax, r12
    mov rdx, r13
    mov rcx, r14
    EPILOGUE
# execute(RX*, readonly TD*) -> owned bytes, len, ecx success
FN snippet_transform_execute
    PROLOGUE TXF_SIZE
    mov r12, rdi
    mov r13, rsi
    cmp qword ptr [r12 + RX_error], 0
    jne .Ltx_sticky
    mov rbx, rsp
    mov rdi, rsp
    mov ecx, TXF_SIZE/8
    xor eax, eax
    rep stosq
    mov [rbx + SC_rx], r12
    mov [rbx + TXF_desc], r13
    mov rdi, r12
    call snippet_transform_detach
    mov qword ptr [r12 + RX_pc], -1
    mov qword ptr [r12 + RX_errbyte], -1
    mov qword ptr [r12 + RX_tstage], TRANSFORM_FORMAT
    mov qword ptr [r12 + RX_trecord], -1
    mov r14, [r13 + TD_format]
    mov r15, [r13 + TD_flen]
    cmp r15, 32
    jb .Ltx_format_bad
    cmp r15, 4194304
    ja .Ltx_format_bad
    mov eax, [r14 + 12]
    cmp eax, 8192
    ja .Ltx_format_bad
    mov [rbx + TXF_nrecords], rax
    imul rax, rax, 24
    add rax, 32
    cmp rax, r15
    ja .Ltx_format_bad
    mov [rbx + TXF_format], r14
    lea rdx, [r14 + rax]
    mov [rbx + TXF_blob], rdx
    mov r14, rax
    mov rdi, r12
    call snippet_regex_clock
    test eax, eax
    jz .Ltx_finish
    mov rdi, r12
    mov rsi, r14
    call snippet_regex_spend
    test eax, eax
    jz .Ltx_finish
    mov rdi, r12
    mov rsi, r15
    sub rsi, r14
    call snippet_regex_spend
    test eax, eax
    jz .Ltx_finish
    mov rdi, [rbx + TXF_format]
    mov rsi, r15
    call snippet_replacement_validate
    test eax, eax
    jz .Ltx_format_offset
    mov rdi, r12
    call snippet_regex_clock
    test eax, eax
    jz .Ltx_finish
    mov r14, [rbx + TXF_format]
    add r14, 32
    mov r15, [rbx + TXF_nrecords]
.Ltx_fallback_scan:
    test r15, r15
    jz .Ltx_open
    cmp dword ptr [r14], 10
    jne 1f
    cmp dword ptr [r14 + 12], 0
    jne 2f
1:  cmp dword ptr [r14], 11
    jne 3f
    cmp dword ptr [r14 + 20], 0
    je 3f
2:  mov qword ptr [rbx + TXF_fallback], 1
3:  add r14, 24
    dec r15
    jmp .Ltx_fallback_scan
.Ltx_open:
    mov qword ptr [r12 + RX_tstage], TRANSFORM_MATCH
    mov rdi, r12
    mov rsi, [r13 + TD_regex]
    mov rdx, [r13 + TD_rlen]
    mov rcx, [r13 + TD_input]
    mov r8, [r13 + TD_ilen]
    call snippet_regex_open
    test eax, eax
    jz .Ltx_finish
.Ltx_find:
    mov qword ptr [r12 + RX_tstage], TRANSFORM_MATCH
    mov qword ptr [r12 + RX_trecord], -1
    mov rdi, r12
    mov rsi, [rbx + TXF_next]
    call snippet_regex_find
    test rax, rax
    js .Ltx_finish
    jz .Ltx_no_more
    mov qword ptr [rbx + TXF_found], 1
    mov rdi, rbx
    mov rsi, [r13 + TD_input]
    add rsi, [rbx + TXF_cursor]
    mov rdx, [r12 + RX_start]
    sub rdx, [rbx + TXF_cursor]
    mov rcx, -1
    call snippet_transform_output
    test eax, eax
    jz .Ltx_finish
    mov rdi, rbx
    mov esi, 1
    call snippet_transform_render
    test eax, eax
    jz .Ltx_finish
    mov rax, [r12 + RX_end]
    mov [rbx + TXF_cursor], rax
    test qword ptr [r12 + RX_flags], 1
    jz .Ltx_tail
    mov [rbx + TXF_next], rax
    cmp rax, [r12 + RX_start]
    jne .Ltx_find
    cmp rax, [r13 + TD_ilen]
    je .Ltx_tail
    mov qword ptr [r12 + RX_tstage], TRANSFORM_MATCH
    mov qword ptr [r12 + RX_trecord], -1
    mov qword ptr [r12 + RX_pc], -1
    mov rdi, r12
    mov esi, 4
    call snippet_regex_spend
    test eax, eax
    jz .Ltx_finish
    mov rdi, [r13 + TD_input]
    add rdi, [rbx + TXF_next]
    mov rsi, [r13 + TD_ilen]
    sub rsi, [rbx + TXF_next]
    call utf8_decode
    add [rbx + TXF_next], rdx
    jmp .Ltx_find
.Ltx_no_more:
    cmp qword ptr [rbx + TXF_found], 0
    jne .Ltx_tail
    cmp qword ptr [rbx + TXF_fallback], 0
    je .Ltx_tail
    mov rdi, rbx
    xor esi, esi
    call snippet_transform_render
    jmp .Ltx_finish
.Ltx_tail:
    mov rdi, rbx
    mov rsi, [r13 + TD_input]
    add rsi, [rbx + TXF_cursor]
    mov rdx, [r13 + TD_ilen]
    sub rdx, [rbx + TXF_cursor]
    mov rcx, -1
    call snippet_transform_output
.Ltx_finish:
    mov rdi, rbx
    call snippet_transform_finish
    EPILOGUE
.Ltx_format_bad:
    mov qword ptr [r12 + RX_errbyte], -1
    jmp 1f
.Ltx_format_offset:
    mov [r12 + RX_errbyte], rdx
1:  mov rdi, r12
    mov esi, RX_REPLACEMENT_ERROR
    call snippet_regex_fail
    jmp .Ltx_finish
.Ltx_sticky:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
