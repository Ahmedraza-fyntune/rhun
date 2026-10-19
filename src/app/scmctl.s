# headless control commands of the source control contract (control.s's ctl_tables):
#   print-git-data            extensions' Git requests still waiting (gitdata.s)
#   print-scm-ext             extension source control providers and the last row menu (scmext.s)
.include "rhun.inc"

.section .rodata
.p2align 3
.globl scm_ctl
scm_ctl:
    .quad .Lc_print_git_data, c_print_git_data, .Lc_print_scm_ext, c_print_scm_ext
    .quad 0, 0
.Lc_print_git_data: .asciz "print-git-data"
.Lc_print_scm_ext: .asciz "print-scm-ext"

.text
# each fn(out sb, rest, rest len) -> rax 0

c_print_git_data:
    sub rsp, 8
    call gitdata_dump
    add rsp, 8
    xor eax, eax
    ret

c_print_scm_ext:
    sub rsp, 8
    call scmext_dump
    add rsp, 8
    xor eax, eax
    ret
