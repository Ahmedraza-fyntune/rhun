# scmext: extensions as source control providers (protocol 1.1, docs/extensions/v1.1.md). A
# commit-message provider stands beside Claude Code, Codex and Ollama in Settings > Git > Commit message
# AI (feature commit-message); the Generate button and its cancel and keep-the-draft rules are
# commit_ai.s's. Quick-diff providers and VCS provider tabs follow below.
.include "rhun.inc"

.equ AI_PROVIDERS, 16           # extension commit-message providers listed in Settings
.equ CM_MS, 180000              # a provider's time to write a message
.equ CM_START_MS, 5000          # and to start
.equ CM_MAX, 8192               # a message, at most
.equ AI_OPTS_SIZE, 4096         # g_ai_opts

# a quickdiff request out
STRUCT
F QD_ext, 8
F QD_id, 8
F QD_doc, 8                     # the document's id (it may close meanwhile)
F QD_deadline, 8                # time_ms when rhun stops waiting (withdrawn)
ENDSTRUCT QD_SIZE
.equ QD_MS, 15000               # a provider's time for a base
.equ QD_EXT_MAX, 64             # requests out to one provider

.bss
.p2align 3
.globl g_ai_ext_name
g_ai_ext_name: .quad 0          # cstr owned: OWNER/NAME of the extension commit_ai = ext: names, or 0
cm_ext: .quad 0                 # the provider being asked, or 0
cm_id: .quad 0                  # the request rhun sent it; 0 while it starts
cm_deadline: .quad 0
cm_diff: .zero SB_SIZE          # the request's body while the provider starts
cm_line: .zero SB_SIZE
cm_pid: .long 0
qd_dirty: .long 0                   # documents may wait for a quick-diff base
qd_primed: .zero 4 * EXT_CAP        # per extension record: the process last told about the documents
.p2align 3
qd_pend: .zero VEC_SIZE             # QD records: quickdiff requests out
.p2align 3
tmp: .zero SB_SIZE
.globl g_scm_menu_target, g_scm_menu_loc
g_scm_menu_target: .zero SB_SIZE    # the last row menu's target line (scm_row_menu)
menu_path: .zero SB_SIZE            # its path in the work tree, a cstr
menu_abs_path: .zero SB_SIZE
menu_sha: .zero 72
g_scm_menu_loc: .long 0             # SL_* of the last row menu

.text

# ---------------- the providers in Settings ----------------

# scmext_ai_options(): g_ai_opts lists the built-in providers, then each installed commit-message
#   extension as "ext:OWNER/NAME" and its title; cfg_commit_ai follows the extension g_ai_ext_name
#   names (one not installed is listed by its name, so the choice survives until it is back)
FN scmext_ai_options
    PROLOGUE 16
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + ai_builtin]
    mov edx, ai_builtin_end - ai_builtin
    call sb_push
    mov r15d, 4                 # the next entry's index
    mov dword ptr [rsp], -1     # the index of g_ai_ext_name
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 5f
    cmp r15d, 4 + AI_PROVIDERS
    jae 5f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call is_commit_provider
    test eax, eax
    jz 1b
    mov rdi, rbx
    call ext_full_name
    mov r13, rax
    mov rsi, [rip + g_ai_ext_name]
    test rsi, rsi
    jz 2f
    mov rdi, r13
    call strcmp_eq
    test eax, eax
    jz 2f
    mov [rsp], r15d
2:  lea rdi, [rip + tmp]
    lea rsi, [rip + .Lext_prefix]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [rbx + EXT_title]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    inc r15d
    jmp 1b
5:  # the named one is not installed: listed by its name
    mov rsi, [rip + g_ai_ext_name]
    test rsi, rsi
    jz 6f
    cmp dword ptr [rsp], -1
    jne 6f
    mov [rsp], r15d
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lext_prefix]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, [rip + g_ai_ext_name]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [rip + g_ai_ext_name]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lmissing]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
6:  lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdx, [rip + tmp + SB_len]
    cmp rdx, AI_OPTS_SIZE
    ja 9f                       # cannot happen with AI_PROVIDERS names of 81 bytes and titles cut
    lea rdi, [rip + g_ai_opts]
    mov rsi, [rip + tmp + SB_ptr]
    call memcpy
    # the setting's value follows the name
    cmp qword ptr [rip + g_ai_ext_name], 0
    je 7f
    mov eax, [rsp]
    mov [rip + cfg_commit_ai], eax
    jmp 9f
