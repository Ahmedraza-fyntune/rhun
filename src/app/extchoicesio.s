# Prepared rooted settings creation/replacement, with no compensation or path fallback.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/extchoicesdisk.inc"
.text

# raw_create(parent,basename,wideName,wideByteLen,SD)->raw/-errno. No classification.
FN ext_choices_raw_create
.ifdef WINDOWS
    PROLOGUE 240
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov qword ptr [rsp + 96], 0
    mov qword ptr [rsp + 120], 48
    mov [rsp + 128], rbx
    lea rax, [rsp + 168]
    mov [rsp + 136], rax
    mov qword ptr [rsp + 144], 0x40
    mov [rsp + 152], r14
    mov qword ptr [rsp + 160], 0
    mov word ptr [rsp + 168], r13w
    mov word ptr [rsp + 170], r13w
    mov dword ptr [rsp + 172], 0
    mov [rsp + 176], r12
    lea rcx, [rsp + 96]
    mov edx, 0x0013019f        # read/write/delete/synchronize
    lea r8, [rsp + 120]
    lea r9, [rsp + 104]
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 7
    mov qword ptr [rsp + 56], 2 # FILE_CREATE, never overwrite or truncate.
    mov qword ptr [rsp + 64], 0x200060 # no reparse, synchronous nonalert, nondirectory.
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
    API NtCreateFile          # synchronous file creation completes before return.
    test eax, eax
    js 1f
    mov rax, [rsp + 96]
    xor edx, edx
    EPILOGUE
1:  call .Leci_nt_error
    xor edx, edx
    EPILOGUE
.else
    mov edx, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    mov r10d, 0600
1:  SYS SYS_openat
    cmp rax, -EINTR
    je 1b
    xor edx, edx
    ret
.endif

# raw_replace(parent,source,destination,sourceHandle,renameInfo,IOSB)->0/-errno.
# All request storage belongs to ECP, including the Windows pending lifetime.
FN ext_choices_raw_replace
.ifdef WINDOWS
    PROLOGUE 96
    mov rdx, r9
    mov r9d, 48               # header20 + extensions.ini UTF16(28).
    mov qword ptr [rsp + 32], 10
    API NtSetInformationFile
    cmp eax, 0x103
    je 1f
    test eax, eax
    jz 2f
    js 3f
    mov rax, -5
    xor edx, edx
    EPILOGUE
3:  call .Leci_nt_error
    xor edx, edx
    EPILOGUE
1:  mov rax, -115
    xor edx, edx
    EPILOGUE
2:  xor eax, eax
    xor edx, edx
    EPILOGUE
.else
.ifdef MACOS
    call mac_ext_choices_replace
.else
    mov r10, rdx
    mov rdx, rdi
    xor r8d, r8d              # rooted replacement, no copy/inverse operation.
    SYS SYS_renameat2
.endif
    xor edx, edx
    ret
.endif

# raw_replace_poll(source,IOSB)->completed0/-errno or-115,RDX observation failure.
FN ext_choices_raw_replace_poll
.ifdef WINDOWS
    PROLOGUE 96
    mov rbx, rsi
    mov rcx, rdi
    xor edx, edx
    API WaitForSingleObject
    cmp eax, 258
    je 1f
    test eax, eax
    jnz 2f
    mov eax, [rbx]
    cmp eax, 0x103
    je 1f
    test eax, eax
    jz 3f
    js 4f
2:  mov rax, -115             # failed observation never proves completion.
    mov rdx, -5
    EPILOGUE
4:  call .Leci_nt_error
    xor edx, edx
    EPILOGUE
1:  mov rax, -115
    xor edx, edx
    EPILOGUE
3:  xor eax, eax
    xor edx, edx
    EPILOGUE
.else
    mov rax, -22
    xor edx, edx
    ret
.endif

.ifdef WINDOWS
.Leci_nt_error:
    PROLOGUE 96
    mov ecx, eax
    API RtlNtStatusToDosError
    mov ecx, eax
    API SetLastError
    call win_error
    EPILOGUE
.endif
