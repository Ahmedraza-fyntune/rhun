.include "rhun.inc"
.section .rodata
cm_text: .ascii "abc"
cm_piece_text: .ascii "a\nb\nc"
cm_pieces: .quad 2,5,0,3,4,1
cm_pairs: .quad 0,0,1,1
cm_bar: .ascii "|"
cm_distributed: .ascii "a\nb|c"
cm_full: .ascii "a\nb\nc|a\nb\nc"
cm_line: .ascii "L\n"
cm_line_result: .ascii "L\nabc"
cm_inner: .ascii "I"
cm_nested_rich: .ascii "L\naIbc"
cm_nested_plain: .ascii "L\naL\nbc"
cm_bad: .byte 0xff
cm_replaced: .ascii "replacement"
cm_ok: .ascii "ok native clipboard metadata delivery\n"
.bss
.p2align 3
cm_stage: .quad 0
cm_live: .quad 0
cm_doc: .quad 0
cm_snapshot: .quad 0
cm_wire: .quad 0
cm_wirelen: .quad 0
cm_second: .quad 0
cm_secondlen: .quad 0
cm_token: .quad 0
cm_calls: .quad 0
cm_mode: .quad 0
cm_accept: .quad 0
cm_seen: .quad 0
cm_out: .zero 64
cm_view: .zero CWB_SIZE
.text
cm_fail:
    mov edi, [rip + cm_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  call sys_exit
cm_get:
    PROLOGUE
    inc qword ptr [rip + cm_calls]
    mov rax, [rip + app_clip_active_token]
    mov [rip + cm_token], rax
    cmp qword ptr [rip + cm_calls], 2
    jne .Lcm_get_done
    cmp qword ptr [rip + cm_mode], 0
    je .Lcm_get_done
    mov rbx, [rip + clip_delivery_view]
    test rbx, rbx
    jz cm_fail
    mov r12, [rbx + CWB_text]
    mov r13, [rbx + CWB_len]
    mov rdi, r12
    mov rsi, r13
    call ed_clip_linewise
    cmp eax, 1
    jne cm_fail
    # Free both headless source buffers while the outer detached bytes are still in use.
    lea rdi, [rip + cm_replaced]
    mov esi, 11
    call headless_clip_set
    cmp eax, 1
    jne cm_fail
    mov rdi, r12
    lea rsi, [rip + cm_line]
    mov edx, 2
    call memeq
    test eax, eax
    jz cm_fail
    cmp qword ptr [rip + cm_mode], 1
    jne 2f
    mov rdi, [rip + cm_token]
    mov rsi, [rip + cm_second]
    mov rdx, [rip + cm_secondlen]
    call app_clip_complete_native
    cmp eax, 1
    jne cm_fail
    jmp 3f
2:  mov rdi, [rip + cm_token]
    cmp qword ptr [rip + cm_mode], 3
    jne 21f
    xor edi, edi
21: mov rsi, r12
    mov rdx, r13
    mov ecx, 1
    call app_clip_complete
    cmp qword ptr [rip + cm_mode], 3
    jne 3f
    mov rdi, [rip + cm_token]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call app_clip_complete
3:  cmp rbx, [rip + clip_delivery_view]
    jne cm_fail
    mov rdi, r12
    mov rsi, r13
    call ed_clip_linewise
    cmp eax, 1
    jne cm_fail
.Lcm_get_done:
    EPILOGUE
cm_rich:
    PROLOGUE
    lea rdx, [rip + cm_view]
    call clip_wire_decode
    cmp eax, 1
    jne cm_fail
    mov rax, [rip + cm_view + CWB_metadata]
    test rax, rax
    jz cm_fail
    cmp qword ptr [rax + ECM_count], 2
    jne cm_fail
    cmp qword ptr [rax + ECM_total], 5
    jne cm_fail
    mov rdi, rax
    lea rsi, [rip + cm_pieces]
    mov edx, 48
    call memeq
    test eax, eax
    jz cm_fail
    inc qword ptr [rip + cm_seen]
    mov rax, [rip + cm_accept]
    EPILOGUE
cm_setup:
    PROLOGUE
    inc qword ptr [rip + cm_stage]
    lea rax, [rip + headless_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + headless_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    lea rax, [rip + cm_get]
    mov [rip + g_plat + P_clip_get], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    call headless_clip_reset
    mov rax, [rip + g_mem_live]
    mov [rip + cm_live], rax
    mov qword ptr [rip + cm_mode], 0
    mov qword ptr [rip + cm_calls], 0
    mov qword ptr [rip + cm_seen], 0
    mov qword ptr [rip + cm_wire], 0
    mov qword ptr [rip + cm_second], 0
    mov dword ptr [rip + cfg_vim], 0
    mov dword ptr [rip + cfg_multi_cursor_paste], 0
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call doc_new
    mov [rip + cm_doc], rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + cm_text]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    EPILOGUE
cm_cleanup:
    PROLOGUE
    call app_clip_reset
    cmp qword ptr [rip + clip_delivery_view], 0
    jne cm_fail
    lea rax, [rip + headless_clip_write]
    mov [rip + g_plat + P_clip_write], rax
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    call headless_clip_reset
    mov rdi, [rip + cm_doc]
    call doc_free
    mov qword ptr [rip + g_doc], 0
    mov rdi, [rip + cm_wire]
    call mem_free
    mov rdi, [rip + cm_second]
    call mem_free
    mov rax, [rip + cm_live]
    cmp rax, [rip + g_mem_live]
    jne cm_fail
    EPILOGUE
cm_encode:
    PROLOGUE
    call clip_wire_encode
    test rax, rax
    jz cm_fail
    mov [rip + cm_wire], rax
    mov [rip + cm_wirelen], rdx
    EPILOGUE
cm_write:
    PROLOGUE
    mov rdi, [rip + cm_wire]
    mov rsi, [rip + cm_wirelen]
    call headless_clip_write
    cmp eax, 1
    jne cm_fail
    EPILOGUE
cm_request:
    PROLOGUE
    call app_clip_request
    cmp eax, 1
    jne cm_fail
    EPILOGUE
cm_check:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + cm_doc]
    call doc_len
    cmp rax, r13
    jne cm_fail
    mov rdi, [rip + cm_doc]
    xor esi, esi
    mov rdx, r13
    lea rcx, [rip + cm_out]
    call doc_copy
    lea rdi, [rip + cm_out]
    mov rsi, r12
    mov rdx, r13
    call memeq
    test eax, eax
    jz cm_fail
    EPILOGUE
