# tasks: the "tasks" feature of protocol 1.1 (tasks design 3.5, 1.2, 1.5) and rhun's own task
# commands. Extensions publish task definitions (tasks-set); rhun lists them (Run Task, Run Build
# Task on ctrl+shift+B, Restart, Stop, Show), runs them in terminal tabs (one tab per task, reused when
# it runs again), runs their dependencies first (in sequence or in parallel, 8 at once), knows a
# background task is ready when a line matches its ready patterns (busy starts a new cycle), and turns
# their lines into problems with their matchers. An extension may also start a published task
# (task-start) or one it does not publish (task-run). The debugger runs a launch configuration's
# prelaunch task with tasks_run_named.
#
#   termproto_request hands tasks-set, task-start and task-run to tasks_request(ext, id, line, len,
#   body, blen); tasks_forget(ext): its published tasks go (stopped, disabled, removed); the project
#   changing drops them all (tasks_project_changed)
#   tasks_run_named(name, cb(cookie, result), cookie) -> 0 started (cb comes later with TASK_DONE or
#       TASK_FAILED), -1 no such task (or more than one), -2 busy: name is OWNER/NAME:ID, a task id
#       no other extension publishes, or a label only one task has
.include "rhun.inc"

.equ TASKS_MAX, 1000             # in one tasks-set
.equ PUBLISHED_MAX, 4194304      # bytes of published definitions in all
.equ RN_MAX, 32                  # run nodes, waiting or running
.equ DEPTH_MAX, 8
.equ PARALLEL_MAX, 8
.equ KIDS_MAX, 16
.equ RECENT_MAX, 16
.equ RS_FREE, 0
.equ RS_WAIT, 1                  # its dependencies are not done yet
.equ RS_RUN, 2                   # its program runs
.equ RS_FAILED, 3                # a dependency failed: it will not run
.equ PK_NONE, 0                  # what waits for the approval dialog
.equ PK_START, 1                 # task-start: reply ok ID TERM
.equ PK_RUN, 2                   # task-run: reply ok ID TERM
.equ PK_USER, 3                  # the user's Run Task
.equ PK_NAMED, 4                 # tasks_run_named: its callback

# an extension's published tasks
STRUCT
F RG_ext, 8
F RG_dfs, VEC_SIZE              # DF*
F RG_bytes, 8                   # the tasks-set body's bytes
ENDSTRUCT RG_SIZE

# a node of a run: a task and the dependencies it waits for
STRUCT
F RN_state, 4
F RN_parent, 4                  # node index, or -1 for the run's root
F RN_ext, 8
F RN_df, 8                      # held while the node lives
F RN_tr, 8                      # its terminal record
F RN_cb, 8                      # the root's callback (tasks_run_named), or 0
F RN_cookie, 8
F RN_nkids, 4
F RN_next, 4                    # the next dependency to start
F RN_left, 4                    # dependencies not done
F RN_running, 4                 # dependencies started and not done (parallel: 8 at most)
F RN_kids, 4*KIDS_MAX
ENDSTRUCT RN_SIZE

.bss
.p2align 3
regs: .zero VEC_SIZE            # RG*
nodes: .zero RN_SIZE * RN_MAX
published: .quad 0              # bytes of every extension's published definitions
srcs: .zero VEC_SIZE            # the Problems sources of tasks (Clear Task Problems)
recent: .zero 16 * RECENT_MAX   # the tasks the user ran, newest first: EXT*, owned id
# what waits for the approval dialog
pk_kind: .long 0
.p2align 3
pk_ext: .quad 0
pk_id: .quad 0
pk_df: .quad 0                  # held
pk_cb: .quad 0
pk_cookie: .quad 0
# the request being served
req_ext: .quad 0
req_id: .quad 0
words: .zero 16 * 8
nwords: .quad 0
ob: .zero SB_SIZE
tmp: .zero SB_SIZE
picks: .zero VEC_SIZE           # the palette's tasks: EXT*, owned id, DF* (for its label) per item
pick_mode: .long 0              # which command opened it (PICK_*)
build_err: .long 0              # build(): 1 past the limits

.equ PICK_RUN, 1
.equ PICK_RESTART, 2
.equ PICK_STOP, 3
.equ PICK_SHOW, 4
.equ PICK_GROUP, 5

.text

# ---------------- small helpers ----------------

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
ob_send:
    lea rsi, [rip + ob]
    jmp tr_send

# reply_error(cstr), reply_error2(cstr, cstr): "error ID CODE TEXT" to the request being served
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

# reply_ok_u64(ext, id, value): "ok ID VALUE"; value -1: "ok ID"
reply_ok_u64:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ob_begin
    lea rdi, [rip + .Lw_ok]
    call ob_cstr
    mov rdi, r12
    call ob_u64
    cmp r13, -1
    je 1f
    mov edi, ' '
    call ob_byte
    mov rdi, r13
    call ob_u64
1:  mov edi, 10
    call ob_byte
    mov rdi, rbx
    call ob_send
    EPILOGUE

# split(ptr, len): the line's words into words/nwords
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
    ret

word_is:
    lea rax, [rip + words]
    shl rdi, 4
    mov rdx, rsi
    mov rsi, [rax + rdi + 8]
    mov rdi, [rax + rdi]
    jmp str_eq_cstr

# word(i) -> rax ptr, rdx len
word:
    lea rax, [rip + words]
    shl rdi, 4
    mov rdx, [rax + rdi + 8]
    mov rax, [rax + rdi]
    ret

# ---------------- the registry ----------------

# reg_of(ext, make) -> its RG*, or 0 (made when make is 1)
reg_of:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    xor ecx, ecx
1:  cmp rcx, [rip + regs + VEC_len]
    jae 2f
    mov rax, [rip + regs + VEC_ptr]
    mov rax, [rax + rcx*8]
    cmp [rax + RG_ext], rbx
    je 9f
    inc rcx
    jmp 1b
2:  xor eax, eax
    test r12d, r12d
    jz 9f
    mov edi, RG_SIZE
    call mem_alloc
    mov [rax + RG_ext], rbx
    mov r13, rax
    lea rdi, [rip + regs]
    mov esi, 8
    call vec_push
    mov [rax], r13
    mov rax, r13
9:  EPILOGUE

# reg_clear(RG*): its definitions go (a run that holds one keeps it until it ends)
reg_clear:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + RG_dfs + VEC_len]
    jae 2f
    mov rax, [rbx + RG_dfs + VEC_ptr]
    mov rdi, [rax + r12*8]
    call df_release
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + RG_dfs + VEC_len], 0
    mov rax, [rbx + RG_bytes]
    sub [rip + published], rax
    mov qword ptr [rbx + RG_bytes], 0
    EPILOGUE

# df_hold(DF*), df_release(DF*): a DF lives while its registry or a run node holds it
FN tasks_df_release
    jmp df_release
df_hold:
    inc dword ptr [rdi + DF_refs]
    ret
df_release:
    dec dword ptr [rdi + DF_refs]
    jns 1f
    jmp def_free
1:  ret

# reg_find(RG*, id ptr, len) -> its DF*, or 0
reg_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz 8f
    xor r14d, r14d
1:  cmp r14, [rbx + RG_dfs + VEC_len]
    jae 8f
    mov rax, [rbx + RG_dfs + VEC_ptr]
    mov r15, [rax + r14*8]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + DF_id]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# tasks_forget(ext): its published tasks go (the user stopped, turned off or removed it)
FN tasks_forget
    PROLOGUE
    xor esi, esi
    call reg_of
    test rax, rax
    jz 9f
    mov rdi, rax
    call reg_clear
9:  EPILOGUE

# tasks_project_changed(): another project: every published task goes (its extension publishes again)
FN tasks_project_changed
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + regs + VEC_len]
    jae 9f
    mov rax, [rip + regs + VEC_ptr]
    mov rdi, [rax + rbx*8]
    inc rbx
    call reg_clear
    jmp 1b
