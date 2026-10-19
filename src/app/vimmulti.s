# Vim with several cursors. A normal or visual mode key runs once for every selection: each in
# turn is the primary while the others stay in DOC_selections, so the edits one makes move the
# others (docselection.s maps them), and the vim state the key found (count, pending operator,
# prefix, mode) is given back before each. The whole command is one undo step that brings the
# selections back. Yanks and deletes at several cursors make one copy with a piece each, which p
# and P put back paired. Insert mode needs nothing: its keys go to the editor's multi-selection
# paths. Keys about one place (searches, :, J, r, ~, > <, z, page keys) collapse to the primary.
.include "rhun.inc"

.equ VM_MAX, DOC_SELECTIONS_MAX
# vim.s's keys without a character
.equ VK_ESC_KEY, 0x110000
.equ VK_PGUP_KEY, 0x110007
.equ VK_PGDN_KEY, 0x110008
.equ VK_REDO_KEY, 0x11000c
.equ VK_HALFDN_KEY, 0x11000d
.equ VK_HALFUP_KEY, 0x11000e

# a yanked piece
STRUCT
F VP_index, 8                   # the cursor it came from
F VP_offset, 8                  # its bytes in vm_text
F VP_len, 8
F VP_line, 8                    # linewise
ENDSTRUCT VP_SIZE

.bss
.p2align 3
vm_n: .quad 0
vm_pairs: .zero DMP_SIZE*VM_MAX # every cursor, the primary first, kept current between runs
vm_tmp: .zero DMP_SIZE*VM_MAX   # the one running first, then the others
vm_cols: .zero 8*VM_MAX         # the preferred column each one ended with
vm_rank: .zero 8*VM_MAX         # its place in the text (pieces go in this order)
.globl vm_cur
vm_cur: .quad 0                 # the cursor running now
vm_fn: .quad 0
vm_key: .long 0
vm_state: .zero 20              # v_count, v_opcount, v_op, v_prefix, g_vim_mode the key found
.globl vm_collect, vm_piece
vm_collect: .long 0             # vyank hands its text to vm_yank_piece
vm_piece: .long 0               # vput_text puts a piece: no line copy check on it
vm_pairing: .long 0
.p2align 3
vm_npieces: .quad 0
vm_pieces: .zero VP_SIZE*VM_MAX
vm_text: .zero SB_SIZE
vm_seg: .quad 0                 # vm_put: the clipboard's pieces, or 0
vm_ptr: .quad 0
vm_len: .quad 0
vm_undo: .quad 0                # undo records before the command
vm_snap: .quad 0                # the selections before it (owned until given to the first record)
vm_bcur: .quad 0
vm_banchor: .quad 0

.text

# vm_each(fn): fn() once for every cursor of the active document, as described above; then the
# cursors are the selections (merged where they meet), each keeping the preferred column it ended
# with. Stops early if fn changed the number of selections.
FN vm_each
    PROLOGUE 16
    mov [rip + vm_fn], rdi
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    lea rsi, [rip + vm_pairs]
    call sel_collect
    mov [rip + vm_n], rax
    cmp rax, VM_MAX
    jbe 1f
    mov qword ptr [rip + vm_n], VM_MAX
1:  mov rax, [rbx + DOC_prefx]
    mov [rsp], rax
    xor r12d, r12d
.Lve_each:
    cmp r12, [rip + vm_n]
    jae .Lve_done
    mov [rip + vm_cur], r12
    # this one first, then the others in their order
    lea r13, [rip + vm_pairs]
    lea r14, [rip + vm_tmp]
    mov rax, r12
    shl rax, 4
    mov rcx, [r13 + rax + DMP_cur]
    mov [r14 + DMP_cur], rcx
    mov rcx, [r13 + rax + DMP_anchor]
    mov [r14 + DMP_anchor], rcx
    mov r15d, 1
    xor ecx, ecx
2:  cmp rcx, [rip + vm_n]
    jae 3f
    cmp rcx, r12
    je 21f
    mov rax, rcx
    shl rax, 4
    mov rdx, r15
    shl rdx, 4
    mov r8, [r13 + rax + DMP_cur]
    mov [r14 + rdx + DMP_cur], r8
    mov r8, [r13 + rax + DMP_anchor]
    mov [r14 + rdx + DMP_anchor], r8
    inc r15
21: inc rcx
    jmp 2b
