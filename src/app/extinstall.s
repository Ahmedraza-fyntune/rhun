# installing an extension (Chrome's "Add extension"), updating one, and removing one. A background
# job (a fixed shell script, fed checked arguments) downloads a release's archive for this system
# and its sha256sums.txt (an exact tag, or the latest release's tag resolved first), checks the
# checksum (and the extensions index's digest when the index pins the version), refuses archives
# with links, devices, paths outside themselves or more than 64 MB unpacked, and unpacks into a
# fresh folder under the extensions folder. The same job takes a local archive, or a folder it
# packs first. rhun then reads the manifest there and asks, showing what the extension can do; Add
# moves it into place (the installed version steps aside into ROOT/.previous for Roll back) and
# starts it, Cancel throws it away. A pack's members are fetched in the same batch and asked about
# in one dialog. Updates use the same batch: a manual one asks when nobody reviewed the version or
# it asks for more, an automatic one installs only what asks for no more (extupdate.s).
#   RHUN_EXT_BASE   another place than https://github.com for the releases (tests)
.include "rhun.inc"

.equ IQ_MAX, 17                 # a batch: a pack and its 16 members
.equ IRS_QUEUED, 0
.equ IRS_RUNNING, 1
.equ IRS_STAGED, 2              # downloaded and checked: waits for Add
.equ IRS_FAILED, 3
.equ IRS_DONE, 4
STRUCT
F IR_owner, 104                 # owner and name (the manifest's spelling once staged)
F IR_name, 104
F IR_tag, 72                    # asked: "latest" or a tag; staged: the tag fetched
F IR_want, 72                   # the index's digest for this target, or "-"
F IR_sha, 72                    # the archive's digest
F IR_file, 8                    # owned cstr: the local archive or folder, or 0
F IR_tmp, 8                     # owned cstr: the job's .install-XXXXXX folder, or 0
F IR_err, 8                     # owned cstr: why it failed, or 0
F IR_kind, 4                    # IK_*
F IR_reviewed, 4                # the tag and digest are the index's
F IR_state, 4                   # IRS_*
F IR_member, 4                  # 1: a member of the batch's pack
F IR_pv, EXT_SIZE               # the manifest offered
ENDSTRUCT IR_SIZE

.bss
.p2align 3
in_out: .zero SB_SIZE           # the job's output
in_sb: .zero SB_SIZE            # scratch: paths, the dialog's strings, the record
in_words: .zero SB_SIZE         # what an update asks for in addition
in_title: .zero 256             # the dialog's question
in_text: .zero 4096             # its lines
in_pid: .long 0
ib_n: .long 0                   # requests in the batch
ib_cur: .long 0                 # the one the job works on
ib_purpose: .long 0             # IP_*
.p2align 3
ib_reqs: .zero IR_SIZE * IQ_MAX
.ifdef WINDOWS
.p2align 3
ei_vars: .zero 9 * SB_SIZE      # the job's RHUN_EI_* variables
ei_envp: .quad 0
ei_shell: .quad 0
ei_argv: .zero 64
.endif
.globl g_ext_install_state
g_ext_install_state: .long 0    # 0 idle, 1 downloading, 2 asking, 3 done, 4 failed (tests wait on it)
.p2align 3
rm_ext: .quad 0                 # the extension Remove asks about

.data
in_fd: .long -1

.text

# cmd_install_extension(): the palette asks for a repository name or GitHub URL
FN cmd_install_extension
    PROLOGUE
    lea rdi, [rip + .Lask]
    mov esi, PROMPT_EXT_INSTALL
    xor edx, edx
    xor ecx, ecx
    call palette_ext_prompt_open
    EPILOGUE

# cmd_install_extension_folder(), cmd_link_extension_folder(), cmd_install_extension_archive(): the
# palette asks for the folder or the archive
FN cmd_install_extension_folder
    lea rdi, [rip + .Lask_folder]
    mov esi, PROMPT_EXT_FOLDER
    jmp 1f
FN cmd_link_extension_folder
    lea rdi, [rip + .Lask_link]
    mov esi, PROMPT_EXT_LINK
    jmp 1f
FN cmd_install_extension_archive
    lea rdi, [rip + .Lask_archive]
    mov esi, PROMPT_EXT_ARCHIVE
1:  PROLOGUE
    xor edx, edx
    xor ecx, ecx
    call palette_ext_prompt_open
    EPILOGUE

# ext_install_prompt_done(ptr, len, kind PROMPT_EXT_*): the folder or archive the palette asked for
FN ext_install_prompt_done
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov ecx, IK_ARCHIVE
    cmp edx, PROMPT_EXT_ARCHIVE
    je 1f
    mov ecx, IK_LINK
    cmp edx, PROMPT_EXT_LINK
    je 1f
    mov ecx, IK_FOLDER
1:  mov rdi, rbx
    mov rsi, r12
    mov edx, ecx
    call ext_install_local
    EPILOGUE

# ext_install_start(ptr, len): owner/name[@VERSION], github.com/owner/name or https://github.com/...
FN ext_install_start
    PROLOGUE 336
    mov r12, rdi
    mov r13, rsi
    # drop a URL's scheme and host
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lgh]
    mov ecx, 11
    call str_find
    test rax, rax
    js 1f
    lea r12, [r12 + rax + 11]
    sub r13, rax
    sub r13, 11
1:  # owner, then name, each [A-Za-z0-9._-], not starting with a dot
    lea rdi, [rsp]
    call take_part
    test eax, eax
    jz .Lis_bad
    cmp r13, 0
    je .Lis_bad
    cmp byte ptr [r12], '/'
    jne .Lis_bad
    inc r12
    dec r13
    lea rdi, [rsp + 112]
    call take_part
    test eax, eax
    jz .Lis_bad
    # a name ending in .git loses it
    lea rdi, [rsp + 112]
    call strlen
    cmp rax, 4
    jbe 2f
    lea rcx, [rsp + 112]
    cmp dword ptr [rcx + rax - 4], 0x7469672e   # ".git"
    jne 2f
    mov byte ptr [rcx + rax - 4], 0
2:  # @VERSION: that release's tag (a version gets its "v")
    xor r14d, r14d
    test r13, r13
    jz 4f
    cmp byte ptr [r12], '@'
    jne 4f                      # the rest of a URL (/releases, .git) is ignored
    inc r12
    dec r13
    lea rdi, [rsp + 224 + 1]
    call take_part
    test eax, eax
    jz .Lis_bad
    lea r14, [rsp + 224 + 1]
    movzx eax, byte ptr [r14]
    sub eax, '0'
    cmp eax, 9
    ja 4f
    dec r14
    mov byte ptr [r14], 'v'
4:  lea rdi, [rsp]
    lea rsi, [rsp + 112]
    mov rdx, r14
    mov ecx, IP_ADD
    call ext_install_github
    EPILOGUE
.Lis_bad:
    mov dword ptr [rip + g_ext_install_state], 4
    lea rdi, [rip + .Le_name]
    call app_toast
    EPILOGUE

# ext_link_open(cstr) -> eax 1 when it is a rhun://extension/OWNER/NAME[@VERSION] link (the site
# catalog's Install buttons): the install starts and always asks (the scheme and "extension" in any
# case; a %40 may stand for the @)
FN ext_link_open
    PROLOGUE 128
    mov rbx, rdi
    lea rsi, [rip + .Lext_link]
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    movzx edx, byte ptr [rbx + rcx]
    lea r8d, [rdx - 'A']
    cmp r8d, 25
    ja 11f
    or edx, 0x20
11: cmp edx, eax
    jne 8f
    inc rcx
    jmp 1b
2:  # the rest, %40 decoded, at most 120 bytes
    lea rsi, [rbx + rcx]
    xor ecx, ecx
3:  movzx eax, byte ptr [rsi]
    test eax, eax
    jz 5f
    cmp eax, '?'
    je 5f
    cmp eax, '#'
    je 5f
    cmp ecx, 120
    jae 8f
    cmp eax, '%'
    jne 4f
    cmp byte ptr [rsi + 1], '4'
    jne 4f
    cmp byte ptr [rsi + 2], '0'
    jne 4f
    mov eax, '@'
    add rsi, 2
4:  mov [rsp + rcx], al
    inc ecx
    inc rsi
    jmp 3b
5:  test ecx, ecx
    jz 8f
    cmp byte ptr [rsp + rcx - 1], '/'
    jne 6f
    dec ecx
6:  lea rdi, [rsp]
    mov esi, ecx
    call ext_install_start
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ext_install_busy() -> 1 while a batch downloads or asks
FN ext_install_busy
    xor eax, eax
    cmp dword ptr [rip + g_ext_install_state], 1
    je 1f
    cmp dword ptr [rip + g_ext_install_state], 2
    jne 2f
1:  mov eax, 1
2:  ret

# ext_install_github(owner, name, tag or 0, purpose IP_*) -> eax 1 when the batch started: the tag
# asked for, else the version the extensions index pins (its digest checked), else the latest
# release's tag. Busy: a toast (not for automatic updates) and 0
FN ext_install_github
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15d, ecx
    call ext_install_busy
    test eax, eax
    jz 1f
    cmp r15d, IP_AUTO
    je 8f
    lea rdi, [rip + .Le_busy]
    call app_toast
    jmp 8f
1:  call batch_reset
    mov [rip + ib_purpose], r15d
    mov rdi, r12
    mov rsi, r13
    call batch_add
    mov rbx, rax
    test r14, r14
    jz 2f
    lea rdi, [rbx + IR_tag]
    mov rsi, r14
    mov ecx, 64
    call copy_max
