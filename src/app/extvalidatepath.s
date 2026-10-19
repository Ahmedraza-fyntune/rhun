# Rooted no-follow managed filesystem access. Handles are owned unless stated otherwise.
.include "rhun.inc"
.include "app/extvalidate.inc"
.text
# Bounded C-string length; readable terminated strings are an internal caller contract.
FN ext_root_length
    test rdi, rdi
    jz .Lerl_bad
    xor eax, eax
1:  cmp rax, rsi
    ja .Lerl_long
    cmp byte ptr [rdi + rax], 0
    je 9f
    inc rax
    jmp 1b
.Lerl_bad:
    mov rax, -22
9:  ret
.Lerl_long:
    mov rax, -36
    ret

# ext_root_name(single basename) -> positive UTF8 byte count or negative errno.
FN ext_root_name
    PROLOGUE 32
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lern_bad
    mov r12, rax
    cmp rax, 1
    jne 1f
    cmp byte ptr [rbx], '.'
    je .Lern_bad
1:  cmp r12, 2
    jne 2f
    cmp word ptr [rbx], 0x2e2e
    je .Lern_bad
2:  mov rdi, rbx
    mov rsi, r12
    call snippet_utf8_valid
    test eax, eax
    jz .Lern_bad
    xor r13d, r13d
.Lern_scalar:
    lea rdi, [rbx + r13]
    mov rsi, r12
    sub rsi, r13
    call utf8_decode
    cmp eax, 127
    jb .Lern_scalar_next
    cmp eax, 160
    jb .Lern_bad
.Lern_scalar_next:
    add r13, rdx
    cmp r13, r12
    jb .Lern_scalar
    xor ecx, ecx
3:  movzx eax, byte ptr [rbx + rcx]
    cmp eax, 32
    jb .Lern_bad
    cmp eax, 127
    je .Lern_bad
    cmp eax, '/'
    je .Lern_bad
.ifdef WINDOWS
    cmp eax, 92
    je .Lern_bad
    cmp eax, ':'
    je .Lern_bad
    cmp eax, '<'
    je .Lern_bad
    cmp eax, '>'
    je .Lern_bad
    cmp eax, '"'
    je .Lern_bad
    cmp eax, '|'
    je .Lern_bad
    cmp eax, '?'
    je .Lern_bad
    cmp eax, '*'
    je .Lern_bad
.endif
    inc rcx
    cmp rcx, r12
    jb 3b
.ifdef WINDOWS
    mov al, [rbx + r12 - 1]
    cmp al, '.'
    je .Lern_bad
    cmp al, ' '
    je .Lern_bad
    xor ecx, ecx
4:  cmp rcx, r12
    jae 5f
    cmp byte ptr [rbx + rcx], '.'
    je 5f
    inc rcx
    jmp 4b
5:  test rcx, rcx
    jz .Lern_ok
    cmp byte ptr [rbx + rcx - 1], ' '
    jne 6f
    dec rcx
    jmp 5b
6:  cmp rcx, 8
    ja .Lern_ok
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    xor edx, edx
7:  cmp rdx, rcx
    jae 8f
    mov al, [rbx + rdx]
    cmp al, 'A'
    jb 71f
    cmp al, 'Z'
    ja 71f
    or al, 32
71: mov [rsp + rdx], al
    inc rdx
    jmp 7b
8:  cmp rcx, 3
    jne 81f
    mov eax, [rsp]
    cmp eax, 0x006e6f63         # con
    je .Lern_bad
    cmp eax, 0x006e7270         # prn
    je .Lern_bad
    cmp eax, 0x00787561         # aux
    je .Lern_bad
    cmp eax, 0x006c756e         # nul
    je .Lern_bad
81: cmp rcx, 6
    jne 82f
    cmp dword ptr [rsp], 0x636f6c63 # cloc
    jne 82f
    cmp word ptr [rsp + 4], 0x246b # k$
    je .Lern_bad
82: cmp rcx, 6
    jne 83f
    cmp dword ptr [rsp], 0x696e6f63 # coni
    jne 83f
    cmp word ptr [rsp + 4], 0x246e # n$
    je .Lern_bad
83: cmp rcx, 7
    jne 84f
    cmp dword ptr [rsp], 0x6f6e6f63 # cono
    jne 84f
    cmp word ptr [rsp + 4], 0x7475 # ut
    jne 84f
    cmp byte ptr [rsp + 6], '$'
    je .Lern_bad
84: cmp rcx, 4
    je 85f
    cmp rcx, 5
    jne .Lern_ok
85: mov eax, [rsp]
    and eax, 0xffffff
    cmp eax, 0x6d6f63          # com
    je 86f
    cmp eax, 0x74706c          # lpt
    jne .Lern_ok