3:  mov rdi, rbx
    mov rsi, r14
    mov rdx, [rip + vm_n]
    call doc_selections_set
    test eax, eax
    jz .Lve_done
    # its preferred column for j and k
    mov rax, [rsp]
    test r12, r12
    jz 4f
    cmp rax, -1
    je 4f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call sel_col_lookup
4:  mov [rbx + DOC_prefx], rax
    call [rip + vm_fn]
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call doc_selections_count
    cmp rax, [rip + vm_n]
    jne .Lve_lost
    lea rax, [rip + vm_cols]
    mov rcx, [rbx + DOC_prefx]
    mov [rax + r12*8], rcx
    # where all of them are now
    lea r13, [rip + vm_pairs]
    mov rax, r12
    shl rax, 4
    mov rcx, [rbx + DOC_cur]
    mov [r13 + rax + DMP_cur], rcx
    mov rcx, [rbx + DOC_anchor]
    mov [r13 + rax + DMP_anchor], rcx
    mov r14, [rbx + DOC_selections]
    add r14, DMS_DATA
    xor ecx, ecx
5:  cmp rcx, [rip + vm_n]
    jae 6f
    cmp rcx, r12
    je 51f
    mov rax, rcx
    shl rax, 4
    mov rdx, [r14 + DMP_cur]
    mov [r13 + rax + DMP_cur], rdx
    mov rdx, [r14 + DMP_anchor]
    mov [r13 + rax + DMP_anchor], rdx
    add r14, DMP_SIZE
51: inc rcx
    jmp 5b
6:  inc r12
    jmp .Lve_each
.Lve_done:
    # the columns by caret, then the selections
    mov rcx, [rip + vm_n]
    shl rcx, 4
    lea rdi, [rip + sel_pairs]
    lea rsi, [rip + vm_pairs]
    mov rdx, rcx
    call memcpy
    lea rdi, [rip + sel_cols]
    lea rsi, [rip + vm_cols]
    mov rdx, [rip + vm_n]
    shl rdx, 3
    call memcpy
    mov rdi, rbx
    mov rsi, [rip + vm_n]
    call sel_col_store
    mov rdi, rbx
    lea rsi, [rip + sel_pairs]
    mov rdx, [rip + vm_n]
    call sel_install
    mov rax, [rip + vm_cols]
    mov [rbx + DOC_prefx], rax
    EPILOGUE
.Lve_lost:
    mov rdi, rbx
    call sel_collapse
    EPILOGUE

# vm_ranks(): vm_rank of every selection: how many start before it
vm_ranks:
    PROLOGUE 16
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call doc_selections_count
    mov r12, rax
    cmp r12, VM_MAX
    jbe 1f
    mov r12, VM_MAX
1:  xor r13d, r13d
2:  cmp r13, r12
    jae 9f
    mov rdi, rbx
    mov rsi, r13
    call doc_selections_get
    cmp rax, rdx
    cmova rax, rdx
    mov r14, rax                # its start
    xor r15d, r15d              # rank
    mov qword ptr [rsp], 0
3:  mov rsi, [rsp]
    cmp rsi, r12
    jae 4f
    inc qword ptr [rsp]
    mov rdi, rbx
    call doc_selections_get
    cmp rax, rdx
    cmova rax, rdx
    cmp rax, r14
    jae 3b
    inc r15
    jmp 3b
4:  lea rax, [rip + vm_rank]
    mov [rax + r13*8], r15
    inc r13
    jmp 2b
9:  EPILOGUE

# vm_begin(): the undo records and selections before a command
vm_begin:
    PROLOGUE
    mov rbx, [rip + g_doc]
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rip + vm_undo], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + vm_bcur], rax
    mov rax, [rbx + DOC_anchor]
    mov [rip + vm_banchor], rax
    mov rdi, rbx
    call doc_selections_snapshot
    mov [rip + vm_snap], rax
    EPILOGUE

# vm_end(): the records the command made are one undo step: undo brings back the selections from
# before it, redo the ones after it
vm_end:
    PROLOGUE
    mov rbx, [rip + g_doc]
    mov rax, [rip + vm_undo]
    cmp rax, [rbx + DOC_undo + VEC_len]
    jae 8f
    imul r12, rax, UR_SIZE
    add r12, [rbx + DOC_undo + VEC_ptr]
    mov rcx, [r12 + UR_group]
    lea rdx, [r12 + UR_SIZE]
    mov r8, [rbx + DOC_undo + VEC_len]
    imul r8, r8, UR_SIZE
    add r8, [rbx + DOC_undo + VEC_ptr]
