// Final retirement wait deliberately bypasses the Cocoa SYS_poll hook.
.include "mac.inc"
FN mac_ext_store_job_retire_wait
    ENTER
    mov x0, #0
    mov x1, #0
    mov x2, #16
    bl _poll
    sxtw x8, w0
    LEAVE
    XRET
