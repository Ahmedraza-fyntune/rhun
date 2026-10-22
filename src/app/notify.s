# notifications and progress (features notify and progress): cards stacked at the bottom right
# above the status bar (newest at the bottom, 4 shown, "+N more" over them), with a severity mark,
# a wrapped message, a muted detail line, up to 3 buttons and a close button; info cards go after
# 8 s and warnings after 12 s (the pointer over a card holds it), errors, cards with buttons and
# sticky ones stay. Progress shows in the status bar (a click opens its card), as a card with a bar
# and Cancel, or as a bar at the top of one of its extension's views; nothing shows for progress
# that ends within 500 ms.
#
# Built-in code uses the same:
#   id = notify_add(ext or 0, SEV_ERROR|SEV_WARNING|SEV_INFO, msg, len); notify_button(id, title cstr,
#        fn(ctx, id), ctx); notify_close(id)
#   id = progress_begin(ext or 0, NPW_STATUS|NPW_NOTE, title cstr, cancel fn(ctx, id) or 0, ctx);
#        progress_update(id, percent or -1, msg, len); progress_end(id)
.include "rhun.inc"

.equ NC_MAX, 64
.equ NC_PER_EXT, 16
.equ NC_SHOWN, 4
.equ ID_NOTE_MD, 0x6a0000         # + card index * 4096: a Markdown message's links
.equ NC_MSG_MAX, 2000
.equ NP_MAX, 64
.equ NP_PER_EXT, 8
.equ NP_DELAY_MS, 500
.equ NP_CANCEL_MS, 10000
.equ SPIN_MS, 300
.equ ID_NT, 0x590000             # + card << 4 + i: a card's buttons (0 close, 1..3 its buttons, 8 body)
.equ ID_PG_STATUS, 0x58f000      # + i: a progress entry in the status bar
.equ NPW_STATUS, 1
.equ NPW_NOTE, 2
.equ NPW_VIEW, 3

# a notification
STRUCT
F NC_ext, 8             # its extension, 0 for rhun's own
F NC_msg, 8             # owned cstr
F NC_detail, 8          # owned cstr or 0
F NC_btitle, 24         # owned cstrs, 0 past the last button
F NC_bref, 24           # a button's command reference (CRF, owned) or 0
F NC_bfn, 24            # built-in: a button's callback fn(ctx, id), or 0
F NC_bctx, 8
F NC_created, 8
F NC_deadline, 8        # time_ms when it goes, 0: it stays
F NC_id, 4              # 0: the slot is free
F NC_sev, 4             # SEV_*
F NC_nbtn, 4
F NC_sticky, 4
F NC_x, 4               # where it was last drawn
F NC_y, 4
F NC_w, 4
F NC_h, 4
F NC_pg, 4              # a progress card: its PG slot + 1
F NC_order, 4           # when it came, among cards and progress (ord_seq)
F NC_md, 8              # its message as Markdown (an extension with markdown agreed), made when drawn, or 0
ENDSTRUCT NC_SIZE

# a progress
STRUCT
F NP_ext, 8
F NP_title, 8           # owned cstr
F NP_msg, 8             # owned cstr or 0
F NP_fn, 8              # built-in: its Cancel's callback fn(ctx, id), or 0
F NP_ctx, 8
F NP_started, 8
F NP_cancel_at, 8       # when Cancel was pressed (it goes 10 s later), 0
F NP_id, 4              # 0: free
F NP_where, 4           # NPW_*
F NP_slot, 4            # NPW_VIEW: the view's instance slot
F NP_percent, 4         # 0-100, -1 indeterminate
F NP_cancel, 4          # 1: it can be cancelled
F NP_open, 4            # its status entry's card is open
F NP_order, 4           # when it came, among cards and progress (ord_seq)
F NP_pad, 4
ENDSTRUCT NP_SIZE

.bss
.p2align 3
nts: .zero NC_SIZE * NC_MAX
pgs: .zero NP_SIZE * NP_MAX
nt_seq: .long 0
pg_seq: .long 0
ord_seq: .long 0
nt_stack: .zero 16              # last frame's cards: x, y, w, h (the pointer's hole this frame)
nt_fbtn: .long 0                # its button (0 none)
nt_order: .zero 4 * (NC_MAX + NP_MAX)   # the cards shown, oldest first: NT slot, or PG slot | 0x100
nt_count: .long 0
.p2align 3
nbuf: .zero SB_SIZE
rr_nt: .zero RR_SIZE
wrapbuf: .zero 8 * 16           # a message's wrapped lines: start, len (u32 each)

.data
nt_focus: .long -1              # the card with the keyboard (an index among those shown), -1
nt_place: .long -1              # the hidden place item the keyboard reaches the cards through

.text

# ---------------- notifications ----------------

# nt_at(i) -> rax NT*
nt_at:
    imul rax, rdi, NC_SIZE
    lea rcx, [rip + nts]
    add rax, rcx
    ret

# pg_at(i) -> rax PG*
pg_at:
    imul rax, rdi, NP_SIZE
    lea rcx, [rip + pgs]
    add rax, rcx
    ret

# nt_by_id(ext, id) -> rax NT* of that extension, or 0
nt_by_id:
    xor eax, eax
    lea rcx, [rip + nts]
1:  cmp eax, NC_MAX
    jae 8f
    cmp [rcx + NC_id], esi
    jne 2f
    test esi, esi
    jz 2f
    cmp [rcx + NC_ext], rdi
    jne 2f
    mov rax, rcx
    ret
2:  add rcx, NC_SIZE
    inc eax
    jmp 1b
8:  xor eax, eax
    ret

# nt_free(NT*): its bytes, the slot free
nt_free:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + NC_md]
    call md_free
    mov rdi, [rbx + NC_msg]
    call mem_free
    mov rdi, [rbx + NC_detail]
    call mem_free
    xor r12d, r12d
1:  cmp r12d, 3
    jae 2f
    mov rdi, [rbx + NC_btitle + r12*8]
    call mem_free
    mov rdi, [rbx + NC_bref + r12*8]
    call cmdref_free
    inc r12d
    jmp 1b
2:  mov rdi, rbx
    xor esi, esi
    mov edx, NC_SIZE
    call memset
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# nt_clear_content(NT*): its message, detail and buttons go (for new content)
nt_clear_content:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + NC_md]
    call md_free
    mov qword ptr [rbx + NC_md], 0
    mov rdi, [rbx + NC_msg]
    call mem_free
    mov rdi, [rbx + NC_detail]
    call mem_free
    mov qword ptr [rbx + NC_msg], 0
    mov qword ptr [rbx + NC_detail], 0
    xor r12d, r12d
1:  cmp r12d, 3
    jae 2f
    mov rdi, [rbx + NC_btitle + r12*8]
    call mem_free
    mov rdi, [rbx + NC_bref + r12*8]
    call cmdref_free
    mov qword ptr [rbx + NC_btitle + r12*8], 0
    mov qword ptr [rbx + NC_bref + r12*8], 0
    mov qword ptr [rbx + NC_bfn + r12*8], 0
    inc r12d
    jmp 1b
2:  mov dword ptr [rbx + NC_nbtn], 0
    mov dword ptr [rbx + NC_sticky], 0
    EPILOGUE

# nt_alloc(ext) -> rax a free NT with a new id, or 0 when all are taken (or 16 are the extension's)
nt_alloc:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d              # its cards
    mov r13, -1                 # a free slot
    xor ecx, ecx
1:  cmp ecx, NC_MAX
    jae 3f
    mov edi, ecx
    push rcx
    push rcx
    call nt_at
    pop rcx
    pop rcx
    cmp dword ptr [rax + NC_id], 0
    jne 2f
    cmp r13, -1
    jne 21f
    mov r13, rax
    jmp 21f
2:  cmp [rax + NC_ext], rbx
    jne 21f
    test rbx, rbx
    jz 21f
    inc r12d
21: inc ecx
    jmp 1b
3:  cmp r13, -1
    je 8f
    cmp r12d, NC_PER_EXT
    jae 8f
    mov rdi, r13
    xor esi, esi
    mov edx, NC_SIZE
    call memset
    mov [r13 + NC_ext], rbx
    inc dword ptr [rip + nt_seq]
    mov eax, [rip + nt_seq]
    mov [r13 + NC_id], eax
    inc dword ptr [rip + ord_seq]
    mov eax, [rip + ord_seq]
    mov [r13 + NC_order], eax
    call time_ms
    mov [r13 + NC_created], rax
    mov dword ptr [rip + g_dirty], 1
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# nt_deadline(NT*): when it goes: info 8 s, warning 12 s; errors, buttons and sticky stay
nt_deadline:
    push rbx
    mov rbx, rdi
    mov qword ptr [rbx + NC_deadline], 0
    cmp dword ptr [rbx + NC_sev], SEV_ERROR
    je 9f
    cmp dword ptr [rbx + NC_nbtn], 0
    jne 9f
    cmp dword ptr [rbx + NC_sticky], 0
    jne 9f
    cmp dword ptr [rbx + NC_pg], 0
    jne 9f
    call time_ms
    mov ecx, 8000
    cmp dword ptr [rbx + NC_sev], SEV_WARNING
    jne 1f
    mov ecx, 12000
1:  add rax, rcx
    mov [rbx + NC_deadline], rax
9:  pop rbx
    ret

# nt_body(NT*, ext, body, len) -> eax 1 when the body reads: MSG_LEN EXTRA_LEN LF MSG EXTRA with
#   records detail LEN, sticky 0, and up to 3 button LEN + title each optionally followed by its
#   command NAME ARGS_LEN record
nt_body:
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov r12, rdx
    lea r13, [rdx + rcx]
    # the header
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call parse_u64
    test rdx, rdx
    jz 8f
    mov r14, rax                # MSG_LEN
    add r12, rdx
    cmp r12, r13
    jae 8f
    cmp byte ptr [r12], ' '
    jne 8f
    inc r12
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call parse_u64
    test rdx, rdx
    jz 8f
    mov r15, rax                # EXTRA_LEN
    add r12, rdx
    cmp r12, r13
    jae 8f
    cmp byte ptr [r12], 10
    jne 8f
    inc r12
    mov rax, r14
    add rax, r15
    mov rcx, r13
    sub rcx, r12
    cmp rax, rcx
    jne 8f
    # the message: at most 2000 bytes, whole characters
    mov rdi, rbx
    call nt_clear_content
    mov rdi, r14
    mov rsi, r12
    mov edx, NC_MSG_MAX
    call utf8_cut
    mov rsi, rax
    mov rdi, r12
    call mem_dup
    mov [rbx + NC_msg], rax
    add r12, r14
    mov [rsp + 8], r13
.Lnb_rec:
    cmp r12, [rsp + 8]
    jae 7f
    mov rdi, r12
    mov rsi, [rsp + 8]
    lea rdx, [rip + rr_nt]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r12, rax
    lea rdi, [rip + rr_nt]
    xor esi, esi
    lea rdx, [rip + .Lr_detail]
    call tree_rec_is
    test eax, eax
    jz 1f
    mov rdi, [rip + rr_nt + RR_len]
    mov rsi, [rip + rr_nt + RR_data]
    mov edx, 1000
    call utf8_cut
    mov rsi, rax
    mov rdi, [rip + rr_nt + RR_data]
    call mem_dup
    mov rdi, [rbx + NC_detail]
    mov [rbx + NC_detail], rax
    call mem_free
    jmp .Lnb_rec
1:  lea rdi, [rip + rr_nt]
    xor esi, esi
    lea rdx, [rip + .Lr_sticky]
    call tree_rec_is
    test eax, eax
    jz 2f
    mov dword ptr [rbx + NC_sticky], 1
    jmp .Lnb_rec
2:  lea rdi, [rip + rr_nt]
    xor esi, esi
    lea rdx, [rip + .Lr_button]
    call tree_rec_is
    test eax, eax
    jz 3f
    cmp dword ptr [rbx + NC_nbtn], 3
    jae .Lnb_rec                # past 3: cut
    mov rdi, [rip + rr_nt + RR_len]
    mov rsi, [rip + rr_nt + RR_data]
    mov edx, 60
    call utf8_cut
    mov rsi, rax
    mov rdi, [rip + rr_nt + RR_data]
    call mem_dup
    mov ecx, [rbx + NC_nbtn]
    mov [rbx + NC_btitle + rcx*8], rax
    inc dword ptr [rbx + NC_nbtn]
    jmp .Lnb_rec
3:  lea rdi, [rip + rr_nt]
    xor esi, esi
    lea rdx, [rip + .Lr_command]
    call tree_rec_is
    test eax, eax
    jz .Lnb_rec
    mov ecx, [rbx + NC_nbtn]    # it belongs to the button before it
    test ecx, ecx
    jz .Lnb_rec
    dec ecx
    cmp qword ptr [rbx + NC_bref + rcx*8], 0
    jne .Lnb_rec
    push rcx
    push rcx
    mov rdi, [rsp + 16]         # the extension
    mov rsi, [rip + rr_nt + 16]
    mov rdx, [rip + rr_nt + 24]
    mov rcx, [rip + rr_nt + RR_data]
    mov r8, [rip + rr_nt + RR_len]
    call cmdref_new
    pop rcx
    pop rcx
    mov [rbx + NC_bref + rcx*8], rax
    jmp .Lnb_rec
7:  mov rdi, rbx
    call nt_deadline
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# notify_request(ext, sev ptr, len, body, blen) -> rax the new card's NOTE, -1 a bad body or
#   severity, -2 too many
FN notify_request
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov rdi, rsi
    mov rsi, rdx
    call sev_word
    cmp eax, -1
    je 7f
    mov r13d, eax
    mov rdi, rbx
    call nt_alloc
    test rax, rax
    jz 6f
    mov r12, rax
    mov [r12 + NC_sev], r13d
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call nt_body
    test eax, eax
    jz 5f
    mov eax, [r12 + NC_id]
    EPILOGUE
5:  mov rdi, r12
    call nt_free
7:  mov rax, -1
    EPILOGUE
6:  mov rax, -2
    EPILOGUE

# notify_set_request(ext, note, body, len) -> eax 0, 1 no such card, 2 a bad body
FN notify_set_request
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    call nt_by_id
    test rax, rax
    jz 7f
    mov r14, rax
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r13
    call nt_body
    test eax, eax
    jz 8f
    xor eax, eax
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  mov eax, 2
    EPILOGUE

# notify_close_request(ext, note) -> eax 0, 1 no such card: it closes without an event
FN notify_close_request
    push rbx
    call nt_by_id
    test rax, rax
    jz 7f
    mov rdi, rax
    call nt_free
    xor eax, eax
    pop rbx
    ret
7:  mov eax, 1
    pop rbx
    ret

# sev_word(ptr, len) -> eax SEV_* for info, warning or error, -1 otherwise
sev_word:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdx, [rip + .Ls_info]
    call str_eq_cstr
    mov ebx, SEV_INFO
    test eax, eax
    jnz 1f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_warning]
    call str_eq_cstr
    mov ebx, SEV_WARNING
    test eax, eax
    jnz 1f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Ls_error]
    call str_eq_cstr
    mov ebx, SEV_ERROR
    test eax, eax
    jnz 1f
    mov ebx, -1
1:  mov eax, ebx
    EPILOGUE

# notify_add(ext or 0, sev, msg, len) -> eax the card's id (0 when all are taken): built-in code's
#   notification
FN notify_add
    PROLOGUE
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    call nt_alloc
    test rax, rax
    jz 8f
    mov rbx, rax
    mov [rbx + NC_sev], r12d
    mov rdi, r14
    mov rsi, r13
    mov edx, NC_MSG_MAX
    call utf8_cut
    mov rsi, rax
    mov rdi, r13
    call mem_dup
    mov [rbx + NC_msg], rax
    mov rdi, rbx
    call nt_deadline
    mov eax, [rbx + NC_id]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# notify_button(id, title cstr, fn(ctx, id), ctx): one more button (3 at most; one ctx for all) on a
#   built-in card; it stays until closed
FN notify_button
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov esi, edi
    xor edi, edi
    call nt_by_id
    test rax, rax
    jz 9f
    mov rbx, rax
    mov ecx, [rbx + NC_nbtn]
    cmp ecx, 3
    jae 9f
    push rcx
    push rcx
    mov rdi, r12
    call dup_cstr
    pop rcx
    pop rcx
    mov [rbx + NC_btitle + rcx*8], rax
    mov [rbx + NC_bfn + rcx*8], r13
    mov [rbx + NC_bctx], r14
    inc dword ptr [rbx + NC_nbtn]
    mov rdi, rbx
    call nt_deadline
9:  EPILOGUE

# notify_close(id): a built-in card closes
FN notify_close
    mov esi, edi
    xor edi, edi
    call nt_by_id
    test rax, rax
    jz 1f
    mov rdi, rax
    jmp nt_free
1:  ret

# nt_event(NT*, what cstr, n): "0 notify NOTE WHAT[ N]" to its extension (n -1: no number)
nt_event:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, [rbx + NC_ext]
    test r14, r14
    jz 9f
    cmp dword ptr [r14 + EXT_status], ES_RUNNING
    jne 9f
    lea rdi, [rip + nbuf]
    call sb_clear
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lev_notify]
    call sb_push_cstr
    lea rdi, [rip + nbuf]
    mov esi, [rbx + NC_id]
    call sb_push_u64
    lea rdi, [rip + nbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbuf]
    mov rsi, r12
    call sb_push_cstr
    cmp r13d, -1
    je 1f
    lea rdi, [rip + nbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbuf]
    mov esi, r13d
    call sb_push_u64
1:  lea rdi, [rip + nbuf]
    mov esi, 10
    call sb_push_byte
    mov rdi, r14
    mov rsi, [rip + nbuf + SB_ptr]
    mov rdx, [rip + nbuf + SB_len]
    call ext_send
9:  EPILOGUE

# nt_press(NT*, button 1..3): its command reference runs, or its callback, or "pressed N"; the card
#   closes
nt_press:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    lea r13d, [r12 - 1]
    cmp r13d, [rbx + NC_nbtn]
    jae 9f
    mov rdi, [rbx + NC_bref + r13*8]
    test rdi, rdi
    jz 1f
    xor esi, esi
    call cmdref_invoke
    jmp 8f
