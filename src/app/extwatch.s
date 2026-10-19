# Workspace invalidation subscriptions. One bounded staged native tree is shared
# by every extension, with a periodic reconciliation signal for dropped events.
.include "rhun.inc"
.equ EW_MAX_SUBS, 128
.equ EW_MAX_DIRS, 512
.equ EW_MAX_ENTRIES, 32768
.equ EW_DIR_ENTRIES, 4096
.equ EW_DIR_SIZE, 16
.equ EW_SUB_SIZE, 16
.equ EW_INTERVAL, 250
.equ EW_RECONCILE, 2000
.bss
.p2align 3
ew_subs: .zero EW_SUB_SIZE * EW_MAX_SUBS
ew_sub_count: .quad 0
ew_next_handle: .quad 0
ew_root: .quad 0
ew_active: .zero EW_DIR_SIZE * EW_MAX_DIRS
ew_active_len: .quad 0
ew_stage: .zero EW_DIR_SIZE * EW_MAX_DIRS
ew_stage_len: .quad 0
ew_stage_at: .quad 0
ew_entries: .quad 0
ew_scanning: .quad 0
ew_dirty: .quad 0
ew_rescan: .quad 0
ew_rebuild: .quad 0
ew_emit_at: .quad 0
ew_poll_at: .quad 0
ew_path: .zero 4096
.text

# extwatch_add(ext) -> positive handle, or -errno. Same runtime is idempotent.
FN extwatch_add
    PROLOGUE
    mov rbx, rdi
    call ext_has_metadata
    test eax, eax
    jz .Lew_denied
    test dword ptr [rbx + EXT_features], FEAT_WORKSPACE_WATCH
    jz .Lew_denied
    test dword ptr [rbx + EXT_needs], NEEDS_PROJECT_READ | NEEDS_PROJECT_WRITE
    jz .Lew_denied
    mov rdi, [rip + g_project]
    test rdi, rdi
    jz .Lew_no_project
    cmp byte ptr [rdi], 0
    je .Lew_no_project
    call strlen
    cmp rax, 4096
    jae .Lew_no_project
    lea r12, [rip + ew_subs]
    xor r13d, r13d
    xor r14d, r14d
1:  cmp [r12 + r13], rbx
    je 8f
    cmp qword ptr [r12 + r13], 0
    jne 2f
    lea r14, [r12 + r13 + 1]
2:  add r13, EW_SUB_SIZE
    cmp r13, EW_MAX_SUBS * EW_SUB_SIZE
    jb 1b
    test r14, r14
    jz .Lew_full
    dec r14
    cmp qword ptr [rip + ew_next_handle], 0x7fffffff
    jae .Lew_full
    cmp qword ptr [rip + ew_sub_count], 0
    jne 3f
    mov rdi, [rip + g_project]
    call strlen
    mov rdi, [rip + g_project]
    mov rsi, rax
    call mem_dup_try
    test rax, rax
    jz .Lew_memory
    mov [rip + ew_root], rax
    mov qword ptr [rip + ew_rebuild], 1
    mov qword ptr [rip + ew_rescan], 1
    mov qword ptr [rip + ew_dirty], 1
    mov qword ptr [rip + ew_emit_at], 0
    call time_ms
    add rax, EW_RECONCILE
    mov [rip + ew_poll_at], rax
3:  inc qword ptr [rip + ew_sub_count]
    inc qword ptr [rip + ew_next_handle]
    mov rax, [rip + ew_next_handle]
    mov [r14], rbx
    mov [r14 + 8], rax
    EPILOGUE
8:  mov rax, [r12 + r13 + 8]
    EPILOGUE
.Lew_denied: mov rax, -13
    EPILOGUE
.Lew_no_project: mov rax, -2
    EPILOGUE
.Lew_full: mov rax, -28
    EPILOGUE
.Lew_memory: mov rax, -12
    EPILOGUE

# extwatch_remove(ext, handle) -> 1 if owned, 0 otherwise.
FN extwatch_remove
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + ew_subs]
    xor r14d, r14d
1:  cmp [r13 + r14], rbx
    jne 2f
    cmp [r13 + r14 + 8], r12
    jne 2f
    mov qword ptr [r13 + r14], 0
    mov qword ptr [r13 + r14 + 8], 0
    dec qword ptr [rip + ew_sub_count]
    jne 3f
    call .Lew_clear_tree
3:  mov eax, 1
    EPILOGUE
2:  add r14, EW_SUB_SIZE
    cmp r14, EW_MAX_SUBS * EW_SUB_SIZE
    jb 1b
    xor eax, eax
    EPILOGUE

