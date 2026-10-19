# workspace access: files, folders, watches and programs of the project, local or on the host of a
# remote window (remote.s). Workspace code calls these instead of sys.s and proc.s; rhun's own
# config, state, themes and installed extensions keep the direct functions. Each one is the local
# function when the window is not remote.
.include "rhun.inc"

.equ VFS_CHUNK, 4194304         # a read or a write of the host's file goes in parts this big
.equ VFS_ONE_WRITE, 33554432    # files up to this size are written in one request

.bss
.p2align 3
vfs_pending: .zero SB_SIZE      # watch events from the host, waiting for vfs_tick: WD MASK LEN name
vfs_line: .zero SB_SIZE         # a request's line
vfs_body: .zero SB_SIZE         # a request's body
vfs_acc: .zero SB_SIZE          # a file read in parts
.globl vfs_statbuf
vfs_statbuf: .zero 144          # the last vfs_stat / vfs_lstat (Linux struct stat on every system)
vfs_tmp: .zero 4200

.text

# ---------------- requests ----------------

# vfs_req_path(verb cstr, path) -> as remote_call: "VERB" with the path as the body
vfs_req_path:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rcx, rax
    mov rdx, r12
    mov rdi, rbx
    push rcx
    push rdx
    call strlen
    mov rsi, rax
    pop rdx
    pop rcx
    mov rdi, rbx
    call remote_call
    add rsp, 8
    pop r12
    pop rbx
    ret

# vfs_line_start(verb cstr): vfs_line = "VERB"
vfs_line_start:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + vfs_line]
    call sb_clear
    lea rdi, [rip + vfs_line]
    mov rsi, rbx
    call sb_push_cstr
    pop rbx
    ret

# vfs_line_num(n): " N" onto vfs_line
vfs_line_num:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + vfs_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + vfs_line]
    mov rsi, rbx
    call sb_push_u64
    pop rbx
    ret

# vfs_line_call(body, len) -> as remote_call with vfs_line
vfs_line_call:
    mov rcx, rsi
    mov rdx, rdi
    mov rdi, [rip + vfs_line + SB_ptr]
    mov rsi, [rip + vfs_line + SB_len]
    jmp remote_call

# ---------------- reading and writing ----------------

# vfs_read_all(path) -> as file_read_all: rax the text (NUL-terminated, mem_alloc'd), rdx its length;
#   rax 0 and rdx -errno on failure
FN vfs_read_all
    xor esi, esi
    jmp vfs_read_all_extra

# vfs_read_all_extra(path, extra) -> as file_read_all_extra
FN vfs_read_all_extra
    cmp dword ptr [rip + g_remote], 0
    je file_read_all_extra
    mov rdx, -1
    jmp vfs_read_remote

# vfs_read_limited(path, max) -> as file_read_limited: EFBIG past max, no allocation of it
FN vfs_read_limited
    cmp dword ptr [rip + g_remote], 0
    je file_read_limited
    mov rdx, rsi
    xor esi, esi
    jmp vfs_read_remote

# vfs_read_remote(path, extra, max): the host's file in VFS_CHUNK parts; a regular file only
vfs_read_remote:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi                # extra
    mov r13, rdx                # max (-1: any)
    mov rdi, rbx
    call vfs_stat
    test rax, rax
    js 8f
    mov eax, [rip + vfs_statbuf + 24]
    and eax, 0xf000
    cmp eax, 0x8000
    je 1f
    mov rax, -21                # EISDIR
    cmp eax, 0x4000
    je 8f
    mov rax, -22                # a FIFO or a device would never end
    jmp 8f
1:  mov rax, [rip + vfs_statbuf + 48]
    cmp rax, r13
    jbe 2f
    mov rax, -27                # EFBIG
    jmp 8f
2:  lea rdi, [rip + vfs_acc]
    call sb_clear
    xor r14d, r14d              # offset
3:  lea rdi, [rip + vfs_line_read]
    call vfs_line_start
    mov rdi, r14
    call vfs_line_num
    mov edi, VFS_CHUNK
    call vfs_line_num
    mov rdi, rbx
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call vfs_line_call
    test rax, rax
    js 8f
    mov r15, [rip + g_remote_reply + SB_len]
    add r14, r15
    cmp r14, r13
    jbe 4f
    mov rax, -27
    jmp 8f
