# launch.ini's questions (docs/guide.md "Debugging"): ${ask:PROMPT} asks for text, ${pick:PROMPT|A|B}
# offers a list, ${process} a list of the running processes (their ids). dcfg_prepare stops at the
# first one without an answer (dask_value), dap_start asks (dask_begin), and the answer starts the
# launch again (dask_answer, dask_chosen) until every question of the configuration is answered.
.include "rhun.inc"

.equ DQ_ASK, 1
.equ DQ_PICK, 2
.equ DQ_PROCESS, 3
.equ DQ_PS_MAX, 1048576         # ps output kept
.equ DQ_ROWS_MAX, 2000          # processes offered

.bss
.p2align 3
answers: .zero SB_SIZE          # "KEY" TAB "VALUE" LF for each answered question
need_key: .zero SB_SIZE         # the question to ask: the variable's text (ask:Process id)
need_kind: .long 0              # DQ_*, 0 none
pend_nodebug: .long 0
resuming: .long 0               # 1 while an answer starts the launch again
ps_pid: .long 0
.p2align 3
pend_name: .zero SB_SIZE        # the configuration waiting for the answer
label: .zero SB_SIZE            # the prompt's text (NUL-terminated)
items: .zero SB_SIZE            # the offered values, LF separated, in row order
psout: .zero SB_SIZE

.data
ps_fd: .long -1                 # ${process}: ps's output while it runs

.text

# dask_value(name ptr, len, out sb) -> eax 1 with the answer appended to out, 2 when it is a question
#   without an answer yet (the first such one is remembered), 0 when the name is not a question
FN dask_value
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov ebx, DQ_PROCESS
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lv_process]
    call str_eq_cstr
    test eax, eax
    jnz 1f
    mov ebx, DQ_ASK
    cmp r13, 4
    jb 8f
    cmp dword ptr [r12], 0x3a6b7361     # "ask:"
    je 1f
    mov ebx, DQ_PICK
    cmp r13, 5
    jb 8f
    cmp dword ptr [r12], 0x6b636970     # "pick"
    jne 8f
    cmp byte ptr [r12 + 4], ':'
    jne 8f
1:  # answered?
    mov r15, [rip + answers + SB_ptr]
    mov rcx, [rip + answers + SB_len]
    add rcx, r15
2:  cmp r15, rcx
    jae 5f
    # this line: KEY TAB VALUE LF
    mov rax, r15
21: cmp byte ptr [rax], 9
    je 22f
    inc rax
    jmp 21b
22: mov rdx, rax
    sub rdx, r15                # the key's length
    lea r8, [rax + 1]           # the value
    mov r9, r8
23: cmp byte ptr [r9], 10
    je 24f
    inc r9
    jmp 23b
24: cmp rdx, r13
    jne 25f
    push rcx
    push r8
    push r9
    push r9
    mov rdi, r15
    mov rsi, r12
    call memeq
    pop r9
    pop r9
    pop r8
    pop rcx
    test eax, eax
    jz 25f
    mov rdi, r14
    mov rsi, r8
    mov rdx, r9
    sub rdx, r8
    call sb_push
    mov eax, 1
    EPILOGUE
25: lea r15, [r9 + 1]
    jmp 2b
5:  # not yet: the first question without an answer is the one to ask
    cmp dword ptr [rip + need_kind], 0
    jne 6f
    mov [rip + need_kind], ebx
    lea rdi, [rip + need_key]
    mov rsi, r12
    mov rdx, r13
    call sb_set_dq
6:  mov eax, 2
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# dask_starting(): dap_start begins a launch; one the user starts forgets the earlier answers
FN dask_starting
    mov dword ptr [rip + need_kind], 0
    cmp dword ptr [rip + resuming], 0
    jne 1f
    mov qword ptr [rip + answers + SB_len], 0
1:  ret

# dask_done(): the configuration was prepared: its answers are spent
FN dask_done
    mov qword ptr [rip + answers + SB_len], 0
    mov dword ptr [rip + need_kind], 0
    ret

# dask_begin(name ptr, len, nodebug): ask the remembered question; the launch waits for the answer
FN dask_begin
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov [rip + pend_nodebug], edx
    cmp r12, [rip + pend_name + SB_ptr]
    je 20f                      # an answer's launch asking again: the name is ours already
    lea rdi, [rip + pend_name]
    mov rsi, r12
    mov rdx, r13
    call sb_set_dq
20: mov eax, [rip + need_kind]
    cmp eax, DQ_PROCESS
    je .Lb_process
    # the prompt's text: what follows ask: or pick:, up to the first |
    mov r12, [rip + need_key + SB_ptr]
    mov r13, [rip + need_key + SB_len]
    mov ecx, 4
    cmp eax, DQ_PICK
    jne 1f
    mov ecx, 5
1:  lea r14, [r12 + rcx]        # the text
    lea r15, [r12 + r13]        # the key's end
    mov rcx, r14
2:  cmp rcx, r15
    jae 3f
    cmp byte ptr [rcx], '|'
    je 3f
    inc rcx
    jmp 2b
