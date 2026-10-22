# Settings per workspace, folder and language (feature scoped-settings, docs/extensions/v1.1.md).
# An extension's [settings] say how far down a key may be set (KEY.scope = user, the default, |
# workspace | folder) and whether KEY@LANG values apply (KEY.languages = yes). Values: the user's
# in ~/.config/rhun/extensions.ini (as in v1, with setting.KEY@LANG lines too), the workspace's in
# the primary folder's .rhun/extensions.ini, another folder's in its own .rhun/extensions.ini, all
# in [owner/name] sections. A folder that is not trusted (a rhun:// link opened it) contributes
# nothing, and a key a project file may not set is ignored there, so a cloned repository changes
# nothing an extension did not open to it.
#
# The window value ("0 setting KEY VALUE") is the workspace's, then the user's, then the default
# (no language). setting-get resolves folder@LANG, folder, workspace@LANG, workspace, user@LANG,
# user, default. When a project file changes (polled once a second) running extensions get
# "0 setting" for window values that changed and, with the feature, "0 setting-changed KEY" for
# keys with a stored value that changed.
#
#   extconfig_field(sd, field, len, it) -> eax 1 for KEY.scope / KEY.languages (manifest)
#   extconfig_user_line(ext, it) -> eax 1 for a setting.KEY@LANG line of extensions.ini
#   extconfig_user_reset(ext or 0): its (everyone's) setting.KEY@LANG values go before a reload
#   extconfig_window(ext, sd) -> rax the window value (cstr)
#   extconfig_get(ext, sd, folder id, lang ptr, len) -> rax the value in force there (cstr)
#   extconfig_override(ext, sd) -> rax "This workspace sets VALUE (.rhun/extensions.ini)" or 0
#   extconfig_poll(), extconfig_user_changed(ext, sd), extconfig_open()
.include "rhun.inc"

.equ ECL_USER, 0
.equ ECL_WORKSPACE, 1
.equ ECL_FOLDER, 2
.equ ECF_FILE_MAX, 65536
.equ ECF_VALUE_MAX, 4096
.equ ECF_FOLDERS, 16
STRUCT
F ECR_name, 8           # "owner/name" (owned)
F ECR_key, 8            # the setting (owned)
F ECR_lang, 8           # a grammar name with _ for spaces (owned), or 0
F ECR_value, 8          # (owned)
F ECR_folder, 8         # ECL_FOLDER: the folder's id
F ECR_level, 4          # ECL_*
F ECR_pad, 4
ENDSTRUCT ECR_SIZE

.bss
.p2align 3
ecf_recs: .zero VEC_SIZE
ecf_it: .zero INI_SIZE
ecf_name: .zero 160             # an extension's "owner/name"
ecf_num: .zero 32               # a number written out
ecf_stamps: .zero 8 * (ECF_FOLDERS + 2)
ecf_project: .quad 0            # g_project when last read
ecf_ws_gen: .quad 0             # g_ws_gen when last read
ecf_poll_t: .quad 0
ecf_ignored: .quad 0            # lines of the project files ignored
ecf_old: .zero VEC_SIZE         # notify: (signature, window value) per extension setting
ecf_msg: .zero SB_SIZE
ecf_text: .zero SB_SIZE

.text

# ---------------- the manifest ----------------

# FN extconfig_field(sd, field ptr, len, it) -> eax 1 when the field was the group's
FN extconfig_field
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lf_scope]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov rdi, [r14 + INI_val]
    mov rsi, [r14 + INI_vallen]
    lea rdx, [rip + .Lv_workspace]
    call str_eq_cstr
    mov ecx, ECL_WORKSPACE
    test eax, eax
    jnz 2f
    mov rdi, [r14 + INI_val]
    mov rsi, [r14 + INI_vallen]
    lea rdx, [rip + .Lv_folder]
    call str_eq_cstr
    mov ecx, ECL_FOLDER
    test eax, eax
    jnz 2f
    xor ecx, ecx                # user, and anything else
2:  mov eax, [rbx + SD_scope]
    and eax, ~3
    or eax, ecx
    mov [rbx + SD_scope], eax
    jmp 8f
3:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lf_languages]
    call str_eq_cstr
    test eax, eax
    jz 9f
    and dword ptr [rbx + SD_scope], ~SDS_LANGUAGES
    mov rdi, [r14 + INI_val]
    mov rsi, [r14 + INI_vallen]
    lea rdx, [rip + .Lv_yes]
    call str_eq_cstr
    test eax, eax
    jz 8f
    or dword ptr [rbx + SD_scope], SDS_LANGUAGES
8:  mov eax, 1
9:  EPILOGUE

# ---------------- values ----------------

# ecf_valid(sd, ptr, len) -> rax an owned normalized value that fits the setting, or 0: a switch is
# yes or no, a number is clamped to its range, a choice one of its options, a text 4096 bytes at most
ecf_valid:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, ECF_VALUE_MAX
    ja 8f
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov r14, rax
    mov eax, [rbx + SD_type]
    cmp eax, SDT_BOOL
    jne 2f
    mov rdi, r14
    lea rsi, [rip + .Lv_yes]
    call strcmp_eq
    test eax, eax
    jnz 9f
    mov rdi, r14
    lea rsi, [rip + .Lv_no]
    call strcmp_eq
    test eax, eax
    jnz 9f
    jmp 7f
2:  cmp eax, SDT_INT
    jne 3f
    mov rdi, r12
    mov rsi, r13
    call parse_int31
    cmp rdx, r13
    jne 7f
    test r13, r13
    jz 7f
    cmp eax, [rbx + SD_min]
    jge 21f
    mov eax, [rbx + SD_min]
21: cmp eax, [rbx + SD_max]
    jle 22f
    mov eax, [rbx + SD_max]
22: mov r15d, eax
    mov rdi, r14
    call mem_free
    lea rdi, [rip + ecf_num]
    mov esi, r15d
    call fmt_u64
    mov byte ptr [rdi], 0
    lea rdi, [rip + ecf_num]
    call dup_cstr
    mov r14, rax
    jmp 9f
3:  cmp eax, SDT_CHOICE
    jne 9f
    mov rdi, rbx
    mov rsi, r14
    call sdef_is_option
    test eax, eax
    jnz 9f
7:  mov rdi, r14
    call mem_free
8:  xor eax, eax
    EPILOGUE
9:  mov rax, r14
    EPILOGUE

# ecf_add(name cstr, key ptr, len, lang ptr, len, value owned, level, folder): a record (one with
# the same name, key, language, level and folder is replaced)
ecf_add:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    mov r12, r9                 # the value
    mov r13d, [rbp + 16]        # level
    mov r14, [rbp + 24]         # folder
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    mov r8, [rsp + 32]
    mov r9d, r13d
    push r14
    push r14
    call ecf_find_exact
    add rsp, 16
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, [rbx + ECR_value]
    call mem_free
    mov [rbx + ECR_value], r12
    EPILOGUE
1:  lea rdi, [rip + ecf_recs]
    mov esi, ECR_SIZE
    call vec_push
    mov rbx, rax
    mov rdi, [rsp]
    call dup_cstr
    mov [rbx + ECR_name], rax
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    call mem_dup
    mov [rbx + ECR_key], rax
    cmp qword ptr [rsp + 32], 0
    je 2f
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    call mem_dup
    mov [rbx + ECR_lang], rax
2:  mov [rbx + ECR_value], r12
    mov [rbx + ECR_level], r13d
    mov [rbx + ECR_folder], r14
    EPILOGUE

# ecf_find_exact(name cstr, key ptr, len, lang ptr, len, level, [stack] folder) -> rax the record or 0
ecf_find_exact:
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov [rsp + 32], r8
    mov r13d, r9d
    mov r14, [rbp + 16]
    xor r12d, r12d
1:  cmp r12, [rip + ecf_recs + VEC_len]
    jae 8f
    imul rbx, r12, ECR_SIZE
    add rbx, [rip + ecf_recs + VEC_ptr]
    inc r12
    cmp [rbx + ECR_level], r13d
    jne 1b
    cmp r13d, ECL_FOLDER
    jne 2f
    cmp [rbx + ECR_folder], r14
    jne 1b
2:  mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, [rbx + ECR_key]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rdi, [rbx + ECR_name]
    mov rsi, [rsp]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdx, [rbx + ECR_lang]
    cmp qword ptr [rsp + 32], 0
    jne 3f
    test rdx, rdx
    jnz 1b
    jmp 9f
