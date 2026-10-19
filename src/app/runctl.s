# control commands of tasks and terminals (--script, --control), in control.s's ctl_tables
#   print-terminals                a line per terminal tab (term_programs_dump)
#   term-select TERM               that tab becomes the current one
#   term-run [--cwd DIR] [--env NAME=VALUE]... [--unset NAME]... [--title WORD] [--task] [--silent]
#            [--matcher NAME] [--matcher-file PATH] [--sh] -- ARGV...
#                                  a program in a tab of its own, as an extension's terminal runs one;
#                                  with --sh the rest is one command for /bin/sh -c (PowerShell on
#                                  Windows); up to 4 matchers (built-in, or a matcher's text in a file)
#                                  turn its lines into problems; prints "term=ID"
#   print-pattern PATTERN<TAB>LINE "match=0", "match=1 file=... line=..." or "error=REASON"
#   print-problems                 the Problems store, a line per problem
#   print-problems-tab             the Problems tab's rows
#   print-tasks                    published tasks: "OWNER/NAME id=ID group=G default=0|1 label=L"
#   print-terminal-records         extensions' terminals: "TERM ext=OWNER/NAME live=0|1 output=0|1 task=ID"
#   term-stop TERM | term-restart TERM | term-close TERM
#   wait-terminal TERM STATE [RUNS] until the tab is there and running, exited, stopped, failed or
#                                  ended (not running), having started RUNS times when given; 10 s
#                                  at most
#   print-uproc                    programs run as the user, and the login environment's state
#   print-allowed                  run approvals ("OWNER/NAME PROJECT")
#   run-approve OWNER/NAME COMMAND ask as an extension's first program in the project would; prints
#                                  "approve=allowed|asked|busy|noext"; print-approve: the answer since
#   print-approve                  "approve=none|yes|no"
.include "rhun.inc"

.equ RUN_ARGS, 64
.equ RUN_ENVS, 16

.bss
.p2align 3
approve_last: .long 0           # 0 none, 1 yes, 2 no
key_buf: .zero 48

.text

# each command for control.s's ctl_tables: fn(out, rest, rest len) -> 0, wrapping a handler below
#   that reads the rest from rbx, r12 and writes to r15
.macro TCTL name, handler
\name:
    PROLOGUE
    mov r15, rdi
    mov rbx, rsi
    mov r12, rdx
    call \handler
    xor eax, eax
    EPILOGUE
.endm
TCTL t_print_terminals, c_print_terminals
TCTL t_term_select, c_term_select
TCTL t_term_run, c_term_run
TCTL t_term_stop, c_term_stop
TCTL t_term_restart, c_term_restart
TCTL t_term_close, c_term_close
TCTL t_print_uproc, c_print_uproc
TCTL t_print_allowed, c_print_allowed
TCTL t_run_approve, c_run_approve
TCTL t_print_approve, c_print_approve
TCTL t_wait_terminal, c_wait_terminal
TCTL t_print_tasks, c_print_tasks
TCTL t_print_records, c_print_records
TCTL t_print_pattern, c_print_pattern
TCTL t_print_problems, c_print_problems
TCTL t_print_problems_tab, c_print_problems_tab

# rest_word() -> rax word, rdx its length: the next word of the rest (rbx, r12 move past it)
rest_word:
    mov rdi, rbx
    mov rsi, r12
    call next_word
    add rbx, rcx
    sub r12, rcx
    ret

# rest_term() -> the next word as a number
rest_term:
    sub rsp, 8
    call rest_word
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    add rsp, 8
    ret

c_print_terminals:
    sub rsp, 8
    mov rdi, r15
    call term_programs_dump
    add rsp, 8
    ret

c_term_select:
    sub rsp, 8
    call rest_term
    mov rdi, rax
    call term_select
    add rsp, 8
    ret

c_term_stop:
    sub rsp, 8
    call rest_term
    mov rdi, rax
    call term_stop
    add rsp, 8
    ret

c_term_restart:
    sub rsp, 8
    call rest_term
    mov rdi, rax
    call term_restart
    add rsp, 8
    ret

c_term_close:
    sub rsp, 8
    call rest_term
    mov rdi, rax
    call term_close
    add rsp, 8
    ret