1:  mov rax, [rbx + NC_bfn + r13*8]
    test rax, rax
    jz 2f
    mov rdi, [rbx + NC_bctx]
    mov esi, [rbx + NC_id]
    push rbx
    push rbx
    call rax
    pop rbx
    pop rbx
    jmp 8f
2:  mov rdi, rbx
    lea rsi, [rip + .Lw_pressed]
    mov edx, r12d
    call nt_event
8:  cmp dword ptr [rbx + NC_id], 0
    je 9f                       # a callback closed it already
    mov rdi, rbx
    call nt_free
9:  EPILOGUE

# nt_user_close(NT*): the user closed it (or it timed out): "closed"; a progress card's Cancel
nt_user_close:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    lea rsi, [rip + .Lw_closed]
    mov edx, -1
    call nt_event
    mov rdi, rbx
    call nt_free
    EPILOGUE

# ---------------- progress ----------------

# pg_by_id(ext, id) -> rax PG* or 0
pg_by_id:
    xor eax, eax
    lea rcx, [rip + pgs]
1:  cmp eax, NP_MAX
    jae 8f
    cmp [rcx + NP_id], esi
    jne 2f
    test esi, esi
    jz 2f
    cmp [rcx + NP_ext], rdi
    jne 2f
    mov rax, rcx
    ret
2:  add rcx, NP_SIZE
    inc eax
    jmp 1b
8:  xor eax, eax
    ret

# pg_alloc(ext) -> rax a free PG with a new id (8 per extension), or 0
pg_alloc:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    mov r13, -1
    xor ecx, ecx
1:  cmp ecx, NP_MAX
    jae 3f
    mov edi, ecx
    push rcx
    push rcx
    call pg_at
    pop rcx
    pop rcx
    cmp dword ptr [rax + NP_id], 0
    jne 2f
    cmp r13, -1
    jne 21f
    mov r13, rax
    jmp 21f
2:  cmp [rax + NP_ext], rbx
    jne 21f
    test rbx, rbx
    jz 21f
    inc r12d
21: inc ecx
    jmp 1b
3:  cmp r13, -1
    je 8f
    cmp r12d, NP_PER_EXT
    jae 8f
    mov rdi, r13
    xor esi, esi
    mov edx, NP_SIZE
    call memset
    mov [r13 + NP_ext], rbx
    inc dword ptr [rip + pg_seq]
    mov eax, [rip + pg_seq]
    mov [r13 + NP_id], eax
    inc dword ptr [rip + ord_seq]
    mov eax, [rip + ord_seq]
    mov [r13 + NP_order], eax
    mov dword ptr [r13 + NP_percent], -1
    mov dword ptr [r13 + NP_slot], -1
    call time_ms
    mov [r13 + NP_started], rax
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# pg_free(PG*): gone (a view's bar too)
pg_free:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + NP_where], NPW_VIEW
    jne 1f
    mov edi, [rbx + NP_slot]
    xor esi, esi
    mov edx, -2
    call rview_progress
1:  mov rdi, [rbx + NP_title]
    call mem_free
    mov rdi, [rbx + NP_msg]
    call mem_free
    mov rdi, rbx
    xor esi, esi
    mov edx, NP_SIZE
    call memset
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# progress_request(ext, where, wlen, cancel, clen, title, [stack] tlen) -> rax P, -1 a bad WHERE or
#   CANCEL (or a view not its own), -2 too many: WHERE status, note or view:VIEW; CANCEL cancel or -
FN progress_request
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx              # the cancel word
    mov [rsp + 8], r8
    mov [rsp + 16], r9          # the title
    mov rdi, rbx
    call pg_alloc
    test rax, rax
    jz 6f
    mov r14, rax
    # where
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lw_status]
    call str_eq_cstr
    mov ecx, NPW_STATUS
    test eax, eax
    jnz 2f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lw_note]
    call str_eq_cstr
    mov ecx, NPW_NOTE
    test eax, eax
    jnz 2f
    cmp r13, 6
    jb 5f
    cmp dword ptr [r12], 0x77656976     # "view"
    jne 5f
    cmp byte ptr [r12 + 4], ':'
    jne 5f
    lea rdi, [r12 + 5]
    lea rsi, [r13 - 5]
    call parse_u64
    lea rcx, [r13 - 5]
    cmp rdx, rcx
    jne 5f
    mov rdi, rbx
    mov esi, eax
    call rview_slot_of
    cmp eax, -1
    je 5f
    mov [r14 + NP_slot], eax
    mov ecx, NPW_VIEW
2:  mov [r14 + NP_where], ecx
    # cancel: "cancel" or "-"
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Lw_cancel]
    call str_eq_cstr
    mov [r14 + NP_cancel], eax
    test eax, eax
    jnz 3f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Lw_dash]
    call str_eq_cstr
    test eax, eax
    jz 5f
3:  mov rdi, [rbp + 16]         # the title: 200 bytes at most
    mov rsi, [rsp + 16]
    mov edx, 200
    call utf8_cut
    mov rsi, rax
    mov rdi, [rsp + 16]
    call mem_dup
    mov [r14 + NP_title], rax
    cmp dword ptr [r14 + NP_where], NPW_VIEW
    jne 4f
    mov edi, [r14 + NP_slot]
    mov esi, 1
    mov edx, -1
    call rview_progress
4:  mov eax, [r14 + NP_id]
    EPILOGUE
5:  mov rdi, r14
    call pg_free
    mov rax, -1
    EPILOGUE
6:  mov rax, -2
    EPILOGUE

# progress_set_request(ext, p, percent or -1, msg, len) -> eax 0, 1 no such progress
FN progress_set_request
    PROLOGUE
    mov r12d, edx
    mov r13, rcx
    mov r14, r8
    call pg_by_id
    test rax, rax
    jz 7f
    mov rbx, rax
    mov [rbx + NP_percent], r12d
    mov rdi, [rbx + NP_msg]
    call mem_free
    mov rdi, r14
    mov rsi, r13
    mov edx, 200
    call utf8_cut
    mov rsi, rax
    mov rdi, r13
    call mem_dup
    mov [rbx + NP_msg], rax
    cmp dword ptr [rbx + NP_where], NPW_VIEW
    jne 1f
    mov edi, [rbx + NP_slot]
    mov esi, 1
    mov edx, r12d
    call rview_progress
1:  mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
7:  mov eax, 1
    EPILOGUE

# progress_end_request(ext, p) -> eax 0, 1 no such progress
FN progress_end_request
    push rbx
    call pg_by_id
    test rax, rax
    jz 7f
    mov rdi, rax
    call pg_free
    xor eax, eax
    pop rbx
    ret
7:  mov eax, 1
    pop rbx
    ret

# progress_begin(ext or 0, NPW_STATUS|NPW_NOTE, title cstr, cancel fn(ctx, id) or 0, ctx) -> eax its
#   id, 0 when all are taken: built-in code's progress (a cancel fn makes it cancellable)
FN progress_begin
    PROLOGUE
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    call pg_alloc
    test rax, rax
    jz 8f
    mov rbx, rax
    mov [rbx + NP_where], r12d
    mov [rbx + NP_fn], r14
    mov [rbx + NP_ctx], r15
    xor eax, eax
    test r14, r14
    setnz al
    mov [rbx + NP_cancel], eax
    mov rdi, r13
    call dup_cstr
    mov [rbx + NP_title], rax
    mov eax, [rbx + NP_id]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# progress_update(id, percent or -1, msg, len): built-in progress's state
FN progress_update
    mov r8, rcx
    mov rcx, rdx
    mov edx, esi
    mov esi, edi
    xor edi, edi
    jmp progress_set_request

# progress_end(id): built-in progress ends
FN progress_end
    mov esi, edi
    xor edi, edi
    jmp progress_end_request

# pg_cancel(PG*): the user pressed Cancel: its callback, or "0 progress P cancel"; "Cancelling…" and
#   it goes 10 s later unless it ends first
pg_cancel:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + NP_cancel], 0  # without Cancel: never
    je 9f
    cmp qword ptr [rbx + NP_cancel_at], 0
    jne 9f
    call time_ms
    mov [rbx + NP_cancel_at], rax
    mov rax, [rbx + NP_fn]
    test rax, rax
    jz 1f
    mov rdi, [rbx + NP_ctx]
    mov esi, [rbx + NP_id]
    call rax
    jmp 9f
1:  mov r12, [rbx + NP_ext]
    test r12, r12
    jz 9f
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne 9f
    lea rdi, [rip + nbuf]
    call sb_clear
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lev_progress]
    call sb_push_cstr
    lea rdi, [rip + nbuf]
    mov esi, [rbx + NP_id]
    call sb_push_u64
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lw_sp_cancel]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + nbuf + SB_ptr]
    mov rdx, [rip + nbuf + SB_len]
    call ext_send
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# pg_shown(PG*) -> eax 1 when it shows: past its first 500 ms
pg_shown:
    push rbx
    mov rbx, rdi
    call time_ms
    sub rax, [rbx + NP_started]
    cmp rax, NP_DELAY_MS
    setae al
    movzx eax, al
    pop rbx
    ret

