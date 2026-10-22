# A new extension from a template (docs/guide.md, "New extensions"): `rhun new-extension [DIR]` in a
# terminal, and the palette's Extensions: New Extension... (also on the Extensions page's Install
# menu). Both ask the same four things (the name, the owner, Rust or Go, the agent skills; the GUI
# also the folder) and run one job: newext_script (runtime/jobs/archive.sh and runtime/jobs/
# newext.sh, under sh) or on Windows newext_ps_script (runtime/windows/newext.ps1, under
# PowerShell). The job downloads the template's main branch as a .tar.gz (from
# https://codeload.github.com, or RHUN_NEW_EXT_BASE for tests), checks and unpacks it with Install
# from GitHub's rules (no links or devices, nothing outside itself, at most 64 MB), renames it to
# OWNER/NAME, adds the skills repository's rhun-extension skill for Claude Code and Codex, moves it
# into DIR and runs git init.
#   terminal: newext_main() with flags --name N --owner O --lang rust|go --skills|--no-skills --yes;
#     in a terminal it asks (raw mode, arrows or digits for the choices; Windows: line prompts),
#     without one the flags are needed. The job's output is the terminal's.
#   GUI: a multi-step quick input (quick.s, native), then the job in the background with a
#     progress card and Cancel; the result is a notification with Open Folder, New Window and
#     Dev Install (Link a Folder).
#   RHUN_NEW_EXT_BASE   another place than https://codeload.github.com for the archives (tests)
.include "rhun.inc"

.equ NE_NAME_MAX, 64
.equ NE_OWNER_MAX, 39
.equ NE_DIR_MAX, 3000
.equ NE_OUT_MAX, 65536
.equ NE_STEPS, 5
.equ NE_PG_NOTE, 2                # notify.s NPW_NOTE: the progress shows as a card with Cancel
.equ NS_IDLE, 0
.equ NS_ASKING, 1
.equ NS_RUNNING, 2
.equ NS_DONE, 3
.equ NS_FAILED, 4
.equ NS_CANCELLED, 5
.equ K_EOF, -1
.equ K_NONE, 0
.equ K_CTRLC, 3
.equ K_CTRLD, 4
.equ K_ENTER, 10
.equ K_ESC, 27
.equ K_BS, 127
.equ K_UP, 0x101
.equ K_DOWN, 0x102
# terminals: the kernel's termios as Linux lays it out (src/mac/linux.s translates it on macOS)
.equ NT_TCGETS, 0x5401
.equ NT_TCSETS, 0x5402
.equ NT_SIZE, 64
.equ NT_iflag, 0
.equ NT_lflag, 12
.equ NT_vtime, 22               # c_cc (at 17) [VTIME 5]
.equ NT_vmin, 23                # c_cc [VMIN 6]
.equ NT_ICRNL, 0x100
.equ NT_ECHO, 8
.ifdef MACOS
.equ NT_IXON, 0x200
.equ NT_ISIG, 0x80
.equ NT_ICANON, 0x100
.equ NT_IEXTEN, 0x400
.else
.equ NT_IXON, 0x400
.equ NT_ISIG, 1
.equ NT_ICANON, 2
.equ NT_IEXTEN, 0x8000
.endif

.bss
.p2align 3
.globl ne_name
ne_name: .zero 128
ne_owner: .zero 128
.globl ne_dir
ne_dir: .zero 4096
ne_cwd: .zero 4096
.globl ne_line
ne_line: .zero 4096             # a line typed at a Windows prompt
.globl ne_sb
ne_sb: .zero SB_SIZE            # scratch
ne_argv: .zero 16 * 8
ne_tty: .zero NT_SIZE           # the terminal as it was
ne_raw: .zero NT_SIZE
ne_kbuf: .zero 64               # keys read and not taken yet
ne_klen: .long 0
ne_raw_on: .long 0
ne_lang: .long 0                # 0 not chosen, 1 rust, 2 go
ne_yes: .long 0
.p2align 3
# the GUI
ne_evq: .zero SB_SIZE           # quick input events kept for newext_tick: 8 bytes length, the bytes
ne_evcur: .zero SB_SIZE
.globl ne_body
ne_body: .zero SB_SIZE          # a step's body
ne_out: .zero SB_SIZE           # the job's output
ne_tmp: .zero 4096              # the job's folder beside DIR ("tmp PATH")
ne_done: .zero 4096             # the folder made ("ok DIR")
ne_why: .zero 1024              # why it failed ("fail WHY")
ne_title: .zero 256
ne_cnt: .quad 0
.ifdef WINDOWS
ne_envbuf: .zero 32768
ne_envlist: .zero 16 * 8
ne_envn: .quad 0
ne_envcur: .quad 0
ne_envp: .quad 0
ne_shell: .quad 0
.endif
.globl g_newext_state
g_newext_state: .long 0         # NS_* (tests wait on it)
ne_step: .long 0                # the step shown, 1..5
ne_q: .long 0                   # the quick input's Q
ne_pid: .long 0
ne_pg: .long 0                  # the progress' id
ne_cancelled: .long 0

.data
.p2align 3
.globl ne_prefix, ne_usage, ne_abort_fn
ne_prefix: .quad .Lprefix       # the command's name for its messages, and its usage line
ne_usage: .quad .Lusage
ne_abort_fn: .quad 0            # called before an abort exits (a command's temporary folder)
ne_skills: .long -1             # -1 not chosen, 0 no, 1 yes
ne_fd: .long -1

.text

# ---------------- shared ----------------

# ne_name_ok(cstr) -> rax 0, or why it is no manifest name ([a-z0-9][a-z0-9-]*, at most 64)
ne_name_ok:
    lea rax, [rip + .Le_name_empty]
    cmp byte ptr [rdi], 0
    je 9f
    lea rax, [rip + .Le_name_chars]
    cmp byte ptr [rdi], '-'
    je 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 3f
    cmp edx, '-'
    je 2f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 2f
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    ja 9f
2:  inc ecx
    cmp ecx, NE_NAME_MAX
    jbe 1b
    lea rax, [rip + .Le_name_long]
    ret
3:  xor eax, eax
9:  ret

# ne_owner_ok(cstr) -> rax 0, or why it is no GitHub owner ([A-Za-z0-9][A-Za-z0-9-]*, at most 39)
FN ne_owner_ok
    lea rax, [rip + .Le_owner_empty]
    cmp byte ptr [rdi], 0
    je 9f
    lea rax, [rip + .Le_owner_chars]
    cmp byte ptr [rdi], '-'
    je 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 3f
    cmp edx, '-'
    je 2f
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 2f
    or edx, 0x20
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    ja 9f
2:  inc ecx
    cmp ecx, NE_OWNER_MAX
    jbe 1b
    lea rax, [rip + .Le_owner_long]
    ret
3:  xor eax, eax
9:  ret

# ne_copy(dst, src, max): src cut at max bytes, NUL-terminated
FN ne_copy
    xor ecx, ecx
1:  cmp ecx, edx
    jae 2f
    movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    mov [rdi + rcx], al
    inc ecx
    jmp 1b
2:  mov byte ptr [rdi + rcx], 0
    ret

# ne_git_owner(dst): git's github.user ([github] user in $XDG_CONFIG_HOME/git/config or
#   ~/.config/git/config, then ~/.gitconfig, which wins), or "" (read, not asked of git: no process)
FN ne_git_owner
    PROLOGUE 16
    mov rbx, rdi
    mov byte ptr [rbx], 0
    lea rdi, [rip + .Lenv_xdg]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rdi, rax
    lea rsi, [rip + .Lgit_xdg]
    call path_join_tmp
    jmp 2f
1:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 3f
    mov rdi, rax
    lea rsi, [rip + .Lgit_cfg2]
    call path_join_tmp
2:  mov rdi, rax
    mov rsi, rbx
    call ne_git_file
3:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 9f
    mov rdi, rax
    lea rsi, [rip + .Lgit_cfg]
    call path_join_tmp
    mov rdi, rax
    mov rsi, rbx
    call ne_git_file
9:  EPILOGUE

# ne_git_file(path, dst): its [github] user, when one that ne_owner_ok takes, into dst
ne_git_file:
    PROLOGUE 80                 # an INI iterator at [rsp]
    mov r12, rsi
    call file_read_all
    test rax, rax
    jz 9f
    mov r13, rax
    lea rdi, [rsp]
    mov rsi, rax
    call ini_init
1:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz 8f
    mov rdi, [rsp + INI_sec]
    mov rsi, [rsp + INI_seclen]
    lea rdx, [rip + .Lgit_github]
    mov ecx, 6
    cmp rsi, rcx
    jne 1b
    call str_ieq
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_key]
    mov rsi, [rsp + INI_keylen]
    lea rdx, [rip + .Lgit_user]
    mov ecx, 4
    cmp rsi, rcx
    jne 1b
    call str_ieq
    test eax, eax
    jz 1b
    mov rcx, [rsp + INI_vallen]
    test rcx, rcx
    jz 1b
    cmp rcx, NE_OWNER_MAX
    ja 1b
    lea rdi, [rip + ne_line]
    mov rsi, [rsp + INI_val]
    mov rdx, rcx
    push rcx
    push rcx
    call memcpy
    pop rcx
    pop rcx
    lea rdi, [rip + ne_line]
    mov byte ptr [rdi + rcx], 0
    call ne_owner_ok
    test rax, rax
    jnz 1b
    mov rdi, r12
    lea rsi, [rip + ne_line]
    mov edx, NE_OWNER_MAX
    call ne_copy
    jmp 1b
