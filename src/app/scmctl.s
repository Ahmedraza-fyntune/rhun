# headless control commands of the source control contract (control.s's ctl_tables):
#   print-git-data            extensions' Git requests still waiting (gitdata.s)
#   print-scm-ext             extension source control providers, the last row menu, and the
#                             version control panels with their tree rows (scmext.s, scmpanel.s)
#   scm-click SCM GROUP PATH  a click on a panel's resource
#   scm-action SCM N          panel button N (from 0)
#   scm-menu SCM GROUP [PATH] a group's or resource's menu (then menu-pick)
#   scm-focus SCM             the panel's message box gets the keyboard (then type)
#   print-vcs PATH            "vcs=LETTER dir=0|1 color=RRGGBB" as the explorer colors the path
#   wait-scm SCM [TEXT]       until panel SCM has an update whose status line holds TEXT (15 s at most)
#   wait-quickdiff            until no document waits for a quick-diff base (15 s at most)
.include "rhun.inc"

.bss
.p2align 3
id_buf: .zero 4200

.section .rodata
.p2align 3
.globl scm_ctl
scm_ctl:
    .quad .Lc_print_git_data, c_print_git_data, .Lc_print_scm_ext, c_print_scm_ext
    .quad .Lc_scm_click, c_scm_click, .Lc_scm_action, c_scm_action, .Lc_scm_menu, c_scm_menu
    .quad .Lc_scm_focus, c_scm_focus, .Lc_print_vcs, c_print_vcs, .Lc_wait_scm, c_wait_scm
    .quad .Lc_wait_qd, c_wait_qd
    .quad 0, 0
.Lc_print_git_data: .asciz "print-git-data"
.Lc_print_scm_ext: .asciz "print-scm-ext"
.Lc_scm_click: .asciz "scm-click"
.Lc_scm_action: .asciz "scm-action"
.Lc_scm_menu: .asciz "scm-menu"
.Lc_scm_focus: .asciz "scm-focus"
.Lc_print_vcs: .asciz "print-vcs"
.Lc_wait_scm: .asciz "wait-scm"
.Lc_wait_qd: .asciz "wait-quickdiff"
.Lno: .asciz "scm: no such provider or row\n"
.Lvcs: .asciz "vcs="
.Ldir: .asciz " dir="
.Lcolor: .asciz " color="

.text
# each fn(out sb, rest, rest len) -> rax 0

c_print_git_data:
    sub rsp, 8
    call gitdata_dump
    add rsp, 8
    xor eax, eax
    ret

c_print_scm_ext:
    PROLOGUE
    mov rbx, rdi
    call scmext_dump
    mov rdi, rbx
    call scmpanel_dump
    xor eax, eax
    EPILOGUE

# word(): the next word of the rest (r13 ptr, r14 len) -> rax ptr, rdx len
word:
    mov rdi, r13
    mov rsi, r14
    call next_word
    add r13, rcx
    sub r14, rcx
    ret

# num() -> rax the next word as a number
num:
    call word
    mov rdi, rax
    mov rsi, rdx
    jmp parse_u64

# no(): "scm: no such provider or row"
no:
    mov rdi, rbx
    lea rsi, [rip + .Lno]
    jmp sb_push_cstr

c_scm_click:
    PROLOGUE 32
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    call num
    mov r15, rax
    call word
    mov [rsp], rax
    mov [rsp + 8], rdx
    call word
    mov rcx, rax
    mov r8, rdx
    mov edi, r15d
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call scmpanel_click
    test eax, eax
    jnz 9f
    call no
9:  xor eax, eax
    EPILOGUE

c_scm_action:
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    call num
    mov r15, rax
    call num
    mov edi, r15d
    mov esi, eax
    call scmpanel_action
    test eax, eax
    jnz 9f
    call no
9:  xor eax, eax
    EPILOGUE

