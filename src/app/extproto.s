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
pr_ext: .quad 0                 # the open prompt (choose, ask, term): its extension,
pr_id: .quad 0                  #   request id (0: no prompt is open),
pr_kind: .quad 0                #   1 choose, 2 ask, 3 term,
pr_body: .quad 0                #   the items' bytes (choose), owned
pr_opened: .quad 0              #   time_ms when it opened (a fresh term prompt ignores Enter)
pr_label: .zero 208             #   the prompt text, a cstr
pr_cmd: .zero SB_SIZE           # the command sent to the terminal

.text

# ---------------- reading ----------------

# extproto_pump(ext): handle every complete message in the receive buffer
FN extproto_pump
    PROLOGUE 16
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz 9f
    mov [rip + cur], rbx
    call time_ms
    mov r15, rax                # the per-extension window uses milliseconds
    call time_us
    mov [rsp + 8], rax          # aggregate work includes sub-millisecond callbacks
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    je .Lpp_budget_enter
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
.Lpp_budget_enter:
    mov rdi, r15
    call ext_budget_enter
    test eax, eax
    jz .Lpp_global_cap
    mov dword ptr [rbx + EXT_global_wait], 0
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
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 9f
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
    # the handler may have ended the program (a third syntax error): its buffers are gone
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    je 11f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
11: mov rdi, [rbx + EXT_body]
    call mem_free
    mov qword ptr [rbx + EXT_body], 0
    mov rdi, rbx                # resources group: bytes in
    mov rsi, [rbx + EXT_body_len]
    xor edx, edx
    call extres_in
    mov rdi, [rbx + EXT_body_len]
    add [rbx + EXT_fbytes], rdi
    inc qword ptr [rbx + EXT_win_msgs]
    call ext_budget_message
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
    mov rdi, rbx                # resources group: a message in
    lea rsi, [r14 + 1]
    mov edx, 1
    call extres_in
    lea rdi, [r14 + 1]
    add [rbx + EXT_fbytes], rdi
    inc qword ptr [rbx + EXT_win_msgs]
    call ext_budget_message
    call consume
    mov qword ptr [rip + body_ptr], 0
    mov qword ptr [rip + body_len], 0
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call handle_line
.Lpp_time:
    # A handler may have stopped the extension and released its watches/buffers.
    cmp dword ptr [rbx + EXT_status], ES_STARTING
    je .Lpp_live
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
.Lpp_live:
    # one run takes EXT_PUMP_MS at most; the rest waits like a capped window (ext_tick resumes it)
    call time_us
    sub rax, [rsp + 8]
    mov r12, rax
    mov rdi, rax
    call ext_budget_room
    test eax, eax
    jz .Lpp_global_cap
    mov rax, r12
    cmp rax, EXT_PUMP_MS * 1000
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
    jmp 9f
.Lpp_global_cap:
    mov rdi, rbx
    call ext_budget_pause
9:  call time_us
    sub rax, [rsp + 8]
    mov rdi, rax
    call ext_budget_leave
    EPILOGUE

# consume(n): drop n bytes from the front of rbx's receive buffer
consume:
    push rbx
    push rdi
    call ext_budget_bytes
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

# field_u64(i) -> rax value, rdx 1 for a complete decimal u64 without overflow.
field_u64:
    cmp rdi, [rip + nfields]
    jae 8f                      # past the line's fields: what is there is an older line's
    lea r8, [rip + fields]
    shl rdi, 4
    mov rsi, [r8 + rdi + 8]
    mov rdi, [r8 + rdi]
    test rsi, rsi
    jz 8f
    xor eax, eax
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 8f
    mov r9, 1844674407370955161
    cmp rax, r9
    ja 8f
    jb 2f
    cmp edx, 5
    ja 8f
2:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    cmp rcx, rsi
    jb 1b
    mov edx, 1
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# field_is(i, cstr) -> 1 if equal
field_is:
    cmp rdi, [rip + nfields]
    jae 8f
    lea r8, [rip + fields]
    mov rdx, rsi
    shl rdi, 4
    mov rsi, [r8 + rdi + 8]
    mov rdi, [r8 + rdi]
    jmp str_eq_cstr
8:  xor eax, eax
    ret

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
    mov rdi, rbx
    call extres_hello           # resources group: how long the start took
    call ext_hooks_update
    mov rdi, rbx
    call hello_features         # the features it named that rhun knows, said back before ready
    mov rdi, rbx
    call extproto_send_folders  # resources group: workspace-folders, before ready
    mov rdi, rbx
    call send_ready
    mov rdi, rbx
    call send_settings          # its own settings, before anything else
    mov rdi, rbx
    call extproto_events        # catch-up: nothing is known yet, so everything open is reported
    mov rdi, rbx
    call rview_ext_ready        # its declared views open (views group, rview.s)
    mov rdi, rbx
    call testproto_ready        # testing: a controller is asked for its roots
    mov rdi, rbx
    call ext_pending_try
    mov rdi, rbx
    call tools_owner_ready      # AI: tool calls that waited for it to start (tools.s)
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
    # replies to rhun's requests (section 12): "ok ID LEN" and its body, "error ID CODE TEXT"; an
    # extension that agreed no feature is asked nothing, and its stray replies are ignored
    xor edi, edi
    lea rsi, [rip + .Lw_ok]
    call field_is
    test eax, eax
    jnz .Lhl_ok
    xor edi, edi
    lea rsi, [rip + .Lw_error]
    call field_is
    test eax, eax
    jnz .Lhl_err
    xor edi, edi
    call field_u64
    test edx, edx
    jz .Lhl_bad_request_id
    test rax, rax
    jz .Lhl_bad_request_id      # events come from rhun, not from extensions
    cmp rax, 2147483647
    ja .Lhl_bad_request_id
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
    lea rax, [rip + h_snippet]
    cmp [r12 + 8], rax
    jne .Lhl_body_number
    call save_number           # snippet lengths must not wrap before framing
    jmp .Lhl_body_parsed
.Lhl_body_number:
    call field_u64
.Lhl_body_parsed:
    test edx, edx
    jz .Lhl_syntax_id          # v1: error ID syntax, the line dropped, no body read
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
.Lhl_ok:
    cmp qword ptr [rip + nfields], 3
    jb .Lhl_bad_frame
    mov edi, 1
    call field_u64
    xor r12d, r12d              # invalid/stray ids still have their framed bodies drained
    test edx, edx
    jz .Lhl_ok_length
    cmp rax, 2147483647
    ja .Lhl_ok_length
    mov r12, rax
.Lhl_ok_length:
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lhl_bad_frame
    cmp qword ptr [rip + body_ptr], 0
    jne 2f
    test rax, rax
    jz 2f                       # no body: answered at once
    cmp rax, REPLY_BODY_MAX
    jbe 1f
    # notebooks: a request may have a cap of its own (nb-open, nb-save: 64 MB)
    push rax
    push rax
    mov rdi, rbx
    mov rsi, r12
    call ext_reply_cap
    mov rcx, rax
    pop rax
    pop rdx
    cmp rax, rcx
    jbe 1f
    mov rdi, rbx                # a body over the cap ends the program, as for requests
    lea rsi, [rip + .Lr_body]
    call ext_kill
    jmp 9f
1:  mov [rbx + EXT_body_len], rax
    mov rdi, [rip + line + SB_ptr]
    mov rsi, [rip + line + SB_len]
    call mem_dup
    mov [rbx + EXT_body], rax
    jmp 9f
2:  test r12, r12
    jz 9f
    mov rdi, rbx                # resources group: slow, dropped
    mov rsi, r12
    mov edx, 1
    call extres_req_answer
    cmp dword ptr [rbx + EXT_feat_asks], 0
    je 9f
    mov rdi, rbx                # resources group: a virtual document's text (vdoc.s)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call vdoc_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # language features: counted, and a late answer goes no further
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call query_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # views group: vkids and vmore answers (rview.s)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call rview_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # testing: tests-resolve and test-run answers
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call testproto_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # AI: transcripts, tool answers, prompts (extaiproto.inc)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call ai_reply
    test eax, eax
    jnz 9f
    # source control (wider-parity C): commit-message and quickdiff answers (scmext.s)
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call scmext_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # wsedit: linked editing's answer (wslinked.s)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call ws_linked_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # notebooks: nb-open, nb-save
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call nb_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # debugger: debug-resolve (debugext.s)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call dbgx_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # editor presentation: folding ranges, tokens, hints ... (present.s)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call present_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # custom editors (ceproto.inc)
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call ce_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call invoke_reply           # a call's answer goes to its caller (invoke.s)
    mov [rip + cur], rbx
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call save_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call complete_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call langfeat_reply
    jmp 9f
.Lhl_err:
    mov edi, 1
    call field_u64
    test edx, edx
    jz 9f
    mov r12, rax
    mov edi, 2                  # resources group: failed, dropped
    lea rsi, [rip + .Le_cancelled]
    call field_is
    lea edx, [rax + rax]        # 2 for cancelled, 0 for any other error
    mov rdi, rbx
    mov rsi, r12
    call extres_req_answer
    cmp dword ptr [rbx + EXT_feat_asks], 0
    je 9f
    mov edi, 2                  # resources group: a virtual document's error (vdoc.s)
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call vdoc_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # language features: counted, and a late answer goes no further
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call query_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # views group: a failed vkids or vmore (rview.s)
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call rview_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # testing: the code and text go with the answer
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call testproto_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # AI: the code and text go with the error (extaiproto.inc)
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call ai_reply
    test eax, eax
    jnz 9f
    # source control (wider-parity C): commit-message and quickdiff errors (scmext.s)
    mov edi, 2
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call scmext_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx                # editor presentation: an error changes nothing (present.s)
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call present_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # a call's error goes to its caller with its code and text
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call invoke_reply           # (invoke.s)
    mov [rip + cur], rbx
    test eax, eax
    jnz 9f
    mov rdi, rbx                # wsedit: linked editing's error (wslinked.s)
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call ws_linked_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # notebooks: nb-open, nb-save, with the code and text
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call nb_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # debugger: debug-resolve's code and text (debugext.s)
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call dbgx_reply
    test eax, eax
    jnz 9f
    mov edi, 2                  # custom editors, with the code and text
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call ce_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call save_reply
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call complete_reply
    test eax, eax
    jnz 9f
    # the code and text after the id, for the user when the request was theirs (rename)
    mov edi, 2
    call rest_from
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call langfeat_reply
    jmp 9f
.Lhl_syntax:
    xor edi, edi
    call reply_syntax
    jmp 9f
.Lhl_syntax_id:
    mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# An invalid request id on a body verb cannot let its payload become new requests.
.Lhl_bad_request_id:
    lea r12, [rip + verbs]
1:  cmp qword ptr [r12], 0
    je .Lhl_syntax
    cmp qword ptr [r12 + 16], 0
    je 2f
    mov edi, 1
    mov rsi, [r12]
    call field_is
    test eax, eax
    jnz .Lhl_bad_frame
2:  add r12, 24
    jmp 1b
.Lhl_bad_frame:
    mov rdi, rbx
    lea rsi, [rip + .Lr_framing]
    call ext_kill
    jmp 9b

# testing (testproto.s): every tests verb goes to testproto_request(ext, id, line, len, body,
# body length), which parses the line itself and answers through ext_send_checked
# tasks and terminals (termproto.s, tasks.s): every terminal and task verb goes to
# termproto_request(ext, id, line, len, body, body length), which answers itself
h_terminals:
    mov rdi, [rip + cur]
    mov rsi, [rip + cur_id]
    mov rdx, [rip + line + SB_ptr]
    mov rcx, [rip + line + SB_len]
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    jmp termproto_request

h_tests:
    mov rdi, [rip + cur]
    mov rsi, [rip + cur_id]
    mov rdx, [rip + line + SB_ptr]
    mov rcx, [rip + line + SB_len]
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    jmp testproto_request

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
    jmp ext_send_checked

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

# ---------------- for verb handlers in other files (editor presentation) ----------------

# xp_field(i) -> rax ptr, rdx len of field i of the message being handled (0, 0 past its fields)
FN xp_field
    cmp rdi, [rip + nfields]
    jae 1f
    jmp field_at
1:  xor eax, eax
    xor edx, edx
    ret
# xp_field_u64(i) -> rax value, rdx 1 when field i is a decimal u64
FN xp_field_u64
    jmp field_u64
# xp_nfields() -> rax
FN xp_nfields
    mov rax, [rip + nfields]
    ret
# xp_cur() -> rax the EXT being served; xp_cur_id() -> rax its request id
FN xp_cur
    mov rax, [rip + cur]
    ret
FN xp_cur_id
    mov rax, [rip + cur_id]
    ret
# xp_body() -> rax ptr, rdx len of the message's body
FN xp_body
    mov rax, [rip + body_ptr]
    mov rdx, [rip + body_len]
    ret
# xp_reply_ok(id), xp_reply_error(id, "code text"), xp_reply_error_u64(id, "code text ", value),
# xp_reply_syntax(id)
FN xp_reply_ok
    jmp reply_ok
FN xp_reply_error
    jmp reply_error
FN xp_reply_error_u64
    jmp reply_error_u64
FN xp_reply_syntax
    jmp reply_syntax
# xp_arg_doc(i) -> rax DOC* of field i, or 0 after replying
FN xp_arg_doc
    jmp arg_doc
# xp_need(NEEDS_*) -> eax 1, or 0 after replying needs
FN xp_need
    jmp need
# xp_send(ext, ptr, len): bytes to an extension as one message (an event line and its body)
FN xp_send
    PROLOGUE
    mov r12, [rip + cur]
    mov [rip + cur], rdi
    mov rbx, rsi
    mov r13, rdx
    call out_begin
    mov rdi, rbx
    mov rsi, r13
    call out_bytes
    call out_end
    mov [rip + cur], r12
    EPILOGUE

# ---------------- for verb handlers in other files (language features: query.s) ----------------

# FN extproto_cur() -> rax the EXT being served; extproto_req_id() -> rax its request's id
FN extproto_cur
    mov rax, [rip + cur]
    ret
FN extproto_req_id
    mov rax, [rip + cur_id]
    ret
# FN extproto_nfields() -> rax the fields of the request's line
FN extproto_nfields
    mov rax, [rip + nfields]
    ret
