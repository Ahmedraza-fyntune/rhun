# agent sources from extensions (wider-parity D1): the sessions of another agent an extension lists
# in the agents panel (feature agents), and the transcripts rhun asks it for. What one extension
# contributes to the AI features is kept here, in a table indexed like g_exts (ai_ext), along with
# the small reader the AI parsers share (ai_rd_*).
.include "rhun.inc"

.equ AGENT_ROWS_MAX, 1000
.equ AGENT_SID_MAX, 128
.equ AGENT_TITLE_MAX, 200       # a row's title is cut to this many bytes, the model to 120
.equ AGENT_MODEL_MAX, 120
.equ AGENT_FIELD_MAX, 4096      # any field of a row, before cutting
.equ AGENT_TEXT_MAX, 71680      # a message's text is cut at 70 KB, as OpenCode copies are
.equ AGENT_MSGS_MAX, 2000       # messages one transcript answer may hold

.bss
.p2align 3
ax_tab: .zero AX_SIZE * EXT_CAP
rd_p: .quad 0
rd_end: .quad 0
rows_new: .zero VEC_SIZE        # agentext_set_rows: the parsed rows (RW records)
keep: .zero VEC_SIZE            # and the AS objects that stay
hidden_names: .zero VEC_SIZE    # cstr OWNER/NAME of the sources switched off in Settings
qual: .zero SB_SIZE
tmp: .zero SB_SIZE
match_len: .quad 0              # cwd_match: the longest root that holds the CWD so far
match_name: .quad 0             #   its worktree name (a copy) when it is a linked worktree
match_cwd: .quad 0

# a row as parsed, pointing into the body
STRUCT
F RW_updated, 8
F RW_state, 8
F RW_sid, 8
F RW_sidlen, 8
F RW_title, 8
F RW_titlelen, 8
F RW_model, 8
F RW_modellen, 8
F RW_cwd, 8
F RW_cwdlen, 8
ENDSTRUCT RW_SIZE

.text

# FN ai_ext(ext) -> AX*: what the extension contributes to the AI features
FN ai_ext
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    imul rax, rax, AX_SIZE
    lea rcx, [rip + ax_tab]
    add rax, rcx
    ret

# FN ai_ext_reset(ext): a record being (re)loaded from its manifest starts with nothing
FN ai_ext_reset
    PROLOGUE
    mov rbx, rdi
    call agentext_gone
    mov rdi, rbx
    call ai_ext
    mov r12, rax
    mov rdi, [r12 + AX_title]
    call mem_free
    lea rdi, [r12 + AX_rows]
    call vec_free
    mov rdi, rbx
    call tools_ext_reset
    mov rdi, r12
    mov ecx, AX_SIZE
    xor eax, eax
    rep stosb
    EPILOGUE

# ---------------- the shared reader ----------------

# FN ai_rd_init(ptr, len): the bytes the ai_rd_* functions read
FN ai_rd_init
    mov [rip + rd_p], rdi
    add rdi, rsi
    mov [rip + rd_end], rdi
    ret

# FN ai_rd_pos() -> rax the next byte's address
FN ai_rd_pos
    mov rax, [rip + rd_p]
    ret

# FN ai_rd_num() -> rax value, edx 1, and the space after it skipped; edx 0 when there is no decimal
#   number of 1 to 18 digits
FN ai_rd_num
    mov rcx, [rip + rd_p]
    mov r8, [rip + rd_end]
    xor eax, eax
    xor edx, edx
1:  cmp rcx, r8
    jae 2f
    movzx r9d, byte ptr [rcx]
    sub r9d, '0'
    cmp r9d, 9
    ja 2f
    cmp edx, 18
    jae 8f
    imul rax, rax, 10
    add rax, r9
    inc edx
    inc rcx
    jmp 1b
2:  test edx, edx
    jz 8f
    cmp rcx, r8
    jae 3f
    cmp byte ptr [rcx], ' '
    jne 3f
    inc rcx
3:  mov [rip + rd_p], rcx
    mov edx, 1
    ret
8:  xor edx, edx
    ret

# FN ai_rd_word() -> rax ptr, rdx len of the bytes up to a space or LF (the space skipped)
FN ai_rd_word
    mov rax, [rip + rd_p]
    mov r8, [rip + rd_end]
    mov rcx, rax
