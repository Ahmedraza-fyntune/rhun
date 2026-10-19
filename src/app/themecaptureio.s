# Isolated helper only. Follow ordinary user symlinks and retain only stable regular bytes.
.include "rhun.inc"
.include "app/themecapture.inc"
.text
# capture(path,max<=65536,out48,absoluteDeadline)->primary/cleanup; out untouched on failure.
FN tc_file_capture
    PROLOGUE 288
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsp
    xor esi, esi
    mov edx, 288
    call memset
    mov qword ptr [rsp + 224], -1
    mov [rsp + 200], r12
    mov [rsp + 208], r13
    mov [rsp + 216], r14
    test r13, r13
    jz .Ltcfc_bad
    test r14, r14
    jle .Ltcfc_bad
    cmp r12, TC_THEME_CAP
    ja .Ltcfc_bad
    mov rdi, rbx
    call tc_path_len
    test rax, rax
    js .Ltcfc_error
.Ltcfc_open:
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcfc_error
    mov rdi, rbx
    call tc_file_open
    cmp rax, -EINTR
    je .Ltcfc_open
    test rax, rax
    js .Ltcfc_error
    mov [rsp + 224], rax
.Ltcfc_stat_before:
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcfc_error
    mov rdi, [rsp + 224]
    mov rsi, rsp
    call tc_file_stat
    cmp rax, -EINTR
    je .Ltcfc_stat_before
    test rax, rax
    js .Ltcfc_error
    mov r15, [rsp + TCSTAT_length]
    cmp r15, r12
    ja .Ltcfc_large
    mov [rsp + 264], r15
    lea rdi, [r15 + 1]
    call tc_alloc_try
    test rax, rax
    jz .Ltcfc_oom
    mov [rsp + 248], rax
    lea rdi, [r15 + 1]
    call tc_alloc_try
    test rax, rax
    jz .Ltcfc_oom
    mov [rsp + 256], rax
    mov rdi, [rsp + 224]
    mov rsi, [rsp + 248]
    mov rdx, r15
    mov rcx, r14
    call tc_file_pass
    test rax, rax
    js .Ltcfc_error
    mov rdi, [rsp + 248]
    mov rsi, r15
    lea rdx, [rsp + 128]
    call sha256_hash
    test eax, eax
    jz .Ltcfc_io
    mov rdi, [rsp + 224]
    mov rsi, [rsp + 256]
    mov rdx, r15
    mov rcx, r14
    call tc_file_pass
    test rax, rax
    js .Ltcfc_error
    mov rdi, [rsp + 256]
    mov rsi, r15
    lea rdx, [rsp + 160]
    call sha256_hash
    test eax, eax
    jz .Ltcfc_io
    lea rdi, [rsp + 128]
    lea rsi, [rsp + 160]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Ltcfc_changed
.Ltcfc_stat_after:
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js .Ltcfc_error
    mov rdi, [rsp + 224]
    lea rsi, [rsp + 64]
    call tc_file_stat
    cmp rax, -EINTR
    je .Ltcfc_stat_after
    test rax, rax
    js .Ltcfc_error
    mov rdi, rsp
    lea rsi, [rsp + 64]
    mov edx, TCSTAT_SIZE
    call memeq
    test eax, eax
    jz .Ltcfc_changed
    jmp .Ltcfc_close
.Ltcfc_bad:
    mov rax, -22
    jmp .Ltcfc_error
.Ltcfc_large:
    mov rax, -27
    jmp .Ltcfc_error
.Ltcfc_oom:
    mov rax, -12
    jmp .Ltcfc_error
.Ltcfc_io:
    mov rax, -5
    jmp .Ltcfc_error
.Ltcfc_changed:
    mov rax, -1008
.Ltcfc_error:
    mov [rsp + 232], rax
.Ltcfc_close:
    mov rdi, [rsp + 224]
    mov qword ptr [rsp + 224], -1
    test rdi, rdi
    js 1f
    call tc_file_close
    test rax, rax
    jns 1f
    mov [rsp + 240], rax
1:  cmp qword ptr [rsp + 232], 0
    jne 2f
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    jns 2f
    mov [rsp + 232], rax
2:  lea rdi, [rsp + 256]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 3f
    cmp qword ptr [rsp + 240], 0
    jne 3f
    mov [rsp + 240], rax
