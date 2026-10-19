# Independent keeper Windows job backend. It never uses the editor-owned proc_spawn job.
.include "win.inc"
.include "app/taskproc.inc"
.text

# UTF8 C string -> owned UTF16, maximum code units including NUL. All allocation is recoverable.
kpw_wide_owned:
    PROLOGUE 128
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + 112], rdx
    cmp qword ptr [rdx], 0
    jne 4f
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz 8f
    mov r13d, eax
    cmp r13, r12
    ja 7f
    lea rdi, [r13 + r13]
    call mem_alloc_try
    test rax, rax
    jz 6f
    mov r14, rax
    mov rdx, [rsp + 112]
    mov [rdx], rax
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov [rsp + 32], r14
    mov [rsp + 40], r13
    API MultiByteToWideChar
    cmp eax, r13d
    jne 5f
    mov rax, r14
    mov rdx, r13
    EPILOGUE
5:
8:  call win_error
    test rax, rax
    js 9f
    mov rax, -22
9:  EPILOGUE
6:  mov rax, -12
    EPILOGUE
7:  mov rax, -7
    EPILOGUE

4:  mov rax, -16
    EPILOGUE
# Compatibility conversion is restricted to the small PowerShell temporary.
kpw_wide:
    cmp rsi, 4097
    ja 7f
    PROLOGUE 32
    mov qword ptr [rsp], 0
    lea rdx, [rsp]
    call kpw_wide_owned
    test rax, rax
    jns 8f
    mov [rsp + 8], rax
    mov rdi, [rsp]
    call prep_cleanup_free
    mov rax, [rsp + 8]
8:  EPILOGUE
7:  mov rax, -7
    ret

# Bounded CRT argv serializer. Every argument is quoted; target command itself uses EncodedCommand.
kpw_command:
    PROLOGUE 32
    mov r12, rdi
    mov [rsp + 8], rsi
    mov edi, 262144
    call mem_alloc_try
    test rax, rax
    jz .Lkpw_cmd_nomem
    mov rbx, rax
    mov rcx, [rsp + 8]
    mov [rcx + KB_mem + 8], rax
    mov r13, rax
    xor r14d, r14d
.Lkpw_cmd_arg:
    mov r15, [r12 + r14*8]
    test r15, r15
    jz .Lkpw_cmd_end
    cmp r14, 64
    jae .Lkpw_cmd_big
    test r14, r14
    jz 1f
    mov byte ptr [r13], ' '
    inc r13
1:  mov byte ptr [r13], '"'
    inc r13
.Lkpw_cmd_char:
    xor ecx, ecx
2:  movzx eax, byte ptr [r15]
    cmp eax, 92
    je 3f
    test r14, r14
    jnz 4f
    cmp eax, '/'
    jne 4f
3:  inc ecx
    inc r15
    jmp 2b
4:  mov edx, ecx
    test eax, eax
    jz 5f
    cmp eax, '"'
    jne 6f
    lea ecx, [rcx + rcx + 1]
    jmp 6f
5:  add ecx, ecx
6:  test ecx, ecx
    jz 8f
7:  mov byte ptr [r13], 92
    inc r13
    dec ecx
    jnz 7b
8:  test eax, eax
    jz 9f
    mov [r13], al
    inc r13
    inc r15
    jmp .Lkpw_cmd_char
9:  mov byte ptr [r13], '"'
    inc r13
    mov rax, r13
    sub rax, rbx
    cmp rax, 262140
    ja .Lkpw_cmd_big
    inc r14
    jmp .Lkpw_cmd_arg
.Lkpw_cmd_end:
    test r14, r14
    jz .Lkpw_cmd_big
    mov byte ptr [r13], 0
    mov rdi, rbx
    mov esi, 32767
    mov rdx, [rsp + 8]
    add rdx, KB_mem + 24
    call kpw_wide_owned
    EPILOGUE
.Lkpw_cmd_big:
    mov rax, -7
    EPILOGUE
.Lkpw_cmd_nomem:
    mov rax, -12
    EPILOGUE

# Create an exact bounded Unicode environment block, independent of helper startup defaults.
kpw_environment:
    PROLOGUE 128
    mov r12, rdi
    mov [rsp + 104], rsi
    mov edi, 262148
    call mem_alloc_try
    test rax, rax
    jz 7f
    mov rbx, rax
    mov rcx, [rsp + 104]
    mov [rcx + KB_mem], rax
    mov r13, rax
    xor r14d, r14d
1:  mov r15, [r12 + r14*8]
    test r15, r15
    jz 4f
    cmp r14, 1024
    jae 6f
    mov ecx, 65001
    mov edx, 8
    mov r8, r15
    mov r9d, -1
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz 6f
    cmp eax, 32767
    ja 6f
    mov [rsp + 96], eax
    mov rdx, r13
    sub rdx, rbx
    lea rdx, [rdx + rax*2]
    cmp rdx, 262144
    ja 6f
    mov ecx, 65001
    mov edx, 8
    mov r8, r15
    mov r9d, -1
    mov [rsp + 32], r13
    mov eax, [rsp + 96]
    mov [rsp + 40], rax
    API MultiByteToWideChar
    cmp eax, [rsp + 96]
    jne 6f
    lea r13, [r13 + rax*2]
    inc r14
    jmp 1b
