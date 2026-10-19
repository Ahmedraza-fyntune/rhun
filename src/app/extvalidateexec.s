# Static launch validation. No payload or interpreter is ever executed.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Canonical counted payload-relative path -> owned regular handle. Root is borrowed.
FN ext_validate_open_relative
    PROLOGUE 4144
    mov rbx, rdi
    mov r12, rdx
    mov qword ptr [rsp + 4120], 0
    mov qword ptr [rsp + 4096], 0
    test r12, r12
    jz .Levr_bad
    cmp r12, 4095
    ja .Levr_bad
    mov rdi, rsp
    call memcpy
    mov byte ptr [rsp + r12], 0
    xor r13d, r13d
    xor r14d, r14d
    mov r15, rbx
.Levr_next:
    mov [rsp + 4104], r13
1:  cmp r13, r12
    jae 2f
    cmp byte ptr [rsp + r13], 92
    je .Levr_cleanup_bad
    cmp byte ptr [rsp + r13], ':'
    je .Levr_cleanup_bad
    cmp byte ptr [rsp + r13], '/'
    je 2f
    inc r13
    jmp 1b
2:  cmp r13, [rsp + 4104]
    je .Levr_cleanup_bad
    inc r14
    cmp r14, 32
    ja .Levr_cleanup_bad
    mov byte ptr [rsp + r13], 0
    mov rdi, r15
    mov rax, [rsp + 4104]
    lea rsi, [rsp + rax]
    mov edx, ER_FILE
    cmp r13, r12
    je 3f
    mov edx, ER_DIR
3:  xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    mov [rsp + 4112], rax
    mov [rsp + 4120], rdx
    cmp qword ptr [rsp + 4096], 0
    je 4f
    mov rdi, r15
    call ext_root_close
    test rax, rax
    jns 4f
    cmp qword ptr [rsp + 4120], 0
    jne 31f
    mov [rsp + 4120], rax
31: cmp qword ptr [rsp + 4112], 0
    js 4f
    mov rdi, [rsp + 4112]
    mov [rsp + 4112], rax
    call ext_root_close
4:  mov r15, [rsp + 4112]
    mov qword ptr [rsp + 4096], 0
    test r15, r15
    js .Levr_result
    cmp r13, r12
    je .Levr_result
    mov qword ptr [rsp + 4096], 1
    inc r13
    jmp .Levr_next
.Levr_result:
    mov rax, r15
    mov rdx, [rsp + 4120]
    EPILOGUE
.Levr_cleanup_bad:
    cmp qword ptr [rsp + 4096], 0
    je .Levr_bad
    mov rdi, r15
    call ext_root_close
    mov [rsp + 4120], rax
.Levr_bad:
    mov rax, -EV_BAD_PATH
    mov rdx, [rsp + 4120]
    EPILOGUE

# A PATH-dependent child may not resolve relative to different helper/editor/launch cwd.
# requirePresent is set for env shebangs, whose libc fallback differs from proc_which.
evx_path:
    PROLOGUE
    mov r15, rdi
    lea rdi, [rip + evx_pathname]
    call getenv
    test rax, rax
    jnz 1f
    test r15, r15
    jnz .Levp_bad
    xor eax, eax
    EPILOGUE
1:  mov rbx, rax
    mov rdi, rax
    mov esi, 65536
    call ext_root_length
    test rax, rax
    jle .Levp_bad
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call snippet_utf8_valid
    test eax, eax
    jz .Levp_bad
    xor r13d, r13d
2:  mov r14, r13
3:  cmp r13, r12
    jae 4f
.ifdef WINDOWS
    cmp byte ptr [rbx + r13], ';'
.else
    cmp byte ptr [rbx + r13], ':'
.endif
    je 4f
    inc r13
    jmp 3b
4:  cmp r13, r14
    je .Levp_bad
