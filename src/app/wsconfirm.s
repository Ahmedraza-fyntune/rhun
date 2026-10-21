# workspace edits' questions in the palette: the confirmation list before an edit changes files
# on disk (v1.1.md workspace-edits) and the partial-undo list (wstx.s). A list is a pick list of
# its own palette mode; the rows' strings live here until it closes.
.include "rhun.inc"

.equ WLK_UNDO, 1
.equ WLK_CONFIRM, 2

STRUCT
F WR_off, 8                     # its text: offset in wl_bytes, length
F WR_len, 8
F WR_data, 8                    # what wslist_chosen gets
ENDSTRUCT WR_SIZE

.bss
.p2align 3
wl_kind: .quad 0                # WLK_* of the list on show, 0 for none
wl_label: .zero SB_SIZE         # its placeholder (the question)
wl_bytes: .zero SB_SIZE         # the rows' texts
wl_rows: .zero VEC_SIZE         # WR records

.text

# FN wslist_open(kind, label cstr): a new list (whatever the palette showed closes first), rows
# follow with wslist_add, then wslist_ready
FN wslist_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + wl_label]
    call sb_clear
    lea rdi, [rip + wl_label]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + wl_label]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + wl_bytes]
    call sb_clear
    mov qword ptr [rip + wl_rows + VEC_len], 0
    mov rdi, [rip + wl_label + SB_ptr]
    call palette_wslist_open    # closes what was open (an earlier list is cancelled then)
    mov [rip + wl_kind], rbx
    EPILOGUE

# FN wslist_add(text cstr, data): a row
FN wslist_add
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call strlen
    mov r13, rax
    lea rdi, [rip + wl_rows]
    mov esi, WR_SIZE
    call vec_push
    mov rcx, [rip + wl_bytes + SB_len]
    mov [rax + WR_off], rcx
    mov [rax + WR_len], r13
    mov [rax + WR_data], r12
    lea rdi, [rip + wl_bytes]
    mov rsi, rbx
    mov rdx, r13
    call sb_push
    EPILOGUE

# FN wslist_ready(): the rows go to the palette (their texts no longer move)
FN wslist_ready
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wl_rows + VEC_len]
    jae 2f
    imul r12, rbx, WR_SIZE
    add r12, [rip + wl_rows + VEC_ptr]
    inc rbx
    mov rdi, [r12 + WR_off]
    add rdi, [rip + wl_bytes + SB_ptr]
    mov rsi, [r12 + WR_len]
    mov rdx, [r12 + WR_data]
    call palette_choose_add
    jmp 1b
2:  call palette_choose_ready
    EPILOGUE

# FN wslist_chosen(data): the palette's pick (the palette has closed)
FN wslist_chosen
    mov rax, [rip + wl_kind]
    mov qword ptr [rip + wl_kind], 0
    cmp rax, WLK_UNDO
    je tx_list_chosen
    cmp rax, WLK_CONFIRM
    je ws_confirm_chosen
    ret

# FN wslist_abort(): the palette closed or turned to something else under the list: unanswered
FN wslist_abort
    mov rax, [rip + wl_kind]
    test rax, rax
    jz 9f
    mov qword ptr [rip + wl_kind], 0
    cmp rax, WLK_UNDO
    je tx_list_cancel
    cmp rax, WLK_CONFIRM
    je ws_confirm_cancel
9:  ret

# FN wslist_kind() -> rax the kind of the list on show, 0 for none
FN wslist_kind
    mov rax, [rip + wl_kind]
    ret

# ---------------- the confirmation list ----------------
# An edit that writes to disk without the extension's permission (project = write, or the user's
# standing permission) waits here: the plan (wg_vec, we_vec, the hidden documents, the body copy)
# stays as it is until the user applies it, previews it, or cancels.

