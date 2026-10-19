# notebooks (docs/extensions/v1.1.md, "Feature: notebooks"): the model. A notebook is a tab of its
# own (TAB_NOTEBOOK) whose document has the file's path and no text; its cells are documents of
# their own (DF_CELL) in no tab, so every editor command works in a cell. The extension whose
# [provides] notebook names the file reads it into cells (nb-open) and writes them back (nb-save):
# rhun never parses a notebook format. nbview.s draws and edits notebooks, nbout.s draws outputs,
# nbproto.inc (in extproto.s) speaks the protocol.
#
# A notebook body, both ways:  N META_LEN LF <META>, then per cell
#   KIND LANG COUNT SOURCE_LEN META_LEN NOUT LF <SOURCE><META>, then its NOUT output bodies:
#   KIND OUTID KEEP_LEN NITEM LF <KEEP>, then NITEM items: TYPE W H LEN LF <LEN bytes>
.include "rhun.inc"

.bss
.p2align 3
.globl g_nbs, g_nb_cell_seq, g_nb_run_seq, g_nb_open_text
g_nbs: .zero VEC_SIZE           # NB* of the open notebooks
nb_seq: .quad 0                 # the last notebook id handed out
g_nb_cell_seq: .quad 0          # the last cell id
g_nb_run_seq: .quad 0           # the last run id
g_nb_open_text: .long 0         # app_open_file opens the next file as text, whatever provides it
.p2align 3
rd_cur: .quad 0                 # the body being read: where, and its end
rd_end: .quad 0
rd_f: .zero 16 * 8              # the fields of its last line: ptr, len
rd_n: .quad 0
newcells: .zero VEC_SIZE        # nb-open's cells while its answer is read
nbx_ext: .quad 0                # nb_ext_doc_at's place: the extension, the index, notebook and cell
nbx_i: .quad 0
nbx_nb: .quad 0
nbx_c: .quad 0
newmeta: .zero SB_SIZE
tmp: .zero SB_SIZE
langbuf: .zero 136

.text

# ---------------- finding notebooks ----------------

# nb_provider(path) -> EXT* whose [provides] notebook names the file, or 0
FN nb_provider
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 8f
    imul r13, rbx, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc rbx
    mov rdi, r13
    mov esi, EXT_pv_notebook
    call ext_pv
    test rax, rax
    jz 1b
    cmp dword ptr [r13 + EXT_disabled], 0
    jne 1b
    mov eax, [r13 + EXT_status]
    cmp eax, ES_FAILED
    je 1b
    cmp eax, ES_DISABLED
    je 1b
    cmp eax, ES_REMOVED
    je 1b
    mov rdi, r13
    mov esi, EXT_pv_notebook
    call ext_pv
    mov rsi, rax
    mov rdi, r12
    call ext_path_matches
    test eax, eax
    jz 1b
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_of_tab(i) -> NB* of tab i when it is a notebook, or 0
FN nb_of_tab
    test rdi, rdi
    js 8f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_NOTEBOOK
    jne 8f
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 8f
    mov rax, [rax + DOC_nb]
    ret
8:  xor eax, eax
    ret

# nb_active() -> NB* of the active tab when it is a notebook, or 0
FN nb_active
    mov rdi, [rip + g_tab_cur]
    jmp nb_of_tab

# nb_by_id(ext, id) -> NB* that the extension reads and writes, or 0
FN nb_by_id
    xor ecx, ecx
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 8f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp [rax + NB_ext], rdi
    jne 1b
    cmp [rax + NB_id], rsi
    jne 1b
    ret
8:  xor eax, eax
    ret

# nb_cell_by_id(nb, id) -> rax CL*, rdx its index, or rax 0
FN nb_cell_by_id
    xor ecx, ecx
1:  cmp rcx, [rdi + NB_cells + VEC_len]
    jae 8f
    mov rax, [rdi + NB_cells + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp [rax + NBC_id], rsi
    jne 1b
    lea rdx, [rcx - 1]
    ret
8:  xor eax, eax
    ret

# nb_cell(nb, i) -> CL* or 0
FN nb_cell
    test rsi, rsi
    js 8f
    cmp rsi, [rdi + NB_cells + VEC_len]
    jae 8f
    mov rax, [rdi + NB_cells + VEC_ptr]
    mov rax, [rax + rsi*8]
    ret
8:  xor eax, eax
    ret

# nb_sel_cell(nb) -> the selected cell, or 0
FN nb_sel_cell
    mov rsi, [rdi + NB_sel]
    jmp nb_cell

# app_doc_by_id(id) -> an open document by its id: a text document's (extproto_doc), or a
#   notebook's tab document, which extensions never see as text
FN app_doc_by_id
    push rbx
    mov rbx, rdi
    call extproto_doc
    test rax, rax
    jnz 9f
    xor ecx, ecx
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 8f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    mov rax, [rax + NB_host]
    cmp [rax + DOC_id], rbx
    jne 1b
    jmp 9f
8:  xor eax, eax
9:  pop rbx
    ret

# nb_sync_active(nb): g_doc follows the selected cell while the notebook is the active tab
FN nb_sync_active
    push rbx
    mov rbx, rdi
    call nb_active
    cmp rax, rbx
    jne 9f
    call app_sync_doc
9:  pop rbx
    ret

# nb_active_doc(host) -> the document g_doc is while the notebook's tab is active: its selected
#   cell's, or 0
FN nb_active_doc
    mov rdi, [rdi + DOC_nb]
    test rdi, rdi
    jz 8f
    call nb_sel_cell
    test rax, rax
    jz 8f
    mov rax, [rax + NBC_doc]
    ret
8:  xor eax, eax
    ret

# ---------------- opening and closing ----------------

# nb_open_tab(path, ext) -> the index of a new notebook tab for the file, which the extension
#   reads (nb-open) once it runs
FN nb_open_tab
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call doc_new
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_set_path
    mov rdi, r12
    call file_stamp
    mov [rbx + DOC_mtime], rax
    mov edi, NB_SIZE
    call mem_alloc
    mov r14, rax
    mov [r14 + NB_host], rbx
    mov [rbx + DOC_nb], r14
    mov [r14 + NB_ext], r13
    inc qword ptr [rip + nb_seq]
    mov rax, [rip + nb_seq]
    mov [r14 + NB_id], rax
    mov dword ptr [r14 + NB_want], NBR_OPEN
    call time_ms
    mov [r14 + NB_reqat], rax
    lea rdi, [rip + g_nbs]
    mov esi, 8
    call vec_push
    mov [rax], r14
    mov rdi, r13
    call nb_ext_wake
    mov rdi, rbx
    mov esi, TAB_NOTEBOOK
    call app_add_tab
    mov r15, rax
    mov rdi, r14
    call nb_pump
    mov rax, r15
    EPILOGUE

# nb_ext_wake(ext): an extension a notebook needs starts when it is idle or crashed; one the user
#   stopped stays stopped
nb_ext_wake:
    mov eax, [rdi + EXT_status]
    cmp eax, ES_IDLE
    je 1f
    cmp eax, ES_CRASHED
    jne 9f
1:  jmp ext_start
9:  ret

# nb_free(nb): the notebook goes (its tab is closing): its cells, the cells its undo keeps, its
#   record in g_nbs
FN nb_free
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + NB_host]
    mov qword ptr [r12 + DOC_nb], 0
    # g_doc may be one of its cells
    xor r13d, r13d
1:  cmp r13, [rbx + NB_cells + VEC_len]
    jae 2f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rdi, [rax + r13*8]
    mov rax, [rdi + NBC_doc]
    cmp rax, [rip + g_doc]
    jne 11f
    mov qword ptr [rip + g_doc], 0
11: call cl_free
    inc r13
    jmp 1b
2:  lea rdi, [rbx + NB_cells]
    call vec_free
    mov rdi, rbx
    call nu_clear
    lea rdi, [rbx + NB_undo]
    call vec_free
    lea rdi, [rbx + NB_meta]
    call sb_free
    lea rdi, [rbx + NB_kernel]
    call sb_free
    lea rdi, [rbx + NB_err]
    call sb_free
    lea rdi, [rbx + NB_sent]
    call vec_free
    # out of g_nbs
    xor ecx, ecx
3:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 5f
    mov rax, [rip + g_nbs + VEC_ptr]
    cmp [rax + rcx*8], rbx
    je 4f
    inc rcx
    jmp 3b
4:  mov rdx, [rip + g_nbs + VEC_len]
    dec rdx
    mov [rip + g_nbs + VEC_len], rdx
    mov rsi, [rax + rdx*8]
    mov [rax + rcx*8], rsi
