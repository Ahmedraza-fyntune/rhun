# inotify: explorer refresh, agent sessions, files changed on disk, config reload, Omarchy theme
.include "rhun.inc"

.equ WK_EXPLORER, 1
.equ WK_AGENTS, 2
.equ WK_DOCS, 4
.equ WK_CONFIG, 8
.equ WK_OMARCHY, 16
.equ MAXWD, 4096
.equ WMASK, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE | IN_MODIFY

.bss
.p2align 3
wd_paths: .zero 8 * MAXWD
wd_kinds: .zero MAXWD
evbuf: .zero 16384
tmp: .zero SB_SIZE
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

# add_watch(path, kind)
add_watch:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
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
9:  EPILOGUE

FN watch_dir
    mov esi, WK_EXPLORER
    jmp add_watch
FN watch_agents_dir
    mov esi, WK_AGENTS
    jmp add_watch

# watch_doc(path): watch the directory holding an open file
FN watch_doc
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jz 9f
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov r12, rax
    mov rdi, rax
    mov esi, WK_DOCS
    call add_watch
    mov rdi, r12
    call mem_free
9:  EPILOGUE

on_inotify:
    PROLOGUE 16
    mov dword ptr [rsp], 0      # explorer refresh wanted
    mov dword ptr [rsp + 4], 0  # agents changed
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
    test ecx, WK_EXPLORER
    jz 1f
    test r15d, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO
    jz 1f
    mov dword ptr [rsp], 1
1:  test ecx, WK_AGENTS
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
    cmp dword ptr [rsp], 0
    je 4f
    call explorer_refresh
4:  cmp dword ptr [rsp + 4], 0
    je 5f
    call agents_on_change
5:  EPILOGUE

# doc_changed(wd, name): reload an unmodified open document whose file changed
doc_changed:
    PROLOGUE
    lea rax, [rip + wd_paths]
    mov rdi, [rax + rdi*8]
    test rdi, rdi
    jz 9f
    call path_join
    mov rbx, rax
    mov rdi, rax
    call app_find_tab
    test rax, rax
    js 8f
    mov rdi, rax
    call tab_at
    mov r12, [rax + TAB_doc]
    mov rdi, rbx
    call file_mtime
    cmp rax, [r12 + DOC_mtime]
    je 8f
    mov rdi, r12
    call doc_dirty
    test eax, eax
    jnz 7f
    mov rdi, r12
    call app_reload_doc
    jmp 8f
7:  lea rdi, [rip + .Lchanged]
    call app_toast
8:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

# app_reload_doc(doc): replace contents from disk, keep the cursor near where it was
FN app_reload_doc
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 9f
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    mov r13, rdx
    # drop CRs of CRLF files
    cmp dword ptr [rbx + DOC_crlf], 0
    je 2f
    xor ecx, ecx
    xor edx, edx
1:  cmp rcx, r13
    jae 11f
    movzx eax, byte ptr [r12 + rcx]
    inc rcx
    cmp al, 13
    je 1b
    mov [r12 + rdx], al
    inc rdx
    jmp 1b
11: mov r13, rdx
2:  mov r14, [rbx + DOC_cur]
    mov r15, [rbx + DOC_scrolly]
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_set_text
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    call doc_len
    cmp r14, rax
    cmova r14, rax
    mov [rbx + DOC_cur], r14
    mov [rbx + DOC_anchor], r14
    mov [rbx + DOC_scrolly], r15
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rbx + DOC_savepoint], rax
    mov rdi, [rbx + DOC_path]
    call file_mtime
    mov [rbx + DOC_mtime], rax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

FN cmd_reload_file
    mov rdi, [rip + g_doc]
    test rdi, rdi
    jz 1f
    jmp app_reload_doc
1:  ret

.section .rodata
.Lconfig: .asciz "config"
.Ltheme_name: .asciz "theme.name"
.Lchanged: .asciz "File changed on disk (unsaved edits kept)"
