# Language configuration (docs/extensions/v1.1.md "Language configuration"): brackets, auto-closing
# and surrounding pairs, Enter indentation from token rules, auto-outdent while typing, continued
# comments and lists, doc comment blocks, word characters, toggle comment tokens and folding
# markers. The keys come from a grammar (.syn), an extension's [language.NAME] and defaults (the
# behaviour without any: today's); lc_for_doc merges them per grammar. The single-cursor and
# multi-cursor editing paths share lc_type, lc_newline and lc_pair_around.
.include "rhun.inc"

# the keys, in lck_names order; a .syn sets the first LCK_GRAMMAR of them here (comment, block,
# ident and colon_indent are the grammar's own keys)
.equ LCK_BRACKETS, 0
.equ LCK_AUTOCLOSE, 1
.equ LCK_AUTOCLOSE_CODE, 2
.equ LCK_SURROUND, 3
.equ LCK_OPEN, 4
.equ LCK_CLOSE, 5
.equ LCK_MIDDLE, 6
.equ LCK_DEDENT, 7
.equ LCK_CONTINUE, 8
.equ LCK_DOC, 9
.equ LCK_FOLD, 10
.equ LCK_FM, 11
.equ LCK_COMMENT, 12
.equ LCK_BLOCK, 13
.equ LCK_IDENT, 14
.equ LCK_COLON, 15
.equ LCK_COUNT, 16
.equ LCK_GRAMMAR, 12

# a token: up to 14 bytes, its length, its qualifiers
.equ LCT_len, 14
.equ LCT_qual, 15
.equ LCT_SIZE, 16
.equ LCT_TEXT, 14
.equ QF_FIRST, 1                # ^T: only as a line's first code token
.equ QF_LAST, 2                 # T$: only as its last
# a token list
.equ LCL_n, 0
.equ LCL_items, 8
.equ LCL_MAX, 32
.equ LCL_SIZE, 8 + 32 * 16
# an auto-closing pair
.equ LCP_open, 0
.equ LCP_close, 8
.equ LCP_olen, 16
.equ LCP_clen, 17
.equ LCP_flags, 18
.equ LCP_SIZE, 24
.equ LCP_CODE, 1                # autoclose_code: not inside strings and comments
.equ LC_PAIRS_MAX, 16

# a merged configuration
.equ LC_np, 0
.equ LC_pairs, 8                                # LC_PAIRS_MAX LCP
.equ LC_nsur, LC_pairs + 16 * LCP_SIZE
.equ LC_sur, LC_nsur + 8                        # 16 x (open, close)
.equ LC_br, LC_sur + 32                         # "()[]{}" NUL-ended, at most 16 pairs
.equ LC_open, LC_br + 40
.equ LC_close, LC_open + LCL_SIZE
.equ LC_middle, LC_close + LCL_SIZE
.equ LC_dedent, LC_middle + LCL_SIZE
.equ LC_cont, LC_dedent + LCL_SIZE
.equ LC_doc, LC_cont + LCL_SIZE                 # START MIDDLE END
.equ LC_hasdoc, LC_doc + 3 * LCT_SIZE
.equ LC_fold, LC_hasdoc + 8                     # 0 brackets, 1 indent
.equ LC_fm, LC_fold + 8                         # START END
.equ LC_hasfm, LC_fm + 2 * LCT_SIZE
.equ LC_cmt, LC_hasfm + 8                       # the line comment token (length 0: none)
.equ LC_blk, LC_cmt + LCT_SIZE                  # START END of the block comment toggle
.equ LC_hasblk, LC_blk + 2 * LCT_SIZE
.equ LC_nocase, LC_hasblk + 8
.equ LC_src, LC_nocase + 8                      # per key: 0 default, 1 grammar, 2 user grammar, 3 extension
.equ LC_srcext, LC_src + LCK_COUNT * 8
.equ LC_val, LC_srcext + LCK_COUNT * 8          # per key: the value used (cstr), or 0
.equ LC_wchar, LC_val + LCK_COUNT * 8
.equ LC_SIZE, LC_wchar + 256

# an extension's [language.NAME] key
.equ LO_ext, 0
.equ LO_lang, 8                 # owned cstr, "_" read as a space
.equ LO_key, 16
.equ LO_val, 24                 # owned cstr
.equ LO_SIZE, 32
.equ LO_MAX, 512

.equ LINE_MAX, 16384            # longer lines keep today's plain indentation
.equ TOK_MAX, 256
.equ IND_MAX, 240               # longer indentation is never outdented
.equ LCF_TEXT_MAX, 24576        # lcf_text's room: a line's indentation and a few tokens
.equ LC_POOL, 32
.equ LCS_owner, 0               # a pool slot: its grammar, what it was merged from, the LC
.equ LCS_sig, 8
.equ LCS_lc, 16
.equ LCS_SIZE, 16 + LC_SIZE

.bss
.p2align 3
lo_list: .zero VEC_SIZE
lc_gen: .quad 0
lc_dflt: .zero LC_SIZE          # the configuration of a document without a grammar
lc_dflt_ok: .quad 0
lcf_lc: .quad 0                 # the configuration being used
lcf_long: .quad 0               # 1: the loaded line is longer than LINE_MAX
lcf_len: .quad 0
lcf_line: .zero LINE_MAX + 16
lcf_cls: .zero LINE_MAX + 16
lcf_ntok: .quad 0
lcf_toks: .zero TOK_MAX * 16    # start, length, word?
lcf_text: .zero SB_SIZE         # lc_newline's and lc_type's text, in lcf_textbuf (never on the heap)
lcf_textbuf: .zero LCF_TEXT_MAX
lc_pool: .zero LC_POOL * LCS_SIZE   # merged configurations, by grammar (no heap: a cache)
lc_pool_next: .quad 0
lcf_cind: .zero 256             # a copy of the current line's indentation
lcf_cind_len: .quad 0
lcf_save: .zero 256             # a copy of the token being outdented
lcf_save_len: .quad 0
lcf_eind: .zero 256             # what Enter gives after a line
lcf_eind_len: .quad 0
lcf_eind_nd: .quad 0            # its length before a dedent word took a unit off
lcf_tgt_len: .quad 0            # an outdented line's indentation: lcf_eind's first bytes
nl_line: .quad 0                # lc_newline: the caret's line
nl_c: .quad 0                   # the caret's byte in it
nl_ind: .quad 0                 # its indentation (up to the caret)
nl_del: .quad 0                 # bytes before start the text replaces too
nl_caret: .quad 0               # the caret's offset in the text, or -1: at its end
nl_last: .quad 0                # the last code token before the caret when it is one byte, else 0
.globl lc_scanned
lc_scanned: .quad 0             # what the last lc_newline counts against the multi-cursor scan budget

.text

# lcf_text_reset(): lcf_text empty, on its static buffer
lcf_text_reset:
    lea rax, [rip + lcf_textbuf]
    mov [rip + lcf_text + SB_ptr], rax
    mov qword ptr [rip + lcf_text + SB_cap], LCF_TEXT_MAX
    mov qword ptr [rip + lcf_text + SB_len], 0
    mov byte ptr [rax], 0
    ret

# ---------------------------------------------------------------- keys and values

# lck_index(ptr, len, count) -> eax the key's index below count, or -1
lck_index:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    xor ebx, ebx
1:  cmp ebx, r14d
    jae 8f
    lea rax, [rip + lck_names]
    mov rdx, [rax + rbx*8]
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc ebx
    jmp 1b
2:  mov eax, ebx
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# lcf_count(ptr, len) -> rax tokens, rdx the longest, rcx the shortest
lcf_count:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d              # count
    xor r14d, r14d              # longest
    mov qword ptr [rsp], -1     # shortest
1:  mov rdi, rbx
    mov rsi, r12
    call next_word
    add rbx, rcx
    sub r12, rcx
    test rdx, rdx
    jz 2f
    inc r13
    cmp rdx, r14
    cmovg r14, rdx
    cmp rdx, [rsp]
    jae 1b
    mov [rsp], rdx
    jmp 1b
2:  mov rax, r13
    mov rdx, r14
    mov rcx, [rsp]
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# lc_value_ok(key, ptr, len) -> eax 1 when the value fits the key
lc_value_ok:
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    call lcf_count
    mov r14, rax                # tokens
    mov r15, rdx                # longest
    test r14, r14
    jz 8f
    cmp ebx, LCK_BRACKETS
    jne 1f
    cmp r14, 16
    ja 8f
    cmp r15, 2
    jne 8f
    cmp rcx, 2
    jne 8f
    jmp 9f
1:  cmp ebx, LCK_AUTOCLOSE
    jne 2f
    test r14, 1
    jnz 8f
    cmp r14, 2 * LC_PAIRS_MAX
    ja 8f
    cmp r15, 8
    ja 8f
    jmp 9f
2:  cmp ebx, LCK_AUTOCLOSE_CODE
    jne 3f
    cmp r15, 8
    ja 8f
    cmp r14, LC_PAIRS_MAX
    ja 8f
    jmp 9f
3:  cmp ebx, LCK_SURROUND
    jne 4f
    test r14, 1
    jnz 8f
    cmp r14, 32
    ja 8f
    cmp r15, 1
    jne 8f
    jmp 9f
4:  cmp ebx, LCK_CONTINUE
    ja 5f
    # the token lists: open, close, middle, dedent, continue
    cmp r14, LCL_MAX
    ja 8f
    cmp r15, LCT_TEXT + 1
    ja 8f
    jmp 9f
5:  cmp ebx, LCK_DOC
    jne 6f
    cmp r14, 3
    jne 8f
    cmp r15, LCT_TEXT
    ja 8f
    jmp 9f
6:  cmp ebx, LCK_FOLD
    jne 7f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lv_indent]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lv_brackets]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    jmp 8f
7:  cmp ebx, LCK_FM
    je 71f
    cmp ebx, LCK_BLOCK
    jne 72f
71: cmp r14, 2
    jne 8f
    cmp r15, LCT_TEXT
    ja 8f
    jmp 9f
72: cmp ebx, LCK_COMMENT
    jne 73f
    cmp r14, 1
    jne 8f
    cmp r15, LCT_TEXT
    ja 8f
    jmp 9f
73: cmp ebx, LCK_IDENT
    jne 74f
    cmp r14, 1
    jne 8f
    cmp r15, 31
    ja 8f
    jmp 9f
