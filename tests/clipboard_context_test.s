.include "rhun.inc"
.section .rodata
cc_text: .ascii "abcdef"
cc_ok: .ascii "ok clipboard destination snapshots\n"
.bss
.p2align 3
cc_stage: .quad 0
cc_live: .quad 0
cc_doc: .quad 0
cc_snapshot: .quad 0
cc_sn: .quad 0
cc_sn_snapshot: .quad 0
cc_field: .quad 0
cc_a: .zero CPX_SIZE
cc_b: .zero CPX_SIZE
cc_pairs: .zero 16 * 512
.text
cc_fail:
    mov edi, [rip + cc_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  call sys_exit
cc_same:
    PROLOGUE
    mov rdi, [rip + cc_doc]
    mov rsi, [rip + cc_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz cc_fail
    mov rdi, [rip + cc_sn]
    mov rsi, [rip + cc_sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz cc_fail
    EPILOGUE
cc_match:
    sub rsp, 8
    lea rdi, [rip + cc_a]
    call clip_context_matches
    cmp eax, 1
    jne cc_fail
    add rsp, 8
    ret
cc_stale:
    sub rsp, 8
    lea rdi, [rip + cc_a]
    call clip_context_matches
    test eax, eax
    jnz cc_fail
    add rsp, 8
    ret
cc_capture:
    sub rsp, 8
    lea rdi, [rip + cc_a]
    call clip_context_capture
    cmp eax, 1
    jne cc_fail
    add rsp, 8
    ret
cc_clear:
    sub rsp, 8
    lea rdi, [rip + cc_a]
    call clip_context_clear
    lea rdi, [rip + cc_b]
    call clip_context_clear
    add rsp, 8
    ret

FN main
    PROLOGUE 16
    mov qword ptr [rip + cc_stage], 1
    mov rax, [rip + g_mem_live]
    mov [rip + cc_live], rax
    call doc_new
    mov [rip + cc_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + cc_text]
    mov ecx, 6
    xor r8d, r8d
    call doc_insert
    lea rdi, [rip + cc_text]
    mov esi, 6
    call snippet_new
    mov [rip + cc_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 6
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + cc_sn]
    call snippet_validate
    cmp eax, 1
    jne cc_fail
    mov rdi, [rip + cc_doc]
    mov rsi, [rip + cc_sn]
    xor edx, edx
    call snippet_attach
    xor ecx, ecx
    lea rdx, [rip + cc_pairs]
1:  mov qword ptr [rdx], 3
    mov qword ptr [rdx + 8], 1
    add rdx, 16
    inc ecx
    cmp ecx, 512
    jb 1b
    mov rdi, [rip + cc_doc]
    lea rsi, [rip + cc_pairs]
    mov edx, 512
    call doc_selections_set
    cmp eax, 1
    jne cc_fail
    mov rdi, [rip + cc_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + cc_snapshot], rax
    mov rdi, [rip + cc_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + cc_sn_snapshot], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call cc_capture
    call cc_match
    call cc_same
    lea rdi, [rip + cc_b]
    lea rsi, [rip + cc_a]
    call clip_context_clone
    mov rax, [rip + cc_a + CPX_extras]
    cmp rax, [rip + cc_b + CPX_extras]
    je cc_fail
    lea rdi, [rip + cc_a]
    lea rsi, [rip + cc_b]
    call clip_context_equal
    cmp eax, 1
    jne cc_fail

    # A different current target or mutation cannot match the old owned snapshot.
    inc qword ptr [rip + cc_stage]
    mov rbx, [rip + cc_doc]
    inc qword ptr [rbx + DOC_id]
    call cc_stale
    dec qword ptr [rbx + DOC_id]
    inc qword ptr [rbx + DOC_version]
    call cc_stale
    dec qword ptr [rbx + DOC_version]
    inc qword ptr [rbx + DOC_cur]
    call cc_stale
    dec qword ptr [rbx + DOC_cur]
    inc qword ptr [rbx + DOC_anchor]
    call cc_stale
    dec qword ptr [rbx + DOC_anchor]
    or dword ptr [rbx + DOC_flags], DF_READONLY
    call cc_stale
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 1
    call cc_stale
    mov qword ptr [rbx + DOC_selectionbatch], 0
    mov rax, [rbx + DOC_selections]
    mov [rsp], rax
    inc qword ptr [rax + DMS_DATA]
    call cc_stale
    mov rax, [rsp]
    dec qword ptr [rax + DMS_DATA]
    dec qword ptr [rax + DMS_count]
    call cc_stale
    mov rax, [rsp]
    inc qword ptr [rax + DMS_count]
    xor dword ptr [rip + cfg_vim], 1
    call cc_stale
    xor dword ptr [rip + cfg_vim], 1
    inc dword ptr [rip + g_vim_mode]
    call cc_stale
    dec dword ptr [rip + g_vim_mode]
    mov dword ptr [rip + g_focus], FOCUS_TERMINAL
    call cc_stale
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call cc_match
    call cc_same
    call cc_clear

    # Real focused Find field: content, owner, caret and lifecycle changes reject.
    inc qword ptr [rip + cc_stage]
    mov dword ptr [rip + g_focus], FOCUS_FIND
    call find_field
    mov [rip + cc_field], rax
    mov rdi, rax
    lea rsi, [rip + cc_text]
    mov edx, 6
    call tf_set
    call cc_capture
    call cc_match
    mov rbx, [rip + cc_field]
    inc qword ptr [rbx + TF_cur]
    call cc_stale
    dec qword ptr [rbx + TF_cur]
    inc dword ptr [rbx + TF_id]
    call cc_stale
    dec dword ptr [rbx + TF_id]
    mov rax, [rip + cc_doc]
    inc qword ptr [rax + DOC_id]
    call cc_stale
    mov rax, [rip + cc_doc]
    dec qword ptr [rax + DOC_id]
    call cc_match
    mov rdi, rbx
    call tf_revision_touch
    call cc_stale
    call cc_clear
    call cc_capture
    mov rdi, rbx
    lea rsi, [rip + cc_text]
    mov edx, 6
    call tf_set                 # equal bytes/caret still advance revision
    call cc_stale
    call cc_clear
    call cc_capture
    mov r12, [rbx + TF_revision]
    mov rdi, rbx
    lea rsi, [rip + cc_text]
    mov edx, 1
    call tf_insert
    cmp r12, [rbx + TF_revision]
    je cc_fail
    call cc_stale
    call cc_clear
    mov rdi, rbx
    call sb_free
    call cc_same

    # Empty Find close/reopen must invalidate even with identical cursor endpoints.
    inc qword ptr [rip + cc_stage]
    mov rax, [rip + cc_doc]
    mov r12, [rax + DOC_anchor]
    mov rdx, [rax + DOC_cur]
    mov [rax + DOC_anchor], rdx
    call cmd_find_bar
    call cc_capture
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call cmd_find_bar
    call cc_stale
    call cc_clear
    mov rax, [rip + cc_doc]
    mov [rax + DOC_anchor], r12
    mov rdi, [rip + cc_field]
    call sb_free
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call cc_same
    mov rdi, [rip + cc_snapshot]
    call mem_free
    mov rdi, [rip + cc_sn_snapshot]
    call mem_free
    mov rdi, [rip + cc_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rax, [rip + cc_live]
    cmp rax, [rip + g_mem_live]
    jne cc_fail
    mov edi, 1
    lea rsi, [rip + cc_ok]
    mov edx, 35
    call write_all
    xor edi, edi
    call sys_exit
