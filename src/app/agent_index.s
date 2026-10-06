# Metadata index worker. No UI, transcript loading, or external programs.
.include "rhun.inc"

STRUCT
F AW_path, 8
F AW_claude, 8
F AW_name, 8
F AW_saved, 8
F AW_guard, 8
ENDSTRUCT AW_SIZE


.bss
.p2align 3
roots: .zero VEC_SIZE
entries: .zero VEC_SIZE
matches: .zero VEC_SIZE
tmp: .zero SB_SIZE
packet: .zero SB_SIZE
cache_key: .zero SB_SIZE
cache_file: .zero SB_SIZE
history_file: .zero SB_SIZE
history_dir: .zero SB_SIZE
history_item: .zero SB_SIZE
member_file: .zero SB_SIZE
repository: .quad 0
history_records: .zero VEC_SIZE
table: .quad 0
page_limit: .quad 0
scan_failed: .long 0
.text
# root_add(name path override or 0, path, linked): retain entries across refreshes.
root_add:
    PROLOGUE
    mov r12, rsi
    mov r13d, edx
    mov r14, rdi
    xor r15d, r15d
    xor ebx, ebx
1:  cmp rbx, [rip + roots + VEC_len]
    jae 2f
    mov rax, [rip + roots + VEC_ptr]
    mov rax, [rax + rbx*8]
    mov r15, rax
    mov rdi, [rax + AW_path]
    mov rsi, r12
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 9f
    inc rbx
    jmp 1b
2:  cmp qword ptr [rip + roots + VEC_len], 4096
    jae 8f
    mov edi, AW_SIZE
    call mem_alloc
    mov r15, rax
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov [r15 + AW_path], rax
    test r13d, r13d
    jz 3f
    test r14, r14
    cmovz r14, r12
    mov rdi, r14
    call worktree_name
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov [r15 + AW_name], rax
3:  lea rdi, [rip + roots]
    mov esi, 8
    call vec_push
    mov [rax], r15
    mov rdi, r15
    call claude_root
9:  mov rax, r15
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# worktree_name(path) -> ptr, len. Codex puts the repo inside a named worktree directory.
worktree_name:
    PROLOGUE
    mov r12, rdi
    call strlen
    mov r13, rax
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lcodex_worktrees]
    mov ecx, 18
    call str_find
    test rax, rax
    js 3f
    lea rbx, [r12 + rax + 18]
    mov rax, rbx
1:  cmp byte ptr [rax], 0
    je 3f
    cmp byte ptr [rax], '/'
    je 2f
    inc rax
    jmp 1b
2:  mov rdx, rax
    sub rdx, rbx
    jz 3f
    mov rax, rbx
    EPILOGUE
3:
    mov rdi, r12
    mov rsi, r13
    call path_basename
    EPILOGUE

# claude_root(AW*): session directory for this checkout.
claude_root:
    PROLOGUE
    mov rbx, rdi
    # ~/.claude/projects/<path with every non-alphanumeric UTF-16 unit as '-'>
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lclaude_projects]
    call sb_push_cstr
    mov rdi, [rip + tmp + SB_ptr]
    mov r12, [rbx + AW_path]
    mov rdi, r12
    call strlen
    lea r13, [r12 + rax]
3:  cmp r12, r13
    jae 4f
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call utf8_decode
    add r12, rdx
    mov r14d, eax
    mov esi, eax
    lea ecx, [rax - '0']
    cmp ecx, 9
    jbe 31f
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    jbe 31f
    mov esi, '-'
31: lea rdi, [rip + tmp]
    call sb_push_byte
    # Claude's JS regex has no Unicode flag: supplementary characters take two '-'.
    cmp r14d, 0xffff
    jbe 3b
    lea rdi, [rip + tmp]
    mov esi, '-'
    call sb_push_byte
    jmp 3b
4:  mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [rip + tmp + SB_len]
    call mem_dup
    mov [rbx + AW_claude], rax
    mov rdi, rax
9:
    EPILOGUE


FN agent_index_main
    PROLOGUE
    mov rbx, [rip + g_argv]
    mov rax, [rbx + 16]
    mov [rip + g_project], rax
    mov rdi, [rbx + 24]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 24]
    call parse_u64
    cmp rax, 50
    jb .Lindex_bad
    cmp rax, 100000
    ja .Lindex_bad
    mov [rip + page_limit], rax
    mov rax, [rbx + 32]
    mov [rip + cfg_agent_sources], rax
    mov dword ptr [rip + cfg_git], 0
    call git_set_project
    mov rdi, [rip + g_git_root]
    mov rsi, [rip + g_project]
    xor edx, edx
    cmp byte ptr [rip + g_worktree], 0
    setne dl
    call root_add
    lea rdi, [rip + root_add]
    xor esi, esi
    call git_each_agent_worktree
    mov edi, 8 * 262144
    call mem_alloc
    mov [rip + table], rax
    call cache_path
    call history_load
    cmp dword ptr [rip + scan_failed], 0
    jne .Lindex_bad
    call history_save
    call cache_load
    call verify_roots
    # Cached metadata supplies a provisional page before full directory discovery.
    xor edi, edi
    call collect_matches
    cmp dword ptr [rip + scan_failed], 0
    jne .Lindex_bad
    mov rdi, 0x3356455250484152   # RAHPREV3
    call emit_page
    call scan_sources
    cmp dword ptr [rip + scan_failed], 0
    jne .Lindex_bad
    call recover_roots
    call history_save
    call verify_roots
    mov edi, 1
    call collect_matches
    cmp dword ptr [rip + scan_failed], 0
    jne .Lindex_bad
    mov rdi, 0x3345474150484152   # RAHPAGE3
    call emit_page
    call cache_save
    xor eax, eax
    EPILOGUE
.Lindex_bad:
    mov eax, 1
    EPILOGUE

has_source:
    PROLOGUE
    mov r12, rdi
    call strlen
    mov r13, rax
    mov rdi, [rip + cfg_agent_sources]
    call strlen
    mov rdi, [rip + cfg_agent_sources]
    mov rsi, rax
    mov rdx, r12
    mov rcx, r13
    call str_find
    not rax
    shr rax, 63
    EPILOGUE

# Cache filename is hashed; the entire identity is also stored and checked on load.
cache_path:
    PROLOGUE 32
    call git_repository_id
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov [rip + repository], rax
    lea rdi, [rip + cache_key]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + cache_key]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    lea rdi, [rip + cache_key]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + cache_file]
    call session_state_dir
    test eax, eax
    jz 9f
    lea rdi, [rip + history_file]
    mov rsi, [rip + cache_file + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + history_file]
    lea rsi, [rip + .Lhistory_prefix]
    call sb_push_cstr
    lea rdi, [rip + history_dir]
    mov rsi, [rip + cache_file + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + history_dir]
    lea rsi, [rip + .Lhistory_dir_prefix]
    call sb_push_cstr
    lea rdi, [rip + cache_file]
    lea rsi, [rip + .Lcache_prefix]
    call sb_push_cstr
    mov rdi, [rip + cache_key + SB_ptr]
    mov rsi, [rip + cache_key + SB_len]
    call hash_line
    mov rsi, rax
    mov rdi, rsp
    call fmt_hex
    mov [rsp + 24], rax
    mov rdx, rax
    lea rdi, [rip + cache_file]
    mov rsi, rsp
    call sb_push
    lea rdi, [rip + history_file]
    mov rsi, rsp
    mov rdx, [rsp + 24]
    call sb_push
    lea rdi, [rip + history_dir]
    mov rsi, rsp
    mov rdx, [rsp + 24]
    call sb_push
9:  EPILOGUE

# Repository-scoped worktree identities survive transcript cache rebuilds and Git pruning.
history_load:
    PROLOGUE
    cmp qword ptr [rip + history_file + SB_len], 0
    je 9f
    mov rdi, [rip + history_file + SB_ptr]
    xor esi, esi              # import the earlier whole-file format once
    call history_read_file
    mov rdi, [rip + history_dir + SB_ptr]
    lea rsi, [rip + history_cb]
    mov rdx, rdi
    call dir_each
    test rax, rax
    jns 9f
    cmp rax, -2
    je 9f
    cmp rax, -20              # unavailable optional state (ENOTDIR)
    je 9f
    cmp rax, -13              # unavailable optional state (EACCES)
    je 9f
    mov dword ptr [rip + scan_failed], 1
9:  EPILOGUE

history_cb:
    PROLOGUE
    test edx, edx
    jnz 9f
    mov r12, rdi
    mov rbx, rsi
    mov rdi, rsi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    lea rdx, [rip + .Lhistory_suffix]
    mov ecx, 5
    call str_ends
    test eax, eax
    jz 9f
    mov rdi, r12
    mov rsi, rbx
    call path_join
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call history_read_file
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

history_read_file:
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], esi
    mov esi, (1 << 20) + 1
    call agent_read_head
    test rax, rax
    jnz 10f
    # Preserve the association file and previous UI snapshot on a failed read.
    mov rdi, [rsp]
    call file_stamp
    test rax, rax
    jz 9f
    mov dword ptr [rip + scan_failed], 1
    jmp 9f
10:
    mov rbx, rax
    mov r12, rdx
    cmp r12, 40
    jb 8f
    cmp r12, 1 << 20
    ja 8f
    mov r13, [rbx]
    cmp r13, [rip + cache_key + SB_len]
    jne 8f
    lea rax, [r13 + 40]
    cmp rax, r12
    ja 8f
    lea rdi, [rbx + 8]
    mov rsi, [rip + cache_key + SB_ptr]
    mov rdx, r13
    call memeq
    test eax, eax
    jz 8f
    lea rdi, [rbx + r13 + 8]
    mov rax, 0x31544f4f52484152   # RAHROOT1
    cmp [rdi], rax
    jne 8f
    cmp qword ptr [rdi + 8], 4096
    ja 8f
    mov rsi, r12
    sub rsi, r13
    sub rsi, 8
    lea rdx, [rip + history_records]
    call agent_records_decode
    test eax, eax
    jz 8f
    xor r13d, r13d
1:  cmp r13, [rip + history_records + VEC_len]
    jae 2f
    mov rax, [rip + history_records + VEC_ptr]
    mov r14, [rax + r13*8]
    cmp dword ptr [r14 + AS_kind], 1
    jne 7f
    cmp qword ptr [r14 + AS_cwd], 0
    je 7f
    cmp qword ptr [r14 + AS_worktree], 0
    je 7f
    mov rdi, [r14 + AS_path]
    mov rsi, [r14 + AS_cwd]
    call strcmp_eq
    test eax, eax
    jz 7f
    inc r13
    jmp 1b
2:  xor r13d, r13d
3:  cmp r13, [rip + history_records + VEC_len]
    jae 7f
    mov rax, [rip + history_records + VEC_ptr]
    mov rax, [rax + r13*8]
    mov rsi, [rax + AS_cwd]
    xor edi, edi
    mov edx, 1
    call root_add
    test rax, rax
    jz 31f
    cmp dword ptr [rsp + 8], 0
    je 31f
    mov qword ptr [rax + AW_saved], 1
31:
    inc r13
    jmp 3b
7:  lea rdi, [rip + history_records]
    call agent_records_free
8:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

history_save:
    PROLOGUE 32
    cmp qword ptr [rip + history_dir + SB_len], 0
    je 9f
    mov rdi, [rip + history_dir + SB_ptr]
    call mkdir_p
    mov edi, AS_SIZE
    call mem_alloc
    mov r12, rax
    mov dword ptr [r12 + AS_kind], 1
    xor ebx, ebx
