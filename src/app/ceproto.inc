# Included in extproto.s: the custom-editors feature's messages (docs/extensions/v1.1.md, "Feature:
# custom-editors"). rhun asks editor-open, editor-save (in parts), editor-undo, editor-redo and
# editor-revert, tells editor-closed, editor-changed and editor-path, and handles editor-read and
# editor-dirty. customed.s keeps the editors.

.bss
.p2align 3
ceq: .zero SB_SIZE              # a request's or event's line

.text

# ce_line_begin(ext, verb cstr, ce) -> rax the new request id (rhun's own ids), with ceq holding
#   "ID VERB CDOC"; rax 0 when the extension is not running
ce_line_begin:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    cmp qword ptr [rbx + EXT_hreq], 2147483647
    jae 9f
    inc qword ptr [rbx + EXT_hreq]
    mov r14, [rbx + EXT_hreq]
    lea rdi, [rip + ceq]
    call sb_clear
    lea rdi, [rip + ceq]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + ceq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ceq]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + ceq]
    mov esi, ' '
    call sb_push_byte
    mov rax, [r13 + CE_doc]
    lea rdi, [rip + ceq]
    mov rsi, [rax + DOC_id]
    call sb_push_u64
9:  mov rax, r14
    EPILOGUE

# ce_line_send(ext, id, kind): ceq (and LF) to the extension, the request tracked as kind
ce_line_send:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    lea rdi, [rip + ceq]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + ceq + SB_ptr]
    mov rdx, [rip + ceq + SB_len]
    call ext_send
    mov rdi, rbx                # counted with the other requests rhun waits on (query.s)
    mov rsi, r12
    mov edx, r13d
    mov ecx, QO_CUSTOM
    call query_track
    EPILOGUE

# FN ce_send_open(ce) -> rax the id of "ID editor-open CDOC VIEW MODEL SOURCE LEN" + path, or 0
FN ce_send_open
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CE_ext]
    mov rdi, r12
    lea rsi, [rip + .Lce_v_open]
    mov rdx, rbx
    call ce_line_begin
    test rax, rax
    jz 9f
    mov r13, rax
    lea rdi, [rip + ceq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ceq]
    mov rsi, [rbx + CE_vid]
    call sb_push_u64
    lea rsi, [rip + .Lce_text]
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne 1f
    lea rsi, [rip + .Lce_owned]
1:  lea rdi, [rip + ceq]
    call sb_push_cstr
    lea rdi, [rip + ceq]
    lea rsi, [rip + .Lce_file]
    call sb_push_cstr
    mov rdi, [rbx + CE_path]
    call strlen
    mov r14, rax
    lea rdi, [rip + ceq]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + ceq]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + ceq]
    mov rsi, [rbx + CE_path]
    mov rdx, r14
    call sb_push
    mov rdi, r12
    mov rsi, [rip + ceq + SB_ptr]
    mov rdx, [rip + ceq + SB_len]
    call ext_send
    mov rdi, r12
    mov rsi, r13
    mov edx, PK_ED_OPEN
    mov ecx, QO_CUSTOM
    call query_track
    # its view's size and metrics went out before the extension ran: they go again, after this
    mov rdi, r12
    mov esi, [rbx + CE_vid]
    call extview_find
    test rax, rax
    jz 1f
    mov dword ptr [rax + VW_lw], -1
    mov dword ptr [rax + VW_lh], -1
    mov dword ptr [rax + VW_scale], -1
    mov dword ptr [rip + g_dirty], 1
1:  mov rax, r13
9:  EPILOGUE

# FN ce_send_save(ce) -> rax the id of "ID editor-save CDOC KIND PART", or 0; its answer may carry a
#   part of 4 MB and its MORE line
FN ce_send_save
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CE_ext]
    mov rdi, r12
    lea rsi, [rip + .Lce_v_save]
    mov rdx, rbx
    call ce_line_begin
    test rax, rax
    jz 9f
    mov r13, rax
    mov eax, [rbx + CE_skind]
    lea rcx, [rip + ce_kind_names]
    mov rsi, [rcx + rax*8]
    lea rdi, [rip + ceq]
    call sb_push_cstr
    lea rdi, [rip + ceq]
    mov rsi, [rbx + CE_part]
    call sb_push_u64
    mov rdi, r12
    mov rsi, r13
    mov edx, CE_PART_MAX + 64
    call ext_reply_cap_set
    mov rdi, r12
    mov rsi, r13
    mov edx, PK_ED_SAVE
    call ce_line_send
    mov rax, r13
9:  EPILOGUE

# FN ce_send_verb(ce, verb cstr) -> rax the id of "ID VERB CDOC" (editor-undo, -redo, -revert), or 0
FN ce_send_verb
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CE_ext]
    mov rdi, r12
    mov rdx, rbx
    call ce_line_begin
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, r12
    mov rsi, r13
    mov edx, PK_ED_CMD
    call ce_line_send
    mov rax, r13
9:  EPILOGUE

