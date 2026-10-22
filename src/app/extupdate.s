# extension updates (extension management): what is known about each installed extension's newer
# versions, kept in $XDG_STATE_HOME/rhun/extension-updates:
#   checked = UNIX          the last check
#   [owner/name]
#   latest = TAG            the newest version offered (the index's pinned tag, or GitHub's latest)
#   from = index|github
#   skip = TAG              rolled back from: automatic updates leave this tag alone
#   asks = TAG              it asks for more access: waits for the user
#   error = TEXT            why the last check or update of it failed
.include "rhun.inc"

.equ XU_MAX, EXT_CAP
STRUCT
F XE_name, 104                  # owner/name
F XE_latest, 72
F XE_skip, 72
F XE_asks, 72
F XE_error, 160
F XE_from, 4                    # XF_*
F XE_pad, 4
ENDSTRUCT XE_SIZE
.equ XF_NONE, 0
.equ XF_GITHUB, 1
.equ XF_INDEX, 2
.equ XU_FIRST, 60000            # ms after startup: the first automatic check
.equ XU_EVERY, 86400000         # ms between automatic checks
.equ XC_IDLE, 0                 # the check: nothing running
.equ XC_INDEX, 1                # fetching the index
.equ XC_GITHUB, 2               # asking GitHub
.equ XQ_SIZE, 112               # a queued update: owner/name (104), IP_* (4)

.bss
.p2align 3
xu_sb: .zero SB_SIZE            # scratch: paths, the state file
xu_path: .zero SB_SIZE          # the state file's path
xu_n: .long 0
.p2align 3
xu_checked: .quad 0             # unix seconds of the last check
xu_tab: .zero XE_SIZE * XU_MAX
xu_out: .zero SB_SIZE           # the check job's output
xu_args: .zero SB_SIZE          # the names it asks about
xu_argv: .zero 8 * (XU_MAX + 8)
xu_next_at: .quad 0             # time_ms of the next automatic check, 0 for none
xu_every: .quad 0
xu_first: .quad 0
xu_pid: .long 0
xu_phase: .long 0               # XC_*
xu_manual: .long 0              # the check was asked for: its result is reported
xq_n: .long 0                   # updates waiting
xu_error: .zero 256             # why the last check failed
xu_line: .zero 160
.p2align 3
xq_tab: .zero XQ_SIZE * XU_MAX
.ifdef WINDOWS
xu_ev: .zero 2 * SB_SIZE        # the check job's RHUN_EC_* variables
xu_envv: .zero 24
xu_envp: .quad 0
xu_shell: .quad 0
.endif
.globl g_extup_desc
g_extup_desc: .zero 256         # the Check extensions now row's text in Settings

.data
xu_fd: .long -1

.text

# ---------------- the state ----------------

# extupdate_init(): what earlier checks found; install folders a crashed install left go
FN extupdate_init
    PROLOGUE INI_SIZE + 112     # the iterator, then a section's name (at most 100 bytes and a NUL)
    call install_leftovers
    call xu_state_path
    test rax, rax
    jz 9f
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    lea rdi, [rsp]
    mov rsi, rax
    call ini_init
    xor ebx, ebx                # the section's entry
1:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz 8f
    cmp qword ptr [rsp + INI_seclen], 0
    jne 3f
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_checked]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call parse_u64
    mov [rip + xu_checked], rax
    jmp 1b
3:  # [owner/name]: its entry (made when the section is new)
    test rbx, rbx
    jz 31f
    lea rdi, [rbx + XE_name]
    mov rsi, [rsp + INI_sec]
    mov rdx, [rsp + INI_seclen]
    call same_sec
    test eax, eax
    jnz 32f
31: xor ebx, ebx
    mov rsi, [rsp + INI_seclen]
    cmp rsi, 100
    ja 1b
    lea rdi, [rsp + INI_SIZE]
    mov rsi, [rsp + INI_sec]
    mov rdx, [rsp + INI_seclen]
    call copy_n
    lea rdi, [rsp + INI_SIZE]
    call xu_get
    mov rbx, rax
    test rbx, rbx
    jz 1b
32: lea rdi, [rsp]
    lea rsi, [rip + .Lk_latest]
    lea rdx, [rbx + XE_latest]
    mov ecx, 70
    call ini_take
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_skip]
    lea rdx, [rbx + XE_skip]
    mov ecx, 70
    call ini_take
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_asks]
    lea rdx, [rbx + XE_asks]
    mov ecx, 70
    call ini_take
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_error]
    lea rdx, [rbx + XE_error]
    mov ecx, 150
    call ini_take
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_from]
    call ini_key_is
    test eax, eax
    jz 1b
    mov dword ptr [rbx + XE_from], XF_GITHUB
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    lea rdx, [rip + .Lv_index]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov dword ptr [rbx + XE_from], XF_INDEX
    jmp 1b
8:  mov rdi, r12
    call mem_free
9:  call extupdate_schedule
    EPILOGUE

# same_sec(cstr, ptr, len) -> 1 when the cstr is the section's name
same_sec:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rax
    jmp str_eq_cstr

# copy_n(dst, ptr, len): len bytes and a NUL
copy_n:
    push rdx
    push rdi
    call memcpy
    pop rdi
    pop rdx
    mov byte ptr [rdi + rdx], 0
    ret

# ini_take(it, key, dst, max): when the iterator's key is key, its value (at most max bytes) into dst
ini_take:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13d, ecx
    call ini_key_is
    test eax, eax
    jz 9f
    mov rdx, [rbx + INI_vallen]
    cmp rdx, r13
    jbe 1f
    mov rdx, r13
1:  mov rdi, r12
    mov rsi, [rbx + INI_val]
    call copy_n
9:  EPILOGUE

# install_leftovers(): ROOT/.install-* folders older than an hour are a crashed install's
install_leftovers:
    PROLOGUE
    call ext_root_dir
    test rax, rax
    jz 9f
    mov rdi, rax
    lea rsi, [rip + leftover_cb]
    xor edx, edx
    call dir_each
9:  EPILOGUE

# leftover_cb(ctx, name, is_dir)
leftover_cb:
    PROLOGUE
    test edx, edx
    jz 9f
    mov rbx, rsi
    mov rdi, rsi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rip + .Linstall_prefix]
    mov ecx, 9
    call str_starts
    test eax, eax
    jz 9f
    call ext_root_dir
    mov rdi, rax
    mov rsi, rbx
    call path_join
    mov r12, rax
    mov rdi, rax
    call file_mtime
    mov r13, rax
    call time_now
    sub rax, r13
    cmp rax, 3600
    jb 8f
    mov rdi, r12
    call file_remove_tree
8:  mov rdi, r12
    call mem_free
9:  EPILOGUE

# xu_find(name cstr) -> its entry, or 0
xu_find:
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13d, [rip + xu_n]
    jae 8f
    imul rbx, r13, XE_SIZE
    lea rax, [rip + xu_tab]
    add rbx, rax
    inc r13d
    lea rdi, [rbx + XE_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# xu_get(name cstr) -> its entry, made when it has none (0 when the table is full)
xu_get:
    PROLOGUE
    mov r12, rdi
    call xu_find
    test rax, rax
    jnz 9f
    mov ecx, [rip + xu_n]
    cmp ecx, XU_MAX
    jae 9f
    inc dword ptr [rip + xu_n]
    imul rbx, rcx, XE_SIZE
    lea rax, [rip + xu_tab]
    add rbx, rax
    mov rdi, rbx
    xor esi, esi
    mov edx, XE_SIZE
    call memset
    lea rdi, [rbx + XE_name]
    mov rsi, r12
    mov ecx, 100
    call copy_upto
    mov rax, rbx
9:  EPILOGUE

# copy_upto(dst, src, max): at most max bytes of src and a NUL
copy_upto:
    xor edx, edx
1:  cmp edx, ecx
    jae 2f
    mov al, [rsi + rdx]
    test al, al
    jz 2f
    mov [rdi + rdx], al
    inc edx
    jmp 1b
2:  mov byte ptr [rdi + rdx], 0
    ret

# xu_state_path() -> $XDG_STATE_HOME/rhun/extension-updates (or ~/.local/state/...), or 0
xu_state_path:
    PROLOGUE
    lea rdi, [rip + xu_path]
    call sb_clear
    lea rdi, [rip + .Lenv_state]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    lea rdi, [rip + xu_path]
    mov rsi, rax
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 8f
    cmp byte ptr [rax], 0
    je 8f
    lea rdi, [rip + xu_path]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + xu_path]
    lea rsi, [rip + .Llocal_state]
    call sb_push_cstr
2:  lea rdi, [rip + xu_path]
    lea rsi, [rip + .Lstate_name]
    call sb_push_cstr
    lea rdi, [rip + xu_path]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + xu_path + SB_ptr]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# xu_save(): the state file from the table (entries with nothing to say are left out)
xu_save:
    PROLOGUE
    lea rdi, [rip + xu_sb]
    call sb_clear
    lea rdi, [rip + .Lw_head]
    call xu_push
    lea rdi, [rip + .Lw_checked]
    call xu_push
    lea rdi, [rip + xu_sb]
    mov rsi, [rip + xu_checked]
    call sb_push_u64
    lea rdi, [rip + .Lnl]
    call xu_push
    xor r12d, r12d
1:  cmp r12d, [rip + xu_n]
    jae 8f
    imul rbx, r12, XE_SIZE
    lea rax, [rip + xu_tab]
    add rbx, rax
    inc r12d
    mov al, [rbx + XE_latest]
    or al, [rbx + XE_skip]
    or al, [rbx + XE_asks]
    or al, [rbx + XE_error]
    jz 1b
    lea rdi, [rip + .Lw_open]
    call xu_push
    lea rdi, [rbx + XE_name]
    call xu_push
    lea rdi, [rip + .Lw_close]
    call xu_push
    lea rdi, [rip + .Lw_latest]
    lea rsi, [rbx + XE_latest]
    call xu_pair
    cmp dword ptr [rbx + XE_from], XF_NONE
    je 2f
    lea rdi, [rip + .Lw_from]
    lea rsi, [rip + .Lv_github]
    cmp dword ptr [rbx + XE_from], XF_INDEX
    jne 11f
    lea rsi, [rip + .Lv_index]
11: call xu_pair
2:  lea rdi, [rip + .Lw_skip]
    lea rsi, [rbx + XE_skip]
    call xu_pair
    lea rdi, [rip + .Lw_asks]
    lea rsi, [rbx + XE_asks]
    call xu_pair
    lea rdi, [rip + .Lw_error]
    lea rsi, [rbx + XE_error]
    call xu_pair
    jmp 1b
8:  call xu_state_path
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    call mkdir_parent
    mov rdi, rbx
    mov rsi, [rip + xu_sb + SB_ptr]
    mov rdx, [rip + xu_sb + SB_len]
    call file_write_all
9:  EPILOGUE

# xu_pair(key "k = ", value cstr): "k = value\n" onto xu_sb when the value is not empty
xu_pair:
    PROLOGUE
    cmp byte ptr [rsi], 0
    je 9f
    mov rbx, rsi
    call xu_push
    mov rdi, rbx
    call xu_push
    lea rdi, [rip + .Lnl]
    call xu_push
9:  EPILOGUE

# xu_push(cstr): onto xu_sb
xu_push:
    mov rsi, rdi
    lea rdi, [rip + xu_sb]
    jmp sb_push_cstr

# extupdate_skip(name, tag): rolled back from tag: automatic updates leave it alone
FN extupdate_skip
    PROLOGUE
    mov r12, rsi
    call xu_get
    test rax, rax
    jz 9f
    lea rdi, [rax + XE_skip]
    mov rsi, r12
    mov ecx, 70
    call copy_upto
    call xu_save
