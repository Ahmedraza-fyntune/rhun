# headless control commands of the workspace edits and editor model work (control.s's ctl_tables):
#   print-tx                  the workspace-edit transactions, newest first (wstx.s)
#   print-journal             their journal folders on disk (wsdisk.s)
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

.section .rodata
.p2align 3
.globl ws_ctl
ws_ctl:
    .quad .Lc_print_tx, c_print_tx, .Lc_print_journal, c_print_journal
    .quad 0, 0
.Lc_print_tx: .asciz "print-tx"
.Lc_print_journal: .asciz "print-journal"
