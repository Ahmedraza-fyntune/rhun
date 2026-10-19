# Canonical complete payload identity, streamed from held no-follow directory handles.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extvalidatetree.inc"
.include "app/extprepare.inc"
.text
# Unsigned byte path comparison, prefix-shorter-first, independent of locale.
FN ext_validate_records_compare
evt_compare:
    mov r8, [rdi + VR_path]
    mov r9, [rsi + VR_path]
    mov rdi, [rdi + VR_len]
    mov rsi, [rsi + VR_len]
    xor ecx, ecx
1:  cmp rcx, rdi
    jae 3f
    cmp rcx, rsi
    jae 4f
    movzx eax, byte ptr [r8 + rcx]
    movzx edx, byte ptr [r9 + rcx]
    cmp eax, edx
    jb 5f
    ja 4f
    inc rcx
    jmp 1b
3:  cmp rdi, rsi
    jb 5f
    xor eax, eax
    ret
4:  mov eax, 1
    ret
5:  mov rax, -1
    ret
# Swap two fixed records, no allocation.
evt_swap:
    xor ecx, ecx
1:  mov rax, [rdi + rcx]
    mov rdx, [rsi + rcx]
    mov [rdi + rcx], rdx
    mov [rsi + rcx], rax
    add rcx, 8
    cmp rcx, VR_SIZE
    jb 1b
    ret
# Max-heap sift(records,root,count), logarithmic depth, bounded memory.
evt_sift:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  lea r14, [r12*2 + 1]
    cmp r14, r13
    jae 9f
    lea r15, [r14 + 1]
    cmp r15, r13
    jae 3f
    imul rdi, r14, VR_SIZE
    add rdi, rbx
    imul rsi, r15, VR_SIZE
    add rsi, rbx
    call evt_compare
    test rax, rax
    jns 3f
    mov r14, r15
3:  imul rdi, r12, VR_SIZE
    add rdi, rbx
    imul rsi, r14, VR_SIZE
    add rsi, rbx
    call evt_compare
    test rax, rax
    jns 9f
    imul rdi, r12, VR_SIZE
    add rdi, rbx
    imul rsi, r14, VR_SIZE
    add rsi, rbx
    call evt_swap
    mov r12, r14
    jmp 1b
9:  EPILOGUE

FN ext_validate_records_sort
evt_sort:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rsi
    shr r13, 1
1:  test r13, r13
    jz 2f
    dec r13
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    call evt_sift
    jmp 1b
2:  cmp r12, 1
    jbe 9f
    dec r12
    mov rdi, rbx
    imul rsi, r12, VR_SIZE
    add rsi, rbx
    call evt_swap
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    call evt_sift
    jmp 2b
9:  EPILOGUE

# Hash exactly the initially classified file, then EOF and metadata recheck.
evt_file:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    lea rdi, [rbx + VT_sha]
    call sha256_init
1:  cmp r14, [r13 + VR_size]
    jae 3f
    mov r15, [r13 + VR_size]
    sub r15, r14
    cmp r15, 65536
    jbe 2f
    mov r15d, 65536
2:  mov rdi, r12
    lea rsi, [rbx + VT_buffer]
    mov rdx, r15
    mov rcx, r14
    call ext_root_read
    test rax, rax
    js 8f
    jz .Levtf_changed
    cmp rax, r15
    ja .Levtf_changed
    add r14, rax
    lea rdi, [rbx + VT_sha]
    lea rsi, [rbx + VT_buffer]
    mov rdx, rax
    call sha256_update
    test eax, eax
    jz .Levtf_changed
    jmp 1b
3:  mov rdi, r12
    lea rsi, [rbx + VT_buffer]
    mov edx, 1
    mov rcx, r14
    call ext_root_read
    test rax, rax
    js 8f
    jnz .Levtf_changed
    mov rdi, r12
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js 8f
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Levtf_changed
    mov rax, [rsp + ER_size]
    cmp rax, [r13 + VR_size]
    jne .Levtf_changed
    mov rax, [rsp + ER_exec]
    cmp rax, [r13 + VR_exec]
    jne .Levtf_changed
    lea rdi, [rbx + VT_sha]
    lea rsi, [r13 + VR_hash]
    call sha256_final
    test eax, eax
    jz .Levtf_changed
    xor eax, eax
8:  EPILOGUE
.Levtf_changed:
    mov rax, -EV_CHANGED
    EPILOGUE

