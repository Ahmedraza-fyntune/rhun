# custom editors (wider-parity design, part B; docs/extensions/v1.1.md "Feature: custom-editors"):
# a file an extension's [provides] editor matches opens in a tab the extension draws, a 12a view
# (extview.s) bound to a CE. The text model keeps the file in an ordinary DOC (TAB_doc), whose undo,
# dirty state, saving and reloading are rhun's; the extension draws it and changes it with replace.
# The owned model keeps the file in the extension: TAB_doc is a stand-in with the path and no text,
# rhun routes Save, Save As, Undo, Redo, Revert and the close questions to the extension, shows its
# dirty dot (the stand-in's DOC_savepoint is -1 while it is dirty, as a notebook's) and writes the
# bytes it is given, asked for in parts. ceproto.inc speaks the messages.
#
#   ce_provider(path) -> rax EXT* of the editor that opens the file, edx its CEM_ model, or rax 0
#   ce_open_tab(path, ext, model) -> rax the tab's index, or -1
#   ce_of_tab(TAB*) -> CE* or 0; ce_active() -> CE* of the active tab or 0
#   ce_tab_closed(doc), ce_ext_gone(ext), ce_tick(), ce_timeout()
#   ce_save_start(doc, flags, fn, arg): app_save_start for an owned model's stand-in
#   ce_undo(), ce_redo(): Undo and Redo in a custom editor's tab; ce_revert(doc), ce_disk_changed(doc)
#   cmd_reopen_with: the Reopen With list; ce_config_*: the [editors] choices in the config
.include "rhun.inc"

.bss
.p2align 3
.globl g_ces
g_ces: .zero VEC_SIZE           # CE* each
choices: .zero VEC_SIZE         # [editors]: pattern cstr, value cstr (16 bytes each)
picks: .zero VEC_SIZE           # Reopen With's rows: EXT* (0: Text), 8 bytes each
pick_path: .quad 0              # the file Reopen With is for (owned cstr)
msg: .zero SB_SIZE

.text

# ---------------- which editor ----------------

# ce_model_of(ext) -> eax CEM_OWNED when its editor.model is "owned", else CEM_TEXT
ce_model_of:
    PROLOGUE
    mov esi, EXT_pv_edmodel
    call ext_pv
    test rax, rax
    jz 8f
    mov rdi, rax
    lea rsi, [rip + .Lowned]
    call strcmp_eq
    test eax, eax
    jz 8f
    mov eax, CEM_OWNED
    EPILOGUE
8:  mov eax, CEM_TEXT
    EPILOGUE

# ce_ext_matches(ext, path) -> eax 1 when the extension provides an editor for the file
ce_ext_matches:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ext_is_visible
    test eax, eax
    jz 8f
    cmp dword ptr [rbx + EXT_manifest_ok], 0
    je 8f
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 8f
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    mov rdi, rbx
    mov esi, EXT_pv_editor
    call ext_pv
    test rax, rax
    jz 8f
    mov rdi, r12
    mov rsi, rax
    call ext_path_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_is_option(ext) -> eax 1 when its editor.priority is "option" (only through Reopen With)
ce_is_option:
    PROLOGUE
    mov esi, EXT_pv_edprio
    call ext_pv
    test rax, rax
    jz 8f
    mov rdi, rax
    lea rsi, [rip + .Loption]
    call strcmp_eq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_ext_named(cstr "owner/name") -> EXT* or 0
ce_ext_named:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 8f
    imul r13, rbx, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc rbx
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    mov rsi, [r13 + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + msg]
    mov rsi, [r13 + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ce_provider(path) -> rax EXT* of the editor that opens the file, edx its model; rax 0: the
#   file opens as rhun would open it. An [editors] choice for the file wins ("text" or OWNER/NAME);
#   else the first extension whose editor matches it and is not an option.
FN ce_provider
    PROLOGUE
    mov r12, rdi
    call ce_choice_for
    test rax, rax
    jz 2f
    mov rdi, rax
    lea rsi, [rip + .Ltext]
    push rdi
    push rdi
    call strcmp_eq
    pop rdi
    pop rdi
    test eax, eax
    jnz 8f
    call ce_ext_named
    test rax, rax
    jz 2f
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    call ce_ext_matches
    test eax, eax
    jnz 7f
2:  xor r13d, r13d
3:  cmp r13, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    mov rdi, rbx
    mov rsi, r12
    call ce_ext_matches
    test eax, eax
    jz 3b
    mov rdi, rbx
    call ce_is_option
    test eax, eax
    jnz 3b
7:  mov rdi, rbx
    call ce_model_of
    mov edx, eax
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ce_provider_any(path) -> rax EXT* of the first editor that matches the file, an option one
#   too, edx its model; rax 0 when none does (a binary file that cannot open as text)
FN ce_provider_any
    PROLOGUE
    mov r12, rdi
    cmp dword ptr [rip + ce_open_text], 0
    jne 8f
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r13
    mov rdi, rbx
    mov rsi, r12
    call ce_ext_matches
    test eax, eax
    jz 1b
    mov rdi, rbx
    call ce_model_of
    mov edx, eax
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- the [editors] choices ----------------

# FN ce_config_reset(): the choices go (the config is read again)
FN ce_config_reset
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + choices + VEC_len]
    jae 2f
    mov rax, rbx
    shl rax, 4
    add rax, [rip + choices + VEC_ptr]
    mov r12, rax
    mov rdi, [r12]
    call mem_free
    mov rdi, [r12 + 8]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + choices + VEC_len], 0
    EPILOGUE

# FN ce_config_kv(key ptr, len, value ptr, len): "PATTERN = OWNER/NAME | text" under [editors]
FN ce_config_kv
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    test r13, r13
    jz 9f
    test r15, r15
    jz 9f
    lea rdi, [rip + choices]
    mov esi, 16
    call vec_push
    mov rbx, rax
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rbx], rax
    mov rdi, r14
    mov rsi, r15
    call mem_dup
    mov [rbx + 8], rax
9:  EPILOGUE

# FN ce_config_write(sb): the choices as an [editors] section, when there are any
FN ce_config_write
    PROLOGUE
    mov r12, rdi
    cmp qword ptr [rip + choices + VEC_len], 0
    je 9f
    mov rdi, r12
    lea rsi, [rip + .Lsec]
    call sb_push_cstr
    xor ebx, ebx
1:  cmp rbx, [rip + choices + VEC_len]
    jae 9f
    mov r13, rbx
    shl r13, 4
    add r13, [rip + choices + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, [r13]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Leq]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r13 + 8]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# ce_choice_for(path) -> rax the value of the first [editors] pattern the file matches, or 0