3:  cmp rbx, [rip + roots + VEC_len]
    jae 4f
    mov rax, [rip + roots + VEC_ptr]
    mov rax, [rax + rbx*8]
    mov r13, rax
    cmp qword ptr [r13 + AW_saved], 0
    jne 31f
    mov rdx, [rax + AW_name]
    test rdx, rdx
    jz 31f
    mov [r12 + AS_worktree], rdx
    mov rax, [rax + AW_path]
    mov [r12 + AS_path], rax
    mov [r12 + AS_cwd], rax
    mov rdi, 0x31544f4f52484152
    mov esi, 1
    mov edx, 1
    call packet_start
    lea rdi, [rip + packet]
    mov rsi, r12
    call agent_record_encode
    call packet_finish
    lea rdi, [rip + history_item]
    call sb_clear
    lea rdi, [rip + history_item]
    mov rsi, [rip + history_dir + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + history_item]
    mov esi, '/'
    call sb_push_byte
    mov rdi, [r13 + AW_path]
    call strlen
    mov rsi, rax
    mov rdi, [r13 + AW_path]
    call hash_line
    mov rsi, rax
    mov rdi, rsp
    call fmt_hex
    mov rdx, rax
    lea rdi, [rip + history_item]
    mov rsi, rsp
    call sb_push
    lea rdi, [rip + history_item]
    lea rsi, [rip + .Lhistory_suffix]
    call sb_push_cstr
    mov rdi, [rip + history_item + SB_ptr]
    call keyed_save
    test rax, rax
    jnz 31f
    mov qword ptr [r13 + AW_saved], 1
31: inc rbx
    jmp 3b
4:  mov rdi, r12
    call mem_free
9:  EPILOGUE

# A transcript proof is keyed by its path and stable first metadata record.
# Unlike a remembered checkout path, it cannot admit a new repository's session.
member_key:
    PROLOGUE 32
    mov r12, rdi
    cmp qword ptr [rip + history_dir + SB_len], 0
    je 9f
    mov rdi, [r12 + AS_path]
    mov esi, 1 << 20
    call agent_read_first_line
    test rax, rax
    jnz 10f
    test rdx, rdx
    jns 9f
    mov dword ptr [rip + scan_failed], 1
    jmp 9f
10:
    mov rbx, rax
    mov r13, rdx
    mov rdi, rax
    mov rsi, rdx
    call json_parse
    cmp dword ptr [r12 + AS_kind], 1
    je 1f
    mov rdi, rax
    lea rsi, [rip + .Lpayload]
    call json_get
    mov r14, rax
    mov rdi, rax
    lea rsi, [rip + .Lsession_id]
    call json_get
    test rax, rax
    jnz 2f
    mov rdi, r14
    lea rsi, [rip + .Lid]
    call json_get
    jmp 2f
1:  mov rdi, rax
    lea rsi, [rip + .Lclaude_session_id]
    call json_get
2:  mov rdi, rax
    call json_str
    mov rdi, rax
    mov rsi, rdx
    test rax, rax
    jz 3f
    test rdx, rdx
    jnz 4f
3:  mov rdi, rbx
    mov rsi, r13
4:  call hash_line
    mov r14, rax
    mov rdi, rbx
    call mem_free
    lea rdi, [rip + member_file]
    call sb_clear
    lea rdi, [rip + member_file]
    mov rsi, [rip + history_dir + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + member_file]
    mov esi, '/'
    call sb_push_byte
    mov rdi, [r12 + AS_path]
    call strlen
    mov rsi, rax
    mov rdi, [r12 + AS_path]
    call hash_line
    mov rsi, rax
    mov rdi, rsp
    call fmt_hex
    mov rdx, rax
    lea rdi, [rip + member_file]
    mov rsi, rsp
    call sb_push
    lea rdi, [rip + member_file]
    mov esi, '-'
    call sb_push_byte
    mov rdi, rsp
    mov rsi, r14
    call fmt_hex
    mov rdx, rax
    lea rdi, [rip + member_file]
    mov rsi, rsp
    call sb_push
    lea rdi, [rip + member_file]
    lea rsi, [rip + .Lmember_suffix]
    call sb_push_cstr
    mov rax, [rip + member_file + SB_ptr]
    mov rdx, r14
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# member_save(AS*, foreign): immutable evidence for this transcript identity.
member_save:
    PROLOGUE 16
    mov [rsp], esi
    mov r12, rdi
    call member_key
    test rax, rax
    jz 9f
    mov r14, rdx
    mov rdi, rax
    call file_stamp
    test rax, rax
    jnz 9f
    mov edi, AS_SIZE
    call mem_alloc
    mov rbx, rax
    mov eax, [r12 + AS_kind]
    mov [rbx + AS_kind], eax
    mov rax, [r12 + AS_path]
    mov [rbx + AS_path], rax
    mov rax, [r12 + AS_cwd]
    mov [rbx + AS_cwd], rax
    mov [rbx + AS_prefix_hash], r14
    mov eax, [rsp]             # proof-only field: 0 owned, 1 foreign
    mov [rbx + AS_title_rev], rax
    mov rdi, 0x31424d454d484152   # RAHMEMB1
    mov esi, 1
    mov edx, 1
    call packet_start
    lea rdi, [rip + packet]
    mov rsi, rbx
    call agent_record_encode
    mov rdi, rbx
    call mem_free
    call packet_finish
    mov rdi, [rip + member_file + SB_ptr]
    call keyed_save
9:  EPILOGUE

# member_check(AS*) -> 1 owned, -1 foreign, 0 unknown/invalid.
member_check:
    PROLOGUE 16
    mov r12, rdi
    xor r15d, r15d
    call member_key
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, rax
    mov esi, (1 << 20) + 1
    call agent_read_head
    test rax, rax
    jnz 10f
    mov rdi, [rsp]
    call file_stamp
    test rax, rax
    jz 9f
    mov dword ptr [rip + scan_failed], 1
    jmp 9f
10: mov rbx, rax
    mov r13, rdx
    cmp r13, 40
    jb 8f
    cmp r13, 1 << 20
    ja 8f
    mov r14, [rbx]
    cmp r14, [rip + cache_key + SB_len]
    jne 8f
    lea rax, [r14 + 40]
    cmp rax, r13
    ja 8f
    lea rdi, [rbx + 8]
    mov rsi, [rip + cache_key + SB_ptr]
    mov rdx, r14
    call memeq
    test eax, eax
    jz 8f
    lea rdi, [rbx + r14 + 8]
    mov rax, 0x31424d454d484152
    cmp [rdi], rax
    jne 8f
    cmp qword ptr [rdi + 8], 1
    jne 8f
    mov rsi, r13
    sub rsi, r14
    sub rsi, 8
    lea rdx, [rip + history_records]
    call agent_records_decode
    test eax, eax
    jz 8f
    mov rax, [rip + history_records + VEC_ptr]
    mov r14, [rax]
    mov rax, [rsp + 8]
    cmp rax, [r14 + AS_prefix_hash]
    jne 7f
    cmp qword ptr [r14 + AS_title_rev], 1
    ja 7f
    mov eax, [r12 + AS_kind]
    cmp eax, [r14 + AS_kind]
    jne 7f
    cmp qword ptr [r14 + AS_cwd], 0
    je 7f
    mov rdi, [r14 + AS_path]
    mov rsi, [r12 + AS_path]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [r14 + AS_cwd]
    mov rsi, [r12 + AS_cwd]
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    mov r15d, eax
    test eax, eax
    jz 7f
    cmp qword ptr [r14 + AS_title_rev], 0
    je 7f
    mov r15d, -1
7:  lea rdi, [rip + history_records]
    call agent_records_free
8:  mov rdi, rbx
    call mem_free
9:  mov eax, r15d
    EPILOGUE

cache_load:
    PROLOGUE
    cmp qword ptr [rip + cache_file + SB_len], 0
    je 9f
    mov rdi, [rip + cache_file + SB_ptr]
    call file_open_read
    test rax, rax
    js 9f
    mov ebx, eax
    mov edi, ebx
    call file_size
    mov r12, rax
    mov edi, ebx
    SYS SYS_close
    cmp r12, 40
    jb 9f
    cmp r12, 1 << 26
    ja 9f
    mov rdi, [rip + cache_file + SB_ptr]
    lea rsi, [r12 + 1]
    call agent_read_head
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp r12, rdx
    jne 8f
    cmp rdx, 40
    jb 8f
    mov r13, [rbx]
    cmp r13, [rip + cache_key + SB_len]
    jne 8f
    lea rax, [r13 + 40]
    cmp rax, r12
    ja 8f
    lea rdi, [rbx + 8]
    mov rsi, [rip + cache_key + SB_ptr]
    mov rdx, r13
    call memeq
    test eax, eax
    jz 8f
    lea rdi, [rbx + r13 + 8]
    mov rax, 0x3558444941484152   # RAHAIDX5, verified transcript ownership
    cmp [rdi], rax
    jne 8f
    mov rsi, r12
    sub rsi, r13
    sub rsi, 8
    lea rdx, [rip + entries]
    call agent_records_decode
    test eax, eax
    jz 8f
    xor r13d, r13d
1:  cmp r13, [rip + entries + VEC_len]
    jae 8f
    mov rax, [rip + entries + VEC_ptr]
    mov rdx, [rax + r13*8]
    mov rdi, [rip + table]
    mov esi, 262143
    call agent_table_put
    inc r13
    jmp 1b
8:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

# Start a length-framed packet: magic, count, total, payload length.
packet_start:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov qword ptr [rsp + 24], 0
    lea rdi, [rip + packet]
    call sb_clear
    lea rdi, [rip + packet]
    mov rsi, rsp
    mov edx, 32
    call sb_push
    EPILOGUE
packet_finish:
    mov rax, [rip + packet + SB_ptr]
    mov rcx, [rip + packet + SB_len]
    sub rcx, 32
    mov [rax + 24], rcx
    ret

emit_page:
    PROLOGUE
    mov r12, [rip + matches + VEC_len]
    mov rdx, r12
    cmp r12, [rip + page_limit]
    cmova r12, [rip + page_limit]
    mov rsi, r12
    call packet_start
    xor ebx, ebx
1:  cmp rbx, r12
    jae 2f
    mov rax, [rip + matches + VEC_ptr]
    mov rsi, [rax + rbx*8]
    lea rdi, [rip + packet]
    call agent_record_encode
    inc rbx
    jmp 1b
2:  call packet_finish
    cmp qword ptr [rip + packet + SB_len], 1 << 26
    ja 9f
    mov edi, 1
    mov rsi, [rip + packet + SB_ptr]
    mov rdx, [rip + packet + SB_len]
    call write_all
9:  EPILOGUE

cache_save:
    PROLOGUE 16
    cmp qword ptr [rip + cache_file + SB_len], 0
    je 9f
    xor ebx, ebx
    xor r12d, r12d
1:  cmp rbx, [rip + entries + VEC_len]
    jae 2f
    mov rax, [rip + entries + VEC_ptr]
    mov rax, [rax + rbx*8]
    cmp qword ptr [rax + AS_seen], 0
    je 11f
    inc r12
11: inc rbx
    jmp 1b
2:  mov rdi, 0x3558444941484152
    mov rsi, r12
    mov rdx, r12
    call packet_start
    xor ebx, ebx
3:  cmp rbx, [rip + entries + VEC_len]
    jae 4f
    cmp qword ptr [rip + packet + SB_len], (1 << 26) - 16384
    ja 9f
    mov rax, [rip + entries + VEC_ptr]
    mov rsi, [rax + rbx*8]
    cmp qword ptr [rsi + AS_seen], 0
    je 31f
    mov qword ptr [rsi + AS_replaced], 0 # replacement is a page event, never cached
    lea rdi, [rip + packet]
    call agent_record_encode
31: inc rbx
    jmp 3b
4:  call packet_finish
    mov rdi, [rip + cache_file + SB_ptr]
    call keyed_save
9:  EPILOGUE

# keyed_save(path): atomically write the identity and current packet.
keyed_save:
    PROLOGUE 16
    mov r12, rdi
    lea rdi, [rip + tmp]
    call sb_clear
    mov rax, [rip + cache_key + SB_len]
    mov [rsp], rax
    lea rdi, [rip + tmp]
    mov rsi, rsp
    mov edx, 8
    call sb_push
    lea rdi, [rip + tmp]
    mov rsi, [rip + cache_key + SB_ptr]
    mov rdx, [rip + cache_key + SB_len]
    call sb_push
    lea rdi, [rip + tmp]
    mov rsi, [rip + packet + SB_ptr]
    mov rdx, [rip + packet + SB_len]
    call sb_push
    cmp qword ptr [rip + tmp + SB_len], 1 << 26
    ja 9f
    mov rdi, r12
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    call file_write_all
9:  EPILOGUE

# directory errors preserve the previous UI snapshot. Absent directories are normal.
scan_dir:
    call dir_each
    test rax, rax
    jns 1f
    cmp rax, -2                # ENOENT
    je 1f
    mov dword ptr [rip + scan_failed], 1
1:  ret

scan_sources:
    PROLOGUE
    lea rdi, [rip + .Lclaude]
    call has_source
    test eax, eax
    jz 3f
    xor ebx, ebx
1:  cmp rbx, [rip + roots + VEC_len]
    jae 3f
    mov rax, [rip + roots + VEC_ptr]
    mov r12, [rax + rbx*8]
    mov rdi, [r12 + AW_claude]
    test rdi, rdi
    jz 2f
    lea rsi, [rip + claude_cb]
    mov rdx, r12
    call scan_dir
    cmp qword ptr [r12 + AW_name], 0
    jne 2f
    mov rdi, r12
    call claude_retired_dirs
2:  inc rbx
    jmp 1b
3:  lea rdi, [rip + .Lcodex]
    call has_source
    test eax, eax
    jz 9f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    mov rdi, rax
    lea rsi, [rip + .Lcodex_sessions]
    call path_join
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    call codex_walk
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

claude_cb:
    PROLOGUE
    test edx, edx
    jnz 9f
    mov r12, rdi
    mov r13, rsi
    call jsonl_name
    test eax, eax
    jz 9f
    mov rdi, [r12 + AW_claude]
    mov rsi, r13
    call path_join
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    mov rdx, [r12 + AW_path]
    call index_file
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# Retired nested Claude worktrees leave project directories after Git prunes them.
# The folder prefix only selects candidates; exact cwd metadata verifies ownership.
claude_retired_dirs:
    PROLOGUE 32
    mov rbx, rdi
    mov rdi, [rbx + AW_claude]
    call strlen
    mov rdi, [rbx + AW_claude]
    mov rsi, rax
    call path_dirlen
    mov rdi, [rbx + AW_claude]
    mov rsi, rax
    call mem_dup
    mov [rsp], rax
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rbx + AW_claude]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lclaude_tree_slug]
    call sb_push_cstr
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [rip + tmp + SB_len]
    mov [rsp + 16], rsi
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, [rsp]
    lea rsi, [rip + retired_dir_cb]
    mov rdx, rsp
    call scan_dir
    mov rdi, [rsp]
    call mem_free
    mov rdi, [rsp + 8]
    call mem_free
    EPILOGUE

retired_dir_cb:
    PROLOGUE AW_SIZE
    test edx, edx
    jz 9f
    mov r12, rdi
    mov rdi, [r12]
    call path_join
    mov rbx, rax
    mov rdi, rax
    call strlen
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [r12 + 8]
    mov rcx, [r12 + 16]
    call str_starts
    test eax, eax
    jz 8f
    mov qword ptr [rsp + AW_path], 0
    mov [rsp + AW_claude], rbx
    mov qword ptr [rsp + AW_name], 0
    mov rdi, rbx
    lea rsi, [rip + claude_cb]
    mov rdx, rsp
    call scan_dir
8:  mov rdi, rbx
    call mem_free
9:  EPILOGUE

jsonl_name:
    push rsi
    mov rdi, rsi
    call strlen
    pop rdi
    mov rsi, rax
    lea rdx, [rip + .Ljsonl]
    mov ecx, 6
    jmp str_ends

codex_walk:
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], esi
    lea rsi, [rip + codex_cb]
    mov rdx, rsp
    call scan_dir
    EPILOGUE
codex_cb:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rdi, [r12]
    call path_join
    mov rbx, rax
    test r14d, r14d
    jz 1f
    cmp dword ptr [r12 + 8], 3
    jae 9f
    mov rdi, rbx
    mov esi, [r12 + 8]
    inc esi
    call codex_walk
    jmp 9f
1:  mov rsi, r13
    call jsonl_name
    test eax, eax
    jz 9f
    mov rdi, rbx
    mov esi, 2
    xor edx, edx
    call index_file
9:  mov rdi, rbx
    call mem_free
    EPILOGUE

# index_file(path, kind, Claude cwd or 0): hash lookup and stat, parse changed metadata only.
index_file:
    PROLOGUE 32
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov rdx, rdi
    mov rdi, [rip + table]
    mov esi, 262143
    call agent_table_find
    mov rbx, rax
    test rax, rax
    jnz 1f
    cmp qword ptr [rip + entries + VEC_len], 100000
    jae .Lindex_full
    mov edi, AS_SIZE
    call mem_alloc
    mov rbx, rax
    mov [rbx + AS_kind], r13d
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov [rbx + AS_path], rax
    lea rdi, [rip + entries]
    mov esi, 8
    call vec_push
    mov [rax], rbx
    mov rdi, [rip + table]
    mov esi, 262143
    mov rdx, rbx
    call agent_table_put
1:  mov qword ptr [rbx + AS_seen], 1
    mov rdi, r12
    call file_stamp
    mov r15, rax
    mov [rsp], rcx             # mtime and size from the same stat snapshot
    mov [rsp + 8], rdx
    cmp rax, [rbx + AS_stamp]
    jne 2f
    cmp qword ptr [rbx + AS_cwd], 0
    jne 9f
