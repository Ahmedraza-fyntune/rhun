.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
cut_capture: .zero SB_SIZE
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
    je .Lgroups
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rbx
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
    mov eax, [r12 + 48]
    mov [rip + cfg_auto_pairs], eax
    mov eax, [r12 + 56]
    mov [rip + g_insert_spaces], eax
    mov eax, [r12 + 64]
    mov [rip + g_tab_width], eax
    mov qword ptr [rsp + 24], 0
    cmp qword ptr [r12 + 112], 0
    je .Lno_snippet
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    call snippet_new
    mov r14, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
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
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    mov rdi, r14
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 24], rax
.Lno_snippet:
    test qword ptr [r12 + 120], 1
    jz 2f
    or dword ptr [rbx + DOC_flags], DF_READONLY
2:  test qword ptr [r12 + 120], 2
    jz 3f
    mov qword ptr [rbx + DOC_selectionbatch], -1
3:  test qword ptr [r12 + 120], 4
    jz 4f
    mov qword ptr [rip + g_doc], 0
4:  test qword ptr [r12 + 120], 8
    jz 5f
    mov qword ptr [rbx + DOC_cur], 1
5:  test qword ptr [r12 + 120], 16
    jz 6f
    mov rdi, rbx
    call doc_begin_group
6:  mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp], rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [r12 + 32]
    mov rdx, [r12 + 40]
    mov rcx, [r12 + 104]
    call editor_multi_delete_limited
    cmp rdx, [r12 + 112]
    jne failed
    cmp qword ptr [r12 + 112], 0
    je .Lsuccess
    test eax, eax
    jnz failed
    mov rdi, rbx
    mov rsi, [rsp]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 24]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    jmp .Lfree
.Lsuccess:
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 72]
    mov rdx, [r12 + 80]
    mov rcx, [r12 + 88]
    mov r8, [r12 + 96]
    call check
    test eax, eax
    jz failed
    test qword ptr [r12 + 120], 16
    jz 1f
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    call doc_end_group
1:  mov rax, [rbx + DOC_undo + VEC_len]
    cmp rax, [rsp + 8]
    jne .Ledited
    cmp qword ptr [rbx + DOC_redo + VEC_len], 1
    jne failed
    jmp .Lfree
.Ledited:
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
    mov rsi, [r12 + 72]
    mov rdx, [r12 + 80]
    mov rcx, [r12 + 88]
    mov r8, [r12 + 96]
    call check
    test eax, eax
    jz failed
    dec r14
    jnz .Lreplay
    cmp qword ptr [r12 + 24], 1
    jbe .Lfree
    mov rdi, rbx
    call doc_undo
    mov edi, [r12 + 40]
    cmp qword ptr [r12 + 32], 0
    jne 1f
    call ed_backspace
    jmp 2f
1:  call ed_delete_fwd
2:  mov rdi, rbx
    mov rsi, [r12 + 72]
    mov rdx, [r12 + 80]
    mov rcx, [r12 + 88]
    mov r8, [r12 + 96]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    call doc_redo
    mov rdi, rbx
    mov rsi, [r12 + 72]
    mov rdx, [r12 + 80]
    mov rcx, [r12 + 88]
    mov r8, [r12 + 96]
    call check
    test eax, eax
    jz failed
.Lfree:
    mov rdi, [rsp + 24]
    call mem_free
    mov rdi, [rsp]
    call mem_free
    mov qword ptr [rbx + DOC_selectionbatch], 0
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 128
    inc r13
    jmp .Lcase
.Lgroups:
    xor r12d, r12d
.Lgroup:
    lea r13, [r12 + 100]
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + group_source]
    mov ecx, 7
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + group_initial]
    cmp r12, 1
    jne 1f
    lea rsi, [rip + group_forward]
1:  mov edx, 2
    call doc_selections_set
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    cmp r12, 7
    jne 2f
    mov rdi, rbx
    call doc_begin_group
2:  mov rdi, rbx
    xor esi, esi
    cmp r12, 1
    sete sil
    xor edx, edx
    call editor_multi_delete
    cmp eax, 1
    jne failed
    cmp r12, 7
    je .Lgroup_outer
    cmp r12, 3
    jne 3f
    sub qword ptr [rbx + DOC_lastedit], 1600
3:  cmp r12, 4
    jb .Lgroup_second
    mov rax, r12
    shl rax, 6
    lea rdx, [rip + group_vectors]
    add rax, rdx
    mov rdi, rbx
    mov rsi, [rax + 32]
    mov rdx, [rax + 40]
    call doc_selections_set
.Lgroup_second:
    mov rdi, rbx
    xor esi, esi
    cmp r12, 1
    je 4f
    cmp r12, 2
    jne 5f
4:  mov esi, 1
5:  xor edx, edx
    call editor_multi_delete
    cmp eax, 1
    jne failed
    cmp r12, 1
    ja .Lgroup_result
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    call editor_multi_delete
    cmp eax, 1
    jne failed
    jmp .Lgroup_result
.Lgroup_outer:
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_selections_record_after
    mov rdi, rbx
    call doc_end_group
