# inotify: explorer refresh, agent sessions, files changed on disk, config reload, Omarchy theme, git
.include "rhun.inc"

.equ WK_EXPLORER, 1
.equ WK_AGENTS, 2
.equ WK_DOCS, 4
.equ WK_CONFIG, 8
.equ WK_OMARCHY, 16
.equ WK_GIT, 32
.equ WK_WORKTREE, 64
.equ WK_WAIT, 128               # the nearest folder there is above an open file's missing folder
.equ MAXWD, 4096
.equ WMASK, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE | IN_MODIFY | IN_MOVE_SELF
.equ RELOAD_DELAY_MS, 100

.bss
.p2align 3
wd_paths: .zero 8 * MAXWD
wd_kinds: .zero MAXWD
evbuf: .zero 16384
wait_path: .zero 4096
next_tick: .quad 0              # earliest pending reload or fade frame; 0 means no timer
.data
ino_fd: .long -1

.text

FN watch_init
    PROLOGUE
    mov edi, IN_NONBLOCK | IN_CLOEXEC
    SYS SYS_inotify_init1
    test rax, rax
    js 9f
    mov [rip + ino_fd], eax
    mov edi, eax
    mov esi, POLLIN
    lea rdx, [rip + on_inotify]
    xor ecx, ecx
    call watch_add
    call config_dir
    mov rdi, rax
    mov esi, WK_CONFIG
    call add_watch
    call omarchy_dir
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, WK_OMARCHY
    call add_watch
9:  EPILOGUE

# add_watch(path, kind) -> descriptor or -1
add_watch:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, -1
    mov edi, [rip + ino_fd]
    test edi, edi
    js 9f
    mov rsi, rbx
    mov edx, WMASK
    SYS SYS_inotify_add_watch
    test rax, rax
    js 9f
    cmp rax, MAXWD
    jae 9f
    mov r13, rax
    lea rcx, [rip + wd_kinds]
    or [rcx + r13], r12b
    lea rcx, [rip + wd_paths]
    cmp qword ptr [rcx + r13*8], 0
    jne 9f
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    lea rcx, [rip + wd_paths]
    mov [rcx + r13*8], rax
9:  mov rax, r13
    EPILOGUE

# watch_forget_agents(): no folder watched so far reports to the agents panel (a new project's folders
# are added again; the kernel keeps the watches of folders other kinds still use)
FN watch_forget_agents
    lea rax, [rip + wd_kinds]
    xor ecx, ecx
1:  and byte ptr [rax + rcx], 0xff - WK_AGENTS
    inc ecx
    cmp ecx, MAXWD
    jb 1b
    ret

FN watch_dir
    mov esi, WK_EXPLORER
    jmp add_watch
FN watch_agents_dir
    mov esi, WK_AGENTS
    jmp add_watch
FN watch_git
    mov esi, WK_GIT
    jmp add_watch
FN watch_worktree
    mov esi, WK_WORKTREE
    jmp add_watch

# watch_doc(doc): watch the folder of its file (DOC_wd) and, when the file is a symlink, the folder of
#   the file it leads to (DOC_real, DOC_rname, DOC_wd2). A folder that is not there is -1, and the
#   nearest folder above it is watched for it to come.
FN watch_doc
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + DOC_wd], -1
    mov qword ptr [rbx + DOC_wd2], -1
    mov rdi, [rbx + DOC_real]
    call mem_free
    mov qword ptr [rbx + DOC_real], 0
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 9f
    call watch_file_dir
    mov [rbx + DOC_wd], rax
    mov rdi, [rbx + DOC_path]
    call link_target
    test rax, rax
    jz 9f
    mov [rbx + DOC_real], rax
    mov rdi, rax
    call strlen
    mov rdi, [rbx + DOC_real]
    mov rsi, rax
    call path_basename
    mov [rbx + DOC_rname], rax
    mov rdi, [rbx + DOC_real]
    call watch_file_dir
    mov [rbx + DOC_wd2], rax
9:  EPILOGUE

