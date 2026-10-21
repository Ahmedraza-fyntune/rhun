# gitrepos: the repositories of the workspace's folders (resources group, multi-root). Each folder's
#   repository has a slot with its branch and its status, so the explorer colours every folder's
#   changes (git_status_of asks here for paths outside the repository git.s shows) and Source Control
#   lists the repositories in a row of their own. git.s shows the active document's folder's
#   repository, or the one picked in that row until the active document changes.
.include "rhun.inc"

.equ GR_MAX, 16                 # workspace folders (workspace.s WS_MAX)
.equ GR_EVERY, 10000            # ms between statuses of a repository git.s does not show
.equ GR_TOUCH, 1000             # after files changed
.equ GT_SIZE, SB_SIZE+32        # a status table (git_table_swap)
.equ ID_GR, 0x6a0000            # + slot: a repository's line in Source Control

STRUCT
F GR_root, 8                    # work tree, owned
F GR_rootlen, 8
F GR_gitdir, 8                  # owned
F GR_name, 8                    # the first folder's name in it, owned (0: the work tree's)
F GR_at, 8                      # when its next status is due (ms), 0 not planned
F GR_running, 4                 # a status runs
F GR_changes, 4
F GR_loaded, 4                  # its table holds a status
F GR_paused, 4                  # a rhun:// link opened the project and this repository is not trusted
F GR_due, 4                     # new, or files changed: a status soon (git_busy waits for it)
F GR_shown, 4                   # git.s showed it at the last tick
F GR_table, GT_SIZE
F GR_branch, 64
ENDSTRUCT GR_SIZE

.bss
.p2align 3
gr_slots: .zero GR_SIZE*GR_MAX
gr_doc: .quad 0                 # the active document followed last
gr_count: .long 0
gr_gen: .long 0                 # answers for older slots are dropped
gr_built: .long 0
gr_wsgen: .long 0               # g_ws_gen of the slots
gr_cfg: .long 0                 # cfg_git of the slots
gr_of: .zero 4*GR_MAX           # folder index -> slot, -1 none
gr_req: .long 0                 # a line clicked, + 1: shown at the next tick
gr_num: .zero 32

.text

# gr_at(i) -> rax the slot
gr_at:
    mov eax, edi
    imul rax, rax, GR_SIZE
    lea rcx, [rip + gr_slots]
    add rax, rcx
    ret

# gr_shown(slot) -> eax 1 when git.s shows its repository
gr_shown:
    push rbx
    mov rsi, [rip + g_git_root]
    xor eax, eax
    test rsi, rsi
    jz 1f
    mov rdi, [rdi + GR_root]
    call strcmp_eq
1:  pop rbx
    ret

# gr_find_root(path) -> eax the slot whose work tree it is, or -1
gr_find_root:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 8f
    mov edi, ebx
    call gr_at
    mov rdi, [rax + GR_root]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 9f
    inc ebx
    jmp 1b
8:  mov ebx, -1
9:  mov eax, ebx
    EPILOGUE

# gr_clear(): every slot goes
gr_clear:
    PROLOGUE
    inc dword ptr [rip + gr_gen]
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    mov r12, rax
    lea rdi, [r12 + GR_table]
    call git_table_swap
    call git_table_free
    lea rdi, [r12 + GR_table]
    call git_table_swap
    mov rdi, [r12 + GR_root]
    call mem_free
    mov rdi, [r12 + GR_gitdir]
    call mem_free
    mov rdi, [r12 + GR_name]
    call mem_free
    mov rdi, r12
    xor eax, eax
    mov ecx, GR_SIZE
    rep stosb
    inc ebx
    jmp 1b
9:  mov dword ptr [rip + gr_count], 0
    EPILOGUE

# gr_rebuild(): a slot for each folder's repository (one for folders that share one)
gr_rebuild:
    PROLOGUE
    call gr_clear
    mov eax, [rip + g_ws_gen]
    mov [rip + gr_wsgen], eax
    mov eax, [rip + cfg_git]
    mov [rip + gr_cfg], eax
    mov dword ptr [rip + gr_built], 1
    mov qword ptr [rip + gr_doc], 0     # the active document is followed again
    lea rdi, [rip + gr_of]
    mov eax, -1
    mov ecx, GR_MAX
    rep stosd
    cmp dword ptr [rip + cfg_git], 0
    je 9f
    xor r12d, r12d              # folder
