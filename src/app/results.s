# The Results panel tab (docs/extensions/v1.1.md, "navigation" and "hierarchy"): one set of results
# at a time, drawn as a tree (rtree.s) in a bottom panel tab (places.s): Find All References'
# locations grouped by file, or a call or type hierarchy whose rows ask their provider for their
# children when they are expanded. The last 8 sets are kept; the tab's title actions go back and
# forth through them, switch a hierarchy's direction and drop the shown set. F4 and shift+F4 open
# the next and previous location of the shown set from anywhere.
#
#   results_refs_begin(word cstr, serial) -> RST*: the set that query (serial) fills, emptied to be
#                                  filled again, or a new one
#   results_loc(RST*, path cstr, range ptr (4 dwords), preview ptr, len): one location
#   results_refs_end(RST*, busy): its rows from its locations; the tab shows it (focus: the first
#                                  time)
#   results_reply(ext, id, ok, body, len) -> eax 1 when it answered a hierarchy request (the pump)
#   results_part(ext, id, body, len) -> rax records taken, -1 broken, -2 not a hierarchy request
#   results_ext_gone(ext), results_dump(sb)
#   cmd_call_hierarchy, cmd_type_hierarchy, cmd_next_result, cmd_prev_result, cmd_focus_results
.include "rhun.inc"

.equ RS_HIST, 8                 # sets kept
.equ RS_BUDGET, 33554432        # their bytes together: older ones go first
.equ RH_ROOTS, 64               # hierarchy roots in one answer
.equ RH_KIDS, 1000              # children in one answer or part
.equ RH_SITES, 1000             # call sites of one call
.equ RH_DATA, 16384             # the bytes an item gives back
.equ RSK_REFS, 1
.equ RSK_CALLS, 2
.equ RSK_TYPES, 3
.equ ID_RS_BTN, 0x6c1000        # + n: the tab's title actions

# a set
STRUCT
F RST_kind, 4                   # RSK_*
F RST_mode, 4                   # a hierarchy's direction: 0 incoming calls, supertypes; 1 outgoing, subtypes
F RST_serial, 8                 # the references query that fills it, 0 when it is done
F RST_tree, 8
F RST_word, 8                   # owned cstr: what it is about (the word, the first root's name)
F RST_locs, VEC_SIZE            # RSL records (references)
F RST_hier, VEC_SIZE            # RSH records (hierarchies), the roots first
F RST_nroots, 8
F RST_bytes, SB_SIZE            # their strings
F RST_cur, 8                    # F4's location, -1 before the first
F RST_busy, 4                   # providers are still searching
F RST_shown, 4                  # the tab showed it once (it takes the keyboard only then)
F RST_find, 4                   # Find in Files' results (their title)
F RST_pad, 4
ENDSTRUCT RST_SIZE

# a location
STRUCT
F RSL_path, 8                   # offsets in RST_bytes, cstrs
F RSL_prev, 8
F RSL_l1, 4
F RSL_c1, 4
F RSL_l2, 4
F RSL_c2, 4
F RSL_node, 4                   # its row's node
F RSL_pad, 4
ENDSTRUCT RSL_SIZE

# a hierarchy item
STRUCT
F RSH_ext, 8                    # its provider
F RSH_path, 8                   # offsets in RST_bytes, cstrs
F RSH_name, 8
F RSH_detail, 8
F RSH_data, 8                   # the bytes its provider gets back: offset, length
F RSH_dlen, 8
F RSH_sites, 8                  # its call sites (4 dwords each): offset, count
F RSH_nsites, 4
F RSH_parent, 4                 # RSH index, -1 for a root
F RSH_l1, 4                     # its name's range
F RSH_c1, 4
F RSH_l2, 4
F RSH_c2, 4
F RSH_node, 4
F RSH_got, 4                    # children given so far (parts)
F RSH_req, 8                    # the request asking for its children, 0 for none
ENDSTRUCT RSH_SIZE

.data
.p2align 2
tab_id: .long -1                # the Results tab's place, -1 before it is made

.bss
.p2align 3
hist: .zero 8 * RS_HIST         # RST*, the oldest first
nhist: .quad 0
cur: .quad 0                    # the shown set's index
rh_ext: .quad 0                 # a hierarchy's roots asked for: the provider, id, kind, document
rh_id: .quad 0
rh_kind: .quad 0
rh_doc: .quad 0
keep_focus: .long 0             # Space opens a location without leaving the tab
rs_pad: .long 0
lbuf: .zero SB_SIZE             # an id, a label, a request line
dbuf: .zero SB_SIZE             # a row's description
tmp4: .zero 16                  # four numbers

.text
.globl lf_pos_near

# ---------------- sets ----------------

# cur_set() -> rax the shown set, or 0
cur_set:
    xor eax, eax
    cmp qword ptr [rip + nhist], 0
    je 1f
    mov rax, [rip + cur]
    lea rcx, [rip + hist]
    mov rax, [rcx + rax*8]
1:  ret

# set_bytes(RST*) -> rax what it holds, roughly
set_bytes:
    mov rax, [rdi + RST_bytes + SB_len]
    mov rcx, [rdi + RST_locs + VEC_len]
    imul rcx, rcx, RSL_SIZE + 64      # with its tree rows
    add rax, rcx
    mov rcx, [rdi + RST_hier + VEC_len]
    imul rcx, rcx, RSH_SIZE + 64
    add rax, rcx
    ret

# set_free(RST*): its requests withdrawn, everything it holds freed
set_free:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + RST_hier + VEC_len]
    jae 2f
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    inc r12
    mov rsi, [r13 + RSH_req]
    test rsi, rsi
    jz 1b
    mov rdi, [r13 + RSH_ext]
    call query_withdraw
    jmp 1b
2:  mov rdi, [rbx + RST_tree]
    call tree_free
    lea rdi, [rbx + RST_locs]
    call vec_free
    lea rdi, [rbx + RST_hier]
    call vec_free
    lea rdi, [rbx + RST_bytes]
    call sb_free
    mov rdi, [rbx + RST_word]
    call mem_free
    mov rdi, rbx
    call mem_free
    EPILOGUE

# drop_at(i): set i goes; the shown one stays shown when it can
drop_at:
    PROLOGUE
    mov rbx, rdi
    lea rax, [rip + hist]
    mov rdi, [rax + rbx*8]
    call set_free
    lea rax, [rip + hist]
    mov rcx, rbx
1:  lea rdx, [rcx + 1]
    cmp rdx, [rip + nhist]
    jae 2f
    mov r8, [rax + rdx*8]
    mov [rax + rcx*8], r8
    mov rcx, rdx
    jmp 1b
2:  dec qword ptr [rip + nhist]
    mov rax, [rip + cur]        # the shown one keeps its place, or the one before it shows
    cmp rax, rbx
    ja 31f
    cmp rax, [rip + nhist]
    jb 3f
31: test rax, rax
    jz 3f
    dec qword ptr [rip + cur]
3:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# set_new(kind) -> rax a new set, shown; the oldest go past 8 sets or the byte budget
set_new:
    PROLOGUE
    mov ebx, edi
0:  cmp qword ptr [rip + nhist], RS_HIST
    jb 1f
    xor edi, edi
    call drop_at
    jmp 0b
1:  # the byte budget
    xor r13d, r13d              # bytes of the kept sets
    xor r12d, r12d
