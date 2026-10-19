# Additive runtime row maintenance fields. No reply/session retry fields are shared.
.equ RT_debtCursor, 592
.equ RT_nativeCursor, 600
.equ RT_revokeCursor, 608
.equ RTR_debtBackoff, RTR_acceptSequence
.equ RTR_debtDue, RTR_slotNext
.equ RTB_QUIESCING, 1
.equ RTB_PUBLISHING, 2
.if RT_revokeCursor + 8 > RT_HEADER_SIZE
.error "runtime maintenance cursor span"
.endif