.bss
.p2align 3
wc_parked: .quad 0              # 1 while an edit waits
wc_ext: .quad 0                 # its extension, request id (0: not a request), what ws_run had
wc_id: .quad 0
wc_req: .quad 0
wc_back: .quad 0
wc_feats: .quad 0
wc_quiet: .quad 0
wc_stale: .quad 0               # a document of the plan closed meanwhile
wc_data: .quad 0                # a code action's DATA (owned), sent once the edit is made
wc_dlen: .quad 0
wc_allow: .quad 0               # the list offers the standing permission
wc_prevdoc: .quad 0             # the preview tab's document, or 0
wc_sb: .zero SB_SIZE            # the question
wc_row: .zero SB_SIZE           # a row
wc_prev: .zero SB_SIZE          # the preview's unified diff
wc_old: .zero SB_SIZE
wc_new: .zero SB_SIZE

.text

# FN ws_parked() -> eax 1 while an edit waits for the user's answer
FN ws_parked
    mov rax, [rip + wc_parked]
    ret

# wc_allowed() -> eax 1 when the edit's extension may change project files without asking
wc_allowed:
    xor eax, eax
    mov rcx, [rip + ws_ext]
    test rcx, rcx
    jz 9f
    test dword ptr [rcx + EXT_needs], NEEDS_PROJECT_WRITE
    jnz 8f
    cmp dword ptr [rcx + EXT_edits], 0
    je 9f
8:  mov eax, 1
9:  ret

# FN ws_gate() -> eax 1 when the edit may be made now, 0 refused (ws_code), 2 waiting for the user:
# it changes disk without the extension's permission, or asked for the list (confirm record)
FN ws_gate
    PROLOGUE
    call ws_disk_needed
    mov ebx, eax
    cmp qword ptr [rip + ws_confirm], 0
    jne 1f
    test ebx, ebx
    jz 8f                       # open documents only: nothing to ask
    call wc_allowed
    test eax, eax
    jnz 8f
1:  call palette_is_open
    test eax, eax
    jnz .Lwg_busy
    # the plan waits: what ws_run's caller had goes with it
    call ws_tx_label            # the name, while the caller's string still exists
    mov qword ptr [rip + wc_parked], 1
    mov rax, [rip + ws_ext]
    mov [rip + wc_ext], rax
    mov rax, [rip + ws_req_id]
    mov [rip + wc_id], rax
    mov rax, [rip + ws_request_ext]
    mov [rip + wc_req], rax
    mov rax, [rip + ws_back]
    mov [rip + wc_back], rax
    mov rax, [rip + ws_feats]
    mov [rip + wc_feats], rax
    mov eax, [rip + ws_quiet]
    mov [rip + wc_quiet], rax
    mov qword ptr [rip + wc_stale], 0
    mov qword ptr [rip + wc_data], 0
    mov qword ptr [rip + wc_dlen], 0
    xor eax, eax
    test ebx, ebx
    jz 2f
    call wc_allowed
    xor eax, 1
2:  mov [rip + wc_allow], rax
    mov rsi, [rip + ws_act_dlen]
    test rsi, rsi
    jz 3f
    mov [rip + wc_dlen], rsi
    mov rdi, [rip + ws_act_data]
    call mem_dup
    mov [rip + wc_data], rax
3:  call wc_show
    mov eax, 2
    EPILOGUE
8:  mov eax, 1
    EPILOGUE
.Lwg_busy:
    lea rdi, [rip + .Lwc_busy]
    lea rsi, [rip + .Lws_e_busy]
    call ws_err
    EPILOGUE

# wc_count(kind) -> rax: text groups with edits: kind 0 of closed files, 1 of open documents
wc_count:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + wg_vec + VEC_len]
    jae 9f
    imul rdx, rcx, WG_SIZE
    add rdx, [rip + wg_vec + VEC_ptr]
    inc rcx
    cmp qword ptr [rdx + WG_kind], WK_TEXT
    jne 1b
    cmp qword ptr [rdx + WG_count], 0
    je 1b
    cmp qword ptr [rdx + WG_doc], 0
    je 1b
    mov r8, [rdx + WG_hidden]
    xor r8, 1                   # 1 for an open document
    cmp r8, rdi
    jne 1b
    inc rax
    jmp 1b
9:  ret

# wc_push_count(n, word cstr): " N WORD" with an s for several ("1 file", "3 files")
wc_push_count:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + wc_sb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + wc_sb]
    mov rsi, rbx
    call sb_push_u64
    lea rdi, [rip + wc_sb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + wc_sb]
    mov rsi, r12
    call sb_push_cstr
    cmp rbx, 1
    je 1f
    lea rdi, [rip + wc_sb]
    mov esi, 's'
    call sb_push_byte
