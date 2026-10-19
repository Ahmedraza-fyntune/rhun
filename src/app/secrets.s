# Secrets for extensions (parity 4h): values kept per key for an extension with [needs] secrets =
# yes. The system's store by default: the macOS Keychain (src/mac/keychain.s), the Windows
# Credential Manager (src/win/cred.s), the Linux Secret Service over D-Bus
# (src/plat/secretservice.s). Without one, or when the user chooses, memory (until rhun quits); a
# file only the user can read when the user chooses ([extensions] secrets = system|memory|file).
#
# Requests queue in order and are served one at a time: a store may answer later (an unlock
# dialog), and rhun keeps reading the extension's other requests meanwhile. At most
# SECRET_OUTSTANDING per extension. The page shows the keys (never the values) with Forget; a
# removed extension's secrets go with it. Identity in every store: service "rhun extension
# OWNER/NAME", account KEY.
.include "rhun.inc"

# an entry of the memory store, and of a file being changed
.equ MS_ext, 0
.equ MS_key, 8                  # owned cstr
.equ MS_val, 16                 # owned bytes
.equ MS_len, 24
.equ MS_SIZE, 32

.bss
.p2align 3
sec_head: .quad 0               # the queue of SR records
sec_tail: .quad 0
sec_busy: .long 0               # the head is with an asynchronous store
sec_fallback: .long 0           # Linux: no Secret Service answered; memory stands in
sec_env_read: .long 0
.p2align 3
sec_mem: .zero VEC_SIZE         # the memory store
sec_file: .zero VEC_SIZE        # a file's entries while it is changed
sec_path: .zero SB_SIZE
sec_tmp: .zero SB_SIZE
sec_line: .zero SB_SIZE

.data
sec_override: .long -1          # secret-backend (tests) or RHUN_SECRETS, else -1
sec_pipe: .long -1, -1          # macOS: the keychain's worker reports here

.text

# ---------------- the queue ----------------

# secrets_queue(ext, id, op, key cstr or 0, value ptr, value len) -> rax 0, or -16 (busy) when
# the extension has SECRET_OUTSTANDING requests already
FN secrets_queue
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], edx
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    # how many it has queued
    xor ecx, ecx
    mov rax, [rip + sec_head]
1:  test rax, rax
    jz 2f
    cmp [rax + SECR_ext], rbx
    jne 11f
    inc ecx
11: mov rax, [rax + SECR_next]
    jmp 1b
2:  cmp ecx, SECRET_OUTSTANDING
    jb 3f
    mov rax, -16
    EPILOGUE
3:  mov edi, SECR_SIZE - SECRET_BUF
    add edi, SECRET_BUF
    call mem_alloc
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, SECR_SIZE - SECRET_BUF
    call memset
    mov eax, [rsp + 8]
    mov [r15 + SECR_op], eax
    mov dword ptr [r15 + SECR_fd], -1
    mov [r15 + SECR_ext], rbx
    mov rax, [rsp]
    mov [r15 + SECR_id], rax
    mov rdi, rbx
    call extres_row
    test rax, rax
    jz 4f
    mov eax, [rax + EL_starts]
    mov [r15 + SECR_gen], rax
4:  mov rdi, rbx
    call service_name
    mov [r15 + SECR_service], rax
    test r12, r12
    jz 5f
    mov rdi, r12
    call dup_cstr
    mov [r15 + SECR_key], rax
5:  cmp dword ptr [rsp + 8], SECO_SET
    jne 6f
    mov rdi, r13
    mov rsi, r14
    call mem_dup
    mov [r15 + SECR_val], rax
    mov [r15 + SECR_len], r14
6:  mov rax, [rip + sec_tail]
    test rax, rax
    jz 7f
    mov [rax + SECR_next], r15
    jmp 8f
7:  mov [rip + sec_head], r15
8:  mov [rip + sec_tail], r15
    call secrets_pump
    xor eax, eax
    EPILOGUE

# secrets_pending(ext) -> eax 1 while a request of the extension is queued (it is not idle)
FN secrets_pending
    mov rax, [rip + sec_head]
