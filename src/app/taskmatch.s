# problem patterns and matchers (tasks design 3.3): a task's lines, as its terminal shows them, turned
# into problems. A pattern is a template matched against a whole line, not a regex, so it can be
# written by hand anywhere (the wire, .rhun/tasks.ini) and checked the same in every SDK:
#   {file} {line} {col} {endline} {endcol} {severity} {code} {message} {_} are fields, {{ and }} literal
#   braces; a run of spaces matches one or more blanks; every other character itself. Numbers are 1 to
#   9 digits; {file} does not start with a blank or hold "://"; {severity} is error, fatal error, fatal,
#   warning, warn, info, note, hint or help (any case); {code} and {message} 1 or more characters, {_}
#   0 or more. Fields are lazy with backtracking, at most 10000 steps per line.
# A matcher is lines: "severity S", "columns chars|bytes", "N PATTERN" for steps 1 to 4 (1 to 8
# alternatives each), "loop". Step 1 is tried on every line not taken by a step in progress; step k+1
# must match the next line; when the last one matches, a problem is made from what the steps captured.
#
#   tpat_compile(ptr, len, out CP) -> 0, or a cstr saying what is wrong
#   tpat_match(CP, line, len, caps) -> 1 and caps filled (start, length per field), or 0
#   matcher_compile(ptr, len) -> rax MT* (mem_free with matcher_free), or 0 with rdx the reason (cstr)
#   matcher_builtin(name ptr, len) -> MT* of go, gcc, rustc, tsc or msbuild (kept), or 0
#   mstate_new(MT*) -> MS*; mstate_line(MS*, line, len, emit fn, cookie): emit(cookie, MS*) for each
#   problem, its fields in the MS (MS_file, MS_msg, ... below)
#   mrun_new(source PS*, cwd cstr, TERM) -> MR*: a run's matchers (mrun_add(MR*, MT*), 4 at most); its
#   terminal's lines through mrun_tap (a term_set_tap fn) to each, problems into the source with their
#   files found from cwd (else the project); mrun_restart(MR*): a new run; mrun_free(MR*)
.include "rhun.inc"

.equ PAT_MAX, 512
.equ PAT_TOKS, 32
.equ STEP_MAX, 10000
.equ LINE_MAX, 4096
.equ MSG_MAX, 200
.equ CODE_MAX, 40
# token kinds: the fields (also the capture index), then literal and blank
.equ FK_FILE, 1
.equ FK_LINE, 2
.equ FK_COL, 3
.equ FK_ENDLINE, 4
.equ FK_ENDCOL, 5
.equ FK_SEV, 6
.equ FK_CODE, 7
.equ FK_MSG, 8
.equ FK_ANY, 9
.equ TOK_LIT, 16
.equ TOK_BLANK, 17
# a compiled pattern
.equ CP_n, 0                    # tokens
.equ CP_tok, 8                  # PAT_TOKS x (kind u16, literal offset u16, literal length u16, pad)
.equ CP_lit, 8 + 8 * PAT_TOKS   # the literal bytes, braces unescaped
.equ CP_SIZE, CP_lit + PAT_MAX
# captures: (start, length) per field 1..8, as two dwords
.equ CAPS_SIZE, 8 * 10
# a matcher
.equ MT_sev, 0                  # SEV_* for a pattern without {severity}
.equ MT_bytes, 4                # 1: {col} counts bytes, else characters
.equ MT_steps, 8
.equ MT_loop, 12
.equ MT_nalt, 16                # 4 dwords
.equ MT_alt, 32                 # 4 x 8 CP pointers
.equ MT_SIZE, 32 + 8 * 32
# a matcher's state in a run, and the problem it makes
.equ MS_mt, 0
.equ MS_step, 8                 # the step the next line must match (2.., or the last when looping), 0
.equ MS_has, 12                 # bit per field captured
.equ MS_line, 16                # numbers, 0 when not captured
.equ MS_col, 20
.equ MS_endline, 24
.equ MS_endcol, 28
.equ MS_sev, 32                 # SEV_*
.equ MS_bytes, 36               # the matcher's columns
.equ MS_codelen, 40
.equ MS_msglen, 44
.equ MS_filelen, 48
.equ MS_code, 56                # CODE_MAX bytes and a NUL
.equ MS_msg, 104                # MSG_MAX bytes and a NUL
.equ MS_file, 312               # LINE_MAX bytes and a NUL
.equ MS_SIZE, 312 + LINE_MAX + 8
# a run's matchers
.equ MR_src, 0
.equ MR_cwd, 8                  # owned
.equ MR_term, 16
.equ MR_n, 24
.equ MR_states, 32              # 4 MS*
.equ MR_SIZE, 64

.bss
.p2align 3
steps: .quad 0                  # tpat_match's step count
mline: .quad 0                  # its line and length, its pattern, its captures
mlen: .quad 0
mcp: .quad 0
mcaps: .quad 0
builtins: .zero 8 * 5           # compiled on first use
caps_tmp: .zero CAPS_SIZE

.text

# ---------------- patterns ----------------

# tpat_compile(ptr, len, out CP) -> 0, or the reason (cstr)
FN tpat_compile
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rax, [rip + .Le_length]
    test r12, r12
    jz 9f
    cmp r12, PAT_MAX
    ja 9f
    mov qword ptr [r13 + CP_n], 0
    xor r14d, r14d              # position in the pattern
    xor r15d, r15d              # literal bytes so far
    mov dword ptr [rsp], 0      # fields seen (bits)