1:  cmp rcx, r8
    jae 2f
    cmp byte ptr [rcx], ' '
    je 2f
    cmp byte ptr [rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov rdx, rcx
    sub rdx, rax
    cmp rcx, r8
    jae 3f
    cmp byte ptr [rcx], ' '
    jne 3f
    inc rcx
3:  mov [rip + rd_p], rcx
    ret

# FN ai_rd_eol() -> eax 1 when the next byte is LF (taken), else 0
FN ai_rd_eol
    mov rcx, [rip + rd_p]
    xor eax, eax
    cmp rcx, [rip + rd_end]
    jae 1f
    cmp byte ptr [rcx], 10
    jne 1f
    inc rcx
    mov [rip + rd_p], rcx
    inc eax
1:  ret

# FN ai_rd_take(n) -> rax the address of the next n bytes (taken), or 0 when fewer are left
FN ai_rd_take
    mov rax, [rip + rd_p]
    mov rcx, [rip + rd_end]
    sub rcx, rax
    cmp rdi, rcx
    ja 1f
    add [rip + rd_p], rdi
    ret
1:  xor eax, eax
    ret

# FN ai_rd_line() -> rax ptr, rdx len of the rest of the line (the LF taken); rax 0 without an LF
FN ai_rd_line
    mov rax, [rip + rd_p]
    mov r8, [rip + rd_end]
    mov rcx, rax
1:  cmp rcx, r8
    jae 8f
    cmp byte ptr [rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov rdx, rcx
    sub rdx, rax
    inc rcx
    mov [rip + rd_p], rcx
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# FN ai_rd_done() -> eax 1 when every byte was read
FN ai_rd_done
    mov rcx, [rip + rd_p]
    xor eax, eax
    cmp rcx, [rip + rd_end]
    sete al
    ret

# FN ai_cut(ptr, len, max) -> rax ptr, rdx len cut to at most max bytes, at a character boundary
FN ai_cut
    mov rax, rdi
    cmp rsi, rdx
    jbe 2f
1:  test rdx, rdx
    jz 3f
    movzx ecx, byte ptr [rdi + rdx]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne 3f
    dec rdx
    jmp 1b
2:  mov rdx, rsi
3:  ret

# FN ai_dup(ptr, len) -> a NUL-terminated copy (mem_alloc'd)
FN ai_dup
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsi + 1]
    call mem_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov byte ptr [r13 + r12], 0
    mov rax, r13
    EPILOGUE

# FN ai_word_ok(ptr, len, max) -> eax 1 when it is 1 to max bytes of visible ASCII (an id that goes in
#   a space-separated field)
FN ai_word_ok
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, rdx
    ja 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    cmp edx, 0x21
    jb 9f
    cmp edx, 0x7e
    ja 9f
    inc rcx
    cmp rcx, rsi
    jb 1b
    inc eax
9:  ret

# ---------------- the manifest ----------------

# FN agentext_manifest_kv(ext, ini) -> eax 1 when the [provides] key was agents or agents.title
FN agentext_manifest_kv
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Lk_agents]
    call ini_key_is
    test eax, eax
    jz 1f
    mov rdi, rbx
    call ai_ext
    mov r13, rax
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call parse_bool
    mov [r13 + AX_agents], eax
    mov rdi, rbx
    call agentext_hidden_load
    mov eax, 1
    EPILOGUE
1:  mov rdi, r12
    lea rsi, [rip + .Lk_agents_title]
    call ini_key_is
    test eax, eax
    jz 9f
    mov rdi, rbx
    call ai_ext
    mov r13, rax
    mov rdi, [r13 + AX_title]
    call mem_free
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    mov edx, 80
    call ai_cut
    mov rdi, rax
    mov rsi, rdx
    call ai_dup
    mov [r13 + AX_title], rax
    mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# FN agentext_title(ext) -> cstr: the name its sessions show (agents.title, else its title)
FN agentext_title
    push rbx
    mov rbx, rdi
    call ai_ext
    mov rax, [rax + AX_title]
    test rax, rax
    jnz 1f
    mov rdi, rbx
    call ext_title
1:  pop rbx
    ret

# ---------------- rows (agent-sessions) ----------------

# FN agentext_set_rows(ext, body, len) -> rax 0, or the error reply's "CODE TEXT": its rows replaced
#   by the body's: N LF, then N rows UPDATED STATE SID_LEN TITLE_LEN MODEL_LEN CWD_LEN LF and the four
#   strings. Rows keep their objects (and a fetched transcript) by session id.
FN agentext_set_rows
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov rdi, rbx
    call ai_ext
    mov r15, rax
    cmp dword ptr [r15 + AX_agents], 0
    je .Lsr_provides
    mov qword ptr [rip + rows_new + VEC_len], 0
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call ai_rd_init
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov r12, rax
    call ai_rd_eol
    test eax, eax
    jz .Lsr_syntax
    cmp r12, AGENT_ROWS_MAX
    ja .Lsr_toobig