8:  mov rdi, r13
    call mem_free
9:  EPILOGUE

# ne_base() -> where the archives are: RHUN_NEW_EXT_BASE, or https://codeload.github.com
ne_base:
    sub rsp, 8
    lea rdi, [rip + .Lenv_base]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 2f
1:  lea rax, [rip + .Lcodeload]
2:  add rsp, 8
    ret

# ne_lang_word() -> "rust" or "go"; ne_skills_word() -> "yes" or "no"
ne_lang_word:
    lea rax, [rip + .Lrust]
    cmp dword ptr [rip + ne_lang], 2
    jne 1f
    lea rax, [rip + .Lgo]
1:  ret
ne_skills_word:
    lea rax, [rip + .Lyes]
    cmp dword ptr [rip + ne_skills], 0
    jne 1f
    lea rax, [rip + .Lno]
1:  ret

# ne_job(ui cstr) -> rax argv, rdx envp (rax 0: no PowerShell): the job for ne_name, ne_owner,
#   ne_lang, ne_skills and ne_dir
ne_job:
    PROLOGUE
    mov r12, rdi
.ifdef WINDOWS
    # PowerShell runs runtime/windows/newext.ps1 (newext_ps_script), the inputs in RHUN_NE_*
    call ne_env_reset
    lea rdi, [rip + .Lne_name]
    lea rsi, [rip + ne_name]
    call ne_env
    lea rdi, [rip + .Lne_owner]
    lea rsi, [rip + ne_owner]
    call ne_env
    call ne_lang_word
    lea rdi, [rip + .Lne_lang]
    mov rsi, rax
    call ne_env
    call ne_skills_word
    lea rdi, [rip + .Lne_skills]
    mov rsi, rax
    call ne_env
    lea rdi, [rip + .Lne_dir]
    lea rsi, [rip + ne_dir]
    call ne_env
    call ne_base
    lea rdi, [rip + .Lne_base]
    mov rsi, rax
    call ne_env
    lea rdi, [rip + .Lne_ui]
    mov rsi, r12
    call ne_env
    lea rdi, [rip + newext_ps_script]
    call ne_ps_job
    EPILOGUE
.else
    # sh -c SCRIPT rhun-new-extension NAME OWNER LANG SKILLS DIR BASE UI
    lea rbx, [rip + ne_argv]
    lea rax, [rip + .Lsh]
    mov [rbx], rax
    lea rax, [rip + .Ldash_c]
    mov [rbx + 8], rax
    lea rax, [rip + newext_script]
    mov [rbx + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rbx + 24], rax
    lea rax, [rip + ne_name]
    mov [rbx + 32], rax
    lea rax, [rip + ne_owner]
    mov [rbx + 40], rax
    call ne_lang_word
    mov [rbx + 48], rax
    call ne_skills_word
    mov [rbx + 56], rax
    lea rax, [rip + ne_dir]
    mov [rbx + 64], rax
    call ne_base
    mov [rbx + 72], rax
    mov [rbx + 80], r12
    mov qword ptr [rbx + 88], 0
    mov rax, rbx
    mov rdx, [rip + g_envp]
    EPILOGUE
.endif

.ifdef WINDOWS
# FN ne_env_reset(), FN ne_env("NAME=", value), FN ne_ps_job(script) -> rax argv, rdx envp (rax 0:
#   no PowerShell): a PowerShell job's inputs as variables, then powershell.exe -EncodedCommand
FN ne_env_reset
    mov qword ptr [rip + ne_envn], 0
    lea rax, [rip + ne_envbuf]
    mov [rip + ne_envcur], rax
    ret
FN ne_env
    PROLOGUE
    mov r12, rsi
    mov rbx, [rip + ne_envcur]
    mov rcx, [rip + ne_envn]
    cmp rcx, 14
    jae 9f
    lea rax, [rip + ne_envlist]
    mov [rax + rcx*8], rbx
    inc qword ptr [rip + ne_envn]
    mov rsi, rdi
    mov rdi, rbx
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    call cstr_copy
    inc rax
    mov [rip + ne_envcur], rax
9:  EPILOGUE
FN ne_ps_job
    PROLOGUE
    mov r12, rdi
    mov rcx, [rip + ne_envn]
    lea rax, [rip + ne_envlist]
    mov qword ptr [rax + rcx*8], 0
    mov rdi, [rip + ne_envp]
    call mem_free
    lea rdi, [rip + ne_envlist]
    call env_make
    mov [rip + ne_envp], rax
    mov rdi, [rip + ne_shell]
    call mem_free
    lea rdi, [rip + .Lps]
    call proc_which
    mov [rip + ne_shell], rax
    test rax, rax
    jz 8f
    lea rcx, [rip + ne_argv]
    mov [rcx], rax
    lea rax, [rip + .Lps_noprofile]
    mov [rcx + 8], rax
    lea rax, [rip + .Lps_nonint]
    mov [rcx + 16], rax
    lea rax, [rip + .Lps_format]
    mov [rcx + 24], rax
    lea rax, [rip + .Lps_text]
    mov [rcx + 32], rax
    lea rax, [rip + .Lps_encoded]
    mov [rcx + 40], rax
    mov [rcx + 48], r12
    mov qword ptr [rcx + 56], 0
    mov rax, rcx
    mov rdx, [rip + ne_envp]
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE
.endif

# ne_dir_usable(path) -> rax 0 when the job can make it (nothing there, or an empty folder), or why not
ne_dir_usable:
    PROLOGUE
    mov rbx, rdi
    call file_missing
    test eax, eax
    jnz 8f
    mov rdi, rbx
    call file_type
    and eax, 0xf000
    cmp eax, 0x4000
    jne 7f
    mov qword ptr [rip + ne_cnt], 0
    mov rdi, rbx
    lea rsi, [rip + ne_count_one]
    xor edx, edx
    call dir_each_names
    test rax, rax
    js 6f
    cmp qword ptr [rip + ne_cnt], 0
    jne 6f
8:  xor eax, eax
    EPILOGUE
7:  lea rax, [rip + .Le_dir_file]
    EPILOGUE
6:  lea rax, [rip + .Le_dir_full]
    EPILOGUE

# ne_count_one(ctx, name): one more entry
ne_count_one:
    inc qword ptr [rip + ne_cnt]
    ret

# ne_absolute(path) -> eax 1 when it does not depend on the current folder
FN ne_absolute
.ifdef WINDOWS
    sub rsp, 8
    call path_rootlen
    add rsp, 8
    test rax, rax
    setnz al
    movzx eax, al
    ret
.else
    xor eax, eax
    cmp byte ptr [rdi], '/'
    sete al
    ret
.endif

# ---------------- the terminal ----------------

# newext_main(): `rhun new-extension [DIR] [flags]`; it exits with the job's status (2: usage)
FN newext_main
    PROLOGUE 16
    mov r12, [rip + g_argv]
    mov r13, [rip + g_argc]
    mov ebx, 2
    xor r15d, r15d              # 1: --name, 2: --owner given
.Lnm_arg:
    cmp rbx, r13
    jae .Lnm_args_done
    mov r14, [r12 + rbx*8]
    mov rdi, r14
    lea rsi, [rip + .Lo_name]
    call strcmp_eq
    test eax, eax
    jz 1f
    call ne_flag_value
    lea rdi, [rip + ne_name]
    mov rsi, rax
    mov edx, 120
    call ne_copy
    or r15d, 1
    jmp .Lnm_next
1:  mov rdi, r14
    lea rsi, [rip + .Lo_owner]
    call strcmp_eq
    test eax, eax
    jz 2f
    call ne_flag_value
    lea rdi, [rip + ne_owner]
    mov rsi, rax
    mov edx, 120
    call ne_copy
    or r15d, 2
    jmp .Lnm_next
2:  mov rdi, r14
    lea rsi, [rip + .Lo_lang]
    call strcmp_eq
    test eax, eax
    jz 3f
    call ne_flag_value
    mov r14, rax
    mov dword ptr [rip + ne_lang], 1
    mov rdi, rax
    lea rsi, [rip + .Lrust]
    call strcmp_eq
    test eax, eax
    jnz .Lnm_next
    mov dword ptr [rip + ne_lang], 2
    mov rdi, r14
    lea rsi, [rip + .Lgo]
    call strcmp_eq
    test eax, eax
    jnz .Lnm_next
    lea rdi, [rip + .Le_lang]
    call ne_fail_usage
3:  mov rdi, r14
    lea rsi, [rip + .Lo_skills]
    call strcmp_eq
    test eax, eax
    jz 4f
    mov dword ptr [rip + ne_skills], 1
    jmp .Lnm_next
4:  mov rdi, r14
    lea rsi, [rip + .Lo_no_skills]
    call strcmp_eq
    test eax, eax
    jz 5f
    mov dword ptr [rip + ne_skills], 0
    jmp .Lnm_next
5:  mov rdi, r14
    lea rsi, [rip + .Lo_yes]
    call strcmp_eq
    test eax, eax
    jnz 51f
    mov rdi, r14
    lea rsi, [rip + .Lo_y]
    call strcmp_eq
    test eax, eax
    jz 6f
51: mov dword ptr [rip + ne_yes], 1
    jmp .Lnm_next
6:  mov rdi, r14
    lea rsi, [rip + .Lo_help]
    call strcmp_eq
    test eax, eax
    jnz 61f
    mov rdi, r14
    lea rsi, [rip + .Lo_h]
    call strcmp_eq
    test eax, eax
    jz 7f
61: mov edi, 1
    lea rsi, [rip + .Lusage]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lusage_more]
    call ne_put
    xor edi, edi
    call sys_exit