4:  mov dword ptr [r13], 0
    mov rax, rbx
    EPILOGUE
6:
    mov rax, -7
    EPILOGUE
7:  mov rax, -12
    EPILOGUE

# Real current-process handle is not serialized; private inheritable duplicates are allowlisted.
kpw_duplicate:
    PROLOGUE 112
    mov r12, rdi
    mov rcx, -1
    mov rdx, r12
    mov r8, -1
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 1
    mov qword ptr [rsp + 48], 2  # DUPLICATE_SAME_ACCESS
    API DuplicateHandle
    test eax, eax
    jz 8f
    mov rax, [rsp + 96]
    EPILOGUE
8:  call win_error
    EPILOGUE

kpw_nowait:
    PROLOGUE 112
    mov rcx, rdi
    mov dword ptr [rsp + 96], 1
    lea rdx, [rsp + 96]
    xor r8d, r8d
    xor r9d, r9d
    API SetNamedPipeHandleState
    test eax, eax
    jz 8f
    xor eax, eax
    EPILOGUE
8:  call win_error
    EPILOGUE

# kpw_spawn(argv,wideEnv,wideCwd,inheritableHandles,count,jobOr0)
# -> exact process handle/-errno, rdx thread handle, r8d PID. Job assignment is atomic at creation.
kpw_spawn:
    PROLOGUE 608
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rsp + 576], r9
    mov [rsp + 584], r10       # private seventh argument: persistent KB
    lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, 480
    call memset
    mov rdi, [r12]
    mov esi, 32767
    mov rdx, [rsp + 584]
    add rdx, KB_mem + 16
    call kpw_wide_owned
    test rax, rax
    js .Lkpw_spawn_fail
    mov [rsp + 256], rax
    mov rcx, rax
1:  movzx eax, word ptr [rcx]
    test eax, eax
    jz 2f
    cmp eax, '/'
    jne 11f
    mov word ptr [rcx], 92
11: add rcx, 2
    jmp 1b
2:  mov rdi, r12
    mov rsi, [rsp + 584]
    call kpw_command
    test rax, rax
    js .Lkpw_spawn_fail
    mov [rsp + 264], rax
    xor ecx, ecx
    mov edx, 1
    cmp qword ptr [rsp + 576], 0
    je 3f
    inc edx
3:  xor r8d, r8d
    lea r9, [rsp + 248]
    API InitializeProcThreadAttributeList
    mov rdi, [rsp + 248]
    test rdi, rdi
    jz .Lkpw_spawn_invalid
    cmp rdi, 65536
    ja .Lkpw_spawn_invalid
    call mem_alloc_try
    test rax, rax
    jz .Lkpw_spawn_nomem
    mov [rsp + 240], rax
    mov rcx, [rsp + 584]
    mov [rcx + KB_mem + 32], rax
    mov rcx, rax
    mov edx, 1
    cmp qword ptr [rsp + 576], 0
    je 4f
    inc edx
4:  xor r8d, r8d
    lea r9, [rsp + 248]
    API InitializeProcThreadAttributeList
    test eax, eax
    jz .Lkpw_spawn_api
    mov qword ptr [rsp + 336], 1
    mov rcx, [rsp + 584]
    mov qword ptr [rcx + KB_attr], 1
    mov rcx, [rsp + 240]
    xor edx, edx
    mov r8d, 0x20002
    mov r9, r15
    lea rax, [rbx*8]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    API UpdateProcThreadAttribute
    test eax, eax
    jz .Lkpw_spawn_api
    cmp qword ptr [rsp + 576], 0
    je 5f
    mov rcx, [rsp + 240]
    xor edx, edx
    mov r8d, 0x2000d
    lea r9, [rsp + 576]
    mov qword ptr [rsp + 32], 8
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    API UpdateProcThreadAttribute
    test eax, eax
    jz .Lkpw_spawn_api
5:  mov dword ptr [rsp + 96], 112
    mov dword ptr [rsp + 156], 0x100
    mov rax, [r15]
    mov [rsp + 176], rax
    mov rax, [r15 + 8]
    mov [rsp + 184], rax
    mov rax, [r15 + 16]
    mov [rsp + 192], rax
    mov rax, [rsp + 240]
    mov [rsp + 200], rax
    mov rcx, [rsp + 256]
    mov rdx, [rsp + 264]
    xor r8d, r8d
    xor r9d, r9d
    mov qword ptr [rsp + 32], 1
    mov qword ptr [rsp + 40], 0x8080400
    cmp qword ptr [rsp + 576], 0
    je 6f
    or qword ptr [rsp + 40], 4
