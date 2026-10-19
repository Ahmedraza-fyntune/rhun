# Legacy-only captured context and bounded header validation. No package IO in parent.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.bss
.p2align 3
esjl_cached_length: .zero 8
esjl_cached_executable: .zero 4096
.section .rodata
esjl_path: .asciz "PATH"
esjl_prefix: .ascii "PATH="
esjl_locale: .asciz "LC_ALL=C"
esjl_cwd: .asciz "RHUN_LEGACY_CWD"
.text
# Startup only, before app_init. Failure is sticky and never triggers lazy filesystem work.
FN ext_store_job_legacy_cache_executable
    PROLOGUE
    mov rax, [rip + esjl_cached_length]
    test rax, rax
    jnz 2f
    lea rdi, [rip + esjl_cached_executable]
    mov esi, 4096
.ifdef WINDOWS
    call ext_store_job_module_path
.else
    call proc_self_path
.endif
    test rax, rax
    jg 1f
    js 3f
    mov rax, -5
    jmp 3f
1:  cmp rax, 4095
    ja 4f
    mov rbx, rax
.ifdef WINDOWS
    lea rdi, [rip + esjl_cached_executable]
    call ext_store_job_legacy_volume
    test rax, rax
    js 3f
.else
    cmp byte ptr [rip + esjl_cached_executable], '/'
    jne 6f
.endif
    mov [rip + esjl_cached_length], rbx
    mov rax, rbx
2:  test rax, rax
    js 5f
    xor eax, eax
5:  EPILOGUE
6:  mov rax, -22
    jmp 3f
4:  mov rax, -36
3:  mov [rip + esjl_cached_length], rax
    EPILOGUE

FN ext_store_job_legacy_copy_executable
    PROLOGUE
    mov rbx, [rip + esjl_cached_length]
    test rbx, rbx
    js 2f
    jz 3f
    lea rsi, [rip + esjl_cached_executable]
    lea rdx, [rbx + 1]
    call memcpy
2:  mov rax, rbx
    EPILOGUE
3:  mov rax, -2
    EPILOGUE

FN ext_store_job_legacy_capture
    PROLOGUE
    mov rbx, rdi
    mov edi, ELC_SIZE
    call mem_alloc_try
    test rax, rax
    jz 8f
    mov r12, rax
    mov [rbx + ESJ_legacy], rax
    mov rdi, rax
    xor esi, esi
    mov edx, ELC_SIZE
    call memset
.ifdef WINDOWS
    mov rdi, r12
    call win_ext_store_job_legacy_capture
.else
    lea rax, [r12 + ELC_envp]
    mov [r12 + ELC_env], rax
    lea rax, [rip + esjl_locale]
    mov [r12 + ELC_envp], rax
    lea rdi, [rip + esjl_path]
    call getenv
    test rax, rax
    jz 7f
    mov r13, rax
    mov rdi, rax
    mov esi, 65534
    call ext_root_length
    test rax, rax
    js 9f
    mov r14, rax
    lea rdi, [r12 + ELC_envbuf]
    lea rsi, [rip + esjl_prefix]
    mov edx, 5
    call memcpy
    lea rdi, [r12 + ELC_envbuf + 5]
    mov rsi, r13
    lea rdx, [r14 + 1]
    call memcpy
    lea rax, [r12 + ELC_envbuf]
    mov [r12 + ELC_envp + 8], rax
    mov qword ptr [r12 + ELC_path_present], 1
7:  xor eax, eax
.endif
    EPILOGUE
8:  mov rax, -12
    EPILOGUE
9:  mov rax, -7
    EPILOGUE

# Pure saved context, lifetime ends only at consumed job_free.
FN ext_store_job_legacy_context
    test rdi, rdi
    jz 8f
    test rsi, rsi
    jz 8f
    mov rax, [rdi + ESJ_purpose]
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    ja 8f
    mov rax, [rdi + ESJ_error]
    test rax, rax
    js 9f
    mov rax, [rdi + ESJ_guard]
    test rax, rax
    jz 1f
    mov rcx, [rdi + ESJ_tag + EST_epoch]
    cmp [rax + ESG_epoch], rcx
    jne 7f
1:  mov rdx, [rdi + ESJ_legacy]
    test rdx, rdx
    jz 8f
    mov rax, [rdx + ELC_cwd]
    mov rcx, [rdx + ELC_drive]
    mov [rsi], rax
    mov [rsi + 8], rcx
    xor eax, eax
9:  ret
7:  mov rax, -116
    ret
8:  mov rax, -22
    ret

# Helper only. No handle transfer. Missing private bootstrap preserves direct CLI cwd.
FN ext_store_job_legacy_child_context
.ifdef WINDOWS
    PROLOGUE
    lea rdi, [rip + esjl_cwd]
    call getenv
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, rax
    call ext_store_job_legacy_volume
    test rax, rax
    js 2f
    mov rdi, rbx
    call win_ext_store_job_legacy_chdir
