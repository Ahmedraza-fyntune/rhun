# notebooks: kernels that run as the user (DECISIONS.md, decision 1). A notebook extension asks
# rhun to start its kernel (nb-exec): a program its manifest names in [needs] kernels, found on the
# user's PATH or given by path (an environment's python). rhun asks the user once per extension and
# project (runallow.s), starts it outside the sandbox with the login environment and a process group
# of its own (uproc.s), its output going to kernel-EXEC.log in the extension's state folder, and
# reports its end as "0 nb-exec-exit EXEC CODE". The extension talks to the kernel itself (Jupyter's
# sockets on the loopback). A kernel stops with its extension, 3 s after its notebook closes (time
# for the extension's own shutdown), and when rhun quits (uproc.s).
#
#   nbexec_request(ext, NB*, id, body, len) -> rax 0 answered or waiting for the user, else the
#       "code text" to answer with
#   nbexec_signal(ext, exec, which) -> rax 0 sent, else the "code text": which 0 interrupt,
#       1 terminate, 2 kill
#   nbexec_tick(), nbexec_timeout(), nbexec_ext_gone(ext), nbexec_nb_closed(ext, nb id)
#   nbexec_dump(sb): print-nb-exec, "exec=N nb=N pid=P state=asking|running" per kernel
.include "rhun.inc"

.equ NX_MAX, 32
.equ NX_PER_EXT, 4
.equ NX_ARGS_MAX, 256
.equ NX_ENVS_MAX, 64
.equ NX_ARG_MAX, 32768
.equ NX_CLOSE_MS, 3000
.equ NXS_FREE, 0
.equ NXS_ASKING, 1
.equ NXS_RUNNING, 2

STRUCT
F NX_ext, 8
F NX_nb, 8                      # the NB id it was started for
F NX_id, 8                      # EXEC
F NX_req, 8                     # the request waiting for the user's answer
F NX_argv, 8                    # owned, 0-ended, strings owned; argv[0] the path to run
F NX_envs, 8                    # owned, 0-ended: the request's NAME=VALUE strings
F NX_envp, 8                    # uproc_env_make's array (its strings borrowed)
F NX_cwd, 8                     # owned cstr
F NX_cmd, 8                     # owned cstr: the command as the question shows it
F NX_kill_at, 8                 # time_ms after which it is ended (its notebook closed), 0 none
F NX_pid, 4
F NX_state, 4
ENDSTRUCT NX_SIZE

.bss
.p2align 3
slots: .zero NX_SIZE * NX_MAX
seq: .quad 0
msg: .zero SB_SIZE

.text

# nbexec_request(ext, NB*, id, body, len): see the top of the file
FN nbexec_request
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov [rsp + 8], r8
    cmp dword ptr [rip + g_remote], 0
    jne .Lnr_remote             # a remote window's kernels would belong on its host
    mov rdi, rbx
    call live_of
    cmp eax, NX_PER_EXT
    jae .Lnr_busy
    call free_slot
    test rax, rax
    jz .Lnr_busy
    mov r14, rax
    mov [r14 + NX_ext], rbx
    mov rax, [r12 + NB_id]
    mov [r14 + NX_nb], rax
    mov [r14 + NX_req], r13
    mov rdi, r14
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call parse_into
    test rax, rax
    jnz .Lnr_fail
    mov rax, [r14 + NX_argv]
    mov rdi, rbx
    mov rsi, [rax]
    call prog_allowed
    test eax, eax
    jz .Lnr_needs
    # the user's environment with the request's variables; the program on its PATH
    mov rdi, [r14 + NX_envs]
    xor esi, esi
    xor edx, edx
    call uproc_env_make
    mov [r14 + NX_envp], rax
    mov rax, [r14 + NX_argv]
    mov rdi, [rax]
    mov rsi, [r14 + NX_envp]
    call uproc_which
    test rax, rax
    jz .Lnr_nofile
    mov rcx, [r14 + NX_argv]
    mov rdi, [rcx]
    mov [rcx], rax
    call mem_free
    # the folder: the notebook's own when none is given
    mov rdi, [r14 + NX_cwd]
    cmp byte ptr [rdi], 0
    jne 1f
    call mem_free
    mov qword ptr [r14 + NX_cwd], 0
    mov rax, [r12 + NB_host]
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz .Lnr_nofolder
    call strlen
    mov rcx, [r12 + NB_host]
    mov rdi, [rcx + DOC_path]
    mov rsi, rax
    call path_dirlen
    mov rcx, [r12 + NB_host]
    mov rdi, [rcx + DOC_path]
    mov rsi, rax
    call mem_dup
    mov [r14 + NX_cwd], rax
