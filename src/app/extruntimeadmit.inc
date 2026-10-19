# Response ownership is separate from ticket and native channel lifetime.
.equ RTRSP_OK, 0
.equ RTRSP_INVALID, 1
.equ RTRSP_BUSY, 2
.equ RTRSP_OOM, 3
.equ RTRSP_TOOBIG, 4
.equ RTRSP_NAME, 5
.equ RTRSP_NOT_RUNTIME, 6
.equ RTRSP_UNSUPPORTED, 7
.equ RTRSP_CATALOG, 8
.equ RTRSP_CANCELLED, 9
.equ RTDEL_NONE, 0
.equ RTDEL_WAIT, 1
.equ RTDEL_QUEUED, 2
.equ RTDEL_ABANDONED, 3
.equ RTT_TERMINAL_ERROR, 3
.equ RT_STOP_DUPLICATE_ID, 1