6:  mov [rsp + 48], r13
    mov [rsp + 56], r14
    lea rax, [rsp + 96]
    mov [rsp + 64], rax
    lea rax, [rsp + 208]
    mov [rsp + 72], rax
    API CreateProcessW
    test eax, eax
    jz .Lkpw_spawn_api
    mov rcx, [rsp + 584]
    mov rax, [rsp + 208]
    mov [rcx + KB_process], rax
    mov rax, [rsp + 216]
    mov [rcx + KB_thread], rax
    mov eax, [rsp + 224]
    mov [rcx + KB_pid], rax
    mov qword ptr [rcx + KB_created], 1
    xor eax, eax
    EPILOGUE
.Lkpw_spawn_api:
    call win_error
    jmp .Lkpw_spawn_fail
.Lkpw_spawn_nomem:
    mov rax, -12
    jmp .Lkpw_spawn_fail
.Lkpw_spawn_invalid:
    mov rax, -22
.Lkpw_spawn_fail:
    EPILOGUE

.section .rdata,"dr"
kpw_systemroot: .short 'S','y','s','t','e','m','R','o','o','t','=',0
kpw_windir: .short 'W','I','N','D','I','R','=',0
kpw_pathkey: .short 'P','A','T','H','=',0
kpw_system32: .short 92,'S','y','s','t','e','m','3','2',0
kpw_b64: .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
kpw_nologo: .asciz "-NoLogo"
kpw_noprofile: .asciz "-NoProfile"
kpw_noninteractive: .asciz "-NonInteractive"
kpw_command_arg: .asciz "-Command"
kpw_encoded_arg: .asciz "-EncodedCommand"
kpw_keeper_flag: .asciz "--process-keeper"
kpw_keeper_version: .asciz "v1"
kpw_null: .asciz "/dev/null"
.text
kpw_copy_wide:
    movzx eax, word ptr [rsi]
    mov [rdi], ax
    test eax, eax
    jz 1f
    add rdi, 2
    add rsi, 2
    jmp kpw_copy_wide
1:  mov rax, rdi
    ret

# A fixed loader environment and trusted helper CWD, independent of target/user environment.
# ->owned Unicode block, rdx System32 path within that owned block.
kpw_safe_environment:
    PROLOGUE 8352
    mov r14, rdi
    lea rcx, [rsp + 160]
    mov edx, 4096
    API GetWindowsDirectoryW
    test eax, eax
    jz 8f
    cmp eax, 4096
    jae 7f
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz 6f
    mov rbx, rax
    mov [r14 + KB_mem], rax
    mov rdi, rax
    lea rsi, [rip + kpw_systemroot]
    call kpw_copy_wide
    mov rdi, rax
    lea rsi, [rsp + 160]
    call kpw_copy_wide
    lea rdi, [rax + 2]
    lea rsi, [rip + kpw_windir]
    call kpw_copy_wide
    mov rdi, rax
    lea rsi, [rsp + 160]
    call kpw_copy_wide
    lea rdi, [rax + 2]
    lea rsi, [rip + kpw_pathkey]
    call kpw_copy_wide
    mov r12, rax
    mov rdi, rax
    lea rsi, [rsp + 160]
    call kpw_copy_wide
    mov rdi, rax
    lea rsi, [rip + kpw_system32]
    call kpw_copy_wide
    mov word ptr [rax + 2], 0
    mov rax, rbx
    mov rdx, r12
    EPILOGUE
6:  mov rax, -12
    EPILOGUE
7:  mov rax, -7
    EPILOGUE
8:  call win_error
    EPILOGUE

# Exact UTF16LE bytes, excluding the terminating NUL, as PowerShell's documented base64 argument.
FN keeper_powershell_encode
    PROLOGUE
    mov esi, 4097
    call kpw_wide
    test rax, rax
    js 9f
    mov rbx, rax
    lea r12, [rdx + rdx - 2]
    lea rax, [r12 + 2]
    xor edx, edx
    mov ecx, 3
    div rcx
    shl rax, 2
    lea rdi, [rax + 1]
    call mem_alloc_try
    test rax, rax
    jz 8f
    mov r13, rax
    xor r14d, r14d
    xor r15d, r15d
1:  cmp r14, r12
    jae 7f
    mov r8, r12
    sub r8, r14
    movzx ecx, byte ptr [rbx + r14]
    shl ecx, 16
    cmp r8, 2
    jb 2f
    movzx eax, byte ptr [rbx + r14 + 1]
    shl eax, 8
    or ecx, eax
    cmp r8, 3
    jb 2f
    movzx eax, byte ptr [rbx + r14 + 2]
    or ecx, eax
2:  lea rdi, [rip + kpw_b64]
    mov edx, ecx
    shr edx, 18
    mov al, [rdi + rdx]
    mov [r13 + r15], al
    mov edx, ecx
    shr edx, 12
    and edx, 63
    mov al, [rdi + rdx]
    mov [r13 + r15 + 1], al
    mov al, '='
    cmp r8, 2
    jb 3f
    mov edx, ecx
    shr edx, 6
    and edx, 63
    mov al, [rdi + rdx]