2:  mov rdi, rbx
    call req_pin
    cmp r15d, IP_AUTO
    je 3f
    lea rdi, [rip + in_sb]
    call sb_clear
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_getting]
    call sb_push_cstr
    mov rdi, rbx
    call push_req_name
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Ldots]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call app_toast
3:  mov dword ptr [rip + g_ext_install_state], 1
    call batch_next
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# req_pin(ir): an extension the index lists installs its pinned tag, the archive matching its digest;
# a tag asked for that is the pinned one is reviewed too
req_pin:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    call extindex_entry
    test rax, rax
    jz 9f
    mov r14, rax
    # the reviewed version needs a newer rhun: it is not installed (an older tag asked for is)
    mov rdi, rax
    call extindex_newer
    test rax, rax
    jz 2f
    mov r15, rax
    lea rdi, [rbx + IR_tag]
    lea rsi, [rip + .Llatest]
    call strcmp_eq
    test eax, eax
    jnz 3f
    lea rdi, [rbx + IR_tag]
    mov rsi, [r14 + XI_tag]
    call strcmp_eq
    test eax, eax
    jz 9f
3:  lea rdi, [rip + in_words]
    call sb_clear
    lea rdi, [rip + in_words]
    lea rsi, [rip + .Le_newer]
    call sb_push_cstr
    lea rdi, [rip + in_words]
    mov rsi, r15
    call sb_push_cstr
    lea rdi, [rip + in_words]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + in_words + SB_ptr]
    call req_fail
    EPILOGUE
2:  mov rax, [r14 + XI_tag]
    mov rdx, [r14 + XI_digest]
    test rdx, rdx
    jz 9f
    mov r12, rax
    mov r13, rdx
    lea rdi, [rbx + IR_tag]
    lea rsi, [rip + .Llatest]
    call strcmp_eq
    test eax, eax
    jnz 1f
    lea rdi, [rbx + IR_tag]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 9f
1:  lea rdi, [rbx + IR_tag]
    mov rsi, r12
    mov ecx, 64
    call copy_max
    lea rdi, [rbx + IR_want]
    mov rsi, r13
    mov ecx, 64
    call copy_max
    mov dword ptr [rbx + IR_reviewed], 1
9:  EPILOGUE

# ext_install_local(ptr, len, kind IK_ARCHIVE | IK_FOLDER | IK_LINK): a release archive on this
# computer, or a folder holding extension.ini (copied, or linked for development); ~ is the home
FN ext_install_local
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    call ext_install_busy
    test eax, eax
    jz 1f
    lea rdi, [rip + .Le_busy]
    call app_toast
    EPILOGUE
1:  mov rdi, r12
    mov rsi, r13
    call trim
    mov r12, rax
    mov r13, rdx
    test r13, r13
    jz .Lil_bad
    cmp r13, 3000
    ja .Lil_bad
    xor ecx, ecx                # one line: the record holds it
2:  cmp rcx, r13
    jae 3f
    cmp byte ptr [r12 + rcx], 10
    je .Lil_bad
    cmp byte ptr [r12 + rcx], 13
    je .Lil_bad
    inc rcx
    jmp 2b
3:  lea rdi, [rip + in_sb]
    call sb_clear
    cmp byte ptr [r12], '~'
    jne 4f
    cmp r13, 1
    je 31f
    cmp byte ptr [r12 + 1], '/'
    jne 4f
31: lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 4f
    lea rdi, [rip + in_sb]
    mov rsi, rax
    call sb_push_cstr
    inc r12
    dec r13
4:  lea rdi, [rip + in_sb]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    call in_sb_cstr
    mov rbx, rax
    # absolute, normalized
.ifdef WINDOWS
    mov rdi, rbx
    call win_fullpath
    test rax, rax
    jz .Lil_bad
    mov r15, rax
.else
    PATH_ABSOLUTE rbx, 5f
    sub rsp, 4096
    mov rdi, rsp
    mov esi, 4000
    SYS SYS_getcwd
    mov rdi, rsp
    mov rsi, rbx
    call path_join
    add rsp, 4096
    mov r15, rax
    jmp 6f
5:  mov rdi, rbx
    call dup_cstr
    mov r15, rax
6:
.endif
    mov rdi, r15
    call path_normalize
    call batch_reset
    mov dword ptr [rip + ib_purpose], IP_ADD
    lea rdi, [rip + .Ldash]
    lea rsi, [rip + .Ldash]
    call batch_add
    mov [rax + IR_kind], r14d
    mov [rax + IR_file], r15
    mov dword ptr [rip + g_ext_install_state], 1
    call batch_next
    EPILOGUE
.Lil_bad:
    mov dword ptr [rip + g_ext_install_state], 4
    lea rdi, [rip + .Le_path]
    call app_toast
    EPILOGUE

# ---------------- the batch ----------------

# batch_reset(): the batch is empty: folders it downloaded and did not install go, strings are freed
batch_reset:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12d, [rip + ib_n]
    jae 8f
    imul rbx, r12, IR_SIZE
    lea rax, [rip + ib_reqs]
    add rbx, rax
    inc r12d
    mov rdi, [rbx + IR_tmp]
    test rdi, rdi
    jz 2f
    call file_remove_tree
    mov rdi, [rbx + IR_tmp]
    call mem_free
2:  mov rdi, [rbx + IR_file]
    call mem_free
    mov rdi, [rbx + IR_err]
    call mem_free
    lea rdi, [rbx + IR_pv]
    call extrec_pv_free
    jmp 1b
8:  mov dword ptr [rip + ib_n], 0
    mov dword ptr [rip + ib_newmembers], 0
    EPILOGUE

# batch_add(owner cstr, name cstr) -> IR*: a request for the latest release, or 0 when the batch is full
batch_add:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor eax, eax
    mov ecx, [rip + ib_n]
    cmp ecx, IQ_MAX
    jae 9f
    inc dword ptr [rip + ib_n]
    imul rbx, rcx, IR_SIZE
    lea rax, [rip + ib_reqs]
    add rbx, rax
    mov rdi, rbx
    xor esi, esi
    mov edx, IR_SIZE
    call memset
    lea rdi, [rbx + IR_owner]
    mov rsi, r12
    mov ecx, 100
    call copy_max
    lea rdi, [rbx + IR_name]
    mov rsi, r13
    mov ecx, 100
    call copy_max
    lea rdi, [rbx + IR_tag]
    lea rsi, [rip + .Llatest]
    call cstr_copy
    lea rdi, [rbx + IR_want]
    lea rsi, [rip + .Ldash]
    call cstr_copy
    mov rax, rbx
9:  EPILOGUE

# req_at(i) -> IR*
req_at:
    imul rax, rdi, IR_SIZE
    lea rcx, [rip + ib_reqs]
    add rax, rcx
    ret

# batch_next(): the next queued request's job starts (a link is read at once); none left: the batch
# is done
batch_next:
    PROLOGUE
1:  xor r12d, r12d
2:  cmp r12d, [rip + ib_n]
    jae .Lbn_done
    mov edi, r12d
    call req_at
    mov rbx, rax
    inc r12d
    cmp dword ptr [rbx + IR_state], IRS_QUEUED
    jne 2b
    lea eax, [r12 - 1]
    mov [rip + ib_cur], eax
    mov dword ptr [rbx + IR_state], IRS_RUNNING
    cmp dword ptr [rbx + IR_kind], IK_LINK
    jne 3f
    mov rdi, rbx
    call stage
    jmp 1b
3:  mov rdi, rbx
    call spawn_job
    test eax, eax
    jnz 9f
    mov rdi, rbx
    lea rsi, [rip + .Le_spawn]
    call req_fail
    jmp 1b
.Lbn_done:
    call batch_done
9:  EPILOGUE

# spawn_job(ir) -> eax 1 when the job runs
spawn_job:
    PROLOGUE 96
    mov rbx, rdi
.ifdef WINDOWS
    mov rdi, rbx
    call win_install_job        # rax argv, rdx envp
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    jmp 4f
.endif
    # argv: sh -c SCRIPT rhun-install OWNER NAME TARGET ROOT BASE TAG WANT FILE KIND
    lea rax, [rip + .Lsh]
    mov [rsp], rax
    lea rax, [rip + .Ldash_c]
    mov [rsp + 8], rax
    lea rax, [rip + install_script]
    mov [rsp + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rsp + 24], rax
    lea rax, [rbx + IR_owner]
    mov [rsp + 32], rax
    lea rax, [rbx + IR_name]
    mov [rsp + 40], rax
    lea rax, [rip + ext_target]
    mov [rsp + 48], rax
    call ext_root_dir
    mov [rsp + 56], rax
    call ext_release_base
    mov [rsp + 64], rax
    lea rax, [rbx + IR_tag]
    mov [rsp + 72], rax
    lea rax, [rbx + IR_want]
    mov [rsp + 80], rax
    mov rdi, rbx
    call req_file
    mov [rsp + 88], rax
    mov edi, [rbx + IR_kind]
    call kind_word
    mov [rsp + 96], rax
    mov qword ptr [rsp + 104], 0
    mov rdi, rsp
    mov rsi, [rip + g_envp]
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
4:  mov [rip + in_pid], eax
    mov [rip + in_fd], edx
    lea rdi, [rip + in_out]
    call sb_clear
    mov edi, [rip + in_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_install_job]
    xor ecx, ecx
    call watch_add
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# req_file(ir) -> its archive or folder, or "-"
req_file:
    mov rax, [rdi + IR_file]
    test rax, rax
    jnz 1f
    lea rax, [rip + .Ldash]
1:  ret

