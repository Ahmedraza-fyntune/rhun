# quick input (views design 1.4 and 3.11, feature quick-input): an extension's multi-step quick
# pick or validated input, drawn as the palette is: a title row ("Title  2/3", a Back button, title
# buttons, "N selected"), the field (masked for passwords, a spinner while busy), a prompt or a
# message under it, items (icon, label with matched characters in accent, a muted description, a
# detail line, item buttons on the active row, separators with labels, checkboxes in multi mode).
# One session at a time; the extension moves it from step to step with quick-set.
#     quick_open(ext, body, len) -> rax Q, -1 syntax, -2 toobig, -3 busy
#     quick_set(ext, Q, body, len) -> eax 0, 1 no such session, 2 syntax, 3 toobig
#     quick_close(ext, Q) -> eax 0, 1 no such session
# Events "0 quick Q ...": value, active, accept, back, button, hide.
.include "rhun.inc"

.equ QF_MULTI, 1
.equ QF_BACK, 2
.equ QF_BUSY, 4
.equ QF_NOFILTER, 8
.equ QF_MDESC, 16
.equ QF_MDETAIL, 32
.equ QF_PASSWORD, 64

.equ QK_ITEMS_MAX, 10000
.equ QK_BODY_MAX, 2097152
.equ QK_BUTTONS_MAX, 8
.equ QK_IBUTTONS_MAX, 4
.equ QK_ROWS, 12
.equ ID_QUICK, 0x6d0000         # rows + visible row; 0x1000 title buttons, back; 0x2000 item buttons; 0x3000 field

# an item
.equ QI_id, 0
.equ QI_label, 8
.equ QI_desc, 16
.equ QI_detail, 24
.equ QI_extra, 32
.equ QI_idlen, 40
.equ QI_lablen, 44
.equ QI_desclen, 48
.equ QI_detaillen, 52
.equ QI_xlen, 56
.equ QI_flags, 60
.equ QI_icon, 64
.equ QI_icolor, 68
.equ QI_SIZE, 72
.equ QIF_SEP, 1
.equ QIF_CHECKED, 2
.equ QIF_ALWAYS, 4

# a title button
.equ QB_key, 0
.equ QB_tip, 8
.equ QB_keylen, 16
.equ QB_tiplen, 20
.equ QB_icon, 24
.equ QB_x, 28                   # where it was drawn (headless)
.equ QB_SIZE, 32

.data
.p2align 2
q_active: .long -1              # the active item (an index into q_items), -1 for none
q_active_sent: .long -1         # the one an active event last named
q_hover: .long -1

.bss
.p2align 3
q_ext: .quad 0                  # the session's extension (0: none open)
q_tf: .zero TF_SIZE
q_items: .quad 0                # QI array
q_nitems: .quad 0
q_ibody: .quad 0                # the items' bytes and the title buttons' bytes (owned)
q_bbody: .quad 0
q_btns: .zero QB_SIZE * QK_BUTTONS_MAX
q_nbtns: .quad 0
q_title: .quad 0                # cstrs (mem_alloc'd) or 0
q_placeholder: .quad 0
q_prompt: .quad 0
q_msg: .quad 0
q_rows: .zero VEC_SIZE          # u32: the items shown, in order
q_ev: .zero SB_SIZE             # an event being written
q_rr: .zero RR_SIZE
q_rr2: .zero RR_SIZE
q_oldids: .zero VEC_SIZE        # quick-set: ptr, len of the checked items before it
q_actid: .zero SB_SIZE          # quick-set: the active item's id before it
q_id: .long 0                   # Q of the open session
q_gen: .long 0                  # the last Q handed out
q_seq: .long 0                  # the field's edits, from 1
q_sent: .long 0                 # the sequence of the last value event
q_msgseq: .long 0
q_msgsev: .long 0               # 0 info, 1 warning, 2 error
q_stepn: .long 0
q_stepm: .long 0
q_mode: .long 0                 # 0 pick, 1 input
q_flags: .long 0                # QF_*
q_scroll: .long 0               # the first row shown
q_waiting: .long 0              # accept was sent: Enter waits for a quick-set or quick-close
q_initial: .long 0              # the body being applied opens the session
q_prev_focus: .long 0
q_reveal: .long 0               # the active row comes into view when next drawn
q_shown: .long 0                # rows shown when last drawn
q_rowh: .long 0
q_x: .long 0                    # the card, last drawn
q_y: .long 0
q_w: .long 0
q_h: .long 0
q_fy: .long 0                   # the field's y, the rows' y
q_ry: .long 0
q_backx: .long 0                # the Back button's x, -1 none
q_rec_ok: .long 0
q_pad: .long 0
q_mask: .zero TF_SIZE           # a password field drawn as "*"

.text

# ---------------- requests ----------------

# quick_is_open() -> eax 1 while a session shows
FN quick_is_open
    xor eax, eax
    cmp qword ptr [rip + q_ext], 0
    setne al
    ret

# quick_field() -> rax its field while it has the keyboard (focused_field)
FN quick_field
    lea rax, [rip + q_tf]
    ret

# quick_open(ext, body, len) -> rax Q, -1 syntax, -2 toobig, -3 busy (a session, the palette or a
#   prompt shows)
FN quick_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rip + q_ext], 0
    jne 7f
    call palette_is_open
    test eax, eax
    jnz 7f
    cmp r13, QK_BODY_MAX
    ja 6f
    mov rdi, r12
    mov rsi, r13
    xor edx, edx
    call qk_body                # checked whole first
    cmp eax, 1
    je 5f
    cmp eax, 2
    je 6f
    # a fresh session
    call qk_reset
    mov [rip + q_ext], rbx
    inc dword ptr [rip + q_gen]
    mov eax, [rip + q_gen]
    mov [rip + q_id], eax
    mov dword ptr [rip + q_initial], 1
    mov rdi, r12
    mov rsi, r13
    mov edx, 1
    call qk_body
    mov dword ptr [rip + q_initial], 0
    call qk_filter
    mov eax, [rip + g_focus]
    mov [rip + q_prev_focus], eax
    mov dword ptr [rip + g_focus], FOCUS_QUICK
    mov dword ptr [rip + q_reveal], 1
    mov dword ptr [rip + g_dirty], 1
    mov eax, [rip + q_id]
    EPILOGUE
5:  mov rax, -1
    EPILOGUE
6:  mov rax, -2
    EPILOGUE
7:  mov rax, -3
    EPILOGUE

# quick_set(ext, Q, body, len) -> eax 0, 1 no such session, 2 syntax, 3 toobig: what the records
#   name changes, atomically; Enter works again
FN quick_set
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    cmp [rip + q_ext], rbx
    jne 7f
    test rbx, rbx
    jz 7f
    cmp [rip + q_id], r12d
    jne 7f
    cmp r14, QK_BODY_MAX
    ja 6f
    mov rdi, r13
    mov rsi, r14
    xor edx, edx
    call qk_body
    cmp eax, 1
    je 5f
    cmp eax, 2
    je 6f
    mov rdi, r13
    mov rsi, r14
    mov edx, 1
    call qk_body
    mov dword ptr [rip + q_waiting], 0
    call qk_filter
    mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
5:  mov eax, 2
    EPILOGUE
6:  mov eax, 3
    EPILOGUE
7:  mov eax, 1
    EPILOGUE

# quick_close(ext, Q) -> eax 0, 1 no such session: it closes without a hide event
FN quick_close
    PROLOGUE
    cmp [rip + q_ext], rdi
    jne 7f
    test rdi, rdi
    jz 7f
    cmp [rip + q_id], esi
    jne 7f
    call qk_end
    xor eax, eax
    EPILOGUE
7:  mov eax, 1
    EPILOGUE

# quick_owner_gone(ext): its session closes with it
FN quick_owner_gone
    cmp [rip + q_ext], rdi
    jne 9f
    test rdi, rdi
    jz 9f
    jmp qk_end
9:  ret

# qk_hide(): the user dismissed it: "hide", then it closes
qk_hide:
    sub rsp, 8
    lea rdi, [rip + .Le_hide]
    call ev_begin
    test eax, eax
    jz 1f
    call ev_line
1:  call qk_end
    add rsp, 8
    ret

# qk_end(): the session is gone; the keyboard goes back
qk_end:
    sub rsp, 8
    call qk_reset
    mov qword ptr [rip + q_ext], 0
    mov dword ptr [rip + q_id], 0
    cmp dword ptr [rip + g_focus], FOCUS_QUICK
    jne 1f
    mov eax, [rip + q_prev_focus]
    cmp eax, FOCUS_QUICK
    jne 2f
    xor eax, eax
2:  mov [rip + g_focus], eax
1:  mov dword ptr [rip + g_dirty], 1
    add rsp, 8
    ret

# qk_reset(): every part of a session freed and cleared
qk_reset:
    sub rsp, 8
    call free_items
    mov rdi, [rip + q_bbody]
    call mem_free
    mov qword ptr [rip + q_bbody], 0
    mov qword ptr [rip + q_nbtns], 0
    lea rdi, [rip + q_title]
    call free_str
    lea rdi, [rip + q_placeholder]
    call free_str
    lea rdi, [rip + q_prompt]
    call free_str
    lea rdi, [rip + q_msg]
    call free_str
    lea rdi, [rip + q_tf]
    call tf_clear
    xor eax, eax
    mov [rip + q_seq], eax
    mov [rip + q_sent], eax
    mov [rip + q_msgseq], eax
    mov [rip + q_msgsev], eax
    mov [rip + q_stepn], eax
    mov [rip + q_stepm], eax
    mov [rip + q_mode], eax
    mov [rip + q_flags], eax
    mov [rip + q_scroll], eax
    mov [rip + q_waiting], eax
    mov dword ptr [rip + q_active], -1
    mov dword ptr [rip + q_active_sent], -1
    mov qword ptr [rip + q_rows + VEC_len], 0
    add rsp, 8
    ret

# free_str(slot*): its cstr freed, the slot 0
free_str:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx]
    call mem_free
    mov qword ptr [rbx], 0
    pop rbx
    ret

# free_items(): the items and their bytes
free_items:
    sub rsp, 8
    mov rdi, [rip + q_items]
    call mem_free
    mov rdi, [rip + q_ibody]
    call mem_free
    mov qword ptr [rip + q_items], 0
    mov qword ptr [rip + q_ibody], 0
    mov qword ptr [rip + q_nitems], 0
    add rsp, 8
    ret

# ---------------- step bodies ----------------

# qk_body(ptr, len, apply) -> eax 0, 1 a record rhun cannot read, 2 past a limit: every record
#   checked (apply 0) or applied (apply 1); records rhun does not know are skipped
qk_body:
    PROLOGUE 16
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov [rsp], edx
1:  cmp r12, r13
    jae 8f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + q_rr]
    call tree_rec_read
    test rax, rax
    jz 7f
    mov r12, rax
    lea rbx, [rip + rec_table]
2:  mov rdx, [rbx]
    test rdx, rdx
    jz 1b                       # not one rhun knows
    lea rdi, [rip + q_rr]
    xor esi, esi
    call tree_rec_is
    test eax, eax
    jnz 3f
    add rbx, 24
    jmp 2b
3:  cmp dword ptr [rsp], 0
    jne 4f
    call [rbx + 8]              # its check: 1 good, 0 not, 2 too big
    cmp eax, 1
    je 1b
    test eax, eax
    jz 7f
    mov eax, 2
    EPILOGUE
4:  call [rbx + 16]
    jmp 1b
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# record helpers (q_rr)
rec_n:
    mov rax, [rip + q_rr + RR_n]
    ret
rec_len:
    mov rax, [rip + q_rr + RR_len]
    ret
# rec_word(i, cstr) -> eax 1 when field i is that word
rec_word:
    mov rdx, rsi
    mov esi, edi
    lea rdi, [rip + q_rr]
    jmp tree_rec_is
# rec_seq(i) -> rax the field's number ("-" 0), edx 1 when it is one
rec_seq:
    push rbx
    mov ebx, edi
    lea rsi, [rip + .Ldash]
    call rec_word
    test eax, eax
    jz 1f
    xor eax, eax
    mov edx, 1
    pop rbx
    ret
1:  mov esi, ebx
    lea rdi, [rip + q_rr]
    call tree_rec_num
    pop rbx
    ret
# one_line(max) -> eax 1 when the data is at most max bytes without LF or NUL
one_line:
    xor eax, eax
    mov rcx, [rip + q_rr + RR_len]
    cmp rcx, rdi
    ja 9f
    mov rdx, [rip + q_rr + RR_data]
    xor esi, esi
1:  cmp rsi, rcx
    jae 8f
    movzx edi, byte ptr [rdx + rsi]
    cmp edi, 10
    je 9f
    test edi, edi
    jz 9f
    inc rsi
    jmp 1b
8:  mov eax, 1
9:  ret

# take_str(slot*): the data as a cstr into the slot
take_str:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx]
    call mem_free
    mov rdi, [rip + q_rr + RR_data]
    mov rsi, [rip + q_rr + RR_len]
    call mem_dup
    mov [rbx], rax
    pop rbx
    ret

# title LEN, placeholder LEN: a line of at most 200 bytes; prompt LEN: 1000
ck_line200:
    sub rsp, 8
    call rec_n
    cmp rax, 2
    jne 8f
    mov edi, 200
    call one_line
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ck_line1000:
    sub rsp, 8
    call rec_n
    cmp rax, 2
    jne 8f
    mov edi, 1000
    call one_line
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ap_title:
    lea rdi, [rip + q_title]
    jmp take_str
ap_placeholder:
    lea rdi, [rip + q_placeholder]
    jmp take_str
ap_prompt:
    lea rdi, [rip + q_prompt]
    jmp take_str

# step N M 0 (0 0 hides it)
ck_step:
    sub rsp, 8
    call rec_n
    cmp rax, 4
    jne 8f
    call rec_len
    test rax, rax
    jnz 8f
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 8f
    cmp rax, 9999
    ja 8f
    lea rdi, [rip + q_rr]
    mov esi, 2
    call tree_rec_num
    test edx, edx
    jz 8f
    cmp rax, 9999
    ja 8f
    mov eax, 1
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ap_step:
    sub rsp, 8
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    mov [rip + q_stepn], eax
    lea rdi, [rip + q_rr]
    mov esi, 2
    call tree_rec_num
    mov [rip + q_stepm], eax
    add rsp, 8
    ret

# value SEQ LEN: at most 64 KB, one line
ck_value:
    sub rsp, 8
    call rec_n
    cmp rax, 3
    jne 8f
    mov edi, 1
    call rec_seq
    test edx, edx
    jz 8f
    mov edi, 65536
    call one_line
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
# the field's text when SEQ is its sequence, at quick, or after an accept (the next step)
ap_value:
    sub rsp, 8
    mov edi, 1
    call rec_seq
    cmp dword ptr [rip + q_initial], 0
    jne 1f
    cmp dword ptr [rip + q_waiting], 0
    jne 1f
    cmp eax, [rip + q_seq]
    jne 9f
1:  lea rdi, [rip + q_tf]
    mov rsi, [rip + q_rr + RR_data]
    mov rdx, [rip + q_rr + RR_len]
    call tf_set
    mov eax, [rip + q_seq]      # rhun set it: no value event for it
    mov [rip + q_sent], eax
9:  add rsp, 8
    ret

# mode pick|input 0
ck_mode:
    sub rsp, 8
    call rec_n
    cmp rax, 3
    jne 8f
    call rec_len
    test rax, rax
    jnz 8f
    mov edi, 1
    lea rsi, [rip + .Lw_pick]
    call rec_word
    test eax, eax
    jnz 7f
    mov edi, 1
    lea rsi, [rip + .Lw_input]
    call rec_word
    add rsp, 8
    ret
7:  mov eax, 1
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ap_mode:
    sub rsp, 8
    mov edi, 1
    lea rsi, [rip + .Lw_input]
    call rec_word
    mov [rip + q_mode], eax
    add rsp, 8
    ret

# flags F... 0 (- clears them all): the flags in effect from now
ck_flags:
    PROLOGUE
    call rec_n
    cmp rax, 3
    jb 8f
    call rec_len
    test rax, rax
    jnz 8f
    mov ebx, 1
1:  call rec_n
    dec rax
    cmp rbx, rax
    jae 7f
    mov edi, ebx
    call flag_bit
    test eax, eax
    js 8f
    inc ebx
    jmp 1b
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
ap_flags:
    PROLOGUE
    xor r12d, r12d
    mov ebx, 1
1:  call rec_n
    dec rax
    cmp rbx, rax
    jae 7f
    mov edi, ebx
    call flag_bit
    or r12d, eax
    inc ebx
    jmp 1b
7:  mov [rip + q_flags], r12d
    call qk_filter
    EPILOGUE
# flag_bit(i) -> eax the field's QF_* bit, 0 for "-", -1 for a word rhun does not know
flag_bit:
    PROLOGUE
    mov ebx, edi
    mov edi, ebx
    lea rsi, [rip + .Ldash]
    call rec_word
    test eax, eax
    jz 1f
    xor eax, eax
    EPILOGUE
1:  lea r12, [rip + flag_words]
    mov r13d, 1
2:  mov rsi, [r12]
    test rsi, rsi
    jz 8f
    mov edi, ebx
    call rec_word
    test eax, eax
    jnz 3f
    add r12, 8
    shl r13d, 1
    jmp 2b
3:  mov eax, r13d
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# msg SEQ SEVERITY LEN: shown while SEQ is the field's sequence; an error blocks Enter
ck_msg:
    sub rsp, 8
    call rec_n
    cmp rax, 4
    jne 8f
    mov edi, 1
    call rec_seq
    test edx, edx
    jz 8f
    call sev_of
    test eax, eax
    js 8f
    mov edi, 1000
    call one_line
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ap_msg:
    sub rsp, 8
    mov edi, 1
    call rec_seq
    mov [rip + q_msgseq], eax
    call sev_of
    mov [rip + q_msgsev], eax
    lea rdi, [rip + q_msg]
    call take_str
    add rsp, 8
    ret
# sev_of() -> eax 0 info, 1 warning, 2 error (field 2), -1 none of them
sev_of:
    sub rsp, 8
    mov edi, 2
    lea rsi, [rip + .Lw_info]
    call rec_word
    test eax, eax
    jnz 1f
    mov edi, 2
    lea rsi, [rip + .Lw_warning]
    call rec_word
    test eax, eax
    jnz 2f
    mov edi, 2
    lea rsi, [rip + .Lw_error]
    call rec_word
    test eax, eax
    jnz 3f
    mov eax, -1
    add rsp, 8
    ret
1:  xor eax, eax
    add rsp, 8
    ret
2:  mov eax, 1
    add rsp, 8
    ret
3:  mov eax, 2
    add rsp, 8
    ret

# buttons N LEN + N records "KEY ICON TIP_LEN" LF TIP: the title buttons (at most 8)
ck_buttons:
    PROLOGUE
    call rec_n
    cmp rax, 3
    jne 8f
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 8f
    cmp rax, QK_BUTTONS_MAX
    ja 9f
    mov r14d, eax
    mov r12, [rip + q_rr + RR_data]
    mov r13, r12
    add r13, [rip + q_rr + RR_len]
1:  test r14d, r14d
    jz 7f
    mov rdi, r12
    mov rsi, r13
    call button_rec
    test rax, rax
    jz 8f
    mov r12, rax
    dec r14d
    jmp 1b
7:  cmp r12, r13
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 2
    EPILOGUE
ap_buttons:
    PROLOGUE
    mov rdi, [rip + q_bbody]
    call mem_free
    mov rdi, [rip + q_rr + RR_data]
    mov rsi, [rip + q_rr + RR_len]
    call mem_dup
    mov [rip + q_bbody], rax
    mov r12, rax
    mov r13, rax
    add r13, [rip + q_rr + RR_len]
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    mov r14d, eax
    mov [rip + q_nbtns], rax
    xor r15d, r15d
1:  cmp r15d, r14d
    jae 9f
    mov rdi, r12
    mov rsi, r13
    call button_rec
    mov r12, rax
    imul ebx, r15d, QB_SIZE
    lea rcx, [rip + q_btns]
    add rbx, rcx
    mov rax, [rip + q_rr2]      # KEY
    mov [rbx + QB_key], rax
    mov eax, [rip + q_rr2 + 8]
    mov [rbx + QB_keylen], eax
    mov rax, [rip + q_rr2 + RR_data]
    mov [rbx + QB_tip], rax
    mov eax, [rip + q_rr2 + RR_len]
    mov [rbx + QB_tiplen], eax
    mov eax, [rip + q_rec_ok]   # the icon button_rec found
    mov [rbx + QB_icon], eax
    inc r15d
    jmp 1b
9:  EPILOGUE

# button_rec(p, end) -> rax past a "KEY ICON TIP_LEN" LF TIP record (q_rr2; q_rec_ok its icon, -1
#   for "-"), 0 when it is not one; also item records' "button KEY ICON LEN" + tooltip
button_rec:
    PROLOGUE
    lea rdx, [rip + q_rr2]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp qword ptr [rip + q_rr2 + RR_n], 3
    jne 8f
    xor r12d, r12d              # field of KEY
    jmp key_icon_tip
8:  xor eax, eax
    EPILOGUE
# the record in q_rr2 from field r12 on: KEY ICON, then the tooltip as its data; rbx past it
key_icon_tip:
    mov rcx, r12
    shl rcx, 4
    lea rdx, [rip + q_rr2]
    mov rdi, [rdx + rcx]
    mov rsi, [rdx + rcx + 8]
    test rsi, rsi
    jz 8f
    cmp rsi, 64
    ja 8f
    xor ecx, ecx                # KEY: [A-Za-z0-9_.-]
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    lea rdx, [rip + key_ok]
    cmp byte ptr [rdx + rax], 0
    je 8f
    inc rcx
    jmp 1b
2:  lea rdi, [rip + q_rr2]      # ICON: a built-in name or "-"
    lea esi, [r12 + 1]
    lea rdx, [rip + .Ldash]
    call tree_rec_is
    mov dword ptr [rip + q_rec_ok], -1
    test eax, eax
    jnz 3f
    lea rcx, [r12 + 1]
    shl rcx, 4
    lea rdx, [rip + q_rr2]
    mov rdi, [rdx + rcx]
    mov rsi, [rdx + rcx + 8]
    call tree_icon_code
    test eax, eax
    js 8f
    test eax, NDI_FILE
    jnz 8f
    mov [rip + q_rec_ok], eax
3:  mov rcx, [rip + q_rr2 + RR_len]
    cmp rcx, 200
    ja 8f
    mov rdi, [rip + q_rr2 + RR_data]
    mov esi, 10
    call has_lf
    test eax, eax
    jnz 8f
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# has_lf(ptr, byte, len in rcx) -> eax 1 when the bytes hold it
has_lf:
    xor eax, eax
    test rcx, rcx
    jz 9f
    mov eax, esi
    repne scasb
    sete al
    movzx eax, al
9:  ret

# items N LEN + N item records "ID_LEN LABEL_LEN EXTRA_LEN KIND" LF <ID><LABEL><EXTRA>
ck_items:
    PROLOGUE
    call rec_n
    cmp rax, 3
    jne 8f
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 8f
    cmp rax, QK_ITEMS_MAX
    ja 9f
    mov r14d, eax
    mov r12, [rip + q_rr + RR_data]
    mov r13, r12
    add r13, [rip + q_rr + RR_len]
1:  test r14d, r14d
    jz 7f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + item_tmp]
    call item_rec
    cmp rax, 1
    je 9f
    test rax, rax
    jz 8f
    mov r12, rax
    dec r14d
    jmp 1b
7:  cmp r12, r13
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 2
    EPILOGUE

# item_rec(p, end, QI*) -> rax past the item record (the QI filled, pointing into the bytes), 0
#   when it is not one, 1 for more than 4 item buttons
item_rec:
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov rdi, rbx
    xor esi, esi
    mov edx, QI_SIZE
    call memset
    mov dword ptr [rbx + QI_icon], -1
    mov dword ptr [rbx + QI_icolor], -1
    # the header: three numbers and a word
    mov r14, r12
1:  cmp r14, r13
    jae 8f
    cmp byte ptr [r14], 10
    je 2f
    inc r14
    jmp 1b
2:  mov [rsp], r14              # its LF
    mov r15, r12
    xor ecx, ecx                # numbers read
3:  cmp ecx, 3
    jae 4f
    mov [rsp + 8], ecx
    mov rdi, r15
    mov rsi, r14
    sub rsi, r15
    call parse_u64
    test rdx, rdx
    jz 8f
    cmp rdx, 10
    ja 8f
    add r15, rdx
    cmp r15, r14
    jae 8f
    cmp byte ptr [r15], ' '
    jne 8f
    inc r15
    mov ecx, [rsp + 8]
    lea rdx, [rip + num3]
    mov [rdx + rcx*8], rax
    inc ecx
    jmp 3b
4:  mov rdi, r15                # KIND
    mov rsi, r14
    sub rsi, r15
    lea rdx, [rip + .Lw_sep]
    call str_eq_cstr
    test eax, eax
    jz 41f
    or dword ptr [rbx + QI_flags], QIF_SEP
    jmp 42f
41: mov rdi, r15
    mov rsi, r14
    sub rsi, r15
    lea rdx, [rip + .Lw_item]
    call str_eq_cstr
    test eax, eax
    jz 8f
42: mov rax, [rip + num3]       # ID at most 1000, LABEL 1000 (one line), EXTRA the rest
    cmp rax, 1000
    ja 8f
    mov rax, [rip + num3 + 8]
    cmp rax, 1000
    ja 8f
    lea r15, [r14 + 1]
    mov rax, r13
    sub rax, r15
    mov rcx, [rip + num3]
    add rcx, [rip + num3 + 8]
    add rcx, [rip + num3 + 16]
    cmp rcx, rax
    ja 8f
    mov [rbx + QI_id], r15
    mov rax, [rip + num3]
    mov [rbx + QI_idlen], eax
    add r15, rax
    mov [rbx + QI_label], r15
    mov rcx, [rip + num3 + 8]
    mov [rbx + QI_lablen], ecx
    mov rdi, r15
    mov esi, 10
    call has_lf
    test eax, eax
    jnz 8f
    add r15, [rip + num3 + 8]
    mov [rbx + QI_extra], r15
    mov rax, [rip + num3 + 16]
    mov [rbx + QI_xlen], eax
    lea rax, [r15 + rax]
    mov [rsp + 16], rax         # past the item
    # its records
    mov dword ptr [rsp + 24], 0 # item buttons
5:  cmp r15, [rsp + 16]
    jae 7f
    mov rdi, r15
    mov rsi, [rsp + 16]
    lea rdx, [rip + q_rr2]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r15, rax
    lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_desc]
    call tree_rec_is
    test eax, eax
    jz 51f
    mov rax, [rip + q_rr2 + RR_data]
    mov [rbx + QI_desc], rax
    mov eax, [rip + q_rr2 + RR_len]
    mov [rbx + QI_desclen], eax
    jmp 5b
51: lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_detail]
    call tree_rec_is
    test eax, eax
    jz 52f
    mov rax, [rip + q_rr2 + RR_data]
    mov [rbx + QI_detail], rax
    mov eax, [rip + q_rr2 + RR_len]
    mov [rbx + QI_detaillen], eax
    jmp 5b
52: lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_picked]
    call tree_rec_is
    test eax, eax
    jz 53f
    or dword ptr [rbx + QI_flags], QIF_CHECKED
    jmp 5b
53: lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_always]
    call tree_rec_is
    test eax, eax
    jz 54f
    or dword ptr [rbx + QI_flags], QIF_ALWAYS
    jmp 5b
54: lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_icon]
    call tree_rec_is
    test eax, eax
    jz 55f
    cmp qword ptr [rip + q_rr2 + RR_n], 4
    jne 5b
    mov rdi, [rip + q_rr2 + 16]
    mov rsi, [rip + q_rr2 + 24]
    call tree_icon_code
    mov [rbx + QI_icon], eax
    mov rdi, [rip + q_rr2 + 32]
    mov rsi, [rip + q_rr2 + 40]
    call tree_color_code
    mov [rbx + QI_icolor], eax
    jmp 5b
55: lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_button]
    call tree_rec_is
    test eax, eax
    jz 5b
    cmp qword ptr [rip + q_rr2 + RR_n], 4
    jne 8f
    inc dword ptr [rsp + 24]
    cmp dword ptr [rsp + 24], QK_IBUTTONS_MAX
    ja 9f
    push rbx
    push r12
    mov rbx, r15
    mov r12d, 1
    call key_icon_tip_call
    pop r12
    pop rbx
    test rax, rax
    jz 8f
    jmp 5b
7:  mov rax, [rsp + 16]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# key_icon_tip_call(): key_icon_tip as a function (rbx past the record, r12 KEY's field)
key_icon_tip_call:
    PROLOGUE
    jmp key_icon_tip

ap_items:
    PROLOGUE 16
    # the checked items' ids and the active one's, kept by id
    mov qword ptr [rip + q_oldids + VEC_len], 0
    lea rdi, [rip + q_actid]
    call sb_clear
    mov dword ptr [rsp], 0      # an active item
    movsxd rax, dword ptr [rip + q_active]
    test rax, rax
    js 11f
    imul rax, rax, QI_SIZE
    add rax, [rip + q_items]
    lea rdi, [rip + q_actid]
    mov rsi, [rax + QI_id]
    mov edx, [rax + QI_idlen]
    call sb_push
    mov dword ptr [rsp], 1
11: xor ebx, ebx
1:  cmp rbx, [rip + q_nitems]
    jae 2f
    imul rax, rbx, QI_SIZE
    add rax, [rip + q_items]
    test dword ptr [rax + QI_flags], QIF_CHECKED
    jz 12f
    mov [rsp + 8], rax
    lea rdi, [rip + q_oldids]
    mov esi, 16
    call vec_push
    mov rcx, [rsp + 8]
    mov rdx, [rcx + QI_id]
    mov [rax], rdx
    mov edx, [rcx + QI_idlen]
    mov [rax + 8], rdx
12: inc rbx
    jmp 1b
2:  # the old bytes stay until the new items are read (the ids above point into them)
    mov r14, [rip + q_ibody]
    mov r15, [rip + q_items]
    mov rdi, [rip + q_rr + RR_data]
    mov rsi, [rip + q_rr + RR_len]
    call mem_dup
    mov [rip + q_ibody], rax
    mov r12, rax
    mov r13, rax
    add r13, [rip + q_rr + RR_len]
    lea rdi, [rip + q_rr]
    mov esi, 1
    call tree_rec_num
    mov [rip + q_nitems], rax
    mov rbx, rax
    imul rdi, rax, QI_SIZE
    add rdi, QI_SIZE
    call mem_alloc
    mov [rip + q_items], rax
    mov dword ptr [rip + q_active], -1
    xor ecx, ecx
3:  cmp rcx, rbx
    jae 4f
    push rcx
    push rcx
    imul rdx, rcx, QI_SIZE
    add rdx, [rip + q_items]
    mov rdi, r12
    mov rsi, r13
    call item_rec
    mov r12, rax
    pop rcx
    pop rcx
    imul rdx, rcx, QI_SIZE      # checked before: still checked; the active id: active again
    add rdx, [rip + q_items]
    push rcx
    push rdx
    mov rdi, rdx
    call was_checked
    pop rdx
    pop rcx
    test eax, eax
    jz 31f
    or dword ptr [rdx + QI_flags], QIF_CHECKED
31: cmp dword ptr [rsp], 0
    je 32f
    cmp dword ptr [rip + q_active], -1
    jne 32f
    push rcx
    push rdx
    mov rdi, [rdx + QI_id]
    mov esi, [rdx + QI_idlen]
    mov rdx, [rip + q_actid + SB_ptr]
    mov rcx, [rip + q_actid + SB_len]
    call same_bytes
    pop rdx
    pop rcx
    test eax, eax
    jz 32f
    mov [rip + q_active], ecx
32: inc rcx
    jmp 3b
4:  mov rdi, r14
    call mem_free
    mov rdi, r15
    call mem_free
    call qk_filter
    EPILOGUE

# was_checked(QI*) -> eax 1 when an item with its id was checked before the quick-set
was_checked:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rip + q_oldids + VEC_len]
    jae 8f
    mov rax, r12
    shl rax, 4
    add rax, [rip + q_oldids + VEC_ptr]
    mov rdi, [rbx + QI_id]
    mov esi, [rbx + QI_idlen]
    mov rdx, [rax]
    mov rcx, [rax + 8]
    call same_bytes
    test eax, eax
    jnz 9f
    inc r12
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# same_bytes(a, alen, b, blen) -> eax 1 when equal
same_bytes:
    xor eax, eax
    cmp rsi, rcx
    jne 9f
    mov rcx, rsi
    mov rsi, rdx
    repe cmpsb
    sete al
    movzx eax, al
9:  ret

# active LEN + item id
ck_active:
    sub rsp, 8
    call rec_n
    cmp rax, 2
    jne 8f
    call rec_len
    cmp rax, 1000
    ja 8f
    mov eax, 1
    add rsp, 8
    ret
8:  xor eax, eax
    add rsp, 8
    ret
ap_active:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + q_nitems]
    jae 9f
    imul r12, rbx, QI_SIZE
    add r12, [rip + q_items]
    test dword ptr [r12 + QI_flags], QIF_SEP
    jnz 2f
    mov rdi, [r12 + QI_id]
    mov esi, [r12 + QI_idlen]
    mov rdx, [rip + q_rr + RR_data]
    mov rcx, [rip + q_rr + RR_len]
    call same_bytes
    test eax, eax
    jz 2f
    mov [rip + q_active], ebx
    mov [rip + q_active_sent], ebx  # the extension named it: no event for it
    mov dword ptr [rip + q_reveal], 1
    jmp 9f
2:  inc rbx
    jmp 1b
9:  EPILOGUE

# ---------------- filtering ----------------

# qk_filter(): q_rows = the items shown, in order: all of them without a query or with nofilter;
#   else those whose label (with the flags, description or detail) holds the query as a fuzzy
#   subsequence, and "always" ones; a separator shows when an item after it (before the next one)
#   does. The active item stays when shown, else the first shown item takes it.
qk_filter:
    PROLOGUE 16
    mov qword ptr [rip + q_rows + VEC_len], 0
    lea rdi, [rip + q_tf]
    call tf_text
    mov r14, rax                # the query
    mov r15, rdx
    test dword ptr [rip + q_flags], QF_NOFILTER
    jz 1f
    xor r15d, r15d