# watch_file_dir(path) -> the watch of the file's folder, or -1 while it is not there, its nearest
#   folder that is then watched (WK_WAIT). That search runs again until it ends at the same watch
#   twice, so a folder made meanwhile is not missed.
watch_file_dir:
    PROLOGUE
    mov rbx, rdi
    mov r13, -1
    mov r14, -1                 # the folder waited on last
    mov r15d, 16
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jnz 1f
    cmp byte ptr [rbx], '/'
    jne 9f
    mov eax, 1                  # a file directly under the filesystem root
1:  cmp rax, 4096
    jae 9f
    mov r12, rax
0:  lea rdi, [rip + wait_path]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    mov byte ptr [rdi], 0
    lea rdi, [rip + wait_path]
    mov esi, WK_DOCS
    call add_watch
    test rax, rax
    jns 8f
    # up to the nearest folder there is
2:  lea rdi, [rip + wait_path]
    call strlen
    mov rcx, rax
    lea rdi, [rip + wait_path]
    mov rsi, rax
    push rcx
    push rcx
    call path_dirlen
    pop rcx
    pop rcx
    test rax, rax
    jnz 3f
    cmp byte ptr [rip + wait_path], '/'
    jne 9f
    mov eax, 1
3:  cmp rax, rcx
    jae 9f
    lea rdx, [rip + wait_path]
    mov byte ptr [rdx + rax], 0
    lea rdi, [rip + wait_path]
    mov esi, WK_WAIT
    call add_watch
    test rax, rax
    js 2b
    cmp rax, r14
    je 9f
    mov r14, rax
    dec r15d
    jnz 0b
    jmp 9f
8:  mov r13, rax
9:  mov rax, r13
    EPILOGUE

# link_target(path) -> a new copy of the path a symlink at path leads to, through further symlinks,
#   or 0 when path is not one; the file there need not exist
link_target:
    PROLOGUE 8192
    mov rbx, rdi
    call strlen
    cmp rax, 4096
    jae 8f
    mov rdi, rsp
    mov rsi, rbx
    call cstr_copy
    mov r12d, 40
    xor r13d, r13d              # a link was followed
1:  mov rdi, rsp
    lea rsi, [rsp + 4096]
    mov edx, 4095
    SYS SYS_readlink
    test rax, rax
    js 5f                       # not a symlink, or not there: the path reached
    cmp rax, 4095
    jae 8f
    dec r12d
    jz 8f
    mov r13d, 1
    mov byte ptr [rsp + rax + 4096], 0
    mov r14, rax
    lea rax, [rsp + 4096]
    PATH_ABSOLUTE rax, 3f
    # relative link text replaces the name, in the link's folder
    mov rdi, rsp
    call strlen
    mov rdi, rsp
    mov rsi, rax
    call path_basename
    mov rdi, rax
    sub rax, rsp
    add rax, r14
    cmp rax, 4096
    jae 8f
    jmp 4f
3:  mov rdi, rsp
4:  lea rsi, [rsp + 4096]
    call cstr_copy
    jmp 1b
5:  test r13d, r13d
    jz 8f
    mov rdi, rsp
    call strlen
    mov rdi, rsp
    mov rsi, rax
    call mem_dup
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# docs_lost(wd): open files whose folder that watch was have none now (the folder was removed, or
#   moved: the watch follows it, not the path)
docs_lost:
    PROLOGUE
    mov r14d, edi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 8f
    cmp [r12 + DOC_wd], r14
    jne 2f
    mov qword ptr [r12 + DOC_wd], -1
2:  cmp qword ptr [r12 + DOC_real], 0
    je 8f
    cmp [r12 + DOC_wd2], r14
    jne 8f
    mov qword ptr [r12 + DOC_wd2], -1
8:  inc rbx
    jmp 1b
9:  EPILOGUE

# docs_wake(): open files waiting for their folder try again; one that has it now is compared with
#   the disk, as it may have been written before its folder was watched. With none still waiting,
#   no folder reports for them.
docs_wake:
    PROLOGUE
    xor ebx, ebx
    xor r13d, r13d              # one still waits
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 7f
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 8f
    cmp qword ptr [r12 + DOC_path], 0
    je 8f
    cmp qword ptr [r12 + DOC_wd], 0
    jl 2f
    cmp qword ptr [r12 + DOC_real], 0
    je 8f
    cmp qword ptr [r12 + DOC_wd2], 0
    jge 8f