# kind_word(IK_*) -> "github", "archive" or "folder"
kind_word:
    lea rax, [rip + .Lk_github]
    cmp edi, IK_ARCHIVE
    jne 1f
    lea rax, [rip + .Lk_archive]
1:  cmp edi, IK_FOLDER
    jne 2f
    lea rax, [rip + .Lk_folder]
2:  ret

# ext_release_base() -> where releases are: RHUN_EXT_BASE, or https://github.com
FN ext_release_base
    PROLOGUE
    lea rdi, [rip + .Lenv_base]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 2f
1:  lea rax, [rip + .Lgithub]
2:  EPILOGUE

.ifdef WINDOWS
# win_install_job(ir) -> rax argv, rdx envp (0 when PowerShell is not there): powershell.exe runs
# runtime/windows/extinstall.ps1 (embedded by tools/build-windows.py as ext_install_script) with
# the job's arguments in RHUN_EI_* variables
win_install_job:
    PROLOGUE 80
    mov rbx, rdi
    mov rdi, [rip + ei_envp]
    call mem_free
    mov qword ptr [rip + ei_envp], 0
    mov rdi, [rip + ei_shell]
    call mem_free
    mov qword ptr [rip + ei_shell], 0
    lea rdi, [rip + ei_vars]
    lea rsi, [rip + .Lei_owner]
    lea rdx, [rbx + IR_owner]
    call ei_var
    mov [rsp], rax
    lea rdi, [rip + ei_vars + SB_SIZE]
    lea rsi, [rip + .Lei_name]
    lea rdx, [rbx + IR_name]
    call ei_var
    mov [rsp + 8], rax
    lea rdi, [rip + ei_vars + 2*SB_SIZE]
    lea rsi, [rip + .Lei_target]
    lea rdx, [rip + ext_target]
    call ei_var
    mov [rsp + 16], rax
    call ext_root_dir
    lea rdi, [rip + ei_vars + 3*SB_SIZE]
    lea rsi, [rip + .Lei_root]
    mov rdx, rax
    call ei_var
    mov [rsp + 24], rax
    call ext_release_base
    lea rdi, [rip + ei_vars + 4*SB_SIZE]
    lea rsi, [rip + .Lei_base]
    mov rdx, rax
    call ei_var
    mov [rsp + 32], rax
    lea rdi, [rip + ei_vars + 5*SB_SIZE]
    lea rsi, [rip + .Lei_tag]
    lea rdx, [rbx + IR_tag]
    call ei_var
    mov [rsp + 40], rax
    lea rdi, [rip + ei_vars + 6*SB_SIZE]
    lea rsi, [rip + .Lei_want]
    lea rdx, [rbx + IR_want]
    call ei_var
    mov [rsp + 48], rax
    mov rdi, rbx
    call req_file
    lea rdi, [rip + ei_vars + 7*SB_SIZE]
    lea rsi, [rip + .Lei_file]
    mov rdx, rax
    call ei_var
    mov [rsp + 56], rax
    mov edi, [rbx + IR_kind]
    call kind_word
    lea rdi, [rip + ei_vars + 8*SB_SIZE]
    lea rsi, [rip + .Lei_kind]
    mov rdx, rax
    call ei_var
    mov [rsp + 64], rax
    mov qword ptr [rsp + 72], 0
    mov rdi, rsp
    call env_make
    mov [rip + ei_envp], rax
    lea rdi, [rip + .Lei_shell]
    call proc_which
    mov [rip + ei_shell], rax
    test rax, rax
    jz 9f
    lea rcx, [rip + ei_argv]
    mov [rcx], rax
    lea rax, [rip + .Lei_noprofile]
    mov [rcx + 8], rax
    lea rax, [rip + .Lei_noninteractive]
    mov [rcx + 16], rax
    lea rax, [rip + .Lei_outputformat]
    mov [rcx + 24], rax
    lea rax, [rip + .Lei_text]
    mov [rcx + 32], rax
    lea rax, [rip + .Lei_encoded]
    mov [rcx + 40], rax
    lea rax, [rip + ext_install_script]
    mov [rcx + 48], rax
    mov qword ptr [rcx + 56], 0
    mov rax, rcx
    mov rdx, [rip + ei_envp]
    EPILOGUE
9:  xor eax, eax
    xor edx, edx
    EPILOGUE

# ei_var(sb, "NAME=", value) -> the cstr "NAME=value" in sb
FN ei_var
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call sb_clear
    mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r13
    call sb_push_cstr
    mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    mov rax, [rbx + SB_ptr]
    EPILOGUE
.endif

# on_install_job(fd, revents, ctx): the job's output; at its end, the request is staged or failed
# and the batch goes on
on_install_job:
    PROLOGUE
1:  lea rdi, [rip + in_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + in_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    cmp qword ptr [rip + in_out + SB_len], 65536
    jae 1b
    add [rip + in_out + SB_len], rax
    jmp 1b
2:  mov edi, [rip + in_fd]
    call watch_remove
    mov edi, [rip + in_fd]
    SYS SYS_close
    mov dword ptr [rip + in_fd], -1
    mov edi, [rip + in_pid]
    xor esi, esi
    call proc_wait
    mov r13d, eax
    mov edi, [rip + ib_cur]
    call req_at
    mov rbx, rax
    # the last line: "ok SHA256 TAG DIR", or why it failed
    lea rdi, [rip + in_out]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + in_out + SB_ptr]
    mov rsi, [rip + in_out + SB_len]
    dec rsi
3:  test rsi, rsi
    jz 4f
    cmp byte ptr [rdi + rsi - 1], 10
    je 31f
    cmp byte ptr [rdi + rsi - 1], 13    # PowerShell ends its lines with CR LF
    jne 4f
31: dec rsi
    mov byte ptr [rdi + rsi], 0
    jmp 3b
4:  mov rcx, rsi                # the last line starts after the last LF
5:  test rcx, rcx
    jz 6f
    cmp byte ptr [rdi + rcx - 1], 10
    je 6f
    dec rcx
    jmp 5b
6:  lea r12, [rdi + rcx]
    test r13d, r13d
    jnz .Loi_failed
    cmp word ptr [r12], 0x6b6f     # "ok"
    jne .Loi_failed
    cmp byte ptr [r12 + 2], ' '
    jne .Loi_failed
    add r12, 3
    lea rdi, [rbx + IR_sha]
    mov esi, 70
    call take_word
    lea rdi, [rbx + IR_tag]
    mov esi, 70
    call take_word
    cmp byte ptr [r12], 0
    je .Loi_failed
    mov rdi, r12
    call dup_cstr
    mov [rbx + IR_tmp], rax
    mov rdi, rbx
    call stage
    jmp 8f
.Loi_failed:
    mov rsi, r12
    cmp byte ptr [r12], 0
    jne 7f
    lea rsi, [rip + .Le_unknown]
7:  mov rdi, rbx
    call req_fail
8:  call batch_next
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# take_word(dst, max): r12's word (up to a space) into dst, r12 after it and its space
take_word:
    xor ecx, ecx
1:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 3f
    inc r12
    cmp eax, ' '
    je 3f
    cmp ecx, esi
    jae 1b
    mov [rdi + rcx], al
    inc ecx
    jmp 1b
3:  mov byte ptr [rdi + rcx], 0
    ret

# req_fail(ir, why cstr): the request failed; its folder goes
req_fail:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov dword ptr [rbx + IR_state], IRS_FAILED
    mov rdi, [rbx + IR_err]
    call mem_free
    mov rdi, r12
    call dup_cstr
    mov [rbx + IR_err], rax
    mov rdi, [rbx + IR_tmp]
    test rdi, rdi
    jz 9f
    call file_remove_tree
    mov rdi, [rbx + IR_tmp]
    call mem_free
    mov qword ptr [rbx + IR_tmp], 0
9:  EPILOGUE

# stage(ir): the downloaded (or linked) folder's manifest is read and checked against the request;
# a pack's members join the batch
stage:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call req_manifest_dir
    lea rdi, [rip + in_sb]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lslash_manifest]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    mov esi, EXT_MANIFEST_MAX
    call file_read_limited
    test rax, rax
    jz .Lst_bad
    mov r12, rax
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rbx + IR_pv]
    call ext_preview
    mov r13d, eax
    mov rdi, r12
    call mem_free
    test r13d, r13d
    jz .Lst_bad
    cmp dword ptr [rbx + IR_kind], IK_GITHUB
    jne 2f
    # from GitHub: the manifest must be the extension asked for (GitHub names ignore case: the
    # manifest's spelling names the folders)
    mov rdi, [rbx + IR_pv + EXT_mowner]
    lea rsi, [rbx + IR_owner]
    call same_ci
    test eax, eax
    jz .Lst_other
    mov rdi, [rbx + IR_pv + EXT_mname]
    lea rsi, [rbx + IR_name]
    call same_ci
    test eax, eax
    jz .Lst_other
    jmp 3f
2:  # from this computer: the manifest names it, as folder names
    mov rdi, [rbx + IR_pv + EXT_mowner]
    call name_ok
    test eax, eax
    jz .Lst_names
    mov rdi, [rbx + IR_pv + EXT_mname]
    call name_ok
    test eax, eax
    jz .Lst_names
3:  lea rdi, [rbx + IR_owner]
    mov rsi, [rbx + IR_pv + EXT_mowner]
    call cstr_copy
    lea rdi, [rbx + IR_name]
    mov rsi, [rbx + IR_pv + EXT_mname]
    call cstr_copy
    # a release fetched as releases/latest (a file:// tree) is named by its version
    lea rdi, [rbx + IR_tag]
    lea rsi, [rip + .Llatest]
    call strcmp_eq
    test eax, eax
    jz 4f
    lea rdi, [rbx + IR_tag]
    mov byte ptr [rdi], 'v'
    inc rdi
    mov rsi, [rbx + IR_pv + EXT_version]
    mov ecx, 60
    call copy_max
