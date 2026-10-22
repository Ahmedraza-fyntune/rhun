.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
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

FN main
    PROLOGUE 64
    mov r15, [rip + g_mem_live]
    lea r12, [rip + vectors]
    mov r13d, 1
.Lcase:
    cmp qword ptr [r12], 0
    je .Lruns
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r12]
    mov rcx, [r12 + 8]
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, [r12 + 8]
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    cmp eax, 1
    jne failed
    mov eax, [r12 + 40]
    mov [rip + cfg_auto_pairs], eax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [r12 + 32]
    call editor_multi_type
    cmp qword ptr [r12 + 80], 0
    je .Lsuccess
    test eax, eax
    jnz failed
    cmp rdx, [r12 + 80]
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    jmp .Lfree
.Lsuccess:
    cmp eax, 1
    jne failed
    test edx, edx
    jnz failed
    mov rdi, rbx
    mov rsi, [r12 + 48]
    mov rdx, [r12 + 56]
    mov rcx, [r12 + 64]
    mov r8, [r12 + 72]
    call check
    test eax, eax
    jz failed
    mov rax, [rbx + DOC_undo + VEC_len]
    cmp rax, [rsp]
    je .Lno_edit
    mov r14d, 3
.Lreplay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12]
    mov rdx, [r12 + 8]
    mov rcx, [r12 + 16]
    mov r8, [r12 + 24]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 48]
    mov rdx, [r12 + 56]
    mov rcx, [r12 + 64]
    mov r8, [r12 + 72]
    call check
    test eax, eax
    jz failed
    dec r14
    jnz .Lreplay
    # Exercise the actual ed_type entry hook as well as its private planner.
    cmp qword ptr [r12 + 24], 1
    jbe .Lfree
    mov rdi, rbx
    call doc_undo
    mov edi, [r12 + 32]
    call ed_type
    mov rdi, rbx
    mov rsi, [r12 + 48]
    mov rdx, [r12 + 56]
    mov rcx, [r12 + 64]
    mov r8, [r12 + 72]
    call check
    test eax, eax
    jz failed
    jmp .Lfree
.Lno_edit:
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
.Lfree:
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 88
    inc r13
    jmp .Lcase
.Lruns:
    mov r13d, 100
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + run_source]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + run_before]
    mov edx, 2
    call doc_selections_set
    mov dword ptr [rip + cfg_auto_pairs], 0
    mov edi, 'x'
    call ed_type
    mov edi, 'y'
    call ed_type
    mov edi, ' '
    call ed_type
    mov edi, 'z'
    call ed_type
    mov r14d, 3
.Lrun_replay:
    mov rdi, rbx
    lea rsi, [rip + run_final]
    mov edx, 9
    lea rcx, [rip + run_final_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + run_word]
    mov edx, 7
    lea rcx, [rip + run_word_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + run_source]
    mov edx, 1
    lea rcx, [rip + run_before]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    mov rdi, rbx
    call doc_redo
    dec r14
    jnz .Lrun_replay
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    xor r12d, r12d
.Lbreak_case:
    lea r13, [r12 + 110]
    call typing_doc
    mov rbx, rax
    mov edi, 'x'
    call ed_type
    test r12, r12
    jnz 1f
    call time_ms
    sub rax, 2000
    mov [rbx + DOC_lastedit], rax
    jmp .Lbreak_type
1:  cmp r12, 1
    jne 2f
    inc qword ptr [rbx + DOC_group]
    jmp .Lbreak_type
2:  lea rsi, [rip + run_shift_pairs]
    cmp r12, 2
    je 3f
    lea rsi, [rip + run_selected_pairs]
3:  mov rdi, rbx
    mov edx, 2
    call doc_selections_set
.Lbreak_type:
    mov edi, 'y'
    call ed_type
    mov rdi, rbx
    call doc_undo
    lea rcx, [rip + run_x_pairs]
    cmp r12, 2
    jb 4f
    lea rcx, [rip + run_shift_pairs]
    je 4f
    lea rcx, [rip + run_selected_pairs]
4:  mov rdi, rbx
    lea rsi, [rip + run_x]
    mov edx, 3
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + run_source]
    mov edx, 1
    lea rcx, [rip + run_before]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r12
    cmp r12, 4
    jb .Lbreak_case
    xor r12d, r12d
.Lsnippet_case:
    lea r13, [r12 + 120]
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + snippet_source]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + snippet_source]
    mov esi, 3
    call snippet_new
    mov r14, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov rcx, r12
    xor r8d, r8d
    call snippet_add
    mov rdi, r14
    call snippet_validate
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call snippet_attach
    mov rdi, rbx
    lea rsi, [rip + snippet_before]
    mov edx, 2
    call doc_selections_set
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 16], rax
    mov dword ptr [rip + cfg_auto_pairs], 1
    mov rdi, rbx
    mov esi, ')'
    call editor_multi_type
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + snippet_source]
    mov edx, 3
    lea rcx, [rip + snippet_after]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rax, [rsp + 16]
    cmp [rbx + DOC_undo + VEC_len], rax
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
    test r12, r12
    jnz 5f
    cmp qword ptr [rbx + DOC_snippet], 0
    jne failed
    jmp 6f