74: mov rdi, r12                # colon_indent
    mov rsi, r13
    lea rdx, [rip + .Lv_yes]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lv_no]
    call str_eq_cstr
    test eax, eax
    jnz 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

# lcf_raw(gr) -> rax the grammar's table of raw values (LCK_COUNT cstrs), made on first use
lcf_raw:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + GR_lckeys]
    test rax, rax
    jnz 1f
    mov edi, LCK_COUNT * 8
    call mem_alloc
    mov [rbx + GR_lckeys], rax
1:  pop rbx
    ret

# FN lc_grammar_key(gr, key, klen, val, vlen) -> eax 1 when it was a language key (kept for the
#   grammar; a bad value counts as a grammar warning)
FN lc_grammar_key
    PROLOGUE
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    mov rdi, rsi
    mov rsi, rdx
    mov edx, LCK_GRAMMAR
    call lck_index
    test eax, eax
    js 8f
    mov r14d, eax
    mov rdi, r12
    mov rsi, r13
    call trim
    mov r12, rax
    mov r13, rdx
    mov edi, r14d
    mov rsi, r12
    mov rdx, r13
    call lc_value_ok
    test eax, eax
    jz 7f
    mov rdi, rbx
    call lcf_raw
    mov r15, rax
    mov rdi, [r15 + r14*8]
    test rdi, rdi
    jz 1f
    call mem_free
1:  mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r15 + r14*8], rax
    mov eax, 1
    EPILOGUE
7:  inc dword ptr [rip + g_grammar_warnings]
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN lc_grammar_block(gr, start, slen, end, elen): the grammar's first block comment, the pair
#   Toggle Comment uses when it has no line comment
FN lc_grammar_block
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    test r13, r13
    jz 9f
    test r15, r15
    jz 9f
    cmp r13, LCT_TEXT
    ja 9f
    cmp r15, LCT_TEXT
    ja 9f
    mov rdi, rbx
    call lcf_raw
    cmp qword ptr [rax + LCK_BLOCK*8], 0
    jne 9f
    mov [rsp + 40], rax
    lea rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [rsp + r13], ' '
    lea rdi, [rsp + r13 + 1]
    mov rsi, r14
    mov rdx, r15
    call memcpy
    lea rsi, [r13 + r15 + 1]
    lea rdi, [rsp]
    call mem_dup
    mov rcx, [rsp + 40]
    mov [rcx + LCK_BLOCK*8], rax
9:  EPILOGUE

# ---------------------------------------------------------------- extensions' [language.NAME]

# FN langconf_manifest_kv(ext, ini) -> eax 1 for a [language.NAME] line: KEY = VALUE, one of the
#   language keys; a bad key or value is a problem on the extension's page
FN langconf_manifest_kv
    PROLOGUE 160
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [r12 + INI_sec]
    mov rsi, [r12 + INI_seclen]
    lea rdx, [rip + .Llanguage_dot]
    mov ecx, 9
    call str_starts
    test eax, eax
    jz .Llm_no
    mov r13, [r12 + INI_seclen]
    sub r13, 9                  # the name's length
    jz .Llm_bad_name
    cmp r13, 64
    ja .Llm_bad_name
    # the name, "_" as a space
    mov rsi, [r12 + INI_sec]
    add rsi, 9
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    mov al, [rsi + rcx]
    cmp al, '_'
    jne 11f
    mov al, ' '
11: mov [rsp + rcx], al
    inc rcx
    jmp 1b
2:  mov byte ptr [rsp + r13], 0
    mov rdi, [r12 + INI_key]
    mov rsi, [r12 + INI_keylen]
    mov edx, LCK_COUNT
    call lck_index
    test eax, eax
    js .Llm_bad_key
    mov r14d, eax
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call trim
    mov [rsp + 72], rax
    mov [rsp + 80], rdx
    mov edi, r14d
    mov rsi, rax
    call lc_value_ok
    test eax, eax
    jz .Llm_bad_value
    # another extension setting the same key of the same language: listed on both pages
    xor r15d, r15d
3:  cmp r15, [rip + lo_list + VEC_len]
    jae 5f
    imul rax, r15, LO_SIZE
    add rax, [rip + lo_list + VEC_ptr]
    inc r15
    cmp [rax + LO_key], r14
    jne 3b
    cmp [rax + LO_ext], rbx
    je 3b
    mov [rsp + 88], rax
    mov rdi, [rax + LO_lang]
    lea rsi, [rsp]
    call lcf_name_eq
    test eax, eax
    jz 3b
    mov rax, [rsp + 88]
    mov rdi, [rax + LO_ext]
    call lcf_also_text
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rip + lcf_text + SB_ptr]
    call contrib_problem_line
    # and on the other one's page: "[language.NAME] KEY: also set by THIS"
    mov rdi, rbx
    call lcf_also_text
    lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    lea rdi, [rsp + 96]
    lea rsi, [rip + .Lp_open]
    call sb_push_cstr
    lea rdi, [rsp + 96]
    mov rsi, [r12 + INI_sec]
    mov rdx, [r12 + INI_seclen]
    call sb_push
    lea rdi, [rsp + 96]
    lea rsi, [rip + .Lp_close]
    call sb_push_cstr
    lea rdi, [rsp + 96]
    mov rsi, [r12 + INI_key]
    mov rdx, [r12 + INI_keylen]
    call sb_push
    lea rdi, [rsp + 96]
    lea rsi, [rip + .Lp_colon]
    call sb_push_cstr
    lea rdi, [rsp + 96]
    mov rsi, [rip + lcf_text + SB_ptr]
    call sb_push_cstr
    mov rax, [rsp + 88]
    mov rdi, [rax + LO_ext]
    mov rsi, [rsp + 96 + SB_ptr]
    call contrib_problem
    lea rdi, [rsp + 96]
    call sb_free
    jmp 3b
5:  cmp qword ptr [rip + lo_list + VEC_len], LO_MAX
    jae .Llm_bad_value
    lea rdi, [rip + lo_list]
    mov esi, LO_SIZE
    call vec_push
    mov r15, rax
    mov [r15 + LO_ext], rbx
    mov [r15 + LO_key], r14
    lea rdi, [rsp]
    mov rsi, r13
    call mem_dup
    mov [r15 + LO_lang], rax
    mov rdi, [rsp + 72]
    mov rsi, [rsp + 80]
    call mem_dup
    mov [r15 + LO_val], rax
    inc qword ptr [rip + lc_gen]
    mov eax, 1
    EPILOGUE
.Llm_bad_name:
    lea rdx, [rip + .Lp_name]
    jmp .Llm_problem
.Llm_bad_key:
    lea rdx, [rip + .Lp_key]
    jmp .Llm_problem
.Llm_bad_value:
    lea rdx, [rip + .Lp_value]
.Llm_problem:
    mov rdi, rbx
    mov rsi, r12
    call contrib_problem_line
    mov eax, 1
    EPILOGUE
.Llm_no:
    xor eax, eax
    EPILOGUE

# lcf_also_text(ext): lcf_text = "also set by OWNER/NAME"
lcf_also_text:
    push rbx
    mov rbx, rdi
    call lcf_text_reset
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + .Lp_also]
    call sb_push_cstr
    lea rdi, [rip + lcf_text]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + lcf_text]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    pop rbx
    ret

# lcf_name_eq(cstr, cstr) -> eax 1 when the names are equal ignoring case
lcf_name_eq:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call strlen
    mov [rsp], rax
    mov rdi, r12
    call strlen
    mov rcx, rax
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, r12
    call str_ieq
    add rsp, 8
    pop r12
    pop rbx
    ret

# FN langconf_ext_gone(ext): its [language.NAME] keys go
FN langconf_ext_gone
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + lo_list + VEC_len]
1:  test r12, r12
    jz 9f
    dec r12
    imul r13, r12, LO_SIZE
    add r13, [rip + lo_list + VEC_ptr]
    cmp [r13 + LO_ext], rbx
    jne 1b
    mov rdi, [r13 + LO_lang]
    call mem_free
    mov rdi, [r13 + LO_val]
    call mem_free
    # the later ones move down
    mov rdx, [rip + lo_list + VEC_len]
    sub rdx, r12
    dec rdx
    imul rdx, rdx, LO_SIZE
    mov rdi, r13
    lea rsi, [r13 + LO_SIZE]
    call memmove
    dec qword ptr [rip + lo_list + VEC_len]
    inc qword ptr [rip + lc_gen]
    jmp 1b
9:  EPILOGUE

# ---------------------------------------------------------------- merging

# lcf_sig() -> rax what the cached configurations depend on: the overlays and whether their
#   extensions are on
lcf_sig:
    mov rax, [rip + lc_gen]
    imul rax, rax, 1000003
    xor ecx, ecx
1:  cmp rcx, [rip + lo_list + VEC_len]
    jae 3f
    imul rdx, rcx, LO_SIZE
    add rdx, [rip + lo_list + VEC_ptr]
    mov rdx, [rdx + LO_ext]
    imul rax, rax, 31
    mov r8d, [rdx + EXT_disabled]
    lea rax, [rax + r8 + 1]
    inc rcx
    jmp 1b
3:  ret

# FN lc_for_doc(doc) -> rax the document's merged configuration (never 0)
FN lc_for_doc
    test rdi, rdi
    jz lc_for_gr
    mov rdi, [rdi + DOC_lang]   # its grammar as last synced (no syncing here: no side effects)
    jmp lc_for_gr

# FN lc_for_gr(gr or 0) -> rax its merged configuration
FN lc_for_gr
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jnz 1f
    lea rax, [rip + lc_dflt]
    cmp qword ptr [rip + lc_dflt_ok], 0
    jne 9f
    mov rdi, rax
    xor esi, esi
    call lc_build
    mov qword ptr [rip + lc_dflt_ok], 1
    lea rax, [rip + lc_dflt]
    jmp 9f
1:  mov rdi, rbx
    call syntax_ready
    call lcf_sig
    mov r12, rax
    # its slot in the pool (the grammar itself is not written: it may be read-only)
    lea rax, [rip + lc_pool]
    xor ecx, ecx
1:  cmp ecx, LC_POOL
    jae 2f
    cmp [rax + LCS_owner], rbx
    je 4f
    add rax, LCS_SIZE
    inc ecx
    jmp 1b