4:  mov dword ptr [rbx + IR_state], IRS_STAGED
    # a pack added (or updated) by hand: its members not installed yet come along; an automatic
    # update that would add members waits for the user
    cmp dword ptr [rbx + IR_member], 0
    jne 9f
    cmp qword ptr [rbx + IR_pv + EXT_pack], 0
    je 9f
    cmp dword ptr [rip + ib_purpose], IP_AUTO
    je 5f
    mov rdi, rbx
    call pack_queue
9:  EPILOGUE
5:  mov rdi, rbx
    call pack_missing
    mov [rip + ib_newmembers], eax
    EPILOGUE
.Lst_bad:
    mov rdi, rbx
    lea rsi, [rip + .Le_manifest]
    call req_fail
    EPILOGUE
.Lst_other:
    mov rdi, rbx
    lea rsi, [rip + .Le_other]
    call req_fail
    EPILOGUE
.Lst_names:
    mov rdi, rbx
    lea rsi, [rip + .Le_names]
    call req_fail
    EPILOGUE

# copy_max(dst, src, max) -> rax the end (its NUL): at most max bytes of src
copy_max:
    xor edx, edx
1:  cmp edx, ecx
    jae 2f
    mov al, [rsi + rdx]
    test al, al
    jz 2f
    mov [rdi + rdx], al
    inc edx
    jmp 1b
2:  mov byte ptr [rdi + rdx], 0
    lea rax, [rdi + rdx]
    ret

# req_manifest_dir(ir) -> where its manifest is: the unpacked folder, or the linked one
req_manifest_dir:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + IR_file]
    cmp dword ptr [rbx + IR_kind], IK_LINK
    je 9f
    lea rdi, [rip + in_words]
    call sb_clear
    lea rdi, [rip + in_words]
    mov rsi, [rbx + IR_tmp]
    call sb_push_cstr
    lea rdi, [rip + in_words]
    lea rsi, [rip + .Lslash_x]
    call sb_push_cstr
    lea rdi, [rip + in_words]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + in_words + SB_ptr]
9:  EPILOGUE

# name_ok(cstr) -> 1 for [A-Za-z0-9._-]{1,100} not starting with a dot (a folder name)
name_ok:
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp byte ptr [rdi], '.'
    je 9f
    xor ecx, ecx
1:  movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 8f
    inc ecx
    cmp ecx, 100
    ja 9f
    call name_char
    test r8d, r8d
    jnz 1b
    ret
8:  test ecx, ecx
    setnz al
9:  ret

# name_char(edx) -> r8d 1 for [A-Za-z0-9._-]
name_char:
    mov r8d, 1
    cmp edx, '.'
    je 1f
    cmp edx, '_'
    je 1f
    cmp edx, '-'
    je 1f
    lea r9d, [rdx - '0']
    cmp r9d, 9
    jbe 1f
    mov r9d, edx
    or r9d, 0x20
    sub r9d, 'a'
    cmp r9d, 25
    jbe 1f
    xor r8d, r8d
1:  ret

# pack_queue(pack ir): each member of its pack list not installed yet joins the batch (at most 16)
pack_queue:
    PROLOGUE 240
    mov rbx, rdi
    mov r14, [rbx + IR_pv + EXT_pack]
1:  mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call next_word
    add r14, rcx
    test rdx, rdx
    jz 9f
    cmp rdx, 200
    jae 1b
    mov r12, rax
    mov r13, rdx
    # installed already (a live record of that name)?
    mov rdi, r12
    mov rsi, r13
    call ext_by_name
    test rax, rax
    jnz 1b
    # OWNER/NAME: the parts into the frame
    lea rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call split_full
    test eax, eax
    jz 1b
    # in the batch already?
    lea rdi, [rsp]
    lea rsi, [rsp + 112]
    call batch_has
    test eax, eax
    jnz 1b
    lea rdi, [rsp]
    lea rsi, [rsp + 112]
    call batch_add
    test rax, rax
    jz 9f
    mov dword ptr [rax + IR_member], 1
    mov rdi, rax
    call req_pin
    jmp 1b
9:  EPILOGUE

# pack_missing(pack ir) -> eax 1 when its pack list names an extension that is not installed
pack_missing:
    PROLOGUE
    mov rbx, rdi
    mov r14, [rbx + IR_pv + EXT_pack]
1:  mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call next_word
    add r14, rcx
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jnz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# split_full(dst, ptr, len) -> eax 1: "owner/name" into dst (owner) and dst + 112 (name), each a
# folder name
split_full:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor ecx, ecx
1:  cmp rcx, r13
    jae 8f
    cmp byte ptr [r12 + rcx], '/'
    je 2f
    inc rcx
    jmp 1b
2:  cmp rcx, 100
    ja 8f
    mov r14, rcx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call memcpy
    mov byte ptr [rbx + r14], 0
    lea rsi, [r12 + r14 + 1]
    mov rdx, r13
    sub rdx, r14
    dec rdx
    cmp rdx, 100
    ja 8f
    mov r15, rdx
    lea rdi, [rbx + 112]
    call memcpy
    mov byte ptr [rbx + 112 + r15], 0
    mov rdi, rbx
    call name_ok
    test eax, eax
    jz 8f
    lea rdi, [rbx + 112]
    call name_ok
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# batch_has(owner, name) -> 1 when the batch has a request for it (ignoring case)
batch_has:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
1:  cmp r14d, [rip + ib_n]
    jae 8f
    mov edi, r14d
    call req_at
    mov rbx, rax
    inc r14d
    lea rdi, [rbx + IR_owner]
    mov rsi, r12
    call same_ci
    test eax, eax
    jz 1b
    lea rdi, [rbx + IR_name]
    mov rsi, r13
    call same_ci
    test eax, eax
    jz 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# batch_done(): every request ran: nothing downloaded says why; a single extension or a pack is
# offered; an update is asked about or installed (extupdate.s hears how it ended)
batch_done:
    PROLOGUE
    xor r12d, r12d              # staged
    xor r13d, r13d              # the first failed
    xor r14d, r14d
1:  cmp r14d, [rip + ib_n]
    jae 2f
    mov edi, r14d
    call req_at
    inc r14d
    cmp dword ptr [rax + IR_state], IRS_STAGED
    jne 11f
    inc r12d
    jmp 1b
11: cmp dword ptr [rax + IR_state], IRS_FAILED
    jne 1b
    test r13, r13
    jnz 1b
    mov r13, rax
    jmp 1b
2:  xor edi, edi
    call req_at
    mov rbx, rax                # the request asked for
    cmp dword ptr [rbx + IR_state], IRS_STAGED
    jne .Lbd_failed
    mov eax, [rip + ib_purpose]
    cmp eax, IP_UPDATE
    je .Lbd_update
    cmp eax, IP_AUTO
    je .Lbd_update
    cmp dword ptr [rip + ib_n], 1
    ja .Lbd_pack
    mov rdi, rbx
    call add_dialog
    EPILOGUE
.Lbd_pack:
    call pack_dialog
    EPILOGUE
.Lbd_update:
    cmp dword ptr [rip + ib_n], 1
    ja .Lbd_pack                # a pack's update that adds members asks about them
    mov rdi, rbx
    call update_decide
    EPILOGUE
.Lbd_failed:
    mov dword ptr [rip + g_ext_install_state], 4
    mov r12, [rbx + IR_err]
    test r12, r12
    jnz 3f
    lea r12, [rip + .Le_unknown]
3:  cmp dword ptr [rip + ib_purpose], IP_ADD
    je 4f
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    lea rsi, [rbx + IR_tag]
    mov edx, XU_FAILED
    mov rcx, r12
    call extupdate_install_done
    cmp dword ptr [rip + ib_purpose], IP_AUTO
    je 8f                       # automatic: the Extensions page shows the error
4:  lea rdi, [rip + in_sb]
    call sb_clear
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_cannot]
    call sb_push_cstr
    mov rdi, rbx
    call push_req_name
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, r12
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call app_toast
8:  call batch_reset
    EPILOGUE

# push_req_name(ir): "owner/name" onto in_sb (an archive's or folder's file name before its
# manifest is read)
push_req_name:
    PROLOGUE
    mov rbx, rdi
    cmp byte ptr [rbx + IR_owner], '-'
    jne 1f
    mov rsi, [rbx + IR_file]
    test rsi, rsi
    jz 1f
    mov rdi, rsi
    call strlen
    mov rdi, [rbx + IR_file]
    mov rsi, rax
    call path_basename
    lea rdi, [rip + in_sb]
    mov rsi, rax
    call sb_push_cstr
    EPILOGUE
1:  lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_owner]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_name]
    call sb_push_cstr
    EPILOGUE

# in_sb_cstr() -> in_sb as a cstr
in_sb_cstr:
    push rbx
    lea rdi, [rip + in_sb]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + in_sb + SB_len]
    mov rax, [rip + in_sb + SB_ptr]
    pop rbx
    ret

# ---------------- what is asked ----------------

# source_line(ir): "Version V from github.com/O/N. It can ..." onto in_sb, with the index's word for a
# GitHub release on a line of its own
source_line:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_version]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, [rbx + IR_pv + EXT_version]
    call sb_push_cstr
    mov eax, [rbx + IR_kind]
    cmp eax, IK_GITHUB
    jne 1f
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_from]
    call sb_push_cstr
    mov rdi, rbx
    call push_req_name
    jmp 4f