1:  test rax, rax
    jz 8f
    cmp [rax + SECR_ext], rdi
    je 9f
    mov rax, [rax + SECR_next]
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# service_name(ext) -> owned cstr: "rhun extension OWNER/NAME"; in a --extensions session
# RHUN_SECRETS_SERVICE replaces "rhun extension" (tests use a store of their own)
service_name:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + sec_tmp]
    call sb_clear
    lea rsi, [rip + .Lservice]
    cmp qword ptr [rip + g_ext_dir], 0
    je 1f
    lea rdi, [rip + .Lenv_service]
    call getenv
    lea rsi, [rip + .Lservice]
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rsi, rax
1:  lea rdi, [rip + sec_tmp]
    call sb_push_cstr
    lea rdi, [rip + sec_tmp]
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    call ext_full_name
    lea rdi, [rip + sec_tmp]
    mov rsi, rax
    call sb_push_cstr
    mov rdi, [rip + sec_tmp + SB_ptr]
    mov rsi, [rip + sec_tmp + SB_len]
    call mem_dup
    EPILOGUE

# secrets_backend() -> eax SB_* in use: secret-backend or RHUN_SECRETS (tests, --extensions
# sessions), else [extensions] secrets; on Linux memory once no Secret Service answered
FN secrets_backend
    PROLOGUE
    cmp dword ptr [rip + sec_env_read], 0
    jne 2f
    mov dword ptr [rip + sec_env_read], 1
    cmp qword ptr [rip + g_ext_dir], 0
    je 2f
    lea rdi, [rip + .Lenv_secrets]
    call getenv
    test rax, rax
    jz 2f
    mov rdi, rax
    call backend_named
    test eax, eax
    js 2f
    mov [rip + sec_override], eax
2:  mov eax, [rip + sec_override]
    test eax, eax
    jns 3f
    mov eax, [rip + cfg_secrets]
3:  cmp eax, SECB_SYSTEM
    jne 9f
    cmp dword ptr [rip + sec_fallback], 0
    je 9f
    mov eax, SECB_MEMORY
9:  EPILOGUE

# backend_named(cstr) -> eax SB_*, or -1
backend_named:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  lea rax, [rip + backend_names]
    mov rsi, [rax + r12*8]
    test rsi, rsi
    jz 8f
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jnz 9f
    inc r12d
    jmp 1b
8:  mov eax, -1
    EPILOGUE
9:  mov eax, r12d
    EPILOGUE

# secrets_pump(): serve the queue's head, and the next, until one waits for its store
FN secrets_pump
    PROLOGUE
1:  mov rbx, [rip + sec_head]
    test rbx, rbx
    jz 9f
    cmp dword ptr [rip + sec_busy], 0
    jne 9f
    call secrets_backend
    cmp eax, SECB_MEMORY
    je .Lsp_memory
    cmp eax, SECB_FILE
    je .Lsp_file
.ifdef WINDOWS
    mov rdi, rbx
    call win_cred_op
    jmp .Lsp_done
.endif
.ifdef MACOS
    call sec_pipe_open
    test eax, eax
    jz .Lsp_nostore
    mov eax, [rip + sec_pipe + 4]
    mov [rbx + SECR_fd], eax
    mov dword ptr [rip + sec_busy], 1
    mov rdi, rbx
    call mac_secret_start
    jmp 9f
.endif
.ifndef WINDOWS
.ifndef MACOS
    mov rdi, rbx
    call ss_start
    test eax, eax
    jnz 2f
    mov dword ptr [rip + sec_busy], 1
    jmp 9f
2:  # no Secret Service: memory stands in for the session, and the user is told
    mov dword ptr [rip + sec_fallback], 1
    mov dword ptr [rip + g_dirty], 1
    jmp .Lsp_memory
.endif
.endif
.Lsp_nostore:
    mov dword ptr [rbx + SECR_status], SECS_NOSTORE
    jmp .Lsp_done
.Lsp_memory:
    lea rdi, [rip + sec_mem]
    mov rsi, rbx
    call ms_op
    call told_memory
    jmp .Lsp_done
.Lsp_file:
    mov rdi, rbx
    call file_op
.Lsp_done:
    call complete
    jmp 1b
9:  EPILOGUE

# secrets_done(): the asynchronous store answered the head
FN secrets_done
    PROLOGUE
    mov dword ptr [rip + sec_busy], 0
    cmp qword ptr [rip + sec_head], 0
    je 1f
    call complete
