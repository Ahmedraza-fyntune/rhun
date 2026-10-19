# Saved single-provider choices and deferred editor actions. Provider identities are always
# owner/name. An unavailable saved choice is an error, never permission to use another program.
.include "rhun.inc"

.equ PP_SYMBOLS, 3
.equ PP_RENAME, 5
.equ PP_FORMAT, 6
.equ PP_SIGNATURE, 7
.equ PP_RANGE_FORMAT, 10        # language features: range-format (langfeat.s LF_RANGEFMT)
.equ PP_TYPE_FORMAT, 11         # and type-format (langextra.s), both with the formatter's choice
.equ PP_LAST, PP_FOLDING        # PP_TOKENS..PP_FOLDING: editor presentation's (rhun.inc)
.equ PP_CHOOSING, 1
.equ PP_STARTING, 2
.equ PP_RENAMING, 3
.equ PP_ACCEPTING, 4
.equ PP_PREPARING, 5            # prepare-rename asked: the prompt waits for its answer
.equ PP_MAX_PREFS, 512

STRUCT
F PP_kind, 8
F PP_lang, 8
F PP_owner, 8
ENDSTRUCT PP_SIZE
STRUCT
F PC_ext, 8
F PC_label, 8
ENDSTRUCT PC_SIZE

.bss
.p2align 3
pp_prefs: .zero VEC_SIZE
pp_choices: .zero VEC_SIZE
pp_state: .quad 0
pp_kind: .quad 0
pp_store_only: .quad 0
pp_transfer: .quad 0
pp_doc: .quad 0
pp_doc_id: .quad 0
pp_version: .quad 0
pp_cursor: .quad 0
pp_anchor: .quad 0
pp_language_revision: .quad 0
pp_path: .quad 0
pp_language: .quad 0
pp_ext: .quad 0
pp_deadline: .quad 0

.text
# A kind name in an INI key or the control interface.
FN ext_provider_kind
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, PP_SYMBOLS
1:  lea rax, [rip + pp_names]
    mov rdx, [rax + r13*8]
    test rdx, rdx
    jz 2f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 3f
2:  inc r13
    cmp r13, PP_LAST
    jbe 1b
    xor eax, eax
    EPILOGUE
3:  mov eax, r13d
    EPILOGUE

# The qualified identifier is stored even when its extension is absent. Reject INI injection,
# bare names, empty segments and path syntax. Installed manifest names obey the same alphabet.
pp_valid_owner:
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    test rsi, rsi
    jz 8f
    cmp rsi, 201
    ja 8f
1:  cmp rcx, rsi
    jae 7f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp al, '/'
    jne 2f
    test r9d, r9d
    jz 8f
    inc r8d
    cmp r8d, 1
    ja 8f
    xor r9d, r9d
    jmp 1b
2:  inc r9d
    cmp al, '-'
    je 1b
    cmp al, '_'
    je 1b
    cmp al, '.'
    je 1b
    cmp al, '0'
    jb 8f
    cmp al, '9'
    jbe 1b
    or al, 32
    sub al, 'a'
    cmp al, 26
    jb 1b
    jmp 8f
7:  test r9d, r9d
    jz 8f
    cmp r8d, 1
    jne 8f
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# pp_find(kind, language cstr) -> preference slot, including a cleared slot, or 0. Range
# formatting (language features) uses the formatter's choice.
pp_find:
    PROLOGUE
    cmp rdi, PP_RANGE_FORMAT
    jb 0f
    cmp rdi, PP_TYPE_FORMAT     # (editor presentation's kinds follow: their own choices)
    ja 0f
    mov edi, PP_FORMAT
0:  mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
1:  cmp r14, [rip + pp_prefs + VEC_len]
    jae 8f
    imul rbx, r14, PP_SIZE
    add rbx, [rip + pp_prefs + VEC_ptr]
    inc r14
    cmp [rbx + PP_kind], r12
    jne 1b
    mov rdi, [rbx + PP_lang]
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ext_provider_set(kind, language cstr, owner cstr or 0, persist) -> 0 or -1.
# Stage one pointer while the atomic settings write runs synchronously. Roll it back on failure.
FN ext_provider_set
    PROLOGUE 16
    cmp rdi, PP_RANGE_FORMAT    # range formatting saves the formatter's choice
    jb 0f
    cmp rdi, PP_TYPE_FORMAT     # (editor presentation's kinds follow: their own choices)
    ja 0f
    mov edi, PP_FORMAT
