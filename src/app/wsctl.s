# headless control commands of the workspace edits and editor model work (control.s's ctl_tables):
#   print-tx                  the workspace-edit transactions, newest first (wstx.s)
#   print-journal             their journal folders on disk (wsdisk.s)
#   ext-edits NAME yes|no     an extension's standing permission to change project files
#   print-linked              linked editing's session: "linked=N" and its ranges, or "linked=none"
#   print-selections          multi-cursor: "sels=N", then "L1 C1 L2 C2" a selection (anchor,
#                             cursor; lines and byte columns from 1), the primary first
#   drag X1 Y1 X2 Y2 [MODS]   multi-cursor: the left button pressed at X1 Y1 with the modifiers
#                             (alt, shift+alt, ...), moved to X2 Y2 over two frames, released there
.include "rhun.inc"

.text

# each fn(out sb, rest, rest len) -> rax 0

c_print_tx:
    call tx_print
    xor eax, eax
    ret

c_print_journal:
    call ws_journal_print
    xor eax, eax
    ret

c_print_linked:
    call ws_linked_print
    xor eax, eax
    ret

c_ext_edits:
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    mov rdi, rbx
    mov rsi, r12
    call next_word
    mov r13, rax                # the name
    mov r14, rdx
    add rbx, rcx
    sub r12, rcx
    mov rdi, rbx
    mov rsi, r12
    call trim
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lyes]
    call str_eq_cstr
    mov r15d, eax
    mov rdi, r13
    mov rsi, r14
    call ext_by_name
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, r15d
    call ext_set_edits
9:  xor eax, eax
    EPILOGUE

# ---- multi-cursor ----

c_print_selections:
    sub rsp, 8
    mov rsi, rdi
    mov rdi, [rip + g_doc]
    call sel_dump
    add rsp, 8
    xor eax, eax
    ret

c_drag:
    PROLOGUE 48
    mov [rsp], rsi              # the rest of the line
    mov [rsp + 8], rdx
    xor ebx, ebx
1:  lea rdi, [rsp]
    call wsc_int
    mov [rsp + 16 + rbx*4], eax # x1 y1 x2 y2
    inc ebx
    cmp ebx, 4
    jb 1b
    mov dword ptr [rsp + 32], 0
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call next_word
    test rdx, rdx
    jz 2f
    mov rdi, rax
    mov rsi, rdx
    call parse_combo
    mov [rsp + 32], edx
2:  mov edi, [rsp + 16]
    mov esi, [rsp + 20]
    call app_on_motion
    call wsc_flush
    mov edi, BTN_LEFT
    mov esi, 1
    mov edx, [rsp + 32]
    call app_on_button
    call wsc_flush
    mov edi, [rsp + 16]
    add edi, [rsp + 24]
    sar edi, 1
    mov esi, [rsp + 20]
    add esi, [rsp + 28]
    sar esi, 1
    call app_on_motion
    call wsc_flush
    mov edi, [rsp + 24]
    mov esi, [rsp + 28]
    call app_on_motion
    call wsc_flush
    # released, unless a window move took the pointer (headless records that)
    cmp dword ptr [rip + g_hl_grab], 0
    je 3f
    mov dword ptr [rip + g_hl_grab], 0
    jmp 4f
3:  mov edi, BTN_LEFT
    xor esi, esi
    mov edx, [rsp + 32]
    call app_on_button
4:  xor eax, eax
    EPILOGUE

# wsc_int(rest*) -> eax the next number of the rest {pointer, length}, which moves past it
wsc_int:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    call next_word
    add [rbx], rcx
    sub [rbx + 8], rcx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    EPILOGUE

# wsc_flush(): the frame the input asked for, drawn now (headless draws synchronously)
wsc_flush:
.ifndef WINDOWS
    cmp dword ptr [rip + g_headless], 0
    je 1f
.endif
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

.section .rodata
.p2align 3
.globl ws_ctl
ws_ctl:
    .quad .Lc_print_tx, c_print_tx, .Lc_print_journal, c_print_journal, .Lc_ext_edits, c_ext_edits
    .quad .Lc_print_selections, c_print_selections, .Lc_drag, c_drag   # multi-cursor
    .quad .Lc_print_linked, c_print_linked
    .quad 0, 0
.Lc_print_tx: .asciz "print-tx"
.Lc_print_journal: .asciz "print-journal"
.Lc_ext_edits: .asciz "ext-edits"
.Lyes: .asciz "yes"
.Lc_print_selections: .asciz "print-selections"
.Lc_drag: .asciz "drag"
.Lc_print_linked: .asciz "print-linked"