.Lpc_next:
    cmp r14, r12
    jae .Lpc_done
    movzx eax, byte ptr [rbx + r14]
    cmp eax, 0x20
    jb .Lpc_control
    cmp eax, 0x7f
    je .Lpc_control
    cmp eax, ' '
    je .Lpc_blank
    cmp eax, '{'
    je .Lpc_open
    cmp eax, '}'
    je .Lpc_close
.Lpc_char:
    # a literal byte: onto the last token when it is literal, else a new one
    call last_literal
    test rax, rax
    jnz 1f
    mov edi, TOK_LIT
    call new_token
    test rax, rax
    jz .Lpc_toomany
    mov [rax + 2], r15w
1:  inc word ptr [rax + 4]
    movzx ecx, byte ptr [rbx + r14]
    mov [r13 + r15 + CP_lit], cl
    inc r15
    inc r14
    jmp .Lpc_next
.Lpc_blank:
    inc r14
    cmp r14, r12
    jae 2f
    cmp byte ptr [rbx + r14], ' '
    je .Lpc_blank
2:  mov edi, TOK_BLANK
    call new_token
    test rax, rax
    jz .Lpc_toomany
    jmp .Lpc_next
.Lpc_open:
    lea rax, [r14 + 1]
    cmp rax, r12
    jae .Lpc_unclosed
    cmp byte ptr [rbx + rax], '{'
    jne 3f
    inc r14                     # {{: the brace
    jmp .Lpc_char
3:  # {name}
    mov rcx, rax
4:  cmp rcx, r12
    jae .Lpc_unclosed
    cmp byte ptr [rbx + rcx], '}'
    je 5f
    inc rcx
    jmp 4b
5:  lea rdi, [rbx + rax]
    mov rsi, rcx
    sub rsi, rax
    push rcx
    push rcx
    call field_kind
    pop rcx
    pop rcx
    test eax, eax
    jz .Lpc_unknown
    lea r14, [rcx + 1]
    cmp eax, FK_ANY
    je 6f
    mov ecx, eax
    mov edx, 1
    shl edx, cl
    test [rsp], edx
    jnz .Lpc_twice
    or [rsp], edx
6:  mov edi, eax
    call new_token
    test rax, rax
    jz .Lpc_toomany
    jmp .Lpc_next
.Lpc_close:
    lea rax, [r14 + 1]
    cmp rax, r12
    jae .Lpc_lone
    cmp byte ptr [rbx + rax], '}'
    jne .Lpc_lone
    inc r14
    jmp .Lpc_char
.Lpc_done:
    xor eax, eax
9:  EPILOGUE
.Lpc_control:
    lea rax, [rip + .Le_control]
    EPILOGUE
.Lpc_unclosed:
    lea rax, [rip + .Le_unclosed]
    EPILOGUE
.Lpc_unknown:
    lea rax, [rip + .Le_unknown]
    EPILOGUE
.Lpc_twice:
    lea rax, [rip + .Le_twice]
    EPILOGUE
.Lpc_lone:
    lea rax, [rip + .Le_lone]
    EPILOGUE
.Lpc_toomany:
    lea rax, [rip + .Le_toomany]
    EPILOGUE

# tpat_new(ptr, len) -> rax a compiled pattern (mem_free it), or 0 with rdx the reason
FN tpat_new
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, CP_SIZE
    call mem_alloc
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call tpat_compile
    test rax, rax
    jnz 1f
    mov rax, r13
    EPILOGUE
1:  mov r12, rax
    mov rdi, r13
    call mem_free
    mov rdx, r12
    xor eax, eax
    EPILOGUE

# tpat_line(CP, line, len) -> 1 when the whole line matches
FN tpat_line
    lea rcx, [rip + caps_tmp]
    jmp tpat_match

# last_literal() -> the last token when it is a literal run, else 0 (r13 CP)
last_literal:
    mov rcx, [r13 + CP_n]
    test rcx, rcx
    jz 1f
    lea rax, [r13 + rcx*8 + CP_tok - 8]
    cmp word ptr [rax], TOK_LIT
    jne 1f
    ret
1:  xor eax, eax
    ret

# new_token(kind) -> the token, or 0 past PAT_TOKS (r13 CP)
new_token:
    mov rcx, [r13 + CP_n]
    cmp rcx, PAT_TOKS
    jae 1f
    lea rax, [r13 + rcx*8 + CP_tok]
    mov [rax], di
    mov word ptr [rax + 2], 0
    mov word ptr [rax + 4], 0
    mov word ptr [rax + 6], 0
    inc qword ptr [r13 + CP_n]
    ret
1:  xor eax, eax
    ret

# field_kind(name, len) -> FK_*, or 0 for a name that is not a field
field_kind:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + field_names]
    mov ecx, 1
1:  mov rdx, [r13]
    test rdx, rdx
    jz 8f
    push rcx
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    pop rcx
    test eax, eax
    jnz 2f
    add r13, 8
    inc ecx
    jmp 1b
2:  mov eax, ecx
    jmp 9f
8:  xor eax, eax
9:  pop r13
    pop r12
    pop rbx
    ret

# tpat_match(CP, line, len, caps) -> 1 when the whole line matches, caps filled; 0
FN tpat_match
    PROLOGUE
    mov [rip + mcp], rdi
    mov [rip + mline], rsi
    mov [rip + mlen], rdx
    mov [rip + mcaps], rcx
    mov qword ptr [rip + steps], 0
    mov rdi, rcx
    xor esi, esi
    mov edx, CAPS_SIZE
    call memset
    xor edi, edi
    xor esi, esi
    call match_from
    EPILOGUE

