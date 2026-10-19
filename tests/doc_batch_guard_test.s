.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
context: .quad 0
calls: .quad 0
bad: .quad 0
mode: .quad 0
snapshot: .quad 0
extras: .quad 0
sn_snapshot: .quad 0
external: .quad 0
guard: .zero GDC_SIZE
edits: .zero DBE_SIZE*2
pairs: .zero DMP_SIZE*2
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


# The callback checks the complete original state, then performs only its selected test action.
callback:
    PROLOGUE 16
    lea rax, [rip + context]
    cmp rdi, rax
    jne .Lcb_bad
    inc qword ptr [rip + calls]
    mov rbx, [rdi]
    mov rdi, rbx
    mov rsi, [rip + snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz .Lcb_bad
    mov rdi, rbx
    call compare_extras
    test eax, eax
    jz .Lcb_bad
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rip + sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz .Lcb_bad
    mov rdi, rbx
    lea rsi, [rip + original]
    mov edx, 6
    lea rcx, [rip + before_pairs]
    mov r8d, 2
    cmp qword ptr [rip + mode], 33
    jb 20f
    mov r8d, 1
    cmp qword ptr [rip + mode], 35
    jne 20f
    lea rcx, [rip + max_before]
    mov r8d, DOC_SELECTIONS_MAX
20: call check
    test eax, eax
    jz .Lcb_bad
    mov r12, [rip + mode]
    cmp r12, 1
    je .Lcb_no
    cmp r12, 34
    je .Lcb_no
    cmp r12, 4
    jne 1f
    mov qword ptr [rbx + DOC_cur], 3
1:  cmp r12, 5
    jne 2f
    inc qword ptr [rbx + DOC_version]
2:  cmp r12, 6
    jne 3f
    or dword ptr [rbx + DOC_flags], DF_READONLY
3:  cmp r12, 7
    jne 4f
    inc qword ptr [rbx + DOC_lastkind]
4:  cmp r12, 8
    jne 5f
    mov rax, [rbx + DOC_selections]
    mov qword ptr [rax + DMS_DATA + DMP_cur], 5
5:  cmp r12, 9
    jne 6f
    mov rax, [rbx + DOC_selections]
    mov qword ptr [rax + DMS_count], 0
6:  cmp r12, 13
    jne 7f
    inc qword ptr [rbx + DOC_group]
7:  cmp r12, 14
    jne 8f
    inc qword ptr [rbx + DOC_prefx]
8:  cmp r12, 15
    jne 9f
    inc qword ptr [rbx + DOC_undo + VEC_cap]
9:  cmp r12, 16
    jne 10f
    inc qword ptr [rbx + DOC_redo + VEC_cap]
10: cmp r12, 17
    jne 11f
    mov qword ptr [rbx + DOC_selectionbatch], 1
11: cmp r12, 18
    jne 12f
    mov qword ptr [rbx + DOC_selections], 0
12: cmp r12, 19
    jne 13f
    mov rax, [rbx + DOC_selections]
    mov qword ptr [rax + DMS_DATA + DMP_anchor], 3
13: cmp r12, 10
    jne .Lcb_yes
    mov rdi, [rip + external]
    call mem_free
    mov qword ptr [rip + external], 0
.Lcb_yes:
    mov eax, 1
    EPILOGUE
.Lcb_bad:
    mov qword ptr [rip + bad], 1
.Lcb_no:
    xor eax, eax
    EPILOGUE

# Compare the original secondary block, including the primary-only null representation.
compare_extras:
    mov rsi, [rip + extras]
    mov rdi, [rdi + DOC_selections]
    test rsi, rsi
    jnz 1f
    xor eax, eax
    test rdi, rdi
    sete al
    ret
1:  test rdi, rdi
    jz 2f
    mov rdx, [rsi + DMS_count]
    cmp rdx, [rdi + DMS_count]
    jne 2f
    shl rdx, 4
    add rdx, DMS_DATA
    jmp memeq
2:  xor eax, eax
    ret

FN main
    PROLOGUE 112
    mov r13d, 1
.Lcase:
    cmp r13d, 35
    ja .Ldone
    mov r15, [rip + g_mem_live]
    mov [rip + mode], r13
    mov qword ptr [rip + calls], 0
    mov qword ptr [rip + bad], 0
    mov qword ptr [rip + external], 0
    call doc_new
    mov rbx, rax
    mov [rip + context], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + original]
    mov ecx, 6
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 6
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    lea rsi, [rip + before_pairs]
    mov edx, 2
    cmp r13d, 33
    jb 20f
    mov edx, 1
    cmp r13d, 35
    jne 20f
    lea rsi, [rip + max_before]
    mov edx, DOC_SELECTIONS_MAX