ce_choice_for:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + choices + VEC_len]
    jae 8f
    mov r13, rbx
    shl r13, 4
    add r13, [rip + choices + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, [r13]
    call ext_path_matches
    test eax, eax
    jz 1b
    mov rax, [r13 + 8]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_choose(path, value cstr): the choice for files like this one (by its extension, "*.bin", or
#   its name) is the value from now on, and the config is written
ce_choose:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    # the pattern: "*" and the name's last dot on, or the whole name
    call strlen
    mov rsi, rax
    mov rdi, r12
    call path_basename
    mov r14, rax
    mov r15, rdx
    lea rdi, [rip + msg]
    call sb_clear
    mov rcx, r15
1:  test rcx, rcx
    jz 3f
    cmp byte ptr [r14 + rcx - 1], '.'
    je 2f
    dec rcx
    jmp 1b
2:  cmp rcx, 1                  # ".bashrc": the name itself
    je 3f
    push rcx
    push rcx
    lea rdi, [rip + msg]
    mov esi, '*'
    call sb_push_byte
    pop rcx
    pop rcx
    lea rsi, [r14 + rcx - 1]
    mov rdx, r15
    sub rdx, rcx
    inc rdx
    lea rdi, [rip + msg]
    call sb_push
    jmp 4f
3:  lea rdi, [rip + msg]
    mov rsi, r14
    mov rdx, r15
    call sb_push
4:  # replace the pattern's line, or add one
    xor ebx, ebx
5:  cmp rbx, [rip + choices + VEC_len]
    jae 6f
    mov rax, rbx
    shl rax, 4
    add rax, [rip + choices + VEC_ptr]
    inc rbx
    push rax
    push rax
    mov rdi, [rax]
    mov rsi, [rip + msg + SB_ptr]
    mov rdx, [rip + msg + SB_len]
    call str_eq_cstr_n
    pop rcx
    pop rcx
    test eax, eax
    jz 5b
    mov r14, rcx
    mov rdi, [r14 + 8]
    call mem_free
    mov rdi, r13
    call dup_cstr
    mov [r14 + 8], rax
    jmp 7f
6:  mov rdi, [rip + msg + SB_ptr]
    mov rsi, [rip + msg + SB_len]
    mov rdx, r13
    push rdx
    push rdx
    mov rdi, r13
    call strlen
    mov rcx, rax
    pop rdx
    pop rdx
    mov rdi, [rip + msg + SB_ptr]
    mov rsi, [rip + msg + SB_len]
    call ce_config_kv
7:  call config_save
    EPILOGUE

# str_eq_cstr_n(cstr, ptr, len) -> eax 1 when the cstr is those bytes
str_eq_cstr_n:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rbx
    call str_eq_cstr
    pop rbx
    ret

# ---------------- tabs ----------------

# FN ce_of_tab(TAB*) -> CE* when the tab is a custom editor's, else 0
FN ce_of_tab
    xor eax, eax
    cmp qword ptr [rdi + TAB_kind], TAB_VIEW
    jne 9f
    test dword ptr [rdi + TAB_flags], TF_CUSTOM
    jz 9f
    mov rax, [rdi + TAB_doc]
    test rax, rax
    jz 9f
    mov rax, [rax + DOC_ce]
9:  ret

# FN ce_active() -> CE* of the active tab, or 0
FN ce_active
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 8f
    sub rsp, 8
    call tab_at
    add rsp, 8
    mov rdi, rax
    jmp ce_of_tab
8:  xor eax, eax
    ret

# FN ce_open_tab(path, ext, model) -> rax the new tab's index, or -1 (said in a toast)
FN ce_open_tab
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], edx
    call doc_new
    mov rbx, rax
    cmp dword ptr [rsp], CEM_OWNED
    je 1f
    # text model: the file's document, read as rhun reads files
    mov rdi, rbx
    mov rsi, r12
    call doc_load
    cmp rax, -2                 # a missing file can be created
    je 2f
    test rax, rax
    jns 2f
    mov rdi, rbx
    call doc_free
    lea rdi, [rip + .Lcannot_read]
    call app_toast
    mov rax, -1
    EPILOGUE
2:  mov rdi, rbx
    call app_detect_lang
    jmp 3f
1:  mov rdi, rbx                # owned: a stand-in that has the path
    mov rsi, r12
    call doc_set_path
    mov rdi, r12
    call vfs_stamp
    mov [rbx + DOC_mtime], rax
3:  mov edi, CE_SIZE
    call mem_alloc
    mov r14, rax
    mov rdi, r14
    xor esi, esi
    mov edx, CE_SIZE
    call memset
    mov [r14 + CE_doc], rbx
    mov [rbx + DOC_ce], r14
    mov [r14 + CE_ext], r13
    mov eax, [rsp]
    mov [r14 + CE_model], eax
    mov dword ptr [r14 + CE_want], CER_OPEN
    call time_ms
    mov [r14 + CE_reqat], rax
    mov rdi, r12
    call dup_cstr
    mov [r14 + CE_path], rax
    cmp dword ptr [r14 + CE_model], CEM_OWNED
    jne 4f
    mov rdi, r14                # B3: unsaved changes a crash left in a backup open again
    call ce_backup_exists
    mov [r14 + CE_restore], eax
4:  # its view: a picture rhun hosts in the tab (not one of the extension's 8 views; a press gives
    # it the keyboard with view-keys), titled with the file's name
    call extview_next_id
    mov [r14 + CE_vid], rax
    mov rdi, r13
    mov esi, eax
    call extview_open_hosted
    test rax, rax
    jz .Lcot_noview
    mov r15, rax
    mov rdi, [r15 + VW_title]
    call mem_free
    mov rdi, r12
    call strlen
    mov rsi, rax
    mov rdi, r12
    call path_basename
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov [r15 + VW_title], rax
    mov rdi, rbx
    mov esi, TAB_VIEW
    call app_add_tab
    mov rdi, rax
    call tab_at
    lea rcx, [rip + g_views]    # the view's slot in the tab's flags, as extview_open's tabs have it
    mov rdx, r15
    sub rdx, rcx
    mov rax, rdx
    push rax
    push rax
    mov rdi, [rip + g_tab_cur]
    call tab_at
    mov rcx, rax
    pop rax
    pop rdx
    xor edx, edx
    mov r8d, VW_SIZE
    div r8
    inc rax
    shl rax, TF_VIEW_SHIFT
    or rax, TF_CUSTOM
    or [rcx + TAB_flags], rax
    lea rdi, [rip + g_ces]
    mov esi, 8
    call vec_push
    mov [rax], r14
    mov rdi, r13
    call ce_ext_wake
    mov rdi, r14
    call ce_pump
    call app_sync_doc
    mov rax, [rip + g_tab_cur]
    EPILOGUE
.Lcot_noview:
    mov qword ptr [rbx + DOC_ce], 0
    mov rdi, [r14 + CE_path]
    call mem_free
    mov rdi, r14
    call mem_free
    mov rdi, rbx
    call doc_free
    lea rdi, [rip + .Lno_view]
    call app_toast
    mov rax, -1
    EPILOGUE

# ce_ext_wake(ext): an extension an editor needs starts when it is idle or crashed; one the user
#   stopped stays stopped
ce_ext_wake:
    mov eax, [rdi + EXT_status]
    cmp eax, ES_IDLE
    je 1f
    cmp eax, ES_CRASHED
    jne 9f
1:  jmp ext_start
9:  ret

# FN ce_tab_closed(doc): a custom editor's tab closes (app_close_tab_now, before its document is
#   freed): the extension hears editor-closed, a request rhun waited on is withdrawn, a save in
#   progress fails, the CE goes
FN ce_tab_closed
    PROLOGUE
    mov rbx, [rdi + DOC_ce]
    test rbx, rbx
    jz 9f
    mov qword ptr [rdi + DOC_ce], 0
    mov rdi, rbx
    call ce_send_closed
    mov rdi, rbx
    call ce_req_drop
    mov rdi, rbx
    mov rsi, -5
    call ce_save_done
    mov rdi, rbx                # closed after the save-or-discard question: its backup goes
    call ce_backup_drop
    mov rdi, rbx
    call ce_free
9:  EPILOGUE

# ce_free(ce): out of g_ces, its memory freed (not its document)
ce_free:
    PROLOGUE
    mov rbx, rdi
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 3f
    mov rax, [rip + g_ces + VEC_ptr]
    cmp [rax + rcx*8], rbx
    je 2f
    inc rcx
    jmp 1b
2:  mov rdx, [rip + g_ces + VEC_len]
    dec rdx
    mov [rip + g_ces + VEC_len], rdx
    mov rsi, [rax + rdx*8]
    mov [rax + rcx*8], rsi
3:  lea rdi, [rbx + CE_buf]
    call sb_free
    mov rdi, [rbx + CE_target]
    call mem_free
    mov rdi, [rbx + CE_path]
    call mem_free
    mov rdi, rbx
    call mem_free
    EPILOGUE

# FN ce_by_cdoc(ext, cdoc) -> CE* of that extension's editor of the document, or 0
FN ce_by_cdoc
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp [rax + CE_ext], rdi
    jne 1b
    mov rdx, [rax + CE_doc]
    cmp [rdx + DOC_id], rsi
    jne 1b
    ret
8:  xor eax, eax
    ret

# FN ce_doc_by_id(id) -> DOC* of a text model's document with that id (it has no TAB_DOC tab), or 0
FN ce_doc_by_id
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp dword ptr [rax + CE_model], CEM_TEXT
    jne 1b
    mov rax, [rax + CE_doc]
    cmp [rax + DOC_id], rdi
    jne 1b
    ret
8:  xor eax, eax
    ret

# FN ce_any_by_id(id) -> DOC* of a custom editor's document (either model) with that id, or 0
FN ce_any_by_id
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    mov rax, [rax + CE_doc]
    cmp [rax + DOC_id], rdi
    jne 1b
    ret
8:  xor eax, eax
    ret

# FN ce_ext_doc_at(ext, i) -> DOC* of the i-th document extensions hear of besides the tabs: the
#   notebooks' cells (for one that agreed notebooks, nbdoc.s), then the text models' documents;
#   0 past the last
FN ce_ext_doc_at
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d              # the cells there are for it
    FEAT_TEST rbx, FEAT_NOTEBOOKS
    jz 2f
    mov rdi, rbx
    mov rsi, r12
    call nb_ext_doc_at
    test rax, rax
    jnz 9f
    # how many cells: the index past the last one
    xor r13d, r13d
1:  mov rdi, rbx
    mov rsi, r13
    call nb_ext_doc_at
    test rax, rax
    jz 2f
    inc r13
    jmp 1b
2:  mov rcx, r12
    sub rcx, r13
    js 8f
    xor edx, edx
3:  cmp rdx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rdx*8]
    inc rdx
    cmp dword ptr [rax + CE_model], CEM_TEXT
    jne 3b
    test rcx, rcx
    jz 4f
    dec rcx
    jmp 3b
