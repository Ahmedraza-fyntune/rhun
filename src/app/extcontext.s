# extensions' context keys (feature context-keys, manifest [context]): an extension sets KEY,
# when clauses read it as NAME.KEY or OWNER/NAME.KEY (when.s). A key's value is what the running
# program set, else the manifest's [context] default, else empty. Runtime values go when the
# program stops. Also the lifecycle hooks the contributions work needs from ext.s.
.include "rhun.inc"

# a key: XK records per extension, in xc_keys[extension index]
.equ XK_name, 0                 # owned cstr
.equ XK_val, 8                  # owned cstr set at run time, or 0
.equ XK_def, 16                 # owned cstr from [context], or 0
.equ XK_SIZE, 24
.equ XC_KEYS_MAX, 64            # keys per extension, defaults included
.equ XP_MAX, 64                 # problems kept per extension

.bss
.p2align 3
xc_keys: .zero EXT_CAP * VEC_SIZE
xp_list: .zero EXT_CAP * VEC_SIZE   # per extension: its contribution problems (owned cstrs)
xp_buf: .zero SB_SIZE

.text

# xc_vec(ext) -> rax its VEC of XK records, or 0 for a pointer that is not an extension
xc_vec:
    mov rax, rdi
    sub rax, [rip + g_exts + VEC_ptr]
    jb 8f
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    test rdx, rdx
    jnz 8f
    cmp rax, EXT_CAP
    jae 8f
    imul rax, rax, VEC_SIZE
    lea rcx, [rip + xc_keys]
    add rax, rcx
    ret
8:  xor eax, eax
    ret

# xc_find(vec, key, klen) -> rax the XK with that name, or 0
xc_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 8f
    imul r15, r14, XK_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + XK_name]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# xc_present(vec) -> rax the keys with a value or a default
xc_present:
    xor eax, eax
    xor ecx, ecx
    mov rdx, [rdi + VEC_ptr]
1:  cmp rcx, [rdi + VEC_len]
    jae 9f
    imul r8, rcx, XK_SIZE
    inc rcx
    cmp qword ptr [rdx + r8 + XK_val], 0
    jne 2f
    cmp qword ptr [rdx + r8 + XK_def], 0
    je 1b
2:  inc rax
    jmp 1b
9:  ret

# xc_slot(vec, key, klen) -> rax the key's XK, made when absent (reusing an empty one), or 0 when
# the extension has XC_KEYS_MAX keys already
xc_slot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call xc_find
    test rax, rax
    jnz 9f
    mov rdi, rbx
    call xc_present
    cmp rax, XC_KEYS_MAX
    jae 8f
    # an empty record (its value removed, no default) takes the name
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 2f
    imul r15, r14, XK_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    cmp qword ptr [r15 + XK_val], 0
    jne 1b
    cmp qword ptr [r15 + XK_def], 0
    jne 1b
    mov rdi, [r15 + XK_name]
    call mem_free
    jmp 3f
2:  mov rdi, rbx
    mov esi, XK_SIZE
    call vec_push
    mov r15, rax
    xor eax, eax
    mov [r15 + XK_val], rax
    mov [r15 + XK_def], rax
3:  mov rdi, r12
    mov rsi, r13
    call mem_dup                # mem_dup ends it with a NUL
    mov [r15 + XK_name], rax
    mov rax, r15
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN xc_key_ok(ptr, len) -> eax 1 for a key name: a lowercase letter, then letters, digits and _,
# at most 40 bytes
FN xc_key_ok
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 40
    ja 9f
    movzx ecx, byte ptr [rdi]
    sub ecx, 'a'
    cmp ecx, 25
    ja 9f
    mov ecx, 1
1:  cmp rcx, rsi
    jae 8f
    movzx edx, byte ptr [rdi + rcx]
    inc rcx
    cmp dl, '_'
    je 1b
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 1b
    or dl, 0x20
    lea r8d, [rdx - 'a']
    cmp r8d, 25
    jbe 1b
    jmp 9f
