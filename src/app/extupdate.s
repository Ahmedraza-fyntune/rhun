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

.bss
.p2align 3
xu_sb: .zero SB_SIZE            # scratch: paths, the state file
xu_path: .zero SB_SIZE          # the state file's path
xu_n: .long 0
.p2align 3
xu_checked: .quad 0             # unix seconds of the last check
xu_tab: .zero XE_SIZE * XU_MAX

.text

# ---------------- the state ----------------

# extupdate_init(): what earlier checks found; install folders a crashed install left go
FN extupdate_init
    PROLOGUE INI_SIZE + 16
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
9:  EPILOGUE

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

# extupdate_tick(): once per frame: the automatic check when it is due
FN extupdate_tick
    ret

# extupdate_timeout() -> ms until the next automatic check, or -1
FN extupdate_timeout
    mov eax, -1
    ret

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
