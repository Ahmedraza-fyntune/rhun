# A single checked close. The owning host or keeper retains its disposition.
.include "rhun.inc"
.text
FN ext_fd_close_checked
.ifdef WINDOWS
    jmp win_ext_fd_close_checked
.else
    jmp ext_root_close
.endif