1:  mov rdi, [r14 + NX_cwd]
    call vfs_is_dir
    test eax, eax
    jz .Lnr_nofolder
    mov rdi, r14
    call make_cmd
    inc qword ptr [rip + seq]
    mov rax, [rip + seq]
    mov [r14 + NX_id], rax
    mov dword ptr [r14 + NX_state], NXS_ASKING
    mov rdi, rbx
    mov rsi, [r14 + NX_cmd]
    lea rdx, [rip + answered]
    mov rcx, r14
    call run_approve
    test eax, eax
    jz 8f                       # asked: the answer comes later
    js .Lnr_asking
    mov rdi, r14
    call start
8:  xor eax, eax
    EPILOGUE
.Lnr_busy:
    lea rax, [rip + .Le_busy]
    EPILOGUE
.Lnr_remote:
    lea rax, [rip + .Le_remote]
    EPILOGUE
.Lnr_asking:
    lea rax, [rip + .Le_asking]
    jmp .Lnr_drop
.Lnr_needs:
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    lea rsi, [rip + .Le_needs]
    call sb_push_cstr
    mov rax, [r14 + NX_argv]
    mov rdi, [rax]
    call base_name
    mov rsi, rax
    lea rdi, [rip + msg]
    call sb_push
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + msg + SB_ptr]
    jmp .Lnr_drop
.Lnr_nofile:
    lea rax, [rip + .Le_nofile]
    jmp .Lnr_drop
.Lnr_nofolder:
    lea rax, [rip + .Le_nofolder]
.Lnr_fail:
.Lnr_drop:
    push rax
    push rax
    mov rdi, r14
    call drop
    pop rax
    pop rax
    EPILOGUE

# answered(slot, allowed): the user's answer to the question nbexec_request asked
answered:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + NX_state], NXS_ASKING
    jne 9f
    test esi, esi
    jz 1f
    mov rdi, [rbx + NX_ext]
    mov rsi, [rbx + NX_nb]
    call nb_by_id
    test rax, rax
    jz 2f
    mov rdi, rbx
    call start
    EPILOGUE
1:  lea rsi, [rip + .Le_refused]
    jmp 3f
2:  lea rsi, [rip + .Le_stale]
3:  mov rdi, rbx
    call reply_error
    mov rdi, rbx
    call drop
9:  EPILOGUE

# start(slot): the program runs, its output into the log, and the request is answered "ok ID EXEC"
#   (else with the reason, and the slot is free)
start:
    PROLOGUE 16
    mov rbx, rdi
    mov dword ptr [rsp], -1
    mov dword ptr [rsp + 4], -1
    lea rdi, [rip + msg]
    call sb_clear
    mov rax, [rbx + NX_ext]
    lea rdi, [rip + msg]
    mov rsi, [rax + EXT_state]
    call sb_push_cstr
    lea rdi, [rip + msg]
    lea rsi, [rip + .Llog_head]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov rsi, [rbx + NX_id]
    call sb_push_u64
    lea rdi, [rip + msg]
    lea rsi, [rip + .Llog_tail]
    call sb_push_cstr
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js .Lst_fail
    mov [rsp], eax
    lea rdi, [rip + .Ldevnull]
    mov esi, O_RDWR | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lst_fail
    mov [rsp + 4], eax
    mov rdi, [rbx + NX_argv]
    mov rsi, [rbx + NX_envp]
    mov rdx, [rbx + NX_cwd]
    mov ecx, [rsp + 4]
    mov r8d, [rsp]
    mov r9d, [rsp]
    push 0
    push 0
    call uproc_spawn
    add rsp, 16
    mov r12, rax
    call close_fds
    test r12, r12
    jle .Lst_fail
    mov [rbx + NX_pid], r12d
    mov dword ptr [rbx + NX_state], NXS_RUNNING
    mov rdi, rbx
    call free_lists
    # ok ID EXEC
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lok]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov rsi, [rbx + NX_req]
    call sb_push_u64
    lea rdi, [rip + msg]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + msg]
    mov rsi, [rbx + NX_id]
    call sb_push_u64
    lea rdi, [rip + msg]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + NX_ext]
    mov rsi, [rip + msg + SB_ptr]
    mov rdx, [rip + msg + SB_len]
    call ext_send_checked
    EPILOGUE