# match_from(token, pos) -> 1 when tokens [token, n) match the line from pos to its end
match_from:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    inc qword ptr [rip + steps]
    cmp qword ptr [rip + steps], STEP_MAX
    ja .Lmf_no
    mov r13, [rip + mcp]
    cmp rbx, [r13 + CP_n]
    jne 1f
    cmp r12, [rip + mlen]
    jne .Lmf_no
    jmp .Lmf_yes
1:  lea r14, [r13 + rbx*8 + CP_tok]
    movzx eax, word ptr [r14]
    mov r15, [rip + mline]
    cmp eax, TOK_LIT
    je .Lmf_lit
    cmp eax, TOK_BLANK
    je .Lmf_blank
    # a field: which lengths it may take, shortest first
    mov ecx, eax
    cmp ecx, FK_SEV
    je .Lmf_sev
    cmp ecx, FK_LINE
    jb .Lmf_text
    cmp ecx, FK_ENDCOL
    jbe .Lmf_number
.Lmf_text:
    # {file}, {code}, {message}: 1 or more; {_}: 0 or more
    mov r13d, 1
    cmp ecx, FK_ANY
    jne 2f
    xor r13d, r13d
2:  cmp ecx, FK_FILE
    jne .Lmf_len
    # {file}: not from a blank
    cmp r12, [rip + mlen]
    jae .Lmf_no
    movzx eax, byte ptr [r15 + r12]
    cmp eax, ' '
    je .Lmf_no
    cmp eax, 9
    je .Lmf_no
.Lmf_len:
    # take r13 bytes, then one more each time the rest does not match
    lea rax, [r12 + r13]
    cmp rax, [rip + mlen]
    ja .Lmf_no
    movzx ecx, word ptr [r14]
    cmp ecx, FK_FILE
    jne 3f
    cmp r13, 3                  # {file} holds no "://"
    jb 3f
    cmp byte ptr [r15 + rax - 3], ':'
    jne 3f
    cmp byte ptr [r15 + rax - 2], '/'
    jne 3f
    cmp byte ptr [r15 + rax - 1], '/'
    je .Lmf_no
3:  mov edi, ecx
    mov rsi, r12
    mov rdx, r13
    call capture
    lea rdi, [rbx + 1]
    lea rsi, [r12 + r13]
    call match_from
    test eax, eax
    jnz .Lmf_yes
    cmp qword ptr [rip + steps], STEP_MAX
    ja .Lmf_no
    inc r13
    jmp .Lmf_len
.Lmf_number:
    # 1 to 9 digits
    mov r13d, 1
4:  lea rax, [r12 + r13]
    cmp rax, [rip + mlen]
    ja .Lmf_no
    cmp r13, 9
    ja .Lmf_no
    movzx edx, byte ptr [r15 + rax - 1]
    sub edx, '0'
    cmp edx, 9
    ja .Lmf_no
    movzx edi, word ptr [r14]
    mov rsi, r12
    mov rdx, r13
    call capture
    lea rdi, [rbx + 1]
    lea rsi, [r12 + r13]
    call match_from
    test eax, eax
    jnz .Lmf_yes
    cmp qword ptr [rip + steps], STEP_MAX
    ja .Lmf_no
    inc r13
    jmp 4b
.Lmf_sev:
    # each severity word, in any case
    lea r13, [rip + sev_words]
5:  mov rdi, [r13]
    test rdi, rdi
    jz .Lmf_no
    call strlen
    mov rcx, rax
    lea rax, [r12 + rcx]
    cmp rax, [rip + mlen]
    ja 6f
    push rcx
    push rcx
    lea rdi, [r15 + r12]
    mov rsi, rcx
    mov rdx, [r13]
    call str_ieq_cstr
    pop rcx
    pop rcx
    test eax, eax
    jz 6f
    push rcx
    push rcx
    mov edi, FK_SEV
    mov rsi, r12
    mov rdx, rcx
    call capture
    pop rcx
    pop rcx
    lea rdi, [rbx + 1]
    lea rsi, [r12 + rcx]
    call match_from
    test eax, eax
    jnz .Lmf_yes
6:  add r13, 16
    jmp 5b
.Lmf_lit:
    movzx ecx, word ptr [r14 + 4]
    lea rax, [r12 + rcx]
    cmp rax, [rip + mlen]
    ja .Lmf_no
    movzx esi, word ptr [r14 + 2]
    lea rsi, [r13 + rsi + CP_lit]
    lea rdi, [r15 + r12]
    mov rdx, rcx
    push rcx
    push rcx
    call memeq
    pop rcx
    pop rcx
    test eax, eax
    jz .Lmf_no
    lea rdi, [rbx + 1]
    lea rsi, [r12 + rcx]
    call match_from
    EPILOGUE
.Lmf_blank:
    # one or more spaces or tabs, the fewest first
    mov r13, r12
7:  cmp r13, [rip + mlen]
    jae .Lmf_no
    movzx eax, byte ptr [r15 + r13]
    cmp eax, ' '
    je 8f
    cmp eax, 9
    jne .Lmf_no
8:  inc r13
    lea rdi, [rbx + 1]
    mov rsi, r13
    call match_from
    test eax, eax
    jnz .Lmf_yes
    cmp qword ptr [rip + steps], STEP_MAX
    ja .Lmf_no
    jmp 7b