FN extwatch_owner_gone
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + ew_subs]
    xor r13d, r13d
1:  cmp [r12 + r13], rbx
    jne 2f
    mov rsi, [r12 + r13 + 8]
    mov rdi, rbx
    call extwatch_remove
2:  add r13, EW_SUB_SIZE
    cmp r13, EW_MAX_SUBS * EW_SUB_SIZE
    jb 1b
    EPILOGUE

FN extwatch_project_changed
    PROLOGUE
    lea rdi, [rip + ew_subs]
    xor esi, esi
    mov edx, EW_SUB_SIZE * EW_MAX_SUBS
    call memset
    mov qword ptr [rip + ew_sub_count], 0
    call .Lew_clear_tree
    EPILOGUE

# release entries(array, count), consuming their owned path and broker ref.
.Lew_release:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, r12
    jae 9f
    mov r14, r13
    shl r14, 4
    mov rdi, [rbx + r14 + 8]
    call watch_broker_release
    mov rdi, [rbx + r14]
    call mem_free
    mov qword ptr [rbx + r14], 0
    inc r13
    jmp 1b
9:  EPILOGUE
.Lew_clear_tree:
    PROLOGUE
    lea rdi, [rip + ew_active]
    mov rsi, [rip + ew_active_len]
    call .Lew_release
    lea rdi, [rip + ew_stage]
    mov rsi, [rip + ew_stage_len]
    call .Lew_release
    mov rdi, [rip + ew_root]
    call mem_free
    mov qword ptr [rip + ew_root], 0
    mov qword ptr [rip + ew_active_len], 0
    mov qword ptr [rip + ew_stage_len], 0
    mov qword ptr [rip + ew_scanning], 0
    mov qword ptr [rip + ew_rebuild], 0
    mov qword ptr [rip + ew_dirty], 0
    mov qword ptr [rip + ew_rescan], 0
    EPILOGUE

# Queue paths without native I/O. Each tick acquires at most one new watch.
.Lew_enroll:
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rip + ew_stage_len], EW_MAX_DIRS
    jae .Lew_enroll_bad
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup_try
    test rax, rax
    jz .Lew_enroll_bad
    mov rcx, [rip + ew_stage_len]
    shl rcx, 4
    lea rdx, [rip + ew_stage]
    mov [rdx + rcx], rax
    mov qword ptr [rdx + rcx + 8], -1
    inc qword ptr [rip + ew_stage_len]
    xor eax, eax
    EPILOGUE
.Lew_enroll_bad:
    mov rax, -28
    EPILOGUE

# dir_scan callback(parent path, name, length). Only directories need native refs.
.Lew_entry:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    inc qword ptr [rip + ew_entries]
    cmp qword ptr [rip + ew_entries], EW_MAX_ENTRIES
    ja .Lew_entry_bad
    call strlen
    lea rcx, [rax + r13 + 1]
    cmp rcx, 4096
    jae .Lew_entry_bad
    lea rdi, [rip + ew_path]
    mov rsi, rbx
    call cstr_copy
    lea rbx, [rip + ew_path]
    mov rdi, rbx
    call strlen
    mov byte ptr [rbx + rax], '/'
    lea rdi, [rbx + rax + 1]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 0
    mov rdi, rbx
    call extwatch_directory
    test eax, eax
    jz 8f
    mov rdi, rbx
    call .Lew_enroll
    test rax, rax
    js .Lew_entry_bad
8:  xor eax, eax
    EPILOGUE
.Lew_entry_bad:
    mov rax, -28
    EPILOGUE

FN extwatch_native_event
    cmp qword ptr [rip + ew_sub_count], 0
    je 9f
    test esi, 0x4000          # IN_Q_OVERFLOW has wd=-1
    jnz 8f
    cmp edi, 4096
    jae 9f
    PROLOGUE
    mov ebx, esi
    call watch_broker_count
    test eax, eax
    jz 7f
    mov qword ptr [rip + ew_dirty], 1
    test ebx, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_MOVE_SELF | IN_IGNORED
    jz 7f
    mov qword ptr [rip + ew_rebuild], 1
7:  EPILOGUE
8:  mov qword ptr [rip + ew_dirty], 1
    mov qword ptr [rip + ew_rescan], 1
    mov qword ptr [rip + ew_rebuild], 1
9:  ret

FN extwatch_tick
    cmp qword ptr [rip + ew_sub_count], 0
    je 9f
    PROLOGUE
    call time_ms
    mov r15, rax
    cmp rax, [rip + ew_poll_at]
    jb 1f
    add rax, EW_RECONCILE
    mov [rip + ew_poll_at], rax
    mov qword ptr [rip + ew_dirty], 1
    mov qword ptr [rip + ew_rescan], 1
    mov qword ptr [rip + ew_rebuild], 1