5:  mov rdi, rbx
    call mem_free
    EPILOGUE

# nb_tab_closed(host): a notebook's tab closes (app_close_tab_now): the extension hears nb-closed,
#   a request it was asked is withdrawn, the notebook goes
FN nb_tab_closed
    PROLOGUE
    mov rbx, [rdi + DOC_nb]
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call nb_send_closed
    mov rdi, rbx
    call nb_req_drop
    mov rax, [rbx + NB_savefn]
    test rax, rax
    jz 1f
    mov qword ptr [rbx + NB_savefn], 0
    mov rdi, [rbx + NB_host]
    mov rdi, [rdi + DOC_id]
    mov rsi, [rbx + NB_savearg]
    mov rdx, -1
    call rax
1:  mov rdi, [rbx + NB_ext]     # its kernels end soon (nbexec.s)
    mov rsi, [rbx + NB_id]
    call nbexec_nb_closed
    mov rdi, rbx
    call nb_free
9:  EPILOGUE

# nb_req_drop(nb): rhun no longer waits on its request: "0 cancel ID" when one went out
nb_req_drop:
    push rbx
    mov rbx, rdi
    mov rsi, [rbx + NB_req]
    test rsi, rsi
    jz 1f
    mov qword ptr [rbx + NB_req], 0
    mov rdi, [rbx + NB_ext]
    push rsi
    push rdi
    call ext_reply_cap_drop
    pop rdi
    pop rsi
    call query_withdraw         # "0 cancel ID" when it runs
1:  mov dword ptr [rbx + NB_want], 0
    pop rbx
    ret

# nb_ext_gone(ext): the extension stopped: what it was asked fails, runs end, the kernel is gone
FN nb_ext_gone
    PROLOGUE
    mov r12, rdi
    call nbexec_ext_gone        # its kernels stop
    mov rdi, r12
    call nb_sent_forget         # and what it heard of the cells' order
    mov rdi, r12
    xor esi, esi
    call ext_reply_cap_drop
    xor r13d, r13d
1:  cmp r13, [rip + g_nbs + VEC_len]
    jae 9f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rbx, [rax + r13*8]
    inc r13
    cmp [rbx + NB_ext], r12
    jne 1b
    mov dword ptr [rbx + NB_kstate], NBK_NONE
    lea rdi, [rbx + NB_kernel]
    call sb_clear
    # runs that were queued or running are cancelled
    xor r14d, r14d
2:  cmp r14, [rbx + NB_cells + VEC_len]
    jae 3f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rax, [rax + r14*8]
    inc r14
    mov ecx, [rax + NBC_state]
    cmp ecx, NBRUN_QUEUED
    je 21f
    cmp ecx, NBRUN_RUNNING
    jne 2b
21: mov dword ptr [rax + NBC_state], NBRUN_CANCELLED
    mov dword ptr [rax + NBC_unsent], 0
    jmp 2b
3:  cmp qword ptr [rbx + NB_req], 0
    je 1b
    mov qword ptr [rbx + NB_req], 0
    mov rdi, rbx
    lea rsi, [rip + .Lstopped]
    call nb_req_failed
    jmp 1b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_req_failed(nb, why cstr): an nb-open fails (the notebook shows why and offers the text), or
#   an nb-save does (it stays dirty, a toast says why, its callback hears -1)
nb_req_failed:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + NB_reqkind]
    mov ecx, [rbx + NB_want]
    test ecx, ecx
    cmovnz eax, ecx
    mov dword ptr [rbx + NB_want], 0
    mov dword ptr [rbx + NB_reqkind], 0
    cmp eax, NBR_SAVE
    je 5f
    # open: a notebook that was open keeps its cells (a reload failed)
    cmp dword ptr [rbx + NB_state], NBS_READY
    je 4f
    mov dword ptr [rbx + NB_state], NBS_FAILED
    lea rdi, [rbx + NB_err]
    call sb_clear
    lea rdi, [rbx + NB_err]
    mov rsi, r12
    call sb_push_cstr
    jmp 9f
4:  mov rdi, r12
    call app_toast
    jmp 9f
5:  mov rdi, r12
    call app_toast
    mov rax, [rbx + NB_savefn]
    test rax, rax
    jz 9f
    mov qword ptr [rbx + NB_savefn], 0
    mov rdi, [rbx + NB_host]
    mov rdi, [rdi + DOC_id]
    mov rsi, [rbx + NB_savearg]
    mov rdx, -1
    call rax
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_pump(nb): what the notebook waits for goes out once its extension runs (nb-open, nb-save);
#   an extension that cannot run, does not speak notebooks or takes too long fails it
FN nb_pump
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + NB_want], 0
    je 9f
    cmp qword ptr [rbx + NB_req], 0
    jne 9f
    mov r12, [rbx + NB_ext]
    mov eax, [r12 + EXT_status]
    cmp eax, ES_RUNNING
    je 3f
    cmp eax, ES_STARTING
    je 2f
    cmp eax, ES_STOPPING
    je 2f
    cmp eax, ES_IDLE
    jne 1f
    cmp dword ptr [r12 + EXT_wait_slot], 0
    jne 2f
    mov rdi, r12
    call ext_start
    jmp 2f
1:  cmp eax, ES_CRASHED
    jne 11f
    mov rdi, r12
    call ext_start
    mov eax, [r12 + EXT_status]
    cmp eax, ES_STARTING
    je 2f
11: # stopped by the user or a limit, failed, disabled or removed
    mov rdi, r12
    lea rsi, [rip + .Lnot_running]
    call nb_why
    mov rdi, rbx
    mov rsi, rax
    call nb_req_failed
    jmp 9f
2:  call time_ms
    sub rax, [rbx + NB_reqat]
    cmp rax, NB_OPEN_MS
    jb 9f
    mov rdi, r12
    lea rsi, [rip + .Lno_answer]
    call nb_why
    mov rdi, rbx
    mov rsi, rax
    call nb_req_failed
    jmp 9f
3:  FEAT_TEST r12, FEAT_NOTEBOOKS
    jnz 4f
    mov rdi, r12
    lea rsi, [rip + .Lno_feature]
    call nb_why
    mov rdi, rbx
    mov rsi, rax
    call nb_req_failed
    jmp 9f
4:  xor edi, edi                # rhun waits on at most 64 requests
    call query_room
    test eax, eax
    jz 9f
    cmp dword ptr [rbx + NB_want], NBR_SAVE
    je 5f
    mov rdi, rbx
    call nb_send_open
    jmp 6f
5:  mov rdi, rbx
    call nb_send_save
6:  test rax, rax
    jle 7f
    mov [rbx + NB_req], rax
    mov eax, [rbx + NB_want]
    mov [rbx + NB_reqkind], eax
    mov dword ptr [rbx + NB_want], 0
    call time_ms
    mov [rbx + NB_reqat], rax
    jmp 9f
7:  # it could not be asked: rdx says why
    mov rdi, rbx
    mov rsi, rdx
    call nb_req_failed
9:  EPILOGUE

# nb_why(ext, what cstr) -> cstr in tmp: the extension's title, then what
nb_why:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + tmp]
    call sb_clear
    mov rsi, [rbx + EXT_title]
    test rsi, rsi
    jnz 1f
    mov rsi, [rbx + EXT_name]
1:  lea rdi, [rip + tmp]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, r12
    call sb_push_cstr
    mov rax, [rip + tmp + SB_ptr]
    EPILOGUE

# nb_tick(): every frame: requests that wait for their extension, dirty dots, edit records no
#   extension reads
FN nb_tick
    PROLOGUE
    call nbexec_tick            # kernels that ended
    xor r12d, r12d
1:  cmp r12, [rip + g_nbs + VEC_len]
    jae 9f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rbx, [rax + r12*8]
    inc r12
    mov rdi, rbx
    call nb_pump
    mov rdi, rbx
    call nb_runs_tick
    mov rdi, rbx
    call nb_sync_dirty
    # a pending request that never gets an answer
    cmp qword ptr [rbx + NB_req], 0
    je 2f
    call time_ms
    sub rax, [rbx + NB_reqat]
    cmp rax, NB_OPEN_MS
    jb 2f
    mov rdi, rbx
    call nb_req_drop
    mov rdi, [rbx + NB_ext]
    lea rsi, [rip + .Lno_answer]
    call nb_why
    mov rdi, rbx
    mov rsi, rax
    call nb_req_failed
