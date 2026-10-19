# Included by extproto.s. Every peer counter describes an accepted enqueue prefix.

# Capture the baseline of an accepted opened event. The caller owns current DOC/XK.
xe_opened_baseline:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + XK_language_revision]
    mov rax, [rbx + DOC_language_revision]
    mov [r12 + XK_language_revision], rax
    mov rax, [rbx + DOC_version]
    mov [r12 + XK_ver], rax
    mov [r12 + XK_text_ver], rax
    mov rax, [rbx + DOC_saves]
    mov [r12 + XK_saves], rax
    mov qword ptr [r12 + XK_cur], -1
    mov qword ptr [r12 + XK_anchor], -1
    mov qword ptr [r12 + XK_selcur], -1
    mov qword ptr [r12 + XK_resync], 0
    mov qword ptr [r12 + XK_replay], 7
    mov qword ptr [r12 + XK_phase], XP_POSITIONS
    test r13, r13
    jnz 2f
    # Preserve initial catch-up: only the active document replays its position.
    mov qword ptr [r12 + XK_replay], 0
    call active_doc_id
    cmp rax, [rbx + DOC_id]
    jne 2f
    mov qword ptr [r12 + XK_replay], 3
2:  mov rax, [rbx + DOC_xedits]
    xor edx, edx
    test rax, rax
    jz 1f
    mov rdx, [rax + SB_len]
1:  mov [r12 + XK_eoff], rdx
    EPILOGUE

# xe_text(ext, doc, xk) ->0/-errno. No counter advances after a refused frame.
xe_text:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rbx + EXT_sub_edits]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jz .Lxt_no_edits
    mov rax, [r12 + DOC_version]
    cmp [r13 + XK_text_ver], rax
    jne .Lxt_text_due
    cmp qword ptr [r13 + XK_resync], 0
    je .Lxt_changed
.Lxt_text_due:
    cmp qword ptr [r13 + XK_resync], 0
    jne .Lxt_resync
    cmp dword ptr [r12 + DOC_xresync], 0
    jne .Lxt_resync
    mov rax, [r12 + DOC_xedits]
    test rax, rax
    jz .Lxt_resync
    mov rcx, [r13 + XK_eoff]
    cmp rcx, [rax + SB_len]
    jae .Lxt_resync
    mov rdi, r12
    mov rsi, r13
    call send_edits
    test rax, rax
    js .Lxt_done
    jmp .Lxt_text_accepted
.Lxt_resync:
    lea rdi, [rip + .Lev_resync]
    mov rsi, r12
    call send_doc_version
    test rax, rax
    js .Lxt_done
    mov rax, [r12 + DOC_xedits]
    xor edx, edx
    test rax, rax
    jz 1f
    mov rdx, [rax + SB_len]
1:  mov [r13 + XK_eoff], rdx
.Lxt_text_accepted:
    mov qword ptr [r13 + XK_resync], 0
.Lxt_no_edits:
    mov qword ptr [r13 + XK_resync], 0
    mov rax, [r12 + DOC_version]
    mov [r13 + XK_text_ver], rax
.Lxt_changed:
    mov r14, [r12 + DOC_version]
    cmp [r13 + XK_ver], r14
    je .Lxt_saved
    mov rdi, [rbx + EXT_sub_changed]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jz 2f
    lea rdi, [rip + .Lev_changed]
    mov rsi, r12
    call send_doc_version
    test rax, rax
    js .Lxt_done
2:  mov [r13 + XK_ver], r14
.Lxt_saved:
    mov r14, [r12 + DOC_saves]
    cmp [r13 + XK_saves], r14
    je .Lxt_ok
    mov rdi, [rbx + EXT_sub_saved]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jz 3f
    lea rdi, [rip + .Lev_saved]
    mov rsi, r12
    call send_doc_version
    test rax, rax
    js .Lxt_done
3:  mov [r13 + XK_saves], r14
.Lxt_ok:
    xor eax, eax
.Lxt_done:
    EPILOGUE

