# rhun --wasm-host [--dir PATH | --dir-ro PATH]... FILE.wasm [ARG...]: runs a wasm32-wasip1
# program (an extension) with WASI preview 1. Its standard input and output are the host's (the
# extension pipes), its environment the host's. Files: only inside the folders named by --dir
# (read and write) and --dir-ro (read only), which the program sees as preopened directories of
# the same names; paths are resolved lexically and may not climb out of them. No sockets, no
# processes. Functions WASI defines and rhun does not implement answer ENOSYS.
.include "rhun.inc"
.include "wasm/wasm.inc"

# WASI errno values
.equ WE_ACCES, 2
.equ WE_AGAIN, 6
.equ WE_BADF, 8
.equ WE_FAULT, 21
.equ WE_INVAL, 28
.equ WE_IO, 29
.equ WE_ISDIR, 31
.equ WE_MFILE, 33
.equ WE_NAMETOOLONG, 37
.equ WE_NOENT, 44
.equ WE_NOSYS, 52
.equ WE_NOTDIR, 54
.equ WE_SPIPE, 70
.equ WE_NOTCAPABLE, 76

.equ SYS_rmdir, 84
.equ SYS_stat, 4
.equ WASI_FDS, 128
.equ WASI_RIGHTS, 0x1fffffff        # every right WASI preview 1 defines
.equ WASI_PATH_MAX, 4096

# a file descriptor of the program
STRUCT
F WFD_kind, 4                       # 0 free, 1 standard stream, 2 directory, 3 file
F WFD_flags, 4                      # fdflags: 1 append, 4 nonblock
F WFD_host, 4                       # the host's descriptor (standard streams, files)
F WFD_write, 4                      # writing allowed
F WFD_resize, 4                     # files: fd_filestat_set_size allowed (asked for, writable folder)
F WFD_pad2, 4
F WFD_path, 8                       # directories: the host path (allocated)
F WFD_root, 8                       # directories: the allowed folder it is in
F WFD_rootreal, 8                   # directories: that folder's real path (links resolved)
F WFD_guest, 8                      # preopened directories: the name the program sees
F WFD_list, 8                       # directories: fd_readdir's names (type byte, name, NUL each)
F WFD_listlen, 8
F WFD_count, 8                      # entries in the list
ENDSTRUCT WFD_SIZE

.bss
.p2align 3
wasi_fds: .zero WASI_FDS * WFD_SIZE
wasi_args: .quad 0                  # C strings
wasi_nargs: .quad 0
wasi_inst: .quad 0
wasi_env: .quad 0                   # the program's environment (NULL-ended)
wasi_path_buf: .zero WASI_PATH_MAX + 16
wasi_path2_buf: .zero WASI_PATH_MAX + 16
wasi_real_buf: .zero 4096 + 16
wasi_list: .zero SB_SIZE
wasi_fnmem: .zero VEC_SIZE          # host functions made so far (WFN pointers)

.text
# wasm_host_main(argc, argv): never returns
FN wasm_host_main
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    # standard streams
    lea rbx, [rip + wasi_fds]
    xor ecx, ecx
1:  mov dword ptr [rbx + WFD_kind], 1
    mov [rbx + WFD_host], ecx
    mov dword ptr [rbx + WFD_write], 1
    add rbx, WFD_SIZE
    inc ecx
    cmp ecx, 3
    jb 1b
    # options, then the module
    mov r14d, 2
2:  cmp r14, r12
    jae .Lhost_usage
    mov rdi, [r13 + r14*8]
    lea rsi, [rip + .Lo_dir]
    call strcmp_eq
    mov r15d, 1
    test eax, eax
    jnz 3f
    mov rdi, [r13 + r14*8]
    lea rsi, [rip + .Lo_dir_ro]
    call strcmp_eq
    xor r15d, r15d
    test eax, eax
    jz 4f
3:  inc r14
    cmp r14, r12
    jae .Lhost_usage
    mov rdi, [r13 + r14*8]
    mov esi, r15d
    call wasi_preopen
    inc r14
    jmp 2b
4:  # argv for the program: the module's path, then the arguments after it
    mov rax, r12
    sub rax, r14
    mov [rip + wasi_nargs], rax
    lea rax, [r13 + r14*8]
    mov [rip + wasi_args], rax
    call wasi_environment
    lea rax, [rip + wasi_resolve]
    mov [rip + g_wasm_resolve], rax
    mov rdi, [r13 + r14*8]
    call file_read_all
    test rax, rax
    jz .Lhost_unreadable
    mov rdi, rax
    mov rsi, rdx
    call wasm_load
    test rax, rax
    jz .Lhost_invalid
    mov rbx, rax
    mov [rip + wasi_inst], rax
    mov rdi, rbx
    lea rsi, [rip + .Ls_start]
    mov edx, 6
    mov ecx, WK_FUNC
    call wasm_export_object
    test rax, rax
    jz .Lhost_no_start
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call wasm_invoke
    test eax, eax
    jz 7f
    cmp eax, WT_EXIT
    jne 6f
    mov rdi, [rip + g_wasm_exit]
    call sys_exit
6:  mov edi, eax
    call wasm_trap_text
    push rax
    push rax
    lea rdi, [rip + .Lm_trap]
    call log_cstr
    pop rdi
    pop rdi
    call log_cstr
    call log_nl
    mov edi, 134
    call sys_exit
7:  xor edi, edi
    call sys_exit
.Lhost_usage:
    lea rdi, [rip + .Lm_usage]
    call die
.Lhost_unreadable:
    lea rdi, [rip + .Lm_unreadable]
    call die
.Lhost_invalid:
    lea rdi, [rip + .Lm_invalid]
    call log_cstr
    mov rdi, [rip + g_wasm_err]
    call die
.Lhost_no_start:
    lea rdi, [rip + .Lm_no_start]
    call die

# wasi_environment(): the program's environment is the host's with PWD=/, so that a path that is
# not absolute resolves against the root in every runtime (Go takes PWD as its working folder,
# wasi-libc starts at /): on Windows C:/Users/me/a.txt is such a path, and finds /C:/Users/me
wasi_environment:
    PROLOGUE
    mov r12, [rip + g_envp]
    xor ebx, ebx
1:  cmp qword ptr [r12 + rbx*8], 0
    je 2f
    inc rbx
    jmp 1b
2:  lea rdi, [rbx*8 + 16]
    call mem_alloc
    mov r13, rax
    xor r14d, r14d                  # copied
    xor ebx, ebx
3:  mov rdi, [r12 + rbx*8]
    test rdi, rdi
    jz 5f
    inc rbx
    cmp dword ptr [rdi], 0x3d445750 # "PWD="
    je 3b
    mov [r13 + r14*8], rdi
    inc r14
    jmp 3b
5:  lea rax, [rip + .Ls_pwd]
    mov [r13 + r14*8], rax
    mov qword ptr [r13 + r14*8 + 8], 0
    mov [rip + wasi_env], r13
    EPILOGUE

# wasi_preopen(path, writable): the next descriptor is that folder, under its own name
wasi_preopen:
    PROLOGUE
    mov r12, rdi
    mov r13d, esi
    call wasi_fd_new
    test rax, rax
    jz 9f
    mov rbx, rax
    mov dword ptr [rbx + WFD_kind], 2
    mov dword ptr [rbx + WFD_host], -1
    mov [rbx + WFD_write], r13d
    # the host path without a trailing slash (the root keeps its own)
    mov rdi, r12
    call strlen
    mov rsi, rax
2:  cmp rsi, 1
    jbe 3f
    cmp byte ptr [r12 + rsi - 1], '/'
.ifdef WINDOWS
    je 21f
    cmp byte ptr [r12 + rsi - 1], '\\'
    jne 3f
21:
.else
    jne 3f
.endif
    dec rsi
    jmp 2b
3:  mov rdi, r12
    call mem_dup
.ifdef WINDOWS
    # forward slashes, as rhun writes paths and the program sees them
    mov rcx, rax
4:  cmp byte ptr [rcx], 0
    je 5f
    cmp byte ptr [rcx], '\\'
    jne 41f
    mov byte ptr [rcx], '/'
41: inc rcx
    jmp 4b
5:
.endif
    mov [rbx + WFD_path], rax
    mov [rbx + WFD_root], rax
    mov [rbx + WFD_guest], rax
    # its real path, which every path resolved under it must stay within (the path itself when
    # it cannot be resolved)
    mov r14, rax
    mov rdi, rax
    lea rsi, [rip + wasi_real_buf]
    call ext_realpath
    test eax, eax
    jz 6f
    lea r14, [rip + wasi_real_buf]
