# tables (views design 3.8.1): a tree (rtree.s) with a header row of columns. Column 1 is the
# tree's own row (indent, icon, label); later columns show the node's "cell" records in order.
# Headers sort (rhun sorts each node's children itself, stable, numeric when both cells read as
# numbers, and keeps that order across updates; when children are paged anywhere its owner sorts
# instead), the dividers between them drag to resize, and a cut cell's tooltip is the whole cell.
#     tree_set_columns(tr, TBC* (mem_alloc'd, owned from now) or 0, n, sortfn)
#     tree_set_sorted(tr, col, desc, owner)    the arrow; rhun sorts when owner is 0
#     tree_sort(tr)                            again, after the store changed
#     tree_cell(tr, node, col) -> ptr, len     col 0 the label, col i its i-th cell record
# rtree.s calls table_layout, table_header, table_cells and table_dump_cells for a tree with columns.
.include "rhun.inc"

.macro NDP out, tr, idx
    imul \out, \idx, ND_SIZE
    add \out, [\tr + TR_nodes + VEC_ptr]
.endm

# a sort entry
.equ SE_ptr, 0
.equ SE_num, 8                  # its value * 10^6 when it reads as a number
.equ SE_len, 16
.equ SE_node, 20
.equ SE_isnum, 24
.equ SE_SIZE, 32

.bss
.p2align 3
rr_cell: .zero RR_SIZE
sort_a: .quad 0                 # entries, and the merge's other buffer
sort_b: .quad 0
sort_cap: .quad 0               # entries each holds
drag_tr: .quad 0                # a divider being dragged: its tree, column, where it started
drag_col: .long 0
drag_x0: .long 0
drag_w0: .long 0
sort_desc: .long 0              # tree_sort: descending
cell_tip: .zero 1024            # a cut cell's text for its tooltip
.p2align 3
mdtip_text: .quad 0             # tree_md_tip: the text and its document
mdtip_md: .quad 0

.text

# tree_set_columns(tr, cols or 0, n, sortfn): the columns (a TBC array the tree owns from now; a
#   column keeps the width the user dragged it to when the count stays); sortfn(ctx, tr, col, desc)
#   hears a header sorted while children are paged
FN tree_set_columns
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rbx + TR_sortfn], rcx
    mov r14, [rbx + TR_cols]
    test r14, r14
    jz 3f
    test r12, r12
    jz 2f
    cmp r13d, [rbx + TR_ncols]
    jne 2f
    xor ecx, ecx                # the user's widths stay
1:  cmp ecx, r13d
    jae 2f
    imul eax, ecx, TBC_SIZE
    mov edx, [r14 + rax + TBC_user]
    mov [r12 + rax + TBC_user], edx
    inc ecx
    jmp 1b
2:  xor r15d, r15d              # the old ones go
21: cmp r15d, [rbx + TR_ncols]
    jae 22f
    imul eax, r15d, TBC_SIZE
    mov rdi, [r14 + rax + TBC_title]
    call mem_free
    inc r15d
    jmp 21b
22: mov rdi, r14
    call mem_free
3:  mov [rbx + TR_cols], r12
    mov [rbx + TR_ncols], r13d
    test r12, r12
    jnz 4f
    mov dword ptr [rbx + TR_ncols], 0
4:  mov eax, [rbx + TR_sort]    # a sorted column past the last: none
    and eax, 0xff
    cmp eax, [rbx + TR_ncols]
    jbe 5f
    mov dword ptr [rbx + TR_sort], 0
5:  cmp [rip + drag_tr], rbx
    jne 6f
    mov qword ptr [rip + drag_tr], 0
6:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# tree_free_columns(tr): its columns go (tree_free)
FN tree_free_columns
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    jmp tree_set_columns

# tree_set_sorted(tr, col from 1 or 0, desc, owner): the header's arrow; when owner is 0 rhun sorts
FN tree_set_sorted
    and esi, 0xff
    and edx, 1
    shl edx, 8
    or esi, edx
    and ecx, 1
    shl ecx, 16
    or esi, ecx
    mov [rdi + TR_sort], esi
    mov dword ptr [rip + g_dirty], 1
    jmp tree_sort

# tree_cell(tr, node, col) -> rax ptr, rdx len: col 0 its label, col i its i-th "cell" record (0, 0
#   when it has none)
FN tree_cell
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    test r13d, r13d
    jnz 1f
    call tree_node_label
    EPILOGUE