1:  cmp qword ptr [rip + ew_scanning], 0
    jne 3f
    cmp qword ptr [rip + ew_rebuild], 0
    je 6f
    mov qword ptr [rip + ew_rebuild], 0
    mov qword ptr [rip + ew_stage_len], 0
    mov qword ptr [rip + ew_stage_at], 0
    mov qword ptr [rip + ew_entries], 0
    mov rdi, [rip + ew_root]
    call .Lew_enroll
    test rax, rax
    js 5f
    mov qword ptr [rip + ew_scanning], 1
3:  mov rax, [rip + ew_stage_at]
    cmp rax, [rip + ew_stage_len]
    jae 4f
    shl rax, 4
    lea rcx, [rip + ew_stage]
    lea rbx, [rcx + rax]
    mov rdi, [rbx]
    call watch_broker_acquire
    test rax, rax
    js 5f
    mov r12, rax
    lea r13, [rip + ew_stage]
    xor r14d, r14d
31: cmp r14, [rip + ew_stage_at]
    jae 32f
    mov rax, r14
    shl rax, 4
    cmp [r13 + rax + 8], r12
    je 33f
    inc r14
    jmp 31b
33: mov rdi, r12
    call watch_broker_release
    inc qword ptr [rip + ew_stage_at]
    jmp 6f
32: mov [rbx + 8], r12
    mov rdi, [rbx]
    mov rcx, rdi
    mov esi, EW_DIR_ENTRIES
    lea rdx, [rip + .Lew_entry]
    call dir_scan_try
    test rax, rax
    js 5f
    inc qword ptr [rip + ew_stage_at]
    jmp 6f
4:  lea rdi, [rip + ew_active]
    mov rsi, [rip + ew_active_len]
    call .Lew_release
    lea rdi, [rip + ew_active]
    lea rsi, [rip + ew_stage]
    mov rdx, [rip + ew_stage_len]
    shl rdx, 4
    call memcpy
    mov rax, [rip + ew_stage_len]
    mov [rip + ew_active_len], rax
    mov qword ptr [rip + ew_stage_len], 0
    mov qword ptr [rip + ew_scanning], 0
    jmp 6f
5:  lea rdi, [rip + ew_stage]
    mov rsi, [rip + ew_stage_len]
    call .Lew_release
    mov qword ptr [rip + ew_stage_len], 0
    mov qword ptr [rip + ew_scanning], 0
    mov qword ptr [rip + ew_dirty], 1
    mov qword ptr [rip + ew_rescan], 1
6:  cmp qword ptr [rip + ew_dirty], 0
    je 8f
    cmp r15, [rip + ew_emit_at]
    jb 8f
    lea rax, [r15 + EW_INTERVAL]
    mov [rip + ew_emit_at], rax
    mov qword ptr [rip + ew_dirty], 0
    mov r14, [rip + ew_rescan]
    mov qword ptr [rip + ew_rescan], 0
    lea r12, [rip + ew_subs]
    xor r13d, r13d
7:  mov rdi, [r12 + r13]
    test rdi, rdi
    jz 71f
    mov rsi, [r12 + r13 + 8]
    mov rdx, r14
    call extproto_watch_event
71: add r13, EW_SUB_SIZE
    cmp r13, EW_MAX_SUBS * EW_SUB_SIZE
    jb 7b
8:  EPILOGUE
9:  ret

# Wake promptly for staged enrollment and at bounded invalidation deadlines.
FN extwatch_timeout
    cmp qword ptr [rip + ew_sub_count], 0
    je 9f
    PROLOGUE
    mov rbx, [rip + ew_poll_at]
    cmp qword ptr [rip + ew_scanning], 0
    jne 8f
    cmp qword ptr [rip + ew_rebuild], 0
    jne 8f
    cmp qword ptr [rip + ew_dirty], 0
    je 1f
    mov rax, [rip + ew_emit_at]
    cmp rax, rbx
    cmovb rbx, rax
1:  call time_ms
    sub rbx, rax
    xor eax, eax
    test rbx, rbx
    cmovg rax, rbx
    EPILOGUE
8:  mov eax, 1
    EPILOGUE
9:  mov rax, -1
    ret

.ifndef WINDOWS
# lstat prevents following directory links when extending the native tree.
FN extwatch_directory
    PROLOGUE 144
    mov rsi, rsp
    mov eax, 6
    XSYS
    test rax, rax
    js 1f
    mov eax, [rsp + 24]
    and eax, 0xf000
    cmp eax, 0x4000
    sete al
    movzx eax, al
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
.endif
