.include "rhun.inc"
.bss
sigact: .zero 32
.text
FN main
    PROLOGUE
    # ignore SIGPIPE
    mov qword ptr [rip + sigact], 1
    mov edi, 13
    lea rsi, [rip + sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    call raster_init
    call app_init
    call wl_connect
    test eax, eax
    jnz 1f
    lea rdi, [rip + nowl]
    call die
1:  lea rdi, [rip + title]
    call wl_open_window
    call loop_run
    xor eax, eax
    EPILOGUE
.section .rodata
title: .asciz "rhun"
nowl: .asciz "no wayland"
