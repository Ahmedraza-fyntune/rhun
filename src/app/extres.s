# Extension lifecycle and cost (parity 4m): what rhun keeps beside each extension for its page
# and for `idle = stop`. Messages and bytes each way, how the requests rhun asked were answered
# (slow, dropped, failed), CPU and memory of its processes, when it started and how long hello
# took. An EL row sits beside each EXT slot: g_exts never moves and a slot is never reused (a
# reinstall is a new record), so the slot names the extension for the session.
#
# Also here: the manifest keys of the resources group (idle, idle.after, runs, contains:,
# [provides] schemes), startup pacing (EXT_STARTS_PER_FRAME), and the headless commands of the
# group (res_control, called by control.s for the names it does not know).
.include "rhun.inc"

.bss
.p2align 3
el_rows: .zero EL_SIZE * EXT_CAP
el_t0: .quad 0                  # time_ms at ext_init: the session's start
el_first_frame: .quad 0         # ms from el_t0 to the first extension tick (the first frame)
el_ready: .quad 0               # ms from el_t0 to the last on = startup hello so far
el_slowest_ext: .quad 0         # the on = startup extension slowest to say hello, and its ms
el_slowest_ms: .quad 0
el_idle_t: .quad 0              # time_ms of the last idle pass
el_page_t: .quad 0              # time_ms the Extensions page was last drawn
el_sample_t: .quad 0            # time_ms of the last CPU and memory samples
el_usage: .zero 32              # proc_usage's answer: CPU ns, resident bytes, processes
el_frame_starts: .long 0        # extensions started this frame
el_scale: .long 0               # RHUN_IDLE_SCALE in a --extensions session, else 1; 0 unread
el_num: .zero 32

.text

# extres_row(ext) -> rax its EL row, or 0 for a record that is not an EXT slot (a preview)
FN extres_row
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    test rdx, rdx
    jnz 8f
    cmp rax, EXT_CAP
    jae 8f
    imul rax, rax, EL_SIZE
    lea rcx, [rip + el_rows]
    add rax, rcx
    ret
8:  xor eax, eax
    ret

# extres_ext(row) -> the EXT beside an EL row
FN extres_ext
    mov rax, rdi
    lea rcx, [rip + el_rows]
    sub rax, rcx
    xor edx, edx
    mov ecx, EL_SIZE
    div rcx
    imul rax, rax, EXT_SIZE
    add rax, [rip + g_exts + VEC_ptr]
    ret

# extres_init(): the session's start (ext_init)
FN extres_init
    push rax
    call time_ms
    mov [rip + el_t0], rax
    pop rax
    ret

# ---------------- counters ----------------

# extres_in(ext, bytes, messages): what the extension wrote
FN extres_in
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call extres_row
    test rax, rax
    jz 9f
    mov rbx, rax
    add [rbx + EL_bytes_in], r12
    add [rbx + EL_msgs_in], r13
    call time_ms
    mov [rbx + EL_last_work], rax
9:  EPILOGUE

# extres_out(ext, bytes): a message rhun queued for it
FN extres_out
    PROLOGUE
    mov r12, rsi
    call extres_row
    test rax, rax
    jz 9f
    mov rbx, rax
    add [rbx + EL_bytes_out], r12
    inc qword ptr [rbx + EL_msgs_out]
    call time_ms
    mov [rbx + EL_last_work], rax
9:  EPILOGUE

# kind_of(verb ptr, len) -> rax its kinds entry (name cstr, slow threshold in ms)
kind_of:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + kinds]
1:  cmp qword ptr [rbx], 0
    je 8f
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    add rbx, 24
    jmp 1b
8:  lea rbx, [rip + kind_other]
9:  mov rax, rbx
    EPILOGUE

# extres_req_sent(ext, id, verb ptr, verb len): rhun asked the extension something
FN extres_req_sent
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call extres_row
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, r13
    mov rsi, r14
    call kind_of
    mov r15, rax
    mov ecx, [rbx + EL_nreq]
    cmp ecx, ELQ_MAX
    jb 1f
    # full: the oldest is forgotten (an answer to it counts as dropped)
    lea rdi, [rbx + EL_req]
    lea rsi, [rbx + EL_req + ELQ_SIZE]
    mov edx, ELQ_SIZE * (ELQ_MAX - 1)
    call memmove
    mov ecx, ELQ_MAX - 1
    mov [rbx + EL_nreq], ecx
1:  imul rax, rcx, ELQ_SIZE
    lea r13, [rbx + EL_req + rax]
    mov [r13 + ELQ_id], r12
    mov [r13 + ELQ_kind], r15
    mov qword ptr [r13 + ELQ_cancelled], 0
    call time_ms
    mov [r13 + ELQ_t], rax
    inc dword ptr [rbx + EL_nreq]
9:  EPILOGUE

# req_find(row, id) -> rax the index of the request, or -1
req_find:
    xor eax, eax
1:  cmp eax, [rdi + EL_nreq]
    jae 8f
    imul rcx, rax, ELQ_SIZE
    cmp [rdi + EL_req + rcx + ELQ_id], rsi
    je 9f
    inc eax
    jmp 1b
8:  mov rax, -1
9:  ret

# req_remove(row, index): the entries after it move down
req_remove:
    PROLOGUE
    mov rbx, rdi
    mov ecx, [rbx + EL_nreq]
    dec ecx
    mov [rbx + EL_nreq], ecx
    sub ecx, esi
    imul rdx, rcx, ELQ_SIZE
    imul rax, rsi, ELQ_SIZE
    lea rdi, [rbx + EL_req + rax]
    lea rsi, [rdi + ELQ_SIZE]
    call memmove
    EPILOGUE

# extres_req_cancel(ext, id): rhun sent 0 cancel ID
FN extres_req_cancel
    PROLOGUE
    mov r12, rsi
    call extres_row
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, r12
    mov rbx, rax
    call req_find
    test rax, rax
    js 9f
    imul rax, rax, ELQ_SIZE
    mov qword ptr [rbx + EL_req + rax + ELQ_cancelled], 1
