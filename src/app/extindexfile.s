# the rhun extensions index (extension management): rhun-editor/extensions publishes index.ini as a
# release asset (with sha256sums.txt), the reviewed version of each extension it lists: its tag and
# archive digests, title, description, color, category, keywords, permissions, the oldest rhun it
# works with, featured, and a pack's members. rhun fetches it for an update check, for Browse when
# the cached copy is older than a day, and on Refresh (never at startup for Browse's sake), and keeps
# it in $XDG_STATE_HOME/rhun/extension-index.ini. Browse's list (search and order) is here too.
#   format = 1                       an index with a newer format asks for a newer rhun
#   [owner/name]                     title, version and tag required; sha256.TARGET per system
.include "rhun.inc"

.equ XI_MAX, 2000               # entries
.equ XI_FILE_MAX, 1048576       # bytes of index.ini
.equ XI_VAL_MAX, 1000           # bytes of a value
.equ XI_AGE, 86400              # seconds: older is fetched again for Browse

.bss
.p2align 3
xi_tab: .zero XI_SIZE * XI_MAX
xi_arena: .zero SB_SIZE         # the strings: offsets while parsing, pointers after
xi_path: .zero SB_SIZE          # the cache's path
xi_sb: .zero SB_SIZE
xi_out: .zero SB_SIZE           # the fetch job's output
xi_n: .long 0
xi_format: .long 0              # the index's format (0: no index)
xi_loaded: .long 0              # the cache was read
xi_pid: .long 0
xi_busy: .long 0                # a fetch runs
.p2align 3
xi_fetched: .quad 0             # unix seconds the cache was written, 0 without one
xi_done: .quad 0                # called when the running fetch ends (or 0)
xi_done2: .quad 0               # and a second caller's
xi_error: .zero 256             # why the last fetch failed
.ifdef WINDOWS
xi_ev: .zero 2 * SB_SIZE
xi_envv: .zero 24
xi_envp: .quad 0
xi_shell: .quad 0
xi_argv: .zero 64
.endif
.globl g_xi_list, g_xi_count
g_xi_list: .zero 4 * XI_MAX     # Browse: the entries that match the search, in order
g_xi_count: .long 0
xi_qhash: .quad 0               # the search the list was made for
xi_qgen: .long 0                # the index load it was made for

.data
xi_fd: .long -1

.text

# ---------------- the cache ----------------

# xi_cache_path() -> $XDG_STATE_HOME/rhun/extension-index.ini (or ~/.local/state/...), or 0
xi_cache_path:
    PROLOGUE
    lea rdi, [rip + xi_path]
    call sb_clear
    lea rdi, [rip + .Lenv_state]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    lea rdi, [rip + xi_path]
    mov rsi, rax
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 8f
    cmp byte ptr [rax], 0
    je 8f
    lea rdi, [rip + xi_path]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + xi_path]
    lea rsi, [rip + .Llocal_state]
    call sb_push_cstr
2:  lea rdi, [rip + xi_path]
    lea rsi, [rip + .Lcache_name]
    call sb_push_cstr
    lea rdi, [rip + xi_path]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + xi_path + SB_ptr]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# xi_ensure(): the cache is read once (later fetches read it again)
xi_ensure:
    cmp dword ptr [rip + xi_loaded], 0
    jne 1f
    jmp xi_load
1:  ret

# xi_load(): the cached index into the table (an entry without title, version and tag is left out)
xi_load:
    PROLOGUE INI_SIZE + 16
    mov dword ptr [rip + xi_loaded], 1
    inc dword ptr [rip + xi_qgen]
    mov dword ptr [rip + xi_n], 0
    mov dword ptr [rip + xi_format], 0
    mov qword ptr [rip + xi_fetched], 0
    lea rdi, [rip + xi_arena]
    call sb_clear
    lea rdi, [rip + xi_arena]
    xor esi, esi
    call sb_push_byte           # offset 0 stands for none
    call xi_cache_path
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    call file_mtime
    mov [rip + xi_fetched], rax
    mov rdi, r12
    mov esi, XI_FILE_MAX
    call file_read_limited
    test rax, rax
    jz 9f
    mov r12, rax
    lea rdi, [rsp]
    mov rsi, rax
    call ini_init
    xor ebx, ebx                # the entry being read, or 0
1:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz 7f
    cmp qword ptr [rsp + INI_seclen], 0
    jne 3f
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_format]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call parse_u64
    mov [rip + xi_format], eax
    jmp 1b