1:  call wfold_count
    cmp r12, rax
    jae 8f
    cmp r12, GR_MAX
    jae 8f
    mov rdi, r12
    call wfold_path
    test rax, rax
    jz 7f
    mov rdi, rax
    call git_find_repo
    test rax, rax
    jz 7f
    mov r13, rax                # git directory
    mov r14, rdx                # work tree
    mov r15, rcx
    mov rdi, r14
    call gr_find_root
    cmp eax, -1
    je 3f
    lea rcx, [rip + gr_of]
    mov [rcx + r12*4], eax
    mov rdi, r13
    call mem_free
    mov rdi, r14
    call mem_free
    jmp 7f
3:  mov ebx, [rip + gr_count]
    lea rcx, [rip + gr_of]
    mov [rcx + r12*4], ebx
    inc dword ptr [rip + gr_count]
    mov edi, ebx
    call gr_at
    mov rbx, rax
    mov [rbx + GR_root], r14
    mov [rbx + GR_rootlen], r15
    mov [rbx + GR_gitdir], r13
    mov rdi, r12
    call wfold_name
    test rax, rax
    jz 4f
    mov rdi, rax
    call dup_cstr
    mov [rbx + GR_name], rax
4:  mov dword ptr [rbx + GR_due], 1
    mov qword ptr [rbx + GR_at], 1   # due now
    # a link opened the project: a repository the user has not trusted runs no git
    cmp dword ptr [rip + g_project_link], 0
    je 5f
    mov rdi, r14
    call session_trusted
    test eax, eax
    jnz 5f
    mov dword ptr [rbx + GR_paused], 1
    mov dword ptr [rbx + GR_due], 0
    mov qword ptr [rbx + GR_at], 0
5:  mov rdi, r13
    lea rsi, [rbx + GR_branch]
    call git_head_name
7:  inc r12
    jmp 1b
8:  # the repository git.s shows went with its folder: the project's again
    mov rdi, [rip + g_git_root]
    test rdi, rdi
    jz 9f
    call gr_find_root
    cmp eax, -1
    jne 9f
    call git_set_project
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# gr_show(i): git.s shows slot i's repository
gr_show:
    PROLOGUE
    call gr_at
    mov rbx, rax
    mov rdi, rax
    call gr_shown
    test eax, eax
    jnz 9f
    mov rdi, [rbx + GR_root]
    call git_set_root
9:  EPILOGUE

# FN gitrepos_pick(i): Source Control's repository line i was clicked: git.s shows that repository
#   until the active document changes
FN gitrepos_pick
    PROLOGUE
    cmp edi, [rip + gr_count]
    jae 9f
    call gr_show
    mov rax, [rip + g_doc]
    mov [rip + gr_doc], rax
9:  EPILOGUE

# gr_follow(): a new active document in another folder's repository: git.s shows that one (a folder
#   without a repository keeps the one shown; a project a rhun:// link opened keeps its own)
gr_follow:
    PROLOGUE
    cmp dword ptr [rip + gr_count], 0
    je 9f
    cmp dword ptr [rip + g_project_link], 0
    jne 9f
    call wfold_count
    cmp rax, 2
    jb 9f
    mov rbx, [rip + g_doc]
    cmp rbx, [rip + gr_doc]
    je 9f
    mov [rip + gr_doc], rbx
    test rbx, rbx
    jz 9f
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 9f
    call wfold_of
    test rax, rax
    js 9f
    cmp rax, GR_MAX
    jae 9f
    lea rcx, [rip + gr_of]
    mov eax, [rcx + rax*4]
    cmp eax, -1
    je 9f
    mov edi, eax
    call gr_show
9:  EPILOGUE