7:  cmp dword ptr [rip + cfg_commit_ai], 4
    jb 9f
    mov dword ptr [rip + cfg_commit_ai], 0
9:  EPILOGUE

# scmext_ai_config(value ptr, len) -> eax 1 when it was an extension's ("ext:OWNER/NAME", config.s)
FN scmext_ai_config
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + g_ai_ext_name]
    call mem_free
    mov qword ptr [rip + g_ai_ext_name], 0
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lext_prefix]
    mov ecx, 4
    call str_starts
    test eax, eax
    jz 8f
    cmp r13, 4 + 81
    ja 8f
    lea rdi, [r12 + 4]
    lea rsi, [r13 - 4]
    call mem_dup
    mov [rip + g_ai_ext_name], rax
    mov dword ptr [rip + cfg_commit_ai], 4
    call scmext_ai_options
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# scmext_ai_chosen(): Settings changed cfg_commit_ai: g_ai_ext_name follows it
FN scmext_ai_chosen
    PROLOGUE
    mov rdi, [rip + g_ai_ext_name]
    call mem_free
    mov qword ptr [rip + g_ai_ext_name], 0
    cmp dword ptr [rip + cfg_commit_ai], 4
    jb 9f
    lea rdi, [rip + g_ai_opts]
    mov esi, [rip + cfg_commit_ai]
    call choice_entry
    test rax, rax
    jz 8f
    lea rdi, [rax + 4]
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov [rip + g_ai_ext_name], rax
    jmp 9f
8:  mov dword ptr [rip + cfg_commit_ai], 0
9:  EPILOGUE

# scmext_providers_changed(): extensions were found, installed or removed
FN scmext_providers_changed
    jmp scmext_ai_options

# is_commit_provider(ext) -> eax 1 when its manifest says commit_message = yes and it is installed
is_commit_provider:
    push rbx
    mov rbx, rdi
    xor eax, eax
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 9f
    mov rdi, rbx
    mov esi, EXT_pv_commit
    call ext_pv
    mov rdi, rax
    xor eax, eax
    test rdi, rdi
    jz 9f
    lea rsi, [rip + .Lyes]
    call strcmp_eq
9:  pop rbx
    ret

# scmext_ai_ext() -> rax the extension commit_ai names, or 0 (not installed)
FN scmext_ai_ext
    PROLOGUE
    xor r15d, r15d
    mov r13, [rip + g_ai_ext_name]
    test r13, r13
    jz 9f
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call is_commit_provider
    test eax, eax
    jz 1b
    mov rdi, rbx
    call ext_full_name
    mov rdi, rax
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    mov r15, rbx
9:  mov rax, r15
    EPILOGUE

# ---------------- asking a provider ----------------

# scmext_commit_begin() -> eax 1 when the provider commit_ai names can be asked (it is started when
#   idle, so that it is ready when the diff is); else 0 with g_ai_desc saying why
FN scmext_commit_begin
    PROLOGUE
    call scmext_ai_ext
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp dword ptr [rbx + EXT_disabled], 0
    jne 7f
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 1f
    cmp eax, ES_STARTING
    je 1f
    cmp eax, ES_IDLE
    je 2f
    cmp eax, ES_CRASHED
    jne 7f
2:  mov rdi, rbx
    call ext_start
1:  mov eax, 1
    EPILOGUE
7:  lea rdi, [rip + .Lstopped]
    call ai_describe
    xor eax, eax
    EPILOGUE
8:  lea rdi, [rip + .Lnot_installed]
    call ai_describe
    xor eax, eax
    EPILOGUE

# scmext_commit_request(diff ptr, len) -> eax 1 when the provider is asked (or will be once it runs):
#   "ID commit-message LEN" with BRANCH_LEN DIFF_LEN LF <BRANCH><DIFF>
FN scmext_commit_request
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call scmext_commit_cancel
    call scmext_ai_ext
    test rax, rax
    jz 8f
    mov rbx, rax
    lea rdi, [rip + cm_diff]
    call sb_clear
    lea rdi, [rip + g_branch]
    call strlen
    mov r14, rax
    lea rdi, [rip + cm_diff]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + cm_diff]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cm_diff]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + cm_diff]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cm_diff]
    lea rsi, [rip + g_branch]
    mov rdx, r14
    call sb_push
    lea rdi, [rip + cm_diff]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov [rip + cm_ext], rbx
    mov qword ptr [rip + cm_id], 0
    call time_ms
    add rax, CM_START_MS
    mov [rip + cm_deadline], rax
    call try_send
    mov eax, 1
    EPILOGUE