9:  EPILOGUE

# extres_req_answer(ext, id, how): an answer arrived; how 1 ok, 0 an error, 2 error cancelled.
# Slow: after the kind's threshold; dropped: after rhun cancelled it, gave up on it (5 s) or
# forgot it; failed: an error other than cancelled.
FN extres_req_answer
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    call extres_row
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    call req_find
    test rax, rax
    js .Lra_dropped
    mov r15, rax
    imul rax, rax, ELQ_SIZE
    lea r14, [rbx + EL_req + rax]
    cmp qword ptr [r14 + ELQ_cancelled], 0
    jne .Lra_dropped_remove
    call time_ms
    sub rax, [r14 + ELQ_t]
    cmp rax, 5000
    jae .Lra_dropped_remove
    mov rcx, [r14 + ELQ_kind]
    cmp rax, [rcx + 8]
    jb 1f
    inc dword ptr [rbx + EL_slow]
1:  cmp eax, [rbx + EL_slowest_ms]
    jbe 2f
    mov [rbx + EL_slowest_ms], eax
    mov [rbx + EL_slowest], rcx
2:  test r13d, r13d
    jnz .Lra_remove
    inc dword ptr [rbx + EL_failed]
    jmp .Lra_remove
.Lra_dropped_remove:
    inc dword ptr [rbx + EL_dropped]
.Lra_remove:
    mov rdi, rbx
    mov rsi, r15
    call req_remove
    EPILOGUE
.Lra_dropped:
    inc dword ptr [rbx + EL_dropped]
9:  EPILOGUE

# expire(row, now): requests nobody answered for 10 s are dropped (their modules gave up)
expire:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13d, [rbx + EL_nreq]
    jae 9f
    imul rax, r13, ELQ_SIZE
    mov rcx, r12
    sub rcx, [rbx + EL_req + rax + ELQ_t]
    cmp rcx, 10000
    jb 2f
    inc dword ptr [rbx + EL_dropped]
    mov rdi, rbx
    mov rsi, r13
    call req_remove
    jmp 1b
2:  inc r13d
    jmp 1b
9:  EPILOGUE

# ---------------- starts and stops ----------------

# extres_started(ext): its program was spawned (ES_STARTING)
FN extres_started
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    mov r12, rax
    inc dword ptr [rip + el_frame_starts]
    inc dword ptr [r12 + EL_starts]
    call time_ms
    mov [r12 + EL_start_t], rax
    mov [r12 + EL_last_work], rax
    mov dword ptr [r12 + EL_busy], 0
    mov dword ptr [r12 + EL_nreq], 0
    mov qword ptr [r12 + EL_cpu_t], 0
    mov qword ptr [r12 + EL_cpu0_t], 0
    mov qword ptr [r12 + EL_cpu_ns], 0
    mov qword ptr [r12 + EL_cpu0_ns], 0
    mov qword ptr [r12 + EL_rss], 0
    mov dword ptr [r12 + EL_procs], 0
    and dword ptr [r12 + EL_flags], ~ELF_IDLE_STOPPING
9:  EPILOGUE

# extres_hello(ext): hello arrived
FN extres_hello
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    mov r12, rax
    call time_ms
    mov r13, rax
    mov rcx, rax
    sub rcx, [r12 + EL_start_t]
    mov [r12 + EL_ready_ms], ecx
    test dword ptr [r12 + EL_flags], ELF_STARTUP
    jz 9f
    and dword ptr [r12 + EL_flags], ~ELF_STARTUP
    mov rax, r13
    sub rax, [rip + el_t0]
    cmp rax, [rip + el_ready]
    jbe 1f
    mov [rip + el_ready], rax
1:  mov ecx, [r12 + EL_ready_ms]
    cmp rcx, [rip + el_slowest_ms]
    jb 9f
    mov [rip + el_slowest_ms], rcx
    mov [rip + el_slowest_ext], rbx
9:  EPILOGUE

# extres_exited(ext): its program is gone; what this run held goes with it
FN extres_exited
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    mov qword ptr [rax + EL_start_t], 0
    mov dword ptr [rax + EL_nreq], 0
    mov dword ptr [rax + EL_busy], 0
    mov dword ptr [rax + EL_procs], 0
    mov qword ptr [rax + EL_rss], 0
    mov rdi, rbx
    call vdoc_ext_exited        # the virtual documents waiting for it say so
    mov rdi, rbx
    call links_ext_exited       # and its links will not be taken
    mov rdi, rbx
    call filesearch_ext_gone    # nor its finds and searches answered
9:  EPILOGUE

# extres_stopped(ext) -> eax 1 when the stop that ended it was for idleness: it is idle again
# (ES_IDLE, reason "idle"), so its next command, provider request or activation starts it
FN extres_stopped
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 8f
    test dword ptr [rax + EL_flags], ELF_IDLE_STOPPING
    jz 8f
    and dword ptr [rax + EL_flags], ~ELF_IDLE_STOPPING
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    cmp dword ptr [rbx + EXT_restart], 0
    jne 8f
    mov dword ptr [rbx + EXT_status], ES_IDLE
    lea rax, [rip + .Lr_idle]
    mov [rbx + EXT_reason], rax
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# extres_pace(ext, startup) -> eax 1 when it may start in this frame. At most
# EXT_STARTS_PER_FRAME start a frame for on = startup and the extensions waiting for a turn; one
# that may not waits with EXT_wait_slot (ext_tick starts it in a later frame). startup marks an
# on = startup start for print-startup.
FN extres_pace
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call extres_row
    test rax, rax
    jz 1f
    test r12d, r12d
    jz 1f
    or dword ptr [rax + EL_flags], ELF_STARTUP
