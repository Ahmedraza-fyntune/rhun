# Binary fixture: [u32 name length, raw name]*, then u32(-1), i64 status,
# u64 callback count, u64 nested callback count. Only the last repetition emits.
.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.section .rodata
dst_bad_utf8: .byte 0xc0,0xaf,0
.bss
.p2align 3
.globl dst_mode, dst_native_reads, dst_last_handle
dst_mode: .quad 0
dst_native_reads: .quad 0
dst_last_handle: .quad 0
dst_count: .quad 0
dst_nested_count: .quad 0
dst_nested_path: .quad 0
dst_did_dive: .quad 0
dst_mute: .quad 0
dst_count_scratch: .quad 0
dst_long_path: .zero 4097
.text
dst_fail:
    mov edi, 101
    call sys_exit
dst_zero:
    test rax, rax
    jnz dst_fail
    ret
dst_number:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov rsi, rax
    mov rdi, rbx
    call parse_u64
    cmp rdx, rsi
    jne dst_fail
    EPILOGUE
dst_nested_callback:
    inc qword ptr [rdi]
    xor eax, eax
    ret
dst_recurse:
    PROLOGUE 4112
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp + 16]
    mov rsi, rbx
    lea rdx, [r12 + 1]
    call memcpy
    mov rdi, [rip + dst_nested_path]
    test rdi, rdi
    jz dst_fail
    mov esi, DSC_CAP_MAX
    lea rdx, [rip + dst_nested_callback]
    lea rcx, [rip + dst_nested_count]
    call dir_scan_try
    call dst_zero
    cmp rdx, [rip + dst_nested_count]
    jne dst_fail
    mov rdi, rbx
    lea rsi, [rsp + 16]
    lea rdx, [r12 + 1]
    call memeq
    cmp eax, 1
    jne dst_fail
    xor eax, eax
    EPILOGUE
dst_callback:
    cmp rdi, 0x12345678
    jne dst_fail
    PROLOGUE 16
    mov rbx, rsi
    mov r12, rdx
    inc qword ptr [rip + dst_count]
    cmp qword ptr [rip + dst_mode], 3
    jne 1f
    cmp qword ptr [rip + dst_did_dive], 0
    jne 1f
    mov qword ptr [rip + dst_did_dive], 1
    mov rdi, rbx
    mov rsi, r12
    call dst_recurse
1:  cmp qword ptr [rip + dst_mute], 0
    jne 2f
    mov [rsp], r12d
    mov edi, 1
    mov rsi, rsp
    mov edx, 4
    call write_all
    call dst_zero
    mov edi, 1
    mov rsi, rbx
    mov rdx, r12
    call write_all
    call dst_zero
2:  mov rax, [rip + dst_mode]
    cmp rax, 9
    je 21f
    cmp rax, 16
    je 21f
    cmp rax, 1
    jne 3f
21:
    mov rax, -125
    EPILOGUE
3:  cmp rax, 18
    je 31f
    cmp rax, 17
    je 31f
    cmp rax, 2
31: sete al
    movzx eax, al
    EPILOGUE

# Explicitly prove borrowed enumeration leaves the actual descriptor/handle live
# on success, overflow and callback failure. Caller then closes it exactly once.
dst_borrowed:
    PROLOGUE 192
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
.ifdef WINDOWS
    call win_file_path_try
    test rax, rax
    jz dst_fail
    mov r15, rax
    mov rcx, rax
    mov edx, 0x80000000
    mov r8d, 7
    xor r9d, r9d
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x02200000
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je dst_fail
.else
    mov esi, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js dst_fail
.endif
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
.ifdef WINDOWS
    call win_dir_scan_handle_try
.else
    call dir_scan_fd_try
.endif
    mov r13, rax
    mov r14, rdx
.ifdef WINDOWS
    mov rcx, rbx
    lea rdx, [rsp + 128]
    API GetHandleInformation
    test eax, eax
    jz dst_fail
    mov rcx, rbx
    API CloseHandle
    test eax, eax
    jz dst_fail
    mov rdi, r15
    call mem_free
.else
    mov edi, ebx
    lea rsi, [rsp + 32]
    SYS SYS_fstat
    call dst_zero
    mov edi, ebx
    SYS SYS_close
    call dst_zero