2:  # cells' edit records go once every extension that knows them has them (A3), as a tab's do
    xor r13d, r13d
3:  cmp r13, [rbx + NB_cells + VEC_len]
    jae 1b
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rax, [rax + r13*8]
    inc r13
    mov rdi, [rax + NBC_doc]
    cmp qword ptr [rdi + DOC_xedits], 0
    je 3b
    call ext_edits_clear
    jmp 3b
9:  EPILOGUE

# nb_timeout() -> ms until nb_tick should look again: soon while a request waits for its program, or
#   while a kernel runs
FN nb_timeout
    xor ecx, ecx
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 8f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp dword ptr [rax + NB_want], 0
    jne 2f
    cmp qword ptr [rax + NB_req], 0
    je 1b
    mov eax, 500
    ret
2:  mov eax, 50
    ret
8:  jmp nbexec_timeout          # a running kernel's end is looked for

# ---------------- the extension's answers ----------------

# nb_reply(ext, id, ok, ptr, len) -> eax 1 when it answered a notebook's nb-open or nb-save. An
#   error's bytes are its CODE TEXT.
FN nb_reply
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], edx
    mov r14, rcx
    mov r15, r8
    xor ecx, ecx
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 8f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rbx, [rax + rcx*8]
    inc rcx
    cmp [rbx + NB_ext], r12
    jne 1b
    cmp [rbx + NB_req], r13
    jne 1b
    test r13, r13
    jz 1b
    mov qword ptr [rbx + NB_req], 0
    mov rdi, r12
    mov rsi, r13
    call ext_reply_cap_drop
    cmp dword ptr [rsp], 0
    je 5f
    cmp dword ptr [rbx + NB_reqkind], NBR_SAVE
    je 4f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call nb_opened
    jmp 7f
4:  mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call nb_saved
    jmp 7f
5:  # the extension's error: its text after the code
    lea rdi, [rip + tmp]
    call sb_clear
    mov rdi, r12
    lea rsi, [rip + .Lsays]
    call nb_why
    xor ecx, ecx
51: cmp rcx, r15
    jae 52f
    cmp byte ptr [r14 + rcx], ' '
    je 53f
    inc rcx
    jmp 51b
53: inc rcx
52: lea rsi, [r14 + rcx]
    mov rdx, r15
    sub rdx, rcx
    cmp rdx, 200
    jbe 54f
    mov edx, 200
54: lea rdi, [rip + tmp]
    call sb_push
    mov rdi, rbx
    mov rsi, [rip + tmp + SB_ptr]
    call nb_req_failed
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_opened(nb, ptr, len): nb-open's answer: the cells it reads replace the ones shown
nb_opened:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rbx + NB_reqkind], 0
    mov rdi, rsi
    mov rsi, rdx
    call nb_parse
    test rax, rax
    jz 1f
    mov rdi, rbx
    mov rsi, rax
    call nb_req_failed
    jmp 9f
1:  # the old cells go
    xor r12d, r12d
2:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 3f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rdi, [rax + r12*8]
    mov rax, [rdi + NBC_doc]
    cmp rax, [rip + g_doc]
    jne 21f
    mov qword ptr [rip + g_doc], 0
21: call cl_free
    inc r12
    jmp 2b
3:  lea rdi, [rbx + NB_cells]
    call vec_free
    mov rdi, rbx
    call nu_clear
    # the new ones in their place
    mov rax, [rip + newcells + VEC_ptr]
    mov [rbx + NB_cells + VEC_ptr], rax
    mov rax, [rip + newcells + VEC_len]
    mov [rbx + NB_cells + VEC_len], rax
    mov rax, [rip + newcells + VEC_cap]
    mov [rbx + NB_cells + VEC_cap], rax
    lea rdi, [rip + newcells]
    xor esi, esi
    mov edx, VEC_SIZE
    call memset
    lea rdi, [rbx + NB_meta]
    call sb_free
    mov rax, [rip + newmeta + SB_ptr]
    mov [rbx + NB_meta + SB_ptr], rax
    mov rax, [rip + newmeta + SB_len]
    mov [rbx + NB_meta + SB_len], rax
    mov rax, [rip + newmeta + SB_cap]
    mov [rbx + NB_meta + SB_cap], rax
    lea rdi, [rip + newmeta]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    # an empty notebook gets one code cell to type in
    cmp qword ptr [rbx + NB_cells + VEC_len], 0
    jne 4f
    mov edi, NBCK_CODE
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call cl_new
    lea rdi, [rbx + NB_cells]
    mov esi, 8
    push rax
    push rax
    call vec_push
    pop rcx
    pop rcx
    mov [rax], rcx
4:  mov rdi, rbx
    call nb_count_bytes
    mov dword ptr [rbx + NB_state], NBS_READY
    mov dword ptr [rbx + NB_dirty], 0
    mov dword ptr [rbx + NB_editing], 0
    lea rdi, [rbx + NB_err]
    call sb_clear
    mov rax, [rbx + NB_cells + VEC_len]
    dec rax
    cmp [rbx + NB_sel], rax
    jbe 5f
    mov [rbx + NB_sel], rax
5:  mov rax, [rbx + NB_host]
    and dword ptr [rax + DOC_flags], ~DF_DISK_CHANGED
    mov qword ptr [rax + DOC_savepoint], 0
    mov dword ptr [rbx + NB_layoutw], 0
    mov rdi, rbx
    call nb_sync_active
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_saved(nb, ptr, len): nb-save's answer is the file's bytes: written in place of the file
nb_saved:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov dword ptr [rbx + NB_reqkind], 0
    mov r14, [rbx + NB_host]
    mov rdi, [r14 + DOC_path]
    mov rsi, r12
    mov rdx, r13
    call file_write_all
    test rax, rax
    jns 2f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lwrite_failed]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + tmp + SB_ptr]
    mov dword ptr [rbx + NB_reqkind], NBR_SAVE
    call nb_req_failed
    jmp 9f
2:  mov r15, [rbx + NB_host]
    mov rdi, [r15 + DOC_path]
    call file_stamp
    mov [r15 + DOC_mtime], rax
    inc qword ptr [r15 + DOC_saves]
    and dword ptr [r15 + DOC_flags], ~DF_DISK_CHANGED
    mov qword ptr [r15 + DOC_disk_seen], 0
    mov rdi, rbx
    call nb_mark_saved
    mov rax, [rbx + NB_savefn]
    test rax, rax
    jz 9f
    mov qword ptr [rbx + NB_savefn], 0
    mov rdi, [r15 + DOC_id]
    mov rsi, [rbx + NB_savearg]
    xor edx, edx
    call rax
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- saving ----------------

# nb_save_start(host, flags, fn, arg) -> 0 saved, negative error, 1 queued: save_start's contract
#   for a notebook's document. fn(doc id, arg, result) hears the result of a queued save.
FN nb_save_start
    PROLOGUE
    mov rbx, [rdi + DOC_nb]
    mov r12, rdx
    mov r13, rcx
    test rbx, rbx
    jz 7f
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 7f
    cmp qword ptr [rbx + NB_req], 0
    jne 6f
    cmp dword ptr [rbx + NB_want], 0
    jne 6f
    mov [rbx + NB_savefn], r12
    mov [rbx + NB_savearg], r13
    mov dword ptr [rbx + NB_want], NBR_SAVE
    call time_ms
    mov [rbx + NB_reqat], rax
    mov rdi, [rbx + NB_ext]
    call nb_ext_wake
    mov rdi, rbx
    call nb_pump
    mov eax, 1
    EPILOGUE
6:  lea rdi, [rip + .Lbusy]
    call app_toast
    mov rax, -16
    EPILOGUE
7:  mov rax, -22
    EPILOGUE

# app_save_start(doc, flags, fn, arg): save_start, or nb_save_start for a notebook's document
FN app_save_start
    cmp qword ptr [rdi + DOC_nb], 0
    jne nb_save_start
    jmp save_start

# nb_mark_saved(nb): what is shown is what the file holds
FN nb_mark_saved
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 2f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rax, [rax + r12*8]
    mov rax, [rax + NBC_doc]
    mov rcx, [rax + DOC_undo + VEC_len]
    mov [rax + DOC_savepoint], rcx
    inc r12
    jmp 1b
2:  mov dword ptr [rbx + NB_dirty], 0
    mov rax, [rbx + NB_host]
    mov qword ptr [rax + DOC_savepoint], 0
    EPILOGUE