1:  call secrets_pump
    EPILOGUE

# told_memory(): rbx a set kept in memory because no keyring runs: the first per extension says
# so ("No keyring is running: Title's sign-in lasts until rhun quits")
told_memory:
    PROLOGUE
    cmp dword ptr [rbx + SECR_op], SECO_SET
    jne 9f
    cmp dword ptr [rbx + SECR_status], SECS_OK
    jne 9f
    cmp dword ptr [rip + sec_fallback], 0
    je 9f
    mov rdi, [rbx + SECR_ext]
    call extres_row
    test rax, rax
    jz 9f
    test dword ptr [rax + EL_flags], ELF_SECRETS_TOLD
    jnz 9f
    or dword ptr [rax + EL_flags], ELF_SECRETS_TOLD
    lea rdi, [rip + sec_line]
    call sb_clear
    lea rdi, [rip + sec_line]
    lea rsi, [rip + .Lt_no_keyring]
    call sb_push_cstr
    mov rdi, [rbx + SECR_ext]
    call ext_title
    lea rdi, [rip + sec_line]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + sec_line]
    lea rsi, [rip + .Lt_until_quit]
    call sb_push_cstr
    lea rdi, [rip + sec_line]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + sec_line + SB_ptr]
    call app_toast
9:  EPILOGUE

# complete(): the head is answered: the reply (when the extension still runs the same session),
# the page's list of keys, and the record goes
complete:
    PROLOGUE
    mov rbx, [rip + sec_head]
    mov rax, [rbx + SECR_next]
    mov [rip + sec_head], rax
    test rax, rax
    jnz 1f
    mov qword ptr [rip + sec_tail], 0
1:  mov r12, [rbx + SECR_ext]
    mov rdi, r12
    call extres_row
    mov r13, rax
    test r13, r13
    jz 5f
    # the reply
    cmp qword ptr [rbx + SECR_id], 0
    je 3f
    cmp dword ptr [r12 + EXT_status], ES_RUNNING
    jne 3f
    mov eax, [r13 + EL_starts]
    cmp rax, [rbx + SECR_gen]
    jne 3f
    mov rdi, rbx
    call extproto_secret_reply
3:  # what the page knows of its keys
    cmp dword ptr [rbx + SECR_status], SECS_OK
    jne 5f
    mov eax, [rbx + SECR_op]
    cmp eax, SECO_KEYS
    je 31f
    cmp eax, SECO_GET
    je 5f
    # a set, delete or clear changed them: the page asks again when it shows
    mov rdi, [r13 + EL_skeys]
    call mem_free
    mov qword ptr [r13 + EL_skeys], 0
    and dword ptr [r13 + EL_flags], ~ELF_SKEYS_ASKED
    jmp 4f
31: mov rdi, [r13 + EL_skeys]
    call mem_free
    lea rdi, [rbx + SECR_buf]
    mov rsi, [rbx + SECR_outlen]
    call mem_dup
    mov [r13 + EL_skeys], rax
4:  mov dword ptr [rip + g_dirty], 1
5:  mov rdi, [rbx + SECR_service]
    call mem_free
    mov rdi, [rbx + SECR_key]
    call mem_free
    mov rdi, [rbx + SECR_val]
    call mem_free
    mov rdi, rbx
    call mem_free
    EPILOGUE

# ---------------- memory ----------------

# ms_find(vec, ext, key cstr) -> rax the entry's index, or -1
ms_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 8f
    imul r15, r14, MS_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    cmp [r15 + MS_ext], r12
    jne 1b
    mov rdi, [r15 + MS_key]
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jz 1b
    lea rax, [r14 - 1]
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# ms_remove(vec, index): the entry's bytes go; the last entry takes its place
ms_remove:
    PROLOGUE
    mov rbx, rdi
    imul r12, rsi, MS_SIZE
    add r12, [rbx + VEC_ptr]
    mov rdi, [r12 + MS_key]
    call mem_free
    mov rdi, [r12 + MS_val]
    call mem_free
    mov rax, [rbx + VEC_len]
    dec rax
    mov [rbx + VEC_len], rax
    imul rsi, rax, MS_SIZE
    add rsi, [rbx + VEC_ptr]
    cmp rsi, r12
    je 9f
    mov rdi, r12
    mov edx, MS_SIZE
    call memcpy