20: call doc_selections_set
    cmp eax, 1
    jne failed
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov esi, SN_SIZE
    mov rdi, rax
    call mem_dup
    mov [rip + sn_snapshot], rax
    lea rdi, [rip + edits]
    lea rsi, [rip + valid_edits]
    mov edx, DBE_SIZE*2
    call memcpy
    lea rdi, [rip + pairs]
    lea rsi, [rip + after_pairs]
    mov edx, DMP_SIZE*2
    call memcpy
    lea rax, [rip + callback]
    mov [rip + guard + GDC_callback], rax
    lea rax, [rip + context]
    mov [rip + guard + GDC_context], rax
    cmp r13d, 11
    jne 1f
    mov rdi, rbx
    call doc_begin_group
1:  cmp r13d, 20
    jne 2f
    mov qword ptr [rip + edits + DBE_start], 7
2:  cmp r13d, 21
    jne 3f
    lea rax, [rip + invalid_utf8]
    mov [rip + edits + DBE_text], rax
    mov qword ptr [rip + edits + DBE_len], 1
3:  cmp r13d, 22
    jne 4f
    mov qword ptr [rip + edits + DBE_len], DOC_MULTI_BYTES_MAX + 1
4:  cmp r13d, 23
    jne 5f
    mov qword ptr [rip + pairs + DMP_cur], 999
5:  cmp r13d, 24
    jne 6f
    or dword ptr [rbx + DOC_flags], DF_READONLY
6:  cmp r13d, 25
    jne 7f
    mov qword ptr [rbx + DOC_selectionbatch], 1
7:  cmp r13d, 26
    jne 8f
    mov qword ptr [rip + guard + GDC_callback], 0
8:  cmp r13d, 30
    jne 9f
    mov qword ptr [rip + edits + DBE_text], 0
9:  cmp r13d, 31
    jne 10f
    # The final offset one lies inside the replacement scalar Ω.
    lea rax, [rip + omega]
    mov [rip + edits + DBE_text], rax
    mov qword ptr [rip + pairs + DMP_cur], 1
10: cmp r13d, 32
    jne 11f
    # Invalid current oriented endpoint also rejects before the callback.
    mov qword ptr [rbx + DOC_cur], 7
11: mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + snapshot], rax
    mov rdi, rbx
    call doc_selections_snapshot
    mov [rip + extras], rax
    # Callback may release the owners of borrowed descriptors, outputs, GDC, and text.
    cmp r13d, 10
    jne .Largs
    mov edi, 120
    call mem_alloc
    mov [rip + external], rax
    mov rdi, rax
    lea rsi, [rip + edits]
    mov edx, DBE_SIZE*2
    call memcpy
    mov rdi, [rip + external]
    add rdi, 64
    lea rsi, [rip + pairs]
    mov edx, DMP_SIZE*2
    call memcpy
    mov rdi, [rip + external]
    add rdi, 96
    lea rsi, [rip + payload]
    mov edx, 4
    call memcpy
    mov rdi, [rip + external]
    add rdi, 104
    lea rsi, [rip + guard]
    mov edx, GDC_SIZE
    call memcpy
    mov rax, [rip + external]
    lea rdx, [rax + 96]
    mov [rax + DBE_text], rdx
    add rdx, 2
    mov [rax + DBE_SIZE + DBE_text], rdx