8:  lea rdi, [rip + .Lnot_installed]
    call ai_describe
    xor eax, eax
    EPILOGUE

# try_send(): the waiting request goes out once its provider runs and agreed commit-message
try_send:
    PROLOGUE
    mov rbx, [rip + cm_ext]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rip + cm_id], 0
    jne 9f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    FEAT_TEST rbx, FEAT_COMMIT_MESSAGE
    jz 7f
    lea rdi, [rip + cm_line]
    call sb_clear
    lea rdi, [rip + cm_line]
    lea rsi, [rip + .Lv_commit]
    call sb_push_cstr
    lea rdi, [rip + cm_line]
    mov rsi, [rip + cm_diff + SB_len]
    call sb_push_u64
    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + cm_line + SB_ptr]
    mov rcx, [rip + cm_line + SB_len]
    mov r8, [rip + cm_diff + SB_ptr]
    mov r9, [rip + cm_diff + SB_len]
    call extproto_host_send_body
    test rax, rax
    jz 7f
    mov [rip + cm_id], rax
    mov rdi, rbx
    mov rsi, rax
    mov edx, PK_COMMIT_MESSAGE
    mov ecx, QO_SCM
    call query_track
    mov eax, [rbx + EXT_pid]
    mov [rip + cm_pid], eax
    call time_ms
    add rax, CM_MS
    mov [rip + cm_deadline], rax
    mov rdi, [rbx + EXT_title]
    call describe_title
    jmp 9f
7:  call forget
    lea rdi, [rip + .Lno_feature]
    call ai_describe
    lea rdi, [rip + g_ai_desc]
    call app_toast
9:  EPILOGUE

# describe_title(title): "Generating with TITLE..."
describe_title:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lgenerating]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Ldots]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tmp + SB_ptr]
    call ai_describe
    EPILOGUE

# forget(): no request
forget:
    mov qword ptr [rip + cm_ext], 0
    mov qword ptr [rip + cm_id], 0
    ret

# scmext_commit_busy() -> eax 1 while a provider is asked or starting
FN scmext_commit_busy
    xor eax, eax
    cmp qword ptr [rip + cm_ext], 0
    setne al
    ret

# scmext_commit_cancel(): the request is withdrawn ("0 cancel ID" when it went out)
FN scmext_commit_cancel
    PROLOGUE
    mov rbx, [rip + cm_ext]
    test rbx, rbx
    jz 9f
    mov rsi, [rip + cm_id]
    test rsi, rsi
    jz 1f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1f
    mov eax, [rbx + EXT_pid]
    cmp eax, [rip + cm_pid]
    jne 1f
    mov rdi, rbx
    call query_withdraw
1:  call forget
9:  EPILOGUE

# scmext_tick(): quick-diff providers are asked; a starting commit-message provider is asked once it
#   runs; one past its time is cancelled
FN scmext_tick
    PROLOGUE
    call qd_tick
    cmp qword ptr [rip + cm_ext], 0
    je 9f
    call try_send
    cmp qword ptr [rip + cm_ext], 0
    je 9f
    call time_ms
    cmp rax, [rip + cm_deadline]
    jb 9f
    call scmext_commit_cancel
    lea rdi, [rip + .Ltimeout]
    call ai_describe
    lea rdi, [rip + g_ai_desc]
    call app_toast
9:  EPILOGUE

# scmext_reply(ext, id, ok, ptr, len) -> eax 1 when it answered rhun's commit-message (or quickdiff)
#   request; ptr/len the message, or the error's code and text
FN scmext_reply
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    call qd_reply
    test eax, eax
    jnz 8f
    cmp [rip + cm_ext], rbx
    jne 5f
    cmp [rip + cm_id], r12
    jne 5f
    call forget
    test r13d, r13d
    jz 4f
    # the message: trimmed, at most 8 KB, no control characters but tabs and line breaks
    mov rdi, r14
    mov rsi, r15
    call trim
    mov r14, rax
    mov r15, rdx
    test r15, r15
    jz 3f
    cmp r15, CM_MAX
    ja 3f
    xor ecx, ecx
1:  cmp rcx, r15
    jae 2f
    movzx eax, byte ptr [r14 + rcx]
    inc rcx
    cmp eax, 0x7f
    je 3f
    cmp eax, 0x20
    jae 1b
    cmp eax, 9
    je 1b
    cmp eax, 10
    je 1b
    cmp eax, 13
    je 1b
    jmp 3f