0:  mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    cmp r12d, PP_SYMBOLS
    je 1f
    cmp r12d, PP_RENAME
    je 1f
    cmp r12d, PP_FORMAT
    je 1f
    cmp r12d, PP_SIGNATURE
    je 1f
    cmp r12d, PP_TOKENS
    jb 8f
    cmp r12d, PP_LAST
    ja 8f
1:  mov rdi, r13
    call strlen
    test rax, rax
    jz 8f
    cmp rax, 128
    ja 8f
    xor ecx, ecx
2:  cmp rcx, rax
    jae 3f
    movzx edx, byte ptr [r13 + rcx]
    inc rcx
    cmp edx, 32
    jb 8f
    cmp edx, '='
    je 8f
    cmp edx, '['
    je 8f
    cmp edx, ']'
    je 8f
    jmp 2b
3:  test r14, r14
    jz 4f
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call pp_valid_owner
    test eax, eax
    jz 8f
4:  mov rdi, r12
    mov rsi, r13
    call pp_find
    test rax, rax
    jnz 5f
    cmp qword ptr [rip + pp_prefs + VEC_len], PP_MAX_PREFS
    jae 8f
    lea rdi, [rip + pp_prefs]
    mov esi, PP_SIZE
    call vec_push
    mov rbx, rax
    mov [rbx + PP_kind], r12
    mov rdi, r13
    call dup_cstr
    mov [rbx + PP_lang], rax
    jmp 51f
5:  mov rbx, rax
51: mov rax, [rbx + PP_owner]
    mov [rsp], rax
    xor eax, eax
    test r14, r14
    jz 6f
    mov rdi, r14
    call dup_cstr
6:  mov [rbx + PP_owner], rax
    test r15, r15
    jz 7f
    call ext_settings_save
    test rax, rax
    js 61f
7:  mov rdi, [rsp]
    call mem_free
    xor eax, eax
    EPILOGUE
61: mov rdi, [rbx + PP_owner]
    call mem_free
    mov rax, [rsp]
    mov [rbx + PP_owner], rax
8:  mov rax, -1
    EPILOGUE

# Called for every settings line before interpreting it as an extension section.
FN ext_provider_load_line
    PROLOGUE 16
    mov rbx, rdi
    lea rsi, [rip + .Lproviders]
    call ini_sec_is
    test eax, eax
    jz 9f
    mov r12, [rbx + INI_key]
    xor r13d, r13d
1:  cmp r13, [rbx + INI_keylen]
    jae 8f
    cmp byte ptr [r12 + r13], '.'
    je 2f
    inc r13
    jmp 1b
2:  mov rdi, r12
    mov rsi, r13
    call ext_provider_kind
    test eax, eax
    jz 8f
    mov r14d, eax
    lea rdi, [r12 + r13 + 1]
    mov rsi, [rbx + INI_keylen]
    sub rsi, r13
    dec rsi
    call mem_dup
    mov [rsp], rax
    mov rdi, [rbx + INI_val]
    mov rsi, [rbx + INI_vallen]
    call mem_dup
    mov [rsp + 8], rax
    mov edi, r14d
    mov rsi, [rsp]
    mov rdx, rax
    xor ecx, ecx
    call ext_provider_set
    mov rdi, [rsp]
    call mem_free
    mov rdi, [rsp + 8]
    call mem_free
8:  mov eax, 1
9:  EPILOGUE

# Append the providers section to the settings writer's SB (also used by the control dump).
FN ext_provider_dump
    PROLOGUE
    mov r12, rdi
    xor r14d, r14d              # emit the section only when a saved choice exists
    xor r13d, r13d