# nb_sync_dirty(nb) -> eax 1 when it differs from its file: a cell operation, an output or a cell's
#   text. The tab's document then counts as modified (DOC_savepoint -1), so the close and quit
#   questions, the tab's dot and the file watcher treat a notebook as a document.
FN nb_sync_dirty
    PROLOGUE
    mov rbx, rdi
    mov r13d, [rbx + NB_dirty]
    test r13d, r13d
    jnz 2f
    xor r12d, r12d
1:  cmp r12, [rbx + NB_cells + VEC_len]
    jae 2f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov rax, [rax + r12*8]
    inc r12
    mov rdi, [rax + NBC_doc]
    call doc_dirty
    test eax, eax
    jz 1b
    mov r13d, 1
2:  mov rax, [rbx + NB_host]
    xor ecx, ecx
    test r13d, r13d
    jz 3f
    mov rcx, -1
3:  cmp [rax + DOC_savepoint], rcx
    je 4f
    mov [rax + DOC_savepoint], rcx
    mov dword ptr [rip + g_dirty], 1
4:  mov eax, r13d
    EPILOGUE

# nb_disk_reload(host) -> eax 1: the file changed on disk while the notebook was clean (a dirty
#   one keeps its cells and shows the disk warning): it is read again
FN nb_disk_reload
    PROLOGUE
    mov rbx, [rdi + DOC_nb]
    mov r12, rdi
    test rbx, rbx
    jz 8f
    mov rdi, rbx
    call nb_sync_dirty
    test eax, eax
    jnz 7f
    cmp qword ptr [rbx + NB_req], 0
    jne 8f
    mov rdi, [r12 + DOC_path]
    call file_stamp
    mov [r12 + DOC_mtime], rax
    mov dword ptr [rbx + NB_want], NBR_OPEN
    call time_ms
    mov [rbx + NB_reqat], rax
    mov rdi, rbx
    call nb_pump
    mov eax, 1
    EPILOGUE
7:  or dword ptr [r12 + DOC_flags], DF_DISK_CHANGED
    mov dword ptr [rip + g_dirty], 1
8:  xor eax, eax
    EPILOGUE

# nb_reload(nb): Revert File: the file is read again, the notebook's changes go
FN nb_reload
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + NB_req], 0
    jne 9f
    mov r12, [rbx + NB_host]
    mov rdi, [r12 + DOC_path]
    call file_stamp
    mov [r12 + DOC_mtime], rax
    mov dword ptr [rbx + NB_want], NBR_OPEN
    call time_ms
    mov [rbx + NB_reqat], rax
    mov rdi, [rbx + NB_ext]
    call nb_ext_wake
    mov rdi, rbx
    call nb_pump
9:  EPILOGUE

# ---------------- cells ----------------

# cl_new(kind, lang ptr, lang len, source ptr, source len) -> CL* with a document of its own
FN cl_new
    PROLOGUE 16
    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov [rsp], r8
    mov edi, NBC_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + NBC_kind], r12d
    mov qword ptr [rbx + NBC_count], -1
    mov dword ptr [rbx + NBC_y], -1
    inc qword ptr [rip + g_nb_cell_seq]
    mov rax, [rip + g_nb_cell_seq]
    mov [rbx + NBC_id], rax
    call doc_new
    mov [rbx + NBC_doc], rax
    or dword ptr [rax + DOC_flags], DF_CELL
    lea rcx, [rip + .Lnb_cell_file]
    mov [rax + DOC_name], rcx
    mov rdi, rax
    mov rsi, r15
    mov rdx, [rsp]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Lempty]
    xor edx, edx
1:  call doc_replace_all
    mov rax, [rbx + NBC_doc]
    mov qword ptr [rax + DOC_cur], 0
    mov qword ptr [rax + DOC_anchor], 0
    # its language as named (code), or "-" for none
    test r14, r14
    jz 2f
    cmp r14, 1
    jne 3f
    cmp byte ptr [r13], '-'
    je 2f
3:  mov rdi, r13
    mov rsi, r14
    call mem_dup
    mov [rbx + NBC_lang], rax
2:  mov rdi, rbx
    call cl_set_language
    mov rax, rbx
    EPILOGUE

# cl_set_language(cl): Markdown for a markup cell, the language it names for a code cell
FN cl_set_language
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lmarkdown]
    cmp dword ptr [rbx + NBC_kind], NBCK_MARKUP
    je 3f
    mov rsi, [rbx + NBC_lang]
    test rsi, rsi
    jz 9f
    # "Visual_Basic" names "Visual Basic"
    lea rdi, [rip + langbuf]
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    cmp ecx, 128
    jae 2f
    cmp eax, '_'
    jne 11f
    mov eax, ' '
11: mov [rdi + rcx], al
    inc ecx
    jmp 1b
2:  mov byte ptr [rdi + rcx], 0
    lea rsi, [rip + langbuf]
3:  mov rdi, [rbx + NBC_doc]
    mov rdx, rsi
    mov esi, DL_NAMED
    call doc_language_set
9:  EPILOGUE

# cl_free(cl): a cell and its document go
FN cl_free
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + NBC_doc]
    call vim_forget
    mov rdi, [rbx + NBC_doc]
    call doc_free
    mov rdi, rbx
    call cl_clear_outputs
    lea rdi, [rbx + NBC_outs]
    call vec_free
    lea rdi, [rbx + NBC_meta]
    call sb_free
    mov rdi, [rbx + NBC_lang]
    call mem_free
    mov rdi, rbx
    call mem_free
    EPILOGUE

# cl_clear_outputs(cl) -> rax the bytes its outputs counted (NB_outbytes is the caller's)
FN cl_clear_outputs
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
1:  cmp r12, [rbx + NBC_outs + VEC_len]
    jae 2f
    mov rax, [rbx + NBC_outs + VEC_ptr]
    mov rdi, [rax + r12*8]
    add r13, [rdi + NBO_bytes]
    call ou_free
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + NBC_outs + VEC_len], 0
    inc qword ptr [rbx + NBC_outrev]
    mov dword ptr [rbx + NBC_clearwait], 0
    mov rax, r13
    EPILOGUE

# nb_clear_outputs(nb, cl): a cell's outputs go (Clear Outputs, a new run)
FN nb_clear_outputs
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [r12 + NBC_outs + VEC_len], 0
    je 9f
    mov rdi, r12
    call cl_clear_outputs
    sub [rbx + NB_outbytes], rax
    mov dword ptr [rbx + NB_dirty], 1
9:  mov dword ptr [rip + g_dirty], 1
    pop r12
    pop rbx
    ret

# nb_count_bytes(nb): NB_outbytes from its cells' outputs
nb_count_bytes:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rdi + NB_cells + VEC_len]
    jae 3f
    mov rdx, [rdi + NB_cells + VEC_ptr]
    mov rdx, [rdx + rcx*8]
    inc rcx
    xor r8d, r8d
2:  cmp r8, [rdx + NBC_outs + VEC_len]
    jae 1b
    mov r9, [rdx + NBC_outs + VEC_ptr]
    mov r9, [r9 + r8*8]
    add rax, [r9 + NBO_bytes]
    inc r8
    jmp 2b
3:  mov [rdi + NB_outbytes], rax
    ret

# ou_free(ou)
FN ou_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  cmp r12, [rbx + NBO_items + VEC_len]
    jae 2f
    imul rax, r12, NBI_SIZE
    add rax, [rbx + NBO_items + VEC_ptr]
    mov r13, rax
    mov rdi, [r13 + NBI_name]
    call mem_free
    lea rdi, [r13 + NBI_data]
    call sb_free
    inc r12
    jmp 1b
2:  lea rdi, [rbx + NBO_items]
    call vec_free
    lea rdi, [rbx + NBO_keep]
    call sb_free
    mov rdi, [rbx + NBO_id]
    call mem_free
    mov rdi, [rbx + NBO_img]
    call mem_free
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# nb_default_lang(nb) -> cstr: the language of its first code cell that names one, or 0
FN nb_default_lang
    xor ecx, ecx