3:  mov rax, [rsp + 232]
    or rax, [rsp + 240]
    jnz .Ltcfc_dispose
    mov rdi, r14
    call tc_before_deadline
    test rax, rax
    jns 5f
    mov [rsp + 232], rax
    jmp .Ltcfc_dispose
5:  mov rdi, [rsp + 248]
    mov byte ptr [rdi + r15], 0
    mov [r13 + TCIO_bytes], rdi
    mov [r13 + TCIO_length], r15
    lea rdi, [r13 + TCIO_digest]
    lea rsi, [rsp + 128]
    mov edx, 32
    call memcpy
    mov qword ptr [rsp + 248], 0
.Ltcfc_dispose:
    lea rdi, [rsp + 248]
    mov rsi, r14
    call tc_file_release
    test rax, rax
    jns 4f
    cmp qword ptr [rsp + 240], 0
    jne 4f
    mov [rsp + 240], rax
4:  mov rax, [rsp + 232]
    mov rdx, [rsp + 240]
    EPILOGUE

# Isolated helper only. A stack-owned pointer cannot escape after failed release.
# One attempt per pass; nonzero exit on deadline leaves OS-owned process lifetime intact.
FN tc_file_release
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  mov rdi, [rbx]
    call tc_free
    test rax, rax
    jns 2f
    test r13, r13
    jnz 2f
    mov r13, rax
2:  test rdx, rdx
    jnz 3f
    mov rdi, r12
    call tc_before_deadline
    test rax, rax
    js 4f
    call tc_helper_wait
    jmp 1b
3:  mov qword ptr [rbx], 0
    mov rax, r13
    EPILOGUE
4:  mov edi, 70
    call sys_exit
FN tc_helper_wait
    PROLOGUE 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 1000000
    mov rdi, rsp
    xor esi, esi
    SYS 35
    EPILOGUE
# Both exact passes start at offset0. Probe a further byte even for an empty initial file.
FN tc_file_pass
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    xor r15d, r15d
1:  mov rdi, r14
    call tc_before_deadline
    test rax, rax
    js 9f
    cmp r15, r13
    jae 3f
    mov rdi, rbx
    lea rsi, [r12 + r15]
    mov rdx, r13
    sub rdx, r15
    mov rcx, r15
    call tc_file_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    jz 7f
    mov rcx, r13
    sub rcx, r15
    cmp rax, rcx
    ja 8f
    add r15, rax
    jmp 1b
3:  mov rdi, rbx
    mov rsi, rsp
    mov edx, 1
    mov rcx, r13
    call tc_file_read
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js 9f
    jnz 7f
    xor eax, eax
9:  EPILOGUE
7:  mov rax, -1008
    EPILOGUE
8:  mov rax, -5
    EPILOGUE
FN tc_before_deadline
    PROLOGUE
    mov rbx, rdi
    call time_ms
    cmp rax, rbx
    jae 1f
    xor eax, eax
    EPILOGUE
1:  mov rax, -110
    EPILOGUE
FN tc_file_open
.ifdef WINDOWS
    jmp win_tc_file_open
.else
    mov esi, O_RDONLY | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    SYS SYS_open
    ret
.endif
FN tc_file_read
.ifdef WINDOWS
    jmp win_tc_file_read
.else
    mov r10, rcx
    SYS SYS_pread
    ret
.endif
FN tc_file_close
.ifdef WINDOWS
    jmp win_ext_root_close
.else
    SYS SYS_close
    ret
.endif
# Canonical actual-handle observation excludes access time and unrelated padding.
FN tc_file_stat
.ifdef WINDOWS
    jmp win_tc_file_stat
.else
    PROLOGUE 144
    mov r12, rsi
    mov rsi, rsp
    SYS SYS_fstat
    test rax, rax
    js 9f
    mov eax, [rsp + 24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne 8f
    mov qword ptr [r12 + TCSTAT_type], 0x8000
    mov rax, [rsp]
    mov [r12 + TCSTAT_dev], rax
    mov rax, [rsp + 8]
    mov [r12 + TCSTAT_ino], rax
    mov rax, [rsp + 48]
    mov [r12 + TCSTAT_length], rax
    mov rax, [rsp + 88]
    mov [r12 + TCSTAT_mtime], rax
    mov rax, [rsp + 96]
    mov [r12 + TCSTAT_mtime_ns], rax
    mov rax, [rsp + 104]
    mov [r12 + TCSTAT_ctime], rax
    mov rax, [rsp + 112]
    mov [r12 + TCSTAT_ctime_ns], rax
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
.endif