2:  cmp r12, [rip + nhist]
    jae 3f
    lea rax, [rip + hist]
    mov rdi, [rax + r12*8]
    call set_bytes
    add r13, rax
    inc r12
    jmp 2b
3:  cmp r13, RS_BUDGET
    jbe 4f
    cmp qword ptr [rip + nhist], 0
    je 4f
    xor edi, edi
    call drop_at
    jmp 1b
4:  mov edi, RST_SIZE
    call mem_alloc
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    mov edx, RST_SIZE
    call memset
    mov [r12 + RST_kind], ebx
    mov qword ptr [r12 + RST_cur], -1
    lea rdi, [rip + tree_ops]
    mov rsi, r12
    call tree_new
    mov [r12 + RST_tree], rax
    mov rax, [rip + nhist]
    lea rcx, [rip + hist]
    mov [rcx + rax*8], r12
    mov [rip + cur], rax
    inc qword ptr [rip + nhist]
    mov dword ptr [rip + g_dirty], 1
    mov rax, r12
    EPILOGUE

# set_str(RST*, ptr, len) -> rax the offset of a copy in its bytes, as a cstr
set_str:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + RST_bytes + SB_len]
    lea rdi, [rbx + RST_bytes]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rbx + RST_bytes]
    xor esi, esi
    call sb_push_byte
    mov rax, r14
    EPILOGUE

# set_word(RST*, cstr): what the set is about
set_word:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + RST_word]
    call mem_free
    mov rdi, r12
    call dup_cstr
    mov [rbx + RST_word], rax
    EPILOGUE

# tab_ensure(): the tab, made once
tab_ensure:
    PROLOGUE
    cmp dword ptr [rip + tab_id], 0
    jge 9f
    mov edi, PLACE_PANEL
    lea rsi, [rip + .Ltab_name]
    lea rdx, [rip + .Ltab_title]
    lea rcx, [rip + tab_place_ops]
    xor r8d, r8d
    call place_add
    mov [rip + tab_id], eax
    test eax, eax
    js 9f
    mov edi, eax
    mov esi, -1
    call place_set_icon
9:  EPILOGUE

# show_set(RST*): the tab shows it; the first time it takes the keyboard
show_set:
    PROLOGUE
    mov rbx, rdi
    call tab_ensure
    mov edi, [rip + tab_id]
    test edi, edi
    js 9f
    xor esi, esi
    cmp dword ptr [rbx + RST_shown], 0
    jne 1f
    mov dword ptr [rbx + RST_shown], 1
    mov esi, 1
1:  call place_show
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- references ----------------

# FN results_refs_begin(word, serial) -> rax the set the query fills
FN results_refs_begin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call cur_set
    test rax, rax
    jz 1f
    test r12, r12
    jz 1f
    cmp [rax + RST_serial], r12
    jne 1f
    cmp dword ptr [rax + RST_kind], RSK_REFS
    jne 1f
    mov r13, rax                # filled again (a part came): the rows keep their state
    mov qword ptr [r13 + RST_locs + VEC_len], 0
    lea rdi, [r13 + RST_bytes]
    call sb_clear
    mov rax, r13
    EPILOGUE
1:  mov edi, RSK_REFS
    call set_new
    mov r13, rax
    mov [r13 + RST_serial], r12
    mov rdi, r13
    mov rsi, rbx
    call set_word
    mov rax, r13
    EPILOGUE

# FN results_find_begin(query cstr) -> rax a new set of Find in Files' results (palette.s fills it as
# references, results_loc then results_refs_end)
FN results_find_begin
    PROLOGUE
    mov rbx, rdi
    mov edi, RSK_REFS
    call set_new
    mov r12, rax
    mov dword ptr [r12 + RST_find], 1
    mov rdi, r12
    mov rsi, rbx
    call set_word
    mov rax, r12
    EPILOGUE

# FN results_loc(RST*, path cstr, range ptr, preview ptr, len): one location (the same path as the
# location before shares its copy)
FN results_loc
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rax, [rbx + RST_locs + VEC_len]
    test rax, rax
    jz 1f
    dec rax
    imul rax, rax, RSL_SIZE
    add rax, [rbx + RST_locs + VEC_ptr]
    mov rdi, [rax + RSL_path]
    mov [rsp], rdi
    add rdi, [rbx + RST_bytes + SB_ptr]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 2f
1:  mov rdi, r12
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call set_str
    mov [rsp], rax
2:  mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call set_str
    mov [rsp + 8], rax
    lea rdi, [rbx + RST_locs]
    mov esi, RSL_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + RSL_path], rcx
    mov rcx, [rsp + 8]
    mov [rax + RSL_prev], rcx
    mov ecx, [r13]
    mov [rax + RSL_l1], ecx
    mov ecx, [r13 + 4]
    mov [rax + RSL_c1], ecx
    mov ecx, [r13 + 8]
    mov [rax + RSL_l2], ecx
    mov ecx, [r13 + 12]
    mov [rax + RSL_c2], ecx
    mov dword ptr [rax + RSL_node], -1
    EPILOGUE

# FN results_refs_end(RST*, busy): the rows: a file row per path (its name, its folder, the count),
# its locations under it ("LINE:COL  preview")
FN results_refs_end
    PROLOGUE 32
    mov rbx, rdi
    mov [rbx + RST_busy], esi
    test esi, esi
    jnz 1f
    mov qword ptr [rbx + RST_serial], 0
1:  mov r12, [rbx + RST_tree]
    # the file rows
    mov rdi, r12
    xor esi, esi
    call tree_kids_begin
    xor r13d, r13d
2:  cmp r13, [rbx + RST_locs + VEC_len]
    jae 3f
    mov rdi, rbx
    mov rsi, r13
    call group_end
    mov [rsp], rax              # past the group
    mov rdi, rbx
    mov rsi, r13
    call file_row
    mov r13, [rsp]
    jmp 2b
3:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
    # the locations under each
    xor r13d, r13d
4:  cmp r13, [rbx + RST_locs + VEC_len]
    jae 9f
    mov rdi, rbx
    mov rsi, r13
    call group_end
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r13
    call file_id
    mov rdi, r12
    mov rsi, [rip + lbuf + SB_ptr]
    mov rdx, [rip + lbuf + SB_len]
    call tree_find
    test eax, eax
    js 8f
    mov rdi, r12
    mov esi, eax
    call tree_kids_begin
5:  cmp r13, [rsp]
    jae 6f
    mov rdi, rbx
    mov rsi, r13
    call loc_row
    inc r13
    jmp 5b
6:  mov rdi, r12
    xor esi, esi
    call tree_kids_end
8:  mov r13, [rsp]
    jmp 4b
9:  mov rdi, rbx
    call show_set
    EPILOGUE

# group_end(RST*, i) -> rax the first location after i with another path
group_end:
    mov rax, rsi
    imul rcx, rsi, RSL_SIZE
    add rcx, [rdi + RST_locs + VEC_ptr]
    mov rdx, [rcx + RSL_path]
1:  inc rax
    cmp rax, [rdi + RST_locs + VEC_len]
    jae 2f
    add rcx, RSL_SIZE
    cmp [rcx + RSL_path], rdx
    je 1b
2:  ret