86: cmp rcx, 4
    jne 87f
    mov al, [rsp + 3]
    cmp al, '1'
    jb .Lern_ok
    cmp al, '9'
    jbe .Lern_bad
    jmp .Lern_ok
87: cmp byte ptr [rsp + 3], 0xc2
    jne .Lern_ok
    mov al, [rsp + 4]
    cmp al, 0xb9
    je .Lern_bad
    cmp al, 0xb2
    je .Lern_bad
    cmp al, 0xb3
    je .Lern_bad
.endif
.Lern_ok:
    mov rax, r12
    EPILOGUE
.Lern_bad:
    mov rax, -22
    EPILOGUE

# ext_root_open(absolute directory) -> owned raw handle/-errno.
FN ext_root_open
.ifdef WINDOWS
    jmp win_ext_root_open
.else
    PROLOGUE 4112
    mov qword ptr [rsp + 4096], 0 # first mandatory cleanup error
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lero_bad
    cmp byte ptr [rbx], '/'
    jne .Lero_bad
    mov r12, rax
    mov rdi, rsp
    mov rsi, rbx
    lea rdx, [rax + 1]
    call memcpy
    lea rdi, [rip + .Ler_slash]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
    xor edx, edx
1:  SYS SYS_open
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js .Lero_done
    mov r13, rax
    mov r14d, 1
.Lero_next:
    cmp r14, r12
    jae .Lero_success
    cmp byte ptr [rsp + r14], '/'
    jne 2f
    inc r14
    jmp .Lero_next
2:  mov r15, r14
3:  cmp r14, r12
    jae 4f
    cmp byte ptr [rsp + r14], '/'
    je 4f
    inc r14
    jmp 3b
4:  mov byte ptr [rsp + r14], 0
    mov rdi, r13
    lea rsi, [rsp + r15]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    mov r15, rax
    mov [rsp + 4096], rdx
    mov rdi, r13
    call ext_root_close
    test rax, rax
    jns .Lero_parent_closed
    cmp qword ptr [rsp + 4096], 0
    jne .Lero_parent_closed
    mov [rsp + 4096], rax
.Lero_parent_closed:
    test r15, r15
    js 5f
    cmp qword ptr [rsp + 4096], 0
    jne .Lero_close_new
    mov r13, r15
    inc r14
    jmp .Lero_next
5:  mov rax, r15
    jmp .Lero_done
.Lero_close_new:
    mov r13, [rsp + 4096]
    mov rdi, r15
    call ext_root_close
    mov rax, r13
    jmp .Lero_done
.Lero_success:
    mov rax, r13
    jmp .Lero_done
.Lero_bad:
    mov rax, -22
.Lero_done:
    mov rdx, [rsp + 4096]
    EPILOGUE
.endif

# ext_root_open_at(parent,name,kind,flags,mode). Single component, no heap.
FN ext_root_open_at
.ifdef WINDOWS
    jmp win_ext_root_open_at
.else
    PROLOGUE 160
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rdi, rsi
    call ext_root_name
    test rax, rax
    js .Lerat_done
    cmp r13, ER_FILE
    jb .Lerat_bad
    cmp r13, ER_ANY
    ja .Lerat_bad
    test r14, -16
    jnz .Lerat_bad
    test r14, ER_EXCL
    jz 1f
    test r14, ER_CREATE
    jz .Lerat_bad
1:  cmp r13, ER_ANY
    jne 2f
    test r14, 7
    jnz .Lerat_bad
2:  cmp r13, ER_DIR
    jne .Lerat_open
    test r14, ER_WRITE
    jnz .Lerat_bad
    test r14, ER_CREATE
    jz .Lerat_open
.Lerat_mkdir:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
.ifdef MACOS
    call mac_ext_mkdir_at
.else
    SYS 258                   # mkdirat, independent from ordinary pathname helpers
.endif
    cmp rax, -EINTR
    je .Lerat_mkdir
    test rax, rax
    jz .Lerat_open
    cmp rax, -17
    jne .Lerat_done
    test r14, ER_EXCL
    jnz .Lerat_done
.Lerat_open:
    mov rdi, rbx
    mov rsi, r12
    mov edx, O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
    cmp r13, ER_DIR
    jne 3f
    or edx, O_DIRECTORY
    jmp 4f
3:  test r14, ER_WRITE
    jz 31f
    or edx, O_RDWR
31: test r14, ER_CREATE
    jz 4f
    or edx, O_CREAT
    test r14, ER_EXCL
    jz 4f
    or edx, O_EXCL
4:  mov r10, r15
    SYS SYS_openat
    cmp rax, -EINTR
    je .Lerat_open
    test rax, rax
    js .Lerat_done
    mov r15, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Lerat_close
    cmp r13, ER_ANY
    je .Lerat_good
    cmp [rsp + ER_kind], r13
    je .Lerat_good
    mov rax, -20
    cmp r13, ER_DIR
    je .Lerat_close
    mov rax, -21
