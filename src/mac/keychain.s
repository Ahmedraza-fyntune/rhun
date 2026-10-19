// rhun on macOS: extensions' secrets in the login keychain (src/app/secrets.s). Generic
// passwords, service "rhun extension OWNER/NAME", account KEY. A request runs on a dispatch queue,
// because the keychain may show its own unlock or access dialog; the worker writes a byte to the
// request's pipe when it is done and secrets_done answers it on the main thread. Items are tied
// to rhun's code signature: a Developer ID release keeps its access across updates, an ad hoc
// local build may be asked again after a rebuild.
.include "mac.inc"

// the secret request's fields (SR_* in src/rhun.inc)
.equ SR_op, 0
.equ SR_status, 4
.equ SR_fd, 8
.equ SR_service, 16
.equ SR_key, 24
.equ SR_val, 32
.equ SR_len, 40
.equ SR_outlen, 48
.equ SR_buf, 88
.equ SECRET_BUF, 12288
.equ SECRET_VALUE_MAX, 8192
.equ SECRET_KEYS_MAX, 64
.equ SO_GET, 1
.equ SO_SET, 2
.equ SO_DELETE, 3
.equ SO_KEYS, 4
.equ SO_CLEAR, 5
.equ SS_OK, 0
.equ SS_NONE, 1
.equ SS_REFUSED, -1
.equ SS_TOOBIG, -3
.equ ERR_NOT_FOUND, -25300          // errSecItemNotFound
.equ UTF8, 0x08000100               // kCFStringEncodingUTF8

// the value of a global CF constant, and its address
.macro GOTVAL reg, sym
    adrp \reg, \sym@GOTPAGE
    ldr \reg, [\reg, \sym@GOTPAGEOFF]
    ldr \reg, [\reg]
.endm
.macro GOTADR reg, sym
    adrp \reg, \sym@GOTPAGE
    ldr \reg, [\reg, \sym@GOTPAGEOFF]
.endm

// mac_secret_start(sr): the request goes to a background queue (called from translated code)
FN mac_secret_start
    ENTER
    mov x19, x0
    mov x0, #0
    mov x1, #0
    bl _dispatch_get_global_queue
    mov x1, x19
    ADR x2, kc_worker
    bl _dispatch_async_f
    LEAVE
    XRET

