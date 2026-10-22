# feature diff (v1.1.md): an extension's read-only tab showing a unified line diff from one open
# document to another, drawn like the git changes view (wsdiff.s). It follows both sides as they
# change (at most every 100 ms) and closes when either side closes or its extension stops. A side
# may be a virtual document (feature uris) the diff opened without a tab: it goes with the last
# diff tab that shows it, unless the user opened it meanwhile.
.include "rhun.inc"

.equ DFT_MAX, 128                # diff tabs in all
.equ DFT_PER_EXT, 32             # and per extension
.equ DFT_SIDE_MAX, 16777216      # a side larger than this is not compared
.equ DFT_EVERY, 100              # ms between computations while a side changes

STRUCT
F DFT_ext, 8                     # its extension
F DFT_left, 8                    # the two documents' ids
F DFT_right, 8
F DFT_lp, 8                      # and the documents (cleared when one goes: the tab is dead then)
F DFT_rp, 8
F DFT_doc, 8                     # the diff tab's document
F DFT_title, 8                   # owned cstr
F DFT_lv, 8                      # the sides' versions it shows
F DFT_rv, 8
F DFT_at, 8                      # time_ms of its last computation
F DFT_dead, 8                    # 1: it closes at the next tick
ENDSTRUCT DFT_SIZE

.bss
.p2align 3
dt_vec: .zero VEC_SIZE
dt_sb: .zero SB_SIZE            # the unified diff
dt_a: .zero SB_SIZE             # the sides' texts
dt_b: .zero SB_SIZE

.text

# dt_text(doc, sb) -> eax 1 with the document's text in sb, 0 when it is over 16 MiB
dt_text:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call sb_clear
    mov rdi, rbx
    call doc_len
    cmp rax, DFT_SIDE_MAX
    ja 8f
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    call sb_reserve
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    mov rcx, rax
    call doc_copy
    mov [r12 + SB_len], r13
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# dt_compute(DT*): its tab shows the diff of the sides as they are now
dt_compute:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DFT_lp]
    mov r13, [rbx + DFT_rp]
    test r12, r12
    jz 9f
    test r13, r13
    jz 9f
    mov rax, [r12 + DOC_version]
    mov [rbx + DFT_lv], rax
    mov rax, [r13 + DOC_version]
    mov [rbx + DFT_rv], rax
    call time_ms
    mov [rbx + DFT_at], rax
    lea rdi, [rip + dt_sb]
    call sb_clear
    mov rdi, r12
    lea rsi, [rip + dt_a]
    call dt_text
    test eax, eax
    jz 7f
    mov rdi, r13
    lea rsi, [rip + dt_b]
    call dt_text
    test eax, eax
    jz 7f
    lea rdi, [rip + dt_sb]
    mov rsi, [r13 + DOC_name]
    mov rdx, [rip + dt_a + SB_ptr]
    mov rcx, [rip + dt_a + SB_len]
    mov r8, [rip + dt_b + SB_ptr]
    mov r9, [rip + dt_b + SB_len]
    call diff_unified
    jmp 8f
7:  # too large to compare: one hunk line says so
    lea rdi, [rip + dt_sb]
    lea rsi, [rip + .Ltoo_large]
    call sb_push_cstr
8:  mov rdi, [rbx + DFT_doc]
    mov rsi, [rip + dt_sb + SB_ptr]
    mov rdx, [rip + dt_sb + SB_len]
    call wsdiff_show
9:  EPILOGUE

# FN ws_diff_open(ext, left DOC*, right DOC*, title, len, show) -> rax the diff tab's DOC id (the
# same pair and title again: the tab it has), or 0 when the extension has 32 already (toobig)
FN ws_diff_open
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov [rsp + 16], r9
    # one it has already
    xor r14d, r14d              # its count
    xor ecx, ecx
1:  cmp rcx, [rip + dt_vec + VEC_len]
    jae 3f
    imul r15, rcx, DFT_SIZE
    add r15, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [r15 + DFT_ext], rbx
    jne 1b
    cmp qword ptr [r15 + DFT_dead], 0
    jne 1b
    inc r14
    mov rax, [r12 + DOC_id]
    cmp [r15 + DFT_left], rax
    jne 1b
    mov rax, [r13 + DOC_id]
    cmp [r15 + DFT_right], rax
    jne 1b
    push rcx
    push rcx
    mov rdi, [r15 + DFT_title]
    call strlen
    pop rcx
    pop rcx
    cmp rax, [rsp + 8]
    jne 1b
    push rcx
    push rcx
    mov rdi, [r15 + DFT_title]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jz 1b
    mov rdi, r15
    call dt_compute
    jmp 6f