4:  cmp [rax + LCS_sig], r12
    jne 3f
    lea rax, [rax + LCS_lc]
    jmp 9f
2:  # a slot of the pool, in turn
    mov rax, [rip + lc_pool_next]
    lea rcx, [rax + 1]
    cmp rcx, LC_POOL
    jb 21f
    xor ecx, ecx
21: mov [rip + lc_pool_next], rcx
    imul rax, rax, LCS_SIZE
    lea rcx, [rip + lc_pool]
    add rax, rcx
    mov [rax + LCS_owner], rbx
3:  mov [rax + LCS_sig], r12
    mov r13, rax
    lea rdi, [rax + LCS_lc]
    mov rsi, rbx
    call lc_build
    lea rax, [r13 + LCS_lc]
9:  EPILOGUE

# lcf_grammar_value(gr, key) -> rax the grammar's own value (cstr), or 0
lcf_grammar_value:
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp esi, LCK_COMMENT
    jne 1f
    cmp qword ptr [rdi + GR_commentlen], 0
    je 9f
    mov rax, [rdi + GR_comment]
    ret
1:  cmp esi, LCK_COLON
    jne 2f
    test qword ptr [rdi + GR_flags], GF_COLON
    jz 9f
    lea rax, [rip + .Lv_yes]
    ret
2:  cmp esi, LCK_IDENT
    je 9f                       # in GR_wchar already
    mov rdx, [rdi + GR_lckeys]
    test rdx, rdx
    jz 9f
    movsxd rsi, esi
    mov rax, [rdx + rsi*8]
9:  ret

# lcf_resolve(gr, key) -> rax value or 0, edx source, rcx the extension
lcf_resolve:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call lcf_grammar_value
    mov r13, rax
    test rbx, rbx
    jz 7f
    test qword ptr [rbx + GR_flags], GF_USER
    jz 1f
    test r13, r13
    jz 1f
    mov rax, r13
    mov edx, 2
    xor ecx, ecx
    EPILOGUE
1:  xor r14d, r14d              # the first enabled extension's value
2:  cmp r14, [rip + lo_list + VEC_len]
    jae 7f
    imul r15, r14, LO_SIZE
    add r15, [rip + lo_list + VEC_ptr]
    inc r14
    cmp [r15 + LO_key], r12
    jne 2b
    mov rdi, [r15 + LO_ext]
    call ext_is_visible
    test eax, eax
    jz 2b
    mov rax, [r15 + LO_ext]
    cmp dword ptr [rax + EXT_disabled], 0
    jne 2b
    mov rdi, [r15 + LO_lang]
    mov rsi, [rbx + GR_name]
    test rsi, rsi
    jz 2b
    call lcf_name_eq
    test eax, eax
    jz 2b
    mov rax, [r15 + LO_val]
    mov edx, 3
    mov rcx, [r15 + LO_ext]
    EPILOGUE
7:  mov rax, r13
    xor edx, edx
    test rax, rax
    setnz dl
    xor ecx, ecx
    EPILOGUE

# lc_build(lc, gr or 0): the merged configuration of a grammar
lc_build:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    xor esi, esi
    mov edx, LC_SIZE
    call memset
    # word bytes: the grammar's, else letters, digits, _ and every byte of a multibyte character
    test r12, r12
    jz 1f
    lea rdi, [rbx + LC_wchar]
    lea rsi, [r12 + GR_wchar]
    mov edx, 256
    call memcpy
    test qword ptr [r12 + GR_flags], GF_NOCASE
    setnz al
    movzx eax, al
    mov [rbx + LC_nocase], rax
    jmp 2f
1:  xor ecx, ecx
11: mov edi, ecx
    push rcx
    push rcx
    call is_ident
    pop rcx
    pop rcx
    mov [rbx + LC_wchar + rcx], al
    inc ecx
    cmp ecx, 256
    jb 11b
2:  # every key: its value and where it came from
    xor r13d, r13d
3:  cmp r13d, LCK_COUNT
    jae 4f
    mov rdi, r12
    mov esi, r13d
    call lcf_resolve
    mov [rbx + LC_val + r13*8], rax
    mov [rbx + LC_src + r13*8], rdx
    mov [rbx + LC_srcext + r13*8], rcx
    inc r13d
    jmp 3b
4:  # ident: more word bytes
    mov rsi, [rbx + LC_val + LCK_IDENT*8]
    test rsi, rsi
    jz 5f
41: movzx eax, byte ptr [rsi]
    test eax, eax
    jz 5f
    mov byte ptr [rbx + LC_wchar + rax], 1
    inc rsi
    jmp 41b
5:  # pairs
    mov rsi, [rbx + LC_val + LCK_AUTOCLOSE*8]
    test rsi, rsi
    jnz 51f
    lea rsi, [rip + .Ld_autoclose]
51: mov rdi, rbx
    call lcf_parse_pairs
    mov rsi, [rbx + LC_val + LCK_AUTOCLOSE_CODE*8]
    test rsi, rsi
    jnz 52f
    lea rsi, [rip + .Ld_code]
52: mov rdi, rbx
    call lcf_parse_code
    mov rsi, [rbx + LC_val + LCK_SURROUND*8]
    mov rdi, rbx
    call lcf_parse_surround
    mov rsi, [rbx + LC_val + LCK_BRACKETS*8]
    test rsi, rsi
    jnz 53f
    lea rsi, [rip + .Ld_brackets]
53: mov rdi, rbx
    call lcf_parse_brackets
    # indentation tokens
    mov rsi, [rbx + LC_val + LCK_OPEN*8]
    test rsi, rsi
    jnz 6f
    lea rsi, [rip + .Ld_open]
6:  lea rdi, [rbx + LC_open]
    mov edx, 1
    call lcf_parse_list
    mov rsi, [rbx + LC_val + LCK_COLON*8]
    test rsi, rsi
    jz 61f
    lea rdi, [rip + .Lv_yes]
    call strcmp_eq_swap
    test eax, eax
    jz 61f
    lea rdi, [rbx + LC_open]
    lea rsi, [rip + .Ld_colon]
    mov edx, 1
    call lcf_parse_list
61: mov rsi, [rbx + LC_val + LCK_CLOSE*8]
    test rsi, rsi
    jnz 62f
    lea rsi, [rip + .Ld_close]
62: lea rdi, [rbx + LC_close]
    mov edx, 1
    call lcf_parse_list
    mov rsi, [rbx + LC_val + LCK_MIDDLE*8]
    lea rdi, [rbx + LC_middle]
    mov edx, 1
    call lcf_parse_list
    mov rsi, [rbx + LC_val + LCK_DEDENT*8]
    lea rdi, [rbx + LC_dedent]
    xor edx, edx
    call lcf_parse_list
    mov rsi, [rbx + LC_val + LCK_CONTINUE*8]
    lea rdi, [rbx + LC_cont]
    xor edx, edx
    call lcf_parse_list
    # doc_block, fold, fold_markers, comment, block
    mov rsi, [rbx + LC_val + LCK_DOC*8]
    lea rdi, [rbx + LC_doc]
    mov edx, 3
    call lcf_parse_fixed
    mov [rbx + LC_hasdoc], rax
    mov rsi, [rbx + LC_val + LCK_FOLD*8]
    test rsi, rsi
    jz 7f
    lea rdi, [rip + .Lv_indent]
    call strcmp_eq_swap
    mov [rbx + LC_fold], rax
7:  mov rsi, [rbx + LC_val + LCK_FM*8]
    lea rdi, [rbx + LC_fm]
    mov edx, 2
    call lcf_parse_fixed
    mov [rbx + LC_hasfm], rax
    mov rsi, [rbx + LC_val + LCK_COMMENT*8]
    lea rdi, [rbx + LC_cmt]
    mov edx, 1
    call lcf_parse_fixed
    mov rsi, [rbx + LC_val + LCK_BLOCK*8]
    lea rdi, [rbx + LC_blk]
    mov edx, 2
    call lcf_parse_fixed
    mov [rbx + LC_hasblk], rax
    EPILOGUE

# strcmp_eq_swap(a, b) -> strcmp_eq(b, a); 0 when b is 0
strcmp_eq_swap:
    xor eax, eax
    test rsi, rsi
    jz 1f
    jmp strcmp_eq
1:  ret

# lcf_tok(dst LCT, ptr, len): a token
lcf_tok:
    mov byte ptr [rdi + LCT_len], dl
    mov byte ptr [rdi + LCT_qual], 0
    mov rcx, rdx
    push rdi
    push rdi
    mov rdx, rcx
    call memcpy
    pop rdi
    pop rdi
    ret

# lcf_parse_list(LCL, cstr or 0, qualifiers?): its space separated tokens, appended
lcf_parse_list:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r15d, edx
    test r12, r12
    jz 9f
    mov rdi, r12
    call strlen
    mov r13, rax
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    mov r14, rax
    xor ecx, ecx                # qualifiers
    test r15d, r15d
    jz 3f
    cmp rdx, 1
    jbe 3f
    cmp byte ptr [r14], '^'
    jne 2f
    or ecx, QF_FIRST
    inc r14
    dec rdx
2:  cmp rdx, 1
    jbe 3f
    cmp byte ptr [r14 + rdx - 1], '$'
    jne 3f
    or ecx, QF_LAST
    dec rdx
3:  test rdx, rdx
    jz 1b
    cmp rdx, LCT_TEXT
    ja 1b
    mov rax, [rbx + LCL_n]
    cmp rax, LCL_MAX
    jae 9f
    inc qword ptr [rbx + LCL_n]
    shl rax, 4
    lea rdi, [rbx + LCL_items + rax]
    push rcx
    push rdi
    mov rsi, r14
    call lcf_tok
    pop rdi
    pop rcx
    mov [rdi + LCT_qual], cl
    jmp 1b
9:  EPILOGUE

# lcf_parse_fixed(LCT array, cstr or 0, count) -> rax 1 when the value has exactly count tokens
lcf_parse_fixed:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r15d, edx
    xor eax, eax
    test r12, r12
    jz 9f
    mov rdi, r12
    call strlen
    mov r13, rax
    xor r14d, r14d
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 2f
    cmp r14d, r15d
    jae 8f
    cmp rdx, LCT_TEXT
    ja 8f
    mov rdi, r14
    shl rdi, 4
    add rdi, rbx
    mov rsi, rax
    call lcf_tok
    inc r14d
    jmp 1b