1:  mov rdi, rbx
    mov esi, r12d
    call tree_node_extra
    mov r14, rax
    lea r15, [rax + rdx]
2:  cmp r14, r15
    jae 8f
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + rr_cell]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r14, rax
    cmp qword ptr [rip + rr_cell + RR_n], 2
    jne 2b
    lea rdi, [rip + rr_cell]
    xor esi, esi
    lea rdx, [rip + .Lr_cell]
    call tree_rec_is
    test eax, eax
    jz 2b
    dec r13d
    jnz 2b
    mov rax, [rip + rr_cell + RR_data]
    mov rdx, [rip + rr_cell + RR_len]
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# ---------------- sorting ----------------

# tree_sort(tr): when rhun sorts the table (a column, not its owner), every node's children in
#   that column's order (stable; numbers by value when both cells read as numbers, other text by
#   bytes with ASCII letters folded)
FN tree_sort
    PROLOGUE 16
    mov rbx, rdi
    mov eax, [rbx + TR_sort]
    test eax, 1 << 16
    jnz 9f
    movzx ecx, al
    test ecx, ecx
    jz 9f
    cmp ecx, [rbx + TR_ncols]
    ja 9f
    dec ecx
    mov [rsp], ecx              # the column, from 0
    shr eax, 8
    and eax, 1
    mov [rip + sort_desc], eax
    xor r12d, r12d              # every live node with two children or more
1:  cmp r12, [rbx + TR_nodes + VEC_len]
    jae 8f
    NDP rax, rbx, r12
    test dword ptr [rax + ND_flags], NF_LIVE
    jz 2f
    cmp dword ptr [rax + ND_nkids], 2
    jb 2f
    mov rdi, rbx
    mov esi, r12d
    mov edx, [rsp]
    call sort_kids
2:  inc r12
    jmp 1b
8:  or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# sort_kids(tr, parent, col): its children sorted and linked again in that order
sort_kids:
    PROLOGUE 32
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], edx
    NDP rax, rbx, r12
    mov r13d, [rax + ND_nkids]
    mov rdi, r13
    call sort_reserve
    test eax, eax
    jz 9f
    # the entries, in the present order
    NDP rax, rbx, r12
    mov r14d, [rax + ND_first]
    xor r15d, r15d
1:  cmp r14d, -1
    je 2f
    cmp r15d, r13d
    jae 2f
    mov rdi, rbx
    mov esi, r14d
    mov edx, [rsp]
    call tree_cell
    imul rcx, r15, SE_SIZE
    add rcx, [rip + sort_a]
    mov [rcx + SE_ptr], rax
    mov [rcx + SE_len], edx
    mov [rcx + SE_node], r14d
    mov [rsp + 8], rcx
    mov rdi, rax
    mov esi, edx
    call read_number
    mov rcx, [rsp + 8]
    mov [rcx + SE_num], rax
    mov [rcx + SE_isnum], edx
    inc r15d
    NDP rax, rbx, r14
    mov r14d, [rax + ND_next]
    jmp 1b
2:  mov r13d, r15d
    mov edi, r13d
    call merge_sort             # -> rax the sorted entries
    mov r14, rax
    # linked again
    NDP rax, rbx, r12
    mov ecx, [r14 + SE_node]
    mov [rax + ND_first], ecx
    mov r15d, -1                # the previous child
    xor ecx, ecx
3:  cmp ecx, r13d
    jae 4f
    imul rdx, rcx, SE_SIZE
    mov edx, [r14 + rdx + SE_node]
    NDP rax, rbx, rdx
    mov [rax + ND_prev], r15d
    mov dword ptr [rax + ND_next], -1
    cmp r15d, -1
    je 31f
    NDP rax, rbx, r15
    mov [rax + ND_next], edx
31: mov r15d, edx
    inc ecx
    jmp 3b
4:  NDP rax, rbx, r12
    mov [rax + ND_last], r15d
9:  EPILOGUE

