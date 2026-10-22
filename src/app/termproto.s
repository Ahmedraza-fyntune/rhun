# tasks and terminals: the "terminals" feature of protocol 1.1 (docs/extensions/v1.1.md, tasks design
# 3.4), and the terminal records the "tasks" feature (tasks.s) builds on. An extension with
# terminal = run opens terminals running programs it names, as the user, after the one approval per
# project (runallow.s); it stops, restarts, closes and shows them; with terminal = input it types
# into them, with output it reads their finished lines and their screen. A TERM is termview's id; an
# extension reaches only the terminals it opened or that run its tasks, in its current runtime. The
# user's own shells have no handle here.
#
#   termproto_request(ext, id, line, len, body, blen)  every terminal verb (extproto.s)
#   termproto_tick()                 output batches go out, within the rates of tasks design 3.6
#   termproto_timeout()              -> ms until it has output to send, or -1
#   termproto_ext_gone(ext)          its runtime stopped: its programs stop, their tabs stay
#   termproto_cancel(ext, id) -> 1 when that request's approval question was withdrawn (cancel ID)
#   tr_open(ext, DF*, kind) -> TR*, or 0 when every tab is taken: a program's tab of its own (tasks.s
#                                    sets TRC_mrun, TRC_hook and TRC_linefn after)
#   tr_send(ext, sb): an event to the extension when it is running
.include "rhun.inc"

.equ OUT_EVENT, 65536            # a terminal-output event's bytes at most
.equ OUT_PENDING, 65536          # a terminal's lines waiting at most (more are counted as dropped)
.equ OUT_EXT_RATE, 262144        # bytes a second for one extension
.equ OUT_ALL_RATE, 1048576       # and for all of them
.equ OUT_QUEUE, 524288           # none while the extension's queue holds more than this
.equ INPUT_MAX, 65536
.equ RATE_SLOTS, 64

.bss
.p2align 3
recs: .zero VEC_SIZE            # TR*
ob: .zero SB_SIZE               # the message being built
words: .zero 16 * 8             # the request line's words (ptr, len)
nwords: .quad 0
req_ext: .quad 0
req_id: .quad 0
# the terminal-open waiting for the approval dialog
park_ext: .quad 0
park_id: .quad 0
park_df: .quad 0
# output rates: the second they count, and bytes per extension in it
rate_t0: .quad 0
rate_all: .quad 0
rate_ext: .zero 16 * RATE_SLOTS  # EXT*, bytes
screen: .zero SB_SIZE

.text

# ---------------- messages ----------------

ob_begin:
    lea rdi, [rip + ob]
    jmp sb_clear
ob_cstr:
    mov rsi, rdi
    lea rdi, [rip + ob]
    jmp sb_push_cstr
ob_u64:
    mov rsi, rdi
    lea rdi, [rip + ob]
    jmp sb_push_u64
ob_byte:
    mov esi, edi
    lea rdi, [rip + ob]
    jmp sb_push_byte
ob_bytes:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + ob]
    jmp sb_push

# tr_send(ext, sb) -> 0 queued: the bytes to the extension while it runs
FN tr_send
    mov rdx, [rsi + SB_len]
    mov rsi, [rsi + SB_ptr]
    jmp ext_send_checked

# ob_send(ext)
ob_send:
    lea rsi, [rip + ob]
    jmp tr_send

# reply_ok(): "ok ID" to the request being served
reply_ok:
    sub rsp, 8
    call ob_begin
    lea rdi, [rip + .Lw_ok]
    call ob_cstr
    mov rdi, [rip + req_id]
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rip + req_ext]
    call ob_send
    add rsp, 8
    ret

# reply_ok_u64(value): "ok ID VALUE"
reply_ok_u64:
    push rbx
    mov rbx, rdi
    call ob_begin
    lea rdi, [rip + .Lw_ok]
    call ob_cstr
    mov rdi, [rip + req_id]
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, rbx
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rip + req_ext]
    call ob_send
    pop rbx
    ret

# reply_error(cstr "code text"), reply_error2(cstr, cstr): "error ID CODE TEXT" (the second string
#   follows the first)
reply_error:
    xor esi, esi
reply_error2:
    push rbx
    push r12
    push r12
    mov rbx, rdi
    mov r12, rsi
    call ob_begin
    lea rdi, [rip + .Lw_error]
    call ob_cstr
    mov rdi, [rip + req_id]
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, rbx
    call ob_cstr
    test r12, r12
    jz 1f
    mov rdi, r12
    call ob_cstr
