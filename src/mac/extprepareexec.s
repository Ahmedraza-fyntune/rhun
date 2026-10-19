// Effective UID for the managed caller-owned executable policy.
.include "mac.inc"
FN mac_prep_effective_uid
    ENTER
    bl _geteuid
    mov w8, w0
    LEAVE
    XRET
