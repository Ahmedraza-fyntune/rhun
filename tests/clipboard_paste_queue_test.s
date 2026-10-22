.include "rhun.inc"
.section .rodata
pq_text: .ascii "abcdef"
pq_one: .ascii "X"
pq_two: .ascii "Y"
pq_three: .ascii "Z"
pq_fifo: .ascii "XYZabcdef"
pq_twice: .ascii "XYabcdef"
pq_once: .ascii "Xabcdef"
pq_vim: .ascii "aYYZXbcdef"
pq_visual: .ascii "Xcdef"
pq_vline_fifo: .ascii "YZX"
pq_at_end: .ascii "abcdeXYZf"
pq_at_lf: .ascii "abcdeXYZf\n"
pq_lf: .byte 10
pq_xyz: .ascii "XYZ"
pq_multi: .ascii "XYZabcdefXYZ"
pq_pairs: .quad 0,0,6,6
pq_bad: .byte 0xff
pq_ok: .ascii "ok clipboard paste request queue\n"
.bss
.p2align 3
pq_stage: .quad 0
pq_live: .quad 0
pq_doc: .quad 0
pq_other: .quad 0
pq_snapshot: .quad 0
pq_token: .quad 0
pq_first_token: .quad 0
pq_calls: .quad 0
pq_sync: .quad 0
pq_field: .quad 0
pq_sn: .quad 0
pq_sn_snapshot: .quad 0
pq_pre: .zero CPX_SIZE
pq_post: .zero CPX_SIZE
pq_buffer: .zero 64
.text
pq_fail:
    mov edi, [rip + pq_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  call sys_exit
pq_get:
    inc qword ptr [rip + pq_calls]
    mov rax, [rip + app_clip_active_token]
    test rax, rax
    jz pq_fail
    mov [rip + pq_token], rax
    cmp qword ptr [rip + pq_sync], 1
    je 1f
    cmp qword ptr [rip + pq_sync], 2
    je 2f
    cmp qword ptr [rip + pq_sync], 3
    je 3f
    ret
1:  mov rdi, rax
    lea rsi, [rip + pq_one]
    mov edx, 1
    mov ecx, 1
    jmp app_clip_complete
2:  cmp qword ptr [rip + pq_calls], 1
    jne 4f
    jmp pq_request
3:  cmp qword ptr [rip + pq_calls], 1
    jne 4f
    sub rsp, 8
    call pq_x
    call pq_request
    add rsp, 8
4:  ret

pq_setup:
    PROLOGUE
    inc qword ptr [rip + pq_stage]
    mov rax, [rip + g_mem_live]
    mov [rip + pq_live], rax
    mov qword ptr [rip + pq_calls], 0
    mov qword ptr [rip + pq_sync], 0
    mov dword ptr [rip + cfg_vim], 0
    mov dword ptr [rip + g_vim_mode], VM_NORMAL
    mov dword ptr [rip + g_vim_cmdline], 0
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call doc_new
    mov [rip + pq_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + pq_text]
    mov ecx, 6
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + pq_doc]
    mov esi, 6
    lea rdx, [rip + pq_one]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + pq_doc]
    call doc_undo
    mov rdi, [rip + pq_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + pq_snapshot], rax
    EPILOGUE
pq_cleanup:
    PROLOGUE
    call app_clip_reset
    call app_clip_timeout
    cmp eax, -1
    jne pq_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne pq_fail
    mov rdi, [rip + pq_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, [rip + pq_snapshot]
    call mem_free
    mov rax, [rip + pq_live]
    cmp rax, [rip + g_mem_live]
    jne pq_fail
    EPILOGUE
pq_request:
    sub rsp, 8
    call app_clip_request
    cmp eax, 1
    jne pq_fail
    add rsp, 8
    ret
pq_same:
    sub rsp, 8
    mov rdi, [rip + pq_doc]
    mov rsi, [rip + pq_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz pq_fail
    add rsp, 8
    ret
pq_complete:
    mov ecx, 1
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + pq_token]
    jmp app_clip_complete
pq_x:
    lea rdi, [rip + pq_one]
    mov esi, 1
    jmp pq_complete
pq_y:
    lea rdi, [rip + pq_two]
    mov esi, 1
    jmp pq_complete
pq_z:
    lea rdi, [rip + pq_three]
    mov esi, 1
    jmp pq_complete
pq_text_check:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + pq_doc]
    call doc_len
    cmp rax, r13
    jne pq_fail
    mov rdi, [rip + pq_doc]
    xor esi, esi
    mov rdx, r13
    lea rcx, [rip + pq_buffer]
    call doc_copy
    lea rdi, [rip + pq_buffer]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jz pq_fail
    EPILOGUE