# sort_reserve(n) -> eax 1 when sort_a and sort_b hold n entries each
sort_reserve:
    PROLOGUE
    mov rbx, rdi
    cmp rbx, [rip + sort_cap]
    jbe 8f
    mov rdi, [rip + sort_a]
    call mem_free
    mov rdi, [rip + sort_b]
    call mem_free
    mov qword ptr [rip + sort_a], 0
    mov qword ptr [rip + sort_b], 0
    mov qword ptr [rip + sort_cap], 0
    imul rdi, rbx, SE_SIZE
    call mem_alloc_try
    test rax, rax
    jz 9f
    mov [rip + sort_a], rax
    imul rdi, rbx, SE_SIZE
    call mem_alloc_try
    test rax, rax
    jz 7f
    mov [rip + sort_b], rax
    mov [rip + sort_cap], rbx
8:  mov eax, 1
    EPILOGUE
7:  mov rdi, [rip + sort_a]
    call mem_free
    mov qword ptr [rip + sort_a], 0
9:  xor eax, eax
    EPILOGUE

# merge_sort(n) -> rax sort_a or sort_b, whichever holds the n entries sorted (stable, bottom up)
merge_sort:
    PROLOGUE 48
    mov [rsp], edi              # n
    mov r12, [rip + sort_a]     # from
    mov r13, [rip + sort_b]     # to
    mov dword ptr [rsp + 4], 1  # width
1:  mov eax, [rsp + 4]
    cmp eax, [rsp]
    jae 8f
    xor r14d, r14d              # each pair of runs: left from r14
2:  cmp r14d, [rsp]
    jae 7f
    mov eax, r14d               # mid, right: clamped to n
    add eax, [rsp + 4]
    cmp eax, [rsp]
    jbe 21f
    mov eax, [rsp]
21: mov [rsp + 8], eax
    add eax, [rsp + 4]
    cmp eax, [rsp]
    jbe 22f
    mov eax, [rsp]
22: mov [rsp + 12], eax
    mov r15d, r14d              # i (left run), [rsp + 16] j (right run), ebx k (out)
    mov eax, [rsp + 8]
    mov [rsp + 16], eax
    mov ebx, r14d
3:  cmp ebx, [rsp + 12]
    jae 6f
    cmp r15d, [rsp + 8]
    jae 5f                      # the left run is spent: the right one's next
    mov eax, [rsp + 16]
    cmp eax, [rsp + 12]
    jae 4f                      # the right one is spent
    imul rdi, r15, SE_SIZE
    add rdi, r12
    imul rsi, rax, SE_SIZE
    add rsi, r12
    call cmp_entries
    test eax, eax
    jg 5f                       # equal ones keep their order: the left first
4:  imul rsi, r15, SE_SIZE
    inc r15d
    jmp 51f
5:  mov eax, [rsp + 16]
    imul rsi, rax, SE_SIZE
    inc dword ptr [rsp + 16]
51: add rsi, r12
    imul rdi, rbx, SE_SIZE
    add rdi, r13
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 16]
    movdqu [rdi], xmm0
    movdqu [rdi + 16], xmm1
    inc ebx
    jmp 3b
6:  mov r14d, [rsp + 12]
    jmp 2b
7:  xchg r12, r13
    shl dword ptr [rsp + 4], 1
    jmp 1b
8:  mov rax, r12
    EPILOGUE

# cmp_entries(a, b) -> eax < 0, 0, > 0 in the sort's direction
cmp_entries:
    push rbx
    push r12
    cmp dword ptr [rdi + SE_isnum], 0
    je 3f
    cmp dword ptr [rsi + SE_isnum], 0
    je 3f
    mov rax, [rdi + SE_num]
    cmp rax, [rsi + SE_num]
    jl 1f
    jg 2f
    xor eax, eax
    jmp 9f
1:  mov eax, -1
    jmp 9f
2:  mov eax, 1
    jmp 9f
3:  mov r8, [rdi + SE_ptr]
    mov r9, [rsi + SE_ptr]
    mov ecx, [rdi + SE_len]
    mov edx, [rsi + SE_len]
    mov r10d, ecx               # the shorter length
    cmp r10d, edx
    jbe 4f
    mov r10d, edx
4:  xor r11d, r11d
5:  cmp r11d, r10d
    jae 7f
    movzx eax, byte ptr [r8 + r11]
    movzx ebx, byte ptr [r9 + r11]
    lea r12d, [rax - 'A']
    cmp r12d, 25
    ja 51f
    or eax, 0x20
51: lea r12d, [rbx - 'A']
    cmp r12d, 25
    ja 52f
    or ebx, 0x20
52: sub eax, ebx
    jnz 9f
    inc r11d
    jmp 5b