1:  mov edi, 10
    call ob_byte
    mov rdi, [rip + req_ext]
    call ob_send
    pop r12
    pop r12
    pop rbx
    ret

# ---------------- the request line ----------------

# split(ptr, len) -> eax its words (at most 8; 9 for more) into words/nwords
split:
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + words]
1:  cmp rdx, rsi
    jae 9f
    cmp byte ptr [rdi + rdx], ' '
    jne 2f
    inc rdx
    jmp 1b
2:  cmp ecx, 8
    jae 8f
    lea rax, [rdi + rdx]
    mov [r8], rax
    mov r9, rdx
3:  cmp rdx, rsi
    jae 4f
    cmp byte ptr [rdi + rdx], ' '
    je 4f
    inc rdx
    jmp 3b
4:  mov rax, rdx
    sub rax, r9
    mov [r8 + 8], rax
    add r8, 16
    inc ecx
    jmp 1b
8:  mov ecx, 9
9:  mov [rip + nwords], rcx
    mov eax, ecx
    ret

# word_is(i, cstr) -> eax 1 when word i is that text
word_is:
    lea rax, [rip + words]
    shl rdi, 4
    mov rdx, rsi
    mov rsi, [rax + rdi + 8]
    mov rdi, [rax + rdi]
    jmp str_eq_cstr

# word_num(i) -> rax its decimal value, edx 1 when it is a number
word_num:
    lea rax, [rip + words]
    shl rdi, 4
    mov rsi, [rax + rdi + 8]
    mov rdi, [rax + rdi]
    xor edx, edx
    test rsi, rsi
    jz 9f
    cmp rsi, 19
    ja 9f
    push rdi
    push rsi
    call parse_u64
    pop rsi
    pop rdi
    cmp rdx, rsi                # every byte a digit
    sete dl
    movzx edx, dl
9:  ret

# ---------------- records ----------------

# tr_find_term(TERM) -> its TR*, or 0
FN tr_find_term
    mov rcx, [rip + recs + VEC_ptr]
    mov rdx, [rip + recs + VEC_len]
1:  test rdx, rdx
    jz 2f
    mov rax, [rcx]
    cmp [rax + TRC_term], rdi
    je 3f
    add rcx, 8
    dec rdx
    jmp 1b
2:  xor eax, eax
3:  ret

# tr_find_task(ext, task id cstr) -> the TR* of the tab that runs that task of the extension (in any
#   of its runtimes), or 0
FN tr_find_task
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + recs + VEC_len]
    jae 8f
    mov rax, [rip + recs + VEC_ptr]
    mov r14, [rax + rbx*8]
    inc rbx
    cmp [r14 + TRC_ext], r12
    jne 1b
    mov rdi, [r14 + TRC_task]
    test rdi, rdi
    jz 1b
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# tr_of(ext, TERM) -> the extension's TR* for that terminal in its current runtime, or 0
tr_of:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    call tr_find_term
    test rax, rax
    jz 9f
    cmp [rax + TRC_ext], rbx
    jne 8f
    cmp dword ptr [rax + TRC_live], 0
    jne 9f
8:  xor eax, eax
9:  pop rbx
    ret

# tr_set_output(TR*, DF*): terminal-output for it as the definition asks, only when its extension
#   may read terminals (terminal = output): a task's definition is checked as terminal-open's is
FN tr_set_output
    and dword ptr [rdi + TRC_flags], ~TRCF_OUTPUT
    cmp dword ptr [rsi + DF_output], 0
    je 9f
    mov rax, [rdi + TRC_ext]
    test dword ptr [rax + EXT_needs], NEEDS_TERM_OUTPUT
    jz 9f
    or dword ptr [rdi + TRC_flags], TRCF_OUTPUT
9:  ret

# tr_open(ext, DF*, kind) -> TR*, or 0 when every tab is taken
FN tr_open
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov edi, TRC_SIZE
    call mem_alloc
    mov r14, rax
    mov [r14 + TRC_ext], rbx
    mov dword ptr [r14 + TRC_live], 1
    mov rdi, r14
    mov rsi, r12
    call tr_set_output
    mov rax, [r12 + DF_id]
    cmp word ptr [rax], 0x002d  # "-": a terminal, no task
    je 2f
    mov rdi, rax
    call strlen
    mov rdi, [r12 + DF_id]
    mov rsi, rax
    call mem_dup
    mov [r14 + TRC_task], rax
2:  mov rdi, r12
    lea rsi, [rsp]
    call def_program
    # show, focus or silent
    mov edx, r13d
    mov eax, [r12 + DF_reveal]
    cmp eax, 1
    jne 3f
    or edx, TRV_FOCUS
