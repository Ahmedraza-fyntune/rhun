# Bounded plain-text task output. The caller consumes actions synchronously, before dispatch.
.include "rhun.inc"
.include "app/taskcore.inc"
.include "app/taskview.inc"
.text
FN task_view_init
    PROLOGUE
    mov rbx, rdi
    xor esi, esi
    mov edx, TV_SIZE
    call memset
    mov dword ptr [rbx + TV_page], 20
    EPILOGUE

# A selection change invalidates both an armed button and a press not drawn yet.
tv_cancel_gesture:
    mov dword ptr [rdi + TV_suppress], 1
    mov eax, [rip + g_active]
    sub eax, TASK_VIEW_BUTTON
    cmp eax, 4
    jae 1f
    mov dword ptr [rip + g_active], 0
1:  ret
FN task_view_hide
    mov dword ptr [rdi + TV_open], 0
    mov qword ptr [rdi + TV_core], 0
    mov qword ptr [rdi + TV_id], 0
    jmp tv_cancel_gesture

# resolve(view) -> retained record or0; missing IDs close the pane.
FN task_view_record
    cmp dword ptr [rdi + TV_open], 0
    je 2f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + TV_core]
    test rdi, rdi
    jz 1f
    mov rsi, [rbx + TV_id]
    call task_core_find
    test rax, rax
    jnz 9f
1:  mov rdi, rbx
    call task_view_hide
    xor eax, eax
9:  EPILOGUE
2:  xor eax, eax
    ret

# show(view,core,stableID)->bool. Root has already checked extension ownership.
FN task_view_show
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rbx
    call task_view_hide
    xor eax, eax
    test r12, r12
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call task_core_find
    test rax, rax
    jz 9f
    mov [rbx + TV_core], r12
    mov [rbx + TV_id], r13
    mov dword ptr [rbx + TV_open], 1
    mov dword ptr [rbx + TV_tail], 1
    mov qword ptr [rbx + TV_cursor], 0
    mov eax, 1
9:  EPILOGUE

# buttons(view)->bool. Do not call ui_btn while a stale selection press is pending.
FN task_view_buttons
    cmp dword ptr [rdi + TV_suppress], 0
    je 2f
    mov eax, [rip + g_mdown]
    or eax, [rip + g_pressed]
    or eax, [rip + g_released]
    test eax, 1 << BTN_LEFT
    jnz 1f
    mov dword ptr [rdi + TV_suppress], 0
2:  mov eax, 1
    ret
1:  xor eax, eax
    ret

# sanitize(raw,len,out,capacity)->length/-errno. No NUL; never writes partial encoded units.
# Reject length before touching either pointer. The maximum expansion is four times input.
FN task_view_sanitize
    cmp rsi, TASK_OUTPUT_MAX
    ja .Ltv_sanitize_invalid
    test rsi, rsi
    jz .Ltv_sanitize_empty
    test rdi, rdi
    jz .Ltv_sanitize_invalid
    test rdx, rdx
    jz .Ltv_sanitize_invalid
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor r15d, r15d
    mov qword ptr [rsp], 0
.Ltv_sanitize_loop:
    lea rdi, [rbx + r15]
    mov rsi, r12
    sub rsi, r15
    call utf8_decode
    mov [rsp + 32], rdx
    cmp edx, 1
    jne 1f
    cmp byte ptr [rbx + r15], 0x80
    jae .Ltv_replacement
1:  cmp eax, 0x10ffff
    ja .Ltv_replacement
    cmp eax, 0xd800
    jb 2f
    cmp eax, 0xdfff
    jbe .Ltv_replacement
2:  cmp eax, 10
    je .Ltv_copy_scalar
    cmp eax, 0x20
    jb .Ltv_escape_byte
    cmp eax, 0x7f
    je .Ltv_escape_byte
    cmp eax, 0x80
    jb .Ltv_copy_scalar
    cmp eax, 0xa0
    jb .Ltv_escape_unicode
    lea rsi, [rip + .Ltv_hidden]
    mov ecx, TV_HIDDEN_RANGES