.Lmf_yes:
    mov eax, 1
    EPILOGUE
.Lmf_no:
    xor eax, eax
    EPILOGUE

# capture(field, start, length): the field's place in the line (not {_})
capture:
    cmp edi, FK_ANY
    jae 1f
    mov rax, [rip + mcaps]
    mov [rax + rdi*8], esi
    mov [rax + rdi*8 + 4], edx
1:  ret

# str_ieq_cstr(ptr, len, lowercase cstr) -> 1 when the bytes are the word in any case
str_ieq_cstr:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 3f
    movzx eax, byte ptr [rdi + rcx]
    lea r8d, [rax - 'A']
    cmp r8d, 25
    ja 2f
    add eax, 32
2:  movzx r8d, byte ptr [rdx + rcx]
    test r8d, r8d
    jz 8f
    cmp eax, r8d
    jne 8f
    inc rcx
    jmp 1b
3:  cmp byte ptr [rdx + rcx], 0
    jne 8f
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ---------------- matchers ----------------

# matcher_compile(ptr, len) -> rax MT*, or 0 with rdx the reason
FN matcher_compile
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    lea rax, [rip + .Le_mlength]
    cmp r12, 4096
    ja .Lmc_err
    mov edi, MT_SIZE
    call mem_alloc
    mov r13, rax
    mov dword ptr [r13 + MT_sev], SEV_ERROR
    lea r14, [rbx + r12]        # end
.Lmc_line:
    cmp rbx, r14
    jae .Lmc_end
    mov r15, rbx
1:  cmp r15, r14
    jae 2f
    cmp byte ptr [r15], 10
    je 2f
    inc r15
    jmp 1b
2:  mov [rsp], r15              # the line is [rbx, r15)
    mov rdi, rbx
    mov rsi, r15
    sub rsi, rbx
    call matcher_line_parse
    test rax, rax
    jnz .Lmc_bad
    mov rbx, [rsp]
    inc rbx
    jmp .Lmc_line
.Lmc_end:
    lea rax, [rip + .Le_nosteps]
    cmp dword ptr [r13 + MT_steps], 0
    je .Lmc_bad
    mov rax, r13
    EPILOGUE
.Lmc_bad:
    mov [rsp + 8], rax
    mov rdi, r13
    call matcher_free
    mov rax, [rsp + 8]
.Lmc_err:
    mov rdx, rax
    xor eax, eax
    EPILOGUE

# matcher_line_parse(ptr, len) -> 0, or the reason (r13 MT being built)
matcher_line_parse:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    # a CR before the LF and trailing blanks are not part of it; an empty line is nothing
    mov rdi, rbx
    mov rsi, r12
    call trim
    mov rbx, rax
    mov r12, rdx
    test r12, r12
    jz .Lml_ok
    mov rdi, rbx
    mov rsi, r12
    call next_word
    mov r14, rax
    mov r15, rdx
    mov [rsp], rcx              # past the word
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + .Lw_loop]
    call str_eq_cstr
    test eax, eax
    jz 1f
    cmp r15, r12
    jne .Lml_bad
    mov dword ptr [r13 + MT_loop], 1
    jmp .Lml_ok
1:  # the rest after one blank
    mov rcx, [rsp]
    cmp rcx, r12
    jae .Lml_bad
    lea rax, [rbx + rcx + 1]
    mov [rsp + 8], rax
    mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + .Lw_severity]
    call str_eq_cstr
    test eax, eax
    jz 2f
    mov rdi, [rsp + 8]
    lea rsi, [rbx + r12]
    sub rsi, rdi
    call severity_word
    test eax, eax
    js .Lml_bad
    mov [r13 + MT_sev], eax
    jmp .Lml_ok
2:  mov rdi, r14
    mov rsi, r15
    lea rdx, [rip + .Lw_columns]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov rdi, [rsp + 8]
    lea rsi, [rbx + r12]
    sub rsi, rdi
    lea rdx, [rip + .Lw_bytes]
    call str_eq_cstr
    test eax, eax
    jz 21f
    mov dword ptr [r13 + MT_bytes], 1
    jmp .Lml_ok
21: mov rdi, [rsp + 8]
    lea rsi, [rbx + r12]
    sub rsi, rdi
    lea rdx, [rip + .Lw_chars]
    call str_eq_cstr
    test eax, eax
    jz .Lml_bad
    mov dword ptr [r13 + MT_bytes], 0
    jmp .Lml_ok
3:  # N PATTERN: N is the current step or the next
    cmp r15, 1
    jne .Lml_bad
    movzx eax, byte ptr [r14]
    sub eax, '0'
    cmp eax, 1
    jb .Lml_bad
    cmp eax, 4
    ja .Lml_bad
    mov ecx, [r13 + MT_steps]
    cmp eax, ecx
    je 4f
    inc ecx
    cmp eax, ecx
    jne .Lml_order
    mov [r13 + MT_steps], eax
4:  lea r15, [rax - 1]          # step index
    mov ecx, [r13 + MT_nalt + r15*4]
    cmp ecx, 8
    jae .Lml_alts
    mov edi, CP_SIZE
    call mem_alloc
    mov r14, rax
    mov ecx, [r13 + MT_nalt + r15*4]
    lea rdx, [r15*8]
    lea rdx, [rdx + rcx]
    mov [r13 + rdx*8 + MT_alt], r14
    inc dword ptr [r13 + MT_nalt + r15*4]
    # the pattern: everything after "N "
    mov rdi, [rsp + 8]
    lea rsi, [rbx + r12]
    sub rsi, rdi
    mov rdx, r14
    call tpat_compile
    test rax, rax
    jnz 9f
