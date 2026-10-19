.include "rhun.inc"
.include "app/taskcore.inc"
.include "app/taskview.inc"
.bss
.p2align 3
tvt_context: .zero TC_SIZE
tvt_view: .zero TV_SIZE
tvt_out: .zero 128
tvt_line_out: .zero 16416
tvt_large: .zero TASK_OUTPUT_MAX
tvt_pixels: .zero 640*240*4
tvt_stage: .quad 0
tvt_calls: .quad 0
tvt_fail_alloc: .quad 0
.text
.ifdef TEST_TASK_VIEW_FAULT
FN tvt_alloc
    inc qword ptr [rip + tvt_calls]
    cmp qword ptr [rip + tvt_fail_alloc], 0
    je 1f
    xor eax, eax
    ret
1:  jmp mem_alloc_try
.endif
tvt_bad:
    mov rdi, [rip + tvt_stage]
    inc edi
    call sys_exit
tvt_resolve:
    lea rdi, [rip + tvt_view]
    jmp task_view_record
tvt_cursor:
    lea rdi, [rip + tvt_view]
    mov esi, 2
    jmp task_view_cursor
tvt_show:
    lea rdi, [rip + tvt_view]
    lea rsi, [rip + tvt_context]
    mov edx, 1
    jmp task_view_show
tvt_draw:
    lea rdi, [rip + tvt_view]
    mov esi, 16
    mov edx, 16
    mov ecx, 608
    mov r8d, 208
    jmp task_view_draw
tvt_key:
    lea rdi, [rip + tvt_view]
    xor edx, edx
    jmp task_view_key
FN main
    PROLOGUE 32
    lea r12, [rip + tvt_cases]
1:  mov rsi, [r12 + 8]
    cmp rsi, -1
    je .Ltvt_model
    mov rdi, [r12]
    lea rdx, [rip + tvt_out]
    mov ecx, 128
    call task_view_sanitize
    cmp rax, [r12 + 24]
    jne tvt_bad
    lea rdi, [rip + tvt_out]
    mov rsi, [r12 + 16]
    mov rdx, rax
    call memeq
    cmp eax, 1
    jne tvt_bad
    add r12, 32
    jmp 1b
.Ltvt_model:
    inc qword ptr [rip + tvt_stage]
    # Capacity cannot split an escape or read a rejected oversized source.
    mov dword ptr [rip + tvt_out], 0x55555555
    lea rdi, [rip + tvt_control]
    mov esi, 1
    lea rdx, [rip + tvt_out]
    mov ecx, 3
    call task_view_sanitize
    cmp rax, -28
    jne tvt_bad
    cmp dword ptr [rip + tvt_out], 0x55555555
    jne tvt_bad
    mov edi, 1
    mov esi, TASK_OUTPUT_MAX + 1
    mov edx, 1
    mov ecx, 1
    call task_view_sanitize
    cmp rax, -22
    jne tvt_bad
    xor edi, edi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call task_view_sanitize
    test rax, rax
    jnz tvt_bad
    lea rdi, [rip + tvt_context]
    call task_core_init
    lea rdi, [rip + tvt_view]
    call task_view_init
    # Direct private record fixture. These static bytes are never passed to core disposal.
    mov qword ptr [rip + tvt_context + TC_records + TK_id], 1
    lea rax, [rip + tvt_lines]
    mov [rip + tvt_context + TC_records + TK_output], rax
    mov qword ptr [rip + tvt_context + TC_records + TK_length], 10
    mov qword ptr [rip + tvt_context + TC_records + TK_total], 10
    mov dword ptr [rip + tvt_context + TC_records + TK_state], TASK_RUNNING
    call tvt_show
    cmp eax, 1
    jne tvt_bad
    call tvt_cursor
    cmp rax, 8                    # six lines including trailing empty, page two
    jne tvt_bad
    lea rdi, [rip + tvt_view]
    mov rsi, -1
    call task_view_scroll
    test rax, rax
    jnz tvt_bad
    cmp dword ptr [rip + tvt_view + TV_tail], 0
    jne tvt_bad
    cmp qword ptr [rip + tvt_view + TV_cursor], 6
    jne tvt_bad
    # Retained prefix moves by two bytes, but history stays at absolute byte six.
    lea rax, [rip + tvt_lines + 2]
    mov [rip + tvt_context + TC_records + TK_output], rax
    mov qword ptr [rip + tvt_context + TC_records + TK_length], 8
    call tvt_cursor
    cmp rax, 4
    jne tvt_bad
    cmp qword ptr [rip + tvt_view + TV_cursor], 6
    jne tvt_bad
    mov esi, KEY_HOME
    call tvt_key
    cmp eax, TASK_VIEW_HANDLED
    jne tvt_bad
    cmp qword ptr [rip + tvt_view + TV_cursor], 2
    jne tvt_bad
    mov esi, KEY_PAGEUP
    call tvt_key
    cmp eax, TASK_VIEW_HANDLED
    jne tvt_bad
    mov esi, KEY_END
    call tvt_key
    cmp eax, TASK_VIEW_HANDLED
    jne tvt_bad
    cmp dword ptr [rip + tvt_view + TV_tail], 1
    jne tvt_bad
    mov esi, 's'
    mov edx, MOD_CTRL | MOD_SHIFT
    lea rdi, [rip + tvt_view]
    call task_view_key
    cmp eax, TASK_VIEW_STOP
    jne tvt_bad
    cmp rdx, 1
    jne tvt_bad
    lea rax, [rip + tvt_context]
    cmp rcx, rax
    jne tvt_bad
    lea rdi, [rip + tvt_view]
    mov esi, 's'
    mov edx, MOD_CTRL | MOD_SHIFT | MOD_ALT
    call task_view_key
    test eax, eax
    jnz tvt_bad
    inc qword ptr [rip + tvt_stage]
    # Copy owns a NUL-terminated valid UTF-8 allocation, failure owns nothing.
    mov r12, [rip + g_mem_live]
    lea rdi, [rip + tvt_view]
    call task_view_copy
    test rax, rax
    jz tvt_bad
    mov rbx, rax
    cmp rdx, 8
    jne tvt_bad
    cmp byte ptr [rax + 8], 0
    jne tvt_bad
    mov rdi, rax
    lea rsi, [rip + tvt_lines + 2]
    call memeq
    cmp eax, 1
    jne tvt_bad
    mov rdi, rbx
    call mem_free
    cmp r12, [rip + g_mem_live]
    jne tvt_bad