3:  cmp eax, [rsi]
    jb .Ltv_copy_scalar
    cmp eax, [rsi + 4]
    jbe .Ltv_escape_unicode
    add rsi, 8
    dec ecx
    jnz 3b
.Ltv_copy_scalar:
    lea rsi, [rbx + r15]
    jmp .Ltv_emit
.Ltv_replacement:
    mov qword ptr [rsp + 32], 1
    mov dword ptr [rsp + 8], 0x00bdbfef
    lea rsi, [rsp + 8]
    mov edx, 3
    jmp .Ltv_emit
.Ltv_escape_byte:
    mov word ptr [rsp + 8], 0x785c
    mov ecx, eax
    shr ecx, 4
    and eax, 15
    lea rsi, [rip + .Ltv_hex]
    mov cl, [rsi + rcx]
    mov [rsp + 10], cl
    mov al, [rsi + rax]
    mov [rsp + 11], al
    lea rsi, [rsp + 8]
    mov edx, 4
    jmp .Ltv_emit
.Ltv_escape_unicode:
    mov word ptr [rsp + 8], 0x755c
    mov ecx, 4
    mov edx, 6
    cmp eax, 0xffff
    jbe 6f
    mov byte ptr [rsp + 9], 'U'
    mov ecx, 8
    mov edx, 10
6:  mov [rsp + 24], rdx
    lea rsi, [rip + .Ltv_hex]
7:  mov edx, eax
    and edx, 15
    mov dl, [rsi + rdx]
    mov [rsp + rcx + 9], dl
    shr eax, 4
    dec ecx
    jnz 7b
    lea rsi, [rsp + 8]
    mov rdx, [rsp + 24]
.Ltv_emit:
    mov rax, [rsp]
    add rax, rdx
    cmp rax, r14
    ja .Ltv_sanitize_full
    mov [rsp + 40], rax
    mov rdi, r13
    add rdi, [rsp]
    call memcpy
    mov rax, [rsp + 40]
    mov [rsp], rax
    add r15, [rsp + 32]
    cmp r15, r12
    jb .Ltv_sanitize_loop
    EPILOGUE
.Ltv_sanitize_full:
    mov rax, -28
    EPILOGUE
.Ltv_sanitize_invalid:
    mov rax, -22
    ret
.Ltv_sanitize_empty:
    xor eax, eax
    ret

# copy(view)->owned buffer inrax,length inrdx; failure0/negative_errno. Root always frees.
FN task_view_copy
    PROLOGUE 16
    call task_view_record
    test rax, rax
    jz .Ltv_copy_missing
    mov rbx, rax
    mov r12, [rbx + TK_length]
    cmp r12, TASK_OUTPUT_MAX
    ja .Ltv_copy_invalid
    lea rdi, [r12*4 + 1]
    mov [rsp], rdi
    call mem_alloc_try
    test rax, rax
    jz .Ltv_copy_oom
    mov r13, rax
    mov rdi, [rbx + TK_output]
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rsp]
    dec rcx
    call task_view_sanitize
    test rax, rax
    js .Ltv_copy_bad
    mov byte ptr [r13 + rax], 0
    mov rdx, rax
    mov rax, r13
    EPILOGUE
.Ltv_copy_bad:
    mov [rsp + 8], rax
    mov rdi, r13
    call mem_free
    mov rdx, [rsp + 8]
    xor eax, eax
    EPILOGUE
.Ltv_copy_oom:
    mov rdx, -12
    jmp .Ltv_copy_no
.Ltv_copy_invalid:
    mov rdx, -22
    jmp .Ltv_copy_no
.Ltv_copy_missing:
    mov rdx, -2
.Ltv_copy_no:
    xor eax, eax
    EPILOGUE

