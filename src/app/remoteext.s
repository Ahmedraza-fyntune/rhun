# remote hosts, extensions (the design's E3): in a remote window an extension runs on the host
# unless its manifest says where = local. Its files are copied once into the host's
# ~/.cache/rhun-remote/extensions/OWNER/NAME/VERSION-HASH (HASH: the local files' names, sizes and
# times, so a rebuilt development folder is copied again), from the installed folder when that
# holds what the host runs (a script, a WebAssembly module, the Linux build) and otherwise from its
# release's linux-x86_64 archive, fetched here once by extinstall.s's script into
# STATE/rhun/remote/extensions. Its state folder is the host's
# ~/.local/state/rhun/extensions/OWNER--NAME, and the agent holds it there with Landlock built
# from its [needs] as for a local extension (ragent.s, spawn MODE 3). The copy goes as pipelined
# requests answered later, so the window never waits for it; the extension waits idle meanwhile
# (EXT_remote_wait), and so does one whose host is not connected yet.
.include "rhun.inc"

.equ RX_MAX, 64
.equ RX_WINDOW, 4               # copy requests in flight
.equ RX_PART, 4194304           # a file goes in parts this big
.equ RX_TOTAL_MAX, 67108864     # an extension's files at most (an install's limit)
.equ RX_DEPTH, 16
.equ RX_PATH_MAX, 4000

.equ RXS_NEW, 0
.equ RXS_CHECK, 1               # is the host's folder there?
.equ RXS_FETCH, 2               # its Linux build is being downloaded here
.equ RXS_UPLOAD, 3
.equ RXS_RENAME, 4
.equ RXS_READY, 5
.equ RXS_FAILED, 6

STRUCT
F RX_ext, 8                     # EXT*, 0 for a free entry
F RX_state, 4                   # RXS_*
F RX_out, 4                     # requests in flight
F RX_err, 4                     # the copy's first failure (errno), 0
F RX_pid, 4                     # the download, 0
F RX_fd, 4                      # its output, -1
F RX_ran, 4                     # 1: it ran on the host (it starts again after a reconnect)
F RX_waitconn, 4                # 1: it waits for the host to connect
F RX_fresh, 4                   # 1: just made ready (the next start need not look again)
F RX_hdir, 8                    # cstr: the host's folder
F RX_part, 8                    # cstr: the host's folder being written
F RX_src, 8                     # cstr: the local folder copied
F RX_run, 8                     # cstr: run.linux-x86_64 (a program's), 0
F RX_fdir, 8                    # cstr: where a download goes, 0
F RX_files, SB_SIZE             # "d", "f" or "x" (executable) + relative path + NUL each, in walk order
F RX_next, 8                    # RX_files offset of the next to send
F RX_data, 8                    # the file being sent (mem_alloc'd), 0
F RX_dlen, 8
F RX_doff, 8
F RX_dpath, 8                   # its host path (mem_alloc'd)
F RX_dmode, 4
F RX_pad, 4
F RX_dl, SB_SIZE                # the download's output
F RX_tag, 112                   # the release tag fetched
F RX_why, 512                   # why it cannot run on the host
F RX_cwhy, 384                  # why the host does not hold it to its permissions
ENDSTRUCT RX_SIZE

.bss
.p2align 3
rx_tab: .zero RX_SIZE * RX_MAX
rx_wpath: .zero SB_SIZE         # the walk: the local path (reserved: dir_each holds it)
rx_wrel: .zero SB_SIZE          # and the part after the folder
rx_line: .zero SB_SIZE          # a request's line
rx_body: .zero SB_SIZE          # a request's body
rx_sbuf: .zero SB_SIZE          # the spawn's strings
rx_conf: .zero SB_SIZE          # its confinement block
rx_tmp: .zero SB_SIZE
rx_fp: .quad 0                  # the walk's hash
rx_total: .quad 0               # and its bytes
rx_depth: .long 0
rx_toolong: .long 0
rx_stat: .zero 144
rx_hstate: .zero 4200
rx_argv: .zero 8 * 300
rx_envv: .zero 8 * 400
rx_dlbuf: .zero 4096

.text

# remote_ext_remote(ext) -> eax 1 when it runs on the host: a remote window, and not where = local
FN remote_ext_remote
    xor eax, eax
    cmp dword ptr [rip + g_remote], 0
    je 9f
    cmp dword ptr [rdi + EXT_where_local], 0
    jne 9f
    mov eax, 1
9:  ret

# remote_ext_check(ext) -> rax 0, or why its manifest is refused: where = local may not need the
# project or the home folder (it sees the host's paths as names only, documents through rhun)
FN remote_ext_check
    xor eax, eax
    cmp dword ptr [rdi + EXT_where_local], 0
    je 9f
    test dword ptr [rdi + EXT_needs], NEEDS_PROJECT_READ | NEEDS_PROJECT_WRITE | NEEDS_HOME_READ
    jz 9f
    lea rax, [rip + .Lr_where_local]
9:  ret

# remote_ext_spawn(ext) -> rax the pid (EXT_pid, EXT_in and EXT_out set, the program running on
# the host), 0 while it waits (its files on their way, or the host not connected: it starts by
# itself later), or -errno with EXT_reason saying why it cannot. ext_spawn calls it with argv_vec
# and env_vec built as for a local start; they are rewritten for the host.
FN remote_ext_spawn
    PROLOGUE 16
    mov rbx, rdi
    mov esi, 1
    call rx_find
    test rax, rax
    jz .Lxs_full
    mov r12, rax
    call remote_is_up
    test eax, eax
    jz .Lxs_waitconn
    mov eax, [r12 + RX_state]
    cmp eax, RXS_READY
    je .Lxs_ready
    cmp eax, RXS_FAILED
    je .Lxs_new
    cmp eax, RXS_NEW
    jne .Lxs_wait               # on its way
.Lxs_new:
    mov dword ptr [rbx + EXT_remote_wait], 1
    mov dword ptr [rbx + EXT_status], ES_IDLE
    lea rax, [rip + .Lw_copy]
    mov [rbx + EXT_reason], rax
    mov rdi, r12
    call rx_continue
    cmp dword ptr [r12 + RX_state], RXS_FAILED
    jne .Lxs_wait
    lea rax, [r12 + RX_why]
    mov [rbx + EXT_reason], rax
    mov rax, -22
    EPILOGUE
.Lxs_ready:
    cmp dword ptr [r12 + RX_fresh], 0
    jne .Lxs_go
    # the same files as when they were copied? (a development folder may have been rebuilt)
    mov rax, [r12 + RX_hdir]
    mov [rsp], rax
    mov qword ptr [r12 + RX_hdir], 0
    mov rdi, r12
    call rx_prepare
    mov [rsp + 8], eax
    test eax, eax
    jnz .Lxs_changed
    mov rdi, [rsp]
    mov rsi, [r12 + RX_hdir]
    call strcmp_eq
    test eax, eax
    jz .Lxs_changed
    mov rdi, [rsp]
    call mem_free
    jmp .Lxs_go
.Lxs_changed:
    mov rdi, [rsp]
    call mem_free
    mov eax, [rsp + 8]
    cmp eax, 1
    je .Lxs_wait                # a download started
    test eax, eax
    js .Lxs_failed_now
    mov dword ptr [r12 + RX_state], RXS_NEW
    jmp .Lxs_new
.Lxs_failed_now:
    mov dword ptr [r12 + RX_state], RXS_FAILED
    mov dword ptr [rbx + EXT_remote_wait], 0
    lea rax, [r12 + RX_why]
    mov [rbx + EXT_reason], rax
    mov rax, -22
    EPILOGUE
