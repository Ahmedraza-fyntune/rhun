# headless commands for Markdown rendering (markdown.s):
#   print-md WIDTH PATH   the file parsed and laid out at WIDTH: md_dump's lines
#   md-demo PATH          a panel tab "md-demo" drawing the file with md_draw (a link clicked:
#                         followed, or a toast naming it)
.include "rhun.inc"

.globl md_ctl

.data
md_ctl:
    .quad .Lc_print_md, c_print_md, .Lc_md_demo, c_md_demo
    .quad 0, 0
demo_place: .long -1

.bss
.p2align 3
demo_md: .quad 0
demo_scroll: .long 0
demo_pad: .long 0
tsb: .zero SB_SIZE

.text

# read_md(ptr, len of "PATH") -> rax a parsed document, or 0 when the file cannot be read
read_md:
    PROLOGUE
    call mem_dup
    mov rbx, rax
    mov rdi, rbx
    call vfs_read_all
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    call mem_free
    test r12, r12
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call md_new
    mov rbx, rax
    mov rdi, r12
    call mem_free
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# print-md WIDTH PATH
c_print_md:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    call parse_u64
    test rdx, rdx
    jz 8f
    mov r14, rax
    add r12, rdx
    sub r13, rdx
    cmp r13, 2
    jb 8f
    inc r12                     # the space
    dec r13
    mov rdi, r12
    mov rsi, r13
    call read_md
    test rax, rax
    jz 8f
    mov r15, rax
    mov rdi, r15
    mov esi, r14d
    call md_layout
    mov rdi, r15
    mov rsi, rbx
    call md_dump
    mov rdi, r15
    call md_free
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lnone]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# md-demo PATH
c_md_demo:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call read_md
    test rax, rax
    jz 8f
    mov r12, rax
    mov rdi, [rip + demo_md]
    call md_free
    mov [rip + demo_md], r12
    mov dword ptr [rip + demo_scroll], 0
    cmp dword ptr [rip + demo_place], -1
    jne 1f
    mov edi, PLACE_PANEL
    lea rsi, [rip + .Lname]
    lea rdx, [rip + .Ltitle]
    lea rcx, [rip + demo_ops]
    xor r8d, r8d
    call place_add
    mov [rip + demo_place], eax
1:  mov edi, [rip + demo_place]
    mov esi, 1
    call place_show
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lnone]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# demo_draw(ctx, x, y, w, h): the document with a margin, the wheel scrolls it
demo_draw:
    PROLOGUE 32
    mov r12, [rip + demo_md]
    test r12, r12
    jz 9f
    M eax, MI_16
    add esi, eax
    add edx, [rip + g_mt + 4*MI_8]
    sub ecx, eax
    sub ecx, eax
    sub r8d, [rip + g_mt + 4*MI_8]
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov rdi, r12
    mov esi, ecx
    call md_layout
    mov [rsp + 16], eax         # its height
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    mov eax, [rip + g_scroll_y]
    sub [rip + demo_scroll], eax
1:  mov eax, [rsp + 16]         # within the document
    sub eax, [rsp + 12]
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    cmp [rip + demo_scroll], eax
    jle 2f
    mov [rip + demo_scroll], eax
2:  cmp dword ptr [rip + demo_scroll], 0
    jge 3f
    mov dword ptr [rip + demo_scroll], 0
3:  mov eax, 0x5b8000           # its links' widget ids
    push rax
    push rax
    mov rdi, r12
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 8]
    mov r8d, [rsp + 16 + 12]
    mov r9d, [rip + demo_scroll]
    call md_draw
    add rsp, 16
    test eax, eax
    js 9f
    mov ebx, eax
    mov rdi, r12
    mov esi, ebx
    call md_open_link
    test eax, eax
    jnz 9f
    lea rdi, [rip + tsb]        # not one rhun follows: a toast names it
    call sb_clear
    lea rdi, [rip + tsb]
    lea rsi, [rip + .Llink]
    call sb_push_cstr
    mov rdi, r12
    mov esi, ebx
    call md_link
    lea rdi, [rip + tsb]
    mov rsi, rax
    call sb_push
    lea rdi, [rip + tsb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tsb + SB_ptr]
    call app_toast
9:  EPILOGUE

.section .rodata
.Lc_print_md: .asciz "print-md"
.Lc_md_demo: .asciz "md-demo"
.Lnone: .asciz "none\n"
.Lname: .asciz "md-demo"
.Ltitle: .asciz "Markdown"
.Llink: .asciz "link "
.p2align 3
demo_ops: .quad demo_draw, 0, 0, 0, 0, 0