1:  add rsp, 8
    pop r12
    pop rbx
    ret

# FN ws_rel(path cstr) -> rax the path as shown: inside the project, from it
FN ws_rel
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 8f
    call strlen
    mov r12, rax
    mov rdi, rbx
    call strlen
    cmp rax, r12
    jbe 8f
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rip + g_project]
    mov rcx, r12
    call str_starts
    test eax, eax
    jz 8f
    lea rax, [rbx + r12]
    cmp byte ptr [rax], '/'
.ifdef WINDOWS
    je 1f
    cmp byte ptr [rax], 92
.endif
    jne 8f
1:  inc rax
    jmp 9f
8:  mov rax, rbx
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# FN ws_group_name(WG*) -> rax its file's name as shown (the document's when untitled)
FN ws_group_name
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + WG_real]
    test rdi, rdi
    jnz 1f
    mov rax, [rbx + WG_doc]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jnz 1f
    mov rax, [rax + DOC_name]
    jmp 9f
1:  call ws_rel
9:  pop rbx
    ret

# wc_show(): the list: the question, Apply (and the standing permission), Preview, a row per file
wc_show:
    PROLOGUE
    # "Wsx: 'Rename to total' changes 3 files that are not open and 1 open file, renames 1"
    lea rdi, [rip + wc_sb]
    call sb_clear
    mov rax, [rip + wc_ext]
    lea rsi, [rip + .Lan_ext]
    test rax, rax
    jz 1f
    mov rsi, [rax + EXT_title]
1:  lea rdi, [rip + wc_sb]
    call sb_push_cstr
    lea rdi, [rip + wc_sb]
    lea rsi, [rip + .Lcolon_q]
    call sb_push_cstr
    lea rdi, [rip + wc_sb]
    mov rsi, [rip + ws_label + SB_ptr]
    mov rdx, [rip + ws_label + SB_len]
    call sb_push
    lea rdi, [rip + wc_sb]
    mov esi, 39
    call sb_push_byte
    xor edi, edi
    call wc_count
    mov rbx, rax                # closed files
    mov edi, 1
    call wc_count
    mov r12, rax                # open documents
    mov rax, rbx
    or rax, r12
    jz 4f
    lea rdi, [rip + wc_sb]
    lea rsi, [rip + .Lchanges]
    call sb_push_cstr
    test rbx, rbx
    jz 2f
    mov rdi, rbx
    lea rsi, [rip + .Lfile]
    call wc_push_count
    lea rdi, [rip + wc_sb]
    lea rsi, [rip + .Lnot_open]
    cmp rbx, 1
    jne 3f
    lea rsi, [rip + .Lnot_open1]
3:  call sb_push_cstr
    test r12, r12
    jz 4f
    lea rdi, [rip + wc_sb]
    lea rsi, [rip + .Land]
    call sb_push_cstr
2:  test r12, r12
    jz 4f
    mov rdi, r12
    lea rsi, [rip + .Lopen_file]
    call wc_push_count
4:  lea rdi, [rip + wc_sb]
    call ws_ops_summary         # ", creates 1, renames 1, deletes 1" (wsops.s)
    lea rdi, [rip + wc_sb]
    xor esi, esi
    call sb_push_byte
    mov edi, WLK_CONFIRM
    mov rsi, [rip + wc_sb + SB_ptr]
    call wslist_open
    lea rdi, [rip + .Lapply]
    mov esi, 1
    call wslist_add
    cmp qword ptr [rip + wc_allow], 0
    je 5f
    lea rdi, [rip + wc_row]
    call sb_clear
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Lallow1]
    call sb_push_cstr
    mov rax, [rip + wc_ext]
    lea rdi, [rip + wc_row]
    mov rsi, [rax + EXT_title]
    call sb_push_cstr
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Lallow2]
    call sb_push_cstr
    lea rdi, [rip + wc_row]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wc_row + SB_ptr]
    mov esi, 2
    call wslist_add