3:  test rdx, rdx
    jz 1b
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    call str_eq_cstr
    test eax, eax
    jz 1b
9:  mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ecf_drop(level from, name cstr or 0): records of that level and above (of that extension) go
ecf_drop:
    PROLOGUE
    mov r13d, edi
    mov r14, rsi
    xor r12d, r12d
1:  cmp r12, [rip + ecf_recs + VEC_len]
    jae 9f
    imul rbx, r12, ECR_SIZE
    add rbx, [rip + ecf_recs + VEC_ptr]
    cmp [rbx + ECR_level], r13d
    jb 3f
    test r14, r14
    jz 2f
    mov rdi, [rbx + ECR_name]
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jz 3f
2:  mov rdi, [rbx + ECR_name]
    call mem_free
    mov rdi, [rbx + ECR_key]
    call mem_free
    mov rdi, [rbx + ECR_lang]
    call mem_free
    mov rdi, [rbx + ECR_value]
    call mem_free
    # the last record takes its place
    mov rax, [rip + ecf_recs + VEC_len]
    dec rax
    mov [rip + ecf_recs + VEC_len], rax
    imul rsi, rax, ECR_SIZE
    add rsi, [rip + ecf_recs + VEC_ptr]
    mov rdi, rbx
    mov ecx, ECR_SIZE
    rep movsb
    jmp 1b
3:  inc r12
    jmp 1b
9:  EPILOGUE

# FN extconfig_user_reset(ext or 0)
FN extconfig_user_reset
    PROLOGUE
    xor esi, esi
    test rdi, rdi
    jz 1f
    call ecf_set_name
    lea rsi, [rip + ecf_name]
1:  call ecf_drop_user
    EPILOGUE

# ecf_drop_user(name or 0): level 0 records (of that extension)
ecf_drop_user:
    PROLOGUE
    mov r14, rsi
    xor r12d, r12d
1:  cmp r12, [rip + ecf_recs + VEC_len]
    jae 9f
    imul rbx, r12, ECR_SIZE
    add rbx, [rip + ecf_recs + VEC_ptr]
    cmp dword ptr [rbx + ECR_level], ECL_USER
    jne 3f
    test r14, r14
    jz 2f
    mov rdi, [rbx + ECR_name]
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jz 3f
2:  mov rdi, [rbx + ECR_name]
    call mem_free
    mov rdi, [rbx + ECR_key]
    call mem_free
    mov rdi, [rbx + ECR_lang]
    call mem_free
    mov rdi, [rbx + ECR_value]
    call mem_free
    mov rax, [rip + ecf_recs + VEC_len]
    dec rax
    mov [rip + ecf_recs + VEC_len], rax
    imul rsi, rax, ECR_SIZE
    add rsi, [rip + ecf_recs + VEC_ptr]
    mov rdi, rbx
    mov ecx, ECR_SIZE
    rep movsb
    jmp 1b
3:  inc r12
    jmp 1b
9:  EPILOGUE

# ecf_set_name(ext): ecf_name = "owner/name"
ecf_set_name:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + ecf_name]
    mov rsi, [rbx + EXT_owner]
    call cstr_copy
    mov byte ptr [rax], '/'
    lea rdi, [rax + 1]
    mov rsi, [rbx + EXT_name]
    call cstr_copy
    EPILOGUE

# ecf_split(it) -> rax the key after "setting." (rdx its length up to @, or 0 when it is not a
# setting line), rcx the language after @ (r8 its length, 0 without)
ecf_split:
    mov rax, [rdi + INI_key]
    mov rdx, [rdi + INI_keylen]
    xor ecx, ecx
    xor r8d, r8d
    cmp rdx, 8
    jbe 8f
    cmp dword ptr [rax], 0x74746573         # "sett"
    jne 8f
    cmp dword ptr [rax + 4], 0x2e676e69     # "ing."
    jne 8f
    add rax, 8
    sub rdx, 8
    xor r9d, r9d
1:  cmp r9, rdx
    jae 9f
    cmp byte ptr [rax + r9], '@'
    je 2f
    inc r9
    jmp 1b
2:  lea rcx, [rax + r9 + 1]
    mov r8, rdx
    sub r8, r9
    dec r8
    mov rdx, r9
    test r8, r8
    jz 8f
    test rdx, rdx
    jz 8f
9:  ret
8:  xor edx, edx
    ret

# FN extconfig_user_line(ext, it) -> eax 1 when the line was setting.KEY@LANG (kept when the setting
# takes languages and the value fits)
FN extconfig_user_line
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call ecf_split
    test rdx, rdx
    jz 8f
    test r8, r8
    jz 8f
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov r13, rax
    mov r14, rdx
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    call sdef_find
    test rax, rax
    jz 7f
    mov r15, rax
    test dword ptr [r15 + SD_scope], SDS_LANGUAGES
    jz 7f
    mov rdi, r15
    mov rsi, [r12 + INI_val]
    mov rdx, [r12 + INI_vallen]
    call ecf_valid
    test rax, rax
    jz 7f
    mov r15, rax
    mov rdi, rbx
    call ecf_set_name
    lea rdi, [rip + ecf_name]
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rsp]
    mov r8, [rsp + 8]
    mov r9, r15
    push 0
    push ECL_USER
    call ecf_add
    add rsp, 16
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- the project files ----------------

# ecf_trusted() -> eax 1 when the project's files may set values: opened by hand, or a repository
# the user trusted
ecf_trusted:
    mov eax, 1
    cmp dword ptr [rip + g_project_link], 0
    je 1f
    xor eax, eax
    cmp qword ptr [rip + g_git_root], 0
    je 1f
    cmp dword ptr [rip + g_git_paused], 0
    jne 1f
    mov eax, 1
1:  ret

# ecf_file(i) -> rax folder i's .rhun/extensions.ini (owned path)
ecf_file:
    push rbx
    call wfold_path
    mov rdi, rax
    lea rsi, [rip + .Lf_file]
    call path_join
    pop rbx
    ret

# ecf_reload(): the project files read again
ecf_reload:
    PROLOGUE
    mov edi, ECL_WORKSPACE
    xor esi, esi
    call ecf_drop
    mov qword ptr [rip + ecf_ignored], 0
    call ecf_trusted
    test eax, eax
    jz 9f
    # a workspace file's sections are the workspace's values (workspace.s)
    mov rdi, [rip + g_ws_file]
    test rdi, rdi
    jz 0f
    mov esi, ECF_FILE_MAX
    call vfs_read_limited
    test rax, rax
    jz 0f
    mov r14, rax
    mov rdi, rax
    mov rsi, rdx
    mov edx, ECL_WORKSPACE
    xor ecx, ecx
    call ecf_parse
    mov rdi, r14
    call mem_free
0:  xor r12d, r12d
1:  call wfold_count
    cmp r12, rax
    jae 9f
    cmp r12, ECF_FOLDERS
    jae 9f
    mov rdi, r12
    call ecf_file
    mov r13, rax
    mov rdi, rax
    mov esi, ECF_FILE_MAX
    call vfs_read_limited
    mov r14, rax
    mov r15, rdx                # its length
    mov rdi, r13
    call mem_free
    test r14, r14
    jz 2f
    mov rdi, r12
    call wfold_id
    mov rcx, rax
    mov edx, ECL_FOLDER         # the primary folder's file is the workspace's without a workspace file
    test r12, r12
    jnz 11f
    cmp qword ptr [rip + g_ws_file], 0
    jne 11f
    mov edx, ECL_WORKSPACE
11: mov rdi, r14
    mov rsi, r15
    call ecf_parse
    mov rdi, r14
    call mem_free
2:  inc r12
    jmp 1b
9:  EPILOGUE

# ecf_parse(text, len, level, folder id): one project file's values at that level (ECL_WORKSPACE:
# a workspace file or the primary folder's; ECL_FOLDER: a folder's own, with its id)
ecf_parse:
    PROLOGUE 32
    mov [rsp], rdx
    mov [rsp + 8], rcx
    lea r15, [rip + ecf_it]
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, r15
    call ini_init
