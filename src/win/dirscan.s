# Handle-based enumeration for private package scans. No virtual descriptor or
# FindFirstFile state, fatal allocation, or later path lookup is involved.
.include "win.inc"
.equ WDS_CTX, 96
.equ WDS_NEXT, 128
.equ WDS_NAME_LEN, 136
.equ WDS_FIRST, 144
.equ WDS_RECORD, 152
.equ WDS_OWNS, 160
.equ WDS_BUFFER, 192
.equ WDS_NAME, WDS_BUFFER + 32768
.equ WDS_FRAME, WDS_NAME + 4096
.text
FN win_dir_scan_try
    PROLOGUE WDS_FRAME
    mov qword ptr [rsp + WDS_OWNS], 1
    mov [rsp + WDS_CTX + DSC_max], rsi
    mov qword ptr [rsp + WDS_CTX + DSC_count], 0
    mov [rsp + WDS_CTX + DSC_callback], rdx
    mov [rsp + WDS_CTX + DSC_user], rcx
    call win_file_path_try
    test rax, rax
    jz .Lwds_path_error
    mov r12, rax
    mov rcx, rax
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02200000
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lwds_open_error
    mov rbx, rax
.Lwds_classify:
    mov rcx, rbx
    API GetFileType
    test eax, eax
    jz .Lwds_native_error
    cmp eax, 1
    jne .Lwds_notdir
    lea r13, [rsp + WDS_BUFFER]
    mov rcx, rbx
    mov rdx, r13
    API GetFileInformationByHandle
    test eax, eax
    jz .Lwds_native_error
    test dword ptr [r13], 0x400
    jnz .Lwds_link
    test dword ptr [r13], 16
    jz .Lwds_notdir
    mov qword ptr [rsp + WDS_FIRST], 1
.Lwds_read:
    mov rcx, rbx
    mov edx, 14                 # FileFullDirectoryInfo
    cmp qword ptr [rsp + WDS_FIRST], 0
    je 1f
    mov edx, 15                 # FileFullDirectoryRestartInfo
1:  mov r8, r13
    mov r9d, 32768
    API GetFileInformationByHandleEx
    test eax, eax
    jz .Lwds_read_error
    mov qword ptr [rsp + WDS_FIRST], 0
    xor r14d, r14d
.Lwds_record:
    mov rax, 32768
    sub rax, r14
    cmp rax, 70                 # fixed fields plus one UTF-16 unit
    jb .Lwds_bad
    lea rsi, [r13 + r14]
    mov [rsp + WDS_RECORD], rsi
    mov r15d, [rsi + 60]        # counted UTF-16 filename, length in bytes
    test r15d, r15d
    jz .Lwds_bad
    test r15d, 1
    jnz .Lwds_bad
    lea rdx, [r15 + 68]
    cmp rdx, rax
    ja .Lwds_bad
    mov ecx, [rsi]
    mov [rsp + WDS_NEXT], rcx
    test ecx, ecx
    jz 2f
    test ecx, 7
    jnz .Lwds_bad
    cmp rcx, rdx
    jb .Lwds_bad
    sub rax, 70
    cmp rcx, rax
    ja .Lwds_bad
2:  mov ecx, 65001
    mov edx, 0x80               # WC_ERR_INVALID_CHARS
    lea r8, [rsi + 68]
    mov r9, r15
    shr r9, 1
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    test eax, eax
    jz .Lwds_encoding
    cmp eax, 4095
    ja .Lwds_long
    mov [rsp + WDS_NAME_LEN], rax
    mov ecx, 65001
    mov edx, 0x80
    mov r8, [rsp + WDS_RECORD]
    add r8, 68
    mov r9, r15
    shr r9, 1
    lea rax, [rsp + WDS_NAME]
    mov [rsp + 32], rax
    mov rax, [rsp + WDS_NAME_LEN]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    mov qword ptr [rsp + 56], 0
    API WideCharToMultiByte
    cmp rax, [rsp + WDS_NAME_LEN]
    jne .Lwds_encoding
    lea rsi, [rsp + WDS_NAME]
    mov byte ptr [rsi + rax], 0
    mov rdx, rax
    lea rdi, [rsp + WDS_CTX]
    call dir_scan_emit
    test rax, rax
    js .Lwds_close_result
    mov rax, [rsp + WDS_NEXT]
    test rax, rax
    jz .Lwds_read
    add r14, rax
    jmp .Lwds_record
.Lwds_read_error:
    API GetLastError
    cmp eax, 18                # ERROR_NO_MORE_FILES
    je .Lwds_done
    cmp eax, 2                 # Initial no-match (including empty volume root)
    jne .Lwds_native_error
    cmp qword ptr [rsp + WDS_FIRST], 1
    jne .Lwds_native_error
.Lwds_done:
    xor eax, eax
    jmp .Lwds_close_result
.Lwds_native_error:
    call win_error
    jmp .Lwds_close_result
.Lwds_notdir:
    mov rax, -20
    jmp .Lwds_close_result
.Lwds_link:
    mov rax, -40
    jmp .Lwds_close_result
.Lwds_bad:
    mov rax, -5
    jmp .Lwds_close_result
.Lwds_encoding:
    mov rax, -22
    jmp .Lwds_close_result
.Lwds_long:
    mov rax, -36
.Lwds_close_result:
    cmp qword ptr [rsp + WDS_OWNS], 0
    je .Lwds_borrowed_return
    mov r15, rax
    mov rcx, rbx
    API CloseHandle
    test eax, eax
    jnz .Lwds_free
    call win_error
    test r15, r15
    jnz .Lwds_free
    mov r15, rax
    jmp .Lwds_free
.Lwds_open_error:
    call win_error
    mov r15, rax
.Lwds_free:
    mov rdi, r12
    call mem_free
    mov rax, r15
    mov rdx, [rsp + WDS_CTX + DSC_count]
    EPILOGUE
.Lwds_path_error:
    mov rax, rdx
    xor edx, edx
    EPILOGUE

# win_dir_scan_handle_try(rawHandle,max,callback,user) -> status, callback count.
# Borrowed noninherited directory handle. Validate the opened object, restart its
# enumeration and leave ownership with caller on every result.
FN win_dir_scan_handle_try
    test rdi, rdi
    jz .Lwdh_invalid
    cmp rdi, -1
    je .Lwdh_invalid
    test rdx, rdx
    jz .Lwdh_invalid
    cmp rsi, DSC_CAP_MAX
    ja .Lwdh_invalid
    PROLOGUE WDS_FRAME
    mov qword ptr [rsp + WDS_OWNS], 0
    mov [rsp + WDS_CTX + DSC_max], rsi
    mov qword ptr [rsp + WDS_CTX + DSC_count], 0
    mov [rsp + WDS_CTX + DSC_callback], rdx
    mov [rsp + WDS_CTX + DSC_user], rcx
    mov rbx, rdi
    jmp .Lwds_classify
.Lwds_borrowed_return:
    mov rdx, [rsp + WDS_CTX + DSC_count]
    EPILOGUE
.Lwdh_invalid:
    mov rax, -22
    xor edx, edx
    ret