2:  mov rdi, r14
    mov rsi, r15
    call scm_ai_result
    lea rdi, [rip + .Lready]
    call ai_describe
    jmp 8f
3:  lea rdi, [rip + .Linvalid]
    call ai_describe
    lea rdi, [rip + g_ai_desc]
    call app_toast
    jmp 8f
4:  # an error: its text for the user
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rbx + EXT_title]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    mov rdx, r15
    cmp rdx, 200
    jbe 41f
    mov edx, 200
41: lea rdi, [rip + tmp]
    mov rsi, r14
    call sb_push
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + tmp + SB_ptr]
    call ai_describe
    lea rdi, [rip + g_ai_desc]
    call app_toast
8:  mov eax, 1
    EPILOGUE
5:  xor eax, eax
    EPILOGUE

# trim(ptr, len) -> rax, rdx without spaces, tabs and line breaks at either end
trim:
    mov rax, rdi
    mov rdx, rsi
1:  test rdx, rdx
    jz 9f
    movzx ecx, byte ptr [rax]
    call blank
    jnz 2f
    inc rax
    dec rdx
    jmp 1b
2:  movzx ecx, byte ptr [rax + rdx - 1]
    call blank
    jnz 9f
    dec rdx
    jmp 2b
9:  ret
# blank(cl) -> ZF set for a space, tab, CR or LF
blank:
    cmp cl, ' '
    je 1f
    cmp cl, 9
    je 1f
    cmp cl, 10
    je 1f
    cmp cl, 13
1:  ret

# scmext_ext_gone(ext): an extension stopped: requests to it end
FN scmext_ext_gone
    PROLOGUE
    mov rbx, rdi
    call qd_forget_ext
    cmp [rip + cm_ext], rbx
    jne 9f
    call forget
    lea rdi, [rip + .Lgone]
    call ai_describe
9:  EPILOGUE


# ---------------- quick diff (feature quickdiff) ----------------
# A provider gives a file's base text; rhun hashes it and draws the gutter marks as it does for
# HEAD (git.s, diff.s). It applies to files under a root the extension registered (scm-register),
# else to files outside a git work tree rhun runs git in. rhun asks when a document opens and after
# it is saved (DOC_qdwant, looked at in scmext_tick once the provider knows the document), and when
# the extension asks with quickdiff-refresh.

# FN scmext_qd_want(doc): ask a provider for the document's base
FN scmext_qd_want
    cmp qword ptr [rdi + DOC_path], 0
    je 9f
    mov dword ptr [rdi + DOC_qdwant], 1
    mov dword ptr [rip + qd_dirty], 1
9:  ret

# qd_tick(): providers that just started hear about every open document; documents waiting for a
#   base are asked about
qd_tick:
    PROLOGUE 16
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 3f
    cmp r12, EXT_CAP
    jae 3f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    lea r13, [rip + qd_primed]
    lea r13, [r13 + r12*4]
    inc r12
    xor eax, eax
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 2f
    FEAT_TEST rbx, FEAT_QUICKDIFF
    jz 2f
    mov eax, [rbx + EXT_pid]
2:  cmp eax, [r13]
    je 1b
    mov [r13], eax
    test eax, eax
    jz 1b
    call qd_want_all
    jmp 1b
3:  cmp dword ptr [rip + qd_dirty], 0
    je 9f
    mov dword ptr [rip + qd_dirty], 0
    xor r12d, r12d
4:  cmp r12, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, r12
    inc r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 4b
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz 4b
    cmp dword ptr [r13 + DOC_qdwant], 0
    je 4b
    mov dword ptr [r13 + DOC_qdwant], 0
    mov rdi, r13
    call qd_provider
    test rax, rax
    jz 4b
    mov rbx, rax
    # one request per document: an earlier one still out is withdrawn; a provider with too many
    # out is not asked
    mov rdi, rbx
    mov rsi, [r13 + DOC_id]
    call qd_supersede
    cmp eax, QD_EXT_MAX
    jae 4b
    # "quickdiff DOC VERSION"
    lea rdi, [rip + cm_line]
    call sb_clear
    lea rdi, [rip + cm_line]
    lea rsi, [rip + .Lv_quickdiff]
    call sb_push_cstr
    lea rdi, [rip + cm_line]
    mov rsi, [r13 + DOC_id]
    call sb_push_u64
    lea rdi, [rip + cm_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cm_line]
    mov rsi, [r13 + DOC_version]
    call sb_push_u64
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [rip + cm_line + SB_ptr]
    mov rcx, [rip + cm_line + SB_len]
    call extproto_host_send
    test rax, rax
    jz 4b                       # it does not know the document: not asked
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, rax
    mov edx, PK_QUICKDIFF
    mov ecx, QO_SCM
    call query_track
    lea rdi, [rip + qd_pend]
    mov esi, QD_SIZE
    call vec_push
    mov [rax + QD_ext], rbx
    mov rcx, [rsp]
    mov [rax + QD_id], rcx
    mov rcx, [r13 + DOC_id]
    mov [rax + QD_doc], rcx
    mov [rsp + 8], rax
    call time_ms
    add rax, QD_MS
    mov rcx, [rsp + 8]
    mov [rcx + QD_deadline], rax
    jmp 4b
