# Deterministic accepted/refused output prefixes for the actual protocol event state machine.
.include "rhun.inc"
.bss
.p2align 3
ev_ext: .zero EXT_SIZE
ev_tab: .zero 2 * TAB_SIZE
ev_counts: .zero 80
ev_doc: .quad 0
ev_doc2: .quad 0
ev_open_allow: .quad 0
ev_reply_expected: .quad 0
ev_saved_off: .quad 0
ev_live: .quad 0
ev_stage: .quad 0
ev_block: .quad 0
.text
# Test-only out_end replacement, preserving the checked enqueue return contract.
FN ext_events_send
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    mov r13d, 9
    cmp byte ptr [rbx], '0'
    jne .Les_classified
    xor r13d, r13d
.Les_classify:
    lea r14, [rip + ev_prefixes]
    mov rdx, [r14 + r13*8]
    mov rdi, rdx
    call strlen
    cmp r12, rax
    jb .Les_next
    mov rcx, rax
    mov rsi, rax
    mov rdx, [r14 + r13*8]
    mov rdi, rbx
    call str_eq
    test eax, eax
    jnz .Les_classified
.Les_next:
    inc r13
    cmp r13, 9
    jb .Les_classify
    jmp ev_bad
.Les_classified:
    cmp r13, 9
    jne .Les_maybe_block
    mov rdi, [rip + ev_reply_expected]
    test rdi, rdi
    jz .Les_maybe_block
    call strlen
    mov rcx, rax
    mov rdx, [rip + ev_reply_expected]
    mov rdi, rbx
    mov rsi, r12
    call str_eq
    test eax, eax
    jz ev_bad
.Les_maybe_block:
    cmp [rip + ev_block], r13
    jne .Les_accepted
    cmp r13, 1
    jne .Les_refused
    cmp qword ptr [rip + ev_open_allow], 0
    je .Les_refused
    dec qword ptr [rip + ev_open_allow]
.Les_accepted:
    lea rax, [rip + ev_counts]
    inc qword ptr [rax + r13*8]
    xor eax, eax
    EPILOGUE
.Les_refused:
    mov rax, -11
    EPILOGUE

ev_events:
    lea rdi, [rip + ev_ext]
    jmp extproto_events

ev_request:
    lea rdi, [rip + ev_ext]
    lea rsi, [rip + ev_verb]
    mov rdx, [rip + ev_doc]
    lea rcx, [rip + ev_kind]
    mov r8d, 'x'
    jmp extproto_host_request

ev_known:
    lea rdi, [rip + ev_ext]
    mov rsi, [rip + ev_doc]
    mov rsi, [rsi + DOC_id]
    jmp extproto_known

ev_edit:
    mov rdi, [rip + ev_doc]
    xor esi, esi
    lea rdx, [rip + ev_byte]
    mov ecx, 1
    xor r8d, r8d
    jmp doc_insert

# Exercise actual parser/permission/text/range handlers, not a bookkeeping alias.
ev_receive:
    PROLOGUE
    mov rbx, rdi
    mov [rip + ev_reply_expected], rsi
    lea rdi, [rip + ev_ext + EXT_rbuf]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + ev_ext]
    call extproto_pump
    cmp qword ptr [rip + ev_ext + EXT_rbuf + SB_len], 0
    jne ev_bad
    mov qword ptr [rip + ev_reply_expected], 0
    EPILOGUE