2:  mov rsi, [rbx + AS_stamp]
    xor rsi, [rbx + AS_recency]
    ror rsi, 32                # recover the previous size from file_stamp
    mov dword ptr [rsp + 24], 0
    cmp r13d, 1
    jne 3f
    mov rdx, [rsp + 8]
    mov rdi, rbx
    call claude_cwd
    test edx, edx
    jz 9f                     # unresolved reads retry, without guessing a slug identity
    mov [rsp + 24], ecx
    test rax, rax
    jnz 4f
    test r14, r14
    jz 4f
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call mem_dup
    jmp 4f
3:  mov rdi, r12
    call codex_cwd
    test edx, edx
    jz 9f
4:  mov [rsp + 16], rax
    cmp dword ptr [rsp + 24], 0
    je 5f
    mov rdi, [rbx + AS_cwd]
    mov rsi, rax
    test rdi, rdi
    jz 5f
    test rsi, rsi
    jz 5f
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 6f                    # same identity and verified append: keep the custom title
5:  cmp r13d, 1
    jne 51f
    mov rax, [rbx + AS_stamp]
    test rax, rax
    jz 51f
    cmp rax, r15
    je 51f
    mov qword ptr [rbx + AS_replaced], 1
51: mov rdi, [rbx + AS_title]
    call mem_free
    mov qword ptr [rbx + AS_title], 0
    mov dword ptr [rbx + AS_titled], 0
    mov qword ptr [rbx + AS_title_off], 0
6:  mov [rbx + AS_stamp], r15
    mov rax, [rsp]
    mov [rbx + AS_recency], rax
    mov rdi, [rbx + AS_cwd]
    call mem_free
    mov rax, [rsp + 16]
    mov [rbx + AS_cwd], rax
    mov dword ptr [rbx + AS_pad], 0
    mov dword ptr [rbx + AS_loaded], 1 # newly parsed metadata needs an ownership proof
9:  EPILOGUE
.Lindex_full:
    mov dword ptr [rip + scan_failed], 1
    EPILOGUE

codex_cwd:
    PROLOGUE
    mov esi, 1 << 20
    call agent_read_first_line
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    mov rsi, rdx
    call json_parse
    mov rdi, rax
    lea rsi, [rip + .Lpayload]
    call json_get
    mov rdi, rax
    lea rsi, [rip + .Lcwd]
    call json_get
    mov rdi, rax
    call json_str
    xor r12d, r12d
    test rax, rax
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r12, rax
1:  mov rdi, rbx
    call mem_free
    mov rax, r12
    mov edx, 1
    EPILOGUE
9:  xor edx, edx
    EPILOGUE

# Recover an exact nested checkout path from session metadata, without relying on its slug.
recover_roots:
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + entries + VEC_len]
    jae 9f
    mov rax, [rip + entries + VEC_ptr]
    mov rax, [rax + rbx*8]
    mov rdi, [rax + AS_cwd]
    test rdi, rdi
    jz 2f
    call recover_nested
2:  inc rbx
    jmp 1b
9:  EPILOGUE

recover_nested:
    PROLOGUE
    mov r12, rdi
.ifdef WINDOWS
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov r12, rax
    mov rdi, rax
    call win_path_normalize
.endif
    mov rdi, r12
    call strlen
    mov r13, rax
    xor ebx, ebx
1:  cmp rbx, [rip + roots + VEC_len]
    jae 9f
    mov rax, [rip + roots + VEC_ptr]
    mov r14, [rax + rbx*8]
    cmp qword ptr [r14 + AW_name], 0
    jne 8f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [r14 + AW_path]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lclaude_tree_path]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rip + tmp + SB_ptr]
    mov rcx, [rip + tmp + SB_len]
.ifdef WINDOWS
    cmp r13, rcx
    jb 8f
    mov rsi, rcx
    call mem_dup
    mov r15, rax
    mov rdi, rax
    mov rsi, [rip + tmp + SB_ptr]
    call win_path_equal
    mov r14d, eax
    mov rdi, r15
    call mem_free
    mov eax, r14d
.else
    call str_starts
.endif
    test eax, eax
    jz 8f
    mov rax, [rip + tmp + SB_len]
    lea r14, [r12 + rax]
    cmp byte ptr [r14], 0
    je 9f
    mov rax, r14
3:  cmp byte ptr [rax], 0
    je 4f
    cmp byte ptr [rax], '/'
    je 9f
    cmp byte ptr [rax], '\\'
    je 9f
    inc rax
    jmp 3b
4:  mov rdi, r14
    lea rsi, [rip + .Ldot]
    call strcmp_eq
    test eax, eax
    jnz 9f
    mov rdi, r14
    lea rsi, [rip + .Ldotdot]
    call strcmp_eq
    test eax, eax
    jnz 9f
    xor edi, edi
    mov rsi, r12
    mov edx, 1
    call root_add
    jmp 9f
8:  inc rbx
    jmp 1b
9:
.ifdef WINDOWS
    mov rdi, r12
    call mem_free
.endif
    EPILOGUE

# An existing remembered path may now be a checkout of an unrelated repository.
verify_roots:
    PROLOGUE
    mov r15, [rip + g_project]
    xor ebx, ebx
1:  cmp rbx, [rip + roots + VEC_len]
    jae 8f
    mov rax, [rip + roots + VEC_ptr]
    mov r12, [rax + rbx*8]
    mov qword ptr [r12 + AW_guard], 0
    cmp qword ptr [r12 + AW_name], 0
    je 7f
    mov rdi, [r12 + AW_path]
    call file_is_dir
    test eax, eax
    jz 7f
    mov rax, [r12 + AW_path]
    mov [rip + g_project], rax
    call git_set_project
    call git_repository_id
    mov rdi, rax
    mov rsi, [rip + repository]
    test rdi, rdi
    jz 6f
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 7f
6:  mov qword ptr [r12 + AW_guard], 1
7:  inc rbx
    jmp 1b
8:  mov [rip + g_project], r15
    call git_set_project
    EPILOGUE