.Lgroup_result:
    mov r14, r12
    shl r14, 6
    lea rax, [rip + group_vectors]
    add r14, rax
    mov qword ptr [rsp + 8], 3
.Lgroup_replay:
    mov rdi, rbx
    mov rsi, [r14]
    mov rdx, [r14 + 8]
    mov rcx, [r14 + 16]
    mov r8, [r14 + 24]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    cmp r12, 2
    jb .Lgroup_original
    cmp r12, 7
    jae .Lgroup_original
    mov rdi, rbx
    lea rsi, [rip + group_first]
    mov edx, 5
    mov rcx, [r14 + 32]
    mov r8, [r14 + 40]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
.Lgroup_original:
    mov rdi, rbx
    lea rsi, [rip + group_source]
    mov edx, 7
    mov rcx, [r14 + 48]
    mov r8, [r14 + 56]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    cmp r12, 2
    jb .Lgroup_again
    cmp r12, 7
    jae .Lgroup_again
    mov rdi, rbx
    lea rsi, [rip + group_first]
    mov edx, 5
    lea rcx, [rip + group_first_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
.Lgroup_again:
    dec qword ptr [rsp + 8]
    jnz .Lgroup_replay
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    inc r12
    cmp r12, 8
    jb .Lgroup
    mov r13d, 120
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + word_source]
    mov ecx, 27
    xor r8d, r8d
    call doc_insert
    xor r12d, r12d
.Lword_direction:
    xor r14d, r14d
.Lword_position:
    mov rdi, rbx
    mov rsi, r14
    test r12, r12
    jnz 6f
    call doc_word_left
    jmp 7f
6:  call doc_word_right
7:  mov [rsp], rax
    mov qword ptr [rsp + 8], DOC_MULTI_BYTES_MAX
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    lea rcx, [rsp + 8]
    call editor_delete_word
    test edx, edx
    jnz failed
    cmp rax, [rsp]
    jne failed
    cmp r14, 27
    jae .Lword_next
    mov rdi, rbx
    mov rsi, r14
    call doc_next_char
    mov r14, rax
    jmp .Lword_position
.Lword_next:
    inc r12
    cmp r12, 2
    jb .Lword_direction
    mov rdi, rbx
    call doc_free
    cmp r15, [rip + g_mem_live]
    jne failed
    # Warm the existing global clipboard cache before measuring Cut's live allocations.
    mov rax, [rip + g_plat + P_clip_set]
    mov [rsp + 40], rax
    lea rax, [rip + capture_clip]
    mov [rip + g_plat + P_clip_set], rax
    call cut_doc
    mov rbx, rax
    call cmd_copy
    mov rdi, rbx
    call doc_free
    mov r15, [rip + g_mem_live]
    call cut_doc
    mov rbx, rax
    mov r13d, 130
    call cmd_cut
    cmp qword ptr [rip + cut_capture + SB_len], 5
    jne failed
    mov rdi, [rip + cut_capture + SB_ptr]
    lea rsi, [rip + cut_clipboard]
    mov edx, 5
    call memeq
    test eax, eax
    jz failed
    mov rdi, rbx
    lea rsi, [rip + cut_result]
    mov edx, 1
    lea rcx, [rip + cut_after]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    lea rdi, [rip + cut_capture]
    call sb_free
    mov rax, [rsp + 40]
    mov [rip + g_plat + P_clip_set], rax
.Ldone:
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

capture_clip:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + cut_capture]
    call sb_clear
    lea rdi, [rip + cut_capture]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    mov eax, 1
    EPILOGUE
cut_doc:
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + cut_source]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + cut_before]
    mov edx, 2
    call doc_selections_set
    mov rax, rbx
    EPILOGUE
.section .rodata
ok: .asciz "ok editor multiple deletion\n"
fail: .asciz "failed editor multiple deletion case "
letter: .byte 88
group_source: .ascii "abc def"
group_initial: .quad 3,3,7,7
group_forward: .quad 0,0,4,4
group_first: .ascii "ab de"
group_first_pairs: .quad 2,2,5,5
group_moved: .quad 0,0,3,3
group_selected: .quad 1,0,4,3
group_single: .quad 2,2
group_empty: .ascii " "
group_empty_pairs: .quad 0,0,1,1
group_joined: .ascii "abde"
group_joined_pairs: .quad 2,2,4,4
group_twice: .ascii "a d"
group_twice_pairs: .quad 1,1,3,3
group_moved_pairs: .quad 0,0,2,2
group_selected_text: .ascii "b e"
group_single_text: .ascii "a de"
group_single_after: .quad 1,1
group_outer_text: .ascii "Xab de"
group_outer_after: .quad 3,3,6,6
group_vectors:
    .quad group_empty,1,group_empty_pairs,2,group_initial,2,group_initial,2
    .quad group_empty,1,group_empty_pairs,2,group_forward,2,group_forward,2
    .quad group_joined,4,group_joined_pairs,2,group_first_pairs,2,group_initial,2
    .quad group_twice,3,group_twice_pairs,2,group_first_pairs,2,group_initial,2
    .quad group_joined,4,group_moved_pairs,2,group_moved,2,group_initial,2
    .quad group_selected_text,3,group_moved_pairs,2,group_selected,2,group_initial,2
    .quad group_single_text,4,group_single_after,1,group_single,1,group_initial,2
    .quad group_outer_text,6,group_outer_after,2,group_initial,2,group_initial,2
