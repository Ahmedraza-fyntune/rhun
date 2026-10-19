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
.p2align 3
tmp: .zero SB_SIZE

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
    mov rdi, [rbx + EXT_pv_commit]
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
    test dword ptr [rbx + EXT_features], FEAT_COMMIT_MESSAGE
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
    mov rsi, [rip + cm_line + SB_ptr]
    mov rdx, [rip + cm_line + SB_len]
    mov rcx, [rip + cm_diff + SB_ptr]
    mov r8, [rip + cm_diff + SB_len]
    call extproto_host_post
    test rax, rax
    jz 7f
    mov [rip + cm_id], rax
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
    call extproto_send_cancel
1:  call forget
9:  EPILOGUE

# scmext_tick(): a starting provider is asked once it runs; a provider past its time is cancelled
FN scmext_tick
    PROLOGUE
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

# scmext_ext_gone(ext): an extension stopped: a request to it ends
FN scmext_ext_gone
    cmp [rip + cm_ext], rdi
    jne 9f
    push rbx
    mov rbx, rdi
    call forget
    lea rdi, [rip + .Lgone]
    call ai_describe
    pop rbx
9:  ret

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
.Ld_asked: .asciz " asked="