1:  cmp r13, [rip + pp_prefs + VEC_len]
    jae 9f
    imul rbx, r13, PP_SIZE
    add rbx, [rip + pp_prefs + VEC_ptr]
    inc r13
    cmp qword ptr [rbx + PP_owner], 0
    je 1b
    test r14d, r14d
    jnz 2f
    inc r14d
    mov rdi, r12
    lea rsi, [rip + .Lsection]
    call sb_push_cstr
2:  mov rcx, [rbx + PP_kind]
    lea rax, [rip + pp_names]
    mov rsi, [rax + rcx*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, '.'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [rbx + PP_lang]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lequals]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rbx + PP_owner]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# ext_provider_forget(name cstr "owner/name"): an extension was removed: the saved choices naming it
# go, so the chooser asks again (nothing switches silently). The caller saves the file (extension
# management, remove_commit)
FN ext_provider_forget
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, [rip + pp_prefs + VEC_len]
    jae 9f
    imul rbx, r13, PP_SIZE
    add rbx, [rip + pp_prefs + VEC_ptr]
    inc r13
    mov rdi, [rbx + PP_owner]
    test rdi, rdi
    jz 1b
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [rbx + PP_owner]
    call mem_free
    mov qword ptr [rbx + PP_owner], 0
    jmp 1b
9:  EPILOGUE

# Stateless checks for automatic help. These do not disturb an explicit action's snapshot.
# pp_match_for(ext, kind, doc): valid, enabled manifest and matching provider declaration.
pp_match_for:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_is_visible
    test eax, eax
    jz 8f
    cmp dword ptr [rbx + EXT_manifest_ok], 0
    je 8f
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 8f
    lea rax, [rip + pp_patterns]
    mov rsi, [rax + r12*8]
    mov rdi, rbx
    call ext_pv                 # provider-scope's narrowed values count
    mov rdi, rax
    mov rsi, r13
    call extproto_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ext_provider_supports(ext, kind, doc) -> whether it can serve a request now.
FN ext_provider_supports
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call pp_match_for
    test eax, eax
    jz 8f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    lea rax, [rip + pp_features]
    mov esi, [rax + r12*4]
    mov rdi, rbx
    call ext_feature
    test eax, eax
    jz 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ext_provider_running(kind, doc): read-only resolution for automatic help. A competing idle or
# starting declaration makes the choice ambiguous even when only one provider is ready so far.
FN ext_provider_running
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    lea r14, [rip + .Lno_language]
    mov rdi, r13
    call doc_sync_grammar
    test rax, rax
    js 8f
    mov rdi, r13
    call doc_language
    test rax, rax
    jz 1f
    mov r14, [rax + GR_name]
1:  mov rdi, r12
    mov rsi, r14
    call pp_find
    test rax, rax
    jz 2f
    cmp qword ptr [rax + PP_owner], 0
    jne 3f
2:  mov rdi, r12
    lea rsi, [rip + .Lwildcard]
    call pp_find
    test rax, rax
    jz 4f
    cmp qword ptr [rax + PP_owner], 0
    je 4f
3:  mov r14, [rax + PP_owner]
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call ext_by_name
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call ext_provider_supports
    test eax, eax
    jz 8f
    mov rax, rbx
    EPILOGUE
4:  xor r14d, r14d
    xor r15d, r15d
    mov qword ptr [rsp], 0
5:  cmp r14, [rip + g_exts + VEC_len]
    jae 7f
    imul rbx, r14, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r14
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pp_match_for
    test eax, eax
    jz 5b
    mov eax, [rbx + EXT_status]
    cmp eax, ES_IDLE
    je 6f
    cmp eax, ES_STARTING
    je 6f
    cmp eax, ES_CRASHED
    je 6f
    cmp eax, ES_RUNNING
    jne 5b
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_provider_supports
    test eax, eax
    jz 5b
6:  inc r15
    cmp r15, 1
    ja 8f
    mov [rsp], rbx
    jmp 5b