3:  cmp eax, 2
    jne 4f
    or edx, TRV_SILENT
4:  lea rdi, [rsp]
    mov rsi, [r12 + DF_label]
    lea rcx, [rip + tr_event]
    mov r8, r14
    call term_run
    mov r15, rax
    mov rdi, [rsp + PGM_argv]
    call mem_free
    test r15, r15
    jle 8f
    mov [r14 + TRC_term], r15
    mov rdi, r15
    mov rsi, rbx
    mov rdx, [r14 + TRC_task]
    call term_set_owner
    mov rdi, r15
    lea rsi, [rip + tr_tap]
    mov rdx, r14
    call term_set_tap
    lea rdi, [rip + recs]
    mov esi, 8
    call vec_push
    mov [rax], r14
    mov rax, r14
    EPILOGUE
8:  mov rdi, [r14 + TRC_task]
    call mem_free
    mov rdi, r14
    call mem_free
    xor eax, eax
    EPILOGUE

# tr_free(TR*): out of the list, and what it holds
tr_free:
    PROLOGUE
    mov rbx, rdi
    xor ecx, ecx
1:  cmp rcx, [rip + recs + VEC_len]
    jae 3f
    mov rax, [rip + recs + VEC_ptr]
    cmp [rax + rcx*8], rbx
    je 2f
    inc rcx
    jmp 1b
2:  lea rdi, [rax + rcx*8]
    lea rsi, [rdi + 8]
    mov rdx, [rip + recs + VEC_len]
    sub rdx, rcx
    dec rdx
    shl rdx, 3
    call memmove
    dec qword ptr [rip + recs + VEC_len]
3:  mov rdi, [rbx + TRC_mrun]
    call mrun_free
    mov rdi, [rbx + TRC_df]
    test rdi, rdi
    jz 4f
    call tasks_df_release
4:
    mov rdi, [rbx + TRC_task]
    call mem_free
    lea rdi, [rbx + TRC_out]
    call sb_free
    mov rdi, rbx
    call mem_free
    EPILOGUE

# tr_live_for(TR*) -> eax 1 when its extension's runtime is the one that opened it and has the feature
tr_live_for:
    xor eax, eax
    cmp dword ptr [rdi + TRC_live], 0
    je 9f
    mov rcx, [rdi + TRC_ext]
    test rcx, rcx
    jz 9f
    FEAT_TEST rcx, FEAT_TERMINALS
    setnz al
    movzx eax, al
9:  ret

# tr_event(TR*, TERM, event, code): termview's news of the program: the extension hears it (output
#   that waited goes first), then its task run (TRC_hook); a closed tab's record goes
tr_event:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    cmp r13d, TE_STARTED
    je .Lte_started
    cmp r13d, TE_CLOSED
    je .Lte_closed
    # it ended
    mov rdi, rbx
    call out_flush
    mov rdi, rbx
    call tr_live_for
    test eax, eax
    jz 7f
    call ob_begin
    lea rdi, [rip + .Le_ended]
    call ob_cstr
    mov rdi, r12
    call ob_u64
    mov edi, ' '
    call ob_byte
    lea rax, [rip + end_words]
    mov rdi, [rax + r13*8]
    call ob_cstr
    mov edi, ' '
    call ob_byte
    cmp r13d, TE_FAILED
    jne 1f
    mov edi, '-'
    call ob_byte
    jmp 2f
1:  mov edi, r14d
    call ob_u64
2:  # the problems this run made
    xor eax, eax
    xor edx, edx
    mov rdi, [rbx + TRC_mrun]
    test rdi, rdi
    jz 3f
    call mrun_counts
3:  mov r15d, edx
    mov edi, ' '
    push rax
    push rax
    call ob_byte
    pop rdi
    pop rax
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov edi, r15d
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rbx + TRC_ext]
    call ob_send
    jmp 7f
.Lte_started:
    lea rdi, [rbx + TRC_out]
    call sb_clear
    mov qword ptr [rbx + TRC_dropped], 0
    mov rdi, rbx
    call tr_live_for
    test eax, eax
    jz 7f
    call ob_begin
    lea rdi, [rip + .Le_started]
    call ob_cstr
    mov rdi, r12
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov edi, r14d
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, [rbx + TRC_task]
    test rdi, rdi
    jnz 4f
    lea rdi, [rip + .Ldash]
4:  call ob_cstr
    mov edi, 10
    call ob_byte
    mov rdi, [rbx + TRC_ext]
    call ob_send
    jmp 7f
