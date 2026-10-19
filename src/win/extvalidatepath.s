# Native object-relative managed opens. Final reconciliation never allocates.
.include "win.inc"
.include "app/extvalidate.inc"
.text
# Internal trusted UTF16 open(parent,wide,byteCount,kind,flags), including root/empty reopen.
.Lwer_nt_open:
    xor r9d, r9d
.Lwer_nt_open_into:
    PROLOGUE 256
    mov [rsp + 232], r9
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
    mov eax, 0x200020         # no final reparse processing, synchronous IO
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
    js .Lwer_nt_error
    mov rax, [rsp + 232]
    test rax, rax
    jz 6f
    mov rcx, [rsp + 96]
    mov [rax], rcx
6:  mov rdi, [rsp + 96]
    lea rsi, [rsp + 192]
    call win_ext_root_stat
    test rax, rax
    js .Lwer_nt_close
    cmp r12, ER_ANY
    je .Lwer_nt_good
    cmp [rsp + 192 + ER_kind], r12
    je .Lwer_nt_good
    mov rax, -20
    cmp r12, ER_DIR
    je .Lwer_nt_close
    mov rax, -21
.Lwer_nt_close:
    cmp qword ptr [rsp + 232], 0
    je 7f
    xor edx, edx
    EPILOGUE
7:  mov r15, rax
    mov rdi, [rsp + 96]
    call win_ext_root_close
    mov rdx, rax
    mov rax, r15
    EPILOGUE
.Lwer_nt_good:
    mov rax, [rsp + 96]
    cmp qword ptr [rsp + 232], 0
    je 8f
    xor eax, eax
8:  xor edx, edx
    EPILOGUE
.Lwer_nt_error:
    mov ecx, eax
    API RtlNtStatusToDosError
    mov ecx, eax
    API SetLastError
    call win_error
    xor edx, edx
    EPILOGUE

# Internal prepared-native basename only. Caller owns validated counted UTF16 storage.
FN win_ext_root_open_prepared_at
    jmp .Lwer_nt_open

FN win_ext_root_open_at
    PROLOGUE 640
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsi
    call ext_root_name
    test rax, rax
    js .Lwer_at_name_error
    mov r15, rax
    cmp r13, ER_FILE
    jb .Lwer_at_bad
    cmp r13, ER_ANY
    ja .Lwer_at_bad
    test r14, -16
    jnz .Lwer_at_bad
    test r14, ER_EXCL
    jz 1f
    test r14, ER_CREATE
    jz .Lwer_at_bad
1:  cmp r13, ER_DIR
    jne 2f
    test r14, ER_WRITE
    jnz .Lwer_at_bad
2:  cmp r13, ER_ANY
    jne 3f
    test r14, 7
    jnz .Lwer_at_bad
3:  mov ecx, 65001
    mov edx, 8
    mov r8, r12
    mov r9, r15
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    API MultiByteToWideChar
    test eax, eax
    jz .Lwer_at_bad
    cmp eax, 255
    ja .Lwer_at_long
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
    jne .Lwer_at_bad
    mov rdi, rbx
    lea rsi, [rsp + 112]
    lea rdx, [rax*2]
    mov rcx, r13
    mov r8, r14
    call .Lwer_nt_open
.Lwer_at_done:
    EPILOGUE
.Lwer_at_name_error:
    xor edx, edx
    EPILOGUE
.Lwer_at_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lwer_at_long:
    mov rax, -36
    xor edx, edx
    EPILOGUE

FN win_ext_root_stat
    PROLOGUE 160
    mov rbx, rdi
    mov r12, rsi
    mov rcx, rdi
    API GetFileType
    cmp eax, 1
    jne .Lwer_stat_bad
    mov rcx, rbx
    lea rdx, [rsp + 96]
    API GetFileInformationByHandle
    test eax, eax
    jz .Lwer_stat_error
    test dword ptr [rsp + 96], 0x400
    jnz .Lwer_stat_link
    mov eax, ER_FILE
    test dword ptr [rsp + 96], 16
    jz 1f
    mov eax, ER_DIR
