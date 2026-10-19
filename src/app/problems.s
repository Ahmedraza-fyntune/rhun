# the Problems store: problems in any file, from any source (DECISIONS.md: the tasks group owns it;
# language features adds extensions' file-diagnostics to it). A source is an opaque record: a task
# run's matchers, a term-run with --matcher. A problem: absolute path, line and column (bytes, or
# characters when its matcher counts them so), an optional exclusive end, severity, message, code.
# Open documents show them as marks (extmarks.s: gutter dot, underline, tooltip, status counts); a
# file opened later gets its marks then, from the problem's line and column.
#
#   problems_source(key cstr, label cstr) -> PS*: the source with that key, made when new (kept)
#   problems_clear(PS*)            its problems go, and their marks
#   problems_add(PS*, PR*) -> 1 kept, 0 a duplicate of one of its own or past the caps (2000 per
#                                  source, 10000 in all): PR's strings are copied
#   problems_tick()                documents opened since get the marks of their problems
#   problems_dump(sb)              print-problems
.include "rhun.inc"

.equ PER_SOURCE, 2000
.equ ALL_MAX, 10000

.bss
.p2align 3
sources: .zero VEC_SIZE         # PS*
probs: .zero VEC_SIZE           # PR records, in the order they came
last_doc: .quad 0               # the newest DOC_id problems_tick has seen
doc_tmp: .zero 4096

.text

# problems_source(key, label) -> PS*
FN problems_source
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, [rip + sources + VEC_len]
    jae 2f
    mov rax, [rip + sources + VEC_ptr]
    mov r14, [rax + rbx*8]
    inc rbx
    mov rdi, [r14 + PS_key]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r14
    EPILOGUE
2:  mov edi, PS_SIZE
    call mem_alloc
    mov r14, rax
    mov rdi, r12
    call dup
    mov [r14 + PS_key], rax
    mov rdi, r13
    call dup
    mov [r14 + PS_label], rax
    lea rdi, [rip + sources]
    mov esi, 8
    call vec_push
    mov [rax], r14
    mov rax, r14
    EPILOGUE

# dup(cstr) -> an owned copy ("" for 0)
dup:
    push rbx
    mov rbx, rdi
    test rbx, rbx
    jnz 1f
    lea rbx, [rip + .Lempty]
1:  mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    pop rbx
    ret

# problems_clear(PS*): its problems and their marks go
FN problems_clear
    PROLOGUE
    mov r12, rdi
    mov rbx, [rip + probs + VEC_len]
1:  test rbx, rbx
    jz 2f
    dec rbx
    imul r13, rbx, PR_SIZE
    add r13, [rip + probs + VEC_ptr]
    cmp [r13 + PR_src], r12
    jne 1b
    mov rdi, [r13 + PR_path]
    call mem_free
    mov rdi, [r13 + PR_msg]
    call mem_free
    mov rdi, [r13 + PR_code]
    call mem_free
    # the later ones move up: the order stays
    mov rdi, r13
    lea rsi, [r13 + PR_SIZE]
    mov rdx, [rip + probs + VEC_len]
    sub rdx, rbx
    dec rdx
    imul rdx, rdx, PR_SIZE
    call memmove
    dec qword ptr [rip + probs + VEC_len]
    jmp 1b
2:  mov dword ptr [r12 + PS_count], 0
    mov dword ptr [r12 + PS_errors], 0
    mov dword ptr [r12 + PS_warnings], 0
    mov dword ptr [r12 + PS_dropped], 0
    mov rdi, r12
    call extmarks_clear_owner
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# problems_add(PS*, PR*) -> 1 kept, 0 not
FN problems_add
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call problems_tick          # documents opened before it get the ones before it, and not this twice
    cmp dword ptr [r12 + PS_count], PER_SOURCE
    jae .Lpa_drop
    cmp qword ptr [rip + probs + VEC_len], ALL_MAX
    jae .Lpa_drop
    # one of its own the same: kept once
    xor ebx, ebx
1:  cmp rbx, [rip + probs + VEC_len]
    jae 2f
    imul r14, rbx, PR_SIZE
    add r14, [rip + probs + VEC_ptr]
    inc rbx
    cmp [r14 + PR_src], r12
    jne 1b
    mov eax, [r14 + PR_line]
    cmp eax, [r13 + PR_line]
    jne 1b
    mov eax, [r14 + PR_col]
    cmp eax, [r13 + PR_col]
    jne 1b
    mov eax, [r14 + PR_sev]
    cmp eax, [r13 + PR_sev]
    jne 1b
    mov rdi, [r14 + PR_path]
    mov rsi, [r13 + PR_path]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [r14 + PR_msg]
    mov rsi, [r13 + PR_msg]
    call strcmp_eq
    test eax, eax
    jz 1b
    xor eax, eax
    EPILOGUE