// kc_worker(sr): on a dispatch thread, plain AAPCS
.p2align 2
kc_worker:
    ENTER 1184
    mov x19, x0
    str xzr, [x19, #SR_outlen]
    mov w9, #SS_REFUSED
    str w9, [x19, #SR_status]
    // no keychain folder in this HOME (a test's own HOME): the keychain is not asked, because it
    // would wait for a "keychain not found" dialog
    mov x20, #0
    mov x21, #0
    ADR x0, s_home
    bl _getenv
    cbz x0, 0f
    mov x22, x0
    bl _strlen
    cmp x0, #900
    b.hs 0f
    mov x2, x0
    mov x23, x0
    add x0, sp, #160
    mov x1, x22
    bl _memcpy
    add x0, sp, #160
    add x0, x0, x23
    ADR x1, s_keychains
    bl _strcpy
    add x0, sp, #160
    mov w1, #0
    bl _access
    cbz w0, 01f
0:  mov w9, #-2                     // SS_NOSTORE
    str w9, [x19, #SR_status]
    b 9f
01:
    // the service and the account as CFStrings
    mov x0, #0
    ldr x1, [x19, #SR_service]
    mov w2, #(UTF8 & 0xffff)
    movk w2, #(UTF8 >> 16), lsl #16
    bl _CFStringCreateWithCString
    mov x20, x0                     // service
    mov x21, #0                     // account
    ldr x1, [x19, #SR_key]
    cbz x1, 1f
    mov x0, #0
    mov w2, #(UTF8 & 0xffff)
    movk w2, #(UTF8 >> 16), lsl #16
    bl _CFStringCreateWithCString
    mov x21, x0
1:  cbz x20, 9f
    ldr w9, [x19, #SR_op]
    cmp w9, #SO_GET
    b.eq kc_get
    cmp w9, #SO_SET
    b.eq kc_set
    cmp w9, #SO_DELETE
    b.eq kc_delete
    cmp w9, #SO_KEYS
    b.eq kc_keys
    cmp w9, #SO_CLEAR
    b.eq kc_clear
    b 8f

// get: the item's data into SR_buf
kc_get:
    mov w3, #2
    GOTVAL x9, _kSecReturnData
    GOTVAL x10, _kCFBooleanTrue
    stp x9, x10, [sp]
    GOTVAL x9, _kSecMatchLimit
    GOTVAL x10, _kSecMatchLimitOne
    stp x9, x10, [sp, #16]
    bl kc_query
    mov x22, x0
    add x1, sp, #64
    str xzr, [x1]
    bl _SecItemCopyMatching
    mov w23, w0
    mov x0, x22
    bl _CFRelease
    cmp w23, #0
    b.eq 2f
    mov w10, #(ERR_NOT_FOUND & 0xffff)
    movk w10, #0xffff, lsl #16
    cmp w23, w10
    b.ne 8f
    mov w9, #SS_NONE
    str w9, [x19, #SR_status]
    b 8f
2:  ldr x22, [sp, #64]
    mov x0, x22
    bl _CFDataGetLength
    mov x23, x0
    cmp x23, #SECRET_VALUE_MAX
    b.ls 3f
    mov x23, #SECRET_VALUE_MAX
3:  mov x0, x22
    bl _CFDataGetBytePtr
    mov x1, x0
    add x0, x19, #SR_buf
    mov x2, x23
    bl _memcpy
    str x23, [x19, #SR_outlen]
    mov x0, x22
    bl _CFRelease
    str wzr, [x19, #SR_status]
    b 8f

// set: update the item, or add it while the extension has fewer than SECRET_KEYS_MAX
kc_set:
    mov x0, #0
    ldr x1, [x19, #SR_val]
    ldr x2, [x19, #SR_len]
    bl _CFDataCreate
    mov x24, x0                     // the data
    cbz x24, 8f
    // update: attributes {kSecValueData: data}
    GOTVAL x9, _kSecValueData
    stp x9, x24, [sp, #96]
    mov x0, #0
    add x1, sp, #96
    add x2, sp, #104
    mov x3, #1
    GOTADR x4, _kCFTypeDictionaryKeyCallBacks
    GOTADR x5, _kCFTypeDictionaryValueCallBacks
    bl _CFDictionaryCreate
    mov x25, x0
    mov w3, #0
    bl kc_query
    mov x22, x0
    mov x1, x25
    bl _SecItemUpdate
    mov w23, w0
    mov x0, x22
    bl _CFRelease
    mov x0, x25
    bl _CFRelease
    cbz w23, 5f
    mov w10, #(ERR_NOT_FOUND & 0xffff)
    movk w10, #0xffff, lsl #16
    cmp w23, w10
    b.ne 6f
    // a new key: how many it has
    bl kc_count
    cmp x0, #SECRET_KEYS_MAX
    b.lo 4f
    mov w9, #SS_TOOBIG
    str w9, [x19, #SR_status]
    b 6f
4:  GOTVAL x9, _kSecValueData
    stp x9, x24, [sp]
    GOTVAL x9, _kSecAttrLabel
    stp x9, x20, [sp, #16]
    mov w3, #2
    bl kc_query
    mov x22, x0
    mov x1, #0
    bl _SecItemAdd
    mov w23, w0
    mov x0, x22
    bl _CFRelease
    cbnz w23, 6f
5:  str wzr, [x19, #SR_status]
6:  mov x0, x24
    bl _CFRelease
    b 8f

// delete: gone, or never there
kc_delete:
    mov w3, #0
    bl kc_query
    mov x22, x0
    bl _SecItemDelete
    mov w23, w0
    mov x0, x22
    bl _CFRelease
    cbz w23, 1f
    mov w10, #(ERR_NOT_FOUND & 0xffff)
    movk w10, #0xffff, lsl #16
    cmp w23, w10
    b.ne 8f
1:  str wzr, [x19, #SR_status]
    b 8f

// clear: every item of the service (SecItemDelete again until none is left)
kc_clear:
    mov x26, #0
1:  mov w3, #0
    bl kc_query
    mov x22, x0
    bl _SecItemDelete
    mov w23, w0
    mov x0, x22
    bl _CFRelease
    add x26, x26, #1
    cmp x26, #(SECRET_KEYS_MAX + 8)
    b.hs 2f
    cbz w23, 1b
    mov w10, #(ERR_NOT_FOUND & 0xffff)
    movk w10, #0xffff, lsl #16
    cmp w23, w10
    b.ne 8f
2:  str wzr, [x19, #SR_status]
    b 8f

// keys: each item's account, followed by LF
kc_keys:
    str wzr, [x19, #SR_status]
    bl kc_list
    mov x22, x0
    cbz x22, 7f
    mov x0, x22
    bl _CFArrayGetCount
    mov x24, x0
    mov x25, #0
1:  cmp x25, x24
    b.hs 6f
    mov x0, x22
    mov x1, x25
    add x25, x25, #1
    bl _CFArrayGetValueAtIndex
    GOTVAL x1, _kSecAttrAccount
    bl _CFDictionaryGetValue
    cbz x0, 1b
    ldr x9, [x19, #SR_outlen]
    mov x10, #(SECRET_BUF - 2)
    sub x2, x10, x9
    cmp x2, #8
    b.lt 6f
    add x1, x19, #SR_buf
    add x1, x1, x9
    mov w3, #(UTF8 & 0xffff)
    movk w3, #(UTF8 >> 16), lsl #16
    bl _CFStringGetCString
    cbz w0, 1b
    ldr x9, [x19, #SR_outlen]
    add x0, x19, #SR_buf
    add x0, x0, x9
    bl _strlen
    ldr x9, [x19, #SR_outlen]
    add x9, x9, x0
    add x10, x19, #SR_buf
    mov w11, #10
    strb w11, [x10, x9]
    add x9, x9, #1
    str x9, [x19, #SR_outlen]
    b 1b
6:  mov x0, x22
    bl _CFRelease
7:  b 8f

8:  // done: the strings go, and the main thread hears of it
    cbz x20, 81f
    mov x0, x20
    bl _CFRelease
81: cbz x21, 9f
    mov x0, x21
    bl _CFRelease
9:  strb wzr, [sp, #128]
    ldr w0, [x19, #SR_fd]
    add x1, sp, #128
    mov x2, #1
    bl _write
    LEAVE
    ret

// kc_query(w3 extra pairs at [sp of the caller]..) -> x0 a CFDictionary: the class, the service
// (x20), the account (x21, when there is one) and the w3 extra key/value pairs the caller put at
// its [sp], [sp + 16]
.p2align 2
kc_query:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #96
    // keys at [sp], values at [sp + 48]
    add x12, x29, #16               // the caller's sp
    GOTVAL x9, _kSecClass
    GOTVAL x10, _kSecClassGenericPassword
    str x9, [sp]
    str x10, [sp, #48]
    GOTVAL x9, _kSecAttrService
    str x9, [sp, #8]
    str x20, [sp, #56]
    mov x11, #2
    cbz x21, 1f
    GOTVAL x9, _kSecAttrAccount
    str x9, [sp, #16]
    str x21, [sp, #64]
    mov x11, #3
1:  mov x13, #0
2:  cmp w13, w3
    b.hs 3f
    add x14, x12, x13, lsl #4
    ldp x9, x10, [x14]
    str x9, [sp, x11, lsl #3]
    add x14, sp, #48
    str x10, [x14, x11, lsl #3]
    add x11, x11, #1
    add x13, x13, #1
    b 2b
3:  mov x0, #0
    mov x1, sp
    add x2, sp, #48
    mov x3, x11
    GOTADR x4, _kCFTypeDictionaryKeyCallBacks
    GOTADR x5, _kCFTypeDictionaryValueCallBacks
    bl _CFDictionaryCreate
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

// kc_list() -> x0 a CFArray of the service's items' attributes, or 0 (none, or refused: then
// SR_status says so)
.p2align 2
kc_list:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #64
    stp x21, x22, [sp, #48]
    mov x21, #0                     // no account: all of them
    GOTVAL x9, _kSecReturnAttributes
    GOTVAL x10, _kCFBooleanTrue
    stp x9, x10, [sp]
    GOTVAL x9, _kSecMatchLimit
    GOTVAL x10, _kSecMatchLimitAll
    stp x9, x10, [sp, #16]
    mov w3, #2
    bl kc_query
    mov x22, x0
    add x1, sp, #32
    str xzr, [x1]
    bl _SecItemCopyMatching
    mov w9, w0
    mov x0, x22
    str w9, [sp, #40]
    bl _CFRelease
    ldr w9, [sp, #40]
    ldr x0, [sp, #32]
    cbz w9, 9f
    mov x0, #0
    mov w10, #(ERR_NOT_FOUND & 0xffff)
    movk w10, #0xffff, lsl #16
    cmp w9, w10
    b.eq 9f
    mov w9, #SS_REFUSED             // not a list: refused
    str w9, [x19, #SR_status]
    ldp x21, x22, [sp, #48]
    mov sp, x29
    ldp x29, x30, [sp], #16
    mov x0, #0
    ret
9:  ldp x21, x22, [sp, #48]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

// kc_count() -> x0 how many items the service has
.p2align 2
kc_count:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    str x22, [sp]
    bl kc_list
    mov x22, x0
    mov x0, #0
    cbz x22, 9f
    mov x0, x22
    bl _CFArrayGetCount
    str x0, [sp, #8]
    mov x0, x22
    bl _CFRelease
    ldr x0, [sp, #8]
9:  ldr x22, [sp]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret

.section __TEXT,__cstring,cstring_literals
s_home: .asciz "HOME"
s_keychains: .asciz "/Library/Keychains"