7:  cmp r15, 1
    jne 8f
    mov rbx, [rsp]
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 8f
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ext_provider_automatic(kind, doc) -> EXT* or 0, edx: 0 absent, 1 ambiguous, 2 unavailable.
# Includes cold providers but never a program the user stopped. Does not change chooser state.
FN ext_provider_automatic
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    lea r14, [rip + .Lno_language]
    mov rdi, r13
    call doc_sync_grammar
    test rax, rax
    js 82f
    mov rdi, r13
    call doc_language
    test rax, rax
    jz 1f
    mov r14, [rax + GR_name]
1:  mov rdi, r12
    mov rsi, r14
    call pp_find
    test rax, rax
    jz 2f
    cmp qword ptr [rax + PP_owner], 0
    jne 3f
2:  mov rdi, r12
    lea rsi, [rip + .Lwildcard]
    call pp_find
    test rax, rax
    jz 4f
    cmp qword ptr [rax + PP_owner], 0
    je 4f
3:  mov r14, [rax + PP_owner]
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call ext_by_name
    test rax, rax
    jz 82f
    mov rbx, rax
    call pp_auto_eligible
    test eax, eax
    jz 82f
    mov rax, rbx
    xor edx, edx
    EPILOGUE
4:  xor r14d, r14d
    xor r15d, r15d
    mov qword ptr [rsp], 0
5:  cmp r14, [rip + g_exts + VEC_len]
    jae 7f
    imul rbx, r14, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r14
    call pp_auto_eligible
    test eax, eax
    jz 5b
    inc r15
    cmp r15, 1
    ja 81f
    mov [rsp], rbx
    jmp 5b
7:  mov rax, [rsp]
    xor edx, edx
    EPILOGUE
81: mov edx, 1
    xor eax, eax
    EPILOGUE
82: mov edx, 2
    xor eax, eax
    EPILOGUE

# Uses the resolver's callee-saved ext/kind/document, with no IO or shared query state.
pp_auto_eligible:
    push rbx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pp_match_for
    test eax, eax
    jz 8f
    mov eax, [rbx + EXT_status]
    cmp eax, ES_IDLE
    je 7f
    cmp eax, ES_STARTING
    je 7f
    cmp eax, ES_CRASHED
    je 7f
    cmp eax, ES_RUNNING
    jne 8f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_provider_supports
    pop rbx
    ret
7:  mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# A palette replacement or Escape abandons its deferred action. Transfer is set only around
# the intended chooser/prompt opening, never around arbitrary editor or extension code.
FN ext_provider_cancel
    cmp qword ptr [rip + pp_transfer], 0
    jne 9f
    mov qword ptr [rip + pp_state], 0
    mov qword ptr [rip + pp_ext], 0
9:  ret

# Validate the snapshot without dereferencing the old document until it is the live active one.
pp_context:
    PROLOGUE
    mov eax, [rip + g_focus]
    cmp qword ptr [rip + pp_state], PP_CHOOSING
    je 41f
    cmp qword ptr [rip + pp_state], PP_RENAMING
    je 42f
    cmp eax, FOCUS_EDITOR
    jne 8f
    jmp 43f
41: cmp eax, FOCUS_PALETTE
    jne 8f
    jmp 43f
42: cmp eax, FOCUS_PROMPT
    jne 8f
43:
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 8f
    cmp rbx, [rip + pp_doc]
    jne 8f
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rax, [rbx + DOC_id]
    cmp rax, [rip + pp_doc_id]
    jne 8f
    mov rax, [rbx + DOC_version]
    cmp rax, [rip + pp_version]
    jne 8f
    mov rax, [rbx + DOC_cur]
    cmp rax, [rip + pp_cursor]
    jne 8f
    mov rax, [rbx + DOC_anchor]
    cmp rax, [rip + pp_anchor]
    jne 8f
    mov rdi, rbx
    call doc_sync_grammar
    test rax, rax
    js 8f
    mov rax, [rbx + DOC_language_revision]
    test rax, rax
    jz 8f
    cmp rax, [rip + pp_language_revision]
    jne 8f
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Lempty]
1:  mov rsi, [rip + pp_path]
    call strcmp_eq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# pp_declared(ext): valid manifest with patterns matching the captured document. Status is
