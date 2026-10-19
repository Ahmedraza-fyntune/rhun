# A document's language: automatic detection, manual intent, refresh after the grammars change,
# stale highlighting states and revision exhaustion, without app initialization.
.include "rhun.inc"
.bss
.p2align 3
dlt_rows: .zero 16
dlt_live: .quad 0
.text
dlt_bad:
    mov edi, 73
    call sys_exit

FN main
    PROLOGUE 32
    # the grammars live as long as the process, as built-in ones do
    lea rdi, [rip + dlt_alpha]
    mov esi, dlt_alpha_end - dlt_alpha
    call grammar_parse
    mov r12, rax
    mov [rip + dlt_rows], rax
    lea rdi, [rip + dlt_beta]
    mov esi, dlt_beta_end - dlt_beta
    call grammar_parse
    mov r13, rax
    mov [rip + dlt_rows + 8], rax
    lea rdi, [rip + dlt_alpha_small]
    mov esi, dlt_alpha_small_end - dlt_alpha_small
    call grammar_parse
    mov r14, rax
    lea rax, [rip + dlt_rows]
    mov [rip + g_grammars + VEC_ptr], rax
    mov qword ptr [rip + g_grammars + VEC_len], 2
    mov rax, [rip + g_mem_live]
    mov [rip + dlt_live], rax
    call doc_new
    mov rbx, rax
    lea rdi, [rip + dlt_path]
    mov esi, 6
    call mem_dup
    mov [rbx + DOC_path], rax
    mov rdi, rbx
    call doc_sync_grammar
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_lang], r12
    jne dlt_bad
    # A no-op does not invalidate syntax state.
    mov r15, [rbx + DOC_language_revision]
    mov rdi, rbx
    mov rsi, r12
    call doc_set_grammar
    cmp [rbx + DOC_language_revision], r15
    jne dlt_bad
    # Explicit named mode has stable owned intent.
    mov rdi, rbx
    mov esi, DL_NAMED
    lea rdx, [rip + dlt_alpha_name]
    call doc_language_set
    test rax, rax
    jnz dlt_bad
    mov r15, [rbx + DOC_language_name]
    test r15, r15
    jz dlt_bad
    cmp dword ptr [rbx + DOC_language_mode], DL_NAMED
    jne dlt_bad
    # A name that is not printable text is refused and changes nothing.
    mov rdi, rbx
    mov esi, DL_NAMED
    lea rdx, [rip + dlt_bad_name]
    call doc_language_set
    cmp rax, -22
    jne dlt_bad
    cmp [rbx + DOC_language_name], r15
    jne dlt_bad
    # The grammars change: the next use resolves the intent again. Poison all old incremental
    # states first; the new grammar has no regions.
    mov [rip + dlt_rows], r14
    mov rdi, rbx
    call doc_language_refresh
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_lang], r14
    jne dlt_bad
    mov rdi, rbx
    mov rsi, r12
    call doc_set_grammar
    mov rax, [rbx + DOC_buf]
    mov dword ptr [rax], 0x0a610a61
    mov dword ptr [rax + 4], 0x0a610a61
    mov qword ptr [rbx + DOC_gs], 8
    mov qword ptr [rbx + DOC_nlines], 5
    mov rax, [rbx + DOC_lines]
    mov qword ptr [rax + 8], 2
    mov qword ptr [rax + 16], 4
    mov qword ptr [rax + 24], 6
    mov qword ptr [rax + 32], 8
    mov rax, [rbx + DOC_states]
    mov dword ptr [rax], 3
    mov dword ptr [rax + 4], 0
    mov dword ptr [rax + 8], 3
    mov dword ptr [rax + 12], 3
    mov dword ptr [rax + 16], 3
    mov qword ptr [rbx + DOC_svalid], 1
    mov qword ptr [rbx + DOC_sold], 5
    mov qword ptr [rbx + DOC_ehi], -1
    mov [rip + g_long_doc], rbx
    mov [rip + g_br_doc], rbx
    mov rdi, rbx
    call doc_language_refresh
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_lang], r14
    jne dlt_bad
    cmp qword ptr [rbx + DOC_svalid], 0
    jne dlt_bad
    cmp qword ptr [rbx + DOC_sold], 0
    jne dlt_bad
    cmp qword ptr [rip + g_long_doc], 0
    jne dlt_bad
    cmp qword ptr [rip + g_br_doc], 0
    jne dlt_bad
    mov rdi, rbx
    mov esi, 4
    call syntax_prepare
    mov rax, [rbx + DOC_states]
    cmp dword ptr [rax + 16], 0
    jne dlt_bad
    # Remove the selected named grammar. Its name survives the plain fallback.
    mov [rip + dlt_rows], r13
    mov qword ptr [rip + g_grammars + VEC_len], 1
    mov rdi, rbx
    call doc_language_refresh
    mov rdi, rbx
    call doc_language
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_language_name], r15
    jne dlt_bad
    # Restore it and resolve without another picker action.
    mov [rip + dlt_rows + 8], r14
    mov qword ptr [rip + g_grammars + VEC_len], 2
    mov rdi, rbx
    call doc_language_refresh
    mov rdi, rbx
    call doc_language
    cmp rax, r14
    jne dlt_bad
    # Recursion is an explicit failure.
    mov dword ptr [rbx + DOC_language_syncing], 1
    mov rdi, rbx
    call doc_language_refresh
    cmp rax, -16
    jne dlt_bad
    mov dword ptr [rbx + DOC_language_syncing], 0
    mov rdi, rbx
    mov esi, DL_PLAIN
    xor edx, edx
    call doc_language_set
    test rax, rax
    jnz dlt_bad
    cmp qword ptr [rbx + DOC_language_name], 0
    jne dlt_bad
    mov rdi, rbx
    call doc_language_refresh
    mov rdi, rbx
    call doc_language
    test rax, rax
    jnz dlt_bad
    # Automatic clears explicit intent and uses the path.
    mov rdi, rbx
    mov esi, DL_AUTO
    xor edx, edx
    call doc_language_set
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_lang], r14
    jne dlt_bad
    # Revision exhaustion is sticky, while the grammar still changes.
    mov qword ptr [rbx + DOC_language_revision], -1
    mov rdi, rbx
    mov rsi, r13
    call doc_set_grammar
    cmp qword ptr [rbx + DOC_language_revision], 0
    jne dlt_bad
    cmp [rbx + DOC_lang], r13
    jne dlt_bad
    mov rdi, rbx
    mov rsi, r14
    call doc_set_grammar
    cmp qword ptr [rbx + DOC_language_revision], 0
    jne dlt_bad
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_grammars + VEC_ptr], 0
    mov qword ptr [rip + g_grammars + VEC_len], 0
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + dlt_live]
    jne dlt_bad
    mov edi, 1
    lea rsi, [rip + dlt_ok]
    mov edx, dlt_ok_end - dlt_ok
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
dlt_path: .asciz "demo.a"
dlt_alpha_name: .asciz "Alpha"
dlt_bad_name: .asciz "Al\tpha"
dlt_alpha: .ascii "name = Alpha\nfiles = *.a\nregion = one ONE string\nregion = two TWO comment\nregion = three THREE string\n"
dlt_alpha_end:
dlt_alpha_small: .ascii "name = Alpha\nfiles = *.a\nkeywords = alpha\n"
dlt_alpha_small_end:
dlt_beta: .ascii "name = Beta\nfiles = *.b\nkeywords = beta\n"
dlt_beta_end:
dlt_ok: .ascii "ok document language intent, refresh, stale states and revision exhaustion\n"
dlt_ok_end:
