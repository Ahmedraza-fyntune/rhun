# which extensions may run programs as the user, per project (DECISIONS.md, decision 1). The first
# time an extension runs a program outside its sandbox in a project (a task, a terminal, a debug
# adapter, a test run), rhun shows the exact command and asks once, Allow or Cancel; Allow covers
# that extension's later programs in that project. Approvals are kept in extensions.ini as
# `allow_run = PROJECT` lines (`-` without a project) under [OWNER/NAME], a file the extension cannot
# write; at most 64 projects per extension, the oldest dropped. Forget on its page drops them.
#
#   run_approve(ext, command cstr, done, cookie) -> 1 allowed already (done is not called);
#       0 asked: done(cookie, allowed 1|0) comes with the answer; -1 busy: another dialog is open
#   run_approve_cancel(cookie)    the open question for cookie goes away unanswered (cancel ID, its
#                                 extension stopped); done is not called
#   run_approved(ext) -> 1 when it may run programs in the current project
#   run_forget(ext)               Forget: its approvals go
.include "rhun.inc"

.equ RA_PER_EXT, 64
.equ CMD_SHOWN, 96              # bytes of the command the dialog shows; a longer one loses its middle

STRUCT
F RA_name, 8                    # owned "owner/name"
F RA_project, 8                 # owned folder, or "-"
ENDSTRUCT RA_SIZE

.bss
.p2align 3
allows: .zero VEC_SIZE          # RA, oldest first
ask_open: .long 0               # the question on screen
.p2align 3
ask_done: .quad 0
ask_cookie: .quad 0
ask_name: .quad 0               # owned: whose and where
ask_project: .quad 0
q_buf: .zero 1024               # the dialog's question and line
l_buf: .zero 8192
name_buf: .zero 512

.text

# project_key() -> the current project's folder, or "-"
project_key:
    mov rax, [rip + g_project]
    test rax, rax
    jnz 1f
    lea rax, [rip + .Ldash]
1:  ret

# full_name(ext) -> its "owner/name" in name_buf
full_name:
    sub rsp, 8
    call ext_full_name
    lea rdi, [rip + name_buf]
    mov rsi, rax
    call cstr_copy
    lea rax, [rip + name_buf]
    add rsp, 8
    ret

# find(name, project) -> RA* or 0
find:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + allows + VEC_len]
    jae 8f
    imul r14, rbx, RA_SIZE
    add r14, [rip + allows + VEC_ptr]
    inc rbx
    mov rdi, [r14 + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [r14 + RA_project]
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# add(name, project): owned strings into the list, unless it has them; an extension's 65th project
#   pushes out its oldest
add:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call find
    test rax, rax
    jnz 7f
    # how many it has, and its oldest
    xor ebx, ebx
    xor r14d, r14d              # count
    mov r15, -1                 # oldest index
1:  cmp rbx, [rip + allows + VEC_len]
    jae 3f
    imul rax, rbx, RA_SIZE
    add rax, [rip + allows + VEC_ptr]
    mov rdi, [rax + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 2f
    inc r14d
    cmp r15, -1
    jne 2f
    mov r15, rbx
2:  inc rbx
    jmp 1b
3:  cmp r14d, RA_PER_EXT
    jb 4f
    mov rdi, r15
    call remove_at
4:  lea rdi, [rip + allows]
    mov esi, RA_SIZE
    call vec_push
    mov [rax + RA_name], r12
    mov [rax + RA_project], r13
    EPILOGUE
7:  mov rdi, r12
    call mem_free
    mov rdi, r13
    call mem_free
    EPILOGUE

# remove_at(index): the entry goes, the later ones move up
remove_at:
    PROLOGUE
    mov rbx, rdi
    imul r12, rbx, RA_SIZE
    add r12, [rip + allows + VEC_ptr]
    mov rdi, [r12 + RA_name]
    call mem_free
    mov rdi, [r12 + RA_project]
    call mem_free
    mov rdx, [rip + allows + VEC_len]
    sub rdx, rbx
    dec rdx
    imul rdx, rdx, RA_SIZE
    mov rdi, r12
    lea rsi, [r12 + RA_SIZE]
    call memmove
    dec qword ptr [rip + allows + VEC_len]
    EPILOGUE

# dup(cstr) -> an owned copy
dup:
    push rbx
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    pop rbx
    ret

# run_approved(ext) -> 1 when it may run programs as the user in the current project
FN run_approved
    sub rsp, 8
    call full_name
    mov rdi, rax
    call project_key
    mov rsi, rax
    call find
    add rsp, 8
    xor ecx, ecx
    test rax, rax
    setnz cl
    mov eax, ecx
    ret

# run_approve(ext, command, done, cookie) -> 1, 0 or -1 (see the top of the file)
FN run_approve
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call run_approved
    test eax, eax
    jnz 9f
    cmp dword ptr [rip + ask_open], 0
    jne 8f
    call app_dialog_open
    test eax, eax
    jnz 8f
    mov [rip + ask_done], r13
    mov [rip + ask_cookie], r14
    mov rdi, rbx
    call full_name
    mov rdi, rax
    call dup
    mov [rip + ask_name], rax
    call project_key
    mov rdi, rax
    call dup
    mov [rip + ask_project], rax
    mov dword ptr [rip + ask_open], 1
    # Let Tasks run programs in app?
    lea rdi, [rip + q_buf]
    lea rsi, [rip + .Lq_let]
    call cstr_copy
    mov r15, rax
    mov rdi, rbx
    call ext_title
    mov rdi, r15
    mov rsi, rax
    mov edx, 200
    call copy_max
    mov rdi, rax
    lea rsi, [rip + .Lq_run]
    call cstr_copy
    mov r15, rax
    mov rsi, [rip + g_project_name]
    test rsi, rsi
    jz 1f
    cmp qword ptr [rip + g_project], 0
    je 1f
    mov rdi, r15
    lea rsi, [rip + .Lq_in]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + g_project_name]
    mov edx, 200
    call copy_max
    mov r15, rax
1:  mov rdi, r15
    lea rsi, [rip + .Lq_end]
    call cstr_copy
    # the command (its middle left out when long), then where: go build ./...   in ~/code/app
    lea rdi, [rip + l_buf]
    mov rsi, r12
    call elided
    mov r15, rax
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 2f
    call strlen
    cmp rax, 4000
    jae 2f
    mov rdi, r15
    lea rsi, [rip + .Ll_in]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rip + g_project]
    call path_tilde