1:  cmp dword ptr [rip + el_frame_starts], EXT_STARTS_PER_FRAME
    jb 9f
    mov dword ptr [rbx + EXT_wait_slot], 1
    xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# ---------------- idle = stop ----------------

# idle_ms(row) -> rax how long without work stops it
idle_ms:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + el_scale], 0
    jne 1f
    mov dword ptr [rip + el_scale], 1
    cmp qword ptr [rip + g_ext_dir], 0
    je 1f                       # the test hook works in --extensions sessions only
    lea rdi, [rip + .Lenv_scale]
    call getenv
    test rax, rax
    jz 1f
    mov r12, rax
    mov rdi, rax
    call strlen
    mov rdi, r12
    mov rsi, rax
    call parse_u64
    test rax, rax
    jz 1f
    cmp rax, 100000
    ja 1f
    mov [rip + el_scale], eax
1:  mov eax, [rbx + EL_idle_cfg]
    test eax, eax
    jnz 2f
    mov eax, IDLE_AFTER_DEFAULT
2:  imul rax, rax, 1000
    mov ecx, [rip + el_scale]
    xor edx, edx
    div rcx
    EPILOGUE

# idle_held(ext, row) -> eax 1 while it holds something the user sees or waits for: busy yes,
# status text, a command waiting for it, its prompt, a view, diagnostics marks, a request either
# way
idle_held:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [r12 + EL_busy], 0
    jne 8f
    cmp qword ptr [rbx + EXT_status_text], 0
    jne 8f
    cmp qword ptr [rbx + EXT_pending], 0
    jne 8f
    xor ecx, ecx
1:  cmp ecx, [r12 + EL_nreq]
    jae 2f
    imul rax, rcx, ELQ_SIZE
    inc ecx
    cmp qword ptr [r12 + EL_req + rax + ELQ_cancelled], 0
    je 8f
    jmp 1b
2:  call extproto_prompt_owner
    cmp rax, rbx
    je 8f
    # its views
    lea rax, [rip + g_views]
    mov ecx, VW_MAX
3:  cmp [rax + VW_ext], rbx
    je 8f
    add rax, VW_SIZE
    dec ecx
    jnz 3b
    # its marks on open documents
    xor r13d, r13d
4:  cmp r13, [rip + g_tabs + VEC_len]
    jae 6f
    imul rax, r13, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r13
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 4b
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 4b
    mov rdx, [rax + DOC_xmarks]
    test rdx, rdx
    jz 4b
    xor ecx, ecx
5:  cmp rcx, [rdx + VEC_len]
    jae 4b
    imul rax, rcx, MK_SIZE
    add rax, [rdx + VEC_ptr]
    inc rcx
    cmp [rax + MK_owner], rbx
    je 8f
    jmp 5b
6:  # what the other parts of this group hold for it
    mov rdi, rbx
    call extres_group_holds
    test eax, eax
    jnz 8f
    xor eax, eax
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# extres_group_holds(ext) -> eax 1 while a secret request, a pending link or a search of it runs
# (the parts of the group add their checks here as they arrive)
FN extres_group_holds
    push rdi
    push rdi
    call secrets_pending
    pop rdi
    pop rdi
    test eax, eax
    jnz 9f
    push rdi
    push rdi
    call links_pending
    pop rdi
    pop rdi
    test eax, eax
    jnz 9f
    jmp filesearch_pending
9:  ret

# idle_pass(): once a second: requests nobody answers, and idle = stop extensions quiet for
# their period that hold nothing
idle_pass:
    PROLOGUE
    call time_ms
    mov r15, rax
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    imul r12, r13, EL_SIZE
    lea rax, [rip + el_rows]
    add r12, rax
    inc r13
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, r12
    mov rsi, r15
    call expire
    test dword ptr [r12 + EL_flags], ELF_IDLE
    jz 1b
    test dword ptr [r12 + EL_flags], ELF_IDLE_STOPPING
    jnz 1b
    mov rdi, r12
    call idle_ms
    mov rcx, r15
    sub rcx, [r12 + EL_last_work]
    cmp rcx, rax
    jb 1b
    mov rdi, rbx
    mov rsi, r12
    call idle_held
    test eax, eax
    jnz 1b
    or dword ptr [r12 + EL_flags], ELF_IDLE_STOPPING
    mov rdi, rbx
    lea rsi, [rip + .Lr_idle]
    call ext_stop
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
9:  EPILOGUE

# extres_busy(ext, on): busy yes|no from the idle feature
FN extres_busy
    PROLOGUE
    mov r12d, esi
    call extres_row
    test rax, rax
    jz 9f
    mov [rax + EL_busy], r12d
9:  EPILOGUE

# ---------------- the frame ----------------

# extres_frame(): at the start of each ext_tick
FN extres_frame
    PROLOGUE
    mov dword ptr [rip + el_frame_starts], 0
    call extconfig_poll         # the project files' settings (extconfig.s)
    call time_ms
    mov r12, rax
    cmp qword ptr [rip + el_first_frame], 0
    jne 1f
    mov rcx, rax
    sub rcx, [rip + el_t0]
    jnz 0f
    inc rcx
0:  mov [rip + el_first_frame], rcx
1:  mov rax, r12
    sub rax, [rip + el_idle_t]
    cmp rax, 1000
    jb 2f
    mov [rip + el_idle_t], r12
    call idle_pass
    call links_expire
2:  # every 2 s while the Extensions page shows: CPU and memory
    mov rax, r12
    sub rax, [rip + el_page_t]
    cmp rax, 3000
    jae 9f
    mov rax, r12
    sub rax, [rip + el_sample_t]
    cmp rax, 2000
    jb 9f
    mov [rip + el_sample_t], r12
    call sample_all
    mov dword ptr [rip + g_dirty], 1
9:  call vdoc_tick              # virtual documents waiting for their providers
    call filesearch_tick        # finds and searches of extensions
    EPILOGUE