1:  mov dword ptr [rsp], -1     # a separator waiting for an item
    xor ebx, ebx
2:  cmp rbx, [rip + q_nitems]
    jae 6f
    imul r12, rbx, QI_SIZE
    add r12, [rip + q_items]
    test dword ptr [r12 + QI_flags], QIF_SEP
    jz 3f
    mov [rsp], ebx
    jmp 5f
3:  test r15, r15
    jz 4f
    test dword ptr [r12 + QI_flags], QIF_ALWAYS
    jnz 4f
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    call item_score
    test eax, eax
    js 5f
4:  mov eax, [rsp]              # its separator first
    cmp eax, -1
    je 41f
    lea rdi, [rip + q_rows]
    mov esi, 4
    call vec_push
    mov ecx, [rsp]
    mov [rax], ecx
    mov dword ptr [rsp], -1
41: lea rdi, [rip + q_rows]
    mov esi, 4
    call vec_push
    mov [rax], ebx
5:  inc rbx
    jmp 2b
6:  # the active item: still shown, or the first item shown
    mov eax, [rip + q_active]
    cmp eax, -1
    je 62f
    xor ecx, ecx
61: cmp rcx, [rip + q_rows + VEC_len]
    jae 62f
    mov rdx, [rip + q_rows + VEC_ptr]
    cmp [rdx + rcx*4], eax
    je 9f
    inc rcx
    jmp 61b
62: mov dword ptr [rip + q_active], -1
    xor ecx, ecx
63: cmp rcx, [rip + q_rows + VEC_len]
    jae 9f
    mov rdx, [rip + q_rows + VEC_ptr]
    mov eax, [rdx + rcx*4]
    imul r8, rax, QI_SIZE
    add r8, [rip + q_items]
    test dword ptr [r8 + QI_flags], QIF_SEP
    jnz 64f
    mov [rip + q_active], eax
    mov dword ptr [rip + q_reveal], 1
    jmp 9f
64: inc rcx
    jmp 63b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# item_score(QI*, query, qlen) -> eax the best fuzzy score of its label (description, detail with
#   the flags), -1 for no match
item_score:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rbx + QI_label]
    mov esi, [rbx + QI_lablen]
    mov rdx, r12
    mov rcx, r13
    call fuzzy
    mov r14d, eax
    test dword ptr [rip + q_flags], QF_MDESC
    jz 1f
    cmp qword ptr [rbx + QI_desc], 0
    je 1f
    mov rdi, [rbx + QI_desc]
    mov esi, [rbx + QI_desclen]
    mov rdx, r12
    mov rcx, r13
    call fuzzy
    cmp eax, r14d
    cmovg r14d, eax
1:  test dword ptr [rip + q_flags], QF_MDETAIL
    jz 2f
    cmp qword ptr [rbx + QI_detail], 0
    je 2f
    mov rdi, [rbx + QI_detail]
    mov esi, [rbx + QI_detaillen]
    mov rdx, r12
    mov rcx, r13
    call fuzzy
    cmp eax, r14d
    cmovg r14d, eax
2:  mov eax, r14d
    EPILOGUE

# quick_changed(): the user edited the field: its sequence counts on, the items filter again, and
#   a value event goes when the frame is drawn
FN quick_changed
    sub rsp, 8
    inc dword ptr [rip + q_seq]
    call qk_filter
    add rsp, 8
    ret

# ---------------- events ----------------

# ev_begin(cstr what) -> eax 1 with "0 quick Q WHAT" in q_ev, 0 when its extension does not run
ev_begin:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rip + q_ext]
    test rax, rax
    jz 8f
    cmp dword ptr [rax + EXT_status], ES_RUNNING
    jne 8f
    lea rdi, [rip + q_ev]
    call sb_clear
    lea rdi, [rip + q_ev]
    lea rsi, [rip + .Le_quick]
    call sb_push_cstr
    lea rdi, [rip + q_ev]
    mov esi, [rip + q_id]
    call sb_push_u64
    lea rdi, [rip + q_ev]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + q_ev]
    mov rsi, rbx
    call sb_push_cstr
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ev_num(n): " N"
ev_num:
    push rdi
    lea rdi, [rip + q_ev]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    lea rdi, [rip + q_ev]
    jmp sb_push_u64

# ev_word(cstr): " WORD"
ev_word:
    push rdi
    lea rdi, [rip + q_ev]
    mov esi, ' '
    call sb_push_byte
    pop rsi
    lea rdi, [rip + q_ev]
    jmp sb_push_cstr

# ev_line(): the event's LF, sent
ev_line:
    sub rsp, 8
    lea rdi, [rip + q_ev]
    mov esi, 10
    call sb_push_byte
    call ev_send
    add rsp, 8
    ret

# ev_body(ptr, len): " LEN" LF and the bytes, sent
ev_body:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, r13
    call ev_num
    lea rdi, [rip + q_ev]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + q_ev]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    call ev_send
    EPILOGUE

ev_send:
    mov rdi, [rip + q_ext]
    mov rsi, [rip + q_ev + SB_ptr]
    mov rdx, [rip + q_ev + SB_len]
    jmp ext_send

# send_pending(): once a frame: the field's value when it changed, the active item when it did
send_pending:
    PROLOGUE
    mov eax, [rip + q_seq]
    cmp eax, [rip + q_sent]
    je 1f
    mov [rip + q_sent], eax
    lea rdi, [rip + .Le_value]
    call ev_begin
    test eax, eax
    jz 1f
    mov edi, [rip + q_seq]
    call ev_num
    lea rdi, [rip + q_tf]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    call ev_body
1:  mov eax, [rip + q_active]
    cmp eax, [rip + q_active_sent]
    je 9f
    mov [rip + q_active_sent], eax
    cmp eax, -1
    je 9f
    lea rdi, [rip + .Le_active]
    call ev_begin
    test eax, eax
    jz 9f
    mov edi, [rip + q_seq]
    call ev_num
    movsxd rax, dword ptr [rip + q_active]
    imul rax, rax, QI_SIZE
    add rax, [rip + q_items]
    mov rdi, [rax + QI_id]
    mov esi, [rax + QI_idlen]
    call ev_body
9:  EPILOGUE

# qk_accept(): Enter: "accept SEQ N LEN" + the chosen ids (the checked ones in multi mode, else the
#   active one), each ending in LF, then the field's text; refused while an error for this text
#   shows or the last accept waits for its answer
qk_accept:
    PROLOGUE 16
    cmp dword ptr [rip + q_waiting], 0
    jne 9f
    call msg_current
    cmp eax, 2
    je 9f
    call send_pending           # the value and active item it is about go first
    lea rdi, [rip + .Le_accept]
    call ev_begin
    test eax, eax
    jz 9f
    mov edi, [rip + q_seq]
    call ev_num
    lea rdi, [rip + acc_body]
    call sb_clear
    xor r12d, r12d              # ids
    cmp dword ptr [rip + q_mode], 1
    je 5f
    test dword ptr [rip + q_flags], QF_MULTI
    jnz 2f
    movsxd rax, dword ptr [rip + q_active]
    test rax, rax
    js 5f
    imul rax, rax, QI_SIZE
    add rax, [rip + q_items]
    mov rdi, rax
    call push_id
    inc r12d
    jmp 5f
2:  xor ebx, ebx
3:  cmp rbx, [rip + q_nitems]
    jae 5f
    imul rax, rbx, QI_SIZE
    add rax, [rip + q_items]
    test dword ptr [rax + QI_flags], QIF_CHECKED
    jz 4f
    test dword ptr [rax + QI_flags], QIF_SEP
    jnz 4f
    mov rdi, rax
    call push_id
    inc r12d
4:  inc rbx
    jmp 3b
5:  mov edi, r12d
    call ev_num
    lea rdi, [rip + q_tf]
    call tf_text
    lea rdi, [rip + acc_body]
    mov rsi, rax
    call sb_push
    mov rdi, [rip + acc_body + SB_ptr]
    mov rsi, [rip + acc_body + SB_len]
    call ev_body
    mov dword ptr [rip + q_waiting], 1
9:  EPILOGUE

# push_id(QI*): its id and a LF onto acc_body
push_id:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + acc_body]
    mov rsi, [rbx + QI_id]
    mov edx, [rbx + QI_idlen]
    call sb_push
    lea rdi, [rip + acc_body]
    mov esi, 10
    call sb_push_byte
    pop rbx
    ret

# msg_current() -> eax the message's severity while it is about this text (0 info 1 warning 2
#   error), -1 when none shows
msg_current:
    mov eax, -1
    cmp qword ptr [rip + q_msg], 0
    je 9f
    mov ecx, [rip + q_msgseq]
    cmp ecx, [rip + q_seq]
    jne 9f
    mov eax, [rip + q_msgsev]
9:  ret

# qk_back(): Alt+Left or the Back button: "back SEQ"
qk_back:
    sub rsp, 8
    test dword ptr [rip + q_flags], QF_BACK
    jz 9f
    lea rdi, [rip + .Le_back]
    call ev_begin
    test eax, eax
    jz 9f
    mov edi, [rip + q_seq]
    call ev_num
    call ev_line
9:  add rsp, 8
    ret

# qk_button(key ptr, keylen, QI* or 0): "button SEQ KEY LEN" + the item's id (empty: a title button)
qk_button:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    lea rdi, [rip + .Le_button]
    call ev_begin
    test eax, eax
    jz 9f
    mov edi, [rip + q_seq]
    call ev_num
    lea rdi, [rip + q_ev]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + q_ev]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    xor edi, edi
    xor esi, esi
    test r14, r14
    jz 1f
    mov rdi, [r14 + QI_id]
    mov esi, [r14 + QI_idlen]
1:  call ev_body
9:  EPILOGUE

# toggle(item index): multi mode: its check flips
toggle:
    test dword ptr [rip + q_flags], QF_MULTI
    jz 9f
    test edi, edi
    js 9f
    movsxd rax, edi
    imul rax, rax, QI_SIZE
    add rax, [rip + q_items]
    test dword ptr [rax + QI_flags], QIF_SEP
    jnz 9f
    xor dword ptr [rax + QI_flags], QIF_CHECKED
    mov dword ptr [rip + g_dirty], 1
9:  ret

# ---------------- keys ----------------

# quick_key(keysym, cp, mods) -> eax 1 when the session took the key: Escape dismisses, Enter
#   accepts, Up/Down/Page Up/Page Down move the active item, Space toggles it in multi mode,
#   Alt+Left goes back; the field's editing keys
FN quick_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    cmp qword ptr [rip + q_ext], 0
    je 8f
    cmp r12d, KEY_ESCAPE
    jne 1f
    call qk_hide
    jmp 7f
1:  cmp r12d, KEY_RETURN
    je 11f
    cmp r12d, KEY_KP_ENTER
    jne 2f
11: call qk_accept
    jmp 7f
2:  cmp r12d, KEY_LEFT
    jne 3f
    test r14d, MOD_ALT
    jz 3f
    call qk_back
    jmp 7f
3:  mov esi, 1
    cmp r12d, KEY_DOWN
    je 31f
    mov esi, -1
    cmp r12d, KEY_UP
    je 31f
    mov esi, QK_ROWS - 1
    cmp r12d, KEY_PAGEDOWN
    je 31f
    mov esi, -(QK_ROWS - 1)
    cmp r12d, KEY_PAGEUP
    jne 4f