.Largs:
    mov rdi, rbx
    lea rsi, [rip + edits]
    mov edx, 2
    lea rcx, [rip + pairs]
    mov r8d, 2
    lea r9, [rip + guard]
    cmp r13d, 33
    jb 20f
    cmp r13d, 35
    je 20f
    mov r8d, 1
20: cmp r13d, 3
    jne 1f
    xor edx, edx
1:  cmp r13d, 10
    jne 2f
    mov rsi, [rip + external]
    lea rcx, [rsi + 64]
    lea r9, [rsi + 104]
2:  cmp r13d, 12
    jne 3f
    xor r9d, r9d              # explicit unguarded new API remains equivalent
3:  cmp r13d, 27
    jne 4f
    mov r8d, DOC_SELECTIONS_MAX + 1
4:  cmp r13d, 28
    jne 5f
    mov edx, DOC_BATCH_EDITS_MAX + 1
5:  cmp r13d, 29
    jne 6f
    xor r8d, r8d
6:  call doc_selections_apply_guarded
    lea rcx, [rip + expected_errors]
    mov r14, [rcx + r13*8 - 8]
    cmp rdx, r14
    jne failed
    cmp qword ptr [rip + bad], 0
    jne failed
    mov ecx, 1
    cmp r13d, 12
    je 7f
    cmp r13d, 20
    jb 8f
    cmp r13d, 33
    jae 8f
7:  xor ecx, ecx
8:  cmp rcx, [rip + calls]
    jne failed
    test r14, r14
    jz .Laccepted
    test eax, eax
    jnz failed
    cmp r14, 6
    je .Lstale
    mov rdi, rbx
    mov rsi, [rip + snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    jmp .Lrejected_sn
.Lstale:
    # Verify the guard's deliberate change remains, without a prepared text/history edit.
    mov rdi, rbx
    mov rsi, [rip + snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz 1f
    cmp r13d, 8
    jb failed
1:  cmp r13d, 4
    jne 2f
    cmp qword ptr [rbx + DOC_cur], 3
    jne failed
2:  cmp r13d, 5
    jne 3f
    mov rax, [rip + snapshot]
    mov rax, [rax + DOC_version]
    inc rax
    cmp [rbx + DOC_version], rax
    jne failed
3:  cmp r13d, 6
    jne 4f
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jz failed
4:  cmp r13d, 7
    jne 5f
    mov rax, [rip + snapshot]
    mov rax, [rax + DOC_lastkind]
    inc rax
    cmp [rbx + DOC_lastkind], rax
    jne failed
5:  cmp r13d, 8
    jne 6f
    mov rax, [rbx + DOC_selections]
    cmp qword ptr [rax + DMS_DATA + DMP_cur], 5
    jne failed
6:  cmp r13d, 9
    jne 7f
    mov rax, [rbx + DOC_selections]
    cmp qword ptr [rax + DMS_count], 0
    jne failed
7:  mov rax, [rip + snapshot]
    mov rcx, [rax + DOC_undo + VEC_len]
    cmp rcx, [rbx + DOC_undo + VEC_len]
    jne failed
    mov rcx, [rax + DOC_redo + VEC_len]
    cmp rcx, [rbx + DOC_redo + VEC_len]
    jne failed
    # Test-only scalar/header changes are restored for normal lifetime cleanup.
    mov rdi, rbx
    mov rsi, rax
    mov edx, DOC_SIZE
    call memcpy
    mov rdi, [rbx + DOC_selections]
    mov rsi, [rip + extras]
    mov edx, DMS_DATA + DMP_SIZE
    call memcpy
.Lrejected_sn:
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rip + sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, rbx
    call compare_extras
    test eax, eax
    jz failed
    jmp .Lfree
.Laccepted:
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + after]
    mov edx, 6
    lea rcx, [rip + after_pairs]
    mov r8d, 2
    cmp r13d, 33
    jne 20f
    mov r8d, 1
20: cmp r13d, 3
    jne 1f
    lea rsi, [rip + original]
1:  call check
    test eax, eax
    jz failed
    cmp r13d, 3
    jne .Lhistory
    mov rax, [rip + snapshot]
    mov rcx, [rax + DOC_snippet]
    cmp [rbx + DOC_snippet], rcx
    jne failed
    mov rcx, [rax + DOC_undo + VEC_len]
    cmp [rbx + DOC_undo + VEC_len], rcx
    jne failed
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
    jmp .Lfree
.Lhistory:
    cmp qword ptr [rbx + DOC_snippet], 0
    jne failed
    cmp r13d, 11
    jne .Lreplay_begin
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    mov esi, 6
    lea rdx, [rip + bang]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + later_pairs]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    mov rax, [rip + snapshot]
    mov rsi, [rax + DOC_undo + VEC_len]
    call doc_selections_record_after
    mov rdi, rbx
    call doc_end_group