# extres_timeout() -> rax the time (time_ms) the loop must come back for idleness and samples,
# or -1
FN extres_timeout
    PROLOGUE
    mov r12, -1
    xor r13d, r13d
1:  cmp r13, [rip + g_exts + VEC_len]
    jae 3f
    imul rbx, r13, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    imul rcx, r13, EL_SIZE
    lea rax, [rip + el_rows]
    add rcx, rax
    inc r13
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    cmp dword ptr [rcx + EL_nreq], 0
    jne 2f
    test dword ptr [rcx + EL_flags], ELF_IDLE
    jz 1b
2:  mov r12, [rip + el_idle_t]
    add r12, 1000
3:  call vdoc_waiting           # a virtual document waits: back in 100 ms
    test eax, eax
    jz 31f
    call time_ms
    add rax, 100
    cmp r12, -1
    je 30f
    cmp rax, r12
    jae 31f
30: mov r12, rax
31: call filesearch_timeout     # finds and searches: now, or in 10 ms
    test eax, eax
    js 32f
    mov r13d, eax
    call time_ms
    add rax, r13
    cmp r12, -1
    je 33f
    cmp rax, r12
    jae 32f
33: mov r12, rax
32: call time_ms
    sub rax, [rip + el_page_t]
    cmp rax, 3000
    jae 9f
    mov rax, [rip + el_sample_t]
    add rax, 2000
    cmp r12, -1
    je 4f
    cmp rax, r12
    jae 9f
4:  mov r12, rax
9:  mov rax, r12
    EPILOGUE

# extres_page_seen(): the Extensions page is being drawn (samples are taken while it shows)
FN extres_page_seen
    push rax
    call time_ms
    mov [rip + el_page_t], rax
    pop rax
    ret

# sample(ext): CPU and memory of a running extension's processes
sample:
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    mov r12, rax
    mov edi, [rbx + EXT_pid]
    test edi, edi
    jle 9f
    lea rsi, [rip + el_usage]
    call proc_usage
    test rax, rax
    js 9f
    call time_ms
    mov r13, rax
    # the older sample: the first one, or the last one once 10 s passed since it
    cmp qword ptr [r12 + EL_cpu0_t], 0
    je 1f
    mov rcx, r13
    sub rcx, [r12 + EL_cpu0_t]
    cmp rcx, 10000
    jb 2f
    mov rax, [r12 + EL_cpu_ns]
    mov [r12 + EL_cpu0_ns], rax
    mov rax, [r12 + EL_cpu_t]
    mov [r12 + EL_cpu0_t], rax
    jmp 2f
1:  mov rax, [rip + el_usage]
    mov [r12 + EL_cpu0_ns], rax
    mov [r12 + EL_cpu0_t], r13
2:  mov rax, [rip + el_usage]
    mov [r12 + EL_cpu_ns], rax
    mov [r12 + EL_cpu_t], r13
    mov rax, [rip + el_usage + 8]
    mov [r12 + EL_rss], rax
    mov eax, [rip + el_usage + 16]
    mov [r12 + EL_procs], eax
9:  EPILOGUE

sample_all:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 2f
    cmp eax, ES_STARTING
    jne 1b
2:  mov rdi, rbx
    call sample
    jmp 1b
9:  EPILOGUE

# cpu_tenths(row) -> rax CPU use now in tenths of a percent (between the two samples)
cpu_tenths:
    mov rcx, [rdi + EL_cpu_t]
    sub rcx, [rdi + EL_cpu0_t]
    jbe 8f
    mov rax, [rdi + EL_cpu_ns]
    sub rax, [rdi + EL_cpu0_ns]
    jb 8f
    imul rcx, rcx, 1000
    xor edx, edx
    div rcx
    ret
8:  xor eax, eax
    ret

# ---------------- the manifest ----------------

# extres_manifest_kv(ini, ext): the keys of this group, before ext.s reads the line as usual:
# idle, idle.after, runs, on = contains:NAME, [provides] schemes
FN extres_manifest_kv
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    mov rdi, rbx
    call extres_row
    test rax, rax
    jz 9f
    mov r13, rax
    cmp qword ptr [r12 + INI_seclen], 0
    jne .Lmk_sections
    mov rdi, r12
    lea rsi, [rip + .Lk_idle]
    call ini_key_is
    test eax, eax
    jz 1f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + .Lv_stop]
    call str_eq_cstr
    and dword ptr [r13 + EL_flags], ~ELF_IDLE
    test eax, eax
    jz 9f
    or dword ptr [r13 + EL_flags], ELF_IDLE
    jmp 9f
1:  mov rdi, r12
    lea rsi, [rip + .Lk_idle_after]
    call ini_key_is
    test eax, eax
    jz 2f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call parse_u64
    cmp rdx, [r12 + INI_vallen]
    jne 9f
    test rdx, rdx
    jz 9f
    cmp rax, 10                 # 10 s to a day; anything else keeps the default
    jb 9f
    cmp rax, 86400
    ja 9f
    mov [r13 + EL_idle_cfg], eax
    jmp 9f
2:  mov rdi, r12
    lea rsi, [rip + .Lk_runs]
    call ini_key_is
    test eax, eax
    jz 3f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + .Lv_local]
    call str_eq_cstr
    and dword ptr [r13 + EL_flags], ~ELF_RUNS_LOCAL
    test eax, eax
    jz 9f
    or dword ptr [r13 + EL_flags], ELF_RUNS_LOCAL
    jmp 9f
3:  mov rdi, r12
    lea rsi, [rip + .Lk_on]
    call ini_key_is
    test eax, eax
    jz 9f
    # contains:NAME words collect into EL_contains
    mov r14, [r12 + INI_val]
    mov r15, [r12 + INI_vallen]
