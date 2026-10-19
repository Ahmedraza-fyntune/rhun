.include "win.inc"
.include "app/taskproc.inc"
.bss
kcw_calls: .quad 0
kcw_slot: .quad 0
kcw_owned: .quad 0
kcw_base: .quad 0
kcw_text: .zero 35001
.text
FN win_fd_alloc
.if KCW_CASE == 0
    mov rax, -24
    ret
.else
    PROLOGUE
    call kcw_real_fd_alloc
    mov [rip + kcw_slot], r8
    EPILOGUE
.endif
FN kcw_create
    inc qword ptr [rip + kcw_calls]
    PROLOGUE 96
    mov ecx, 5
    API SetLastError
    mov rax, -1
    EPILOGUE
FN kcw_convert_fail
    PROLOGUE 96
    mov ecx, 87
    API SetLastError
    xor eax, eax
    EPILOGUE
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + kcw_base], rax
.if KCW_CASE == 3
    lea rdi, [rip + kcw_text]
    mov esi, 97
    mov edx, 35000
    call memset
    lea rdi, [rip + kcw_text]
    mov esi, 65536
    lea rdx, [rip + kcw_owned]
    call kcw_wide
    cmp rax, -5
    jne 9f
    mov rdi, [rip + kcw_owned]
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi - 16], 64
    jb 9f
    call prep_cleanup_free
    test rax, rax
    jnz 9f
    cmp rdx, 1
    jne 9f
.else
    call kcw_null
.if KCW_CASE == 0
    cmp rax, -24
    jne 9f
    cmp qword ptr [rip + kcw_calls], 0
    jne 9f
.else
.if KCW_CASE == 1
    cmp rax, -13
    jne 9f
    cmp qword ptr [rip + kcw_calls], 1
    jne 9f
.else
    test rax, rax
    js 9f
    mov rdi, rax
    call ext_fd_close_checked
    test rax, rax
    jnz 9f
    cmp rdx, 1
    jne 9f
.endif
    mov rax, [rip + kcw_slot]
    test rax, rax
    jz 9f
    cmp dword ptr [rax + FD_kind], 0
    jne 9f
.endif
.endif
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + kcw_base]
    jne 9f
    xor eax, eax
    EPILOGUE
9:  mov edi, 73
    call sys_exit