2:  xor eax, eax
    cmp r14d, r15d
    jne 9f
    mov eax, 1
9:  EPILOGUE
8:  # a bad value: none
    mov rdi, rbx
    xor esi, esi
    mov edx, r15d
    shl edx, 4
    call memset
    xor eax, eax
    EPILOGUE

# lcf_parse_pairs(lc, cstr): OPEN CLOSE token pairs
lcf_parse_pairs:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call strlen
    mov r13, rax
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    cmp r15, 8
    ja 1b
    cmp rdx, 8
    ja 1b
    mov rcx, [rbx + LC_np]
    cmp rcx, LC_PAIRS_MAX
    jae 9f
    inc qword ptr [rbx + LC_np]
    imul rcx, rcx, LCP_SIZE
    lea rdi, [rbx + LC_pairs + rcx]
    mov [rdi + LCP_olen], r15b
    mov [rdi + LCP_clen], dl
    push rdi
    push rdx
    lea rdi, [rdi + LCP_close]
    mov rsi, rax
    call memcpy
    pop rdx
    pop rdi
    mov rsi, r14
    mov rdx, r15
    call memcpy
    jmp 1b
9:  EPILOGUE

# lcf_parse_code(lc, cstr): pairs whose OPEN is listed close only in code
lcf_parse_code:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call strlen
    mov r13, rax
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    mov r14, rax
    mov r15, rdx
    xor ecx, ecx
2:  cmp rcx, [rbx + LC_np]
    jae 1b
    imul rax, rcx, LCP_SIZE
    lea rax, [rbx + LC_pairs + rax]
    inc rcx
    movzx edx, byte ptr [rax + LCP_olen]
    cmp rdx, r15
    jne 2b
    push rcx
    push rax
    mov rdi, rax
    mov rsi, r15
    mov rdx, r14
    mov rcx, r15
    call str_eq
    mov edx, eax
    pop rax
    pop rcx
    test edx, edx
    jz 2b
    or byte ptr [rax + LCP_flags], LCP_CODE
    jmp 2b
9:  EPILOGUE

# lcf_parse_surround(lc, cstr or 0): single-byte OPEN CLOSE pairs; without a value the
#   single-byte auto-closing pairs
lcf_parse_surround:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 5f
    mov rdi, r12
    call strlen
    mov r13, rax
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    cmp r15, 1
    jne 1b
    cmp rdx, 1
    jne 1b
    mov rcx, [rbx + LC_nsur]
    cmp rcx, 16
    jae 9f
    movzx edx, byte ptr [r14]
    mov [rbx + LC_sur + rcx*2], dl
    movzx edx, byte ptr [rax]
    mov [rbx + LC_sur + rcx*2 + 1], dl
    inc qword ptr [rbx + LC_nsur]
    jmp 1b
5:  xor ecx, ecx
6:  cmp rcx, [rbx + LC_np]
    jae 9f
    imul rax, rcx, LCP_SIZE
    lea rax, [rbx + LC_pairs + rax]
    inc rcx
    cmp byte ptr [rax + LCP_olen], 1
    jne 6b
    cmp byte ptr [rax + LCP_clen], 1
    jne 6b
    mov rdx, [rbx + LC_nsur]
    cmp rdx, 16
    jae 9f
    mov r8b, [rax + LCP_open]
    mov [rbx + LC_sur + rdx*2], r8b
    mov r8b, [rax + LCP_close]
    mov [rbx + LC_sur + rdx*2 + 1], r8b
    inc qword ptr [rbx + LC_nsur]
    jmp 6b
9:  EPILOGUE

# lcf_parse_brackets(lc, cstr): two-byte tokens into LC_br
lcf_parse_brackets:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call strlen
    mov r13, rax
    xor r14d, r14d              # bytes written
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 9f
    cmp rdx, 2
    jne 1b
    cmp r14, 32
    jae 9f
    movzx ecx, byte ptr [rax]
    mov [rbx + LC_br + r14], cl
    movzx ecx, byte ptr [rax + 1]
    mov [rbx + LC_br + r14 + 1], cl
    add r14, 2
    jmp 1b
9:  mov byte ptr [rbx + LC_br + r14], 0
    EPILOGUE

# ---------------------------------------------------------------- reading a line

# lcf_load(doc, line, upto or -1): lcf_line/lcf_cls = the line's bytes (its first upto, at most
#   LINE_MAX) and their syntax classes (all code for a grammar without regions). Nothing is allocated.
lcf_load:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r15, rax
    sub r15, r14
    add [rip + lc_scanned], r15
    mov qword ptr [rip + lcf_long], 0
    cmp r15, r13
    jbe 1f
    mov r15, r13
1:  cmp r15, LINE_MAX
    jbe 2f
    mov r15, LINE_MAX
    mov qword ptr [rip + lcf_long], 1
2:  mov [rip + lcf_len], r15
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    lea rcx, [rip + lcf_line]
    call doc_copy
    lea rax, [rip + lcf_line]
    mov byte ptr [rax + r15], 0
    call lcf_classes
    EPILOGUE

# lcf_classes (rbx the document, r12 the line): lcf_cls for lcf_line/lcf_len
lcf_classes:
    push rbx
    mov rax, [rbx + DOC_lang]
    test rax, rax
    jz 1f
    cmp qword ptr [rax + GR_regions + VEC_len], 0
    jne 2f
    cmp qword ptr [rax + GR_lines + VEC_len], 0
    jne 2f
1:  lea rdi, [rip + lcf_cls]
    xor esi, esi
    mov rdx, [rip + lcf_len]
    inc rdx
    call memset
    pop rbx
    ret
2:  mov rdi, rbx
    mov rsi, r12
    call syntax_prepare
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + lcf_line]
    mov rcx, [rip + lcf_len]
    lea r8, [rip + lcf_cls]
    call syntax_line
    pop rbx
    ret

# lcf_code(i) -> eax 1 when byte i of the loaded line is code (not a string or a comment)
lcf_code:
    lea rax, [rip + lcf_cls]
    movzx eax, byte ptr [rax + rdi]
    cmp eax, C_STRING
    je 1f
    cmp eax, C_COMMENT
    je 1f
    cmp eax, C_ESCAPE
    je 1f
    mov eax, 1
    ret
1:  xor eax, eax
    ret

# lcf_indent() -> rax the loaded line's leading blanks
lcf_indent:
    xor eax, eax
    lea rcx, [rip + lcf_line]
1:  cmp rax, [rip + lcf_len]
    jae 2f
    movzx edx, byte ptr [rcx + rax]
    cmp edx, ' '
    je 3f
    cmp edx, 9
    jne 2f
3:  inc rax
    jmp 1b
2:  ret

# lcf_punct_len(i, to) -> rax the longest configured punctuation token at byte i of the loaded
#   line (open, close and middle lists), else 1
lcf_punct_len:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r15d, 1                 # the best length
    mov rbx, [rip + lcf_lc]
    lea r14, [rbx + LC_open]
    call .Lpl_list
    lea r14, [rbx + LC_close]
    call .Lpl_list
    lea r14, [rbx + LC_middle]
    call .Lpl_list
    mov eax, r15d
    EPILOGUE
.Lpl_list:
    xor ecx, ecx
1:  cmp rcx, [r14 + LCL_n]
    jae 9f
    mov rax, rcx
    shl rax, 4
    lea rax, [r14 + LCL_items + rax]
    inc rcx
    movzx edx, byte ptr [rax + LCT_len]
    cmp edx, r15d
    jbe 1b
    lea r8, [r12 + rdx]
    cmp r8, r13
    ja 1b
    # a word token is not punctuation
    movzx r8d, byte ptr [rax]
    cmp byte ptr [rbx + LC_wchar + r8], 0
    jne 1b
    xor r9d, r9d
    lea r10, [rip + lcf_line]
    add r10, r12
2:  cmp r9, rdx
    jae 3f
    mov r8b, [rax + r9]
    cmp r8b, [r10 + r9]
    jne 1b
    inc r9
    jmp 2b
3:  mov r15d, edx
    jmp 1b
9:  ret

# lcf_tokens(from, to): lcf_toks = the loaded line's code tokens in [from, to)
lcf_tokens:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + lcf_lc]
    mov qword ptr [rip + lcf_ntok], 0
1:  cmp r12, r13
    jae 9f
    cmp qword ptr [rip + lcf_ntok], TOK_MAX
    jae 9f
    lea rax, [rip + lcf_line]
    movzx r14d, byte ptr [rax + r12]
    cmp r14d, ' '
    je 2f
    cmp r14d, 9
    je 2f
    cmp r14d, 13
    je 2f
    mov rdi, r12
    call lcf_code
    test eax, eax
    jz 2f
    cmp byte ptr [rbx + LC_wchar + r14], 0
    je 4f
    # a word
    mov r15, r12
3:  inc r15
    cmp r15, r13
    jae 31f
    lea rax, [rip + lcf_line]
    movzx eax, byte ptr [rax + r15]
    cmp byte ptr [rbx + LC_wchar + rax], 0
    je 31f
    mov rdi, r15
    call lcf_code
    test eax, eax
    jnz 3b
31: mov rdx, r15
    sub rdx, r12
    mov ecx, 1
    jmp 5f
4:  mov rdi, r12
    mov rsi, r13
    call lcf_punct_len
    mov rdx, rax
    xor ecx, ecx
5:  mov rax, [rip + lcf_ntok]
    shl rax, 4
    lea r8, [rip + lcf_toks]
    mov [r8 + rax], r12d
    mov [r8 + rax + 4], edx
    mov [r8 + rax + 8], ecx
    inc qword ptr [rip + lcf_ntok]
    add r12, rdx
    jmp 1b
2:  inc r12
    jmp 1b
9:  EPILOGUE

# lcf_tok_in(list LCL, k) -> eax 1 when token k matches an item of the list
lcf_tok_in:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    shl rsi, 4
    lea rax, [rip + lcf_toks]
    add rax, rsi
    mov r13d, [rax]             # start
    mov r14d, [rax + 4]         # length
    xor r15d, r15d
1:  cmp r15, [rbx + LCL_n]
    jae 8f
    mov rax, r15
    shl rax, 4
    lea rdi, [rbx + LCL_items + rax]
    inc r15
    movzx ecx, byte ptr [rdi + LCT_qual]
    test ecx, QF_FIRST
    jz 2f
    test r12, r12
    jnz 1b