.Lxs_go:
    mov dword ptr [r12 + RX_fresh], 0
    mov dword ptr [rbx + EXT_remote_wait], 0
    mov rdi, r12
    call rx_spawn
    EPILOGUE
.Lxs_waitconn:
    mov dword ptr [r12 + RX_waitconn], 1
    lea rax, [rip + .Lw_conn]
    mov [rbx + EXT_reason], rax
.Lxs_wait:
    mov dword ptr [rbx + EXT_remote_wait], 1
    mov dword ptr [rbx + EXT_status], ES_IDLE
    xor eax, eax
    EPILOGUE
.Lxs_full:
    lea rax, [rip + .Lr_full]
    mov [rbx + EXT_reason], rax
    mov rax, -12
    EPILOGUE

# remote_ext_tick(): copies held back by a full request table go on
FN remote_ext_tick
    PROLOGUE
    lea rbx, [rip + rx_tab]
    xor r12d, r12d
1:  cmp qword ptr [rbx + RX_ext], 0
    je 2f
    cmp dword ptr [rbx + RX_state], RXS_UPLOAD
    jne 2f
    mov rdi, rbx
    call rx_pump
2:  add rbx, RX_SIZE
    inc r12d
    cmp r12d, RX_MAX
    jb 1b
    EPILOGUE

# remote_ext_connected(): the host answers (the first time or again): extensions that waited for
# it start, and those that ran there and ended with the connection start again
FN remote_ext_connected
    PROLOGUE
    lea rbx, [rip + rx_tab]
    xor r12d, r12d
1:  mov r13, [rbx + RX_ext]
    test r13, r13
    jz 5f
    mov rdi, r13
    call ext_is_visible
    test eax, eax
    jz 5f
    cmp dword ptr [rbx + RX_waitconn], 0
    jne 2f
    cmp dword ptr [rbx + RX_state], RXS_FAILED
    jne 3f
    cmp dword ptr [rbx + RX_err], 107       # ENOTCONN: the copy ended with the connection
    jne 3f
    mov dword ptr [rbx + RX_state], RXS_NEW
    jmp 4f
2:  mov dword ptr [rbx + RX_waitconn], 0
    cmp dword ptr [r13 + EXT_status], ES_IDLE
    jne 5f
    mov dword ptr [r13 + EXT_remote_wait], 0
    mov qword ptr [r13 + EXT_reason], 0
    mov rdi, r13
    call ext_start
    jmp 5f
3:  cmp dword ptr [rbx + RX_ran], 0
    je 5f
4:  mov eax, [r13 + EXT_status]
    cmp eax, ES_CRASHED
    je 41f
    cmp eax, ES_FAILED
    jne 5f
41: mov qword ptr [r13 + EXT_reason], 0
    mov rdi, r13
    call ext_restart
5:  add rbx, RX_SIZE
    inc r12d
    cmp r12d, RX_MAX
    jb 1b
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- the entry of an extension ----------------

# rx_find(ext, create) -> rax its RX, or 0 (none, or the table is full)
rx_find:
    lea rax, [rip + rx_tab]
    xor ecx, ecx
    xor r8d, r8d
1:  cmp ecx, RX_MAX
    jae 3f
    cmp [rax + RX_ext], rdi
    je 9f
    test r8, r8
    jnz 2f
    cmp qword ptr [rax + RX_ext], 0
    jne 2f
    mov r8, rax
2:  add rax, RX_SIZE
    inc ecx
    jmp 1b
3:  xor eax, eax
    test esi, esi
    jz 9f
    test r8, r8
    jz 9f
    mov rax, r8
    mov [rax + RX_ext], rdi
    mov dword ptr [rax + RX_state], RXS_NEW
    mov dword ptr [rax + RX_fd], -1
9:  ret

# rx_cpy(dst, src, limit) -> rax the end (its NUL): src, stopping before limit
rx_cpy:
1:  cmp rdi, rdx
    jae 2f
    mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rdi
    inc rsi
    jmp 1b
2:  mov byte ptr [rdi], 0
    mov rax, rdi
    ret

# rx_why(rx, a, b or 0): RX_why = a then b (cut to fit)
rx_why:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    lea rdi, [rbx + RX_why]
    lea rdx, [rbx + RX_why + 500]
    call rx_cpy
    test r12, r12
    jz 9f
    mov rdi, rax
    mov rsi, r12
    lea rdx, [rbx + RX_why + 500]
    call rx_cpy
9:  EPILOGUE

# rx_continue(rx): the next step towards the host: a download, the look for the host's folder, or
# the failure
rx_continue:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rbx + RX_fresh], 0
    mov rdi, rbx
    call rx_prepare
    cmp eax, 1
    je 9f                       # fetching
    test eax, eax
    jnz 8f
    mov dword ptr [rbx + RX_state], RXS_CHECK
    lea rdi, [rip + .Lv_stat]
    call rx_line_start
    mov rdi, [rbx + RX_hdir]
    call strlen
    mov rdi, rax
    call rx_line_num
    mov rdi, [rbx + RX_hdir]
    call strlen
    mov rcx, rax
    mov rdx, [rbx + RX_hdir]
    mov rdi, [rip + rx_line + SB_ptr]
    mov rsi, [rip + rx_line + SB_len]
    lea r8, [rip + rx_on_check]
    mov r9, rbx
    call remote_request_cb
    test eax, eax
    jnz 9f
    mov dword ptr [rbx + RX_err], 107
    mov rdi, rbx
    lea rsi, [rip + .Lr_lost]
    xor edx, edx
    call rx_why
8:  mov rdi, rbx
    call rx_fail
9:  EPILOGUE

# rx_on_check(rx, status, ptr, len): the host's folder is there (ready), missing (copied), or the
# host did not answer
rx_on_check:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + RX_state], RXS_CHECK
    jne 9f
    test rsi, rsi
    jz 1f
    cmp rsi, -2
    je 2f
    neg esi
    mov [rbx + RX_err], esi
    mov rdi, rbx
    lea rsi, [rip + .Lr_lost]
    xor edx, edx
    call rx_why
    mov rdi, rbx
    call rx_fail
    jmp 9f
1:  lea rdi, [rip + .Ll_found]
    mov rsi, [rbx + RX_hdir]
    call remote_log2
    mov rdi, rbx
    call rx_ready
    jmp 9f
2:  mov rdi, rbx
    call rx_upload_start
9:  EPILOGUE

# rx_ready(rx): its files are on the host: it starts, if it still waits
rx_ready:
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rbx + RX_state], RXS_READY
    mov dword ptr [rbx + RX_fresh], 1
    mov r12, [rbx + RX_ext]
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jz 9f
    cmp dword ptr [r12 + EXT_remote_wait], 0
    je 9f
    mov dword ptr [r12 + EXT_remote_wait], 0
    cmp dword ptr [r12 + EXT_status], ES_IDLE
    jne 9f
    mov qword ptr [r12 + EXT_reason], 0
    mov rdi, r12
    call ext_start
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# rx_fail(rx): it cannot run on the host; RX_why says why. A later start tries again.
rx_fail:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + .Ll_failed]
    lea rsi, [rbx + RX_why]
    call remote_log2
    mov dword ptr [rbx + RX_state], RXS_FAILED
    mov dword ptr [rbx + RX_fresh], 0
    mov r12, [rbx + RX_ext]
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jz 9f
    mov dword ptr [r12 + EXT_remote_wait], 0
    cmp dword ptr [r12 + EXT_status], ES_IDLE
    jne 9f
    lea rax, [rbx + RX_why]
    mov [r12 + EXT_reason], rax
    mov dword ptr [r12 + EXT_status], ES_FAILED
    mov rdi, r12
    call ext_pending_reconcile
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- what is copied ----------------

