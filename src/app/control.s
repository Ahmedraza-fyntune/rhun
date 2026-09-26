# scripted control: line commands from a file (--script) or a unix socket (--control)
#   key ctrl+s | type text | click x y [right] | move x y | down | up | scroll dy
#   open path | cmd name | shot file.ppm | wait ms | resize w h | print-doc | print-state | echo text | quit
.include "rhun.inc"

.bss
.p2align 3
out: .zero SB_SIZE
cbuf: .zero SB_SIZE
addr: .zero 110
.globl g_headless
g_headless: .long 0

.text

# arg helpers: rbx = rest pointer, r12 = rest length
next_arg:
    mov rdi, rbx
    mov rsi, r12
    call next_word
    add rbx, rcx
    sub r12, rcx
    ret

next_int:
    call next_arg
    push rbx
    mov rdi, rax
    mov rsi, rdx
    xor ebx, ebx
    test rsi, rsi
    jz 1f
    cmp byte ptr [rdi], '-'
    jne 1f
    inc rdi
    dec rsi
    mov ebx, 1
1:  call parse_u64
    test ebx, ebx
    jz 2f
    neg rax
2:  pop rbx
    ret

# render if needed (headless draws synchronously)
flush_frame:
    cmp dword ptr [rip + g_headless], 0
    je 1f
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

# emit_key(keysym, mods): derive the character like the platform does
emit_key:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    xor r13d, r13d
    cmp ebx, 0x20
    jb 1f
    cmp ebx, 0x7e
    ja 1f
    mov r13d, ebx
    # shift for letters
    test r12d, MOD_SHIFT
    jz 1f
    lea eax, [rbx - 'a']
    cmp eax, 25
    ja 1f
    sub r13d, 32
    sub ebx, 32
1:  mov edi, ebx
    mov esi, r13d
    mov edx, r12d
    call app_on_key
    pop r13
    pop r12
    pop rbx
    ret

# control_exec(line ptr, len) -> 0 ok, 1 quit, -1 unknown
FN control_exec
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + out]
    call sb_clear
    call next_arg
    test rdx, rdx
    jz .Lce_ok
    mov r13, rax
    mov r14, rdx
    cmp byte ptr [r13], '#'
    je .Lce_ok
    # trim leading blank of the rest (for type/echo)
    mov rdi, rbx
    mov rsi, r12
    call trim
    mov rbx, rax
    mov r12, rdx
    lea r15, [rip + ctl_table]
1:  mov rdx, [r15]
    test rdx, rdx
    jz .Lce_unknown
    mov rdi, r13
    mov rsi, r14
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add r15, 16
    jmp 1b
2:  call [r15 + 8]
    push rax
    push rax
    call flush_frame
    pop rax
    pop rax
    EPILOGUE
.Lce_ok:
    xor eax, eax
    EPILOGUE
.Lce_unknown:
    lea rdi, [rip + out]
    lea rsi, [rip + .Lunknown]
    call sb_push_cstr
    mov rax, -1
    EPILOGUE

c_key:
    mov rdi, rbx
    mov rsi, r12
    call parse_combo
    test eax, eax
    jz 1f
    mov edi, eax
    mov esi, edx
    call emit_key
1:  xor eax, eax
    ret

c_type:
    push r13
    push r14
    sub rsp, 8
    xor r13d, r13d
1:  cmp r13, r12
    jae 2f
    lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    add r13, rdx
    mov r14d, eax
    mov edi, eax
    cmp eax, 0x7e
    jbe 3f
    or edi, 0x1000000
3:  mov esi, r14d
    xor edx, edx
    call app_on_key
    call flush_frame
    jmp 1b
2:  add rsp, 8
    pop r14
    pop r13
    xor eax, eax
    ret

c_move:
    call next_int
    push rax
    call next_int
    pop rdi
    mov esi, eax
    call app_on_motion
    xor eax, eax
    ret

c_click:
    call next_int
    push rax
    call next_int
    pop rdi
    push rdi
    push rax
    mov esi, eax
    call app_on_motion
    call flush_frame
    call next_arg
    mov r13d, BTN_LEFT
    test rdx, rdx
    jz 1f
    cmp byte ptr [rax], 'r'
    jne 1f
    mov r13d, BTN_RIGHT
1:  mov edi, r13d
    mov esi, 1
    xor edx, edx
    call app_on_button
    call flush_frame
    mov edi, r13d
    call release
    pop rax
    pop rax
    xor eax, eax
    ret

# release(button): unless a window move took the pointer (headless records that)
release:
    cmp dword ptr [rip + g_hl_grab], 0
    je 1f
    mov dword ptr [rip + g_hl_grab], 0
    ret
