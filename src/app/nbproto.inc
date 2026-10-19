# Included in extproto.s: the notebooks feature's messages (docs/extensions/v1.1.md, "Feature:
# notebooks"). rhun asks nb-open and nb-save (answers up to 64 MB: a reply cap of their own), tells
# nb-run, nb-interrupt, nb-restart, nb-kernel and nb-closed, and handles nb-state, nb-output,
# nb-stream and nb-kernel-label. nbdoc.s keeps the notebooks.

.equ RCAP_MAX, 64               # requests with a reply cap of their own, all extensions

.bss
.p2align 3
rcap: .zero 24 * RCAP_MAX       # EXT*, request id, cap; EXT* 0 is a free slot
nbq: .zero SB_SIZE              # a request's line
nbb: .zero SB_SIZE              # its body
nbev: .zero SB_SIZE             # an event

.text

# ---------------- reply caps (wider-parity G: one per outstanding request) ----------------

# ext_reply_cap(ext, id) -> rax the most bytes the answer to request id may carry
FN ext_reply_cap
    lea rax, [rip + rcap]
    xor ecx, ecx
1:  cmp ecx, RCAP_MAX
    jae 8f
    cmp [rax], rdi
    jne 2f
    cmp [rax + 8], rsi
    jne 2f
    mov rax, [rax + 16]
    ret
2:  add rax, 24
    inc ecx
    jmp 1b
8:  mov eax, REPLY_BODY_MAX
    ret

# ext_reply_cap_set(ext, id, cap): the answer to request id may carry up to cap bytes (no free slot:
#   the usual cap stays)
FN ext_reply_cap_set
    lea rax, [rip + rcap]
    xor ecx, ecx
1:  cmp ecx, RCAP_MAX
    jae 9f
    cmp qword ptr [rax], 0
    je 2f
    add rax, 24
    inc ecx
    jmp 1b
2:  mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
9:  ret

# ext_reply_cap_drop(ext, id): request id was answered or withdrawn; id 0: all of the extension's
FN ext_reply_cap_drop
    lea rax, [rip + rcap]
    xor ecx, ecx
1:  cmp ecx, RCAP_MAX
    jae 9f
    cmp [rax], rdi
    jne 2f
    test rsi, rsi
    jz 3f
    cmp [rax + 8], rsi
    jne 2f
3:  mov qword ptr [rax], 0
2:  add rax, 24
    inc ecx
    jmp 1b
9:  ret

# ---------------- sending ----------------

# nb_send_bytes(ext, ptr, len): ext_send for a body that may pass the queue's 8 MB cap (nb-save
#   carries up to 64 MB): the queue takes it whole and drains as the program reads; a program that
#   stops reading is still ended by the not-reading clock
nb_send_bytes:
    cmp rdx, EXT_WQ_HARD / 2
    jb ext_send
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_is_visible
    test eax, eax
    jz 9f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    mov rcx, [rbx + EXT_wq_off]
    test rcx, rcx
    jz 1f
    mov rdi, [rbx + EXT_wq + SB_ptr]
    lea rsi, [rdi + rcx]
    mov rdx, [rbx + EXT_wq + SB_len]
    sub rdx, rcx
    call memmove
    mov rcx, [rbx + EXT_wq_off]
    sub [rbx + EXT_wq + SB_len], rcx
    mov qword ptr [rbx + EXT_wq_off], 0
1:  lea rdi, [rbx + EXT_wq]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, rbx
    call ext_flush
9:  EPILOGUE

# nb_request(nb, verb cstr) -> rax the id of "ID VERB NB LEN" + nbb sent to the notebook's
#   extension, or 0 (nbb is emptied either way)
nb_request:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + NB_ext]
    xor r14d, r14d
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 9f
    cmp qword ptr [r13 + EXT_hreq], 2147483647
    jae 9f
    inc qword ptr [r13 + EXT_hreq]
    mov r14, [r13 + EXT_hreq]
    lea rdi, [rip + nbq]
    call sb_clear
    lea rdi, [rip + nbq]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + nbq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbq]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + nbq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbq]
    mov rsi, [rbx + NB_id]
    call sb_push_u64
    lea rdi, [rip + nbq]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbq]
    mov rsi, [rip + nbb + SB_len]
    call sb_push_u64
    lea rdi, [rip + nbq]
    mov esi, 10
    call sb_push_byte
    mov rdi, r13
    mov rsi, [rip + nbq + SB_ptr]
    mov rdx, [rip + nbq + SB_len]
    call ext_send
    mov rdi, r13
    mov rsi, [rip + nbb + SB_ptr]
    mov rdx, [rip + nbb + SB_len]
    call nb_send_bytes
    mov rdi, r13
    mov rsi, r14
    mov edx, NB_BODY_MAX
    call ext_reply_cap_set
    mov rdi, r13                # counted with the other requests rhun waits on (query.s)
    mov rsi, r14
    mov edx, PK_NB_SAVE
    cmp byte ptr [r12 + 3], 'o' # "nb-open"
    jne 1f
    mov edx, PK_NB_OPEN