.ifdef WINDOWS
    mov rax, r13
    sub rax, r14
    cmp rax, 3
    jb .Levp_bad
    mov al, [rbx + r14]
    cmp al, '/'
    je 5f
    cmp al, 92
    je 5f
    or al, 32
    cmp al, 'a'
    jb .Levp_bad
    cmp al, 'z'
    ja .Levp_bad
    cmp byte ptr [rbx + r14 + 1], ':'
    jne .Levp_bad
    mov al, [rbx + r14 + 2]
    cmp al, '/'
    je 6f
    cmp al, 92
    jne .Levp_bad
    jmp 6f
5:  mov al, [rbx + r14 + 1]
    cmp al, '/'
    je 6f
    cmp al, 92
    jne .Levp_bad
.else
    cmp byte ptr [rbx + r14], '/'
    jne .Levp_bad
.endif
6:  cmp r13, r12
    jae 9f
    inc r13
    jmp 2b
9:  xor eax, eax
    EPILOGUE
.Levp_bad:
    mov rax, -EV_BAD_RUNTIME
    EPILOGUE

FN ext_validate_path_env
    jmp evx_path

# System runtimes/interpreters may follow their installation's links. Payloads never do.
FN ext_validate_system_open
evx_system_open:
.ifdef WINDOWS
    jmp win_ext_runtime_open
.else
    PROLOGUE 32
    mov rbx, rdi
    mov esi, 1
    SYS SYS_access
    test rax, rax
    js 9f
    mov rdi, rbx
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
1:  SYS SYS_open
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js 8f
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne 7f
    mov rax, r12
    xor edx, edx
    jmp 91f
7:  mov rax, -EV_BAD_RUNTIME
8:  mov r13, rax
    mov rdi, r12
    call ext_root_close
    mov rdx, rax
    mov rax, r13
    jmp 91f
9:  xor edx, edx
91: EPILOGUE
.endif

# Resolve a counted basename using the actual loader's platform runtime lookup.
evx_runtime:
    PROLOGUE 272
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx              # require present PATH (env)
    test r12, r12
    jz .Levxr_bad
    cmp r12, 255
    ja .Levxr_bad
    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov byte ptr [rsp + r12], 0
    mov rdi, rsp
    call ext_root_name
    test rax, rax
    js .Levxr_bad
    mov rdi, r13
    call evx_path
    test rax, rax
    jnz .Levxr_done
    mov rdi, rsp
    call ext_manifest_runtime
    test rax, rax
    jz .Levxr_bad
    mov rbx, rax
    mov rdi, rax
    call evx_system_open
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rax, r12
.Levxr_done:
    EPILOGUE
.Levxr_bad:
    mov rax, -EV_BAD_RUNTIME
    EPILOGUE

# ext_validate_launch(root,dir,relativeSpan,len,runtimeSpanOr0,runtimeLen).
FN ext_validate_launch
    PROLOGUE 4128
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp + 4096], r9
    mov rsi, rdx
    mov rdx, rcx
    call ext_validate_open_relative
    test rax, rax
    js .Levl_done
    mov [rsp + 4104], rax
    mov rdi, r12
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Levl_path_error
    lea rdx, [rax + r14 + 1]
    cmp rdx, 4095
    ja .Levl_path_error
    mov rbx, rax
    mov rdi, rsp
    mov rsi, r12
    mov rdx, rbx
    call memcpy
    mov byte ptr [rsp + rbx], '/'
    lea rdi, [rsp + rbx + 1]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    lea rax, [rbx + r14 + 1]
    mov byte ptr [rsp + rax], 0
    test r15, r15
    jz .Levl_native
    mov rdi, rsp
    mov esi, 4                # the actual absolute script spelling must be readable too
    SYS SYS_access
    test rax, rax
    js .Levl_close_error
    jmp .Levl_runtime
.Levl_native:
.ifndef WINDOWS
    mov rdi, rsp
    mov esi, 1
    SYS SYS_access
    test rax, rax
    js .Levl_close_error
.endif
    mov rdi, [rsp + 4104]
    mov esi, 1
    call ext_validate_image
    jmp .Levl_close_error