# notify_view_closed(slot): progress shown in that view instance shows nowhere now
FN notify_view_closed
    xor eax, eax
    lea rcx, [rip + pgs]
1:  cmp eax, NP_MAX
    jae 9f
    cmp dword ptr [rcx + NP_id], 0
    je 2f
    cmp dword ptr [rcx + NP_where], NPW_VIEW
    jne 2f
    cmp [rcx + NP_slot], edi
    jne 2f
    mov dword ptr [rcx + NP_slot], -1
2:  add rcx, NP_SIZE
    inc eax
    jmp 1b
9:  ret

# notify_owner_gone(ext): its cards and progress go without events
FN notify_owner_gone
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp ebx, NC_MAX
    jae 2f
    mov edi, ebx
    call nt_at
    cmp dword ptr [rax + NC_id], 0
    je 11f
    cmp [rax + NC_ext], r12
    jne 11f
    mov rdi, rax
    call nt_free
11: inc ebx
    jmp 1b
2:  xor ebx, ebx
3:  cmp ebx, NP_MAX
    jae 9f
    mov edi, ebx
    call pg_at
    cmp dword ptr [rax + NP_id], 0
    je 31f
    cmp [rax + NP_ext], r12
    jne 31f
    mov rdi, rax
    call pg_free
31: inc ebx
    jmp 3b
9:  EPILOGUE

# ---------------- timers ----------------

# notify_timeout() -> ms until a card goes, a progress shows, Cancelling ends or a spinner moves; -1
FN notify_timeout
    PROLOGUE
    call time_ms
    mov r13, rax
    mov r12, -1
    xor ebx, ebx
1:  cmp ebx, NC_MAX
    jae 2f
    mov edi, ebx
    call nt_at
    cmp dword ptr [rax + NC_id], 0
    je 11f
    mov rcx, [rax + NC_deadline]
    test rcx, rcx
    jz 11f
    sub rcx, r13
    call keep_min
11: inc ebx
    jmp 1b
2:  xor ebx, ebx
3:  cmp ebx, NP_MAX
    jae 9f
    mov edi, ebx
    call pg_at
    cmp dword ptr [rax + NP_id], 0
    je 31f
    mov rcx, [rax + NP_started]
    add rcx, NP_DELAY_MS
    sub rcx, r13
    jg 32f
    mov ecx, SPIN_MS            # shown: its spinner turns
32: call keep_min
    mov rcx, [rax + NP_cancel_at]
    test rcx, rcx
    jz 31f
    add rcx, NP_CANCEL_MS
    sub rcx, r13
    call keep_min
31: inc ebx
    jmp 3b
9:  mov rax, r12
    EPILOGUE

# keep_min(): r12 = min(r12, rcx clamped at 0), -1 in r12 meaning none yet
keep_min:
    test rcx, rcx
    jns 1f
    xor ecx, ecx
1:  cmp r12, -1
    je 2f
    cmp rcx, r12
    jge 3f
2:  mov r12, rcx
3:  ret

# notify_tick(): cards past their time close ("closed"), cancelled progress past 10 s goes, and a
#   frame for the spinners
FN notify_tick
    PROLOGUE
    call time_ms
    mov r13, rax
    xor ebx, ebx
1:  cmp ebx, NC_MAX
    jae 2f
    mov edi, ebx
    call nt_at
    cmp dword ptr [rax + NC_id], 0
    je 11f
    mov rcx, [rax + NC_deadline]
    test rcx, rcx
    jz 11f
    cmp r13, rcx
    jb 11f
    cmp dword ptr [rax + NC_w], 0   # the pointer over it holds it, frames or not
    je 12f
    mov ecx, [rip + g_mx]
    sub ecx, [rax + NC_x]
    cmp ecx, [rax + NC_w]
    jae 12f
    mov ecx, [rip + g_my]
    sub ecx, [rax + NC_y]
    cmp ecx, [rax + NC_h]
    jae 12f
    lea rcx, [r13 + 2000]
    mov [rax + NC_deadline], rcx
    jmp 11f
12: mov rdi, rax
    call nt_user_close
11: inc ebx
    jmp 1b
2:  xor ebx, ebx
3:  cmp ebx, NP_MAX
    jae 9f
    mov edi, ebx
    call pg_at
    cmp dword ptr [rax + NP_id], 0
    je 31f
    mov dword ptr [rip + g_dirty], 1     # a spinner or a delayed entry
    mov rcx, [rax + NP_cancel_at]
    test rcx, rcx
    jz 31f
    add rcx, NP_CANCEL_MS
    cmp r13, rcx
    jb 31f
    mov rdi, rax
    call pg_free
31: inc ebx
    jmp 3b
9:  EPILOGUE

# ---------------- drawing ----------------

# notify_hole(): at the frame's start: last frame's cards keep the pointer from what is drawn under
#   them this frame
FN notify_hole
    mov eax, [rip + nt_stack]
    mov [rip + g_hole3], eax
    mov eax, [rip + nt_stack + 4]
    mov [rip + g_hole3 + 4], eax
    mov eax, [rip + nt_stack + 8]
    mov [rip + g_hole3 + 8], eax
    mov eax, [rip + nt_stack + 12]
    mov [rip + g_hole3 + 12], eax
    ret

# collect(): the cards to show into nt_order, oldest first (notifications by id, progress cards
#   among them by id too; a status entry's card while it is open); nt_count
collect:
    PROLOGUE
    xor r12d, r12d              # count
    mov ebx, 1                  # ids ascending: a simple pass per kind, merged by id below
    xor r13d, r13d
1:  cmp r13d, NC_MAX
    jae 2f
    mov edi, r13d
    call nt_at
    cmp dword ptr [rax + NC_id], 0
    je 11f
    lea rcx, [rip + nt_order]
    mov [rcx + r12*4], r13d
    inc r12d
11: inc r13d
    jmp 1b
2:  xor r13d, r13d
3:  cmp r13d, NP_MAX
    jae 4f
    mov edi, r13d
    call pg_at
    mov r14, rax
    cmp dword ptr [r14 + NP_id], 0
    je 31f
    cmp dword ptr [r14 + NP_where], NPW_NOTE
    je 32f
    cmp dword ptr [r14 + NP_where], NPW_STATUS
    jne 31f
    cmp dword ptr [r14 + NP_open], 0
    je 31f
32: mov rdi, r14
    call pg_shown
    test eax, eax
    jz 31f
    lea rcx, [rip + nt_order]
    lea eax, [r13 + 0x100]
    mov [rcx + r12*4], eax
    inc r12d
31: inc r13d
    jmp 3b
4:  mov [rip + nt_count], r12d
    # oldest first: by when each came (a slot freed and taken again is no older for it)
    mov ebx, 1
5:  cmp ebx, r12d
    jae 9f
    lea rax, [rip + nt_order]
    mov r13d, [rax + rbx*4]     # the entry being placed, its order
    mov edi, r13d
    call entry_order
    mov r14d, eax
    mov r15d, ebx
6:  test r15d, r15d
    jz 7f
    lea rax, [rip + nt_order]
    mov edi, [rax + r15*4 - 4]
    call entry_order
    cmp eax, r14d
    jbe 7f
    lea rax, [rip + nt_order]
    mov ecx, [rax + r15*4 - 4]
    mov [rax + r15*4], ecx
    dec r15d
    jmp 6b
7:  lea rax, [rip + nt_order]
    mov [rax + r15*4], r13d
    inc ebx
    jmp 5b
9:  EPILOGUE

# entry_order(entry: a card's slot, or a progress' | 0x100) -> eax when it came
entry_order:
    test edi, 0x100
    jnz 1f
    imul rax, rdi, NC_SIZE
    lea rcx, [rip + nts]
    mov eax, [rcx + rax + NC_order]
    ret
1:  and edi, 0xff
    imul rax, rdi, NP_SIZE
    lea rcx, [rip + pgs]
    mov eax, [rcx + rax + NP_order]
    ret

# notify_draw(): the cards over the window (in the overlay phase, under menus and the palette)
FN notify_draw
    PROLOGUE 48
    mov dword ptr [rip + g_hole3 + 12], 0      # the cards take the pointer themselves
    mov dword ptr [rip + nt_stack + 12], 0
    xor eax, eax                # none drawn yet (tests: where each was drawn)
    lea rcx, [rip + nts]
2:  mov dword ptr [rcx + NC_w], 0
    add rcx, NC_SIZE
    inc eax
    cmp eax, NC_MAX
    jb 2b
    call collect
    mov eax, [rip + nt_count]
    test eax, eax
    jnz 1f
    call place_focused          # no cards left: the keyboard goes back to the editor
    cmp eax, -1
    je 9f
    cmp eax, [rip + nt_place]
    jne 9f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    jmp 9f