1:  mov ecx, QO_NOTEBOOK
    call query_track
9:  lea rdi, [rip + nbb]
    call sb_free
    mov rax, r14
    EPILOGUE

# nb_send_open(nb) -> rax the id of nb-open, or 0 with rdx why: the file's path and bytes
FN nb_send_open
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + NB_host]
    mov rdi, [r12 + DOC_path]
    mov esi, NB_BODY_MAX
    call file_read_limited
    mov r13, rax
    mov r14, rdx
    test rax, rax
    jnz 1f
    cmp rdx, -2                 # no such file yet: an empty notebook, written on save
    jne 8f
    xor r14d, r14d
1:  lea rdi, [rip + nbb]
    call sb_clear
    mov rdi, [r12 + DOC_path]
    call strlen
    mov r15, rax
    lea rdi, [rip + nbb]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + nbb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbb]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + nbb]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + nbb]
    mov rsi, [r12 + DOC_path]
    mov rdx, r15
    call sb_push
    lea rdi, [rip + nbb]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    mov rdi, r13
    call mem_free
    mov rdi, rbx
    lea rsi, [rip + .Lnb_v_open]
    call nb_request
    lea rdx, [rip + .Lnb_r_send]
    EPILOGUE
8:  xor eax, eax
    lea rdx, [rip + .Lnb_r_read]
    EPILOGUE

# nb_send_save(nb) -> rax the id of nb-save, or 0 with rdx why: the path, then the notebook body
FN nb_send_save
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + NB_host]
    lea rdi, [rip + nbb]
    call sb_clear
    mov rdi, [r12 + DOC_path]
    call strlen
    mov r15, rax
    lea rdi, [rip + nbb]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + nbb]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + nbb]
    mov rsi, [r12 + DOC_path]
    mov rdx, r15
    call sb_push
    mov rdi, rbx
    lea rsi, [rip + nbb]
    call nb_write
    test eax, eax
    jz 8f
    mov rdi, rbx
    lea rsi, [rip + .Lnb_v_save]
    call nb_request
    lea rdx, [rip + .Lnb_r_send]
    EPILOGUE
8:  lea rdi, [rip + nbb]
    call sb_free
    xor eax, eax
    lea rdx, [rip + .Lnb_r_large]
    EPILOGUE

# nb_event_begin(nb, verb cstr) -> eax 1 with "0 VERB NB" in nbev when its extension runs and
#   agreed notebooks, else 0
nb_event_begin:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + NB_ext]
    cmp dword ptr [rax + EXT_status], ES_RUNNING
    jne 8f
    FEAT_TEST rax, FEAT_NOTEBOOKS
    jz 8f
    lea rdi, [rip + nbev]
    call sb_clear
    lea rdi, [rip + nbev]
    lea rsi, [rip + .Lnb_ev0]
    call sb_push_cstr
    lea rdi, [rip + nbev]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + nbev]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbev]
    mov rsi, [rbx + NB_id]
    call sb_push_u64
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_event_end(nb): nbev, a line feed, to the notebook's extension
nb_event_end:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + nbev]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + NB_ext]
    mov rsi, [rip + nbev + SB_ptr]
    mov rdx, [rip + nbev + SB_len]
    call ext_send
    pop rbx
    ret

# nb_send_simple(nb, verb cstr) -> eax 1 when "0 VERB NB" went out
FN nb_send_simple
    push rbx
    mov rbx, rdi
    call nb_event_begin
    test eax, eax
    jz 9f
    mov rdi, rbx
    call nb_event_end
    mov eax, 1
9:  pop rbx
    ret

# nb_send_closed(nb): "0 nb-closed NB"
FN nb_send_closed
    lea rsi, [rip + .Lnb_v_closed]
    jmp nb_send_simple

