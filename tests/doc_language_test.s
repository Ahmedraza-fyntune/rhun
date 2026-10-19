# Owned grammar lifetime, manual intent and lazy catalog refresh without app initialization.
.include "rhun.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
dlt_rows: .zero 16
dlt_live: .quad 0
.text
dlt_bad:
    mov edi, 73
    call sys_exit

# Parse one private GP with its own independently owned package lifetime.
dlt_parse:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz dlt_bad
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call grammar_parse_prepare
    test rax, rax
    jz dlt_bad
    mov r14, rax
    mov rdi, r13
    call ext_prepare_owner_release
    test rax, rax
    jnz dlt_bad
    mov rax, r14
    EPILOGUE

FN main
    PROLOGUE 32
    mov rax, [rip + g_mem_live]
    mov [rip + dlt_live], rax
    lea rdi, [rip + dlt_alpha]
    mov esi, dlt_alpha_end - dlt_alpha
    call dlt_parse
    mov r12, rax
    lea rcx, [rax + GP_gr]
    mov [rip + dlt_rows], rcx
    lea rdi, [rip + dlt_beta]
    mov esi, dlt_beta_end - dlt_beta
    call dlt_parse
    mov r13, rax
    lea rcx, [rax + GP_gr]
    mov [rip + dlt_rows + 8], rcx
    lea rax, [rip + dlt_rows]
    mov [rip + g_grammars + VEC_ptr], rax
    mov qword ptr [rip + g_grammars + VEC_len], 2
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
    lea rax, [r12 + GP_gr]
    cmp [rbx + DOC_lang], rax
    jne dlt_bad
    cmp qword ptr [r12 + PO_refs], 2
    jne dlt_bad
    # A no-op does not retain twice or invalidate syntax state.
    mov r14, [rbx + DOC_language_revision]
    mov rdi, rbx
    mov rsi, rax
    call doc_set_grammar
    cmp [rbx + DOC_language_revision], r14
    jne dlt_bad
    cmp qword ptr [r12 + PO_refs], 2
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
    mov qword ptr [r13 + PO_refs], -1
    mov rdi, rbx
    mov esi, DL_NAMED
    lea rdx, [rip + dlt_beta_name]
    call doc_language_set
    cmp rax, -75
    jne dlt_bad
    cmp [rbx + DOC_language_name], r15
    jne dlt_bad
    cmp [rbx + DOC_language_revision], r14
    jne dlt_bad
    cmp dword ptr [rbx + DOC_language_mode], DL_NAMED
    jne dlt_bad
    mov qword ptr [r13 + PO_refs], 1
    # Replace the catalog reference first. DOC is now the old GP's sole owner.
    lea rdi, [rip + dlt_alpha_small]
    mov esi, dlt_alpha_small_end - dlt_alpha_small
    call dlt_parse
    mov r14, rax
    lea rcx, [rax + GP_gr]
    mov [rip + dlt_rows], rcx
    mov rdi, r12
    call grammar_prepare_release
    cmp qword ptr [r12 + PO_refs], 1
    jne dlt_bad
    call syntax_catalog_advance
    # Failed lazy synchronization cannot advance observed epoch or revision.
    mov qword ptr [r14 + PO_refs], -1
    mov r12, [rbx + DOC_language_revision]
    mov rdi, rbx
    call doc_sync_grammar
    cmp rax, -75
    jne dlt_bad
    cmp [rbx + DOC_language_revision], r12
    jne dlt_bad
    mov rax, [rip + syntax_catalog_epoch]
    cmp [rbx + DOC_language_epoch], rax
    je dlt_bad
    mov qword ptr [r14 + PO_refs], 1
    # Poison all old incremental states, then replace with a grammar with no regions.
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
    call doc_sync_grammar
    test rax, rax
    jnz dlt_bad
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
    mov rax, [rip + dlt_rows + 8]
    mov [rip + dlt_rows], rax
    mov qword ptr [rip + g_grammars + VEC_len], 1
    mov rdi, r14
    call grammar_prepare_release
    call syntax_catalog_advance
    mov rdi, rbx
    call doc_language
    test rax, rax
    jnz dlt_bad
    cmp [rbx + DOC_language_name], r15
    jne dlt_bad
    # Restore a new instance and resolve without another picker action.
    lea rdi, [rip + dlt_alpha_small]
    mov esi, dlt_alpha_small_end - dlt_alpha_small
    call dlt_parse
    mov r14, rax
    lea rcx, [rax + GP_gr]
    mov [rip + dlt_rows + 8], rcx
    mov qword ptr [rip + g_grammars + VEC_len], 2
    call syntax_catalog_advance
    mov rdi, rbx
    call doc_language
    lea rcx, [r14 + GP_gr]
    cmp rax, rcx
    jne dlt_bad
    # Recursion is an explicit failure, even at an already observed epoch.
    mov dword ptr [rbx + DOC_language_syncing], 1
    mov rdi, rbx
    call doc_sync_grammar
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
    call syntax_catalog_advance
    mov rdi, rbx
    call doc_language
    test rax, rax
    jnz dlt_bad
    # Automatic clears explicit intent and uses the live path.
    mov rdi, rbx
    mov esi, DL_AUTO
    xor edx, edx
    call doc_language_set
    test rax, rax
    jnz dlt_bad
    lea rax, [r14 + GP_gr]
    cmp [rbx + DOC_lang], rax
    jne dlt_bad
    # Revision exhaustion is sticky, while rendering ownership still changes safely.
    mov qword ptr [rbx + DOC_language_revision], -1
    mov rdi, rbx
    lea rsi, [r13 + GP_gr]
    call doc_set_grammar
    cmp qword ptr [rbx + DOC_language_revision], 0
    jne dlt_bad
    mov rdi, rbx
    lea rsi, [r14 + GP_gr]
    call doc_set_grammar
    cmp qword ptr [rbx + DOC_language_revision], 0
    jne dlt_bad
    mov qword ptr [rip + syntax_catalog_epoch], -1
    call syntax_catalog_advance
    cmp rax, -75
    jne dlt_bad
    cmp qword ptr [rip + syntax_catalog_epoch], -1
    jne dlt_bad
    mov rdi, rbx
    call doc_free
    mov rdi, r13
    call grammar_prepare_release
    mov rdi, r14
    call grammar_prepare_release
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
dlt_beta_name: .asciz "Beta"
dlt_alpha: .ascii "name = Alpha\nfiles = *.a\nregion = one ONE string\nregion = two TWO comment\nregion = three THREE string\n"
dlt_alpha_end:
dlt_alpha_small: .ascii "name = Alpha\nfiles = *.a\nkeywords = alpha\n"
dlt_alpha_small_end:
dlt_beta: .ascii "name = Beta\nfiles = *.b\nkeywords = beta\n"
dlt_beta_end:
dlt_ok: .ascii "ok document grammar ownership, intent, epochs, stale states and refcount failures\n"
dlt_ok_end:
