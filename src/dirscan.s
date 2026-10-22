# Strict, bounded directory enumeration. Callbacks collect private results and
# must discard them on any error. Final-component no-follow only, not ancestors.
.include "rhun.inc"
.text
# dir_scan_path_check(path) -> 0 or -errno. Never modify the input. A trailing
# separator requires canonical root syntax, preventing link/ from bypassing
# the native final-component no-follow open.
FN dir_scan_path_check
    test rdi, rdi
    jz .Ldsp_invalid
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0
    je 2f
    inc ecx
    cmp ecx, 4096
    jb 1b
    mov rax, -36
    ret
2:  test ecx, ecx
    jz .Ldsp_ok
    mov al, [rdi + rcx - 1]
    call .Ldsp_separator
    test al, al
    jz .Ldsp_ok
    cmp ecx, 1
    je .Ldsp_ok
.ifdef WINDOWS
    cmp ecx, 3
    jne 3f
    cmp byte ptr [rdi + 1], ':'
    jne 3f
    mov al, [rdi]
    call .Ldsp_drive
    test al, al
    jnz .Ldsp_ok
3:  cmp ecx, 5
    jb .Ldsp_invalid
    mov al, [rdi]
    call .Ldsp_separator
    test al, al
    jz .Ldsp_invalid
    mov al, [rdi + 1]
    call .Ldsp_separator
    test al, al
    jz .Ldsp_invalid
    lea r10, [rdi + rcx]
    lea rsi, [rdi + 2]
    cmp byte ptr [rdi + 2], '?'
    je .Ldsp_namespace
    cmp byte ptr [rdi + 2], '.'
    jne .Ldsp_unc
.Ldsp_namespace:
    mov al, [rdi + 3]
    call .Ldsp_separator
    test al, al
    jz .Ldsp_invalid
    cmp ecx, 7
    jne 4f
    cmp byte ptr [rdi + 5], ':'
    jne 4f
    mov al, [rdi + 4]
    call .Ldsp_drive
    test al, al
    jnz .Ldsp_ok
4:  cmp byte ptr [rdi + 2], '?'
    jne .Ldsp_invalid
    cmp ecx, 12
    jb .Ldsp_invalid
    mov eax, [rdi + 4]
    or eax, 0x00202020
    and eax, 0x00ffffff
    cmp eax, 0x00636e75       # ASCII UNC, case insensitive
    jne .Ldsp_invalid
    mov al, [rdi + 7]
    call .Ldsp_separator
    test al, al
    jz .Ldsp_invalid
    lea rsi, [rdi + 8]
.Ldsp_unc:
    mov r9d, 2               # server and share, each nonempty and not dot/dotdot
    mov r8, rsi
.Ldsp_component:
    cmp rsi, r10
    jae .Ldsp_invalid
    mov al, [rsi]
    call .Ldsp_separator
    test al, al
    jnz .Ldsp_component_end
    inc rsi
    jmp .Ldsp_component
.Ldsp_component_end:
    mov rax, rsi
    sub rax, r8
    jz .Ldsp_invalid
    cmp rax, 1
    jne 5f
    cmp byte ptr [r8], '.'
    je .Ldsp_invalid
    cmp r9d, 2
    jne 6f
    cmp byte ptr [r8], '?'
    je .Ldsp_invalid
    jmp 6f
5:  cmp rax, 2
    jne 6f
    cmp word ptr [r8], 0x2e2e
    je .Ldsp_invalid
6:  inc rsi
    dec r9d
    jz 7f
    mov r8, rsi
    jmp .Ldsp_component
7:  cmp rsi, r10
    je .Ldsp_ok
.endif
.Ldsp_invalid:
    mov rax, -22
    ret
.Ldsp_ok:
    xor eax, eax
    ret
.Ldsp_separator:
    cmp al, '/'
    je 1f
.ifdef WINDOWS
    cmp al, 92
    sete al
.else
    xor eax, eax
.endif
    ret
1:  mov eax, 1
    ret
.ifdef WINDOWS
.Ldsp_drive:
    or al, 0x20
    cmp al, 'a'
    jb 1f
    cmp al, 'z'
    seta al
    xor al, 1
    ret
1:  xor eax, eax
    ret
.endif

# dir_scan_emit(private DSC, name, length) -> 0 or -errno. Native adapters
# guarantee name[length] is NUL; validate only counted bytes, without overread.
FN dir_scan_emit
    test rdx, rdx
    jz .Ldse_bad
    cmp rdx, 4095
    ja .Ldse_long
    test rsi, rsi
    jz .Ldse_bad
    xor ecx, ecx
