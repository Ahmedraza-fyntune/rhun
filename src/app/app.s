.include "rhun.inc"
.bss
.p2align 3
face_a: .zero FACE_SIZE
mx: .long 0
my: .long 0
lastkey: .long 0
lastcp: .long 0
lastmods: .long 0
.p2align 3
sb: .zero SB_SIZE
.globl font_m, font_u
font_m: .quad 0
font_u: .quad 0
.text
FN app_init
    lea rdi, [rip + font_mono]
    xor esi, esi
    call font_load
    mov [rip + font_m], rax
    lea rdi, [rip + font_ui]
    xor esi, esi
    call font_load
    mov [rip + font_u], rax
    ret
FN app_on_resize
    mov dword ptr [rip + g_dirty], 1
    ret
FN app_on_close
    mov dword ptr [rip + g_quit], 1
    ret
FN app_on_motion
    mov [rip + mx], edi
    mov [rip + my], esi
    mov dword ptr [rip + g_dirty], 1
    mov edi, CUR_TEXT
    cmp dword ptr [rip + my], 80
    jge 1f
    mov edi, CUR_DEFAULT
1:  PCALL P_cursor
    ret
FN app_on_pointer_leave
    ret
FN app_on_button
    cmp edi, BTN_LEFT
    jne 1f
    cmp esi, 1
    jne 1f
    cmp dword ptr [rip + my], 80
    jge 1f
    PCALL P_move
1:  ret
FN app_on_scroll
    ret
FN app_on_focus
    mov dword ptr [rip + g_dirty], 1
    ret
FN app_on_key
    mov [rip + lastkey], edi
    mov [rip + lastcp], esi
    mov [rip + lastmods], edx
    mov dword ptr [rip + g_dirty], 1
    cmp edi, KEY_ESCAPE
    jne 1f
    mov dword ptr [rip + g_quit], 1
1:  ret
FN app_on_paste
    ret
FN app_timeout
    mov eax, -1
    ret
FN app_tick
    ret
FN app_render
    PROLOGUE 32
    movss xmm0, [rip + g_dpi_scale]
    mulss xmm0, [rip + f15]
    cvtss2si edx, xmm0
    lea rdi, [rip + face_a]
    mov rsi, [rip + font_m]
    cmp edx, [rip + face_a + FACE_px]
    je 1f
    call face_init
1:  xor edi, edi
    xor esi, esi
    mov edx, [rip + g_cv + CV_w]
    mov ecx, [rip + g_cv + CV_h]
    mov r8d, 0xff1e2127
    call gfx_fill
    xor edi, edi
    xor esi, esi
    mov edx, [rip + g_cv + CV_w]
    mov ecx, 80
    mov r8d, 0xff16181d
    call gfx_fill
    lea rdi, [rip + sb]
    call sb_clear
    lea rdi, [rip + sb]
    lea rsi, [rip + s_key]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + lastkey]
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + s_cp]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + lastcp]
    call sb_push_utf8
    lea rdi, [rip + sb]
    lea rsi, [rip + s_mods]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + lastmods]
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + s_mouse]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + mx]
    call sb_push_u64
    lea rdi, [rip + sb]
    mov esi, ','
    call sb_push_byte
    lea rdi, [rip + sb]
    mov esi, [rip + my]
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + s_size]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + g_cv + CV_w]
    call sb_push_u64
    lea rdi, [rip + sb]
    mov esi, 'x'
    call sb_push_byte
    lea rdi, [rip + sb]
    mov esi, [rip + g_cv + CV_h]
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + s_csd]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, [rip + g_csd]
    call sb_push_u64
    lea rdi, [rip + face_a]
    mov esi, 20
    mov edx, 130
    mov rcx, [rip + sb + SB_ptr]
    mov r8, [rip + sb + SB_len]
    mov r9d, 0xffdcdfe4
    call text_draw
    mov edi, [rip + mx]
    sub edi, 6
    mov esi, [rip + my]
    sub esi, 6
    mov edx, 12
    mov ecx, 12
    mov r8d, 6
    mov r9d, 0xff61afef
    call gfx_round_rect
    lea rdi, [rip + dump]
    call shot_write
    EPILOGUE
.section .rodata
f15: .float 15.0
s_key: .asciz "key="
s_cp: .asciz " char="
s_mods: .asciz " mods="
s_mouse: .asciz "  mouse="
s_size: .asciz "  size="
s_csd: .asciz "  csd="
dump: .asciz "/tmp/claude-1000/-home-vsh-code-rhun/a5190e87-52e7-4684-9a0c-3782228f8c9e/scratchpad/wl.ppm"