2:  test ecx, QF_LAST
    jz 3f
    mov rax, [rip + lcf_ntok]
    dec rax
    cmp r12, rax
    jne 1b
3:  movzx esi, byte ptr [rdi + LCT_len]
    lea rdx, [rip + lcf_line]
    add rdx, r13
    mov rcx, r14
    mov rax, [rip + lcf_lc]
    cmp qword ptr [rax + LC_nocase], 0
    jne 4f
    call str_eq
    jmp 5f
4:  call str_ieq
5:  test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_net() -> rax +1 per opening token, -1 per closing one, a leading closing token ignored and
#   a leading middle one counted +1
lcf_net:
    PROLOGUE
    mov rbx, [rip + lcf_lc]
    xor r12d, r12d              # net
    xor r13d, r13d              # first token counted
    cmp qword ptr [rip + lcf_ntok], 0
    je 9f
    lea rdi, [rbx + LC_middle]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz 1f
    mov r12d, 1
    mov r13d, 1
    jmp 2f
1:  lea rdi, [rbx + LC_open]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jnz 2f
    lea rdi, [rbx + LC_close]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz 2f
    mov r13d, 1
2:  cmp r13, [rip + lcf_ntok]
    jae 9f
    lea rdi, [rbx + LC_open]
    mov rsi, r13
    call lcf_tok_in
    test eax, eax
    jz 3f
    inc r12
    jmp 4f
3:  lea rdi, [rbx + LC_close]
    mov rsi, r13
    call lcf_tok_in
    test eax, eax
    jz 4f
    dec r12
4:  inc r13
    jmp 2b
9:  mov rax, r12
    EPILOGUE

# lcf_first_byte() / lcf_last_byte() -> rax the byte of the first / last token of lcf_toks when
#   it is one byte of punctuation, else 0
lcf_first_byte:
    xor eax, eax
    cmp qword ptr [rip + lcf_ntok], 0
    je 9f
    jmp 1f
lcf_last_byte:
    mov rax, [rip + lcf_ntok]
    test rax, rax
    jz 9f
    dec rax
1:  shl rax, 4
    lea rcx, [rip + lcf_toks]
    add rcx, rax
    cmp dword ptr [rcx + 4], 1
    jne 9f
    cmp dword ptr [rcx + 8], 0
    jne 9f
    mov eax, [rcx]
    lea rcx, [rip + lcf_line]
    movzx eax, byte ptr [rcx + rax]
    ret
9:  xor eax, eax
    ret

# lcf_brackets_differ(open byte, close byte) -> eax 1 when both are brackets (LC_br) and the close
#   is not the open's partner
lcf_brackets_differ:
    mov r8, [rip + lcf_lc]
    add r8, LC_br
    xor ecx, ecx
    mov r9d, -1                 # the open's partner
    xor r10d, r10d              # the close is a closing bracket
1:  movzx eax, byte ptr [r8 + rcx]
    test eax, eax
    jz 3f
    movzx edx, byte ptr [r8 + rcx + 1]
    cmp eax, edi
    jne 2f
    mov r9d, edx
2:  cmp edx, esi
    jne 21f
    mov r10d, 1
21: add rcx, 2
    jmp 1b
3:  xor eax, eax
    cmp r9d, -1
    je 9f
    test r10d, r10d
    jz 9f
    cmp r9d, esi
    setne al
9:  ret

# lcf_unit_into(sb): one indentation unit
lcf_unit_into:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    cmp dword ptr [rip + g_insert_spaces], 0
    je 2f
    mov r12d, [rip + g_tab_width]
1:  test r12d, r12d
    jz 3f
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    dec r12d
    jmp 1b
2:  mov rdi, rbx
    mov esi, 9
    call sb_push_byte
3:  add rsp, 8
    pop r12
    pop rbx
    ret

# lcf_less(ptr, len) -> rax the length of the indentation one unit less (a tab, or up to a tab
#   width of spaces, off its end)
lcf_less:
    test rsi, rsi
    jz 9f
    cmp byte ptr [rdi + rsi - 1], 9
    jne 1f
    lea rax, [rsi - 1]
    ret
1:  mov ecx, [rip + g_tab_width]
2:  test ecx, ecx
    jz 9f
    test rsi, rsi
    jz 9f
    cmp byte ptr [rdi + rsi - 1], ' '
    jne 9f
    dec rsi
    dec ecx
    jmp 2b
9:  mov rax, rsi
    ret

# lcf_enter_after(doc, line): lcf_eind = the indentation Enter gives at the end of that line:
#   its own, one unit more after an opening token, one less after a dedent word (lcf_eind_nd: the
#   length without that last rule)
lcf_enter_after:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, r12
    mov rdx, -1
    call lcf_load
    call lcf_indent
    mov r13, rax
    cmp r13, IND_MAX
    ja 8f
    lea rdi, [rip + lcf_eind]
    lea rsi, [rip + lcf_line]
    mov rdx, r13
    call memcpy
    mov [rip + lcf_eind_len], r13
    xor edi, edi
    mov rsi, [rip + lcf_len]
    call lcf_tokens
    call lcf_net
    test rax, rax
    jle 2f
    # one more: the unit after the copy
    cmp dword ptr [rip + g_insert_spaces], 0
    jne 1f
    lea rax, [rip + lcf_eind]
    mov byte ptr [rax + r13], 9
    inc qword ptr [rip + lcf_eind_len]
    jmp 9f
1:  mov ecx, [rip + g_tab_width]
11: test ecx, ecx
    jz 9f
    mov rax, [rip + lcf_eind_len]
    cmp rax, 250
    jae 9f
    lea rdx, [rip + lcf_eind]
    mov byte ptr [rdx + rax], ' '
    inc qword ptr [rip + lcf_eind_len]
    dec ecx
    jmp 11b
2:  mov rax, [rip + lcf_eind_len]
    mov [rip + lcf_eind_nd], rax
    cmp qword ptr [rip + lcf_ntok], 0
    je 91f
    lea rax, [rip + lcf_toks]
    cmp dword ptr [rax + 8], 0
    je 91f
    mov rdi, [rip + lcf_lc]
    add rdi, LC_dedent
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz 91f
    lea rdi, [rip + lcf_eind]
    mov rsi, [rip + lcf_eind_len]
    call lcf_less
    mov [rip + lcf_eind_len], rax
91: mov eax, 1
    EPILOGUE
9:  mov rax, [rip + lcf_eind_len]
    mov [rip + lcf_eind_nd], rax
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_untouched(doc, line) -> eax 1 when the line's indentation (lcf_cind) is what Enter after the
#   previous non-blank line gives (the user did not align it by hand) and the line's block is one
#   unit less than that line's: lcf_eind's first lcf_tgt_len bytes
lcf_untouched:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 1000              # lines looked at
1:  test r12, r12
    jz 8f
    dec r13d
    jz 8f
    dec r12
    mov rdi, rbx
    mov rsi, r12
    call lcf_blank
    test eax, eax
    jnz 1b
    mov rdi, rbx
    mov rsi, r12
    call lcf_enter_after
    test eax, eax
    jz 8f
    lea rdi, [rip + lcf_eind]
    mov rsi, [rip + lcf_eind_len]
    lea rdx, [rip + lcf_cind]
    mov rcx, [rip + lcf_cind_len]
    call str_eq
    test eax, eax
    jz 8f
    # outdented: one unit less than that line's block (not again after a dedent word took it)
    lea rdi, [rip + lcf_eind]
    mov rsi, [rip + lcf_eind_nd]
    call lcf_less
    mov [rip + lcf_tgt_len], rax
    cmp rax, [rip + lcf_cind_len]
    jae 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_blank(doc, line) -> eax 1 when the line has only blanks
lcf_blank:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_start
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov r14, rax
1:  cmp r13, r14
    jae 2f
    mov rdi, rbx
    mov rsi, r13
    call doc_byte
    inc r13
    cmp eax, ' '
    je 1b
    cmp eax, 9
    je 1b
    cmp eax, 13
    je 1b
    xor eax, eax
    EPILOGUE
2:  mov eax, 1
    EPILOGUE

# ---------------------------------------------------------------- Enter

# FN lc_newline(doc, start, end) -> rax the text Enter puts in place of [start - r8, end) (valid
#   until the next call), rdx its length, rcx the caret's offset in it, r8 the bytes before start it
#   replaces too (an ended list's marker, an outdented closing word)
FN lc_newline
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [rip + lc_scanned], 0
    mov qword ptr [rip + nl_del], 0
    mov qword ptr [rip + nl_caret], -1
    mov rdi, rbx
    call lc_for_doc
    mov [rip + lcf_lc], rax
    mov r14, rax
    call lcf_text_reset
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov [rip + nl_line], rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r15, rax                        # the line's start
    mov rax, r12
    sub rax, r15
    mov [rip + nl_c], rax
    mov rdi, rbx
    mov rsi, [rip + nl_line]
    mov rdx, -1
    call lcf_load
    call lcf_indent
    cmp rax, [rip + nl_c]
    cmova rax, [rip + nl_c]
    mov [rip + nl_ind], rax
    cmp qword ptr [rip + lcf_long], 0
    jne .Lnl_plain
    mov rax, [rip + nl_c]
    cmp rax, [rip + lcf_len]
    ja .Lnl_plain
    # 1. a continued list or comment, a doc comment block
    call .Lnl_continue
    test eax, eax
    jnz .Lnl_ret
    call .Lnl_doc
    test eax, eax
    jnz .Lnl_ret
    # the indentation new lines start from: the line's, or one unit less when it is a closing
    # word Enter outdents
    mov rdx, [rip + nl_ind]
    cmp rdx, IND_MAX
    ja .Lnl_plain
    mov [rip + lcf_cind_len], rdx
    lea rdi, [rip + lcf_cind]
    lea rsi, [rip + lcf_line]
    call memcpy
    call .Lnl_outdent
    # 2. and 3. the next line's indentation
    mov rdi, [rip + nl_ind]
    mov rsi, [rip + nl_c]
    call lcf_tokens
    call lcf_last_byte
    mov [rip + nl_last], rax
    call lcf_net
    mov [rsp], rax                      # net
    lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_cind]
    mov rdx, [rip + lcf_cind_len]
    call sb_push
    cmp qword ptr [rsp], 0
    jle 1f
    lea rdi, [rip + lcf_text]
    call lcf_unit_into
    jmp 2f