1:  mov [r12 + ER_kind], rax
    mov eax, [rsp + 128]
    shl rax, 32
    mov edx, [rsp + 132]
    or rax, rdx
    mov [r12 + ER_size], rax
    mov qword ptr [r12 + ER_exec], 0
    mov qword ptr [r12 + 24], 0
    xor eax, eax
    EPILOGUE
.Lwer_stat_error:
    call win_error
    EPILOGUE
.Lwer_stat_link:
    mov rax, -40
    EPILOGUE
.Lwer_stat_bad:
    mov rax, -22
    EPILOGUE

FN win_ext_root_identity
    PROLOGUE 192
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [rsp + 160]
    call win_ext_root_stat
    test rax, rax
    js 9f
    mov rcx, rbx
    lea rdx, [rsp + 96]
    API GetFileInformationByHandle
    test eax, eax
    jz 8f
    mov eax, [rsp + 124]
    mov [r12], rax
    mov eax, [rsp + 140]
    shl rax, 32
    mov edx, [rsp + 144]
    or rax, rdx
    mov [r12 + 8], rax
    mov qword ptr [r12 + 16], 0
    mov qword ptr [r12 + 24], 0
    xor eax, eax
9:  EPILOGUE
8:  call win_error
    EPILOGUE

FN win_ext_root_close
    PROLOGUE 96
    mov rcx, rdi
    API CloseHandle
    test eax, eax
    jz 8f
    xor eax, eax
    mov edx, 1
    EPILOGUE
8:  call win_error
    mov edx, 2                # no safe inference after failed CloseHandle
    EPILOGUE

FN win_ext_root_read
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov eax, 0xffffffff
    cmp rdx, rax
    ja .Lwer_read_bad
    test rcx, rcx
    js .Lwer_read_bad
    mov rcx, rbx
    mov rdx, r14
    xor r8d, r8d
    xor r9d, r9d
    API SetFilePointerEx
    test eax, eax
    jz .Lwer_read_error
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    API ReadFile
    test eax, eax
    jz .Lwer_read_error
    mov eax, [rsp + 96]
    EPILOGUE
.Lwer_read_bad:
    mov rax, -22
    EPILOGUE
.Lwer_read_error:
    call win_error
    EPILOGUE

FN win_ext_root_reopen_dir_into
    test rsi, rsi
    jz .Lwer_into_bad
    cmp qword ptr [rsi], -1
    jne .Lwer_into_bad
    mov r9, rsi
    lea rsi, [rip + .Lwer_empty]
    xor edx, edx
    mov ecx, ER_DIR
    xor r8d, r8d
    jmp .Lwer_nt_open_into
.Lwer_into_bad:
    mov rax, -22
    xor edx, edx
    ret

FN win_ext_root_reopen_dir
    lea rsi, [rip + .Lwer_empty]
    xor edx, edx
    mov ecx, ER_DIR
    xor r8d, r8d
    jmp .Lwer_nt_open

# Root prefix is opened once; all filesystem components thereafter use held handles.
FN win_ext_root_open
    PROLOGUE 12560
    mov qword ptr [rsp + 4192], 0
    mov rbx, rdi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lwer_root_bad
    mov r12, rax
    lea rdi, [rsp + 96]
    mov rsi, rbx
    lea rdx, [rax + 1]
    call memcpy
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp byte ptr [rsp + 96 + rcx], 92
    jne 11f
    mov byte ptr [rsp + 96 + rcx], '/'
11: inc rcx
    jmp 1b
2:  cmp r12, 3
    jb .Lwer_root_bad
    cmp byte ptr [rsp + 97], ':'
    jne .Lwer_root_unc
    cmp byte ptr [rsp + 98], '/'
    jne .Lwer_root_bad
    mov al, [rsp + 96]
    or al, 32
    cmp al, 'a'
    jb .Lwer_root_bad
    cmp al, 'z'
    ja .Lwer_root_bad
    mov r14d, 3
    jmp .Lwer_root_prefix