# cursor(view,pageRows)->retained-relative raw offset/-ENOENT, rdx record.
# Two bounded passes at most: first choose the desired line, then find its byte position.
FN task_view_cursor
    PROLOGUE 32
    mov rbx, rdi
    cmp esi, 1
    jge 1f
    mov esi, 1
1:  cmp esi, TASK_VIEW_ROWS
    jle 2f
    mov esi, TASK_VIEW_ROWS
2:  mov [rbx + TV_page], esi
    call task_view_record
    test rax, rax
    jz .Ltv_cursor_missing
    mov r12, rax
    mov r13, [r12 + TK_output]
    mov r14, [r12 + TK_length]
    cmp r14, TASK_OUTPUT_MAX
    ja .Ltv_cursor_missing
    mov r15, [r12 + TK_total]
    sub r15, r14                  # absolute start of retained raw bytes
    mov [rsp], r15
    cmp dword ptr [rbx + TV_tail], 0
    je .Ltv_cursor_manual
    xor ecx, ecx
    mov edx, 1                    # empty and trailing-empty lines count
3:  cmp rcx, r14
    jae 4f
    cmp byte ptr [r13 + rcx], 10
    jne 31f
    inc edx
31: inc rcx
    jmp 3b
4:  sub edx, [rbx + TV_page]
    jns 5f
    xor edx, edx
5:  xor eax, eax
    xor ecx, ecx
6:  test edx, edx
    jz .Ltv_cursor_commit
    cmp rcx, r14
    jae .Ltv_cursor_commit
    cmp byte ptr [r13 + rcx], 10
    jne 61f
    dec edx
    lea rax, [rcx + 1]
61: inc rcx
    jmp 6b
.Ltv_cursor_manual:
    mov rcx, [rbx + TV_cursor]
    sub rcx, r15
    jb 7f
    cmp rcx, r14
    jbe 8f
    mov rcx, r14
8:  # Find the first logical boundary at or after the preserved cursor.
    xor eax, eax
    test rcx, rcx
    jz .Ltv_cursor_commit
    xor edx, edx
81: cmp rdx, r14
    jae .Ltv_cursor_commit
    cmp byte ptr [r13 + rdx], 10
    jne 82f
    lea rax, [rdx + 1]
    cmp rax, rcx
    jae .Ltv_cursor_commit
82: inc rdx
    jmp 81b
7:  xor eax, eax
.Ltv_cursor_commit:
    add r15, rax
    mov [rbx + TV_cursor], r15
    mov rdx, r12
    EPILOGUE
.Ltv_cursor_missing:
    mov rax, -2
    xor edx, edx
    EPILOGUE

# scroll(view,signedRows), negative is up. Only End/Show resume follow-tail.
FN task_view_scroll
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov esi, [rbx + TV_page]
    call task_view_cursor
    test rax, rax
    js 9f
    test r12, r12
    jz 8f
    mov dword ptr [rbx + TV_tail], 0
    # Limit signed arithmetic and scan work before considering an extreme wheel delta.
    mov rcx, TASK_OUTPUT_MAX
    cmp r12, rcx
    cmovg r12, rcx
    mov rcx, -TASK_OUTPUT_MAX
    cmp r12, rcx
    cmovl r12, rcx
    mov r13, [rdx + TK_output]
    mov r14, [rdx + TK_length]
    mov r15, [rdx + TK_total]
    sub r15, r14
    mov [rsp], rax
    xor ecx, ecx
    xor esi, esi
1:  cmp rcx, rax
    jae 2f
    cmp byte ptr [r13 + rcx], 10
    jne 11f
    inc esi
11: inc rcx
    jmp 1b
2:  add r12, rsi                  # desired zero-based line, clamped at either end
    test r12, r12
    jns 3f
    xor r12d, r12d
3:  xor eax, eax
    xor ecx, ecx