.Lsr_row:
    test r12, r12
    jz .Lsr_parsed
    dec r12
    lea rdi, [rip + rows_new]
    mov esi, RW_SIZE
    call vec_push
    mov r13, rax
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov [r13 + RW_updated], rax
    call ai_rd_word
    mov rdi, rax
    mov rsi, rdx
    call state_of
    test rax, rax
    js .Lsr_syntax
    mov [r13 + RW_state], rax
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov [r13 + RW_sidlen], rax
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov [r13 + RW_titlelen], rax
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov [r13 + RW_modellen], rax
    call ai_rd_num
    test edx, edx
    jz .Lsr_syntax
    mov [r13 + RW_cwdlen], rax
    call ai_rd_eol
    test eax, eax
    jz .Lsr_syntax
    cmp qword ptr [r13 + RW_titlelen], AGENT_FIELD_MAX
    ja .Lsr_syntax
    cmp qword ptr [r13 + RW_modellen], AGENT_FIELD_MAX
    ja .Lsr_syntax
    cmp qword ptr [r13 + RW_cwdlen], AGENT_FIELD_MAX
    ja .Lsr_syntax
    mov rdi, [r13 + RW_sidlen]
    call ai_rd_take
    test rax, rax
    jz .Lsr_syntax
    mov [r13 + RW_sid], rax
    mov rdi, rax
    mov rsi, [r13 + RW_sidlen]
    mov edx, AGENT_SID_MAX
    call ai_word_ok
    test eax, eax
    jz .Lsr_syntax
    mov rdi, [r13 + RW_titlelen]
    call ai_rd_take
    test rax, rax
    jz .Lsr_syntax
    mov [r13 + RW_title], rax
    mov rdi, [r13 + RW_modellen]
    call ai_rd_take
    test rax, rax
    jz .Lsr_syntax
    mov [r13 + RW_model], rax
    mov rdi, [r13 + RW_cwdlen]
    call ai_rd_take
    test rax, rax
    jz .Lsr_syntax
    mov [r13 + RW_cwd], rax
    # a CWD is an absolute path without NUL or LF, or nothing
    mov rcx, [r13 + RW_cwdlen]
    test rcx, rcx
    jz .Lsr_row
    mov rdi, rax
    xor edx, edx
1:  movzx eax, byte ptr [rdi + rdx]
    test eax, eax
    jz .Lsr_syntax
    cmp eax, 10
    je .Lsr_syntax
    inc rdx
    cmp rdx, rcx
    jb 1b
    PATH_ABSOLUTE rdi, .Lsr_row
    jmp .Lsr_syntax
.Lsr_parsed:
    call ai_rd_done
    test eax, eax
    jz .Lsr_syntax
    # a session id names one row
    xor r12d, r12d
2:  cmp r12, [rip + rows_new + VEC_len]
    jae 4f
    imul r13, r12, RW_SIZE
    add r13, [rip + rows_new + VEC_ptr]
    xor r14d, r14d
3:  cmp r14, r12
    jae 31f
    imul rax, r14, RW_SIZE
    add rax, [rip + rows_new + VEC_ptr]
    mov rcx, [rax + RW_sidlen]
    cmp rcx, [r13 + RW_sidlen]
    jne 32f
    mov rdi, [rax + RW_sid]
    mov rsi, [r13 + RW_sid]
    mov rdx, rcx
    call memeq
    test eax, eax
    jnz .Lsr_syntax
32: inc r14
    jmp 3b
31: inc r12
    jmp 2b
4:  # the new list: existing objects updated, new ones made
    mov qword ptr [rip + keep + VEC_len], 0
    xor r12d, r12d
5:  cmp r12, [rip + rows_new + VEC_len]
    jae 7f
    imul r13, r12, RW_SIZE
    add r13, [rip + rows_new + VEC_ptr]
    mov rdi, r15
    mov rsi, [r13 + RW_sid]
    mov rdx, [r13 + RW_sidlen]
    call row_find
    test rax, rax
    jnz 6f
    mov rdi, rbx
    mov rsi, r13
    call row_new
6:  mov r14, rax
    mov rdi, r14
    mov rsi, r13
    call row_update
    lea rdi, [rip + keep]
    mov esi, 8
    call vec_push
    mov [rax], r14
    inc r12
    jmp 5b
7:  # swap the lists, show them, then free the rows that went (after the panel forgot them)
    mov rax, [r15 + AX_rows + VEC_ptr]
    mov rcx, [r15 + AX_rows + VEC_len]
    mov rdx, [r15 + AX_rows + VEC_cap]
    mov [rsp + 16], rax
    mov [rsp + 24], rcx
    mov rax, [rip + keep + VEC_len]
    lea rdi, [rax*8 + 8]
    call mem_alloc
    mov [r15 + AX_rows + VEC_ptr], rax
    mov rcx, [rip + keep + VEC_len]
    mov [r15 + AX_rows + VEC_len], rcx
    inc rcx
    mov [r15 + AX_rows + VEC_cap], rcx
    mov rdi, rax
    mov rsi, [rip + keep + VEC_ptr]
    mov rdx, [rip + keep + VEC_len]
    shl rdx, 3
    call memcpy
    call agents_ext_rows
    xor r12d, r12d
8:  cmp r12, [rsp + 24]
    jae 81f
    mov rax, [rsp + 16]
    mov r13, [rax + r12*8]
    inc r12
    mov rdi, r15
    mov rsi, r13
    call row_listed
    test eax, eax
    jnz 8b
    mov rdi, r13
    call row_free
    jmp 8b
81: mov rdi, [rsp + 16]
    call mem_free
    xor eax, eax
    EPILOGUE
.Lsr_provides:
    lea rax, [rip + .Le_provides]
    EPILOGUE
.Lsr_toobig:
    lea rax, [rip + .Le_rows_toobig]
    EPILOGUE
.Lsr_syntax:
    lea rax, [rip + .Le_rows_syntax]
    EPILOGUE

# state_of(ptr, len) -> rax AGS_*, or -1
state_of:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  lea rax, [rip + state_names]
    mov rdx, [rax + r13*8]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13
    jmp 1b