2:  lea rdi, [rip + q_buf]
    lea rsi, [rip + l_buf]
    lea rdx, [rip + .Lallow]
    lea rcx, [rip + on_allow]
    call app_confirm
    lea rdi, [rip + on_cancel]
    call app_confirm_cancel
    xor eax, eax
    EPILOGUE
8:  mov eax, -1
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# copy_max(dst, src, max) -> dst's NUL: src, cut at max bytes on a character's start
copy_max:
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 3f
    cmp rcx, rdx
    jb 2f
    and eax, 0xc0
    cmp eax, 0x80
    jne 3f                      # at the limit and not inside a character
2:  mov al, [rsi + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp 1b
3:  mov byte ptr [rdi + rcx], 0
    lea rax, [rdi + rcx]
    ret

# elided(dst, cmd) -> dst's NUL: the command, or its first and last parts around a "…" when longer
#   than CMD_SHOWN bytes (each cut on a character's start)
elided:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov r13, rax
    cmp rax, CMD_SHOWN
    ja 1f
    mov rdi, rbx
    mov rsi, r12
    call cstr_copy
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, r12
    mov edx, CMD_SHOWN / 2
    call copy_max
    mov rdi, rax
    lea rsi, [rip + .Lellipsis]
    call cstr_copy
    mov r14, rax
    # the tail: from len - CMD_SHOWN/2, moved forward to a character's start
    lea rsi, [r12 + r13 - CMD_SHOWN / 2]
2:  movzx eax, byte ptr [rsi]
    and eax, 0xc0
    cmp eax, 0x80
    jne 3f
    inc rsi
    jmp 2b
3:  mov rdi, r14
    call cstr_copy
    EPILOGUE

# on_allow(): Allow: remembered for this extension and project, then the program runs
on_allow:
    PROLOGUE
    cmp dword ptr [rip + ask_open], 0
    je 9f
    mov dword ptr [rip + ask_open], 0
    mov rdi, [rip + ask_name]
    mov rsi, [rip + ask_project]
    mov qword ptr [rip + ask_name], 0
    mov qword ptr [rip + ask_project], 0
    call add
    call ext_settings_save
    mov rdi, [rip + ask_cookie]
    mov esi, 1
    call [rip + ask_done]
9:  EPILOGUE

# on_cancel(): Cancel, or another dialog took its place: nothing is remembered
on_cancel:
    PROLOGUE
    cmp dword ptr [rip + ask_open], 0
    je 9f
    call ask_clear
    mov rdi, [rip + ask_cookie]
    xor esi, esi
    call [rip + ask_done]
9:  EPILOGUE

# ask_clear(): no question open
ask_clear:
    sub rsp, 8
    mov dword ptr [rip + ask_open], 0
    mov rdi, [rip + ask_name]
    call mem_free
    mov rdi, [rip + ask_project]
    call mem_free
    mov qword ptr [rip + ask_name], 0
    mov qword ptr [rip + ask_project], 0
    add rsp, 8
    ret

# run_approve_cancel(cookie): the question for cookie goes away unanswered
FN run_approve_cancel
    sub rsp, 8
    cmp dword ptr [rip + ask_open], 0
    je 9f
    cmp [rip + ask_cookie], rdi
    jne 9f
    call ask_clear
    xor edi, edi                # closing it must not run its Cancel
    call app_confirm_cancel
    lea rdi, [rip + on_allow]
    call app_confirm_revoke_pure
    mov dword ptr [rip + g_dirty], 1
9:  add rsp, 8
    ret

# run_forget(ext): its approvals go, and it will ask again
FN run_forget
    PROLOGUE
    call full_name
    mov r12, rax
    mov rbx, [rip + allows + VEC_len]
1:  test rbx, rbx
    jz 8f
    dec rbx
    imul rax, rbx, RA_SIZE
    add rax, [rip + allows + VEC_ptr]
    mov rdi, [rax + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, rbx
    call remove_at
    jmp 1b
8:  call ext_settings_save
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- extensions.ini ----------------

# run_allow_load_line(ini iterator) -> 1 when the line was an approval (allow_run = PROJECT)
FN run_allow_load_line
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + INI_key]
    mov rsi, [rbx + INI_keylen]
    lea rdx, [rip + .Lk_allow]
    call str_eq_cstr
    test eax, eax
    jz 9f
    cmp qword ptr [rbx + INI_seclen], 0
    je 8f
    cmp qword ptr [rbx + INI_vallen], 0
    je 8f
    mov rdi, [rbx + INI_sec]
    mov rsi, [rbx + INI_seclen]
    call mem_dup
    mov r12, rax
    mov rdi, [rbx + INI_val]
    mov rsi, [rbx + INI_vallen]
    call mem_dup
    mov rdi, r12
    mov rsi, rax
    call add
8:  mov eax, 1
9:  EPILOGUE

# run_allow_has(ext) -> 1 when it has approvals to write
FN run_allow_has
    PROLOGUE
    call full_name
    mov r12, rax
    xor ebx, ebx
1:  cmp rbx, [rip + allows + VEC_len]
    jae 8f
    imul rax, rbx, RA_SIZE
    add rax, [rip + allows + VEC_ptr]
    inc rbx
    mov rdi, [rax + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# run_allow_write(ext, sb): its "allow_run = PROJECT" lines (inside its section)
FN run_allow_write
    PROLOGUE
    mov r13, rsi
    call full_name
    mov r12, rax
    xor ebx, ebx
1:  cmp rbx, [rip + allows + VEC_len]
    jae 9f
    imul r14, rbx, RA_SIZE
    add r14, [rip + allows + VEC_ptr]
    inc rbx
    mov rdi, [r14 + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, r13
    lea rsi, [rip + .Lw_allow]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [r14 + RA_project]
    call sb_push_cstr
    mov rdi, r13
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# run_allow_projects(ext, sb) -> how many: its approved folders, ~ for home, joined by ", " (its page)
FN run_allow_projects
    PROLOGUE 4096
    mov r13, rsi
    call full_name
    mov r12, rax
    xor ebx, ebx
    xor r15d, r15d
1:  cmp rbx, [rip + allows + VEC_len]
    jae 9f
    imul r14, rbx, RA_SIZE
    add r14, [rip + allows + VEC_ptr]
    inc rbx
    mov rdi, [r14 + RA_name]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    test r15d, r15d
    jz 2f
    mov rdi, r13
    lea rsi, [rip + .Lcomma]
    call sb_push_cstr
2:  inc r15d
    mov rsi, [r14 + RA_project]
    lea rax, [rip + .Lno_project]
    cmp word ptr [rsi], 0x002d          # "-"
    cmove rsi, rax
    je 3f
    mov rdi, rsi
    call strlen
    cmp rax, 4000
    jae 3f
    lea rdi, [rsp]
    mov rsi, [r14 + RA_project]
    call path_tilde
    lea rsi, [rsp]
3:  mov rdi, r13
    call sb_push_cstr
    jmp 1b
9:  mov eax, r15d
    EPILOGUE

# run_allow_dump(sb): "OWNER/NAME PROJECT" per approval, and "ask=open" while one asks (print-allowed)
FN run_allow_dump
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + allows + VEC_len]
    jae 8f
    imul r14, rbx, RA_SIZE
    add r14, [rip + allows + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, [r14 + RA_name]
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + RA_project]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
8:  cmp dword ptr [rip + ask_open], 0
    je 9f
    mov rdi, r12
    lea rsi, [rip + .Ld_asking]
    call sb_push_cstr
9:  EPILOGUE

.section .rodata
.Ldash: .asciz "-"
.Lq_let: .asciz "Let "
.Lq_run: .asciz " run programs"
.Lq_in: .asciz " in "
.Lq_end: .asciz "?"
.Ll_in: .asciz "   in "
.Lallow: .asciz "Allow"
.Lellipsis: .asciz "\342\200\246"
.Lk_allow: .asciz "allow_run"
.Lw_allow: .asciz "allow_run = "
.Lcomma: .asciz ", "
.Lno_project: .asciz "without a project"
.Ld_asking: .asciz "ask=open\n"