3:  # [owner/name]: a new entry when the section changes
    test rbx, rbx
    jz 31f
    mov rdi, [rbx + XI_name]
    add rdi, [rip + xi_arena + SB_ptr]
    mov rsi, [rsp + INI_sec]
    mov rdx, [rsp + INI_seclen]
    call same_text
    test eax, eax
    jnz 4f
    mov rdi, rbx
    call xi_finish
31: xor ebx, ebx
    mov rdi, [rsp + INI_sec]
    mov rsi, [rsp + INI_seclen]
    call full_name_ok
    test eax, eax
    jz 1b
    mov ecx, [rip + xi_n]
    cmp ecx, XI_MAX
    jae 1b
    inc dword ptr [rip + xi_n]
    imul rbx, rcx, XI_SIZE
    lea rax, [rip + xi_tab]
    add rbx, rax
    mov rdi, rbx
    xor esi, esi
    mov edx, XI_SIZE
    call memset
    mov rdi, [rsp + INI_sec]
    mov rsi, [rsp + INI_seclen]
    call xi_keep
    mov [rbx + XI_name], rax
4:  # its keys
    lea r13, [rip + xi_keys]
5:  mov rsi, [r13]
    test rsi, rsi
    jz 6f
    lea rdi, [rsp]
    call ini_key_is
    test eax, eax
    jnz 51f
    add r13, 16
    jmp 5b
51: mov r14, [r13 + 8]
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call xi_keep
    mov [rbx + r14], rax
    jmp 1b
6:  # sha256.TARGET, color, featured
    mov rdi, [rsp + INI_key]
    mov rsi, [rsp + INI_keylen]
    lea rdx, [rip + .Lk_sha_target]
    call str_eq_cstr
    test eax, eax
    jz 61f
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call xi_keep
    mov [rbx + XI_digest], rax
    jmp 1b
61: lea rdi, [rsp]
    lea rsi, [rip + .Lk_color]
    call ini_key_is
    test eax, eax
    jz 62f
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call parse_color
    test edx, edx
    jz 1b
    or eax, 0xff000000
    mov [rbx + XI_color], eax
    jmp 1b
62: lea rdi, [rsp]
    lea rsi, [rip + .Lk_featured]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    lea rdx, [rip + .Lyes]
    call str_eq_cstr
    mov [rbx + XI_featured], eax
    jmp 1b
7:  test rbx, rbx
    jz 71f
    mov rdi, rbx
    call xi_finish
71: mov rdi, r12
    call mem_free
    # offsets to pointers (the arena no longer moves)
    xor r12d, r12d
8:  cmp r12d, [rip + xi_n]
    jae 9f
    imul rbx, r12, XI_SIZE
    lea rax, [rip + xi_tab]
    add rbx, rax
    inc r12d
    xor ecx, ecx
81: mov rax, [rbx + rcx*8]
    test rax, rax
    jz 82f
    add rax, [rip + xi_arena + SB_ptr]
    mov [rbx + rcx*8], rax
82: inc ecx
    cmp ecx, XI_FIELDS
    jb 81b
    jmp 8b
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# xi_finish(entry): the entry ends; without title, version and tag it is dropped (the last one)
xi_finish:
    cmp qword ptr [rdi + XI_title], 0
    je 1f
    cmp qword ptr [rdi + XI_version], 0
    je 1f
    cmp qword ptr [rdi + XI_tag], 0
    je 1f
    ret
1:  dec dword ptr [rip + xi_n]
    ret

# xi_keep(ptr, len) -> its offset in the arena (at most XI_VAL_MAX bytes, and a NUL)
xi_keep:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp r13, XI_VAL_MAX
    jbe 1f
    mov r13d, XI_VAL_MAX
1:  mov rbx, [rip + xi_arena + SB_len]
    lea rdi, [rip + xi_arena]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + xi_arena]
    xor esi, esi
    call sb_push_byte
    mov rax, rbx
    EPILOGUE

# same_text(cstr, ptr, len) -> 1 when equal
same_text:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rax
    jmp str_eq_cstr

# full_name_ok(ptr, len) -> 1 for OWNER/NAME of [A-Za-z0-9._-], neither starting with a dot
full_name_ok:
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 200
    ja 9f
    xor ecx, ecx
    mov r8, -1                  # the slash