1:  cmp rdx, r8
    jae 2f
    mov [rdx + UR_group], rcx
    add rdx, UR_SIZE
    jmp 1b
2:  mov rdi, [r12 + UR_beforeselections]
    call mem_free
    mov rax, [rip + vm_snap]
    mov [r12 + UR_beforeselections], rax
    mov qword ptr [rip + vm_snap], 0
    mov rax, [rip + vm_bcur]
    mov [r12 + UR_cur], rax
    mov rax, [rip + vm_banchor]
    mov [r12 + UR_anchor], rax
    mov rdi, rbx
    mov rsi, [rip + vm_undo]
    call doc_selections_record_after
    mov qword ptr [rbx + DOC_lastkind], EK_OTHER
8:  mov rdi, [rip + vm_snap]
    mov qword ptr [rip + vm_snap], 0
    call mem_free
    EPILOGUE

# vm_cmd(key): vim_key's key with several cursors
FN vm_cmd
    PROLOGUE
    mov [rip + vm_key], edi
    mov r12d, edi
    mov rbx, [rip + g_doc]
    mov eax, [rip + v_prefix]
    test eax, eax
    jnz .Lvm_prefix
    cmp dword ptr [rip + v_op], 0
    jne .Lvm_pending
    lea rdi, [rip + vm_one_place]
    mov esi, r12d
    call vm_in
    test eax, eax
    jnz .Lvm_single
    cmp dword ptr [rip + g_vim_mode], VM_VISUAL
    jae .Lvm_visual
    cmp r12d, VK_ESC_KEY
    je .Lvm_single              # normal mode: back to the primary
    cmp r12d, 'u'
    je .Lvm_undo
    cmp r12d, VK_REDO_KEY
    je .Lvm_undo
    cmp r12d, 'o'
    je .Lvm_wrap
    cmp r12d, 'O'
    je .Lvm_wrap
    lea rdi, [rip + vm_once]
    mov esi, r12d
    call vm_in
    test eax, eax
    jnz .Lvm_once
    jmp .Lvm_each
.Lvm_visual:
    cmp r12d, 'u'               # visual u U: case, about one place here
    je .Lvm_single
    cmp r12d, 'U'
    je .Lvm_single
    cmp r12d, 'p'
    je .Lvm_once
    cmp r12d, 'P'
    je .Lvm_once
    jmp .Lvm_each
.Lvm_pending:                   # d c y wait for a motion
    cmp r12d, '/'
    je .Lvm_single
    cmp r12d, '?'
    je .Lvm_single
    jmp .Lvm_each
.Lvm_prefix:
    cmp eax, 'g'
    jne .Lvm_each
    cmp r12d, 'b'
    je .Lvm_once                # gb adds a cursor
    cmp r12d, 'g'
    je .Lvm_each
    cmp r12d, 'u'
    je .Lvm_single
    cmp r12d, 'U'
    je .Lvm_single
    cmp r12d, '~'
    je .Lvm_single
    jmp .Lvm_each
.Lvm_single:
    mov rdi, rbx
    call sel_collapse
.Lvm_once:
    mov edi, r12d
    call vcmd
    EPILOGUE
.Lvm_undo:
    call vm_undo_keys
    EPILOGUE
.Lvm_wrap:                      # o O: a line at every cursor already; undo brings the cursors back
    call vm_begin
    mov edi, r12d
    call vcmd
    call vm_end
    jmp 1f
.Lvm_each:
    mov eax, [rip + v_count]
    mov [rip + vm_state], eax
    mov eax, [rip + v_opcount]
    mov [rip + vm_state + 4], eax
    mov eax, [rip + v_op]
    mov [rip + vm_state + 8], eax
    mov eax, [rip + v_prefix]
    mov [rip + vm_state + 12], eax
    mov eax, [rip + g_vim_mode]
    mov [rip + vm_state + 16], eax
    call vm_begin
    call vm_ranks
    mov qword ptr [rip + vm_npieces], 0
    lea rdi, [rip + vm_text]
    call sb_clear
    mov dword ptr [rip + vm_collect], 1
    lea rdi, [rip + vm_one]
    call vm_each
    mov dword ptr [rip + vm_collect], 0
    cmp qword ptr [rip + vm_npieces], 0
    je 3f
    call vm_clip_set
3:  call vm_end
    # a change that goes on in insert mode: Esc makes all of it one step