9:  EPILOGUE

# ms_op(vec, sr): the request on a list of entries (the memory store, or a file's)
ms_op:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + SECR_ext]
    mov dword ptr [r12 + SECR_status], SECS_OK
    mov qword ptr [r12 + SECR_outlen], 0
    mov eax, [r12 + SECR_op]
    cmp eax, SECO_KEYS
    je .Lmo_keys
    cmp eax, SECO_CLEAR
    je .Lmo_clear
    mov rdi, rbx
    mov rsi, r13
    mov rdx, [r12 + SECR_key]
    call ms_find
    mov r14, rax
    mov eax, [r12 + SECR_op]
    cmp eax, SECO_GET
    je .Lmo_get
    cmp eax, SECO_DELETE
    je .Lmo_delete
    # set: replace the value, or a new entry while it has fewer than SECRET_KEYS_MAX
    test r14, r14
    js 1f
    imul r15, r14, MS_SIZE
    add r15, [rbx + VEC_ptr]
    mov rdi, [r15 + MS_val]
    call mem_free
    jmp 3f
1:  xor ecx, ecx
    xor edx, edx
2:  cmp rdx, [rbx + VEC_len]
    jae 21f
    imul rax, rdx, MS_SIZE
    add rax, [rbx + VEC_ptr]
    inc rdx
    cmp [rax + MS_ext], r13
    jne 2b
    inc ecx
    jmp 2b
21: cmp ecx, SECRET_KEYS_MAX
    jb 22f
    mov dword ptr [r12 + SECR_status], SECS_TOOBIG
    EPILOGUE
22: mov rdi, rbx
    mov esi, MS_SIZE
    call vec_push
    mov r15, rax
    mov [r15 + MS_ext], r13
    mov rdi, [r12 + SECR_key]
    call dup_cstr
    mov [r15 + MS_key], rax
3:  mov rdi, [r12 + SECR_val]
    mov rsi, [r12 + SECR_len]
    call mem_dup
    mov [r15 + MS_val], rax
    mov rax, [r12 + SECR_len]
    mov [r15 + MS_len], rax
    EPILOGUE
.Lmo_get:
    test r14, r14
    jns 1f
    mov dword ptr [r12 + SECR_status], SECS_NONE
    EPILOGUE
1:  imul r15, r14, MS_SIZE
    add r15, [rbx + VEC_ptr]
    mov rdx, [r15 + MS_len]
    mov [r12 + SECR_outlen], rdx
    lea rdi, [r12 + SECR_buf]
    mov rsi, [r15 + MS_val]
    call memcpy
    EPILOGUE
.Lmo_delete:
    test r14, r14
    js 9f
    mov rdi, rbx
    mov rsi, r14
    call ms_remove
9:  EPILOGUE
.Lmo_keys:
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 9b
    imul r15, r14, MS_SIZE
    add r15, [rbx + VEC_ptr]
    inc r14
    cmp [r15 + MS_ext], r13
    jne 1b
    mov rdi, [r15 + MS_key]
    call strlen
    mov rdx, rax
    mov rcx, [r12 + SECR_outlen]
    lea rax, [rcx + rdx + 1]
    cmp rax, SECRET_BUF
    ja 1b
    lea rdi, [r12 + SECR_buf + rcx]
    mov rsi, [r15 + MS_key]
    push rdx
    push rdx
    call memcpy
    pop rdx
    pop rdx
    mov rcx, [r12 + SECR_outlen]
    add rcx, rdx
    mov byte ptr [r12 + SECR_buf + rcx], 10
    inc rcx
    mov [r12 + SECR_outlen], rcx
    jmp 1b
.Lmo_clear:
    xor r14d, r14d
1:  cmp r14, [rbx + VEC_len]
    jae 9b
    imul r15, r14, MS_SIZE
    add r15, [rbx + VEC_ptr]
    cmp [r15 + MS_ext], r13
    je 2f
    inc r14
    jmp 1b
2:  mov rdi, rbx
    mov rsi, r14
    call ms_remove
    jmp 1b

# ---------------- a file only you can read ----------------