8:  mov eax, 1
9:  ret

# FN xc_setting_name_ok(ptr, len) -> eax 1 for a setting key: [a-z0-9_]
FN xc_setting_name_ok
    jmp cmd_name_ok

# FN xc_names_ext(ext, name, len) -> eax 1 when the name is the extension's NAME or OWNER/NAME
FN xc_names_ext
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + EXT_name]
    call str_eq_cstr
    test eax, eax
    jnz 9f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lslash]
    mov ecx, 1
    call str_find
    test rax, rax
    jle 8f
    mov r14, rax
    mov rdi, r12
    mov rsi, r14
    mov rdx, [rbx + EXT_owner]
    call str_eq_cstr
    test eax, eax
    jz 9f
    lea rdi, [r12 + r14 + 1]
    mov rsi, r13
    sub rsi, r14
    dec rsi
    mov rdx, [rbx + EXT_name]
    call str_eq_cstr
9:  EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN xc_resolve(name, len) -> rax the installed extension NAME or OWNER/NAME names, or 0; edx 1
# when a short name fits more than one
FN xc_resolve
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d              # the match
    xor r15d, r15d              # the next record
1:  cmp r15, [rip + g_exts + VEC_len]
    jae 7f
    imul rbx, r15, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r15
    mov rdi, rbx
    call ext_is_visible
    test eax, eax
    jz 1b
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call xc_names_ext
    test eax, eax
    jz 1b
    test r14, r14
    jnz 8f
    mov r14, rbx
    jmp 1b
7:  mov rax, r14
    xor edx, edx
    EPILOGUE
8:  xor eax, eax
    mov edx, 1
    EPILOGUE

# FN xc_value(ext, key, klen) -> rax ptr, rdx len: the extension's key now (empty when unset)
FN xc_value
    PROLOGUE
    mov rbx, rsi
    mov r12, rdx
    call xc_vec
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call xc_find
    test rax, rax
    jz 8f
    mov rdi, [rax + XK_val]
    test rdi, rdi
    jnz 1f
    mov rdi, [rax + XK_def]
    test rdi, rdi
    jz 8f
1:  mov rbx, rdi
    call strlen
    mov rdx, rax
    mov rax, rbx
    EPILOGUE
8:  lea rax, [rip + .Lslash]
    xor edx, edx
    EPILOGUE

# FN xc_setting(ext, key, klen) -> rax ptr, rdx len: the extension's setting KEY ([settings], the
# value 0 setting sends), empty when it has none
FN xc_setting
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + EXT_sdefs + VEC_len]
    jae 8f
    imul r15, r14, SD_SIZE
    add r15, [rbx + EXT_sdefs + VEC_ptr]
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + SD_key]
    call str_eq_cstr
    test eax, eax
    jz 1b
    mov rdi, [r15 + SD_value]
    test rdi, rdi
    jz 8f
    mov rbx, rdi
    call strlen
    mov rdx, rax
    mov rax, rbx
    EPILOGUE
8:  lea rax, [rip + .Lslash]
    xor edx, edx
    EPILOGUE

# FN xc_set(ext, key, klen, value, vlen) -> eax 0 set, 1 too many keys, 2 not a key name; vlen 0
# removes the run-time value (the default applies again)
FN xc_set
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, r12
    mov rsi, r13
    call xc_key_ok
    test eax, eax
    jz 7f
    mov rdi, rbx
    call xc_vec
    test rax, rax
    jz 7f
    mov [rsp], rax
    test r15, r15
    jnz 1f
    # removal
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call xc_find
    test rax, rax
    jz 5f
    mov rbx, rax
    mov rdi, [rbx + XK_val]
    call mem_free
    mov qword ptr [rbx + XK_val], 0
    jmp 5f
1:  mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call xc_slot
    test rax, rax
    jz 6f
    mov rbx, rax
    mov rdi, [rbx + XK_val]
    call mem_free
    mov rdi, r14
    mov rsi, r15
    call mem_dup
    mov [rbx + XK_val], rax
