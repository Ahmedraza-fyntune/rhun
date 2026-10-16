# extension protocol v1 (docs/extensions/v1.md): parsing what an extension writes, answering its
# requests, and telling it what changed. ext.s owns the processes and the pipes.
.include "rhun.inc"

.bss
.p2align 3
line: .zero SB_SIZE             # the message being handled, as a copy (the receive buffer may move)
out: .zero SB_SIZE              # the reply or event being built
fields: .zero 8 * 32            # ptr, len of each field of the line (up to 16)
nfields: .quad 0
cur: .quad 0                    # the EXT being served
cur_id: .quad 0                 # the request id
body_ptr: .quad 0               # its body
body_len: .quad 0
syntax_seen: .quad 0            # a syntax reply went out while handling this message
toast_buf: .zero 256

.text

# ---------------- reading ----------------

# extproto_pump(ext): handle every complete message in the receive buffer
FN extproto_pump
    PROLOGUE 16
    mov rbx, rdi
    mov [rip + cur], rbx
    call time_ms
    mov r15, rax                # this run's start: EXT_PUMP_MS at most
    # the window: a new one after EXT_WIN_MS; a window that hit a cap counts toward flooding,
    # one that did not ends the count
    mov rax, r15
    sub rax, [rbx + EXT_win_t0]
    cmp rax, EXT_WIN_MS
    jl .Lpp_next
    mov [rbx + EXT_win_t0], r15
    # a busy window (a fifth of a cap or more: 100 messages or 64 KB in 16 ms) counts; a quieter
    # one ends the count
    cmp qword ptr [rbx + EXT_win_msgs], EXT_WIN_MSGS / 5
    jae 8f
    cmp qword ptr [rbx + EXT_fbytes], EXT_WIN_BYTES / 4
    jae 8f
    mov dword ptr [rbx + EXT_flood], 0
    jmp 81f
8:  inc dword ptr [rbx + EXT_flood]
81: mov qword ptr [rbx + EXT_win_msgs], 0
    mov qword ptr [rbx + EXT_fbytes], 0
    mov dword ptr [rbx + EXT_win_hit], 0
.Lpp_next:
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    je 1f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
1:  # the caps
    cmp qword ptr [rbx + EXT_win_msgs], EXT_WIN_MSGS
    jae .Lpp_cap
    cmp qword ptr [rbx + EXT_fbytes], EXT_WIN_BYTES
    jae .Lpp_cap
    mov r12, [rbx + EXT_rbuf + SB_ptr]
    mov r13, [rbx + EXT_rbuf + SB_len]
    # a message waiting for its body
    mov rax, [rbx + EXT_body]
    test rax, rax
    jz 2f
    mov rcx, [rbx + EXT_body_len]
    cmp r13, rcx
    jb 9f
    mov [rip + body_ptr], r12
    mov [rip + body_len], rcx
    mov rdi, rax
    call strlen
    mov rdi, [rbx + EXT_body]
    mov rsi, rax
    call handle_line            # the saved line, now with its body
    mov rdi, [rbx + EXT_body]
    call mem_free
    mov qword ptr [rbx + EXT_body], 0
    mov rdi, [rbx + EXT_body_len]
    add [rbx + EXT_fbytes], rdi
    inc qword ptr [rbx + EXT_win_msgs]
    call consume
    jmp .Lpp_time
2:  # a complete line?
    xor ecx, ecx
3:  cmp rcx, r13
    jae 9f
    cmp byte ptr [r12 + rcx], 10
    je 4f
    inc rcx
    jmp 3b
4:  mov r14, rcx                # line length without LF
    mov rdx, rcx
    test rdx, rdx
    jz 5f
    cmp byte ptr [r12 + rdx - 1], 13
    jne 5f
    dec rdx
5:  # copy the line out first: handling it may change the buffer
    mov [rsp], rdx
    lea rdi, [rip + out]        # `out` is free until a reply is built
    call sb_clear
    lea rdi, [rip + out]
    mov rsi, r12
    mov rdx, [rsp]
    call sb_push
    lea rdi, [r14 + 1]
    add [rbx + EXT_fbytes], rdi
    inc qword ptr [rbx + EXT_win_msgs]
    call consume
    mov qword ptr [rip + body_ptr], 0
    mov qword ptr [rip + body_len], 0
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call handle_line
.Lpp_time:
    # one run takes EXT_PUMP_MS at most; the rest waits like a capped window (ext_tick resumes it)
    call time_ms
    sub rax, r15
    cmp rax, EXT_PUMP_MS
    jl .Lpp_next
.Lpp_cap:
    # the window's cap: the rest waits for the next window (ext_tick resumes it)
    mov dword ptr [rbx + EXT_win_hit], 1
    mov dword ptr [rbx + EXT_throttled], 1
    cmp dword ptr [rbx + EXT_out], 0
    jl 9f
    mov edi, [rbx + EXT_out]
    xor esi, esi
    call watch_set_events
9:  EPILOGUE

# consume(n): drop n bytes from the front of rbx's receive buffer
consume:
    push rbx
    push rdi
    mov rax, [rbx + EXT_rbuf + SB_len]
    sub rax, rdi
    mov rsi, [rbx + EXT_rbuf + SB_ptr]
    add rsi, rdi
    mov rdi, [rbx + EXT_rbuf + SB_ptr]
    mov rdx, rax
    push rax
    push rax
    call memmove
    pop rax
    pop rax
    mov [rbx + EXT_rbuf + SB_len], rax
    pop rdi
    pop rbx
    ret