2:  mov rax, r13
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# row_find(AX*, sid, len) -> AS* with that session id, or 0
row_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + AX_rows + VEC_len]
    jae 8f
    mov rax, [rbx + AX_rows + VEC_ptr]
    mov r15, [rax + r14*8]
    inc r14
    mov rdi, [r15 + AS_sid]
    mov rsi, r12
    mov rdx, r13
    call str_eq_cstr_rev
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# str_eq_cstr_rev(cstr, ptr, len) -> eax 1 when equal
str_eq_cstr_rev:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rax
    jmp str_eq_cstr

# row_listed(AX*, AS*) -> eax 1 when the row is in its rows
row_listed:
    xor ecx, ecx
1:  cmp rcx, [rdi + AX_rows + VEC_len]
    jae 8f
    mov rax, [rdi + AX_rows + VEC_ptr]
    cmp [rax + rcx*8], rsi
    je 9f
    inc rcx
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# row_new(ext, RW*) -> a new AS for the row (kind 5), cleared
row_new:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, AS_SIZE
    call mem_alloc
    mov r13, rax
    mov rdi, rax
    mov ecx, AS_SIZE
    xor eax, eax
    rep stosb
    mov dword ptr [r13 + AS_kind], AS_KIND_EXT
    mov [r13 + AS_ext], rbx
    mov qword ptr [r13 + AS_dirty], 0
    mov dword ptr [r13 + AS_titled], 1
    mov rdi, [r12 + RW_sid]
    mov rsi, [r12 + RW_sidlen]
    call ai_dup
    mov [r13 + AS_sid], rax
    # the key the panel's tables know a row by: OWNER/NAME:SID
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, ':'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r13 + AS_sid]
    call sb_push_cstr
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [rip + tmp + SB_len]
    call ai_dup
    mov [r13 + AS_path], rax
    mov rax, r13
    EPILOGUE

# row_update(AS*, RW*): the row's title, model, state, time and folder from the parsed row
row_update:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + RW_state]
    mov [rbx + AS_state], eax
    mov rax, [r12 + RW_updated]
    cmp rax, [rbx + AS_mtime]
    je 1f
    mov [rbx + AS_mtime], rax
    mov rcx, 1000000000
    imul rax, rcx
    mov [rbx + AS_recency], rax
    call time_ms
    mov [rbx + AS_changed], rax
1:  # the title: its first line, trimmed and cut
    mov rdi, [r12 + RW_title]
    mov rsi, [r12 + RW_titlelen]
    xor ecx, ecx
2:  cmp rcx, rsi
    jae 3f
    cmp byte ptr [rdi + rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov rsi, rcx
    call trim
    mov rdi, rax
    mov rsi, rdx
    mov edx, AGENT_TITLE_MAX
    call ai_cut
    lea rdi, [rbx + AS_title]
    mov rsi, rax
    call set_slot
    mov rdi, [r12 + RW_model]
    mov rsi, [r12 + RW_modellen]
    mov edx, AGENT_MODEL_MAX
    call ai_cut
    lea rdi, [rbx + AS_model]
    mov rsi, rax
    call set_slot
    lea rdi, [rbx + AS_cwd]
    mov rsi, [r12 + RW_cwd]
    mov rdx, [r12 + RW_cwdlen]
    call set_slot
    mov rdi, rbx
    call row_match
    EPILOGUE

# set_slot(slot, ptr, len): *slot holds a copy of the bytes, or 0 for none
set_slot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [rbx]
    call mem_free
    mov qword ptr [rbx], 0
    test r13, r13
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call ai_dup
    mov [rbx], rax
9:  EPILOGUE

# row_free(AS*): a row that went; a card still open on it is answered cancelled
row_free:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + AS_req]     # a transcript asked for is no longer wanted
    test rsi, rsi
    jz 1f
    mov rdi, [rbx + AS_ext]
    call query_withdraw
1:  mov rdi, rbx
    call agentext_ask_drop
    mov rdi, [rbx + AS_sid]
    call mem_free
    mov rdi, rbx
    call agent_session_free
    EPILOGUE

# ---------------- which rows the project shows ----------------

# row_match(AS*): AXF_MATCH and AS_worktree from its CWD: none (any project), the project or a folder
#   in it, or one of the repository's checkouts (a linked worktree gets its badge)
row_match:
    PROLOGUE
    mov rbx, rdi
    and dword ptr [rbx + AS_xflags], ~AXF_MATCH
    mov rdi, [rbx + AS_worktree]
    call mem_free
    mov qword ptr [rbx + AS_worktree], 0
    mov r12, [rbx + AS_cwd]
    test r12, r12
    jz .Lrm_yes
    cmp qword ptr [rip + g_project], 0
    je 9f
    mov [rip + match_cwd], r12
    mov qword ptr [rip + match_len], 0
    mov qword ptr [rip + match_name], 0
    xor edi, edi
    mov rsi, [rip + g_project]
    xor edx, edx
    call match_cb
    lea rdi, [rip + match_cb]
    xor esi, esi
    call git_each_agent_worktree
    cmp qword ptr [rip + match_len], 0
    je 9f
    mov rax, [rip + match_name]
    mov [rbx + AS_worktree], rax