9:  EPILOGUE

# ---------------- tasks-set ----------------

# tasks_set(body, blen) -> 0, or replied with the reason: "N" LF then N definitions, checked whole
#   (ids unique, depends naming ids of the list, no cycle, patterns and matchers valid) before the
#   extension's list is replaced
tasks_set:
    PROLOGUE 48
    mov r12, rdi
    mov r13, rsi
    # the count
    xor ecx, ecx
1:  cmp rcx, r13
    jae .Lts_count
    cmp rcx, 8
    ja .Lts_count
    cmp byte ptr [r12 + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  test rcx, rcx
    jz .Lts_count
    mov [rsp], rcx
    mov rdi, r12
    mov rsi, rcx
    call parse_u64
    cmp rdx, [rsp]
    jne .Lts_count
    cmp rax, TASKS_MAX
    ja .Lts_toobig
    mov r14, rax                # tasks
    mov rax, [rsp]
    lea r15, [r12 + rax + 1]    # the definitions
    add r12, r13                # the end
    # the published bytes in all
    mov rdi, [rip + req_ext]
    xor esi, esi
    call reg_of
    xor ecx, ecx
    test rax, rax
    jz 3f
    mov rcx, [rax + RG_bytes]
3:  mov rax, [rip + published]
    sub rax, rcx
    add rax, r13
    cmp rax, PUBLISHED_MAX
    ja .Lts_toobig
    # every definition, into a new list
    lea rdi, [rip + tmp]
    call sb_clear               # (DF* pointers)
    xor ebx, ebx
4:  cmp rbx, r14
    jae 5f
    mov rdi, r15
    mov rsi, r12
    sub rsi, r15
    mov edx, 1
    call def_parse
    test rax, rax
    jz .Lts_bad
    add r15, rcx
    mov [rsp + 8], rax
    lea rdi, [rip + tmp]
    lea rsi, [rsp + 8]
    mov edx, 8
    call sb_push
    inc rbx
    jmp 4b
5:  cmp r15, r12
    jne .Lts_trailing
    # ids unique, depends known, no cycle
    call list_check
    test rax, rax
    jnz .Lts_bad_list
    # the new list replaces the old
    mov rdi, [rip + req_ext]
    mov esi, 1
    call reg_of
    mov rbx, rax
    mov rdi, rbx
    call reg_clear
    xor r15d, r15d
6:  cmp r15, r14
    jae 7f
    mov rax, [rip + tmp + SB_ptr]
    mov rcx, [rax + r15*8]
    mov [rsp + 8], rcx
    lea rdi, [rbx + RG_dfs]
    mov esi, 8
    call vec_push
    mov rcx, [rsp + 8]
    mov [rax], rcx
    inc r15
    jmp 6b
7:  mov [rbx + RG_bytes], r13
    add [rip + published], r13
    xor eax, eax
    EPILOGUE
.Lts_count:
    lea rdi, [rip + .Le_count]
    call reply_error
    mov eax, 1
    EPILOGUE
.Lts_toobig:
    lea rdi, [rip + .Le_toobig]
    call reply_error
    mov eax, 1
    EPILOGUE
.Lts_bad:
    # "syntax task N: REASON"
    mov [rsp + 16], rdx
    lea rdi, [rip + ob]          # (built here, sent by reply_error2 below)
    call free_tmp_list
    lea rdi, [rip + why_buf]
    lea rsi, [rip + .Le_task]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rbx + 1]
    call fmt_u64
    mov byte ptr [rdi], ':'
    mov byte ptr [rdi + 1], ' '
    lea rdi, [rdi + 2]
    mov rsi, [rsp + 16]
    call cstr_copy
    lea rdi, [rip + .Le_syntax_sp]
    lea rsi, [rip + why_buf]
    call reply_error2
    mov eax, 1
    EPILOGUE
.Lts_trailing:
    call free_tmp_list
    lea rdi, [rip + .Le_trailing]
    call reply_error
    mov eax, 1
    EPILOGUE
.Lts_bad_list:
    mov [rsp + 16], rax
    call free_tmp_list
    lea rdi, [rip + .Le_syntax_sp]
    mov rsi, [rsp + 16]
    call reply_error2
    mov eax, 1
    EPILOGUE

# free_tmp_list(): the DFs parsed into tmp go
free_tmp_list:
    push rbx
    xor ebx, ebx
1:  mov rax, [rip + tmp + SB_len]
    shr rax, 3
    cmp rbx, rax
    jae 9f
    mov rax, [rip + tmp + SB_ptr]
    mov rdi, [rax + rbx*8]
    call def_free
    inc rbx
    jmp 1b
9:  pop rbx
    ret

# list_check() -> 0, or the reason (cstr in why_buf) for the DFs in tmp: ids unique, every depends
#   naming one of them, no cycle
list_check:
    PROLOGUE 16
    mov r14, [rip + tmp + SB_len]
    shr r14, 3                  # tasks
    mov r15, [rip + tmp + SB_ptr]
    xor ebx, ebx
1:  cmp rbx, r14
    jae 4f
    mov r12, [r15 + rbx*8]
    # unique
    lea r13, [rbx + 1]
2:  cmp r13, r14
    jae 3f
    mov rax, [r15 + r13*8]
    mov rdi, [rax + DF_id]
    mov rsi, [r12 + DF_id]
    call strcmp_eq
    test eax, eax
    jnz .Llc_twice
    inc r13
    jmp 2b
3:  # its depends known
    mov r13, [r12 + DF_deps]
31: mov rdi, [r13]
    test rdi, rdi
    jz 32f
    call tmp_index
    test rax, rax
    js .Llc_nodep
    add r13, 8
    jmp 31b
32: inc rbx
    jmp 1b
4:  # no cycle: from each task, depth-first with marks (DF_refs is free to use while parsed: -1
    # visiting, -2 done)
    xor ebx, ebx
5:  cmp rbx, r14
    jae 6f
    mov rdi, rbx
    call visit
    test eax, eax
    jnz .Llc_cycle
    inc rbx
    jmp 5b
6:  xor ebx, ebx
7:  cmp rbx, r14
    jae 8f
    mov rax, [r15 + rbx*8]
    mov dword ptr [rax + DF_refs], 0
    inc rbx
    jmp 7b
8:  xor eax, eax
    EPILOGUE
.Llc_twice:
    lea rsi, [rip + .Le_twice]
    jmp .Llc_why
.Llc_nodep:
    # depends: no task "lint"
    lea rdi, [rip + why_buf]
    lea rsi, [rip + .Le_task]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rbx + 1]
    call fmt_u64
    lea rsi, [rip + .Le_nodep]
    call cstr_copy
    mov rdi, rax
    mov rsi, [r13]
    call cstr_copy
    mov word ptr [rax], 0x0022  # the closing quote
    lea rax, [rip + why_buf]
    EPILOGUE
.Llc_cycle:
    lea rsi, [rip + .Le_cycle]
.Llc_why:
    lea rdi, [rip + why_buf]
    push rsi
    push rsi
    lea rsi, [rip + .Le_task]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rbx + 1]
    call fmt_u64
    pop rsi
    pop rsi
    call cstr_copy
    mov r14, [rip + tmp + SB_len]   # the marks go for the next time
    shr r14, 3
    xor ebx, ebx
91: cmp rbx, r14
    jae 92f
    mov rax, [r15 + rbx*8]
    mov dword ptr [rax + DF_refs], 0
    inc rbx
    jmp 91b
92: lea rax, [rip + why_buf]
    EPILOGUE

# tmp_index(id cstr) -> the index in tmp of the DF with that id, or -1
tmp_index:
    PROLOGUE
    mov r12, rdi
    mov r14, [rip + tmp + SB_len]
    shr r14, 3
    mov r15, [rip + tmp + SB_ptr]
    xor ebx, ebx
