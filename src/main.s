.include "rhun.inc"
.bss
face_a: .zero FACE_SIZE
face_b: .zero FACE_SIZE
.text
FN main
    PROLOGUE 32
    call raster_init
    mov edi, 800*300*4
    call mem_alloc
    mov rdi, rax
    mov esi, 800
    mov edx, 300
    mov ecx, 800
    call gfx_set_target
    xor edi, edi
    xor esi, esi
    mov edx, 800
    mov ecx, 300
    mov r8d, 0xff282c34
    call gfx_fill
    mov edi, 20
    mov esi, 150
    mov edx, 300
    mov ecx, 100
    mov r8d, 10
    mov r9d, 0xff3e4451
    call gfx_round_rect
    lea rdi, [rip + font_mono]
    mov esi, 0
    call font_load
    mov rbx, rax
    lea rdi, [rip + face_a]
    mov rsi, rbx
    mov edx, 15
    call face_init
    lea rdi, [rip + face_a]
    mov esi, 20
    mov edx, 40
    lea rcx, [rip + msg]
    mov r8d, OFFSET msg_len
    mov r9d, 0xffabb2bf
    call text_draw
    lea rdi, [rip + font_ui]
    xor esi, esi
    call font_load
    lea rdi, [rip + face_b]
    mov rsi, rax
    mov edx, 13
    call face_init
    lea rdi, [rip + face_b]
    mov esi, 20
    mov edx, 80
    lea rcx, [rip + msg2]
    mov r8d, OFFSET msg2_len
    mov r9d, 0xffdcdfe4
    call text_draw
    lea rdi, [rip + face_a]
    mov esi, 40
    mov edx, 200
    lea rcx, [rip + msg]
    mov r8d, OFFSET msg_len
    mov r9d, 0xffe5c07b
    call text_draw
    lea rdi, [rip + outp]
    call shot_write
    xor eax, eax
    EPILOGUE
.section .rodata
msg: .ascii "mov rax, [rbx+8] ; {}()=>0x1F lIi|O0 \321\200\321\203\320\275 \303\251\303\274 \342\200\246"
.equ msg_len, . - msg
msg2: .ascii "Explorer  Agents  Settings \342\200\224 rhun editor (Ubuntu Sans)"
.equ msg2_len, . - msg2
outp: .asciz "/tmp/claude-1000/-home-vsh-code-rhun/a5190e87-52e7-4684-9a0c-3782228f8c9e/scratchpad/t1.ppm"