# file_id(RST*, i): lbuf = "f" and location i's path
file_id:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + lbuf]
    call sb_clear
    lea rdi, [rip + lbuf]
    mov esi, 'f'
    call sb_push_byte
    imul rax, r12, RSL_SIZE
    add rax, [rbx + RST_locs + VEC_ptr]
    mov rsi, [rax + RSL_path]
    add rsi, [rbx + RST_bytes + SB_ptr]
    lea rdi, [rip + lbuf]
    call sb_push_cstr
    EPILOGUE

# file_row(RST*, i): the row of location i's file: its name, its folder, how many
file_row:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    call group_end
    sub rax, r12
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    call file_id
    imul rax, r12, RSL_SIZE
    add rax, [rbx + RST_locs + VEC_ptr]
    mov r13, [rax + RSL_path]
    add r13, [rbx + RST_bytes + SB_ptr]
    mov rdi, r13
    call name_of
    mov r14, rax                # the name
    mov rdi, rax
    call strlen
    mov r8, rax
    mov rdi, [rbx + RST_tree]
    mov rsi, [rip + lbuf + SB_ptr]
    mov rdx, [rip + lbuf + SB_len]
    mov rcx, r14
    mov r9d, KIDS_OPEN
    call tree_kid
    test eax, eax
    js 9f
    mov r15d, eax
    mov rdi, [rbx + RST_tree]
    mov esi, r15d
    mov edx, [rsp]
    call tree_set_badge
    mov rdi, [rbx + RST_tree]
    mov esi, r15d
    mov edx, IC_FILE
    mov ecx, -1
    call tree_set_icon
    mov rdi, r13
    mov rsi, r14
    call folder_desc
    mov rdi, [rbx + RST_tree]
    mov esi, r15d
    mov rdx, [rip + dbuf + SB_ptr]
    mov rcx, [rip + dbuf + SB_len]
    call tree_set_desc
9:  EPILOGUE

# loc_row(RST*, i): location i's row "LINE:COL  preview", its value i + 1
loc_row:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    imul r13, r12, RSL_SIZE
    add r13, [rbx + RST_locs + VEC_ptr]
    # the id: the path, then the range (a location given twice gets one row)
    lea rdi, [rip + dbuf]
    call sb_clear
    mov rsi, [r13 + RSL_path]
    add rsi, [rbx + RST_bytes + SB_ptr]
    lea rdi, [rip + dbuf]
    call sb_push_cstr
    lea rdi, [rip + dbuf]
    mov esi, 1
    call sb_push_byte
    mov rdi, r13
    lea rsi, [rip + dbuf]
    call push_range
    # the label
    lea rdi, [rip + lbuf]
    call sb_clear
    lea rdi, [rip + lbuf]
    mov esi, [r13 + RSL_l1]
    call sb_push_u64
    lea rdi, [rip + lbuf]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + lbuf]
    mov esi, [r13 + RSL_c1]
    call sb_push_u64
    lea rdi, [rip + lbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lbuf]
    mov esi, ' '
    call sb_push_byte
    mov rsi, [r13 + RSL_prev]
    add rsi, [rbx + RST_bytes + SB_ptr]
    lea rdi, [rip + lbuf]
    call push_line
    mov rdi, [rbx + RST_tree]
    mov rsi, [rip + dbuf + SB_ptr]
    mov rdx, [rip + dbuf + SB_len]
    mov rcx, [rip + lbuf + SB_ptr]
    mov r8, [rip + lbuf + SB_len]
    mov r9d, KIDS_LEAF
    call tree_kid
    test eax, eax
    js 9f
    imul r13, r12, RSL_SIZE
    add r13, [rbx + RST_locs + VEC_ptr]
    mov [r13 + RSL_node], eax
    mov rdi, [rbx + RST_tree]
    mov esi, eax
    lea rdx, [r12 + 1]
    call tree_set_user
9:  EPILOGUE

# push_range(rec with L1 C1 L2 C2 at RSL_l1, sb): "L1:C1-L2:C2"
push_range:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov esi, [rbx + RSL_l1]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + RSL_c1]
    call sb_push_u64
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + RSL_l2]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [rbx + RSL_c2]
    call sb_push_u64
    EPILOGUE

# push_line(sb, cstr): its text, line breaks and tabs as spaces, at most 200 bytes
push_line:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  movzx esi, byte ptr [r12 + r13]
    test esi, esi
    jz 9f
    cmp r13, 200
    jae 9f
    cmp esi, ' '
    jae 2f
    mov esi, ' '
2:  mov rdi, rbx
    call sb_push_byte
    inc r13
    jmp 1b
9:  EPILOGUE

# name_of(path cstr) -> rax its last part ("#ID" stays whole)
name_of:
    mov rax, rdi
    mov rcx, rdi
1:  movzx edx, byte ptr [rcx]
    test edx, edx
    jz 9f
    inc rcx
    cmp edx, '/'
    je 2f
    cmp edx, '\\'
    jne 1b
2:  mov rax, rcx
    jmp 1b
9:  ret

# folder_desc(path cstr, its name in it): dbuf = the folder, relative to the project inside it
folder_desc:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + dbuf]
    call sb_clear
    mov r13, r12
    sub r13, rbx                # the folder's length with its separator
    jz 9f
    dec r13
    mov r14, rbx
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 5f
    call strlen
    mov r15, rax
    cmp r15, r13
    ja 5f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [rip + g_project]
    mov rcx, r15
    call str_starts
    test eax, eax
    jz 5f
    cmp r15, r13
    je 9f                       # the project's own folder: nothing
    movzx eax, byte ptr [rbx + r15]
    cmp eax, '/'
    je 4f
    cmp eax, '\\'
    jne 5f
4:  lea r14, [rbx + r15 + 1]
    mov r13, r12
    sub r13, r14
    dec r13
5:  lea rdi, [rip + dbuf]
    mov rsi, r14
    mov rdx, r13
    call sb_push
9:  EPILOGUE

# ---------------- opening a result ----------------

# goto_range(path cstr, range ptr (4 dwords)) -> eax 1 when its file is open in the editor with the
# range selected (the keyboard goes to the editor unless keep_focus)
goto_range:
    PROLOGUE
    mov r13, rsi
    call lf_open_path
    test rax, rax
    jz 8f
    mov r12, rax
    mov rdi, r12
    mov esi, [r13]
    mov edx, [r13 + 4]
    call lf_pos_near
    mov r14, rax
    mov rdi, r12
    mov esi, [r13 + 8]
    mov edx, [r13 + 12]
    call lf_pos_near
    cmp rax, r14
    jae 1f
    mov rax, r14
1:  mov [r12 + DOC_anchor], r14
    mov [r12 + DOC_cur], rax
    call ed_touch
    cmp dword ptr [rip + keep_focus], 0
    jne 2f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
2:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# goto_loc(RST*, i): location i, its row the tree's cursor
goto_loc:
    PROLOGUE
    mov rbx, rdi
    mov [rbx + RST_cur], rsi
    imul r12, rsi, RSL_SIZE
    add r12, [rbx + RST_locs + VEC_ptr]
    mov esi, [r12 + RSL_node]
    test esi, esi
    js 1f
    mov rdi, [rbx + RST_tree]
    call tree_set_cursor
    mov rdi, [rbx + RST_tree]
    mov esi, [r12 + RSL_node]
    call tree_reveal