word_source: .ascii "one β中_1++ \t𐀀x\n  end!"
cut_source: .ascii "ab cd"
cut_before: .quad 2,0,5,3
cut_clipboard: .ascii "ab\ncd"
cut_result: .ascii " "
cut_after: .quad 0,0,1,1
vectors:
    # back chars
    .quad v0s,7,v0p,2,0,0,1,1,4,v0r,5,v0a,2,67108864,0,0
    # forward chars
    .quad v1s,7,v1p,2,1,0,1,1,4,v1r,5,v1a,2,67108864,0,0
    # reversed order
    .quad v2s,7,v2p,2,0,0,1,1,4,v2r,5,v2a,2,67108864,0,0
    # selected mixed
    .quad v3s,9,v3p,2,0,0,1,1,4,v3r,3,v3a,2,67108864,0,0
    # selected word forward
    .quad v4s,9,v4p,2,1,1,1,1,4,v4r,3,v4a,2,67108864,0,0
    # selected and caret
    .quad v5s,7,v5p,2,0,0,1,1,4,v5r,4,v5a,2,67108864,0,0
    # overlap
    .quad v6s,6,v6p,2,0,0,1,1,4,v6r,0,v6a,1,67108864,0,0
    # inside caret cannot expand
    .quad v7s,6,v7p,2,0,0,1,1,4,v7r,2,v7a,1,67108864,0,0
    # duplicate
    .quad v8s,3,v8p,2,0,0,1,1,4,v8r,2,v8a,1,67108864,0,0
    # adjacent back
    .quad v9s,4,v9p,2,0,0,1,1,4,v9r,2,v9a,2,67108864,0,0
    # adjacent forward
    .quad v10s,4,v10p,2,1,0,1,1,4,v10r,2,v10a,2,67108864,0,0
    # expanded word overlap
    .quad v11s,10,v11p,2,0,1,1,1,4,v11r,4,v11a,1,67108864,0,0
    # expanded word overlap reverse
    .quad v12s,10,v12p,2,0,1,1,1,4,v12r,4,v12a,1,67108864,0,0
    # expanded fwd word overlap
    .quad v13s,10,v13p,2,1,1,1,1,4,v13r,5,v13a,1,67108864,0,0
    # bof empty
    .quad v14s,0,v14p,2,0,0,1,1,4,v14r,0,v14a,1,67108864,0,0
    # eof empty
    .quad v15s,0,v15p,2,1,0,1,1,4,v15r,0,v15a,1,67108864,0,0
    # bof and end
    .quad v16s,1,v16p,2,0,0,1,1,4,v16r,0,v16a,1,67108864,0,0
    # eof and start
    .quad v17s,1,v17p,2,1,0,1,1,4,v17r,0,v17a,1,67108864,0,0
    # pair (
    .quad v18s,5,v18p,2,0,0,1,1,4,v18r,1,v18a,2,67108864,0,0
    # disabled (
    .quad v19s,5,v19p,2,0,0,0,1,4,v19r,3,v19a,2,67108864,0,0
    # pair [
    .quad v20s,5,v20p,2,0,0,1,1,4,v20r,1,v20a,2,67108864,0,0
    # disabled [
    .quad v21s,5,v21p,2,0,0,0,1,4,v21r,3,v21a,2,67108864,0,0
    # pair {
    .quad v22s,5,v22p,2,0,0,1,1,4,v22r,1,v22a,2,67108864,0,0
    # disabled {
    .quad v23s,5,v23p,2,0,0,0,1,4,v23r,3,v23a,2,67108864,0,0
    # pair "
    .quad v24s,5,v24p,2,0,0,1,1,4,v24r,1,v24a,2,67108864,0,0
    # disabled "
    .quad v25s,5,v25p,2,0,0,0,1,4,v25r,3,v25a,2,67108864,0,0
    # pair '
    .quad v26s,5,v26p,2,0,0,1,1,4,v26r,1,v26a,2,67108864,0,0
    # disabled '
    .quad v27s,5,v27p,2,0,0,0,1,4,v27r,3,v27a,2,67108864,0,0
    # pair `
    .quad v28s,5,v28p,2,0,0,1,1,4,v28r,1,v28a,2,67108864,0,0
    # disabled `
    .quad v29s,5,v29p,2,0,0,0,1,4,v29r,3,v29a,2,67108864,0,0
    # mismatch
    .quad v30s,5,v30p,2,0,0,1,1,4,v30r,3,v30a,2,67108864,0,0
    # space tabstop
    .quad v31s,15,v31p,2,0,0,1,1,4,v31r,11,v31a,2,67108864,0,0
    # width1
    .quad v32s,11,v32p,2,0,0,1,1,1,v32r,9,v32a,2,67108864,0,0
    # width16
    .quad v33s,36,v33p,2,0,0,1,1,16,v33r,19,v33a,2,67108864,0,0
    # tab mode spaces
    .quad v34s,11,v34p,2,0,0,1,0,4,v34r,9,v34a,2,67108864,0,0
    # tab prefix
    .quad v35s,9,v35p,2,0,0,1,1,4,v35r,7,v35a,2,67108864,0,0
    # midline spaces
    .quad v36s,10,v36p,2,0,0,1,1,4,v36r,8,v36a,2,67108864,0,0
    # newlines
    .quad v37s,4,v37p,2,0,0,1,1,4,v37r,2,v37a,2,67108864,0,0
    # forward newlines
    .quad v38s,4,v38p,2,1,0,1,1,4,v38r,2,v38a,2,67108864,0,0
    # unicode2
    .quad v39s,5,v39p,2,0,0,1,1,4,v39r,1,v39a,2,67108864,0,0
    # unicode3
    .quad v40s,7,v40p,2,1,0,1,1,4,v40r,1,v40a,2,67108864,0,0
    # unicode4
    .quad v41s,9,v41p,2,0,0,1,1,4,v41r,1,v41a,2,67108864,0,0
    # nul
    .quad v42s,5,v42p,2,0,0,1,1,4,v42r,3,v42a,2,67108864,0,0
    # word boundaries 0
    .quad v43s,7,v43p,8,0,1,1,1,4,v43r,0,v43a,2,67108864,0,0
    # word boundaries 0
    .quad v44s,11,v44p,12,0,1,1,1,4,v44r,0,v44a,4,67108864,0,0
    # word boundaries 0
    .quad v45s,7,v45p,8,0,1,1,1,4,v45r,0,v45a,4,67108864,0,0
    # word boundaries 0
    .quad v46s,13,v46p,8,0,1,1,1,4,v46r,0,v46a,2,67108864,0,0
    # word boundaries 0
    .quad v47s,11,v47p,12,0,1,1,1,4,v47r,0,v47a,4,67108864,0,0
    # word boundaries 1
    .quad v48s,7,v48p,8,1,1,1,1,4,v48r,0,v48a,2,67108864,0,0
    # word boundaries 1
    .quad v49s,11,v49p,12,1,1,1,1,4,v49r,0,v49a,4,67108864,0,0
    # word boundaries 1
    .quad v50s,7,v50p,8,1,1,1,1,4,v50r,0,v50a,4,67108864,0,0
    # word boundaries 1
    .quad v51s,13,v51p,8,1,1,1,1,4,v51r,0,v51a,2,67108864,0,0
    # word boundaries 1
    .quad v52s,11,v52p,12,1,1,1,1,4,v52r,0,v52a,3,67108864,0,0
    # max512
    .quad v53s,1024,v53p,512,0,0,1,1,4,v53r,512,v53a,512,67108864,0,0
    # zero shared scan after one
    .quad v54s,3,v54p,2,0,1,1,1,4,v54r,1,v54a,2,1,2,0
    # indent scan after one
    .quad v55s,7,v55p,2,0,0,1,1,4,v55r,3,v55a,2,2,2,0
    # readonly
    .quad v56s,3,v56p,2,0,0,1,1,4,v56r,1,v56a,2,67108864,3,1
    # busy
    .quad v57s,3,v57p,2,0,0,1,1,4,v57r,1,v57a,2,67108864,4,2
    # inactive
    .quad v58s,3,v58p,2,0,0,1,1,4,v58r,1,v58a,2,67108864,1,4
    # bad boundary
    .quad v59s,4,v59p,2,0,0,1,1,4,v59r,3,v59a,2,67108864,1,8
    # invalid direction
    .quad v60s,3,v60p,2,2,0,1,1,4,v60r,2,v60a,2,67108864,1,0
    # invalid word
    .quad v61s,3,v61p,2,0,2,1,1,4,v61r,1,v61a,2,67108864,1,0
    # invalid scan
    .quad v62s,3,v62p,2,0,0,1,1,4,v62r,1,v62a,2,67108865,2,0
    # outer group
    .quad v63s,7,v63p,2,0,0,1,1,4,v63r,5,v63a,2,67108864,0,16
    # outer scan error
    .quad v64s,3,v64p,2,0,1,1,1,4,v64r,1,v64a,2,1,2,16
    .quad 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
