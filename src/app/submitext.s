# An extension's release into the rhun extensions index, github.com/rhun-editor/extensions
# (docs/guide.md, "Submitting to the index"): `rhun submit-extension [DIR]` in a terminal, and the
# palette's Extensions: Submit to Index... (also on a linked extension's page). One job in two steps
# (submitext_script: runtime/jobs/archive.sh and runtime/jobs/submitext.sh under sh; on Windows
# submitext_ps_script, runtime/windows/submitext.ps1): prepare reads DIR/extension.ini, the
# release's sha256sums.txt, the tag's commit and the index's entry for it if there is one; then the
# questions (the category, keywords, the maintainer, gh or the browser; an entry's answers are the
# defaults); then submit writes the entry as the index's files are written and either opens the
# pull request through gh (a fork, a branch, gh api for the file, gh pr create) or opens GitHub's
# page that proposes the file (new, or the editor of an entry that is there).
#   terminal: submitext_main(), with the questions as newext.s asks them (--category C --keywords
#     "a b" --maintainer M --gh|--browser --yes --tag vX.Y.Z answer them)
#   GUI: a five-step quick input (the folder, then the questions), prepare and submit in the
#     background, progress and the result in notifications
#   RHUN_EXT_BASE (releases, as Install from GitHub), RHUN_SUBMIT_API (https://api.github.com) and
#   RHUN_SUBMIT_RAW (https://raw.githubusercontent.com): other places, for tests; RHUN_SUBMIT_OPENER
#   a program that gets the browser's address instead of the desktop (tests)
.include "rhun.inc"

.equ SX_KEYWORDS_MAX, 300
.equ SX_OUT_MAX, 65536
.equ SX_PG_NOTE, 2              # notify.s NPW_NOTE: the progress shows as a card with Cancel
.equ SS_IDLE, 0
.equ SS_ASKING, 1
.equ SS_PREPARING, 2
.equ SS_RUNNING, 3
.equ SS_DONE, 4
.equ SS_FAILED, 5
.equ SS_CANCELLED, 6
.equ SF_CATEGORY, 1             # sx_set: answered by a flag
.equ SF_KEYWORDS, 2
.equ SF_MAINTAINER, 4
.equ SH_UNSET, 0                # sx_how
.equ SH_GH, 1
.equ SH_BROWSER, 2

.bss
.p2align 3
sx_dir: .zero 4096
sx_tag: .zero 80                # --tag, or "-"
sx_work: .zero 4096             # the prepare step's folder
sx_full: .zero 256              # OWNER/NAME
sx_tagout: .zero 80             # the tag it read
sx_category: .zero 32
sx_keywords: .zero 512
sx_maintainer: .zero 64
sx_gh: .zero 64                 # gh's login, or ""
sx_url: .zero 8192
sx_pr: .zero 1024
sx_why: .zero 1024
sx_out: .zero SB_SIZE
sx_entry: .zero SB_SIZE         # the entry's lines ("say")
sx_evq: .zero SB_SIZE           # quick input events for submitext_tick
sx_evcur: .zero SB_SIZE
sx_title: .zero 512
sx_argv: .zero 16 * 8
sx_existing: .long 0
sx_edit: .long 0                # the browser path edits the entry that is there
sx_ok: .long 0
sx_set: .long 0                 # SF_*
sx_how: .long 0                 # SH_*
sx_yes: .long 0
sx_gui: .long 0                 # lines go to the GUI (notifications), not the terminal
sx_said: .long 0
sx_step: .long 0
sx_q: .long 0
sx_seq: .long 0                 # the folder step's sequence, for prepare's error
sx_pid: .long 0
sx_pg: .long 0
sx_cancelled: .long 0
sx_jobstep: .long 0                 # 1 prepare, 2 submit
.globl g_submitext_state
g_submitext_state: .long 0      # SS_* (tests wait on it)

.data
sx_fd: .long -1

.text

# ---------------- shared ----------------

# sx_keywords_ok(cstr) -> rax 0, or why they are not the index's keywords: lowercase words
sx_keywords_ok:
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 8f
    inc ecx
    cmp ecx, SX_KEYWORDS_MAX
    ja 7f
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    jbe 1b
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 1b
    cmp edx, ' '
    je 1b
    cmp edx, '-'
    je 1b
    cmp edx, '.'
    je 1b
    cmp edx, '_'
    je 1b
    cmp edx, '+'
    je 1b
    cmp edx, '#'
    je 1b
    lea rax, [rip + .Le_keywords]
    ret
7:  lea rax, [rip + .Le_keywords_long]
    ret
8:  xor eax, eax
    ret

# sx_category_index(cstr) -> eax its index in sx_categories, -1 for none
sx_category_index:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  lea rax, [rip + sx_categories]
    mov rsi, [rax + r12*8]
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jnz 8f
    inc r12d
    cmp r12d, 8
    jb 1b
    mov eax, -1
    EPILOGUE
8:  mov eax, r12d
    EPILOGUE

# sx_env_base(name cstr, default cstr) -> the variable when it is set, else the default
sx_env_base:
    PROLOGUE
    mov rbx, rsi
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 9f
1:  mov rax, rbx
9:  EPILOGUE

# sx_reset(): the answers and what prepare read, cleared (sx_dir and sx_tag stay)
sx_reset:
    xor eax, eax
    mov [rip + sx_work], al
    mov [rip + sx_full], al
    mov [rip + sx_tagout], al
    mov [rip + sx_gh], al
    mov [rip + sx_url], al
    mov [rip + sx_pr], al
    mov [rip + sx_why], al
    mov [rip + sx_existing], eax
    mov [rip + sx_edit], eax
    mov [rip + sx_ok], eax
    mov [rip + sx_said], eax
    ret

# sx_job(step) -> rax argv, rdx envp (rax 0: no PowerShell): step 1 prepare (sx_dir, sx_tag), 2
#   submit (sx_work and the answers)
sx_job:
    PROLOGUE
    mov r12d, edi
    lea rax, [rip + .Lhow_gh]
    cmp dword ptr [rip + sx_how], SH_GH
    je 1f
    lea rax, [rip + .Lhow_browser]
1:  mov r13, rax
.ifdef WINDOWS
    call ne_env_reset
    cmp r12d, 1
    jne 2f
    lea rdi, [rip + .Lx_step]
    lea rsi, [rip + .Lprepare]
    call ne_env
    lea rdi, [rip + .Lx_dir]
    lea rsi, [rip + sx_dir]
    call ne_env
    lea rdi, [rip + .Lx_tag]
    lea rsi, [rip + sx_tag]
    call ne_env
    call ext_release_base
    lea rdi, [rip + .Lx_github]
    mov rsi, rax
    call ne_env
    lea rdi, [rip + .Lenv_api]
    lea rsi, [rip + .Lapi]
    call sx_env_base
    lea rdi, [rip + .Lx_api]
    mov rsi, rax
    call ne_env
    lea rdi, [rip + .Lenv_raw]
    lea rsi, [rip + .Lraw]
    call sx_env_base
    lea rdi, [rip + .Lx_raw]
    mov rsi, rax
    call ne_env
    jmp 3f
2:  lea rdi, [rip + .Lx_step]
    lea rsi, [rip + .Lsubmit]
    call ne_env
    lea rdi, [rip + .Lx_work]
    lea rsi, [rip + sx_work]
    call ne_env
    lea rdi, [rip + .Lx_category]
    lea rsi, [rip + sx_category]
    call ne_env
    lea rdi, [rip + .Lx_keywords]
    lea rsi, [rip + sx_keywords]
    call ne_env
    lea rdi, [rip + .Lx_maintainer]
    lea rsi, [rip + sx_maintainer]
    call ne_env
    lea rdi, [rip + .Lx_how]
    mov rsi, r13
    call ne_env
3:  lea rdi, [rip + submitext_ps_script]
    call ne_ps_job
    EPILOGUE
.else
    # sh -c SCRIPT rhun-submit-extension prepare DIR TAG GITHUB API RAW
    #                                    submit WORK CATEGORY KEYWORDS MAINTAINER HOW
    lea rbx, [rip + sx_argv]
    lea rax, [rip + .Lsh]
    mov [rbx], rax
    lea rax, [rip + .Ldash_c]
    mov [rbx + 8], rax
    lea rax, [rip + submitext_script]
    mov [rbx + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rbx + 24], rax
    mov qword ptr [rbx + 80], 0
    cmp r12d, 1
    jne 2f
    lea rax, [rip + .Lprepare]
    mov [rbx + 32], rax
    lea rax, [rip + sx_dir]
    mov [rbx + 40], rax
    lea rax, [rip + sx_tag]
    mov [rbx + 48], rax
    call ext_release_base
    mov [rbx + 56], rax
    lea rdi, [rip + .Lenv_api]
    lea rsi, [rip + .Lapi]
    call sx_env_base
    mov [rbx + 64], rax
    lea rdi, [rip + .Lenv_raw]
    lea rsi, [rip + .Lraw]
    call sx_env_base
    mov [rbx + 72], rax
    jmp 3f
2:  lea rax, [rip + .Lsubmit]
    mov [rbx + 32], rax
    lea rax, [rip + sx_work]
    mov [rbx + 40], rax
    lea rax, [rip + sx_category]
    mov [rbx + 48], rax
    lea rax, [rip + sx_keywords]
    mov [rbx + 56], rax
    lea rax, [rip + sx_maintainer]
    mov [rbx + 64], rax
    mov [rbx + 72], r13
3:  mov rax, rbx
    mov rdx, [rip + g_envp]
    EPILOGUE
.endif

# sx_value(dst, src, max, flag SF_*): a value prepare read, unless a flag answered it
sx_value:
    test [rip + sx_set], ecx
    jnz 1f
    jmp ne_copy
1:  ret

# sx_line(cstr): one line of the job (newext.s's ne_take_lines)
sx_line:
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Lj_step]
    call ne_starts
    test eax, eax
    jnz .Lsl_step
    mov rdi, rbx
    lea rsi, [rip + .Lj_say]
    call ne_starts
    test eax, eax
    jnz .Lsl_say
    mov rdi, rbx
    lea rsi, [rip + .Lj_warn]
    call ne_starts
    test eax, eax
    jnz .Lsl_warn
    mov rdi, rbx
    lea rsi, [rip + .Lj_existing]
    call strcmp_eq
    test eax, eax
    jz 11f
    mov dword ptr [rip + sx_existing], 1
    jmp 9f
11: mov rdi, rbx
    lea rsi, [rip + .Lj_edit]
    call strcmp_eq
    test eax, eax
    jz 12f
    mov dword ptr [rip + sx_edit], 1
    jmp 9f
12: mov rdi, rbx
    lea rsi, [rip + .Lj_ok]
    call strcmp_eq
    test eax, eax
    jz 13f
    mov dword ptr [rip + sx_ok], 1
    jmp 9f
13: mov rdi, rbx
    lea rsi, [rip + .Lj_gh]
    call ne_starts
    test eax, eax
    jz 14f
    mov byte ptr [rip + sx_gh], 0
    cmp word ptr [rbx + 3], '-'     # "gh -": none
    je 9f
    lea rdi, [rip + sx_gh]
    lea rsi, [rbx + 3]
    mov edx, 39
    call ne_copy
    jmp 9f
14: lea r12, [rip + sx_line_words]
1:  mov rsi, [r12]
    test rsi, rsi
    jz 9f
    mov rdi, rbx
    call ne_starts
    test eax, eax
    jnz 2f
    add r12, 24
    jmp 1b
2:  mov rdi, [r12]
    call strlen
    lea rsi, [rbx + rax]
    mov rdi, [r12 + 8]
    mov rax, [r12 + 16]
    movzx edx, ax               # its room
    shr eax, 16                 # its flag
    mov ecx, eax
    call sx_value
    jmp 9f
.Lsl_step:
    # "step N M TEXT": the terminal shows TEXT, the GUI's progress (N - 1) / M of the way
    lea r12, [rbx + 5]
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call parse_u64
    test rdx, rdx
    jz 9f
    mov r13, rax
    add r12, rdx
    inc r12
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call parse_u64
    test rdx, rdx
    jz 9f
    test rax, rax
    jz 9f
    mov r14, rax
    add r12, rdx
    cmp byte ptr [r12], ' '
    jne 9f
    inc r12
    cmp dword ptr [rip + sx_gui], 0
    jne 3f
    cmp dword ptr [rip + sx_said], 1
    jne 21f
    mov dword ptr [rip + sx_said], 2    # a blank line after the entry
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
21: mov edi, 1
    mov rsi, r12
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    jmp 9f
3:  lea rax, [r13 - 1]
    imul rax, rax, 100
    xor edx, edx
    div r14
    mov r15, rax
    mov rdi, r12
    call strlen
    mov rcx, rax
    mov edi, [rip + sx_pg]
    mov esi, r15d
    mov rdx, r12
    call progress_update
    jmp 9f
.Lsl_say:
    lea r12, [rbx + 4]
    lea rdi, [rip + sx_entry]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + sx_entry]
    mov esi, 10
    call sb_push_byte
    cmp dword ptr [rip + sx_gui], 0
    jne 9f
    cmp dword ptr [rip + sx_said], 0
    jne 4f
    mov dword ptr [rip + sx_said], 1
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
4:  mov edi, 1
    mov rsi, r12
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    jmp 9f
.Lsl_warn:
    lea r12, [rbx + 5]
    cmp dword ptr [rip + sx_gui], 0
    jne 5f
    mov edi, 2
    lea rsi, [rip + .Lwarning]
    call ne_put
    mov edi, 2
    mov rsi, r12
    call ne_put
    mov edi, 2
    lea rsi, [rip + .Lnl]
    call ne_put
    jmp 9f
5:  mov rdi, r12
    call strlen
    mov rcx, rax
    xor edi, edi
    mov esi, SEV_WARNING
    mov rdx, r12
    call notify_add
9:  EPILOGUE

# sx_drop_work(): the prepare step's folder, when one is left (only a rhun-submit- folder)
FN sx_drop_work
    PROLOGUE
    cmp byte ptr [rip + sx_work], 0
    je 9f
    lea rdi, [rip + sx_work]
    call strlen
    lea rdi, [rip + sx_work]
    mov rsi, rax
    call path_basename
    mov rdi, rax
    lea rsi, [rip + .Lwork_prefix]
    call ne_starts
    test eax, eax
    jz 8f
    lea rdi, [rip + sx_work]
    call file_missing
    test eax, eax
    jnz 8f
    lea rdi, [rip + sx_work]
    call file_remove_tree
8:  mov byte ptr [rip + sx_work], 0
9:  EPILOGUE

# sx_default_maintainer(): the maintainer, when nothing gave one: gh's login, git's github.user,
#   else the owner
sx_default_maintainer:
    PROLOGUE
    cmp byte ptr [rip + sx_maintainer], 0
    jne 9f
    lea rdi, [rip + sx_maintainer]
    lea rsi, [rip + sx_gh]
    mov edx, 39
    call ne_copy
    cmp byte ptr [rip + sx_maintainer], 0
    jne 9f
    lea rdi, [rip + sx_maintainer]
    call ne_git_owner
    cmp byte ptr [rip + sx_maintainer], 0
    jne 9f
    lea rbx, [rip + sx_full]
    xor ecx, ecx
1:  movzx eax, byte ptr [rbx + rcx]
    test eax, eax
    jz 2f
    cmp eax, '/'
    je 2f
    cmp ecx, 39
    jae 2f
    lea rdx, [rip + sx_maintainer]
    mov [rdx + rcx], al
    inc ecx
    jmp 1b
2:  lea rdx, [rip + sx_maintainer]
    mov byte ptr [rdx + rcx], 0
9:  EPILOGUE

# ---------------- the terminal ----------------

# submitext_main(): `rhun submit-extension [DIR] [flags]`; exits 0 when it is submitted (1: it
#   failed, 2: usage)
FN submitext_main
    PROLOGUE 16
    lea rax, [rip + .Lprefix]
    mov [rip + ne_prefix], rax
    lea rax, [rip + .Lusage]
    mov [rip + ne_usage], rax
    lea rax, [rip + sx_drop_work]
    mov [rip + ne_abort_fn], rax
    lea rdi, [rip + sx_tag]
    lea rsi, [rip + .Ldash]
    call cstr_copy
    mov r12, [rip + g_argv]
    mov r13, [rip + g_argc]
    mov ebx, 2
.Lsm_arg:
    cmp rbx, r13
    jae .Lsm_args_done
    mov r14, [r12 + rbx*8]
    mov rdi, r14
    lea rsi, [rip + .Lo_tag]
    call strcmp_eq
    test eax, eax
    jz 1f
    call sx_flag_value
    lea rdi, [rip + sx_tag]
    mov rsi, rax
    mov edx, 70
    call ne_copy
    jmp .Lsm_next
1:  mov rdi, r14
    lea rsi, [rip + .Lo_category]
    call strcmp_eq
    test eax, eax
    jz 2f
    call sx_flag_value
    lea rdi, [rip + sx_category]
    mov rsi, rax
    mov edx, 30
    call ne_copy
    or dword ptr [rip + sx_set], SF_CATEGORY
    jmp .Lsm_next
2:  mov rdi, r14
    lea rsi, [rip + .Lo_keywords]
    call strcmp_eq
    test eax, eax
    jz 3f
    call sx_flag_value
    lea rdi, [rip + sx_keywords]
    mov rsi, rax
    mov edx, 500
    call ne_copy
    or dword ptr [rip + sx_set], SF_KEYWORDS
    jmp .Lsm_next
3:  mov rdi, r14
    lea rsi, [rip + .Lo_maintainer]
    call strcmp_eq
    test eax, eax
    jz 4f
    call sx_flag_value
    lea rdi, [rip + sx_maintainer]
    mov rsi, rax
    mov edx, 60
    call ne_copy
    or dword ptr [rip + sx_set], SF_MAINTAINER
    jmp .Lsm_next
4:  mov rdi, r14
    lea rsi, [rip + .Lo_gh]
    call strcmp_eq
    test eax, eax
    jz 5f
    mov dword ptr [rip + sx_how], SH_GH
    jmp .Lsm_next
5:  mov rdi, r14
    lea rsi, [rip + .Lo_browser]
    call strcmp_eq
    test eax, eax
    jz 6f
    mov dword ptr [rip + sx_how], SH_BROWSER
    jmp .Lsm_next
6:  mov rdi, r14
    lea rsi, [rip + .Lo_yes]
    call strcmp_eq
    test eax, eax
    jnz 61f
    mov rdi, r14
    lea rsi, [rip + .Lo_y]
    call strcmp_eq
    test eax, eax
    jz 7f
61: mov dword ptr [rip + sx_yes], 1
    jmp .Lsm_next
7:  mov rdi, r14
    lea rsi, [rip + .Lo_help]
    call strcmp_eq
    test eax, eax
    jnz 71f
    mov rdi, r14
    lea rsi, [rip + .Lo_h]
    call strcmp_eq
    test eax, eax
    jz 72f
71: mov edi, 1
    lea rsi, [rip + .Lusage]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lusage_more]
    call ne_put
    xor edi, edi
    call sys_exit
72: cmp byte ptr [r14], '-'
    jne 73f
    lea rdi, [rip + .Le_flag]
    call ne_fail_usage
73: cmp byte ptr [rip + ne_dir], 0
    je 74f
    lea rdi, [rip + .Le_two_dirs]
    call ne_fail_usage
74: mov rdi, r14
    call strlen
    cmp rax, 3000
    jb 75f
    lea rdi, [rip + .Le_dir_long]
    call ne_fail_usage
75: lea rdi, [rip + ne_dir]
    mov rsi, r14
    call cstr_copy
.Lsm_next:
    inc rbx
    jmp .Lsm_arg
.Lsm_args_done:
    test dword ptr [rip + sx_set], SF_CATEGORY
    jz 1f
    lea rdi, [rip + sx_category]
    call sx_category_index
    test eax, eax
    jns 1f
    lea rdi, [rip + .Le_category]
    call ne_fail_usage
1:  # DIR, else the current folder, from the top
    cmp byte ptr [rip + ne_dir], 0
    jne 2f
    mov word ptr [rip + ne_dir], '.'
2:  call ne_dir_absolute
    lea rdi, [rip + sx_dir]
    lea rsi, [rip + ne_dir]
    mov edx, 4000
    call ne_copy
    # prepare
    call sx_reset
    mov edi, 1
    call sx_job
    test rax, rax
    jnz 3f
    lea rdi, [rip + .Le_no_ps]
    call sx_die
3:  mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + sx_out]
    lea rcx, [rip + sx_line]
    call ne_run_lines
    test eax, eax
    jnz .Lsm_failed
    cmp byte ptr [rip + sx_full], 0
    je .Lsm_failed
    call sx_default_maintainer
    # the questions, in a terminal unless --yes
    cmp dword ptr [rip + sx_yes], 0
    jne .Lsm_flags
    xor edi, edi
    call ne_isatty
    test eax, eax
    jz .Lsm_flags
    mov edi, 1
    call ne_isatty
    test eax, eax
    jz .Lsm_flags
    call ne_raw_begin
    test dword ptr [rip + sx_set], SF_CATEGORY
    jnz 4f
    lea rdi, [rip + sx_category]
    call sx_category_index
    mov ecx, eax
    test ecx, ecx
    jns 31f
    mov ecx, 7                  # other
31: lea rdi, [rip + .Lq_category]
    lea rsi, [rip + sx_categories]
    mov edx, 8
    call ne_ask_choice
    lea rcx, [rip + sx_categories]
    mov rsi, [rcx + rax*8]
    lea rdi, [rip + sx_category]
    call cstr_copy
4:  test dword ptr [rip + sx_set], SF_KEYWORDS
    jnz 5f
    lea rdi, [rip + .Lq_keywords]
    lea rsi, [rip + sx_keywords]
    mov edx, SX_KEYWORDS_MAX
    lea rcx, [rip + sx_keywords_ok]
    call ne_ask_text
5:  test dword ptr [rip + sx_set], SF_MAINTAINER
    jnz 6f
    lea rdi, [rip + .Lq_maintainer]
    lea rsi, [rip + sx_maintainer]
    mov edx, 39
    lea rcx, [rip + ne_owner_ok]
    call ne_ask_text
6:  cmp dword ptr [rip + sx_how], SH_UNSET
    jne 7f
    mov dword ptr [rip + sx_how], SH_BROWSER
    cmp byte ptr [rip + sx_gh], 0
    je 7f
    # "Open the pull request with gh as LOGIN"
    lea rdi, [rip + sx_title]
    lea rsi, [rip + .Lq_gh]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + sx_gh]
    call cstr_copy
    lea rdi, [rip + sx_title]
    lea rsi, [rip + .Lc_how]
    mov edx, 2
    xor ecx, ecx
    call ne_ask_choice
    mov ecx, SH_GH
    test eax, eax
    jz 61f
    mov ecx, SH_BROWSER
61: mov [rip + sx_how], ecx
7:  call ne_raw_end
    jmp .Lsm_check
.Lsm_flags:
    # no terminal, or --yes: the flags and what the index's entry has (--yes: other, gh when it is
    # logged in); without --gh it opens the browser
    cmp byte ptr [rip + sx_category], 0
    jne 1f
    cmp dword ptr [rip + sx_yes], 0
    jne 11f
    lea rdi, [rip + .Le_need_category]
    call sx_usage
11: lea rdi, [rip + sx_category]
    lea rsi, [rip + .Lother]
    call cstr_copy
1:  cmp dword ptr [rip + sx_how], SH_UNSET
    jne .Lsm_check
    mov dword ptr [rip + sx_how], SH_BROWSER
    cmp dword ptr [rip + sx_yes], 0
    je .Lsm_check
    cmp byte ptr [rip + sx_gh], 0
    je .Lsm_check
    mov dword ptr [rip + sx_how], SH_GH
.Lsm_check:
    lea rdi, [rip + sx_category]
    call sx_category_index
    test eax, eax
    jns 1f
    lea rdi, [rip + .Le_category]
    call sx_die
1:  lea rdi, [rip + sx_keywords]
    call sx_keywords_ok
    test rax, rax
    jz 2f
    mov rdi, rax
    call sx_die
2:  lea rdi, [rip + sx_maintainer]
    call ne_owner_ok
    test rax, rax
    jz 3f
    lea rdi, [rip + .Le_maintainer]
    call sx_die
3:  cmp dword ptr [rip + sx_how], SH_GH
    jne 4f
    cmp byte ptr [rip + sx_gh], 0
    jne 4f
    lea rdi, [rip + .Le_no_gh]
    call sx_die
4:  # submit
    mov dword ptr [rip + sx_ok], 0
    mov edi, 2
    call sx_job
    test rax, rax
    jnz 5f
    lea rdi, [rip + .Le_no_ps]
    call sx_die
5:  mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + sx_out]
    lea rcx, [rip + sx_line]
    call ne_run_lines
    test eax, eax
    jnz .Lsm_failed
    cmp dword ptr [rip + sx_ok], 0
    je .Lsm_failed
    mov byte ptr [rip + sx_work], 0     # the job took it
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    cmp byte ptr [rip + sx_pr], 0
    je 6f
    mov edi, 1
    lea rsi, [rip + .Lt_pr]
    call ne_put
    mov edi, 1
    lea rsi, [rip + sx_pr]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
6:  cmp byte ptr [rip + sx_url], 0
    je 8f
    mov edi, 1
    lea rsi, [rip + .Lt_open_new]
    cmp dword ptr [rip + sx_edit], 0
    je 7f
    lea rsi, [rip + .Lt_open_edit]
7:  call ne_put
    mov edi, 1
    lea rsi, [rip + sx_url]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    lea rdi, [rip + sx_url]
    call sx_open_url
    # the opener runs to its end (5 s at most) before rhun goes
    call time_ms
    lea r13, [rax + 5000]
71: call watch_count
    test eax, eax
    jz 8f
    call time_ms
    cmp rax, r13
    jae 8f
    mov edi, 100
    call loop_poll
    jmp 71b
8:  xor edi, edi
    call sys_exit
.Lsm_failed:
    cmp byte ptr [rip + sx_why], 0
    jne 1f
    lea rdi, [rip + sx_why]
    lea rsi, [rip + .Le_job]
    call cstr_copy
1:  lea rdi, [rip + sx_why]
    call sx_die

# sx_flag_value() -> rax the argument after the flag at rbx (rbx moves on); none: usage
sx_flag_value:
    inc rbx
    cmp rbx, r13
    jae 1f
    mov rax, [r12 + rbx*8]
    ret
1:  lea rdi, [rip + .Le_value]
    jmp ne_fail_usage

# sx_usage(why): as ne_fail_usage, the prepare step's folder gone first
sx_usage:
    push rdi
    call sx_drop_work
    pop rdi
    jmp ne_fail_usage

# sx_die(why): "rhun submit-extension: WHY", the folder gone, exit 1
sx_die:
    push rdi
    call ne_raw_end
    call sx_drop_work
    mov edi, 2
    lea rsi, [rip + .Lprefix]
    call ne_put
    pop rsi
    mov edi, 2
    call ne_put
    mov edi, 2
    lea rsi, [rip + .Lnl]
    call ne_put
    mov edi, 1
    call sys_exit

# ---------------- the GUI ----------------

# cmd_submit_extension(): Extensions: Submit to Index... asks for the folder (the project's when it
#   holds extension.ini), then the questions
FN cmd_submit_extension
    PROLOGUE
    mov byte ptr [rip + sx_dir], 0
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz 1f
    lea rsi, [rip + .Lmanifest]
    call path_join_tmp
    mov rdi, rax
    call file_missing
    test eax, eax
    jnz 1f
    lea rdi, [rip + sx_dir]
    mov rsi, [rip + g_project]
    mov edx, 4000
    call ne_copy
1:  call sx_open
    EPILOGUE

# FN submitext_folder(dir cstr): the same, for that folder (a linked extension's page)
FN submitext_folder
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + sx_dir]
    mov rsi, rbx
    mov edx, 4000
    call ne_copy
    call sx_open
    EPILOGUE

# sx_open(): the quick input at its first step, sx_dir the folder's text
sx_open:
    PROLOGUE
    mov eax, [rip + g_submitext_state]
    cmp eax, SS_RUNNING
    je 7f
    cmp eax, SS_PREPARING
    je 7f
    cmp eax, SS_ASKING
    jne 1f
    call quick_is_open
    test eax, eax
    jnz 9f
1:  call sx_drop_work
    call sx_reset
    mov dword ptr [rip + sx_set], 0
    mov dword ptr [rip + sx_how], SH_UNSET
    mov dword ptr [rip + sx_gui], 1
    mov byte ptr [rip + sx_category], 0
    mov byte ptr [rip + sx_keywords], 0
    mov byte ptr [rip + sx_maintainer], 0
    lea rdi, [rip + sx_tag]
    lea rsi, [rip + .Ldash]
    call cstr_copy
    lea rdi, [rip + sx_evq]
    call sb_clear
    mov dword ptr [rip + sx_step], 1
    xor edi, edi
    call sx_step_body
    lea rdi, [rip + sx_on_quick]
    mov rsi, [rip + ne_body + SB_ptr]
    mov rdx, [rip + ne_body + SB_len]
    call quick_open_native
    test rax, rax
    jg 2f
    lea rdi, [rip + .Lt_busy]
    call app_toast
    EPILOGUE
2:  mov [rip + sx_q], eax
    mov dword ptr [rip + g_submitext_state], SS_ASKING
    EPILOGUE
7:  lea rdi, [rip + .Lt_running]
    call app_toast
9:  EPILOGUE

# sx_on_quick(ptr, len): a quick input event, kept for submitext_tick
sx_on_quick:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], rsi
    lea rdi, [rip + sx_evq]
    lea rsi, [rsp]
    mov edx, 8
    call sb_push
    lea rdi, [rip + sx_evq]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    EPILOGUE

# submitext_timeout() -> eax 0 while quick input events wait, else -1 (app.s's timeout_fns)
FN submitext_timeout
    mov eax, -1
    cmp qword ptr [rip + sx_evq + SB_len], 0
    je 1f
    xor eax, eax
1:  ret

# submitext_tick(): the quick input's events (app.s's app_tick)
FN submitext_tick
    PROLOGUE
    cmp qword ptr [rip + sx_evq + SB_len], 0
    je 9f
    lea rdi, [rip + sx_evcur]
    call sb_clear
    lea rdi, [rip + sx_evcur]
    mov rsi, [rip + sx_evq + SB_ptr]
    mov rdx, [rip + sx_evq + SB_len]
    call sb_push
    lea rdi, [rip + sx_evq]
    call sb_clear
    xor ebx, ebx
1:  lea rax, [rbx + 8]
    cmp rax, [rip + sx_evcur + SB_len]
    ja 9f
    mov rcx, [rip + sx_evcur + SB_ptr]
    mov r12, [rcx + rbx]
    lea r13, [rcx + rbx + 8]
    lea rbx, [rbx + r12 + 8]
    cmp rbx, [rip + sx_evcur + SB_len]
    ja 9f
    mov rdi, r13
    mov rsi, r12
    call sx_event
    jmp 1b
9:  EPILOGUE

# sx_event(ptr, len): "0 quick Q WHAT ..." LF + body
sx_event:
    PROLOGUE 32
    mov eax, [rip + g_submitext_state]
    cmp eax, SS_ASKING
    je 1f
    cmp eax, SS_PREPARING
    jne 9f
1:  mov r12, rdi
    lea r13, [rdi + rsi]
    mov r14, rdi
2:  cmp r14, r13
    jae 9f
    cmp byte ptr [r14], 10
    je 3f
    inc r14
    jmp 2b
3:  lea r15, [r14 + 1]
    mov ebx, 3                  # "0", "quick", Q
4:  mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    dec ebx
    jnz 4b
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    cmp eax, [rip + sx_q]
    jne 9f
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov [rsp + 16], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Le_hide]
    call str_eq_cstr
    test eax, eax
    jz 5f
    # gone: a prepare running stops, its folder goes
    call sx_stop_job
    call sx_drop_work
    mov dword ptr [rip + g_submitext_state], SS_IDLE
    jmp 9f
5:  cmp dword ptr [rip + g_submitext_state], SS_PREPARING
    je 9f                       # the card waits for prepare
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Le_back]
    call str_eq_cstr
    test eax, eax
    jz 6f
    cmp dword ptr [rip + sx_step], 1
    jbe 9f
    dec dword ptr [rip + sx_step]
    mov rdi, [rsp + 16]
    call sx_show
    jmp 9f
6:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Le_accept]
    call str_eq_cstr
    test eax, eax
    jz 9f
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov rdi, r15
    xor esi, esi
    test eax, eax
    jz 8f
7:  lea rax, [r15 + rsi]
    cmp rax, r13
    jae 8f
    cmp byte ptr [rax], 10
    je 8f
    inc esi
    jmp 7b
8:  test eax, eax
    jnz 81f
    mov rsi, r13
    sub rsi, r15
81: mov rdx, [rsp + 16]
    call sx_accept
9:  EPILOGUE

# sx_accept(ptr, len, seq): the step's answer
sx_accept:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp dword ptr [rip + sx_step], 2
    je .Lsa_category
    cmp dword ptr [rip + sx_step], 5
    je .Lsa_how
    # a text, trimmed, in ne_line
    cmp r13, 4000
    jbe 1f
    mov r13d, 4000
1:  lea rdi, [rip + ne_line]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    lea rax, [rip + ne_line]
    mov byte ptr [rax + r13], 0
    lea rdi, [rip + ne_line]
    mov rsi, r13
    call trim
    lea rdi, [rip + ne_line]
    mov rsi, rax
    push rdx
    push rdx
    call memmove
    pop rdx
    pop rdx
    lea rax, [rip + ne_line]
    mov byte ptr [rax + rdx], 0
    cmp dword ptr [rip + sx_step], 3
    je .Lsa_keywords
    cmp dword ptr [rip + sx_step], 4
    je .Lsa_maintainer
    # the folder: ~ is the home; it holds extension.ini
    lea rax, [rip + .Le_dir_empty]
    cmp byte ptr [rip + ne_line], 0
    je .Lsa_error
    lea rdi, [rip + sx_dir]
    lea rsi, [rip + ne_line]
    call ne_expand_home
    lea rdi, [rip + sx_dir]
    call ne_absolute
    lea rcx, [rip + .Le_dir_relative]
    test eax, eax
    mov rax, rcx
    jz .Lsa_error
    lea rdi, [rip + sx_dir]
    lea rsi, [rip + .Lmanifest]
    call path_join_tmp
    mov rdi, rax
    call file_missing
    lea rcx, [rip + .Le_no_manifest]
    test eax, eax
    mov rax, rcx
    jnz .Lsa_error
    # prepare, while the card waits with its spinner
    mov [rip + sx_seq], r14d
    call sx_drop_work
    call sx_reset
    mov edi, 1
    call sx_start
    test eax, eax
    jz .Lsa_spawn
    mov dword ptr [rip + g_submitext_state], SS_PREPARING
    lea rdi, [rip + ne_body]
    call sb_clear
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_flags_busy]
    call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_reading]
    call ne_rec
    call sx_set_body
    EPILOGUE
.Lsa_spawn:
    lea rax, [rip + .Le_spawn]
    jmp .Lsa_error
.Lsa_category:
    cmp r13, 30
    ja 9f
    lea rdi, [rip + sx_category]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    lea rax, [rip + sx_category]
    mov byte ptr [rax + r13], 0
    jmp .Lsa_next
.Lsa_keywords:
    lea rdi, [rip + ne_line]
    call sx_keywords_ok
    test rax, rax
    jnz .Lsa_error
    lea rdi, [rip + sx_keywords]
    lea rsi, [rip + ne_line]
    mov edx, 500
    call ne_copy
    jmp .Lsa_next
.Lsa_maintainer:
    lea rdi, [rip + ne_line]
    call ne_owner_ok
    test rax, rax
    jz 2f
    lea rax, [rip + .Le_maintainer]
    jmp .Lsa_error
2:  lea rdi, [rip + sx_maintainer]
    lea rsi, [rip + ne_line]
    mov edx, 39
    call ne_copy
    jmp .Lsa_next
.Lsa_how:
    mov dword ptr [rip + sx_how], SH_BROWSER
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lhow_gh]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov dword ptr [rip + sx_how], SH_GH
3:  mov edi, [rip + sx_q]
    call quick_close_native
    mov dword ptr [rip + sx_ok], 0
    mov edi, 2
    call sx_start
    test eax, eax
    jnz 4f
    mov dword ptr [rip + g_submitext_state], SS_FAILED
    lea rdi, [rip + sx_why]
    lea rsi, [rip + .Le_spawn]
    call cstr_copy
    call sx_note_failed
    EPILOGUE
4:  mov dword ptr [rip + g_submitext_state], SS_RUNNING
    # "Submitting OWNER/NAME TAG", with Cancel
    lea rdi, [rip + sx_title]
    lea rsi, [rip + .Lt_submitting]
    call cstr_copy
    call sx_push_full_tag
    xor edi, edi
    mov esi, SX_PG_NOTE
    lea rdx, [rip + sx_title]
    lea rcx, [rip + sx_cancel]
    xor r8d, r8d
    call progress_begin
    mov [rip + sx_pg], eax
9:  EPILOGUE
.Lsa_next:
    inc dword ptr [rip + sx_step]
    mov rdi, r14
    call sx_show
    EPILOGUE
.Lsa_error:
    mov rdi, rax
    mov rsi, r14
    call sx_error
    EPILOGUE

# sx_push_full_tag(rax: where in sx_title): "OWNER/NAME TAG" there
sx_push_full_tag:
    PROLOGUE
    mov rdi, rax
    lea rsi, [rip + sx_full]
    call cstr_copy
    mov byte ptr [rax], ' '
    lea rdi, [rax + 1]
    lea rsi, [rip + sx_tagout]
    call cstr_copy
    EPILOGUE

# sx_error(why cstr, seq): "msg SEQ error LEN" under the field (the spinner off)
sx_error:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + ne_body]
    call sb_clear
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_flags_none]
    cmp dword ptr [rip + sx_step], 1
    je 1f
    lea rsi, [rip + .Lr_flags_back]
1:  call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_dir]
    cmp dword ptr [rip + sx_step], 1
    je 2f
    lea rsi, [rip + .Lp_maintainer]
    cmp dword ptr [rip + sx_step], 4
    je 2f
    lea rsi, [rip + .Lp_keywords]
2:  call ne_rec
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_msg]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_error]
    call sb_push_cstr
    mov rdi, rbx
    call ne_rec_data
    call sx_set_body
    EPILOGUE

# sx_set_body(): ne_body onto the card
sx_set_body:
    sub rsp, 8
    mov edi, [rip + sx_q]
    mov rsi, [rip + ne_body + SB_ptr]
    mov rdx, [rip + ne_body + SB_len]
    call quick_set_native
    add rsp, 8
    ret

# sx_show(seq): the card at step sx_step
sx_show:
    sub rsp, 8
    call sx_step_body
    call sx_set_body
    add rsp, 8
    ret

# sx_step_body(seq): step sx_step's records into ne_body
sx_step_body:
    PROLOGUE 16
    mov r15, rdi
    lea rdi, [rip + ne_body]
    call sb_clear
    lea rdi, [rip + .Lr_title]
    lea rsi, [rip + .Lq_title]
    call ne_rec
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_step]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov esi, [rip + sx_step]
    call sb_push_u64
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_step_end]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_flags_back]
    cmp dword ptr [rip + sx_step], 1
    jne 1f
    lea rsi, [rip + .Lr_flags_none]
1:  call sb_push_cstr
    mov eax, [rip + sx_step]
    cmp eax, 2
    je .Lsb_category
    cmp eax, 5
    je .Lsb_how
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_input]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_items_none]
    call sb_push_cstr
    cmp dword ptr [rip + sx_step], 3
    je .Lsb_keywords
    cmp dword ptr [rip + sx_step], 4
    je .Lsb_maintainer
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_dir]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_dir]
    call ne_rec
    lea rsi, [rip + sx_dir]
    jmp .Lsb_value
.Lsb_keywords:
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_keywords]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_keywords]
    call ne_rec
    lea rsi, [rip + sx_keywords]
    jmp .Lsb_value
.Lsb_maintainer:
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_maintainer]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_maintainer]
    call ne_rec
    lea rsi, [rip + sx_maintainer]
    jmp .Lsb_value
.Lsb_category:
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_pick]
    call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_category]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lempty]
    call ne_rec
    mov rax, [rip + ne_body + SB_len]
    mov [rsp], rax
    xor ebx, ebx
2:  lea rax, [rip + sx_categories]
    mov rdi, [rax + rbx*8]
    mov rsi, rdi
    lea rax, [rip + sx_category_descs]
    mov rdx, [rax + rbx*8]
    call ne_item
    inc ebx
    cmp ebx, 8
    jb 2b
    mov rdi, [rsp]
    mov esi, 8
    call ne_items_head
    lea rdi, [rip + sx_category]
    call sx_category_index
    test eax, eax
    jns 3f
    mov eax, 7
3:  lea rcx, [rip + sx_categories]
    mov rax, [rcx + rax*8]
    jmp .Lsb_active
.Lsb_how:
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_pick]
    call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_how]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lempty]
    call ne_rec
    mov rax, [rip + ne_body + SB_len]
    mov [rsp], rax
    xor ebx, ebx
    cmp byte ptr [rip + sx_gh], 0
    je 4f
    # "as LOGIN: a fork, a branch, gh pr create"
    lea rdi, [rip + sx_title]
    lea rsi, [rip + .Ld_gh_as]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + sx_gh]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Ld_gh_rest]
    call cstr_copy
    lea rdi, [rip + .Lhow_gh]
    lea rsi, [rip + .Ll_gh]
    lea rdx, [rip + sx_title]
    call ne_item
    inc ebx
4:  lea rdi, [rip + .Lhow_browser]
    lea rsi, [rip + .Ll_browser]
    lea rdx, [rip + .Ld_browser]
    call ne_item
    inc ebx
    mov rdi, [rsp]
    mov esi, ebx
    call ne_items_head
    lea rax, [rip + .Lhow_browser]
    cmp ebx, 2
    jne .Lsb_active
    lea rax, [rip + .Lhow_gh]
.Lsb_active:
    mov rbx, rax
    lea rdi, [rip + .Lr_active]
    mov rsi, rbx
    call ne_rec
    lea rsi, [rip + .Lempty]
.Lsb_value:
    mov rbx, rsi
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_value]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + ne_body]
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    call ne_rec_data
    EPILOGUE

# sx_start(step 1 prepare, 2 submit) -> eax 1 when the job runs in the background
sx_start:
    PROLOGUE
    mov ebx, edi
    mov [rip + sx_jobstep], edi
    mov dword ptr [rip + sx_cancelled], 0
    lea rdi, [rip + sx_out]
    call sb_clear
    lea rdi, [rip + sx_entry]
    call sb_clear
    mov edi, ebx
    call sx_job
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    xor edx, edx
.ifdef WINDOWS
    call run_piped
.else
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, 1                  # its errors too, in a session of its own (Cancel stops the group)
    call run_piped_input
.endif
    test rax, rax
    jle 8f
    mov [rip + sx_pid], eax
    mov [rip + sx_fd], edx
    mov edi, edx
    mov esi, POLLIN
    lea rdx, [rip + sx_on_job]
    xor ecx, ecx
    call watch_add
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sx_stop_job(): a job still running stops (its output is no longer wanted)
sx_stop_job:
    sub rsp, 8
    mov edi, [rip + sx_pid]
    test edi, edi
    jle 9f
    mov dword ptr [rip + sx_cancelled], 1
    neg edi
    mov esi, SIGTERM
    call proc_kill
9:  add rsp, 8
    ret

# sx_cancel(ctx, id): the progress card's Cancel
sx_cancel:
    sub rsp, 8
    cmp dword ptr [rip + g_submitext_state], SS_RUNNING
    jne 9f
    call sx_stop_job
9:  add rsp, 8
    ret

# sx_on_job(fd, revents, ctx): the job's output; at its end what it did
sx_on_job:
    PROLOGUE
1:  lea rdi, [rip + sx_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + sx_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 8f
    test rax, rax
    jle 7f
    cmp qword ptr [rip + sx_out + SB_len], SX_OUT_MAX
    jae 1b
    add [rip + sx_out + SB_len], rax
    lea rdi, [rip + sx_out]
    lea rsi, [rip + sx_line]
    call ne_take_lines
    jmp 1b
7:  lea rdi, [rip + sx_out]
    lea rsi, [rip + sx_line]
    call ne_take_lines
    call sx_finish
8:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# sx_finish(): the job ended: prepare goes on to the questions (or says why under the folder);
#   submit's result is a notification
sx_finish:
    PROLOGUE 16
    mov edi, [rip + sx_fd]
    call watch_remove
    mov edi, [rip + sx_fd]
    SYS SYS_close
    mov dword ptr [rip + sx_fd], -1
    mov edi, [rip + sx_pid]
    xor esi, esi
    call proc_wait
    mov ebx, eax
    mov dword ptr [rip + sx_pid], 0
    cmp dword ptr [rip + sx_jobstep], 1
    jne .Lsf_submit
    cmp dword ptr [rip + sx_cancelled], 0
    jne 9f                      # the card is gone already
    test ebx, ebx
    jnz 1f
    cmp byte ptr [rip + sx_full], 0
    je 1f
    # the questions, the entry's answers as defaults
    call sx_default_maintainer
    mov dword ptr [rip + g_submitext_state], SS_ASKING
    mov dword ptr [rip + sx_step], 2
    mov edi, [rip + sx_seq]
    call sx_show
    EPILOGUE
1:  call sx_drop_work
    mov dword ptr [rip + g_submitext_state], SS_ASKING
    lea rdi, [rip + sx_why]
    cmp byte ptr [rdi], 0
    jne 2f
    lea rsi, [rip + .Le_job]
    call cstr_copy
2:  lea rdi, [rip + sx_why]
    mov esi, [rip + sx_seq]
    call sx_error
9:  EPILOGUE
.Lsf_submit:
    mov edi, [rip + sx_pg]
    call progress_end
    mov dword ptr [rip + sx_pg], 0
    cmp dword ptr [rip + sx_cancelled], 0
    je 1f
    call sx_drop_work
    mov dword ptr [rip + g_submitext_state], SS_CANCELLED
    lea rdi, [rip + .Lt_cancelled]
    call strlen
    mov rcx, rax
    xor edi, edi
    mov esi, SEV_INFO
    lea rdx, [rip + .Lt_cancelled]
    call notify_add
    EPILOGUE
1:  test ebx, ebx
    jnz 5f
    cmp dword ptr [rip + sx_ok], 0
    je 5f
    mov byte ptr [rip + sx_work], 0     # the job took it
    mov dword ptr [rip + g_submitext_state], SS_DONE
    lea rdi, [rip + ne_sb]
    call sb_clear
    cmp byte ptr [rip + sx_pr], 0
    je 2f
    # "Opened the pull request for OWNER/NAME TAG: URL", with Open
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_pr_note]
    call sb_push_cstr
    call sx_note_full_tag
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_colon]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + sx_pr]
    call sb_push_cstr
    call sx_note_info
    mov edi, eax
    test eax, eax
    jz 9f
    lea rsi, [rip + .Lb_open]
    lea rdx, [rip + sx_b_pr]
    xor ecx, ecx
    call notify_button
    EPILOGUE
2:  # the browser at GitHub's page; the entry stays on hand for its editor
    lea rdi, [rip + sx_url]
    call sx_open_url
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_web_new]
    cmp dword ptr [rip + sx_edit], 0
    je 3f
    lea rsi, [rip + .Lt_web_edit]
3:  call sb_push_cstr
    call sx_note_full_tag
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_web_end]
    cmp dword ptr [rip + sx_edit], 0
    je 4f
    lea rsi, [rip + .Lt_web_edit_end]
4:  call sb_push_cstr
    call sx_note_info
    mov r12d, eax
    test eax, eax
    jz 9f
    mov edi, r12d
    lea rsi, [rip + .Lb_again]
    lea rdx, [rip + sx_b_url]
    xor ecx, ecx
    call notify_button
    mov edi, r12d
    lea rsi, [rip + .Lb_copy]
    lea rdx, [rip + sx_b_copy]
    xor ecx, ecx
    call notify_button
9:  EPILOGUE
5:  call sx_drop_work
    mov dword ptr [rip + g_submitext_state], SS_FAILED
    cmp byte ptr [rip + sx_why], 0
    jne 6f
    lea rdi, [rip + sx_why]
    lea rsi, [rip + .Le_job]
    call cstr_copy
6:  call sx_note_failed
    EPILOGUE

# sx_note_full_tag(): "OWNER/NAME TAG" onto ne_sb
sx_note_full_tag:
    sub rsp, 8
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + sx_full]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + sx_tagout]
    call sb_push_cstr
    add rsp, 8
    ret

# sx_note_info() -> eax the card: ne_sb as an info notification
sx_note_info:
    sub rsp, 8
    xor edi, edi
    mov esi, SEV_INFO
    mov rdx, [rip + ne_sb + SB_ptr]
    mov rcx, [rip + ne_sb + SB_len]
    call notify_add
    add rsp, 8
    ret

# sx_note_failed(): "Could not submit OWNER/NAME: WHY"
sx_note_failed:
    sub rsp, 8
    lea rdi, [rip + ne_sb]
    call sb_clear
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_failed]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + sx_full]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_colon]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + sx_why]
    call sb_push_cstr
    xor edi, edi
    mov esi, SEV_ERROR
    mov rdx, [rip + ne_sb + SB_ptr]
    mov rcx, [rip + ne_sb + SB_len]
    call notify_add
    add rsp, 8
    ret

# the result's buttons: fn(ctx, id)
sx_b_pr:
    lea rdi, [rip + sx_pr]
    jmp desktop_open
sx_b_url:
    lea rdi, [rip + sx_url]
    jmp sx_open_url
sx_b_copy:
    sub rsp, 8
    mov rdi, [rip + sx_entry + SB_ptr]
    mov rsi, [rip + sx_entry + SB_len]
    xor edx, edx
    call ed_clip_set
    add rsp, 8
    ret

# sx_open_url(url): the desktop's browser (desktop.s), or RHUN_SUBMIT_OPENER's program with the
#   address, waited for (tests: no browser opens)
sx_open_url:
    PROLOGUE 32
    mov rbx, rdi
    lea rdi, [rip + .Lenv_opener]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov [rsp], rax
    mov [rsp + 8], rbx
    mov qword ptr [rsp + 16], 0
    lea rdi, [rsp]
    mov rsi, [rip + g_envp]
    xor edx, edx
    call run_piped
    test rax, rax
    jle 9f
    mov r12d, eax
    mov edi, edx
    SYS SYS_close
    mov edi, r12d
    xor esi, esi
    call proc_wait
    EPILOGUE
1:  mov rdi, rbx
    call desktop_open
9:  EPILOGUE

# ---------------- headless ----------------

# wait-submit-extension: until no step runs and no event waits (2 minutes at most), then
#   "submit-extension=STATE"
c_wait_submit:
    PROLOGUE
    mov rbx, rdi
    call time_ms
    lea r13, [rax + 120000]
1:  mov eax, [rip + g_submitext_state]
    cmp eax, SS_RUNNING
    je 2f
    cmp eax, SS_PREPARING
    je 2f
    cmp qword ptr [rip + sx_evq + SB_len], 0
    je 3f
2:  call time_ms
    cmp rax, r13
    jae 3f
    mov edi, 50
    call loop_poll
    call app_tick
    call ne_flush
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rip + .Lw_prefix]
    call sb_push_cstr
    mov eax, [rip + g_submitext_state]
    lea rcx, [rip + .Lw_states]
    mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# print-submit-entry: the last entry written, its lines
c_print_entry:
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rip + sx_entry + SB_ptr]
    mov rdx, [rip + sx_entry + SB_len]
    call sb_push
    xor eax, eax
    EPILOGUE

.section .rodata
.Lprefix: .asciz "rhun submit-extension: "
.Lusage: .asciz "usage: rhun submit-extension [DIR] [--tag vX.Y.Z] [--category C] [--keywords \"a b\"] [--maintainer M] [--gh|--browser] [--yes]\n"
.Lusage_more:
    .ascii "Submits DIR's release (DIR/extension.ini: owner, name and the tag vVERSION) to the rhun\n"
    .ascii "extensions index, github.com/rhun-editor/extensions: the entry OWNER/NAME.ini with the\n"
    .ascii "release's commit and archive digests, then a pull request through gh when it is logged in,\n"
    .ascii "or GitHub's page that proposes the file in the browser. In a terminal it asks the category\n"
    .ascii "(languages formatters themes testing debugging tools packs other), keywords and the\n"
    .ascii "maintainer; an entry in the index gives the defaults. --yes, or no terminal, takes the flags\n"
    .ascii "(--yes: other, gh when it is logged in); without --gh it opens the browser.\n"
    .asciz "RHUN_EXT_BASE, RHUN_SUBMIT_API and RHUN_SUBMIT_RAW replace github.com, its API and raw files.\n"
.Le_flag: .asciz "unknown option"
.Le_value: .asciz "an option needs its value"
.Le_two_dirs: .asciz "one folder only"
.Le_dir_long: .asciz "the folder's path is too long"
.Le_dir_empty: .asciz "the folder is needed"
.Le_dir_relative: .asciz "the folder's path starts at the top (or ~)"
.Le_no_manifest: .asciz "that folder has no extension.ini"
.Le_category: .asciz "the category is one of languages formatters themes testing debugging tools packs other"
.Le_need_category: .asciz "without a terminal it needs --category C (or --yes for other)"
.Le_keywords: .asciz "keywords are lowercase words: letters, digits and - . _ + #"
.Le_keywords_long: .asciz "keywords are at most 300 characters"
.Le_maintainer: .asciz "the maintainer is a GitHub user: letters, digits and dashes"
.Le_no_gh: .asciz "gh is not installed or not logged in (gh auth login); --browser opens GitHub instead"
.Le_no_ps: .asciz "powershell.exe is not on PATH"
.Le_spawn: .asciz "the job could not start"
.Le_job: .asciz "the job stopped"
.Lwarning: .asciz "warning: "
.Lnl: .asciz "\n"
.Ldash: .asciz "-"
.Lother: .asciz "other"
.Lmanifest: .asciz "extension.ini"
.Lwork_prefix: .asciz "rhun-submit-"
.Lo_tag: .asciz "--tag"
.Lo_category: .asciz "--category"
.Lo_keywords: .asciz "--keywords"
.Lo_maintainer: .asciz "--maintainer"
.Lo_gh: .asciz "--gh"
.Lo_browser: .asciz "--browser"
.Lo_yes: .asciz "--yes"
.Lo_y: .asciz "-y"
.Lo_help: .asciz "--help"
.Lo_h: .asciz "-h"
.Lq_category: .asciz "Category"
.Lq_keywords: .asciz "Keywords (space separated)"
.Lq_maintainer: .asciz "Maintainer (GitHub user)"
.Lq_gh: .asciz "Open the pull request with gh as "
.Lc_yes: .asciz "Yes: a fork, a branch and gh pr create"
.Lc_no: .asciz "No: GitHub's page in the browser"
.Lt_pr: .asciz "Pull request: "
.Lt_open_new: .asciz "Opening GitHub's page that proposes the file (it forks the index for you): "
.Lt_open_edit: .asciz "The index has the entry: GitHub's editor for it, where the entry above replaces its text: "
.Lhow_gh: .asciz "gh"
.Lhow_browser: .asciz "browser"
.Lprepare: .asciz "prepare"
.Lsubmit: .asciz "submit"
.Lenv_api: .asciz "RHUN_SUBMIT_API"
.Lenv_opener: .asciz "RHUN_SUBMIT_OPENER"
.Lenv_raw: .asciz "RHUN_SUBMIT_RAW"
.Lapi: .asciz "https://api.github.com"
.Lraw: .asciz "https://raw.githubusercontent.com"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-submit-extension"
.ifdef WINDOWS
.Lx_step: .asciz "RHUN_SX_STEP="
.Lx_dir: .asciz "RHUN_SX_DIR="
.Lx_tag: .asciz "RHUN_SX_TAG="
.Lx_github: .asciz "RHUN_SX_GITHUB="
.Lx_api: .asciz "RHUN_SX_API="
.Lx_raw: .asciz "RHUN_SX_RAW="
.Lx_work: .asciz "RHUN_SX_WORK="
.Lx_category: .asciz "RHUN_SX_CATEGORY="
.Lx_keywords: .asciz "RHUN_SX_KEYWORDS="
.Lx_maintainer: .asciz "RHUN_SX_MAINTAINER="
.Lx_how: .asciz "RHUN_SX_HOW="
.endif
.Lj_step: .asciz "step "
.Lj_say: .asciz "say "
.Lj_warn: .asciz "warn "
.Lj_work: .asciz "work "
.Lj_full: .asciz "full "
.Lj_tag: .asciz "tag "
.Lj_existing: .asciz "existing yes"
.Lj_category: .asciz "category "
.Lj_keywords: .asciz "keywords "
.Lj_maintainer: .asciz "maintainer "
.Lj_gh: .asciz "gh "
.Lj_url: .asciz "url "
.Lj_pr: .asciz "pr "
.Lj_edit: .asciz "edit yes"
.Lj_fail: .asciz "fail "
.Lj_ok: .asciz "ok"
.Le_hide: .asciz "hide"
.Le_back: .asciz "back"
.Le_accept: .asciz "accept"
.Lr_title: .asciz "title "
.Lr_step: .asciz "step "
.Lr_step_end: .asciz " 5 0\n"
.Lr_flags_back: .asciz "flags back 0\n"
.Lr_flags_none: .asciz "flags - 0\n"
.Lr_flags_busy: .asciz "flags busy 0\n"
.Lr_mode_input: .asciz "mode input 0\n"
.Lr_mode_pick: .asciz "mode pick 0\n"
.Lr_items_none: .asciz "items 0 0\n"
.Lr_prompt: .asciz "prompt "
.Lr_placeholder: .asciz "placeholder "
.Lr_active: .asciz "active "
.Lr_value: .asciz "value "
.Lr_msg: .asciz "msg "
.Lr_error: .asciz " error "
.Lq_title: .asciz "Submit to Index"
.Lp_dir: .asciz "Folder: the extension's own (extension.ini names it and its version: the tag vVERSION is submitted)"
.Lh_dir: .asciz "~/code/my-extension"
.Lp_reading: .asciz "Reading the release, its commit and the index\342\200\246"
.Lp_category: .asciz "Category: where Browse lists it"
.Lp_keywords: .asciz "Keywords: lowercase words that Browse's search finds"
.Lh_keywords: .asciz "charts statistics"
.Lp_maintainer: .asciz "Maintainer: the GitHub user who answers for it"
.Lh_maintainer: .asciz "your-github-user"
.Lp_how: .asciz "Submit: a pull request to github.com/rhun-editor/extensions"
.Ll_gh: .asciz "Open the pull request with gh"
.Ld_gh_as: .asciz "as "
.Ld_gh_rest: .asciz ": a fork, the branch submit-OWNER-NAME-TAG, gh pr create"
.Ll_browser: .asciz "Propose it on GitHub in the browser"
.Ld_browser: .asciz "GitHub's page with the file filled in; it forks the index for you"
.Lempty: .asciz ""
.Lt_running: .asciz "A submission is under way"
.Lt_busy: .asciz "Another question is open"
.Lt_submitting: .asciz "Submitting "
.Lt_cancelled: .asciz "Cancelled the submission"
.Lt_pr_note: .asciz "Opened the pull request for "
.Lt_web_new: .asciz "GitHub opens to propose "
.Lt_web_end: .asciz ": sign in there and press Propose changes"
.Lt_web_edit: .asciz "GitHub's editor opens for "
.Lt_web_edit_end: .asciz ": paste the entry (Copy Entry) over the file's text, then Propose changes"
.Lt_failed: .asciz "Could not submit "
.Lt_colon: .asciz ": "
.Lb_open: .asciz "Open"
.Lb_again: .asciz "Open Again"
.Lb_copy: .asciz "Copy Entry"
.Lc_wait: .asciz "wait-submit-extension"
.Lc_entry: .asciz "print-submit-entry"
.Lw_prefix: .asciz "submit-extension="
.Lw_idle: .asciz "idle"
.Lw_asking: .asciz "asking"
.Lw_preparing: .asciz "preparing"
.Lw_running: .asciz "running"
.Lw_done: .asciz "done"
.Lw_failed: .asciz "failed"
.Lw_cancelled: .asciz "cancelled"
.Lk_languages: .asciz "languages"
.Lk_formatters: .asciz "formatters"
.Lk_themes: .asciz "themes"
.Lk_testing: .asciz "testing"
.Lk_debugging: .asciz "debugging"
.Lk_tools: .asciz "tools"
.Lk_packs: .asciz "packs"
.Lk_other: .asciz "other"
.Ld_languages: .asciz "language support: completion, errors, symbols"
.Ld_formatters: .asciz "formatting documents"
.Ld_themes: .asciz "colors and icons"
.Ld_testing: .asciz "running and showing tests"
.Ld_debugging: .asciz "debuggers"
.Ld_tools: .asciz "commands, views and everything else that helps"
.Ld_packs: .asciz "several extensions at once"
.Ld_other: .asciz "anything else"
.p2align 3
sx_categories: .quad .Lk_languages, .Lk_formatters, .Lk_themes, .Lk_testing, .Lk_debugging, .Lk_tools, .Lk_packs, .Lk_other
sx_category_descs: .quad .Ld_languages, .Ld_formatters, .Ld_themes, .Ld_testing, .Ld_debugging, .Ld_tools, .Ld_packs, .Ld_other
.Lc_how: .quad .Lc_yes, .Lc_no
.Lw_states: .quad .Lw_idle, .Lw_asking, .Lw_preparing, .Lw_running, .Lw_done, .Lw_failed, .Lw_cancelled
# sx_line's values: the line's word, where its value goes, its room | its flag << 16
sx_line_words:
    .quad .Lj_work, sx_work, 4000
    .quad .Lj_full, sx_full, 250
    .quad .Lj_tag, sx_tagout, 70
    .quad .Lj_category, sx_category, 30 | (SF_CATEGORY << 16)
    .quad .Lj_keywords, sx_keywords, 500 | (SF_KEYWORDS << 16)
    .quad .Lj_maintainer, sx_maintainer, 39 | (SF_MAINTAINER << 16)
    .quad .Lj_url, sx_url, 8000
    .quad .Lj_pr, sx_pr, 1000
    .quad .Lj_fail, sx_why, 1000
    .quad 0, 0, 0
# headless commands (registered in control.s's ctl_tables)
.globl submitext_ctl
submitext_ctl:
    .quad .Lc_wait, c_wait_submit, .Lc_entry, c_print_entry
    .quad 0, 0