1:  mov eax, [rip + g_block]
    mov [rsp + 32], eax
    call app_modal_open         # under a menu, the palette or a dialog the cards take no input
    or [rip + g_block], eax
    mov edi, 360                # at the window's bottom right
    call sc
    mov ecx, [rip + g_cv + CV_w]
    sub ecx, [rip + g_mt + 4*MI_32]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp], eax              # w
    mov ecx, [rip + g_cv + CV_w]
    sub ecx, eax
    sub ecx, [rip + g_mt + 4*MI_16]
    mov [rsp + 4], ecx          # x
    mov ecx, [rip + g_cv + CV_h]
    sub ecx, [rip + g_mt + 4*MI_STATUS]
    sub ecx, [rip + g_mt + 4*MI_8]
    cmp qword ptr [rip + g_toast_until], 0
    je 1f
    sub ecx, [rip + g_mt + 4*MI_28]     # over a toast
    sub ecx, [rip + g_mt + 4*MI_12]
1:  mov [rsp + 8], ecx          # the bottom of the next card
    mov [rsp + 12], ecx         # the stack's bottom
    # newest at the bottom: from the last, NC_SHOWN at most
    mov ebx, [rip + nt_count]
    xor r12d, r12d              # drawn
.Lnd_card:
    test ebx, ebx
    jz .Lnd_done
    cmp r12d, NC_SHOWN
    jae .Lnd_more
    dec ebx
    lea rax, [rip + nt_order]
    mov edi, [rax + rbx*4]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp]
    mov r8d, ebx
    call draw_card              # -> eax its height
    sub [rsp + 8], eax
    mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp + 8], eax
    inc r12d
    jmp .Lnd_card
.Lnd_more:
    # "+N more" over the cards
    lea rdi, [rip + nbuf]
    call sb_clear
    lea rdi, [rip + nbuf]
    mov esi, '+'
    call sb_push_byte
    lea rdi, [rip + nbuf]
    mov esi, ebx
    call sb_push_u64
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lmore]
    call sb_push_cstr
    M eax, MI_24
    sub [rsp + 8], eax
    COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 16 + 8]
    M ecx, MI_24
    mov r8, [rip + nbuf + SB_ptr]
    mov r9, [rip + nbuf + SB_len]
    call ui_text_v
    add rsp, 16
.Lnd_done:
    mov eax, [rsp + 4]          # the stack's rectangle: next frame's hole
    mov [rip + nt_stack], eax
    mov eax, [rsp + 8]
    mov [rip + nt_stack + 4], eax
    mov eax, [rsp]
    mov [rip + nt_stack + 8], eax
    mov eax, [rsp + 12]
    sub eax, [rsp + 8]
    mov [rip + nt_stack + 12], eax
    mov eax, [rsp + 32]
    mov [rip + g_block], eax
9:  EPILOGUE

# wrap(face, ptr, len, maxw, maxlines) -> eax lines in wrapbuf (start, len each): at LF, else greedy
#   at spaces, a word wider than the line cut where it must
wrap:
    PROLOGUE 32
    mov [rsp], rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    xor r14d, r14d              # lines
    xor r15d, r15d              # offset
1:  cmp r15, r13
    jae 9f
    cmp r14d, [rsp + 12]
    jae 9f
    mov rax, r15                # the segment: up to the next LF
11: cmp rax, r13
    jae 12f
    cmp byte ptr [r12 + rax], 10
    je 12f
    inc rax
    jmp 11b
12: mov [rsp + 16], rax
    mov rdi, [rsp]
    lea rsi, [r12 + r15]
    mov rdx, rax
    sub rdx, r15
    mov ecx, [rsp + 8]
    call text_fit
    mov rbx, rax                # bytes that fit
    test rbx, rbx
    jnz 2f
    cmp r15, [rsp + 16]
    je 4f                       # an empty line
    movzx eax, byte ptr [r12 + r15]     # not even one character: that character alone
    mov ebx, 1
    cmp eax, 0xc0
    jb 2f
    inc ebx
    cmp eax, 0xe0
    jb 2f
    inc ebx
    cmp eax, 0xf0
    jb 2f
    inc ebx
2:  lea rax, [r15 + rbx]
    cmp rax, [rsp + 16]
    jae 4f                      # the rest of the segment fits
    mov rcx, rbx                # back to the last space
    lea rdx, [r12 + r15]
3:  test rcx, rcx
    jz 4f
    cmp byte ptr [rdx + rcx], ' '
    je 31f
    dec rcx
    jmp 3b
31: mov rbx, rcx
4:  lea rax, [rip + wrapbuf]
    mov [rax + r14*8], r15d
    mov [rax + r14*8 + 4], ebx
    inc r14d
    add r15, rbx
    cmp r15, [rsp + 16]
    jb 5f
    inc r15                     # past the LF (or the end)
    jmp 1b
5:  cmp byte ptr [r12 + r15], ' '       # spaces at a break
    jne 1b
    inc r15
    cmp r15, [rsp + 16]
    jb 5b
    jmp 1b
9:  mov eax, r14d
    EPILOGUE

# notify_copy_selection() -> eax 1 when the pointer is over a card whose Markdown message has text
#   selected: it goes to the clipboard (Copy)
FN notify_copy_selection
    PROLOGUE 32
    xor ebx, ebx
1:  cmp ebx, NC_MAX
    jae 8f
    imul r12, rbx, NC_SIZE
    lea rax, [rip + nts]
    add r12, rax
    cmp dword ptr [r12 + NC_id], 0
    je 2f
    cmp qword ptr [r12 + NC_md], 0
    je 2f
    mov eax, [rip + g_mx]
    sub eax, [r12 + NC_x]
    js 2f
    cmp eax, [r12 + NC_w]
    jge 2f
    mov eax, [rip + g_my]
    sub eax, [r12 + NC_y]
    js 2f
    cmp eax, [r12 + NC_h]
    jge 2f
    lea rdi, [rsp]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    mov rdi, [r12 + NC_md]
    lea rsi, [rsp]
    call md_sel_text
    mov r13d, eax
    test eax, eax
    jz 3f
    mov rdi, [rsp + SB_ptr]
    mov rsi, [rsp + SB_len]
    xor edx, edx
    call ed_clip_set
3:  lea rdi, [rsp]
    call sb_free
    test r13d, r13d
    jnz 9f
2:  inc ebx
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# nt_md(NT*) -> rax its message as Markdown when its extension agreed markdown (made once), else 0
nt_md:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + NC_md]
    test rax, rax
    jnz 9f
    mov rcx, [rbx + NC_ext]
    test rcx, rcx
    jz 8f
    FEAT_TEST rcx, FEAT_MARKDOWN
    jz 8f
    mov rdi, [rbx + NC_msg]
    test rdi, rdi
    jz 8f
    call strlen
    mov rsi, rax
    mov rdi, [rbx + NC_msg]
    call md_new
    mov [rbx + NC_md], rax
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# draw_card(entry, x, bottom, w, index) -> eax its height: a notification or a progress card
draw_card:
    PROLOGUE 96
    mov [rsp], edi
    mov [rsp + 4], esi          # x
    mov [rsp + 8], edx          # bottom
    mov [rsp + 12], ecx         # w
    mov [rsp + 16], r8d         # its place in nt_order
    # the text: a notification's message, a progress' title and message
    test edi, 0x100
    jnz 1f
    call nt_at
    mov rbx, rax
    xor r15d, r15d              # PG*: none
    mov r12, [rbx + NC_msg]
    jmp 2f
1:  and edi, 0xff
    call pg_at
    mov r15, rax
    xor ebx, ebx
    mov r12, [r15 + NP_title]
2:  mov rdi, r12
    call strlen
    mov r13, rax
    mov ecx, [rsp + 12]
    sub ecx, [rip + g_mt + 4*MI_48]      # mark, padding and the close button
    sub ecx, [rip + g_mt + 4*MI_20]
    mov [rsp + 84], ecx         # the text's width
    lea rdi, [rip + g_face_ui]
    mov rsi, r12
    mov rdx, r13
    mov r8d, 6
    call wrap
    mov [rsp + 20], eax         # lines
    mov eax, [rip + g_face_ui + FACE_lineh]
    imul eax, [rsp + 20]
    mov [rsp + 80], eax         # the text's height
    mov qword ptr [rsp + 72], 0 # Markdown: an extension's message with markdown agreed
    test rbx, rbx
    jz 23f
    mov rdi, rbx
    call nt_md
    mov [rsp + 72], rax
    test rax, rax
    jz 23f
    mov rdi, rax
    mov esi, [rsp + 84]
    call md_layout
    mov ecx, [rip + g_face_ui + FACE_lineh]     # at most six lines' height
    imul ecx, ecx, 6
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 80], eax
23: # the height: padding, the text, the detail line, the bar, the buttons
    mov eax, [rsp + 80]
    add eax, [rip + g_mt + 4*MI_24]
    mov [rsp + 24], eax         # h so far
    mov dword ptr [rsp + 28], 0 # buttons
    test rbx, rbx
    jz 3f
    cmp qword ptr [rbx + NC_detail], 0
    jne 21f
    cmp qword ptr [rbx + NC_ext], 0
    je 22f
21: mov eax, [rip + g_face_small + FACE_lineh]
    add eax, [rip + g_mt + 4*MI_4]
    add [rsp + 24], eax
22: mov eax, [rbx + NC_nbtn]
    mov [rsp + 28], eax
    jmp 4f
3:  mov eax, [rip + g_face_small + FACE_lineh]   # progress: its message and its bar
    add eax, [rip + g_mt + 4*MI_12]
    add [rsp + 24], eax
    cmp dword ptr [r15 + NP_cancel], 0
    je 4f
    mov dword ptr [rsp + 28], 1
