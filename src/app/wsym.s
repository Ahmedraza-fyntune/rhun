# Go to Symbol in Project (docs/extensions/v1.1.md, "workspace-symbols"): the palette's symbol mode
# (ctrl+t, or "#" typed first in Go to File). 120 ms after each change of the query rhun asks every
# running provider that agreed workspace-symbols (withdrawing the requests before); answers and
# parts fill the list, which the palette filters and ranks as it does any list; the older results
# stay until the new query's first answer. Choosing one opens its file at its range.
#
#   cmd_workspace_symbols, wsym_changed(query ptr, len) (palette.s, symbol mode), wsym_chosen(i),
#   wsym_tick(), wsym_timeout() -> ms, wsym_reply(ext, id, ok, body, len) -> eax 1 when it answered,
#   wsym_part(ext, id, body, len) -> rax records, -1 broken, -2 not one of its requests,
#   wsym_ext_gone(ext)
.include "rhun.inc"

.equ WS_DEBOUNCE, 120
.equ WS_MAX_HINT, 500           # MAX in the request
.equ WS_KEEP, 5000              # symbols kept for the list
.equ WS_REQS, 16
.equ WS_QUERY_MAX, 256

# a symbol
STRUCT
F WSY_path, 8                   # offsets in ws_bytes, cstrs
F WSY_name, 8
F WSY_detail, 8                 # "container  folder/file:line"
F WSY_l1, 4
F WSY_c1, 4
F WSY_l2, 4
F WSY_c2, 4
ENDSTRUCT WSY_SIZE

.bss
.p2align 3
ws_open: .long 0                # the palette is in symbol mode
ws_fresh: .long 0               # the list holds the current query's answers (else the older ones)
ws_due: .quad 0                 # when to ask (time_ms), 0: not due
ws_reqs: .zero 16 * WS_REQS     # ext, id
ws_nreqs: .quad 0
ws_syms: .zero VEC_SIZE         # WSY
ws_bytes: .zero SB_SIZE
ws_query: .zero SB_SIZE
ws_line: .zero SB_SIZE
ws_tmp: .zero SB_SIZE

.text

# FN cmd_workspace_symbols(): ctrl+t
FN cmd_workspace_symbols
    PROLOGUE
    call ed_single
    lea rdi, [rip + .Llabel]
    call palette_wsym_open
    mov dword ptr [rip + ws_open], 1
    mov dword ptr [rip + ws_fresh], 0
    mov qword ptr [rip + ws_syms + VEC_len], 0
    lea rdi, [rip + ws_bytes]
    call sb_clear
    xor edi, edi
    xor esi, esi
    call wsym_changed
    call time_ms                # the empty query: asked at once
    mov [rip + ws_due], rax
    EPILOGUE

# FN wsym_changed(ptr, len): the symbol mode's query changed (palette.s): asked 120 ms later
FN wsym_changed
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov dword ptr [rip + ws_open], 1
    cmp r12, WS_QUERY_MAX
    jbe 1f
    mov r12d, WS_QUERY_MAX
1:  lea rdi, [rip + ws_query]
    call sb_clear
    test r12, r12
    jz 2f
    lea rdi, [rip + ws_query]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
2:  call time_ms
    add rax, WS_DEBOUNCE
    mov [rip + ws_due], rax
    EPILOGUE

# withdraw(): the requests out are not wanted
withdraw:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + ws_nreqs]
    jae 2f
    mov rax, rbx
    shl rax, 4
    lea rcx, [rip + ws_reqs]
    mov rdi, [rcx + rax]
    mov rsi, [rcx + rax + 8]
    call query_withdraw
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + ws_nreqs], 0
    EPILOGUE

# FN wsym_tick(): the query is asked when due; the mode ending withdraws it
FN wsym_tick
    PROLOGUE
    cmp dword ptr [rip + ws_open], 0
    je 9f
    call palette_wsym_showing
    test eax, eax
    jnz 1f
    mov dword ptr [rip + ws_open], 0
    mov qword ptr [rip + ws_due], 0
    call withdraw
    jmp 9f
1:  mov rax, [rip + ws_due]
    test rax, rax
    jz 9f
    call time_ms
    cmp rax, [rip + ws_due]
    jb 9f
    mov qword ptr [rip + ws_due], 0
    call ask