1:  cmp rcx, [rdi + NB_cells + VEC_len]
    jae 8f
    mov rax, [rdi + NB_cells + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    cmp dword ptr [rax + NBC_kind], NBCK_CODE
    jne 1b
    mov rax, [rax + NBC_lang]
    test rax, rax
    jz 1b
    ret
8:  xor eax, eax
    ret

# ---------------- cell operations and their undo ----------------

# vec_ptr_insert(vec, i, ptr): ptr at index i, the ones after it one place on
vec_ptr_insert:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov esi, 8
    call vec_push
    mov rax, [rbx + VEC_ptr]
    lea rsi, [rax + r12*8]
    lea rdi, [rsi + 8]
    mov rdx, [rbx + VEC_len]
    dec rdx
    sub rdx, r12
    shl rdx, 3
    call memmove
    mov rax, [rbx + VEC_ptr]
    mov [rax + r12*8], r13
    EPILOGUE

# vec_ptr_remove(vec, i) -> the ptr that was at index i
vec_ptr_remove:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rbx + VEC_ptr]
    mov r13, [rax + r12*8]
    lea rdi, [rax + r12*8]
    lea rsi, [rdi + 8]
    mov rdx, [rbx + VEC_len]
    sub rdx, r12
    dec rdx
    shl rdx, 3
    call memmove
    dec qword ptr [rbx + VEC_len]
    mov rax, r13
    EPILOGUE

# nu_push(nb, op, index, index2, cell): a record for z; past NB_UNDO_MAX the oldest goes
nu_push:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    cmp qword ptr [rbx + NB_undo + VEC_len], NB_UNDO_MAX
    jb 1f
    mov rax, [rbx + NB_undo + VEC_ptr]
    mov rdi, [rax + NBU_cell]
    test rdi, rdi
    jz 2f
    call cl_free
2:  mov rdi, [rbx + NB_undo + VEC_ptr]
    lea rsi, [rdi + NBU_SIZE]
    mov rdx, [rbx + NB_undo + VEC_len]
    dec rdx
    imul rdx, rdx, NBU_SIZE
    call memmove
    dec qword ptr [rbx + NB_undo + VEC_len]
1:  lea rdi, [rbx + NB_undo]
    mov esi, NBU_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + NBU_op], rcx
    mov rcx, [rsp + 8]
    mov [rax + NBU_index], rcx
    mov rcx, [rsp + 16]
    mov [rax + NBU_index2], rcx
    mov rcx, [rsp + 24]
    mov [rax + NBU_cell], rcx
    EPILOGUE

# nu_clear(nb): its undo records go, with the cells they kept
nu_clear:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + NB_undo + VEC_len]
    jae 2f
    imul rax, r12, NBU_SIZE
    add rax, [rbx + NB_undo + VEC_ptr]
    mov rdi, [rax + NBU_cell]
    inc r12
    test rdi, rdi
    jz 1b
    call cl_free
    jmp 1b
2:  mov qword ptr [rbx + NB_undo + VEC_len], 0
    EPILOGUE

# nb_insert_cell(nb, i, kind) -> CL*: a new empty cell at index i, selected
FN nb_insert_cell
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 8f
    cmp qword ptr [rbx + NB_cells + VEC_len], NB_CELLS_MAX
    jae 8f
    mov rdi, rbx
    call nb_default_lang
    xor esi, esi
    xor edx, edx
    test rax, rax
    jz 1f
    mov rsi, rax
    mov rdi, rax
    push rsi
    push rsi
    call strlen
    pop rsi
    pop rsi
    mov rdx, rax
1:  mov edi, r13d
    xor ecx, ecx
    xor r8d, r8d
    call cl_new
    mov r14, rax
    lea rdi, [rbx + NB_cells]
    mov rsi, r12
    mov rdx, r14
    call vec_ptr_insert
    mov rdi, rbx
    mov esi, NBUO_INSERT
    mov rdx, r12
    xor ecx, ecx
    xor r8d, r8d
    call nu_push
    mov [rbx + NB_sel], r12
    mov dword ptr [rbx + NB_dirty], 1
    mov dword ptr [rbx + NB_reveal], 1
    mov rdi, rbx
    call nb_sync_active
    mov dword ptr [rip + g_dirty], 1
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_delete_cell(nb, i): the cell leaves (z brings it back); the last one leaves an empty one
FN nb_delete_cell
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 9f
    cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    lea rdi, [rbx + NB_cells]
    mov rsi, r12
    call vec_ptr_remove
    mov r13, rax
    mov rax, [r13 + NBC_doc]
    cmp rax, [rip + g_doc]
    jne 1f
    mov qword ptr [rip + g_doc], 0
1:  mov dword ptr [r13 + NBC_state], NBRUN_NONE
    mov rdi, rbx
    mov esi, NBUO_DELETE
    mov rdx, r12
    xor ecx, ecx
    mov r8, r13
    call nu_push
    mov dword ptr [rbx + NB_dirty], 1
    cmp qword ptr [rbx + NB_cells + VEC_len], 0
    jne 2f
    mov rdi, rbx
    xor esi, esi
    mov edx, NBCK_CODE
    call nb_insert_cell
2:  mov rax, [rbx + NB_cells + VEC_len]
    dec rax
    cmp r12, rax
    jbe 3f
    mov r12, rax
3:  mov [rbx + NB_sel], r12
    mov dword ptr [rbx + NB_reveal], 1
    mov dword ptr [rbx + NB_layoutw], 0
    mov rdi, rbx
    call nb_sync_active
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_move_cell(nb, i, dir): the cell moves one place up (dir -1) or down (1), selected
FN nb_move_cell
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    cmp dword ptr [rbx + NB_state], NBS_READY
    jne 9f
    test r13, r13
    js 9f
    cmp r13, [rbx + NB_cells + VEC_len]
    jae 9f
    cmp r12, [rbx + NB_cells + VEC_len]
    jae 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call nb_swap
    mov rdi, rbx
    mov esi, NBUO_MOVE
    mov rdx, r12
    mov rcx, r13
    xor r8d, r8d
    call nu_push
    mov [rbx + NB_sel], r13
    mov dword ptr [rbx + NB_dirty], 1
    mov dword ptr [rbx + NB_reveal], 1
    mov dword ptr [rbx + NB_layoutw], 0
    mov rdi, rbx
    call nb_sync_active
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_swap(nb, i, j): two cells trade places
nb_swap:
    mov rax, [rdi + NB_cells + VEC_ptr]
    mov rcx, [rax + rsi*8]
    mov r8, [rax + rdx*8]
    mov [rax + rsi*8], r8
    mov [rax + rdx*8], rcx
    ret

# nb_set_kind(nb, i, kind): a code cell becomes markup or the other way; its outputs and count go
FN nb_set_kind
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, rbx
    mov rsi, r12
    call nb_cell
    test rax, rax
    jz 9f
    mov r14, rax
    mov ecx, [r14 + NBC_kind]
    cmp ecx, r13d
    je 9f
    mov rdi, rbx
    mov esi, NBUO_KIND
    mov rdx, r12
    xor r8d, r8d
    call nu_push
    mov rdi, rbx
    mov rsi, r14
    mov edx, r13d
    call nb_kind_now
9:  EPILOGUE

# nb_kind_now(nb, cl, kind): the cell takes the kind
nb_kind_now:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov [r12 + NBC_kind], edx
    mov qword ptr [r12 + NBC_count], -1
    mov dword ptr [r12 + NBC_state], NBRUN_NONE
    mov rdi, rbx
    mov rsi, r12
    call nb_clear_outputs
    cmp dword ptr [r12 + NBC_kind], NBCK_CODE
    jne 1f
    cmp qword ptr [r12 + NBC_lang], 0
    jne 1f
    mov rdi, rbx
    call nb_default_lang
    test rax, rax
    jz 1f
    mov rdi, rax
    call dup_cstr
    mov [r12 + NBC_lang], rax
1:  mov rdi, r12
    call cl_set_language
    mov dword ptr [rbx + NB_dirty], 1
    mov dword ptr [rbx + NB_layoutw], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nb_undo_op(nb) -> eax 1 when the last cell operation was undone
FN nb_undo_op
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + NB_undo + VEC_len]
    test rax, rax
    jz 8f
    dec rax
    mov [rbx + NB_undo + VEC_len], rax
    imul rax, rax, NBU_SIZE
    add rax, [rbx + NB_undo + VEC_ptr]
    mov r12, rax
    mov rax, [r12 + NBU_op]
    cmp rax, NBUO_INSERT
    je .Lnu_insert
    cmp rax, NBUO_DELETE
    je .Lnu_delete
    cmp rax, NBUO_MOVE
    je .Lnu_move
    # kind: back to the old one
    mov rdi, rbx
    mov rsi, [r12 + NBU_index]
    call nb_cell
    test rax, rax
    jz 7f
    mov rsi, rax
    mov rdi, rbx
    mov edx, [r12 + NBU_index2]
    call nb_kind_now
    mov rax, [r12 + NBU_index]
    mov [rbx + NB_sel], rax
    jmp 7f