31: mov edi, esi
    call move_active
    jmp 7f
4:  cmp r12d, ' '
    jne 5f
    test dword ptr [rip + q_flags], QF_MULTI
    jz 5f
    test r14d, MOD_CTRL | MOD_ALT
    jnz 5f
    mov edi, [rip + q_active]
    call toggle
    jmp 7f
5:  mov rax, [rip + q_tf + TF_revision]
    mov rbx, rax
    lea rdi, [rip + q_tf]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tf_key
    test eax, eax
    jz 8f
    cmp rbx, [rip + q_tf + TF_revision]
    je 7f
    call quick_changed
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# move_active(by): the active item moves by that many rows (separators skipped), clamped
move_active:
    PROLOGUE
    mov r12d, edi
    mov rbx, [rip + q_rows + VEC_len]
    test rbx, rbx
    jz 9f
    xor r13d, r13d              # the active item's row
    mov eax, [rip + q_active]
1:  cmp r13, rbx
    jae 2f
    mov rdx, [rip + q_rows + VEC_ptr]
    cmp [rdx + r13*4], eax
    je 3f
    inc r13
    jmp 1b
2:  xor r13d, r13d
    mov r12d, 0
3:  add r13d, r12d
    test r13d, r13d
    jns 4f
    xor r13d, r13d
4:  cmp r13, rbx
    jb 5f
    lea r13, [rbx - 1]
5:  # off a separator: on in the direction of travel, else back
    mov r14d, 1
    test r12d, r12d
    jns 51f
    mov r14d, -1
51: mov ecx, 2                  # both directions at most
52: mov rdx, [rip + q_rows + VEC_ptr]
    mov eax, [rdx + r13*4]
    imul r8, rax, QI_SIZE
    add r8, [rip + q_items]
    test dword ptr [r8 + QI_flags], QIF_SEP
    jz 6f
    add r13d, r14d
    js 53f
    cmp r13, rbx
    jb 52b
53: sub r13d, r14d              # past an end: the other way
    neg r14d
    dec ecx
    jnz 52b
    jmp 9f
6:  mov [rip + q_active], eax
    mov dword ptr [rip + q_reveal], 1
9:  EPILOGUE

# ---------------- drawing ----------------

# quick_draw(): the card, over everything but dialogs; a click outside dismisses it; the palette
#   opening dismisses it too
FN quick_draw
    PROLOGUE 96
    cmp qword ptr [rip + q_ext], 0
    je .Lqd_ret
    call palette_is_open
    test eax, eax
    jz 1f
    call qk_hide
    jmp .Lqd_ret
1:  call send_pending
    # the width as the palette's; rows: 12 at most, fitted
    xor edi, edi
    xor esi, esi
    mov edx, [rip + g_cv + CV_w]
    mov ecx, [rip + g_cv + CV_h]
    mov r8d, 0x30000000
    call gfx_fill
    mov edi, 640
    call sc
    mov ecx, [rip + g_cv + CV_w]
    sub ecx, [rip + g_mt + 4*MI_16]
    cmp eax, ecx
    cmovg eax, ecx
    mov ecx, 1
    cmp eax, ecx
    cmovl eax, ecx
    mov r12d, eax               # w
    mov eax, [rip + g_cv + CV_w]
    sub eax, r12d
    sar eax, 1
    mov r13d, eax               # x
    M r14d, MI_TITLE
    add r14d, [rip + g_mt + 4*MI_8]     # y
    # the row height: taller when an item shown has a detail
    M eax, MI_32
    xor ecx, ecx
2:  cmp rcx, [rip + q_rows + VEC_len]
    jae 3f
    mov rdx, [rip + q_rows + VEC_ptr]
    mov edx, [rdx + rcx*4]
    imul rdx, rdx, QI_SIZE
    add rdx, [rip + q_items]
    cmp qword ptr [rdx + QI_detail], 0
    je 21f
    M eax, MI_48
    jmp 3f
21: inc rcx
    jmp 2b
3:  mov [rip + q_rowh], eax
    mov ebx, eax
    # the parts' heights
    xor eax, eax
    call has_title_row
    mov [rsp], eax              # 1: a title row
    call msg_or_prompt
    mov [rsp + 8], rax          # the line under the field (cstr or 0), its color in [rsp + 16]
    mov [rsp + 16], edx
    mov rax, [rip + q_rows + VEC_len]
    cmp rax, QK_ROWS
    jbe 31f
    mov eax, QK_ROWS
31: mov [rsp + 4], eax          # rows shown
    # fitted in the window
    mov eax, [rip + g_cv + CV_h]
    sub eax, r14d
    sub eax, [rip + g_mt + 4*MI_48]
    sub eax, [rip + g_mt + 4*MI_32]
    sub eax, [rip + g_mt + 4*MI_32]
    cdq
    idiv ebx
    mov ecx, 1
    cmp eax, ecx
    cmovl eax, ecx
    cmp eax, [rsp + 4]
    jge 32f
    mov [rsp + 4], eax
32: mov eax, [rsp + 4]
    mov [rip + q_shown], eax
    imul eax, ebx
    add eax, [rip + g_mt + 4*MI_48]
    cmp dword ptr [rsp + 4], 0
    je 33f
    add eax, [rip + g_mt + 4*MI_8]
33: cmp dword ptr [rsp], 0
    je 34f
    add eax, [rip + g_mt + 4*MI_32]
34: cmp qword ptr [rsp + 8], 0
    je 35f
    add eax, [rip + g_mt + 4*MI_20]
35: mov [rsp + 20], eax         # card h
    mov edi, r13d
    mov esi, r14d
    mov edx, r12d
    mov ecx, eax
    mov [rip + q_x], r13d
    mov [rip + q_y], r14d
    mov [rip + q_w], r12d
    mov [rip + q_h], eax
    call ui_card
    # a click outside dismisses it
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 4f
    mov edi, r13d
    mov esi, r14d
    mov edx, r12d
    mov ecx, [rsp + 20]
    call ui_in
    test eax, eax
    jnz 4f
    call qk_hide
    jmp .Lqd_ret
4:  mov r15d, r14d              # y as the parts go down
    cmp dword ptr [rsp], 0
    je 41f
    mov edi, r13d
    mov esi, r15d
    mov edx, r12d
    call title_row
    cmp qword ptr [rip + q_ext], 0
    je .Lqd_ret                 # a button closed it
    add r15d, [rip + g_mt + 4*MI_32]
41: # the field
    M eax, MI_8
    lea esi, [r13 + rax]
    lea edx, [r15 + rax]
    mov [rip + q_fy], edx
    mov ecx, r12d
    sub ecx, eax
    sub ecx, eax
    mov [rsp + 24], esi
    mov [rsp + 28], ecx
    test dword ptr [rip + q_flags], QF_BUSY     # room for the spinner
    jz 42f
    sub ecx, [rip + g_mt + 4*MI_32]
42: M r8d, MI_32
    xor r9d, r9d
    cmp dword ptr [rip + g_focus], FOCUS_QUICK
    sete r9b
    mov rax, [rip + q_placeholder]
    test rax, rax
    jnz 43f
    lea rax, [rip + .Lempty]
43: push rax
    push rax
    lea rdi, [rip + q_tf]
    mov dword ptr [rdi + TF_id], ID_QUICK + 0x3000
    test dword ptr [rip + q_flags], QF_PASSWORD
    jz 44f
    mov [rsp + 16 + 56], esi    # masked_field keeps none of the field's arguments
    mov [rsp + 16 + 60], edx
    mov [rsp + 16 + 64], ecx
    mov [rsp + 16 + 68], r9d
    call masked_field
    mov esi, [rsp + 16 + 56]
    mov edx, [rsp + 16 + 60]
    mov ecx, [rsp + 16 + 64]
    mov r9d, [rsp + 16 + 68]
    M r8d, MI_32
44: call ui_textfield
    add rsp, 16
    test dword ptr [rip + q_flags], QF_BUSY
    jz 45f
    mov edi, [rsp + 24]
    add edi, [rsp + 28]
    sub edi, [rip + g_mt + 4*MI_24]
    mov esi, [rip + q_fy]
    M edx, MI_32
    call notify_spinner
45: add r15d, [rip + g_mt + 4*MI_48]
    # the prompt or the message
    mov r8, [rsp + 8]
    test r8, r8
    jz 46f
    mov rdi, r8
    call strlen
    mov r9, rax
    mov eax, r12d
    sub eax, [rip + g_mt + 4*MI_32]
    push rax
    mov eax, [rsp + 8 + 16]
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, r13d
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, r15d
    sub edx, [rip + g_mt + 4*MI_4]
    M ecx, MI_20
    mov r8, [rsp + 16 + 8]
    call ui_text_v_fit
    add rsp, 16
    add r15d, [rip + g_mt + 4*MI_20]
46: mov [rip + q_ry], r15d
    # the rows
    call keep_active_in_view
    movsxd rax, dword ptr [rip + g_scroll_y]      # the wheel over the card scrolls them
    test rax, rax
    jz 5f
    mov edi, r13d
    mov esi, r14d
    mov edx, r12d
    mov ecx, [rsp + 20]
    call ui_in
    test eax, eax
    jz 5f
    movsxd rax, dword ptr [rip + g_scroll_y]
    cqo
    idiv rbx
    test eax, eax
    jnz 47f
    mov eax, 1                  # less than a row still moves one
    cmp dword ptr [rip + g_scroll_y], 0
    jg 47f
    mov eax, -1
47: add [rip + q_scroll], eax
5:  call clamp_scroll
    mov dword ptr [rip + q_hover], -1
    xor ecx, ecx
    mov [rsp + 32], ecx         # visible row
.Lqd_row:
    mov ecx, [rsp + 32]
    cmp ecx, [rsp + 4]
    jae .Lqd_ret
    mov eax, [rip + q_scroll]
    add eax, ecx
    cmp rax, [rip + q_rows + VEC_len]
    jae .Lqd_ret
    mov rdx, [rip + q_rows + VEC_ptr]
    mov eax, [rdx + rax*4]
    mov [rsp + 36], eax         # its item
    mov eax, ecx
    imul eax, ebx
    add eax, r15d
    mov [rsp + 40], eax         # its y
    mov edi, r13d
    mov esi, eax
    mov edx, r12d
    mov ecx, [rsp + 36]
    mov r8d, [rsp + 32]
    call draw_row
    cmp qword ptr [rip + q_ext], 0
    je .Lqd_ret                 # a click closed it
    inc dword ptr [rsp + 32]
    jmp .Lqd_row
.Lqd_ret:
    EPILOGUE

# has_title_row() -> eax 1 when the title row shows: a title, a step, Back, title buttons or
#   multi-select
has_title_row:
    mov eax, 1
    mov rcx, [rip + q_title]
    test rcx, rcx
    jz 1f
    cmp byte ptr [rcx], 0
    jne 9f
1:  cmp dword ptr [rip + q_stepm], 0
    jne 9f
    test dword ptr [rip + q_flags], QF_BACK | QF_MULTI
    jnz 9f
    cmp qword ptr [rip + q_nbtns], 0
    jne 9f
    xor eax, eax
9:  ret

# msg_or_prompt() -> rax the line under the field (the message about this text, else the prompt)
#   or 0, edx its color
msg_or_prompt:
    sub rsp, 8
    call msg_current
    test eax, eax
    js 1f
    COLOR edx, T_MUTED
    cmp eax, 1
    jne 11f
    COLOR edx, T_WARNING