.ifdef TEST_TASK_VIEW_FAULT
    mov qword ptr [rip + tvt_fail_alloc], 1
    lea rdi, [rip + tvt_view]
    call task_view_copy
    test rax, rax
    jnz tvt_bad
    cmp rdx, -12
    jne tvt_bad
    cmp r12, [rip + g_mem_live]
    jne tvt_bad
    cmp qword ptr [rip + tvt_calls], 2
    jne tvt_bad
    mov qword ptr [rip + tvt_fail_alloc], 0
.endif
    # Switching selection before the old press is drawn suppresses all pane buttons.
    mov dword ptr [rip + g_active], TASK_VIEW_BUTTON + 1
    mov dword ptr [rip + g_pressed], 1 << BTN_LEFT
    mov dword ptr [rip + g_released], 1 << BTN_LEFT
    call tvt_show
    cmp dword ptr [rip + g_active], 0
    jne tvt_bad
    lea rdi, [rip + tvt_view]
    call task_view_buttons
    test eax, eax
    jnz tvt_bad
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 0
    lea rdi, [rip + tvt_view]
    call task_view_buttons
    cmp eax, 1
    jne tvt_bad
    mov dword ptr [rip + g_active], 123
    call tvt_show
    cmp dword ptr [rip + g_active], 123
    jne tvt_bad
    # Recycling a stable ID closes the pane rather than selecting its replacement.
    mov qword ptr [rip + tvt_context + TC_records + TK_id], 2
    call tvt_resolve
    test rax, rax
    jnz tvt_bad
    cmp dword ptr [rip + tvt_view + TV_open], 0
    jne tvt_bad
    mov esi, KEY_HOME
    call tvt_key
    test eax, eax
    jnz tvt_bad
    lea rdi, [rip + tvt_view]
    call task_view_copy
    test rax, rax
    jnz tvt_bad
    cmp rdx, -2
    jne tvt_bad
    inc qword ptr [rip + tvt_stage]
    # Silent terminal tasks still distinguish success, nonzero exit and launch failure.
    lea rbx, [rip + tvt_context + TC_records]
    mov dword ptr [rbx + TK_state], TASK_EXITED
    mov dword ptr [rbx + TK_exit], 0
    mov rdi, rbx
    lea rsi, [rip + tvt_out]
    mov edx, 128
    call task_view_status
    cmp rax, 8
    jne tvt_bad
    lea rdi, [rip + tvt_out]
    lea rsi, [rip + tvt_exit_zero]
    mov edx, 8
    call memeq
    cmp eax, 1
    jne tvt_bad
    mov dword ptr [rbx + TK_exit], 1
    mov rdi, rbx
    lea rsi, [rip + tvt_out]
    mov edx, 128
    call task_view_status
    cmp rax, 8
    jne tvt_bad
    cmp byte ptr [rip + tvt_out + 7], '1'
    jne tvt_bad
    mov dword ptr [rbx + TK_state], TASK_FAILED
    mov dword ptr [rbx + TK_exit], -2147483648
    mov rdi, rbx
    lea rsi, [rip + tvt_out]
    mov edx, 128
    call task_view_status
    cmp rax, 18
    jne tvt_bad
    lea rdi, [rip + tvt_out]
    lea rsi, [rip + tvt_exit_negative]
    mov edx, 18
    call memeq
    cmp eax, 1
    jne tvt_bad
    # Long lines are bounded, visibly marked before text, and consume the whole raw line.
    lea rdi, [rip + tvt_large]
    mov esi, 'A'
    mov edx, TASK_OUTPUT_MAX
    call memset
    mov byte ptr [rip + tvt_large + TASK_OUTPUT_MAX - 1], 10
    lea rax, [rip + tvt_large]
    mov [rbx + TK_output], rax
    mov qword ptr [rbx + TK_length], TASK_OUTPUT_MAX
    mov qword ptr [rbx + TK_total], TASK_OUTPUT_MAX
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + tvt_line_out]
    mov ecx, 16416
    call task_view_line
    cmp rax, TASK_VIEW_LINE + TV_LONG_LEN
    jne tvt_bad
    cmp rdx, TASK_OUTPUT_MAX
    jne tvt_bad
    lea rdi, [rip + tvt_line_out]
    lea rsi, [rip + tvt_long_marker]
    mov edx, TV_LONG_LEN
    call memeq
    cmp eax, 1
    jne tvt_bad
    cmp byte ptr [rip + tvt_line_out + TV_LONG_LEN], 'A'
    jne tvt_bad
    mov rdi, rbx
    mov esi, TASK_OUTPUT_MAX
    lea rdx, [rip + tvt_line_out]
    mov ecx, 16416
    call task_view_line
    test rax, rax
    jnz tvt_bad
    cmp rdx, -1
    jne tvt_bad
    # Worst-case retained text expands to exactly one MiB, with a separate terminator.
    lea rdi, [rip + tvt_large]
    xor esi, esi
    mov edx, TASK_OUTPUT_MAX
    call memset
    mov qword ptr [rbx + TK_id], 1
    call tvt_show
    mov r12, [rip + g_mem_live]
    lea rdi, [rip + tvt_view]
    call task_view_copy
    test rax, rax
    jz tvt_bad
    mov r13, rax
    cmp rdx, TASK_OUTPUT_MAX*4
    jne tvt_bad
    cmp dword ptr [rax], 0x3030785c
    jne tvt_bad
    cmp dword ptr [rax + TASK_OUTPUT_MAX*4 - 4], 0x3030785c
    jne tvt_bad
    cmp byte ptr [rax + TASK_OUTPUT_MAX*4], 0
    jne tvt_bad
    mov rdi, r13
    call mem_free
    cmp r12, [rip + g_mem_live]
    jne tvt_bad
    mov byte ptr [rip + tvt_line_out + 16415], 0x55
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + tvt_line_out]
    mov ecx, 16416
    call task_view_line
    cmp rax, TASK_VIEW_LINE*4 + TV_LONG_LEN
    jne tvt_bad
    cmp rdx, -1
    jne tvt_bad
    cmp byte ptr [rip + tvt_line_out + 16415], 0x55
    jne tvt_bad
    mov qword ptr [rbx + TK_length], TASK_OUTPUT_MAX + 1