3:  mov [r13 + r15 + 2], al
    mov al, '='
    cmp r8, 3
    jb 4f
    and ecx, 63
    mov al, [rdi + rcx]
4:  mov [r13 + r15 + 3], al
    add r14, 3
    add r15, 4
    jmp 1b
7:  mov byte ptr [r13 + r15], 0
    mov rdi, rbx
    call mem_free
    mov rax, r13
9:  EPILOGUE
8:  mov rdi, rbx
    call mem_free
    mov rax, -12
    EPILOGUE

kpw_raw:
    PROLOGUE
    mov ebx, esi
    call win_fd
    test rax, rax
    jz 8f
    cmp dword ptr [rax + FD_kind], FD_FILE
    je 1f
    cmp dword ptr [rax + FD_kind], FD_PIPE
    jne 8f
1:  test ebx, ebx
    jnz 2f
    mov rax, [rax + FD_handle]
    EPILOGUE
2:  mov rax, [rax + FD_write]
    EPILOGUE
8:  mov rax, -9
    EPILOGUE

FN kp_backend_prepare
    PROLOGUE 4864
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp + 96]
    mov esi, 255
    mov edx, 28
    call memset
    lea rdi, [rsp + 128]
    xor esi, esi
    mov edx, 104
    call memset
    lea rdi, [rsp + 4688]
    xor esi, esi
    mov edx, 144
    call memset
    mov rdi, [r12 + KP_cwd]
    call kpw_absolute
    test eax, eax
    jz .Lkpw_backend_invalid
    lea rdi, [rsp + 256]
    mov esi, 4096
    call kpw_module_path
    test rax, rax
    jle .Lkpw_backend_fail
    lea rdi, [rsp + 96]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KX_native]
    mov ecx, 0
    call kpw_pipe_owned
    test rax, rax
    js .Lkpw_backend_fail
    lea rdi, [rsp + 104]
    mov esi, O_CLOEXEC | O_NONBLOCK
    lea rdx, [rbx + KX_native]
    mov ecx, 2
    call kpw_pipe_owned
    test rax, rax
    js .Lkpw_backend_fail
    call kpw_open_null
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 112], eax
    mov [rbx + KX_native + KB_fds + 32], rax
    cmp qword ptr [r12 + KP_stdout], -1
    jne 1f
    lea rdi, [rsp + 116]
    mov esi, O_CLOEXEC
    lea rdx, [rbx + KX_native]
    mov ecx, 5
    call kpw_pipe_owned
    test rax, rax
    js .Lkpw_backend_fail
    mov edi, [rsp + 116]
    call win_fd
    or dword ptr [rax + FD_flags], O_NONBLOCK
1:  mov edi, [rsp + 100]
    mov esi, 1
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov rdi, rax
    call kpw_nowait
    test rax, rax
    js .Lkpw_backend_fail
    mov edi, [rsp + 108]
    mov esi, 1
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov rdi, rax
    call kpw_nowait
    test rax, rax
    js .Lkpw_backend_fail
    xor ecx, ecx
    xor edx, edx
    API CreateJobObjectW
    test rax, rax
    jz .Lkpw_backend_api
    mov [rsp + 184], rax
    mov [rbx + KX_native + KB_raw + 56], rax
    mov dword ptr [rsp + 4704], 0x2000
    mov rcx, rax
    mov edx, 9
    lea r8, [rsp + 4688]
    mov r9d, 144
    API SetInformationJobObject
    test eax, eax
    jz .Lkpw_backend_api
    mov edi, [rsp + 96]
    xor esi, esi
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4608], rax
    mov edi, [rsp + 108]
    mov esi, 1
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4616], rax
    mov edi, [rsp + 112]
    xor esi, esi
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4624], rax
    mov rdi, [r12 + KP_stdin]
    cmp rdi, -1
    jne 2f
    mov edi, [rsp + 112]
2:  xor esi, esi
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4632], rax
    mov rdi, [r12 + KP_stdout]
    cmp rdi, -1
    jne 3f
    mov edi, [rsp + 120]
3:  mov esi, 1
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4640], rax
    mov rdi, [r12 + KP_stderr]
    cmp rdi, -1
    jne 4f
    mov edi, [rsp + 120]
4:  mov esi, 1
    call kpw_raw
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 4648], rax
    mov rax, [rsp + 184]
    mov [rsp + 4656], rax
    xor r13d, r13d
5:  mov rdi, [rsp + r13*8 + 4608]
    call kpw_duplicate
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + r13*8 + 128], rax
    mov [rbx + r13*8 + KX_native + KB_raw], rax
    inc r13
    cmp r13, 7
    jb 5b
    lea rdi, [rsp + 4352]
    mov rsi, [rbx + KX_id]
    call fmt_u64
    mov byte ptr [rsp + rax + 4352], 0
    xor r13d, r13d