# rx_prepare(rx) -> eax 0: RX_src, RX_files and RX_hdir name the local files and the host's folder;
#   1: its Linux build is being fetched (rx_on_fetch goes on); -1: it cannot run there (RX_why)
rx_prepare:
    PROLOGUE
    mov r12, rdi
    mov rbx, [r12 + RX_ext]
    # a WebAssembly module or a script runs from the installed folder as it is
    cmp dword ptr [rbx + EXT_wasm_run], 0
    jne .Lxp_installed
    cmp qword ptr [rbx + EXT_script], 0
    jne .Lxp_installed
    # a program: the one run.linux-x86_64 names
    mov rdi, rbx
    call rx_linux_run
    test rax, rax
    jz .Lxp_no_linux
    mov r13, rax
    mov rdi, [r12 + RX_run]
    call mem_free
    mov [r12 + RX_run], r13
    mov rdi, [rbx + EXT_dir]
    mov rsi, r13
    call rx_exists
    test eax, eax
    jnz .Lxp_installed
    # its release's linux-x86_64 archive, fetched once
    mov rdi, r12
    call rx_fetch_dir
    test rax, rax
    jz .Lxp_no_release
    mov r13, rax
    mov rdi, rax
    mov rsi, [r12 + RX_run]
    call rx_exists
    test eax, eax
    jnz .Lxp_src_fetched
    mov rdi, r12
    mov rsi, r13
    call rx_fetch
    mov r14d, eax
    mov rdi, r13
    call mem_free
    test r14d, r14d
    jz .Lxp_fail
    mov eax, 1
    EPILOGUE
.Lxp_src_fetched:
    mov rdi, [r12 + RX_src]
    call mem_free
    mov [r12 + RX_src], r13
    jmp .Lxp_walk
.Lxp_installed:
    mov rdi, [r12 + RX_src]
    call mem_free
    mov rdi, [rbx + EXT_dir]
    call dup_cstr
    mov [r12 + RX_src], rax
.Lxp_walk:
    mov rdi, r12
    call rx_walk
    test eax, eax
    jnz .Lxp_fail
    mov rdi, r12
    call rx_host_dir
    xor eax, eax
    EPILOGUE
.Lxp_no_linux:
    lea rsi, [rip + .Lr_no_linux]
    jmp .Lxp_why
.Lxp_no_release:
    lea rsi, [rip + .Lr_no_release]
.Lxp_why:
    mov rdi, r12
    xor edx, edx
    call rx_why
.Lxp_fail:
    mov eax, -1
    EPILOGUE

# rx_exists(dir, name) -> eax 1 when dir/name is there
rx_exists:
    PROLOGUE
    call path_join
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    SYS SYS_access
    mov r12, rax
    mov rdi, rbx
    call mem_free
    xor eax, eax
    test r12, r12
    sete al
    EPILOGUE

# rx_linux_run(ext) -> its manifest's run.linux-x86_64 (cstr, mem_alloc'd), or 0
rx_linux_run:
    PROLOGUE
    mov rdi, [rdi + EXT_dir]
    lea rsi, [rip + .Lmanifest]
    call path_join
    mov rbx, rax
    mov rdi, rax
    call file_read_all
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call mem_free
    xor r14d, r14d
    test r12, r12
    jz 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lk_run_linux]
    call ini_top_value
    test rax, rax
    jz 8f
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r14, rax
8:  mov rdi, r12
    call mem_free
9:  mov rax, r14
    EPILOGUE

# rx_fetch_dir(rx) -> where its release's Linux build is kept here (STATE/rhun/remote/extensions/
# OWNER--NAME--TAG, mem_alloc'd; RX_tag the tag), or 0 when it was not installed from a release
rx_fetch_dir:
    PROLOGUE
    mov r12, rdi
    mov rbx, [r12 + RX_ext]
    mov rdi, rbx
    lea rsi, [rip + .Lk_source]
    call extrec_get
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lw_github]
    call str_eq_cstr
    test eax, eax
    jz 8f
    mov rdi, rbx
    call ext_tag_of
    lea rdi, [r12 + RX_tag]
    mov rsi, rax
    lea rdx, [r12 + RX_tag + 100]
    call rx_cpy
    lea rdi, [rip + rx_tmp]
    call rx_fetch_root
    test eax, eax
    jz 8f
    lea rdi, [rip + rx_tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + .Ldashes]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + .Ldashes]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [r12 + RX_tag]
    call sb_push_cstr
    mov rdi, [rip + rx_tmp + SB_ptr]
    mov rsi, [rip + rx_tmp + SB_len]
    call mem_dup
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# rx_fetch_root(sb) -> eax 1 with STATE/rhun/remote/extensions in sb (created)
rx_fetch_root:
    PROLOGUE
    mov rbx, rdi
    call session_state_dir
    test eax, eax
    jz 9f
    mov rdi, rbx
    lea rsi, [rip + .Lsub_fetch]
    call sb_push_cstr
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + SB_len]
    mov rdi, [rbx + SB_ptr]
    call mkdir_p
    mov eax, 1
9:  EPILOGUE

# rx_fetch(rx, dir) -> eax 1 when the download started (rx_on_fetch takes it into dir), else 0
#   with RX_why
rx_fetch:
.ifdef WINDOWS
    PROLOGUE
    lea rsi, [rip + .Lr_no_fetch_windows]
    xor edx, edx
    call rx_why
    xor eax, eax
    EPILOGUE
.else
    PROLOGUE 112
    mov r12, rdi
    mov r13, rsi
    mov rbx, [r12 + RX_ext]
    mov rdi, [r12 + RX_fdir]
    call mem_free
    mov rdi, r13
    call dup_cstr
    mov [r12 + RX_fdir], rax
    lea rdi, [rip + rx_tmp]
    call rx_fetch_root
    test eax, eax
    jz 8f
    # sh -c SCRIPT rhun-install OWNER NAME linux-x86_64 ROOT BASE TAG - - github
    lea rax, [rip + .Lsh]
    mov [rsp], rax
    lea rax, [rip + .Ldash_c]
    mov [rsp + 8], rax
    lea rax, [rip + install_script]
    mov [rsp + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rsp + 24], rax
    mov rax, [rbx + EXT_owner]
    mov [rsp + 32], rax
    mov rax, [rbx + EXT_name]
    mov [rsp + 40], rax
    lea rax, [rip + .Ltarget]
    mov [rsp + 48], rax
    mov rax, [rip + rx_tmp + SB_ptr]
    mov [rsp + 56], rax
    call ext_release_base
    mov [rsp + 64], rax
    lea rax, [r12 + RX_tag]
    mov [rsp + 72], rax
    lea rax, [rip + .Ldash]
    mov [rsp + 80], rax
    mov [rsp + 88], rax
    lea rax, [rip + .Lw_github]
    mov [rsp + 96], rax
    mov qword ptr [rsp + 104], 0
    mov rdi, rsp
    mov rsi, [rip + g_envp]
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    mov [r12 + RX_pid], eax
    mov [r12 + RX_fd], edx
    lea rdi, [r12 + RX_dl]
    call sb_clear
    mov edi, [r12 + RX_fd]
    mov esi, POLLIN
    lea rdx, [rip + rx_on_fetch]
    mov rcx, r12
    call watch_add
    mov dword ptr [r12 + RX_state], RXS_FETCH
    lea rdi, [rip + .Ll_fetching]
    mov rsi, [r12 + RX_fdir]
    call remote_log2
    lea rax, [rip + .Lw_fetch]
    mov [rbx + EXT_reason], rax
    mov eax, 1
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Lr_fetch_start]
    xor edx, edx
    call rx_why
    xor eax, eax
    EPILOGUE