3:  cmp r14, DFT_PER_EXT
    jae 8f
    cmp qword ptr [rip + dt_vec + VEC_len], DFT_MAX
    jae 8f
    lea rdi, [rip + dt_vec]
    mov esi, DFT_SIZE
    call vec_push
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, DFT_SIZE
    call memset
    mov [r15 + DFT_ext], rbx
    mov rax, [r12 + DOC_id]
    mov [r15 + DFT_left], rax
    mov rax, [r13 + DOC_id]
    mov [r15 + DFT_right], rax
    mov [r15 + DFT_lp], r12
    mov [r15 + DFT_rp], r13
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [r15 + DFT_title], rax
    mov rdi, rax
    lea rsi, [rip + .Lempty]
    xor edx, edx
    mov ecx, [rsp + 16]
    call wsdiff_tab             # (shows nothing yet: dt_compute fills it)
    mov rcx, [rip + dt_vec + VEC_ptr]   # (vec_push may have moved the records: find it again)
    mov rdx, [rip + dt_vec + VEC_len]
    dec rdx
    imul rdx, rdx, DFT_SIZE
    lea r15, [rcx + rdx]
    mov [r15 + DFT_doc], rax
    mov rdi, r15
    call dt_compute
    jmp 7f
6:  cmp dword ptr [rsp + 16], 0
    je 7f
    mov rdi, [r15 + DFT_doc]
    call doc_tab
    test rax, rax
    js 7f
    mov rdi, rax
    call app_activate_tab
7:  mov rax, [r15 + DFT_doc]
    mov rax, [rax + DOC_id]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_diff_close(ext, doc id) -> eax 1 when it was one of the extension's diff tabs (it closes at
# the next frame), 0 otherwise
FN ws_diff_close
    xor ecx, ecx
1:  cmp rcx, [rip + dt_vec + VEC_len]
    jae 8f
    imul rax, rcx, DFT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [rax + DFT_ext], rdi
    jne 1b
    cmp qword ptr [rax + DFT_dead], 0
    jne 1b
    mov rdx, [rax + DFT_doc]
    cmp [rdx + DOC_id], rsi
    jne 1b
    mov qword ptr [rax + DFT_dead], 1
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# FN ws_difftab_doc_closed(doc): a document goes: its diff tab's record goes with it (and lets go
# of its sides); a side's diff tabs close at the next frame
FN ws_difftab_doc_closed
    PROLOGUE 16
    mov rbx, rdi
    mov qword ptr [rsp], 0      # the sides of the diff tab that goes
    mov qword ptr [rsp + 8], 0
    mov r12, [rip + dt_vec + VEC_len]
1:  test r12, r12
    jz 5f
    dec r12
    imul r13, r12, DFT_SIZE
    add r13, [rip + dt_vec + VEC_ptr]
    cmp [r13 + DFT_doc], rbx
    jne 2f
    # the tab itself: the record goes (the last takes its place)
    mov rax, [r13 + DFT_lp]
    mov [rsp], rax
    mov rax, [r13 + DFT_rp]
    mov [rsp + 8], rax
    mov rdi, [r13 + DFT_title]
    call mem_free
    mov rax, [rip + dt_vec + VEC_len]
    dec rax
    mov [rip + dt_vec + VEC_len], rax
    imul rsi, rax, DFT_SIZE
    add rsi, [rip + dt_vec + VEC_ptr]
    cmp rsi, r13
    je 1b
    mov rdi, r13
    mov edx, DFT_SIZE
    call memcpy
    jmp 1b
2:  xor eax, eax
    cmp [r13 + DFT_lp], rbx
    jne 3f
    mov qword ptr [r13 + DFT_lp], 0
    mov eax, 1
3:  cmp [r13 + DFT_rp], rbx
    jne 4f
    mov qword ptr [r13 + DFT_rp], 0
    mov eax, 1
4:  test eax, eax
    jz 1b
    mov qword ptr [r13 + DFT_dead], 1
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
5:  mov rdi, [rsp]
    call dt_let_go
    mov rdi, [rsp + 8]
    cmp rdi, [rsp]
    je 9f
    call dt_let_go
9:  EPILOGUE

# FN ws_diff_unused(doc or 0): a side h_diff resolved but did not use (dt_let_go)
FN ws_diff_unused
    jmp dt_let_go