# nb_send_run(nb, cl) -> eax 1 when "0 nb-run NB CELL RUN LANG LEN" + the cell's source went out
#   for its run CL_run
FN nb_send_run
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    lea rsi, [rip + .Lnb_v_run]
    call nb_event_begin
    test eax, eax
    jz 9f
    lea rdi, [rip + nbev]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbev]
    mov rsi, [r12 + CL_id]
    call sb_push_u64
    lea rdi, [rip + nbev]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbev]
    mov rsi, [r12 + CL_run]
    call sb_push_u64
    lea rdi, [rip + nbev]
    mov esi, ' '
    call sb_push_byte
    mov rsi, [r12 + CL_lang]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Ldash]
1:  lea rdi, [rip + nbev]
    call sb_push_cstr
    lea rdi, [rip + nbev]
    mov esi, ' '
    call sb_push_byte
    mov rdi, [r12 + CL_doc]
    call doc_len
    mov r13, rax
    lea rdi, [rip + nbev]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + nbev]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + nbev]
    mov rsi, r13
    call sb_reserve
    mov rcx, rax
    mov rdi, [r12 + CL_doc]
    xor esi, esi
    mov rdx, r13
    call doc_copy
    add [rip + nbev + SB_len], r13
    mov rdi, [rbx + NB_ext]
    mov rsi, [rip + nbev + SB_ptr]
    mov rdx, [rip + nbev + SB_len]
    call ext_send
    mov eax, 1
9:  EPILOGUE

# ---------------- requests from the extension ----------------

# nb_arg(need fields) -> rax NB* and rdx CL* named by fields 2 (NB) and 3 (CELL), with field 4 the
#   cell's current run; rax 0 when the reply went out (unknown, syntax, stale)
nb_arg:
    PROLOGUE
    mov r12, rdi
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_NOTEBOOKS
    jz .Lna_unknown
    cmp [rip + nfields], r12
    jne .Lna_syntax
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lna_syntax
    mov rdi, [rip + cur]
    mov rsi, rax
    call nb_by_id
    test rax, rax
    jz .Lna_stale
    mov rbx, rax
    mov edi, 3
    call field_u64
    test edx, edx
    jz .Lna_syntax
    mov rdi, rbx
    mov rsi, rax
    call nb_cell_by_id
    test rax, rax
    jz .Lna_stale
    mov r13, rax
    mov edi, 4
    call field_u64
    test edx, edx
    jz .Lna_syntax
    test rax, rax
    jz .Lna_stale
    cmp rax, [r13 + CL_run]
    jne .Lna_stale
    mov rax, rbx
    mov rdx, r13
    EPILOGUE
.Lna_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    xor eax, eax
    EPILOGUE
.Lna_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    xor eax, eax
    EPILOGUE
.Lna_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lnb_e_stale]
    call reply_error
    xor eax, eax
    EPILOGUE

# ID nb-state NB CELL RUN STATE COUNT -> ok ID: the run's state and execution count
h_nb_state:
    PROLOGUE
    mov edi, 7
    call nb_arg
    test rax, rax
    jz 9f
    mov rbx, rax
    mov r12, rdx
    xor r13d, r13d
1:  lea rax, [rip + nb_run_names]
    mov rsi, [rax + r13*8]
    test rsi, rsi
    jz .Lns_syntax
    mov edi, 5
    call field_is
    inc r13d
    test eax, eax
    jz 1b
    mov edi, 6
    lea rsi, [rip + .Ldash]
    call field_is
    test eax, eax
    jnz 2f
    mov edi, 6
    call field_u64
    test edx, edx
    jz .Lns_syntax
    cmp rax, [r12 + CL_count]
    je 2f
    mov [r12 + CL_count], rax
    mov dword ptr [rbx + NB_dirty], 1