# deliberately separate: a disabled or user-stopped rename provider still prevents file rename.
pp_declared:
    PROLOGUE
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz 8f
    cmp dword ptr [rbx + EXT_manifest_ok], 0
    je 8f
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 8f
    mov rcx, [rip + pp_kind]
    lea rax, [rip + pp_patterns]
    mov rsi, [rax + rcx*8]
    mov rdi, rbx
    call ext_pv                 # provider-scope's narrowed values count
    mov rdi, rax
    mov rsi, [rip + pp_doc]
    call extproto_matches
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

pp_eligible:
    push rbx
    mov rbx, rdi
    call pp_declared
    test eax, eax
    jz 8f
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 8f
    mov eax, [rbx + EXT_status]
    cmp eax, ES_IDLE
    je 7f
    cmp eax, ES_STARTING
    je 7f
    cmp eax, ES_CRASHED
    je 7f
    cmp eax, ES_RUNNING
    jne 8f
    mov rcx, [rip + pp_kind]
    lea rax, [rip + pp_features]
    mov esi, [rax + rcx*4]
    mov rdi, rbx
    call ext_feature
    test eax, eax
    jz 8f
7:  mov eax, 1
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# ext_provider_begin(kind, store_only) -> handled. A zero return is reserved for F2's real
# absence of a symbol-rename declaration or preference.
FN ext_provider_begin
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    call ext_provider_cancel
    call palette_provider_close
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 8f
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 8f
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 8f
    mov rdi, rbx
    call doc_sync_grammar
    test rax, rax
    js 9f
    cmp qword ptr [rbx + DOC_language_revision], 0
    je 9f
    call langfeat_provider_cancel
    mov [rip + pp_kind], r12
    mov [rip + pp_store_only], r13
    mov [rip + pp_doc], rbx
    mov rax, [rbx + DOC_id]
    mov [rip + pp_doc_id], rax
    mov rax, [rbx + DOC_version]
    mov [rip + pp_version], rax
    mov rax, [rbx + DOC_cur]
    mov [rip + pp_cursor], rax
    mov rax, [rbx + DOC_anchor]
    mov [rip + pp_anchor], rax
    mov rax, [rbx + DOC_language_revision]
    mov [rip + pp_language_revision], rax
    mov rdi, rbx
    call doc_language
    lea r14, [rip + .Lno_language]
    test rax, rax
    jz 1f
    mov r14, [rax + GR_name]
1:  mov rdi, [rip + pp_language]
    call mem_free
    mov rdi, r14
    call dup_cstr
    mov [rip + pp_language], rax
    mov rdi, [rip + pp_path]
    call mem_free
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jnz 2f
    lea rdi, [rip + .Lempty]
2:  call dup_cstr
    mov [rip + pp_path], rax
    test r13, r13
    jnz .Lpb_choose
    # Exact language first, then wildcard. A cleared slot allows wildcard inheritance.
    mov rdi, r12
    mov rsi, [rip + pp_language]
    call pp_find
    test rax, rax
    jz 3f
    cmp qword ptr [rax + PP_owner], 0
    jne 4f
3:  mov rdi, r12
    lea rsi, [rip + .Lwildcard]
    call pp_find
    test rax, rax
    jz 5f
    cmp qword ptr [rax + PP_owner], 0
    je 5f
4:  mov r14, [rax + PP_owner]
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call ext_by_name
    test rax, rax
    jz .Lpb_unavailable
    mov r14, rax
    mov rdi, rax
    call pp_eligible
    test eax, eax
    jz .Lpb_unavailable
    jmp .Lpb_start
5:  xor r13d, r13d              # eligible count
    xor r14d, r14d              # sole eligible EXT
    xor r15d, r15d
    mov qword ptr [rsp], 0      # declaration count
6:  cmp r15, [rip + g_exts + VEC_len]
    jae 7f
    imul rbx, r15, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r15
    mov rdi, rbx
    call pp_declared
    test eax, eax
    jz 6b
    inc qword ptr [rsp]
    mov rdi, rbx
    call pp_eligible
    test eax, eax
    jz 6b
    inc r13
    mov r14, rbx
    jmp 6b