.ifdef TEST_TASK_VIEW_FAULT
    mov r14, [rip + tvt_calls]
.endif
    lea rdi, [rip + tvt_view]
    call task_view_copy
    test rax, rax
    jnz tvt_bad
    cmp rdx, -22
    jne tvt_bad
.ifdef TEST_TASK_VIEW_FAULT
    cmp r14, [rip + tvt_calls]
    jne tvt_bad
.endif
    mov qword ptr [rbx + TK_length], TASK_OUTPUT_MAX
    # Actual native rendering and button press/release, without app startup side effects.
    inc qword ptr [rip + tvt_stage]
    call raster_init
    lea rdi, [rip + font_ui]
    lea rsi, [rip + font_ui_end]
    sub rsi, rdi
    call font_load
    test rax, rax
    jz tvt_bad
    lea rdi, [rip + g_face_small]
    mov rsi, rax
    mov edx, 12
    call face_init
    mov dword ptr [rip + g_mt + 4*MI_28], 28
    mov dword ptr [rip + g_mt + 4*MI_64], 64
    mov dword ptr [rip + g_mt + 4*MI_4], 4
    mov dword ptr [rip + g_mt + 4*MI_6], 6
    mov dword ptr [rip + g_mt + 4*MI_8], 8
    mov dword ptr [rip + g_mt + 4*MI_16], 16
    mov dword ptr [rip + g_theme + 4*T_BG], 0xff101010
    mov dword ptr [rip + g_theme + 4*T_PANEL], 0xff202020
    mov dword ptr [rip + g_theme + 4*T_FG], 0xffeeeeee
    mov dword ptr [rip + g_theme + 4*T_MUTED], 0xffaaaaaa
    mov dword ptr [rip + g_theme + 4*T_HOVER], 0xff404040
    lea rdi, [rip + tvt_pixels]
    mov esi, 640
    mov edx, 240
    mov ecx, 640
    call gfx_set_target
    mov qword ptr [rbx + TK_id], 1
    lea rax, [rip + tvt_label]
    mov [rbx + TK_label], rax
    lea rax, [rip + tvt_display]
    mov [rbx + TK_output], rax
    lea rcx, [rip + tvt_display_end]
    sub rcx, rax
    mov [rbx + TK_length], rcx
    mov [rbx + TK_total], rcx
    mov dword ptr [rbx + TK_state], TASK_EXITED
    mov dword ptr [rbx + TK_exit], 1
    call tvt_show
    call tvt_draw
    test eax, eax
    jnz tvt_bad
    inc qword ptr [rip + tvt_stage]
    # Drawing must contain actual glyph coverage, not only background rectangles.
    lea rax, [rip + tvt_pixels]
    mov ecx, 640*240
    xor edx, edx