4:  mov rax, [rax + CE_doc]
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# FN ce_ext_gone(ext): its editors' requests fail and their tabs close (unsaved changes of an owned
#   model go with its extension)
FN ce_ext_gone
    PROLOGUE
    mov r12, rdi
1:  xor r13d, r13d
2:  cmp r13, [rip + g_ces + VEC_len]
    jae 9f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rbx, [rax + r13*8]
    inc r13
    cmp [rbx + CE_ext], r12
    jne 2b
    cmp dword ptr [rbx + CE_state], CES_STOPPED
    je 2b
    mov qword ptr [rbx + CE_req], 0
    mov dword ptr [rbx + CE_reqkind], 0
    mov dword ptr [rbx + CE_want], 0
    mov rdi, rbx
    mov rsi, -32
    call ce_save_done
    # unsaved changes in a backup (B3): the tab stays, and offers them back
    cmp dword ptr [rbx + CE_dirty], 0
    je 3f
    cmp dword ptr [rbx + CE_bkdone], 0
    je 3f
    mov dword ptr [rbx + CE_state], CES_STOPPED
    mov dword ptr [rip + g_dirty], 1
    jmp 2b
3:  mov rdi, [rbx + CE_doc]
    call doc_tab
    test rax, rax
    js 2b
    mov rdi, rax
    call app_close_tab_now      # ce_tab_closed frees the CE: g_ces changed, look again
    jmp 1b
9:  EPILOGUE

# ---------------- requests rhun waits on ----------------

# ce_req_drop(ce): rhun no longer waits on its request: "0 cancel ID" when one went out
ce_req_drop:
    push rbx
    mov rbx, rdi
    mov rsi, [rbx + CE_req]
    test rsi, rsi
    jz 1f
    mov qword ptr [rbx + CE_req], 0
    mov dword ptr [rbx + CE_reqkind], 0
    mov rdi, [rbx + CE_ext]
    push rsi
    push rdi
    call ext_reply_cap_drop
    pop rdi
    pop rsi
    call query_withdraw
1:  pop rbx
    ret

