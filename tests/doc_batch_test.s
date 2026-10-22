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
    PROLOGUE 80
    mov r15, [rip + g_mem_live]
    lea r12, [rip + vectors]
    mov r13d, 1
.Lcase:
    cmp qword ptr [r12], 0
    je .Ldone
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r12]
    mov rcx, [r12 + 8]
    xor r8d, r8d
    call doc_insert
    # Every preflight runs while redo history and an owned snippet node exist.
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
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov [rsp + 32], rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 24], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, [r12 + 32]
    mov rdx, [r12 + 40]
    mov rcx, [r12 + 64]
    mov r8, [r12 + 72]
    call doc_selections_apply
    cmp qword ptr [r12 + 80], 0
    je .Lsuccess
    test eax, eax
    jnz failed
    cmp rdx, [r12 + 80]
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 16]
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
    cmp qword ptr [rbx + DOC_selectionbatch], 0
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 48]
    mov rdx, [r12 + 56]
    mov rcx, [r12 + 64]
    mov r8, [r12 + 72]
    call check
    test eax, eax
    jz failed
    cmp qword ptr [r12 + 40], 0
    je .Lselection_only
    cmp qword ptr [rbx + DOC_snippet], 0
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 0
    jne failed
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
    jmp .Lfree
.Lselection_only:
    mov rax, [rsp + 32]
    cmp [rbx + DOC_snippet], rax
    jne failed
    mov rax, [rsp + 24]
    cmp [rbx + DOC_undo + VEC_len], rax
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
.Lfree:
    mov rdi, [rsp + 16]
    call mem_free
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 88
    inc r13
    jmp .Lcase