.Lml_ok:
    xor eax, eax
9:  EPILOGUE
.Lml_bad:
    lea rax, [rip + .Le_mline]
    EPILOGUE
.Lml_order:
    lea rax, [rip + .Le_order]
    EPILOGUE
.Lml_alts:
    lea rax, [rip + .Le_alts]
    EPILOGUE

# severity_word(ptr, len) -> SEV_* for error, warning, info or hint; -1
severity_word:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + sev_names]
    xor ecx, ecx
1:  mov rdx, [r13 + rcx*8]
    test rdx, rdx
    jz 8f
    push rcx
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    pop rcx
    test eax, eax
    jnz 2f
    inc ecx
    jmp 1b
2:  mov eax, ecx
    jmp 9f
8:  mov eax, -1
9:  pop r13
    pop r12
    pop rbx
    ret

# matcher_free(MT*)
FN matcher_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  mov rdi, [rbx + r12*8 + MT_alt]
    call mem_free
    inc r12
    cmp r12, 32
    jb 1b
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# matcher_builtin(name, len) -> the built-in matcher's MT* (compiled once, kept), or 0
FN matcher_builtin
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, 5
    jae 8f
    lea rax, [rip + builtin_names]
    mov rdx, [rax + r13*8]
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13
    jmp 1b
2:  lea rax, [rip + builtins]
    mov rcx, [rax + r13*8]
    test rcx, rcx
    jnz 3f
    lea rax, [rip + builtin_texts]
    mov rdi, [rax + r13*8]
    push rdi
    push rdi
    call strlen
    pop rdi
    pop rdi
    mov rsi, rax
    call matcher_compile
    lea rcx, [rip + builtins]
    mov [rcx + r13*8], rax
    mov rcx, rax
3:  mov rax, rcx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- a matcher in a run ----------------

# mstate_new(MT*) -> MS* (mem_free it)
FN mstate_new
    push rbx
    mov rbx, rdi
    mov edi, MS_SIZE
    call mem_alloc
    mov [rax + MS_mt], rbx
    pop rbx
    ret

# mstate_line(MS*, line, len, emit, cookie): the next line for this matcher; emit(cookie, MS*) for each
#   problem it completes
FN mstate_line
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    cmp r13, LINE_MAX
    jbe 1f
    mov r13d, LINE_MAX
1:  mov r15, [rbx + MS_mt]
    mov eax, [rbx + MS_step]
    test eax, eax
    jz .Lsl_first
    # a step in progress: this line must match it
    lea edi, [rax - 1]
    call try_step
    test eax, eax
    jz 3f
    mov eax, [rbx + MS_step]
    cmp eax, [r15 + MT_steps]
    jb 2f
    call emit
    mov dword ptr [rbx + MS_step], 0
    cmp dword ptr [r15 + MT_loop], 0
    je 9f
    mov eax, [r15 + MT_steps]
    mov [rbx + MS_step], eax    # the last step again on the next line
    jmp 9f
2:  inc dword ptr [rbx + MS_step]
    jmp 9f
3:  mov dword ptr [rbx + MS_step], 0
.Lsl_first:
    mov dword ptr [rbx + MS_has], 0
    xor edi, edi
    call try_step
    test eax, eax
    jz 9f
    cmp dword ptr [r15 + MT_steps], 1
    ja 4f
    call emit
    jmp 9f
4:  mov dword ptr [rbx + MS_step], 2
9:  EPILOGUE

# try_step(step index) -> 1 when an alternative of the step matched the line (its fields taken into
#   the state), else 0 (mstate_line's registers)
try_step:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi                    # alternative
    mov qword ptr [rbp - 16], 0
1:  mov rdi, [rbp - 8]
    mov ecx, [r15 + MT_nalt + rdi*4]
    mov rax, [rbp - 16]
    cmp rax, rcx
    jae 8f
    lea rdx, [rdi*8]
    add rdx, rax
    mov rdi, [r15 + rdx*8 + MT_alt]
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rip + caps_tmp]
    call tpat_match
    test eax, eax
    jnz 2f
    inc qword ptr [rbp - 16]
    jmp 1b
2:  call take_fields
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  mov rsp, rbp
    pop rbp
    ret

# take_fields(): caps_tmp's fields of the line into the state (a later step's replace an earlier's)
take_fields:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    lea r8, [rip + caps_tmp]
    mov ecx, FK_FILE
1:  mov eax, [r8 + rcx*8 + 4]   # length
    test eax, eax
    jz 7f
    mov edx, 1
    shl edx, cl
    or [rbx + MS_has], edx
    mov esi, [r8 + rcx*8]
    lea rsi, [r12 + rsi]        # its bytes
    cmp ecx, FK_FILE
    jne 2f
    lea rdi, [rbx + MS_file]
    mov edx, LINE_MAX
    call take_text
    mov [rbx + MS_filelen], eax
    jmp 7f
2:  cmp ecx, FK_MSG
    jne 3f
    lea rdi, [rbx + MS_msg]
    mov edx, MSG_MAX
    call take_text
    mov [rbx + MS_msglen], eax
    jmp 7f
