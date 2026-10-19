# Managed saves. One automatic participant runs at a time; callbacks own stable IDs.
.include "rhun.inc"

.equ SJ_MAX, 256
.equ ST_MAX, 32
STRUCT
F SJ_next, 8
F SJ_doc, 8
F SJ_id, 8
F SJ_path, 8
F SJ_flags, 8
F SJ_state, 8                  # 0 queued, 1 starting, 2 waiting, 3 commit, 4 reply
F SJ_deadline, 8
F SJ_ext, 8
F SJ_request, 8
F SJ_version, 8
F SJ_body, 8
F SJ_len, 8
F SJ_warning, 8
F SJ_tickets, 8
F SJ_ntickets, 8
F SJ_phase, 8                  # 0 source not initialized, 1 source actions, 2 formatting
F SJ_source, 8                 # owned source-phase snapshot, or 0
F SJ_language_revision, 8
ENDSTRUCT SJ_SIZE
STRUCT
F SS_text, 8
F SS_end, 8
F SS_kind, 8
F SS_index, 8
F SS_count, 8
F SS_providers, 16*EXT_CAP      # EXT pointer and owned qualified identity per entry
ENDSTRUCT SS_SIZE
STRUCT
F ST_next, 8
F ST_fn, 8
F ST_arg, 8
F ST_intent, 8                 # latest effectful intent wins; observers run first
ENDSTRUCT ST_SIZE

.bss
.p2align 3
save_head: .quad 0
save_tail: .quad 0
save_count: .quad 0
save_line: .zero SB_SIZE

.text
# save_start(doc, flags, fn, arg): 0 saved, negative error, 1 queued.
# Callback(id, arg, result) only for pending completion. Caller owns arg on synchronous return.
FN save_start
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    test rbx, rbx
    jz .Lss_error
    cmp qword ptr [rbx + DOC_path], 0
    je .Lss_error
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lss_error
    mov r15, [rip + save_head]
1:  test r15, r15
    jz 3f
    cmp [r15 + SJ_doc], rbx
    jne 2f
    mov rax, [rbx + DOC_id]
    cmp [r15 + SJ_id], rax
    je 5f
2:  mov r15, [r15 + SJ_next]
    jmp 1b
3:  cmp qword ptr [rip + save_head], 0
    jne 4f
    test r12d, SAVE_BYPASS
    jnz 31f
    cmp dword ptr [rip + cfg_format_on_save], 0
    jne 4f
    mov rax, [rip + cfg_save_actions]
    cmp byte ptr [rax], 0
    jne 4f
31: mov rdi, rbx
    mov rsi, r12
    call save_commit
    EPILOGUE
4:  cmp qword ptr [rip + save_count], SJ_MAX
    jae .Lss_error
    mov edi, SJ_SIZE
    call mem_alloc
    mov r15, rax
    mov [rax + SJ_doc], rbx
    mov rcx, [rbx + DOC_id]
    mov [rax + SJ_id], rcx
    mov [rax + SJ_flags], r12
    mov rdi, [rbx + DOC_path]
    call strlen
    mov rdi, [rbx + DOC_path]
    mov rsi, rax
    call mem_dup
    mov [r15 + SJ_path], rax
    mov rax, [rip + save_tail]
    test rax, rax
    jz 41f
    mov [rax + SJ_next], r15
    jmp 42f
41: mov [rip + save_head], r15
42: mov [rip + save_tail], r15
    inc qword ptr [rip + save_count]
5:  # Add each owned callback once. No callback means an ordinary coalesced Save.
    test r13, r13
    jz 7f
    mov rbx, [r15 + SJ_tickets]
    xor eax, eax
51: test rbx, rbx
    jz 6f
    cmp [rbx + ST_fn], r13
    jne 52f
    cmp [rbx + ST_arg], r14
    je 7f
52: mov rbx, [rbx + ST_next]
    jmp 51b
6:  cmp qword ptr [r15 + SJ_ntickets], ST_MAX
    jae .Lss_error
    mov edi, ST_SIZE
    call mem_alloc
    mov [rax + ST_fn], r13
    mov [rax + ST_arg], r14
    mov rcx, r12
    and ecx, SAVE_INTENT
    mov [rax + ST_intent], rcx
    mov rcx, [r15 + SJ_tickets]
    mov [rax + ST_next], rcx
    mov [r15 + SJ_tickets], rax
    inc qword ptr [r15 + SJ_ntickets]
7:  or [r15 + SJ_flags], r12
    test r12d, SAVE_BYPASS
    jz 8f
    mov rdi, r15
    call save_cancel_request
    mov qword ptr [r15 + SJ_state], 3
8:  mov eax, 1
    EPILOGUE
.Lss_error:
    lea rdi, [rip + .Lfailed]
    call app_toast
    mov rax, -1
    EPILOGUE

