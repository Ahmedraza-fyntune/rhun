# editor presentation: inlay hints (feature inlay-hints). rhun asks every matching provider for the
# hints of the lines around the view (present.s: when the document becomes active, 250 ms after
# edits, 100 ms after a scroll leaves the lines asked about); an answer replaces that provider's
# hints on those lines. A hint is virtual text (vtext.s, VK_HINT) at a position that moves with
# edits: an `after` hint stays after the text it follows, a `before` hint before the text it
# precedes. Each part may carry a tooltip, a command or a place to go; a double click applies the
# hint's edits (a type written out, say).
.include "rhun.inc"

.equ EDIT_MAX_WORDS, 6

.bss
.p2align 3
ih_new: .zero VEC_SIZE          # an answer's hints
ih_keys: .zero VEC_SIZE         # sort keys
ih_tmp: .zero VEC_SIZE          # the merged vector being built
# the hint being read: its parts (label, tip, extra: ptr, len each) and edits
pv_ptr: .zero 8 * 6 * IH_PARTS
.globl ev_rec
ev_rec: .zero 8 * 6 * IH_EDITS  # l1, c1, l2, c2, text ptr, len
vi_hint: .zero VI_SIZE
hdoc: .zero 32                  # "#DOC": the hint's own document for goto
tipbuf: .zero IH_TIP_MAX + 8    # a part's tooltip

.text

# ---------------- answers ----------------

# FN inlay_reply(doc, ext, body, len, version, PQR*) -> eax 1 taken, 0 dropped: "N" LF, then per
# hint "LINE COL SIDE NPARTS EXTRA_LEN" LF, NPARTS times "LABEL_LEN TIP_LEN PEXTRA_LEN" LF LABEL
# TIP PEXTRA, then EXTRA (up to 16 "edit L1 C1 L2 C2 LEN" records)
FN inlay_reply
    PROLOGUE 96
    mov r13, rdi                # doc
    mov [rsp], rsi              # ext
    mov rbx, rdx
    lea r12, [rdx + rcx]
    mov [rsp + 8], r8           # version
    mov [rsp + 16], r9          # PQR*
    lea rdi, [rip + ih_new]
    call ih_vec_clear
    call present_num
    test edx, edx
    jz .Lir_drop
    cmp rax, IH_MAX
    ja .Lir_drop
    mov r14, rax                # N
.Lir_hint:
    test r14, r14
    jz .Lir_done
    dec r14
    call present_num            # LINE
    test edx, edx
    jz .Lir_drop
    test rax, rax
    jz .Lir_drop
    mov [rsp + 24], rax
    call present_num            # COL
    test edx, edx
    jz .Lir_drop
    test rax, rax
    jz .Lir_drop
    mov [rsp + 32], rax
    call present_word           # SIDE
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Ls_after]
    push rdi
    push rsi
    call str_eq_cstr
    pop rsi
    pop rdi
    mov ecx, VS_AFTER
    test eax, eax
    jnz 1f
    lea rdx, [rip + .Ls_before]
    call str_eq_cstr
    test eax, eax
    jz .Lir_drop
    mov ecx, VS_BEFORE
1:  mov [rsp + 40], ecx
    call present_num            # NPARTS
    test edx, edx
    jz .Lir_drop
    test rax, rax
    jz .Lir_drop
    cmp rax, IH_PARTS
    ja .Lir_drop
    mov [rsp + 48], rax
    call present_num            # EXTRA_LEN
    test edx, edx
    jz .Lir_drop
    cmp rax, IH_EXTRA_MAX
    ja .Lir_drop
    mov [rsp + 56], rax
    # the parts
    xor r15d, r15d
    mov qword ptr [rsp + 64], 0 # the label's bytes so far
    mov qword ptr [rsp + 72], 0 # every part's bytes