# Enumeration callback: collect private records only. Any failure discards the whole tree.
evt_entry:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rbx + VT_count], 8192
    jae .Levte_cap
    cmp qword ptr [rbx + VT_depth], 32
    jae .Levte_cap
    mov r14, [rbx + VT_prefix]
    mov [rsp + 32], r14
    mov r15, r14
    test r14, r14
    jz 1f
    inc r15
1:  add r15, r13
    cmp r15, 4095
    ja .Levte_cap
    mov rax, [rbx + VT_pathbytes]
    add rax, r15
    cmp rax, 8 * 1024 * 1024
    ja .Levte_cap
    mov [rbx + VT_pathbytes], rax
    # Backslashes are not portable managed payload relative path separators.
    xor ecx, ecx
2:  cmp rcx, r13
    jae 3f
    cmp byte ptr [r12 + rcx], 92
    je .Levte_path
    inc rcx
    jmp 2b
3:  mov rdi, [rbx + VT_dir]
    mov rsi, r12
    mov edx, ER_ANY
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Levte_open_error
    mov [rsp + 40], rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Levte_close
    test r14, r14
    jz 4f
    mov byte ptr [rbx + VT_path + r14], '/'
    inc r14
4:  lea rdi, [rbx + VT_path + r14]
    mov rsi, r12
    lea rdx, [r13 + 1]
    call memcpy
    mov rax, [rbx + VT_count]
    imul rax, rax, VR_SIZE
    add rax, [rbx + VT_records]
    mov r12, rax
    mov rax, [rbx + VT_paths]
    add rax, [rbx + VT_pathused]
    mov [r12 + VR_path], rax
    mov [r12 + VR_len], r15
    mov rdi, rax
    lea rsi, [rbx + VT_path]
    lea rdx, [r15 + 1]
    call memcpy
    lea rax, [r15 + 1]
    add [rbx + VT_pathused], rax
    inc qword ptr [rbx + VT_count]
    mov rax, [rsp + ER_kind]
    mov [r12 + VR_kind], rax
    cmp rax, ER_DIR
    je .Levte_directory
    cmp qword ptr [rbx + VT_files], 4096
    jae .Levte_close_cap
    inc qword ptr [rbx + VT_files]
    mov rax, [rsp + ER_size]
    cmp rax, 64 * 1024 * 1024
    ja .Levte_close_cap
    mov [r12 + VR_size], rax
    add rax, [rbx + VT_bytes]
    cmp rax, 128 * 1024 * 1024
    ja .Levte_close_cap
    mov [rbx + VT_bytes], rax
    mov rax, [rsp + ER_exec]
    mov [r12 + VR_exec], rax
    mov rdi, rbx
    mov rsi, [rsp + 40]
    mov rdx, r12
    call evt_file
    jmp .Levte_close
.Levte_directory:
    cmp qword ptr [rbx + VT_dirs], 4096
    jae .Levte_close_cap
    inc qword ptr [rbx + VT_dirs]
    mov rax, [rbx + VT_dir]
    mov [rsp + 48], rax
    mov rax, [rsp + 40]
    mov [rbx + VT_dir], rax
    mov [rbx + VT_prefix], r15
    inc qword ptr [rbx + VT_depth]
    mov rdi, rax
    mov rsi, 8192
    sub rsi, [rbx + VT_count]
    lea rdx, [rip + evt_entry]
    mov rcx, rbx
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    dec qword ptr [rbx + VT_depth]
    mov rdx, [rsp + 48]
    mov [rbx + VT_dir], rdx
    mov rdx, [rsp + 32]
    mov [rbx + VT_prefix], rdx
    jmp .Levte_close
.Levte_close_cap:
    mov rax, -EV_RESOURCE
.Levte_close:
    mov r15, rax
    mov rdi, [rsp + 40]
    call ext_root_close
    test rax, rax
    jns 51f
    cmp qword ptr [rbx + VT_cleanup], 0
    jne 51f
    mov [rbx + VT_cleanup], rax
51: test r15, r15
    jnz 5f
    mov r15, rax
5:  mov rdx, [rsp + 32]
    mov byte ptr [rbx + VT_path + rdx], 0
    mov rax, r15
.Levte_done:
    EPILOGUE
.Levte_open_error:
    cmp qword ptr [rbx + VT_cleanup], 0
    jne .Levte_done
    mov [rbx + VT_cleanup], rdx
    EPILOGUE
.Levte_cap:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Levte_path:
    mov rax, -EV_BAD_PATH
    EPILOGUE

# ext_validate_tree(fresh borrowed root directory, out32). Writes out only on success.
FN ext_validate_tree
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    jmp .Levtt_start
FN ext_validate_tree_bound
    mov r8d, 1