3:  cmp ecx, FK_CODE
    jne 4f
    lea rdi, [rbx + MS_code]
    mov edx, CODE_MAX
    call take_text
    mov [rbx + MS_codelen], eax
    jmp 7f
4:  cmp ecx, FK_SEV
    jne 5f
    # the word's severity: error, fatal error, fatal; warning, warn; info, note; hint, help
    push rcx
    push r8
    lea r12, [rip + sev_words]
41: mov rdx, [r12]
    test rdx, rdx
    jz 43f
    push rax
    push rsi
    mov rdi, rsi
    mov rsi, rax
    call str_ieq_cstr
    mov r9d, eax
    pop rsi
    pop rax
    test r9d, r9d
    jnz 42f
    add r12, 16
    jmp 41b
42: mov eax, [r12 + 8]
    mov [rbx + MS_sev], eax
43: pop r8
    pop rcx
    mov r12, [rbp - 16]         # the line again
    jmp 7f
5:  # a number: line, col, endline, endcol (1 to 9 digits)
    xor edx, edx
    xor edi, edi
6:  cmp edi, eax
    jae 61f
    movzx r9d, byte ptr [rsi + rdi]
    sub r9d, '0'
    imul edx, edx, 10
    add edx, r9d
    inc edi
    jmp 6b
61: lea r9, [rip + number_slots]
    mov r9d, [r9 + rcx*4]
    mov [rbx + r9], edx
7:  inc ecx
    cmp ecx, FK_MSG
    jbe 1b
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# take_text(dst, src, max, length eax) -> eax bytes kept: at most max, cut on a character's start, and a
#   NUL; keeps rcx, r8
take_text:
    mov r9d, eax
    cmp r9d, edx
    jbe 2f
    mov r9d, edx
1:  test r9d, r9d               # back to a character's start
    jz 2f
    movzx r10d, byte ptr [rsi + r9]
    and r10d, 0xc0
    cmp r10d, 0x80
    jne 2f
    dec r9d
    jmp 1b
2:  xor r10d, r10d
3:  cmp r10d, r9d
    jae 4f
    mov r11b, [rsi + r10]
    mov [rdi + r10], r11b
    inc r10d
    jmp 3b
4:  mov byte ptr [rdi + r10], 0
    mov eax, r9d
    ret

# emit(): the steps are done: a problem when a file and a message were captured (mstate_line's
#   registers; the severity of a pattern without one is the matcher's)
emit:
    push rbp
    mov rbp, rsp
    mov eax, [rbx + MS_has]
    and eax, (1 << FK_FILE) | (1 << FK_MSG)
    cmp eax, (1 << FK_FILE) | (1 << FK_MSG)
    jne 9f
    test dword ptr [rbx + MS_has], 1 << FK_SEV
    jnz 1f
    mov eax, [r15 + MT_sev]
    mov [rbx + MS_sev], eax
1:  mov eax, [r15 + MT_bytes]
    mov [rbx + MS_bytes], eax
    # numbers not captured are 0, a code not captured empty
    xor eax, eax
    test dword ptr [rbx + MS_has], 1 << FK_LINE
    jnz 2f
    mov [rbx + MS_line], eax
2:  test dword ptr [rbx + MS_has], 1 << FK_COL
    jnz 3f
    mov [rbx + MS_col], eax
3:  test dword ptr [rbx + MS_has], 1 << FK_ENDLINE
    jnz 4f
    mov [rbx + MS_endline], eax
4:  test dword ptr [rbx + MS_has], 1 << FK_ENDCOL
    jnz 5f
    mov [rbx + MS_endcol], eax
5:  test dword ptr [rbx + MS_has], 1 << FK_CODE
    jnz 6f
    mov [rbx + MS_codelen], eax
    mov byte ptr [rbx + MS_code], 0
6:  test r14, r14
    jz 9f
    mov rdi, [rbp + 16]         # the cookie, at mstate_line's [rsp]
    mov rsi, rbx
    call r14
9:  mov rsp, rbp
    pop rbp
    ret

# ---------------- a run's matchers ----------------

# mrun_new(source, cwd, TERM) -> MR*
FN mrun_new
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov edi, MR_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + MR_src], r12
    mov [rbx + MR_term], r14
    mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    call mem_dup
    mov [rbx + MR_cwd], rax
    mov rax, rbx
    EPILOGUE

# mrun_counts(MR*) -> eax errors, edx warnings of its run so far
FN mrun_counts
    mov rdi, [rdi + MR_src]
    test rdi, rdi
    jz 1f
    jmp problems_counts
1:  xor eax, eax
    xor edx, edx
    ret

# mrun_bind(MR*, source, TERM): where its problems go and whose footer counts them (made before both)
FN mrun_bind
    mov [rdi + MR_src], rsi
    mov [rdi + MR_term], rdx
    ret

# mrun_add(MR*, MT*) -> 1, or 0 with 4 already
FN mrun_add
    push rbx
    mov rbx, rdi
    xor eax, eax
    cmp dword ptr [rbx + MR_n], 4
    jae 9f
    mov rdi, rsi
    call mstate_new
    mov ecx, [rbx + MR_n]
    mov [rbx + rcx*8 + MR_states], rax
    inc dword ptr [rbx + MR_n]
    mov eax, 1
9:  pop rbx
    ret

# mrun_restart(MR*): a new run: the source's problems go, every matcher starts over
FN mrun_restart
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + MR_src]
    call problems_clear
    xor ecx, ecx