5:  lea rdi, [rip + .Lpreview]
    mov esi, 3
    call wslist_add
    # a row per entry: "M  path  2 edits", the file operations' rows (wsops.s)
    xor ebx, ebx
6:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    lea rdi, [rip + wc_row]
    call sb_clear
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 7f
    cmp qword ptr [r12 + WG_count], 0
    je 6b
    cmp qword ptr [r12 + WG_doc], 0
    je 6b
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Lm]
    call sb_push_cstr
    mov rdi, r12
    call ws_group_name
    lea rdi, [rip + wc_row]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Lgap]
    call sb_push_cstr
    lea rdi, [rip + wc_row]
    mov rsi, [r12 + WG_count]
    call sb_push_u64
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Ledits]
    cmp qword ptr [r12 + WG_count], 1
    jne 61f
    lea rsi, [rip + .Ledit]
61: call sb_push_cstr
    jmp 71f
7:  mov rdi, r12
    lea rsi, [rip + wc_row]
    call ws_ops_row             # "C  path", "R  from → to", "D  path" (wsops.s)
71: lea rdi, [rip + wc_row]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wc_row + SB_ptr]
    lea rsi, [rbx + 99]         # 100 + its index
    call wslist_add
    jmp 6b
8:  call wslist_ready
    EPILOGUE

# FN ws_confirm_chosen(n): the list's answer: 1 Apply, 2 Apply and allow from now on, 3 Preview,
# 100 + i the preview of entry i
FN ws_confirm_chosen
    PROLOGUE
    cmp qword ptr [rip + wc_parked], 0
    je 9f
    mov rbx, rdi
    cmp rbx, 3
    je 3f
    cmp rbx, 100
    jae 4f
    cmp rbx, 2
    jne 1f
    mov rdi, [rip + wc_ext]
    test rdi, rdi
    jz 1f
    mov esi, 1
    call ext_set_edits
1:  call ws_resume
    jmp 9f
3:  mov rdi, -1
    call wc_preview
    call wc_show
    jmp 9f
4:  lea rdi, [rbx - 100]
    call wc_preview
    call wc_show
9:  EPILOGUE

# FN ws_confirm_cancel(): the list closed unanswered: nothing changes; a request is answered
# cancelled
FN ws_confirm_cancel
    PROLOGUE
    cmp qword ptr [rip + wc_parked], 0
    je 9f
    mov qword ptr [rip + wc_parked], 0
    xor edi, edi                # language features: an action's command that waited goes
    call langfeat_ws_resolved
    mov rax, [rip + wc_quiet]
    mov [rip + ws_quiet], eax
    mov rax, [rip + wc_back]
    mov [rip + ws_back], rax
    call ws_release
    mov rdi, [rip + wc_data]
    call mem_free
    mov qword ptr [rip + wc_data], 0
    mov rsi, [rip + wc_id]
    test rsi, rsi
    jz 8f
    mov rdi, [rip + wc_ext]
    lea rdx, [rip + .Lwc_cancelled]
    call extproto_reply_to
8:  mov dword ptr [rip + ws_quiet], 0
9:  EPILOGUE

# FN ws_confirm_owner_gone(ext): the extension stopped: its waiting edit goes, unanswered
FN ws_confirm_owner_gone
    PROLOGUE
    cmp qword ptr [rip + wc_parked], 0
    je 9f
    cmp [rip + wc_ext], rdi
    jne 9f
    mov qword ptr [rip + wc_id], 0
    mov qword ptr [rip + wc_ext], 0
    call wslist_kind
    cmp rax, WLK_CONFIRM
    jne 1f
    call palette_close          # wslist_abort cancels it
    jmp 9f
1:  call ws_confirm_cancel
9:  EPILOGUE

# FN ws_park_doc_closed(doc): a document closes while an edit waits: the edit is stale
FN ws_park_doc_closed
    cmp qword ptr [rip + wc_parked], 0
    je 9f
    xor ecx, ecx
1:  cmp rcx, [rip + wg_vec + VEC_len]
    jae 9f
    imul rax, rcx, WG_SIZE
    add rax, [rip + wg_vec + VEC_ptr]
    inc rcx
    cmp qword ptr [rax + WG_hidden], 0
    jne 1b
    cmp [rax + WG_doc], rdi
    jne 1b
    mov qword ptr [rax + WG_doc], 0
    mov qword ptr [rip + wc_stale], 1
    jmp 1b