11: cmp eax, 2
    jne 12f
    COLOR edx, T_ERROR
12: mov rax, [rip + q_msg]
    add rsp, 8
    ret
1:  COLOR edx, T_MUTED
    mov rax, [rip + q_prompt]
    test rax, rax
    jz 9f
    cmp byte ptr [rax], 0
    jne 9f
    xor eax, eax
9:  add rsp, 8
    ret

# keep_active_in_view(): after a move, the active row within the rows shown
keep_active_in_view:
    cmp dword ptr [rip + q_reveal], 0
    je 9f
    mov dword ptr [rip + q_reveal], 0
    mov eax, [rip + q_active]
    xor ecx, ecx
1:  cmp rcx, [rip + q_rows + VEC_len]
    jae 9f
    mov rdx, [rip + q_rows + VEC_ptr]
    cmp [rdx + rcx*4], eax
    je 2f
    inc rcx
    jmp 1b
2:  cmp ecx, [rip + q_scroll]
    jge 3f
    mov [rip + q_scroll], ecx
    ret
3:  mov edx, [rip + q_scroll]
    add edx, [rip + q_shown]
    cmp ecx, edx
    jl 9f
    sub ecx, [rip + q_shown]
    inc ecx
    mov [rip + q_scroll], ecx
9:  ret

# clamp_scroll(): within the rows
clamp_scroll:
    mov rax, [rip + q_rows + VEC_len]
    mov ecx, [rip + q_shown]
    sub eax, ecx
    mov ecx, [rip + q_scroll]
    cmp ecx, eax
    jle 1f
    mov ecx, eax
1:  test ecx, ecx
    jns 2f
    xor ecx, ecx
2:  mov [rip + q_scroll], ecx
    ret

# masked_field(rdi field) -> rdi a copy with one "*" for each character (a password)
masked_field:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + q_mask]     # the copy: its own text
    mov r12, [rdi + TF_sb + SB_ptr]
    mov r13, [rdi + TF_sb + SB_cap]
    mov rsi, rbx
    mov edx, TF_SIZE
    call memcpy
    lea rdi, [rip + q_mask]
    mov [rdi + TF_sb + SB_ptr], r12
    mov [rdi + TF_sb + SB_cap], r13
    mov qword ptr [rdi + TF_sb + SB_len], 0
    mov rdi, rbx
    mov rsi, [rbx + TF_cur]
    call chars_before
    mov [rip + q_mask + TF_cur], rax
    mov rdi, rbx
    mov rsi, [rbx + TF_anchor]
    call chars_before
    mov [rip + q_mask + TF_anchor], rax
    mov rdi, rbx
    mov rsi, [rbx + TF_sb + SB_len]
    call chars_before
    mov r12, rax
1:  test r12, r12
    jz 2f
    lea rdi, [rip + q_mask + TF_sb]
    mov esi, '*'
    call sb_push_byte
    dec r12
    jmp 1b
2:  lea rdi, [rip + q_mask]
    EPILOGUE

# chars_before(field, offset) -> rax the characters (UTF-8 lead bytes) before offset
chars_before:
    mov rdx, [rdi + TF_sb + SB_ptr]
    xor eax, eax
    test rdx, rdx
    jz 9f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    movzx r8d, byte ptr [rdx + rcx]
    and r8d, 0xc0
    cmp r8d, 0x80
    je 2f
    inc rax
2:  inc rcx
    jmp 1b
9:  ret

# title_row(x, y, w): ← Back, the title and "N/M", "K selected", the title buttons at the right
title_row:
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    M eax, MI_16
    add eax, edi
    mov [rsp + 12], eax         # x as parts go right
    mov dword ptr [rip + q_backx], -1
    test dword ptr [rip + q_flags], QF_BACK
    jz 1f
    mov eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_8]
    mov [rip + q_backx], eax
    mov edi, ID_QUICK + 0x1000 + 15
    mov esi, eax
    mov edx, [rsp + 4]
    M ecx, MI_28
    M r8d, MI_32
    call ui_btn
    mov [rsp + 16], eax
    test eax, UB_HOVER
    jz 11f
    mov edi, [rip + q_backx]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    M edx, MI_28
    M ecx, MI_24
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
11: mov edi, IC_BACK
    mov esi, [rip + q_backx]
    add esi, [rip + g_mt + 4*MI_6]
    M ecx, MI_16
    mov edx, [rip + g_mt + 4*MI_32]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    mov eax, [rip + g_mt + 4*MI_28]
    add eax, [rip + g_mt + 4*MI_4]
    add [rsp + 12], eax
    test dword ptr [rsp + 16], UB_CLICK
    jz 1f
    call qk_back
1:  # the title buttons from the right
    mov eax, [rsp]
    add eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 20], eax         # the right edge left of them
    mov rcx, [rip + q_nbtns]
    mov [rsp + 24], ecx
2:  dec dword ptr [rsp + 24]
    js 3f
    mov eax, [rsp + 24]
    imul eax, eax, QB_SIZE
    lea rcx, [rip + q_btns]
    lea r15, [rcx + rax]
    mov eax, [rip + g_mt + 4*MI_28]
    sub [rsp + 20], eax
    mov eax, [rsp + 20]
    mov [r15 + QB_x], eax
    mov edi, ID_QUICK + 0x1000
    add edi, [rsp + 24]
    mov esi, [rsp + 20]
    mov edx, [rsp + 4]
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_28
    M r8d, MI_28
    call ui_btn
    mov [rsp + 16], eax
    test eax, UB_HOVER
    jz 21f
    mov edi, [rsp + 20]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_2]
    M edx, MI_28
    M ecx, MI_28
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
21: mov edi, [r15 + QB_icon]
    cmp edi, -1
    jne 22f
    mov edi, IC_MORE
22: mov esi, [rsp + 20]
    add esi, [rip + g_mt + 4*MI_6]
    M ecx, MI_16
    mov edx, [rip + g_mt + 4*MI_32]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    # its tooltip
    mov rdi, [r15 + QB_tip]
    mov esi, [r15 + QB_tiplen]
    call tip_cstr
    mov r9, rax
    mov edi, ID_QUICK + 0x1000
    add edi, [rsp + 24]
    mov esi, [rsp + 20]
    mov edx, [rsp + 4]
    add edx, [rip + g_mt + 4*MI_28]
    M ecx, MI_28
    mov r8d, [rsp + 16]
    call tip_note_text
    test dword ptr [rsp + 16], UB_CLICK
    jz 2b
    mov rdi, [r15 + QB_key]
    mov esi, [r15 + QB_keylen]
    xor edx, edx
    call qk_button
    jmp 2b
3:  # "K selected" at the right of the text
    test dword ptr [rip + q_flags], QF_MULTI
    jz 4f
    lea rdi, [rip + tbuf]
    call sb_clear
    call checked_count
    lea rdi, [rip + tbuf]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + tbuf]
    lea rsi, [rip + .Lselected]
    call sb_push_cstr
    lea rdi, [rip + g_face_small]
    mov rsi, [rip + tbuf + SB_ptr]
    mov rdx, [rip + tbuf + SB_len]
    call text_width
    sub [rsp + 20], eax
    sub dword ptr [rsp + 20], 0
    COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 20]
    mov edx, [rsp + 16 + 4]
    M ecx, MI_32
    mov r8, [rip + tbuf + SB_ptr]
    mov r9, [rip + tbuf + SB_len]
    call ui_text_v
    add rsp, 16
    mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp + 20], eax
4:  # the title, then "N/M" in muted
    mov eax, [rsp + 20]
    sub eax, [rsp + 12]
    mov [rsp + 28], eax         # room
    jle 9f
    mov rdi, [rip + q_title]
    test rdi, rdi
    jz 5f
    call strlen
    mov r9, rax
    test r9, r9
    jz 5f
    mov [rsp + 32], r9
    lea rdi, [rip + g_face_ui]
    mov rsi, [rip + q_title]
    mov rdx, r9
    call text_width
    cmp eax, [rsp + 28]
    jle 41f
    mov eax, [rsp + 28]
41: mov [rsp + 40], eax         # its width as drawn (the length at [rsp + 32] is a qword)
    mov eax, [rsp + 28]
    push rax
    COLOR eax, T_FG
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16 + 12]
    mov edx, [rsp + 16 + 4]
    M ecx, MI_32
    mov r8, [rip + q_title]
    mov r9, [rsp + 16 + 32]
    call ui_text_v_fit
    add rsp, 16
    mov eax, [rsp + 40]
    add eax, [rip + g_mt + 4*MI_12]
    add [rsp + 12], eax
5:  cmp dword ptr [rip + q_stepm], 0
    je 9f
    lea rdi, [rip + tbuf]
    call sb_clear
    lea rdi, [rip + tbuf]
    mov esi, [rip + q_stepn]
    call sb_push_u64
    lea rdi, [rip + tbuf]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + tbuf]
    mov esi, [rip + q_stepm]
    call sb_push_u64
    mov eax, [rsp + 20]
    sub eax, [rsp + 12]
    jle 9f
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 12]
    mov edx, [rsp + 16 + 4]
    M ecx, MI_32
    mov r8, [rip + tbuf + SB_ptr]
    mov r9, [rip + tbuf + SB_len]
    call ui_text_v_fit
    add rsp, 16
9:  EPILOGUE

# checked_count() -> rax the items checked
checked_count:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + q_nitems]
    jae 9f
    imul rdx, rcx, QI_SIZE
    add rdx, [rip + q_items]
    test dword ptr [rdx + QI_flags], QIF_CHECKED
    jz 2f
    test dword ptr [rdx + QI_flags], QIF_SEP
    jnz 2f
    inc rax
2:  inc rcx
    jmp 1b
9:  ret

# tip_cstr(ptr, len) -> rax a cstr of it (tip_buf, 200 bytes at most)
tip_cstr:
    cmp rsi, 200
    jbe 1f
    mov esi, 200
1:  lea rax, [rip + tip_buf]
    xor ecx, ecx
2:  cmp rcx, rsi
    jae 3f
    mov dl, [rdi + rcx]
    mov [rax + rcx], dl
    inc rcx
    jmp 2b
3:  mov byte ptr [rax + rcx], 0
    ret

# draw_row(x, y, w, item, visible row): a separator (its label, a line) or an item: the active or
#   hovered background, a checkbox (multi), the icon, the label with matched characters, the
#   description, the detail line under it, item buttons on the active or hovered row; a click
#   makes it active and accepts it (multi: toggles it)
draw_row:
    PROLOGUE 96
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov [rsp + 16], r8d
    movsxd rax, ecx
    imul rax, rax, QI_SIZE
    add rax, [rip + q_items]
    mov r15, rax                # the item
    test dword ptr [r15 + QI_flags], QIF_SEP
    jz 1f
    # a separator: its label in small muted text, a line after it
    mov eax, [rip + g_mt + 4*MI_16]
    add eax, [rsp]
    mov [rsp + 20], eax
    mov ecx, [r15 + QI_lablen]
    test ecx, ecx
    jz 11f
    lea rdi, [rip + g_face_small]
    mov rsi, [r15 + QI_label]
    mov edx, ecx
    call text_width
    mov [rsp + 24], eax
    mov eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_32]
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 20]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rip + q_rowh]
    mov r8, [r15 + QI_label]
    mov r9d, [r15 + QI_lablen]
    call ui_text_v_fit
    add rsp, 16
    mov eax, [rsp + 24]
    add eax, [rip + g_mt + 4*MI_8]
    add [rsp + 20], eax