6:  mov rdi, r14
    call strlen
    mov rsi, rax
    mov rdi, r14
    call mem_dup
    mov [rbx + WFD_rootreal], rax
    mov rax, [rbx + WFD_guest]
.ifdef WINDOWS
    # the name it is seen under starts with a slash (/C:/Users/me): Go resolves C:/Users/me/a.txt
    # against the root /, wasi-libc drops leading slashes before it compares
    mov rdi, rax
    call strlen
    lea rdi, [rax + 2]
    call mem_alloc
    mov byte ptr [rax], '/'
    mov [rbx + WFD_guest], rax
    lea rdi, [rax + 1]
    mov rsi, [rbx + WFD_path]
    call cstr_copy
.endif
9:  EPILOGUE

# wasi_fd_new() -> rax a free record (zeroed), or 0; ecx its number
wasi_fd_new:
    lea rax, [rip + wasi_fds]
    xor ecx, ecx
1:  cmp dword ptr [rax + WFD_kind], 0
    je 2f
    add rax, WFD_SIZE
    inc ecx
    cmp ecx, WASI_FDS
    jb 1b
    xor eax, eax
    ret
2:  push rax
    push rcx
    mov rdi, rax
    xor esi, esi
    mov edx, WFD_SIZE
    call memset
    pop rcx
    pop rax
    ret

# wasi_fd(number) -> rax its record, or 0 when it is not open
wasi_fd:
    cmp edi, WASI_FDS
    jae 1f
    mov eax, edi
    imul rax, rax, WFD_SIZE
    lea rcx, [rip + wasi_fds]
    add rax, rcx
    cmp dword ptr [rax + WFD_kind], 0
    je 1f
    ret
1:  xor eax, eax
    ret

# wmem(guest address edi, length rsi) -> rax the host address of those bytes of the calling
# instance's memory, or 0 when they are not all inside it
wmem:
    mov rax, [rbx + WI_mem]
    mov ecx, edi
    lea rdx, [rcx + rsi]
    cmp rdx, [rax + WMEM_size]
    ja 1f
    mov rax, [rax + WMEM_base]
    add rax, rcx
    ret
1:  xor eax, eax
    ret

# wasi_errno(negative Linux errno rax) -> eax the WASI errno
wasi_errno:
    neg rax
    cmp rax, 40
    ja 1f
    lea rcx, [rip + .Lerrnos]
    movzx eax, byte ptr [rcx + rax]
    ret
1:  mov eax, WE_IO
    ret

# ---------------------------------------------------------------- linking

# wasi_resolve(module ptr, len, field ptr, len, kind r8, type id r9) -> a host function or 0
wasi_resolve:
    PROLOGUE 16
    mov r12, rdx
    mov r13, rcx
    mov r14d, r9d
    cmp r8, WK_FUNC
    jne 8f
    lea rdx, [rip + .Ls_wasi]
    call str_eq_cstr
    test eax, eax
    jz 8f
    lea rbx, [rip + wasi_table]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 5f
    push rdi
    push rdi
    call strlen
    pop rdx
    pop rdx
    cmp rax, r13
    jne 2f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 3f
2:  add rbx, 24
    jmp 1b
3:  # its signature: parameter count, result count, types
    mov rax, [rbx + 16]
    lea rdi, [rax + 2]
    movzx esi, byte ptr [rax]
    movzx edx, byte ptr [rax + 1]
    call wasm_type_intern
    mov r14d, eax
    mov r15, [rbx + 8]
    jmp 6f
5:  # a function rhun does not know answers ENOSYS: with an i32 result or none (any other
    # result would be a value of the wrong type), else it does not link
    mov edi, r14d
    call wasm_type
    mov ecx, [rax + WTY_nresults]
    test ecx, ecx
    jz 51f
    cmp ecx, 1
    jne 8f
    mov rdx, [rax + WTY_types]
    mov ecx, [rax + WTY_nparams]
    cmp byte ptr [rdx + rcx], WV_I32
    jne 8f
51: lea r15, [rip + wasi_nosys]
6:  lea rdi, [rip + wasi_fnmem]
    mov esi, 8
    call vec_push
    mov rbx, rax
    mov edi, WFN_SIZE
    call mem_alloc
    mov [rbx], rax
    mov [rax + WFN_type], r14d
    mov [rax + WFN_host], r15
    push rax
    push rax
    mov edi, r14d
    call wasm_type
    mov rcx, rax
    pop rax
    pop rax
    mov edx, [rcx + WTY_nparams]
    mov [rax + WFN_nparams], edx
    mov edx, [rcx + WTY_nresults]
    mov [rax + WFN_nresults], edx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# host functions: (arguments rdi, function rsi, instance rbx) -> eax 0, or a trap code; the
# errno result replaces the first argument

wasi_nosys:
    mov rax, rsi
    cmp dword ptr [rax + WFN_nresults], 0
    je 1f
    mov qword ptr [rdi], WE_NOSYS
1:  xor eax, eax
    ret

# answer(errno ecx): the common ending
.macro ANSWER
    mov [r12], rcx
    xor eax, eax
    EPILOGUE
.endm

# args_sizes_get(count*, size*)
w_args_sizes_get:
    lea rax, [rip + wasi_args]
    lea rcx, [rip + wasi_nargs]
    jmp .Lsizes
# environ_sizes_get(count*, size*)
w_environ_sizes_get:
    lea rax, [rip + wasi_env]
    xor ecx, ecx
.Lsizes:
    PROLOGUE
    mov r12, rdi
    mov r13, [rax]                  # the strings
    mov r14, rcx                    # their count's place, or 0 for a NULL-ended list
    xor r15d, r15d                  # count
    xor ebx, ebx
    push rbx
    push rbx
1:  test r14, r14
    jz 2f
    cmp r15, [r14]
    jae 3f
    jmp 21f
2:  cmp qword ptr [r13 + r15*8], 0
    je 3f
21: mov rdi, [r13 + r15*8]
    call strlen
    inc rax
    add [rsp], rax
    inc r15
    jmp 1b
3:  pop r13
    pop rax
    mov rbx, [rip + g_wasm_caller]
    mov edi, [r12]
    mov esi, 4
    call wmem
    test rax, rax
    jz 8f
    mov [rax], r15d
    mov edi, [r12 + 8]
    mov esi, 4
    call wmem
    test rax, rax
    jz 8f
    mov [rax], r13d
    xor ecx, ecx
    ANSWER
8:  mov ecx, WE_FAULT
    ANSWER

# args_get(argv*, buf*)
w_args_get:
    lea rax, [rip + wasi_args]
    lea rcx, [rip + wasi_nargs]
    jmp .Lstrings
# environ_get(environ*, buf*)
w_environ_get:
    lea rax, [rip + wasi_env]
    xor ecx, ecx
.Lstrings:
    PROLOGUE 16
    mov r12, rdi
    mov r13, [rax]
    mov r14, rcx
    xor r15d, r15d
    mov rbx, [rip + g_wasm_caller]
    mov eax, [r12]
    mov [rsp], eax                  # the next pointer slot
    mov eax, [r12 + 8]
    mov [rsp + 4], eax              # the next string
1:  test r14, r14
    jz 2f
    cmp r15, [r14]
    jae 3f
    jmp 21f
2:  cmp qword ptr [r13 + r15*8], 0
    je 3f
21: mov rdi, [r13 + r15*8]
    call strlen
    lea rdx, [rax + 1]
    mov [rsp + 8], rdx
    mov edi, [rsp + 4]
    mov rsi, rdx
    call wmem
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, [r13 + r15*8]
    mov rdx, [rsp + 8]
    call memcpy
    mov edi, [rsp]
    mov esi, 4
    call wmem
    test rax, rax
    jz 8f
    mov ecx, [rsp + 4]
    mov [rax], ecx
    add dword ptr [rsp], 4
    mov rdx, [rsp + 8]
    add [rsp + 4], edx
    inc r15
    jmp 1b
3:  xor ecx, ecx
    ANSWER
8:  mov ecx, WE_FAULT
    ANSWER

# clock_res_get(id, resolution*)
w_clock_res_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12 + 8]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov qword ptr [rax], 1000
    xor ecx, ecx
9:  ANSWER

# clock_time_get(id, precision i64, time*): realtime for 0, monotonic otherwise
w_clock_time_get:
    PROLOGUE 16
    mov r12, rdi
    xor edi, edi
    cmp dword ptr [r12], 0
    je 1f
    mov edi, CLOCK_MONOTONIC