1:  cmp dword ptr [rip + g_vim_mode], VM_INSERT
    jne 2f
    cmp rbx, [rip + v_chgdoc]
    jne 2f
    mov rax, [rip + vm_undo]
    mov [rip + v_chglen], rax
2:  EPILOGUE

# vm_one(): the key for the cursor running now, from the state the key found
vm_one:
    sub rsp, 8
    mov eax, [rip + vm_state]
    mov [rip + v_count], eax
    mov eax, [rip + vm_state + 4]
    mov [rip + v_opcount], eax
    mov eax, [rip + vm_state + 8]
    mov [rip + v_op], eax
    mov eax, [rip + vm_state + 12]
    mov [rip + v_prefix], eax
    mov eax, [rip + vm_state + 16]
    mov [rip + g_vim_mode], eax
    mov edi, [rip + vm_key]
    call vcmd
    add rsp, 8
    ret

# vm_in(table, key) -> eax 1 when the zero-terminated dword table has the key
vm_in:
1:  mov eax, [rdi]
    test eax, eax
    jz 2f
    add rdi, 4
    cmp eax, esi
    jne 1b
    mov eax, 1
    ret
2:  xor eax, eax
    ret

# vm_undo_keys(): u and ctrl+r: the change undone (redone) count times; the selections come back
# as they were, each a caret on a character
vm_undo_keys:
    PROLOGUE
    mov rbx, [rip + g_doc]
    mov r13d, [rip + v_count]
    test r13d, r13d
    jnz 1f
    mov r13d, 1
1:  xor eax, eax
    mov [rip + v_count], eax
    mov [rip + v_opcount], eax
    mov [rip + v_op], eax
    mov [rip + v_prefix], eax
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz 9f
    lea r12, [rip + doc_undo]
    cmp dword ptr [rip + vm_key], 'u'
    je 2f
    lea r12, [rip + doc_redo]
2:  mov rdi, rbx
    call r12
    test eax, eax
    jz 3f
    dec r13d
    jnz 2b
3:  lea rdi, [rip + vm_caret]
    call vm_each
9:  EPILOGUE

# vm_carets(): every selection becomes a caret on a character
FN vm_carets
    lea rdi, [rip + vm_caret]
    jmp vm_each

# vm_caret(): the cursor running now becomes a caret on a character
vm_caret:
    sub rsp, 8
    mov rax, [rip + g_doc]
    mov rdi, [rax + DOC_cur]
    call vclamp
    mov rcx, [rip + g_doc]
    mov [rcx + DOC_cur], rax
    mov [rcx + DOC_anchor], rax
    add rsp, 8
    ret

# vm_esc(): Esc in insert mode: every caret steps back (vesc_one), as one more part of the change
FN vm_esc
    PROLOGUE
    mov rbx, [rip + g_doc]
    mov r12, [rbx + DOC_undo + VEC_len]
    lea rdi, [rip + vesc_one]
    call vm_each
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    mov rsi, r12
    call doc_selections_record_after
    EPILOGUE

# vm_gb(): gb adds a cursor at the next occurrence of the word under the primary (in visual mode,
# of the selection), whole words of the same case for a word; it becomes the primary
FN vm_gb
    PROLOGUE 32
    mov rbx, [rip + g_doc]
    cmp dword ptr [rip + g_vim_mode], VM_VISUAL
    jae 1f
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call word_at
    mov dword ptr [rsp + 16], 1
    jmp 2f
1:  mov rdi, rbx
    call vim_sel
    mov dword ptr [rsp + 16], 0
2:  cmp rax, rdx
    je 9f
    mov [rsp + 24], rdx         # the search starts past it
    mov rdi, rbx
    mov rsi, rax
    call sel_text
    mov r12, rax
    mov r13, rdx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, [rsp + 24]
    mov r8d, [rsp + 16]
    call sel_find_next
    mov r14, rax
    mov rdi, r12
    call mem_free
    test r14, r14
    js 8f
    mov rsi, r14                # a caret at the word's start
    cmp dword ptr [rip + g_vim_mode], VM_VISUAL
    jb 3f
    mov rdi, rbx                # a selection whose cursor is on its last character
    lea rsi, [r14 + r13]
    call doc_prev_char
    mov rsi, rax
3:  mov rdi, rbx
    mov rdx, r14
    call sel_add
    mov qword ptr [rbx + DOC_prefx], -1
    call ed_touch
    jmp 9f