2:  cmp r15, [rsp + 48]
    jae 5f
    call present_num            # LABEL_LEN
    test edx, edx
    jz .Lir_drop
    imul rcx, r15, 48
    lea rdi, [rip + pv_ptr]
    add rdi, rcx
    mov [rdi + 8], rax
    add [rsp + 64], rax
    call present_num            # TIP_LEN
    test edx, edx
    jz .Lir_drop
    cmp rax, IH_TIP_MAX
    ja .Lir_drop
    imul rcx, r15, 48
    lea rdi, [rip + pv_ptr]
    add rdi, rcx
    mov [rdi + 24], rax
    call present_num            # PEXTRA_LEN
    test edx, edx
    jz .Lir_drop
    cmp rax, IH_PEXTRA_MAX
    ja .Lir_drop
    imul rcx, r15, 48
    lea rdi, [rip + pv_ptr]
    add rdi, rcx
    mov [rdi + 40], rax
    cmp qword ptr [rsp + 64], IH_LABEL_MAX
    ja .Lir_drop
    # the bytes: label, tip, extra
    mov rax, r12
    sub rax, rbx
    mov rcx, [rdi + 8]
    add rcx, [rdi + 24]
    add rcx, [rdi + 40]
    cmp rcx, rax
    ja .Lir_drop
    add [rsp + 72], rcx
    mov [rdi], rbx
    mov rcx, [rdi + 8]
    xor eax, eax                # a label is one line
3:  cmp rax, rcx
    jae 4f
    cmp byte ptr [rbx + rax], 0x20
    jb .Lir_drop
    inc rax
    jmp 3b
4:  add rbx, rcx
    mov [rdi + 16], rbx
    add rbx, [rdi + 24]
    mov [rdi + 32], rbx
    add rbx, [rdi + 40]
    inc r15
    jmp 2b
5:  cmp qword ptr [rsp + 64], 0
    je .Lir_drop                # nothing to show
    # EXTRA: its edit records
    mov rax, r12
    sub rax, rbx
    cmp [rsp + 56], rax
    ja .Lir_drop
    mov rdi, rbx
    mov rsi, [rsp + 56]
    call edits_read             # -> rax edits, rdx their text bytes; rax -1 broken
    test rax, rax
    js .Lir_drop
    mov [rsp + 80], rax
    add [rsp + 72], rdx
    add rbx, [rsp + 56]
    # its place in the text
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 24]
    dec rdx
    mov rcx, [rsp + 32]
    dec rcx
    mov r8d, GR_RIGHT
    cmp dword ptr [rsp + 40], VS_AFTER
    je 6f
    mov r8d, GR_LEFT
6:  call tape_map_lc
    test rax, rax
    js .Lir_drop
    mov [rsp + 88], rax
    mov rdi, rsp
    call hint_make
    jmp .Lir_hint
.Lir_done:
    cmp rbx, r12
    jne .Lir_drop               # bytes after the last hint
    mov rdi, r13
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    call hints_merge
    test eax, eax
    jz .Lir_drop
    mov rdi, r13
    call pres_touch
    mov eax, 1
    EPILOGUE
.Lir_drop:
    lea rdi, [rip + ih_new]
    call ih_vec_clear
    xor eax, eax
    EPILOGUE

# hint_make(frame): the hint read into pv_ptr and ev_rec becomes a record in ih_new; inlay_reply's
# frame (its [rsp]) gives the rest
hint_make:
    PROLOGUE
    mov r15, rdi
    # blob: parts, edits, then the bytes
    mov rax, [r15 + 48]         # parts
    imul rax, rax, IHP_SIZE
    mov rcx, [r15 + 80]         # edits
    imul rcx, rcx, IHE_SIZE
    add rax, rcx
    mov r14, rax                # the bytes' offset
    add rax, [r15 + 72]
    mov rdi, rax
    call mem_alloc
    mov r13, rax                # the blob
    xor ebx, ebx
