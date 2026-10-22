# Next and Previous Problem (language-features.md 1.1, F8 and shift+F8): the cursor goes to the next
# (previous) diagnostic of the focused document after (before) it, wrapping around, and the hover
# card shows its message.
#
#   cmd_next_problem, cmd_prev_problem
.include "rhun.inc"

.text

# FN cmd_next_problem(), cmd_prev_problem()
FN cmd_next_problem
    mov esi, 1
    jmp step
FN cmd_prev_problem
    mov esi, -1
step:
    PROLOGUE
    mov r15d, esi
    call ed_single
    call lf_focused_doc
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rcx, [rbx + DOC_xmarks]
    test rcx, rcx
    jz 8f
    mov r12, [rbx + DOC_cur]
    mov r13, -1                 # the nearest start past the cursor in the direction
    mov r14, -1                 # and the first (or last) of all, for wrapping around
    xor ecx, ecx
1:  mov rdx, [rbx + DOC_xmarks]
    cmp rcx, [rdx + VEC_len]
    jae 5f
    imul rax, rcx, MK_SIZE
    add rax, [rdx + VEC_ptr]
    inc rcx
    mov rax, [rax + MK_start]
    test r15d, r15d
    js 3f
    # forward: the smallest start after the cursor, and the smallest of all
    cmp r14, -1
    je 21f
    cmp rax, r14
    jae 22f
21: mov r14, rax
22: cmp rax, r12
    jbe 1b
    cmp r13, -1
    je 23f
    cmp rax, r13
    jae 1b
23: mov r13, rax
    jmp 1b
3:  # backward: the largest start before the cursor, and the largest of all
    cmp r14, -1
    je 31f
    cmp rax, r14
    jbe 32f
31: mov r14, rax
32: cmp rax, r12
    jae 1b
    cmp r13, -1
    je 33f
    cmp rax, r13
    jbe 1b
33: mov r13, rax
    jmp 1b
5:  cmp r13, -1
    jne 6f
    mov r13, r14                # around
    cmp r13, -1
    je 8f
6:  mov [rbx + DOC_cur], r13
    mov [rbx + DOC_anchor], r13
    call ed_touch
    mov dword ptr [rip + g_dirty], 1
    call hovercard_at_cursor
    jmp 9f
8:  lea rdi, [rip + .Lnone]
    call app_toast
9:  EPILOGUE

.section .rodata
.Lnone: .asciz "No problems in this file"
