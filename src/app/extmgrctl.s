# extension management's headless commands (registered in control.s's ctl_tables):
#   ext-install-folder PATH [copy|link]   Install from Folder (copied) or Link a Folder
#   ext-install-archive PATH              Install from Archive
#   ext-rollback NAME                     Roll back to the previous version (asks when it may do more)
#   print-ext-versions NAME               "version=V source=S tag=T previous=P link=yes|no fresh=0|1"
#   ext-check-updates                     Check for updates (the index, then GitHub)
#   wait-ext-updates                      until the check and the updates it queued are done (or ask)
#   print-ext-updates                     a line per extension (extupdate_dump)
#   ext-update NAME, ext-update-all       Update, Update all
#   ext-browse                            the Extensions page's Browse list (the index fetched when old)
#   ext-index-refresh, wait-index         Refresh; until no fetch runs (1 minute at most), "index=..."
#   ext-search TEXT                       Browse's search
#   print-ext-browse                      extpage_browse_dump
#   ext-browse-install NAME               the entry's Install or Update button
.include "rhun.inc"

.bss
.p2align 3
xm_out: .quad 0                 # control.s's output buffer
xm_buf: .zero 4096

.text

# XM_ARGS: a command's (out sb, rest, rest len) as rest in rdi, len in rsi, the output kept
.macro XM_ARGS
    mov [rip + xm_out], rdi
    mov rdi, rsi
    mov rsi, rdx
.endm

# XM_DONE: a command's end: rax 0 (done)
.macro XM_DONE
    xor eax, eax
    EPILOGUE
.endm

# xm_push(cstr): onto the output
xm_push:
    mov rsi, rdi
    mov rdi, [rip + xm_out]
    jmp sb_push_cstr

# xm_ext(ptr, len) -> the extension named by the first word of the arguments, or 0 (the output says so)
xm_ext:
    PROLOGUE
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jnz 9f
    push rax
    push rax
    lea rdi, [rip + .Lno_ext]
    call xm_push
    pop rax
    pop rax
9:  EPILOGUE

# ext-install-folder PATH [copy|link]
c_install_folder:
    XM_ARGS
    PROLOGUE
    call trim
    mov rbx, rax
    mov r12, rdx
    mov r13d, IK_FOLDER
    cmp r12, 5
    jb 9f
    lea rdi, [rbx + r12 - 5]
    mov esi, 5
    lea rdx, [rip + .Lsp_link]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov r13d, IK_LINK
    sub r12, 5
    jmp 9f
1:  lea rdi, [rbx + r12 - 5]
    mov esi, 5
    lea rdx, [rip + .Lsp_copy]
    call str_eq_cstr
    test eax, eax
    jz 9f
    sub r12, 5
9:  mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ext_install_local
    XM_DONE

# ext-install-archive PATH
c_install_archive:
    XM_ARGS
    PROLOGUE
    mov edx, IK_ARCHIVE
    call ext_install_local
    XM_DONE

# ext-rollback NAME
c_rollback:
    XM_ARGS
    PROLOGUE
    call xm_ext
    test rax, rax
    jz 9f
    mov rdi, rax
    call ext_rollback_ask
9:  XM_DONE

# print-ext-versions NAME
c_print_versions:
    XM_ARGS
    PROLOGUE
    call xm_ext
    test rax, rax
    jz 9f
    mov rbx, rax
    lea rdi, [rip + .Lp_version]
    call xm_push
    mov rdi, [rbx + EXT_version]
    test rdi, rdi
    jz 1f
    call xm_push
1:  lea rdi, [rip + .Lp_source]
    lea rsi, [rip + .Lk_source]
    call xm_rec_pair
    lea rdi, [rip + .Lp_tag]
    lea rsi, [rip + .Lk_tag]
    call xm_rec_pair
    lea rdi, [rip + .Lp_previous]
    call xm_push
    mov rdi, [rbx + EXT_prev]
    test rdi, rdi
    jnz 2f
    lea rdi, [rip + .Ldash]
2:  call xm_push
    lea rdi, [rip + .Lp_link]
    call xm_push
    lea rdi, [rip + .Lno]
    cmp qword ptr [rbx + EXT_inst], 0
    je 3f
    lea rdi, [rip + .Lyes]
3:  call xm_push
    lea rdi, [rip + .Lp_fresh]
    call xm_push
    mov rdi, [rip + xm_out]
    mov esi, [rbx + EXT_fresh]
    call sb_push_u64
    mov rdi, [rip + xm_out]
    mov esi, 10
    call sb_push_byte
9:  XM_DONE

# ext-check-updates
c_check_updates:
    XM_ARGS
    PROLOGUE
    call cmd_check_extensions
    XM_DONE

# wait-ext-updates: until no check runs, no update downloads and none waits its turn unless a
# dialog asks (2 minutes at most), then "updates=idle|asking|busy"
c_wait_updates:
    XM_ARGS
    PROLOGUE
    call time_ms
    lea r13, [rax + 120000]
1:  call xm_updates_state
    cmp eax, 2
    jne 2f
    call time_ms
    cmp rax, r13
    jae 2f
    mov edi, 50
    call loop_poll
    call app_tick
    call xm_flush
    jmp 1b
2:  lea rdi, [rip + .Lu_idle]
    test eax, eax
    jz 3f
    lea rdi, [rip + .Lu_asking]
    cmp eax, 1
    je 3f
    lea rdi, [rip + .Lu_busy]
3:  call xm_push
    XM_DONE