4:  cmp dword ptr [rsp + 28], 0
    je 5f
    mov eax, [rip + g_mt + 4*MI_32]
    add [rsp + 24], eax
5:  mov eax, [rsp + 8]
    sub eax, [rsp + 24]
    mov [rsp + 32], eax         # y
    test rbx, rbx
    jz 51f
    mov ecx, [rsp + 4]
    mov [rbx + NC_x], ecx
    mov [rbx + NC_y], eax
    mov ecx, [rsp + 12]
    mov [rbx + NC_w], ecx
    mov ecx, [rsp + 24]
    mov [rbx + NC_h], ecx
51: mov edi, [rsp + 4]
    mov esi, [rsp + 32]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 24]
    call ui_card
    # the pointer over a card holds it
    mov edi, [rsp + 4]
    mov esi, [rsp + 32]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 24]
    call ui_in
    test eax, eax
    jz 52f
    test rbx, rbx
    jz 52f
    cmp qword ptr [rbx + NC_deadline], 0
    je 52f
    call time_ms
    add rax, 2000
    cmp [rbx + NC_deadline], rax
    jae 52f
    mov [rbx + NC_deadline], rax
52: # the keyboard's card: an accent frame
    mov eax, [rsp + 16]
    cmp eax, [rip + nt_focus]
    jne 53f
    call place_focused
    cmp eax, [rip + nt_place]
    jne 53f
    mov edi, [rsp + 4]
    mov esi, [rsp + 32]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 24]
    M r8d, MI_RADIUS
    COLOR r9d, T_ACCENT
    COLOR eax, T_POPUP
    push rax
    push rax
    call gfx_frame
    add rsp, 16
53: # the severity mark (a progress: the spinner)
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 36], eax         # x of the mark
    mov eax, [rsp + 32]
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 40], eax         # y of the text
    test rbx, rbx
    jz 54f
    mov eax, [rbx + NC_sev]
    lea rcx, [rip + sev_slots]
    mov eax, [rcx + rax*4]
    lea rcx, [rip + g_theme]
    mov r9d, [rcx + rax*4]
    M edx, MI_10
    mov edi, [rsp + 36]
    mov esi, [rip + g_face_ui + FACE_lineh]
    sub esi, edx
    sar esi, 1
    add esi, [rsp + 40]
    mov ecx, edx
    mov r8d, edx
    sar r8d, 1
    call gfx_round_rect
    jmp 55f
54: mov edi, [rsp + 36]
    sub edi, [rip + g_mt + 4*MI_4]
    mov esi, [rsp + 40]
    mov edx, [rip + g_face_ui + FACE_lineh]
    call spinner
55: # the message: Markdown (dragging selects its text), or its lines
    mov rdi, [rsp + 72]
    test rdi, rdi
    jz 551f
    mov edi, [rsp + 16]
    shl edi, 12
    add edi, ID_NOTE_MD + 0xfff
    mov esi, [rsp + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 40]
    mov ecx, [rsp + 84]
    mov r8d, [rsp + 80]
    call ui_btn
    mov r8d, eax
    mov rdi, [rsp + 72]
    mov esi, [rsp + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 40]
    xor ecx, ecx
    call md_select_mouse
    mov eax, [rsp + 16]         # its links' ids
    shl eax, 12
    add eax, ID_NOTE_MD
    push rax
    push rax
    mov esi, [rsp + 16 + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 16 + 40]
    mov ecx, [rsp + 16 + 84]
    mov r8d, [rsp + 16 + 80]
    xor r9d, r9d
    call md_draw
    add rsp, 16
    test eax, eax
    js 57f
    mov rdi, [rsp + 72]         # a link rhun follows (others are ignored in a popup)
    mov esi, eax
    call md_open_link
    jmp 57f
551:mov dword ptr [rsp + 44], 0
56: mov eax, [rsp + 44]
    cmp eax, [rsp + 20]
    jae 57f
    lea rcx, [rip + wrapbuf]
    mov esi, [rcx + rax*8]
    mov r9d, [rcx + rax*8 + 4]
    lea r8, [r12 + rsi]
    mov edx, eax
    imul edx, [rip + g_face_ui + FACE_lineh]
    add edx, [rsp + 40]
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16 + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov ecx, [rip + g_face_ui + FACE_lineh]
    call ui_text_v
    add rsp, 16
    inc dword ptr [rsp + 44]
    jmp 56b
57: mov eax, [rsp + 80]
    add eax, [rsp + 40]
    mov [rsp + 48], eax         # y after the message
    test rbx, rbx
    jz .Ldc_progress
    # the detail and the extension's title, muted
    lea rdi, [rip + nbuf]
    call sb_clear
    mov rsi, [rbx + NC_detail]
    test rsi, rsi
    jz 58f
    lea rdi, [rip + nbuf]
    call sb_push_cstr
58: mov rax, [rbx + NC_ext]
    test rax, rax
    jz 59f
    cmp qword ptr [rip + nbuf + SB_len], 0
    je 581f
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
581:mov rax, [rbx + NC_ext]
    mov rsi, [rax + EXT_title]
    test rsi, rsi
    jnz 582f
    mov rsi, [rax + EXT_name]
582:lea rdi, [rip + nbuf]
    call sb_push_cstr
59: cmp qword ptr [rip + nbuf + SB_len], 0
    je 60f
    mov eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_48]
    COLOR ecx, T_MUTED
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 16 + 48]
    M ecx, MI_16
    mov r8, [rip + nbuf + SB_ptr]
    mov r9, [rip + nbuf + SB_len]
    call ui_text_v_fit
    add rsp, 16
60: # the close button at the top right
    mov edi, [rsp + 16]
    shl edi, 4
    add edi, ID_NT
    mov esi, [rsp + 4]
    add esi, [rsp + 12]
    sub esi, [rip + g_mt + 4*MI_32]
    mov edx, [rsp + 32]
    add edx, [rip + g_mt + 4*MI_8]
    M ecx, MI_20
    mov r8d, ecx
    mov r9d, IC_CLOSE
    call ui_icon_btn
    test eax, UB_CLICK
    jz 61f
    mov rdi, rbx
    call nt_user_close
    jmp .Ldc_ret
61: # its buttons, right to left from the card's right, the first accented
    mov r13d, [rbx + NC_nbtn]
    mov eax, [rsp + 4]
    add eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 52], eax         # right
.Ldc_btn:
    test r13d, r13d
    jz .Ldc_ret
    dec r13d
    mov rdi, [rbx + NC_btitle + r13*8]
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + NC_btitle + r13*8]
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    sub [rsp + 52], eax
    mov [rsp + 56], eax         # its width
    mov edi, [rsp + 16]
    shl edi, 4
    lea edi, [rdi + r13 + 1]
    add edi, ID_NT
    mov [rsp + 60], edi
    mov esi, [rsp + 52]
    mov edx, [rsp + 32]
    add edx, [rsp + 24]
    sub edx, [rip + g_mt + 4*MI_32]
    mov [rsp + 64], edx
    mov ecx, eax
    M r8d, MI_24
    call ui_btn
    mov [rsp + 68], eax
    # the face: the first accented, the others framed; the keyboard's button framed in accent
    mov edi, [rsp + 52]
    mov esi, [rsp + 64]
    mov edx, [rsp + 56]
    M ecx, MI_24
    M r8d, MI_RADIUS
    COLOR r9d, T_ACCENT
    test r13d, r13d
    jz 62f
    COLOR r9d, T_HOVER
    test dword ptr [rsp + 68], UB_HOVER
    jnz 62f
    COLOR r9d, T_INPUT
62: call gfx_round_rect
    mov eax, [rsp + 16]
    cmp eax, [rip + nt_focus]
    jne 63f
    lea eax, [r13 + 1]
    cmp eax, [rip + nt_fbtn]
    jne 63f
    mov edi, [rsp + 52]
    mov esi, [rsp + 64]
    mov edx, [rsp + 56]
    M ecx, MI_24
    M r8d, MI_RADIUS
    COLOR r9d, T_FG
    COLOR eax, T_ACCENT
    push rax
    push rax
    call gfx_frame
    add rsp, 16
63: COLOR eax, T_ACCENT_FG
    test r13d, r13d
    jz 64f
    COLOR eax, T_FG
64: push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 52]
    mov edx, [rsp + 16 + 64]
    mov ecx, [rsp + 16 + 56]
    M r8d, MI_24
    mov r9, [rbx + NC_btitle + r13*8]
    call ui_text_center
    add rsp, 16
    mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp + 52], eax
    test dword ptr [rsp + 68], UB_CLICK
    jz .Ldc_btn
    mov rdi, rbx
    lea esi, [r13 + 1]
    call nt_press
    jmp .Ldc_ret
.Ldc_progress:
    # its message, its bar, Cancel (Cancelling once pressed)
    mov rax, [r15 + NP_msg]
    test rax, rax
    jz 65f
    mov rdi, rax
    call strlen
    mov r9, rax
    mov eax, [rsp + 12]
    sub eax, [rip + g_mt + 4*MI_48]
    COLOR ecx, T_MUTED
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 36]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, [rsp + 16 + 48]
    M ecx, MI_16
    mov r8, [r15 + NP_msg]
    call ui_text_v_fit
    add rsp, 16