# xe_document(ext, doc, xk) ->0/-errno. Fresh DOC synchronization precedes this helper.
xe_document:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [r13 + XK_phase], XP_NEED_OPEN
    je .Lxd_open
    cmp qword ptr [r13 + XK_phase], XP_DORMANT
    je .Lxd_open
    mov rax, [r12 + DOC_language_revision]
    cmp [r13 + XK_language_revision], rax
    je .Lxd_phase
    mov qword ptr [r13 + XK_phase], XP_NEED_CLOSE
.Lxd_phase:
    cmp qword ptr [r13 + XK_phase], XP_NEED_CLOSE
    jne .Lxd_text
    mov rdi, [r13 + XK_id]
    call send_closed
    test rax, rax
    js .Lxd_done
    mov qword ptr [r13 + XK_phase], XP_NEED_OPEN
    mov qword ptr [r13 + XK_replay], 0
.Lxd_open:
    mov rdi, [rbx + EXT_sub_opened]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jnz .Lxd_send_opened
    mov qword ptr [r13 + XK_phase], XP_DORMANT
    jmp .Lxd_ok
.Lxd_send_opened:
    mov rdi, r12
    call send_opened
    test rax, rax
    js .Lxd_done
    mov rdi, r12
    mov rsi, r13
    call xe_opened_baseline
.Lxd_text:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call xe_text
    test rax, rax
    js .Lxd_done
    EPILOGUE
.Lxd_ok:
    xor eax, eax
.Lxd_done:
    EPILOGUE

# xe_positions(ext,doc,xk), after accepted current text and all opened events.
xe_positions:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [r13 + XK_phase], XP_POSITIONS
    jne .Lxp_events
    cmp qword ptr [r13 + XK_replay], 0
    jne .Lxp_events
    mov rax, [r12 + DOC_cur]
    mov [r13 + XK_cur], rax
    mov [r13 + XK_selcur], rax
    mov rax, [r12 + DOC_anchor]
    mov [r13 + XK_anchor], rax
    jmp .Lxp_ready
.Lxp_events:
    # Active precedes the new active document's cursor/selection replay.
    test qword ptr [r13 + XK_replay], 1
    jz .Lxp_cursor
    call active_doc_id
    cmp rax, [r12 + DOC_id]
    jne 1f
    mov r14, rax
    mov rdi, rax
    call send_active
    test rax, rax
    js .Lxp_done
    mov [rbx + EXT_active], r14
1:  and qword ptr [r13 + XK_replay], -2
.Lxp_cursor:
    test qword ptr [r13 + XK_replay], 2
    jnz .Lxp_cursor_due
    mov rax, [r12 + DOC_cur]
    cmp [r13 + XK_cur], rax
    je .Lxp_selection
.Lxp_cursor_due:
    mov r14, [r12 + DOC_cur]
    mov rdi, [rbx + EXT_sub_cursor]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jz 2f
    mov rdi, r12
    call send_cursor
    test rax, rax
    js .Lxp_done
2:  mov [r13 + XK_cur], r14
    and qword ptr [r13 + XK_replay], -3
.Lxp_selection:
    test qword ptr [r13 + XK_replay], 4
    jnz .Lxp_selection_due
    mov rax, [r12 + DOC_cur]
    cmp [r13 + XK_selcur], rax
    jne .Lxp_selection_due
    mov rax, [r12 + DOC_anchor]
    cmp [r13 + XK_anchor], rax
    je .Lxp_ready
.Lxp_selection_due:
    mov r14, [r12 + DOC_cur]
    mov r15, [r12 + DOC_anchor]
    mov rdi, [rbx + EXT_sub_selection]
    mov rsi, r12
    call sub_matches
    test eax, eax
    jz 3f
    # Initial/reopen replay includes empty selection. Ordinary collapsed motion needs no event.
    test qword ptr [r13 + XK_replay], 4
    jnz 4f
    cmp r14, r15
    jne 4f
    mov rax, [r13 + XK_selcur]
    cmp rax, [r13 + XK_anchor]
    je 3f
4:  mov rdi, r12
    call send_selection
    test rax, rax
    js .Lxp_done
3:  mov [r13 + XK_selcur], r14
    mov [r13 + XK_anchor], r15
    and qword ptr [r13 + XK_replay], -5
.Lxp_ready:
    mov qword ptr [r13 + XK_phase], XP_READY
.Lxp_ok:
    xor eax, eax