1:  cmp ecx, [rbx + MR_n]
    jae 9f
    mov rax, [rbx + rcx*8 + MR_states]
    mov dword ptr [rax + MS_step], 0
    inc ecx
    jmp 1b
9:  pop rbx
    ret

# mrun_free(MR*)
FN mrun_free
    push rbx
    push r12
    push r13
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  cmp r12d, [rbx + MR_n]
    jae 2f
    mov rdi, [rbx + r12*8 + MR_states]
    call mem_free
    inc r12d
    jmp 1b
2:  mov rdi, [rbx + MR_cwd]
    call mem_free
    mov rdi, rbx
    call mem_free
9:  pop r13
    pop r12
    pop rbx
    ret

# mrun_tap(MR*, TERM, line, len): a finished line of the run's terminal, to every matcher; len -1: the
#   program starts again (mrun_restart)
FN mrun_tap
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    cmp r13, -1
    jne 1f
    call mrun_restart
    EPILOGUE
1:  xor r14d, r14d
2:  cmp r14d, [rbx + MR_n]
    jae 9f
    mov rdi, [rbx + r14*8 + MR_states]
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rip + mrun_emit]
    mov r8, rbx
    call mstate_line
    inc r14d
    jmp 2b
9:  EPILOGUE

# mrun_emit(MR*, MS*): a problem: its file found, then into the store; the terminal's footer counts
mrun_emit:
    PROLOGUE 80
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [r12 + MS_file]
    mov rsi, [rbx + MR_cwd]
    call find_file
    mov r13, rax                # owned
    mov [rsp + PR_path], rax
    mov eax, [r12 + MS_line]
    mov [rsp + PR_line], eax
    mov eax, [r12 + MS_col]
    mov [rsp + PR_col], eax
    mov eax, [r12 + MS_endline]
    mov [rsp + PR_endline], eax
    mov eax, [r12 + MS_endcol]
    mov [rsp + PR_endcol], eax
    mov eax, [r12 + MS_sev]
    mov [rsp + PR_sev], eax
    xor eax, eax
    cmp dword ptr [r12 + MS_bytes], 0
    jne 1f
    mov eax, PRF_CHARS
1:  mov [rsp + PR_flags], eax
    lea rax, [r12 + MS_msg]
    mov [rsp + PR_msg], rax
    lea rax, [r12 + MS_code]
    mov [rsp + PR_code], rax
    mov rdi, [rbx + MR_src]
    lea rsi, [rsp]
    call problems_add
    mov rdi, r13
    call mem_free
    mov rdi, [rbx + MR_src]
    call problems_counts
    mov rdi, [rbx + MR_term]
    mov esi, eax
    call term_set_problems
    EPILOGUE

# find_file(name, cwd) -> owned absolute path: an absolute name as it is, ~/ in the home folder, else
#   from cwd when it is there, from the project when it is there, else from cwd; "." and ".." taken out
find_file:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call path_rootlen
    test eax, eax
    jz 1f
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    jmp 8f
1:  cmp byte ptr [rbx], '~'
    jne 2f
    cmp byte ptr [rbx + 1], '/'
    jne 2f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 2f
    mov rdi, rax
    lea rsi, [rbx + 2]
    call path_join
    jmp 8f
2:  mov rdi, r12
    mov rsi, rbx
    call path_join
    mov r13, rax
    mov rdi, rax
    call path_normalize
    mov rdi, r13
    call file_type
    test eax, eax
    jnz 7f
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 7f
    mov rsi, rbx
    call path_join
    mov r14, rax
    mov rdi, rax
    call path_normalize
    mov rdi, r14
    call file_type
    test eax, eax
    jz 6f
    mov rdi, r13
    call mem_free
    mov rax, r14
    EPILOGUE
6:  mov rdi, r14
    call mem_free
7:  mov rax, r13
    EPILOGUE
8:  mov r13, rax
    mov rdi, rax
    call path_normalize
    mov rax, r13
    EPILOGUE

# ---------------- for the tests ----------------

# tpat_dump(text, len, sb): "PATTERN<TAB>LINE" -> "match=0", "match=1 file=... line=..." or
#   "error=REASON" (print-pattern)
FN tpat_dump
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor ecx, ecx
1:  cmp rcx, r12
    jae 8f
    cmp byte ptr [rbx + rcx], 9
    je 2f
    inc rcx
    jmp 1b
2:  mov r14, rcx
    mov edi, CP_SIZE
    call mem_alloc
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call tpat_compile
    test rax, rax
    jnz 7f
    lea rsi, [rbx + r14 + 1]
    mov rdx, r12
    sub rdx, r14
    dec rdx
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov rdi, r15
    lea rcx, [rip + caps_tmp]
    call tpat_match
    test eax, eax
    jnz 3f
    mov rdi, r13
    lea rsi, [rip + .Ld_nomatch]
    call sb_push_cstr
    jmp 6f
3:  mov rdi, r13
    lea rsi, [rip + .Ld_match]
    call sb_push_cstr
    mov r14d, FK_FILE
4:  lea rax, [rip + caps_tmp]
    mov ecx, [rax + r14*8 + 4]
    test ecx, ecx
    jz 5f
    mov rdi, r13
    mov esi, ' '
    call sb_push_byte
    lea rax, [rip + field_names]
    mov rsi, [rax + r14*8 - 8]
    mov rdi, r13
    call sb_push_cstr
    mov rdi, r13
    mov esi, '='
    call sb_push_byte
    lea rax, [rip + caps_tmp]
    mov esi, [rax + r14*8]
    mov edx, [rax + r14*8 + 4]
    add rsi, [rsp]
    mov rdi, r13
    call sb_push