9:  call qd_expire
    EPILOGUE

# qd_supersede(ext, doc id) -> eax the requests still out to the extension, after its earlier one for
#   that document was withdrawn
qd_supersede:
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    xor r14d, r14d              # the others
    xor r12d, r12d
1:  cmp r12, [rip + qd_pend + VEC_len]
    jae 9f
    imul rax, r12, QD_SIZE
    add rax, [rip + qd_pend + VEC_ptr]
    cmp [rax + QD_ext], rbx
    jne 3f
    cmp [rax + QD_doc], r13
    jne 2f
    mov rsi, [rax + QD_id]
    mov rdi, rbx
    call query_withdraw
    mov rdi, r12
    call qd_remove
    jmp 1b
2:  inc r14d
3:  inc r12
    jmp 1b
9:  mov eax, r14d
    EPILOGUE

# qd_expire(): requests past their time are withdrawn ("0 cancel ID"); what is shown stays
qd_expire:
    PROLOGUE
    cmp qword ptr [rip + qd_pend + VEC_len], 0
    je 9f
    call time_ms
    mov r13, rax
    xor r12d, r12d
1:  cmp r12, [rip + qd_pend + VEC_len]
    jae 9f
    imul rax, r12, QD_SIZE
    add rax, [rip + qd_pend + VEC_ptr]
    cmp r13, [rax + QD_deadline]
    jae 2f
    inc r12
    jmp 1b
2:  mov rdi, [rax + QD_ext]
    mov rsi, [rax + QD_id]
    call query_withdraw
    mov rdi, r12
    call qd_remove
    jmp 1b
9:  EPILOGUE

# FN scmext_timeout() -> ms until the first quick-diff request's time is up, or -1 (app_timeout)
FN scmext_timeout
    PROLOGUE
    mov eax, -1
    mov rcx, [rip + qd_pend + VEC_len]
    test rcx, rcx
    jz 9f
    mov rbx, -1
    xor edx, edx
1:  cmp rdx, rcx
    jae 2f
    imul rax, rdx, QD_SIZE
    add rax, [rip + qd_pend + VEC_ptr]
    mov rax, [rax + QD_deadline]
    cmp rax, rbx
    cmovb rbx, rax
    inc rdx
    jmp 1b
2:  call time_ms
    sub rbx, rax
    mov eax, ebx
    test rbx, rbx
    jns 9f
    xor eax, eax
9:  EPILOGUE

# qd_want_all(): every open document is to be asked about
qd_want_all:
    push rbx
    push r12
    sub rsp, 8
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, r12
    inc r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rdi, [rax + TAB_doc]
    test rdi, rdi
    jz 1b
    call scmext_qd_want
    jmp 1b
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# qd_provider(doc) -> rax the running quick-diff provider for the document, or 0: the one whose
#   registered root holds it, else the first whose patterns match a file outside rhun's git
qd_provider:
    PROLOGUE 16
    mov r13, rdi
    mov rdi, [r13 + DOC_path]
    call scm_root_ext
    mov r14, rax                # the registered root's provider, or 0
    xor r15d, r15d              # the candidate outside git
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 8f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    FEAT_TEST rbx, FEAT_QUICKDIFF
    jz 1b
    mov rdi, rbx
    mov esi, EXT_pv_quickdiff
    call ext_pv
    test rax, rax
    jz 1b
    mov rdi, rax
    mov rsi, r13
    call extproto_matches
    test eax, eax
    jz 1b
    cmp r14, rbx
    je 7f
    test r14, r14
    jnz 1b                      # another provider's root holds it
    test r15, r15
    jnz 1b
    cmp dword ptr [rip + g_git_on], 0
    je 2f
    mov rdi, [r13 + DOC_path]
    call git_rel
    test rax, rax
    jnz 1b                      # rhun's git has it