.Lep_line:
    mov rdi, r15
    call ini_next
    test eax, eax
    jz 9f
    # the extension of the section
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae .Lep_bad
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    mov rdi, rbx
    call ecf_set_name
    mov rdi, r15
    lea rsi, [rip + ecf_name]
    call ini_sec_is
    test eax, eax
    jz 1b
    mov rdi, r15
    call ecf_split
    test rdx, rdx
    jz .Lep_bad
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    mov r13, rax
    mov r14, rdx
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rbx
    call sdef_find
    test rax, rax
    jz .Lep_bad
    mov r12, rax                # the setting
    # how far down it may be set
    mov eax, [r12 + SD_scope]
    and eax, 3
    mov rcx, [rsp]
    cmp eax, ecx
    jb .Lep_bad
    cmp qword ptr [rsp + 24], 0
    je 3f
    test dword ptr [r12 + SD_scope], SDS_LANGUAGES
    jz .Lep_bad
3:  mov rdi, r12
    mov rsi, [r15 + INI_val]
    mov rdx, [r15 + INI_vallen]
    call ecf_valid
    test rax, rax
    jz .Lep_bad
    mov r9, rax
    mov eax, ECL_WORKSPACE
    xor ecx, ecx
    cmp qword ptr [rsp], ECL_FOLDER
    jne 4f
    mov eax, ECL_FOLDER
    mov rcx, [rsp + 8]
4:  push rcx
    push rax
    lea rdi, [rip + ecf_name]
    mov rsi, r13
    mov rdx, r14
    mov rcx, [rsp + 32]
    mov r8, [rsp + 40]
    call ecf_add
    add rsp, 16
    jmp .Lep_line
.Lep_bad:
    inc qword ptr [rip + ecf_ignored]
    jmp .Lep_line
9:  EPILOGUE

# ---------------- reading values ----------------

# ecf_lookup(ext, sd, level, folder, lang ptr, len) -> rax the record's value or 0
ecf_lookup:
    PROLOGUE 32
    mov [rsp], rcx
    mov [rsp + 8], r8
    mov [rsp + 16], r9
    mov r13d, edx
    mov r14, rsi
    call ecf_set_name
    mov rdi, [r14 + SD_key]
    call strlen
    mov rdx, rax
    lea rdi, [rip + ecf_name]
    mov rsi, [r14 + SD_key]
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    mov r9d, r13d
    push qword ptr [rsp]
    push qword ptr [rsp + 8]
    call ecf_find_exact
    add rsp, 16
    test rax, rax
    jz 9f
    mov rax, [rax + ECR_value]
9:  EPILOGUE

# FN extconfig_window(ext, sd) -> rax the window value: the workspace's, then the user's (the
# default when the user set none)
FN extconfig_window
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, [r12 + SD_scope]
    and eax, 3
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    mov edx, ECL_WORKSPACE
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call ecf_lookup
    test rax, rax
    jnz 9f
8:  mov rax, [r12 + SD_value]
    test rax, rax
    jnz 9f
    lea rax, [rip + .Lempty]
9:  EPILOGUE

# FN extconfig_get(ext, sd, folder id, lang ptr, len) -> rax the value in force for that folder (0:
# the window) and language (len 0: none)
FN extconfig_get
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    mov [rsp + 8], r8
    test dword ptr [r12 + SD_scope], SDS_LANGUAGES
    jnz 1f
    mov qword ptr [rsp + 8], 0  # languages do not apply
1:  mov eax, [r12 + SD_scope]
    and eax, 3
    mov [rsp + 16], eax
    cmp eax, ECL_FOLDER
    jne 3f
    test r13, r13
    jz 3f
    mov r14d, ECL_FOLDER
    call .Leg_pair
    test rax, rax
    jnz 9f
3:  cmp dword ptr [rsp + 16], ECL_WORKSPACE
    jb 4f
    mov r14d, ECL_WORKSPACE
    call .Leg_pair
    test rax, rax
    jnz 9f
4:  cmp qword ptr [rsp + 8], 0
    je 5f
    mov rdi, rbx
    mov rsi, r12
    mov edx, ECL_USER
    xor ecx, ecx
    mov r8, [rsp]
    mov r9, [rsp + 8]
    call ecf_lookup
    test rax, rax
    jnz 9f
5:  mov rax, [r12 + SD_value]
    test rax, rax
    jnz 9f
    lea rax, [rip + .Lempty]
9:  EPILOGUE
# .Leg_pair: level r14d @LANG, then without (extconfig_get's frame, one return address deeper)
.Leg_pair:
    cmp qword ptr [rsp + 16], 0
    je 1f
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    mov rcx, r13
    mov r8, [rsp + 8]
    mov r9, [rsp + 16]
    call ecf_lookup
    test rax, rax
    jnz 2f