1:  mov rsi, rsp
    SYS SYS_clock_gettime
    mov rax, [rsp]
    imul rax, rax, 1000000000
    add rax, [rsp + 8]
    mov [rsp], rax
    mov edi, [r12 + 16]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov rcx, [rsp]
    mov [rax], rcx
    xor ecx, ecx
9:  ANSWER

# random_get(buf*, len)
w_random_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    mov esi, [r12 + 8]
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov rdi, rax
    mov esi, [r12 + 8]
    call wasi_os_random
    mov ecx, WE_IO
    test rax, rax
    jnz 9f
    xor ecx, ecx
9:  ANSWER

# proc_exit(code)
w_proc_exit:
    mov eax, [rdi]
    mov [rip + g_wasm_exit], rax
    mov eax, WT_EXIT
    ret

w_sched_yield:
    mov qword ptr [rdi], 0
    xor eax, eax
    ret

# fd_write(fd, iovs*, count, written*)
w_fd_write:
    PROLOGUE 16
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    cmp dword ptr [rax + WFD_kind], 2
    je 9f
    cmp dword ptr [rax + WFD_write], 0
    je 9f
    mov r13d, [rax + WFD_host]
    # a file in append mode (fd_fdstat_set_flags may set it after the open) writes at its end
    cmp dword ptr [rax + WFD_kind], 3
    jne 11f
    test dword ptr [rax + WFD_flags], 1
    jz 11f
    mov edi, r13d
    xor esi, esi
    mov edx, 2
    SYS SYS_lseek
11: xor r14d, r14d                  # written
    xor r15d, r15d                  # iov
1:  cmp r15d, [r12 + 16]
    jae 5f
    mov edi, [r12 + 8]
    lea edi, [rdi + r15*8]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov edi, [rax]
    mov esi, [rax + 4]
    mov [rsp], rsi
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov edi, r13d
    mov rsi, rax
    mov rdx, [rsp]
    call write_all
    test rax, rax
    js 8f
    add r14, [rsp]
    inc r15d
    jmp 1b
5:  mov edi, [r12 + 24]
    mov esi, 4
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov [rax], r14d
    xor ecx, ecx
9:  ANSWER
8:  call wasi_errno
    mov ecx, eax
    ANSWER

# fd_read(fd, iovs*, count, read*): one host read per buffer, until one comes back short
w_fd_read:
    PROLOGUE 16
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    cmp dword ptr [rax + WFD_kind], 2
    mov ecx, WE_ISDIR
    je 9f
    mov r13d, [rax + WFD_host]
    test dword ptr [rax + WFD_flags], 4
    jz 1f
    # non-blocking: nothing waiting is EAGAIN
    mov edi, r13d
    xor esi, esi
    call wasi_os_wait_read
    mov ecx, WE_AGAIN
    test eax, eax
    jz 9f
1:  xor r14d, r14d
    xor r15d, r15d
2:  cmp r15d, [r12 + 16]
    jae 5f
    mov edi, [r12 + 8]
    lea edi, [rdi + r15*8]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov edi, [rax]
    mov esi, [rax + 4]
    mov [rsp], rsi
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    cmp qword ptr [rsp], 0
    je 4f
3:  mov edi, r13d
    mov rsi, rax
    mov rdx, [rsp]
    mov [rsp + 8], rax
    SYS SYS_read
    cmp rax, -EINTR
    jne 31f
    mov rax, [rsp + 8]
    jmp 3b
31: test rax, rax
    js 8f
    add r14, rax
    cmp rax, [rsp]
    jb 5f
4:  inc r15d
    jmp 2b
5:  mov edi, [r12 + 24]
    mov esi, 4
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov [rax], r14d
    xor ecx, ecx
9:  ANSWER
8:  test r14, r14
    jnz 5b
    call wasi_errno
    mov ecx, eax
    ANSWER

# fd_pread(fd, iovs*, count, offset i64, read*): through fd_read at the offset, then back
w_fd_pread:
    mov eax, SYS_read
    jmp .Lpositioned
# fd_pwrite(fd, iovs*, count, offset i64, written*)
w_fd_pwrite:
    mov eax, SYS_write
.Lpositioned:
    PROLOGUE 48
    mov r12, rdi
    mov [rsp + 16], eax
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov ecx, WE_SPIPE
    cmp dword ptr [rax + WFD_kind], 3
    jne 9f
    mov r13d, [rax + WFD_host]
    mov edi, r13d
    xor esi, esi
    mov edx, 1
    SYS SYS_lseek
    test rax, rax
    js 8f
    mov [rsp + 24], rax             # where it was
    mov edi, r13d
    mov rsi, [r12 + 24]
    xor edx, edx
    SYS SYS_lseek
    test rax, rax
    js 8f
    # the same arguments, with the result pointer where fd_read and fd_write take it
    mov rax, [r12 + 32]
    mov [r12 + 24], rax
    mov rdi, r12
    cmp dword ptr [rsp + 16], SYS_read
    jne 1f
    call w_fd_read
    jmp 2f
1:  call w_fd_write
2:  mov edi, r13d
    mov rsi, [rsp + 24]
    xor edx, edx
    SYS SYS_lseek
    xor eax, eax
    EPILOGUE
9:  ANSWER
8:  call wasi_errno
    mov ecx, eax
    ANSWER

# fd_close(fd)
w_fd_close:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp dword ptr [rbx + WFD_kind], 2
    je 1f
    mov edi, [rbx + WFD_host]
    SYS SYS_close
    jmp 2f
1:  mov rdi, [rbx + WFD_list]
    call mem_free
2:  mov dword ptr [rbx + WFD_kind], 0
    xor ecx, ecx
9:  ANSWER

# fd_seek(fd, offset i64, whence, newoffset*)
w_fd_seek:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov ecx, WE_SPIPE
    cmp dword ptr [rax + WFD_kind], 3
    jne 9f
    mov edi, [rax + WFD_host]
    mov rsi, [r12 + 8]
    mov edx, [r12 + 16]
    cmp edx, 2
    mov ecx, WE_INVAL
    ja 9f
    SYS SYS_lseek
    test rax, rax
    js 8f
    mov r13, rax
    mov edi, [r12 + 24]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov [rax], r13
    xor ecx, ecx
9:  ANSWER
8:  call wasi_errno
    mov ecx, eax
    ANSWER

# fd_tell(fd, offset*)
w_fd_tell:
    mov rax, [rdi + 8]
    mov [rdi + 24], rax
    mov qword ptr [rdi + 8], 0
    mov qword ptr [rdi + 16], 1
    jmp w_fd_seek

# fd_sync, fd_datasync (fd)
w_fd_sync:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    xor ecx, ecx
    cmp dword ptr [rax + WFD_kind], 3
    jne 9f
    mov edi, [rax + WFD_host]
    SYS SYS_fsync
    xor ecx, ecx
9:  ANSWER

# fd_fdstat_get(fd, fdstat*): filetype, flags, all rights
w_fd_fdstat_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov r13, rax
    mov edi, [r12 + 8]
    mov esi, 24
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov ecx, [r13 + WFD_kind]
    lea rdx, [rip + .Lkind_types]
    movzx ecx, byte ptr [rdx + rcx]
    mov [rax], cl
    mov byte ptr [rax + 1], 0
    mov ecx, [r13 + WFD_flags]
    mov [rax + 2], cx
    mov dword ptr [rax + 4], 0
    mov rcx, WASI_RIGHTS
    mov [rax + 8], rcx
    mov [rax + 16], rcx
    xor ecx, ecx
9:  ANSWER

# fd_fdstat_set_flags(fd, flags): append and non-blocking are kept
w_fd_fdstat_set_flags:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov ecx, [r12 + 8]
    and ecx, 5
    mov [rax + WFD_flags], ecx
    xor ecx, ecx
9:  ANSWER

# fd_fdstat_set_rights and the advice and allocation calls: accepted, nothing to do
w_fd_ok:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    xor ecx, ecx
9:  ANSWER

# fd_prestat_get(fd, prestat*): the preopened directories' names
w_fd_prestat_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    cmp qword ptr [rax + WFD_guest], 0
    je 9f
    mov rdi, [rax + WFD_guest]
    call strlen
    mov r13, rax
    mov edi, [r12 + 8]
    mov esi, 8
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov dword ptr [rax], 0
    mov [rax + 4], r13d
    xor ecx, ecx
9:  ANSWER

