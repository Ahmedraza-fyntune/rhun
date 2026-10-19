# the shared tree widget: a store of nodes (ids chosen by their owner, kept across updates with
# their expansion, children and the cursor), the rows flattened from the expanded ones, drawing
# with hit testing, and the keys. Extension views (rview.s) fill a store from patches; built-in
# code fills one the same way:
#     tr = tree_new(ops, ctx)                     ops: TRO callbacks (rhun.inc), ctx: yours
#     tree_kids_begin(tr, parent)                 parent 0 is the root
#     n = tree_kid(tr, id, idlen, label, lablen, KIDS_*)   then tree_set_icon/badge/desc/user(n, ...)
#     tree_kids_end(tr, more)                     children not listed again go, with their subtrees
#     tree_draw(tr, x, y, w, h, focused)          inside a place's draw
#     tree_key(tr, keysym, cp, mods) -> taken     inside a place's key
# A node's extra bytes hold records as the wire gives them (desc, tip, icon, color, badge, check,
# hl, ...; docs/extensions/v1.1.md "Retained views").
.include "rhun.inc"

.macro NDP out, tr, idx
    imul \out, \idx, ND_SIZE
    add \out, [\tr + TR_nodes + VEC_ptr]
.endm

.equ TYPE_MS, 1000               # type-to-jump: a pause this long starts a new prefix

.bss
.p2align 3
tree_seq: .long 0
mark_seq: .long 0
.p2align 3
rr_tmp: .zero RR_SIZE
name_buf: .zero 256
hl_buf: .zero 16 * 8             # label highlights: from, to (u32 each), sorted

.text

# tree_mark_new() -> eax a mark no node holds yet (kids diffing, patch checks)
FN tree_mark_new
    inc dword ptr [rip + mark_seq]
    jnz 1f
    inc dword ptr [rip + mark_seq]  # 0 is what new nodes hold
1:  mov eax, [rip + mark_seq]
    ret

# tree_new(ops, ctx) -> TR*: an empty store; its root (node 0) is expanded
FN tree_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov edi, TR_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + TR_ops], r12
    mov [rbx + TR_ctx], r13
    mov qword ptr [rbx + TR_free], -1
    mov dword ptr [rbx + TR_cursor], -1
    mov dword ptr [rbx + TR_anchor], -1
    mov dword ptr [rbx + TR_hover], -1
    mov dword ptr [rbx + TR_flags], TRF_DIRTY
    inc dword ptr [rip + tree_seq]
    mov eax, [rip + tree_seq]
    and eax, 0xfff
    shl eax, 16
    add eax, 0x10000000
    mov [rbx + TR_idbase], eax
    mov rdi, rbx
    call node_alloc
    mov rax, [rbx + TR_nodes + VEC_ptr]     # the root
    or dword ptr [rax + ND_flags], NF_OPEN | NF_GIVEN
    mov rax, rbx
    EPILOGUE

# tree_free(tr): the store and everything it holds
FN tree_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  cmp r12, [rbx + TR_nodes + VEC_len]
    jae 2f
    NDP r13, rbx, r12
    test dword ptr [r13 + ND_flags], NF_LIVE
    jz 11f
    mov rdi, [r13 + ND_blob]
    call mem_free
    mov rdi, [r13 + ND_desc]
    call mem_free
    mov rdi, [r13 + ND_tip]
    call mem_free
11: inc r12
    jmp 1b
2:  lea rdi, [rbx + TR_nodes]
    call vec_free
    lea rdi, [rbx + TR_rows]
    call vec_free
    lea rdi, [rbx + TR_order]
    call vec_free
    mov rdi, [rbx + TR_map]
    call mem_free
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# tree_nd(tr, node) -> rax ND*
FN tree_nd
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    ret

# tree_node_id(tr, node) -> rax ptr, rdx len
FN tree_node_id
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov edx, [rax + ND_idlen]
    mov rax, [rax + ND_blob]
    ret

# tree_node_label(tr, node) -> rax ptr, rdx len
FN tree_node_label
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov ecx, [rax + ND_idlen]
    mov edx, [rax + ND_lablen]
    mov rax, [rax + ND_blob]
    add rax, rcx
    ret

# tree_node_extra(tr, node) -> rax ptr, rdx len: its raw extra records
FN tree_node_extra
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov ecx, [rax + ND_idlen]
    add ecx, [rax + ND_lablen]
    mov edx, [rax + ND_xlen]
    mov rax, [rax + ND_blob]
    add rax, rcx
    ret

# ---------------- the id map ----------------

# tree_id_hash(ptr, len) -> eax (FNV-1a)
FN tree_id_hash
    mov eax, 2166136261
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx edx, byte ptr [rdi + rcx]
    xor eax, edx
    imul eax, eax, 16777619
    inc rcx
    jmp 1b
2:  ret

# tree_find(tr, ptr, len) -> eax the live node with that id, or -1; the empty id is the root
FN tree_find
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor eax, eax
    test r13, r13
    jz 9f
    cmp qword ptr [rbx + TR_mapcap], 0
    je 8f
    mov rdi, r12
    mov rsi, r13
    call tree_id_hash
    mov r14, [rbx + TR_mapcap]
    dec r14
    and rax, r14
    mov r15, rax
1:  mov rcx, [rbx + TR_map]
    mov eax, [rcx + r15*4]
    test eax, eax
    jz 8f
    cmp eax, -1
    je 2f
    dec eax
    NDP rcx, rbx, rax
    cmp [rcx + ND_idlen], r13d
    jne 2f
    mov rdi, [rcx + ND_blob]
    mov rsi, r12
    mov rdx, r13
    push rcx
    push rcx
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jz 2f
    mov rax, rcx
    sub rax, [rbx + TR_nodes + VEC_ptr]
    xor edx, edx
    mov ecx, ND_SIZE
    div rcx
    jmp 9f
2:  inc r15
    and r15, r14
    jmp 1b
8:  mov eax, -1
9:  EPILOGUE

# map_insert(tr, node): the node's id into the map (it is not there yet)
map_insert:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rax, [rbx + TR_mapused]
    inc rax
    add rax, rax
    cmp rax, [rbx + TR_mapcap]
    jbe 1f
    mov rdi, rbx
    call map_grow
    EPILOGUE                    # the node is live: map_grow put it in (a second entry would outlive it)
1:  NDP r13, rbx, r12
    mov rdi, [r13 + ND_blob]
    mov esi, [r13 + ND_idlen]
    call tree_id_hash
    mov r14, [rbx + TR_mapcap]
    dec r14
    and rax, r14
    mov rcx, [rbx + TR_map]
2:  mov edx, [rcx + rax*4]
    test edx, edx
    jz 3f
    cmp edx, -1
    je 4f
    inc rax
    and rax, r14
    jmp 2b
3:  inc qword ptr [rbx + TR_mapused]
4:  lea edx, [r12 + 1]
    mov [rcx + rax*4], edx
    EPILOGUE

# map_grow(tr): a table for twice the live nodes, at least 64 slots, without removed slots
map_grow:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + TR_count]
    inc rax
    shl rax, 2
    mov r12d, 64
1:  cmp r12, rax
    jae 2f
    add r12, r12
    jmp 1b
2:  mov rdi, [rbx + TR_map]
    call mem_free
    lea rdi, [r12*4]
    call mem_alloc
    mov [rbx + TR_map], rax
    mov [rbx + TR_mapcap], r12
    mov qword ptr [rbx + TR_mapused], 0
    mov r13d, 1                 # every live node but the root
3:  cmp r13, [rbx + TR_nodes + VEC_len]
    jae 9f
    NDP rax, rbx, r13
    test dword ptr [rax + ND_flags], NF_LIVE
    jz 4f
    mov rdi, [rax + ND_blob]
    mov esi, [rax + ND_idlen]
    call tree_id_hash
    lea r14, [r12 - 1]
    and rax, r14
    mov rcx, [rbx + TR_map]
5:  cmp dword ptr [rcx + rax*4], 0
    je 6f
    inc rax
    and rax, r14
    jmp 5b
6:  lea edx, [r13 + 1]
    mov [rcx + rax*4], edx
    inc qword ptr [rbx + TR_mapused]
4:  inc r13
    jmp 3b
9:  EPILOGUE

# map_remove(tr, node): its slot is marked removed
map_remove:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    cmp qword ptr [rbx + TR_mapcap], 0
    je 9f
    NDP r13, rbx, r12
    mov rdi, [r13 + ND_blob]
    mov esi, [r13 + ND_idlen]
    call tree_id_hash
    mov r14, [rbx + TR_mapcap]
    dec r14
    and rax, r14
    mov rcx, [rbx + TR_map]
    lea edx, [r12 + 1]
1:  mov r8d, [rcx + rax*4]
    test r8d, r8d
    jz 9f
    cmp r8d, edx
    je 2f
    inc rax
    and rax, r14
    jmp 1b
2:  mov dword ptr [rcx + rax*4], -1
9:  EPILOGUE

# ---------------- nodes ----------------

# node_alloc(tr) -> eax a fresh live node, not linked (ND pointers taken before may move)
node_alloc:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + TR_free]
    cmp rax, -1
    je 1f
    mov r12, rax
    NDP rax, rbx, r12
    movsxd rcx, dword ptr [rax + ND_next]
    mov [rbx + TR_free], rcx
    jmp 2f
1:  lea rdi, [rbx + TR_nodes]
    mov esi, ND_SIZE
    call vec_push
    mov r12, [rbx + TR_nodes + VEC_len]
    dec r12
2:  NDP rdi, rbx, r12
    push rdi
    push rdi
    xor esi, esi
    mov edx, ND_SIZE
    call memset
    pop rax
    pop rax
    mov dword ptr [rax + ND_parent], -1
    mov dword ptr [rax + ND_first], -1
    mov dword ptr [rax + ND_last], -1
    mov dword ptr [rax + ND_next], -1
    mov dword ptr [rax + ND_prev], -1
    mov dword ptr [rax + ND_icon], -1
    mov dword ptr [rax + ND_icolor], -1
    mov dword ptr [rax + ND_lcolor], -1
    mov dword ptr [rax + ND_flags], NF_LIVE
    test r12, r12
    jz 3f
    inc qword ptr [rbx + TR_count]
3:  mov eax, r12d
    EPILOGUE

# node_release(tr, node): out of the map, its bytes freed, the slot onto the free list (unlinked)
node_release:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rbx
    mov esi, r12d
    call map_remove
    NDP r13, rbx, r12
    mov eax, [r13 + ND_idlen]
    add eax, [r13 + ND_lablen]
    add eax, [r13 + ND_xlen]
    sub [rbx + TR_bytes], rax
    mov rdi, [r13 + ND_blob]
    call mem_free
    mov rdi, [r13 + ND_desc]
    call mem_free
    mov rdi, [r13 + ND_tip]
    call mem_free
    mov qword ptr [r13 + ND_blob], 0
    mov qword ptr [r13 + ND_desc], 0
    mov qword ptr [r13 + ND_tip], 0
    test dword ptr [r13 + ND_flags], NF_SEL
    jz 1f
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
1:  mov dword ptr [r13 + ND_flags], 0
    mov dword ptr [r13 + ND_parent], -1
    mov rax, [rbx + TR_free]
    mov [r13 + ND_next], eax
    mov [rbx + TR_free], r12
    dec qword ptr [rbx + TR_count]
    EPILOGUE

# unlink(tr, node): out of its parent's children
unlink:
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    movsxd r8, dword ptr [rax + ND_parent]
    cmp r8, -1
    je 9f
    imul r9, r8, ND_SIZE
    add r9, [rdi + TR_nodes + VEC_ptr]  # the parent
    movsxd rcx, dword ptr [rax + ND_prev]
    movsxd rdx, dword ptr [rax + ND_next]
    cmp rcx, -1
    je 1f
    imul r10, rcx, ND_SIZE
    add r10, [rdi + TR_nodes + VEC_ptr]
    mov [r10 + ND_next], edx
    jmp 2f
