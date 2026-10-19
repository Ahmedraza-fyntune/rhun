# Process context capture only. Network cwd lookup runs in the child bootstrap.
.include "win.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.section .rdata,"dr"
esjlw_path: .short 'P','A','T','H',0
esjlw_locale: .short 'L','C','_','A','L','L','=','C',0
esjlw_prefix: .short 'P','A','T','H','='
esjlw_cwdkey: .short 'R','H','U','N','_','L','E','G','A','C','Y','_','C','W','D','='
.text
FN win_ext_store_job_legacy_capture
    PROLOGUE 112
    mov rbx, rdi
    mov ecx, 4096
    lea rdx, [rbx + ELC_wcWbuf]
    API GetCurrentDirectoryW
    test eax, eax
    jz .Lesjlw_api
    cmp eax, 4096
    jae .Lesjlw_large
    mov r12d, eax
    mov ecx, 65001
    mov edx, 0x80
    lea r8, [rbx + ELC_wcWbuf]
    mov r9d, -1
    lea rax, [rbx + ELC_cwdbuf]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lesjlw_api
    lea rdi, [rbx + ELC_cwdbuf]
    call win_slashes
    lea rdi, [rbx + ELC_cwdbuf]
    call ext_store_job_legacy_volume
    test rax, rax
    js .Lesjlw_done
    mov [rbx + ELC_drive], rdx
    lea rax, [rbx + ELC_cwdbuf]
    mov [rbx + ELC_cwd], rax
    lea rax, [rbx + ELC_wcWbuf]
    mov [rbx + ELC_wcwd], rax
    xor ecx, ecx
    API SetLastError
    lea rcx, [rip + esjlw_path]
    lea rdx, [rbx + ELC_pathbuf]
    mov r8d, 32768
    API GetEnvironmentVariableW
    mov r13d, eax
    test eax, eax
    jnz .Lesjlw_path
    API GetLastError
    cmp eax, 203
    je .Lesjlw_environment
    test eax, eax
    jnz .Lesjlw_api
.Lesjlw_path:
    cmp r13d, 32767
    jae .Lesjlw_large
    mov qword ptr [rbx + ELC_path_present], 1
.Lesjlw_environment:
    lea rdi, [rbx + ELC_envbuf]
    lea rsi, [rip + esjlw_locale]
    mov edx, 18
    call memcpy
    lea r14, [rbx + ELC_envbuf + 18]
    cmp qword ptr [rbx + ELC_path_present], 0
    je 1f
    mov rdi, r14
    lea rsi, [rip + esjlw_prefix]
    mov edx, 10
    call memcpy
    lea rdi, [r14 + 10]
    lea rsi, [rbx + ELC_pathbuf]
    lea rdx, [r13*2 + 2]
    call memcpy
    lea r14, [r14 + r13*2 + 12]
1:  mov rdi, r14
    lea rsi, [rip + esjlw_cwdkey]
    mov edx, 32
    call memcpy
    lea rdi, [r14 + 32]
    lea rsi, [rbx + ELC_wcWbuf]
    lea rdx, [r12*2 + 2]
    call memcpy
    lea rax, [rbx + ELC_envbuf]
    mov [rbx + ELC_env], rax
    xor eax, eax
.Lesjlw_done:
    EPILOGUE
.Lesjlw_large:
    mov rax, -7
    EPILOGUE
.Lesjlw_api:
    call win_error
    EPILOGUE

# Child-only bounded conversion, then native directory operation under job deadline.
FN win_ext_store_job_legacy_chdir
    PROLOGUE 8320
    mov rbx, rdi
    mov ecx, 65001
    mov edx, 8
    mov r8, rbx
    mov r9d, -1
    lea rax, [rsp + 96]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 4096
    API MultiByteToWideChar
    test eax, eax
    jz 8f
    lea rcx, [rsp + 96]
    API SetCurrentDirectoryW
    test eax, eax
    jz 8f
    xor eax, eax
    EPILOGUE
8:  call win_error
    EPILOGUE
