# workspace edits' questions in the palette: the confirmation list before an edit changes files
# on disk (v1.1.md workspace-edits) and the partial-undo list (wstx.s). A list is a pick list of
# its own palette mode; the rows' strings live here until it closes.
.include "rhun.inc"

.equ WLK_UNDO, 1
.equ WLK_CONFIRM, 2

STRUCT
F WR_off, 8                     # its text: offset in wl_bytes, length
F WR_len, 8
F WR_data, 8                    # what wslist_chosen gets
ENDSTRUCT WR_SIZE

.bss
.p2align 3
wl_kind: .quad 0                # WLK_* of the list on show, 0 for none
wl_label: .zero SB_SIZE         # its placeholder (the question)
wl_bytes: .zero SB_SIZE         # the rows' texts
wl_rows: .zero VEC_SIZE         # WR records

.text

# FN wslist_open(kind, label cstr): a new list (whatever the palette showed closes first), rows
# follow with wslist_add, then wslist_ready
FN wslist_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + wl_label]
    call sb_clear
    lea rdi, [rip + wl_label]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + wl_label]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + wl_bytes]
    call sb_clear
    mov qword ptr [rip + wl_rows + VEC_len], 0
    mov rdi, [rip + wl_label + SB_ptr]
    call palette_wslist_open    # closes what was open (an earlier list is cancelled then)
    mov [rip + wl_kind], rbx
    EPILOGUE

# FN wslist_add(text cstr, data): a row
FN wslist_add
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call strlen
    mov r13, rax
    lea rdi, [rip + wl_rows]
    mov esi, WR_SIZE
    call vec_push
    mov rcx, [rip + wl_bytes + SB_len]
    mov [rax + WR_off], rcx
    mov [rax + WR_len], r13
    mov [rax + WR_data], r12
    lea rdi, [rip + wl_bytes]
    mov rsi, rbx
    mov rdx, r13
    call sb_push
    EPILOGUE

# FN wslist_ready(): the rows go to the palette (their texts no longer move)
FN wslist_ready
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wl_rows + VEC_len]
    jae 2f
    imul r12, rbx, WR_SIZE
    add r12, [rip + wl_rows + VEC_ptr]
    inc rbx
    mov rdi, [r12 + WR_off]
    add rdi, [rip + wl_bytes + SB_ptr]
    mov rsi, [r12 + WR_len]
    mov rdx, [r12 + WR_data]
    call palette_choose_add
    jmp 1b
2:  call palette_choose_ready
    EPILOGUE

# FN wslist_chosen(data): the palette's pick (the palette has closed)
FN wslist_chosen
    mov rax, [rip + wl_kind]
    mov qword ptr [rip + wl_kind], 0
    cmp rax, WLK_UNDO
    je tx_list_chosen
    cmp rax, WLK_CONFIRM
    je ws_confirm_chosen
    ret

# FN wslist_abort(): the palette closed or turned to something else under the list: unanswered
FN wslist_abort
    mov rax, [rip + wl_kind]
    test rax, rax
    jz 9f
    mov qword ptr [rip + wl_kind], 0
    cmp rax, WLK_UNDO
    je tx_list_cancel
    cmp rax, WLK_CONFIRM
    je ws_confirm_cancel
9:  ret

# FN wslist_kind() -> rax the kind of the list on show, 0 for none
FN wslist_kind
    mov rax, [rip + wl_kind]
    ret