1:  cmp rbx, [r15 + 48]
    jae 3f
    imul r12, rbx, IHP_SIZE
    add r12, r13
    imul rax, rbx, 48
    lea rcx, [rip + pv_ptr]
    add rcx, rax
    mov [rsp], rcx
    # label, tip, extra
    mov [r12 + IHP_loff], r14d
    mov rdx, [rcx + 8]
    mov [r12 + IHP_llen], edx
    lea rdi, [r13 + r14]
    mov rsi, [rcx]
    add r14, rdx
    call memcpy
    mov rcx, [rsp]
    mov [r12 + IHP_toff], r14d
    mov rdx, [rcx + 24]
    mov [r12 + IHP_tlen], edx
    lea rdi, [r13 + r14]
    mov rsi, [rcx + 16]
    add r14, rdx
    call memcpy
    mov rcx, [rsp]
    mov [r12 + IHP_xoff], r14d
    mov rdx, [rcx + 40]
    mov [r12 + IHP_xlen], edx
    lea rdi, [r13 + r14]
    mov rsi, [rcx + 32]
    add r14, rdx
    call memcpy
    inc rbx
    jmp 1b
3:  xor ebx, ebx
4:  cmp rbx, [r15 + 80]
    jae 6f
    mov r12, [r15 + 48]
    imul r12, r12, IHP_SIZE
    imul rax, rbx, IHE_SIZE
    add r12, rax
    add r12, r13
    imul rax, rbx, 48
    lea rcx, [rip + ev_rec]
    add rcx, rax
    mov eax, [rcx]
    mov [r12 + IHE_l1], eax
    mov eax, [rcx + 8]
    mov [r12 + IHE_c1], eax
    mov eax, [rcx + 16]
    mov [r12 + IHE_l2], eax
    mov eax, [rcx + 24]
    mov [r12 + IHE_c2], eax
    mov [r12 + IHE_toff], r14d
    mov rdx, [rcx + 40]
    mov [r12 + IHE_tlen], edx
    lea rdi, [r13 + r14]
    mov rsi, [rcx + 32]
    add r14, rdx
    call memcpy
    inc rbx
    jmp 4b
6:  lea rdi, [rip + ih_new]
    mov esi, IH_SIZE
    call vec_push
    mov rcx, [r15 + 88]
    mov [rax + IH_pos], rcx
    mov rcx, [r15]
    mov [rax + IH_owner], rcx
    mov [rax + IH_blob], r13
    mov rcx, [r15 + 8]
    mov [rax + IH_ver], rcx
    mov ecx, [r15 + 40]
    mov [rax + IH_side], cl
    mov ecx, [r15 + 48]
    mov [rax + IH_nparts], cl
    mov ecx, [r15 + 80]
    mov [rax + IH_nedits], cl
    EPILOGUE

# edits_read(ptr, len) -> rax the "edit L1 C1 L2 C2 LEN" records found (into ev_rec, positions
# 0-based), rdx their texts' bytes; other records are skipped; rax -1 when the records are broken
# or there are more than 16 edits
.globl edits_read
edits_read:
    PROLOGUE 16
    mov rbx, rdi
    lea r12, [rdi + rsi]
    xor r13d, r13d              # edits
    xor r14d, r14d              # their bytes
.Ler_rec:
    cmp rbx, r12
    jae .Ler_done
    call present_word           # the record's name
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Ls_edit]
    call str_eq_cstr
    test eax, eax
    jnz .Ler_edit
    # another record: its last field before the line feed is its length
    xor r15d, r15d
1:  cmp rbx, r12
    jae 8f
    cmp byte ptr [rbx - 1], 10
    je 2f
    call present_num
    test edx, edx
    jz 11f
    mov r15, rax
    jmp 1b
11: call present_word
    jmp 1b
2:  mov rax, r12
    sub rax, rbx
    cmp r15, rax
    ja 8f
    add rbx, r15
    jmp .Ler_rec
.Ler_edit:
    cmp r13, IH_EDITS
    jae 8f
    imul r15, r13, 48
    lea rax, [rip + ev_rec]
    add r15, rax
    xor ecx, ecx
3:  cmp ecx, 5
    jae 4f
    mov [rsp], ecx
    call present_num
    test edx, edx
    jz 8f
    mov ecx, [rsp]
    cmp ecx, 4
    je 31f
    test rax, rax
    jz 8f                       # positions are 1-based
    dec rax
31: mov [r15 + rcx*8], rax
    inc ecx
    jmp 3b