.Lst_fail:
    call close_fds
    mov rdi, rbx
    lea rsi, [rip + .Le_start]
    call reply_error
    mov rdi, rbx
    call drop
    EPILOGUE
close_fds:                      # the log and the null device, in the caller's frame
    mov edi, [rsp + 8]
    test edi, edi
    js 1f
    SYS SYS_close
1:  mov edi, [rsp + 12]
    test edi, edi
    js 2f
    SYS SYS_close
2:  ret

# reply_error(slot, "code text"): "error ID code text" to the request waiting in the slot
reply_error:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + NX_ext]
    call ext_is_visible
    test eax, eax
    jz 9f
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lerror]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov rsi, [rbx + NX_req]
    call sb_push_u64
    lea rdi, [rip + msg]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + msg]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + NX_ext]
    mov rsi, [rip + msg + SB_ptr]
    mov rdx, [rip + msg + SB_len]
    call ext_send_checked
9:  EPILOGUE

# nbexec_signal(ext, exec, which): see the top of the file
FN nbexec_signal
    PROLOGUE
    mov r12d, edx
    call find
    test rax, rax
    jz 8f
    mov rbx, rax
    mov esi, SIGINT
    test r12d, r12d
    jz 1f
    mov esi, SIGTERM
    cmp r12d, 1
    je 1f
    mov esi, SIGKILL
1:
.ifdef WINDOWS
    test r12d, r12d             # Windows ends a job; it has no interrupt for another process
    jz 7f
.endif
    mov edi, [rbx + NX_pid]
    call uproc_signal
    xor eax, eax
    EPILOGUE
.ifdef WINDOWS
7:  lea rax, [rip + .Le_nointr]
    EPILOGUE
.endif
8:  lea rax, [rip + .Le_noexec]
    EPILOGUE

# find(ext, exec) -> rax its running slot, or 0
find:
    lea rax, [rip + slots]
    mov ecx, NX_MAX
1:  cmp dword ptr [rax + NX_state], NXS_RUNNING
    jne 2f
    cmp [rax + NX_ext], rdi
    jne 2f
    cmp [rax + NX_id], rsi
    je 9f
2:  add rax, NX_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
9:  ret

# nbexec_tick(): ended kernels are reported; one whose notebook closed long enough ago is ended
FN nbexec_tick
    PROLOGUE
    lea rbx, [rip + slots]
    mov r12d, NX_MAX
1:  cmp dword ptr [rbx + NX_state], NXS_RUNNING
    jne 5f
    mov rax, [rbx + NX_kill_at]
    test rax, rax
    jz 2f
    call time_ms
    cmp rax, [rbx + NX_kill_at]
    jb 2f
    mov qword ptr [rbx + NX_kill_at], 0
    mov edi, [rbx + NX_pid]
    mov esi, 1000
    call uproc_end
2:  mov edi, [rbx + NX_pid]
    mov esi, 1
    call uproc_wait
    cmp rax, -1
    je 5f
    mov r13, rax
    # 0 nb-exec-exit EXEC CODE
    mov rdi, [rbx + NX_ext]
    call ext_is_visible
    test eax, eax
    jz 4f
    lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lexit]
    call sb_push_cstr
    lea rdi, [rip + msg]
    mov rsi, [rbx + NX_id]
    call sb_push_u64
    lea rdi, [rip + msg]
    mov esi, ' '
    call sb_push_byte
    cmp r13, -2
    jne 3f
    lea rdi, [rip + msg]
    lea rsi, [rip + .Lkilled]
    call sb_push_cstr
    jmp 31f
3:  lea rdi, [rip + msg]
    mov rsi, r13
    call sb_push_u64
31: lea rdi, [rip + msg]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + NX_ext]
    mov rsi, [rip + msg + SB_ptr]
    mov rdx, [rip + msg + SB_len]
    call ext_send_checked
4:  mov rdi, rbx
    call drop
5:  add rbx, NX_SIZE
    dec r12d
    jnz 1b
    EPILOGUE

# nbexec_timeout() -> rax 200 while a kernel runs (its end is looked for), else -1
FN nbexec_timeout
    lea rax, [rip + slots]
    mov ecx, NX_MAX