8:  lea rdi, [rip + .Lvm_none]
    call app_toast
9:  EPILOGUE

# vm_yank_piece(linewise) -> eax 1: vyank's text (v_buf) is the running cursor's piece
FN vm_yank_piece
    PROLOGUE
    mov r12d, edi
    mov rbx, [rip + vm_npieces]
    cmp rbx, VM_MAX
    jae 9f
    imul rbx, rbx, VP_SIZE
    lea rax, [rip + vm_pieces]
    add rbx, rax
    mov rax, [rip + vm_cur]
    mov [rbx + VP_index], rax
    mov rax, [rip + vm_text + SB_len]
    mov [rbx + VP_offset], rax
    mov rax, [rip + v_buf + SB_len]
    mov [rbx + VP_len], rax
    mov [rbx + VP_line], r12
    lea rdi, [rip + vm_text]
    mov rsi, [rip + v_buf + SB_ptr]
    mov rdx, [rip + v_buf + SB_len]
    call sb_push
    inc qword ptr [rip + vm_npieces]
9:  mov eax, 1
    EPILOGUE

# vm_clip_set(): the pieces, in the order of their cursors in the text and a newline between
# them, as one copy that knows them (editor_multi_copy's form)
vm_clip_set:
    PROLOGUE 48
    mov edi, ECM_SIZE
    call mem_alloc
    mov r15, rax
    mov rax, [rip + vm_npieces]
    mov [r15 + ECM_count], rax
    mov qword ptr [rsp], 0      # the copy
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], 1 # all linewise
    xor r12d, r12d              # pieces placed
    xor r13d, r13d              # rank
.Lvc_rank:
    cmp r12, [rip + vm_npieces]
    jae .Lvc_set
    cmp r13, VM_MAX
    jae .Lvc_set
    # the piece of the cursor with this rank, if it yanked
    xor r14d, r14d
1:  cmp r14, [rip + vm_npieces]
    jae 3f
    imul rbx, r14, VP_SIZE
    lea rax, [rip + vm_pieces]
    add rbx, rax
    mov rax, [rbx + VP_index]
    lea rcx, [rip + vm_rank]
    cmp [rcx + rax*8], r13
    je 2f
    inc r14
    jmp 1b
2:  test r12, r12
    jz 21f
    lea rdi, [rsp]
    mov esi, 10
    call sb_push_byte
21: mov rax, r12
    shl rax, 4
    lea rax, [r15 + rax + ECM_segments]
    mov rcx, [rsp + SB_len]
    mov [rax + ECS_offset], rcx
    mov rcx, [rbx + VP_len]
    mov [rax + ECS_len], rcx
    cmp qword ptr [rbx + VP_line], 0
    jne 22f
    mov qword ptr [rsp + 24], 0
22: lea rdi, [rsp]
    mov rsi, [rip + vm_text + SB_ptr]
    add rsi, [rbx + VP_offset]
    mov rdx, [rbx + VP_len]
    call sb_push
    inc r12
3:  inc r13
    jmp .Lvc_rank
.Lvc_set:
    mov [r15 + ECM_count], r12
    mov rax, [rsp + SB_len]
    mov [r15 + ECM_total], rax
    lea rdi, [rip + vm_text]
    call sb_free
    test r12, r12
    jz 8f
    mov rdi, [rsp + SB_ptr]
    mov rsi, [rsp + SB_len]
    mov rdx, [rsp + 24]
    mov rcx, r15
    call ed_clip_set_metadata
    test eax, eax
    jz 7f
    mov rdi, r15
    call editor_clip_segments_adopt
    jmp 9f
7:  call editor_clip_failure
8:  mov rdi, r15
    call mem_free
9:  lea rdi, [rsp]
    call sb_free
    EPILOGUE

# vm_put(text, length): p or P at every cursor: its own piece when the copy has one a cursor, else
# all of the text
FN vm_put
    PROLOGUE
    mov [rip + vm_ptr], rdi
    mov [rip + vm_len], rsi
    call editor_clip_segments_get
    mov [rip + vm_seg], rax
    mov rbx, [rip + g_doc]
    mov dword ptr [rip + vm_pairing], 0
    test rax, rax
    jz 1f
    mov r12, [rax + ECM_count]
    mov rdi, rbx
    call doc_selections_count
    cmp rax, r12
    jne 1f
    mov dword ptr [rip + vm_pairing], 1
