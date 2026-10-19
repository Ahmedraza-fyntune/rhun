# Document grammar ownership and lazy catalog synchronization.
.include "rhun.inc"
.data
.p2align 3
.globl syntax_catalog_epoch
syntax_catalog_epoch: .quad 1
.section .rodata
.Ldl_empty: .asciz ""
.text

# syntax_catalog_advance() -> 0/-EOVERFLOW. Caller preflights before pure publication.
FN syntax_catalog_advance
    cmp qword ptr [rip + syntax_catalog_epoch], -1
    je .Ldl_overflow
    inc qword ptr [rip + syntax_catalog_epoch]
    xor eax, eax
    ret
.Ldl_overflow:
    mov rax, -75
    ret

# doc_set_grammar(doc, borrowed current GR) -> status, post-apply cleanup diagnostic.
# A negative RAX always leaves ownership unchanged. RAX0/RDX<0 means applied.
# Selection and this call must not yield across a catalog publication.
FN doc_set_grammar
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
    test r12, r12
    jz 1f
    mov r13, [r12 + GR_owner]
1:  cmp [rbx + DOC_lang], r12
    jne 2f
    cmp [rbx + DOC_language_owner], r13
    je .Ldl_set_same
2:  test r13, r13
    jz 3f
    mov rdi, r13
    call grammar_prepare_retain
    test rax, rax
    js .Ldl_set_failed
3:  mov r14, [rbx + DOC_language_owner]
    mov [rbx + DOC_lang], r12
    mov [rbx + DOC_language_owner], r13
    mov qword ptr [rbx + DOC_svalid], 0
    mov qword ptr [rbx + DOC_sold], 0
    mov qword ptr [rbx + DOC_ehi], 0
    mov rdi, rbx
    call editor_language_changed
    cmp qword ptr [rbx + DOC_language_revision], 0
    je 6f
    inc qword ptr [rbx + DOC_language_revision]
6:  mov qword ptr [rbx + DOC_language_pending], 1
    mov rax, [rip + syntax_catalog_epoch]
    mov [rbx + DOC_language_epoch], rax
    xor edx, edx
    test r14, r14
    jz .Ldl_set_ok
    mov rdi, r14
    call grammar_prepare_release
    mov rdx, rax
.Ldl_set_ok:
    xor eax, eax
    EPILOGUE
.Ldl_set_same:
    mov rax, [rip + syntax_catalog_epoch]
    mov [rbx + DOC_language_epoch], rax
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Ldl_set_failed:
    xor edx, edx
    EPILOGUE

# Resolve borrowed DOC intent with no output or ownership changes.
dl_resolve:
    PROLOGUE
    mov rbx, rdi
    cmp esi, DL_AUTO
    je .Ldl_resolve_auto
    cmp esi, DL_PLAIN
    je .Ldl_resolve_plain
    mov r12, rdx
    mov rdi, rdx
    call strlen
    mov rdi, r12
    mov rsi, rax
    call syntax_by_name
    EPILOGUE
.Ldl_resolve_auto:
    mov rdi, rbx
    xor esi, esi
    call doc_line_text
    mov r12, rax
    mov r13, rdx
    mov rdi, [rbx + DOC_path]
    mov rax, [rbx + DOC_diff]
    test rax, rax
    jz 1f
    mov rdi, [rax + DV_path]
1:  test rdi, rdi
    jnz 2f
    lea rdi, [rip + .Ldl_empty]
2:  mov rsi, r12
    mov rdx, r13
    call syntax_detect
    EPILOGUE
.Ldl_resolve_plain:
    xor eax, eax
    EPILOGUE