# Actual write, with permission checked at commit time. Exactly one after-save notification.
save_commit:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12d, SAVE_READONLY
    jnz 1f
    call doc_readonly
    test eax, eax
    jnz 4f
    mov rdi, rbx
    call doc_save
    jmp 2f
1:  mov rdi, rbx
    call doc_save_readonly
2:  test rax, rax
    js 4f
    mov rdi, rbx
    call app_after_save
    call app_update_title
    xor eax, eax
    EPILOGUE
4:  lea rdi, [rip + .Lfailed]
    call app_toast
    mov rax, -1
    EPILOGUE

# Only the head can own a request. Clearing the ID also makes late responses harmless.
save_cancel_request:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + SJ_request]
    test rsi, rsi
    jz 1f
    mov qword ptr [rbx + SJ_request], 0
    mov rdi, [rbx + SJ_ext]
    call extproto_send_cancel
1:  EPILOGUE

# Remove and free the job BEFORE callbacks, which may close documents or enqueue saves.
# save_finish(job, result), job must be head.
save_finish:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov rax, [rbx + SJ_next]
    mov [rip + save_head], rax
    test rax, rax
    jnz 1f
    mov qword ptr [rip + save_tail], 0
1:  dec qword ptr [rip + save_count]
    mov rax, [rbx + SJ_id]
    mov [rsp + 8], rax
    mov r12, [rbx + SJ_tickets]
    xor r13d, r13d              # newest intent (list is newest first)
    mov rax, r12
2:  test rax, rax
    jz 3f
    cmp qword ptr [rax + ST_intent], 0
    jne 21f
    mov rax, [rax + ST_next]
    jmp 2b
21: mov r13, rax
3:  mov rdi, [rbx + SJ_body]
    call mem_free
    mov rdi, rbx
    call save_source_free
    mov rdi, [rbx + SJ_path]
    call mem_free
    mov rdi, rbx
    call mem_free
    # Observers and superseded intents run first. The winning close/quit runs last.
4:  test r12, r12
    jz 7f
    mov r14, [r12 + ST_next]
    cmp r12, r13
    je 6f
    mov rdx, [rsp]
    test rdx, rdx
    jnz 5f
    cmp qword ptr [r12 + ST_intent], 0
    je 5f
    mov rdx, SAVE_SUPERSEDED
5:  mov rdi, [rsp + 8]
    mov rsi, [r12 + ST_arg]
    call [r12 + ST_fn]
    mov rdi, r12
    call mem_free
6:  mov r12, r14
    jmp 4b
7:  test r13, r13
    jz 8f
    mov rdi, [rsp + 8]
    mov rsi, [r13 + ST_arg]
    mov rdx, [rsp]
    call [r13 + ST_fn]
    mov rdi, r13
    call mem_free
8:  EPILOGUE

# save_reply(ext, request, ok, body, len) -> consumed. IO pump only copies the result.
FN save_reply
    PROLOGUE 32
    mov [rsp], edx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    mov rbx, [rip + save_head]
    test rbx, rbx
    jz 8f
    cmp qword ptr [rbx + SJ_state], 2
    jne 8f
    cmp [rbx + SJ_ext], rdi
    jne 8f
    cmp [rbx + SJ_request], rsi
    jne 8f
    mov qword ptr [rbx + SJ_request], 0
    call ext_is_visible
    test eax, eax
    jz 7f
    mov rdi, [rbx + SJ_id]
    call extproto_doc
    test rax, rax
    jz 7f
    cmp rax, [rbx + SJ_doc]
    jne 7f
    mov rdi, rax
    mov rsi, [rbx + SJ_language_revision]
    call doc_language_matches
    test eax, eax
    jnz 6f
    mov qword ptr [rbx + SJ_state], 3
    jmp 9f
6:  mov edx, [rsp]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    test edx, edx
    jz 7f
    cmp r8, 4194304
    ja 7f
    mov r12, r8
    mov rdi, rcx
    mov rsi, r8
    call mem_dup
    mov [rbx + SJ_body], rax
    mov [rbx + SJ_len], r12
    mov qword ptr [rbx + SJ_state], 4
    jmp 9f
7:  lea rax, [rip + .Lformat_failed]
    cmp qword ptr [rbx + SJ_phase], 1
    jne 71f
    lea rax, [rip + .Lsource_failed]
    mov [rbx + SJ_warning], rax
    mov qword ptr [rbx + SJ_state], 5
    jmp 9f
71:
    mov [rbx + SJ_warning], rax
    mov qword ptr [rbx + SJ_state], 3
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