4:  lea rdi, [rip + vfs_acc]
    mov rsi, [rip + g_remote_reply + SB_ptr]
    mov rdx, r15
    call sb_push
    cmp r15, VFS_CHUNK
    je 3b
    # the text with room for extra bytes after it
    mov r14, [rip + vfs_acc + SB_len]
    lea rdi, [r14 + r12 + 1]
    call mem_alloc
    mov r15, rax
    mov rdi, rax
    mov rsi, [rip + vfs_acc + SB_ptr]
    mov rdx, r14
    call memcpy
    mov byte ptr [r15 + r14], 0
    lea rdi, [rip + vfs_acc]
    call sb_free
    mov rax, r15
    mov rdx, r14
    EPILOGUE
8:  mov rdx, rax
    xor eax, eax
    EPILOGUE

# vfs_write_all(path, ptr, len) -> as file_write_all: 0 or -errno. On the host a file replaced keeps
#   its mode (the agent writes a temporary file and renames it over); a big one goes in parts
FN vfs_write_all
    cmp dword ptr [rip + g_remote], 0
    je file_write_all
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rbx
    call strlen
    mov r14, rax                # path length
    cmp r13, VFS_ONE_WRITE
    ja .Lvw_parts
    mov edi, 1
    call vfs_write_req
    EPILOGUE
.Lvw_parts:
    # PATH.rhun-save: created, appended to, then renamed over the file
    mov rdi, rbx
    lea rsi, [rip + .Lsave_suffix]
    call vfs_cat_tmp
    test rax, rax
    jz 8f
    mov r15, rbx                # the real path
    lea rbx, [rip + vfs_tmp]
    mov rdi, rbx
    call strlen
    mov r14, rax
    xor ecx, ecx                # written
    mov [rsp], rcx
1:  mov rax, r13
    sub rax, [rsp]
    jz 3f
    cmp rax, VFS_ONE_WRITE
    jbe 2f
    mov eax, VFS_ONE_WRITE
2:  mov [rsp + 8], rax
    mov edi, 4
    cmp qword ptr [rsp], 0
    jne 21f
    mov edi, 8
21: push r12
    push r13
    add r12, [rsp + 16]
    mov r13, [rsp + 24]
    call vfs_write_req
    pop r13
    pop r12
    test rax, rax
    js 7f
    mov rax, [rsp + 8]
    add [rsp], rax
    jmp 1b
3:  mov rdi, rbx
    mov rsi, r15
    xor edx, edx
    call vfs_rename
    test rax, rax
    js 7f
    xor eax, eax
    EPILOGUE
7:  mov [rsp], rax
    mov rdi, rbx
    call vfs_unlink
    mov rax, [rsp]
    EPILOGUE
8:  mov rax, -36
    EPILOGUE

# vfs_write_req(flags) with rbx path, r14 its length, r12 data, r13 its length -> as remote_call:
#   write FLAGS 644 PLEN LEN + path + data
vfs_write_req:
    push rbx
    push r15
    sub rsp, 8
    mov r15d, edi
    lea rdi, [rip + vfs_line_write]
    call vfs_line_start
    mov edi, r15d
    call vfs_line_num
    mov edi, 644
    call vfs_line_num
    mov rdi, r14
    call vfs_line_num
    lea rdi, [rip + vfs_body]
    call sb_clear
    lea rdi, [rip + vfs_body]
    mov rsi, rbx
    mov rdx, r14
    call sb_push
    lea rdi, [rip + vfs_body]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    mov rdi, [rip + vfs_body + SB_ptr]
    mov rsi, [rip + vfs_body + SB_len]
    call vfs_line_call
    push rax
    push rax
    lea rdi, [rip + vfs_body]
    call sb_free                # a big file's bytes are not kept around
    pop rax
    pop rax
    add rsp, 8
    pop r15
    pop rbx
    ret