1:  mov [r9 + ND_first], edx
2:  cmp rdx, -1
    je 3f
    imul r10, rdx, ND_SIZE
    add r10, [rdi + TR_nodes + VEC_ptr]
    mov [r10 + ND_prev], ecx
    jmp 4f
3:  mov [r9 + ND_last], ecx
4:  dec dword ptr [r9 + ND_nkids]
    mov dword ptr [rax + ND_parent], -1
    mov dword ptr [rax + ND_prev], -1
    mov dword ptr [rax + ND_next], -1
9:  ret

# link_last(tr, parent, node): the node becomes its parent's last child
link_last:
    mov r8d, esi
    imul r9, r8, ND_SIZE
    add r9, [rdi + TR_nodes + VEC_ptr]  # the parent
    mov eax, edx
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov [rax + ND_parent], esi
    mov dword ptr [rax + ND_next], -1
    movsxd rcx, dword ptr [r9 + ND_last]
    mov [rax + ND_prev], ecx
    cmp rcx, -1
    je 1f
    imul r10, rcx, ND_SIZE
    add r10, [rdi + TR_nodes + VEC_ptr]
    mov [r10 + ND_next], edx
    jmp 2f
1:  mov [r9 + ND_first], edx
2:  mov [r9 + ND_last], edx
    inc dword ptr [r9 + ND_nkids]
    ret

# in_subtree(tr, node, top) -> eax 1 when node is top or below it
in_subtree:
    xor eax, eax
    cmp esi, -1
    je 9f
1:  cmp esi, edx
    je 8f
    mov ecx, esi
    imul rcx, rcx, ND_SIZE
    add rcx, [rdi + TR_nodes + VEC_ptr]
    mov esi, [rcx + ND_parent]
    cmp esi, -1
    jne 1b
    ret
8:  mov eax, 1
9:  ret

# free_subtree(tr, top): the node and everything under it go (the cursor, the anchor and the
#   hover row let go of them)
free_subtree:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rbx
    mov esi, [rbx + TR_cursor]
    mov edx, r12d
    call in_subtree
    test eax, eax
    jz 1f
    mov dword ptr [rbx + TR_cursor], -1
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
1:  mov rdi, rbx
    mov esi, [rbx + TR_anchor]
    mov edx, r12d
    call in_subtree
    test eax, eax
    jz 2f
    mov dword ptr [rbx + TR_anchor], -1
2:  mov dword ptr [rbx + TR_hover], -1
    or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov r13d, r12d              # n
.Lfs_down:
    NDP rax, rbx, r13
    movsxd rcx, dword ptr [rax + ND_first]
    cmp rcx, -1
    je .Lfs_leaf
    mov r13, rcx
    jmp .Lfs_down
.Lfs_leaf:
    NDP rax, rbx, r13
    movsxd r14, dword ptr [rax + ND_parent]
    mov rdi, rbx
    mov esi, r13d
    call unlink
    mov rdi, rbx
    mov esi, r13d
    call node_release
    cmp r13d, r12d
    je 9f
    NDP rax, rbx, r14
    movsxd rcx, dword ptr [rax + ND_first]
    cmp rcx, -1
    je 3f
    mov r13, rcx
    jmp .Lfs_down
3:  mov r13, r14
    jmp .Lfs_leaf
9:  EPILOGUE

# free_children(tr, node): every child's subtree goes
free_children:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
1:  NDP rax, rbx, r12
    mov esi, [rax + ND_first]
    cmp esi, -1
    je 9f
    mov rdi, rbx
    call free_subtree
    jmp 1b
9:  EPILOGUE

# ---------------- filling: kids, add, set, del ----------------

# tree_node_set(tr, node, blk): blk = id ptr, id len, label ptr, label len, kids, extra ptr, extra len
#   (qwords): the node's bytes and fields from a record
FN tree_node_set
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov rax, [r13 + 8]
    add rax, [r13 + 24]
    add rax, [r13 + 48]
    mov [rsp], rax              # blob bytes
    lea rdi, [rax + 1]
    call mem_alloc
    mov r14, rax
    mov rdi, r14
    mov rsi, [r13]
    mov rcx, [r13 + 8]
    rep movsb
    mov rsi, [r13 + 16]
    mov rcx, [r13 + 24]
    rep movsb
    mov rsi, [r13 + 40]
    mov rcx, [r13 + 48]
    rep movsb
    mov byte ptr [rdi], 0
    NDP r15, rbx, r12
    mov eax, [r15 + ND_idlen]
    add eax, [r15 + ND_lablen]
    add eax, [r15 + ND_xlen]
    sub [rbx + TR_bytes], rax
    mov rdi, [r15 + ND_blob]
    call mem_free
    NDP r15, rbx, r12
    mov [r15 + ND_blob], r14
    mov rax, [r13 + 8]
    mov [r15 + ND_idlen], eax
    mov rax, [r13 + 24]
    mov [r15 + ND_lablen], eax
    mov rax, [r13 + 48]
    mov [r15 + ND_xlen], eax
    mov rax, [rsp]
    add [rbx + TR_bytes], rax
    # its kind of children
    mov eax, [r15 + ND_kids]
    mov rcx, [r13 + 32]
    mov [r15 + ND_kids], ecx
    cmp ecx, KIDS_LEAF
    jne 2f
    and dword ptr [r15 + ND_flags], ~(NF_OPEN | NF_GIVEN | NF_MORE | NF_LOADING | NF_ERROR | NF_MOREWAIT)
    cmp dword ptr [r15 + ND_first], -1
    je 3f
    mov rdi, rbx
    mov esi, [rbx + TR_cursor]
    mov edx, r12d
    call in_subtree             # the cursor under it stays on it
    push rax
    push rax
    mov rdi, rbx
    mov esi, r12d
    call free_children
    pop rax
    pop rax
    test eax, eax
    jz 3f
    mov [rbx + TR_cursor], r12d
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
    jmp 3f
2:  cmp eax, KIDS_LEAF
    jne 3f
    cmp ecx, KIDS_OPEN
    jne 3f
    or dword ptr [r15 + ND_flags], NF_OPEN
3:  mov rdi, rbx
    mov esi, r12d
    call node_decode
    or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# tree_kids_begin(tr, parent): the children of parent are listed next (tree_kid), in order
FN tree_kids_begin
    push rbx
    mov rbx, rdi
    mov [rbx + TR_kparent], esi
    call tree_mark_new
    mov [rbx + TR_kgen], eax
    mov qword ptr [rbx + TR_order + VEC_len], 0
    and dword ptr [rbx + TR_flags], ~TRF_APPEND
    pop rbx
    ret

# tree_add_begin(tr, parent): children appended after parent's next (tree_kid, then tree_add_end)
FN tree_add_begin
    push rdi
    call tree_kids_begin
    pop rdi
    or dword ptr [rdi + TR_flags], TRF_APPEND
    ret

# tree_kid(tr, id, idlen, label, lablen, kids) -> eax the node, or -1 when the id is listed twice or
#   is somewhere else in the tree: one child of tree_kids_begin's parent. A child it had already
#   keeps its expansion and its own children (KIDS_LEAF takes them away).
FN tree_kid
    xor eax, eax
    push rax
    push rax
    push rax
    call tree_kid_x
    add rsp, 24
    ret

# tree_kid_x(tr, id, idlen, label, lablen, kids, [stack] extra, xlen): tree_kid with extra records
FN tree_kid_x
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], rsi              # the record block for tree_node_set: id, idlen, label, lablen,
    mov [rsp + 8], rdx          #   kids, extra, xlen
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    mov eax, r9d
    mov [rsp + 32], rax
    mov rax, [rbp + 16]
    mov [rsp + 40], rax
    mov rax, [rbp + 24]
    mov [rsp + 48], rax
    mov rdi, rbx
    call tree_find
    cmp eax, -1
    je 2f
    test eax, eax
    jz 8f                       # the root is no one's child
    mov r12d, eax
    test dword ptr [rbx + TR_flags], TRF_APPEND
    jnz 8f
    NDP rax, rbx, r12
    mov ecx, [rbx + TR_kparent]
    cmp [rax + ND_parent], ecx
    jne 8f
    mov ecx, [rbx + TR_kgen]
    cmp [rax + ND_mark], ecx
    je 8f
    jmp 3f
2:  mov rdi, rbx
    call node_alloc
    mov r12d, eax
    NDP rax, rbx, r12
    mov ecx, [rbx + TR_kparent]
    mov [rax + ND_parent], ecx  # not linked until tree_kids_end
    mov qword ptr [rax + ND_blob], 0
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rsp]
    call tree_node_set
    mov rdi, rbx
    mov esi, r12d
    call map_insert
    jmp 4f
3:  mov rdi, rbx
    mov esi, r12d
    lea rdx, [rsp]
    call tree_node_set
4:  NDP rax, rbx, r12
    mov ecx, [rbx + TR_kgen]
    mov [rax + ND_mark], ecx
    lea rdi, [rbx + TR_order]
    mov esi, 4
    call vec_push
    mov [rax], r12d
    mov eax, r12d
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# tree_kids_end(tr, more): the children listed since tree_kids_begin are its parent's children, in
#   that order (tree_add_begin: after the ones it had); more 1 puts a "Load more" row after them
FN tree_kids_end
    PROLOGUE 16
    mov rbx, rdi
    mov [rsp], esi
    mov r12d, [rbx + TR_kparent]
    test dword ptr [rbx + TR_flags], TRF_APPEND
    jnz 5f
    # the cursor on a child that goes moves to the next one that stays, else the one before, else
    # the parent
    mov r13d, [rbx + TR_cursor]
    cmp r13d, -1
    je 3f
1:  NDP rax, rbx, r13
    movsxd rcx, dword ptr [rax + ND_parent]
    cmp ecx, r12d
    je 2f
    cmp rcx, -1
    je 3f
    mov r13, rcx
    jmp 1b
2:  mov ecx, [rbx + TR_kgen]
    cmp [rax + ND_mark], ecx
    je 3f                       # it stays
    mov r14, rax
21: movsxd rdx, dword ptr [r14 + ND_next]
    cmp rdx, -1
    je 22f
    NDP r14, rbx, rdx
    cmp [r14 + ND_mark], ecx
    jne 21b
    mov [rbx + TR_cursor], edx
    jmp 25f
22: mov r14, rax
23: movsxd rdx, dword ptr [r14 + ND_prev]
    cmp rdx, -1
    je 24f
    NDP r14, rbx, rdx
    cmp [r14 + ND_mark], ecx
    jne 23b
    mov [rbx + TR_cursor], edx
    jmp 25f
24: mov eax, r12d
    test eax, eax
    jnz 241f
    mov eax, -1
241:mov [rbx + TR_cursor], eax
25: or dword ptr [rbx + TR_flags], TRF_SELCHANGED
3:  # the children not listed go
    NDP rax, rbx, r12
    movsxd r13, dword ptr [rax + ND_first]
4:  cmp r13, -1
    je 41f
    NDP rax, rbx, r13
    movsxd r14, dword ptr [rax + ND_next]
    mov ecx, [rbx + TR_kgen]
    cmp [rax + ND_mark], ecx
    je 42f
    mov rdi, rbx
    mov esi, r13d
    call free_subtree
42: mov r13, r14
    jmp 4b
41: NDP rax, rbx, r12           # the rest are listed: they are linked again in the new order
    mov dword ptr [rax + ND_first], -1
    mov dword ptr [rax + ND_last], -1
    mov dword ptr [rax + ND_nkids], 0
5:  xor r13d, r13d
6:  cmp r13, [rbx + TR_order + VEC_len]
    jae 7f
    mov rax, [rbx + TR_order + VEC_ptr]
    mov edx, [rax + r13*4]
    mov rdi, rbx
    mov esi, r12d
    call link_last
    inc r13
    jmp 6b