# split(ptr, len): fields[] from the line; a field is a run of non-space bytes
split:
    xor ecx, ecx
    mov [rip + nfields], rcx
    lea r8, [rip + fields]
    add rsi, rdi                # end
1:  cmp rdi, rsi
    jae 9f
    cmp byte ptr [rdi], ' '
    jne 2f
    inc rdi
    jmp 1b
2:  cmp rcx, 16
    jae 9f
    mov rax, rcx
    shl rax, 4
    mov [r8 + rax], rdi
    mov rdx, rdi
3:  cmp rdx, rsi
    jae 4f
    cmp byte ptr [rdx], ' '
    je 4f
    inc rdx
    jmp 3b
4:  mov rax, rdx
    sub rax, rdi
    mov r9, rcx
    shl r9, 4
    mov [r8 + r9 + 8], rax
    inc rcx
    mov [rip + nfields], rcx
    mov rdi, rdx
    jmp 1b
9:  ret

# field_u64(i) -> rax value, rdx 1 when it was a number (and only digits)
field_u64:
    lea r8, [rip + fields]
    shl rdi, 4
    mov rsi, [r8 + rdi + 8]
    mov rdi, [r8 + rdi]
    test rsi, rsi
    jz 8f
    push rsi
    call parse_u64
    pop rsi
    cmp rdx, rsi
    jne 8f
    mov edx, 1
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# field_is(i, cstr) -> 1 if equal
field_is:
    lea r8, [rip + fields]
    mov rdx, rsi
    shl rdi, 4
    mov rsi, [r8 + rdi + 8]
    mov rdi, [r8 + rdi]
    jmp str_eq_cstr

# rest_from(i) -> rax ptr, rdx len: from field i to the end of the line
rest_from:
    lea r8, [rip + fields]
    cmp rdi, [rip + nfields]
    jae 8f
    shl rdi, 4
    mov rax, [r8 + rdi]
    mov rdx, [rip + line + SB_ptr]
    add rdx, [rip + line + SB_len]
    sub rdx, rax
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# handle_line(ptr, len): one message from cur (body_ptr set when it is a body message's line)
handle_line:
    PROLOGUE
    mov rbx, [rip + cur]
    test rsi, rsi
    jz 9f
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + line]
    call sb_clear
    lea rdi, [rip + line]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rax, [rip + line + SB_ptr]
    add rax, [rip + line + SB_len]
    mov byte ptr [rax], 0
    mov rdi, [rip + line + SB_ptr]
    mov rsi, [rip + line + SB_len]
    call split
    cmp qword ptr [rip + nfields], 0
    je 9f
    cmp dword ptr [rbx + EXT_hello], 0
    jne .Lhl_msg
    # the first line must be hello 1
    xor edi, edi
    lea rsi, [rip + .Lw_hello]
    call field_is
    test eax, eax
    jz 3f
    mov edi, 1
    call field_u64
    test edx, edx
    jz 3f
    cmp rax, 1
    jne 4f
    mov dword ptr [rbx + EXT_hello], 1
    mov dword ptr [rbx + EXT_status], ES_RUNNING
    call ext_hooks_update
    mov rdi, rbx
    call send_ready
    mov rdi, rbx
    call extproto_events        # catch-up: nothing is known yet, so everything open is reported
    mov rax, [rbx + EXT_pending]
    test rax, rax
    jz 9f
    mov qword ptr [rbx + EXT_pending], 0
    mov rdi, rbx
    lea rsi, [rax - 1]
    call extproto_send_run
    jmp 9f
3:  mov rdi, rbx
    lea rsi, [rip + .Lr_no_hello]
    call ext_kill
    jmp 9f
4:  mov rdi, rbx
    lea rsi, [rip + .Lr_protocol]
    call ext_kill
    jmp 9f
.Lhl_msg:
    # replies to rhun's requests (none in gate 1) are ignored
    xor edi, edi
    lea rsi, [rip + .Lw_ok]
    call field_is
    test eax, eax
    jnz 9f
    xor edi, edi
    lea rsi, [rip + .Lw_error]
    call field_is
    test eax, eax
    jnz 9f
    xor edi, edi
    call field_u64
    test edx, edx
    jz .Lhl_syntax
    test rax, rax
    jz .Lhl_syntax              # events come from rhun, not from extensions
    cmp rax, 2147483647
    ja .Lhl_syntax
    mov [rip + cur_id], rax
    cmp qword ptr [rip + nfields], 2
    jb .Lhl_syntax
    mov qword ptr [rip + syntax_seen], 0
    # the verb
    lea r12, [rip + verbs]
5:  mov rsi, [r12]
    test rsi, rsi
    jz .Lhl_unknown
    mov edi, 1
    call field_is
    test eax, eax
    jnz 6f
    add r12, 24
    jmp 5b
6:  # a body verb waits for its body first
    cmp qword ptr [r12 + 16], 0
    je 7f
    cmp qword ptr [rip + body_ptr], 0
    jne 7f
    mov rdi, [rip + nfields]
    dec rdi
    call field_u64
    test edx, edx
    jz .Lhl_syntax_id
    cmp rax, [r12 + 16]
    jbe 61f
    # over the cap: the body cannot be skipped without reading it, and reading megabytes to
    # throw them away is the attack: the program ends
    mov rdi, rbx
    lea rsi, [rip + .Lr_body]
    call ext_kill
    jmp 9f