1:  cmp rcx, rsi
    jae 3f
    movzx edx, byte ptr [rdi + rcx]
    cmp edx, '/'
    jne 2f
    cmp r8, -1
    jne 9f
    mov r8, rcx
    inc rcx
    jmp 1b
2:  cmp edx, '.'
    je 21f
    cmp edx, '_'
    je 21f
    cmp edx, '-'
    je 21f
    lea r9d, [rdx - '0']
    cmp r9d, 9
    jbe 21f
    or edx, 0x20
    sub edx, 'a'
    cmp edx, 25
    ja 9f
21: inc rcx
    jmp 1b
3:  test r8, r8
    jle 9f
    lea rcx, [r8 + 1]
    cmp rcx, rsi
    jae 9f
    cmp byte ptr [rdi], '.'
    je 9f
    cmp byte ptr [rdi + r8 + 1], '.'
    je 9f
    mov eax, 1
9:  ret

# ---------------- lookups ----------------

# extindex_find(name cstr) -> the entry for owner/name (ignoring case), or 0
FN extindex_find
    PROLOGUE
    mov r12, rdi
    call xi_ensure
    xor r13d, r13d
1:  cmp r13d, [rip + xi_n]
    jae 8f
    imul rbx, r13, XI_SIZE
    lea rax, [rip + xi_tab]
    add rbx, rax
    inc r13d
    mov rdi, [rbx + XI_name]
    mov rsi, r12
    call same_ci_names
    test eax, eax
    jz 1b
    mov rax, rbx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# same_ci_names(a, b) -> 1 when the cstrs are equal ignoring ASCII case
same_ci_names:
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

# extindex_pin(name cstr "owner/name") -> rax the pinned tag and rdx this system's digest, or rax 0
# when the index does not list it for this system (or needs a newer rhun to read)
FN extindex_pin
    PROLOGUE
    call extindex_find
    test rax, rax
    jz 8f
    cmp dword ptr [rip + xi_format], 1
    ja 8f
    mov rdx, [rax + XI_digest]
    test rdx, rdx
    jz 8f
    mov rax, [rax + XI_tag]
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# extindex_tag(name cstr) -> rax the pinned tag of an extension the index lists for this system, or 0
FN extindex_tag
    jmp extindex_pin

# extindex_dump_age(sb): "Index updated 2 h ago" (or nothing without an index), for Browse
FN extindex_fetched
    call xi_ensure
    mov rax, [rip + xi_fetched]
    ret

# extindex_state() -> eax 0 no index, 1 an index, 2 one rhun is too old to read; edx 1 while fetching
FN extindex_state
    PROLOGUE
    call xi_ensure
    xor eax, eax
    cmp dword ptr [rip + xi_format], 0
    je 1f
    mov eax, 1
    cmp dword ptr [rip + xi_format], 1
    jbe 1f
    mov eax, 2
1:  mov edx, [rip + xi_busy]
    EPILOGUE

# extindex_error() -> why the last fetch failed (cstr, empty when it did not)
FN extindex_error
    lea rax, [rip + xi_error]
    ret

# ---------------- fetching ----------------

# extindex_fetch(done fn): fetch the index now; done() is called once it is in (or could not be had)
FN extindex_fetch
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + xi_busy], 0
    je 1f
    # a fetch runs already: done joins it
    mov [rip + xi_done2], rbx
    EPILOGUE
1:  mov [rip + xi_done], rbx
    call xi_spawn
    test eax, eax
    jnz 9f
    lea rdi, [rip + .Le_start]
    call xi_failed
9:  EPILOGUE

# extindex_browse_fetch(): Browse is shown: the index is fetched when the cached copy is missing or
# older than a day
FN extindex_browse_fetch
    PROLOGUE
    call xi_ensure
    cmp dword ptr [rip + xi_busy], 0
    jne 9f
    cmp byte ptr [rip + xi_error], 0
    jne 9f                      # it failed this session: Refresh tries again
    mov rbx, [rip + xi_fetched]
    test rbx, rbx
    jz 1f
    call time_now
    sub rax, rbx
    cmp rax, XI_AGE
    jb 9f
1:  xor edi, edi
    call extindex_fetch
9:  EPILOGUE

# extindex_refresh(): Refresh
FN extindex_refresh
    PROLOGUE
    cmp dword ptr [rip + xi_busy], 0
    jne 9f
    xor edi, edi
    call extindex_fetch
9:  EPILOGUE

