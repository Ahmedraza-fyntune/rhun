// Native Darwin operations used only by the independent process keeper.
.include "mac.inc"

// kp_native_wait(pid) -> x8 1 zombie/0 alive/-errno, x2 normalized status, x4 raw status.
FN kp_native_wait
    ENTER 112
    mov w19, w0
    stp xzr, xzr, [sp]
    stp xzr, xzr, [sp, #16]
    stp xzr, xzr, [sp, #32]
    stp xzr, xzr, [sp, #48]
    stp xzr, xzr, [sp, #64]
    stp xzr, xzr, [sp, #80]
    str xzr, [sp, #96]
    mov w0, #1                 // P_PID
    mov w1, w19
    mov x2, sp
    mov w3, #0x25              // WEXITED|WNOHANG|WNOWAIT
    bl _waitid
    cbnz w0, .Lkp_wait_error
    ldr w9, [sp, #12]
    cbz w9, .Lkp_wait_alive
    ldr w4, [sp, #20]
    ldr w9, [sp, #8]
    cmp w9, #1                 // CLD_EXITED
    b.eq 1f
    add w2, w4, #128
    mov w9, #255
    cmp w2, w9
    csel w2, w2, w9, lo
    b 2f
1:  and w2, w4, #255
2:  mov x8, #1
    LEAVE
    XRET
.Lkp_wait_alive:
    mov x8, #0
    mov w2, #-1
    mov w4, #0
    LEAVE
    XRET
.Lkp_wait_error:
    bl ___error
    ldr w0, [x0]
    bl linux_errno
    neg x8, x0
    mov w2, #-1
    mov w4, #0
    LEAVE
    XRET

// Numeric membership is collected under the kernel process-list lock. Only sole anchor succeeds.
FN kp_native_group_alone
    ENTER
    mov w19, w0
    mov x20, x1
    mov w0, #2                 // PROC_PGRP_ONLY
    mov w1, w19
    mov x2, x20
    mov w3, #16388             // 4097 pid_t entries
    bl _proc_listpids
    cmp w0, #4
    b.ne 1f
    ldr w9, [x20]
    cmp w9, w19
    cset x8, eq
    LEAVE
    XRET
1:  mov x8, #0                 // zero, error, cap and all other memberships are inconclusive
    LEAVE
    XRET

// Complete post-fork FD census. No editor-owned control descriptor crosses helper/target exec.
// kp_native_closefrom(first, work1MiB) ->0/-errno.
FN kp_native_closefrom
    ENTER
    mov w19, w0
    mov x20, x1
    bl _getpid
    mov w1, #1                 // PROC_PIDLISTFDS
    mov x2, #0
    mov x3, x20
    mov w4, #0x100000
    bl _proc_pidinfo
    cmp w0, #0
    b.le .Lkp_close_bad
    tst w0, #7
    b.ne .Lkp_close_bad
    mov w21, w0
    mov w9, #0x80000            // at most65536 complete entries, plus an excess observation
    cmp w21, w9
    b.hi .Lkp_close_big
    mov w22, #0
1:  cmp w22, w21
    b.hs 4f
    ldr w23, [x20, x22]
    cmp w23, w19
    b.lt 3f
    mov w24, #3
2:  mov w0, w23
    bl _close
    cbz w0, 3f
    bl ___error
    ldr w9, [x0]
    cmp w9, #4                 // EINTR. No other thread can reuse this descriptor.
    b.ne .Lkp_close_bad
    subs w24, w24, #1
    b.ne 2b
    b .Lkp_close_bad
3:  add w22, w22, #8
    b 1b
4:  mov x8, #0
    LEAVE
    XRET
.Lkp_close_big:
    mov x8, #-75
    LEAVE
    XRET
.Lkp_close_bad:
    mov x8, #-5
    LEAVE
    XRET

// Target defaults must not inherit ignored editor signals or a blocked signal mask.
FN kp_native_reset_signals
    ENTER 32
    stp xzr, xzr, [sp]
    stp xzr, xzr, [sp, #16]
    mov w19, #1
1:  cmp w19, #9
    b.eq 2f
    cmp w19, #17                // Darwin SIGSTOP
    b.eq 2f
    mov w0, w19
    mov x1, sp
    mov x2, #0
    bl _sigaction
    cbnz w0, 8f
2:  add w19, w19, #1
    cmp w19, #32
    b.lo 1b
    mov w0, #3                 // SIG_SETMASK
    mov x1, sp
    mov x2, #0
    bl _sigprocmask
    cbnz w0, 8f
    mov x8, #0
    LEAVE
    XRET
8:  mov x8, #-5
    LEAVE
    XRET

FN kp_native_helper_init
    ENTER 32
    stp xzr, xzr, [sp]
    stp xzr, xzr, [sp, #16]
    mov w0, #20                // Darwin SIGCHLD
    mov x1, sp
    mov x2, #0
    bl _sigaction
    cbnz w0, 8f
    mov w0, #3
    mov x1, sp
    mov x2, #0
    bl _sigprocmask
    cbnz w0, 8f
    mov x8, #0
    LEAVE
    XRET
8:  mov x8, #-5
    LEAVE
    XRET