1:  cmp dword ptr [rax + NX_state], NXS_RUNNING
    je 2f
    add rax, NX_SIZE
    dec ecx
    jnz 1b
    mov rax, -1
    ret
2:  mov eax, 200
    ret

# nbexec_ext_gone(ext): its question goes away and its kernels stop; nothing more is sent
FN nbexec_ext_gone
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + slots]
    mov r13d, NX_MAX
1:  cmp dword ptr [rbx + NX_state], NXS_FREE
    je 3f
    cmp [rbx + NX_ext], r12
    jne 3f
    cmp dword ptr [rbx + NX_state], NXS_ASKING
    jne 2f
    mov rdi, rbx
    call run_approve_cancel
    jmp 21f
2:  mov edi, [rbx + NX_pid]
    mov esi, 1000
    call uproc_end
21: mov rdi, rbx
    call drop
3:  add rbx, NX_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# nbexec_nb_closed(ext, nb id): its kernels end in 3 s unless they exit first; a question still open
#   goes away and its request is answered stale
FN nbexec_nb_closed
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + slots]
    mov r14d, NX_MAX
1:  cmp dword ptr [rbx + NX_state], NXS_FREE
    je 3f
    cmp [rbx + NX_ext], r12
    jne 3f
    cmp [rbx + NX_nb], r13
    jne 3f
    cmp dword ptr [rbx + NX_state], NXS_ASKING
    jne 2f
    mov rdi, rbx
    call run_approve_cancel
    mov rdi, rbx
    lea rsi, [rip + .Le_stale]
    call reply_error
    mov rdi, rbx
    call drop
    jmp 3f
2:  call time_ms
    add rax, NX_CLOSE_MS
    mov [rbx + NX_kill_at], rax
3:  add rbx, NX_SIZE
    dec r14d
    jnz 1b
    EPILOGUE

# nbexec_dump(sb): print-nb-exec
FN nbexec_dump
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + slots]
    mov r13d, NX_MAX
1:  cmp dword ptr [rbx + NX_state], NXS_FREE
    je 3f
    mov rdi, r12
    lea rsi, [rip + .Ld_exec]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NX_id]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_nb]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + NX_nb]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_pid]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rbx + NX_pid]
    call sb_push_u64
    lea rsi, [rip + .Ld_asking]
    cmp dword ptr [rbx + NX_state], NXS_ASKING
    je 2f
    lea rsi, [rip + .Ld_running]
2:  mov rdi, r12
    call sb_push_cstr
3:  add rbx, NX_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# ---------------- slots ----------------

# live_of(ext) -> eax its slots in use
live_of:
    lea rax, [rip + slots]
    mov ecx, NX_MAX
    xor edx, edx
1:  cmp dword ptr [rax + NX_state], NXS_FREE
    je 2f
    cmp [rax + NX_ext], rdi
    jne 2f
    inc edx
2:  add rax, NX_SIZE
    dec ecx
    jnz 1b
    mov eax, edx
    ret

# free_slot() -> rax a free slot (zeroed), or 0
free_slot:
    lea rax, [rip + slots]
    mov ecx, NX_MAX
1:  cmp dword ptr [rax + NX_state], NXS_FREE
    jne 2f
    cmp qword ptr [rax + NX_ext], 0
    je 9f
2:  add rax, NX_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
9:  ret

# drop(slot): its memory freed and the slot free
drop:
    PROLOGUE
    mov rbx, rdi
    call free_lists
    mov rdi, [rbx + NX_cmd]
    call mem_free
    mov rdi, rbx
    xor eax, eax
    mov ecx, NX_SIZE
    rep stosb
    EPILOGUE

# free_lists(slot): argv, the variables, the environment and the folder, freed
free_lists:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + NX_argv]
    call free_vec
    mov rdi, [rbx + NX_envs]
    call free_vec
    mov rdi, [rbx + NX_envp]
    call mem_free
    mov rdi, [rbx + NX_cwd]
    call mem_free
    xor eax, eax
    mov [rbx + NX_argv], rax
    mov [rbx + NX_envs], rax
    mov [rbx + NX_envp], rax
    mov [rbx + NX_cwd], rax
    EPILOGUE

# free_vec(array): a 0-ended array of owned strings, and the array
free_vec:
    PROLOGUE
    mov rbx, rdi
    test rdi, rdi
    jz 9f
    mov r12, rdi