65: mov edi, [rsp + 36]
    add edi, [rip + g_mt + 4*MI_20]
    mov esi, [rsp + 48]
    add esi, [rip + g_face_small + FACE_lineh]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 12]
    sub edx, [rip + g_mt + 4*MI_48]
    mov ecx, [r15 + NP_percent]
    call notify_bar
    cmp dword ptr [r15 + NP_cancel], 0
    je .Ldc_ret
    lea r12, [rip + .Lcancel]
    cmp qword ptr [r15 + NP_cancel_at], 0
    je 66f
    lea r12, [rip + .Lcancelling]
66: mov rdi, r12
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, r12
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov [rsp + 56], eax
    mov ecx, [rsp + 4]
    add ecx, [rsp + 12]
    sub ecx, [rip + g_mt + 4*MI_12]
    sub ecx, eax
    mov [rsp + 52], ecx
    mov edx, [rsp + 32]
    add edx, [rsp + 24]
    sub edx, [rip + g_mt + 4*MI_32]
    mov [rsp + 64], edx
    mov edi, [rsp + 16]
    shl edi, 4
    add edi, ID_NT + 1
    mov esi, ecx
    mov ecx, eax
    M r8d, MI_24
    call ui_btn
    mov [rsp + 68], eax
    mov edi, [rsp + 52]
    mov esi, [rsp + 64]
    mov edx, [rsp + 56]
    M ecx, MI_24
    M r8d, MI_RADIUS
    COLOR r9d, T_INPUT
    test dword ptr [rsp + 68], UB_HOVER
    jz 67f
    COLOR r9d, T_HOVER
67: call gfx_round_rect
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 52]
    mov edx, [rsp + 16 + 64]
    mov ecx, [rsp + 16 + 56]
    M r8d, MI_24
    mov r9, r12
    call ui_text_center
    add rsp, 16
    test dword ptr [rsp + 68], UB_CLICK
    jz .Ldc_ret
    mov rdi, r15
    call pg_cancel
.Ldc_ret:
    mov eax, [rsp + 24]
    EPILOGUE

# spinner(x, y, h): three dots, one bright, turning every 300 ms (notify_spinner for others)
FN notify_spinner
spinner:
    PROLOGUE 16
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    call time_ms
    xor edx, edx
    mov ecx, SPIN_MS
    div rcx
    xor edx, edx
    mov ecx, 3
    div rcx
    mov r12d, edx               # the bright one
    xor ebx, ebx
1:  cmp ebx, 3
    jae 9f
    M ecx, MI_4
    mov edi, ebx
    imul edi, [rip + g_mt + 4*MI_6]
    add edi, [rsp]
    mov esi, [rsp + 8]
    sub esi, ecx
    sar esi, 1
    add esi, [rsp + 4]
    mov edx, ecx
    mov r8d, ecx
    sar r8d, 1
    COLOR r9d, T_MUTED
    cmp ebx, r12d
    jne 2f
    COLOR r9d, T_ACCENT
2:  call gfx_round_rect
    inc ebx
    jmp 1b
9:  EPILOGUE

# notify_bar(x, y, w, percent or -1): a progress bar; indeterminate: a third of it, moving
FN notify_bar
    PROLOGUE 16
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    M ecx, MI_4
    M r8d, MI_2
    COLOR r9d, T_BORDER
    call gfx_round_rect
    mov eax, [rsp + 12]
    cmp eax, -1
    je 1f
    imul eax, [rsp + 8]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edx, eax
    mov edi, [rsp]
    jmp 2f
1:  call time_ms                # a third, sliding along
    xor edx, edx
    mov ecx, 1500
    div rcx
    mov eax, edx
    imul eax, [rsp + 8]
    xor edx, edx
    mov ecx, 1500
    div ecx
    mov edi, [rsp]
    add edi, eax
    mov edx, [rsp + 8]
    xor ecx, ecx
    mov eax, edx
    mov ecx, 3
    push rdx
    xor edx, edx
    div ecx
    pop rdx
    mov edx, eax
    mov eax, [rsp]
    add eax, [rsp + 8]
    sub eax, edi
    cmp edx, eax
    cmovg edx, eax
2:  test edx, edx
    jle 9f
    mov esi, [rsp + 4]
    M ecx, MI_4
    M r8d, MI_2
    COLOR r9d, T_ACCENT
    call gfx_round_rect
9:  EPILOGUE

# notify_status_draw(right, y, h) -> eax the x left of what it drew: each shown status progress
#   entry (spinner, title, percent); a click opens its card
FN notify_status_draw
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    xor ebx, ebx
.Lns_entry:
    cmp ebx, NP_MAX
    jae .Lns_done
    mov edi, ebx
    call pg_at
    mov r12, rax
    cmp dword ptr [r12 + NP_id], 0
    je .Lns_next
    cmp dword ptr [r12 + NP_where], NPW_STATUS
    jne .Lns_next
    mov rdi, r12
    call pg_shown
    test eax, eax
    jz .Lns_next
    # its text: title and percent (Cancelling once cancelled)
    lea rdi, [rip + nbuf]
    call sb_clear
    lea rdi, [rip + nbuf]
    mov rsi, [r12 + NP_title]
    call sb_push_cstr
    cmp qword ptr [r12 + NP_cancel_at], 0
    je 1f
    lea rdi, [rip + nbuf]
    lea rsi, [rip + .Lsp_cancelling]
    call sb_push_cstr
    jmp 2f
1:  cmp dword ptr [r12 + NP_percent], -1
    je 2f
    lea rdi, [rip + nbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + nbuf]
    mov esi, [r12 + NP_percent]
    call sb_push_u64
    lea rdi, [rip + nbuf]
    mov esi, '%'
    call sb_push_byte
2:  lea rdi, [rip + g_face_small]
    mov rsi, [rip + nbuf + SB_ptr]
    mov rdx, [rip + nbuf + SB_len]
    call text_width
    add eax, [rip + g_mt + 4*MI_40]
    mov r13d, eax               # entry width: the spinner and the text
    sub [rsp], r13d
    lea edi, [rbx + ID_PG_STATUS]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, r13d
    mov r8d, [rsp + 8]
    call ui_btn
    mov r14d, eax
    test r14d, UB_HOVER
    jz 3f
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, r13d
    mov ecx, [rsp + 8]
    xor r8d, r8d
    COLOR r9d, T_HOVER
    call gfx_round_rect
3:  mov edi, [rsp]
    add edi, [rip + g_mt + 4*MI_6]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    call spinner
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_28]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8, [rip + nbuf + SB_ptr]
    mov r9, [rip + nbuf + SB_len]
    COLOR eax, T_FG
    push rax
    push rax
    call ui_text_v
    add rsp, 16
    test r14d, UB_CLICK
    jz 4f
    xor dword ptr [r12 + NP_open], 1
    mov dword ptr [rip + g_dirty], 1
4:  mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp], eax
.Lns_next:
    inc ebx
    jmp .Lns_entry
.Lns_done:
    mov eax, [rsp]
    EPILOGUE

# ---------------- the keyboard: focus_notifications ----------------

# cmd_focus_notifications(): the keyboard to the newest card
FN cmd_focus_notifications
    PROLOGUE
    call collect
    mov eax, [rip + nt_count]
    test eax, eax
    jz 9f
    dec eax
    mov [rip + nt_focus], eax
    mov dword ptr [rip + nt_fbtn], 0
    mov edi, [rip + nt_place]
    call place_focus
9:  EPILOGUE

# cmd_clear_notifications(): every card closes ("closed" each)
FN cmd_clear_notifications
    PROLOGUE
    xor ebx, ebx
1:  cmp ebx, NC_MAX
    jae 2f
    mov edi, ebx
    call nt_at
    cmp dword ptr [rax + NC_id], 0
    je 11f
    mov rdi, rax
    call nt_user_close
11: inc ebx
    jmp 1b
2:  xor ebx, ebx
3:  cmp ebx, NP_MAX
    jae 9f
    mov edi, ebx
    call pg_at
    mov dword ptr [rax + NP_open], 0
    inc ebx
    jmp 3b
9:  EPILOGUE

# nt_key(ctx, keysym, cp, mods) -> eax 1 when taken: Up/Down between cards, Left/Right between
#   buttons, Enter presses (the close button: closes), Delete closes, Escape back to the editor
nt_key:
    PROLOGUE
    mov r12d, esi
    call collect
    mov ecx, [rip + nt_count]
    test ecx, ecx
    jz 8f
    mov eax, [rip + nt_focus]
    cmp eax, ecx
    jb 1f
    lea eax, [rcx - 1]
    mov [rip + nt_focus], eax
1:  lea rdx, [rip + nt_order]
    mov ebx, [rdx + rax*4]      # the entry
    cmp r12d, KEY_UP
    jne 2f
    test eax, eax
    jz 7f
    dec dword ptr [rip + nt_focus]
    mov dword ptr [rip + nt_fbtn], 0
    jmp 7f
