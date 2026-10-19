# Helper-only ordinary legacy target-following opens.
.include "win.inc"
.include "app/extvalidate.inc"
.text
.Lwel_nt_open:
    PROLOGUE 240
    mov rbx, rdi
    mov r14, rsi
    mov r15, rdx
    mov r12, rcx
    mov r13, r8
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 120], 48
    mov [rsp + 128], rbx
    lea rax, [rsp + 168]
    mov [rsp + 136], rax
    mov qword ptr [rsp + 144], 0x40 # OBJ_CASE_INSENSITIVE, never OBJ_INHERIT
    mov qword ptr [rsp + 152], 0
    mov qword ptr [rsp + 160], 0
    mov word ptr [rsp + 168], r15w
    mov word ptr [rsp + 170], r15w
    mov dword ptr [rsp + 172], 0
    mov [rsp + 176], r14
    lea rcx, [rsp + 96]
    mov edx, 0x00120089        # FILE_GENERIC_READ, SYNCHRONIZE
    test r13, ER_WRITE
    jz 1f
    mov edx, 0x0012019f        # read/write, no truncate
1:  test r13, ER_DELETE
    jz 2f
    or edx, 0x10000
2:  lea r8, [rsp + 120]
    lea r9, [rsp + 104]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 7
    mov eax, 1                # FILE_OPEN
    test r13, ER_CREATE
    jz 3f
    mov eax, 3                # FILE_OPEN_IF
    test r13, ER_EXCL
    jz 3f
    mov eax, 2                # FILE_CREATE
3:  mov [rsp + 56], rax
    mov eax, 0x20         # no final reparse processing, synchronous IO
    cmp r12, ER_DIR
    jne 4f
    or eax, 1                 # FILE_DIRECTORY_FILE
    jmp 5f
4:  cmp r12, ER_FILE
    jne 5f
    or eax, 0x40              # FILE_NON_DIRECTORY_FILE
5:  mov [rsp + 64], rax
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
    API NtCreateFile
    test eax, eax
    js .Lwel_nt_error
    mov rdi, [rsp + 96]
    lea rsi, [rsp + 192]
    call win_ext_root_stat
    test rax, rax
    js .Lwel_nt_close
    cmp r12, ER_ANY
    je .Lwel_nt_good
    cmp [rsp + 192 + ER_kind], r12
    je .Lwel_nt_good
    mov rax, -20
    cmp r12, ER_DIR
    je .Lwel_nt_close
    mov rax, -21
.Lwel_nt_close:
    mov r15, rax
    mov rdi, [rsp + 96]
    call win_ext_root_close
    mov rdx, rax
    mov rax, r15
    EPILOGUE
.Lwel_nt_good:
    mov rax, [rsp + 96]
    xor edx, edx
    EPILOGUE
.Lwel_nt_error:
    mov ecx, eax
    API RtlNtStatusToDosError
    mov ecx, eax
    API SetLastError
    call win_error
    xor edx, edx
    EPILOGUE

FN win_prep_legacy_open_at
    PROLOGUE 640
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    mov rdi, rsi
    call ext_root_name
    test rax, rax
    js .Lwel_at_name_error
    mov r15, rax
    cmp r13, ER_FILE
    jb .Lwel_at_bad
    cmp r13, ER_ANY
    ja .Lwel_at_bad
    test r14, -16
    jnz .Lwel_at_bad
    test r14, ER_EXCL
    jz 1f
    test r14, ER_CREATE
    jz .Lwel_at_bad
1:  cmp r13, ER_DIR
    jne 2f
    test r14, ER_WRITE
    jnz .Lwel_at_bad
2:  cmp r13, ER_ANY
    jne 3f
    test r14, 7
    jnz .Lwel_at_bad
3:  mov ecx, 65001
    mov edx, 8
    mov r8, r12
    mov r9, r15
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz .Lwel_at_bad
    cmp eax, 255
    ja .Lwel_at_long
    mov [rsp + 96], rax
    mov ecx, 65001
    mov edx, 8
    mov r8, r12
    mov r9, r15
    lea rax, [rsp + 112]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 256
    API MultiByteToWideChar
    cmp rax, [rsp + 96]
    jne .Lwel_at_bad
    mov rdi, rbx
    lea rsi, [rsp + 112]
    lea rdx, [rax*2]
    mov rcx, r13
    mov r8, r14
    call .Lwel_nt_open