7:  mov eax, ecx
    sub eax, edx
9:  cmp dword ptr [rip + sort_desc], 0
    je 91f
    neg eax
91: pop r12
    pop rbx
    ret

# read_number(ptr, len) -> rax its value * 10^6, edx 1 when the text (spaces around it aside) is
#   [-+]digits[.digits]: at most 12 digits before the point; digits past the sixth after it count
#   for nothing
read_number:
    xor eax, eax
    xor edx, edx
    test rdi, rdi
    jz 9f
    mov ecx, esi
    lea rsi, [rdi + rcx]        # the end
1:  cmp rdi, rsi                # spaces
    jae 9f
    cmp byte ptr [rdi], ' '
    jne 2f
    inc rdi
    jmp 1b
2:  cmp byte ptr [rsi - 1], ' '
    jne 3f
    dec rsi
    jmp 2b
3:  xor r8d, r8d                # negative
    movzx ecx, byte ptr [rdi]
    cmp ecx, '-'
    jne 31f
    mov r8d, 1
    inc rdi
    jmp 32f
31: cmp ecx, '+'
    jne 32f
    inc rdi
32: xor r9d, r9d                # digits before the point
    xor eax, eax
4:  cmp rdi, rsi
    jae 6f
    movzx ecx, byte ptr [rdi]
    cmp ecx, '.'
    je 5f
    sub ecx, '0'
    cmp ecx, 9
    ja 8f
    inc r9d
    cmp r9d, 12
    ja 8f
    imul rax, rax, 10
    add rax, rcx
    inc rdi
    jmp 4b
5:  test r9d, r9d
    jz 8f
    inc rdi                     # the point: at least one digit after it
    cmp rdi, rsi
    jae 8f
6:  imul rax, rax, 1000000
    mov r10d, 100000            # the next decimal's weight
7:  cmp rdi, rsi
    jae 71f
    movzx ecx, byte ptr [rdi]
    sub ecx, '0'
    cmp ecx, 9
    ja 8f
    imul ecx, r10d
    add rax, rcx
    push rax
    mov eax, r10d
    xor edx, edx
    mov ecx, 10
    div ecx
    mov r10d, eax
    pop rax
    inc rdi
    jmp 7b
71: test r9d, r9d
    jz 8f
    test r8d, r8d
    jz 72f
    neg rax
72: mov edx, 1
    ret
8:  xor eax, eax
    xor edx, edx
9:  ret

# owner_sorts(tr) -> eax 1 when children are paged somewhere (a "Load more"): its owner sorts
owner_sorts:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rdi + TR_nodes + VEC_len]
    jae 9f
    imul rdx, rcx, ND_SIZE
    add rdx, [rdi + TR_nodes + VEC_ptr]
    mov esi, [rdx + ND_flags]
    and esi, NF_LIVE | NF_MORE
    cmp esi, NF_LIVE | NF_MORE
    je 8f
    inc rcx
    jmp 1b
8:  mov eax, 1
9:  ret

# ---------------- drawing ----------------

# table_layout(tr, x, w): each column's x and w for rows drawn at x, w wide (the scrollbar's strip
#   left out): a column the user dragged keeps that width; one with a minimum gets that many
#   characters, or its title and arrow when wider, and its padding; the others share the rest (the
#   last column takes the rest when none shares)
FN table_layout
    PROLOGUE 32
    mov rbx, rdi
    mov r12, [rbx + TR_cols]
    add esi, [rip + g_mt + 4*MI_4]
    mov [rsp], esi              # where they start
    sub edx, [rip + g_mt + 4*MI_12]
    sub edx, [rip + g_mt + 4*MI_4]
    mov r13d, edx               # the width they share
    xor r15d, r15d              # fixed width
    mov dword ptr [rsp + 4], 0  # columns that share
    xor r14d, r14d              # each column's fixed width into TBC_w (0: it shares)
1:  cmp r14d, [rbx + TR_ncols]
    jae 3f
    imul eax, r14d, TBC_SIZE
    lea rdi, [r12 + rax]
    call fixed_width
    imul ecx, r14d, TBC_SIZE
    mov [r12 + rcx + TBC_w], eax
    test eax, eax
    jnz 2f
    inc dword ptr [rsp + 4]
2:  add r15d, eax
    inc r14d
    jmp 1b