FN save_tick
    PROLOGUE
    mov rbx, [rip + save_head]
    test rbx, rbx
    jz .Lst_done
    mov rdi, [rbx + SJ_id]
    call extproto_doc
    test rax, rax
    jz .Lst_cancel
    cmp rax, [rbx + SJ_doc]
    jne .Lst_cancel
    mov r12, rax
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz .Lst_cancel
    mov rsi, [rbx + SJ_path]
    call strcmp_eq
    test eax, eax
    jz .Lst_cancel
    cmp qword ptr [rbx + SJ_language_revision], 0
    jne .Lst_language_check
    mov rdi, r12
    call doc_sync_grammar
    test rax, rax
    js .Lst_language_stale
    mov rax, [r12 + DOC_language_revision]
    test rax, rax
    jz .Lst_language_stale
    mov [rbx + SJ_language_revision], rax
.Lst_language_check:
    mov rdi, r12
    mov rsi, [rbx + SJ_language_revision]
    call doc_language_matches
    test eax, eax
    jnz .Lst_language_ready
.Lst_language_stale:
    mov rdi, rbx
    call save_cancel_request
    jmp .Lst_commit
.Lst_language_ready:
    cmp qword ptr [rbx + SJ_phase], 2
    jae 91f
    test qword ptr [rbx + SJ_flags], SAVE_BYPASS
    jnz .Lst_commit
    mov rdi, rbx
    mov rsi, r12
    call save_source_tick
    test eax, eax
    jnz .Lst_done
91:
    mov rax, [rbx + SJ_state]
    cmp rax, 3
    je .Lst_commit
    cmp rax, 4
    je .Lst_apply
    test rax, rax
    jnz .Lst_wait
    test qword ptr [rbx + SJ_flags], SAVE_BYPASS
    jnz .Lst_commit
    cmp dword ptr [rip + cfg_format_on_save], 0
    je .Lst_commit
    call time_ms
    mov ecx, [rip + cfg_format_save_timeout]
    add rax, rcx
    mov [rbx + SJ_deadline], rax
    mov edi, 6
    mov rsi, r12
    call ext_provider_automatic
    test rax, rax
    jnz 1f
    test edx, edx
    jz .Lst_commit
    lea rax, [rip + .Lchoose]
    mov [rbx + SJ_warning], rax
    jmp .Lst_commit
1:  mov [rbx + SJ_ext], rax
    mov qword ptr [rbx + SJ_state], 1
    mov rdi, rax
    call ext_start
    lea rdi, [rip + .Lformatting]
    call app_toast