# fd_prestat_dir_name(fd, buf*, len)
w_fd_prestat_dir_name:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov r13, [rax + WFD_guest]
    test r13, r13
    jz 9f
    mov rdi, r13
    call strlen
    mov r14, rax
    mov ecx, WE_NAMETOOLONG
    cmp r14d, [r12 + 16]
    ja 9f
    mov edi, [r12 + 8]
    mov rsi, r14
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call memcpy
    xor ecx, ecx
9:  ANSWER

# filestat(host path rdi or 0, host fd esi, follow edx, guest filestat* ecx) -> ecx the errno
wasi_filestat:
    PROLOGUE 16
    mov r13d, ecx
    test rdi, rdi
    jz 1f
    mov rsi, rsp
    mov eax, SYS_stat
    test edx, edx
    jnz 2f
    mov eax, SYS_lstat
    jmp 2f
1:  mov edi, esi
    mov rsi, rsp
    mov eax, SYS_fstat
2:  # the Linux stat layout, in a buffer of its own
    lea rsi, [rip + stat_tmp]
    XSYS
    test rax, rax
    js 8f
    mov edi, r13d
    mov esi, 64
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    lea rdx, [rip + stat_tmp]
    mov rcx, [rdx]
    mov [rax], rcx                  # dev
    mov rcx, [rdx + 8]
    mov [rax + 8], rcx              # ino
    mov ecx, [rdx + 24]
    call wasi_mode_type
    mov qword ptr [rax + 16], 0
    mov [rax + 16], cl              # filetype
    mov rcx, [rdx + 16]
    mov [rax + 24], rcx             # nlink
    mov rcx, [rdx + 48]
    mov [rax + 32], rcx             # size
    mov rcx, [rdx + 72]
    imul rcx, rcx, 1000000000
    add rcx, [rdx + 80]
    mov [rax + 40], rcx             # atim
    mov rcx, [rdx + 88]
    imul rcx, rcx, 1000000000
    add rcx, [rdx + 96]
    mov [rax + 48], rcx             # mtim
    mov rcx, [rdx + 104]
    imul rcx, rcx, 1000000000
    add rcx, [rdx + 112]
    mov [rax + 56], rcx             # ctim
    xor ecx, ecx
9:  EPILOGUE
8:  call wasi_errno
    mov ecx, eax
    EPILOGUE

# wasi_mode_type(st_mode ecx) -> ecx the WASI filetype (keeps rax and rdx)
wasi_mode_type:
    and ecx, 0xf000
    cmp ecx, 0x4000
    je 1f
    cmp ecx, 0x8000
    je 2f
    cmp ecx, 0xa000
    je 3f
    cmp ecx, 0x2000
    je 4f
    xor ecx, ecx
    ret
1:  mov ecx, 3
    ret
2:  mov ecx, 4
    ret
3:  mov ecx, 7
    ret
4:  mov ecx, 2
    ret

# fd_filestat_get(fd, filestat*)
w_fd_filestat_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    xor edi, edi
    cmp dword ptr [rax + WFD_kind], 2
    jne 1f
    mov rdi, [rax + WFD_path]
1:  mov esi, [rax + WFD_host]
    mov edx, 1
    mov ecx, [r12 + 8]
    call wasi_filestat
9:  ANSWER

# fd_filestat_set_size(fd, size i64)
w_fd_filestat_set_size:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    cmp dword ptr [rax + WFD_kind], 3
    jne 9f
    mov ecx, WE_NOTCAPABLE
    mov edx, [rax + WFD_write]
    or edx, [rax + WFD_resize]
    jz 9f
    mov edi, [rax + WFD_host]
    mov rsi, [r12 + 8]
    SYS SYS_ftruncate
    xor ecx, ecx
    test rax, rax
    jns 9f
    call wasi_errno
    mov ecx, eax
9:  ANSWER

# wasi_path(dirfd edi, guest path esi, length edx, buffer rcx, mode r8d) -> rax 0 and the host
# path in the buffer, or the WASI errno; r8d the directory's write permission, r9d 1 when the
# target does not exist (open it without following a final link). Components are resolved
# lexically ("." stays, ".." climbs, climbing above the allowed folder is refused), then the real
# path decides, so that a link inside cannot lead out: mode 0 follows the target (its real path,
# or its folder's when it does not exist, must be inside the allowed folder's real path); mode 1
# acts on the target itself (a link, a name to remove or create: its folder's must be inside, and its own too when it resolves).
wasi_path:
    PROLOGUE 32
    mov [rsp + 20], r8d
    mov dword ptr [rsp + 24], 0
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz .Lp_fail
    mov ecx, WE_NOTDIR
    cmp dword ptr [rax + WFD_kind], 2
    jne .Lp_fail
    mov rbx, rax
    mov [rsp + 8], rax              # the directory's record
    mov eax, [rbx + WFD_write]
    mov [rsp + 16], eax
    mov edi, r12d
    mov esi, r13d
    push rbx
    mov rbx, [rip + g_wasm_caller]
    call wmem
    pop rbx
    mov ecx, WE_FAULT
    test rax, rax
    jz .Lp_fail
    mov r12, rax                    # the guest path's bytes
    mov ecx, WE_NAMETOOLONG
    cmp r13, 2048
    ja .Lp_fail
    # the buffer: the directory's path; the root's length is the floor ".." stops at
    mov rdi, [rbx + WFD_root]
    call strlen
    mov r15, rax
    mov rdi, [rbx + WFD_path]
    call strlen
    mov rdx, rax
    mov rdi, r14
    mov rsi, [rbx + WFD_path]
    push rdx
    push rdx
    call memcpy
    pop rax
    pop rax
    mov [rsp], rax                  # the buffer's length
    mov rcx, WE_NOTCAPABLE
    test r13, r13
    jz 7f
    cmp byte ptr [r12], '/'
    je .Lp_fail
    xor ebx, ebx                    # position in the guest path
1:  cmp rbx, r13
    jae 7f
    # one component: [rbx, rdx)
    mov rdx, rbx
2:  cmp rdx, r13
    jae 3f
    movzx eax, byte ptr [r12 + rdx]
    test eax, eax
    jz .Lp_inval
.ifdef WINDOWS
    # drive letters and backslashes would name other places
    cmp eax, '\\'
    je .Lp_notcapable
    cmp eax, ':'
    je .Lp_notcapable
.endif
    cmp eax, '/'
    je 3f
    inc rdx
    jmp 2b
3:  mov rcx, rdx
    sub rcx, rbx                    # its length
    jz 6f
    cmp rcx, 1
    jne 4f
    cmp byte ptr [r12 + rbx], '.'
    je 6f
4:  cmp rcx, 2
    jne 5f
    cmp word ptr [r12 + rbx], 0x2e2e
    jne 5f
    # ..: back to the previous slash, never above the root
    mov rax, [rsp]
    cmp rax, r15
    jbe .Lp_notcapable
41: dec rax
    cmp byte ptr [r14 + rax], '/'
    jne 41b
    mov [rsp], rax
    jmp 6f
5:  mov rax, [rsp]
    lea r8, [rax + rcx + 2]
    cmp r8, WASI_PATH_MAX
    jae .Lp_long
    mov byte ptr [r14 + rax], '/'
    inc rax
    push rdx
    push rcx
    lea rdi, [r14 + rax]
    lea rsi, [r12 + rbx]
    mov rdx, rcx
    push rax
    push rax
    call memcpy
    pop rax
    pop rax
    pop rcx
    pop rdx
    add rax, rcx
    mov [rsp], rax
6:  lea rbx, [rdx + 1]
    jmp 1b
7:  mov rax, [rsp]
    mov byte ptr [r14 + rax], 0
    # the real path: the target's when it exists (in mode 1 too: Windows, or Wine's view of Unix
    # links, may remove or rename what a link leads to), and its folder's
    mov rdi, r14
    lea rsi, [rip + wasi_real_buf]
    call ext_realpath
    test eax, eax
    jz 71f
    call .Lp_inside
    jz .Lp_notcapable
    cmp dword ptr [rsp + 20], 0
    je 9f
    jmp 8f
71: mov dword ptr [rsp + 24], 1
8:  # the folder: the buffer up to its last slash (the allowed folder itself when that is all)
    mov rcx, [rsp]
    mov rax, [rsp + 8]
    mov rdi, [rax + WFD_root]
    push rcx
    push rcx
    call strlen
    pop rcx
    pop rcx
    cmp rcx, rax
    jbe 82f