4:  cmp byte ptr [rbx - 1], 10
    jne 8f
    mov rax, [r15 + 32]         # LEN
    mov rcx, r12
    sub rcx, rbx
    cmp rax, rcx
    ja 8f
    mov [r15 + 40], rax
    mov [r15 + 32], rbx
    add rbx, rax
    add r14, rax
    inc r13
    jmp .Ler_rec
.Ler_done:
    mov rax, r13
    mov rdx, r14
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# hints_merge(doc, ext, version, PQR*) -> eax 1: the provider's hints on the lines asked about go,
# ih_new's join, all sorted by position; 0 when the document would hold too many
hints_merge:
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], rsi
    mov r15, rcx
    mov [rsp + 8], rdx
    call pres_ensure
    mov r12, rax
    # the lines asked about, in the current text
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [r15 + PQR_l1]
    xor ecx, ecx
    mov r8d, GR_LEFT
    call tape_map_lc
    test rax, rax
    js 8f
    mov [rsp + 16], rax
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [r15 + PQR_l2]
    xor ecx, ecx
    mov r8d, GR_LEFT
    call tape_map_lc
    test rax, rax
    js 8f
    mov rdi, rbx
    mov rsi, rax
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_end
    mov [rsp + 24], rax
    # keep the others
    mov qword ptr [rip + ih_tmp + VEC_len], 0
    xor r13d, r13d
1:  cmp r13, [r12 + PRS_hints + VEC_len]
    jae 3f
    imul r14, r13, IH_SIZE
    add r14, [r12 + PRS_hints + VEC_ptr]
    inc r13
    mov rax, [rsp]
    cmp [r14 + IH_owner], rax
    jne 2f
    mov rax, [r14 + IH_pos]
    cmp rax, [rsp + 16]
    jb 2f
    cmp rax, [rsp + 24]
    ja 2f
    jmp 1b                      # replaced (freed once the merge is sure)
2:  lea rdi, [rip + ih_tmp]
    mov esi, IH_SIZE
    call vec_push
    mov rdi, rax
    mov rsi, r14
    mov edx, IH_SIZE
    call memcpy
    jmp 1b
3:  mov rax, [rip + ih_tmp + VEC_len]
    add rax, [rip + ih_new + VEC_len]
    cmp rax, IH_DOC_MAX
    ja 8f
    # the replaced ones' blobs go
    xor r13d, r13d
4:  cmp r13, [r12 + PRS_hints + VEC_len]
    jae 5f
    imul r14, r13, IH_SIZE
    add r14, [r12 + PRS_hints + VEC_ptr]
    inc r13
    mov rax, [rsp]
    cmp [r14 + IH_owner], rax
    jne 4b
    mov rax, [r14 + IH_pos]
    cmp rax, [rsp + 16]
    jb 4b
    cmp rax, [rsp + 24]
    ja 4b
    mov rdi, [r14 + IH_blob]
    call mem_free
    jmp 4b
5:  # the new ones join
    xor r13d, r13d
6:  cmp r13, [rip + ih_new + VEC_len]
    jae 7f
    imul rsi, r13, IH_SIZE
    add rsi, [rip + ih_new + VEC_ptr]
    inc r13
    push rsi
    push rsi
    lea rdi, [rip + ih_tmp]
    mov esi, IH_SIZE
    call vec_push
    pop rsi
    pop rsi
    mov rdi, rax
    mov edx, IH_SIZE
    call memcpy
    jmp 6b
7:  mov qword ptr [rip + ih_new + VEC_len], 0
    # sorted by position (keys: position, then the order above)
    mov r13, [rip + ih_tmp + VEC_len]
    mov qword ptr [rip + ih_keys + VEC_len], 0
    xor r14d, r14d
71: cmp r14, r13
    jae 72f
    lea rdi, [rip + ih_keys]
    mov esi, 8
    call vec_push
    imul rcx, r14, IH_SIZE
    add rcx, [rip + ih_tmp + VEC_ptr]
    mov rcx, [rcx + IH_pos]
    shl rcx, 17
    or rcx, r14
    mov [rax], rcx
    inc r14
    jmp 71b