3:  mov rbx, rcx                # the choices start after it
    lea rdi, [rip + label]
    mov rsi, r14
    mov rdx, rcx
    sub rdx, r14
    call sb_set_dq
    lea rdi, [rip + label]
    xor esi, esi
    call sb_push_byte
    cmp dword ptr [rip + need_kind], DQ_ASK
    jne 4f
    mov rdi, [rip + label + SB_ptr]
    call dview_ask_launch
    EPILOGUE
4:  # pick: the choices, | separated
    lea rdi, [rip + items]
    call sb_clear
    mov rdi, [rip + label + SB_ptr]
    mov dword ptr [rip + g_dpick_kind], 1
    call palette_dpick_open
    xor r13d, r13d              # rows
5:  cmp rbx, r15
    jae 7f
    inc rbx                     # the |
    mov r14, rbx
6:  cmp rbx, r15
    jae 61f
    cmp byte ptr [rbx], '|'
    je 61f
    inc rbx
    jmp 6b
61: mov rdx, rbx
    sub rdx, r14
    jz 5b
    push rdx
    push rdx
    lea rdi, [rip + items]
    mov rsi, r14
    call sb_push
    lea rdi, [rip + items]
    mov esi, 10
    call sb_push_byte
    pop rsi
    pop rsi
    mov rdi, r14
    mov rdx, r13
    call palette_choose_add
    inc r13d
    jmp 5b
7:  call palette_choose_ready
    EPILOGUE
.Lb_process:
    call ps_start
    EPILOGUE

# dask_answer(ptr, len): the text typed for ${ask:}: the launch starts again
FN dask_answer
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp dword ptr [rip + need_kind], 0
    je 9f
    call answer_add
9:  EPILOGUE

# dask_chosen(row): the row picked for ${pick:} or ${process}
FN dask_chosen
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + need_kind], 0
    je 9f
    # the row's value: the row-th line of items
    mov r12, [rip + items + SB_ptr]
    mov r14, r12
    add r14, [rip + items + SB_len]
1:  cmp r12, r14
    jae 9f
    mov r13, r12
2:  cmp byte ptr [r13], 10
    je 3f
    inc r13
    jmp 2b
3:  test rbx, rbx
    jz 4f
    dec rbx
    lea r12, [r13 + 1]
    jmp 1b
4:  sub r13, r12
    call answer_add
9:  EPILOGUE

# answer_add(): r12/r13 is the answer to need_key: kept, then the launch starts again
answer_add:
    PROLOGUE
    lea rdi, [rip + answers]
    mov rsi, [rip + need_key + SB_ptr]
    mov rdx, [rip + need_key + SB_len]
    call sb_push
    lea rdi, [rip + answers]
    mov esi, 9
    call sb_push_byte
    # one line: line breaks become spaces
    xor ebx, ebx
1:  cmp rbx, r13
    jae 2f
    movzx esi, byte ptr [r12 + rbx]
    cmp esi, 10
    je 11f
    cmp esi, 9
    jne 12f
11: mov esi, ' '
12: lea rdi, [rip + answers]
    call sb_push_byte
    inc rbx
    jmp 1b
2:  lea rdi, [rip + answers]
    mov esi, 10
    call sb_push_byte
    mov dword ptr [rip + need_kind], 0
    mov dword ptr [rip + resuming], 1
    mov rdi, [rip + pend_name + SB_ptr]
    mov rsi, [rip + pend_name + SB_len]
    mov edx, [rip + pend_nodebug]
    call dap_start
    mov dword ptr [rip + resuming], 0
    EPILOGUE

# ---------------- ${process}: ps -A -o pid=,comm= ----------------

# ps_start(): ps runs; its rows become the pick list when its output ends (ps_on_out)
ps_start:
    PROLOGUE 48
    cmp dword ptr [rip + ps_fd], 0
    jge 9f                      # one already runs
    lea rdi, [rsp]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js 8f
    lea rdi, [rsp + 8]          # its input: at once at its end
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js 7f
    lea rax, [rip + .Lps]
    mov [rsp + 16], rax
    lea rax, [rip + .Lps_a]
    mov [rsp + 24], rax
    lea rax, [rip + .Lps_o]
    mov [rsp + 32], rax
    lea rax, [rip + .Lps_fmt]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call uproc_env_make
    mov rbx, rax
    lea rdi, [rip + .Lps]       # argv[0] is the path to run
    mov rsi, rbx
    call uproc_which
    test rax, rax
    jz 5f
    mov [rsp + 16], rax
    lea rdi, [rsp + 16]
    mov rsi, rbx
    xor edx, edx
    mov ecx, [rsp + 8]          # in: the read end
    mov r8d, [rsp + 4]          # out: the write end
    mov r9d, [rsp + 4]          # errors too
    xor eax, eax
    push rax
    push rax
    call uproc_spawn
    add rsp, 16
    mov r12, rax
    mov rdi, [rsp + 16]
    call mem_free
    mov rdi, rbx
    call mem_free
    mov edi, [rsp + 4]
    SYS SYS_close
    mov edi, [rsp + 8]
    SYS SYS_close
    mov edi, [rsp + 12]
    SYS SYS_close
    test r12, r12
    jle 6f
    mov [rip + ps_pid], r12d
    mov eax, [rsp]
    mov [rip + ps_fd], eax
    mov edi, eax
    mov esi, F_SETFL
    mov edx, O_NONBLOCK
    SYS SYS_fcntl
    lea rdi, [rip + psout]
    call sb_clear
    mov edi, [rip + ps_fd]
    mov esi, POLLIN
    lea rdx, [rip + ps_on_out]
    xor ecx, ecx
    call watch_add
    EPILOGUE