31: test r15, r15
    jz 9f
    mov rdi, r14
    mov rsi, r15
    call next_word
    add r14, rcx
    sub r15, rcx
    test rdx, rdx
    jz 9f
    cmp rdx, 9
    jbe 31b
    push rax
    push rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lo_contains]
    mov ecx, 9
    call str_starts
    pop rdx
    pop rsi
    test eax, eax
    jz 31b
    add rsi, 9
    sub rdx, 9
    lea rdi, [r13 + EL_contains]
    call words_append
    or dword ptr [rbx + EXT_on], ON_CONTAINS
    jmp 31b
.Lmk_sections:
    mov rdi, r12
    lea rsi, [rip + .Ls_provides]
    call ini_sec_is
    test eax, eax
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Lk_schemes]
    call ini_key_is
    test eax, eax
    jz 9f
    mov rdi, [r13 + EL_schemes]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call mem_dup
    mov [r13 + EL_schemes], rax
9:  EPILOGUE

# words_append(slot*, ptr, len): "a b" lists kept as owned cstrs
FN words_append
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rbx]
    xor r14d, r14d
    test rdi, rdi
    jz 1f
    call strlen
    mov r14, rax
1:  lea rdi, [r14 + r13 + 2]
    call mem_alloc
    mov r15, rax
    mov rsi, [rbx]
    test rsi, rsi
    jz 2f
    mov rdi, r15
    mov rdx, r14
    call memcpy
    mov byte ptr [r15 + r14], ' '
    inc r14
2:  lea rdi, [r15 + r14]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add r14, r13
    mov byte ptr [r15 + r14], 0
    mov rdi, [rbx]
    call mem_free
    mov [rbx], r15
    EPILOGUE

# extres_idle_secs(ext) -> rax the seconds without work that stop it, 0 when it keeps running
FN extres_idle_secs
    call extres_row
    test rax, rax
    jz 8f
    test dword ptr [rax + EL_flags], ELF_IDLE
    jz 8f
    mov eax, [rax + EL_idle_cfg]
    test eax, eax
    jnz 9f
    mov eax, IDLE_AFTER_DEFAULT
9:  ret
8:  xor eax, eax
    ret

# ---------------- the user's choices for it (extensions.ini) ----------------

# FN extres_choice(ini, ext) -> eax 1 when the key was the group's: open_urls = yes
FN extres_choice
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    mov rdi, r12
    lea rsi, [rip + .Lk_open_urls]
    call ini_key_is
    test eax, eax
    jz 8f
    mov rdi, rbx
    call extres_row
    test rax, rax
    jz 9f
    mov r13, rax
    and dword ptr [r13 + EL_flags], ~ELF_OPEN_URLS
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    lea rdx, [rip + .Lv_yes]
    call str_eq_cstr
    test eax, eax
    jz 9f
    or dword ptr [r13 + EL_flags], ELF_OPEN_URLS
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extres_choices_write(ext, sb, write) -> eax 1 when the extension has choices of the group
# to keep; with write 1 their lines go onto sb
FN extres_choices_write
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call extres_row
    test rax, rax
    jz 8f
    test dword ptr [rax + EL_flags], ELF_OPEN_URLS
    jz 8f
    test r13d, r13d
    jz 9f
    mov rdi, r12
    lea rsi, [rip + .Lw_open_urls]
    call sb_push_cstr
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN extres_open_urls_revoke(ext): its page's switch: it asks before opening links again
FN extres_open_urls_revoke
    PROLOGUE
    call extres_row
    test rax, rax
    jz 9f
    and dword ptr [rax + EL_flags], ~ELF_OPEN_URLS
    call ext_settings_save
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# ---------------- words for the page ----------------

# push_commas(sb, n): 3,812
push_commas:
    PROLOGUE 32
    mov rbx, rdi
    lea rdi, [rsp]
    call fmt_u64
    mov r12, rax                # digits
    xor r13d, r13d
1:  cmp r13, r12
    jae 9f
    test r13, r13
    jz 2f
    mov rax, r12
    sub rax, r13
    xor edx, edx
    mov ecx, 3
    div rcx
    test rdx, rdx
    jnz 2f
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
2:  mov rdi, rbx
    movzx esi, byte ptr [rsp + r13]
    call sb_push_byte
    inc r13
    jmp 1b
9:  EPILOGUE

# push_tenths(sb, n): n / 10 with one decimal ("2.4"), without it from 100 ("12")
push_tenths:
    PROLOGUE
    mov rbx, rdi
    mov rax, rsi
    xor edx, edx
    mov ecx, 10
    div rcx
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rax
    cmp rax, 10
    jae 1f
    call sb_push_u64
    mov rdi, rbx
    mov esi, '.'
    call sb_push_byte
    lea rsi, [r12 + '0']
    mov rdi, rbx
    call sb_push_byte
    EPILOGUE
1:  call push_commas
    EPILOGUE

# push_bytes(sb, n): "512 bytes", "61 KB", "1.2 MB", "3.4 GB"
push_bytes:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 1024
    jae 1f
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lu_bytes]
    call sb_push_cstr
    EPILOGUE
1:  lea r13, [rip + .Lu_kb]
    mov r14d, 10
    cmp r12, 1 << 20
    jb 2f
    lea r13, [rip + .Lu_mb]
    mov r14d, 20
    cmp r12, 1 << 30
    jb 2f
    lea r13, [rip + .Lu_gb]
    mov r14d, 30
2:  # tenths of the unit
    mov rax, r12
    imul rax, rax, 10
    mov ecx, r14d
    shr rax, cl
    mov rdi, rbx
    mov rsi, rax
    call push_tenths
    mov rdi, rbx
    mov rsi, r13
    call sb_push_cstr
    EPILOGUE

# push_duration(sb, ms): "38 ms", "2.4 s", "12 min", "3 h 5 min"
push_duration:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 1000
    jae 1f
    mov rdi, rbx
    call push_commas
    mov rdi, rbx
    lea rsi, [rip + .Lu_ms]
    call sb_push_cstr
    EPILOGUE
