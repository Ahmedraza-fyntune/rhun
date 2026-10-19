// Root-object anchored settings replacement. No backup or inverse rename.
.include "mac.inc"
FN mac_ext_choices_replace
    ENTER
    mov x3, x2
    mov x2, x0
    mov x4, #0
    bl _renameatx_np
    cmn w0, #1
    b.ne 1f
    bl ___error
    ldr w0, [x0]
    bl linux_errno
    neg x0, x0
1:  sxtw x8, w0
    LEAVE
    XRET