1:  mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    call ecf_lookup
2:  ret

# FN extconfig_override(ext, sd) -> rax "This workspace sets VALUE (.rhun/extensions.ini)" (a cstr
# of this module, valid until the next call) when the workspace's value is in force, or 0
FN extconfig_override
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    mov ecx, [r12 + SD_scope]
    and ecx, 3
    jz 9f
    mov rdi, rbx
    mov rsi, r12
    mov edx, ECL_WORKSPACE
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call ecf_lookup
    test rax, rax
    jz 9f
    mov r13, rax
    lea rdi, [rip + ecf_text]
    call sb_clear
    lea rdi, [rip + ecf_text]
    lea rsi, [rip + .Lt_sets]
    call sb_push_cstr
    lea rdi, [rip + ecf_text]
    mov rsi, r13
    call sb_push_cstr
    mov rdi, [rip + g_ws_file]  # where: the workspace file, or the primary folder's
    test rdi, rdi
    jz 1f
    call strlen
    mov rdi, [rip + g_ws_file]
    mov rsi, rax
    call path_basename
    mov r13, rax
    lea rdi, [rip + ecf_text]
    lea rsi, [rip + .Lt_open]
    call sb_push_cstr
    lea rdi, [rip + ecf_text]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + ecf_text]
    lea rsi, [rip + .Lt_close]
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + ecf_text]
    lea rsi, [rip + .Lt_file]
    call sb_push_cstr
2:
    lea rdi, [rip + ecf_text]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + ecf_text + SB_ptr]
9:  EPILOGUE

# FN extconfig_open(): the workspace's .rhun/extensions.ini in a tab (the page's Open)
FN extconfig_open
    PROLOGUE
    mov rdi, [rip + g_ws_file]
    test rdi, rdi
    jz 1f
    call app_open_file
    EPILOGUE
1:  call wfold_count
    test eax, eax
    jz 9f
    xor edi, edi
    call ecf_file
    mov rbx, rax
    mov rdi, rax
    call app_open_file
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# ---------------- telling extensions ----------------

# ecf_sig(ext, sd) -> rax a hash of every stored value of the setting (all levels)
ecf_sig:
    PROLOGUE
    mov r14, rsi
    call ecf_set_name
    mov r15, 0xcbf29ce484222325
    xor r12d, r12d
1:  cmp r12, [rip + ecf_recs + VEC_len]
    jae 9f
    imul rbx, r12, ECR_SIZE
    add rbx, [rip + ecf_recs + VEC_ptr]
    inc r12
    mov rdi, [rbx + ECR_name]
    lea rsi, [rip + ecf_name]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [rbx + ECR_key]
    mov rsi, [r14 + SD_key]
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [rbx + ECR_value]
    call ecf_mix
    mov rdi, [rbx + ECR_lang]
    call ecf_mix
    mov eax, [rbx + ECR_level]
    add rax, [rbx + ECR_folder]
    xor r15, rax
    mov rax, 0x100000001b3
    imul r15, rax
    jmp 1b
9:  mov rax, r15
    EPILOGUE

# ecf_mix(cstr or 0): r15 = FNV-1a of r15 and the bytes (and a separator)
ecf_mix:
    mov r8, 0x100000001b3
    test rdi, rdi
    jz 2f
1:  movzx eax, byte ptr [rdi]
    test eax, eax
    jz 2f
    xor r15, rax
    imul r15, r8
    inc rdi
    jmp 1b
2:  xor r15, 0xff
    imul r15, r8
    ret

# ecf_snapshot(): each running extension setting's signature and window value into ecf_old
ecf_snapshot:
    PROLOGUE
    call ecf_old_free
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    xor r13d, r13d
2:  cmp r13, [rbx + EXT_sdefs + VEC_len]
    jae 1b
    imul r14, r13, SD_SIZE
    add r14, [rbx + EXT_sdefs + VEC_ptr]
    inc r13
    mov rdi, rbx
    mov rsi, r14
    call ecf_sig
    mov r15, rax
    mov rdi, rbx
    mov rsi, r14
    call extconfig_window
    mov rdi, rax
    call dup_cstr
    push rax
    push rax
    lea rdi, [rip + ecf_old]
    mov esi, 16
    call vec_push
    pop rcx
    pop rcx
    mov [rax], r15
    mov [rax + 8], rcx
    jmp 2b