5:  inc r14d
    cmp r14d, FK_MSG
    jbe 4b
6:  mov rdi, r13
    mov esi, 10
    call sb_push_byte
    mov rdi, r15
    call mem_free
    EPILOGUE
7:  mov [rsp], rax
    mov rdi, r13
    lea rsi, [rip + .Ld_error]
    call sb_push_cstr
    mov rdi, r13
    mov rsi, [rsp]
    call sb_push_cstr
    mov rdi, r13
    mov esi, 10
    call sb_push_byte
    mov rdi, r15
    call mem_free
    EPILOGUE
8:  mov rdi, r13
    lea rsi, [rip + .Ld_notab]
    call sb_push_cstr
    EPILOGUE

.section .rodata
.Le_length: .asciz "a pattern is 1 to 512 bytes"
.Le_control: .asciz "a pattern is one line of text"
.Le_unclosed: .asciz "{ without }"
.Le_unknown: .asciz "unknown field"
.Le_twice: .asciz "a field twice"
.Le_lone: .asciz "a } alone (write }})"
.Le_toomany: .asciz "more than 32 parts"
.Le_mlength: .asciz "a matcher is at most 4096 bytes"
.Le_mline: .asciz "a matcher line is severity S, columns chars|bytes, N PATTERN or loop"
.Le_order: .asciz "steps go 1, 2, 3, 4 in order"
.Le_alts: .asciz "more than 8 patterns in a step"
.Le_nosteps: .asciz "a matcher needs a step 1 pattern"
.Lw_loop: .asciz "loop"
.Lw_severity: .asciz "severity"
.Lw_columns: .asciz "columns"
.Lw_bytes: .asciz "bytes"
.Lw_chars: .asciz "chars"
.Lf_file: .asciz "file"
.Lf_line: .asciz "line"
.Lf_col: .asciz "col"
.Lf_endline: .asciz "endline"
.Lf_endcol: .asciz "endcol"
.Lf_severity: .asciz "severity"
.Lf_code: .asciz "code"
.Lf_message: .asciz "message"
.Lf_any: .asciz "_"
.Ls_error: .asciz "error"
.Ls_fatal_error: .asciz "fatal error"
.Ls_fatal: .asciz "fatal"
.Ls_warning: .asciz "warning"
.Ls_warn: .asciz "warn"
.Ls_info: .asciz "info"
.Ls_note: .asciz "note"
.Ls_hint: .asciz "hint"
.Ls_help: .asciz "help"
.Ld_match: .asciz "match=1"
.Lhome: .asciz "HOME"
.Ld_nomatch: .asciz "match=0"
.Ld_error: .asciz "error="
.Ld_notab: .asciz "error=PATTERN<TAB>LINE\n"
# the built-in matchers (tasks design 3.3)
.Lb_go: .asciz "go"
.Lb_gcc: .asciz "gcc"
.Lb_rustc: .asciz "rustc"
.Lb_tsc: .asciz "tsc"
.Lb_msbuild: .asciz "msbuild"
# (vet's first: a file may hold spaces, so the general one would take "vet: a.go" as the file)
.Lt_go: .ascii "columns bytes\n1 vet: {file}:{line}:{col}: {message}\n1 {file}:{line}:{col}: {message}\n"
        .asciz "1  {file}:{line}: {message}\n"
# (clang counts columns in bytes, as GCC can: -fdiagnostics-column-unit=byte)
.Lt_gcc: .asciz "columns bytes\n1 {file}:{line}:{col}: {severity}: {message}\n1 {file}:{line}: {severity}: {message}\n"
.Lt_rustc: .asciz "1 {severity}[{code}]: {message}\n1 {severity}: {message}\n2  --> {file}:{line}:{col}\n"
.Lt_tsc: .ascii "1 {file}({line},{col}): {severity} {code}: {message}\n"
         .asciz "1 {file}:{line}:{col} - {severity} {code}: {message}\n"
.Lt_msbuild: .ascii "1 {file}({line},{col}): {severity} {code}: {message}\n"
             .asciz "1 {file}({line},{col},{endline},{endcol}): {severity} {code}: {message}\n"
.p2align 3
field_names: .quad .Lf_file, .Lf_line, .Lf_col, .Lf_endline, .Lf_endcol, .Lf_severity, .Lf_code
             .quad .Lf_message, .Lf_any, 0
# word, SEV_*: the longer words before the ones they start with
sev_words: .quad .Ls_fatal_error, SEV_ERROR, .Ls_error, SEV_ERROR, .Ls_fatal, SEV_ERROR
           .quad .Ls_warning, SEV_WARNING, .Ls_warn, SEV_WARNING, .Ls_info, SEV_INFO
           .quad .Ls_note, SEV_INFO, .Ls_hint, SEV_HINT, .Ls_help, SEV_HINT, 0, 0
sev_names: .quad .Ls_error, .Ls_warning, .Ls_info, .Ls_hint, 0
builtin_names: .quad .Lb_go, .Lb_gcc, .Lb_rustc, .Lb_tsc, .Lb_msbuild
builtin_texts: .quad .Lt_go, .Lt_gcc, .Lt_rustc, .Lt_tsc, .Lt_msbuild
# the state's field for each number field (index FK_*)
number_slots: .long 0, 0, MS_line, MS_col, MS_endline, MS_endcol, 0, 0, 0