2:  mov rdi, r12
    call watch_doc
    cmp qword ptr [r12 + DOC_wd], 0
    jl 3f
    cmp qword ptr [r12 + DOC_real], 0
    je 4f
    cmp qword ptr [r12 + DOC_wd2], 0
    jge 4f
3:  mov r13d, 1
    cmp qword ptr [r12 + DOC_wd], 0
    jl 8f
4:  cmp qword ptr [r12 + DOC_reload_at], 0
    jne 8f
    call time_ms
    add rax, RELOAD_DELAY_MS
    mov [r12 + DOC_reload_at], rax
    call tick_at
8:  inc rbx
    jmp 1b
7:  test r13d, r13d
    jnz 9f
    lea rax, [rip + wd_kinds]
    xor ecx, ecx
6:  and byte ptr [rax + rcx], 0xff - WK_WAIT
    inc ecx
    cmp ecx, MAXWD
    jb 6b
9:  EPILOGUE

on_inotify:
    PROLOGUE 16
    mov dword ptr [rsp], 0      # explorer refresh wanted
    mov dword ptr [rsp + 4], 0  # agents changed
    mov dword ptr [rsp + 8], 0  # open files wait for a folder that may be there now
.Lin_read:
    mov edi, [rip + ino_fd]
    lea rsi, [rip + evbuf]
    mov edx, 16384
    SYS SYS_read
    test rax, rax
    jle .Lin_done
    mov r12, rax
    xor r13d, r13d
.Lin_ev:
    cmp r13, r12
    jae .Lin_read
    lea r14, [rip + evbuf]
    add r14, r13
    mov ebx, [r14]              # wd
    mov r15d, [r14 + 4]         # mask
    mov eax, [r14 + 12]         # name len
    lea r13, [r13 + rax + 16]
    cmp ebx, MAXWD
    jae .Lin_ev
    lea rcx, [rip + wd_kinds]
    movzx ecx, byte ptr [rcx + rbx]
    # a folder an open file needs was removed or moved away (its watch goes with it), or one above
    # a missing folder changed
    test ecx, WK_DOCS | WK_WAIT
    jz 6f
    test r15d, IN_IGNORED | IN_MOVE_SELF
    jz 61f
    push rcx
    push rcx
    mov edi, ebx
    call docs_lost
    pop rcx
    pop rcx
    mov dword ptr [rsp + 8], 1
61: test ecx, WK_WAIT
    jz 6f
    mov dword ptr [rsp + 8], 1
6:
    # the work tree changed: git status again
    test ecx, WK_EXPLORER | WK_DOCS | WK_WORKTREE
    jz 62f
    push rcx
    push rcx
    call git_touch
    pop rcx
    pop rcx
62: test ecx, WK_GIT
    jz 7f
    push rcx
    push rcx
    lea rax, [rip + wd_paths]
    mov rdi, [rax + rbx*8]
    lea rsi, [r14 + 16]
    call git_fs_event
    pop rcx
    pop rcx
7:  test ecx, WK_EXPLORER
    jz 1f
    test r15d, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO
    jz 1f
    mov dword ptr [rsp], 1
1:  test ecx, WK_AGENTS
    jz 2f
    push rcx
    push rcx
    mov edi, ebx
    lea rsi, [r14 + 16]
    mov edx, r15d
    call agents_event           # only what can change the sessions listed
    pop rcx
    pop rcx
    test eax, eax
    jz 2f
    mov dword ptr [rsp + 4], 1
2:  test ecx, WK_DOCS
    jz 3f
    test r15d, IN_CLOSE_WRITE | IN_MOVED_TO
    jz 3f
    push rcx
    push rcx
    mov edi, ebx
    lea rsi, [r14 + 16]
    call doc_changed
    pop rcx
    pop rcx
3:  test ecx, WK_CONFIG
    jz 31f
    test r15d, IN_CLOSE_WRITE | IN_MOVED_TO
    jz 31f
    push rcx
    push rcx
    lea rdi, [r14 + 16]
    lea rsi, [rip + .Lconfig]
    call strcmp_eq
    test eax, eax
    jz 30f
    call config_changed         # not for a write rhun has already read, or made itself
    test eax, eax
    jz 30f
    call app_reload_config