.Levtt_start:
    PROLOGUE 112
    mov [rsp + 96], r8
    mov [rsp + 80], rdx
    mov [rsp + 88], rcx
    cmp rcx, 258
    ja .Levtt_cap
    mov [rsp + 64], rdi
    mov [rsp + 72], rsi
    mov edi, VT_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Levtt_oom
    mov rbx, rax
    mov rax, [rsp + 96]
    mov [rbx + VT_bound], rax
    mov rax, [rsp + 80]
    mov [rbx + VT_sources], rax
    mov rax, [rsp + 88]
    mov [rbx + VT_nsource], rax
    mov edi, 258
    call mem_alloc_try
    test rax, rax
    jz .Levtt_alloc_error
    mov [rbx + VT_seen], rax
    mov edi, 8192 * VR_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Levtt_alloc_error
    mov [rbx + VT_records], rax
    mov edi, 8 * 1024 * 1024 + 8192
    call mem_alloc_try
    test rax, rax
    jz .Levtt_alloc_error
    mov [rbx + VT_paths], rax
    mov rdi, [rsp + 64]
    mov [rbx + VT_dir], rdi
    mov esi, 8192
    lea rdx, [rip + evt_entry]
    mov rcx, rbx
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    test rax, rax
    jnz .Levtt_cleanup
    mov rdi, [rbx + VT_records]
    mov rsi, [rbx + VT_count]
    call evt_sort
    mov rdi, rbx
    call evt_bind_sources
    test rax, rax
    jnz .Levtt_cleanup
    lea rdi, [rbx + VT_sha]
    call sha256_init
    lea rdi, [rbx + VT_sha]
    lea rsi, [rip + evt_domain]
    mov edx, 16
    call sha256_update
    xor r12d, r12d
.Levtt_record:
    cmp r12, [rbx + VT_count]
    jae .Levtt_final
    imul r13, r12, VR_SIZE
    add r13, [rbx + VT_records]
    test r12, r12
    jz 1f
    lea rdi, [r13 - VR_SIZE]
    mov rsi, r13
    call evt_compare
    test rax, rax
    jz .Levtt_changed
1:  mov byte ptr [rsp], 'f'
    cmp qword ptr [r13 + VR_kind], ER_DIR
    jne 2f
    mov byte ptr [rsp], 'd'
2:  mov rax, [r13 + VR_len]
    mov [rsp + 1], eax
    lea rdi, [rbx + VT_sha]
    mov rsi, rsp
    mov edx, 5
    call sha256_update
    test eax, eax
    jz .Levtt_changed
    lea rdi, [rbx + VT_sha]
    mov rsi, [r13 + VR_path]
    mov rdx, [r13 + VR_len]
    call sha256_update
    test eax, eax
    jz .Levtt_changed
    cmp qword ptr [r13 + VR_kind], ER_DIR
    je 3f
    mov rax, [r13 + VR_size]
    mov [rsp], rax
    mov rax, [r13 + VR_exec]
    mov [rsp + 8], eax
    lea rdi, [rsp + 12]
    lea rsi, [r13 + VR_hash]
    mov edx, 32
    call memcpy
    lea rdi, [rbx + VT_sha]
    mov rsi, rsp
    mov edx, 44
    call sha256_update
    test eax, eax
    jz .Levtt_changed
3:  inc r12
    jmp .Levtt_record
.Levtt_final:
    lea rdi, [rbx + VT_sha]
    mov rsi, rsp
    call sha256_final
    test eax, eax
    jz .Levtt_changed
    mov rdi, [rsp + 72]
    mov rsi, rsp
    mov edx, 32
    call memcpy
    xor eax, eax
    jmp .Levtt_cleanup
.Levtt_changed:
    mov rax, -EV_CHANGED
    jmp .Levtt_cleanup
.Levtt_alloc_error:
    mov rax, -12
.Levtt_cleanup:
    mov r15, rax
    mov rdi, [rbx + VT_seen]
    call mem_free
    mov rdi, [rbx + VT_paths]
    call mem_free
    mov rdi, [rbx + VT_records]
    call mem_free
    mov r12, [rbx + VT_cleanup]
    mov rdi, rbx
    call mem_free
    mov rax, r15
    mov rdx, r12
    EPILOGUE
.Levtt_cap:
    mov rax, -EV_RESOURCE
    xor edx, edx
    EPILOGUE
.Levtt_oom:
    mov rax, -12
    xor edx, edx
    EPILOGUE