1:  cmp rbx, r14
    jae 8f
    mov rax, [r15 + rbx*8]
    mov rdi, [rax + DF_id]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 9f
    inc rbx
    jmp 1b
8:  mov rax, -1
    EPILOGUE
9:  mov rax, rbx
    EPILOGUE

# visit(index) -> eax 1 when a cycle runs through it (DF_refs: -1 being visited, -2 done)
visit:
    PROLOGUE
    mov rax, [rip + tmp + SB_ptr]
    mov rbx, [rax + rdi*8]
    cmp dword ptr [rbx + DF_refs], -2
    je 8f
    cmp dword ptr [rbx + DF_refs], -1
    je 9f
    mov dword ptr [rbx + DF_refs], -1
    mov r12, [rbx + DF_deps]
1:  mov rdi, [r12]
    test rdi, rdi
    jz 2f
    call tmp_index
    mov rdi, rax
    call visit
    test eax, eax
    jnz 9f
    add r12, 8
    jmp 1b
2:  mov dword ptr [rbx + DF_refs], -2
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# ---------------- requests ----------------

# tasks_request(ext, id, line, len, body, blen): tasks-set, task-start, task-run
FN tasks_request
    PROLOGUE 16
    mov rbx, rdi
    mov [rip + req_ext], rdi
    mov [rip + req_id], rsi
    mov r12, r8
    mov r13, r9
    mov rdi, rdx
    mov rsi, rcx
    call split
    FEAT_TEST rbx, FEAT_TASKS
    jz .Lrq_unknown
    mov rax, [rip + req_ext]
    test dword ptr [rax + EXT_needs], NEEDS_TERM_RUN
    jz .Lrq_needs
    mov edi, 1
    lea rsi, [rip + .Lv_set]
    call word_is
    test eax, eax
    jnz .Lrq_set
    mov edi, 1
    lea rsi, [rip + .Lv_start]
    call word_is
    test eax, eax
    jnz .Lrq_start
    mov edi, 1
    lea rsi, [rip + .Lv_run]
    call word_is
    test eax, eax
    jnz .Lrq_run
.Lrq_unknown:
    lea rdi, [rip + .Le_unknown]
    call reply_error
    EPILOGUE
.Lrq_needs:
    lea rdi, [rip + .Le_needs]
    call reply_error
    EPILOGUE
.Lrq_set:
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov rdi, r12
    mov rsi, r13
    call tasks_set
    test eax, eax
    jnz 9f
    mov rdi, [rip + req_ext]
    mov rsi, [rip + req_id]
    mov rdx, -1
    call reply_ok_u64
9:  EPILOGUE
.Lrq_start:
    # ID task-start TASK_ID
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov rdi, rbx
    xor esi, esi
    call reg_of
    mov r14, rax
    mov edi, 2
    call word
    mov rdi, r14
    mov rsi, rax
    call reg_find
    test rax, rax
    jz .Lrq_notask
    mov rdi, rax
    mov esi, PK_START
    xor edx, edx                # no callback
    xor ecx, ecx
    call start_request
    EPILOGUE
.Lrq_run:
    # ID task-run LEN + definition (its depends may name published ids)
    cmp qword ptr [rip + nwords], 3
    jne .Lrq_syntax
    mov rdi, r12
    mov rsi, r13
    mov edx, 1
    call def_parse
    test rax, rax
    jz .Lrq_bad_def
    cmp rcx, r13
    jne .Lrq_trailing
    mov r14, rax
    # its depends are published tasks
    mov rdi, rbx
    xor esi, esi
    call reg_of
    mov r15, rax
    mov r12, [r14 + DF_deps]
1:  mov rsi, [r12]
    test rsi, rsi
    jz 2f
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rsi, [r12]
    mov rdi, r15
    call reg_find
    test rax, rax
    jz .Lrq_run_nodep
    add r12, 8
    jmp 1b
2:  # busy while a task with that id runs
    mov rdi, rbx
    mov rsi, [r14 + DF_id]
    call tr_find_task
    test rax, rax
    jz 3f
    mov rdi, [rax + TRC_term]
    call term_pid
    test eax, eax
    jnz .Lrq_run_busy
3:  mov rdi, r14
    mov esi, PK_RUN
    xor edx, edx
    xor ecx, ecx
    call start_request
    mov rdi, r14
    call df_release             # start_request holds what it keeps
    EPILOGUE
.Lrq_run_nodep:
    lea rdi, [rip + .Le_run_nodep]
    call reply_error
    mov rdi, r14
    call def_free
    EPILOGUE
.Lrq_run_busy:
    lea rdi, [rip + .Le_busy]
    call reply_error
    mov rdi, r14
    call def_free
    EPILOGUE
.Lrq_bad_def:
    mov rsi, rdx
    lea rdi, [rip + .Le_syntax_def]
    call reply_error2
    EPILOGUE
.Lrq_trailing:
    mov rdi, rax
    call def_free
    lea rdi, [rip + .Le_trailing]
    call reply_error
    EPILOGUE
.Lrq_notask:
    lea rdi, [rip + .Le_notask]
    call reply_error
    EPILOGUE
.Lrq_syntax:
    lea rdi, [rip + .Le_syntax]
    call reply_error
    EPILOGUE

# ---------------- starting ----------------

# start_request(DF*, kind): a task to start for req_ext (PK_START, PK_RUN: req_id waits for its
#   TERM; PK_USER; PK_NAMED with pk_cb/pk_cookie set by the caller in rdx, rcx): after the one
#   approval per extension and project, the run begins
start_request:
    PROLOGUE 16
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    mov rbx, [rip + req_ext]
    # a published task that runs already: left running, its TERM the answer
    cmp r13d, PK_RUN
    je 1f
    mov rdi, rbx
    mov rsi, [r12 + DF_id]
    call tr_find_task
    test rax, rax
    jz 1f
    mov [rsp], rax
    mov rdi, [rax + TRC_term]
    call term_pid
    test eax, eax
    jz 1f
    mov rax, [rsp]
    mov rdi, rbx
    mov rsi, rax
    mov edx, r13d
    mov rcx, r14
    mov r8, r15
    call already_running
    EPILOGUE
1:  # the exact command, and how many tasks it depends on
    lea rdi, [rip + ob]
    call sb_clear
    mov rdi, r12
    lea rsi, [rip + ob]
    call def_command
    mov rdi, r12
    call count_deps
    test eax, eax
    jz 2f
    mov [rsp], eax
    lea rdi, [rip + ob]
    lea rsi, [rip + .Lw_and]
    call sb_push_cstr
    lea rdi, [rip + ob]
    mov esi, [rsp]
    call sb_push_u64
    lea rdi, [rip + ob]
    lea rsi, [rip + .Lw_task_it]
    cmp dword ptr [rsp], 1
    je 11f
    lea rsi, [rip + .Lw_tasks_it]
11: call sb_push_cstr
2:  lea rdi, [rip + ob]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + ob + SB_ptr]
    lea rdx, [rip + approval_answer]
    mov ecx, 2
    call run_approve
    cmp eax, 1
    je 3f
    test eax, eax
    jnz .Lsr_busy
    # parked until the user answers
    cmp dword ptr [rip + pk_kind], PK_NONE
    jne .Lsr_busy               # (one at a time)
    mov [rip + pk_kind], r13d
    mov [rip + pk_ext], rbx
    mov rax, [rip + req_id]
    mov [rip + pk_id], rax
    mov [rip + pk_df], r12
    mov rdi, r12
    call df_hold
    mov [rip + pk_cb], r14
    mov [rip + pk_cookie], r15
    EPILOGUE
3:  mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov rcx, [rip + req_id]
    mov r8, r14
    mov r9, r15
    call run_begin
    EPILOGUE