.Lst_wait:
    call time_ms
    cmp rax, [rbx + SJ_deadline]
    jae .Lst_timeout
    mov r13, [rbx + SJ_ext]
    mov eax, [r13 + EXT_status]
    cmp eax, ES_STARTING
    je .Lst_done
    cmp eax, ES_IDLE          # includes a provider waiting for a shared process slot
    je .Lst_done
    cmp eax, ES_RUNNING
    jne .Lst_failed
    cmp qword ptr [rbx + SJ_state], 2
    je .Lst_done
    mov rdi, r13
    mov esi, 6
    mov rdx, r12
    call ext_provider_supports
    test eax, eax
    jz .Lst_failed
    lea rdi, [rip + save_line]
    call sb_clear
    lea rdi, [rip + save_line]
    lea rsi, [rip + .Lformat]
    call sb_push_cstr
    lea rdi, [rip + save_line]
    mov rsi, [r12 + DOC_id]
    call sb_push_u64
    call save_space
    lea rdi, [rip + save_line]
    mov rsi, [r12 + DOC_version]
    mov [rbx + SJ_version], rsi
    call sb_push_u64
    call save_space
    # Formatting uses the target document's options, even when another tab is active.
    lea rdi, [rip + save_line]
    mov rsi, r12
    call save_tab_width
    call sb_push_u64
    call save_space
    lea rdi, [rip + save_line]
    mov rsi, r12
    call save_spaces
    call sb_push_cstr
    mov rdi, r13
    mov rsi, r12
    mov rdx, [rip + save_line + SB_ptr]
    mov rcx, [rip + save_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz .Lst_failed
    mov [rbx + SJ_request], rax
    mov qword ptr [rbx + SJ_state], 2
    jmp .Lst_done
.Lst_apply:
    mov rax, [r12 + DOC_version]
    cmp rax, [rbx + SJ_version]
    jne .Lst_commit            # never overwrite edits typed during formatting
    cmp qword ptr [rbx + SJ_len], 0
    je .Lst_commit             # a valid empty provider reply means no changes
    mov rdi, [rbx + SJ_body]
    mov rsi, [rbx + SJ_len]
    mov rdx, [rbx + SJ_id]
    mov ecx, 1
    call ws_apply_document
    test eax, eax
    jnz .Lst_commit
    lea rax, [rip + .Lformat_failed]
    mov [rbx + SJ_warning], rax
    jmp .Lst_commit
.Lst_timeout:
    lea rax, [rip + .Ltimed_out]
    mov [rbx + SJ_warning], rax
    mov rdi, rbx
    call save_cancel_request
    jmp .Lst_commit
.Lst_failed:
    lea rax, [rip + .Lformat_failed]
    mov [rbx + SJ_warning], rax
.Lst_commit:
    mov rdi, r12
    mov rsi, [rbx + SJ_flags]
    call save_commit
    mov r13, rax
    test rax, rax
    js 2f
    mov rdi, [rbx + SJ_warning]
    test rdi, rdi
    jz 2f
    call app_toast
2:  mov rdi, rbx
    mov rsi, r13
    call save_finish
    jmp .Lst_done
.Lst_cancel:
    mov rdi, rbx
    call save_cancel_request
    mov rdi, rbx
    mov rsi, SAVE_CANCELLED
    call save_finish
.Lst_done:
    EPILOGUE

save_space:
    lea rdi, [rip + save_line]
    mov esi, ' '
    jmp sb_push_byte

# Option overrides are stored in the document's resolved option vector (ext options included).
save_tab_width:
    push rdi
    push rcx
    push rdx
    mov rdi, rsi
    mov esi, OPT_TAB
    call ext_doc_option
    pop rdx
    pop rcx
    pop rdi
    mov esi, [rip + cfg_tab_width]
    test eax, eax
    jz 1f
    mov esi, eax
1:
    ret
save_spaces:
    push rdi
    push rcx
    push rdx
    mov rdi, rsi
    mov esi, OPT_SPACES
    call ext_doc_option
    pop rdx
    pop rcx
    pop rdi
    lea rsi, [rip + .Lyes]
    cmp eax, 2
    je 1f
    cmp eax, 1
    je 2f
    cmp dword ptr [rip + cfg_insert_spaces], 0
    jne 1f
2:  lea rsi, [rip + .Lno]
1:  ret

FN save_timeout
    cmp qword ptr [rip + save_head], 0
    je 1f
    mov eax, 10
    ret
1:  mov eax, -1
    ret

# Cancel all jobs for an existing document. Move each to head before the common detach path.
FN save_forget
    PROLOGUE
    mov r12, rdi
1:  mov rbx, [rip + save_head]
    xor r13d, r13d
2:  test rbx, rbx
    jz 9f
    cmp [rbx + SJ_doc], r12
    je 3f
    mov r13, rbx
    mov rbx, [rbx + SJ_next]
    jmp 2b
3:  test r13, r13
    jz 5f
    mov rax, [rbx + SJ_next]
    mov [r13 + SJ_next], rax
    cmp rbx, [rip + save_tail]
    jne 4f
    mov [rip + save_tail], r13
4:  mov rax, [rip + save_head]
    mov [rbx + SJ_next], rax
    mov [rip + save_head], rbx
5:  mov rdi, rbx
    call save_cancel_request
    mov rdi, rbx
    mov rsi, SAVE_CANCELLED
    call save_finish
    jmp 1b
9:  EPILOGUE

FN cmd_cancel_save
    PROLOGUE
    mov rdi, [rip + g_doc]
    call save_forget
    lea rdi, [rip + .Lcancelled]
    call app_toast
    EPILOGUE

# Editor Escape is consumed only when this document has a pending save.
FN save_cancel_key
    mov rax, [rip + save_head]
1:  test rax, rax
    jz 2f
    cmp [rax + SJ_doc], rdi
    je 3f
    mov rax, [rax + SJ_next]
    jmp 1b
3:  push rbx
    call save_forget
    mov eax, 1
    pop rbx
2:  ret

# app_doc_tab(id) -> current index, or -1. No index crosses an async boundary.
FN app_doc_tab
    xor ecx, ecx
1:  cmp rcx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rcx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc rcx
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    je 2f
    cmp qword ptr [rax + TAB_kind], TAB_NOTEBOOK
    jne 1b
2:  mov rax, [rax + TAB_doc]
    cmp [rax + DOC_id], rdi
    jne 1b
    lea rax, [rcx - 1]
    ret
8:  mov rax, -1
    ret

# Save All captures document IDs once, then submits one save at a time. A newer close/quit/all
# operation invalidates this observer's epoch; its callback then only releases the context.
.equ SA_ids, 0
.equ SA_pos, VEC_SIZE
.equ SA_epoch, VEC_SIZE + 8
.equ SA_quit, VEC_SIZE + 16
.equ SA_readonly, VEC_SIZE + 24
.equ SA_SIZE, VEC_SIZE + 32
FN app_save_all
    PROLOGUE
    mov r13d, edi
    inc qword ptr [rip + app_save_epoch]
    mov edi, SA_SIZE
    call mem_alloc
    mov r12, rax
    mov rax, [rip + app_save_epoch]
    mov [r12 + SA_epoch], rax
    mov [r12 + SA_quit], r13
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, rbx
    call tab_at
    inc rbx
    cmp qword ptr [rax + TAB_kind], TAB_NOTEBOOK     # notebooks save too
    jne 11f
    mov r14, [rax + TAB_doc]
    mov rdi, [r14 + DOC_nb]
    call nb_sync_dirty
    jmp 12f
11: cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r14, [rax + TAB_doc]
    test dword ptr [r14 + DOC_flags], DF_READONLY
    jnz 1b
    cmp qword ptr [r14 + DOC_path], 0
    je 1b
    mov rdi, r14
    call doc_dirty
12: test eax, eax
    jz 1b
    mov rdi, r14
    call doc_readonly
    test eax, eax
    jz 2f
    mov qword ptr [r12 + SA_readonly], 1
    jmp 1b
2:  lea rdi, [r12 + SA_ids]
    mov esi, 8
    call vec_push
    mov rcx, [r14 + DOC_id]
    mov [rax], rcx
    jmp 1b
3:  mov rdi, r12
    call save_all_step
    EPILOGUE

save_all_completed:
    mov rdi, rsi
    test rdx, rdx
    jnz save_all_free
    jmp save_all_step

save_all_step:
    PROLOGUE
    mov rbx, rdi
1:  mov rax, [rbx + SA_epoch]
    cmp rax, [rip + app_save_epoch]
    jne 8f
    mov rax, [rbx + SA_pos]
    cmp rax, [rbx + SA_ids + VEC_len]
    jae 7f
    inc qword ptr [rbx + SA_pos]
    mov rcx, [rbx + SA_ids + VEC_ptr]
    mov rdi, [rcx + rax*8]
    call app_doc_by_id
    test rax, rax
    jz 1b
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + save_all_completed]
    mov rcx, rbx
    call app_save_start
    test rax, rax
    jz 1b
    cmp rax, 1
    je 9f
    jmp 8f