# file_path(ext) -> sec_path: $XDG_STATE_HOME/rhun/secrets/OWNER--NAME, its folder made with mode
# 0700; 0 without a state folder
file_path:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + sec_path]
    call session_state_dir
    test eax, eax
    jz 9f
    lea rdi, [rip + sec_path]
    lea rsi, [rip + .Lsecrets_dir]
    call sb_push_cstr
    mov rdi, [rip + sec_path + SB_ptr]
    call mkdir_p
    mov rdi, [rip + sec_path + SB_ptr]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    SYS SYS_open
    test rax, rax
    js 1f
    mov r12d, eax
    mov edi, eax
    mov esi, 0700
    SYS SYS_fchmod
    mov edi, r12d
    SYS SYS_close
1:  lea rdi, [rip + sec_path]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + sec_path]
    mov rsi, [rbx + EXT_owner]
    call sb_push_cstr
    lea rdi, [rip + sec_path]
    lea rsi, [rip + .Ldashdash]
    call sb_push_cstr
    lea rdi, [rip + sec_path]
    mov rsi, [rbx + EXT_name]
    call sb_push_cstr
    lea rdi, [rip + sec_path]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + sec_path + SB_len]
    mov eax, 1
9:  EPILOGUE

# file_op(sr): the file's entries read (records "KEY LEN" LF, the value, LF), the request served
# on them, and the file written again (a new file renamed over it, mode 0600) when it changed
file_op:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + SECR_ext]
    call file_path
    test eax, eax
    jnz 1f
    mov dword ptr [rbx + SECR_status], SECS_NOSTORE
    EPILOGUE
1:  mov rdi, [rip + sec_path + SB_ptr]
    mov esi, 1 << 20
    call file_read_limited
    mov r12, rax
    mov r13, rdx
    test rax, rax
    jz 4f
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + SECR_ext]
    call file_parse
    mov rdi, r12
    call mem_free
4:  lea rdi, [rip + sec_file]
    mov rsi, rbx
    call ms_op
    mov eax, [rbx + SECR_op]
    cmp eax, SECO_GET
    je 8f
    cmp eax, SECO_KEYS
    je 8f
    cmp dword ptr [rbx + SECR_status], SECS_OK
    jne 8f
    call file_write
    test eax, eax
    jnz 8f
    mov dword ptr [rbx + SECR_status], SECS_NOSTORE
8:  # the entries go
81: cmp qword ptr [rip + sec_file + VEC_len], 0
    je 9f
    lea rdi, [rip + sec_file]
    xor esi, esi
    call ms_remove
    jmp 81b
9:  EPILOGUE

# file_parse(ptr, len, ext): records "KEY LEN" LF, the value, LF, into sec_file; a cut or broken
# record ends the list
file_parse:
    PROLOGUE 16
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov [rsp], rdx
1:  mov rbx, r12
2:  cmp rbx, r13
    jae 9f
    cmp byte ptr [rbx], ' '
    je 3f
    cmp byte ptr [rbx], 10
    je 9f
    inc rbx
    jmp 2b
3:  cmp rbx, r12
    je 9f
    lea rdi, [rbx + 1]
    mov rsi, r13
    sub rsi, rdi
    call parse_u64
    test rdx, rdx
    jz 9f
    mov r14, rax
    lea r15, [rbx + rdx + 1]
    cmp r15, r13
    jae 9f
    cmp byte ptr [r15], 10
    jne 9f
    inc r15
    mov rax, r13
    sub rax, r15
    cmp r14, rax
    ja 9f
    cmp r14, SECRET_VALUE_MAX
    ja 9f
    lea rdi, [rip + sec_file]
    mov esi, MS_SIZE
    call vec_push
    mov [rsp + 8], rax
    mov rcx, [rsp]
    mov [rax + MS_ext], rcx
    mov [rax + MS_len], r14
    mov rdi, r12
    mov rsi, rbx
    sub rsi, r12
    call mem_dup
    mov rcx, [rsp + 8]
    mov [rcx + MS_key], rax
    mov rdi, r15
    mov rsi, r14
    call mem_dup
    mov rcx, [rsp + 8]
    mov [rcx + MS_val], rax
    lea r12, [r15 + r14 + 1]
    jmp 1b
9:  EPILOGUE

# file_write() -> eax 1 when sec_file's entries are in the file at sec_path (none: no file)
file_write:
    PROLOGUE
    cmp qword ptr [rip + sec_file + VEC_len], 0
    jne 1f
    mov rdi, [rip + sec_path + SB_ptr]
    SYS SYS_unlink
    mov eax, 1
    EPILOGUE