1:  cmp r12, 60000
    jae 2f
    mov rax, r12
    xor edx, edx
    mov ecx, 100
    div rcx
    mov rdi, rbx
    mov rsi, rax
    call push_tenths
    mov rdi, rbx
    lea rsi, [rip + .Lu_s]
    call sb_push_cstr
    EPILOGUE
2:  mov rax, r12
    xor edx, edx
    mov ecx, 60000
    div rcx
    mov r12, rax                # minutes
    cmp r12, 60
    jae 3f
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lu_min]
    call sb_push_cstr
    EPILOGUE
3:  mov rax, r12
    xor edx, edx
    mov ecx, 60
    div rcx
    mov r12, rdx
    mov rdi, rbx
    mov rsi, rax
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lu_h]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lu_min]
    call sb_push_cstr
    EPILOGUE

# extres_page_line(ext, i, sb) -> eax 1 with line i of the page's Resources block in sb, 0 past
# the last:
#   Running 12 min · started in 38 ms · runs on this computer
#   CPU 2.4 s · 0.4% now · memory 61 MB in 3 processes
#   Messages 3,812 in · 4,101 out · 1.2 MB
#   Answers 2 slow · 1 dropped · 0 failed · slowest: completion 1,240 ms
#   Stops after 5 min without work
FN extres_page_line
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov rdi, rbx
    call extres_row
    test rax, rax
    jz 8f
    mov r14, rax
    cmp r12d, 0
    je .Lpl_run
    cmp r12d, 1
    je .Lpl_cpu
    cmp r12d, 2
    je .Lpl_msgs
    cmp r12d, 3
    je .Lpl_answers
    cmp r12d, 4
    je .Lpl_idle
8:  xor eax, eax
    EPILOGUE
.Lpl_run:
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 1f
    cmp eax, ES_STARTING
    je 1f
    mov rdi, r13
    lea rsi, [rip + .Lp_not_running]
    call sb_push_cstr
    jmp .Lpl_where
1:  mov rdi, r13
    lea rsi, [rip + .Lp_running]
    call sb_push_cstr
    call time_ms
    sub rax, [r14 + EL_start_t]
    mov rdi, r13
    mov rsi, rax
    call push_duration
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne .Lpl_where
    mov rdi, r13
    lea rsi, [rip + .Lp_started_in]
    call sb_push_cstr
    mov rdi, r13
    mov esi, [r14 + EL_ready_ms]
    call push_duration
.Lpl_where:
    mov rdi, r13
    lea rsi, [rip + .Lp_here]
    call sb_push_cstr
    jmp 9f
.Lpl_cpu:
    mov rdi, r13
    lea rsi, [rip + .Lp_cpu]
    call sb_push_cstr
    mov rax, [r14 + EL_cpu_ns]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov rdi, r13
    mov rsi, rax
    call push_duration
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 2f
    mov rdi, r13
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    mov rdi, r14
    call cpu_tenths
    mov rdi, r13
    mov rsi, rax
    call push_tenths
    mov rdi, r13
    lea rsi, [rip + .Lp_now]
    call sb_push_cstr
2:  cmp dword ptr [r14 + EL_procs], 0
    je 9f
    mov rdi, r13
    lea rsi, [rip + .Lp_memory]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [r14 + EL_rss]
    call push_bytes
    mov rdi, r13
    lea rsi, [rip + .Lp_in]
    call sb_push_cstr
    mov rdi, r13
    mov esi, [r14 + EL_procs]
    call sb_push_u64
    mov rdi, r13
    lea rsi, [rip + .Lp_process]
    cmp dword ptr [r14 + EL_procs], 1
    je 3f
    lea rsi, [rip + .Lp_processes]
3:  call sb_push_cstr
    jmp 9f
.Lpl_msgs:
    mov rdi, r13
    lea rsi, [rip + .Lp_messages]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [r14 + EL_msgs_in]
    call push_commas
    mov rdi, r13
    lea rsi, [rip + .Lp_in_sep]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [r14 + EL_msgs_out]
    call push_commas
    mov rdi, r13
    lea rsi, [rip + .Lp_out_sep]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [r14 + EL_bytes_in]
    add rsi, [r14 + EL_bytes_out]
    call push_bytes
    jmp 9f
.Lpl_answers:
    mov rdi, r13
    lea rsi, [rip + .Lp_answers]
    call sb_push_cstr
    mov rdi, r13
    mov esi, [r14 + EL_slow]
    call push_commas
    mov rdi, r13
    lea rsi, [rip + .Lp_slow]
    call sb_push_cstr
    mov rdi, r13
    mov esi, [r14 + EL_dropped]
    call push_commas
    mov rdi, r13
    lea rsi, [rip + .Lp_dropped]
    call sb_push_cstr
    mov rdi, r13
    mov esi, [r14 + EL_failed]
    call push_commas
    mov rdi, r13
    lea rsi, [rip + .Lp_failed]
    call sb_push_cstr
    mov rax, [r14 + EL_slowest]
    test rax, rax
    jz 9f
    mov rdi, r13
    lea rsi, [rip + .Lp_slowest]
    call sb_push_cstr
    mov rax, [r14 + EL_slowest]
    mov rdi, r13
    mov rsi, [rax + 16]
    call sb_push_cstr
    mov rdi, r13
    mov esi, ' '
    call sb_push_byte
    mov rdi, r13
    mov esi, [r14 + EL_slowest_ms]
    call push_duration
    jmp 9f
.Lpl_idle:
    mov rdi, rbx
    call extres_idle_secs
    test rax, rax
    jz 8b
    imul rsi, rax, 1000
    push rsi
    push rsi
    mov rdi, r13
    lea rsi, [rip + .Lp_stops]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, r13
    call push_duration
    mov rdi, r13
    lea rsi, [rip + .Lp_without_work]
    call sb_push_cstr
9:  mov eax, 1
    EPILOGUE