7:  mov r12, [rbx + SA_quit]
    cmp qword ptr [rbx + SA_readonly], 0
    je 71f
    lea rdi, [rip + .Lreadonly_left]
    call app_toast
71: mov rdi, rbx
    call save_all_free
    test r12, r12
    jz 9f
    call cmd_quit
    jmp 9f
8:  mov rdi, rbx
    call save_all_free
9:  EPILOGUE

save_all_free:
    push rbx
    mov rbx, rdi
    lea rdi, [rbx + SA_ids]
    call vec_free
    mov rdi, rbx
    call mem_free
    pop rbx
    ret

FN cmd_save_all
    xor edi, edi
    jmp app_save_all

.section .rodata
.Lfailed: .asciz "Could not save the file"
.Lformat: .asciz "format "
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.Lformatting: .asciz "Formatting before saving..."
.Lformat_failed: .asciz "Saved. Formatting failed"
.Ltimed_out: .asciz "Saved. Formatting timed out"
.Lchoose: .asciz "Saved. Choose an available default formatter"
.Lcancelled: .asciz "Save cancelled"
.Lreadonly_left: .asciz "Read-only files were not saved (:w asks to overwrite)"

.text
# Validate the whole candidate before replacing a setting. Return an owned normalized string.
FN save_actions_config
    PROLOGUE 560
    mov r12, rdi
    mov r13, rsi
    cmp rsi, 4096
    ja .Lsac_bad
    xor ebx, ebx               # input offset
    xor r14d, r14d             # candidate count
.Lsac_token:
    cmp rbx, r13
    jae .Lsac_normalize
    movzx eax, byte ptr [r12 + rbx]
    cmp al, ' '
    je .Lsac_space
    cmp al, 9
    je .Lsac_space
    cmp r14, 32
    jae .Lsac_bad
    lea rdi, [r12 + rbx]
    mov [rsp + 512], rdi
    mov r15, rbx
1:  cmp rbx, r13
    jae 2f
    mov al, [r12 + rbx]
    cmp al, ' '
    je 2f
    cmp al, 9
    je 2f
    inc rbx
    jmp 1b
2:  mov rsi, rbx
    sub rsi, r15
    mov [rsp + 520], rsi
    mov rdi, [rsp + 512]
    call save_source_kind
    test eax, eax
    jz .Lsac_bad
    mov rcx, r14
    shl rcx, 4
    mov rax, [rsp + 512]
    mov [rsp + rcx], rax
    mov rax, [rsp + 520]
    mov [rsp + rcx + 8], rax
    inc r14
    jmp .Lsac_token
.Lsac_space:
    inc rbx
    jmp .Lsac_token
.Lsac_normalize:
    lea rdi, [rsp + 528]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    xor ebx, ebx