9:  EPILOGUE

# extupdate_forget(name): removed: nothing about it is kept
FN extupdate_forget
    PROLOGUE
    call xu_find
    test rax, rax
    jz 9f
    mov rdi, rax
    xor esi, esi
    mov edx, XE_SIZE
    call memset
    call xu_save
9:  EPILOGUE

# extupdate_install_done(name, tag, XU_*, reason or 0): how an update (or an install) of it ended
FN extupdate_install_done
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    call xu_get
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp r13d, XU_UPDATED
    jne 1f
    mov byte ptr [rbx + XE_asks], 0
    mov byte ptr [rbx + XE_error], 0
    jmp 8f
1:  cmp r13d, XU_ASKS
    jne 2f
    test r12, r12
    jz 8f
    lea rdi, [rbx + XE_asks]
    mov rsi, r12
    mov ecx, 70
    call copy_upto
    jmp 8f
2:  cmp r13d, XU_FAILED
    jne 9f
    test r14, r14
    jz 8f
    lea rdi, [rbx + XE_error]
    mov rsi, r14
    mov ecx, 150
    call copy_upto
8:  call xu_save
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- checks ----------------
# One check: the index first (extindexfile.s: the reviewed versions of the extensions it lists),
# then GitHub's /releases/latest redirect for each installed GitHub extension the index does not
# list (a fixed script fed the names: no API, no JSON). Automatic checks run 60 s after startup and
# then daily, never headless unless RHUN_EXT_UPDATE_EVERY=MS sets the period (tests). An extension
# the index lists is offered only its pinned version, the only kind [updates] extensions = install
# installs by itself (when it asks for no more access, and is not the version rolled back from).

# extupdate_schedule(): the first automatic check (extupdate_init calls it)
extupdate_schedule:
    PROLOGUE
    mov qword ptr [rip + xu_every], XU_EVERY
    mov qword ptr [rip + xu_first], XU_FIRST
    lea rdi, [rip + .Lenv_every]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rdi, rax
    mov esi, 20
    call parse_u64
    test rax, rax
    jz 1f
    mov [rip + xu_every], rax
    mov [rip + xu_first], rax
    jmp 2f
1:  cmp dword ptr [rip + g_headless], 0
    jne 9f                      # a script's run checks only when asked to
2:  call time_ms
    add rax, [rip + xu_first]
    mov [rip + xu_next_at], rax
9:  EPILOGUE

# extupdate_tick(): once per frame: the next queued update starts when no install runs; the
# automatic check when it is due
FN extupdate_tick
    PROLOGUE
    cmp dword ptr [rip + xq_n], 0
    je 2f
    cmp dword ptr [rip + xu_phase], XC_IDLE
    jne 2f
    call ext_install_busy
    test eax, eax
    jnz 2f
    call xq_next
2:  mov rbx, [rip + xu_next_at]
    test rbx, rbx
    jz 9f
    call time_ms
    cmp rax, rbx
    jb 9f
    add rax, [rip + xu_every]
    mov [rip + xu_next_at], rax
    cmp dword ptr [rip + cfg_ext_updates], XM_OFF
    je 9f
    cmp dword ptr [rip + xu_phase], XC_IDLE
    jne 9f
    xor edi, edi
    call xu_check_start
9:  EPILOGUE

# extupdate_timeout() -> ms until the loop should come back: the next check, soon while updates wait
# in the queue, or -1
FN extupdate_timeout
    mov eax, 100
    cmp dword ptr [rip + xq_n], 0
    jne 2f
    mov rax, [rip + xu_next_at]
    test rax, rax
    jz 1f
    push rbx
    mov rbx, rax
    call time_ms
    sub rbx, rax
    mov rax, rbx
    pop rbx
    test rax, rax
    jns 3f
    xor eax, eax
3:  cmp rax, 0x7fffffff
    jbe 2f
    mov eax, 0x7fffffff
2:  ret
1:  mov eax, -1
    ret

# extupdate_busy() -> 1 while a check runs or updates wait
FN extupdate_busy
    xor eax, eax
    cmp dword ptr [rip + xu_phase], XC_IDLE
    jne 1f
    cmp dword ptr [rip + xq_n], 0
    je 2f
1:  mov eax, 1
2:  ret

# cmd_check_extensions(): Check extensions now (Settings > Updates, the Extensions page)
FN cmd_check_extensions
    PROLOGUE
    cmp dword ptr [rip + xu_phase], XC_IDLE
    jne 9f
    mov edi, 1
    call xu_check_start
9:  EPILOGUE

# xu_check_start(asked): the index, then GitHub's answers (asked: the result is reported)
xu_check_start:
    PROLOGUE
    mov [rip + xu_manual], edi
    mov byte ptr [rip + xu_error], 0
    mov dword ptr [rip + xu_phase], XC_INDEX
    lea rdi, [rip + xu_index_done]
    call extindex_fetch          # calls xu_index_done when the index is in (or could not be had)
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# xu_index_done(): the index is fresh (or is what the cache holds): the extensions it lists are
# offered its pinned version; the others are asked about on GitHub
xu_index_done:
    PROLOGUE
    cmp dword ptr [rip + xu_phase], XC_INDEX
    jne 9f
    call xu_from_index
    call xu_github_start
9:  EPILOGUE

# xu_from_index(): each installed GitHub extension the index lists: its pinned tag is the latest,
# unless that version needs a newer rhun or has no archive for this system (then nothing is offered
# and the entry says why)
xu_from_index:
    PROLOGUE 16
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call xu_checkable
    test eax, eax
    jz 1b
    mov rdi, rbx
    call ext_full_name
    mov r13, rax
    mov rdi, rax
    call extindex_entry
    test rax, rax
    jz 1b
    mov r14, rax
    mov rdi, r13
    call xu_get
    test rax, rax
    jz 1b
    mov r15, rax
    mov dword ptr [r15 + XE_from], XF_INDEX
    mov byte ptr [r15 + XE_error], 0
    mov byte ptr [r15 + XE_latest], 0
    mov rdi, r14
    call extindex_newer
    test rax, rax
    jz 2f
    # "the reviewed version needs rhun 0.19.0"
    mov [rsp], rax
    lea rdi, [r15 + XE_error]
    lea rsi, [rip + .Le_newer]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rsp]
    mov ecx, 60
    call copy_upto
    jmp 1b