3:  mov eax, r13d               # each share
    sub eax, r15d
    mov [rsp + 8], eax          # the rest
    cmp dword ptr [rsp + 4], 0
    je 31f
    cdq
    idiv dword ptr [rsp + 4]
31: mov ecx, [rip + g_face_ui + FACE_cellw]     # at least 6 characters and the padding
    lea ecx, [rcx + rcx*2]
    add ecx, ecx
    add ecx, [rip + g_mt + 4*MI_16]
    cmp eax, ecx
    jge 32f
    mov eax, ecx
32: mov [rsp + 12], eax
    mov esi, [rsp]              # x
    xor ecx, ecx
4:  cmp ecx, [rbx + TR_ncols]
    jae 9f
    imul eax, ecx, TBC_SIZE
    lea rdx, [r12 + rax]
    mov [rdx + TBC_x], esi
    mov eax, [rdx + TBC_w]
    test eax, eax
    jnz 42f
    mov eax, [rsp + 12]
    jmp 41f
42: cmp dword ptr [rsp + 4], 0  # none shares: the last takes the rest
    jne 41f
    lea edi, [rcx + 1]
    cmp edi, [rbx + TR_ncols]
    jne 41f
    cmp dword ptr [rsp + 8], 0
    jle 41f
    add eax, [rsp + 8]
41: mov [rdx + TBC_w], eax
    add esi, eax
    inc ecx
    jmp 4b
9:  EPILOGUE

# fixed_width(TBC*) -> eax its width when it does not share: the user's, else its minimum in
#   characters or its title and arrow when wider, with the padding; 0 when it shares
fixed_width:
    PROLOGUE
    mov rbx, rdi
    mov eax, [rbx + TBC_user]
    test eax, eax
    jnz 9f
    mov r12d, [rbx + TBC_min]
    imul r12d, [rip + g_face_ui + FACE_cellw]
    test r12d, r12d
    jz 8f
    mov rdi, [rbx + TBC_title]
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [rbx + TBC_title]
    mov rdx, rax
    call text_width
    cmp dword ptr [rbx + TBC_sort], 0
    je 1f
    add eax, [rip + g_mt + 4*MI_16]     # the arrow's room
    add eax, [rip + g_mt + 4*MI_2]
1:  cmp eax, r12d
    jge 2f
    mov eax, r12d
2:  add eax, [rip + g_mt + 4*MI_16]
    EPILOGUE
8:  xor eax, eax
9:  EPILOGUE

# table_header(tr, x, y, w, h): the header row: titles, the sorted column's arrow, dividers; a click
#   on a header that sorts sorts by it (again: the other way), a divider drags its column's width
FN table_header
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov r12, [rbx + TR_cols]
    # a line under it
    mov edi, esi
    mov esi, edx
    add esi, r8d
    dec esi
    mov edx, ecx
    mov ecx, 1
    COLOR r8d, T_BORDER
    call gfx_fill
    xor r13d, r13d
.Lth_col:
    cmp r13d, [rbx + TR_ncols]
    jae .Lth_dividers
    imul eax, r13d, TBC_SIZE
    lea r14, [r12 + rax]
    mov edi, [rbx + TR_idbase]
    add edi, 0xff00
    add edi, r13d
    mov esi, [r14 + TBC_x]
    mov edx, [rsp + 4]
    mov ecx, [r14 + TBC_w]
    mov r8d, [rsp + 12]
    call ui_btn
    mov [rsp + 16], eax
    cmp dword ptr [r14 + TBC_sort], 0
    je 3f
    test eax, UB_HOVER
    jz 2f
    mov edi, [r14 + TBC_x]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_2]
    mov edx, [r14 + TBC_w]
    mov ecx, [rsp + 12]
    sub ecx, [rip + g_mt + 4*MI_4]
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
    mov edi, CUR_POINTER
    call ui_set_cursor
2:  test dword ptr [rsp + 16], UB_CLICK
    jz 3f
    mov rdi, rbx
    lea esi, [r13 + 1]
    call header_sort
3:  # the title, and the arrow of the sorted column
    mov eax, [r14 + TBC_w]
    sub eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 20], eax         # room for the title
    mov dword ptr [rsp + 24], -1    # the arrow
    mov eax, [rbx + TR_sort]
    movzx ecx, al
    lea edx, [r13 + 1]
    cmp ecx, edx
    jne 31f
    mov ecx, IC_ARROW_UP
    test eax, 1 << 8
    jz 30f
    mov ecx, IC_ARROW_DN