.Lwer_root_unc:
    cmp word ptr [rsp + 96], 0x2f2f
    jne .Lwer_root_bad
    mov r14d, 2
    mov r15d, 2
.Lwer_unc_component:
    mov rbx, r14
3:  cmp r14, r12
    jae 4f
    cmp byte ptr [rsp + 96 + r14], '/'
    je 4f
    inc r14
    jmp 3b
4:  movzx eax, byte ptr [rsp + 96 + r14]
    mov [rsp + 4200], rax
    mov byte ptr [rsp + 96 + r14], 0
    lea rdi, [rsp + 96 + rbx]
    call ext_root_name
    mov rcx, [rsp + 4200]
    mov [rsp + 96 + r14], cl
    test rax, rax
    js .Lwer_root_done
    dec r15
    jz .Lwer_root_prefix
    cmp r14, r12
    jae .Lwer_root_bad
    inc r14
    jmp .Lwer_unc_component
.Lwer_root_prefix:
    lea rbx, [rsp + 4224]
    mov rax, 0x005c003f003f005c # NT \??\ prefix
    mov [rbx], rax
    mov r15d, 4
    lea r8, [rsp + 96]
    mov r9, r14
    lea rax, [rbx + 8]
    cmp word ptr [rsp + 96], 0x2f2f
    jne 5f
    mov rdx, 0x005c0043004e0055 # UNC\
    mov [rbx + 8], rdx
    mov r15d, 8
    add r8, 2
    sub r9, 2
    lea rax, [rbx + 16]
5:  mov ecx, 65001
    mov edx, 8
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    API MultiByteToWideChar
    test eax, eax
    jz .Lwer_root_bad
    add r15, rax
    xor ecx, ecx
6:  cmp rcx, r15
    jae 61f
    cmp word ptr [rbx + rcx*2], '/'
    jne 60f
    mov word ptr [rbx + rcx*2], 92
60: inc rcx
    jmp 6b
61: mov word ptr [rbx + r15*2], 0
    xor edi, edi
    mov rsi, rbx
    lea rdx, [r15*2]
    mov ecx, ER_DIR
    xor r8d, r8d
    call .Lwer_nt_open
    mov [rsp + 4192], rdx
    mov r13, rax
    test rax, rax
    js .Lwer_root_done
.Lwer_root_next:
    cmp r14, r12
    jae .Lwer_root_success
    cmp byte ptr [rsp + 96 + r14], '/'
    jne 7f
    inc r14
    jmp .Lwer_root_next
7:  mov r15, r14
8:  cmp r14, r12
    jae 81f
    cmp byte ptr [rsp + 96 + r14], '/'
    je 81f
    inc r14
    jmp 8b
81: mov byte ptr [rsp + 96 + r14], 0
    mov rdi, r13
    lea rsi, [rsp + 96 + r15]
    mov edx, ER_DIR
    xor ecx, ecx
    xor r8d, r8d
    call win_ext_root_open_at
    mov r15, rax
    mov [rsp + 4192], rdx
    mov rdi, r13
    call win_ext_root_close
    test rax, rax
    jns .Lwer_parent_closed
    cmp qword ptr [rsp + 4192], 0
    jne .Lwer_parent_closed
    mov [rsp + 4192], rax
.Lwer_parent_closed:
    test r15, r15
    js .Lwer_root_child_error
    cmp qword ptr [rsp + 4192], 0
    jne .Lwer_root_close_new
    mov r13, r15
    inc r14
    jmp .Lwer_root_next
.Lwer_root_child_error:
    mov rax, r15
    jmp .Lwer_root_done
.Lwer_root_close_new:
    mov r13, [rsp + 4192]
    mov rdi, r15
    call win_ext_root_close
.Lwer_root_result:
    mov rax, r13
    jmp .Lwer_root_done
.Lwer_root_success:
    mov rax, r13
    jmp .Lwer_root_done
.Lwer_root_bad:
    mov rax, -22
.Lwer_root_done:
    mov rdx, [rsp + 4192]
    EPILOGUE
.section .rodata
.Lwer_empty: .word 0