2:  mov [r12 + CL_state], r13d
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lns_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# ID nb-output NB CELL RUN OP TARGET LEN + output body -> ok ID: append, replace (TARGET an index
#   or an OUTID), clear, clear-wait
h_nb_output:
    PROLOGUE 16
    mov edi, 8
    call nb_arg
    test rax, rax
    jz 9f
    mov rbx, rax
    mov r12, rdx
    mov edi, 5
    lea rsi, [rip + .Lnb_op_clear]
    call field_is
    test eax, eax
    jnz .Lno_clear
    mov edi, 5
    lea rsi, [rip + .Lnb_op_wait]
    call field_is
    test eax, eax
    jnz .Lno_wait
    # append or replace: the body is one output
    mov rdi, [rip + body_ptr]
    mov rsi, [rip + body_len]
    call nb_rd_begin
    call nb_rd_output
    test rax, rax
    jz .Lno_syntax
    mov r13, rax
    call nb_rd_left
    test rax, rax
    jnz .Lno_bad
    mov edi, 5
    lea rsi, [rip + .Lnb_op_append]
    call field_is
    test eax, eax
    jnz .Lno_append
    mov edi, 5
    lea rsi, [rip + .Lnb_op_replace]
    call field_is
    test eax, eax
    jz .Lno_bad
    # replace: an index into the cell's outputs, or an OUTID anywhere in the notebook
    mov edi, 6
    call field_u64
    test edx, edx
    jz 3f
    cmp rax, [r12 + CL_outs + VEC_len]
    jae .Lno_stale_out
    mov r14, r12
    mov r15, rax
    jmp 5f
3:  mov edi, 6
    call field_at
    mov rdi, rbx
    mov rsi, rax
    call nb_find_outid
    test rax, rax
    jz .Lno_stale_out
    mov r14, rax
    mov r15, rdx
5:  # the old one's bytes give way to the new one's
    mov rax, [r14 + CL_outs + VEC_ptr]
    mov rdi, [rax + r15*8]
    mov rax, [rbx + NB_outbytes]
    sub rax, [rdi + OU_bytes]
    add rax, [r13 + OU_bytes]
    cmp rax, NB_OUTALL_MAX
    ja .Lno_toobig
    mov [rbx + NB_outbytes], rax
    call ou_free
    mov rax, [r14 + CL_outs + VEC_ptr]
    mov [rax + r15*8], r13
    inc qword ptr [r14 + CL_outrev]
    jmp .Lno_done
.Lno_append:
    cmp dword ptr [r12 + CL_clearwait], 0
    je 6f
    mov rdi, rbx
    mov rsi, r12
    call nb_clear_outputs
6:  cmp qword ptr [r12 + CL_outs + VEC_len], NB_OUTS_MAX
    jae .Lno_toobig
    mov rax, [rbx + NB_outbytes]
    add rax, [r13 + OU_bytes]
    cmp rax, NB_OUTALL_MAX
    ja .Lno_toobig
    mov [rbx + NB_outbytes], rax
    lea rdi, [r12 + CL_outs]
    mov esi, 8
    call vec_push
    mov [rax], r13
    inc qword ptr [r12 + CL_outrev]
    jmp .Lno_done
.Lno_clear:
    mov rdi, rbx
    mov rsi, r12
    call nb_clear_outputs
    jmp .Lno_done_ok
.Lno_wait:
    mov dword ptr [r12 + CL_clearwait], 1
    jmp .Lno_done_ok
.Lno_done:
    mov dword ptr [rbx + NB_dirty], 1
.Lno_done_ok:
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lno_toobig:
    mov rdi, r13
    call ou_free
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lnb_e_toobig]
    call reply_error
    EPILOGUE
.Lno_stale_out:
    mov rdi, r13
    call ou_free
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lnb_e_nooutput]
    call reply_error
    EPILOGUE
.Lno_bad:
    mov rdi, r13
    call ou_free
.Lno_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# nb_find_outid(nb, ptr, len) -> rax CL* and rdx the index of its output whose OUTID is that, or 0
nb_find_outid:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + NB_cells + VEC_len]
    jae 8f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r15, [rax + r14*8]
    inc r14
    xor ecx, ecx