# collect_matches(final): re-match cached cwd against known repository roots.
collect_matches:
    PROLOGUE
    mov r15d, edi
    mov qword ptr [rip + matches + VEC_len], 0
    xor ebx, ebx
.Lmatch_next:
    cmp rbx, [rip + entries + VEC_len]
    jae .Lmatch_done
    mov rax, [rip + entries + VEC_ptr]
    mov r12, [rax + rbx*8]
    test r15d, r15d
    jz 1f
    cmp qword ptr [r12 + AS_seen], 0
    je .Lmatch_skip
1:  lea rdi, [rip + .Lclaude]
    cmp dword ptr [r12 + AS_kind], 1
    je 2f
    lea rdi, [rip + .Lcodex]
2:  call has_source
    test eax, eax
    jz .Lmatch_skip
    cmp qword ptr [r12 + AS_cwd], 0
    je .Lmatch_skip
    xor r13d, r13d
3:  cmp r13, [rip + roots + VEC_len]
    jae .Lmatch_skip
    mov rax, [rip + roots + VEC_ptr]
    mov r14, [rax + r13*8]
    mov rdi, [r12 + AS_cwd]
    mov rsi, [r14 + AW_path]
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 4f
    inc r13
    jmp 3b
4:  cmp qword ptr [r14 + AW_name], 0
    je 42f
    mov rdi, r12
    call member_check
    cmp eax, -1
    je .Lmatch_skip
    cmp qword ptr [r14 + AW_guard], 0
    je 41f
    test eax, eax
    jnz 42f
    test r15d, r15d
    jz .Lmatch_skip
    mov rdi, r12
    mov esi, 1
    call member_save
    jmp .Lmatch_skip
41: test eax, eax
    jnz 42f
    test r15d, r15d
    jz 42f
    cmp dword ptr [r12 + AS_loaded], 0
    je 42f
    mov rdi, r12
    xor esi, esi
    call member_save
42: mov rdi, [r12 + AS_worktree]
    call mem_free
    mov qword ptr [r12 + AS_worktree], 0
    mov rdi, [r14 + AW_name]
    test rdi, rdi
    jz 5f
    call strlen
    mov rdi, [r14 + AW_name]
    mov rsi, rax
    call mem_dup
    mov [r12 + AS_worktree], rax
5:  lea rdi, [rip + matches]
    mov esi, 8
    call vec_push
    mov [rax], r12
.Lmatch_skip:
    inc rbx
    jmp .Lmatch_next
.Lmatch_done:
    call sort_matches
    test r15d, r15d
    jz 9f
    xor ebx, ebx
6:  cmp rbx, [rip + page_limit]
    jae 9f
    cmp rbx, [rip + matches + VEC_len]
    jae 9f
    mov rax, [rip + matches + VEC_ptr]
    mov r12, [rax + rbx*8]
    cmp dword ptr [r12 + AS_pad], 0
    jne 7f
    mov rdi, r12
    call agent_session_header
    mov r14d, eax
    mov rdi, r12
    call agent_session_tail_title
    and eax, r14d
    mov [r12 + AS_pad], eax
    test eax, eax
    jz 7f
    mov rax, [r12 + AS_stamp]
    xor rax, [r12 + AS_recency]
    ror rax, 32
    mov [r12 + AS_title_off], rax
7:  inc rbx
    jmp 6b
9:  EPILOGUE

# Heap sort by descending mtime, path ascending breaks ties deterministically.
sort_matches:
    PROLOGUE
    mov r12, [rip + matches + VEC_ptr]
    mov r13, [rip + matches + VEC_len]
    cmp r13, 2
    jb 9f
    mov rbx, r13
    shr rbx, 1
1:  test rbx, rbx
    jz 2f
    dec rbx
    mov rdi, rbx
    mov rsi, r13
    call sort_sift
    jmp 1b
2:  mov r14, r13
3:  dec r14
    jz 9f
    mov rax, [r12]
    mov rcx, [r12 + r14*8]
    mov [r12], rcx
    mov [r12 + r14*8], rax
    xor edi, edi
    mov rsi, r14
    call sort_sift
    jmp 3b
9:  EPILOGUE

# later(a,b) -> 1 when a belongs later in the final list.
later:
    mov rax, [rdi + AS_recency]
    cmp rax, [rsi + AS_recency]
    jne 1f
    mov rdi, [rdi + AS_path]
    mov rsi, [rsi + AS_path]
2:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    cmp eax, ecx
    jne 3f
    test eax, eax
    jz 4f
    inc rdi
    inc rsi
    jmp 2b
3:  seta al
    movzx eax, al
    ret
1:  setb al
    movzx eax, al
    ret
4:  xor eax, eax
    ret
sort_sift:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov rax, [r12 + rdi*8]
    mov [rsp + 16], rax
1:  mov rdi, [rsp]
    lea rbx, [rdi*2 + 1]
    cmp rbx, [rsp + 8]
    jae 4f
    lea r15, [rbx + 1]
    cmp r15, [rsp + 8]
    jae 2f
    mov rdi, [r12 + r15*8]
    mov rsi, [r12 + rbx*8]
    call later
    test eax, eax
    cmovnz rbx, r15
2:  mov rdi, [r12 + rbx*8]
    mov rsi, [rsp + 16]
    call later
    test eax, eax
    jz 4f
    mov rax, [r12 + rbx*8]
    mov rcx, [rsp]
    mov [r12 + rcx*8], rax
    mov [rsp], rbx
    jmp 1b
4:  mov rcx, [rsp]
    mov rax, [rsp + 16]
    mov [r12 + rcx*8], rax
    EPILOGUE