2:  lea rdi, [rip + probs]
    mov esi, PR_SIZE
    call vec_push
    mov r14, rax
    mov rdi, r14
    mov rsi, r13
    mov edx, PR_SIZE
    call memcpy
    mov [r14 + PR_src], r12
    mov rdi, [r13 + PR_path]
    call dup
    mov [r14 + PR_path], rax
    mov rdi, [r13 + PR_msg]
    call dup
    mov [r14 + PR_msg], rax
    mov rdi, [r13 + PR_code]
    call dup
    mov [r14 + PR_code], rax
    inc dword ptr [r12 + PS_count]
    mov eax, [r14 + PR_sev]
    cmp eax, SEV_ERROR
    jne 3f
    inc dword ptr [r12 + PS_errors]
3:  cmp eax, SEV_WARNING
    jne 4f
    inc dword ptr [r12 + PS_warnings]
4:  # an open document shows it at once
    mov rdi, [r14 + PR_path]
    call doc_by_path
    test rax, rax
    jz 5f
    mov rdi, rax
    mov rsi, r14
    call mark_problem
5:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
.Lpa_drop:
    inc dword ptr [r12 + PS_dropped]
    xor eax, eax
    EPILOGUE

# doc_by_path(path) -> the open document of that file, or 0
doc_by_path:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rbx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc rbx
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz 1b
    mov rdi, [r13 + DOC_path]
    test rdi, rdi
    jz 1b
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# mark_problem(doc, PR*): the problem as a mark on the document: from its line and column (a column in
#   characters counted on the line), to its end, else the word at the column, else one character;
#   past the text it is not shown
mark_problem:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_len
    mov r15, rax                # the text's length
    mov esi, [r12 + PR_line]
    test esi, esi
    jnz 1f
    mov esi, 1
1:  mov edx, [r12 + PR_col]
    mov ecx, [r12 + PR_flags]
    mov rdi, rbx
    call point_of
    test rax, rax
    js 9f
    mov r13, rax                # start
    mov esi, [r12 + PR_endline]
    test esi, esi
    jz 3f
    mov edx, [r12 + PR_endcol]
    test edx, edx
    jz 3f
    mov ecx, [r12 + PR_flags]
    mov rdi, rbx
    call point_of
    test rax, rax
    js 3f
    cmp rax, r13
    ja 4f
3:  # the word at the column (letters, digits, _, and the bytes of other characters), else one byte
    mov r14, r13
2:  cmp r14, r15
    jae 21f
    mov rdi, rbx
    mov rsi, r14
    call doc_byte
    cmp eax, 0x80
    jae 22f
    mov edi, eax
    call is_ident
    test eax, eax
    jz 21f
22: inc r14
    jmp 2b
21: mov rax, r14
    cmp rax, r13
    ja 4f
    lea rax, [r13 + 1]          # one character (a line feed, at a line's end)
    cmp rax, r15
    jbe 4f
    mov rax, r13
4:  mov rdi, rbx
    mov rsi, [r12 + PR_src]
    mov rdx, r13
    mov rcx, rax
    mov r8d, [r12 + PR_sev]
    mov r9, [r12 + PR_msg]
    call extmarks_add_source
9:  EPILOGUE

# point_of(doc, line, col, flags) -> byte position of a 1-based line and column (bytes, or characters
#   with PRF_CHARS; 0 the line's first non-blank), or -1 past the text
point_of:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    cmp r12, [rbx + DOC_nlines]
    ja 8f
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_start
    mov r15, rax
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_end
    mov r12, rax                # the line's end
    test r13d, r13d
    jnz 2f
    # no column: the first non-blank
1:  cmp r15, r12
    jae 7f
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    cmp eax, ' '
    je 11f
    cmp eax, 9
    jne 7f
11: inc r15
    jmp 1b
2:  test r14d, PRF_CHARS
    jnz 3f
    lea rax, [r15 + r13 - 1]
    cmp rax, r12
    ja 8f
    mov r15, rax
    jmp 7f
3:  # characters: each lead byte counts
    dec r13d
4:  test r13d, r13d
    jz 7f
    cmp r15, r12
    jae 8f
    inc r15
5:  cmp r15, r12
    jae 6f
    mov rdi, rbx
    mov rsi, r15
    call doc_byte
    and eax, 0xc0
    cmp eax, 0x80
    jne 6f
    inc r15
    jmp 5b
