# Native isolated legacy source proof entry. No application initialization.
.include "rhun.inc"
.text
FN main
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    jmp ext_validate_legacy_anchored_main