1:  xor esi, esi
    xor edx, edx
    jmp app_on_button

c_down:
    mov edi, BTN_LEFT
    mov esi, 1
    xor edx, edx
    call app_on_button
    xor eax, eax
    ret

c_up:
    mov edi, BTN_LEFT
    call release
    xor eax, eax
    ret

# print-cursor SHAPE SIZE: which cursor image the theme lookup picks
c_print_cursor:
    push r13
    push r14
    sub rsp, 8
    call next_int
    mov r13d, eax
    call next_int
    mov r14d, eax
    mov edi, r13d
    mov esi, r14d
    lea rdx, [rip + pc_xc]
    call xcursor_load
    test eax, eax
    jz 1f
    lea rdi, [rip + out]
    mov rsi, [rip + g_xcursor_found + SB_ptr]
    call sb_push_cstr
    jmp 2f
1:  mov edi, r13d
    mov esi, r14d
    lea rdx, [rip + pc_xc]
    call xcursor_builtin
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_builtin]
    call sb_push_cstr
2:  lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rip + pc_xc + XC_w]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 'x'
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rip + pc_xc + XC_h]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_hot]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + pc_xc + XC_xhot]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ','
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rip + pc_xc + XC_yhot]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + pc_xc + XC_file]
    call mem_free
    add rsp, 8
    pop r14
    pop r13
    xor eax, eax
    ret

# print-window: window requests seen by the headless platform
c_print_window:
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_moves]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_hl_moves]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_maximized]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_win_states]
    and esi, 1
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_minimized]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_hl_minimized]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_quit]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_quit]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_csd]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_csd]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    ret

c_scroll:
    call next_int
    xor edi, edi
    mov esi, eax
    call app_on_scroll
    xor eax, eax
    ret

c_open:
    mov rdi, rbx
    mov rsi, r12
    call mem_dup
    push rax
    push rax
    mov rdi, rax
    call app_open_path
    pop rdi
    pop rdi
    call mem_free
    xor eax, eax
    ret

c_cmd:
    mov rdi, rbx
    mov rsi, r12
    call cmd_find
    test rax, rax
    jz 1f
    call [rax + CMD_fn]
    mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    ret
1:  mov rax, -1
    ret

c_shot:
    mov rdi, rbx
    mov rsi, r12
    call mem_dup
    mov [rip + g_shot_path], rax
    mov dword ptr [rip + g_dirty], 1
    cmp dword ptr [rip + g_headless], 0
    je 1f
    PCALL P_draw
1:  xor eax, eax
    ret

c_wait:
    call next_int
    sub rsp, 24
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [rsp], rax
    imul rdx, rdx, 1000000
    mov [rsp + 8], rdx
    mov rdi, rsp
    xor esi, esi
    mov eax, 35                 # nanosleep
    syscall
    add rsp, 24
    # let timers run (agents poll, blink)
    call app_tick
    xor eax, eax
    ret

c_resize:
    call next_int
    push rax
    call next_int
    pop rdi
    mov esi, eax
    call headless_resize
    xor eax, eax
    ret

c_quit:
    mov eax, 1
    ret

c_echo:
    lea rdi, [rip + out]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    ret

c_print_doc:
    push rbx
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 1f
    mov rdi, rbx
    call doc_len
    push rax
    push rax
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_reserve
    pop rdx
    pop rdx
    mov rcx, rax
    push rdx
    push rdx
    mov rdi, rbx
    xor esi, esi
    call doc_copy
    pop rdx
    pop rdx
    add [rip + out + SB_len], rdx
    lea rdi, [rip + out]
    lea rsi, [rip + .Leod]
    call sb_push_cstr
1:  pop rbx
    xor eax, eax
    ret

# print-state: "tabs=N active=name line=L col=C sel=S dirty=D focus=F lang=X theme=T"
c_print_state:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_tabs]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, [rip + g_tabs + VEC_len]
    call sb_push_u64
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 1f
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_active]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, [rbx + DOC_name]
    call sb_push_cstr
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_line]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    lea rdi, [rip + out]
    lea rsi, [rax + 1]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_col]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
    lea rdi, [rip + out]
    lea esi, [rax + 1]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_sel]
    call sb_push_cstr
    mov rdi, rbx
    call ed_sel
    sub rdx, rax
    lea rdi, [rip + out]
    mov rsi, rdx
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_dirty]
    call sb_push_cstr
    mov rdi, rbx
    call doc_dirty
    lea rdi, [rip + out]
    mov esi, eax
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_lang]
    call sb_push_cstr
    mov rax, [rbx + DOC_lang]
    lea rsi, [rip + .Lnone]
    test rax, rax
    jz 2f
    mov rsi, [rax + GR_name]