.Lrm_yes:
    or dword ptr [rbx + AS_xflags], AXF_MATCH
9:  EPILOGUE

# match_cb(ctx, root, linked): note the root when it holds match_cwd and is longer than the last
match_cb:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov rdi, r12
    call strlen
    mov r14, rax
    test r14, r14
    jz 9f
    cmp r14, [rip + match_len]
    jbe 9f
    mov rbx, [rip + match_cwd]
    mov rdi, rbx
    call strlen
    cmp rax, r14
    jb 9f
    mov r15, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call memeq
    test eax, eax
    jz 9f
    cmp r15, r14
    je 1f
    cmp byte ptr [rbx + r14], '/'
    jne 9f
1:  mov [rip + match_len], r14
    mov rdi, [rip + match_name]
    call mem_free
    mov qword ptr [rip + match_name], 0
    test r13d, r13d
    jz 9f
    mov rdi, r12
    mov rsi, r14
    call path_basename
    mov rdi, rax
    mov rsi, rdx
    call ai_dup
    mov [rip + match_name], rax
9:  EPILOGUE

# FN agentext_rematch(): the project changed: which rows it shows
FN agentext_rematch
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + g_exts + VEC_len]
    jae 9f
    imul rdi, rbx, EXT_SIZE
    add rdi, [rip + g_exts + VEC_ptr]
    inc rbx
    call ai_ext
    mov r12, rax
    xor r13d, r13d
2:  cmp r13, [r12 + AX_rows + VEC_len]
    jae 1b
    mov rax, [r12 + AX_rows + VEC_ptr]
    mov rdi, [rax + r13*8]
    inc r13
    call row_match
    jmp 2b
9:  EPILOGUE

# ---------------- transcripts ----------------

# FN agentext_changed(ext, sid ptr, len, total, first) -> rax 0, or "CODE TEXT": the session has TOTAL
#   messages now, the first changed one at FIRST; an open conversation asks for them
FN agentext_changed
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    mov rdi, rbx
    call ai_ext
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call row_find
    test rax, rax
    jz 8f
    mov r15, rax
    mov [r15 + AS_total], r14
    mov rax, [rsp]
    cmp rax, r14
    jbe 1f
    mov rax, r14
1:  mov rcx, [r15 + AS_dirty]
    test rcx, rcx
    js 2f
    cmp rax, rcx
    jae 3f
2:  mov [r15 + AS_dirty], rax
3:  call time_ms
    mov [r15 + AS_changed], rax
    call time_now
    mov [r15 + AS_mtime], rax
    mov rdi, r15
    call agents_ext_is_open
    test eax, eax
    jz 4f
    mov rdi, r15
    call agentext_fetch
4:  mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
8:  lea rax, [rip + .Le_no_session]
    EPILOGUE

# FN agentext_open(AS*): the user opened the conversation: what it does not have yet is asked for
FN agentext_open
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rbx + AS_loaded], 1
    test dword ptr [rbx + AS_xflags], AXF_FETCHED
    jnz 1f
    mov qword ptr [rbx + AS_dirty], 0
1:  mov rdi, rbx
    call agentext_fetch
    EPILOGUE

# FN agentext_fetch(AS*): "ID agent-transcript SID FROM" when the copy is behind and nothing is asked
FN agentext_fetch
    PROLOGUE 48
    mov rbx, rdi
    cmp qword ptr [rbx + AS_req], 0
    jne 9f
    mov r12, [rbx + AS_dirty]
    test r12, r12
    js 9f
    mov r13, [rbx + AS_ext]
    FEAT_TEST r13, FEAT_AGENTS
    jz 9f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lv_transcript]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, [rbx + AS_sid]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, r12
    call sb_push_u64
    mov rdi, r13
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    xor ecx, ecx
    xor r8d, r8d
    call extproto_ai_request
    test rax, rax
    jz 9f
    mov [rbx + AS_req], rax
    mov [rbx + AS_from], r12
    mov qword ptr [rbx + AS_dirty], -1
    mov rdi, r13                # counted and timed with the language queries (query.s)
    mov rsi, rax
    mov edx, PK_TRANSCRIPT
    mov ecx, QO_AI
    call query_track
9:  EPILOGUE

# FN agentext_reply(ext, id, ok, body, len) -> eax 1 when it answered an agent-transcript request:
#   TOTAL N LF, then N messages ROLE NAME_LEN TEXT_LEN MODEL_LEN LF and the three strings
FN agentext_reply
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], edx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    test rsi, rsi
    jz 8f
    mov rdi, rbx
    call ai_ext
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, [r12 + AX_rows + VEC_len]
    jae 8f
    mov rax, [r12 + AX_rows + VEC_ptr]
    mov r14, [rax + r13*8]
    inc r13
    mov rax, [rsp]
    cmp [r14 + AS_req], rax
    jne 1b
    mov qword ptr [r14 + AS_req], 0
    cmp dword ptr [rsp + 8], 0
    je .Lar_done                # an error: the copy stays as it was
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call ai_rd_init
    call ai_rd_num
    test edx, edx
    jz .Lar_done
    mov [rsp + 32], rax         # TOTAL
    call ai_rd_num
    test edx, edx
    jz .Lar_done
    mov r15, rax                # N
    call ai_rd_eol
    test eax, eax
    jz .Lar_done
    cmp r15, AGENT_MSGS_MAX
    ja .Lar_done
    # the answer replaces the copy from FROM on
    mov rdi, r14
    mov rsi, [r14 + AS_from]
    call agents_ext_truncate
    or dword ptr [r14 + AS_xflags], AXF_FETCHED
    mov rax, [rsp + 32]
    mov [r14 + AS_total], rax
    mov qword ptr [rsp + 40], 0