6:  mov edi, [rsp]
    SYS SYS_close
    jmp 8f
5:  # no ps on the PATH
    mov rdi, rbx
    call mem_free
    lea r12, [rsp]
    xor r13d, r13d
51: mov edi, [r12 + r13*4]
    SYS SYS_close
    inc r13d
    cmp r13d, 4
    jb 51b
    jmp 8f
7:  mov edi, [rsp]
    SYS SYS_close
    mov edi, [rsp + 4]
    SYS SYS_close
8:  # no ps: the process id is asked for as text
    lea rdi, [rip + label]
    lea rsi, [rip + .Lm_pid]
    call sb_set_cstr_dq
    mov dword ptr [rip + need_kind], DQ_PROCESS
    mov rdi, [rip + label + SB_ptr]
    call dview_ask_launch
9:  EPILOGUE

# ps_on_out(fd, revents, ctx): ps's output; at its end the rows ("PID  NAME") become the list
ps_on_out:
    PROLOGUE
    mov r12d, edi
1:  mov rax, [rip + psout + SB_len]
    cmp rax, DQ_PS_MAX
    jae 3f
    lea rdi, [rip + psout]
    mov esi, 65536
    call sb_reserve
    mov edi, r12d
    mov rsi, rax
    mov edx, 65536
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 3f
    add [rip + psout + SB_len], rax
    jmp 1b
3:  mov edi, r12d
    call watch_remove
    mov edi, r12d
    SYS SYS_close
    mov dword ptr [rip + ps_fd], -1
    mov edi, [rip + ps_pid]
    mov esi, 1
    call uproc_wait
    cmp dword ptr [rip + need_kind], DQ_PROCESS
    jne 9f
    call ps_list
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ps_list(): the pick list of processes, their ids as the values
ps_list:
    PROLOGUE
    lea rdi, [rip + items]
    call sb_clear
    lea rdi, [rip + label]
    lea rsi, [rip + .Lm_process]
    call sb_set_cstr_dq
    mov rdi, [rip + label + SB_ptr]
    mov dword ptr [rip + g_dpick_kind], 1
    call palette_dpick_open
    mov r12, [rip + psout + SB_ptr]
    mov r15, r12
    add r15, [rip + psout + SB_len]
    xor ebx, ebx                # rows
1:  cmp r12, r15
    jae 8f
    cmp ebx, DQ_ROWS_MAX
    jae 8f
    # a line: spaces, PID, spaces, NAME
    mov r13, r12
2:  cmp r13, r15
    jae 3f
    cmp byte ptr [r13], 10
    je 3f
    inc r13
    jmp 2b
3:  mov r14, r12                # the pid's start
4:  cmp r14, r13
    jae 7f
    cmp byte ptr [r14], ' '
    jne 41f
    inc r14
    jmp 4b
41: mov rcx, r14
5:  cmp rcx, r13
    jae 51f
    movzx eax, byte ptr [rcx]
    sub eax, '0'
    cmp eax, 9
    ja 51f
    inc rcx
    jmp 5b
51: cmp rcx, r14
    je 7f                       # not a process line
    push rcx
    push rcx
    lea rdi, [rip + items]
    mov rsi, r14
    mov rdx, rcx
    sub rdx, r14
    call sb_push
    lea rdi, [rip + items]
    mov esi, 10
    call sb_push_byte
    pop rcx
    pop rcx
    mov rdi, r14
    mov rsi, r13
    sub rsi, r14
    mov edx, ebx
    call palette_choose_add
    inc ebx
7:  lea r12, [r13 + 1]
    jmp 1b
8:  call palette_choose_ready
    EPILOGUE

# sb_set_dq(sb, ptr, len), sb_set_cstr_dq(sb, cstr)
sb_set_dq:
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
    pop r13
    pop r12
    pop rbx
    ret
sb_set_cstr_dq:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    add rsp, 8
    pop r12
    pop rbx
    ret

.section .rodata
.Lv_process: .asciz "process"
.Lps: .asciz "ps"
.Lps_a: .asciz "-A"
.Lps_o: .asciz "-o"
.Lps_fmt: .asciz "pid=,comm="
.Lm_pid: .asciz "Process id"
.Lm_process: .asciz "Attach to which process?"