# xi_spawn() -> eax 1 when the fetch job runs
xi_spawn:
    PROLOGUE 64
    call xi_cache_path
    test rax, rax
    jz 8f
    mov rdi, rax
    call mkdir_parent
.ifdef WINDOWS
    call ext_release_base
    lea rdi, [rip + xi_ev]
    lea rsi, [rip + .Lex_base]
    mov rdx, rax
    call ei_var
    mov [rip + xi_envv], rax
    lea rdi, [rip + xi_ev + SB_SIZE]
    lea rsi, [rip + .Lex_out]
    mov rdx, [rip + xi_path + SB_ptr]
    call ei_var
    mov [rip + xi_envv + 8], rax
    mov qword ptr [rip + xi_envv + 16], 0
    mov rdi, [rip + xi_envp]
    call mem_free
    lea rdi, [rip + xi_envv]
    call env_make
    mov [rip + xi_envp], rax
    mov rdi, [rip + xi_shell]
    call mem_free
    lea rdi, [rip + .Lex_shell]
    call proc_which
    mov [rip + xi_shell], rax
    test rax, rax
    jz 8f
    lea rcx, [rip + xi_argv]
    mov [rcx], rax
    lea rax, [rip + .Lex_noprofile]
    mov [rcx + 8], rax
    lea rax, [rip + .Lex_noninteractive]
    mov [rcx + 16], rax
    lea rax, [rip + .Lex_outputformat]
    mov [rcx + 24], rax
    lea rax, [rip + .Lex_text]
    mov [rcx + 32], rax
    lea rax, [rip + .Lex_encoded]
    mov [rcx + 40], rax
    lea rax, [rip + ext_index_script]
    mov [rcx + 48], rax
    mov qword ptr [rcx + 56], 0
    mov rdi, rcx
    mov rsi, [rip + xi_envp]
.else
    # argv: sh -c SCRIPT rhun-index BASE OUT
    lea rax, [rip + .Lsh]
    mov [rsp], rax
    lea rax, [rip + .Ldash_c]
    mov [rsp + 8], rax
    lea rax, [rip + index_script]
    mov [rsp + 16], rax
    lea rax, [rip + .Lsh_name]
    mov [rsp + 24], rax
    call ext_release_base
    mov [rsp + 32], rax
    mov rax, [rip + xi_path + SB_ptr]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    lea rdi, [rsp]
    mov rsi, [rip + g_envp]
.endif
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    mov [rip + xi_pid], eax
    mov [rip + xi_fd], edx
    lea rdi, [rip + xi_out]
    call sb_clear
    mov edi, [rip + xi_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_xi_job]
    xor ecx, ecx
    call watch_add
    mov dword ptr [rip + xi_busy], 1
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# on_xi_job(fd, revents, ctx): the fetch's output; at its end the cache is read again, or why it
# failed is kept
on_xi_job:
    PROLOGUE