# rx_on_fetch(fd, revents, rx): the download's output; at its end the build moves into RX_fdir
rx_on_fetch:
    PROLOGUE
    mov rbx, rdx
1:  mov edi, [rbx + RX_fd]
    lea rsi, [rip + rx_dlbuf]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    cmp qword ptr [rbx + RX_dl + SB_len], 65536
    jae 1b
    lea rdi, [rbx + RX_dl]
    lea rsi, [rip + rx_dlbuf]
    mov rdx, rax
    call sb_push
    jmp 1b
2:  mov edi, [rbx + RX_fd]
    call watch_remove
    mov edi, [rbx + RX_fd]
    SYS SYS_close
    mov dword ptr [rbx + RX_fd], -1
    mov edi, [rbx + RX_pid]
    xor esi, esi
    call proc_wait
    mov r13d, eax
    mov dword ptr [rbx + RX_pid], 0
    # the last line: "ok SHA256 TAG DIR", or why it failed
    lea rdi, [rbx + RX_dl]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rbx + RX_dl + SB_ptr]
    mov rsi, [rbx + RX_dl + SB_len]
    dec rsi
3:  test rsi, rsi
    jz 4f
    cmp byte ptr [rdi + rsi - 1], 10
    jne 4f
    dec rsi
    mov byte ptr [rdi + rsi], 0
    jmp 3b
4:  mov rcx, rsi
5:  test rcx, rcx
    jz 6f
    cmp byte ptr [rdi + rcx - 1], 10
    je 6f
    dec rcx
    jmp 5b
6:  lea r12, [rdi + rcx]
    test r13d, r13d
    jnz .Lxf_failed
    cmp word ptr [r12], 0x6b6f     # "ok"
    jne .Lxf_failed
    # past "ok SHA TAG "
    mov ecx, 3
7:  cmp byte ptr [r12], 0
    je .Lxf_failed
    cmp byte ptr [r12], ' '
    lea r12, [r12 + 1]
    jne 7b
    dec ecx
    jnz 7b
    cmp byte ptr [r12], 0
    je .Lxf_failed
    # DIR/x becomes RX_fdir (one there already, from another window, stays)
    lea rdi, [rip + rx_tmp]
    call sb_clear
    lea rdi, [rip + rx_tmp]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + .Lsub_x]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + rx_tmp + SB_ptr]
    mov rsi, [rbx + RX_fdir]
    SYS SYS_rename
    mov rdi, r12
    call file_remove_tree
    mov rdi, rbx
    call rx_waiting
    test eax, eax
    jz 9f
    mov rdi, rbx
    call rx_continue
    jmp 9f
.Lxf_failed:
    mov rdx, r12
    cmp byte ptr [r12], 0
    jne 8f
    lea rdx, [rip + .Lr_unknown]
8:  mov rdi, rbx
    lea rsi, [rip + .Lr_fetch]
    call rx_why
    mov rdi, rbx
    call rx_fail
9:  EPILOGUE
.endif

# rx_waiting(rx) -> eax 1 while its extension still waits to start
rx_waiting:
    mov rax, [rdi + RX_ext]
    xor ecx, ecx
    cmp dword ptr [rax + EXT_status], ES_REMOVED
    je 9f
    cmp dword ptr [rax + EXT_remote_wait], 0
    je 9f
    mov ecx, 1
9:  mov eax, ecx
    ret

# ---------------- the walk ----------------

# rx_walk(rx) -> eax 0 with RX_files listing RX_src's files and folders, rx_fp their hash; -1 with
# RX_why when the folder cannot be read or is too big
rx_walk:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rbx + RX_files]
    call sb_clear
    mov rax, 0xcbf29ce484222325
    mov [rip + rx_fp], rax
    mov qword ptr [rip + rx_total], 0
    mov dword ptr [rip + rx_depth], 0
    mov dword ptr [rip + rx_toolong], 0
    lea rdi, [rip + rx_wrel]
    call sb_clear
    lea rdi, [rip + rx_wpath]
    call sb_clear
    lea rdi, [rip + rx_wpath]
    mov esi, 8192               # never moved while dir_each reads it
    call sb_reserve
    mov rdi, [rbx + RX_src]
    call strlen
    cmp rax, RX_PATH_MAX
    jae 7f
    lea rdi, [rip + rx_wpath]
    mov rsi, [rbx + RX_src]
    call sb_push_cstr
    call rx_wpath_end
    mov rdi, [rip + rx_wpath + SB_ptr]
    lea rsi, [rip + rx_walk_cb]
    mov rdx, rbx
    call dir_each
    test rax, rax
    js 7f
    cmp qword ptr [rip + rx_total], RX_TOTAL_MAX
    ja 6f
    xor eax, eax
    EPILOGUE
6:  lea rsi, [rip + .Lr_too_big]
    jmp 8f
7:  lea rsi, [rip + .Lr_unreadable]
8:  mov rdi, rbx
    xor edx, edx
    call rx_why
    mov eax, -1
    EPILOGUE

# rx_wpath_end(): rx_wpath and rx_wrel NUL-terminated (outside their lengths)
rx_wpath_end:
    push rbx
    lea rdi, [rip + rx_wpath]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + rx_wpath + SB_len]
    lea rdi, [rip + rx_wrel]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + rx_wrel + SB_len]
    pop rbx
    ret

# rx_hash(ptr, len): into rx_fp (FNV-1a)
rx_hash:
    mov rax, [rip + rx_fp]
    mov r8, 0x100000001b3
1:  test rsi, rsi
    jz 2f
    movzx ecx, byte ptr [rdi]
    xor rax, rcx
    imul rax, r8
    inc rdi
    dec rsi
    jmp 1b
2:  mov [rip + rx_fp], rax
    ret

# rx_walk_cb(rx, name, is_dir): one entry of the folder rx_wpath names
rx_walk_cb:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    # rhun's own record of the install and version control stay here
    mov rdi, r12
    lea rsi, [rip + .Lrec_name]
    call strcmp_eq
    test eax, eax
    jnz 9f
    mov rdi, r12
    lea rsi, [rip + .Lgit_name]
    call strcmp_eq
    test eax, eax
    jnz 9f
    cmp qword ptr [rip + rx_total], RX_TOTAL_MAX
    ja 9f
    mov rax, [rip + rx_wpath + SB_len]
    mov [rsp], rax
    mov rax, [rip + rx_wrel + SB_len]
    mov [rsp + 8], rax
    mov rdi, r12
    call strlen
    mov r14, rax
    add rax, [rip + rx_wpath + SB_len]
    cmp rax, RX_PATH_MAX
    jb 1f
    mov dword ptr [rip + rx_toolong], 1
    jmp 9f
1:  lea rdi, [rip + rx_wpath]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + rx_wpath]
    mov rsi, r12
    mov rdx, r14
    call sb_push
    cmp qword ptr [rip + rx_wrel + SB_len], 0
    je 2f
    lea rdi, [rip + rx_wrel]
    mov esi, '/'
    call sb_push_byte
2:  lea rdi, [rip + rx_wrel]
    mov rsi, r12
    mov rdx, r14
    call sb_push
    call rx_wpath_end
    # its kind: a folder, a file, or an executable file
    mov r15d, 'd'
    test r13d, r13d
    jnz 3f
    mov rdi, [rip + rx_wpath + SB_ptr]
    lea rsi, [rip + rx_stat]
    mov eax, 4                  # stat (follows links)
    XSYS
    test rax, rax
    js 8f                       # gone since it was listed
    mov r15d, 'f'
    test dword ptr [rip + rx_stat + 24], 0100
    jz 21f
    mov r15d, 'x'