.section .rodata
.Lhome: .asciz "HOME"
.Lclaude_projects: .asciz "/.claude/projects/"
.Lcodex_sessions: .asciz ".codex/sessions"
.Lcodex_worktrees: .ascii "/.codex/worktrees/"
.Ljsonl: .ascii ".jsonl"
.Lclaude: .asciz "claude"
.Lcodex: .asciz "codex"
.Lpayload: .asciz "payload"
.Lcwd: .asciz "cwd"
.Lcache_prefix: .asciz "/agents-index-v5-"
.Lhistory_prefix: .asciz "/agents-worktrees-v1-"
.Lhistory_dir_prefix: .asciz "/agents-worktrees-v2-"
.Lhistory_suffix: .asciz ".root"
.Lmember_suffix: .asciz ".member"
.Lsession_id: .asciz "session_id"
.Lid: .asciz "id"
.Lclaude_session_id: .asciz "sessionId"
.Lclaude_tree_slug: .asciz "--claude-worktrees-"
.Lclaude_tree_path: .asciz "/.claude/worktrees/"
.Ldot: .asciz "."
.Ldotdot: .asciz ".."

.text
# claude_cwd(s, old size, new size) -> owned cwd, edx read success, ecx verified append.
# Select a cwd whose encoded path matches the transcript's directory. Attachments
# can name the main checkout before a later record names the actual worktree.
claude_cwd:
    PROLOGUE 64
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov dword ptr [rsp + 16], 0
    mov [rsp + 24], rdi
    mov rdi, [rdi + AS_path]
    call strlen
    mov rsi, rax
    mov rax, [rsp + 24]
    mov rdi, [rax + AS_path]
    call path_dirlen
    mov rsi, rax
    mov rax, [rsp + 24]
    mov rdi, [rax + AS_path]
    call mem_dup
    mov [rsp + 32], rax
    mov rax, [rsp + 24]
    mov rdi, [rax + AS_path]
    mov esi, 262144
    call agent_read_head
    test rax, rax
    jz .Lcwd_error
    mov r12, rax
    mov r13, rdx
    mov r14, [rsp + 24]
    mov rsi, [rsp]
    test rsi, rsi
    jz 6f
    cmp rsi, [rsp + 8]
    jae 6f
    mov eax, 262144
    cmp rsi, rax
    cmova rsi, rax
    cmp rsi, r13
    ja 6f
    mov rdi, r12
    call hash_line
    cmp rax, [r14 + AS_prefix_hash]
    jne 6f
    mov dword ptr [rsp + 16], 1
6:  mov rdi, r12
    mov rsi, r13
    call hash_line
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], -1  # head first, then bounded streaming if needed
    mov dword ptr [rsp + 56], 0
    xor r15d, r15d
.Lcwd_buffer:
    xor ebx, ebx
    cmp dword ptr [rsp + 56], 0
    je .Lcwd_line
.Lcwd_skip:
    cmp rbx, r13
    jae .Lcwd_advance
    mov al, [r12 + rbx]
    inc rbx
    cmp al, 10
    jne .Lcwd_skip
    mov dword ptr [rsp + 56], 0
.Lcwd_line:
    mov r14, rbx
1:  cmp r14, r13
    jae .Lcwd_partial
    cmp byte ptr [r12 + r14], 10
    je 2f
    inc r14
    jmp 1b
2:  lea rdi, [r12 + rbx]
    mov rsi, r14
    sub rsi, rbx
    mov rdx, [rsp + 32]
    call claude_cwd_line
    test rax, rax
    jnz .Lcwd_found
    lea rbx, [r14 + 1]
    jmp .Lcwd_line
.Lcwd_partial:
    cmp qword ptr [rsp + 48], -1
    jne 3f
    cmp r13, 262144
    je .Lcwd_advance
    jmp 4f
3:  cmp r13, 1 << 20
    je .Lcwd_advance
4:  lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    mov rdx, [rsp + 32]
    call claude_cwd_line
    test rax, rax
    jnz .Lcwd_found
    jmp .Lcwd_done
.Lcwd_advance:
    cmp qword ptr [rsp + 48], -1
    jne 5f
    mov qword ptr [rsp + 48], 0
    jmp .Lcwd_read
5:  cmp r13, 1 << 20
    jb .Lcwd_done
    test rbx, rbx
    jnz 7f
    mov rbx, r13
    mov dword ptr [rsp + 56], 1 # a record over 1 MiB is skipped without allocating it
7:  add [rsp + 48], rbx
.Lcwd_read:
    mov rdi, r12
    call mem_free
    mov rax, [rsp + 24]
    mov rdi, [rax + AS_path]
    mov esi, 1 << 20
    mov rdx, [rsp + 48]
    call agent_read_window
    test rax, rax
    jz .Lcwd_error
    mov r12, rax
    mov r13, rdx
    jmp .Lcwd_buffer
.Lcwd_found:
    mov r15, rax
.Lcwd_done:
    mov rdi, r12
    call mem_free
    mov rdi, [rsp + 32]
    call mem_free
    mov rax, [rsp + 24]
    mov rdx, [rsp + 40]
    mov [rax + AS_prefix_hash], rdx
    mov rax, r15
    mov edx, 1
    mov ecx, [rsp + 16]
    EPILOGUE
.Lcwd_error:
    mov rdi, [rsp + 32]
    call mem_free
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

# claude_cwd_line(JSON line, bytes, directory) -> exact owned cwd or 0.
claude_cwd_line:
    PROLOGUE AW_SIZE
    mov r12, rdx
    call json_parse
    mov rdi, rax
    lea rsi, [rip + .Lcwd]
    call json_get
    mov rdi, rax
    call json_str
    test rax, rax
    jz 9f
    test rdx, rdx
    jz 9f
    cmp rdx, 4096
    ja 9f
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov rbx, rax
    mov [rsp + AW_path], rax
    mov qword ptr [rsp + AW_claude], 0
    mov qword ptr [rsp + AW_name], 0
    mov rdi, rsp
    call claude_root
    mov rdi, [rsp + AW_claude]
    test rdi, rdi
    jz 8f
    mov rsi, r12
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    mov r13d, eax
    mov rdi, [rsp + AW_claude]
    call mem_free
    test r13d, r13d
    jz 8f
    mov rax, rbx
    EPILOGUE
8:  mov rdi, rbx
    call mem_free
9:  xor eax, eax
    EPILOGUE
