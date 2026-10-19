# More language features of protocol 1.1 (docs/extensions/v1.1.md): formatting as you type and
# pasted text (partial-format). Each keeps a small state of its own; answers arrive in extproto's
# pump (langfeat_reply hands them here first) and are acted on from the tick.
.include "rhun.inc"

.equ PP_RANGE_FORMAT_X, 10      # extproviders.s's kinds for range- and type-format (the formatter's
.equ PP_TYPE_FORMAT, 11         # choice)

.bss
.p2align 3
lx_line: .zero SB_SIZE          # a request being built
lx_fmt_ext: .quad 0             # an on-type or paste format request out: its extension, id,
lx_fmt_id: .quad 0              # document and version
lx_fmt_doc: .quad 0
lx_fmt_ver: .quad 0
lx_fmt_ready: .long 0           # its answer came
lx_fmt_pad: .long 0
lx_fmt_body: .zero SB_SIZE

.text

# lx_push_sp(), lx_push_num(n), lx_push_cstr(s): onto lx_line
lx_push_sp:
    lea rdi, [rip + lx_line]
    mov esi, ' '
    jmp sb_push_byte
lx_push_num:
    mov rsi, rdi
    lea rdi, [rip + lx_line]
    jmp sb_push_u64
lx_push_cstr:
    mov rsi, rdi
    lea rdi, [rip + lx_line]
    jmp sb_push_cstr

# lx_push_pos(doc, pos): " LINE COL"
lx_push_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    sub r12, rax
    call lx_push_sp
    lea rdi, [r13 + 1]
    call lx_push_num
    call lx_push_sp
    lea rdi, [r12 + 1]
    call lx_push_num
    EPILOGUE

# lx_push_options(doc): " TAB_WIDTH SPACES TRIM FINAL", the document's own
lx_push_options:
    PROLOGUE
    mov rbx, rdi
    call ext_options_apply
    call lx_push_sp
    mov edi, [rip + g_tab_width]
    call lx_push_num
    lea r12, [rip + .Lyes]
    lea r13, [rip + .Lno]
    call lx_push_sp
    mov rdi, r12
    cmp dword ptr [rip + g_insert_spaces], 0
    jne 1f
    mov rdi, r13
1:  call lx_push_cstr
    call lx_push_sp
    mov rdi, rbx
    mov esi, OPT_TRIM
    call ext_opt_bool
    mov rdi, r12
    test eax, eax
    jnz 2f
    mov rdi, r13
2:  call lx_push_cstr
    call lx_push_sp
    mov rdi, rbx
    mov esi, OPT_FINAL
    call ext_opt_bool
    mov rdi, r12
    test eax, eax
    jnz 3f
    mov rdi, r13
3:  call lx_push_cstr
    EPILOGUE

# lx_fmt_send(ext, doc, kind PK_*): lx_line to the formatter, the previous request withdrawn
lx_fmt_send:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call lx_fmt_withdraw
    mov edi, 1
    call query_room
    test eax, eax
    jz 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rip + lx_line + SB_ptr]
    mov rcx, [rip + lx_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz 9f
    mov [rip + lx_fmt_id], rax
    mov [rip + lx_fmt_ext], rbx
    mov rcx, [r12 + DOC_id]
    mov [rip + lx_fmt_doc], rcx
    mov rcx, [r12 + DOC_version]
    mov [rip + lx_fmt_ver], rcx
    mov dword ptr [rip + lx_fmt_ready], 0
    mov rdi, rbx
    mov rsi, rax
    mov edx, r13d
    mov ecx, QO_LANGFEAT
    call query_track
9:  EPILOGUE

lx_fmt_withdraw:
    push rbx
    mov rdi, [rip + lx_fmt_ext]
    test rdi, rdi
    jz 9f
    mov rsi, [rip + lx_fmt_id]
    mov qword ptr [rip + lx_fmt_ext], 0
    mov dword ptr [rip + lx_fmt_ready], 0
    call query_withdraw
9:  pop rbx
    ret

# FN langextra_typed(ch): a character went into the focused document (10 for Enter): with
# [editor] format_on_type, a trigger of the document's formatter asks it for an edit
# ("ID type-format DOC VERSION LINE COL CHAR TAB_WIDTH SPACES TRIM FINAL", CHAR newline for Enter)
FN langextra_typed
    PROLOGUE
    mov r12d, edi
    cmp dword ptr [rip + cfg_format_on_type], 0
    je 9f
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov edi, PP_TYPE_FORMAT
    mov rsi, rbx
    call ext_provider_running   # quietly: a saved or sole running formatter
    test rax, rax
    jz 9f
    mov r13, rax
    # one of its triggers? (the word newline stands for Enter)
    mov rdi, r13
    mov esi, EXT_pv_ttrig
    call ext_pv
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, r12d
    call lx_trigger_has
    test eax, eax
    jz 9f
    lea rdi, [rip + lx_line]
    call sb_clear
    lea rdi, [rip + .Lv_type_format]
    call lx_push_cstr
    mov rdi, [rbx + DOC_id]
    call lx_push_num
    call lx_push_sp
    mov rdi, [rbx + DOC_version]
    call lx_push_num
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lx_push_pos
    call lx_push_sp
    cmp r12d, 10
    jne 1f
    lea rdi, [rip + .Lnewline]
    call lx_push_cstr
    jmp 2f
1:  lea rdi, [rip + lx_line]
    mov esi, r12d
    call sb_push_byte
2:  mov rdi, rbx
    call lx_push_options
    mov rdi, r13
    mov rsi, rbx
    mov edx, PK_TYPE_FORMAT
    call lx_fmt_send
9:  EPILOGUE

# lx_trigger_has(list, ch) -> eax 1 when the space-separated list holds ch, or newline for 10
lx_trigger_has:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
1:  cmp byte ptr [rbx], 0
    je 8f
    cmp byte ptr [rbx], ' '
    jne 2f
    inc rbx
    jmp 1b
2:  xor r13d, r13d              # the word's length
3:  movzx eax, byte ptr [rbx + r13]
    test eax, eax
    jz 4f
    cmp eax, ' '
    je 4f
    inc r13
    jmp 3b
4:  cmp r12d, 10
    jne 5f
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [rip + .Lnewline]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    jmp 6f
5:  cmp r13, 1
    jne 6f
    movzx eax, byte ptr [rbx]
    cmp eax, r12d
    je 7f
6:  add rbx, r13
    jmp 1b
7:  mov eax, 1
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN langextra_paste(ptr, len): Paste into the editor; with [editor] format_on_paste the pasted
# lines are range-formatted by the document's formatter
FN langextra_paste
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + g_doc]
    xor r14d, r14d
    test rbx, rbx
    jz 1f
    mov rdi, rbx
    call ed_sel
    mov r14, rax                # where the pasted text starts
    mov rax, [rbx + DOC_version]
    mov [rsp], rax