6:  mov rax, r13
    shl rax, 5
    lea rdi, [rsp + rax + 4384]
    mov rsi, [rsp + r13*8 + 152]
    call fmt_u64
    mov rcx, r13
    shl rcx, 5
    lea rcx, [rsp + rcx + 4384]
    mov byte ptr [rcx + rax], 0
    mov [rsp + r13*8 + 4544], rcx
    inc r13
    cmp r13, 4
    jb 6b
    lea rax, [rsp + 256]
    mov [rsp + 4512], rax
    lea rax, [rip + kpw_keeper_flag]
    mov [rsp + 4520], rax
    lea rax, [rip + kpw_keeper_version]
    mov [rsp + 4528], rax
    lea rax, [rsp + 4352]
    mov [rsp + 4536], rax
    mov qword ptr [rsp + 4576], 0
    lea rdi, [rbx + KX_native]
    call kpw_safe_environment
    test rax, rax
    js .Lkpw_backend_fail
    mov [rsp + 192], rax
    mov [rsp + 200], rdx
    lea rdi, [rsp + 4512]
    mov rsi, rax
    lea rcx, [rsp + 128]
    mov r8d, 7
    xor r9d, r9d
    lea r10, [rbx + KX_native]
    call kpw_spawn
    test rax, rax
    js .Lkpw_backend_fail
    mov rax, [rbx + KX_native + KB_process]
    mov [rbx + KX_helper], rax
    mov qword ptr [rbx + KX_native + KB_process], 0
    mov qword ptr [rbx + KX_native_state], KN_OWNED
    mov rax, [rbx + KX_native + KB_thread]
    mov [rbx + KX_native + KB_raw + 64], rax
    mov qword ptr [rbx + KX_native + KB_thread], 0
    mov rax, [rsp + 184]
    mov [rbx + KX_job], rax
    mov qword ptr [rsp + 184], 0
    mov qword ptr [rbx + KX_native + KB_raw + 56], 0
    movsxd rax, dword ptr [rsp + 100]
    mov [rbx + KX_control], rax
    mov dword ptr [rsp + 100], -1
    mov qword ptr [rbx + KX_native + KB_fds + 8], -1
    movsxd rax, dword ptr [rsp + 104]
    mov [rbx + KX_status], rax
    mov dword ptr [rsp + 104], -1
    mov qword ptr [rbx + KX_native + KB_fds + 16], -1
    movsxd rax, dword ptr [rsp + 116]
    mov [rbx + KX_output], rax
    mov dword ptr [rsp + 116], -1
    mov qword ptr [rbx + KX_native + KB_fds + 40], -1
    xor r15d, r15d
    jmp .Lkpw_backend_cleanup
.Lkpw_backend_invalid:
    mov rax, -22
    jmp .Lkpw_backend_fail
.Lkpw_backend_api:
    call win_error
.Lkpw_backend_fail:
    mov r15, rax
    test r15, r15
    js .Lkpw_backend_cleanup
    mov r15, -5
.Lkpw_backend_cleanup:
    lea rdi, [rbx + KX_native]
    xor esi, esi
    call kp_native_cleanup
    mov rdx, rax
    mov rax, r15
    EPILOGUE

kpw_job_empty:
    PROLOGUE 160
    mov rcx, rdi
    mov edx, 1
    lea r8, [rsp + 96]
    mov r9d, 48
    mov qword ptr [rsp + 32], 0
    API QueryInformationJobObject
    test eax, eax
    jz 8f
    cmp dword ptr [rsp + 136], 0
    sete al
    movzx eax, al
    EPILOGUE
8:  call win_error
    EPILOGUE

FN kp_backend_poll
    PROLOGUE 112
    mov rbx, rdi
    cmp qword ptr [rbx + KX_native_state], KN_OWNED
    jne 9f
    mov rcx, [rbx + KX_helper]
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je 9f
    test eax, eax
    jnz 8f
    mov qword ptr [rbx + KX_native_state], KN_REAPED
    mov dword ptr [rbx + KX_reaped], 1
    mov rcx, [rbx + KX_helper]
    lea rdx, [rsp + 96]
    API GetExitCodeProcess
    test eax, eax
    jz 7f
    mov eax, [rsp + 96]
    mov [rbx + KX_helper_exit], eax
    mov dword ptr [rbx + KX_reaped], 1
    jmp 9f
7:  mov dword ptr [rbx + KX_helper_exit], 255
    mov dword ptr [rbx + KX_reaped], 1
8:  cmp qword ptr [rbx + KX_native_state], KN_REAPED
    jne 82f
    mov dword ptr [rbx + KX_helper_exit], 255
    mov qword ptr [rbx + KX_transport_bad], 1
82: cmp dword ptr [rbx + KX_error], 0
    jne 81f
    mov dword ptr [rbx + KX_error], -5
81: or dword ptr [rbx + KX_flags], KP_FAILED | KP_DEFERRED
9:  xor eax, eax
    EPILOGUE