9:  EPILOGUE

ecf_old_free:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + ecf_old + VEC_len]
    jae 2f
    mov rax, r12
    shl rax, 4
    add rax, [rip + ecf_old + VEC_ptr]
    mov rdi, [rax + 8]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rip + ecf_old + VEC_len], 0
    EPILOGUE

# ecf_notify(): after a reload, against ecf_old: running extensions get "0 setting" for a window
# value that changed and, with scoped-settings, "0 setting-changed KEY" for a setting whose stored
# values changed
ecf_notify:
    PROLOGUE
    xor r12d, r12d              # extension
    xor r15d, r15d              # its place in ecf_old
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    xor r13d, r13d
2:  cmp r13, [rbx + EXT_sdefs + VEC_len]
    jae 1b
    imul r14, r13, SD_SIZE
    add r14, [rbx + EXT_sdefs + VEC_ptr]
    inc r13
    cmp r15, [rip + ecf_old + VEC_len]
    jae 9f                      # the extensions changed meanwhile
    mov rax, r15
    shl rax, 4
    add rax, [rip + ecf_old + VEC_ptr]
    inc r15
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 2b
    push rax
    push rax
    mov rdi, rbx
    mov rsi, r14
    call extconfig_window
    mov rdi, rax
    mov rax, [rsp]
    mov rsi, [rax + 8]
    call strcmp_eq
    test eax, eax
    jnz 3f
    mov rdi, rbx
    mov rsi, r14
    call extproto_send_setting
3:  mov rdi, rbx
    mov rsi, r14
    call ecf_sig
    pop rcx
    pop rcx
    cmp rax, [rcx]
    je 2b
    mov rdi, rbx
    mov rsi, r14
    call ecf_tell_changed
    jmp 2b
9:  call ecf_old_free
    EPILOGUE

# ecf_tell_changed(ext, sd): "0 setting-changed KEY" when it agreed scoped-settings
ecf_tell_changed:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    FEAT_TEST rbx, FEAT_SCOPED_SETTINGS
    jz 9f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    lea rdi, [rip + ecf_msg]
    call sb_clear
    lea rdi, [rip + ecf_msg]
    lea rsi, [rip + .Lev_changed]
    call sb_push_cstr
    lea rdi, [rip + ecf_msg]
    mov rsi, [r12 + SD_key]
    call sb_push_cstr
    lea rdi, [rip + ecf_msg]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + ecf_msg + SB_ptr]
    mov rdx, [rip + ecf_msg + SB_len]
    call ext_send_checked
9:  EPILOGUE

# FN extconfig_user_changed(ext, sd): the user changed a value on the page (ext_setting_set)
FN extconfig_user_changed
    jmp ecf_tell_changed

# FN extconfig_poll(): every frame: at once when the project changed, else once a second, the
# project files' stamps; when one changed (or the trust), they are read again and extensions told
FN extconfig_poll
    PROLOGUE
    mov rax, [rip + g_project]
    cmp rax, [rip + ecf_project]
    jne 1f
    mov eax, [rip + g_ws_gen]   # the folders were made again (their ids are new): read at once
    cmp eax, [rip + ecf_ws_gen]
    jne 1f
    call time_ms
    mov rcx, rax
    sub rcx, [rip + ecf_poll_t]
    cmp rcx, 1000
    jb 9f
1:  call time_ms
    mov [rip + ecf_poll_t], rax
    # the stamp of every folder's file, the trust and the folders
    call ecf_trusted
    mov r13d, eax
    xor r12d, r12d
    xor r14d, r14d              # 1 when something differs
2:  call wfold_count
    mov r15, rax
    cmp r12, ECF_FOLDERS
    jae 4f
    cmp r12, r15
    jae 4f
    mov rdi, r12
    call ecf_file
    mov rbx, rax
    mov rdi, rax
    call vfs_stamp
    push rax
    push rax
    mov rdi, rbx
    call mem_free
    pop rax
    pop rax
    lea rcx, [rip + ecf_stamps]
    cmp [rcx + r12*8], rax
    je 3f
    mov [rcx + r12*8], rax
    mov r14d, 1
3:  inc r12
    jmp 2b