1:  cmp qword ptr [rip + lcf_ntok], 0
    je 2f
    lea rax, [rip + lcf_toks]
    cmp dword ptr [rax + 8], 0
    je 2f
    lea rdi, [r14 + LC_dedent]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz 2f
    # a dedent word: the new line one unit less
    mov rax, [rip + lcf_text + SB_len]
    sub rax, [rip + lcf_cind_len]       # where the copy starts
    mov [rsp + 8], rax
    lea rdi, [rip + lcf_cind]
    mov rsi, [rip + lcf_cind_len]
    call lcf_less
    add rax, [rsp + 8]
    mov [rip + lcf_text + SB_len], rax
2:  mov rax, [rip + lcf_text + SB_len]
    mov [rip + nl_caret], rax
    # 4. a closing token after the caret goes to a line of its own
    cmp qword ptr [rsp], 0
    jle .Lnl_ret
    mov rdi, rbx
    mov rsi, r13
    call doc_line_of
    cmp rax, [rip + nl_line]
    jne .Lnl_ret
    mov rdi, r13
    sub rdi, r15
    mov rsi, [rip + lcf_len]
    cmp rdi, rsi
    ja .Lnl_ret
    call lcf_tokens
    cmp qword ptr [rip + lcf_ntok], 0
    je .Lnl_ret
    lea rdi, [r14 + LC_close]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jnz 3f
    lea rdi, [r14 + LC_middle]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz .Lnl_ret
3:  # a bracket after an opening bracket that is not its partner stays ("{|]")
    call lcf_first_byte
    test rax, rax
    jz 4f
    mov rdi, [rip + nl_last]
    mov rsi, rax
    call lcf_brackets_differ
    test eax, eax
    jnz .Lnl_ret
4:  lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_cind]
    mov rdx, [rip + lcf_cind_len]
    call sb_push
.Lnl_ret:
    call lcf_scan_cost
    mov rax, [rip + lcf_text + SB_ptr]
    mov rdx, [rip + lcf_text + SB_len]
    mov rcx, [rip + nl_caret]
    cmp rcx, -1
    jne 1f
    mov rcx, rdx
1:  mov r8, [rip + nl_del]
    EPILOGUE
.Lnl_plain:
    # a line too long to read: its indentation, as before
    call lcf_text_reset
    lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    mov rdx, [rip + nl_ind]
    cmp rdx, LINE_MAX
    jbe 1f
    xor edx, edx
1:  lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_line]
    call sb_push
    mov qword ptr [rip + nl_caret], -1
    jmp .Lnl_ret

# lcf_scan_cost(): lc_scanned = what Enter at nl_c counts against a multi-cursor scan budget, as
#   the bytes the indentation rule used to read: the leading blanks and the first byte after them,
#   the blanks before the caret and the byte before them (twice the caret's column on a blank line)
lcf_scan_cost:
    mov rax, [rip + nl_ind]
    mov rcx, [rip + nl_c]
    cmp rax, rcx
    jb 1f
    lea rax, [rcx + rcx]
    mov [rip + lc_scanned], rax
    ret
1:  cmp rcx, [rip + lcf_len]
    jbe 2f
    mov rcx, [rip + lcf_len]
2:  lea rdx, [rip + lcf_line]
    xor r8d, r8d                # blanks before the caret
3:  cmp rcx, rax
    jbe 4f
    movzx r9d, byte ptr [rdx + rcx - 1]
    cmp r9d, ' '
    je 31f
    cmp r9d, 9
    jne 4f
31: inc r8
    dec rcx
    jmp 3b
4:  lea rax, [rax + r8 + 2]
    mov [rip + lc_scanned], rax
    ret

# .Lnl_continue (r14 the configuration, nl_* the caret) -> eax 1 when the line continues a list
#   or a line comment (or ends one): lcf_text, nl_del
.Lnl_continue:
    PROLOGUE 16
    mov qword ptr [rsp], 0              # the best token's length
    mov qword ptr [rsp + 8], 0          # and the token
    lea rbx, [r14 + LC_cont]
    xor r12d, r12d
1:  cmp r12, [rbx + LCL_n]
    jae 3f
    mov rax, r12
    shl rax, 4
    lea r13, [rbx + LCL_items + rax]
    inc r12
    movzx ecx, byte ptr [r13 + LCT_len]
    cmp rcx, [rsp]
    jbe 1b
    mov rax, [rip + nl_ind]
    add rax, rcx
    cmp rax, [rip + lcf_len]
    ja 1b
    # its bytes at the indentation, then a blank or the line's end
    lea rdi, [rip + lcf_line]
    add rdi, [rip + nl_ind]
    mov rsi, rcx
    mov rdx, r13
    push rcx
    push rcx
    call str_eq
    pop rcx
    pop rcx
    test eax, eax
    jz 1b
    mov rax, [rip + nl_ind]
    add rax, rcx
    cmp rax, [rip + lcf_len]
    je 2f
    lea rdx, [rip + lcf_line]
    movzx edx, byte ptr [rdx + rax]
    cmp edx, ' '
    je 2f
    cmp edx, 9
    jne 1b
2:  mov [rsp], rcx
    mov [rsp + 8], r13
    jmp 1b
3:  mov rcx, [rsp]
    test rcx, rcx
    jz 8f
    mov rax, [rip + nl_ind]
    add rax, rcx
    cmp [rip + nl_c], rax
    jb 8f                               # the caret before the marker: a plain Enter
    # only the marker on the line: it goes (the list ends)
    lea rdi, [rip + lcf_line]
    add rdi, rax
    mov rsi, [rip + lcf_len]
    sub rsi, rax
    call trim
    test rdx, rdx
    jnz 4f
    mov rax, [rip + nl_c]
    sub rax, [rip + nl_ind]
    mov [rip + nl_del], rax
    mov eax, 1
    EPILOGUE
4:  lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_line]
    mov rdx, [rip + nl_ind]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov rsi, [rsp + 8]
    movzx edx, byte ptr [rsi + LCT_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, ' '
    call sb_push_byte
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# .Lnl_doc -> eax 1 when the caret is in a doc comment block: " MIDDLE " on the new line
.Lnl_doc:
    PROLOGUE
    cmp qword ptr [r14 + LC_hasdoc], 0
    je 8f
    mov rax, [rip + nl_ind]
    cmp rax, [rip + lcf_len]
    jae 8f
    mov rdi, rax
    call lcf_code
    test eax, eax
    jnz 8f                              # not inside a comment
    # START: the caret after it
    lea r12, [r14 + LC_doc]
    call .Lnd_at
    test eax, eax
    jz 3f
    movzx eax, byte ptr [r12 + LCT_len]
    add rax, [rip + nl_ind]
    cmp [rip + nl_c], rax
    jb 8f
    lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_line]
    mov rdx, [rip + nl_ind]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [r14 + LC_doc + LCT_SIZE]
    movzx edx, byte ptr [rsi + LCT_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, ' '
    call sb_push_byte
    # END right after the caret: on a line of its own
    mov r13, [rip + nl_c]
1:  cmp r13, [rip + lcf_len]
    jae 7f
    lea rax, [rip + lcf_line]
    cmp byte ptr [rax + r13], ' '
    jne 2f
    inc r13
    jmp 1b
2:  lea r12, [r14 + LC_doc + 2 * LCT_SIZE]
    movzx esi, byte ptr [r12 + LCT_len]
    lea rax, [r13 + rsi]
    cmp rax, [rip + lcf_len]
    ja 7f
    lea rdi, [rip + lcf_line]
    add rdi, r13
    mov rdx, r12
    mov rcx, rsi
    call str_eq
    test eax, eax
    jz 7f
    mov rax, [rip + lcf_text + SB_len]
    mov [rip + nl_caret], rax
    lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_line]
    mov rdx, [rip + nl_ind]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, ' '
    call sb_push_byte
    mov eax, 2
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
3:  # MIDDLE (and not END): " MIDDLE " again under it
    lea r12, [r14 + LC_doc + 2 * LCT_SIZE]
    call .Lnd_at
    test eax, eax
    jnz 8f
    lea r12, [r14 + LC_doc + LCT_SIZE]
    call .Lnd_at
    test eax, eax
    jz 8f
    movzx eax, byte ptr [r12 + LCT_len]
    add rax, [rip + nl_ind]
    cmp [rip + nl_c], rax
    jb 8f
    lea rdi, [rip + lcf_text]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_line]
    mov rdx, [rip + nl_ind]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov rsi, r12
    movzx edx, byte ptr [r12 + LCT_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, ' '
    call sb_push_byte
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# .Lnd_at (r12 a token) -> eax 1 when the line has it at its indentation
.Lnd_at:
    movzx esi, byte ptr [r12 + LCT_len]
    test esi, esi
    jz 1f
    mov rax, [rip + nl_ind]
    add rax, rsi
    cmp rax, [rip + lcf_len]
    ja 1f
    lea rdi, [rip + lcf_line]
    add rdi, [rip + nl_ind]
    mov rdx, r12
    mov rcx, rsi
    jmp str_eq
1:  xor eax, eax
    ret

# .Lnl_outdent: when the text before the caret is the indentation and one closing or middle token
#   whose indentation is untouched, the line loses one unit: the replacement starts at the line's
#   start with the outdented line, and lcf_cind is that indentation
.Lnl_outdent:
    PROLOGUE
    mov rdi, [rip + nl_ind]
    mov rsi, [rip + nl_c]
    call lcf_tokens
    cmp qword ptr [rip + lcf_ntok], 1
    jne 9f
    lea rax, [rip + lcf_toks]
    mov ecx, [rax]
    add ecx, [rax + 4]
    cmp rcx, [rip + nl_c]
    jne 9f
    cmp qword ptr [rip + nl_ind], 0
    je 9f
    lea rdi, [r14 + LC_close]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jnz 1f
    lea rdi, [r14 + LC_middle]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jz 9f
1:  # the token, kept before the previous line is read
    mov rcx, [rip + nl_c]
    sub rcx, [rip + nl_ind]
    cmp rcx, IND_MAX
    ja 9f
    mov [rip + lcf_save_len], rcx
    lea rdi, [rip + lcf_save]
    lea rsi, [rip + lcf_line]
    add rsi, [rip + nl_ind]
    mov rdx, rcx
    call memcpy
    mov rdi, rbx
    mov rsi, [rip + nl_line]
    call lcf_untouched
    mov r12d, eax
    # the line again (lcf_untouched read another)
    mov rdi, rbx
    mov rsi, [rip + nl_line]
    mov rdx, -1
    call lcf_load
    test r12d, r12d
    jz 9f
    mov rdx, [rip + lcf_tgt_len]
    mov [rip + lcf_cind_len], rdx
    lea rdi, [rip + lcf_cind]
    lea rsi, [rip + lcf_eind]
    call memcpy
    # the replacement: the outdented line up to the caret
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_cind]
    mov rdx, [rip + lcf_cind_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_save]
    mov rdx, [rip + lcf_save_len]
    call sb_push
    mov rax, [rip + nl_c]
    mov [rip + nl_del], rax