30: pop rcx
    pop rcx
31: test ecx, WK_OMARCHY
    jz .Lin_ev
    test r15d, IN_CLOSE_WRITE | IN_MOVED_TO
    jz .Lin_ev
    lea rdi, [r14 + 16]
    lea rsi, [rip + .Ltheme_name]
    call strcmp_eq
    test eax, eax
    jz .Lin_ev
    call omarchy_changed
    jmp .Lin_ev
.Lin_done:
    cmp dword ptr [rsp + 8], 0
    je 3f
    call docs_wake
3:  cmp dword ptr [rsp], 0
    je 4f
    call explorer_refresh
4:  cmp dword ptr [rsp + 4], 0
    je 5f
    call agents_on_change
5:  EPILOGUE

# doc_changed(wd, name): queue an open file, named in its folder or, for a symlink, in the folder of
#   the file it leads to; agents often replace it several times in one burst
doc_changed:
    PROLOGUE
    mov r14d, edi
    mov r15, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 8f
    cmp qword ptr [r12 + DOC_path], 0
    je 8f
    cmp [r12 + DOC_wd], r14
    jne 2f
    mov rdi, [r12 + DOC_name]
    mov rsi, r15
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 3f
2:  cmp qword ptr [r12 + DOC_real], 0
    je 8f
    cmp [r12 + DOC_wd2], r14
    jne 8f
    mov rdi, [r12 + DOC_rname]
    mov rsi, r15
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jz 8f
3:  cmp qword ptr [r12 + DOC_reload_at], 0
    jne 8f                     # one reload per 100 ms, even during a continuous stream of writes
    call time_ms
    add rax, RELOAD_DELAY_MS
    mov [r12 + DOC_reload_at], rax
    call tick_at
8:  inc rbx
    jmp 1b
9:  EPILOGUE

# tick_at(time): keep only the earliest deadline
tick_at:
    mov rcx, [rip + next_tick]
    test rcx, rcx
    jz 1f
    cmp rax, rcx
    jae 2f
1:  mov [rip + next_tick], rax
2:  ret

# watch_apply_settings(): disabling the fade clears it from every tab and keeps reload timers
FN watch_apply_settings
    cmp dword ptr [rip + cfg_animate_disk_changes], 0
    jne 9f
    PROLOGUE
    mov qword ptr [rip + next_tick], 0
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    mov rdi, rbx
    call tab_at
    mov rdx, [rax + TAB_doc]
    test rdx, rdx
    jz 2f
    mov qword ptr [rdx + DOC_disk_until], 0
    mov rax, [rdx + DOC_reload_at]
    test rax, rax
    jz 2f
    call tick_at
2:  inc rbx
    jmp 1b
8:  EPILOGUE
9:  ret

# watch_show(): resume a still-visible fade when returning to its tab
FN watch_show
    mov rax, [rip + g_doc]
    test rax, rax
    jz 1f
    cmp qword ptr [rax + DOC_disk_until], 0
    je 1f
    sub rsp, 8
    call time_ms
    call tick_at
    add rsp, 8
1:  ret

# watch_timeout() -> ms until a pending reload or the editor fade needs a frame, -1 when idle
FN watch_timeout
    mov rax, [rip + next_tick]
    test rax, rax
    jz 1f
    push rax
    call time_ms
    pop rcx
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg rax, rcx
    ret
1:  mov eax, -1
    ret

# watch_tick(): only scan tabs while reloads or fades are pending, never poll files while idle
FN watch_tick
    PROLOGUE
    cmp qword ptr [rip + next_tick], 0
    je 9f
    call time_ms
    mov r13, rax
    cmp rax, [rip + next_tick]
    jb 9f
    mov qword ptr [rip + next_tick], 0
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    call tab_at
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 8f
    mov rax, [r12 + DOC_reload_at]
    test rax, rax
    jz 3f
    cmp rax, r13
    ja 2f
    mov qword ptr [r12 + DOC_reload_at], 0
    mov rdi, r12
    call reload_changed
    jmp 3f
