# Native isolated snapshot entry. No application initialization.
.include "rhun.inc"
.text
FN main
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    jmp ext_legacy_snapshot_anchored_main