1:  lea rdi, [rip + xi_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + xi_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    cmp qword ptr [rip + xi_out + SB_len], 65536
    jae 1b
    add [rip + xi_out + SB_len], rax
    jmp 1b
2:  mov edi, [rip + xi_fd]
    call watch_remove
    mov edi, [rip + xi_fd]
    SYS SYS_close
    mov dword ptr [rip + xi_fd], -1
    mov edi, [rip + xi_pid]
    xor esi, esi
    call proc_wait
    mov ebx, eax
    mov dword ptr [rip + xi_busy], 0
    lea rdi, [rip + xi_out]
    xor esi, esi
    call sb_push_byte
    # the last line: "ok", or why
    mov rdi, [rip + xi_out + SB_ptr]
    call last_line
    mov r12, rax
    test ebx, ebx
    jnz 3f
    cmp byte ptr [r12], 'o'
    jne 3f
    cmp byte ptr [r12 + 1], 'k'
    jne 3f
    mov byte ptr [rip + xi_error], 0
    call xi_load
    call xi_call_done
    jmp 9f
3:  mov rdi, r12
    cmp byte ptr [r12], 0
    jne 4f
    lea rdi, [rip + .Le_fetch]
4:  call xi_failed
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# xi_failed(why): the fetch failed: kept for Browse; the callers go on with the cached copy
xi_failed:
    PROLOGUE
    mov rsi, rdi
    lea rdi, [rip + xi_error]
    xor ecx, ecx
1:  mov al, [rsi + rcx]
    test al, al
    jz 2f
    cmp al, 13
    je 2f
    cmp ecx, 250
    jae 2f
    mov [rdi + rcx], al
    inc ecx
    jmp 1b
2:  mov byte ptr [rdi + rcx], 0
    mov dword ptr [rip + xi_busy], 0
    call xi_ensure
    call xi_call_done
    EPILOGUE

# xi_call_done(): the callers waiting for the fetch hear it ended
xi_call_done:
    PROLOGUE
    mov rax, [rip + xi_done]
    mov qword ptr [rip + xi_done], 0
    test rax, rax
    jz 1f
    call rax
1:  mov rax, [rip + xi_done2]
    mov qword ptr [rip + xi_done2], 0
    test rax, rax
    jz 9f
    call rax
9:  EPILOGUE

# last_line(cstr) -> its last line that is not empty (trailing LF and CR cut off in place)
last_line:
    mov rax, rdi
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0
    je 2f
    inc rcx
    jmp 1b
2:  test rcx, rcx
    jz 4f
    movzx edx, byte ptr [rdi + rcx - 1]
    cmp edx, 10
    je 3f
    cmp edx, 13
    jne 4f
3:  dec rcx
    mov byte ptr [rdi + rcx], 0
    jmp 2b
4:  test rcx, rcx
    jz 5f
    cmp byte ptr [rdi + rcx - 1], 10
    je 5f
    dec rcx
    jmp 4b
5:  lea rax, [rdi + rcx]
    ret

# ---------------- Browse: search and order ----------------

# extindex_list(query ptr, len): g_xi_list holds the entries matching the search, featured first,
# then by title; made again only when the search or the index changed
FN extindex_list
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    call xi_ensure
    mov rdi, r12
    mov rsi, r13
    call hash_line
    mov ecx, [rip + xi_qgen]
    xor rax, rcx
    cmp rax, [rip + xi_qhash]
    je 9f
    mov [rip + xi_qhash], rax
    mov dword ptr [rip + g_xi_count], 0
    xor r14d, r14d
1:  cmp r14d, [rip + xi_n]
    jae 5f
    imul rbx, r14, XI_SIZE
    lea rax, [rip + xi_tab]
    add rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call xi_matches
    test eax, eax
    jz 4f
    # insert in order
    mov ecx, [rip + g_xi_count]
    inc dword ptr [rip + g_xi_count]
    lea r15, [rip + g_xi_list]
2:  test ecx, ecx
    jz 3f
    mov eax, [r15 + rcx*4 - 4]
    mov [rsp], ecx
    imul rdi, rax, XI_SIZE
    lea rax, [rip + xi_tab]
    add rdi, rax
    mov rsi, rbx
    call xi_before
    mov ecx, [rsp]
    test eax, eax
    jnz 3f
    mov eax, [r15 + rcx*4 - 4]
    mov [r15 + rcx*4], eax
    dec ecx
    jmp 2b
3:  mov [r15 + rcx*4], r14d
4:  inc r14d
    jmp 1b
5:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# xi_before(a, b) -> 1 when entry a comes before (or with) b: featured first, then by title
xi_before:
    mov eax, [rdi + XI_featured]
    cmp eax, [rsi + XI_featured]
    je 1f
    ja 8f
    xor eax, eax
    ret
1:  mov rdi, [rdi + XI_title]
    mov rsi, [rsi + XI_title]
2:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    lea edx, [rax - 'A']
    cmp edx, 25
    ja 3f
    add eax, 32
3:  lea edx, [rcx - 'A']
    cmp edx, 25
    ja 4f
    add ecx, 32
4:  cmp eax, ecx
    jb 8f
    ja 9f
    test eax, eax
    jz 8f
    inc rdi
    inc rsi
    jmp 2b
8:  mov eax, 1
    ret
9:  xor eax, eax
    ret

# xi_matches(entry, query ptr, len) -> 1 when each word of the query starts a word of its title,
# name, owner, description or keywords (ignoring ASCII case)
xi_matches:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz 8f
    mov r14, rax
    mov r15, rdx
    lea rax, [rip + xi_search_fields]
    xor ecx, ecx
2:  mov rdx, [rax + rcx*8]
    cmp rdx, -1
    je 9f                       # no field has it
    push rcx
    push rax
    mov rdi, [rbx + rdx]
    mov rsi, r14
    mov rdx, r15
    call word_starts
    pop rcx
    pop rcx
    lea rdx, [rip + xi_search_fields]
    test eax, eax
    jnz 1b
    mov rax, rdx
    inc ecx
    jmp 2b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# word_starts(text cstr or 0, word ptr, len) -> 1 when the word starts a word of the text (a word
# starts at the text's start or after a character that is not a letter or a digit)
word_starts:
    test rdi, rdi
    jz 8f
    mov r8, rdi                 # the text's start
1:  cmp byte ptr [rdi], 0
    je 8f
    cmp rdi, r8
    je 2f
    movzx eax, byte ptr [rdi - 1]
    lea ecx, [rax - '0']
    cmp ecx, 9
    jbe 6f
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    jbe 6f
    cmp byte ptr [rdi - 1], 0x80
    jae 6f
2:  xor ecx, ecx
3:  cmp rcx, rdx
    jae 9f
    movzx eax, byte ptr [rdi + rcx]
    test eax, eax
    jz 6f
    movzx r9d, byte ptr [rsi + rcx]
    lea r10d, [rax - 'A']
    cmp r10d, 25
    ja 4f
    add eax, 32
4:  lea r10d, [r9 - 'A']
    cmp r10d, 25
    ja 5f
    add r9d, 32
5:  cmp eax, r9d
    jne 6f
    inc rcx
    jmp 3b
6:  inc rdi
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# extindex_at(i) -> the i-th entry of g_xi_list
FN extindex_at
    lea rax, [rip + g_xi_list]
    mov eax, [rax + rdi*4]
    imul rax, rax, XI_SIZE
    lea rcx, [rip + xi_tab]
    add rax, rcx
    ret

# extindex_entry_needs(entry, ext): the entry's needs (KEY=VALUE words, lists comma separated) as
# [needs] bits and a run list in the scratch record ext (for ext_needs_words)
FN extindex_entry_needs
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov dword ptr [r12 + EXT_needs], 0
    mov rdi, [r12 + EXT_runs]
    call mem_free
    mov qword ptr [r12 + EXT_runs], 0
    mov r13, [rbx + XI_needs]
    test r13, r13
    jz 9f
1:  mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    call next_word
    add r13, rcx
    test rdx, rdx
    jz 9f
    mov r14, rax
    mov r15, rdx
    lea rcx, [rip + xi_needs_map]
2:  mov rsi, [rcx]
    test rsi, rsi
    jz 3f
    push rcx
    push rcx
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rcx]
    call str_eq_cstr
    pop rcx
    pop rcx
    test eax, eax
    jnz 21f
    add rcx, 16
    jmp 2b