2:  cmp qword ptr [r14 + XI_digest], 0
    jne 3f
    lea rdi, [r15 + XE_error]
    lea rsi, [rip + .Le_no_target]
    mov ecx, 150
    call copy_upto
    jmp 1b
3:  lea rdi, [r15 + XE_latest]
    mov rsi, [r14 + XI_tag]
    mov ecx, 70
    call copy_upto
    jmp 1b
9:  EPILOGUE

# xu_checkable(ext) -> 1 for an installed extension that came from GitHub (a record saying so, or
# none: copied by hand, owner/name is its repository)
xu_checkable:
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 9f
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 9f
    mov eax, 1
    cmp qword ptr [rbx + EXT_rec], 0
    je 9f
    mov rdi, rbx
    lea rsi, [rip + .Lk_source]
    call extrec_get
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lv_github]
    call str_eq_cstr
    EPILOGUE
8:  mov eax, 1
9:  EPILOGUE

# xu_github_start(): the redirect check for each installed GitHub extension the index does not list
xu_github_start:
    PROLOGUE
    lea rdi, [rip + xu_args]
    call sb_clear
    xor r13d, r13d              # names
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 2f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call xu_checkable
    test eax, eax
    jz 1b
    mov rdi, rbx
    call ext_full_name
    mov r14, rax
    mov rdi, rax
    call extindex_entry
    test rax, rax
    jnz 1b                      # the index answers for it
    lea rdi, [rip + xu_args]
    mov rsi, r14
    call sb_push_cstr
    lea rdi, [rip + xu_args]
    mov esi, ' '
    call sb_push_byte
    inc r13d
    jmp 1b
2:  test r13d, r13d
    jz .Lgs_done
    lea rdi, [rip + xu_args]
    xor esi, esi
    call sb_push_byte
    call xu_spawn_check
    test eax, eax
    jnz 9f
    lea rdi, [rip + .Le_start]
    call xu_fail
.Lgs_done:
    call xu_check_done
9:  EPILOGUE

# xu_spawn_check() -> eax 1 when the check job runs for the names in xu_args (space separated)
xu_spawn_check:
    PROLOGUE 16
.ifdef WINDOWS
    lea rdi, [rip + xu_ev]
    lea rsi, [rip + .Lec_base]
    call ext_release_base
    mov rdx, rax
    lea rdi, [rip + xu_ev]
    lea rsi, [rip + .Lec_base]
    call ei_var
    mov [rip + xu_envv], rax
    lea rdi, [rip + xu_ev + SB_SIZE]
    lea rsi, [rip + .Lec_repos]
    mov rdx, [rip + xu_args + SB_ptr]
    call ei_var
    mov [rip + xu_envv + 8], rax
    mov qword ptr [rip + xu_envv + 16], 0
    mov rdi, [rip + xu_envp]
    call mem_free
    lea rdi, [rip + xu_envv]
    call env_make
    mov [rip + xu_envp], rax
    mov rdi, [rip + xu_shell]
    call mem_free
    lea rdi, [rip + .Lec_shell]
    call proc_which
    mov [rip + xu_shell], rax
    test rax, rax
    jz 8f
    lea rcx, [rip + xu_argv]
    mov [rcx], rax
    lea rax, [rip + .Lec_noprofile]
    mov [rcx + 8], rax
    lea rax, [rip + .Lec_noninteractive]
    mov [rcx + 16], rax
    lea rax, [rip + .Lec_outputformat]
    mov [rcx + 24], rax
    lea rax, [rip + .Lec_text]
    mov [rcx + 32], rax
    lea rax, [rip + .Lec_encoded]
    mov [rcx + 40], rax
    lea rax, [rip + ext_check_script]
    mov [rcx + 48], rax
    mov qword ptr [rcx + 56], 0
    mov rdi, rcx
    mov rsi, [rip + xu_envp]
.else
    # argv: sh -c SCRIPT rhun-check BASE OWNER/NAME...: the names split at their spaces
    lea rcx, [rip + xu_argv]
    lea rax, [rip + .Lsh]
    mov [rcx], rax
    lea rax, [rip + .Ldash_c]
    mov [rcx + 8], rax
    lea rax, [rip + check_script]
    mov [rcx + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rcx + 24], rax
    call ext_release_base
    lea rcx, [rip + xu_argv]
    mov [rcx + 32], rax
    mov ebx, 5                  # the next argv slot
    mov r12, [rip + xu_args + SB_ptr]
1:  cmp byte ptr [r12], 0
    je 3f
    lea rcx, [rip + xu_argv]
    mov [rcx + rbx*8], r12
    inc ebx
2:  inc r12
    cmp byte ptr [r12], ' '
    jne 2b
    mov byte ptr [r12], 0
    inc r12
    cmp ebx, XU_MAX + 5
    jb 1b
3:  lea rcx, [rip + xu_argv]
    mov qword ptr [rcx + rbx*8], 0
    lea rdi, [rip + xu_argv]
    mov rsi, [rip + g_envp]
.endif
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    mov [rip + xu_pid], eax
    mov [rip + xu_fd], edx
    lea rdi, [rip + xu_out]
    call sb_clear
    mov edi, [rip + xu_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_xu_job]
    xor ecx, ecx
    call watch_add
    mov dword ptr [rip + xu_phase], XC_GITHUB
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# on_xu_job(fd, revents, ctx): the check job's output; at its end, its answers
on_xu_job:
    PROLOGUE
