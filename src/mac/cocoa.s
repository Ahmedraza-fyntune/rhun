// rhun on macOS: the window (AppKit)
.include "mac.inc"

// mac_open_window(title)
FN mac_open_window
    ADR x0, Lmsg
    bl _puts
    mov w0, #1
    bl _exit

.section __TEXT,__cstring
Lmsg: .asciz "rhun: no window yet"

// x_key_test(keycode, state): X11 key injection for scripts; nothing to do here
FN x_key_test
    XRET

.data
.p2align 2
.globl g_csd, g_dpi_scale, g_win_states
g_csd: .long 1
g_dpi_scale: .float 1.0
g_win_states: .long 0           // bit0 maximized, bit1 fullscreen, bit2 activated, bit3 tiled