9:  EPILOGUE

# FN wsym_timeout() -> ms until the query is due, or -1
FN wsym_timeout
    mov rax, [rip + ws_due]
    test rax, rax
    jz 8f
    push rax
    push rax
    call time_ms
    pop rcx
    pop rcx
    sub rcx, rax
    jns 1f
    xor ecx, ecx
1:  mov eax, ecx
    ret
8:  mov eax, -1
    ret

# ask(): "workspace-symbols MAX LEN" + the query to every running provider of the feature
ask:
    PROLOGUE
    call withdraw
    mov dword ptr [rip + ws_fresh], 0
    lea rdi, [rip + ws_line]
    call sb_clear
    lea rdi, [rip + ws_line]
    lea rsi, [rip + .Lv_wsym]
    call sb_push_cstr
    lea rdi, [rip + ws_line]
    mov rsi, [rip + ws_query + SB_len]
    call sb_push_u64
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 9f
    imul r12, rbx, EXT_SIZE
    add r12, [rip + g_exts + VEC_ptr]
    inc rbx
    cmp qword ptr [rip + ws_nreqs], WS_REQS
    jae 9f
    mov rdi, r12
    call ext_is_visible
    test eax, eax
    jz 1b
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne 1b
    mov rdi, r12
    mov esi, FEAT_WORKSPACE_SYMBOLS
    call ext_feature
    test eax, eax
    jz 1b
    mov rdi, r12
    mov esi, EXT_pv_workspace_symbols
    call ext_pv
    test rax, rax
    jz 1b
    cmp byte ptr [rax], 0
    je 1b
    mov rdi, r12
    xor esi, esi
    mov rdx, [rip + ws_line + SB_ptr]
    mov rcx, [rip + ws_line + SB_len]
    mov r8, [rip + ws_query + SB_ptr]
    mov r9, [rip + ws_query + SB_len]
    call extproto_host_send_body
    test rax, rax
    jz 1b
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    mov edx, PK_WSYMBOLS
    mov ecx, QO_LANGFEAT
    call query_track
    mov rax, [rip + ws_nreqs]
    shl rax, 4
    lea rcx, [rip + ws_reqs]
    mov [rcx + rax], r12
    mov [rcx + rax + 8], r13
    inc qword ptr [rip + ws_nreqs]
    jmp 1b
9:  EPILOGUE

# req_index(ext, id) -> rax its index among the requests out, or -1
req_index:
    xor eax, eax
1:  cmp rax, [rip + ws_nreqs]
    jae 8f
    mov rcx, rax
    shl rcx, 4
    lea rdx, [rip + ws_reqs]
    cmp [rdx + rcx], rdi
    jne 2f
    cmp [rdx + rcx + 8], rsi
    je 9f
2:  inc rax
    jmp 1b
8:  mov rax, -1
9:  ret

# FN wsym_part(ext, id, body, len) -> rax records taken, -1 when the part breaks the rules, -2 when
# the request is not one of the symbol mode's
FN wsym_part
    PROLOGUE
    mov r12, rdx
    mov r13, rcx
    call req_index
    test rax, rax
    js 8f
    mov rdi, r12
    mov rsi, r13
    call take
    EPILOGUE
8:  mov rax, -2
    EPILOGUE

# FN wsym_reply(ext, id, ok, body, len) -> eax 1 when it answered one of the symbol mode's requests
FN wsym_reply
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    call req_index
    test rax, rax
    js 8f
    mov rcx, [rip + ws_nreqs]   # its record goes (the last takes its place)
    dec rcx
    mov [rip + ws_nreqs], rcx
    shl rcx, 4
    shl rax, 4
    lea rdx, [rip + ws_reqs]
    mov rsi, [rdx + rcx]
    mov [rdx + rax], rsi
    mov rsi, [rdx + rcx + 8]
    mov [rdx + rax + 8], rsi
    test r13d, r13d
    jz 7f
    mov rdi, r14
    mov rsi, r15
    call take
    test rax, rax
    jns 7f
    mov rdi, rbx
    mov esi, PK_WSYMBOLS
    call query_dropped
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# take(body, len) -> rax the symbols taken into the list (the first answer of a query replaces the
# older ones), -1 when the body breaks the rules (nothing taken)
take:
    PROLOGUE 64
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov edx, 10000
    call lf_head
    test rax, rax
    js 8f
    mov r15, rax
    cmp dword ptr [rip + ws_fresh], 0
    jne 1f
    mov dword ptr [rip + ws_fresh], 1     # the older results go now
    mov qword ptr [rip + ws_syms + VEC_len], 0
    lea rdi, [rip + ws_bytes]
    call sb_clear
