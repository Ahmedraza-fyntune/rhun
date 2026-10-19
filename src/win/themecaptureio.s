# Child-only user source IO. Paths follow ordinary links; actual handles must be disk files.
.include "win.inc"
.include "app/themecapture.inc"
.text
FN win_tc_file_open
    PROLOGUE 112
    mov rbx, rdi
    mov edi, 32768
    call tc_charge_reserve
    test rax, rax
    js 9f
    mov rdi, rbx
    call win_file_path_try
    test rax, rax
    jz 7f
    mov r12, rax
    mov rcx, rax
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    mov r13, rax
    cmp rax, -1
    jne 2f
    API GetLastError
    cmp eax, 997
    je .Ltcio_pending
    call win_error
    mov r13, rax
2:  mov rdi, r12
    call mem_free
    mov edi, 32768
    call tc_charge_release
    mov rax, r13
9:  EPILOGUE
7:  mov r13, rdx
    mov edi, 32768
    call tc_charge_release
    mov rax, r13
    EPILOGUE
FN win_tc_file_stat
    PROLOGUE 160
    mov rbx, rdi
    mov r12, rsi
    mov rcx, rbx
    API GetFileType
    test eax, eax
    jz .Ltcio_error
    cmp eax, 1
    jne .Ltcio_bad
    mov rcx, rbx
    lea rdx, [rsp + 96]
    API GetFileInformationByHandle
    test eax, eax
    jz .Ltcio_error
    test dword ptr [rsp + 96], 16
    jnz .Ltcio_bad
    mov eax, [rsp + 124]
    mov [r12 + TCSTAT_dev], rax
    mov eax, [rsp + 140]
    shl rax, 32
    mov edx, [rsp + 144]
    or rax, rdx
    mov [r12 + TCSTAT_ino], rax
    mov eax, [rsp + 128]
    shl rax, 32
    mov edx, [rsp + 132]
    or rax, rdx
    mov [r12 + TCSTAT_length], rax
    mov rax, [rsp + 116]
    mov [r12 + TCSTAT_mtime], rax
    mov qword ptr [r12 + TCSTAT_mtime_ns], 0
    mov rax, [rsp + 100]
    mov [r12 + TCSTAT_ctime], rax
    mov qword ptr [r12 + TCSTAT_ctime_ns], 0
    mov qword ptr [r12 + TCSTAT_type], 0x8000
    xor eax, eax
    EPILOGUE
.Ltcio_bad:
    mov rax, -22
    EPILOGUE
.Ltcio_error:
    API GetLastError
    cmp eax, 997
    je .Ltcio_pending
    call win_error
    EPILOGUE
FN win_tc_file_read
    PROLOGUE 112
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rcx, rbx
    mov rdx, r14
    lea r8, [rsp + 96]
    xor r9d, r9d
    API SetFilePointerEx
    test eax, eax
    jz .Ltcio_read_error
    cmp [rsp + 96], r14
    jne .Ltcio_read_bad
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    lea r9, [rsp + 104]
    mov qword ptr [rsp + 32], 0
    API ReadFile
    test eax, eax
    jz .Ltcio_read_error
    mov eax, [rsp + 104]
    cmp rax, r13
    ja .Ltcio_read_bad
    EPILOGUE
.Ltcio_read_bad:
    mov rax, -5
    EPILOGUE
.Ltcio_read_error:
    API GetLastError
    cmp eax, 997
    je .Ltcio_pending
    call win_error
    EPILOGUE
# Synchronous regular operations cannot normally pend. Never retire unknown kernel storage.
.Ltcio_pending:
    mov edi, 70
    call sys_exit

# GetFileAttributes observes an ordinary entry, including a dangling user link.
FN win_tc_marker_presence
    PROLOGUE 96
    mov rbx, rdi
    mov rdi, rsi
    call tc_before_deadline
    test rax, rax
    js 9f
    mov edi, 32768
    call tc_charge_reserve
    test rax, rax
    js 9f
    mov rdi, rbx
    call win_file_path_try
    test rax, rax
    jz 7f
    mov r12, rax
    mov rcx, rax
    API GetFileAttributesW
    cmp eax, -1
    jne 1f
    API GetLastError
    cmp eax, 997
    je .Ltcio_pending
    cmp eax, 2
    je 2f
    cmp eax, 3
    je 2f
    call win_error
    mov r13, rax
    jmp 3f
1:  mov r13d, 1
    jmp 3f
2:  xor r13d, r13d
3:  mov rdi, r12
    call mem_free
    mov edi, 32768
    call tc_charge_release
    mov rax, r13
9:  EPILOGUE
7:  mov r13, rdx
    mov edi, 32768
    call tc_charge_release
    mov rax, r13
    EPILOGUE