1:  lea rdi, [rip + xu_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + xu_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    cmp qword ptr [rip + xu_out + SB_len], 262144
    jae 1b
    add [rip + xu_out + SB_len], rax
    jmp 1b
2:  mov edi, [rip + xu_fd]
    call watch_remove
    mov edi, [rip + xu_fd]
    SYS SYS_close
    mov dword ptr [rip + xu_fd], -1
    mov edi, [rip + xu_pid]
    xor esi, esi
    call proc_wait
    mov ebx, eax
    lea rdi, [rip + xu_out]
    xor esi, esi
    call sb_push_byte
    mov edi, ebx
    call xu_github_done
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# xu_github_done(status): "owner/name TAG" or "owner/name - why" a line each
xu_github_done:
    PROLOGUE
    mov r15d, edi
    mov r12, [rip + xu_out + SB_ptr]
    xor r14d, r14d              # lines understood
1:  cmp byte ptr [r12], 0
    je 7f
    # the line's end
    mov r13, r12
2:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 3f
    cmp eax, 10
    je 3f
    inc r13
    jmp 2b
3:  mov bl, [r13]
    mov byte ptr [r13], 0
    mov rdi, r12
    call xu_answer
    add r14d, eax
    mov [r13], bl
    lea r12, [r13 + 1]
    cmp bl, 0
    jne 1b
7:  test r14d, r14d
    jnz 8f
    # nothing understood: the job's own words (needs curl), or that it failed
    mov rdi, [rip + xu_out + SB_ptr]
    call xu_trim_line
    lea rdi, [rip + .Le_check]
    cmp byte ptr [rax], 0
    je 71f
    mov rdi, rax
71: call xu_fail
8:  call xu_check_done
    EPILOGUE

# xu_trim_line(cstr) -> its first line without the CR, at most 150 bytes (in xu_line)
xu_trim_line:
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    test eax, eax
    jz 2f
    cmp eax, 10
    je 2f
    cmp eax, 13
    je 2f
    cmp ecx, 150
    jae 2f
    lea rdx, [rip + xu_line]
    mov [rdx + rcx], al
    inc ecx
    jmp 1b
2:  lea rax, [rip + xu_line]
    mov byte ptr [rax + rcx], 0
    ret

# xu_answer(line cstr) -> eax 1 when it was one: its entry's latest tag (from GitHub), or its error
xu_answer:
    PROLOGUE 112
    mov rbx, rdi
    # the name, up to the space
    xor ecx, ecx
1:  movzx eax, byte ptr [rbx + rcx]
    cmp eax, ' '
    je 2f
    test eax, eax
    jz 8f
    cmp ecx, 100
    jae 8f
    mov [rsp + rcx], al
    inc ecx
    jmp 1b
2:  mov byte ptr [rsp + rcx], 0
    test ecx, ecx
    jz 8f
    lea r12, [rbx + rcx + 1]
    lea rdi, [rsp]
    call xu_get
    test rax, rax
    jz 8f
    mov r13, rax
    cmp byte ptr [r12], '-'
    jne 4f
    cmp byte ptr [r12 + 1], ' '
    jne 4f
    # "- why"
    lea rdi, [r12 + 2]
    call xu_trim_line
    lea rdi, [r13 + XE_error]
    mov rsi, rax
    mov ecx, 150
    call copy_upto
    jmp 7f
4:  # a tag: [0-9A-Za-z._-]{1,64}
    mov rdi, r12
    call xu_trim_line
    mov r14, rax
    xor ecx, ecx
5:  movzx edx, byte ptr [r14 + rcx]
    test edx, edx
    jz 6f
    inc ecx
    cmp ecx, 64
    ja 51f
    cmp edx, '.'
    je 5b
    cmp edx, '_'
    je 5b
    cmp edx, '-'
    je 5b
    lea eax, [rdx - '0']
    cmp eax, 9
    jbe 5b
    or edx, 0x20
    sub edx, 'a'
    cmp edx, 25
    jbe 5b
51: lea rdi, [r13 + XE_error]
    lea rsi, [rip + .Le_tag]
    mov ecx, 150
    call copy_upto
    jmp 7f
6:  test ecx, ecx
    jz 51b
    lea rdi, [r13 + XE_latest]
    mov rsi, r14
    mov ecx, 70
    call copy_upto
    mov dword ptr [r13 + XE_from], XF_GITHUB
    mov byte ptr [r13 + XE_error], 0
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# xu_fail(why): the check could not be done
xu_fail:
    mov rsi, rdi
    lea rdi, [rip + xu_error]
    mov ecx, 200
    jmp copy_upto

# xu_check_done(): the answers are in: kept, the automatic updates queued, an asked-for check reports
xu_check_done:
    PROLOGUE
    mov dword ptr [rip + xu_phase], XC_IDLE
    call time_now
    mov [rip + xu_checked], rax
    call xu_save
    cmp dword ptr [rip + cfg_ext_updates], XM_INSTALL
    jne 1f
    call xu_queue_auto
1:  cmp dword ptr [rip + xu_manual], 0
    je 9f
    mov dword ptr [rip + xu_manual], 0
    lea rdi, [rip + xu_sb]
    call sb_clear
    cmp byte ptr [rip + xu_error], 0
    je 2f
    lea rdi, [rip + .Lt_couldnt]
    call xu_push
    lea rdi, [rip + xu_error]
    call xu_push
    jmp 8f
2:  call extupdate_count
    test eax, eax
    jnz 3f
    lea rdi, [rip + .Lt_up_to_date]
    call xu_push
    jmp 8f
3:  mov ebx, eax
    lea rdi, [rip + xu_sb]
    mov esi, ebx
    call sb_push_u64
    lea rdi, [rip + .Lt_updates]
    cmp ebx, 1
    jne 4f
    lea rdi, [rip + .Lt_update]
4:  call xu_push
8:  lea rdi, [rip + xu_sb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + xu_sb + SB_ptr]
    call app_toast
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# xu_queue_auto(): automatic mode: each reviewed (index-pinned) update that asks for no more access
# and is not the version rolled back from waits for its turn in the queue
xu_queue_auto:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    mov rdi, rbx
    call extupdate_state
    cmp eax, XS_AVAILABLE
    jne 1b
    cmp dword ptr [rdx + XE_from], XF_INDEX
    jne 1b
    mov rdi, rbx
    mov esi, IP_AUTO
    call xq_add
    jmp 1b
9:  EPILOGUE

# ---------------- what is offered ----------------

# extupdate_state(ext) -> eax XS_*, rdx its entry (or 0): available (a newer version), asks (it asks
# for more access: waits for the user), skipped (the version rolled back from), error (the last
# check of it failed), or none (current, or nothing known)
FN extupdate_state
    PROLOGUE 64
    mov rbx, rdi
    xor r12d, r12d
    call xu_checkable           # a link, a folder or an archive install is never offered updates
    test eax, eax
    jz 9f
    mov rdi, rbx
    call ext_full_name
    mov rdi, rax
    call xu_find
    mov r12, rax
    xor eax, eax
    test r12, r12
    jz 9f
    mov eax, XS_ERROR
    cmp byte ptr [r12 + XE_error], 0
    jne 9f
    xor eax, eax
    cmp byte ptr [r12 + XE_latest], 0
    je 9f
    mov rsi, [rbx + EXT_version]
    test rsi, rsi
    jz 9f
    # the tag as a version ("v0.1.2" is 0.1.2), compared with the installed one
    lea rsi, [r12 + XE_latest]
    cmp byte ptr [rsi], 'v'
    jne 1f
    inc rsi
1:  mov r13, rsi
    mov rdi, rsi
    call strlen
    mov rdi, r13
    mov rsi, rax
    call ver_valid
    test eax, eax
    jz 9f
    mov rdi, r13
    mov rsi, [rbx + EXT_version]
    call ver_cmp
    mov ecx, eax
    xor eax, eax
    cmp ecx, 0
    jle 9f
    lea rdi, [r12 + XE_latest]
    lea rsi, [r12 + XE_asks]
    call strcmp_eq
    mov ecx, eax
    mov eax, XS_ASKS
    test ecx, ecx
    jnz 9f
    lea rdi, [r12 + XE_latest]
    lea rsi, [r12 + XE_skip]
    call strcmp_eq
    mov ecx, eax
    mov eax, XS_SKIPPED
    test ecx, ecx
    jnz 9f
    mov eax, XS_AVAILABLE
9:  mov rdx, r12
    EPILOGUE

# extupdate_offer(ext) -> rax the version offered (the latest tag without its "v"), or 0
FN extupdate_offer
    PROLOGUE
    call extupdate_state
    cmp eax, XS_AVAILABLE
    je 1f
    cmp eax, XS_ASKS
    je 1f
    cmp eax, XS_SKIPPED
    je 1f
    xor eax, eax
    EPILOGUE
1:  lea rax, [rdx + XE_latest]
    cmp byte ptr [rax], 'v'
    jne 2f
    inc rax
2:  EPILOGUE

# extupdate_count() -> how many installed extensions have an update waiting for the user (available
# or asking for more; not the versions rolled back from)
FN extupdate_count
    PROLOGUE
    xor r13d, r13d
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    mov rdi, rbx
    call extupdate_state
    cmp eax, XS_AVAILABLE
    je 2f
    cmp eax, XS_ASKS
    jne 1b
2:  inc r13d
    jmp 1b
9:  mov eax, r13d
    EPILOGUE

# extupdate_update(ext): Update: its offered version, as an update asked for (a dialog when nobody
# reviewed it or it asks for more)
FN extupdate_update
    PROLOGUE
    mov rbx, rdi
    call extupdate_offer
    test rax, rax
    jz 8f
    mov rdi, rbx
    mov esi, IP_UPDATE
    call xq_add
    call extupdate_tick         # at once when nothing else runs
    EPILOGUE
8:  lea rdi, [rip + .Le_no_update]
    call app_toast
    EPILOGUE

# extupdate_update_all(): Update all: each update waiting for the user, one after another
FN extupdate_update_all
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    mov rdi, rbx
    call extupdate_state
    cmp eax, XS_AVAILABLE
    je 2f
    cmp eax, XS_ASKS
    jne 1b
2:  mov rdi, rbx
    mov esi, IP_UPDATE
    call xq_add
    jmp 1b
9:  call extupdate_tick
    EPILOGUE

# extupdate_release_url(ext, sb): "BASE/OWNER/NAME/releases/tag/TAG" of the offered version onto sb
# (What's new)
FN extupdate_release_url
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call extupdate_state
    mov r13, rdx
    test r13, r13
    jz 9f
    call ext_release_base
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    lea rsi, [r13 + XE_name]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lrelease_tag]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [r13 + XE_latest]
    call sb_push_cstr