# FN extproto_field(i) -> rax value, rdx 1 for a decimal number; extproto_field_at(i) -> rax ptr,
# rdx len (0 past the line's fields); extproto_rest(i) -> rax ptr, rdx len: field i to the end
FN extproto_field
    jmp field_u64
FN extproto_field_at
    cmp rdi, [rip + nfields]
    jae 8f
    jmp field_at
8:  xor eax, eax
    xor edx, edx
    ret
FN extproto_rest
    jmp rest_from
# FN extproto_body() -> rax ptr, rdx len of the request's body
FN extproto_body
    mov rax, [rip + body_ptr]
    mov rdx, [rip + body_len]
    ret
# FN extproto_ok(id), extproto_error(id, "code text"): the reply
FN extproto_ok
    jmp reply_ok
FN extproto_error
    jmp reply_error
# FN extproto_error_u64(id, "code text ", value)
FN extproto_error_u64
    jmp reply_error_u64

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
8:  push rdi                    # notebooks (A3): a cell, which has no tab
    call nb_cell_doc_by_id
    pop rdi
    test rax, rax
    jnz 9f
    jmp ce_doc_by_id            # custom editors: a text model's document, in a view's tab
9:  ret

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
    jne 11f
    lea rsi, [rip + .Le_needs_write]
11: cmp edi, NEEDS_TERMINAL
    jne 12f
    lea rsi, [rip + .Le_needs_term]
12: cmp edi, NEEDS_TERM_RUN     # tasks: the task commands of cmd
    jne 2f
    lea rsi, [rip + .Le_needs_term_run]
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
    # Flush edits before the snapshot. Later batches then start after this text's
    # version, even when text and edit requests arrive in the same pump.
    mov rdi, [rip + cur]
    call extproto_events
    test rax, rax
    js 9f
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
    test rax, rax
    js 9f
    mov rdi, rbx
    call snapshot_taken
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
1:  mov rdi, [rip + cur]
    call extproto_events
    test rax, rax
    js 9f
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

# ID snippet-context DOC VERSION L1 C1 L2 C2 -> ok ID VERSION LEN + context.
h_snippet_context:
    PROLOGUE
    mov edi, NEEDS_DOC_READ
    call need
    test eax, eax
    jz 9f
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_SNIPPETS
    jz .Lhsc_unknown
    cmp qword ptr [rip + nfields], 8
    jne .Lhsc_syntax
    xor r12d, r12d
1:  mov rdi, r12
    call save_number
    test edx, edx
    jz .Lhsc_syntax
    test r12, r12
    jnz 2f
    test rax, rax
    jz .Lhsc_syntax
    cmp rax, 2147483647
    ja .Lhsc_syntax
2:  inc r12
    cmp r12, 1
    jne 3f
    inc r12
3:  cmp r12, 8
    jb 1b
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov edi, 3
    call field_u64
    cmp rax, [rbx + DOC_version]
    jne .Lhsc_stale
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
    sub rax, r12
    js .Lhsc_badpos
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call snippet_context
    cmp rax, -1
    je .Lhsc_large
    cmp rax, -2
    je .Lhsc_utf8
    mov r12, rax
    mov r13, rdx
    # Send pending edits before the context, without granting a full-text snapshot.
    mov rdi, [rip + cur]
    call extproto_events
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
    mov rdi, r13
    call out_u64
    mov edi, 10
    call out_byte
    mov rdi, r12
    mov rsi, r13
    call out_bytes
    call out_end
    mov rdi, r12
    call mem_free
9:  EPILOGUE
.Lhsc_unknown:
    lea rsi, [rip + .Le_unknown]
    jmp .Lhsc_error
.Lhsc_large:
    lea rsi, [rip + .Le_context_large]
    jmp .Lhsc_error
.Lhsc_utf8:
    lea rsi, [rip + .Le_context_utf8]
    jmp .Lhsc_error
.Lhsc_badpos:
    lea rsi, [rip + .Le_badpos]
.Lhsc_error:
    mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
.Lhsc_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_stale]
    mov rdx, [rbx + DOC_version]
    call reply_error_u64
    EPILOGUE
.Lhsc_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID snippet DOC VERSION L1 C1 L2 C2 LEN + one prepared completion record.
h_snippet:
    PROLOGUE 32
    mov edi, NEEDS_DOC_WRITE
    call need
    test eax, eax
    jz 9f
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_SNIPPETS
    jz .Lhsn_unknown
    cmp qword ptr [rip + nfields], 9
    jne .Lhsn_syntax
    xor r12d, r12d
.Lhsn_numbers:
    mov rdi, r12
    call save_number
    test edx, edx
    jz .Lhsn_syntax
    inc r12
    cmp r12, 1
    jne 1f
    inc r12                    # field 1 is the verb
1:  cmp r12, 9
    jb .Lhsn_numbers
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lhsn_readonly
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lhsn_syntax
    cmp rax, [rbx + DOC_version]
    jne .Lhsn_stale
    mov rdi, rbx
    call sel_collapse           # a snippet is about one place (multi-cursor)
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
    sub rax, r12
    js .Lhsn_badpos
    mov r13, rax
    mov rdi, [rip + body_ptr]
    mov rsi, [rip + body_len]
    mov rax, [rip + cur]
    mov edx, [rax + EXT_features]
    call snippet_decode_record
    test rax, rax
    jz .Lhsn_syntax
    mov r14, rax
    cmp qword ptr [r14 + SN_transform], 0
    je .Lhsn_indent_done
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call snippet_capture_indent
    test eax, eax
    jnz .Lhsn_indent_done
    mov rdi, r14
    call snippet_free_node
    jmp .Lhsn_syntax
.Lhsn_indent_done:
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    lea rcx, [r12 + r13]
    call snippet_insertion_begin
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [r12 + r13]
    call snippet_replace_range
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [r14 + SN_text]
    mov r8, [r14 + SN_tlen]
    call apply_replace
    mov rax, [r14 + SN_tlen]
    add rax, r12
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
    mov rdi, rbx
    mov rsi, r12
    call snippet_insertion_finish
    mov r12, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call snippet_push
    mov rdi, rbx
    mov rsi, [rsp]
    call snippet_record_after
    mov rdi, [rip + cur_id]
    mov rsi, [rbx + DOC_version]
    call reply_ok_u64
9:  EPILOGUE
.Lhsn_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lhsn_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_stale]
    mov rdx, [rbx + DOC_version]
    call reply_error_u64
    EPILOGUE
.Lhsn_readonly:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_readonly]
    call reply_error
    EPILOGUE
.Lhsn_badpos:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos]
    call reply_error
    EPILOGUE
.Lhsn_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# apply LEN + a workspace edit (section 12g): checked whole, then each document changed as one
# undo step; files that are not open open in tabs, unsaved
h_apply:
    PROLOGUE
    mov edi, NEEDS_DOC_WRITE
    call need
    test eax, eax
    jz 9f
    mov rdi, [rip + body_ptr]
    mov rsi, [rip + body_len]
    mov rdx, [rip + cur]
    mov rcx, [rip + cur_id]
    call ws_apply_request
    cmp eax, 2
    je 9f                       # wsedit: the confirmation list answers when the user does
    test eax, eax
    jz 1f
    mov rdi, [rip + cur_id]
    call reply_ok
    jmp 9f
1:  mov rdi, [rip + cur_id]
    mov rsi, rdx
    call reply_error
9:  EPILOGUE

# wsedit: FN extproto_reply_to(ext, id, error "CODE TEXT" or 0): a reply that waited (an apply
# request the confirmation list held)
FN extproto_reply_to
    PROLOGUE
    mov rbx, [rip + cur]
    mov [rip + cur], rdi
    mov r12, rdx
    mov rdi, rsi
    test r12, r12
    jnz 1f
    call reply_ok
    jmp 2f
1:  mov rsi, r12
    call reply_error
2:  mov [rip + cur], rbx
    EPILOGUE

# Additive protocol identity/position fields are decimal int64 values, with overflow rejected.
save_number:
    call field_at
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 7f
    movzx edx, byte ptr [rdi + rcx]
    sub edx, '0'
    cmp edx, 9
    ja 8f
    mov r8, 922337203685477580
    cmp rax, r8
    ja 8f
    jb 2f
    cmp edx, 7
    ja 8f
2:  imul rax, rax, 10
    add rax, rdx
    inc rcx
    jmp 1b
7:  mov edx, 1
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# save-apply SAVE_REQUEST DOC VERSION LEN. The source job alone grants intermediate authority.
h_save_apply:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_SAVE_ACTIONS
    jz .Lhsa_unknown
    mov edi, NEEDS_DOC_WRITE
    call need
    test eax, eax
    jz .Lhsa_done
    cmp qword ptr [rip + nfields], 6
    jne .Lhsa_syntax
    mov edi, 2
    call save_number
    test edx, edx
    jz .Lhsa_syntax
    test rax, rax
    jz .Lhsa_syntax
    cmp rax, 2147483647
    ja .Lhsa_syntax
    mov r12, rax
    mov edi, 3
    call save_number
    test edx, edx
    jz .Lhsa_syntax
    test rax, rax
    jle .Lhsa_syntax
    mov r13, rax
    mov edi, 4
    call save_number
    test edx, edx
    jz .Lhsa_syntax
    test rax, rax
    js .Lhsa_syntax
    mov rdi, [rip + cur]
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    call save_apply
    test rax, rax
    js 1f
    mov rsi, rax
    mov rdi, [rip + cur_id]
    call reply_ok_u64
    jmp .Lhsa_done
1:  cmp rax, -2
    jne 2f
    lea rsi, [rip + .Le_stale]
    mov rdi, [rip + cur_id]
    call reply_error_u64
    jmp .Lhsa_done
2:  lea rsi, [rip + .Le_save_apply]
    jmp .Lhsa_error
.Lhsa_unknown:
    lea rsi, [rip + .Le_unknown]
.Lhsa_error:
    mov rdi, [rip + cur_id]
    call reply_error
    jmp .Lhsa_done
.Lhsa_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
.Lhsa_done:
    EPILOGUE

# apply_replace(doc, pos, len, ptr, blen): one undo step; the cursor and anchor follow the text
apply_replace:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    # where the cursor and the anchor end (section 4: one inside the range goes after the new
    # text; the editor's own rule would leave it at the range's start)
    mov rax, [rbx + DOC_cur]
    mov [rsp], rax
    lea rdi, [rsp]
    call move_mark
    mov rax, [rbx + DOC_anchor]
    mov [rsp + 8], rax
    lea rdi, [rsp + 8]
    call move_mark
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
    # through the editor, so the view follows
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call set_marks
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# move_mark(ptr to a position): where it is after [r12, r12+r13) is replaced with r15 bytes
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

# set_marks(doc, cur, anchor): through the editor (which reveals the cursor) for the document on
# screen, directly for any other
set_marks:
    cmp rdi, [rip + g_doc]
    je 1f
    mov [rdi + DOC_cur], rsi
    mov [rdi + DOC_anchor], rdx
    jmp snippet_selection_changed
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
    # feature selections: at every selection, as typing would
    cmp qword ptr [rbx + DOC_selections], 0
    je 2f
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_SELECTIONS
    jz 2f
    mov rdi, rbx
    call sel_insert_all
    test rax, rax
    jz 9f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_error
    jmp 9f
2:  mov rdi, rbx
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
    call sel_collapse           # one selection (multi-cursor)
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
    mov rdi, rbx                # the status item _v1 (statusitems.s)
    mov rsi, [rbx + EXT_status_text]
    call status_v1_set
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE

# utf8_cut(len, ptr, max) -> the length to keep: at most max bytes, not ending inside a character
FN utf8_cut
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
    mov rdi, rax                # resources group: a URI (feature uris; extresproto.inc)
    mov rsi, rdx
    mov rdx, r12
    mov rcx, r13
    call res_open_uri
    cmp rax, -1
    je .Lho_done
    mov rdi, rax
    mov rsi, rdx
    cmp byte ptr [rdi], '/'
    je 1f
.ifdef WINDOWS
    # D:/x, D:\x, \\server\share are absolute too
    cmp byte ptr [rdi], 92
    je 1f
    cmp rsi, 3
    jb 4f
    cmp byte ptr [rdi + 1], ':'
    jne 4f
    cmp byte ptr [rdi + 2], '/'
    je 1f
    cmp byte ptr [rdi + 2], 92
    je 1f
4:
.endif
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
.ifdef WINDOWS
    mov rdi, rax
    call win_slashes            # backslashes, as Windows programs write them
.endif
    mov rdi, r14
    call vfs_type
    cmp eax, 0x8000             # a regular file
    jne .Lho_missing
    mov rdi, [rip + cur]
    mov rsi, r14
    call ext_open_path
    mov r15, rax
    mov rdi, r14
    call mem_free
    test r15, r15
    jz .Lho_denied
    mov r14, r15
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
.Lho_denied:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_file_needs]
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
.Lho_done:
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
    push rbx
    mov edi, 2                  # AI: a tool call it no longer wants (tools.s)
    call field_u64
    test edx, edx
    jz 0f
    mov rdi, [rip + cur]
    mov rsi, rax
    call tools_cancel
    mov edi, 2                  # or a card of one of its sessions (agentext.s)
    call field_u64
    mov rdi, [rip + cur]
    mov rsi, rax
    call agentext_cancel
    mov edi, 2                  # a terminal-open waiting for the approval dialog: answered cancelled (termproto.s)
    call field_u64
    mov rdi, [rip + cur]
    mov rsi, rax
    call termproto_cancel
    mov edi, 2                  # resources group: a find or search (filesearch.s)
    call field_u64
    test edx, edx
    jz 0f
    mov rdi, [rip + cur]
    mov rsi, rax
    call filesearch_cancel
0:  pop rbx
    # of this extension's open prompt: the prompt closes, answered cancelled
    cmp qword ptr [rip + pr_id], 0
    je 1f
    mov rax, [rip + cur]
    cmp [rip + pr_ext], rax
    jne 1f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 1f
    cmp rax, [rip + pr_id]
    jne 1f
    call palette_close          # extproto_prompt_abort answers it
1:  mov rdi, [rip + cur_id]
    jmp reply_ok