61: mov [rbx + EXT_body_len], rax
    mov rdi, [rip + line + SB_ptr]
    mov rsi, [rip + line + SB_len]
    call mem_dup
    mov [rbx + EXT_body], rax
    jmp 9f
7:  call [r12 + 8]
    cmp qword ptr [rip + syntax_seen], 0
    jne 9f
    mov dword ptr [rbx + EXT_syntax_errs], 0    # a whole request parsed: the streak is over
    jmp 9f
.Lhl_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    jmp 9f
.Lhl_syntax:
    xor edi, edi
    call reply_syntax
    jmp 9f
.Lhl_syntax_id:
    mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# reply_syntax(id): "error ID syntax ..."; the third in a row ends the program
reply_syntax:
    push rbx
    mov rbx, [rip + cur]
    lea rsi, [rip + .Le_syntax]
    call reply_error
    mov qword ptr [rip + syntax_seen], 1
    inc dword ptr [rbx + EXT_syntax_errs]
    cmp dword ptr [rbx + EXT_syntax_errs], 3
    jb 9f
    mov rdi, rbx
    lea rsi, [rip + .Lr_syntax]
    call ext_kill
9:  pop rbx
    ret

# ---------------- replies ----------------

# out_begin(): start a reply or event
out_begin:
    lea rdi, [rip + out]
    jmp sb_clear
# out_cstr(cstr), out_u64(v), out_byte(b), out_bytes(ptr, len), out_end(): send it to cur
out_cstr:
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push_cstr
out_u64:
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push_u64
out_byte:
    mov esi, edi
    lea rdi, [rip + out]
    jmp sb_push_byte
out_bytes:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push
out_end:
    mov rdi, [rip + cur]
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    jmp ext_send

# reply_ok(id)
reply_ok:
    push rdi
    call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, 10
    call out_byte
    jmp out_end

# reply_ok_u64(id, value): "ok ID VALUE"
reply_ok_u64:
    push rsi
    push rdi
    call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, ' '
    call out_byte
    pop rdi
    call out_u64
    mov edi, 10
    call out_byte
    jmp out_end

# reply_error(id, "code text")
reply_error:
    push rsi
    push rdi
    call out_begin
    lea rdi, [rip + .Lw_error_sp]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, ' '
    call out_byte
    pop rdi
    call out_cstr
    mov edi, 10
    call out_byte
    jmp out_end

# reply_error_u64(id, "code text ", value)
reply_error_u64:
    push rdx
    push rsi
    push rdi
    call out_begin
    lea rdi, [rip + .Lw_error_sp]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, ' '
    call out_byte
    pop rdi
    call out_cstr
    pop rdi
    call out_u64
    mov edi, 10
    call out_byte
    jmp out_end

# ---------------- documents ----------------

# doc_by_id(id) -> DOC* or 0, among the open document tabs
doc_by_id:
    xor ecx, ecx
1:  cmp rcx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rcx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc rcx
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 1b
    cmp [rax + DOC_id], rdi
    jne 1b
    ret
8:  xor eax, eax
    ret

# arg_doc(i) -> DOC* from field i, or 0 after replying nodoc
arg_doc:
    push rbx
    call field_u64
    test edx, edx
    jz 7f
    mov rdi, rax
    call doc_by_id
    test rax, rax
    jz 8f
    pop rbx
    ret
7:  mov rdi, [rip + cur_id]
    call reply_syntax
    xor eax, eax
    pop rbx
    ret
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nodoc]
    call reply_error
    xor eax, eax
    pop rbx
    ret

# arg_pos(doc, i) -> rax byte position from fields i, i+1 (LINE COL), or -1 after replying badpos
arg_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call field_u64
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, [rbx + DOC_nlines]
    ja 8f
    lea r13, [rax - 1]          # line, 0-based
    lea rdi, [r12 + 1]
    call field_u64
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    mov r14, rax                # col, 1-based byte
    mov rdi, rbx
    mov rsi, r13
    call doc_line_start
    mov r15, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_end
    sub rax, r15                # line length
    lea rcx, [r14 - 1]
    cmp rcx, rax
    ja 8f
    add r15, rcx
    # not inside a multibyte sequence
    cmp rcx, rax
    je 9f
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
9:  mov rax, r15
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos]
    call reply_error
    mov rax, -1
    EPILOGUE

# need(bit) -> 1 when cur has the capability, else 0 after replying needs
need:
    mov rax, [rip + cur]
    test [rax + EXT_needs], edi
    jz 1f
    mov eax, 1
    ret
1:  lea rsi, [rip + .Le_needs_read]
    cmp edi, NEEDS_DOC_WRITE
    jne 2f
    lea rsi, [rip + .Le_needs_write]
2:  mov rdi, [rip + cur_id]
    call reply_error
    xor eax, eax
    ret

# ---------------- requests ----------------

# ID text DOC -> ok ID VERSION LEN + body
h_text:
    PROLOGUE
    mov edi, NEEDS_DOC_READ
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jb 8f
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    call doc_len
    mov r12, rax
    call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rip + cur_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r12
    call out_u64
    mov edi, 10
    call out_byte
    lea rdi, [rip + out]
    mov rsi, r12
    call sb_reserve
    mov rcx, rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    call doc_copy
    add [rip + out + SB_len], r12
    call out_end