7:  cmp byte ptr [r14], '-'
    jne 8f
    lea rdi, [rip + .Le_flag]
    call ne_fail_usage
8:  cmp byte ptr [rip + ne_dir], 0
    je 81f
    lea rdi, [rip + .Le_two_dirs]
    call ne_fail_usage
81: mov rdi, r14
    call strlen
    cmp rax, NE_DIR_MAX
    jb 82f
    lea rdi, [rip + .Le_dir_long]
    call ne_fail_usage
82: lea rdi, [rip + ne_dir]
    mov rsi, r14
    call cstr_copy
.Lnm_next:
    inc rbx
    jmp .Lnm_arg
.Lnm_args_done:
    # DIR from the top, then the name: --name, else DIR's last part
    cmp byte ptr [rip + ne_dir], 0
    je 1f
    call ne_dir_absolute
    test r15d, 1
    jnz 1f
    lea rdi, [rip + ne_dir]
    call strlen
    lea rdi, [rip + ne_dir]
    mov rsi, rax
    call ne_trim_seps
    mov rsi, rax
    lea rdi, [rip + ne_dir]
    call path_basename
    cmp rdx, 120
    ja 1f
    lea rdi, [rip + ne_name]
    mov rsi, rax
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rax, [rip + ne_name]
    mov byte ptr [rax + rdx], 0
1:  test r15d, 2
    jnz 2f
    lea rdi, [rip + ne_owner]
    call ne_git_owner
2:  # asked in a terminal, unless --yes
    cmp dword ptr [rip + ne_yes], 0
    jne .Lnm_flags
    xor edi, edi
    call ne_isatty
    test eax, eax
    jz .Lnm_flags
    mov edi, 1
    call ne_isatty
    test eax, eax
    jz .Lnm_flags
    call ne_raw_begin
    test r15d, 1
    jnz 3f
    lea rdi, [rip + .Lq_name]
    lea rsi, [rip + ne_name]
    mov edx, NE_NAME_MAX
    lea rcx, [rip + ne_name_ok]
    call ne_ask_text
3:  test r15d, 2
    jnz 4f
    lea rdi, [rip + .Lq_owner]
    lea rsi, [rip + ne_owner]
    mov edx, NE_OWNER_MAX
    lea rcx, [rip + ne_owner_ok]
    call ne_ask_text
4:  cmp dword ptr [rip + ne_lang], 0
    jne 5f
    lea rdi, [rip + .Lq_lang]
    lea rsi, [rip + .Lc_lang]
    mov edx, 2
    xor ecx, ecx
    call ne_ask_choice
    inc eax
    mov [rip + ne_lang], eax
5:  cmp dword ptr [rip + ne_skills], -1
    jne 6f
    lea rdi, [rip + .Lq_skills]
    lea rsi, [rip + .Lc_skills]
    mov edx, 2
    xor ecx, ecx
    call ne_ask_choice
    xor ecx, ecx
    test eax, eax
    sete cl
    mov [rip + ne_skills], ecx
6:  call ne_raw_end
    jmp .Lnm_check
.Lnm_flags:
    # no terminal, or --yes: the flags (the owner may come from git; --yes takes Rust and the skills)
    cmp byte ptr [rip + ne_name], 0
    jne 1f
    lea rdi, [rip + .Le_need_name]
    call ne_fail_usage
1:  cmp byte ptr [rip + ne_owner], 0
    jne 2f
    lea rdi, [rip + .Le_need_owner]
    call ne_fail_usage
2:  cmp dword ptr [rip + ne_lang], 0
    jne 3f
    cmp dword ptr [rip + ne_yes], 0
    jne 21f
    lea rdi, [rip + .Le_need_lang]
    call ne_fail_usage
21: mov dword ptr [rip + ne_lang], 1
3:  cmp dword ptr [rip + ne_skills], -1
    jne .Lnm_check
    mov dword ptr [rip + ne_skills], 1
.Lnm_check:
    lea rdi, [rip + ne_name]
    call ne_name_ok
    test rax, rax
    jz 1f
    mov rdi, rax
    call ne_fail
1:  lea rdi, [rip + ne_owner]
    call ne_owner_ok
    test rax, rax
    jz 2f
    mov rdi, rax
    call ne_fail
2:  # the folder: DIR, else NAME in the current folder
    cmp byte ptr [rip + ne_dir], 0
    jne 4f
    lea rdi, [rip + ne_dir]
    lea rsi, [rip + ne_name]
    call cstr_copy
    call ne_dir_absolute
4:  lea rdi, [rip + .Lcli]
    call ne_job
    test rax, rax
    jnz 5f
    lea rdi, [rip + .Le_no_ps]
    call ne_fail
5:  mov rdi, rax
    mov rsi, rdx
    xor edx, edx
    xor ecx, ecx
    mov r8d, 1
    mov r9d, 2
    push 0
    push 0
    call proc_spawn
    add rsp, 16
    test rax, rax
    jg 6f
    lea rdi, [rip + .Le_spawn]
    call ne_fail
6:  mov edi, eax
    xor esi, esi
    call proc_wait
    mov edi, eax
    test edi, edi
    jns 7f
    mov edi, 1
7:  call sys_exit

# ne_dir_absolute(): ne_dir from the top: under the current folder unless it is already
FN ne_dir_absolute
    sub rsp, 8
    lea rdi, [rip + ne_dir]
    call ne_absolute
    test eax, eax
    jnz 1f
    lea rdi, [rip + ne_cwd]
    mov esi, 4096
    SYS SYS_getcwd
    test rax, rax
    js 9f
    lea rdi, [rip + ne_cwd]
    lea rsi, [rip + ne_dir]
    call path_join_tmp
    lea rdi, [rip + ne_dir]
    mov rsi, rax
    mov edx, 4090
    call ne_copy
1:  lea rdi, [rip + ne_dir]
    call path_normalize         # "." and ".." go: DIR "." names the current folder
9:  add rsp, 8
    ret

# ne_flag_value() -> rax the argument after the flag at rbx (rbx moves on to it); none: usage
ne_flag_value:
    inc rbx
    cmp rbx, r13
    jae 1f
    mov rax, [r12 + rbx*8]
    ret
1:  lea rdi, [rip + .Le_value]
    jmp ne_fail_usage

# ne_trim_seps(path, len) -> rax len without trailing separators (one character stays)
ne_trim_seps:
    mov rax, rsi
1:  cmp rax, 1
    jbe 9f
    cmp byte ptr [rdi + rax - 1], '/'
    je 2f
.ifdef WINDOWS
    cmp byte ptr [rdi + rax - 1], 92
    je 2f
.endif
    jmp 9f
2:  dec rax
    jmp 1b
9:  ret

# ne_put(fd, cstr)
FN ne_put
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rsi, r12
    mov edi, ebx
    call write_all
    EPILOGUE

# ne_fail(why cstr): "rhun new-extension: WHY" on the error output, exit 2
FN ne_fail
    push rdi
    call ne_raw_end
    mov rax, [rip + ne_abort_fn]
    test rax, rax
    jz 1f
    call rax
1:
    mov edi, 2
    mov rsi, [rip + ne_prefix]
    call ne_put
    pop rsi
    mov edi, 2
    call ne_put
    mov edi, 2
    lea rsi, [rip + .Lnl]
    call ne_put
    mov edi, 2
    call sys_exit

# ne_fail_usage(why cstr): as ne_fail, then the usage line
FN ne_fail_usage
    push rdi
    call ne_raw_end
    mov edi, 2
    mov rsi, [rip + ne_prefix]
    call ne_put
    pop rsi
    mov edi, 2
    call ne_put
    mov edi, 2
    lea rsi, [rip + .Lnl]
    call ne_put
    mov edi, 2
    mov rsi, [rip + ne_usage]
    call ne_put
    mov edi, 2
    call sys_exit

# ne_isatty(fd) -> eax 1 for a terminal (Windows: a console)
FN ne_isatty
.ifdef WINDOWS
    jmp win_console_is
.else
    PROLOGUE NT_SIZE
    mov esi, NT_TCGETS
    lea rdx, [rsp]
    SYS SYS_ioctl
    xor ecx, ecx
    test rax, rax
    sete cl
    mov eax, ecx
    EPILOGUE
.endif

# ne_raw_begin(): the terminal gives each key at once, without echo or signals (Ctrl+C is a key
#   here, after which ne_raw_end puts it back); Windows keeps its line editing
FN ne_raw_begin
.ifdef WINDOWS
    ret
.else
    sub rsp, 8
    xor edi, edi
    mov esi, NT_TCGETS
    lea rdx, [rip + ne_tty]
    SYS SYS_ioctl
    test rax, rax
    jnz 9f
    lea rdi, [rip + ne_raw]
    lea rsi, [rip + ne_tty]
    mov edx, NT_SIZE
    call memcpy
    lea rax, [rip + ne_raw]
    and dword ptr [rax + NT_iflag], ~(NT_ICRNL | NT_IXON)
    and dword ptr [rax + NT_lflag], ~(NT_ICANON | NT_ECHO | NT_ISIG | NT_IEXTEN)
    mov byte ptr [rax + NT_vmin], 1
    mov byte ptr [rax + NT_vtime], 0
    xor edi, edi
    mov esi, NT_TCSETS
    lea rdx, [rip + ne_raw]
    SYS SYS_ioctl
    test rax, rax
    jnz 9f
    mov dword ptr [rip + ne_raw_on], 1
9:  add rsp, 8
    ret
.endif