2:  lea rdi, [rip + out]
    call sb_push_cstr
1:  lea rdi, [rip + out]
    lea rsi, [rip + .Ls_focus]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + g_focus]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Ls_theme]
    call sb_push_cstr
    call theme_current_id
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    add rsp, 8
    pop r12
    pop rbx
    xor eax, eax
    ret

# print-syntax N: class digit per byte of line N
c_print_syntax:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call next_int
    mov r14, rax
    dec r14
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp r14, [rbx + DOC_nlines]
    jae 9f
    mov rdi, rbx
    mov rsi, r14
    call syntax_prepare
    mov rdi, rbx
    mov rsi, r14
    call doc_line_text
    mov r12, rax
    mov r13, rdx
    lea rdi, [rip + out]
    lea rsi, [r13 + r13 + 2]
    call sb_reserve
    mov r15, rax
    # text line, then classes
    mov rdi, r15
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 10
    lea r8, [r15 + r13 + 1]
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    mov rcx, r13
    push r8
    push r8
    call syntax_line
    pop r8
    pop r8
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    movzx eax, byte ptr [r8 + rcx]
    lea rdx, [rip + .Ldigits]
    mov al, [rdx + rax]
    mov [r8 + rcx], al
    inc rcx
    jmp 1b
2:  lea rax, [r13 + r13 + 1]
    add [rip + out + SB_len], rax
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
9:  pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    ret

# print-agents [open N]: sessions and the open thread
c_print_agents:
    call next_int
    test rdx, rdx
    jz 1f
    dec rax
    js 1f
    mov rdi, rax
    call agents_open
1:  lea rdi, [rip + out]
    call agents_dump
    xor eax, eax
    ret

# xkey KEYCODE STATE: X11 only, runs a keycode through the server's keymap
c_xkey:
    call next_int
    push rax
    call next_int
    pop rdi
    mov esi, eax
    call x_key_test
    xor eax, eax
    ret

# control_run_script(path): execute every line, print outputs to stdout
FN control_run_script
    PROLOGUE
    call file_read_all
    test rax, rax
    jz .Lrs_fail
    mov r12, rax
    mov r13, rdx
    xor r14d, r14d
.Lrs_line:
    cmp r14, r13
    jae .Lrs_done
    mov r15, r14
1:  cmp r15, r13
    jae 2f
    cmp byte ptr [r12 + r15], 10
    je 2f
    inc r15
    jmp 1b
2:  lea rdi, [r12 + r14]
    mov rsi, r15
    sub rsi, r14
    call control_exec
    mov rbx, rax
    mov rdi, 1
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    test rdx, rdx
    jz 3f
    call write_all
3:  cmp rbx, 1
    je .Lrs_done
    lea r14, [r15 + 1]
    jmp .Lrs_line
.Lrs_done:
    xor eax, eax
    EPILOGUE
.Lrs_fail:
    mov eax, 1
    EPILOGUE

# control_listen(path): accept connections, one command per line, reply "ok"/"error"
FN control_listen
    PROLOGUE
    mov rbx, rdi
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js 9f
    mov [rip + lsock], eax
    mov rdi, rbx
    SYS SYS_unlink
    lea rdi, [rip + addr]
    mov word ptr [rdi], AF_UNIX
    add rdi, 2
    mov rsi, rbx
    call cstr_copy
    mov edi, [rip + lsock]
    lea rsi, [rip + addr]
    mov edx, 110
    SYS SYS_bind
    test rax, rax
    js 9f
    mov edi, [rip + lsock]
    mov esi, 4
    SYS SYS_listen
    mov edi, [rip + lsock]
    mov esi, POLLIN
    lea rdx, [rip + on_accept]
    xor ecx, ecx
    call watch_add
9:  EPILOGUE

on_accept:
    push rbx
    mov edi, [rip + lsock]
    xor esi, esi
    xor edx, edx
    mov r10d, SOCK_CLOEXEC
    SYS SYS_accept4
    test rax, rax
    js 9f
    mov ebx, eax
    # one client at a time: drop the previous one
    mov edi, [rip + csock]
    test edi, edi
    js 1f
    call watch_remove
    mov edi, [rip + csock]
    SYS SYS_close
1:  mov [rip + csock], ebx
    lea rdi, [rip + cbuf]
    call sb_clear
    mov edi, ebx
    mov esi, POLLIN
    lea rdx, [rip + on_client]
    xor ecx, ecx
    call watch_add