.Levl_runtime:
    mov rdi, [rsp + 4104]
    call ext_root_close
    test rax, rax
    js .Levl_done
    mov rdi, r15
    mov rsi, [rsp + 4096]
    xor edx, edx
    call evx_runtime
    test rax, rax
    js .Levl_done
    mov [rsp + 4104], rax
    mov rdi, rax
    mov esi, 1
    call ext_validate_image
    jmp .Levl_close_error
.Levl_path_error:
    mov rax, -EV_BAD_PATH
.Levl_close_error:
    mov r15, rax
    mov rdi, [rsp + 4104]
    call ext_root_close
    test r15, r15
    jnz 1f
    mov r15, rax
1:  mov rax, r15
.Levl_done:
    EPILOGUE

.ifdef MACOS
# A bounded ARM64 MH_EXECUTE slice, thin or selected from a fat image.
evx_macho:
    PROLOGUE 32
    mov rbx, rdx              # slice length
    cmp rbx, 32
    jb 8f
    mov rcx, rsi              # slice offset
    mov rsi, rsp
    mov edx, 32
    call prep_image_read
    cmp rax, 32
    jne 8f
    cmp dword ptr [rsp], 0xfeedfacf
    jne 8f
    cmp dword ptr [rsp + 4], 0x0100000c
    jne 8f
    cmp dword ptr [rsp + 12], 2
    jne 8f
    mov eax, [rsp + 16]
    test eax, eax
    jz 8f
    cmp eax, 4096
    ja 8f
    shl rax, 3
    mov edx, [rsp + 20]
    cmp rdx, rax
    jb 8f
    sub rbx, 32
    cmp rdx, rbx
    ja 8f
    xor eax, eax
    EPILOGUE
8:  mov rax, -EV_BAD_EXEC
    EPILOGUE
.endif

# Borrowed regular file. Host-native image or one supported shebang layer.
FN ext_validate_image
    xor edx, edx
FN ext_validate_image_owned
    PROLOGUE 1120
    mov [rsp + 1112], rdx
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call prep_image_stat
    test rax, rax
    js .Levxi_done
    cmp qword ptr [rsp + ER_kind], ER_FILE
    jne .Levxi_bad
    mov r13, [rsp + ER_size]
    mov rdi, rbx
    lea rsi, [rsp + 32]
    mov edx, 512
    xor ecx, ecx
    call prep_image_read
    test rax, rax
    js .Levxi_done
    mov r14, rax
.ifdef WINDOWS
    cmp r14, 64
    jb .Levxi_bad
    cmp word ptr [rsp + 32], 0x5a4d
    jne .Levxi_bad
    mov r15d, [rsp + 32 + 60]
    cmp r15, 64
    jb .Levxi_bad
    cmp r15, r13
    ja .Levxi_bad
    mov rax, r13
    sub rax, r15
    cmp rax, 136
    jb .Levxi_bad
    mov rdi, rbx
    lea rsi, [rsp + 32]
    mov edx, 136
    mov rcx, r15
    call prep_image_read
    cmp rax, 136
    jne .Levxi_bad
    cmp dword ptr [rsp + 32], 0x00004550
    jne .Levxi_bad
    cmp word ptr [rsp + 32 + 4], 0x8664
    jne .Levxi_bad
    movzx r12d, word ptr [rsp + 32 + 6]
    test r12d, r12d
    jz .Levxi_bad
    cmp r12, 96
    ja .Levxi_bad
    movzx eax, word ptr [rsp + 32 + 22]
    test eax, 2
    jz .Levxi_bad
    test eax, 0x2000
    jnz .Levxi_bad
    cmp word ptr [rsp + 32 + 24], 0x20b
    jne .Levxi_bad
    movzx eax, word ptr [rsp + 32 + 92]
    cmp eax, 2
    je 1f
    cmp eax, 3
    jne .Levxi_bad
1:  cmp dword ptr [rsp + 32 + 40], 0
    je .Levxi_bad
    movzx r14d, word ptr [rsp + 32 + 20]
    cmp r14, 112
    jb .Levxi_bad
    cmp r14, 4096
    ja .Levxi_bad
    mov eax, [rsp + 32 + 132]
    cmp eax, 16
    ja .Levxi_bad
    lea rax, [rax*8 + 112]
    cmp rax, r14
    ja .Levxi_bad
    imul r12, r12, 40
    lea rax, [r15 + r14 + 24]
    add rax, r12
    cmp rax, r13
    ja .Levxi_bad
    mov edx, [rsp + 32 + 84]
    cmp rdx, rax
    jb .Levxi_bad
    cmp rdx, r13
    ja .Levxi_bad
    jmp .Levxi_good