21: mov rax, [rip + rx_stat + 48]
    add [rip + rx_total], rax
    lea rdi, [rip + rx_stat + 48]   # size
    mov esi, 8
    call rx_hash
    lea rdi, [rip + rx_stat + 88]   # modification time, seconds and nanoseconds
    mov esi, 16
    call rx_hash
3:  lea rdi, [rbx + RX_files]
    mov esi, r15d
    call sb_push_byte
    lea rdi, [rbx + RX_files]
    mov rsi, [rip + rx_wrel + SB_ptr]
    mov rdx, [rip + rx_wrel + SB_len]
    call sb_push
    lea rdi, [rbx + RX_files]
    xor esi, esi
    call sb_push_byte
    mov [rsp + 16], r15
    lea rdi, [rsp + 16]
    mov esi, 1
    call rx_hash
    mov rdi, [rip + rx_wrel + SB_ptr]
    mov rsi, [rip + rx_wrel + SB_len]
    call rx_hash
    cmp r15d, 'd'
    jne 8f
    cmp dword ptr [rip + rx_depth], RX_DEPTH
    jae 8f
    inc dword ptr [rip + rx_depth]
    mov rdi, [rip + rx_wpath + SB_ptr]
    lea rsi, [rip + rx_walk_cb]
    mov rdx, rbx
    call dir_each
    dec dword ptr [rip + rx_depth]
8:  mov rax, [rsp]
    mov [rip + rx_wpath + SB_len], rax
    mov rax, [rsp + 8]
    mov [rip + rx_wrel + SB_len], rax
    call rx_wpath_end
9:  EPILOGUE

# rx_host_dir(rx): RX_hdir = HOME/.cache/rhun-remote/extensions/OWNER/NAME/VERSION-HASH
rx_host_dir:
    PROLOGUE 32
    mov r12, rdi
    mov rbx, [r12 + RX_ext]
    lea rdi, [rip + rx_tmp]
    call sb_clear
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + g_remote_home]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + .Lsub_cache]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov esi, '/'
    call sb_push_byte
    # the version, only the characters a folder name takes as they are
    mov r13, [rbx + EXT_version]
    test r13, r13
    jnz 1f
    lea r13, [rip + .Lzero]
1:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 3f
    inc r13
    mov esi, eax
    cmp eax, '.'
    je 2f
    cmp eax, '-'
    je 2f
    cmp eax, '_'
    je 2f
    mov ecx, eax
    or ecx, 0x20
    sub ecx, 'a'
    cmp ecx, 26
    jb 2f
    mov ecx, eax
    sub ecx, '0'
    cmp ecx, 10
    jb 2f
    mov esi, '_'
2:  lea rdi, [rip + rx_tmp]
    call sb_push_byte
    jmp 1b
3:  lea rdi, [rip + rx_tmp]
    mov esi, '-'
    call sb_push_byte
    # the hash: 16 hex digits
    mov r14, [rip + rx_fp]
    mov r15d, 60
4:  mov rax, r14
    mov ecx, r15d
    shr rax, cl
    and eax, 15
    lea rcx, [rip + hexdigits]
    movzx esi, byte ptr [rcx + rax]
    lea rdi, [rip + rx_tmp]
    call sb_push_byte
    sub r15d, 4
    jns 4b
    mov rdi, [r12 + RX_hdir]
    call mem_free
    mov rdi, [rip + rx_tmp + SB_ptr]
    mov rsi, [rip + rx_tmp + SB_len]
    call mem_dup
    mov [r12 + RX_hdir], rax
    EPILOGUE

# ---------------- the copy ----------------

# rx_line_start(verb cstr) / rx_line_num(n): the request's line
rx_line_start:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + rx_line]
    call sb_clear
    lea rdi, [rip + rx_line]
    mov rsi, rbx
    call sb_push_cstr
    pop rbx
    ret
rx_line_num:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + rx_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + rx_line]
    mov rsi, rbx
    call sb_push_u64
    pop rbx
    ret

# rx_send(rx, body ptr, len) -> eax 1 when rx_line went (one more in flight), 0 when it waits
rx_send:
    push rbx
    mov rbx, rdi
    mov rcx, rdx
    mov rdx, rsi
    mov rdi, [rip + rx_line + SB_ptr]
    mov rsi, [rip + rx_line + SB_len]
    lea r8, [rip + rx_on_part]
    mov r9, rbx
    call remote_request_cb
    test eax, eax
    jz 9f
    inc dword ptr [rbx + RX_out]
    mov eax, 1
9:  pop rbx
    ret

# rx_upload_start(rx): the files go into RX_hdir.part-PID-TIME, which then becomes RX_hdir
rx_upload_start:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + rx_tmp]
    call sb_clear
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + RX_hdir]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    lea rsi, [rip + .Lsuf_part]
    call sb_push_cstr
    call time_ms
    lea rdi, [rip + rx_tmp]
    mov rsi, rax
    call sb_push_u64
    mov rdi, [rbx + RX_part]
    call mem_free
    mov rdi, [rip + rx_tmp + SB_ptr]
    mov rsi, [rip + rx_tmp + SB_len]
    call mem_dup
    mov [rbx + RX_part], rax
    mov qword ptr [rbx + RX_next], 0
    mov dword ptr [rbx + RX_out], 0
    mov dword ptr [rbx + RX_err], 0
    mov dword ptr [rbx + RX_state], RXS_UPLOAD
    lea rdi, [rip + .Ll_copying]
    mov rsi, [rbx + RX_hdir]
    call remote_log2
    # mkdir 1 LEN + the folder (and those on the way)
    lea rdi, [rip + .Lv_mkdir]
    call rx_line_start
    mov edi, 1
    call rx_line_num
    mov rdi, [rbx + RX_part]
    call strlen
    mov r12, rax
    mov rdi, rax
    call rx_line_num
    mov rdi, rbx
    mov rsi, [rbx + RX_part]
    mov rdx, r12
    call rx_send
    mov rdi, rbx
    call rx_pump
    EPILOGUE

# rx_pump(rx): more of the copy, while fewer than RX_WINDOW requests are in flight; once every one
# was answered, the folder takes its name (or the copy failed)
rx_pump:
    PROLOGUE 16
    mov rbx, rdi
.Lxu_loop:
    cmp dword ptr [rbx + RX_state], RXS_UPLOAD
    jne .Lxu_done
    cmp dword ptr [rbx + RX_out], RX_WINDOW
    jae .Lxu_done
    cmp qword ptr [rbx + RX_data], 0
    jne .Lxu_part
    mov rax, [rbx + RX_next]
    cmp rax, [rbx + RX_files + SB_len]
    jae .Lxu_all_sent
    # the next entry: KIND + path
    mov r12, [rbx + RX_files + SB_ptr]
    add r12, rax
    movzx r13d, byte ptr [r12]
    inc r12
    lea rdi, [rip + rx_tmp]
    call sb_clear
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + RX_part]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + rx_tmp]
    mov rsi, r12
    call sb_push_cstr
    mov rdi, r12
    call strlen
    lea r14, [rax + 2]          # the entry's length, KIND and NUL with it
    cmp r13d, 'd'
    jne .Lxu_file
    lea rdi, [rip + .Lv_mkdir]
    call rx_line_start
    xor edi, edi
    call rx_line_num
    mov rdi, [rip + rx_tmp + SB_len]
    call rx_line_num
    mov rdi, rbx
    mov rsi, [rip + rx_tmp + SB_ptr]
    mov rdx, [rip + rx_tmp + SB_len]
    call rx_send
    test eax, eax
    jz .Lxu_held
    add [rbx + RX_next], r14
    jmp .Lxu_loop