.Lsr_busy:
    cmp r13d, PK_START
    je 4f
    cmp r13d, PK_RUN
    je 4f
    cmp r13d, PK_NAMED
    jne 5f
    test r14, r14
    jz 5f
    mov rdi, r15
    mov esi, TASK_FAILED
    call r14
    EPILOGUE
4:  lea rdi, [rip + .Le_busy]
    call reply_error
5:  EPILOGUE

# approval_answer(cookie, allowed): the user answered for the parked start
approval_answer:
    PROLOGUE
    mov r12d, esi
    mov ebx, [rip + pk_kind]
    test ebx, ebx
    jz 9f
    mov dword ptr [rip + pk_kind], PK_NONE
    mov r13, [rip + pk_df]
    mov rax, [rip + pk_ext]
    mov [rip + req_ext], rax
    mov rax, [rip + pk_id]
    mov [rip + req_id], rax
    test r12d, r12d
    jz 1f
    mov rdi, [rip + pk_ext]
    mov rsi, r13
    mov edx, ebx
    mov rcx, [rip + pk_id]
    mov r8, [rip + pk_cb]
    mov r9, [rip + pk_cookie]
    call run_begin
    jmp 8f
1:  # refused
    cmp ebx, PK_START
    je 2f
    cmp ebx, PK_RUN
    je 2f
    cmp ebx, PK_NAMED
    jne 8f
    mov rax, [rip + pk_cb]
    test rax, rax
    jz 8f
    mov rdi, [rip + pk_cookie]
    mov esi, TASK_FAILED
    call rax
    jmp 8f
2:  lea rdi, [rip + .Le_cancelled]
    call reply_error
8:  mov rdi, r13
    call df_release
9:  EPILOGUE

# tasks_cancel(ext, id) -> 1 when that request waited for the approval dialog (cancel ID)
FN tasks_cancel
    push rbx
    xor eax, eax
    cmp dword ptr [rip + pk_kind], PK_START
    je 1f
    cmp dword ptr [rip + pk_kind], PK_RUN
    jne 9f
1:  cmp [rip + pk_ext], rdi
    jne 9f
    cmp [rip + pk_id], rsi
    jne 9f
    mov [rip + req_ext], rdi
    mov [rip + req_id], rsi
    mov dword ptr [rip + pk_kind], PK_NONE
    mov edi, 2
    call run_approve_cancel
    mov rdi, [rip + pk_df]
    call df_release
    lea rdi, [rip + .Le_cancelled]
    call reply_error
    mov eax, 1
9:  pop rbx
    ret

# tasks_ext_gone(ext): its runtime stopped: a start waiting for the dialog for it goes
FN tasks_ext_gone
    PROLOGUE
    cmp dword ptr [rip + pk_kind], PK_NONE
    je 9f
    cmp [rip + pk_ext], rdi
    jne 9f
    mov dword ptr [rip + pk_kind], PK_NONE
    mov edi, 2
    call run_approve_cancel
    mov rdi, [rip + pk_df]
    call df_release
9:  EPILOGUE

# already_running(ext, TR*, kind, cb, cookie): the task runs already: its tab shows; task-start gets
#   its TERM; a prelaunch is done once it is (a background task that is ready: at once)
already_running:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    mov rdi, [r12 + TRC_term]
    mov esi, 0
    call term_reveal
    cmp r13d, PK_START
    jne 1f
    mov rdi, rbx
    mov rsi, [rip + req_id]
    mov rdx, [r12 + TRC_term]
    call reply_ok_u64
    EPILOGUE
1:  cmp r13d, PK_NAMED
    jne 9f
    test r14, r14
    jz 9f
    cmp dword ptr [r12 + TRC_ready], 0
    je 2f
    mov rdi, r15
    mov esi, TASK_DONE
    call r14
    EPILOGUE
2:  # waited for, as a node of its own
    call node_alloc
    test rax, rax
    jz 3f
    mov dword ptr [rax + RN_state], RS_RUN
    mov dword ptr [rax + RN_parent], -1
    mov [rax + RN_ext], rbx
    mov [rax + RN_tr], r12
    mov [rax + RN_cb], r14
    mov [rax + RN_cookie], r15
    mov rdi, [r12 + TRC_df]
    mov [rax + RN_df], rdi
    test rdi, rdi
    jz 9f
    call df_hold
    EPILOGUE
3:  mov rdi, r15
    mov esi, TASK_FAILED
    call r14
9:  EPILOGUE

# count_deps(DF*) -> eax its dependencies, theirs included, as far as the registry knows (the dialog)
count_deps:
    PROLOGUE
    mov rbx, [rdi + DF_deps]
    xor r12d, r12d
1:  cmp qword ptr [rbx], 0
    je 9f
    inc r12d
    add rbx, 8
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# node_alloc() -> a free RN*, zeroed, or 0 with all 32 in use
node_alloc:
    lea rax, [rip + nodes]
    mov ecx, RN_MAX
1:  cmp dword ptr [rax + RN_state], RS_FREE
    je 2f
    add rax, RN_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
    ret
2:  push rax
    mov rdi, rax
    xor esi, esi
    mov edx, RN_SIZE
    call memset
    pop rax
    ret

# node_ptr(index) -> RN*;  node_index(RN*) -> eax
node_ptr:
    imul eax, edi, RN_SIZE
    lea rcx, [rip + nodes]
    add rax, rcx
    ret
node_index:
    lea rcx, [rip + nodes]
    mov rax, rdi
    sub rax, rcx
    xor edx, edx
    mov ecx, RN_SIZE
    div rcx
    ret

# node_free(RN*): its DF released, the slot free
node_free:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + RN_df]
    test rdi, rdi
    jz 1f
    call df_release
1:  mov dword ptr [rbx + RN_state], RS_FREE
    pop rbx
    ret

# run_begin(ext, DF*, kind, id, cb, cookie): the run's nodes and their tabs (waiting), the answer to
#   task-start and task-run (ok ID TERM), then the tasks with nothing to wait for start
run_begin:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov [rsp], r8
    mov [rsp + 8], r9
    mov dword ptr [rip + build_err], 0
    mov rdi, rbx
    mov rsi, r12
    mov edx, -1
    xor ecx, ecx
    call build
    movsxd r15, eax
    test r15, r15
    js .Lrb_fail                # -1 past the limits; -2 (ready already) does not come for the root
    mov rdi, r15
    call node_ptr
    mov rcx, [rsp]
    mov [rax + RN_cb], rcx
    mov rcx, [rsp + 8]
    mov [rax + RN_cookie], rcx
    mov [rsp + 16], rax
    cmp r13d, PK_USER
    jne 1f
    mov rdi, rbx
    mov rsi, [r12 + DF_id]
    call recent_add
1:  # task-start and task-run hear the root's TERM
    cmp r13d, PK_START
    je 2f
    cmp r13d, PK_RUN
    jne 3f
2:  mov rax, [rsp + 16]
    mov rax, [rax + RN_tr]
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [rax + TRC_term]
    call reply_ok_u64
3:  mov edi, r15d
    call node_go
    EPILOGUE
.Lrb_fail:
    cmp r13d, PK_START
    je 4f
    cmp r13d, PK_RUN
    je 4f
    mov rax, [rsp]
    test rax, rax
    jz 5f
    mov rdi, [rsp + 8]
    mov esi, TASK_FAILED
    call rax
    jmp 5f
4:  mov [rip + req_ext], rbx
    mov [rip + req_id], r14
    lea rdi, [rip + .Le_busy_run]
    call reply_error
5:  EPILOGUE

# build(ext, DF*, parent, depth) -> eax the node index (waiting), -2 when there is nothing to wait for
#   (a background task that is ready), -1 past the limits (nodes made so far are freed by the caller
#   failing: they never start)
build:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    cmp r14d, DEPTH_MAX
    ja .Lbd_fail
    # its tab, when it has one: running, it is waited for (ready: done at once)
    mov rdi, rbx
    mov rsi, [r12 + DF_id]
    call tr_find_task
    mov [rsp], rax
    test rax, rax
    jz 1f
    mov rdi, [rax + TRC_term]
    call term_pid
    test eax, eax
    jz 1f
    mov rax, [rsp]
    cmp dword ptr [rax + TRC_ready], 0
    je 11f
    mov eax, -2
    EPILOGUE