.Lte_closed:
    mov rdi, rbx
    call tr_live_for
    test eax, eax
    jz 6f
    call ob_begin
    lea rdi, [rip + .Le_closed]
    call ob_cstr
    mov rdi, r12
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rbx + TRC_ext]
    call ob_send
6:  mov rax, [rbx + TRC_hook]
    test rax, rax
    jz 61f
    mov rdi, [rbx + TRC_cookie]
    mov rsi, rbx
    mov edx, r13d
    mov ecx, r14d
    call rax
61: mov rdi, rbx
    call tr_free
    EPILOGUE
7:  mov rax, [rbx + TRC_hook]
    test rax, rax
    jz 9f
    mov rdi, [rbx + TRC_cookie]
    mov rsi, rbx
    mov edx, r13d
    mov ecx, r14d
    call rax
9:  EPILOGUE

# tr_tap(TR*, TERM, line, len): a finished line of its program: to its matchers, its task's ready and
#   busy patterns (TRC_linefn), and the extension's output batch; len -1: a run begins
tr_tap:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, [rbx + TRC_mrun]
    test rdi, rdi
    jz 1f
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call mrun_tap
1:  mov rax, [rbx + TRC_linefn]
    test rax, rax
    jz 2f
    mov rdi, [rbx + TRC_cookie]
    mov rsi, r13
    mov rdx, r14
    call rax
2:  cmp r14, -1
    je 9f
    test dword ptr [rbx + TRCF_OUTPUT + TRC_flags - TRCF_OUTPUT], TRCF_OUTPUT
    jz 9f
    # the line, as plain UTF-8 with its LF, while there is room
    mov rax, [rbx + TRC_out + SB_len]
    add rax, r14
    inc rax
    cmp rax, OUT_PENDING
    jbe 3f
    inc qword ptr [rbx + TRC_dropped]
    jmp 9f
3:  lea rdi, [rbx + TRC_out]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    lea rdi, [rbx + TRC_out]
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

# ---------------- output ----------------

# rate_slot(ext) -> rax its bytes-this-second counter (made when new), or 0 when the table is full
rate_slot:
    lea rax, [rip + rate_ext]
    mov ecx, RATE_SLOTS
1:  cmp [rax], rdi
    je 3f
    add rax, 16
    dec ecx
    jnz 1b
    lea rax, [rip + rate_ext]
    mov ecx, RATE_SLOTS
2:  cmp qword ptr [rax], 0
    je 4f
    add rax, 16
    dec ecx
    jnz 2b
    xor eax, eax
    ret
4:  mov [rax], rdi
    mov qword ptr [rax + 8], 0
3:  add rax, 8
    ret

# out_flush(TR*): its waiting lines in terminal-output events now, within the rates: what does not
#   fit is dropped and counted
out_flush:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + TRC_out + SB_len]
    test r12, r12
    jnz 1f
    cmp qword ptr [rbx + TRC_dropped], 0
    je 9f
1:  test dword ptr [rbx + TRC_flags], TRCF_OUTPUT
    jz 10f
    mov rdi, rbx
    call tr_live_for
    test eax, eax
    jz 10f
    # the extension reads what it got: none while its queue is long
    mov rax, [rbx + TRC_ext]
    mov rcx, [rax + EXT_wq + SB_len]
    sub rcx, [rax + EXT_wq_off]
    cmp rcx, OUT_QUEUE
    ja .Lof_drop
    # this second's budgets
    call time_ms
    mov rcx, rax
    sub rcx, [rip + rate_t0]
    cmp rcx, 1000
    jb 2f
    mov [rip + rate_t0], rax
    mov qword ptr [rip + rate_all], 0
    lea rdi, [rip + rate_ext]
    xor esi, esi
    mov edx, 16 * RATE_SLOTS
    call memset
2:  mov rdi, [rbx + TRC_ext]
    call rate_slot
    test rax, rax
    jz .Lof_drop
    mov r13, rax
    mov r14, OUT_EXT_RATE
    sub r14, [r13]
    mov rax, OUT_ALL_RATE
    sub rax, [rip + rate_all]
    cmp r14, rax
    cmovg r14, rax
    cmp r14, OUT_EVENT
    jbe 3f
    mov r14d, OUT_EVENT
3:  # whole lines that fit
    test r14, r14
    jle .Lof_drop
    mov r15, r12
    cmp r15, r14
    jbe 5f
    mov r15, r14
4:  test r15, r15
    jz .Lof_drop
    mov rax, [rbx + TRC_out + SB_ptr]
    cmp byte ptr [rax + r15 - 1], 10
    je 5f
    dec r15
    jmp 4b