4:  test r12, r12
    jz 7f
    cmp rcx, r14
    jae 7f
    cmp byte ptr [r13 + rcx], 10
    jne 5f
    dec r12
    lea rax, [rcx + 1]
5:  inc rcx
    jmp 4b
7:  add rax, r15
    mov [rbx + TV_cursor], rax
8:  xor eax, eax
9:  EPILOGUE

# key(view,key,mods)->action (0 unhandled,5 handled navigation), rdxID/rcxcore for1..4.
FN task_view_key
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    call task_view_record
    test rax, rax
    jz .Ltv_key_unhandled
    test r13d, r13d
    jnz .Ltv_key_modified
    cmp r12d, KEY_ESCAPE
    je .Ltv_key_close
    cmp r12d, KEY_HOME
    je .Ltv_key_home
    cmp r12d, KEY_END
    je .Ltv_key_end
    cmp r12d, KEY_PAGEUP
    je .Ltv_key_up
    cmp r12d, KEY_PAGEDOWN
    je .Ltv_key_down
    jmp .Ltv_key_unhandled
.Ltv_key_modified:
    cmp r13d, MOD_CTRL
    jne 1f
    or r12d, 0x20
    cmp r12d, 'c'
    jne .Ltv_key_unhandled
    mov eax, TASK_VIEW_COPY
    jmp .Ltv_key_action
1:  cmp r13d, MOD_CTRL | MOD_SHIFT
    jne .Ltv_key_unhandled
    or r12d, 0x20
    cmp r12d, 's'
    je .Ltv_key_stop
    cmp r12d, 'r'
    jne .Ltv_key_unhandled
    mov eax, TASK_VIEW_RESTART
    jmp .Ltv_key_action
.Ltv_key_stop:
    mov eax, TASK_VIEW_STOP
    jmp .Ltv_key_action
.Ltv_key_close:
    mov eax, TASK_VIEW_CLOSE
.Ltv_key_action:
    mov rdx, [rbx + TV_id]
    mov rcx, [rbx + TV_core]
    EPILOGUE
.Ltv_key_home:
    mov dword ptr [rbx + TV_tail], 0
    mov rcx, [rax + TK_total]
    sub rcx, [rax + TK_length]
    mov [rbx + TV_cursor], rcx
    jmp .Ltv_key_handled
.Ltv_key_end:
    mov dword ptr [rbx + TV_tail], 1
    jmp .Ltv_key_handled
.Ltv_key_up:
    movsxd rsi, dword ptr [rbx + TV_page]
    neg rsi
    jmp 2f
.Ltv_key_down:
    movsxd rsi, dword ptr [rbx + TV_page]
2:  mov rdi, rbx
    call task_view_scroll
.Ltv_key_handled:
    mov eax, TASK_VIEW_HANDLED
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltv_key_unhandled:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

.section .rodata
.Ltv_hex: .ascii "0123456789ABCDEF"
.text
# line(record,rawOffset,out,capacity)->sanitized length/-errno, rdxnextOffset or-1.
FN task_view_line
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, [rbx + TK_length]
    cmp r15, TASK_OUTPUT_MAX
    ja .Ltv_line_invalid
    cmp r12, r15
    ja .Ltv_line_invalid
    mov rax, [rbx + TK_output]
    mov [rsp + 24], rax
    test r15, r15
    jz 1f
    test rax, rax
    jz .Ltv_line_invalid