72: mov rdi, [rip + ih_keys + VEC_ptr]
    mov rsi, r13
    call sort_u64
    mov qword ptr [r12 + PRS_hints + VEC_len], 0
    xor r14d, r14d
73: cmp r14, r13
    jae 74f
    lea rdi, [r12 + PRS_hints]
    mov esi, IH_SIZE
    call vec_push
    mov rdi, rax
    mov rsi, [rip + ih_keys + VEC_ptr]
    mov rsi, [rsi + r14*8]
    and esi, 0x1ffff
    imul rsi, rsi, IH_SIZE
    add rsi, [rip + ih_tmp + VEC_ptr]
    mov edx, IH_SIZE
    call memcpy
    inc r14
    jmp 73b
74: mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ih_vec_clear(vec): its hints and their blobs go
ih_vec_clear:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    imul rax, r12, IH_SIZE
    add rax, [rbx + VEC_ptr]
    mov rdi, [rax + IH_blob]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
    EPILOGUE

# ---------------- drawing ----------------

# FN inlay_line_inlays(doc, line): the line's hints, a VK_HINT inlay per part, to vt_add
FN inlay_line_inlays
    PROLOGUE 16
    cmp dword ptr [rip + cfg_inlay_hints], 0
    je 9f
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    cmp qword ptr [r13 + PRS_hints + VEC_len], 0
    je 9f
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov [rsp + 8], rax
    # the first hint at or after the line's start
    xor ecx, ecx
    mov rdx, [r13 + PRS_hints + VEC_len]
1:  cmp rcx, rdx
    jae 2f
    lea rsi, [rcx + rdx]
    shr rsi, 1
    imul rdi, rsi, IH_SIZE
    add rdi, [r13 + PRS_hints + VEC_ptr]
    mov rax, [rdi + IH_pos]
    cmp rax, [rsp]
    jae 11f
    lea rcx, [rsi + 1]
    jmp 1b
11: mov rdx, rsi
    jmp 1b
2:  mov r14, rcx
3:  cmp r14, [r13 + PRS_hints + VEC_len]
    jae 9f
    imul r15, r14, IH_SIZE
    add r15, [r13 + PRS_hints + VEC_ptr]
    mov rax, [r15 + IH_pos]
    cmp rax, [rsp + 8]
    ja 9f
    xor ebx, ebx                # part
4:  movzx eax, byte ptr [r15 + IH_nparts]
    cmp ebx, eax
    jae 6f
    imul rcx, rbx, IHP_SIZE
    add rcx, [r15 + IH_blob]
    lea rdi, [rip + vi_hint]
    mov rax, [r15 + IH_pos]
    sub rax, [rsp]
    mov [rdi + VI_off], rax
    mov eax, [rcx + IHP_loff]
    add rax, [r15 + IH_blob]
    mov [rdi + VI_text], rax
    mov eax, [rcx + IHP_llen]
    mov [rdi + VI_len], eax
    mov dword ptr [rdi + VI_cells], 0
    mov al, [r15 + IH_side]
    mov [rdi + VI_side], al
    mov byte ptr [rdi + VI_kind], VK_HINT
    mov word ptr [rdi + VI_flags], 0
    mov rax, r14
    shl rax, 8
    or rax, rbx
    mov [rdi + VI_ref], rax
    COLOR eax, T_INLAY
    mov [rdi + VI_fg], eax
    COLOR eax, T_INLAY_BG
    mov [rdi + VI_bg], eax
    mov dword ptr [rdi + VI_prio], 0
    call vt_add
    inc ebx
    jmp 4b
6:  inc r14
    jmp 3b
9:  EPILOGUE

# ---------------- pointer ----------------

