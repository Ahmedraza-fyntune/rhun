# Raw handles from ext_root_* only. No virtual descriptor indirection on Windows.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extstore.inc"
.text
# ext_store_raw_lock(raw,exclusive0|1)->0/-errno.
FN ext_store_raw_lock
    cmp rsi, 1
    ja .Lesio_invalid
.ifdef WINDOWS
    PROLOGUE 128
    mov rcx, rdi
    lea edx, [rsi*2 + 1]
    xor r8d, r8d
    mov r9d, 1
    mov qword ptr [rsp + 32], 0
    lea rax, [rsp + 96]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 104], 0
    mov qword ptr [rsp + 112], 0
    mov qword ptr [rsp + 120], 0
    API LockFileEx
    test eax, eax
    jnz 1f
    API GetLastError
    cmp eax, 33
    jne 2f
    mov rax, -11
    EPILOGUE
2:  call win_error
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
.else
    jmp file_lock_try
.endif
.Lesio_invalid:
    mov rax, -22
    ret

# ext_store_raw_write(raw,bytes,count)->written/-errno, one native operation.
FN ext_store_raw_write
.ifdef WINDOWS
    PROLOGUE 112
    mov rcx, rdi
    mov r8, rdx
    mov rdx, rsi
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 0
    API WriteFile
    test eax, eax
    jz 1f
    mov eax, [rsp + 96]
    EPILOGUE
1:  call win_error
    EPILOGUE
.else
    SYS SYS_write
    ret
.endif

# ext_store_raw_sync(raw)->0/-errno.
FN ext_store_raw_sync
.ifdef WINDOWS
    PROLOGUE 96
    mov rcx, rdi
    API FlushFileBuffers
    test eax, eax
    jnz 1f
    call win_error
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
.else
    SYS SYS_fsync
    ret
.endif

# ext_store_raw_rename(parent,source,destination,winSource,renameInfo,iosb)->0/-errno.
# All native request storage belongs to ESW. No path conversion or allocator here.
FN ext_store_raw_rename
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, r9
    mov rdx, r9
    # rcx is the retained source raw handle, r8 is FILE_RENAME_INFORMATION.
    mov r9d, 60               # 20-byte header plus canonical20 UTF16 characters
    mov qword ptr [rsp + 32], 10
    API NtSetInformationFile
    cmp eax, 0x103
    je 2f
    test eax, eax
    jz 1f
    js 3f
    mov rax, -5
    EPILOGUE
3:  call .Lesio_nt_error
    EPILOGUE
2:  mov rax, -115             # asynchronous result retains source+IOSB ownership
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
.else
.ifdef MACOS
    jmp mac_ext_store_rename
.else
    mov r10, rdx
    mov rdx, rdi
    mov r8d, 1                # RENAME_NOREPLACE
    SYS SYS_renameat2
    ret
.endif
.endif

# ext_store_raw_rename_poll(winSource,iosb)->completed status/-EINPROGRESS.
FN ext_store_raw_rename_poll
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, rsi
    mov rcx, rdi
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je 2f
    test eax, eax
    jnz 6f
    mov eax, [rbx]
    cmp eax, 0x103
    je 2f
    test eax, eax
    jz 1f
    js 4f
3:  mov rax, -5
    xor edx, edx
    EPILOGUE
6:  mov rax, -115
    mov rdx, -5
    EPILOGUE
4:  call .Lesio_nt_error
    EPILOGUE
2:  mov rax, -115
    xor edx, edx
    EPILOGUE
1:  xor eax, eax
    xor edx, edx
    EPILOGUE
.else
    mov rax, -22
    ret
.endif

.ifdef WINDOWS
.Lesio_nt_error:
    PROLOGUE 96
    mov ecx, eax
    API RtlNtStatusToDosError
    mov ecx, eax
    API SetLastError
    call win_error
    EPILOGUE
.endif

# Initialize private storage only before first use or after established completion.
FN ext_store_unlink_init
    PROLOGUE
    mov rbx, rdi
    xor esi, esi
    mov edx, ESU_SIZE
    call memset
    mov qword ptr [rbx + ESU_raw], -1
    xor eax, eax
    EPILOGUE