9:  EPILOGUE
8:  mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID range DOC L1 C1 L2 C2 -> ok ID VERSION LEN + body
h_range:
    PROLOGUE
    mov edi, NEEDS_DOC_READ
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 7
    jb .Lhr_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov esi, 3
    call arg_pos
    test rax, rax
    js 9f
    mov r12, rax
    mov rdi, rbx
    mov esi, 5
    call arg_pos
    test rax, rax
    js 9f
    mov r13, rax
    sub r13, r12                # length
    jns 1f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos]
    call reply_error
    jmp 9f
1:  call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rip + cur_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r13
    call out_u64
    mov edi, 10
    call out_byte
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_reserve
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_copy
    add [rip + out + SB_len], r13
    call out_end
9:  EPILOGUE
.Lhr_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID replace DOC VERSION L1 C1 L2 C2 LEN + body -> ok ID NEWVERSION
h_replace:
    PROLOGUE
    mov edi, NEEDS_DOC_WRITE
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 9
    jb .Lhp_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lhp_readonly
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lhp_syntax
    cmp rax, [rbx + DOC_version]
    jne .Lhp_stale
    mov rdi, rbx
    mov esi, 4
    call arg_pos
    test rax, rax
    js 9f
    mov r12, rax
    mov rdi, rbx
    mov esi, 6
    call arg_pos
    test rax, rax
    js 9f
    mov r13, rax
    sub r13, r12
    js .Lhp_badpos
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call apply_replace
    mov rdi, [rip + cur_id]
    mov rsi, [rbx + DOC_version]
    call reply_ok_u64
9:  EPILOGUE
.Lhp_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_stale]
    mov rdx, [rbx + DOC_version]
    call reply_error_u64
    EPILOGUE
.Lhp_badpos:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos]
    call reply_error
    EPILOGUE
.Lhp_readonly:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_readonly]
    call reply_error
    EPILOGUE
.Lhp_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# apply_replace(doc, pos, len, ptr, blen): one undo step; the cursor and anchor follow the text
apply_replace:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, rbx
    call doc_begin_group
    test r13, r13
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov ecx, EK_OTHER
    call doc_delete
1:  test r15, r15
    jz 2f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rcx, r15
    mov r8d, EK_OTHER
    call doc_insert
2:  mov rdi, rbx
    call doc_end_group
    lea rdi, [rbx + DOC_cur]
    call move_mark
    lea rdi, [rbx + DOC_anchor]
    call move_mark
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    mov rdx, [rbx + DOC_anchor]
    call set_marks
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# set_marks(doc, cur, anchor): through the editor (which reveals the cursor) for the document on
# screen, directly for any other
set_marks:
    cmp rdi, [rip + g_doc]
    je 1f
    mov [rdi + DOC_cur], rsi
    mov [rdi + DOC_anchor], rdx
    ret
1:  push rbx
    push rsi
    mov rbx, rdi
    mov rsi, rdx
    xor edx, edx
    call ed_set_cursor
    pop rsi
    mov rdi, rbx
    mov edx, 1
    call ed_set_cursor
    pop rbx
    ret

# move_mark(ptr to a position): after replacing [r12, r12+r13) with r15 bytes
move_mark:
    mov rax, [rdi]
    cmp rax, r12
    jb 9f
    lea rcx, [r12 + r13]
    cmp rax, rcx
    jae 1f
    lea rax, [r12 + r15]        # inside the range: after the new text
    mov [rdi], rax
    ret
1:  sub rax, r13
    add rax, r15
    mov [rdi], rax
9:  ret

# ID insert DOC VERSION LEN + body -> ok ID NEWVERSION: at the cursor, replacing the selection
h_insert:
    PROLOGUE
    mov edi, NEEDS_DOC_WRITE
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 5
    jb .Lhi_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lhi_readonly
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lhi_syntax
    cmp rax, [rbx + DOC_version]
    jne .Lhi_stale
    mov rdi, rbx
    call ed_sel
    mov r12, rax
    mov r13, rdx
    cmp r12, r13
    jbe 1f
    xchg r12, r13
1:  sub r13, r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call apply_replace
    mov rdi, [rip + cur_id]
    mov rsi, [rbx + DOC_version]
    call reply_ok_u64
9:  EPILOGUE
.Lhi_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_stale]
    mov rdx, [rbx + DOC_version]
    call reply_error_u64
    EPILOGUE
.Lhi_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE
.Lhi_readonly:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_readonly]
    call reply_error
    EPILOGUE

# ID select DOC L1 C1 L2 C2 -> ok ID: the anchor at the first position, the cursor at the second
h_select:
    PROLOGUE
    cmp qword ptr [rip + nfields], 7
    jb .Lhs_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov esi, 3
    call arg_pos
    test rax, rax
    js 9f
    mov r12, rax
    mov rdi, rbx
    mov esi, 5
    call arg_pos
    test rax, rax
    js 9f
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    call set_marks
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Lhs_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID toast LEN + body -> ok ID (at most 200 bytes shown)
h_toast:
    PROLOGUE
    mov rsi, [rip + body_ptr]
    mov rdi, [rip + body_len]
    mov edx, 200
    call utf8_cut
    mov rdx, rax
    mov rsi, [rip + body_ptr]
    lea rdi, [rip + toast_buf]
    mov rcx, rdx
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rdi, [rip + toast_buf]
    mov byte ptr [rdi + rdx], 0
    call app_toast
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE

# ID status LEN + body -> ok ID: the extension's status text (at most 80 bytes; empty clears)
h_status:
    PROLOGUE
    mov rbx, [rip + cur]
    mov rdi, [rbx + EXT_status_text]
    call mem_free
    mov qword ptr [rbx + EXT_status_text], 0
    mov rsi, [rip + body_len]
    test rsi, rsi
    jz 1f
    mov rdi, rsi
    mov edx, 80
    mov rsi, [rip + body_ptr]
    call utf8_cut
    mov rsi, rax
    mov rdi, [rip + body_ptr]
    call mem_dup
    mov [rbx + EXT_status_text], rax
1:  mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE

# utf8_cut(len, ptr, max) -> the length to keep: at most max bytes, not ending inside a character
utf8_cut:
    mov rax, rdi
    cmp rax, rdx
    jbe 9f
    mov rax, rdx
1:  test rax, rax
    jz 9f
    movzx ecx, byte ptr [rsi + rax]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne 9f
    dec rax
    jmp 1b
9:  ret

# ID open LINE COL PATH -> ok ID DOC: a tab for the file, the cursor at the position (0 0 keeps it)
h_open:
    PROLOGUE
    cmp qword ptr [rip + nfields], 5
    jb .Lho_syntax
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lho_syntax
    mov r12, rax                # line
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lho_syntax
    mov r13, rax                # col
    mov edi, 4
    call rest_from
    mov rdi, rax
    mov rsi, rdx
    cmp byte ptr [rdi], '/'
    je 1f
    # relative: inside the project
    mov rcx, [rip + g_project]
    test rcx, rcx
    jz .Lho_nofile
    push rdi
    push rsi
    mov rdi, rcx
    call strlen
    pop rsi
    pop rdi
    push rsi
    push rdi
    lea rdi, [rip + out]
    call sb_clear
    lea rdi, [rip + out]
    mov rsi, [rip + g_project]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, '/'
    call sb_push_byte
    pop rsi
    pop rdx
    lea rdi, [rip + out]
    call sb_push
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
1:  call mem_dup
    mov r14, rax
    mov rdi, rax
    call file_type
    cmp eax, 0x8000             # a regular file
    jne .Lho_missing
    mov rdi, r14
    call app_open_file
    mov rbx, rax
    mov rdi, r14
    call mem_free
    test rbx, rbx
    js .Lho_failed
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lho_notdoc
    mov rbx, [rax + TAB_doc]
    test r12, r12
    jz 1f
    cmp r12, [rbx + DOC_nlines]
    jbe 11f
    mov r12, [rbx + DOC_nlines]  # past the end: the last line
    mov r13, 1 << 40             # and its end
11: lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_start
    mov r15, rax
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_end
    sub rax, r15
    lea rcx, [r13 - 1]
    test r13, r13
    jz 2f
    cmp rcx, rax
    jbe 3f
2:  mov rcx, rax
3:  add r15, rcx
    mov rdi, rbx
    mov rsi, r15
    xor edx, edx
    call ed_set_cursor
1:  mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    mov rsi, [rbx + DOC_id]
    call reply_ok_u64
    EPILOGUE
.Lho_missing:
    mov rdi, r14
    call mem_free
.Lho_nofile:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nofile]
    call reply_error
    EPILOGUE
.Lho_notdoc:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nodoc]
    call reply_error
    EPILOGUE
.Lho_failed:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nofile]
    call reply_error
    EPILOGUE
.Lho_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID diagnostics DOC VERSION N + body -> ok ID: the extension's marks on the document
h_diagnostics:
    PROLOGUE
    mov edi, NEEDS_DOC_READ
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 6
    jb .Lhd_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lhd_syntax
    cmp rax, [rbx + DOC_version]
    jne .Lhd_stale
    mov edi, 4
    call field_u64
    test edx, edx
    jz .Lhd_syntax
    cmp rax, MARKS_MAX
    ja .Lhd_toobig
    mov r12, rax
    mov rdi, rbx
    mov rsi, [rip + cur]
    mov rdx, [rip + body_ptr]
    mov rcx, [rip + body_len]
    mov r8, r12
    call extmarks_set
    test rax, rax
    jnz .Lhd_bad
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Lhd_bad:
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_error
    EPILOGUE
.Lhd_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_stale]
    mov rdx, [rbx + DOC_version]
    call reply_error_u64
    EPILOGUE
.Lhd_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig]
    call reply_error
    EPILOGUE
.Lhd_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID hover DOC LINE COL LEN + body -> ok ID: shown if the pointer still rests there
h_hover:
    PROLOGUE
    mov edi, NEEDS_DOC_READ
    call need
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 6
    jb .Lhh_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov esi, 3
    call arg_pos
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rip + body_ptr]
    mov rcx, [rip + body_len]
    call ext_hover_text_set
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Lhh_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID cancel ID2 -> ok ID: requests are handled as they arrive, so there is nothing to withdraw
h_cancel:
    mov rdi, [rip + cur_id]
    jmp reply_ok

# ---------------- events ----------------

