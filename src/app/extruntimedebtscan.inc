# Complete bounded timer census. No owner references or shared scheduling cursors.
.equ RT_debtScanDirty, 616
.equ RT_debtScanCursor, 624
.equ RT_debtScanMin, 632
.equ RT_debtScanHasDue, 640
.equ RT_debtScanActive, 648
.equ RT_debtScanValid, 656
.if RT_debtScanValid + 8 > RT_HEADER_SIZE
.error "runtime debt timer census exceeds header"
.endif