# hint_part(doc, ref) -> rax IH*, rdx IHP* of an inlay's reference (0 when it is gone)
hint_part:
    mov rax, [rdi + DOC_pres]
    test rax, rax
    jz 8f
    mov rcx, rsi
    shr rcx, 8
    cmp rcx, [rax + PRS_hints + VEC_len]
    jae 8f
    imul rcx, rcx, IH_SIZE
    add rcx, [rax + PRS_hints + VEC_ptr]
    movzx edx, sil
    movzx eax, byte ptr [rcx + IH_nparts]
    cmp edx, eax
    jae 8f
    imul rdx, rdx, IHP_SIZE
    add rdx, [rcx + IH_blob]
    mov rax, rcx
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# FN inlay_tip(doc, ref) -> rax the part's tooltip (a cstr in tipbuf), or 0
FN inlay_tip
    call hint_part
    test rax, rax
    jz 8f
    mov ecx, [rdx + IHP_tlen]
    test ecx, ecx
    jz 8f
    mov esi, [rdx + IHP_toff]
    add rsi, [rax + IH_blob]
    lea rdi, [rip + tipbuf]
    mov edx, ecx
    mov byte ptr [rdi + rdx], 0
    sub rsp, 8
    call memcpy
    add rsp, 8
    lea rax, [rip + tipbuf]
    ret
8:  xor eax, eax
    ret

# FN inlay_click(doc, ref) -> eax 1 when a press on a hint part did something: a double click
# applies the hint's edits; a click runs the part's command or goes to its place
FN inlay_click
    PROLOGUE 32
    mov rbx, rdi
    call hint_part
    test rax, rax
    jz 8f
    mov r12, rax                # IH*
    mov r13, rdx                # IHP*
    cmp dword ptr [rip + g_clicks], 2
    jne 1f
    cmp byte ptr [r12 + IH_nedits], 0
    je 1f
    mov rdi, rbx
    mov rsi, r12
    call hint_apply
    mov eax, 1
    EPILOGUE
1:  mov r14d, [r13 + IHP_xlen]
    test r14d, r14d
    jz 8f
    mov r15d, [r13 + IHP_xoff]
    add r15, [r12 + IH_blob]    # the part's extra records
    mov rdi, r15
    mov rsi, r14
    lea rdx, [rip + .Ls_command]
    call extra_find
    test rax, rax
    jz 2f
    mov rdi, [r12 + IH_owner]
    mov rsi, rax
    call cmdref_parse
    test rax, rax
    jz 8f
    mov [rsp], rax
    mov rdi, rax
    mov rsi, [rbx + DOC_id]
    call cmdref_invoke
    mov rdi, [rsp]
    call cmdref_free
    mov eax, 1
    EPILOGUE
2:  mov rdi, r15
    mov rsi, r14
    lea rdx, [rip + .Ls_goto]
    call extra_find
    test rax, rax
    jz 8f
    # "goto L C LEN" LF PATH (none: this document)
    mov rcx, [r12 + IH_owner]
    mov [rsp + 24], rcx
    mov [rsp], rbx
    mov rbx, rax
    lea r12, [rax + rdx]
    call present_word
    call present_num
    test edx, edx
    jz 81f
    mov [rsp + 8], rax
    call present_num
    test edx, edx
    jz 81f
    mov [rsp + 16], rax
    call present_num
    test edx, edx
    jz 81f
    cmp byte ptr [rbx - 1], 10
    jne 81f
    mov rcx, r12
    sub rcx, rbx
    cmp rax, rcx
    ja 81f
    mov r13, rbx                # the path
    mov r14, rax
    mov rbx, [rsp]
    test r14, r14
    jnz 3f
    lea r13, [rip + hdoc]       # "#DOC"
    mov byte ptr [r13], '#'
    lea rdi, [r13 + 1]
    mov rsi, [rbx + DOC_id]
    call fmt_u64
    lea r14, [rax + 1]
3:  mov rdi, [rsp + 24]
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    call rview_open_at
    mov eax, 1
    EPILOGUE
81: mov rbx, [rsp]
8:  xor eax, eax
    EPILOGUE

# hint_apply(doc, IH*): its edits, from its version onto the text, as one undo step
hint_apply:
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call doc_begin_group
    movzx r13d, byte ptr [r12 + IH_nedits]
    # from the last to the first, so earlier positions hold
