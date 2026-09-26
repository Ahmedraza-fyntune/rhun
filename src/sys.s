# syscall wrappers, process env, logging, files, time
.include "rhun.inc"

.bss
.globl g_argc, g_argv, g_envp
g_argc: .quad 0
g_argv: .quad 0
g_envp: .quad 0
.p2align 4
ts_buf: .zero 16
stat_buf: .zero 144
tmp_path: .zero 4096

.text

# sys_init(rsp_at_start): record argc/argv/envp
FN sys_init
    mov rax, [rdi]
    mov [rip + g_argc], rax
    lea rcx, [rdi + 8]
    mov [rip + g_argv], rcx
    lea rcx, [rcx + rax*8 + 8]
    mov [rip + g_envp], rcx
    ret

# getenv(name) -> value cstr or 0
FN getenv
    push rbx
    mov rbx, [rip + g_envp]
.Lge_next:
    mov rsi, [rbx]
    test rsi, rsi
    jz .Lge_none
    mov rcx, rdi
.Lge_cmp:
    mov al, [rcx]
    test al, al
    jz .Lge_endname
    cmp al, [rsi]
    jne .Lge_skip
    inc rcx
    inc rsi
    jmp .Lge_cmp
.Lge_endname:
    cmp byte ptr [rsi], '='
    jne .Lge_skip
    lea rax, [rsi + 1]
    pop rbx
    ret
.Lge_skip:
    add rbx, 8
    jmp .Lge_next
.Lge_none:
    xor eax, eax
    pop rbx
    ret

FN sys_exit
    SYS SYS_exit_group

# write_all(fd, ptr, len) -> 0 or -errno
FN write_all
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
.Lwa_loop:
    test r13, r13
    jz .Lwa_ok
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    SYS SYS_write
    cmp rax, -EINTR
    je .Lwa_loop
    cmp rax, -EAGAIN
    je .Lwa_loop
    test rax, rax
    js .Lwa_ret
    add r12, rax
    sub r13, rax
    jmp .Lwa_loop
.Lwa_ok:
    xor eax, eax
.Lwa_ret:
    pop r13
    pop r12
    pop rbx
    ret

# log_write(ptr, len) -> stderr
FN log_write
    mov rdx, rsi
    mov rsi, rdi
    mov edi, 2
    jmp write_all

# log_cstr(s)
FN log_cstr
    push rdi
    call strlen
    pop rdi
    mov rsi, rax
    jmp log_write

# log_u64(v)
FN log_u64
    sub rsp, 40
    mov rsi, rdi
    mov rdi, rsp
    call fmt_u64
    mov rdi, rsp
    mov rsi, rax
    call log_write
    add rsp, 40
    ret

# log_hex(v)
FN log_hex
    sub rsp, 40
    mov rsi, rdi
    mov rdi, rsp
    call fmt_hex
    mov rdi, rsp
    mov rsi, rax
    call log_write
    add rsp, 40
    ret

FN log_nl
    push 10
    mov rdi, rsp
    mov esi, 1
    call log_write
    pop rax
    ret

# die(msg cstr)
FN die
    call log_cstr
    call log_nl
    mov edi, 1
    jmp sys_exit

# time_ms() -> monotonic milliseconds
FN time_ms
    mov edi, CLOCK_MONOTONIC
    lea rsi, [rip + ts_buf]
    SYS SYS_clock_gettime
    mov rax, [rip + ts_buf]
    imul rax, rax, 1000
    mov rcx, rax
    mov rax, [rip + ts_buf + 8]
    xor edx, edx
    mov r8d, 1000000
    div r8
    add rax, rcx
    ret

# time_now() -> unix seconds
FN time_now
    mov edi, CLOCK_REALTIME
    lea rsi, [rip + ts_buf]
    SYS SYS_clock_gettime
    mov rax, [rip + ts_buf]
    ret

# file_open_read(path) -> fd or -errno
FN file_open_read
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    ret

# file_size(fd) -> size or -errno
FN file_size
    lea rsi, [rip + stat_buf]
    SYS SYS_fstat
    test rax, rax
    js 1f
    mov rax, [rip + stat_buf + 48]
1:  ret

# file_mtime(path) -> unix seconds (0 on error)
FN file_mtime
    lea rsi, [rip + stat_buf]
    SYS SYS_lstat
    test rax, rax
    js 1f
    mov rax, [rip + stat_buf + 88]
    ret
1:  xor eax, eax
    ret