2:  call tick_at
3:  mov rax, [r12 + DOC_disk_until]
    test rax, rax
    jz 8f
    cmp r12, [rip + g_doc]
    jne 8f                     # background reloads do not animate an unrelated editor
    mov dword ptr [rip + g_dirty], 1
    cmp rax, r13
    ja 4f
    mov qword ptr [r12 + DOC_disk_until], 0
    jmp 8f
4:  lea rcx, [r13 + DISK_FRAME_MS]
    cmp rax, rcx
    cmova rax, rcx
    call tick_at
8:  inc rbx
    jmp 1b
9:  EPILOGUE

# reload_changed(doc): compare the stamp after the burst, checking dirty state at reload time; a
#   symlink may lead elsewhere now
reload_changed:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 9f
    # a symlink, or a file that is one now: what it leads to, and that folder's watch, again
    cmp qword ptr [rbx + DOC_real], 0
    jne 1f
    sub rsp, 16
    mov rsi, rsp
    mov edx, 1
    SYS SYS_readlink
    add rsp, 16
    test rax, rax
    js 2f
1:  mov rdi, rbx
    call watch_doc
2:  mov rdi, [rbx + DOC_path]
    call file_stamp
    test rax, rax
    jz 9f                      # a removed file keeps its current contents
    cmp rax, [rbx + DOC_mtime]
    je 9f                      # includes our own saves
    cmp rax, [rbx + DOC_disk_seen]
    je 9f
    mov rdi, rbx
    call doc_dirty
    test eax, eax
    jnz 7f                     # the stamp stays unseen: a later clean state still loads it
    mov rdi, rbx
    call app_reload_doc
    test eax, eax
    jz 9f
    cmp rbx, [rip + g_doc]
    jne 9f
    cmp dword ptr [rip + cfg_animate_disk_changes], 0
    je 9f
    call time_ms
    add rax, DISK_FADE_MS
    mov [rbx + DOC_disk_until], rax
    jmp 9f
7:  or dword ptr [rbx + DOC_flags], DF_DISK_CHANGED
    mov qword ptr [rbx + DOC_disk_until], 0
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# watch_doc_clean(doc): undo or redo back to the saved state loads a version kept out by local edits
FN watch_doc_clean
    test dword ptr [rdi + DOC_flags], DF_DISK_CHANGED
    jz 9f
    cmp qword ptr [rdi + DOC_reload_at], 0
    jne 9f
    push rbx
    mov rbx, rdi
    call doc_dirty
    test eax, eax
    jnz 8f
    call time_ms
    add rax, RELOAD_DELAY_MS
    mov [rbx + DOC_reload_at], rax
    call tick_at
8:  pop rbx
9:  ret

# disk_range(doc, new text, length) -> changed in eax, prefix in rdx, old end in rcx, new end in r8.
# Find a common prefix and suffix directly in the gap buffer, with no second file-sized allocation
# or full diff.
disk_range:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_len
    mov r14, rax               # old end
    mov r15, r13               # new end
    mov r8, [rbx + DOC_buf]
    mov r9, [rbx + DOC_gs]
    mov r10, [rbx + DOC_ge]
    sub r10, r9                # gap size
    xor ecx, ecx               # common prefix
1:  cmp rcx, r14
    jae 3f
    cmp rcx, r13
    jae 3f
    mov rdx, rcx
    cmp rdx, r9
    jb 2f
    add rdx, r10
2:  mov al, [r8 + rdx]
    cmp al, [r12 + rcx]
    jne 3f
    inc rcx
    jmp 1b
3:  cmp rcx, r14
    jne 4f
    cmp rcx, r13
    jne 4f
    mov qword ptr [rbx + DOC_disk_lo], 0
    mov qword ptr [rbx + DOC_disk_hi], 0
    xor eax, eax
    EPILOGUE
4:  cmp r14, rcx
    jbe 6f
    cmp r15, rcx
    jbe 6f
    lea rdx, [r14 - 1]
    cmp rdx, r9
    jb 5f
    add rdx, r10
5:  mov al, [r8 + rdx]
    cmp al, [r12 + r15 - 1]
    jne 6f
    dec r14
    dec r15
    jmp 4b