1:  mov rcx, r12
2:  cmp rcx, r15
    jae 3f
    cmp byte ptr [rax + rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov qword ptr [rsp], -1
    cmp rcx, r15
    jae 4f
    lea rdx, [rcx + 1]
    mov [rsp], rdx
4:  sub rcx, r12
    mov [rsp + 8], rcx
    cmp rcx, TASK_VIEW_LINE
    jbe 5f
    mov ecx, TASK_VIEW_LINE
5:  mov rdi, [rsp + 24]
    add rdi, r12
    mov rsi, rcx
    mov rdx, r13
    mov rcx, r14
    call task_view_sanitize
    test rax, rax
    js .Ltv_line_bad
    cmp qword ptr [rsp + 8], TASK_VIEW_LINE
    jbe 6f
    mov [rsp + 16], rax
    lea rdx, [rax + TV_LONG_LEN]
    cmp rdx, r14
    ja .Ltv_line_full
    lea rdi, [r13 + TV_LONG_LEN]
    mov rsi, r13
    mov rdx, [rsp + 16]
    call memmove
    mov rdi, r13
    lea rsi, [rip + .Ltv_long]
    mov edx, TV_LONG_LEN
    call memcpy
    mov rax, [rsp + 16]
    add rax, TV_LONG_LEN
6:  mov rdx, [rsp]
    EPILOGUE
.Ltv_line_full:
    mov rax, -28
    jmp .Ltv_line_bad
.Ltv_line_invalid:
    mov rax, -22
.Ltv_line_bad:
    mov rdx, -1
    EPILOGUE

# status(record,out,capacity>=32)->length/-ENOSPC. Terminal results are signed32.
FN task_view_status
    cmp rdx, 32
    jb 9f
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + TK_state]
    test eax, eax
    jz 1f
    cmp eax, TASK_FAILED
    ja 1f
    dec eax
    lea rcx, [rip + .Ltv_states]
    mov r13, [rcx + rax*8]
    jmp 2f
1:  lea r13, [rip + .Ltv_unknown]
2:  mov rdi, r13
    call strlen
    mov r14, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, rax
    call memcpy
    cmp dword ptr [rbx + TK_state], TASK_EXITED
    jb 8f
    mov byte ptr [r12 + r14], ' '
    inc r14
    movsxd rsi, dword ptr [rbx + TK_exit]
    test rsi, rsi
    jns 3f
    mov byte ptr [r12 + r14], '-'
    inc r14
    neg rsi
3:  lea rdi, [r12 + r14]
    call fmt_u64
    add r14, rax
8:  mov rax, r14
    EPILOGUE
9:  mov rax, -28
    ret

# tv_button(view,index,x,y,w,h)->action 0..4. Caller clips to pane.
tv_button:
    PROLOGUE 32
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov [rsp + 8], r8d
    mov [rsp + 12], r9d
    mov dword ptr [rsp + 16], 0
    call task_view_buttons
    test eax, eax
    jz 1f
    lea edi, [r12 + TASK_VIEW_BUTTON]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call ui_btn
    mov [rsp + 16], eax
1:  test dword ptr [rsp + 16], UB_HOVER
    jz 2f
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_HOVER
    call gfx_fill
2:  lea rax, [rip + .Ltv_buttons]
    mov r13, [rax + r12*8]
    mov rdi, r13
    call strlen
    mov r8, rax
    mov ecx, [rsp + 12]
    sub ecx, [rip + g_face_small + FACE_ascent]
    sub ecx, [rip + g_face_small + FACE_descent]
    sar ecx, 1
    add ecx, [rsp + 4]
    add ecx, [rip + g_face_small + FACE_ascent]
    mov edx, ecx
    mov esi, [rsp]
    M eax, MI_6
    add esi, eax
    mov ecx, [rsp + 8]
    sub ecx, eax
    sub ecx, eax
    push rcx
    push rcx
    mov rcx, r13
    lea rdi, [rip + g_face_small]
    COLOR r9d, T_FG
    call text_draw_fit
    add rsp, 16
    xor eax, eax
    test dword ptr [rsp + 16], UB_CLICK
    jz 3f
    lea rax, [rip + .Ltv_actions]
    mov eax, [rax + r12*4]
3:  EPILOGUE