1:  call vm_begin
    call vm_ranks
    mov dword ptr [rip + vm_piece], 1
    lea rdi, [rip + vm_put_one]
    call vm_each
    mov dword ptr [rip + vm_piece], 0
    call vm_end
    EPILOGUE

vm_put_one:
    sub rsp, 8
    mov rdi, [rip + vm_ptr]
    mov rsi, [rip + vm_len]
    cmp dword ptr [rip + vm_pairing], 0
    je 1f
    mov rax, [rip + vm_cur]
    lea rcx, [rip + vm_rank]
    mov rax, [rcx + rax*8]
    shl rax, 4
    add rax, [rip + vm_seg]
    add rdi, [rax + ECM_segments + ECS_offset]
    mov rsi, [rax + ECM_segments + ECS_len]
1:  call vput_text
    add rsp, 8
    ret

# vm_range(doc, cur, anchor) -> rax start, rdx end of a selection as vim draws it (vim_sel's rule)
FN vm_range
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, r13
    jbe 1f
    xchg r12, r13
1:  cmp dword ptr [rip + cfg_vim], 0
    je 9f
    cmp dword ptr [rip + g_vim_mode], VM_VISUAL
    jb 9f
    cmp dword ptr [rip + g_vim_mode], VM_VLINE
    je 2f
    mov rdi, rbx
    mov rsi, r13
    call doc_next_char
    mov r13, rax
    jmp 9f
2:  mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r12, rax
    mov rdi, rbx
    mov rsi, r13
    call doc_line_of
    lea rsi, [rax + 1]
    cmp rsi, [rbx + DOC_nlines]
    jae 3f
    mov rdi, rbx
    call doc_line_start
    mov r13, rax
    jmp 9f
3:  mov rdi, rbx
    call doc_len
    mov r13, rax
9:  mov rax, r12
    mov rdx, r13
    EPILOGUE

# vm_view(doc, visual): vim_view's rule for the other selections: in normal mode each is a caret on
# a character; a selection made another way becomes visual, its far end stepping back onto the
# last character selected (visual set)
FN vm_view
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rbx + DOC_selections]
    test r13, r13
    jz 9f
    mov r14, [r13 + DMS_count]
    add r13, DMS_DATA
1:  test r14, r14
    jz 9f
    mov rax, [r13 + DMP_cur]
    cmp rax, [r13 + DMP_anchor]
    jne 3f
    test r12d, r12d
    jnz 4f
    mov rdi, rax
    call vclamp
    mov [r13 + DMP_cur], rax
    mov [r13 + DMP_anchor], rax
    jmp 4f
3:  test r12d, r12d
    jz 4f
    lea r15, [r13 + DMP_cur]
    cmp rax, [r13 + DMP_anchor]
    ja 31f
    lea r15, [r13 + DMP_anchor]
31: mov rdi, rbx
    mov rsi, [r15]
    call doc_prev_char
    mov [r15], rax
4:  add r13, DMP_SIZE
    dec r14
    jmp 1b
9:  EPILOGUE

# vm_export(doc): vim_export's rule for the other selections: each becomes the editor's own as vim
# draws it (the character under its cursor included)
FN vm_export
    PROLOGUE
    mov rbx, rdi
    mov r13, [rbx + DOC_selections]
    test r13, r13
    jz 9f
    mov r14, [r13 + DMS_count]
    add r13, DMS_DATA
1:  test r14, r14
    jz 9f
    mov rdi, rbx
    mov rsi, [r13 + DMP_cur]
    mov rdx, [r13 + DMP_anchor]
    call vm_range
    mov rcx, [r13 + DMP_cur]
    cmp rcx, [r13 + DMP_anchor]
    jb 2f
    mov [r13 + DMP_anchor], rax
    mov [r13 + DMP_cur], rdx
    jmp 3f
2:  mov [r13 + DMP_anchor], rdx
    mov [r13 + DMP_cur], rax
3:  add r13, DMP_SIZE
    dec r14
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 2
# keys about one place: the primary alone does them (any mode, nothing pending)
vm_one_place:
    .long '/', '?', ':', 'n', 'N', '*', '#', 'J', 'r', '~', '>', '<', 'z', 'Z', 'm', '`', 0x27
    .long VK_HALFDN_KEY, VK_HALFUP_KEY, VK_PGUP_KEY, VK_PGDN_KEY, 0
# normal mode keys that act on every cursor by themselves, run once
vm_once:
    .long '.', 'p', 'P', 0
.Lvm_none: .asciz "No more matches"