21: mov eax, [rcx + 8]
    or [r12 + EXT_needs], eax
    jmp 1b
3:  # run=a,b: the programs, space separated
    cmp r15, 4
    jbe 1b
    cmp dword ptr [r14], 0x3d6e7572 # "run="
    jne 1b
    lea rdi, [r14 + 4]
    lea rsi, [r15 - 4]
    call mem_dup
    mov [r12 + EXT_runs], rax
    mov rcx, rax
4:  cmp byte ptr [rcx], 0
    je 1b
    cmp byte ptr [rcx], ','
    jne 41f
    mov byte ptr [rcx], ' '
41: inc rcx
    jmp 4b
9:  EPILOGUE

# extindex_dump(sb): print-ext-browse: "index=N format=F fetching=0|1 error=..." and the list's
# entries, "OWNER/NAME VERSION" (the caller adds each button)
FN extindex_count
    call xi_ensure
    mov eax, [rip + xi_n]
    mov edx, [rip + xi_format]
    ret

.section .rodata
.Lenv_state: .asciz "XDG_STATE_HOME"
.Lenv_home: .asciz "HOME"
.Llocal_state: .asciz "/.local/state"
.Lcache_name: .asciz "/rhun/extension-index.ini"
.Lk_format: .asciz "format"
.Lk_title: .asciz "title"
.Lk_description: .asciz "description"
.Lk_version: .asciz "version"
.Lk_tag: .asciz "tag"
.Lk_category: .asciz "category"
.Lk_keywords: .asciz "keywords"
.Lk_needs: .asciz "needs"
.Lk_rhun: .asciz "rhun"
.Lk_pack: .asciz "pack"
.Lk_color: .asciz "color"
.Lk_featured: .asciz "featured"
.Lyes: .asciz "yes"
.ifdef WINDOWS
.Lk_sha_target: .asciz "sha256.windows-x64"
.endif
.ifdef MACOS
.Lk_sha_target: .asciz "sha256.macos-arm64"
.endif
.ifndef WINDOWS
.ifndef MACOS
.Lk_sha_target: .asciz "sha256.linux-x86_64"
.endif
.endif
.Ln_documents_read: .asciz "documents=read"
.Ln_documents_write: .asciz "documents=write"
.Ln_project_read: .asciz "project=read"
.Ln_project_write: .asciz "project=write"
.Ln_home_read: .asciz "home=read"
.Ln_network: .asciz "network=yes"
.Ln_terminal: .asciz "terminal=yes"
.Lsh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh_name: .asciz "rhun-index"
.Le_start: .asciz "the download did not start"
.Le_fetch: .asciz "the download failed"
.ifdef WINDOWS
.Lex_base: .asciz "RHUN_EX_BASE="
.Lex_out: .asciz "RHUN_EX_OUT="
.Lex_shell: .asciz "powershell.exe"
.Lex_noprofile: .asciz "-NoProfile"
.Lex_noninteractive: .asciz "-NonInteractive"
.Lex_outputformat: .asciz "-OutputFormat"
.Lex_text: .asciz "Text"
.Lex_encoded: .asciz "-EncodedCommand"
.endif
.p2align 3
xi_keys:
    .quad .Lk_title, XI_title, .Lk_description, XI_desc, .Lk_version, XI_version, .Lk_tag, XI_tag
    .quad .Lk_category, XI_category, .Lk_keywords, XI_keywords, .Lk_needs, XI_needs
    .quad .Lk_rhun, XI_rhun, .Lk_pack, XI_pack, 0, 0