5:  cmp [rbx + DOC_snippet], r14
    jne failed
6:  mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r12
    cmp r12, 2
    jb .Lsnippet_case
    mov r13d, 130
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + ranges_source]
    mov ecx, 4
    xor r8d, r8d
    call doc_insert
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    lea rsi, [rip + ranges_input]
    mov edx, 4
    call doc_ranges_new
    test rax, rax
    jz failed
    mov r14, rax
    cmp qword ptr [rax + DNS_count], 1
    jne failed
    cmp qword ptr [rax + DNS_doclen], 4
    jne failed
    cmp qword ptr [rax + DNS_ranges + DMR_start], 0
    jne failed
    cmp qword ptr [rax + DNS_ranges + DMR_end], 4
    jne failed
    cmp qword ptr [rax + DNS_ranges + DMR_index], 0
    jne failed
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    lea rsi, [rip + ranges_input]
    xor edx, edx
    call doc_ranges_new
    test rax, rax
    jnz failed
    cmp edx, 1
    jne failed
    mov rdi, rbx
    xor esi, esi
    mov edx, 1
    call doc_ranges_new
    test rax, rax
    jnz failed
    cmp edx, 1
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
    mov r13d, 131
    call typing_doc
    mov rbx, rax
    mov dword ptr [rip + cfg_auto_pairs], 1
    # The huge selection ends at a virtual EOF. All other validated positions are zero.
    mov rax, DOC_MULTI_BYTES_MAX + 4095
    mov [rbx + DOC_cap], rax
    mov qword ptr [rbx + DOC_cur], DOC_MULTI_BYTES_MAX
    mov qword ptr [rbx + DOC_anchor], 0
    mov rax, [rbx + DOC_selections]
    mov qword ptr [rax + DMS_DATA + DMP_cur], 0
    mov qword ptr [rax + DMS_DATA + DMP_anchor], 0
    or dword ptr [rbx + DOC_flags], DF_GROUP
    mov qword ptr [rbx + DOC_multilastcp], 'C'
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    mov esi, '('
    call editor_multi_type
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
    mov qword ptr [rbx + DOC_cap], 4096
    mov qword ptr [rbx + DOC_cur], 0
    and dword ptr [rbx + DOC_flags], ~DF_GROUP
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 140
    call doc_new
    mov r14, rax             # document whose view must stay untouched
    call typing_doc
    mov rbx, rax
    mov [rip + g_doc], r14
    mov rdi, r14
    mov esi, DOC_SIZE
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 32], rax
    mov rdi, rbx
    mov esi, 'x'
    call editor_multi_type
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov [rip + g_doc], rbx
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov rdi, rbx
    mov esi, 'x'
    call editor_multi_type
    test eax, eax
    jnz failed
    cmp edx, 3
    jne failed
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 1
    mov rdi, rbx
    mov esi, 'x'
    call editor_multi_type
    test eax, eax
    jnz failed
    cmp edx, 4
    jne failed
    mov qword ptr [rbx + DOC_selectionbatch], 0
    mov rdi, rbx
    mov rsi, [rsp + 32]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 32]
    call mem_free
    mov [rip + g_doc], r14
    mov dword ptr [rip + g_reveal], 777
    mov dword ptr [rip + g_dirty], 0
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    xor ecx, ecx
    call ed_insert
    cmp dword ptr [rip + g_reveal], 777
    jne failed
    cmp dword ptr [rip + g_dirty], 1
    jne failed
    mov rdi, r14
    mov rsi, r12
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, rbx
    lea rsi, [rip + inserted_x]
    mov edx, 3
    lea rcx, [rip + run_x_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov [rip + g_doc], rbx
    mov rdi, rbx
    lea rsi, [rip + pasted]
    mov edx, 2
    xor ecx, ecx
    call ed_insert
    mov rdi, rbx
    lea rsi, [rip + pasted_result]
    mov edx, 7
    lea rcx, [rip + pasted_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + inserted_x]
    mov edx, 3
    lea rcx, [rip + run_x_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    mov rdi, rbx
    lea rsi, [rip + pasted_result]
    mov edx, 7
    lea rcx, [rip + pasted_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call doc_free
    mov rdi, r14
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 150
    call typing_doc
    mov rbx, rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 16], rax
    mov rdi, rbx
    call doc_begin_group
    mov edi, 'x'
    call ed_type
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
    mov rdi, rbx
    mov rsi, [rsp + 16]
    call doc_selections_record_after
    mov r14d, 3
.Louter_replay:
    mov rdi, rbx
    lea rsi, [rip + outer_result]
    mov edx, 4
    lea rcx, [rip + outer_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + run_source]
    mov edx, 1
    lea rcx, [rip + run_before]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    dec r14
    jnz .Louter_replay
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
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

# A small active document with two cursors and no automatic pairs.
typing_doc:
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + run_source]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + run_before]
    mov edx, 2
    call doc_selections_set
    mov dword ptr [rip + cfg_auto_pairs], 0
    mov rax, rbx
    EPILOGUE
