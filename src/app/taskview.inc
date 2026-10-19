# One task output pane, owned by the native event loop. IDs never retain record pointers.
.equ TV_core, 0
.equ TV_id, 8
.equ TV_cursor, 16          # absolute raw byte position, preserved while scrolling history
.equ TV_open, 24
.equ TV_tail, 28
.equ TV_page, 32
.equ TV_suppress, 36
.equ TV_SIZE, 40
.equ TASK_VIEW_COPY, 1
.equ TASK_VIEW_STOP, 2
.equ TASK_VIEW_RESTART, 3
.equ TASK_VIEW_CLOSE, 4
.equ TASK_VIEW_HANDLED, 5
.equ TASK_VIEW_BUTTON, 0x6800
.equ TASK_VIEW_ROWS, 100
.equ TASK_VIEW_LINE, 4096
.equ TV_LONG_LEN, 17
.equ TV_DISCARD_LEN, 26
.equ TV_HIDDEN_RANGES, 25