7:  cmp r13, 1
    ja .Lpb_choose
    je .Lpb_start
    cmp qword ptr [rsp], 0
    jne .Lpb_unavailable
    cmp r12, PP_RENAME
    je 8f
    lea rdi, [rip + .Lnone]
    call app_toast
    jmp 9f
.Lpb_choose:
    call pp_choose
    jmp 9f
.Lpb_start:
    mov [rip + pp_ext], r14
    mov qword ptr [rip + pp_state], PP_STARTING
    call time_ms
    add rax, EXT_HELLO_MS
    mov [rip + pp_deadline], rax
    mov rdi, r14
    call ext_start
    call ext_provider_tick
    jmp 9f
.Lpb_unavailable:
    call pp_unavailable
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# Each row owns its qualified label because ext_full_name uses shared temporary storage.
pp_choose:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + pp_choices + VEC_len]
    jae 2f
    imul rax, r12, PC_SIZE
    add rax, [rip + pp_choices + VEC_ptr]
    mov rdi, [rax + PC_label]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rip + pp_choices + VEC_len], 0
    mov qword ptr [rip + pp_transfer], 1
    mov rax, [rip + pp_kind]
    lea rcx, [rip + pp_titles]
    mov rdi, [rcx + rax*8]
    call palette_providers_open
    mov qword ptr [rip + pp_transfer], 0
    mov qword ptr [rip + pp_state], PP_CHOOSING
    xor r12d, r12d
3:  cmp r12, [rip + g_exts + VEC_len]
    jae 5f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call pp_eligible
    test eax, eax
    jz 3b
    mov rdi, rbx
    call ext_full_name
    mov rdi, rax
    call dup_cstr
    mov r13, rax
    lea rdi, [rip + pp_choices]
    mov esi, PC_SIZE
    call vec_push
    mov [rax + PC_ext], rbx
    mov [rax + PC_label], r13
    mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    mov rdx, [rbx + EXT_title]
    mov rcx, [rip + pp_choices + VEC_len]
    dec rcx
    call palette_results_add
    jmp 3b
5:  lea rdi, [rip + .Lautomatic]
    call strlen
    lea rdi, [rip + .Lautomatic]
    mov rsi, rax
    lea rdx, [rip + .Lautomatic_detail]
    mov rcx, -1
    call palette_results_add
    call palette_results_ready
    EPILOGUE

FN ext_provider_chosen
    PROLOGUE
    mov r12, rdi
    cmp qword ptr [rip + pp_state], PP_CHOOSING
    jne 9f
    mov qword ptr [rip + pp_state], PP_ACCEPTING
    call pp_context
    test eax, eax
    jz .Lpc_changed
    xor r13d, r13d
    xor r14d, r14d
    cmp r12, -1
    je 1f
    cmp r12, [rip + pp_choices + VEC_len]
    jae .Lpc_changed
    imul rax, r12, PC_SIZE
    add rax, [rip + pp_choices + VEC_ptr]
    mov r14, [rax + PC_ext]
    mov r13, [rax + PC_label]
    mov rdi, r14
    call pp_eligible
    test eax, eax
    jz .Lpc_unavailable
1:  mov rdi, [rip + pp_kind]
    mov rsi, [rip + pp_language]
    mov rdx, r13
    mov ecx, 1
    call ext_provider_set
    test rax, rax
    js .Lpc_write
    mov qword ptr [rip + pp_state], 0
    cmp r12, -1
    je .Lpc_auto
    cmp qword ptr [rip + pp_store_only], 0
    jne 9f
    mov [rip + pp_ext], r14
    mov qword ptr [rip + pp_state], PP_STARTING
    call time_ms
    add rax, EXT_HELLO_MS
    mov [rip + pp_deadline], rax
    mov rdi, r14
    call ext_start
    call ext_provider_tick
9:  EPILOGUE
.Lpc_changed:
    call pp_changed
    EPILOGUE