.section .rodata
ok: .asciz "ok editor multiple typing\n"
fail: .asciz "failed editor multiple typing case "
letter: .ascii "X"
run_source: .ascii " "
run_before: .quad 0,0, 1,1
run_word: .ascii "xy  xy "
run_word_pairs: .quad 3,3, 7,7
run_final: .ascii "xy z xy z"
run_final_pairs: .quad 4,4, 9,9
run_x: .ascii "x x"
run_x_pairs: .quad 1,1, 3,3
run_shift_pairs: .quad 0,0, 2,2
run_selected_pairs: .quad 1,0, 3,2
snippet_source: .ascii ") )"
snippet_before: .quad 0,0, 2,2
snippet_after: .quad 1,1, 3,3
ranges_source: .ascii "abcd"
ranges_input: .quad 2,0, 4,2, 3,1, 4,4
inserted_x: .ascii "X X"
pasted: .ascii "ZZ"
pasted_result: .ascii "XZZ XZZ"
pasted_pairs: .quad 3,3, 7,7
outer_result: .ascii "Xx x"
outer_pairs: .quad 2,2, 4,4
vectors:
    .quad vec0_source,5,vec0_before,2,937,1,vec0_result,6,vec0_after,2,0
    .quad vec1_source,5,vec1_before,2,40,1,vec1_result,9,vec1_after,2,0
    .quad vec2_source,2,vec2_before,2,40,1,vec2_result,6,vec2_after,2,0
    .quad vec3_source,2,vec3_before,2,40,1,vec3_result,5,vec3_after,2,0
    .quad vec4_source,3,vec4_before,2,41,1,vec4_result,4,vec4_after,2,0
    .quad vec5_source,2,vec5_before,2,34,1,vec5_result,4,vec5_after,2,0
    .quad vec6_source,3,vec6_before,2,34,1,vec6_result,5,vec6_after,2,0
    .quad vec7_source,2,vec7_before,2,34,1,vec7_result,5,vec7_after,2,0
    .quad vec8_source,2,vec8_before,2,34,1,vec8_result,4,vec8_after,2,0
    .quad vec9_source,3,vec9_before,2,34,1,vec9_result,6,vec9_after,2,0
    .quad vec10_source,1,vec10_before,2,40,1,vec10_result,5,vec10_after,2,0
    .quad vec11_source,2,vec11_before,2,40,1,vec11_result,6,vec11_after,2,0
    .quad vec12_source,1,vec12_before,2,91,1,vec12_result,5,vec12_after,2,0
    .quad vec13_source,2,vec13_before,2,91,1,vec13_result,6,vec13_after,2,0
    .quad vec14_source,1,vec14_before,2,123,1,vec14_result,5,vec14_after,2,0
    .quad vec15_source,2,vec15_before,2,123,1,vec15_result,6,vec15_after,2,0
    .quad vec16_source,1,vec16_before,2,34,1,vec16_result,5,vec16_after,2,0
    .quad vec17_source,2,vec17_before,2,34,1,vec17_result,6,vec17_after,2,0
    .quad vec18_source,1,vec18_before,2,39,1,vec18_result,5,vec18_after,2,0
    .quad vec19_source,2,vec19_before,2,39,1,vec19_result,6,vec19_after,2,0
    .quad vec20_source,1,vec20_before,2,96,1,vec20_result,5,vec20_after,2,0
    .quad vec21_source,2,vec21_before,2,96,1,vec21_result,6,vec21_after,2,0
    .quad vec22_source,3,vec22_before,2,41,1,vec22_result,3,vec22_after,2,0
    .quad vec23_source,3,vec23_before,2,93,1,vec23_result,3,vec23_after,2,0
    .quad vec24_source,3,vec24_before,2,125,1,vec24_result,3,vec24_after,2,0
    .quad vec25_source,3,vec25_before,2,34,1,vec25_result,3,vec25_after,2,0
    .quad vec26_source,3,vec26_before,2,39,1,vec26_result,3,vec26_after,2,0
    .quad vec27_source,3,vec27_before,2,96,1,vec27_result,3,vec27_after,2,0
    .quad vec28_source,1,vec28_before,2,40,1,vec28_result,5,vec28_after,2,0
    .quad vec29_source,1,vec29_before,2,40,1,vec29_result,5,vec29_after,2,0
    .quad vec30_source,1,vec30_before,2,40,1,vec30_result,5,vec30_after,2,0
    .quad vec31_source,1,vec31_before,2,40,1,vec31_result,5,vec31_after,2,0
    .quad vec32_source,1,vec32_before,2,40,1,vec32_result,5,vec32_after,2,0
    .quad vec33_source,1,vec33_before,2,40,1,vec33_result,5,vec33_after,2,0
    .quad vec34_source,1,vec34_before,2,40,1,vec34_result,5,vec34_after,2,0
    .quad vec35_source,1,vec35_before,2,40,1,vec35_result,5,vec35_after,2,0
    .quad vec36_source,1,vec36_before,2,40,1,vec36_result,4,vec36_after,2,0
    .quad vec37_source,1,vec37_before,2,40,1,vec37_result,4,vec37_after,2,0
    .quad vec38_source,1,vec38_before,2,40,1,vec38_result,4,vec38_after,2,0
    .quad vec39_source,1,vec39_before,2,40,1,vec39_result,4,vec39_after,2,0
    .quad vec40_source,3,vec40_before,2,41,0,vec40_result,5,vec40_after,2,0
    .quad vec41_source,1,vec41_before,2,40,0,vec41_result,3,vec41_after,2,0
    .quad vec42_source,2,vec42_before,2,946,1,vec42_result,4,vec42_after,1,0
    .quad vec43_source,4,vec43_before,2,40,1,vec43_result,6,vec43_after,1,0
    .quad vec44_source,0,vec44_before,2,40,1,vec44_result,2,vec44_after,1,0
    .quad vec45_source,1,vec45_before,2,65536,1,vec45_result,9,vec45_after,2,0
    .quad vec46_source,1,vec46_before,2,0,1,vec46_result,3,vec46_after,2,0
    .quad vec47_source,1,vec47_before,2,55296,1,vec47_result,1,vec47_after,2,1
    .quad vec48_source,1,vec48_before,2,57343,1,vec48_result,1,vec48_after,2,1
    .quad vec49_source,1,vec49_before,2,1114112,1,vec49_result,1,vec49_after,2,1
    .quad vec50_source,1,vec50_before,2,-1,1,vec50_result,1,vec50_after,2,1
    .quad vec51_source,1,vec51_before,2,40,1,vec51_result,1,vec51_after,2,1
    .quad max_source,512,max_before,512,937,1,max_result,1536,max_after,512,0
    .quad 0,0,0,0,0,0,0,0,0,0,0
