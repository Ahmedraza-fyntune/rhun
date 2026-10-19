.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
options: .zero PPO_SIZE
cached_input: .quad 0
cached_len: .quad 0
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
    lea r12, [rip + paste_vectors]
    mov r13d, 1
.Lvector:
    cmp qword ptr [r12], 0
    je .Ldone
    mov r15, [rip + g_mem_live]
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
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 8]
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    # The exact raw selections are restored before the planner observes a live snippet and redo.
    mov rdi, rbx
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov rdi, rax
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 24], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp], rax
    mov rdi, rbx
    call doc_selections_snapshot
    mov [rsp + 8], rax
    mov rax, [r12 + 48]
    mov [rip + options + PPO_mode], rax
    mov rax, [r12 + 56]
    mov [rip + options + PPO_line], rax
    mov rax, [r12 + 64]
    mov [rip + options + PPO_metadata], rax
    mov rax, [r12 + 72]
    mov [rip + options + PPO_limit], rax
    mov rdi, rbx
    mov rsi, [r12 + 32]
    mov rdx, [r12 + 40]
    lea rcx, [rip + options]
    call editor_paste_plan_new
    mov r14, rax
    cmp rdx, [r12 + 80]
    jne failed
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
    mov rdx, [r12 + 24]
    dec rdx
    shl rdx, 4
    test rdx, rdx
    jz 1f
    add rdx, DMS_DATA
    mov rdi, [rbx + DOC_selections]
    mov rsi, [rsp + 8]
    call memeq
    test eax, eax
    jz failed
1:  cmp qword ptr [r12 + 80], 0
    je .Lsuccess
    test r14, r14
    jnz failed
    jmp .Lfree
.Lsuccess:
    test r14, r14
    jz failed
    mov rax, [r12 + 120]
    cmp rax, [r14 + EPP_noop]
    jne failed
    test rax, rax
    jnz .Lfree
    cmp qword ptr [r12 + 64], 0
    jne .Lapply_prepared
    cmp qword ptr [r12 + 56], 0
    jne .Lapply_prepared
    cmp qword ptr [r12 + 72], DOC_MULTI_BYTES_MAX
    jne .Lapply_prepared
    mov rdi, rbx
    mov rsi, [r12 + 32]
    mov rdx, [r12 + 40]
    mov rcx, [r12 + 48]
    call editor_multi_paste
    jmp .Lapplied
.Lapply_prepared:
    mov rdi, rbx
    lea rsi, [r14 + EPP_edits]
    mov rdx, [r14 + EPP_nedits]
    lea rcx, [r14 + EPP_pairs]
    mov r8, [r14 + EPP_npairs]
    call doc_selections_apply
.Lapplied:
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 88]
    mov rdx, [r12 + 96]
    mov rcx, [r12 + 104]
    mov r8, [r12 + 112]
    call check
    test eax, eax
    jz failed
    cmp qword ptr [r14 + EPP_nedits], 0
    je .Lfree
    mov qword ptr [rsp + 16], 3
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
    mov rsi, [r12 + 88]
    mov rdx, [r12 + 96]
    mov rcx, [r12 + 104]
    mov r8, [r12 + 112]
    call check
    test eax, eax
    jz failed
    dec qword ptr [rsp + 16]
    jnz .Lreplay
.Lfree:
    mov rdi, r14
    call editor_paste_plan_free
    mov rdi, [rsp]
    call mem_free
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, [rsp + 24]
    call mem_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 128
    inc r13
    jmp .Lvector
.Ldone:
    call integration
    test eax, eax
    jnz .Lmain_return
    lea rdi, [rip + success]
    call log_cstr
    xor eax, eax
.Lmain_return:
    EPILOGUE
failed:
    lea rdi, [rip + failure]
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
# The platform stub retains the owned cache pointer only until another successful write.
capture_clip:
    mov [rip + cached_input], rdi
    mov [rip + cached_len], rsi
    mov eax, 1
    ret
make_destination:
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + destination]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + destination_pairs]
    mov edx, 2
    call doc_selections_set
    mov rax, rbx
    EPILOGUE