# ext_store_raw_unlink(parent,basename,persistentESU)->0/-errno or-EINPROGRESS.
# ESU belongs to caller until completion. Windows deletes the actual opened object.
FN ext_store_raw_unlink
.ifdef WINDOWS
    cmp qword ptr [rdx + ESU_pending], 0
    je 9f
    mov rax, -16
    xor edx, edx
    ret
9:  PROLOGUE
    mov rbx, rdx
    mov edx, 1
    mov ecx, 8
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js 1f
    mov rdi, rax
    mov rsi, rbx
    call ext_store_unlink_handle_try
1:  EPILOGUE
.else
.ifdef MACOS
    call mac_ext_store_unlink
.else
    xor edx, edx
    SYS 263                   # unlinkat, cooperative held-guard trust boundary
.endif
    xor edx, edx
    ret
.endif

# Takes ownership of Windows raw DELETE handle, including pending native work.
FN ext_store_unlink_handle_try
.ifdef WINDOWS
    cmp qword ptr [rsi + ESU_pending], 0
    je 9f
    mov rax, -16
    xor edx, edx
    ret                       # busy rejects before taking incoming raw ownership
9:  PROLOGUE 96
    mov rbx, rsi
    mov [rbx + ESU_raw], rdi
    mov qword ptr [rbx + ESU_iosb], 0x103
    mov qword ptr [rbx + ESU_iosb + 8], 0
    mov byte ptr [rbx + ESU_disposition], 1
    mov qword ptr [rbx + ESU_pending], 0
    mov qword ptr [rbx + ESU_observation], 0
    mov qword ptr [rbx + ESU_status], 0
    mov qword ptr [rbx + ESU_secondary], 0
    mov rcx, rdi
    lea rdx, [rbx + ESU_iosb]
    lea r8, [rbx + ESU_disposition]
    mov r9d, 1
    mov qword ptr [rsp + 32], 13
    API NtSetInformationFile
    cmp eax, 0x103
    jne 1f
    mov qword ptr [rbx + ESU_pending], 1
    mov rax, -115
    xor edx, edx
    EPILOGUE
1:  test eax, eax
    jz 2f
    js 3f
    mov rax, -5
    jmp 2f
3:  call .Lesio_nt_error
2:  call .Lesio_unlink_complete
    EPILOGUE
.else
    mov rax, -22
    xor edx, edx
    ret
.endif

# Poll observation failures retain ownership exactly like a still-pending request.
FN ext_store_unlink_poll
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, rdi
    cmp qword ptr [rbx + ESU_pending], 1
    jne 4f
    mov rcx, [rbx + ESU_raw]
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je 2f
    test eax, eax
    jnz 3f
    mov eax, [rbx + ESU_iosb]
    cmp eax, 0x103
    je 2f
    test eax, eax
    jz 1f
    js 5f
    mov rax, -5
    jmp 1f
5:  call .Lesio_nt_error
1:  mov qword ptr [rbx + ESU_pending], 0
    call .Lesio_unlink_complete
    EPILOGUE
3:  mov qword ptr [rbx + ESU_observation], -5
2:  mov rax, -115
    xor edx, edx
    EPILOGUE
4:  mov rax, [rbx + ESU_status]
    mov rdx, [rbx + ESU_secondary]
    EPILOGUE
.else
    xor eax, eax
    xor edx, edx
    ret
.endif
.ifdef WINDOWS
# rbx persistent ESU, rax completed primary status; close only after completion.
.Lesio_unlink_complete:
    PROLOGUE
    mov r12, rax
    mov rdi, [rbx + ESU_raw]
    mov qword ptr [rbx + ESU_raw], -1
    call ext_root_close
    xor edx, edx
    test r12, r12
    jz 1f
    mov rdx, rax
    mov rax, r12
1:  mov [rbx + ESU_status], rax
    mov [rbx + ESU_secondary], rdx
    EPILOGUE
.endif

FN ext_store_raw_pid
.ifdef WINDOWS
    PROLOGUE 96
    API GetCurrentProcessId
    EPILOGUE
.else
    SYS SYS_getpid
    ret
.endif