81: dec rcx
    cmp byte ptr [r14 + rcx], '/'
    jne 81b
    test rcx, rcx
    jz 82f
    mov byte ptr [r14 + rcx], 0
    mov [rsp + 28], ecx
    mov rdi, r14
    lea rsi, [rip + wasi_real_buf]
    call ext_realpath
    mov ecx, [rsp + 28]
    mov byte ptr [r14 + rcx], '/'
    jmp 83f
82: mov rdi, r14
    lea rsi, [rip + wasi_real_buf]
    call ext_realpath
83: test eax, eax
    jz .Lp_noent
    call .Lp_inside
    jz .Lp_notcapable
9:  mov r8d, [rsp + 16]
    mov r9d, [rsp + 24]
    xor eax, eax
    EPILOGUE
# wasi_real_buf inside the directory's allowed folder ([rsp + 8 + 8] its record) -> ZF clear
.Lp_inside:
    mov rax, [rsp + 16]
    mov rdi, [rax + WFD_rootreal]
    call wasi_inside
    test eax, eax
    ret

# wasi_inside(real path of the allowed folder) -> eax 1 when wasi_real_buf is that folder or in it
wasi_inside:
    push rdi
    call strlen
    pop rsi
    cmp rax, 1
    jne 1f
    cmp byte ptr [rsi], '/'
    je 3f                           # the root of everything: all is inside
1:  push rax
    lea rdi, [rip + wasi_real_buf]
    mov rdx, rax
    call memeq
    pop rcx
    test eax, eax
    jz 2f
    lea rdx, [rip + wasi_real_buf]
    movzx eax, byte ptr [rdx + rcx]
    test eax, eax
    jz 3f
    cmp eax, '/'
    je 3f
2:  xor eax, eax
    ret
3:  mov eax, 1
    ret
.Lp_noent:
    mov ecx, WE_NOENT
    jmp .Lp_fail
.Lp_inval:
    mov ecx, WE_INVAL
    jmp .Lp_fail
.Lp_notcapable:
    mov ecx, WE_NOTCAPABLE
    jmp .Lp_fail
.Lp_long:
    mov ecx, WE_NAMETOOLONG
.Lp_fail:
    mov eax, ecx
    EPILOGUE

# path_filestat_get(fd, flags, path*, len, filestat*)
w_path_filestat_get:
    PROLOGUE
    mov r12, rdi
    mov edi, [r12]
    mov esi, [r12 + 16]
    mov edx, [r12 + 24]
    lea rcx, [rip + wasi_path_buf]
    mov r8d, [r12 + 8]
    and r8d, 1
    xor r8d, 1                      # following a final link: mode 0
    call wasi_path
    mov ecx, eax
    test eax, eax
    jnz 9f
    lea rdi, [rip + wasi_path_buf]
    mov edx, [r12 + 8]
    and edx, 1
    mov ecx, [r12 + 32]
    call wasi_filestat
9:  ANSWER

# path_open(fd, dirflags, path*, len, oflags, rights i64, inheriting i64, fdflags, fd*)
w_path_open:
    PROLOGUE 32
    mov r12, rdi
    mov edi, [r12]
    mov esi, [r12 + 16]
    mov edx, [r12 + 24]
    lea rcx, [rip + wasi_path_buf]
    xor r8d, r8d
    call wasi_path
    mov ecx, eax
    test eax, eax
    jnz 9f
    mov [rsp + 8], r8d              # the directory may be written to
    mov [rsp + 12], r9d             # the target does not exist yet
    # writing: creating, truncating, appending, or the right to write or allocate asked for (Go
    # asks for fd_filestat_set_size even to read, wasi-libc only to write: it does not count)
    xor r13d, r13d
    test dword ptr [r12 + 32], 9
    jnz 1f
    test dword ptr [r12 + 56], 1
    jnz 1f
    mov rax, [r12 + 40]
    test rax, (1 << 6) | (1 << 8)
    jz 2f
1:  mov r13d, 1
    mov ecx, WE_NOTCAPABLE
    cmp dword ptr [rsp + 8], 0
    je 9f
2:  # host flags
    xor r15d, r15d                  # resizing only (fd_filestat_set_size without fd_write)
    mov esi, O_CLOEXEC
    test r13d, r13d
    jz 25f
    mov rax, [r12 + 40]
    or esi, O_WRONLY
    test rax, (1 << 1) | (1 << 14)
    jz 3f
    xor esi, O_WRONLY ^ O_RDWR
    jmp 3f
25: # the right to resize asked for under a writable folder: open to read and write when this
    # user may (Go asks for it in every open, so it is a wish, not a need: see the open below)
    mov rax, [r12 + 40]
    test rax, 1 << 22
    jz 3f
    cmp dword ptr [rsp + 8], 0
    je 3f
    mov r15d, 1
    or esi, O_RDWR
3:  mov eax, [r12 + 32]
    test eax, 1
    jz 31f
    or esi, O_CREAT
31: test eax, 4
    jz 32f
    or esi, O_EXCL
32: test eax, 8
    jz 33f
    or esi, O_TRUNC
33: test eax, 2
    jz 34f
    or esi, O_DIRECTORY
34: test dword ptr [r12 + 56], 1
    jz 35f
    or esi, O_APPEND
35: # a final link is followed only when asked and when it resolved inside (wasi_path); a name
    # that is there but does not resolve is a link to nowhere, which creating would follow out
    # (Windows has no O_NOFOLLOW to stop it)
    test dword ptr [r12 + 8], 1
    jz 36f
    cmp dword ptr [rsp + 12], 0
    je 37f
36: or esi, O_NOFOLLOW
    cmp dword ptr [rsp + 12], 0
    je 37f
    mov [rsp + 16], esi
    lea rdi, [rip + wasi_path_buf]
    call wasi_os_lexists
    mov esi, [rsp + 16]
    mov ecx, WE_NOTCAPABLE
    test eax, eax
    jnz 9f
37: mov [rsp + 24], esi
    lea rdi, [rip + wasi_path_buf]
    mov edx, 0644
    SYS SYS_open
    test rax, rax
    jns 371f
    test r15d, r15d
    jz 8f
    # a file this user cannot write (or a directory) opens to read, without the resizing
    xor r15d, r15d
    mov esi, [rsp + 24]
    and esi, ~3
    lea rdi, [rip + wasi_path_buf]
    mov edx, 0644
    SYS SYS_open
    test rax, rax
    js 8f
371: mov r14d, eax
    # what was opened: its real path is inside, or it is closed again
    lea rdi, [rip + wasi_path_buf]
    lea rsi, [rip + wasi_real_buf]
    call ext_realpath
    test eax, eax
    jz 38f
    mov edi, [r12]
    call wasi_fd
    mov rdi, [rax + WFD_rootreal]
    call wasi_inside
    test eax, eax
    jnz 38f
    mov edi, r14d
    SYS SYS_close
    # made outside through a link the checks could not see (Wine's view of Unix links): it did
    # not exist before this call, so it goes again
    cmp dword ptr [rsp + 12], 0
    je 39f
    lea rdi, [rip + wasi_real_buf]
    SYS SYS_unlink
39: mov ecx, WE_NOTCAPABLE
    jmp 9f
38:
    # a directory becomes a path-based descriptor (stat by path: Windows' fstat knows files only)
    lea rdi, [rip + wasi_path_buf]
    lea rsi, [rip + stat_tmp]
    SYS SYS_stat
    mov ecx, [rip + stat_tmp + 24]
    and ecx, 0xf000
    cmp ecx, 0x4000
    jne 5f
    mov edi, r14d
    SYS SYS_close
    call wasi_fd_new
    test rax, rax
    jz 53f
    mov rbx, rax
    mov [rsp + 16], ecx
    mov dword ptr [rbx + WFD_kind], 2
    mov dword ptr [rbx + WFD_host], -1
    mov eax, [rsp + 8]
    mov [rbx + WFD_write], eax
    lea rdi, [rip + wasi_path_buf]
    call strlen
    mov rsi, rax
    lea rdi, [rip + wasi_path_buf]
    call mem_dup
    mov [rbx + WFD_path], rax
    # the allowed folder it lies in: the directory it was opened from's
    mov edi, [r12]
    call wasi_fd
    mov rcx, [rax + WFD_rootreal]
    mov [rbx + WFD_rootreal], rcx
    mov rax, [rax + WFD_root]
    mov [rbx + WFD_root], rax
    jmp 6f