5:  call ob_begin
    lea rdi, [rip + .Le_output]
    call ob_cstr
    mov rdi, [rbx + TRC_term]
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, [rbx + TRC_dropped]
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, r15
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rbx + TRC_out + SB_ptr]
    mov rsi, r15
    call ob_bytes
    mov rdi, [rbx + TRC_ext]
    call ob_send
    add [r13], r15
    add [rip + rate_all], r15
    mov qword ptr [rbx + TRC_dropped], 0
    # the rest waits for the next frame
    mov rdi, [rbx + TRC_out + SB_ptr]
    lea rsi, [rdi + r15]
    mov rdx, r12
    sub rdx, r15
    call memmove
    sub [rbx + TRC_out + SB_len], r15
    jmp 9f
.Lof_drop:
    # the lines that waited, counted
    mov rax, [rbx + TRC_out + SB_ptr]
    xor ecx, ecx
6:  cmp rcx, r12
    jae 7f
    cmp byte ptr [rax + rcx], 10
    jne 61f
    inc qword ptr [rbx + TRC_dropped]
61: inc rcx
    jmp 6b
7:
8:  lea rdi, [rbx + TRC_out]
    call sb_clear
9:  EPILOGUE
10: # nobody to tell: nothing waits, nothing is counted
    mov qword ptr [rbx + TRC_dropped], 0
    jmp 8b

# termproto_tick(): each terminal's waiting lines out, once a frame; lines dropped with nothing
#   waiting are told too (an event of no lines with their count) once the budgets allow
FN termproto_tick
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + recs + VEC_len]
    jae 9f
    mov rax, [rip + recs + VEC_ptr]
    mov rdi, [rax + rbx*8]
    inc rbx
    cmp qword ptr [rdi + TRC_out + SB_len], 0
    jne 2f
    cmp qword ptr [rdi + TRC_dropped], 0
    je 1b
2:  call out_flush
    jmp 1b
9:  EPILOGUE

# termproto_timeout() -> ms until termproto_tick has output to send (lines or a drop count waiting
#   for the next second's budget), or -1
FN termproto_timeout
    xor ecx, ecx
1:  cmp rcx, [rip + recs + VEC_len]
    jae 8f
    mov rax, [rip + recs + VEC_ptr]
    mov rdx, [rax + rcx*8]
    inc rcx
    cmp qword ptr [rdx + TRC_out + SB_len], 0
    jne 2f
    cmp qword ptr [rdx + TRC_dropped], 0
    je 1b
2:  mov eax, 50
    ret
8:  mov eax, -1
    ret

# ---------------- the extension's runtime ----------------

# termproto_ext_gone(ext): its runtime stopped: its running programs stop (their tabs stay), its
#   terminals are no longer its handles, a question asked for it goes
FN termproto_ext_gone
    PROLOGUE
    mov r12, rdi
    call tasks_ext_gone
    xor ebx, ebx
1:  cmp rbx, [rip + recs + VEC_len]
    jae 3f
    mov rax, [rip + recs + VEC_ptr]
    mov r13, [rax + rbx*8]
    inc rbx
    cmp [r13 + TRC_ext], r12
    jne 1b
    mov dword ptr [r13 + TRC_live], 0
    lea rdi, [r13 + TRC_out]
    call sb_clear
    mov rdi, [r13 + TRC_term]
    call term_stop
    jmp 1b
3:  cmp [rip + park_ext], r12
    jne 9f
    mov edi, 1
    call run_approve_cancel
    call park_clear
9:  EPILOGUE

# termproto_holds(ext) -> eax 1 while a program it started runs or waits to (or its start waits for
#   the dialog): such an extension is never idle (tasks design 4.9; extres.s idle = stop)
FN termproto_holds
    PROLOGUE
    mov r12, rdi
    cmp [rip + park_ext], r12
    je 8f
    xor ebx, ebx
1:  cmp rbx, [rip + recs + VEC_len]
    jae 7f
    mov rax, [rip + recs + VEC_ptr]
    mov r13, [rax + rbx*8]
    inc rbx
    cmp [r13 + TRC_ext], r12
    jne 1b
    cmp dword ptr [r13 + TRC_live], 0
    je 1b
    mov rdi, [r13 + TRC_term]
    call term_state
    test eax, eax
    jz 8f                       # running
    cmp eax, 5
    je 8f                       # waiting for its dependencies
    jmp 1b