# ce_pump(ce): editor-open goes out once its extension runs and agreed custom-editors
ce_pump:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_want], CER_OPEN
    jne 9f
    cmp qword ptr [rbx + CE_req], 0
    jne 9f
    mov r12, [rbx + CE_ext]
    mov eax, [r12 + EXT_status]
    cmp eax, ES_RUNNING
    je 3f
    cmp eax, ES_STARTING
    je 9f
    cmp eax, ES_STOPPING
    je 9f
    cmp eax, ES_IDLE            # waiting for a slot, or to be started
    jne .Lcp_failed
    cmp dword ptr [r12 + EXT_wait_slot], 0
    jne 9f
    mov rdi, r12
    call ext_start
    jmp 9f
3:  FEAT_TEST r12, FEAT_CUSTOM_EDITORS
    jz .Lcp_nofeat
    mov dword ptr [rbx + CE_want], 0
    mov rdi, rbx
    call ce_send_open
    test rax, rax
    jz .Lcp_failed
    mov [rbx + CE_req], rax
    mov dword ptr [rbx + CE_reqkind], CER_OPEN
    call time_ms
    mov [rbx + CE_reqat], rax
9:  EPILOGUE
.Lcp_nofeat:
    lea rsi, [rip + .Lno_feature]
    jmp 1f
.Lcp_failed:
    lea rsi, [rip + .Lno_send]
1:  mov dword ptr [rbx + CE_want], 0
    mov rdi, rbx
    call ce_open_failed
    EPILOGUE

# ce_open_failed(ce, why cstr): the editor did not open: its tab closes, the file opens as text,
#   the reason in a toast
ce_open_failed:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi                # a copy: closing the tab reuses msg
    call dup_cstr
    mov r12, rax
    mov rdi, [rbx + CE_path]
    call dup_cstr
    mov r13, rax
    mov rdi, [rbx + CE_doc]
    call doc_tab
    test rax, rax
    js 1f
    mov rdi, rax
    call app_close_tab_now      # ce_tab_closed frees the CE
1:  mov dword ptr [rip + g_nb_open_text], 1
    mov dword ptr [rip + ce_open_text], 1
    mov rdi, r13
    call app_open_file
    mov dword ptr [rip + g_nb_open_text], 0
    mov dword ptr [rip + ce_open_text], 0
    mov rdi, r13
    call mem_free
    mov rdi, r12
    call app_toast
    mov rdi, r12
    call mem_free
    EPILOGUE

# FN ce_tick(): editors waiting for their extension are opened; a request without an answer fails
FN ce_tick
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_ces + VEC_len]
    jae 9f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rbx, [rax + r12*8]
    inc r12
    mov rdi, rbx
    call ce_pump
    # the caller may have closed it: g_ces then shrank
    cmp r12, [rip + g_ces + VEC_len]
    ja 9f
    mov rax, [rip + g_ces + VEC_ptr]
    cmp [rax + r12*8 - 8], rbx
    jne 1b
    mov rdi, rbx                # B3: a dirty owned model's backup
    call ce_backup_due
    cmp qword ptr [rbx + CE_req], 0
    jne 2f
    cmp dword ptr [rbx + CE_want], 0
    je 1b
2:  call time_ms
    sub rax, [rbx + CE_reqat]
    cmp rax, CE_WAIT_MS
    jb 1b
    mov r13d, [rbx + CE_reqkind]
    cmp dword ptr [rbx + CE_want], CER_OPEN
    jne 3f
    mov r13d, CER_OPEN
3:  mov rdi, rbx
    call ce_req_drop
    cmp r13d, CER_OPEN
    jne 4f
    mov dword ptr [rbx + CE_want], 0
    mov rdi, rbx
    lea rsi, [rip + .Lno_answer]
    call ce_open_failed
    jmp 9f                      # g_ces changed: the rest next tick
4:  mov rdi, rbx
    mov rsi, -110
    call ce_save_done
    jmp 1b
9:  EPILOGUE

# FN ce_timeout() -> ms until ce_tick should look again: soon while a request waits
FN ce_timeout
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp dword ptr [rax + CE_want], 0
    jne 2f
    cmp qword ptr [rax + CE_req], 0
    je 1b
    mov eax, 500
    ret
2:  mov eax, 50
    ret
8:  mov rax, -1
    ret

# ---------------- the extension's answers ----------------

# FN ce_reply(ext, id, ok, ptr, len) -> eax 1 when it answered an editor's request. An error's
#   bytes are its CODE TEXT.
FN ce_reply
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], edx
    mov r14, rcx
    mov r15, r8
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 8f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rbx, [rax + rcx*8]
    inc rcx
    cmp [rbx + CE_ext], r12
    jne 1b
    cmp [rbx + CE_req], r13
    jne 1b
    mov eax, [rbx + CE_reqkind]
    mov [rsp + 8], eax
    mov qword ptr [rbx + CE_req], 0
    mov dword ptr [rbx + CE_reqkind], 0
    mov rdi, r12
    mov rsi, r13
    call ext_reply_cap_drop
    mov eax, [rsp + 8]
    cmp eax, CER_OPEN
    jne 2f
    cmp dword ptr [rsp], 0
    jne 11f
    mov rdi, rbx                # refused: the file opens as text, the reason in a toast
    mov rsi, r14
    mov rdx, r15
    call ce_why
    mov rsi, rax
    mov rdi, rbx
    call ce_open_failed
    jmp 7f
11: mov dword ptr [rbx + CE_state], CES_READY
    mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rbx + CE_restore], 0
    je 7f
    mov rdi, rbx                # its backup's bytes differ from the file's
    mov esi, 1
    call ce_set_dirty
    mov dword ptr [rbx + CE_bkdone], 1
    jmp 7f
2:  cmp eax, CER_SAVE
    jne 7f
    cmp dword ptr [rsp], 0
    jne 21f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call ce_why
    mov rdi, rax
    call app_toast
    mov rdi, rbx
    mov rsi, -5
    call ce_save_done
    jmp 7f
21: mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call ce_save_part
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_why(ce, ptr, len) -> rax "Hex Editor: TEXT" for a toast (msg), from an error's CODE TEXT
ce_why:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rip + msg]
    call sb_clear
    mov rdi, [rbx + CE_ext]
    mov esi, EXT_pv_edtitle
    call ext_pv
    test rax, rax
    jnz 1f
    mov rax, [rbx + CE_ext]
    mov rax, [rax + EXT_title]
1:  mov rsi, rax
    lea rdi, [rip + msg]
    call sb_push_cstr
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    # the text after the code
    xor ecx, ecx
2:  cmp rcx, r13
    jae 3f
    cmp byte ptr [r12 + rcx], ' '
    je 4f
    inc rcx
    jmp 2b
4:  inc rcx
    jmp 5f