xi_search_fields:
    .quad XI_title, XI_name, XI_desc, XI_keywords, -1
xi_needs_map:
    .quad .Ln_documents_read, NEEDS_DOC_READ, .Ln_documents_write, NEEDS_DOC_READ | NEEDS_DOC_WRITE
    .quad .Ln_project_read, NEEDS_PROJECT_READ, .Ln_project_write, NEEDS_PROJECT_READ | NEEDS_PROJECT_WRITE
    .quad .Ln_home_read, NEEDS_HOME_READ, .Ln_network, NEEDS_NETWORK, .Ln_terminal, NEEDS_TERMINAL, 0, 0
# the fetch: fixed text, the base and the cache file as arguments; index.ini from rhun-editor/extensions'
# latest release, checked against its sha256sums.txt, replaces the cache. The last line is "ok", or why
index_script:
    .ascii "set -u; base=$1 out=$2 tmp=$2.tmp\n"
    .ascii "proto=; case $base in https:*) proto='--proto =https --proto-redir =https' ;; esac\n"
    .ascii "fail() { rm -f \"$tmp.ini\" \"$tmp.sums\"; echo \"$1\"; exit 1; }\n"
    .ascii "get() {\n"
    .ascii "  if command -v curl >/dev/null 2>&1; then curl -fsSL $proto --max-time 60 --max-filesize 1048576 -o \"$2\" \"$1\"\n"
    .ascii "  elif command -v wget >/dev/null 2>&1; then wget -q -T 60 -O \"$2\" \"$1\"\n"
    .ascii "  else fail 'needs curl or wget'; fi\n"
    .ascii "}\n"
    .ascii "url=$base/rhun-editor/extensions/releases/latest/download\n"
    .ascii "get \"$url/index.ini\" \"$tmp.ini\" || fail 'the index could not be downloaded'\n"
    .ascii "get \"$url/sha256sums.txt\" \"$tmp.sums\" || fail 'the index has no sha256sums.txt'\n"
    .ascii "want=$(awk '$2 == \"index.ini\" || $2 == \"*index.ini\" { print $1 }' \"$tmp.sums\")\n"
    .ascii "if command -v sha256sum >/dev/null 2>&1; then have=$(sha256sum \"$tmp.ini\"); else have=$(shasum -a 256 \"$tmp.ini\"); fi\n"
    .ascii "have=${have%% *}\n"
    .ascii "[ -n \"$want\" ] && [ \"$want\" = \"$have\" ] || fail 'the index does not match its checksum'\n"
    .ascii "mv -f \"$tmp.ini\" \"$out\" || fail 'the index cannot be kept'\n"
    .ascii "rm -f \"$tmp.sums\"\n"
    .asciz "echo ok\n"