7:  NDP rax, rbx, r12
    and dword ptr [rax + ND_flags], ~(NF_LOADING | NF_ERROR | NF_MORE | NF_MOREWAIT)
    or dword ptr [rax + ND_flags], NF_GIVEN
    cmp dword ptr [rsp], 0
    je 8f
    or dword ptr [rax + ND_flags], NF_MORE
8:  or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# tree_add_end(tr, more): see tree_kids_end
FN tree_add_end
    jmp tree_kids_end

# tree_set(tr, node, label, lablen, kids, [stack] extra, xlen): an existing node's label, kind of
#   children and extra records; its expansion stays the user's
FN tree_set
    PROLOGUE 64
    mov rbx, rdi
    mov r12d, esi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov eax, r8d
    mov [rsp + 32], rax
    mov rax, [rbp + 16]
    mov [rsp + 40], rax
    mov rax, [rbp + 24]
    mov [rsp + 48], rax
    mov rdi, rbx
    call tree_node_id
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rsp]
    call tree_node_set
    EPILOGUE

# tree_del(tr, node): the node and its subtree go; the cursor on it moves to the next sibling, else
#   the one before, else the parent
FN tree_del
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    test r12d, r12d
    jz 9f
    mov rdi, rbx
    mov esi, [rbx + TR_cursor]
    mov edx, r12d
    call in_subtree
    test eax, eax
    jz 5f
    NDP rax, rbx, r12
    mov ecx, [rax + ND_next]
    cmp ecx, -1
    jne 3f
    mov ecx, [rax + ND_prev]
    cmp ecx, -1
    jne 3f
    mov ecx, [rax + ND_parent]
    test ecx, ecx
    jnz 3f
    mov ecx, -1
3:  mov r13d, ecx
    mov rdi, rbx
    mov esi, r12d
    call free_subtree
    mov [rbx + TR_cursor], r13d
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
    jmp 9f
5:  mov rdi, rbx
    mov esi, r12d
    call free_subtree
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# tree_clear(tr): the root's children go
FN tree_clear
    push rbx
    mov rbx, rdi
    xor esi, esi
    call free_children
    mov dword ptr [rbx + TR_cursor], -1
    mov dword ptr [rbx + TR_scroll], 0
    or dword ptr [rbx + TR_flags], TRF_DIRTY
    pop rbx
    ret

# tree_expand(tr, node, on): expanded (1) or collapsed (0), without telling the owner
FN tree_expand
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    cmp dword ptr [rax + ND_kids], KIDS_LEAF
    je 9f
    test esi, esi
    jz 9f                       # the root stays expanded
    and dword ptr [rax + ND_flags], ~NF_OPEN
    test edx, edx
    jz 1f
    or dword ptr [rax + ND_flags], NF_OPEN
1:  or dword ptr [rdi + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
9:  ret

# tree_set_icon(tr, node, IC_*, T_* color or -1)
FN tree_set_icon
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov [rax + ND_icon], edx
    mov [rax + ND_icolor], ecx
    ret

# tree_set_color(tr, node, T_* or -1): the label's color
FN tree_set_color
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov [rax + ND_lcolor], edx
    ret

# tree_set_badge(tr, node, n)
FN tree_set_badge
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov [rax + ND_badge], edx
    ret

# tree_set_user(tr, node, value): the owner's own value for the node
FN tree_set_user
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov [rax + ND_user], rdx
    ret

# tree_user(tr, node) -> rax its owner's value
FN tree_user
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    mov rax, [rax + ND_user]
    ret

# tree_set_desc(tr, node, ptr, len): the muted text after its label (len 0: none)
FN tree_set_desc
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    NDP rax, rbx, r12
    mov rdi, [rax + ND_desc]
    call mem_free
    xor eax, eax
    test r14, r14
    jz 1f
    mov rdi, r13
    mov rsi, r14
    call mem_dup
1:  NDP rcx, rbx, r12
    mov [rcx + ND_desc], rax
    EPILOGUE

# tree_set_tip(tr, node, ptr, len): its tooltip (len 0: none)
FN tree_set_tip
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    NDP rax, rbx, r12
    mov rdi, [rax + ND_tip]
    call mem_free
    xor eax, eax
    test r14, r14
    jz 1f
    mov rdi, r13
    mov rsi, r14
    call mem_dup
1:  NDP rcx, rbx, r12
    mov [rcx + ND_tip], rax
    EPILOGUE

# tree_set_check(tr, node, state): a checkbox (state 0 or 1), -1 for none
FN tree_set_check
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    and dword ptr [rax + ND_flags], ~(NF_CHECK | NF_CHECKED)
    cmp edx, -1
    je 1f
    or dword ptr [rax + ND_flags], NF_CHECK
    or dword ptr [rdi + TR_flags], TRF_CHECKS
    test edx, edx
    jz 1f
    or dword ptr [rax + ND_flags], NF_CHECKED
1:  ret

# tree_set_error(tr, node): asking for its children failed: an error row with Retry under it
FN tree_set_error
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    and dword ptr [rax + ND_flags], ~(NF_LOADING | NF_MOREWAIT)
    or dword ptr [rax + ND_flags], NF_ERROR
    or dword ptr [rdi + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
    ret

# tree_cursor(tr) -> eax the keyboard's node, or -1
FN tree_cursor
    mov eax, [rdi + TR_cursor]
    ret

# tree_set_cursor(tr, node): the keyboard's node (and the selection), -1 for none
FN tree_set_cursor
    mov [rdi + TR_cursor], esi
    or dword ptr [rdi + TR_flags], TRF_SELCHANGED
    mov dword ptr [rip + g_dirty], 1
    ret

# tree_reveal(tr, node): its ancestors expanded and its row scrolled into view when next drawn
FN tree_reveal
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    NDP rax, rbx, r12
    movsxd r13, dword ptr [rax + ND_parent]
1:  cmp r13, 0
    jle 2f
    NDP rax, rbx, r13
    or dword ptr [rax + ND_flags], NF_OPEN
    movsxd r13, dword ptr [rax + ND_parent]
    jmp 1b
2:  or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov rdi, rbx
    call tree_rows
    mov rdi, rbx
    mov esi, r12d
    call row_of
    test eax, eax
    js 9f
    mov rdi, rbx
    mov esi, eax
    call scroll_to_row
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- records ----------------

# tree_rec_read(ptr, end, rr) -> rax the byte after the record, or 0 when the bytes do not start
#   with one: a header line of at most 8 space-separated fields whose last is LEN, a LF, then LEN
#   bytes
FN tree_rec_read
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov qword ptr [rbx + RR_n], 0
    mov r14, r12
1:  cmp r14, r13                # the header's end
    jae 8f
    cmp byte ptr [r14], 10
    je 2f
    inc r14
    jmp 1b
2:  mov r15, r12                # split it
3:  cmp r15, r14
    jae 5f
    cmp byte ptr [r15], ' '
    jne 4f
    inc r15
    jmp 3b
4:  mov rax, [rbx + RR_n]
    cmp rax, 8
    jae 8f
    shl rax, 4
    mov [rbx + rax], r15
    mov rcx, r15
41: cmp rcx, r14
    jae 42f
    cmp byte ptr [rcx], ' '
    je 42f
    inc rcx
    jmp 41b
42: mov rdx, rcx
    sub rdx, r15
    mov [rbx + rax + 8], rdx
    inc qword ptr [rbx + RR_n]
    mov r15, rcx
    jmp 3b
5:  mov rax, [rbx + RR_n]
    cmp rax, 2
    jb 8f
    dec rax
    mov rdi, rbx
    mov esi, eax
    call tree_rec_num
    test edx, edx
    jz 8f
    lea rcx, [r14 + 1]
    mov rdx, r13
    sub rdx, rcx
    cmp rax, rdx
    ja 8f
    mov [rbx + RR_data], rcx
    mov [rbx + RR_len], rax
    lea rax, [rcx + rax]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# tree_rec_num(rr, i) -> rax the field's value, edx 1 when it is all digits (at most 10)
FN tree_rec_num
    mov eax, esi
    shl eax, 4
    mov rcx, [rdi + rax + 8]
    mov rdi, [rdi + rax]
    xor edx, edx
    test rcx, rcx
    jz 9f
    cmp rcx, 10
    ja 9f
    mov rsi, rcx
    push rcx
    call parse_u64
    pop rcx
    cmp rdx, rcx
    jne 8f
    mov edx, 1
    ret
8:  xor edx, edx
9:  ret

# tree_rec_is(rr, i, cstr) -> eax 1 when field i is that word
FN tree_rec_is
    xor eax, eax
    cmp rsi, [rdi + RR_n]
    jae 9f
    shl rsi, 4
    push rdx
    mov rcx, rdi
    mov rdi, [rcx + rsi]
    mov rsi, [rcx + rsi + 8]
    pop rdx
    jmp str_eq_cstr
9:  ret

# color_code(ptr, len) -> eax a T_* slot, 0x100 + i for c1 .. c8, or -1
FN tree_color_code
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + color_names]
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 3f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    add rbx, 16
    jmp 1b
2:  mov eax, [rbx + 8]
    EPILOGUE
3:  cmp r13, 2                  # c1 .. c8
    jne 8f
    cmp byte ptr [r12], 'c'
    jne 8f
    movzx eax, byte ptr [r12 + 1]
    sub eax, '1'
    cmp eax, 7
    ja 8f
    add eax, 0x100
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# tree_color(code, fallback T_*) -> eax ARGB
FN tree_color
    cmp edi, -1
    jne 1f
    mov edi, esi
1:  cmp edi, 0x100
    jae 2f
    lea rax, [rip + g_theme]
    mov eax, [rax + rdi*4]
    ret
2:  sub edi, 0x100
    and edi, 7
    lea rax, [rip + chart_colors]
    mov eax, [rax + rdi*4]
    ret

# tree_icon_code(ptr, len) -> eax an IC_* for a built-in icon name, NDI_FILE | icon | color << 8
#   for file:NAME, or -1
FN tree_icon_code
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp r13, 5
    jb 1f
    cmp dword ptr [r12], 0x656c6966     # "file"
    jne 1f
    cmp byte ptr [r12 + 4], ':'
    jne 1f
    lea rsi, [r12 + 5]
    lea rcx, [r13 - 5]
    cmp rcx, 200
    jbe 11f
    mov ecx, 200
11: lea rdi, [rip + name_buf]
    rep movsb
    mov byte ptr [rdi], 0
    lea rdi, [rip + name_buf]
    call file_icon
    shl edx, 8
    or eax, edx
    or eax, NDI_FILE
    EPILOGUE
1:  lea rbx, [rip + icon_names]
2:  mov rdx, [rbx]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 3f
    add rbx, 16
    jmp 2b
3:  mov eax, [rbx + 8]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# node_decode(tr, node): desc, tip, icon, color, badge and check from its extra records (records it
#   does not know are skipped)
node_decode:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    NDP r13, rbx, r12
    mov rdi, [r13 + ND_desc]
    call mem_free
    mov rdi, [r13 + ND_tip]
    call mem_free
    NDP r13, rbx, r12
    mov qword ptr [r13 + ND_desc], 0
    mov qword ptr [r13 + ND_tip], 0
    mov dword ptr [r13 + ND_icon], -1
    mov dword ptr [r13 + ND_icolor], -1
    mov dword ptr [r13 + ND_lcolor], -1
    mov dword ptr [r13 + ND_badge], 0
    and dword ptr [r13 + ND_flags], ~(NF_CHECK | NF_CHECKED)
    mov rdi, rbx
    mov esi, r12d
    call tree_node_extra
    mov r14, rax
    lea r15, [rax + rdx]
.Lnd_rec:
    cmp r14, r15
    jae .Lnd_done
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + rr_tmp]
    call tree_rec_read
    test rax, rax
    jz .Lnd_done
    mov r14, rax
    lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_desc]
    call tree_rec_is
    test eax, eax
    jz 1f
    mov rdi, rbx
    mov esi, r12d
    mov rdx, [rip + rr_tmp + RR_data]
    mov rcx, [rip + rr_tmp + RR_len]
    call tree_set_desc
    jmp .Lnd_rec
1:  lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_tip]
    call tree_rec_is
    test eax, eax
    jz 2f
    mov rdi, rbx
    mov esi, r12d
    mov rdx, [rip + rr_tmp + RR_data]
    mov rcx, [rip + rr_tmp + RR_len]
    call tree_set_tip
    jmp .Lnd_rec
2:  lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_icon]
    call tree_rec_is
    test eax, eax
    jz 3f
    cmp qword ptr [rip + rr_tmp + RR_n], 4
    jb .Lnd_rec
    mov rdi, [rip + rr_tmp + 16]
    mov rsi, [rip + rr_tmp + 24]
    call tree_icon_code
    NDP rcx, rbx, r12
    mov [rcx + ND_icon], eax
    mov rdi, [rip + rr_tmp + 32]
    mov rsi, [rip + rr_tmp + 40]
    call tree_color_code
    NDP rcx, rbx, r12
    mov [rcx + ND_icolor], eax
    jmp .Lnd_rec
3:  lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_color]
    call tree_rec_is
    test eax, eax
    jz 4f
    mov rdi, [rip + rr_tmp + 16]
    mov rsi, [rip + rr_tmp + 24]
    call tree_color_code
    NDP rcx, rbx, r12
    mov [rcx + ND_lcolor], eax
    jmp .Lnd_rec
4:  lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_badge]
    call tree_rec_is
    test eax, eax
    jz 5f
    lea rdi, [rip + rr_tmp]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz .Lnd_rec
    NDP rcx, rbx, r12
    mov [rcx + ND_badge], eax
    jmp .Lnd_rec
5:  lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_check]
    call tree_rec_is
    test eax, eax
    jz .Lnd_rec
    lea rdi, [rip + rr_tmp]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz .Lnd_rec
    mov edx, eax
    and edx, 1
    mov rdi, rbx
    mov esi, r12d
    call tree_set_check
    jmp .Lnd_rec
.Lnd_done:
    EPILOGUE

# tree_extra_find(tr, node, cstr name, rr) -> eax 1 with the node's first record of that name in rr
FN tree_extra_find
    PROLOGUE
    mov rbx, rdx
    mov r12, rcx
    call tree_node_extra
    mov r13, rax
    lea r14, [rax + rdx]
1:  cmp r13, r14
    jae 8f
    mov rdi, r13
    mov rsi, r14
    mov rdx, r12
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, r12
    xor esi, esi
    mov rdx, rbx
    call tree_rec_is
    test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- rows ----------------

# push_row(tr, node, depth, kind)
push_row:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    lea rdi, [rbx + TR_rows]
    mov esi, RW_SIZE
    call vec_push
    mov [rax + RW_node], r12d
    mov [rax + RW_depth], r13w
    mov [rax + RW_kind], r14w
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# tail_rows(tr, parent, depth of its children): its "Load more" or failed row after its children
tail_rows:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    NDP rax, rbx, r12
    mov eax, [rax + ND_flags]
    test eax, NF_GIVEN
    jz 9f
    test eax, NF_ERROR
    jz 1f
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    mov ecx, RWK_ERROR
    call push_row
    jmp 9f
1:  test eax, NF_MORE
    jz 9f
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    mov ecx, RWK_MORE
    call push_row
9:  pop r13
    pop r12
    pop rbx
    ret

# tree_rows(tr): the rows again when they are out of date, the scroll kept on its anchor's row
FN tree_rows
    PROLOGUE
    mov rbx, rdi
    test dword ptr [rbx + TR_flags], TRF_DIRTY
    jz 9f
    and dword ptr [rbx + TR_flags], ~TRF_DIRTY
    mov qword ptr [rbx + TR_rows + VEC_len], 0
    mov rax, [rbx + TR_nodes + VEC_ptr]     # the root
    movsxd r12, dword ptr [rax + ND_first]
    xor r13d, r13d              # the depth of r12's row
    cmp r12, -1
    je .Ltr_tail
.Ltr_node:
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    mov ecx, RWK_NODE
    call push_row
    NDP r14, rbx, r12
    mov eax, [r14 + ND_flags]
    test eax, NF_OPEN
    jz .Ltr_next
    cmp dword ptr [r14 + ND_kids], KIDS_LEAF
    je .Ltr_next
    test eax, NF_GIVEN
    jnz 1f
    mov ecx, RWK_LOADING
    test eax, NF_ERROR
    jz 11f
    mov ecx, RWK_ERROR
11: mov rdi, rbx
    mov esi, r12d
    lea edx, [r13 + 1]
    call push_row
    jmp .Ltr_next
1:  movsxd rcx, dword ptr [r14 + ND_first]
    cmp rcx, -1
    je 2f
    mov r12, rcx
    inc r13d
    jmp .Ltr_node
2:  mov rdi, rbx
    mov esi, r12d
    lea edx, [r13 + 1]
    call tail_rows
.Ltr_next:
    NDP r14, rbx, r12
    movsxd rcx, dword ptr [r14 + ND_next]
    cmp rcx, -1
    je 3f
    mov r12, rcx
    jmp .Ltr_node
3:  movsxd r12, dword ptr [r14 + ND_parent]   # the last child: its parent's tail
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call tail_rows
    test r12, r12
    jz 8f
    dec r13d
    jmp .Ltr_next
.Ltr_tail:
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call tail_rows
8:  # the scroll follows the anchor's row
    mov esi, [rbx + TR_anchor]
    cmp esi, -1
    je 9f
    mov rdi, rbx
    call row_of
    test eax, eax
    js 9f
    M ecx, MI_ROW
    imul eax, ecx
    add eax, [rbx + TR_anchor_off]
    mov [rbx + TR_scroll], eax
9:  EPILOGUE

# row_of(tr, node) -> eax the row showing the node, or -1
row_of:
    mov rcx, [rdi + TR_rows + VEC_ptr]
    mov r8, [rdi + TR_rows + VEC_len]
    xor eax, eax
1:  cmp rax, r8
    jae 8f
    cmp word ptr [rcx + rax*8 + RW_kind], RWK_NODE
    jne 2f
    cmp [rcx + rax*8 + RW_node], esi
    je 9f
2:  inc rax
    jmp 1b
8:  mov eax, -1
9:  ret

# scroll_to_row(tr, row): the row in view in the last drawn rectangle
scroll_to_row:
    M ecx, MI_ROW
    mov eax, esi
    imul eax, ecx
    cmp eax, [rdi + TR_scroll]
    jge 1f
    mov [rdi + TR_scroll], eax
    mov dword ptr [rdi + TR_anchor], -1
    ret
1:  add eax, ecx
    sub eax, [rdi + TR_rect + 12]
    cmp eax, [rdi + TR_scroll]
    jle 2f
    mov [rdi + TR_scroll], eax
2:  mov dword ptr [rdi + TR_anchor], -1     # the scroll is where it was put
    ret

# tree_count(tr) -> rax its live nodes, tree_rows_count(tr) -> rax its rows
FN tree_count
    mov rax, [rdi + TR_count]
    ret
FN tree_rows_count
    push rdi
    call tree_rows
    pop rdi
    mov rax, [rdi + TR_rows + VEC_len]
    ret

# tree_row(tr, i) -> eax node, edx kind << 16 | depth (after tree_rows_count)
FN tree_row
    mov rax, [rdi + TR_rows + VEC_ptr]
    movzx edx, word ptr [rax + rsi*8 + RW_kind]
    shl edx, 16
    movzx ecx, word ptr [rax + rsi*8 + RW_depth]
    or edx, ecx
    mov eax, [rax + rsi*8 + RW_node]
    ret

# ---------------- acting ----------------

# call_op(tr, offset, a, b, c): the owner's callback at that TRO offset, if any, with (ctx, tr, a, b, c)
#   (rdx, rcx, r8 pass through)
call_op:
    mov rax, [rdi + TR_ops]
    test rax, rax
    jz 9f
    mov rax, [rax + rsi]
    test rax, rax
    jz 9f
    mov rsi, rdi
    mov rdi, [rsi + TR_ctx]
    jmp rax
9:  ret

# tree_toggle(tr, node): the user expands or collapses it; the owner hears it
FN tree_toggle
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    NDP rax, rbx, r12
    cmp dword ptr [rax + ND_kids], KIDS_LEAF
    je 9f
    test r12d, r12d
    jz 9f
    xor dword ptr [rax + ND_flags], NF_OPEN
    mov r13d, [rax + ND_flags]
    and r13d, NF_OPEN
    shr r13d, 1
    or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov dword ptr [rip + g_dirty], 1
    # the anchor stays on the row above what moves
    mov rdi, rbx
    mov esi, TRO_expand
    mov edx, r12d
    mov ecx, r13d
    call call_op
    test r13d, r13d
    jnz 9f
    NDP rax, rbx, r12           # a collapse drops a wait for children
    and dword ptr [rax + ND_flags], ~NF_LOADING
    mov rdi, rbx
    mov esi, [rbx + TR_cursor]
    mov edx, r12d
    call in_subtree             # the cursor inside comes up to it
    test eax, eax
    jz 9f
    cmp [rbx + TR_cursor], r12d
    je 9f
    mov [rbx + TR_cursor], r12d
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
9:  EPILOGUE

# tree_activate(tr, node): Enter or a double click
FN tree_activate
    mov edx, esi
    mov esi, TRO_activate
    jmp call_op

# tree_flush(tr): the select callback once for the frame's changes
FN tree_flush
    test dword ptr [rdi + TR_flags], TRF_SELCHANGED
    jz 9f
    and dword ptr [rdi + TR_flags], ~TRF_SELCHANGED
    mov esi, TRO_select
    jmp call_op
9:  ret

# ---------------- keys ----------------

# move_cursor(tr, row): the cursor to that row's node (clamped), scrolled into view
move_cursor:
    push rbx
    mov rbx, rdi
    mov rcx, [rbx + TR_rows + VEC_len]
    test rcx, rcx
    jz 9f
    test esi, esi
    jns 1f
    xor esi, esi
1:  cmp rsi, rcx
    jb 2f
    lea rsi, [rcx - 1]
2:  mov rax, [rbx + TR_rows + VEC_ptr]
    cmp word ptr [rax + rsi*8 + RW_kind], RWK_NODE
    je 3f
    mov eax, [rax + rsi*8 + RW_node]     # a marker row: its parent's... stay on the row's node above
    jmp 4f
3:  mov eax, [rax + rsi*8 + RW_node]
4:  cmp eax, [rbx + TR_cursor]
    je 5f
    mov [rbx + TR_cursor], eax
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
5:  mov rdi, rbx
    call scroll_to_row
    mov dword ptr [rip + g_dirty], 1
9:  pop rbx
    ret

# tree_key(tr, keysym, cp, mods) -> eax 1 when the tree took the key: arrows, Page Up/Down,
#   Home/End, Left/Right (collapse or parent, expand or first child), Enter, Space (checkbox, else
#   activate), Shift+F10 (menu) and type-to-jump
FN tree_key
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov rdi, rbx
    call tree_rows
    mov esi, [rbx + TR_cursor]
    mov rdi, rbx
    call row_of
    mov r15d, eax               # the cursor's row, -1
    cmp r12d, ' '               # Ctrl+Space toggles the cursor's node in a multi-select tree
    jne 191f
    test r14d, MOD_CTRL
    jz 191f
    test dword ptr [rbx + TR_flags], TRF_MULTI
    jz .Ltk_no
    mov esi, [rbx + TR_cursor]
    cmp esi, -1
    je .Ltk_yes
    mov rdi, rbx
    mov edx, MOD_CTRL
    call select_click
    jmp .Ltk_yes