1:  mov rdi, [r12]
    test rdi, rdi
    jz 2f
    call mem_free
    add r12, 8
    jmp 1b
2:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

# ---------------- the request's body ----------------

# parse_into(slot, body, len) -> rax 0 with argv, the variables and the folder in the slot, else
#   "code text". The body is test-exec's command body (docs/extensions/v1.1.md):
#   PROGRAM_LEN CWD_LEN ARGC ENVC LF PROGRAM CWD, ARGC arguments "LEN" LF bytes, ENVC variables
#   "LEN" LF NAME=VALUE
parse_into:
    PROLOGUE 32
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call nb_rd_begin
    call nb_rd_line
    cmp eax, 4
    jne .Lpi_syntax
    xor r12d, r12d
1:  mov edi, r12d               # the four counts
    call nb_rd_u64
    test edx, edx
    jz .Lpi_syntax
    mov [rsp + r12*8], rax
    inc r12d
    cmp r12d, 4
    jb 1b
    mov rax, [rsp]
    test rax, rax
    jz .Lpi_syntax
    cmp rax, 4096
    ja .Lpi_toobig
    cmp qword ptr [rsp + 8], 4096
    ja .Lpi_toobig
    cmp qword ptr [rsp + 16], NX_ARGS_MAX
    ja .Lpi_toobig
    cmp qword ptr [rsp + 24], NX_ENVS_MAX
    ja .Lpi_toobig
    # argv: the program, the arguments, 0
    mov rdi, [rsp + 16]
    lea rdi, [rdi*8 + 16]
    call mem_alloc
    mov [rbx + NX_argv], rax
    mov rdi, rax
    mov rcx, [rsp + 16]
    lea rcx, [rcx*8 + 16]
    xor eax, eax
    rep stosb
    mov rdi, [rsp + 24]
    lea rdi, [rdi*8 + 8]
    call mem_alloc
    mov [rbx + NX_envs], rax
    mov rdi, rax
    mov rcx, [rsp + 24]
    lea rcx, [rcx*8 + 8]
    xor eax, eax
    rep stosb
    mov rdi, [rsp]
    call take_string
    test rax, rax
    jz .Lpi_syntax
    mov rcx, [rbx + NX_argv]
    mov [rcx], rax
    mov rdi, [rsp + 8]
    call take_string
    test rax, rax
    jz .Lpi_syntax
    mov [rbx + NX_cwd], rax
    xor r12d, r12d
2:  cmp r12, [rsp + 16]
    jae 3f
    call take_counted
    test rax, rax
    jz .Lpi_syntax
    mov rcx, [rbx + NX_argv]
    mov [rcx + r12*8 + 8], rax
    inc r12
    jmp 2b
3:  xor r12d, r12d
4:  cmp r12, [rsp + 24]
    jae 5f
    call take_counted
    test rax, rax
    jz .Lpi_syntax
    mov rcx, [rbx + NX_envs]
    mov [rcx + r12*8], rax
    mov r13, rax
    mov rdi, rax
    call strlen
    mov rsi, rax
    mov rdi, r13
    call env_name_ok
    test eax, eax
    jz .Lpi_syntax
    inc r12
    jmp 4b
5:  call nb_rd_left
    test rax, rax
    jnz .Lpi_syntax
    xor eax, eax
    EPILOGUE
.Lpi_syntax:
    lea rax, [rip + .Le_syntax]
    EPILOGUE
.Lpi_toobig:
    lea rax, [rip + .Le_toobig]
    EPILOGUE

# take_counted() -> rax the next "LEN" LF record as an owned cstr, or 0 (malformed, too long, a NUL)
take_counted:
    sub rsp, 8
    call nb_rd_line
    cmp eax, 1
    jne 8f
    xor edi, edi
    call nb_rd_u64
    test edx, edx
    jz 8f
    cmp rax, NX_ARG_MAX
    ja 8f
    mov rdi, rax
    add rsp, 8
    jmp take_string
8:  xor eax, eax
    add rsp, 8
    ret