# gr_start(i): slot i's status in the background; its branch again
gr_start:
    PROLOGUE
    mov ebx, edi
    call gr_at
    mov r12, rax
    mov qword ptr [r12 + GR_at], 0
    mov dword ptr [r12 + GR_due], 0
    mov rdi, [r12 + GR_gitdir]
    lea rsi, [r12 + GR_branch]
    call git_head_name
    mov edi, 8
    call mem_alloc
    mov ecx, [rip + gr_gen]
    mov [rax], ecx
    mov [rax + 4], ebx
    mov rdi, [r12 + GR_root]
    lea rsi, [rip + gr_args]
    lea rdx, [rip + gr_on_status]
    mov rcx, rax
    xor r8d, r8d
    call git_start_in
    xor ecx, ecx
    test rax, rax
    setnz cl
    mov [r12 + GR_running], ecx
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# gr_on_status(ctx, ptr, len, status): a slot's status --porcelain -z records
gr_on_status:
    PROLOGUE
    mov eax, [rdi]
    cmp eax, [rip + gr_gen]
    jne 9f
    mov ebx, [rdi + 4]
    mov r13, rsi
    mov r14, rdx
    mov r15d, ecx
    mov edi, ebx
    call gr_at
    mov r12, rax
    mov dword ptr [r12 + GR_running], 0
    test r15d, r15d
    jnz 2f
    lea rdi, [r12 + GR_table]
    call git_table_swap
    mov rdi, r13
    mov rsi, r14
    call git_table_load
    mov [r12 + GR_changes], eax
    lea rdi, [r12 + GR_table]
    call git_table_swap
    mov dword ptr [r12 + GR_loaded], 1
2:  cmp dword ptr [r12 + GR_due], 0     # files changed while it ran: their status is planned
    jne 3f
    call time_ms
    add rax, GR_EVERY
    mov [r12 + GR_at], rax
3:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# FN gitrepos_tick(): new folders, the active document's repository, statuses due
FN gitrepos_tick
    PROLOGUE
    cmp dword ptr [rip + gr_built], 0
    je 1f
    mov eax, [rip + g_ws_gen]
    cmp eax, [rip + gr_wsgen]
    jne 1f
    mov eax, [rip + cfg_git]
    cmp eax, [rip + gr_cfg]
    je 2f
1:  call gr_rebuild
2:  mov edi, [rip + gr_req]
    test edi, edi
    jz 21f
    mov dword ptr [rip + gr_req], 0
    dec edi
    call gitrepos_pick
21: call gr_follow
    call time_ms
    mov r13, rax
    xor ebx, ebx
3:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    mov r12, rax
    cmp dword ptr [r12 + GR_paused], 0
    jne 7f
    mov rdi, r12
    call gr_shown
    test eax, eax
    jz 4f
    # git.s keeps this one's status
    mov dword ptr [r12 + GR_shown], 1
    mov dword ptr [r12 + GR_due], 0
    mov qword ptr [r12 + GR_at], 0
    jmp 7f
4:  cmp dword ptr [r12 + GR_shown], 0  # no longer shown: its own table is old
    je 5f
    mov dword ptr [r12 + GR_shown], 0
    mov dword ptr [r12 + GR_due], 1
    mov [r12 + GR_at], r13
5:  cmp dword ptr [r12 + GR_running], 0
    jne 7f
    mov rax, [r12 + GR_at]
    test rax, rax
    jnz 6f
    lea rax, [r13 + GR_EVERY]
    mov [r12 + GR_at], rax
    jmp 7f
6:  cmp r13, rax
    jb 7f
    mov edi, ebx
    call gr_start
7:  inc ebx
    jmp 3b
9:  EPILOGUE

# FN gitrepos_touch(): files changed (git_touch): the other repositories' statuses soon
FN gitrepos_touch
    PROLOGUE
    cmp dword ptr [rip + gr_count], 0
    je 9f
    call time_ms
    lea r13, [rax + GR_TOUCH]
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    cmp dword ptr [rax + GR_paused], 0
    jne 3f
    mov dword ptr [rax + GR_due], 1
    mov rcx, [rax + GR_at]
    test rcx, rcx
    jz 2f
    cmp rcx, r13
    jbe 3f
2:  mov [rax + GR_at], r13
3:  inc ebx
    jmp 1b
9:  EPILOGUE

# FN gitrepos_busy() -> eax 1 while slots are to be made or a status is due (git_busy, wait-git)
FN gitrepos_busy
    PROLOGUE
    xor r12d, r12d
    cmp dword ptr [rip + cfg_git], 0
    je 9f
    mov r12d, 1
    cmp dword ptr [rip + gr_built], 0
    je 9f
    mov eax, [rip + g_ws_gen]
    cmp eax, [rip + gr_wsgen]
    jne 9f
    xor r12d, r12d
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    mov r13, rax
    cmp dword ptr [r13 + GR_running], 0
    jne 8f
    cmp dword ptr [r13 + GR_due], 0
    je 2f
    cmp dword ptr [r13 + GR_paused], 0
    jne 2f
    mov rdi, r13
    call gr_shown
    test eax, eax
    jz 8f