11: call node_alloc
    test rax, rax
    jz .Lbd_fail
    mov dword ptr [rax + RN_state], RS_RUN
    mov [rax + RN_parent], r13d
    mov [rax + RN_ext], rbx
    mov rcx, [rsp]
    mov [rax + RN_tr], rcx
    mov rdi, rax
    call node_index
    EPILOGUE
1:  call node_alloc
    test rax, rax
    jz .Lbd_fail
    mov r15, rax
    mov dword ptr [r15 + RN_state], RS_WAIT
    mov [r15 + RN_parent], r13d
    mov [r15 + RN_ext], rbx
    mov [r15 + RN_df], r12
    mov rdi, r12
    call df_hold
    mov rdi, r15
    call node_index
    mov [rsp + 8], eax          # its index
    # its dependencies, published by the same extension
    mov rax, [r12 + DF_deps]
    mov [rsp + 16], rax
2:  mov rax, [rsp + 16]
    mov rsi, [rax]
    test rsi, rsi
    jz 4f
    add qword ptr [rsp + 16], 8
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, [rsp + 16]
    mov rsi, [rax - 8]
    push rsi
    push rdx
    mov rdi, rbx
    xor esi, esi
    call reg_of
    pop rdx
    pop rsi
    mov rdi, rax
    call reg_find
    test rax, rax
    jz .Lbd_fail
    mov rdi, rbx
    mov rsi, rax
    mov edx, [rsp + 8]
    lea ecx, [r14 + 1]
    call build
    cmp eax, -1
    je .Lbd_fail
    cmp eax, -2
    je 2b                       # a ready one: nothing to wait for
    mov ecx, [r15 + RN_nkids]
    cmp ecx, KIDS_MAX
    jae .Lbd_fail
    mov [r15 + rcx*4 + RN_kids], eax
    inc dword ptr [r15 + RN_nkids]
    inc dword ptr [r15 + RN_left]
    jmp 2b
4:  # its tab, waiting for its turn
    mov rdi, rbx
    mov rsi, r12
    call task_tab
    test rax, rax
    jz .Lbd_fail
    mov [r15 + RN_tr], rax
    mov eax, [rsp + 8]
    EPILOGUE
.Lbd_fail:
    mov dword ptr [rip + build_err], 1
    mov eax, -1
    EPILOGUE

# task_tab(ext, DF*) -> TR*: the task's tab, reused when it has one (its program and title the
#   DF's), else a new one; waiting (not started), its matchers ready; 0 when no tab can be had
task_tab:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, [r12 + DF_id]
    call tr_find_task
    mov r13, rax
    test r13, r13
    jz 1f
    # the same tab, the program as published now
    mov rdi, r12
    lea rsi, [rsp]
    call def_program
    mov rdi, [r13 + TRC_term]
    lea rsi, [rsp]
    mov rdx, [r12 + DF_label]
    call term_set_program
    mov rdi, [rsp + PGM_argv]
    call mem_free
    mov dword ptr [r13 + TRC_live], 1
    jmp 2f
1:  mov rdi, rbx
    mov rsi, r12
    mov edx, TK_TASK | TRV_WAIT
    call tr_open
    mov r13, rax
    test rax, rax
    jz 9f
2:  # the DF its lines are read with, its matchers, its problems' source
    mov rdi, [r13 + TRC_df]
    test rdi, rdi
    jz 3f
    call df_release
3:  mov [r13 + TRC_df], r12
    mov rdi, r12
    call df_hold
    mov dword ptr [r13 + TRC_ready], 0
    lea rax, [rip + task_event]
    mov [r13 + TRC_hook], rax
    lea rax, [rip + task_line]
    mov [r13 + TRC_linefn], rax
    mov [r13 + TRC_cookie], r13
    mov rdi, [r13 + TRC_mrun]
    call mrun_free
    mov qword ptr [r13 + TRC_mrun], 0
    cmp dword ptr [r12 + DF_nmatch], 0
    je 6f
    mov rdi, rbx
    mov rsi, r12
    call task_source
    mov r14, rax
    mov rdi, [r12 + DF_cwd]
    call term_run_folder
    mov r15, rax
    mov rdi, r14
    mov rsi, r15
    mov rdx, [r13 + TRC_term]
    call mrun_new
    mov [r13 + TRC_mrun], rax
    mov rdi, r15
    call mem_free
    xor r14d, r14d
5:  cmp r14d, [r12 + DF_nmatch]
    jae 6f
    mov rdi, [r13 + TRC_mrun]
    mov rsi, [r12 + r14*8 + DF_match]
    call mrun_add
    inc r14d
    jmp 5b
6:  mov rax, r13
9:  EPILOGUE

# task_source(ext, DF*) -> its Problems source: task:OWNER/NAME:ID, labelled with the task's label
task_source:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lw_task_key]
    call sb_push_cstr
    mov rdi, rbx
    call ext_full_name
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r12 + DF_id]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [r12 + DF_label]
    call problems_source
    mov rbx, rax
    # remembered for Clear Task Problems
    xor ecx, ecx
1:  cmp rcx, [rip + srcs + VEC_len]
    jae 2f
    mov rax, [rip + srcs + VEC_ptr]
    cmp [rax + rcx*8], rbx
    je 3f
    inc rcx
    jmp 1b
2:  lea rdi, [rip + srcs]
    mov esi, 8
    call vec_push
    mov [rax], rbx
3:  mov rax, rbx
    EPILOGUE

# node_go(index): its dependencies start, in sequence or 8 at a time; with none left, its program
node_go:
    PROLOGUE
    mov ebx, edi
    call node_ptr
    mov r12, rax
    cmp dword ptr [r12 + RN_state], RS_WAIT
    jne 9f
    cmp dword ptr [r12 + RN_left], 0
    jne 1f
    # its turn
    mov dword ptr [r12 + RN_state], RS_RUN
    mov rax, [r12 + RN_tr]
    mov rdi, [rax + TRC_term]
    call term_start
    EPILOGUE
1:  # the dependencies it may start now
    mov rax, [r12 + RN_df]
    mov r13d, 1
    cmp dword ptr [rax + DF_order], 2
    jne 2f
    mov r13d, PARALLEL_MAX
2:  mov eax, [r12 + RN_next]
    cmp eax, [r12 + RN_nkids]
    jae 9f
    cmp [r12 + RN_running], r13d
    jae 9f
    inc dword ptr [r12 + RN_next]
    inc dword ptr [r12 + RN_running]
    mov edi, [r12 + rax*4 + RN_kids]
    call node_go
    jmp 2b
9:  EPILOGUE

# node_done(index, ok): a node's program ended (ok: exit 0) or became ready, or it could not run:
#   its parent goes on, or fails with the tabs above it saying why; the root's callback hears it
node_done:
    PROLOGUE 16
    mov ebx, edi
    mov r14d, esi
    call node_ptr
    mov r12, rax
    mov r13d, [r12 + RN_parent]
    cmp r13d, -1
    jne 1f
    # the root: its callback
    mov rax, [r12 + RN_cb]
    test rax, rax
    jz 8f
    mov rdi, [r12 + RN_cookie]
    mov esi, TASK_DONE
    test r14d, r14d
    jnz 11f
    mov esi, TASK_FAILED
11: call rax
    jmp 8f
1:  mov edi, r13d
    call node_ptr
    mov r15, rax
    cmp dword ptr [r15 + RN_state], RS_WAIT
    jne 8f                      # the parent failed already
    dec dword ptr [r15 + RN_running]
    dec dword ptr [r15 + RN_left]
    test r14d, r14d
    jz 2f
    mov edi, r13d
    call node_go
    jmp 8f