c_print_uproc:
    sub rsp, 8
    mov rdi, r15
    call uproc_dump
    add rsp, 8
    ret

c_print_pattern:
    sub rsp, 8
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call tpat_dump
    add rsp, 8
    ret

c_print_problems:
    sub rsp, 8
    mov rdi, r15
    call problems_dump
    add rsp, 8
    ret

c_print_problems_tab:
    sub rsp, 8
    call problems_tick          # a change made in this command's frame shows at once
    mov rdi, r15
    call problems_tab_dump
    add rsp, 8
    ret

c_print_tasks:
    sub rsp, 8
    mov rdi, r15
    call tasks_dump
    add rsp, 8
    ret

c_print_records:
    sub rsp, 8
    mov rdi, r15
    call termproto_dump
    add rsp, 8
    ret

c_print_allowed:
    sub rsp, 8
    mov rdi, r15
    call run_allow_dump
    add rsp, 8
    ret

# wait-terminal TERM STATE [RUNS]
c_wait_terminal:
    PROLOGUE 16
    call rest_term
    mov r13, rax
    call rest_word
    mov rdi, rax
    mov rsi, rdx
    call state_word
    mov r14d, eax
    call rest_term
    mov [rsp], eax              # runs, 0 any
    call time_ms
    lea r15, [rax + 10000]
1:  mov rdi, r13
    call term_state
    cmp eax, -1
    je 4f                       # not there yet (an extension's terminal-open is on its way)
    cmp dword ptr [rsp], 0
    je 2f
    cmp edx, [rsp]
    jb 4f
2:  cmp r14d, eax
    je 9f
    cmp r14d, 4                 # ended: exited, stopped or failed
    jne 4f
    test eax, eax
    jz 4f
    cmp eax, 3
    jbe 9f
4:  call time_ms
    cmp rax, r15
    jae 9f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
9:  EPILOGUE

# state_word(ptr, len) -> 0 running, 1 exited, 2 stopped, 3 failed, 4 ended
state_word:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rax, [rip + state_words]
    mov rdx, [rax + r13*8]
    test rdx, rdx
    jz 2f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

# term-run: see the top of the file
c_term_run:
    PROLOGUE 1152
    # [rsp] PG, [rsp + 32] title, +40 shell command, +48 mode, +56 the copy of the rest,
    # +64 counts (argv, sets, unsets), +88 --sh, +96 out, +104 matchers, argv at +160, sets at
    # +704, unsets at +848
    mov [rsp + 96], r15
    xor eax, eax
    mov [rsp + 88], rax
    mov [rsp + 104], rax        # +104: the matchers (4), +136 their count, +144 the run's MR
    mov [rsp + 112], rax
    mov [rsp + 120], rax
    mov [rsp + 128], rax
    mov [rsp + 136], rax
    mov [rsp + PGM_cwd], rax
    mov [rsp + 32], rax
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], TK_TERMINAL
    mov [rsp + 64], rax
    mov [rsp + 72], rax
    mov [rsp + 80], rax
    lea rax, [rsp + 160]
    mov [rsp + PGM_argv], rax
    lea rax, [rsp + 704]
    mov [rsp + PGM_sets], rax
    lea rax, [rsp + 848]
    mov [rsp + PGM_unsets], rax
    mov rdi, rbx
    mov rsi, r12
    call mem_dup
    mov [rsp + 56], rax
    mov r13, rax                # the words are cut in place
    xor r14d, r14d              # 1 past "--"
.Ltr_word:
    # the next word: blanks skipped, then up to a blank, which becomes its NUL
1:  cmp byte ptr [r13], ' '
    jne 2f
    inc r13
    jmp 1b
2:  cmp byte ptr [r13], 0
    je .Ltr_run
    test r14d, r14d
    jz 3f
    cmp qword ptr [rsp + 88], 0         # --sh: the rest is the command
    jne .Ltr_command
3:  mov r12, r13
4:  cmp byte ptr [r13], 0
    je 5f
    cmp byte ptr [r13], ' '
    je 41f
    inc r13
    jmp 4b
41: mov byte ptr [r13], 0
    inc r13
