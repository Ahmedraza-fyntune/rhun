# A document's language: automatic, plain text or a named grammar, resolved lazily.
# DOC_language_epoch is 1 once DOC_lang follows the document's intent, 0 when it is to be resolved
# again (doc_language_refresh: the grammars or the file changed).
.include "rhun.inc"
.section .rodata
.Ldl_empty: .asciz ""
.text

# doc_set_grammar(doc, GR or 0) -> rax 0, rdx 0: the document's grammar; a change starts its
# highlighting over and tells the editor and the extensions (DOC_language_pending)
FN doc_set_grammar
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp [rbx + DOC_lang], r12
    je .Ldl_set_same
    mov [rbx + DOC_lang], r12
    mov qword ptr [rbx + DOC_svalid], 0
    mov qword ptr [rbx + DOC_sold], 0
    mov qword ptr [rbx + DOC_ehi], 0
    mov rdi, rbx
    call editor_language_changed
    cmp qword ptr [rbx + DOC_language_revision], 0
    je 6f
    inc qword ptr [rbx + DOC_language_revision]
6:  mov qword ptr [rbx + DOC_language_pending], 1
.Ldl_set_same:
    mov qword ptr [rbx + DOC_language_epoch], 1
    xor eax, eax
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
    cmp qword ptr [rdi + DOC_language_epoch], 0
    jne .Ldl_sync_same
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

# doc_language_dispose(doc): its language state, before the document is freed
FN doc_language_dispose
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_language_name]
    mov qword ptr [rbx + DOC_language_name], 0
    mov qword ptr [rbx + DOC_lang], 0
    mov qword ptr [rbx + DOC_language_epoch], 0
    call mem_free
    xor eax, eax
    EPILOGUE

# ext_validate_text(ptr, len) -> eax 1 for printable text: valid shortest UTF-8 without C0 or C1
# controls (a language name a user or an extension gives)
FN ext_validate_text
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rsi, rsi
    jz 8f
    call snippet_utf8_valid
    test eax, eax
    jz 8f
    xor r13d, r13d
1:  lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp eax, 32
    jb 8f
    cmp eax, 127
    jb 2f
    cmp eax, 160
    jb 8f
2:  add r13, rdx
    cmp r13, r12
    jb 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