# field_at(i) -> rax ptr, rdx len
field_at:
    lea r8, [rip + fields]
    shl rdi, 4
    mov rax, [r8 + rdi]
    mov rdx, [r8 + rdi + 8]
    ret

# ---------------- gate 4: register, option, prompts, cmd ----------------

# ID register NAME KEYS TITLE -> ok ID: a command for this session
h_register:
    PROLOGUE
    cmp qword ptr [rip + nfields], 5
    jb .Lhreg_syntax
    mov edi, 2
    call field_at
    mov r12, rax
    mov r13, rdx                # name
    test rdx, rdx
    jz .Lhreg_syntax
    cmp rdx, 40
    ja .Lhreg_syntax
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    movzx eax, byte ptr [r12 + rcx]
    inc rcx
    cmp al, '_'
    je 1b
    sub al, '0'
    cmp al, 9
    jbe 1b
    sub al, 'a' - '0'
    cmp al, 25
    jbe 1b
    jmp .Lhreg_syntax
2:  mov edi, 4
    call rest_from
    mov rdi, rdx
    mov rsi, rax
    mov edx, 80
    push rsi
    call utf8_cut
    pop rsi
    mov rdx, rax
    lea rdi, [rip + out]
    push rsi
    push rdx
    call sb_clear
    pop rdx
    pop rsi
    lea rdi, [rip + out]
    call sb_push
    lea rdi, [rip + out]
    xor esi, esi
    call sb_push_byte           # the title, as a cstr
    mov edi, 3
    call field_at
    mov rcx, rax
    mov r8, rdx                 # keys
    mov rdi, [rip + cur]
    mov rsi, r12
    mov rdx, r13
    mov r9, [rip + out + SB_ptr]
    call ext_cmd_register
    test eax, eax
    jz 8f
    lea rsi, [rip + .Le_refused_name]
    cmp eax, 1
    je 7f
    lea rsi, [rip + .Le_toobig_cmds]
7:  mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lhreg_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID unregister NAME -> ok ID: negotiated command lifecycle, only the caller's runtime commands.
h_unregister:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_COMMANDS
    jz .Lhun_unknown
    cmp qword ptr [rip + nfields], 3
    jne .Lhun_syntax
    mov edi, 2
    call field_at
    mov r12, rax
    mov r13, rdx
    test rdx, rdx
    jz .Lhun_syntax
    cmp rdx, 40
    ja .Lhun_syntax
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    movzx eax, byte ptr [r12 + rcx]
    inc rcx
    cmp al, '_'
    je 1b
    sub al, '0'
    cmp al, 9
    jbe 1b
    sub al, 'a' - '0'
    cmp al, 25
    jbe 1b
    jmp .Lhun_syntax
2:  mov rdi, [rip + cur]
    mov rsi, r12
    mov rdx, r13
    call ext_cmd_unregister
    test eax, eax
    jnz .Lhun_refused
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lhun_unknown:
    lea rsi, [rip + .Le_unknown]
    jmp .Lhun_error
.Lhun_refused:
    lea rsi, [rip + .Le_refused_unregister]
.Lhun_error:
    mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
.Lhun_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID option DOC KEY VALUE -> ok ID: a per-document override (section 6c)
h_option:
    PROLOGUE
    cmp qword ptr [rip + nfields], 5
    jne .Lhop_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz .Lhop_ret
    mov rbx, rax
    xor r12d, r12d              # the key's index
1:  cmp r12d, 4
    jae .Lhop_syntax
    lea rax, [rip + opt_names]
    mov rsi, [rax + r12*8]
    mov edi, 3
    call field_is
    test eax, eax
    jnz 2f
    inc r12d
    jmp 1b
2:  cmp r12d, OPT_TRIM
    jb 21f
    mov edi, NEEDS_DOC_WRITE    # trim and the final newline change what is written to disk
    call need
    test eax, eax
    jz .Lhop_ret
21: mov edi, 4
    lea rsi, [rip + .Lo_dash]
    call field_is
    test eax, eax
    jz 3f
    # remove this extension's override
    mov rax, [rip + cur]
    cmp [rbx + DOC_oown + r12*8], rax
    jne 8f
    mov qword ptr [rbx + DOC_oown + r12*8], 0
    mov dword ptr [rbx + DOC_oval + r12*4], 0
    jmp 8f
3:  test r12d, r12d
    jnz 4f
    mov edi, 4
    call field_u64
    test edx, edx
    jz .Lhop_syntax
    test rax, rax
    jz .Lhop_syntax
    cmp rax, 16
    ja .Lhop_syntax
    jmp 6f
4:  mov eax, 2
    mov edi, 4
    lea rsi, [rip + .Lo_yes]
    call field_is
    test eax, eax
    mov eax, 2
    jnz 6f
    mov edi, 4
    lea rsi, [rip + .Lo_no]
    call field_is
    test eax, eax
    jz .Lhop_syntax
    mov eax, 1
6:  mov [rbx + DOC_oval + r12*4], eax
    mov rax, [rip + cur]
    mov [rbx + DOC_oown + r12*8], rax
8:  call ext_options_apply
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
.Lhop_ret:
    EPILOGUE
.Lhop_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# prompt_busy() -> 1 after replying busy when a prompt or the palette is open
prompt_busy:
    cmp qword ptr [rip + pr_id], 0
    jne 1f
    push rax
    call palette_is_open
    pop rcx
    test eax, eax
    jnz 1f
    push rax
    call quick_is_open          # an extension's quick input (quick.s)
    pop rcx
    test eax, eax
    jnz 1f
    xor eax, eax
    ret
1:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_busy]
    call reply_error
    mov eax, 1
    ret

# prompt_begin(kind): the open prompt is cur's current request
prompt_begin:
    push rbx
    mov [rip + pr_kind], rdi
    mov rax, [rip + cur]
    mov [rip + pr_ext], rax
    mov rax, [rip + cur_id]
    mov [rip + pr_id], rax
    call time_ms
    mov [rip + pr_opened], rax
    pop rbx
    ret

# extproto_prompt_fresh() -> 1 while a term prompt is less than half a second old: an Enter that
# early was meant for whatever had the focus before the prompt appeared
FN extproto_prompt_fresh
    xor eax, eax
    cmp qword ptr [rip + pr_kind], 3
    jne 9f
    push rbx
    call time_ms
    pop rbx
    sub rax, [rip + pr_opened]
    cmp rax, 500
    jge 8f
    mov eax, 1
    ret
8:  xor eax, eax
9:  ret

# prompt_clear(): no prompt is open
prompt_clear:
    push rbx
    mov rdi, [rip + pr_body]
    call mem_free
    mov qword ptr [rip + pr_body], 0
    mov qword ptr [rip + pr_id], 0
    mov qword ptr [rip + pr_ext], 0
    mov qword ptr [rip + pr_kind], 0
    mov qword ptr [rip + pr_tool], 0    # AI (extaiproto.inc)
    pop rbx
    ret

# set_label(ptr, len): the prompt text into pr_label, the first line only, at most 200 bytes
set_label:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  push rdi
    mov rsi, rdi
    mov rdi, rcx
    mov edx, 200
    call utf8_cut
    pop rsi
    lea rdi, [rip + pr_label]
    mov rdx, rax
    mov byte ptr [rdi + rax], 0
    jmp memcpy

# ID choose LEN + body -> ok ID N when the user picks the N-th item (section 8), or cancelled
h_choose:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jne .Lhc_syntax
    call prompt_busy
    test eax, eax
    jnz .Lhc_ret
    mov r12, [rip + body_ptr]
    mov r13, [rip + body_len]
    # the first line is the prompt
    xor ebx, ebx
1:  cmp rbx, r13
    jae .Lhc_syntax             # no items
    cmp byte ptr [r12 + rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, r12
    mov rsi, rbx
    call set_label
    inc rbx                     # the items start here
    # count the item lines
    xor r14d, r14d              # items
    xor r15d, r15d              # non-empty items
    mov rcx, rbx
3:  cmp rcx, r13
    jae 4f
    mov rdx, rcx
31: cmp rdx, r13
    jae 32f
    cmp byte ptr [r12 + rdx], 10
    je 32f
    inc rdx
    jmp 31b
32: inc r14
    cmp rdx, rcx
    je 33f
    inc r15
33: lea rcx, [rdx + 1]
    jmp 3b
4:  test r15, r15
    jz .Lhc_syntax
    cmp r14, EXT_CHOOSE_MAX
    ja .Lhc_toobig
    # the items' bytes outlive the receive buffer
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rip + pr_body], rax
    mov r12, rax
    lea rdi, [rip + pr_label]
    call palette_choose_open
    xor r14d, r14d              # item number - 1
    mov rcx, rbx
5:  cmp rcx, r13
    jae 7f
    mov rdx, rcx
51: cmp rdx, r13
    jae 52f
    cmp byte ptr [r12 + rdx], 10
    je 52f
    inc rdx
    jmp 51b
52: inc r14
    mov rsi, rdx
    sub rsi, rcx
    jz 6f                       # an empty line keeps its number but is not shown
    push rcx
    push rdx
    lea rdi, [r12 + rcx]
    mov rdi, rsi
    lea rsi, [r12 + rcx]
    mov edx, 200
    call utf8_cut
    pop rdx
    pop rcx
    push rcx
    push rdx
    lea rdi, [r12 + rcx]
    mov rsi, rax
    mov rdx, r14
    call palette_choose_add
    pop rdx
    pop rcx
6:  lea rcx, [rdx + 1]
    jmp 5b
7:  call palette_choose_ready
    mov edi, 1
    call prompt_begin
.Lhc_ret:
    EPILOGUE
.Lhc_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_items]
    call reply_error
    EPILOGUE
.Lhc_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID ask LEN + body -> ok ID LEN + the answer, or cancelled
h_ask:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jne .Lha_syntax
    call prompt_busy
    test eax, eax
    jnz .Lha_ret
    mov rdi, [rip + body_ptr]
    mov rsi, [rip + body_len]
    call set_label
    lea rdi, [rip + pr_label]
    mov esi, PROMPT_ASK
    xor edx, edx
    xor ecx, ecx
    call palette_ext_prompt_open
    mov edi, 2
    call prompt_begin
.Lha_ret:
    EPILOGUE
.Lha_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID term LEN + body -> ok ID once the user ran it in the terminal, or cancelled
h_term:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jne .Lht_syntax
    mov edi, NEEDS_TERMINAL
    call need
    test eax, eax
    jz .Lht_ret
    mov r12, [rip + body_ptr]
    mov r13, [rip + body_len]
    test r13, r13
    jz .Lht_syntax
    cmp r13, EXT_TERM_MAX
    ja .Lht_toobig
    mov rdi, r12
    mov rsi, r13
    call plain_text             # one line of valid UTF-8, nothing that hides or reorders text
    test eax, eax
    jz .Lht_syntax              # what is shown is what runs
    call prompt_busy
    test eax, eax
    jnz .Lht_ret
    lea rdi, [rip + .Lrun_label]
    mov esi, PROMPT_TERM
    mov rdx, r12
    mov rcx, r13
    call palette_ext_prompt_open
    call palette_field
    mov qword ptr [rax + TF_cur], 0     # the start of the command is what the user sees
    mov qword ptr [rax + TF_anchor], 0
    mov edi, 3
    call prompt_begin
.Lht_ret:
    EPILOGUE
.Lht_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_term]
    call reply_error
    EPILOGUE
.Lht_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID cmd NAME -> ok ID: one of rhun's own commands, from the list of section 8a
# ---------------- views (section 12a) ----------------

# view_agreed() -> ZF clear when the views feature was agreed; otherwise the reply is sent
view_agreed:
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_VIEWS
    jnz 1f
    push rax
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    pop rax
    xor eax, eax                # ZF set: answered
1:  ret

# ID view TITLE -> ok ID VIEW
h_view:
    PROLOGUE
    call view_agreed
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jb .Lhvw_syntax
    mov edi, 2
    call rest_from
    mov rdi, [rip + cur]
    mov rsi, rax
    call extview_open
    test rax, rax
    js .Lhvw_toobig
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
.Lhvw_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_views]
    call reply_error
    EPILOGUE
.Lhvw_syntax:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_syntax]
    call reply_error
9:  EPILOGUE

# view_arg() -> rax the VW* named by field 2, or 0 with the reply sent
view_arg:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jb 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 8f
    mov rdx, rax
    shr rdx, 32
    jnz 8f                     # reject before narrowing the native view id
    mov rdi, [rip + cur]
    mov esi, eax
    call extview_find
    test rax, rax
    jnz 9f
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noview]
    call reply_error
    xor eax, eax
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_syntax]
    call reply_error
    xor eax, eax
9:  EPILOGUE

# ID draw VIEW LEN + body -> ok ID: the view's picture
h_draw:
    PROLOGUE
    call view_agreed
    jz 9f
    call view_arg
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, [rip + body_ptr]
    mov rdx, [rip + body_len]
    call extview_set
    test eax, eax
    jnz 1f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
1:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_syntax_line]
    mov edx, eax
    call reply_error_u64
9:  EPILOGUE

# ID unview VIEW -> ok ID: its tab closes
h_unview:
    PROLOGUE
    mov rax, [rip + cur]        # a retained view's tab first (views group, rview.s)
    FEAT_TEST rax, FEAT_VIEW_TREE
    jz 1f
    cmp qword ptr [rip + nfields], 3
    jne 1f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 1f
    mov rdi, [rip + cur]
    mov esi, eax
    call rview_unview
    cmp eax, 1
    je 1f
    test eax, eax
    jnz 2f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
2:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_refused_unview]
    call reply_error
    EPILOGUE
1:  call view_agreed
    jz 9f
    call view_arg
    test rax, rax
    jz 9f
    mov rdi, rax
    call extview_close
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE

# ---- retained views (views group, rview.s) ----

# vtree_agreed() -> ZF clear when view-tree was agreed; otherwise the reply is sent
vtree_agreed:
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_VIEW_TREE
    jnz 1f
    push rax
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    pop rax
    xor eax, eax
1:  ret