# ce_event(ce, verb cstr, ptr, len): "0 VERB CDOC" (with " LEN" and the bytes when ptr is not 0) to
#   the extension, when it runs and agreed custom-editors
ce_event:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, [rbx + CE_ext]
    mov rdi, r15
    call ext_is_visible
    test eax, eax
    jz 9f
    cmp dword ptr [r15 + EXT_status], ES_RUNNING
    jne 9f
    FEAT_TEST r15, FEAT_CUSTOM_EDITORS
    jz 9f
    lea rdi, [rip + ceq]
    call sb_clear
    lea rdi, [rip + ceq]
    lea rsi, [rip + .Lce_zero]
    call sb_push_cstr
    lea rdi, [rip + ceq]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + ceq]
    mov esi, ' '
    call sb_push_byte
    mov rax, [rbx + CE_doc]
    lea rdi, [rip + ceq]
    mov rsi, [rax + DOC_id]
    call sb_push_u64
    test r13, r13
    jz 1f
    lea rdi, [rip + ceq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ceq]
    mov rsi, r14
    call sb_push_u64
1:  lea rdi, [rip + ceq]
    mov esi, 10
    call sb_push_byte
    test r13, r13
    jz 2f
    lea rdi, [rip + ceq]
    mov rsi, r13
    mov rdx, r14
    call sb_push
2:  mov rdi, r15
    mov rsi, [rip + ceq + SB_ptr]
    mov rdx, [rip + ceq + SB_len]
    call ext_send
9:  EPILOGUE

# FN ce_send_closed(ce), ce_send_changed(ce): "0 editor-closed CDOC", "0 editor-changed CDOC"
FN ce_send_closed
    lea rsi, [rip + .Lce_v_closed]
    xor edx, edx
    xor ecx, ecx
    jmp ce_event
FN ce_send_changed
    lea rsi, [rip + .Lce_v_changed]
    xor edx, edx
    xor ecx, ecx
    jmp ce_event

# FN ce_send_path(ce): "0 editor-path CDOC LEN" + the path a Save As gave it
FN ce_send_path
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + CE_path]
    call strlen
    mov rcx, rax
    mov rdi, rbx
    lea rsi, [rip + .Lce_v_path]
    mov rdx, [rbx + CE_path]
    call ce_event
    pop rbx
    ret

# ---------------- requests from the extension ----------------

# ce_arg() -> rax the CE named by field 2 (CDOC), one of this extension's; rax 0 when the reply went
#   out (unknown, syntax, stale)
ce_arg:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_CUSTOM_EDITORS
    jz .Lca_unknown
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lca_syntax
    mov rdi, [rip + cur]
    mov rsi, rax
    call ce_by_cdoc
    test rax, rax
    jz .Lca_stale
    EPILOGUE
.Lca_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    xor eax, eax
    EPILOGUE
.Lca_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    xor eax, eax
    EPILOGUE
.Lca_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lce_e_stale]
    call reply_error
    xor eax, eax
    EPILOGUE

# ID editor-read CDOC OFFSET MAX -> ok ID LEN + up to MAX (4 MB at most) bytes of the file from
#   OFFSET; LEN 0 at its end
h_ed_read:
    PROLOGUE
    cmp qword ptr [rip + nfields], 5
    jne .Ler_syntax
    call ce_arg
    test rax, rax
    jz 9f
    mov rbx, rax
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Ler_syntax
    mov r12, rax
    mov edi, 4
    call field_u64
    test edx, edx
    jz .Ler_syntax
    mov r13, rax
    cmp r13, CE_READ_MAX
    jbe 1f
    mov r13d, CE_READ_MAX
1:  mov rax, [rbx + CE_doc]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz .Ler_nofile
    mov rsi, r12
    mov rdx, r13
    call vfs_read_at
    test rax, rax
    jz .Ler_nofile
    mov r14, rax
    mov r15, rdx
    call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rip + cur_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r15
    call out_u64
    mov edi, 10
    call out_byte
    mov rdi, r14
    mov rsi, r15
    call out_bytes
    call out_end
    mov rdi, r14
    call mem_free
9:  EPILOGUE
.Ler_nofile:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lce_e_nofile]
    call reply_error
    EPILOGUE
.Ler_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID editor-dirty CDOC 0|1 -> ok ID: the dirty dot and the close question follow it
h_ed_dirty:
    PROLOGUE
    cmp qword ptr [rip + nfields], 4
    jne .Led_syntax
    call ce_arg
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + CE_model], CEM_OWNED
    jne .Led_refused
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Led_syntax
    cmp rax, 1
    ja .Led_syntax
    mov rdi, rbx
    mov esi, eax
    call ce_set_dirty
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Led_refused:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lce_e_text]
    call reply_error
    EPILOGUE
.Led_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

.section .rodata
.p2align 3
ce_kind_names: .quad .Lce_k_save, .Lce_k_saveas, .Lce_k_backup
.Lce_v_open: .asciz "editor-open"
.Lce_v_save: .asciz "editor-save"
.Lce_v_closed: .asciz "editor-closed"
.Lce_v_changed: .asciz "editor-changed"
.Lce_v_path: .asciz "editor-path"
.Lce_v_read: .asciz "editor-read"
.Lce_v_dirty: .asciz "editor-dirty"
.Lce_k_save: .asciz " save "
.Lce_k_saveas: .asciz " saveas "
.Lce_k_backup: .asciz " backup "
.Lce_text: .asciz " text"
.Lce_owned: .asciz " owned"
.Lce_file: .asciz " file "
.Lce_zero: .asciz "0 "
.Lce_e_stale: .asciz "stale no such editor"
.Lce_e_nofile: .asciz "nofile the file cannot be read"
.Lce_e_text: .asciz "refused a text model's dirty state is rhun's"
.text