v0s: .byte 97,98,99,32,100,101,102
v0r: .byte 97,98,32,100,101
v0p: .quad 3,3,7,7
v0a: .quad 2,2,5,5
v1s: .byte 97,98,99,32,100,101,102
v1r: .byte 98,99,32,101,102
v1p: .quad 0,0,4,4
v1a: .quad 0,0,3,3
v2s: .byte 97,98,99,32,100,101,102
v2r: .byte 97,98,32,100,101
v2p: .quad 7,7,3,3
v2a: .quad 5,5,2,2
v3s: .byte 97,98,99,100,32,101,102,103,104
v3r: .byte 100,32,101
v3p: .quad 3,0,9,6
v3a: .quad 0,0,3,3
v4s: .byte 97,98,99,100,32,101,102,103,104
v4r: .byte 100,32,101
v4p: .quad 0,3,6,9
v4a: .quad 0,0,3,3
v5s: .byte 97,98,99,32,100,101,102
v5r: .byte 99,32,100,101
v5p: .quad 2,0,7,7
v5a: .quad 0,0,4,4
v6s: .byte 97,98,99,100,101,102
v6r: .byte 0
v6p: .quad 4,0,2,6
v6a: .quad 0,0
v7s: .byte 97,98,99,100,101,102
v7r: .byte 101,102
v7p: .quad 2,2,4,0
v7a: .quad 0,0
v8s: .byte 97,98,99
v8r: .byte 97,99
v8p: .quad 2,2,2,2
v8a: .quad 1,1
v9s: .byte 97,98,99,100
v9r: .byte 97,100
v9p: .quad 2,2,3,3
v9a: .quad 1,1,1,1
v10s: .byte 97,98,99,100
v10r: .byte 97,100
v10p: .quad 1,1,2,2
v10a: .quad 1,1,1,1
v11s: .byte 97,98,99,100,101,102,32,120,121,122
v11r: .byte 32,120,121,122
v11p: .quad 4,4,6,6
v11a: .quad 0,0
v12s: .byte 97,98,99,100,101,102,32,120,121,122
v12r: .byte 32,120,121,122
v12p: .quad 6,6,4,4
v12a: .quad 0,0
v13s: .byte 97,98,99,100,101,102,32,120,121,122
v13r: .byte 97,32,120,121,122
v13p: .quad 1,1,4,4
v13a: .quad 1,1
v14s: .byte 0
v14r: .byte 0
v14p: .quad 0,0,0,0
v14a: .quad 0,0
v15s: .byte 0
v15r: .byte 0
v15p: .quad 0,0,0,0
v15a: .quad 0,0
v16s: .byte 120
v16r: .byte 0
v16p: .quad 0,0,1,1
v16a: .quad 0,0
v17s: .byte 120
v17r: .byte 0
v17p: .quad 1,1,0,0
v17a: .quad 0,0
v18s: .byte 40,41,32,40,41
v18r: .byte 32
v18p: .quad 1,1,4,4
v18a: .quad 0,0,1,1
v19s: .byte 40,41,32,40,41
v19r: .byte 41,32,41
v19p: .quad 1,1,4,4
v19a: .quad 0,0,2,2
v20s: .byte 91,93,32,91,93
v20r: .byte 32
v20p: .quad 1,1,4,4
v20a: .quad 0,0,1,1
v21s: .byte 91,93,32,91,93
v21r: .byte 93,32,93
v21p: .quad 1,1,4,4
v21a: .quad 0,0,2,2
v22s: .byte 123,125,32,123,125
v22r: .byte 32
v22p: .quad 1,1,4,4
v22a: .quad 0,0,1,1
v23s: .byte 123,125,32,123,125
v23r: .byte 125,32,125
v23p: .quad 1,1,4,4
v23a: .quad 0,0,2,2
v24s: .byte 34,34,32,34,34
v24r: .byte 32
v24p: .quad 1,1,4,4
v24a: .quad 0,0,1,1
v25s: .byte 34,34,32,34,34
v25r: .byte 34,32,34
v25p: .quad 1,1,4,4
v25a: .quad 0,0,2,2
v26s: .byte 39,39,32,39,39
v26r: .byte 32
v26p: .quad 1,1,4,4
v26a: .quad 0,0,1,1
v27s: .byte 39,39,32,39,39
v27r: .byte 39,32,39
v27p: .quad 1,1,4,4
v27a: .quad 0,0,2,2
v28s: .byte 96,96,32,96,96
v28r: .byte 32
v28p: .quad 1,1,4,4
v28a: .quad 0,0,1,1
v29s: .byte 96,96,32,96,96
v29r: .byte 96,32,96
v29p: .quad 1,1,4,4
v29a: .quad 0,0,2,2
v30s: .byte 40,93,32,91,41
v30r: .byte 93,32,41
v30p: .quad 1,1,4,4
v30a: .quad 0,0,2,2
v31s: .byte 32,32,32,32,32,32,32,120,10,32,32,32,32,32,121
v31r: .byte 32,32,32,32,120,10,32,32,32,32,121
v31p: .quad 7,7,14,14
v31a: .quad 4,4,10,10
v32s: .byte 32,32,32,32,120,10,32,32,32,32,121
v32r: .byte 32,32,32,120,10,32,32,32,121
v32p: .quad 4,4,10,10
v32a: .quad 3,3,8,8
v33s: .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,120,10,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,121
v33r: .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,120,10,121
v33p: .quad 17,17,35,35
v33a: .quad 16,16,18,18
v34s: .byte 32,32,32,32,120,10,32,32,32,32,121
v34r: .byte 32,32,32,120,10,32,32,32,121
v34p: .quad 4,4,10,10
v34a: .quad 3,3,8,8
v35s: .byte 9,32,32,120,10,32,9,32,121
v35r: .byte 9,32,120,10,32,9,121
v35p: .quad 3,3,8,8
v35a: .quad 2,2,6,6
v36s: .byte 120,32,32,32,121,32,120,32,32,122
v36r: .byte 120,32,32,121,32,120,32,122
v36p: .quad 4,4,9,9
v36a: .quad 3,3,7,7
v37s: .byte 97,10,98,10
v37r: .byte 97,98
v37p: .quad 2,2,4,4
v37a: .quad 1,1,2,2
v38s: .byte 97,10,98,10
v38r: .byte 97,98
v38p: .quad 1,1,3,3
v38a: .quad 1,1,2,2
v39s: .byte 206,178,32,206,169
v39r: .byte 32
v39p: .quad 2,2,5,5
v39a: .quad 0,0,1,1
v40s: .byte 228,184,173,32,230,150,135
v40r: .byte 32
v40p: .quad 0,0,4,4
v40a: .quad 0,0,1,1
v41s: .byte 240,144,128,128,32,240,144,128,129
v41r: .byte 32
v41p: .quad 4,4,9,9
v41a: .quad 0,0,1,1
v42s: .byte 0,120,32,0,121
v42r: .byte 120,32,121
v42p: .quad 1,1,4,4
v42a: .quad 0,0,2,2
v43s: .byte 97,98,99,32,100,101,102
v43r: .byte 0
v43p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
v43a: .quad 0,0,0,0
v44s: .byte 97,98,99,32,32,10,32,32,100,101,102
v44r: .byte 0
v44p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11
v44a: .quad 0,0,0,0,0,0,0,0
v45s: .byte 97,43,43,32,98,45,45
v45r: .byte 0
v45p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
v45a: .quad 0,0,0,0,0,0,0,0
v46s: .byte 206,178,228,184,173,95,49,32,240,144,128,128,120
v46r: .byte 0
v46p: .quad 0,0,2,2,5,5,6,6,7,7,8,8,12,12,13,13
v46a: .quad 0,0,0,0
v47s: .byte 9,102,111,111,32,9,32,98,97,114,10
v47r: .byte 0
v47p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11
v47a: .quad 0,0,0,0,0,0,0,0
v48s: .byte 97,98,99,32,100,101,102
v48r: .byte 0
v48p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
v48a: .quad 0,0,0,0
v49s: .byte 97,98,99,32,32,10,32,32,100,101,102
v49r: .byte 0
v49p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11
v49a: .quad 0,0,0,0,0,0,0,0
v50s: .byte 97,43,43,32,98,45,45
v50r: .byte 0
v50p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
v50a: .quad 0,0,0,0,0,0,0,0
v51s: .byte 206,178,228,184,173,95,49,32,240,144,128,128,120
v51r: .byte 0
v51p: .quad 0,0,2,2,5,5,6,6,7,7,8,8,12,12,13,13
v51a: .quad 0,0,0,0
v52s: .byte 9,102,111,111,32,9,32,98,97,114,10
v52r: .byte 0
v52p: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11
v52a: .quad 0,0,0,0,0,0
v53s: .byte 120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32
v53r: .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
v53p: .quad 1,1,3,3,5,5,7,7,9,9,11,11,13,13,15,15,17,17,19,19,21,21,23,23,25,25,27,27,29,29,31,31,33,33,35,35,37,37,39,39,41,41,43,43,45,45,47,47,49,49,51,51,53,53,55,55,57,57,59,59,61,61,63,63,65,65,67,67,69,69,71,71,73,73,75,75,77,77,79,79,81,81,83,83,85,85,87,87,89,89,91,91,93,93,95,95,97,97,99,99,101,101,103,103,105,105,107,107,109,109,111,111,113,113,115,115,117,117,119,119,121,121,123,123,125,125,127,127,129,129,131,131,133,133,135,135,137,137,139,139,141,141,143,143,145,145,147,147,149,149,151,151,153,153,155,155,157,157,159,159,161,161,163,163,165,165,167,167,169,169,171,171,173,173,175,175,177,177,179,179,181,181,183,183,185,185,187,187,189,189,191,191,193,193,195,195,197,197,199,199,201,201,203,203,205,205,207,207,209,209,211,211,213,213,215,215,217,217,219,219,221,221,223,223,225,225,227,227,229,229,231,231,233,233,235,235,237,237,239,239,241,241,243,243,245,245,247,247,249,249,251,251,253,253,255,255,257,257,259,259,261,261,263,263,265,265,267,267,269,269,271,271,273,273,275,275,277,277,279,279,281,281,283,283,285,285,287,287,289,289,291,291,293,293,295,295,297,297,299,299,301,301,303,303,305,305,307,307,309,309,311,311,313,313,315,315,317,317,319,319,321,321,323,323,325,325,327,327,329,329,331,331,333,333,335,335,337,337,339,339,341,341,343,343,345,345,347,347,349,349,351,351,353,353,355,355,357,357,359,359,361,361,363,363,365,365,367,367,369,369,371,371,373,373,375,375,377,377,379,379,381,381,383,383,385,385,387,387,389,389,391,391,393,393,395,395,397,397,399,399,401,401,403,403,405,405,407,407,409,409,411,411,413,413,415,415,417,417,419,419,421,421,423,423,425,425,427,427,429,429,431,431,433,433,435,435,437,437,439,439,441,441,443,443,445,445,447,447,449,449,451,451,453,453,455,455,457,457,459,459,461,461,463,463,465,465,467,467,469,469,471,471,473,473,475,475,477,477,479,479,481,481,483,483,485,485,487,487,489,489,491,491,493,493,495,495,497,497,499,499,501,501,503,503,505,505,507,507,509,509,511,511,513,513,515,515,517,517,519,519,521,521,523,523,525,525,527,527,529,529,531,531,533,533,535,535,537,537,539,539,541,541,543,543,545,545,547,547,549,549,551,551,553,553,555,555,557,557,559,559,561,561,563,563,565,565,567,567,569,569,571,571,573,573,575,575,577,577,579,579,581,581,583,583,585,585,587,587,589,589,591,591,593,593,595,595,597,597,599,599,601,601,603,603,605,605,607,607,609,609,611,611,613,613,615,615,617,617,619,619,621,621,623,623,625,625,627,627,629,629,631,631,633,633,635,635,637,637,639,639,641,641,643,643,645,645,647,647,649,649,651,651,653,653,655,655,657,657,659,659,661,661,663,663,665,665,667,667,669,669,671,671,673,673,675,675,677,677,679,679,681,681,683,683,685,685,687,687,689,689,691,691,693,693,695,695,697,697,699,699,701,701,703,703,705,705,707,707,709,709,711,711,713,713,715,715,717,717,719,719,721,721,723,723,725,725,727,727,729,729,731,731,733,733,735,735,737,737,739,739,741,741,743,743,745,745,747,747,749,749,751,751,753,753,755,755,757,757,759,759,761,761,763,763,765,765,767,767,769,769,771,771,773,773,775,775,777,777,779,779,781,781,783,783,785,785,787,787,789,789,791,791,793,793,795,795,797,797,799,799,801,801,803,803,805,805,807,807,809,809,811,811,813,813,815,815,817,817,819,819,821,821,823,823,825,825,827,827,829,829,831,831,833,833,835,835,837,837,839,839,841,841,843,843,845,845,847,847,849,849,851,851,853,853,855,855,857,857,859,859,861,861,863,863,865,865,867,867,869,869,871,871,873,873,875,875,877,877,879,879,881,881,883,883,885,885,887,887,889,889,891,891,893,893,895,895,897,897,899,899,901,901,903,903,905,905,907,907,909,909,911,911,913,913,915,915,917,917,919,919,921,921,923,923,925,925,927,927,929,929,931,931,933,933,935,935,937,937,939,939,941,941,943,943,945,945,947,947,949,949,951,951,953,953,955,955,957,957,959,959,961,961,963,963,965,965,967,967,969,969,971,971,973,973,975,975,977,977,979,979,981,981,983,983,985,985,987,987,989,989,991,991,993,993,995,995,997,997,999,999,1001,1001,1003,1003,1005,1005,1007,1007,1009,1009,1011,1011,1013,1013,1015,1015,1017,1017,1019,1019,1021,1021,1023,1023
v53a: .quad 0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13,14,14,15,15,16,16,17,17,18,18,19,19,20,20,21,21,22,22,23,23,24,24,25,25,26,26,27,27,28,28,29,29,30,30,31,31,32,32,33,33,34,34,35,35,36,36,37,37,38,38,39,39,40,40,41,41,42,42,43,43,44,44,45,45,46,46,47,47,48,48,49,49,50,50,51,51,52,52,53,53,54,54,55,55,56,56,57,57,58,58,59,59,60,60,61,61,62,62,63,63,64,64,65,65,66,66,67,67,68,68,69,69,70,70,71,71,72,72,73,73,74,74,75,75,76,76,77,77,78,78,79,79,80,80,81,81,82,82,83,83,84,84,85,85,86,86,87,87,88,88,89,89,90,90,91,91,92,92,93,93,94,94,95,95,96,96,97,97,98,98,99,99,100,100,101,101,102,102,103,103,104,104,105,105,106,106,107,107,108,108,109,109,110,110,111,111,112,112,113,113,114,114,115,115,116,116,117,117,118,118,119,119,120,120,121,121,122,122,123,123,124,124,125,125,126,126,127,127,128,128,129,129,130,130,131,131,132,132,133,133,134,134,135,135,136,136,137,137,138,138,139,139,140,140,141,141,142,142,143,143,144,144,145,145,146,146,147,147,148,148,149,149,150,150,151,151,152,152,153,153,154,154,155,155,156,156,157,157,158,158,159,159,160,160,161,161,162,162,163,163,164,164,165,165,166,166,167,167,168,168,169,169,170,170,171,171,172,172,173,173,174,174,175,175,176,176,177,177,178,178,179,179,180,180,181,181,182,182,183,183,184,184,185,185,186,186,187,187,188,188,189,189,190,190,191,191,192,192,193,193,194,194,195,195,196,196,197,197,198,198,199,199,200,200,201,201,202,202,203,203,204,204,205,205,206,206,207,207,208,208,209,209,210,210,211,211,212,212,213,213,214,214,215,215,216,216,217,217,218,218,219,219,220,220,221,221,222,222,223,223,224,224,225,225,226,226,227,227,228,228,229,229,230,230,231,231,232,232,233,233,234,234,235,235,236,236,237,237,238,238,239,239,240,240,241,241,242,242,243,243,244,244,245,245,246,246,247,247,248,248,249,249,250,250,251,251,252,252,253,253,254,254,255,255,256,256,257,257,258,258,259,259,260,260,261,261,262,262,263,263,264,264,265,265,266,266,267,267,268,268,269,269,270,270,271,271,272,272,273,273,274,274,275,275,276,276,277,277,278,278,279,279,280,280,281,281,282,282,283,283,284,284,285,285,286,286,287,287,288,288,289,289,290,290,291,291,292,292,293,293,294,294,295,295,296,296,297,297,298,298,299,299,300,300,301,301,302,302,303,303,304,304,305,305,306,306,307,307,308,308,309,309,310,310,311,311,312,312,313,313,314,314,315,315,316,316,317,317,318,318,319,319,320,320,321,321,322,322,323,323,324,324,325,325,326,326,327,327,328,328,329,329,330,330,331,331,332,332,333,333,334,334,335,335,336,336,337,337,338,338,339,339,340,340,341,341,342,342,343,343,344,344,345,345,346,346,347,347,348,348,349,349,350,350,351,351,352,352,353,353,354,354,355,355,356,356,357,357,358,358,359,359,360,360,361,361,362,362,363,363,364,364,365,365,366,366,367,367,368,368,369,369,370,370,371,371,372,372,373,373,374,374,375,375,376,376,377,377,378,378,379,379,380,380,381,381,382,382,383,383,384,384,385,385,386,386,387,387,388,388,389,389,390,390,391,391,392,392,393,393,394,394,395,395,396,396,397,397,398,398,399,399,400,400,401,401,402,402,403,403,404,404,405,405,406,406,407,407,408,408,409,409,410,410,411,411,412,412,413,413,414,414,415,415,416,416,417,417,418,418,419,419,420,420,421,421,422,422,423,423,424,424,425,425,426,426,427,427,428,428,429,429,430,430,431,431,432,432,433,433,434,434,435,435,436,436,437,437,438,438,439,439,440,440,441,441,442,442,443,443,444,444,445,445,446,446,447,447,448,448,449,449,450,450,451,451,452,452,453,453,454,454,455,455,456,456,457,457,458,458,459,459,460,460,461,461,462,462,463,463,464,464,465,465,466,466,467,467,468,468,469,469,470,470,471,471,472,472,473,473,474,474,475,475,476,476,477,477,478,478,479,479,480,480,481,481,482,482,483,483,484,484,485,485,486,486,487,487,488,488,489,489,490,490,491,491,492,492,493,493,494,494,495,495,496,496,497,497,498,498,499,499,500,500,501,501,502,502,503,503,504,504,505,505,506,506,507,507,508,508,509,509,510,510,511,511
v54s: .byte 120,32,121
v54r: .byte 32
v54p: .quad 1,1,3,3
v54a: .quad 0,0,1,1
v55s: .byte 32,32,120,10,32,32,121
v55r: .byte 120,10,121
v55p: .quad 2,2,6,6
v55a: .quad 0,0,2,2
v56s: .byte 120,32,121
v56r: .byte 32
v56p: .quad 1,1,3,3
v56a: .quad 0,0,1,1
v57s: .byte 120,32,121
v57r: .byte 32
v57p: .quad 1,1,3,3
v57a: .quad 0,0,1,1
v58s: .byte 120,32,121
v58r: .byte 32
v58p: .quad 1,1,3,3
v58a: .quad 0,0,1,1
v59s: .byte 206,178,32,120
v59r: .byte 206,178,32
v59p: .quad 0,0,4,4
v59a: .quad 0,0,3,3
v60s: .byte 120,32,121
v60r: .byte 120,121
v60p: .quad 1,1,3,3
v60a: .quad 1,1,2,2
v61s: .byte 120,32,121
v61r: .byte 32
v61p: .quad 1,1,3,3
v61a: .quad 0,0,1,1
v62s: .byte 120,32,121
v62r: .byte 32
v62p: .quad 1,1,3,3
v62a: .quad 0,0,1,1
v63s: .byte 97,98,99,32,100,101,102
v63r: .byte 97,98,32,100,101
v63p: .quad 3,3,7,7
v63a: .quad 2,2,5,5
v64s: .byte 120,32,121
v64r: .byte 32
v64p: .quad 1,1,3,3
v64a: .quad 0,0,1,1