integration:
    PROLOGUE 112
    mov r13d, 100
    mov rax, [rip + g_plat + P_clip_set]
    mov [rsp], rax
    lea rax, [rip + capture_clip]
    mov [rip + g_plat + P_clip_set], rax
    mov eax, [rip + cfg_multi_cursor_paste]
    mov [rsp + 24], rax
    mov dword ptr [rip + cfg_multi_cursor_paste], 1
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + copied_source]
    mov ecx, 7
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + copied_pairs]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne failed
    mov rdi, rbx
    call doc_free               # clipboard text/segments must outlive the source document
    call make_destination
    mov rbx, rax
    mov rdi, [rip + cached_input]
    mov rsi, [rip + cached_len]
    call ed_paste              # matching multi-line segments override the full-text setting
    mov rdi, rbx
    lea rsi, [rip + copied_source]
    mov edx, 7
    lea rcx, [rip + copied_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov r14d, 3
.Lroundtrip:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + destination]
    mov edx, 5
    lea rcx, [rip + destination_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    dec r14
    jnz .Lroundtrip
    # Empty direct and editor-entry pastes preserve every DOC/SN byte.
    mov r13d, 101
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov rdi, rax
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 40], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 32], rax
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call editor_multi_paste
    cmp eax, 1
    jne failed
    xor edi, edi
    xor esi, esi
    call ed_paste
    mov rdi, rbx
    mov rsi, [rsp + 32]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 40]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 32]
    call mem_free
    mov rdi, [rsp + 40]
    call mem_free
    mov rdi, rbx
    call doc_free
    # Restored old bytes cannot revive the segment metadata invalidated by empty delivery.
    mov r13d, 102
    call make_destination
    mov rbx, rax
    mov rdi, [rip + cached_input]
    mov rsi, [rip + cached_len]
    call ed_paste
    mov rdi, rbx
    lea rsi, [rip + restored_full]
    mov edx, 15
    lea rcx, [rip + restored_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    # A cached whole-line copy is inserted only once when both cursors share the line.
    mov r13d, 103
    lea rdi, [rip + whole_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne failed
    call make_destination
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + line_cursors]
    mov edx, 2
    call doc_selections_set
    mov rdi, [rip + cached_input]
    mov rsi, [rip + cached_len]
    call ed_paste
    mov rdi, rbx
    lea rsi, [rip + line_result]
    mov edx, 7
    lea rcx, [rip + line_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    # Direct action rejects invalid state without changing a live snippet or redo branch.
    call make_destination
    mov rbx, rax
    mov rdi, rax
    mov esi, 5
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov rdi, rax
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 40], rax
    xor r14d, r14d
.Laction_error:
    mov r13d, 110
    add r13d, r14d
    mov qword ptr [rsp + 64], 1
    cmp r14d, 0
    jne 1f
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov qword ptr [rsp + 64], 3
1:  cmp r14d, 1
    jne 2f
    mov qword ptr [rbx + DOC_selectionbatch], 1
    mov qword ptr [rsp + 64], 4
2:  cmp r14d, 5
    jne 3f
    mov qword ptr [rip + g_doc], 0
3:  mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 32], rax
    mov rdi, rbx
    lea rsi, [rip + letter]
    mov edx, 1
    xor ecx, ecx
    cmp r14d, 2
    jne 4f
    mov ecx, 2
4:  cmp r14d, 3
    jne 5f
    xor esi, esi
5:  cmp r14d, 4
    jne 6f
    mov edx, DOC_MULTI_BYTES_MAX + 1
    mov qword ptr [rsp + 64], 2
6:  call editor_multi_paste
    test eax, eax
    jnz failed
    cmp rdx, [rsp + 64]
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 32]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 40]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 32]
    call mem_free
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 0
    mov [rip + g_doc], rbx
    inc r14d
    cmp r14d, 6
    jb .Laction_error
    mov rdi, [rsp + 40]
    call mem_free
    mov rdi, rbx
    call doc_free
    # DOC-buffer alias plus an outer group that continues after Paste.
    mov r13d, 120
    call make_destination
    mov rbx, rax
    mov rdi, rax
    call doc_contiguous
    mov rsi, rax
    mov rdi, rbx
    mov edx, 2
    mov ecx, 1
    call editor_multi_paste
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + alias_result]
    mov edx, 5
    lea rcx, [rip + destination_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_free
    call make_destination
    mov rbx, rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 56], rax
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    lea rsi, [rip + letter_z]
    mov edx, 1
    mov ecx, 1
    call editor_multi_paste
    cmp eax, 1
    jne failed
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    mov esi, 3
    lea rdx, [rip + bang]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + group_outputs]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    mov rsi, [rsp + 56]
    call doc_selections_record_after
    mov rdi, rbx
    call doc_end_group
    mov r14d, 3
.Lgroup_replay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + destination]
    mov edx, 5
    lea rcx, [rip + destination_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + group_result]
    mov edx, 4
    lea rcx, [rip + group_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    dec r14
    jnz .Lgroup_replay
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    # Input, metadata, and options may all be freed immediately after pure preparation.
    mov r13d, 125
    call make_destination
    mov rbx, rax
    mov edi, ECM_SIZE + 64
    call mem_alloc
    mov [rsp + 48], rax
    mov rdi, rax
    lea rsi, [rip + external_text]
    mov edx, 8
    call memcpy
    mov rax, [rsp + 48]
    mov qword ptr [rax + 16 + ECM_count], 2
    mov qword ptr [rax + 16 + ECM_total], 8
    mov qword ptr [rax + 16 + ECM_segments + ECS_offset], 0
    mov qword ptr [rax + 16 + ECM_segments + ECS_len], 4
    mov qword ptr [rax + 16 + ECM_segments + ECS_SIZE + ECS_offset], 5
    mov qword ptr [rax + 16 + ECM_segments + ECS_SIZE + ECS_len], 3
    lea rcx, [rax + 16 + ECM_SIZE]
    mov qword ptr [rcx + PPO_mode], 1
    lea rdx, [rax + 16]
    mov [rcx + PPO_metadata], rdx
    mov qword ptr [rcx + PPO_line], 0
    mov qword ptr [rcx + PPO_limit], DOC_MULTI_BYTES_MAX
    mov rdi, rbx
    mov rsi, rax
    mov edx, 8
    call editor_paste_plan_new
    test rax, rax
    jz failed
    mov r14, rax
    mov rdi, [rsp + 48]
    call mem_free
    mov rdi, rbx
    lea rsi, [r14 + EPP_edits]
    mov rdx, [r14 + EPP_nedits]
    lea rcx, [r14 + EPP_pairs]
    mov r8, [r14 + EPP_npairs]
    call doc_selections_apply
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + copied_source]
    mov edx, 7
    lea rcx, [rip + copied_outputs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, r14
    call editor_paste_plan_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov r13d, 131
    call primary_empty_noop
    # The choice parser keeps its old value for unknown input.
    mov r13d, 130
    lea rbx, [rip + g_settings]
    lea r14, [rip + cfg_multi_cursor_paste]
.Lsetting_find:
    cmp qword ptr [rbx + SET_key], 0
    je failed
    cmp r14, [rbx + SET_ptr]
    je .Lsetting_assign
    add rbx, SET_SIZE
    jmp .Lsetting_find
.Lsetting_assign:
    mov rdi, rbx
    lea rsi, [rip + full_value]
    mov edx, 4
    call setting_assign
    cmp dword ptr [rip + cfg_multi_cursor_paste], 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + invalid_value]
    mov edx, 7
    call setting_assign
    cmp dword ptr [rip + cfg_multi_cursor_paste], 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + spread_value]
    mov edx, 6
    call setting_assign
    cmp dword ptr [rip + cfg_multi_cursor_paste], 0
    jne failed
    mov eax, [rsp + 24]
    mov [rip + cfg_multi_cursor_paste], eax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    mov rax, [rsp]
    mov [rip + g_plat + P_clip_set], rax
    xor eax, eax
    EPILOGUE