.Lpc_unavailable:
    call pp_unavailable
    EPILOGUE
.Lpc_write:
    call ext_provider_cancel
    lea rdi, [rip + .Lwrite_error]
    call app_toast
    EPILOGUE
.Lpc_auto:
    lea rdi, [rip + .Lauto_done]
    call app_toast
    EPILOGUE

# A rename prompt consumes its original selection once, after checking the snapshot again.
FN ext_provider_rename_take
    push rbx
    xor ebx, ebx
    cmp qword ptr [rip + pp_state], PP_RENAMING
    jne 9f
    mov qword ptr [rip + pp_state], PP_ACCEPTING
    call pp_context
    test eax, eax
    jz 8f
    mov rdi, [rip + pp_ext]
    call pp_eligible
    test eax, eax
    jz 7f
    mov rbx, [rip + pp_ext]
    jmp 9f
8:  call pp_changed
    jmp 9f
7:  call pp_unavailable
9:  call ext_provider_cancel
    mov rax, rbx
    pop rbx
    ret

FN ext_provider_tick
    PROLOGUE
    cmp qword ptr [rip + pp_state], 0
    je 9f
    call pp_context
    test eax, eax
    jz 8f
    cmp qword ptr [rip + pp_state], PP_PREPARING
    je .Lpt_preparing
    cmp qword ptr [rip + pp_state], PP_STARTING
    jne 9f
    call time_ms
    cmp rax, [rip + pp_deadline]
    jae 7f
    mov rbx, [rip + pp_ext]
    mov rdi, rbx
    call pp_eligible
    test eax, eax
    jz 7f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    mov qword ptr [rip + pp_state], 0
    cmp qword ptr [rip + pp_kind], PP_SIGNATURE
    jne 2f
    mov rdi, rbx
    call complete_signature_start
    jmp 9f
2:  cmp qword ptr [rip + pp_kind], PP_RENAME
    je 1f
    mov rdi, [rip + pp_kind]
    mov rsi, rbx
    call langfeat_provider_start
    jmp 9f
1:  # prepare-rename (protocol 1.1): the provider is asked before the prompt opens
    mov rdi, rbx
    mov esi, FEAT_PREPARE_RENAME
    call ext_feature
    test eax, eax
    jz 11f
    mov rdi, rbx
    call langfeat_prepare_send
    test eax, eax
    jz 11f
    mov qword ptr [rip + pp_state], PP_PREPARING
    jmp 9f
11: call pp_rename_prompt
9:  EPILOGUE
8:  call pp_changed
    EPILOGUE
7:  call pp_unavailable
    EPILOGUE
.Lpt_preparing:
    call langfeat_prepare_state     # 0 waiting, 1 prompt, 2 refused (said why)
    test eax, eax
    jz 9b
    cmp eax, 1
    jne 21f
    call pp_rename_prompt
    EPILOGUE
21: call ext_provider_cancel        # neither the prompt nor a file rename follows
    EPILOGUE

# pp_rename_prompt(): the new name's prompt opens; the snapshot follows what it selected
pp_rename_prompt:
    push rbx
    mov qword ptr [rip + pp_transfer], 1
    call langfeat_rename_prompt
    mov qword ptr [rip + pp_transfer], 0
    mov qword ptr [rip + pp_state], PP_RENAMING
    mov rax, [rip + pp_doc]
    mov rcx, [rax + DOC_cur]
    mov [rip + pp_cursor], rcx
    mov rcx, [rax + DOC_anchor]
    mov [rip + pp_anchor], rcx
    pop rbx
    ret

FN ext_provider_timeout
    cmp qword ptr [rip + pp_state], PP_PREPARING
    je 0f
    cmp qword ptr [rip + pp_state], PP_STARTING
    jne 1f
0:
    mov eax, 20                # also notices document changes while hello/slot waiting
    ret
1:  cmp qword ptr [rip + pp_state], 0
    je 2f
    mov eax, 50
    ret
2:  mov eax, -1
    ret