2:  # it fails, and the ones above it: "── not run: LABEL failed ──"
    mov rax, [r12 + RN_df]
    mov rsi, [rax + DF_label]
    test rax, rax
    jnz 3f
    lea rsi, [rip + .Lw_dependency]
3:  mov edi, r13d
    call node_fail
8:  mov rdi, r12
    call node_free
    EPILOGUE

# node_fail(index, label of what failed): it will not run: its tab says so, its parent fails too
node_fail:
    PROLOGUE
    mov ebx, edi
    mov r13, rsi
1:  mov edi, ebx
    call node_ptr
    mov r12, rax
    mov dword ptr [r12 + RN_state], RS_FAILED
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lw_not_run]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lw_failed]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rax, [r12 + RN_tr]
    mov rdi, [rax + TRC_term]
    mov rsi, [rip + tmp + SB_ptr]
    call term_note
    mov r14d, [r12 + RN_parent]
    cmp r14d, -1
    jne 2f
    # the root: its callback hears it failed
    mov rax, [r12 + RN_cb]
    test rax, rax
    jz 3f
    mov rdi, [r12 + RN_cookie]
    mov esi, TASK_FAILED
    call rax
3:  # a failed node with no dependency still running goes
    cmp dword ptr [r12 + RN_running], 0
    jne 9f
    mov rdi, r12
    call node_free
    EPILOGUE
2:  mov rax, [r12 + RN_df]
    mov r13, [rax + DF_label]
    cmp dword ptr [r12 + RN_running], 0
    jne 4f
    mov rdi, r12
    call node_free
4:  mov edi, r14d
    call node_ptr
    cmp dword ptr [rax + RN_state], RS_WAIT
    jne 9f
    dec dword ptr [rax + RN_running]
    mov ebx, r14d
    jmp 1b
9:  EPILOGUE

# task_event(TR*, TR*, event, code): a task tab's program started or ended: the nodes that wait on it
task_event:
    PROLOGUE 16
    mov rbx, rsi
    mov r12d, edx
    mov r13d, ecx
    cmp r12d, TE_STARTED
    jne 1f
    mov dword ptr [rbx + TRC_ready], 0
    EPILOGUE
1:  cmp r12d, TE_CLOSED
    jne 2f
    mov rdi, [rbx + TRC_df]
    test rdi, rdi
    jz 2f
    mov qword ptr [rbx + TRC_df], 0
    call df_release
2:  mov dword ptr [rbx + TRC_ready], 0
    # exit 0 is done; another code, a stop, a failure to start or a closed tab fail what waits
    xor r14d, r14d
    cmp r12d, TE_EXIT
    jne 3f
    test r13d, r13d
    jnz 3f
    mov r14d, 1
3:  xor r15d, r15d
4:  cmp r15d, RN_MAX
    jae 9f
    mov edi, r15d
    call node_ptr
    inc r15d
    cmp dword ptr [rax + RN_state], RS_RUN
    jne 4b
    cmp [rax + RN_tr], rbx
    jne 4b
    lea edi, [r15 - 1]
    mov esi, r14d
    call node_done
    jmp 4b
9:  EPILOGUE

# task_line(TR*, line, len): a background task's line: busy begins a new cycle (its problems go),
#   ready makes it done for what waits on it; both are told to its extension
task_line:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, -1
    je 9f
    mov r14, [rbx + TRC_df]
    test r14, r14
    jz 9f
    cmp dword ptr [r14 + DF_nready], 0
    je 9f
    # busy
    xor r15d, r15d
1:  cmp r15d, [r14 + DF_nbusy]
    jae 3f
    mov rdi, [r14 + r15*8 + DF_busy]
    mov rsi, r12
    mov rdx, r13
    call tpat_line
    test eax, eax
    jnz 2f
    inc r15d
    jmp 1b
2:  mov dword ptr [rbx + TRC_ready], 0
    mov rdi, [rbx + TRC_mrun]
    test rdi, rdi
    jz 21f
    call mrun_restart
21: mov rdi, [rbx + TRC_term]
    xor esi, esi
    xor edx, edx
    call term_set_problems
    lea rdi, [rip + .Le_busy_ev]
    mov rsi, rbx
    call send_task_event
    EPILOGUE
3:  cmp dword ptr [rbx + TRC_ready], 0
    jne 9f
    xor r15d, r15d
4:  cmp r15d, [r14 + DF_nready]
    jae 9f
    mov rdi, [r14 + r15*8 + DF_ready]
    mov rsi, r12
    mov rdx, r13
    call tpat_line
    test eax, eax
    jnz 5f
    inc r15d
    jmp 4b
5:  mov dword ptr [rbx + TRC_ready], 1
    lea rdi, [rip + .Le_ready_ev]
    mov rsi, rbx
    call send_task_event
    # what waits on it goes on
    xor r15d, r15d
6:  cmp r15d, RN_MAX
    jae 9f
    mov edi, r15d
    call node_ptr
    inc r15d
    cmp dword ptr [rax + RN_state], RS_RUN
    jne 6b
    cmp [rax + RN_tr], rbx
    jne 6b
    lea edi, [r15 - 1]
    mov esi, 1
    call node_done
    jmp 6b
9:  EPILOGUE

# send_task_event(prefix cstr, TR*): "0 task-ready TERM ERRORS WARNINGS" or "0 task-busy TERM"
send_task_event:
    PROLOGUE
    mov r12, rdi
    mov rbx, rsi
    cmp dword ptr [rbx + TRC_live], 0
    je 9f
    mov rax, [rbx + TRC_ext]
    FEAT_TEST rax, FEAT_TASKS
    jz 9f
    call ob_begin
    mov rdi, r12
    call ob_cstr
    mov rdi, [rbx + TRC_term]
    call ob_u64
    lea rax, [rip + .Le_ready_ev]
    cmp r12, rax
    jne 1f
    xor eax, eax
    xor edx, edx
    mov rdi, [rbx + TRC_mrun]
    test rdi, rdi
    jz 2f
    call mrun_counts
2:  mov r13d, edx
    push rax
    push rax
    mov edi, ' '
    call ob_byte
    pop rdi
    pop rax
    call ob_u64
    mov edi, ' '
    call ob_byte
    mov edi, r13d
    call ob_u64
1:  mov edi, 10
    call ob_byte
    mov rdi, [rbx + TRC_ext]
    call ob_send
9:  EPILOGUE

# ---------------- the user's commands ----------------

# recent_add(ext, id): the task the user ran goes first in Run Task's list
recent_add:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    # the last entry goes, the rest move down
    lea rax, [rip + recent]
    mov rdi, [rax + 16 * (RECENT_MAX - 1) + 8]
    call mem_free
    lea rdi, [rip + recent + 16]
    lea rsi, [rip + recent]
    mov edx, 16 * (RECENT_MAX - 1)
    call memmove
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    lea rcx, [rip + recent]
    mov [rcx], rbx
    mov [rcx + 8], rax
    EPILOGUE

# recent_rank(ext, id) -> eax its place among the recent ones (0 newest), or RECENT_MAX
recent_rank:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13d, RECENT_MAX
    jae 9f
    lea rax, [rip + recent]
    mov ecx, r13d
    shl ecx, 4
    cmp [rax + rcx], rbx
    jne 2f
    mov rdi, [rax + rcx + 8]
    test rdi, rdi
    jz 2f
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 9f
2:  inc r13d
    jmp 1b
9:  mov eax, r13d
    EPILOGUE

# picks_clear(): the palette's list goes
picks_clear:
    push rbx
    xor ebx, ebx
1:  cmp rbx, [rip + picks + VEC_len]
    jae 2f
    imul rax, rbx, 24
    add rax, [rip + picks + VEC_ptr]
    mov rdi, [rax + 8]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + picks + VEC_len], 0
    pop rbx
    ret