2:  inc ebx
    jmp 1b
8:  mov r12d, 1
9:  mov eax, r12d
    EPILOGUE

# FN gitrepos_timeout() -> eax ms until a status is due, or -1
FN gitrepos_timeout
    PROLOGUE
    mov r12d, -1
    call time_ms
    mov r13, rax
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    cmp dword ptr [rax + GR_running], 0
    jne 3f
    cmp dword ptr [rax + GR_paused], 0
    jne 3f
    mov rcx, [rax + GR_at]
    test rcx, rcx
    jz 3f
    sub rcx, r13
    jns 2f
    xor ecx, ecx
2:  cmp r12d, -1
    je 21f
    cmp ecx, r12d
    jae 3f
21: mov r12d, ecx
3:  inc ebx
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# FN gitrepos_status_of(path cstr) -> eax code letter or 0, edx 1 or 2 for folders: git_status_of for
#   a path in another workspace folder's repository (the innermost one holding it)
FN gitrepos_status_of
    PROLOGUE 16
    mov r12, rdi
    mov qword ptr [rsp], 0
    cmp dword ptr [rip + gr_count], 0
    je 9f
    call strlen
    mov r13, rax
    mov r14d, -1                # the slot
    xor r15d, r15d              # its work tree's length
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 5f
    mov edi, ebx
    call gr_at
    cmp dword ptr [rax + GR_loaded], 0
    je 4f
    mov rcx, [rax + GR_rootlen]
    cmp rcx, r15
    jbe 4f
    lea rdx, [rcx + 1]
    cmp r13, rdx
    jbe 4f
    cmp byte ptr [r12 + rcx], '/'
    jne 4f
    mov [rsp + 8], rcx
    mov rdi, r12
    mov rsi, [rax + GR_root]
    mov rdx, rcx
    call memeq
    test eax, eax
    jz 4f
    mov r14d, ebx
    mov r15, [rsp + 8]
4:  inc ebx
    jmp 1b
5:  cmp r14d, -1
    je 9f
    mov edi, r14d
    call gr_at
    mov rbx, rax
    lea rdi, [rbx + GR_table]
    call git_table_swap
    lea rdi, [r12 + r15 + 1]
    mov rsi, r13
    sub rsi, r15
    dec rsi
    call git_table_status
    mov [rsp], eax
    mov [rsp + 4], edx
    lea rdi, [rbx + GR_table]
    call git_table_swap
9:  mov eax, [rsp]
    mov edx, [rsp + 4]
    EPILOGUE

# FN gitrepos_draw_row(x, y, w) -> eax the height it took: Source Control's repositories, a line
#   each when the workspace's folders have two or more; the one shown has the accent colour, a click
#   shows another (scm.s, above the branch)
FN gitrepos_draw_row
    PROLOGUE 32
    xor eax, eax
    cmp dword ptr [rip + gr_count], 2
    jb 99f
    mov [rsp], edi              # x
    mov [rsp + 4], edx          # w
    mov [rsp + 24], esi         # y
    mov r13d, esi               # the line's y
    M r15d, MI_28
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 8f
    mov edi, ebx
    call gr_at
    mov r12, rax
    lea edi, [rbx + ID_GR]
    mov esi, [rsp]
    mov edx, r13d
    mov ecx, [rsp + 4]
    mov r8d, r15d
    call ui_btn
    mov r14d, eax
    test eax, UB_HOVER
    jz 2f
    M eax, MI_6
    mov edi, [rsp]
    add edi, eax
    mov esi, r13d
    mov edx, [rsp + 4]
    sub edx, eax
    sub edx, eax
    mov ecx, r15d
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
2:  test r14d, UB_CLICK          # at the next tick: git_set_root resets Source Control's lists
    jz 3f
    lea eax, [rbx + 1]
    mov [rip + gr_req], eax
    mov dword ptr [rip + g_dirty], 1
3:  mov rdi, r12
    call gr_shown
    mov [rsp + 8], eax
    COLOR r9d, T_MUTED
    test eax, eax
    jz 4f
    COLOR r9d, T_ACCENT
4:  mov edi, IC_FOLDER
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, r13d
    M ecx, MI_ICON
    mov r8d, r15d
    call ui_icon_center
    # its name, then its branch
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_16]
    add esi, [rip + g_mt + 4*MI_ICON]
    add esi, [rip + g_mt + 4*MI_8]
    mov r8, [r12 + GR_name]
    test r8, r8
    jnz 5f
    mov r8, [r12 + GR_root]
5:  lea rdi, [rip + g_face_ui]
    mov edx, r13d
    mov ecx, r15d
    COLOR r9d, T_FG
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 12], eax         # the branch's x
    # the changes on the right: git.s's own count for the repository it shows
    mov esi, [r12 + GR_changes]
    cmp dword ptr [rsp + 8], 0
    je 51f
    mov esi, [rip + g_git_changes]
51: mov dword ptr [rsp + 16], 0  # the count's width
    test esi, esi
    jz 6f
    lea rdi, [rip + gr_num]
    call fmt_u64
    mov [rsp + 20], eax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + gr_num]
    mov edx, [rsp + 20]
    call text_width
    mov [rsp + 16], eax
    mov esi, [rsp]
    add esi, [rsp + 4]
    sub esi, [rip + g_mt + 4*MI_16]
    sub esi, eax
    COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov edx, r13d
    mov ecx, r15d
    lea r8, [rip + gr_num]
    mov r9d, [rsp + 36]
    call ui_text_v
    add rsp, 16
6:  # the branch, cut to the room left
    lea rdi, [r12 + GR_branch]
    call strlen
    mov [rsp + 20], eax
    mov eax, [rsp]
    add eax, [rsp + 4]
    sub eax, [rip + g_mt + 4*MI_16]
    sub eax, [rsp + 16]
    sub eax, [rip + g_mt + 4*MI_8]
    sub eax, [rsp + 12]
    jle 7f
    push rax
    COLOR ecx, T_MUTED
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 28]
    mov edx, r13d
    mov ecx, r15d
    lea r8, [r12 + GR_branch]
    mov r9d, [rsp + 36]
    call ui_text_v_fit
    add rsp, 16
7:  add r13d, r15d
    inc ebx
    jmp 1b
8:  add r13d, [rip + g_mt + 4*MI_8]
    mov eax, r13d
    sub eax, [rsp + 24]
99: EPILOGUE

# FN c_print_repos(out, args, len): print-repos: "repo=NAME root=R branch=B changes=N shown=0|1
#   paused=0|1" a line
FN c_print_repos
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp ebx, [rip + gr_count]
    jae 9f
    mov edi, ebx
    call gr_at
    mov r13, rax
    mov rdi, r12
    lea rsi, [rip + .Lp_repo]
    call sb_push_cstr
    mov rsi, [r13 + GR_name]
    test rsi, rsi
    jnz 2f
    lea rsi, [rip + .Lp_none]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_root]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r13 + GR_root]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_branch]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [r13 + GR_branch]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_changes]
    call sb_push_cstr
    mov rdi, r13
    call gr_shown
    mov r14d, eax
    mov esi, [r13 + GR_changes]
    test r14d, r14d
    jz 3f
    mov esi, [rip + g_git_changes]
3:  mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Lp_shown]
    call sb_push_cstr
    mov rdi, r12
    mov esi, r14d
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Lp_paused]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r13 + GR_paused]
    call sb_push_u64
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc ebx
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# FN c_repo_show(out, args, len): repo-show N: Source Control's repository line N clicked
FN c_repo_show
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call parse_u64
    mov rdi, rax
    call gitrepos_pick
    xor eax, eax
    EPILOGUE

.section .rodata
gr_args: .quad .Lstatus, .Lporcelain, .Ldash_z, 0
.Lstatus: .asciz "status"
.Lporcelain: .asciz "--porcelain"
.Ldash_z: .asciz "-z"
.Lp_repo: .asciz "repo="
.Lp_none: .asciz "-"
.Lp_root: .asciz " root="
.Lp_branch: .asciz " branch="
.Lp_changes: .asciz " changes="
.Lp_shown: .asciz " shown="
.Lp_paused: .asciz " paused="