3:  xor ecx, ecx
5:  lea rsi, [r12 + rcx]
    mov rdx, r13
    sub rdx, rcx
    cmp rdx, 200
    jbe 6f
    mov edx, 200
6:  lea rdi, [rip + msg]
    call sb_push
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + msg + SB_ptr]
    EPILOGUE

# ---------------- saving an owned model ----------------

# FN ce_save_start(doc, flags, fn, arg) -> 1 started (fn(doc id, arg, result) follows), else -errno:
#   the save_start contract for an owned model's stand-in. Save As has set the new path already.
FN ce_save_start
    PROLOGUE
    mov rbx, [rdi + DOC_ce]
    mov r12, rdx
    mov r13, rcx
    test rbx, rbx
    jz 7f
    cmp dword ptr [rbx + CE_state], CES_READY
    jne 6f
    cmp qword ptr [rbx + CE_req], 0
    jne 6f
    cmp qword ptr [rbx + CE_target], 0      # a save in progress
    jne 6f
    mov [rbx + CE_savefn], r12
    mov [rbx + CE_savearg], r13
    mov rax, [rbx + CE_doc]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz 5f
    call dup_cstr
    mov [rbx + CE_target], rax
    # Save As when the path is not the one the extension knows
    mov dword ptr [rbx + CE_skind], CEK_SAVE
    mov rdi, [rbx + CE_target]
    mov rsi, [rbx + CE_path]
    call strcmp_eq
    test eax, eax
    jnz 1f
    mov dword ptr [rbx + CE_skind], CEK_SAVEAS
1:  lea rdi, [rbx + CE_buf]
    call sb_clear
    mov qword ptr [rbx + CE_part], 0
    mov rdi, rbx
    call ce_ask_part
    test rax, rax
    jz 4f
    mov eax, 1
    EPILOGUE
4:  mov rdi, rbx
    mov rsi, -32
    call ce_save_done
    mov eax, 1
    EPILOGUE
5:  mov qword ptr [rbx + CE_savefn], 0
7:  mov rax, -22
    EPILOGUE
6:  lea rdi, [rip + .Lbusy]
    call app_toast
    mov rax, -16
    EPILOGUE

# ce_ask_part(ce) -> rax the id of "ID editor-save CDOC KIND PART", or 0
ce_ask_part:
    PROLOGUE
    mov rbx, rdi
    call ce_send_save
    test rax, rax
    jz 9f
    mov [rbx + CE_req], rax
    mov dword ptr [rbx + CE_reqkind], CER_SAVE
    push rax
    push rax
    call time_ms
    mov [rbx + CE_reqat], rax
    pop rax
    pop rax
9:  EPILOGUE

# ce_save_part(ce, ptr, len): an editor-save answer: "MORE" LF then the part's bytes; the next part
#   is asked for, or the bytes are written
ce_save_part:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    # MORE
    xor ecx, ecx
1:  cmp rcx, r13
    jae .Lsp_bad
    cmp byte ptr [r12 + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  cmp rcx, 1
    jne .Lsp_bad
    movzx r14d, byte ptr [r12]
    sub r14d, '0'
    cmp r14d, 1
    ja .Lsp_bad
    lea rsi, [r12 + 2]
    lea rdx, [r13 - 2]
    cmp rdx, CE_PART_MAX
    ja .Lsp_bad
    mov rax, [rbx + CE_buf + SB_len]
    add rax, rdx
    cmp rax, CE_SAVE_MAX
    ja .Lsp_big
    lea rdi, [rbx + CE_buf]
    call sb_push
    test r14d, r14d
    jz 3f
    inc qword ptr [rbx + CE_part]
    mov rdi, rbx
    call ce_ask_part
    test rax, rax
    jnz 9f
    mov rdi, rbx
    mov rsi, -32
    call ce_save_done
    EPILOGUE
3:  # the last part: the file replaced at once (a temporary file renamed over it); a backup in
    # rhun's state folder, with the file's path beside it
    cmp dword ptr [rbx + CE_skind], CEK_BACKUP
    jne 31f
    mov rdi, [rbx + CE_target]
    mov rsi, [rbx + CE_buf + SB_ptr]
    mov rdx, [rbx + CE_buf + SB_len]
    call file_write_all
    test rax, rax
    jnz 32f
    push rax
    push rax
    mov rdi, rbx
    call ce_backup_note
    pop rax
    pop rax
    jmp 32f
31: mov rdi, [rbx + CE_target]
    mov rsi, [rbx + CE_buf + SB_ptr]
    mov rdx, [rbx + CE_buf + SB_len]
    call vfs_write_all
32: mov rsi, rax
    mov rdi, rbx
    call ce_save_done
9:  EPILOGUE
.Lsp_big:
    lea rdi, [rip + .Ltoo_big]
    call app_toast
    mov rdi, rbx
    mov rsi, -27
    call ce_save_done
    EPILOGUE
.Lsp_bad:
    lea rdi, [rip + .Lbad_part]
    call app_toast
    mov rdi, rbx
    mov rsi, -5
    call ce_save_done
    EPILOGUE

# ce_save_done(ce, result): the save in progress ends (0 written, else -errno): when written the
#   stand-in is clean and a new path is told to the extension; then the caller's callback
ce_save_done:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rbx + CE_buf]
    call sb_free
    cmp qword ptr [rbx + CE_target], 0      # no save in progress
    je 9f
    cmp dword ptr [rbx + CE_skind], CEK_BACKUP
    jne 1f
    test r12, r12               # a backup: it holds what is shown (nothing else changes)
    jnz 2f
    mov dword ptr [rbx + CE_bkdone], 1
    jmp 2f
1:  test r12, r12
    jnz 2f
    mov dword ptr [rbx + CE_restore], 0
    mov rdi, rbx
    call ce_backup_drop
    mov dword ptr [rbx + CE_dirty], 0
    mov rax, [rbx + CE_doc]
    mov qword ptr [rax + DOC_savepoint], 0
    mov rdi, [rax + DOC_path]
    call vfs_stamp
    mov rcx, [rbx + CE_doc]
    mov [rcx + DOC_mtime], rax
    cmp dword ptr [rbx + CE_skind], CEK_SAVEAS
    jne 2f
    mov rdi, [rbx + CE_path]
    call mem_free
    mov rdi, [rbx + CE_target]
    call dup_cstr
    mov [rbx + CE_path], rax
    mov rdi, rbx
    call ce_send_path