# vfs_cat_tmp(a, b) -> vfs_tmp holding a then b, or 0 when too long
vfs_cat_tmp:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    call strlen
    push rax
    mov rdi, r12
    call strlen
    pop rcx
    add rax, rcx
    cmp rax, 4096
    jae 8f
    lea rdi, [rip + vfs_tmp]
    mov rsi, rbx
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    call cstr_copy
    lea rax, [rip + vfs_tmp]
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# ---------------- what is there ----------------

# vfs_stat(path) / vfs_lstat(path) -> 0 or -errno, the Linux struct stat in vfs_statbuf
FN vfs_stat
    mov eax, 4                  # stat
    lea rsi, [rip + .Lv_stat]
    jmp vfs_stat_common
FN vfs_lstat
    mov eax, SYS_lstat
    lea rsi, [rip + .Lv_lstat]
vfs_stat_common:
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    lea rsi, [rip + vfs_statbuf]
    XSYS
    ret
1:  push rbx
    xchg rdi, rsi
    call vfs_req_path
    test rax, rax
    js 9f
    lea rdi, [rip + vfs_statbuf]
    mov rsi, [rip + g_remote_reply + SB_ptr]
    mov rdx, [rip + g_remote_reply + SB_len]
    cmp rdx, 144
    jbe 2f
    mov edx, 144
2:  call memcpy
    xor eax, eax
9:  pop rbx
    ret

# vfs_stamp(path) -> as file_stamp: mtime and size mixed (0 when missing), rdx the size, rcx the mtime
FN vfs_stamp
    cmp dword ptr [rip + g_remote], 0
    je file_stamp
    sub rsp, 8
    call vfs_stat
    add rsp, 8
    test rax, rax
    js 1f
    mov rax, [rip + vfs_statbuf + 88]
    imul rax, rax, 1000000000
    add rax, [rip + vfs_statbuf + 96]
    mov rcx, rax
    mov rdx, [rip + vfs_statbuf + 48]
    rol rdx, 32
    xor rax, rdx
    ror rdx, 32
    ret
1:  xor eax, eax
    xor edx, edx
    xor ecx, ecx
    ret

# vfs_missing(path) -> as file_missing
FN vfs_missing
    cmp dword ptr [rip + g_remote], 0
    je file_missing
    sub rsp, 8
    call vfs_lstat
    add rsp, 8
    xor ecx, ecx
    cmp rax, -2
    sete cl
    cmp rax, -20
    jne 1f
    mov ecx, 1
1:  mov eax, ecx
    ret

# vfs_mtime(path) -> as file_mtime (lstat, seconds)
FN vfs_mtime
    cmp dword ptr [rip + g_remote], 0
    je file_mtime
    sub rsp, 8
    call vfs_lstat
    add rsp, 8
    test rax, rax
    js 1f
    mov rax, [rip + vfs_statbuf + 88]
    ret
1:  xor eax, eax
    ret

# vfs_mtime_ns(path) -> as file_mtime_ns (lstat)
FN vfs_mtime_ns
    cmp dword ptr [rip + g_remote], 0
    je file_mtime_ns
    sub rsp, 8
    call vfs_lstat
    add rsp, 8
    test rax, rax
    js 1f
    mov rax, [rip + vfs_statbuf + 88]
    imul rax, rax, 1000000000
    add rax, [rip + vfs_statbuf + 96]
    ret
1:  xor eax, eax
    ret

# vfs_is_dir(path) -> as file_is_dir (follows links)
FN vfs_is_dir
    cmp dword ptr [rip + g_remote], 0
    je file_is_dir
    sub rsp, 8
    call vfs_stat
    add rsp, 8
    test rax, rax
    js 1f
    mov eax, [rip + vfs_statbuf + 24]
    and eax, 0xf000
    cmp eax, 0x4000
    sete al
    movzx eax, al
    ret
1:  xor eax, eax
    ret

# vfs_type(path) -> as file_type: the S_IFMT bits, 0 when missing (follows links)
FN vfs_type
    cmp dword ptr [rip + g_remote], 0
    je file_type
    sub rsp, 8
    call vfs_stat
    add rsp, 8
    test rax, rax
    js 1f
    mov eax, [rip + vfs_statbuf + 24]
    and eax, 0xf000
    ret