.Lnu_insert:
    mov r13, [r12 + NBU_index]
    cmp r13, [rbx + NB_cells + VEC_len]
    jae 7f
    cmp qword ptr [rbx + NB_cells + VEC_len], 1
    jbe 7f                      # the only cell stays
    lea rdi, [rbx + NB_cells]
    mov rsi, r13
    call vec_ptr_remove
    mov rdi, rax
    mov rax, [rdi + NBC_doc]
    cmp rax, [rip + g_doc]
    jne 1f
    mov qword ptr [rip + g_doc], 0
1:  call cl_free
    mov rax, [rbx + NB_cells + VEC_len]
    dec rax
    cmp r13, rax
    jbe 2f
    mov r13, rax
2:  mov [rbx + NB_sel], r13
    jmp 7f
.Lnu_delete:
    mov r13, [r12 + NBU_index]
    mov rax, [rbx + NB_cells + VEC_len]
    cmp r13, rax
    cmova r13, rax
    lea rdi, [rbx + NB_cells]
    mov rsi, r13
    mov rdx, [r12 + NBU_cell]
    mov qword ptr [r12 + NBU_cell], 0
    call vec_ptr_insert
    mov [rbx + NB_sel], r13
    jmp 7f
.Lnu_move:
    mov rsi, [r12 + NBU_index2]
    mov rdx, [r12 + NBU_index]
    cmp rsi, [rbx + NB_cells + VEC_len]
    jae 7f
    cmp rdx, [rbx + NB_cells + VEC_len]
    jae 7f
    mov rdi, rbx
    call nb_swap
    mov rax, [r12 + NBU_index]
    mov [rbx + NB_sel], rax
7:  mov dword ptr [rbx + NB_dirty], 1
    mov dword ptr [rbx + NB_reveal], 1
    mov dword ptr [rbx + NB_layoutw], 0
    mov rdi, rbx
    call nb_count_bytes
    mov rdi, rbx
    call nb_sync_active
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- reading bodies ----------------

# rd_line() -> eax the fields of the next line (at most 16), -1 when no line feed is left; rd_cur
#   moves past the line feed
FN nb_rd_line
rd_line:
    mov rax, [rip + rd_cur]
    mov rdx, [rip + rd_end]
    mov rcx, rax
1:  cmp rcx, rdx
    jae 8f
    cmp byte ptr [rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  lea r8, [rcx + 1]
    mov [rip + rd_cur], r8
    # fields of [rax, rcx)
    xor r9d, r9d
    lea r10, [rip + rd_f]
3:  cmp rax, rcx
    jae 6f
    cmp byte ptr [rax], ' '
    jne 4f
    inc rax
    jmp 3b
4:  cmp r9d, 16
    jae 6f
    mov r11, r9
    shl r11, 4
    mov [r10 + r11], rax
    mov rdx, rax
5:  cmp rdx, rcx
    jae 51f
    cmp byte ptr [rdx], ' '
    je 51f
    inc rdx
    jmp 5b
51: mov r8, rdx
    sub r8, rax
    mov [r10 + r11 + 8], r8
    inc r9d
    mov rax, rdx
    jmp 3b
6:  mov [rip + rd_n], r9
    mov eax, r9d
    ret
8:  mov eax, -1
    ret

# rd_u64(i) -> rax the value of field i, edx 1 when it is a plain decimal of at most 18 digits
FN nb_rd_u64
rd_u64:
    cmp rdi, [rip + rd_n]
    jae 8f
    push rbx
    lea rax, [rip + rd_f]
    shl rdi, 4
    mov rbx, [rax + rdi + 8]
    mov rdi, [rax + rdi]
    test rbx, rbx
    jz 7f
    cmp rbx, 18
    ja 7f
    mov rsi, rbx
    call parse_u64
    cmp rdx, rbx
    jne 7f
    mov edx, 1
    pop rbx
    ret
7:  pop rbx
8:  xor eax, eax
    xor edx, edx
    ret

# rd_field(i) -> rax ptr, rdx len of field i (len 0 past the line's fields)
rd_field:
    cmp rdi, [rip + rd_n]
    jae 8f
    lea rax, [rip + rd_f]
    shl rdi, 4
    mov rdx, [rax + rdi + 8]
    mov rax, [rax + rdi]
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# rd_is(i, cstr) -> eax 1 when field i is the word
rd_is:
    push rsi
    call rd_field
    pop rcx
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rcx
    jmp str_eq_cstr
8:  xor eax, eax
    ret

# rd_bytes(n) -> rax a pointer to the next n bytes, 0 when fewer are left; rd_cur moves past them
FN nb_rd_bytes
rd_bytes:
    mov rax, [rip + rd_cur]
    mov rcx, [rip + rd_end]
    sub rcx, rax
    cmp rdi, rcx
    ja 8f
    add [rip + rd_cur], rdi
    ret
8:  xor eax, eax
    ret

# rd_begin(ptr, len): read from these bytes
FN nb_rd_begin
rd_begin:
    mov [rip + rd_cur], rdi
    add rdi, rsi
    mov [rip + rd_end], rdi
    ret

# rd_left() -> bytes not read yet
FN nb_rd_left
    mov rax, [rip + rd_end]
    sub rax, [rip + rd_cur]
    ret

# token_ok(ptr, len, max) -> eax 1 when it is 1 to max bytes of [a-z0-9_.+/-] (a type, an OUTID)
token_ok:
    test rsi, rsi
    jz 8f
    cmp rsi, rdx
    ja 8f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp eax, '_'
    je 1b
    cmp eax, '-'
    je 1b
    cmp eax, '.'
    je 1b
    cmp eax, '+'
    je 1b
    cmp eax, '/'
    je 1b
    lea r8d, [rax - '0']
    cmp r8d, 9
    jbe 1b
    lea r8d, [rax - 'a']
    cmp r8d, 25
    jbe 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# nb_parse(ptr, len) -> rax 0 with the cells in newcells and the metadata in newmeta, or a cstr
#   saying why the body cannot be read (newcells empty then)
FN nb_parse
    PROLOGUE 48
    call rd_begin
    lea rdi, [rip + newmeta]
    call sb_clear
    call newcells_free
    call rd_line
    cmp eax, 2
    jb .Lnp_bad
    xor edi, edi
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    cmp rax, NB_CELLS_MAX
    ja .Lnp_toobig
    mov [rsp], rax              # cells
    mov edi, 1
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    mov rdi, rax
    mov [rsp + 8], rax
    call rd_bytes
    test rax, rax
    jz .Lnp_bad
    lea rdi, [rip + newmeta]
    mov rsi, rax
    mov rdx, [rsp + 8]
    call sb_push
    xor r12d, r12d
.Lnp_cell:
    cmp r12, [rsp]
    jae .Lnp_done
    call rd_line
    cmp eax, 6
    jb .Lnp_bad
    xor r13d, r13d              # NBCK_CODE
    xor edi, edi
    lea rsi, [rip + .Lk_code]
    call rd_is
    test eax, eax
    jnz 1f
    xor edi, edi
    lea rsi, [rip + .Lk_markup]
    call rd_is
    test eax, eax
    jz .Lnp_bad
    mov r13d, NBCK_MARKUP
1:  # LANG, kept to make the cell
    mov edi, 1
    call rd_field
    cmp rdx, 128
    ja .Lnp_bad
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    # COUNT
    mov qword ptr [rsp + 32], -1
    mov edi, 2
    lea rsi, [rip + .Ldash]
    call rd_is
    test eax, eax
    jnz 2f
    mov edi, 2
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    mov [rsp + 32], rax
2:  mov edi, 3
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    cmp rax, NB_SOURCE_MAX
    ja .Lnp_toobig
    mov r14, rax                # source length
    mov edi, 4
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    mov r15, rax                # meta length
    mov edi, 5
    call rd_u64
    test edx, edx
    jz .Lnp_bad
    cmp rax, NB_OUTS_MAX
    ja .Lnp_toobig
    mov [rsp + 40], rax         # outputs
    mov rdi, r14
    call rd_bytes
    test rax, rax
    jz .Lnp_bad
    mov rcx, rax                # source
    mov edi, r13d
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    mov r8, r14
    call cl_new
    mov rbx, rax
    lea rdi, [rip + newcells]
    mov esi, 8
    call vec_push
    mov [rax], rbx
    mov rax, [rsp + 32]
    mov [rbx + NBC_count], rax
    mov rdi, r15
    call rd_bytes
    test rax, rax
    jz .Lnp_bad
    lea rdi, [rbx + NBC_meta]
    mov rsi, rax
    mov rdx, r15
    call sb_push
    # its outputs
.Lnp_out:
    cmp qword ptr [rsp + 40], 0
    je .Lnp_next
    dec qword ptr [rsp + 40]
    call nb_rd_output
    test rax, rax
    jz .Lnp_bad
    mov r14, rax
    lea rdi, [rbx + NBC_outs]
    mov esi, 8
    call vec_push
    mov [rax], r14
    jmp .Lnp_out
.Lnp_next:
    inc r12
    jmp .Lnp_cell
.Lnp_done:
    xor eax, eax
    EPILOGUE
.Lnp_toobig:
    call newcells_free
    lea rax, [rip + .Lbody_large]
    EPILOGUE
.Lnp_bad:
    call newcells_free
    lea rax, [rip + .Lbody_bad]
    EPILOGUE

# newcells_free(): nb_parse's cells go
newcells_free:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + newcells + VEC_len]
    jae 2f
    mov rax, [rip + newcells + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call cl_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + newcells + VEC_len], 0
    EPILOGUE