30: mov [rsp + 24], ecx
    mov eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_2]
    sub [rsp + 20], eax
31: cmp dword ptr [rsp + 20], 0
    jle .Lth_next
    mov rdi, [r14 + TBC_title]
    call strlen
    mov r15, rax
    lea rdi, [rip + g_face_small]
    mov rsi, [r14 + TBC_title]
    mov rdx, r15
    call text_width
    cmp eax, [rsp + 20]
    jle 32f
    mov eax, [rsp + 20]
32: mov [rsp + 28], eax         # the title's width as drawn
    mov esi, [r14 + TBC_x]      # its x: right columns align it right
    add esi, [rip + g_mt + 4*MI_8]
    cmp dword ptr [r14 + TBC_align], 1
    jne 33f
    add esi, [rsp + 20]
    sub esi, eax
    cmp dword ptr [rsp + 24], -1
    je 33f
    mov eax, [rip + g_mt + 4*MI_16]     # the arrow goes left of a right column's title
    add eax, [rip + g_mt + 4*MI_2]
    add esi, eax
33: mov [rsp + 32], esi
    COLOR eax, T_MUTED
    mov ecx, [rsp + 20]
    push rcx
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 32]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 12]
    mov r8, [r14 + TBC_title]
    mov r9, r15
    call ui_text_v_fit
    add rsp, 16
    mov edi, [rsp + 24]
    cmp edi, -1
    je .Lth_next
    mov esi, [rsp + 32]         # the arrow: after a left title, before a right one
    add esi, [rsp + 28]
    add esi, [rip + g_mt + 4*MI_2]
    cmp dword ptr [r14 + TBC_align], 1
    jne 34f
    mov esi, [rsp + 32]
    sub esi, [rip + g_mt + 4*MI_16]
    sub esi, [rip + g_mt + 4*MI_2]
34: M ecx, MI_14
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
.Lth_next:
    inc r13d
    jmp .Lth_col
.Lth_dividers:
    # between columns: a line, a strip that drags (pressed after the headers: it wins the press)
    xor r13d, r13d
4:  mov eax, [rbx + TR_ncols]
    dec eax
    cmp r13d, eax
    jge 6f
    imul eax, r13d, TBC_SIZE
    lea r14, [r12 + rax]
    mov edi, [r14 + TBC_x]
    add edi, [r14 + TBC_w]
    dec edi
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, 1
    mov ecx, [rsp + 12]
    sub ecx, [rip + g_mt + 4*MI_8]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov edi, [rbx + TR_idbase]
    add edi, 0xff20
    add edi, r13d
    mov esi, [r14 + TBC_x]
    add esi, [r14 + TBC_w]
    sub esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 4]
    M ecx, MI_8
    mov r8d, [rsp + 12]
    call ui_btn
    test eax, UB_HOVER
    jz 41f
    mov [rsp + 16], eax
    mov edi, CUR_EW
    call ui_set_cursor
    mov eax, [rsp + 16]
41: test eax, UB_PRESS
    jz 5f
    mov [rip + drag_tr], rbx
    mov [rip + drag_col], r13d
    mov eax, [rip + g_mx]
    mov [rip + drag_x0], eax
    mov eax, [r14 + TBC_w]
    mov [rip + drag_w0], eax
5:  inc r13d
    jmp 4b
6:  # a drag in progress
    cmp [rip + drag_tr], rbx
    jne 9f
    test dword ptr [rip + g_mdown], 1 << BTN_LEFT
    jz 8f
    mov eax, [rip + drag_col]
    cmp eax, [rbx + TR_ncols]
    jae 8f
    imul eax, eax, TBC_SIZE
    lea r14, [r12 + rax]
    mov eax, [rip + g_mx]
    sub eax, [rip + drag_x0]
    add eax, [rip + drag_w0]
    mov ecx, [rip + g_face_ui + FACE_cellw]
    lea ecx, [rcx + rcx*2]      # at least 3 characters
    cmp eax, ecx
    jge 61f
    mov eax, ecx
61: cmp eax, [r14 + TBC_user]
    je 62f
    mov [r14 + TBC_user], eax
    mov dword ptr [rip + g_dirty], 1
62: mov edi, CUR_EW
    call ui_set_cursor
    jmp 9f