1:  mov rdi, [r12 + RSL_path]
    add rdi, [rbx + RST_bytes + SB_ptr]
    lea rsi, [r12 + RSL_l1]
    call goto_range
    EPILOGUE

# goto_hier(RST*, i): item i: a call's first call site (in the caller's file for incoming calls, in
# the asked item's file for outgoing ones), else its name
goto_hier:
    PROLOGUE
    mov rbx, rdi
    imul r12, rsi, RSH_SIZE
    add r12, [rbx + RST_hier + VEC_ptr]
    mov rdi, [r12 + RSH_path]
    lea rsi, [r12 + RSH_l1]
    cmp dword ptr [r12 + RSH_nsites], 0
    je 2f
    mov rsi, [r12 + RSH_sites]
    add rsi, [rbx + RST_bytes + SB_ptr]
    cmp dword ptr [rbx + RST_mode], 0
    je 2f
    movsxd rax, dword ptr [r12 + RSH_parent]
    test rax, rax
    js 2f
    imul rax, rax, RSH_SIZE
    add rax, [rbx + RST_hier + VEC_ptr]
    mov rdi, [rax + RSH_path]
2:  add rdi, [rbx + RST_bytes + SB_ptr]
    call goto_range
    EPILOGUE

# tree_activate_cb(set, tr, node): Enter, a double click or a click on a leaf
tree_activate_cb:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov esi, edx
    call tree_user
    test rax, rax
    jz 9f
    lea rsi, [rax - 1]
    mov rdi, rbx
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    jne 1f
    call goto_loc
    jmp 9f
1:  call goto_hier
9:  EPILOGUE

# FN cmd_next_result(), cmd_prev_result(): F4, shift+F4: the shown set's next or previous location
FN cmd_next_result
    mov esi, 1
    jmp step_result
FN cmd_prev_result
    mov esi, -1
step_result:
    PROLOGUE
    mov r13d, esi
    call cur_set
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    jne 9f
    mov r12, [rbx + RST_locs + VEC_len]
    test r12, r12
    jz 9f
    mov rax, [rbx + RST_cur]
    test rax, rax
    jns 2f
    xor eax, eax                # before the first: F4 the first, shift+F4 the last
    test r13d, r13d
    jns 3f
    lea rax, [r12 - 1]
    jmp 3f
2:  movsxd rcx, r13d
    add rax, rcx
    add rax, r12
    xor edx, edx
    div r12
    mov rax, rdx
3:  mov rdi, rbx
    mov rsi, rax
    call goto_loc
9:  EPILOGUE

# FN cmd_focus_results(): the Results tab with the keyboard
FN cmd_focus_results
    PROLOGUE
    call tab_ensure
    mov edi, [rip + tab_id]
    test edi, edi
    js 9f
    mov esi, 1
    call place_show
9:  EPILOGUE

# ---------------- hierarchies ----------------

# FN cmd_call_hierarchy(), cmd_type_hierarchy(): the roots at the cursor, asked of the first running
# provider whose patterns match the document
FN cmd_call_hierarchy
    mov edi, RSK_CALLS
    jmp hier_start
FN cmd_type_hierarchy
    mov edi, RSK_TYPES
hier_start:
    PROLOGUE 16
    mov [rsp], edi
    call ed_single
    call lf_active_doc          # the editor's document, also from the Results tab
    test rax, rax
    jz 9f
    mov rbx, rax
    # the roots asked before are not wanted any more
    mov rsi, [rip + rh_id]
    test rsi, rsi
    jz 1f
    mov rdi, [rip + rh_ext]
    call query_withdraw
    mov qword ptr [rip + rh_id], 0
1:  xor r12d, r12d
2:  cmp r12, [rip + g_exts + VEC_len]
    jae 7f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, r13
    call ext_is_visible
    test eax, eax
    jz 2b
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 2b
    mov rdi, r13
    mov esi, FEAT_HIERARCHY
    call ext_feature
    test eax, eax
    jz 2b
    mov esi, EXT_pv_call_hierarchy
    cmp dword ptr [rsp], RSK_CALLS
    je 3f
    mov esi, EXT_pv_type_hierarchy
3:  mov rdi, r13
    call ext_pv
    mov rdi, rax
    mov rsi, rbx
    call extproto_matches
    test eax, eax
    jz 2b
    # "call-hierarchy DOC VERSION LINE COL invoked -"
    lea rdi, [rip + lbuf]
    call sb_clear
    lea rsi, [rip + .Lv_callh]
    cmp dword ptr [rsp], RSK_CALLS
    je 4f
    lea rsi, [rip + .Lv_typeh]
4:  lea rdi, [rip + lbuf]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + lbuf]
    call push_doc_pos
    lea rdi, [rip + lbuf]
    lea rsi, [rip + .Linvoked]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, rbx
    mov rdx, [rip + lbuf + SB_ptr]
    mov rcx, [rip + lbuf + SB_len]
    call extproto_host_send
    test rax, rax
    jz 2b
    mov [rip + rh_id], rax
    mov [rip + rh_ext], r13
    mov ecx, [rsp]
    mov [rip + rh_kind], rcx
    mov rcx, [rbx + DOC_id]
    mov [rip + rh_doc], rcx
    mov rdi, r13
    mov rsi, rax
    mov edx, PK_CALLH
    cmp dword ptr [rsp], RSK_CALLS
    je 5f
    mov edx, PK_TYPEH
5:  mov ecx, QO_LANGFEAT
    call query_track
    jmp 9f
7:  lea rdi, [rip + .Lno_callh]
    cmp dword ptr [rsp], RSK_CALLS
    je 8f
    lea rdi, [rip + .Lno_typeh]
8:  call app_toast
9:  EPILOGUE

# push_doc_pos(doc, sb): " DOC VERSION LINE COL" of the cursor
push_doc_pos:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + DOC_id]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + DOC_version]
    call sb_push_u64
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call lf_line_col
    mov r13, rdx
    mov r14, rax
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, r14
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, r13
    call sb_push_u64
    EPILOGUE

# parse_items(RST*, ext, body, len, parent index or -1, calls, max) -> rax the items appended to the
# set's RSH records (their rows are made by the caller), -1 when the body breaks the rules (nothing
# appended). "N", then N items (or calls: one more number R and R call-site lines after the bytes)
parse_items:
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], rsi              # ext
    mov [rsp + 8], r8           # parent
    mov [rsp + 16], r9          # calls
    mov rax, [rbx + RST_hier + VEC_len]
    mov [rsp + 24], rax         # to roll back to
    mov rax, [rbx + RST_bytes + SB_len]
    mov [rsp + 32], rax
    mov rdi, rdx
    mov rsi, rcx
    mov edx, [rbp + 16]         # max
    call lf_head
    test rax, rax
    js .Lpi_bad
    mov r15, rax