# send_ready(ext): "0 ready PROJECT"
send_ready:
    PROLOGUE
    mov [rip + cur], rdi
    call out_begin
    lea rdi, [rip + .Lev_ready]
    call out_cstr
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Ldash]
1:  call out_cstr
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# extproto_send_run(ext, command index): "0 run NAME DOC"
FN extproto_send_run
    PROLOGUE
    mov rbx, rsi
    # what changed since the last tick goes first: the extension must know the document
    # (opened, active) before it is asked to act on it
    call extproto_events
    mov rax, [rip + cur]
    cmp dword ptr [rax + EXT_status], ES_RUNNING
    jne 9f
    call out_begin
    lea rdi, [rip + .Lev_run]
    call out_cstr
    imul rax, rbx, CMD_SIZE
    add rax, [rip + g_ext_cmds + VEC_ptr]
    mov rdi, [rax + CMD_name]
    call out_cstr
    mov edi, ' '
    call out_byte
    call active_doc_id
    mov rdi, rax
    call out_u64
    mov edi, 10
    call out_byte
    call out_end
9:  EPILOGUE

# active_doc_id() -> the active document's id, or 0
active_doc_id:
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rdi, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    mov rax, [rax + DOC_id]
    ret
8:  xor eax, eax
    ret

# extproto_events(ext): what changed since the extension was last told, as events
FN extproto_events
    PROLOGUE
    mov rbx, rdi
    mov [rip + cur], rbx
    # forget nothing yet: mark every known document unseen
    xor ecx, ecx
1:  cmp rcx, [rbx + EXT_known + VEC_len]
    jae 2f
    imul rax, rcx, XK_SIZE
    add rax, [rbx + EXT_known + VEC_ptr]
    mov qword ptr [rax + XK_seen], 0
    inc rcx
    jmp 1b
2:  # every open document
    xor r12d, r12d
.Lev_tabs:
    cmp r12, [rip + g_tabs + VEC_len]
    jae .Lxe_closed
    imul rax, r12, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r12
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lev_tabs
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz .Lev_tabs
    mov rdi, rbx
    mov rsi, [r13 + DOC_id]
    call known_find
    test rax, rax
    jnz 3f
    # new to this extension
    mov rdi, [rbx + EXT_sub_opened]
    mov rsi, r13
    call sub_matches            # opened is the gate: a document never opened to it stays unknown
    test eax, eax
    jz .Lev_tabs
    lea rdi, [rbx + EXT_known]
    mov esi, XK_SIZE
    call vec_push
    mov r14, rax
    mov rcx, [r13 + DOC_id]
    mov [r14 + XK_id], rcx
    mov rcx, [r13 + DOC_version]
    mov [r14 + XK_ver], rcx
    mov rcx, [r13 + DOC_saves]
    mov [r14 + XK_saves], rcx
    mov rcx, [r13 + DOC_cur]
    mov [r14 + XK_cur], rcx
    mov rcx, [r13 + DOC_anchor]
    mov [r14 + XK_anchor], rcx
    mov qword ptr [r14 + XK_seen], 2    # new this pass: no edits for it yet
    cmp qword ptr [rbx + EXT_sub_opened], 0
    je 31f
    mov rdi, r13
    call send_opened
31: # the active document's position is part of the snapshot, sent after `active` below
    call active_doc_id
    cmp rax, [r13 + DOC_id]
    jne .Lev_tabs
    mov qword ptr [r14 + XK_cur], -1
    mov qword ptr [r14 + XK_anchor], -1
    jmp .Lev_tabs
3:  mov r14, rax
    mov qword ptr [r14 + XK_seen], 1
    # edits since the last frame, or a resync, for an edits subscriber
    mov rdi, [rbx + EXT_sub_edits]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 30f
    cmp dword ptr [r13 + DOC_xresync], 0
    je 29f
    lea rdi, [rip + .Lev_resync]
    mov rsi, r13
    call send_doc_version
    jmp 30f
29: mov rax, [r13 + DOC_xedits]
    test rax, rax
    jz 30f
    cmp qword ptr [rax + SB_len], 0
    je 30f
    mov rdi, r13
    call send_edits
30: # changed? (before saved, so a save after a change reports both)
    mov rcx, [r13 + DOC_version]
    cmp rcx, [r14 + XK_ver]
    je 4f
    mov [r14 + XK_ver], rcx
    mov rdi, [rbx + EXT_sub_changed]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 4f
    lea rdi, [rip + .Lev_changed]
    mov rsi, r13
    call send_doc_version
4:  # saved?
    mov rcx, [r13 + DOC_saves]
    cmp rcx, [r14 + XK_saves]
    je 5f
    mov [r14 + XK_saves], rcx
    mov rdi, [rbx + EXT_sub_saved]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 5f
    lea rdi, [rip + .Lev_saved]
    mov rsi, r13
    call send_doc_version
5:  # cursor or selection?
    mov rcx, [r13 + DOC_cur]
    mov rdx, [r13 + DOC_anchor]
    cmp rcx, [r14 + XK_cur]
    jne 6f
    cmp rdx, [r14 + XK_anchor]
    je .Lev_tabs
6:  mov rax, [r14 + XK_cur]
    cmp rax, [r14 + XK_anchor]
    setne r15b                  # a selection existed before
    cmp rax, rcx
    sete r15b                   # bit 1: the cursor itself did not move
    shl r15b, 1
    mov rax, [r14 + XK_cur]
    cmp rax, [r14 + XK_anchor]
    setne al
    or r15b, al
    mov [r14 + XK_cur], rcx
    mov [r14 + XK_anchor], rdx
    # the cursor moved: cursor subscribers hear it, selection or not
    test r15b, 2
    jnz 62f
    mov rdi, [rbx + EXT_sub_cursor]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 62f
    mov rdi, r13
    call send_cursor