# ID vpatch VIEW LEN + patch -> ok ID REV, applied whole or not at all
h_vpatch:
    PROLOGUE
    call vtree_agreed
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    mov rdx, rax
    shr rdx, 32
    jnz 8f
    mov rdi, [rip + cur]
    mov esi, eax
    mov rdx, [rip + body_ptr]
    mov rcx, [rip + body_len]
    call rview_patch
    test rax, rax
    js 6f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
6:  call rview_error
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_error
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noview]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID vtab KIND TITLE -> ok ID VIEW: a retained view in an editor tab of its own
h_vtab:
    PROLOGUE
    call vtree_agreed
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jb 7f
    mov edi, 3
    call rest_from
    mov r12, rax
    mov r13, rdx
    mov edi, 2
    call field_at
    mov rdi, [rip + cur]
    mov rsi, rax
    mov rcx, r12
    mov r8, r13
    call rview_tab
    cmp rax, -1
    je 6f
    cmp rax, -2
    je 5f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
5:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_vtab]
    call reply_error
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# feat_or_unknown(FEAT index) -> eax 1 when the extension agreed it, else unknown is answered
feat_or_unknown:
    push rbx
    mov rax, [rip + cur]
    mov esi, edi
    mov rdi, rax
    call ext_feature
    test eax, eax
    jnz 1f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    xor eax, eax
1:  pop rbx
    ret

# ID notify SEVERITY LEN + body -> ok ID NOTE: a notification card (notify.s)
h_notify:
    PROLOGUE
    mov edi, FEAT_NOTIFY
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jne 7f
    mov edi, 2
    call field_at
    mov rdi, [rip + cur]
    mov rsi, rax
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call notify_request
    cmp rax, -1
    je 7f
    cmp rax, -2
    je 6f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_notes]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID notify-set NOTE LEN + body -> ok ID: new content (a card that is gone: noview)
h_notify_set:
    PROLOGUE
    mov edi, FEAT_NOTIFY
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff          # past an id rhun gives: no such one
    ja 6f
    mov rdi, [rip + cur]
    mov esi, eax
    mov rdx, [rip + body_ptr]
    mov rcx, [rip + body_len]
    call notify_set_request
    cmp eax, 2
    je 7f
    cmp eax, 1
    je 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nonote]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID unnotify NOTE -> ok ID: the card closes without an event
h_unnotify:
    PROLOGUE
    mov edi, FEAT_NOTIFY
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff          # past an id rhun gives: no such one
    ja 6f
    mov rdi, [rip + cur]
    mov esi, eax
    call notify_close_request
    test eax, eax
    jnz 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nonote]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID progress WHERE CANCEL LEN + title -> ok ID P
h_progress:
    PROLOGUE
    mov edi, FEAT_PROGRESS
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 5
    jne 7f
    mov rcx, [rip + body_len]   # a title: one line, not empty
    test rcx, rcx
    jz 7f
    mov rax, [rip + body_ptr]
1:  cmp byte ptr [rax + rcx - 1], 10
    je 7f
    dec rcx
    jnz 1b
    mov edi, 3
    call field_at
    mov r12, rax
    mov r13, rdx
    mov edi, 2
    call field_at
    push qword ptr [rip + body_len]
    push qword ptr [rip + body_len]
    mov rdi, [rip + cur]
    mov rsi, rax
    mov rcx, r12
    mov r8, r13
    mov r9, [rip + body_ptr]
    call progress_request
    add rsp, 16
    cmp rax, -1
    je 7f
    cmp rax, -2
    je 6f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_progress]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID progress-set P PERCENT LEN + message -> ok ID (PERCENT 0-100 or -; a progress that is gone: noview)
h_progress_set:
    PROLOGUE
    mov edi, FEAT_PROGRESS
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 5
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff          # past an id rhun gives: no such one
    ja 6f
    mov r12, rax
    mov r13, -1
    mov edi, 3
    lea rsi, [rip + .Lw_dash_pct]
    call field_is
    test eax, eax
    jnz 1f
    mov edi, 3
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 100
    ja 7f
    mov r13, rax
1:  mov rdi, [rip + cur]
    mov esi, r12d
    mov edx, r13d
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call progress_set_request
    test eax, eax
    jnz 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noprogress]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID progress-end P -> ok ID
h_progress_end:
    PROLOGUE
    mov edi, FEAT_PROGRESS
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff          # past an id rhun gives: no such one
    ja 6f
    mov rdi, [rip + cur]
    mov esi, eax
    call progress_end_request
    test eax, eax
    jnz 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noprogress]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID vimage LEN + PNG, JPEG or GIF -> ok ID IMG: decoded once, kept until unimage or the end
h_vimage:
    PROLOGUE
    mov edi, FEAT_VIEW_IMAGES
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    mov rdi, [rip + cur]
    mov rsi, [rip + body_ptr]
    mov rdx, [rip + body_len]
    call viewimg_request
    cmp rax, -1
    je 7f
    cmp rax, -2
    je 6f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_images]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID unimage IMG -> ok ID
# ID quick LEN + step body -> ok ID Q: an extension's quick input (quick.s); busy while one, the
#   palette or a prompt shows
h_quick:
    PROLOGUE
    mov edi, FEAT_QUICK_INPUT
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    cmp qword ptr [rip + pr_id], 0
    jne 5f
    mov rdi, [rip + cur]
    mov rsi, [rip + body_ptr]
    mov rdx, [rip + body_len]
    call quick_open
    cmp rax, -1
    je 7f
    cmp rax, -2
    je 6f
    cmp rax, -3
    je 5f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
    EPILOGUE
5:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_busy]
    call reply_error
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_quick]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID quick-set Q LEN + step body -> ok ID: what the records name changes (no such session: noview)
h_quick_set:
    PROLOGUE
    mov edi, FEAT_QUICK_INPUT
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff
    ja 5f
    mov rdi, [rip + cur]
    mov esi, eax
    mov rdx, [rip + body_ptr]
    mov rcx, [rip + body_len]
    call quick_set
    cmp eax, 1
    je 5f
    cmp eax, 2
    je 7f
    cmp eax, 3
    je 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
5:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noquick]
    call reply_error
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_toobig_quick]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID quick-close Q -> ok ID: it closes without a hide event
h_quick_close:
    PROLOGUE
    mov edi, FEAT_QUICK_INPUT
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff
    ja 5f
    mov rdi, [rip + cur]
    mov esi, eax
    call quick_close
    test eax, eax
    jnz 5f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
5:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noquick]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

h_unimage:
    PROLOGUE
    mov edi, FEAT_VIEW_IMAGES
    call feat_or_unknown
    test eax, eax
    jz 9f
    cmp qword ptr [rip + nfields], 3
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    cmp rax, 0x7fffffff          # past an id rhun gives: no such one
    ja 6f
    mov rdi, [rip + cur]
    mov esi, eax
    call viewimg_unimage
    test eax, eax
    jnz 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noimage]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID vreveal VIEW HOW LEN + node id -> ok ID: its ancestors expand, it scrolls into view
h_vreveal:
    PROLOGUE
    call vtree_agreed
    jz 9f
    cmp qword ptr [rip + nfields], 5
    jne 7f
    mov edi, 2
    call field_u64
    test edx, edx
    jz 7f
    mov r12, rax
    mov edi, 3
    call field_at
    mov rdi, [rip + cur]
    mov esi, r12d
    mov rcx, rdx
    mov rdx, rax
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    call rview_reveal
    cmp eax, 1
    je 5f
    cmp eax, 2
    je 6f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
5:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_noview]
    call reply_error
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos_vreveal]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID vshow NAME FOCUS -> ok ID VIEW: a declared view's place opens on it
h_vshow:
    PROLOGUE
    call vtree_agreed
    jz 9f
    cmp qword ptr [rip + nfields], 4
    jne 7f
    xor r12d, r12d
    mov edi, 3
    lea rsi, [rip + .Lvs_focus]
    call field_is
    test eax, eax
    jz 1f
    mov r12d, 1
    jmp 2f
1:  mov edi, 3
    lea rsi, [rip + .Ldash]
    call field_is
    test eax, eax
    jz 7f
2:  mov edi, 2
    call field_at
    mov rdi, [rip + cur]
    mov rsi, rax
    mov ecx, r12d
    call rview_show
    cmp eax, -1
    je 6f
    mov rdi, [rip + cur_id]
    mov esi, eax
    call reply_ok_u64
    EPILOGUE
6:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_refused_vshow]
    call reply_error
    EPILOGUE
7:  mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

h_cmd:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jne .Lhcm_syntax
    lea rbx, [rip + cmd_allow]
1:  mov rsi, [rbx]
    test rsi, rsi
    jz .Lhcm_refused
    add rbx, 16
    mov edi, 2
    call field_is
    test eax, eax
    jz 1b
    mov edi, [rbx - 8]          # what the command needs: a document write, the terminal
    test edi, edi
    jz 2f
    call need
    test eax, eax
    jz .Lhcm_ret
2:  mov edi, 2
    call field_at
    mov rdi, rax
    mov rsi, rdx
    call cmd_find
    test rax, rax
    jz .Lhcm_refused
    mov r12, rax
    mov rdi, [rip + cur_id]
    call reply_ok
    mov rdi, r12
    call [r12 + CMD_fn]
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
.Lhcm_refused:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_refused_cmd]
    call reply_error
.Lhcm_ret:
    EPILOGUE

# ---------------- contributions and commands ----------------

# FN extproto_set_cur(ext): the extension being served again (extproto_cur), after sending to
# another one (events and cancels switch it)
FN extproto_set_cur
    mov [rip + cur], rdi
    ret

# ID status-item ITEM LEN + body -> ok ID: adds or replaces a status bar item (feature status-items,
# statusitems.s)
h_status_item:
    PROLOGUE
    mov rbx, [rip + cur]
    FEAT_TEST rbx, FEAT_STATUS_ITEMS
    jz .Lhsi_unknown
    cmp qword ptr [rip + nfields], 4
    jne .Lhsi_syntax
    mov edi, 2
    call field_at
    mov rdi, rbx
    mov rsi, rax
    mov rcx, [rip + body_ptr]
    mov r8, [rip + body_len]
    call status_item_set
    test eax, eax
    jz .Lhsi_ok
    cmp eax, 1
    jne .Lhsi_syntax
    lea rsi, [rip + .Le_toobig_status]
    jmp .Lhsi_error
# ID status-remove ITEM -> ok ID
h_status_remove:
    PROLOGUE
    mov rbx, [rip + cur]
    FEAT_TEST rbx, FEAT_STATUS_ITEMS
    jz .Lhsi_unknown
    cmp qword ptr [rip + nfields], 3
    jne .Lhsi_syntax
    mov edi, 2
    call field_at
    mov rdi, rbx
    mov rsi, rax
    call status_item_remove
.Lhsi_ok:
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lhsi_unknown:
    lea rsi, [rip + .Le_unknown]
.Lhsi_error:
    mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
.Lhsi_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID run-command NAME LEN + ARGS: a built-in, or another extension's callable command (feature
# command-args; invoke.s answers, now or when the call comes back)
h_run_command:
    PROLOGUE
    mov rbx, [rip + cur]
    FEAT_TEST rbx, FEAT_COMMAND_ARGS
    jz .Lhrc_unknown
    cmp qword ptr [rip + nfields], 4
    jne .Lhrc_syntax
    mov edi, 2
    call field_at
    mov rdi, rbx
    mov rsi, [rip + cur_id]
    mov rcx, rdx
    mov rdx, rax
    mov r8, [rip + body_ptr]
    mov r9, [rip + body_len]
    call invoke_run
    mov [rip + cur], rbx
    test eax, eax
    jnz .Lhrc_syntax
    EPILOGUE
.Lhrc_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lhrc_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID set-context KEY VALUE -> ok ID: the extension's context key KEY (feature context-keys);
# VALUE is the rest of the line, "-" removes it (extcontext.s)
h_set_context:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_CONTEXT_KEYS
    jz .Lhctx_unknown
    cmp qword ptr [rip + nfields], 4
    jb .Lhctx_syntax
    mov edi, 3
    call rest_from
    mov r12, rax
    mov r13, rdx
    cmp r13, CTX_VAL_MAX
    ja .Lhctx_long
    mov rdi, r12
    mov rsi, r13
    call plain_text
    test eax, eax
    jz .Lhctx_syntax
    cmp r13, 1
    jne 1f
    cmp byte ptr [r12], '-'
    jne 1f
    xor r13d, r13d
1:  mov edi, 2
    call field_at
    mov rsi, rax
    mov rdi, [rip + cur]
    mov rcx, r12
    mov r8, r13
    call xc_set
    test eax, eax
    jnz 2f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
2:  cmp eax, 1
    jne .Lhctx_syntax
    lea rsi, [rip + .Le_toobig_keys]
    jmp .Lhctx_error
.Lhctx_long:
    lea rsi, [rip + .Le_toobig_value]
    jmp .Lhctx_error
.Lhctx_unknown:
    lea rsi, [rip + .Le_unknown]
.Lhctx_error:
    mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
.Lhctx_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

.globl plain_text              # (also taskdef.s: labels and commands of tasks)
# plain_text(ptr, len) -> 1 when the bytes are one line of valid UTF-8 with no control
# character (C0, DEL, C1), no bidi control (U+202A-202E, U+2066-2069) and no zero-width
# character (U+200B-200F, U+2060, U+FEFF): text that shows as it is
plain_text:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    movzx eax, byte ptr [rdi + rcx]
    cmp al, 0x20
    jb 8f
    cmp al, 0x7f
    je 8f
    jb 7f                       # ASCII
    cmp al, 0xc2
    jb 8f                       # a continuation byte or an overlong lead
    cmp al, 0xf4
    ja 8f
    # the sequence length and its continuation bytes
    mov edx, 1
    cmp al, 0xe0
    jb 2f
    inc edx
    cmp al, 0xf0
    jb 2f
    inc edx
2:  lea r8, [rcx + rdx]
    cmp r8, rsi
    jae 8f                      # cut short
    push rcx
    push rdx