.Lreplay_begin:
    mov r14d, 3
.Lreplay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + original]
    mov edx, 6
    lea rcx, [rip + before_pairs]
    mov r8d, 2
    cmp r13d, 33
    jne 20f
    mov r8d, 1
20: cmp r13d, 35
    jne 21f
    lea rcx, [rip + max_before]
    mov r8d, DOC_SELECTIONS_MAX
21: call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + after]
    mov edx, 6
    lea rcx, [rip + after_pairs]
    mov r8d, 2
    cmp r13d, 33
    jne 20f
    mov r8d, 1
20: cmp r13d, 11
    jne 1f
    lea rsi, [rip + later]
    mov edx, 7
    lea rcx, [rip + later_pairs]
1:  call check
    test eax, eax
    jz failed
    dec r14
    jnz .Lreplay
.Lfree:
    # Preflight-only invalid metadata must not escape the fixture.
    mov qword ptr [rbx + DOC_selectionbatch], 0
    mov rdi, [rip + snapshot]
    call mem_free
    mov rdi, [rip + extras]
    call mem_free
    mov rdi, [rip + sn_snapshot]
    call mem_free
    mov rdi, [rip + external]
    call mem_free
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r13
    jmp .Lcase
.Ldone:
    lea rdi, [rip + success]
    mov esi, success_end-success
    call log_write
    xor eax, eax
    EPILOGUE
failed:
    lea rdi, [rip + out]
    lea rsi, [rip + failure]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE
.section .rodata
.p2align 3
# 1 reject; 2 accept; 3 selection only; 4..9 stale fields; 10 freed sources;
# 11 enclosing group; 12 unguarded; 13..19 stale metadata; 20..32 invalid preflight.
expected_errors: .quad 5,0,0,6,6,6,6,6,6,0,0,0,6,6,6,6,6,6,6,1,1,2,1,3,4,1,2,2,1,1,1,1,0,5,0
max_before: .zero DMP_SIZE*DOC_SELECTIONS_MAX
before_pairs: .quad 2,0,6,4
after_pairs: .quad 2,2,6,6
later_pairs: .quad 3,3,7,7
valid_edits: .quad 0,2,payload,2,4,6,omega,2
original: .ascii "abcdef"
after: .ascii "XYcdΩ"
later: .ascii "XYcdΩ!"
payload: .ascii "XY"
omega: .ascii "Ω"
letter: .ascii "x"
bang: .ascii "!"
invalid_utf8: .byte 0x80
success: .ascii "doc batch guard: 35 cases passed\n"
success_end:
failure: .asciz "guard case failed: "