.Lsac_candidate:
    cmp rbx, r14
    jae .Lsac_result
    mov rax, rbx
    shl rax, 4
    mov r12, [rsp + rax]
    mov r13, [rsp + rax + 8]
    xor r15d, r15d
.Lsac_ancestor:
    cmp r15, r14
    jae .Lsac_emit
    cmp r15, rbx
    je 3f
    mov rcx, r15
    shl rcx, 4
    mov rdx, [rsp + rcx + 8]
    cmp rdx, r13
    ja 3f
    jb 4f
    cmp r15, rbx               # equal kinds: keep the first
    ja 3f
4:  mov rdi, [rsp + rcx]
    mov rsi, rdx
    mov rdx, r12
    mov rcx, rsi
    call str_eq
    test eax, eax
    jz 3f
    mov rax, r15
    shl rax, 4
    mov rcx, [rsp + rax + 8]
    cmp rcx, r13
    je .Lsac_skip
    cmp byte ptr [r12 + rcx], '.'
    je .Lsac_skip
3:  inc r15
    jmp .Lsac_ancestor
.Lsac_emit:
    cmp qword ptr [rsp + 528 + SB_len], 0
    je 5f
    lea rdi, [rsp + 528]
    mov esi, ' '
    call sb_push_byte
5:  lea rdi, [rsp + 528]
    mov rsi, r12
    mov rdx, r13
    call sb_push
.Lsac_skip:
    inc rbx
    jmp .Lsac_candidate
.Lsac_result:
    lea rdi, [rsp + 528]
    xor esi, esi
    call sb_push_byte
    mov rax, [rsp + 528 + SB_ptr]
    EPILOGUE
.Lsac_bad:
    lea rdi, [rip + .Lsource_config_bad]
    call app_toast
    xor eax, eax
    EPILOGUE

# save_source_kind(ptr,len): source followed by nonempty ASCII hierarchy segments.
save_source_kind:
    cmp rsi, 6
    jb 8f
    cmp rsi, 128
    ja 8f
    cmp dword ptr [rdi], 0x72756f73     # sour
    jne 8f
    cmp word ptr [rdi + 4], 0x6563    # ce
    jne 8f
    cmp rsi, 6
    je 7f
    cmp byte ptr [rdi + 6], '.'
    jne 8f
    mov ecx, 7
    xor r8d, r8d
1:  cmp rcx, rsi
    jae 6f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp al, '.'
    je 4f
    cmp al, '_'
    je 3f
    cmp al, '-'
    je 3f
    cmp al, '0'
    jb 8f
    cmp al, '9'
    jbe 3f
    or al, 32
    sub al, 'a'
    cmp al, 25
    ja 8f
3:  mov r8d, 1
    jmp 1b
4:  test r8d, r8d
    jz 8f
    xor r8d, r8d
    jmp 1b
6:  test r8d, r8d
    jz 8f
7:  mov eax, 1
    ret
8:  xor eax, eax
    ret

save_source_free:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + SJ_source]
    test r12, r12
    jz 9f
    mov qword ptr [rbx + SJ_source], 0
    xor r13d, r13d
1:  cmp r13, [r12 + SS_count]
    jae 2f
    mov rax, r13
    shl rax, 4
    mov rdi, [r12 + SS_providers + rax + 8]
    call mem_free
    inc r13
    jmp 1b
2:  mov rdi, [r12 + SS_text]
    call mem_free
    mov rdi, r12
    call mem_free
9:  EPILOGUE

# Manifest/status eligibility is rechecked before activation and dispatch.
save_source_eligible:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_is_visible
    test eax, eax
    jz 8f
    test dword ptr [rbx + EXT_needs], NEEDS_DOC_WRITE
    jz 8f
    cmp dword ptr [rbx + EXT_manifest_ok], 0
    je 8f
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    jbe 1f
    cmp eax, ES_CRASHED
    jne 8f
1:  mov rdi, [rbx + EXT_pv_save_actions]
    mov rsi, r12
    call extproto_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Names are owned so comparison includes the slash even when one owner prefixes another.
save_source_less:
1:  movzx eax, byte ptr [rdi]
    movzx edx, byte ptr [rsi]
    cmp eax, edx
    jne 2f
    test eax, eax
    jz 2f
    inc rdi
    inc rsi
    jmp 1b
2:  setb al
    movzx eax, al
    ret

# Initialize an immutable provider/kind snapshot. The source deadline includes cold starts.
save_source_init:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + DOC_version]
    mov [rbx + SJ_version], rax
    mov rdi, [rip + cfg_save_actions]
    cmp byte ptr [rdi], 0
    je 8f
    call strlen
    mov r13, rax
    mov edi, SS_SIZE
    call mem_alloc
    mov r14, rax
    mov [rbx + SJ_source], rax
    mov rdi, [rip + cfg_save_actions]
    mov rsi, r13
    call mem_dup
    mov [r14 + SS_text], rax
    mov [r14 + SS_kind], rax
    lea rcx, [rax + r13 + 1]
    mov [r14 + SS_end], rcx