5:  mov dword ptr [rip + g_dirty], 1
    xor eax, eax
    EPILOGUE
6:  mov eax, 1
    EPILOGUE
7:  mov eax, 2
    EPILOGUE

# FN xc_default(ext, key, klen, value, vlen) -> eax as xc_set: a [context] default
FN xc_default
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, r12
    mov rsi, r13
    call xc_key_ok
    test eax, eax
    jz 7f
    cmp r15, CTX_VAL_MAX
    ja 7f
    mov rdi, rbx
    call xc_vec
    test rax, rax
    jz 7f
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call xc_slot
    test rax, rax
    jz 6f
    mov rbx, rax
    mov rdi, [rbx + XK_def]
    call mem_free
    mov rdi, r14
    mov rsi, r15
    call mem_dup
    mov [rbx + XK_def], rax
    xor eax, eax
    EPILOGUE
6:  mov eax, 1
    EPILOGUE
7:  mov eax, 2
    EPILOGUE

# xc_clear(ext, defaults too): the run-time values go (and the defaults with them)
xc_clear:
    PROLOGUE
    mov r12d, esi
    call xc_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r13d, r13d
1:  cmp r13, [rbx + VEC_len]
    jae 2f
    imul r14, r13, XK_SIZE
    add r14, [rbx + VEC_ptr]
    inc r13
    mov rdi, [r14 + XK_val]
    call mem_free
    mov qword ptr [r14 + XK_val], 0
    test r12d, r12d
    jz 1b
    mov rdi, [r14 + XK_def]
    call mem_free
    mov qword ptr [r14 + XK_def], 0
    mov rdi, [r14 + XK_name]
    call mem_free
    jmp 1b
2:  test r12d, r12d
    jz 9f
    mov qword ptr [rbx + VEC_len], 0
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN xc_dump_ext(out sb, ext): "  KEY=VALUE" lines of its keys (print-context for an extension)
FN xc_dump_ext
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    call xc_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r13d, r13d
1:  cmp r13, [rbx + VEC_len]
    jae 9f
    imul r14, r13, XK_SIZE
    add r14, [rbx + VEC_ptr]
    inc r13
    mov r15, [r14 + XK_val]
    test r15, r15
    jnz 2f
    mov r15, [r14 + XK_def]
    test r15, r15
    jz 1b
2:  mov rdi, r12
    mov rsi, [r14 + XK_name]
    call sb_push_cstr
    mov rdi, r12
    mov esi, '='
    call sb_push_byte
    mov rdi, r12
    mov rsi, r15
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# ---------------- lifecycle hooks (ext.s calls them) ----------------

# FN contrib_ext_stopped(ext): its program stopped: what it set at run time goes, and the calls
# it made or was asked
FN contrib_ext_stopped
    PROLOGUE
    mov rbx, rdi
    call invoke_ext_stopped
    mov rdi, rbx
    xor esi, esi
    call xc_clear
    EPILOGUE

# FN contrib_ext_gone(ext): it was removed: everything of it goes
FN contrib_ext_gone
    PROLOGUE
    mov rbx, rdi
    mov esi, 1
    call xc_clear
    mov rdi, rbx
    call cmdopt_clear
    mov rdi, rbx
    call xp_clear
    EPILOGUE

# ---------------- problems: manifest entries that were dropped, shown on its page ----------------

# xp_vec(ext) -> rax its problems' VEC, or 0
xp_vec:
    call xc_vec
    test rax, rax
    jz 1f
    lea rcx, [rip + xc_keys]
    sub rax, rcx
    lea rcx, [rip + xp_list]
    add rax, rcx
1:  ret

# FN contrib_problem(ext, cstr): one more problem (a copy; at most XP_MAX are kept)
FN contrib_problem
    PROLOGUE
    mov r12, rsi
    call xp_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp qword ptr [rbx + VEC_len], XP_MAX
    jae 9f
    mov rdi, r12
    call dup_cstr
    mov r12, rax
    mov rdi, rbx
    mov esi, 8
    call vec_push
    mov [rax], r12
