# rhun: shared macros and constants
.intel_syntax noprefix

# ---- linux x86-64 syscalls ----
.equ SYS_read, 0
.equ SYS_write, 1
.equ SYS_open, 2
.equ SYS_close, 3
.equ SYS_fstat, 5
.equ SYS_lstat, 6
.equ SYS_poll, 7
.equ SYS_lseek, 8
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_rt_sigaction, 13
.equ SYS_ioctl, 16
.equ SYS_access, 21
.equ SYS_mremap, 25
.equ SYS_shmget, 29
.equ SYS_shmat, 30
.equ SYS_shmctl, 31
.equ SYS_getpid, 39
.equ SYS_socket, 41
.equ SYS_connect, 42
.equ SYS_accept, 43
.equ SYS_sendmsg, 46
.equ SYS_recvmsg, 47
.equ SYS_bind, 49
.equ SYS_listen, 50
.equ SYS_exit, 60
.equ SYS_kill, 62
.equ SYS_fcntl, 72
.equ SYS_fsync, 74
.equ SYS_ftruncate, 77
.equ SYS_getcwd, 79
.equ SYS_rename, 82
.equ SYS_mkdir, 83
.equ SYS_unlink, 87
.equ SYS_readlink, 89
.equ SYS_fchmod, 91
.equ SYS_shmdt, 67
.equ SYS_getdents64, 217
.equ SYS_clock_gettime, 228
.equ SYS_exit_group, 231
.equ SYS_inotify_add_watch, 254
.equ SYS_inotify_rm_watch, 255
.equ SYS_openat, 257
.equ SYS_timerfd_create, 283
.equ SYS_timerfd_settime, 286
.equ SYS_accept4, 288
.equ SYS_pipe2, 293
.equ SYS_inotify_init1, 294
.equ SYS_memfd_create, 319

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_RDWR, 2
.equ O_CREAT, 0x40
.equ O_TRUNC, 0x200
.equ O_APPEND, 0x400
.equ O_NONBLOCK, 0x800
.equ O_DIRECTORY, 0x10000
.equ O_CLOEXEC, 0x80000

.equ PROT_READ, 1
.equ PROT_WRITE, 2
.equ MAP_SHARED, 1
.equ MAP_PRIVATE, 2
.equ MAP_ANONYMOUS, 0x20
.equ MREMAP_MAYMOVE, 1

.equ AF_UNIX, 1
.equ SOCK_STREAM, 1
.equ SOCK_NONBLOCK, 0x800
.equ SOCK_CLOEXEC, 0x80000
.equ SOL_SOCKET, 1
.equ SCM_RIGHTS, 1
.equ MSG_DONTWAIT, 0x40
.equ MSG_NOSIGNAL, 0x4000

.equ POLLIN, 1
.equ POLLOUT, 4
.equ POLLERR, 8
.equ POLLHUP, 16

.equ CLOCK_REALTIME, 0
.equ CLOCK_MONOTONIC, 1

.equ IN_MODIFY, 0x2
.equ IN_CLOSE_WRITE, 0x8
.equ IN_MOVED_FROM, 0x40
.equ IN_MOVED_TO, 0x80
.equ IN_CREATE, 0x100
.equ IN_DELETE, 0x200
.equ IN_ONLYDIR, 0x1000000
.equ IN_NONBLOCK, 0x800
.equ IN_CLOEXEC, 0x80000

.equ EAGAIN, 11
.equ EINTR, 4

# ---- function helpers ----
.macro FN name
    .text
    .globl \name
    .type \name, @function
    .p2align 4
\name:
.endm

# Saves rbp, rbx, r12-r15 and reserves `frame` bytes (multiple of 16) at [rsp].
.macro PROLOGUE frame=0
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8 + \frame
.endm

.macro EPILOGUE
    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.endm

.macro SYS num
    mov eax, \num
    syscall
.endm

# ---- struct layout ----
.macro STRUCT
    .set __so, 0
.endm
.macro F name, size
    .equ \name, __so
    .set __so, __so + \size
.endm
.macro ENDSTRUCT name
    .equ \name, __so
.endm

# zero-terminated string in .rodata, label = name
.macro CSTR name, text
    .section .rodata
\name: .asciz "\text"
    .text
.endm

# ---- shared structs ----