# extres_card_cost(ext, sb) -> eax 1 with "61 MB · 0.4%" for a running extension's card, 0 when
# it is not running or has no sample yet
FN extres_card_cost
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    call extres_row
    test rax, rax
    jz 8f
    mov r14, rax
    cmp dword ptr [r14 + EL_procs], 0
    je 8f
    mov rdi, r13
    mov rsi, [r14 + EL_rss]
    call push_bytes
    mov rdi, r13
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    mov rdi, r14
    call cpu_tenths
    mov rdi, r13
    mov rsi, rax
    call push_tenths
    mov rdi, r13
    mov esi, '%'
    call sb_push_byte
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- headless commands ----------------

# ext_named(ptr, len) -> rax the extension (name or owner/name), or 0 after "no such extension"
# in rbx's sb (the caller's out)
ext_named:
    PROLOGUE
    mov r12, rdx
    call ext_by_name
    test rax, rax
    jnz 9f
    mov rdi, r12
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
9:  EPILOGUE

# key_u64(sb, " key=", value)
key_u64:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    EPILOGUE

# print-ext-cost OWNER/NAME: cpu_ms= rss_kb= procs= msgs_in= msgs_out= bytes_in= bytes_out=
# slow= dropped= failed= start_ms= starts= busy= idle_after= state= (a fresh sample first)
c_print_ext_cost:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    call ext_named
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    call sample
    mov rdi, r12
    call extres_row
    mov r13, rax
    mov rax, [r13 + EL_cpu_ns]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov rdx, rax
    mov rdi, rbx
    lea rsi, [rip + .Lk_cpu]
    call key_u64
    mov rdx, [r13 + EL_rss]
    shr rdx, 10
    mov rdi, rbx
    lea rsi, [rip + .Lk_rss]
    call key_u64
    mov edx, [r13 + EL_procs]
    mov rdi, rbx
    lea rsi, [rip + .Lk_procs]
    call key_u64
    mov rdx, [r13 + EL_msgs_in]
    mov rdi, rbx
    lea rsi, [rip + .Lk_msgs_in]
    call key_u64
    mov rdx, [r13 + EL_msgs_out]
    mov rdi, rbx
    lea rsi, [rip + .Lk_msgs_out]
    call key_u64
    mov rdx, [r13 + EL_bytes_in]
    mov rdi, rbx
    lea rsi, [rip + .Lk_bytes_in]
    call key_u64
    mov rdx, [r13 + EL_bytes_out]
    mov rdi, rbx
    lea rsi, [rip + .Lk_bytes_out]
    call key_u64
    mov edx, [r13 + EL_slow]
    mov rdi, rbx
    lea rsi, [rip + .Lk_slow]
    call key_u64
    mov edx, [r13 + EL_dropped]
    mov rdi, rbx
    lea rsi, [rip + .Lk_dropped]
    call key_u64
    mov edx, [r13 + EL_failed]
    mov rdi, rbx
    lea rsi, [rip + .Lk_failed]
    call key_u64
    mov edx, [r13 + EL_ready_ms]
    mov rdi, rbx
    lea rsi, [rip + .Lk_start_ms]
    call key_u64
    mov edx, [r13 + EL_starts]
    mov rdi, rbx
    lea rsi, [rip + .Lk_starts]
    call key_u64
    mov edx, [r13 + EL_busy]
    mov rdi, rbx
    lea rsi, [rip + .Lk_busy]
    call key_u64
    mov rdi, r12
    call extres_idle_secs
    mov rdx, rax
    mov rdi, rbx
    lea rsi, [rip + .Lk_idle_after_eq]
    call key_u64
    mov edx, [r13 + EL_nreq]
    mov rdi, rbx
    lea rsi, [rip + .Lk_pending]
    call key_u64
    mov rdi, rbx
    lea rsi, [rip + .Lk_state]
    call sb_push_cstr
    mov edi, [r12 + EXT_status]
    call ext_state_name
    mov rdi, rbx
    mov rsi, rax
    call sb_push_cstr
    mov rsi, [r12 + EXT_reason]
    test rsi, rsi
    jz 1f
    mov rdi, rbx
    lea rsi, [rip + .Lk_reason]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r12 + EXT_reason]
    call sb_push_cstr
1:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
9:  xor eax, eax
    EPILOGUE

# print-startup: first_frame_ms= ext_ready_ms= slowest=OWNER/NAME:MS
c_print_startup:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    lea rsi, [rip + .Lk_first_frame]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + el_first_frame]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lk_ext_ready]
    mov rdx, [rip + el_ready]
    call key_u64
    mov rdi, rbx
    lea rsi, [rip + .Lk_slowest]
    call sb_push_cstr
    mov r12, [rip + el_slowest_ext]
    test r12, r12
    jz 1f
    mov rdi, r12
    call ext_full_name
    mov rdi, rbx
    mov rsi, rax
    call sb_push_cstr
    mov rdi, rbx
    mov esi, ':'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + el_slowest_ms]
    call sb_push_u64
    jmp 2f
1:  mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
2:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# print-ext-page-resources OWNER/NAME: the Resources block's lines, as the page shows them
c_print_resources:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    call ext_named
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    call sample
    xor r13d, r13d
1:  mov rdi, r12
    mov esi, r13d
    mov rdx, rbx
    call extres_page_line
    test eax, eax
    jz 2f
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    inc r13d
    jmp 1b
2:  mov rdi, r12
    mov rsi, rbx
    call extres_card_cost
    test eax, eax
    jz 9f
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
9:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
# the kinds of request rhun asks, and when an answer counts as slow: the presentation target
# where one exists (completion, signature help), else half the 5 s deadline
kinds:   # verb, threshold, the word the page shows
    .quad .Lv_complete, 500, .Lq_complete, .Lq_signature, 500, .Lq_signature
    .quad .Lq_definition, 2500, .Lq_definition, .Lq_references, 2500, .Lq_references
    .quad .Lq_symbols, 2500, .Lq_symbols, .Lq_actions, 1000, .Lq_actions
    .quad .Lq_rename, 2500, .Lq_rename, .Lq_format, 1000, .Lq_format
    .quad .Lq_save_actions, 1000, .Lq_save_actions, .Lq_content, 2500, .Lq_content, 0, 0, 0