3:  inc rcx
    movzx r9d, byte ptr [rdi + rcx]
    and r9d, 0xc0
    cmp r9d, 0x80
    jne 6f
    dec edx
    jnz 3b
    pop rdx
    pop rcx
    # the characters that hide or reorder what follows
    cmp al, 0xc2
    jne 4f
    movzx r9d, byte ptr [rdi + rcx + 1]
    cmp r9d, 0xa0
    jb 8f                       # U+0080-009F
4:  cmp al, 0xe2
    jne 5f
    movzx r9d, byte ptr [rdi + rcx + 1]
    movzx r10d, byte ptr [rdi + rcx + 2]
    cmp r9d, 0x80
    jne 41f
    cmp r10d, 0x8b
    jb 5f
    cmp r10d, 0x8f
    jbe 8f                      # U+200B-200F
    cmp r10d, 0xaa
    jb 5f
    cmp r10d, 0xae
    jbe 8f                      # U+202A-202E
    jmp 5f
41: cmp r9d, 0x81
    jne 5f
    cmp r10d, 0xa0
    je 8f                       # U+2060
    cmp r10d, 0xa6
    jb 5f
    cmp r10d, 0xa9
    jbe 8f                      # U+2066-2069
5:  cmp al, 0xef
    jne 51f
    cmp byte ptr [rdi + rcx + 1], 0xbb
    jne 51f
    cmp byte ptr [rdi + rcx + 2], 0xbf
    je 8f                       # U+FEFF
51: add rcx, rdx
7:  inc rcx
    jmp 1b
6:  pop rdx
    pop rcx
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret
.Lhcm_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# extproto_prompt_abort(): the open prompt, if any, is answered cancelled (the palette closed or
# changed mode under it)
FN extproto_prompt_abort
    PROLOGUE
    cmp qword ptr [rip + pr_id], 0
    je 9f
    mov rbx, [rip + cur]
    mov rax, [rip + pr_ext]
    mov [rip + cur], rax
    xor edi, edi                # cancelled (AI: rhun.run's call, extaiproto.inc)
    call prompt_term_answer
    mov [rip + cur], rbx
    call prompt_clear
9:  EPILOGUE

# extproto_prompt_chose(n): the user picked item n of the choose prompt
FN extproto_prompt_chose
    PROLOGUE
    cmp qword ptr [rip + pr_id], 0
    je 9f
    cmp qword ptr [rip + pr_kind], 4    # resources group: an open-url prompt (extresproto.inc)
    jne 1f
    call res_url_chose
    jmp 9f
1:
    mov r12, rdi
    mov rbx, [rip + cur]
    mov rax, [rip + pr_ext]
    mov [rip + cur], rax
    mov rdi, [rip + pr_id]
    mov rsi, r12
    call reply_ok_u64
    mov [rip + cur], rbx
    call prompt_clear
9:  EPILOGUE

# extproto_prompt_text(ptr, len, PROMPT_ASK | PROMPT_TERM): the user accepted the field's text
FN extproto_prompt_text
    PROLOGUE
    cmp qword ptr [rip + pr_id], 0
    je 9f
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rbx, [rip + cur]
    mov rax, [rip + pr_ext]
    mov [rip + cur], rax
    cmp r14d, PROMPT_TERM
    je 5f
    # ask: "ok ID LEN" + the answer
    call out_begin
    lea rdi, [rip + .Lw_ok_sp]
    call out_cstr
    mov rdi, [rip + pr_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r13
    call out_u64
    mov edi, 10
    call out_byte
    mov rdi, r12
    mov rsi, r13
    call out_bytes
    call out_end
    jmp 8f
5:  # term: an empty line is a dismissal; otherwise the line runs in the terminal panel
    test r13, r13
    jnz 6f
    xor edi, edi                # (AI: rhun.run answers its call, extaiproto.inc)
    call prompt_term_answer
    jmp 8f
6:  mov rdi, r12
    mov rsi, r13
    call plain_text             # the user may have edited it: the same rule
    test eax, eax
    jz 61f
    lea rdi, [rip + pr_cmd]
    call sb_clear
    lea rdi, [rip + pr_cmd]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + pr_cmd]
    mov esi, 10
    call sb_push_byte
    cmp dword ptr [rip + g_term_open], 0
    jne 7f
    call term_show
7:  mov rdi, [rip + pr_cmd + SB_ptr]
    mov rsi, [rip + pr_cmd + SB_len]
    call term_panel_write       # typed into the shell, not pasted: Enter is Enter
    test eax, eax
    jz 61f
    mov edi, 1
    call prompt_term_answer
    jmp 8f
61: xor edi, edi
    call prompt_term_answer
8:  mov [rip + cur], rbx
    call prompt_clear
9:  EPILOGUE

# extproto_prompt_owner_gone(ext): the extension stopped: its prompt leaves the screen unanswered
FN extproto_prompt_owner_gone
    push rbx
    cmp qword ptr [rip + pr_id], 0
    je 9f
    cmp [rip + pr_ext], rdi
    jne 9f
    call prompt_clear
    call palette_is_open
    test eax, eax
    jz 9f
    call palette_close
9:  pop rbx
    ret

# ---------------- events ----------------

# send_settings(ext): "0 setting KEY VALUE" for each of its own settings
send_settings:
    PROLOGUE
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz 9f
    xor r12d, r12d
1:  cmp r12, [rbx + EXT_sdefs + VEC_len]
    jae 9f
    imul rsi, r12, SD_SIZE
    add rsi, [rbx + EXT_sdefs + VEC_ptr]
    inc r12
    mov rdi, rbx
    call extproto_send_setting
    jmp 1b
9:  EPILOGUE

# extproto_send_setting(ext, sd): "0 setting KEY VALUE"
FN extproto_send_setting
    PROLOGUE
    mov rbx, rsi
    mov r12, [rip + cur]
    mov [rip + cur], rdi
    call out_begin
    lea rdi, [rip + .Lev_setting]
    call out_cstr
    mov rdi, [rbx + SD_key]
    call out_cstr
    mov edi, ' '
    call out_byte
    mov rdi, [rip + cur]        # resources group: the window value (a workspace's, extconfig.s)
    mov rsi, rbx
    call extconfig_window
    mov rdi, rax
    call out_cstr
    mov edi, 10
    call out_byte
    call out_end
    mov [rip + cur], r12
    EPILOGUE

# FN extproto_doc(id) -> rax the open document with that id, or 0 (it may have been closed)
FN extproto_doc
    jmp doc_by_id

# FN extproto_matches(patterns, doc) -> eax 1 when the document's name matches the patterns
FN extproto_matches
    xor edx, edx                # the recipient is not known here
    jmp sub_matches

# FN extproto_host_request(ext, verb, doc, kind, ch) -> rax the id of "ID VERB DOC VERSION LINE COL
# KIND CHAR" sent to the extension (section 12), or 0: every event about the document goes first,
# and a document it does not know is not asked about
FN extproto_host_request
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov r12, rdx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8d
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    mov rdi, rbx
    call extproto_events
    test rax, rax
    js 8f
    mov rdi, rbx
    mov rsi, r12
    call extproto_doc_ready
    test eax, eax
    jz 8f
    mov [rip + cur], rbx
    cmp qword ptr [rbx + EXT_hreq], 2147483647
    jae 8f                      # never reuse a cancelled request's authority
    inc qword ptr [rbx + EXT_hreq]
    mov r13, [rbx + EXT_hreq]
    call out_begin
    mov rdi, r13
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rsp]
    call out_cstr
    mov edi, ' '
    call out_byte
    mov rdi, [r12 + DOC_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [r12 + DOC_version]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r12
    mov rsi, [r12 + DOC_cur]
    call doc_line_of
    mov r14, rax
    lea rdi, [rax + 1]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r12
    mov rsi, r14
    call doc_line_start
    mov rdi, [r12 + DOC_cur]
    sub rdi, rax
    inc rdi
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rsp + 8]
    call out_cstr
    mov edi, ' '
    call out_byte
    mov edi, [rsp + 16]
    lea rsi, [rsp + 20]
    call utf8_encode
    lea rdi, [rsp + 20]
    mov rsi, rax
    call out_bytes
    mov edi, 10
    call out_byte
    call out_end
    test rax, rax
    js 8f
    mov rdi, [rsp]              # resources group: the request's kind and time
    call strlen
    mov rcx, rax
    mov rdx, [rsp]
    mov rdi, rbx
    mov rsi, r13
    call extres_req_sent
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extproto_host_send(ext, doc, line, len) -> rax the id of "ID LINE" sent to the extension, or
# 0: every event about the document goes first, and a document it does not know is not asked about
FN extproto_host_send
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    mov rdi, rbx
    call extproto_events
    test rax, rax
    js 8f
    mov rdi, rbx
    mov rsi, r12
    call extproto_doc_ready
    test eax, eax
    jz 8f
    mov [rip + cur], rbx
    cmp qword ptr [rbx + EXT_hreq], 2147483647
    jae 8f                      # exhausted IDs are never reused
    inc qword ptr [rbx + EXT_hreq]
    mov r15, [rbx + EXT_hreq]
    call out_begin
    mov rdi, r15
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r13
    mov rsi, r14
    call out_bytes
    mov edi, 10
    call out_byte
    call out_end
    test rax, rax
    js 8f
    mov rdi, r13                # resources group: the request's kind (its first word) and time
    mov rsi, r14
    call next_word
    mov rcx, rdx
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r15
    call extres_req_sent
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extproto_host_send_body(ext, doc or 0, line, len, body, blen) -> rax the id of "ID LINE" and
# the body's bytes after it (language features: the line ends with blen), or 0. With a document,
# every event about it goes first and a document the extension does not know is not asked about
FN extproto_host_send_body
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    mov [rsp + 8], r9
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    mov rdi, rbx
    call extproto_events
    test rax, rax
    js 8f
    test r12, r12
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    call extproto_doc_ready
    test eax, eax
    jz 8f
1:  mov [rip + cur], rbx
    cmp qword ptr [rbx + EXT_hreq], 2147483647
    jae 8f
    inc qword ptr [rbx + EXT_hreq]
    mov r15, [rbx + EXT_hreq]
    call out_begin
    mov rdi, r15
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r13
    mov rsi, r14
    call out_bytes
    mov edi, 10
    call out_byte
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call out_bytes
    call out_end
    test rax, rax
    js 8f
    xor ecx, ecx                # resources group: the request's kind (its verb) and time
1:  cmp rcx, r14
    jae 2f
    cmp byte ptr [r13 + rcx], ' '
    je 2f
    inc rcx
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r15
    mov rdx, r13
    call extres_req_sent
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extproto_send_action(ext, data, len): "0 action LEN" and the bytes of a chosen code action
FN extproto_send_action
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_is_visible
    test eax, eax
    jz 9f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lev_action]
    call out_cstr
    mov rdi, r13
    call out_u64
    mov edi, 10
    call out_byte
    mov rdi, r12
    mov rsi, r13
    call out_bytes
    call out_end
9:  EPILOGUE

# FN extproto_send_cancel(ext, id): "0 cancel ID", a request rhun no longer needs the answer to
FN extproto_send_cancel
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call extres_req_cancel      # resources group: an answer after this is dropped
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lev_cancel]
    call out_cstr
    mov rdi, r12
    call out_u64
    mov edi, 10
    call out_byte
    call out_end
    EPILOGUE

# send_ready(ext): "0 ready PROJECT"
# hello_features(ext): EXT_features from every name after "hello 1" in the bounded line,
# and "0 features NAME..." with those rhun knows, when there are any
hello_features:
    PROLOGUE
    mov rbx, rdi
    mov [rip + cur], rdi
    mov rdi, rbx
    call ext_features_clear
    mov edi, 2
    call rest_from
    mov r12, rax
    lea r15, [rax + rdx]
1:  cmp r12, r15
    jae 4f
    cmp byte ptr [r12], ' '
    jne .Lhf_token
    inc r12
    jmp 1b
.Lhf_token:
    mov rax, r12
.Lhf_token_end:
    cmp rax, r15
    jae .Lhf_token_found
    cmp byte ptr [rax], ' '
    je .Lhf_token_found
    inc rax
    jmp .Lhf_token_end
.Lhf_token_found:
    mov r13, rax
    sub r13, r12
    mov rdi, r12
    mov rsi, r13
    call feature_index
    test eax, eax
    js 3f
    bts dword ptr [rbx + EXT_features], eax
    test edx, edx
    jz 3f
    mov dword ptr [rbx + EXT_feat_asks], 1
3:  add r12, r13
    jmp 1b
4:  mov rdi, rbx                # wsedit: which of its features it may have yet
    call ws_features_agreed
    mov rdi, rbx                # views group: features only with what they need (viewpic.s)
    call views_features_agreed
    # tasks only with terminals (a task's terminal is a TERM)
    FEAT_TEST rbx, FEAT_TASKS
    jz 40f
    FEAT_TEST rbx, FEAT_TERMINALS
    jnz 40f
    mov eax, FEAT_TASKS
    btr dword ptr [rbx + EXT_features], eax
40: xor r14d, r14d              # anything agreed?
    xor ecx, ecx
41: or r14, [rbx + EXT_features + rcx*8]
    inc ecx
    cmp ecx, FEAT_MAX / 64
    jb 41b
    test r14, r14
    jz 9f
    call pres_enable            # answers about older versions move through the edit tapes (edtape.s)
    call deco_visible_again     # and the visible event reaches the new extension too (deco.s)
    mov rdi, rbx
    call present_hello          # and the active document is asked what it provides (present.s)
    call out_begin
    lea rdi, [rip + .Lev_features]
    call out_cstr
    xor r14d, r14d              # the feature's index
    lea r13, [rip + feature_names]
5:  cmp byte ptr [r13], 0xff
    je 7f
    inc r13                     # past its asks byte
    bt dword ptr [rbx + EXT_features], r14d
    jnc 6f
    mov edi, ' '
    call out_byte
    mov rdi, r13
    call out_cstr
6:  mov rdi, r13
    call strlen
    lea r13, [r13 + rax + 1]
    inc r14d
    jmp 5b
7:  mov edi, 10
    call out_byte
    call out_end
9:  EPILOGUE

# feature_index(ptr, len) -> eax the feature's index (FEAT_*) or -1, edx its asks flag
feature_index:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
    lea rbx, [rip + feature_names]
