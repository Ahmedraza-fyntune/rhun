.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
many: .zero DOC_SELECTIONS_MAX * DMP_SIZE
.text

# check(doc, text, len, pairs, count) -> bool, comparing all oriented selections.
check:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    call doc_len
    cmp rax, r13
    jne .Lcheck_bad
    lea rdi, [r13 + 1]
    call mem_alloc
    mov [rsp], rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    mov rcx, rax
    call doc_copy
    mov rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call memeq
    mov [rsp + 8], rax
    mov rdi, [rsp]
    call mem_free
    cmp qword ptr [rsp + 8], 0
    je .Lcheck_bad
    mov rdi, rbx
    call doc_selections_count
    cmp rax, r15
    jne .Lcheck_bad
    mov qword ptr [rsp + 16], 0
1:  mov rsi, [rsp + 16]
    cmp rsi, r15
    jae .Lcheck_ok
    mov rdi, rbx
    call doc_selections_get
    test r8d, r8d
    jz .Lcheck_bad
    cmp rax, [r14 + DMP_cur]
    jne .Lcheck_bad
    cmp rdx, [r14 + DMP_anchor]
    jne .Lcheck_bad
    add r14, DMP_SIZE
    inc qword ptr [rsp + 16]
    jmp 1b
.Lcheck_ok:
    mov eax, 1
    EPILOGUE
.Lcheck_bad:
    xor eax, eax
    EPILOGUE

# Check one fixture side. Caller r12 is a vector of ten qwords.
.macro CHECK_SIDE side
    mov rdi, rbx
    mov rsi, [r12 + \side]
    mov rdx, [r12 + \side + 8]
    mov rcx, [r12 + \side + 16]
    mov r8, [r12 + \side + 24]
    call check
    test eax, eax
    jz failed
.endm

FN main
    PROLOGUE 80
    mov r15, [rip + g_mem_live]
    lea r12, [rip + vectors]
    mov r13d, 1
.Ltest_case:
    cmp qword ptr [r12], 0
    je .Ltest_outer
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r12]
    mov rcx, [r12 + 8]
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    cmp eax, 1
    jne failed
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rsi, [r12 + 32]
    test rsi, rsi
    jnz 1f
    cmp qword ptr [r12 + 40], 0
    je 1f
    mov rdi, rbx
    call doc_contiguous
    mov rsi, rax             # payload borrows document storage that the batch can reallocate
1:  mov rdi, rbx
    mov rdx, [r12 + 40]
    call doc_selections_replace
    cmp eax, 1
    jne failed
    test edx, edx
    jnz failed
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne failed
    CHECK_SIDE 48
    mov rax, [rbx + DOC_undo + VEC_len]
    cmp rax, [rsp]
    je .Ltest_free          # an all-empty deletion is history-free
    # Only the first record owns before extras; intermediate records own none.
    mov r14, [rsp]
1:  cmp r14, [rbx + DOC_undo + VEC_len]
    jae 3f
    imul rax, r14, UR_SIZE
    add rax, [rbx + DOC_undo + VEC_ptr]
    cmp r14, [rsp]
    je 2f
    cmp qword ptr [rax + UR_beforeselections], 0
    jne failed
2:  inc r14
    jmp 1b
3:  mov r14d, 3
.Ltest_replay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    CHECK_SIDE 0
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    CHECK_SIDE 48
    dec r14
    jnz .Ltest_replay
    # A new batch after undo releases both boundary snapshots owned by redo history.
    mov rdi, rbx
    call doc_undo
    mov rsi, [r12 + 32]
    test rsi, rsi
    jnz 4f
    cmp qword ptr [r12 + 40], 0
    je 4f
    mov rdi, rbx
    call doc_contiguous
    mov rsi, rax
4:  mov rdi, rbx
    mov rdx, [r12 + 40]
    call doc_selections_replace
    cmp eax, 1
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 0
    jne failed
    CHECK_SIDE 48
.Ltest_free:
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 80
    inc r13
    jmp .Ltest_case
.Ltest_outer:
    mov r13d, 100
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + abcdef]
    mov ecx, 6
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + order_pairs]
    mov edx, 3
    call doc_selections_set
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    mov esi, 6
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    call doc_selections_replace
    cmp eax, 1
    jne failed
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_end_group
    # The owner finalizes selections after the last edit in the enclosing group.
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    mov r14d, 3
.Ltest_outer_replay:
    mov rdi, rbx
    lea rsi, [rip + outer_text]
    mov edx, 8
    lea rcx, [rip + outer_pairs]
    mov r8d, 3
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + abcdef]
    mov edx, 6
    lea rcx, [rip + order_pairs]
    mov r8d, 3
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    dec r14
    jnz .Ltest_outer_replay
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    jmp .Ltest_errors
.Ltest_errors:
    mov r13d, 200
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + unicode]
    mov ecx, 4
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 4
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + unicode_pairs]
    mov edx, 2
    call doc_selections_set
    # Keep a real owned snippet node and a redo record during every rejection.
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov [rsp + 24], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 16], rax
    lea r12, [rip + errors]