5:  mov ecx, WE_ISDIR
    test dword ptr [r12 + 32], 2
    jnz 51f
    call wasi_fd_new
    test rax, rax
    jz 52f
    mov rbx, rax
    mov [rsp + 16], ecx
    mov dword ptr [rbx + WFD_kind], 3
    mov [rbx + WFD_host], r14d
    mov [rbx + WFD_write], r13d
    mov [rbx + WFD_resize], r15d
    mov eax, [r12 + 56]
    and eax, 5
    mov [rbx + WFD_flags], eax
6:  mov edi, [r12 + 64]
    mov esi, 4
    push rbx
    mov rbx, [rip + g_wasm_caller]
    call wmem
    pop rbx
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov ecx, [rsp + 16]
    mov [rax], ecx
    xor ecx, ecx
9:  ANSWER
51: mov ecx, WE_NOTDIR
52: push rcx
    push rcx
    mov edi, r14d
    SYS SYS_close
    pop rcx
    pop rcx
    test ecx, ecx
    jnz 9b
    mov ecx, WE_MFILE
    ANSWER
53: mov ecx, WE_MFILE
    ANSWER
8:  call wasi_errno
    mov ecx, eax
    ANSWER

# a path call that changes the tree: (fd, path*, len) resolved writable into wasi_path_buf
.macro TREE_PATH fdoff, pathoff, lenoff, buf
    mov edi, [r12 + \fdoff]
    mov esi, [r12 + \pathoff]
    mov edx, [r12 + \lenoff]
    lea rcx, [rip + \buf]
    mov r8d, 1
    call wasi_path
    mov ecx, eax
    test eax, eax
    jnz 9f
    mov ecx, WE_NOTCAPABLE
    test r8d, r8d
    jz 9f
.endm

# path_create_directory(fd, path*, len)
w_path_create_directory:
    PROLOGUE
    mov r12, rdi
    TREE_PATH 0, 8, 16, wasi_path_buf
    lea rdi, [rip + wasi_path_buf]
    mov esi, 0755
    SYS SYS_mkdir
    jmp .Ltree_result
# path_remove_directory(fd, path*, len)
w_path_remove_directory:
    PROLOGUE
    mov r12, rdi
    TREE_PATH 0, 8, 16, wasi_path_buf
    lea rdi, [rip + wasi_path_buf]
    SYS SYS_rmdir
    jmp .Ltree_result
# path_unlink_file(fd, path*, len)
w_path_unlink_file:
    PROLOGUE
    mov r12, rdi
    TREE_PATH 0, 8, 16, wasi_path_buf
    lea rdi, [rip + wasi_path_buf]
    SYS SYS_unlink
    jmp .Ltree_result
# path_rename(fd, old*, len, newfd, new*, len)
w_path_rename:
    PROLOGUE
    mov r12, rdi
    TREE_PATH 0, 8, 16, wasi_path_buf
    TREE_PATH 24, 32, 40, wasi_path2_buf
    lea rdi, [rip + wasi_path_buf]
    lea rsi, [rip + wasi_path2_buf]
    SYS SYS_rename
.Ltree_result:
    xor ecx, ecx
    test rax, rax
    jns 9f
    call wasi_errno
    mov ecx, eax
9:  ANSWER

# fd_readdir(fd, buf*, len, cookie i64, used*): entries from the cookie's on (a cookie is the
# next entry's index); the directory is listed again when the cookie is 0
w_fd_readdir:
    PROLOGUE 48
    mov r12, rdi
    mov edi, [r12]
    call wasi_fd
    mov ecx, WE_BADF
    test rax, rax
    jz 9f
    mov ecx, WE_NOTDIR
    cmp dword ptr [rax + WFD_kind], 2
    jne 9f
    mov rbx, rax
    cmp qword ptr [r12 + 24], 0
    jne 1f
    lea rdi, [rip + wasi_list]
    call sb_clear
    mov qword ptr [rip + list_count], 0
    mov rdi, [rbx + WFD_path]
    lea rsi, [rip + readdir_entry]
    xor edx, edx
    call dir_each
    mov rdi, [rbx + WFD_list]
    call mem_free
    mov rdi, [rip + wasi_list + SB_ptr]
    mov rsi, [rip + wasi_list + SB_len]
    call mem_dup
    mov [rbx + WFD_list], rax
    mov rax, [rip + wasi_list + SB_len]
    mov [rbx + WFD_listlen], rax
    mov rax, [rip + list_count]
    mov [rbx + WFD_count], rax
1:  mov edi, [r12 + 8]
    mov esi, [r12 + 16]
    push rbx
    mov rbx, [rip + g_wasm_caller]
    call wmem
    pop rbx
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov r13, rax                    # the output
    mov r14d, [r12 + 16]            # its room
    xor r15d, r15d                  # used
    # skip to the cookie's entry
    mov rsi, [rbx + WFD_list]
    xor ecx, ecx
2:  cmp rcx, [r12 + 24]
    jae 3f
    cmp rcx, [rbx + WFD_count]
    jae 3f
    inc rsi
21: cmp byte ptr [rsi], 0
    je 22f
    inc rsi
    jmp 21b
22: inc rsi
    inc rcx
    jmp 2b
3:  cmp rcx, [rbx + WFD_count]
    jae 7f
    mov [rsp], rcx
    mov [rsp + 8], rsi
    # dirent: next, inode, name length, type; then the name, cut off when the room ends
    movzx eax, byte ptr [rsi]
    mov [rsp + 16], eax
    lea rdi, [rsi + 1]
    call strlen
    mov [rsp + 24], rax
    lea rdi, [rsp + 32]
    mov rcx, [rsp]
    inc rcx
    mov [rip + dirent_tmp], rcx
    mov qword ptr [rip + dirent_tmp + 8], 0
    mov rcx, [rsp + 24]
    mov [rip + dirent_tmp + 16], ecx
    mov ecx, [rsp + 16]
    mov dword ptr [rip + dirent_tmp + 20], 0
    mov [rip + dirent_tmp + 20], cl
    lea rsi, [rip + dirent_tmp]
    mov edx, 24
    call .Lrd_put
    mov rsi, [rsp + 8]
    inc rsi
    mov rdx, [rsp + 24]
    call .Lrd_put
    cmp r15, r14
    jae 7f
    mov rcx, [rsp]
    inc rcx
    mov rsi, [rsp + 8]
    inc rsi
    add rsi, [rsp + 24]
    inc rsi
    jmp 3b
7:  mov edi, [r12 + 32]
    mov esi, 4
    push rbx
    mov rbx, [rip + g_wasm_caller]
    call wmem
    pop rbx
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov [rax], r15d
    xor ecx, ecx
9:  ANSWER
# copy rdx bytes from rsi to the output, as many as fit
.Lrd_put:
    mov rcx, r14
    sub rcx, r15
    cmp rdx, rcx
    cmova rdx, rcx
    lea rdi, [r13 + r15]
    add r15, rdx
    jmp memcpy

# dir_each's callback(ctx, name, is_dir): type byte, name, NUL
readdir_entry:
    push rbx
    mov rbx, rsi
    mov eax, 4
    test edx, edx
    jz 1f
    mov eax, 3
1:  mov esi, eax
    lea rdi, [rip + wasi_list]
    call sb_push_byte
    lea rdi, [rip + wasi_list]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + wasi_list]
    xor esi, esi
    call sb_push_byte
    inc qword ptr [rip + list_count]
    xor eax, eax
    pop rbx
    ret

# poll_oneoff(subscriptions*, events*, count, nevents*): waits until a clock is due or the standard
# input can be read; reads of other descriptors and every write are ready at once
w_poll_oneoff:
    PROLOGUE 80
    mov r12, rdi
    mov ecx, WE_INVAL
    mov r13d, [r12 + 16]            # subscriptions
    test r13d, r13d
    jz 9f
    cmp r13d, 4096
    ja 9f
    mov edi, [r12]
    imul rsi, r13, 48
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov r14, rax
    mov edi, [r12 + 8]
    imul rsi, r13, 32
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov r15, rax
    # the earliest clock (an absolute monotonic time, -1 none), the standard input's descriptor
    # when a read waits on it (-1 none), and whether something is ready at once
    call time_now_ns
    mov [rsp + 16], rax             # now, at the call
    call time_real_ns
    mov [rsp + 64], rax             # the realtime clock then
    mov qword ptr [rsp + 40], -1    # the earliest deadline
    mov qword ptr [rsp + 8], -1     # the standard input
    mov qword ptr [rsp + 48], 0     # ready at once
    xor ecx, ecx
