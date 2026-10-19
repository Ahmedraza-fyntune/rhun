// Root-object anchored immutable selection publication and cleanup.
.include "mac.inc"
FN mac_ext_store_rename
    ENTER
    mov x3, x2
    mov x2, x0
    mov x4, #4                // RENAME_EXCL
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
FN mac_ext_store_unlink
    ENTER
    mov x2, #0
    bl _unlinkat
    cmn w0, #1
    b.ne 1f
    bl ___error
    ldr w0, [x0]
    bl linux_errno
    neg x0, x0
1:  sxtw x8, w0
    LEAVE
    XRET