# A primary-only empty delivery cannot open a snippet transaction or consume a redo branch.
primary_empty_noop:
    PROLOGUE 32
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 0
    mov dword ptr [rip + g_vim_cmdline], 0
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    lea rdi, [rip + letter]
    mov esi, 1
    call snippet_new
    mov r12, rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call snippet_add
    mov rdi, r12
    call snippet_validate
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call snippet_attach
    cmp [rbx + DOC_snippet], r12
    jne failed
    cmp qword ptr [rbx + DOC_selections], 0
    jne failed
    mov rax, [r12 + SN_beginundo]
    cmp rax, [rbx + DOC_undo + VEC_len]
    je failed
    mov rdi, r12
    mov esi, SN_SIZE
    call mem_dup
    mov r14, rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov r15, rax
    mov qword ptr [rsp], 3
.Lprimary_empty_repeat:
    xor edi, edi
    xor esi, esi
    call ed_paste
    call primary_empty_same
    xor edi, edi
    xor esi, esi
    call app_on_paste
    call primary_empty_same
    dec qword ptr [rsp]
    jnz .Lprimary_empty_repeat
    mov rdi, r14
    call mem_free
    mov rdi, r15
    call mem_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    EPILOGUE
primary_empty_same:
    PROLOGUE
    mov rdi, rbx
    mov rsi, r15
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, r12
    mov rsi, r14
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    EPILOGUE
.section .rodata
external_text: .ascii "A\r\nB\nC\rD"
copied_source: .ascii "A\nB C\nD"
copied_pairs: .quad 3,0,7,4
copied_outputs: .quad 3,3,7,7
destination: .ascii "xx yy"
destination_pairs: .quad 2,0,5,3
destination_outputs: .quad 2,2,5,5
restored_full: .ascii "A\nB\nC\nD A\nB\nC\nD"
restored_outputs: .quad 7,7,15,15
whole_line: .ascii "L\n"
line_cursors: .quad 1,1,4,4
line_result: .ascii "L\nxx yy"
line_outputs: .quad 3,3,6,6
alias_result: .ascii "xx xx"
letter_z: .ascii "Z"
bang: .ascii "!"
group_result: .ascii "Z Z!"
group_outputs: .quad 4,4,1,1
full_value: .ascii "FULL"
invalid_value: .ascii "invalid"
spread_value: .ascii "spread"
success: .asciz "ok editor multiple paste\n"
failure: .asciz "failed editor paste case "
letter: .ascii "x"
.section .rodata
.p2align 3
paste_vectors:
    .quad paste_source0,5,paste_before0,2,paste_text0,3,0,0,0,67108864,0,paste_after0,3,paste_outputs0,2,0
    .quad paste_source1,5,paste_before1,2,paste_text1,3,1,0,0,67108864,0,paste_after1,7,paste_outputs1,2,0
    .quad paste_source2,5,paste_before2,2,paste_text2,3,0,0,0,67108864,0,paste_after2,3,paste_outputs2,2,0
    .quad paste_source3,5,paste_before3,2,paste_text3,7,0,0,0,67108864,0,paste_after3,7,paste_outputs3,2,0
    .quad paste_source4,5,paste_before4,2,paste_text4,7,1,0,paste_meta4,67108864,0,paste_after4,7,paste_outputs4,2,0
    .quad paste_source5,5,paste_before5,2,paste_text5,3,0,0,paste_meta5,67108864,0,paste_after5,3,paste_outputs5,2,0
    .quad paste_source6,5,paste_before6,2,paste_text6,6,0,0,0,67108864,0,paste_after6,3,paste_outputs6,2,0
    .quad paste_source7,5,paste_before7,2,paste_text7,6,1,0,0,67108864,0,paste_after7,9,paste_outputs7,2,0
    .quad paste_source8,5,paste_before8,2,paste_text8,4,0,0,0,67108864,0,paste_after8,3,paste_outputs8,2,0
    .quad paste_source9,5,paste_before9,2,paste_text9,4,1,0,0,67108864,0,paste_after9,9,paste_outputs9,2,0
    .quad paste_source10,5,paste_before10,2,paste_text10,2,0,0,0,67108864,0,paste_after10,1,paste_outputs10,2,0
    .quad paste_source11,4,paste_before11,2,paste_text11,2,0,0,0,67108864,0,paste_after11,0,paste_outputs11,1,0
    .quad paste_source12,5,paste_before12,2,paste_text12,0,0,0,0,67108864,0,paste_after12,5,paste_outputs12,2,1
    .quad paste_source13,6,paste_before13,2,paste_text13,3,0,0,0,67108864,0,paste_after13,4,paste_outputs13,1,0
    .quad paste_source14,5,paste_before14,2,paste_text14,3,0,0,0,67108864,0,paste_after14,6,paste_outputs14,1,0
    .quad paste_source15,5,paste_before15,2,paste_text15,3,0,0,0,67108864,0,paste_after15,7,paste_outputs15,2,0
    .quad paste_source16,5,paste_before16,2,paste_text16,2,0,1,0,67108864,0,paste_after16,9,paste_outputs16,2,0
    .quad paste_source17,3,paste_before17,2,paste_text17,2,0,1,0,67108864,0,paste_after17,5,paste_outputs17,2,0
    .quad paste_source18,5,paste_before18,2,paste_text18,2,0,1,0,67108864,0,paste_after18,9,paste_outputs18,2,0
    .quad paste_source19,5,paste_before19,2,paste_text19,2,0,1,0,67108864,0,paste_after19,9,paste_outputs19,2,0
    .quad paste_source20,5,paste_before20,2,paste_text20,4,0,1,0,67108864,0,paste_after20,13,paste_outputs20,2,0
    .quad paste_source21,5,paste_before21,2,paste_text21,2,0,1,0,67108864,0,paste_after21,7,paste_outputs21,2,0
    .quad paste_source22,5,paste_before22,2,paste_text22,4,0,1,0,67108864,0,paste_after22,5,paste_outputs22,2,0
    .quad paste_source23,3,paste_before23,2,paste_text23,2,0,1,0,67108864,0,paste_after23,7,paste_outputs23,2,0
    .quad paste_source24,0,paste_before24,2,paste_text24,2,0,1,0,67108864,0,paste_after24,2,paste_outputs24,1,0
    .quad paste_source25,5,paste_before25,2,paste_text25,3,1,0,0,6,0,paste_after25,7,paste_outputs25,2,0
    .quad paste_source26,5,paste_before26,2,paste_text26,3,1,0,0,5,2,paste_after26,5,paste_outputs26,2,0
    .quad paste_source27,5,paste_before27,2,paste_text27,6,1,0,0,8,0,paste_after27,9,paste_outputs27,2,0
    .quad paste_source28,5,paste_before28,2,paste_text28,6,1,0,0,7,2,paste_after28,5,paste_outputs28,2,0
    .quad paste_source29,3,paste_before29,2,paste_text29,2,0,1,0,2,0,paste_after29,5,paste_outputs29,2,0
    .quad paste_source30,5,paste_before30,2,paste_text30,3,0,0,paste_meta30,67108864,1,paste_after30,5,paste_outputs30,2,0
    .quad paste_source31,5,paste_before31,2,paste_text31,3,0,0,paste_meta31,67108864,1,paste_after31,5,paste_outputs31,2,0
    .quad paste_source32,5,paste_before32,2,paste_text32,3,0,0,paste_meta32,67108864,1,paste_after32,5,paste_outputs32,2,0
    .quad paste_source33,5,paste_before33,2,paste_text33,3,0,0,paste_meta33,67108864,1,paste_after33,5,paste_outputs33,2,0
    .quad paste_source34,5,paste_before34,2,paste_text34,3,0,0,paste_meta34,67108864,1,paste_after34,5,paste_outputs34,2,0
    .quad paste_source35,5,paste_before35,2,paste_text35,3,0,0,paste_meta35,67108864,1,paste_after35,5,paste_outputs35,2,0
    .quad paste_source36,5,paste_before36,2,paste_text36,5,0,0,paste_meta36,67108864,1,paste_after36,5,paste_outputs36,2,0
    .quad paste_source37,5,paste_before37,2,paste_text37,1,2,0,0,67108864,1,paste_after37,5,paste_outputs37,2,0
    .quad paste_source38,5,paste_before38,2,paste_text38,1,0,2,0,67108864,1,paste_after38,5,paste_outputs38,2,0
    .quad paste_source39,5,paste_before39,2,paste_text39,1,0,0,0,67108865,2,paste_after39,5,paste_outputs39,2,0
    .quad paste_source40,5,paste_before40,2,paste_text40,1,0,0,0,67108864,1,paste_after40,5,paste_outputs40,2,0
    .quad paste_source41,1024,paste_before41,512,paste_text41,1023,0,0,0,67108864,0,paste_after41,1024,paste_outputs41,512,0
    .quad paste_source42,5,paste_before42,2,paste_text42,3,0,0,paste_meta42,67108864,1,paste_after42,5,paste_outputs42,2,0
    .quad paste_source43,3,paste_before43,2,paste_text43,1,1,0,0,67108864,0,paste_after43,5,paste_outputs43,2,0
    .quad paste_source44,5,paste_before44,2,paste_text44,3,1,0,0,67108864,0,paste_after44,7,paste_outputs44,2,0
    .quad 0