# picks_add(ext, DF*): a task into the palette's list
picks_add:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [r12 + DF_id]
    call strlen
    mov rdi, [r12 + DF_id]
    mov rsi, rax
    call mem_dup
    mov r13, rax
    lea rdi, [rip + picks]
    mov esi, 24
    call vec_push
    mov [rax], rbx
    mov [rax + 8], r13
    mov [rax + 16], r12
    EPILOGUE

# collect(mode, group): the tasks a command lists, into picks: Run Task: every published task, the
#   ones the user ran first, then build, test, the rest; a group: its tasks; Restart: the tasks with
#   a tab; Stop: the running ones; Show: the ones with a tab, running first
collect:
    PROLOGUE 16
    mov [rsp], edi
    mov [rsp + 4], esi
    call picks_clear
    # in passes: the recent ones (rank order), build, test, the rest
    xor r15d, r15d              # pass
.Lco_pass:
    cmp r15d, RECENT_MAX + 3
    jae 9f
    xor ebx, ebx
1:  cmp rbx, [rip + regs + VEC_len]
    jae 8f
    mov rax, [rip + regs + VEC_ptr]
    mov r12, [rax + rbx*8]
    inc rbx
    mov rax, [r12 + RG_ext]
    cmp dword ptr [rax + EXT_status], ES_REMOVED
    je 1b
    xor r13d, r13d
2:  cmp r13, [r12 + RG_dfs + VEC_len]
    jae 1b
    mov rax, [r12 + RG_dfs + VEC_ptr]
    mov r14, [rax + r13*8]
    inc r13
    mov rdi, [r12 + RG_ext]
    mov rsi, [r14 + DF_id]
    call recent_rank
    # this pass's ones only
    cmp r15d, RECENT_MAX
    jae 3f
    cmp eax, r15d
    jne 2b
    jmp 5f
3:  cmp eax, RECENT_MAX
    jne 2b                      # listed with the recent ones
    mov eax, r15d
    sub eax, RECENT_MAX         # 0 build, 1 test, 2 the rest
    mov ecx, [r14 + DF_group]
    cmp eax, 2
    je 4f
    inc eax
    cmp ecx, eax
    jne 2b
    jmp 5f
4:  test ecx, ecx
    jnz 2b
5:  # the command's own filter
    mov eax, [rsp]
    cmp eax, PICK_GROUP
    jne 6f
    mov ecx, [rsp + 4]
    cmp [r14 + DF_group], ecx
    jne 2b
    jmp 7f
6:  cmp eax, PICK_RUN
    je 7f
    mov rdi, [r12 + RG_ext]
    mov rsi, [r14 + DF_id]
    call tr_find_task
    test rax, rax
    jz 2b
    cmp dword ptr [rsp], PICK_STOP
    jne 7f
    mov rdi, [rax + TRC_term]
    call term_pid
    test eax, eax
    jz 2b
7:  mov rdi, [r12 + RG_ext]
    mov rsi, r14
    call picks_add
    jmp 2b
8:  inc r15d
    jmp .Lco_pass
9:  EPILOGUE

# open_picks(label): the palette with the picks: label, detail (the command, or its own), extension
open_picks:
    PROLOGUE
    mov rbx, rdi
    call palette_tasks_open
    xor r12d, r12d
1:  cmp r12, [rip + picks + VEC_len]
    jae 9f
    imul r13, r12, 24
    add r13, [rip + picks + VEC_ptr]
    mov r14, [r13 + 16]         # its DF (held by the registry while the palette is open)
    mov rdi, [r14 + DF_label]
    call strlen
    mov rdi, [r14 + DF_label]
    mov rsi, rax
    mov rdx, [r14 + DF_detail]
    cmp byte ptr [rdx], 0
    jne 2f
    mov rdx, [r14 + DF_cmd]
2:  mov rcx, r12
    call palette_tasks_add
    inc r12
    jmp 1b
9:  call palette_tasks_ready
    EPILOGUE

# tasks_chosen(n): the palette's pick
FN tasks_chosen
    PROLOGUE
    cmp rdi, [rip + picks + VEC_len]
    jae 9f
    imul rbx, rdi, 24
    add rbx, [rip + picks + VEC_ptr]
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    mov edx, [rip + pick_mode]
    call act
9:  EPILOGUE

# act(ext, id, mode): the command's action on a task: run it (a running one shows), restart, stop, show
act:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, rbx
    mov rsi, r12
    call tr_find_task
    mov r14, rax
    cmp r13d, PICK_RUN
    je .Lact_run
    cmp r13d, PICK_GROUP
    je .Lact_run
    test r14, r14
    jz 9f
    cmp r13d, PICK_STOP
    jne 1f
    mov rdi, [r14 + TRC_term]
    call term_stop
    EPILOGUE
1:  cmp r13d, PICK_SHOW
    jne 2f
    mov rdi, [r14 + TRC_term]
    mov esi, 1
    call term_reveal
    EPILOGUE
2:  # Restart: the chain again when it is not running, else its program (as Stop, then again)
    mov rdi, [r14 + TRC_term]
    call term_pid
    test eax, eax
    jz .Lact_run
    mov rdi, [r14 + TRC_term]
    call term_restart
    EPILOGUE
.Lact_run:
    mov rdi, rbx
    xor esi, esi
    call reg_of
    mov r15, rax
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rdi, r15
    mov rsi, r12
    call reg_find
    test rax, rax
    jz 9f
    mov [rip + req_ext], rbx
    mov qword ptr [rip + req_id], 0
    mov rdi, rax
    mov esi, PK_USER
    xor edx, edx
    xor ecx, ecx
    call start_request
9:  EPILOGUE

# cmd_run_task(): Run Task: every published task
FN cmd_run_task
    PROLOGUE
    mov dword ptr [rip + pick_mode], PICK_RUN
    mov edi, PICK_RUN
    xor esi, esi
    call collect
    cmp qword ptr [rip + picks + VEC_len], 0
    je .Lno_tasks
    lea rdi, [rip + .Lp_run]
    call open_picks
    EPILOGUE
.Lno_tasks:
    lea rdi, [rip + .Lt_no_tasks]
    call app_toast
    EPILOGUE

# group_task(group): Run Build Task, Run Test Task: the group's default task, else a list of the group
group_task:
    PROLOGUE
    mov ebx, edi
    mov dword ptr [rip + pick_mode], PICK_GROUP
    mov edi, PICK_GROUP
    mov esi, ebx
    call collect
    cmp qword ptr [rip + picks + VEC_len], 0
    je 7f
    # the first default one runs at once
    xor r12d, r12d
1:  cmp r12, [rip + picks + VEC_len]
    jae 3f
    imul rax, r12, 24
    add rax, [rip + picks + VEC_ptr]
    inc r12
    mov rcx, [rax + 16]
    cmp dword ptr [rcx + DF_default], 0
    je 1b
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov edx, PICK_RUN
    call act
    EPILOGUE
3:  cmp qword ptr [rip + picks + VEC_len], 1
    jne 4f
    mov rax, [rip + picks + VEC_ptr]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov edx, PICK_RUN
    call act
    EPILOGUE
4:  lea rdi, [rip + .Lp_build]
    cmp ebx, 1
    je 5f
    lea rdi, [rip + .Lp_test]
5:  call open_picks
    EPILOGUE
7:  lea rdi, [rip + .Lt_no_build]
    cmp ebx, 1
    je 8f
    lea rdi, [rip + .Lt_no_test]
8:  call app_toast
    EPILOGUE

FN cmd_run_build_task
    mov edi, 1
    jmp group_task

FN cmd_run_test_task
    mov edi, 2
    jmp group_task

# cmd_rerun_last_task(): the task the user ran last, again
FN cmd_rerun_last_task
    PROLOGUE
    lea rax, [rip + recent]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    test rsi, rsi
    jz 9f
    mov edx, PICK_RUN
    call act