1:  lea rsi, [rip + .Lt_from_archive]
    cmp eax, IK_ARCHIVE
    je 2f
    lea rsi, [rip + .Lt_from_folder]
    cmp eax, IK_FOLDER
    je 2f
    lea rsi, [rip + .Lt_linked]
2:  lea rdi, [rip + in_sb]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, [rbx + IR_file]
    call sb_push_cstr
    cmp dword ptr [rbx + IR_kind], IK_LINK
    jne 4f
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_development]
    call sb_push_cstr
4:  lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_it_can]
    call sb_push_cstr
    lea rdi, [rbx + IR_pv]
    lea rsi, [rip + in_sb]
    call ext_needs_words
    lea rdi, [rip + in_sb]
    mov esi, '.'
    call sb_push_byte
    cmp dword ptr [rbx + IR_kind], IK_GITHUB
    jne 9f
    lea rsi, [rip + .Lt_reviewed]
    cmp dword ptr [rbx + IR_reviewed], 0
    jne 5f
    lea rsi, [rip + .Lt_unreviewed]
5:  lea rdi, [rip + in_sb]
    call sb_push_cstr
9:  EPILOGUE

# text_from_sb(): in_sb into in_text (cut to its size)
text_from_sb:
    PROLOGUE
    call in_sb_cstr
    lea rdi, [rip + in_text]
    mov rsi, rax
    mov rcx, [rip + in_sb + SB_len]
    cmp rcx, 4000
    jbe 1f
    mov ecx, 4000
1:  mov rdx, rcx
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    lea rax, [rip + in_text]
    mov byte ptr [rax + rdx], 0
    EPILOGUE

# add_dialog(ir): "Add “Title”?" with where it comes from and what it can do
add_dialog:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_title]
    lea rsi, [rip + .Lq_add]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_title]
    call ext_copy_title
    mov rdi, rax
    lea rsi, [rip + .Lq_end]
    call cstr_copy
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call source_line
    call text_from_sb
    lea rdx, [rip + .Lb_add]
    call ask
    EPILOGUE

# pack_dialog(): "Add “Essentials” and 3 extensions?", a line per member and per failure
pack_dialog:
    PROLOGUE
    xor edi, edi
    call req_at
    mov rbx, rax
    xor r12d, r12d              # members staged
    mov r13d, 1
1:  cmp r13d, [rip + ib_n]
    jae 2f
    mov edi, r13d
    call req_at
    inc r13d
    cmp dword ptr [rax + IR_state], IRS_STAGED
    jne 1b
    inc r12d
    jmp 1b
2:  cmp dword ptr [rip + ib_purpose], IP_ADD
    je 22f
    # "Update “Essentials” to 0.2.0?"
    lea rdi, [rip + in_title]
    lea rsi, [rip + .Lq_update]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_title]
    call ext_copy_title
    mov rdi, rax
    lea rsi, [rip + .Lq_close_to]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_version]
    mov ecx, 60
    call copy_max
    mov byte ptr [rax], '?'
    mov byte ptr [rax + 1], 0
    jmp 4f
22: lea rdi, [rip + in_title]
    lea rsi, [rip + .Lq_add]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_title]
    call ext_copy_title
    mov r14, rax
    test r12d, r12d
    jz 3f
    mov rdi, r14
    lea rsi, [rip + .Lq_close_and]
    call cstr_copy
    mov rdi, rax
    mov esi, r12d
    call fmt_u64                # rdi: after the digits
    lea rsi, [rip + .Lq_extensions]
    cmp r12d, 1
    jne 21f
    lea rsi, [rip + .Lq_extension]
21: call cstr_copy
    mov r14, rax
    mov rdi, r14
    lea rsi, [rip + .Lq_mark]
    call cstr_copy
    jmp 4f
3:  mov rdi, r14
    lea rsi, [rip + .Lq_end]
    call cstr_copy
4:  # the pack's own line, then each member's
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call source_line
    mov r13d, 1
5:  cmp r13d, [rip + ib_n]
    jae 8f
    mov edi, r13d
    call req_at
    mov r14, rax
    inc r13d
    lea rdi, [rip + in_sb]
    mov esi, 10
    call sb_push_byte
    cmp dword ptr [r14 + IR_state], IRS_STAGED
    jne 6f
    # "Format 0.2.0: read and change the files you have open, run gofmt"
    lea rdi, [rip + in_sb]
    mov rsi, [r14 + IR_pv + EXT_title]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + in_sb]
    mov rsi, [r14 + IR_pv + EXT_version]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    lea rdi, [r14 + IR_pv]
    lea rsi, [rip + in_sb]
    call ext_needs_words
    jmp 5b
6:  # "Could not get x/y: reason"
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_could_not_get]
    call sb_push_cstr
    mov rdi, r14
    call push_req_name
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lcolon]
    call sb_push_cstr
    mov rsi, [r14 + IR_err]
    test rsi, rsi
    jnz 7f
    lea rsi, [rip + .Le_unknown]
7:  lea rdi, [rip + in_sb]
    call sb_push_cstr
    jmp 5b
8:  call text_from_sb
    mov dword ptr [rip + ib_wider], 1   # Cancel of a pack's update that adds members: it waits
    lea rdx, [rip + .Lb_add]
    cmp dword ptr [rip + ib_purpose], IP_ADD
    je 81f
    lea rdx, [rip + .Lb_update]
81: call ask
    EPILOGUE

# update_decide(ir): an update is downloaded. One that asks for more, or that nobody reviewed and
# was asked for by hand, asks; an automatic one never asks: one that asks for more waits for the
# user (asks), the others are installed
update_decide:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_words]
    call sb_clear
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    mov rsi, [rip + in_sb + SB_len]
    call ext_by_name
    xor r12d, r12d              # wider
    test rax, rax
    jz 1f
    mov rdi, rax
    lea rsi, [rbx + IR_pv]
    lea rdx, [rip + in_words]
    call ext_needs_wider
    mov r12d, eax
1:  or r12d, [rip + ib_newmembers]   # a pack that would add extensions asks too
    cmp dword ptr [rip + ib_purpose], IP_AUTO
    jne 3f
    test r12d, r12d
    jz 2f
    mov edx, XU_ASKS            # it waits for the user
    call update_end
    EPILOGUE
2:  call install_commit
    EPILOGUE
3:  test r12d, r12d
    jnz 4f
    cmp dword ptr [rbx + IR_reviewed], 0
    je 4f
    call install_commit
    EPILOGUE
4:  # "Update “Showcase” to 0.2.0?"
    lea rdi, [rip + in_title]
    lea rsi, [rip + .Lq_update]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_title]
    call ext_copy_title
    mov rdi, rax
    lea rsi, [rip + .Lq_close_to]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + IR_pv + EXT_version]
    mov ecx, 60
    call copy_max
    mov byte ptr [rax], '?'
    mov byte ptr [rax + 1], 0
    lea rdi, [rip + in_sb]
    call sb_clear
    cmp dword ptr [rbx + IR_reviewed], 0
    jne 5f
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_nobody]
    call sb_push_cstr
5:  test r12d, r12d
    jz 6f
    cmp qword ptr [rip + in_sb + SB_len], 0
    je 51f
    lea rdi, [rip + in_sb]
    mov esi, 10
    call sb_push_byte
51: lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_now_also]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, [rip + in_words + SB_ptr]
    mov rdx, [rip + in_words + SB_len]
    call sb_push
    lea rdi, [rip + in_sb]
    mov esi, '.'
    call sb_push_byte
6:  call text_from_sb
    mov [rip + ib_wider], r12d
    lea rdx, [rip + .Lb_update]
    call ask
    EPILOGUE

# ask(button cstr): the dialog with in_title and in_text; Add/Update commits the batch, Cancel
# throws it away
ask:
    PROLOGUE
    mov rbx, rdx
    mov dword ptr [rip + g_ext_install_state], 2
    lea rdi, [rip + in_title]
    lea rsi, [rip + in_text]
    mov rdx, rbx
    lea rcx, [rip + install_commit]
    call app_confirm
    lea rdi, [rip + install_discard]
    call app_confirm_cancel
    EPILOGUE

# update_end(XU_*): an update ended without being installed: extupdate.s hears it, the batch goes
update_end:
    PROLOGUE
    mov r13d, edx
    xor edi, edi
    call req_at
    mov rbx, rax
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    lea rsi, [rbx + IR_tag]
    mov edx, r13d
    xor ecx, ecx
    call extupdate_install_done
    mov dword ptr [rip + g_ext_install_state], 0
    call batch_reset
    EPILOGUE

# install_discard(): Cancel: the downloaded folders go (an update that asks for more waits)
install_discard:
    PROLOGUE
    cmp dword ptr [rip + g_ext_install_state], 2
    jne 9f
    mov eax, [rip + ib_purpose]
    cmp eax, IP_ADD
    je 1f
    mov edx, XU_CANCELLED
    cmp dword ptr [rip + ib_wider], 0
    je 2f
    mov edx, XU_ASKS
2:  call update_end
    EPILOGUE
1:  mov dword ptr [rip + g_ext_install_state], 0
    call batch_reset
9:  EPILOGUE

# ext_copy_title(dst, cstr) -> rax the end (its NUL): at most TITLE_MAX bytes of a manifest's title,
# cut between characters and ended with "…" when it is longer
.equ TITLE_MAX, 120
FN ext_copy_title
    test rsi, rsi
    jnz 0f
    lea rsi, [rip + .Lempty]