1:  mov rax, [rip + ws_syms + VEC_len]
    mov [rsp + 16], rax
    mov rax, [rip + ws_bytes + SB_len]
    mov [rsp + 24], rax
2:  test r15, r15
    jz 6f
    dec r15
    call ps_line
    test eax, eax
    jz 7f
    call lf_four
    test eax, eax
    jz 7f
    call ps_word                # KIND (not kept)
    test rdx, rdx
    jz 7f
    call ps_num                 # PATH_LEN
    test edx, edx
    jz 7f
    test rax, rax
    jz 7f
    cmp rax, 4096
    ja 7f
    mov r12, rax
    call ps_num                 # NAME_LEN
    test edx, edx
    jz 7f
    test rax, rax
    jz 7f
    cmp rax, 1000
    ja 7f
    mov r13, rax
    call ps_num                 # DETAIL_LEN
    test edx, edx
    jz 7f
    cmp rax, 1000
    ja 7f
    mov r14, rax
    call ps_eol
    test eax, eax
    jz 7f
    mov rdi, r12
    call lf_take
    test rax, rax
    jz 7f
    mov [rsp + 32], rax         # the path
    mov rdi, rax
    mov rsi, r12
    call lf_path_ok
    test eax, eax
    jz 7f
    mov rdi, r13
    call lf_take
    test rax, rax
    jz 7f
    mov [rsp + 40], rax         # the name
    mov rdi, r14
    call lf_take
    test rax, rax
    jz 7f
    mov [rsp + 48], rax         # the detail
    cmp qword ptr [rip + ws_syms + VEC_len], WS_KEEP
    jae 2b                      # enough to choose from: read and left out
    mov rdi, [rsp + 32]
    mov rsi, r12
    call str_in
    mov [rsp + 56], rax
    mov rdi, [rsp + 40]
    mov rsi, r13
    call str_in
    push rax
    push rax
    mov rdi, [rsp + 48 + 16]    # "container  folder/file:line"
    mov rsi, r14
    mov rdx, [rsp + 56 + 16]
    call detail_in
    mov rcx, rax
    pop rdx
    pop rdx
    push rcx
    push rdx
    lea rdi, [rip + ws_syms]
    mov esi, WSY_SIZE
    call vec_push
    pop rdx
    pop rcx
    mov [rax + WSY_name], rdx
    mov [rax + WSY_detail], rcx
    mov rcx, [rsp + 56]
    mov [rax + WSY_path], rcx
    lea rcx, [rip + lf_tmp4]
    mov edx, [rcx]
    mov [rax + WSY_l1], edx
    mov edx, [rcx + 4]
    mov [rax + WSY_c1], edx
    mov edx, [rcx + 8]
    mov [rax + WSY_l2], edx
    mov edx, [rcx + 12]
    mov [rax + WSY_c2], edx
    jmp 2b
6:  mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne 7f
    call fill
    mov rax, [rip + ws_syms + VEC_len]
    sub rax, [rsp + 16]
    EPILOGUE
7:  mov rax, [rsp + 16]         # broken: what it added goes
    mov [rip + ws_syms + VEC_len], rax
    mov rax, [rsp + 24]
    mov [rip + ws_bytes + SB_len], rax
8:  mov rax, -1
    EPILOGUE

# str_in(ptr, len) -> rax the offset of a one-line copy in ws_bytes (line breaks as spaces)
str_in:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rip + ws_bytes + SB_len]
    xor r14d, r14d
1:  cmp r14, r12
    jae 2f
    movzx esi, byte ptr [rbx + r14]
    cmp esi, ' '
    jae 11f
    mov esi, ' '
11: lea rdi, [rip + ws_bytes]
    call sb_push_byte
    inc r14
    jmp 1b