.Lxp_done:
    EPILOGUE

# extproto_events(ext) ->0 when all applicable preceding events were accepted, else -errno.
FN extproto_events
    PROLOGUE 16
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz .Lxe_pipe
    mov [rip + cur], rbx
    mov qword ptr [rsp], 0
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne .Lxe_pipe
    xor ecx, ecx
.Lxe_mark:
    cmp rcx, [rbx + EXT_known + VEC_len]
    jae .Lxe_start_tabs
    imul rax, rcx, XK_SIZE
    add rax, [rbx + EXT_known + VEC_ptr]
    mov qword ptr [rax + XK_seen], 0
    inc rcx
    jmp .Lxe_mark
.Lxe_start_tabs:
    xor r12d, r12d
.Lxe_tabs:
    cmp r12, [rip + g_tabs + VEC_len]
    jae .Lxe_start_closed
    imul rax, r12, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r12
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lxe_tabs
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz .Lxe_tabs
    mov rdi, r13
    call doc_sync_grammar
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, [r13 + DOC_id]
    call known_find
    mov r14, rax
    test rax, rax
    jz 1f
    mov qword ptr [r14 + XK_seen], 1
1:  cmp qword ptr [rsp + 8], 0
    jl .Lxe_sync_failed
    cmp qword ptr [r13 + DOC_language_revision], 0
    je .Lxe_exhausted
    test r14, r14
    jnz .Lxe_known
    mov rdi, [rbx + EXT_sub_opened]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz .Lxe_tabs
    lea rdi, [rbx + EXT_known]
    mov esi, XK_SIZE
    call vec_push
    mov r14, rax
    mov rdi, r14
    xor esi, esi
    mov edx, XK_SIZE
    call memset
    mov rcx, [r13 + DOC_id]
    mov [r14 + XK_id], rcx
    mov qword ptr [r14 + XK_phase], XP_NEED_OPEN
    mov qword ptr [r14 + XK_seen], 1
.Lxe_known:
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call xe_document
    test rax, rax
    jns .Lxe_tabs
    cmp rax, -32
    je .Lxe_return
    mov [rsp], rax
    jmp .Lxe_tabs
.Lxe_sync_failed:
    mov rax, [rsp + 8]
    mov [rsp], rax
    jmp .Lxe_tabs
.Lxe_exhausted:
    mov qword ptr [rsp], -75
    jmp .Lxe_tabs
.Lxe_start_closed:
    # Every initial opened event precedes position replay, including another document.
    cmp qword ptr [rsp], 0
    jne .Lxe_closed_begin
    xor r12d, r12d
.Lxe_positions:
    cmp r12, [rip + g_tabs + VEC_len]
    jae .Lxe_closed_begin
    imul rax, r12, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r12
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lxe_positions
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz .Lxe_positions
    mov rdi, r13
    call doc_sync_grammar
    test rax, rax
    js .Lxe_positions_failed
    mov rdi, rbx
    mov rsi, [r13 + DOC_id]
    call known_find
    test rax, rax
    jz .Lxe_positions
    mov r14, rax
    cmp qword ptr [r14 + XK_phase], XP_NEED_OPEN
    je .Lxe_positions
    cmp qword ptr [r14 + XK_phase], XP_NEED_CLOSE
    je .Lxe_positions
    cmp qword ptr [r14 + XK_phase], XP_DORMANT
    je .Lxe_positions
    mov rax, [r13 + DOC_language_revision]
    test rax, rax
    jz .Lxe_positions_pending
    cmp [r14 + XK_language_revision], rax
    jne .Lxe_positions_pending
    mov rax, [r13 + DOC_version]
    cmp [r14 + XK_text_ver], rax
    jne .Lxe_positions_pending
    cmp [r14 + XK_ver], rax
    jne .Lxe_positions_pending
    mov rax, [r13 + DOC_saves]
    cmp [r14 + XK_saves], rax
    jne .Lxe_positions_pending
    cmp qword ptr [r14 + XK_resync], 0
    jne .Lxe_positions_pending
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call xe_positions
    test rax, rax
    jns .Lxe_positions
.Lxe_positions_failed:
    cmp rax, -32
    je .Lxe_return
    mov [rsp], rax
    jmp .Lxe_positions