191:test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .Ltk_no
    cmp r12d, KEY_DOWN
    jne 1f
    lea esi, [r15 + 1]
    jmp .Ltk_move
1:  cmp r12d, KEY_UP
    jne 2f
    lea esi, [r15 - 1]
    cmp r15d, -1
    jne .Ltk_move
    xor esi, esi
    jmp .Ltk_move
2:  cmp r12d, KEY_HOME
    jne 3f
    xor esi, esi
    jmp .Ltk_move
3:  cmp r12d, KEY_END
    jne 4f
    mov esi, [rbx + TR_rows + VEC_len]
    dec esi
    jmp .Ltk_move
4:  cmp r12d, KEY_PAGEDOWN
    jne 5f
    call page_rows
    lea esi, [r15 + rax]
    jmp .Ltk_move
5:  cmp r12d, KEY_PAGEUP
    jne 6f
    call page_rows
    mov esi, r15d
    sub esi, eax
    jmp .Ltk_move
6:  cmp r12d, KEY_F1 + 9        # F10
    jne 61f
    test r14d, MOD_SHIFT
    jz .Ltk_no
    jmp .Ltk_menu
61: cmp r12d, 0xff67            # Menu
    je .Ltk_menu
    mov r8d, [rbx + TR_cursor]
    cmp r8d, -1
    je .Ltk_type
    cmp r12d, KEY_LEFT
    jne 7f
    NDP rax, rbx, r8
    cmp dword ptr [rax + ND_kids], KIDS_LEAF
    je 62f
    test dword ptr [rax + ND_flags], NF_OPEN
    jz 62f
    mov rdi, rbx
    mov esi, r8d
    call tree_toggle
    jmp .Ltk_yes
62: mov ecx, [rax + ND_parent]
    test ecx, ecx
    jle .Ltk_yes
    mov [rbx + TR_cursor], ecx
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
    mov rdi, rbx
    mov esi, ecx
    call row_of
    mov rdi, rbx
    mov esi, eax
    call scroll_to_row
    jmp .Ltk_yes
7:  cmp r12d, KEY_RIGHT
    jne 8f
    NDP rax, rbx, r8
    cmp dword ptr [rax + ND_kids], KIDS_LEAF
    je .Ltk_yes
    test dword ptr [rax + ND_flags], NF_OPEN
    jnz 71f
    mov rdi, rbx
    mov esi, r8d
    call tree_toggle
    jmp .Ltk_yes
71: lea esi, [r15 + 1]          # the first child's row
    mov rcx, [rbx + TR_rows + VEC_ptr]
    cmp rsi, [rbx + TR_rows + VEC_len]
    jae .Ltk_yes
    cmp word ptr [rcx + rsi*8 + RW_kind], RWK_NODE
    jne .Ltk_yes
    jmp .Ltk_move
8:  cmp r12d, KEY_RETURN
    je 81f
    cmp r12d, KEY_KP_ENTER
    jne 9f
81: mov rdi, rbx
    mov esi, r8d
    call tree_activate
    jmp .Ltk_yes
9:  cmp r12d, ' '
    jne .Ltk_type
    NDP rax, rbx, r8
    test dword ptr [rax + ND_flags], NF_CHECK
    jz 81b
    mov rdi, rbx
    mov esi, r8d
    call tree_toggle_check
    jmp .Ltk_yes
.Ltk_type:
    # type-to-jump: a printable character extends the prefix (a new one after a pause)
    cmp r13d, 0x20
    jbe .Ltk_no
    cmp r12d, 0xff00
    jae .Ltk_no
    cmp r13d, 0x7f
    jae .Ltk_no                 # ASCII prefixes only
    call time_ms
    mov rcx, rax
    sub rcx, [rbx + TR_typed_at]
    mov [rbx + TR_typed_at], rax
    cmp rcx, TYPE_MS
    jb 91f
    mov dword ptr [rbx + TR_typedlen], 0
91: mov eax, [rbx + TR_typedlen]
    cmp eax, 31
    jae .Ltk_yes
    mov [rbx + TR_typed + rax], r13b
    inc dword ptr [rbx + TR_typedlen]
    mov rdi, rbx
    mov esi, r15d
    call jump_prefix
    jmp .Ltk_yes
.Ltk_menu:
    mov r8d, [rbx + TR_cursor]
    cmp r8d, -1
    je .Ltk_yes
    mov rdi, rbx
    mov esi, r8d
    call row_of
    M ecx, MI_ROW
    imul eax, ecx
    add eax, [rbx + TR_rect + 4]
    sub eax, [rbx + TR_scroll]
    add eax, ecx
    mov r8d, eax
    mov ecx, [rbx + TR_rect]
    add ecx, [rip + g_mt + 4*MI_32]
    mov rdi, rbx
    mov esi, TRO_menu
    mov edx, [rbx + TR_cursor]
    call call_op
    jmp .Ltk_yes
.Ltk_move:
    mov rdi, rbx
    call move_cursor
    test dword ptr [rbx + TR_flags], TRF_MULTI
    jz .Ltk_yes
    mov esi, [rbx + TR_cursor]  # several selected: Shift extends from the anchor, else it alone
    cmp esi, -1
    je .Ltk_yes
    mov rdi, rbx
    mov edx, r14d
    and edx, MOD_SHIFT
    call select_click
.Ltk_yes:
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
.Ltk_no:
    xor eax, eax
    EPILOGUE

# page_rows() -> eax rows in the last drawn rectangle, at least 1 (rbx tree)
page_rows:
    mov eax, [rbx + TR_rect + 12]
    xor edx, edx
    M ecx, MI_ROW
    test ecx, ecx
    jz 1f
    div ecx
1:  cmp eax, 1
    jge 2f
    mov eax, 1
2:  ret

# jump_prefix(tr, row): the cursor to the next row (from row, wrapping) whose label starts with the
#   typed prefix, ignoring case
jump_prefix:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rbx + TR_rows + VEC_len]
    test r13, r13
    jz 9f
    xor r14d, r14d              # rows tried
    cmp dword ptr [rbx + TR_typedlen], 1
    jne 1f
    inc r12d                    # a new prefix starts after the cursor; a longer one at it
1:  cmp r14, r13
    jae 9f
    test r12d, r12d
    jns 2f
    xor r12d, r12d
2:  cmp r12, r13
    jb 3f
    xor r12d, r12d
3:  mov rax, [rbx + TR_rows + VEC_ptr]
    cmp word ptr [rax + r12*8 + RW_kind], RWK_NODE
    jne 4f
    mov r15d, [rax + r12*8 + RW_node]
    mov rdi, rbx
    mov esi, r15d
    call tree_node_label
    mov ecx, [rbx + TR_typedlen]
    cmp rdx, rcx
    jb 4f
    mov rdi, rax
    mov rsi, rcx
    lea rdx, [rbx + TR_typed]
    call str_ieq
    test eax, eax
    jz 4f
    mov rdi, rbx
    mov esi, r12d
    call move_cursor
    jmp 9f
4:  inc r12d
    inc r14
    jmp 1b
9:  EPILOGUE

# tree_toggle_check(tr, node): the user toggles its checkbox; it shows the new state at once
FN tree_toggle_check
    mov eax, esi
    imul rax, rax, ND_SIZE
    add rax, [rdi + TR_nodes + VEC_ptr]
    test dword ptr [rax + ND_flags], NF_CHECK
    jz 9f
    xor dword ptr [rax + ND_flags], NF_CHECKED
    mov ecx, [rax + ND_flags]
    shr ecx, 7
    and ecx, 1
    mov edx, esi
    mov esi, TRO_check
    mov dword ptr [rip + g_dirty], 1
    jmp call_op
9:  ret

# ---------------- drawing ----------------

# tree_draw(tr, x, y, w, h, focused): the rows in view, the scrollbar; the pointer selects (the cursor
#   follows), expands, activates leaves and double-clicked nodes, toggles checkboxes, opens menus; a
#   Loading row in view asks for children (TRO_load), a Load more row for more (TRO_more)
FN tree_draw
    PROLOGUE 96
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov [rsp + 16], r9d         # focused
    mov [rip + tr_focused], r9d
    mov [rbx + TR_rect], esi
    mov [rbx + TR_rect + 4], edx
    mov [rbx + TR_rect + 8], ecx
    mov [rbx + TR_rect + 12], r8d
    mov rdi, rbx
    call tree_rows
    M r12d, MI_ROW
    # the wheel
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    mov eax, [rip + g_scroll_y]
    add [rbx + TR_scroll], eax
    mov dword ptr [rbx + TR_anchor], -1
1:  mov rax, [rbx + TR_rows + VEC_len]
    imul eax, r12d
    mov [rsp + 20], eax         # content height
    sub eax, [rsp + 12]
    jns 2f
    xor eax, eax
2:  cmp [rbx + TR_scroll], eax
    jle 3f
    mov [rbx + TR_scroll], eax
3:  cmp dword ptr [rbx + TR_scroll], 0
    jge 4f
    mov dword ptr [rbx + TR_scroll], 0
4:  mov eax, [rbx + TR_scroll]
    xor edx, edx
    div r12d
    mov r13d, eax               # the first row
    mov [rip + tr_first], eax
    mov [rsp + 24], edx         # its pixels above the top
    mov dword ptr [rbx + TR_hover], -1
    mov eax, [rsp + 4]
    sub eax, [rsp + 24]
    mov r14d, eax               # row y
.Ltd_row:
    cmp r13, [rbx + TR_rows + VEC_len]
    jae .Ltd_rows_done
    mov eax, [rsp + 4]
    add eax, [rsp + 12]
    cmp r14d, eax
    jge .Ltd_rows_done
    mov rdi, rbx
    mov esi, r13d
    mov edx, r14d
    lea rcx, [rsp]
    call draw_row
    add r14d, r12d
    inc r13d
    jmp .Ltd_row
.Ltd_rows_done:
    # the scrollbar
    mov eax, [rsp + 12]
    push rax
    mov eax, [rsp + 8 + 20]
    push rax
    mov edi, [rbx + TR_idbase]
    add edi, 0xffff
    mov esi, [rsp + 16]
    add esi, [rsp + 16 + 8]
    M eax, MI_12
    sub esi, eax
    mov edx, [rsp + 16 + 4]
    mov ecx, eax
    mov r8d, [rsp + 16 + 12]
    lea r9, [rbx + TR_scroll]
    call ui_scrollbar
    add rsp, 16
    # the anchor: the first row's node and how far above the top it starts
    mov eax, [rbx + TR_scroll]
    xor edx, edx
    M ecx, MI_ROW
    div ecx
    mov rcx, [rbx + TR_rows + VEC_ptr]
    cmp rax, [rbx + TR_rows + VEC_len]
    jae 5f
    cmp word ptr [rcx + rax*8 + RW_kind], RWK_NODE
    jne 5f
    mov eax, [rcx + rax*8 + RW_node]
    jmp 6f
5:  mov eax, -1
6:  mov [rbx + TR_anchor], eax
    mov [rbx + TR_anchor_off], edx
    mov rdi, rbx
    call tree_flush
    EPILOGUE

# draw_row(tr, row, y, frame*): one row (the frame holds x, y, w, h, focused of tree_draw)
draw_row:
    PROLOGUE 64
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r15, rcx
    mov rax, [rbx + TR_rows + VEC_ptr]
    mov ecx, [rax + r12*8 + RW_node]
    mov [rsp], ecx              # node
    movzx ecx, word ptr [rax + r12*8 + RW_depth]
    mov [rsp + 4], ecx          # depth
    movzx ecx, word ptr [rax + r12*8 + RW_kind]
    mov [rsp + 8], ecx          # kind
    M eax, MI_ROW
    mov [rsp + 12], eax
    # the pointer
    mov edi, [rbx + TR_idbase]
    add edi, r12d
    sub edi, [rip + tr_first]
    mov esi, [r15]
    mov edx, r13d
    mov ecx, [r15 + 8]
    sub ecx, [rip + g_mt + 4*MI_12]     # not under the scrollbar
    mov r8d, [rsp + 12]
    call ui_btn
    mov [rsp + 16], eax
    test eax, UB_HOVER
    jz 1f
    mov [rbx + TR_hover], r12d
