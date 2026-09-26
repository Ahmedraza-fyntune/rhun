// rhun on macOS: inotify on FSEvents
.include "mac.inc"

.text
.globl sys_inotify_init1, sys_inotify_add_watch, sys_inotify_rm_watch
.p2align 2
sys_inotify_init1:
sys_inotify_add_watch:
sys_inotify_rm_watch:
    mov x0, #-38
    ret