1:  test r13d, r13d
    jz 8f
    dec r13d
    movzx eax, byte ptr [r12 + IH_nparts]
    imul rax, rax, IHP_SIZE
    imul rcx, r13, IHE_SIZE
    add rax, rcx
    add rax, [r12 + IH_blob]
    mov r14, rax                # IHE*
    mov rdi, rbx
    mov rsi, [r12 + IH_ver]
    mov edx, [r14 + IHE_l1]
    mov ecx, [r14 + IHE_c1]
    mov r8d, GR_RIGHT
    call tape_map_lc
    test rax, rax
    js 1b
    mov r15, rax
    mov rdi, rbx
    mov rsi, [r12 + IH_ver]
    mov edx, [r14 + IHE_l2]
    mov ecx, [r14 + IHE_c2]
    mov r8d, GR_LEFT
    call tape_map_lc
    test rax, rax
    js 1b
    cmp rax, r15
    jb 1b
    mov rdx, rax
    sub rdx, r15
    jz 2f
    mov rdi, rbx
    mov rsi, r15
    mov ecx, EK_OTHER
    call doc_delete
2:  mov edx, [r14 + IHE_tlen]
    test edx, edx
    jz 1b
    mov ecx, [r14 + IHE_toff]
    add rcx, [r12 + IH_blob]
    mov rdi, rbx
    mov rsi, r15
    mov rax, rdx
    mov rdx, rcx
    mov rcx, rax
    mov r8d, EK_OTHER
    call doc_insert
    jmp 1b
8:  mov rdi, rbx
    call doc_end_group
    mov rdi, rbx
    call ed_touch
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- edits ----------------

# FN inlay_shift(doc, entry): hints move with an edit: an after hint stays after its text, a before
# hint before its text
FN inlay_shift
    PROLOGUE
    mov rbx, rdi
    mov rax, [rdi + DOC_pres]
    mov r14, [rax + PRS_hints + VEC_len]
    test r14, r14
    jz 9f
    mov r15, [rax + PRS_hints + VEC_ptr]
    mov r12, rsi
    mov rsi, [r12 + TE_pos]
    mov rdx, [r12 + TE_del]
    mov rcx, [r12 + TE_ins]
1:  mov r8d, GR_RIGHT
    cmp byte ptr [r15 + IH_side], VS_AFTER
    je 2f
    mov r8d, GR_LEFT
2:  mov rdi, [r15 + IH_pos]
    call tape_shift
    mov [r15 + IH_pos], rax
    add r15, IH_SIZE
    dec r14
    jnz 1b
    # an after hint and a before hint at one gap part at a line break typed there: the order by
    # position comes back (inlay_line_inlays searches it), one stable insertion pass
    mov rax, [rbx + DOC_pres]
    mov r14, [rax + PRS_hints + VEC_len]
    mov r15, [rax + PRS_hints + VEC_ptr]
    mov r12d, 1
3:  cmp r12, r14
    jae 9f
    imul r13, r12, IH_SIZE
    add r13, r15
    inc r12
    mov rax, [r13 + IH_pos]
    cmp rax, [r13 - IH_SIZE + IH_pos]
    jae 3b
    # r13 goes back to its place: kept on the stack while the ones before it move up
    sub rsp, IH_SIZE + 8
    mov rdi, rsp
    mov rsi, r13
    mov edx, IH_SIZE
    call memcpy
4:  cmp r13, r15
    jbe 5f
    mov rax, [rsp + IH_pos]
    cmp rax, [r13 - IH_SIZE + IH_pos]
    jae 5f
    mov rdi, r13
    lea rsi, [r13 - IH_SIZE]
    mov edx, IH_SIZE
    call memcpy
    sub r13, IH_SIZE
    jmp 4b
5:  mov rdi, r13
    mov rsi, rsp
    mov edx, IH_SIZE
    call memcpy
    add rsp, IH_SIZE + 8
    jmp 3b
9:  EPILOGUE

# ---------------- lifetime ----------------

# FN inlay_free(PRS): its hints go
FN inlay_free
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rbx + PRS_hints]
    call ih_vec_clear
    lea rdi, [rbx + PRS_hints]
    call vec_free
    EPILOGUE

