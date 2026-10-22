// Private pasteboard fixture. No reads or writes to the desktop clipboard.
.include "mac.inc"
.section __TEXT,__const
fixture_unicode: .ascii "a\303\251\346\260\264\360\237\230\200"
.equ fixture_unicode_len, .-fixture_unicode
fixture_nul: .ascii "a\000b\303\251\346\260\264\360\237\230\200"
.equ fixture_nul_len, .-fixture_nul
fixture_empty: .byte 0
fixture_ok: .ascii "ok mac counted clipboard read\n"
.equ fixture_ok_len, .-fixture_ok
fixture_bad: .ascii "FAIL mac counted clipboard read stage "
.equ fixture_bad_len, .-fixture_bad

.text
.macro TMSG name
    adrp x1, fixture_sel_\name@PAGE
    ldr x1, [x1, fixture_sel_\name@PAGEOFF]
    bl _objc_msgSend
.endm
.macro STAGE n
    ADR x9, fixture_stage
    mov x10, #\n
    str x10, [x9]
.endm
.macro CHECK ptr, len, limit, accepted=1
    mov x0, x19
    mov x1, #\limit
    ADR x2, \ptr
    mov x3, #\len
    mov x4, #\accepted
    bl fixture_check
.endm

// AAPCS helper: board, bytes, count -> accepted.
fixture_write:
    ENTER
    mov x19, x0
    mov x20, x1
    mov x21, x2
    ADR x0, fixture_nsstring
    bl _objc_getClass
    TMSG alloc
    mov x2, x20
    mov x3, x21
    mov x4, #4
    TMSG init
    cbz x0, fixture_failed
    mov x20, x0
    mov x0, x19
    TMSG clear
    mov x0, x19
    mov x2, x20
    adrp x3, _NSPasteboardTypeString@GOTPAGE
    ldr x3, [x3, _NSPasteboardTypeString@GOTPAGEOFF]
    ldr x3, [x3]
    TMSG set_string
    mov x21, x0
    mov x0, x20
    TMSG release
    mov x0, x21
    LEAVE
    ret