.Lxe_positions_pending:
    mov qword ptr [rsp], -11
    jmp .Lxe_positions
.Lxe_closed_begin:
    xor r12d, r12d
.Lxe_closed:
    cmp r12, [rbx + EXT_known + VEC_len]
    jae .Lxe_active
    imul r14, r12, XK_SIZE
    add r14, [rbx + EXT_known + VEC_ptr]
    cmp qword ptr [r14 + XK_seen], 0
    jne .Lxe_closed_next
    cmp qword ptr [r14 + XK_phase], XP_NEED_OPEN
    je .Lxe_remove
    cmp qword ptr [r14 + XK_phase], XP_DORMANT
    je .Lxe_remove
    mov rdi, [r14 + XK_id]
    call send_closed
    test rax, rax
    jns .Lxe_remove
    cmp rax, -32
    je .Lxe_return
    mov [rsp], rax
    jmp .Lxe_closed_next
.Lxe_remove:
    mov rcx, [rbx + EXT_known + VEC_len]
    dec rcx
    mov [rbx + EXT_known + VEC_len], rcx
    imul rsi, rcx, XK_SIZE
    add rsi, [rbx + EXT_known + VEC_ptr]
    mov rdi, r14
    mov edx, XK_SIZE
    call memcpy
    jmp .Lxe_closed
.Lxe_closed_next:
    inc r12
    jmp .Lxe_closed
.Lxe_active:
    cmp qword ptr [rsp], 0
    jne .Lxe_result
    call active_doc_id
    mov r15, rax
    cmp [rbx + EXT_active], rax
    je .Lxe_result
    test r15, r15
    jz .Lxe_send_active
    mov rdi, rbx
    mov rsi, r15
    call known_find
    test rax, rax
    jz .Lxe_send_active
    cmp qword ptr [rax + XK_phase], XP_READY
    je .Lxe_send_active
    cmp qword ptr [rax + XK_phase], XP_DORMANT
    jne .Lxe_active_pending
.Lxe_send_active:
    mov rdi, r15
    call send_active
    test rax, rax
    jns 2f
    cmp rax, -32
    je .Lxe_return
    mov [rsp], rax
    jmp .Lxe_result
2:  mov [rbx + EXT_active], r15
    jmp .Lxe_result
.Lxe_active_pending:
    mov qword ptr [rsp], -11
.Lxe_result:
    mov rax, [rsp]
.Lxe_return:
    EPILOGUE
.Lxe_pipe:
    mov rax, -32
    EPILOGUE

# extproto_doc_ready(ext, live doc) ->1/0. This is stronger than known-record existence.
FN extproto_doc_ready
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_is_visible
    test eax, eax
    jz 8f
    mov rdi, r12
    call doc_sync_grammar
    test rax, rax
    js 8f
    mov rdi, rbx
    mov rsi, [r12 + DOC_id]
    call known_find
    test rax, rax
    jz 8f
    cmp qword ptr [rax + XK_phase], XP_READY
    jne 8f
    mov rcx, [r12 + DOC_language_revision]
    test rcx, rcx
    jz 8f
    cmp [rax + XK_language_revision], rcx
    jne 8f
    mov rcx, [r12 + DOC_version]
    cmp [rax + XK_text_ver], rcx
    jne 8f
    cmp [rax + XK_ver], rcx
    jne 8f
    mov rcx, [r12 + DOC_saves]
    cmp [rax + XK_saves], rcx
    jne 8f
    cmp qword ptr [rax + XK_resync], 0
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Transfer undelivered history into per-peer debt before shared edit/resync storage changes.
FN extproto_edits_debt
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, r13
    mov rsi, [rbx + DOC_id]
    call known_find
    test rax, rax
    jz 1b
    cmp qword ptr [rax + XK_phase], XP_NEED_OPEN
    je 1b
    cmp qword ptr [rax + XK_phase], XP_DORMANT
    je 1b
    mov rcx, [rbx + DOC_version]
    cmp [rax + XK_text_ver], rcx
    jne 2f
    jmp 1b
2:  mov qword ptr [rax + XK_resync], 1
    jmp 1b
9:  EPILOGUE
