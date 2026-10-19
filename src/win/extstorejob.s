# Explicit current-executable helper inheritance. Native handles never enter virtual FD table.
.include "win.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.include "app/extsettingsnative.inc"
.section .rdata,"dr"
esjw_nul: .short 'N','U','L',0
esjw_env: .short 'L','C','_','A','L','L','=','C',0,0
.text
FN ext_store_job_module_path
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

esjw_wide:
    PROLOGUE 112
    mov rbx, rdi
    mov r14, rsi
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz 8f
    cmp eax, 32767
    ja 7f
    mov r12d, eax
    lea rdi, [rax + rax]
    call mem_alloc_try
    test rax, rax
    jz 6f
    mov r13, rax
    mov [r14], rax
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    mov [rsp + 32], r13
    mov [rsp + 40], r12
    API MultiByteToWideChar
    cmp eax, r12d
    jne 5f
    mov rax, r13
    EPILOGUE
5:
8:  call win_error
    EPILOGUE
7:  mov rax, -7
    EPILOGUE
6:  mov rax, -12
    EPILOGUE

# All arguments quoted using the Microsoft CRT slash/quote rule. Known max10 arguments.
esjw_command:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + ESJ_work]
    add r12, 1024
    mov r13, r12
    xor r14d, r14d
1:  mov r15, [rbx + ESJ_argv + r14*8]
    test r15, r15
    jz 8f
    cmp r14, 10
    jae 9f
    test r14, r14
    jz 2f
    mov byte ptr [r13], ' '
    inc r13
2:  mov byte ptr [r13], '"'
    inc r13
3:  mov rax, r13
    sub rax, r12
    cmp rax, 32760
    jae 9f
    xor ecx, ecx
4:  movzx eax, byte ptr [r15]
    cmp eax, 92
    jne 5f
    inc ecx
    inc r15
    jmp 4b
5:  test eax, eax
    jz 51f
    cmp eax, '"'
    jne 6f
    lea ecx, [rcx + rcx + 1]
    jmp 6f
51: add ecx, ecx
6:  mov rdx, r13
    sub rdx, r12
    add rdx, rcx
    cmp rdx, 32760
    jae 9f
61: test ecx, ecx
    jz 7f
    mov byte ptr [r13], 92
    inc r13
    dec ecx
    jmp 61b
7:  test eax, eax
    jz 71f
    mov [r13], al
    inc r13
    inc r15
    jmp 3b
71: mov byte ptr [r13], '"'
    inc r13
    inc r14
    jmp 1b
8:  mov byte ptr [r13], 0
    mov rdi, r12
    lea rsi, [rbx + ESJ_native + 104]
    call esjw_wide
    EPILOGUE
9:  mov rax, -7
    EPILOGUE

# Independent private inheritable duplicates only.
esjw_duplicate:
    PROLOGUE 112
    mov rbx, rdi
    mov rcx, -1
    mov rdx, rbx
    mov r8, -1
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 1
    mov qword ptr [rsp + 48], 2
    API DuplicateHandle
    test eax, eax
    jz 8f
    mov rax, [rsp + 96]
    EPILOGUE
8:  call win_error
    EPILOGUE

FN ext_store_job_native_spawn
    PROLOGUE 384
    mov rbx, rdi
    lea rdi, [rsp + 96]
    xor esi, esi
    mov edx, 288
    call memset
    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz .Lesjw_spawn_oom
    mov [rbx + ESJ_work], rax
    mov rcx, rax
    mov edx, 512
    API GetWindowsDirectoryW
    test eax, eax
    jz .Lesjw_spawn_api
    cmp eax, 512
    jae .Lesjw_spawn_big
    xor r12d, r12d
.Lesjw_pipes:
    lea rcx, [rbx + ESJ_native + r12]
    lea rdx, [rbx + ESJ_native + r12 + 8]
    xor r8d, r8d
    xor r9d, r9d
    API CreatePipe
    test eax, eax
    jz .Lesjw_spawn_api
    mov rdi, [rbx + ESJ_native + r12 + 8]
    call esjw_duplicate
    test rax, rax
    js .Lesjw_spawn_error
    mov r13, rax
    mov rcx, [rbx + ESJ_native + r12 + 8]
    mov [rbx + ESJ_native + r12 + 8], r13
    API CloseHandle
    test eax, eax
    jz .Lesjw_spawn_api
    add r12, 16
    cmp r12, 32
    jb .Lesjw_pipes
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 10f
    mov rdi, rbx
    call ext_settings_native_windows_input
    test rax, rax
    js .Lesjw_spawn_error
    jmp .Lesjw_settings_stdio