9:  EPILOGUE

# ---------------- the queue ----------------

# xq_add(ext, IP_UPDATE | IP_AUTO): its update waits for its turn (once)
xq_add:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rbx
    call ext_full_name
    mov r13, rax
    xor r14d, r14d
1:  cmp r14d, [rip + xq_n]
    jae 2f
    imul rdi, r14, XQ_SIZE
    lea rax, [rip + xq_tab]
    add rdi, rax
    inc r14d
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    jmp 9f                      # waiting already
2:  mov ecx, [rip + xq_n]
    cmp ecx, XU_MAX
    jae 9f
    inc dword ptr [rip + xq_n]
    imul rdi, rcx, XQ_SIZE
    lea rax, [rip + xq_tab]
    add rdi, rax
    mov [rdi + 104], r12d
    mov rsi, r13
    mov ecx, 100
    call copy_upto
9:  EPILOGUE

# xq_next(): the first waiting update starts
xq_next:
    PROLOGUE 240
    lea rsi, [rip + xq_tab]
    lea rdi, [rsp]
    mov ecx, 100
    call copy_upto
    mov eax, [rip + xq_tab + 104]
    mov [rsp + 232], eax
    # the rest move up
    dec dword ptr [rip + xq_n]
    lea rdi, [rip + xq_tab]
    lea rsi, [rip + xq_tab + XQ_SIZE]
    mov eax, [rip + xq_n]
    imul edx, eax, XQ_SIZE
    call memmove
    # still installed, still offered?
    lea rdi, [rsp]
    call strlen
    lea rdi, [rsp]
    mov rsi, rax
    call ext_by_name
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rbx
    call extupdate_state
    mov r12, rdx
    cmp eax, XS_AVAILABLE
    je 1f
    cmp eax, XS_ASKS
    je 1f
    cmp eax, XS_SKIPPED
    jne 9f
    cmp dword ptr [rsp + 232], IP_AUTO
    je 9f
1:  mov rdi, [rbx + EXT_owner]
    mov rsi, [rbx + EXT_name]
    lea rdx, [r12 + XE_latest]
    mov ecx, [rsp + 232]
    call ext_install_github
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- what is shown ----------------

# extupdate_desc_refresh(): g_extup_desc, the Check extensions now row's text in Settings
FN extupdate_desc_refresh
    PROLOGUE
    lea rdi, [rip + xu_sb]
    call sb_clear
    cmp dword ptr [rip + xu_phase], XC_IDLE
    je 1f
    lea rdi, [rip + .Ld_checking]
    call xu_push
    jmp 8f
1:  cmp byte ptr [rip + xu_error], 0
    je 2f
    lea rdi, [rip + .Lt_couldnt]
    call xu_push
    lea rdi, [rip + xu_error]
    call xu_push
    jmp 8f
2:  cmp qword ptr [rip + xu_checked], 0
    jne 3f
    lea rdi, [rip + .Ld_never]
    call xu_push
    jmp 8f
3:  call extupdate_count
    test eax, eax
    jnz 4f
    lea rdi, [rip + .Ld_up_to_date]
    call xu_push
    jmp 5f
4:  mov ebx, eax
    lea rdi, [rip + xu_sb]
    mov esi, ebx
    call sb_push_u64
    lea rdi, [rip + .Lt_updates]
    cmp ebx, 1
    jne 41f
    lea rdi, [rip + .Lt_update]
41: call xu_push
5:  lea rdi, [rip + .Ld_checked]
    call xu_push
    call xu_push_age
    lea rdi, [rip + .Ld_close]
    call xu_push
8:  mov rsi, [rip + xu_sb + SB_ptr]
    mov rbx, [rip + xu_sb + SB_len]
    cmp rbx, 255
    jbe 81f
    mov ebx, 255
81: lea rdi, [rip + g_extup_desc]
    mov rdx, rbx
    call memcpy
    lea rax, [rip + g_extup_desc]
    mov byte ptr [rax + rbx], 0
    EPILOGUE

# xu_push_age(): how long ago the last check was, onto xu_sb ("5 min ago")
xu_push_age:
    PROLOGUE
    call time_now
    sub rax, [rip + xu_checked]
    jns 1f
    xor eax, eax
1:  cmp rax, 60
    jae 2f
    lea rdi, [rip + .Ld_now]
    call xu_push
    EPILOGUE
2:  lea r12, [rip + .Ld_min]
    mov ecx, 60
    cmp rax, 3600
    jb 3f
    lea r12, [rip + .Ld_hour]
    mov ecx, 3600
    cmp rax, 86400
    jb 3f
    lea r12, [rip + .Ld_days]
    mov ecx, 86400
3:  xor edx, edx
    div rcx
    mov rbx, rax
    lea rdi, [rip + xu_sb]
    mov rsi, rax
    call sb_push_u64
    cmp rbx, 1
    jne 4f
    lea rax, [rip + .Ld_days]
    cmp r12, rax
    jne 4f
    lea r12, [rip + .Ld_day]
4:  mov rdi, r12
    call xu_push
    EPILOGUE

# extupdate_dump(sb): print-ext-updates: "checked=0|1 busy=0|1", then a line per installed extension:
# "OWNER/NAME installed=0.1.0 latest=0.1.2 state=current|available|asks|skipped|error [reason]"
FN extupdate_dump
    PROLOGUE
    mov r15, rdi
    mov rdi, r15
    lea rsi, [rip + .Lp_checked]
    call sb_push_cstr
    xor esi, esi
    cmp qword ptr [rip + xu_checked], 0
    setne sil
    mov rdi, r15
    call sb_push_u64
    mov rdi, r15
    lea rsi, [rip + .Lp_busy]
    call sb_push_cstr
    call extupdate_busy
    mov rdi, r15
    mov esi, eax
    call sb_push_u64
    cmp byte ptr [rip + xu_error], 0
    je 1f
    mov rdi, r15
    lea rsi, [rip + .Lp_error]
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + xu_error]
    call sb_push_cstr
1:  mov rdi, r15
    mov esi, 10
    call sb_push_byte
    xor r12d, r12d
2:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 2b
    mov rdi, rbx
    call ext_full_name
    mov rdi, r15
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Lp_installed]
    call sb_push_cstr
    mov rsi, [rbx + EXT_version]
    test rsi, rsi
    jnz 3f
    lea rsi, [rip + .Ldash]
3:  mov rdi, r15
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Lp_latest]
    call sb_push_cstr
    mov rdi, rbx
    call extupdate_state
    mov r13d, eax
    mov r14, rdx
    lea rsi, [rip + .Ldash]
    test r14, r14
    jz 4f
    cmp byte ptr [r14 + XE_latest], 0
    je 4f
    lea rsi, [r14 + XE_latest]
    cmp byte ptr [rsi], 'v'
    jne 4f
    inc rsi
4:  mov rdi, r15
    call sb_push_cstr
    mov rdi, r15
    lea rsi, [rip + .Lp_state]
    call sb_push_cstr
    lea rax, [rip + xs_names]
    mov rsi, [rax + r13*8]
    mov rdi, r15
    call sb_push_cstr
    cmp r13d, XS_ERROR
    jne 5f
    mov rdi, r15
    mov esi, ' '
    call sb_push_byte
    mov rdi, r15
    lea rsi, [r14 + XE_error]
    call sb_push_cstr