.Ltest_error:
    mov rdx, [r12 + 8]
    cmp rdx, -1
    je .Ltest_error_flags
    mov rdi, rbx
    mov rsi, [r12]
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp rdx, [r12 + 16]
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    add r12, 24
    inc r13
    jmp .Ltest_error
.Ltest_error_flags:
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp edx, 3
    jne failed
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 1
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp edx, 4
    jne failed
    mov qword ptr [rbx + DOC_selectionbatch], 0
    # Deliberately corrupted primary endpoints are rejected without changing anything.
    mov qword ptr [rbx + DOC_cur], 2
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov qword ptr [rbx + DOC_cur], 3
    # A malformed stored count is rejected before any snapshot clone or array read.
    mov r14, [rbx + DOC_selections]
    mov qword ptr [r14 + DMS_count], DOC_SELECTIONS_MAX
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov qword ptr [r14 + DMS_count], 1
    mov rdi, rbx
    mov rsi, [rsp + 16]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 16]
    call mem_free
    mov r14, [rbx + DOC_undo + VEC_len]
    mov rdi, rbx
    lea rsi, [rip + noop_pairs]
    mov edx, 3
    call doc_selections_set
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call doc_selections_replace
    cmp eax, 1
    jne failed
    mov rax, [rsp + 24]
    cmp [rbx + DOC_snippet], rax
    jne failed
    cmp [rbx + DOC_undo + VEC_len], r14
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
    mov rdi, rbx
    call doc_selections_count
    cmp rax, 1
    jne failed
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 300
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + max_text]
    mov ecx, DOC_SELECTIONS_MAX
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + max_pairs]
    mov edx, DOC_SELECTIONS_MAX
    call doc_selections_set
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov r12, rax
    # Aggregate bounds must be checked before reading this intentionally inaccessible payload.
    mov rdi, rbx
    mov esi, 1
    mov edx, DOC_MULTI_BYTES_MAX / DOC_SELECTIONS_MAX + 1
    call doc_selections_replace
    test eax, eax
    jnz failed
    cmp edx, 2
    jne failed
    mov rdi, rbx
    mov rsi, r12
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
failed:
    lea rdi, [rip + fail]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r13
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
ok: .asciz "ok document multiple edits\n"
fail: .asciz "failed document multiple edits case "
letter: .ascii "X"
bad_utf8: .byte 0xff
errors:
    .quad 0,1,1
    .quad bad_utf8,1,1
    .quad letter,DOC_MULTI_BYTES_MAX+1,2
    .quad letter,-2,2
    .quad 0,-1,0
abcdef: .ascii "abcdef"
order_pairs: .quad 5,4, 1,0, 3,2
unicode: .ascii "aéz"
unicode_pairs: .quad 3,1, 0,0
noop_pairs: .quad 3,3, 3,3, 3,3
outer_text: .ascii "XXbXdXfX"
outer_pairs: .quad 6,6, 2,2, 4,4
vectors:
    # Source, source length, original pairs/count, payload/length, result/pairs/count.
    .quad vec0_text,6,vec0_pairs,3,vec0_insert,1,vec0_result,6,vec0_after,3
    .quad vec1_text,6,vec1_pairs,3,vec1_insert,2,vec1_result,9,vec1_after,3
    .quad vec2_text,6,vec2_pairs,2,vec2_insert,1,vec2_result,2,vec2_after,1
    .quad vec3_text,6,vec3_pairs,2,vec3_insert,1,vec3_result,4,vec3_after,2
    .quad vec4_text,6,vec4_pairs,2,vec4_insert,1,vec4_result,5,vec4_after,1
    .quad vec5_text,6,vec5_pairs,3,vec5_insert,1,vec5_result,1,vec5_after,1
    .quad vec6_text,6,vec6_pairs,3,vec6_insert,1,vec6_result,7,vec6_after,1
    .quad vec7_text,6,vec7_pairs,3,vec7_insert,0,vec7_result,6,vec7_after,1
    .quad vec8_text,6,vec8_pairs,3,vec8_insert,0,vec8_result,3,vec8_after,3
    .quad vec9_text,4,vec9_pairs,2,vec9_insert,2,vec9_result,6,vec9_after,2
    .quad vec10_text,0,vec10_pairs,2,vec10_insert,2,vec10_result,2,vec10_after,1
    .quad vec11_text,6,vec11_pairs,1,vec11_insert,0,vec11_result,0,vec11_after,1
    .quad vec12_text,6,vec12_pairs,2,vec12_insert,1,vec12_result,8,vec12_after,2
    .quad alias_text,6000,alias_pairs,2,0,6000,alias_result,18000,alias_after,2
    .quad max_text,512,max_pairs,512,letter,1,max_result,1024,max_after,512
    .quad 0,0,0,0,0,0,0,0,0,0