# Every prepared source must appear with exact spelling/content/exec in the full tree.
# Every direct native asset file must have been privately parsed before acceptance.
evt_bind_sources:
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rbx + VT_bound], 0
    je .Levtbs_ok
    xor r12d, r12d
1:  cmp r12, [rbx + VT_count]
    jae .Levtbs_missing
    imul r13, r12, VR_SIZE
    add r13, [rbx + VT_records]
    xor r14d, r14d
2:  cmp r14, [rbx + VT_nsource]
    jae .Levtbs_extra
    imul r15, r14, SR_SIZE
    add r15, [rbx + VT_sources]
    mov rdi, r13
    mov rsi, r15
    call evt_compare
    test rax, rax
    jz .Levtbs_match
    inc r14
    jmp 2b
.Levtbs_match:
    cmp qword ptr [r13 + VR_kind], ER_FILE
    jne .Levtbs_changed
    mov rax, [r15 + SR_size]
    cmp [r13 + VR_size], rax
    jne .Levtbs_changed
    mov rax, [r15 + SR_exec]
    cmp [r13 + VR_exec], rax
    jne .Levtbs_changed
    lea rdi, [r13 + VR_hash]
    lea rsi, [r15 + SR_hash]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Levtbs_changed
    mov rdi, r13
    call evt_asset_role
    test rax, rax
    jz .Levtbs_mark
    test [r15 + SR_roles], rax
    jz .Levtbs_changed
.Levtbs_mark:
    mov rax, [rbx + VT_seen]
    mov byte ptr [rax + r14], 1
    jmp .Levtbs_next
.Levtbs_extra:
    mov rdi, r13
    call evt_asset_role
    test rax, rax
    jnz .Levtbs_changed
.Levtbs_next:
    inc r12
    jmp 1b
.Levtbs_missing:
    xor r12d, r12d
    mov rax, [rbx + VT_seen]
6:  cmp r12, [rbx + VT_nsource]
    jae .Levtbs_ok
    cmp byte ptr [rax + r12], 1
    jne .Levtbs_changed
    inc r12
    jmp 6b
.Levtbs_ok:
    xor eax, eax
    EPILOGUE
.Levtbs_changed:
    mov rax, -EV_CHANGED
    EPILOGUE
# Direct regular contributions require their parser role even when also a launch source.
evt_asset_role:
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + VR_kind], ER_FILE
    jne .Levtar_none
    mov r12, [rbx + VR_path]
    mov r13, [rbx + VR_len]
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + evt_syntax_prefix]
    mov ecx, 7
    call evt_asset_prefix
    test eax, eax
    jz 1f
    lea r14, [rip + evt_syn_suffix]
    mov r15d, 4
    jmp 2f
1:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + evt_themes_prefix]
    mov ecx, 7
    call evt_asset_prefix
    test eax, eax
    jz .Levtar_none
    lea r14, [rip + evt_theme_suffix]
    mov r15d, 6
2:  cmp r13, r15
    jbe .Levtar_none
    lea rdi, [r12 + r13]
    sub rdi, r15
    mov rsi, r14
    mov rdx, r15
    call memeq
    test eax, eax
    jz .Levtar_none
    mov ecx, 7
3:  cmp rcx, r13
    jae 4f
    cmp byte ptr [r12 + rcx], '/'
    je .Levtar_none
    inc rcx
    jmp 3b
4:  mov eax, SR_GRAMMAR
    cmp r15, 4
    je 5f
    mov eax, SR_THEME
5:  EPILOGUE
.Levtar_none:
    xor eax, eax
    EPILOGUE

# Asset directory aliases cannot introduce unprepared contributions on case-insensitive hosts.
evt_asset_prefix:
.ifdef MACOS
    jmp .Levtap_fold
.else
.ifdef WINDOWS
    jmp .Levtap_fold
.else
    jmp str_starts
.endif
.endif
.Levtap_fold:
    cmp rsi, rcx
    jb 8f
    xor r8d, r8d
1:  cmp r8, rcx
    jae 9f
    movzx eax, byte ptr [rdi + r8]
    cmp eax, 'A'
    jb 2f
    cmp eax, 'Z'
    ja 2f
    or eax, 32
2:  cmp al, [rdx + r8]
    jne 8f
    inc r8
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret
.section .rodata
evt_domain: .asciz "rhun-package-v1"

evt_syntax_prefix: .asciz "syntax/"
evt_themes_prefix: .asciz "themes/"
evt_syn_suffix: .asciz ".syn"
evt_theme_suffix: .asciz ".theme"