2:  mov r15, rbx
    jmp 1b
7:  mov rax, rbx
    EPILOGUE
8:  mov rax, r15
    EPILOGUE

# qd_reply(ext, id, ok, ptr, len) -> eax 1 when it answered a quickdiff request
qd_reply:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    xor ecx, ecx
1:  cmp rcx, [rip + qd_pend + VEC_len]
    jae 8f
    imul rax, rcx, QD_SIZE
    add rax, [rip + qd_pend + VEC_ptr]
    inc rcx
    cmp [rax + QD_ext], rbx
    jne 1b
    cmp [rax + QD_id], r12
    jne 1b
    push qword ptr [rax + QD_doc]
    push rax
    lea rdi, [rcx - 1]
    call qd_remove
    pop rax
    pop rdi
    call extproto_doc
    test rax, rax
    jz 9f                       # closed meanwhile
    test r13d, r13d
    jz 9f                       # an error: what is shown stays
    mov rdi, rax
    test r15, r15
    jz 2f
    mov [rdi + DOC_gext], rbx
    mov rsi, r14
    mov rdx, r15
    call git_set_base_ext
    jmp 9f
2:  call git_drop_base_ext      # "ok ID 0": no base, git's marks stay
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# qd_remove(index): out of qd_pend
qd_remove:
    push rbx
    mov rcx, [rip + qd_pend + VEC_len]
    dec rcx
    mov [rip + qd_pend + VEC_len], rcx
    cmp rdi, rcx
    jae 9f
    imul rsi, rcx, QD_SIZE
    imul rdi, rdi, QD_SIZE
    mov rax, [rip + qd_pend + VEC_ptr]
    add rsi, rax
    add rdi, rax
    mov edx, QD_SIZE
    call memcpy
9:  pop rbx
    ret

# qd_forget_ext(): rbx's quickdiff requests go, and the bases it gave (another provider is asked)
qd_forget_ext:
    push r12
    xor r12d, r12d
1:  cmp r12, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, r12
    inc r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rdi, [rax + TAB_doc]
    test rdi, rdi
    jz 1b
    cmp dword ptr [rdi + DOC_gsrc], 0
    je 1b
    cmp [rdi + DOC_gext], rbx
    jne 1b
    mov qword ptr [rdi + DOC_gext], 0
    push rdi
    call git_drop_base_ext
    pop rdi
    call scmext_qd_want
    jmp 1b
3:  xor r12d, r12d
1:  cmp r12, [rip + qd_pend + VEC_len]
    jae 9f
    imul rax, r12, QD_SIZE
    add rax, [rip + qd_pend + VEC_ptr]
    cmp [rax + QD_ext], rbx
    je 2f
    inc r12
    jmp 1b
2:  mov rdi, r12
    call qd_remove
    jmp 1b
9:  pop r12
    ret

# ID quickdiff-refresh LEN + path ("-" for all): fresh bases for the extension's documents
FN scmext_h_qd_refresh
    PROLOGUE
    call extproto_cur
    mov rbx, rax
    call extproto_req_id
    mov r12, rax
    FEAT_TEST rbx, FEAT_QUICKDIFF
    jz 7f
    call extproto_body
    mov r13, rax
    mov r14, rdx
    test r14, r14
    jz 6f
    cmp r14, 1
    jne 1f
    cmp byte ptr [r13], '-'
    jne 1f
    call qd_want_all
    jmp 5f
1:  # the open documents with that path
    xor r15d, r15d
2:  cmp r15, [rip + g_tabs + VEC_len]
    jae 5f
    mov rdi, r15
    inc r15
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 2b
    mov rbx, [rax + TAB_doc]
    test rbx, rbx
    jz 2b
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jz 2b
    call strlen
    cmp rax, r14
    jne 2b
    mov rdi, [rbx + DOC_path]
    mov rsi, r13
    mov rdx, r14
    call memeq
    test eax, eax
    jz 2b
    mov rdi, rbx
    call scmext_qd_want
    jmp 2b
5:  mov rdi, r12
    call extproto_ok
    EPILOGUE
6:  call extproto_answer_syntax
    EPILOGUE
7:  mov rdi, r12
    lea rsi, [rip + .Le_unknown]
    call extproto_error
    EPILOGUE