7:  mov rdi, r12
    call tasks_holds            # a task-start or task-run waiting for the dialog
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# park_clear(): no terminal-open waits for the dialog
park_clear:
    sub rsp, 8
    mov rdi, [rip + park_df]
    call def_free
    xor eax, eax
    mov [rip + park_df], rax
    mov [rip + park_ext], rax
    mov [rip + park_id], rax
    add rsp, 8
    ret

# termproto_cancel(ext, id) -> 1 when that request waited for the approval dialog: it goes away,
#   answered cancelled
FN termproto_cancel
    push rbx
    push rdi
    push rsi
    call tasks_cancel           # a task-start or task-run waiting for the dialog
    pop rsi
    pop rdi
    test eax, eax
    jnz 9f
    xor eax, eax
    cmp [rip + park_ext], rdi
    jne 9f
    test rdi, rdi
    jz 9f
    cmp [rip + park_id], rsi
    jne 9f
    mov [rip + req_ext], rdi
    mov [rip + req_id], rsi
    mov edi, 1
    call run_approve_cancel
    call park_clear
    lea rdi, [rip + .Le_cancelled]
    call reply_error
    mov eax, 1
9:  pop rbx
    ret

# ---------------- requests ----------------

# termproto_request(ext, id, line, len, body, blen): a terminal verb
FN termproto_request
    PROLOGUE 16
    mov rbx, rdi
    mov [rip + req_ext], rdi
    mov [rip + req_id], rsi
    mov r12, r8                 # body
    mov r13, r9
    mov [rsp], rcx              # the line, for tasks.s
    mov [rsp + 8], rdx
    mov rdi, rdx
    mov rsi, rcx
    call split
    FEAT_TEST rbx, FEAT_TERMINALS
    jz .Lrq_unknown
    # tasks-set, task-start, task-run: tasks.s
    lea rax, [rip + words]
    mov rdi, [rax + 16]
    mov rsi, [rax + 24]
    cmp rsi, 4
    jbe 0f
    cmp dword ptr [rdi], 0x6b736174     # "task"
    jne 0f
    mov rdi, rbx
    mov rsi, [rip + req_id]
    mov rdx, [rsp + 8]
    mov rcx, [rsp]
    mov r8, r12
    mov r9, r13
    call tasks_request
    EPILOGUE
0:  mov edi, 1
    lea rsi, [rip + .Lv_open]
    call word_is
    test eax, eax
    jnz .Lrq_open
    mov edi, 1
    lea rsi, [rip + .Lv_input]
    call word_is
    test eax, eax
    jnz .Lrq_input
    mov edi, 1
    lea rsi, [rip + .Lv_screen]
    call word_is
    test eax, eax
    jnz .Lrq_screen
    # the rest name a terminal and need run: ID VERB TERM [show|focus]
    mov edi, NEEDS_TERM_RUN
    call need
    test eax, eax
    jz .Lrq_ret
    cmp qword ptr [rip + nwords], 3
    jb .Lrq_syntax
    mov edi, 2
    call word_num
    test edx, edx
    jz .Lrq_syntax
    mov rdi, rbx
    mov rsi, rax
    call tr_of
    test rax, rax
    jz .Lrq_noterm
    mov r14, rax
    mov edi, 1
    lea rsi, [rip + .Lv_show]
    call word_is
    test eax, eax
    jnz .Lrq_show
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov rdi, [r14 + TRC_term]
    mov edi, 1
    lea rsi, [rip + .Lv_stop]
    call word_is
    test eax, eax
    jz 1f
    mov rdi, [r14 + TRC_term]
    call term_stop
    jmp .Lrq_ok
1:  mov edi, 1
    lea rsi, [rip + .Lv_restart]
    call word_is
    test eax, eax
    jz 2f
    mov rdi, [r14 + TRC_term]
    call term_restart
    jmp .Lrq_ok
2:  mov edi, 1
    lea rsi, [rip + .Lv_close]
    call word_is
    test eax, eax
    jz .Lrq_unknown
    mov rdi, [r14 + TRC_term]
    call term_close             # its record goes with the tab (TE_CLOSED)
    jmp .Lrq_ok
.Lrq_show:
    cmp qword ptr [rip + nwords], 4
    jne .Lrq_syntax
    mov edi, 3
    lea rsi, [rip + .Lw_focus]
    call word_is
    mov r15d, eax
    test eax, eax
    jnz 3f
    mov edi, 3
    lea rsi, [rip + .Lw_show]
    call word_is
    test eax, eax
    jz .Lrq_syntax
3:  mov rdi, [r14 + TRC_term]
    mov esi, r15d
    call term_reveal
.Lrq_ok:
    call reply_ok