1:  lea rdi, [rip + sec_line]
    call sb_clear
    xor r12d, r12d
2:  cmp r12, [rip + sec_file + VEC_len]
    jae 3f
    imul rbx, r12, MS_SIZE
    add rbx, [rip + sec_file + VEC_ptr]
    inc r12
    lea rdi, [rip + sec_line]
    mov rsi, [rbx + MS_key]
    call sb_push_cstr
    lea rdi, [rip + sec_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + sec_line]
    mov rsi, [rbx + MS_len]
    call sb_push_u64
    lea rdi, [rip + sec_line]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + sec_line]
    mov rsi, [rbx + MS_val]
    mov rdx, [rbx + MS_len]
    call sb_push
    lea rdi, [rip + sec_line]
    mov esi, 10
    call sb_push_byte
    jmp 2b
3:  # PATH.new, 0600, renamed over PATH
    lea rdi, [rip + sec_tmp]
    call sb_clear
    lea rdi, [rip + sec_tmp]
    mov rsi, [rip + sec_path + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + sec_tmp]
    lea rsi, [rip + .Lnew]
    call sb_push_cstr
    lea rdi, [rip + sec_tmp]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + sec_tmp + SB_ptr]
    SYS SYS_unlink
    mov rdi, [rip + sec_tmp + SB_ptr]
    mov esi, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    test rax, rax
    js 8f
    mov ebx, eax
    mov edi, eax
    mov rsi, [rip + sec_line + SB_ptr]
    mov rdx, [rip + sec_line + SB_len]
    call write_all
    mov r12, rax
    mov edi, ebx
    SYS SYS_close
    test r12, r12
    jnz 8f
    mov rdi, [rip + sec_tmp + SB_ptr]
    mov rsi, [rip + sec_path + SB_ptr]
    SYS SYS_rename
    test rax, rax
    js 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- macOS: the keychain's worker reports through a pipe ----------------
.ifdef MACOS
# sec_pipe_open() -> eax 1 once the pipe exists and the loop watches its read end
sec_pipe_open:
    PROLOGUE
    cmp dword ptr [rip + sec_pipe], 0
    jge 9f
    lea rdi, [rip + sec_pipe]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js 8f
    mov edi, [rip + sec_pipe]
    mov esi, POLLIN
    lea rdx, [rip + sec_pipe_readable]
    xor ecx, ecx
    call watch_add
9:  mov eax, 1
    EPILOGUE
8:  mov dword ptr [rip + sec_pipe], -1
    xor eax, eax
    EPILOGUE

# sec_pipe_readable(fd, revents, ctx): the worker finished the head
sec_pipe_readable:
    PROLOGUE 16
    mov edi, [rip + sec_pipe]
    lea rsi, [rsp]
    mov edx, 1
    SYS SYS_read
    test rax, rax
    jle 9f
    call secrets_done
9:  EPILOGUE
.endif

# ---------------- the page, removals, the tests ----------------

# secrets_keys_refresh(ext): the store asked for its keys again (the page shows them)
FN secrets_keys_refresh
    PROLOGUE
    mov rbx, rdi
    call extres_row
    test rax, rax
    jz 9f
    or dword ptr [rax + EL_flags], ELF_SKEYS_ASKED
    mov rdi, rbx
    xor esi, esi
    mov edx, SECO_KEYS
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    call secrets_queue
9:  EPILOGUE

# secrets_forget(ext, key cstr or 0): one key, or every key (Forget on the page, a removal)
FN secrets_forget
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edx, SECO_DELETE
    test r12, r12
    jnz 1f
    mov edx, SECO_CLEAR
1:  mov rdi, rbx
    xor esi, esi
    mov rcx, r12
    xor r8d, r8d
    xor r9d, r9d
    call secrets_queue
    EPILOGUE

# secrets_ext_removed(ext): an extension with secrets was removed: they go with it
FN secrets_ext_removed
    test dword ptr [rdi + EXT_needs], NEEDS_SECRETS
    jz 9f
    xor esi, esi
    jmp secrets_forget
9:  ret