9:  pop rbx
    ret

on_client:
    PROLOGUE
    mov ebx, edi
    lea rdi, [rip + cbuf]
    mov esi, 4096
    call sb_reserve
    mov edi, ebx
    mov rsi, rax
    mov edx, 4096
    SYS SYS_read
    test rax, rax
    jle .Loc_close
    add [rip + cbuf + SB_len], rax
.Loc_lines:
    mov r12, [rip + cbuf + SB_ptr]
    mov r13, [rip + cbuf + SB_len]
    xor ecx, ecx
1:  cmp rcx, r13
    jae 9f
    cmp byte ptr [r12 + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov r14, rcx
    mov rdi, r12
    mov rsi, rcx
    call control_exec
    mov r15, rax
    # reply: output then ok / error
    mov edi, ebx
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    test rdx, rdx
    jz 3f
    call write_all
3:  lea rsi, [rip + .Lok]
    mov edx, 3
    test r15, r15
    jns 4f
    lea rsi, [rip + .Lerror]
    mov edx, 6
4:  mov edi, ebx
    call write_all
    cmp r15, 1
    jne 5f
    mov dword ptr [rip + g_quit], 1
5:  # drop the processed line
    mov rdi, [rip + cbuf + SB_ptr]
    lea rsi, [rdi + r14 + 1]
    mov rdx, [rip + cbuf + SB_len]
    sub rdx, r14
    dec rdx
    mov [rip + cbuf + SB_len], rdx
    call memmove
    jmp .Loc_lines
.Loc_close:
    mov edi, ebx
    call watch_remove
    mov edi, ebx
    SYS SYS_close
    mov dword ptr [rip + csock], -1
9:  EPILOGUE

.section .rodata
.Lunknown: .asciz "unknown command\n"
.Leod: .asciz "\n<eod>\n"
.Lok: .ascii "ok\n"
.Lerror: .ascii "error\n"
.Lnone: .asciz "none"
.Ls_tabs: .asciz "tabs="
.Ls_active: .asciz " active="
.Ls_line: .asciz " line="
.Ls_col: .asciz " col="
.Ls_sel: .asciz " sel="
.Ls_dirty: .asciz " dirty="
.Ls_lang: .asciz " lang="
.Ls_focus: .asciz " focus="
.Ls_theme: .asciz " theme="
.Lc_key: .asciz "key"
.Lc_type: .asciz "type"
.Lc_move: .asciz "move"
.Lc_click: .asciz "click"
.Lc_down: .asciz "down"
.Lc_up: .asciz "up"
.Lc_scroll: .asciz "scroll"
.Lc_open: .asciz "open"
.Lc_cmd: .asciz "cmd"
.Lc_shot: .asciz "shot"
.Lc_wait: .asciz "wait"
.Lc_resize: .asciz "resize"
.Lc_quit: .asciz "quit"
.Lc_echo: .asciz "echo"
.Lc_print_doc: .asciz "print-doc"
.Lc_print_state: .asciz "print-state"
.Lc_print_syntax: .asciz "print-syntax"
.Lc_print_agents: .asciz "print-agents"
.Lc_xkey: .asciz "xkey"
.Lc_print_window: .asciz "print-window"
.Lc_print_cursor: .asciz "print-cursor"
.Ls_builtin: .asciz "built-in"
.Ls_hot: .asciz " hot "
.Ls_moves: .asciz "moves="
.Ls_maximized: .asciz " maximized="
.Ls_minimized: .asciz " minimized="
.Ls_quit: .asciz " quit="
.Ls_csd: .asciz " csd="
.Ldigits: .ascii "0123456789abcdefghijk"
.p2align 3
ctl_table:
    .quad .Lc_key, c_key, .Lc_type, c_type, .Lc_move, c_move, .Lc_click, c_click
    .quad .Lc_down, c_down, .Lc_up, c_up, .Lc_scroll, c_scroll, .Lc_open, c_open
    .quad .Lc_cmd, c_cmd, .Lc_shot, c_shot, .Lc_wait, c_wait, .Lc_resize, c_resize
    .quad .Lc_quit, c_quit, .Lc_echo, c_echo, .Lc_print_doc, c_print_doc
    .quad .Lc_print_state, c_print_state, .Lc_print_syntax, c_print_syntax, .Lc_print_agents, c_print_agents, .Lc_xkey, c_xkey
    .quad .Lc_print_window, c_print_window, .Lc_print_cursor, c_print_cursor, 0, 0

.data
lsock: .long -1
csock: .long -1
.bss
.p2align 3
pc_xc: .zero XC_SIZE