# nb_rd_output() -> OU* read from the body (rd_*), or 0 when it cannot be read
FN nb_rd_output
    PROLOGUE 32
    call rd_line
    cmp eax, 4
    jb 8f
    xor r13d, r13d
    lea r12, [rip + ouk_names]
1:  mov rsi, [r12 + r13*8]
    test rsi, rsi
    jz 8f
    xor edi, edi
    call rd_is
    inc r13d
    test eax, eax
    jz 1b
    mov edi, 2
    call rd_u64
    test edx, edx
    jz 8f
    mov r14, rax                # KEEP_LEN
    mov edi, 3
    call rd_u64
    test edx, edx
    jz 8f
    cmp rax, NB_ITEMS_MAX
    ja 8f
    mov r15, rax                # NITEM
    mov edi, NBO_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + NBO_kind], r13d
    mov qword ptr [rbx + NBO_show], -1
    # OUTID
    mov edi, 1
    call rd_field
    cmp rdx, 1
    jne 2f
    cmp byte ptr [rax], '-'
    je 3f
2:  mov rdi, rax
    mov rsi, rdx
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov edx, 64
    call token_ok
    test eax, eax
    jz 7f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [rbx + NBO_id], rax
3:  mov rdi, r14
    call rd_bytes
    test rax, rax
    jz 7f
    lea rdi, [rbx + NBO_keep]
    mov rsi, rax
    mov rdx, r14
    call sb_push
    add [rbx + NBO_bytes], r14
    # the items
4:  test r15, r15
    jz 6f
    dec r15
    call rd_line
    cmp eax, 4
    jb 7f
    lea rdi, [rbx + NBO_items]
    mov esi, NBI_SIZE
    call vec_push
    mov r12, rax
    mov edi, 1
    call rd_u64
    test edx, edx
    jz 7f
    cmp rax, 65536
    ja 7f
    mov [r12 + NBI_w], eax
    mov edi, 2
    call rd_u64
    test edx, edx
    jz 7f
    cmp rax, 65536
    ja 7f
    mov [r12 + NBI_h], eax
    mov edi, 3
    call rd_u64
    test edx, edx
    jz 7f
    cmp rax, NB_ITEM_MAX
    ja 7f
    mov r14, rax
    # the type: known, or kept by name
    xor r13d, r13d
5:  lea rax, [rip + nit_names]
    mov rsi, [rax + r13*8]
    test rsi, rsi
    jz 51f
    xor edi, edi
    call rd_is
    inc r13d
    test eax, eax
    jz 5b
    mov [r12 + NBI_type], r13d
    jmp 52f
51: xor edi, edi
    call rd_field
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rax
    mov rsi, rdx
    mov edx, 64
    call token_ok
    test eax, eax
    jz 7f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [r12 + NBI_name], rax
52: mov rdi, r14
    call rd_bytes
    test rax, rax
    jz 7f
    lea rdi, [r12 + NBI_data]
    mov rsi, rax
    mov rdx, r14
    call sb_push
    add [rbx + NBO_bytes], r14
    jmp 4b
6:  mov rdi, rbx
    call ou_ready
    mov rax, rbx
    EPILOGUE
7:  mov rdi, rbx
    call ou_free
8:  xor eax, eax
    EPILOGUE

# ou_ready(ou): which item it shows, and a text item's lines
FN ou_ready
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + NBO_show], -1
    mov qword ptr [rbx + NBO_lines], 0
    mov dword ptr [rbx + NBO_ikey], 0
    mov dword ptr [rbx + NBO_ierr], 0
    mov rdi, [rbx + NBO_img]
    call mem_free
    mov qword ptr [rbx + NBO_img], 0
    xor r12d, r12d
1:  cmp r12, [rbx + NBO_items + VEC_len]
    jae 9f
    imul r13, r12, NBI_SIZE
    add r13, [rbx + NBO_items + VEC_ptr]
    inc r12
    mov eax, [r13 + NBI_type]
    cmp eax, NBIT_TEXT
    jb 1b
    cmp eax, NBIT_GIF
    ja 1b
    lea rax, [r12 - 1]
    mov [rbx + NBO_show], rax
    mov eax, [r13 + NBI_type]
    cmp eax, NBIT_ANSI
    ja 9f
    # lines: line feeds, and one more when the text does not end in one
    mov rdi, [r13 + NBI_data + SB_ptr]
    mov rsi, [r13 + NBI_data + SB_len]
    call count_lines
    mov [rbx + NBO_lines], rax
9:  EPILOGUE

# count_lines(ptr, len) -> lines of the text
FN nb_count_lines
count_lines:
    xor eax, eax
    test rsi, rsi
    jz 9f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 10
    jne 11f
    inc rax
11: inc rcx
    jmp 1b
2:  cmp byte ptr [rdi + rsi - 1], 10
    je 9f
    inc rax
9:  ret

# ---------------- writing bodies ----------------

# nb_write(nb, sb) -> eax 1 with the notebook body appended to sb, 0 when it would pass NB_BODY_MAX
FN nb_write
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov rsi, [rbx + NB_cells + VEC_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + NB_meta + SB_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + NB_meta + SB_ptr]
    mov rdx, [rbx + NB_meta + SB_len]
    call sb_push
    xor r13d, r13d
1:  cmp r13, [rbx + NB_cells + VEC_len]
    jae 8f
    cmp qword ptr [r12 + SB_len], NB_BODY_MAX
    ja 7f
    mov rax, [rbx + NB_cells + VEC_ptr]
    mov r14, [rax + r13*8]
    inc r13
    lea rsi, [rip + .Lk_code]
    cmp dword ptr [r14 + NBC_kind], NBCK_CODE
    je 2f
    lea rsi, [rip + .Lk_markup]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, [r14 + NBC_lang]
    cmp dword ptr [r14 + NBC_kind], NBCK_CODE
    jne 21f
    test rsi, rsi
    jnz 22f
21: lea rsi, [rip + .Ldash]
22: mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, [r14 + NBC_count]
    test rsi, rsi
    js 23f
    mov rdi, r12
    call sb_push_u64
    jmp 24f
23: mov rdi, r12
    mov esi, '-'
    call sb_push_byte
24: mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, [r14 + NBC_doc]
    call doc_len
    mov r15, rax
    mov rdi, r12
    mov rsi, rax
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + NBC_meta + SB_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + NBC_outs + VEC_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    # the source, straight from the gap buffer
    mov rdi, r12
    mov rsi, r15
    call sb_reserve
    mov rcx, rax
    mov rdi, [r14 + NBC_doc]
    xor esi, esi
    mov rdx, r15
    call doc_copy
    add [r12 + SB_len], r15
    mov rdi, r12
    mov rsi, [r14 + NBC_meta + SB_ptr]
    mov rdx, [r14 + NBC_meta + SB_len]
    call sb_push
    xor r15d, r15d
3:  cmp r15, [r14 + NBC_outs + VEC_len]
    jae 1b
    mov rax, [r14 + NBC_outs + VEC_ptr]
    mov rdi, [rax + r15*8]
    mov rsi, r12
    call nb_write_output
    inc r15
    jmp 3b
7:  xor eax, eax
    EPILOGUE
8:  xor eax, eax
    cmp qword ptr [r12 + SB_len], NB_BODY_MAX
    ja 9f
    mov eax, 1
9:  EPILOGUE