.Ldone:
    mov r13d, 100
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + alias_source]
    mov ecx, 6048
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_contiguous
    mov r14, rax
    # Descriptors, final pairs, and the large payload all borrow the same gap-buffer allocation.
    mov qword ptr [r14 + DBE_start], 0
    mov qword ptr [r14 + DBE_end], 0
    lea rax, [r14 + 48]
    mov [r14 + DBE_text], rax
    mov qword ptr [r14 + DBE_len], 6000
    mov qword ptr [r14 + 32 + DMP_cur], 6000
    mov qword ptr [r14 + 32 + DMP_anchor], 6000
    mov edi, 12048
    call mem_alloc
    mov [rsp + 40], rax
    mov rdi, rax
    mov esi, 97
    mov edx, 6000
    call memset
    mov rdi, [rsp + 40]
    add rdi, 6000
    mov rsi, r14
    mov edx, 6048
    call memcpy
    mov rdi, rbx
    mov rsi, r14
    mov edx, 1
    lea rcx, [r14 + 32]
    mov r8d, 1
    call doc_selections_apply
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 40]
    mov edx, 12048
    lea rcx, [rip + alias_pairs]
    mov r8d, 1
    call check
    test eax, eax
    jz failed
    mov rdi, [rsp + 40]
    call mem_free
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 101
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + borrow_source]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + borrow_before]
    mov edx, 3
    call doc_selections_set
    mov rcx, [rbx + DOC_selections]
    add rcx, DMS_DATA
    mov rdi, rbx
    lea rsi, [rip + borrow_edit]
    mov edx, 1
    mov r8d, 2
    call doc_selections_apply
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + borrow_after]
    mov edx, 4
    lea rcx, [rip + borrow_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    mov r13d, 102
    call doc_new
    mov rbx, rax
    mov rdi, rax
    mov esi, DOC_SIZE
    call mem_dup
    mov r14, rax
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov rdi, rbx
    lea rsi, [rip + borrow_edit]
    mov edx, 1
    lea rcx, [rip + zero_pair]
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 3
    jne failed
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 1
    mov rdi, rbx
    lea rsi, [rip + borrow_edit]
    mov edx, 1
    lea rcx, [rip + zero_pair]
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 4
    jne failed
    mov qword ptr [rbx + DOC_selectionbatch], 0
    # Model a document at the supported size boundary without allocating a terabyte.
    # Its validated offset zero still points to the actual small allocation.
    mov rax, (1 << 40) - 1
    mov [rbx + DOC_cap], rax
    mov qword ptr [rbx + DOC_gs], 1
    mov rdi, rbx
    lea rsi, [rip + borrow_edit]
    mov edx, 1
    lea rcx, [rip + zero_pair]
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 2
    jne failed
    mov qword ptr [rbx + DOC_cap], 4096
    mov qword ptr [rbx + DOC_gs], 0
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov qword ptr [rbx + DOC_cur], 1
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    lea rcx, [rip + zero_pair]
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov qword ptr [rbx + DOC_cur], 0
    mov rdi, rbx
    mov rsi, r14
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    lea rsi, [rip + duplicate_zero_pairs]
    mov edx, 2
    call doc_selections_set
    mov r14, [rbx + DOC_selections]
    mov qword ptr [r14 + DMS_count], DOC_SELECTIONS_MAX
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    lea rcx, [rip + zero_pair]
    mov r8d, 1
    call doc_selections_apply
    test eax, eax
    jnz failed
    cmp edx, 1
    jne failed
    mov qword ptr [r14 + DMS_count], 1
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
ok: .asciz "ok document prepared edits\n"
fail: .asciz "failed document prepared edits case "
letter: .ascii "X"
alias_source: .zero 6048,97
alias_pairs: .quad 6000,6000
borrow_source: .ascii "abc"
borrow_before: .quad 0,0, 1,1, 3,3
borrow_pairs: .quad 1,1, 3,3
borrow_after: .ascii "Xabc"
borrow_edit: .quad 0,0,letter,1
zero_pair: .quad 0,0
duplicate_zero_pairs: .quad 0,0, 0,0
vectors:
    .quad vec0_source,6,vec0_before_pairs,2,vec0_edits,3,vec0_after,8,vec0_after_pairs,2,0
    .quad vec1_source,3,vec1_before_pairs,1,vec1_edits,2,vec1_after,5,vec1_after_pairs,1,0
    .quad vec2_source,4,vec2_before_pairs,2,vec2_edits,2,vec2_after,9,vec2_after_pairs,2,0
    .quad vec3_source,5,vec3_before_pairs,2,vec3_edits,1,vec3_after,6,vec3_after_pairs,2,0
    .quad vec4_source,5,vec4_before_pairs,2,0,0,vec4_after,5,vec4_after_pairs,2,0
    .quad vec5_source,6,vec5_before_pairs,1,vec5_edits,1,vec5_after,4,vec5_after_pairs,1,0
    .quad vec6_source,6,vec6_before_pairs,1,vec6_edits,1,vec6_after,2,vec6_after_pairs,1,0
    .quad vec7_source,2,vec7_before_pairs,1,vec7_edits,2,vec7_after,4,vec7_after_pairs,2,0
    .quad vec8_source,0,vec8_before_pairs,1,vec8_edits,1,vec8_after,2,vec8_after_pairs,1,0
    .quad vec9_source,2,vec9_before_pairs,1,vec9_edits,2,vec9_after,4,vec9_after_pairs,1,1
    .quad vec10_source,2,vec10_before_pairs,1,vec10_edits,2,vec10_after,4,vec10_after_pairs,1,1
    .quad vec11_source,6,vec11_before_pairs,1,vec11_edits,1,vec11_after,4,vec11_after_pairs,1,1
    .quad vec12_source,6,vec12_before_pairs,1,vec12_edits,1,vec12_after,2,vec12_after_pairs,1,1
    .quad vec13_source,3,vec13_before_pairs,1,0,0,vec13_after,3,vec13_after_pairs,1,1
    .quad vec14_source,3,vec14_before_pairs,1,vec14_edits,2,vec14_after,3,vec14_after_pairs,1,1
    .quad vec15_source,3,vec15_before_pairs,1,vec15_edits,2,vec15_after,3,vec15_after_pairs,1,1
    .quad vec16_source,3,vec16_before_pairs,1,vec16_edits,2,vec16_after,3,vec16_after_pairs,1,1
    .quad vec17_source,3,vec17_before_pairs,1,vec17_edits,1,vec17_after,3,vec17_after_pairs,1,1
    .quad vec18_source,3,vec18_before_pairs,1,vec18_edits,1,vec18_after,3,vec18_after_pairs,1,1
    .quad vec19_source,3,vec19_before_pairs,1,vec19_edits,1,vec19_after,3,vec19_after_pairs,1,1
    .quad vec20_source,3,vec20_before_pairs,1,vec20_edits,1,vec20_after,3,vec20_after_pairs,1,1
    .quad vec21_source,3,vec21_before_pairs,1,vec21_edits,1,vec21_after,3,vec21_after_pairs,1,1
    .quad vec22_source,3,vec22_before_pairs,1,vec22_edits,1,vec22_after,3,vec22_after_pairs,1,2
    .quad vec23_source,3,vec23_before_pairs,1,vec23_edits,2,vec23_after,3,vec23_after_pairs,1,2
    .quad vec24_source,3,vec24_before_pairs,1,vec24_edits,1,vec24_after,3,vec24_after_pairs,1,1
    .quad vec25_source,3,vec25_before_pairs,1,vec25_edits,1025,vec25_after,3,vec25_after_pairs,1,2
    .quad vec26_source,3,vec26_before_pairs,1,0,0,vec26_after,3,vec26_after_pairs,513,2
    .quad vec27_source,3,vec27_before_pairs,1,0,0,vec27_after,3,vec27_after_pairs,0,1
    .quad max_source,1024,max_before,512,max_edits,1024,max_after,2048,max_pairs,512,0
    .quad diff0_source,36,diff0_before,2,diff0_edits,5,diff0_after,56,diff0_pairs,1,1
    .quad diff1_source,39,diff1_before,2,diff1_edits,1,diff1_after,19,diff1_pairs,3,0
    .quad diff2_source,10,diff2_before,4,diff2_edits,1,diff2_after,12,diff2_pairs,3,0
    .quad diff3_source,10,diff3_before,3,diff3_edits,6,diff3_after,35,diff3_pairs,3,1
    .quad diff4_source,46,diff4_before,3,0,0,diff4_after,46,diff4_pairs,1,0
    .quad diff5_source,38,diff5_before,1,diff5_edits,2,diff5_after,40,diff5_pairs,2,0
    .quad diff6_source,33,diff6_before,1,diff6_edits,4,diff6_after,54,diff6_pairs,2,1
    .quad diff7_source,23,diff7_before,2,diff7_edits,2,diff7_after,22,diff7_pairs,2,0
    .quad diff8_source,29,diff8_before,1,diff8_edits,6,diff8_after,39,diff8_pairs,1,0
    .quad diff9_source,14,diff9_before,1,diff9_edits,3,diff9_after,25,diff9_pairs,5,1
    .quad diff10_source,44,diff10_before,5,0,0,diff10_after,44,diff10_pairs,3,0
    .quad diff11_source,36,diff11_before,1,diff11_edits,5,diff11_after,44,diff11_pairs,1,0
    .quad diff12_source,12,diff12_before,4,0,0,diff12_after,12,diff12_pairs,1,1
    .quad diff13_source,27,diff13_before,3,0,0,diff13_after,27,diff13_pairs,3,0
    .quad diff14_source,35,diff14_before,1,diff14_edits,5,diff14_after,36,diff14_pairs,2,0
    .quad diff15_source,7,diff15_before,1,diff15_edits,3,diff15_after,28,diff15_pairs,5,1
    .quad diff16_source,28,diff16_before,2,diff16_edits,4,diff16_after,39,diff16_pairs,5,0
    .quad diff17_source,23,diff17_before,5,diff17_edits,5,diff17_after,38,diff17_pairs,1,0
    .quad diff18_source,49,diff18_before,4,diff18_edits,1,diff18_after,49,diff18_pairs,3,1
    .quad diff19_source,33,diff19_before,1,diff19_edits,2,diff19_after,34,diff19_pairs,1,0
    .quad diff20_source,13,diff20_before,4,diff20_edits,4,diff20_after,40,diff20_pairs,1,0
    .quad diff21_source,3,diff21_before,4,diff21_edits,4,diff21_after,21,diff21_pairs,4,1
    .quad diff22_source,26,diff22_before,5,0,0,diff22_after,26,diff22_pairs,3,0
    .quad diff23_source,39,diff23_before,5,diff23_edits,5,diff23_after,57,diff23_pairs,2,0
    .quad diff24_source,28,diff24_before,3,0,0,diff24_after,28,diff24_pairs,2,1
    .quad diff25_source,38,diff25_before,3,diff25_edits,2,diff25_after,41,diff25_pairs,2,0
    .quad diff26_source,32,diff26_before,1,0,0,diff26_after,32,diff26_pairs,5,0
    .quad diff27_source,38,diff27_before,2,0,0,diff27_after,38,diff27_pairs,2,1
    .quad diff28_source,17,diff28_before,1,diff28_edits,2,diff28_after,28,diff28_pairs,4,0
    .quad diff29_source,4,diff29_before,2,diff29_edits,4,diff29_after,18,diff29_pairs,3,0
    .quad diff30_source,3,diff30_before,4,diff30_edits,2,diff30_after,10,diff30_pairs,3,1
    .quad diff31_source,27,diff31_before,2,diff31_edits,3,diff31_after,27,diff31_pairs,2,0
    .quad diff32_source,23,diff32_before,1,diff32_edits,6,diff32_after,56,diff32_pairs,2,0
    .quad diff33_source,17,diff33_before,2,diff33_edits,3,diff33_after,20,diff33_pairs,3,1
    .quad diff34_source,25,diff34_before,4,diff34_edits,2,diff34_after,29,diff34_pairs,4,0
    .quad diff35_source,15,diff35_before,3,0,0,diff35_after,15,diff35_pairs,1,0
    .quad diff36_source,16,diff36_before,4,diff36_edits,6,diff36_after,53,diff36_pairs,4,1
    .quad diff37_source,28,diff37_before,1,0,0,diff37_after,28,diff37_pairs,2,0
    .quad diff38_source,25,diff38_before,5,diff38_edits,1,diff38_after,22,diff38_pairs,2,0
    .quad diff39_source,31,diff39_before,1,diff39_edits,3,diff39_after,32,diff39_pairs,5,1
    .quad diff40_source,7,diff40_before,3,diff40_edits,2,diff40_after,4,diff40_pairs,4,0
    .quad diff41_source,13,diff41_before,5,diff41_edits,3,diff41_after,19,diff41_pairs,3,0
    .quad diff42_source,40,diff42_before,2,diff42_edits,1,diff42_after,37,diff42_pairs,5,1
    .quad diff43_source,16,diff43_before,3,diff43_edits,6,diff43_after,38,diff43_pairs,5,0
    .quad diff44_source,11,diff44_before,2,diff44_edits,6,diff44_after,40,diff44_pairs,2,0
    .quad diff45_source,27,diff45_before,1,diff45_edits,2,diff45_after,29,diff45_pairs,4,1
    .quad diff46_source,38,diff46_before,3,diff46_edits,5,diff46_after,52,diff46_pairs,4,0
    .quad diff47_source,19,diff47_before,3,diff47_edits,5,diff47_after,24,diff47_pairs,5,0
    .quad diff48_source,17,diff48_before,2,diff48_edits,1,diff48_after,18,diff48_pairs,4,1
    .quad diff49_source,10,diff49_before,1,diff49_edits,4,diff49_after,29,diff49_pairs,1,0
    .quad diff50_source,29,diff50_before,5,diff50_edits,6,diff50_after,44,diff50_pairs,5,0
    .quad diff51_source,13,diff51_before,4,diff51_edits,1,diff51_after,16,diff51_pairs,2,1
    .quad diff52_source,26,diff52_before,4,diff52_edits,1,diff52_after,34,diff52_pairs,5,0
    .quad diff53_source,49,diff53_before,2,0,0,diff53_after,49,diff53_pairs,2,0
    .quad diff54_source,28,diff54_before,3,diff54_edits,3,diff54_after,33,diff54_pairs,1,1
    .quad diff55_source,5,diff55_before,2,diff55_edits,1,diff55_after,8,diff55_pairs,4,0
    .quad diff56_source,31,diff56_before,5,diff56_edits,4,diff56_after,40,diff56_pairs,2,0
    .quad diff57_source,29,diff57_before,5,0,0,diff57_after,29,diff57_pairs,3,1
    .quad diff58_source,5,diff58_before,5,diff58_edits,1,diff58_after,4,diff58_pairs,5,0
    .quad diff59_source,13,diff59_before,3,0,0,diff59_after,13,diff59_pairs,5,0
    .quad diff60_source,16,diff60_before,1,diff60_edits,4,diff60_after,16,diff60_pairs,1,1
    .quad diff61_source,17,diff61_before,5,diff61_edits,2,diff61_after,17,diff61_pairs,3,0
    .quad diff62_source,32,diff62_before,2,diff62_edits,5,diff62_after,45,diff62_pairs,3,0
    .quad diff63_source,10,diff63_before,3,diff63_edits,3,diff63_after,13,diff63_pairs,1,1
    .quad diff64_source,26,diff64_before,5,diff64_edits,1,diff64_after,30,diff64_pairs,3,0
    .quad diff65_source,37,diff65_before,1,diff65_edits,2,diff65_after,44,diff65_pairs,4,0
    .quad diff66_source,31,diff66_before,4,diff66_edits,1,diff66_after,29,diff66_pairs,3,1
    .quad diff67_source,26,diff67_before,3,diff67_edits,3,diff67_after,29,diff67_pairs,1,0
    .quad diff68_source,24,diff68_before,2,diff68_edits,1,diff68_after,18,diff68_pairs,2,0
    .quad diff69_source,14,diff69_before,3,diff69_edits,2,diff69_after,20,diff69_pairs,1,1
    .quad diff70_source,6,diff70_before,1,diff70_edits,4,diff70_after,24,diff70_pairs,3,0
    .quad diff71_source,53,diff71_before,3,diff71_edits,2,diff71_after,49,diff71_pairs,4,0
    .quad diff72_source,30,diff72_before,4,diff72_edits,6,diff72_after,47,diff72_pairs,5,1
    .quad diff73_source,33,diff73_before,2,diff73_edits,2,diff73_after,22,diff73_pairs,2,0
    .quad diff74_source,29,diff74_before,2,diff74_edits,3,diff74_after,28,diff74_pairs,4,0
    .quad diff75_source,31,diff75_before,1,0,0,diff75_after,31,diff75_pairs,1,1
    .quad diff76_source,30,diff76_before,4,diff76_edits,6,diff76_after,42,diff76_pairs,2,0
    .quad diff77_source,8,diff77_before,4,diff77_edits,2,diff77_after,10,diff77_pairs,2,0
    .quad diff78_source,14,diff78_before,3,diff78_edits,4,diff78_after,26,diff78_pairs,2,1
    .quad diff79_source,21,diff79_before,4,diff79_edits,2,diff79_after,18,diff79_pairs,2,0
    .quad diff80_source,11,diff80_before,1,diff80_edits,3,diff80_after,13,diff80_pairs,3,0
    .quad diff81_source,15,diff81_before,2,diff81_edits,6,diff81_after,38,diff81_pairs,1,1
    .quad diff82_source,28,diff82_before,4,diff82_edits,2,diff82_after,28,diff82_pairs,1,0
    .quad diff83_source,14,diff83_before,4,0,0,diff83_after,14,diff83_pairs,1,0
    .quad diff84_source,11,diff84_before,3,diff84_edits,6,diff84_after,29,diff84_pairs,2,1
    .quad diff85_source,33,diff85_before,5,diff85_edits,4,diff85_after,37,diff85_pairs,1,0
    .quad diff86_source,50,diff86_before,1,diff86_edits,2,diff86_after,62,diff86_pairs,2,0
    .quad diff87_source,29,diff87_before,1,diff87_edits,6,diff87_after,47,diff87_pairs,5,1
    .quad diff88_source,24,diff88_before,4,0,0,diff88_after,24,diff88_pairs,3,0
    .quad diff89_source,4,diff89_before,2,diff89_edits,5,diff89_after,17,diff89_pairs,2,0
    .quad diff90_source,14,diff90_before,1,diff90_edits,2,diff90_after,25,diff90_pairs,4,1
    .quad diff91_source,24,diff91_before,4,0,0,diff91_after,24,diff91_pairs,5,0
    .quad diff92_source,6,diff92_before,1,0,0,diff92_after,6,diff92_pairs,2,0
    .quad diff93_source,27,diff93_before,1,diff93_edits,5,diff93_after,31,diff93_pairs,4,1
    .quad diff94_source,8,diff94_before,3,diff94_edits,1,diff94_after,5,diff94_pairs,3,0
    .quad diff95_source,5,diff95_before,1,diff95_edits,1,diff95_after,4,diff95_pairs,2,0
    .quad diff96_source,25,diff96_before,5,diff96_edits,3,diff96_after,24,diff96_pairs,3,1
    .quad diff97_source,25,diff97_before,5,diff97_edits,6,diff97_after,42,diff97_pairs,3,0
    .quad diff98_source,32,diff98_before,5,diff98_edits,2,diff98_after,37,diff98_pairs,4,0
    .quad diff99_source,31,diff99_before,2,diff99_edits,5,diff99_after,50,diff99_pairs,5,1
    .quad diff100_source,25,diff100_before,4,diff100_edits,6,diff100_after,55,diff100_pairs,2,0
    .quad diff101_source,24,diff101_before,5,diff101_edits,5,diff101_after,37,diff101_pairs,2,0
    .quad diff102_source,14,diff102_before,2,diff102_edits,5,diff102_after,10,diff102_pairs,2,1
    .quad diff103_source,33,diff103_before,4,diff103_edits,3,diff103_after,18,diff103_pairs,1,0
    .quad diff104_source,35,diff104_before,2,diff104_edits,5,diff104_after,43,diff104_pairs,2,0
    .quad diff105_source,41,diff105_before,5,0,0,diff105_after,41,diff105_pairs,5,1
    .quad diff106_source,29,diff106_before,4,diff106_edits,3,diff106_after,25,diff106_pairs,3,0
    .quad diff107_source,4,diff107_before,3,diff107_edits,3,diff107_after,11,diff107_pairs,3,0
    .quad diff108_source,29,diff108_before,4,diff108_edits,4,diff108_after,39,diff108_pairs,3,1
    .quad diff109_source,12,diff109_before,4,diff109_edits,6,diff109_after,23,diff109_pairs,2,0
    .quad diff110_source,11,diff110_before,5,diff110_edits,2,diff110_after,21,diff110_pairs,1,0
    .quad diff111_source,22,diff111_before,4,diff111_edits,2,diff111_after,24,diff111_pairs,2,1
    .quad diff112_source,36,diff112_before,5,0,0,diff112_after,36,diff112_pairs,2,0
    .quad diff113_source,11,diff113_before,1,diff113_edits,5,diff113_after,26,diff113_pairs,1,0
    .quad diff114_source,44,diff114_before,2,0,0,diff114_after,44,diff114_pairs,5,1
    .quad diff115_source,26,diff115_before,3,diff115_edits,2,diff115_after,26,diff115_pairs,1,0
    .quad diff116_source,21,diff116_before,4,diff116_edits,5,diff116_after,35,diff116_pairs,4,0
    .quad diff117_source,36,diff117_before,2,diff117_edits,4,diff117_after,39,diff117_pairs,3,1
    .quad diff118_source,25,diff118_before,5,diff118_edits,3,diff118_after,26,diff118_pairs,2,0
    .quad diff119_source,19,diff119_before,4,diff119_edits,1,diff119_after,8,diff119_pairs,5,0
    .quad diff120_source,26,diff120_before,5,diff120_edits,5,diff120_after,36,diff120_pairs,4,1
    .quad diff121_source,5,diff121_before,5,diff121_edits,5,diff121_after,23,diff121_pairs,5,0
    .quad diff122_source,29,diff122_before,2,0,0,diff122_after,29,diff122_pairs,2,0
    .quad diff123_source,32,diff123_before,1,diff123_edits,1,diff123_after,33,diff123_pairs,2,1
    .quad diff124_source,42,diff124_before,1,diff124_edits,2,diff124_after,31,diff124_pairs,4,0
    .quad diff125_source,17,diff125_before,4,diff125_edits,2,diff125_after,11,diff125_pairs,5,0
    .quad diff126_source,20,diff126_before,5,diff126_edits,4,diff126_after,24,diff126_pairs,2,1
    .quad diff127_source,12,diff127_before,4,diff127_edits,1,diff127_after,18,diff127_pairs,5,0
    .quad diff128_source,6,diff128_before,1,diff128_edits,2,diff128_after,8,diff128_pairs,5,0
    .quad diff129_source,42,diff129_before,1,0,0,diff129_after,42,diff129_pairs,5,1
    .quad diff130_source,27,diff130_before,5,0,0,diff130_after,27,diff130_pairs,2,0
    .quad diff131_source,37,diff131_before,5,diff131_edits,5,diff131_after,23,diff131_pairs,4,0
    .quad diff132_source,43,diff132_before,2,diff132_edits,3,diff132_after,36,diff132_pairs,5,1
    .quad diff133_source,8,diff133_before,5,diff133_edits,3,diff133_after,22,diff133_pairs,5,0
    .quad diff134_source,18,diff134_before,2,diff134_edits,3,diff134_after,40,diff134_pairs,5,0
    .quad diff135_source,8,diff135_before,2,diff135_edits,6,diff135_after,34,diff135_pairs,1,1
    .quad diff136_source,38,diff136_before,2,diff136_edits,5,diff136_after,31,diff136_pairs,2,0
    .quad diff137_source,15,diff137_before,3,diff137_edits,3,diff137_after,34,diff137_pairs,4,0
    .quad diff138_source,22,diff138_before,1,diff138_edits,3,diff138_after,24,diff138_pairs,3,1
    .quad diff139_source,10,diff139_before,1,diff139_edits,5,diff139_after,34,diff139_pairs,5,0
    .quad diff140_source,14,diff140_before,2,diff140_edits,5,diff140_after,29,diff140_pairs,5,0
    .quad diff141_source,17,diff141_before,3,diff141_edits,4,diff141_after,20,diff141_pairs,5,1
    .quad diff142_source,10,diff142_before,2,diff142_edits,2,diff142_after,11,diff142_pairs,2,0
    .quad diff143_source,30,diff143_before,3,0,0,diff143_after,30,diff143_pairs,1,0
    .quad diff144_source,29,diff144_before,2,0,0,diff144_after,29,diff144_pairs,2,1
    .quad diff145_source,10,diff145_before,2,diff145_edits,2,diff145_after,15,diff145_pairs,2,0
    .quad diff146_source,11,diff146_before,4,diff146_edits,1,diff146_after,6,diff146_pairs,1,0
    .quad diff147_source,28,diff147_before,1,diff147_edits,3,diff147_after,49,diff147_pairs,3,1
    .quad diff148_source,36,diff148_before,1,diff148_edits,5,diff148_after,30,diff148_pairs,2,0
    .quad diff149_source,15,diff149_before,4,diff149_edits,3,diff149_after,19,diff149_pairs,5,0
    .quad diff150_source,14,diff150_before,2,diff150_edits,1,diff150_after,22,diff150_pairs,2,1
    .quad diff151_source,39,diff151_before,5,diff151_edits,5,diff151_after,20,diff151_pairs,2,0
    .quad diff152_source,11,diff152_before,3,diff152_edits,2,diff152_after,31,diff152_pairs,3,0
    .quad diff153_source,30,diff153_before,1,diff153_edits,4,diff153_after,42,diff153_pairs,1,1
    .quad diff154_source,30,diff154_before,4,diff154_edits,5,diff154_after,26,diff154_pairs,1,0
    .quad diff155_source,35,diff155_before,1,0,0,diff155_after,35,diff155_pairs,2,0
    .quad diff156_source,11,diff156_before,5,diff156_edits,4,diff156_after,21,diff156_pairs,3,1
    .quad diff157_source,24,diff157_before,5,diff157_edits,4,diff157_after,28,diff157_pairs,3,0
    .quad diff158_source,3,diff158_before,1,0,0,diff158_after,3,diff158_pairs,1,0
    .quad diff159_source,39,diff159_before,4,diff159_edits,2,diff159_after,32,diff159_pairs,5,1
    .quad diff160_source,4,diff160_before,2,diff160_edits,3,diff160_after,10,diff160_pairs,1,0
    .quad diff161_source,14,diff161_before,3,diff161_edits,6,diff161_after,33,diff161_pairs,1,0
    .quad diff162_source,12,diff162_before,3,diff162_edits,4,diff162_after,24,diff162_pairs,5,1
    .quad diff163_source,21,diff163_before,1,diff163_edits,2,diff163_after,16,diff163_pairs,3,0
    .quad diff164_source,12,diff164_before,5,diff164_edits,5,diff164_after,41,diff164_pairs,2,0
    .quad diff165_source,31,diff165_before,4,diff165_edits,3,diff165_after,27,diff165_pairs,5,1
    .quad diff166_source,38,diff166_before,2,diff166_edits,1,diff166_after,43,diff166_pairs,5,0
    .quad diff167_source,29,diff167_before,4,diff167_edits,4,diff167_after,33,diff167_pairs,5,0
    .quad diff168_source,48,diff168_before,2,0,0,diff168_after,48,diff168_pairs,3,1
    .quad diff169_source,17,diff169_before,2,diff169_edits,4,diff169_after,20,diff169_pairs,5,0
    .quad diff170_source,36,diff170_before,3,diff170_edits,4,diff170_after,41,diff170_pairs,5,0
    .quad diff171_source,41,diff171_before,1,diff171_edits,4,diff171_after,57,diff171_pairs,5,1
    .quad diff172_source,23,diff172_before,5,diff172_edits,3,diff172_after,27,diff172_pairs,3,0
    .quad diff173_source,10,diff173_before,3,diff173_edits,5,diff173_after,31,diff173_pairs,3,0
    .quad diff174_source,18,diff174_before,4,diff174_edits,1,diff174_after,18,diff174_pairs,5,1
    .quad diff175_source,3,diff175_before,4,diff175_edits,1,diff175_after,8,diff175_pairs,3,0
    .quad diff176_source,18,diff176_before,1,0,0,diff176_after,18,diff176_pairs,1,0
    .quad diff177_source,9,diff177_before,3,diff177_edits,4,diff177_after,24,diff177_pairs,1,1
    .quad diff178_source,12,diff178_before,2,diff178_edits,5,diff178_after,32,diff178_pairs,2,0
    .quad diff179_source,42,diff179_before,5,diff179_edits,6,diff179_after,51,diff179_pairs,3,0
    .quad diff180_source,8,diff180_before,2,diff180_edits,6,diff180_after,42,diff180_pairs,5,1
    .quad diff181_source,8,diff181_before,4,diff181_edits,5,diff181_after,27,diff181_pairs,5,0
    .quad diff182_source,45,diff182_before,4,diff182_edits,1,diff182_after,35,diff182_pairs,5,0
    .quad diff183_source,36,diff183_before,4,diff183_edits,5,diff183_after,36,diff183_pairs,3,1
    .quad diff184_source,17,diff184_before,4,0,0,diff184_after,17,diff184_pairs,2,0
    .quad diff185_source,11,diff185_before,2,diff185_edits,6,diff185_after,47,diff185_pairs,1,0
    .quad diff186_source,37,diff186_before,2,diff186_edits,3,diff186_after,24,diff186_pairs,3,1
    .quad diff187_source,11,diff187_before,1,diff187_edits,6,diff187_after,28,diff187_pairs,1,0
    .quad diff188_source,12,diff188_before,3,diff188_edits,6,diff188_after,35,diff188_pairs,3,0
    .quad diff189_source,7,diff189_before,1,diff189_edits,5,diff189_after,14,diff189_pairs,2,1
    .quad diff190_source,38,diff190_before,4,0,0,diff190_after,38,diff190_pairs,3,0
    .quad diff191_source,29,diff191_before,3,0,0,diff191_after,29,diff191_pairs,3,0
    .quad diff192_source,17,diff192_before,2,diff192_edits,3,diff192_after,25,diff192_pairs,1,1
    .quad diff193_source,14,diff193_before,3,diff193_edits,4,diff193_after,18,diff193_pairs,3,0
    .quad diff194_source,6,diff194_before,3,diff194_edits,1,diff194_after,8,diff194_pairs,2,0
    .quad diff195_source,36,diff195_before,4,diff195_edits,6,diff195_after,58,diff195_pairs,4,1
    .quad diff196_source,11,diff196_before,5,diff196_edits,5,diff196_after,33,diff196_pairs,3,0
    .quad diff197_source,22,diff197_before,4,0,0,diff197_after,22,diff197_pairs,2,0
    .quad diff198_source,16,diff198_before,4,diff198_edits,2,diff198_after,20,diff198_pairs,5,1
    .quad diff199_source,12,diff199_before,4,diff199_edits,3,diff199_after,13,diff199_pairs,4,0
    .quad diff200_source,20,diff200_before,4,diff200_edits,3,diff200_after,24,diff200_pairs,4,0
    .quad diff201_source,34,diff201_before,1,0,0,diff201_after,34,diff201_pairs,1,1
    .quad diff202_source,18,diff202_before,2,diff202_edits,6,diff202_after,57,diff202_pairs,2,0
    .quad diff203_source,16,diff203_before,2,diff203_edits,4,diff203_after,25,diff203_pairs,5,0
    .quad diff204_source,9,diff204_before,5,diff204_edits,3,diff204_after,19,diff204_pairs,4,1
    .quad diff205_source,11,diff205_before,5,diff205_edits,1,diff205_after,12,diff205_pairs,5,0
    .quad diff206_source,14,diff206_before,4,0,0,diff206_after,14,diff206_pairs,5,0
    .quad diff207_source,14,diff207_before,4,diff207_edits,4,diff207_after,26,diff207_pairs,4,1
    .quad diff208_source,28,diff208_before,3,diff208_edits,3,diff208_after,30,diff208_pairs,2,0
    .quad diff209_source,35,diff209_before,5,diff209_edits,1,diff209_after,25,diff209_pairs,5,0
    .quad diff210_source,47,diff210_before,4,diff210_edits,5,diff210_after,41,diff210_pairs,1,1
    .quad diff211_source,17,diff211_before,3,diff211_edits,3,diff211_after,23,diff211_pairs,2,0
    .quad diff212_source,19,diff212_before,2,diff212_edits,3,diff212_after,14,diff212_pairs,5,0
    .quad diff213_source,34,diff213_before,4,diff213_edits,1,diff213_after,36,diff213_pairs,3,1
    .quad diff214_source,8,diff214_before,1,diff214_edits,2,diff214_after,14,diff214_pairs,1,0
    .quad diff215_source,23,diff215_before,5,diff215_edits,6,diff215_after,37,diff215_pairs,2,0
    .quad diff216_source,34,diff216_before,2,0,0,diff216_after,34,diff216_pairs,2,1
    .quad diff217_source,40,diff217_before,4,0,0,diff217_after,40,diff217_pairs,1,0
    .quad diff218_source,22,diff218_before,4,diff218_edits,6,diff218_after,56,diff218_pairs,4,0
    .quad diff219_source,43,diff219_before,2,diff219_edits,6,diff219_after,41,diff219_pairs,2,1
    .quad diff220_source,47,diff220_before,1,diff220_edits,1,diff220_after,40,diff220_pairs,3,0
    .quad diff221_source,45,diff221_before,2,diff221_edits,6,diff221_after,54,diff221_pairs,3,0
    .quad diff222_source,20,diff222_before,1,diff222_edits,2,diff222_after,34,diff222_pairs,3,1
    .quad diff223_source,24,diff223_before,1,0,0,diff223_after,24,diff223_pairs,4,0
    .quad diff224_source,30,diff224_before,2,diff224_edits,1,diff224_after,33,diff224_pairs,3,0
    .quad diff225_source,29,diff225_before,4,diff225_edits,5,diff225_after,60,diff225_pairs,3,1
    .quad diff226_source,31,diff226_before,5,diff226_edits,4,diff226_after,33,diff226_pairs,1,0
    .quad diff227_source,41,diff227_before,4,diff227_edits,1,diff227_after,41,diff227_pairs,1,0
    .quad diff228_source,33,diff228_before,2,diff228_edits,1,diff228_after,24,diff228_pairs,3,1
    .quad diff229_source,8,diff229_before,2,diff229_edits,4,diff229_after,21,diff229_pairs,1,0
    .quad diff230_source,22,diff230_before,1,diff230_edits,6,diff230_after,52,diff230_pairs,2,0
    .quad diff231_source,22,diff231_before,5,diff231_edits,2,diff231_after,22,diff231_pairs,4,1
    .quad diff232_source,33,diff232_before,5,0,0,diff232_after,33,diff232_pairs,5,0
    .quad diff233_source,18,diff233_before,2,diff233_edits,5,diff233_after,28,diff233_pairs,4,0
    .quad diff234_source,15,diff234_before,5,diff234_edits,2,diff234_after,15,diff234_pairs,3,1
    .quad diff235_source,10,diff235_before,1,diff235_edits,4,diff235_after,13,diff235_pairs,2,0
    .quad diff236_source,29,diff236_before,4,diff236_edits,4,diff236_after,45,diff236_pairs,4,0
    .quad diff237_source,11,diff237_before,2,diff237_edits,5,diff237_after,28,diff237_pairs,4,1
    .quad diff238_source,13,diff238_before,2,diff238_edits,4,diff238_after,17,diff238_pairs,1,0
    .quad diff239_source,7,diff239_before,5,diff239_edits,3,diff239_after,22,diff239_pairs,1,0
    .quad diff240_source,30,diff240_before,5,diff240_edits,5,diff240_after,36,diff240_pairs,3,1
    .quad diff241_source,20,diff241_before,4,0,0,diff241_after,20,diff241_pairs,4,0
    .quad diff242_source,35,diff242_before,3,diff242_edits,3,diff242_after,11,diff242_pairs,5,0
    .quad diff243_source,9,diff243_before,5,diff243_edits,1,diff243_after,7,diff243_pairs,5,1
    .quad diff244_source,30,diff244_before,2,diff244_edits,5,diff244_after,34,diff244_pairs,5,0
    .quad diff245_source,36,diff245_before,5,diff245_edits,3,diff245_after,50,diff245_pairs,2,0
    .quad diff246_source,49,diff246_before,3,diff246_edits,3,diff246_after,41,diff246_pairs,3,1
    .quad diff247_source,9,diff247_before,1,diff247_edits,5,diff247_after,21,diff247_pairs,5,0
    .quad diff248_source,11,diff248_before,2,diff248_edits,4,diff248_after,38,diff248_pairs,1,0
    .quad diff249_source,27,diff249_before,4,0,0,diff249_after,27,diff249_pairs,5,1
    .quad diff250_source,13,diff250_before,4,diff250_edits,4,diff250_after,15,diff250_pairs,3,0
    .quad diff251_source,53,diff251_before,2,0,0,diff251_after,53,diff251_pairs,4,0
    .quad diff252_source,28,diff252_before,5,diff252_edits,4,diff252_after,46,diff252_pairs,2,1
    .quad diff253_source,19,diff253_before,2,0,0,diff253_after,19,diff253_pairs,2,0
    .quad diff254_source,43,diff254_before,2,diff254_edits,3,diff254_after,42,diff254_pairs,3,0
    .quad diff255_source,21,diff255_before,2,diff255_edits,4,diff255_after,26,diff255_pairs,1,1
    .quad diff256_source,12,diff256_before,1,diff256_edits,1,diff256_after,17,diff256_pairs,5,0
    .quad diff257_source,12,diff257_before,4,diff257_edits,6,diff257_after,36,diff257_pairs,3,0
    .quad diff258_source,5,diff258_before,5,diff258_edits,4,diff258_after,3,diff258_pairs,5,0
    .quad diff259_source,44,diff259_before,2,diff259_edits,3,diff259_after,63,diff259_pairs,4,0
    .quad diff260_source,25,diff260_before,2,diff260_edits,4,diff260_after,29,diff260_pairs,5,0
    .quad diff261_source,18,diff261_before,4,diff261_edits,2,diff261_after,19,diff261_pairs,2,1
    .quad diff262_source,24,diff262_before,1,diff262_edits,1,diff262_after,19,diff262_pairs,3,0
    .quad diff263_source,19,diff263_before,4,diff263_edits,1,diff263_after,18,diff263_pairs,2,0
    .quad diff264_source,26,diff264_before,1,diff264_edits,6,diff264_after,32,diff264_pairs,3,1
    .quad diff265_source,39,diff265_before,4,diff265_edits,3,diff265_after,25,diff265_pairs,3,0
    .quad diff266_source,13,diff266_before,4,0,0,diff266_after,13,diff266_pairs,5,0
    .quad diff267_source,9,diff267_before,4,diff267_edits,1,diff267_after,11,diff267_pairs,2,1
    .quad diff268_source,12,diff268_before,3,diff268_edits,3,diff268_after,21,diff268_pairs,2,0
    .quad diff269_source,44,diff269_before,3,0,0,diff269_after,44,diff269_pairs,4,0
    .quad diff270_source,22,diff270_before,4,diff270_edits,6,diff270_after,43,diff270_pairs,3,1
    .quad diff271_source,13,diff271_before,3,diff271_edits,3,diff271_after,39,diff271_pairs,4,0
    .quad diff272_source,7,diff272_before,5,diff272_edits,3,diff272_after,17,diff272_pairs,2,0
    .quad diff273_source,18,diff273_before,2,0,0,diff273_after,18,diff273_pairs,3,1
    .quad diff274_source,36,diff274_before,4,0,0,diff274_after,36,diff274_pairs,1,0
    .quad diff275_source,36,diff275_before,3,diff275_edits,5,diff275_after,30,diff275_pairs,2,0
    .quad diff276_source,32,diff276_before,4,diff276_edits,2,diff276_after,42,diff276_pairs,3,1
    .quad diff277_source,13,diff277_before,3,diff277_edits,6,diff277_after,45,diff277_pairs,3,0
    .quad diff278_source,35,diff278_before,1,diff278_edits,3,diff278_after,38,diff278_pairs,5,0
    .quad diff279_source,28,diff279_before,1,diff279_edits,2,diff279_after,40,diff279_pairs,5,1
    .quad diff280_source,3,diff280_before,4,diff280_edits,2,diff280_after,11,diff280_pairs,1,0
    .quad diff281_source,11,diff281_before,5,diff281_edits,3,diff281_after,20,diff281_pairs,2,0
    .quad diff282_source,20,diff282_before,3,diff282_edits,6,diff282_after,49,diff282_pairs,5,1
    .quad diff283_source,7,diff283_before,1,0,0,diff283_after,7,diff283_pairs,3,0
    .quad diff284_source,31,diff284_before,4,diff284_edits,5,diff284_after,30,diff284_pairs,5,0
    .quad diff285_source,27,diff285_before,5,diff285_edits,6,diff285_after,28,diff285_pairs,1,1
    .quad diff286_source,39,diff286_before,1,diff286_edits,2,diff286_after,15,diff286_pairs,4,0
    .quad diff287_source,32,diff287_before,4,diff287_edits,6,diff287_after,39,diff287_pairs,5,0
    .quad diff288_source,36,diff288_before,1,0,0,diff288_after,36,diff288_pairs,2,1
    .quad diff289_source,7,diff289_before,2,diff289_edits,5,diff289_after,15,diff289_pairs,4,0
    .quad diff290_source,28,diff290_before,2,0,0,diff290_after,28,diff290_pairs,3,0
    .quad diff291_source,38,diff291_before,2,diff291_edits,2,diff291_after,43,diff291_pairs,3,1
    .quad diff292_source,34,diff292_before,3,diff292_edits,2,diff292_after,25,diff292_pairs,3,0
    .quad diff293_source,19,diff293_before,2,diff293_edits,5,diff293_after,48,diff293_pairs,4,0
    .quad diff294_source,44,diff294_before,4,diff294_edits,1,diff294_after,48,diff294_pairs,3,1
    .quad diff295_source,9,diff295_before,2,diff295_edits,6,diff295_after,26,diff295_pairs,1,0
    .quad diff296_source,30,diff296_before,3,0,0,diff296_after,30,diff296_pairs,4,0
    .quad diff297_source,9,diff297_before,2,diff297_edits,5,diff297_after,29,diff297_pairs,5,1
    .quad diff298_source,29,diff298_before,5,diff298_edits,3,diff298_after,40,diff298_pairs,4,0
    .quad diff299_source,11,diff299_before,5,diff299_edits,2,diff299_after,27,diff299_pairs,1,0
    .quad 0,0,0,0,0,0,0,0,0,0,0
vec0_source: .ascii "abcdef"
vec0_after: .ascii "Ωbdefβ"
vec0_before_pairs: .quad 5,2,1,0
vec0_after_pairs: .quad 8,6,2,0
vec0_payload0: .ascii "Ω"
vec0_payload1: .ascii ""
vec0_payload2: .ascii "β"
vec0_edits:
    .quad 0,1,vec0_payload0,2
    .quad 2,3,vec0_payload1,0
    .quad 6,6,vec0_payload2,2
vec1_source: .ascii "abc"
vec1_after: .ascii "(abc)"
vec1_before_pairs: .quad 3,0
vec1_after_pairs: .quad 4,1
vec1_payload0: .ascii "("
vec1_payload1: .ascii ")"
vec1_edits:
    .quad 0,0,vec1_payload0,1
    .quad 3,3,vec1_payload1,1
vec2_source: .ascii "a\n b"
vec2_after: .ascii "a\n  \n b\n "
vec2_before_pairs: .quad 1,1,4,4
vec2_after_pairs: .quad 4,4,9,9
vec2_payload0: .ascii "\n  "
vec2_payload1: .ascii "\n "
vec2_edits:
    .quad 1,1,vec2_payload0,3
    .quad 4,4,vec2_payload1,2
vec3_source: .ascii "() xy"
vec3_after: .ascii "() xZy"
vec3_before_pairs: .quad 1,1,4,4
vec3_after_pairs: .quad 2,2,5,5
vec3_payload0: .ascii "Z"
vec3_edits:
    .quad 4,4,vec3_payload0,1
vec4_source: .ascii "() xy"
vec4_after: .ascii "() xy"
vec4_before_pairs: .quad 1,1,4,4
vec4_after_pairs: .quad 2,2,5,5
vec4_edits:
vec5_source: .ascii "aéβz"
vec5_after: .ascii "aβz"
vec5_before_pairs: .quad 3,1
vec5_after_pairs: .quad 3,1
vec5_payload0: .ascii ""
vec5_edits:
    .quad 1,3,vec5_payload0,0
vec6_source: .ascii "aéβz"
vec6_after: .ascii "az"
vec6_before_pairs: .quad 3,1
vec6_after_pairs: .quad 1,1
vec6_payload0: .ascii ""
vec6_edits:
    .quad 1,5,vec6_payload0,0
vec7_source: .ascii "ab"
vec7_after: .ascii "Ωβ"
vec7_before_pairs: .quad 1,0
vec7_after_pairs: .quad 2,0,4,4
vec7_payload0: .ascii "Ω"
vec7_payload1: .ascii "β"
vec7_edits:
    .quad 0,1,vec7_payload0,2
    .quad 1,2,vec7_payload1,2
vec8_source: .ascii ""
vec8_after: .ascii "β"
vec8_before_pairs: .quad 0,0
vec8_after_pairs: .quad 2,0
vec8_payload0: .ascii "β"
vec8_edits:
    .quad 0,0,vec8_payload0,2
vec9_source: .ascii "ab"
vec9_after: .ascii "Ωβ"
vec9_before_pairs: .quad 1,0
vec9_after_pairs: .quad 1,1
vec9_payload0: .ascii "Ω"
vec9_payload1: .ascii "β"
vec9_edits:
    .quad 0,1,vec9_payload0,2
    .quad 1,2,vec9_payload1,2
vec10_source: .ascii "ab"
vec10_after: .ascii "Ωβ"
vec10_before_pairs: .quad 1,0
vec10_after_pairs: .quad 3,3
vec10_payload0: .ascii "Ω"
vec10_payload1: .ascii "β"
vec10_edits:
    .quad 0,1,vec10_payload0,2
    .quad 1,2,vec10_payload1,2
vec11_source: .ascii "aéβz"
vec11_after: .ascii "aβz"
vec11_before_pairs: .quad 3,1
vec11_after_pairs: .quad 2,2
vec11_payload0: .ascii ""
vec11_edits:
    .quad 1,3,vec11_payload0,0
vec12_source: .ascii "aéβz"
vec12_after: .ascii "az"
vec12_before_pairs: .quad 3,1
vec12_after_pairs: .quad 3,3
vec12_payload0: .ascii ""
vec12_edits:
    .quad 1,5,vec12_payload0,0
vec13_source: .ascii "abc"
vec13_after: .ascii "abc"
vec13_before_pairs: .quad 1,0
vec13_after_pairs: .quad -1,0
vec13_edits:
vec14_source: .ascii "abc"
vec14_after: .ascii "abc"
vec14_before_pairs: .quad 1,0
vec14_after_pairs: .quad 0,0
vec14_payload0: .ascii "X"
vec14_payload1: .ascii "X"
vec14_edits:
    .quad 0,3,vec14_payload0,1
    .quad 1,3,vec14_payload1,1
vec15_source: .ascii "abc"
vec15_after: .ascii "abc"
vec15_before_pairs: .quad 1,0
vec15_after_pairs: .quad 0,0
vec15_payload0: .ascii "X"
vec15_payload1: .ascii "Y"
vec15_edits:
    .quad 0,0,vec15_payload0,1
    .quad 0,1,vec15_payload1,1
vec16_source: .ascii "abc"
vec16_after: .ascii "abc"
vec16_before_pairs: .quad 1,0
vec16_after_pairs: .quad 0,0
vec16_payload0: .ascii "X"
vec16_payload1: .ascii "X"
vec16_edits:
    .quad 2,3,vec16_payload0,1
    .quad 0,1,vec16_payload1,1
vec17_source: .ascii "abc"
vec17_after: .ascii "abc"
vec17_before_pairs: .quad 1,0
vec17_after_pairs: .quad 0,0
vec17_payload0: .ascii ""
vec17_edits:
    .quad 0,0,vec17_payload0,0
vec18_source: .ascii "abc"
vec18_after: .ascii "abc"
vec18_before_pairs: .quad 1,0
vec18_after_pairs: .quad 0,0
vec18_payload0: .ascii "X"
vec18_edits:
    .quad 3,2,vec18_payload0,1
vec19_source: .ascii "abc"
vec19_after: .ascii "abc"
vec19_before_pairs: .quad 1,0
vec19_after_pairs: .quad 0,0
vec19_payload0: .ascii "X"
vec19_edits:
    .quad 4,4,vec19_payload0,1
vec20_source: .ascii "abc"
vec20_after: .ascii "abc"
vec20_before_pairs: .quad 1,0
vec20_after_pairs: .quad 0,0
vec20_payload0: .byte 255
vec20_edits:
    .quad 0,1,vec20_payload0,1
vec21_source: .ascii "abc"
vec21_after: .ascii "abc"
vec21_before_pairs: .quad 1,0
vec21_after_pairs: .quad 0,0
vec21_edits:
    .quad 0,0,0,1
vec22_source: .ascii "abc"
vec22_after: .ascii "abc"
vec22_before_pairs: .quad 1,0
vec22_after_pairs: .quad 0,0
vec22_edits:
    .quad 0,0,1,67108865
vec23_source: .ascii "abc"
vec23_after: .ascii "abc"
vec23_before_pairs: .quad 1,0
vec23_after_pairs: .quad 0,0
vec23_edits:
    .quad 0,0,1,67108864
    .quad 1,1,1,1
vec24_source: .ascii "aé"
vec24_after: .ascii "aé"
vec24_before_pairs: .quad 3,1
vec24_after_pairs: .quad 0,0
vec24_payload0: .ascii "X"
vec24_edits:
    .quad 1,2,vec24_payload0,1
vec25_source: .ascii "abc"
vec25_after: .ascii "abc"
vec25_before_pairs: .quad 1,0
vec25_after_pairs: .quad 0,0
vec25_edits:
vec26_source: .ascii "abc"
vec26_after: .ascii "abc"
vec26_before_pairs: .quad 1,0
vec26_after_pairs: .quad 0,0
vec26_edits:
vec27_source: .ascii "abc"
vec27_after: .ascii "abc"
vec27_before_pairs: .quad 1,0
vec27_after_pairs: .quad 0,0
vec27_edits:
max_source: .zero 1024,97
max_after: .ascii "XaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXaXa"
max_before:
    .quad 0,0
    .quad 2,2
    .quad 4,4
    .quad 6,6
    .quad 8,8
    .quad 10,10
    .quad 12,12
    .quad 14,14
    .quad 16,16
    .quad 18,18
    .quad 20,20
    .quad 22,22
    .quad 24,24
    .quad 26,26
    .quad 28,28
    .quad 30,30
    .quad 32,32
    .quad 34,34
    .quad 36,36
    .quad 38,38
    .quad 40,40
    .quad 42,42
    .quad 44,44
    .quad 46,46
    .quad 48,48
    .quad 50,50
    .quad 52,52
    .quad 54,54
    .quad 56,56
    .quad 58,58
    .quad 60,60
    .quad 62,62
    .quad 64,64
    .quad 66,66
    .quad 68,68
    .quad 70,70
    .quad 72,72
    .quad 74,74
    .quad 76,76
    .quad 78,78
    .quad 80,80
    .quad 82,82
    .quad 84,84
    .quad 86,86
    .quad 88,88
    .quad 90,90
    .quad 92,92
    .quad 94,94
    .quad 96,96
    .quad 98,98
    .quad 100,100
    .quad 102,102
    .quad 104,104
    .quad 106,106
    .quad 108,108
    .quad 110,110
    .quad 112,112
    .quad 114,114
    .quad 116,116
    .quad 118,118
    .quad 120,120
    .quad 122,122
    .quad 124,124
    .quad 126,126
    .quad 128,128
    .quad 130,130
    .quad 132,132
    .quad 134,134
    .quad 136,136
    .quad 138,138
    .quad 140,140
    .quad 142,142
    .quad 144,144
    .quad 146,146
    .quad 148,148
    .quad 150,150
    .quad 152,152
    .quad 154,154
    .quad 156,156
    .quad 158,158
    .quad 160,160
    .quad 162,162
    .quad 164,164
    .quad 166,166
    .quad 168,168
    .quad 170,170
    .quad 172,172
    .quad 174,174
    .quad 176,176
    .quad 178,178
    .quad 180,180
    .quad 182,182
    .quad 184,184
    .quad 186,186
    .quad 188,188
    .quad 190,190
    .quad 192,192
    .quad 194,194
    .quad 196,196
    .quad 198,198
    .quad 200,200
    .quad 202,202
    .quad 204,204
    .quad 206,206
    .quad 208,208
    .quad 210,210
    .quad 212,212
    .quad 214,214
    .quad 216,216
    .quad 218,218
    .quad 220,220
    .quad 222,222
    .quad 224,224
    .quad 226,226
    .quad 228,228
    .quad 230,230
    .quad 232,232
    .quad 234,234
    .quad 236,236
    .quad 238,238
    .quad 240,240
    .quad 242,242
    .quad 244,244
    .quad 246,246
    .quad 248,248
    .quad 250,250
    .quad 252,252
    .quad 254,254
    .quad 256,256
    .quad 258,258
    .quad 260,260
    .quad 262,262
    .quad 264,264
    .quad 266,266
    .quad 268,268
    .quad 270,270
    .quad 272,272
    .quad 274,274
    .quad 276,276
    .quad 278,278
    .quad 280,280
    .quad 282,282
    .quad 284,284
    .quad 286,286
    .quad 288,288
    .quad 290,290
    .quad 292,292
    .quad 294,294
    .quad 296,296
    .quad 298,298
    .quad 300,300
    .quad 302,302
    .quad 304,304
    .quad 306,306
    .quad 308,308
    .quad 310,310
    .quad 312,312
    .quad 314,314
    .quad 316,316
    .quad 318,318
    .quad 320,320
    .quad 322,322
    .quad 324,324
    .quad 326,326
    .quad 328,328
    .quad 330,330
    .quad 332,332
    .quad 334,334
    .quad 336,336
    .quad 338,338
    .quad 340,340
    .quad 342,342
    .quad 344,344
    .quad 346,346
    .quad 348,348
    .quad 350,350
    .quad 352,352
    .quad 354,354
    .quad 356,356
    .quad 358,358
    .quad 360,360
    .quad 362,362
    .quad 364,364
    .quad 366,366
    .quad 368,368
    .quad 370,370
    .quad 372,372
    .quad 374,374
    .quad 376,376
    .quad 378,378
    .quad 380,380
    .quad 382,382
    .quad 384,384
    .quad 386,386
    .quad 388,388
    .quad 390,390
    .quad 392,392
    .quad 394,394
    .quad 396,396
    .quad 398,398
    .quad 400,400
    .quad 402,402
    .quad 404,404
    .quad 406,406
    .quad 408,408
    .quad 410,410
    .quad 412,412
    .quad 414,414
    .quad 416,416
    .quad 418,418
    .quad 420,420
    .quad 422,422
    .quad 424,424
    .quad 426,426
    .quad 428,428
    .quad 430,430
    .quad 432,432
    .quad 434,434
    .quad 436,436
    .quad 438,438
    .quad 440,440
    .quad 442,442
    .quad 444,444
    .quad 446,446
    .quad 448,448
    .quad 450,450
    .quad 452,452
    .quad 454,454
    .quad 456,456
    .quad 458,458
    .quad 460,460
    .quad 462,462
    .quad 464,464
    .quad 466,466
    .quad 468,468
    .quad 470,470
    .quad 472,472
    .quad 474,474
    .quad 476,476
    .quad 478,478
    .quad 480,480
    .quad 482,482
    .quad 484,484
    .quad 486,486
    .quad 488,488
    .quad 490,490
    .quad 492,492
    .quad 494,494
    .quad 496,496
    .quad 498,498
    .quad 500,500
    .quad 502,502
    .quad 504,504
    .quad 506,506
    .quad 508,508
    .quad 510,510
    .quad 512,512
    .quad 514,514
    .quad 516,516
    .quad 518,518
    .quad 520,520
    .quad 522,522
    .quad 524,524
    .quad 526,526
    .quad 528,528
    .quad 530,530
    .quad 532,532
    .quad 534,534
    .quad 536,536
    .quad 538,538
    .quad 540,540
    .quad 542,542
    .quad 544,544
    .quad 546,546
    .quad 548,548
    .quad 550,550
    .quad 552,552
    .quad 554,554
    .quad 556,556
    .quad 558,558
    .quad 560,560
    .quad 562,562
    .quad 564,564
    .quad 566,566
    .quad 568,568
    .quad 570,570
    .quad 572,572
    .quad 574,574
    .quad 576,576
    .quad 578,578
    .quad 580,580
    .quad 582,582
    .quad 584,584
    .quad 586,586
    .quad 588,588
    .quad 590,590
    .quad 592,592
    .quad 594,594
    .quad 596,596
    .quad 598,598
    .quad 600,600
    .quad 602,602
    .quad 604,604
    .quad 606,606
    .quad 608,608
    .quad 610,610
    .quad 612,612
    .quad 614,614
    .quad 616,616
    .quad 618,618
    .quad 620,620
    .quad 622,622
    .quad 624,624
    .quad 626,626
    .quad 628,628
    .quad 630,630
    .quad 632,632
    .quad 634,634
    .quad 636,636
    .quad 638,638
    .quad 640,640
    .quad 642,642
    .quad 644,644
    .quad 646,646
    .quad 648,648
    .quad 650,650
    .quad 652,652
    .quad 654,654
    .quad 656,656
    .quad 658,658
    .quad 660,660
    .quad 662,662
    .quad 664,664
    .quad 666,666
    .quad 668,668
    .quad 670,670
    .quad 672,672
    .quad 674,674
    .quad 676,676
    .quad 678,678
    .quad 680,680
    .quad 682,682
    .quad 684,684
    .quad 686,686
    .quad 688,688
    .quad 690,690
    .quad 692,692
    .quad 694,694
    .quad 696,696
    .quad 698,698
    .quad 700,700
    .quad 702,702
    .quad 704,704
    .quad 706,706
    .quad 708,708
    .quad 710,710
    .quad 712,712
    .quad 714,714
    .quad 716,716
    .quad 718,718
    .quad 720,720
    .quad 722,722
    .quad 724,724
    .quad 726,726
    .quad 728,728
    .quad 730,730
    .quad 732,732
    .quad 734,734
    .quad 736,736
    .quad 738,738
    .quad 740,740
    .quad 742,742
    .quad 744,744
    .quad 746,746
    .quad 748,748
    .quad 750,750
    .quad 752,752
    .quad 754,754
    .quad 756,756
    .quad 758,758
    .quad 760,760
    .quad 762,762
    .quad 764,764
    .quad 766,766
    .quad 768,768
    .quad 770,770
    .quad 772,772
    .quad 774,774
    .quad 776,776
    .quad 778,778
    .quad 780,780
    .quad 782,782
    .quad 784,784
    .quad 786,786
    .quad 788,788
    .quad 790,790
    .quad 792,792
    .quad 794,794
    .quad 796,796
    .quad 798,798
    .quad 800,800
    .quad 802,802
    .quad 804,804
    .quad 806,806
    .quad 808,808
    .quad 810,810
    .quad 812,812
    .quad 814,814
    .quad 816,816
    .quad 818,818
    .quad 820,820
    .quad 822,822
    .quad 824,824
    .quad 826,826
    .quad 828,828
    .quad 830,830
    .quad 832,832
    .quad 834,834
    .quad 836,836
    .quad 838,838
    .quad 840,840
    .quad 842,842
    .quad 844,844
    .quad 846,846
    .quad 848,848
    .quad 850,850
    .quad 852,852
    .quad 854,854
    .quad 856,856
    .quad 858,858
    .quad 860,860
    .quad 862,862
    .quad 864,864
    .quad 866,866
    .quad 868,868
    .quad 870,870
    .quad 872,872
    .quad 874,874
    .quad 876,876
    .quad 878,878
    .quad 880,880
    .quad 882,882
    .quad 884,884
    .quad 886,886
    .quad 888,888
    .quad 890,890
    .quad 892,892
    .quad 894,894
    .quad 896,896
    .quad 898,898
    .quad 900,900
    .quad 902,902
    .quad 904,904
    .quad 906,906
    .quad 908,908
    .quad 910,910
    .quad 912,912
    .quad 914,914
    .quad 916,916
    .quad 918,918
    .quad 920,920
    .quad 922,922
    .quad 924,924
    .quad 926,926
    .quad 928,928
    .quad 930,930
    .quad 932,932
    .quad 934,934
    .quad 936,936
    .quad 938,938
    .quad 940,940
    .quad 942,942
    .quad 944,944
    .quad 946,946
    .quad 948,948
    .quad 950,950
    .quad 952,952
    .quad 954,954
    .quad 956,956
    .quad 958,958
    .quad 960,960
    .quad 962,962
    .quad 964,964
    .quad 966,966
    .quad 968,968
    .quad 970,970
    .quad 972,972
    .quad 974,974
    .quad 976,976
    .quad 978,978
    .quad 980,980
    .quad 982,982
    .quad 984,984
    .quad 986,986
    .quad 988,988
    .quad 990,990
    .quad 992,992
    .quad 994,994
    .quad 996,996
    .quad 998,998
    .quad 1000,1000
    .quad 1002,1002
    .quad 1004,1004
    .quad 1006,1006
    .quad 1008,1008
    .quad 1010,1010
    .quad 1012,1012
    .quad 1014,1014
    .quad 1016,1016
    .quad 1018,1018
    .quad 1020,1020
    .quad 1022,1022
max_pairs:
    .quad 1,1
    .quad 5,5
    .quad 9,9
    .quad 13,13
    .quad 17,17
    .quad 21,21
    .quad 25,25
    .quad 29,29
    .quad 33,33
    .quad 37,37
    .quad 41,41
    .quad 45,45
    .quad 49,49
    .quad 53,53
    .quad 57,57
    .quad 61,61
    .quad 65,65
    .quad 69,69
    .quad 73,73
    .quad 77,77
    .quad 81,81
    .quad 85,85
    .quad 89,89
    .quad 93,93
    .quad 97,97
    .quad 101,101
    .quad 105,105
    .quad 109,109
    .quad 113,113
    .quad 117,117
    .quad 121,121
    .quad 125,125
    .quad 129,129
    .quad 133,133
    .quad 137,137
    .quad 141,141
    .quad 145,145
    .quad 149,149
    .quad 153,153
    .quad 157,157
    .quad 161,161
    .quad 165,165
    .quad 169,169
    .quad 173,173
    .quad 177,177
    .quad 181,181
    .quad 185,185
    .quad 189,189
    .quad 193,193
    .quad 197,197
    .quad 201,201
    .quad 205,205
    .quad 209,209
    .quad 213,213
    .quad 217,217
    .quad 221,221
    .quad 225,225
    .quad 229,229
    .quad 233,233
    .quad 237,237
    .quad 241,241
    .quad 245,245
    .quad 249,249
    .quad 253,253
    .quad 257,257
    .quad 261,261
    .quad 265,265
    .quad 269,269
    .quad 273,273
    .quad 277,277
    .quad 281,281
    .quad 285,285
    .quad 289,289
    .quad 293,293
    .quad 297,297
    .quad 301,301
    .quad 305,305
    .quad 309,309
    .quad 313,313
    .quad 317,317
    .quad 321,321
    .quad 325,325
    .quad 329,329
    .quad 333,333
    .quad 337,337
    .quad 341,341
    .quad 345,345
    .quad 349,349
    .quad 353,353
    .quad 357,357
    .quad 361,361
    .quad 365,365
    .quad 369,369
    .quad 373,373
    .quad 377,377
    .quad 381,381
    .quad 385,385
    .quad 389,389
    .quad 393,393
    .quad 397,397
    .quad 401,401
    .quad 405,405
    .quad 409,409
    .quad 413,413
    .quad 417,417
    .quad 421,421
    .quad 425,425
    .quad 429,429
    .quad 433,433
    .quad 437,437
    .quad 441,441
    .quad 445,445
    .quad 449,449
    .quad 453,453
    .quad 457,457
    .quad 461,461
    .quad 465,465
    .quad 469,469
    .quad 473,473
    .quad 477,477
    .quad 481,481
    .quad 485,485
    .quad 489,489
    .quad 493,493
    .quad 497,497
    .quad 501,501
    .quad 505,505
    .quad 509,509
    .quad 513,513
    .quad 517,517
    .quad 521,521
    .quad 525,525
    .quad 529,529
    .quad 533,533
    .quad 537,537
    .quad 541,541
    .quad 545,545
    .quad 549,549
    .quad 553,553
    .quad 557,557
    .quad 561,561
    .quad 565,565
    .quad 569,569
    .quad 573,573
    .quad 577,577
    .quad 581,581
    .quad 585,585
    .quad 589,589
    .quad 593,593
    .quad 597,597
    .quad 601,601
    .quad 605,605
    .quad 609,609
    .quad 613,613
    .quad 617,617
    .quad 621,621
    .quad 625,625
    .quad 629,629
    .quad 633,633
    .quad 637,637
    .quad 641,641
    .quad 645,645
    .quad 649,649
    .quad 653,653
    .quad 657,657
    .quad 661,661
    .quad 665,665
    .quad 669,669
    .quad 673,673
    .quad 677,677
    .quad 681,681
    .quad 685,685
    .quad 689,689
    .quad 693,693
    .quad 697,697
    .quad 701,701
    .quad 705,705
    .quad 709,709
    .quad 713,713
    .quad 717,717
    .quad 721,721
    .quad 725,725
    .quad 729,729
    .quad 733,733
    .quad 737,737
    .quad 741,741
    .quad 745,745
    .quad 749,749
    .quad 753,753
    .quad 757,757
    .quad 761,761
    .quad 765,765
    .quad 769,769
    .quad 773,773
    .quad 777,777
    .quad 781,781
    .quad 785,785
    .quad 789,789
    .quad 793,793
    .quad 797,797
    .quad 801,801
    .quad 805,805
    .quad 809,809
    .quad 813,813
    .quad 817,817
    .quad 821,821
    .quad 825,825
    .quad 829,829
    .quad 833,833
    .quad 837,837
    .quad 841,841
    .quad 845,845
    .quad 849,849
    .quad 853,853
    .quad 857,857
    .quad 861,861
    .quad 865,865
    .quad 869,869
    .quad 873,873
    .quad 877,877
    .quad 881,881
    .quad 885,885
    .quad 889,889
    .quad 893,893
    .quad 897,897
    .quad 901,901
    .quad 905,905
    .quad 909,909
    .quad 913,913
    .quad 917,917
    .quad 921,921
    .quad 925,925
    .quad 929,929
    .quad 933,933
    .quad 937,937
    .quad 941,941
    .quad 945,945
    .quad 949,949
    .quad 953,953
    .quad 957,957
    .quad 961,961
    .quad 965,965
    .quad 969,969
    .quad 973,973
    .quad 977,977
    .quad 981,981
    .quad 985,985
    .quad 989,989
    .quad 993,993
    .quad 997,997
    .quad 1001,1001
    .quad 1005,1005
    .quad 1009,1009
    .quad 1013,1013
    .quad 1017,1017
    .quad 1021,1021
    .quad 1025,1025
    .quad 1029,1029
    .quad 1033,1033
    .quad 1037,1037
    .quad 1041,1041
    .quad 1045,1045
    .quad 1049,1049
    .quad 1053,1053
    .quad 1057,1057
    .quad 1061,1061
    .quad 1065,1065
    .quad 1069,1069
    .quad 1073,1073
    .quad 1077,1077
    .quad 1081,1081
    .quad 1085,1085
    .quad 1089,1089
    .quad 1093,1093
    .quad 1097,1097
    .quad 1101,1101
    .quad 1105,1105
    .quad 1109,1109
    .quad 1113,1113
    .quad 1117,1117
    .quad 1121,1121
    .quad 1125,1125
    .quad 1129,1129
    .quad 1133,1133
    .quad 1137,1137
    .quad 1141,1141
    .quad 1145,1145
    .quad 1149,1149
    .quad 1153,1153
    .quad 1157,1157
    .quad 1161,1161
    .quad 1165,1165
    .quad 1169,1169
    .quad 1173,1173
    .quad 1177,1177
    .quad 1181,1181
    .quad 1185,1185
    .quad 1189,1189
    .quad 1193,1193
    .quad 1197,1197
    .quad 1201,1201
    .quad 1205,1205
    .quad 1209,1209
    .quad 1213,1213
    .quad 1217,1217
    .quad 1221,1221
    .quad 1225,1225
    .quad 1229,1229
    .quad 1233,1233
    .quad 1237,1237
    .quad 1241,1241
    .quad 1245,1245
    .quad 1249,1249
    .quad 1253,1253
    .quad 1257,1257
    .quad 1261,1261
    .quad 1265,1265
    .quad 1269,1269
    .quad 1273,1273
    .quad 1277,1277
    .quad 1281,1281
    .quad 1285,1285
    .quad 1289,1289
    .quad 1293,1293
    .quad 1297,1297
    .quad 1301,1301
    .quad 1305,1305
    .quad 1309,1309
    .quad 1313,1313
    .quad 1317,1317
    .quad 1321,1321
    .quad 1325,1325
    .quad 1329,1329
    .quad 1333,1333
    .quad 1337,1337
    .quad 1341,1341
    .quad 1345,1345
    .quad 1349,1349
    .quad 1353,1353
    .quad 1357,1357
    .quad 1361,1361
    .quad 1365,1365
    .quad 1369,1369
    .quad 1373,1373
    .quad 1377,1377
    .quad 1381,1381
    .quad 1385,1385
    .quad 1389,1389
    .quad 1393,1393
    .quad 1397,1397
    .quad 1401,1401
    .quad 1405,1405
    .quad 1409,1409
    .quad 1413,1413
    .quad 1417,1417
    .quad 1421,1421
    .quad 1425,1425
    .quad 1429,1429
    .quad 1433,1433
    .quad 1437,1437
    .quad 1441,1441
    .quad 1445,1445
    .quad 1449,1449
    .quad 1453,1453
    .quad 1457,1457
    .quad 1461,1461
    .quad 1465,1465
    .quad 1469,1469
    .quad 1473,1473
    .quad 1477,1477
    .quad 1481,1481
    .quad 1485,1485
    .quad 1489,1489
    .quad 1493,1493
    .quad 1497,1497
    .quad 1501,1501
    .quad 1505,1505
    .quad 1509,1509
    .quad 1513,1513
    .quad 1517,1517
    .quad 1521,1521
    .quad 1525,1525
    .quad 1529,1529
    .quad 1533,1533
    .quad 1537,1537
    .quad 1541,1541
    .quad 1545,1545
    .quad 1549,1549
    .quad 1553,1553
    .quad 1557,1557
    .quad 1561,1561
    .quad 1565,1565
    .quad 1569,1569
    .quad 1573,1573
    .quad 1577,1577
    .quad 1581,1581
    .quad 1585,1585
    .quad 1589,1589
    .quad 1593,1593
    .quad 1597,1597
    .quad 1601,1601
    .quad 1605,1605
    .quad 1609,1609
    .quad 1613,1613
    .quad 1617,1617
    .quad 1621,1621
    .quad 1625,1625
    .quad 1629,1629
    .quad 1633,1633
    .quad 1637,1637
    .quad 1641,1641
    .quad 1645,1645
    .quad 1649,1649
    .quad 1653,1653
    .quad 1657,1657
    .quad 1661,1661
    .quad 1665,1665
    .quad 1669,1669
    .quad 1673,1673
    .quad 1677,1677
    .quad 1681,1681
    .quad 1685,1685
    .quad 1689,1689
    .quad 1693,1693
    .quad 1697,1697
    .quad 1701,1701
    .quad 1705,1705
    .quad 1709,1709
    .quad 1713,1713
    .quad 1717,1717
    .quad 1721,1721
    .quad 1725,1725
    .quad 1729,1729
    .quad 1733,1733
    .quad 1737,1737
    .quad 1741,1741
    .quad 1745,1745
    .quad 1749,1749
    .quad 1753,1753
    .quad 1757,1757
    .quad 1761,1761
    .quad 1765,1765
    .quad 1769,1769
    .quad 1773,1773
    .quad 1777,1777
    .quad 1781,1781
    .quad 1785,1785
    .quad 1789,1789
    .quad 1793,1793
    .quad 1797,1797
    .quad 1801,1801
    .quad 1805,1805
    .quad 1809,1809
    .quad 1813,1813
    .quad 1817,1817
    .quad 1821,1821
    .quad 1825,1825
    .quad 1829,1829
    .quad 1833,1833
    .quad 1837,1837
    .quad 1841,1841
    .quad 1845,1845
    .quad 1849,1849
    .quad 1853,1853
    .quad 1857,1857
    .quad 1861,1861
    .quad 1865,1865
    .quad 1869,1869
    .quad 1873,1873
    .quad 1877,1877
    .quad 1881,1881
    .quad 1885,1885
    .quad 1889,1889
    .quad 1893,1893
    .quad 1897,1897
    .quad 1901,1901
    .quad 1905,1905
    .quad 1909,1909
    .quad 1913,1913
    .quad 1917,1917
    .quad 1921,1921
    .quad 1925,1925
    .quad 1929,1929
    .quad 1933,1933
    .quad 1937,1937
    .quad 1941,1941
    .quad 1945,1945
    .quad 1949,1949
    .quad 1953,1953
    .quad 1957,1957
    .quad 1961,1961
    .quad 1965,1965
    .quad 1969,1969
    .quad 1973,1973
    .quad 1977,1977
    .quad 1981,1981
    .quad 1985,1985
    .quad 1989,1989
    .quad 1993,1993
    .quad 1997,1997
    .quad 2001,2001
    .quad 2005,2005
    .quad 2009,2009
    .quad 2013,2013
    .quad 2017,2017
    .quad 2021,2021
    .quad 2025,2025
    .quad 2029,2029
    .quad 2033,2033
    .quad 2037,2037
    .quad 2041,2041
    .quad 2045,2045
max_edits:
    .quad 0,0,letter,1
    .quad 1,1,letter,1
    .quad 2,2,letter,1
    .quad 3,3,letter,1
    .quad 4,4,letter,1
    .quad 5,5,letter,1
    .quad 6,6,letter,1
    .quad 7,7,letter,1
    .quad 8,8,letter,1
    .quad 9,9,letter,1
    .quad 10,10,letter,1
    .quad 11,11,letter,1
    .quad 12,12,letter,1
    .quad 13,13,letter,1
    .quad 14,14,letter,1
    .quad 15,15,letter,1
    .quad 16,16,letter,1
    .quad 17,17,letter,1
    .quad 18,18,letter,1
    .quad 19,19,letter,1
    .quad 20,20,letter,1
    .quad 21,21,letter,1
    .quad 22,22,letter,1
    .quad 23,23,letter,1
    .quad 24,24,letter,1
    .quad 25,25,letter,1
    .quad 26,26,letter,1
    .quad 27,27,letter,1
    .quad 28,28,letter,1
    .quad 29,29,letter,1
    .quad 30,30,letter,1
    .quad 31,31,letter,1
    .quad 32,32,letter,1
    .quad 33,33,letter,1
    .quad 34,34,letter,1
    .quad 35,35,letter,1
    .quad 36,36,letter,1
    .quad 37,37,letter,1
    .quad 38,38,letter,1
    .quad 39,39,letter,1
    .quad 40,40,letter,1
    .quad 41,41,letter,1
    .quad 42,42,letter,1
    .quad 43,43,letter,1
    .quad 44,44,letter,1
    .quad 45,45,letter,1
    .quad 46,46,letter,1
    .quad 47,47,letter,1
    .quad 48,48,letter,1
    .quad 49,49,letter,1
    .quad 50,50,letter,1
    .quad 51,51,letter,1
    .quad 52,52,letter,1
    .quad 53,53,letter,1
    .quad 54,54,letter,1
    .quad 55,55,letter,1
    .quad 56,56,letter,1
    .quad 57,57,letter,1
    .quad 58,58,letter,1
    .quad 59,59,letter,1
    .quad 60,60,letter,1
    .quad 61,61,letter,1
    .quad 62,62,letter,1
    .quad 63,63,letter,1
    .quad 64,64,letter,1
    .quad 65,65,letter,1
    .quad 66,66,letter,1
    .quad 67,67,letter,1
    .quad 68,68,letter,1
    .quad 69,69,letter,1
    .quad 70,70,letter,1
    .quad 71,71,letter,1
    .quad 72,72,letter,1
    .quad 73,73,letter,1
    .quad 74,74,letter,1
    .quad 75,75,letter,1
    .quad 76,76,letter,1
    .quad 77,77,letter,1
    .quad 78,78,letter,1
    .quad 79,79,letter,1
    .quad 80,80,letter,1
    .quad 81,81,letter,1
    .quad 82,82,letter,1
    .quad 83,83,letter,1
    .quad 84,84,letter,1
    .quad 85,85,letter,1
    .quad 86,86,letter,1
    .quad 87,87,letter,1
    .quad 88,88,letter,1
    .quad 89,89,letter,1
    .quad 90,90,letter,1
    .quad 91,91,letter,1
    .quad 92,92,letter,1
    .quad 93,93,letter,1
    .quad 94,94,letter,1
    .quad 95,95,letter,1
    .quad 96,96,letter,1
    .quad 97,97,letter,1
    .quad 98,98,letter,1
    .quad 99,99,letter,1
    .quad 100,100,letter,1
    .quad 101,101,letter,1
    .quad 102,102,letter,1
    .quad 103,103,letter,1
    .quad 104,104,letter,1
    .quad 105,105,letter,1
    .quad 106,106,letter,1
    .quad 107,107,letter,1
    .quad 108,108,letter,1
    .quad 109,109,letter,1
    .quad 110,110,letter,1
    .quad 111,111,letter,1
    .quad 112,112,letter,1
    .quad 113,113,letter,1
    .quad 114,114,letter,1
    .quad 115,115,letter,1
    .quad 116,116,letter,1
    .quad 117,117,letter,1
    .quad 118,118,letter,1
    .quad 119,119,letter,1
    .quad 120,120,letter,1
    .quad 121,121,letter,1
    .quad 122,122,letter,1
    .quad 123,123,letter,1
    .quad 124,124,letter,1
    .quad 125,125,letter,1
    .quad 126,126,letter,1
    .quad 127,127,letter,1
    .quad 128,128,letter,1
    .quad 129,129,letter,1
    .quad 130,130,letter,1
    .quad 131,131,letter,1
    .quad 132,132,letter,1
    .quad 133,133,letter,1
    .quad 134,134,letter,1
    .quad 135,135,letter,1
    .quad 136,136,letter,1
    .quad 137,137,letter,1
    .quad 138,138,letter,1
    .quad 139,139,letter,1
    .quad 140,140,letter,1
    .quad 141,141,letter,1
    .quad 142,142,letter,1
    .quad 143,143,letter,1
    .quad 144,144,letter,1
    .quad 145,145,letter,1
    .quad 146,146,letter,1
    .quad 147,147,letter,1
    .quad 148,148,letter,1
    .quad 149,149,letter,1
    .quad 150,150,letter,1
    .quad 151,151,letter,1
    .quad 152,152,letter,1
    .quad 153,153,letter,1
    .quad 154,154,letter,1
    .quad 155,155,letter,1
    .quad 156,156,letter,1
    .quad 157,157,letter,1
    .quad 158,158,letter,1
    .quad 159,159,letter,1
    .quad 160,160,letter,1
    .quad 161,161,letter,1
    .quad 162,162,letter,1
    .quad 163,163,letter,1
    .quad 164,164,letter,1
    .quad 165,165,letter,1
    .quad 166,166,letter,1
    .quad 167,167,letter,1
    .quad 168,168,letter,1
    .quad 169,169,letter,1
    .quad 170,170,letter,1
    .quad 171,171,letter,1
    .quad 172,172,letter,1
    .quad 173,173,letter,1
    .quad 174,174,letter,1
    .quad 175,175,letter,1
    .quad 176,176,letter,1
    .quad 177,177,letter,1
    .quad 178,178,letter,1
    .quad 179,179,letter,1
    .quad 180,180,letter,1
    .quad 181,181,letter,1
    .quad 182,182,letter,1
    .quad 183,183,letter,1
    .quad 184,184,letter,1
    .quad 185,185,letter,1
    .quad 186,186,letter,1
    .quad 187,187,letter,1
    .quad 188,188,letter,1
    .quad 189,189,letter,1
    .quad 190,190,letter,1
    .quad 191,191,letter,1
    .quad 192,192,letter,1
    .quad 193,193,letter,1
    .quad 194,194,letter,1
    .quad 195,195,letter,1
    .quad 196,196,letter,1
    .quad 197,197,letter,1
    .quad 198,198,letter,1
    .quad 199,199,letter,1
    .quad 200,200,letter,1
    .quad 201,201,letter,1
    .quad 202,202,letter,1
    .quad 203,203,letter,1
    .quad 204,204,letter,1
    .quad 205,205,letter,1
    .quad 206,206,letter,1
    .quad 207,207,letter,1
    .quad 208,208,letter,1
    .quad 209,209,letter,1
    .quad 210,210,letter,1
    .quad 211,211,letter,1
    .quad 212,212,letter,1
    .quad 213,213,letter,1
    .quad 214,214,letter,1
    .quad 215,215,letter,1
    .quad 216,216,letter,1
    .quad 217,217,letter,1
    .quad 218,218,letter,1
    .quad 219,219,letter,1
    .quad 220,220,letter,1
    .quad 221,221,letter,1
    .quad 222,222,letter,1
    .quad 223,223,letter,1
    .quad 224,224,letter,1
    .quad 225,225,letter,1
    .quad 226,226,letter,1
    .quad 227,227,letter,1
    .quad 228,228,letter,1
    .quad 229,229,letter,1
    .quad 230,230,letter,1
    .quad 231,231,letter,1
    .quad 232,232,letter,1
    .quad 233,233,letter,1
    .quad 234,234,letter,1
    .quad 235,235,letter,1
    .quad 236,236,letter,1
    .quad 237,237,letter,1
    .quad 238,238,letter,1
    .quad 239,239,letter,1
    .quad 240,240,letter,1
    .quad 241,241,letter,1
    .quad 242,242,letter,1
    .quad 243,243,letter,1
    .quad 244,244,letter,1
    .quad 245,245,letter,1
    .quad 246,246,letter,1
    .quad 247,247,letter,1
    .quad 248,248,letter,1
    .quad 249,249,letter,1
    .quad 250,250,letter,1
    .quad 251,251,letter,1
    .quad 252,252,letter,1
    .quad 253,253,letter,1
    .quad 254,254,letter,1
    .quad 255,255,letter,1
    .quad 256,256,letter,1
    .quad 257,257,letter,1
    .quad 258,258,letter,1
    .quad 259,259,letter,1
    .quad 260,260,letter,1
    .quad 261,261,letter,1
    .quad 262,262,letter,1
    .quad 263,263,letter,1
    .quad 264,264,letter,1
    .quad 265,265,letter,1
    .quad 266,266,letter,1
    .quad 267,267,letter,1
    .quad 268,268,letter,1
    .quad 269,269,letter,1
    .quad 270,270,letter,1
    .quad 271,271,letter,1
    .quad 272,272,letter,1
    .quad 273,273,letter,1
    .quad 274,274,letter,1
    .quad 275,275,letter,1
    .quad 276,276,letter,1
    .quad 277,277,letter,1
    .quad 278,278,letter,1
    .quad 279,279,letter,1
    .quad 280,280,letter,1
    .quad 281,281,letter,1
    .quad 282,282,letter,1
    .quad 283,283,letter,1
    .quad 284,284,letter,1
    .quad 285,285,letter,1
    .quad 286,286,letter,1
    .quad 287,287,letter,1
    .quad 288,288,letter,1
    .quad 289,289,letter,1
    .quad 290,290,letter,1
    .quad 291,291,letter,1
    .quad 292,292,letter,1
    .quad 293,293,letter,1
    .quad 294,294,letter,1
    .quad 295,295,letter,1
    .quad 296,296,letter,1
    .quad 297,297,letter,1
    .quad 298,298,letter,1
    .quad 299,299,letter,1
    .quad 300,300,letter,1
    .quad 301,301,letter,1
    .quad 302,302,letter,1
    .quad 303,303,letter,1
    .quad 304,304,letter,1
    .quad 305,305,letter,1
    .quad 306,306,letter,1
    .quad 307,307,letter,1
    .quad 308,308,letter,1
    .quad 309,309,letter,1
    .quad 310,310,letter,1
    .quad 311,311,letter,1
    .quad 312,312,letter,1
    .quad 313,313,letter,1
    .quad 314,314,letter,1
    .quad 315,315,letter,1
    .quad 316,316,letter,1
    .quad 317,317,letter,1
    .quad 318,318,letter,1
    .quad 319,319,letter,1
    .quad 320,320,letter,1
    .quad 321,321,letter,1
    .quad 322,322,letter,1
    .quad 323,323,letter,1
    .quad 324,324,letter,1
    .quad 325,325,letter,1
    .quad 326,326,letter,1
    .quad 327,327,letter,1
    .quad 328,328,letter,1
    .quad 329,329,letter,1
    .quad 330,330,letter,1
    .quad 331,331,letter,1
    .quad 332,332,letter,1
    .quad 333,333,letter,1
    .quad 334,334,letter,1
    .quad 335,335,letter,1
    .quad 336,336,letter,1
    .quad 337,337,letter,1
    .quad 338,338,letter,1
    .quad 339,339,letter,1
    .quad 340,340,letter,1
    .quad 341,341,letter,1
    .quad 342,342,letter,1
    .quad 343,343,letter,1
    .quad 344,344,letter,1
    .quad 345,345,letter,1
    .quad 346,346,letter,1
    .quad 347,347,letter,1
    .quad 348,348,letter,1
    .quad 349,349,letter,1
    .quad 350,350,letter,1
    .quad 351,351,letter,1
    .quad 352,352,letter,1
    .quad 353,353,letter,1
    .quad 354,354,letter,1
    .quad 355,355,letter,1
    .quad 356,356,letter,1
    .quad 357,357,letter,1
    .quad 358,358,letter,1
    .quad 359,359,letter,1
    .quad 360,360,letter,1
    .quad 361,361,letter,1
    .quad 362,362,letter,1
    .quad 363,363,letter,1
    .quad 364,364,letter,1
    .quad 365,365,letter,1
    .quad 366,366,letter,1
    .quad 367,367,letter,1
    .quad 368,368,letter,1
    .quad 369,369,letter,1
    .quad 370,370,letter,1
    .quad 371,371,letter,1
    .quad 372,372,letter,1
    .quad 373,373,letter,1
    .quad 374,374,letter,1
    .quad 375,375,letter,1
    .quad 376,376,letter,1
    .quad 377,377,letter,1
    .quad 378,378,letter,1
    .quad 379,379,letter,1
    .quad 380,380,letter,1
    .quad 381,381,letter,1
    .quad 382,382,letter,1
    .quad 383,383,letter,1
    .quad 384,384,letter,1
    .quad 385,385,letter,1
    .quad 386,386,letter,1
    .quad 387,387,letter,1
    .quad 388,388,letter,1
    .quad 389,389,letter,1
    .quad 390,390,letter,1
    .quad 391,391,letter,1
    .quad 392,392,letter,1
    .quad 393,393,letter,1
    .quad 394,394,letter,1
    .quad 395,395,letter,1
    .quad 396,396,letter,1
    .quad 397,397,letter,1
    .quad 398,398,letter,1
    .quad 399,399,letter,1
    .quad 400,400,letter,1
    .quad 401,401,letter,1
    .quad 402,402,letter,1
    .quad 403,403,letter,1
    .quad 404,404,letter,1
    .quad 405,405,letter,1
    .quad 406,406,letter,1
    .quad 407,407,letter,1
    .quad 408,408,letter,1
    .quad 409,409,letter,1
    .quad 410,410,letter,1
    .quad 411,411,letter,1
    .quad 412,412,letter,1
    .quad 413,413,letter,1
    .quad 414,414,letter,1
    .quad 415,415,letter,1
    .quad 416,416,letter,1
    .quad 417,417,letter,1
    .quad 418,418,letter,1
    .quad 419,419,letter,1
    .quad 420,420,letter,1
    .quad 421,421,letter,1
    .quad 422,422,letter,1
    .quad 423,423,letter,1
    .quad 424,424,letter,1
    .quad 425,425,letter,1
    .quad 426,426,letter,1
    .quad 427,427,letter,1
    .quad 428,428,letter,1
    .quad 429,429,letter,1
    .quad 430,430,letter,1
    .quad 431,431,letter,1
    .quad 432,432,letter,1
    .quad 433,433,letter,1
    .quad 434,434,letter,1
    .quad 435,435,letter,1
    .quad 436,436,letter,1
    .quad 437,437,letter,1
    .quad 438,438,letter,1
    .quad 439,439,letter,1
    .quad 440,440,letter,1
    .quad 441,441,letter,1
    .quad 442,442,letter,1
    .quad 443,443,letter,1
    .quad 444,444,letter,1
    .quad 445,445,letter,1
    .quad 446,446,letter,1
    .quad 447,447,letter,1
    .quad 448,448,letter,1
    .quad 449,449,letter,1
    .quad 450,450,letter,1
    .quad 451,451,letter,1
    .quad 452,452,letter,1
    .quad 453,453,letter,1
    .quad 454,454,letter,1
    .quad 455,455,letter,1
    .quad 456,456,letter,1
    .quad 457,457,letter,1
    .quad 458,458,letter,1
    .quad 459,459,letter,1
    .quad 460,460,letter,1
    .quad 461,461,letter,1
    .quad 462,462,letter,1
    .quad 463,463,letter,1
    .quad 464,464,letter,1
    .quad 465,465,letter,1
    .quad 466,466,letter,1
    .quad 467,467,letter,1
    .quad 468,468,letter,1
    .quad 469,469,letter,1
    .quad 470,470,letter,1
    .quad 471,471,letter,1
    .quad 472,472,letter,1
    .quad 473,473,letter,1
    .quad 474,474,letter,1
    .quad 475,475,letter,1
    .quad 476,476,letter,1
    .quad 477,477,letter,1
    .quad 478,478,letter,1
    .quad 479,479,letter,1
    .quad 480,480,letter,1
    .quad 481,481,letter,1
    .quad 482,482,letter,1
    .quad 483,483,letter,1
    .quad 484,484,letter,1
    .quad 485,485,letter,1
    .quad 486,486,letter,1
    .quad 487,487,letter,1
    .quad 488,488,letter,1
    .quad 489,489,letter,1
    .quad 490,490,letter,1
    .quad 491,491,letter,1
    .quad 492,492,letter,1
    .quad 493,493,letter,1
    .quad 494,494,letter,1
    .quad 495,495,letter,1
    .quad 496,496,letter,1
    .quad 497,497,letter,1
    .quad 498,498,letter,1
    .quad 499,499,letter,1
    .quad 500,500,letter,1
    .quad 501,501,letter,1
    .quad 502,502,letter,1
    .quad 503,503,letter,1
    .quad 504,504,letter,1
    .quad 505,505,letter,1
    .quad 506,506,letter,1
    .quad 507,507,letter,1
    .quad 508,508,letter,1
    .quad 509,509,letter,1
    .quad 510,510,letter,1
    .quad 511,511,letter,1
    .quad 512,512,letter,1
    .quad 513,513,letter,1
    .quad 514,514,letter,1
    .quad 515,515,letter,1
    .quad 516,516,letter,1
    .quad 517,517,letter,1
    .quad 518,518,letter,1
    .quad 519,519,letter,1
    .quad 520,520,letter,1
    .quad 521,521,letter,1
    .quad 522,522,letter,1
    .quad 523,523,letter,1
    .quad 524,524,letter,1
    .quad 525,525,letter,1
    .quad 526,526,letter,1
    .quad 527,527,letter,1
    .quad 528,528,letter,1
    .quad 529,529,letter,1
    .quad 530,530,letter,1
    .quad 531,531,letter,1
    .quad 532,532,letter,1
    .quad 533,533,letter,1
    .quad 534,534,letter,1
    .quad 535,535,letter,1
    .quad 536,536,letter,1
    .quad 537,537,letter,1
    .quad 538,538,letter,1
    .quad 539,539,letter,1
    .quad 540,540,letter,1
    .quad 541,541,letter,1
    .quad 542,542,letter,1
    .quad 543,543,letter,1
    .quad 544,544,letter,1
    .quad 545,545,letter,1
    .quad 546,546,letter,1
    .quad 547,547,letter,1
    .quad 548,548,letter,1
    .quad 549,549,letter,1
    .quad 550,550,letter,1
    .quad 551,551,letter,1
    .quad 552,552,letter,1
    .quad 553,553,letter,1
    .quad 554,554,letter,1
    .quad 555,555,letter,1
    .quad 556,556,letter,1
    .quad 557,557,letter,1
    .quad 558,558,letter,1
    .quad 559,559,letter,1
    .quad 560,560,letter,1
    .quad 561,561,letter,1
    .quad 562,562,letter,1
    .quad 563,563,letter,1
    .quad 564,564,letter,1
    .quad 565,565,letter,1
    .quad 566,566,letter,1
    .quad 567,567,letter,1
    .quad 568,568,letter,1
    .quad 569,569,letter,1
    .quad 570,570,letter,1
    .quad 571,571,letter,1
    .quad 572,572,letter,1
    .quad 573,573,letter,1
    .quad 574,574,letter,1
    .quad 575,575,letter,1
    .quad 576,576,letter,1
    .quad 577,577,letter,1
    .quad 578,578,letter,1
    .quad 579,579,letter,1
    .quad 580,580,letter,1
    .quad 581,581,letter,1
    .quad 582,582,letter,1
    .quad 583,583,letter,1
    .quad 584,584,letter,1
    .quad 585,585,letter,1
    .quad 586,586,letter,1
    .quad 587,587,letter,1
    .quad 588,588,letter,1
    .quad 589,589,letter,1
    .quad 590,590,letter,1
    .quad 591,591,letter,1
    .quad 592,592,letter,1
    .quad 593,593,letter,1
    .quad 594,594,letter,1
    .quad 595,595,letter,1
    .quad 596,596,letter,1
    .quad 597,597,letter,1
    .quad 598,598,letter,1
    .quad 599,599,letter,1
    .quad 600,600,letter,1
    .quad 601,601,letter,1
    .quad 602,602,letter,1
    .quad 603,603,letter,1
    .quad 604,604,letter,1
    .quad 605,605,letter,1
    .quad 606,606,letter,1
    .quad 607,607,letter,1
    .quad 608,608,letter,1
    .quad 609,609,letter,1
    .quad 610,610,letter,1
    .quad 611,611,letter,1
    .quad 612,612,letter,1
    .quad 613,613,letter,1
    .quad 614,614,letter,1
    .quad 615,615,letter,1
    .quad 616,616,letter,1
    .quad 617,617,letter,1
    .quad 618,618,letter,1
    .quad 619,619,letter,1
    .quad 620,620,letter,1
    .quad 621,621,letter,1
    .quad 622,622,letter,1
    .quad 623,623,letter,1
    .quad 624,624,letter,1
    .quad 625,625,letter,1
    .quad 626,626,letter,1
    .quad 627,627,letter,1
    .quad 628,628,letter,1
    .quad 629,629,letter,1
    .quad 630,630,letter,1
    .quad 631,631,letter,1
    .quad 632,632,letter,1
    .quad 633,633,letter,1
    .quad 634,634,letter,1
    .quad 635,635,letter,1
    .quad 636,636,letter,1
    .quad 637,637,letter,1
    .quad 638,638,letter,1
    .quad 639,639,letter,1
    .quad 640,640,letter,1
    .quad 641,641,letter,1
    .quad 642,642,letter,1
    .quad 643,643,letter,1
    .quad 644,644,letter,1
    .quad 645,645,letter,1
    .quad 646,646,letter,1
    .quad 647,647,letter,1
    .quad 648,648,letter,1
    .quad 649,649,letter,1
    .quad 650,650,letter,1
    .quad 651,651,letter,1
    .quad 652,652,letter,1
    .quad 653,653,letter,1
    .quad 654,654,letter,1
    .quad 655,655,letter,1
    .quad 656,656,letter,1
    .quad 657,657,letter,1
    .quad 658,658,letter,1
    .quad 659,659,letter,1
    .quad 660,660,letter,1
    .quad 661,661,letter,1
    .quad 662,662,letter,1
    .quad 663,663,letter,1
    .quad 664,664,letter,1
    .quad 665,665,letter,1
    .quad 666,666,letter,1
    .quad 667,667,letter,1
    .quad 668,668,letter,1
    .quad 669,669,letter,1
    .quad 670,670,letter,1
    .quad 671,671,letter,1
    .quad 672,672,letter,1
    .quad 673,673,letter,1
    .quad 674,674,letter,1
    .quad 675,675,letter,1
    .quad 676,676,letter,1
    .quad 677,677,letter,1
    .quad 678,678,letter,1
    .quad 679,679,letter,1
    .quad 680,680,letter,1
    .quad 681,681,letter,1
    .quad 682,682,letter,1
    .quad 683,683,letter,1
    .quad 684,684,letter,1
    .quad 685,685,letter,1
    .quad 686,686,letter,1
    .quad 687,687,letter,1
    .quad 688,688,letter,1
    .quad 689,689,letter,1
    .quad 690,690,letter,1
    .quad 691,691,letter,1
    .quad 692,692,letter,1
    .quad 693,693,letter,1
    .quad 694,694,letter,1
    .quad 695,695,letter,1
    .quad 696,696,letter,1
    .quad 697,697,letter,1
    .quad 698,698,letter,1
    .quad 699,699,letter,1
    .quad 700,700,letter,1
    .quad 701,701,letter,1
    .quad 702,702,letter,1
    .quad 703,703,letter,1
    .quad 704,704,letter,1
    .quad 705,705,letter,1
    .quad 706,706,letter,1
    .quad 707,707,letter,1
    .quad 708,708,letter,1
    .quad 709,709,letter,1
    .quad 710,710,letter,1
    .quad 711,711,letter,1
    .quad 712,712,letter,1
    .quad 713,713,letter,1
    .quad 714,714,letter,1
    .quad 715,715,letter,1
    .quad 716,716,letter,1
    .quad 717,717,letter,1
    .quad 718,718,letter,1
    .quad 719,719,letter,1
    .quad 720,720,letter,1
    .quad 721,721,letter,1
    .quad 722,722,letter,1
    .quad 723,723,letter,1
    .quad 724,724,letter,1
    .quad 725,725,letter,1
    .quad 726,726,letter,1
    .quad 727,727,letter,1
    .quad 728,728,letter,1
    .quad 729,729,letter,1
    .quad 730,730,letter,1
    .quad 731,731,letter,1
    .quad 732,732,letter,1
    .quad 733,733,letter,1
    .quad 734,734,letter,1
    .quad 735,735,letter,1
    .quad 736,736,letter,1
    .quad 737,737,letter,1
    .quad 738,738,letter,1
    .quad 739,739,letter,1
    .quad 740,740,letter,1
    .quad 741,741,letter,1
    .quad 742,742,letter,1
    .quad 743,743,letter,1
    .quad 744,744,letter,1
    .quad 745,745,letter,1
    .quad 746,746,letter,1
    .quad 747,747,letter,1
    .quad 748,748,letter,1
    .quad 749,749,letter,1
    .quad 750,750,letter,1
    .quad 751,751,letter,1
    .quad 752,752,letter,1
    .quad 753,753,letter,1
    .quad 754,754,letter,1
    .quad 755,755,letter,1
    .quad 756,756,letter,1
    .quad 757,757,letter,1
    .quad 758,758,letter,1
    .quad 759,759,letter,1
    .quad 760,760,letter,1
    .quad 761,761,letter,1
    .quad 762,762,letter,1
    .quad 763,763,letter,1
    .quad 764,764,letter,1
    .quad 765,765,letter,1
    .quad 766,766,letter,1
    .quad 767,767,letter,1
    .quad 768,768,letter,1
    .quad 769,769,letter,1
    .quad 770,770,letter,1
    .quad 771,771,letter,1
    .quad 772,772,letter,1
    .quad 773,773,letter,1
    .quad 774,774,letter,1
    .quad 775,775,letter,1
    .quad 776,776,letter,1
    .quad 777,777,letter,1
    .quad 778,778,letter,1
    .quad 779,779,letter,1
    .quad 780,780,letter,1
    .quad 781,781,letter,1
    .quad 782,782,letter,1
    .quad 783,783,letter,1
    .quad 784,784,letter,1
    .quad 785,785,letter,1
    .quad 786,786,letter,1
    .quad 787,787,letter,1
    .quad 788,788,letter,1
    .quad 789,789,letter,1
    .quad 790,790,letter,1
    .quad 791,791,letter,1
    .quad 792,792,letter,1
    .quad 793,793,letter,1
    .quad 794,794,letter,1
    .quad 795,795,letter,1
    .quad 796,796,letter,1
    .quad 797,797,letter,1
    .quad 798,798,letter,1
    .quad 799,799,letter,1
    .quad 800,800,letter,1
    .quad 801,801,letter,1
    .quad 802,802,letter,1
    .quad 803,803,letter,1
    .quad 804,804,letter,1
    .quad 805,805,letter,1
    .quad 806,806,letter,1
    .quad 807,807,letter,1
    .quad 808,808,letter,1
    .quad 809,809,letter,1
    .quad 810,810,letter,1
    .quad 811,811,letter,1
    .quad 812,812,letter,1
    .quad 813,813,letter,1
    .quad 814,814,letter,1
    .quad 815,815,letter,1
    .quad 816,816,letter,1
    .quad 817,817,letter,1
    .quad 818,818,letter,1
    .quad 819,819,letter,1
    .quad 820,820,letter,1
    .quad 821,821,letter,1
    .quad 822,822,letter,1
    .quad 823,823,letter,1
    .quad 824,824,letter,1
    .quad 825,825,letter,1
    .quad 826,826,letter,1
    .quad 827,827,letter,1
    .quad 828,828,letter,1
    .quad 829,829,letter,1
    .quad 830,830,letter,1
    .quad 831,831,letter,1
    .quad 832,832,letter,1
    .quad 833,833,letter,1
    .quad 834,834,letter,1
    .quad 835,835,letter,1
    .quad 836,836,letter,1
    .quad 837,837,letter,1
    .quad 838,838,letter,1
    .quad 839,839,letter,1
    .quad 840,840,letter,1
    .quad 841,841,letter,1
    .quad 842,842,letter,1
    .quad 843,843,letter,1
    .quad 844,844,letter,1
    .quad 845,845,letter,1
    .quad 846,846,letter,1
    .quad 847,847,letter,1
    .quad 848,848,letter,1
    .quad 849,849,letter,1
    .quad 850,850,letter,1
    .quad 851,851,letter,1
    .quad 852,852,letter,1
    .quad 853,853,letter,1
    .quad 854,854,letter,1
    .quad 855,855,letter,1
    .quad 856,856,letter,1
    .quad 857,857,letter,1
    .quad 858,858,letter,1
    .quad 859,859,letter,1
    .quad 860,860,letter,1
    .quad 861,861,letter,1
    .quad 862,862,letter,1
    .quad 863,863,letter,1
    .quad 864,864,letter,1
    .quad 865,865,letter,1
    .quad 866,866,letter,1
    .quad 867,867,letter,1
    .quad 868,868,letter,1
    .quad 869,869,letter,1
    .quad 870,870,letter,1
    .quad 871,871,letter,1
    .quad 872,872,letter,1
    .quad 873,873,letter,1
    .quad 874,874,letter,1
    .quad 875,875,letter,1
    .quad 876,876,letter,1
    .quad 877,877,letter,1
    .quad 878,878,letter,1
    .quad 879,879,letter,1
    .quad 880,880,letter,1
    .quad 881,881,letter,1
    .quad 882,882,letter,1
    .quad 883,883,letter,1
    .quad 884,884,letter,1
    .quad 885,885,letter,1
    .quad 886,886,letter,1
    .quad 887,887,letter,1
    .quad 888,888,letter,1
    .quad 889,889,letter,1
    .quad 890,890,letter,1
    .quad 891,891,letter,1
    .quad 892,892,letter,1
    .quad 893,893,letter,1
    .quad 894,894,letter,1
    .quad 895,895,letter,1
    .quad 896,896,letter,1
    .quad 897,897,letter,1
    .quad 898,898,letter,1
    .quad 899,899,letter,1
    .quad 900,900,letter,1
    .quad 901,901,letter,1
    .quad 902,902,letter,1
    .quad 903,903,letter,1
    .quad 904,904,letter,1
    .quad 905,905,letter,1
    .quad 906,906,letter,1
    .quad 907,907,letter,1
    .quad 908,908,letter,1
    .quad 909,909,letter,1
    .quad 910,910,letter,1
    .quad 911,911,letter,1
    .quad 912,912,letter,1
    .quad 913,913,letter,1
    .quad 914,914,letter,1
    .quad 915,915,letter,1
    .quad 916,916,letter,1
    .quad 917,917,letter,1
    .quad 918,918,letter,1
    .quad 919,919,letter,1
    .quad 920,920,letter,1
    .quad 921,921,letter,1
    .quad 922,922,letter,1
    .quad 923,923,letter,1
    .quad 924,924,letter,1
    .quad 925,925,letter,1
    .quad 926,926,letter,1
    .quad 927,927,letter,1
    .quad 928,928,letter,1
    .quad 929,929,letter,1
    .quad 930,930,letter,1
    .quad 931,931,letter,1
    .quad 932,932,letter,1
    .quad 933,933,letter,1
    .quad 934,934,letter,1
    .quad 935,935,letter,1
    .quad 936,936,letter,1
    .quad 937,937,letter,1
    .quad 938,938,letter,1
    .quad 939,939,letter,1
    .quad 940,940,letter,1
    .quad 941,941,letter,1
    .quad 942,942,letter,1
    .quad 943,943,letter,1
    .quad 944,944,letter,1
    .quad 945,945,letter,1
    .quad 946,946,letter,1
    .quad 947,947,letter,1
    .quad 948,948,letter,1
    .quad 949,949,letter,1
    .quad 950,950,letter,1
    .quad 951,951,letter,1
    .quad 952,952,letter,1
    .quad 953,953,letter,1
    .quad 954,954,letter,1
    .quad 955,955,letter,1
    .quad 956,956,letter,1
    .quad 957,957,letter,1
    .quad 958,958,letter,1
    .quad 959,959,letter,1
    .quad 960,960,letter,1
    .quad 961,961,letter,1
    .quad 962,962,letter,1
    .quad 963,963,letter,1
    .quad 964,964,letter,1
    .quad 965,965,letter,1
    .quad 966,966,letter,1
    .quad 967,967,letter,1
    .quad 968,968,letter,1
    .quad 969,969,letter,1
    .quad 970,970,letter,1
    .quad 971,971,letter,1
    .quad 972,972,letter,1
    .quad 973,973,letter,1
    .quad 974,974,letter,1
    .quad 975,975,letter,1
    .quad 976,976,letter,1
    .quad 977,977,letter,1
    .quad 978,978,letter,1
    .quad 979,979,letter,1
    .quad 980,980,letter,1
    .quad 981,981,letter,1
    .quad 982,982,letter,1
    .quad 983,983,letter,1
    .quad 984,984,letter,1
    .quad 985,985,letter,1
    .quad 986,986,letter,1
    .quad 987,987,letter,1
    .quad 988,988,letter,1
    .quad 989,989,letter,1
    .quad 990,990,letter,1
    .quad 991,991,letter,1
    .quad 992,992,letter,1
    .quad 993,993,letter,1
    .quad 994,994,letter,1
    .quad 995,995,letter,1
    .quad 996,996,letter,1
    .quad 997,997,letter,1
    .quad 998,998,letter,1
    .quad 999,999,letter,1
    .quad 1000,1000,letter,1
    .quad 1001,1001,letter,1
    .quad 1002,1002,letter,1
    .quad 1003,1003,letter,1
    .quad 1004,1004,letter,1
    .quad 1005,1005,letter,1
    .quad 1006,1006,letter,1
    .quad 1007,1007,letter,1
    .quad 1008,1008,letter,1
    .quad 1009,1009,letter,1
    .quad 1010,1010,letter,1
    .quad 1011,1011,letter,1
    .quad 1012,1012,letter,1
    .quad 1013,1013,letter,1
    .quad 1014,1014,letter,1
    .quad 1015,1015,letter,1
    .quad 1016,1016,letter,1
    .quad 1017,1017,letter,1
    .quad 1018,1018,letter,1
    .quad 1019,1019,letter,1
    .quad 1020,1020,letter,1
    .quad 1021,1021,letter,1
    .quad 1022,1022,letter,1
    .quad 1023,1023,letter,1
diff0_source: .ascii "!βa!𐐀\n!a\nébβba\n𐐀bβéabββ"
diff0_after: .ascii "!βa!𐐀\n!a\nébβ😃😃\nΩΩYβY😃Y😃😃aΩ\nΩΩ"
diff0_before: .quad 13,32,36,28
diff0_pairs: .quad 42,34
diff0_payload0: .ascii "😃😃\n"
diff0_payload1: .ascii "ΩΩY"
diff0_payload2: .ascii "Y😃Y😃😃"
diff0_payload3: .ascii "Ω"
diff0_payload4: .ascii "\nΩΩ"
diff0_edits:
    .quad 18,19,diff0_payload0,9
    .quad 19,26,diff0_payload1,5
    .quad 28,30,diff0_payload2,14
    .quad 31,34,diff0_payload3,2
    .quad 34,36,diff0_payload4,5
diff1_source: .ascii "aβéébbb\na𐐀βaa\n!é!aβbééééé"
diff1_after: .ascii "aβéaβbééééé"
diff1_before: .quad 21,11,9,35
diff1_pairs: .quad 5,13,13,0,5,15
diff1_payload0: .ascii ""
diff1_edits:
    .quad 5,25,diff1_payload0,0
diff2_source: .ascii "𐐀\n!bé!"
diff2_after: .ascii "𐐀\n!bé!XX"
diff2_before: .quad 6,5,0,10,7,5,10,9
diff2_pairs: .quad 0,6,12,7,7,12
diff2_payload0: .ascii "XX"
diff2_edits:
    .quad 10,10,diff2_payload0,2
diff3_source: .ascii "!éb𐐀b\n"
diff3_after: .ascii "😃😃\nX!\n😃\nΩX𐐀XX\n😃😃"
diff3_before: .quad 3,1,8,8,4,8
diff3_pairs: .quad 15,12,9,35,10,35
diff3_payload0: .ascii "😃😃\nX"
diff3_payload1: .ascii "\n😃\nΩ"
diff3_payload2: .ascii "X"
diff3_payload3: .ascii "X"
diff3_payload4: .ascii "X"
diff3_payload5: .ascii "😃😃"
diff3_edits:
    .quad 0,0,diff3_payload0,10
    .quad 1,4,diff3_payload1,8
    .quad 4,4,diff3_payload2,1
    .quad 8,9,diff3_payload3,1
    .quad 9,9,diff3_payload4,1
    .quad 10,10,diff3_payload5,8
diff4_source: .ascii "!é𐐀!a!éβ\n𐐀é𐐀béé𐐀\nb!aéβ!bé"
diff4_after: .ascii "!é𐐀!a!éβ\n𐐀é𐐀béé𐐀\nb!aéβ!bé"
diff4_before: .quad 0,40,36,46,40,15
diff4_pairs: .quad 15,12
diff4_edits:
diff5_source: .ascii "\né𐐀β\naββ𐐀𐐀bβ\na\n\na!aβ!é"
diff5_after: .ascii "\né𐐀β\naββΩ😃😃Y\nβ😃\nXΩ!é"
diff5_before: .quad 23,10
diff5_pairs: .quad 17,11,34,29
diff5_payload0: .ascii "Ω😃😃Y\n"
diff5_payload1: .ascii "😃\nXΩ"
diff5_edits:
    .quad 15,24,diff5_payload0,12
    .quad 26,35,diff5_payload1,8
diff6_source: .ascii "β𐐀é\nβ𐐀!𐐀βééβ!βé"
diff6_after: .ascii "X😃Yβ𐐀ΩΩXΩX𐐀βééY\n😃YXβ!😃ΩΩΩ\né"
diff6_before: .quad 8,9
diff6_pairs: .quad 53,51,19,16
diff6_payload0: .ascii "X😃Y"
diff6_payload1: .ascii "ΩΩXΩX"
diff6_payload2: .ascii "Y\n😃YX"
diff6_payload3: .ascii "😃ΩΩΩ\n"
diff6_edits:
    .quad 0,9,diff6_payload0,6
    .quad 15,16,diff6_payload1,8
    .quad 26,26,diff6_payload2,8
    .quad 29,31,diff6_payload3,11
diff7_source: .ascii "β!b\nbβ!\nβ𐐀éaβ!\n"
diff7_after: .ascii "β!b\nbβX!\nβ𐐀XXΩ\n"
diff7_before: .quad 18,3,16,0
diff7_pairs: .quad 22,11,17,18
diff7_payload0: .ascii "X"
diff7_payload1: .ascii "XXΩ"
diff7_edits:
    .quad 8,8,diff7_payload0,1
    .quad 16,22,diff7_payload1,4
diff8_source: .ascii "βaabéa𐐀!βbβéa!β\n!\n\n!"
diff8_after: .ascii "β\naaYbéa😃😃\nΩY😃β\n!YΩ\n\nY!Y\n"
diff8_before: .quad 18,3
diff8_pairs: .quad 34,19
diff8_payload0: .ascii "\n"
diff8_payload1: .ascii "Y"
diff8_payload2: .ascii "😃😃\nΩY"
diff8_payload3: .ascii "😃"
diff8_payload4: .ascii "YΩ\n\nY"
diff8_payload5: .ascii "Y\n"
diff8_edits:
    .quad 2,2,diff8_payload0,1
    .quad 4,4,diff8_payload1,1
    .quad 8,20,diff8_payload2,12
    .quad 20,22,diff8_payload3,4
    .quad 26,28,diff8_payload4,6
    .quad 29,29,diff8_payload5,2
diff9_source: .ascii "\n\naa\n𐐀!bbβ"
diff9_after: .ascii "XXaY😃𐐀!bΩ😃Ωbβ"
diff9_before: .quad 11,2
diff9_pairs: .quad 17,13,13,4,8,25,0,3,23,25
diff9_payload0: .ascii "XX"
diff9_payload1: .ascii "Y😃"
diff9_payload2: .ascii "Ω😃Ω"
diff9_edits:
    .quad 0,3,diff9_payload0,2
    .quad 4,5,diff9_payload1,5
    .quad 11,11,diff9_payload2,8
diff10_source: .ascii "!b𐐀βéaaβa𐐀!éé\né𐐀β\n𐐀𐐀\nb"
diff10_after: .ascii "!b𐐀βéaaβa𐐀!éé\né𐐀β\n𐐀𐐀\nb"
diff10_before: .quad 43,34,20,24,22,1,31,2,15,25
diff10_pairs: .quad 19,6,44,6,12,25
diff10_edits:
diff11_source: .ascii "𐐀𐐀éβaβ\néé!𐐀baaβ!ββ\n"
diff11_after: .ascii "XYYXéβY😃aβ\néé!𐐀baΩ\n\n\n😃Ω😃\n"
diff11_before: .quad 4,30
diff11_pairs: .quad 8,8
diff11_payload0: .ascii "X"
diff11_payload1: .ascii "YYX"
diff11_payload2: .ascii "Y😃"
diff11_payload3: .ascii "Ω\n\n"
diff11_payload4: .ascii "\n😃Ω😃"
diff11_edits:
    .quad 0,4,diff11_payload0,1
    .quad 4,8,diff11_payload1,3
    .quad 12,12,diff11_payload2,5
    .quad 27,33,diff11_payload3,4
    .quad 33,35,diff11_payload4,11
diff12_source: .ascii "\nβbbb𐐀β"
diff12_after: .ascii "\nβbbb𐐀β"
diff12_before: .quad 4,0,10,3,1,5,12,10
diff12_pairs: .quad 11,6
diff12_edits:
diff13_source: .ascii "\n!β!b\nβb\néaéβa𐐀𐐀"
diff13_after: .ascii "\n!β!b\nβb\néaéβa𐐀𐐀"
diff13_before: .quad 23,6,0,0,23,10
diff13_pairs: .quad 19,23,18,16,7,9
diff13_edits:
diff14_source: .ascii "bé\n𐐀𐐀\nbaéb!𐐀abb𐐀!β!!"
diff14_after: .ascii "ΩY𐐀Y\néb!\n😃\nΩXabb𐐀XΩX\n!!"
diff14_before: .quad 12,12
diff14_pairs: .quad 14,25,3,34
diff14_payload0: .ascii "ΩY"
diff14_payload1: .ascii "Y\n"
diff14_payload2: .ascii "\n😃\nΩX"
diff14_payload3: .ascii "X"
diff14_payload4: .ascii "ΩX\n"
diff14_edits:
    .quad 0,8,diff14_payload0,3
    .quad 12,15,diff14_payload1,2
    .quad 19,23,diff14_payload2,9
    .quad 30,31,diff14_payload3,1
    .quad 31,33,diff14_payload4,4
diff15_source: .ascii "bé\nβ\n"
diff15_after: .ascii "bé😃😃😃😃😃Ω\nXY"
diff15_before: .quad 7,3
diff15_pairs: .quad 2,25,27,15,27,27,25,28,7,23
diff15_payload0: .ascii "😃😃😃😃😃"
diff15_payload1: .ascii "Ω"
diff15_payload2: .ascii "XY"
diff15_edits:
    .quad 3,6,diff15_payload0,20
    .quad 6,6,diff15_payload1,2
    .quad 7,7,diff15_payload2,2
diff16_source: .ascii "β\né𐐀é𐐀βéaaéββb"
diff16_after: .ascii "β😃\nY😃éX\néΩY\naaéββb😃X\nΩ"
diff16_before: .quad 27,9,27,15
diff16_pairs: .quad 36,8,22,28,36,37,30,30,37,8
diff16_payload0: .ascii "😃\nY😃"
diff16_payload1: .ascii "X\n"
diff16_payload2: .ascii "ΩY\n"
diff16_payload3: .ascii "😃X\nΩ"
diff16_edits:
    .quad 2,3,diff16_payload0,10
    .quad 5,17,diff16_payload1,2
    .quad 19,19,diff16_payload2,4
    .quad 28,28,diff16_payload3,8
diff17_source: .ascii "a𐐀β𐐀\n𐐀\nabaβa"
diff17_after: .ascii "a𐐀YX\n😃YΩ😃😃X😃\n𐐀\nabβ"
diff17_before: .quad 0,20,20,19,22,19,18,11,5,7
diff17_pairs: .quad 38,6
diff17_payload0: .ascii "Y"
diff17_payload1: .ascii "X\n😃YΩ"
diff17_payload2: .ascii "😃😃X😃\n"
diff17_payload3: .ascii ""
diff17_payload4: .ascii ""
diff17_edits:
    .quad 5,7,diff17_payload0,1
    .quad 7,11,diff17_payload1,9
    .quad 11,12,diff17_payload2,14
    .quad 19,20,diff17_payload3,0
    .quad 22,23,diff17_payload4,0
diff18_source: .ascii "béβaa𐐀β!𐐀!é𐐀é𐐀βébβé𐐀bβaa"
diff18_after: .ascii "béβaa𐐀β!𐐀!é𐐀é𐐀βébβé𐐀bβa\n"
diff18_before: .quad 13,47,6,36,31,1,5,38
diff18_pairs: .quad 37,6,21,1,45,31
diff18_payload0: .ascii "\n"
diff18_edits:
    .quad 48,49,diff18_payload0,1
diff19_source: .ascii "\nb\n!!éββ\n!b\nbéa\n!!é𐐀baaa\n"
diff19_after: .ascii "\nb\n!!éββ\n!b\nb😃ΩΩX𐐀baaa\n"
diff19_before: .quad 18,32
diff19_pairs: .quad 14,7
diff19_payload0: .ascii ""
diff19_payload1: .ascii "😃ΩΩX"
diff19_edits:
    .quad 16,24,diff19_payload0,0
    .quad 24,24,diff19_payload1,9
diff20_source: .ascii "éb!β!ββ!a"
diff20_after: .ascii "ΩYΩXb!β😃😃ΩΩXΩYβΩΩ\n😃Ωa"
diff20_before: .quad 2,3,11,11,7,9,7,3
diff20_pairs: .quad 6,10
diff20_payload0: .ascii "ΩYΩX"
diff20_payload1: .ascii "😃😃"
diff20_payload2: .ascii "ΩΩXΩY"
diff20_payload3: .ascii "ΩΩ\n😃Ω"
diff20_edits:
    .quad 0,2,diff20_payload0,6
    .quad 6,9,diff20_payload1,8
    .quad 9,9,diff20_payload2,8
    .quad 11,12,diff20_payload3,11
diff21_source: .ascii "abb"
diff21_after: .ascii "X😃a\n😃Xb😃XXΩ"
diff21_before: .quad 3,2,1,1,1,2,2,3
diff21_pairs: .quad 14,1,6,7,17,13,17,6
diff21_payload0: .ascii "X😃"
diff21_payload1: .ascii "\n😃"
diff21_payload2: .ascii "X"
diff21_payload3: .ascii "😃XXΩ"
diff21_edits:
    .quad 0,0,diff21_payload0,5
    .quad 1,2,diff21_payload1,5
    .quad 2,2,diff21_payload2,1
    .quad 3,3,diff21_payload3,8
diff22_source: .ascii "!𐐀aββéé!𐐀𐐀\nb\n"
diff22_after: .ascii "!𐐀aββéé!𐐀𐐀\nb\n"
diff22_before: .quad 0,24,15,12,19,26,26,5,25,24
diff22_pairs: .quad 10,19,0,6,24,19
diff22_edits:
diff23_source: .ascii "\n\n!ébβ𐐀é𐐀𐐀!!béβ\nβ\nβaba!"
diff23_after: .ascii "\n\n!Xbβ𐐀X😃XYY𐐀!😃Xbéβ\nβΩΩΩX\nβaba\n\n😃!"
diff23_before: .quad 38,3,29,37,25,36,14,3,8,8
diff23_pairs: .quad 49,50,50,5
diff23_payload0: .ascii "X"
diff23_payload1: .ascii "X😃XYY"
diff23_payload2: .ascii "😃X"
diff23_payload3: .ascii "ΩΩΩX"
diff23_payload4: .ascii "\n\n😃"
diff23_edits:
    .quad 3,5,diff23_payload0,1
    .quad 12,18,diff23_payload1,8
    .quad 23,24,diff23_payload2,5
    .quad 32,32,diff23_payload3,7
    .quad 38,38,diff23_payload4,6
diff24_source: .ascii "é\n𐐀b\nβ𐐀βββab\n𐐀"
diff24_after: .ascii "é\n𐐀b\nβ𐐀βββab\n𐐀"
diff24_before: .quad 22,8,8,11,7,7
diff24_pairs: .quad 20,11,3,2
diff24_edits:
diff25_source: .ascii "\né!bbaβa𐐀é!\na𐐀𐐀éβ!é!β\n"
diff25_after: .ascii "\né!bbaβa𐐀é😃Ω😃X😃\nβ!é!β\n"
diff25_before: .quad 32,32,14,4,32,32
diff25_pairs: .quad 35,6,40,37
diff25_payload0: .ascii "😃Ω😃"
diff25_payload1: .ascii "X😃\n"
diff25_edits:
    .quad 16,27,diff25_payload0,10
    .quad 27,29,diff25_payload1,6
diff26_source: .ascii "éb\n!\nββ!b\na!𐐀a!𐐀𐐀abb"
diff26_after: .ascii "éb\n!\nββ!b\na!𐐀a!𐐀𐐀abb"
diff26_before: .quad 6,4
diff26_pairs: .quad 31,15,15,29,2,31,14,19,15,5
diff26_edits:
diff27_source: .ascii "β𐐀bβa𐐀β\naéβ𐐀ββébbé!\n"
diff27_after: .ascii "β𐐀bβa𐐀β\naéβ𐐀ββébbé!\n"
diff27_before: .quad 17,34,0,22
diff27_pairs: .quad 8,16,28,36
diff27_edits:
diff28_source: .ascii "β𐐀β\n!𐐀éb"
diff28_after: .ascii "β𐐀β😃XY😃ΩX𐐀éb"
diff28_before: .quad 8,0
diff28_pairs: .quad 28,12,25,13,18,28,27,8
diff28_payload0: .ascii "😃X"
diff28_payload1: .ascii "Y😃ΩX"
diff28_edits:
    .quad 8,9,diff28_payload0,5
    .quad 9,10,diff28_payload1,8
diff29_source: .ascii "a\na\n"
diff29_after: .ascii "a\n😃XΩ😃😃X"
diff29_before: .quad 2,1,4,2
diff29_pairs: .quad 7,2,13,17,13,9
diff29_payload0: .ascii "\n😃X"
diff29_payload1: .ascii "Ω😃😃"
diff29_payload2: .ascii ""
diff29_payload3: .ascii "X"
diff29_edits:
    .quad 1,2,diff29_payload0,6
    .quad 2,3,diff29_payload1,10
    .quad 3,4,diff29_payload2,0
    .quad 4,4,diff29_payload3,1
diff30_source: .ascii "abb"
diff30_after: .ascii "ab😃ΩbX"
diff30_before: .quad 0,0,0,3,2,0,3,2
diff30_pairs: .quad 5,6,8,0,8,9
diff30_payload0: .ascii "😃Ω"
diff30_payload1: .ascii "X"
diff30_edits:
    .quad 2,2,diff30_payload0,6
    .quad 3,3,diff30_payload1,1
diff31_source: .ascii "é𐐀𐐀\n!é𐐀é𐐀βa"
diff31_after: .ascii "é𐐀𐐀Ω\nΩXYé𐐀βaY"
diff31_before: .quad 6,27,0,11
diff31_pairs: .quad 10,27,13,2
diff31_payload0: .ascii "Ω\nΩXY"
diff31_payload1: .ascii ""
diff31_payload2: .ascii "Y"
diff31_edits:
    .quad 10,12,diff31_payload0,7
    .quad 12,18,diff31_payload1,0
    .quad 27,27,diff31_payload2,1
diff32_source: .ascii "ab\na𐐀aβ𐐀baéβa!"
diff32_after: .ascii "😃😃😃😃Y😃😃😃aβXX𐐀XYXXaéΩ😃Yβa!"
diff32_before: .quad 15,23
diff32_pairs: .quad 25,45,4,8
diff32_payload0: .ascii "😃😃😃😃Y"
diff32_payload1: .ascii "😃"
diff32_payload2: .ascii "😃😃"
diff32_payload3: .ascii "XX"
diff32_payload4: .ascii "XYXX"
diff32_payload5: .ascii "Ω😃Y"
diff32_edits:
    .quad 0,3,diff32_payload0,17
    .quad 3,4,diff32_payload1,4
    .quad 4,8,diff32_payload2,8
    .quad 11,11,diff32_payload3,2
    .quad 15,16,diff32_payload4,4
    .quad 19,19,diff32_payload5,7
diff33_source: .ascii "a\n\nβ!!𐐀β!!é"
diff33_after: .ascii "aX\nY\n\nβ!!XX😃Y\né"
diff33_before: .quad 14,3,7,17
diff33_pairs: .quad 14,20,2,12,6,11
diff33_payload0: .ascii ""
diff33_payload1: .ascii "X\nY\n"
diff33_payload2: .ascii "XX😃Y\n"
diff33_edits:
    .quad 1,2,diff33_payload0,0
    .quad 2,2,diff33_payload1,4
    .quad 7,15,diff33_payload2,8
diff34_source: .ascii "éa!!bβbaβ\n!!a\nbb!𐐀\n"
diff34_after: .ascii "éa!!bβbaβ\n!!a\nb\nΩ\nΩ😃\n"
diff34_before: .quad 16,9,19,3,13,9,5,12
diff34_pairs: .quad 28,24,19,18,12,10,22,18
diff34_payload0: .ascii "\nΩ\n"
diff34_payload1: .ascii "Ω😃\n"
diff34_edits:
    .quad 18,25,diff34_payload0,4
    .quad 25,25,diff34_payload1,7
diff35_source: .ascii "βbéb\néba!é!"
diff35_after: .ascii "βbéb\néba!é!"
diff35_before: .quad 9,15,11,10,0,15
diff35_pairs: .quad 7,12
diff35_edits:
diff36_source: .ascii "β!b\nβ𐐀a!é\n"
diff36_after: .ascii "Ω😃\nYX!b\nΩΩY😃\nX𐐀\n😃Y😃a!YY\nΩ😃XΩΩ"
diff36_before: .quad 16,5,11,15,7,15,3,15
diff36_pairs: .quad 15,32,53,12,44,28,39,32
diff36_payload0: .ascii "Ω😃\nYX"
diff36_payload1: .ascii "ΩΩY"
diff36_payload2: .ascii "😃\nX"
diff36_payload3: .ascii "\n😃Y😃"
diff36_payload4: .ascii "YY"
diff36_payload5: .ascii "Ω😃XΩΩ"
diff36_edits:
    .quad 0,2,diff36_payload0,9
    .quad 5,7,diff36_payload1,5
    .quad 7,7,diff36_payload2,6
    .quad 11,11,diff36_payload3,10
    .quad 13,15,diff36_payload4,2
    .quad 16,16,diff36_payload5,11
diff37_source: .ascii "𐐀!éβ!b!b!𐐀𐐀éβé"
diff37_after: .ascii "𐐀!éβ!b!b!𐐀𐐀éβé"
diff37_before: .quad 10,13
diff37_pairs: .quad 4,26,11,18
diff37_edits:
diff38_source: .ascii "aa\nébaβaa!\naéaa\né\n\nβ"
diff38_after: .ascii "aa\nébYa!\naéaa\né\n\nβ"
diff38_before: .quad 13,11,16,2,16,17,22,9,12,6
diff38_pairs: .quad 11,0,5,15
diff38_payload0: .ascii "Y"
diff38_edits:
    .quad 6,10,diff38_payload0,1
diff39_source: .ascii "b!aéaéaβ!𐐀𐐀\nb𐐀\n𐐀"
diff39_after: .ascii "YX😃YbΩΩX!𐐀𐐀\nb𐐀YΩ\n"
diff39_before: .quad 27,1
diff39_pairs: .quad 17,18,6,14,12,22,22,29,18,10
diff39_payload0: .ascii "YX😃Y"
diff39_payload1: .ascii "ΩΩX"
diff39_payload2: .ascii "YΩ\n"
diff39_edits:
    .quad 0,0,diff39_payload0,7
    .quad 1,11,diff39_payload1,5
    .quad 26,31,diff39_payload2,4
diff40_source: .ascii "abβ\nab"
diff40_after: .ascii "XXab"
diff40_before: .quad 4,6,5,4,2,4
diff40_pairs: .quad 1,3,4,0,0,1,3,2
diff40_payload0: .ascii ""
diff40_payload1: .ascii "XX"
diff40_edits:
    .quad 0,5,diff40_payload0,0
    .quad 5,5,diff40_payload1,2
diff41_source: .ascii "a!aβ𐐀é!b"
diff41_after: .ascii "a!βXé!Y😃Y😃b"
diff41_before: .quad 1,13,2,11,11,1,2,1,3,5
diff41_pairs: .quad 13,1,4,9,0,5
diff41_payload0: .ascii ""
diff41_payload1: .ascii "X"
diff41_payload2: .ascii "Y😃Y😃"
diff41_edits:
    .quad 2,3,diff41_payload0,0
    .quad 5,9,diff41_payload1,1
    .quad 12,12,diff41_payload2,10
diff42_source: .ascii "a!b!a\néa𐐀bbéββ\n𐐀éβéβ𐐀\n!"
diff42_after: .ascii "a!b!a\néa𐐀bbéβXΩY😃éβ𐐀\n!"
diff42_before: .quad 28,30,38,3
diff42_pairs: .quad 10,3,36,5,8,35,35,19,5,29
diff42_payload0: .ascii "XΩY😃"
diff42_edits:
    .quad 19,30,diff42_payload0,8
diff43_source: .ascii "𐐀𐐀é\nbβé"
diff43_after: .ascii "\nΩ😃\n𐐀X𐐀é😃😃YYXbX😃YX"
diff43_before: .quad 0,8,14,10,11,0
diff43_pairs: .quad 23,32,1,36,28,8,30,13,37,28
diff43_payload0: .ascii "\nΩ😃\n"
diff43_payload1: .ascii "X"
diff43_payload2: .ascii "😃😃YY"
diff43_payload3: .ascii "X"
diff43_payload4: .ascii ""
diff43_payload5: .ascii "X😃YX"
diff43_edits:
    .quad 0,0,diff43_payload0,8
    .quad 4,4,diff43_payload1,1
    .quad 10,11,diff43_payload2,10
    .quad 11,11,diff43_payload3,1
    .quad 12,14,diff43_payload4,0
    .quad 14,16,diff43_payload5,7
diff44_source: .ascii "!\néaa\n𐐀"
diff44_after: .ascii "😃Y!😃ΩXXΩéaXYaΩY\n😃𐐀ΩXXYY"
diff44_before: .quad 1,0,4,2
diff44_pairs: .quad 16,22,21,39
diff44_payload0: .ascii "😃Y"
diff44_payload1: .ascii "😃ΩXXΩ"
diff44_payload2: .ascii "XY"
diff44_payload3: .ascii "ΩY"
diff44_payload4: .ascii "😃"
diff44_payload5: .ascii "ΩXXYY"
diff44_edits:
    .quad 0,0,diff44_payload0,5
    .quad 1,2,diff44_payload1,10
    .quad 5,5,diff44_payload2,2
    .quad 6,6,diff44_payload3,3
    .quad 7,7,diff44_payload4,4
    .quad 11,11,diff44_payload5,6
diff45_source: .ascii "β!\n\n!é𐐀a𐐀é\né𐐀\n"
diff45_after: .ascii "\n\n\nYX!é𐐀a𐐀é\né𐐀XYY"
diff45_before: .quad 12,17
diff45_pairs: .quad 7,26,1,12,29,12,1,17
diff45_payload0: .ascii "\n\n\nYX"
diff45_payload1: .ascii "XYY"
diff45_edits:
    .quad 0,5,diff45_payload0,5
    .quad 26,27,diff45_payload1,3
diff46_source: .ascii "𐐀\n\n!β\n!b𐐀β\n𐐀𐐀aabβ!β!\n\n"
diff46_after: .ascii "ΩXYXΩΩ😃\n!βΩXXβ\n\nΩ\n\n😃\nΩY𐐀aabβ!β!\n\n"
diff46_before: .quad 32,23,19,23,29,7
diff46_pairs: .quad 49,34,34,19,25,14,27,37
diff46_payload0: .ascii "ΩXY"
diff46_payload1: .ascii "XΩΩ😃"
diff46_payload2: .ascii "ΩXX"
diff46_payload3: .ascii "\n\nΩ\n"
diff46_payload4: .ascii "😃\nΩY"
diff46_edits:
    .quad 0,4,diff46_payload0,4
    .quad 4,5,diff46_payload1,9
    .quad 9,16,diff46_payload2,4
    .quad 18,18,diff46_payload3,5
    .quad 19,23,diff46_payload4,8
diff47_source: .ascii "!b\n!β!𐐀!!\n𐐀!"
diff47_after: .ascii "X\n!β!😃😃!!😃YXXX"
diff47_before: .quad 2,11,14,0,18,3
diff47_pairs: .quad 10,21,24,24,0,2,22,16,15,22
diff47_payload0: .ascii ""
diff47_payload1: .ascii "X"
diff47_payload2: .ascii "😃😃"
diff47_payload3: .ascii "😃YX"
diff47_payload4: .ascii "XX"
diff47_edits:
    .quad 0,2,diff47_payload0,0
    .quad 2,2,diff47_payload1,1
    .quad 7,11,diff47_payload2,8
    .quad 13,19,diff47_payload3,6
    .quad 19,19,diff47_payload4,2
diff48_source: .ascii "𐐀é\né\n\nab!\nβ"
diff48_after: .ascii "𐐀é\né😃\nX\nβ"
diff48_before: .quad 15,15,4,6
diff48_pairs: .quad 8,13,6,0,9,13,13,4
diff48_payload0: .ascii "😃\nX"
diff48_edits:
    .quad 9,14,diff48_payload0,6
diff49_source: .ascii "!𐐀ba\n!b"
diff49_after: .ascii "!𐐀Ω\nΩ\n\nY\n😃ΩbΩYX😃"
diff49_before: .quad 9,9
diff49_pairs: .quad 8,24
diff49_payload0: .ascii "Ω\nΩ"
diff49_payload1: .ascii "\n"
diff49_payload2: .ascii "Y\n😃Ω"
diff49_payload3: .ascii "ΩYX😃"
diff49_edits:
    .quad 5,7,diff49_payload0,5
    .quad 7,7,diff49_payload1,1
    .quad 8,9,diff49_payload2,8
    .quad 10,10,diff49_payload3,8
diff50_source: .ascii "\n𐐀βé!aβ𐐀\nβéβ𐐀\n"
diff50_after: .ascii "XΩΩ\n😃\nΩ😃aβ𐐀Ω😃Y\nβΩéYYYΩ\n"
diff50_before: .quad 18,7,17,29,9,0,29,29,22,17
diff50_pairs: .quad 11,0,34,20,5,13,40,6,32,36
diff50_payload0: .ascii "XΩΩ"
diff50_payload1: .ascii "😃\nΩ😃"
diff50_payload2: .ascii "Ω😃Y\n"
diff50_payload3: .ascii "Ω"
diff50_payload4: .ascii "YYYΩ\n"
diff50_payload5: .ascii ""
diff50_edits:
    .quad 0,0,diff50_payload0,5
    .quad 1,10,diff50_payload1,11
    .quad 17,18,diff50_payload2,8
    .quad 20,20,diff50_payload3,2
    .quad 22,24,diff50_payload4,6
    .quad 24,29,diff50_payload5,0
diff51_source: .ascii "\nabaβ𐐀βa"
diff51_after: .ascii "\nabaβ𐐀βaY\n\n"
diff51_before: .quad 10,10,0,2,6,4,10,4
diff51_pairs: .quad 11,14,4,10
diff51_payload0: .ascii "Y\n\n"
diff51_edits:
    .quad 13,13,diff51_payload0,3
diff52_source: .ascii "\n\nb𐐀βb!é\n!b𐐀!aa!β"
diff52_after: .ascii "\n\nb𐐀βb!\n😃Y😃\n!b𐐀!aa!β"
diff52_before: .quad 10,3,3,2,0,24,3,20
diff52_pairs: .quad 22,12,32,32,7,1,22,29,10,34
diff52_payload0: .ascii "\n😃Y😃"
diff52_edits:
    .quad 11,13,diff52_payload0,10
diff53_source: .ascii "𐐀bb𐐀b!β𐐀\n!𐐀β\nabéa𐐀𐐀\nβ𐐀\n\n"
diff53_after: .ascii "𐐀bb𐐀b!β𐐀\n!𐐀β\nabéa𐐀𐐀\nβ𐐀\n\n"
diff53_before: .quad 24,36,26,5
diff53_pairs: .quad 0,12,43,14
diff53_edits:
diff54_source: .ascii "éb!!é\néa\na\n!𐐀\n\néa𐐀"
diff54_after: .ascii "é😃😃\nb!ΩX😃𐐀\n\néa𐐀"
diff54_before: .quad 11,24,4,21,5,3
diff54_pairs: .quad 32,0
diff54_payload0: .ascii "😃😃\n"
diff54_payload1: .ascii "Ω"
diff54_payload2: .ascii "X😃"
diff54_edits:
    .quad 2,2,diff54_payload0,9
    .quad 4,8,diff54_payload1,2
    .quad 8,15,diff54_payload2,5
diff55_source: .ascii "\né\n\n"
diff55_after: .ascii "\néY\n\nYX"
diff55_before: .quad 4,0,3,4
diff55_pairs: .quad 8,8,3,1,5,5,4,5
diff55_payload0: .ascii "Y\n\nYX"
diff55_edits:
    .quad 3,5,diff55_payload0,5
diff56_source: .ascii "𐐀β\nβa𐐀éβaéb!!a!!𐐀"
diff56_after: .ascii "𐐀\nY😃XX\n😃a𐐀éβaéb\nYXa!!XΩX"
diff56_before: .quad 27,21,27,16,16,6,10,9,9,18
diff56_pairs: .quad 18,35,12,33
diff56_payload0: .ascii "\nY"
diff56_payload1: .ascii "😃XX\n😃"
diff56_payload2: .ascii "\nYX"
diff56_payload3: .ascii "XΩX"
diff56_edits:
    .quad 4,6,diff56_payload0,2
    .quad 6,9,diff56_payload1,11
    .quad 22,24,diff56_payload2,3
    .quad 27,31,diff56_payload3,4
diff57_source: .ascii "\n𐐀β!\n\n\nββ\nββ\nbéββ!"
diff57_after: .ascii "\n𐐀β!\n\n\nββ\nββ\nbéββ!"
diff57_before: .quad 26,0,1,5,11,26,1,24,1,26
diff57_pairs: .quad 23,9,0,16,7,24
diff57_edits:
diff58_source: .ascii "é!β"
diff58_after: .ascii "Y!β"
diff58_before: .quad 5,2,2,3,3,5,3,0,3,0
diff58_pairs: .quad 4,1,4,1,2,0,4,4,4,1
diff58_payload0: .ascii "Y"
diff58_edits:
    .quad 0,2,diff58_payload0,1
diff59_source: .ascii "a\n𐐀𐐀\nβ"
diff59_after: .ascii "a\n𐐀𐐀\nβ"
diff59_before: .quad 11,2,0,6,6,1
diff59_pairs: .quad 10,11,2,1,2,13,1,0,10,2
diff59_edits:
diff60_source: .ascii "aβ\n\nβ!é!𐐀a"
diff60_after: .ascii "aβ\n\n\néX\n\nX😃"
diff60_before: .quad 8,16
diff60_pairs: .quad 7,6
diff60_payload0: .ascii "\n\n"
diff60_payload1: .ascii ""
diff60_payload2: .ascii "X\n\n"
diff60_payload3: .ascii "X😃"
diff60_edits:
    .quad 3,3,diff60_payload0,2
    .quad 4,8,diff60_payload1,0
    .quad 10,15,diff60_payload2,3
    .quad 15,16,diff60_payload3,5
diff61_source: .ascii "b!βabβ𐐀𐐀!"
diff61_after: .ascii "b!ΩΩΩ😃βab\n"
diff61_before: .quad 16,5,0,1,17,1,4,5,4,8
diff61_pairs: .quad 2,1,8,15,8,4
diff61_payload0: .ascii "ΩΩΩ😃"
diff61_payload1: .ascii "\n"
diff61_edits:
    .quad 2,2,diff61_payload0,10
    .quad 6,17,diff61_payload1,1
diff62_source: .ascii "!b𐐀é!!βb!βébbβ𐐀β𐐀"
diff62_after: .ascii "!bX𐐀é!X!Ω😃YΩYbΩYΩYY!\nbβ𐐀β𐐀"
diff62_before: .quad 14,8,10,9
diff62_pairs: .quad 7,12,21,2,18,3
diff62_payload0: .ascii "X"
diff62_payload1: .ascii "X"
diff62_payload2: .ascii "Ω😃YΩY"
diff62_payload3: .ascii "ΩYΩYY"
diff62_payload4: .ascii "\n"
diff62_edits:
    .quad 2,2,diff62_payload0,1
    .quad 9,9,diff62_payload1,1
    .quad 10,12,diff62_payload2,10
    .quad 13,13,diff62_payload3,7
    .quad 14,19,diff62_payload4,1
diff63_source: .ascii "𐐀\n!βb\n"
diff63_after: .ascii "𐐀\nY!XXΩXX"
diff63_before: .quad 0,6,5,8,10,5
diff63_pairs: .quad 1,0
diff63_payload0: .ascii "Y"
diff63_payload1: .ascii "XXΩ"
diff63_payload2: .ascii "XX"
diff63_edits:
    .quad 5,5,diff63_payload0,1
    .quad 6,9,diff63_payload1,4
    .quad 9,10,diff63_payload2,2
diff64_source: .ascii "!é𐐀β𐐀b\nb!aé𐐀é"
diff64_after: .ascii "!é𐐀βXY\n\n𐐀b\nb!aé𐐀é"
diff64_before: .quad 7,15,1,18,14,24,17,18,17,13
diff64_pairs: .quad 18,10,20,28,28,22
diff64_payload0: .ascii "XY\n\n"
diff64_edits:
    .quad 9,9,diff64_payload0,4
diff65_source: .ascii "𐐀\n\n!éb!é!β!a𐐀𐐀bβ\né!\néa"
diff65_after: .ascii "Ω\nΩ𐐀\n\n!ébΩΩX!β!a𐐀𐐀bβ\né!\néa"
diff65_before: .quad 22,30
diff65_pairs: .quad 24,5,23,29,25,14,15,37
diff65_payload0: .ascii "Ω\nΩ"
diff65_payload1: .ascii "ΩΩX"
diff65_edits:
    .quad 0,0,diff65_payload0,5
    .quad 10,13,diff65_payload1,5
diff66_source: .ascii "𐐀éaaβb\n𐐀!b\na𐐀βba\nb!"
diff66_after: .ascii "𐐀éaaβb\n𐐀!Y𐐀βba\nb!"
diff66_before: .quad 6,4,20,29,10,11,18,24
diff66_pairs: .quad 23,28,28,8,26,27
diff66_payload0: .ascii "Y"
diff66_edits:
    .quad 17,20,diff66_payload0,1
diff67_source: .ascii "\né𐐀é!β𐐀!abé\nβ\nb"
diff67_after: .ascii "\né𐐀é!βX\nΩ\nbé\nXβX\nX\nb"
diff67_before: .quad 3,21,18,9,1,19
diff67_pairs: .quad 27,20
diff67_payload0: .ascii "X\nΩ\n"
diff67_payload1: .ascii "X"
diff67_payload2: .ascii "X\nX"
diff67_edits:
    .quad 12,18,diff67_payload0,5
    .quad 22,22,diff67_payload1,1
    .quad 24,24,diff67_payload2,3
diff68_source: .ascii "abéb\n𐐀𐐀𐐀!aββ"
diff68_after: .ascii "abéb\n𐐀😃ββ"
diff68_before: .quad 20,1,2,22
diff68_pairs: .quad 4,18,1,6
diff68_payload0: .ascii "😃"
diff68_edits:
    .quad 10,20,diff68_payload0,4
diff69_source: .ascii "𐐀βé\na𐐀"
diff69_after: .ascii "𐐀β\n\nΩ\nΩXY\n𐐀"
diff69_before: .quad 14,4,6,8,14,6
diff69_pairs: .quad 9,16
diff69_payload0: .ascii "\n\nΩ"
diff69_payload1: .ascii "\nΩXY\n"
diff69_edits:
    .quad 6,10,diff69_payload0,4
    .quad 10,10,diff69_payload1,6
diff70_source: .ascii "!𐐀!"
diff70_after: .ascii "Y\nY😃XΩYYΩ\n\n\n😃ΩX"
diff70_before: .quad 6,1
diff70_pairs: .quad 0,16,23,7,14,8
diff70_payload0: .ascii "Y\nY😃X"
diff70_payload1: .ascii "ΩYYΩ\n"
diff70_payload2: .ascii "\n\n😃"
diff70_payload3: .ascii "ΩX"
diff70_edits:
    .quad 0,1,diff70_payload0,8
    .quad 1,5,diff70_payload1,7
    .quad 5,6,diff70_payload2,6
    .quad 6,6,diff70_payload3,3
diff71_source: .ascii "!aé\n𐐀é\n\n!é𐐀éβé𐐀𐐀!a𐐀éa𐐀𐐀é"
diff71_after: .ascii "!aé😃😃😃\n\n!é𐐀😃YΩ𐐀éa𐐀𐐀é"
diff71_before: .quad 24,42,5,20,14,51
diff71_pairs: .quad 8,39,1,29,18,29,12,1
diff71_payload0: .ascii "😃😃😃"
diff71_payload1: .ascii "😃YΩ"
diff71_edits:
    .quad 4,11,diff71_payload0,12
    .quad 20,36,diff71_payload1,7
diff72_source: .ascii "éβébé!b𐐀bββββééé"
diff72_after: .ascii "éβéb\nYYYX!b𐐀bX😃YβXX😃é\né\n😃😃"
diff72_before: .quad 20,26,30,28,22,26,2,15
diff72_pairs: .quad 15,9,33,8,47,33,13,8,9,4
diff72_payload0: .ascii "\nY"
diff72_payload1: .ascii "YYX"
diff72_payload2: .ascii "X😃Y"
diff72_payload3: .ascii "XX😃"
diff72_payload4: .ascii "\n"
diff72_payload5: .ascii "\n😃😃"
diff72_edits:
    .quad 7,9,diff72_payload0,2
    .quad 9,9,diff72_payload1,3
    .quad 16,16,diff72_payload2,6
    .quad 18,24,diff72_payload3,6
    .quad 26,26,diff72_payload4,1
    .quad 28,30,diff72_payload5,9
diff73_source: .ascii "βbbéββ!b!baééa!bab!βaaβa\n"
diff73_after: .ascii "βbbX\n😃\nXb!βaaβa\n"
diff73_before: .quad 17,27,12,28
diff73_pairs: .quad 16,17,5,10
diff73_payload0: .ascii "X\n"
diff73_payload1: .ascii "😃\nX"
diff73_edits:
    .quad 4,23,diff73_payload0,2
    .quad 23,23,diff73_payload1,6
diff74_source: .ascii "𐐀!\n𐐀a!𐐀b!ébaé!\nbé"
diff74_after: .ascii "𐐀!ΩΩ\nYY𐐀b!ébaé!\né"
diff74_before: .quad 11,12,12,21
diff74_pairs: .quad 20,16,16,10,16,25,28,0
diff74_payload0: .ascii "ΩΩ"
diff74_payload1: .ascii "YY"
diff74_payload2: .ascii ""
diff74_edits:
    .quad 5,5,diff74_payload0,4
    .quad 6,12,diff74_payload1,2
    .quad 26,27,diff74_payload2,0
diff75_source: .ascii "é!béba\n\nβ!\n𐐀\né\naβ\n\né!a"
diff75_after: .ascii "é!béba\n\nβ!\n𐐀\né\naβ\n\né!a"
diff75_before: .quad 3,18
diff75_pairs: .quad 5,0
diff75_edits:
diff76_source: .ascii "é\nééabaβ!βéabé!é𐐀ab"
diff76_after: .ascii "\nXΩ\nβ!βéXΩ\na\nXbé!\nYé𐐀a\nΩY😃Yb"
diff76_before: .quad 2,5,24,8,24,19,5,15
diff76_pairs: .quad 1,5,16,19
diff76_payload0: .ascii "\nXΩ\n"
diff76_payload1: .ascii ""
diff76_payload2: .ascii "XΩ\n"
diff76_payload3: .ascii "\nX"
diff76_payload4: .ascii "\nY"
diff76_payload5: .ascii "\nΩY😃Y"
diff76_edits:
    .quad 0,2,diff76_payload0,5
    .quad 2,10,diff76_payload1,0
    .quad 17,17,diff76_payload2,4
    .quad 18,18,diff76_payload3,2
    .quad 22,22,diff76_payload4,2
    .quad 29,29,diff76_payload5,9
diff77_source: .ascii "éa\nb\nba"
diff77_after: .ascii "éa\nb\nbXa\n"
diff77_before: .quad 2,5,4,7,3,7,0,3
diff77_pairs: .quad 6,8,4,6
diff77_payload0: .ascii "X"
diff77_payload1: .ascii "\n"
diff77_edits:
    .quad 7,7,diff77_payload0,1
    .quad 8,8,diff77_payload1,1
diff78_source: .ascii "béβ!!β\nβbb"
diff78_after: .ascii "\nbXX😃Xéβ!XXY😃Ω\n\nX"
diff78_before: .quad 10,0,6,3,3,1
diff78_pairs: .quad 7,21,2,2
diff78_payload0: .ascii "\n"
diff78_payload1: .ascii "XX😃X"
diff78_payload2: .ascii "XXY😃Ω"
diff78_payload3: .ascii "\n\nX"
diff78_edits:
    .quad 0,0,diff78_payload0,1
    .quad 1,1,diff78_payload1,7
    .quad 6,9,diff78_payload2,9
    .quad 9,14,diff78_payload3,3
diff79_source: .ascii "bbβ\n𐐀βébbβ𐐀"
diff79_after: .ascii "bb𐐀βébbβ𐐀"
diff79_before: .quad 11,2,11,4,11,17,2,13
diff79_pairs: .quad 1,11,1,12
diff79_payload0: .ascii ""
diff79_payload1: .ascii ""
diff79_edits:
    .quad 2,4,diff79_payload0,0
    .quad 4,5,diff79_payload1,0
diff80_source: .ascii "aé𐐀𐐀"
diff80_after: .ascii "aXé😃Y😃"
diff80_before: .quad 1,0
diff80_pairs: .quad 1,9,9,8,9,4
diff80_payload0: .ascii "X"
diff80_payload1: .ascii "😃Y😃"
diff80_payload2: .ascii ""
diff80_edits:
    .quad 1,1,diff80_payload0,1
    .quad 3,7,diff80_payload1,9
    .quad 7,11,diff80_payload2,0
diff81_source: .ascii "ébéaabababaé"
diff81_after: .ascii "ébaΩ😃\nXYabX😃Ω\nΩaΩbΩYabaéX"
diff81_before: .quad 0,8,13,7
diff81_pairs: .quad 21,16
diff81_payload0: .ascii ""
diff81_payload1: .ascii "Ω😃\nXY"
diff81_payload2: .ascii "X😃Ω\nΩ"
diff81_payload3: .ascii "Ω"
diff81_payload4: .ascii "ΩY"
diff81_payload5: .ascii "X"
diff81_edits:
    .quad 3,5,diff81_payload0,0
    .quad 6,6,diff81_payload1,9
    .quad 8,8,diff81_payload2,10
    .quad 9,9,diff81_payload3,2
    .quad 10,10,diff81_payload4,3
    .quad 15,15,diff81_payload5,1
diff82_source: .ascii "β𐐀b\n𐐀βba\nβββ!é!\n"
diff82_after: .ascii "β𐐀b\nXY\nββΩ😃😃YX\n"
diff82_before: .quad 2,8,19,17,28,21,21,26
diff82_pairs: .quad 26,13
diff82_payload0: .ascii "XY"
diff82_payload1: .ascii "Ω😃😃YX"
diff82_edits:
    .quad 8,16,diff82_payload0,2
    .quad 21,27,diff82_payload1,12
diff83_source: .ascii "\n𐐀𐐀!b\nbb"
diff83_after: .ascii "\n𐐀𐐀!b\nbb"
diff83_before: .quad 12,0,11,11,13,10,14,14
diff83_pairs: .quad 0,13
diff83_edits:
diff84_source: .ascii "\na!aa𐐀b!"
diff84_after: .ascii "\na!Ω😃Y😃XaXYb\nXΩ!\nΩXY"
diff84_before: .quad 1,9,3,10,5,2
diff84_pairs: .quad 7,2,18,27
diff84_payload0: .ascii "Ω😃Y😃"
diff84_payload1: .ascii "X"
diff84_payload2: .ascii "X"
diff84_payload3: .ascii "Y"
diff84_payload4: .ascii "\nXΩ"
diff84_payload5: .ascii "\nΩXY"
diff84_edits:
    .quad 3,4,diff84_payload0,11
    .quad 4,4,diff84_payload1,1
    .quad 5,9,diff84_payload2,1
    .quad 9,9,diff84_payload3,1
    .quad 10,10,diff84_payload4,4
    .quad 11,11,diff84_payload5,5
diff85_source: .ascii "β!βaβ𐐀βbaβé!𐐀bβb𐐀"
diff85_after: .ascii "β!βaβ𐐀βba😃ΩYΩ😃Ωβ𐐀"
diff85_before: .quad 0,20,0,21,12,12,14,25,28,2
diff85_pairs: .quad 25,20
diff85_payload0: .ascii "😃ΩY"
diff85_payload1: .ascii ""
diff85_payload2: .ascii "Ω😃Ω"
diff85_payload3: .ascii ""
diff85_edits:
    .quad 16,18,diff85_payload0,7
    .quad 18,21,diff85_payload1,0
    .quad 21,26,diff85_payload2,8
    .quad 28,29,diff85_payload3,0
diff86_source: .ascii "𐐀!βaβ!\nβéaa𐐀𐐀𐐀aaéa𐐀ébβ\n𐐀\n"
diff86_after: .ascii "𐐀!βaβXΩ😃\nYYXXΩβéaa𐐀𐐀𐐀aaéa𐐀ébβ\n𐐀\n"
diff86_before: .quad 12,22
diff86_pairs: .quad 17,17,57,42
diff86_payload0: .ascii "XΩ😃"
diff86_payload1: .ascii "YYXXΩ"
diff86_edits:
    .quad 10,11,diff86_payload0,7
    .quad 12,12,diff86_payload1,6
diff87_source: .ascii "é𐐀bé!β\né𐐀a\nββaa!a"
diff87_after: .ascii "é𐐀\n😃βX\n\n\nXY\n😃\nYββaa!X\nXΩ😃\nXXΩ"
diff87_before: .quad 12,7
diff87_pairs: .quad 40,47,36,33,14,36,43,32,31,31
diff87_payload0: .ascii "\n😃"
diff87_payload1: .ascii "X"
diff87_payload2: .ascii "\n\nXY\n"
diff87_payload3: .ascii "😃\nY"
diff87_payload4: .ascii "X\nXΩ"
diff87_payload5: .ascii "😃\nXXΩ"
diff87_edits:
    .quad 6,10,diff87_payload0,5
    .quad 12,12,diff87_payload1,1
    .quad 13,21,diff87_payload2,5
    .quad 21,21,diff87_payload3,6
    .quad 28,29,diff87_payload4,5
    .quad 29,29,diff87_payload5,9
diff88_source: .ascii "b\n𐐀ββa!\na\n𐐀βéa"
diff88_after: .ascii "b\n𐐀ββa!\na\n𐐀βéa"
diff88_before: .quad 2,10,0,14,24,19,24,13
diff88_pairs: .quad 12,11,14,15,0,21
diff88_edits:
diff89_source: .ascii "aa\n!"
diff89_after: .ascii "X\nYa😃aX\n😃!X"
diff89_before: .quad 2,0,1,4
diff89_pairs: .quad 17,0,17,2
diff89_payload0: .ascii "X\nY"
diff89_payload1: .ascii "😃"
diff89_payload2: .ascii ""
diff89_payload3: .ascii "X\n😃"
diff89_payload4: .ascii "X"
diff89_edits:
    .quad 0,0,diff89_payload0,3
    .quad 1,1,diff89_payload1,4
    .quad 2,3,diff89_payload2,0
    .quad 3,3,diff89_payload3,6
    .quad 4,4,diff89_payload4,1
diff90_source: .ascii "𐐀!é𐐀\n!\n"
diff90_after: .ascii "𐐀!é𐐀\n!XY\nΩ😃\nΩ"
diff90_before: .quad 7,5
diff90_pairs: .quad 1,18,25,12,11,7,4,13
diff90_payload0: .ascii "XY"
diff90_payload1: .ascii "\nΩ😃\nΩ"
diff90_edits:
    .quad 13,14,diff90_payload0,2
    .quad 14,14,diff90_payload1,10
diff91_source: .ascii "bb!\nβbβ!!!éβé𐐀é"
diff91_after: .ascii "bb!\nβbβ!!!éβé𐐀é"
diff91_before: .quad 9,2,2,1,1,2,18,18
diff91_pairs: .quad 7,0,4,18,16,16,4,16,18,10
diff91_edits:
diff92_source: .ascii "\naa\nβ"
diff92_after: .ascii "\naa\nβ"
diff92_before: .quad 6,6
diff92_pairs: .quad 0,6,6,3
diff92_edits:
diff93_source: .ascii "!\nβ!aββ\n!é𐐀𐐀β!β"
diff93_after: .ascii "!\nβYXΩ\nYaβ\nXYX😃!Ω😃YYX"
diff93_before: .quad 14,22
diff93_pairs: .quad 27,11,10,30,13,11,28,28
diff93_payload0: .ascii "YXΩ\nY"
diff93_payload1: .ascii ""
diff93_payload2: .ascii "XYX😃"
diff93_payload3: .ascii "Ω😃Y"
diff93_payload4: .ascii "YX"
diff93_edits:
    .quad 4,5,diff93_payload0,6
    .quad 8,10,diff93_payload1,0
    .quad 11,11,diff93_payload2,7
    .quad 12,25,diff93_payload3,7
    .quad 25,27,diff93_payload4,2
diff94_source: .ascii "𐐀\néb"
diff94_after: .ascii "𐐀b"
diff94_before: .quad 8,0,4,8,5,0
diff94_pairs: .quad 5,0,4,4,5,0
diff94_payload0: .ascii ""
diff94_edits:
    .quad 4,7,diff94_payload0,0
diff95_source: .ascii "β!β"
diff95_after: .ascii "X\nβ"
diff95_before: .quad 3,3
diff95_pairs: .quad 1,4,2,4
diff95_payload0: .ascii "X\n"
diff95_edits:
    .quad 0,3,diff95_payload0,2
diff96_source: .ascii "!𐐀\n𐐀\n𐐀\nééaβé"
diff96_after: .ascii "!𐐀\n\nΩXΩX𐐀\nΩéé"
diff96_before: .quad 5,5,25,10,10,1,10,20,23,1
diff96_pairs: .quad 4,5,10,20,9,12
diff96_payload0: .ascii "\nΩXΩX"
diff96_payload1: .ascii "Ω"
diff96_payload2: .ascii ""
diff96_edits:
    .quad 6,6,diff96_payload0,7
    .quad 11,16,diff96_payload1,2
    .quad 20,25,diff96_payload2,0
diff97_source: .ascii "\nβéβ!éβé\nbbβ𐐀é"
diff97_after: .ascii "X\nβéβY😃XΩYXbβYXY\n𐐀ΩYé\n\n😃Ω"
diff97_before: .quad 15,10,0,25,17,25,15,15,16,3
diff97_pairs: .quad 34,14,8,4,23,2
diff97_payload0: .ascii "X"
diff97_payload1: .ascii "Y😃XΩY"
diff97_payload2: .ascii "X"
diff97_payload3: .ascii "YXY\n"
diff97_payload4: .ascii "ΩY"
diff97_payload5: .ascii "\n\n😃Ω"
diff97_edits:
    .quad 0,0,diff97_payload0,1
    .quad 7,14,diff97_payload1,9
    .quad 14,16,diff97_payload2,1
    .quad 19,19,diff97_payload3,4
    .quad 23,23,diff97_payload4,3
    .quad 25,25,diff97_payload5,8
diff98_source: .ascii "β!𐐀βabb𐐀aébb\nβéβ𐐀"
diff98_after: .ascii "β!𐐀βabb𐐀aébb\nX\nXYY\nXéβ𐐀"
diff98_before: .quad 26,10,24,11,26,28,32,24,10,2
diff98_pairs: .quad 33,37,33,21,23,16,10,22
diff98_payload0: .ascii "\nX\nXY"
diff98_payload1: .ascii "Y\nX"
diff98_edits:
    .quad 21,22,diff98_payload0,5
    .quad 22,24,diff98_payload1,3
diff99_source: .ascii "ébbébab!b!𐐀β𐐀\né\n\n!bβ"
diff99_after: .ascii "ébY\nΩ😃XbéYYX𐐀b😃😃Ω😃😃😃\n😃"
diff99_before: .quad 29,16,2,10
diff99_pairs: .quad 14,41,37,3,33,17,37,31,15,4
diff99_payload0: .ascii "Y\nΩ😃X"
diff99_payload1: .ascii "YYX"
diff99_payload2: .ascii ""
diff99_payload3: .ascii "😃😃Ω😃"
diff99_payload4: .ascii "😃😃\n😃"
diff99_edits:
    .quad 3,3,diff99_payload0,9
    .quad 6,18,diff99_payload1,3
    .quad 22,28,diff99_payload2,0
    .quad 29,31,diff99_payload3,14
    .quad 31,31,diff99_payload4,13
diff100_source: .ascii "a𐐀aaééaa\n!\n!!baβbb!"
diff100_after: .ascii "a𐐀aXXaééaa\n😃Y😃\nY😃YX😃ΩXYΩ😃XXΩ😃"
diff100_before: .quad 24,13,14,13,1,19,15,5
diff100_pairs: .quad 31,47,32,8
diff100_payload0: .ascii "XX"
diff100_payload1: .ascii "😃Y😃\nY"
diff100_payload2: .ascii "😃YX😃"
diff100_payload3: .ascii "ΩXY"
diff100_payload4: .ascii "Ω😃"
diff100_payload5: .ascii "XXΩ😃"
diff100_edits:
    .quad 6,6,diff100_payload0,2
    .quad 14,16,diff100_payload1,11
    .quad 16,20,diff100_payload2,10
    .quad 20,24,diff100_payload3,4
    .quad 24,25,diff100_payload4,6
    .quad 25,25,diff100_payload5,8
diff101_source: .ascii "!b\né!βa𐐀é𐐀\nβé"
diff101_after: .ascii "!b\né!βY\nYa𐐀XXΩéY\nYΩX𐐀YYYXX"
diff101_before: .quad 13,3,9,15,1,20,0,8,20,24
diff101_pairs: .quad 25,36,6,2
diff101_payload0: .ascii "Y\nY"
diff101_payload1: .ascii "XXΩ"
diff101_payload2: .ascii "Y\nYΩX"
diff101_payload3: .ascii ""
diff101_payload4: .ascii "YYYXX"
diff101_edits:
    .quad 8,8,diff101_payload0,3
    .quad 13,13,diff101_payload1,4
    .quad 15,15,diff101_payload2,6
    .quad 19,24,diff101_payload3,0
    .quad 24,24,diff101_payload4,5
diff102_source: .ascii "éb𐐀é𐐀a"
diff102_after: .ascii "XéX𐐀aX"
diff102_before: .quad 13,2,7,14
diff102_pairs: .quad 2,0,8,10
diff102_payload0: .ascii ""
diff102_payload1: .ascii ""
diff102_payload2: .ascii "X"
diff102_payload3: .ascii "X"
diff102_payload4: .ascii "X"
diff102_edits:
    .quad 0,2,diff102_payload0,0
    .quad 2,7,diff102_payload1,0
    .quad 7,7,diff102_payload2,1
    .quad 9,9,diff102_payload3,1
    .quad 14,14,diff102_payload4,1
diff103_source: .ascii "abβ!β!a𐐀!bébβb!é𐐀b\nβa"
diff103_after: .ascii "Ω\nΩβb!é\nYYΩYY"
diff103_before: .quad 24,14,8,7,21,9,21,22
diff103_pairs: .quad 2,13
diff103_payload0: .ascii "Ω\nΩ"
diff103_payload1: .ascii "\nY"
diff103_payload2: .ascii "YΩYY"
diff103_edits:
    .quad 0,18,diff103_payload0,5
    .quad 24,32,diff103_payload1,2
    .quad 32,33,diff103_payload2,5
diff104_source: .ascii "aé!𐐀é\naé\n𐐀é\né\na\n𐐀\nβb"
diff104_after: .ascii "Xaé\n\nXΩaé\n𐐀éXΩΩ\n😃Xé\na\n𐐀\nβb"
diff104_before: .quad 1,10,31,4
diff104_pairs: .quad 4,35,5,6
diff104_payload0: .ascii "X"
diff104_payload1: .ascii "\n"
diff104_payload2: .ascii "XΩ"
diff104_payload3: .ascii "XΩΩ\n😃"
diff104_payload4: .ascii "X"
diff104_edits:
    .quad 0,0,diff104_payload0,1
    .quad 3,10,diff104_payload1,1
    .quad 11,11,diff104_payload2,3
    .quad 21,22,diff104_payload3,10
    .quad 22,22,diff104_payload4,1
diff105_source: .ascii "é\n!aβab𐐀aβ𐐀\n𐐀éβb!!ébé!β\n"
diff105_after: .ascii "é\n!aβab𐐀aβ𐐀\n𐐀éβb!!ébé!β\n"
diff105_before: .quad 31,8,3,5,2,41,20,29,27,25
diff105_pairs: .quad 11,16,40,20,32,34,27,37,30,13
diff105_edits:
diff106_source: .ascii "bbβ\naa!!bb𐐀𐐀𐐀aa!\né"
diff106_after: .ascii "bbβb𐐀𐐀XXa\nΩXΩ\né"
diff106_before: .quad 6,2,26,27,1,11,23,4
diff106_pairs: .quad 20,13,5,20,9,2
diff106_payload0: .ascii ""
diff106_payload1: .ascii "XX"
diff106_payload2: .ascii "\nΩXΩ"
diff106_edits:
    .quad 4,10,diff106_payload0,0
    .quad 19,23,diff106_payload1,2
    .quad 24,26,diff106_payload2,6
diff107_source: .ascii "\n!β"
diff107_after: .ascii "Y\n\nΩY😃Y"
diff107_before: .quad 0,2,4,0,1,0
diff107_pairs: .quad 3,0,10,5,5,3
diff107_payload0: .ascii "Y\n"
diff107_payload1: .ascii "\nΩ"
diff107_payload2: .ascii "Y😃Y"
diff107_edits:
    .quad 0,2,diff107_payload0,2
    .quad 2,4,diff107_payload1,3
    .quad 4,4,diff107_payload2,6
diff108_source: .ascii "éβ\nβ\né!\nβ\nb!é\n𐐀β\né"
diff108_after: .ascii "é\nYΩXYβX\nβ\n😃XY\n\nb!\n😃𐐀β\né"
diff108_before: .quad 12,27,0,2,20,2,29,8
diff108_pairs: .quad 9,20,15,39,7,23
diff108_payload0: .ascii "\nYΩXY"
diff108_payload1: .ascii "X"
diff108_payload2: .ascii "😃XY\n"
diff108_payload3: .ascii "\n😃"
diff108_edits:
    .quad 2,2,diff108_payload0,6
    .quad 4,4,diff108_payload1,1
    .quad 8,14,diff108_payload2,7
    .quad 17,20,diff108_payload3,5
diff109_source: .ascii "ééa\n!!éab"
diff109_after: .ascii "Xa😃XΩ\nX!ΩéΩYa\nYb"
diff109_before: .quad 8,8,7,12,10,11,10,5
diff109_pairs: .quad 23,6,18,2
diff109_payload0: .ascii ""
diff109_payload1: .ascii "X"
diff109_payload2: .ascii "😃XΩ\nX"
diff109_payload3: .ascii "Ω"
diff109_payload4: .ascii "ΩY"
diff109_payload5: .ascii "\nY"
diff109_edits:
    .quad 0,4,diff109_payload0,0
    .quad 4,4,diff109_payload1,1
    .quad 5,6,diff109_payload2,9
    .quad 7,8,diff109_payload3,2
    .quad 10,10,diff109_payload4,3
    .quad 11,11,diff109_payload5,2
diff110_source: .ascii "\né\n\nβbβ\n"
diff110_after: .ascii "\né\n😃😃ΩX\nβbβ"
diff110_before: .quad 8,1,5,4,7,11,0,11,3,7
diff110_pairs: .quad 16,12
diff110_payload0: .ascii "😃😃ΩX"
diff110_payload1: .ascii ""
diff110_edits:
    .quad 4,4,diff110_payload0,11
    .quad 10,11,diff110_payload1,0
diff111_source: .ascii "aββébβéb𐐀𐐀\n"
diff111_after: .ascii "aββébβébΩ😃\nYXXX"
diff111_before: .quad 17,10,5,8,5,21,22,10
diff111_pairs: .quad 18,22,24,24
diff111_payload0: .ascii "Ω😃"
diff111_payload1: .ascii "\nYXXX"
diff111_edits:
    .quad 13,22,diff111_payload0,6
    .quad 22,22,diff111_payload1,5
diff112_source: .ascii "β\n!b𐐀éb𐐀β!βaa!aé\nbβ𐐀b"
diff112_after: .ascii "β\n!b𐐀éb𐐀β!βaa!aé\nbβ𐐀b"
diff112_before: .quad 0,23,9,22,29,36,3,11,4,2
diff112_pairs: .quad 27,3,21,18
diff112_edits:
diff113_source: .ascii "!a𐐀éβ!"
diff113_after: .ascii "!\nYaΩY\n😃😃β😃Y!YY"
diff113_before: .quad 11,8
diff113_pairs: .quad 4,26
diff113_payload0: .ascii "\nY"
diff113_payload1: .ascii "ΩY"
diff113_payload2: .ascii "\n😃😃"
diff113_payload3: .ascii "😃Y"
diff113_payload4: .ascii "YY"
diff113_edits:
    .quad 1,1,diff113_payload0,2
    .quad 2,6,diff113_payload1,3
    .quad 6,8,diff113_payload2,9
    .quad 10,10,diff113_payload3,5
    .quad 11,11,diff113_payload4,2
diff114_source: .ascii "é!ééβ𐐀\n!\n𐐀!!éb𐐀bb𐐀éaé𐐀"
diff114_after: .ascii "é!ééβ𐐀\n!\n𐐀!!éb𐐀bb𐐀éaé𐐀"
diff114_before: .quad 20,24,13,38
diff114_pairs: .quad 36,0,15,31,24,22,38,30,15,16
diff114_edits:
diff115_source: .ascii "!bé𐐀𐐀!aβbaaβb!\nβ"
diff115_after: .ascii "!bé𐐀𐐀!aβbaaβXb!β"
diff115_before: .quad 12,17,21,26,24,23
diff115_pairs: .quad 4,24
diff115_payload0: .ascii "X"
diff115_payload1: .ascii ""
diff115_edits:
    .quad 21,21,diff115_payload0,1
    .quad 23,24,diff115_payload1,0
diff116_source: .ascii "bβbab\néaabééé\nβ"
diff116_after: .ascii "Ω\nXba😃Ω😃YéaaΩX\nbéééXβ"
diff116_before: .quad 21,21,14,1,11,16,12,10
diff116_pairs: .quad 21,2,26,19,32,23,16,4
diff116_payload0: .ascii "Ω\nX"
diff116_payload1: .ascii ""
diff116_payload2: .ascii "😃Ω😃Y"
diff116_payload3: .ascii "ΩX\n"
diff116_payload4: .ascii "X"
diff116_edits:
    .quad 0,1,diff116_payload0,4
    .quad 1,3,diff116_payload1,0
    .quad 5,7,diff116_payload2,11
    .quad 11,11,diff116_payload3,4
    .quad 18,19,diff116_payload4,1
diff117_source: .ascii "é!a𐐀β\né𐐀éβé𐐀éβ!𐐀"
diff117_after: .ascii "Xé!a𐐀β\nX😃X𐐀éβΩéΩβ!𐐀"
diff117_before: .quad 8,23,2,29
diff117_pairs: .quad 31,17,11,30,17,5
diff117_payload0: .ascii "X"
diff117_payload1: .ascii "X😃X"
diff117_payload2: .ascii "Ω"
diff117_payload3: .ascii "Ω"
diff117_edits:
    .quad 0,0,diff117_payload0,1
    .quad 11,13,diff117_payload1,6
    .quad 21,21,diff117_payload2,2
    .quad 23,29,diff117_payload3,2
diff118_source: .ascii "\n𐐀aa\n𐐀é!!\nba!aβb\n"
diff118_after: .ascii "\n𐐀Y😃bX!aβbYX😃Ω\n"
diff118_before: .quad 17,23,7,23,23,7,16,16,0,15
diff118_pairs: .quad 1,13,13,10
diff118_payload0: .ascii "Y😃"
diff118_payload1: .ascii "X"
diff118_payload2: .ascii "YX😃Ω"
diff118_edits:
    .quad 5,17,diff118_payload0,5
    .quad 18,19,diff118_payload1,1
    .quad 24,24,diff118_payload2,8
diff119_source: .ascii "b!b!β𐐀\naé𐐀!"
diff119_after: .ascii "aé𐐀!"
diff119_before: .quad 3,1,12,3,1,12,3,3
diff119_pairs: .quad 3,1,1,0,3,0,8,3,1,1
diff119_payload0: .ascii ""
diff119_edits:
    .quad 0,11,diff119_payload0,0
diff120_source: .ascii "β!βé\n\né!\né\né𐐀𐐀"
diff120_after: .ascii "β!βé😃\n😃YY\né😃\n😃YY𐐀"
diff120_before: .quad 0,0,0,18,7,13,13,13,7,9
diff120_pairs: .quad 35,7,26,0,25,2,30,7
diff120_payload0: .ascii "😃\n😃YY"
diff120_payload1: .ascii ""
diff120_payload2: .ascii ""
diff120_payload3: .ascii "😃\n😃Y"
diff120_payload4: .ascii "Y"
diff120_edits:
    .quad 7,8,diff120_payload0,11
    .quad 11,12,diff120_payload1,0
    .quad 12,13,diff120_payload2,0
    .quad 13,18,diff120_payload3,10
    .quad 18,22,diff120_payload4,1
diff121_source: .ascii "é!\na"
diff121_after: .ascii "😃éΩXΩΩY😃ΩYXY"
diff121_before: .quad 4,3,5,4,4,0,0,2,4,0
diff121_pairs: .quad 14,8,23,21,11,22,0,11,22,11
diff121_payload0: .ascii "😃"
diff121_payload1: .ascii "ΩXΩΩY"
diff121_payload2: .ascii "😃ΩY"
diff121_payload3: .ascii ""
diff121_payload4: .ascii "XY"
diff121_edits:
    .quad 0,0,diff121_payload0,4
    .quad 2,3,diff121_payload1,8
    .quad 3,4,diff121_payload2,7
    .quad 4,5,diff121_payload3,0
    .quad 5,5,diff121_payload4,2
diff122_source: .ascii "b\n!éβ\n\n\n\nbaaéaéβb𐐀é\n"
diff122_after: .ascii "b\n!éβ\n\n\n\nbaaéaéβb𐐀é\n"
diff122_before: .quad 3,8,11,29
diff122_pairs: .quad 7,29,2,14
diff122_edits:
diff123_source: .ascii "!𐐀!βbé!\n\n𐐀bba!éa!!b𐐀"
diff123_after: .ascii "!𐐀!βbé!\n\n𐐀bba😃YX!b𐐀"
diff123_before: .quad 26,21
diff123_pairs: .quad 7,5,18,19
diff123_payload0: .ascii "😃YX"
diff123_edits:
    .quad 21,26,diff123_payload0,6
diff124_source: .ascii "éé\nb\nβa𐐀é𐐀βé𐐀b𐐀éb\na!\nβ"
diff124_after: .ascii "éé\nb\nβaX𐐀é𐐀XΩX\na!\nβ"
diff124_before: .quad 33,35
diff124_pairs: .quad 4,15,17,24,5,27,10,25
diff124_payload0: .ascii "X"
diff124_payload1: .ascii "XΩX"
diff124_edits:
    .quad 10,10,diff124_payload0,1
    .quad 20,36,diff124_payload1,4
diff125_source: .ascii "𐐀!𐐀𐐀éé"
diff125_after: .ascii "𐐀XΩéé"
diff125_before: .quad 15,5,4,17,4,0,15,9
diff125_pairs: .quad 5,11,7,0,7,5,5,5,9,5
diff125_payload0: .ascii "X"
diff125_payload1: .ascii "Ω"
diff125_edits:
    .quad 4,9,diff125_payload0,1
    .quad 9,13,diff125_payload1,2
diff126_source: .ascii "!é𐐀!β!b𐐀𐐀"
diff126_after: .ascii "\nβXΩYbYΩYY𐐀\n\nY𐐀"
diff126_before: .quad 8,7,1,7,1,20,3,11,7,12
diff126_pairs: .quad 21,0,3,11
diff126_payload0: .ascii "\n"
diff126_payload1: .ascii "XΩY"
diff126_payload2: .ascii "YΩYY"
diff126_payload3: .ascii "\n\nY"
diff126_edits:
    .quad 0,8,diff126_payload0,1
    .quad 10,11,diff126_payload1,4
    .quad 12,12,diff126_payload2,5
    .quad 16,16,diff126_payload3,3
diff127_source: .ascii "éβ!a!éβa"
diff127_after: .ascii "éβ!a!éβa\n😃\n"
diff127_before: .quad 5,11,6,0,12,6,2,6
diff127_pairs: .quad 4,6,2,6,18,0,0,9,5,4
diff127_payload0: .ascii "\n😃\n"
diff127_edits:
    .quad 12,12,diff127_payload0,6
diff128_source: .ascii "ébé\n"
diff128_after: .ascii "éXbéX\n"
diff128_before: .quad 0,6
diff128_pairs: .quad 4,4,7,6,7,7,4,6,7,3
diff128_payload0: .ascii "X"
diff128_payload1: .ascii "X"
diff128_edits:
    .quad 2,2,diff128_payload0,1
    .quad 5,5,diff128_payload1,1
diff129_source: .ascii "!\nββb\n𐐀béβ!𐐀aβ𐐀b!!!β!aβbé"
diff129_after: .ascii "!\nββb\n𐐀béβ!𐐀aβ𐐀b!!!β!aβbé"
diff129_before: .quad 36,39
diff129_pairs: .quad 24,12,8,30,32,17,37,39,0,1
diff129_edits:
diff130_source: .ascii "b!𐐀é𐐀b!!bβééβ\n!b"
diff130_after: .ascii "b!𐐀é𐐀b!!bβééβ\n!b"
diff130_before: .quad 8,26,16,2,12,25,25,20,20,12
diff130_pairs: .quad 6,0,6,15
diff130_edits:
diff131_source: .ascii "b!\n𐐀é\nb\néββ𐐀\néβ𐐀!\nabβ"
diff131_after: .ascii "b!\né\n\nb\n\n\n😃ΩX😃Y"
diff131_before: .quad 10,11,12,27,22,10,32,3,3,32
diff131_pairs: .quad 2,17,0,10,2,1,23,7
diff131_payload0: .ascii ""
diff131_payload1: .ascii "\n"
diff131_payload2: .ascii ""
diff131_payload3: .ascii "\n\n\n"
diff131_payload4: .ascii "😃ΩX😃Y"
diff131_edits:
    .quad 3,7,diff131_payload0,0
    .quad 10,11,diff131_payload1,1
    .quad 11,34,diff131_payload2,0
    .quad 35,37,diff131_payload3,3
    .quad 37,37,diff131_payload4,12
diff132_source: .ascii "\néaβé𐐀\néaé!é!𐐀éé\nβ\n!é𐐀!b"
diff132_after: .ascii "\nY\n😃Y😃😃Y!𐐀éé\nβ😃\nΩ"
diff132_before: .quad 42,19,18,31
diff132_pairs: .quad 30,17,1,22,26,22,7,26,26,36
diff132_payload0: .ascii "Y\n😃"
diff132_payload1: .ascii "Y😃😃Y"
diff132_payload2: .ascii "😃\nΩ"
diff132_edits:
    .quad 1,16,diff132_payload0,6
    .quad 16,21,diff132_payload1,10
    .quad 33,43,diff132_payload2,7
diff133_source: .ascii "b𐐀\né"
diff133_after: .ascii "YXYXXb\n😃\né\nY😃Ω"
diff133_before: .quad 8,5,5,8,1,0,6,0,0,1
diff133_pairs: .quad 5,16,0,12,11,5,12,5,4,14
diff133_payload0: .ascii "YXYXX"
diff133_payload1: .ascii "\n😃"
diff133_payload2: .ascii "\nY😃Ω"
diff133_edits:
    .quad 0,0,diff133_payload0,5
    .quad 1,5,diff133_payload1,5
    .quad 8,8,diff133_payload2,8
diff134_source: .ascii "\n\nabaβéb!bβ\nbé"
diff134_after: .ascii "\n\nab😃\nΩ😃aβébX\n😃😃YYbβ\nbé"
diff134_before: .quad 3,7,15,0
diff134_pairs: .quad 16,31,36,36,1,27,34,40,9,27
diff134_payload0: .ascii "😃\nΩ😃"
diff134_payload1: .ascii "X\n😃😃"
diff134_payload2: .ascii "YY"
diff134_edits:
    .quad 4,4,diff134_payload0,11
    .quad 10,11,diff134_payload1,10
    .quad 11,11,diff134_payload2,2
diff135_source: .ascii "!!bb𐐀"
diff135_after: .ascii "X😃Ω😃\n!X\nYYX\nb\nb\n😃Y😃YX"
diff135_before: .quad 3,2,3,2
diff135_pairs: .quad 25,32
diff135_payload0: .ascii "X😃Ω😃\n"
diff135_payload1: .ascii "X\n"
diff135_payload2: .ascii "YYX\n"
diff135_payload3: .ascii "\n"
diff135_payload4: .ascii "\n😃Y"
diff135_payload5: .ascii "😃YX"
diff135_edits:
    .quad 0,0,diff135_payload0,12
    .quad 1,2,diff135_payload1,2
    .quad 2,2,diff135_payload2,4
    .quad 3,3,diff135_payload3,1
    .quad 4,8,diff135_payload4,6
    .quad 8,8,diff135_payload5,6
diff136_source: .ascii "\nβé𐐀bβé!ab!𐐀\n\néb\n\n𐐀βbé"
diff136_after: .ascii "\nβY\nXé!Xab!𐐀YX\nY\n𐐀βbé"
diff136_before: .quad 33,35,10,23
diff136_pairs: .quad 6,22,8,26
diff136_payload0: .ascii "Y\n"
diff136_payload1: .ascii "X"
diff136_payload2: .ascii "X"
diff136_payload3: .ascii "Y"
diff136_payload4: .ascii "X\nY"
diff136_edits:
    .quad 3,9,diff136_payload0,2
    .quad 9,12,diff136_payload1,1
    .quad 15,15,diff136_payload2,1
    .quad 22,28,diff136_payload3,1
    .quad 28,28,diff136_payload4,3
diff137_source: .ascii "\n!\n\nba\n𐐀ββ"
diff137_after: .ascii "\n!😃\n\nΩΩ\nΩX\nΩX😃a\n𐐀ββ"
diff137_before: .quad 0,5,13,5,3,15
diff137_pairs: .quad 7,16,26,7,2,26,32,13
diff137_payload0: .ascii "😃"
diff137_payload1: .ascii "ΩΩ\nΩ"
diff137_payload2: .ascii "X\nΩX😃"
diff137_edits:
    .quad 2,2,diff137_payload0,4
    .quad 4,5,diff137_payload1,7
    .quad 5,5,diff137_payload2,9
diff138_source: .ascii "a\na𐐀β𐐀\nabé𐐀"
diff138_after: .ascii "Y\n😃YXYΩY😃Ωé𐐀"
diff138_before: .quad 13,18
diff138_pairs: .quad 19,24,11,16,24,24
diff138_payload0: .ascii "Y\n😃"
diff138_payload1: .ascii "YXY"
diff138_payload2: .ascii "ΩY😃Ω"
diff138_edits:
    .quad 0,1,diff138_payload0,6
    .quad 1,7,diff138_payload1,3
    .quad 7,16,diff138_payload2,9
diff139_source: .ascii "\n\n\nbba!!aa"
diff139_after: .ascii "\n\n\n😃b😃\nΩ\n\nY\nX!!Y😃Ωa😃"
diff139_before: .quad 2,9
diff139_pairs: .quad 17,34,17,15,8,30,29,3,13,18
diff139_payload0: .ascii "😃"
diff139_payload1: .ascii "😃\nΩ\n\n"
diff139_payload2: .ascii "Y\nX"
diff139_payload3: .ascii "Y😃Ω"
diff139_payload4: .ascii "😃"
diff139_edits:
    .quad 3,3,diff139_payload0,4
    .quad 4,5,diff139_payload1,9
    .quad 5,6,diff139_payload2,3
    .quad 8,8,diff139_payload3,7
    .quad 9,10,diff139_payload4,4
diff140_source: .ascii "\na\nβa!\n!β!é"
diff140_after: .ascii "a\nβa😃\nY!😃\n\nY😃XΩYXX"
diff140_before: .quad 0,0,8,12
diff140_pairs: .quad 1,5,4,26,28,9,16,11,19,27
diff140_payload0: .ascii ""
diff140_payload1: .ascii "😃\nY"
diff140_payload2: .ascii "😃\n\nY"
diff140_payload3: .ascii "😃"
diff140_payload4: .ascii "XΩYXX"
diff140_edits:
    .quad 0,1,diff140_payload0,0
    .quad 6,6,diff140_payload1,6
    .quad 7,8,diff140_payload2,7
    .quad 8,14,diff140_payload3,4
    .quad 14,14,diff140_payload4,6
diff141_source: .ascii "b!bb\n𐐀𐐀𐐀"
diff141_after: .ascii "b\n😃XY\n😃bX\n𐐀"
diff141_before: .quad 5,13,13,9,2,13
diff141_pairs: .quad 4,0,15,9,8,20,14,20,8,13
diff141_payload0: .ascii "\n"
diff141_payload1: .ascii "😃XY\n😃"
diff141_payload2: .ascii "X\n"
diff141_payload3: .ascii ""
diff141_edits:
    .quad 1,2,diff141_payload0,1
    .quad 2,2,diff141_payload1,11
    .quad 3,4,diff141_payload2,2
    .quad 4,13,diff141_payload3,0
diff142_source: .ascii "bééééa"
diff142_after: .ascii "béééΩΩ"
diff142_before: .quad 0,9,0,7
diff142_pairs: .quad 9,5,5,7
diff142_payload0: .ascii ""
diff142_payload1: .ascii "ΩΩ"
diff142_edits:
    .quad 1,3,diff142_payload0,0
    .quad 9,10,diff142_payload1,4
diff143_source: .ascii "β𐐀𐐀éab!éβaéé𐐀ab"
diff143_after: .ascii "β𐐀𐐀éab!éβaéé𐐀ab"
diff143_before: .quad 20,28,17,24,24,6
diff143_pairs: .quad 17,6
diff143_edits:
diff144_source: .ascii "βa\n𐐀βa!é\na\nβ!𐐀a𐐀"
diff144_after: .ascii "βa\n𐐀βa!é\na\nβ!𐐀a𐐀"
diff144_before: .quad 16,3,4,24
diff144_pairs: .quad 13,20,20,14
diff144_edits:
diff145_source: .ascii "𐐀abéa!"
diff145_after: .ascii "𐐀aΩX😃Ω!"
diff145_before: .quad 0,8,0,5
diff145_pairs: .quad 12,8,4,7
diff145_payload0: .ascii "ΩX😃"
diff145_payload1: .ascii "Ω"
diff145_edits:
    .quad 5,8,diff145_payload0,7
    .quad 8,9,diff145_payload1,2
diff146_source: .ascii "aéaé\n𐐀"
diff146_after: .ascii "aéaé"
diff146_before: .quad 6,1,6,4,6,3,0,11
diff146_pairs: .quad 3,1
diff146_payload0: .ascii ""
diff146_edits:
    .quad 6,11,diff146_payload0,0
diff147_source: .ascii "𐐀é!ébaé𐐀a!β𐐀\n\na"
diff147_after: .ascii "𐐀\nXé😃😃ébaé𐐀a!β𐐀X😃Ω😃Ω\na"
diff147_before: .quad 28,6
diff147_pairs: .quad 36,22,35,5,28,22
diff147_payload0: .ascii "\nX"
diff147_payload1: .ascii "😃😃"
diff147_payload2: .ascii "X😃Ω😃Ω"
diff147_edits:
    .quad 4,4,diff147_payload0,2
    .quad 6,7,diff147_payload1,8
    .quad 25,26,diff147_payload2,13
diff148_source: .ascii "\n𐐀𐐀𐐀!β\nβ\n\n!!abβ!!!𐐀b\n"
diff148_after: .ascii "\n𐐀𐐀!β\nβ\n\nYY!!a\n\n\n!!bX\n"
diff148_before: .quad 20,23
diff148_pairs: .quad 30,22,12,21
diff148_payload0: .ascii ""
diff148_payload1: .ascii "YY"
diff148_payload2: .ascii "\n\n\n"
diff148_payload3: .ascii ""
diff148_payload4: .ascii "X"
diff148_edits:
    .quad 9,13,diff148_payload0,0
    .quad 21,21,diff148_payload1,2
    .quad 24,27,diff148_payload2,3
    .quad 29,34,diff148_payload3,0
    .quad 35,35,diff148_payload4,1
diff149_source: .ascii "aββbβéb𐐀"
diff149_after: .ascii "a😃Y\nbβ\nX😃ΩY"
diff149_before: .quad 6,15,3,10,3,11,5,10
diff149_pairs: .quad 1,11,7,11,1,5,12,19,1,18
diff149_payload0: .ascii "😃Y\n"
diff149_payload1: .ascii "\nX"
diff149_payload2: .ascii "😃ΩY"
diff149_edits:
    .quad 1,5,diff149_payload0,6
    .quad 8,11,diff149_payload1,2
    .quad 11,15,diff149_payload2,7
diff150_source: .ascii "é\nβ!!é\n!bé"
diff150_after: .ascii "é\nβ!!é\n!bé😃😃"
diff150_before: .quad 10,6,11,9
diff150_pairs: .quad 16,18,7,14
diff150_payload0: .ascii "😃😃"
diff150_edits:
    .quad 14,14,diff150_payload0,8
diff151_source: .ascii "ba𐐀β!𐐀ba!𐐀β\nββéaβ\n𐐀é"
diff151_after: .ascii "aXYYΩX𐐀😃Ω\n\nY"
diff151_before: .quad 29,20,9,25,0,29,8,8,20,23
diff151_pairs: .quad 6,2,6,3
diff151_payload0: .ascii ""
diff151_payload1: .ascii ""
diff151_payload2: .ascii "XYYΩ"
diff151_payload3: .ascii "X"
diff151_payload4: .ascii "😃Ω\n\nY"
diff151_edits:
    .quad 0,2,diff151_payload0,0
    .quad 2,29,diff151_payload1,0
    .quad 30,33,diff151_payload2,5
    .quad 33,33,diff151_payload3,1
    .quad 37,39,diff151_payload4,9
diff152_source: .ascii "éé\n!𐐀b"
diff152_after: .ascii "😃é😃😃😃😃é\n!𐐀b"
diff152_before: .quad 5,6,10,5,5,2
diff152_pairs: .quad 30,26,14,0,31,31
diff152_payload0: .ascii "😃"
diff152_payload1: .ascii "😃😃😃😃"
diff152_edits:
    .quad 0,0,diff152_payload0,4
    .quad 2,2,diff152_payload1,16
diff153_source: .ascii "!βébβabééééβéβaéβb"
diff153_after: .ascii "!βébβabé😃éYXéΩXXβaéXX😃\n\nβb"
diff153_before: .quad 27,30
diff153_pairs: .quad 13,16
diff153_payload0: .ascii "😃"
diff153_payload1: .ascii "YX"
diff153_payload2: .ascii "ΩXX"
diff153_payload3: .ascii "XX😃\n\n"
diff153_edits:
    .quad 12,12,diff153_payload0,4
    .quad 14,14,diff153_payload1,2
    .quad 16,22,diff153_payload2,4
    .quad 27,27,diff153_payload3,8
diff154_source: .ascii "!éβ\n𐐀bb𐐀ébééé𐐀b"
diff154_after: .ascii "ΩYYYYΩYXXΩéééXXΩXXb"
diff154_before: .quad 25,12,16,19,25,23,6,0
diff154_pairs: .quad 9,9
diff154_payload0: .ascii "ΩYYYY"
diff154_payload1: .ascii "ΩYXXΩ"
diff154_payload2: .ascii ""
diff154_payload3: .ascii ""
diff154_payload4: .ascii "XXΩXX"
diff154_edits:
    .quad 0,1,diff154_payload0,6
    .quad 1,3,diff154_payload1,7
    .quad 3,6,diff154_payload2,0
    .quad 6,19,diff154_payload3,0
    .quad 25,29,diff154_payload4,6
diff155_source: .ascii "é\nb𐐀b\naa𐐀!b!é𐐀β\n\n!𐐀b"
diff155_after: .ascii "é\nb𐐀b\naa𐐀!b!é𐐀β\n\n!𐐀b"
diff155_before: .quad 11,3
diff155_pairs: .quad 30,16,3,12
diff155_edits:
diff156_source: .ascii "\n𐐀\na𐐀"
diff156_after: .ascii "\n😃😃YΩ\na\n𐐀YX"
diff156_before: .quad 7,7,0,6,5,6,6,1,0,6
diff156_pairs: .quad 3,20,21,21,9,20
diff156_payload0: .ascii "😃"
diff156_payload1: .ascii "😃YΩ"
diff156_payload2: .ascii "\n"
diff156_payload3: .ascii "YX"
diff156_edits:
    .quad 1,5,diff156_payload0,4
    .quad 5,5,diff156_payload1,7
    .quad 7,7,diff156_payload2,1
    .quad 11,11,diff156_payload3,2
diff157_source: .ascii "ββ!éé\n\n!𐐀!!b\né!b"
diff157_after: .ascii "ββ!éé\nX\n!\nb\néX\n😃😃"
diff157_before: .quad 23,5,10,4,7,11,23,0,2,12
diff157_pairs: .quad 15,28,13,7,20,15
diff157_payload0: .ascii "X\n"
diff157_payload1: .ascii "\n"
diff157_payload2: .ascii ""
diff157_payload3: .ascii "X\n😃😃"
diff157_edits:
    .quad 10,17,diff157_payload0,2
    .quad 18,18,diff157_payload1,1
    .quad 22,23,diff157_payload2,0
    .quad 23,24,diff157_payload3,10
diff158_source: .ascii "aa!"
diff158_after: .ascii "aa!"
diff158_before: .quad 0,0
diff158_pairs: .quad 0,3
diff158_edits:
diff159_source: .ascii "!!!!β𐐀abββéé!éb𐐀!aébéβb!"
diff159_after: .ascii "!!!!β𐐀abββé!ΩΩ\n\nbéβb!"
diff159_before: .quad 37,37,37,30,3,11,32,10
diff159_pairs: .quad 27,10,2,19,28,2,16,2,19,3
diff159_payload0: .ascii ""
diff159_payload1: .ascii "ΩΩ\n\n"
diff159_edits:
    .quad 18,28,diff159_payload0,0
    .quad 29,32,diff159_payload1,6
diff160_source: .ascii "\né\n"
diff160_after: .ascii "\n\n\nXX\nΩ\nX"
diff160_before: .quad 4,1,0,4
diff160_pairs: .quad 6,8
diff160_payload0: .ascii "\n"
diff160_payload1: .ascii "\nXX"
diff160_payload2: .ascii "Ω\nX"
diff160_edits:
    .quad 1,3,diff160_payload0,1
    .quad 3,3,diff160_payload1,3
    .quad 4,4,diff160_payload2,4
diff161_source: .ascii "a!abaa!𐐀éa"
diff161_after: .ascii "aXXX😃!😃XΩ😃XaΩ!𐐀YΩa"
diff161_before: .quad 11,5,4,14,1,3
diff161_pairs: .quad 13,2
diff161_payload0: .ascii "XXX😃"
diff161_payload1: .ascii "😃XΩ😃"
diff161_payload2: .ascii "X"
diff161_payload3: .ascii "Ω"
diff161_payload4: .ascii "Y"
diff161_payload5: .ascii "Ω"
diff161_edits:
    .quad 1,1,diff161_payload0,7
    .quad 2,3,diff161_payload1,11
    .quad 3,5,diff161_payload2,1
    .quad 6,6,diff161_payload3,2
    .quad 11,13,diff161_payload4,1
    .quad 13,13,diff161_payload5,2
diff162_source: .ascii "a!a!β!!éβ"
diff162_after: .ascii "a!YΩ😃XYYΩ😃YYYβX"
diff162_before: .quad 12,3,6,12,7,7
diff162_pairs: .quad 4,9,10,12,23,12,10,3,14,2
diff162_payload0: .ascii "YΩ😃XY"
diff162_payload1: .ascii "YΩ"
diff162_payload2: .ascii "😃YYY"
diff162_payload3: .ascii "X"
diff162_edits:
    .quad 2,6,diff162_payload0,9
    .quad 6,7,diff162_payload1,3
    .quad 7,10,diff162_payload2,7
    .quad 12,12,diff162_payload3,1
diff163_source: .ascii "βbβ𐐀\n𐐀βéa\nb"
diff163_after: .ascii "YYY😃X𐐀Ω\nb"
diff163_before: .quad 5,21
diff163_pairs: .quad 3,12,7,14,12,14
diff163_payload0: .ascii "YYY😃X"
diff163_payload1: .ascii "Ω\n"
diff163_edits:
    .quad 0,5,diff163_payload0,8
    .quad 9,20,diff163_payload1,3
diff164_source: .ascii "\nβ\nbbébaa\n"
diff164_after: .ascii "ΩXΩ\n\n😃Y😃Y\nΩbébaaY😃😃\n\n\nXXY"
diff164_before: .quad 1,4,4,11,0,10,11,9,4,11
diff164_pairs: .quad 16,7,38,24
diff164_payload0: .ascii "ΩXΩ"
diff164_payload1: .ascii "\n😃Y😃Y"
diff164_payload2: .ascii "Ω"
diff164_payload3: .ascii "Y😃😃\n\n"
diff164_payload4: .ascii "XXY"
diff164_edits:
    .quad 0,0,diff164_payload0,5
    .quad 1,3,diff164_payload1,11
    .quad 4,5,diff164_payload2,2
    .quad 11,11,diff164_payload3,11
    .quad 12,12,diff164_payload4,3
diff165_source: .ascii "bb𐐀a𐐀\na\na\n𐐀b𐐀\nb𐐀"
diff165_after: .ascii "bb𐐀a𐐀\na\n\n😃XΩ𐐀\n"
diff165_before: .quad 21,14,21,14,14,13,6,26
diff165_pairs: .quad 21,27,19,0,2,7,19,2,27,19
diff165_payload0: .ascii "\n"
diff165_payload1: .ascii "😃XΩ"
diff165_payload2: .ascii ""
diff165_edits:
    .quad 14,21,diff165_payload0,1
    .quad 21,21,diff165_payload1,7
    .quad 26,31,diff165_payload2,0
diff166_source: .ascii "b!ββ𐐀\nβ𐐀𐐀\nβbab!ééβé!!"
diff166_after: .ascii "b!ββ𐐀\nβ𐐀𐐀\nβb😃XYX!ééβé!!"
diff166_before: .quad 17,25,13,27
diff166_pairs: .quad 37,32,31,21,25,30,41,2,32,4
diff166_payload0: .ascii "😃XYX"
diff166_edits:
    .quad 25,27,diff166_payload0,7
diff167_source: .ascii "!b𐐀é\néββ\n!β\néééb!a"
diff167_after: .ascii "\nYΩY𐐀Ω😃XX\nééΩ\n\n\nXΩb!a"
diff167_before: .quad 9,29,16,16,20,19,16,20
diff167_pairs: .quad 2,32,22,25,30,15,16,30,4,27
diff167_payload0: .ascii "\nYΩY"
diff167_payload1: .ascii "Ω😃XX"
diff167_payload2: .ascii "Ω"
diff167_payload3: .ascii "\n\n\nXΩ"
diff167_edits:
    .quad 0,2,diff167_payload0,5
    .quad 6,19,diff167_payload1,8
    .quad 24,26,diff167_payload2,2
    .quad 26,26,diff167_payload3,6
diff168_source: .ascii "!𐐀é𐐀a𐐀é𐐀𐐀bb\n!!𐐀aa\n\n\nββbβa"
diff168_after: .ascii "!𐐀é𐐀a𐐀é𐐀𐐀bb\n!!𐐀aa\n\n\nββbβa"
diff168_before: .quad 12,5,38,45
diff168_pairs: .quad 19,36,45,27,12,31
diff168_edits:
diff169_source: .ascii "bββ!\n𐐀!éb!\n"
diff169_after: .ascii "b\n😃😃βX!YYXb!\n"
diff169_before: .quad 16,12,14,6
diff169_pairs: .quad 2,19,1,12,18,20,2,1,2,15
diff169_payload0: .ascii "\n😃"
diff169_payload1: .ascii "😃"
diff169_payload2: .ascii "X"
diff169_payload3: .ascii "YYX"
diff169_edits:
    .quad 1,3,diff169_payload0,5
    .quad 3,3,diff169_payload1,4
    .quad 5,5,diff169_payload2,1
    .quad 6,14,diff169_payload3,3
diff170_source: .ascii "𐐀bab𐐀!bébβ\nβ!!!!éaaé\n𐐀"
diff170_after: .ascii "𐐀bab𐐀!Xbébβ\nβ!!\nΩ\n\nYXΩ\né\n𐐀"
diff170_before: .quad 23,5,21,29,15,5
diff170_pairs: .quad 4,7,41,22,22,41,7,14,28,41
diff170_payload0: .ascii "X"
diff170_payload1: .ascii "\nΩ"
diff170_payload2: .ascii "\n"
diff170_payload3: .ascii "\nYXΩ\n"
diff170_edits:
    .quad 12,12,diff170_payload0,1
    .quad 23,24,diff170_payload1,3
    .quad 24,28,diff170_payload2,1
    .quad 28,29,diff170_payload3,6
diff171_source: .ascii "β!!𐐀!𐐀éébé\né!!bé𐐀bββé!a"
diff171_after: .ascii "β!!𐐀!\n😃XX𐐀éé😃Y!!bé𐐀b😃😃X\n😃é!a"
diff171_before: .quad 23,13
diff171_pairs: .quad 33,22,22,43,28,22,49,22,9,22
diff171_payload0: .ascii "\n😃XX"
diff171_payload1: .ascii "😃Y"
diff171_payload2: .ascii "😃😃X"
diff171_payload3: .ascii "\n😃"
diff171_edits:
    .quad 9,9,diff171_payload0,7
    .quad 17,23,diff171_payload1,5
    .quad 33,37,diff171_payload2,9
    .quad 37,37,diff171_payload3,5
diff172_source: .ascii "bééβaaβaéββb𐐀"
diff172_after: .ascii "b\nXXaβaéYY😃Ω😃b𐐀"
diff172_before: .quad 5,11,19,8,3,16,19,3,1,5
diff172_pairs: .quad 5,23,12,27,3,18
diff172_payload0: .ascii "\nXX"
diff172_payload1: .ascii "YY"
diff172_payload2: .ascii "😃Ω😃"
diff172_edits:
    .quad 1,8,diff172_payload0,3
    .quad 14,18,diff172_payload1,2
    .quad 18,18,diff172_payload2,10
diff173_source: .ascii "\néβa!b!\n"
diff173_after: .ascii "😃Ω\n\nX\nΩXYXXb\n😃\n😃YΩ\n"
diff173_before: .quad 5,0,8,7,7,9
diff173_pairs: .quad 4,28,6,6,15,17
diff173_payload0: .ascii "😃Ω\n\nX"
diff173_payload1: .ascii ""
diff173_payload2: .ascii "ΩXYXX"
diff173_payload3: .ascii "\n😃\n😃Y"
diff173_payload4: .ascii "Ω"
diff173_edits:
    .quad 0,0,diff173_payload0,9
    .quad 1,5,diff173_payload1,0
    .quad 5,7,diff173_payload2,6
    .quad 8,9,diff173_payload3,11
    .quad 9,9,diff173_payload4,2
diff174_source: .ascii "é!aβa\n\nβaaβbβ"
diff174_after: .ascii "é!aβaYY😃X😃"
diff174_before: .quad 9,11,0,11,11,4,11,11
diff174_pairs: .quad 17,13,14,8,7,4,6,14,18,9
diff174_payload0: .ascii "YY😃X😃"
diff174_edits:
    .quad 7,18,diff174_payload0,11
diff175_source: .ascii "\nb\n"
diff175_after: .ascii "\nb\nΩYYX"
diff175_before: .quad 1,3,2,0,3,2,0,0
diff175_pairs: .quad 7,6,3,2,0,8
diff175_payload0: .ascii "ΩYYX"
diff175_edits:
    .quad 3,3,diff175_payload0,5
diff176_source: .ascii "a𐐀𐐀!baéβab"
diff176_after: .ascii "a𐐀𐐀!baéβab"
diff176_before: .quad 1,16
diff176_pairs: .quad 11,16
diff176_edits:
diff177_source: .ascii "\n𐐀aβ!"
diff177_after: .ascii "\nΩ𐐀aΩΩ😃ΩXΩXYY"
diff177_before: .quad 6,8,9,6,5,6
diff177_pairs: .quad 11,21
diff177_payload0: .ascii ""
diff177_payload1: .ascii "\nΩ"
diff177_payload2: .ascii "ΩΩ😃ΩX"
diff177_payload3: .ascii "ΩXYY"
diff177_edits:
    .quad 0,1,diff177_payload0,0
    .quad 1,1,diff177_payload1,3
    .quad 6,8,diff177_payload2,11
    .quad 8,9,diff177_payload3,5
diff178_source: .ascii "𐐀ββ𐐀"
diff178_after: .ascii "Ω😃YY😃β\nX😃X😃XΩ😃"
diff178_before: .quad 8,0,0,12
diff178_pairs: .quad 32,20,7,15
diff178_payload0: .ascii ""
diff178_payload1: .ascii "Ω😃YY😃"
diff178_payload2: .ascii "\n"
diff178_payload3: .ascii "X😃"
diff178_payload4: .ascii "X😃XΩ😃"
diff178_edits:
    .quad 0,4,diff178_payload0,0
    .quad 4,4,diff178_payload1,12
    .quad 6,8,diff178_payload2,1
    .quad 8,12,diff178_payload3,5
    .quad 12,12,diff178_payload4,12
diff179_source: .ascii "ééβéba𐐀\n𐐀b\na𐐀!\né!aa\néβ!éa"
diff179_after: .ascii "😃XΩYYa𐐀b\na𐐀!\néXX\néΩ😃\nX😃βΩYYYΩ"
diff179_before: .quad 31,31,28,36,9,31,31,10,2,38
diff179_pairs: .quad 9,0,44,46,25,23
diff179_payload0: .ascii "😃XΩ"
diff179_payload1: .ascii "YY"
diff179_payload2: .ascii ""
diff179_payload3: .ascii "XX"
diff179_payload4: .ascii "Ω😃\nX😃"
diff179_payload5: .ascii "ΩYYYΩ"
diff179_edits:
    .quad 0,8,diff179_payload0,7
    .quad 8,9,diff179_payload1,2
    .quad 10,15,diff179_payload2,0
    .quad 30,33,diff179_payload3,2
    .quad 36,36,diff179_payload4,12
    .quad 38,42,diff179_payload5,7
diff180_source: .ascii "!aaβ\nβ"
diff180_after: .ascii "\nΩXX\n!😃\nYXΩXΩ😃YXβΩYXX\n😃😃X"
diff180_before: .quad 2,1,5,6
diff180_pairs: .quad 35,17,31,6,31,30,42,33,19,37
diff180_payload0: .ascii "\nΩXX\n"
diff180_payload1: .ascii "😃\nYX"
diff180_payload2: .ascii "ΩXΩ😃Y"
diff180_payload3: .ascii "X"
diff180_payload4: .ascii "ΩYX"
diff180_payload5: .ascii "X\n😃😃X"
diff180_edits:
    .quad 0,0,diff180_payload0,6
    .quad 1,2,diff180_payload1,7
    .quad 2,3,diff180_payload2,10
    .quad 3,3,diff180_payload3,1
    .quad 5,8,diff180_payload4,4
    .quad 8,8,diff180_payload5,11
diff181_source: .ascii "\n!βa!é"
diff181_after: .ascii "\nX!😃X😃XβY\nY!éΩΩΩ"
diff181_before: .quad 1,0,4,5,2,4,4,6
diff181_pairs: .quad 13,27,25,8,0,16,12,7,7,1
diff181_payload0: .ascii "X"
diff181_payload1: .ascii "😃X😃X"
diff181_payload2: .ascii "Y"
diff181_payload3: .ascii "\nY"
diff181_payload4: .ascii "ΩΩΩ"
diff181_edits:
    .quad 1,1,diff181_payload0,1
    .quad 2,2,diff181_payload1,10
    .quad 4,5,diff181_payload2,1
    .quad 5,5,diff181_payload3,2
    .quad 8,8,diff181_payload4,6
diff182_source: .ascii "βa𐐀éb\nb𐐀\n\naβ\n\n𐐀bb𐐀!βaβββé"
diff182_after: .ascii "βa𐐀éb\nb𐐀\n\n😃Y😃\n\nββé"
diff182_before: .quad 22,21,23,10,17,18,39,18
diff182_pairs: .quad 11,18,10,0,11,23,12,33,31,23
diff182_payload0: .ascii "😃Y😃\n\n"
diff182_edits:
    .quad 18,39,diff182_payload0,11
diff183_source: .ascii "bé\na!\nb𐐀ééé!aβa!\n𐐀b𐐀ba"
diff183_after: .ascii "bé\naYΩééé!aX😃ΩXa\nXYΩ\n\nYXba"
diff183_before: .quad 30,18,7,25,36,24,19,23
diff183_pairs: .quad 11,28,12,6,31,6
diff183_payload0: .ascii "YΩ"
diff183_payload1: .ascii "X😃Ω"
diff183_payload2: .ascii "X"
diff183_payload3: .ascii "\nXYΩ"
diff183_payload4: .ascii "\nYX"
diff183_edits:
    .quad 5,12,diff183_payload0,3
    .quad 20,22,diff183_payload1,7
    .quad 22,22,diff183_payload2,1
    .quad 23,24,diff183_payload3,5
    .quad 25,34,diff183_payload4,3
diff184_source: .ascii "\n\n𐐀b\nβaββé"
diff184_after: .ascii "\n\n𐐀b\nβaββé"
diff184_before: .quad 2,6,10,8,13,10,2,15
diff184_pairs: .quad 6,6,0,1
diff184_edits:
diff185_source: .ascii "𐐀b𐐀aa"
diff185_after: .ascii "ΩΩ😃𐐀\n😃\nYYb\nX𐐀XΩ😃Ω😃😃X\nY"
diff185_before: .quad 10,11,10,5
diff185_pairs: .quad 20,2
diff185_payload0: .ascii "ΩΩ😃"
diff185_payload1: .ascii "\n😃\nYY"
diff185_payload2: .ascii "\nX"
diff185_payload3: .ascii "X"
diff185_payload4: .ascii "Ω😃Ω"
diff185_payload5: .ascii "😃😃X\nY"
diff185_edits:
    .quad 0,0,diff185_payload0,8
    .quad 4,4,diff185_payload1,8
    .quad 5,5,diff185_payload2,2
    .quad 9,10,diff185_payload3,1
    .quad 10,11,diff185_payload4,8
    .quad 11,11,diff185_payload5,11
diff186_source: .ascii "bβ𐐀βa𐐀baβéβba\n\n\nb!b\né𐐀"
diff186_after: .ascii "bβa𐐀bX\n\nb!b\né\nΩYYY"
diff186_before: .quad 18,30,25,23
diff186_pairs: .quad 2,18,0,19,3,13
diff186_payload0: .ascii ""
diff186_payload1: .ascii "X"
diff186_payload2: .ascii "\nΩYYY"
diff186_edits:
    .quad 1,7,diff186_payload0,0
    .quad 15,25,diff186_payload1,1
    .quad 33,37,diff186_payload2,6
diff187_source: .ascii "éaββ𐐀"
diff187_after: .ascii "Yé\nYXβX\nYYY\n😃😃𐐀X\n"
diff187_before: .quad 11,3
diff187_pairs: .quad 8,27
diff187_payload0: .ascii "Y"
diff187_payload1: .ascii "\nY"
diff187_payload2: .ascii "X"
diff187_payload3: .ascii "X\nYYY"
diff187_payload4: .ascii "\n😃😃"
diff187_payload5: .ascii "X\n"
diff187_edits:
    .quad 0,0,diff187_payload0,1
    .quad 2,3,diff187_payload1,2
    .quad 3,3,diff187_payload2,1
    .quad 5,7,diff187_payload3,5
    .quad 7,7,diff187_payload4,9
    .quad 11,11,diff187_payload5,2
diff188_source: .ascii "𐐀\nb𐐀β"
diff188_after: .ascii "Y\nX😃\nXΩ\nX\nΩbΩ😃\nX😃YY😃"
diff188_before: .quad 6,0,5,5,6,6
diff188_pairs: .quad 9,31,35,16,7,31
diff188_payload0: .ascii "Y\nX😃\n"
diff188_payload1: .ascii "XΩ\nX"
diff188_payload2: .ascii "Ω"
diff188_payload3: .ascii ""
diff188_payload4: .ascii "Ω😃\n"
diff188_payload5: .ascii "X😃YY😃"
diff188_edits:
    .quad 0,4,diff188_payload0,8
    .quad 4,4,diff188_payload1,5
    .quad 5,5,diff188_payload2,2
    .quad 6,10,diff188_payload3,0
    .quad 10,12,diff188_payload4,7
    .quad 12,12,diff188_payload5,11
diff189_source: .ascii "\n\nb𐐀"
diff189_after: .ascii "\nΩ\nXX\nΩ😃Y"
diff189_before: .quad 0,3
diff189_pairs: .quad 8,3,3,1
diff189_payload0: .ascii ""
diff189_payload1: .ascii "\nΩ"
diff189_payload2: .ascii "XX\nΩ😃"
diff189_payload3: .ascii ""
diff189_payload4: .ascii "Y"
diff189_edits:
    .quad 0,1,diff189_payload0,0
    .quad 1,1,diff189_payload1,3
    .quad 2,3,diff189_payload2,9
    .quad 3,7,diff189_payload3,0
    .quad 7,7,diff189_payload4,1
diff190_source: .ascii "aaβéaaaaβ!baébβ!𐐀aβββ𐐀é"
diff190_after: .ascii "aaβéaaaaβ!baébβ!𐐀aβββ𐐀é"
diff190_before: .quad 25,4,1,9,2,12,14,12
diff190_pairs: .quad 9,0,10,0,10,18
diff190_edits:
diff191_source: .ascii "é\nbéé\néβ!aβ\nβ𐐀babé"
diff191_after: .ascii "é\nbéé\néβ!aβ\nβ𐐀babé"
diff191_before: .quad 3,0,20,29,4,8
diff191_pairs: .quad 26,4,25,14,6,0
diff191_edits:
diff192_source: .ascii "𐐀b𐐀\na!𐐀b"
diff192_after: .ascii "😃😃\nb𐐀ΩaΩ!𐐀b"
diff192_before: .quad 10,17,9,9
diff192_pairs: .quad 5,25
diff192_payload0: .ascii "😃😃\n"
diff192_payload1: .ascii "Ω"
diff192_payload2: .ascii "Ω"
diff192_edits:
    .quad 0,4,diff192_payload0,9
    .quad 9,10,diff192_payload1,2
    .quad 11,11,diff192_payload2,2
diff193_source: .ascii "a!!é!𐐀éβ"
diff193_after: .ascii "\nYX😃ΩYXX😃é"
diff193_before: .quad 10,5,3,2,14,14
diff193_pairs: .quad 18,16,12,12,11,10
diff193_payload0: .ascii "\nYX😃Ω"
diff193_payload1: .ascii ""
diff193_payload2: .ascii "YXX😃"
diff193_payload3: .ascii ""
diff193_edits:
    .quad 0,1,diff193_payload0,9
    .quad 1,5,diff193_payload1,0
    .quad 5,10,diff193_payload2,7
    .quad 12,14,diff193_payload3,0
diff194_source: .ascii "b\n!!β"
diff194_after: .ascii "b\n!!βΩ"
diff194_before: .quad 6,4,3,6,0,1
diff194_pairs: .quad 3,6,0,8
diff194_payload0: .ascii "Ω"
diff194_edits:
    .quad 6,6,diff194_payload0,2
diff195_source: .ascii "bb𐐀𐐀𐐀é\nbb\naβ!a𐐀!\n!!éa"
diff195_after: .ascii "bb𐐀𐐀Y\nXΩ𐐀é\n😃X😃X😃a\nΩβ!!YΩ😃éa😃"
diff195_before: .quad 31,19,16,33,10,14,17,35
diff195_pairs: .quad 28,51,26,1,54,45,26,6
diff195_payload0: .ascii "Y\nXΩ"
diff195_payload1: .ascii "😃X😃X😃"
diff195_payload2: .ascii "\nΩ"
diff195_payload3: .ascii ""
diff195_payload4: .ascii "YΩ😃"
diff195_payload5: .ascii "😃"
diff195_edits:
    .quad 10,10,diff195_payload0,5
    .quad 17,20,diff195_payload1,14
    .quad 21,21,diff195_payload2,3
    .quad 24,31,diff195_payload3,0
    .quad 32,33,diff195_payload4,7
    .quad 36,36,diff195_payload5,4
diff196_source: .ascii "b𐐀éb!\na"
diff196_after: .ascii "b😃𐐀ΩΩ😃YXé😃Y\nXY\nXXa"
diff196_before: .quad 5,8,7,5,8,5,1,1,11,11
diff196_pairs: .quad 29,31,1,11,26,29
diff196_payload0: .ascii "😃"
diff196_payload1: .ascii "ΩΩ😃YX"
diff196_payload2: .ascii "😃"
diff196_payload3: .ascii "Y\nXY"
diff196_payload4: .ascii "\nXX"
diff196_edits:
    .quad 1,1,diff196_payload0,4
    .quad 5,5,diff196_payload1,10
    .quad 7,8,diff196_payload2,4
    .quad 8,10,diff196_payload3,4
    .quad 10,10,diff196_payload4,3
diff197_source: .ascii "βé𐐀aébb\nβ𐐀é"
diff197_after: .ascii "βé𐐀aébb\nβ𐐀é"
diff197_before: .quad 16,0,0,16,11,14,16,14
diff197_pairs: .quad 4,22,12,8
diff197_edits:
diff198_source: .ascii "\n𐐀a!a!βéβb"
diff198_after: .ascii "\n𐐀a!\n\n😃a\nΩ\nYY"
diff198_before: .quad 15,11,11,8,16,16,6,5
diff198_pairs: .quad 11,1,8,8,6,13,7,19,8,14
diff198_payload0: .ascii "\n\n😃"
diff198_payload1: .ascii "\nΩ\nYY"
diff198_edits:
    .quad 7,7,diff198_payload0,6
    .quad 8,16,diff198_payload1,6
diff199_source: .ascii "\nβ!!β\naβa"
diff199_after: .ascii "\naβX😃😃"
diff199_before: .quad 8,12,5,1,8,5,8,1
diff199_pairs: .quad 13,4,9,5,13,9,13,13
diff199_payload0: .ascii ""
diff199_payload1: .ascii "X😃"
diff199_payload2: .ascii "😃"
diff199_edits:
    .quad 1,8,diff199_payload0,0
    .quad 11,12,diff199_payload1,5
    .quad 12,12,diff199_payload2,4
diff200_source: .ascii "ééb\nβ!\naa!βb𐐀"
diff200_after: .ascii "éX\nβXXXΩY😃Yβb𐐀"
diff200_before: .quad 5,5,12,13,6,16,6,11
diff200_pairs: .quad 17,3,16,12,3,16,4,17
diff200_payload0: .ascii "X\n"
diff200_payload1: .ascii "XXXΩ"
diff200_payload2: .ascii "Y😃Y"
diff200_edits:
    .quad 2,6,diff200_payload0,2
    .quad 8,12,diff200_payload1,5
    .quad 12,13,diff200_payload2,6
diff201_source: .ascii "aaβ𐐀ba\nb\n\na\n𐐀𐐀aβéb𐐀"
diff201_after: .ascii "aaβ𐐀ba\nb\n\na\n𐐀𐐀aβéb𐐀"
diff201_before: .quad 29,15
diff201_pairs: .quad 18,12
diff201_edits:
diff202_source: .ascii "a𐐀aβb𐐀béé"
diff202_after: .ascii "Ω😃\nXa𐐀😃\nYΩXβXb😃ΩX😃X𐐀ΩY\nbéé\nΩXX\n"
diff202_before: .quad 14,0,0,5
diff202_pairs: .quad 46,44,54,54
diff202_payload0: .ascii "Ω😃\nX"
diff202_payload1: .ascii "😃\nYΩX"
diff202_payload2: .ascii "X"
diff202_payload3: .ascii "😃ΩX😃X"
diff202_payload4: .ascii "ΩY\n"
diff202_payload5: .ascii "\nΩXX\n"
diff202_edits:
    .quad 0,0,diff202_payload0,8
    .quad 5,6,diff202_payload1,9
    .quad 8,8,diff202_payload2,1
    .quad 9,9,diff202_payload3,12
    .quad 13,13,diff202_payload4,4
    .quad 18,18,diff202_payload5,6
diff203_source: .ascii "!!𐐀𐐀\na\n\na!"
diff203_after: .ascii "YΩ😃ΩY!!𐐀XΩΩa\n\n!"
diff203_before: .quad 15,16,16,12
diff203_pairs: .quad 24,21,16,1,12,3,0,10,23,1
diff203_payload0: .ascii "YΩ😃ΩY"
diff203_payload1: .ascii ""
diff203_payload2: .ascii "XΩΩ"
diff203_payload3: .ascii "\n"
diff203_edits:
    .quad 0,0,diff203_payload0,10
    .quad 2,6,diff203_payload1,0
    .quad 10,11,diff203_payload2,5
    .quad 13,15,diff203_payload3,1
diff204_source: .ascii "𐐀é!é"
diff204_after: .ascii "𐐀\n\n😃Y\né!YYYX"
diff204_before: .quad 0,4,9,4,0,0,9,9,4,6
diff204_pairs: .quad 7,17,19,16,18,16,15,15
diff204_payload0: .ascii "\n\n😃Y\n"
diff204_payload1: .ascii "YYY"
diff204_payload2: .ascii "X"
diff204_edits:
    .quad 4,4,diff204_payload0,8
    .quad 7,9,diff204_payload1,3
    .quad 9,9,diff204_payload2,1
diff205_source: .ascii "!β𐐀abba"
diff205_after: .ascii "!β𐐀Yabba"
diff205_before: .quad 9,1,9,9,8,7,9,11,1,8
diff205_pairs: .quad 9,9,12,1,7,1,3,11,12,8
diff205_payload0: .ascii "Y"
diff205_edits:
    .quad 7,7,diff205_payload0,1
diff206_source: .ascii "aé\n𐐀𐐀bb"
diff206_after: .ascii "aé\n𐐀𐐀bb"
diff206_before: .quad 8,14,13,13,12,14,3,3
diff206_pairs: .quad 13,14,12,14,13,1,4,12,13,1
diff206_edits:
diff207_source: .ascii "!é!𐐀bbéβ"
diff207_after: .ascii "!Xé\n😃ΩbY\nYX\néYΩ\nXΩ"
diff207_before: .quad 10,12,14,10,4,0,8,9
diff207_pairs: .quad 25,23,9,4,4,14,17,1
diff207_payload0: .ascii "X"
diff207_payload1: .ascii "\n😃Ω"
diff207_payload2: .ascii "Y\nYX\n"
diff207_payload3: .ascii "YΩ\nXΩ"
diff207_edits:
    .quad 1,1,diff207_payload0,1
    .quad 3,9,diff207_payload1,7
    .quad 10,10,diff207_payload2,5
    .quad 12,14,diff207_payload3,7
diff208_source: .ascii "!aa\nβbβ!a\nbβb\na𐐀aéb\n\n"
diff208_after: .ascii "!aa\nβbX!a\nbΩ😃Ω𐐀aéb\n\n"
diff208_before: .quad 27,3,27,13,27,22
diff208_pairs: .quad 18,18,28,10
diff208_payload0: .ascii ""
diff208_payload1: .ascii "X"
diff208_payload2: .ascii "Ω😃Ω"
diff208_edits:
    .quad 7,9,diff208_payload0,0
    .quad 9,9,diff208_payload1,1
    .quad 13,18,diff208_payload2,8
diff209_source: .ascii "𐐀!β!\n\n\né!aa𐐀!𐐀!\nb!!!𐐀"
diff209_after: .ascii "𐐀!β!\n\n!𐐀!\nb!!!𐐀"
diff209_before: .quad 7,11,4,5,11,11,25,27,16,4
diff209_pairs: .quad 9,20,7,15,5,17,5,9,5,4
diff209_payload0: .ascii "\n"
diff209_edits:
    .quad 9,20,diff209_payload0,1
diff210_source: .ascii "\nβé𐐀𐐀ébé!𐐀ébééβ!𐐀a𐐀ab\nβ"
diff210_after: .ascii "\n\nΩé😃X\n😃𐐀éb𐐀aΩ😃XΩY\nβ"
diff210_before: .quad 25,1,38,15,13,43,3,9
diff210_pairs: .quad 32,11
diff210_payload0: .ascii "\n"
diff210_payload1: .ascii "Ω"
diff210_payload2: .ascii "😃X\n😃"
diff210_payload3: .ascii ""
diff210_payload4: .ascii "Ω😃XΩY"
diff210_edits:
    .quad 1,3,diff210_payload0,1
    .quad 3,16,diff210_payload1,2
    .quad 18,19,diff210_payload2,10
    .quad 26,33,diff210_payload3,0
    .quad 38,44,diff210_payload4,10
diff211_source: .ascii "éé!βa\nβ\n!\nab!"
diff211_after: .ascii "éé!Y😃aXXX😃XXΩ!"
diff211_before: .quad 12,9,0,13,0,7
diff211_pairs: .quad 23,12,18,10
diff211_payload0: .ascii "Y😃"
diff211_payload1: .ascii "XX"
diff211_payload2: .ascii "X😃XXΩ"
diff211_edits:
    .quad 5,7,diff211_payload0,5
    .quad 8,14,diff211_payload1,2
    .quad 14,16,diff211_payload2,9
diff212_source: .ascii "éb𐐀aβé𐐀\né"
diff212_after: .ascii "ébY😃Ωβé"
diff212_before: .quad 2,16,8,19
diff212_pairs: .quad 12,0,8,10,10,2,8,14,4,12
diff212_payload0: .ascii ""
diff212_payload1: .ascii "Y😃Ω"
diff212_payload2: .ascii ""
diff212_edits:
    .quad 3,8,diff212_payload0,0
    .quad 8,8,diff212_payload1,7
    .quad 10,17,diff212_payload2,0
diff213_source: .ascii "!β!β𐐀!\nβéb𐐀aé\nβ𐐀β\n"
diff213_after: .ascii "!β!β𐐀!\nβéb𐐀aé\nβ😃Ωβ\n"
diff213_before: .quad 24,22,27,21,17,22,11,24
diff213_pairs: .quad 2,14,10,3,27,10
diff213_payload0: .ascii "😃Ω"
diff213_edits:
    .quad 27,31,diff213_payload0,6
diff214_source: .ascii "\néβ!a!"
diff214_after: .ascii "\néβ!YXX😃!"
diff214_before: .quad 3,6
diff214_pairs: .quad 1,9
diff214_payload0: .ascii "Y"
diff214_payload1: .ascii "XX😃"
diff214_edits:
    .quad 6,7,diff214_payload0,1
    .quad 7,7,diff214_payload1,6
diff215_source: .ascii "\nβ\né𐐀𐐀b𐐀ββ"
diff215_after: .ascii "ΩΩβΩ\nΩX𐐀ΩY\nΩYb𐐀β\nβXΩY"
diff215_before: .quad 10,4,10,19,19,3,15,1,14,4
diff215_pairs: .quad 19,11,12,16
diff215_payload0: .ascii "ΩΩ"
diff215_payload1: .ascii "Ω"
diff215_payload2: .ascii "ΩX"
diff215_payload3: .ascii "ΩY\nΩY"
diff215_payload4: .ascii "\n"
diff215_payload5: .ascii "XΩY"
diff215_edits:
    .quad 0,1,diff215_payload0,4
    .quad 3,3,diff215_payload1,2
    .quad 4,6,diff215_payload2,3
    .quad 10,14,diff215_payload3,7
    .quad 21,21,diff215_payload4,1
    .quad 23,23,diff215_payload5,4
diff216_source: .ascii "b!é𐐀béé𐐀a𐐀!b!𐐀a𐐀"
diff216_after: .ascii "b!é𐐀béé𐐀a𐐀!b!𐐀a𐐀"
diff216_before: .quad 2,24,1,17
diff216_pairs: .quad 33,8,1,25
diff216_edits:
diff217_source: .ascii "βba\n𐐀!é\nbββb𐐀𐐀βb!βββ\naa"
diff217_after: .ascii "βba\n𐐀!é\nbββb𐐀𐐀βb!βββ\naa"
diff217_before: .quad 2,12,39,23,9,33,5,33
diff217_pairs: .quad 30,9
diff217_edits:
diff218_source: .ascii "!𐐀𐐀βab!βééa!"
diff218_after: .ascii "!𐐀𐐀βX😃😃XaΩYYY\nb\nΩY😃\néX\nΩ😃éYΩYΩ"
diff218_before: .quad 1,9,11,14,21,11,0,11
diff218_pairs: .quad 9,11,44,20,12,28,20,32
diff218_payload0: .ascii "X😃😃X"
diff218_payload1: .ascii "ΩYYY\n"
diff218_payload2: .ascii ""
diff218_payload3: .ascii "\nΩY😃\n"
diff218_payload4: .ascii "X\nΩ😃"
diff218_payload5: .ascii "YΩYΩ"
diff218_edits:
    .quad 11,11,diff218_payload0,10
    .quad 12,12,diff218_payload1,6
    .quad 13,14,diff218_payload2,0
    .quad 14,16,diff218_payload3,9
    .quad 18,18,diff218_payload4,8
    .quad 20,22,diff218_payload5,6
diff219_source: .ascii "a𐐀!𐐀β𐐀β!a\nb𐐀bab!a𐐀é!b𐐀"
diff219_after: .ascii "a𐐀!𐐀βY\naX😃X\nbY\n😃XΩa!bΩ\n\nYY"
diff219_before: .quad 12,43,35,43
diff219_pairs: .quad 9,1,6,16
diff219_payload0: .ascii "Y\n"
diff219_payload1: .ascii "X😃X"
diff219_payload2: .ascii "\n"
diff219_payload3: .ascii "Y\n😃XΩ"
diff219_payload4: .ascii ""
diff219_payload5: .ascii "Ω\n\nYY"
diff219_edits:
    .quad 12,19,diff219_payload0,2
    .quad 20,27,diff219_payload1,6
    .quad 27,28,diff219_payload2,1
    .quad 29,30,diff219_payload3,9
    .quad 31,37,diff219_payload4,0
    .quad 39,43,diff219_payload5,6
diff220_source: .ascii "β\n!ββ!!βββ!𐐀éβ\nβ𐐀\né\n𐐀é\n𐐀"
diff220_after: .ascii "β\nYYββ!𐐀éβ\nβ𐐀\né\n𐐀é\n𐐀"
diff220_before: .quad 36,14
diff220_pairs: .quad 26,35,14,4,0,10
diff220_payload0: .ascii "YY"
diff220_edits:
    .quad 3,12,diff220_payload0,2
diff221_source: .ascii "a𐐀𐐀éééb𐐀!a!a!b\néβéβ𐐀𐐀!b"
diff221_after: .ascii "aΩΩ😃\nYYYééΩΩXb𐐀!😃βé😃β𐐀𐐀!b\nY"
diff221_before: .quad 29,33,39,23
diff221_pairs: .quad 36,28,13,12,19,22
diff221_payload0: .ascii "ΩΩ"
diff221_payload1: .ascii "😃\nYYY"
diff221_payload2: .ascii "ΩΩX"
diff221_payload3: .ascii "😃"
diff221_payload4: .ascii "😃"
diff221_payload5: .ascii "\nY"
diff221_edits:
    .quad 1,11,diff221_payload0,4
    .quad 11,11,diff221_payload1,8
    .quad 15,15,diff221_payload2,5
    .quad 21,29,diff221_payload3,4
    .quad 33,33,diff221_payload4,4
    .quad 45,45,diff221_payload5,2
diff222_source: .ascii "βaβ𐐀aéβaéé!"
diff222_after: .ascii "βaβ𐐀X\n😃X\naéβaéXΩ\n😃!"
diff222_before: .quad 19,12
diff222_pairs: .quad 7,9,10,5,17,22
diff222_payload0: .ascii "X\n😃X\n"
diff222_payload1: .ascii "XΩ\n😃"
diff222_edits:
    .quad 9,9,diff222_payload0,8
    .quad 17,19,diff222_payload1,8
diff223_source: .ascii "𐐀!b!éb\naβ𐐀béé!"
diff223_after: .ascii "𐐀!b!éb\naβ𐐀béé!"
diff223_before: .quad 4,21
diff223_pairs: .quad 19,0,10,11,9,0,24,7
diff223_edits:
diff224_source: .ascii "\na!!\nβ!bβbéβaaβé𐐀𐐀"
diff224_after: .ascii "\na!!\nβ!bβbéβaaβYΩY\n𐐀𐐀"
diff224_before: .quad 26,2,26,30
diff224_pairs: .quad 16,3,33,2,18,24
diff224_payload0: .ascii "YΩY\n"
diff224_edits:
    .quad 20,22,diff224_payload0,5
diff225_source: .ascii "βa!\nββbbé𐐀aaaéβa\nβ!"
diff225_after: .ascii "β😃\nXββ😃XXΩ\né𐐀aaΩ😃X😃\néβΩ😃\n\n😃β!"
diff225_before: .quad 28,3,13,7,20,9,22,22
diff225_pairs: .quad 25,17,36,8,52,27
diff225_payload0: .ascii "😃\nX"
diff225_payload1: .ascii "😃X"
diff225_payload2: .ascii "XΩ\n"
diff225_payload3: .ascii "Ω😃X😃\n"
diff225_payload4: .ascii "Ω😃\n\n😃"
diff225_edits:
    .quad 2,5,diff225_payload0,6
    .quad 9,10,diff225_payload1,5
    .quad 10,11,diff225_payload2,4
    .quad 19,20,diff225_payload3,12
    .quad 24,26,diff225_payload4,12
diff226_source: .ascii "a\n\néb\n𐐀ééa\naβ!!éb\néaβ"
diff226_after: .ascii "a\n\né\n\nY\n𐐀YXYΩ!éb\néaβΩ\n\n\n"
diff226_before: .quad 22,18,20,16,22,11,22,21,26,22
diff226_pairs: .quad 30,26
diff226_payload0: .ascii "\n"
diff226_payload1: .ascii "\nY"
diff226_payload2: .ascii "YXYΩ"
diff226_payload3: .ascii "Ω\n\n\n"
diff226_edits:
    .quad 5,6,diff226_payload0,1
    .quad 6,6,diff226_payload1,2
    .quad 11,21,diff226_payload2,5
    .quad 31,31,diff226_payload3,5
diff227_source: .ascii "βéaβ!βééaaab\nβ!𐐀𐐀𐐀!!𐐀\n"
diff227_after: .ascii "βéaβ!βéé\n😃\nΩ𐐀𐐀𐐀!!𐐀\n"
diff227_before: .quad 40,2,18,5,8,40,18,35
diff227_pairs: .quad 4,8
diff227_payload0: .ascii "\n😃\nΩ"
diff227_edits:
    .quad 14,22,diff227_payload0,8
diff228_source: .ascii "βb\néaaββ𐐀aéa\nééβ\nabéb"
diff228_after: .ascii "βb\néaa\n\nX\nééβ\nabéb"
diff228_before: .quad 32,28,6,12
diff228_pairs: .quad 17,3,9,16,8,7
diff228_payload0: .ascii "\n\nX\n"
diff228_edits:
    .quad 8,21,diff228_payload0,4
diff229_source: .ascii "é!βé\n"
diff229_after: .ascii "😃é😃Y\n\n!\n\nX😃"
diff229_before: .quad 3,2,8,0
diff229_pairs: .quad 4,17
diff229_payload0: .ascii "😃"
diff229_payload1: .ascii "😃Y\n\n"
diff229_payload2: .ascii "\n"
diff229_payload3: .ascii "X😃"
diff229_edits:
    .quad 0,0,diff229_payload0,4
    .quad 2,2,diff229_payload1,7
    .quad 3,7,diff229_payload2,1
    .quad 8,8,diff229_payload3,5
diff230_source: .ascii "éb𐐀!b\n\n\nb\n!\n\na\naβ"
diff230_after: .ascii "éb\nYYXXbΩΩ😃Y\n😃X😃\nYΩ😃XY\n!\n\naΩY😃\nX"
diff230_before: .quad 14,15
diff230_pairs: .quad 42,50,3,0
diff230_payload0: .ascii "\nYYXX"
diff230_payload1: .ascii "ΩΩ😃Y"
diff230_payload2: .ascii "😃X😃"
diff230_payload3: .ascii "YΩ😃XY"
diff230_payload4: .ascii "ΩY😃\n"
diff230_payload5: .ascii "X"
diff230_edits:
    .quad 3,8,diff230_payload0,5
    .quad 9,9,diff230_payload1,9
    .quad 10,10,diff230_payload2,9
    .quad 11,13,diff230_payload3,9
    .quad 18,22,diff230_payload4,8
    .quad 22,22,diff230_payload5,1
diff231_source: .ascii "b!\néb\n\n𐐀!é!βéaa"
diff231_after: .ascii "b!\néb\n😃\nΩΩ\né!Ω"
diff231_before: .quad 0,0,2,22,13,2,16,3,7,15
diff231_pairs: .quad 15,1,7,20,5,1,12,14
diff231_payload0: .ascii "😃\nΩΩ\n"
diff231_payload1: .ascii "Ω"
diff231_edits:
    .quad 7,13,diff231_payload0,10
    .quad 16,22,diff231_payload1,2
diff232_source: .ascii "!!\nβ\n\nb\n!ééβbbbb!!bba!β\n𐐀"
diff232_after: .ascii "!!\nβ\n\nb\n!ééβbbbb!!bba!β\n𐐀"
diff232_before: .quad 25,7,8,14,3,9,29,5,12,24
diff232_pairs: .quad 5,19,7,10,7,12,20,20,29,26
diff232_edits:
diff233_source: .ascii "𐐀β\né\n!βa!βb"
diff233_after: .ascii "ΩX\nΩX😃Y\nΩΩ\nXXβ\n\nΩXX"
diff233_before: .quad 7,13,6,14
diff233_pairs: .quad 23,17,11,15,18,3,27,3
diff233_payload0: .ascii "ΩX"
diff233_payload1: .ascii "ΩX😃Y\n"
diff233_payload2: .ascii "ΩΩ\n"
diff233_payload3: .ascii "XX"
diff233_payload4: .ascii "\n\nΩXX"
diff233_edits:
    .quad 0,6,diff233_payload0,3
    .quad 7,13,diff233_payload1,9
    .quad 13,14,diff233_payload2,5
    .quad 14,15,diff233_payload3,2
    .quad 17,18,diff233_payload4,6
diff234_source: .ascii "b𐐀b\nβééaa"
diff234_after: .ascii "b𐐀b\nβ\n\nΩY\n"
diff234_before: .quad 15,0,15,1,11,15,5,13,15,5
diff234_pairs: .quad 4,11,0,5,9,5
diff234_payload0: .ascii "\n"
diff234_payload1: .ascii "\nΩY\n"
diff234_edits:
    .quad 9,13,diff234_payload0,1
    .quad 13,15,diff234_payload1,5
diff235_source: .ascii "éa𐐀aβ"
diff235_after: .ascii "ΩΩYβX\nΩ\nY"
diff235_before: .quad 7,10
diff235_pairs: .quad 11,5,13,12
diff235_payload0: .ascii ""
diff235_payload1: .ascii "ΩΩ"
diff235_payload2: .ascii "Y"
diff235_payload3: .ascii "X\nΩ\nY"
diff235_edits:
    .quad 0,3,diff235_payload0,0
    .quad 3,7,diff235_payload1,4
    .quad 7,8,diff235_payload2,1
    .quad 10,10,diff235_payload3,6
diff236_source: .ascii "bβaβ\néβé!éββ𐐀βé!"
diff236_after: .ascii "bXYβ\n😃YΩ\nΩéβé!éββ𐐀β😃😃Ω"
diff236_before: .quad 24,28,7,28,0,24,18,24
diff236_pairs: .quad 0,43,27,22,22,6,27,2
diff236_payload0: .ascii "XY"
diff236_payload1: .ascii "😃YΩ\nΩ"
diff236_payload2: .ascii ""
diff236_payload3: .ascii "😃😃Ω"
diff236_edits:
    .quad 1,4,diff236_payload0,2
    .quad 7,7,diff236_payload1,10
    .quad 26,29,diff236_payload2,0
    .quad 29,29,diff236_payload3,10
diff237_source: .ascii "a𐐀\nébé"
diff237_after: .ascii "ΩΩ😃ΩX𐐀😃YéΩ\nXé"
diff237_before: .quad 9,5,8,1
diff237_pairs: .quad 12,20,15,22,4,4,4,26
diff237_payload0: .ascii "ΩΩ😃"
diff237_payload1: .ascii "ΩX"
diff237_payload2: .ascii "😃Y"
diff237_payload3: .ascii "Ω"
diff237_payload4: .ascii "\nX"
diff237_edits:
    .quad 0,1,diff237_payload0,8
    .quad 1,1,diff237_payload1,3
    .quad 5,6,diff237_payload2,5
    .quad 8,9,diff237_payload3,2
    .quad 9,9,diff237_payload4,2
diff238_source: .ascii "é!𐐀𐐀β"
diff238_after: .ascii "YX𐐀😃XY\n😃"
diff238_before: .quad 13,2,7,2
diff238_pairs: .quad 17,13
diff238_payload0: .ascii "Y"
diff238_payload1: .ascii "X"
diff238_payload2: .ascii "😃XY"
diff238_payload3: .ascii "\n😃"
diff238_edits:
    .quad 0,2,diff238_payload0,1
    .quad 2,3,diff238_payload1,1
    .quad 7,13,diff238_payload2,6
    .quad 13,13,diff238_payload3,5
diff239_source: .ascii "\n𐐀\nb"
diff239_after: .ascii "YXXYX\nXΩ\nb\n😃😃\n\n"
diff239_before: .quad 6,7,7,6,1,0,5,0,7,7
diff239_pairs: .quad 9,9
diff239_payload0: .ascii "YXXYX"
diff239_payload1: .ascii "XΩ\n"
diff239_payload2: .ascii "\n😃😃\n\n"
diff239_edits:
    .quad 0,5,diff239_payload0,5
    .quad 6,6,diff239_payload1,4
    .quad 7,7,diff239_payload2,11
diff240_source: .ascii "\n!𐐀𐐀𐐀β\n\néβ!!𐐀β"
diff240_after: .ascii "\n!𐐀Y😃X𐐀βΩβ\n𐐀YΩΩΩΩ"
diff240_before: .quad 23,17,20,23,10,28,16,14,22,0
diff240_pairs: .quad 10,7,30,6,18,34
diff240_payload0: .ascii "Y😃X"
diff240_payload1: .ascii ""
diff240_payload2: .ascii "Ω"
diff240_payload3: .ascii "\n"
diff240_payload4: .ascii "YΩΩΩΩ"
diff240_edits:
    .quad 6,10,diff240_payload0,6
    .quad 16,20,diff240_payload1,0
    .quad 20,20,diff240_payload2,2
    .quad 22,24,diff240_payload3,1
    .quad 28,30,diff240_payload4,9
diff241_source: .ascii "b!é!\n𐐀ba𐐀a\n!!"
diff241_after: .ascii "b!é!\n𐐀ba𐐀a\n!!"
diff241_before: .quad 12,10,17,2,17,12,5,10
diff241_pairs: .quad 5,0,5,2,1,2,1,5
diff241_edits:
diff242_source: .ascii "βbb𐐀β!\nb\n𐐀b\nβ\n!a𐐀β𐐀"
diff242_after: .ascii "\nXΩ!aY𐐀"
diff242_before: .quad 14,12,2,18,2,29
diff242_pairs: .quad 1,6,5,1,4,1,6,4,2,1
diff242_payload0: .ascii "\n"
diff242_payload1: .ascii "XΩ"
diff242_payload2: .ascii "Y"
diff242_edits:
    .quad 0,8,diff242_payload0,1
    .quad 8,23,diff242_payload1,3
    .quad 25,31,diff242_payload2,1
diff243_source: .ascii "éβbéβ"
diff243_after: .ascii "éβbé"
diff243_before: .quad 0,0,4,4,7,4,5,9,4,2
diff243_pairs: .quad 1,0,0,5,0,2,2,2,4,7
diff243_payload0: .ascii ""
diff243_edits:
    .quad 7,9,diff243_payload0,0
diff244_source: .ascii "\nbbβé\nbéβ𐐀\nb!𐐀a𐐀\n"
diff244_after: .ascii "\n😃Y\nbβXbéY𐐀\nΩ\n!𐐀a𐐀\n"
diff244_before: .quad 7,20,29,30
diff244_pairs: .quad 28,14,28,15,12,10,10,19,8,10
diff244_payload0: .ascii "\n😃Y\n"
diff244_payload1: .ascii ""
diff244_payload2: .ascii "X"
diff244_payload3: .ascii "Y"
diff244_payload4: .ascii "Ω\n"
diff244_edits:
    .quad 0,2,diff244_payload0,7
    .quad 5,7,diff244_payload1,0
    .quad 7,8,diff244_payload2,1
    .quad 11,13,diff244_payload3,1
    .quad 18,19,diff244_payload4,3
diff245_source: .ascii "éééééb!𐐀aébb\nββéβb𐐀!"
diff245_after: .ascii "ééééb\nXX😃Ω!𐐀😃Y😃\nbb\nββéβb𐐀!"
diff245_before: .quad 8,21,11,6,36,21,10,8,28,2
diff245_pairs: .quad 6,10,8,18
diff245_payload0: .ascii ""
diff245_payload1: .ascii "\nXX😃Ω"
diff245_payload2: .ascii "😃Y😃\n"
diff245_edits:
    .quad 6,8,diff245_payload0,0
    .quad 11,11,diff245_payload1,9
    .quad 16,19,diff245_payload2,10
diff246_source: .ascii "ébbé\nβ\n!!𐐀𐐀\néé\n𐐀𐐀bb𐐀βéβéb"
diff246_after: .ascii "ΩYbY\nβ\n!!𐐀𐐀\néé\n𐐀𐐀😃Yéb"
diff246_before: .quad 4,2,6,0,11,48
diff246_pairs: .quad 36,24,8,25,38,19
diff246_payload0: .ascii "ΩY"
diff246_payload1: .ascii "Y\n"
diff246_payload2: .ascii "😃Y"
diff246_edits:
    .quad 0,3,diff246_payload0,3
    .quad 4,7,diff246_payload1,2
    .quad 34,46,diff246_payload2,5
diff247_source: .ascii "!babb𐐀"
diff247_after: .ascii "b\nΩ\nYXaXb\nXY\nb𐐀\nX"
diff247_before: .quad 4,1
diff247_pairs: .quad 2,5,4,4,9,12,10,14,5,6
diff247_payload0: .ascii ""
diff247_payload1: .ascii "\nΩ\nYX"
diff247_payload2: .ascii "X"
diff247_payload3: .ascii "\nXY\n"
diff247_payload4: .ascii "\nX"
diff247_edits:
    .quad 0,1,diff247_payload0,0
    .quad 2,2,diff247_payload1,6
    .quad 3,3,diff247_payload2,1
    .quad 4,4,diff247_payload3,4
    .quad 9,9,diff247_payload4,2
diff248_source: .ascii "éé!\naébb"
diff248_after: .ascii "éΩΩ😃😃😃!Y😃\nΩ😃YΩYb\nb"
diff248_before: .quad 7,2,2,5
diff248_pairs: .quad 6,38
diff248_payload0: .ascii "ΩΩ😃😃😃"
diff248_payload1: .ascii "Y😃\nΩ"
diff248_payload2: .ascii "😃YΩY"
diff248_payload3: .ascii "\n"
diff248_edits:
    .quad 2,4,diff248_payload0,16
    .quad 5,7,diff248_payload1,8
    .quad 7,9,diff248_payload2,8
    .quad 10,10,diff248_payload3,1
diff249_source: .ascii "βa\n\nbaba!ab𐐀b𐐀aa\n\né"
diff249_after: .ascii "βa\n\nbaba!ab𐐀b𐐀aa\n\né"
diff249_before: .quad 23,16,24,25,9,27,24,25
diff249_pairs: .quad 14,2,17,24,5,5,25,8,27,25
diff249_edits:
diff250_source: .ascii "aé\n𐐀\naé\n"
diff250_after: .ascii "a𐐀\n\n😃X\nY\n"
diff250_before: .quad 10,4,9,10,13,8,10,0
diff250_pairs: .quad 12,1,15,11,15,13
diff250_payload0: .ascii ""
diff250_payload1: .ascii "\n"
diff250_payload2: .ascii ""
diff250_payload3: .ascii "😃X\nY\n"
diff250_edits:
    .quad 1,4,diff250_payload0,0
    .quad 9,10,diff250_payload1,1
    .quad 10,12,diff250_payload2,0
    .quad 12,13,diff250_payload3,8
diff251_source: .ascii "𐐀éaaa𐐀𐐀bé!é𐐀𐐀ββ𐐀aβββ\néé!b"
diff251_after: .ascii "𐐀éaaa𐐀𐐀bé!é𐐀𐐀ββ𐐀aβββ\néé!b"
diff251_before: .quad 13,17,23,13
diff251_pairs: .quad 47,51,8,47,53,0,17,53
diff251_edits:
diff252_source: .ascii "aaé𐐀aéa\nβé!βéb!abb\n"
diff252_after: .ascii "aa\n😃YΩé𐐀Y\nXaéa\nβé!ΩβY😃😃XYb\n"
diff252_before: .quad 2,13,9,11,2,22,23,13,20,8
diff252_pairs: .quad 13,26,22,43
diff252_payload0: .ascii "\n😃YΩ"
diff252_payload1: .ascii "Y\nX"
diff252_payload2: .ascii "Ω"
diff252_payload3: .ascii "Y😃😃XY"
diff252_edits:
    .quad 2,2,diff252_payload0,8
    .quad 8,8,diff252_payload1,3
    .quad 18,18,diff252_payload2,2
    .quad 20,26,diff252_payload3,11
diff253_source: .ascii "a!\n𐐀\naaβba𐐀a"
diff253_after: .ascii "a!\n𐐀\naaβba𐐀a"
diff253_before: .quad 2,3,3,2
diff253_pairs: .quad 8,2,13,13
diff253_edits:
diff254_source: .ascii "béβ!é𐐀a𐐀𐐀a!éaββ!bβ𐐀\nbβ!"
diff254_after: .ascii "béβ!😃😃X\nYβ😃\nXYβ!bβ𐐀\nΩYXY"
diff254_before: .quad 39,26,25,28
diff254_pairs: .quad 17,37,25,25,0,23
diff254_payload0: .ascii "😃😃X\nY"
diff254_payload1: .ascii "😃\nXY"
diff254_payload2: .ascii "ΩYXY"
diff254_edits:
    .quad 6,26,diff254_payload0,11
    .quad 28,28,diff254_payload1,7
    .quad 39,43,diff254_payload2,5
diff255_source: .ascii "𐐀!éé\n\néé!a\naβ"
diff255_after: .ascii "𐐀YΩΩΩ\n\n\néé!\nYYXΩX"
diff255_before: .quad 19,15,0,13
diff255_pairs: .quad 10,23
diff255_payload0: .ascii "Y"
diff255_payload1: .ascii "ΩΩΩ\n"
diff255_payload2: .ascii "\n"
diff255_payload3: .ascii "YYXΩX"
diff255_edits:
    .quad 4,5,diff255_payload0,1
    .quad 5,9,diff255_payload1,7
    .quad 16,18,diff255_payload2,1
    .quad 18,21,diff255_payload3,6
diff256_source: .ascii "𐐀𐐀!bb\n"
diff256_after: .ascii "𐐀𐐀!bb\n😃\n"
diff256_before: .quad 0,8
diff256_pairs: .quad 11,4,9,0,10,16,0,16,9,12
diff256_payload0: .ascii "😃\n"
diff256_edits:
    .quad 12,12,diff256_payload0,5
diff257_source: .ascii "\n\n𐐀b!𐐀"
diff257_after: .ascii "\n\n\n\n😃X😃Ω𐐀😃\nX\n😃!Y\n\nΩ"
diff257_before: .quad 1,12,6,0,12,8,0,0
diff257_pairs: .quad 19,15,33,31,3,36
diff257_payload0: .ascii "\n\n"
diff257_payload1: .ascii "😃X😃Ω"
diff257_payload2: .ascii ""
diff257_payload3: .ascii "😃\nX\n😃"
diff257_payload4: .ascii ""
diff257_payload5: .ascii "Y\n\nΩ"
diff257_edits:
    .quad 0,0,diff257_payload0,2
    .quad 2,2,diff257_payload1,11
    .quad 6,7,diff257_payload2,0
    .quad 7,7,diff257_payload3,11
    .quad 8,12,diff257_payload4,0
    .quad 12,12,diff257_payload5,5
diff258_source: .ascii "ab!a!"
diff258_after: .ascii "\n!X"
diff258_before: .quad 1,3,2,3,4,2,4,2,5,2
diff258_pairs: .quad 2,3,1,1,1,1,3,1,3,2
diff258_payload0: .ascii ""
diff258_payload1: .ascii ""
diff258_payload2: .ascii "\n"
diff258_payload3: .ascii "X"
diff258_edits:
    .quad 0,2,diff258_payload0,0
    .quad 2,4,diff258_payload1,0
    .quad 4,4,diff258_payload2,1
    .quad 5,5,diff258_payload3,1
diff259_source: .ascii "βaéa!ébbab𐐀é𐐀!a\n!𐐀ββ\na𐐀β\n"
diff259_after: .ascii "βaéa!ébbab𐐀é\nX😃𐐀!a😃YX!XXX\n😃𐐀ββ\na𐐀β\n"
diff259_before: .quad 24,37,10,0
diff259_pairs: .quad 52,2,13,55,56,10,60,30
diff259_payload0: .ascii "\nX😃"
diff259_payload1: .ascii "😃YX"
diff259_payload2: .ascii "XXX\n😃"
diff259_edits:
    .quad 19,19,diff259_payload0,6
    .quad 25,26,diff259_payload1,6
    .quad 27,27,diff259_payload2,8
diff260_source: .ascii "éa!!βé\n!!!𐐀aabβ\na\n"
diff260_after: .ascii "éXa\n!!!𐐀aabβ\nΩ😃YXaX\n"
diff260_before: .quad 17,13,5,5
diff260_pairs: .quad 15,27,5,14,5,12,7,0,28,25
diff260_payload0: .ascii "X"
diff260_payload1: .ascii ""
diff260_payload2: .ascii "\nΩ😃YX"
diff260_payload3: .ascii "X"
diff260_edits:
    .quad 2,2,diff260_payload0,1
    .quad 3,9,diff260_payload1,0
    .quad 22,23,diff260_payload2,9
    .quad 24,24,diff260_payload3,1
diff261_source: .ascii "ab\né!aβ\n\na!bb!a\n"
diff261_after: .ascii "ab\né!aβ\n\n\n\nY\n\n!a\n"
diff261_before: .quad 12,10,5,18,2,1,12,14
diff261_pairs: .quad 8,9,12,19
diff261_payload0: .ascii "\n\nY\n\n"
diff261_payload1: .ascii ""
diff261_edits:
    .quad 11,12,diff261_payload0,5
    .quad 12,15,diff261_payload1,0
diff262_source: .ascii "!aé𐐀a!𐐀b𐐀ββ\n"
diff262_after: .ascii "!aé𐐀Ω😃ββ\n"
diff262_before: .quad 15,0
diff262_pairs: .quad 0,4,19,10,8,0
diff262_payload0: .ascii "Ω😃"
diff262_edits:
    .quad 8,19,diff262_payload0,6
diff263_source: .ascii "βéé\n!𐐀!!ébé"
diff263_after: .ascii "βé😃Y😃Y\nbé"
diff263_before: .quad 12,4,8,8,16,2,19,4
diff263_pairs: .quad 18,14,13,14
diff263_payload0: .ascii "😃Y😃Y\n"
diff263_edits:
    .quad 4,16,diff263_payload0,11
diff264_source: .ascii "\nba!β!b\n\n\nbba!βb𐐀\nbβ"
diff264_after: .ascii "\nbXa!YY!b\n\nΩXba!βb\n😃YYYΩβ"
diff264_before: .quad 24,0
diff264_pairs: .quad 31,3,28,1,27,27
diff264_payload0: .ascii "X"
diff264_payload1: .ascii "YY"
diff264_payload2: .ascii "ΩX"
diff264_payload3: .ascii ""
diff264_payload4: .ascii ""
diff264_payload5: .ascii "😃YYYΩ"
diff264_edits:
    .quad 2,2,diff264_payload0,1
    .quad 4,6,diff264_payload1,2
    .quad 10,12,diff264_payload2,3
    .quad 18,22,diff264_payload3,0
    .quad 23,24,diff264_payload4,0
    .quad 24,24,diff264_payload5,9
diff265_source: .ascii "aaéa\n\naé𐐀𐐀\n𐐀ββ\na!éa\n\n!β!"
diff265_after: .ascii "aaéa\nY😃ββXa\n\n!β!Ω"
diff265_before: .quad 36,4,10,29,30,14,7,10
diff265_pairs: .quad 0,13,7,5,15,17
diff265_payload0: .ascii "\nY😃"
diff265_payload1: .ascii "X"
diff265_payload2: .ascii "Ω"
diff265_edits:
    .quad 5,23,diff265_payload0,6
    .quad 27,32,diff265_payload1,1
    .quad 39,39,diff265_payload2,2
diff266_source: .ascii "𐐀!\nb\n𐐀\n"
diff266_after: .ascii "𐐀!\nb\n𐐀\n"
diff266_before: .quad 4,6,4,12,5,4,6,12
diff266_pairs: .quad 0,4,8,12,12,13,4,0,7,13
diff266_edits:
diff267_source: .ascii "ébéβa!"
diff267_after: .ascii "ébé\nYβa!"
diff267_before: .quad 7,7,5,0,9,8,7,8
diff267_pairs: .quad 8,2,5,5
diff267_payload0: .ascii "\nY"
diff267_edits:
    .quad 5,5,diff267_payload0,2
diff268_source: .ascii "b!β\n𐐀!β"
diff268_after: .ascii "b!βΩX\nY\n😃X😃β"
diff268_before: .quad 0,9,12,10,1,12
diff268_pairs: .quad 10,0,4,2
diff268_payload0: .ascii "ΩX"
diff268_payload1: .ascii "\nY\n😃"
diff268_payload2: .ascii "X😃"
diff268_edits:
    .quad 4,5,diff268_payload0,3
    .quad 5,10,diff268_payload1,7
    .quad 10,10,diff268_payload2,5
diff269_source: .ascii "baa𐐀a\n\n𐐀ééé\n𐐀!aβbβ!𐐀é𐐀\n"
diff269_after: .ascii "baa𐐀a\n\n𐐀ééé\n𐐀!aβbβ!𐐀é𐐀\n"
diff269_before: .quad 33,43,2,0,16,14
diff269_pairs: .quad 27,26,18,21,18,33,43,1
diff269_edits:
diff270_source: .ascii "βa!\na!𐐀\n!é𐐀bbb"
diff270_after: .ascii "Y\nΩa!\naΩX𐐀😃Ω😃YX!é𐐀\nXbb😃Y"
diff270_before: .quad 21,11,12,15,4,3,19,5
diff270_pairs: .quad 14,4,6,10,4,42
diff270_payload0: .ascii "Y\nΩ"
diff270_payload1: .ascii "ΩX"
diff270_payload2: .ascii "😃Ω😃YX"
diff270_payload3: .ascii "\n"
diff270_payload4: .ascii "X"
diff270_payload5: .ascii "😃Y"
diff270_edits:
    .quad 0,2,diff270_payload0,4
    .quad 6,7,diff270_payload1,3
    .quad 11,12,diff270_payload2,12
    .quad 19,20,diff270_payload3,1
    .quad 20,20,diff270_payload4,1
    .quad 22,22,diff270_payload5,5
diff271_source: .ascii "éééb!é\n!b"
diff271_after: .ascii "éééb!XΩ\nX😃\n!😃😃YXΩYΩ😃\n"
diff271_before: .quad 10,8,7,7,7,7
diff271_pairs: .quad 19,18,6,7,4,4,34,9
diff271_payload0: .ascii "XΩ\nX😃"
diff271_payload1: .ascii "😃😃YXΩ"
diff271_payload2: .ascii "YΩ😃\n"
diff271_edits:
    .quad 8,10,diff271_payload0,9
    .quad 12,13,diff271_payload1,12
    .quad 13,13,diff271_payload2,8
diff272_source: .ascii "éβaba"
diff272_after: .ascii "😃YéΩXYYabYΩ"
diff272_before: .quad 4,2,2,6,7,6,5,6,5,2
diff272_pairs: .quad 5,17,7,11
diff272_payload0: .ascii "😃Y"
diff272_payload1: .ascii "ΩXYY"
diff272_payload2: .ascii "YΩ"
diff272_edits:
    .quad 0,0,diff272_payload0,5
    .quad 2,4,diff272_payload1,5
    .quad 6,7,diff272_payload2,3
diff273_source: .ascii "\n\n!\n𐐀aaaβ!𐐀"
diff273_after: .ascii "\n\n!\n𐐀aaaβ!𐐀"
diff273_before: .quad 4,11,13,14
diff273_pairs: .quad 15,2,11,2,2,9
diff273_edits:
diff274_source: .ascii "𐐀\nb𐐀!\nβébββ𐐀éa\na\nbbaβ"
diff274_after: .ascii "𐐀\nb𐐀!\nβébββ𐐀éa\na\nbbaβ"
diff274_before: .quad 11,11,19,14,5,27,36,19
diff274_pairs: .quad 14,12
diff274_edits:
diff275_source: .ascii "β\n\naéb!!aéβé𐐀!b𐐀βé!\n\nβ"
diff275_after: .ascii "β\n\naéY!XΩaéΩ😃X😃\n\nβ"
diff275_before: .quad 13,36,0,10,13,8
diff275_pairs: .quad 4,30,8,10
diff275_payload0: .ascii ""
diff275_payload1: .ascii "Y"
diff275_payload2: .ascii "XΩ"
diff275_payload3: .ascii "Ω😃X"
diff275_payload4: .ascii "😃"
diff275_edits:
    .quad 7,8,diff275_payload0,0
    .quad 8,9,diff275_payload1,1
    .quad 10,10,diff275_payload2,3
    .quad 13,21,diff275_payload3,7
    .quad 21,32,diff275_payload4,4
diff276_source: .ascii "\n𐐀b\né!a\nbéaaéβaé\n!\n!β!b"
diff276_after: .ascii "😃😃XΩ😃\né!a\nbéaaéβaéX\n!\n!β!b"
diff276_before: .quad 1,25,1,13,6,5,10,12
diff276_pairs: .quad 39,21,34,26,36,8
diff276_payload0: .ascii "😃😃XΩ😃"
diff276_payload1: .ascii "X"
diff276_edits:
    .quad 0,6,diff276_payload0,15
    .quad 24,24,diff276_payload1,1
diff277_source: .ascii "𐐀b!bb𐐀\n"
diff277_after: .ascii "😃Y\n𐐀ΩY\n😃Yb😃😃ΩYΩ😃\n𐐀\n\n\n"
diff277_before: .quad 0,4,6,6,6,7
diff277_pairs: .quad 18,37,38,24,10,28
diff277_payload0: .ascii "😃Y\n"
diff277_payload1: .ascii "Ω"
diff277_payload2: .ascii "Y\n😃Y"
diff277_payload3: .ascii "😃😃ΩYΩ"
diff277_payload4: .ascii "😃\n"
diff277_payload5: .ascii "\n\n"
diff277_edits:
    .quad 0,0,diff277_payload0,6
    .quad 4,6,diff277_payload1,2
    .quad 6,6,diff277_payload2,7
    .quad 7,8,diff277_payload3,13
    .quad 8,8,diff277_payload4,5
    .quad 12,12,diff277_payload5,2
diff278_source: .ascii "aéaa𐐀\n!β!!baβ𐐀a𐐀𐐀\né"
diff278_after: .ascii "aéaa𐐀\n!β!YY!YXXXaβ𐐀aΩ\n😃é"
diff278_before: .quad 3,0
diff278_pairs: .quad 9,32,31,4,38,36,0,5,21,14
diff278_payload0: .ascii "YY"
diff278_payload1: .ascii "YXXX"
diff278_payload2: .ascii "Ω\n😃"
diff278_edits:
    .quad 14,14,diff278_payload0,2
    .quad 15,16,diff278_payload1,4
    .quad 24,33,diff278_payload2,7
diff279_source: .ascii "\n!𐐀!𐐀ébb!a𐐀\n𐐀\na"
diff279_after: .ascii "\n!𐐀!𐐀ébYXΩ😃Ωb\n\nYa𐐀\n𐐀\na"
diff279_before: .quad 27,28
diff279_pairs: .quad 4,0,25,6,0,2,29,24,15,33
diff279_payload0: .ascii "YXΩ😃Ω"
diff279_payload1: .ascii "\n\nY"
diff279_edits:
    .quad 14,14,diff279_payload0,10
    .quad 15,16,diff279_payload1,3
diff280_source: .ascii "bb!"
diff280_after: .ascii "bb\n😃\nX!X"
diff280_before: .quad 0,1,2,1,2,2,0,0
diff280_pairs: .quad 9,7
diff280_payload0: .ascii "\n😃\nX"
diff280_payload1: .ascii "X"
diff280_edits:
    .quad 2,2,diff280_payload0,7
    .quad 3,3,diff280_payload1,1
diff281_source: .ascii "bé!!\nβ!\nb"
diff281_after: .ascii "bé!!YΩXΩYYβXYYYb"
diff281_before: .quad 0,11,6,11,4,11,0,1,4,1
diff281_pairs: .quad 19,4,9,6
diff281_payload0: .ascii "Y"
diff281_payload1: .ascii "ΩXΩYY"
diff281_payload2: .ascii "XYYY"
diff281_edits:
    .quad 5,6,diff281_payload0,1
    .quad 6,6,diff281_payload1,7
    .quad 8,10,diff281_payload2,4
diff282_source: .ascii "β!éβ!𐐀𐐀!!β"
diff282_after: .ascii "YΩXX!YYYΩ😃éβ😃X😃\nYΩ😃\nY\nY😃XΩX\n"
diff282_before: .quad 5,20,18,17,7,18
diff282_pairs: .quad 2,29,49,23,37,19,44,7,9,3
diff282_payload0: .ascii "YΩXX"
diff282_payload1: .ascii "YYYΩ😃"
diff282_payload2: .ascii "😃X😃\nY"
diff282_payload3: .ascii "Ω"
diff282_payload4: .ascii "😃\nY\nY"
diff282_payload5: .ascii "😃XΩX\n"
diff282_edits:
    .quad 0,2,diff282_payload0,5
    .quad 3,3,diff282_payload1,9
    .quad 7,16,diff282_payload2,11
    .quad 16,18,diff282_payload3,2
    .quad 18,20,diff282_payload4,8
    .quad 20,20,diff282_payload5,9
diff283_source: .ascii "βéβa"
diff283_after: .ascii "βéβa"
diff283_before: .quad 4,6
diff283_pairs: .quad 6,4,6,2,6,2
diff283_edits:
diff284_source: .ascii "bβéβ𐐀!𐐀β!!\n𐐀\nbéé"
diff284_after: .ascii "bβéβYΩY\nΩ𐐀!!\nY𐐀YXé"
diff284_before: .quad 3,21,1,18,29,5,21,26
diff284_pairs: .quad 7,5,11,14,3,12,18,3,30,22
diff284_payload0: .ascii "YΩY"
diff284_payload1: .ascii "\nΩ"
diff284_payload2: .ascii ""
diff284_payload3: .ascii "Y"
diff284_payload4: .ascii "YX"
diff284_edits:
    .quad 7,11,diff284_payload0,4
    .quad 11,12,diff284_payload1,3
    .quad 16,18,diff284_payload2,0
    .quad 21,21,diff284_payload3,1
    .quad 25,29,diff284_payload4,2
diff285_source: .ascii "bb𐐀éβ𐐀a!𐐀\naa𐐀"
diff285_after: .ascii "bb\n\nX\n😃Y😃\n😃X😃YYY"
diff285_before: .quad 27,22,15,0,10,8,21,23,21,21
diff285_pairs: .quad 18,5
diff285_payload0: .ascii "\n\nX"
diff285_payload1: .ascii "\n😃Y😃"
diff285_payload2: .ascii "\n"
diff285_payload3: .ascii ""
diff285_payload4: .ascii "😃X😃"
diff285_payload5: .ascii "YYY"
diff285_edits:
    .quad 2,6,diff285_payload0,3
    .quad 6,8,diff285_payload1,10
    .quad 8,20,diff285_payload2,1
    .quad 20,21,diff285_payload3,0
    .quad 21,23,diff285_payload4,9
    .quad 23,27,diff285_payload5,3
diff286_source: .ascii "é𐐀ab𐐀\n\n\naba!éé\n\néébbb𐐀éa"
diff286_after: .ascii "YX\n\naba!éé\nYa"
diff286_before: .quad 18,27
diff286_pairs: .quad 3,4,7,15,6,5,3,5
diff286_payload0: .ascii "YX\n"
diff286_payload1: .ascii "Y"
diff286_edits:
    .quad 0,14,diff286_payload0,3
    .quad 24,38,diff286_payload1,1
diff287_source: .ascii "b!b!𐐀\n𐐀aβé\n𐐀!aa!βb\nb"
diff287_after: .ascii "b!😃\nYΩΩX😃a\nΩXβ😃😃XΩYX\nb"
diff287_before: .quad 24,14,16,18,0,2,2,23
diff287_pairs: .quad 28,1,24,7,36,39,37,39,28,19
diff287_payload0: .ascii "😃\nYΩΩ"
diff287_payload1: .ascii "X😃"
diff287_payload2: .ascii "\nΩX"
diff287_payload3: .ascii "😃"
diff287_payload4: .ascii ""
diff287_payload5: .ascii "😃XΩYX"
diff287_edits:
    .quad 2,4,diff287_payload0,10
    .quad 4,13,diff287_payload1,5
    .quad 14,14,diff287_payload2,4
    .quad 16,18,diff287_payload3,4
    .quad 18,19,diff287_payload4,0
    .quad 19,30,diff287_payload5,9
diff288_source: .ascii "aaééaβéββaββbβa\néb𐐀abé"
diff288_after: .ascii "aaééaβéββaββbβa\néb𐐀abé"
diff288_before: .quad 33,20
diff288_pairs: .quad 3,32,36,2
diff288_edits:
diff289_source: .ascii "ba𐐀b"
diff289_after: .ascii "XbYΩ\n😃X\nXbX"
diff289_before: .quad 6,6,2,7
diff289_pairs: .quad 12,1,11,2,11,3,14,5
diff289_payload0: .ascii "X"
diff289_payload1: .ascii "YΩ\n😃"
diff289_payload2: .ascii "X\n"
diff289_payload3: .ascii "X"
diff289_payload4: .ascii "X"
diff289_edits:
    .quad 0,0,diff289_payload0,1
    .quad 1,2,diff289_payload1,8
    .quad 2,6,diff289_payload2,2
    .quad 6,6,diff289_payload3,1
    .quad 7,7,diff289_payload4,1
diff290_source: .ascii "𐐀!!𐐀𐐀\n\naéaba!b\nbβ"
diff290_after: .ascii "𐐀!!𐐀𐐀\n\naéaba!b\nbβ"
diff290_before: .quad 26,19,23,20
diff290_pairs: .quad 17,10,15,15,21,19
diff290_edits:
diff291_source: .ascii "𐐀a𐐀βé\na!\nβé\nbb\néβ𐐀é!β"
diff291_after: .ascii "𐐀a😃βé\na!\nβé\n\n😃bb\néβ𐐀é!β"
diff291_before: .quad 35,14,17,24
diff291_pairs: .quad 2,5,23,43,38,19
diff291_payload0: .ascii "😃"
diff291_payload1: .ascii "\n😃"
diff291_edits:
    .quad 5,9,diff291_payload0,4
    .quad 22,22,diff291_payload1,5
diff292_source: .ascii "b𐐀ββbé!a\n!\n\na!𐐀aaβ!éba\n"
diff292_after: .ascii "b𐐀ββ😃b😃😃Y\nX"
diff292_before: .quad 19,31,25,34,13,1
diff292_pairs: .quad 25,0,1,14,1,9
diff292_payload0: .ascii "😃"
diff292_payload1: .ascii "😃😃Y\nX"
diff292_edits:
    .quad 9,31,diff292_payload0,4
    .quad 32,34,diff292_payload1,11
diff293_source: .ascii "𐐀\n\nab\n!b𐐀ββ"
diff293_after: .ascii "\nXYab\n!\n\n😃XΩb𐐀😃Y😃Xβ😃Ω😃YΩβ"
diff293_before: .quad 17,19,5,11
diff293_pairs: .quad 7,31,26,3,17,3,43,33
diff293_payload0: .ascii "\n"
diff293_payload1: .ascii "XY"
diff293_payload2: .ascii "\n\n😃XΩ"
diff293_payload3: .ascii "😃Y😃X"
diff293_payload4: .ascii "😃Ω😃YΩ"
diff293_edits:
    .quad 0,4,diff293_payload0,1
    .quad 4,6,diff293_payload1,2
    .quad 10,10,diff293_payload2,9
    .quad 15,15,diff293_payload3,10
    .quad 17,17,diff293_payload4,13
diff294_source: .ascii "éé!\n\n𐐀β𐐀βb𐐀é!b!!é\né𐐀béβ"
diff294_after: .ascii "éé!\n\n𐐀😃Y\n😃βb𐐀é!b!!é\né𐐀béβ"
diff294_before: .quad 40,17,24,5,40,11,26,19
diff294_pairs: .quad 3,21,15,5,31,15
diff294_payload0: .ascii "😃Y\n😃"
diff294_edits:
    .quad 11,17,diff294_payload0,10
diff295_source: .ascii "𐐀!!βa"
diff295_after: .ascii "\n😃😃X!Y!XβXa😃XYΩ"
diff295_before: .quad 5,5,0,8
diff295_pairs: .quad 13,22
diff295_payload0: .ascii "\n😃😃"
diff295_payload1: .ascii "X"
diff295_payload2: .ascii "Y"
diff295_payload3: .ascii "X"
diff295_payload4: .ascii "X"
diff295_payload5: .ascii "😃XYΩ"
diff295_edits:
    .quad 0,4,diff295_payload0,9
    .quad 4,4,diff295_payload1,1
    .quad 5,5,diff295_payload2,1
    .quad 6,6,diff295_payload3,1
    .quad 8,8,diff295_payload4,1
    .quad 9,9,diff295_payload5,8
diff296_source: .ascii "ββaa!β!b𐐀ééβ\n𐐀βbb"
diff296_after: .ascii "ββaa!β!b𐐀ééβ\n𐐀βbb"
diff296_before: .quad 10,9,2,28,5,5
diff296_pairs: .quad 7,0,0,7,30,28,7,5
diff296_edits:
diff297_source: .ascii "β\n!\n!\nβ"
diff297_after: .ascii "ΩΩX\n!\nXYXΩΩ😃Yβ😃\nYX"
diff297_before: .quad 3,4,7,0
diff297_pairs: .quad 1,19,28,2,8,4,8,6,8,2
diff297_payload0: .ascii "ΩΩX"
diff297_payload1: .ascii "\nX"
diff297_payload2: .ascii "YXΩΩ"
diff297_payload3: .ascii "😃Y"
diff297_payload4: .ascii "😃\nYX"
diff297_edits:
    .quad 0,2,diff297_payload0,5
    .quad 4,5,diff297_payload1,2
    .quad 5,6,diff297_payload2,6
    .quad 6,7,diff297_payload3,5
    .quad 9,9,diff297_payload4,7
diff298_source: .ascii "β!!a𐐀ééb𐐀βa!\néb!é"
diff298_after: .ascii "XXΩXXβ!!a𐐀ééb𐐀βa\n\nΩXb😃Xé"
diff298_before: .quad 13,29,5,25,3,9,21,22,5,14
diff298_pairs: .quad 28,29,0,40,40,9,15,5
diff298_payload0: .ascii "XXΩXX"
diff298_payload1: .ascii "\n\nΩX"
diff298_payload2: .ascii "😃X"
diff298_edits:
    .quad 0,0,diff298_payload0,6
    .quad 21,25,diff298_payload1,5
    .quad 26,27,diff298_payload2,5
diff299_source: .ascii "bβ\naβ𐐀"
diff299_after: .ascii "bβΩ😃\nΩX\naΩ😃YY𐐀"
diff299_before: .quad 1,7,4,0,1,4,5,0,1,3
diff299_pairs: .quad 27,23
diff299_payload0: .ascii "Ω😃\nΩX"
diff299_payload1: .ascii "Ω😃YY"
diff299_edits:
    .quad 3,3,diff299_payload0,10
    .quad 5,7,diff299_payload1,8