# draw(view,x,y,w,h)->action 0..4,rdxstableID/rcxcore. No events dispatched internally.
FN task_view_draw
    PROLOGUE 16608
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov qword ptr [rsp + 32], 0
    test ecx, ecx
    jle .Ltv_draw_return
    test r8d, r8d
    jle .Ltv_draw_return
    call task_view_record
    test rax, rax
    jz .Ltv_draw_return
    mov [rsp + 48], rax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_BG
    call gfx_fill
    M eax, MI_28
    cmp eax, 1
    jge 1f
    mov eax, 1
1:  mov [rsp + 20], eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, eax
    COLOR r8d, T_PANEL
    call gfx_fill
    mov eax, [rip + g_face_small + FACE_ascent]
    add eax, [rip + g_face_small + FACE_descent]
    add eax, [rip + g_mt + 4*MI_4]
    cmp eax, 1
    jge 2f
    mov eax, 1
2:  mov [rsp + 16], eax
    # Header state/result comes first, so long task labels cannot hide failure.
    mov rdi, [rsp + 48]
    lea rsi, [rsp + 128]
    mov edx, 32
    call task_view_status
    mov r15, rax
    mov edi, [rsp + 20]
    sub edi, [rip + g_face_small + FACE_ascent]
    sub edi, [rip + g_face_small + FACE_descent]
    sar edi, 1
    add edi, [rsp + 4]
    add edi, [rip + g_face_small + FACE_ascent]
    mov [rsp + 36], edi
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 36]
    lea rcx, [rsp + 128]
    mov r8, r15
    COLOR r9d, T_FG
    call text_draw
    mov [rsp + 40], eax
    # Hide buttons together on a narrow pane; focused keyboard actions remain available.
    M r14d, MI_64
    cmp r14d, 1
    jge 3f
    mov r14d, 1
3:  mov eax, r14d
    imul eax, 4
    neg eax
    add eax, [rsp]
    add eax, [rsp + 8]
    mov edx, [rsp + 40]
    add edx, [rip + g_mt + 4*MI_16]
    cmp edx, eax
    jg .Ltv_draw_label
    xor r12d, r12d
4:  mov eax, r14d
    imul eax, 4
    mov r13d, [rsp]
    add r13d, [rsp + 8]
    sub r13d, eax
    mov eax, r12d
    imul eax, r14d
    add r13d, eax
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    mov ecx, [rsp + 4]
    mov r8d, r14d
    mov r9d, [rsp + 20]
    call tv_button
    test eax, eax
    jz 5f
    mov [rsp + 32], eax
5:  inc r12d
    cmp r12d, 4
    jb 4b
    # label right limit is the start of the first button.
    mov eax, r14d
    imul eax, 4
    neg eax
    add eax, [rsp + 8]
    jmp 6f
.Ltv_draw_label:
    mov eax, [rsp + 8]
6:  add eax, [rsp]
    sub eax, [rsp + 40]
    sub eax, [rip + g_mt + 4*MI_16]
    test eax, eax
    jle .Ltv_draw_body
    mov [rsp + 44], eax
    mov rax, [rsp + 48]
    mov r13, [rax + TK_label]
    test r13, r13
    jz .Ltv_draw_body
    mov rdi, r13
    call strlen
    mov r8, rax
    mov eax, [rsp + 44]
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 56]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 52]
    mov rcx, r13
    COLOR r9d, T_MUTED
    call text_draw_fit
    add rsp, 16
.Ltv_draw_body:
    mov eax, [rsp + 12]
    sub eax, [rsp + 20]
    test eax, eax
    jle .Ltv_draw_pop
    xor edx, edx
    div dword ptr [rsp + 16]
    cmp eax, TASK_VIEW_ROWS
    jbe 7f
    mov eax, TASK_VIEW_ROWS
7:  mov [rsp + 24], eax
    test eax, eax
    jz .Ltv_draw_pop
    mov rdi, [rsp + 48]
    mov rax, [rdi + TK_total]
    sub rax, [rdi + TK_length]
    mov [rsp + 88], rax
    mov esi, [rsp + 24]
    test rax, rax
    jz 8f
    dec esi