# secrets_where() -> rax the words for where secrets are kept now, for the page
FN secrets_where
    push rbx
    call secrets_backend
    lea rcx, [rip + where_names]
    mov rax, [rcx + rax*8]
    cmp dword ptr [rip + sec_fallback], 0
    je 9f
    lea rax, [rip + .Lw_fallback]
9:  pop rbx
    ret

# c_secret_backend(out, args, len): secret-backend system|memory|file for this session
FN c_secret_backend
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov rbx, rax
    mov rdi, rax
    call backend_named
    mov r12d, eax
    mov rdi, rbx
    call mem_free
    test r12d, r12d
    js 8f
    mov [rip + sec_override], r12d
    mov dword ptr [rip + sec_env_read], 1
    xor eax, eax
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# c_print_secrets(out, args, len): "backend=B keys=a,b" for OWNER/NAME, as last read
FN c_print_secrets
    PROLOGUE
    mov r12, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + .Lp_backend]
    call sb_push_cstr
    call secrets_backend
    cmp dword ptr [rip + sec_fallback], 0
    je 1f
    mov eax, 3
1:  lea rcx, [rip + print_names]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Lp_keys]
    call sb_push_cstr
    mov rdi, rbx
    call extres_row
    mov r13, [rax + EL_skeys]
    test r13, r13
    jnz 2f
    mov rdi, r12
    mov esi, '?'
    call sb_push_byte
    jmp 7f
2:  xor r14d, r14d                # keys printed
3:  movzx eax, byte ptr [r13]
    test eax, eax
    jz 7f
    inc r13
    cmp eax, 10
    jne 4f
    cmp byte ptr [r13], 0
    je 7f
    mov eax, ','
4:  mov rdi, r12
    mov esi, eax
    call sb_push_byte
    jmp 3b
7:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    xor eax, eax
    EPILOGUE
8:  mov rdi, r12
    lea rsi, [rip + .Lno_ext]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# c_secrets_refresh(out, args, len): secrets-refresh OWNER/NAME asks the store for its keys
FN c_secrets_refresh
    PROLOGUE
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 9f
    mov rdi, rax
    call secrets_keys_refresh
9:  xor eax, eax
    EPILOGUE

# c_secret_forget(out, args, len): secret-forget OWNER/NAME [KEY], as the page's Forget does
FN c_secret_forget
    PROLOGUE 16
    mov rbx, rsi
    mov r12, rdx
    mov rdi, rbx
    mov rsi, r12
    call next_word
    add rbx, rcx
    sub r12, rcx
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call trim
    xor r14d, r14d
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r14, rax
1:  mov rdi, r13
    mov rsi, r14
    call secrets_forget
    mov rdi, r14
    call mem_free
9:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
backend_names: .quad .Lb_system, .Lb_memory, .Lb_file, 0
print_names: .quad .Lb_system, .Lb_memory, .Lb_file, .Lb_fallback
where_names: .quad .Lw_system, .Lw_memory, .Lw_file
.Lb_system: .asciz "system"
.Lb_memory: .asciz "memory"
.Lb_file: .asciz "file"
.Lb_fallback: .asciz "memory-fallback"
.ifdef MACOS
.Lw_system: .asciz "Kept in your macOS Keychain."
.endif
.ifdef WINDOWS
.Lw_system: .asciz "Kept in the Windows Credential Manager."
.endif
.ifndef MACOS
.ifndef WINDOWS
.Lw_system: .asciz "Kept in your keyring (the Secret Service)."
.endif
.endif
.Lw_memory: .asciz "Kept in memory until rhun quits."
.Lw_file: .asciz "Kept in a file only you can read."
.Lw_fallback: .asciz "No keyring is running: kept in memory until rhun quits."
.Lservice: .asciz "rhun extension"
.Lenv_service: .asciz "RHUN_SECRETS_SERVICE"
.Lenv_secrets: .asciz "RHUN_SECRETS"
.Lsecrets_dir: .asciz "/secrets"
.Ldashdash: .asciz "--"
.Lnew: .asciz ".new"
.Lt_no_keyring: .asciz "No keyring is running: "
.Lt_until_quit: .asciz "'s sign-in lasts until rhun quits"
.Lp_backend: .asciz "backend="
.Lp_keys: .asciz " keys="
.Lno_ext: .asciz "no such extension\n"