.Lwel_at_done:
    EPILOGUE
.Lwel_at_name_error:
    xor edx, edx
    EPILOGUE
.Lwel_at_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lwel_at_long:
    mov rax, -36
    xor edx, edx
    EPILOGUE

# Normalize ordinary Win32 dot/dotdot before long-path prefix construction.
FN win_prep_legacy_open_absolute
    PROLOGUE 17024
    mov rbx, rdi
    mov r13, rsi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lwela_bad
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call ext_validate_text
    test eax, eax
    jz .Lwela_bad
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9, r12
    lea rax, [rsp + 128]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    API MultiByteToWideChar
    test eax, eax
    jz .Lwela_bad
    mov r12, rax
    mov word ptr [rsp + 128 + r12*2], 0
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp word ptr [rsp + 128 + rcx*2], '/'
    jne 11f
    mov word ptr [rsp + 128 + rcx*2], 92
11: inc rcx
    jmp 1b
2:  lea rcx, [rsp + 128]
    mov edx, 4096
    lea r8, [rsp + 8448]
    xor r9d, r9d
    API GetFullPathNameW
    test eax, eax
    jz .Lwela_native_error
    cmp eax, 4096
    jae .Lwela_bad
    mov r12, rax
    cmp r12, 3
    jb .Lwela_bad
    cmp word ptr [rsp + 8450], ':'
    jne .Lwela_unc
    cmp word ptr [rsp + 8452], 92
    jne .Lwela_bad
    movzx eax, word ptr [rsp + 8448]
    or eax, 32
    sub eax, 'a'
    cmp eax, 25
    ja .Lwela_bad
    mov rax, 0x005c003f005c005c
    mov [rsp + 8440], rax
    lea r14, [rsp + 8440]
    jmp .Lwela_open
.Lwela_unc:
    cmp r12, 5
    jb .Lwela_bad
    cmp dword ptr [rsp + 8448], 0x005c005c
    jne .Lwela_bad
    cmp word ptr [rsp + 8452], '?'
    je .Lwela_bad
    cmp word ptr [rsp + 8452], '.'
    je .Lwela_bad
    mov rax, 0x005c003f005c005c
    mov [rsp + 8436], rax
    mov rax, 0x005c0043004e0055
    mov [rsp + 8444], rax
    lea r14, [rsp + 8436]
.Lwela_open:
    mov rcx, r14
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02000000
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lwela_native_error
    mov r12, rax
    mov rdi, rax
    lea rsi, [rsp + 16800]
    call win_ext_root_stat
    test rax, rax
    js .Lwela_close
    cmp r13, ER_ANY
    je .Lwela_good
    cmp [rsp + 16800 + ER_kind], r13
    je .Lwela_good
    mov rax, -EV_BAD_PATH
.Lwela_close:
    mov r13, rax
    mov rdi, r12
    call win_ext_root_close
    mov rdx, rax
    mov rax, r13
    EPILOGUE
.Lwela_good:
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Lwela_native_error:
    call win_error
    xor edx, edx
    EPILOGUE
.Lwela_bad:
    mov rax, -EV_BAD_PATH
    xor edx, edx
    EPILOGUE

.text
# Stack-only cwd conversion, ordinary local process context rather than a filesystem read.
FN win_prep_legacy_cwd
    PROLOGUE 8352
    mov rbx, rdi
    mov ecx, 4096
    lea rdx, [rsp + 96]
    API GetCurrentDirectoryW
    test eax, eax
    jz .Lwelcwd_error
    cmp eax, 4096
    jae .Lwelcwd_bad
    mov r12, rax
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rsp + 96]
    mov r9, r12
    mov [rsp + 32], rbx
    mov qword ptr [rsp + 40], 4095
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lwelcwd_error
    cmp eax, 4095
    ja .Lwelcwd_bad
    mov byte ptr [rbx + rax], 0
    mov r12, rax
    mov rdi, rbx
    call win_slashes
    lea rax, [r12 + 1]
    EPILOGUE
.Lwelcwd_error:
    call win_error
    EPILOGUE
.Lwelcwd_bad:
    mov rax, -EV_BAD_PATH
    EPILOGUE