9:  EPILOGUE

# ---------------------------------------------------------------- typing

# FN lc_type(doc, start, end, scalar, LTP*) -> eax LTP_kind: what typing the character does
#   LTK_PLAIN: insert it; LTK_PAIR: insert it and LTP_close after the caret; LTK_OVER: move over
#   the next byte; LTK_WRAP: LTP_close's byte after the selection and the character before it;
#   LTK_OUTDENT: put LTP_text (the line one unit less, then the character) in place of
#   [LTP_from, end)
FN lc_type
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15, r8
    mov dword ptr [r15 + LTP_kind], LTK_PLAIN
    mov rdi, rbx
    call lc_for_doc
    mov [rip + lcf_lc], rax
    mov [rsp], rax
    cmp r14d, 0x80
    jae 9f
    cmp r12, r13
    je 2f
    # a selection: a surrounding pair wraps it
    cmp dword ptr [rip + cfg_auto_pairs], 0
    je 9f
    mov rax, [rsp]
    xor ecx, ecx
1:  cmp rcx, [rax + LC_nsur]
    jae 9f
    movzx edx, byte ptr [rax + LC_sur + rcx*2]
    cmp edx, r14d
    je 11f
    inc rcx
    jmp 1b
11: movzx edx, byte ptr [rax + LC_sur + rcx*2 + 1]
    mov [r15 + LTP_close], dl
    mov dword ptr [r15 + LTP_clen], 1
    mov dword ptr [r15 + LTP_kind], LTK_WRAP
    jmp 9f
2:  cmp dword ptr [rip + cfg_auto_pairs], 0
    je 3f
    # a closer already there is typed over
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    cmp eax, r14d
    jne 3f
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    call lcf_close_at
    test eax, eax
    jz 3f
    mov dword ptr [r15 + LTP_kind], LTK_OVER
    jmp 9f
3:  mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    mov rcx, r15
    call lcf_outdent_typed
    test eax, eax
    jz 4f
    mov dword ptr [r15 + LTP_kind], LTK_OUTDENT
    jmp 9f
4:  cmp dword ptr [rip + cfg_auto_pairs], 0
    je 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    call lcf_autoclose
    test rax, rax
    jz 9f
    movzx ecx, byte ptr [rax + LCP_clen]
    mov [r15 + LTP_clen], ecx
    mov rdx, [rax + LCP_close]
    mov [r15 + LTP_close], rdx
    mov dword ptr [r15 + LTP_kind], LTK_PAIR
9:  mov eax, [r15 + LTP_kind]
    EPILOGUE

# lcf_doc_eq(doc, pos, ptr, len) -> eax 1 when the document has those bytes at pos
lcf_doc_eq:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor r15d, r15d
1:  cmp r15, r14
    jae 2f
    mov rdi, rbx
    lea rsi, [r12 + r15]
    call doc_byte
    cmp al, [r13 + r15]
    jne 8f
    inc r15
    jmp 1b
2:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_close_at(doc, pos, byte) -> eax 1 when a pair's CLOSE starting with byte is at pos
lcf_close_at:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, [rip + lcf_lc]
    xor r15d, r15d
1:  cmp r15, [r14 + LC_np]
    jae 8f
    imul rax, r15, LCP_SIZE
    lea rcx, [r14 + LC_pairs + rax]
    inc r15
    movzx eax, byte ptr [rcx + LCP_close]
    cmp eax, r13d
    jne 1b
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rcx + LCP_close]
    movzx ecx, byte ptr [rcx + LCP_clen]
    call lcf_doc_eq
    test eax, eax
    jz 1b
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_closer_byte(byte) -> eax 1 when it starts the CLOSE of a pair that is not a quote
lcf_closer_byte:
    mov r8, [rip + lcf_lc]
    xor ecx, ecx
1:  cmp rcx, [r8 + LC_np]
    jae 8f
    imul rax, rcx, LCP_SIZE
    lea rax, [r8 + LC_pairs + rax]
    inc rcx
    movzx edx, byte ptr [rax + LCP_close]
    cmp edx, edi
    jne 1b
    mov rdx, [rax + LCP_open]
    cmp rdx, [rax + LCP_close]
    je 1b
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# lcf_in_code(doc, pos) -> eax 1 when a character typed at pos would be code, not inside a string or
#   a comment
lcf_in_code:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r14, r12
    sub r14, rax
    cmp r14, LINE_MAX - 2
    jae 7f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call lcf_load
    # a neutral byte after the text before pos: its class says
    mov rax, [rip + lcf_len]
    lea rcx, [rip + lcf_line]
    mov byte ptr [rcx + rax], 'a'
    inc rax
    mov [rip + lcf_len], rax
    push r12
    push r12
    mov r12, r13
    call lcf_classes
    pop r12
    pop r12
    mov rdi, [rip + lcf_len]
    dec rdi
    call lcf_code
    EPILOGUE
7:  mov eax, 1
    EPILOGUE

# lcf_autoclose(doc, pos, byte) -> rax the pair typing byte at pos opens (and closes), or 0
lcf_autoclose:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, [rip + lcf_lc]
    xor r15d, r15d              # the best pair
    mov qword ptr [rsp], 0
1:  mov rax, [rsp]
    cmp rax, [r14 + LC_np]
    jae 3f
    imul rcx, rax, LCP_SIZE
    lea rcx, [r14 + LC_pairs + rcx]
    inc qword ptr [rsp]
    movzx eax, byte ptr [rcx + LCP_olen]
    movzx edx, byte ptr [rcx + rax - 1]
    cmp edx, r13d
    jne 1b
    test r15, r15
    jz 2f
    cmp al, [r15 + LCP_olen]
    jbe 1b
2:  # the bytes before pos are the rest of OPEN
    dec rax
    cmp r12, rax
    jb 1b
    mov [rsp + 8], rcx
    mov rdi, rbx
    mov rsi, r12
    sub rsi, rax
    mov rdx, rcx
    mov rcx, rax
    call lcf_doc_eq
    test eax, eax
    jz 1b
    mov r15, [rsp + 8]
    jmp 1b
3:  test r15, r15
    jz 8f
    movzx eax, byte ptr [r15 + LCP_olen]
    mov r14, r12
    sub r14, rax
    inc r14                     # where OPEN starts
    test byte ptr [r15 + LCP_flags], LCP_CODE
    jz 4f
    mov rdi, rbx
    mov rsi, r14
    call lcf_in_code
    test eax, eax
    jz 8f
4:  # before a blank, a closer or the end
    mov rdi, rbx
    mov rsi, r12
    call doc_byte
    mov [rsp], rax
    test eax, eax
    jz 5f
    cmp eax, 10
    je 5f
    cmp eax, 13
    je 5f
    cmp eax, ' '
    je 5f
    cmp eax, 9
    je 5f
    cmp eax, ','
    je 5f
    cmp eax, ';'
    je 5f
    mov edi, eax
    call lcf_closer_byte
    test eax, eax
    jz 8f
5:  # a quote (OPEN = CLOSE) not next to a word or the same quote
    movzx eax, byte ptr [r15 + LCP_olen]
    cmp al, [r15 + LCP_clen]
    jne 7f
    mov rax, [r15 + LCP_open]
    cmp rax, [r15 + LCP_close]
    jne 7f
    mov rax, [rsp]
    mov rcx, [rip + lcf_lc]
    cmp byte ptr [rcx + LC_wchar + rax], 0
    jne 8f
    test r14, r14
    jz 7f
    mov rdi, rbx
    lea rsi, [r14 - 1]
    call doc_byte
    cmp eax, r13d
    je 8f
    mov rcx, [rip + lcf_lc]
    cmp byte ptr [rcx + LC_wchar + rax], 0
    jne 8f
7:  mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# lcf_outdent_typed(doc, pos, byte, LTP*) -> eax 1 when typing byte makes the line its indentation
#   and a closing or middle token whose indentation is untouched: LTP_from, LTP_text
lcf_outdent_typed:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], rcx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_of
    mov r14, rax                # the line
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r15, rax                # its start
    mov rax, r12
    sub rax, r15
    cmp rax, IND_MAX
    ja 8f
    mov rdi, rbx
    mov rsi, r14
    mov rdx, -1
    call lcf_load
    mov rax, r12
    sub rax, r15
    cmp rax, [rip + lcf_len]
    ja 8f
    # nothing but blanks after pos
    lea rdi, [rip + lcf_line]
    add rdi, rax
    mov rsi, [rip + lcf_len]
    sub rsi, rax
    call trim
    test rdx, rdx
    jnz 8f
    call lcf_indent
    mov rcx, r12
    sub rcx, r15
    cmp rax, rcx
    cmova rax, rcx
    test rax, rax
    jz 8f                       # nothing to lose
    mov [rip + lcf_cind_len], rax
    mov rdx, [rip + lcf_lc]
    cmp byte ptr [rdx + LC_wchar + r13], 0
    jne 2f
    # a word, then a character that ends it
    mov rdi, rax
    mov rsi, r12
    sub rsi, r15
    cmp rdi, rsi
    jae 2f
    call lcf_tokens
    cmp qword ptr [rip + lcf_ntok], 1
    jne 2f
    lea rax, [rip + lcf_toks]
    cmp dword ptr [rax + 8], 0
    je 2f
    mov ecx, [rax]
    add ecx, [rax + 4]
    mov rdx, r12
    sub rdx, r15
    cmp rcx, rdx
    jne 2f
    call .Lot_listed
    test eax, eax
    jnz 5f