2:  mov rdi, [rbx + CE_target]
    call mem_free
    mov qword ptr [rbx + CE_target], 0
    cmp dword ptr [rbx + CE_skind], CEK_BACKUP
    je 9f
    mov rax, [rbx + CE_savefn]
    mov qword ptr [rbx + CE_savefn], 0
    test rax, rax
    jz 9f
    mov rcx, [rbx + CE_doc]
    mov rdi, [rcx + DOC_id]
    mov rsi, [rbx + CE_savearg]
    mov rdx, r12
    call rax
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN ce_set_dirty(ce, dirty): editor-dirty: the dot and the close question follow it; a dirty model
#   is backed up 30 s later (B3), a clean one's backup goes
FN ce_set_dirty
    PROLOGUE
    mov rbx, rdi
    mov [rbx + CE_dirty], esi
    mov rax, [rbx + CE_doc]
    xor ecx, ecx
    test esi, esi
    jz 1f
    mov rcx, -1
1:  mov [rax + DOC_savepoint], rcx
    mov dword ptr [rbx + CE_bkdone], 0
    test esi, esi
    jz 2f
    call time_ms
    mov [rbx + CE_dirtyat], rax
    jmp 3f
2:  mov rdi, rbx
    call ce_backup_drop
3:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- backups of owned models (B3) ----------------

# ce_backup_path(ce, suffix cstr) -> rax "STATE/backups/HASH" + suffix (msg), the folder made (0700),
#   or 0 without a state folder. HASH names the file's path.
ce_backup_path:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + msg]
    call session_state_dir
    test eax, eax
    jz 8f
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lbackups]
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    mov esi, 0700
    call ce_mkdir
    dec qword ptr [rip + msg + SB_len]
    lea rdi, [rip + msg]
    mov esi, '/'
    call sb_push_byte
    # FNV-1a of the path, 16 hex digits
    mov rdi, [rbx + CE_path]
    mov rax, 0xcbf29ce484222325
    mov rcx, 0x100000001b3
1:  movzx edx, byte ptr [rdi]
    test edx, edx
    jz 2f
    xor rax, rdx
    imul rax, rcx
    inc rdi
    jmp 1b
2:  mov r13, rax
    mov r14d, 60
3:  mov rax, r13
    mov ecx, r14d
    shr rax, cl
    and eax, 15
    lea rcx, [rip + .Lhex]
    movzx esi, byte ptr [rcx + rax]
    lea rdi, [rip + msg]
    call sb_push_byte
    sub r14d, 4
    jns 3b
    lea rdi, [rip + msg]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + msg + SB_ptr]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_mkdir(path, mode): the folder (and its parents), then its mode
ce_mkdir:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call mkdir_p
    mov rdi, rbx
    mov esi, r12d
    SYS SYS_chmod
    EPILOGUE

# ce_backup_due(ce): a dirty owned model whose backup is 30 s due (and rhun waits on nothing of
#   it) is asked for its bytes: editor-save CDOC backup PART, into the backup
ce_backup_due:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 9f
    cmp dword ptr [rbx + CE_state], CES_READY
    jne 9f
    cmp dword ptr [rbx + CE_dirty], 0
    je 9f
    cmp dword ptr [rbx + CE_bkdone], 0
    jne 9f
    cmp qword ptr [rbx + CE_req], 0
    jne 9f
    cmp qword ptr [rbx + CE_target], 0
    jne 9f
    call time_ms
    sub rax, [rbx + CE_dirtyat]
    cmp rax, CE_BACKUP_MS
    jb 9f
    mov rdi, rbx
    lea rsi, [rip + .Lempty]
    call ce_backup_path
    test rax, rax
    jz 9f
    mov rdi, rax
    call dup_cstr
    mov [rbx + CE_target], rax
    mov dword ptr [rbx + CE_skind], CEK_BACKUP
    mov qword ptr [rbx + CE_savefn], 0
    lea rdi, [rbx + CE_buf]
    call sb_clear
    mov qword ptr [rbx + CE_part], 0
    mov rdi, rbx
    call ce_ask_part
    test rax, rax
    jnz 9f
    mov rdi, [rbx + CE_target]
    call mem_free
    mov qword ptr [rbx + CE_target], 0
9:  EPILOGUE

# ce_backup_note(ce): HASH.path beside the backup: the file it is for
ce_backup_note:
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lpath_suffix]
    call ce_backup_path
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, [rbx + CE_path]
    call strlen
    mov rdx, rax
    mov rdi, r12
    mov rsi, [rbx + CE_path]
    call file_write_all
9:  EPILOGUE

# ce_backup_exists(ce) -> eax 1 when a backup of its file is there (its .path names the file)
ce_backup_exists:
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lpath_suffix]
    call ce_backup_path
    test rax, rax
    jz 8f
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 8f
    mov r12, rax
    mov r13, rdx
    mov rdi, [rbx + CE_path]
    call strlen
    xor r14d, r14d
    cmp rax, r13
    jne 1f
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + CE_path]
    call str_eq_cstr
    mov r14d, eax
1:  mov rdi, r12
    call mem_free
    mov eax, r14d
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ce_backup_drop(ce): an owned model's backup and its .path go
FN ce_backup_drop
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 9f
    lea rsi, [rip + .Lempty]
    call ce_backup_path
    test rax, rax
    jz 9f
    mov rdi, rax
    SYS SYS_unlink
    mov rdi, rbx
    lea rsi, [rip + .Lpath_suffix]
    call ce_backup_path
    test rax, rax
    jz 9f
    mov rdi, rax
    SYS SYS_unlink
9:  EPILOGUE

# FN ce_restore(ce): a stopped editor's extension starts again and opens the backup (SOURCE backup)
FN ce_restore
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_state], CES_STOPPED
    jne 9f
    mov dword ptr [rbx + CE_state], CES_OPENING
    mov dword ptr [rbx + CE_restore], 1
    mov dword ptr [rbx + CE_want], CER_OPEN
    call time_ms
    mov [rbx + CE_reqat], rax
    mov rdi, [rbx + CE_ext]
    call ce_ext_wake
    mov rdi, rbx
    call ce_pump
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN ce_read_path(ce) -> rax the path editor-read reads: its backup while it opened one, else the file
FN ce_read_path
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_restore], 0
    je 1f
    lea rsi, [rip + .Lempty]
    call ce_backup_path
    test rax, rax
    jnz 9f
1:  mov rax, [rbx + CE_doc]
    mov rax, [rax + DOC_path]
9:  EPILOGUE

# FN ce_draw_tab(x, y, w, h) -> eax 1 when it drew the active tab: a stopped editor's notice and
#   its Restore Unsaved Changes button (else the view draws)
FN ce_draw_tab
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    call ce_active
    test rax, rax
    jz 8f
    cmp dword ptr [rax + CE_state], CES_STOPPED
    jne 8f
    mov rbx, rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_BG
    call gfx_fill
    # "Hex Editor stopped"
    lea rdi, [rip + msg]
    call sb_clear
    mov rdi, [rbx + CE_ext]
    mov esi, EXT_pv_edtitle
    call ext_pv
    test rax, rax
    jnz 1f
    mov rax, [rbx + CE_ext]
    mov rax, [rax + EXT_title]