1:  cmp byte ptr [rbx], 0xff
    je 8f
    movzx r15d, byte ptr [rbx]
    inc rbx
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call str_eq_cstr
    test eax, eax
    jnz 2f
    mov rdi, rbx
    call strlen
    lea rbx, [rbx + rax + 1]
    inc r14d
    jmp 1b
2:  mov eax, r14d
    mov edx, r15d
    EPILOGUE
8:  mov eax, -1
    xor edx, edx
    EPILOGUE

# FN ext_feature(ext, index) -> eax 1 when the extension agreed feature FEAT_* index (any
# register index; a negative one is no feature)
FN ext_feature
    xor eax, eax
    test esi, esi
    js 9f
    cmp esi, FEAT_MAX
    jae 9f
    bt dword ptr [rdi + EXT_features], esi
    setc al
9:  ret

# FN ext_features_clear(ext): nothing agreed (a new run)
FN ext_features_clear
    xor eax, eax
    xor ecx, ecx
1:  mov [rdi + EXT_features + rcx*8], rax
    inc ecx
    cmp ecx, FEAT_MAX / 64
    jb 1b
    mov dword ptr [rdi + EXT_feat_asks], 0
    ret

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

# extproto_send_run(ext, command index): "0 run NAME DOC", from the palette without a body
FN extproto_send_run
    xor edx, edx
    jmp extproto_send_invoke

# extproto_send_invoke(ext, command index, INV* or 0): "0 run NAME DOC", and with command-args
# " FROM LEN" LF and the body. DOC is the invocation's document while it is open, else the
# active one.
FN extproto_send_invoke
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    mov r14, rdx
    cmp qword ptr [rip + ext_pending_shutting_down], 0
    jne .Lpsr_closed
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne .Lpsr_closed
    cmp dword ptr [r12 + EXT_disabled], 0
    jne .Lpsr_closed
    call ext_cmd_index_owned
    test eax, eax
    jz .Lpsr_missing
    mov rdi, r12
    call extproto_events
    test rax, rax
    js 9f
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne .Lpsr_closed
    mov rdi, r12
    mov rsi, rbx
    call ext_cmd_index_owned
    test eax, eax
    jz .Lpsr_missing
    imul rax, rbx, CMD_SIZE
    add rax, [rip + g_ext_cmds + VEC_ptr]
    mov r13, [rax + CMD_name]
    test r13, r13
    jz .Lpsr_missing
    mov rdi, r12                # debugger: a debug-start may follow this command (debugext.s)
    call dbgx_note_command
    mov [rip + cur], r12
    call out_begin
    lea rdi, [rip + .Lev_run]
    call out_cstr
    mov rdi, r13
    call out_cstr
    mov edi, ' '
    call out_byte
    # the document: the invocation's while it is open (0 once it closed), else the active one
    test r14, r14
    jz 1f
    mov rdi, [r14 + INV_doc]
    test rdi, rdi
    jz 1f
    call doc_by_id
    xor edi, edi
    test rax, rax
    jz 2f
    mov rdi, [rax + DOC_id]
    jmp 2f
1:  call active_doc_id
    mov rdi, rax
2:  call out_u64
    FEAT_TEST r12, FEAT_COMMAND_ARGS
    jz 5f
    # command-args: " FROM LEN" and the body
    mov edi, ' '
    call out_byte
    xor edi, edi
    test r14, r14
    jz 3f
    mov edi, [r14 + INV_from]
3:  call invoke_from_name
    mov rdi, rax
    call out_cstr
    mov edi, ' '
    call out_byte
    xor edi, edi
    test r14, r14
    jz 4f
    mov rdi, [r14 + INV_len]
4:  call out_u64
    mov edi, 10
    call out_byte
    test r14, r14
    jz 6f
    mov rdi, [r14 + INV_body]
    mov rsi, [r14 + INV_len]
    test rsi, rsi
    jz 6f
    call out_bytes
    jmp 6f
5:  mov edi, 10
    call out_byte
6:  call out_end
9:  EPILOGUE
.Lpsr_closed:
    mov rax, -32
    EPILOGUE
.Lpsr_missing:
    mov rax, -2
    EPILOGUE

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
    jne 7f
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    mov rcx, [rax + DOC_diff]   # wsedit: a diff tab of wsdiff.s is no document for extensions
    test rcx, rcx
    jz 1f
    test dword ptr [rcx + DV_flags], DVF_OWN
    jnz 8f
1:  mov rax, [rax + DOC_id]
    ret
7:  cmp qword ptr [rax + TAB_kind], TAB_NOTEBOOK
    jne 8f
    mov rax, [rip + cur]        # notebooks (A3): the selected cell, for one that agreed notebooks
    test rax, rax
    jz 8f
    FEAT_TEST rax, FEAT_NOTEBOOKS
    jnz nb_active_cell_id
8:  xor eax, eax
    ret

.include "app/extprotoevents.inc"

# extproto_known(ext, id) -> XK* or 0: what the extension was told about the document
FN extproto_known
    jmp known_find

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

# sub_matches(patterns cstr or 0, doc, recipient ext or 0) -> 1 when the document's name matches
# ("*" matches all, untitled documents too); a virtual document only for a recipient that agreed uris
sub_matches:
    PROLOGUE
    test rdi, rdi
    jz 8f
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test dword ptr [r12 + DOC_flags], DF_CELL
    jnz 4f
    cmp qword ptr [r12 + DOC_uri], 0
    jne 2f
    cmp byte ptr [rbx], '*'
    jne 1f
    cmp byte ptr [rbx + 1], 0
    je 9f
1:
    mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz 8f
    mov rsi, rbx
    call ext_path_matches
    EPILOGUE
2:  # resources group: a virtual document, only for extensions that agreed uris, by its URI's
    # last segment (with the recipient unknown, its request about the document is refused later:
    # extproto_host_request asks only about documents the extension was told of)
    test r13, r13
    jz 21f
    mov rdi, r13
    mov esi, FEAT_URIS
    call ext_feature
    test eax, eax
    jz 8f
21: cmp byte ptr [rbx], '*'
    jne 3f
    cmp byte ptr [rbx + 1], 0
    je 9f
3:  mov rdi, r12
    call extproto_uri_segment
    mov rdi, rax
    mov rsi, rbx
    call ext_path_matches
    EPILOGUE
4:  # notebooks (A3): a cell, only for extensions that agreed notebooks, by its language's file name
    mov rdi, r13                # the recipient when the caller names it (resources group)
    test rdi, rdi
    jnz 41f
    mov rdi, [rip + cur]
41: mov esi, FEAT_NOTEBOOKS
    call ext_feature
    test eax, eax
    jz 8f
    cmp byte ptr [rbx], '*'
    jne 5f
    cmp byte ptr [rbx + 1], 0
    je 9f
5:  mov rdi, rbx
    mov rsi, r12
    call nb_cell_match
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# send_opened(doc): "0 opened DOC VERSION LANG PATH"
send_opened:
    PROLOGUE
    mov rbx, rdi
    call doc_sync_grammar
    test rax, rax
    js 9f
    mov rdi, rbx
    call doc_language
    mov r12, rax
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
    mov rax, r12
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
    mov rdi, [rbx + DOC_uri]    # resources group: a virtual document's URI
    test rdi, rdi
    jnz 3f
    lea rdi, [rip + .Ldash]
3:  call out_cstr
    mov edi, 10
    call out_byte
    call out_end
9:  EPILOGUE

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
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
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

# send_edits(doc, xk): "0 edits DOC VERSION LEN" + the records this extension has not had yet
# (from XK_eoff to the end of the frame's records); the offset moves to the end
send_edits:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
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
    mov r13, [r12 + XK_eoff]
    mov rdi, [rax + SB_len]
    sub rdi, r13
    call out_u64
    mov edi, 10
    call out_byte
    mov rax, [rbx + DOC_xedits]
    mov rdi, [rax + SB_ptr]
    add rdi, r13
    mov rsi, [rax + SB_len]
    sub rsi, r13
    call out_bytes
    call out_end
    test rax, rax
    js 1f
    mov rcx, [rbx + DOC_xedits]
    mov rcx, [rcx + SB_len]
    mov [r12 + XK_eoff], rcx
1:  EPILOGUE

# snapshot_taken(doc): a complete full-text reply was accepted in this nonyielding handler
snapshot_taken:
    push rbx
    mov rbx, rdi
    mov rdi, [rip + cur]
    mov rsi, [rbx + DOC_id]
    call known_find
    test rax, rax
    jz 9f
    mov rcx, [rbx + DOC_xedits]
    xor edx, edx
    test rcx, rcx
    jz 1f
    mov rdx, [rcx + SB_len]
1:  mov [rax + XK_eoff], rdx
    mov rcx, [rbx + DOC_version]
    mov [rax + XK_text_ver], rcx
    mov qword ptr [rax + XK_resync], 0
9:  pop rbx
    ret

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
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, [rbx + EXT_sub_hover]
    mov rsi, r13
    mov rdx, rbx
    call sub_matches
    test eax, eax
    jz 1b
    mov rdi, rbx                # language features: hover-query instead (hovercard.s)
    mov rsi, r13
    call hovercard_asks
    test eax, eax
    jnz 1b
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

# ---------------- feature selections (multi-cursor) ----------------

# sel_insert_all(doc) -> rax 0 after replying ok ID VERSION, else the error text: the body at
# every selection of the document, as typing would
sel_insert_all:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rip + body_ptr]
    mov rdx, [rip + body_len]
    call doc_selections_replace
    test eax, eax
    jz 1f
    mov dword ptr [rip + g_dirty], 1
    cmp rbx, [rip + g_doc]
    jne 2f
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
2:  mov rdi, [rip + cur_id]
    mov rsi, [rbx + DOC_version]
    call reply_ok_u64
    xor eax, eax
    EPILOGUE
1:  lea rax, [rip + .Le_sel_refused]
    cmp edx, 2
    jne 3f
    lea rax, [rip + .Le_sel_large]
3:  cmp edx, 3
    jne 4f
    lea rax, [rip + .Le_readonly]
4:  EPILOGUE

# ID select-many DOC N LEN + N lines "L1 C1 L2 C2" -> ok ID: the selections (anchor, cursor),
# the first the primary; overlapping ones merge
h_select_many:
    PROLOGUE 16
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_SELECTIONS
    jz .Lsm_unknown
    cmp qword ptr [rip + nfields], 5
    jb .Lsm_syntax
    mov edi, 2
    call arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lsm_syntax
    test rax, rax
    jz .Lsm_toobig
    cmp rax, DOC_SELECTIONS_MAX
    ja .Lsm_toobig
    mov r12, rax                # selections
    mov r13, [rip + body_ptr]   # the numbers go on from here
    mov r14, r13
    add r14, [rip + body_len]
    xor r15d, r15d
1:  cmp r15, r12
    jae 2f
    call sm_number              # anchor line, column
    mov [rsp], rax
    call sm_number
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, rax
    call sm_pos
    test rax, rax
    js .Lsm_badpos
    mov rcx, r15
    shl rcx, 4
    lea rdx, [rip + sel_pairs]
    mov [rdx + rcx + DMP_anchor], rax
    call sm_number              # cursor line, column
    mov [rsp], rax
    call sm_number
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, rax
    call sm_pos
    test rax, rax
    js .Lsm_badpos
    mov rcx, r15
    shl rcx, 4
    lea rdx, [rip + sel_pairs]
    mov [rdx + rcx + DMP_cur], rax
    inc r15
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, r12
    call sel_install
    test rax, rax
    jz .Lsm_badpos
    mov qword ptr [rbx + DOC_prefx], -1
    cmp rbx, [rip + g_doc]
    jne 3f
    call ed_touch
    jmp 4f
3:  mov rdi, rbx
    call snippet_selection_changed
4:  mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Lsm_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lsm_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE
.Lsm_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_sel_toobig]
    call reply_error
    EPILOGUE
.Lsm_badpos:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_badpos]
    call reply_error
    EPILOGUE

# ---------------- feature reveal (wsedit) ----------------

# ws_arg_doc(i, open) -> DOC* from field i, or 0 after replying: a DOC id, or for an extension that
# agreed uris a URI without spaces: a file: URI names the open document of that path, any other the
# open virtual document; with open 1 one that is not open opens without a tab (a diff's side)
ws_arg_doc:
    PROLOGUE
    mov ebx, edi
    mov r15d, esi
    call field_at
    mov r12, rax
    mov r13, rdx
    test r13, r13
    jz 7f
    movzx eax, byte ptr [r12]
    sub eax, '0'
    cmp eax, 9
    jbe 7f
    mov rdi, [rip + cur]
    mov esi, FEAT_URIS
    call ext_feature
    test eax, eax
    jz 7f
    mov rdi, r12
    mov rsi, r13
    call uri_scheme_len
    test rax, rax
    jz 7f
    mov rdi, r12
    mov rsi, r13
    call uri_file_path
    test rax, rax
    jz 2f
    mov rdi, rax                # a local file: its tab
    call app_find_tab
    test rax, rax
    js 8f
    mov rdi, rax
    call tab_at
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    EPILOGUE
2:  cmp r13, 5
    jb 3f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lres_file_colon]
    mov ecx, 5
    call str_starts
    test eax, eax
    jnz 8f                      # a file: URI that is no local path
3:  mov rdi, r12
    mov rsi, r13
    call ws_doc_by_uri
    test rax, rax
    jnz 9f
    test r15d, r15d
    jz 8f
    mov rdi, [rip + cur]
    mov rsi, r12
    mov rdx, r13
    call vdoc_open_hidden
    test rax, rax
    jns 9f
    cmp rax, -27
    jne 8f
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lres_e_vdocs]
    call reply_error
    xor eax, eax
    EPILOGUE
7:  mov edi, ebx                # a DOC id (or the syntax error)
    call arg_doc
9:  EPILOGUE
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nodoc]
    call reply_error
    xor eax, eax
    EPILOGUE

# ID reveal DOC LINE COL WHERE -> ok ID: the document's view scrolls so the position shows (WHERE
# top, center, nearest or center-if-outside); the cursor does not move, no tab is activated
h_reveal:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_REVEAL
    jz .Lrv_unknown
    cmp qword ptr [rip + nfields], 6
    jne .Lrv_syntax
    mov edi, 2
    xor esi, esi
    call ws_arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov esi, 3
    call arg_pos
    test rax, rax
    js 9f
    mov r12, rax
    mov edi, 5
    call field_at
    mov r14, rax
    mov r15, rdx
    xor r13d, r13d              # RV_* by its word