0:  xor ecx, ecx
1:  mov al, [rsi + rcx]
    test al, al
    jz 3f
    inc rcx
    cmp rcx, TITLE_MAX
    jb 1b
    cmp byte ptr [rsi + rcx], 0
    je 3f
    # too long: back to the start of a character, then the ellipsis
2:  mov al, [rsi + rcx]
    and al, 0xc0
    cmp al, 0x80
    jne 4f
    dec rcx
    jnz 2b
4:  push rcx
    push rcx
    mov rdx, rcx
    call memcpy                 # rax: dst (memcpy returns it)
    pop rcx
    pop rcx
    add rax, rcx
    mov byte ptr [rax], 0xe2
    mov byte ptr [rax + 1], 0x80
    mov byte ptr [rax + 2], 0xa6
    mov byte ptr [rax + 3], 0
    add rax, 3
    ret
3:  jmp cstr_copy

# same_ci(a, b) -> 1 when the cstrs are equal ignoring ASCII case
same_ci:
1:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    lea edx, [rax - 'A']
    cmp edx, 25
    ja 2f
    add eax, 32
2:  lea edx, [rcx - 'A']
    cmp edx, 25
    ja 3f
    add ecx, 32
3:  cmp eax, ecx
    jne 8f
    test eax, eax
    jz 9f
    inc rdi
    inc rsi
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# take_part(buf): copy [A-Za-z0-9._-]+ from r12/r13 into buf (at most 100), advancing them -> 1 when
# something was taken and it does not start with a dot
take_part:
    xor ecx, ecx
1:  test r13, r13
    jz 3f
    movzx edx, byte ptr [r12]
    push rcx
    call name_char
    pop rcx
    test r8d, r8d
    jz 3f
    cmp ecx, 100
    jae 8f
    mov [rdi + rcx], dl
    inc ecx
    inc r12
    dec r13
    jmp 1b
3:  mov byte ptr [rdi + rcx], 0
    test ecx, ecx
    jz 8f
    cmp byte ptr [rdi], '.'
    je 8f
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ---------------- putting it in place ----------------

# install_commit(): Add or Update (or an automatic update): every downloaded request goes into
# OWNER/NAME, the installed version stepping aside as the previous one; loaded and started
install_commit:
    PROLOGUE 16
    mov dword ptr [rsp], 0      # installed
    mov qword ptr [rsp + 8], 0  # the first one's record
    xor r12d, r12d
1:  cmp r12d, [rip + ib_n]
    jae 2f
    mov edi, r12d
    call req_at
    mov rbx, rax
    inc r12d
    cmp dword ptr [rbx + IR_state], IRS_STAGED
    jne 1b
    mov rdi, rbx
    call commit_one
    test rax, rax
    jz 1b
    inc dword ptr [rsp]
    cmp qword ptr [rsp + 8], 0
    jne 1b
    mov [rsp + 8], rax
    jmp 1b
2:  mov rbx, [rsp + 8]
    test rbx, rbx
    jz .Lic_none
    mov dword ptr [rip + g_ext_install_state], 3
    lea rdi, [rip + in_sb]
    call sb_clear
    mov eax, [rip + ib_purpose]
    cmp eax, IP_ADD
    jne 4f
    # "Added Hello. Its commands are in the command palette." / "Added Essentials and 3 extensions"
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_added]
    call sb_push_cstr
    mov rdi, rbx
    call push_title
    mov eax, [rsp]
    cmp eax, 1
    je 3f
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lq_and]
    call sb_push_cstr
    mov esi, [rsp]
    dec esi
    lea rdi, [rip + in_sb]
    call sb_push_u64
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lq_extensions]
    cmp dword ptr [rsp], 2
    jne 21f
    lea rsi, [rip + .Lq_extension]
21: call sb_push_cstr
    jmp 8f
3:  lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_added_end]
    call sb_push_cstr
    jmp 8f
4:  # "Updated Showcase to 0.1.2"
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_updated]
    call sb_push_cstr
    mov rdi, rbx
    call push_title
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lq_to]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, [rbx + EXT_version]
    call sb_push_cstr
    xor edi, edi
    call req_at
    lea r13, [rax + IR_tag]
    mov rdi, rbx
    call ext_full_name
    mov rdi, rax
    mov rsi, r13
    mov edx, XU_UPDATED
    xor ecx, ecx
    call extupdate_install_done
8:  call in_sb_cstr
    mov rdi, rax
    call app_toast
    jmp 9f
.Lic_none:
    mov dword ptr [rip + g_ext_install_state], 4
    cmp dword ptr [rip + ib_purpose], IP_ADD
    je 9f
    xor edi, edi
    call req_at
    mov rbx, rax
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    lea rsi, [rbx + IR_tag]
    mov edx, XU_FAILED
    lea rcx, [rip + .Le_move]
    call extupdate_install_done
9:  call batch_reset
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# push_title(ext): its title (or name) onto in_sb
push_title:
    mov rsi, [rdi + EXT_title]
    test rsi, rsi
    jnz 1f
    mov rsi, [rdi + EXT_name]
1:  lea rdi, [rip + in_sb]
    jmp sb_push_cstr

# commit_one(ir) -> rax the installed record, or 0 (a toast says why): its folder takes the place of
# ROOT/OWNER/NAME, whose earlier content becomes ROOT/.previous/OWNER/NAME (replacing an older
# previous version); a link gets a stub folder holding only its record
commit_one:
    PROLOGUE 16
    mov rbx, rdi
    xor r14d, r14d              # the installed version moved aside
    xor r15d, r15d              # its record, retired
    mov qword ptr [rsp], 0      # the new folder (owned)
    mov qword ptr [rsp + 8], 0
    xor r12d, r12d
    xor r13d, r13d
    # a record for it first: nothing on disk changes when the table has no room (an installed
    # version's record, or a removed one's, is used again)
    call ext_slot_free
    test eax, eax
    jnz 0f
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    mov rsi, [rip + in_sb + SB_len]
    call ext_by_name
    test rax, rax
    jz .Lco_full
0:
    # ROOT/OWNER/NAME and ROOT/.previous/OWNER/NAME
    lea rdi, [rip + .Lempty]
    call root_path
    lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_owner]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call mkdir_p
    lea rdi, [rip + in_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_name]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call dup_cstr
    mov r12, rax
    lea rdi, [rip + .Lprevious]
    call root_path
    lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_owner]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call mkdir_p
    lea rdi, [rip + in_sb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + in_sb]
    lea rsi, [rbx + IR_name]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    call dup_cstr
    mov r13, rax
    # the record goes into the new folder before it moves
    cmp dword ptr [rbx + IR_kind], IK_LINK
    je 1f
    mov rdi, rbx
    call req_manifest_dir
    mov rdi, rax
    call dup_cstr
    mov [rsp], rax
    mov rdi, rax
    mov rsi, rbx
    call record_write
    test eax, eax
    jz .Lco_fail
1:  # an installed version stops and steps aside
    lea rdi, [rip + in_sb]
    call sb_clear
    mov rdi, rbx
    call push_req_name
    call in_sb_cstr
    mov rdi, rax
    mov rsi, [rip + in_sb + SB_len]
    call ext_by_name
    mov r15, rax
    test rax, rax
    jz 2f
    xor ecx, ecx
    cmp [rip + g_xp_detail], rax
    sete cl
    mov [rsp + 8], ecx          # its details are shown: the new version's will be
    mov rdi, rax
    call ext_retire
2:  mov rdi, r13
    call file_remove_tree
    mov rdi, r12
    mov rsi, r13
    SYS SYS_rename
    test rax, rax
    jz 21f
    cmp rax, -2                 # nothing installed there
    jne .Lco_keep
    jmp 3f
21: mov r14d, 1
3:  cmp dword ptr [rbx + IR_kind], IK_LINK
    jne 4f
    mov rdi, r12
    call mkdir_p
    mov rdi, r12
    mov rsi, rbx
    call record_write
    test eax, eax
    jnz 5f
    mov rdi, r12                # the stub this made
    call file_remove_tree
    jmp .Lco_back
4:  mov rdi, [rsp]
    mov rsi, r12
    SYS SYS_rename
    test rax, rax
    js .Lco_back
    mov rdi, [rbx + IR_tmp]
    call file_remove_tree
    mov rdi, [rbx + IR_tmp]
    call mem_free
    mov qword ptr [rbx + IR_tmp], 0
5:  mov dword ptr [rbx + IR_state], IRS_DONE
    call co_slot                # the installed version's record is used again
    # loaded, its choices read, its commands in the palette, and started
    mov rdi, r12
    lea rsi, [rbx + IR_owner]
    lea rdx, [rbx + IR_name]
    call ext_install_load
    test rax, rax
    jz .Lco_full
    mov rbx, rax
    cmp dword ptr [rsp + 8], 0
    je 9f
    mov [rip + g_xp_detail], rax
    jmp 9f
.Lco_back:
    # the installed version comes back
    test r14d, r14d
    jz .Lco_keep
    mov rdi, r13
    mov rsi, r12
    SYS SYS_rename
.Lco_keep:
    # and runs again
    test r15, r15
    jz .Lco_fail
    call co_slot
    mov rdi, r12
    lea rsi, [rbx + IR_owner]
    lea rdx, [rbx + IR_name]
    call ext_install_load
.Lco_fail:
    lea rdi, [rip + .Le_move]
    call app_toast
    xor ebx, ebx
    jmp 9f
.Lco_full:
    lea rdi, [rip + .Le_full]
    call app_toast
    xor ebx, ebx
