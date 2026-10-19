# headless control commands of the workspace edits and editor model work (control.s's ctl_tables):
#   print-tx                  the workspace-edit transactions, newest first (wstx.s)
#   print-journal             their journal folders on disk (wsdisk.s)
#   ext-edits NAME yes|no     an extension's standing permission to change project files
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

.section .rodata
.p2align 3
.globl ws_ctl
ws_ctl:
    .quad .Lc_print_tx, c_print_tx, .Lc_print_journal, c_print_journal, .Lc_ext_edits, c_ext_edits
    .quad 0, 0
.Lc_print_tx: .asciz "print-tx"
.Lc_print_journal: .asciz "print-journal"
.Lc_ext_edits: .asciz "ext-edits"
.Lyes: .asciz "yes"