5:  test r14d, r14d
    jnz .Ltr_arg
    mov rdi, r12
    lea rsi, [rip + .Lo_end]
    call strcmp_eq
    test eax, eax
    jz 6f
    mov r14d, 1
    jmp .Ltr_word
6:  lea r15, [rip + options]
7:  mov rsi, [r15]
    test rsi, rsi
    jz .Ltr_word                # not an option: left out
    mov rdi, r12
    call strcmp_eq
    test eax, eax
    jnz 8f
    add r15, 16
    jmp 7b
8:  jmp [r15 + 8]
.Ltr_arg:
    mov rax, [rsp + 64]
    cmp rax, RUN_ARGS
    jae .Ltr_word
    mov rcx, [rsp + PGM_argv]
    mov [rcx + rax*8], r12
    inc qword ptr [rsp + 64]
    jmp .Ltr_word
.Ltr_command:
    mov [rsp + 40], r13
.Ltr_run:
    # with --sh: sh -c COMMAND, or PowerShell
    mov rax, [rsp + 40]
    test rax, rax
    jz 1f
    lea rcx, [rip + .Lsh]
    mov [rsp + 160], rcx
.ifdef WINDOWS
    lea rcx, [rip + .Lnologo]
    mov [rsp + 168], rcx
    lea rcx, [rip + .Lnoprofile]
    mov [rsp + 176], rcx
    lea rcx, [rip + .Lcommand]
    mov [rsp + 184], rcx
    mov [rsp + 192], rax
    mov qword ptr [rsp + 64], 5
.else
    lea rcx, [rip + .Ldash_c]
    mov [rsp + 168], rcx
    mov [rsp + 176], rax
    mov qword ptr [rsp + 64], 3
.endif
1:  mov rax, [rsp + 64]
    test rax, rax
    jz .Ltr_none
    mov rcx, [rsp + PGM_argv]
    mov qword ptr [rcx + rax*8], 0
    mov rax, [rsp + 72]
    mov rcx, [rsp + PGM_sets]
    mov qword ptr [rcx + rax*8], 0
    mov rax, [rsp + 80]
    mov rcx, [rsp + PGM_unsets]
    mov qword ptr [rcx + rax*8], 0
    # the title: --title, else the command
    mov rsi, [rsp + 32]
    test rsi, rsi
    jnz 2f
    mov rsi, [rsp + 40]
    test rsi, rsi
    jnz 2f
    mov rsi, [rsp + 160]
2:  mov [rsp + 32], rsi
    # the matchers' run, before the program starts so that no line is missed
    mov qword ptr [rsp + 144], 0
    cmp qword ptr [rsp + 136], 0
    je 3f
    xor edi, edi
    mov rsi, [rsp + PGM_cwd]
    test rsi, rsi
    jnz 21f
    lea rsi, [rip + .Lempty]
21: mov rdi, rsi
    call term_run_folder
    mov r13, rax
    xor edi, edi
    mov rsi, r13
    xor edx, edx
    call mrun_new
    mov [rsp + 144], rax
    mov rdi, r13
    call mem_free
    xor r13d, r13d
22: cmp r13, [rsp + 136]
    jae 3f
    mov rdi, [rsp + 144]
    mov rsi, [rsp + r13*8 + 104]
    call mrun_add
    inc r13
    jmp 22b
3:  lea rdi, [rsp]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 48]
    xor ecx, ecx
    xor r8d, r8d
    call term_run
    mov r12, rax
    test r12, r12
    jle .Ltr_busy
    cmp qword ptr [rsp + 144], 0
    je 4f
    # its problems: a source of their own, labelled with the title
    mov rdi, r12
    call run_key
    mov rdi, rax
    mov rsi, [rsp + 32]
    call problems_source
    mov rdi, [rsp + 144]
    mov rsi, rax
    mov rdx, r12
    call mrun_bind
    mov rdi, r12
    lea rsi, [rip + mrun_tap]
    mov rdx, [rsp + 144]
    call term_set_tap
4:
    mov rdi, [rsp + 96]
    lea rsi, [rip + .Ls_term]
    call sb_push_cstr
    mov rdi, [rsp + 96]
    mov rsi, r12
    call sb_push_u64
    mov rdi, [rsp + 96]
    mov esi, 10
    call sb_push_byte
    jmp .Ltr_free