9:  ret

# ws_resume(): Apply: the waiting edit is checked again and made; a request gets its reply
ws_resume:
    PROLOGUE
    mov qword ptr [rip + wc_parked], 0
    mov rax, [rip + wc_ext]
    mov [rip + ws_ext], rax
    mov rax, [rip + wc_id]
    mov [rip + ws_req_id], rax
    mov rax, [rip + wc_req]
    mov [rip + ws_request_ext], rax
    mov rax, [rip + wc_back]
    mov [rip + ws_back], rax
    mov rax, [rip + wc_feats]
    mov [rip + ws_feats], rax
    mov rax, [rip + wc_quiet]
    mov [rip + ws_quiet], eax
    mov qword ptr [rip + ws_deflabel], 0
    mov qword ptr [rip + ws_entry], 0
    mov dword ptr [rip + ws_wrote], 0
    cmp qword ptr [rip + wc_stale], 0
    jne .Lwm_stale
    # nothing changed while the list was open: open documents at their versions, closed files
    # with their stamps
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 3f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 1b
    mov rax, [r12 + WG_doc]
    test rax, rax
    jz 1b
    cmp qword ptr [r12 + WG_hidden], 0
    jne 2f
    mov rcx, [rax + DOC_version]
    cmp rcx, [r12 + WG_ver0]
    jne .Lwm_stale
    jmp 1b
2:  mov rdi, [r12 + WG_real]
    call vfs_stamp
    cmp rax, [r12 + WG_stamp]
    jne .Lwm_stale
    jmp 1b
3:  call ws_ops_recheck         # the file operations' paths as they were (wsops.s)
    test eax, eax
    jz .Lwm_fail
    mov qword ptr [rip + ws_entry], 0
    call ws_commit
    test eax, eax
    jz .Lwm_fail
    call ws_finish
    mov edi, 1                  # language features: an action's command that waited runs now
    call langfeat_ws_resolved
    mov rsi, [rip + wc_id]
    test rsi, rsi
    jz 4f
    mov rdi, [rip + wc_ext]
    xor edx, edx
    call extproto_reply_to
4:  mov rsi, [rip + wc_data]
    test rsi, rsi
    jz 8f
    mov rdi, [rip + wc_ext]
    test rdi, rdi
    jz 8f
    mov rdx, [rip + wc_dlen]
    call extproto_send_action
    jmp 8f
.Lwm_stale:
    lea rdi, [rip + .Lwc_stale]
    lea rsi, [rip + .Lws_e_stale]
    call ws_err
.Lwm_fail:
    xor edi, edi                # language features: an action's command that waited goes
    call langfeat_ws_resolved
    call ws_unwind
    mov rsi, [rip + wc_id]
    test rsi, rsi
    jz 8f
    mov rdi, [rip + wc_ext]
    mov rdx, [rip + ws_code]
    call extproto_reply_to
8:  mov rdi, [rip + wc_data]
    call mem_free
    mov qword ptr [rip + wc_data], 0
    mov dword ptr [rip + ws_quiet], 0
    mov qword ptr [rip + ws_request_ext], 0
    mov qword ptr [rip + ws_req_id], 0
    EPILOGUE

# wc_preview(entry or -1): a read-only "Preview: LABEL" tab with the unified diff of every file the
# edit changes (or of that entry only); the one shown before closes
wc_preview:
    PROLOGUE 16
    mov [rsp], rdi
    mov rdi, [rip + wc_prevdoc]
    test rdi, rdi
    jz 1f
    mov qword ptr [rip + wc_prevdoc], 0
    call doc_tab
    test rax, rax
    js 1f
    mov rdi, rax
    call app_close_tab_now
1:  lea rdi, [rip + wc_prev]
    call sb_clear
    xor ebx, ebx
2:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 5f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov rax, [rsp]
    test rax, rax
    js 21f
    lea rcx, [rbx - 1]
    cmp rcx, rax
    jne 2b