paste_source0: .byte 97,98,32,99,100,0
paste_text0: .byte 88,10,89,0
paste_after0: .byte 88,32,89,0
paste_before0: .quad 2,0,5,3
paste_outputs0: .quad 1,1,3,3
paste_source1: .byte 97,98,32,99,100,0
paste_text1: .byte 88,10,89,0
paste_after1: .byte 88,10,89,32,88,10,89,0
paste_before1: .quad 2,0,5,3
paste_outputs1: .quad 3,3,7,7
paste_source2: .byte 97,98,32,99,100,0
paste_text2: .byte 88,10,89,0
paste_after2: .byte 88,32,89,0
paste_before2: .quad 5,3,2,0
paste_outputs2: .quad 3,3,1,1
paste_source3: .byte 195,169,32,206,169,0
paste_text3: .byte 240,159,152,128,10,206,178,0
paste_after3: .byte 240,159,152,128,32,206,178,0
paste_before3: .quad 2,0,5,3
paste_outputs3: .quad 4,4,7,7
paste_source4: .byte 120,120,32,121,121,0
paste_text4: .byte 97,10,98,10,99,10,100,0
paste_after4: .byte 97,10,98,32,99,10,100,0
paste_before4: .quad 2,0,5,3
paste_outputs4: .quad 3,3,7,7
paste_meta4: .quad 2,7 ,0,3,4,3
paste_source5: .byte 97,98,32,99,100,0
paste_text5: .byte 88,10,89,0
paste_after5: .byte 88,32,89,0
paste_before5: .quad 2,0,5,3
paste_outputs5: .quad 1,1,3,3
paste_meta5: .quad 1,3 ,0,3
paste_source6: .byte 97,98,32,99,100,0
paste_text6: .byte 88,13,10,89,13,10,0
paste_after6: .byte 88,32,89,0
paste_before6: .quad 2,0,5,3
paste_outputs6: .quad 1,1,3,3
paste_source7: .byte 97,98,32,99,100,0
paste_text7: .byte 88,13,10,89,13,10,0
paste_after7: .byte 88,10,89,10,32,88,10,89,10,0
paste_before7: .quad 2,0,5,3
paste_outputs7: .quad 4,4,9,9
paste_source8: .byte 97,98,32,99,100,0
paste_text8: .byte 88,13,89,13,0
paste_after8: .byte 88,32,89,0
paste_before8: .quad 2,0,5,3
paste_outputs8: .quad 1,1,3,3
paste_source9: .byte 97,98,32,99,100,0
paste_text9: .byte 88,13,89,13,0
paste_after9: .byte 88,10,89,10,32,88,10,89,10,0
paste_before9: .quad 2,0,5,3
paste_outputs9: .quad 4,4,9,9
paste_source10: .byte 97,98,32,99,100,0
paste_text10: .byte 10,10,0
paste_after10: .byte 32,0
paste_before10: .quad 2,0,5,3
paste_outputs10: .quad 0,0,1,1
paste_source11: .byte 97,98,99,100,0
paste_text11: .byte 10,10,0
paste_after11: .byte 0
paste_before11: .quad 2,0,4,2
paste_outputs11: .quad 0,0
paste_source12: .byte 97,98,32,99,100,0
paste_text12: .byte 0
paste_after12: .byte 97,98,32,99,100,0
paste_before12: .quad 2,0,5,3
paste_outputs12: .quad 2,0,5,3
paste_source13: .byte 97,98,99,100,101,102,0
paste_text13: .byte 88,10,89,0
paste_after13: .byte 88,10,89,102,0
paste_before13: .quad 3,0,5,2
paste_outputs13: .quad 3,3
paste_source14: .byte 97,98,32,99,100,0
paste_text14: .byte 88,10,89,0
paste_after14: .byte 88,10,89,32,99,100,0
paste_before14: .quad 2,0,2,0
paste_outputs14: .quad 3,3
paste_source15: .byte 97,98,32,99,100,0
paste_text15: .byte 88,10,89,0
paste_after15: .byte 97,88,98,32,99,89,100,0
paste_before15: .quad 1,1,4,4
paste_outputs15: .quad 2,2,6,6
paste_source16: .byte 97,98,10,99,100,0
paste_text16: .byte 76,10,0
paste_after16: .byte 76,10,97,98,10,76,10,99,100,0
paste_before16: .quad 1,1,4,4
paste_outputs16: .quad 3,3,8,8
paste_source17: .byte 97,98,99,0
paste_text17: .byte 76,10,0
paste_after17: .byte 76,10,97,98,99,0
paste_before17: .quad 1,1,2,2
paste_outputs17: .quad 3,3,4,4
paste_source18: .byte 97,98,10,99,100,0
paste_text18: .byte 76,10,0
paste_after18: .byte 76,10,97,98,10,76,10,99,100,0
paste_before18: .quad 0,0,3,3
paste_outputs18: .quad 2,2,7,7
paste_source19: .byte 9,195,169,10,120,0
paste_text19: .byte 76,10,0
paste_after19: .byte 76,10,9,195,169,10,76,10,120,0
paste_before19: .quad 1,1,4,4
paste_outputs19: .quad 3,3,8,8
paste_source20: .byte 97,98,10,99,100,0
paste_text20: .byte 65,10,66,10,0
paste_after20: .byte 65,10,66,10,97,98,10,65,10,66,10,99,100,0
paste_before20: .quad 1,1,4,4
paste_outputs20: .quad 5,5,12,12
paste_source21: .byte 97,98,32,99,100,0
paste_text21: .byte 76,10,0
paste_after21: .byte 76,10,32,99,76,10,100,0
paste_before21: .quad 2,0,4,4
paste_outputs21: .quad 2,2,6,6
paste_source22: .byte 97,98,32,99,100,0
paste_text22: .byte 88,10,89,10,0
paste_after22: .byte 88,32,99,89,100,0
paste_before22: .quad 2,0,4,4
paste_outputs22: .quad 1,1,4,4
paste_source23: .byte 97,98,10,0
paste_text23: .byte 76,10,0
paste_after23: .byte 76,10,97,98,10,76,10,0
paste_before23: .quad 1,1,3,3
paste_outputs23: .quad 3,3,7,7
paste_source24: .byte 0
paste_text24: .byte 76,10,0
paste_after24: .byte 76,10,0
paste_before24: .quad 0,0,0,0
paste_outputs24: .quad 2,2
paste_source25: .byte 97,98,32,99,100,0
paste_text25: .byte 88,10,89,0
paste_after25: .byte 88,10,89,32,88,10,89,0
paste_before25: .quad 2,0,5,3
paste_outputs25: .quad 3,3,7,7
paste_source26: .byte 97,98,32,99,100,0
paste_text26: .byte 88,10,89,0
paste_after26: .byte 97,98,32,99,100,0
paste_before26: .quad 2,0,5,3
paste_outputs26: .quad 2,0,5,3
paste_source27: .byte 97,98,32,99,100,0
paste_text27: .byte 88,13,10,89,13,10,0
paste_after27: .byte 88,10,89,10,32,88,10,89,10,0
paste_before27: .quad 2,0,5,3
paste_outputs27: .quad 4,4,9,9
paste_source28: .byte 97,98,32,99,100,0
paste_text28: .byte 88,13,10,89,13,10,0
paste_after28: .byte 97,98,32,99,100,0
paste_before28: .quad 2,0,5,3
paste_outputs28: .quad 2,0,5,3
paste_source29: .byte 97,98,99,0
paste_text29: .byte 76,10,0
paste_after29: .byte 76,10,97,98,99,0
paste_before29: .quad 1,1,2,2
paste_outputs29: .quad 3,3,4,4
paste_source30: .byte 97,98,32,99,100,0
paste_text30: .byte 88,10,89,0
paste_after30: .byte 97,98,32,99,100,0
paste_before30: .quad 2,0,5,3
paste_outputs30: .quad 2,0,5,3
paste_meta30: .quad 0,3
paste_source31: .byte 97,98,32,99,100,0
paste_text31: .byte 88,10,89,0
paste_after31: .byte 97,98,32,99,100,0
paste_before31: .quad 2,0,5,3
paste_outputs31: .quad 2,0,5,3
paste_meta31: .quad 1,3 ,0,4
paste_source32: .byte 97,98,32,99,100,0
paste_text32: .byte 88,10,89,0
paste_after32: .byte 97,98,32,99,100,0
paste_before32: .quad 2,0,5,3
paste_outputs32: .quad 2,0,5,3
paste_meta32: .quad 2,3 ,3,1,0,1
paste_source33: .byte 97,98,32,99,100,0
paste_text33: .byte 88,10,89,0
paste_after33: .byte 97,98,32,99,100,0
paste_before33: .quad 2,0,5,3
paste_outputs33: .quad 2,0,5,3
paste_meta33: .quad 2,3 ,0,2,1,2
paste_source34: .byte 97,98,32,99,100,0
paste_text34: .byte 88,10,89,0
paste_after34: .byte 97,98,32,99,100,0
paste_before34: .quad 2,0,5,3
paste_outputs34: .quad 2,0,5,3
paste_meta34: .quad 2,3 ,0,2,4,2
paste_source35: .byte 97,98,32,99,100,0
paste_text35: .byte 88,10,89,0
paste_after35: .byte 97,98,32,99,100,0
paste_before35: .quad 2,0,5,3
paste_outputs35: .quad 2,0,5,3
paste_meta35: .quad 2,3 ,0,2,18446744073709551615,1
paste_source36: .byte 97,98,32,99,100,0
paste_text36: .byte 195,169,10,206,169,0
paste_after36: .byte 97,98,32,99,100,0
paste_before36: .quad 2,0,5,3
paste_outputs36: .quad 2,0,5,3
paste_meta36: .quad 2,5 ,1,1,3,2
paste_source37: .byte 97,98,32,99,100,0
paste_text37: .byte 88,0
paste_after37: .byte 97,98,32,99,100,0
paste_before37: .quad 2,0,5,3
paste_outputs37: .quad 2,0,5,3
paste_source38: .byte 97,98,32,99,100,0
paste_text38: .byte 88,0
paste_after38: .byte 97,98,32,99,100,0
paste_before38: .quad 2,0,5,3
paste_outputs38: .quad 2,0,5,3
paste_source39: .byte 97,98,32,99,100,0
paste_text39: .byte 88,0
paste_after39: .byte 97,98,32,99,100,0
paste_before39: .quad 2,0,5,3
paste_outputs39: .quad 2,0,5,3
paste_source40: .byte 97,98,32,99,100,0
paste_text40: .byte 255,0
paste_after40: .byte 97,98,32,99,100,0
paste_before40: .quad 2,0,5,3
paste_outputs40: .quad 2,0,5,3
paste_source41: .byte 120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,0
paste_text41: .byte 122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,10,122,0
paste_after41: .byte 122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,122,32,0
paste_before41: .quad 1023,1022,1021,1020,1019,1018,1017,1016,1015,1014,1013,1012,1011,1010,1009,1008,1007,1006,1005,1004,1003,1002,1001,1000,999,998,997,996,995,994,993,992,991,990,989,988,987,986,985,984,983,982,981,980,979,978,977,976,975,974,973,972,971,970,969,968,967,966,965,964,963,962,961,960,959,958,957,956,955,954,953,952,951,950,949,948,947,946,945,944,943,942,941,940,939,938,937,936,935,934,933,932,931,930,929,928,927,926,925,924,923,922,921,920,919,918,917,916,915,914,913,912,911,910,909,908,907,906,905,904,903,902,901,900,899,898,897,896,895,894,893,892,891,890,889,888,887,886,885,884,883,882,881,880,879,878,877,876,875,874,873,872,871,870,869,868,867,866,865,864,863,862,861,860,859,858,857,856,855,854,853,852,851,850,849,848,847,846,845,844,843,842,841,840,839,838,837,836,835,834,833,832,831,830,829,828,827,826,825,824,823,822,821,820,819,818,817,816,815,814,813,812,811,810,809,808,807,806,805,804,803,802,801,800,799,798,797,796,795,794,793,792,791,790,789,788,787,786,785,784,783,782,781,780,779,778,777,776,775,774,773,772,771,770,769,768,767,766,765,764,763,762,761,760,759,758,757,756,755,754,753,752,751,750,749,748,747,746,745,744,743,742,741,740,739,738,737,736,735,734,733,732,731,730,729,728,727,726,725,724,723,722,721,720,719,718,717,716,715,714,713,712,711,710,709,708,707,706,705,704,703,702,701,700,699,698,697,696,695,694,693,692,691,690,689,688,687,686,685,684,683,682,681,680,679,678,677,676,675,674,673,672,671,670,669,668,667,666,665,664,663,662,661,660,659,658,657,656,655,654,653,652,651,650,649,648,647,646,645,644,643,642,641,640,639,638,637,636,635,634,633,632,631,630,629,628,627,626,625,624,623,622,621,620,619,618,617,616,615,614,613,612,611,610,609,608,607,606,605,604,603,602,601,600,599,598,597,596,595,594,593,592,591,590,589,588,587,586,585,584,583,582,581,580,579,578,577,576,575,574,573,572,571,570,569,568,567,566,565,564,563,562,561,560,559,558,557,556,555,554,553,552,551,550,549,548,547,546,545,544,543,542,541,540,539,538,537,536,535,534,533,532,531,530,529,528,527,526,525,524,523,522,521,520,519,518,517,516,515,514,513,512,511,510,509,508,507,506,505,504,503,502,501,500,499,498,497,496,495,494,493,492,491,490,489,488,487,486,485,484,483,482,481,480,479,478,477,476,475,474,473,472,471,470,469,468,467,466,465,464,463,462,461,460,459,458,457,456,455,454,453,452,451,450,449,448,447,446,445,444,443,442,441,440,439,438,437,436,435,434,433,432,431,430,429,428,427,426,425,424,423,422,421,420,419,418,417,416,415,414,413,412,411,410,409,408,407,406,405,404,403,402,401,400,399,398,397,396,395,394,393,392,391,390,389,388,387,386,385,384,383,382,381,380,379,378,377,376,375,374,373,372,371,370,369,368,367,366,365,364,363,362,361,360,359,358,357,356,355,354,353,352,351,350,349,348,347,346,345,344,343,342,341,340,339,338,337,336,335,334,333,332,331,330,329,328,327,326,325,324,323,322,321,320,319,318,317,316,315,314,313,312,311,310,309,308,307,306,305,304,303,302,301,300,299,298,297,296,295,294,293,292,291,290,289,288,287,286,285,284,283,282,281,280,279,278,277,276,275,274,273,272,271,270,269,268,267,266,265,264,263,262,261,260,259,258,257,256,255,254,253,252,251,250,249,248,247,246,245,244,243,242,241,240,239,238,237,236,235,234,233,232,231,230,229,228,227,226,225,224,223,222,221,220,219,218,217,216,215,214,213,212,211,210,209,208,207,206,205,204,203,202,201,200,199,198,197,196,195,194,193,192,191,190,189,188,187,186,185,184,183,182,181,180,179,178,177,176,175,174,173,172,171,170,169,168,167,166,165,164,163,162,161,160,159,158,157,156,155,154,153,152,151,150,149,148,147,146,145,144,143,142,141,140,139,138,137,136,135,134,133,132,131,130,129,128,127,126,125,124,123,122,121,120,119,118,117,116,115,114,113,112,111,110,109,108,107,106,105,104,103,102,101,100,99,98,97,96,95,94,93,92,91,90,89,88,87,86,85,84,83,82,81,80,79,78,77,76,75,74,73,72,71,70,69,68,67,66,65,64,63,62,61,60,59,58,57,56,55,54,53,52,51,50,49,48,47,46,45,44,43,42,41,40,39,38,37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
paste_outputs41: .quad 1023,1023,1021,1021,1019,1019,1017,1017,1015,1015,1013,1013,1011,1011,1009,1009,1007,1007,1005,1005,1003,1003,1001,1001,999,999,997,997,995,995,993,993,991,991,989,989,987,987,985,985,983,983,981,981,979,979,977,977,975,975,973,973,971,971,969,969,967,967,965,965,963,963,961,961,959,959,957,957,955,955,953,953,951,951,949,949,947,947,945,945,943,943,941,941,939,939,937,937,935,935,933,933,931,931,929,929,927,927,925,925,923,923,921,921,919,919,917,917,915,915,913,913,911,911,909,909,907,907,905,905,903,903,901,901,899,899,897,897,895,895,893,893,891,891,889,889,887,887,885,885,883,883,881,881,879,879,877,877,875,875,873,873,871,871,869,869,867,867,865,865,863,863,861,861,859,859,857,857,855,855,853,853,851,851,849,849,847,847,845,845,843,843,841,841,839,839,837,837,835,835,833,833,831,831,829,829,827,827,825,825,823,823,821,821,819,819,817,817,815,815,813,813,811,811,809,809,807,807,805,805,803,803,801,801,799,799,797,797,795,795,793,793,791,791,789,789,787,787,785,785,783,783,781,781,779,779,777,777,775,775,773,773,771,771,769,769,767,767,765,765,763,763,761,761,759,759,757,757,755,755,753,753,751,751,749,749,747,747,745,745,743,743,741,741,739,739,737,737,735,735,733,733,731,731,729,729,727,727,725,725,723,723,721,721,719,719,717,717,715,715,713,713,711,711,709,709,707,707,705,705,703,703,701,701,699,699,697,697,695,695,693,693,691,691,689,689,687,687,685,685,683,683,681,681,679,679,677,677,675,675,673,673,671,671,669,669,667,667,665,665,663,663,661,661,659,659,657,657,655,655,653,653,651,651,649,649,647,647,645,645,643,643,641,641,639,639,637,637,635,635,633,633,631,631,629,629,627,627,625,625,623,623,621,621,619,619,617,617,615,615,613,613,611,611,609,609,607,607,605,605,603,603,601,601,599,599,597,597,595,595,593,593,591,591,589,589,587,587,585,585,583,583,581,581,579,579,577,577,575,575,573,573,571,571,569,569,567,567,565,565,563,563,561,561,559,559,557,557,555,555,553,553,551,551,549,549,547,547,545,545,543,543,541,541,539,539,537,537,535,535,533,533,531,531,529,529,527,527,525,525,523,523,521,521,519,519,517,517,515,515,513,513,511,511,509,509,507,507,505,505,503,503,501,501,499,499,497,497,495,495,493,493,491,491,489,489,487,487,485,485,483,483,481,481,479,479,477,477,475,475,473,473,471,471,469,469,467,467,465,465,463,463,461,461,459,459,457,457,455,455,453,453,451,451,449,449,447,447,445,445,443,443,441,441,439,439,437,437,435,435,433,433,431,431,429,429,427,427,425,425,423,423,421,421,419,419,417,417,415,415,413,413,411,411,409,409,407,407,405,405,403,403,401,401,399,399,397,397,395,395,393,393,391,391,389,389,387,387,385,385,383,383,381,381,379,379,377,377,375,375,373,373,371,371,369,369,367,367,365,365,363,363,361,361,359,359,357,357,355,355,353,353,351,351,349,349,347,347,345,345,343,343,341,341,339,339,337,337,335,335,333,333,331,331,329,329,327,327,325,325,323,323,321,321,319,319,317,317,315,315,313,313,311,311,309,309,307,307,305,305,303,303,301,301,299,299,297,297,295,295,293,293,291,291,289,289,287,287,285,285,283,283,281,281,279,279,277,277,275,275,273,273,271,271,269,269,267,267,265,265,263,263,261,261,259,259,257,257,255,255,253,253,251,251,249,249,247,247,245,245,243,243,241,241,239,239,237,237,235,235,233,233,231,231,229,229,227,227,225,225,223,223,221,221,219,219,217,217,215,215,213,213,211,211,209,209,207,207,205,205,203,203,201,201,199,199,197,197,195,195,193,193,191,191,189,189,187,187,185,185,183,183,181,181,179,179,177,177,175,175,173,173,171,171,169,169,167,167,165,165,163,163,161,161,159,159,157,157,155,155,153,153,151,151,149,149,147,147,145,145,143,143,141,141,139,139,137,137,135,135,133,133,131,131,129,129,127,127,125,125,123,123,121,121,119,119,117,117,115,115,113,113,111,111,109,109,107,107,105,105,103,103,101,101,99,99,97,97,95,95,93,93,91,91,89,89,87,87,85,85,83,83,81,81,79,79,77,77,75,75,73,73,71,71,69,69,67,67,65,65,63,63,61,61,59,59,57,57,55,55,53,53,51,51,49,49,47,47,45,45,43,43,41,41,39,39,37,37,35,35,33,33,31,31,29,29,27,27,25,25,23,23,21,21,19,19,17,17,15,15,13,13,11,11,9,9,7,7,5,5,3,3,1,1
paste_source42: .byte 97,98,32,99,100,0
paste_text42: .byte 88,10,89,0
paste_after42: .byte 97,98,32,99,100,0
paste_before42: .quad 2,0,5,3
paste_outputs42: .quad 2,0,5,3
paste_meta42: .quad 513,3 ,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
paste_source43: .byte 97,32,98,0
paste_text43: .byte 40,0
paste_after43: .byte 97,40,32,98,40,0
paste_before43: .quad 1,1,3,3
paste_outputs43: .quad 2,2,5,5
paste_source44: .byte 97,98,32,99,100,0
paste_text44: .byte 88,0,89,0
paste_after44: .byte 88,0,89,32,88,0,89,0
paste_before44: .quad 2,0,5,3
paste_outputs44: .quad 3,3,7,7