2:  lea rdi, [rip + ws_bytes]
    xor esi, esi
    call sb_push_byte
    mov rax, r13
    EPILOGUE

# detail_in(container ptr, len, path offset) -> rax the offset of "container  folder/file:LINE" (the
# path relative to the project when inside it; LINE from lf_tmp4)
detail_in:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rip + ws_bytes + SB_len]
    lea rdi, [rip + ws_tmp]
    call sb_clear
    test r12, r12
    jz 1f
    lea rdi, [rip + ws_tmp]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    lea rdi, [rip + ws_tmp]
    lea rsi, [rip + .Lgap]
    call sb_push_cstr
1:  mov r15, r13
    add r15, [rip + ws_bytes + SB_ptr]   # the path, relative when inside the project
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 2f
    call strlen
    mov rbx, rax
    mov rdi, r15
    call strlen
    mov rdi, r15
    mov rsi, rax
    mov rdx, [rip + g_project]
    mov rcx, rbx
    call str_starts
    test eax, eax
    jz 2f
    movzx eax, byte ptr [r15 + rbx]
    cmp eax, '/'
    je 11f
    cmp eax, '\\'
    jne 2f
11: lea r15, [r15 + rbx + 1]
2:  lea rdi, [rip + ws_tmp]
    mov rsi, r15
    call sb_push_cstr
    lea rdi, [rip + ws_tmp]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + ws_tmp]
    mov esi, [rip + lf_tmp4]
    call sb_push_u64
    mov rdi, [rip + ws_tmp + SB_ptr]
    mov rsi, [rip + ws_tmp + SB_len]
    call str_in
    EPILOGUE

# fill(): the palette's list from the symbols (its strings move as ws_bytes grows: all again)
fill:
    PROLOGUE
    cmp dword ptr [rip + ws_open], 0
    je 9f
    call palette_wsym_showing
    test eax, eax
    jz 9f
    call palette_wsym_clear
    xor ebx, ebx
1:  cmp rbx, [rip + ws_syms + VEC_len]
    jae 2f
    imul r12, rbx, WSY_SIZE
    add r12, [rip + ws_syms + VEC_ptr]
    mov r13, [r12 + WSY_name]
    add r13, [rip + ws_bytes + SB_ptr]
    mov rdi, r13
    call strlen
    mov rsi, rax
    mov rdi, r13
    mov rdx, [r12 + WSY_detail]
    add rdx, [rip + ws_bytes + SB_ptr]
    mov rcx, rbx
    call palette_wsym_add
    inc rbx
    jmp 1b
2:  call palette_wsym_ready
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN wsym_chosen(i): symbol i's file opens at its start
FN wsym_chosen
    PROLOGUE
    cmp rdi, [rip + ws_syms + VEC_len]
    jae 9f
    imul rbx, rdi, WSY_SIZE
    add rbx, [rip + ws_syms + VEC_ptr]
    mov dword ptr [rip + ws_open], 0
    call withdraw
    mov rdi, [rbx + WSY_path]
    add rdi, [rip + ws_bytes + SB_ptr]
    call lf_open_path
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, r12
    mov esi, [rbx + WSY_l1]
    mov edx, [rbx + WSY_c1]
    call lf_pos_near
    mov [r12 + DOC_cur], rax
    mov [r12 + DOC_anchor], rax
    call ed_touch
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN wsym_ext_gone(ext): its requests are not waited for
FN wsym_ext_gone
    xor ecx, ecx
1:  cmp rcx, [rip + ws_nreqs]
    jae 9f
    mov rax, rcx
    shl rax, 4
    lea rdx, [rip + ws_reqs]
    add rax, rdx
    cmp [rax], rdi
    je 2f
    inc rcx
    jmp 1b
2:  mov rdx, [rip + ws_nreqs]
    dec rdx
    mov [rip + ws_nreqs], rdx
    shl rdx, 4
    lea r8, [rip + ws_reqs]
    mov rsi, [r8 + rdx]
    mov [rax], rsi
    mov rsi, [r8 + rdx + 8]
    mov [rax + 8], rsi
    jmp 1b
9:  ret

.section .rodata
.Llabel: .asciz "Go to Symbol in Project"
.Lv_wsym: .asciz "workspace-symbols 500 "
.Lgap: .asciz "  "