6:  dec r13d
    jmp 4b
7:  mov rax, r15
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# problems_tick(): documents opened since the last tick get their problems' marks
FN problems_tick
    PROLOGUE
    cmp qword ptr [rip + probs + VEC_len], 0
    je 9f
    mov r15, [rip + last_doc]
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rbx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    inc rbx
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r12, [rax + TAB_doc]
    test r12, r12
    jz 1b
    mov rax, [r12 + DOC_id]
    cmp rax, [rip + last_doc]
    jbe 1b
    cmp rax, r15
    cmova r15, rax
    mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz 1b
    # its problems, from every source
    xor r13d, r13d
2:  cmp r13, [rip + probs + VEC_len]
    jae 1b
    imul r14, r13, PR_SIZE
    add r14, [rip + probs + VEC_ptr]
    inc r13
    mov rdi, [r14 + PR_path]
    mov rsi, [r12 + DOC_path]
    call strcmp_eq
    test eax, eax
    jz 2b
    mov rdi, r12
    mov rsi, r14
    call mark_problem
    jmp 2b
8:  mov [rip + last_doc], r15
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
9:  # with none, documents opened meanwhile have nothing to show
    call newest_doc
    mov [rip + last_doc], rax
    EPILOGUE

# newest_doc() -> the highest DOC_id of the open documents
newest_doc:
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + g_tabs + VEC_len]
    jae 9f
    imul rdx, rcx, TAB_SIZE
    add rdx, [rip + g_tabs + VEC_ptr]
    inc rcx
    cmp qword ptr [rdx + TAB_kind], TAB_DOC
    jne 1b
    mov rdx, [rdx + TAB_doc]
    test rdx, rdx
    jz 1b
    mov rdx, [rdx + DOC_id]
    cmp rdx, rax
    cmova rax, rdx
    jmp 1b
9:  ret

# problems_counts(PS*) -> eax errors, edx warnings, ecx not kept (past the caps)
FN problems_counts
    mov eax, [rdi + PS_errors]
    mov edx, [rdi + PS_warnings]
    mov ecx, [rdi + PS_dropped]
    ret

# problems_dump(sb): a line per problem (print-problems): "problem path=PATH line=L col=C end=L:C|-
#   severity=S code=CODE|- source=LABEL message=MESSAGE"
FN problems_dump
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + probs + VEC_len]
    jae 9f
    imul r13, rbx, PR_SIZE
    add r13, [rip + probs + VEC_ptr]
    inc rbx
    mov rdi, r12
    lea rsi, [rip + .Ld_path]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r13 + PR_path]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_line]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r13 + PR_line]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_col]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r13 + PR_col]
    call sb_push_u64
    test dword ptr [r13 + PR_flags], PRF_CHARS
    jz 2f
    mov rdi, r12
    mov esi, 'c'
    call sb_push_byte
2:  mov rdi, r12
    lea rsi, [rip + .Ld_end]
    call sb_push_cstr
    cmp dword ptr [r13 + PR_endline], 0
    jne 3f
    mov rdi, r12
    mov esi, '-'
    call sb_push_byte
    jmp 4f
3:  mov rdi, r12
    mov esi, [r13 + PR_endline]
    call sb_push_u64
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov esi, [r13 + PR_endcol]
    call sb_push_u64
4:  mov rdi, r12
    lea rsi, [rip + .Ld_sev]
    call sb_push_cstr
    mov eax, [r13 + PR_sev]
    lea rcx, [rip + .Ld_sevs]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_code]
    call sb_push_cstr
    mov rsi, [r13 + PR_code]
    cmp byte ptr [rsi], 0
    jne 5f
    lea rsi, [rip + .Ld_dash]
5:  mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_source]
    call sb_push_cstr
    mov rax, [r13 + PR_src]
    mov rsi, [rax + PS_label]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_message]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r13 + PR_msg]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lempty: .asciz ""
.Ld_path: .asciz "problem path="
.Ld_line: .asciz " line="
.Ld_col: .asciz " col="
.Ld_end: .asciz " end="
.Ld_sev: .asciz " severity="
.Ld_code: .asciz " code="
.Ld_dash: .asciz "-"
.Ld_source: .asciz " source="
.Ld_message: .asciz " message="
.Ld_error: .asciz "error"
.Ld_warning: .asciz "warning"
.Ld_info: .asciz "info"
.Ld_hint: .asciz "hint"
.p2align 3
.Ld_sevs: .quad .Ld_error, .Ld_warning, .Ld_info, .Ld_hint