# nb_write_output(ou, sb): an output body
FN nb_write_output
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + NBO_kind]
    dec eax
    lea rcx, [rip + ouk_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rsi, [rbx + NBO_id]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Ldash]
1:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + NBO_keep + SB_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + NBO_items + VEC_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + NBO_keep + SB_ptr]
    mov rdx, [rbx + NBO_keep + SB_len]
    call sb_push
    xor r13d, r13d
2:  cmp r13, [rbx + NBO_items + VEC_len]
    jae 9f
    imul r14, r13, NBI_SIZE
    add r14, [rbx + NBO_items + VEC_ptr]
    inc r13
    mov rsi, [r14 + NBI_name]
    test rsi, rsi
    jnz 3f
    mov eax, [r14 + NBI_type]
    dec eax
    lea rcx, [rip + nit_names]
    mov rsi, [rcx + rax*8]
3:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + NBI_w]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + NBI_h]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + NBI_data + SB_len]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + NBI_data + SB_ptr]
    mov rdx, [r14 + NBI_data + SB_len]
    call sb_push
    jmp 2b
9:  EPILOGUE

.section .rodata
.p2align 3
.globl nb_ouk_names, nb_nit_names
nb_ouk_names:
ouk_names: .quad .Lo_stdout, .Lo_stderr, .Lo_result, .Lo_display, .Lo_error, 0
nb_nit_names:
nit_names: .quad .Li_text, .Li_ansi, .Li_png, .Li_jpeg, .Li_gif, .Li_rich, .Li_picture, 0
.Lo_stdout: .asciz "stdout"
.Lo_stderr: .asciz "stderr"
.Lo_result: .asciz "result"
.Lo_display: .asciz "display"
.Lo_error: .asciz "error"
.Li_text: .asciz "text"
.Li_ansi: .asciz "ansi"
.Li_png: .asciz "png"
.Li_jpeg: .asciz "jpeg"
.Li_gif: .asciz "gif"
.Li_rich: .asciz "rich"
.Li_picture: .asciz "picture"
.Lk_code: .asciz "code"
.Lk_markup: .asciz "markup"
.Ldash: .asciz "-"
.Lempty: .asciz ""
.Lmarkdown: .asciz "Markdown"
.Lnb_cell_file: .asciz "cell"
.Lstopped: .asciz "The notebook's extension stopped"
.Lnot_running: .asciz " is not running: restart it on the Extensions page"
.Lno_answer: .asciz " did not answer"
.Lno_feature: .asciz " does not read notebooks (the notebooks feature)"
.Lsays: .asciz ": "
.Lbusy: .asciz "The notebook is being saved"
.Lwrite_failed: .asciz "Could not write the notebook"
.Lbody_bad: .asciz "The extension's notebook cannot be read"
.Lbody_large: .asciz "The notebook is too big"

.text
# ---------------- cells as documents for language providers (A3) ----------------

# nb_ext_doc_at(ext, i) -> DOC* of the i-th cell of the open notebooks, for an extension that agreed
#   notebooks (extproto_events walks them after the tabs); 0 past the last, and always for one that
#   did not. Walking i = 0, 1, 2... costs one step each.
FN nb_ext_doc_at
    FEAT_TEST rdi, FEAT_NOTEBOOKS
    jz 8f
    test rsi, rsi
    jz 1f
    cmp rdi, [rip + nbx_ext]
    jne 1f
    lea rax, [rsi - 1]
    cmp rax, [rip + nbx_i]
    jne 1f
    mov rcx, [rip + nbx_nb]
    mov rdx, [rip + nbx_c]
    inc rdx
    call nbx_norm
    jmp 5f
1:  mov [rip + nbx_ext], rdi
    xor ecx, ecx
    xor edx, edx
    mov r8, rsi
2:  call nbx_norm
    test rax, rax
    jz 9f
    test r8, r8
    jz 5f
    inc rdx
    dec r8
    jmp 2b
5:  mov [rip + nbx_i], rsi
    mov [rip + nbx_nb], rcx
    mov [rip + nbx_c], rdx
    ret
8:  xor eax, eax
9:  mov qword ptr [rip + nbx_ext], 0
    ret

# nbx_norm(rcx notebook, rdx cell) -> rax the DOC* of that cell, or of the next one there is (rcx and
#   rdx move to it), or 0; only notebooks that are open count
nbx_norm:
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 8f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rax, [rax + rcx*8]
    cmp dword ptr [rax + NB_state], NBS_READY
    jne 2f
    cmp rdx, [rax + NB_cells + VEC_len]
    jae 2f
    mov rax, [rax + NB_cells + VEC_ptr]
    mov rax, [rax + rdx*8]
    mov rax, [rax + NBC_doc]
    ret
2:  inc rcx
    xor edx, edx
    jmp 1b
8:  xor eax, eax
    ret

# nb_cell_doc_by_id(id) -> DOC* of the cell with that document id, or 0
FN nb_cell_doc_by_id
    xor ecx, ecx
    xor edx, edx
1:  call nbx_norm
    test rax, rax
    jz 9f
    cmp [rax + DOC_id], rdi
    je 9f
    inc rdx
    jmp 1b
9:  ret

# nb_active_cell_id() -> the DOC id of the selected cell while a notebook tab is active, or 0
FN nb_active_cell_id
    sub rsp, 8
    call nb_active
    test rax, rax
    jz 9f
    mov rcx, [rax + NB_sel]
    cmp rcx, [rax + NB_cells + VEC_len]
    jae 8f
    mov rax, [rax + NB_cells + VEC_ptr]
    mov rax, [rax + rcx*8]
    mov rax, [rax + NBC_doc]
    mov rax, [rax + DOC_id]
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    ret

# nb_cell_match(patterns, doc) -> eax 1 when a cell's language's usual file name matches the
#   patterns: a Python cell is "cell.py" to a provider of *.py (the grammar's first "*." pattern)
FN nb_cell_match
    PROLOGUE 16
    mov rbx, rdi
    mov rdi, rsi
    call doc_language
    test rax, rax
    jz 8f
    mov r12, [rax + GR_files]
    test r12, r12
    jz 8f
    mov rdi, r12
    call strlen
    mov r13, rax
1:  test r13, r13
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    cmp rdx, 2
    jbe 1b
    cmp word ptr [rax], 0x2e2a      # "*."
    jne 1b
    lea r14, [rax + 1]
    lea r15, [rdx - 1]
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lnb_cell_file]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, r14
    mov rdx, r15
    call sb_push
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, rbx
    call ext_path_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nb_sent_hash(nb, ext, hash) -> eax 1 when the extension heard this order already; else it is
#   remembered as heard
FN nb_sent_hash
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor ecx, ecx
1:  cmp rcx, [rbx + NB_sent + VEC_len]
    jae 3f
    imul rax, rcx, NBS2_SIZE
    add rax, [rbx + NB_sent + VEC_ptr]
    inc rcx
    cmp [rax + NBS2_ext], r12
    jne 1b
    cmp [rax + NBS2_hash], r13
    je 8f
    mov [rax + NBS2_hash], r13
    xor eax, eax
    EPILOGUE
3:  lea rdi, [rbx + NB_sent]
    mov esi, NBS2_SIZE
    call vec_push
    mov [rax + NBS2_ext], r12
    mov [rax + NBS2_hash], r13
    xor eax, eax
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# nb_sent_forget(ext): what the extension heard of every notebook goes (it stopped)
FN nb_sent_forget
    xor ecx, ecx
1:  cmp rcx, [rip + g_nbs + VEC_len]
    jae 9f
    mov rax, [rip + g_nbs + VEC_ptr]
    mov rax, [rax + rcx*8]
    inc rcx
    xor edx, edx
2:  cmp rdx, [rax + NB_sent + VEC_len]
    jae 1b
    imul r8, rdx, NBS2_SIZE
    add r8, [rax + NB_sent + VEC_ptr]
    inc rdx
    cmp [r8 + NBS2_ext], rdi
    jne 2b
    mov qword ptr [r8 + NBS2_ext], 0
    jmp 2b
9:  ret


.text
# nb_focus_cell() -> the selected cell's DOC* while the active notebook is in edit mode (language
#   features work in it as in a tab), else 0
FN nb_focus_cell
    sub rsp, 8
    call nb_active
    test rax, rax
    jz 9f
    cmp dword ptr [rax + NB_editing], 0
    je 8f
    mov rax, [rip + g_doc]
    test rax, rax
    jz 9f
    test dword ptr [rax + DOC_flags], DF_CELL
    jnz 9f
8:  xor eax, eax
9:  add rsp, 8
    ret
