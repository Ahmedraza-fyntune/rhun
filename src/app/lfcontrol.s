# Headless control commands of the language features (--script and --control; control.s looks
# them up in langfeat_ctl): print-langstats, print-provides, print-query and the ones later stages
# add. Each writes its answer into the control's output buffer.
.include "rhun.inc"

.bss
.p2align 3
lc_out: .quad 0                 # the SB the answer goes to
lc_rest: .quad 0                # the rest of the line after the command's name
lc_rlen: .quad 0

.text

# LCWRAP: a table entry fn(out, rest, rest len) that keeps them for lc_arg, then runs the command
.macro LCWRAP name, target
\name:
    mov [rip + lc_out], rdi
    mov [rip + lc_rest], rsi
    mov [rip + lc_rlen], rdx
    sub rsp, 8
    call \target
    add rsp, 8
    xor eax, eax
    ret
.endm
    LCWRAP w_print_langstats, c_print_langstats
    LCWRAP w_print_provides, c_print_provides
    LCWRAP w_print_query, c_print_query

# lc_arg() -> rax ptr, rdx len of the next word of the rest (rdx 0 at its end)
lc_arg:
    mov rax, [rip + lc_rest]
    mov rcx, [rip + lc_rlen]
1:  test rcx, rcx
    jz 3f
    cmp byte ptr [rax], ' '
    jne 2f
    inc rax
    dec rcx
    jmp 1b
2:  xor edx, edx
21: cmp rdx, rcx
    jae 22f
    cmp byte ptr [rax + rdx], ' '
    je 22f
    inc rdx
    jmp 21b
22: lea r8, [rax + rdx]
    mov [rip + lc_rest], r8
    sub rcx, rdx
    mov [rip + lc_rlen], rcx
    ret
3:  mov [rip + lc_rest], rax
    mov qword ptr [rip + lc_rlen], 0
    xor edx, edx
    ret

# lc_ext() -> rax the EXT named by the next word, or 0 (and "no such extension" in the answer)
lc_ext:
    push rbx
    call lc_arg
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jnz 9f
8:  mov rdi, [rip + lc_out]
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
9:  pop rbx
    ret

# print-langstats [OWNER/NAME]: each kind an extension was asked, with its numbers (query.s)
c_print_langstats:
    push rbx
    call lc_arg
    xor esi, esi
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    mov rsi, rax
    test rax, rax
    jnz 1f
    mov rdi, [rip + lc_out]
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    pop rbx
    ret
1:  mov rdi, [rip + lc_out]
    call query_dump_stats
    pop rbx
    ret

# print-provides OWNER/NAME: its [provides] values in force, "KEY = VALUES" each
c_print_provides:
    push rbx
    call lc_ext
    test rax, rax
    jz 9f
    mov rsi, rax
    mov rdi, [rip + lc_out]
    call query_dump_provides
9:  pop rbx
    ret

# print-query: the requests rhun waits on, with their progress
c_print_query:
    push rbx
    mov rdi, [rip + lc_out]
    call query_dump_pending
    pop rbx
    ret

.section .rodata
.Lno_ext: .asciz "no such extension\n"
.Lc_print_langstats: .asciz "print-langstats"
.Lc_print_provides: .asciz "print-provides"
.Lc_print_query: .asciz "print-query"
.p2align 3
.globl langfeat_ctl
langfeat_ctl:
    .quad .Lc_print_langstats, w_print_langstats
    .quad .Lc_print_provides, w_print_provides
    .quad .Lc_print_query, w_print_query
    .quad 0, 0