1:  xor eax, eax
    ret

# vfs_id(path) -> as file_id: rax inode, rdx device
FN vfs_id
    cmp dword ptr [rip + g_remote], 0
    je file_id
    sub rsp, 8
    call vfs_stat
    add rsp, 8
    test rax, rax
    js 1f
    mov rax, [rip + vfs_statbuf + 8]
    mov rdx, [rip + vfs_statbuf]
    ret
1:  xor eax, eax
    xor edx, edx
    ret

# vfs_access(path, mode) -> 0 or -errno, access(2)
FN vfs_access
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    SYS SYS_access
    ret
1:  push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    lea rdi, [rip + .Lv_access]
    call vfs_line_start
    mov edi, r12d
    call vfs_line_num
    mov rdi, rbx
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call vfs_line_call
    add rsp, 8
    pop r12
    pop rbx
    ret

# vfs_realpath(path, buf 4096) -> length of the resolved path in buf (NUL-terminated), or -errno
FN vfs_realpath
    cmp dword ptr [rip + g_remote], 0
    jne 1f
.ifdef MACOS
    push rsi
    SYS SYS_realpath
    pop rdi
    test rax, rax
    jz 7f
    jmp strlen
7:  mov rax, -2
    ret
.else
    PROLOGUE
    mov r12, rsi
.ifdef WINDOWS
    mov edx, 4096
    call win_realpath
    test rax, rax
    js 9f
    mov rdi, r12
    call strlen
    EPILOGUE
.endif
    mov esi, O_PATH | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 9f
    mov ebx, eax
    lea rdi, [rip + vfs_tmp]
    lea rsi, [rip + .Lproc_fd]
    call cstr_copy
    mov rdi, rax
    mov esi, ebx
    call fmt_u64
    mov byte ptr [rdi], 0
    lea rdi, [rip + vfs_tmp]
    mov rsi, r12
    mov edx, 4095
    SYS SYS_readlink
    mov r13, rax
    mov edi, ebx
    SYS SYS_close
    mov rax, r13
    test rax, rax
    js 9f
    mov byte ptr [r12 + rax], 0
9:  EPILOGUE
.endif
1:  push rbx
    mov rbx, rsi
    mov rsi, rdi
    lea rdi, [rip + .Lv_realpath]
    call vfs_req_path
    test rax, rax
    js 9f
    mov rdx, [rip + g_remote_reply + SB_len]
    cmp rdx, 4095
    jae 8f
    mov rdi, rbx
    mov rsi, [rip + g_remote_reply + SB_ptr]
    push rdx
    push rdx
    call memcpy
    pop rax
    pop rax
    mov byte ptr [rbx + rax], 0
    jmp 9f
8:  mov rax, -36
9:  pop rbx
    ret

# ---------------- folders ----------------

# vfs_dir_each(path, cb, ctx) -> as dir_each: cb(ctx, name, is_dir) for each entry, folders through
#   links counting as folders
FN vfs_dir_each
    cmp dword ptr [rip + g_remote], 0
    je dir_each
    xor ecx, ecx
    jmp vfs_list

# vfs_dir_each_names(path, cb, ctx) -> as dir_each_names
FN vfs_dir_each_names
    cmp dword ptr [rip + g_remote], 0
    je dir_each_names
    mov ecx, 1
vfs_list:
    PROLOGUE 16
    mov r12, rsi
    mov r13, rdx
    mov [rsp], ecx
    mov rsi, rdi
    lea rdi, [rip + .Lv_list]
    call vfs_req_path
    test rax, rax
    js 9f
    # the answer is copied: a callback may make requests of its own
    mov rdi, [rip + g_remote_reply + SB_ptr]
    mov rsi, [rip + g_remote_reply + SB_len]
    call mem_dup
    mov r14, rax
    mov r15, [rip + g_remote_reply + SB_len]
    add r15, rax                # end
    mov rbx, rax
1:  cmp rbx, r15
    jae 8f
    lea rsi, [rbx + 2]          # "T NAME\0"
    movzx edx, byte ptr [rbx]
    xor eax, eax
    cmp edx, 'd'
    sete al
    cmp edx, 'L'
    jne 2f
    mov eax, 1