.Lpi_next:
    test r15, r15
    jz .Lpi_end
    dec r15
    call ps_line
    test eax, eax
    jz .Lpi_bad
    call ps_word                # KIND: a word (not kept)
    test rdx, rdx
    jz .Lpi_bad
    cmp rdx, 40
    ja .Lpi_bad
    call lf_four                # the whole symbol (not kept)
    test eax, eax
    jz .Lpi_bad
    call lf_four                # its name
    test eax, eax
    jz .Lpi_bad
    lea rax, [rip + lf_tmp4]
    mov rcx, [rax]
    mov [rip + tmp4], rcx
    mov rcx, [rax + 8]
    mov [rip + tmp4 + 8], rcx
    call ps_num                 # PATH_LEN
    test edx, edx
    jz .Lpi_bad
    test rax, rax
    jz .Lpi_bad
    cmp rax, 4096
    ja .Lpi_bad
    mov [rsp + 40], rax
    call ps_num                 # NAME_LEN
    test edx, edx
    jz .Lpi_bad
    test rax, rax
    jz .Lpi_bad
    cmp rax, 1000
    ja .Lpi_bad
    mov [rsp + 48], rax
    call ps_num                 # DETAIL_LEN
    test edx, edx
    jz .Lpi_bad
    cmp rax, 1000
    ja .Lpi_bad
    mov [rsp + 56], rax
    call ps_num                 # DATA_LEN
    test edx, edx
    jz .Lpi_bad
    cmp rax, RH_DATA
    ja .Lpi_bad
    mov r14, rax
    xor r13d, r13d              # R
    cmp qword ptr [rsp + 16], 0
    je 1f
    call ps_num
    test edx, edx
    jz .Lpi_bad
    test rax, rax
    jz .Lpi_bad
    cmp rax, RH_SITES
    ja .Lpi_bad
    mov r13, rax
1:  call ps_eol
    test eax, eax
    jz .Lpi_bad
    # the record, its strings copied as they are read
    lea rdi, [rbx + RST_hier]
    mov esi, RSH_SIZE
    call vec_push
    mov r12, [rbx + RST_hier + VEC_len]
    dec r12                     # its index (the vector may move: found again by index)
    mov rcx, [rsp]
    mov [rax + RSH_ext], rcx
    mov rcx, [rsp + 8]
    mov [rax + RSH_parent], ecx
    mov dword ptr [rax + RSH_node], -1
    mov dword ptr [rax + RSH_got], 0
    mov qword ptr [rax + RSH_req], 0
    mov [rax + RSH_nsites], r13d
    mov ecx, [rip + tmp4]
    mov [rax + RSH_l1], ecx
    mov ecx, [rip + tmp4 + 4]
    mov [rax + RSH_c1], ecx
    mov ecx, [rip + tmp4 + 8]
    mov [rax + RSH_l2], ecx
    mov ecx, [rip + tmp4 + 12]
    mov [rax + RSH_c2], ecx
    # PATH
    mov rdi, [rsp + 40]
    call lf_take
    test rax, rax
    jz .Lpi_bad
    mov rdi, rax
    mov rsi, [rsp + 40]
    push rdi
    push rsi
    call lf_path_ok
    pop rdx
    pop rsi
    test eax, eax
    jz .Lpi_bad
    mov rdi, rbx
    call set_str
    imul rcx, r12, RSH_SIZE
    add rcx, [rbx + RST_hier + VEC_ptr]
    mov [rcx + RSH_path], rax
    # NAME, DETAIL: one line each
    mov rdi, [rsp + 48]
    call take_line
    test rax, rax
    js .Lpi_bad
    imul rcx, r12, RSH_SIZE
    add rcx, [rbx + RST_hier + VEC_ptr]
    mov [rcx + RSH_name], rax
    mov rdi, [rsp + 56]
    call take_line
    test rax, rax
    js .Lpi_bad
    imul rcx, r12, RSH_SIZE
    add rcx, [rbx + RST_hier + VEC_ptr]
    mov [rcx + RSH_detail], rax
    # DATA, kept as given
    mov rdi, r14
    call lf_take
    test rax, rax
    jz .Lpi_bad
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r14
    call set_str
    imul rcx, r12, RSH_SIZE
    add rcx, [rbx + RST_hier + VEC_ptr]
    mov [rcx + RSH_data], rax
    mov [rcx + RSH_dlen], r14
    # the call sites: R lines "L1 C1 L2 C2", kept as dwords
    test r13, r13
    jz .Lpi_next
    mov rax, [rbx + RST_bytes + SB_len]
    imul rcx, r12, RSH_SIZE
    add rcx, [rbx + RST_hier + VEC_ptr]
    mov [rcx + RSH_sites], rax
2:  test r13, r13
    jz .Lpi_next
    dec r13
    call ps_line
    test eax, eax
    jz .Lpi_bad
    call lf_four
    test eax, eax
    jz .Lpi_bad
    call ps_eol
    test eax, eax
    jz .Lpi_bad
    lea rdi, [rbx + RST_bytes]
    lea rsi, [rip + lf_tmp4]
    mov edx, 16
    call sb_push
    jmp 2b
.Lpi_end:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne .Lpi_bad
    mov rax, [rbx + RST_hier + VEC_len]
    sub rax, [rsp + 24]
    EPILOGUE
.Lpi_bad:
    mov rax, [rsp + 24]
    mov [rbx + RST_hier + VEC_len], rax
    mov rax, [rsp + 32]
    mov [rbx + RST_bytes + SB_len], rax
    mov rax, -1
    EPILOGUE

# take_line(n) -> rax the offset of a copy of the next n bytes in the set (rbx) as a cstr, -1 when
# they are not there or hold a line break
take_line:
    PROLOGUE
    mov r12, rdi
    call lf_take
    test rax, rax
    jz 8f
    mov r13, rax
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    movzx eax, byte ptr [r13 + rcx]
    cmp eax, 10
    je 8f
    cmp eax, 13
    je 8f
    test eax, eax
    jz 8f
    inc rcx
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    call set_str
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# hier_rows(RST*, from): rows for the set's items from index `from` on (all of one parent), under
# their parent's row (or the root); a parent that already had children gets them appended
hier_rows:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    cmp r12, [rbx + RST_hier + VEC_len]
    jae 9f
    imul rax, r12, RSH_SIZE
    add rax, [rbx + RST_hier + VEC_ptr]
    movsxd r13, dword ptr [rax + RSH_parent]
    xor esi, esi                # the parent's node: the root for roots
    mov dword ptr [rsp], 0      # 1: appended
    test r13, r13
    js 1f
    imul rax, r13, RSH_SIZE
    add rax, [rbx + RST_hier + VEC_ptr]
    mov esi, [rax + RSH_node]
    cmp dword ptr [rax + RSH_got], 0
    je 1f
    mov dword ptr [rsp], 1
    mov rdi, [rbx + RST_tree]
    call tree_add_begin
    jmp 2f
1:  mov rdi, [rbx + RST_tree]
    call tree_kids_begin
2:  cmp r12, [rbx + RST_hier + VEC_len]
    jae 3f
    mov rdi, rbx
    mov rsi, r12
    call hier_row
    inc r12
    jmp 2b
3:  mov rdi, [rbx + RST_tree]
    xor esi, esi
    cmp dword ptr [rsp], 0
    jne 4f
    call tree_kids_end
    jmp 5f
4:  call tree_add_end
5:  test r13, r13
    js 9f
    imul rax, r13, RSH_SIZE
    add rax, [rbx + RST_hier + VEC_ptr]
    mov dword ptr [rax + RSH_got], 1
9:  EPILOGUE

