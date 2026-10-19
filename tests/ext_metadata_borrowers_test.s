# Hidden suppliers must be rejected before any borrowed metadata or document is read.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.section .rodata
borrow_owner: .asciz "owner"
borrow_name: .asciz "name"
borrow_message: .asciz "retained message"
.bss
.p2align 3
borrow_host: .zero EXT_SIZE
borrow_copy: .zero EXT_SIZE
borrow_doc: .zero DOC_SIZE
borrow_cmd: .zero CMD_SIZE
borrow_owner_index: .quad 0
borrow_marks: .zero VEC_SIZE
borrow_mark: .zero 2 * MK_SIZE
borrow_visible_host: .zero EXT_SIZE
borrow_lines: .quad 0
borrow_edits: .zero SB_SIZE
borrow_live: .quad 0
borrow_charge: .quad 0
.text
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + borrow_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + borrow_charge], rax
    lea rbx, [rip + borrow_host]
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    mov dword ptr [rbx + EXT_catalog_state], 2
    mov dword ptr [rbx + EXT_features], -1
    mov dword ptr [rbx + EXT_needs], -1
    mov dword ptr [rbx + EXT_manifest_ok], 1
    mov dword ptr [rbx + EXT_pinned], 1
    mov qword ptr [rbx + EXT_identity_owner], 1
    mov qword ptr [rbx + EXT_metadata_owner], 1
    mov qword ptr [rbx + EXT_owner], 1
    mov qword ptr [rbx + EXT_name], 1
    mov qword ptr [rbx + EXT_title], 1
    mov qword ptr [rbx + EXT_dir], 1
    mov qword ptr [rbx + EXT_icon], 1
    mov qword ptr [rbx + EXT_pv_complete], 1
    mov qword ptr [rbx + EXT_pv_signature], 1
    mov qword ptr [rbx + EXT_pv_definition], 1
    mov qword ptr [rbx + EXT_sub_hover], 1
    mov qword ptr [rbx + EXT_sub_edits], 1
    mov qword ptr [rbx + EXT_sdefs + VEC_ptr], 1
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 1
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov qword ptr [rip + g_exts + VEC_cap], 1
    lea rax, [rip + borrow_cmd]
    mov [rip + g_ext_cmds + VEC_ptr], rax
    mov qword ptr [rip + g_ext_cmds + VEC_len], 1
    lea rax, [rip + borrow_owner_index]
    mov [rip + g_ext_owner + VEC_ptr], rax
    mov qword ptr [rip + g_ext_owner + VEC_len], 1
    lea rdi, [rip + borrow_copy]
    mov rsi, rbx
    mov edx, EXT_SIZE
    call memcpy
    mov r15d, 1
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call ext_provider_supports
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 16
    call ext_icon
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    call ext_icon_state
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    call extwatch_add
    cmp rax, -13
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    call extproto_events
    cmp rax, -32
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    call extproto_doc_ready
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    mov ecx, 1
    mov r8d, 1
    call extproto_host_request
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    mov ecx, 1
    call extproto_host_send
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call extproto_watch_event
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    call ext_start
    cmp rax, -116
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    xor esi, esi
    call ext_cmd_index_owned
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    xor esi, esi
    call ext_pending_set
    cmp rax, -32
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    call ext_pending_new
    test rax, rax
    jnz borrow_bad
    cmp rdx, -22
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    call ext_pending_resolve
    cmp rax, -2
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov edi, 1
    mov rsi, rbx
    mov edx, 1
    call ext_pending_matches
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    lea r12, [rip + borrow_doc]
    mov [r12 + DOC_oown], rbx
    mov qword ptr [r12 + DOC_oval], 99
    mov rdi, r12
    xor esi, esi
    call ext_doc_option
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    lea rax, [rip + borrow_marks]
    mov [r12 + DOC_xmarks], rax
    lea rcx, [rip + borrow_mark]
    mov [rax + VEC_ptr], rcx
    mov qword ptr [rax + VEC_len], 1
    mov [rcx + MK_owner], rbx
    mov qword ptr [rcx + MK_start], 0
    mov qword ptr [rcx + MK_end], 10
    mov dword ptr [rcx + MK_sev], SEV_ERROR
    lea rax, [rip + borrow_message]
    mov [rcx + MK_msg], rax
    mov rdi, r12
    call extmarks_counts
    or eax, edx
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, r12
    mov esi, 1
    call extmarks_at
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    call ext_hooks_update
    cmp dword ptr [rip + g_ext_hooks], 0
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    lea rdi, [rip + borrow_name]
    mov esi, 4
    call ext_by_name
    test rax, rax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    call extbar_count
    cmp eax, 1
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    xor edi, edi
    call ext_cmd_live
    test eax, eax
    jnz borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    xor esi, esi
    call ext_set_pinned
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    call ext_set_disabled
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    call ext_remove_ask
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call extview_open
    cmp rax, -1
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    call extproto_send_action
    call borrow_unchanged
    inc r15d
    call extproto_send_project_all
    call borrow_unchanged
    inc r15d
    mov edi, 1
    mov esi, 1
    call extproto_send_hover_all
    call borrow_unchanged
    # Retained hidden marks must still follow insertions and deletions.
    inc r15d
    lea rax, [rip + borrow_edits]
    mov [r12 + DOC_xedits], rax
    mov dword ptr [r12 + DOC_xresync], 1
    mov dword ptr [rip + g_ext_hooks], 1
    mov qword ptr [rip + borrow_marks + VEC_len], 2
    lea r14, [rip + borrow_mark]
    mov [r14 + MK_SIZE + MK_owner], rbx
    mov qword ptr [r14 + MK_SIZE + MK_start], 4
    mov qword ptr [r14 + MK_SIZE + MK_end], 4
    mov rdi, r12
    mov esi, 1
    mov edx, 1
    mov ecx, 3
    call ext_note_insert
    cmp qword ptr [r14 + MK_start], 0
    jne borrow_bad
    cmp qword ptr [r14 + MK_end], 13
    jne borrow_bad
    cmp qword ptr [r14 + MK_SIZE + MK_start], 7
    jne borrow_bad
    cmp qword ptr [r14 + MK_SIZE + MK_end], 7
    jne borrow_bad
    call borrow_unchanged
    inc r15d
    mov rdi, r12
    mov esi, 1
    mov edx, 3
    call ext_note_delete
    cmp qword ptr [r14 + MK_start], 0
    jne borrow_bad
    cmp qword ptr [r14 + MK_end], 10
    jne borrow_bad
    cmp qword ptr [r14 + MK_SIZE + MK_start], 4
    jne borrow_bad
    cmp qword ptr [r14 + MK_SIZE + MK_end], 4
    jne borrow_bad
    mov dword ptr [rip + g_ext_hooks], 0
    mov qword ptr [rip + borrow_marks + VEC_len], 1
    call borrow_unchanged
    # Drawing filters hidden diagnostics, without changing the retained records.
    inc r15d
    lea rax, [rip + borrow_lines]
    mov [r12 + DOC_lines], rax
    mov qword ptr [r12 + DOC_nlines], 1
    mov rdi, r12
    xor esi, esi
    call extmarks_line
    cmp eax, -1
    jne borrow_bad
    call borrow_unchanged
    # Visible legacy compatibility supplies the positive display/count cases.
    inc r15d
    lea r13, [rip + borrow_visible_host]
    mov dword ptr [r13 + EXT_status], ES_RUNNING
    mov dword ptr [r13 + EXT_pinned], 1
    mov [rip + g_exts + VEC_ptr], r13
    call extbar_count
    cmp eax, 2
    jne borrow_bad
    mov [r14 + MK_owner], r13
    mov rdi, r12
    xor esi, esi
    call extmarks_line
    cmp eax, SEV_ERROR
    jne borrow_bad
    mov rdi, r12
    call extmarks_counts
    cmp eax, 1
    jne borrow_bad
    test edx, edx
    jnz borrow_bad
    mov rdi, r12
    mov esi, 1
    call extmarks_at
    lea rcx, [rip + borrow_message]
    cmp rax, rcx
    jne borrow_bad
    mov [rip + g_exts + VEC_ptr], rbx
    mov [r14 + MK_owner], rbx
    call borrow_unchanged
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + borrow_live]
    jne borrow_bad
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + borrow_charge]
    jne borrow_bad
    xor eax, eax
    EPILOGUE
borrow_unchanged:
    PROLOGUE
    mov rdi, rbx
    lea rsi, [rip + borrow_copy]
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz borrow_bad
    EPILOGUE
borrow_bad:
    mov edi, r15d
    SYS SYS_exit_group