2:  cmp rcx, [r15 + CL_outs + VEC_len]
    jae 1b
    mov rax, [r15 + CL_outs + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    mov rdx, [rax + OU_id]
    test rdx, rdx
    jz 2b
    push rcx
    push rcx
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    pop rcx
    pop rcx
    test eax, eax
    jz 2b
    mov rax, r15
    lea rdx, [rcx - 1]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ID nb-stream NB CELL RUN NAME LEN + bytes -> ok ID: appended to the cell's last output when it is
#   that stream, else a stream output of its own; a carriage return starts its line again
h_nb_stream:
    PROLOGUE 16
    mov edi, 7
    call nb_arg
    test rax, rax
    jz 9f
    mov rbx, rax
    mov r12, rdx
    mov r13d, OUK_STDOUT
    mov edi, 5
    lea rsi, [rip + .Lnb_stdout]
    call field_is
    test eax, eax
    jnz 1f
    mov r13d, OUK_STDERR
    mov edi, 5
    lea rsi, [rip + .Lnb_stderr]
    call field_is
    test eax, eax
    jz .Lnst_syntax
1:  cmp dword ptr [r12 + CL_clearwait], 0
    je 2f
    mov rdi, rbx
    mov rsi, r12
    call nb_clear_outputs
2:  mov rax, [rbx + NB_outbytes]
    add rax, [rip + body_len]
    cmp rax, NB_OUTALL_MAX
    ja .Lnst_toobig
    # the last output, when it is this stream
    mov rax, [r12 + CL_outs + VEC_len]
    test rax, rax
    jz 3f
    mov rcx, [r12 + CL_outs + VEC_ptr]
    mov r14, [rcx + rax*8 - 8]
    cmp [r14 + OU_kind], r13d
    jne 3f
    cmp qword ptr [r14 + OU_id], 0
    jne 3f
    cmp qword ptr [r14 + OU_items + VEC_len], 1
    jne 3f
    mov rax, [r14 + OU_items + VEC_ptr]
    cmp dword ptr [rax + NI_type], NIT_ANSI
    jne 3f
    mov rcx, [rax + NI_data + SB_len]
    add rcx, [rip + body_len]
    cmp rcx, NB_ITEM_MAX
    ja .Lnst_toobig
    jmp 4f
3:  # a stream output of its own
    cmp qword ptr [r12 + CL_outs + VEC_len], NB_OUTS_MAX
    jae .Lnst_toobig
    mov edi, OU_SIZE
    call mem_alloc
    mov r14, rax
    mov [r14 + OU_kind], r13d
    lea rdi, [r14 + OU_items]
    mov esi, NI_SIZE
    call vec_push
    mov dword ptr [rax + NI_type], NIT_ANSI
    lea rdi, [r12 + CL_outs]
    mov esi, 8
    call vec_push
    mov [rax], r14
4:  mov rax, [r14 + OU_items + VEC_ptr]
    lea r15, [rax + NI_data]
    mov rax, [r15 + SB_len]
    sub [rbx + NB_outbytes], rax
    sub [r14 + OU_bytes], rax
    # its lines: the line feeds it had, and those the bytes add (a carriage return never takes
    # a line feed away), then one more when it does not end in one
    mov rax, [r14 + OU_lines]
    mov [rsp], rax
    mov rcx, [r15 + SB_len]
    test rcx, rcx
    jz 41f
    mov rdx, [r15 + SB_ptr]
    cmp byte ptr [rdx + rcx - 1], 10
    je 41f
    dec qword ptr [rsp]
41: mov rdi, r15
    mov rsi, [rip + body_ptr]
    mov rdx, [rip + body_len]
    call nb_stream_append
    add [rsp], rax
    mov rax, [r15 + SB_len]
    add [rbx + NB_outbytes], rax
    add [r14 + OU_bytes], rax
    mov rcx, [rsp]
    test rax, rax
    jz 42f
    mov rdx, [r15 + SB_ptr]
    cmp byte ptr [rdx + rax - 1], 10
    je 42f
    inc rcx
42: mov [r14 + OU_lines], rcx
    mov qword ptr [r14 + OU_show], 0
    inc qword ptr [r12 + CL_outrev]
    mov dword ptr [rbx + NB_dirty], 1
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lnst_toobig:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lnb_e_toobig]
    call reply_error
    EPILOGUE
.Lnst_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
9:  EPILOGUE

# nb_stream_append(sb, ptr, len) -> rax the line feeds appended: the bytes after the stream's text;
#   CR LF is a line feed, a carriage return alone takes the text back to its line's start (a
#   progress bar draws over itself)
FN nb_stream_append
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    xor r15d, r15d
1:  cmp r12, r13
    jae 9f
    # a run without carriage returns goes in whole
    mov r14, r12
2:  cmp r14, r13
    jae 3f
    movzx eax, byte ptr [r14]
    cmp eax, 13
    je 3f
    cmp eax, 10
    jne 21f
    inc r15
21: inc r14
    jmp 2b
3:  mov rdx, r14
    sub rdx, r12
    jz 4f
    mov rdi, rbx
    mov rsi, r12
    call sb_push