.Ltr_busy:
    mov rdi, [rsp + 96]
    lea rsi, [rip + .Ls_busy]
    call sb_push_cstr
    jmp .Ltr_free
.Ltr_none:
    mov rdi, [rsp + 96]
    lea rsi, [rip + .Ls_noargs]
    call sb_push_cstr
.Ltr_free:
    mov rdi, [rsp + 56]
    call mem_free
    EPILOGUE
# options: each takes the next word (o_value) or none
o_cwd:
    call o_value
    mov [rsp + PGM_cwd], rax
    jmp .Ltr_word
o_env:
    call o_value
    mov rcx, [rsp + 72]
    cmp rcx, RUN_ENVS
    jae .Ltr_word
    mov rdx, [rsp + PGM_sets]
    mov [rdx + rcx*8], rax
    inc qword ptr [rsp + 72]
    jmp .Ltr_word
o_unset:
    call o_value
    mov rcx, [rsp + 80]
    cmp rcx, RUN_ENVS
    jae .Ltr_word
    mov rdx, [rsp + PGM_unsets]
    mov [rdx + rcx*8], rax
    inc qword ptr [rsp + 80]
    jmp .Ltr_word
o_title:
    call o_value
    mov [rsp + 32], rax
    jmp .Ltr_word
o_task:
    mov qword ptr [rsp + 48], TK_TASK
    jmp .Ltr_word
o_matcher:
    call o_value
    mov r12, rax
    mov rdi, rax
    call strlen
    mov rdi, r12
    mov rsi, rax
    call matcher_builtin
    jmp o_add_matcher
o_matcher_file:
    call o_value
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz .Ltr_word
    mov r12, rax
    mov rdi, rax
    mov rsi, rdx
    call matcher_compile
    mov [rsp + 152], rax
    mov rdi, r12
    call mem_free
    mov rax, [rsp + 152]
o_add_matcher:
    test rax, rax
    jz .Ltr_word                # not a matcher: left out
    mov rcx, [rsp + 136]
    cmp rcx, 4
    jae .Ltr_word
    mov [rsp + rcx*8 + 104], rax
    inc qword ptr [rsp + 136]
    jmp .Ltr_word
o_silent:
    or qword ptr [rsp + 48], TRV_SILENT
    jmp .Ltr_word
o_sh:
    mov qword ptr [rsp + 88], 1
    jmp .Ltr_word
# run_key(TERM) -> "term-run:TERM", the Problems source of a term-run's matchers (until the next call)
run_key:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + key_buf]
    lea rsi, [rip + .Lkey]
    call cstr_copy
    mov rdi, rax
    mov rsi, rbx
    call fmt_u64
    mov byte ptr [rdi], 0
    lea rax, [rip + key_buf]
    pop rbx
    ret

# o_value() -> rax the next word, cut in place (r13 moves past it); "" at the end
o_value:
1:  cmp byte ptr [r13], ' '
    jne 2f
    inc r13
    jmp 1b
2:  mov rax, r13
3:  cmp byte ptr [r13], 0
    je 9f
    cmp byte ptr [r13], ' '
    je 4f
    inc r13
    jmp 3b
4:  mov byte ptr [r13], 0
    inc r13
9:  ret

# run-approve OWNER/NAME COMMAND
c_run_approve:
    PROLOGUE
    call rest_word
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call trim
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r14, rax
    mov dword ptr [rip + approve_last], 0
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + approve_done]
    xor ecx, ecx
    call run_approve
    mov ebx, eax
    mov rdi, r14
    call mem_free
    lea rsi, [rip + .Ls_allowed]
    cmp ebx, 1
    je 1f
    lea rsi, [rip + .Ls_asked]
    test ebx, ebx
    jz 1f
    lea rsi, [rip + .Ls_abusy]
1:  mov rdi, r15
    call sb_push_cstr
    EPILOGUE
8:  mov rdi, r15
    lea rsi, [rip + .Ls_noext]
    call sb_push_cstr
    EPILOGUE

# approve_done(cookie, allowed)
approve_done:
    mov eax, 2
    test esi, esi
    jz 1f
    mov eax, 1
1:  mov [rip + approve_last], eax
    ret