10: lea rcx, [rip + esjw_nul]
    mov edx, 0x80000000
    mov r8d, 3
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lesjw_spawn_api
    mov [rbx + ESJ_native + 32], rax
    mov rdi, rax
    call esjw_duplicate
    test rax, rax
    js .Lesjw_spawn_error
    mov r13, rax
    mov rcx, [rbx + ESJ_native + 32]
    mov [rbx + ESJ_native + 32], r13
    API CloseHandle
    test eax, eax
    jz .Lesjw_spawn_api
    mov rdi, [rbx + ESJ_anchor]
    call esjw_duplicate
    test rax, rax
    js .Lesjw_spawn_error
    mov [rbx + ESJ_native + 40], rax
    mov rsi, rax
    lea rdi, [rbx + ESJ_rawtext]
    call fmt_u64
    mov byte ptr [rbx + ESJ_rawtext + rax], 0
 .Lesjw_settings_stdio:
    mov rax, [rbx + ESJ_native + 32]
    mov [rbx + ESJ_native + 64], rax
    mov rax, [rbx + ESJ_native + 8]
    mov [rbx + ESJ_native + 72], rax
    mov rax, [rbx + ESJ_native + 24]
    mov [rbx + ESJ_native + 80], rax
    mov rax, [rbx + ESJ_native + 40]
    mov [rbx + ESJ_native + 88], rax
    lea rdi, [rbx + ESJ_exe]
    lea rsi, [rbx + ESJ_native + 112]
    call esjw_wide
    test rax, rax
    js .Lesjw_spawn_error
    mov [rbx + ESJ_native + 112], rax
    mov rdi, rbx
    call esjw_command
    test rax, rax
    js .Lesjw_spawn_error
    mov [rbx + ESJ_native + 104], rax
    xor ecx, ecx
    mov edx, 1
    xor r8d, r8d
    lea r9, [rsp + 272]
    API InitializeProcThreadAttributeList
    mov rdi, [rsp + 272]
    test rdi, rdi
    jz .Lesjw_spawn_big
    cmp rdi, 65536
    ja .Lesjw_spawn_big
    call mem_alloc_try
    test rax, rax
    jz .Lesjw_spawn_oom
    mov [rbx + ESJ_native + 96], rax
    mov rcx, rax
    mov edx, 1
    xor r8d, r8d
    lea r9, [rsp + 272]
    API InitializeProcThreadAttributeList
    test eax, eax
    jz .Lesjw_spawn_api
    mov qword ptr [rbx + ESJ_native + 120], 1
    mov rcx, [rbx + ESJ_native + 96]
    xor edx, edx
    mov r8d, 0x20002
    lea r9, [rbx + ESJ_native + 64]
    mov qword ptr [rsp + 32], 32
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    jne 11f
    mov qword ptr [rsp + 32], 24
11: mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    API UpdateProcThreadAttribute
    test eax, eax
    jz .Lesjw_spawn_api
    mov dword ptr [rsp + 96], 112
    mov dword ptr [rsp + 156], 0x100
    mov rax, [rbx + ESJ_native + 64]
    mov [rsp + 176], rax
    mov rax, [rbx + ESJ_native + 72]
    mov [rsp + 184], rax
    mov rax, [rbx + ESJ_native + 80]
    mov [rsp + 192], rax
    mov rax, [rbx + ESJ_native + 96]
    mov [rsp + 200], rax
    mov rcx, [rbx + ESJ_native + 112]
    mov rdx, [rbx + ESJ_native + 104]
    xor r8d, r8d
    xor r9d, r9d
    mov qword ptr [rsp + 32], 1
    mov qword ptr [rsp + 40], 0x8080400
    lea rax, [rip + esjw_env]
    mov rcx, [rbx + ESJ_purpose]
    sub rcx, ESJ_LEGACY_VALIDATOR
    cmp rcx, 1
    ja 12f
    mov rax, [rbx + ESJ_legacy]
    mov rax, [rax + ELC_env]
12: mov [rsp + 48], rax
    mov rcx, [rbx + ESJ_native + 112]
    mov rax, [rbx + ESJ_work]
    mov [rsp + 56], rax
    lea rax, [rsp + 96]
    mov [rsp + 64], rax
    lea rax, [rsp + 224]
    mov [rsp + 72], rax
    API CreateProcessW
    test eax, eax
    jz .Lesjw_spawn_api
    mov rax, [rsp + 224]
    mov [rbx + ESJ_process], rax
    mov qword ptr [rbx + ESJ_authority], ESJ_OWNED
    mov rax, [rsp + 232]
    mov [rbx + ESJ_native + 48], rax
    mov rax, [rbx + ESJ_native]
    mov [rbx + ESJ_stdout], rax
    mov qword ptr [rbx + ESJ_native], -1
    mov rax, [rbx + ESJ_native + 16]
    mov [rbx + ESJ_stderr], rax
    mov qword ptr [rbx + ESJ_native + 16], -1
    mov qword ptr [rbx + ESJ_eof], 4
    mov rdi, rbx
    call ext_store_job_native_free
    EPILOGUE
.Lesjw_spawn_api:
    call win_error
    jmp .Lesjw_spawn_error
.Lesjw_spawn_big:
    mov rax, -7
    jmp .Lesjw_spawn_error