1:  mov rsi, rax
    lea rdi, [rip + msg]
    call sb_push_cstr
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lstopped]
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov eax, [rsp + 12]
    shr eax, 1
    sub eax, [rip + g_mt + 4*MI_40]
    add eax, [rsp + 4]
    mov [rsp + 16], eax
    COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 16]
    mov ecx, [rsp + 16 + 8]
    M r8d, MI_32
    mov r9, [rip + msg + SB_ptr]
    call ui_text_center
    add rsp, 16
    # the button
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lrestore_text]
    mov rdx, 23
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov r12d, eax
    mov esi, [rsp + 8]
    sub esi, r12d
    shr esi, 1
    add esi, [rsp]
    mov r13d, esi
    mov edx, [rsp + 16]
    add edx, [rip + g_mt + 4*MI_40]
    mov r14d, edx
    mov edi, ID_CE_RESTORE
    mov ecx, r12d
    M r8d, MI_32
    call ui_btn
    mov r15d, eax
    test eax, UB_CLICK
    jz 2f
    mov rdi, rbx
    call ce_restore
2:  mov edi, r13d
    mov esi, r14d
    mov edx, r12d
    M ecx, MI_32
    M r8d, MI_RADIUS
    COLOR r9d, T_PANEL
    test r15d, UB_HOVER
    jz 3f
    COLOR r9d, T_HOVER
3:  call gfx_round_rect
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r13d
    mov edx, r14d
    mov ecx, r12d
    M r8d, MI_32
    lea r9, [rip + .Lrestore_text]
    call ui_text_center
    add rsp, 16
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- commands in a custom editor's tab ----------------

# FN ce_undo(), ce_redo(): Undo and Redo while a custom editor's tab is active: the text model's
#   document, or the extension's model (editor-undo, editor-redo)
FN ce_undo
    lea rsi, [rip + .Lv_undo]
    lea rdx, [rip + doc_undo]
    jmp ce_cmd
FN ce_redo
    lea rsi, [rip + .Lv_redo]
    lea rdx, [rip + doc_redo]
ce_cmd:
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call ce_active
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    je 1f
    mov rdi, [rbx + CE_doc]
    call r13
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, r12
    call ce_send_cmd
9:  EPILOGUE

# FN ce_revert(doc) -> eax 1 when Revert File was an owned model's: editor-revert goes to it
FN ce_revert
    PROLOGUE
    mov rbx, [rdi + DOC_ce]
    test rbx, rbx
    jz 8f
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 8f
    mov rdi, rbx
    lea rsi, [rip + .Lv_revert]
    call ce_send_cmd
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ce_disk_changed(doc) -> eax 1 when the file of an owned model changed on disk: the extension
#   hears editor-changed (a clean model reloads, a dirty one is its call) and the stamp is taken
FN ce_disk_changed
    PROLOGUE
    mov rbx, [rdi + DOC_ce]
    test rbx, rbx
    jz 8f
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 8f
    mov rax, [rbx + CE_doc]
    mov rdi, [rax + DOC_path]
    call vfs_stamp
    mov rcx, [rbx + CE_doc]
    mov [rcx + DOC_mtime], rax
    mov rdi, rbx
    call ce_send_changed
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ce_send_cmd(ce, verb cstr): "ID editor-undo CDOC" (and redo, revert), when no other waits
ce_send_cmd:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + CE_state], CES_READY
    jne 9f
    cmp qword ptr [rbx + CE_req], 0
    jne 9f
    call ce_send_verb
    test rax, rax
    jz 9f
    mov [rbx + CE_req], rax
    mov dword ptr [rbx + CE_reqkind], CER_CMD
    call time_ms
    mov [rbx + CE_reqat], rax
9:  EPILOGUE

# ---------------- Reopen With ----------------

# FN cmd_reopen_with(): the active file's editors in a pick list: Text, then each extension's
FN cmd_reopen_with
    PROLOGUE
    call app_active_path
    test rax, rax
    jz 9f
    mov rdi, rax
    call dup_cstr
    mov rdi, [rip + pick_path]
    mov [rip + pick_path], rax
    call mem_free
    mov qword ptr [rip + picks + VEC_len], 0
    lea rdi, [rip + .Lreopen_label]
    call palette_reopen_open
    lea rdi, [rip + picks]
    mov esi, 8
    call vec_push
    mov qword ptr [rax], 0
    lea rdi, [rip + .Ltext_row]
    call strlen
    mov rsi, rax
    lea rdi, [rip + .Ltext_row]
    xor edx, edx
    call palette_choose_add
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 3f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    mov rsi, [rip + pick_path]
    call ce_ext_matches
    test eax, eax
    jz 1b
    lea rdi, [rip + picks]
    mov esi, 8
    call vec_push
    mov [rax], rbx
    lea rdi, [rip + msg]
    call sb_clear
    mov rdi, rbx
    mov esi, EXT_pv_edtitle
    call ext_pv
    test rax, rax
    jnz 2f
    mov rax, [rbx + EXT_title]
2:  mov rsi, rax
    lea rdi, [rip + msg]
    call sb_push_cstr
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lopen_paren]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + msg]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov esi, ')'
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    mov rsi, [rip + msg + SB_len]
    mov rdx, [rip + picks + VEC_len]
    dec rdx
    call palette_choose_add
    jmp 1b
3:  call palette_choose_ready
9:  EPILOGUE

# FN ce_reopen_chosen(n): row n of Reopen With: the choice for files like this one, and the file
#   opens again with it (a tab with changes keeps them: it says to save first)
FN ce_reopen_chosen
    PROLOGUE
    cmp rdi, [rip + picks + VEC_len]
    jae 9f
    mov rax, [rip + picks + VEC_ptr]
    mov rdi, [rax + rdi*8]
    call ce_reopen_with
9:  EPILOGUE

# ce_reopen_with(ext or 0 for Text): see ce_reopen_chosen
ce_reopen_with:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + pick_path]
    test r12, r12
    jz 9f
    test rbx, rbx
    jnz 1f
    mov rdi, r12
    lea rsi, [rip + .Ltext]
    call ce_choose
    jmp 2f
1:  lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + msg]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    call dup_cstr
    mov r13, rax
    mov rdi, r12
    mov rsi, r13
    call ce_choose
    mov rdi, r13
    call mem_free