.Lerat_close:
    mov r12, rax
    mov rdi, r15
    call ext_root_close
    mov rdx, rax
    mov rax, r12
    EPILOGUE
.Lerat_good:
    mov rax, r15
    jmp .Lerat_done
.Lerat_bad:
    mov rax, -22
.Lerat_done:
    xor edx, edx
    EPILOGUE
.endif

FN ext_root_close
.ifdef WINDOWS
    jmp win_ext_root_close
.else
    SYS SYS_close              # Darwin also retires any fdopendir stream state
    mov edx, 1                # consumed, including Linux close errors
.ifdef MACOS
    test rax, rax
    jns 1f
    cmp rax, -9
    je 1f
    mov edx, 2                # POSIX close error can leave descriptor state unknown
1:
.endif
    ret
.endif

FN ext_root_stat
.ifdef WINDOWS
    jmp win_ext_root_stat
.else
    PROLOGUE 144
    mov rbx, rsi
    mov rsi, rsp
1:  SYS SYS_fstat
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js .Lerst_done
    mov eax, [rsp + 24]
    and eax, 0xf000
    mov ecx, ER_FILE
    cmp eax, 0x8000
    je 2f
    mov ecx, ER_DIR
    cmp eax, 0x4000
    jne .Lerst_bad
2:  mov [rbx + ER_kind], rcx
    mov rax, [rsp + 48]
    test rax, rax
    js .Lerst_bad
    mov [rbx + ER_size], rax
    mov eax, [rsp + 24]
    and eax, 0x49
    mov [rbx + ER_exec], rax
    mov qword ptr [rbx + 24], 0
    xor eax, eax
    jmp .Lerst_done
.Lerst_bad:
    mov rax, -22
.Lerst_done:
    EPILOGUE
.endif

FN ext_root_identity
.ifdef WINDOWS
    jmp win_ext_root_identity
.else
    PROLOGUE 176
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rsp + 144]
    call ext_root_stat
    test rax, rax
    js 9f
    mov rdi, rbx
    mov rsi, rsp
1:  SYS SYS_fstat
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    mov rax, [rsp]
    mov [r12], rax
    mov rax, [rsp + 8]
    mov [r12 + 8], rax
    mov qword ptr [r12 + 16], 0
    mov qword ptr [r12 + 24], 0
    xor eax, eax
9:  EPILOGUE
.endif

# One native attempt, for callers with an explicit shared retry budget.
FN ext_root_read_once
.ifdef WINDOWS
    jmp win_ext_root_read
.else
    mov r10, rcx
    SYS SYS_pread
    ret
.endif

FN ext_root_read
.ifdef WINDOWS
    jmp win_ext_root_read
.else
    mov r10, rcx
1:  SYS SYS_pread
    cmp rax, -EINTR
    je 1b
    ret
.endif

# Store ownership before classification. No hidden close on a later failure.
FN ext_root_reopen_dir_into
.ifdef WINDOWS
    jmp win_ext_root_reopen_dir_into
.else
    PROLOGUE ER_STAT_SIZE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .Leri_bad
    cmp qword ptr [r12], -1
    jne .Leri_bad
    mov r13d, 128
1:  mov rdi, rbx
    lea rsi, [rip + .Ler_dot]
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
    xor r10d, r10d
    SYS SYS_openat
    cmp rax, -EINTR
    jne 2f
    dec r13
    jnz 1b
2:  test rax, rax
    js .Leri_done
    mov [r12], rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Leri_done
    cmp qword ptr [rsp + ER_kind], ER_DIR
    jne .Leri_not_dir
    xor eax, eax
.Leri_done:
    xor edx, edx
    EPILOGUE
.Leri_not_dir:
    mov rax, -20
    jmp .Leri_done
.Leri_bad:
    mov rax, -22
    jmp .Leri_done
.endif

FN ext_root_reopen_dir
.ifdef WINDOWS
    jmp win_ext_root_reopen_dir
.else
    PROLOGUE 32
    lea rsi, [rip + .Ler_dot]
    mov edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
    xor r10d, r10d
1:  SYS SYS_openat
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    mov rbx, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js 8f
    cmp qword ptr [rsp + ER_kind], ER_DIR
    jne 7f
    mov rax, rbx
    jmp 9f
7:  mov rax, -20
8:  mov r12, rax
    mov rdi, rbx
    call ext_root_close
    mov rdx, rax
    mov rax, r12
    EPILOGUE
9:  xor edx, edx
    EPILOGUE
.endif
.section .rodata
.Ler_slash: .asciz "/"
.Ler_dot: .asciz "."