90: mov esi, [rax]
    test esi, esi
    jz 91f
    cmp esi, 0xff101010
    je 91f
    cmp esi, 0xff202020
    je 91f
    inc edx
91: add rax, 4
    dec ecx
    jnz 90b
    cmp edx, 100
    jb tvt_bad
    cmp dword ptr [rip + tvt_pixels], 0
    jne tvt_bad
    cmp dword ptr [rip + tvt_pixels + (16*640 + 16)*4], 0xff202020
    jne tvt_bad
.ifdef TEST_TASK_VIEW_SHOT
    lea rdi, [rip + tvt_shot]
    call shot_write
    test rax, rax
    jnz tvt_bad
.endif
    inc qword ptr [rip + tvt_stage]
    mov dword ptr [rip + g_mx], 390
    mov dword ptr [rip + g_my], 24
    mov dword ptr [rip + g_mdown], 1 << BTN_LEFT
    mov dword ptr [rip + g_pressed], 1 << BTN_LEFT
    call tvt_draw
    test eax, eax
    jnz tvt_bad
    mov dword ptr [rip + g_mdown], 0
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 1 << BTN_LEFT
    call tvt_draw
    cmp eax, TASK_VIEW_STOP
    jne tvt_bad
    cmp rdx, 1
    jne tvt_bad
    inc qword ptr [rip + tvt_stage]
    # A still-queued press cannot arm buttons after show changes the selection.
    mov dword ptr [rip + g_released], 0
    mov dword ptr [rip + g_mdown], 1 << BTN_LEFT
    mov dword ptr [rip + g_pressed], 1 << BTN_LEFT
    call tvt_show
    call tvt_draw
    test eax, eax
    jnz tvt_bad
    mov dword ptr [rip + g_mdown], 0
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 1 << BTN_LEFT
    call tvt_draw
    test eax, eax
    jnz tvt_bad
    inc qword ptr [rip + tvt_stage]
    # Measured status width prevents controls from overwriting a large-font failure result.
    mov dword ptr [rip + g_mdown], 0
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 0
    mov dword ptr [rbx + TK_state], TASK_FAILED
    mov dword ptr [rbx + TK_exit], -2147483648
    lea rdi, [rip + tvt_pixels]
    xor esi, esi
    mov edx, 640*240*4
    call memset
    lea rdi, [rip + g_face_small]
    mov rsi, [rip + g_face_small + FACE_font]
    mov edx, 24
    call face_init
    call tvt_show
    lea rdi, [rip + tvt_view]
    mov esi, 16
    mov edx, 16
    mov ecx, 384
    mov r8d, 208
    call task_view_draw