1:  # inline buttons on the hovered or cursor row: hit tested now (a press on one is not the row's),
    # drawn after the background
    mov dword ptr [rip + inl_n], 0
    cmp dword ptr [rsp + 8], RWK_NODE
    jne 11f
    cmp qword ptr [rbx + TR_nactions], 0
    je 11f
    mov eax, [rsp]
    cmp eax, [rbx + TR_cursor]
    je 12f
    test dword ptr [rsp + 16], UB_HOVER
    jz 11f
12: mov rdi, rbx
    mov esi, [rsp]
    mov edx, r12d
    sub edx, [rip + tr_first]
    mov ecx, r13d
    call inline_hit
    test eax, eax
    jz 11f
    and dword ptr [rsp + 16], ~(UB_PRESS | UB_DOUBLE | UB_RPRESS)
11: # x after the indent
    mov eax, [rsp + 4]
    imul eax, [rip + g_mt + 4*MI_12]
    add eax, [r15]
    add eax, [rip + g_mt + 4*MI_8]
    mov r14d, eax
    cmp dword ptr [rsp + 8], RWK_NODE
    jne .Ldr_marker
    mov eax, [rsp]
    NDP r15, rbx, rax           # r15: the node from here on
    # acting
    mov eax, [rsp + 16]
    test eax, UB_PRESS
    jz 3f
    test dword ptr [rbx + TR_flags], TRF_MULTI
    jz 20f
    mov rdi, rbx                # several selected: Ctrl toggles, Shift extends, else this one alone
    mov esi, [rsp]
    mov edx, [rip + g_mods]
    call select_click
    test dword ptr [rip + g_mods], MOD_CTRL | MOD_SHIFT
    jnz 3f                      # a selection gesture does nothing else
    jmp 2f
20: mov ecx, [rsp]
    cmp ecx, [rbx + TR_cursor]
    je 2f
    mov [rbx + TR_cursor], ecx
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
2:  # a press on the checkbox toggles it; on the chevron or a node with children expands it; a leaf
    # (or any node's second click) activates
    test dword ptr [r15 + ND_flags], NF_CHECK
    jz 21f
    mov eax, r14d               # after the chevron's place (leaves keep it too)
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_2]
    mov ecx, [rip + g_mx]
    cmp ecx, eax
    jl 21f
    add eax, [rip + g_mt + 4*MI_16]
    cmp ecx, eax
    jge 21f
    mov rdi, rbx
    mov esi, [rsp]
    call tree_toggle_check
    jmp 3f
21: test dword ptr [rsp + 16], UB_DOUBLE
    jz 23f
    mov rdi, rbx
    mov esi, [rsp]
    call tree_activate
    jmp 3f
23: cmp dword ptr [r15 + ND_kids], KIDS_LEAF
    je 24f
    mov rdi, rbx
    mov esi, [rsp]
    call tree_toggle
    jmp 3f
24: mov rdi, rbx
    mov esi, [rsp]
    call tree_activate
3:  mov eax, [rsp]              # the callbacks may have changed the store
    NDP r15, rbx, rax
    test dword ptr [rsp + 16], UB_RPRESS
    jz 4f
    mov ecx, [rsp]
    cmp ecx, [rbx + TR_cursor]
    je 31f
    mov [rbx + TR_cursor], ecx
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
31: mov rdi, rbx
    mov esi, TRO_menu
    mov edx, [rsp]
    mov ecx, [rip + g_mx]
    mov r8d, [rip + g_my]
    call call_op
    mov eax, [rsp]
    NDP r15, rbx, rax
4:  test dword ptr [r15 + ND_flags], NF_LIVE
    jz .Ldr_ret                 # gone meanwhile: the next frame shows the rows without it
    # background: the selected row, the hover, the keyboard's frame
    mov edi, [rbx + TR_rect]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, r13d
    mov edx, [rbx + TR_rect + 8]
    sub edx, [rip + g_mt + 4*MI_8]
    mov ecx, [rsp + 12]
    M r8d, MI_RADIUS
    mov eax, [rsp]
    cmp eax, [rbx + TR_cursor]
    je 40f
    test dword ptr [r15 + ND_flags], NF_SEL
    jz 41f
    COLOR r9d, T_SELECTION      # selected, not the cursor
    call gfx_round_rect
    jmp 43f
40: COLOR r9d, T_ACTIVE
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r8
    call gfx_round_rect
    pop r8
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    jmp 42f
41: test dword ptr [rsp + 16], UB_HOVER
    jz 43f
    COLOR r9d, T_HOVER
    call gfx_round_rect
    jmp 43f
42: # the keyboard's frame when the tree has it
    test dword ptr [rip + tr_focused], 1
    jz 43f
    COLOR r9d, T_ACCENT
    COLOR eax, T_ACTIVE
    push rax
    push rax
    call gfx_frame
    add rsp, 16
43: # chevron
    M ecx, MI_16
    cmp dword ptr [r15 + ND_kids], KIDS_LEAF
    je 44f
    mov edi, IC_CHEV_R
    test dword ptr [r15 + ND_flags], NF_OPEN
    jz 431f
    mov edi, IC_CHEV_D
431:mov esi, r14d
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    COLOR r8d, T_MUTED
    call icon_draw
    mov eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_2]
    add r14d, eax
    jmp 45f
44: mov eax, [rip + g_mt + 4*MI_16]     # leaves line up with the labels of nodes with children
    add eax, [rip + g_mt + 4*MI_2]
    add r14d, eax
45: # checkbox
    test dword ptr [r15 + ND_flags], NF_CHECK
    jz 46f
    M ecx, MI_14
    mov edi, r14d
    mov esi, [rsp + 12]
    sub esi, ecx
    sar esi, 1
    add esi, r13d
    mov edx, ecx
    M r8d, MI_3
    COLOR r9d, T_MUTED
    COLOR eax, T_INPUT
    test dword ptr [r15 + ND_flags], NF_CHECKED
    jz 451f
    COLOR r9d, T_ACCENT
    COLOR eax, T_ACCENT
451:push rax
    push rax
    call gfx_frame
    add rsp, 16
    test dword ptr [r15 + ND_flags], NF_CHECKED
    jz 452f
    M ecx, MI_14
    mov edi, IC_CHECK
    mov esi, r14d
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    COLOR r8d, T_ACCENT_FG
    call icon_draw
452:mov eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_4]
    add r14d, eax
46: # icon
    mov eax, [r15 + ND_icon]
    cmp eax, -1
    je 47f
    test eax, NDI_FILE
    jz 461f
    mov edi, eax
    and edi, 0xff
    shr eax, 8
    and eax, 0xff
    lea rdx, [rip + g_theme]
    mov r8d, [rdx + rax*4]
    jmp 462f
461:mov edi, eax
    push rdi
    push rdi
    mov edi, [r15 + ND_icolor]
    mov esi, T_MUTED
    call tree_color
    mov r8d, eax
    pop rdi
    pop rdi
462:M ecx, MI_16
    mov esi, r14d
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    call icon_draw
    mov eax, [rip + g_mt + 4*MI_20]
    add eax, [rip + g_mt + 4*MI_2]
    add r14d, eax
47: # badge at the right
    mov eax, [rbx + TR_rect]
    add eax, [rbx + TR_rect + 8]
    sub eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 20], eax         # the right edge for the label and description
    cmp dword ptr [rip + inl_n], 0
    je 471f
    mov eax, [rip + inl_left]   # inline buttons take the right end, over the badge
    sub eax, [rip + g_mt + 4*MI_4]
    mov [rsp + 20], eax
    jmp 48f
471:cmp dword ptr [r15 + ND_badge], 0
    je 48f
    mov edi, [rsp + 20]
    sub edi, [rip + g_mt + 4*MI_24]
    mov esi, r13d
    mov edx, [rsp + 12]
    mov ecx, [r15 + ND_badge]
    call badge_draw
    mov eax, [rsp + 20]
    sub eax, [rip + g_mt + 4*MI_28]
    mov [rsp + 20], eax
48: # label
    mov edi, [r15 + ND_lcolor]
    mov esi, T_PANEL_FG
    call tree_color
    mov ecx, eax
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, r14d
    mov r8d, [rsp + 20]
    sub r8d, r14d
    mov r9d, r13d
    call draw_label
    mov r14d, eax
    mov eax, [rsp]
    NDP r15, rbx, rax
    mov rax, [r15 + ND_desc]
    test rax, rax
    jz 49f
    mov rdi, rax
    call strlen
    mov r9, rax
    add r14d, [rip + g_mt + 4*MI_8]
    mov eax, [rsp + 20]
    sub eax, r14d
    jle 49f
    COLOR ecx, T_MUTED
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, r14d
    mov edx, r13d
    mov ecx, [rsp + 16 + 12]
    mov r8, [r15 + ND_desc]
    call ui_text_v_fit
    add rsp, 16
49: # inline buttons, and a click on one
    cmp dword ptr [rip + inl_n], 0
    je 491f
    mov rdi, rbx
    call inline_draw
    test eax, eax
    js 491f
    mov ecx, eax
    shl ecx, 4
    lea rax, [rip + inl_keys]
    mov rdi, rbx
    mov esi, TRO_action
    mov edx, [rsp]
    mov r9, [rax + rcx + 8]
    mov rcx, [rax + rcx]
    mov r8, r9
    call call_op
    jmp .Ldr_ret
491:# tooltip
    mov rax, [r15 + ND_tip]
    test rax, rax
    jz .Ldr_ret
    push rax
    push rax
    mov edi, [rbx + TR_idbase]
    add edi, r12d
    sub edi, [rip + tr_first]
    mov esi, [rbx + TR_rect]
    mov edx, r13d
    add edx, [rsp + 16 + 12]
    mov ecx, [rbx + TR_rect + 8]
    mov r8d, [rsp + 16 + 16]
    pop r9
    pop r9
    call tip_note_text
    jmp .Ldr_ret
.Ldr_marker:
    # Loading, Load more, a failed request with Retry
    mov eax, [rsp]
    NDP r15, rbx, rax
    cmp dword ptr [rsp + 8], RWK_LOADING
    jne 5f
    test dword ptr [r15 + ND_flags], NF_LOADING
    jnz 51f
    or dword ptr [r15 + ND_flags], NF_LOADING
    mov rdi, rbx
    mov esi, TRO_load
    mov edx, [rsp]
    call call_op
51: lea r8, [rip + .Lloading]
    COLOR r9d, T_MUTED
    jmp 7f
5:  cmp dword ptr [rsp + 8], RWK_MORE
    jne 6f
    test dword ptr [r15 + ND_flags], NF_MOREWAIT
    jnz 52f
    or dword ptr [r15 + ND_flags], NF_MOREWAIT
    mov rdi, rbx
    mov esi, TRO_more
    mov edx, [rsp]
    call call_op
52: lea r8, [rip + .Lmore]
    COLOR r9d, T_ACCENT
    jmp 7f
6:  test dword ptr [rsp + 16], UB_CLICK
    jz 61f
    mov eax, [rsp]
    NDP r15, rbx, rax
    and dword ptr [r15 + ND_flags], ~NF_ERROR
    or dword ptr [rbx + TR_flags], TRF_DIRTY
    mov rdi, rbx
    mov esi, TRO_retry
    mov edx, [rsp]
    call call_op
61: lea r8, [rip + .Lfailed]
    COLOR r9d, T_ERROR
7:  test dword ptr [rsp + 16], UB_HOVER
    jz 71f
    cmp dword ptr [rsp + 8], RWK_LOADING
    je 71f
    push r8
    push r9
    mov edi, [rbx + TR_rect]
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, r13d
    mov edx, [rbx + TR_rect + 8]
    sub edx, [rip + g_mt + 4*MI_8]
    mov ecx, [rsp + 16 + 12]
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
    pop r9
    pop r8
71: lea rdi, [rip + g_face_ui]
    mov esi, r14d
    add esi, [rip + g_mt + 4*MI_16]
    add esi, [rip + g_mt + 4*MI_2]
    mov edx, r13d
    mov ecx, [rsp + 12]
    call ui_text_c
.Ldr_ret:
    EPILOGUE

# draw_label(tr, node, x, argb, maxw, y) -> eax the x after it: the label cut with an ellipsis to
#   maxw, its hl ranges in the accent color
draw_label:
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], esi              # node
    mov [rsp + 4], edx          # x
    mov [rsp + 8], ecx          # color
    mov [rsp + 12], r8d         # maxw
    mov [rsp + 16], r9d         # row y
    call tree_node_label
    mov r12, rax
    mov r13, rdx
    mov [rsp + 24], r13         # bytes to draw
    mov dword ptr [rsp + 32], 0 # cut
    test r13, r13
    jz .Ldl_ret0
    lea rdi, [rip + g_face_ui]
    mov rsi, r12
    mov rdx, r13
    call text_width
    cmp eax, [rsp + 12]
    jle 1f
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lellipsis]
    mov edx, 3
    call text_width
    mov ecx, [rsp + 12]
    sub ecx, eax
    jle .Ldl_ret0
    lea rdi, [rip + g_face_ui]
    mov rsi, r12
    mov rdx, r13
    call text_fit
    mov [rsp + 24], rax
    mov dword ptr [rsp + 32], 1
1:  # the baseline
    M eax, MI_ROW
    sub eax, [rip + g_face_ui + FACE_ascent]
    sub eax, [rip + g_face_ui + FACE_descent]
    sar eax, 1
    add eax, [rsp + 16]
    add eax, [rip + g_face_ui + FACE_ascent]
    mov [rsp + 20], eax
    # the highlight ranges, sorted
    mov rdi, rbx
    mov esi, [rsp]
    call collect_hl
    mov r14d, eax               # ranges
    xor r15d, r15d              # bytes drawn
    xor ebx, ebx                # range index (rbx is free now: the store is not needed)
2:  cmp ebx, r14d
    jae 5f
    lea rax, [rip + hl_buf]
    mov ecx, [rax + rbx*8]      # from
    mov edx, [rax + rbx*8 + 4]  # to
    cmp rcx, r15
    jae 21f
    mov rcx, r15
21: cmp rdx, [rsp + 24]
    jbe 22f
    mov rdx, [rsp + 24]
22: cmp rcx, rdx
    jae 4f
    mov [rsp + 40], rcx
    mov [rsp + 48], rdx
    # [drawn, from) in the label's color, [from, to) in the accent
    mov rdx, rcx
    sub rdx, r15
    mov ecx, [rsp + 8]
    call seg_draw
    mov rdx, [rsp + 48]
    sub rdx, [rsp + 40]
    COLOR ecx, T_ACCENT
    call seg_draw
4:  inc ebx
    jmp 2b
5:  mov rdx, [rsp + 24]
    sub rdx, r15
    mov ecx, [rsp + 8]
    call seg_draw
    cmp dword ptr [rsp + 32], 0
    je 6f
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 4]
    mov edx, [rsp + 20]
    lea rcx, [rip + .Lellipsis]
    mov r8d, 3
    mov r9d, [rsp + 8]
    call text_draw
    mov [rsp + 4], eax
6:  mov eax, [rsp + 4]
    EPILOGUE
.Ldl_ret0:
    mov eax, [rsp + 4]
    EPILOGUE

# seg_draw(rdx bytes, ecx argb): the next bytes of the label (draw_label's frame: r12 label, r15 drawn)
seg_draw:
    test rdx, rdx
    jz 9f
    push rdx
    push rdx
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16 + 8 + 4]
    mov r9d, ecx
    lea rcx, [r12 + r15]
    mov r8, rdx
    mov edx, [rsp + 16 + 8 + 20]
    call text_draw
    mov [rsp + 16 + 8 + 4], eax
    pop rdx
    pop rdx
    add r15, rdx
9:  ret

# collect_hl(tr, node) -> eax how many hl ranges it has (16 at most) in hl_buf, sorted by start
collect_hl:
    PROLOGUE
    call tree_node_extra
    mov r12, rax
    lea r13, [rax + rdx]
    xor r14d, r14d
1:  cmp r12, r13
    jae 9f
    cmp r14d, 16
    jae 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + rr_tmp]
    call tree_rec_read
    test rax, rax
    jz 9f
    mov r12, rax
    lea rdi, [rip + rr_tmp]
    xor esi, esi
    lea rdx, [rip + .Lr_hl]
    call tree_rec_is
    test eax, eax
    jz 1b
    cmp qword ptr [rip + rr_tmp + RR_n], 4
    jb 1b
    lea rdi, [rip + rr_tmp]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 1b
    mov r15d, eax
    lea rdi, [rip + rr_tmp]
    mov esi, 2
    call tree_rec_num
    test edx, edx
    jz 1b
    cmp eax, r15d
    jbe 1b
    # insertion by start
    mov ecx, r14d
    lea rbx, [rip + hl_buf]
2:  test ecx, ecx
    jz 3f
    cmp [rbx + rcx*8 - 8], r15d
    jbe 3f
    mov rdx, [rbx + rcx*8 - 8]
    mov [rbx + rcx*8], rdx
    dec ecx
    jmp 2b
3:  mov [rbx + rcx*8], r15d
    mov [rbx + rcx*8 + 4], eax
    inc r14d
    jmp 1b
9:  mov eax, r14d
    EPILOGUE

# tree_set_actions(tr, TA*, n): the actions inline keys name (the owner keeps the records)
FN tree_set_actions
    mov [rdi + TR_actions], rsi
    mov [rdi + TR_nactions], rdx
    mov dword ptr [rip + g_dirty], 1
    ret

# tree_set_multi(tr, on): several nodes may be selected (Ctrl and Shift with clicks and arrows)
FN tree_set_multi
    and dword ptr [rdi + TR_flags], ~TRF_MULTI
    test esi, esi
    jz 1f
    or dword ptr [rdi + TR_flags], TRF_MULTI
1:  ret

# tree_selected(tr, i) -> eax the i-th selected node (node order), or -1 past the last; in single
#   mode the cursor is the selection
FN tree_selected
    test dword ptr [rdi + TR_flags], TRF_MULTI
    jnz 1f
    mov eax, -1
    test esi, esi
    jnz 9f
    mov eax, [rdi + TR_cursor]
    ret
1:  mov rcx, [rdi + TR_nodes + VEC_ptr]
    mov r8, [rdi + TR_nodes + VEC_len]
    xor eax, eax
2:  cmp rax, r8
    jae 8f
    imul rdx, rax, ND_SIZE
    test dword ptr [rcx + rdx + ND_flags], NF_SEL
    jz 3f
    test esi, esi
    jz 9f
    dec esi
3:  inc rax
    jmp 2b
8:  mov eax, -1
9:  ret

# clear_sel(tr): no node selected
clear_sel:
    mov rcx, [rdi + TR_nodes + VEC_ptr]
    mov r8, [rdi + TR_nodes + VEC_len]
    xor eax, eax
1:  cmp rax, r8
    jae 9f
    imul rdx, rax, ND_SIZE
    and dword ptr [rcx + rdx + ND_flags], ~NF_SEL
    inc rax
    jmp 1b
9:  ret

# select_click(tr, node, mods): Ctrl toggles the node, Shift selects the rows from the anchor to it,
#   neither selects it alone; the cursor goes to it
select_click:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov [rbx + TR_cursor], r12d
    or dword ptr [rbx + TR_flags], TRF_SELCHANGED
    test r13d, MOD_CTRL
    jz 1f
    NDP rax, rbx, r12
    xor dword ptr [rax + ND_flags], NF_SEL
    mov [rbx + TR_selanchor], r12d
    jmp 9f
1:  test r13d, MOD_SHIFT
    jz 5f
    mov rdi, rbx
    call clear_sel
    mov rdi, rbx
    mov esi, [rbx + TR_selanchor]
    call row_of
    mov r14d, eax
    mov rdi, rbx
    mov esi, r12d
    call row_of
    mov r15d, eax
    test r14d, r14d
    jns 2f
    mov r14d, r15d
2:  cmp r14d, r15d
    jle 3f
    xchg r14d, r15d
3:  cmp r14d, r15d
    jg 9f
    mov rax, [rbx + TR_rows + VEC_ptr]
    cmp word ptr [rax + r14*8 + RW_kind], RWK_NODE
    jne 4f
    mov eax, [rax + r14*8 + RW_node]
    NDP rcx, rbx, rax
    or dword ptr [rcx + ND_flags], NF_SEL
4:  inc r14d
    jmp 3b
5:  mov rdi, rbx
    call clear_sel
    NDP rax, rbx, r12
    or dword ptr [rax + ND_flags], NF_SEL
    mov [rbx + TR_selanchor], r12d
9:  EPILOGUE

# inline_hit(tr, node, visible row, y) -> eax 1 when the pointer is over one of the node's inline
#   buttons: they are laid out (inl_*) from the tree's right end, their presses taken
inline_hit:
    PROLOGUE 32
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rip + .Lr_inline]
    lea rcx, [rip + rr_tmp]
    call tree_extra_find
    test eax, eax
    jz 8f
    mov r13, [rip + rr_tmp + RR_data]
    mov r14, r13
    add r14, [rip + rr_tmp + RR_len]
    M eax, MI_24
    mov [rip + inl_size], eax
    mov eax, [rbx + TR_rect]
    add eax, [rbx + TR_rect + 8]
    sub eax, [rip + g_mt + 4*MI_16]
    mov [rip + inl_left], eax
    M ecx, MI_ROW
    sub ecx, [rip + inl_size]
    sar ecx, 1
    add ecx, [rsp + 4]
    mov [rip + inl_y], ecx
    mov dword ptr [rsp + 8], 0  # over one
.Lih_word:
    cmp dword ptr [rip + inl_n], 4
    jae .Lih_done
1:  cmp r13, r14                # the next key
    jae .Lih_done
    cmp byte ptr [r13], ' '
    jne 2f
    inc r13
    jmp 1b
2:  mov r15, r13
3:  cmp r15, r14
    jae 4f
    cmp byte ptr [r15], ' '
    je 4f
    inc r15
    jmp 3b
4:  # its action
    mov rcx, [rbx + TR_actions]
    xor edx, edx
5:  cmp rdx, [rbx + TR_nactions]
    jae 7f
    imul r8, rdx, TA_SIZE
    add r8, rcx
    mov rax, r15
    sub rax, r13
    cmp rax, [r8 + TA_keylen]
    jne 6f
    push rcx
    push rdx
    push r8
    push r8
    mov rdi, r13
    mov rsi, [r8 + TA_key]
    mov rdx, rax
    call memeq
    pop r8
    pop r8
    pop rdx
    pop rcx
    test eax, eax
    jnz 61f
6:  inc rdx
    jmp 5b