2:  EPILOGUE
1:  xor eax, eax
    EPILOGUE
.else
    xor eax, eax
    ret
.endif

# O(192) success envelope check. Full body/hash/role parsing belongs to pure importer.
FN ext_store_job_legacy_snapshot_check
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + ESJ_wire]
    mov rax, 0x00003153534c4852
    cmp [r12], rax
    jne 8f
    cmp dword ptr [r12 + 8], 1
    jne 8f
    cmp dword ptr [r12 + 12], 192
    jne 8f
    mov rax, [r12 + 16]
    cmp rax, 192
    jb 8f
    cmp rax, ESJL_CAP
    ja 8f
    cmp [rbx + ESJ_used], rax
    ja 8f
    mov eax, [r12 + 24]
    sub eax, 2
    cmp eax, 256
    ja 8f
    cmp dword ptr [r12 + 28], 0
    jne 8f
    lea rdi, [r12 + 32]
    lea rsi, [rbx + ESJ_tag]
    mov edx, 64
    call memeq
    test eax, eax
    jz 8f
    mov rax, [r12 + 96]
    or rax, [r12 + 104]
    or rax, [r12 + 112]
    or rax, [r12 + 120]
    jz 8f
    mov rax, [r12 + 128]
    or rax, [r12 + 136]
    or rax, [r12 + 156]
    or rax, [r12 + 164]
    or rax, [r12 + 172]
    or rax, [r12 + 180]
    mov ecx, [r12 + 188]
    or rax, rcx
    jnz 8f
    mov eax, [r12 + 144]
    dec eax
    cmp eax, 4094
    ja 8f
    cmp dword ptr [r12 + 148], 4095
    ja 8f
    mov rax, [rbx + ESJ_legacy]
    mov eax, [rax + ELC_drive]
    cmp eax, [r12 + 152]
    jne 8f
    xor eax, eax
    EPILOGUE
8:  mov rax, -5
    EPILOGUE

# Pure ordinary Windows volume syntax, same drive/UNC policy as legacy import.
FN ext_store_job_legacy_volume
    PROLOGUE
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    cmp rax, 3
    jl .Lesjlcv_bad
    mov r12, rax
    mov rsi, rax
    mov rdi, rbx
    call ext_validate_text
    test eax, eax
    jz .Lesjlcv_bad
    cmp byte ptr [rbx + 1], ':'
    jne .Lesjlcv_unc
    movzx edx, byte ptr [rbx]
    and edx, -33
    lea ecx, [rdx - 'A']
    cmp ecx, 25
    ja .Lesjlcv_bad
    mov al, [rbx + 2]
    cmp al, '/'
    je .Lesjlcv_drive
    cmp al, 92
    jne .Lesjlcv_bad
.Lesjlcv_drive:
    mov eax, 2
    EPILOGUE
.Lesjlcv_unc:
    cmp r12, 5
    jb .Lesjlcv_bad
    mov al, [rbx]
    cmp al, '/'
    je 1f
    cmp al, 92
    jne .Lesjlcv_bad
1:  mov al, [rbx + 1]
    cmp al, '/'
    je 2f
    cmp al, 92
    jne .Lesjlcv_bad
2:  mov r13d, 2
.Lesjlcv_server:
    cmp r13, r12
    jae .Lesjlcv_bad
    mov al, [rbx + r13]
    cmp al, '/'
    je 3f
    cmp al, 92
    je 3f
    inc r13
    jmp .Lesjlcv_server
3:  cmp r13, 2
    je .Lesjlcv_bad
    cmp r13, 3
    jne 4f
    mov al, [rbx + 2]
    cmp al, '.'
    je .Lesjlcv_bad
    cmp al, '?'
    je .Lesjlcv_bad
4:  cmp r13, 4
    jne 5f
    cmp word ptr [rbx + 2], 0x2e2e
    je .Lesjlcv_bad
5:  lea r14, [r13 + 1]
    mov r15, r14
.Lesjlcv_share:
    cmp r15, r12
    jae 6f
    mov al, [rbx + r15]
    cmp al, '/'
    je 6f
    cmp al, 92
    je 6f
    inc r15
    jmp .Lesjlcv_share
6:  mov rax, r15
    sub rax, r14
    jz .Lesjlcv_bad
    cmp rax, 1
    jne 7f
    cmp byte ptr [rbx + r14], '.'
    je .Lesjlcv_bad
7:  cmp rax, 2
    jne 8f
    cmp word ptr [rbx + r14], 0x2e2e
    je .Lesjlcv_bad
8:  mov rax, r15
    xor edx, edx
    EPILOGUE
.Lesjlcv_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE

