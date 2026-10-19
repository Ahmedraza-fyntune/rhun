# debugger commands for the headless driver (--script, --control): control.s hands over the commands
# it does not know. debug-start NAME | debug-run NAME | debug-stop | debug-pause | debug-continue |
# debug-step over|into|out | debug-expand PATH | debug-collapse PATH | debug-watch add|remove EXPR |
# debug-eval EXPR | debug-forget | bp PATH LINE [cond=C] [hits=H] [log=L] | bp-toggle PATH LINE |
# bp-enable PATH LINE 0|1 | bp-function NAME [cond=C] | bp-clear | exc-filter TYPE FILTER 0|1 |
# wait-debug STATE [MS] | wait-console TEXT | print-debug | print-stack | print-vars | print-watch |
# print-console [N] | print-bps | print-dap-log | print-configs
.include "rhun.inc"

.bss
.p2align 3
outp: .quad 0                   # the caller's output SB
argb: .zero SB_SIZE
argb2: .zero SB_SIZE
optc: .zero SB_SIZE
opth: .zero SB_SIZE
optl: .zero SB_SIZE

.text

# debug_ctl(cmd ptr, len, rest ptr, len, out sb) -> rax the command's result (0), -1 when it is not
#   one of these
FN debug_ctl
    PROLOGUE
    mov r13, rdi
    mov r14, rsi
    mov rbx, rdx
    mov r12, rcx
    mov [rip + outp], r8
    lea r15, [rip + dctl_table]
1:  mov rdx, [r15]
    test rdx, rdx
    jz 8f
    mov rdi, r13
    mov rsi, r14
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add r15, 16
    jmp 1b
2:  call [r15 + 8]
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# next_arg: rbx/r12 (the rest) -> rax word, rdx its length
next_arg:
    mov rdi, rbx
    mov rsi, r12
    call next_word
    add rbx, rcx
    sub r12, rcx
    ret

# rest_trim -> rax, rdx: what is left of the line, trimmed
rest_trim:
    mov rdi, rbx
    mov rsi, r12
    jmp trim

# out_byte(b), out_cstr(s), out_sb(sb)
out_cstr:
    mov rsi, rdi
    mov rdi, [rip + outp]
    jmp sb_push_cstr

# frame(): the event loop's work for a moment, as control.s's waits do
frame:
    mov edi, 20
    call loop_poll
    call app_tick
.ifndef WINDOWS
    cmp dword ptr [rip + g_headless], 0
    je 1f
.endif
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

# debug-start NAME / debug-run NAME
c_start:
    xor edx, edx
    jmp start_common
c_run:
    mov edx, 1
start_common:
    push rdx
    push rdx
    call rest_trim
    pop rcx
    pop rcx
    mov rdi, rax
    mov rsi, rdx
    mov edx, ecx
    call dap_start
    xor eax, eax
    ret

c_stop:
    call dap_stop
    xor eax, eax
    ret

c_pause:
    call dap_pause
    xor eax, eax
    ret

c_continue:
    xor edi, edi
    call dap_resume
    xor eax, eax
    ret

# debug-step over|into|out
c_step:
    call next_arg
    mov r13, rax
    mov r14, rdx
    mov edi, 1
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Ls_into]
    call str_eq_cstr
    mov edi, 2
    test eax, eax
    jnz 1f
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Ls_out]
    call str_eq_cstr
    mov edi, 3
    test eax, eax
    jnz 1f
    mov edi, 1
1:  call dap_resume
    xor eax, eax
    ret

c_forget:
    call dap_forget_approvals
    xor eax, eax
    ret

# debug-expand PATH / debug-collapse PATH
c_expand:
    mov r15d, 1
    jmp expand_common
c_collapse:
    xor r15d, r15d
expand_common:
    call dap_focused
    test rax, rax
    jz 9f
    mov r13, rax
    call rest_trim
    mov rdi, r13
    mov rsi, rax
    call dap_find_node
    test eax, eax
    js 9f
    mov rdi, r13
    mov esi, eax
    test r15d, r15d
    jz 1f
    call vn_expand
    jmp 9f
1:  call vn_collapse
9:  mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    ret

# debug-watch add|remove EXPR
c_watch:
    call next_arg
    mov r13, rax
    mov r14, rdx
    call rest_trim
    mov r15, rax
    mov rbx, rdx
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Ls_remove]
    call str_eq_cstr
    mov rdi, r15
    mov rsi, rbx
    test eax, eax
    jnz 1f
    call dap_watch_add
    jmp 2f
1:  call dap_watch_remove
2:  call bp_save
    xor eax, eax
    ret

# debug-eval EXPR
c_eval:
    call rest_trim
    mov rdi, rax
    mov rsi, rdx
    call dap_eval
    xor eax, eax
    ret

# path_line() -> argb holds PATH (NUL-terminated), eax LINE; from the rest
path_line:
    push r13
    call next_arg
    lea rdi, [rip + argb]
    mov rsi, rax
    call sb_setz
    call next_arg
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    pop r13
    ret

# sb_setz(sb, ptr, len): exactly these bytes, NUL-terminated
sb_setz:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    pop r13
    pop r12
    pop rbx
    ret

# opts(): cond=, hits=, log= from the rest into optc, opth, optl (empty when absent); a value runs
#   to the next of these keys
opts:
    PROLOGUE
    lea rdi, [rip + optc]
    xor esi, esi
    xor edx, edx
    call sb_setz
    lea rdi, [rip + opth]
    xor esi, esi
    xor edx, edx
    call sb_setz
    lea rdi, [rip + optl]
    xor esi, esi
    xor edx, edx
    call sb_setz
    call rest_trim
    mov r13, rax
    lea r14, [rax + rdx]        # end
1:  cmp r13, r14
    jae 9f
    # which key starts here
    lea r15, [rip + opt_keys]
2:  mov rsi, [r15]
    test rsi, rsi
    jz 8f
    mov rdi, rsi
    call strlen
    mov rcx, rax
    mov rdx, r14
    sub rdx, r13
    cmp rdx, rcx
    jb 3f
    push rcx
    push rcx
    mov rdi, r13
    mov rsi, rcx
    mov rdx, [r15]
    call str_eq_n_cstr
    pop rcx
    pop rcx
    test eax, eax
    jnz 4f
3:  add r15, 16
    jmp 2b
4:  add r13, rcx                # the value: up to the next key at a word start
    mov rbx, r13
5:  cmp rbx, r14
    jae 6f
    cmp byte ptr [rbx], ' '
    jne 51f
    lea rdi, [rbx + 1]
    call key_at
    test eax, eax
    jnz 6f
51: inc rbx
    jmp 5b
6:  mov rdi, r13
    mov rsi, rbx
    sub rsi, r13
    call trim
    mov rdi, [r15 + 8]
    mov rsi, rax
    call sb_setz
    mov r13, rbx
7:  cmp r13, r14
    jae 9f
    cmp byte ptr [r13], ' '
    jne 1b
    inc r13
    jmp 7b
8:  inc r13
    jmp 1b
9:  EPILOGUE

# key_at(ptr) -> eax 1 when one of the option keys starts there (r14 the end)
key_at:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea r12, [rip + opt_keys]
1:  mov rdi, [r12]
    test rdi, rdi
    jz 8f
    call strlen
    mov rdx, r14
    sub rdx, rbx
    cmp rdx, rax
    jb 2f
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [r12]
    call str_eq_n_cstr
    test eax, eax
    jnz 9f
2:  add r12, 16
    jmp 1b
8:  xor eax, eax
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# str_eq_n_cstr(ptr, n, cstr) -> eax 1 when the n bytes are the cstr
str_eq_n_cstr:
    jmp str_eq_cstr

# bp PATH LINE [cond=C] [hits=H] [log=L]
c_bp:
    PROLOGUE
    call path_line
    mov r15d, eax
    call opts
    lea rdi, [rip + argb]
    call sb_ptr
    mov rdi, rax
    mov esi, r15d
    mov rdx, [rip + optc + SB_ptr]
    mov rcx, [rip + opth + SB_ptr]
    mov r8, [rip + optl + SB_ptr]
    call bp_set
    xor eax, eax
    EPILOGUE

# sb_ptr(sb) -> its bytes
sb_ptr:
    mov rax, [rdi + SB_ptr]
    ret

# bp-toggle PATH LINE
c_bp_toggle:
    PROLOGUE
    call path_line
    mov esi, eax
    mov rdi, [rip + argb + SB_ptr]
    call bp_toggle
    xor eax, eax
    EPILOGUE

# bp-enable PATH LINE 0|1
c_bp_enable:
    PROLOGUE
    call path_line
    mov esi, eax
    mov rdi, [rip + argb + SB_ptr]
    call bp_find
    test eax, eax
    js 9f
    mov r15d, eax
    call next_arg
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov edi, r15d
    mov esi, eax
    call bp_enable
9:  xor eax, eax
    EPILOGUE

# bp-function NAME [cond=C]
c_bp_function:
    PROLOGUE
    call next_arg
    lea rdi, [rip + argb]
    mov rsi, rax
    call sb_setz
    call opts
    mov rdi, [rip + argb + SB_ptr]
    mov rsi, [rip + optc + SB_ptr]
    call bp_function
    xor eax, eax
    EPILOGUE

c_bp_clear:
    call bp_clear_all
    xor eax, eax
    ret

# exc-filter TYPE FILTER 0|1
c_exc:
    PROLOGUE
    call next_arg
    lea rdi, [rip + argb]
    mov rsi, rax
    call sb_setz
    call next_arg
    lea rdi, [rip + argb2]
    mov rsi, rax
    call sb_setz
    call next_arg
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov ecx, eax
    mov rdi, [rip + argb + SB_ptr]
    mov rsi, [rip + argb2 + SB_ptr]
    mov rdx, [rip + argb2 + SB_len]
    call bp_exc_set
    xor eax, eax
    EPILOGUE

# wait-debug STATE [MS]: until the focused session is in that state (20 s by default); prints
#   debug=STATE with the state it is in
c_wait_debug:
    PROLOGUE
    call next_arg
    lea rdi, [rip + argb]
    mov rsi, rax
    call sb_setz
    call next_arg
    mov r13d, 20000
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov r13, rax
1:  call app_tick
    call time_ms
    lea r14, [rax + r13]
2:  call dap_focused
    lea r15, [rip + .Ls_none]
    test rax, rax
    jz 3f
    mov edi, [rax + DS_state]
    call dap_state_name
    mov r15, rax
    mov rdi, rax
    mov rsi, [rip + argb + SB_ptr]
    call strcmp_eq
    test eax, eax
    jz 3f
    # paused: once what the stop asked for has come (nothing in flight)
    call dap_focused
    cmp dword ptr [rax + DS_state], DSS_PAUSED
    jne 5f
    cmp dword ptr [rax + DS_npend], 0
    je 5f
3:  call time_ms
    cmp rax, r14
    jae 5f
    call frame
    jmp 2b
5:  lea rdi, [rip + .Ls_debug_eq]
    call out_cstr
    mov rdi, r15
    call out_cstr
    mov rdi, [rip + outp]
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# wait-console TEXT: until a console line holds TEXT (20 s at most)
c_wait_console:
    PROLOGUE
    call rest_trim
    lea rdi, [rip + argb]
    mov rsi, rax
    call sb_setz
    call app_tick
    call time_ms
    lea r14, [rax + 20000]
1:  mov rdi, [rip + argb + SB_ptr]
    mov rsi, [rip + argb + SB_len]
    call dcon_find
    test eax, eax
    jnz 9f
    call time_ms
    cmp rax, r14
    jae 9f
    call frame
    jmp 1b
9:  xor eax, eax
    EPILOGUE

c_print_debug:
    mov rdi, [rip + outp]
    call dap_dump
    xor eax, eax
    ret

c_print_stack:
    mov rdi, [rip + outp]
    call dap_stack_dump
    xor eax, eax
    ret

c_print_vars:
    mov rdi, [rip + outp]
    xor esi, esi
    call dap_vars_dump
    xor eax, eax
    ret

c_print_watch:
    mov rdi, [rip + outp]
    mov esi, 1
    call dap_vars_dump
    xor eax, eax
    ret

# print-console [N]
c_print_console:
    call next_arg
    xor esi, esi
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov rsi, rax
1:  mov rdi, [rip + outp]
    call dcon_dump
    xor eax, eax
    ret

c_print_bps:
    mov rdi, [rip + outp]
    call bp_dump
    xor eax, eax
    ret

c_print_dap_log:
    mov rdi, [rip + outp]
    call dap_log_dump
    xor eax, eax
    ret

# print-configs: launch.ini's configuration names, "config=NAME" per line
c_print_configs:
    PROLOGUE
    lea rdi, [rip + argb]
    call sb_clear
    lea rdi, [rip + argb]
    call dcfg_names
    mov r13, [rip + argb + SB_ptr]
    mov r14, [rip + argb + SB_len]
    add r14, r13
1:  cmp r13, r14
    jae 9f
    mov rcx, r13
2:  cmp byte ptr [rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov r15, rcx
    lea rdi, [rip + .Ls_config_eq]
    call out_cstr
    mov rdi, [rip + outp]
    mov rsi, r13
    mov rdx, r15
    sub rdx, r13
    inc rdx
    call sb_push
    lea r13, [r15 + 1]
    jmp 1b
9:  xor eax, eax
    EPILOGUE

.section .rodata
.Ls_into: .asciz "into"
.Ls_out: .asciz "out"
.Ls_remove: .asciz "remove"
.Ls_none: .asciz "none"
.Ls_debug_eq: .asciz "debug="
.Ls_config_eq: .asciz "config="
.Lk_cond: .asciz "cond="
.Lk_hits: .asciz "hits="
.Lk_log: .asciz "log="
.Lc_debug_start: .asciz "debug-start"
.Lc_debug_run: .asciz "debug-run"
.Lc_debug_stop: .asciz "debug-stop"
.Lc_debug_pause: .asciz "debug-pause"
.Lc_debug_continue: .asciz "debug-continue"
.Lc_debug_step: .asciz "debug-step"
.Lc_debug_expand: .asciz "debug-expand"
.Lc_debug_collapse: .asciz "debug-collapse"
.Lc_debug_watch: .asciz "debug-watch"
.Lc_debug_eval: .asciz "debug-eval"
.Lc_debug_forget: .asciz "debug-forget"
.Lc_bp: .asciz "bp"
.Lc_bp_toggle: .asciz "bp-toggle"
.Lc_bp_enable: .asciz "bp-enable"
.Lc_bp_function: .asciz "bp-function"
.Lc_bp_clear: .asciz "bp-clear"
.Lc_exc_filter: .asciz "exc-filter"
.Lc_wait_debug: .asciz "wait-debug"
.Lc_wait_console: .asciz "wait-console"
.Lc_print_debug: .asciz "print-debug"
.Lc_print_stack: .asciz "print-stack"
.Lc_print_vars: .asciz "print-vars"
.Lc_print_watch: .asciz "print-watch"
.Lc_print_console: .asciz "print-console"
.Lc_print_bps: .asciz "print-bps"
.Lc_print_dap_log: .asciz "print-dap-log"
.Lc_print_configs: .asciz "print-configs"
.p2align 3
opt_keys:
    .quad .Lk_cond, optc, .Lk_hits, opth, .Lk_log, optl, 0, 0
dctl_table:
    .quad .Lc_debug_start, c_start, .Lc_debug_run, c_run, .Lc_debug_stop, c_stop
    .quad .Lc_debug_pause, c_pause, .Lc_debug_continue, c_continue, .Lc_debug_step, c_step
    .quad .Lc_debug_expand, c_expand, .Lc_debug_collapse, c_collapse, .Lc_debug_watch, c_watch
    .quad .Lc_debug_eval, c_eval, .Lc_debug_forget, c_forget
    .quad .Lc_bp, c_bp, .Lc_bp_toggle, c_bp_toggle, .Lc_bp_enable, c_bp_enable
    .quad .Lc_bp_function, c_bp_function, .Lc_bp_clear, c_bp_clear, .Lc_exc_filter, c_exc
    .quad .Lc_wait_debug, c_wait_debug, .Lc_wait_console, c_wait_console
    .quad .Lc_print_debug, c_print_debug, .Lc_print_stack, c_print_stack
    .quad .Lc_print_vars, c_print_vars, .Lc_print_watch, c_print_watch
    .quad .Lc_print_console, c_print_console, .Lc_print_bps, c_print_bps
    .quad .Lc_print_dap_log, c_print_dap_log, .Lc_print_configs, c_print_configs
    .quad 0, 0