11: mov edi, [rsp + 20]
    mov esi, [rip + q_rowh]
    sar esi, 1
    add esi, [rsp + 4]
    mov edx, [rsp]
    add edx, [rsp + 8]
    sub edx, [rip + g_mt + 4*MI_16]
    sub edx, edi
    jle 9f
    mov ecx, 1
    COLOR r8d, T_BORDER
    call gfx_fill
    jmp 9f
1:  # the pointer
    mov edi, ID_QUICK
    add edi, [rsp + 16]
    M eax, MI_6
    mov esi, [rsp]
    add esi, eax
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    sub ecx, eax
    sub ecx, eax
    mov r8d, [rip + q_rowh]
    call ui_btn
    mov [rsp + 20], eax
    test eax, UB_HOVER
    jz 12f
    mov eax, [rsp + 12]
    mov [rip + q_hover], eax
12: # item buttons on the active or hovered row: hit tested first (a press on one is not the row's)
    mov dword ptr [rsp + 28], 0     # their width
    mov eax, [rsp + 12]
    cmp eax, [rip + q_active]
    je 13f
    test dword ptr [rsp + 20], UB_HOVER
    jz 14f
13: mov edi, [rsp]
    add edi, [rsp + 8]
    sub edi, [rip + g_mt + 4*MI_12]
    mov esi, [rsp + 4]
    mov rdx, r15
    mov ecx, [rsp + 16]
    call item_buttons
    mov [rsp + 28], eax
    test edx, edx
    jz 14f
    and dword ptr [rsp + 20], ~(UB_PRESS | UB_CLICK)
    cmp qword ptr [rip + q_ext], 0
    je 9f
14: test dword ptr [rsp + 20], UB_PRESS
    jz 15f
    mov eax, [rsp + 12]
    mov [rip + q_active], eax
15: # the background
    mov eax, [rsp + 12]
    M ecx, MI_6
    mov edi, [rsp]
    add edi, ecx
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    sub edx, ecx
    sub edx, ecx
    mov ecx, [rip + q_rowh]
    M r8d, MI_RADIUS
    cmp eax, [rip + q_active]
    jne 16f
    COLOR r9d, T_ACTIVE
    call gfx_round_rect
    jmp 17f
16: test dword ptr [rsp + 20], UB_HOVER
    jz 17f
    COLOR r9d, T_HOVER
    call gfx_round_rect
17: # the buttons drawn again over the background (they were laid out before it)
    cmp dword ptr [rsp + 28], 0
    je 18f
    mov edi, [rsp]
    add edi, [rsp + 8]
    sub edi, [rip + g_mt + 4*MI_12]
    mov esi, [rsp + 4]
    mov rdx, r15
    mov ecx, -1
    call item_buttons
18: mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 24], eax         # x as parts go right
    # the line's top: one line centered, or two (label, detail)
    mov eax, [rip + q_rowh]
    mov [rsp + 32], eax         # the label line's height
    cmp qword ptr [r15 + QI_detail], 0
    je 2f
    M eax, MI_28
    mov [rsp + 32], eax
2:  # a checkbox in multi mode
    test dword ptr [rip + q_flags], QF_MULTI
    jz 3f
    M ecx, MI_14
    mov edi, [rsp + 24]
    mov esi, [rsp + 32]
    sub esi, ecx
    sar esi, 1
    add esi, [rsp + 4]
    mov edx, ecx
    M r8d, MI_3
    COLOR r9d, T_MUTED
    COLOR eax, T_INPUT
    test dword ptr [r15 + QI_flags], QIF_CHECKED
    jz 21f
    COLOR r9d, T_ACCENT
    COLOR eax, T_ACCENT
21: push rax
    push rax
    call gfx_frame
    add rsp, 16
    test dword ptr [r15 + QI_flags], QIF_CHECKED
    jz 22f
    M ecx, MI_14
    mov edi, IC_CHECK
    mov esi, [rsp + 24]
    mov edx, [rsp + 32]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_ACCENT_FG
    call icon_draw
22: mov eax, [rip + g_mt + 4*MI_14]
    add eax, [rip + g_mt + 4*MI_8]
    add [rsp + 24], eax
3:  # the icon
    mov eax, [r15 + QI_icon]
    cmp eax, -1
    je 4f
    test eax, NDI_FILE
    jz 31f
    mov edi, eax
    and edi, 0xff
    shr eax, 8
    and eax, 0xff
    lea rdx, [rip + g_theme]
    mov r8d, [rdx + rax*4]
    jmp 32f
31: mov [rsp + 36], eax
    mov edi, [r15 + QI_icolor]
    mov esi, T_MUTED
    call tree_color
    mov r8d, eax
    mov edi, [rsp + 36]
32: M ecx, MI_16
    mov esi, [rsp + 24]
    mov edx, [rsp + 32]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    call icon_draw
    mov eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_8]
    add [rsp + 24], eax
4:  # the label, highlighted, then the description: within the buttons' left edge
    mov eax, [rsp]
    add eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_16]
    sub eax, [rsp + 28]
    mov [rsp + 40], eax         # the right edge
    sub eax, [rsp + 24]
    jle 6f
    mov edi, [rsp + 24]
    mov esi, [rsp + 4]
    mov edx, eax
    mov ecx, [rsp + 32]
    call gfx_clip_push
    mov rdi, r15
    mov esi, [rsp + 24]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 32]
    call draw_label
    mov [rsp + 24], eax
    call gfx_clip_pop
    cmp qword ptr [r15 + QI_desc], 0
    je 6f
    add dword ptr [rsp + 24], 0
    mov eax, [rip + g_mt + 4*MI_12]
    add [rsp + 24], eax
    mov eax, [rsp + 40]
    sub eax, [rsp + 24]
    jle 6f
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 24]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 32]
    mov r8, [r15 + QI_desc]
    mov r9d, [r15 + QI_desclen]
    call ui_text_v_fit
    add rsp, 16
6:  # the detail line
    cmp qword ptr [r15 + QI_detail], 0
    je 7f
    mov eax, [rsp + 40]
    mov ecx, [rsp]
    add ecx, [rip + g_mt + 4*MI_16]
    sub eax, ecx
    jle 7f
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_16]
    test dword ptr [rip + q_flags], QF_MULTI     # under the label, past the checkbox and icon
    jz 61f
    add esi, [rip + g_mt + 4*MI_14]
    add esi, [rip + g_mt + 4*MI_8]
61: mov edx, [rsp + 16 + 4]
    add edx, [rip + g_mt + 4*MI_24]
    M ecx, MI_20
    mov r8, [r15 + QI_detail]
    mov r9d, [r15 + QI_detaillen]
    call ui_text_v_fit
    add rsp, 16
7:  # a click: multi toggles, else the item is accepted
    test dword ptr [rsp + 20], UB_CLICK
    jz 9f
    mov eax, [rsp + 12]
    mov [rip + q_active], eax
    test dword ptr [rip + q_flags], QF_MULTI
    jz 71f
    mov edi, eax
    call toggle
    jmp 9f
71: cmp dword ptr [rip + q_mode], 1
    je 9f
    call qk_accept
9:  EPILOGUE

# item_buttons(right, y, QI*, visible row or -1) -> eax their width, edx 1 when the pointer pressed
#   one (with visible row -1 they are only drawn): the item's "button KEY ICON LEN" records, right
#   to left from right
item_buttons:
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov rbx, rdx
    mov [rsp + 8], ecx
    mov dword ptr [rsp + 12], 0     # width
    mov dword ptr [rsp + 16], 0     # pressed
    mov dword ptr [rsp + 20], 0     # index
    mov r12, [rbx + QI_extra]
    mov r13d, [rbx + QI_xlen]
    add r13, r12
1:  cmp r12, r13
    jae 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + q_rr2]
    call tree_rec_read
    test rax, rax
    jz 9f
    mov r12, rax
    lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_button]
    call tree_rec_is
    test eax, eax
    jz 1b
    cmp qword ptr [rip + q_rr2 + RR_n], 4
    jne 1b
    mov eax, [rip + g_mt + 4*MI_28]
    add [rsp + 12], eax
    mov eax, [rsp]
    sub eax, [rsp + 12]
    mov [rsp + 24], eax         # its x
    mov edi, ID_QUICK + 0x2000
    add edi, [rsp + 20]
    mov esi, eax
    mov edx, [rip + q_rowh]
    sub edx, [rip + g_mt + 4*MI_28]
    sar edx, 1
    add edx, [rsp + 4]
    mov [rsp + 28], edx
    M ecx, MI_28
    M r8d, MI_28
    cmp dword ptr [rsp + 8], -1
    je 2f
    call ui_btn
    mov [rsp + 32], eax
    test eax, UB_PRESS | UB_CLICK
    jz 11f
    mov dword ptr [rsp + 16], 1
11: test dword ptr [rsp + 32], UB_CLICK
    jz 12f
    mov rdi, [rip + q_rr2 + 16]
    mov rsi, [rip + q_rr2 + 24]
    mov rdx, rbx
    call qk_button
12: inc dword ptr [rsp + 20]
    jmp 1b
2:  # drawn: the hover, the icon (the tooltip with it)
    mov edi, ID_QUICK + 0x2000
    add edi, [rsp + 20]
    cmp [rip + g_hot], edi
    jne 21f
    mov edi, [rsp + 24]
    mov esi, [rsp + 28]
    M edx, MI_28
    M ecx, MI_28
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
    mov rdi, [rip + q_rr2 + RR_data]
    mov rsi, [rip + q_rr2 + RR_len]
    call tip_cstr
    mov r9, rax
    mov edi, ID_QUICK + 0x2000
    add edi, [rsp + 20]
    mov esi, [rsp + 24]
    mov edx, [rsp + 28]
    add edx, [rip + g_mt + 4*MI_28]
    M ecx, MI_28
    mov r8d, UB_HOVER
    call tip_note_text
21: mov rdi, [rip + q_rr2 + 32]
    mov rsi, [rip + q_rr2 + 40]
    call tree_icon_code
    mov edi, eax
    cmp edi, -1
    jne 22f
    mov edi, IC_MORE
22: test edi, NDI_FILE
    jz 23f
    mov edi, IC_MORE
23: mov esi, [rsp + 24]
    add esi, [rip + g_mt + 4*MI_6]
    mov edx, [rsp + 28]
    add edx, [rip + g_mt + 4*MI_6]
    M ecx, MI_16
    COLOR r8d, T_MUTED
    call icon_draw
    inc dword ptr [rsp + 20]
    jmp 1b
9:  mov eax, [rsp + 12]
    mov edx, [rsp + 16]
    EPILOGUE

# draw_label(QI*, x, y, h) -> eax the x after it: the label, its matched characters (the query as a
#   fuzzy subsequence, or with nofilter its hl ranges) in the accent color
draw_label:
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], esi              # x
    mov [rsp + 4], edx          # y
    mov [rsp + 8], ecx          # h
    lea rdi, [rip + q_tf]
    call tf_text
    mov [rsp + 16], rax         # the query
    mov [rsp + 24], rdx
    test dword ptr [rip + q_flags], QF_NOFILTER
    jz 1f
    mov qword ptr [rsp + 24], 0
1:  lea rcx, [rip + g_face_ui]
    mov eax, [rsp + 8]
    sub eax, [rcx + FACE_ascent]
    sub eax, [rcx + FACE_descent]
    sar eax, 1
    add eax, [rsp + 4]
    add eax, [rcx + FACE_ascent]
    mov [rsp + 32], eax         # the baseline
    mov r12, [rbx + QI_label]
    mov r13d, [rbx + QI_lablen]
    xor r14d, r14d              # label index
    xor r15d, r15d              # query index