8:  mov rdi, rbx
    call task_view_cursor
    test rax, rax
    js .Ltv_draw_pop
    mov r15, rax
    mov r13, rdx
    mov eax, [rsp + 4]
    add eax, [rsp + 20]
    add eax, [rip + g_face_small + FACE_ascent]
    mov [rsp + 36], eax
    xor r12d, r12d
    cmp qword ptr [rsp + 88], 0
    je .Ltv_draw_row
    lea rcx, [rip + .Ltv_discard]
    mov r8d, TV_DISCARD_LEN
    jmp .Ltv_draw_text
.Ltv_draw_row:
    cmp r12d, [rsp + 24]
    jae .Ltv_draw_pop
    mov rdi, r13
    mov rsi, r15
    lea rdx, [rsp + 128]
    mov ecx, 16416
    call task_view_line
    test rax, rax
    js .Ltv_draw_pop
    mov r15, rdx
    lea rcx, [rsp + 128]
    mov r8, rax
.Ltv_draw_text:
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 36]
    COLOR r9d, T_FG
    call text_draw
    mov eax, [rsp + 16]
    add [rsp + 36], eax
    inc r12d
    test r15, r15
    jns .Ltv_draw_row
.Ltv_draw_pop:
    call gfx_clip_pop
.Ltv_draw_return:
    mov eax, [rsp + 32]
    xor edx, edx
    xor ecx, ecx
    test eax, eax
    jz 9f
    mov rdx, [rbx + TV_id]
    mov rcx, [rbx + TV_core]
9:  EPILOGUE

.section .rodata
.p2align 3
.Ltv_states: .quad .Ltv_preparing,.Ltv_queued,.Ltv_running,.Ltv_stopping,.Ltv_exited,.Ltv_failed
.Ltv_buttons: .quad .Ltv_stop,.Ltv_restart,.Ltv_copy,.Ltv_close
.Ltv_actions: .long TASK_VIEW_STOP,TASK_VIEW_RESTART,TASK_VIEW_COPY,TASK_VIEW_CLOSE
.Ltv_preparing: .asciz "preparing"
.Ltv_queued: .asciz "queued"
.Ltv_running: .asciz "running"
.Ltv_stopping: .asciz "stopping"
.Ltv_exited: .asciz "exited"
.Ltv_failed: .asciz "failed"
.Ltv_unknown: .asciz "unknown"
.Ltv_stop: .asciz "Stop"
.Ltv_restart: .asciz "Restart"
.Ltv_copy: .asciz "Copy"
.Ltv_close: .asciz "Close"
.Ltv_long: .ascii "[line truncated] "
.Ltv_discard: .ascii "[earlier output discarded]"

# Unicode17.0 Cf plus Default_Ignorable_Code_Point, sorted merged intervals.
# https://www.unicode.org/Public/17.0.0/ucd/{UnicodeData,DerivedCoreProperties}.txt
.p2align 2
.Ltv_hidden:
    .long 0xad,0xad
    .long 0x34f,0x34f
    .long 0x600,0x605
    .long 0x61c,0x61c
    .long 0x6dd,0x6dd
    .long 0x70f,0x70f
    .long 0x890,0x891
    .long 0x8e2,0x8e2
    .long 0x115f,0x1160
    .long 0x17b4,0x17b5
    .long 0x180b,0x180f
    .long 0x200b,0x200f
    .long 0x202a,0x202e
    .long 0x2060,0x206f
    .long 0x3164,0x3164
    .long 0xfe00,0xfe0f
    .long 0xfeff,0xfeff
    .long 0xffa0,0xffa0
    .long 0xfff0,0xfffb
    .long 0x110bd,0x110bd
    .long 0x110cd,0x110cd
    .long 0x13430,0x1343f
    .long 0x1bca0,0x1bca3
    .long 0x1d173,0x1d17a
    .long 0xe0000,0xe0fff
