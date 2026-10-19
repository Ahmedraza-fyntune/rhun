// Root-relative managed directory creation, separate from ordinary syscall pathname semantics.
.include "mac.inc"
FN mac_ext_mkdir_at
    ENTER
    bl _mkdirat
    cmn w0, #1
    b.ne 1f
    bl ___error
    ldr w0, [x0]
    bl linux_errno
    neg x0, x0
1:  sxtw x8, w0
    LEAVE
    XRET