1:  cmp byte ptr [rax], 0
    je 2f
    cmp byte ptr [rax], ' '
    jne 11f
    mov byte ptr [rax], 0
11: inc rax
    jmp 1b
2:  xor r15d, r15d
3:  cmp r15, [rip + g_exts + VEC_len]
    jae 6f
    imul r13, r15, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r15
    mov rdi, r13
    mov rsi, r12
    call save_source_eligible
    test eax, eax
    jz 3b
    mov rax, [r14 + SS_count]
    shl rax, 4
    mov [r14 + SS_providers + rax], r13
    mov rdi, r13
    call ext_full_name
    mov r13, rax
    mov rdi, rax
    call strlen
    mov rdi, r13
    mov rsi, rax
    call mem_dup
    mov rcx, [r14 + SS_count]
    shl rcx, 4
    mov [r14 + SS_providers + rcx + 8], rax
    inc qword ptr [r14 + SS_count]
    jmp 3b
6:  # Small insertion sort, at most 128 providers.
    mov r13d, 1
61: cmp r13, [r14 + SS_count]
    jae 7f
    mov r15, r13
62: test r15, r15
    jz 65f
    mov rax, r15
    shl rax, 4
    lea r12, [r14 + SS_providers + rax]
    mov rdi, [r12 + 8]
    mov rsi, [r12 - 8]
    call save_source_less
    test eax, eax
    jz 65f
    mov rax, [r12]
    mov rcx, [r12 + 8]
    mov rdx, [r12 - 16]
    mov rsi, [r12 - 8]
    mov [r12 - 16], rax
    mov [r12 - 8], rcx
    mov [r12], rdx
    mov [r12 + 8], rsi
    dec r15
    jmp 62b
65: inc r13
    jmp 61b
7:  call time_ms
    mov ecx, [rip + cfg_save_actions_timeout]
    add rax, rcx
    mov [rbx + SJ_deadline], rax
    mov qword ptr [rbx + SJ_phase], 1
    EPILOGUE
8:  mov qword ptr [rbx + SJ_phase], 2
    EPILOGUE

# Returns 1 while source work is pending, 0 when the formatter/commit phase may proceed.
save_source_tick:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + SJ_phase], 0
    jne 1f
    call save_source_init
    cmp qword ptr [rbx + SJ_phase], 2
    je .Lsst_ready
1:  mov rax, [r12 + DOC_version]
    cmp rax, [rbx + SJ_version]
    jne .Lsst_stale
    call time_ms
    cmp rax, [rbx + SJ_deadline]
    jae .Lsst_timeout
    mov r14, [rbx + SJ_source]
    mov rax, [rbx + SJ_state]
    cmp rax, 5
    je .Lsst_end
    cmp rax, 4
    je .Lsst_apply
    test rax, rax
    jnz .Lsst_wait
.Lsst_next:
    mov rax, [r14 + SS_index]
    cmp rax, [r14 + SS_count]
    jb 3f
    mov rdi, [r14 + SS_kind]
    call strlen
    add rax, [r14 + SS_kind]
    inc rax
    cmp rax, [r14 + SS_end]
    jae .Lsst_end
    mov [r14 + SS_kind], rax
    mov qword ptr [r14 + SS_index], 0
    jmp .Lsst_next
3:  shl rax, 4
    mov r13, [r14 + SS_providers + rax]
    mov rdi, r13
    mov rsi, r12
    call save_source_eligible
    test eax, eax
    jz .Lsst_advance
    mov [rbx + SJ_ext], r13
    mov qword ptr [rbx + SJ_state], 1
    mov rdi, r13
    call ext_start
.Lsst_wait:
    mov r13, [rbx + SJ_ext]
    mov rdi, r13
    mov rsi, r12
    call save_source_eligible
    test eax, eax
    jz .Lsst_advance
    mov eax, [r13 + EXT_status]
    cmp eax, ES_RUNNING
    je 21f
    cmp qword ptr [rbx + SJ_state], 2
    je .Lsst_failed
    cmp eax, ES_CRASHED
    je .Lsst_failed
    jmp .Lsst_pending