8:  mov qword ptr [rip + drag_tr], 0
9:  EPILOGUE

# header_sort(tr, col from 1): the user sorted by that column (the same one again: the other way);
#   rhun sorts, or its owner when children are paged somewhere
header_sort:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    xor r13d, r13d              # descending
    mov eax, [rbx + TR_sort]
    movzx ecx, al
    cmp ecx, r12d
    jne 1f
    shr eax, 8
    and eax, 1
    xor eax, 1
    mov r13d, eax
1:  cmp qword ptr [rbx + TR_sortfn], 0
    je 2f
    mov rdi, rbx
    call owner_sorts
    test eax, eax
    jz 2f
    mov rdi, rbx                # its owner sorts: the arrow shows at once
    mov esi, r12d
    mov edx, r13d
    mov ecx, 1
    call tree_set_sorted
    mov rax, [rbx + TR_sortfn]
    mov rdi, [rbx + TR_ctx]
    mov rsi, rbx
    mov edx, r12d
    mov ecx, r13d
    call rax
    EPILOGUE
2:  mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    xor ecx, ecx
    call tree_set_sorted
    EPILOGUE

# table_cells(tr, node, y, h, right) -> rax ptr, rdx len of a cell the pointer is over that was
#   cut (its tooltip), else 0, 0: columns 2 on of a row, each cut with "…" to its column (and to
#   right, where the row's inline buttons start)
FN table_cells
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], esi              # node
    mov [rsp + 4], edx          # y
    mov [rsp + 8], ecx          # h
    mov [rsp + 12], r8d         # right
    mov qword ptr [rsp + 16], 0 # the cut cell under the pointer
    mov qword ptr [rsp + 24], 0
    mov r13d, 1
1:  cmp r13d, [rbx + TR_ncols]
    jae 9f
    imul eax, r13d, TBC_SIZE
    mov r14, [rbx + TR_cols]
    add r14, rax
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, r13d
    call tree_cell
    test rdx, rdx
    jz 8f
    mov r12, rax
    mov r15, rdx
    mov eax, [r14 + TBC_x]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 32], eax         # x
    mov ecx, [r14 + TBC_w]
    sub ecx, [rip + g_mt + 4*MI_16]
    mov edx, [rsp + 12]         # within right
    sub edx, eax
    cmp ecx, edx
    jle 2f
    mov ecx, edx
2:  test ecx, ecx
    jle 8f
    mov [rsp + 36], ecx         # room
    lea rdi, [rip + g_face_ui]
    mov rsi, r12
    mov rdx, r15
    call text_width
    mov [rsp + 40], eax
    cmp eax, [rsp + 36]
    jle 3f
    # cut: the pointer over its column gives its tooltip
    mov ecx, [rip + g_mx]
    cmp ecx, [r14 + TBC_x]
    jl 4f
    mov edx, [r14 + TBC_x]
    add edx, [r14 + TBC_w]
    cmp ecx, edx
    jge 4f
    mov ecx, [rip + g_my]
    cmp ecx, [rsp + 4]
    jl 4f
    mov edx, [rsp + 4]
    add edx, [rsp + 8]
    cmp ecx, edx
    jge 4f
    mov [rsp + 16], r12
    mov [rsp + 24], r15
    jmp 4f
3:  cmp dword ptr [r14 + TBC_align], 1      # fits: a right column aligns it right
    jne 4f
    mov eax, [rsp + 36]
    sub eax, [rsp + 40]
    add [rsp + 32], eax
4:  COLOR eax, T_PANEL_FG
    mov ecx, [rsp + 36]
    push rcx
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16 + 32]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 8]
    mov r8, r12
    mov r9, r15
    call ui_text_v_fit
    add rsp, 16
8:  inc r13d
    jmp 1b
9:  mov rax, [rsp + 16]
    mov rdx, [rsp + 24]
    EPILOGUE

# tree_md_tip(cstr) -> rax a Markdown document of the text (the last one made, kept while the text
#   stays the same), 0 when it cannot be made
FN tree_md_tip
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    call strlen
    mov r12, rax
    mov rdi, [rip + mdtip_text]
    test rdi, rdi
    jz 1f
    mov rsi, rbx
    call str_eq_cstrs
    test eax, eax
    jz 1f
    mov rax, [rip + mdtip_md]
    EPILOGUE