1:  cmp ecx, r13d
    jae 4f
    imul rdx, rcx, 48
    add rdx, r14
    movzx eax, byte ptr [rdx + 8]
    test eax, eax
    jnz 2f
    call .Lpoll_deadline
    cmp rax, [rsp + 40]
    jae 3f
    mov [rsp + 40], rax
    jmp 3f
2:  cmp eax, 1
    jne 21f
    mov edi, [rdx + 16]
    push rcx
    push rdx
    call wasi_fd
    pop rdx
    pop rcx
    test rax, rax
    jz 21f
    cmp dword ptr [rax + WFD_kind], 1
    jne 21f
    mov eax, [rax + WFD_host]
    mov [rsp + 8], rax
    jmp 3f
21: mov qword ptr [rsp + 48], 1
3:  inc ecx
    jmp 1b
4:  # wait: for the standard input, or until the deadline, or not at all
    call time_now_ns
    mov rdi, [rsp + 40]
    cmp rdi, -1
    je 41f
    sub rdi, rax
    jns 42f
    xor edi, edi
42: add rdi, 999999
    mov rax, rdi
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov rdi, rax                    # ms to the deadline
41: cmp qword ptr [rsp + 48], 0
    je 43f
    xor edi, edi
43: mov qword ptr [rsp + 24], 0     # the input is ready
    cmp qword ptr [rsp + 8], -1
    je 44f
    mov rsi, rdi
    mov rdi, [rsp + 8]
    call wasi_os_wait_read
    mov [rsp + 24], rax
    jmp 6f
44: test rdi, rdi
    jle 6f
    call wasi_os_sleep_ms
6:  # events: ready reads and writes, clocks that are due
    call time_now_ns
    mov [rsp + 32], rax
    xor r9d, r9d                    # events (rbx stays the instance, for wmem)
    xor ecx, ecx
7:  cmp ecx, r13d
    jae 8f
    imul rdx, rcx, 48
    add rdx, r14
    movzx eax, byte ptr [rdx + 8]
    test eax, eax
    jz 71f
    # a read or write: ready unless it is the standard input that did not become readable
    cmp eax, 1
    jne 72f
    mov edi, [rdx + 16]
    push rcx
    push rdx
    push r9
    call wasi_fd
    pop r9
    pop rdx
    pop rcx
    test rax, rax
    jz 72f
    cmp dword ptr [rax + WFD_kind], 1
    jne 72f
    cmp qword ptr [rsp + 24], 0
    je 75f
72: call .Lpoll_event
    mov qword ptr [rdi + 16], 1
    jmp 75f
71: call .Lpoll_deadline
    cmp rax, [rsp + 32]
    ja 75f
    call .Lpoll_event
75: inc ecx
    jmp 7b
8:  test r9d, r9d
    jz 4b                           # woken early: wait for the rest
    mov [rsp + 56], r9
    mov edi, [r12 + 24]
    mov esi, 4
    call wmem
    mov ecx, WE_FAULT
    test rax, rax
    jz 9f
    mov rcx, [rsp + 56]
    mov [rax], ecx
    xor ecx, ecx
9:  ANSWER
# the clock subscription rdx's deadline -> rax (absolute monotonic ns; keeps rcx, rdx): a
# timeout from the call, or a time on its clock (realtime: moved to the monotonic clock)
.Lpoll_deadline:
    mov rax, [rdx + 24]
    test word ptr [rdx + 40], 1
    jnz 1f
    add rax, [rsp + 16 + 8]
    ret
1:  cmp dword ptr [rdx + 16], 0
    jne 2f
    cmp rax, [rsp + 64 + 8]
    ja 3f
    mov rax, [rsp + 16 + 8]         # already past (even before the monotonic clock began): due
    ret
3:  sub rax, [rsp + 64 + 8]
    add rax, [rsp + 16 + 8]
2:  ret
# an event for subscription rdx at events[r9] -> rdi the event
.Lpoll_event:
    mov rdi, r9
    shl rdi, 5
    add rdi, r15
    mov rax, [rdx]
    mov [rdi], rax                  # userdata
    mov qword ptr [rdi + 8], 0
    movzx eax, byte ptr [rdx + 8]
    mov [rdi + 10], al              # type
    mov qword ptr [rdi + 16], 0
    mov qword ptr [rdi + 24], 0
    inc r9d
    ret

# time_real_ns() -> rax: the realtime clock
time_real_ns:
    sub rsp, 24
    mov edi, CLOCK_REALTIME
    mov rsi, rsp
    SYS SYS_clock_gettime
    mov rax, [rsp]
    imul rax, rax, 1000000000
    add rax, [rsp + 8]
    add rsp, 24
    ret

# time_now_ns() -> rax: the monotonic clock
time_now_ns:
    sub rsp, 24
    mov edi, CLOCK_MONOTONIC
    mov rsi, rsp
    SYS SYS_clock_gettime
    mov rax, [rsp]
    imul rax, rax, 1000000000
    add rax, [rsp + 8]
    add rsp, 24
    ret

.ifndef WINDOWS
# wasi_os_lexists(path) -> eax 1 when the name exists, a link counted as itself (not followed)
FN wasi_os_lexists
    sub rsp, 152
    mov rsi, rsp
    SYS SYS_lstat
    add rsp, 152
    xor ecx, ecx
    test rax, rax
    sete cl
    mov eax, ecx
    ret

# wasi_os_random(buf, len) -> 0 or -errno
FN wasi_os_random
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + .Ls_urandom]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 9f
    mov ebx, eax
1:  test r13, r13
    jz 2f
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    SYS SYS_read
    test rax, rax
    jle 3f
    add r12, rax
    sub r13, rax
    jmp 1b
2:  mov edi, ebx
    SYS SYS_close
    xor eax, eax
9:  EPILOGUE
3:  mov edi, ebx
    SYS SYS_close
    mov rax, -EIO
    EPILOGUE

# wasi_os_wait_read(fd, timeout ms or -1) -> rax 1 when it can be read (or reached its end), 0
FN wasi_os_wait_read
    sub rsp, 24
    mov [rsp], edi
    mov word ptr [rsp + 4], POLLIN
    mov word ptr [rsp + 6], 0
    mov edx, esi
    test rsi, rsi
    jns 1f
    mov edx, -1
1:  mov rdi, rsp
    mov esi, 1
    SYS SYS_poll
    cmp rax, -EINTR
    je 1b
    xor ecx, ecx
    test rax, rax
    jle 2f
    mov ecx, 1
2:  mov eax, ecx
    add rsp, 24
    ret

# wasi_os_sleep_ms(ms)
FN wasi_os_sleep_ms
    sub rsp, 24
    mov [rsp + 8], rdi
    mov rdi, rsp
    xor esi, esi
    xor edx, edx
    mov rdx, [rsp + 8]
    xor esi, esi
    SYS SYS_poll
    add rsp, 24
    ret
.endif

.bss
.p2align 3
stat_tmp: .zero 160
dirent_tmp: .zero 32
list_count: .quad 0

.section .rodata
.Lo_dir: .asciz "--dir"
.Lo_dir_ro: .asciz "--dir-ro"
.Ls_start: .ascii "_start"
.Ls_wasi: .asciz "wasi_snapshot_preview1"
.Ls_urandom: .asciz "/dev/urandom"
.Ls_pwd: .asciz "PWD=/"
.Lm_usage: .asciz "usage: rhun --wasm-host [--dir PATH | --dir-ro PATH]... FILE.wasm [ARG...]"
.Lm_unreadable: .asciz "rhun --wasm-host: cannot read the module"
.Lm_invalid: .asciz "rhun --wasm-host: the module cannot run: "
.Lm_no_start: .asciz "rhun --wasm-host: the module has no _start (a wasm32-wasip1 command)"
.Lm_trap: .asciz "rhun --wasm-host: trap: "
# WASI filetype per descriptor kind: free, standard stream (unknown), directory, regular file
.Lkind_types: .byte 0, 0, 3, 4
# Linux errno -> WASI errno, 0 to 40
.Lerrnos:
    .byte 0, 63, 44, 71, 27, 29, 60, 1, 45, 8, 12, 6, 48, 2, 21, 29
    .byte 10, 20, 75, 43, 54, 31, 28, 41, 33, 59, 74, 22, 51, 70, 69, 34
    .byte 64, 18, 68, 16, 37, 46, 52, 55, 32