vec0_text: .ascii "abcdef"
vec0_insert: .ascii "X"
vec0_result: .ascii "XbXdXf"
vec0_pairs: .quad 5, 4, 1, 0, 3, 2
vec0_after: .quad 5, 5, 1, 1, 3, 3
vec1_text: .ascii "abcdef"
vec1_insert: .ascii "Ω"
vec1_result: .ascii "ΩbΩdΩf"
vec1_pairs: .quad 5, 4, 1, 0, 3, 2
vec1_after: .quad 8, 8, 2, 2, 5, 5
vec2_text: .ascii "abcdef"
vec2_insert: .ascii "X"
vec2_result: .ascii "Xf"
vec2_pairs: .quad 3, 0, 2, 5
vec2_after: .quad 1, 1
vec3_text: .ascii "abcdef"
vec3_insert: .ascii "X"
vec3_result: .ascii "XXef"
vec3_pairs: .quad 2, 0, 4, 2
vec3_after: .quad 1, 1, 2, 2
vec4_text: .ascii "abcdef"
vec4_insert: .ascii "X"
vec4_result: .ascii "Xcdef"
vec4_pairs: .quad 2, 2, 2, 0
vec4_after: .quad 1, 1
vec5_text: .ascii "abcdef"
vec5_insert: .ascii "X"
vec5_result: .ascii "X"
vec5_pairs: .quad 0, 2, 4, 6, 1, 5
vec5_after: .quad 1, 1
vec6_text: .ascii "abcdef"
vec6_insert: .ascii "X"
vec6_result: .ascii "abcXdef"
vec6_pairs: .quad 3, 3, 3, 3, 3, 3
vec6_after: .quad 4, 4
vec7_text: .ascii "abcdef"
vec7_insert: .ascii ""
vec7_result: .ascii "abcdef"
vec7_pairs: .quad 3, 3, 3, 3, 3, 3
vec7_after: .quad 3, 3
vec8_text: .ascii "abcdef"
vec8_insert: .ascii ""
vec8_result: .ascii "bdf"
vec8_pairs: .quad 5, 4, 1, 0, 3, 2
vec8_after: .quad 2, 2, 0, 0, 1, 1
vec9_text: .ascii "aéz"
vec9_insert: .ascii "β"
vec9_result: .ascii "βaβz"
vec9_pairs: .quad 3, 1, 0, 0
vec9_after: .quad 5, 5, 2, 2
vec10_text: .ascii ""
vec10_insert: .ascii "Ω"
vec10_result: .ascii "Ω"
vec10_pairs: .quad 0, 0, 0, 0
vec10_after: .quad 2, 2
vec11_text: .ascii "abcdef"
vec11_insert: .ascii ""
vec11_result: .ascii ""
vec11_pairs: .quad 6, 0
vec11_after: .quad 0, 0
vec12_text: .ascii "abcdef"
vec12_insert: .ascii "X"
vec12_result: .ascii "XabcdefX"
vec12_pairs: .quad 0, 0, 6, 6
vec12_after: .quad 1, 1, 8, 8
alias_text: .zero 6000,97
alias_pairs: .quad 0,0, 6000,6000
alias_result: .zero 18000,97
alias_after: .quad 6000,6000, 18000,18000
max_text: .zero 512,97
max_result: .ascii "XaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXa"
max_pairs:
    .quad 0,0
    .quad 1,1
    .quad 2,2
    .quad 3,3
    .quad 4,4
    .quad 5,5
    .quad 6,6
    .quad 7,7
    .quad 8,8
    .quad 9,9
    .quad 10,10
    .quad 11,11
    .quad 12,12
    .quad 13,13
    .quad 14,14
    .quad 15,15
    .quad 16,16
    .quad 17,17
    .quad 18,18
    .quad 19,19
    .quad 20,20
    .quad 21,21
    .quad 22,22
    .quad 23,23
    .quad 24,24
    .quad 25,25
    .quad 26,26
    .quad 27,27
    .quad 28,28
    .quad 29,29
    .quad 30,30
    .quad 31,31
    .quad 32,32
    .quad 33,33
    .quad 34,34
    .quad 35,35
    .quad 36,36
    .quad 37,37
    .quad 38,38
    .quad 39,39
    .quad 40,40
    .quad 41,41
    .quad 42,42
    .quad 43,43
    .quad 44,44
    .quad 45,45
    .quad 46,46
    .quad 47,47
    .quad 48,48
    .quad 49,49
    .quad 50,50
    .quad 51,51
    .quad 52,52
    .quad 53,53
    .quad 54,54
    .quad 55,55
    .quad 56,56
    .quad 57,57
    .quad 58,58
    .quad 59,59
    .quad 60,60
    .quad 61,61
    .quad 62,62
    .quad 63,63
    .quad 64,64
    .quad 65,65
    .quad 66,66
    .quad 67,67
    .quad 68,68
    .quad 69,69
    .quad 70,70
    .quad 71,71
    .quad 72,72
    .quad 73,73
    .quad 74,74
    .quad 75,75
    .quad 76,76
    .quad 77,77
    .quad 78,78
    .quad 79,79
    .quad 80,80
    .quad 81,81
    .quad 82,82
    .quad 83,83
    .quad 84,84
    .quad 85,85
    .quad 86,86
    .quad 87,87
    .quad 88,88
    .quad 89,89
    .quad 90,90
    .quad 91,91
    .quad 92,92
    .quad 93,93
    .quad 94,94
    .quad 95,95
    .quad 96,96
    .quad 97,97
    .quad 98,98
    .quad 99,99
    .quad 100,100
    .quad 101,101
    .quad 102,102
    .quad 103,103
    .quad 104,104
    .quad 105,105
    .quad 106,106
    .quad 107,107
    .quad 108,108
    .quad 109,109
    .quad 110,110
    .quad 111,111
    .quad 112,112
    .quad 113,113
    .quad 114,114
    .quad 115,115
    .quad 116,116
    .quad 117,117
    .quad 118,118
    .quad 119,119
    .quad 120,120
    .quad 121,121
    .quad 122,122
    .quad 123,123
    .quad 124,124
    .quad 125,125
    .quad 126,126
    .quad 127,127
    .quad 128,128
    .quad 129,129
    .quad 130,130
    .quad 131,131
    .quad 132,132
    .quad 133,133
    .quad 134,134
    .quad 135,135
    .quad 136,136
    .quad 137,137
    .quad 138,138
    .quad 139,139
    .quad 140,140
    .quad 141,141
    .quad 142,142
    .quad 143,143
    .quad 144,144
    .quad 145,145
    .quad 146,146
    .quad 147,147
    .quad 148,148
    .quad 149,149
    .quad 150,150
    .quad 151,151
    .quad 152,152
    .quad 153,153
    .quad 154,154
    .quad 155,155
    .quad 156,156
    .quad 157,157
    .quad 158,158
    .quad 159,159
    .quad 160,160
    .quad 161,161
    .quad 162,162
    .quad 163,163
    .quad 164,164
    .quad 165,165
    .quad 166,166
    .quad 167,167
    .quad 168,168
    .quad 169,169
    .quad 170,170
    .quad 171,171
    .quad 172,172
    .quad 173,173
    .quad 174,174
    .quad 175,175
    .quad 176,176
    .quad 177,177
    .quad 178,178
    .quad 179,179
    .quad 180,180
    .quad 181,181
    .quad 182,182
    .quad 183,183
    .quad 184,184
    .quad 185,185
    .quad 186,186
    .quad 187,187
    .quad 188,188
    .quad 189,189
    .quad 190,190
    .quad 191,191
    .quad 192,192
    .quad 193,193
    .quad 194,194
    .quad 195,195
    .quad 196,196
    .quad 197,197
    .quad 198,198
    .quad 199,199
    .quad 200,200
    .quad 201,201
    .quad 202,202
    .quad 203,203
    .quad 204,204
    .quad 205,205
    .quad 206,206
    .quad 207,207
    .quad 208,208
    .quad 209,209
    .quad 210,210
    .quad 211,211
    .quad 212,212
    .quad 213,213
    .quad 214,214
    .quad 215,215
    .quad 216,216
    .quad 217,217
    .quad 218,218
    .quad 219,219
    .quad 220,220
    .quad 221,221
    .quad 222,222
    .quad 223,223
    .quad 224,224
    .quad 225,225
    .quad 226,226
    .quad 227,227
    .quad 228,228
    .quad 229,229
    .quad 230,230
    .quad 231,231
    .quad 232,232
    .quad 233,233
    .quad 234,234
    .quad 235,235
    .quad 236,236
    .quad 237,237
    .quad 238,238
    .quad 239,239
    .quad 240,240
    .quad 241,241
    .quad 242,242
    .quad 243,243
    .quad 244,244
    .quad 245,245
    .quad 246,246
    .quad 247,247
    .quad 248,248
    .quad 249,249
    .quad 250,250
    .quad 251,251
    .quad 252,252
    .quad 253,253
    .quad 254,254
    .quad 255,255
    .quad 256,256
    .quad 257,257
    .quad 258,258
    .quad 259,259
    .quad 260,260
    .quad 261,261
    .quad 262,262
    .quad 263,263
    .quad 264,264
    .quad 265,265
    .quad 266,266
    .quad 267,267
    .quad 268,268
    .quad 269,269
    .quad 270,270
    .quad 271,271
    .quad 272,272
    .quad 273,273
    .quad 274,274
    .quad 275,275
    .quad 276,276
    .quad 277,277
    .quad 278,278
    .quad 279,279
    .quad 280,280
    .quad 281,281
    .quad 282,282
    .quad 283,283
    .quad 284,284
    .quad 285,285
    .quad 286,286
    .quad 287,287
    .quad 288,288
    .quad 289,289
    .quad 290,290
    .quad 291,291
    .quad 292,292
    .quad 293,293
    .quad 294,294
    .quad 295,295
    .quad 296,296
    .quad 297,297
    .quad 298,298
    .quad 299,299
    .quad 300,300
    .quad 301,301
    .quad 302,302
    .quad 303,303
    .quad 304,304
    .quad 305,305
    .quad 306,306
    .quad 307,307
    .quad 308,308
    .quad 309,309
    .quad 310,310
    .quad 311,311
    .quad 312,312
    .quad 313,313
    .quad 314,314
    .quad 315,315
    .quad 316,316
    .quad 317,317
    .quad 318,318
    .quad 319,319
    .quad 320,320
    .quad 321,321
    .quad 322,322
    .quad 323,323
    .quad 324,324
    .quad 325,325
    .quad 326,326
    .quad 327,327
    .quad 328,328
    .quad 329,329
    .quad 330,330
    .quad 331,331
    .quad 332,332
    .quad 333,333
    .quad 334,334
    .quad 335,335
    .quad 336,336
    .quad 337,337
    .quad 338,338
    .quad 339,339
    .quad 340,340
    .quad 341,341
    .quad 342,342
    .quad 343,343
    .quad 344,344
    .quad 345,345
    .quad 346,346
    .quad 347,347
    .quad 348,348
    .quad 349,349
    .quad 350,350
    .quad 351,351
    .quad 352,352
    .quad 353,353
    .quad 354,354
    .quad 355,355
    .quad 356,356
    .quad 357,357
    .quad 358,358
    .quad 359,359
    .quad 360,360
    .quad 361,361
    .quad 362,362
    .quad 363,363
    .quad 364,364
    .quad 365,365
    .quad 366,366
    .quad 367,367
    .quad 368,368
    .quad 369,369
    .quad 370,370
    .quad 371,371
    .quad 372,372
    .quad 373,373
    .quad 374,374
    .quad 375,375
    .quad 376,376
    .quad 377,377
    .quad 378,378
    .quad 379,379
    .quad 380,380
    .quad 381,381
    .quad 382,382
    .quad 383,383
    .quad 384,384
    .quad 385,385
    .quad 386,386
    .quad 387,387
    .quad 388,388
    .quad 389,389
    .quad 390,390
    .quad 391,391
    .quad 392,392
    .quad 393,393
    .quad 394,394
    .quad 395,395
    .quad 396,396
    .quad 397,397
    .quad 398,398
    .quad 399,399
    .quad 400,400
    .quad 401,401
    .quad 402,402
    .quad 403,403
    .quad 404,404
    .quad 405,405
    .quad 406,406
    .quad 407,407
    .quad 408,408
    .quad 409,409
    .quad 410,410
    .quad 411,411
    .quad 412,412
    .quad 413,413
    .quad 414,414
    .quad 415,415
    .quad 416,416
    .quad 417,417
    .quad 418,418
    .quad 419,419
    .quad 420,420
    .quad 421,421
    .quad 422,422
    .quad 423,423
    .quad 424,424
    .quad 425,425
    .quad 426,426
    .quad 427,427
    .quad 428,428
    .quad 429,429
    .quad 430,430
    .quad 431,431
    .quad 432,432
    .quad 433,433
    .quad 434,434
    .quad 435,435
    .quad 436,436
    .quad 437,437
    .quad 438,438
    .quad 439,439
    .quad 440,440
    .quad 441,441
    .quad 442,442
    .quad 443,443
    .quad 444,444
    .quad 445,445
    .quad 446,446
    .quad 447,447
    .quad 448,448
    .quad 449,449
    .quad 450,450
    .quad 451,451
    .quad 452,452
    .quad 453,453
    .quad 454,454
    .quad 455,455
    .quad 456,456
    .quad 457,457
    .quad 458,458
    .quad 459,459
    .quad 460,460
    .quad 461,461
    .quad 462,462
    .quad 463,463
    .quad 464,464
    .quad 465,465
    .quad 466,466
    .quad 467,467
    .quad 468,468
    .quad 469,469
    .quad 470,470
    .quad 471,471
    .quad 472,472
    .quad 473,473
    .quad 474,474
    .quad 475,475
    .quad 476,476
    .quad 477,477
    .quad 478,478
    .quad 479,479
    .quad 480,480
    .quad 481,481
    .quad 482,482
    .quad 483,483
    .quad 484,484
    .quad 485,485
    .quad 486,486
    .quad 487,487
    .quad 488,488
    .quad 489,489
    .quad 490,490
    .quad 491,491
    .quad 492,492
    .quad 493,493
    .quad 494,494
    .quad 495,495
    .quad 496,496
    .quad 497,497
    .quad 498,498
    .quad 499,499
    .quad 500,500
    .quad 501,501
    .quad 502,502
    .quad 503,503
    .quad 504,504
    .quad 505,505
    .quad 506,506
    .quad 507,507
    .quad 508,508
    .quad 509,509
    .quad 510,510
    .quad 511,511
max_after:
    .quad 1,1
    .quad 3,3
    .quad 5,5
    .quad 7,7
    .quad 9,9
    .quad 11,11
    .quad 13,13
    .quad 15,15
    .quad 17,17
    .quad 19,19
    .quad 21,21
    .quad 23,23
    .quad 25,25
    .quad 27,27
    .quad 29,29
    .quad 31,31
    .quad 33,33
    .quad 35,35
    .quad 37,37
    .quad 39,39
    .quad 41,41
    .quad 43,43
    .quad 45,45
    .quad 47,47
    .quad 49,49
    .quad 51,51
    .quad 53,53
    .quad 55,55
    .quad 57,57
    .quad 59,59
    .quad 61,61
    .quad 63,63
    .quad 65,65
    .quad 67,67
    .quad 69,69
    .quad 71,71
    .quad 73,73
    .quad 75,75
    .quad 77,77
    .quad 79,79
    .quad 81,81
    .quad 83,83
    .quad 85,85
    .quad 87,87
    .quad 89,89
    .quad 91,91
    .quad 93,93
    .quad 95,95
    .quad 97,97
    .quad 99,99
    .quad 101,101
    .quad 103,103
    .quad 105,105
    .quad 107,107
    .quad 109,109
    .quad 111,111
    .quad 113,113
    .quad 115,115
    .quad 117,117
    .quad 119,119
    .quad 121,121
    .quad 123,123
    .quad 125,125
    .quad 127,127
    .quad 129,129
    .quad 131,131
    .quad 133,133
    .quad 135,135
    .quad 137,137
    .quad 139,139
    .quad 141,141
    .quad 143,143
    .quad 145,145
    .quad 147,147
    .quad 149,149
    .quad 151,151
    .quad 153,153
    .quad 155,155
    .quad 157,157
    .quad 159,159
    .quad 161,161
    .quad 163,163
    .quad 165,165
    .quad 167,167
    .quad 169,169
    .quad 171,171
    .quad 173,173
    .quad 175,175
    .quad 177,177
    .quad 179,179
    .quad 181,181
    .quad 183,183
    .quad 185,185
    .quad 187,187
    .quad 189,189
    .quad 191,191
    .quad 193,193
    .quad 195,195
    .quad 197,197
    .quad 199,199
    .quad 201,201
    .quad 203,203
    .quad 205,205
    .quad 207,207
    .quad 209,209
    .quad 211,211
    .quad 213,213
    .quad 215,215
    .quad 217,217
    .quad 219,219
    .quad 221,221
    .quad 223,223
    .quad 225,225
    .quad 227,227
    .quad 229,229
    .quad 231,231
    .quad 233,233
    .quad 235,235
    .quad 237,237
    .quad 239,239
    .quad 241,241
    .quad 243,243
    .quad 245,245
    .quad 247,247
    .quad 249,249
    .quad 251,251
    .quad 253,253
    .quad 255,255
    .quad 257,257
    .quad 259,259
    .quad 261,261
    .quad 263,263
    .quad 265,265
    .quad 267,267
    .quad 269,269
    .quad 271,271
    .quad 273,273
    .quad 275,275
    .quad 277,277
    .quad 279,279
    .quad 281,281
    .quad 283,283
    .quad 285,285
    .quad 287,287
    .quad 289,289
    .quad 291,291
    .quad 293,293
    .quad 295,295
    .quad 297,297
    .quad 299,299
    .quad 301,301
    .quad 303,303
    .quad 305,305
    .quad 307,307
    .quad 309,309
    .quad 311,311
    .quad 313,313
    .quad 315,315
    .quad 317,317
    .quad 319,319
    .quad 321,321
    .quad 323,323
    .quad 325,325
    .quad 327,327
    .quad 329,329
    .quad 331,331
    .quad 333,333
    .quad 335,335
    .quad 337,337
    .quad 339,339
    .quad 341,341
    .quad 343,343
    .quad 345,345
    .quad 347,347
    .quad 349,349
    .quad 351,351
    .quad 353,353
    .quad 355,355
    .quad 357,357
    .quad 359,359
    .quad 361,361
    .quad 363,363
    .quad 365,365
    .quad 367,367
    .quad 369,369
    .quad 371,371
    .quad 373,373
    .quad 375,375
    .quad 377,377
    .quad 379,379
    .quad 381,381
    .quad 383,383
    .quad 385,385
    .quad 387,387
    .quad 389,389
    .quad 391,391
    .quad 393,393
    .quad 395,395
    .quad 397,397
    .quad 399,399
    .quad 401,401
    .quad 403,403
    .quad 405,405
    .quad 407,407
    .quad 409,409
    .quad 411,411
    .quad 413,413
    .quad 415,415
    .quad 417,417
    .quad 419,419
    .quad 421,421
    .quad 423,423
    .quad 425,425
    .quad 427,427
    .quad 429,429
    .quad 431,431
    .quad 433,433
    .quad 435,435
    .quad 437,437
    .quad 439,439
    .quad 441,441
    .quad 443,443
    .quad 445,445
    .quad 447,447
    .quad 449,449
    .quad 451,451
    .quad 453,453
    .quad 455,455
    .quad 457,457
    .quad 459,459
    .quad 461,461
    .quad 463,463
    .quad 465,465
    .quad 467,467
    .quad 469,469
    .quad 471,471
    .quad 473,473
    .quad 475,475
    .quad 477,477
    .quad 479,479
    .quad 481,481
    .quad 483,483
    .quad 485,485
    .quad 487,487
    .quad 489,489
    .quad 491,491
    .quad 493,493
    .quad 495,495
    .quad 497,497
    .quad 499,499
    .quad 501,501
    .quad 503,503
    .quad 505,505
    .quad 507,507
    .quad 509,509
    .quad 511,511
    .quad 513,513
    .quad 515,515
    .quad 517,517
    .quad 519,519
    .quad 521,521
    .quad 523,523
    .quad 525,525
    .quad 527,527
    .quad 529,529
    .quad 531,531
    .quad 533,533
    .quad 535,535
    .quad 537,537
    .quad 539,539
    .quad 541,541
    .quad 543,543
    .quad 545,545
    .quad 547,547
    .quad 549,549
    .quad 551,551
    .quad 553,553
    .quad 555,555
    .quad 557,557
    .quad 559,559
    .quad 561,561
    .quad 563,563
    .quad 565,565
    .quad 567,567
    .quad 569,569
    .quad 571,571
    .quad 573,573
    .quad 575,575
    .quad 577,577
    .quad 579,579
    .quad 581,581
    .quad 583,583
    .quad 585,585
    .quad 587,587
    .quad 589,589
    .quad 591,591
    .quad 593,593
    .quad 595,595
    .quad 597,597
    .quad 599,599
    .quad 601,601
    .quad 603,603
    .quad 605,605
    .quad 607,607
    .quad 609,609
    .quad 611,611
    .quad 613,613
    .quad 615,615
    .quad 617,617
    .quad 619,619
    .quad 621,621
    .quad 623,623
    .quad 625,625
    .quad 627,627
    .quad 629,629
    .quad 631,631
    .quad 633,633
    .quad 635,635
    .quad 637,637
    .quad 639,639
    .quad 641,641
    .quad 643,643
    .quad 645,645
    .quad 647,647
    .quad 649,649
    .quad 651,651
    .quad 653,653
    .quad 655,655
    .quad 657,657
    .quad 659,659
    .quad 661,661
    .quad 663,663
    .quad 665,665
    .quad 667,667
    .quad 669,669
    .quad 671,671
    .quad 673,673
    .quad 675,675
    .quad 677,677
    .quad 679,679
    .quad 681,681
    .quad 683,683
    .quad 685,685
    .quad 687,687
    .quad 689,689
    .quad 691,691
    .quad 693,693
    .quad 695,695
    .quad 697,697
    .quad 699,699
    .quad 701,701
    .quad 703,703
    .quad 705,705
    .quad 707,707
    .quad 709,709
    .quad 711,711
    .quad 713,713
    .quad 715,715
    .quad 717,717
    .quad 719,719
    .quad 721,721
    .quad 723,723
    .quad 725,725
    .quad 727,727
    .quad 729,729
    .quad 731,731
    .quad 733,733
    .quad 735,735
    .quad 737,737
    .quad 739,739
    .quad 741,741
    .quad 743,743
    .quad 745,745
    .quad 747,747
    .quad 749,749
    .quad 751,751
    .quad 753,753
    .quad 755,755
    .quad 757,757
    .quad 759,759
    .quad 761,761
    .quad 763,763
    .quad 765,765
    .quad 767,767
    .quad 769,769
    .quad 771,771
    .quad 773,773
    .quad 775,775
    .quad 777,777
    .quad 779,779
    .quad 781,781
    .quad 783,783
    .quad 785,785
    .quad 787,787
    .quad 789,789
    .quad 791,791
    .quad 793,793
    .quad 795,795
    .quad 797,797
    .quad 799,799
    .quad 801,801
    .quad 803,803
    .quad 805,805
    .quad 807,807
    .quad 809,809
    .quad 811,811
    .quad 813,813
    .quad 815,815
    .quad 817,817
    .quad 819,819
    .quad 821,821
    .quad 823,823
    .quad 825,825
    .quad 827,827
    .quad 829,829
    .quad 831,831
    .quad 833,833
    .quad 835,835
    .quad 837,837
    .quad 839,839
    .quad 841,841
    .quad 843,843
    .quad 845,845
    .quad 847,847
    .quad 849,849
    .quad 851,851
    .quad 853,853
    .quad 855,855
    .quad 857,857
    .quad 859,859
    .quad 861,861
    .quad 863,863
    .quad 865,865
    .quad 867,867
    .quad 869,869
    .quad 871,871
    .quad 873,873
    .quad 875,875
    .quad 877,877
    .quad 879,879
    .quad 881,881
    .quad 883,883
    .quad 885,885
    .quad 887,887
    .quad 889,889
    .quad 891,891
    .quad 893,893
    .quad 895,895
    .quad 897,897
    .quad 899,899
    .quad 901,901
    .quad 903,903
    .quad 905,905
    .quad 907,907
    .quad 909,909
    .quad 911,911
    .quad 913,913
    .quad 915,915
    .quad 917,917
    .quad 919,919
    .quad 921,921
    .quad 923,923
    .quad 925,925
    .quad 927,927
    .quad 929,929
    .quad 931,931
    .quad 933,933
    .quad 935,935
    .quad 937,937
    .quad 939,939
    .quad 941,941
    .quad 943,943
    .quad 945,945
    .quad 947,947
    .quad 949,949
    .quad 951,951
    .quad 953,953
    .quad 955,955
    .quad 957,957
    .quad 959,959
    .quad 961,961
    .quad 963,963
    .quad 965,965
    .quad 967,967
    .quad 969,969
    .quad 971,971
    .quad 973,973
    .quad 975,975
    .quad 977,977
    .quad 979,979
    .quad 981,981
    .quad 983,983
    .quad 985,985
    .quad 987,987
    .quad 989,989
    .quad 991,991
    .quad 993,993
    .quad 995,995
    .quad 997,997
    .quad 999,999
    .quad 1001,1001
    .quad 1003,1003
    .quad 1005,1005
    .quad 1007,1007
    .quad 1009,1009
    .quad 1011,1011
    .quad 1013,1013
    .quad 1015,1015
    .quad 1017,1017
    .quad 1019,1019
    .quad 1021,1021
    .quad 1023,1023