.Lrq_ret:
    EPILOGUE
.Lrq_open:
    # ID terminal-open LEN + definition
    mov edi, NEEDS_TERM_RUN
    call need
    test eax, eax
    jz .Lrq_ret
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov rdi, r12
    mov rsi, r13
    xor edx, edx
    call def_parse
    test rax, rax
    jz .Lrq_bad_def
    cmp rcx, r13
    jne .Lrq_trailing
    mov r14, rax
    cmp dword ptr [r14 + DF_output], 0
    je 4f
    mov edi, NEEDS_TERM_OUTPUT
    call need
    test eax, eax
    jz .Lrq_free_def
4:  # the one approval per extension and project, with the exact command
    lea rdi, [rip + screen]
    call sb_clear
    mov rdi, r14
    lea rsi, [rip + screen]
    call def_command
    lea rdi, [rip + screen]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + screen + SB_ptr]
    lea rdx, [rip + open_answer]
    mov ecx, 1
    call run_approve
    cmp eax, 1
    je 5f
    test eax, eax
    jnz .Lrq_busy_def
    mov [rip + park_ext], rbx
    mov rax, [rip + req_id]
    mov [rip + park_id], rax
    mov [rip + park_df], r14
    EPILOGUE                    # answered when the user is
5:  mov rdi, r14
    call open_now
    EPILOGUE
.Lrq_input:
    # ID terminal-input TERM LEN + bytes
    mov edi, NEEDS_TERM_INPUT
    call need
    test eax, eax
    jz .Lrq_ret
    cmp qword ptr [rip + nwords], 4
    jne .Lrq_syntax
    cmp r13, INPUT_MAX
    ja .Lrq_toobig
    mov edi, 2
    call word_num
    test edx, edx
    jz .Lrq_syntax
    mov rdi, rbx
    mov rsi, rax
    call tr_of
    test rax, rax
    jz .Lrq_noterm
    mov rdi, [rax + TRC_term]
    mov rsi, r12
    mov rdx, r13
    call term_input
    cmp eax, -2
    je .Lrq_busy
    jmp .Lrq_ok
.Lrq_screen:
    # ID terminal-screen TERM -> ok ID LEN + ROWS COLS CURSOR_ROW CURSOR_COL, then the rows
    mov edi, NEEDS_TERM_OUTPUT
    call need
    test eax, eax
    jz .Lrq_ret
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov edi, 2
    call word_num
    test edx, edx
    jz .Lrq_syntax
    mov rdi, rbx
    mov rsi, rax
    call tr_of
    test rax, rax
    jz .Lrq_noterm
    mov r14, rax
    lea rdi, [rip + screen]
    call sb_clear
    mov rdi, [r14 + TRC_term]
    lea rsi, [rip + screen]
    call term_screen
    call ob_begin
    lea rdi, [rip + .Lw_ok]
    call ob_cstr
    mov rdi, [rip + req_id]
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov rdi, [rip + screen + SB_len]
    call ob_u64
    mov edi, 10
    call ob_byte
    mov rdi, [rip + screen + SB_ptr]
    mov rsi, [rip + screen + SB_len]
    call ob_bytes
    mov rdi, rbx
    call ob_send
    EPILOGUE
.Lrq_bad_def:
    mov rsi, rdx
    lea rdi, [rip + .Le_syntax_def]
    call reply_error2
    call syntax_count
    EPILOGUE
.Lrq_trailing:
    mov rdi, rax
    call def_free
    lea rdi, [rip + .Le_trailing]
    call reply_error
    call syntax_count
    EPILOGUE
.Lrq_busy_def:
    mov rdi, r14
    call def_free
.Lrq_busy:
    lea rdi, [rip + .Le_busy]
    call reply_error
    EPILOGUE
.Lrq_free_def:
    mov rdi, r14
    call def_free
    EPILOGUE
.Lrq_toobig:
    lea rdi, [rip + .Le_toobig]
    call reply_error
    EPILOGUE
.Lrq_noterm:
    lea rdi, [rip + .Le_noterm]
    call reply_error
    EPILOGUE
.Lrq_unknown:
    lea rdi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lrq_syntax:
    lea rdi, [rip + .Le_syntax]
    call reply_error
    call syntax_count
    EPILOGUE

# syntax_count(): a syntax error counts toward the three in a row that stop a program (as v1's)
syntax_count:
    mov rax, [rip + req_ext]
    inc dword ptr [rax + EXT_syntax_errs]
    ret