1:  mov rdi, [rip + mdtip_md]
    call md_free
    mov rdi, [rip + mdtip_text]
    call mem_free
    mov rdi, rbx
    mov rsi, r12
    call mem_dup
    mov [rip + mdtip_text], rax
    mov rdi, rbx
    mov rsi, r12
    call md_new
    mov [rip + mdtip_md], rax
    EPILOGUE

# str_eq_cstrs(a, b) -> eax 1 when the two cstrs are equal
str_eq_cstrs:
1:  movzx eax, byte ptr [rdi]
    cmp al, [rsi]
    jne 8f
    test eax, eax
    jz 9f
    inc rdi
    inc rsi
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# table_tip(ptr, len) -> rax a cstr of the cell (cut to 1000 bytes) for tip_note_text
FN table_tip
    cmp rsi, 1000
    jbe 1f
    mov esi, 1000
1:  lea rax, [rip + cell_tip]
    xor ecx, ecx
2:  cmp rcx, rsi
    jae 3f
    mov dl, [rdi + rcx]
    mov [rax + rcx], dl
    inc rcx
    jmp 2b
3:  mov byte ptr [rax + rcx], 0
    ret

# table_dump_cells(tr, node, sb): " cells=a|b|c" (columns 2 on)
FN table_dump_cells
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    cmp dword ptr [rbx + TR_ncols], 1
    jbe 9f
    mov rdi, r13
    lea rsi, [rip + .Ld_cells]
    call sb_push_cstr
    mov r14d, 1
1:  cmp r14d, [rbx + TR_ncols]
    jae 9f
    cmp r14d, 1
    je 2f
    mov rdi, r13
    mov esi, '|'
    call sb_push_byte
2:  mov rdi, rbx
    mov esi, r12d
    mov edx, r14d
    call tree_cell
    mov rdi, r13
    mov rsi, rax
    call sb_push
    inc r14d
    jmp 1b
9:  EPILOGUE

# table_dump(tr, sb): "columns=TITLE:ALIGN:MIN:SORT:X:W|... sorted=COL asc|desc [owner]" LF
FN table_dump
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [rbx + TR_ncols], 0
    je 9f
    mov rdi, r12
    lea rsi, [rip + .Ld_columns]
    call sb_push_cstr
    xor r13d, r13d
1:  cmp r13d, [rbx + TR_ncols]
    jae 3f
    test r13d, r13d
    jz 2f
    mov rdi, r12
    mov esi, '|'
    call sb_push_byte
2:  imul eax, r13d, TBC_SIZE
    mov r14, [rbx + TR_cols]
    add r14, rax
    mov rdi, r12
    mov rsi, [r14 + TBC_title]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_left]
    cmp dword ptr [r14 + TBC_align], 1
    jne 21f
    lea rsi, [rip + .Ld_right]
21: call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + TBC_min]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_nosort]
    cmp dword ptr [r14 + TBC_sort], 0
    je 22f
    lea rsi, [rip + .Ld_sort]
22: call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + TBC_x]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + TBC_w]
    call sb_push_u64
    inc r13d
    jmp 1b
3:  mov rdi, r12
    lea rsi, [rip + .Ld_sorted]
    call sb_push_cstr
    mov eax, [rbx + TR_sort]
    movzx esi, al
    mov rdi, r12
    call sb_push_u64
    mov eax, [rbx + TR_sort]
    movzx ecx, al
    test ecx, ecx
    jz 5f
    lea rsi, [rip + .Ld_asc]
    test eax, 1 << 8
    jz 4f
    lea rsi, [rip + .Ld_desc]
4:  mov rdi, r12
    call sb_push_cstr
    test dword ptr [rbx + TR_sort], 1 << 16
    jz 5f
    mov rdi, r12
    lea rsi, [rip + .Ld_owner]
    call sb_push_cstr
5:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
9:  EPILOGUE

.section .rodata
.Lr_cell: .asciz "cell"
.Ld_cells: .asciz " cells="
.Ld_columns: .asciz "columns="
.Ld_left: .asciz ":left:"
.Ld_right: .asciz ":right:"
.Ld_sort: .asciz ":sort:"
.Ld_nosort: .asciz ":-:"
.Ld_sorted: .asciz " sorted="
.Ld_asc: .asciz " asc"
.Ld_desc: .asciz " desc"
.Ld_owner: .asciz " owner"