# doc_sync_grammar(doc) -> 0/-errno, post-apply cleanup diagnostic.
FN doc_sync_grammar
    cmp dword ptr [rdi + DOC_language_syncing], 0
    jne .Ldl_busy
    mov rax, [rip + syntax_catalog_epoch]
    cmp [rdi + DOC_language_epoch], rax
    je .Ldl_sync_same
    PROLOGUE
    mov rbx, rdi
    mov dword ptr [rbx + DOC_language_syncing], 1
    mov esi, [rbx + DOC_language_mode]
    mov rdx, [rbx + DOC_language_name]
    call dl_resolve
    mov rdi, rbx
    mov rsi, rax
    call doc_set_grammar
    mov dword ptr [rbx + DOC_language_syncing], 0
    EPILOGUE
.Ldl_sync_same:
    xor eax, eax
    xor edx, edx
    ret
.Ldl_busy:
    mov rax, -16
    xor edx, edx
    ret

# Rendering may keep the last owned grammar on failure. This is not a freshness proof.
FN doc_language
    push rbx
    mov rbx, rdi
    call doc_sync_grammar
    mov rax, [rbx + DOC_lang]
    pop rbx
    ret

FN doc_language_refresh
    cmp dword ptr [rdi + DOC_language_syncing], 0
    jne .Ldl_busy
    mov qword ptr [rdi + DOC_language_epoch], 0
    jmp doc_sync_grammar

# doc_language_matches(live doc, captured revision) -> 1/0. Never authorizes old state on failure.
FN doc_language_matches
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 1f
    call doc_sync_grammar
    test rax, rax
    js 1f
    xor eax, eax
    cmp [rbx + DOC_language_revision], r12
    sete al
    EPILOGUE
1:  xor eax, eax
    EPILOGUE

# doc_language_set(doc, mode, bounded cstr or NULL) -> status, cleanup diagnostic.
FN doc_language_set
    cmp dword ptr [rdi + DOC_language_syncing], 0
    jne .Ldl_busy
    cmp rsi, DL_NAMED
    ja .Ldl_invalid
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
    cmp r12d, DL_NAMED
    jne .Ldl_intent_ready
    test rdx, rdx
    jz .Ldl_intent_invalid
    mov r14, rdx
    xor r15d, r15d
1:  cmp r15, 128
    ja .Ldl_intent_invalid
    cmp byte ptr [r14 + r15], 0
    je 2f
    inc r15
    jmp 1b
2:  mov rdi, r14
    mov rsi, r15
    call ext_validate_text
    test eax, eax
    jz .Ldl_intent_invalid
    mov rdi, r14
    mov rsi, r15
    call mem_dup_try
    test rax, rax
    jz .Ldl_intent_oom
    mov r13, rax
.Ldl_intent_ready:
    mov dword ptr [rbx + DOC_language_syncing], 1
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call dl_resolve
    mov rdi, rbx
    mov rsi, rax
    call doc_set_grammar
    mov dword ptr [rbx + DOC_language_syncing], 0
    test rax, rax
    js .Ldl_intent_failed
    mov [rsp], rdx
    mov rdi, [rbx + DOC_language_name]
    mov [rbx + DOC_language_name], r13
    mov [rbx + DOC_language_mode], r12d
    call mem_free
    xor eax, eax
    mov rdx, [rsp]
    EPILOGUE
.Ldl_intent_failed:
    mov [rsp], rax
    mov rdi, r13
    call mem_free
    mov rax, [rsp]
    xor edx, edx
    EPILOGUE
.Ldl_intent_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Ldl_intent_oom:
    mov rax, -12
    xor edx, edx
    EPILOGUE
.Ldl_invalid:
    mov rax, -22
    xor edx, edx
    ret

# Consume every DOC-owned language reference before freeing the document.
FN doc_language_dispose
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + DOC_language_owner]
    mov rdi, [rbx + DOC_language_name]
    mov qword ptr [rbx + DOC_language_name], 0
    mov qword ptr [rbx + DOC_language_owner], 0
    mov qword ptr [rbx + DOC_lang], 0
    mov qword ptr [rbx + DOC_language_epoch], 0
    call mem_free
    xor eax, eax
    test r12, r12
    jz 1f
    mov rdi, r12
    call grammar_prepare_release
1:  EPILOGUE