# hier_row(RST*, i): item i's row: its name; "detail  file:line" and "(N calls)" after it
hier_row:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    lea rdi, [rip + lbuf]
    call sb_clear
    lea rdi, [rip + lbuf]
    mov esi, 'h'
    call sb_push_byte
    lea rdi, [rip + lbuf]
    mov rsi, r12
    call sb_push_u64
    # the description
    lea rdi, [rip + dbuf]
    call sb_clear
    mov rsi, [r13 + RSH_detail]
    add rsi, [rbx + RST_bytes + SB_ptr]
    cmp byte ptr [rsi], 0
    je 1f
    lea rdi, [rip + dbuf]
    call sb_push_cstr
    lea rdi, [rip + dbuf]
    lea rsi, [rip + .Lgap]
    call sb_push_cstr
1:  mov rdi, [r13 + RSH_path]
    add rdi, [rbx + RST_bytes + SB_ptr]
    call name_of
    lea rdi, [rip + dbuf]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + dbuf]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + dbuf]
    mov esi, [r13 + RSH_l1]
    call sb_push_u64
    cmp dword ptr [r13 + RSH_nsites], 1
    jbe 2f
    lea rdi, [rip + dbuf]
    lea rsi, [rip + .Lcalls_open]
    call sb_push_cstr
    lea rdi, [rip + dbuf]
    mov esi, [r13 + RSH_nsites]
    call sb_push_u64
    lea rdi, [rip + dbuf]
    lea rsi, [rip + .Lcalls_close]
    call sb_push_cstr
2:  mov rcx, [r13 + RSH_name]
    add rcx, [rbx + RST_bytes + SB_ptr]
    mov r14, rcx
    mov rdi, rcx
    call strlen
    mov r8, rax
    mov rdi, [rbx + RST_tree]
    mov rsi, [rip + lbuf + SB_ptr]
    mov rdx, [rip + lbuf + SB_len]
    mov rcx, r14
    mov r9d, KIDS_CLOSED
    call tree_kid
    test eax, eax
    js 9f
    mov r14d, eax
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    mov [r13 + RSH_node], eax
    mov rdi, [rbx + RST_tree]
    mov esi, r14d
    lea rdx, [r12 + 1]
    call tree_set_user
    mov rdi, [rbx + RST_tree]
    mov esi, r14d
    mov rdx, [rip + dbuf + SB_ptr]
    mov rcx, [rip + dbuf + SB_len]
    call tree_set_desc
9:  EPILOGUE

# hier_ask(RST*, i): item i's children: calls-in, calls-out, supertypes or subtypes with its DATA
hier_ask:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    cmp qword ptr [r13 + RSH_req], 0
    jne 9f
    mov r14, [r13 + RSH_ext]
    cmp dword ptr [r14 + EXT_status], ES_RUNNING
    jne 8f
    lea rdi, [rip + lbuf]
    call sb_clear
    mov eax, [rbx + RST_mode]
    cmp dword ptr [rbx + RST_kind], RSK_TYPES
    jne 1f
    add eax, 2
1:  lea rcx, [rip + hier_verbs]
    mov rsi, [rcx + rax*8]
    lea rdi, [rip + lbuf]
    call sb_push_cstr
    lea rdi, [rip + lbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lbuf]
    mov rsi, [r13 + RSH_dlen]
    call sb_push_u64
    mov r8, [r13 + RSH_data]
    add r8, [rbx + RST_bytes + SB_ptr]
    mov r9, [r13 + RSH_dlen]
    mov rdi, r14
    xor esi, esi
    mov rdx, [rip + lbuf + SB_ptr]
    mov rcx, [rip + lbuf + SB_len]
    call extproto_host_send_body
    test rax, rax
    jz 8f
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    mov [r13 + RSH_req], rax
    mov dword ptr [r13 + RSH_got], 0
    mov rdi, r14
    mov rsi, rax
    mov edx, PK_HIERCALLS
    mov ecx, QO_LANGFEAT
    call query_track
    EPILOGUE
8:  imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    mov rdi, [rbx + RST_tree]
    mov esi, [r13 + RSH_node]
    call tree_set_error
9:  EPILOGUE

# tree_load_cb(set, tr, node): an expanded row on screen wants its children; tree_retry_cb alike
tree_load_cb:
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    je 9f
    mov rdi, rsi
    mov esi, edx
    call tree_user
    test rax, rax
    jz 9f
    lea rsi, [rax - 1]
    mov rdi, rbx
    call hier_ask
9:  EPILOGUE

# hier_build(RST*): the roots' rows again, the first one expanded (its children asked for)
hier_build:
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    xor esi, esi
    call hier_rows
    cmp qword ptr [rbx + RST_hier + VEC_len], 0
    je 9f
    mov rax, [rbx + RST_hier + VEC_ptr]
    mov esi, [rax + RSH_node]
    test esi, esi
    js 9f
    mov rdi, [rbx + RST_tree]
    mov edx, 1
    call tree_expand
    mov rax, [rbx + RST_hier + VEC_ptr]
    mov esi, [rax + RSH_node]
    mov rdi, [rbx + RST_tree]
    call tree_set_cursor
9:  EPILOGUE

# find_req(ext, id) -> rax RST*, rdx the item's index, or rax 0
find_req:
    PROLOGUE
    mov r14, rdi
    mov r15, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + nhist]
    jae 8f
    lea rax, [rip + hist]
    mov r12, [rax + rbx*8]
    inc rbx
    xor r13d, r13d
2:  cmp r13, [r12 + RST_hier + VEC_len]
    jae 1b
    imul rax, r13, RSH_SIZE
    add rax, [r12 + RST_hier + VEC_ptr]
    cmp [rax + RSH_req], r15
    jne 3f
    cmp [rax + RSH_ext], r14
    jne 3f
    mov rax, r12
    mov rdx, r13
    EPILOGUE
3:  inc r13
    jmp 2b
8:  xor eax, eax
    EPILOGUE

# kids_add(RST*, i, ext, body, len) -> rax children taken, -1 when the body breaks the rules: they
# join item i's rows
kids_add:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + RST_hier + VEC_len]
    xor r9d, r9d
    cmp dword ptr [rbx + RST_kind], RSK_CALLS
    sete r9b
    mov rax, r8
    mov r8, r12
    push RH_KIDS
    push RH_KIDS
    mov rsi, rdx
    mov rdx, rcx
    mov rcx, rax
    mov rdi, rbx
    call parse_items
    add rsp, 16
    test rax, rax
    jle 9f
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r13
    call hier_rows
    mov rax, [rsp]
9:  EPILOGUE

# FN results_reply(ext, id, ok, body, len) -> eax 1 when it answered a hierarchy request
FN results_reply
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    cmp rsi, [rip + rh_id]
    jne .Lrr_kids
    test rsi, rsi
    jz .Lrr_kids
    cmp rdi, [rip + rh_ext]
    jne .Lrr_kids
    # the roots
    mov qword ptr [rip + rh_id], 0
    test r13d, r13d
    jz .Lrr_none
    mov edi, [rip + rh_kind]
    call set_new
    mov [rsp], rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r14
    mov rcx, r15
    mov r8, -1
    xor r9d, r9d                # the roots are items, not calls
    push RH_ROOTS
    push RH_ROOTS
    call parse_items
    add rsp, 16
    test rax, rax
    jg 2f
    js 11f
    mov rdi, [rsp]              # none: the set goes again
    call drop_set
    jmp .Lrr_none
11: mov rdi, rbx
    mov esi, PK_CALLH
    cmp qword ptr [rip + rh_kind], RSK_CALLS
    je 12f
    mov esi, PK_TYPEH
12: call query_dropped
    mov rdi, [rsp]
    call drop_set
    jmp .Lrr_none
2:  mov rdi, [rsp]
    mov [rdi + RST_nroots], rax
    mov rax, [rdi + RST_hier + VEC_ptr]
    mov rsi, [rax + RSH_name]
    add rsi, [rdi + RST_bytes + SB_ptr]
    call set_word
    mov rdi, [rsp]
    call hier_build
    mov rdi, [rsp]
    call show_set
    jmp .Lrr_yes
.Lrr_none:
    lea rdi, [rip + .Lno_items]
    call app_toast
    jmp .Lrr_yes
.Lrr_kids:
    mov rdi, rbx
    mov rsi, r12
    call find_req
    test rax, rax
    jz .Lrr_no
    mov [rsp], rax
    mov [rsp + 8], rdx
    imul rcx, rdx, RSH_SIZE
    add rcx, [rax + RST_hier + VEC_ptr]
    mov qword ptr [rcx + RSH_req], 0
    test r13d, r13d
    jz 5f
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    mov rcx, r14
    mov r8, r15
    call kids_add
    test rax, rax
    jns 4f
    mov rdi, rbx
    mov esi, PK_HIERCALLS
    call query_dropped
    jmp 5f
4:  # none at all: the row has no children (it stops asking)
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call kids_none
    jmp .Lrr_yes
5:  # an error or a broken answer: what parts brought stays, else an error row with Retry
    mov rax, [rsp]
    mov rcx, [rsp + 8]
    imul rcx, rcx, RSH_SIZE
    add rcx, [rax + RST_hier + VEC_ptr]
    cmp dword ptr [rcx + RSH_got], 0
    jne .Lrr_yes
    mov rdi, [rax + RST_tree]
    mov esi, [rcx + RSH_node]
    call tree_set_error
.Lrr_yes:
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
.Lrr_no:
    xor eax, eax
    EPILOGUE

# kids_none(RST*, i): item i got its answer; with no children at all its row is told so
kids_none:
    PROLOGUE
    mov rbx, rdi
    imul r12, rsi, RSH_SIZE
    add r12, [rbx + RST_hier + VEC_ptr]
    cmp dword ptr [r12 + RSH_got], 0
    jne 9f
    mov dword ptr [r12 + RSH_got], 1
    mov rdi, [rbx + RST_tree]
    mov esi, [r12 + RSH_node]
    call tree_kids_begin
    mov rdi, [rbx + RST_tree]
    xor esi, esi
    call tree_kids_end
9:  EPILOGUE

# drop_set(RST*): that set goes (wherever it is in the history)
drop_set:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + nhist]
    jae 9f
    lea rax, [rip + hist]
    cmp [rax + rbx*8], rdi
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, rbx
    call drop_at
9:  EPILOGUE

# FN results_part(ext, id, body, len) -> rax children taken from a part of a hierarchy request's
# answer, -1 when it breaks the rules, -2 when the request is not one of these
FN results_part
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    call find_req
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    mov rcx, r13
    mov r8, r14
    call kids_add
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# FN results_ext_gone(ext): its program ended: the rows waiting on it show an error with Retry
FN results_ext_gone
    PROLOGUE
    mov r14, rdi
    cmp rdi, [rip + rh_ext]
    jne 0f
    mov qword ptr [rip + rh_id], 0
    mov qword ptr [rip + rh_ext], 0
0:  xor ebx, ebx
1:  cmp rbx, [rip + nhist]
    jae 9f
    lea rax, [rip + hist]
    mov r12, [rax + rbx*8]
    inc rbx
    xor r13d, r13d
2:  cmp r13, [r12 + RST_hier + VEC_len]
    jae 1b
    imul rax, r13, RSH_SIZE
    add rax, [r12 + RST_hier + VEC_ptr]
    inc r13
    cmp [rax + RSH_ext], r14
    jne 2b
    cmp qword ptr [rax + RSH_req], 0
    je 2b
    mov qword ptr [rax + RSH_req], 0
    mov rdi, [r12 + RST_tree]
    mov esi, [rax + RSH_node]
    call tree_set_error
    jmp 2b
9:  EPILOGUE

# flip(): the shown hierarchy turns around: incoming and outgoing calls, supertypes and subtypes
FN cmd_results_flip
flip:
    PROLOGUE
    call cur_set
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    je 9f
    xor dword ptr [rbx + RST_mode], 1
    xor r12d, r12d
1:  cmp r12, [rbx + RST_hier + VEC_len]
    jae 2f
    imul r13, r12, RSH_SIZE
    add r13, [rbx + RST_hier + VEC_ptr]
    inc r12
    mov rsi, [r13 + RSH_req]
    test rsi, rsi
    jz 11f
    mov rdi, [r13 + RSH_ext]
    call query_withdraw
11: mov qword ptr [r13 + RSH_req], 0
    mov dword ptr [r13 + RSH_got], 0
    mov dword ptr [r13 + RSH_node], -1
    jmp 1b
2:  mov rax, [rbx + RST_nroots]
    mov [rbx + RST_hier + VEC_len], rax
    mov rdi, [rbx + RST_tree]
    call tree_free
    lea rdi, [rip + tree_ops]
    mov rsi, rbx
    call tree_new
    mov [rbx + RST_tree], rax
    mov rdi, rbx
    call hier_build
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- the tab ----------------

# title(RST*): lbuf = "12 references to total", "Incoming calls of main", ...
title:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + lbuf]
    call sb_clear
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    jne 2f
    lea rdi, [rip + lbuf]
    mov rsi, [rbx + RST_locs + VEC_len]
    call sb_push_u64
    lea rsi, [rip + .Lrefs_to]
    cmp qword ptr [rbx + RST_locs + VEC_len], 1
    jne 1f
    lea rsi, [rip + .Lref_to]
1:  cmp dword ptr [rbx + RST_find], 0
    je 11f
    lea rsi, [rip + .Lfound_for]
11: lea rdi, [rip + lbuf]
    call sb_push_cstr
    jmp 3f
2:  mov eax, [rbx + RST_mode]
    cmp dword ptr [rbx + RST_kind], RSK_TYPES
    jne 21f
    add eax, 2
21: lea rcx, [rip + hier_titles]
    mov rsi, [rcx + rax*8]
    lea rdi, [rip + lbuf]
    call sb_push_cstr
3:  mov rsi, [rbx + RST_word]
    test rsi, rsi
    jz 4f
    lea rdi, [rip + lbuf]
    call sb_push_cstr
4:  cmp dword ptr [rbx + RST_busy], 0
    je 5f
    lea rdi, [rip + lbuf]
    lea rsi, [rip + .Lsearching]
    call sb_push_cstr
    lea rdi, [rip + lbuf]       # and the slowest provider's last progress report
    call query_progress_label
5:  lea rdi, [rip + lbuf]
    xor esi, esi
    call sb_push_byte
    EPILOGUE