kind_other: .quad .Lq_request, 2500, .Lq_request
.globl res_commands
res_commands:   # headless commands of the group (control.s ctl_tables): fn(out, rest, rest len)
    .quad .Lc_print_ext_cost, c_print_ext_cost, .Lc_print_startup, c_print_startup
    .quad .Lc_print_resources, c_print_resources
    .quad .Lc_secret_backend, c_secret_backend, .Lc_print_secrets, c_print_secrets
    .quad .Lc_secrets_refresh, c_secrets_refresh, .Lc_secret_forget, c_secret_forget
    .quad .Lc_print_vdocs, c_print_vdocs
    .quad .Lc_link_deliver, c_link_deliver, .Lc_print_links, c_print_links
    .quad .Lc_print_file_runs, c_print_file_runs
    .quad .Lc_print_ext_setting, c_print_ext_setting
    .quad .Lc_print_folders, c_print_folders, .Lc_folder_add, c_folder_add
    .quad .Lc_folder_remove, c_folder_remove
    .quad 0, 0
.Lv_complete: .asciz "complete"
.Lq_complete: .asciz "completion"
.Lq_signature: .asciz "signature"
.Lq_definition: .asciz "definition"
.Lq_references: .asciz "references"
.Lq_symbols: .asciz "symbols"
.Lq_actions: .asciz "actions"
.Lq_rename: .asciz "rename"
.Lq_format: .asciz "format"
.Lq_save_actions: .asciz "save-actions"
.Lq_content: .asciz "content"
.Lq_request: .asciz "request"
.Lc_print_ext_cost: .asciz "print-ext-cost"
.Lc_print_startup: .asciz "print-startup"
.Lc_print_resources: .asciz "print-ext-resources"
.Lc_secret_backend: .asciz "secret-backend"
.Lc_print_secrets: .asciz "print-secrets"
.Lc_secrets_refresh: .asciz "secrets-refresh"
.Lc_secret_forget: .asciz "secret-forget"
.Lc_print_vdocs: .asciz "print-vdocs"
.Lc_link_deliver: .asciz "link-deliver"
.Lc_print_links: .asciz "print-links"
.Lc_print_file_runs: .asciz "print-file-runs"
.Lc_print_ext_setting: .asciz "print-ext-setting"
.Lc_print_folders: .asciz "print-folders"
.Lc_folder_add: .asciz "folder-add"
.Lc_folder_remove: .asciz "folder-remove"
.Lr_idle: .asciz "idle"
.Lk_open_urls: .asciz "open_urls"
.Lv_yes: .asciz "yes"
.Lw_open_urls: .asciz "open_urls = yes\n"
.Lenv_scale: .asciz "RHUN_IDLE_SCALE"
.Lk_idle: .asciz "idle"
.Lk_idle_after: .asciz "idle.after"
.Lk_runs: .asciz "runs"
.Lk_on: .asciz "on"
.Lk_schemes: .asciz "schemes"
.Ls_provides: .asciz "provides"
.Lv_stop: .asciz "stop"
.Lv_local: .asciz "local"
.Lo_contains: .asciz "contains:"
.Lno_ext: .asciz "no such extension\n"
.Lk_cpu: .asciz "cpu_ms="
.Lk_rss: .asciz " rss_kb="
.Lk_procs: .asciz " procs="
.Lk_msgs_in: .asciz " msgs_in="
.Lk_msgs_out: .asciz " msgs_out="
.Lk_bytes_in: .asciz " bytes_in="
.Lk_bytes_out: .asciz " bytes_out="
.Lk_slow: .asciz " slow="
.Lk_dropped: .asciz " dropped="
.Lk_failed: .asciz " failed="
.Lk_start_ms: .asciz " start_ms="
.Lk_starts: .asciz " starts="
.Lk_busy: .asciz " busy="
.Lk_idle_after_eq: .asciz " idle_after="
.Lk_pending: .asciz " pending="
.Lk_state: .asciz " state="
.Lk_reason: .asciz " reason="
.Lk_first_frame: .asciz "first_frame_ms="
.Lk_ext_ready: .asciz " ext_ready_ms="
.Lk_slowest: .asciz " slowest="
.Lu_bytes: .asciz " bytes"
.Lu_kb: .asciz " KB"
.Lu_mb: .asciz " MB"
.Lu_gb: .asciz " GB"
.Lu_ms: .asciz " ms"
.Lu_s: .asciz " s"
.Lu_min: .asciz " min"
.Lu_h: .asciz " h "
.Lsep: .asciz " \xc2\xb7 "
.Lp_not_running: .asciz "Not running"
.Lp_running: .asciz "Running "
.Lp_started_in: .asciz " \xc2\xb7 started in "
.Lp_here: .asciz " \xc2\xb7 runs on this computer"
.Lp_cpu: .asciz "CPU "
.Lp_now: .asciz "% now"
.Lp_memory: .asciz " \xc2\xb7 memory "
.Lp_in: .asciz " in "
.Lp_process: .asciz " process"
.Lp_processes: .asciz " processes"
.Lp_messages: .asciz "Messages "
.Lp_in_sep: .asciz " in \xc2\xb7 "
.Lp_out_sep: .asciz " out \xc2\xb7 "
.Lp_answers: .asciz "Answers "
.Lp_slow: .asciz " slow \xc2\xb7 "
.Lp_dropped: .asciz " dropped \xc2\xb7 "
.Lp_failed: .asciz " failed"
.Lp_slowest: .asciz " \xc2\xb7 slowest: "
.Lp_stops: .asciz "Stops after "
.Lp_without_work: .asciz " without work"