2:  cmp r12d, KEY_DOWN
    jne 3f
    inc eax
    cmp eax, ecx
    jae 7f
    mov [rip + nt_focus], eax
    mov dword ptr [rip + nt_fbtn], 0
    jmp 7f
3:  test ebx, 0x100
    jnz 5f                      # progress cards: Enter cancels
    mov edi, ebx
    call nt_at
    mov r13, rax
    cmp r12d, KEY_LEFT
    jne 31f
    cmp dword ptr [rip + nt_fbtn], 0
    je 7f
    dec dword ptr [rip + nt_fbtn]
    jmp 7f
31: cmp r12d, KEY_RIGHT
    jne 32f
    mov eax, [rip + nt_fbtn]
    cmp eax, [r13 + NC_nbtn]
    jae 7f
    inc dword ptr [rip + nt_fbtn]
    jmp 7f
32: cmp r12d, KEY_DELETE
    jne 33f
34: mov rdi, r13
    call nt_user_close
    jmp 7f
33: cmp r12d, KEY_RETURN
    jne 6f
    mov esi, [rip + nt_fbtn]
    test esi, esi
    jz 34b                      # no button chosen: Enter closes it
    mov rdi, r13
    call nt_press
    jmp 7f
5:  cmp r12d, KEY_RETURN
    jne 6f
    mov edi, ebx
    and edi, 0xff
    call pg_at
    cmp dword ptr [rax + NP_cancel], 0  # one without Cancel cannot be cancelled from the keyboard
    je 7f
    mov rdi, rax
    call pg_cancel
    jmp 7f
6:  xor eax, eax
    EPILOGUE
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov eax, 1
    EPILOGUE

# notify_init(): the hidden place item the keyboard reaches the cards through
FN notify_init
    PROLOGUE
    mov edi, PLACE_TAB
    lea rsi, [rip + .Lnt_name]
    lea rdx, [rip + .Lnt_title]
    lea rcx, [rip + nt_ops]
    xor r8d, r8d
    call place_add
    mov [rip + nt_place], eax
    EPILOGUE

# ---------------- tests ----------------

# notify_dump(sb): "note=ID sev=S ext=OWNER/NAME buttons=a|b|c msg=M detail=D [focus] [btn=N]" per
#   card shown (oldest first), then "progress=ID where=W percent=P cancel=C shown=S title=T msg=M"
FN notify_dump
    PROLOGUE 16
    mov rbx, rdi
    call collect
    xor r12d, r12d
1:  cmp r12d, NC_MAX
    jae 5f
    mov edi, r12d
    call nt_at
    mov r13, rax
    cmp dword ptr [r13 + NC_id], 0
    je 4f
    mov rdi, rbx
    lea rsi, [rip + .Ld_note]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NC_id]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_sev]
    call sb_push_cstr
    mov eax, [r13 + NC_sev]
    lea rcx, [rip + sev_names]
    mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_buttons]
    call sb_push_cstr
    xor r14d, r14d
2:  cmp r14d, [r13 + NC_nbtn]
    jae 3f
    test r14d, r14d
    jz 21f
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
21: mov rdi, rbx
    mov rsi, [r13 + NC_btitle + r14*8]
    call sb_push_cstr
    inc r14d
    jmp 2b
3:  cmp qword ptr [r13 + NC_md], 0    # drawn as Markdown
    je 32f
    mov rdi, rbx
    lea rsi, [rip + .Ld_md]
    call sb_push_cstr
32: mov rdi, rbx
    lea rsi, [rip + .Ld_msg]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + NC_msg]
    call push_line
    mov rsi, [r13 + NC_detail]
    test rsi, rsi
    jz 31f
    push rsi
    push rsi
    mov rdi, rbx
    lea rsi, [rip + .Ld_detail]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, rbx
    call sb_push_cstr
31: cmp qword ptr [r13 + NC_deadline], 0
    jne 32f
    mov rdi, rbx
    lea rsi, [rip + .Ld_stays]
    call sb_push_cstr
32: cmp dword ptr [r13 + NC_w], 0     # drawn this frame: " at=X,Y size=WxH"
    je 33f
    mov rdi, rbx
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NC_x]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ','
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r13 + NC_y]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_size]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NC_w]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 'x'
    call sb_push_byte
    mov rdi, rbx
    mov esi, [r13 + NC_h]
    call sb_push_u64
33: mov rdi, rbx
    mov esi, 10
    call sb_push_byte
4:  inc r12d
    jmp 1b
5:  xor r12d, r12d
6:  cmp r12d, NP_MAX
    jae 9f
    mov edi, r12d
    call pg_at
    mov r13, rax
    cmp dword ptr [r13 + NP_id], 0
    je 8f
    mov rdi, rbx
    lea rsi, [rip + .Ld_progress]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NP_id]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_where]
    call sb_push_cstr
    mov eax, [r13 + NP_where]
    lea rcx, [rip + where_names]
    mov rsi, [rcx + rax*8 - 8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_percent]
    call sb_push_cstr
    mov esi, [r13 + NP_percent]
    cmp esi, -1
    jne 61f
    mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
    jmp 62f
61: mov rdi, rbx
    call sb_push_u64
62: mov rdi, rbx
    lea rsi, [rip + .Ld_cancel]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r13 + NP_cancel]
    cmp qword ptr [r13 + NP_cancel_at], 0
    je 63f
    mov esi, 2                  # cancelling
63: call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_shown]
    call sb_push_cstr
    mov rdi, r13
    call pg_shown
    mov esi, eax
    mov rdi, rbx
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_title]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r13 + NP_title]
    call sb_push_cstr
    mov rsi, [r13 + NP_msg]
    test rsi, rsi
    jz 64f
    push rsi
    push rsi
    mov rdi, rbx
    lea rsi, [rip + .Ld_msg]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, rbx
    call sb_push_cstr
64: mov rdi, rbx
    mov esi, 10
    call sb_push_byte
8:  inc r12d
    jmp 6b
9:  EPILOGUE

# push_line(sb, cstr): the text on one line (LF as " / ")
push_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  movzx esi, byte ptr [r12]
    test esi, esi
    jz 9f
    inc r12
    cmp esi, 10
    je 2f
    mov rdi, rbx
    call sb_push_byte
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [rip + .Ld_lf]
    call sb_push_cstr
    jmp 1b
9:  EPILOGUE

# notify_press_test(card index among those shown, button: 0 close, 1..3; -1 the progress' Cancel)
FN notify_press_test
    PROLOGUE
    mov r12d, esi
    mov ebx, edi
    call collect
    cmp ebx, [rip + nt_count]
    jae 9f
    lea rax, [rip + nt_order]
    mov edi, [rax + rbx*4]
    test edi, 0x100
    jnz 5f
    call nt_at
    test r12d, r12d
    jnz 1f
    mov rdi, rax
    call nt_user_close
    jmp 9f
1:  mov rdi, rax
    mov esi, r12d
    call nt_press
    jmp 9f
5:  and edi, 0xff
    call pg_at
    mov rdi, rax
    call pg_cancel
9:  EPILOGUE

.section .rodata
.Lr_detail: .asciz "detail"
.Lr_sticky: .asciz "sticky"
.Lr_button: .asciz "button"
.Lr_command: .asciz "command"
.Ls_info: .asciz "info"
.Ls_warning: .asciz "warning"
.Ls_error: .asciz "error"
.Ls_hint: .asciz "hint"
.Lev_notify: .asciz "0 notify "
.Lev_progress: .asciz "0 progress "
.Lw_pressed: .asciz "pressed"
.Lw_closed: .asciz "closed"
.Lw_sp_cancel: .asciz " cancel\n"
.Lw_status: .asciz "status"
.Lw_note: .asciz "note"
.Lw_view: .asciz "view"
.Lw_cancel: .asciz "cancel"
.Lw_dash: .asciz "-"
.Lmore: .asciz " more"
.Lsep: .asciz " \302\267 "
.Lcancel: .asciz "Cancel"
.Lcancelling: .asciz "Cancelling\342\200\246"
.Lsp_cancelling: .asciz " \342\200\224 Cancelling\342\200\246"
.Lnt_name: .asciz "notifications"
.Lnt_title: .asciz "Notifications"
.Ld_note: .asciz "note="
.Ld_sev: .asciz " sev="
.Ld_buttons: .asciz " buttons="
.Ld_md: .asciz " markdown"
.Ld_msg: .asciz " msg="
.Ld_detail: .asciz " detail="
.Ld_stays: .asciz " stays"
.Ld_lf: .asciz " / "
.Ld_at: .asciz " at="
.Ld_size: .asciz " size="
.Ld_progress: .asciz "progress="
.Ld_where: .asciz " where="
.Ld_percent: .asciz " percent="
.Ld_cancel: .asciz " cancel="
.Ld_shown: .asciz " shown="
.Ld_title: .asciz " title="
.p2align 3
sev_names: .quad .Ls_error, .Ls_warning, .Ls_info, .Ls_hint       # SEV_*
where_names: .quad .Lw_status, .Lw_note, .Lw_view                  # NPW_* - 1
sev_slots: .long T_ERROR, T_WARNING, T_ACCENT, T_MUTED
nt_ops: .quad 0, nt_key, 0, 0, 0, 0