# ---------------- menus on source control rows ----------------
# A right press on a history commit, a file of a commit, a changed file or a change group opens its
# menu. The target is one line, as menu targets are for extensions' menu items (the contributions
# design's menu_open takes it with these location names): history_commit "commit SHA", history_file
# "commit SHA PATH", scm_resource "resource GROUP PATH", scm_group "group GROUP" (GROUP merge, staged,
# changes; PATH in the work tree). Until extension menu items exist the menus hold built-in items.

# scm_row_menu(location, sha cstr or 0, path ptr or 0, len, group, code): the menu of a row at the
#   pointer; the when-clause keys scmProvider, scmResourceGroup and scmResourceStatus describe it
FN scm_row_menu
    PROLOGUE 16
    mov [rsp], edi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15d, r8d
    mov [rsp + 4], r9d
    mov [rip + g_scm_menu_loc], edi
    mov edi, CTX_SCM_PROVIDER
    lea rsi, [rip + .Lp_git]
    mov edx, 3
    call ctx_set
    lea rax, [rip + group_names]
    mov rdi, [rax + r15*8]
    test r15d, r15d
    jnz 81f
    lea rdi, [rip + .Lempty]
81: mov rbx, rdi
    call strlen
    mov rdx, rax
    mov rsi, rbx
    mov edi, CTX_SCM_RESOURCE_GROUP
    call ctx_set
    lea rsi, [rsp + 4]
    xor edx, edx
    cmp byte ptr [rsi], 0
    je 82f
    mov edx, 1
82: mov edi, CTX_SCM_RESOURCE_STATUS
    call ctx_set
    lea rdi, [rip + g_scm_menu_target]
    call sb_clear
    lea rdi, [rip + menu_path]
    call sb_clear
    mov byte ptr [rip + menu_sha], 0
    test r12, r12
    jz 1f
    # commit SHA
    lea rdi, [rip + menu_sha]
    mov rsi, r12
    call cstr_copy_72
    lea rdi, [rip + g_scm_menu_target]
    lea rsi, [rip + .Lt_commit]
    call sb_push_cstr
    lea rdi, [rip + g_scm_menu_target]
    mov rsi, r12
    call sb_push_cstr
    jmp 2f
1:  # resource GROUP, group GROUP
    lea rsi, [rip + .Lt_resource]
    test r13, r13
    jnz 11f
    lea rsi, [rip + .Lt_group]
11: lea rdi, [rip + g_scm_menu_target]
    call sb_push_cstr
    lea rax, [rip + group_names]
    mov rsi, [rax + r15*8]
    lea rdi, [rip + g_scm_menu_target]
    call sb_push_cstr
2:  test r13, r13
    jz 3f
    lea rdi, [rip + g_scm_menu_target]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + g_scm_menu_target]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    lea rdi, [rip + menu_path]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    lea rdi, [rip + menu_path]
    xor esi, esi
    call sb_push_byte
3:  lea rdi, [rip + g_scm_menu_target]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + g_scm_menu_target + SB_len]
    mov eax, [rsp]
    lea rcx, [rip + menu_tables]
    mov rdi, [rcx + rax*8]
    test rdi, rdi
    jz 9f
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call ctx_menu_open
9:  EPILOGUE

# cstr_copy_72(dest, src): at most 71 bytes and a NUL
cstr_copy_72:
    mov ecx, 71
1:  mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz 1b
2:  mov byte ptr [rdi], 0
    ret

# the menus' items
menu_copy_sha:
    lea rdi, [rip + menu_sha]
    jmp copy_cstr
menu_copy_path:
    call menu_abs
    test rax, rax
    jz 9f
    mov rdi, rax
copy_cstr:
    push rdi
    call strlen
    pop rdi
    mov rsi, rax
    xor edx, edx
    call ed_clip_set
    jmp editor_clip_result
9:  ret
menu_open_changes:
    mov rdi, [rip + menu_path + SB_ptr]
    test rdi, rdi
    jz 9f
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    lea rdi, [rip + menu_sha]
    cmp byte ptr [rdi], 0
    jne 1f
    xor edi, edi
1:  jmp git_open_diff
9:  ret
menu_open_file:
    call menu_abs
    test rax, rax
    jz 9f
    mov rdi, rax
    jmp app_open_path
9:  ret