4:  mov r12, r14
    cmp r12, r13
    jae 9f
    inc r12                     # the CR
    cmp r12, r13
    jae 5f
    cmp byte ptr [r12], 10
    je 1b                       # CR LF: the LF follows
5:  # back to the line's start
    mov rcx, [rbx + SB_len]
51: test rcx, rcx
    jz 52f
    mov rdx, [rbx + SB_ptr]
    cmp byte ptr [rdx + rcx - 1], 10
    je 52f
    dec rcx
    jmp 51b
52: mov [rbx + SB_len], rcx
    jmp 1b
9:  mov rax, r15
    EPILOGUE

# ID nb-kernel-label NB STATE LEN + label -> ok ID: the kernel button's text and state
h_nb_kernel_label:
    PROLOGUE
    mov rax, [rip + cur]
    FEAT_TEST rax, FEAT_NOTEBOOKS
    jz .Lnk_unknown
    cmp qword ptr [rip + nfields], 5
    jne .Lnk_syntax
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lnk_syntax
    mov rdi, [rip + cur]
    mov rsi, rax
    call nb_by_id
    test rax, rax
    jz .Lnk_stale
    mov rbx, rax
    xor r13d, r13d
1:  lea rax, [rip + nb_kernel_names]
    mov rsi, [rax + r13*8]
    test rsi, rsi
    jz .Lnk_syntax
    mov edi, 3
    call field_is
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  # names in NBK_* order: none idle busy starting dead
    mov [rbx + NB_kstate], r13d
    lea rdi, [rbx + NB_kernel]
    call sb_clear
    mov rdi, [rip + body_len]
    mov rsi, [rip + body_ptr]
    mov edx, NB_LABEL_MAX
    call utf8_cut
    mov rdx, rax
    lea rdi, [rbx + NB_kernel]
    mov rsi, [rip + body_ptr]
    call nb_push_line
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lnk_unknown:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lnk_stale:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lnb_e_stale]
    call reply_error
    EPILOGUE
.Lnk_syntax:
    mov rdi, [rip + cur_id]
    call reply_syntax
    EPILOGUE

# nb_push_line(sb, ptr, len): the bytes, control characters as spaces (a label is one line)
nb_push_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
1:  cmp r12, r13
    jae 9f
    movzx esi, byte ptr [r12]
    inc r12
    cmp esi, 32
    jae 2f
    mov esi, ' '
2:  mov rdi, rbx
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
nb_run_names: .quad .Lnb_s_queued, .Lnb_s_running, .Lnb_s_done, .Lnb_s_failed, .Lnb_s_cancelled, 0
nb_kernel_names: .quad .Lnb_k_none, .Lnb_k_idle, .Lnb_k_busy, .Lnb_k_starting, .Lnb_k_dead, 0
.Lnb_s_queued: .asciz "queued"
.Lnb_s_running: .asciz "running"
.Lnb_s_done: .asciz "done"
.Lnb_s_failed: .asciz "failed"
.Lnb_s_cancelled: .asciz "cancelled"
.Lnb_k_none: .asciz "none"
.Lnb_k_idle: .asciz "idle"
.Lnb_k_busy: .asciz "busy"
.Lnb_k_starting: .asciz "starting"
.Lnb_k_dead: .asciz "dead"
.Lnb_op_append: .asciz "append"
.Lnb_op_replace: .asciz "replace"
.Lnb_op_clear: .asciz "clear"
.Lnb_op_wait: .asciz "clear-wait"
.Lnb_stdout: .asciz "stdout"
.Lnb_stderr: .asciz "stderr"
.Lnb_ev0: .asciz "0 "
.Lnb_v_open: .asciz "nb-open"
.Lnb_v_save: .asciz "nb-save"
.Lnb_v_run: .asciz "nb-run"
.Lnb_v_closed: .asciz "nb-closed"
.Lnb_v_state: .asciz "nb-state"
.Lnb_v_output: .asciz "nb-output"
.Lnb_v_stream: .asciz "nb-stream"
.Lnb_v_kernel_label: .asciz "nb-kernel-label"
.Lnb_e_stale: .asciz "stale the run was superseded"
.Lnb_e_toobig: .asciz "toobig outputs over their cap"
.Lnb_e_nooutput: .asciz "badpos no such output"
.Lnb_r_send: .asciz "The notebook could not be sent to its extension"
.Lnb_r_read: .asciz "The notebook file cannot be read"
.Lnb_r_large: .asciz "The notebook is too big to save (64 MB)"
.text