# file_is_dir(path) -> 1/0
FN file_is_dir
    lea rsi, [rip + stat_buf]
    mov eax, 4          # stat (follows symlinks)
    syscall
    test rax, rax
    js 1f
    mov eax, [rip + stat_buf + 24]
    and eax, 0xf000
    cmp eax, 0x4000
    sete al
    movzx eax, al
    ret
1:  xor eax, eax
    ret

# file_read_all(path) -> rax=ptr (NUL-terminated, mem_alloc'd) rdx=len; rax=0 on error
FN file_read_all
    PROLOGUE
    call file_open_read
    test rax, rax
    js .Lfr_fail
    mov ebx, eax
    mov edi, eax
    call file_size
    test rax, rax
    js .Lfr_close_fail
    mov r12, rax            # size
    lea rdi, [rax + 1]
    call mem_alloc
    mov r13, rax            # buf
    xor r14d, r14d          # read so far
.Lfr_loop:
    cmp r14, r12
    jae .Lfr_done
    mov edi, ebx
    lea rsi, [r13 + r14]
    mov rdx, r12
    sub rdx, r14
    SYS SYS_read
    cmp rax, -EINTR
    je .Lfr_loop
    test rax, rax
    js .Lfr_free_fail
    jz .Lfr_done
    add r14, rax
    jmp .Lfr_loop
.Lfr_done:
    mov byte ptr [r13 + r14], 0
    mov edi, ebx
    SYS SYS_close
    mov rax, r13
    mov rdx, r14
    EPILOGUE
.Lfr_free_fail:
    mov rdi, r13
    call mem_free
.Lfr_close_fail:
    mov edi, ebx
    SYS SYS_close
.Lfr_fail:
    xor eax, eax
    xor edx, edx
    EPILOGUE

# file_write_all(path, ptr, len) -> 0 or -errno
# writes path.rhun-tmp then renames over path, keeping the original mode
FN file_write_all
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    # mode of existing file (default 0644)
    mov r15d, 0644
    lea rsi, [rip + stat_buf]
    mov eax, 4
    syscall
    test rax, rax
    js 1f
    mov r15d, [rip + stat_buf + 24]
    and r15d, 07777
1:
    # tmp path = path + ".rhun-tmp"
    mov rdi, r12
    call strlen
    cmp rax, 4000
    ja .Lfw_toolong
    mov rcx, rax
    lea rdi, [rip + tmp_path]
    mov rsi, r12
    rep movsb
    lea rsi, [rip + .Ltmp_suffix]
    mov ecx, 10
    rep movsb
    lea rdi, [rip + tmp_path]
    mov esi, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC
    mov edx, r15d
    SYS SYS_open
    test rax, rax
    js .Lfw_ret
    mov ebx, eax
    mov edi, eax
    mov esi, r15d
    SYS SYS_fchmod
    mov edi, ebx
    mov rsi, r13
    mov rdx, r14
    call write_all
    test rax, rax
    js .Lfw_err_close
    mov edi, ebx
    SYS SYS_fsync
    mov edi, ebx
    SYS SYS_close
    lea rdi, [rip + tmp_path]
    mov rsi, r12
    SYS SYS_rename
    test rax, rax
    js .Lfw_unlink
    xor eax, eax
    EPILOGUE
.Lfw_err_close:
    mov r15, rax
    mov edi, ebx
    SYS SYS_close
    mov rax, r15
.Lfw_unlink:
    mov r15, rax
    lea rdi, [rip + tmp_path]
    SYS SYS_unlink
    mov rax, r15
.Lfw_ret:
    EPILOGUE
.Lfw_toolong:
    mov rax, -36
    EPILOGUE

.section .rodata
.Ltmp_suffix: .asciz ".rhun-tmp"
.text

# mkdir_p(path) : creates path and parents (path buffer is modified then restored)
FN mkdir_p
    PROLOGUE
    mov r12, rdi
    lea rbx, [rdi + 1]
.Lmk_loop:
    mov al, [rbx]
    test al, al
    jz .Lmk_last
    cmp al, '/'
    jne .Lmk_next
    mov byte ptr [rbx], 0
    mov rdi, r12
    mov esi, 0755
    SYS SYS_mkdir
    mov byte ptr [rbx], '/'
.Lmk_next:
    inc rbx
    jmp .Lmk_loop
.Lmk_last:
    mov rdi, r12
    mov esi, 0755
    SYS SYS_mkdir
    EPILOGUE