# xm_updates_state() -> eax 0 idle, 1 a dialog asks, 2 busy
xm_updates_state:
    PROLOGUE
    mov eax, 1
    cmp dword ptr [rip + g_ext_install_state], 2
    je 9f
    mov eax, 2
    cmp dword ptr [rip + g_ext_install_state], 1
    je 9f
    call extupdate_busy
    test eax, eax
    jz 9f
    mov eax, 2
9:  EPILOGUE

# xm_flush(): the frame, as control.s's commands end with one (headless and Windows draw at once)
xm_flush:
.ifndef WINDOWS
    cmp dword ptr [rip + g_headless], 0
    je 1f
.endif
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

# print-ext-updates
c_print_updates:
    XM_ARGS
    PROLOGUE
    mov rdi, [rip + xm_out]
    call extupdate_dump
    XM_DONE

# ext-update NAME
c_update:
    XM_ARGS
    PROLOGUE
    call xm_ext
    test rax, rax
    jz 9f
    mov rdi, rax
    call extupdate_update
9:  XM_DONE

# ext-update-all
c_update_all:
    XM_ARGS
    PROLOGUE
    call extupdate_update_all
    XM_DONE

# ext-browse
c_browse:
    XM_ARGS
    PROLOGUE
    call cmd_extensions
    call extpage_browse
    XM_DONE

# ext-index-refresh
c_index_refresh:
    XM_ARGS
    PROLOGUE
    call extindex_refresh
    XM_DONE

# wait-index
c_wait_index:
    XM_ARGS
    PROLOGUE
    call time_ms
    lea r13, [rax + 60000]
1:  call extindex_state
    test edx, edx
    jz 2f
    call time_ms
    cmp rax, r13
    jae 2f
    mov edi, 50
    call loop_poll
    call app_tick
    call xm_flush
    jmp 1b
2:  XM_DONE

# ext-search TEXT
c_search:
    XM_ARGS
    PROLOGUE
    call trim
    mov rdi, rax
    mov rsi, rdx
    call extpage_search
    XM_DONE

# print-ext-browse
c_print_browse:
    XM_ARGS
    PROLOGUE
    mov rdi, [rip + xm_out]
    call extpage_browse_dump
    XM_DONE

# ext-browse-install NAME
c_browse_install:
    XM_ARGS
    PROLOGUE
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call extpage_browse_click
    test eax, eax
    jnz 9f
    lea rdi, [rip + .Lno_button]
    call xm_push
9:  XM_DONE

# xm_rec_pair(" key=", record key): " key=VALUE" (or "-") for rbx's record
xm_rec_pair:
    PROLOGUE
    mov r12, rsi
    call xm_push
    mov rdi, rbx
    mov rsi, r12
    call extrec_get
    test rax, rax
    jz 8f
    test rdx, rdx
    jz 8f
    cmp rdx, 4000
    ja 8f
    lea rdi, [rip + xm_buf]
    mov rsi, rax
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rdi, [rip + xm_buf]
    mov byte ptr [rdi + rdx], 0
    call xm_push
    EPILOGUE
8:  lea rdi, [rip + .Ldash]
    call xm_push
    EPILOGUE

.section .rodata
.Lc_install_folder: .asciz "ext-install-folder"
.Lc_install_archive: .asciz "ext-install-archive"
.Lc_rollback: .asciz "ext-rollback"
.Lc_print_versions: .asciz "print-ext-versions"
.Lc_check_updates: .asciz "ext-check-updates"
.Lc_wait_updates: .asciz "wait-ext-updates"
.Lc_print_updates: .asciz "print-ext-updates"
.Lc_update: .asciz "ext-update"
.Lc_update_all: .asciz "ext-update-all"
.Lu_idle: .asciz "updates=idle\n"
.Lu_asking: .asciz "updates=asking\n"
.Lu_busy: .asciz "updates=busy\n"
.Lc_browse: .asciz "ext-browse"
.Lc_index_refresh: .asciz "ext-index-refresh"
.Lc_wait_index: .asciz "wait-index"
.Lc_search: .asciz "ext-search"
.Lc_print_browse: .asciz "print-ext-browse"
.Lc_browse_install: .asciz "ext-browse-install"
.Lno_button: .asciz "no such button\n"
.Lsp_link: .asciz " link"
.Lsp_copy: .asciz " copy"
.Lno_ext: .asciz "no such extension\n"
.Lp_version: .asciz "version="
.Lp_source: .asciz " source="
.Lp_tag: .asciz " tag="
.Lp_previous: .asciz " previous="
.Lp_link: .asciz " link="
.Lp_fresh: .asciz " fresh="
.Lk_source: .asciz "source"
.Lk_tag: .asciz "tag"
.Ldash: .asciz "-"
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.p2align 3
.globl extmgr_ctl
extmgr_ctl:
    .quad .Lc_install_folder, c_install_folder, .Lc_install_archive, c_install_archive
    .quad .Lc_rollback, c_rollback, .Lc_print_versions, c_print_versions
    .quad .Lc_check_updates, c_check_updates, .Lc_wait_updates, c_wait_updates
    .quad .Lc_print_updates, c_print_updates, .Lc_update, c_update, .Lc_update_all, c_update_all
    .quad .Lc_browse, c_browse, .Lc_index_refresh, c_index_refresh, .Lc_wait_index, c_wait_index
    .quad .Lc_search, c_search, .Lc_print_browse, c_print_browse, .Lc_browse_install, c_browse_install
    .quad 0, 0