1:  cmp r13d, 4
    jae .Lrv_syntax
    lea rax, [rip + rv_words]
    mov rdx, [rax + r13*8]
    mov rdi, r14
    mov rsi, r15
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ws_reveal
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE
.Lrv_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lrv_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# ID show-locations LEN + a title line and a 12d locations body -> ok ID: the palette lists them as
# Find All References does; busy while a prompt or the palette is open
h_show_locations:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_REVEAL
    jz .Lrv_unknown
    cmp qword ptr [rip + nfields], 3
    jne .Lrv_syntax
    call prompt_busy
    test eax, eax
    jnz 9f
    mov r12, [rip + body_ptr]
    mov r13, [rip + body_len]
    xor ebx, ebx                # the title line
1:  cmp rbx, r13
    jae .Lrv_syntax
    cmp byte ptr [r12 + rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, [rip + cur]
    mov rsi, r12
    mov rdx, rbx
    lea rcx, [r12 + rbx + 1]
    mov r8, r13
    sub r8, rbx
    dec r8
    call langfeat_show_locations
    test eax, eax
    jz .Lrv_syntax
    mov rdi, [rip + cur_id]
    call reply_ok
9:  EPILOGUE

# ---------------- feature diff (wsedit) ----------------

# ID diff LEFT RIGHT FLAGS LEN + TITLE -> ok ID DOC: a read-only diff tab from document LEFT to
# document RIGHT (FLAGS show or background); the same pair and title again: the tab it has
h_diff:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_DIFF
    jz .Lrv_unknown
    cmp qword ptr [rip + nfields], 6
    jne .Lrv_syntax
    mov edi, 4                  # FLAGS first: a side may open a virtual document
    call field_at
    mov r14, rax
    mov r15, rdx
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + .Ldf_show]
    call str_eq_cstr
    mov r13d, eax
    test eax, eax
    jnz 1f
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + .Ldf_background]
    call str_eq_cstr
    test eax, eax
    jz .Lrv_syntax
1:  mov edi, 2
    mov esi, 1
    call ws_arg_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov edi, 3
    mov esi, 1
    call ws_arg_doc
    test rax, rax
    jz 91f
    mov r12, rax
    # the title: its first line, at most 200 bytes
    mov rsi, [rip + body_ptr]
    xor ecx, ecx
2:  cmp rcx, [rip + body_len]
    jae 3f
    cmp byte ptr [rsi + rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov rdi, rcx
    mov edx, 200
    call utf8_cut
    mov r8, rax
    mov rdi, [rip + cur]
    mov rsi, rbx
    mov rdx, r12
    mov rcx, [rip + body_ptr]
    mov r9d, r13d
    call ws_diff_open
    test rax, rax
    jz 4f
    mov rdi, [rip + cur_id]
    mov rsi, rax
    call reply_ok_u64
9:  EPILOGUE
4:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_diff_toobig]
    call reply_error
    mov rdi, rbx                # sides it opened without a tab go again
    call ws_diff_unused
    cmp r12, rbx
    je 9b
    mov rdi, r12
    call ws_diff_unused
    EPILOGUE
91: mov rdi, rbx
    call ws_diff_unused
    EPILOGUE

# ID diff-close DOC -> ok ID: one of the extension's diff tabs closes
h_diff_close:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_DIFF
    jz .Lrv_unknown
    cmp qword ptr [rip + nfields], 3
    jne .Lrv_syntax
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lrv_syntax
    mov rdi, [rip + cur]
    mov rsi, rax
    call ws_diff_close
    test eax, eax
    jz 8f
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
8:  mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_nodoc]
    call reply_error
    EPILOGUE

# sm_number() -> rax the next decimal number of the body between r13 and r14 (r13 moves past it),
# 0 when there is none (no line or column is 0)
sm_number:
    xor eax, eax
1:  cmp r13, r14
    jae 9f
    movzx ecx, byte ptr [r13]
    cmp ecx, ' '
    je 2f
    cmp ecx, 10
    jne 3f
2:  inc r13
    jmp 1b
3:  cmp r13, r14
    jae 9f
    movzx ecx, byte ptr [r13]
    sub ecx, '0'
    cmp ecx, 9
    ja 9f
    imul rax, rax, 10
    add rax, rcx
    mov rcx, 0xffffffffff
    cmp rax, rcx
    ja 8f
    inc r13
    jmp 3b
8:  xor eax, eax
9:  ret

# sm_pos(doc, line, column) -> rax byte position (lines and byte columns from 1, arg_pos's rules),
# -1 when it is outside the document or inside a character
sm_pos:
    PROLOGUE
    mov rbx, rdi
    test rsi, rsi
    jz 8f
    cmp rsi, [rbx + DOC_nlines]
    ja 8f
    test rdx, rdx
    jz 8f
    lea r12, [rsi - 1]
    lea r13, [rdx - 1]
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    sub rax, r14
    cmp r13, rax
    ja 8f
    add r14, r13
    cmp r13, rax
    je 9f
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    je 8f
9:  mov rax, r14
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# send_selections(doc): "0 selections DOC N LEN" + N lines "L1 C1 L2 C2", the primary first
send_selections:
    PROLOGUE 32
    mov rbx, rdi
    lea rdi, [rsp]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    mov rdi, rbx
    lea rsi, [rsp]
    call sel_body
    mov r12, rax
    call out_begin
    lea rdi, [rip + .Lev_selections]
    call out_cstr
    mov rdi, [rbx + DOC_id]
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, r12
    call out_u64
    mov edi, ' '
    call out_byte
    mov rdi, [rsp + SB_len]
    call out_u64
    mov edi, 10
    call out_byte
    mov rdi, [rsp + SB_ptr]
    mov rsi, [rsp + SB_len]
    call out_bytes
    lea rdi, [rsp]
    call sb_free
    call out_end
    EPILOGUE

# ---------------- end feature selections ----------------

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
    .quad .Lewp_watch_verb, h_watch_workspace, 0
    .quad .Lewp_unwatch_verb, h_unwatch_workspace, 0
    .quad .Lv_text, h_text, 0
    .quad .Lv_range, h_range, 0
    .quad .Lv_replace, h_replace, EXT_BODY_MAX
    .quad .Lv_snippet, h_snippet, SN_BYTES_MAX
    .quad .Lv_snippet_context, h_snippet_context, 0
    .quad .Lv_insert, h_insert, EXT_BODY_MAX
    .quad .Lv_select, h_select, 0
    .quad .Lv_select_many, h_select_many, EXT_BODY_MAX    # feature selections
    .quad .Lv_reveal, h_reveal, 0                         # feature reveal (wsedit)
    .quad .Lv_show_locations, h_show_locations, EXT_BODY_MAX
    .quad .Lv_diff, h_diff, EXT_BODY_MAX                  # feature diff (wsedit)
    .quad .Lv_diff_close, h_diff_close, 0
    .quad .Lv_toast, h_toast, EXT_BODY_MAX
    .quad .Lv_status, h_status, EXT_BODY_MAX
    .quad .Lv_open, h_open, 0
    .quad .Lv_cancel, h_cancel, 0
    .quad .Lv_diagnostics, h_diagnostics, EXT_BODY_MAX
    .quad .Lv_hover, h_hover, EXT_BODY_MAX
    .quad .Lv_register, h_register, 0
    .quad .Lv_unregister, h_unregister, 0
    .quad .Lv_option, h_option, 0
    .quad .Lv_choose, h_choose, EXT_BODY_MAX
    .quad .Lv_ask, h_ask, EXT_BODY_MAX
    .quad .Lv_term, h_term, EXT_BODY_MAX
    .quad .Lv_cmd, h_cmd, 0
    .quad .Lv_view, h_view, 0
    .quad .Lv_draw, h_draw, VIEW_BODY_MAX
    .quad .Lv_unview, h_unview, 0
    .quad .Lv_vpatch, h_vpatch, EXT_BODY_MAX     # views group: retained views
    .quad .Lv_vshow, h_vshow, 0
    .quad .Lv_vreveal, h_vreveal, EXT_BODY_MAX
    .quad .Lv_vtab, h_vtab, 0
    .quad .Lv_notify, h_notify, 65536           # notifications and progress (notify.s)
    .quad .Lv_notify_set, h_notify_set, 65536
    .quad .Lv_unnotify, h_unnotify, 0
    .quad .Lv_progress, h_progress, 65536
    .quad .Lv_progress_set, h_progress_set, 65536
    .quad .Lv_progress_end, h_progress_end, 0
    .quad .Lv_vimage, h_vimage, 8388608         # view-images (viewpic.s)
    .quad .Lv_unimage, h_unimage, 0
    .quad .Lv_quick, h_quick, 2097152           # quick input (quick.s)
    .quad .Lv_quick_set, h_quick_set, 2097152
    .quad .Lv_quick_close, h_quick_close, 0
    .quad .Lv_apply, h_apply, EXT_BODY_MAX
    .quad .Lv_save_apply, h_save_apply, EXT_BODY_MAX
    # language features (query.s)
    .quad .Lv_query_part, query_h_part, REPLY_BODY_MAX
    .quad .Lv_query_progress, query_h_progress, 4096
    .quad .Lv_provides, query_h_provides, 0
    .quad .Lv_file_diagnostics, filediag_h_set, EXT_BODY_MAX
    .quad .Lv_file_diagnostics_reset, filediag_h_reset, 0
    # contributions and commands
    .quad .Lv_set_context, h_set_context, 0
    .quad .Lv_run_command, h_run_command, INV_BODY_MAX
    .quad .Lv_status_item, h_status_item, 16384
    .quad .Lv_status_remove, h_status_remove, 0
    # source control (wider-parity C): gitdata.s
    .quad .Lv_git_repo, gitdata_h_repo, 0
    .quad .Lv_git_status, gitdata_h_status, 0
    .quad .Lv_git_blame, gitdata_h_blame, 0
    .quad .Lv_git_log, gitdata_h_log, 4096
    .quad .Lv_git_show, gitdata_h_show, 4096
    .quad .Lv_git_diff_open, gitdata_h_diff_open, 4096
    .quad .Lv_qd_refresh, scmext_h_qd_refresh, 4096
    .quad .Lv_scm_register, scmext_h_register, 8192
    .quad .Lv_scm_update, scmext_h_update, EXT_BODY_MAX
    .quad .Lv_scm_input, scmext_h_input, 0
    .quad .Lv_scm_input_set, scmext_h_input_set, 65536
    # resources group (extresproto.inc)
    .quad .Lres_v_busy, h_res_busy, 0
    .quad .Lres_v_secret_get, h_res_secret_get, 0
    .quad .Lres_v_secret_set, h_res_secret_set, 65536
    .quad .Lres_v_secret_delete, h_res_secret_delete, 0
    .quad .Lres_v_secret_keys, h_res_secret_keys, 0
    .quad .Lres_v_content_changed, h_res_content_changed, 0
    .quad .Lres_v_open_url, h_res_open_url, 65536
    .quad .Lres_v_external_uri, h_res_external_uri, 65536
    .quad .Lres_v_link, h_res_link, 0
    .quad .Lres_v_find_files, h_res_find_files, 65536
    .quad .Lres_v_search_text, h_res_search_text, 340000
    .quad .Lres_v_setting_get, h_res_setting_get, 0
    .quad .Lres_v_folder_of, h_res_folder_of, 0
    # testing (testproto.s): feature "tests"
    .quad .Lv_test_items, h_tests, EXT_BODY_MAX
    .quad .Lv_test_remove, h_tests, EXT_BODY_MAX
    .quad .Lv_test_update, h_tests, TS_RESULTS_BODY
    .quad .Lv_test_end, h_tests, 0
    .quad .Lv_test_coverage, h_tests, TS_COVER_BODY
    .quad .Lv_test_exec, h_tests, TS_EXEC_BODY
    # AI (wider-parity D, extaiproto.inc)
    .quad .Lv_agent_sessions, h_agent_sessions, 1048576
    .quad .Lv_agent_changed, h_agent_changed, 0
    .quad .Lv_propose, h_propose, EXT_BODY_MAX + 8192
    .quad .Lv_unpropose, h_unpropose, 0
    .quad .Lv_tools, h_tools, 0
    .quad .Lv_tool_call, h_tool_call, EXT_BODY_MAX
    .quad .Lv_agent_ask, h_agent_ask, 8192
    # debugger (debugext.s): feature "debug"
    .quad dbgx_v_debug_start, dbgx_h_debug_start, DBGX_BODY_MAX
    # notebooks (nbproto.inc)
    .quad .Lnb_v_state, h_nb_state, 0
    .quad .Lnb_v_output, h_nb_output, NB_OUTPUT_MAX
    .quad .Lnb_v_stream, h_nb_stream, NB_STREAM_MAX
    .quad .Lnb_v_kernel_label, h_nb_kernel_label, 4096
    .quad .Lnb_v_exec, h_nb_exec, 262144
    .quad .Lnb_v_exec_signal, h_nb_exec_signal, 0
    # tasks and terminals (termproto.s)
    .quad .Lv_terminal_open, h_terminals, 131072
    .quad .Lv_terminal_stop, h_terminals, 0
    .quad .Lv_terminal_restart, h_terminals, 0
    .quad .Lv_terminal_close, h_terminals, 0
    .quad .Lv_terminal_show, h_terminals, 0
    .quad .Lv_terminal_input, h_terminals, 65536
    .quad .Lv_terminal_screen, h_terminals, 0
    .quad .Lv_tasks_set, h_terminals, 1048576
    .quad .Lv_task_start, h_terminals, 0
    .quad .Lv_task_run, h_terminals, 131072
    # custom editors (ceproto.inc)
    .quad .Lce_v_read, h_ed_read, 0
    .quad .Lce_v_dirty, h_ed_dirty, 0
    # editor presentation (deco.s)
    .quad .Lpv_decoration_type, h_decoration_type, DTY_BODY_MAX
    .quad .Lpv_decorate, h_decorate, DECO_BODY_MAX
    .quad .Lpv_semantic_legend, h_semantic_legend, SEMT_LEGEND_MAX     # (semtok.s)
    .quad 0, 0, 0