1:  mov rdi, r12
    mov rsi, r13
    call ed_paste
    cmp dword ptr [rip + cfg_format_on_paste], 0
    je 9f
    test rbx, rbx
    jz 9f
    cmp rbx, [rip + g_doc]
    jne 9f
    mov rax, [rbx + DOC_version]
    cmp rax, [rsp]
    je 9f                       # nothing went in
    mov edi, PP_RANGE_FORMAT_X
    mov rsi, rbx
    call ext_provider_running
    test rax, rax
    jz 9f
    mov r15, rax
    # the whole lines from the paste's start to the cursor
    mov rdi, rbx
    mov rsi, r14
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, rax
    mov r13, [rbx + DOC_cur]
    lea rdi, [rip + lx_line]
    call sb_clear
    lea rdi, [rip + .Lv_range_format]
    call lx_push_cstr
    mov rdi, [rbx + DOC_id]
    call lx_push_num
    call lx_push_sp
    mov rdi, [rbx + DOC_version]
    call lx_push_num
    mov rdi, rbx
    mov rsi, r14
    call lx_push_pos
    mov rdi, rbx
    mov rsi, r13
    call lx_push_pos
    mov rdi, rbx
    call lx_push_options
    mov rdi, r15
    mov rsi, rbx
    mov edx, PK_RANGE_FORMAT
    call lx_fmt_send
9:  EPILOGUE

# FN langextra_reply(ext, id, ok, body, len) -> eax 1 when it answered one of these requests
# (from extproto's pump: state only)
FN langextra_reply
    cmp rdi, [rip + lx_fmt_ext]
    jne 8f
    cmp rsi, [rip + lx_fmt_id]
    jne 8f
    test rdi, rdi
    jz 8f
    push rbx
    push r12
    push r13
    mov r12, rcx
    mov r13, r8
    mov qword ptr [rip + lx_fmt_ext], 0
    test edx, edx
    jz 1f
    test r13, r13
    jz 1f
    lea rdi, [rip + lx_fmt_body]
    call sb_clear
    lea rdi, [rip + lx_fmt_body]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov dword ptr [rip + lx_fmt_ready], 1
    mov dword ptr [rip + g_dirty], 1
1:  pop r13
    pop r12
    pop rbx
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# FN langextra_tick(): an on-type or paste format answer is applied as its own undo step, only
# when the document is still at the version it was asked for (the edit names it); quietly
FN langextra_tick
    PROLOGUE
    cmp dword ptr [rip + lx_fmt_ready], 0
    je 9f
    mov dword ptr [rip + lx_fmt_ready], 0
    mov rdi, [rip + lx_fmt_doc]
    call extproto_doc
    test rax, rax
    jz 9f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rip + lx_fmt_ver]
    jne 9f                      # typed on meanwhile: dropped
    mov rdi, [rip + lx_fmt_body + SB_ptr]
    mov rsi, [rip + lx_fmt_body + SB_len]
    mov rdx, [rip + lx_fmt_doc]
    mov ecx, 1
    call ws_apply_document
9:  EPILOGUE

# FN langextra_timeout() -> 0 when an answer waits for the tick, else -1
FN langextra_timeout
    mov eax, -1
    cmp dword ptr [rip + lx_fmt_ready], 0
    je 1f
    xor eax, eax
1:  ret

# FN langextra_ext_gone(ext): its requests go
FN langextra_ext_gone
    cmp rdi, [rip + lx_fmt_ext]
    jne 1f
    mov qword ptr [rip + lx_fmt_ext], 0
1:  ret

.section .rodata
.Lv_type_format: .asciz "type-format "
.Lv_range_format: .asciz "range-format "
.Lnewline: .asciz "newline"
.Lyes: .asciz "yes"
.Lno: .asciz "no"