// AAPCS helper: board, limit, expected bytes, count, accepted.
fixture_check:
    ENTER 64
    str x2, [sp]
    str x3, [sp, #8]
    str x4, [sp, #16]
    ADR x9, g_mem_live
    ldr x9, [x9]
    str x9, [sp, #40]
    mov x19, #19
    mov x20, #20
    mov x21, #21
    mov x22, #22
    mov x23, #23
    mov x24, #24
    XCALL mac_clip_read
    str x8, [sp, #24]
    str x2, [sp, #32]
    cmp x19, #19
    b.ne fixture_failed
    cmp x20, #20
    b.ne fixture_failed
    cmp x21, #21
    b.ne fixture_failed
    cmp x22, #22
    b.ne fixture_failed
    cmp x23, #23
    b.ne fixture_failed
    cmp x24, #24
    b.ne fixture_failed
    ldr x9, [sp, #16]
    cbz x9, 2f
    cbz x8, fixture_failed
    ldr x9, [sp, #8]
    cmp x2, x9
    b.ne fixture_failed
    ldrb w10, [x8, x2]
    cbnz w10, fixture_failed
    mov x0, x8
    ldr x1, [sp]
    XCALL memeq
    cbz x8, fixture_failed
    ldr x0, [sp, #24]
    XCALL mem_free
    b 3f
2:  cbnz x8, fixture_failed
    cbnz x2, fixture_failed
3:  ADR x9, g_mem_live
    ldr x9, [x9]
    ldr x10, [sp, #40]
    cmp x9, x10
    b.ne fixture_failed
    LEAVE
    ret

FN main
    ENTER 64
    bl _objc_autoreleasePoolPush
    mov x20, x0
    ADR x0, fixture_nspasteboard
    bl _objc_getClass
    TMSG unique
    cbz x0, fixture_failed
    mov x19, x0
    ADR x9, g_mem_live
    ldr x21, [x9]
    STAGE 1
    mov x0, x19
    TMSG clear
    CHECK fixture_empty, 0, 64, 0
    STAGE 2
    mov x0, x19
    ADR x1, fixture_unicode
    mov x2, #fixture_unicode_len
    bl fixture_write
    cbz x0, fixture_failed
    CHECK fixture_unicode, fixture_unicode_len, 64
    CHECK fixture_unicode, fixture_unicode_len, fixture_unicode_len
    CHECK fixture_empty, 0, fixture_unicode_len-1, 0
    CHECK fixture_empty, 0, 0, 0
    STAGE 3
    mov x0, x19
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    bl fixture_write
    cbz x0, fixture_failed
    CHECK fixture_nul, fixture_nul_len, 64
    mov x0, x19
    mov x1, #64
    XCALL mac_clip_read
    cbz x8, fixture_failed
    mov x23, x8
    STAGE 4
    mov x0, x19
    ADR x1, fixture_empty
    mov x2, #0
    bl fixture_write
    cbz x0, fixture_failed
    CHECK fixture_empty, 0, 0
    CHECK fixture_empty, 0, 64
    mov x0, x23
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    XCALL memeq
    cbz x8, fixture_failed
    mov x0, x23
    XCALL mem_free
    STAGE 5
    mov x0, x19
    mov x1, #-1
    ADR x2, fixture_empty
    mov x3, #0
    mov x4, #0
    bl fixture_check
    mov x0, x19
    mov x1, #64 << 20
    add x1, x1, #1
    ADR x2, fixture_empty
    mov x3, #0
    mov x4, #0
    bl fixture_check
    mov x0, #0
    mov x1, #64
    ADR x2, fixture_empty
    mov x3, #0
    mov x4, #0
    bl fixture_check
    STAGE 6
    mov x0, #131072
    XCALL mem_alloc
    mov x24, x8
    mov x0, x24
    mov x1, #'x'
    mov x2, #131072
    XCALL memset
    mov x0, x19
    mov x1, x24
    mov x2, #131072
    bl fixture_write
    cbz x0, fixture_failed
    mov x0, x19
    mov x1, #131072
    mov x2, x24
    mov x3, #131072
    mov x4, #1
    bl fixture_check
    mov x0, x24
    XCALL mem_free
    ADR x9, g_mem_live
    ldr x9, [x9]
    cmp x9, x21
    b.ne fixture_failed

    // Production delivery path, real editor dispatch and document history.
    STAGE 7
    mov x0, #320
    mov x1, #200
    XCALL headless_init
    ADR x9, g_focus
    str wzr, [x9]               // FOCUS_EDITOR
    ADR x9, cfg_vim
    str wzr, [x9]
    ADR x9, g_vim_mode
    str wzr, [x9]
    ADR x9, g_vim_cmdline
    str wzr, [x9]
    ADR x9, g_mem_live
    ldr x9, [x9]
    str x9, [sp, #48]
    XCALL doc_new
    mov x23, x8
    ADR x9, g_doc
    str x23, [x9]
    mov x0, x19
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    bl fixture_write
    cbz x0, fixture_failed
    mov x0, x19
    XCALL mac_clip_paste_board
    mov x0, x23
    XCALL doc_len
    mov x9, #fixture_nul_len
    cmp x8, x9
    b.ne fixture_failed
    mov x0, x23
    mov x1, #0
    mov x2, #fixture_nul_len
    mov x3, sp
    XCALL doc_copy
    mov x0, sp
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    XCALL memeq
    cbz x8, fixture_failed
    mov x0, x23
    XCALL doc_undo
    mov x0, x23
    XCALL doc_len
    cbnz x8, fixture_failed
    mov x0, x23
    XCALL doc_redo
    mov x0, x23
    XCALL doc_len
    mov x9, #fixture_nul_len
    cmp x8, x9
    b.ne fixture_failed
    mov x0, x23
    XCALL doc_free
    ADR x9, g_doc
    str xzr, [x9]
    ADR x9, g_mem_live
    ldr x9, [x9]
    ldr x10, [sp, #48]
    cmp x9, x10
    b.ne fixture_failed

    STAGE 8
    XCALL doc_new
    mov x23, x8
    ADR x9, g_doc
    str x23, [x9]
    ADR x0, fixture_unicode
    mov x1, #fixture_unicode_len
    mov x2, #1
    XCALL ed_clip_set           // headless backend, desktop clipboard untouched
    cbz x8, fixture_failed
    ADR x9, g_mem_live
    ldr x21, [x9]
    mov x0, x19
    TMSG clear
    mov x0, x19
    XCALL mac_clip_paste_board
    ADR x9, g_clip_line
    ldr w9, [x9]
    cmp w9, #1                 // missing data did not call app_on_paste
    b.ne fixture_failed
    ADR x9, g_mem_live
    ldr x9, [x9]
    cmp x9, x21
    b.ne fixture_failed
    STAGE 9
    mov x0, x19
    ADR x1, fixture_empty
    mov x2, #0
    bl fixture_write
    cbz x0, fixture_failed
    mov x0, x19
    XCALL mac_clip_paste_board
    ADR x9, g_clip_line
    ldr w9, [x9]
    cbnz w9, fixture_failed     // accepted empty called the observation hook
    mov x0, x23
    XCALL doc_len
    cbnz x8, fixture_failed
    ADR x9, g_mem_live
    ldr x9, [x9]
    cmp x9, x21
    b.ne fixture_failed
    mov x0, x23
    XCALL doc_free
    ADR x9, g_doc
    str xzr, [x9]

    // Tagged queue delivery uses only this private board, including empty/missing recovery.
    STAGE 10
    ADR x9, fixture_board
    str x19, [x9]
    ADR x9, g_plat
    ldr x10, [x9, #48]          // P_clip_get
    ADR x11, fixture_old_get
    str x10, [x11]
    ADR x10, fixture_tagged_get
    str x10, [x9, #48]
    ADR x9, g_mem_live
    ldr x24, [x9]
    XCALL doc_new
    mov x23, x8
    ADR x9, g_doc
    str x23, [x9]
    mov x0, x19
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    bl fixture_write
    cbz x0, fixture_failed
    XCALL app_clip_request
    cbz x8, fixture_failed
    ADR x9, app_clip_active_token
    ldr x9, [x9]
    cbnz x9, fixture_failed
    mov x0, x23
    XCALL doc_len
    mov x9, #fixture_nul_len
    cmp x8, x9
    b.ne fixture_failed
    mov x0, x23
    mov x1, #0
    mov x2, #fixture_nul_len
    mov x3, sp
    XCALL doc_copy
    mov x0, sp
    ADR x1, fixture_nul
    mov x2, #fixture_nul_len
    XCALL memeq
    cbz x8, fixture_failed
    mov x0, x19
    TMSG clear
    XCALL app_clip_request       // missing must release the active request
    cbz x8, fixture_failed
    ADR x9, app_clip_active_token
    ldr x9, [x9]
    cbnz x9, fixture_failed
    mov x0, x19
    ADR x1, fixture_empty
    mov x2, #0
    bl fixture_write
    cbz x0, fixture_failed
    XCALL app_clip_request       // valid empty is a no-op with no history entry
    cbz x8, fixture_failed
    XCALL app_clip_timeout
    cmn w8, #1
    b.ne fixture_failed
    mov x0, x23
    XCALL doc_undo
    mov x0, x23
    XCALL doc_len
    cbnz x8, fixture_failed
    mov x0, x23
    XCALL doc_redo
    mov x0, x23
    XCALL doc_len
    mov x9, #fixture_nul_len
    cmp x8, x9
    b.ne fixture_failed
    ADR x9, fixture_old_get
    ldr x10, [x9]
    ADR x9, g_plat
    str x10, [x9, #48]
    mov x0, x23
    XCALL doc_free
    ADR x9, g_doc
    str xzr, [x9]
    ADR x9, g_mem_live
    ldr x9, [x9]
    cmp x9, x24
    b.ne fixture_failed
    mov x0, x19
    TMSG release_global
    mov x0, x20
    bl _objc_autoreleasePoolPop
    ADR x0, fixture_ok
    mov x1, #fixture_ok_len
    XCALL log_write
    mov x8, #0
    LEAVE
    XRET

// Native callback with the translated ABI used by the platform vtable.
FN fixture_tagged_get
    ENTER
    ADR x9, fixture_board
    ldr x0, [x9]
    ADR x9, app_clip_active_token
    ldr x1, [x9]
    XCALL mac_clip_paste_board_tagged
    LEAVE
    XRET

fixture_failed:
    ADR x0, fixture_bad
    mov x1, #fixture_bad_len
    XCALL log_write
    ADR x9, fixture_stage
    ldr x0, [x9]
    XCALL log_u64
    mov w0, #1
    bl _exit

.bss
.p2align 3
fixture_stage: .quad 0
fixture_board: .quad 0
fixture_old_get: .quad 0
.section __TEXT,__cstring,cstring_literals
fixture_nsstring: .asciz "NSString"
fixture_nspasteboard: .asciz "NSPasteboard"
.macro TSEL name, value
    .section __TEXT,__objc_methname,cstring_literals
fixture_name_\name: .asciz "\value"
    .section __DATA,__objc_selrefs,literal_pointers,no_dead_strip
    .p2align 3
fixture_sel_\name: .quad fixture_name_\name
.endm
TSEL alloc, "alloc"
TSEL init, "initWithBytes:length:encoding:"
TSEL clear, "clearContents"
TSEL set_string, "setString:forType:"
TSEL release, "release"
TSEL unique, "pasteboardWithUniqueName"
TSEL release_global, "releaseGlobally"
.section __DATA,__objc_imageinfo,regular,no_dead_strip
.long 0, 64