2:  cmp [rsp + 40], r15
    jae 3f
    mov rdi, r14
    call one_message
    test eax, eax
    jz 3f
    inc qword ptr [rsp + 40]
    jmp 2b
3:  # more to come: the next page from where this one ended
    mov rax, [r14 + AS_from]
    add rax, [rsp + 40]
    cmp qword ptr [rsp + 40], 0
    je .Lar_done
    cmp rax, [rsp + 32]
    jae .Lar_done
    mov rcx, [r14 + AS_dirty]
    test rcx, rcx
    js 4f
    cmp rcx, rax
    jbe .Lar_done
4:  mov [r14 + AS_dirty], rax
.Lar_done:
    mov rdi, r14
    call agents_ext_is_open
    test eax, eax
    jz 5f
    mov rdi, r14
    call agentext_fetch
5:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# one_message(AS*) -> eax 1 with the next message of the answer added, 0 when it is malformed
one_message:
    PROLOGUE 48
    mov rbx, rdi
    call ai_rd_word
    mov rdi, rax
    mov rsi, rdx
    call role_of
    test eax, eax
    jz 8f
    mov [rsp], eax
    call ai_rd_num
    test edx, edx
    jz 8f
    mov r12, rax                # NAME_LEN
    call ai_rd_num
    test edx, edx
    jz 8f
    mov r13, rax                # TEXT_LEN
    call ai_rd_num
    test edx, edx
    jz 8f
    mov r14, rax                # MODEL_LEN
    call ai_rd_eol
    test eax, eax
    jz 8f
    cmp r12, AGENT_FIELD_MAX
    ja 8f
    cmp r14, AGENT_FIELD_MAX
    ja 8f
    mov rdi, r12
    call ai_rd_take
    test rax, rax
    jz 8f
    mov [rsp + 8], rax
    mov rdi, r13
    call ai_rd_take
    test rax, rax
    jz 8f
    mov [rsp + 16], rax
    mov rdi, r14
    call ai_rd_take
    test rax, rax
    jz 8f
    mov [rsp + 24], rax
    # the label: a tool's name, a reply's model, error and info say so
    xor r15d, r15d
    mov eax, [rsp]
    mov rdi, [rsp + 8]
    mov rsi, r12
    cmp eax, 2                  # assistant: its model
    jne 1f
    mov rdi, [rsp + 24]
    mov rsi, r14
1:  mov edx, AGENT_MODEL_MAX
    call ai_cut
    test rdx, rdx
    jz 2f
    mov rdi, rax
    mov rsi, rdx
    call ai_dup
    mov r15, rax
2:  mov rdi, [rsp + 16]
    mov rsi, r13
    mov edx, AGENT_TEXT_MAX
    call ai_cut
    mov rdi, rbx
    mov esi, [rsp]
    mov rcx, rdx
    mov rdx, rax
    mov r8, r15
    call agents_ext_msg
    mov rdi, r15
    call mem_free
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# role_of(ptr, len) -> eax the panel's role (1 user, 2 assistant, 3 tool, 4 result, 5 error, 6 info), 0
role_of:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 1
1:  lea rax, [rip + role_names]
    mov rdx, [rax + r13*8 - 8]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  mov eax, r13d
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- an extension that stopped ----------------

# FN ai_ext_gone(ext): an extension stopped: its sessions leave the panel, its tool calls and cards end
FN ai_ext_gone
    PROLOGUE
    mov rbx, rdi
    call agentext_gone
    mov rdi, rbx
    call tools_ext_gone
    EPILOGUE

# FN agentext_gone(ext): its rows leave the panel (the conversation shown with them closes)
FN agentext_gone
    PROLOGUE 16
    mov rbx, rdi
    call ai_ext
    mov r12, rax
    mov rax, [r12 + AX_rows + VEC_len]
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov rax, [r12 + AX_rows + VEC_ptr]
    mov [rsp + 8], rax
    mov qword ptr [r12 + AX_rows + VEC_ptr], 0
    mov qword ptr [r12 + AX_rows + VEC_len], 0
    mov qword ptr [r12 + AX_rows + VEC_cap], 0
    call agents_ext_rows
    xor r13d, r13d
1:  cmp r13, [rsp]
    jae 2f
    mov rax, [rsp + 8]
    mov rdi, [rax + r13*8]
    inc r13
    call row_free
    jmp 1b
2:  mov rdi, [rsp + 8]
    call mem_free
9:  EPILOGUE

# FN agentext_set_hidden(ext, hidden): Settings switched its sessions off or on
FN agentext_set_hidden
    PROLOGUE
    mov r12d, esi
    call ai_ext
    mov [rax + AX_hidden], r12d
    call agents_ext_rows
    EPILOGUE