.ifdef TEST_TASK_VIEW_SHOT
    lea rdi, [rip + tvt_shot_large]
    call shot_write
    test rax, rax
    jnz tvt_bad
.endif
    mov dword ptr [rip + g_mx], 164
    mov dword ptr [rip + g_my], 24
    mov dword ptr [rip + g_mdown], 1 << BTN_LEFT
    mov dword ptr [rip + g_pressed], 1 << BTN_LEFT
    lea rdi, [rip + tvt_view]
    mov esi, 16
    mov edx, 16
    mov ecx, 384
    mov r8d, 208
    call task_view_draw
    test eax, eax
    jnz tvt_bad
    mov dword ptr [rip + g_mdown], 0
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 1 << BTN_LEFT
    lea rdi, [rip + tvt_view]
    mov esi, 16
    mov edx, 16
    mov ecx, 384
    mov r8d, 208
    call task_view_draw
    test eax, eax
    jnz tvt_bad
    lea rdi, [rip + tvt_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.section .rodata
.p2align 3
tvt_cases:
    .quad tvt_plain, 5, tvt_plain, 5
    .quad tvt_control, 3, tvt_control_out, 12
    .quad tvt_emoji, 4, tvt_emoji, 4
    .quad tvt_bidi, 3, tvt_bidi_out, 6
    .quad tvt_arabic, 2, tvt_arabic_out, 6
    .quad tvt_deprecated, 3, tvt_deprecated_out, 6
    .quad tvt_tag, 4, tvt_tag_out, 10
    .quad tvt_grapheme, 2, tvt_grapheme_out, 6
    .quad tvt_variation, 3, tvt_variation_out, 6
    .quad tvt_surrogate, 3, tvt_invalid_out, 9
    .quad tvt_above, 4, tvt_invalid_out, 12
    .quad tvt_overlong, 3, tvt_invalid_out, 9
    .quad tvt_emoji, 3, tvt_invalid_out, 9
    .quad tvt_replacement, 3, tvt_replacement, 3
    .quad 0, -1, 0, 0
tvt_plain: .ascii "task\n"
tvt_control: .byte 0,13,127
tvt_control_out: .ascii "\\x00\\x0D\\x7F"
tvt_emoji: .byte 0xf0,0x9f,0x98,0x80
tvt_bidi: .byte 0xe2,0x80,0xae
tvt_bidi_out: .ascii "\\u202E"
tvt_surrogate: .byte 0xed,0xa0,0x80
tvt_above: .byte 0xf4,0x90,0x80,0x80
tvt_overlong: .byte 0xe0,0x80,0xaf
tvt_replacement: .byte 0xef,0xbf,0xbd
tvt_invalid_out: .byte 0xef,0xbf,0xbd,0xef,0xbf,0xbd,0xef,0xbf,0xbd,0xef,0xbf,0xbd
tvt_lines: .ascii "a\nb\nc\nd\ne\n"
tvt_ok: .asciz "ok managed task output view\n"

tvt_exit_zero: .ascii "exited 0"
tvt_exit_negative: .ascii "failed -2147483648"
tvt_long_marker: .ascii "[line truncated] "
tvt_label: .asciz "Build workspace"
tvt_display: .ascii "go build ./...\nBuild finished with errors.\nraw ANSI: "
    .byte 27
    .ascii "[31mred\n"
tvt_display_end:
tvt_shot: .asciz "/tmp/rhun-0180-task-view.ppm"

tvt_arabic: .byte 0xd8,0x9c
tvt_arabic_out: .ascii "\\u061C"
tvt_deprecated: .byte 0xe2,0x81,0xaa
tvt_deprecated_out: .ascii "\\u206A"
tvt_tag: .byte 0xf3,0xa0,0x80,0x81
tvt_tag_out: .ascii "\\U000E0001"
tvt_grapheme: .byte 0xcd,0x8f
tvt_grapheme_out: .ascii "\\u034F"
tvt_variation: .byte 0xef,0xb8,0x8f
tvt_variation_out: .ascii "\\uFE0F"

tvt_shot_large: .asciz "/tmp/rhun-0180-task-view-large.ppm"