FN kp_backend_abort
    PROLOGUE 96
    mov rbx, rdi
    cmp qword ptr [rbx + KX_native_state], KN_OWNED
    jne 1f
    cmp qword ptr [rbx + KX_sent], 0
    jne 1f
    cmp qword ptr [rbx + KX_kill_once], 0
    jne 1f
    mov qword ptr [rbx + KX_kill_once], 1
    mov rcx, [rbx + KX_helper]
    mov edx, 111
    API TerminateProcess
1:  xor eax, eax
    EPILOGUE

FN kp_backend_recover
    PROLOGUE 96
    mov rbx, rdi
    cmp qword ptr [rbx + KX_no_target], 1
    je 7f
    test qword ptr [rbx + KX_close_unknown], 32
    jnz 8f
    test qword ptr [rbx + KX_close_known], 32
    jnz 8f
    mov rcx, [rbx + KX_job]
    test rcx, rcx
    jz 8f
    mov edx, 1
    API TerminateJobObject
    mov rdi, [rbx + KX_job]
    call kpw_job_empty
    cmp rax, 1
    sete al
    movzx eax, al
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

FN kp_backend_close
    xor eax, eax
    ret

FN kp_helper_adopt
    PROLOGUE 96
    mov rbx, rdi
    mov dword ptr [rip + win_fds + FD_kind], FD_PIPE
    mov dword ptr [rip + win_fds + FD_flags], O_NONBLOCK
    mov dword ptr [rip + win_fds + FD_SIZE + FD_kind], FD_PIPE
    mov dword ptr [rip + win_fds + FD_SIZE + FD_flags], O_NONBLOCK
    mov dword ptr [rip + win_fds + FD_SIZE + FD_wend], 1
    mov rdi, [rip + win_fds + FD_SIZE + FD_write]
    call kpw_nowait
    test rax, rax
    js 9f
    xor r12d, r12d
1:  mov rax, [rip + g_argv]
    mov rdi, [rax + r12*8 + 32]
    call kp_parse_positive
    test rax, rax
    jle 8f
    mov rdi, rax
    mov esi, FD_FILE
    mov edx, O_CLOEXEC
    call win_fd_alloc
    lea rcx, [r12 + 3]
    cmp rax, rcx
    jne 8f
    inc r12
    cmp r12, 3
    jb 1b
    mov rax, [rip + g_argv]
    mov rdi, [rax + 56]
    call kp_parse_positive
    test rax, rax
    jle 8f
    mov [rbx + KH_job], rax
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE

FN kp_helper_pause
    PROLOGUE 96
    mov ecx, 20
    API Sleep
    EPILOGUE

.section .rdata,"dr"
.p2align 3
kpw_task_flags: .quad kpw_nologo, kpw_noprofile, kpw_noninteractive, kpw_command_arg
.text
# Drive-rooted or UNC only; never resolve a task's cwd against the helper's trusted folder.
kpw_absolute:
    movzx eax, byte ptr [rdi]
    cmp eax, '/'
    je 2f
    cmp eax, 92
    je 2f
    or eax, 32
    sub eax, 'a'
    cmp eax, 25
    ja 8f
    cmp byte ptr [rdi + 1], ':'
    jne 8f
    movzx eax, byte ptr [rdi + 2]
    cmp eax, '/'
    je 9f
    cmp eax, 92
    je 9f
    jmp 8f
2:  movzx eax, byte ptr [rdi + 1]
    cmp eax, '/'
    je 3f
    cmp eax, 92
    jne 8f
3:  cmp byte ptr [rdi + 2], 0
    je 8f
9:  mov eax, 1
    ret
8:  xor eax, eax
    ret

FN kp_target_prepare
    PROLOGUE 256
    mov rbx, rdi
    mov r12, [rbx + KH_argv]
    lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, 160
    call memset
    mov rax, [r12 + 32]
    mov [rsp + 168], rax
    mov rax, [r12 + 40]
    mov [rsp + 176], rax
    cmp qword ptr [rbx + KH_mode], KP_EXTENSION
    je .Lkpw_extension_argv
    cmp qword ptr [r12 + 48], 0
    jne .Lkpw_target_invalid
    cmp qword ptr [r12 + 40], 0
    je .Lkpw_target_invalid
    xor r13d, r13d
1:  mov rdi, [r12 + r13*8 + 8]
    test rdi, rdi
    jz .Lkpw_target_invalid
    lea rax, [rip + kpw_task_flags]
    mov rsi, [rax + r13*8]
    call strcmp_eq
    test eax, eax
    jz .Lkpw_target_invalid
    inc r13
    cmp r13, 4
    jb 1b
    mov rdi, [r12]
    call kpw_absolute
    test eax, eax
    jz .Lkpw_target_invalid
    mov rdi, [rbx + KH_cwd]
    call kpw_absolute
    test eax, eax
    jz .Lkpw_target_invalid
    mov rdi, [r12 + 40]
    call keeper_powershell_encode
    test rax, rax
    js .Lkpw_target_fail
    mov [rsp + 96], rax
    mov [rbx + KH_native + KB_mem + 48], rax
    mov [r12 + 40], rax
    lea rax, [rip + kpw_encoded_arg]
    mov [r12 + 32], rax
    jmp .Lkpw_target_environment