# need(bit) -> eax 1 when the extension being served has it, else 0 and "needs terminal=LEVEL" sent
need:
    mov rax, [rip + req_ext]
    test [rax + EXT_needs], edi
    jz 1f
    mov eax, 1
    ret
1:  lea rax, [rip + .Le_needs_run]
    cmp edi, NEEDS_TERM_INPUT
    jne 2f
    lea rax, [rip + .Le_needs_input]
2:  cmp edi, NEEDS_TERM_OUTPUT
    jne 3f
    lea rax, [rip + .Le_needs_output]
3:  sub rsp, 8
    mov rdi, rax
    call reply_error
    add rsp, 8
    xor eax, eax
    ret

# open_now(DF*): the terminal-open being served starts, answered "ok ID TERM"; the DF goes
open_now:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rip + req_ext]
    mov rsi, rbx
    mov edx, TK_TERMINAL
    call tr_open
    mov r12, rax
    mov rdi, rbx
    call def_free
    test r12, r12
    jz 8f
    mov rdi, [r12 + TRC_term]
    call reply_ok_u64
    EPILOGUE
8:  lea rdi, [rip + .Le_busy_tabs]
    call reply_error
    EPILOGUE

# open_answer(cookie, allowed): the user answered the approval for the parked terminal-open
open_answer:
    PROLOGUE
    mov rax, [rip + park_ext]
    test rax, rax
    jz 9f
    mov [rip + req_ext], rax
    mov rax, [rip + park_id]
    mov [rip + req_id], rax
    mov rbx, [rip + park_df]
    mov qword ptr [rip + park_df], 0
    mov qword ptr [rip + park_ext], 0
    test esi, esi
    jz 1f
    mov rdi, rbx
    call open_now
    jmp 9f
1:  mov rdi, rbx
    call def_free
    lea rdi, [rip + .Le_cancelled]
    call reply_error
9:  EPILOGUE

# termproto_dump(sb): a line per terminal record (print-terminal-records): "TERM ext=OWNER/NAME
#   live=0|1 output=0|1 task=ID|-"
FN termproto_dump
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + recs + VEC_len]
    jae 9f
    mov rax, [rip + recs + VEC_ptr]
    mov r13, [rax + rbx*8]
    inc rbx
    mov rdi, r12
    mov rsi, [r13 + TRC_term]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_ext]
    call sb_push_cstr
    mov rdi, [r13 + TRC_ext]
    call ext_full_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_live]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r13 + TRC_live]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_output]
    call sb_push_cstr
    mov eax, [r13 + TRC_flags]
    and eax, TRCF_OUTPUT
    mov rdi, r12
    mov esi, eax
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_task]
    call sb_push_cstr
    mov rsi, [r13 + TRC_task]
    test rsi, rsi
    jnz 2f
    lea rsi, [rip + .Ldash]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lw_ok: .asciz "ok "
.Lw_error: .asciz "error "
.Lw_show: .asciz "show"
.Lw_focus: .asciz "focus"
.Ldash: .asciz "-"
.Lv_open: .asciz "terminal-open"
.Lv_stop: .asciz "terminal-stop"
.Lv_restart: .asciz "terminal-restart"
.Lv_close: .asciz "terminal-close"
.Lv_show: .asciz "terminal-show"
.Lv_input: .asciz "terminal-input"
.Lv_screen: .asciz "terminal-screen"
.Le_started: .asciz "0 terminal-started "
.Le_ended: .asciz "0 terminal-ended "
.Le_output: .asciz "0 terminal-output "
.Le_closed: .asciz "0 terminal-closed "
.Le_unknown: .asciz "unknown no such request"
.Le_syntax: .asciz "syntax"
.Le_syntax_def: .asciz "syntax definition: "
.Le_trailing: .asciz "syntax definition: bytes after it"
.Le_busy: .asciz "busy"
.Le_busy_tabs: .asciz "busy every terminal tab is taken"
.Le_toobig: .asciz "toobig 65536 bytes"
.Le_noterm: .asciz "noterm no such terminal"
.Le_cancelled: .asciz "cancelled"
.Le_needs_run: .asciz "needs terminal=run"
.Le_needs_input: .asciz "needs terminal=input"
.Le_needs_output: .asciz "needs terminal=output"
.Lw_exit: .asciz "exit"
.Lw_stopped: .asciz "stopped"
.Lw_failed: .asciz "failed"
.Ld_ext: .asciz " ext="
.Ld_live: .asciz " live="
.Ld_output: .asciz " output="
.Ld_task: .asciz " task="
.p2align 3
end_words: .quad .Lw_exit, .Lw_stopped, .Lw_failed