# growable byte buffer
STRUCT
F SB_ptr, 8
F SB_len, 8
F SB_cap, 8
ENDSTRUCT SB_SIZE

# generic growable array of fixed-size items
STRUCT
F VEC_ptr, 8
F VEC_len, 8
F VEC_cap, 8
ENDSTRUCT VEC_SIZE

# rectangle (i32)
STRUCT
F R_x, 4
F R_y, 4
F R_w, 4
F R_h, 4
ENDSTRUCT RECT_SIZE

# ---- key symbols (X11 keysym values; printable keys use unicode) ----
.equ KEY_BACKSPACE, 0xff08
.equ KEY_TAB, 0xff09
.equ KEY_RETURN, 0xff0d
.equ KEY_ESCAPE, 0xff1b
.equ KEY_HOME, 0xff50
.equ KEY_LEFT, 0xff51
.equ KEY_UP, 0xff52
.equ KEY_RIGHT, 0xff53
.equ KEY_DOWN, 0xff54
.equ KEY_PAGEUP, 0xff55
.equ KEY_PAGEDOWN, 0xff56
.equ KEY_END, 0xff57
.equ KEY_INSERT, 0xff63
.equ KEY_KP_ENTER, 0xff8d
.equ KEY_F1, 0xffbe
.equ KEY_SHIFT_L, 0xffe1
.equ KEY_SUPER_R, 0xffec
.equ KEY_ISO_LEFT_TAB, 0xfe20
.equ KEY_DELETE, 0xffff

.equ MOD_SHIFT, 1
.equ MOD_CTRL, 4
.equ MOD_ALT, 8
.equ MOD_SUPER, 64

# mouse buttons
.equ BTN_LEFT, 1
.equ BTN_MIDDLE, 2
.equ BTN_RIGHT, 3

# cursor shapes
.equ CUR_DEFAULT, 0
.equ CUR_TEXT, 1
.equ CUR_POINTER, 2
.equ CUR_EW, 3
.equ CUR_NS, 4
.equ CUR_NWSE, 5
.equ CUR_NESW, 6

# ---- big-endian loads (font tables) ----
.macro LDBE16 r32, r16, mem
    movzx \r32, word ptr \mem
    rol \r16, 8
.endm
.macro LDBE16S r32, r16, mem
    movzx \r32, word ptr \mem
    rol \r16, 8
    movsx \r32, \r16
.endm
.macro LDBE32 r32, mem
    mov \r32, dword ptr \mem
    bswap \r32
.endm

# ---- graphics ----
STRUCT
F CV_pixels, 8
F CV_w, 4
F CV_h, 4
F CV_stride, 4          # in pixels
F CV_cx0, 4             # clip rect [x0,x1) x [y0,y1)
F CV_cy0, 4
F CV_cx1, 4
F CV_cy1, 4
F CV_pad, 4
ENDSTRUCT CV_SIZE

# cached glyph bitmap
STRUCT
F GL_key, 4             # codepoint + 1
F GL_w, 2
F GL_h, 2
F GL_left, 2            # x offset from pen
F GL_top, 2             # rows above baseline
F GL_adv, 4             # advance, 26.6 fixed
F GL_bits, 8            # w*h alpha bytes
ENDSTRUCT GL_SIZE

# parsed TrueType font
STRUCT
F FONT_data, 8
F FONT_glyf, 8
F FONT_loca, 8
F FONT_hmtx, 8
F FONT_cmap, 8          # selected subtable
F FONT_cmapfmt, 4
F FONT_upem, 4
F FONT_localong, 4
F FONT_nglyphs, 4
F FONT_nhmetrics, 4
F FONT_ascent, 4
F FONT_descent, 4
F FONT_linegap, 4
F FONT_xheight, 4
F FONT_capheight, 4
ENDSTRUCT FONT_SIZE

# font at a pixel size
STRUCT
F FACE_font, 8
F FACE_scale, 4         # float px per unit
F FACE_px, 4            # size in px
F FACE_ascent, 4
F FACE_descent, 4
F FACE_lineh, 4
F FACE_cellw, 4         # advance of '0', px (rounded)
F FACE_tab, 8           # hash table of GL*
F FACE_tabcap, 4
F FACE_tabn, 4
F FACE_ascii, 1024  # fast path GL* for cp < 128
F FACE_embolden, 4
F FACE_pad2, 4
ENDSTRUCT FACE_SIZE