21:
    FEAT_TEST r13, FEAT_SAVE_ACTIONS
    jz .Lsst_advance
    cmp qword ptr [rbx + SJ_state], 2
    je .Lsst_pending
    lea rdi, [rip + save_line]
    call sb_clear
    lea rdi, [rip + save_line]
    lea rsi, [rip + .Lsource_request]
    call sb_push_cstr
    lea rdi, [rip + save_line]
    mov rsi, [rbx + SJ_id]
    call sb_push_u64
    call save_space
    lea rdi, [rip + save_line]
    mov rsi, [rbx + SJ_version]
    call sb_push_u64
    call save_space
    lea rdi, [rip + save_line]
    mov rsi, [r14 + SS_kind]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, r12
    mov rdx, [rip + save_line + SB_ptr]
    mov rcx, [rip + save_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz .Lsst_failed
    mov [rbx + SJ_request], rax
    mov qword ptr [rbx + SJ_state], 2
    jmp .Lsst_pending
.Lsst_apply:
    cmp qword ptr [rbx + SJ_len], 0
    je 4f
    mov rdi, [rbx + SJ_body]
    mov rsi, [rbx + SJ_len]
    mov rdx, [rbx + SJ_id]
    mov ecx, 1
    call ws_apply_document
    test eax, eax
    jz .Lsst_failed
4:  mov rax, [r12 + DOC_version]
    mov [rbx + SJ_version], rax
.Lsst_advance:
    mov rdi, rbx
    call save_cancel_request
    mov rdi, [rbx + SJ_body]
    call mem_free
    mov qword ptr [rbx + SJ_body], 0
    mov qword ptr [rbx + SJ_len], 0
    mov qword ptr [rbx + SJ_state], 0
    inc qword ptr [r14 + SS_index]
.Lsst_pending:
    mov eax, 1
    EPILOGUE
.Lsst_timeout:
    lea rax, [rip + .Lsource_timeout]
    jmp .Lsst_warning
.Lsst_failed:
    lea rax, [rip + .Lsource_failed]
.Lsst_warning:
    mov [rbx + SJ_warning], rax
.Lsst_end:
    mov rdi, rbx
    call save_cancel_request
    mov rdi, rbx
    call save_source_free
    mov rdi, [rbx + SJ_body]
    call mem_free
    mov qword ptr [rbx + SJ_body], 0
    mov qword ptr [rbx + SJ_len], 0
    mov qword ptr [rbx + SJ_phase], 2
    mov qword ptr [rbx + SJ_state], 0
.Lsst_ready:
    xor eax, eax
    EPILOGUE
.Lsst_stale:
    mov rdi, rbx
    call save_cancel_request
    mov qword ptr [rbx + SJ_phase], 2
    mov qword ptr [rbx + SJ_state], 3    # save latest text, skip remaining automatic transforms
    jmp .Lsst_ready

# Intermediate authority only exists while the exact peer's source request is outstanding.
# save_apply(ext, request, doc, version, body, len): version, or -1 refused, -2 stale, -3 edit.
FN save_apply
    PROLOGUE 32
    mov [rsp], r8
    mov [rsp + 8], r9
    mov [rsp + 16], rcx
    mov rbx, [rip + save_head]
    test rbx, rbx
    jz .Lsa_refused
    cmp qword ptr [rbx + SJ_phase], 1
    jne .Lsa_refused
    cmp qword ptr [rbx + SJ_state], 2
    jne .Lsa_refused
    test rsi, rsi
    jz .Lsa_refused
    cmp [rbx + SJ_ext], rdi
    jne .Lsa_refused
    cmp [rbx + SJ_request], rsi
    jne .Lsa_refused
    cmp [rbx + SJ_id], rdx
    jne .Lsa_refused
    call ext_is_visible
    test eax, eax
    jz .Lsa_refused
    call time_ms
    cmp rax, [rbx + SJ_deadline]
    jae .Lsa_refused
    mov rdi, [rbx + SJ_id]
    call extproto_doc
    test rax, rax
    jz .Lsa_refused
    cmp rax, [rbx + SJ_doc]
    jne .Lsa_refused
    mov r12, rax
    mov rdi, r12
    mov rsi, [rbx + SJ_language_revision]
    call doc_language_matches
    test eax, eax
    jz .Lsa_stale
    mov rax, [rbx + SJ_version]
    cmp rax, [rsp + 16]
    jne .Lsa_stale
    cmp rax, [r12 + DOC_version]
    jne .Lsa_stale
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rbx + SJ_id]
    mov ecx, 1
    call ws_apply_document
    test eax, eax
    jz .Lsa_edit
    mov rax, [r12 + DOC_version]
    mov [rbx + SJ_version], rax
    EPILOGUE
.Lsa_refused:
    mov rax, -1
    EPILOGUE
.Lsa_stale:
    mov rdx, [r12 + DOC_version]
    mov rax, -2
    EPILOGUE
.Lsa_edit:
    mov rax, -3
    EPILOGUE

.section .rodata
.Lsource_request: .asciz "save-actions "
.Lsource_failed: .asciz "Saved. Code actions before saving failed"
.Lsource_timeout: .asciz "Saved. Code actions before saving timed out"
.Lsource_config_bad: .asciz "Invalid code actions before saving. Previous setting kept"