2:  # or punctuation the character completes: the line with it appended
    mov rax, r12
    sub rax, r15
    lea rcx, [rip + lcf_line]
    mov [rcx + rax], r13b
    inc rax
    mov [rip + lcf_len], rax
    push r12
    push r12
    mov r12, r14
    call lcf_classes
    pop r12
    pop r12
    mov rdi, [rip + lcf_cind_len]
    mov rsi, [rip + lcf_len]
    call lcf_tokens
    cmp qword ptr [rip + lcf_ntok], 1
    jne 8f
    lea rax, [rip + lcf_toks]
    cmp dword ptr [rax + 8], 0
    jne 8f
    mov ecx, [rax]
    add ecx, [rax + 4]
    cmp rcx, [rip + lcf_len]
    jne 8f
    call .Lot_listed
    test eax, eax
    jz 8f
    # (the token without the character, kept below)
    dec qword ptr [rip + lcf_len]
5:  # the indentation and the token, kept before the previous line is read
    lea rdi, [rip + lcf_cind]
    lea rsi, [rip + lcf_line]
    mov rdx, [rip + lcf_cind_len]
    call memcpy
    mov rcx, r12
    sub rcx, r15
    sub rcx, [rip + lcf_cind_len]
    mov [rip + lcf_save_len], rcx
    lea rdi, [rip + lcf_save]
    lea rsi, [rip + lcf_line]
    add rsi, [rip + lcf_cind_len]
    mov rdx, rcx
    call memcpy
    mov rdi, rbx
    mov rsi, r14
    call lcf_untouched
    test eax, eax
    jz 8f
    call lcf_text_reset
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_eind]
    mov rdx, [rip + lcf_tgt_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    lea rsi, [rip + lcf_save]
    mov rdx, [rip + lcf_save_len]
    call sb_push
    lea rdi, [rip + lcf_text]
    mov esi, r13d
    call sb_push_byte
    mov rcx, [rsp]
    mov [rcx + LTP_from], r15
    mov rax, [rip + lcf_text + SB_ptr]
    mov [rcx + LTP_text], rax
    mov rax, [rip + lcf_text + SB_len]
    mov [rcx + LTP_tlen], rax
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
# .Lot_listed -> eax 1 when the one token is a closing or middle one
.Lot_listed:
    push rbx
    mov rbx, [rip + lcf_lc]
    lea rdi, [rbx + LC_close]
    xor esi, esi
    call lcf_tok_in
    test eax, eax
    jnz 1f
    lea rdi, [rbx + LC_middle]
    xor esi, esi
    call lcf_tok_in
1:  pop rbx
    ret

# FN lc_pair_around(doc, pos) -> rax OPEN's length, rdx CLOSE's: an empty auto-closing pair around
#   pos (Backspace deletes both), else 0
FN lc_pair_around
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    call lc_for_doc
    mov r13, rax
    xor r14d, r14d              # index
    xor r15d, r15d              # the best pair
1:  cmp r14, [r13 + LC_np]
    jae 3f
    imul rax, r14, LCP_SIZE
    lea rcx, [r13 + LC_pairs + rax]
    inc r14
    movzx eax, byte ptr [rcx + LCP_olen]
    cmp r12, rax
    jb 1b
    test r15, r15
    jz 2f
    cmp al, [r15 + LCP_olen]
    jbe 1b
2:  mov [rsp], rcx
    mov rdi, rbx
    mov rsi, r12
    sub rsi, rax
    mov rdx, rcx
    mov rcx, rax
    call lcf_doc_eq
    test eax, eax
    jz 1b
    mov rcx, [rsp]
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rcx + LCP_close]
    movzx ecx, byte ptr [rcx + LCP_clen]
    call lcf_doc_eq
    test eax, eax
    jz 1b
    mov r15, [rsp]
    jmp 1b
3:  xor eax, eax
    xor edx, edx
    test r15, r15
    jz 9f
    movzx eax, byte ptr [r15 + LCP_olen]
    movzx edx, byte ptr [r15 + LCP_clen]
9:  EPILOGUE

# ---------------------------------------------------------------- comments, brackets, folding

# FN lc_line_comment(doc) -> rax the line comment token, rdx its length (0: none)
FN lc_line_comment
    sub rsp, 8
    call lc_for_doc
    movzx edx, byte ptr [rax + LC_cmt + LCT_len]
    add rax, LC_cmt
    add rsp, 8
    ret

# FN lc_block_comment(doc) -> rax START, rdx its length, rcx END, r8 its length (rdx 0: none)
FN lc_block_comment
    sub rsp, 8
    call lc_for_doc
    xor edx, edx
    cmp qword ptr [rax + LC_hasblk], 0
    je 1f
    lea rcx, [rax + LC_blk + LCT_SIZE]
    movzx r8d, byte ptr [rcx + LCT_len]
    movzx edx, byte ptr [rax + LC_blk + LCT_len]
    add rax, LC_blk
1:  add rsp, 8
    ret

# FN lc_bracket_str(doc) -> rax its bracket pairs, "()[]{}", NUL-ended (Match brackets)
FN lc_bracket_str
    sub rsp, 8
    call lc_for_doc
    add rax, LC_br
    add rsp, 8
    ret

# FN lc_fold_kind(doc) -> eax 0 brackets, 1 indent (fold = ...)
FN lc_fold_kind
    sub rsp, 8
    call lc_for_doc
    mov eax, [rax + LC_fold]
    add rsp, 8
    ret

# FN lc_fold_marker(doc, line) -> eax 1 when the line starts a marker region (fold_markers START,
#   after its indentation and optionally the line comment token), 2 when it ends one, else 0
FN lc_fold_marker
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call lc_for_doc
    mov r13, rax
    cmp qword ptr [r13 + LC_hasfm], 0
    je 8f
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    call doc_line_end
    mov rdx, rax
    sub rdx, r14
    cmp rdx, 255
    jbe 1f
    mov edx, 255
1:  mov r15, rdx
    mov rdi, rbx
    mov rsi, r14
    lea rcx, [rip + lcf_line]
    call doc_copy
    lea rdi, [rip + lcf_line]
    mov rsi, r15
    call trim
    mov r14, rax
    mov r15, rdx
    # the line comment token and blanks before it
    movzx ecx, byte ptr [r13 + LC_cmt + LCT_len]
    test ecx, ecx
    jz 3f
    mov rdi, r14
    mov rsi, r15
    lea rdx, [r13 + LC_cmt]
    call str_starts
    test eax, eax
    jz 3f
    movzx ecx, byte ptr [r13 + LC_cmt + LCT_len]
    lea rdi, [r14 + rcx]
    mov rsi, r15
    sub rsi, rcx
    call trim
    mov r14, rax
    mov r15, rdx
3:  mov rdi, r14
    mov rsi, r15
    lea rdx, [r13 + LC_fm]
    movzx ecx, byte ptr [r13 + LC_fm + LCT_len]
    call str_starts
    test eax, eax
    jnz 4f
    mov rdi, r14
    mov rsi, r15
    lea rdx, [r13 + LC_fm + LCT_SIZE]
    movzx ecx, byte ptr [r13 + LC_fm + LCT_SIZE + LCT_len]
    call str_starts
    test eax, eax
    jz 8f
    mov eax, 2
    EPILOGUE
4:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------------------------------------------------------- print-langconf

# FN langconf_dump(out sb, doc): the document's merged keys, a line each: "KEY=VALUE source=default|
#   grammar|user|ext:OWNER/NAME"
FN langconf_dump
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    call lc_for_doc
    mov r13, rax
    xor ebx, ebx
1:  cmp ebx, LCK_COUNT
    jae 9f
    mov rdi, r12
    lea rax, [rip + lck_names]
    mov rsi, [rax + rbx*8]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '='
    call sb_push_byte
    mov rsi, [r13 + LC_val + rbx*8]
    test rsi, rsi
    jz 2f
    mov rdi, r12
    call sb_push_cstr
2:  mov rdi, r12
    lea rsi, [rip + .Ld_source]
    call sb_push_cstr
    mov rax, [r13 + LC_src + rbx*8]
    lea rcx, [rip + src_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    cmp qword ptr [r13 + LC_src + rbx*8], 3
    jne 3f
    mov r14, [r13 + LC_srcext + rbx*8]
    mov rdi, r12
    mov rsi, [r14 + EXT_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '/'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + EXT_name]
    call sb_push_cstr
3:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc ebx
    jmp 1b
9:  EPILOGUE

.section .rodata
.p2align 3
lck_names:
    .quad .Lk0, .Lk1, .Lk2, .Lk3, .Lk4, .Lk5, .Lk6, .Lk7, .Lk8, .Lk9, .Lk10, .Lk11
    .quad .Lk12, .Lk13, .Lk14, .Lk15
src_names: .quad .Ls0, .Ls1, .Ls2, .Ls3
.Lk0: .asciz "brackets"
.Lk1: .asciz "autoclose"
.Lk2: .asciz "autoclose_code"
.Lk3: .asciz "surround"
.Lk4: .asciz "indent_open"
.Lk5: .asciz "indent_close"
.Lk6: .asciz "indent_middle"
.Lk7: .asciz "indent_dedent_after"
.Lk8: .asciz "continue"
.Lk9: .asciz "doc_block"
.Lk10: .asciz "fold"
.Lk11: .asciz "fold_markers"
.Lk12: .asciz "comment"
.Lk13: .asciz "block"
.Lk14: .asciz "ident"
.Lk15: .asciz "colon_indent"
.Ls0: .asciz "default"
.Ls1: .asciz "grammar"
.Ls2: .asciz "user"
.Ls3: .asciz "ext:"
.Ld_source: .asciz " source="
.Ld_autoclose: .asciz "( ) [ ] { } \" \" ' ' ` `"
.Ld_code: .asciz "\" ' `"
.Ld_brackets: .asciz "() [] {}"
.Ld_open: .asciz "{ ( ["
.Ld_colon: .asciz ":$"
.Ld_close: .asciz "} ) ]"
.Lv_indent: .asciz "indent"
.Lv_brackets: .asciz "brackets"
.Lv_yes: .asciz "yes"
.Lv_no: .asciz "no"
.Llanguage_dot: .asciz "language."
.Lp_name: .asciz "a language name is 1 to 64 bytes"
.Lp_key: .asciz "not a language key"
.Lp_value: .asciz "not a value this key takes"
.Lp_also: .asciz "also set by "
.Lp_open: .asciz "["
.Lp_close: .asciz "] "
.Lp_colon: .asciz ": "