FN main
    PROLOGUE 32
    lea rax, [rip + pq_get]
    mov [rip + g_plat + P_clip_get], rax
    call pq_setup
    call pq_request
    call pq_request
    call pq_request
    cmp qword ptr [rip + pq_calls], 1
    jne pq_fail
    call pq_same
    mov rax, [rip + pq_token]
    mov [rip + pq_first_token], rax
    call pq_x
    cmp qword ptr [rip + pq_calls], 2
    jne pq_fail
    lea rdi, [rip + pq_once]
    mov esi, 7
    call pq_text_check
    # A duplicate old completion cannot consume the newly active head.
    mov rdi, [rip + pq_first_token]
    lea rsi, [rip + pq_bad]
    mov edx, 1
    mov ecx, 1
    call app_clip_complete
    call pq_y
    cmp qword ptr [rip + pq_calls], 3
    jne pq_fail
    call pq_z
    lea rdi, [rip + pq_fifo]
    mov esi, 9
    call pq_text_check
    mov r12d, 3
1:  mov rdi, [rip + pq_doc]
    call doc_undo
    dec r12d
    jnz 1b
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    mov r12d, 3
2:  mov rdi, [rip + pq_doc]
    call doc_redo
    dec r12d
    jnz 2b
    lea rdi, [rip + pq_fifo]
    mov esi, 9
    call pq_text_check
    call pq_cleanup

    # Switched/closed current document cannot receive the old request.
    call pq_setup
    call pq_request
    call doc_new
    mov [rip + pq_other], rax
    mov [rip + g_doc], rax
    call pq_x
    mov rdi, [rip + pq_other]
    call doc_len
    test rax, rax
    jnz pq_fail
    call pq_same
    mov rdi, [rip + pq_other]
    call doc_free
    mov rax, [rip + pq_doc]
    mov [rip + g_doc], rax
    call pq_cleanup

    # Selection changes reject the active and same-old-context followers.
    call pq_setup
    call pq_request
    call pq_request
    mov rax, [rip + pq_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    call pq_x
    cmp qword ptr [rip + pq_calls], 1
    jne pq_fail
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    call pq_cleanup

    # Failure, empty and invalid data are no-ops and make progress to the next request.
    call pq_setup
    call pq_request
    call pq_request
    call pq_request
    call pq_request
    call pq_request
    mov rdi, [rip + pq_token]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call app_clip_complete
    lea rdi, [rip + pq_bad]
    mov esi, 1
    call pq_complete
    xor edi, edi
    xor esi, esi
    call pq_complete
    lea rdi, [rip + pq_one]
    mov esi, DOC_MULTI_BYTES_MAX + 1
    call pq_complete
    cmp qword ptr [rip + pq_calls], 5
    jne pq_fail
    call pq_same
    call pq_x
    lea rdi, [rip + pq_once]
    mov esi, 7
    call pq_text_check
    call pq_cleanup

    # Full capacity refuses before modifying queued requests or the destination.
    call pq_setup
    mov r12d, CPR_COUNT
3:  call pq_request
    dec r12d
    jnz 3b
    call app_clip_request
    test eax, eax
    jnz pq_fail
    cmp qword ptr [rip + pq_calls], 1
    jne pq_fail
    call pq_same
    call pq_cleanup

    # Synchronous delivery returns accepted even after freeing its own request.
    call pq_setup
    mov qword ptr [rip + pq_sync], 1
    call pq_request
    lea rdi, [rip + pq_once]
    mov esi, 7
    call pq_text_check
    cmp qword ptr [rip + app_clip_active_token], 0
    jne pq_fail
    call pq_cleanup

    # Reentrant enqueue during the getter remains behind the active head.
    call pq_setup
    mov qword ptr [rip + pq_sync], 2
    call pq_request
    cmp qword ptr [rip + pq_calls], 1
    jne pq_fail
    call pq_x
    cmp qword ptr [rip + pq_calls], 2
    jne pq_fail
    call pq_y
    lea rdi, [rip + pq_twice]
    mov esi, 8
    call pq_text_check
    call pq_cleanup

    # A synchronous successor queued inside the getter yields until a later tick.
    call pq_setup
    mov qword ptr [rip + pq_sync], 3
    call pq_request
    cmp qword ptr [rip + pq_calls], 1
    jne pq_fail
    call app_clip_timeout
    test eax, eax
    jnz pq_fail
    call app_clip_tick
    cmp qword ptr [rip + pq_calls], 2
    jne pq_fail
    call pq_y
    lea rdi, [rip + pq_twice]
    mov esi, 8
    call pq_text_check
    call pq_cleanup

    call pq_fields
    call pq_extra
    call pq_vim_render
    mov edi, 1
    lea rsi, [rip + pq_ok]
    mov edx, 33
    call write_all
    xor edi, edi
    call sys_exit
pq_fields:
    PROLOGUE
    call pq_setup
    mov dword ptr [rip + g_focus], FOCUS_FIND
    call find_field
    mov [rip + pq_field], rax
    mov rdi, rax
    call tf_clear
    call pq_request
    call pq_request
    call pq_request
    call pq_x
    call pq_y
    call pq_z
    mov rdi, [rip + pq_field]
    call tf_text
    cmp rdx, 3
    jne pq_fail
    mov rdi, rax
    lea rsi, [rip + pq_xyz]
    mov edx, 3
    call memeq
    test eax, eax
    jz pq_fail
    mov rdi, [rip + pq_field]
    call sb_free
    lea rdi, [rip + g_ed_find]
    call sb_free
    call pq_cleanup

    # Empty text cannot delete a selected field, and stale field edits do not paste.
    call pq_setup
    mov dword ptr [rip + g_focus], FOCUS_FIND
    mov rdi, [rip + pq_field]
    lea rsi, [rip + pq_text]
    mov edx, 6
    call tf_set
    mov rdi, [rip + pq_field]
    call tf_select_all
    call pq_request
    mov rax, [rip + pq_field]
    mov r12, [rax + TF_revision]
    xor edi, edi
    xor esi, esi
    call pq_complete
    mov rax, [rip + pq_field]
    cmp [rax + TF_revision], r12
    jne pq_fail
    cmp qword ptr [rax + TF_cur], 6
    jne pq_fail
    cmp qword ptr [rax + TF_anchor], 0
    jne pq_fail
    call pq_request
    mov rdi, [rip + pq_field]
    call tf_revision_touch
    call pq_x
    mov rdi, [rip + pq_field]
    call tf_text
    cmp rdx, 6
    jne pq_fail
    mov rdi, rax
    lea rsi, [rip + pq_text]
    mov edx, 6
    call memeq
    test eax, eax
    jz pq_fail
    mov rdi, [rip + pq_field]
    call sb_free
    call pq_same
    call pq_cleanup
    call pq_vim_cases
    EPILOGUE

# Warm Vim's intentional reusable buffers before per-case allocation balance assertions.
pq_vim_warm:
    PROLOGUE
    call doc_new
    mov [rip + g_doc], rax
    mov rbx, rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_NORMAL
    mov edi, 'p'
    mov esi, 1
    mov edx, VM_NORMAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    call pq_x
    call app_clip_reset
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    EPILOGUE
pq_vim_cases:
    PROLOGUE
    call pq_vim_warm
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov edi, 'p'
    mov esi, 1
    mov edx, VM_NORMAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    mov edi, 'P'
    mov esi, 2
    mov edx, VM_NORMAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    mov edi, 'p'
    mov esi, 1
    mov edx, VM_NORMAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    call pq_x
    call pq_y
    call pq_z
    lea rdi, [rip + pq_vim]
    mov esi, 10
    call pq_text_check
    mov r12d, 3
1:  mov rdi, [rip + pq_doc]
    call doc_undo
    dec r12d
    jnz 1b
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    mov r12d, 3
2:  mov rdi, [rip + pq_doc]
    call doc_redo
    dec r12d
    jnz 2b
    lea rdi, [rip + pq_vim]
    mov esi, 10
    call pq_text_check
    call pq_cleanup
    EPILOGUE

pq_extra:
    PROLOGUE
    # Error completion preserves a live snippet and existing redo byte-for-byte.
    call pq_setup
    lea rdi, [rip + pq_text]
    mov esi, 6
    call snippet_new
    mov [rip + pq_sn], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 6
    xor r8d, r8d
    call snippet_add
    mov rdi, [rip + pq_sn]
    call snippet_validate
    cmp eax, 1
    jne pq_fail
    mov rdi, [rip + pq_doc]
    mov rsi, [rip + pq_sn]
    xor edx, edx
    call snippet_attach
    mov rdi, [rip + pq_snapshot]
    call mem_free
    mov rdi, [rip + pq_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + pq_snapshot], rax
    mov rdi, [rip + pq_sn]
    mov esi, SN_SIZE
    call mem_dup
    mov [rip + pq_sn_snapshot], rax
    call pq_request
    call pq_request
    lea rdi, [rip + pq_bad]
    mov esi, 1
    call pq_complete
    call pq_same
    mov dword ptr [rip + g_focus], FOCUS_FIND
    call pq_x
    call pq_same
    mov rdi, [rip + pq_sn]
    mov rsi, [rip + pq_sn_snapshot]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz pq_fail
    mov rdi, [rip + pq_sn_snapshot]
    call mem_free
    call pq_cleanup

    # Repeated multi-selection paste rebases all carets and keeps separate history.
    call pq_setup
    mov rdi, [rip + pq_doc]
    lea rsi, [rip + pq_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne pq_fail
    call pq_request
    call pq_request
    call pq_request
    call pq_x
    call pq_y
    call pq_z
    lea rdi, [rip + pq_multi]
    mov esi, 12
    call pq_text_check
    mov r12d, 3
1:  mov rdi, [rip + pq_doc]
    call doc_undo
    dec r12d
    jnz 1b
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    mov rdi, [rip + pq_doc]
    call doc_selections_count
    cmp rax, 2
    jne pq_fail
    mov r12d, 3
2:  mov rdi, [rip + pq_doc]
    call doc_redo
    dec r12d
    jnz 2b
    lea rdi, [rip + pq_multi]
    mov esi, 12
    call pq_text_check
    call pq_cleanup

    # A post-route context for another document/kind cannot rebind old followers.
    xor r15d, r15d
.Lpq_post:
    call pq_setup
    call pq_request
    call pq_request
    lea rdi, [rip + pq_pre]
    call clip_context_capture
    cmp eax, 1
    jne pq_fail
    test r15d, r15d
    jnz 3f
    call doc_new
    mov [rip + pq_other], rax
    mov [rip + g_doc], rax
    jmp 4f
3:  mov dword ptr [rip + g_focus], FOCUS_FIND
4:  lea rdi, [rip + pq_post]
    call clip_context_capture
    cmp eax, 1
    jne pq_fail
    lea rdi, [rip + pq_pre]
    lea rsi, [rip + pq_post]
    call clip_request_rebase
    test r15d, r15d
    jnz 5f
    mov rdi, [rip + pq_other]
    call doc_free
5:  mov rax, [rip + pq_doc]
    mov [rip + g_doc], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call pq_x
    call pq_y
    cmp qword ptr [rip + pq_calls], 2
    jne pq_fail
    lea rdi, [rip + pq_twice]
    mov esi, 8
    call pq_text_check
    lea rdi, [rip + pq_pre]
    call clip_context_clear
    lea rdi, [rip + pq_post]
    call clip_context_clear
    call pq_cleanup
    inc r15d
    cmp r15d, 2
    jb .Lpq_post

    # Expansion preflight rejects huge Vim counts before allocating repeated text.
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov edi, 'p'
    mov esi, 33554433
    mov edx, VM_NORMAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    lea rdi, [rip + pq_twice]
    mov esi, 2
    call pq_complete
    call pq_same
    call pq_cleanup
    EPILOGUE

# Clipboard admission must survive render-only Vim selection/caret normalization.
pq_vim_render:
    PROLOGUE
    xor r15d, r15d
.Lpq_visual_render:
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_VISUAL
    mov rbx, [rip + pq_doc]
    mov qword ptr [rbx + DOC_cur], 1
    mov qword ptr [rbx + DOC_anchor], 0
    cmp r15d, 1
    jne 1f
    mov qword ptr [rbx + DOC_cur], 0
    mov qword ptr [rbx + DOC_anchor], 1
1:  cmp r15d, 2
    jne 2f
    mov dword ptr [rip + g_vim_mode], VM_VLINE
2:  cmp r15d, 3
    je 3f
    call vim_export
    jmp 4f
3:  mov dword ptr [rip + g_vim_mode], VM_NORMAL
    mov qword ptr [rbx + DOC_cur], 2
4:  mov r12, [rbx + DOC_cur]
    mov r13, [rbx + DOC_anchor]
    mov r14d, [rip + g_vim_mode]
    call pq_request
    # Capture and initial pump validation are pure.
    cmp r12, [rbx + DOC_cur]
    jne pq_fail
    cmp r13, [rbx + DOC_anchor]
    jne pq_fail
    cmp r14d, [rip + g_vim_mode]
    jne pq_fail
    mov rdi, rbx
    call vim_view
    call pq_x
    lea rdi, [rip + pq_visual]
    mov esi, 5
    cmp r15d, 2
    jne 5f
    lea rdi, [rip + pq_one]
    mov esi, 1
5:  call pq_text_check
    call pq_cleanup
    inc r15d
    cmp r15d, 4
    jb .Lpq_visual_render

    # Empty exported visual selections take vim_view's caret branch first.
    mov r15d, VM_VISUAL
.Lpq_empty_visual:
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov [rip + g_vim_mode], r15d
    mov rdi, [rip + pq_doc]
    xor esi, esi
    mov edx, 6
    xor ecx, ecx
    call doc_delete
    mov rbx, [rip + pq_doc]
    mov qword ptr [rbx + DOC_cur], 0
    mov qword ptr [rbx + DOC_anchor], 0
    call vim_export
    call pq_request
    mov rdi, rbx
    call vim_view
    call pq_x
    lea rdi, [rip + pq_one]
    mov esi, 1
    call pq_text_check
    call pq_cleanup
    inc r15d
    cmp r15d, VM_VLINE
    jbe .Lpq_empty_visual

    # Rejected Vim expansion cannot normalize an exported selection.
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_VISUAL
    mov rbx, [rip + pq_doc]
    mov qword ptr [rbx + DOC_cur], 1
    call vim_export
    mov edi, 'p'
    mov esi, 33554433
    mov edx, VM_VISUAL
    call app_clip_request_vim
    cmp eax, 1
    jne pq_fail
    mov r12, [rbx + DOC_cur]
    mov r13, [rbx + DOC_anchor]
    mov r14d, [rip + g_vim_mode]
    lea rdi, [rip + pq_twice]
    mov esi, 2
    call pq_complete
    cmp r12, [rbx + DOC_cur]
    jne pq_fail
    cmp r13, [rbx + DOC_anchor]
    jne pq_fail
    cmp r14d, [rip + g_vim_mode]
    jne pq_fail
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    call pq_cleanup

    # A real visual selection movement still cancels the delayed response.
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_VISUAL
    mov rbx, [rip + pq_doc]
    mov qword ptr [rbx + DOC_cur], 1
    call vim_export
    call pq_request
    mov rdi, rbx
    call vim_view
    inc qword ptr [rbx + DOC_cur]
    call pq_x
    lea rdi, [rip + pq_text]
    mov esi, 6
    call pq_text_check
    call pq_cleanup

    # Repeated ordinary Paste survives a post-paste EOF caret clamp.
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov dword ptr [rip + g_vim_mode], VM_VLINE
    call vim_export
    call pq_request
    call pq_request
    call pq_request
    mov rdi, [rip + pq_doc]
    call vim_view
    call pq_x
    mov rdi, [rip + pq_doc]
    call vim_view
    call pq_y
    mov rdi, [rip + pq_doc]
    call vim_view
    call pq_z
    lea rdi, [rip + pq_vline_fifo]
    mov esi, 3
    call pq_text_check
    call pq_cleanup

    xor r15d, r15d
.Lpq_end_render:
    call pq_setup
    mov dword ptr [rip + cfg_vim], 1
    mov rbx, [rip + pq_doc]
    test r15d, r15d
    jz 6f
    mov rdi, rbx
    mov esi, 6
    lea rdx, [rip + pq_lf]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
6:  mov qword ptr [rbx + DOC_cur], 6
    mov qword ptr [rbx + DOC_anchor], 6
    call pq_request
    call pq_request
    call pq_request
    mov rdi, rbx
    call vim_view
    call pq_x
    mov rdi, rbx
    call vim_view
    call pq_y
    mov rdi, rbx
    call vim_view
    call pq_z
    lea rdi, [rip + pq_at_end]
    mov esi, 9
    test r15d, r15d
    jz 7f
    lea rdi, [rip + pq_at_lf]
    mov esi, 10
7:  call pq_text_check
    call pq_cleanup
    inc r15d
    cmp r15d, 2
    jb .Lpq_end_render
    EPILOGUE
