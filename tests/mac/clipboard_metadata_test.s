// Test-only AAPCS bridge. The C caller's x28 may contain a compiler local.
.include "mac.inc"
.bss
.p2align 3
fixture_stack: .quad 0
.text
FN main
    ENTER
    ADR x9, fixture_stack
    str x28, [x9]
    ADR x9, g_argc
    ldr x0, [x9]
    ADR x9, g_argv
    ldr x1, [x9]
    bl _test_mac_clipboard_metadata
    XCALL sys_exit

// C Result call(function, arg0..arg5). Only called between completed product calls.
FN _fixture_call
    ENTER
    mov x16, x0
    mov x0, x1
    mov x1, x2
    mov x2, x3
    mov x3, x4
    mov x4, x5
    mov x5, x6
    ADR x9, fixture_stack
    ldr x28, [x9]
    adr x17, 1f
    str x17, [x28, #-8]!
    blr x16
1:  mov x0, x8
    mov x1, x2
    LEAVE
    ret

// Product callbacks stay in native assembly and use the currently active x28.
FN fixture_private_write
    ENTER
    mov x2, x1
    mov x1, x0
    ADR x9, _test_clip_board
    ldr x0, [x9]
    XCALL mac_clip_write_board
    LEAVE
    XRET
FN fixture_private_get
    ENTER
    ADR x9, app_clip_active_token
    ldr x1, [x9]
    ADR x9, _test_clip_board
    ldr x0, [x9]
    XCALL mac_clip_paste_board_tagged
    LEAVE
    XRET
FN fixture_accept
    mov x8, #1
    XRET
FN fixture_hold
    XRET

.macro PROBE_SAVED
    cmp x19, #19
    b.ne 2f
    cmp x20, #20
    b.ne 2f
    cmp x21, #21
    b.ne 2f
    cmp x22, #22
    b.ne 2f
    cmp x23, #23
    b.ne 2f
    cmp x24, #24
    b.ne 2f
    cmp x28, x25
    b.ne 2f
    b 3f
2:  mov x8, #-1
3:
.endm
.macro PROBE_INIT
    mov x19, #19
    mov x20, #20
    mov x21, #21
    mov x22, #22
    mov x23, #23
    mov x24, #24
    mov x25, x28
.endm
FN fixture_probe_read
    ENTER
    PROBE_INIT
    XCALL mac_clip_read_native
    PROBE_SAVED
    LEAVE
    XRET
FN fixture_probe_write
    ENTER
    PROBE_INIT
    XCALL mac_clip_write_board
    PROBE_SAVED
    LEAVE
    XRET