# signatures: parameter count, result count, then the types (i = i32, I = i64)
.Lsig_i_i: .byte 1, 1, 0x7f, 0x7f
.Lsig_ii_i: .byte 2, 1, 0x7f, 0x7f, 0x7f
.Lsig_iii_i: .byte 3, 1, 0x7f, 0x7f, 0x7f, 0x7f
.Lsig_iiii_i: .byte 4, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f
.Lsig_iiiii_i: .byte 5, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f
.Lsig_iiiiii_i: .byte 6, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f
.Lsig_iiiiiii_i: .byte 7, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f
.Lsig_iLi_i: .byte 3, 1, 0x7f, 0x7e, 0x7f, 0x7f
.Lsig_iL_i: .byte 2, 1, 0x7f, 0x7e, 0x7f
.Lsig_iLL_i: .byte 3, 1, 0x7f, 0x7e, 0x7e, 0x7f
.Lsig_iLLi_i: .byte 4, 1, 0x7f, 0x7e, 0x7e, 0x7f, 0x7f
.Lsig_iiiLi_i: .byte 5, 1, 0x7f, 0x7f, 0x7f, 0x7e, 0x7f, 0x7f
.Lsig_iLii_i: .byte 4, 1, 0x7f, 0x7e, 0x7f, 0x7f, 0x7f
.Lsig_iiiiLLi_i: .byte 7, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7e, 0x7e, 0x7f, 0x7f
.Lsig_open: .byte 9, 1, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7e, 0x7e, 0x7f, 0x7f, 0x7f
.Lsig_i_: .byte 1, 0, 0x7f
.Lsig__i: .byte 0, 1, 0x7f

.p2align 3
# name, host function, signature
wasi_table:
    .quad .Ln_args_get, w_args_get, .Lsig_ii_i
    .quad .Ln_args_sizes_get, w_args_sizes_get, .Lsig_ii_i
    .quad .Ln_environ_get, w_environ_get, .Lsig_ii_i
    .quad .Ln_environ_sizes_get, w_environ_sizes_get, .Lsig_ii_i
    .quad .Ln_clock_res_get, w_clock_res_get, .Lsig_ii_i
    .quad .Ln_clock_time_get, w_clock_time_get, .Lsig_iLi_i
    .quad .Ln_fd_advise, w_fd_ok, .Lsig_iLLi_i
    .quad .Ln_fd_allocate, w_fd_ok, .Lsig_iLL_i
    .quad .Ln_fd_close, w_fd_close, .Lsig_i_i
    .quad .Ln_fd_datasync, w_fd_sync, .Lsig_i_i
    .quad .Ln_fd_fdstat_get, w_fd_fdstat_get, .Lsig_ii_i
    .quad .Ln_fd_fdstat_set_flags, w_fd_fdstat_set_flags, .Lsig_ii_i
    .quad .Ln_fd_fdstat_set_rights, w_fd_ok, .Lsig_iLL_i
    .quad .Ln_fd_filestat_get, w_fd_filestat_get, .Lsig_ii_i
    .quad .Ln_fd_filestat_set_size, w_fd_filestat_set_size, .Lsig_iL_i
    .quad .Ln_fd_filestat_set_times, wasi_nosys, .Lsig_iLLi_i
    .quad .Ln_fd_pread, w_fd_pread, .Lsig_iiiLi_i
    .quad .Ln_fd_prestat_get, w_fd_prestat_get, .Lsig_ii_i
    .quad .Ln_fd_prestat_dir_name, w_fd_prestat_dir_name, .Lsig_iii_i
    .quad .Ln_fd_pwrite, w_fd_pwrite, .Lsig_iiiLi_i
    .quad .Ln_fd_read, w_fd_read, .Lsig_iiii_i
    .quad .Ln_fd_readdir, w_fd_readdir, .Lsig_iiiLi_i
    .quad .Ln_fd_renumber, wasi_nosys, .Lsig_ii_i
    .quad .Ln_fd_seek, w_fd_seek, .Lsig_iLii_i
    .quad .Ln_fd_sync, w_fd_sync, .Lsig_i_i
    .quad .Ln_fd_tell, w_fd_tell, .Lsig_ii_i
    .quad .Ln_fd_write, w_fd_write, .Lsig_iiii_i
    .quad .Ln_path_create_directory, w_path_create_directory, .Lsig_iii_i
    .quad .Ln_path_filestat_get, w_path_filestat_get, .Lsig_iiiii_i
    .quad .Ln_path_filestat_set_times, wasi_nosys, .Lsig_iiiiLLi_i
    .quad .Ln_path_link, wasi_nosys, .Lsig_iiiiiii_i
    .quad .Ln_path_open, w_path_open, .Lsig_open
    .quad .Ln_path_readlink, wasi_nosys, .Lsig_iiiiii_i
    .quad .Ln_path_remove_directory, w_path_remove_directory, .Lsig_iii_i
    .quad .Ln_path_rename, w_path_rename, .Lsig_iiiiii_i
    .quad .Ln_path_symlink, wasi_nosys, .Lsig_iiiii_i
    .quad .Ln_path_unlink_file, w_path_unlink_file, .Lsig_iii_i
    .quad .Ln_poll_oneoff, w_poll_oneoff, .Lsig_iiii_i
    .quad .Ln_proc_exit, w_proc_exit, .Lsig_i_
    .quad .Ln_proc_raise, wasi_nosys, .Lsig_i_i
    .quad .Ln_random_get, w_random_get, .Lsig_ii_i
    .quad .Ln_sched_yield, w_sched_yield, .Lsig__i
    .quad .Ln_sock_accept, wasi_nosys, .Lsig_iii_i
    .quad .Ln_sock_recv, wasi_nosys, .Lsig_iiiiii_i
    .quad .Ln_sock_send, wasi_nosys, .Lsig_iiiii_i
    .quad .Ln_sock_shutdown, wasi_nosys, .Lsig_ii_i
    .quad 0, 0, 0
.Ln_args_get: .asciz "args_get"
.Ln_args_sizes_get: .asciz "args_sizes_get"
.Ln_environ_get: .asciz "environ_get"
.Ln_environ_sizes_get: .asciz "environ_sizes_get"
.Ln_clock_res_get: .asciz "clock_res_get"
.Ln_clock_time_get: .asciz "clock_time_get"
.Ln_fd_advise: .asciz "fd_advise"
.Ln_fd_allocate: .asciz "fd_allocate"
.Ln_fd_close: .asciz "fd_close"
.Ln_fd_datasync: .asciz "fd_datasync"
.Ln_fd_fdstat_get: .asciz "fd_fdstat_get"
.Ln_fd_fdstat_set_flags: .asciz "fd_fdstat_set_flags"
.Ln_fd_fdstat_set_rights: .asciz "fd_fdstat_set_rights"
.Ln_fd_filestat_get: .asciz "fd_filestat_get"
.Ln_fd_filestat_set_size: .asciz "fd_filestat_set_size"
.Ln_fd_filestat_set_times: .asciz "fd_filestat_set_times"
.Ln_fd_pread: .asciz "fd_pread"
.Ln_fd_prestat_get: .asciz "fd_prestat_get"
.Ln_fd_prestat_dir_name: .asciz "fd_prestat_dir_name"
.Ln_fd_pwrite: .asciz "fd_pwrite"
.Ln_fd_read: .asciz "fd_read"
.Ln_fd_readdir: .asciz "fd_readdir"
.Ln_fd_renumber: .asciz "fd_renumber"
.Ln_fd_seek: .asciz "fd_seek"
.Ln_fd_sync: .asciz "fd_sync"
.Ln_fd_tell: .asciz "fd_tell"
.Ln_fd_write: .asciz "fd_write"
.Ln_path_create_directory: .asciz "path_create_directory"
.Ln_path_filestat_get: .asciz "path_filestat_get"
.Ln_path_filestat_set_times: .asciz "path_filestat_set_times"
.Ln_path_link: .asciz "path_link"
.Ln_path_open: .asciz "path_open"
.Ln_path_readlink: .asciz "path_readlink"
.Ln_path_remove_directory: .asciz "path_remove_directory"
.Ln_path_rename: .asciz "path_rename"
.Ln_path_symlink: .asciz "path_symlink"
.Ln_path_unlink_file: .asciz "path_unlink_file"
.Ln_poll_oneoff: .asciz "poll_oneoff"
.Ln_proc_exit: .asciz "proc_exit"
.Ln_proc_raise: .asciz "proc_raise"
.Ln_random_get: .asciz "random_get"
.Ln_sched_yield: .asciz "sched_yield"
.Ln_sock_accept: .asciz "sock_accept"
.Ln_sock_recv: .asciz "sock_recv"
.Ln_sock_send: .asciz "sock_send"
.Ln_sock_shutdown: .asciz "sock_shutdown"