.Lxu_file:
    add [rbx + RX_next], r14
    mov dword ptr [rbx + RX_dmode], 644
    cmp r13d, 'x'
    jne 1f
    mov dword ptr [rbx + RX_dmode], 755
1:  mov rdi, [rbx + RX_dpath]
    call mem_free
    mov rdi, [rip + rx_tmp + SB_ptr]
    mov rsi, [rip + rx_tmp + SB_len]
    call mem_dup
    mov [rbx + RX_dpath], rax
    # the local file
    lea rdi, [rip + rx_tmp]
    call sb_clear
    lea rdi, [rip + rx_tmp]
    mov rsi, [rbx + RX_src]
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + rx_tmp]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + rx_tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + rx_tmp + SB_ptr]
    call file_read_all
    test rax, rax
    jnz 2f
    neg edx
    cmp dword ptr [rbx + RX_err], 0
    jne .Lxu_loop
    mov [rbx + RX_err], edx
    jmp .Lxu_loop
2:  mov [rbx + RX_data], rax
    mov [rbx + RX_dlen], rdx
    mov qword ptr [rbx + RX_doff], 0
.Lxu_part:
    # write FLAGS MODE PLEN LEN + path + the part: the first creates it, the others append
    mov r12, [rbx + RX_dlen]
    sub r12, [rbx + RX_doff]
    cmp r12, RX_PART
    jbe 3f
    mov r12d, RX_PART
3:  lea rdi, [rip + .Lv_write]
    call rx_line_start
    mov edi, 4
    cmp qword ptr [rbx + RX_doff], 0
    jne 4f
    mov edi, 8
4:  call rx_line_num
    mov edi, [rbx + RX_dmode]
    call rx_line_num
    mov rdi, [rbx + RX_dpath]
    call strlen
    mov r13, rax
    mov rdi, rax
    call rx_line_num
    lea rdi, [rip + rx_body]
    call sb_clear
    lea rdi, [rip + rx_body]
    mov rsi, [rbx + RX_dpath]
    mov rdx, r13
    call sb_push
    lea rdi, [rip + rx_body]
    mov rsi, [rbx + RX_data]
    add rsi, [rbx + RX_doff]
    mov rdx, r12
    call sb_push
    mov rdi, rbx
    mov rsi, [rip + rx_body + SB_ptr]
    mov rdx, [rip + rx_body + SB_len]
    call rx_send
    test eax, eax
    jz .Lxu_held
    add [rbx + RX_doff], r12
    mov rax, [rbx + RX_doff]
    cmp rax, [rbx + RX_dlen]
    jb .Lxu_loop
    mov rdi, [rbx + RX_data]
    call mem_free
    mov qword ptr [rbx + RX_data], 0
    lea rdi, [rip + rx_body]
    call sb_free                # a big file's bytes are not kept around
    jmp .Lxu_loop
.Lxu_all_sent:
    cmp dword ptr [rbx + RX_out], 0
    jne .Lxu_done
    cmp dword ptr [rbx + RX_err], 0
    jne .Lxu_failed
    # rename 0 OLDLEN LEN + the part + the folder
    lea rdi, [rip + .Lv_rename]
    call rx_line_start
    xor edi, edi
    call rx_line_num
    mov rdi, [rbx + RX_part]
    call strlen
    mov r12, rax
    mov rdi, rax
    call rx_line_num
    lea rdi, [rip + rx_body]
    call sb_clear
    lea rdi, [rip + rx_body]
    mov rsi, [rbx + RX_part]
    mov rdx, r12
    call sb_push
    lea rdi, [rip + rx_body]
    mov rsi, [rbx + RX_hdir]
    call sb_push_cstr
    mov rdi, [rip + rx_line + SB_ptr]
    mov rsi, [rip + rx_line + SB_len]
    mov rdx, [rip + rx_body + SB_ptr]
    mov rcx, [rip + rx_body + SB_len]
    lea r8, [rip + rx_on_renamed]
    mov r9, rbx
    call remote_request_cb
    test eax, eax
    jz .Lxu_held
    mov dword ptr [rbx + RX_state], RXS_RENAME
    jmp .Lxu_done
.Lxu_held:
    # the request table is full (remote_ext_tick tries again), or the host is gone
    call remote_is_up
    test eax, eax
    jnz .Lxu_done
    cmp dword ptr [rbx + RX_err], 0
    jne 5f
    mov dword ptr [rbx + RX_err], 107
5:  cmp dword ptr [rbx + RX_out], 0
    jne .Lxu_done
.Lxu_failed:
    mov rdi, [rbx + RX_data]
    call mem_free
    mov qword ptr [rbx + RX_data], 0
    mov rdi, rbx
    call rx_remove_part
    mov rdi, rbx
    lea rsi, [rip + .Lr_copy]
    xor edx, edx
    cmp dword ptr [rbx + RX_err], 107
    jne 6f
    lea rsi, [rip + .Lr_lost]
6:  call rx_why
    mov rdi, rbx
    call rx_fail
.Lxu_done:
    EPILOGUE

# rx_on_part(rx, status, ptr, len): one part of the copy was answered
rx_on_part:
    PROLOGUE
    mov rbx, rdi
    dec dword ptr [rbx + RX_out]
    test rsi, rsi
    jns 1f
    cmp dword ptr [rbx + RX_err], 0
    jne 1f
    neg esi
    mov [rbx + RX_err], esi
1:  cmp dword ptr [rbx + RX_state], RXS_UPLOAD
    jne 9f
    mov rdi, rbx
    call rx_pump
9:  EPILOGUE

# rx_on_renamed(rx, status, ptr, len): the folder has its name (or another window made it first)
rx_on_renamed:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + RX_state], RXS_RENAME
    jne 9f
    test rsi, rsi
    jz 2f
    cmp rsi, -17                # EEXIST
    je 1f
    cmp rsi, -39                # ENOTEMPTY
    je 1f
    neg esi
    mov [rbx + RX_err], esi
    mov rdi, rbx
    call rx_remove_part
    mov rdi, rbx
    lea rsi, [rip + .Lr_copy]
    xor edx, edx
    call rx_why
    mov rdi, rbx
    call rx_fail
    jmp 9f
1:  mov rdi, rbx
    call rx_remove_part
2:  lea rdi, [rip + .Ll_copied]
    mov rsi, [rbx + RX_hdir]
    call remote_log2
    mov rdi, rbx
    call rx_ready
9:  EPILOGUE

# rx_remove_part(rx): the unfinished folder goes (if the request can be made now)
rx_remove_part:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RX_part]
    test r12, r12
    jz 9f
    lea rdi, [rip + .Lv_remove]
    call rx_line_start
    mov edi, 1
    call rx_line_num
    mov rdi, r12
    call strlen
    mov r13, rax
    mov rdi, rax
    call rx_line_num
    mov rdi, [rip + rx_line + SB_ptr]
    mov rsi, [rip + rx_line + SB_len]
    mov rdx, r12
    mov rcx, r13
    lea r8, [rip + rx_ignore]
    xor r9d, r9d
    call remote_request_cb
9:  EPILOGUE

rx_ignore:
    ret

# ---------------- the start ----------------

# rx_push(cstr): onto rx_sbuf with its NUL
rx_push:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + rx_sbuf]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + rx_sbuf]
    xor esi, esi
    call sb_push_byte
    pop rbx
    ret

# rx_prefix(path, root) -> rax the rest of path after root ("" or "/..."), or 0 when it is not
# root or inside it
rx_prefix:
    xor ecx, ecx
    test rsi, rsi
    jz 8f
    cmp byte ptr [rsi], 0
    je 8f
1:  mov al, [rsi + rcx]
    test al, al
    jz 2f
    cmp al, [rdi + rcx]
    jne 8f
    inc rcx
    jmp 1b
2:  lea rax, [rdi + rcx]
    cmp byte ptr [rax], 0
    je 9f
    cmp byte ptr [rax], '/'
    je 9f
8:  xor eax, eax
9:  ret

# rx_remap(rx in rbx's RX r12, value cstr): onto rx_sbuf (without its NUL): the extension's state
# folder and its folder as the host's, the home folder as the host's
rx_remap:
    PROLOGUE
    mov r13, rdi
    mov rsi, [rbx + EXT_state]
    call rx_prefix
    test rax, rax
    jz 1f
    mov r14, rax
    lea rdi, [rip + rx_sbuf]
    lea rsi, [rip + rx_hstate]
    call sb_push_cstr
    jmp 7f
1:  mov rdi, r13
    mov rsi, [rbx + EXT_dir]
    call rx_prefix
    test rax, rax
    jz 2f
    mov r14, rax
    lea rdi, [rip + rx_sbuf]
    mov rsi, [r12 + RX_hdir]
    call sb_push_cstr
    jmp 7f
2:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 3f
    mov rdi, r13
    mov rsi, rax
    call strcmp_eq
    test eax, eax
    jz 3f
    lea rdi, [rip + rx_sbuf]
    lea rsi, [rip + g_remote_home]
    call sb_push_cstr
    jmp 9f
3:  mov r14, r13
7:  lea rdi, [rip + rx_sbuf]
    mov rsi, r14
    call sb_push_cstr
9:  EPILOGUE

# rx_env_drop(entry) -> eax 1 for an entry the host does not get: this machine's PATH, socket,
# Xcode and folders
rx_env_drop:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + rx_env_dropped]
1:  mov rsi, [r12]
    test rsi, rsi
    jz 8f
    add r12, 8
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rdi, rbx
    mov rsi, [r12 - 8]
    call memeq
    test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# rx_spawn(rx) -> as remote_ext_spawn: argv_vec and env_vec rewritten for the host, run there
rx_spawn:
    PROLOGUE 32
    mov r12, rdi
    mov rbx, [r12 + RX_ext]
    # the host's state folder: HOME/.local/state/rhun/extensions/OWNER--NAME
    lea rdi, [rip + rx_hstate]
    lea rsi, [rip + g_remote_home]
    lea rdx, [rip + rx_hstate + 4000]
    call rx_cpy
    mov rdi, rax
    lea rsi, [rip + .Lsub_state]
    lea rdx, [rip + rx_hstate + 4000]
    call rx_cpy
    mov rdi, rax
    mov rsi, [rbx + EXT_owner]
    lea rdx, [rip + rx_hstate + 4000]
    call rx_cpy
    mov rdi, rax
    lea rsi, [rip + .Ldashes]
    lea rdx, [rip + rx_hstate + 4000]
    call rx_cpy
    mov rdi, rax
    mov rsi, [rbx + EXT_name]
    lea rdx, [rip + rx_hstate + 4000]
    call rx_cpy
    lea rdi, [rip + rx_sbuf]
    call sb_clear
    # argv[0]: rhun itself for a WebAssembly module, a script's runtime by name (the host's PATH
    # finds it), else the program in the host's folder
    mov dword ptr [rsp], 2 | 4 | 8      # keep argv[0], the environment exactly, held there
    cmp dword ptr [rbx + EXT_wasm_run], 0
    je 1f
    lea rdi, [rip + .Lat_self]
    call rx_push
    jmp 3f
1:  cmp qword ptr [rbx + EXT_script], 0
    je 2f
    mov dword ptr [rsp], 4 | 8
    mov rdi, [rbx + EXT_prog]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + EXT_prog]
    call path_basename
    mov rdi, rax
    call rx_push
    jmp 3f
2:  lea rdi, [rip + rx_sbuf]
    mov rsi, [r12 + RX_hdir]
    call sb_push_cstr
    lea rdi, [rip + rx_sbuf]
    mov esi, '/'
    call sb_push_byte
    mov rdi, [r12 + RX_run]
    call rx_push
3:  # the rest of argv, its paths the host's
    mov r13d, 1
    mov r14, [rip + argv_vec + VEC_ptr]
4:  mov rdi, [r14 + r13*8]
    test rdi, rdi
    jz 5f
    call rx_remap
    lea rdi, [rip + rx_sbuf]
    xor esi, esi
    call sb_push_byte
    inc r13
    cmp r13, 290
    jb 4b
5:  mov [rsp + 8], r13          # argc
    # the environment: NAME= with its value remapped, some left out, the target and the host
    xor r15d, r15d              # entries
    mov r14, [rip + env_vec + VEC_ptr]
6:  mov r13, [r14]
    test r13, r13
    jz 8f
    add r14, 8
    cmp r15d, 380
    jae 8f
    mov rdi, r13
    call rx_env_drop
    test eax, eax
    jnz 6b
    mov rdi, r13
    lea rsi, [rip + .Le_target]
    mov edx, 12
    call memeq
    test eax, eax
    jz 61f
    lea rdi, [rip + .Le_target_linux]
    call rx_push
    inc r15d
    jmp 6b
61: mov rax, r13
62: cmp byte ptr [rax], 0
    je 6b
    cmp byte ptr [rax], '='
    je 63f
    inc rax
    jmp 62b
63: lea rdx, [rax + 1]
    sub rdx, r13
    mov [rsp + 16], rax
    lea rdi, [rip + rx_sbuf]
    mov rsi, r13
    call sb_push
    mov rdi, [rsp + 16]
    inc rdi
    call rx_remap
    lea rdi, [rip + rx_sbuf]
    xor esi, esi
    call sb_push_byte
    inc r15d
    jmp 6b
8:  lea rdi, [rip + rx_sbuf]
    lea rsi, [rip + .Le_remote]
    call sb_push_cstr
    call remote_spec
    mov rdi, rax
    call rx_push
    inc r15d
    # the pointers (the strings do not move any more)
    mov rsi, [rip + rx_sbuf + SB_ptr]
    lea rdi, [rip + rx_argv]
    mov rcx, [rsp + 8]
    call rx_pointers
    mov rsi, rax
    lea rdi, [rip + rx_envv]
    mov ecx, r15d
    call rx_pointers
    # the confinement: NEEDS DIR SCRIPT STATE PROJECT RUNS
    lea rdi, [rip + rx_conf]
    call sb_clear
    lea rdi, [rip + rx_conf]
    mov esi, [rbx + EXT_needs]
    call sb_push_u64
    call rx_conf_end
    lea rdi, [rip + rx_conf]
    mov rsi, [r12 + RX_hdir]
    call sb_push_cstr
    call rx_conf_end
    mov rdi, [rbx + EXT_script]
    test rdi, rdi
    jz 81f
    cmp byte ptr [rdi], 0
    je 81f
    mov rsi, [rbx + EXT_dir]
    call rx_prefix
    test rax, rax
    jz 81f
    mov r13, rax
    lea rdi, [rip + rx_conf]
    mov rsi, [r12 + RX_hdir]
    call sb_push_cstr
    lea rdi, [rip + rx_conf]
    mov rsi, r13
    call sb_push_cstr