# menu_abs() -> the target's path made absolute (in menu_abs_path), or 0
menu_abs:
    PROLOGUE
    xor eax, eax
    mov r12, [rip + menu_path + SB_ptr]
    test r12, r12
    jz 9f
    mov rsi, [rip + g_git_root]
    test rsi, rsi
    jz 9f
    mov rdi, rsi
    mov rsi, r12
    call path_join
    mov rbx, rax
    lea rdi, [rip + menu_abs_path]
    call sb_clear
    lea rdi, [rip + menu_abs_path]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + menu_abs_path]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    call mem_free
    mov rax, [rip + menu_abs_path + SB_ptr]
9:  EPILOGUE

# scmext_dump(sb): "commit-provider=OWNER/NAME|- asked=0|1" (print-scm-ext)
FN scmext_dump
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Ld_provider]
    call sb_push_cstr
    mov rsi, [rip + g_ai_ext_name]
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + .Ldash]
1:  mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ld_asked]
    call sb_push_cstr
    xor esi, esi
    cmp qword ptr [rip + cm_ext], 0
    setne sil
    mov rdi, rbx
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ld_qd]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + qd_pend + VEC_len]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    # the last row menu's target
    mov rdi, rbx
    lea rsi, [rip + .Ld_menu]
    call sb_push_cstr
    mov eax, [rip + g_scm_menu_loc]
    lea rcx, [rip + loc_names]
    mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + g_scm_menu_target + SB_ptr]
    mov rdx, [rip + g_scm_menu_target + SB_len]
    call sb_push
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

.data
.p2align 3
.globl g_ai_opts
g_ai_opts:
ai_builtin: .asciz "off", "Off", "claude", "Claude Code", "codex", "Codex", "ollama", "Local (Ollama)"
ai_builtin_end:
    .byte 0
    .zero AI_OPTS_SIZE          # room for the extensions (g_ai_opts holds at most AI_OPTS_SIZE)

.section .rodata
.Lext_prefix: .asciz "ext:"
.Lmissing: .asciz " (not installed)"
.Lyes: .asciz "yes"
.Lv_commit: .asciz "commit-message "
.Lv_quickdiff: .asciz "quickdiff "
.Le_unknown: .asciz "unknown no such request"
.Lgenerating: .asciz "Generating with "
.Ldots: .asciz "..."
.Lcolon: .asciz ": "
.Ldash: .asciz "-"
.Lready: .asciz "Ready. Review the generated message before committing."
.Linvalid: .asciz "The extension returned an empty, oversized or invalid message. Your draft was kept."
.Ltimeout: .asciz "The extension did not answer in time. Your draft was kept."
.Lnot_installed: .asciz "The selected commit message extension is not installed."
.Lstopped: .asciz "The selected commit message extension is turned off or failed. See Extensions."
.Lno_feature: .asciz "The extension does not provide commit messages (it did not agree commit-message)."
.Lgone: .asciz "The extension stopped before answering. Your draft was kept."
.Ld_provider: .asciz "commit-provider="
.Ld_menu: .asciz "menu="
.Ld_qd: .asciz " quickdiff-pending="
.Lp_git: .asciz "git"
.Lempty: .asciz ""
.Lt_commit: .asciz "commit "
.Lt_resource: .asciz "resource "
.Lt_group: .asciz "group "
.Lg_none: .asciz "-"
.Lg_merge: .asciz "merge"
.Lg_staged: .asciz "staged"
.Lg_changes: .asciz "changes"
.Ll_none: .asciz "none"
.Ll_commit: .asciz "history_commit"
.Ll_file: .asciz "history_file"
.Ll_resource: .asciz "scm_resource"
.Ll_group: .asciz "scm_group"
.Lm_copy_sha: .asciz "Copy Commit ID"
.Lm_copy_path: .asciz "Copy Path"
.Lm_changes: .asciz "Open Changes"
.Lm_open: .asciz "Open File"
.p2align 3
group_names: .quad .Lg_none, .Lg_merge, .Lg_staged, .Lg_changes
loc_names: .quad .Ll_none, .Ll_commit, .Ll_file, .Ll_resource, .Ll_group
menu_tables: .quad 0, menu_commit, menu_file, menu_resource, 0
menu_commit: .quad .Lm_copy_sha, menu_copy_sha, 0, 0
menu_file: .quad .Lm_changes, menu_open_changes, .Lm_open, menu_open_file, .Lm_copy_path, menu_copy_path, 0, 0
menu_resource: .quad .Lm_changes, menu_open_changes, .Lm_open, menu_open_file, .Lm_copy_path, menu_copy_path, 0, 0
.Ld_asked: .asciz " asked="