.else
.ifdef MACOS
    cmp r14, 32
    jb .Levxi_shebang
    cmp dword ptr [rsp + 32], 0xfeedfacf
    jne .Levxi_fat
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    call evx_macho
    jmp .Levxi_done
.Levxi_fat:
    mov eax, [rsp + 32]
    cmp eax, 0xbebafeca
    je 1f
    cmp eax, 0xbfbafeca
    jne .Levxi_shebang
    mov qword ptr [rsp + 1080], 32
    jmp 2f
1:  mov qword ptr [rsp + 1080], 20
2:  mov r15d, [rsp + 36]
    bswap r15d
    test r15, r15
    jz .Levxi_bad
    cmp r15, 64
    ja .Levxi_bad
    mov rax, [rsp + 1080]
    imul rax, r15
    add rax, 8
    cmp rax, r13
    ja .Levxi_bad
    mov [rsp + 1088], rax
    mov r14d, 8
.Levxi_fat_next:
    test r15, r15
    jz .Levxi_bad
    mov rdi, rbx
    lea rsi, [rsp + 32]
    mov rdx, [rsp + 1080]
    mov rcx, r14
    call prep_image_read
    cmp rax, [rsp + 1080]
    jne .Levxi_bad
    mov eax, [rsp + 32]
    bswap eax
    cmp eax, 0x0100000c
    je 3f
    add r14, [rsp + 1080]
    dec r15
    jmp .Levxi_fat_next
3:  cmp qword ptr [rsp + 1080], 32
    je 4f
    mov esi, [rsp + 40]
    bswap esi
    mov edx, [rsp + 44]
    bswap edx
    jmp 5f
4:  mov rsi, [rsp + 40]
    bswap rsi
    mov rdx, [rsp + 48]
    bswap rdx
5:  cmp rsi, [rsp + 1088]
    jb .Levxi_bad
    cmp rsi, r13
    ja .Levxi_bad
    mov rax, r13
    sub rax, rsi
    cmp rdx, rax
    ja .Levxi_bad
    mov rdi, rbx
    call evx_macho
    jmp .Levxi_done
.else
    cmp r14, 64
    jb .Levxi_shebang
    cmp dword ptr [rsp + 32], 0x464c457f
    jne .Levxi_shebang
    cmp byte ptr [rsp + 36], 2
    jne .Levxi_bad
    cmp byte ptr [rsp + 37], 1
    jne .Levxi_bad
    cmp byte ptr [rsp + 38], 1
    jne .Levxi_bad
    cmp word ptr [rsp + 50], 62
    jne .Levxi_bad
    movzx eax, word ptr [rsp + 48]
    cmp eax, 2
    je 1f
    cmp eax, 3
    jne .Levxi_bad
1:  cmp dword ptr [rsp + 52], 1
    jne .Levxi_bad
    cmp qword ptr [rsp + 56], 0
    je .Levxi_bad
    cmp word ptr [rsp + 84], 64
    jne .Levxi_bad
    cmp word ptr [rsp + 86], 56
    jne .Levxi_bad
    movzx eax, word ptr [rsp + 88]
    test eax, eax
    jz .Levxi_bad
    cmp eax, 1024
    ja .Levxi_bad
    imul rax, rax, 56
    mov rdx, [rsp + 64]
    cmp rdx, 64
    jb .Levxi_bad
    cmp rdx, r13
    ja .Levxi_bad
    sub r13, rdx
    cmp rax, r13
    ja .Levxi_bad
    jmp .Levxi_good
.endif
.Levxi_shebang:
    test r12, r12
    jz .Levxi_bad
    cmp r14, 3
    jb .Levxi_bad
    cmp word ptr [rsp + 32], 0x2123
    jne .Levxi_bad
    mov r15d, 2