81: call rx_conf_end
    lea rdi, [rip + rx_conf]
    lea rsi, [rip + rx_hstate]
    call sb_push_cstr
    call rx_conf_end
    mov rsi, [rip + g_project]
    test rsi, rsi
    jz 82f
    lea rdi, [rip + rx_conf]
    call sb_push_cstr
82: call rx_conf_end
    mov rsi, [rbx + EXT_runs]
    test rsi, rsi
    jz 83f
    lea rdi, [rip + rx_conf]
    call sb_push_cstr
83: call rx_conf_end
    mov rax, [rip + rx_conf + SB_ptr]
    mov [rip + remote_confine_blk], rax
    mov rax, [rip + rx_conf + SB_len]
    mov [rip + remote_confine_len], rax
    # remote_spawn(argv, envp, cwd, flags, errfd, input, input length)
    lea rdi, [rip + rx_argv]
    lea rsi, [rip + rx_envv]
    mov rdx, [r12 + RX_hdir]
    mov ecx, [rsp]
    mov r8d, [rbx + EXT_log]
    test r8d, r8d
    jns 9f
    mov r8d, -1
9:  xor r9d, r9d
    push 0
    push 0
    call remote_spawn
    add rsp, 16
    test rax, rax
    jle .Lxsp_failed
    mov [rbx + EXT_pid], eax
    mov [rbx + EXT_out], edx
    mov r13d, edx
    mov r14, rax
    # its input: a copy of the same socket (ext.s watches input and output apart)
    mov edi, r13d
    xor esi, esi                # F_DUPFD
    mov edx, 3
    SYS SYS_fcntl
    mov [rbx + EXT_in], eax
    mov edi, eax
    mov esi, 2                  # F_SETFD FD_CLOEXEC
    mov edx, 1
    SYS SYS_fcntl
    mov dword ptr [r12 + RX_ran], 1
    # how the host holds it
    mov eax, [rip + g_remote_confined]
    test eax, eax
    jns 10f
    mov eax, CONFINED_NO
10: mov [rbx + EXT_confined], eax
    mov qword ptr [rbx + EXT_confine_why], 0
    cmp byte ptr [rip + g_remote_confine_why], 0
    jne 11f
    cmp dword ptr [rip + g_remote_confined], 0
    jge 12f
    lea rsi, [rip + .Lr_no_answer]
    jmp 111f
11: lea rsi, [rip + g_remote_confine_why]
111: lea rdi, [r12 + RX_cwhy]
    mov r13, rsi
    lea rsi, [rip + .Lr_on_host]
    lea rdx, [r12 + RX_cwhy + 370]
    call rx_cpy
    mov rdi, rax
    mov rsi, r13
    lea rdx, [r12 + RX_cwhy + 370]
    call rx_cpy
    lea rax, [r12 + RX_cwhy]
    mov [rbx + EXT_confine_why], rax
12: mov rax, r14
    EPILOGUE
.Lxsp_failed:
    mov r13, rax
    lea rcx, [rip + .Lr_start]
    cmp rax, -2
    jne 1f
    lea rcx, [rip + .Lr_no_program]
1:  cmp rax, -107
    jne 2f
    lea rcx, [rip + .Lr_lost]
2:  mov [rbx + EXT_reason], rcx
    mov rax, r13
    test rax, rax
    jnz 3f
    mov rax, -5
3:  EPILOGUE

# rx_conf_end(): a NUL onto rx_conf
rx_conf_end:
    lea rdi, [rip + rx_conf]
    xor esi, esi
    jmp sb_push_byte

# rx_pointers(array, strings, count) -> rax past the last: count NUL-terminated strings' addresses,
# then 0
rx_pointers:
    test rcx, rcx
    jz 9f
1:  mov [rdi], rsi
    add rdi, 8
2:  cmp byte ptr [rsi], 0
    lea rsi, [rsi + 1]
    jne 2b
    dec rcx
    jnz 1b
9:  mov qword ptr [rdi], 0
    mov rax, rsi
    ret

.section .rodata
.Lr_where_local: .asciz "where = local cannot go with project or home in [needs]: it runs on this computer and sees the host's files only through rhun"
.Lr_full: .asciz "too many extensions for the host"
.Lr_no_linux: .asciz "it has no Linux build for the host (run.linux-x86_64 in its extension.ini)"
.Lr_no_release: .asciz "its Linux build for the host is not in its folder, and it was not installed from a release that has one"
.Lr_unreadable: .asciz "its folder cannot be read"
.Lr_too_big: .asciz "its folder is over 64 MB, too big to copy to the host"
.Lr_lost: .asciz "the host is not connected"
.Lr_copy: .asciz "its files could not be copied to the host"
.Lr_fetch: .asciz "its Linux build could not be fetched: "
.Lr_fetch_start: .asciz "its Linux build could not be fetched"
.Lr_unknown: .asciz "no reason given"
.Lr_no_program: .asciz "its program is not on the host (a runtime it needs may be missing there)"
.Lr_start: .asciz "the host could not start it"
.Lr_no_answer: .asciz "the host did not say how it is held"
.Lr_on_host: .asciz "on the host: "
.ifdef WINDOWS
.Lr_no_fetch_windows: .asciz "its Linux build is not in its folder (fetching one is not done from Windows)"
.endif
.Ll_found: .asciz "extension on the host: "
.Ll_copying: .asciz "extension copying to "
.Ll_copied: .asciz "extension copied: "
.Ll_failed: .asciz "extension cannot run on the host: "
.Ll_fetching: .asciz "extension's Linux build fetched into "
.Lw_copy: .asciz "getting ready on the host"
.Lw_conn: .asciz "waiting for the host"
.Lw_fetch: .asciz "fetching its Linux build for the host"
.Lw_github: .asciz "github"
.Lk_source: .asciz "source"
.Lk_run_linux: .asciz "run.linux-x86_64"
.Lmanifest: .asciz "extension.ini"
.Lrec_name: .asciz ".rhun-install"
.Lgit_name: .asciz ".git"
.Ldashes: .asciz "--"
.Lzero: .asciz "0"
.Lsub_cache: .asciz "/.cache/rhun-remote/extensions/"
.Lsub_state: .asciz "/.local/state/rhun/extensions/"
.Lsub_fetch: .asciz "/remote/extensions"
.Lsub_x: .asciz "/x"
.Lsuf_part: .asciz ".part-"
.Lv_stat: .asciz "stat"
.Lv_mkdir: .asciz "mkdir"
.Lv_write: .asciz "write"
.Lv_rename: .asciz "rename"
.Lv_remove: .asciz "remove"
.Lat_self: .asciz "@self"
.Lenv_home: .asciz "HOME"
.Le_target: .ascii "RHUN_TARGET="
.Le_target_linux: .asciz "RHUN_TARGET=linux-x86_64"
.Le_remote: .asciz "RHUN_REMOTE="
.Ltarget: .asciz "linux-x86_64"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-install"
.Ldash: .asciz "-"
.Ld_path: .asciz "PATH="
.Ld_socket: .asciz "RHUN_SOCKET="
.Ld_devdir: .asciz "DEVELOPER_DIR="
.Ld_xdg_config: .asciz "XDG_CONFIG_HOME="
.Ld_xdg_state: .asciz "XDG_STATE_HOME="
.Ld_xdg_data: .asciz "XDG_DATA_HOME="
.Ld_xdg_runtime: .asciz "XDG_RUNTIME_DIR="
.p2align 3
rx_env_dropped:
    .quad .Ld_path, .Ld_socket, .Ld_devdir, .Ld_xdg_config, .Ld_xdg_state, .Ld_xdg_data
    .quad .Ld_xdg_runtime, 0