c_print_approve:
    sub rsp, 8
    mov eax, [rip + approve_last]
    lea rcx, [rip + approve_words]
    mov rsi, [rcx + rax*8]
    mov rdi, r15
    call sb_push_cstr
    add rsp, 8
    ret

.section .rodata
.Lc_print_terminals: .asciz "print-terminals"
.Lc_term_select: .asciz "term-select"
.Lc_term_run: .asciz "term-run"
.Lc_term_stop: .asciz "term-stop"
.Lc_term_restart: .asciz "term-restart"
.Lc_term_close: .asciz "term-close"
.Lc_print_uproc: .asciz "print-uproc"
.Lc_print_allowed: .asciz "print-allowed"
.Lc_run_approve: .asciz "run-approve"
.Lc_print_approve: .asciz "print-approve"
.Lc_wait_terminal: .asciz "wait-terminal"
.Lc_print_pattern: .asciz "print-pattern"
.Lc_print_problems: .asciz "print-problems"
.Lc_print_problems_tab: .asciz "print-problems-tab"
.Lc_print_tasks: .asciz "print-tasks"
.Lc_print_records: .asciz "print-terminal-records"
.Lw_running: .asciz "running"
.Lw_exited: .asciz "exited"
.Lw_stopped: .asciz "stopped"
.Lw_failed: .asciz "failed"
.Lw_ended: .asciz "ended"
.Lw_waiting: .asciz "waiting"
.Lo_end: .asciz "--"
.Lo_cwd: .asciz "--cwd"
.Lo_env: .asciz "--env"
.Lo_unset: .asciz "--unset"
.Lo_title: .asciz "--title"
.Lo_task: .asciz "--task"
.Lo_silent: .asciz "--silent"
.Lo_sh: .asciz "--sh"
.Lo_matcher: .asciz "--matcher"
.Lo_matcher_file: .asciz "--matcher-file"
.Lkey: .asciz "term-run:"
.Lempty: .asciz ""
.ifdef WINDOWS
.Lsh: .asciz "powershell.exe"
.Lnologo: .asciz "-NoLogo"
.Lnoprofile: .asciz "-NoProfile"
.Lcommand: .asciz "-Command"
.else
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.endif
.Ls_term: .asciz "term="
.Ls_busy: .asciz "term-run=busy\n"
.Ls_noargs: .asciz "term-run=noargs\n"
.Ls_allowed: .asciz "approve=allowed\n"
.Ls_asked: .asciz "approve=asked\n"
.Ls_abusy: .asciz "approve=busy\n"
.Ls_noext: .asciz "approve=noext\n"
.Ls_none: .asciz "approve=none\n"
.Ls_yes: .asciz "approve=yes\n"
.Ls_no: .asciz "approve=no\n"
.p2align 3
approve_words: .quad .Ls_none, .Ls_yes, .Ls_no
state_words: .quad .Lw_running, .Lw_exited, .Lw_stopped, .Lw_failed, .Lw_ended, .Lw_waiting, 0
.globl tasks_ctl
tasks_ctl:
    .quad .Lc_print_terminals, t_print_terminals, .Lc_term_select, t_term_select
    .quad .Lc_term_run, t_term_run, .Lc_term_stop, t_term_stop, .Lc_term_restart, t_term_restart
    .quad .Lc_term_close, t_term_close, .Lc_print_uproc, t_print_uproc
    .quad .Lc_print_allowed, t_print_allowed, .Lc_run_approve, t_run_approve
    .quad .Lc_print_approve, t_print_approve, .Lc_wait_terminal, t_wait_terminal
    .quad .Lc_print_pattern, t_print_pattern, .Lc_print_problems, t_print_problems
    .quad .Lc_print_problems_tab, t_print_problems_tab, .Lc_print_tasks, t_print_tasks
    .quad .Lc_print_records, t_print_records, 0, 0
options:
    .quad .Lo_cwd, o_cwd, .Lo_env, o_env, .Lo_unset, o_unset, .Lo_title, o_title
    .quad .Lo_task, o_task, .Lo_silent, o_silent, .Lo_sh, o_sh, .Lo_matcher, o_matcher
    .quad .Lo_matcher_file, o_matcher_file, 0, 0