6:  mov [rsp], rcx
    mov [rsp + 8], r14
    mov [rsp + 16], r15
    xor eax, eax               # line of the first changed byte
    xor edx, edx
7:  cmp rdx, rcx
    jae 8f
    cmp byte ptr [r12 + rdx], 10
    jne 71f
    inc rax
71: inc rdx
    jmp 7b
8:  mov [rbx + DOC_disk_lo], rax
    cmp r15, rcx
    jbe 10f                    # a deletion: pulse the surviving line at that position
    dec r15                    # exclude an unchanged line after a replaced newline
9:  cmp rdx, r15
    jae 10f
    cmp byte ptr [r12 + rdx], 10
    jne 91f
    inc rax
91: inc rdx
    jmp 9b
10: inc rax
    mov [rbx + DOC_disk_hi], rax
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    mov eax, 1
    EPILOGUE

# app_reload_doc(doc) -> 1 if text changed, 0 if identical, unreadable or an image; keep cursor and scroll
FN app_reload_doc
    PROLOGUE 32
    mov rbx, rdi
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 9f
    cmp qword ptr [rbx + DOC_img], 0
    jne .Lrd_image
    call file_stamp
    mov [rsp + 24], rax        # stamp belongs to the bytes read, not a later replacement
    mov rdi, [rbx + DOC_path]
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    mov r13, rdx
    mov rdi, [rbx + DOC_path]
    call file_stamp
    cmp rax, [rsp + 24]
    jne .Lrd_unstable          # a concurrent writer replaced or changed it while we read
    mov rdi, r12
    mov rsi, r13
    call doc_is_binary
    test eax, eax
    jnz .Lrd_binary
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_normalize_eol
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call disk_range
    test eax, eax
    jz .Lrd_same
    mov [rsp], rdx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    mov r14, [rbx + DOC_cur]
    mov r15, [rbx + DOC_scrolly]
    mov rdi, rbx
    call doc_begin_group
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    sub rdx, rsi
    xor ecx, ecx
    call doc_delete
    mov rdi, rbx
    mov rsi, [rsp]
    lea rdx, [r12 + rsi]
    mov rcx, [rsp + 16]
    sub rcx, rsi
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_end_group
    mov rdi, rbx
    call doc_len
    cmp r14, rax
    cmova r14, rax
    mov [rbx + DOC_cur], r14
    mov [rbx + DOC_anchor], r14
    mov [rbx + DOC_scrolly], r15
    mov dword ptr [rsp], 1
    jmp .Lrd_done
.Lrd_same:
    mov dword ptr [rsp], 0
.Lrd_done:
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call doc_note_eol
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rbx + DOC_savepoint], rax
    mov rax, [rsp + 24]
    mov [rbx + DOC_mtime], rax
    mov [rbx + DOC_disk_seen], rax
    and dword ptr [rbx + DOC_flags], ~DF_DISK_CHANGED
    mov qword ptr [rbx + DOC_disk_until], 0
    mov dword ptr [rip + g_dirty], 1
    mov eax, [rsp]
    EPILOGUE
9:  xor eax, eax
    EPILOGUE
.Lrd_unstable:
    mov rdi, r12
    call mem_free
    mov qword ptr [rbx + DOC_disk_seen], 0
    call time_ms
    add rax, RELOAD_DELAY_MS
    mov [rbx + DOC_reload_at], rax
    call tick_at
    xor eax, eax
    EPILOGUE
.Lrd_binary:
    mov rdi, r12
    call mem_free
    xor eax, eax
    EPILOGUE
.Lrd_image:
    call file_stamp
    mov [rbx + DOC_mtime], rax
    mov [rbx + DOC_disk_seen], rax
    and dword ptr [rbx + DOC_flags], ~DF_DISK_CHANGED
    mov rdi, [rbx + DOC_img]
    call iv_reload
    mov dword ptr [rip + g_dirty], 1
    xor eax, eax               # the editor fade has nothing to show for an image
    EPILOGUE

FN cmd_reload_file
    mov rdi, [rip + g_file]
    test rdi, rdi
    jz 1f
    jmp app_reload_doc
1:  ret

.section .rodata
.Lconfig: .asciz "config"
.Ltheme_name: .asciz "theme.name"