5:  test r14, r14
    jz 6f
    cmp dword ptr [r14 + XE_from], XF_NONE
    je 6f
    mov rdi, r15
    lea rsi, [rip + .Lp_from_github]
    cmp dword ptr [r14 + XE_from], XF_INDEX
    jne 51f
    lea rsi, [rip + .Lp_from_index]
51: call sb_push_cstr
6:  mov rdi, r15
    mov esi, 10
    call sb_push_byte
    jmp 2b
9:  EPILOGUE

.section .rodata
.Lenv_state: .asciz "XDG_STATE_HOME"
.Lenv_home: .asciz "HOME"
.Llocal_state: .asciz "/.local/state"
.Lstate_name: .asciz "/rhun/extension-updates"
.Linstall_prefix: .asciz ".install-"
.Lk_checked: .asciz "checked"
.Lk_latest: .asciz "latest"
.Lk_skip: .asciz "skip"
.Lk_asks: .asciz "asks"
.Lk_error: .asciz "error"
.Lk_from: .asciz "from"
.Lv_index: .asciz "index"
.Lv_github: .asciz "github"
.Lw_head: .asciz "# extension updates rhun knows about; rhun rewrites this file\n"
.Lw_checked: .asciz "checked = "
.Lw_open: .asciz "\n["
.Lw_close: .asciz "]\n"
.Lw_latest: .asciz "latest = "
.Lw_from: .asciz "from = "
.Lw_skip: .asciz "skip = "
.Lw_asks: .asciz "asks = "
.Lw_error: .asciz "error = "
.Lnl: .asciz "\n"
.Lenv_every: .asciz "RHUN_EXT_UPDATE_EVERY"
.Lk_source: .asciz "source"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-check"
.Ldash: .asciz "-"
.Lrelease_tag: .asciz "/releases/tag/"
.Le_start: .asciz "the check did not start"
.Le_check: .asciz "the check failed"
.Le_tag: .asciz "its latest release has an unusable tag"
.Le_no_update: .asciz "No update is known for it; check for updates first"
.Le_newer: .asciz "the reviewed version needs rhun "
.Le_no_target: .asciz "the index has no version of it for this system"
.Lt_couldnt: .asciz "Couldn't check: "
.Lt_up_to_date: .asciz "Your extensions are up to date"
.Lt_update: .asciz " extension update available"
.Lt_updates: .asciz " extension updates available"
.Ld_checking: .asciz "Checking\342\200\246"
.Ld_never: .asciz "Not checked yet"
.Ld_up_to_date: .asciz "Up to date"
.Ld_checked: .asciz " (checked "
.Ld_close: .asciz ")"
.Ld_now: .asciz "just now"
.Ld_min: .asciz " min ago"
.Ld_hour: .asciz " h ago"
.Ld_day: .asciz " day ago"
.Ld_days: .asciz " days ago"
.Lp_checked: .asciz "checked="
.Lp_busy: .asciz " busy="
.Lp_error: .asciz " error="
.Lp_installed: .asciz " installed="
.Lp_latest: .asciz " latest="
.Lp_state: .asciz " state="
.Lp_from_index: .asciz " from=index"
.Lp_from_github: .asciz " from=github"
.Ls_current: .asciz "current"
.Ls_available: .asciz "available"
.Ls_asks: .asciz "asks"
.Ls_skipped: .asciz "skipped"
.Ls_error: .asciz "error"
.p2align 3
xs_names: .quad .Ls_current, .Ls_available, .Ls_asks, .Ls_skipped, .Ls_error
.ifdef WINDOWS
.Lec_base: .asciz "RHUN_EC_BASE="
.Lec_repos: .asciz "RHUN_EC_REPOS="
.Lec_shell: .asciz "powershell.exe"
.Lec_noprofile: .asciz "-NoProfile"
.Lec_noninteractive: .asciz "-NonInteractive"
.Lec_outputformat: .asciz "-OutputFormat"
.Lec_text: .asciz "Text"
.Lec_encoded: .asciz "-EncodedCommand"
.endif
# the redirect check: fixed text, the base and the names as arguments. Each name gets a line,
# "owner/name TAG" or "owner/name - why"; a base on https keeps its redirects on https
check_script:
    .ascii "set -u; base=$1; shift\n"
    .ascii "proto=; case $base in https:*) proto='--proto =https --proto-redir =https' ;; esac\n"
    .ascii "if command -v curl >/dev/null 2>&1; then curl=1; elif command -v wget >/dev/null 2>&1; then curl=; else echo 'needs curl or wget'; exit 1; fi\n"
    .ascii "for r in \"$@\"; do\n"
    .ascii "  if [ -n \"$curl\" ]; then\n"
    .ascii "    out=$(curl -sS $proto -o /dev/null --max-time 20 -w '%{http_code} %{redirect_url}' \"$base/$r/releases/latest\" 2>/dev/null) || { echo \"$r - no answer\"; continue; }\n"
    .ascii "    code=${out%% *} loc=${out#* }\n"
    .ascii "  else\n"
    .ascii "    loc=$(wget -S --max-redirect=0 -T 20 -O /dev/null \"$base/$r/releases/latest\" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tr -d '\\r' | head -n 1) code=302\n"
    .ascii "  fi\n"
    .ascii "  case $code in 404) echo \"$r - not found\"; continue ;; esac\n"
    .ascii "  case $loc in\n"
    .ascii "  */releases/tag/*) echo \"$r ${loc##*/releases/tag/}\" ;;\n"
    .ascii "  */releases/latest) loc=${loc%/releases/latest}; echo \"$r - moved to ${loc#\"$base\"/}\" ;;\n"
    .ascii "  *) echo \"$r - no release\" ;;\n"
    .ascii "  esac\n"
    .asciz "done\n"
