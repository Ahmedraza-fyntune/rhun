.text
FN dst_open
    cmp qword ptr [rip + dst_mode], 10
    je 1f
    cmp qword ptr [rip + dst_mode], 38
    je 2f
    jmp [rip + __imp_CreateFileW]
1:  mov ecx, 5
    jmp dst_invalid_handle
2:  mov ecx, 2
    jmp dst_invalid_handle
dst_invalid_handle:
    PROLOGUE 96
    API SetLastError
    mov rax, -1
    EPILOGUE
FN dst_false
    PROLOGUE 96
    API SetLastError
    xor eax, eax
    EPILOGUE
FN dst_capture
    cmp rax, -1
    je 1f
    PROLOGUE 96
    mov rbx, rax
    mov [rip + dst_last_handle], rax
    mov rcx, rax
    lea rdx, [rsp + 64]
    API GetHandleInformation
    test eax, eax
    jz dst_fault_fail
    mov rax, rbx
    EPILOGUE
1:  ret
FN dst_handle_closed
    PROLOGUE 96
    mov rcx, [rip + dst_last_handle]
    test rcx, rcx
    jz 1f
    lea rdx, [rsp + 64]
    API GetHandleInformation
    test eax, eax
    jnz dst_fault_fail
    API GetLastError
    cmp eax, 6
    jne dst_fault_fail
1:  EPILOGUE
FN dst_type
    cmp qword ptr [rip + dst_mode], 30
    je 1f
    cmp qword ptr [rip + dst_mode], 32
    je 2f
    jmp [rip + __imp_GetFileType]
1:  mov ecx, 31
    jmp dst_false
2:  mov eax, 2
    ret
FN dst_info
    cmp qword ptr [rip + dst_mode], 31
    je 1f
    cmp qword ptr [rip + dst_mode], 33
    je 2f
    cmp qword ptr [rip + dst_mode], 34
    je 3f
    jmp [rip + __imp_GetFileInformationByHandle]
1:  mov ecx, 31
    jmp dst_false
2:  mov dword ptr [rdx], 0
    mov eax, 1
    ret
3:  mov dword ptr [rdx], 0x410
    mov eax, 1
    ret
FN dst_path
    cmp qword ptr [rip + dst_mode], 39
    jne win_file_path_try
    xor eax, eax
    mov rdx, -12
    ret
FN dst_close
    cmp rcx, [rip + dst_last_handle]
    jne dst_fault_fail
    PROLOGUE 96
    API CloseHandle
    test eax, eax
    jz dst_fault_fail
    mov rax, [rip + dst_mode]
    cmp rax, 13
    je 1f
    cmp rax, 14
    je 1f
    cmp rax, 16
    je 1f
    cmp rax, 17
    je 1f
    cmp rax, 36
    je 1f
    mov eax, 1
    EPILOGUE
1:  mov ecx, 31
    API SetLastError
    xor eax, eax
    EPILOGUE
FN dst_read
    cmp rcx, [rip + dst_last_handle]
    jne dst_fault_fail
    cmp r9d, 32768
    jne dst_fault_fail
    test r8, 7
    jnz dst_fault_fail
    cmp qword ptr [rip + dst_native_reads], 0
    jne 99f
    cmp edx, 15
    jne dst_fault_fail
    jmp 98f
99: cmp edx, 14
    jne dst_fault_fail
98: inc qword ptr [rip + dst_native_reads]
    mov rax, [rip + dst_mode]
    cmp rax, 11
    je .Ldst_eio
    cmp rax, 14
    je .Ldst_eacces
    cmp rax, 35
    je .Ldst_noent
    cmp rax, 36
    je .Ldst_noent
    cmp rax, 37
    je .Ldst_batch
    cmp rax, 12
    je .Ldst_batch
    cmp rax, 20
    jb .Ldst_real
    cmp rax, 29
    ja .Ldst_real
.Ldst_batch:
    cmp qword ptr [rip + dst_native_reads], 1
    je 1f
    cmp rax, 37
    je .Ldst_noent
    cmp rax, 12
    je .Ldst_eio
    mov ecx, 18
    jmp dst_false
1:  cmp edx, 15
    jne dst_fault_fail
    mov dword ptr [r8], 0
    mov dword ptr [r8 + 60], 2
    mov word ptr [r8 + 68], 'a'
    cmp rax, 20
    jne 2f
    mov dword ptr [r8 + 60], 0
2:  cmp rax, 21
    jne 3f
    mov dword ptr [r8 + 60], 1
3:  cmp rax, 22
    jne 4f
    mov dword ptr [r8 + 60], 32702
4:  cmp rax, 23
    jne 5f
    mov dword ptr [r8], 71
5:  cmp rax, 24
    jne 6f
    mov dword ptr [r8], 64
6:  cmp rax, 25
    jne 7f
    mov dword ptr [r8], 32768
7:  cmp rax, 26
    jne 8f
    mov word ptr [r8 + 68], 0xd800
8:  cmp rax, 27
    jne 9f
    mov word ptr [r8 + 68], 0
9:  cmp rax, 28
    jne 10f
    mov word ptr [r8 + 68], '/'
10: cmp rax, 29
    jne 12f
    mov dword ptr [r8 + 60], 8192
    xor ecx, ecx
11: mov word ptr [r8 + rcx*2 + 68], 'a'
    inc ecx
    cmp ecx, 4096
    jb 11b
12: mov eax, 1
    ret
.Ldst_eacces:
    mov ecx, 5
    jmp dst_false
.Ldst_eio:
    mov ecx, 31
    jmp dst_false
.Ldst_noent:
    mov ecx, 2
    jmp dst_false
.Ldst_real:
    jmp [rip + __imp_GetFileInformationByHandleEx]
dst_fault_fail:
    mov edi, 102
    call sys_exit