vec0_source: .ascii "ab cd"
vec0_result: .ascii "Ωb Ω"
vec0_before: .quad 1,0,5,3
vec0_after: .quad 2,2,6,6
vec1_source: .ascii "ab cd"
vec1_result: .ascii "(ab) (cd)"
vec1_before: .quad 0,2,5,3
vec1_after: .quad 1,3,8,6
vec2_source: .ascii "ab"
vec2_result: .ascii "(a)(b)"
vec2_before: .quad 1,0,2,1
vec2_after: .quad 2,1,5,4
vec3_source: .ascii "ab"
vec3_result: .ascii "(ab()"
vec3_before: .quad 0,0,2,2
vec3_after: .quad 1,1,4,4
vec4_source: .ascii ") a"
vec4_result: .ascii ") )a"
vec4_before: .quad 0,0,2,2
vec4_after: .quad 1,1,3,3
vec5_source: .ascii "\" "
vec5_result: .ascii "\" \"\""
vec5_before: .quad 0,0,2,2
vec5_after: .quad 1,1,3,3
vec6_source: .ascii "a b"
vec6_result: .ascii "a\" b\""
vec6_before: .quad 1,1,3,3
vec6_after: .quad 2,2,5,5
vec7_source: .ascii "\" "
vec7_result: .ascii "\"\" \"\""
vec7_before: .quad 1,1,2,2
vec7_after: .quad 2,2,4,4
vec8_source: .ascii "ab"
vec8_result: .ascii "\"ab\""
vec8_before: .quad 0,0,2,2
vec8_after: .quad 1,1,4,4
vec9_source: .ascii "é "
vec9_result: .ascii "é\" \"\""
vec9_before: .quad 2,2,3,3
vec9_after: .quad 3,3,5,5
vec10_source: .ascii " "
vec10_result: .ascii "() ()"
vec10_before: .quad 0,0,1,1
vec10_after: .quad 1,1,4,4
vec11_source: .ascii "ab"
vec11_result: .ascii "(a)(b)"
vec11_before: .quad 1,0,1,2
vec11_after: .quad 2,1,4,5
vec12_source: .ascii " "
vec12_result: .ascii "[] []"
vec12_before: .quad 0,0,1,1
vec12_after: .quad 1,1,4,4
vec13_source: .ascii "ab"
vec13_result: .ascii "[a][b]"
vec13_before: .quad 1,0,1,2
vec13_after: .quad 2,1,4,5
vec14_source: .ascii " "
vec14_result: .ascii "{} {}"
vec14_before: .quad 0,0,1,1
vec14_after: .quad 1,1,4,4
vec15_source: .ascii "ab"
vec15_result: .ascii "{a}{b}"
vec15_before: .quad 1,0,1,2
vec15_after: .quad 2,1,4,5
vec16_source: .ascii " "
vec16_result: .ascii "\"\" \"\""
vec16_before: .quad 0,0,1,1
vec16_after: .quad 1,1,4,4
vec17_source: .ascii "ab"
vec17_result: .ascii "\"a\"\"b\""
vec17_before: .quad 1,0,1,2
vec17_after: .quad 2,1,4,5
vec18_source: .ascii " "
vec18_result: .ascii "'' ''"
vec18_before: .quad 0,0,1,1
vec18_after: .quad 1,1,4,4
vec19_source: .ascii "ab"
vec19_result: .ascii "'a''b'"
vec19_before: .quad 1,0,1,2
vec19_after: .quad 2,1,4,5
vec20_source: .ascii " "
vec20_result: .ascii "`` ``"
vec20_before: .quad 0,0,1,1
vec20_after: .quad 1,1,4,4
vec21_source: .ascii "ab"
vec21_result: .ascii "`a``b`"
vec21_before: .quad 1,0,1,2
vec21_after: .quad 2,1,4,5
vec22_source: .ascii ") )"
vec22_result: .ascii ") )"
vec22_before: .quad 0,0,2,2
vec22_after: .quad 1,1,3,3
vec23_source: .ascii "] ]"
vec23_result: .ascii "] ]"
vec23_before: .quad 0,0,2,2
vec23_after: .quad 1,1,3,3
vec24_source: .ascii "} }"
vec24_result: .ascii "} }"
vec24_before: .quad 0,0,2,2
vec24_after: .quad 1,1,3,3
vec25_source: .ascii "\" \""
vec25_result: .ascii "\" \""
vec25_before: .quad 0,0,2,2
vec25_after: .quad 1,1,3,3
vec26_source: .ascii "' '"
vec26_result: .ascii "' '"
vec26_before: .quad 0,0,2,2
vec26_after: .quad 1,1,3,3
vec27_source: .ascii "` `"
vec27_result: .ascii "` `"
vec27_before: .quad 0,0,2,2
vec27_after: .quad 1,1,3,3
vec28_source: .ascii " "
vec28_result: .ascii "() ()"
vec28_before: .quad 0,0,1,1
vec28_after: .quad 1,1,4,4
vec29_source: .ascii "\t"
vec29_result: .ascii "()\t()"
vec29_before: .quad 0,0,1,1
vec29_after: .quad 1,1,4,4
vec30_source: .ascii "\n"
vec30_result: .ascii "()\n()"
vec30_before: .quad 0,0,1,1
vec30_after: .quad 1,1,4,4
vec31_source: .ascii ")"
vec31_result: .ascii "())()"
vec31_before: .quad 0,0,1,1
vec31_after: .quad 1,1,4,4
vec32_source: .ascii "]"
vec32_result: .ascii "()]()"
vec32_before: .quad 0,0,1,1
vec32_after: .quad 1,1,4,4
vec33_source: .ascii "}"
vec33_result: .ascii "()}()"
vec33_before: .quad 0,0,1,1
vec33_after: .quad 1,1,4,4
vec34_source: .ascii ","
vec34_result: .ascii "(),()"
vec34_before: .quad 0,0,1,1
vec34_after: .quad 1,1,4,4
vec35_source: .ascii ";"
vec35_result: .ascii "();()"
vec35_before: .quad 0,0,1,1
vec35_after: .quad 1,1,4,4
vec36_source: .ascii "a"
vec36_result: .ascii "(a()"
vec36_before: .quad 0,0,1,1
vec36_after: .quad 1,1,3,3
vec37_source: .ascii "("
vec37_result: .ascii "((()"
vec37_before: .quad 0,0,1,1
vec37_after: .quad 1,1,3,3
vec38_source: .ascii "["
vec38_result: .ascii "([()"
vec38_before: .quad 0,0,1,1
vec38_after: .quad 1,1,3,3
vec39_source: .ascii "!"
vec39_result: .ascii "(!()"
vec39_before: .quad 0,0,1,1
vec39_after: .quad 1,1,3,3
vec40_source: .ascii ") )"
vec40_result: .ascii ")) ))"
vec40_before: .quad 0,0,2,2
vec40_after: .quad 1,1,4,4
vec41_source: .ascii " "
vec41_result: .ascii "( ("
vec41_before: .quad 0,0,1,1
vec41_after: .quad 1,1,3,3
vec42_source: .ascii "ab"
vec42_result: .ascii "aβb"
vec42_before: .quad 1,1,1,1
vec42_after: .quad 3,3
vec43_source: .ascii "abcd"
vec43_result: .ascii "(abcd)"
vec43_before: .quad 3,0,2,4
vec43_after: .quad 5,1
vec44_source: .ascii ""
vec44_result: .ascii "()"
vec44_before: .quad 0,0,0,0
vec44_after: .quad 1,1
vec45_source: .ascii " "
vec45_result: .ascii "𐀀 𐀀"
vec45_before: .quad 0,0,1,1
vec45_after: .quad 4,4,9,9
vec46_source: .ascii " "
vec46_result: .byte 0,32,0
vec46_before: .quad 0,0,1,1
vec46_after: .quad 1,1,3,3
vec47_source: .ascii " "
vec47_result: .ascii " "
vec47_before: .quad 0,0,1,1
vec47_after: .quad 0,0,1,1
vec48_source: .ascii " "
vec48_result: .ascii " "
vec48_before: .quad 0,0,1,1
vec48_after: .quad 0,0,1,1
vec49_source: .ascii " "
vec49_result: .ascii " "
vec49_before: .quad 0,0,1,1
vec49_after: .quad 0,0,1,1
vec50_source: .ascii " "
vec50_result: .ascii " "
vec50_before: .quad 0,0,1,1
vec50_after: .quad 0,0,1,1
vec51_source: .byte 255
vec51_result: .byte 255
vec51_before: .quad 1,0,1,1
vec51_after: .quad 1,0,1,1
max_source: .zero 512,97
max_result: .ascii "ΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩaΩa"
max_before:
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
    .quad 2,2
    .quad 5,5
    .quad 8,8
    .quad 11,11
    .quad 14,14
    .quad 17,17
    .quad 20,20
    .quad 23,23
    .quad 26,26
    .quad 29,29
    .quad 32,32
    .quad 35,35
    .quad 38,38
    .quad 41,41
    .quad 44,44
    .quad 47,47
    .quad 50,50
    .quad 53,53
    .quad 56,56
    .quad 59,59
    .quad 62,62
    .quad 65,65
    .quad 68,68
    .quad 71,71
    .quad 74,74
    .quad 77,77
    .quad 80,80
    .quad 83,83
    .quad 86,86
    .quad 89,89
    .quad 92,92
    .quad 95,95
    .quad 98,98
    .quad 101,101
    .quad 104,104
    .quad 107,107
    .quad 110,110
    .quad 113,113
    .quad 116,116
    .quad 119,119
    .quad 122,122
    .quad 125,125
    .quad 128,128
    .quad 131,131
    .quad 134,134
    .quad 137,137
    .quad 140,140
    .quad 143,143
    .quad 146,146
    .quad 149,149
    .quad 152,152
    .quad 155,155
    .quad 158,158
    .quad 161,161
    .quad 164,164
    .quad 167,167
    .quad 170,170
    .quad 173,173
    .quad 176,176
    .quad 179,179
    .quad 182,182
    .quad 185,185
    .quad 188,188
    .quad 191,191
    .quad 194,194
    .quad 197,197
    .quad 200,200
    .quad 203,203
    .quad 206,206
    .quad 209,209
    .quad 212,212
    .quad 215,215
    .quad 218,218
    .quad 221,221
    .quad 224,224
    .quad 227,227
    .quad 230,230
    .quad 233,233
    .quad 236,236
    .quad 239,239
    .quad 242,242
    .quad 245,245
    .quad 248,248
    .quad 251,251
    .quad 254,254
    .quad 257,257
    .quad 260,260
    .quad 263,263
    .quad 266,266
    .quad 269,269
    .quad 272,272
    .quad 275,275
    .quad 278,278
    .quad 281,281
    .quad 284,284
    .quad 287,287
    .quad 290,290
    .quad 293,293
    .quad 296,296
    .quad 299,299
    .quad 302,302
    .quad 305,305
    .quad 308,308
    .quad 311,311
    .quad 314,314
    .quad 317,317
    .quad 320,320
    .quad 323,323
    .quad 326,326
    .quad 329,329
    .quad 332,332
    .quad 335,335
    .quad 338,338
    .quad 341,341
    .quad 344,344
    .quad 347,347
    .quad 350,350
    .quad 353,353
    .quad 356,356
    .quad 359,359
    .quad 362,362
    .quad 365,365
    .quad 368,368
    .quad 371,371
    .quad 374,374
    .quad 377,377
    .quad 380,380
    .quad 383,383
    .quad 386,386
    .quad 389,389
    .quad 392,392
    .quad 395,395
    .quad 398,398
    .quad 401,401
    .quad 404,404
    .quad 407,407
    .quad 410,410
    .quad 413,413
    .quad 416,416
    .quad 419,419
    .quad 422,422
    .quad 425,425
    .quad 428,428
    .quad 431,431
    .quad 434,434
    .quad 437,437
    .quad 440,440
    .quad 443,443
    .quad 446,446
    .quad 449,449
    .quad 452,452
    .quad 455,455
    .quad 458,458
    .quad 461,461
    .quad 464,464
    .quad 467,467
    .quad 470,470
    .quad 473,473
    .quad 476,476
    .quad 479,479
    .quad 482,482
    .quad 485,485
    .quad 488,488
    .quad 491,491
    .quad 494,494
    .quad 497,497
    .quad 500,500
    .quad 503,503
    .quad 506,506
    .quad 509,509
    .quad 512,512
    .quad 515,515
    .quad 518,518
    .quad 521,521
    .quad 524,524
    .quad 527,527
    .quad 530,530
    .quad 533,533
    .quad 536,536
    .quad 539,539
    .quad 542,542
    .quad 545,545
    .quad 548,548
    .quad 551,551
    .quad 554,554
    .quad 557,557
    .quad 560,560
    .quad 563,563
    .quad 566,566
    .quad 569,569
    .quad 572,572
    .quad 575,575
    .quad 578,578
    .quad 581,581
    .quad 584,584
    .quad 587,587
    .quad 590,590
    .quad 593,593
    .quad 596,596
    .quad 599,599
    .quad 602,602
    .quad 605,605
    .quad 608,608
    .quad 611,611
    .quad 614,614
    .quad 617,617
    .quad 620,620
    .quad 623,623
    .quad 626,626
    .quad 629,629
    .quad 632,632
    .quad 635,635
    .quad 638,638
    .quad 641,641
    .quad 644,644
    .quad 647,647
    .quad 650,650
    .quad 653,653
    .quad 656,656
    .quad 659,659
    .quad 662,662
    .quad 665,665
    .quad 668,668
    .quad 671,671
    .quad 674,674
    .quad 677,677
    .quad 680,680
    .quad 683,683
    .quad 686,686
    .quad 689,689
    .quad 692,692
    .quad 695,695
    .quad 698,698
    .quad 701,701
    .quad 704,704
    .quad 707,707
    .quad 710,710
    .quad 713,713
    .quad 716,716
    .quad 719,719
    .quad 722,722
    .quad 725,725
    .quad 728,728
    .quad 731,731
    .quad 734,734
    .quad 737,737
    .quad 740,740
    .quad 743,743
    .quad 746,746
    .quad 749,749
    .quad 752,752
    .quad 755,755
    .quad 758,758
    .quad 761,761
    .quad 764,764
    .quad 767,767
    .quad 770,770
    .quad 773,773
    .quad 776,776
    .quad 779,779
    .quad 782,782
    .quad 785,785
    .quad 788,788
    .quad 791,791
    .quad 794,794
    .quad 797,797
    .quad 800,800
    .quad 803,803
    .quad 806,806
    .quad 809,809
    .quad 812,812
    .quad 815,815
    .quad 818,818
    .quad 821,821
    .quad 824,824
    .quad 827,827
    .quad 830,830
    .quad 833,833
    .quad 836,836
    .quad 839,839
    .quad 842,842
    .quad 845,845
    .quad 848,848
    .quad 851,851
    .quad 854,854
    .quad 857,857
    .quad 860,860
    .quad 863,863
    .quad 866,866
    .quad 869,869
    .quad 872,872
    .quad 875,875
    .quad 878,878
    .quad 881,881
    .quad 884,884
    .quad 887,887
    .quad 890,890
    .quad 893,893
    .quad 896,896
    .quad 899,899
    .quad 902,902
    .quad 905,905
    .quad 908,908
    .quad 911,911
    .quad 914,914
    .quad 917,917
    .quad 920,920
    .quad 923,923
    .quad 926,926
    .quad 929,929
    .quad 932,932
    .quad 935,935
    .quad 938,938
    .quad 941,941
    .quad 944,944
    .quad 947,947
    .quad 950,950
    .quad 953,953
    .quad 956,956
    .quad 959,959
    .quad 962,962
    .quad 965,965
    .quad 968,968
    .quad 971,971
    .quad 974,974
    .quad 977,977
    .quad 980,980
    .quad 983,983
    .quad 986,986
    .quad 989,989
    .quad 992,992
    .quad 995,995
    .quad 998,998
    .quad 1001,1001
    .quad 1004,1004
    .quad 1007,1007
    .quad 1010,1010
    .quad 1013,1013
    .quad 1016,1016
    .quad 1019,1019
    .quad 1022,1022
    .quad 1025,1025
    .quad 1028,1028
    .quad 1031,1031
    .quad 1034,1034
    .quad 1037,1037
    .quad 1040,1040
    .quad 1043,1043
    .quad 1046,1046
    .quad 1049,1049
    .quad 1052,1052
    .quad 1055,1055
    .quad 1058,1058
    .quad 1061,1061
    .quad 1064,1064
    .quad 1067,1067
    .quad 1070,1070
    .quad 1073,1073
    .quad 1076,1076
    .quad 1079,1079
    .quad 1082,1082
    .quad 1085,1085
    .quad 1088,1088
    .quad 1091,1091
    .quad 1094,1094
    .quad 1097,1097
    .quad 1100,1100
    .quad 1103,1103
    .quad 1106,1106
    .quad 1109,1109
    .quad 1112,1112
    .quad 1115,1115
    .quad 1118,1118
    .quad 1121,1121
    .quad 1124,1124
    .quad 1127,1127
    .quad 1130,1130
    .quad 1133,1133
    .quad 1136,1136
    .quad 1139,1139
    .quad 1142,1142
    .quad 1145,1145
    .quad 1148,1148
    .quad 1151,1151
    .quad 1154,1154
    .quad 1157,1157
    .quad 1160,1160
    .quad 1163,1163
    .quad 1166,1166
    .quad 1169,1169
    .quad 1172,1172
    .quad 1175,1175
    .quad 1178,1178
    .quad 1181,1181
    .quad 1184,1184
    .quad 1187,1187
    .quad 1190,1190
    .quad 1193,1193
    .quad 1196,1196
    .quad 1199,1199
    .quad 1202,1202
    .quad 1205,1205
    .quad 1208,1208
    .quad 1211,1211
    .quad 1214,1214
    .quad 1217,1217
    .quad 1220,1220
    .quad 1223,1223
    .quad 1226,1226
    .quad 1229,1229
    .quad 1232,1232
    .quad 1235,1235
    .quad 1238,1238
    .quad 1241,1241
    .quad 1244,1244
    .quad 1247,1247
    .quad 1250,1250
    .quad 1253,1253
    .quad 1256,1256
    .quad 1259,1259
    .quad 1262,1262
    .quad 1265,1265
    .quad 1268,1268
    .quad 1271,1271
    .quad 1274,1274
    .quad 1277,1277
    .quad 1280,1280
    .quad 1283,1283
    .quad 1286,1286
    .quad 1289,1289
    .quad 1292,1292
    .quad 1295,1295
    .quad 1298,1298
    .quad 1301,1301
    .quad 1304,1304
    .quad 1307,1307
    .quad 1310,1310
    .quad 1313,1313
    .quad 1316,1316
    .quad 1319,1319
    .quad 1322,1322
    .quad 1325,1325
    .quad 1328,1328
    .quad 1331,1331
    .quad 1334,1334
    .quad 1337,1337
    .quad 1340,1340
    .quad 1343,1343
    .quad 1346,1346
    .quad 1349,1349
    .quad 1352,1352
    .quad 1355,1355
    .quad 1358,1358
    .quad 1361,1361
    .quad 1364,1364
    .quad 1367,1367
    .quad 1370,1370
    .quad 1373,1373
    .quad 1376,1376
    .quad 1379,1379
    .quad 1382,1382
    .quad 1385,1385
    .quad 1388,1388
    .quad 1391,1391
    .quad 1394,1394
    .quad 1397,1397
    .quad 1400,1400
    .quad 1403,1403
    .quad 1406,1406
    .quad 1409,1409
    .quad 1412,1412
    .quad 1415,1415
    .quad 1418,1418
    .quad 1421,1421
    .quad 1424,1424
    .quad 1427,1427
    .quad 1430,1430
    .quad 1433,1433
    .quad 1436,1436
    .quad 1439,1439
    .quad 1442,1442
    .quad 1445,1445
    .quad 1448,1448
    .quad 1451,1451
    .quad 1454,1454
    .quad 1457,1457
    .quad 1460,1460
    .quad 1463,1463
    .quad 1466,1466
    .quad 1469,1469
    .quad 1472,1472
    .quad 1475,1475
    .quad 1478,1478
    .quad 1481,1481
    .quad 1484,1484
    .quad 1487,1487
    .quad 1490,1490
    .quad 1493,1493
    .quad 1496,1496
    .quad 1499,1499
    .quad 1502,1502
    .quad 1505,1505
    .quad 1508,1508
    .quad 1511,1511
    .quad 1514,1514
    .quad 1517,1517
    .quad 1520,1520
    .quad 1523,1523
    .quad 1526,1526
    .quad 1529,1529
    .quad 1532,1532
    .quad 1535,1535