2:  mov edx, eax
    cmp dword ptr [rsp], 0
    je 3f
    xor edx, edx
3:  mov rdi, rsi
    push rsi
    push rdx
    call strlen
    pop rdx
    pop rsi
    lea rbx, [rsi + rax + 1]
    mov rdi, r13
    call r12
    jmp 1b
8:  mov rdi, r14
    call mem_free
    xor eax, eax
9:  EPILOGUE

# vfs_mkdir(path, mode) -> 0 or -errno
FN vfs_mkdir
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    SYS SYS_mkdir
    ret
1:  xor esi, esi
    jmp vfs_mkdir_req

# vfs_mkdir_p(path): the folder and those on the way (as mkdir_p)
FN vfs_mkdir_p
    cmp dword ptr [rip + g_remote], 0
    je mkdir_p
    mov esi, 1
vfs_mkdir_req:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    lea rdi, [rip + .Lv_mkdir]
    call vfs_line_start
    mov edi, r12d
    call vfs_line_num
    mov rdi, rbx
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call vfs_line_call
    add rsp, 8
    pop r12
    pop rbx
    ret

# vfs_mkdir_parent(path): the folders a file's path lives in (as mkdir_parent)
FN vfs_mkdir_parent
    cmp dword ptr [rip + g_remote], 0
    je mkdir_parent
    push rbx
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jz 9f
    cmp rax, 4095
    jae 9f
    lea rdi, [rip + vfs_tmp]
    mov rsi, rbx
    mov rdx, rax
    push rax
    push rax
    call memcpy
    pop rax
    pop rax
    lea rdi, [rip + vfs_tmp]
    mov byte ptr [rdi + rax], 0
    call vfs_mkdir_p
9:  pop rbx
    ret

# vfs_remove_tree(path) -> as file_remove_tree
FN vfs_remove_tree
    cmp dword ptr [rip + g_remote], 0
    je file_remove_tree
    mov esi, 1
    jmp vfs_remove_req

# vfs_unlink(path) / vfs_rmdir(path) -> 0 or -errno (the host's remove does either)
FN vfs_unlink
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    SYS SYS_unlink
    ret
1:  xor esi, esi
    jmp vfs_remove_req
FN vfs_rmdir
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    mov eax, 84                 # rmdir
    XSYS
    ret
1:  xor esi, esi
vfs_remove_req:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    lea rdi, [rip + .Lv_remove]
    call vfs_line_start
    mov edi, r12d
    call vfs_line_num
    mov rdi, rbx
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call vfs_line_call
    add rsp, 8
    pop r12
    pop rbx
    ret

# vfs_rename(old, new, flags) -> 0 or -errno; flags 1 refuses an existing destination (on the host
#   with renameat2; here it looks first)
FN vfs_rename
    cmp dword ptr [rip + g_remote], 0
    jne 1f
    test edx, 1
    jz 2f
    push rdi
    push rsi
    mov rdi, rsi
    call file_missing
    pop rsi
    pop rdi
    test eax, eax
    jnz 2f
    mov rax, -17                # EEXIST
    ret
2:  SYS SYS_rename
    ret
1:  PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    lea rdi, [rip + .Lv_rename]
    call vfs_line_start
    mov edi, r13d
    call vfs_line_num
    mov rdi, rbx
    call strlen
    mov r14, rax
    mov rdi, rax
    call vfs_line_num
    lea rdi, [rip + vfs_body]
    call sb_clear
    lea rdi, [rip + vfs_body]
    mov rsi, rbx
    mov rdx, r14
    call sb_push
    lea rdi, [rip + vfs_body]
    mov rsi, r12
    call sb_push_cstr
    mov rdi, [rip + vfs_body + SB_ptr]
    mov rsi, [rip + vfs_body + SB_len]
    call vfs_line_call
    EPILOGUE

# ---------------- programs ----------------

# vfs_run_piped(argv, envp, cwd) -> as run_piped
FN vfs_run_piped
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    jmp vfs_run_piped_input