FN main
    PROLOGUE
    # Foreign metadata distributes pieces containing internal newlines at two carets.
    call cm_setup
    mov rdi, [rip + cm_doc]
    xor esi, esi
    mov edx, 3
    xor ecx, ecx
    call doc_delete
    mov rdi, [rip + cm_doc]
    xor esi, esi
    lea rdx, [rip + cm_bar]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cm_doc]
    lea rsi, [rip + cm_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne cm_fail
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    xor edx, edx
    lea rcx, [rip + cm_pieces]
    call cm_encode
    call cm_write
    call cm_request
    call headless_clip_get
    lea rdi, [rip + cm_distributed]
    mov esi, 5
    call cm_check
    call cm_cleanup

    # Whole-line metadata from a foreign source inserts above the current line.
    call cm_setup
    mov rax, [rip + cm_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call cm_encode
    call cm_write
    call cm_request
    call headless_clip_get
    lea rdi, [rip + cm_line_result]
    mov esi, 5
    call cm_check
    call cm_cleanup

    call cm_explicit_none
    call cm_reentry
    call cm_acceptance
    call cm_invalid
    call cm_alias
    call cm_no_segments
    call cm_bad_native_source
    mov edi, 1
    lea rsi, [rip + cm_ok]
    mov edx, 38
    call write_all
    xor edi, edi
    call sys_exit
cm_explicit_none:
    PROLOGUE
    call cm_setup
    # Prime local same-text whole-line state, then receive explicit native false.
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    cmp eax, 1
    jne cm_fail
    lea rdi, [rip + cm_line]
    mov esi, 2
    xor edx, edx
    xor ecx, ecx
    call cm_encode
    call cm_write
    mov rax, [rip + cm_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    call cm_request
    call headless_clip_get
    # Ordinary insertion yields aL\nbc, rather than a whole line above abc.
    lea rdi, [rip + cm_nested_plain + 2]
    mov esi, 5
    call cm_check
    lea rdi, [rip + cm_line]
    mov esi, 2
    call ed_clip_linewise
    test eax, eax
    jnz cm_fail
    call cm_cleanup

    # A plain source replacement must remove the old native envelope.
    call cm_setup
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call cm_encode
    call cm_write
    lea rdi, [rip + cm_inner]
    mov esi, 1
    call headless_clip_set
    cmp eax, 1
    jne cm_fail
    cmp qword ptr [rip + headless_clip_native + SB_ptr], 0
    jne cm_fail
    call cm_request
    call headless_clip_get
    lea rdi, [rip + cm_plain_result]
    mov esi, 4
    call cm_check
    call cm_cleanup
    EPILOGUE

cm_reentry:
    PROLOGUE
    mov r15d, 1
.Lcm_nested:
    call cm_setup
    mov [rip + cm_mode], r15
    lea rdi, [rip + cm_inner]
    mov esi, 1
    xor edx, edx
    xor ecx, ecx
    call clip_wire_encode
    test rax, rax
    jz cm_fail
    mov [rip + cm_second], rax
    mov [rip + cm_secondlen], rdx
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call cm_encode
    call cm_write
    mov rax, [rip + cm_doc]
    mov qword ptr [rax + DOC_cur], 1
    mov qword ptr [rax + DOC_anchor], 1
    call cm_request
    call cm_request
    call headless_clip_get
    cmp qword ptr [rip + cm_calls], 2
    jne cm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne cm_fail
    lea rdi, [rip + cm_nested_rich]
    mov esi, 6
    cmp r15d, 1
    je 1f
    lea rdi, [rip + cm_nested_plain]
    mov esi, 7
1:  call cm_check
    call cm_cleanup
    inc r15d
    cmp r15d, 3
    jbe .Lcm_nested
    EPILOGUE

cm_acceptance:
    PROLOGUE 32
    call cm_setup
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    mov rdi, [rip + headless_clip_native + SB_ptr]
    mov rsi, [rip + headless_clip_native + SB_len]
    lea rdx, [rip + cm_view]
    call clip_wire_decode
    cmp eax, 1
    jne cm_fail
    cmp qword ptr [rip + cm_view + CWB_line], 1
    jne cm_fail
    mov rdi, [rip + cm_doc]
    xor esi, esi
    mov edx, 3
    xor ecx, ecx
    call doc_delete
    mov rdi, [rip + cm_doc]
    xor esi, esi
    lea rdx, [rip + cm_piece_text]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cm_doc]
    mov esi, 5
    lea rdx, [rip + cm_inner]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cm_doc]
    call doc_undo
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    call snippet_new
    mov [rsp], rax
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    mov ecx, 3
    xor r8d, r8d
    call snippet_add
    mov rdi, [rsp]
    call snippet_validate
    cmp eax, 1
    jne cm_fail
    mov rdi, [rip + cm_doc]
    mov rsi, [rsp]
    xor edx, edx
    call snippet_attach
    mov rdi, [rip + cm_doc]
    lea rsi, [rip + cm_selection_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne cm_fail
    mov rdi, [rip + cm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, [rsp]
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 16], rax
    lea rax, [rip + cm_rich]
    mov [rip + g_plat + P_clip_write], rax
    mov qword ptr [rip + cm_accept], 0
    mov rdi, [rip + cm_doc]
    mov esi, 1
    call editor_multi_copy
    test eax, eax
    jnz cm_fail
    cmp edx, 5
    jne cm_fail
    mov rdi, [rip + cm_doc]
    mov rsi, [rsp + 8]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz cm_fail
    mov rdi, [rsp]
    mov rsi, [rsp + 16]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz cm_fail
    lea rdi, [rip + cm_line]
    mov esi, 2
    call ed_clip_linewise
    cmp eax, 1
    jne cm_fail
    mov qword ptr [rip + cm_accept], 1
    mov rdi, [rip + cm_doc]
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne cm_fail
    cmp qword ptr [rip + cm_seen], 2
    jne cm_fail
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    call editor_clip_segments_get
    test rax, rax
    jz cm_fail
    mov rdi, rax
    lea rsi, [rip + cm_pieces]
    mov edx, 48
    call memeq
    test eax, eax
    jz cm_fail
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, [rsp + 16]
    call mem_free
    call cm_cleanup
    EPILOGUE

cm_invalid:
    PROLOGUE
    call cm_setup
    mov rdi, [rip + cm_doc]
    mov esi, DOC_SIZE
    call mem_dup
    mov [rip + cm_snapshot], rax
    call cm_request
    mov rdi, [rip + cm_token]
    lea rsi, [rip + cm_bad]
    mov edx, 1
    call app_clip_complete_native
    test eax, eax
    jnz cm_fail
    mov rax, [rip + cm_token]
    cmp rax, [rip + app_clip_active_token]
    jne cm_fail
    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call cm_encode
    mov rdi, [rip + cm_token]
    mov rsi, [rip + cm_wire]
    mov rdx, [rip + cm_wirelen]
    call app_clip_complete_native
    cmp eax, 1
    jne cm_fail
    cmp qword ptr [rip + app_clip_active_token], 0
    jne cm_fail
    mov rdi, [rip + cm_doc]
    mov rsi, [rip + cm_snapshot]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz cm_fail
    # A valid stale native token is consumed as a format, with no document change.
    mov rdi, [rip + cm_token]
    mov rsi, [rip + cm_wire]
    mov rdx, [rip + cm_wirelen]
    call app_clip_complete_native
    cmp eax, 1
    jne cm_fail
    mov rdi, [rip + cm_snapshot]
    call mem_free
    call cm_cleanup
    EPILOGUE
.section .rodata
cm_plain_result: .ascii "Iabc"
cm_selection_pairs: .quad 3,0,5,4

.text
cm_alias:
    PROLOGUE
    call cm_setup
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call cm_encode
    call cm_write
    # Rich source aliases the old owned native wire.
    mov rdi, [rip + headless_clip_native + SB_ptr]
    mov rsi, [rip + headless_clip_native + SB_len]
    call headless_clip_write
    cmp eax, 1
    jne cm_fail
    # Plain source aliases the old native wire's text, freed by this write.
    mov rdi, [rip + headless_clip_native + SB_ptr]
    mov rsi, [rip + headless_clip_native + SB_len]
    lea rdx, [rip + cm_view]
    call clip_wire_decode
    cmp eax, 1
    jne cm_fail
    mov rdi, [rip + cm_view + CWB_text]
    mov rsi, [rip + cm_view + CWB_len]
    call headless_clip_set
    cmp eax, 1
    jne cm_fail
    # Plain source aliases its own old allocation.
    mov rdi, [rip + headless_clip_plain + SB_ptr]
    mov rsi, [rip + headless_clip_plain + SB_len]
    call headless_clip_set
    cmp eax, 1
    jne cm_fail
    call cm_request
    call headless_clip_get
    lea rdi, [rip + cm_line_result]
    mov esi, 5
    call cm_check
    call cm_cleanup
    EPILOGUE

cm_no_segments:
    PROLOGUE
    call cm_setup
    mov rdi, [rip + cm_doc]
    xor esi, esi
    mov edx, 3
    xor ecx, ecx
    call doc_delete
    mov rdi, [rip + cm_doc]
    xor esi, esi
    lea rdx, [rip + cm_piece_text]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cm_doc]
    lea rsi, [rip + cm_selection_pairs]
    mov edx, 2
    call doc_selections_set
    mov rdi, [rip + cm_doc]
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne cm_fail
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    call editor_clip_segments_get
    test rax, rax
    jz cm_fail
    mov rdi, [rip + cm_doc]
    xor esi, esi
    mov edx, 5
    xor ecx, ecx
    call doc_delete
    mov rdi, [rip + cm_doc]
    xor esi, esi
    lea rdx, [rip + cm_bar]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cm_doc]
    lea rsi, [rip + cm_pairs]
    mov edx, 2
    call doc_selections_set
    mov dword ptr [rip + cfg_multi_cursor_paste], 1
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    xor edx, edx
    xor ecx, ecx
    call cm_encode
    call cm_write
    call cm_request
    call headless_clip_get
    lea rdi, [rip + cm_full]
    mov esi, 11
    call cm_check
    lea rdi, [rip + cm_piece_text]
    mov esi, 5
    call editor_clip_segments_get
    test rax, rax
    jnz cm_fail
    call cm_cleanup
    EPILOGUE

cm_bad_native_source:
    PROLOGUE
    call cm_setup
    lea rdi, [rip + cm_line]
    mov esi, 2
    mov edx, 1
    xor ecx, ecx
    call cm_encode
    call cm_write
    # A malformed native format falls back to the same source's counted plain text.
    mov rax, [rip + headless_clip_native + SB_ptr]
    mov byte ptr [rax], 0
    call cm_request
    call headless_clip_get
    cmp qword ptr [rip + app_clip_active_token], 0
    jne cm_fail
    lea rdi, [rip + cm_line_result]
    mov esi, 5
    call cm_check
    call cm_cleanup
    EPILOGUE