9:  EPILOGUE

# one_or_list(mode, label): the tasks a command acts on; one acts at once
one_or_list:
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov [rip + pick_mode], ebx
    mov edi, ebx
    xor esi, esi
    call collect
    cmp qword ptr [rip + picks + VEC_len], 0
    je 8f
    cmp qword ptr [rip + picks + VEC_len], 1
    jne 2f
    mov rax, [rip + picks + VEC_ptr]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov edx, ebx
    call act
    EPILOGUE
2:  mov rdi, r12
    call open_picks
    EPILOGUE
8:  lea rdi, [rip + .Lt_none_running]
    cmp ebx, PICK_STOP
    je 9f
    lea rdi, [rip + .Lt_none_tabs]
9:  call app_toast
    EPILOGUE

FN cmd_restart_task
    mov edi, PICK_RESTART
    lea rsi, [rip + .Lp_restart]
    jmp one_or_list
FN cmd_stop_task
    mov edi, PICK_STOP
    lea rsi, [rip + .Lp_stop]
    jmp one_or_list
FN cmd_show_task
    mov edi, PICK_SHOW
    lea rsi, [rip + .Lp_show]
    jmp one_or_list

# cmd_clear_task_problems(): every problem the task matchers made goes
FN cmd_clear_task_problems
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + srcs + VEC_len]
    jae 9f
    mov rax, [rip + srcs + VEC_ptr]
    mov rdi, [rax + rbx*8]
    inc rbx
    call problems_clear
    jmp 1b
9:  EPILOGUE

# ---------------- the debugger's prelaunch ----------------

# tasks_run_named(name, cb, cookie) -> 0 started, -1 not found or ambiguous, -2 busy (see the top)
FN tasks_run_named
    PROLOGUE 16
    mov r12, rsi
    mov r13, rdx
    call find_named
    test rax, rax
    jz 8f
    mov [rip + req_ext], rdx
    mov qword ptr [rip + req_id], 0
    mov rdi, rax
    mov esi, PK_NAMED
    mov rdx, r12
    mov rcx, r13
    call start_request
    xor eax, eax
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# find_named(name) -> rax DF*, rdx its EXT*, or 0: OWNER/NAME:ID, a task id one extension publishes,
#   or a label one task has
find_named:
    PROLOGUE 32
    mov rbx, rdi
    mov qword ptr [rsp], 0      # found DF
    mov qword ptr [rsp + 8], 0  # its EXT
    mov dword ptr [rsp + 16], 0 # matches
    xor r12d, r12d
1:  cmp r12, [rip + regs + VEC_len]
    jae 8f
    mov rax, [rip + regs + VEC_ptr]
    mov r13, [rax + r12*8]
    inc r12
    xor r14d, r14d
2:  cmp r14, [r13 + RG_dfs + VEC_len]
    jae 1b
    mov rax, [r13 + RG_dfs + VEC_ptr]
    mov r15, [rax + r14*8]
    inc r14
    # OWNER/NAME:ID
    lea rdi, [rip + tmp]
    call sb_clear
    mov rdi, [r13 + RG_ext]
    call ext_full_name
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r15 + DF_id]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jnz 5f                      # exactly this one
    mov rdi, [r15 + DF_id]
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jnz 3f
    mov rdi, [r15 + DF_label]
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jz 2b
3:  inc dword ptr [rsp + 16]
    mov [rsp], r15
    mov rax, [r13 + RG_ext]
    mov [rsp + 8], rax
    jmp 2b
5:  mov rax, r15
    mov rdx, [r13 + RG_ext]
    EPILOGUE
8:  xor eax, eax
    cmp dword ptr [rsp + 16], 1
    jne 9f
    mov rax, [rsp]
    mov rdx, [rsp + 8]
9:  EPILOGUE

# ---------------- for the tests ----------------

# tasks_dump(sb): "OWNER/NAME id=ID group=build|test|- default=0|1 label=LABEL" per published task
#   (print-tasks)
FN tasks_dump
    PROLOGUE
    mov r15, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + regs + VEC_len]
    jae 9f
    mov rax, [rip + regs + VEC_ptr]
    mov r12, [rax + rbx*8]
    inc rbx
    xor r13d, r13d
2:  cmp r13, [r12 + RG_dfs + VEC_len]
    jae 1b
    mov rax, [r12 + RG_dfs + VEC_ptr]
    mov r14, [rax + r13*8]
    inc r13
    mov rdi, [r12 + RG_ext]
    call ext_full_name
    mov rdi, r15
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Ld_id]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, [r14 + DF_id]
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Ld_group]
    call sb_push_cstr
    mov eax, [r14 + DF_group]
    lea rcx, [rip + group_words]
    mov rsi, [rcx + rax*8]
    mov rdi, r15
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Ld_default]
    call sb_push_cstr
    mov rdi, r15
    mov esi, [r14 + DF_default]
    call sb_push_u64
    mov rdi, r15
    lea rsi, [rip + .Ld_label]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, [r14 + DF_label]
    call sb_push_cstr
    mov rdi, r15
    mov esi, 10
    call sb_push_byte
    jmp 2b
9:  EPILOGUE

.section .rodata
.Lw_ok: .asciz "ok "
.Lw_error: .asciz "error "
.Lw_and: .asciz ", and "
.Lw_task_it: .asciz " task it depends on"
.Lw_tasks_it: .asciz " tasks it depends on"
.Lw_task_key: .asciz "task:"
.Lw_not_run: .asciz "not run: "
.Lw_failed: .asciz " failed"
.Lw_dependency: .asciz "a dependency"
.Lv_set: .asciz "tasks-set"
.Lv_start: .asciz "task-start"
.Lv_run: .asciz "task-run"
.Le_unknown: .asciz "unknown no such request"
.Le_needs: .asciz "needs terminal=run"
.Le_syntax: .asciz "syntax"
.Le_syntax_sp: .asciz "syntax "
.Le_syntax_def: .asciz "syntax definition: "
.Le_trailing: .asciz "syntax bytes after the last definition"
.Le_count: .asciz "syntax the count of tasks"
.Le_toobig: .asciz "toobig 1000 tasks, 4 MB of definitions in all"
.Le_task: .asciz "task "
.Le_twice: .asciz ": id listed twice"
.Le_nodep: .asciz ": depends: no task \""
.Le_cycle: .asciz ": depends: a cycle"
.Le_notask: .asciz "notask no such published task"
.Le_run_nodep: .asciz "syntax definition: depends: names a task that is not published"
.Le_busy: .asciz "busy"
.Le_busy_run: .asciz "busy 32 tasks waiting or running, 8 deep"
.Le_cancelled: .asciz "cancelled"
.Le_ready_ev: .asciz "0 task-ready "
.Le_busy_ev: .asciz "0 task-busy "
.Lp_run: .asciz "Run Task"
.Lp_build: .asciz "Run Build Task"
.Lp_test: .asciz "Run Test Task"
.Lp_restart: .asciz "Restart Task"
.Lp_stop: .asciz "Stop Task"
.Lp_show: .asciz "Show Task"
.Lt_no_tasks: .asciz "No tasks: extensions publish them (the Tasks extension finds them in your project)"
.Lt_no_build: .asciz "No build task: Run Task lists every task"
.Lt_no_test: .asciz "No test task: Run Task lists every task"
.Lt_none_running: .asciz "No task is running"
.Lt_none_tabs: .asciz "No task has run"
.Ld_id: .asciz " id="
.Ld_group: .asciz " group="
.Ld_default: .asciz " default="
.Ld_label: .asciz " label="
.Ld_dash: .asciz "-"
.Ld_build: .asciz "build"
.Ld_test: .asciz "test"
.p2align 3
group_words: .quad .Ld_dash, .Ld_build, .Ld_test

.bss
why_buf: .zero 512
