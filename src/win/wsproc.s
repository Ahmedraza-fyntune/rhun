# wsedit on Windows: whether the process that wrote a workspace-edit journal still runs
.include "win.inc"
.text

# FN win_pid_alive(pid) -> eax 1 when a process with that id runs
FN win_pid_alive
    PROLOGUE 96
    mov r8d, edi
    mov ecx, 0x1000             # PROCESS_QUERY_LIMITED_INFORMATION
    xor edx, edx
    API OpenProcess
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rax
    lea rdx, [rsp + 80]
    mov dword ptr [rdx], 0
    API GetExitCodeProcess
    mov r12d, eax
    mov rcx, rbx
    API CloseHandle
    test r12d, r12d
    jz 8f
    cmp dword ptr [rsp + 80], 259   # STILL_ACTIVE
    jne 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