# ne_raw_end(): the terminal as it was
FN ne_raw_end
    cmp dword ptr [rip + ne_raw_on], 0
    je 9f
    sub rsp, 8
    mov dword ptr [rip + ne_raw_on], 0
    xor edi, edi
    mov esi, NT_TCSETS
    lea rdx, [rip + ne_tty]
    SYS SYS_ioctl
    add rsp, 8
9:  ret

# ne_abort(): Ctrl+C or the input's end at a question: the terminal back, exit 130
FN ne_abort
    call ne_raw_end
    mov rax, [rip + ne_abort_fn]
    test rax, rax
    jz 1f
    call rax
1:
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    mov edi, 130
    call sys_exit

# ne_key() -> eax the next key: a character, K_ENTER, K_BS, K_CTRLC, K_CTRLD, K_UP, K_DOWN, K_ESC,
#   K_NONE for keys the questions do not use, K_EOF
FN ne_key
    PROLOGUE
1:  mov ecx, [rip + ne_klen]
    test ecx, ecx
    jnz 2f
    xor edi, edi
    lea rsi, [rip + ne_kbuf]
    mov edx, 64
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jle 8f
    mov [rip + ne_klen], eax
    jmp 1b
2:  lea rbx, [rip + ne_kbuf]
    movzx eax, byte ptr [rbx]
    mov r12d, 1                 # bytes it takes
    cmp eax, 27
    je 4f
    cmp eax, 13
    jne 3f
    mov eax, K_ENTER
3:  cmp eax, 8
    jne 7f
    mov eax, K_BS
    jmp 7f
4:  # ESC [ ... or ESC O ...: up to its final byte; Up and Down are used
    mov r13d, K_ESC
    cmp ecx, 2
    jb 6f
    movzx edx, byte ptr [rbx + 1]
    cmp edx, '['
    je 41f
    cmp edx, 'O'
    jne 6f
41: mov r13d, K_NONE
    mov r12d, 2
42: cmp r12d, ecx
    jae 6f
    movzx edx, byte ptr [rbx + r12]
    inc r12d
    cmp edx, 0x40
    jb 42b
    cmp edx, 0x7e
    ja 42b
    cmp edx, 'A'
    jne 43f
    mov r13d, K_UP
43: cmp edx, 'B'
    jne 6f
    mov r13d, K_DOWN
6:  mov eax, r13d
7:  # the key's bytes leave the buffer
    push rax
    push rax
    mov ecx, [rip + ne_klen]
    sub ecx, r12d
    mov [rip + ne_klen], ecx
    lea rdi, [rip + ne_kbuf]
    lea rsi, [rdi + r12]
    mov edx, ecx
    call memmove
    pop rax
    pop rax
    EPILOGUE
8:  mov eax, K_EOF
    EPILOGUE

# ne_ask_text(label cstr, buf (its default), max, check fn(cstr) -> 0 or why): "Label: text" until
#   the check takes it; raw: typed and erased in place, Windows: a line (empty keeps the default)
FN ne_ask_text
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
.Lat_prompt:
    mov edi, 1
    mov rsi, rbx
    call ne_put
.ifdef WINDOWS
    cmp byte ptr [r12], 0
    je 1f
    mov edi, 1
    lea rsi, [rip + .Lopen_br]
    call ne_put
    mov edi, 1
    mov rsi, r12
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lclose_br]
    call ne_put
1:  mov edi, 1
    lea rsi, [rip + .Lcolon]
    call ne_put
    call ne_read_line
    test eax, eax
    js ne_abort
    cmp byte ptr [rip + ne_line], 0
    je .Lat_check
    mov rdi, r12
    lea rsi, [rip + ne_line]
    mov edx, r13d
    inc edx                     # one past the most: the check says it is too long
    call ne_copy
.else
    mov edi, 1
    lea rsi, [rip + .Lcolon]
    call ne_put
    mov edi, 1
    mov rsi, r12
    call ne_put
2:  call ne_key
    cmp eax, K_ENTER
    je 5f
    cmp eax, K_CTRLC
    je ne_abort
    cmp eax, K_CTRLD
    je ne_abort
    cmp eax, K_EOF
    je ne_abort
    cmp eax, K_BS
    jne 3f
    mov rdi, r12
    call strlen
    test rax, rax
    jz 2b
    mov byte ptr [r12 + rax - 1], 0
    mov edi, 1
    lea rsi, [rip + .Lerase]
    call ne_put
    jmp 2b
3:  cmp eax, 32
    jb 2b
    cmp eax, 126
    ja 2b
    mov r15d, eax
    mov rdi, r12
    call strlen
    cmp eax, r13d
    jae 2b
    mov [r12 + rax], r15b
    mov byte ptr [r12 + rax + 1], 0
    mov [rsp], r15b
    mov byte ptr [rsp + 1], 0
    mov edi, 1
    lea rsi, [rsp]
    call ne_put
    jmp 2b
5:  mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
.endif
.Lat_check:
    mov rdi, r12
    call r14
    test rax, rax
    jz 9f
    mov r15, rax
    mov edi, 1
    lea rsi, [rip + .Lindent]
    call ne_put
    mov edi, 1
    mov rsi, r15
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    jmp .Lat_prompt
9:  EPILOGUE

# FN ne_ask_choice(label cstr, items cstr array, n (at most 9), default) -> eax the item chosen:
#   raw: the items under the label, Up and Down (or a digit) choose, Enter takes it, then
#   "Label: Item" stays; Windows: "Label (1 A, 2 B, ...) [N]: " takes a digit or a first letter
FN ne_ask_choice
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r15d, edx               # n
    mov r13d, ecx               # the item chosen
.ifdef WINDOWS
1:  mov edi, 1
    mov rsi, rbx
    call ne_put
    xor r14d, r14d
2:  mov edi, 1
    lea rsi, [rip + .Lw_sep]
    test r14d, r14d
    jnz 3f
    lea rsi, [rip + .Lw_open]
3:  call ne_put
    lea eax, [r14 + '1']
    mov [rsp], al
    mov byte ptr [rsp + 1], ' '
    mov byte ptr [rsp + 2], 0
    mov edi, 1
    lea rsi, [rsp]
    call ne_put
    mov edi, 1
    mov rsi, [r12 + r14*8]
    call ne_put
    inc r14d
    cmp r14d, r15d
    jb 2b
    lea eax, [r13 + '1']
    mov [rsp], al
    mov byte ptr [rsp + 1], 0
    mov edi, 1
    lea rsi, [rip + .Lw_close]
    call ne_put
    mov edi, 1
    lea rsi, [rsp]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lw_end]
    call ne_put
    call ne_read_line
    test eax, eax
    js ne_abort
    movzx eax, byte ptr [rip + ne_line]
    test eax, eax
    jz 9f
    lea ecx, [rax - '1']
    cmp ecx, r15d
    jae 4f
    mov r13d, ecx
    jmp 9f
4:  # the first item with that first letter, either case
    or eax, 0x20
    xor r14d, r14d
5:  mov rcx, [r12 + r14*8]
    movzx ecx, byte ptr [rcx]
    or ecx, 0x20
    cmp eax, ecx
    jne 6f
    mov r13d, r14d
    jmp 9f
6:  inc r14d
    cmp r14d, r15d
    jb 5b
    jmp 1b
9:  mov eax, r13d
    EPILOGUE
.else
    mov edi, 1
    mov rsi, rbx
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lcolon_nl]
    call ne_put
    call ne_choice_lines
2:  call ne_key
    cmp eax, K_ENTER
    je 6f
    cmp eax, K_CTRLC
    je ne_abort
    cmp eax, K_CTRLD
    je ne_abort
    cmp eax, K_EOF
    je ne_abort
    cmp eax, K_UP
    jne 3f
    dec r13d
    jns 5f
    lea r13d, [r15 - 1]
    jmp 5f
3:  cmp eax, K_DOWN
    jne 4f
    inc r13d
    cmp r13d, r15d
    jb 5f
    xor r13d, r13d
    jmp 5f
4:  lea ecx, [rax - '1']
    cmp ecx, r15d
    jae 2b
    mov r13d, ecx
    call ne_choice_up
    call ne_choice_lines
    jmp 6f
5:  call ne_choice_up
    call ne_choice_lines
    jmp 2b
6:  # the list folds into "Label: Item"
    lea edi, [r15 + 1]
    call ne_cursor_up
    mov edi, 1
    lea rsi, [rip + .Lclear_down]
    call ne_put
    mov edi, 1
    mov rsi, rbx
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lcolon]
    call ne_put
    mov edi, 1
    mov rsi, [r12 + r13*8]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lnl]
    call ne_put
    mov eax, r13d
    EPILOGUE

# ne_choice_up(): back to the first item's line (r15 items)
ne_choice_up:
    mov edi, r15d
    jmp ne_cursor_up

# ne_cursor_up(n): ESC [ n A
ne_cursor_up:
    PROLOGUE 16
    mov ebx, edi
    mov edi, 1
    lea rsi, [rip + .Lcsi]
    call ne_put
    lea rdi, [rsp]
    mov esi, ebx
    call fmt_u64
    mov byte ptr [rsp + rax], 'A'
    mov byte ptr [rsp + rax + 1], 0
    mov edi, 1
    lea rsi, [rsp]
    call ne_put
    EPILOGUE

# ne_choice_lines(): the items of ne_ask_choice (r12 items, r13 chosen, r15 n), each on a cleared
#   line, the chosen one marked
ne_choice_lines:
    PROLOGUE
    xor r14d, r14d
1:  lea rsi, [rip + .Lmark_off]
    cmp r14d, r13d
    jne 2f
    lea rsi, [rip + .Lmark_on]
2:  mov edi, 1
    call ne_put
    mov edi, 1
    mov rsi, [r12 + r14*8]
    call ne_put
    mov edi, 1
    lea rsi, [rip + .Lmark_end]
    call ne_put
    inc r14d
    cmp r14d, r15d
    jb 1b
    EPILOGUE
.endif

.ifdef WINDOWS
# ne_read_line() -> eax 0 with the line typed in ne_line (without CR LF), -1 at the input's end
ne_read_line:
    PROLOGUE
    xor ebx, ebx
1:  xor edi, edi
    lea rsi, [rip + ne_line]
    add rsi, rbx
    mov edx, 1
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jle 7f
    lea rcx, [rip + ne_line]
    movzx eax, byte ptr [rcx + rbx]
    cmp eax, 10
    je 3f
    cmp eax, 13
    je 1b
    cmp ebx, 4000
    jae 1b
    inc ebx
    jmp 1b
3:  lea rcx, [rip + ne_line]
    mov byte ptr [rcx + rbx], 0
    xor eax, eax
    EPILOGUE
7:  test ebx, ebx
    jnz 3b
    mov eax, -1
    EPILOGUE
.endif

# ---------------- the GUI ----------------

# cmd_new_extension(): Extensions: New Extension... asks its five steps
FN cmd_new_extension
    PROLOGUE
    cmp dword ptr [rip + g_newext_state], NS_RUNNING
    jne 1f
    lea rdi, [rip + .Lt_running]
    call app_toast
    EPILOGUE
1:  cmp dword ptr [rip + g_newext_state], NS_ASKING
    jne 3f
    call quick_is_open
    test eax, eax
    jnz 9f
3:  lea rdi, [rip + ne_owner]
    call ne_git_owner
    mov byte ptr [rip + ne_name], 0
    mov byte ptr [rip + ne_dir], 0
    mov dword ptr [rip + ne_lang], 1
    mov dword ptr [rip + ne_skills], 1
    lea rdi, [rip + ne_evq]
    call sb_clear
    mov dword ptr [rip + ne_step], 1
    xor edi, edi
    call ne_step_body
    lea rdi, [rip + ne_on_quick]
    mov rsi, [rip + ne_body + SB_ptr]
    mov rdx, [rip + ne_body + SB_len]
    call quick_open_native
    test rax, rax
    jg 2f
    lea rdi, [rip + .Lt_busy]
    call app_toast
    EPILOGUE
2:  mov [rip + ne_q], eax
    mov dword ptr [rip + g_newext_state], NS_ASKING
9:  EPILOGUE

# ne_on_quick(ptr, len): a quick input event, kept for newext_tick (the card is mid-change now)
ne_on_quick:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], rsi
    lea rdi, [rip + ne_evq]
    lea rsi, [rsp]
    mov edx, 8
    call sb_push
    lea rdi, [rip + ne_evq]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    EPILOGUE

# newext_timeout() -> eax 0 while quick input events wait, else -1 (app.s's timeout_fns)
FN newext_timeout
    mov eax, -1
    cmp qword ptr [rip + ne_evq + SB_len], 0
    je 1f
    xor eax, eax
1:  ret

# newext_tick(): the quick input's events: the next step, back, or the job (app.s's app_tick)
FN newext_tick
    PROLOGUE
    cmp qword ptr [rip + ne_evq + SB_len], 0
    je 9f
    # the events to take apart; any they cause wait for the next tick
    lea rdi, [rip + ne_evcur]
    call sb_clear
    lea rdi, [rip + ne_evcur]
    mov rsi, [rip + ne_evq + SB_ptr]
    mov rdx, [rip + ne_evq + SB_len]
    call sb_push
    lea rdi, [rip + ne_evq]
    call sb_clear
    xor ebx, ebx
1:  lea rax, [rbx + 8]
    cmp rax, [rip + ne_evcur + SB_len]
    ja 9f
    mov rcx, [rip + ne_evcur + SB_ptr]
    mov r12, [rcx + rbx]
    lea r13, [rcx + rbx + 8]
    lea rbx, [rbx + r12 + 8]
    cmp rbx, [rip + ne_evcur + SB_len]
    ja 9f
    mov rdi, r13
    mov rsi, r12
    call ne_event
    jmp 1b
9:  EPILOGUE

# ne_event(ptr, len): "0 quick Q WHAT ..." LF + body
ne_event:
    PROLOGUE 32
    cmp dword ptr [rip + g_newext_state], NS_ASKING
    jne 9f
    mov r12, rdi
    lea r13, [rdi + rsi]        # the end
    # the header's end
    mov r14, rdi
1:  cmp r14, r13
    jae 9f
    cmp byte ptr [r14], 10
    je 2f
    inc r14
    jmp 1b
2:  lea r15, [r14 + 1]          # the body
    # "0", "quick", Q
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    cmp eax, [rip + ne_q]
    jne 9f
    # WHAT
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    add r12, rcx
    mov [rsp], rax
    mov [rsp + 8], rdx
    # SEQ (back, accept)
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
    jz 3f
    mov dword ptr [rip + g_newext_state], NS_IDLE
    jmp 9f
3:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Le_back]
    call str_eq_cstr
    test eax, eax
    jz 4f
    cmp dword ptr [rip + ne_step], 1
    jbe 9f
    dec dword ptr [rip + ne_step]
    mov rdi, [rsp + 16]
    call ne_show
    jmp 9f
4:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [rip + .Le_accept]
    call str_eq_cstr
    test eax, eax
    jz 9f
    # accept SEQ N LEN: N ids, each ending in LF, then the field's text
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov rdi, r15                # the first id, or the text
    xor esi, esi                # its length
    test eax, eax
    jz 6f
5:  lea rax, [r15 + rsi]
    cmp rax, r13
    jae 6f
    cmp byte ptr [rax], 10
    je 6f
    inc esi
    jmp 5b
6:  test eax, eax
    jnz 7f
    mov rsi, r13
    sub rsi, r15
7:  mov rdx, [rsp + 16]
    call ne_accept
9:  EPILOGUE

# ne_accept(ptr, len, seq): the step's answer (an input's text or a pick's id)
ne_accept:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov eax, [rip + ne_step]
    cmp eax, 3
    je .Lac_lang
    cmp eax, 4
    je .Lac_skills
    # a text: NAME, OWNER or the folder, as a cstr in ne_line
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
    cmp dword ptr [rip + ne_step], 1
    je .Lac_name
    cmp dword ptr [rip + ne_step], 2
    je .Lac_owner
    jmp .Lac_dir
.Lac_name:
    lea rdi, [rip + ne_line]
    call ne_name_ok
    test rax, rax
    jnz .Lac_error
    lea rdi, [rip + ne_name]
    lea rsi, [rip + ne_line]
    mov edx, NE_NAME_MAX
    call ne_copy
    mov byte ptr [rip + ne_dir], 0  # the folder's default follows the name
    jmp .Lac_next
.Lac_owner:
    lea rdi, [rip + ne_line]
    call ne_owner_ok
    test rax, rax
    jnz .Lac_error
    lea rdi, [rip + ne_owner]
    lea rsi, [rip + ne_line]
    mov edx, NE_OWNER_MAX
    call ne_copy
    jmp .Lac_next
.Lac_lang:
    mov dword ptr [rip + ne_lang], 1
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lgo]
    call str_eq_cstr
    test eax, eax
    jz .Lac_next
    mov dword ptr [rip + ne_lang], 2
    jmp .Lac_next
.Lac_skills:
    mov dword ptr [rip + ne_skills], 1
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lno]
    call str_eq_cstr
    test eax, eax
    jz .Lac_next
    mov dword ptr [rip + ne_skills], 0
    jmp .Lac_next
.Lac_dir:
    # ~ is the home; the folder must not depend on rhun's current folder
    lea rax, [rip + .Le_dir_empty]
    cmp byte ptr [rip + ne_line], 0
    je .Lac_error
    lea rdi, [rip + ne_dir]
    lea rsi, [rip + ne_line]
    call ne_expand_home
    lea rdi, [rip + ne_dir]
    call ne_absolute
    lea rcx, [rip + .Le_dir_relative]
    test eax, eax
    mov rax, rcx
    jz .Lac_error
    lea rdi, [rip + ne_dir]
    call strlen
    lea rcx, [rip + .Le_dir_long]
    cmp rax, NE_DIR_MAX
    mov rax, rcx
    jae .Lac_error
    lea rdi, [rip + ne_dir]
    call ne_dir_usable
    test rax, rax
    jnz .Lac_error
    mov edi, [rip + ne_q]
    call quick_close_native
    call ne_start
    EPILOGUE
.Lac_next:
    inc dword ptr [rip + ne_step]
    mov rdi, r14
    call ne_show
    EPILOGUE
.Lac_error:
    # "msg SEQ error LEN": shown under the field, Enter refused until the text changes
    mov r15, rax
    lea rdi, [rip + ne_body]
    call sb_clear
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_msg]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_error]
    call sb_push_cstr
    mov rdi, r15
    call ne_rec_data
    mov edi, [rip + ne_q]
    mov rsi, [rip + ne_body + SB_ptr]
    mov rdx, [rip + ne_body + SB_len]
    call quick_set_native
    EPILOGUE

# ne_expand_home(dst, src): src with a leading ~ (alone or before a separator) as the home
FN ne_expand_home
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp byte ptr [r12], '~'
    jne 8f
    movzx eax, byte ptr [r12 + 1]
    test eax, eax
    jz 1f
    cmp eax, '/'
    je 1f
.ifdef WINDOWS
    cmp eax, 92
    je 1f
.endif
    jmp 8f
1:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 8f
    mov rdi, rax
    call strlen
    cmp rax, 2000
    ja 8f
    lea rdi, [rip + .Lenv_home]
    call getenv
    mov rdi, rbx
    mov rsi, rax
    call cstr_copy
    mov rdi, rax
    lea rsi, [r12 + 1]
    mov edx, 2000
    call ne_copy
    EPILOGUE
8:  mov rdi, rbx
    mov rsi, r12
    mov edx, 4000
    call ne_copy
    EPILOGUE

# ne_show(seq): quick-set to step ne_step, its field's text set for that sequence
ne_show:
    PROLOGUE
    call ne_step_body
    mov edi, [rip + ne_q]
    mov rsi, [rip + ne_body + SB_ptr]
    mov rdx, [rip + ne_body + SB_len]
    call quick_set_native
    EPILOGUE

# ne_rec_data(cstr): "LEN" LF and the bytes onto ne_body (a record's end)
FN ne_rec_data
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    lea rdi, [rip + ne_body]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + ne_body]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + ne_body]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    EPILOGUE

# ne_rec(head cstr, data cstr): "HEAD LEN" LF DATA onto ne_body (head ends in its space)
FN ne_rec
    PROLOGUE
    mov rbx, rsi
    mov rsi, rdi
    lea rdi, [rip + ne_body]
    call sb_push_cstr
    mov rdi, rbx
    call ne_rec_data
    EPILOGUE

# ne_item(id cstr, label cstr, desc cstr) onto ne_body: "ID_LEN LABEL_LEN EXTRA_LEN item" LF ID LABEL
#   and the extra, "desc LEN" LF DESC
FN ne_item
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r13
    call strlen
    mov r14, rax
    lea r15, [rax + 6]          # "desc " LEN LF DESC
    mov rax, r14
    xor ecx, ecx
1:  inc r15
    inc ecx
    xor edx, edx
    mov r8d, 10
    div r8
    test rax, rax
    jnz 1b
    mov rdi, rbx
    call strlen
    lea rdi, [rip + ne_body]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + ne_body]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    call strlen
    lea rdi, [rip + ne_body]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + ne_body]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ne_body]
    mov rsi, r15
    call sb_push_u64
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_item]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + .Lr_desc]
    mov rsi, r13
    call ne_rec
    EPILOGUE

# ne_step_body(seq): step ne_step's records into ne_body
ne_step_body:
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
    mov esi, [rip + ne_step]
    call sb_push_u64
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_step_end]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_flags_back]
    cmp dword ptr [rip + ne_step], 1
    jne 1f
    lea rsi, [rip + .Lr_flags_none]
1:  call sb_push_cstr
    mov eax, [rip + ne_step]
    cmp eax, 3
    je .Lsb_lang
    cmp eax, 4
    je .Lsb_skills
    # an input: the prompt, the placeholder, no items, the text
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_input]
    call sb_push_cstr
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_items_none]
    call sb_push_cstr
    mov eax, [rip + ne_step]
    cmp eax, 1
    je .Lsb_name
    cmp eax, 2
    je .Lsb_owner
    # the folder: by default ~/code/NAME
    cmp byte ptr [rip + ne_dir], 0
    jne 2f
    lea rdi, [rip + ne_dir]
    lea rsi, [rip + .Ldir_default]
    call ne_expand_home
    lea rdi, [rip + ne_dir]
    call strlen
    lea rdi, [rip + ne_dir]
    add rdi, rax
    lea rsi, [rip + ne_name]
    call cstr_copy
2:  lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_dir]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_dir]
    call ne_rec
    lea rsi, [rip + ne_dir]
    jmp .Lsb_value
.Lsb_name:
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_name]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_name]
    call ne_rec
    lea rsi, [rip + ne_name]
    jmp .Lsb_value
.Lsb_owner:
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_owner]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lh_owner]
    call ne_rec
    lea rsi, [rip + ne_owner]
    jmp .Lsb_value
.Lsb_lang:
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_pick]
    call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_lang]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lempty]
    call ne_rec
    # items: the two items' records are measured first
    mov rax, [rip + ne_body + SB_len]
    mov [rsp], rax
    lea rdi, [rip + .Lrust]
    lea rsi, [rip + .Ll_rust]
    lea rdx, [rip + .Ld_rust]
    call ne_item
    lea rdi, [rip + .Lgo]
    lea rsi, [rip + .Ll_go]
    lea rdx, [rip + .Ld_go]
    call ne_item
    mov rdi, [rsp]
    mov esi, 2
    call ne_items_head
    call ne_lang_word
    jmp .Lsb_active
.Lsb_skills:
    lea rdi, [rip + ne_body]
    lea rsi, [rip + .Lr_mode_pick]
    call sb_push_cstr
    lea rdi, [rip + .Lr_prompt]
    lea rsi, [rip + .Lp_skills]
    call ne_rec
    lea rdi, [rip + .Lr_placeholder]
    lea rsi, [rip + .Lempty]
    call ne_rec
    mov rax, [rip + ne_body + SB_len]
    mov [rsp], rax
    lea rdi, [rip + .Lyes]
    lea rsi, [rip + .Ll_yes]
    lea rdx, [rip + .Ld_yes]
    call ne_item
    lea rdi, [rip + .Lno]
    lea rsi, [rip + .Ll_no]
    lea rdx, [rip + .Ld_no]
    call ne_item
    mov rdi, [rsp]
    mov esi, 2
    call ne_items_head
    call ne_skills_word
.Lsb_active:
    mov rbx, rax
    lea rdi, [rip + .Lr_active]
    mov rsi, rbx
    call ne_rec
    lea rsi, [rip + .Lempty]
.Lsb_value:
    # "value SEQ LEN" + the field's text
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

# ne_items_head(start, n): the n item records from offset start in ne_body get their
#   "items N LEN" LF in front
FN ne_items_head
    PROLOGUE 16
    mov r12, rdi
    mov r15d, esi
    mov r13, [rip + ne_body + SB_len]
    sub r13, r12                # their length
    lea rdi, [rip + ne_sb]
    call sb_clear
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lr_items]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    mov esi, r15d
    call sb_push_u64
    lea rdi, [rip + ne_sb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ne_sb]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + ne_sb]
    mov esi, 10
    call sb_push_byte
    mov r14, [rip + ne_sb + SB_len]
    # room, then the items move up behind the head
    lea rdi, [rip + ne_body]
    mov rsi, r14
    call sb_reserve
    mov rax, [rip + ne_body + SB_ptr]
    lea rdi, [rax + r12]
    add rdi, r14
    lea rsi, [rax + r12]
    mov rdx, r13
    call memmove
    mov rax, [rip + ne_body + SB_ptr]
    lea rdi, [rax + r12]
    mov rsi, [rip + ne_sb + SB_ptr]
    mov rdx, r14
    call memcpy
    add [rip + ne_body + SB_len], r14
    EPILOGUE

# ne_start(): the job, in the background, with a progress card
ne_start:
    PROLOGUE
    lea rdi, [rip + ne_out]
    call sb_clear
    mov byte ptr [rip + ne_tmp], 0
    mov byte ptr [rip + ne_done], 0
    mov byte ptr [rip + ne_why], 0
    mov dword ptr [rip + ne_cancelled], 0
    lea rdi, [rip + .Lgui]
    call ne_job
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
    mov [rip + ne_pid], eax
    mov [rip + ne_fd], edx
    mov edi, edx
    mov esi, POLLIN
    lea rdx, [rip + ne_on_job]
    xor ecx, ecx
    call watch_add
    mov dword ptr [rip + g_newext_state], NS_RUNNING
    # "New extension OWNER/NAME"
    lea rdi, [rip + ne_title]
    lea rsi, [rip + .Lt_progress]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + ne_owner]
    call cstr_copy
    mov byte ptr [rax], '/'
    lea rdi, [rax + 1]
    lea rsi, [rip + ne_name]
    call cstr_copy
    xor edi, edi
    mov esi, NE_PG_NOTE
    lea rdx, [rip + ne_title]
    lea rcx, [rip + ne_cancel]
    xor r8d, r8d
    call progress_begin
    mov [rip + ne_pg], eax
    lea rdi, [rip + .Lt_starting]
    call strlen
    mov rcx, rax
    mov edi, [rip + ne_pg]
    xor esi, esi
    lea rdx, [rip + .Lt_starting]
    call progress_update
    EPILOGUE
8:  mov dword ptr [rip + g_newext_state], NS_FAILED
    lea rdi, [rip + ne_why]
    lea rsi, [rip + .Le_spawn]
    call cstr_copy
    call ne_note_failed
    EPILOGUE

# ne_cancel(ctx, id): the progress card's Cancel: the job stops (its folder goes: the script's trap,
#   or ne_finish)
ne_cancel:
    sub rsp, 8
    cmp dword ptr [rip + g_newext_state], NS_RUNNING
    jne 9f
    mov edi, [rip + ne_pid]
    test edi, edi
    jle 9f
    mov dword ptr [rip + ne_cancelled], 1
    neg edi
    mov esi, SIGTERM
    call proc_kill
9:  add rsp, 8
    ret

# ne_on_job(fd, revents, ctx): the job's output; at its end the result
ne_on_job:
    PROLOGUE
1:  lea rdi, [rip + ne_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + ne_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 8f
    test rax, rax
    jle 7f
    cmp qword ptr [rip + ne_out + SB_len], NE_OUT_MAX
    jae 1b
    add [rip + ne_out + SB_len], rax
    call ne_lines
    jmp 1b
7:  call ne_lines
    call ne_finish
8:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ne_lines(): the whole lines in ne_out: "tmp PATH", "step N M TEXT", "ok DIR", "fail WHY"
ne_lines:
    lea rdi, [rip + ne_out]
    lea rsi, [rip + ne_line_one]
    jmp ne_take_lines

# FN ne_take_lines(sb, fn(cstr)): each whole line in sb leaves it and goes to fn, without its CR LF
#   (in ne_line, at most 4000 bytes)
FN ne_take_lines
    PROLOGUE 16
    mov r15, rdi
    mov [rsp], rsi
1:  mov rbx, [r15 + SB_ptr]
    mov r12, [r15 + SB_len]
    xor r13d, r13d
2:  cmp r13, r12
    jae 9f
    cmp byte ptr [rbx + r13], 10
    je 3f
    inc r13
    jmp 2b
3:  # the line without its CR, as a cstr in ne_line
    mov r14, r13
    test r14, r14
    jz 4f
    cmp byte ptr [rbx + r14 - 1], 13
    jne 4f
    dec r14
4:  cmp r14, 4000
    jbe 5f
    mov r14d, 4000
5:  lea rdi, [rip + ne_line]
    mov rsi, rbx
    mov rdx, r14
    call memcpy
    lea rax, [rip + ne_line]
    mov byte ptr [rax + r14], 0
    # the line leaves ne_out
    mov rdi, rbx
    lea rsi, [rbx + r13 + 1]
    mov rdx, r12
    sub rdx, r13
    dec rdx
    mov [r15 + SB_len], rdx
    call memmove
    lea rdi, [rip + ne_line]
    call [rsp]
    jmp 1b
9:  EPILOGUE

# FN ne_run_lines(argv, envp, sb, fn(cstr)) -> eax the program's exit status (-1: it did not start):
#   it runs to its end, each line of its output to fn as it comes (rhun waits: the terminal commands)
FN ne_run_lines
    PROLOGUE 32
    mov r14, rdx
    mov r15, rcx
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    mov r12d, eax
    mov r13d, edx
    mov rdi, r14
    call sb_clear
1:  mov rdi, r14
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, r13d
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    jne 2f
    mov [rsp], r13d             # struct pollfd: fd, POLLIN
    mov dword ptr [rsp + 4], POLLIN
    lea rdi, [rsp]
    mov esi, 1
    mov edx, -1
    SYS SYS_poll
    jmp 1b
2:  test rax, rax
    jle 3f
    add [r14 + SB_len], rax
    mov rdi, r14
    mov rsi, r15
    call ne_take_lines
    jmp 1b
3:  mov edi, r13d
    SYS SYS_close
    mov edi, r12d
    xor esi, esi
    call proc_wait
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# ne_line_one(): ne_line, one line of the job
ne_line_one:
    PROLOGUE 16
    lea rbx, [rip + ne_line]
    mov rdi, rbx
    lea rsi, [rip + .Lj_tmp]
    call ne_starts
    test eax, eax
    jz 1f
    lea rdi, [rip + ne_tmp]
    lea rsi, [rbx + 4]
    mov edx, 4000
    call ne_copy
    EPILOGUE
1:  mov rdi, rbx
    lea rsi, [rip + .Lj_ok]
    call ne_starts
    test eax, eax
    jz 2f
    lea rdi, [rip + ne_done]
    lea rsi, [rbx + 3]
    mov edx, 4000
    call ne_copy
    EPILOGUE
2:  mov rdi, rbx
    lea rsi, [rip + .Lj_fail]
    call ne_starts
    test eax, eax
    jz 3f
    lea rdi, [rip + ne_why]
    lea rsi, [rbx + 5]
    mov edx, 1000
    call ne_copy
    EPILOGUE
3:  mov rdi, rbx
    lea rsi, [rip + .Lj_step]
    call ne_starts
    test eax, eax
    jz 9f
    # step N M TEXT: (N - 1) / M of the way
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
    cmp byte ptr [r12], ' '
    jne 9f
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
    lea rax, [r13 - 1]
    imul rax, rax, 100
    xor edx, edx
    div r14
    mov r15, rax
    mov rdi, r12
    call strlen
    mov rcx, rax
    mov edi, [rip + ne_pg]
    mov esi, r15d
    mov rdx, r12
    call progress_update
9:  EPILOGUE

# ne_starts(cstr, prefix cstr) -> eax 1 when it starts with prefix
FN ne_starts
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    cmp al, [rdi + rcx]
    jne 3f
    inc ecx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret

# ne_finish(): the job ended: its progress goes, and a notification says how it went
ne_finish:
    PROLOGUE 16
    mov edi, [rip + ne_fd]
    call watch_remove
    mov edi, [rip + ne_fd]
    SYS SYS_close
    mov dword ptr [rip + ne_fd], -1
    mov edi, [rip + ne_pid]
    xor esi, esi
    call proc_wait
    mov ebx, eax
    mov dword ptr [rip + ne_pid], 0
    mov edi, [rip + ne_pg]
    call progress_end
    mov dword ptr [rip + ne_pg], 0
    cmp dword ptr [rip + ne_cancelled], 0
    je 1f
    call ne_drop_tmp
    mov dword ptr [rip + g_newext_state], NS_CANCELLED
    lea rdi, [rip + .Lt_cancelled]
    call strlen
    mov rcx, rax
    xor edi, edi
    mov esi, SEV_INFO
    lea rdx, [rip + .Lt_cancelled]
    call notify_add
    EPILOGUE
1:  test ebx, ebx
    jnz 2f
    cmp byte ptr [rip + ne_done], 0
    je 2f
    mov dword ptr [rip + g_newext_state], NS_DONE
    # "Created OWNER/NAME in DIR", with Open Folder, New Window and Dev Install
    lea rdi, [rip + ne_sb]
    call sb_clear
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_created]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_owner]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_name]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_in]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_done]
    call sb_push_cstr
    xor edi, edi
    mov esi, SEV_INFO
    mov rdx, [rip + ne_sb + SB_ptr]
    mov rcx, [rip + ne_sb + SB_len]
    call notify_add
    mov r12d, eax
    test eax, eax
    jz 9f
    mov edi, r12d
    lea rsi, [rip + .Lb_open]
    lea rdx, [rip + ne_b_open]
    xor ecx, ecx
    call notify_button
    mov edi, r12d
    lea rsi, [rip + .Lb_window]
    lea rdx, [rip + ne_b_window]
    xor ecx, ecx
    call notify_button
    mov edi, r12d
    lea rsi, [rip + .Lb_dev]
    lea rdx, [rip + ne_b_dev]
    xor ecx, ecx
    call notify_button
9:  EPILOGUE
2:  call ne_drop_tmp
    mov dword ptr [rip + g_newext_state], NS_FAILED
    cmp byte ptr [rip + ne_why], 0
    jne 3f
    lea rdi, [rip + ne_why]
    lea rsi, [rip + .Le_job]
    call cstr_copy
3:  call ne_note_failed
    EPILOGUE

# ne_note_failed(): "Could not create OWNER/NAME: WHY" as an error notification
ne_note_failed:
    PROLOGUE
    lea rdi, [rip + ne_sb]
    call sb_clear
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_failed]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_owner]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_name]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + .Lt_colon]
    call sb_push_cstr
    lea rdi, [rip + ne_sb]
    lea rsi, [rip + ne_why]
    call sb_push_cstr
    xor edi, edi
    mov esi, SEV_ERROR
    mov rdx, [rip + ne_sb + SB_ptr]
    mov rcx, [rip + ne_sb + SB_len]
    call notify_add
    EPILOGUE

# FN ne_name_starts(path, prefix) -> eax 1 when the path's last part starts with prefix (on Windows
#   after a / or a \: the PowerShell jobs' paths have \)
FN ne_name_starts
    mov rax, rdi
    mov rcx, rdi
1:  movzx edx, byte ptr [rcx]
    test edx, edx
    jz 3f
    inc rcx
    cmp edx, '/'
.ifdef WINDOWS
    je 2f
    cmp edx, 92
.endif
    jne 1b
2:  mov rax, rcx
    jmp 1b
3:  mov rdi, rax
    jmp ne_starts

# ne_drop_tmp(): the job's folder beside DIR, when one is left (a Windows job stopped by Cancel has
#   no trap to remove it); only a .rhun-new- folder
ne_drop_tmp:
    PROLOGUE
    cmp byte ptr [rip + ne_tmp], 0
    je 9f
    lea rdi, [rip + ne_tmp]
    lea rsi, [rip + .Ltmp_prefix]
    call ne_name_starts
    test eax, eax
    jz 8f
    lea rdi, [rip + ne_tmp]
    call file_missing
    test eax, eax
    jnz 8f
    lea rdi, [rip + ne_tmp]
    call file_remove_tree
8:  mov byte ptr [rip + ne_tmp], 0
9:  EPILOGUE

# the result's buttons: fn(ctx, id)
ne_b_open:
    lea rdi, [rip + ne_done]
    jmp app_switch_project
ne_b_window:
    lea rdi, [rip + ne_done]
    jmp app_new_window
ne_b_dev:
    sub rsp, 8
    lea rdi, [rip + ne_done]
    call strlen
    mov rsi, rax
    lea rdi, [rip + ne_done]
    mov edx, IK_LINK
    call ext_install_local
    add rsp, 8
    ret

# ---------------- headless ----------------