4:  mov rdi, [rip + g_ws_file]  # a workspace file's stamp
    xor eax, eax
    test rdi, rdi
    jz 41f
    call vfs_stamp
41: lea rcx, [rip + ecf_stamps]
    cmp [rcx + ECF_FOLDERS*8 + 8], rax
    je 42f
    mov [rcx + ECF_FOLDERS*8 + 8], rax
    mov r14d, 1
42: lea rcx, [rip + ecf_stamps]
    mov rax, r15
    shl rax, 1
    or rax, r13
    cmp [rcx + ECF_FOLDERS*8], rax
    je 5f
    mov [rcx + ECF_FOLDERS*8], rax
    mov r14d, 1
5:  mov eax, [rip + g_ws_gen]
    cmp eax, [rip + ecf_ws_gen]
    je 51f
    mov [rip + ecf_ws_gen], eax
    mov r14d, 1
51: mov rax, [rip + g_project]
    cmp rax, [rip + ecf_project]
    je 6f
    mov [rip + ecf_project], rax
    mov r14d, 1
6:  test r14d, r14d
    jz 9f
    call ecf_snapshot
    call ecf_reload
    call ecf_notify
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# FN c_print_ext_setting(out, args, len): "print-ext-setting OWNER/NAME KEY [FOLDER [LANG]]":
# "value=V window=W ignored=N"
FN c_print_ext_setting
    PROLOGUE 64
    mov [rsp], rdi
    mov r12, rsi
    mov r13, rdx
    # the words
    lea rbx, [rsp + 8]          # 4 words: ptr, len pairs
    xor r14d, r14d
1:  cmp r14, 4
    jae 2f
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    mov rcx, r14
    shl rcx, 4
    mov [rbx + rcx], rax
    mov [rbx + rcx + 8], rdx
    inc r14
    jmp 1b
2:  # the extension
    xor r14d, r14d
3:  cmp r14, [rip + g_exts + VEC_len]
    jae 9f
    imul r15, r14, EXT_SIZE
    add r15, [rip + g_exts + VEC_ptr]
    inc r14
    mov rdi, r15
    call ecf_set_name
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    lea rdx, [rip + ecf_name]
    call str_eq_cstr
    test eax, eax
    jz 3b
    mov rdi, [rbx + 16]
    mov rsi, [rbx + 24]
    mov rdx, r15
    call sdef_find
    test rax, rax
    jz 9f
    mov r14, rax
    mov rdi, [rbx + 32]
    mov rsi, [rbx + 40]
    call parse_int31
    mov rdx, rax
    mov rdi, r15
    mov rsi, r14
    mov rcx, [rbx + 48]
    mov r8, [rbx + 56]
    call extconfig_get
    mov r12, rax
    mov rdi, [rsp]
    lea rsi, [rip + .Lp_value]
    call sb_push_cstr
    mov rdi, [rsp]
    mov rsi, r12
    call sb_push_cstr
    mov rdi, [rsp]
    lea rsi, [rip + .Lp_window]
    call sb_push_cstr
    mov rdi, r15
    mov rsi, r14
    call extconfig_window
    mov rdi, [rsp]
    mov rsi, rax
    call sb_push_cstr
    mov rdi, [rsp]
    lea rsi, [rip + .Lp_ignored]
    call sb_push_cstr
    mov rdi, [rsp]
    mov rsi, [rip + ecf_ignored]
    call sb_push_u64
    mov rdi, [rsp]
    mov esi, 10
    call sb_push_byte
9:  xor eax, eax
    EPILOGUE

.section .rodata
.Lempty: .asciz ""
.Lf_scope: .asciz "scope"
.Lf_languages: .asciz "languages"
.Lv_workspace: .asciz "workspace"
.Lv_folder: .asciz "folder"
.Lv_yes: .asciz "yes"
.Lv_no: .asciz "no"
.Lf_file: .asciz ".rhun/extensions.ini"
.Lt_sets: .asciz "This workspace sets "
.Lt_file: .asciz " (.rhun/extensions.ini)"
.Lt_open: .asciz " ("
.Lt_close: .asciz ")"
.Lev_changed: .asciz "0 setting-changed "
.Lp_value: .asciz "value="
.Lp_window: .asciz " window="
.Lp_ignored: .asciz " ignored="