.Lkpw_extension_argv:
    mov rdi, [r12]
    call kpw_absolute
    test eax, eax
    jz .Lkpw_target_invalid
    mov rdi, [rbx + KH_cwd]
    call kpw_absolute
    test eax, eax
    jz .Lkpw_target_invalid
.Lkpw_target_environment:
    mov rdi, [rbx + KH_envp]
    lea rsi, [rbx + KH_native]
    call kpw_environment
    test rax, rax
    js .Lkpw_target_fail
    mov [rsp + 104], rax
    mov rdi, [rbx + KH_cwd]
    mov esi, 32767
    lea rdx, [rbx + KH_native + KB_mem + 40]
    call kpw_wide_owned
    test rax, rax
    js .Lkpw_target_fail
    mov [rsp + 112], rax
    xor r13d, r13d
2:  lea rdi, [r13 + 3]
    xor esi, esi
    test r13, r13
    setnz sil
    call kpw_raw
    test rax, rax
    js .Lkpw_target_fail
    mov rdi, rax
    call kpw_duplicate
    test rax, rax
    js .Lkpw_target_fail
    mov [rsp + r13*8 + 144], rax
    mov [rbx + r13*8 + KH_native + KB_raw], rax
    inc r13
    cmp r13, 3
    jb 2b
    mov rdi, r12
    mov rsi, [rsp + 104]
    mov rdx, [rsp + 112]
    lea rcx, [rsp + 144]
    mov r8d, 3
    mov r9, [rbx + KH_job]
    lea r10, [rbx + KH_native]
    call kpw_spawn
    test rax, rax
    js .Lkpw_target_fail
    mov rax, [rbx + KH_native + KB_process]
    mov [rbx + KH_process], rax
    mov qword ptr [rbx + KH_native + KB_process], 0
    mov rax, [rbx + KH_native + KB_thread]
    mov [rbx + KH_gate], rax
    mov qword ptr [rbx + KH_native + KB_thread], 0
    mov rax, [rbx + KH_native + KB_pid]
    mov [rbx + KH_target], rax
    mov qword ptr [rbx + KH_group_ready], 1
    mov r13d, 9
3:  mov rdi, rbx
    mov rsi, r13
    call kh_close_field
    inc r13
    cmp r13, 12
    jb 3b
    xor r15d, r15d
    jmp .Lkpw_target_cleanup
.Lkpw_target_invalid:
    mov rax, -22
.Lkpw_target_fail:
    mov r15, rax
.Lkpw_target_cleanup:
    mov rax, [rsp + 168]
    mov [r12 + 32], rax
    mov rax, [rsp + 176]
    mov [r12 + 40], rax
    lea rdi, [rbx + KH_native]
    xor esi, esi
    call kp_native_cleanup
    mov rdi, rbx
    mov rsi, rax
    call kh_note_cleanup
    mov rax, r15
    test rax, rax
    js 4f
    mov rax, [rbx + KH_cleanup]
    test rax, rax
    js 4f
    or dword ptr [rbx + KH_flags], KP_READY
    mov qword ptr [rbx + KH_dirty], 1
4:  EPILOGUE

FN kp_target_start
    PROLOGUE 96
    mov rbx, rdi
    call kp_helper_alive
    test rax, rax
    js 9f
    mov rcx, [rbx + KH_gate]
    test rcx, rcx
    jle 8f
    API ResumeThread
    cmp eax, -1
    je 7f
    cmp eax, 1
    jne 8f
    mov rdi, rbx
    xor esi, esi
    call kh_close_field
9:  EPILOGUE
7:  call win_error
    EPILOGUE
8:  mov rax, -5
    EPILOGUE

FN kp_target_stop
    PROLOGUE 96
    mov rbx, rdi
    cmp qword ptr [rbx + KH_stopping], 0
    jne 9f
    mov qword ptr [rbx + KH_stopping], 1
    mov rcx, [rbx + KH_job]
    test rcx, rcx
    jz 1f
    mov edx, 1
    API TerminateJobObject
1:  mov rdi, rbx
    xor esi, esi
    call kh_close_field
2:  cmp qword ptr [rbx + KH_process], 0
    jne 9f
    cmp qword ptr [rbx + KH_target], 0
    jne 9f
    mov dword ptr [rbx + KH_exit], 255
    or dword ptr [rbx + KH_flags], KP_DONE
    mov qword ptr [rbx + KH_dirty], 1
9:  xor eax, eax
    EPILOGUE