# scm-menu SCM GROUP [PATH]: the node "gGROUP" or "rGROUP\0PATH"
c_scm_menu:
    PROLOGUE 16
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    call num
    mov r15, rax
    call word
    lea rdi, [rip + id_buf + 1]
    mov rsi, rax
    mov rcx, rdx
    cmp rcx, 64
    ja 8f
    mov r12, rdx
    rep movsb
    call word
    test rdx, rdx
    jnz 1f
    mov byte ptr [rip + id_buf], 'g'
    lea rdx, [r12 + 1]
    jmp 2f
1:  cmp rdx, 4095
    ja 8f
    mov byte ptr [rip + id_buf], 'r'
    lea rdi, [rip + id_buf + 1]
    add rdi, r12
    mov byte ptr [rdi], 0
    inc rdi
    mov rsi, rax
    mov rcx, rdx
    lea r12, [r12 + rdx + 2]
    rep movsb
    mov rdx, r12
2:  mov edi, r15d
    lea rsi, [rip + id_buf]
    call scmpanel_menu
    test eax, eax
    jnz 9f
8:  call no
9:  xor eax, eax
    EPILOGUE

c_scm_focus:
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    call num
    mov edi, eax
    call scmpanel_focus
    test eax, eax
    jnz 9f
    call no
9:  xor eax, eax
    EPILOGUE

# wait-scm SCM [TEXT]: the frames go on (extensions answer) until the panel's status holds TEXT
c_wait_scm:
    PROLOGUE 16
    mov r13, rsi
    mov r14, rdx
    call num
    mov r15, rax
    # the rest after one space is the text
    mov rdi, r13
    mov rsi, r14
    call skip_spaces_n
    mov r13, rax
    mov r14, rdx
    call time_ms
    lea rbx, [rax + 15000]
1:  mov edi, r15d
    mov rsi, r13
    mov rdx, r14
    call scmpanel_status_has
    test eax, eax
    jnz 9f
    call time_ms
    cmp rax, rbx
    jae 9f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
9:  xor eax, eax
    EPILOGUE

# wait-quickdiff
c_wait_qd:
    PROLOGUE
    call time_ms
    lea rbx, [rax + 15000]
1:  mov edi, 20
    call loop_poll
    call app_tick
    call scmext_qd_busy
    test eax, eax
    jz 9f
    call time_ms
    cmp rax, rbx
    jb 1b
9:  xor eax, eax
    EPILOGUE

# skip_spaces_n(ptr, len) -> rax, rdx without leading spaces
skip_spaces_n:
    mov rax, rdi
    mov rdx, rsi
1:  test rdx, rdx
    jz 2f
    cmp byte ptr [rax], ' '
    jne 2f
    inc rax
    dec rdx
    jmp 1b
2:  ret

# print-vcs PATH
c_print_vcs:
    PROLOGUE 16
    mov rbx, rdi
    lea rdi, [rip + id_buf]
    cmp rdx, 4095
    ja 9f
    mov rcx, rdx
    rep movsb
    mov byte ptr [rdi], 0
    lea rdi, [rip + id_buf]
    call vcs_status_of
    mov [rsp], eax
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov rdi, rbx
    lea rsi, [rip + .Lvcs]
    call sb_push_cstr
    mov esi, [rsp]
    test esi, esi
    jnz 1f
    mov esi, '-'
1:  mov rdi, rbx
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Ldir]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rsp + 4]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lcolor]
    call sb_push_cstr
    # RRGGBB
    mov r12d, [rsp + 8]
    mov r13d, 20
2:  mov eax, r12d
    mov ecx, r13d
    shr eax, cl
    and eax, 15
    lea rcx, [rip + .Lhex]
    movzx esi, byte ptr [rcx + rax]
    mov rdi, rbx
    call sb_push_byte
    sub r13d, 4
    jns 2b
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
9:  xor eax, eax
    EPILOGUE

.section .rodata
.Lhex: .ascii "0123456789abcdef"