1:  mov al, [rsi + rcx]
    test al, al
    jz .Ldse_bad
    cmp al, '/'
    je .Ldse_bad
    inc rcx
    cmp rcx, rdx
    jb 1b
    cmp rdx, 1
    jne 2f
    cmp byte ptr [rsi], '.'
    je .Ldse_skip
2:  cmp rdx, 2
    jne 3f
    cmp word ptr [rsi], 0x2e2e
    je .Ldse_skip
3:  mov rax, [rdi + DSC_count]
    cmp rax, [rdi + DSC_max]
    jae .Ldse_over
    inc qword ptr [rdi + DSC_count]
    PROLOGUE
    mov rax, [rdi + DSC_callback]
    mov rdi, [rdi + DSC_user]
    call rax
    test rax, rax
    jle 4f
    mov rax, -22
4:  EPILOGUE
.Ldse_skip:
    xor eax, eax
    ret
.Ldse_bad:
    mov rax, -5
    ret
.Ldse_long:
    mov rax, -36
    ret
.Ldse_over:
    mov rax, -27
    ret

# dir_scan_try(path, max, callback, user) -> status, callback count.
FN dir_scan_try
    test rdi, rdi
    jz .Lds_invalid
    test rdx, rdx
    jz .Lds_invalid
    cmp rsi, DSC_CAP_MAX
    ja .Lds_invalid
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    call dir_scan_path_check
    test rax, rax
    js .Lds_path_error
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
.ifdef WINDOWS
    call win_dir_scan_try
.else
    call .Lds_posix
.endif
    EPILOGUE
.Lds_path_error:
    xor edx, edx
    EPILOGUE
.Lds_invalid:
    mov rax, -22
    xor edx, edx
    ret


.ifndef WINDOWS
# dir_scan_fd_try(fd,max,callback,user) -> status, callback count.
# Borrowed freshly opened directory descriptor, consumed from its current stream
# position. Caller closes through SYS_close even after failure; never close here.
FN dir_scan_fd_try
    test rdi, rdi
    js .Lds_invalid
    cmp rdi, 0x7fffffff
    ja .Lds_invalid
    test rdx, rdx
    jz .Lds_invalid
    cmp rsi, DSC_CAP_MAX
    ja .Lds_invalid
    PROLOGUE 32832
    mov qword ptr [rsp + 32], 0
    mov [rsp + DSC_max], rsi
    mov qword ptr [rsp + DSC_count], 0
    mov [rsp + DSC_callback], rdx
    mov [rsp + DSC_user], rcx
    mov ebx, edi
    jmp .Lds_opened
.Lds_posix:
    PROLOGUE 32832
    mov qword ptr [rsp + 32], 1 # owns the descriptor
    mov [rsp + DSC_max], rsi
    mov qword ptr [rsp + DSC_count], 0
    mov [rsp + DSC_callback], rdx
    mov [rsp + DSC_user], rcx
    mov esi, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Lds_return
    mov ebx, eax
.Lds_opened:
    lea r12, [rsp + 64]
.Lds_read:
    mov edi, ebx
    mov rsi, r12
    mov edx, 32768
    SYS SYS_getdents64
    cmp rax, -EINTR
    je .Lds_read
    test rax, rax
    jle .Lds_close
    cmp rax, 32768
    ja .Lds_malformed
    mov r14, rax
    xor r13d, r13d
.Lds_record:
    cmp r13, r14
    jae .Lds_read
    mov rax, r14
    sub rax, r13
    cmp rax, 20
    jb .Lds_malformed
    lea rcx, [r12 + r13]
    movzx r15d, word ptr [rcx + 16]
    cmp r15, 20
    jb .Lds_malformed
    cmp r15, rax
    ja .Lds_malformed
    lea rsi, [rcx + 19]
    mov rcx, r15
    sub rcx, 19
    xor edx, edx
1:  cmp byte ptr [rsi + rdx], 0
    je 2f
    inc rdx
    cmp rdx, rcx
    jb 1b
    jmp .Lds_malformed
2:  mov rdi, rsp
    call dir_scan_emit
    test rax, rax
    js .Lds_close
    add r13, r15
    jmp .Lds_record
.Lds_malformed:
    mov rax, -5
.Lds_close:
    cmp qword ptr [rsp + 32], 0
    je .Lds_return
    mov r12, rax
    mov edi, ebx
    SYS SYS_close
    test r12, r12
    jns .Lds_return
    mov rax, r12
.Lds_return:
    mov rdx, [rsp + DSC_count]
    EPILOGUE
.endif