61: # a button for it, right to left
    mov eax, [rip + inl_n]
    mov ecx, eax
    shl ecx, 4
    lea rdx, [rip + inl_keys]
    mov [rdx + rcx], r13
    mov rdi, r15
    sub rdi, r13
    mov [rdx + rcx + 8], rdi
    lea rdx, [rip + inl_ta]
    mov [rdx + rax*8], r8
    mov ecx, [rip + inl_size]
    add ecx, [rip + g_mt + 4*MI_2]
    sub [rip + inl_left], ecx
    mov ecx, [rip + inl_left]
    lea rdx, [rip + inl_x]
    mov [rdx + rax*4], ecx
    mov edi, [rbx + TR_idbase]
    add edi, 0x8000
    mov esi, [rsp]
    shl esi, 2
    add edi, esi
    add edi, eax
    lea rdx, [rip + inl_id]
    mov [rdx + rax*4], edi
    mov esi, ecx
    mov edx, [rip + inl_y]
    mov ecx, [rip + inl_size]
    mov r8d, ecx
    call ui_btn
    mov ecx, [rip + inl_n]
    lea rdx, [rip + inl_bits]
    mov [rdx + rcx*4], eax
    inc dword ptr [rip + inl_n]
    test eax, UB_HOVER
    jz 7f
    mov dword ptr [rsp + 8], 1
7:  mov r13, r15
    jmp .Lih_word
.Lih_done:
    mov eax, [rsp + 8]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# inline_draw(tr) -> eax the button clicked, or -1: the laid-out inline buttons, their tooltips
inline_draw:
    PROLOGUE 16
    mov rbx, rdi
    mov dword ptr [rsp], -1
    xor r12d, r12d
1:  cmp r12d, [rip + inl_n]
    jae 9f
    lea rax, [rip + inl_bits]
    mov r13d, [rax + r12*4]
    lea rax, [rip + inl_x]
    mov r14d, [rax + r12*4]
    test r13d, UB_HOVER
    jz 2f
    mov edi, r14d
    mov esi, [rip + inl_y]
    mov edx, [rip + inl_size]
    mov ecx, edx
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
2:  lea rax, [rip + inl_ta]
    mov r15, [rax + r12*8]
    mov edi, [r15 + TA_icon]
    cmp edi, -1
    jne 3f
    mov edi, IC_DOT
3:  mov esi, r14d
    mov edx, [rip + inl_y]
    mov ecx, [rip + inl_size]
    mov r8d, ecx
    COLOR r9d, T_MUTED
    test r13d, UB_HOVER
    jz 4f
    COLOR r9d, T_FG
4:  call ui_icon_center
    mov rax, [r15 + TA_title]
    test rax, rax
    jz 5f
    push rax
    push rax
    lea rax, [rip + inl_id]
    mov edi, [rax + r12*4]
    mov esi, r14d
    mov edx, [rip + inl_y]
    add edx, [rip + inl_size]
    mov ecx, [rip + inl_size]
    mov r8d, r13d
    pop r9
    pop r9
    call tip_note_text
5:  test r13d, UB_CLICK
    jz 6f
    mov [rsp], r12d
6:  inc r12d
    jmp 1b
9:  mov eax, [rsp]
    EPILOGUE

# tree_dump(tr, sb): a line per row: "row I d=DEPTH open|closed|leaf|loading|more|error [cur]
#   [check=0|1] id=ID label=LABEL desc=D badge=N icon=I hl=F-T,..."
FN tree_dump
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call tree_rows
    xor r13d, r13d
.Ltdu_row:
    cmp r13, [rbx + TR_rows + VEC_len]
    jae .Ltdu_ret
    mov rax, [rbx + TR_rows + VEC_ptr]
    mov r14d, [rax + r13*8 + RW_node]
    movzx r15d, word ptr [rax + r13*8 + RW_kind]
    movzx eax, word ptr [rax + r13*8 + RW_depth]
    mov [rsp], eax
    mov rdi, r12
    lea rsi, [rip + .Ld_row]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_y]
    call sb_push_cstr
    M eax, MI_ROW
    imul eax, r13d
    add eax, [rbx + TR_rect + 4]
    sub eax, [rbx + TR_scroll]
    mov [rsp + 4], eax
    test eax, eax
    jns 11f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    neg dword ptr [rsp + 4]
11: mov rdi, r12
    mov esi, [rsp + 4]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_d]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [rsp]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    lea rsi, [rip + .Ld_loading]
    cmp r15d, RWK_LOADING
    je 1f
    lea rsi, [rip + .Ld_more]
    cmp r15d, RWK_MORE
    je 1f
    lea rsi, [rip + .Ld_error]
    cmp r15d, RWK_ERROR
    je 1f
    NDP rax, rbx, r14
    lea rsi, [rip + .Ld_leaf]
    cmp dword ptr [rax + ND_kids], KIDS_LEAF
    je 1f
    lea rsi, [rip + .Ld_closed]
    test dword ptr [rax + ND_flags], NF_OPEN
    jz 1f
    lea rsi, [rip + .Ld_open]
1:  mov rdi, r12
    call sb_push_cstr
    cmp r15d, RWK_NODE
    jne .Ltdu_next
    cmp r14d, [rbx + TR_cursor]
    jne 2f
    mov rdi, r12
    lea rsi, [rip + .Ld_cur]
    call sb_push_cstr
2:  NDP rax, rbx, r14
    test dword ptr [rax + ND_flags], NF_CHECK
    jz 3f
    mov rdi, r12
    lea rsi, [rip + .Ld_check]
    call sb_push_cstr
    NDP rax, rbx, r14
    mov esi, [rax + ND_flags]
    shr esi, 7
    and esi, 1
    mov rdi, r12
    call sb_push_u64
3:  mov rdi, r12
    lea rsi, [rip + .Ld_id]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, r14d
    call tree_node_id
    mov rdi, r12
    mov rsi, rax
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_label]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, r14d
    call tree_node_label
    mov rdi, r12
    mov rsi, rax
    call sb_push
    NDP rax, rbx, r14
    mov rsi, [rax + ND_desc]
    test rsi, rsi
    jz 4f
    push rsi
    push rsi
    mov rdi, r12
    lea rsi, [rip + .Ld_desc]
    call sb_push_cstr
    pop rsi
    pop rsi
    mov rdi, r12
    call sb_push_cstr
4:  NDP rax, rbx, r14
    cmp dword ptr [rax + ND_badge], 0
    je 5f
    mov rdi, r12
    lea rsi, [rip + .Ld_badge]
    call sb_push_cstr
    NDP rax, rbx, r14
    mov esi, [rax + ND_badge]
    mov rdi, r12
    call sb_push_u64
5:  NDP rax, rbx, r14
    mov eax, [rax + ND_icon]
    cmp eax, -1
    je 6f
    mov [rsp + 4], eax
    mov rdi, r12
    lea rsi, [rip + .Ld_icon]
    call sb_push_cstr
    mov esi, [rsp + 4]
    and esi, ~NDI_FILE
    and esi, 0xff
    mov rdi, r12
    call sb_push_u64
6:  mov rdi, rbx
    mov esi, r14d
    call collect_hl
    test eax, eax
    jz .Ltdu_next
    mov [rsp + 4], eax
    mov rdi, r12
    lea rsi, [rip + .Ld_hl]
    call sb_push_cstr
    mov dword ptr [rsp + 8], 0
7:  mov eax, [rsp + 8]
    cmp eax, [rsp + 4]
    jae .Ltdu_next
    test eax, eax
    jz 71f
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
71: mov eax, [rsp + 8]
    lea rcx, [rip + hl_buf]
    mov esi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov eax, [rsp + 8]
    lea rcx, [rip + hl_buf]
    mov esi, [rcx + rax*8 + 4]
    mov rdi, r12
    call sb_push_u64
    inc dword ptr [rsp + 8]
    jmp 7b
.Ltdu_next:
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r13
    jmp .Ltdu_row
.Ltdu_ret:
    EPILOGUE

.bss
.p2align 2
.globl tr_focused
tr_focused: .long 0             # the tree being drawn has the keyboard (tree_draw sets it)
tr_first: .long 0               # its first row in view: row ids count from it
inl_n: .long 0                  # the row's inline buttons: how many, where, their keys and state
inl_left: .long 0
inl_y: .long 0
inl_size: .long 0
inl_x: .zero 16
inl_id: .zero 16
inl_bits: .zero 16
.p2align 3
inl_keys: .zero 64              # ptr, len each
inl_ta: .zero 32

.section .rodata
.Lr_desc: .asciz "desc"
.Lr_tip: .asciz "tip"
.Lr_icon: .asciz "icon"
.Lr_color: .asciz "color"
.Lr_badge: .asciz "badge"
.Lr_check: .asciz "check"
.Lr_hl: .asciz "hl"
.Lr_inline: .asciz "inline"
.Lloading: .asciz "Loading\342\200\246"
.Lmore: .asciz "Load more"
.Lfailed: .asciz "Could not load \342\200\224 Retry"
.Lellipsis: .ascii "\342\200\246"
.Ld_row: .asciz "row "
.Ld_d: .asciz " d="
.Ld_y: .asciz " y="
.Ld_open: .asciz "open"
.Ld_closed: .asciz "closed"
.Ld_leaf: .asciz "leaf"
.Ld_loading: .asciz "loading"
.Ld_more: .asciz "more"
.Ld_error: .asciz "error"
.Ld_cur: .asciz " cur"
.Ld_check: .asciz " check="
.Ld_id: .asciz " id="
.Ld_label: .asciz " label="
.Ld_desc: .asciz " desc="
.Ld_badge: .asciz " badge="
.Ld_icon: .asciz " icon="
.Ld_hl: .asciz " hl="
.Lc_fg: .asciz "fg"
.Lc_muted: .asciz "muted"
.Lc_accent: .asciz "accent"
.Lc_error: .asciz "error"
.Lc_warning: .asciz "warning"
.Lc_success: .asciz "success"
.Lc_add: .asciz "add"
.Lc_mod: .asciz "mod"
.Lc_del: .asciz "del"
.p2align 3
color_names:
    .quad .Lc_fg, T_FG, .Lc_muted, T_MUTED, .Lc_accent, T_ACCENT, .Lc_error, T_ERROR
    .quad .Lc_warning, T_WARNING, .Lc_success, T_SUCCESS, .Lc_add, T_GIT_ADD, .Lc_mod, T_GIT_MOD
    .quad .Lc_del, T_GIT_DEL, 0, 0
.Li_file: .asciz "file"
.Li_folder: .asciz "folder"
.Li_folder_open: .asciz "folder-open"
.Li_search: .asciz "search"
.Li_check: .asciz "check"
.Li_close: .asciz "close"
.Li_plus: .asciz "plus"
.Li_minus: .asciz "minus"
.Li_dot: .asciz "dot"
.Li_refresh: .asciz "refresh"
.Li_branch: .asciz "branch"
.Li_pin: .asciz "pin"
.Li_puzzle: .asciz "puzzle"
.Li_more: .asciz "more"
.Li_terminal: .asciz "terminal"
.Li_spark: .asciz "spark"
.Li_user: .asciz "user"
.Li_arrow_up: .asciz "arrow-up"
.Li_arrow_down: .asciz "arrow-down"
.Li_discard: .asciz "discard"
.Li_gear: .asciz "gear"
.p2align 3
icon_names:
    .quad .Li_file, IC_FILE, .Li_folder, IC_FOLDER, .Li_folder_open, IC_FOLDER, .Li_search, IC_SEARCH
    .quad .Li_check, IC_CHECK, .Li_close, IC_CLOSE, .Li_plus, IC_PLUS, .Li_minus, IC_MINUS
    .quad .Li_dot, IC_DOT, .Li_refresh, IC_REFRESH, .Li_branch, IC_BRANCH, .Li_pin, IC_PIN
    .quad .Li_puzzle, IC_PUZZLE, .Li_more, IC_MORE, .Li_terminal, IC_TERMINAL, .Li_spark, IC_SPARK
    .quad .Li_user, IC_USER, .Li_arrow_up, IC_ARROW_UP, .Li_arrow_down, IC_ARROW_DN
    .quad .Li_discard, IC_DISCARD, .Li_gear, IC_SLIDERS, 0, 0