# FN inlay_ext_gone(ext): the hints it provided go
FN inlay_ext_gone
    PROLOGUE 16
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + g_tabs + VEC_len]
    jae 9f
    imul rax, r13, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc r13
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rbx, [rax + TAB_doc]
    test rbx, rbx
    jz 1b
    mov r14, [rbx + DOC_pres]
    test r14, r14
    jz 1b
    xor r15d, r15d              # read
    mov qword ptr [rsp], 0      # write
2:  cmp r15, [r14 + PRS_hints + VEC_len]
    jae 4f
    imul rsi, r15, IH_SIZE
    add rsi, [r14 + PRS_hints + VEC_ptr]
    inc r15
    cmp [rsi + IH_owner], r12
    jne 3f
    mov rdi, [rsi + IH_blob]
    call mem_free
    jmp 2b
3:  mov rdi, [rsp]
    inc qword ptr [rsp]
    imul rdi, rdi, IH_SIZE
    add rdi, [r14 + PRS_hints + VEC_ptr]
    cmp rdi, rsi
    je 2b
    mov edx, IH_SIZE
    call memcpy
    jmp 2b
4:  mov rax, [rsp]
    cmp rax, [r14 + PRS_hints + VEC_len]
    je 1b
    mov [r14 + PRS_hints + VEC_len], rax
    mov rdi, rbx
    call pres_touch
    jmp 1b
9:  EPILOGUE

# ---------------- headless ----------------

# FN inlay_dump(doc, sb): "hint L C SIDE label=TEXT[|TEXT...] [tip] [cmd] [edits=N]" per hint
FN inlay_dump
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + DOC_pres]
    test r13, r13
    jz 9f
    xor r14d, r14d
1:  cmp r14, [r13 + PRS_hints + VEC_len]
    jae 9f
    imul r15, r14, IH_SIZE
    add r15, [r13 + PRS_hints + VEC_ptr]
    inc r14
    mov rdi, r12
    lea rsi, [rip + .Ls_hint]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [r15 + IH_pos]
    call doc_line_of
    mov [rsp], rax
    lea rsi, [rax + 1]
    mov rdi, r12
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rsp]
    call doc_line_start
    mov rsi, [r15 + IH_pos]
    sub rsi, rax
    inc rsi
    mov rdi, r12
    call sb_push_u64
    lea rsi, [rip + .Ls_sp_after]
    cmp byte ptr [r15 + IH_side], VS_AFTER
    je 2f
    lea rsi, [rip + .Ls_sp_before]
2:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ls_label]
    call sb_push_cstr
    xor ecx, ecx
3:  movzx eax, byte ptr [r15 + IH_nparts]
    cmp ecx, eax
    jae 5f
    mov [rsp + 8], ecx
    test ecx, ecx
    jz 4f
    mov rdi, r12
    mov esi, '|'
    call sb_push_byte
    mov ecx, [rsp + 8]
4:  imul rax, rcx, IHP_SIZE
    add rax, [r15 + IH_blob]
    mov esi, [rax + IHP_loff]
    add rsi, [r15 + IH_blob]
    mov edx, [rax + IHP_llen]
    mov rdi, r12
    call sb_push
    mov ecx, [rsp + 8]
    inc ecx
    jmp 3b
5:  movzx eax, byte ptr [r15 + IH_nedits]
    test eax, eax
    jz 6f
    mov rdi, r12
    lea rsi, [rip + .Ls_edits]
    call sb_push_cstr
    movzx esi, byte ptr [r15 + IH_nedits]
    mov rdi, r12
    call sb_push_u64
6:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.Ls_after: .asciz "after"
.Ls_before: .asciz "before"
.Ls_edit: .asciz "edit"
.Ls_command: .asciz "command"
.Ls_goto: .asciz "goto"
.Ls_hint: .asciz "hint "
.Ls_sp_after: .asciz " after "
.Ls_sp_before: .asciz " before "
.Ls_label: .asciz "label="
.Ls_edits: .asciz " edits="