.Lv_query_part: .asciz "query-part"
.Lv_query_progress: .asciz "query-progress"
.Lv_provides: .asciz "provides"
.Lv_file_diagnostics: .asciz "file-diagnostics"
.Lv_file_diagnostics_reset: .asciz "file-diagnostics-reset"
.Lv_test_items: .asciz "test-items"
.Lv_terminal_open: .asciz "terminal-open"
.Lv_terminal_stop: .asciz "terminal-stop"
.Lv_terminal_restart: .asciz "terminal-restart"
.Lv_terminal_close: .asciz "terminal-close"
.Lv_terminal_show: .asciz "terminal-show"
.Lv_terminal_input: .asciz "terminal-input"
.Lv_terminal_screen: .asciz "terminal-screen"
.Lv_tasks_set: .asciz "tasks-set"
.Lv_task_start: .asciz "task-start"
.Lv_task_run: .asciz "task-run"
.Lv_test_remove: .asciz "test-remove"
.Lv_test_update: .asciz "test-update"
.Lv_test_end: .asciz "test-end"
.Lv_test_coverage: .asciz "test-coverage"
.Lv_test_exec: .asciz "test-exec"
.Lpv_decoration_type: .asciz "decoration-type"
.Lpv_semantic_legend: .asciz "semantic-legend"
.Lpv_decorate: .asciz "decorate"
.Lv_set_context: .asciz "set-context"
.Lv_run_command: .asciz "run-command"
.Lv_status_item: .asciz "status-item"
.Lv_status_remove: .asciz "status-remove"
.Le_toobig_status: .asciz "toobig 8 items"
.Le_toobig_keys: .asciz "toobig 64 keys"
.Le_toobig_value: .asciz "toobig 256 bytes"
.Lv_git_repo: .asciz "git-repo"
.Lv_git_status: .asciz "git-status"
.Lv_git_blame: .asciz "git-blame"
.Lv_git_log: .asciz "git-log"
.Lv_git_show: .asciz "git-show"
.Lv_git_diff_open: .asciz "git-diff-open"
.Lv_qd_refresh: .asciz "quickdiff-refresh"
.Lv_scm_register: .asciz "scm-register"
.Lv_scm_update: .asciz "scm-update"
.Lv_scm_input: .asciz "scm-input"
.Lv_scm_input_set: .asciz "scm-input-set"
.Lv_register: .asciz "register"
.Lv_unregister: .asciz "unregister"
.Le_refused_unregister: .asciz "refused not a runtime command of this extension"
.Lv_option: .asciz "option"
.Lv_choose: .asciz "choose"
.Lv_ask: .asciz "ask"
.Lv_term: .asciz "term"
.Lv_cmd: .asciz "cmd"
.Lv_view: .asciz "view"
.Lv_draw: .asciz "draw"
.Lv_unview: .asciz "unview"
.Lv_vpatch: .asciz "vpatch"
.Lv_vshow: .asciz "vshow"
.Lvs_focus: .asciz "focus"
.Lv_vreveal: .asciz "vreveal"
.Lv_vtab: .asciz "vtab"
.Lv_notify: .asciz "notify"
.Lw_dash_pct: .asciz "-"
.Lv_notify_set: .asciz "notify-set"
.Lv_unnotify: .asciz "unnotify"
.Lv_progress: .asciz "progress"
.Lv_progress_set: .asciz "progress-set"
.Lv_progress_end: .asciz "progress-end"
.Lv_vimage: .asciz "vimage"
.Lv_unimage: .asciz "unimage"
.Le_toobig_images: .asciz "toobig 64 images or 128 MB"
.Le_noimage: .asciz "noview no such image"
.Le_toobig_notes: .asciz "toobig 16 notifications"
.Le_toobig_progress: .asciz "toobig 8 progress"
.Le_nonote: .asciz "noview no such notification"
.Le_noprogress: .asciz "noview no such progress"
.Le_refused_unview: .asciz "refused a declared view: the user hides it"
.Le_toobig_vtab: .asciz "toobig 8 views"
.Le_badpos_vreveal: .asciz "badpos no such node"
.Le_refused_vshow: .asciz "refused no such view"
.Lv_apply: .asciz "apply"
.Lv_snippet: .asciz "snippet"
.Lv_snippet_context: .asciz "snippet-context"
.Le_context_large: .asciz "toobig snippet context exceeds 4 MiB"
.Le_context_utf8: .asciz "refused snippet context is not UTF-8"
.Le_toobig_views: .asciz "toobig 8 views"
.Le_noview: .asciz "noview no such view"
.Le_syntax_line: .asciz "syntax line "
.Lo_tab: .asciz "tab_width"
.Lo_spaces: .asciz "insert_spaces"
.Lo_trim: .asciz "trim_trailing_whitespace"
.Lo_final: .asciz "final_newline"
.Lo_yes: .asciz "yes"
.Lo_no: .asciz "no"
.Lo_dash: .asciz "-"
.Le_busy: .asciz "busy a prompt is open"
.Le_toobig_quick: .asciz "toobig 10000 items, 2 MB, 8 buttons, 4 item buttons"
.Le_noquick: .asciz "noview no such quick input"
.Lv_quick: .asciz "quick"
.Lv_quick_set: .asciz "quick-set"
.Lv_quick_close: .asciz "quick-close"
.Le_cancelled: .asciz "cancelled"
.Le_refused_cmd: .asciz "refused not a command an extension may run"
.Le_refused_name: .asciz "refused the name is in use"
.Le_toobig_cmds: .asciz "toobig 64 commands"
.Le_toobig_items: .asciz "toobig 1000 items"
.Le_toobig_term: .asciz "toobig 4096 bytes"
.Le_needs_term: .asciz "needs terminal=yes"
.Le_needs_term_run: .asciz "needs terminal=run"
.Lrun_label: .asciz "Run in the terminal: Enter, or Esc"
.p2align 3
opt_names: .quad .Lo_tab, .Lo_spaces, .Lo_trim, .Lo_final
# the commands cmd may run (section 8a): name, what it needs (0, NEEDS_DOC_WRITE for the ones
# that change the document, NEEDS_TERMINAL for the terminal panel's); cut, copy and paste are
# not here: the clipboard is no extension's, and a paste can reach the terminal
.globl cmd_allow
cmd_allow:
    .quad .La_undo, NEEDS_DOC_WRITE, .La_redo, NEEDS_DOC_WRITE, .La_select_all, 0, .La_select_line, 0
    .quad .La_select_next, 0, .La_duplicate_line, NEEDS_DOC_WRITE, .La_delete_line, NEEDS_DOC_WRITE
    .quad .La_move_line_up, NEEDS_DOC_WRITE, .La_move_line_down, NEEDS_DOC_WRITE
    .quad .La_indent, NEEDS_DOC_WRITE, .La_outdent, NEEDS_DOC_WRITE, .La_toggle_comment, NEEDS_DOC_WRITE
    .quad .La_newline_below, NEEDS_DOC_WRITE, .La_newline_above, NEEDS_DOC_WRITE
    .quad .La_find, 0, .La_replace, 0, .La_find_next, 0, .La_find_prev, 0, .La_find_in_files, 0, .La_goto_line, 0
    .quad .La_quick_open, 0, .La_command_palette, 0, .La_next_tab, 0, .La_prev_tab, 0, .La_reveal_file, 0
    .quad .La_focus_explorer, 0, .La_toggle_sidebar, 0, .La_toggle_agents, 0
    .quad .La_toggle_terminal, NEEDS_TERMINAL, .La_new_terminal, NEEDS_TERMINAL, .La_clear_terminal, NEEDS_TERMINAL
    .quad .La_toggle_word_wrap, 0, .La_toggle_whitespace, 0, .La_toggle_line_numbers, 0
    .quad .La_zoom_in, 0, .La_zoom_out, 0, .La_zoom_reset, 0
    # tasks (with terminal = run): rhun's task commands, which run published tasks after the approval
    .quad .La_run_task, NEEDS_TERM_RUN, .La_run_build_task, NEEDS_TERM_RUN
    .quad .La_run_test_task, NEEDS_TERM_RUN, .La_rerun_last_task, NEEDS_TERM_RUN
    .quad .La_restart_task, NEEDS_TERM_RUN, .La_stop_task, NEEDS_TERM_RUN, .La_show_task, NEEDS_TERM_RUN
    .quad 0, 0
.La_undo: .asciz "undo"
.La_redo: .asciz "redo"
.La_select_all: .asciz "select_all"
.La_select_line: .asciz "select_line"
.La_select_next: .asciz "select_next"
.La_duplicate_line: .asciz "duplicate_line"
.La_delete_line: .asciz "delete_line"
.La_move_line_up: .asciz "move_line_up"
.La_move_line_down: .asciz "move_line_down"
.La_indent: .asciz "indent"
.La_outdent: .asciz "outdent"
.La_toggle_comment: .asciz "toggle_comment"
.La_newline_below: .asciz "newline_below"
.La_newline_above: .asciz "newline_above"
.La_find: .asciz "find"
.La_replace: .asciz "replace"
.La_find_next: .asciz "find_next"
.La_find_prev: .asciz "find_prev"
.La_find_in_files: .asciz "find_in_files"
.La_goto_line: .asciz "goto_line"
.La_quick_open: .asciz "quick_open"
.La_command_palette: .asciz "command_palette"
.La_next_tab: .asciz "next_tab"
.La_prev_tab: .asciz "prev_tab"
.La_reveal_file: .asciz "reveal_file"
.La_focus_explorer: .asciz "focus_explorer"
.La_toggle_sidebar: .asciz "toggle_sidebar"
.La_toggle_agents: .asciz "toggle_agents"
.La_toggle_terminal: .asciz "toggle_terminal"
.La_new_terminal: .asciz "new_terminal"
.La_clear_terminal: .asciz "clear_terminal"
.La_toggle_word_wrap: .asciz "toggle_word_wrap"
.La_toggle_whitespace: .asciz "toggle_whitespace"
.La_toggle_line_numbers: .asciz "toggle_line_numbers"
.La_zoom_in: .asciz "zoom_in"
.La_zoom_out: .asciz "zoom_out"
.La_zoom_reset: .asciz "zoom_reset"
.La_run_task: .asciz "run_task"
.La_run_build_task: .asciz "run_build_task"
.La_run_test_task: .asciz "run_test_task"
.La_rerun_last_task: .asciz "rerun_last_task"
.La_restart_task: .asciz "restart_task"
.La_stop_task: .asciz "stop_task"
.La_show_task: .asciz "show_task"
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
.Lev_features: .asciz "0 features"
.Lev_cancel: .asciz "0 cancel "
.Lev_action: .asciz "0 action "
.Lv_save_apply: .asciz "save-apply"
.Le_save_apply: .asciz "refused save edit is not valid for the active invocation"
.p2align 3
# the features rhun knows, in FEAT_* order: per feature its asks byte and its name; 0xff ends
.set FEATURE_NAMES, 1
feature_names:
    FEATURE_LIST
    .byte 0xff
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
.Lev_selections: .asciz "0 selections "     # feature selections
.Lv_select_many: .asciz "select-many"
.Lv_reveal: .asciz "reveal"                 # feature reveal (wsedit)
.Lv_show_locations: .asciz "show-locations"
.Lrv_top: .asciz "top"
.Lrv_center: .asciz "center"
.Lrv_nearest: .asciz "nearest"
.Lrv_center_outside: .asciz "center-if-outside"
.p2align 3
rv_words: .quad .Lrv_top, .Lrv_center, .Lrv_nearest, .Lrv_center_outside
.Lv_diff: .asciz "diff"                     # feature diff (wsedit)
.Lv_diff_close: .asciz "diff-close"
.Ldf_show: .asciz "show"
.Ldf_background: .asciz "background"
.Le_diff_toobig: .asciz "toobig 32 diff tabs"
.Le_sel_toobig: .asciz "toobig 512 selections at most"
.Le_sel_refused: .asciz "refused the text could not be inserted"
.Le_sel_large: .asciz "toobig the text at every selection exceeds 64 MiB"
.Lev_closed: .asciz "0 closed "
.Lev_active: .asciz "0 active "
.Lev_project: .asciz "0 project "
.Lev_edits: .asciz "0 edits "
.Lev_resync: .asciz "0 resync "
.Lev_hover: .asciz "0 hover "
.Lev_setting: .asciz "0 setting "
.Le_unknown: .asciz "unknown no such request"
.Le_syntax: .asciz "syntax cannot parse the line"
.Le_nodoc: .asciz "nodoc no such document"
.Le_badpos: .asciz "badpos position outside the document or inside a character"
.Le_stale: .asciz "stale "
.Le_needs_read: .asciz "needs documents=read"
.Le_needs_write: .asciz "needs documents=write"
.Le_nofile: .asciz "nofile no such file"
.Le_file_needs: .asciz "needs file=read"
.Le_readonly: .asciz "readonly the document cannot be edited"
.Le_toobig: .asciz "toobig more than 2000 diagnostics"
.Lr_no_hello: .asciz "the first line was not hello 1"
.Lr_protocol: .asciz "protocol version not supported (rhun speaks 1)"
.Lr_body: .asciz "a body over its cap"
.Lr_framing: .asciz "invalid body framing"
.Lr_syntax: .asciz "three unparsable lines in a row"

# ---------------- source control (wider-parity C): for verb handlers in other files ----------------
.text
# FN extproto_answer_syntax(): "error ID syntax ..." for the request being served (counts toward the
# three in a row that end a program)
FN extproto_answer_syntax
    mov rdi, [rip + cur_id]
    jmp reply_syntax

.include "app/extwatchproto.inc"
.include "app/extresproto.inc"    # resources group: idle, secrets, urls, uris, files, folders
.include "app/extaiproto.inc"
.include "app/nbproto.inc"
.include "app/ceproto.inc"
.section .rodata
.Lewp_watch_verb: .asciz "watch-workspace"
.Lewp_unwatch_verb: .asciz "unwatch-workspace"
.Lewp_feature: .asciz "workspace_watch"