21: cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 4f
    cmp qword ptr [r12 + WG_count], 0
    je 2b
    mov r13, [r12 + WG_doc]
    test r13, r13
    jz 2b
    cmp qword ptr [r12 + WG_hidden], 0
    je 3f
    # a closed file: its bytes as read and as they will be written
    mov rdi, r12
    call ws_group_name
    mov rsi, rax
    lea rdi, [rip + wc_prev]
    mov rdx, [r12 + WG_orig]
    mov rcx, [r12 + WG_olen]
    mov r8, [r12 + WG_new]
    mov r9, [r12 + WG_nlen]
    call diff_unified
    jmp 2b
3:  # an open document: its text now, and as it will be (the edits made on a copy)
    mov rdi, r13
    lea rsi, [rip + wc_old]
    call ws_doc_bytes
    call doc_new
    mov r14, rax
    mov eax, [r13 + DOC_crlf]
    mov [r14 + DOC_crlf], eax
    mov rdi, r13
    call doc_len
    mov r15, rax
    lea rdi, [rip + wc_new]
    call sb_clear
    lea rdi, [rip + wc_new]
    mov rsi, r15
    call sb_reserve
    mov rdi, r13
    xor esi, esi
    mov rdx, r15
    mov rcx, rax
    call doc_copy
    mov rdi, r14
    mov rsi, [rip + wc_new + SB_ptr]
    mov rdx, r15
    call doc_replace_all
    mov [r12 + WG_doc], r14
    mov qword ptr [r12 + WG_hidden], 1
    mov rdi, r12
    call ws_apply_group
    mov [r12 + WG_doc], r13
    mov qword ptr [r12 + WG_hidden], 0
    mov rdi, r14
    lea rsi, [rip + wc_new]
    call ws_doc_bytes
    mov rdi, r14
    call doc_free
    mov rdi, r12
    call ws_group_name
    mov rsi, rax
    lea rdi, [rip + wc_prev]
    mov rdx, [rip + wc_old + SB_ptr]
    mov rcx, [rip + wc_old + SB_len]
    mov r8, [rip + wc_new + SB_ptr]
    mov r9, [rip + wc_new + SB_len]
    call diff_unified
    jmp 2b
4:  mov rdi, r12
    lea rsi, [rip + wc_prev]
    call ws_ops_preview         # created, renamed and deleted files (wsops.s)
    jmp 2b
5:  # "Preview: Rename to 'total'"
    lea rdi, [rip + wc_row]
    call sb_clear
    lea rdi, [rip + wc_row]
    lea rsi, [rip + .Lpreview_title]
    call sb_push_cstr
    lea rdi, [rip + wc_row]
    mov rsi, [rip + ws_label + SB_ptr]
    mov rdx, [rip + ws_label + SB_len]
    call sb_push
    lea rdi, [rip + wc_row]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + wc_row + SB_ptr]
    mov rsi, [rip + wc_prev + SB_ptr]
    mov rdx, [rip + wc_prev + SB_len]
    mov ecx, 1
    call wsdiff_tab
    mov [rip + wc_prevdoc], rax
    EPILOGUE

.section .rodata
.Lan_ext: .asciz "An extension"
.Lcolon_q: .asciz ": '"
.Lchanges: .asciz " changes"
.Lfile: .asciz "file"
.Lopen_file: .asciz "open file"
.Lnot_open: .asciz " that are not open"
.Lnot_open1: .asciz " that is not open"
.Land: .asciz " and"
.Lapply: .asciz "Apply"
.Lallow1: .asciz "Apply, and let "
.Lallow2: .asciz " change project files from now on"
.Lpreview: .asciz "Preview changes"
.Lpreview_title: .asciz "Preview: "
.Lm: .asciz "M  "
.Lgap: .asciz "    "
.Ledits: .asciz " edits"
.Ledit: .asciz " edit"
.Lwc_busy: .asciz "busy a prompt or the palette is open"
.Lws_e_busy: .asciz "The palette is open: the extension's edit was not made"
.Lwc_cancelled: .asciz "cancelled 0 the user cancelled the edit"
.Lwc_stale: .asciz "stale a document or file changed while the edit waited"
.Lws_e_stale: .asciz "A file changed while the edit waited: nothing changed"