9:  mov rdi, r12
    call mem_free
    mov rdi, r13
    call mem_free
    mov rdi, [rsp]
    call mem_free
    mov dword ptr [rip + g_dirty], 1
    mov rax, rbx
    EPILOGUE

# co_slot(): commit_one's record for the version it loads: the retired installed version's (r15),
# else, with the table full, a removed one's
co_slot:
    PROLOGUE
    test r15, r15
    jz 1f
    mov rdi, r15
    call ext_slot_reuse
    EPILOGUE
1:  cmp qword ptr [rip + g_exts + VEC_len], EXT_CAP
    jb 9f
    call ext_slot_take
9:  EPILOGUE

# root_path(suffix): in_sb = ROOT + suffix + "/" (suffix "" or "/.previous")
root_path:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + in_sb]
    call sb_clear
    call ext_root_dir
    lea rdi, [rip + in_sb]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    mov esi, '/'
    call sb_push_byte
    EPILOGUE

# record_write(dir, ir) -> eax 1 when dir/.rhun-install holds where it came from
record_write:
    PROLOGUE 48
    mov r12, rdi
    mov rbx, rsi
    lea rdi, [rip + in_words]
    call sb_clear
    lea rsi, [rip + .Lr_head]
    call words_push
    mov eax, [rbx + IR_kind]
    cmp eax, IK_GITHUB
    jne 1f
    lea rsi, [rip + .Lr_github]
    call words_push
    lea rsi, [rip + .Lr_repository]
    call words_push
    lea rsi, [rbx + IR_owner]
    call words_push
    lea rdi, [rip + in_words]
    mov esi, '/'
    call sb_push_byte
    lea rsi, [rbx + IR_name]
    call words_push
    lea rsi, [rip + .Lr_tag]
    call words_push
    lea rsi, [rbx + IR_tag]
    call words_push
    jmp 3f
1:  lea rsi, [rip + .Lr_archive]
    cmp eax, IK_ARCHIVE
    je 2f
    lea rsi, [rip + .Lr_folder]
2:  call words_push
    lea rsi, [rip + .Lr_path]
    call words_push
    mov rsi, [rbx + IR_file]
    call words_push
    cmp dword ptr [rbx + IR_kind], IK_LINK
    jne 3f
    lea rsi, [rip + .Lr_link]
    call words_push
    jmp 4f
3:  lea rsi, [rip + .Lr_sha]
    call words_push
    lea rsi, [rbx + IR_sha]
    call words_push
4:  lea rsi, [rip + .Lr_reviewed_yes]
    cmp dword ptr [rbx + IR_reviewed], 0
    jne 5f
    lea rsi, [rip + .Lr_reviewed_no]
5:  call words_push
    lea rsi, [rip + .Lr_installed]
    call words_push
    call time_now
    lea rdi, [rsp]
    mov rsi, rax
    call fmt_utc
    lea rsi, [rsp]
    call words_push
    lea rdi, [rip + in_words]
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    lea rsi, [rip + .Lrec_name]
    call path_join
    mov r13, rax
    mov rdi, rax
    mov rsi, [rip + in_words + SB_ptr]
    mov rdx, [rip + in_words + SB_len]
    call file_write_all
    mov r14, rax
    mov rdi, r13
    call mem_free
    xor eax, eax
    test r14, r14
    js 9f
    mov eax, 1
9:  EPILOGUE

# words_push(cstr): onto in_words
words_push:
    lea rdi, [rip + in_words]
    jmp sb_push_cstr

# ext_slot_forget(ext): its record's slot is about to hold another version (ext_slot_reuse): the
# Remove and Roll back dialogs and the extensions menu that named it forget it, and its details page
# goes back to the list (an update's commit puts the new version's details back)
FN ext_slot_forget
    PROLOGUE
    mov rbx, rdi
    cmp [rip + rm_ext], rbx
    jne 1f
    mov qword ptr [rip + rm_ext], 0
1:  cmp [rip + g_xp_detail], rbx
    jne 2f
    mov qword ptr [rip + g_xp_detail], 0
2:  mov rdi, rbx
    call extrec_slot_forget
    mov rdi, rbx
    call extbar_slot_forget
    EPILOGUE

# ---------------- removing ----------------

# ext_remove_ask(ext): Remove asks first (a linked one says its folder stays)
FN ext_remove_ask
    PROLOGUE
    mov rbx, rdi
    call ext_is_visible
    test eax, eax
    jz .Lremove_ask_done
    mov [rip + rm_ext], rbx
    lea rdi, [rip + in_title]
    lea rsi, [rip + .Lq_remove]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + EXT_title]
    test rsi, rsi
    jnz 1f
    mov rsi, [rbx + EXT_name]
1:  call ext_copy_title
    mov rdi, rax
    lea rsi, [rip + .Lq_end]
    call cstr_copy
    lea rsi, [rip + .Lt_remove_line]
    cmp qword ptr [rbx + EXT_inst], 0
    je 2f
    # "Its settings and the data it saved go too. Its folder ~/code/x stays."
    lea rdi, [rip + in_text]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Lt_folder_stays]
    call cstr_copy
    mov rdi, rax
    mov rsi, [rbx + EXT_dir]
    mov ecx, 3000
    call copy_max
    mov rdi, rax
    lea rsi, [rip + .Lt_stays]
    call cstr_copy
    lea rsi, [rip + in_text]
2:  lea rdi, [rip + in_title]
    lea rdx, [rip + .Lb_remove]
    lea rcx, [rip + remove_commit]
    call app_confirm
.Lremove_ask_done:
    EPILOGUE

# remove_commit(): the program stops; its folder (a link's stub, never the linked folder), its
# previous version, its state folder and log, its section of extensions.ini, the provider choices
# naming it and its update state go
remove_commit:
    PROLOGUE
    mov rbx, [rip + rm_ext]
    test rbx, rbx
    jz 9f
    mov qword ptr [rip + rm_ext], 0
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 9f
    mov rdi, rbx
    call ext_retire
    mov rdi, rbx
    call ext_home
    mov rdi, rax
    call file_remove_tree
    mov rdi, rbx
    call ext_prev_dir
    mov rdi, rax
    call file_remove_tree
    mov rdi, [rbx + EXT_state]
    call file_remove_tree
    lea rdi, [rip + in_sb]
    call sb_clear
    lea rdi, [rip + in_sb]
    mov rsi, [rbx + EXT_state]
    call sb_push_cstr
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lsuf_log]
    call sb_push_cstr
    call in_sb_cstr
    mov rdi, rax
    SYS SYS_unlink
    mov rdi, rbx
    call ext_full_name
    mov rdi, rax
    call dup_cstr
    mov r12, rax
    mov rdi, r12
    call ext_provider_forget
    mov rdi, r12
    call extupdate_forget
    mov rdi, r12
    call mem_free
    call ext_settings_save      # the removed record has no section any more
    lea rdi, [rip + in_sb]
    call sb_clear
    lea rdi, [rip + in_sb]
    lea rsi, [rip + .Lt_removed]
    call sb_push_cstr
    mov rdi, rbx
    call push_title
    call in_sb_cstr
    mov rdi, rax
    call app_toast
    call extpage_forget
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

