# control commands of tasks and terminals (--script, --control), in control.s's ctl_tables
#   print-terminals                a line per terminal tab (term_programs_dump)
#   term-select TERM               that tab becomes the current one
#   term-run [--cwd DIR] [--env NAME=VALUE]... [--unset NAME]... [--title WORD] [--task] [--silent]
#            [--sh] -- ARGV...     a program in a tab of its own, as an extension's terminal runs one;
#                                  with --sh the rest is one command for /bin/sh -c (PowerShell on
#                                  Windows); prints "term=ID"
#   term-stop TERM | term-restart TERM | term-close TERM
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

c_print_allowed:
    sub rsp, 8
    mov rdi, r15
    call run_allow_dump
    add rsp, 8
    ret

# term-run: see the top of the file
c_term_run:
    PROLOGUE 1152
    # [rsp] PG, [rsp + 32] title, +40 shell command, +48 mode, +56 the copy of the rest,
    # +64 counts (argv, sets, unsets), +88 --sh, +96 out, argv at +128, sets at +672, unsets at +816
    mov [rsp + 96], r15
    xor eax, eax
    mov [rsp + 88], rax
    mov [rsp + PG_cwd], rax
    mov [rsp + 32], rax
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], TK_TERMINAL
    mov [rsp + 64], rax
    mov [rsp + 72], rax
    mov [rsp + 80], rax
    lea rax, [rsp + 128]
    mov [rsp + PG_argv], rax
    lea rax, [rsp + 672]
    mov [rsp + PG_sets], rax
    lea rax, [rsp + 816]
    mov [rsp + PG_unsets], rax
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
    mov rcx, [rsp + PG_argv]
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
    mov [rsp + 128], rcx
.ifdef WINDOWS
    lea rcx, [rip + .Lnologo]
    mov [rsp + 136], rcx
    lea rcx, [rip + .Lnoprofile]
    mov [rsp + 144], rcx
    lea rcx, [rip + .Lcommand]
    mov [rsp + 152], rcx
    mov [rsp + 160], rax
    mov qword ptr [rsp + 64], 5
.else
    lea rcx, [rip + .Ldash_c]
    mov [rsp + 136], rcx
    mov [rsp + 144], rax
    mov qword ptr [rsp + 64], 3
.endif
1:  mov rax, [rsp + 64]
    test rax, rax
    jz .Ltr_none
    mov rcx, [rsp + PG_argv]
    mov qword ptr [rcx + rax*8], 0
    mov rax, [rsp + 72]
    mov rcx, [rsp + PG_sets]
    mov qword ptr [rcx + rax*8], 0
    mov rax, [rsp + 80]
    mov rcx, [rsp + PG_unsets]
    mov qword ptr [rcx + rax*8], 0
    # the title: --title, else the command
    mov rsi, [rsp + 32]
    test rsi, rsi
    jnz 2f
    mov rsi, [rsp + 40]
    test rsi, rsi
    jnz 2f
    mov rsi, [rsp + 128]
2:  lea rdi, [rsp]
    mov rdx, [rsp + 48]
    xor ecx, ecx
    xor r8d, r8d
    call term_run
    mov r12, rax
    test r12, r12
    jle .Ltr_busy
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
    mov [rsp + PG_cwd], rax
    jmp .Ltr_word
o_env:
    call o_value
    mov rcx, [rsp + 72]
    cmp rcx, RUN_ENVS
    jae .Ltr_word
    mov rdx, [rsp + PG_sets]
    mov [rdx + rcx*8], rax
    inc qword ptr [rsp + 72]
    jmp .Ltr_word
o_unset:
    call o_value
    mov rcx, [rsp + 80]
    cmp rcx, RUN_ENVS
    jae .Ltr_word
    mov rdx, [rsp + PG_unsets]
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
o_silent:
    or qword ptr [rsp + 48], TRV_SILENT
    jmp .Ltr_word
o_sh:
    mov qword ptr [rsp + 88], 1
    jmp .Ltr_word
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
.Lo_end: .asciz "--"
.Lo_cwd: .asciz "--cwd"
.Lo_env: .asciz "--env"
.Lo_unset: .asciz "--unset"
.Lo_title: .asciz "--title"
.Lo_task: .asciz "--task"
.Lo_silent: .asciz "--silent"
.Lo_sh: .asciz "--sh"
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
.globl tasks_ctl
tasks_ctl:
    .quad .Lc_print_terminals, t_print_terminals, .Lc_term_select, t_term_select
    .quad .Lc_term_run, t_term_run, .Lc_term_stop, t_term_stop, .Lc_term_restart, t_term_restart
    .quad .Lc_term_close, t_term_close, .Lc_print_uproc, t_print_uproc
    .quad .Lc_print_allowed, t_print_allowed, .Lc_run_approve, t_run_approve
    .quad .Lc_print_approve, t_print_approve, 0, 0
options:
    .quad .Lo_cwd, o_cwd, .Lo_env, o_env, .Lo_unset, o_unset, .Lo_title, o_title
    .quad .Lo_task, o_task, .Lo_silent, o_silent, .Lo_sh, o_sh, 0, 0