# ---------------- Settings > Agents: a switch per source ----------------
# [agents] OWNER/NAME = false hides that extension's sessions. The names are kept as read, also for
# extensions not installed now, and written back with the other agents settings.

# FN agentext_config_reset(): the config file is read again
FN agentext_config_reset
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + hidden_names + VEC_len]
    jae 2f
    mov rax, [rip + hidden_names + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + hidden_names + VEC_len], 0
    EPILOGUE

# FN agentext_config_key(sec, seclen, key, keylen, val, vallen): a key config.s does not know; under
#   [agents], OWNER/NAME = false hides that source
FN agentext_config_key
    PROLOGUE 16
    mov rbx, rdx
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    lea rdx, [rip + .Ls_agents]
    call str_eq_cstr
    test eax, eax
    jz 9f
    mov rdi, rbx
    mov rsi, r12
    mov dl, '/'
    call has_byte
    test eax, eax
    jz 9f
    mov rdi, r13
    mov rsi, r14
    call parse_bool
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    call ai_dup
    mov [rsp], rax
    lea rdi, [rip + hidden_names]
    mov esi, 8
    call vec_push
    mov rcx, [rsp]
    mov [rax], rcx
    call hidden_apply
9:  EPILOGUE

# has_byte(ptr, len, dl) -> eax 1 when the byte is there
has_byte:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    cmp [rdi + rcx], dl
    je 8f
    inc rcx
    jmp 1b
8:  inc eax
9:  ret

# FN agentext_config_save(sb): the hidden sources, as lines of [agents]
FN agentext_config_save
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + hidden_names + VEC_len]
    jae 9f
    mov rax, [rip + hidden_names + VEC_ptr]
    mov rsi, [rax + rbx*8]
    inc rbx
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ls_eq_false]
    call sb_push_cstr
    jmp 1b
9:  EPILOGUE

# hidden_index(ext) -> rax the index of its name among the hidden ones, or -1
hidden_index:
    PROLOGUE
    mov rbx, rdi
    call ext_qualified
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, [rip + hidden_names + VEC_len]
    jae 8f
    mov rax, [rip + hidden_names + VEC_ptr]
    mov rdi, [rax + r13*8]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 2f
    inc r13
    jmp 1b
2:  mov rax, r13
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# ext_qualified(ext) -> "OWNER/NAME" in qual (a static buffer)
ext_qualified:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + qual]
    call sb_clear
    lea rdi, [rip + qual]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + qual]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + qual]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + qual]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + qual + SB_ptr]
    EPILOGUE

# hidden_apply(): AX_hidden of every source from the names
hidden_apply:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call ai_ext
    mov r13, rax
    cmp dword ptr [r13 + AX_agents], 0
    je 1b
    mov rdi, rbx
    call hidden_index
    xor ecx, ecx
    test rax, rax
    setns cl
    mov [r13 + AX_hidden], ecx
    jmp 1b
9:  call agents_ext_rows
    EPILOGUE

# FN agentext_hidden_load(ext): a loaded manifest that provides agents learns whether it is switched off
FN agentext_hidden_load
    PROLOGUE
    mov rbx, rdi
    call ai_ext
    mov r12, rax
    cmp dword ptr [r12 + AX_agents], 0
    je 9f
    mov rdi, rbx
    call hidden_index
    xor ecx, ecx
    test rax, rax
    setns cl
    mov [r12 + AX_hidden], ecx
9:  EPILOGUE

# toggle(ext): Settings switched the source
toggle:
    PROLOGUE 16
    mov rbx, rdi
    call hidden_index
    test rax, rax
    js 1f
    mov r12, rax                # shown again: its name goes
    mov rcx, [rip + hidden_names + VEC_ptr]
    mov rdi, [rcx + r12*8]
    call mem_free
    mov rcx, [rip + hidden_names + VEC_ptr]
    mov rdx, [rip + hidden_names + VEC_len]
    dec rdx
    mov [rip + hidden_names + VEC_len], rdx
    mov rax, [rcx + rdx*8]
    mov [rcx + r12*8], rax
    jmp 2f
1:  mov rdi, rbx
    call ext_qualified
    mov rdi, rax
    call strlen
    mov rsi, rax
    mov rdi, [rip + qual + SB_ptr]
    call ai_dup
    mov [rsp], rax
    lea rdi, [rip + hidden_names]
    mov esi, 8
    call vec_push
    mov rcx, [rsp]
    mov [rax], rcx
2:  call hidden_apply
    mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# sources_each: rbx walks the installed extensions that provide agents (r12 index); used by the two
# functions below

# FN agentext_settings_rows(x, y, w) -> eax the height of the rows: a switch per source, under the
#   built-in agents in Settings
FN agentext_settings_rows
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], esi         # y cursor
    xor r12d, r12d