.section .rodata
.Lask: .asciz "Install from GitHub: owner/repo, owner/repo@version or GitHub URL"
.Lask_folder: .asciz "Install from folder: a folder with extension.ini (copied)"
.Lask_link: .asciz "Link a folder: a folder with extension.ini (development; rebuild and Restart)"
.Lask_archive: .asciz "Install from archive: a release .tar.gz"
.Lgh: .asciz "github.com/"
.Lext_link: .asciz "rhun://extension/"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-install"
.Lenv_base: .asciz "RHUN_EXT_BASE"
.Lgithub: .asciz "https://github.com"
.Lhome: .asciz "HOME"
.Llatest: .asciz "latest"
.Ldash: .asciz "-"
.Lk_github: .asciz "github"
.Lk_archive: .asciz "archive"
.Lk_folder: .asciz "folder"
.Lslash_manifest: .asciz "/extension.ini"
.Lslash_x: .asciz "/x"
.Lprevious: .asciz "/.previous"
.Lrec_name: .asciz ".rhun-install"
.Lsuf_log: .asciz ".log"
.Lempty: .asciz ""
.Ldots: .asciz "\342\200\246"
.Lcolon: .asciz ": "
.Lq_add: .asciz "Add \342\200\234"
.Lq_update: .asciz "Update \342\200\234"
.Lq_remove: .asciz "Remove \342\200\234"
.Lq_end: .asciz "\342\200\235?"
.Lq_close_to: .asciz "\342\200\235 to "
.Lq_and: .asciz " and "
.Lq_close_and: .asciz "\342\200\235 and "
.Lq_extension: .asciz " extension"
.Lq_extensions: .asciz " extensions"
.Lq_mark: .asciz "?"
.Lq_to: .asciz " to "
.Lb_add: .asciz "Add extension"
.Lb_update: .asciz "Update"
.Lb_remove: .asciz "Remove"
.Lt_getting: .asciz "Getting "
.Lt_cannot: .asciz "Could not install "
.Lt_could_not_get: .asciz "Could not get "
.Lt_version: .asciz "Version "
.Lt_from: .asciz " from github.com/"
.Lt_from_archive: .asciz " from the archive "
.Lt_from_folder: .asciz " from the folder "
.Lt_linked: .asciz ", linked to the folder "
.Lt_development: .asciz " (development)"
.Lt_it_can: .asciz ". It can "
.Lt_reviewed: .asciz "\nReviewed for the rhun extensions index."
.Lt_unreviewed: .asciz "\nNot in the rhun extensions index: nobody has reviewed it."
.Lt_nobody: .asciz "Not in the rhun extensions index: nobody has reviewed this version."
.Lt_now_also: .asciz "It now also asks to: "
.Lt_added: .asciz "Added "
.Lt_added_end: .asciz ". Its commands are in the command palette."
.Lt_updated: .asciz "Updated "
.Lt_removed: .asciz "Removed "
.Lt_remove_line: .asciz "Its settings and the data it saved go too."
.Lt_folder_stays: .asciz " Its folder "
.Lt_stays: .asciz " stays."
.Le_busy: .asciz "An extension is already being installed"
.Le_newer: .asciz "the reviewed version needs rhun "
.Le_name: .asciz "Enter owner/repo or a GitHub repository URL"
.Le_path: .asciz "Enter the path of a folder or an archive"
.Le_spawn: .asciz "could not start the download"
.Le_unknown: .asciz "the download failed"
.Le_manifest: .asciz "the download has no readable extension.ini"
.Le_other: .asciz "its extension.ini names a different extension"
.Le_names: .asciz "its extension.ini has no usable owner and name"
.Le_move: .asciz "Could not put the extension in place"
.Le_full: .asciz "Too many extensions are installed"
.Lr_head: .asciz "# written by rhun when it installed this folder\n"
.Lr_github: .asciz "source = github\n"
.Lr_archive: .asciz "source = archive\n"
.Lr_folder: .asciz "source = folder\n"
.Lr_repository: .asciz "repository = "
.Lr_tag: .asciz "\ntag = "
.Lr_path: .asciz "path = "
.Lr_link: .asciz "\nlink = yes"
.Lr_sha: .asciz "\nsha256 = "
.Lr_reviewed_yes: .asciz "\nreviewed = yes\n"
.Lr_reviewed_no: .asciz "\nreviewed = no\n"
.Lr_installed: .asciz "installed = "
.ifdef WINDOWS
.Lei_owner: .asciz "RHUN_EI_OWNER="
.Lei_name: .asciz "RHUN_EI_NAME="
.Lei_target: .asciz "RHUN_EI_TARGET="
.Lei_root: .asciz "RHUN_EI_ROOT="
.Lei_base: .asciz "RHUN_EI_BASE="
.Lei_tag: .asciz "RHUN_EI_TAG="
.Lei_want: .asciz "RHUN_EI_WANT="
.Lei_file: .asciz "RHUN_EI_FILE="
.Lei_kind: .asciz "RHUN_EI_KIND="
.Lei_shell: .asciz "powershell.exe"
.Lei_noprofile: .asciz "-NoProfile"
.Lei_noninteractive: .asciz "-NonInteractive"
.Lei_outputformat: .asciz "-OutputFormat"
.Lei_text: .asciz "Text"
.Lei_encoded: .asciz "-EncodedCommand"
.endif
# the job: fixed text; its arguments come as $1..$9 (github: OWNER NAME, a TAG or "latest", the
# index's digest or "-"; archive and folder: the FILE). Base https: redirects stay https. The last
# line is "ok SHA256 TAG DIR", or why it failed
.globl install_script          # remote hosts: an extension's Linux build fetched for a host (remoteext.s)
install_script:
    .ascii "set -u\n"
    .ascii "owner=$1 name=$2 target=$3 root=$4 base=$5 tag=$6 want=$7 file=$8 kind=$9\n"
    .ascii "export COPYFILE_DISABLE=1\n"
    .ascii "mkdir -p \"$root\" || { echo \"cannot create $root\"; exit 1; }\n"
    .ascii "tmp=$(mktemp -d \"$root/.install-XXXXXX\") || { echo \"cannot create a folder in $root\"; exit 1; }\n"
    .ascii "fail() { rm -rf \"$tmp\"; echo \"$1\"; exit 1; }\n"
    .ascii "proto=; case $base in https:*) proto='--proto =https --proto-redir =https' ;; esac\n"
    .ascii "curl=; command -v curl >/dev/null 2>&1 && curl=1\n"
    .ascii "get() {\n"
    .ascii "  if [ -n \"$curl\" ]; then curl -fsSL $proto --max-time 120 --max-filesize 67108864 -o \"$2\" \"$1\"\n"
    .ascii "  elif command -v wget >/dev/null 2>&1; then wget -q -T 120 -O \"$2\" \"$1\"\n"
    .ascii "  else fail \"neither curl nor wget is installed\"; fi\n"
    .ascii "}\n"
    .ascii "where() {\n"
    .ascii "  if [ -n \"$curl\" ]; then curl -fsS $proto -o /dev/null --max-time 20 -w '%{redirect_url}' \"$1\"\n"
    .ascii "  else wget -S --max-redirect=0 -T 20 -O /dev/null \"$1\" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tr -d '\\r' | head -n 1; fi\n"
    .ascii "}\n"
    .ascii "sums() { awk -v f=\"$2\" '$2 == f || $2 == \"*\" f { print $1 }' \"$1\"; }\n"
    .ascii "what=archive wantsum=\n"
    .ascii "case $kind in\n"
    .ascii "github)\n"
    .ascii "  if [ \"$tag\" = latest ]; then\n"
    .ascii "    case $base in\n"
    .ascii "    file:*) url=$base/$owner/$name/releases/latest/download ;;\n"
    .ascii "    *) loc=$(where \"$base/$owner/$name/releases/latest\") || fail \"no answer from $base\"\n"
    .ascii "      case $loc in */releases/tag/*) tag=${loc##*/releases/tag/} ;; *) fail \"$owner/$name has no release\" ;; esac\n"
    .ascii "      case $tag in ''|*[!0-9A-Za-z._-]*) fail \"the latest release has an unusable tag\" ;; esac\n"
    .ascii "      url=$base/$owner/$name/releases/download/$tag ;;\n"
    .ascii "    esac\n"
    .ascii "  else url=$base/$owner/$name/releases/download/$tag; fi\n"
    .ascii "  asset=$name-$target.tar.gz\n"
    .ascii "  get \"$url/$asset\" \"$tmp/a.tgz\" || { [ \"$tag\" = latest ] && fail \"no release of $owner/$name for $target\"; fail \"no release $tag of $owner/$name for $target\"; }\n"
    .ascii "  get \"$url/sha256sums.txt\" \"$tmp/sums\" || fail \"the release has no sha256sums.txt\"\n"
    .ascii "  wantsum=$(sums \"$tmp/sums\" \"$asset\")\n"
    .ascii "  [ -n \"$wantsum\" ] || fail \"the release's sha256sums.txt does not list $asset\" ;;\n"
    .ascii "archive)\n"
    .ascii "  asset=${file##*/}\n"
    .ascii "  cp \"$file\" \"$tmp/a.tgz\" 2>/dev/null || fail \"cannot read $file\"\n"
    .ascii "  if [ -f \"${file%/*}/sha256sums.txt\" ]; then\n"
    .ascii "    wantsum=$(sums \"${file%/*}/sha256sums.txt\" \"$asset\")\n"
    .ascii "    [ -n \"$wantsum\" ] || fail \"the sha256sums.txt beside it does not list $asset\"\n"
    .ascii "  fi ;;\n"
    .ascii "folder)\n"
    .ascii "  what=folder\n"
    .ascii "  [ -f \"$file/extension.ini\" ] || fail \"the folder has no extension.ini\"\n"
    .ascii "  tar -czf \"$tmp/a.tgz\" -C \"$file\" . 2>/dev/null || fail \"the folder cannot be read\" ;;\n"
    .ascii "*) fail \"unknown source\" ;;\n"
    .ascii "esac\n"
    .ascii "if command -v sha256sum >/dev/null 2>&1; then have=$(sha256sum \"$tmp/a.tgz\"); else have=$(shasum -a 256 \"$tmp/a.tgz\"); fi\n"
    .ascii "have=${have%% *}\n"
    .ascii "[ -z \"$wantsum\" ] || [ \"$wantsum\" = \"$have\" ] || fail \"the download does not match its checksum\"\n"
    .ascii "[ \"$want\" = - ] || [ \"$want\" = \"$have\" ] || fail \"the download is not the version the rhun extensions index reviewed\"\n"
    .ascii "tar -tvzf \"$tmp/a.tgz\" > \"$tmp/list\" 2>/dev/null || fail \"the $what cannot be read\"\n"
    .ascii "grep -q '^[^-d]' \"$tmp/list\" && fail \"the $what holds links or devices\"\n"
    .ascii "tar -tzf \"$tmp/a.tgz\" | grep -Eq '(^/|(^|/)[.][.](/|$))' && fail \"the $what reaches outside itself\"\n"
    .ascii "size=$(awk '{ s += ($2 ~ /\\//) ? $3 : $5 } END { printf \"%.0f\", s }' \"$tmp/list\")\n"
    .ascii "[ \"$size\" -le 67108864 ] 2>/dev/null || fail \"the $what unpacks to more than 64 MB\"\n"
    .ascii "mkdir \"$tmp/x\" && tar -xzf \"$tmp/a.tgz\" -C \"$tmp/x\" 2>/dev/null || fail \"the $what cannot be unpacked\"\n"
    .ascii "[ -f \"$tmp/x/extension.ini\" ] || fail \"the $what has no extension.ini\"\n"
    .ascii "rm -f \"$tmp/a.tgz\" \"$tmp/sums\" \"$tmp/list\"\n"
    .asciz "echo \"ok $have $tag $tmp\"\n"

.bss
ib_wider: .long 0               # the update being asked about asks for more
ib_newmembers: .long 0          # the pack an automatic update fetched names extensions not installed