62: # a selection exists, or one just collapsed: selection subscribers hear the range
    mov rcx, [r14 + XK_cur]
    cmp rcx, [r14 + XK_anchor]
    jne 7f
    test r15b, 1
    jz .Lev_tabs
7:  mov rdi, [rbx + EXT_sub_selection]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz .Lev_tabs
    mov rdi, r13
    call send_selection
    jmp .Lev_tabs
.Lxe_closed:
    # known documents that are gone
    xor r12d, r12d
8:  cmp r12, [rbx + EXT_known + VEC_len]
    jae .Lxe_active
    imul rax, r12, XK_SIZE
    add rax, [rbx + EXT_known + VEC_ptr]
    cmp qword ptr [rax + XK_seen], 0
    jne 81f
    mov rdi, [rax + XK_id]
    call send_closed
    # remove: move the last into this slot
    mov rcx, [rbx + EXT_known + VEC_len]
    dec rcx
    mov [rbx + EXT_known + VEC_len], rcx
    imul rsi, rcx, XK_SIZE
    add rsi, [rbx + EXT_known + VEC_ptr]
    imul rdi, r12, XK_SIZE
    add rdi, [rbx + EXT_known + VEC_ptr]
    mov edx, XK_SIZE
    call memcpy
    jmp 8b
81: inc r12
    jmp 8b
.Lxe_active:
    call active_doc_id
    cmp rax, [rbx + EXT_active]
    je 85f
    mov [rbx + EXT_active], rax
    mov rdi, rax
    call send_active
85: # positions held back during catch-up (XK_cur -1): the active document's, now
    xor r12d, r12d
86: cmp r12, [rbx + EXT_known + VEC_len]
    jae 9f
    imul r14, r12, XK_SIZE
    add r14, [rbx + EXT_known + VEC_ptr]
    inc r12
    cmp qword ptr [r14 + XK_cur], -1
    jne 86b
    mov rdi, [r14 + XK_id]
    call doc_by_id
    test rax, rax
    jz 86b
    mov r13, rax
    mov rcx, [r13 + DOC_cur]
    mov rdx, [r13 + DOC_anchor]
    mov [r14 + XK_cur], rcx
    mov [r14 + XK_anchor], rdx
    mov rdi, [rbx + EXT_sub_cursor]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 88f
    mov rdi, r13
    call send_cursor
88: mov rcx, [r14 + XK_cur]
    cmp rcx, [r14 + XK_anchor]
    je 86b
    mov rdi, [rbx + EXT_sub_selection]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 86b
    mov rdi, r13
    call send_selection
    jmp 86b
9:  EPILOGUE

# known_find(ext, id) -> XK* or 0
known_find:
    xor ecx, ecx
1:  cmp rcx, [rdi + EXT_known + VEC_len]
    jae 8f
    imul rax, rcx, XK_SIZE
    add rax, [rdi + EXT_known + VEC_ptr]
    inc rcx
    cmp [rax + XK_id], rsi
    jne 1b
    ret
8:  xor eax, eax
    ret

# sub_matches(patterns cstr or 0, doc) -> 1 when the document's name matches ("*" matches all,
# untitled documents too)
sub_matches:
    PROLOGUE
    test rdi, rdi
    jz 8f
    mov rbx, rdi
    mov r12, rsi
    cmp byte ptr [rbx], '*'
    jne 1f
    cmp byte ptr [rbx + 1], 0
    je 9f
1:  mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz 8f
    mov rsi, rbx
    call ext_path_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# send_opened(doc): "0 opened DOC VERSION LANG PATH"
send_opened:
    PROLOGUE
    mov rbx, rdi
    call out_begin
    lea rdi, [rip + .Lev_opened]
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rax, [rbx + DOC_lang]
    test rax, rax
    jz 1f
    mov rdi, [rax + GR_name]
    call out_word               # "Visual Basic" travels as Visual_Basic
    jmp 2f
1:  lea rdi, [rip + .Ldash]
    call out_cstr
2:  mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jnz 3f
    lea rdi, [rip + .Ldash]
3:  call out_cstr
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# out_word(cstr): the text with each space as an underscore
out_word:
    push rbx
    mov rbx, rdi
1:  movzx edi, byte ptr [rbx]
    test edi, edi
    jz 9f
    cmp edi, ' '
    jne 2f
    mov edi, '_'
2:  call out_byte
    inc rbx
    jmp 1b
9:  pop rbx
    ret

# extproto_send_project_all(): "0 project PATH" to every running extension
FN extproto_send_project_all
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lev_project]
    call out_cstr
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 2f
    lea rdi, [rip + .Ldash]
2:  call out_cstr
    mov edi, 10
    call out_byte
    call out_end
    jmp 1b
9:  EPILOGUE

