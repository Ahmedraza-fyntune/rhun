# feature diff (v1.1.md): an extension's read-only tab showing a unified line diff from one open
# document to another, drawn like the git changes view (wsdiff.s). It follows both sides as they
# change (at most every 100 ms) and closes when either side closes or its extension stops.
.include "rhun.inc"

.equ DT_MAX, 128                # diff tabs in all
.equ DT_PER_EXT, 32             # and per extension
.equ DT_SIDE_MAX, 16777216      # a side larger than this is not compared
.equ DT_EVERY, 100              # ms between computations while a side changes

STRUCT
F DT_ext, 8                     # its extension
F DT_left, 8                    # the two documents' ids
F DT_right, 8
F DT_doc, 8                     # the diff tab's document
F DT_title, 8                   # owned cstr
F DT_lv, 8                      # the sides' versions it shows
F DT_rv, 8
F DT_at, 8                      # time_ms of its last computation
F DT_dead, 8                    # 1: it closes at the next tick
ENDSTRUCT DT_SIZE

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
    cmp rax, DT_SIDE_MAX
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
    mov rdi, [rbx + DT_left]
    call extproto_doc
    mov r12, rax
    mov rdi, [rbx + DT_right]
    call extproto_doc
    mov r13, rax
    test r12, r12
    jz 9f
    test r13, r13
    jz 9f
    mov rax, [r12 + DOC_version]
    mov [rbx + DT_lv], rax
    mov rax, [r13 + DOC_version]
    mov [rbx + DT_rv], rax
    call time_ms
    mov [rbx + DT_at], rax
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
8:  mov rdi, [rbx + DT_doc]
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
    imul r15, rcx, DT_SIZE
    add r15, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [r15 + DT_ext], rbx
    jne 1b
    cmp qword ptr [r15 + DT_dead], 0
    jne 1b
    inc r14
    mov rax, [r12 + DOC_id]
    cmp [r15 + DT_left], rax
    jne 1b
    mov rax, [r13 + DOC_id]
    cmp [r15 + DT_right], rax
    jne 1b
    push rcx
    push rcx
    mov rdi, [r15 + DT_title]
    call strlen
    pop rcx
    pop rcx
    cmp rax, [rsp + 8]
    jne 1b
    push rcx
    push rcx
    mov rdi, [r15 + DT_title]
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
3:  cmp r14, DT_PER_EXT
    jae 8f
    cmp qword ptr [rip + dt_vec + VEC_len], DT_MAX
    jae 8f
    lea rdi, [rip + dt_vec]
    mov esi, DT_SIZE
    call vec_push
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, DT_SIZE
    call memset
    mov [r15 + DT_ext], rbx
    mov rax, [r12 + DOC_id]
    mov [r15 + DT_left], rax
    mov rax, [r13 + DOC_id]
    mov [r15 + DT_right], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [r15 + DT_title], rax
    mov rdi, rax
    lea rsi, [rip + .Lempty]
    xor edx, edx
    mov ecx, [rsp + 16]
    call wsdiff_tab             # (shows nothing yet: dt_compute fills it)
    mov rcx, [rip + dt_vec + VEC_ptr]   # (vec_push may have moved the records: find it again)
    mov rdx, [rip + dt_vec + VEC_len]
    dec rdx
    imul rdx, rdx, DT_SIZE
    lea r15, [rcx + rdx]
    mov [r15 + DT_doc], rax
    mov rdi, r15
    call dt_compute
    jmp 7f
6:  cmp dword ptr [rsp + 16], 0
    je 7f
    mov rdi, [r15 + DT_doc]
    call doc_tab
    test rax, rax
    js 7f
    mov rdi, rax
    call app_activate_tab
7:  mov rax, [r15 + DT_doc]
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
    imul rax, rcx, DT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [rax + DT_ext], rdi
    jne 1b
    cmp qword ptr [rax + DT_dead], 0
    jne 1b
    mov rdx, [rax + DT_doc]
    cmp [rdx + DOC_id], rsi
    jne 1b
    mov qword ptr [rax + DT_dead], 1
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# FN ws_difftab_doc_closed(doc): a document goes: its diff tab's record goes with it; a side's diff
# tabs close at the next frame
FN ws_difftab_doc_closed
    push rbx
    mov rbx, rdi
    mov rcx, [rip + dt_vec + VEC_len]
1:  test rcx, rcx
    jz 9f
    dec rcx
    imul rax, rcx, DT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    cmp [rax + DT_doc], rbx
    jne 2f
    # the tab itself: the record goes (the last takes its place)
    push rcx
    push rax
    mov rdi, [rax + DT_title]
    call mem_free
    pop rdi
    pop rcx
    mov rax, [rip + dt_vec + VEC_len]
    dec rax
    mov [rip + dt_vec + VEC_len], rax
    imul rsi, rax, DT_SIZE
    add rsi, [rip + dt_vec + VEC_ptr]
    cmp rsi, rdi
    je 1b
    push rcx
    push rcx
    mov edx, DT_SIZE
    call memcpy
    pop rcx
    pop rcx
    jmp 1b
2:  mov rdx, [rbx + DOC_id]
    cmp [rax + DT_left], rdx
    je 3f
    cmp [rax + DT_right], rdx
    jne 1b
3:  mov qword ptr [rax + DT_dead], 1
    mov dword ptr [rip + g_dirty], 1
    jmp 1b
9:  pop rbx
    ret

# FN ws_difftab_ext_gone(ext): the extension stopped: its diff tabs close at the next frame
FN ws_difftab_ext_gone
    xor ecx, ecx
1:  cmp rcx, [rip + dt_vec + VEC_len]
    jae 9f
    imul rax, rcx, DT_SIZE
    add rax, [rip + dt_vec + VEC_ptr]
    inc rcx
    cmp [rax + DT_ext], rdi
    jne 1b
    mov qword ptr [rax + DT_dead], 1
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
    imul r14, rbx, DT_SIZE
    add r14, [rip + dt_vec + VEC_ptr]
    inc rbx
    xor eax, eax
    cmp qword ptr [r14 + DT_dead], 0
    jne 3f
    mov rdi, r14
    call dt_changed
    test eax, eax
    jz 1b
    mov rax, [r14 + DT_at]
    add rax, DT_EVERY
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
    mov rdi, [rbx + DT_left]
    call extproto_doc
    test rax, rax
    jz 8f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rbx + DT_lv]
    jne 9f
    mov rdi, [rbx + DT_right]
    call extproto_doc
    test rax, rax
    jz 8f
    mov rcx, [rax + DOC_version]
    cmp rcx, [rbx + DT_rv]
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
    imul r12, rbx, DT_SIZE
    add r12, [rip + dt_vec + VEC_ptr]
    cmp qword ptr [r12 + DT_dead], 0
    je 2f
    mov rdi, [r12 + DT_doc]
    call doc_tab
    test rax, rax
    js 11f
    mov rdi, rax
    call app_close_tab_now      # its record goes with its document
    jmp 1b
11: mov rdi, [r12 + DT_doc]     # no tab (cannot happen): the record goes all the same
    call ws_difftab_doc_closed
    jmp 1b
2:  mov rdi, r12
    call dt_changed
    test eax, eax
    jz 1b
    mov rax, [r12 + DT_at]
    add rax, DT_EVERY
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