FN kp_target_poll
    PROLOGUE 112
    mov rbx, rdi
    cmp qword ptr [rbx + KH_reaped], 0
    jne .Lkpw_poll_job
    test qword ptr [rbx + KH_unknown], 4
    jnz .Lkpw_poll_ok
    test qword ptr [rbx + KH_known], 4
    jnz .Lkpw_poll_ok
    cmp qword ptr [rbx + KH_process], 0
    je .Lkpw_poll_job
    mov rcx, [rbx + KH_process]
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je .Lkpw_poll_ok
    test eax, eax
    jnz .Lkpw_poll_api
    mov qword ptr [rbx + KH_reaped], 1
    mov rcx, [rbx + KH_process]
    lea rdx, [rsp + 96]
    API GetExitCodeProcess
    test eax, eax
    jnz 91f
    call win_error
    cmp dword ptr [rbx + KH_error], 0
    jne 90f
    mov [rbx + KH_error], eax
90: or dword ptr [rbx + KH_flags], KP_FAILED | KP_DEFERRED
    mov dword ptr [rsp + 96], 255
91: mov eax, [rsp + 96]
    mov [rbx + KH_raw], eax
    cmp eax, 255
    jbe 1f
    mov eax, 255
1:  mov [rbx + KH_exit], eax
    or dword ptr [rbx + KH_flags], KP_EXIT_KNOWN
    mov qword ptr [rbx + KH_dirty], 1
    mov rdi, rbx
    call kp_target_stop
    mov rdi, rbx
    mov esi, 2
    call kh_close_field
.Lkpw_poll_job:
    cmp qword ptr [rbx + KH_stopping], 0
    je .Lkpw_poll_ok
    test qword ptr [rbx + KH_unknown], 8
    jnz .Lkpw_poll_ok
    test qword ptr [rbx + KH_known], 8
    jnz .Lkpw_poll_ok
    mov rdi, [rbx + KH_job]
    call kpw_job_empty
    test rax, rax
    js .Lkpw_poll_error
    jz .Lkpw_poll_ok
    cmp qword ptr [rbx + KH_reaped], 0
    jne 92f
    cmp qword ptr [rbx + KH_process], 0
    jne .Lkpw_poll_ok
92: or dword ptr [rbx + KH_flags], KP_DONE
    mov qword ptr [rbx + KH_dirty], 1
.Lkpw_poll_ok:
    xor eax, eax
    EPILOGUE
.Lkpw_poll_api:
    call win_error
.Lkpw_poll_error:
    or dword ptr [rbx + KH_flags], KP_DEFERRED
    mov qword ptr [rbx + KH_dirty], 1
    EPILOGUE

.section .rdata,"dr"
kpw_nul_w: .short 'N','U','L',0
.text
# Fixed-capacity conversion avoids the legacy proc_self_path adapter's fatal string allocation.
kpw_module_path:
    PROLOGUE 8320
    mov rbx, rdi
    mov r12, rsi
    xor ecx, ecx
    lea rdx, [rsp + 128]
    mov r8d, 4096
    API GetModuleFileNameW
    test eax, eax
    jz 8f
    cmp eax, 4096
    jae 7f
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 128]
    mov r9d, -1
    mov [rsp + 32], rbx
    mov [rsp + 40], r12
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz 8f
    dec rax
    EPILOGUE
7:  mov rax, -36
    EPILOGUE
8:  call win_error
    EPILOGUE

# Native NUL opening has no path-conversion allocation and enters the ordinary virtual FD table.
kpw_open_null:
    PROLOGUE 96
    xor edi, edi
    mov esi, FD_FILE
    mov edx, O_CLOEXEC
    call win_fd_alloc
    test rax, rax
    js 9f
    mov r12, rax
    mov r13, r8
    lea rcx, [rip + kpw_nul_w]
    mov edx, 0xc0000000
    mov r8d, 3
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je 8f
    mov [r13 + FD_handle], rax
    mov [r13 + FD_write], rax
    mov rax, r12
9:  EPILOGUE
8:  call win_error
    mov r12, rax
    mov rdi, r13
    xor esi, esi
    mov edx, FD_SIZE
    call memset
    mov rax, r12
    EPILOGUE

# Windows pipe producer is reserve-first (metadata capsule dependency).
kpw_pipe_owned:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    SYS SYS_pipe2
    test rax, rax
    js 9f
    movsxd rax, dword ptr [rbx]
    mov [r12 + r13*8 + KB_fds], rax
    movsxd rax, dword ptr [rbx + 4]
    mov [r12 + r13*8 + KB_fds + 8], rax
    xor eax, eax
9:  EPILOGUE

# Bounded native absolute-path predicate shared with copied activation authorization.
FN kp_path_absolute
    jmp kpw_absolute

# Raw rooted HANDLE duplication, independent of the editor virtual stdio table.
FN kp_lease_duplicate
    PROLOGUE 96
    mov rbx, rdi
    API GetCurrentProcess
    mov rcx, rax
    mov rdx, rbx
    mov r8, rax
    lea r9, [rsp + 80]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 2
    API DuplicateHandle
    test eax, eax
    jz 8f
    mov rax, [rsp + 80]
    EPILOGUE
8:  call win_error
    EPILOGUE