# take_string(n) -> rax the next n bytes as an owned cstr, or 0 (fewer left, or a NUL among them)
take_string:
    PROLOGUE
    mov r12, rdi
    call nb_rd_bytes
    test rax, rax
    jz 9f
    mov rbx, rax
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp byte ptr [rbx + rcx], 0
    je 8f
    inc rcx
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r12
    call mem_dup
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# env_name_ok(ptr, len) -> eax 1 for NAME=VALUE with NAME [A-Z_][A-Z0-9_]*
env_name_ok:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 8f
    movzx eax, byte ptr [rdi + rcx]
    cmp eax, '='
    je 6f
    inc rcx
    cmp eax, '_'
    je 1b
    lea edx, [rax - 'A']
    cmp edx, 25
    jbe 1b
    cmp rcx, 1                  # not a digit first
    je 8f
    lea edx, [rax - '0']
    cmp edx, 9
    jbe 1b
8:  xor eax, eax
    ret
6:  test rcx, rcx
    jz 8b
    mov eax, 1
    ret

# base_name(path cstr) -> rax its last component, rdx its length (".exe" left out on Windows)
base_name:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    mov rcx, rax
1:  test rcx, rcx
    jz 2f
    movzx eax, byte ptr [rbx + rcx - 1]
    cmp eax, '/'
    je 2f
.ifdef WINDOWS
    cmp eax, '\\'
    je 2f
.endif
    dec rcx
    jmp 1b
2:  lea rax, [rbx + rcx]
    mov rdx, r12
    sub rdx, rcx
.ifdef WINDOWS
    cmp rdx, 4
    jbe 9f
    mov ecx, [rax + rdx - 4]
    or ecx, 0x20202000
    cmp ecx, 0x6578652e         # ".exe"
    jne 9f
    sub rdx, 4
.endif
9:  EPILOGUE

# prog_allowed(ext, program cstr) -> eax 1 when its name (the last component of a path) is a word of
#   [needs] kernels, and a path is absolute
prog_allowed:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call base_name
    mov r13, rax
    mov r14, rdx
    test r14, r14
    jz 8f
    cmp r13, r12
    je 1f                       # a bare name
.ifdef WINDOWS
    cmp byte ptr [r12 + 1], ':' # C:\... or C:/...
    je 1f
    cmp byte ptr [r12], '\\'
    je 1f
    cmp byte ptr [r12], '/'
    jne 8f
.else
    cmp byte ptr [r12], '/'
    jne 8f
.endif
1:  lea rdi, [rip + msg]
    call sb_clear
    lea rdi, [rip + msg]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    lea rdi, [rip + msg]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + msg + SB_ptr]
    mov rsi, [rbx + EXT_nb_kernels]
    call list_has_word
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# make_cmd(slot): NX_cmd, the path and the arguments as the question shows them
make_cmd:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + msg]
    call sb_clear
    mov r12, [rbx + NX_argv]
1:  mov rsi, [r12]
    test rsi, rsi
    jz 2f
    cmp r12, [rbx + NX_argv]
    je 11f
    push rsi
    push rsi
    lea rdi, [rip + msg]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    pop rsi
11: lea rdi, [rip + msg]
    call sb_push_cstr
    add r12, 8
    jmp 1b
2:  mov rdi, [rip + msg + SB_ptr]
    mov rsi, [rip + msg + SB_len]
    call mem_dup
    mov [rbx + NX_cmd], rax
    EPILOGUE

.section .rodata
.Llog_head: .asciz "/kernel-"
.Llog_tail: .asciz ".log"
.Ldevnull: .asciz "/dev/null"
.Lok: .asciz "ok "
.Lerror: .asciz "error "
.Lexit: .asciz "0 nb-exec-exit "
.Lkilled: .asciz "killed"
.Le_busy: .asciz "busy at most 4 kernels an extension"
.Le_remote: .asciz "refused kernels do not run as the user in a remote window yet"
.Le_asking: .asciz "busy another question is open"
.Le_needs: .asciz "needs kernels="
.Le_nofile: .asciz "nofile the program was not found"
.Le_nofolder: .asciz "refused the folder does not exist"
.Le_refused: .asciz "refused the user did not allow it"
.Le_stale: .asciz "stale no such notebook"
.Le_start: .asciz "failed the program could not be started"
.Le_syntax: .asciz "syntax cannot parse the body"
.Le_toobig: .asciz "toobig over a limit of the command body"
.Le_noexec: .asciz "stale no such kernel"
.ifdef WINDOWS
.Le_nointr: .asciz "refused Windows cannot interrupt another program: use the kernel's own message"
.endif
.Ld_exec: .asciz "exec="
.Ld_nb: .asciz " nb="
.Ld_pid: .asciz " pid="
.Ld_asking: .asciz " state=asking\n"
.Ld_running: .asciz " state=running\n"