2:  # the file's tab closes and the file opens again
    mov rdi, r12
    call app_find_tab
    test rax, rax
    js 4f
    mov r13, rax
    mov rdi, rax
    call tab_at
    mov rdi, rax
    call tab_dirty
    test eax, eax
    jz 3f
    lea rdi, [rip + .Lsave_first]
    call app_toast
    EPILOGUE
3:  mov rdi, r13
    call app_close_tab_now
4:  mov rdi, r12
    test rbx, rbx
    jnz 5f
    mov dword ptr [rip + g_nb_open_text], 1     # Text means text, for a notebook too
5:  call app_open_file
    mov dword ptr [rip + g_nb_open_text], 0
9:  EPILOGUE

# app_active_path() -> the active tab's file path, or 0
app_active_path:
    sub rsp, 8
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 8f
    call tab_at
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    mov rax, [rax + DOC_path]
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret

# ---------------- headless controls (control.s's ctl_tables) ----------------

# print-custom: "cdoc=ID ext=OWNER/NAME model=text|owned dirty=D path=P view=V state=opening|ready"
#   per custom editor; reopen-with NAME|text: as Reopen With's row
c_print_custom:
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + g_ces + VEC_len]
    jae 9f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rbx, [rax + r13*8]
    inc r13
    mov rdi, r12
    lea rsi, [rip + .Ld_cdoc]
    call sb_push_cstr
    mov rax, [rbx + CE_doc]
    mov rdi, r12
    mov rsi, [rax + DOC_id]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_ext]
    call sb_push_cstr
    mov rax, [rbx + CE_ext]
    mov rdi, r12
    mov rsi, [rax + EXT_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rax, [rbx + CE_ext]
    mov rdi, r12
    mov rsi, [rax + EXT_name]
    call sb_push_cstr
    lea rsi, [rip + .Ld_text]
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 2f
    lea rsi, [rip + .Ld_owned]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_dirty]
    call sb_push_cstr
    mov rdi, [rbx + CE_doc]
    call doc_dirty
    mov rsi, rax
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_path]
    call sb_push_cstr
    mov rax, [rbx + CE_doc]
    mov rsi, [rax + DOC_path]
    test rsi, rsi
    jnz 3f
    lea rsi, [rip + .Ldash]
3:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_view]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + CE_vid]
    call sb_push_u64
    lea rsi, [rip + .Ld_opening]
    cmp dword ptr [rbx + CE_state], CES_READY
    jne 41f
    lea rsi, [rip + .Ld_ready]
41: cmp dword ptr [rbx + CE_state], CES_STOPPED
    jne 4f
    lea rsi, [rip + .Ld_stopped]
4:  mov rdi, r12
    call sb_push_cstr
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# custom-backup: the backups due in 30 s are taken now; custom-restore: the active stopped editor
#   opens its backup, as its button does
c_custom_backup:
    PROLOGUE
    xor ecx, ecx
1:  cmp rcx, [rip + g_ces + VEC_len]
    jae 9f
    mov rax, [rip + g_ces + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    mov qword ptr [rax + CE_dirtyat], 0
    jmp 1b
9:  call ce_tick
    xor eax, eax
    EPILOGUE

c_custom_restore:
    PROLOGUE
    call ce_active
    test rax, rax
    jz 9f
    mov rdi, rax
    call ce_restore
9:  xor eax, eax
    EPILOGUE

c_reopen_with:
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call app_active_path
    test rax, rax
    jz 9f
    mov rdi, rax
    call dup_cstr
    mov rdi, [rip + pick_path]
    mov [rip + pick_path], rax
    call mem_free
    # "text", else OWNER/NAME
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    lea rsi, [rip + .Ltext]
    call strcmp_eq
    xor ebx, ebx
    test eax, eax
    jnz 1f
    mov rdi, [rip + msg + SB_ptr]
    call dup_cstr
    mov r14, rax
    mov rdi, rax
    call ce_ext_named
    mov rbx, rax
    mov rdi, r14
    call mem_free
    test rbx, rbx
    jz 9f
1:  mov rdi, rbx
    call ce_reopen_with
9:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
.globl ce_ctl
ce_ctl:
    .quad .Lc_print_custom, c_print_custom, .Lc_reopen_with, c_reopen_with
    .quad .Lc_custom_backup, c_custom_backup, .Lc_custom_restore, c_custom_restore
    .quad 0, 0
.Lc_print_custom: .asciz "print-custom"
.Lc_reopen_with: .asciz "reopen-with"
.Lc_custom_backup: .asciz "custom-backup"
.Lc_custom_restore: .asciz "custom-restore"
.Lbackups: .asciz "/backups"
.Lpath_suffix: .asciz ".path"
.Lempty: .asciz ""
.Lhex: .ascii "0123456789abcdef"
.Lstopped: .asciz " stopped. Its unsaved changes are kept."
.Lrestore_text: .asciz "Restore Unsaved Changes"
.Ld_stopped: .asciz " state=stopped\n"
.Lowned: .asciz "owned"
.Loption: .asciz "option"
.Ltext: .asciz "text"
.Lsec: .asciz "\n[editors]\n"
.Leq: .asciz " = "
.Lcolon: .asciz ": "
.Lopen_paren: .asciz " ("
.Ldash: .asciz "-"
.Ltext_row: .asciz "Text"
.Lreopen_label: .asciz "Reopen the file with"
.Lv_undo: .asciz "editor-undo"
.Lv_redo: .asciz "editor-redo"
.Lv_revert: .asciz "editor-revert"
.Lcannot_read: .asciz "The file cannot be read"
.Lno_view: .asciz "Too many extension views are open"
.Lno_feature: .asciz "The editor's extension does not offer custom-editors: the file opens as text"
.Lno_send: .asciz "The editor's extension is not running: the file opens as text"
.Lno_answer: .asciz "The editor's extension did not answer: the file opens as text"
.Lbusy: .asciz "The editor is busy: try again"
.Ltoo_big: .asciz "The file is too big to save (1 GB)"
.Lbad_part: .asciz "The editor's extension sent a part rhun cannot read: the file was not saved"
.Lsave_first: .asciz "Save the file first"
.Ld_cdoc: .asciz "cdoc="
.Ld_ext: .asciz " ext="
.Ld_text: .asciz " model=text"
.Ld_owned: .asciz " model=owned"
.Ld_dirty: .asciz " dirty="
.Ld_path: .asciz " path="
.Ld_view: .asciz " view="
.Ld_opening: .asciz " state=opening\n"
.Ld_ready: .asciz " state=ready\n"

.bss
.globl ce_open_text
ce_open_text: .long 0           # 1 while a file opens as text whatever its editors say