.Levxi_line:
    cmp r15, r14
    jae .Levxi_line_eof
    cmp r15, 255
    jae .Levxi_bad
    cmp byte ptr [rsp + 32 + r15], 10
    je .Levxi_line_ready
    cmp byte ptr [rsp + 32 + r15], 13
    je .Levxi_bad
    inc r15
    jmp .Levxi_line
.Levxi_line_eof:
    cmp r13, 255
    ja .Levxi_bad
.Levxi_line_ready:
    lea rdi, [rsp + 34]
    lea rsi, [r15 - 2]
    call next_word
    test rdx, rdx
    jz .Levxi_bad
    cmp byte ptr [rax], '/'
    jne .Levxi_bad
    mov [rsp + 1080], rcx
    mov [rsp + 1104], rax
    mov r14, rdx
    mov rdi, rax
    mov rsi, rdx
    call ext_validate_text
    test eax, eax
    jz .Levxi_bad
    lea rdi, [rsp + 544]
    mov rsi, [rsp + 1104]
    mov rdx, r14
    call memcpy
    mov byte ptr [rsp + 544 + r14], 0
    mov rax, [rsp + 1080]
    lea rdi, [rsp + 34 + rax]
    lea rsi, [r15 - 2]
    sub rsi, rax
    call next_word
    mov [rsp + 1088], rax
    mov [rsp + 1096], rdx
    add rcx, [rsp + 1080]
    lea rdi, [rsp + 34 + rcx]
    lea rsi, [r15 - 2]
    sub rsi, rcx
    call next_word
    test rdx, rdx
    jnz .Levxi_bad
    mov rsi, [rsp + 1096]
    test rsi, rsi
    jz 7f
    mov rdi, [rsp + 1088]
    call ext_validate_text
    test eax, eax
    jz .Levxi_bad
7:  lea rdi, [rsp + 544]
    lea rsi, [rip + evx_env]
    call strcmp_eq
    test eax, eax
    jz .Levxi_direct_interpreter
    cmp qword ptr [rsp + 1096], 0
    je .Levxi_bad
    mov rdi, [rsp + 1088]
    cmp byte ptr [rdi], '-'
    je .Levxi_bad
    mov rsi, [rsp + 1096]
    mov edx, 1
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rsp + 1112]
    call prep_runtime_resolve
    test rax, rax
    jz .Levxi_runtime_error
    mov r14, rax
    mov rdi, rax
    call evx_system_open
    mov [rsp + 1080], rax
    mov [rsp + 1088], rdx
    mov rdi, [rsp + 1112]
    mov rsi, r14
    call prep_runtime_free
    mov rax, [rsp + 1080]
    mov rdx, [rsp + 1088]
    jmp .Levxi_interpreter_opened
.Levxi_runtime_error:
    mov rax, rdx
    jmp .Levxi_done
.Levxi_direct_interpreter:
    lea rdi, [rsp + 544]
    call evx_system_open
.Levxi_interpreter_opened:
    mov rcx, [rsp + 1112]
    test rcx, rcx
    jz 51f
    cmp qword ptr [rcx + EP_cleanup], 0
    jne 51f
    mov [rcx + EP_cleanup], rdx
51: test rax, rax
    js .Levxi_done
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp + 1112]
    call ext_validate_image_owned
    mov r14, rax
    mov rdi, r15
    call ext_root_close
    mov rcx, [rsp + 1112]
    test rcx, rcx
    jz 52f
    cmp qword ptr [rcx + EP_cleanup], 0
    jne 52f
    mov [rcx + EP_cleanup], rax
52: test r14, r14
    jnz 6f
    mov r14, rax
6:  mov rax, r14
    jmp .Levxi_done
.endif
.Levxi_good:
    xor eax, eax
.Levxi_done:
    EPILOGUE
.Levxi_bad:
    mov rax, -EV_BAD_EXEC
    EPILOGUE
.section .rodata
evx_pathname: .asciz "PATH"
evx_env: .asciz "/usr/bin/env"