pp_changed:
    push rbx
    call ext_provider_cancel
    call palette_provider_close
    lea rdi, [rip + .Lchanged]
    call app_toast
    pop rbx
    ret
pp_unavailable:
    push rbx
    call ext_provider_cancel
    call palette_provider_close
    lea rdi, [rip + .Lunavailable]
    call app_toast
    pop rbx
    ret

FN cmd_select_default_formatter
    mov edi, PP_FORMAT
    mov esi, 1
    jmp ext_provider_begin
FN cmd_select_rename_provider
    mov edi, PP_RENAME
    mov esi, 1
    jmp ext_provider_begin
FN cmd_select_signature_provider
    mov edi, PP_SIGNATURE
    mov esi, 1
    jmp ext_provider_begin
FN cmd_select_symbol_provider
    mov edi, PP_SYMBOLS
    mov esi, 1
    jmp ext_provider_begin

.section .rodata
.Lproviders: .asciz "providers"
.Lsection: .asciz "\n[providers]\n"
.Lequals: .asciz " = "
.Lformat: .asciz "format"
.Lrename: .asciz "rename"
.Lsymbols: .asciz "symbols"
.Lsignature: .asciz "signature"
.Lempty: .asciz ""
.Lwildcard: .asciz "*"
.Lno_language: .asciz "-"
.Lformat_title: .asciz "Choose Formatter"
.Lrename_title: .asciz "Choose Rename Provider"
.Lsymbols_title: .asciz "Choose Symbol Provider"
.Lsignature_title: .asciz "Choose Signature Provider"
.Lautomatic: .asciz "Automatic"
.Lautomatic_detail: .asciz "Clear this language's choice"
.Lauto_done: .asciz "Language choice cleared. A global default may still apply."
.Lnone: .asciz "No matching provider. Install an extension for this language."
.Lunavailable: .asciz "Provider unavailable. Choose a provider or enable/restart the saved extension."
.Lchanged: .asciz "Provider action cancelled because the document changed."
.Lwrite_error: .asciz "Could not save provider choice. Check the extensions settings file."
.p2align 3
pp_names: .quad 0, 0, 0, .Lsymbols, 0, .Lrename, .Lformat, .Lsignature
    .quad 0, 0, .Lformat, .Lformat      # language features: range- and type-format share format's
    .quad .Lpp_tokens, .Lpp_inline, .Lpp_highlights, .Lpp_folding     # editor presentation
pp_patterns: .quad 0, 0, 0, EXT_pv_symbols, 0, EXT_pv_rename, EXT_pv_format, EXT_pv_signature
    .quad 0, 0, EXT_pv_range_format, EXT_pv_type_format
    .quad EXT_pv_semantic_tokens, EXT_pv_inline_complete, EXT_pv_highlights, EXT_pv_folding
pp_titles: .quad 0, 0, 0, .Lsymbols_title, 0, .Lrename_title, .Lformat_title, .Lsignature_title
    .quad 0, 0, .Lformat_title, .Lformat_title
    .quad .Lpp_tokens_title, .Lpp_inline_title, .Lpp_highlights_title, .Lpp_folding_title
pp_features: .long -1, -1, -1, FEAT_SYMBOLS, -1, FEAT_RENAME, FEAT_FORMAT, FEAT_SIGNATURE
    .long -1, -1, FEAT_PARTIAL_FORMAT, FEAT_PARTIAL_FORMAT
    .long FEAT_SEMANTIC_TOKENS, FEAT_INLINE_COMPLETE, FEAT_DOC_HIGHLIGHTS, FEAT_FOLDING_RANGES
.Lpp_tokens: .asciz "tokens"
.Lpp_inline: .asciz "inline"
.Lpp_highlights: .asciz "highlights"
.Lpp_folding: .asciz "folding"
.Lpp_tokens_title: .asciz "Choose Semantic Tokens Provider"
.Lpp_inline_title: .asciz "Choose Inline Completion Provider"
.Lpp_highlights_title: .asciz "Choose Highlights Provider"
.Lpp_folding_title: .asciz "Choose Folding Provider"