ev_bad:
    mov rdi, [rip + ev_stage]
    add rdi, 70
    call sys_exit
    ud2

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + ev_live], rax
    mov qword ptr [rip + ev_block], -1
    call doc_new
    mov rbx, rax
    mov [rip + ev_doc], rax
    mov [rip + ev_tab + TAB_doc], rax
    mov [rip + g_doc], rax
    lea rax, [rip + ev_tab]
    mov [rip + g_tabs + VEC_ptr], rax
    mov qword ptr [rip + g_tabs + VEC_len], 1
    mov qword ptr [rip + g_tab_cur], 0
    mov qword ptr [rip + ev_tab + TAB_kind], TAB_DOC
    lea rax, [rip + ev_ext]
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov dword ptr [rip + ev_ext + EXT_status], ES_RUNNING
    mov qword ptr [rip + ev_ext + EXT_active], -1
    lea rax, [rip + ev_star]
    mov [rip + ev_ext + EXT_sub_opened], rax
    mov [rip + ev_ext + EXT_sub_edits], rax
    mov [rip + ev_ext + EXT_sub_changed], rax
    mov [rip + ev_ext + EXT_sub_saved], rax
    mov [rip + ev_ext + EXT_sub_cursor], rax
    mov [rip + ev_ext + EXT_sub_selection], rax
    mov dword ptr [rip + g_ext_hooks], 1
    # The first document's opened fits, the second refuses. No position may bypass it.
    mov qword ptr [rip + ev_stage], 12
    call doc_new
    mov [rip + ev_doc2], rax
    mov [rip + ev_tab + TAB_SIZE + TAB_doc], rax
    mov qword ptr [rip + ev_tab + TAB_SIZE + TAB_kind], TAB_DOC
    mov qword ptr [rip + g_tabs + VEC_len], 2
    mov qword ptr [rip + ev_block], 1
    mov qword ptr [rip + ev_open_allow], 1
    call ev_events
    cmp rax, -11
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 8], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 24], 0
    jne ev_bad
    call ev_known
    cmp qword ptr [rax + XK_phase], XP_POSITIONS
    jne ev_bad
    mov qword ptr [rip + ev_block], -1
    call ev_events
    test rax, rax
    jnz ev_bad
    cmp qword ptr [rip + ev_counts + 8], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 1
    jne ev_bad
    # Return to a single-document baseline for the remaining independent prefixes.
    mov qword ptr [rip + g_tabs + VEC_len], 1
    call ev_events
    test rax, rax
    jnz ev_bad
    mov qword ptr [rip + ev_counts], 0
    mov qword ptr [rip + ev_counts + 8], 1
    mov rdi, [rip + ev_doc2]
    call doc_free
    mov qword ptr [rip + ev_doc2], 0
    mov qword ptr [rip + ev_stage], 1
    call ev_events
    cmp rax, 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_READY
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 8], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 24], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 32], 0
    jne ev_bad
    mov rdi, rbx
    lea rsi, [rip + ev_grammar]
    call doc_set_grammar
    cmp rax, 0
    jne ev_bad
    mov qword ptr [rip + ev_stage], 2
    mov qword ptr [rip + ev_block], 0
    call ev_request
    cmp rax, 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_NEED_CLOSE
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 8], 1
    jne ev_bad
    mov qword ptr [rip + ev_stage], 3
    mov qword ptr [rip + ev_block], 1
    call ev_request
    cmp rax, 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_NEED_OPEN
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 8], 1
    jne ev_bad
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 1
    jne ev_bad
    mov qword ptr [rip + ev_stage], 4
    mov qword ptr [rip + ev_block], 2
    call ev_request
    cmp rax, 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_POSITIONS
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 8], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 1
    jne ev_bad
    mov qword ptr [rip + ev_stage], 5
    call ev_edit
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 40], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 56], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 1
    jne ev_bad
    mov qword ptr [rip + ev_stage], 6
    mov qword ptr [rip + ev_block], 3
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 24], 1
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_POSITIONS
    jne ev_bad
    call ev_edit
    mov rdi, rbx
    call ext_note_resync
    mov rdi, rbx
    call ext_edits_clear
    cmp dword ptr [rbx + DOC_xresync], 0
    jne ev_bad
    call ev_known
    cmp qword ptr [rax + XK_resync], 1
    jne ev_bad
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 48], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 56], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 24], 1
    jne ev_bad
    call ev_known
    cmp qword ptr [rax + XK_resync], 0
    jne ev_bad
    mov qword ptr [rip + ev_stage], 7
    mov qword ptr [rip + ev_block], 4
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 24], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 32], 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_POSITIONS
    jne ev_bad
    mov qword ptr [rip + ev_stage], 8
    mov qword ptr [rip + ev_block], 9
    call ev_request
    cmp rax, 0
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_READY
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 32], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 0
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_hreq], 1
    jne ev_bad
    mov qword ptr [rip + ev_block], -1
    call ev_request
    cmp rax, 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 1
    jne ev_bad
    mov qword ptr [rip + ev_stage], 9
    call ev_edit
    mov qword ptr [rip + ev_ext + EXT_active], -1
    mov qword ptr [rip + ev_block], 5
    call ev_request
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 1
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 2
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_hreq], 2
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_active], -1
    jne ev_bad
    mov qword ptr [rip + ev_block], -1
    call ev_request
    cmp rax, 3
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 40], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 56], 3
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 2
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 16], 3
    jne ev_bad
    # No edit subscription: full snapshots cover edit offsets, ranges do not.
    mov qword ptr [rip + ev_stage], 13
    mov qword ptr [rip + ev_ext + EXT_sub_edits], 0
    mov dword ptr [rip + ev_ext + EXT_needs], NEEDS_DOC_READ
    mov dword ptr [rip + ev_ext + EXT_hello], 1
    mov dword ptr [rip + ev_ext + EXT_out], -1
    call ev_edit
    call ev_events
    test rax, rax
    jnz ev_bad
    call ev_known
    mov rcx, [rax + XK_eoff]
    mov [rip + ev_saved_off], rcx
    mov rdx, [rbx + DOC_xedits]
    cmp rcx, [rdx + SB_len]
    jae ev_bad
    mov qword ptr [rip + ev_block], 9
    lea rdi, [rip + ev_text_request]
    lea rsi, [rip + ev_text_reply]
    call ev_receive
    call ev_known
    mov rcx, [rip + ev_saved_off]
    cmp [rax + XK_eoff], rcx
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 2
    jne ev_bad
    mov qword ptr [rip + ev_stage], 14
    mov qword ptr [rip + ev_block], -1
    lea rdi, [rip + ev_range_request]
    lea rsi, [rip + ev_range_reply]
    call ev_receive
    call ev_known
    mov rcx, [rip + ev_saved_off]
    cmp [rax + XK_eoff], rcx
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 3
    jne ev_bad
    mov qword ptr [rip + ev_stage], 15
    lea rdi, [rip + ev_text2_request]
    lea rsi, [rip + ev_text2_reply]
    call ev_receive
    call ev_known
    mov rdx, [rbx + DOC_xedits]
    mov rcx, [rdx + SB_len]
    cmp [rax + XK_eoff], rcx
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 72], 4
    jne ev_bad
    mov qword ptr [rip + ev_stage], 10
    mov qword ptr [rip + g_tabs + VEC_len], 0
    mov qword ptr [rip + ev_block], 0
    call ev_events
    cmp rax, -11
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 1
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_known + VEC_len], 1
    jne ev_bad
    mov qword ptr [rip + ev_block], -1
    call ev_events
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 2
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_known + VEC_len], 0
    jne ev_bad
    mov qword ptr [rip + ev_stage], 11
    mov qword ptr [rip + g_tabs + VEC_len], 1
    mov qword ptr [rip + ev_block], 1
    call ev_events
    cmp rax, -11
    jne ev_bad
    call ev_known
    test rax, rax
    jz ev_bad
    cmp qword ptr [rax + XK_phase], XP_NEED_OPEN
    jne ev_bad
    mov qword ptr [rip + g_tabs + VEC_len], 0
    call ev_events
    cmp rax, 0
    jne ev_bad
    cmp qword ptr [rip + ev_counts + 0], 2
    jne ev_bad
    cmp qword ptr [rip + ev_ext + EXT_known + VEC_len], 0
    jne ev_bad
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_tabs + VEC_ptr], 0
    mov qword ptr [rip + g_doc], 0
    mov dword ptr [rip + g_ext_hooks], 0
    mov rdi, rbx
    call doc_free
    lea rdi, [rip + ev_ext + EXT_known]
    call vec_free
    lea rdi, [rip + ev_ext + EXT_rbuf]
    call sb_free
    call ext_events_output_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + ev_live]
    jne ev_bad
    lea rdi, [rip + ev_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + ev_ok]
    call write_all
    xor eax, eax
    EPILOGUE
# Ordinary test linking supplies this fixture-only cleanup; focused driver replaces its body.
FN ext_events_output_free
    ret
.section .rodata
.p2align 3
ev_prefixes: .quad ev_closed, ev_opened, ev_active, ev_cursor, ev_selection, ev_edits, ev_resync, ev_changed, ev_saved
ev_closed: .asciz "0 closed "
ev_opened: .asciz "0 opened "
ev_active: .asciz "0 active "
ev_cursor: .asciz "0 cursor "
ev_selection: .asciz "0 selection "
ev_edits: .asciz "0 edits "
ev_resync: .asciz "0 resync "
ev_changed: .asciz "0 changed "
ev_saved: .asciz "0 saved "
ev_text_request: .asciz "41 text 1\n"
ev_text_reply: .asciz "ok 41 4 4\nxxxx"
ev_range_request: .asciz "42 range 1 1 1 1 2\n"
ev_range_reply: .asciz "ok 42 4 1\nx"
ev_text2_request: .asciz "43 text 1\n"
ev_text2_reply: .asciz "ok 43 4 4\nxxxx"
ev_star: .asciz "*"
ev_byte: .ascii "x"
ev_verb: .asciz "complete"
ev_kind: .asciz "invoke"
ev_newline: .ascii "\n"
ev_ok: .ascii "ok extension event prefixes, retries, lifecycle, resync debt and request authority\n"
ev_ok_end: .byte 0
.data
.p2align 3
ev_grammar: .quad ev_name
    .zero GR_SIZE - 8
ev_name: .asciz "New"