# send_doc_version(event cstr "0 saved ", doc): "EVENT DOC VERSION"
send_doc_version:
    PROLOGUE
    mov rbx, rsi
    mov r12, rdi
    call out_begin
    mov rdi, r12
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# send_edits(doc): "0 edits DOC VERSION LEN" + the records
send_edits:
    PROLOGUE
    mov rbx, rdi
    call out_begin
    lea rdi, [rip + .Lev_edits]
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + DOC_version]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rax, [rbx + DOC_xedits]
    mov rdi, [rax + SB_len]
    call out_u64
    mov edi, 10
    call out_byte
    mov rax, [rbx + DOC_xedits]
    mov rdi, [rax + SB_ptr]
    mov rsi, [rax + SB_len]
    call out_bytes
    call out_end
    EPILOGUE

# extproto_send_hover_all(doc, pos): "0 hover DOC LINE COL" to the running extensions whose
# hover subscription names the document
FN extproto_send_hover_all
    PROLOGUE
    mov r13, rdi
    mov r14, rsi
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, [rbx + EXT_sub_hover]
    mov rsi, r13
    call sub_matches
    test eax, eax
    jz 1b
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lev_hover]
    call out_cstr
    mov rdi, [r13 + DOC_id]
    call out_u64
    mov rdi, r13
    mov rsi, r14
    call out_pos
    mov edi, 10
    call out_byte
    call out_end
    jmp 1b
9:  EPILOGUE

# out_pos(doc, pos): " LINE COL"
out_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, r12
    sub r14, rax
    mov edi, ' '
    call out_byte
    lea rdi, [r13 + 1]
    call out_u64
    mov edi, ' '
    call out_byte
    lea rdi, [r14 + 1]
    call out_u64
    EPILOGUE

# send_cursor(doc): "0 cursor DOC LINE COL"
send_cursor:
    PROLOGUE
    mov rbx, rdi
    call out_begin
    lea rdi, [rip + .Lev_cursor]
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call out_pos
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# send_selection(doc): "0 selection DOC L1 C1 L2 C2" (anchor, then cursor)
send_selection:
    PROLOGUE
    mov rbx, rdi
    call out_begin
    lea rdi, [rip + .Lev_selection]
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov rdi, rbx
    mov rsi, [rbx + DOC_anchor]
    call out_pos
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call out_pos
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# send_closed(id): "0 closed DOC"
send_closed:
    push rdi
    call out_begin
    lea rdi, [rip + .Lev_closed]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, 10
    call out_byte
    jmp out_end

# send_active(id): "0 active DOC"
send_active:
    push rdi
    call out_begin
    lea rdi, [rip + .Lev_active]
    call out_cstr
    pop rdi
    call out_u64
    mov edi, 10
    call out_byte
    jmp out_end

.section .rodata
.p2align 3
# verb table: name, handler, body cap (0: no body)
verbs:
    .quad .Lv_text, h_text, 0
    .quad .Lv_range, h_range, 0
    .quad .Lv_replace, h_replace, EXT_BODY_MAX
    .quad .Lv_insert, h_insert, EXT_BODY_MAX
    .quad .Lv_select, h_select, 0
    .quad .Lv_toast, h_toast, EXT_BODY_MAX
    .quad .Lv_status, h_status, EXT_BODY_MAX
    .quad .Lv_open, h_open, 0
    .quad .Lv_cancel, h_cancel, 0
    .quad .Lv_diagnostics, h_diagnostics, EXT_BODY_MAX
    .quad .Lv_hover, h_hover, EXT_BODY_MAX
    .quad 0, 0, 0
.Lv_text: .asciz "text"
.Lv_range: .asciz "range"
.Lv_replace: .asciz "replace"
.Lv_insert: .asciz "insert"
.Lv_select: .asciz "select"
.Lv_toast: .asciz "toast"
.Lv_status: .asciz "status"
.Lv_open: .asciz "open"
.Lv_cancel: .asciz "cancel"
.Lv_diagnostics: .asciz "diagnostics"
.Lv_hover: .asciz "hover"
.Lw_hello: .asciz "hello"
.Lw_ok: .asciz "ok"
.Lw_error: .asciz "error"
.Lw_ok_sp: .asciz "ok "
.Lw_error_sp: .asciz "error "
.Ldash: .asciz "-"
.Lev_ready: .asciz "0 ready "
.Lev_run: .asciz "0 run "
.Lev_opened: .asciz "0 opened "
.Lev_saved: .asciz "0 saved "
.Lev_changed: .asciz "0 changed "
.Lev_cursor: .asciz "0 cursor "
.Lev_selection: .asciz "0 selection "
.Lev_closed: .asciz "0 closed "
.Lev_active: .asciz "0 active "
.Lev_project: .asciz "0 project "
.Lev_edits: .asciz "0 edits "
.Lev_resync: .asciz "0 resync "
.Lev_hover: .asciz "0 hover "
.Le_unknown: .asciz "unknown no such request"
.Le_syntax: .asciz "syntax cannot parse the line"
.Le_nodoc: .asciz "nodoc no such document"
.Le_badpos: .asciz "badpos position outside the document or inside a character"
.Le_stale: .asciz "stale "
.Le_needs_read: .asciz "needs documents=read"
.Le_needs_write: .asciz "needs documents=write"
.Le_nofile: .asciz "nofile no such file"
.Le_readonly: .asciz "readonly the document cannot be edited"
.Le_toobig: .asciz "toobig more than 2000 diagnostics"
.Lr_no_hello: .asciz "the first line was not hello 1"
.Lr_protocol: .asciz "protocol version not supported (rhun speaks 1)"
.Lr_body: .asciz "a body over its cap"
.Lr_syntax: .asciz "three unparsable lines in a row"