.endif
    mov rax, r13
    mov rdx, r14
    EPILOGUE

FN main
    PROLOGUE 64
    cmp qword ptr [rip + g_argc], 4
    jb dst_fail
    mov r14, [rip + g_argv]
    mov rax, [r14 + 8]
    mov [rsp], rax
    mov rdi, [r14 + 16]
    call dst_number
    mov r12, rax
    mov rdi, [r14 + 24]
    call dst_number
    mov [rip + dst_mode], rax
    mov ebx, 1
    cmp qword ptr [rip + g_argc], 5
    jb 1f
    mov rdi, [r14 + 32]
    call dst_number
    test rax, rax
    jz dst_fail
    cmp rax, 128
    ja dst_fail
    mov rbx, rax
1:  cmp qword ptr [rip + g_argc], 6
    jb 2f
    mov rax, [r14 + 40]
    mov [rip + dst_nested_path], rax
2:  cmp qword ptr [rip + dst_mode], 6
    jne 3f
    lea rdi, [rip + dst_long_path]
    mov esi, 'a'
    mov edx, 4096
    call memset
3:  mov r15, [rip + g_mem_live]
.Ldst_repeat:
    mov qword ptr [rip + dst_count], 0
    mov qword ptr [rip + dst_nested_count], 0
    mov qword ptr [rip + dst_did_dive], 0
    mov qword ptr [rip + dst_native_reads], 0
    mov qword ptr [rip + dst_last_handle], 0
    mov qword ptr [rip + dst_mute], 1
    cmp rbx, 1
    jne 4f
    mov qword ptr [rip + dst_mute], 0
4:  mov rdi, [rsp]
    mov rsi, r12
    lea rdx, [rip + dst_callback]
    mov ecx, 0x12345678
    cmp qword ptr [rip + dst_mode], 4
    jne 41f
    xor edi, edi
41: cmp qword ptr [rip + dst_mode], 5
    jne 42f
    xor edx, edx
42: cmp qword ptr [rip + dst_mode], 6
    jne 43f
    lea rdi, [rip + dst_long_path]
43: cmp qword ptr [rip + dst_mode], 7
    jne 44f
    lea rdi, [rip + dst_bad_utf8]
44: cmp qword ptr [rip + dst_mode], 8
    je 441f
    cmp qword ptr [rip + dst_mode], 9
    je 441f
    cmp qword ptr [rip + dst_mode], 18
    jne 442f
441:call dst_borrowed
    jmp 443f
442:call dir_scan_try
443:
    mov r14, rax
    mov r13, rdx
    cmp rdx, [rip + dst_count]
    jne dst_fail
    cmp r15, [rip + g_mem_live]
    jne dst_fail
.ifdef WINDOWS
.ifdef TEST_DIR_SCAN_FAULT
    call dst_handle_closed
.endif
.endif
    dec rbx
    jnz .Ldst_repeat
    cmp qword ptr [rip + dst_mode], 10
    jb 5f
    # Restore real APIs and retry in this process after native fault groups.
    mov qword ptr [rip + dst_mode], 0
    mov qword ptr [rip + dst_native_reads], 0
    mov qword ptr [rip + dst_last_handle], 0
    mov qword ptr [rip + dst_count], 0
    mov qword ptr [rip + dst_mute], 1
    mov rdi, [rsp]
    mov esi, DSC_CAP_MAX
    lea rdx, [rip + dst_callback]
    mov ecx, 0x12345678
    call dir_scan_try
    call dst_zero
    cmp rdx, [rip + dst_count]
    jne dst_fail
    cmp r15, [rip + g_mem_live]
    jne dst_fail
.ifdef WINDOWS
.ifdef TEST_DIR_SCAN_FAULT
    call dst_handle_closed
.endif
.endif
5:  mov dword ptr [rsp + 16], -1
    mov [rsp + 20], r14
    mov [rsp + 28], r13
    mov rax, [rip + dst_nested_count]
    mov [rsp + 36], rax
    mov edi, 1
    lea rsi, [rsp + 16]
    mov edx, 28
    call write_all
    call dst_zero
    xor eax, eax
    EPILOGUE