# wait-new-extension: until the job is done (2 minutes at most), then "new-extension=STATE"
c_wait_new_extension:
    PROLOGUE
    mov rbx, rdi
    call time_ms
    lea r13, [rax + 120000]
1:  cmp dword ptr [rip + g_newext_state], NS_RUNNING
    je 2f
    cmp qword ptr [rip + ne_evq + SB_len], 0
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
    mov eax, [rip + g_newext_state]
    lea rcx, [rip + .Lw_states]
    mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE

# ne_flush(): the frame, as control.s's commands end with one (headless and Windows draw at once)
FN ne_flush
.ifndef WINDOWS
    cmp dword ptr [rip + g_headless], 0
    je 1f
.endif
    cmp dword ptr [rip + g_dirty], 0
    je 1f
    PCALL P_draw
1:  ret

.section .rodata
.Le_name_empty: .asciz "the name is needed"
.Le_name_chars: .asciz "the name is lowercase letters, digits and dashes, starting with a letter or digit"
.Le_name_long: .asciz "the name is at most 64 characters"
.Le_owner_empty: .asciz "the owner is needed: your GitHub user or organization"
.Le_owner_chars: .asciz "the owner is a GitHub user or organization: letters, digits and dashes"
.Le_owner_long: .asciz "the owner is at most 39 characters"
.Le_lang: .asciz "--lang is rust or go"
.Le_flag: .asciz "unknown option"
.Le_value: .asciz "an option needs its value"
.Le_two_dirs: .asciz "one folder only"
.Le_dir_long: .asciz "the folder's path is too long"
.Le_dir_empty: .asciz "the folder is needed"
.Le_dir_relative: .asciz "the folder's path starts at the top (or ~)"
.Le_dir_file: .asciz "that path is there and is not a folder"
.Le_dir_full: .asciz "that folder is not empty"
.Le_need_name: .asciz "without a terminal it needs --name NAME (or DIR)"
.Le_need_owner: .asciz "without a terminal it needs --owner OWNER (or git config github.user with --yes)"
.Le_need_lang: .asciz "without a terminal it needs --lang rust|go (or --yes for Rust)"
.Le_no_ps: .asciz "powershell.exe is not on PATH"
.Le_spawn: .asciz "the job could not start"
.Le_job: .asciz "the job stopped"
.Lprefix: .asciz "rhun new-extension: "
.Lusage: .asciz "usage: rhun new-extension [DIR] [--name NAME] [--owner OWNER] [--lang rust|go] [--skills|--no-skills] [--yes]\n"
.Lusage_more:
    .ascii "Makes a rhun extension in DIR (a new or empty folder; default ./NAME) from the template for\n"
    .ascii "the language, renamed OWNER/NAME, with the agent skills for Claude Code (.claude/skills)\n"
    .ascii "and Codex (.agents/skills) unless --no-skills. In a terminal it asks; --yes, or no terminal,\n"
    .ascii "takes the flags (--yes: the owner from git config github.user, Rust, the skills).\n"
    .asciz "RHUN_NEW_EXT_BASE replaces https://codeload.github.com for the archives.\n"
.Lnl: .asciz "\n"
.Lcolon: .asciz ": "
.Lcolon_nl: .asciz ":\n"
.Lindent: .asciz "  "
.Lerase: .asciz "\b \b"
.Lopen_br: .asciz " ["
.Lclose_br: .asciz "]"
.Lw_open: .asciz " ("
.Lw_sep: .asciz ", "
.Lw_close: .asciz ") ["
.Lw_end: .asciz "]: "
.Lcsi: .asciz "\r\033["
.Lclear_down: .asciz "\r\033[J"
.Lmark_on: .asciz "\r\033[K  \033[1m> "
.Lmark_off: .asciz "\r\033[K    "
.Lmark_end: .asciz "\033[0m\n"
.Lq_name: .asciz "Name"
.Lq_owner: .asciz "Owner (GitHub user or organization)"
.Lq_lang: .asciz "Language"
.Lq_skills: .asciz "Agent skills for Claude Code and Codex"
.Ll_rust: .asciz "Rust"
.Ll_go: .asciz "Go"
.Ll_yes: .asciz "Yes"
.Ll_no: .asciz "No"
.Ld_rust: .asciz "github.com/rhun-editor/template-rust"
.Ld_go: .asciz "github.com/rhun-editor/template-go"
.Ld_yes: .asciz "the rhun-extension skill in .claude/skills and .agents/skills"
.Ld_no: .asciz "the template as it is"
.Lrust: .asciz "rust"
.Lgo: .asciz "go"
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.Lo_name: .asciz "--name"
.Lo_owner: .asciz "--owner"
.Lo_lang: .asciz "--lang"
.Lo_skills: .asciz "--skills"
.Lo_no_skills: .asciz "--no-skills"
.Lo_yes: .asciz "--yes"
.Lo_y: .asciz "-y"
.Lo_help: .asciz "--help"
.Lo_h: .asciz "-h"
.Lcli: .asciz "cli"
.Lgui: .asciz "gui"
.Lenv_base: .asciz "RHUN_NEW_EXT_BASE"
.Lenv_home: .asciz "HOME"
.Lenv_xdg: .asciz "XDG_CONFIG_HOME"
.Lgit_xdg: .asciz "git/config"
.Lgit_cfg2: .asciz ".config/git/config"
.Lgit_cfg: .asciz ".gitconfig"
.Lgit_github: .asciz "github"
.Lgit_user: .asciz "user"
.Lcodeload: .asciz "https://codeload.github.com"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-new-extension"
.ifdef WINDOWS
.Lne_name: .asciz "RHUN_NE_NAME="
.Lne_owner: .asciz "RHUN_NE_OWNER="
.Lne_lang: .asciz "RHUN_NE_LANG="
.Lne_skills: .asciz "RHUN_NE_SKILLS="
.Lne_dir: .asciz "RHUN_NE_DIR="
.Lne_base: .asciz "RHUN_NE_BASE="
.Lne_ui: .asciz "RHUN_NE_UI="
.Lps: .asciz "powershell.exe"
.Lps_noprofile: .asciz "-NoProfile"
.Lps_nonint: .asciz "-NonInteractive"
.Lps_format: .asciz "-OutputFormat"
.Lps_text: .asciz "Text"
.Lps_encoded: .asciz "-EncodedCommand"
.endif
.Le_hide: .asciz "hide"
.Le_back: .asciz "back"
.Le_accept: .asciz "accept"
.Lr_title: .asciz "title "
.Lr_step: .asciz "step "
.Lr_step_end: .asciz " 5 0\n"
.Lr_flags_back: .asciz "flags back 0\n"
.Lr_flags_none: .asciz "flags - 0\n"
.Lr_mode_input: .asciz "mode input 0\n"
.Lr_mode_pick: .asciz "mode pick 0\n"
.Lr_items_none: .asciz "items 0 0\n"
.Lr_items: .asciz "items "
.Lr_item: .asciz " item\n"
.Lr_desc: .asciz "desc "
.Lr_prompt: .asciz "prompt "
.Lr_placeholder: .asciz "placeholder "
.Lr_active: .asciz "active "
.Lr_value: .asciz "value "
.Lr_msg: .asciz "msg "
.Lr_error: .asciz " error "
.Lq_title: .asciz "New Extension"
.Lp_name: .asciz "Name: lowercase letters, digits and dashes (the manifest's name and the program's)"
.Lh_name: .asciz "my-extension"
.Lp_owner: .asciz "Owner: your GitHub user or organization (the repository will be OWNER/NAME)"
.Lh_owner: .asciz "your-github-user"
.Lp_lang: .asciz "Language: the template it starts from"
.Lp_skills: .asciz "Agent skills: the rhun-extension skill for Claude Code and Codex, from rhun-editor/skills"
.Lp_dir: .asciz "Folder: a new or empty folder for it (git init runs there)"
.Lh_dir: .asciz "~/code/my-extension"
.Ldir_default: .asciz "~/code/"
.Lempty: .asciz ""
.Ltmp_prefix: .asciz ".rhun-new-"
.Lj_tmp: .asciz "tmp "
.Lj_ok: .asciz "ok "
.Lj_fail: .asciz "fail "
.Lj_step: .asciz "step "
.Lt_running: .asciz "A new extension is being made"
.Lt_busy: .asciz "Another question is open"
.Lt_progress: .asciz "New extension "
.Lt_starting: .asciz "Starting"
.Lt_cancelled: .asciz "Cancelled the new extension"
.Lt_created: .asciz "Created "
.Lt_in: .asciz " in "
.Lt_failed: .asciz "Could not create "
.Lt_colon: .asciz ": "
.Lb_open: .asciz "Open Folder"
.Lb_window: .asciz "New Window"
.Lb_dev: .asciz "Dev Install"
.Lc_wait: .asciz "wait-new-extension"
.Lw_prefix: .asciz "new-extension="
.Lw_idle: .asciz "idle"
.Lw_asking: .asciz "asking"
.Lw_running: .asciz "running"
.Lw_done: .asciz "done"
.Lw_failed: .asciz "failed"
.Lw_cancelled: .asciz "cancelled"
.p2align 3
.Lc_lang: .quad .Ll_rust, .Ll_go
.Lc_skills: .quad .Ll_yes, .Ll_no
.Lw_states: .quad .Lw_idle, .Lw_asking, .Lw_running, .Lw_done, .Lw_failed, .Lw_cancelled
# headless commands (registered in control.s's ctl_tables)
.globl newext_ctl
newext_ctl:
    .quad .Lc_wait, c_wait_new_extension
    .quad 0, 0