# vfs_run_piped_input(argv, envp, cwd, ptr, len, errors) -> as run_piped_input: rax pid or -errno,
#   edx the descriptor to read the program's output from. In a remote window the program runs on
#   the host, found by its name in the host's PATH.
FN vfs_run_piped_input
    cmp dword ptr [rip + g_remote], 0
    je run_piped_input
    push rbx
    mov rbx, r8                 # input length
    mov r10d, r9d               # errors: 1 merges them with the output, else /dev/null
    mov r9, rcx                 # input
    mov r8d, -1
    test r10d, 1
    jz 1f
    mov r8d, -2
1:  xor ecx, ecx                # flags: a pipe, argv[0] by name
    push rbx
    push rbx
    call remote_spawn
    add rsp, 16
    pop rbx
    ret

# vfs_pty_spawn(argv, envp, cwd, cols, rows) -> rax pid (or -errno), edx the master (nonblocking).
#   In a remote window an empty argv (argv[0] == 0 or "") is the user's shell on the host.
FN vfs_pty_spawn
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov [rsp], ecx
    mov [rsp + 4], r8d
    cmp dword ptr [rip + g_remote], 0
    jne 5f
.ifdef WINDOWS
    mov rax, -38
    EPILOGUE
.else
    mov edi, ecx
    mov esi, r8d
    call pty_open
    test eax, eax
    js 8f
    mov ebx, eax                # master
    mov r15d, edx               # slave
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov ecx, r15d
    mov r8d, r15d
    mov r9d, r15d
    push 1
    push 1
    call proc_spawn
    add rsp, 16
    mov [rsp + 8], rax
    mov edi, r15d
    SYS SYS_close
    mov rax, [rsp + 8]
    test rax, rax
    jg 2f
    mov edi, ebx
    SYS SYS_close
    mov rax, [rsp + 8]
    test rax, rax
    jnz 9f
    mov rax, -5
    EPILOGUE
2:  mov edx, ebx
    EPILOGUE
8:  mov rax, -5
    EPILOGUE
.endif
5:  # flags: a pty, columns in bits 8-23, rows from bit 24
    mov ecx, [rsp]
    and ecx, 0xffff
    shl ecx, 8
    mov eax, [rsp + 4]
    and eax, 0xff
    shl eax, 24
    or ecx, eax
    or ecx, 1
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov r8d, -1
    xor r9d, r9d
    push 0
    push 0
    call remote_spawn
    add rsp, 16
9:  EPILOGUE

# ---------------- watch events from the host ----------------

# vfs_remote_event(wd, mask, name ptr, len): an inotify event of a remote watch; kept for vfs_tick
#   (it comes in the middle of the stream's parsing, where nothing else may run)
FN vfs_remote_event
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    cmp qword ptr [rip + vfs_pending + SB_len], 4194304
    jae 9f                      # nobody takes them: drop
    lea rdi, [rip + vfs_pending]
    mov esi, 16
    call sb_reserve
    mov [rax], ebx
    mov [rax + 4], r12d
    mov [rax + 8], r14
    add qword ptr [rip + vfs_pending + SB_len], 16
    lea rdi, [rip + vfs_pending]
    mov rsi, r13
    mov rdx, r14
    call sb_push
9:  EPILOGUE

# vfs_remote_lost(): the connection went: pending events are stale
FN vfs_remote_lost
    sub rsp, 8
    lea rdi, [rip + vfs_pending]
    call sb_clear
    add rsp, 8
    ret

# vfs_reconnected(): connected again after a loss (E2 renews the watches here)
FN vfs_reconnected
    ret

.section .rodata
.Lv_stat: .asciz "stat"
.Lv_lstat: .asciz "lstat"
.Lv_list: .asciz "list"
.Lv_access: .asciz "access"
.Lv_realpath: .asciz "realpath"
.Lv_mkdir: .asciz "mkdir"
.Lv_remove: .asciz "remove"
.Lv_rename: .asciz "rename"
vfs_line_read: .asciz "read"
vfs_line_write: .asciz "write"
.Lsave_suffix: .asciz ".rhun-save"
.Lproc_fd: .asciz "/proc/self/fd/"
.text
