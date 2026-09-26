# entry: arguments, platform selection, main loop
#   rhun [PATH...] [--headless WxH] [--scale F] [--script FILE] [--control SOCKET]
.include "rhun.inc"

.bss
.p2align 3
sigact: .zero 32
opt_headless: .long 0
.p2align 3
opt_script: .quad 0
opt_control: .quad 0
paths: .zero VEC_SIZE
cwd: .zero 4096

.data
opt_w: .long 1280
opt_h: .long 800
.text
FN main
    PROLOGUE 16
    # ignore SIGPIPE
    mov qword ptr [rip + sigact], 1
    mov edi, 13
    lea rsi, [rip + sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    call parse_args
    call raster_init
    call app_init
    cmp dword ptr [rip + opt_headless], 0
    jne .Lm_headless
    call wl_connect
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Lno_display]
    call die
1:  lea rdi, [rip + .Ltitle]
    call wl_open_window
    jmp .Lm_open
.Lm_headless:
    mov edi, [rip + opt_w]
    mov esi, [rip + opt_h]
    call headless_init
.Lm_open:
    call open_initial
    mov rdi, [rip + opt_control]
    test rdi, rdi
    jz 2f
    call control_listen
2:  mov rdi, [rip + opt_script]
    test rdi, rdi
    jz 3f
    call control_run_script
    jmp .Lm_exit
3:  call loop_run
.Lm_exit:
    cmp dword ptr [rip + g_settings_changed], 0
    je 4f
    call config_save
4:  xor eax, eax
    EPILOGUE

parse_args:
    PROLOGUE
    mov r12, [rip + g_argv]
    mov r13, [rip + g_argc]
    mov ebx, 1
.Lpa_next:
    cmp rbx, r13
    jae .Lpa_done
    mov r14, [r12 + rbx*8]
    mov rdi, r14
    lea rsi, [rip + .Lo_headless]
    call strcmp_eq
    test eax, eax
    jz 1f
    mov dword ptr [rip + opt_headless], 1
    inc rbx
    cmp rbx, r13
    jae .Lpa_done
    mov rdi, [r12 + rbx*8]
    call parse_size
    jmp 9f
1:  mov rdi, r14
    lea rsi, [rip + .Lo_script]
    call strcmp_eq
    test eax, eax
    jz 2f
    inc rbx
    mov rax, [r12 + rbx*8]
    mov [rip + opt_script], rax
    jmp 9f
2:  mov rdi, r14
    lea rsi, [rip + .Lo_control]
    call strcmp_eq
    test eax, eax
    jz 3f
    inc rbx
    mov rax, [r12 + rbx*8]
    mov [rip + opt_control], rax
    jmp 9f
3:  mov rdi, r14
    lea rsi, [rip + .Lo_scale]
    call strcmp_eq
    test eax, eax
    jz 4f
    inc rbx
    mov rdi, [r12 + rbx*8]
    call strlen
    mov rdi, [r12 + rbx*8]
    mov rsi, rax
    call parse_decimal
    cvtsi2ss xmm0, eax
    divss xmm0, [rip + .Lf100]
    movss [rip + g_dpi_scale], xmm0
    jmp 9f
4:  lea rdi, [rip + paths]
    mov esi, 8
    call vec_push
    mov [rax], r14
9:  inc rbx
    jmp .Lpa_next
.Lpa_done:
    EPILOGUE

# "WxH"
parse_size:
    push rbx
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call parse_u64
    mov [rip + opt_w], eax
    lea rdi, [rbx + rdx + 1]
    push rdi
    call strlen
    pop rdi
    mov rsi, rax
    call parse_u64
    mov [rip + opt_h], eax
    pop rbx
    ret

# open_initial(): project folder and files from the command line
open_initial:
    PROLOGUE
    xor r12d, r12d              # got a directory
    xor ebx, ebx
1:  cmp rbx, [rip + paths + VEC_len]
    jae 2f
    mov rax, [rip + paths + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call file_is_dir
    test eax, eax
    jz 11f
    mov r12d, 1
11: inc rbx
    jmp 1b
2:  test r12d, r12d
    jnz 3f
    # no folder given: the current directory is the project
    lea rdi, [rip + cwd]
    mov esi, 4096
    SYS SYS_getcwd
    test rax, rax
    js 3f
    lea rdi, [rip + cwd]
    call app_set_project
3:  xor ebx, ebx
4:  cmp rbx, [rip + paths + VEC_len]
    jae 5f
    mov rax, [rip + paths + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call app_open_path
    inc rbx
    jmp 4b
5:  # nothing opened: bring back the last session
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    jne 6f
    call session_restore
6:  call app_update_title
    EPILOGUE

.section .rodata
.Ltitle: .asciz "rhun"
.Lno_display: .asciz "rhun: no Wayland display (WAYLAND_DISPLAY), use --headless"
.Lo_headless: .asciz "--headless"
.Lo_script: .asciz "--script"
.Lo_control: .asciz "--control"
.Lo_scale: .asciz "--scale"
.p2align 2
.Lf100: .float 100.0