# dt_let_go(doc or 0): a side a diff tab no longer shows: a virtual document without a tab (one a
# diff opened) goes once no other diff tab shows it
dt_let_go:
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + DOC_uri], 0
    je 9f
    mov rdi, rbx
    call doc_tab
    test rax, rax
    jns 9f
    xor ecx, ecx
1:  cmp rcx, [rip + dt_vec + VEC_len]
    jae 2f
    imul rax, rcx, DFT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [rax + DFT_lp], rbx
    je 9f
    cmp [rax + DFT_rp], rbx
    je 9f
    jmp 1b
2:  mov rdi, rbx
    call doc_free
9:  EPILOGUE

# FN ws_doc_by_uri(ptr, len) -> rax the open document (in a tab) whose URI it is, or 0
FN ws_doc_by_uri
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rbx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc rbx
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r14, [rax + TAB_doc]
    test r14, r14
    jz 1b
    mov rdx, [r14 + DOC_uri]
    test rdx, rdx
    jz 1b
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN ws_difftab_ext_gone(ext): the extension stopped: its diff tabs close at the next frame
FN ws_difftab_ext_gone
    xor ecx, ecx
1:  cmp rcx, [rip + dt_vec + VEC_len]
    jae 9f
    imul rax, rcx, DFT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [rax + DFT_ext], rdi
    jne 1b
    mov qword ptr [rax + DFT_dead], 1
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
9:  ret

# FN ws_difftab_timeout() -> ms until a diff tab whose sides changed is computed again, or -1
FN ws_difftab_timeout
    PROLOGUE
    mov r12, -1
    call time_ms
    mov r13, rax
    xor ebx, ebx
1:  cmp rbx, [rip + dt_vec + VEC_len]
    jae 9f
    imul r14, rbx, DFT_SIZE
    add r14, [rip + dt_vec + VEC_ptr]
    inc rbx
    xor eax, eax
    cmp qword ptr [r14 + DFT_dead], 0
    jne 3f
    mov rdi, r14
    call dt_changed
    test eax, eax
    jz 1b
    mov rax, [r14 + DFT_at]
    add rax, DFT_EVERY
    sub rax, r13
    jns 3f
    xor eax, eax
3:  cmp r12, -1
    je 4f
    cmp rax, r12
    jge 1b
4:  mov r12, rax
    jmp 1b
9:  mov rax, r12
    EPILOGUE

# dt_changed(DT*) -> eax 1 when a side's version is not the one shown
dt_changed:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + DFT_lp]
    test rax, rax
    jz 8f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rbx + DFT_lv]
    jne 9f
    mov rax, [rbx + DFT_rp]
    test rax, rax
    jz 8f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rbx + DFT_rv]
    jne 9f
8:  xor eax, eax
    pop rbx
    ret
9:  mov eax, 1
    pop rbx
    ret

# FN ws_difftab_tick(): diff tabs that must close close; those whose sides changed are computed
# again (at most every 100 ms)
FN ws_difftab_tick
    PROLOGUE
    call time_ms
    mov r13, rax
    mov rbx, [rip + dt_vec + VEC_len]
1:  test rbx, rbx
    jz 9f
    dec rbx
    cmp rbx, [rip + dt_vec + VEC_len]
    jae 1b                      # (closing one removed records)
    imul r12, rbx, DFT_SIZE
    add r12, [rip + dt_vec + VEC_ptr]
    cmp qword ptr [r12 + DFT_dead], 0
    je 2f
    mov rdi, [r12 + DFT_doc]
    call doc_tab
    test rax, rax
    js 11f
    mov rdi, rax
    call app_close_tab_now      # its record goes with its document
    jmp 1b
11: mov rdi, [r12 + DFT_doc]     # no tab (cannot happen): the record goes all the same
    call ws_difftab_doc_closed
    jmp 1b
2:  mov rdi, r12
    call dt_changed
    test eax, eax
    jz 1b
    mov rax, [r12 + DFT_at]
    add rax, DFT_EVERY
    cmp r13, rax
    jb 1b
    mov rdi, r12
    call dt_compute
    jmp 1b
9:  EPILOGUE

# FN ws_doc_hidden(doc) -> eax 1 for a document extensions are not told about: a diff tab of
# wsdiff.s (a workspace edit's preview, an extension's diff)
FN ws_doc_hidden
    xor eax, eax
    mov rcx, [rdi + DOC_diff]
    test rcx, rcx
    jz 9f
    test dword ptr [rcx + DV_flags], DVF_OWN
    setnz al
9:  ret

.section .rodata
.Lempty: .asciz ""
.Ltoo_large: .asciz "@@ -0,0 +0,0 @@ too large to compare\n"