9:  EPILOGUE

# xp_begin(ini): xp_buf holds "[SECTION] KEY: "
xp_begin:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + xp_buf]
    call sb_clear
    lea rdi, [rip + xp_buf]
    mov esi, '['
    call sb_push_byte
    lea rdi, [rip + xp_buf]
    mov rsi, [rbx + INI_sec]
    mov rdx, [rbx + INI_seclen]
    call sb_push
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lxp_sep]
    call sb_push_cstr
    lea rdi, [rip + xp_buf]
    mov rsi, [rbx + INI_key]
    mov rdx, [rbx + INI_keylen]
    call sb_push
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lxp_colon]
    call sb_push_cstr
    pop rbx
    ret

# FN contrib_problem_line(ext, ini, text): "[SECTION] KEY: TEXT"
FN contrib_problem_line
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov rdi, rsi
    call xp_begin
    lea rdi, [rip + xp_buf]
    mov rsi, r12
    call sb_push_cstr
    jmp xp_end

# FN contrib_problem_when(ext, ini, byte, text): "[SECTION] KEY: when: TEXT at byte N"
FN contrib_problem_when
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov rdi, rsi
    call xp_begin
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lxp_when]
    call sb_push_cstr
    lea rdi, [rip + xp_buf]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + xp_buf]
    lea rsi, [rip + .Lxp_at]
    call sb_push_cstr
    lea rdi, [rip + xp_buf]
    mov rsi, r12
    call sb_push_u64
xp_end:                         # (shares the PROLOGUE of its two callers)
    lea rdi, [rip + xp_buf]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + xp_buf + SB_ptr]
    call contrib_problem
    EPILOGUE

# xp_clear(ext)
xp_clear:
    PROLOGUE
    call xp_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r12d, r12d
1:  cmp r12, [rbx + VEC_len]
    jae 2f
    mov rax, [rbx + VEC_ptr]
    mov rdi, [rax + r12*8]
    call mem_free
    inc r12
    jmp 1b
2:  mov qword ptr [rbx + VEC_len], 0
9:  EPILOGUE

# FN contrib_problems_dump(out sb, ext): "problem=TEXT" lines (print-ext-page and tests)
FN contrib_problems_dump
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    call xp_vec
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r13d, r13d
1:  cmp r13, [rbx + VEC_len]
    jae 9f
    mov rdi, r12
    lea rsi, [rip + .Lxp_problem]
    call sb_push_cstr
    mov rax, [rbx + VEC_ptr]
    mov rsi, [rax + r13*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r13
    jmp 1b
9:  EPILOGUE

# FN contrib_problem_count(ext) -> rax
FN contrib_problem_count
    call xp_vec
    test rax, rax
    jz 1f
    mov rax, [rax + VEC_len]
1:  ret

# FN contrib_manifest_kv(ext, ini) -> eax 1 when the manifest line was one of the contributions'
# sections ([context] here; the others as they come)
FN contrib_manifest_kv
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rip + .Ls_command_options]
    call ini_sec_is
    test eax, eax
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    call cmdopt_parse
    mov eax, 1
    EPILOGUE
1:  mov rdi, r12
    lea rsi, [rip + .Ls_context]
    call ini_sec_is
    test eax, eax
    jz 8f
    mov rdi, [r12 + INI_val]
    mov rsi, [r12 + INI_vallen]
    call trim
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    mov rsi, [r12 + INI_key]
    mov rdx, [r12 + INI_keylen]
    call xc_default
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.section .rodata
.Lslash: .asciz "/"
.Ls_context: .asciz "context"
.Ls_command_options: .asciz "command-options"
.Lxp_sep: .asciz "] "
.Lxp_colon: .asciz ": "
.Lxp_when: .asciz "when: "
.Lxp_at: .asciz " at byte "
.Lxp_problem: .asciz "problem="