.Lesjw_spawn_oom:
    mov rax, -12
.Lesjw_spawn_error:
    mov r12, rax
    mov rdi, rbx
    call ext_store_job_native_free
    test rax, rax
    jns 1f
    cmp qword ptr [rbx + ESJ_secondary], 0
    jne 1f
    mov [rbx + ESJ_secondary], rax
1:  mov rax, r12
    EPILOGUE

# Temporary API metadata plus process handle only after actual collection.
FN ext_store_job_native_free
    PROLOGUE 96
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
    mov r14d, 1
1:  mov rcx, [rbx + ESJ_native + r12]
    mov qword ptr [rbx + ESJ_native + r12], -1
    cmp rcx, -1
    je 3f
    test rcx, rcx
    jz 3f
    API CloseHandle
    test eax, eax
    jnz 3f
    call win_error
    test r13, r13
    jnz 3f
    mov r13, rax
3:  add r12, 8
    cmp r12, 56
    jb 1b
    cmp qword ptr [rbx + ESJ_native + 120], 0
    je 4f
    mov qword ptr [rbx + ESJ_native + 120], 0
    mov rcx, [rbx + ESJ_native + 96]
    API DeleteProcThreadAttributeList
4:  mov r12, 96
5:  mov rdi, [rbx + ESJ_native + r12]
    call prep_cleanup_free
    test rdx, rdx
    jz 51f
    mov qword ptr [rbx + ESJ_native + r12], 0
    jmp 52f
51: xor r14d, r14d
52: test rax, rax
    jns 53f
    test r13, r13
    jnz 53f
    mov r13, rax
53: add r12, 8
    cmp r12, 112
    jbe 5b
    mov rdi, [rbx + ESJ_work]
    call prep_cleanup_free
    test rdx, rdx
    jz 54f
    mov qword ptr [rbx + ESJ_work], 0
    jmp 55f
54: xor r14d, r14d
55: test rax, rax
    jns 56f
    test r13, r13
    jnz 56f
    mov r13, rax
56:
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    je 7f
    mov rcx, [rbx + ESJ_process]
    mov qword ptr [rbx + ESJ_process], 0
    test rcx, rcx
    jz 7f
    API CloseHandle
    test eax, eax
    jnz 7f
    call win_error
    test r13, r13
    jnz 7f
    mov r13, rax
7:  mov rax, r13
    mov rdx, r14
    EPILOGUE

FN ext_store_job_native_close
    PROLOGUE 96
    mov rcx, rdi
    API CloseHandle
    test eax, eax
    jz 1f
    xor eax, eax
    EPILOGUE
1:  call win_error
    EPILOGUE

FN ext_store_job_native_read
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp + 96]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    API PeekNamedPipe
    test eax, eax
    jz 8f
    mov eax, [rsp + 96]
    test eax, eax
    jz 7f
    cmp r13, rax
    jbe 1f
    mov r13, rax
1:  mov rcx, rbx
    mov rdx, r12
    mov r8d, r13d
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    API ReadFile
    test eax, eax
    jz 8f
    mov eax, [rsp + 96]
    EPILOGUE
7:  mov rax, -11
    EPILOGUE
8:  API GetLastError
    cmp eax, 109
    jne 9f
    xor eax, eax
    EPILOGUE
9:  call win_error
    EPILOGUE

FN ext_store_job_native_kill
    PROLOGUE 96
    mov rcx, [rdi + ESJ_process]
    mov edx, 111
    API TerminateProcess
    test eax, eax
    jz 1f
    xor eax, eax
    EPILOGUE
1:  call win_error
    EPILOGUE

FN ext_store_job_native_poll
    PROLOGUE 112
    mov rbx, rdi
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne 5f
    mov rcx, [rbx + ESJ_process]
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je 5f
    test eax, eax
    jnz 7f
    mov rcx, [rbx + ESJ_process]
    lea rdx, [rsp + 96]
    API GetExitCodeProcess
    test eax, eax
    jz 7f
    mov eax, [rsp + 96]
    mov [rbx + ESJ_exit], rax
    mov qword ptr [rbx + ESJ_authority], ESJ_REAPED
5:  xor eax, eax
    EPILOGUE
7:  call win_error
    test rax, rax
    js 8f
    mov rax, -5
8:  EPILOGUE

FN ext_store_job_nonce
    PROLOGUE 112
    mov rbx, rdi
    xor ecx, ecx
    lea rdx, [rsp + 96]
    mov r8d, 16
    mov r9d, 2
    API BCryptGenRandom
    test eax, eax
    js 1f
    mov rdi, rbx
    lea rsi, [rsp + 96]
    mov edx, 16
    call memcpy
    xor eax, eax
    EPILOGUE
1:  mov rax, -5
    EPILOGUE
FN ext_store_job_retire_wait
    PROLOGUE 96
    mov ecx, 16
    API Sleep
    xor eax, eax
    EPILOGUE