2:  cmp r14, r13
    jae 9f
    lea rdi, [r12 + r14]
    mov rsi, r13
    sub rsi, r14
    call utf8_decode
    mov [rsp + 36], edx         # its bytes
    mov [rsp + 40], eax         # the code point
    COLOR r9d, T_FG
    test dword ptr [rip + q_flags], QF_NOFILTER
    jz 3f
    mov rdi, rbx                # nofilter: its hl ranges
    mov esi, r14d
    call in_hl
    test eax, eax
    jz 5f
    COLOR r9d, T_ACCENT
    jmp 5f
3:  cmp r15, [rsp + 24]
    jae 5f
    mov rcx, [rsp + 16]         # the next query character, both folded
    movzx eax, byte ptr [rcx + r15]
    movzx ecx, byte ptr [r12 + r14]
    lea edx, [rax - 'A']
    cmp edx, 25
    ja 31f
    or eax, 0x20
31: lea edx, [rcx - 'A']
    cmp edx, 25
    ja 32f
    or ecx, 0x20
32: cmp eax, ecx
    jne 5f
    COLOR r9d, T_ACCENT
    add r15d, [rsp + 36]
5:  mov [rsp + 44], r9d
    lea rdi, [rip + g_face_ui]
    lea rsi, [r12 + r14]
    mov edx, [rsp + 36]
    call text_width
    mov [rsp + 48], eax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp]
    mov edx, [rsp + 32]
    lea rcx, [r12 + r14]
    mov r8d, [rsp + 36]
    mov r9d, [rsp + 44]
    call text_draw
    mov eax, [rsp + 48]
    add [rsp], eax
    add r14d, [rsp + 36]
    jmp 2b
9:  mov eax, [rsp]
    EPILOGUE

# in_hl(QI*, byte offset) -> eax 1 when one of its "hl FROM TO 0" records covers it
in_hl:
    PROLOGUE
    mov rbx, rdi
    mov r14d, esi
    mov r12, [rbx + QI_extra]
    mov r13d, [rbx + QI_xlen]
    add r13, r12
1:  cmp r12, r13
    jae 8f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + q_rr2]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r12, rax
    lea rdi, [rip + q_rr2]
    xor esi, esi
    lea rdx, [rip + .Lr_hl]
    call tree_rec_is
    test eax, eax
    jz 1b
    cmp qword ptr [rip + q_rr2 + RR_n], 4
    jne 1b
    lea rdi, [rip + q_rr2]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 1b
    cmp r14, rax
    jb 1b
    lea rdi, [rip + q_rr2]
    mov esi, 2
    call tree_rec_num
    test edx, edx
    jz 1b
    cmp r14, rax
    jae 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- headless ----------------

# quick_dump(sb): "quick Q title=T step=N/M mode=pick|input flags=F seq=S waiting=0|1 field=TEXT
#   [msg=SEV:TEXT] [prompt=TEXT] at=X,Y size=WxH" then a line per row shown or not: "row I id=ID
#   label=L [sep] [checked] [active] [visible at=X,Y]"; "button KEY at=X,Y" per title button; or
#   "quick none"
FN quick_dump
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rip + q_ext], 0
    jne 1f
    mov rdi, rbx
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
    EPILOGUE
1:  mov rdi, rbx
    lea rsi, [rip + .Ld_quick]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_id]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_title]
    call sb_push_cstr
    mov rsi, [rip + q_title]
    test rsi, rsi
    jz 11f
    mov rdi, rbx
    call sb_push_cstr
11: mov rdi, rbx
    lea rsi, [rip + .Ld_step]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_stepn]
    call sb_push_u64
    mov rdi, rbx
    mov esi, '/'
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rip + q_stepm]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_mode_pick]
    cmp dword ptr [rip + q_mode], 1
    jne 12f
    lea rsi, [rip + .Ld_mode_input]
12: call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_flags]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_flags]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_seq]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_seq]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_waiting]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_waiting]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_focus]
    call sb_push_cstr
    xor esi, esi
    cmp dword ptr [rip + g_focus], FOCUS_QUICK
    sete sil
    mov rdi, rbx
    call sb_push_u64
    call msg_current
    test eax, eax
    js 13f
    mov [rsp], eax
    mov rdi, rbx
    lea rsi, [rip + .Ld_msg]
    call sb_push_cstr
    mov eax, [rsp]
    lea rcx, [rip + sev_words]
    mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, ':'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + q_msg]
    call sb_push_cstr
13: mov rsi, [rip + q_prompt]
    test rsi, rsi
    jz 14f
    push rsi
    push rsi
    mov rdi, rbx
    lea rsi, [rip + .Ld_prompt]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, rbx
    call sb_push_cstr
14: mov rdi, rbx
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_x]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rip + q_y]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_size]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_w]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 'x'
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rip + q_h]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_field]
    call sb_push_cstr
    lea rdi, [rip + q_tf]
    call tf_text
    mov rdi, rbx
    mov rsi, rax
    call sb_push
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    # the rows
    xor r12d, r12d
2:  cmp r12, [rip + q_rows + VEC_len]
    jae 5f
    mov rax, [rip + q_rows + VEC_ptr]
    mov r13d, [rax + r12*4]
    imul r14, r13, QI_SIZE
    add r14, [rip + q_items]
    mov rdi, rbx
    lea rsi, [rip + .Ld_row]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_id]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r14 + QI_id]
    mov edx, [r14 + QI_idlen]
    call sb_push
    mov rdi, rbx
    lea rsi, [rip + .Ld_label]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r14 + QI_label]
    mov edx, [r14 + QI_lablen]
    call sb_push
    test dword ptr [r14 + QI_flags], QIF_SEP
    jz 21f
    mov rdi, rbx
    lea rsi, [rip + .Ld_sep]
    call sb_push_cstr
21: test dword ptr [r14 + QI_flags], QIF_CHECKED
    jz 22f
    mov rdi, rbx
    lea rsi, [rip + .Ld_checked]
    call sb_push_cstr
22: cmp r13d, [rip + q_active]
    jne 23f
    mov rdi, rbx
    lea rsi, [rip + .Ld_active]
    call sb_push_cstr
23: mov eax, r12d               # in view: where
    sub eax, [rip + q_scroll]
    js 24f
    cmp eax, [rip + q_shown]
    jae 24f
    imul eax, [rip + q_rowh]
    add eax, [rip + q_ry]
    mov [rsp], eax
    mov rdi, rbx
    lea rsi, [rip + .Ld_vat]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_x]
    add esi, [rip + g_mt + 4*MI_6]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rsp]
    call sb_push_u64
24: mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    inc r12
    jmp 2b
5:  xor r12d, r12d              # the title buttons
51: cmp r12, [rip + q_nbtns]
    jae 6f
    imul r14, r12, QB_SIZE
    lea rax, [rip + q_btns]
    add r14, rax
    mov rdi, rbx
    lea rsi, [rip + .Ld_button]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r14 + QB_key]
    mov edx, [r14 + QB_keylen]
    call sb_push
    mov rdi, rbx
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r14 + QB_x]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rip + q_y]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    inc r12
    jmp 51b
6:  cmp dword ptr [rip + q_backx], -1
    je 9f
    mov rdi, rbx
    lea rsi, [rip + .Ld_back]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [rip + q_backx]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [rip + q_y]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

# quick_timeout() -> ms until the busy spinner moves, -1 without one
FN quick_timeout
    mov eax, -1
    cmp qword ptr [rip + q_ext], 0
    je 9f
    test dword ptr [rip + q_flags], QF_BUSY
    jz 9f
    mov eax, 300
9:  ret

.data
.p2align 3
rec_table:
    .quad .Lr_title, ck_line200, ap_title
    .quad .Lr_step, ck_step, ap_step
    .quad .Lr_placeholder, ck_line200, ap_placeholder
    .quad .Lr_prompt, ck_line1000, ap_prompt
    .quad .Lr_value, ck_value, ap_value
    .quad .Lr_mode, ck_mode, ap_mode
    .quad .Lr_flags, ck_flags, ap_flags
    .quad .Lr_msg, ck_msg, ap_msg
    .quad .Lr_buttons, ck_buttons, ap_buttons
    .quad .Lr_items, ck_items, ap_items
    .quad .Lr_active, ck_active, ap_active
    .quad 0, 0, 0
flag_words: .quad .Lf_multi, .Lf_back, .Lf_busy, .Lf_nofilter, .Lf_mdesc, .Lf_mdetail, .Lf_password, 0
sev_words: .quad .Lw_info, .Lw_warning, .Lw_error

.bss
.p2align 3
num3: .zero 24
item_tmp: .zero QI_SIZE
acc_body: .zero SB_SIZE
tbuf: .zero SB_SIZE
tip_buf: .zero 208

.section .rodata
key_ok:                         # [A-Za-z0-9_.-]
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0
    .byte 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1
    .byte 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
.Ldash: .asciz "-"
.Lempty: .asciz ""
.Lr_title: .asciz "title"
.Lr_step: .asciz "step"
.Lr_placeholder: .asciz "placeholder"
.Lr_prompt: .asciz "prompt"
.Lr_value: .asciz "value"
.Lr_mode: .asciz "mode"
.Lr_flags: .asciz "flags"
.Lr_msg: .asciz "msg"
.Lr_buttons: .asciz "buttons"
.Lr_items: .asciz "items"
.Lr_active: .asciz "active"
.Lr_desc: .asciz "desc"
.Lr_detail: .asciz "detail"
.Lr_picked: .asciz "picked"
.Lr_always: .asciz "always"
.Lr_icon: .asciz "icon"
.Lr_button: .asciz "button"
.Lr_hl: .asciz "hl"
.Lw_pick: .asciz "pick"
.Lw_input: .asciz "input"
.Lw_item: .asciz "item"
.Lw_sep: .asciz "sep"
.Lw_info: .asciz "info"
.Lw_warning: .asciz "warning"
.Lw_error: .asciz "error"
.Lf_multi: .asciz "multi"
.Lf_back: .asciz "back"
.Lf_busy: .asciz "busy"
.Lf_nofilter: .asciz "nofilter"
.Lf_mdesc: .asciz "match-desc"
.Lf_mdetail: .asciz "match-detail"
.Lf_password: .asciz "password"
.Le_quick: .asciz "0 quick "
.Le_hide: .asciz "hide"
.Le_value: .asciz "value"
.Le_active: .asciz "active"
.Le_accept: .asciz "accept"
.Le_back: .asciz "back"
.Le_button: .asciz "button"
.Lselected: .asciz " selected"
.Ld_none: .asciz "quick none\n"
.Ld_quick: .asciz "quick "
.Ld_title: .asciz " title="
.Ld_step: .asciz " step="
.Ld_mode_pick: .asciz " mode=pick"
.Ld_mode_input: .asciz " mode=input"
.Ld_flags: .asciz " flags="
.Ld_seq: .asciz " seq="
.Ld_waiting: .asciz " waiting="
.Ld_focus: .asciz " focus="
.Ld_msg: .asciz " msg="
.Ld_prompt: .asciz " prompt="
.Ld_at: .asciz " at="
.Ld_size: .asciz " size="
.Ld_field: .asciz " field="
.Ld_row: .asciz "row "
.Ld_id: .asciz " id="
.Ld_label: .asciz " label="
.Ld_sep: .asciz " sep"
.Ld_checked: .asciz " checked"
.Ld_active: .asciz " active"
.Ld_vat: .asciz " at="
.Ld_button: .asciz "button "
.Ld_back: .asciz "back at="