.Lsrow_next:
    cmp r12, [rip + g_exts + VEC_len]
    jae .Lsrow_done
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je .Lsrow_next
    mov rdi, rbx
    call ai_ext
    mov r13, rax
    cmp dword ptr [r13 + AX_agents], 0
    je .Lsrow_next
    M r14d, MI_64
    mov edi, [rsp]
    mov esi, [rsp + 12]
    mov edx, [rsp + 8]
    mov ecx, r14d
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    COLOR eax, T_PANEL
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    mov rdi, rbx
    call agentext_title
    mov r8, rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, [rsp + 12]
    add edx, [rip + g_mt + 4*MI_10]
    M ecx, MI_24
    COLOR r9d, T_FG
    call ui_text_c
    # "Show the sessions OWNER/NAME lists in the agents panel."
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Ls_show]
    call sb_push_cstr
    mov rdi, rbx
    call ext_qualified
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Ls_lists]
    call sb_push_cstr
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_16]
    mov edx, [rsp + 12]
    add edx, [rip + g_mt + 4*MI_32]
    M ecx, MI_20
    mov r8, [rip + tmp + SB_ptr]
    mov r9, [rip + tmp + SB_len]
    COLOR r10d, T_MUTED
    mov r11d, [rsp + 8]
    sub r11d, [rip + g_mt + 4*MI_64]
    sub r11d, [rip + g_mt + 4*MI_16]
    push r11
    push r10
    call ui_text_v_fit
    add rsp, 16
    M eax, MI_14
    add eax, [rip + g_mt + 4*MI_20]
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_16]
    sub esi, eax
    mov edx, r14d
    sub edx, [rip + g_mt + 4*MI_20]
    sar edx, 1
    add edx, [rsp + 12]
    lea edi, [r12 + ID_AI_SOURCE - 1]
    xor ecx, ecx
    cmp dword ptr [r13 + AX_hidden], 0
    sete cl
    call ui_toggle
    test eax, eax
    jz 1f
    mov rdi, rbx
    call toggle
1:  add r14d, [rip + g_mt + 4*MI_8]
    add [rsp + 12], r14d
    jmp .Lsrow_next
.Lsrow_done:
    mov eax, [rsp + 12]
    sub eax, [rsp + 4]
    EPILOGUE

# FN agentext_settings_dump(sb): "agents.OWNER/NAME=true|false" per source (print-settings)
FN agentext_settings_dump
    PROLOGUE
    mov r15, rdi
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    mov rdi, rbx
    call ai_ext
    mov r13, rax
    cmp dword ptr [r13 + AX_agents], 0
    je 1b
    mov rdi, r15
    lea rsi, [rip + .Ls_agents_dot]
    call sb_push_cstr
    mov rdi, rbx
    call ext_qualified
    mov rdi, r15
    mov rsi, rax
    call sb_push_cstr
    lea rsi, [rip + .Ls_eq_true_nl]
    cmp dword ptr [r13 + AX_hidden], 0
    je 2f
    lea rsi, [rip + .Ls_eq_false_nl]
2:  mov rdi, r15
    call sb_push_cstr
    jmp 1b
9:  EPILOGUE

# FN agentext_toggle_named(name ptr, len) -> eax 1 when a source of that OWNER/NAME was switched
#   (the agents-source control command)
FN agentext_toggle_named
    PROLOGUE
    mov r13, rdi
    mov r14, rsi
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    mov rdi, rbx
    call ai_ext
    cmp dword ptr [rax + AX_agents], 0
    je 1b
    mov rdi, rbx
    call ext_qualified
    mov rdx, rax
    mov rdi, r13
    mov rsi, r14
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rdi, rbx
    call toggle
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.section .rodata
.Lk_agents: .asciz "agents"
.Ls_agents: .asciz "agents"
.Ls_agents_dot: .asciz "agents."
.Ls_eq_false: .asciz " = false\n"
.Ls_eq_true_nl: .asciz "=true\n"
.Ls_eq_false_nl: .asciz "=false\n"
.Ls_show: .asciz "Show the sessions "
.Ls_lists: .asciz " lists in the agents panel."
.Lk_agents_title: .asciz "agents.title"
.Lv_transcript: .asciz "agent-transcript "
.Le_provides: .asciz "refused the manifest does not say [provides] agents = yes"
.Le_rows_toobig: .asciz "toobig more than 1000 sessions"
.Le_rows_syntax: .asciz "syntax the sessions cannot be read"
.Le_no_session: .asciz "refused no such session"
.Ls_idle: .asciz "idle"
.Ls_working: .asciz "working"
.Ls_waiting: .asciz "waiting"
.Ls_error: .asciz "error"
.Lr_user: .asciz "user"
.Lr_assistant: .asciz "assistant"
.Lr_tool: .asciz "tool"
.Lr_result: .asciz "result"
.Lr_info: .asciz "info"
.p2align 3
state_names: .quad .Ls_idle, .Ls_working, .Ls_waiting, .Ls_error, 0
role_names: .quad .Lr_user, .Lr_assistant, .Lr_tool, .Lr_result, .Ls_error, .Lr_info, 0
.globl agentext_state_names
agentext_state_names: .quad .Ls_idle, .Ls_working, .Ls_waiting, .Ls_error

.text
# ---------------- interactive sessions (D4) ----------------

# FN agentext_ask_drop(AS*): a card open on the row is answered cancelled (D4)
FN agentext_ask_drop
    ret