# tab_draw(ctx, x, y, w, h): the set's title, its rows under it
tab_draw:
    PROLOGUE 32
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    call cur_set
    test rax, rax
    jnz 1f
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 4]
    M ecx, MI_28
    lea r8, [rip + .Lnone]
    COLOR r9d, T_MUTED
    call ui_text_c
    EPILOGUE
1:  mov rbx, rax
    mov rdi, rbx
    call title
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 4]
    M ecx, MI_ROW
    mov r8, [rip + lbuf + SB_ptr]
    COLOR r9d, T_MUTED
    call ui_text_c
    # the set's actions at the right of its title (panel tabs have no title actions of their own)
    xor edi, edi
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_4]
    mov edx, [rsp + 4]
    M ecx, MI_ROW
    call tab_actions
    call cur_set
    test rax, rax
    jz 9f                       # dropped by its button
    mov rbx, rax
    call place_focused
    xor r9d, r9d
    cmp eax, [rip + tab_id]
    sete r9b
    M eax, MI_ROW
    mov rdi, [rbx + RST_tree]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    add edx, eax
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    sub r8d, eax
    call tree_draw
9:  EPILOGUE

# tab_key(ctx, keysym, cp, mods) -> eax taken: Escape goes to the editor, Space opens a location
# and keeps the keyboard here, the rest is the tree's
tab_key:
    PROLOGUE
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call cur_set
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp r12d, KEY_ESCAPE
    jne 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
1:  cmp r12d, ' '
    jne 2f
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz 2f
    mov rdi, [rbx + RST_tree]
    call tree_cursor
    test eax, eax
    js 2f
    mov dword ptr [rip + keep_focus], 1
    mov rdi, rbx
    mov rsi, [rbx + RST_tree]
    mov edx, eax
    call tree_activate_cb
    mov dword ptr [rip + keep_focus], 0
    mov eax, 1
    EPILOGUE
2:  mov rdi, [rbx + RST_tree]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tree_key
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# tab_actions(ctx, right, y, h) -> eax the x left of its buttons: × drops the set, › and ‹ go
# through the kept ones, and a hierarchy's direction switch
tab_actions:
    PROLOGUE 16
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    call cur_set
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r15d, r15d
1:  cmp r15d, 4
    jae 9f
    cmp r15d, 3
    jne 2f
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    je 9f
2:  M eax, MI_24
    sub r12d, eax
    lea edi, [r15 + ID_RS_BTN]
    mov esi, r12d
    mov edx, r13d
    M ecx, MI_24
    mov r8d, r14d
    lea rax, [rip + btn_icons]
    mov r9d, [rax + r15*4]
    cmp r15d, 3
    jne 3f
    mov r9d, IC_ARROW_DN
    cmp dword ptr [rbx + RST_mode], 0
    je 3f
    mov r9d, IC_ARROW_UP
3:  call ui_icon_btn
    test eax, UB_CLICK
    jz 4f
    lea rax, [rip + btn_fns]
    call [rax + r15*8]
    jmp 9f                      # the set may be gone: no more buttons this frame
4:  inc r15d
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# the title actions, also commands
FN cmd_results_drop
btn_drop:
    PROLOGUE
    cmp qword ptr [rip + nhist], 0
    je 9f
    mov rdi, [rip + cur]
    call drop_at
9:  EPILOGUE
FN cmd_results_forward
btn_next:
    mov rax, [rip + cur]
    inc rax
    cmp rax, [rip + nhist]
    jae 1f
    mov [rip + cur], rax
    mov dword ptr [rip + g_dirty], 1
1:  ret
FN cmd_results_back
btn_prev:
    mov rax, [rip + cur]
    test rax, rax
    jz 1f
    dec rax
    mov [rip + cur], rax
    mov dword ptr [rip + g_dirty], 1
1:  ret

# FN results_dump(sb): print-results: the shown set and its rows, "results=none" without one
FN results_dump
    PROLOGUE
    mov r12, rdi
    call cur_set
    test rax, rax
    jnz 1f
    mov rdi, r12
    lea rsi, [rip + .Ld_none]
    call sb_push_cstr
    EPILOGUE
1:  mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + .Ld_set]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + cur]
    inc rsi
    call sb_push_u64
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rip + nhist]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_kind]
    call sb_push_cstr
    mov eax, [rbx + RST_mode]
    cmp dword ptr [rbx + RST_kind], RSK_TYPES
    jne 2f
    add eax, 2
2:  lea rcx, [rip + hier_verbs]
    mov rsi, [rcx + rax*8]
    cmp dword ptr [rbx + RST_kind], RSK_REFS
    jne 3f
    lea rsi, [rip + .Ld_references]
    cmp dword ptr [rbx + RST_find], 0
    je 3f
    lea rsi, [rip + .Ld_find]
3:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_cur]
    call sb_push_cstr
    mov rax, [rbx + RST_cur]
    test rax, rax
    jns 4f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    mov rax, 1
4:  mov rdi, r12
    mov rsi, rax
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_title]
    call sb_push_cstr
    mov rdi, rbx
    call title
    mov rdi, r12
    mov rsi, [rip + lbuf + SB_ptr]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, [rbx + RST_tree]
    mov rsi, r12
    call tree_dump
    EPILOGUE

.section .rodata
.p2align 3
tab_place_ops: .quad tab_draw, tab_key, 0, 0, 0, 0
tree_ops: .quad tree_activate_cb, 0, 0, 0, 0, 0, tree_load_cb, tree_load_cb
btn_fns: .quad btn_drop, btn_next, btn_prev, flip
hier_verbs: .quad .Lv_in, .Lv_out, .Lv_super, .Lv_sub
hier_titles: .quad .Lt_in, .Lt_out, .Lt_super, .Lt_sub
.p2align 2
btn_icons: .long IC_CLOSE, IC_CHEV_R, IC_BACK, IC_ARROW_DN
.Ltab_name: .asciz "results"
.Ltab_title: .asciz "Results"
.Lnone: .asciz "No results yet: Find All References (shift+F12) and the hierarchies show theirs here"
.Lfound_for: .asciz " results for "
.Lrefs_to: .asciz " references to "
.Lref_to: .asciz " reference to "
.Lsearching: .asciz "  (searching...)"
.Lgap: .asciz "  "
.Lcalls_open: .asciz "  ("
.Lcalls_close: .asciz " calls)"
.Lv_callh: .asciz "call-hierarchy"
.Lv_typeh: .asciz "type-hierarchy"
.Linvoked: .asciz " invoked -"
.Lv_in: .asciz "calls-in"
.Lv_out: .asciz "calls-out"
.Lv_super: .asciz "supertypes"
.Lv_sub: .asciz "subtypes"
.Lt_in: .asciz "Incoming calls of "
.Lt_out: .asciz "Outgoing calls of "
.Lt_super: .asciz "Supertypes of "
.Lt_sub: .asciz "Subtypes of "
.Lno_callh: .asciz "No call hierarchy for this file: no running extension provides one"
.Lno_typeh: .asciz "No type hierarchy for this file: no running extension provides one"
.Lno_items: .asciz "Nothing to show a hierarchy of here"
.Ld_none: .asciz "results=none\n"
.Ld_set: .asciz "set="
.Ld_kind: .asciz " kind="
.Ld_references: .asciz "references"
.Ld_find: .asciz "find"
.Ld_cur: .asciz " cur="
.Ld_title: .asciz " title="
